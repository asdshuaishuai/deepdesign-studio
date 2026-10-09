# AGENTS.md — deepDesign Studio

AI 原生原型设计工具的桌面客户端（Tauri 2 + Rust）。**唯一事实源是 MoonViz 引擎的 `.mbt.md` 文档**：
人类画布操作与 Agent 修改都必须经引擎校验（HumanGate / AgentGate）后回写同一份文档，
`.ddp` 只是它的认证加密容器。

**当前版本：0.4.1**（2026-10-09 发布）——版本号唯一权威是仓库根 `VERSION` 文件，
详见 [docs/versioning.md](docs/versioning.md)。

## 分支纪律（用户决策）

- **`dev` 是开发分支**：所有日常开发提交都落在这里。拉取代码、改动、测试都在 `dev` 上做。
- **`main` 是发布分支**：只接受从 `dev` 合并进来的发布内容，用于打 tag 与构建正式产物。
  不在 `main` 上直接开发。
- **发布流程**：`dev` 改完并验证 → 合并 `dev` 进 `main` → `main` 上打 tag `v*` →
  `release-all.yml` 自动构建三平台产物并附到 GitHub Release（鸿蒙 `.app.zip` 另走本机
  `ohos/ohos-release.sh` 手动补传，见「发布完整性」）。
- **不要把功能提交直接推到 `main`**——那会让发布线偏离 `dev`，两边分叉后
  「已发布版本里到底有没有某个修复」就再也说不清（2026-10-09 的 v0.4.1 实测踩过：
  行内编辑修复只存在本地 main、没进 dev/main 远端，发布产物因此带 bug）。

## 三层架构与边界（改代码前先读）

```
frontend/index.html        纯静态单文件前端（无打包器、无 HTTP 层）+ 画布侧 wasm 引擎实例
src-tauri/src/lib.rs       Tauri 命令层：invoke_fx_sdk / save_ddp（支持原地保存）/ open_ddp（支持 path 免对话框）/ list_ddp_projects（多项目数据源）/ save_text_file / confirm_discard / set_project_dirty / app_exit / model_registry + EngineHost
src-tauri/src/wasmtime_host.rs  wasmtime 进程内引擎宿主（纯 Rust 运行时，agent 循环与 cargo test 共用）
src-tauri/src/agent.rs     进程内 Agent 循环（OpenAI/Anthropic 工具调用 × wasmtime 引擎宿主）
scripts/sync-engine.mjs    引擎产物同步：GitHub Releases 拉标准 classic wasm → sha512 校验 → 真机契约探针 → frontend/vendor/
vendor/moonviz-ddp/        vendored DDP 编解码 crate（引擎仓库 MIT 副本，见其 README）
docs/upstream-engine-ask.md  wasmtime 宿主立项 → **已实施**（上游 classic 变体落地后接入，保留作背景与消费侧清单）
```

必须守住的边界：

- **前端只能经 `window.__TAURI__.core.invoke` 调上面 8 个命令**，没有 HTTP 层，不要引入 fetch/axios。
- **Rust 不解释视觉语义、Markdown 或 MoonBit block**。它只做三件事：b64 搬运、wasmtime 宿主、DDP 加解密。
  任何"顺手在 Rust 里改一下布局/属性"的做法都越界了——变更必须回到引擎。
- **人类操作与 Agent 操作走不同引擎入口**：画布走 `apply_human_op`，Agent 变更走
  `session_apply_agent`（0.1.1-session 起与无状态 `apply_agent_op` 同门同分发器；宿主按
  mbt 键控复用会话——内存棘轮减半、只读突发免重解析），语义差异由门实现，不要在前端绕过门直接改数据。
  画布保持无状态是有意的：人类 op 每次都需要同步渲染，会话路径信封不带 render，迁移反而多一次
  `render_mbt`——别把它「优化」到会话路径。
- **引擎是标准 classic wasm 产物**（`frontend/vendor/moonviz.wasm`，GitHub Releases
  的 `moonviz-wasm-classic-<version>.wasm`——**纯 WASM MVP、宿主中立、零 import**；
  docs #wasm 节的「标准 wasm」，与 engine-v* tag 同源；wasm-gc 变体依赖 JS String
  Builtins 提案、仅 V8 类引擎可跑，本仓库不用）。sync-engine.mjs 拉取 + sha512 校验 +
  真机契约探针（7 经典/4 检视/26 session 导出 + `_in` 面实跑 + 模板/组件/会话计数）。
  **engine-v0.1.2 的 `_in` 字节契约面（issue #8）是全部宿主的写路径**：wasmtime_host、
  前端（engSlotLoad）、sync 探针三处消费——文档/op/artboard 经 in/arg/arg2 三槽 UTF-8
  分块压入（每块小端 4 字节+有效长度），`*_in()` 变体解码调经典入口。**写方向的逆向
  字符串布局依赖已退役**（engWriteStr 删除）；返回方向仍是引擎字符串指针（读布局保留，
  read_str/engReadStr）。0.1.2 兑现 #6 修复：session_apply_agent 免三重往返，实测
  0.37ms/op（无状态 2.62ms/op，7.1×）。
- **两个引擎实例（WebView 画布 + Rust wasmtime 宿主）只交换 canonical `.mbt.md` 文本**，
  无共享状态；前端调 `engApply/engRender`（wasm 直调），agent 循环调 `EngineHost::call`
  （wasmtime 进程内直调——**纯 Rust 运行时：无 node、无子进程、无 WebView 往返**；
  字符串编解码与会话缓存编排在 wasmtime_host.rs，与 engine-host.mjs/前端三处同构）。
  wasm 产物编译期 include_bytes! 嵌入 Rust——**缺失 = 编译错误**（先跑 sync-engine.mjs）。
- 引擎要求文档至少一个视觉块——**空项目起步用种子文档引导**（前端 `seedDoc`/`bootstrapFirstBoard`，
  Rust `agent.rs::seed_doc`，两边逐字对齐；首 op 后删除 `__seed` 画板）。

## 常用命令

**Rust 命令必须在 `src-tauri/` 下执行**——仓库根目录没有 `Cargo.toml`，也没有 `package.json`。

