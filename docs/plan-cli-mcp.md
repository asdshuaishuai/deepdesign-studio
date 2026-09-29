# 1.0 规划：deepDesign Agent CLI + MCP 出口

> 状态：**仅规划，未实施**。目标版本：1.0（dev 分支跟进）。
> 一句话：把 deepDesign 内部的 Agent 能力（agent.rs 循环 + 引擎双门 + DDP 容器）抽象成
> **deepDesign 专属的 CLI 与 MCP Server**，让 Codex / Claude Code 这类外部 Agent 能直接驱动
> deepDesign——不用打开桌面应用。
> 事实核查日期：2026-09-29；写实现代码前先复核引擎版本与 SKILL.md 是否漂移。

## 1. 为什么做，差异化在哪

引擎（MoonViz）已经有 CLI 和 MCP（`moon run --target native mcp`，47 工具面），那为什么还要做？
因为**引擎出口是"裸引擎"，不是 deepDesign**——它没有我们壳层的核心增值：

| 能力 | 引擎裸 CLI/MCP | deepDesign 出口（本规划） |
|------|----------------|--------------------------|
| 单 op 过门校验 | ✅ | ✅（同一 wasm，逐字节一致） |
| **完整 Agent 循环**（多步规划、澄清、收尾三段审查） | ❌ 调用方自己循环 | ✅ `agent.run` 一步到位 |
| **LLM 接入**（13 家预设、双协议、thinking 方言表、上下文三层裁剪） | ❌ 无 LLM | ✅ 复用 agent.rs 全部基座 |
| **DDP 加密容器**（打开/保存/免密 DDP2） | ❌ 只认明文 .mbt.md | ✅ 一等公民 |
| **种子引导**（空项目起步）、**rebase**（人类编辑后重放） | ❌ | ✅ |
| 模型元数据快照 / SSRF 防护 / 上下文预算 | ❌ | ✅ |

一句话定位：**引擎 CLI/MCP 服务于"会写 MoonBit/会自己循环"的集成方；deepDesign 出口服务于
"只想让 Codex/Claude Code 帮忙画原型"的人**。两者不冲突，后者是前者的"整车出厂"形态。

## 2. 核心架构判断：在引擎基础上做，还是包 agent.rs？

**结论：壳层出口（wrap agent.rs + EngineHost），不在引擎仓库做。**

- agent.rs 的 `run()` 已经是完整循环：规划 → 工具调用（`EngineHost::call` 直调 wasm）→
  澄清 → 三段收尾审查 → 返回 `{ok, mbt_b64, render, ops[], stopReason, text}` 契约。
  这个循环直接复用，CLI/MCP 只是换一个"入口 + 出口"：
  - 入口：stdin/参数/MCP tool call 代替 Tauri invoke；
  - 出口：stdout JSON / MCP response 代替 `app.emit` + 前端回灌。
- 引擎仓库不动（只读纪律）。引擎 wasm 经 `include_bytes!` 已嵌入 Rust，二进制天然自包含。
- 架构上前置一步拆分：把 `agent.rs` + `wasmtime_host.rs` + DDP codec 下沉为 `deepdesign-core`
  crate（lib），Tauri 壳与 CLI/MCP 二进制都依赖它。这与鸿蒙方案（docs/harmonyos-port.md）的
  L1 拆分是**同一个前置**——一次拆分，三端复用（桌面 / 鸿蒙 / CLI+MCP）。

```
deepdesign-core (lib crate)
  ├─ EngineHost（wasmtime 宿主，mbt 键控会话缓存）
  ├─ agent::run()（循环 + 收尾审查 + 上下文裁剪）
  ├─ ddp（加解密）+ models（快照）+ thinking 方言表
  └─ Session 抽象（见 §4：进程内会话表，取代"一次 invoke 一次生命周期"）
binaries
  ├─ deepdesign-studio（Tauri 壳，现状不变）
  ├─ ddesign-cli（新：stdin/stdout 行协议 + 子命令）
  └─ ddesign-mcp（新：MCP stdio server，官方 rust-sdk）
```

## 3. CLI 面（`ddesign`）

设计原则：**文件进、文件出，全程无 UI**；与桌面应用共享同一套门与契约。

```bash
# 一次性生成（无状态，最常用）
ddesign run --prompt "做一个活动页，要有倒计时和报名表单" \
  [--in project.ddp | --in source.mbt.md] \
  [--out out.ddp | --out out.mbt.md] [--export svg,html] \
  [--api-key sk-.. | --env] [--provider glm] [--model glm-5.3] [--thinking high]
  [--max-steps 40] [--json]     # --json 输出完整 run 契约（脚本消费）

# 交互式会话（有状态，模拟桌面内的多轮）
ddesign session start project.ddp     # → session id；后续 add/ask 在同一文档上推进
ddesign session <id> ask "把标题改成蓝色"
ddesign session <id> export --out out.ddp
ddesign session <id> close

# 直连引擎（高级：给已会写 op 的外部 agent 用，不经 LLM）
ddesign op apply-agent "<op line>" --in src.mbt.md --out dst.mbt.md
ddesign op read <readonly-op> --in src.mbt.md     # lint/query/missing/export-svg...

# 辅助
ddesign providers        # 13 家预设清单 + 当前配置
ddesign doctor           # wasm 契约自检（复用 sync-engine 探针逻辑）
```

关键语义：
- **进出都是文件**：`.ddp`（加密，带口令 `--password` / `DDPASSWORD` 环境变量 / 免密 DDP2）
  或明文 `.mbt.md`。CLI 不碰剪贴板、不弹窗。
