# deepDesign Studio 技术设计

## 1. 文档目的

deepDesign Studio 是 MoonViz 视觉原型引擎的桌面工作室。它提供画布编辑、组件放置、交互流配置、Agent 辅助修改、MBT 源码查看和 DDP 文件读写。

本设计文档描述当前真实实现及其约束，重点回答四个问题：

1. 画布、Agent、源码和文件之间谁是事实源？
2. Studio 如何调用 Agent 和 MoonViz 引擎？
3. DDP 与 `.mbt.md` 如何转换和渲染？
4. 独立只读查看器 `ddpView` 与 Studio 如何隔离？

## 2. 核心决策

### 2.1 唯一事实源

一个项目对应一份完整的 MoonBit 文学化源码文件：

```text
.ddp
  └─ 认证加密后的完整 UTF-8 `.mbt.md`
```

`.mbt.md` 是唯一事实源。以下内容都不能成为第二份事实源：

- 前端 `sessions`、`nodes`、`flows` 状态
- Agent 操作日志
- 内存中的 `Project` / `Document`
- SVG 或 RenderPlan
- `.mvz.json`
- HTML
- DDP 外部 manifest 或多文件 archive

这些对象只允许作为内存缓存、传输结果或派生显示结果存在。

### 2.2 所有修改都写回 MBT

人类和 Agent 的修改路径不同，但提交边界相同：

```text
人类画布操作 ─┐
              ├─ MoonViz 解析/校验 ─→ canonical `.mbt.md`
Agent 操作 ───┘                         ↓
                                    重新解析/渲染
```

只有 canonical MBT 重新解析成功后，画布显示才被更新。

### 2.3 DDP 是 MBT 的加密表示

DDP 不是 ZIP，不是文件集合，不是带 `manifest.json` 的包。DDP 的明文载荷就是一份完整 `.mbt.md`。

当前 DDP codec 使用共享引擎 crate `moonviz/ddp`：

- Argon2id：密码派生
- XChaCha20-Poly1305：认证加密
- zstd：压缩
- OS CSPRNG：salt 和 nonce
- bounded streaming decompression：限制解压窗口和明文大小
- `Zeroizing`：清理敏感缓冲区

## 3. 系统分层

```text
┌──────────────────────────────────────────────────────────────┐
│ deepDesign Studio                                             │
│ frontend/index.html                                            │
│ 画布、Inspector、组件库、Agent 面板、MBT 源码模式、播放模式       │
└──────────────────────┬───────────────────────────────────────┘
                       │ Tauri invoke / HTTP browser bridge
┌──────────────────────▼───────────────────────────────────────┐
│ Tauri/Rust 壳                                                  │
│ 文件对话框、DDP opaque bytes、fx 进程启动、MoonViz CLI 启动       │
│ 不解释 MBT 视觉语义                                            │
└───────────────┬──────────────────────────┬────────────────────┘
                │                          │
                │ stdin/stdout JSON        │ shared Rust crate
                ▼                          ▼
┌───────────────────────────┐   ┌──────────────────────────────┐
│ MoonViz MoonBit Engine    │   │ moonviz-ddp                  │
│ scanner / decl / core     │   │ DDP 加解密与压缩              │
│ Project / Document        │   │ 无 Tauri 依赖                 │
│ solve / validate / SVG    │   └──────────────────────────────┘
│ HumanGate / AgentGate     │
│ 52 个组件 preset          │
└───────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ 独立 ddpView                                                   │
│ 只读 DDP 文件选择 → codec → MBT render → SVG/交互播放           │
│ 不调用 fx，不读取 Studio 配置，不提供写操作                     │
└──────────────────────────────────────────────────────────────┘
```

## 4. `.mbt.md` 文档模型

`.mbt.md` 遵循 MoonBit 官方文学化源码语义。

### 4.1 官方代码块

