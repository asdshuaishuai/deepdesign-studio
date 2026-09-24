# MoonViz: AI-Native Prototype Design Engine

> **本文件是 deepDesign 仓库的引擎能力字典（vendored 副本，已适配到标准 classic wasm + session API）。**
> 源自 `../moonviz/SKILL.md`。本副本额外保留 deepDesign 特有部分（双门表、机器可读
> 清单块、验证附录）。**op 语法内核不变**（wasm 的 apply_human_op/apply_agent_op 吃的
> 还是同一套 op 串）；变的是**引擎接口形态**：CLI 独立二进制（stdin/stdout）→ GitHub
> Releases 的**标准 classic wasm**（`moonviz-wasm-classic-<version>.wasm`，纯 WASM MVP、
> 宿主中立、零 import；docs #wasm 的「标准 wasm」。**wasm-gc 变体**（npm
> moonviz-engine-wasm，依赖 JS String Builtins 提案、仅 V8 类引擎）本仓库不用）。
> 引擎 engine-v0.1.6：经典消费面 38 = 7 经典 + 4 检视直调 + 27 session API（session_count 可测
> 泄漏、session_open_project_json 支撑 save→open 回灌、session_extract_design_system 新增）；**另有 `_in` 字节契约面（issue #8）
> 是本仓库全部宿主的写路径**——wasmtime_host / 前端 engSlotLoad / sync 探针三处消费，
> in/arg/arg2 三槽 UTF-8 分块压入（小端 4 字节+长度），`*_in()` 变体解码调经典入口；
> 写方向的逆向字符串布局依赖已退役，返回方向仍是引擎字符串指针（读布局保留）。
> 0.1.2 起 session_apply_agent 免三重往返（#6），实测 7.1× 于无状态路径。
> 只读检视命令经 session API 可达（list-tools/doc-json 无对应导出除外）。
> 引擎更新后：`node scripts/sync-engine.mjs`（release 拉取 + sha512 + 全量导出探针）→ `cargo test`。

## What This Is

MoonViz is a prototype design engine built entirely in MoonBit. It treats one MoonBit literate source file (`.mbt.md`) as the only project fact source. Human canvas edits and Agent edits both commit back to that same source; every visual preview is rebuilt from it.

`.mbt.md` follows MoonBit's official literate-source rules: `mbt` compiles, `mbt check` runs document tests, while `mbt nocheck` and `moonbit` are display-only. MoonViz adds explicit `moonviz:artboard` visual blocks and parses only supported public `@decl` declarations.

## Quick Start

本仓库内引擎是 **GitHub Releases 的预编译 wasm 工件**（`frontend/vendor/moonviz.wasm`，
由 `scripts/sync-engine.mjs` 拉取 + sha512 校验 + 全量导出契约探针；WebView 内进程执行，
测试经 node 宿主驱动同一份产物）。op 以字符串形式传入 wasm 导出：

```bash
# 同步工件（release 直链 wasm + 契约探针：7 经典/4 检视/27 session/模板/组件）——engine-v0.1.6
node scripts/sync-engine.mjs

# 变更 op（两门，wasm 导出名）：
#   apply_human_op <mbt> <op>      —— 人类画布操作
#   apply_agent_op <mbt> <op>      —— Agent 单 op 无状态入口（仅变更类）
#   session_apply_agent <h> <op>   —— Agent 会话入口（同门同分发器；agent.rs
#                                     变更路径走这里，宿主 mbt 键控缓存复用会话）
# 只读检视经 session API（宿主 mbt 键控缓存会话）：
#   session_lint / session_critique / session_query_nodes / session_spec /
#   session_infer_missing / session_states / session_interactions / session_flows /
#   session_export_svg / session_tap / session_benchmark / session_list_artboards …
```

## 引擎双门（改任何 op 前必须分清）

| wasm 路径 | 用途 | 接受 |
|------|------|------|
| `apply_human_op` | 人类画布操作（前端 inspector） | 变更类 op |
| `apply_agent_op` | Agent 单 op | **仅变更类**；只读 op 不得走此路（用 session API） |
| `session_open` + `session_*` | 只读检视/Agent 变更 | 检视命令 + `session_apply_agent`（宿主 mbt 键控缓存会话，见上） |
| `render_mbt` / `validate_mbt` | 整篇文档渲染/校验 | 整篇 canonical |

实测结论：同一篇文档经人类门逐 op 全通过，整篇提交给 Agent 门仍可能被
`mbt_gate_block:...:no_sibling_overlap` 拒绝——这是设计意图（Agent 门更严），不是 bug。

## Operation grammar (mutating ops — Agent and Human share them)

