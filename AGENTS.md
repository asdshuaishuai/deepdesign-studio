# AGENTS.md — deepDesign Studio

AI 原生原型设计工具的桌面客户端（Tauri 2 + Rust）。**唯一事实源是 MoonViz 引擎的 `.mbt.md` 文档**：
人类画布操作与 Agent 修改都必须经引擎校验（HumanGate / AgentGate）后回写同一份文档，
`.ddp` 只是它的认证加密容器。

## 三层架构与边界（改代码前先读）

```
frontend/index.html        纯静态单文件前端（无打包器、无 HTTP 层）+ 画布侧 wasm 引擎实例
src-tauri/src/lib.rs       Tauri 命令层：invoke_fx_sdk / save_ddp / open_ddp / model_registry + EngineHost
src-tauri/src/wasmtime_host.rs  wasmtime 进程内引擎宿主（纯 Rust 运行时，agent 循环与 cargo test 共用）
src-tauri/src/agent.rs     进程内 Agent 循环（OpenAI/Anthropic 工具调用 × wasmtime 引擎宿主）
scripts/sync-engine.mjs    引擎产物同步：GitHub Releases 拉标准 classic wasm → sha512 校验 → 真机契约探针 → frontend/vendor/
vendor/moonviz-ddp/        vendored DDP 编解码 crate（引擎仓库 MIT 副本，见其 README）
docs/upstream-engine-ask.md  wasmtime 宿主立项 → **已实施**（上游 classic 变体落地后接入，保留作背景与消费侧清单）
```

必须守住的边界：

- **前端只能经 `window.__TAURI__.core.invoke` 调上面 4 个命令**，没有 HTTP 层，不要引入 fetch/axios。
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
  真机契约探针（7 经典/4 检视/26 session 导出 + 模板/组件/会话计数）。字符串是 linear memory
  对象（[refcnt@ptr-8][长度@ptr-4][UTF-16LE@ptr+0]），宿主侧编解码（sync/wasmtime_host/
  前端三处同构）；写入区锚在「当前内存大小+余量」之上，引擎 bump 堆顶不超过当前内存
  大小，故永不碰撞。
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
./dev.sh                          # debug 编译启动（Windows 用 Git Bash，或手动 npx @tauri-apps/cli dev）
npx @tauri-apps/cli build         # 打包（beforeBuildCommand 自动 sync-engine）
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
86 模型，~48KB，随版本库提交）。MIT 许可，vendored 而非运行时拉取（离线桌面 + 依赖极简）。

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
清单块是文档镜像，不再有契约测试锚定——skill_dictionary 测试已随 wasm 重构删除）。**引擎仓库只读，不改引擎，
以产物行为为准。**对账的权威来源不是引擎的 `help` 文案，而是实际行为：

```bash
node scripts/sync-engine.mjs    # 产物缺失时先同步；契约探针同时校验导出面/模板/组件/会话计数
node scripts/engine-host.mjs    # node 直查工具（调试用；Rust 侧已不依赖——wasmtime 宿主是唯一运行时）
```

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
- **无 capabilities 目录是常态**：前端不用任何 ACL 管辖的 core 面（事件桥已随 wasmtime
  宿主删除）；自定义命令不经 ACL。别为"以防万一"加 capability。
- 依赖刻意保持精简。引入类型化 chat 客户端（如 async-openai）已被评估否决：thinking 家族等非标字段
  必须在序列化后注入，类型层反而被绕过。Rusty V8（进程内 JS 引擎宿主）已被评估并**否决**：
  +30~80MB 安装包税 + 依赖链脆弱（temporal_rs/icu_calendar 编译断裂实证）；**wasmtime 为最终
  形态**（classic wasm 宿主中立使然，见 `docs/upstream-engine-ask.md`）。

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
- **`READONLY_OPS` 是只读路由表**（20 项：清点类 `list`/`list-templates`/`list-components`/
  `list-tools`/`list-tokens`/`list-themes`/`flows`/`benchmark`；检视类 `lint`/`critique`/`query`/`infer`/
  `spec`/`missing`/`doc-json`/`states`/`interactions`/`export-svg`/`export-html`；模拟类 `tap`）：
  engine-v0.1.1-fix 的 **session API 已导出检视面**——命中即走只读路由（session API 或直调导出），
  不进 apply 分发器。此前该表是「wasm 面不可达」拦截名单，现已转回路由白名单语义（注释处的预言成真）。
  **例外**：`list-tools` 与 `doc-json` 无对应 wasm 导出，命中返回 `wasm_engine_export_unavailable`
  （诚实报错，不假装可用）。变更类 op 绝不能进表——会被只读分支拦下而非提交。
  注意：`list_components` 作为**工具**仍可用（agent.rs 经宿主取 components.json 快照），
  路由的是同名 **op**。
- **`constrain` 和独立 `name` op 在 apply 门上不可达**：走 apply-human/apply-agent 均返回
  `mbt_operation_unsupported`；但 **session API 已导出 `session_constrain`**（agent.rs 暂未接入，
  需要时经 session 路由可达）。改节点名要用 `update <ab> <node> name=<id>`，不要教 Agent 用 `name`。
