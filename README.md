# deepDesign Studio

AI 原生原型设计工具的桌面客户端（Tauri 2）。基于 [MoonViz](https://github.com/asdshuaishuai/moonviz) 纯 MoonBit 引擎：唯一事实源是 `.mbt.md` 文档，人类画布操作与 Agent 修改都必须经引擎校验（HumanGate / AgentGate）后回写同一文档。

**当前版本 v0.3.0** — [官网](https://asdshuaishuai.github.io/deepdesign-studio/) · [下载（GitHub Releases）](https://github.com/asdshuaishuai/deepdesign-studio/releases/latest) · [引擎官网](https://asdshuaishuai.github.io/moonviz/) · [生态官网](https://asdshuaishuai.github.io/deeporca-site/)

## 特性

- **进程内 Agent**：Rust Agent 循环 × wasmtime 宿主——无 JS 运行时、无子进程桥。OpenAI / Anthropic 双协议，thinking 等级按 8 家厂商方言下发，13 个服务商预设（models.dev 快照本地化，离线可用）。
- **收尾审查层**：主实现完成后自动进入三段审查——需求完整度、操作逻辑连线、综合修复——审查发现问题直接补齐，产出即验收。
- **同步渲染预览**：Agent 执行过程画布实时可见（节流预览，不污染文档状态），设计一步步长出来而非黑盒等待。
- **多项目 · 多窗口**：最近项目下拉热切换；每个项目可开独立系统窗口并行编辑，未保存更改按窗口保护；画板拖拽移动自由排布。
- **演示模式 + 手绘批注**：底部操作栏导航、一键隐藏热区成真实成品观感、漏接交互的返回钮强制可点；✏ 全画板手绘批注持久化在 DDP 内，重新打开自动重放、可修改。
- **上下文管理**：Agent 历史三层裁剪（工具结果整形 / 同源去重 / 按模型窗口预算），多页长任务成本可控。
- **DDP 加密分发**：Argon2id + XChaCha20（或免密 DDP2），与 [ddpView](https://github.com/asdshuaishuai/ddpView-mac) 只读查看器回路一致。

## 架构

```
前端 (frontend/index.html, 纯静态)
  ├─ 多画板画布 / 组件库 / decl 源码视图 / 演示模式 + 手绘批注
  ├─ 内嵌标准 wasm 引擎（WebView 内进程执行）
  └─ 全部经 Tauri invoke（无应用后端 HTTP 层）
Rust 后端 (src-tauri)
  ├─ wasmtime_host — 引擎进程内宿主（_in 字节契约写路径；agent 循环与测试共用）
  ├─ agent   — 进程内 Agent 循环（OpenAI / Anthropic 双协议）+ 收尾审查层
  └─ save_ddp/open_ddp — DDP 加密容器读写（vendored codec）
引擎 (frontend/vendor/moonviz.wasm, 标准产物)
  └─ GitHub Releases 的 classic wasm（纯 WASM MVP、宿主中立、零 import）
     返回值经线性内存读解码，输入走 _in 字节契约面；session API 覆盖检视命令
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
cd src-tauri && cargo test    # 42 个测试（含 mock-LLM × 真 wasm 端到端、审查层契约）
node test_studio.cjs          # 前端状态机冒烟 + wasm 产物契约
```

引擎门测试：wasm 产物缺失时合法跳过；产物在场但宿主/编解码损坏时必须失败。

## 打包产物

- macOS：`.app` / `.dmg`；Windows：NSIS 安装包（GitHub Actions，打 tag `v*` 触发）
- 发布产物见 [Releases](https://github.com/asdshuaishuai/deepdesign-studio/releases/latest)

## 开源感谢

感谢 **[MoonViz](https://github.com/asdshuaishuai/moonviz)** 引擎——100% MoonBit
编写的原型设计引擎：`.mbt.md` 唯一事实源、HumanGate / AgentGate 双门、47 个 Agent 工具、
六条集成路线（CLI / MCP / Node SDK / WASM SDK / SKILL / DDP）。标准 classic WASM 产物让同一份
引擎在 WebView 画布与 wasmtime 宿主中逐字节一致地运行——没有它就没有 deepDesign。MIT 开源。

同时感谢：[Tauri 2](https://tauri.app)（桌面壳）、[wasmtime](https://wasmtime.dev)
（Bytecode Alliance，进程内 WASM 运行时）、[MoonBit](https://www.moonbitlang.com)（引擎语言）、
tokio · reqwest · serde（Rust 基座）、RustCrypto `argon2` / `chacha20poly1305`（DDP 加密）、
[async-openai](https://github.com/64bit/async-openai)（chat 类型层）、
[models.dev](https://models.dev)（模型元数据快照）。

更多：[AGENTS.md](AGENTS.md)（仓库指令与对账流程）、[SKILL.md](SKILL.md)（引擎能力字典）、
[docs/menus.md](docs/menus.md)（菜单映射）。