Machine-readable source of truth: `list-ops`（CLI）/ `list_ops`（MCP）输出完整 op 面
JSON（`op`/`usage`/`category`/`gates`/`description`，当前 25 op）——本节是它的可读
注解，须同步维护。只读命令见下文 Read-only 节（那两层暂无引擎输出，靠文末清单块锚定）。

Structural:
`create <name> [w] [h]` · `template <id> <name> [w] [h]` ·
`place <ab> <component> <id> [variant|-] [x] [y] [w] [h] [k=v ...]`（final-size place，
**门在最终 bbox 评估**——0.1.6/moonviz#18：默认尺寸相交的中间态仍拒，带最终尺寸一步过门）·
`duplicate <ab> <new_name>` · `delete-artboard <ab>` ·
`move <ab> <node> <x> <y>` · `copy <ab> <node> <new_id> [dx] [dy]` ·
`delete <ab> <node>` · `reorder <ab> <node> front|back|up|down` ·
`flip <ab> <node> h|v|both|none` ·
`group <ab> <group_id> <n1> <n2> ...` · `ungroup <ab> <group_id>` ·
`align <ab> <mode> <n1> <n2> ...` · `resize-canvas <ab> <w> <h>` ·
`responsive <ab>` · `restyle <ab> <component_id> k=v ...`

Images: `place <ab> image <id>` then `update <ab> <id> text=<https://...|data:image/...> radius=<n>` —
a non-empty URL renders a real `<image>` (rounded clip, cover-fit); empty text falls back to the
placeholder glyph. The URL lives in the node's `text` field and round-trips through canonical MBT.
（实测：SVG 输出 `<image href="..." preserveAspectRatio="xMidYMid slice" clip-...>`）

Navigation / theme / tokens:
`flow <from_ab> <to_ab> <node>`（写导航边）·
`unflow <from_ab> <to_ab> <node>`（删除单条导航边；0.1.5-fix-2 起 apply 面可达，moonviz#12）·
`theme <name>`（`light dark high_contrast sepia nord sunset` 共 6 个）·
`token <name> <value>`（**仅颜色令牌**：`primary` `on_primary` `secondary` `surface`
`background` `error` `text_primary` 等，全集见 `list-tokens` 的 colors 组。间距/圆角/字号
令牌一律 `unknown_token`。覆盖即时重着色，随文档 frontmatter `tokens:` 段往返，
改回默认值即撤销覆盖）·
`fix <ab>`（违规**严格减少**才提交的还债语义；因此它属于变更类，绝不能走只读管道）

CLI/MCP 会话级工具（0.1.5-fix-2 起分层可用）：
`history init|commit|log|undo|redo|checkout|diff`（设计版本控制）——**wasm 已导出
`session_history`/`session_history_in`**（0.1.5-fix-2，arg 槽 `<sub> [artboard]`、须先
init、apply 不自动入史须显式 commit），deepDesign 前端已据此实现产品级撤销/重做；但对
**Agent op 面仍不可达**（moonviz_op 无 history 头，勿经 op 尝试）·
`collab-merge` / `anim-css` / `anim-list` / `protest` 仍为 CLI/MCP 独有，wasm 未导出，
勿经 op 尝试：`collab-merge <base_rev> <agent>=<op>[+op...]`（多 agent OT 三方合并）·
`anim-css <node> <preset>` / `anim-list`（press/fade_in/slide_in_right/modal_present/
shake/pop 六预设 → CSS @keyframes）·
`protest <ab> <script>`（断言式原型测试：`tap:x:y>board; back>board; swipe:left>board;
set:node:val; noviol; render`）

Node properties (`update <ab> <node> k=v ...`) — 29 个键全部实测接受：
`w h text fill text_color stroke stroke_width radius opacity font_size weight
shadow rotate blur blend line tracking constraint align italic dash visible
layout gap justify padding width_mode height_mode x_mode y_mode name`

- `align` `left|center|right`; `italic true|false`; `dash solid|dashed|dotted`
- `visible false` hides the subtree without deleting it — it also stops
  rendering *and* hit-testing, so hidden nodes cannot be tapped
- `layout vertical|horizontal|none` enables/clears a container stack layout;
  `gap`, `justify start|center|end`, `padding` shape it
- `width_mode`/`height_mode` `hug|fill`; `w`/`h` also accept `fill`/`hug`（实测通过）
- `x_mode`/`y_mode` `center|start`; `x=@decl.center`, `y=@decl.end(24)`（实测通过）
- `name` renames a node (its carrier for interaction markers)

Interaction and state:
`interact <ab> <node> <trigger> <action_spec>` ·
`uninteract <ab> <node>` ·
`state <ab> <node> <state_name> k=v ...` ·
`set-state <node> <state_name> [toggle]`

