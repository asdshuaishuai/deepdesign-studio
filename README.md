# deepDesign Studio

> AI 时代的原型设计引擎 + 桌面工作室。**deepcode-cli 衍生项目**。

```
deepcode-cli ──衍生──> deepDesign Studio
                       ├─ deepDesign Engine（../moonviz/，100% MoonBit）
                       └─ deepDesign 桌面外壳（Tauri 2 + 零 npm 前端）
```

## 架构

```
┌────────────────────────────────────────────┐
│  前端 frontend/index.html（纯静态，零 npm）  │
│  悬浮追踪 Agent · 播放模式 · 四主题          │
│  (Neumorphism/Glass/Aero/Flat)              │
└──────────────┬─────────────────────────────┘
               │ Tauri invoke / HTTP 双模式
┌──────────────▼─────────────────────────────┐
│  Rust 外壳 src-tauri/                       │
│  exec_cli · 加密 DDP 字节读写 · 诊断          │
└──────────────┬─────────────────────────────┘
               │ stdin/stdout JSON 行协议
┌──────────────▼─────────────────────────────┐
│  deepDesign Engine（moonviz/，纯 MoonBit）   │
│  场景图 · 布局求解 · 约束系统 · 组件×52      │
│  渐变/旋转/模糊 · 交互运行时 · 持久化        │
└────────────────────────────────────────────┘
```

## 唯一事实源与 DDP

**一份完整的 MoonBit `.mbt.md` 是项目唯一事实源。** 人类拖拽、Agent 指令和模板/组件创建都会先成为引擎操作，再写回 canonical `.mbt.md`；随后引擎重新扫描、解析、求解、校验并生成 Studio 画布。`Project`、SVG、RenderPlan 和前端状态都只是派生缓存。

`.ddp` 不是 ZIP、manifest 或 HTML 包。它是单一完整 `.mbt.md` 的加密压缩表示。引擎目录 `../moonviz/ddp/` 提供独立 Rust crate `moonviz-ddp` 和无 Tauri 依赖的 `ddp_codec` 工具，统一执行 Argon2id + XChaCha20-Poly1305 和有界 zstd 解压；Studio Rust 壳通过 path dependency 调用，只负责文件对话框和呈现。解密后的 MBT 仍必须由 Moonviz 引擎校验和渲染。密码不会写入项目状态、浏览器存储或日志。

MoonBit 的 `mbt` / `mbt check` / `mbt nocheck` / `moonbit` fence 语义保留不变。Moonviz 只渲染显式 `<!-- moonviz:artboard <id> -->` 后的 `mbt` 视觉声明块；`mbt check` 只作 MoonBit 文档测试。

## Studio Agent 基座

Studio 使用用户指定的 **Vercel `fx` Agent** 作为 Agent 基座，接入方式为官方 Node SDK **libfx**（`agent/` 目录，`npm install libfx`）：

```text
Studio 前端
  → POST /api/fx/agent（浏览器模式）
  → agent/fx-agent.mjs（libfx createFxAgent 嵌入）
  → fx 通过 moonviz_op / read_mbt / list_components 工具提案
  → 每次工具调用 = MoonViz apply-agent-mbt-op-b64（AgentGate 严格校验）
  → canonical `.mbt.md` 写回并重新渲染
```

要点：

- fx 在桥内以工具调用方式提案，**不能直接编辑 MBT 文本**；每次 `moonviz_op` 都经 MoonViz AgentGate 校验并提交。
- 结构违规的操作会被引擎拒绝并作为错误回灌给 fx 重试；桥进入前先由引擎预验 MBT（`mbt_invalid`）。
- 认证使用 AI Gateway API Key（设置面板本地保存或环境变量 `AI_GATEWAY_API_KEY`），密钥不写入 DDP/MBT/日志；网关拒绝映射为 `fx_auth_refused`。
- 兼容回退：`fx CLI（fx ask）` 与离线 `Studio Agent Shim` 两种基座保留在设置中。
- 无密钥/无效 MBT/桥缺失均为结构化错误，不会静默假装生成成功。
- `ddpView` 完全独立：不加载 libfx、不调用 fx、不读取 Studio 配置。

## 快速启动

### 前置依赖

