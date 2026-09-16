# MoonViz: AI-Native Prototype Design Engine

> **本文件是 deepDesign 仓库的引擎能力字典（vendored 副本）。**
> 源自 `../moonviz/SKILL.md`。上游曾不完整（缺 flow/theme/fix/token/export-html 与只读命令、
> constrain 误标共享、MCP 工具数失实），已于上游 `555e21a` 修正——本副本的修正先于上游落地，
> 两边内容现已收敛；本副本额外保留 deepDesign 特有部分（双门表、机器可读清单块、验证附录）。
> 每一条声明都对照本仓库实际分发的引擎二进制探测验证过。引擎更新后：重跑文末附录探针 →
> 更正本文件（并与上游 diff，能同步回上游的同步回去）→ `cargo test` 的 SKILL 契约测试强制对账。

## What This Is

MoonViz is a prototype design engine built entirely in MoonBit. It treats one MoonBit literate source file (`.mbt.md`) as the only project fact source. Human canvas edits and Agent edits both commit back to that same source; every visual preview is rebuilt from it.

`.mbt.md` follows MoonBit's official literate-source rules: `mbt` compiles, `mbt check` runs document tests, while `mbt nocheck` and `moonbit` are display-only. MoonViz adds explicit `moonviz:artboard` visual blocks and parses only supported public `@decl` declarations.

## Quick Start

本仓库内引擎是**独立二进制**（无 `moon run` 回退），stdin 写命令 / stdout 读 JSON 行：

```bash
# 定位：MOONVIZ_CLI 环境变量 → src-tauri/engine/moonviz-cli.exe → 兄弟仓库 _build 产物
printf 'render-mbt-b64 <base64-utf8-mbt>\nexit\n' | src-tauri/engine/moonviz-cli.exe
printf 'validate-mbt-b64 <base64-utf8-mbt>\nexit\n' | src-tauri/engine/moonviz-cli.exe

# Human 与 Agent 操作都返回 canonical MBT + 引擎渲染
apply-human-mbt-op-b64 <mbt-base64> <operation-base64>
apply-agent-mbt-op-b64 <mbt-base64> <operation-base64>
```

## 引擎双门（改任何 op 前必须分清）

| 路径 | 用途 | 接受 |
|------|------|------|
| `apply-human-mbt-op-b64` | 人类画布操作（前端 inspector） | 变更类 op |
| `apply-agent-mbt-op-b64` | Agent 单 op | **仅变更类**；只读 op 一律 `mbt_operation_unsupported` |
| `apply-agent-mbt-b64` | 整篇文档提交（前端的"校验并渲染"） | 整篇 canonical，**比 op 路径更严**（真实重叠债被 `no_sibling_overlap` 拦下） |
| `load-mbt-b64` + op | 只读检视 | 只读命令 |

实测结论：同一篇文档经人类门逐 op 全通过，整篇提交给 Agent 门仍可能被
`mbt_gate_block:...:no_sibling_overlap` 拒绝——这是设计意图（Agent 门更严），不是 bug。

## Operation grammar (Agent and Human share it)

Structural:
`create <name> [w] [h]` · `template <id> <name> [w] [h]` ·
`place <ab> <component> <id> [variant|-] [x] [y] [k=v ...]` ·
`duplicate <ab> <new_name>` · `delete-artboard <ab>` ·
`move <ab> <node> <x> <y>` · `copy <ab> <node> <new_id> [dx] [dy]` ·
`delete <ab> <node>` · `reorder <ab> <node> front|back|up|down` ·
`flip <ab> <node> h|v|both|none` ·
`group <ab> <group_id> <n1> <n2> ...` · `ungroup <ab> <group_id>` ·
`align <ab> <mode> <n1> <n2> ...` · `resize-canvas <ab> <w> <h>` ·
`responsive <ab>` · `restyle <ab> <component_id> k=v ...`

Navigation / theme / tokens:
`flow <from_ab> <to_ab> <node>`（写导航边）·
`theme <name>`（`light dark high_contrast sepia nord sunset` 共 6 个）·
`token <name> <value>`（**仅颜色令牌**：`primary` `on_primary` `secondary` `surface`
`background` `error` `text_primary` 等，全集见 `list-tokens` 的 colors 组。间距/圆角/字号
令牌一律 `unknown_token`。覆盖即时重着色，随文档 frontmatter `tokens:` 段往返，
改回默认值即撤销覆盖）·
`fix <ab>`（违规**严格减少**才提交的还债语义；因此它属于变更类，绝不能走只读管道）

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