- triggers: `tap long_press swipe_left swipe_right swipe_up swipe_down
  scroll_end key_enter focus blur`
- actions: `back` · `haptic` · `navigate_to:<board>` · `show_toast:<msg>` ·
  `set_text:<node>:<text>` · `set_state:<node>:<state>` ·
  `toggle_state:<node>` · `play_sound:<name>`
- interactions persist as name markers and are executed by the runtime:
  tap resolution is flow → marker → `NodeUpdated`
- component states persist as `[state:name:k=v,...]` markers and apply as a
  render-time transform when activated
- 先 `state` 定义、后 `set-state` 激活；未定义直接 `set-state` 得 `no_states`

### Read-only ops（只读检视，21 个，走 `load-mbt-b64` 管道）

```
list                    画板清单
flows                   导航边清单
list-templates          模板清单（14 个）
list-components         组件清单（65 个内置 + 用户组件）
list-tools              MCP 工具清单（见下方 MCP 段的告警）
list-tokens             设计令牌（colors/spacing/radii/typography 四组）
list-themes             主题清单（6 个）
lint <ab>               设计质检
critique <ab>           八原则评审
query <ab>              节点查询
infer <ab>              页面类型推断
spec <ab>               设计规格生成
missing <ab>            未接线 CTA 检出
doc-json <ab>           结构化文档导出
states <ab>             已注册状态清单
interactions <ab>       已注册交互清单
export-svg <ab>         SVG 导出
export-html <ab>        自包含可交互 HTML 原型（节点级 tap 绑定 + 状态 CSS 变体）
extract-design-system <ab>  设计系统提取：颜色/尺寸 token 用量+置信度（0.1.6，
                        session_extract_design_system；agent.rs 已接只读路由）
tap <ab> <x> <y>        模拟点击，返回状态变化
benchmark               性能基准
```

### CLI-pipeline-only（两道门都不可达）

