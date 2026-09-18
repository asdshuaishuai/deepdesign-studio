# deepDesign Studio

AI 原生原型设计工具的桌面客户端（Tauri 2）。基于 [MoonViz](https://github.com/asdshuaishuai/moonviz) 纯 MoonBit 引擎：唯一事实源是 `.mbt.md` 文档，人类画布操作与 Agent 修改都必须经引擎校验（HumanGate / AgentGate）后回写同一文档。

## 架构

```
前端 (frontend/index.html, 纯静态)
  ├─ 多画板画布 / 组件库 / decl 源码视图 / 演示模式
  ├─ 内嵌标准 wasm 引擎（WebView 内进程执行）
  └─ 全部经 Tauri invoke（无应用后端 HTTP 层）
Rust 后端 (src-tauri)
  ├─ engine 事件桥 — agent 循环经结构化事件驱动前端 wasm
  ├─ agent   — 进程内 Agent 循环（OpenAI / Anthropic 双协议工具调用）
  └─ save_ddp/open_ddp — DDP 加密容器读写（vendored codec）
引擎 (frontend/vendor/moonviz.wasm, 标准产物)
  └─ GitHub Releases 的 classic wasm（纯 WASM MVP、宿主中立、零 import）
     字符串经宿主线性内存编解码；session API 覆盖检视命令
```

Agent 基座为 Rust 进程内实现（`src-tauri/src/agent.rs`）——无 JS 运行时、无子进程桥。
LLM 走任意 OpenAI 兼容或 Anthropic 兼容端点（MiniMax 双协议支持），内置 13 个服务商预设，
思考等级按各家官方方言模型感知降级；模型元数据由 models.dev 裁剪快照供给并契约锁定。

## 开发

```bash
node scripts/sync-engine.mjs   # 拉取标准 wasm 引擎产物（首次必跑）
./dev.sh                       # debug 编译并启动
```

前置：Rust + Tauri CLI + Node（构建期脚本与测试宿主）。仓库自包含——引擎是预编译
wasm 产物、DDP codec 已 vendored，clone 后两步即可构建，无需 MoonBit 工具链或引擎源码。

## 测试

```bash
cd src-tauri && cargo test    # 22 个测试（含 4 个 mock-LLM × 真 wasm 端到端）
node test_studio.cjs          # 前端状态机冒烟 + wasm 产物契约
```

引擎门测试：wasm 产物缺失时合法跳过；产物在场但宿主/编解码损坏时必须失败。

## 打包产物

- macOS：`.app` / `.dmg`；Windows：NSIS 安装包（GitHub Actions，`.github/workflows/windows-build.yml`）

更多：[AGENTS.md](AGENTS.md)（仓库指令与对账流程）、[SKILL.md](SKILL.md)（引擎能力字典）、
[docs/menus.md](docs/menus.md)（菜单映射）。
