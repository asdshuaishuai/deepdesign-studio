# AGENTS.md — deepDesign Studio

AI 原生原型设计工具的桌面客户端（Tauri 2 + Rust）。**唯一事实源是 MoonViz 引擎的 `.mbt.md` 文档**：
人类画布操作与 Agent 修改都必须经引擎校验（HumanGate / AgentGate）后回写同一份文档，
`.ddp` 只是它的认证加密容器。

## 三层架构与边界（改代码前先读）

```
frontend/index.html        纯静态单文件前端（无打包器、无 HTTP 层）
src-tauri/src/lib.rs       Tauri 命令层：exec_cli / save_ddp / open_ddp / invoke_fx_sdk / diagnostics
src-tauri/src/agent.rs     进程内 Agent 循环（OpenAI chat-completions 工具调用 × 引擎管道）
../moonviz                兄弟仓库：MoonBit 引擎源码 + ddp crate（引擎二进制从这里来）
```

必须守住的边界：

- **前端只能经 `window.__TAURI__.core.invoke` 调上面 5 个命令**，没有 HTTP 层，不要引入 fetch/axios。
- **Rust 不解释视觉语义、Markdown 或 MoonBit block**。它只做三件事：b64 搬运、进程编排、DDP 加解密。
  任何"顺手在 Rust 里改一下布局/属性"的做法都越界了——变更必须回到引擎。
- **人类操作与 Agent 操作走不同引擎入口**，两条门的能力面不同（详见下文「引擎双门」表），
  不要为了省事统一成一个。
- **引擎只走独立二进制，无 `moon run` 回退**。定位顺序（`lib.rs::engine_cli_binary`）：
  `MOONVIZ_CLI` 环境变量 → `src-tauri/engine/moonviz-cli.exe`（打包 resources）→
  `../moonviz/_build/native/release/build/cli/cli.exe`（dev）。
- 引擎协议是 **stdin 写命令 / stdout 读 JSON 行**。前端用 `fObj(rs,key)` / `fArr(rs)` 在结果数组里找目标对象。

## 常用命令

**Rust 命令必须在 `src-tauri/` 下执行**——仓库根目录没有 `Cargo.toml`，也没有 `package.json`。

```bash
cd src-tauri && cargo test        # 10 个测试：方言表 + 路由白名单 + base_url 策略 + 4 个引擎契约（含 SKILL 字典契约）+ 3 个端到端
cd src-tauri && cargo build
node test_studio.cjs              # 前端状态机冒烟（在仓库根跑）
node scripts/sync-models.mjs     # 模型元数据快照同步（models.dev → src-tauri/models.json）
./dev.sh                          # debug 编译启动；引擎二进制缺失时自动 moon build
./dev.sh --fresh                  # 先 kill 旧进程 + 清 WebView 缓存
npx @tauri-apps/cli build         # 打包（beforeBuildCommand 自动 staging 引擎二进制）
```

仓库**没有配置 lint / formatter**（无 rustfmt.toml、clippy 配置、eslint、prettier）。
2021 edition，形态上跟随既有代码即可。

## 同步引擎更新（引擎在兄弟仓库迭代后必做）

`src-tauri/engine/` 已被 gitignore，所以引擎二进制**不进版本库**——本地靠下面这套流程对齐，
CI 则直接 checkout 引擎仓库 `main` 现场构建。引擎改了就重跑：

```bash
cd ../moonviz && moon build --release --target native cli   # 产物 _build/native/release/build/cli/cli.exe
cd ../deepDesign && node scripts/sync-engine.mjs            # staging 到 src-tauri/engine/
shasum -a 256 src-tauri/engine/moonviz-cli.exe ../moonviz/_build/native/release/build/cli/cli.exe  # 两值必须相同
```

`moon build` 若报 `no work to do` 说明构建图已最新；此时 `_build` 里的产物就是当前源码的产物，
直接同步即可。同步后**必须重跑 `cargo test`**——引擎契约测试会拿真实二进制校验白名单与模板清单。

## 同步模型快照（models.dev，与引擎无关的另一条对账线）