```bash
cd src-tauri && cargo test        # 测试：方言表/协议/归一化单测 + base_url 策略 + wasm 契约（node 宿主跑真产物）+ 4 个端到端（mock LLM）+ 模型快照契约
cd src-tauri && cargo build
node test_studio.cjs              # 前端状态机冒烟 + wasm 产物契约（在仓库根跑，classic wasm 无 node 版本门槛）
node scripts/sync-engine.mjs      # 引擎产物同步（GitHub Releases classic wasm → frontend/vendor/；先跑这个）
node scripts/sync-models.mjs     # 模型元数据快照同步（models.dev → src-tauri/models.json）
node scripts/i18n-catalog.cjs && python scripts/gen-i18n.py --write   # i18n 字典重建（改 T 表/新增 UI 键后；--check 只验漂移）
./dev.sh                          # debug 编译启动（Windows 用 Git Bash）
dev.bat                           # 同上的 CMD 原生版（免 Git Bash；--fresh 杀旧实例+清 WebView2 HTTP 缓存，绝不动 Local Storage）
npx @tauri-apps/cli build         # 打包（beforeBuildCommand 自动 sync-engine）
scripts/build-packages.sh --all   # Linux 两格式打包：deb（标准 FHS）+ AppImage → dist/
                                  #   WebKitGTK 运行库随包捆绑（从 deepin 仓库现场收集）
.github/workflows/release-all.yml # 全平台构建流：tag v* 触发，产物自动附 GitHub Release（固定名副本供官网直链）
```

仓库**没有配置 lint / formatter**（无 rustfmt.toml、clippy 配置、eslint、prettier）。
2021 edition，形态上跟随既有代码即可。

## 同步引擎更新（引擎发布新版本后必做）

引擎以**预编译 wasm 产物**集成，不依赖兄弟仓库、不装 MoonBit 工具链。升级引擎 =
改 `scripts/sync-engine.mjs` 顶部的 `ENGINE_VERSION` / `WASM_SHA512`（release 资产 sha512），然后：

```bash
node scripts/sync-engine.mjs    # 下载 → sha512 校验 → 契约探针（导出面/模板/组件逐个 place 验证）→ frontend/vendor/
cd src-tauri && cargo test      # node 宿主真机契约 + e2e 必须仍绿
node test_studio.cjs            # 前端侧 wasm 契约（模板清单 vs agent.rs）必须仍绿
```

探针会**自动裁剪**组件快照（引擎不认的 id 不写入 components.json）并在模板清单与
`agent.rs::ENGINE_TEMPLATES` 漂移时直接失败——两边必须一起改。
⚠️ 核对哈希时注意编码：锚点是 **base64**（`sha512-FzIfadPP…`），而 `shasum -a 512`
输出 **hex**——两者是同一份字节的不同编码，直接目测对比会误判「产物被换」
（R5 审查中的真实假警报：hex `17321f69…` ⇄ base64 `FzIfadPP…` 是同一份 wasm）。
`frontend/vendor/moonviz.wasm` 与 `engine-manifest.json` 已 gitignore；`components.json`
入库（它是探针验证过的快照，前端组件面板与 agent list_components 共用）。

## 同步模型快照（models.dev，与引擎无关的另一条对账线）

`src-tauri/models.json` 是 models.dev api.json 的**裁剪快照**（13 个预设映射到 11 个唯一提供商 /
80 模型，~44KB，随版本库提交；以快照实际计数为准，别在文档里写死后被 `snapshot_structure_is_healthy`
的宽松下限掩盖）。MIT 许可，vendored 而非运行时拉取（离线桌面 + 依赖极简）。

```bash
node scripts/sync-models.mjs    # 重新生成快照（更新 fetched_at）
cargo test                      # 5 个模型快照契约测试必须仍绿
```

**分层事实源（models 线）**：快照 ⇄ 前端 `PROVIDERS` 端点与默认模型（`presets_match_snapshot`）、
快照 ⇄ `MINIMAX_STATIC_MODELS`（`minimax_static_models_in_snapshot`）、快照结构健康
（`snapshot_structure_is_healthy`）、溯源字段（`snapshot_has_provenance`）。
**分歧必须显性登记**：端点漂移进 `KNOWN_DIVERGENCES`（记录上游现值 + 理由，上游再变会红）、
快照滞后项进 `KNOWN_UI_EXTRAS`（快照补齐会红逼清理）。**协议族变化（如 MiniMax 转向
Anthropic 兼容）意味着请求体改造，不是改 URL——人工裁决，绝不自动跟随。**
背景与数据口径见 `docs/research/models-dev-ai-sdk.md`；线上方言（thinking/reasoning_effort/
chat_template_kwargs）不在 models.dev 覆盖范围，仍以 `agent.rs::thinking_extra_body`
（官方文档为准）为权威。

引擎的能力面随时可能扩，`frontend/index.html` 与 `agent.rs` 都是硬编码的，**引擎一更新就要回来对账**。
**前端消费层**：`model_registry` Tauri 命令把快照下发给设置面板——模型 datalist、
能力标签（上下文/工具调用/结构化，不支持工具调用会警告，Agent 循环需要工具调用）、
思考等级档位按 `reasoning_options` 收紧（GLM-5.3 类→auto/low/high/max，Kimi k2.6 类→
auto/off），`fetchFxModels` 端点拉取失败时回退到快照清单（MiniMax 静态清单为最后手段）。
快照不可用时全部降级为手输，不影响主流程。

**`SKILL.md`（仓库根）是本仓库的引擎能力字典**——vendored 自引擎仓库 `SKILL.md`。
分层事实源：**变更 op 层由 `list-ops`（wasm 直调导出）提供注册表**（sync-engine 探针校验 ≥25）；
readonly 路由由 agent.rs 的 `READONLY_OPS` 表锚定（`readonly_routing` 单测；SKILL.md 文末
清单块是文档镜像，不再有契约测试锚定——skill_dictionary 测试已随 wasm 重构删除）。
~~引擎仓库只读~~（已修订，见下节「引擎 dev 修改」）：**能力对账仍以产物行为为准。**
对账的权威来源不是引擎的 `help` 文案，而是实际行为：

```bash
node scripts/sync-engine.mjs    # 产物缺失时先同步；契约探针同时校验导出面/模板/组件/会话计数
node scripts/engine-host.mjs    # node 直查工具（调试用；Rust 侧已不依赖——wasmtime 宿主是唯一运行时）
```

### 引擎 dev 修改（引擎规范线，2026-10-09 起，用户决策）

引擎源码仓库在 `../moonviz`，**主线开发分支是 `dev`**（已发布的 0.1.8 即从 dev
出线；`release/1.0` 是 RENDER/SMART-UX 的 1.0 功能线，未发版）。**改引擎不进主
工作区**：`git -C ../moonviz worktree add ../moonviz-dev dev` 切 dev worktree，
`cd moonviz-dev/core && moon test -p core` 全绿后
`cd .. && moon build --release --target wasm wasm` 构建，然后
`MOONVIZ_WASM_PATH=../moonviz-dev/_build/wasm/release/build/wasm/wasm.wasm node scripts/sync-engine.mjs`
接回本仓——本地构建 sha 必然异于发布锚点，脚本会提示「非发布锚点，探针把关」，
**契约探针是本地构建的唯一守门员**（导出面/模板/组件逐个 place/27 session 实跑）。
不带该环境变量跑 sync 仍锚定 GitHub Releases 发布产物，两者互不干扰。