| Fence | MoonBit 行为 | MoonViz 行为 |
|---|---|---|
| ````mbt```` | 编译 MoonBit 源码，不自动创建测试入口 | 只有被显式标记为 visual block 才参与画布构建 |
| ````mbt check```` | 文档测试代码，可执行 `test` / `async test` | 只作验收，不产生第二份画布 |
| ````mbt nocheck```` | 只展示，不编译、不测试 | 只展示 |
| ````moonbit```` | 普通展示代码，不编译、不测试 | 只展示 |

普通 Markdown 正文保存设计意图、约束和修改记录，不被当成视觉 DSL 执行。

### 4.2 MoonBit front matter

`moonbit:` 属于官方工具链配置，可以声明：

- `backend`
- `import`
- `deps`

Studio 不覆盖或重新解释这些字段。

### 4.3 MoonViz visual block

MoonViz 用显式标记绑定画板：

```markdown
<!-- moonviz:artboard login -->
```mbt
fn visual_login() -> @decl.Prototype {
  let page = @decl.prototype(name="login", width=390.0, height=844.0)
  page.add(@decl.text(id="title", content="欢迎回来", size=28.0))
  page.add(@decl.button(id="submit", width=@decl.fill, height=@decl.fixed(48.0), label="登录"))
  page
}
```
```

约束：

- marker 必须紧邻后面的 `mbt` block。
- 一个 visual block 对应一个画板。
- 一个项目 MBT 文件可以包含多个 visual block。
- `mbt check` 测试可以重新构造页面进行断言，但不是页面事实源。
- MoonViz 只解析支持的公开 `@decl` DSL，不执行任意 MoonBit 动态逻辑来猜画布。
- 节点 `id` 是人类和 Agent 的共同引用语言。

## 5. 渲染管线

官方 MoonBit 本身不负责视觉页面渲染。MoonViz 负责将 MBT 源码编译成视觉模型：

```text
DDP bytes
  ↓ decrypt + decompress
UTF-8 `.mbt.md`
  ↓ MBT scanner
front matter + fence + visual blocks
  ↓ visual declaration extraction
@decl DSL
  ↓ parse_decl
Prototype
  ↓ Prototype.build()
Document / Scene Graph
  ↓ solve()
SolvedLayout
  ↓ validate()
HumanGate / AgentGate
  ↓ render_svg() 或 MoonVizRT::render_plan()
Studio / ddpView 显示
```

SVG 和 RenderPlan 是派生结果：

- 不能替代 MBT 保存
- 不写入 DDP
- 不用于恢复项目真相
- 不通过 Markdown-to-HTML 生成视觉交付页

## 6. Studio Agent 架构

### 6.1 实际 Agent 基座

Studio 使用用户指定的 **Vercel `fx` Agent**，通过官方 Node SDK **libfx** 嵌入（`agent/fx-agent.mjs`）：

```text
Studio
  → /api/fx/agent
  → agent/fx-agent.mjs（createFxAgent，apiKey + model + instructions）
  → fx 调用宿主注册的工具：
       moonviz_op     执行一条 MoonViz 操作（AgentGate 严格校验并写回 MBT）
       read_mbt       读取当前 canonical MBT
       list_components 发现 52 个组件 preset
  → 每次工具调用 = moon run cli apply-agent-mbt-op-b64
  → 桥返回最终 canonical MBT + render + ops 日志
```

fx 的模型、Provider、凭据、MCP 和会话由 fx/libfx 自己管理；Studio 只保存 AI Gateway API Key（本地）与可选模型提示。`fx ask` CLI 模式与离线 Shim 保留为兼容回退。

### 6.2 设置项

- Agent 基座：`fx SDK（libfx 嵌入，推荐）` / `fx CLI` / `Studio Agent Shim`
- AI Gateway API Key（本地保存，留空则用 `AI_GATEWAY_API_KEY` 环境变量）
- 模型（留空用 fx 默认）
- fx CLI 路径与工作区（CLI 模式）

### 6.3 Agent 输出边界

fx 只能通过 `moonviz_op` 工具改变设计；操作集合：

```text
move, update, delete, copy, reorder, flip, place, flow, theme, fix
```