| 依赖 | 安装 | 用途 |
|------|------|------|
| MoonBit 工具链（`moon`） | [moonbitlang.com](https://www.moonbitlang.com/download/) | 引擎编译与运行（必需） |
| Rust（`cargo`） | [rustup.rs](https://rustup.rs) | DDP codec、桌面壳 |
| Python 3 | 系统 | 浏览器模式服务器 / ddpView |
| Node.js ≥ 18 | 系统 | 桌面模式 fx Agent 桥、测试 |

> `moon` 必须在启动应用的 shell 的 `PATH` 中（桌面壳靠它调起引擎 CLI）。

### 方式一：桌面模式 · 编译运行（推荐）

```bash
cd moonviz-demo-tauri/src-tauri
cargo build                       # 首次约 1-2 分钟；增量编译秒级
./target/debug/deepdesign-studio  # 编译产物直接运行，无需打包
```

`cargo build` 产出可执行文件 `target/debug/deepdesign-studio`，直接运行即是完整桌面应用。
桌面模式独有：macOS 原生菜单栏（文件/编辑/视图/画板/帮助，含 ⌘N/⌘O/⌘S/⌘1-⌘4 等快捷键）、
四类右键菜单、原生 DDP 打开/保存对话框。功能与浏览器模式完全同源（同一前端 + 同一引擎）。

> 常用变体：`cargo run --manifest-path src-tauri/Cargo.toml --bin deepdesign-studio` 一步编译+运行。

### 方式二：浏览器模式（免编译桌面壳，适合快速预览/调试前端）

```bash
cd moonviz-demo-tauri
./scripts/build-and-run-studio.sh
```

脚本会依次：检查引擎（`moon check`）→ 构建 DDP codec → 在 **http://127.0.0.1:8903/** 启动 Studio。
浏览器打开该地址即可使用；`Ctrl+C` 停止，重启后刷新页面。

> 附注（非运行必需）：仅当需要 Dock/启动台显示应用图标或对外分发时才打包 `.app`
> （`cargo install tauri-cli --locked && cargo tauri build`）。日常开发用上面的编译运行即可；
> 直接运行的二进制在 Dock 显示系统通用图标属 macOS 对无 bundle 程序的正常行为。

### ddpView（独立只读查看器，与 Studio 完全解耦）

```bash
cd moonviz-demo-tauri
./scripts/build-and-run-ddpview.sh   # http://127.0.0.1:8902/
```

打开后仅有一个「打开文件」入口；选择 `.ddp` 输入密码即浏览，可点击绿色热区沿交互流跳转。
不能编辑、不能保存、不加载 Agent。

### Agent（可选）

浏览器/桌面模式设置面板（右上 ⚙）选择基座 `fxsdk`，填入 AI Gateway API Key（或环境变量
`AI_GATEWAY_API_KEY`），并执行一次 `cd agent && npm install libfx`。无密钥时模板/画布编辑不受影响。

### 环境变量

| 变量 | 默认 | 说明 |
|------|------|------|
| `MOONVIZ_PORT` | 8903 / 8902 | 浏览器模式端口 |
| `MOONVIZ_DIR` | 自动向上查找 | 引擎目录（含 `cli/` 包） |
| `MOONVIZ_DDP_HELPER` | 自动构建路径 | `ddp_codec` 二进制 |
| `AI_GATEWAY_API_KEY` | — | fx Agent 密钥 |

### 常用快捷键

`⌘K` Agent 指令 · `⌘1/⌘2/⌘3` 线框图/高保真/MBT 源码 · `⌘4` 演示 · `⌘S` 导出 DDP ·
`⇧⌘N` 新建画板 · `⇧⌘F` 自动修复 · 方向键移动元素 · 双击改文字 · 右键上下文菜单。
完整清单见 `docs/menus.md`（帮助菜单 → 快捷键与菜单说明，或按 `⌘/`）。

### 验证与测试

```bash
cd moonviz && moon test --target native        # 引擎 161 项
cd moonviz/ddp && cargo test                   # DDP 加密 3 项
cd moonviz-demo-tauri && node test_studio.cjs  # Studio 回归
cd moonviz-demo-tauri && python3 test_ddp_view.py
```

## 引擎能力（MoonBit）

| 域 | 能力 |
|:---|:---|
| 布局 | Fixed/Fill/Hug · 栈布局 · 绝对定位 · 结构式自适应模板 |
| Paint | 纯色 · linear/radial 渐变 DSL（含文字渐变） |
| Effects | 阴影 e1-e3 · 旋转 · 模糊 · 混合模式 · 翻转 |
| 约束 | Figma Constraints：rt/ct/stretch/hscale × t/m/b + resize-canvas |
| 结构 | group/ungroup（包围盒换算）· reorder Z序 · copy 子树克隆 · align 对齐 |
| 组件 | 52 个 / 8 大类（actions·inputs·selection·display·layout·navigation·feedback·overlay） |
| 交互 | flow 交互流 · tap 命中检测 · NavigationState · 播放 |
| 持久化 | 单一 `.mbt.md` 事实源 · 加密 `.ddp` 读写 · 引擎重建 SVG/RenderPlan |
| 接入 | CLI（native） · MCP Server · 嵌入式运行时 SDK |