规范线现状（已在 `dev`，`e1fe594`）：`core/norms.mbt`（按钮不卡文案：文案宽+24 留白、
高 ≥ 字号+20；圆角档：按钮族 8、胶囊 高/2、avatar 999；全宽条/全宽行直角）
+ `critique` 第 9 维 `norms`（给 Agent 建议尺寸）+ `auto_fix` 规范预修 +
`list_components` 携带 `norm` 字段（components.json 快照已透传）。
**引擎发版（tag `engine-v0.1.9` + 更新本仓 sync-engine 锚点）是用户决策。**

## 硬性环境约束

- **兄弟目录 `../moonviz` 不再需要**：DDP crate 已 vendor 到 `vendor/moonviz-ddp/`，引擎以
  预编译 wasm 产物集成（sync-engine.mjs 拉取）。仓库自包含，clone 后三步即可构建：
  `node scripts/sync-engine.mjs` → `cargo build` → 打开。
- **Windows 本机编译需 MSVC 工具链**：tauri/webview2 链接在 GNU 工具链下失败
  （`linking with x86_64-w64-mingw32-gcc failed`）。本机默认是 GNU 时用
  `cargo +stable-x86_64-pc-windows-msvc test`，或 `rustup default stable-x86_64-pc-windows-msvc`。
- **wasmtime 依赖对 rustc 有最低版本要求**（wasmtime 49 需 rustc ≥1.96）——工具链过旧会在
  依赖解析阶段直接报错（不是静默降级）。`rustup update stable-x86_64-pc-windows-msvc`。
- **引擎产物编译期嵌入 Rust（include_bytes!）**：`cargo build` 前必须先跑
  `node scripts/sync-engine.mjs`，否则 `wasmtime_host.rs` 编译失败（显性错误优于静默）。
- **node 只剩开发期用途**（sync 脚本 + 前端契约测试 `test_studio.cjs` + engine-host.mjs
  调试工具）；**cargo test 已不依赖 node**——引擎测试走 wasmtime 进程内宿主，无外部运行时。
- **改 `frontend/` 后 `tauri dev` 不会热更**（它只 watch `src-tauri/`）。需在窗口按 ⌘R，
  或用 `./dev.sh --fresh`。`lib.rs` 里还有一段强制 `?v=<timestamp>` 重载，是为了绕 WKWebView 缓存——
  不要删。
- **CSP 在 `src-tauri/tauri.conf.json`**（`script-src 'self' 'wasm-unsafe-eval'`）。`wasm-unsafe-eval`
  是前端实例化引擎 wasm 的硬前提，别删。Tauri codegen 在构建期为非空内联 `<script>` 自动注入
  sha256 hash，所以 `frontend/index.html` 里那一大坨内联脚本没问题；新增内联脚本同样会被自动
  hash，但**不要**改成外部 module script。
  **hash 注入有连锁代价（2026-09-25 release 首包实证，三症状同根因）**：按 CSP 规范，某指令一旦
  含 hash/nonce，其中的 `'unsafe-inline'` 即被忽略——因此必须显式保留
  `script-src-attr 'unsafe-inline'`（内联 onclick/onkeydown 属性不受 script-src 的 hash 保护，
  缺它 = 打包后全部按钮/回车静默变死，应用成"渲染正常的死壳"）和
  `style-src-attr 'unsafe-inline'`（缺它 = HTML 所有静态 `style="…"` 属性被剥：welcome 模板
  全铺开、左栏三 panel 堆叠、topbar spacer 失去 flex 挤向中间）。dev 模式日常可用掩盖了这两条，
  **只有打 release 包才会暴露**；test_studio 检查源码结构，看不到 CSP 执行面。改 CSP 前先想清楚
  hash↔unsafe-inline 的互斥语义。
- **capabilities 最小集**（`src-tauri/capabilities/default.json`，Windows 标题栏合并后新增）：
  只放行自绘标题栏的窗口面（dragging/minimize/maximize/close/set-title——标题随项目名同步）+ `core:event:allow-listen`
  （agent 实时轨迹的 agent-event 监听）。自定义命令不经 ACL。别为"以防万一"加 capability。
- 依赖刻意保持精简。**async-openai 以【纯类型层】采用**（`chat-completion-types` feature：仅
  derive_builder+bytes，无 HTTP client）：请求骨架与 tools schema 用 SDK 类型构造，序列化后
  合并 provider 回显的原始 messages 与 thinking 家族等非标字段再经自有 reqwest 发送；
  响应侧保持 raw Value（SDK issue #498/#503：严格响应枚举在兼容网关上会碎，非标字段
  typed 往返会丢）。tools 必须用 `ChatCompletionTools::Function` 包装——裸
  `ChatCompletionTool` 序列化不带 `"type":"function"` 判别字段（wire 契约测试锚定）。
  byot/full-client 路线已评估并拒绝（byot=零类型收益+SDK 的 HTTP 栈）。Rusty V8
  （进程内 JS 引擎宿主）已被评估并**否决**：+30~80MB 安装包税 + 依赖链脆弱
  （temporal_rs/icu_calendar 编译断裂实证）；**wasmtime 为最终形态**
  （classic wasm 宿主中立使然，见 `docs/upstream-engine-ask.md`）。

## Agent 基座约定（`agent.rs`）

- **思考等级方言表是 `thinking_extra_body(model, level, protocol)`**（三参含协议），按模型名分部匹配：GLM-5.3 强制思考（仅 low/high/max）、
  GLM-5.2 及更早开关+全档、Kimi k3 恒开（off→none）、Kimi k2.x 仅开关、MiniMax 仅开关、
  StepFun 三档无开关、DeepSeek 开关+全档、Qwen 仅 vLLM 方言 off、未知模型直传 OpenAI 标准字段。
  **Anthropic 协议半区**：仅 MiniMax 家族有明确 thinking 语义——`thinking{type:enabled,budget_tokens}`
  (low 2048/medium 8192/high 16384/max 32768)，off/auto 省略即关闭；其余模型不注入。
  档位归一：`off/auto/low/medium/high/max`，旧值 `on`→`high`，未知→`auto`。
  **加任何厂商/型号都必须同步扩 `thinking_family_table` 单测**，那张表就是这个函数的契约。