- `run` = agent.rs `run()` 的直通：stopReason=text 时原样输出（澄清问题），调用方回答后
  `--follow-up "回答"` 续跑（复用前端 clarify-first 的拼接语义）。
- **进度到 stderr**：`tool_start/tool_end/preview` 事件行打 stderr（人看轨迹），
  stdout 只出最终契约（机器消费）——和引擎 CLI 的 stdin/stdout 行协议同风格。
- 空项目起步自动走 `seed_doc`（与桌面/`agent.rs` 逐字对齐），首 op 后删 `__seed`。

## 4. MCP 面（`ddesign-mcp`）

stdio 传输，注册进 Codex / Claude Code / Cursor 等宿主的 mcpServers 即用：

```json
{ "mcpServers": { "deepdesign": { "command": "ddesign-mcp",
    "env": { "DD_API_KEY": "...", "DD_PROVIDER": "glm" } } } }
```

工具面刻意**小而厚**（不是引擎 47 工具的镜像——那是引擎 MCP 的职责）：

| 工具 | 语义 | 底层 |
|------|------|------|
| `design_run` | 一次性生成/修改原型（prompt + 可选项目文件 → 新文档 + 摘要） | agent::run() |
| `design_status` | 只读检视当前文档（lint/missing/结构摘要） | readonly 路由 |
| `design_export` | 导出 svg/html/mbt.md | export 路由 |
| `design_op` | 单 op 高级直连（外部 agent 自己规划时用） | session_apply_agent |
| `design_session` | 打开/关闭持久会话（跨 tool call 保住文档状态） | 会话表 |

- **状态模型**：MCP tool call 之间靠 `session_id` 保持文档（进程内会话表 + mbt 键控复用
  EngineHost 会话，与桌面同机制）。不引入会话 = 每次调用独立（幂等，宿主崩溃无损）。
- **返回即契约**：`design_run` 返回 `{ok, summary, text(澄清问题), artifacts[], ops[]}`；
  澄清语义同 CLI——外部 agent 读到 `stopReason=text` 就该向它的用户转问再续调。
- **安全**：`safe_base_url` 的 SSRF 策略照搬；api key 只从 env 读，不落盘、不进日志。
- 事实源纪律：工具 schema 手写但以 `list-tools`/`list-ops` 探针锚定漂移
  （复用 sync-engine 探针模式，引擎更新即红）。

## 5. 与桌面应用的关系

- **同一核心，两种入口**：桌面 = 有画布的实时协同；CLI/MCP = 无头批处理/外部 agent 驱动。
  事实源（canonical .mbt.md + .ddp）完全同构，桌面打开 CLI 产出的 .ddp 无损。
- **并发边界（明确 v1 不做）**：同项目跨入口并发编辑无锁，后保存者覆盖（与桌面多窗口
  同一既有边界，文档里写清楚即可）。文件锁（flock 语义）列为 1.0+ 可选增强。
- **分发**：CLI/MCP 二进制随 Releases 一起发（同一 tag）；`brew install` / `scoop` / npm
  wrapper（`npx ddesign` 下载二进制）属分发增强项，不阻塞 1.0。

## 6. 阶段计划

| 阶段 | 内容 | 出口判据 | 预估 |
|------|------|----------|------|
| P0 core 拆分 | agent.rs+wasmtime_host.rs+ddp 下沉 `deepdesign-core`；Tauri 壳改依赖 | cargo test 43 项全绿、桌面零行为变化 | 1–2 周 |
| P1 CLI | `ddesign run/session/op` + 行协议 + stderr 事件流 | mock-LLM e2e：prompt→.ddp→桌面打开无损 | 1–2 周 |
| P2 MCP | rust-sdk stdio server + 5 工具 + 会话表 | Claude Code / Codex 实机各完成一次完整 run | 1–2 周 |
| P3 契约与分发 | 探针锚定 + Releases 出二进制 + 文档 | 引擎更新时探针红；双平台产物在 Release | 1 周 |

测试策略：core 契约测试平移；CLI 用行协议 e2e（mock LLM，复用 `spawn_mock_llm`）；
MCP 用官方 conformance + 实机双宿主冒烟。

## 7. 明确不做（v1 非目标）

- 不做 GUI 替代、不做 watch 模式热更新
- 不镜像引擎 47 工具全量 MCP 面（那是引擎 MCP 的既有职责，避免双事实源）
- 不做远程/HTTP 传输（stdio 够用；streamable-http 待生态明确需要再说）
- 不做多项目编排（一次一个项目文件，与桌面 agentBusy 门同语义）

## 8. 风险与开放问题

1. **`run()` 与 Tauri 的耦合度**：progress 回调、emit、窗口句柄需在 P0 梳理成 trait 注入，
   CLI/MCP 提供各自实现（stderr 行 / MCP notification）。这是 P0 唯一的"改造"而非"搬迁"。
2. **长时间 run 与 MCP 超时**：宿主可能中断长调用——契约里 `ops[]` 已含已提交工作，
   中断不丢（与 mid_run_llm_failure_preserves_committed_work 同语义），文档需教调用方重试策略。
3. **api key 配置面**：env 优先 → `~/.ddesign/config.toml` 次之（0600），与桌面 localStorage
   互不读取（明确边界，避免双写漂移）。
4. **命名**：二进制名 `ddesign` / `ddesign-mcp` 避免与引擎 `moonviz` CLI 混淆；包名待定。