- **`INSTRUCTIONS` 与 `ENGINE_TEMPLATES` 必须与引擎同步**（`template_ids_match_engine` 测试锚定 id 集合，
  `prompt_avoids_apply_rejected_ops` 锚定新语法在场）。提示词漏一个模板 Agent 就永远不选它，
  多一个它就会猜不存在的 id。模板尺寸以引擎实际产出为准——`pc_app` 是 1280×800，不是提示词里曾写的 1440×900。
- `safe_base_url` 有 SSRF 防护：仅放行 https 与 localhost/私有网段 http（IP 段是精确判定，
  `172.20.x` 放行、`172.2.x`/`172.255.x` 拒绝，DNS 前缀伪装如 `10.evil.com` 拒绝）。改动时守住单测。
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

## 前端约定（`frontend/index.html`，单文件 ~2500 行）

- 只有**一个**内联 `<script>`，全局可变状态集中在文件顶部（`nodes/selected/mbtText/sessions/active/...`）。
- **所有会改项目的操作必须经 `serializeProject(task)` 串行化**（`projectQueue` 链）。绕过它会产生竞态。
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
    清单（36 个交互层函数）必须全部在场；测试自身的 stub 名单不得掩盖不存在的定义；
    `lib.rs` 的原生菜单 id 必须全部被 `nativeMenuAction` 映射。这几道是**为历史事故专门加的**（见下）。
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
  判断方法：`cargo test -- --nocapture` 看跳过输出（默认输出会吞掉通过测试的 stderr），或数条数仍是 24。

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
6. **CI 现状**（windows-build.yml，2026-09 起）：tag `v*` / 手动触发时跑
   `test_studio.cjs` + `cargo test --release` + `tauri build`——**普通 push/PR 不跑任何 CI**。
   本地改动前端后务必手动 `node test_studio.cjs`。

## 已知缺口

- 原生菜单桥已随 `9f48220` 事故一并修复：`nativeMenuAction` 已在前端实现，id → 函数映射由
  `test_studio.cjs` 检查 D 锁定（从 `lib.rs` 解析菜单 id，逐个断言已被映射）。
  改菜单时**同时**更新 `lib.rs`、前端映射表与 `docs/menus.md`（链路：`lib.rs::on_menu_event`
  经 `win.eval("nativeMenuAction(id)")` 直调前端全局函数；`event.listen` 曾因 Tauri ACL
  未放行而弃用——menus.md 已按此修正）。
- **Agent 长任务与人类编辑的丢失更新**：agent run 以请求起点的 `mbtText` 快照驱动
  （Rust 侧 EngineState 每请求重建），秒级窗口内人类提交的 op 会被 agent 终态整体
  覆盖。修法需要 rebase/合并机制（把 agent 的 op 流重放到最新 canonical），属设计决策；
  交互缓解：agent 执行期间避免并发编辑。
- **工具结果无截断**：`read_mbt`/export 类结果全量入 LLM 历史（引擎 canonical 的
  `mbt check` 块把节点声明重复第二遍，有效载荷约 2 倍），多屏任务 token 成本随轮次
  线性膨胀。截断会伤模型对文档 id 的可见性——分层裁剪方案未决。
- **vendored DDP 长度门潜在不一致**：`vendor/moonviz-ddp` 全局门 `16MiB+16` 与 DDP1 专属门
  `16MiB+45` 不一致（当前不可达——8MiB 明文压缩后到不了 16MiB；上调明文上限时会先撞全局门）。
  **不改**：vendored 副本与上游 `../moonviz` 按 md5 对账（README 记录基线 commit），改它破坏同步保真——应上游修。
- **apiKey 明文存 localStorage**（`deepdesign-fx-config`）：桌面单用户场景的常见做法，但与 Rust 侧
  Zeroizing 的谨慎不一致；改为 OS keychain 属增强项，未排期。
- **用户组件库三入口（画板沉淀 `saveAsComponent` / MCF 导入导出）仍是诚实降级 stub**
  （`USERCOMP_UNAVAILABLE` 提示）：引擎 session 面已导出 `session_component_compile_b64` /
  `session_library_snapshot`，但用户组件注册表只存活在**会话内**——画布是无状态 per-op
  路径、会话缓存轮换即丢；持久化模型（引擎侧全局注册表导出 vs 文档嵌入）未决，接线前先定设计。
- 根目录那份 2412 行的 `index.html` 旧副本已在 `9f48220` 删除，确认无任何引用
  （`tauri.conf.json` 的 `frontendDist` 指向 `../frontend`）。前端只有 `frontend/index.html` 一份。

## 提交与文档

- 提交信息用 Conventional Commits + 英文 subject：`feat(agent): ...` / `fix(studio): ...` /
  `chore: ...`。scope 常用 `agent` / `studio` / `ui` / `engine` / `bundle`。
- `docs/menus.md`：原生菜单 + 右键菜单的文案与动作映射，改菜单必读。
- `README.md`：架构速览与打包产物说明。