- **双协议支持（MiniMax Anthropic Messages）**：`protocol_for(base_url)` 按 `/anthropic` 路径段
  或 `api.anthropic.com` 探测协议。`chat_once` 内做格式转换并**归一化为 OpenAI 形状返回**，
  主循环因此零改动：Anthropic 侧的消息转换（`to_anthropic_messages`，连续 tool 消息必须合并为
  单条 user 消息里的多个 tool_result 块、system 提取为顶层字段）、工具 schema 转换
  （`input_schema`）、响应归一（`normalize_anthropic_response`，tool_use 块 → tool_calls，
  arguments 回填为 JSON 字符串）。auth 用 `x-api-key` + `anthropic-version: 2023-06-01`。
  thinking 在 Anthropic 协议上表达为 `thinking{type:enabled,budget_tokens}`（仅 MiniMax 家族；
  off/auto 省略即关闭；budget 必须小于 max_tokens，按预算预留余量）。
  前端 13 个预设含 4 个 MiniMax（2 条 OpenAI 兼容 + 2 条 Anthropic 兼容，官方推荐路径）。
- **`READONLY_OPS` 是只读路由表**（22 项：清点类 `list`/`list-templates`/`list-components`/`list-ops`/
  `list-tools`/`list-tokens`/`list-themes`/`flows`/`benchmark`；检视类 `lint`/`critique`/`query`/`infer`/
  `spec`/`missing`/`doc-json`/`states`/`interactions`/`export-svg`/`export-html`/`extract-design-system`
  （0.1.6 新增，session_extract_design_system：颜色/尺寸 token 用量+置信度）；模拟类 `tap`）：
  engine-v0.1.1-fix 的 **session API 已导出检视面**——命中即走只读路由（session API 或直调导出），
  不进 apply 分发器。此前该表是「wasm 面不可达」拦截名单，现已转回路由白名单语义（注释处的预言成真）。
  **例外**：`list-tools` 与 `doc-json` 无对应 wasm 导出，命中返回 `wasm_engine_export_unavailable`
  （诚实报错，不假装可用）。变更类 op 绝不能进表——会被只读分支拦下而非提交。
  注意：`list_components` 作为**工具**仍可用（agent.rs 经宿主取 components.json 快照），
  路由的是同名 **op**。
- **`constrain` 自 0.1.6-fix/#19 起经 session 路由接入**（`session_constrain` 特判路由，
  **变更 op，绝不进 READONLY_OPS**）：14 种布局意图词表，cannot_parse 就地返回词表
  （错误即文档）；成功信封带 canonical（#19 修复），与变更路径同构键前移。它是布局意图
  解析器，**不做层级/z-order**——全屏背景+内容走全包含豁免（#15）、z-order 用 `reorder`。
  独立 `name` op 仍不可达，改节点名用 `update <ab> <node> name=<id>`。
- **place 最终尺寸语法（0.1.6/#18）**：`place <ab> <comp> <id> [variant|-] [x] [y] [w] [h] [k=v ...]`
  ——门在**最终 bbox** 评估；提示词已教「知道最终尺寸就随 place 传入」（真实 run 111 次
  拒绝的根因整类消除，`place_final_size_gate_evaluates_final_bbox` 测试锚定）。
- **闲置画板清扫（run 前后确定性执行）**：`sweep_idle_artboards` 以 `session_list_artboards` 的
  nodes 计数 ≤1（空/仅根）判定闲置，总数 >1 才删（实时复核永不删到最后一块）；开始清上一轮
  遗留、收尾清本轮未填充占位。list 宿主直调不记 ops，删除走 AgentGate 并记 ops；done 事件
  携带 `cleanup`/`boards` 字段，前端轨迹以绿胶囊 `tl-final` 强标志呈现收尾。
- **`INSTRUCTIONS` 与 `ENGINE_TEMPLATES` 必须与引擎同步**（`template_ids_match_engine` 测试锚定 id 集合，
  `prompt_avoids_apply_rejected_ops` 锚定新语法在场）。提示词漏一个模板 Agent 就永远不选它，
  多一个它就会猜不存在的 id。模板尺寸以引擎实际产出为准——`pc_app` 是 1280×800，不是提示词里曾写的 1440×900。
- `safe_base_url` 有 SSRF 防护：仅放行 https 与 localhost/私有网段 http（IP 段是精确判定，
  `172.20.x` 放行、`172.2.x`/`172.255.x` 拒绝，DNS 前缀伪装如 `10.evil.com` 拒绝）。改动时守住单测。
- **实时轨迹（agent-event 事件流）**：run() 循环每步经 progress 回调 → `app.emit("agent-event")`
  → 前端「Agent 追踪」时间线。事件类型：`assistant_text`（LLM 计划/澄清提问）、`tool_start`/`tool_end`
  （op、✓/✗、耗时、门拒绝详情）、`preview`（携带 `preview_seq` 单调序号）、`done`/`failed`。run id 由 lib.rs 注入每个事件（前端按它过滤归属），
  **丢 run id = 时间线 100% 失效**（历史事故）。长文本折叠为 `<details class="tl-fold">`（前 120/80 字 +
  展开全文），与 gp-thread 面板、trackAgent 卡三处呈现同一事实，改呈现须同步折叠语义。
- **Agent 运行中预览（preview）四重新鲜度校验**：Rust 每次成功 moonviz_op ≥1.5s 推一帧全量 canonical，
  前端 `schedulePreview`/`paintPreview` 同时校验 **run 归属 + preview_seq 序号 + generation + viewEpoch**——
  旧 run 迟到帧、同 epoch 乱序 WASM 返回、终态/切项目后的残留帧一律丢弃；成功终态只 `invalidatePreview()`
  **不 rollback**（rollback 仅用于澄清/零 ops/异常路径且经 serializeProject）。拖拽手势期间 preview 延后
  （gestureActive 时重新 arm），pointerup 后恢复，防止 renderStage 重建销毁 pointer capture。
  test_studio 检查 J 锚定这套结构（preview_seq 调度/generation 校验/终态不回滚/RAF 合帧）。
- **澄清式多轮（CLARIFY-FIRST）**：用户提示词要求「先确认再生成」时，模型以纯文本回复提问
  （不调工具）→ 前端挂入 `#gp-thread` 对话面板，`agentThread.pending` 记住提问；用户回答后，
  前端把「原任务 + 提问 + 回答」拼成新指令重跑 agent。**设计取舍（当前为提示词级实现）**：
  单槽 pending（启发式触发——任何无 ops 的文本回复都视为澄清，未验证模型意图）；失败路径清
  pending（防旧问题污染下一条无关 prompt）；用户主动选过主题等偏好类标记不受影响。
  演进方向：若需 ChatGPT 式连续对话，Rust 侧维护对话历史 + 前端对话视图，与轨迹时间线分离。