每次调用都经 MoonViz AgentGate；结构/视觉违规被拒绝并把错误回灌给 fx 修正重试，fx 不能直接写 `.mbt.md`、不能改 SVG、不能绕过 Gate。桥接前置校验输入 MBT（`mbt_invalid`），网关认证拒绝映射为 `fx_auth_refused`。


## 7. 人类编辑路径

### 7.1 画布操作

用户拖拽、属性修改、组件放置、复制、排序、翻转、删除和流程连接都被转换为 MoonViz operation。

Studio 调用：

```text
apply-human-mbt-op-b64 <current_mbt_base64> <operation_base64>
```

引擎内部执行：

1. 解码当前完整 MBT。
2. 重新扫描并构建临时 Project。
3. 应用 Human operation。
4. HumanGate 校验。
5. 将结果序列化为 canonical MBT。
6. 从 canonical MBT 重新加载。
7. 重新生成所有画板 SVG、节点快照和流程。
8. 返回新 MBT 和派生结果。

### 7.2 HumanGate

- 结构错误：拒绝提交。
- 视觉错误：允许提交，但记录视觉 debt。
- 写回失败：旧 MBT 和旧画布保持不变。

## 8. Agent 编辑路径

Agent 修改整份 MBT 或提出结构化 operation。Studio 调用：

```text
apply-agent-mbt-b64 <mbt_base64>
```

或：

```text
apply-agent-mbt-op-b64 <current_mbt_base64> <operation_base64>
```

AgentGate 的约束更严格：

- 解析失败：拒绝
- MoonViz 视觉声明无效：拒绝
- 结构谓词失败：拒绝
- 视觉谓词失败：拒绝
- 已存在视觉 debt 未修复：拒绝继续固化

成功后才会更新 revision、写回 MBT 并重新渲染。

## 9. 项目与多画板

一个 MBT 文件可以有多个 visual block：

```text
project.mbt.md（概念名称，不是额外文件）
├── visual block: login
├── visual block: dashboard
├── visual block: settings
└── moonviz front matter flows
```

Studio 内部的 `Project` 只是 MBT 的运行时派生缓存。`active` 只控制当前显示画板，不缩小导出范围。

流程存在于同一份 MBT 的 `moonviz.flows` 元数据中，并引用稳定的画板 ID、节点 ID 和 trigger：

```yaml
flows:
  - from: login
    to: dashboard
    trigger: tap:submit
```

引擎会校验：

- from 画板存在
- to 画板存在
- `tap:<node>` 的节点存在

模板不得生成悬空流程。

## 10. DDP 设计

### 10.1 物理格式

```text
DDP bytes
├── DDP1 magic
├── codec version
├── Argon2id salt
├── XChaCha20 nonce
└── authenticated ciphertext
      └── compressed complete `.mbt.md`
```

没有：

- ZIP entry
- manifest.json
- 文件清单
- pm-design.md
- OpenUI
- HTML
- `.mvz.json`

### 10.2 导出

```text
current canonical MBT
  → UTF-8 bytes
  → zstd compression
  → Argon2id password-derived key
  → XChaCha20-Poly1305 AEAD
  → `.ddp`
```

### 10.3 导入

```text
`.ddp`
  → validate magic/version/size
  → authenticate/decrypt
  → bounded decompress
  → strict UTF-8
  → MoonViz MBT scan/parse/validate/render
  → atomic project replacement
```

错误密码、篡改、损坏、超限、无效 MBT 或 flow 错误都不能污染当前 Studio 项目。

## 11. Tauri 壳

文件：`moonviz-demo-tauri/src-tauri/src/lib.rs`

职责：

- 启动 MoonViz CLI
- 启动 fx `ask --no-save`
- 打开 DDP 文件选择器
- 保存 DDP 文件
- 读取 DDP 并将解密 MBT 交给 MoonViz
- 诊断 MoonViz/FX 环境

不负责：

- 解析 visual block
- 构造 Scene Graph
- 运行组件语义
- 生成 SVG
- 维护第二份项目模型

DDP 加密实现位于共享 crate：

```text
moonviz/ddp/
├── Cargo.toml
├── src/lib.rs
└── src/bin/ddp_codec.rs
```