`constrain <ab> <intent_text>` —— **两门 apply 均拒绝**（`mbt_operation_unsupported`）。
它是 session 管道的**布局意图解析器**（非层级/z-order；0.1.6/#17 起 cannot_parse 就地返回
全部意图词表：居中 | 垂直居中 | 垂直排列 | 水平排列 | 等宽 | 等高 | 等间距 | 网格 N |
顶部 | 底部 | 放大 N | 缩小 N | 边距 N | 间距 N）。**deepDesign 侧仍未接入**：成功信封
不回传 canonical mbt（实测 `{ok,id,x}`），键控会话宿主取不回变更——已提
[#19](https://github.com/asdshuaishuai/moonviz/issues/19) 请求对齐 session_apply_agent
信封；补齐后接线。布局意图用 align/update/place[w h] 表达；全屏背景+内容走全包含豁免
（0.1.5-fix/#15）；z-order 用 `reorder <ab> <node> front|back|up|down`。
改节点名用 `update <ab> <node> name=<id>`，不要教 Agent 用 `constrain` 或独立 `name` op。

## MCP Server

```json
{
  "mcpServers": {
    "moonviz": {
      "command": "moon",
      "args": ["run", "--target", "native", "mcp"],
      "cwd": "/path/to/moonviz"
    }
  }
}
```

MCP 面与 CLI op 面同源、snake_case 命名。工具注册表的事实源是引擎
`core/agent_api.mbt`（47 工具、全量 inputSchema），MCP `tools/list` 直接输出
MCP `tools/list` 形态的合法 JSON（`name`/`description`/`inputSchema{properties,required}`）。
枚举 MCP 面用 `list-tools`，不要引用写死的工具总数。
（此项已修复：此前只倾倒 11 个且嵌套 JSON 未转义。）

> ⚠️ **但注意层次差**：`list-tools` 是 **MCP 命名层且为策展子集**——
> `create`/`copy`/`delete`/`reorder`/`flip`/`duplicate`/`delete-artboard`/`flow` 等
> CLI op 没有 MCP 对应工具。**CLI op 面的完整清单仍以本文件文末的机器可读块为准**
> （引擎 `help` 也不完整：dispatch 里 `token`/`export-html`/`infer`/`missing`/
> `doc-json` 等 8 项不在 help 文案中）。

`ddp_view` is read-only metadata for integrations; it exposes no mutation path.

Argument passing mirrors the CLI: list-ish arguments are comma-separated
(`nodes="a,b"`), property arguments are space-separated `k=v`
(`args="fill=#fff radius=8"`).

## Components

The component catalog is owned by `core/`, not by the Studio shell. `builtin_components()` provides **65 unique engine presets**（实测 `list-components` = 65）across actions, inputs, selection, display, layout, navigation, feedback, and overlay categories, with variants and default geometry. The shell discovers this catalog through the engine and only renders previews/materializes operations.

## Rendering

```text
.ddp authenticated bytes
  → DDP codec
  → one complete `.mbt.md` source
  → official fence scanner
  → explicit MoonViz visual blocks
  → `@decl` parser
  → Prototype / Document / Scene Graph
  → layout solve + predicates
  → SVG / RenderPlan
  → Studio shell
```

Markdown is available as a source-reading view. It is never converted to HTML as the visual source of truth. SVG and RenderPlan are derived display outputs only.

## DDP

A `.ddp` file is the authenticated encrypted representation of one complete `.mbt.md` source. It is not a ZIP, archive, manifest, or collection of files. It contains no `pm-design.md`, OpenUI, HTML, or `.mvz.json` source.

The Tauri shell transports opaque DDP bytes through the authenticated codec. The engine then decrypts, validates, and renders the MBT source. Import is atomic: a bad password, damaged bytes, invalid MBT, unknown visual entry, invalid flow, or predicate failure leaves the current project unchanged.

## Architecture

- **Engine (`core/`, `decl/`)**: MBT scanning, visual declaration parsing, 65 component presets, project reconstruction, layout, predicates, Human/Agent gates, canonical MBT serialization, SVG and RenderPlan.
- **CLI/MCP**: Source-based engine protocols over stdin/stdout.
- **Tauri shell**: file dialogs, opaque DDP transport, and visual presentation only.
- **DDP**: one encrypted `.mbt.md` source.

## User Components (custom component registry)

The engine treats custom components exactly like builtins — the registry is source-agnostic. Whether the declaration comes from an Agent (natural-language translation) or a human (Studio canvas), the artifact is the same: a single-artboard `.mbt.md` declaration with a `component:` front-matter section.

Workflow:

```
# 1. Agent drafts the declaration (params as ${name} slots in node attrs)
# 2. Compile & register (full pipeline: syntax → single-artboard → param
#    closure → instantiation probe → registry)
component-compile-b64 <b64>

# 3. Discover & use exactly like builtins
list-components        # merged view, source: user
component-describe <id>  # params/variants/usage template
place <artboard> <id> <inst> [variant|-] [x] [y] [w] [h] key=value...

# 4. Share — the ONLY outbound form is the proprietary MCF container
component-export <id>   # → mcf_b64 (byte source never leaves the engine)
component-import <b64>  # strict validation (magic/version/CRC×2/fingerprint)
                        # then FULL re-compilation before registration

# 5. Host-side persistence (engine is IO-free by design)
library-snapshot        # dump for the host to persist
library-restore-b64 ... # rehydrate at session start
```

Rules: `.mbt.md` component source exists only inside the engine/local library; outbound distribution is always MCF. MCF is a pure data container — imports are re-validated through the same compile pipeline, no code execution surface.

## 附录：op 清单（机器可读文档镜像；契约锚定在 agent.rs 的 READONLY_OPS）

```
# mutating 层不再手工列举——事实源是引擎 `list-ops` 输出（25 op，
# sync-engine 探针校验 ≥25；agent.rs 侧由 ENGINE_TEMPLATES 契约测试锚定模板）。
readonly: list flows list-templates list-components list-tools list-tokens
  list-themes lint critique query infer spec missing doc-json states
  interactions export-svg export-html extract-design-system tap benchmark
cli_only: constrain name save load export-mbt-human export-mbt-agent export-decl export-artifact
  render-mbt-b64 validate-mbt-b64 canonical-mbt-b64
  apply-agent-mbt-b64 apply-human-mbt-op-b64 apply-agent-mbt-op-b64
  load-mbt-b64 library-snapshot library-restore-b64 component-compile-b64
  component-describe component-delete component-export component-import help exit
  history collab-merge anim-css anim-list protest
```

## 附录：验证方法（引擎更新后重跑）

```bash
E=src-tauri/engine/moonviz-cli.exe
node scripts/sync-engine.mjs                       # 全量导出契约探针（事实源）
node scripts/sync-engine.mjs                       # 全量导出契约探针（含模板/组件）
printf 'list-templates\nexit\n' | $E             # 模板全集
printf 'list-components\nexit\n' | $E            # 组件全集（65）
printf 'list-themes\nexit\n' | $E                # 主题全集（6）
# 变更类逐个探针：apply-agent-mbt-op-b64 <mbt> <op>  → 期望 ok 或 mbt_gate_block（语法接受）
# 只读类逐个探针：load-mbt-b64 <mbt> + <op>        → 期望 ok；apply 路径应报 mbt_operation_unsupported
# 探针已固化在 `node scripts/sync-engine.mjs`（同步时自动跑）与 cargo test 的引擎门测试
```