- **轨迹文本呈现治理**：同一提示词不再于轨迹中重复全文——tl-user/续轮回答行/assistant 计划行
  均折叠（`<details class="tl-fold">`，120/80 字截断 + 悬停全文）；trackAgent 汇总卡截 90 字。
  画布 SVG 内的用户标签**不参与** kbd 本地化与轨迹折叠（显示文本与 mbt.md 源一致）。
- 返回契约（与已删除的 JS 桥一致，前端依赖）：`{ok, mbt_b64, render, ops[], stopReason, text}`，
  失败时额外带 `partial_error` 且 **`ok` 仍为 true**（已提交的工作不得丢失）。

## 引擎双门（改任何 op 前必须分清）

引擎有**两道门**，能力面并不相同，别把 CLI 直连面上的命令当成 Agent 可用的：

| 路径 | 用途 | 接受 |
|------|------|------|
| `apply-human-mbt-op-b64` | 人类画布操作（前端 inspector） | 变更类 + 全部新语法 |
| `apply-agent-mbt-op-b64` | Agent 单 op | **仅变更类**，只读 op 一律 `mbt_operation_unsupported` |
| `apply-agent-mbt-b64` | 整篇文档提交（前端的"校验并渲染"） | 整篇 canonical，**比 op 路径更严**（真实重叠债会被 `no_sibling_overlap` 拦下） |
| `load-mbt-b64` + op | 只读检视 | 只读命令 |

我在同步时踩到的实例：同一篇文档经人类门累计改动后被 `apply-agent-mbt-b64` 以
`mbt_gate_block:lg:no_sibling_overlap:welcome_title` 拒绝，而人类门逐 op 全都通过——
这是设计意图（Agent 门更严），不是 bug。`validate-mbt-b64`（只校验不提交）与
`canonical-mbt-b64`（只规范化）是本次更新新增的非提交变体，目前前端未用。

## 引擎问题上报（元规则）

**引擎（MoonViz wasm/CLI/MCP）的 bug 或能力缺口，直接到上游仓库提 issue**：
`gh issue create --repo asdshuaishuai/moonviz`。不要在 deepDesign 侧绕过或硬扛，不要只
登记在文档里——两个仓库都是我们的内部项目，**issue 提交后那边会直接跟进修复**。
提 issue 的纪律：

- 必须附**真机证据**：用 `frontend/vendor/moonviz.wasm` 跑最小复现探针（人类门/代理门
  对照、引擎返回 JSON 原文，参照 `scripts/engine-host.mjs` 行协议），不得凭推测报障；
- 同时在本仓库做**登记性缓解**（提示词禁令/可用配方、登记性测试、诚实降级文案），
  并在代码注释或本文件引用 issue 编号——上游修复会让登记性测试变红，驱动本侧回收
  （例：`AGENT_GATE_DEBT` 清单对应 #14）；