Studio 通过 path dependency 使用 `moonviz-ddp`。

## 12. 浏览器模式

`server.py` 提供 Studio 浏览器模式：

- `/api/exec`：调用 MoonViz CLI
- `/api/fx/ask`：调用本机 fx
- `/api/ddp/encrypt`：调用共享 DDP helper
- `/api/ddp/decrypt`：调用共享 DDP helper
- `/api/mbt/render`：只读 MBT 渲染
- `/api/ddp/view`：只读 DDP 解密并渲染

服务只监听 loopback，校验 Host/Origin，限制请求大小，并拒绝命令中的换行与注入字符。

## 13. 独立 ddpView

`ddpView` 是从 Studio 拆出的独立只读应用，不依赖 Studio：

```text
用户选择 DDP + 输入密码
  → `/api/ddp/view`
  → DDP codec
  → MoonViz `render-mbt-b64`
  → 只返回 entry、flows、artboards 和 SVG
  → ddpView 播放器
```

### 13.1 UI

未加载时只显示：

- DDP 文件选择
- 密码
- 打开并渲染

加载后显示：

- 当前画板渲染结果
- 画板切换
- 适应窗口
- 放大/缩小
- 交互节点高亮

不显示：

- Studio 编辑器
- Inspector
- Agent 面板
- LLM 配置
- MBT 源码编辑器
- 保存按钮
- 导出按钮

### 13.2 只读交互

ddpView 允许改变浏览状态，不允许改变源文件：

- 点击带 `tap:<node>` flow 的节点，在内存中跳转目标画板。
- Enter/Space 可触发同一跳转。
- 画板选择和缩放只改变当前查看状态。
- DDP 原文、MBT 源文和服务器文件不会被写回。

### 13.3 readonly 服务

```bash
MOONVIZ_PORT=8902 python3 ddpView.py
```

readonly 模式只开放：

- `/api/ddp/view`
- `/api/mbt/render`

会拒绝：

- `/api/exec`
- `/api/fx/ask`
- `/api/ddp/encrypt`
- `/api/ddp/decrypt`
- 任意保存/项目写入路由

## 14. 引擎组件系统

组件定义全部位于 MoonViz `core/`，Studio 不复制组件语义。

当前引擎 catalog：

- 52 个唯一组件
- 8 个分类：actions、inputs、selection、display、layout、navigation、feedback、overlay
- 每个组件带默认尺寸、语义类型、描述和 variants
- Studio 通过 `list-components`/MCP `list_components` 发现
- Studio 只负责预览、拖入和提交 operation

典型组件包括：

```text
button, text_input, card, app_bar, divider, heading, body_text,
badge, fab, search_bar, slider, checkbox, switch, radio, avatar,
progress, chip, image, list_item, tab_bar, alert, toast, dialog,
drawer, menu, table, kbd, rating, stat, accordion, carousel,
timeline, breadcrumb, pagination, stepper, navbar, bottom_nav,
snackbar, skeleton, spinner, meter, popover, tooltip ...
```

组件实例化、variant 应用、尺寸和样式必须由引擎完成；前端预览字符只是视觉提示，不具备组件事实意义。

## 15. 错误处理

错误按层次分为：

### 15.1 Transport

- `mbt_transport_invalid_base64`
- `mbt_transport_invalid_utf8`
- `request_too_large`
- `commands_invalid`
- `origin_forbidden`

### 15.2 DDP

- `ddp_magic_invalid`
- `ddp_version_unsupported`
- `ddp_password_required`
- `ddp_authentication_failed`
- `ddp_container_invalid`
- `ddp_decompression_failed`
- `ddp_plaintext_invalid`
- `ddp_mbt_not_utf8`

### 15.3 MBT

- `mbt_front_matter_unclosed`
- `mbt_fence_unclosed_line:<line>`
- `mbt_no_visual_blocks`
- `mbt_duplicate_artboard:<id>`
- `mbt_visual_parse_error:<id>:line:<line>`
- `mbt_unknown_entry:<id>`
- `mbt_flow_unknown_artboard:<from>:<to>`
- `mbt_flow_unknown_node:<artboard>:<node>`
- `not_renderable_visual_logic_line:<line>`