`src-tauri/models.json` 是 models.dev api.json 的**裁剪快照**（仅 11 个预设提供商 /
86 模型，~48KB，随版本库提交）。MIT 许可，vendored 而非运行时拉取（离线桌面 + 依赖极简）。

```bash
node scripts/sync-models.mjs    # 重新生成快照（更新 fetched_at）
cargo test                      # 三个契约测试必须仍绿
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

**`SKILL.md`（仓库根）是本仓库的引擎能力字典**——vendored 自 `../moonviz/SKILL.md` 并双向同步。
分层事实源：**变更 op 层由引擎 `list-ops` 输出直接接管**（OpEntry 注册表，含 usage/category/gates，
测试直接消费并与探针表双向比对——引擎新增 op 而无人采纳会红）；**readonly / cli_only 两层暂无
引擎输出**，由 SKILL.md 文末清单块锚定并与 `READONLY_OPS` 严格相等。引擎更新后的对账顺序：
重跑 SKILL.md 文末附录的探针 → `list-ops` 有新 op 就加探针 + 写进提示词 → 更新 SKILL.md 两层清单 →
`skill_dictionary_matches_engine_and_agent` 强制全链一致。**引擎仓库构建阶段只读，不改引擎，
以二进制行为为准。**对账的权威来源不是引擎的 `help` 文案，而是实际行为：

```bash
printf 'help\nexit\n' | src-tauri/engine/moonviz-cli.exe          # 命令总览
printf 'list-tools\nexit\n' | src-tauri/engine/moonviz-cli.exe    # Agent 工具面
printf 'list-templates\nexit\n' | src-tauri/engine/moonviz-cli.exe
```

## 硬性环境约束

- **兄弟目录 `../moonviz` 必须存在**。`Cargo.toml` 有 `moonviz-ddp = { path = "../../moonviz/ddp" }`，
  缺失则连编译都过不去。CI 里通过把引擎仓库 checkout 到工作区旁来对齐这个路径。
- **改 `frontend/` 后 `tauri dev` 不会热更**（它只 watch `src-tauri/`）。需在窗口按 ⌘R，
  或用 `./dev.sh --fresh`。`lib.rs` 里还有一段强制 `?v=<timestamp>` 重载，是为了绕 WKWebView 缓存——
  不要删。
- **CSP 在 `src-tauri/tauri.conf.json`**（`script-src 'self'`，无 `unsafe-inline`）。Tauri codegen 在
  构建期为非空内联 `<script>` 自动注入 sha256 hash，所以 `frontend/index.html` 里那一大坨内联脚本没问题；
  新增内联脚本同样会被自动 hash，但**不要**改成外部 module script。
- 依赖刻意保持精简。引入类型化 chat 客户端（如 async-openai）已被评估否决：thinking 家族等非标字段
  必须在序列化后注入，类型层反而被绕过。新增依赖前先确认真的绕不开。

## Agent 基座约定（`agent.rs`）

- **思考等级方言表是 `thinking_extra_body(model, level)`**，按模型名分部匹配：GLM-5.3 强制思考（仅 low/high/max）、
  GLM-5.2 及更早开关+全档、Kimi k3 恒开（off→none）、Kimi k2.x 仅开关、MiniMax 仅开关、
  StepFun 三档无开关、DeepSeek 开关+全档、Qwen 仅 vLLM 方言 off、未知模型直传 OpenAI 标准字段。
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
- **只读 op 白名单是 `is_readonly_op`**，它是**路由契约而非便利表**：引擎的 `apply-agent-mbt-op-b64`
  只接受变更类操作，任何没进这张表的只读 op 都会硬失败 `mbt_operation_unsupported`。
  当前 20 项（清点类 `list`/`list-templates`/`list-components`/`list-tools`/`list-tokens`/`list-themes`/
  `flows`/`benchmark`；检视类 `lint`/`critique`/`query`/`infer`/`spec`/`missing`/`doc-json`/`states`/
  `interactions`/`export-svg`/`export-html`；模拟类 `tap`）。
  两点坑：**`fix` 必须留在表外**——引擎在 apply 路径为它实现了"违规严格下降才提交"的还债语义，
  走只读管道会静默丢弃变更;反之**变更类 op 绝不能进表**（`state`/`interact`/`group`/`responsive`/
  `token` 等），否则变更被丢弃且不报错。`readonly_whitelist_matches_engine_surface` 会拿真实引擎
  逐个探针校验并断言探针集合与白名单严格相等，白名单过时它就会红。
- **`constrain` 和独立 `name` op 不可达**：它们只存在于 CLI 直连面，走 apply-agent 返回
  `mbt_operation_unsupported`。改节点名要用 `update <ab> <node> name=<id>`，不要教 Agent 用 `name`。
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
    清单（27 个交互层函数）必须全部在场；测试自身的 stub 名单不得掩盖不存在的定义；
    `lib.rs` 的原生菜单 id 必须全部被 `nativeMenuAction` 映射。这几道是**为历史事故专门加的**（见下）。
  - **动态防线**：靠字符串切片取真实状态机——`indexOf("const APP_VER")` 到
    `indexOf('async function execCli')` 划区段，再 `indexOf('function NAME(')` 逐函数抽。
    动这些标记、改函数名、或把签名写成非 `function name(` 形式，都会让它**静默取到错东西**。
- Rust 端到端测试在**本机无引擎二进制时静默跳过**（`eprintln!("跳过：...")` + `return`，不是 ignored，
  也不是 `#[ignore]`）。看到"绿"之前先确认引擎真的在，否则等于什么都没测。
  受影响的 5 个：`agent_loop_with_mock_llm_and_real_engine`、`mid_run_llm_failure_preserves_committed_work`、
  `readonly_session_gets_render_fallback`、`readonly_whitelist_matches_engine_surface`、
  `template_ids_match_engine`。`skill_dictionary_matches_engine_and_agent` 无引擎时只跳过探针、
  静态断言（字典↔白名单↔提示词）仍然生效。判断方法：看有没有 "跳过" 输出，或数通过条数是否仍是 10。

## 删前端代码前必读（真实事故，勿重演）

提交 `9f48220`（"purge dead code"）声称只删了「7 个零调用函数」，实际删掉 **33 个函数定义**，
其中 **14 个仍被引用**（约 40 处调用点）。后果：应用能正常启动，但一点画布就 `ReferenceError`——
**选择功能结构性失效**（`select()` 是唯一写入真实节点 id 的地方，它没了则 `selected` 恒为 `null`，
inspector 永久空态），`renderStage` 每次渲染都在 `bindStageSvg` 处中断，
新建画板/模板/快速开始全部误报失败，打开 DDP 直接损坏，原生菜单静默变哑。修复见 `9b8804f` 恢复。

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
6. **CI 从不运行 `test_studio.cjs`**（`windows-build.yml` 只有 cargo + `tauri build`）。
   本地改动前端后务必手动 `node test_studio.cjs`。

## 已知缺口

- 原生菜单桥已随 `9f48220` 事故一并修复：`nativeMenuAction` 已在前端实现，id → 函数映射由
  `test_studio.cjs` 检查 D 锁定（从 `lib.rs` 解析菜单 id，逐个断言已被映射）。
  改菜单时**同时**更新 `lib.rs`、前端映射表与 `docs/menus.md`。
  ⚠️ `docs/menus.md` 开头声称菜单项"只发出 `native-menu` 事件"——**这句是错的**，
  实际链路是 `lib.rs::on_menu_event` 经 `win.eval("nativeMenuAction(id)")` 直调前端全局函数
  （`event.listen` 曾因 Tauri ACL 未放行而弃用）。以代码为准，改菜单时顺手修这份文档。
- 根目录那份 2412 行的 `index.html` 旧副本已在 `9f48220` 删除，确认无任何引用
  （`tauri.conf.json` 的 `frontendDist` 指向 `../frontend`）。前端只有 `frontend/index.html` 一份。

## 提交与文档

- 提交信息用 Conventional Commits + 英文 subject：`feat(agent): ...` / `fix(studio): ...` /
  `chore: ...`。scope 常用 `agent` / `studio` / `ui` / `engine` / `bundle`。
- `docs/menus.md`：原生菜单 + 右键菜单的文案与动作映射，改菜单必读。
- `README.md`：架构速览与打包产物说明。