- 已提交的引擎 issue 台账（**0.1.6-fix 已修 #19；0.1.6 已修 #17/#18；0.1.5-fix-2 已修 #12/#13/#14/#15**）：
  #19（session_constrain 成功信封不回传 canonical，键控缓存宿主取不回变更→已修：constrain/
  auto_fix/tap/generate_responsive/component_compile 全部改文档面信封带 canonical，本侧
  SESSION_EVICT 机制整体移除、constrain 已接线）、
  #18（place 不接受 w/h→已修：`[w] [h]` 位置参数 + 门评估最终 bbox，真实 LLM run 111 次
  拒绝的根因整类消除，本侧提示词已教新语法）、#17（constrain 意图语法无文档→已修：
  cannot_parse 就地返回 14 种意图词表、SKILL.md 词条重写；本侧已接 session 路由）、
  #11（history——会话内
  全链路可用，arg 槽 `<sub> [artboard]`、须先 `init`、place 不自动入史须显式 `commit`；
  曾误报「不跨会话存活」为引擎缺陷后撤回 [#16](https://github.com/asdshuaishuai/moonviz/issues/16)
  ——历史持久是**宿主职责**，已在 deepDesign 前端实现：编辑期常驻历史会话
  （histEnsure/histCommit/undoMbt/redoMbt），写入全走 `session_apply_*_in`，agent 终态/
  打开/实例回收作为撤销栈边界）、#12（缺 flow 删除 op→`unflow` 已落地，前端流程面板已接
  删除）、#13（节点父子层级不可达→`session_query_nodes` 已带 `parent` 字段，图层树层级
  可重建）、#14（4 模板自带债过 AgentGate→已修，`AGENT_GATE_DEBT` 清空为哨兵、种子引导
  已换回 AgentGate）、#15（代理门背景层死锁→已修，提示词禁令已撤）。
- **撤销/重做边界（引擎 history 按画板分栈，实测语义）**：⌘Z 作用于**当前活动画板**；
  agent 终态回灌、打开 DDP、实例回收（192MB 棘轮）都会重置撤销栈；源码编辑器的**已提交**
  编辑同样会重置栈（提交即外部变更），未提交草稿走文本撤销。多板全局线性撤销待上游
  history 持久化方向明确后评估。

## 前端约定（`frontend/index.html`，单文件 ~3000 行）

- 只有**一个**内联 `<script>`，全局可变状态集中在文件顶部（`nodes/selected/mbtText/sessions/active/...`）。
- **所有会改项目的操作必须经 `serializeProject(task)` 串行化**（`projectQueue` 链）。绕过它会产生竞态。
- **i18n（七语言，键源=zh-CN）——生成闭环**：字典键清单 `scripts/i18n-full.json` + 移植/新增翻译
  `scripts/i18n-extra.json`（均由 `node scripts/i18n-catalog.cjs` 对账生成，live-only 键自动移植防丢译，
  T 表重复键直接失败）；`python scripts/gen-i18n.py --write` 重建 `frontend/index.html` 的
  `I18N_GENERATED_START/END` 标记块（`--check` 只校验漂移、CI 可用；原子写回 + 六语言键集合自检）。
  **不要手改标记块内字典**——改 T 表/extra 后重跑生成器。`applyI18n()` 是**快照式**切换——I18N_ORIG
  WeakMap / dataset 存 zh-CN 原文，任何语言→任何语言都从快照出发（当前 DOM 文本可能是上一语言译文，
  直接查键=简中的字典必失败）；切回简中=恢复快照。`L()` 是动态文案 choke 点（toast/确认框/过滤器 label
  等出生即译），带变量的用 `Lfmt('…{id}…',{id})` 模板键（拼好整句查字典永远查不中）；`I18N_RERENDER`
  注册表让出生即译节点随 setLang 重渲染，`i18nSoon()`/MutationObserver 是渲染出口兜底。
  **applyI18n 排除 `#stage`/`#decl-stage`**：画布 SVG 用户文本与 MBT 源码高亮是数据，不是 UI——
  越界翻译会造成「画布显示≠mbtText」的显示漂移。原生菜单经 `set_menu_language`（`menu_t` 七语言标签表，
  **元组方向必须是 `(译文, zh-CN key)`**——写反即静默回退简体，2026-09 真实事故）。系统确认框统一走
  前端 `confirmDiscard()`（唯一 invoke 点，按钮/文案经 L()；deleteBoard 传自定义 ok/cancel），Rust
  `confirm_discard`/`save_ddp`/`open_ddp`/`save_text_file` 的 label 参数为 `Option<String>` 回退中文，
  **Rust 不持有第二套 locale 表**。多窗口偏好经 `storage` 事件白名单同步 `dd-lang`/`dd-theme`/`dd-mode`
  （应用与持久化分层，防回写循环）。test_studio 检查 K 锚定以上结构。
  **事故登记：applyI18n 曾被文件尾部旧定义静默遮蔽**（后者胜出=无快照无简中恢复），test_studio 检查 I 现在
  禁止任何函数重复定义（变异验证过必红）。
- 引擎命令的 payload 一律 b64：`utf8ToB64` / `b64ToUtf8`。
- 命令名 → invoke 参数的命名转换由 Tauri 负责：前端传 `mbtB64`，Rust 侧形参是 `mbt_b64`。
- **画板 / 节点 id 必须是 ASCII snake_case**，且这是**约定而非引擎保证**：引擎的 `sanitize_id`
  只在画板创建路径（`core/project.mbt` 的 `create_artboard`）被调用，**节点 id 不清洗**——
  `place`/`copy` 传什么就是什么。实测 `place … 'x"><img src=y onerror=…>'` 会被原样写进
  `export-svg` 的 `<g id="n_…">`，突破属性引号。所以：中文名会碰撞（画板侧），
  而节点 id 是**不可信字符串**，拼进 `innerHTML` 前必须转义（见 `escHtml`）。
- 拖拽、内联编辑、连接模式等交互最终都要落成一条引擎 op，不要在前端本地改 `nodes` 数组了事。

## 测试的脆弱点

- `test_studio.cjs` 有**两道防线**，改测试前先分清：
  - **静态防线（4 道断言）**：内联 HTML 处理器引用的函数必须有定义；`INTERACTIVE_SURFACE`
    清单（39 个交互层函数）必须全部在场；测试自身的 stub 名单不得掩盖不存在的定义；
    `lib.rs` 的原生菜单 id 必须全部被 `nativeMenuAction` 映射；检查 F 守卫启动期自动执行
    （引用 runGlobalPrompt 的 setTimeout/setInterval 只允许在 dd-dev-autorun 开关门内）；
    检查 G 锚定 fmAct/nativeMenuAction 的字符串分发目标必须真实在场。这几道是**为历史事故专门加的**（见下）。
  - **动态防线**：靠字符串切片取真实状态机——`indexOf("const APP_VER")` 到
    `indexOf('function mbtResult(')` 划区段，再 `indexOf('function NAME(')` 逐函数抽。
    动这些标记、改函数名、或把签名写成非 `function name(` 形式，都会让它**静默取到错东西**。
- Rust 端到端测试的跳过门已收紧：**wasm 产物缺失 → 合法跳过**（eprintln 提示）；
  **产物在场但宿主/编解码调用失败 → panic**（静默跳过曾把 codec 损坏伪装成绿灯，变异实验实证）。
  受影响的 10 个引擎门测试：`wasm_engine_surface_contract`、`template_ids_match_engine`、
  `agent_loop_with_mock_llm_and_real_engine`、`agent_loop_anthropic_protocol_with_mock_llm_and_real_engine`、
  `agent_loop_readonly_op_via_session_api`、`session_api_host_contract`、
  `mid_run_llm_failure_preserves_committed_work`、`readonly_session_gets_render_fallback`、
  `session_count_zero_after_close`（会话泄漏契约）、`agent_session_cache_reuse`（会话缓存命中，
  经行协议宿主的 session_cache_stats 断言，变异验证过必红）。
  判断方法：`cargo test -- --nocapture` 看跳过输出（默认输出会吞掉通过测试的 stderr），或数条数（当前 43）。

## 删前端代码前必读（真实事故，勿重演）

提交 `9f48220`（"purge dead code"）声称只删了「7 个零调用函数」，实际删掉 **33 个函数定义**，
其中 **14 个仍被引用**（约 40 处调用点）。后果：应用能正常启动，但一点画布就 `ReferenceError`——
**选择功能结构性失效**（`select()` 是唯一写入真实节点 id 的地方，它没了则 `selected` 恒为 `null`，
inspector 永久空态），`renderStage` 每次渲染都在 `bindStageSvg` 处中断，
新建画板/模板/快速开始全部误报失败，打开 DDP 直接损坏，原生菜单静默变哑。恢复代码取自已发布的前一提交 `9b8804f`,落地提交是 `c93117d`。

从这次事故总结的硬性规则：

1. **不要在 `frontend/index.html` 里批量删"死代码"。** 它没有打包器、没有 linter、没有类型检查，
   唯一的防线是 `test_studio.cjs` 的静态断言。删任何函数前先确认零引用。
2. **只扫 `name(` 形式会漏掉引用。** 被漏掉的正是 `onDown`/`onCtx`（在 `bindStageSvg` 里
   **以值**传给 `addEventListener`）和 `nodeOf`（`const` 箭头函数）。必须以"任意作用域的绑定"
   来判定，不能只找调用点。
3. **测试替身是盲区。** 当时 `test_studio.cjs` 恰好 stub 了 `updateSel`/`closeAgentPop`/`cancelInline`
   三个被删函数，等于替身顶替了真身，所以测试全绿。现在检查 C 强制"凡 stub，真身必须存在"。
4. **带 `typeof` 守卫的跨文件调用会静默失效。** `lib.rs:370` 用
   `if(typeof nativeMenuAction==='function')nativeMenuAction(...)` 调用前端——缺失时既无报错也无日志，
   纯前端自测永远发现不了。检查 D 就是为此设的。
5. **不要为了"清理"而把 parity 断言改成自己比自己。** `9f48220` 把 `test_studio.cjs` 的读取目标
   从根 `index.html` 改成 `frontend/index.html`，于是 `assert.equal(readFileSync(...), html)` 变成恒真式。
   该恒真断言已删除，改为断言 `tauri.conf.json` 的 `frontendDist === "../frontend"`。
6. **调试用的自动执行代码不许提交为无条件形态。** 72e942d 提交了露营 e2e 的前端残留
   （`setTimeout(…,1500)` 无条件 `runGlobalPrompt()`，注释自承"测试完删除此块"），每次启动
   都自动跑一次真实 LLM run。它能逃过全部防线的原因：vm 动态切片**不执行脚本尾部**。
   已删（露营链路由 `src-tauri/tests/agent_llm_e2e.rs` 的 CAMPING_E2E 环境门覆盖）；前端侧
   启动期自动执行只允许走 `dd-dev-autorun` 开关门（一次性用后即焚），检查 F 静态锚定
   （变异验证过）。新教训：**外部驱动的端到端测试用 localStorage 传指令 + 开关门，不写死代码**。
7. **CI 现状**（windows-build.yml，2026-09 起）：tag `v*` / 手动触发时跑
   `test_studio.cjs` + `cargo test --release` + `tauri build`——**普通 push/PR 不跑任何 CI**。
   本地改动前端后务必手动 `node test_studio.cjs`。

## 多项目（已落地，2026-09）

- **数据流**：最近项目注册表存 localStorage `dd-recent-projects`（path/name/ts，容量 10）；
  启动与渲染前经 `list_ddp_projects` 按父目录批量对账（剔除已删文件、刷 mtime）。
  呈现位三处：欢迎空态「最近项目」区 + 文件菜单顶部动态区 + **左栏顶部常驻项目区**
  （当前项目名 + ＋新建/打开 + 最近列表，空态给引导文案——多项目入口永远可见）。
  原生菜单 `open-recent` 打开同一列表。
- **切换 = 下拉热切换**：项目名（▾）点击弹最近项目下拉，行点击 `openProject(path)` 就地切换
  （不重启应用）；当前项目标 ✓。免对话框口令：先静默试 per-path 会话口令映射与空口令
  （DDP2 免密），解密失败才弹密码框——口令映射是内存态，不持久化明文。⌘O 对话框流程保持
  「先密码后选文件」。agent 在飞（agentBusy）时切换仍拦截。
- **多窗口（2026-09）**：最近项目行 ⧉ 按钮 → `open_project_window` 命令建 `proj-<epoch>` 窗口，
  URL 带 `?project=<percent-encoded path>`；前端引擎就绪后读取该参数自动免对话框打开
  （openProject 对同 path 幂等跳过——?v= 缓存重载会二次触发）。支撑性改造：
  - 脏态按窗口 label 记（`DIRTY_WINDOWS: LazyLock<Mutex<HashSet<label>>>`，
    `set_project_dirty` 经注入的 window 取 label）；CloseRequested 按本窗 label 拦截。
  - 原生菜单动作派发给**聚焦中的**窗口（fallback main）。
  - `agent-event` 轨迹经 `emit_to(发起窗口 label)` 投递，不广播串窗。
  - EngineHost 会话缓存全进程共享（mbt 键控）：多窗交替 agent run 会互踢缓存——
    正确性无损（键不符即重开），仅性能交替重解析。
- **保存 vs 导出边界（防错文件事故）**：`exportDdpNow` 仅在 `filePath` 为空（项目从未保存，
  导出即首次保存）时接管 `filePath`/会话口令；已绑定项目的导出是纯副本，不改绑 ⌘S 目标。
- **标题同步**：`syncProjName` 统一更新 `#proj-name` / 侧栏项目名 / `document.title` / 原生窗口标题
  （capabilities 增了单条 `core:window:allow-set-title`）。注意它位于 vm 动态切片区间内
  （newProject 会调），移位需同步 test_studio.cjs。
- **边界（有意不做）**：切换重置撤销栈是引擎 history 边界；同项目双窗口同时编辑无冲突检测
  （后保存者覆盖，用户自行避让）。
- **已知问题（待查）**：ad-hoc 签名的 bundle 经 `open` 启动偶发**白屏**（LaunchServices/签名
  相关，直跑 `target/release/deepdesign-studio` 二进制从未复现）；且每次重建 ad-hoc 重签会使
  TCC「文稿」授权失效、启动必弹权限框。正式分发需 Developer ID 签名一并解决。

## 已知缺口

- 原生菜单桥已随 `9f48220` 事故一并修复：`nativeMenuAction` 已在前端实现，id → 函数映射由
  `test_studio.cjs` 检查 D 锁定（从 `lib.rs` 解析菜单 id，逐个断言已被映射）。
  改菜单时**同时**更新 `lib.rs`、前端映射表与 `docs/menus.md`（链路：`lib.rs::on_menu_event`
  经 `win.eval("nativeMenuAction(id)")` 直调前端全局函数；`event.listen` 曾因 Tauri ACL
  未放行而弃用——menus.md 已按此修正）。
- **Agent 运行日志（宿主侧可诊断性）**：每次 agent run 落一个 JSONL——
  `app_data/logs/agent-<epoch>-<runid>.jsonl`（macOS 为
  `~/Library/Application Support/com.deepcode.deepdesign/logs/`），run_start 头 + 每个事件
  （工具调用/结果/错误，含 ts 与 run id）+ run_end 尾；保留最近 50 个。排障时直接读最新
  文件，stderr 的 `[agent]` 行是同一事件流的控制台镜像。
- **~~Agent 长任务与人类编辑的丢失更新~~（已解决，2026-09）**：run 起点快照语义保留，
  终态应用前前端比对起点快照——画布被人类编辑推进时把 run 的变更 op 流重放到最新
  canonical（`rebase_agent_ops` 命令，AgentGate 逐条重校验、拒绝即跳过并报告，只读 op
  过滤）。设计决策记录与事实基础见 `docs/agent-rebase.md`。run 中画布编辑现在是安全操作；
  **在飞门（agentBusy）对 run 中新建/打开的拦截保留**（整文档替换超出 rebase 范围）。
- **~~工具结果无截断~~（已解决，2026-09）**：三层确定性裁剪已落地（`docs/agent-context.md`）——
  L0 源头整形（read_mbt 剥 `mbt check` 围栏块、export-* 信封化、检视类 12KB 截断）、
  L1 去supersede（旧 read_mbt/list_components 结果占位化）、L2 预算守卫（**逐模型窗口**：
  models.json `limit.context`，`model_context_window` 按 `/` 末段精确匹配 + 16K 下限，
  未命中回落 128K；超 70% 激进裁剪，context_usage 轨迹事件）。硬边界：只缩 tool 消息 content 绝不删消息
  （tool_call_id 配对是 wire 硬约束）；前端终态 mbt_b64 仍交付完整 canonical；id 可见性由
  真机 e2e（`agent_loop_read_mbt_shaping_keeps_ids`）锚定。LLM 摘要压缩与逐模型窗口贯通是演进方向。
- **vendored DDP 长度门潜在不一致**：`vendor/moonviz-ddp` 全局门 `16MiB+16` 与 DDP1 专属门
  `16MiB+45` 不一致（当前不可达——8MiB 明文压缩后到不了 16MiB；上调明文上限时会先撞全局门）。
  **不改**：vendored 副本与上游 `../moonviz` 按 md5 对账（README 记录基线 commit），改它破坏同步保真——应上游修。
- **apiKey 明文存 localStorage**（按服务商分槽：`deepdesign-fx-providers` map + `deepdesign-fx-active` 当前启用项；旧单槽 `deepdesign-fx-config` 首次自动迁移）：桌面单用户场景的常见做法，但与 Rust 侧
  Zeroizing 的谨慎不一致；改为 OS keychain 属增强项，未排期。
- **用户组件库三入口（画板沉淀 `saveAsComponent` / MCF 导入导出）仍是诚实降级 stub**
  （`USERCOMP_UNAVAILABLE` 提示）：引擎 session 面已导出 `session_component_compile_b64` /
  `session_library_snapshot`，但用户组件注册表只存活在**会话内**——画布是无状态 per-op
  路径、会话缓存轮换即丢；持久化模型（引擎侧全局注册表导出 vs 文档嵌入）未决，接线前先定设计。
- 根目录那份 2412 行的 `index.html` 旧副本已在 `9f48220` 删除，确认无任何引用
  （`tauri.conf.json` 的 `frontendDist` 指向 `../frontend`）。前端只有 `frontend/index.html` 一份。

## 安装纪律（唯一副本）

- **本机任何时刻只允许存在一份 deepDesign Studio**。安装/更新一律走
  `scripts/install-app.sh`（先停实例 → 弹残留 DMG 挂载 → 注销全部 LaunchServices 注册 →
  删旧副本（含 target 内 dev bundle）→ 暂存新包 → 安装 → 重签 → 注册 → 验证
  磁盘副本=1 且注册=1 → 启动）。**禁止手动 cp 到 /Applications**——手动拷贝绕过注册清理，
  正是历史 31 条幽灵注册（Spotlight 出现多个 deepDesign）的来源。
- 运行级单实例由 `tauri-plugin-single-instance` 保证：二次启动（任何路径来源，含 DMG 卷内
  副本）只聚焦既有主窗，不并跑（已实测 `open -a` ×3 与 DMG 副本启动均单进程）。
- `install-app.sh --uninstall` 彻底卸载；`--uninstall --purge` 连用户数据目录一起清。

## 发布完整性（用户决策，2026-10-07 修订）

- **每次发布包含四个资产**：Windows NSIS / macOS DMG / Linux deb / AppImage（release-all.yml
  tag 触发自动构建上传）+ **鸿蒙 app.zip**（CI 无 AGC 签名材料——走本机 `ohos/ohos-release.sh`
  签名打包后 `gh release upload` 手动补传，.app 用 zip 容器因 GitHub 禁 .app 后缀附件）。
- **玲珑（linyaps）支持已移除（用户决策 2026-10-07）**：Linux 只保留 deb + AppImage。
  linglong/ 目录、docs/linglong-package.md、ci-install-linyaps.sh 已删除；当时的构建
  纪律与离线手术法完整快照在 git 历史（tag `archive/harmonyos-port` 前后区间均可考）。

## 版本号（单一事实源，用户决策 2026-10-09）

- **仓库根 `VERSION` 文件是版本号唯一权威**，只写一个语义化版本号。完整清单与派生链见
  [docs/versioning.md](docs/versioning.md)。
- **改版本 = 改 `VERSION` 一个文件，然后跑 `node scripts/sync-version.mjs`**，
  它把版本写进 16 个下游面（tauri.conf / Cargo.toml×2 / Cargo.lock×2 / APP_VER /
  鸿蒙 app.json5 + ArkTS chip + ohpm 包×3 + rawfile 镜像 / README / menus.md / AppStream）。
  `--check` 只校验漂移，`test_studio.cjs` 检查 M 已把它纳入测试门。
- **每次发布后在 AGENTS.md 顶部「当前版本」处写明版本号与发布日期**（本次：0.4.1 / 2026-10-09），
  并同步更新构建内版本号——即跑一次 `sync-version.mjs`，两边都是同一次改动的一部分。
- **不要手改下游面的版本号**：手改会在下一次 `--check` 变红，也可能让某个产物悄悄停在旧版本
  （2026-10 的 v0.4.1 实测：鸿蒙包与 AppStream 停在 0.4.0，桌面显示 0.4.1，用户看到哪个
  取决于装的是哪个包）。改下游面一律经 VERSION + 脚本。
- 鸿蒙 `versionCode` 是 AGC 强制递增的整数面，按 `minor*100+patch` 由脚本派生
  （0.4.1 → 401）；跳大版本时脚本会警告，需人工复核约定。

## 提交与文档

- 提交信息用 Conventional Commits + 英文 subject：`feat(agent): ...` / `fix(studio): ...` /
  `chore: ...`。scope 常用 `agent` / `studio` / `ui` / `engine` / `bundle`。
- `docs/menus.md`：原生菜单 + 右键菜单的文案与动作映射，改菜单必读。
- `docs/harmonyos-port.md`：鸿蒙适配方案（**仅方案未实施**；Rust 侧工具链已在
  Linux 就位：ohrs + aarch64-unknown-linux-ohos target）。
- `docs/plan-cli-mcp.md`：**1.0 规划**（本分支跟进）——deepDesign Agent 能力抽象为专属
  CLI + MCP 出口，让 Codex/Claude Code 直接驱动 deepDesign；前置是 deepdesign-core 拆分
  （与鸿蒙方案共享同一前置）。
- `docs/plan-lan-share.md`：内网分享规划（建议 0.4.x）——export_html + 内嵌 HTTP 服务，
  浏览器只读查看，免装 ddpView；serve-fresh-per-GET 设计，安全清单逐条锚定。
- `docs/versioning.md`：**版本号单一事实源**——`VERSION` 文件 + `sync-version.mjs` 同步的
  16 个下游面清单、鸿蒙 versionCode 约定、发布流程。改版本号前必读。
- `README.md`：架构速览与打包产物说明。