### 15.4 Gate

- `mbt_gate_block:<artboard>:<predicate>:<node>`
- `stale_base`
- `structural_block`
- `hard_block`

错误必须在失败时保持旧 MBT、旧 Project 缓存和旧画布不变。

## 16. 测试策略

### 16.1 MoonViz

```bash
cd moonviz
moon test
```

覆盖：

- 官方 MBT fence 分类
- front matter 和 line mapping
- 多画板加载
- flow 引用校验
- MBT canonical round-trip
- visual block 动态逻辑拒绝
- HumanGate debt
- AgentGate hard block
- 52 个组件 catalog
- CLI Base64 source protocol

### 16.2 真实 MoonBit 工具链

canonical MBT 必须通过：

```bash
moon check design.mbt.md
moon test design.mbt.md
```

不能只通过 MoonViz 自己的 parser 测试。

### 16.3 DDP

```bash
cargo test --manifest-path moonviz/ddp/Cargo.toml
```

覆盖：

- 中文 MBT 加解密往返
- 错误密码
- ciphertext 篡改
- 明文/密文大小限制
- 压缩膨胀限制
- 密文不泄露 MBT 明文

### 16.4 Studio

```bash
cd moonviz-demo-tauri
node test_studio.cjs
python3 test_ddp_view.py
```

覆盖：

- 操作队列串行化
- 多画板追加
- active board/selection/draft 保留
- 新项目失败时不破坏旧项目
- opacity 提交
- 两份 Studio HTML 入口同步
- DDP viewer 真实中文 MBT
- DDP/MBT SHA-256 不变
- readonly 路由拒绝 mutation
- Host/Origin 校验
- 命令注入拒绝

## 19. 编译与启动脚本

项目提供两个独立启动脚本，脚本都会先检查 MoonBit 引擎，再构建所需的 DDP codec，然后启动对应入口：

### 19.1 启动 Studio

```bash
cd moonviz-demo-tauri
./scripts/build-and-run-studio.sh
```

默认启动浏览器模式 `http://127.0.0.1:8903/`。可以用 `MOONVIZ_PORT` 覆盖端口：

```bash
MOONVIZ_PORT=8910 ./scripts/build-and-run-studio.sh
```

脚本执行顺序：检查 `moon`/`cargo`，运行 `moon check --target native`，构建 `../moonviz/ddp` 的 `ddp_codec`，最后启动 `server.py`。

原生 Tauri GUI 的编译命令：

```bash
cd moonviz-demo-tauri/src-tauri
cargo build
```

运行原生 Tauri GUI 需要安装 Tauri CLI（`cargo-tauri`）；Rust 工程本身可以直接通过 `cargo build` 和 `cargo check` 验证。

### 19.2 启动独立 ddpView

```bash
cd moonviz-demo-tauri
./scripts/build-and-run-ddpview.sh
```

默认启动只读查看器 `http://127.0.0.1:8902/`。可以用 `MOONVIZ_PORT` 覆盖端口：

```bash
MOONVIZ_PORT=8911 ./scripts/build-and-run-ddpview.sh
```

脚本先运行 MoonViz native check，再由 `ddpView.py` 构建共享 DDP helper，最后以 `--readonly` 启动 server。Studio 与 ddpView 的进程、端口、配置和权限完全独立：只有 Studio 启动 fx Agent，ddpView 只解密和渲染。


- 本机若未安装 `fx`，Studio 的真实 LLM Agent 请求无法完成；需要用户先执行 `fx login` 或 `fx setup`。
- 当前 Studio 使用 `fx ask --no-save` 简化接入；完整长期 ACP session 管理仍可作为后续增强。
- 当前原生 Tauri GUI 构建需要 `cargo-tauri`/Tauri CLI；Rust 工程本身可以用 Cargo 构建和检查。
- MoonViz 的 visual block 是受控 `@decl` DSL，不执行任意 MoonBit 代码动态生成页面。
- 内存 Project、SVG 和 RenderPlan 仍存在，但只应作为 MBT 的派生缓存，不能被新功能当成持久事实源。