### Read-only ops（只读检视，20 个，走 `load-mbt-b64` 管道）

```
list                    画板清单
flows                   导航边清单
list-templates          模板清单（14 个）
list-components         组件清单（52 个内置 + 用户组件）
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
tap <ab> <x> <y>        模拟点击，返回状态变化
benchmark               性能基准
```

### CLI-pipeline-only（两道门都不可达）

`constrain <ab> <intent_text>` —— 实测 `apply-agent-mbt-op-b64` 与
`apply-human-mbt-op-b64` **双双返回 `mbt_operation_unsupported`**，仅在
`load`/会话管道上可用。上游 SKILL.md 把它列在共享语法里是**错的**。
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

MCP 面与 CLI op 面同源、snake_case 命名（`update_node`/`place_component`/
`apply_template`/`define_state`/`set_state`/`set_token`/`export_html`/`auto_fix`/
`read_mbt`/`render_mbt`/`generate_spec`/`infer_missing`/`suggest_alignment`/
`extract_design_system`/`component_*`/`library_*` 等，分发表在引擎 `mcp/main.mbt`）。

> ⚠️ **告警（引擎侧，待上游修）：** CLI 的 `list-tools` 当前只倾倒 11 个工具，
> 且 `params` 字段的嵌套 JSON 未转义引号，整行不是合法 JSON。
> 枚举 MCP 面请读 `mcp/main.mbt` 分发表，**不要**依赖 `list-tools`，
> 也不要引用任何写死的工具总数。

`ddp_view` is read-only metadata for integrations; it exposes no mutation path.

Argument passing mirrors the CLI: list-ish arguments are comma-separated
(`nodes="a,b"`), property arguments are space-separated `k=v`
(`args="fill=#fff radius=8"`).

## Components

The component catalog is owned by `core/`, not by the Studio shell. `builtin_components()` provides **52 unique engine presets**（实测 `list-components` = 52）across actions, inputs, selection, display, layout, navigation, feedback, and overlay categories, with variants and default geometry. The shell discovers this catalog through the engine and only renders previews/materializes operations.

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

- **Engine (`core/`, `decl/`)**: MBT scanning, visual declaration parsing, 52 component presets, project reconstruction, layout, predicates, Human/Agent gates, canonical MBT serialization, SVG and RenderPlan.
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
place <artboard> <id> <inst> [variant] [x] [y] key=value...

# 4. Share — the ONLY outbound form is the proprietary MCF container
component-export <id>   # → mcf_b64 (byte source never leaves the engine)
component-import <b64>  # strict validation (magic/version/CRC×2/fingerprint)
                        # then FULL re-compilation before registration

# 5. Host-side persistence (engine is IO-free by design)
library-snapshot        # dump for the host to persist
library-restore-b64 ... # rehydrate at session start
```

Rules: `.mbt.md` component source exists only inside the engine/local library; outbound distribution is always MCF. MCF is a pure data container — imports are re-validated through the same compile pipeline, no code execution surface.

## 附录：op 清单（机器可读，`cargo test` 消费此块）

```
mutating: create template place duplicate delete-artboard move copy delete
  reorder flip group ungroup align resize-canvas responsive restyle interact
  uninteract state set-state flow theme token fix update
readonly: list flows list-templates list-components list-tools list-tokens
  list-themes lint critique query infer spec missing doc-json states
  interactions export-svg export-html tap benchmark
cli_only: constrain name save load export-mbt-human export-mbt-agent
  export-decl export-artifact render-mbt-b64 validate-mbt-b64 canonical-mbt-b64
  apply-agent-mbt-b64 apply-human-mbt-op-b64 apply-agent-mbt-op-b64
  load-mbt-b64 library-snapshot library-restore-b64 component-compile-b64
  component-describe component-delete component-export component-import help exit
```

## 附录：验证方法（引擎更新后重跑）

```bash
E=src-tauri/engine/moonviz-cli.exe
printf 'help\nexit\n' | $E                       # 命令总览
printf 'list-templates\nexit\n' | $E             # 模板全集
printf 'list-components\nexit\n' | $E            # 组件全集（52）
printf 'list-themes\nexit\n' | $E                # 主题全集（6）
# 变更类逐个探针：apply-agent-mbt-op-b64 <mbt> <op>  → 期望 ok 或 mbt_gate_block（语法接受）
# 只读类逐个探针：load-mbt-b64 <mbt> + <op>        → 期望 ok；apply 路径应报 mbt_operation_unsupported
# 上述全套探针已固化为 cargo test 里的 SKILL 契约测试，直接跑测试即可对账
```