## 18. Agent 设置与 LLM 端点

Agent 执行基座只有一个：**fx-agent-sdk**（`agent/fx-agent.mjs` 内嵌 libfx `createFxAgent`）。设置面板只配置 **LLM 驱动端点**（OpenAI chat 兼容格式）三项：

| 字段 | 说明 |
|------|------|
| Base URL | 留空 = Vercel AI Gateway；或 DeepSeek / Kimi / GLM / MiniMax 官方 OpenAI 兼容端点 |
| API Token | 仅本机 localStorage；留空回退环境变量 `AI_GATEWAY_API_KEY` |
| Model ID | 如 `deepseek-chat`、`moonshotai/kimi-k2-instruct`、`glm-4.7`、`MiniMax-Text-01` |

服务商预设一键填入（DeepSeek `https://api.deepseek.com`、Kimi `https://api.moonshot.cn/v1`、
GLM `https://open.bigmodel.cn/api/paas/v4`、MiniMax `https://api.minimax.chat/v1`）。
libfx 的 `gatewayChatUrl` 只允许 Vercel Gateway 或 loopback HTTP，因此远程厂商端点由桥内
启动的本地 HTTP 转发器（OpenAI chat 格式直通）承载。旧 fx CLI / Shim 模式已移除。

## 18a. DDP 容器双模式

| 魔数 | 模式 | 查看器行为 |
|------|------|-----------|
| `DDP1` | 密码加密（Argon2id+XChaCha20） | 密码浮层，错误可重试 |
| `DDP2` | 免密（zstd + CRC32 完整性） | **免密直开**（读魔数自动分流） |

## 19. 菜单与文案体系

完整的中文菜单文案清单见 `docs/menus.md`。要点：

- **原生菜单栏**（Tauri 2 `build_native_menus`）：deepDesign Studio / 文件 / 编辑 / 视图 / 画板 / 帮助 六个顶级菜单；菜单项只发 `native-menu` 事件（id 载荷），前端 `nativeMenuAction()` 映射执行 —— 菜单不持有状态，动作最终都落到引擎 CLI 与唯一 `.mbt.md`。
- **右键菜单**（前端 `showMenu()` 动态构建）：画布元素（编辑文字/复制/置顶置底/居中/翻转/链接交互/删除）、画布空白（新建画板/复制画板/形态切换/校验渲染/演示/适配窗口）、画板卡片（切换/复制/从此演示）、MBT 源码编辑器（全选/复制源码/校验渲染/清空）。
- **快捷键帮助**：帮助菜单 → 快捷键与菜单说明弹窗（文件/视图/画板/画布/演示全量快捷键）。
- 引擎配套：`apply_mbt_operation` 新增 `duplicate <artboard> <new_name>`（MBT 通道画板复制），与直接命令同源。
- **演示模式（工作区内）**：`mode-play` 状态隐藏全部编辑面板、只保留当前画板 + 顶部路径 chip；交互命中使用 HTML 热区（`.pm-hot`，节点矩形 × displayScale），点击经 `playTap → flow` 导航；Esc 逐层回退并退出。不再切换独立全屏页。

## 20. 后续演进

1. 将 Studio 从 `fx ask --no-save` 迁移到完整 `fx acp` 长连接会话，保留 fx 的原生线程、权限和 MCP 能力。
2. 为 MBT visual block 增加更完整的官方 MoonBit import/deps 解析和精确 YAML CST 保留。
3. 用增量 Markdown CST 替换当前块级扫描，保证正文和未识别代码块字节级保留。
4. 将 `RenderPlan` 接入高性能 Canvas/Skia 后端，同时保持 MBT 重新解析渲染约束。
5. 增加 `ddpView` 的文件历史/最近打开列表，但只保存本地浏览状态，不保存或修改 DDP 内容。
6. 将引擎 52 个组件的视觉回归扩展为每个 preset/variant 的渲染快照与无障碍检查。
