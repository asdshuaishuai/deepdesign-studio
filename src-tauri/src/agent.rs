//! 进程内 Agent 基座：OpenAI/Anthropic 工具调用循环 × MoonViz wasm 引擎。
//!
//! 引擎是标准 classic wasm 产物（frontend/vendor/moonviz.wasm，宿主中立），本模块经
//! `EngineHost`（wasmtime 进程内纯 Rust 宿主，见 wasmtime_host.rs；与前端画布各自
//! 持有实例、只交换 canonical 文本）调用：变更 op → session_apply_agent
//! （engine-v0.1.1-session 起与无状态 apply_agent_op 同门同分发器，AgentGate；
//! 宿主按 mbt 键控复用会话），空项目起步 → 种子文档 + apply_human_op 引导。
//! 只读检视面（lint/critique/query/...）经 wasm session API 路由可达
//! （导出 26 个 session_*；仅 list-tools/doc-json 无对应导出）。
//! 请求体为 OpenAI chat wire format 或 Anthropic Messages wire（协议按 base_url 探测）。
//! OpenAI 侧经 async-openai【纯类型层】（chat-completion-types，无 HTTP client）构造
//! 请求骨架与 tools schema，序列化后与 provider 回显的原始 messages 合并、注入
//! thinking 家族等非标字段，再经自有 reqwest 发送；响应侧保持 raw Value
//! （typed 往返会丢 reasoning_content 等非标字段，严格枚举在兼容网关上会碎——
//! SDK 自家 issue #498/#503）。返回契约与原 JS 桥一致：
//! {ok, mbt_b64, render, ops[], stopReason, text}。

use serde_json::{json, Value};
use std::time::Duration;

use crate::EngineHost;
use async_openai::types::chat::{
    CreateChatCompletionRequest, ChatCompletionTool, ChatCompletionTools, FunctionObject,
};
use base64::engine::general_purpose::STANDARD as BASE64;

const MAX_STEPS: usize = 200;
/// 单次引擎调用超时。必须**晚于**宿主的 epoch 中断预算（wasmtime_host::CALL_TIMEOUT
/// 30s + tick 粒度 + 外层 5s 宽限）：这里先到点会把「引擎已中断/未提交」误报成
/// engine_timeout，还可能与宿主竞态。45s 保证总能收到宿主的真实结果。
const ENGINE_OP_TIMEOUT: Duration = Duration::from_secs(45);
const LLM_TIMEOUT: Duration = Duration::from_secs(180);

/// 空项目起步的种子画板 id（wasm 引擎要求文档至少一个视觉块才能承载 op；
/// 首个真实 op 落地后立即 delete-artboard 移除种子）。
const SEED_BOARD: &str = "__seed";

/// 最小种子文档（canonical 格式：frontmatter + 单画板 ```mbt 块）。
/// 与 frontend/index.html 的 seedDoc 逐字对齐——改任一边都要同步另一边。
fn seed_doc(id: &str, w: i64, h: i64) -> String {
    format!(
        "---\nmoonviz:\n  format: visual-document\n  revision: 1\n  entry: {id}\n---\n\n# {id}\n\n<!-- moonviz:artboard {id} -->\n```mbt\nfn visual_{id}() -> @decl.Prototype {{\n  let page = @decl.prototype(name=\"{id}\", width={w}.0, height={h}.0)\n  page\n}}\n```\n"
    )
}

/// 引擎模板清单（id 与 MoonViz `list-templates` 对齐，尺寸以引擎实际产出为准）。
/// 改这里必须同步 `template_ids_match_engine` 契约测试。
const ENGINE_TEMPLATES: &str = "login(登录页) | signup(注册页) | dashboard(仪表盘) | profile(个人主页)
settings(设置页) | list_detail(列表-详情) | onboarding(引导页) | empty_state(空状态)
web_landing(Web落地页 1280x800) | web_login(Web登录 1280x800) | web_dashboard(Web仪表盘 1280x800)
pc_app(PC桌面 1280x800) | adaptive_landing(自适应落地页) | login_v2(登录页v2)";

const INSTRUCTIONS: &str = r#"You are the embedded design agent of deepDesign Studio, a visual prototyping editor.
You operate as a product designer, not a command executor: interpret what the user wants to
ACHIEVE, decide which screens the experience needs, build them, connect them, and verify the result.
The single source of truth is one MoonBit literate .mbt.md document; every operation you issue is
validated by the engine (AgentGate) and committed immediately, so the user watches progress live.

## Mindset
- Derive intent: "a WeChat-style app" means an experience (login, feed, chat, profile, settings),
  not one artboard. Before the first tool call, state a one-line plan: the screen list and how they connect.
- CLARIFY-FIRST TASKS: when the user explicitly asks you to confirm questions before building
  (e.g. "先列出你要确认的关键问题，我回答后再开始生成"), reply with those questions as plain
  text — do NOT call tools and do NOT build yet. Your reply is shown to the user verbatim;
  their answers arrive appended to their next instruction, and you then build directly.
  Ask ONLY the unanswered questions — never restate the task background back at them.
- Think in flows: a prototype is screens + navigation. An unconnected screen is unfinished.
- Write real product copy (realistic labels, names, numbers), never lorem ipsum.
- Full-bleed backgrounds are fine: place a background rect and grow it with
  width_mode=fill & height_mode=fill — content placed later may sit on top of
  a fill-mode node. Nodes with EXPLICIT sizes still must never intersect any
  sibling rect (no_sibling_overlap rejects them): before each place, reserve a
  non-intersecting slot; run query <ab> to learn actual sizes, then update w/h
  right after placing.
- Tiny precision nodes (battery/status icons, switches) occupy small rects
  inside bars — place them FIRST, then place larger siblings around them.
- Two modes: BUILD requests get the full loop below; TWEAK requests ("make the button green")
  get read_mbt, one targeted op, done.

## Build loop (from empty document)
1. PLAN: choose screens; map each to a template. Available: __TEMPLATES__
   Notes: template/create size args are optional; list_detail yields ONE artboard
   (a list screen with a detail placeholder card — not two separate screens);
   adaptive templates pick structure by width.
   Artboard names become ids after sanitization — use ASCII snake_case names
   (e.g. chat_list); non-ASCII names collapse to "_" and collide. Chinese copy
   belongs in node text values, never in artboard/node ids.
2. CREATE: one "template <id> <name> [w] [h]" per screen, then IMMEDIATELY read_mbt —
   node ids are only discoverable there. Artboard id = sanitized name.
3. CUSTOMIZE: "update <artboard> <node> k=v ..." per screen; finish one before the next.
   "place <artboard> <component> <instance_id> [variant|-] [x] [y] [w] [h]" to add engine
   components (discover ids via list_components; "-" as variant means default). ALWAYS pass
   the final [w] [h] when you know them — the gate evaluates the FINAL bbox (engine-v0.1.6,
   issue #18): a place that collides at component-default size is rejected even if you meant
   to resize right after; passing final w/h makes it one op instead of reject+update.
4. CONNECT: "flow <from> <to> <node>" for every primary CTA (login button, card tap, tab, back).
   Use "interact" for anything richer than navigation (show_toast, set_state, haptic, play_sound) —
   and define the target with "state" first if you want a pressed/selected visual.
5. VERIFY: read_mbt and check flows cover every screen; every primary CTA wired; no dangling refs.
   Run "fix <artboard>" if violations accumulated. Agent ops are gate-checked:
   violations are rejected outright with mbt_gate_block (debt tolerance is human-canvas only).
6. REPORT: stop calling tools and summarize: screens built and the flow map.

## Tweak loop (document already loaded)
0. read_mbt FIRST — always ground ids and flows before any op.
1. Make the minimal ops. 2. Report what changed.

## Operation grammar (one op per moonviz_op call, no newlines)
  template <template_id> <name> [w] [h] | create <name> [w] [h]
  | duplicate <artboard> <new_name> | delete-artboard <artboard>
  | place <artboard> <component> <instance_id> [variant|-] [x] [y] [w] [h]
  | move <artboard> <node> <x> <y> | update <artboard> <node> k=v [k=v ...]
  | delete <artboard> <node> | copy <artboard> <node> <new_id> [dx] [dy]
  | reorder <artboard> <node> front|back|up|down | flip <artboard> <node> h|v|both|none
  | group <artboard> <group_id> <n1> <n2> ... | ungroup <artboard> <group_id>
  | align <artboard> left|right|top|bottom|hcenter|vcenter <n1> <n2> ...
  | constrain <artboard> <intent_text>   (layout-intent parser, ONE artboard per op; intents:
      居中 | 垂直居中 | 垂直排列 | 水平排列 | 等宽 | 等高 | 等间距 | 网格 N | 顶部 | 底部 |
      放大 N | 缩小 N | 边距 N | 间距 N — an invalid intent error returns the full vocabulary.
      LAYOUT INTENT ONLY, never layering/z-order: fully-contained siblings are already
      gate-legal; z-order via "reorder".)
  | restyle <artboard> <component_id> k=v ...   (propagate to that component's instances)
  | resize-canvas <artboard> <w> <h> | responsive <artboard>  (adds _tablet/_desktop variants)
  | interact <artboard> <node> <trigger> <action>  | uninteract <artboard> <node>
  | state <artboard> <node> <state_name> k=v ...   | set-state <node> <state_name> [toggle]
  | flow <from_artboard> <to_artboard> <node>
  | unflow <from_artboard> <to_artboard> <node>   (delete one navigation edge)
  | theme <name>  (light|dark|high_contrast|sepia|nord|sunset)
  | token <name> <value>   (override ONE COLOR token, e.g. token primary #FF5722)
  | fix <artboard>
- token: color tokens ONLY (primary, on_primary, secondary, surface, background, error, text_
  primary...). Spacing/radii/typography tokens are NOT settable (unknown_token). The override
  recolors immediately, persists in the document's frontmatter tokens: section, and setting
  the value back to its default removes it.
- interact triggers: tap long_press swipe_left swipe_right swipe_up swipe_down scroll_end
  key_enter focus blur. interact actions: back | haptic | navigate_to:<board>
  | show_toast:<msg> | set_text:<node>:<text> | set_state:<node>:<state>
  | toggle_state:<node> | play_sound:<name>. Define the state via "state" BEFORE
  set_state/toggle_state can target it; call set-state only after a state exists.
- inspection: read-only commands ARE available on this engine face (routed through the wasm
  session API — they inspect but never commit): list | flows | list-templates | list-components
  | list-tokens | list-themes | lint <ab> | critique <ab> | query <ab> | infer <ab> | spec <ab>
  | missing <ab> | states <ab> | interactions <ab> | export-svg <ab> | export-html | tap <ab> <x> <y>
  | extract-design-system <ab> (color/size token usage analysis with confidence — ground
    theme/token decisions before restyling).
  | benchmark. Use them to ground decisions before mutating (lint catches contrast/touch-target
  debt, missing finds unwired CTAs, query lists nodes, states/interactions show what's wired).
  Exceptions with no wasm export — never call: list-tools, doc-json (use read_mbt / list-ops
  introspection instead). Mutations still go through moonviz_op only.
  read_mbt and list_components are separate TOOLS — call them directly; passing "read_mbt"
  as a moonviz_op op string returns mbt_operation_unsupported.
- update keys: w h text fill text_color stroke stroke_width radius opacity font_size weight
  shadow rotate blur blend line tracking constraint align italic dash visible layout gap
  justify padding width_mode height_mode x_mode y_mode name.
  (align left|center|right; dash solid|dashed|dotted; visible true|false;
   layout vertical|horizontal|none; width_mode/height_mode hug|fill; x_mode/y_mode center|start;
   w/h also accept fill|hug; x/y also accept @decl.center or @decl.end(24) — edge-anchored)
  Quote values with spaces: text="Sign in".
  Unquoted words after a space are silently dropped — always quote multi-word text.
- duplicate is the cheapest way to spawn "a similar screen" before diverging with update.
- The engine REJECTS unsupported ops with mbt_operation_unsupported. A standalone "name" op is
  CLI-only, NOT reachable here — use "update ... name=<id>". "constrain" IS available on this
  face as a mutating op (layout-intent parser; LAYOUT ONLY, never layering/z-order).

## Ground truth and errors
- NEVER guess node/component/template/theme ids. Templates: list above; components: list_components;
  everything else: read_mbt. Ids are shared with the human canvas: never rename; new ids = snake_case.
- Errors: unknown_artboard/unknown_node/unknown_component/unknown_template → read_mbt then retry with real ids.
  Predicate violations (overflow, overlap) reject the op with predicate + node_id + detail → adjust values;
  if stuck run fix <artboard>. Never repeat an identical failing op.
  delete failing with mbt_flow_unknown_node:<ab>:<node> → that node is a navigation-edge endpoint:
  unflow the edge(s) first (unflow <ab> <target> <node>), then delete.
  A "template" op rejected with mbt_gate_block means that built-in template's content carries gate
  debt — do NOT retry it; build the screen with "create" + "place"/"update" instead.
- keep ops gate-clean (violations → mbt_gate_block rejection, not tolerated debt). All changes go through moonviz_op only."#;

fn instructions() -> String {
    INSTRUCTIONS.replace("__TEMPLATES__", ENGINE_TEMPLATES)
}

/// LLM 线上协议。OpenAI Chat Completions 与 Anthropic Messages 两套请求/响应格式。
/// MiniMax 双协议支持：OpenAI 兼容端点（/v1）与 Anthropic 兼容端点（/anthropic，官方推荐）。
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Protocol {
    OpenAi,
    Anthropic,
}

/// 由 base_url 推断协议：路径尾部为 `/anthropic`（或 `/anthropic/v1`）、host 精确等于
/// api.anthropic.com 时走 Anthropic Messages。尾部匹配而非 contains——`/anthropic-proxy`
/// 这类代理路径不得误判；host 精确比对防 api.anthropic.com.evil.net 前缀伪装。
/// 覆盖 MiniMax 官方文档配置方式（ANTHROPIC_BASE_URL=.../anthropic）与官方 Anthropic 端点。
/// models.rs 的测试用 our_family 副本与本函数钉了等价测试（勿单边改判定规则）。
pub(crate) fn protocol_for(base_url: &str) -> Protocol {
    let b = base_url.to_ascii_lowercase();
    let t = b.trim_end_matches('/');
    // 必须是路径尾部的 anthropic 段（含快照记录的 .../anthropic/v1 形态）：
    // 用 contains 会把 /anthropic-proxy 这类代理路径误判成 Messages 协议。
    // host 精确比对——contains("api.anthropic.com") 会被 api.anthropic.com.evil.net 这类
    // 前缀伪装命中（与 safe_base_url 同级的 DNS 前缀攻击面）
    let host = t.split("://").nth(1).unwrap_or("").split('/').next().unwrap_or("");
    if host == "api.anthropic.com" || t.ends_with("/anthropic") || t.ends_with("/anthropic/v1") {
        Protocol::Anthropic
    } else {
        Protocol::OpenAi
    }
}

/// OpenAI messages 数组 → Anthropic messages + system 提取。
/// 关键约束（Anthropic API 硬性要求）：连续的 role:"tool" 消息必须**合并为单条
/// user 消息**里的多个 tool_result 块；system 不进 messages 而是顶层字段。
fn to_anthropic_messages(messages: &[Value]) -> (Option<String>, Vec<Value>) {
    let mut system = Vec::new();
    let mut out: Vec<Value> = Vec::new();
    let mut pending_tool_results: Vec<Value> = Vec::new();
    let flush = |out: &mut Vec<Value>, pending: &mut Vec<Value>| {
        if !pending.is_empty() {
            out.push(json!({"role": "user", "content": pending.clone()}));
            pending.clear();
        }
    };
    for m in messages {
        let role = m.get("role").and_then(|v| v.as_str()).unwrap_or("");
        match role {
            "system" => {
                if let Some(t) = m.get("content").and_then(|v| v.as_str()) {
                    system.push(t.to_string());
                }
            }
            "tool" => {
                // 归入待合并的 tool_result 批次
                let tid = m.get("tool_call_id").and_then(|v| v.as_str()).unwrap_or("");
                let content = m.get("content").and_then(|v| v.as_str()).unwrap_or("");
                pending_tool_results.push(json!({
                    "type": "tool_result",
                    "tool_use_id": tid,
                    "content": content,
                }));
            }
            "assistant" => {
                flush(&mut out, &mut pending_tool_results);
                let mut blocks = Vec::new();
                if let Some(t) = m.get("content").and_then(|v| v.as_str()) {
                    if !t.is_empty() {
                        blocks.push(json!({"type": "text", "text": t}));
                    }
                }
                if let Some(tcs) = m.get("tool_calls").and_then(|v| v.as_array()) {
                    for c in tcs {
                        let id = c.get("id").and_then(|v| v.as_str()).unwrap_or("");
                        let name = c.pointer("/function/name").and_then(|v| v.as_str()).unwrap_or("");
                        let args_raw = c.pointer("/function/arguments").and_then(|v| v.as_str()).unwrap_or("{}");
                        let input: Value = serde_json::from_str(args_raw).unwrap_or(json!({}));
                        blocks.push(json!({"type": "tool_use", "id": id, "name": name, "input": input}));
                    }
                }
                out.push(json!({"role": "assistant", "content": blocks}));
            }
            "user" => {
                flush(&mut out, &mut pending_tool_results);
                let content = m.get("content").and_then(|v| v.as_str()).unwrap_or("");
                out.push(json!({"role": "user", "content": content}));
            }
            _ => {}
        }
    }
    flush(&mut out, &mut pending_tool_results);
    (if system.is_empty() { None } else { Some(system.join("\n\n")) }, out)
}

/// OpenAI tools schema → Anthropic tools schema（name/description/input_schema）。
fn anthropic_tools() -> Value {
    let fns = tools_schema();
    let arr = fns.as_array().cloned().unwrap_or_default();
    let out: Vec<Value> = arr
        .iter()
        .filter_map(|t| {
            let f = t.get("function")?;
            Some(json!({
                "name": f.get("name")?,
                "description": f.get("description").cloned().unwrap_or(json!("")),
                "input_schema": f.get("parameters").cloned().unwrap_or(json!({"type":"object"})),
            }))
        })
        .collect();
    json!(out)
}

/// Anthropic 响应 → OpenAI 形状（主循环只认这一种）。
/// content 块里 text 拼为 content 字符串，tool_use 块转为 tool_calls
/// （arguments 回填为 JSON **字符串**，与 OpenAI 一致）。
fn normalize_anthropic_response(v: &Value) -> Value {
    let mut text = String::new();
    let mut tool_calls: Vec<Value> = Vec::new();
    if let Some(blocks) = v.get("content").and_then(|c| c.as_array()) {
        for b in blocks {
            match b.get("type").and_then(|t| t.as_str()) {
                Some("text") => {
                    if let Some(t) = b.get("text").and_then(|x| x.as_str()) {
                        text.push_str(t);
                    }
                }
                Some("tool_use") => {
                    let id = b.get("id").and_then(|x| x.as_str()).unwrap_or("");
                    let name = b.get("name").and_then(|x| x.as_str()).unwrap_or("");
                    let input = b.get("input").cloned().unwrap_or(json!({}));
                    let args = serde_json::to_string(&input).unwrap_or_else(|_| "{}".into());
                    tool_calls.push(json!({
                        "id": id,
                        "type": "function",
                        "function": {"name": name, "arguments": args},
                    }));
                }
                _ => {}
            }
        }
    }
    json!({
        "choices": [{
            "message": {
                "role": "assistant",
                "content": text,
                "tool_calls": tool_calls,
            }
        }]
    })
}

/// 思考控制（逐家官方文档核对，2026-09；等级=OpenAI 标准 reasoning_effort，
/// 开关=body 顶层 thinking.type）：
/// - DeepSeek（api-docs.deepseek.com）：effort low/high/max（min/medium/xhigh/ultra
///   服务端自动映射）；off→thinking disabled；思考模式忽略 temperature
/// - GLM-5.3 / 5.3-flash（docs.bigmodel.cn 与 docs.z.ai，bigmodel/z.ai 双平台同参数）：
///   强制思考——off 降级 effort=low、medium 降级 high（官方迁移指引：disabled→enabled+low；
///   仅 low/high/max 三档）
/// - GLM-5.2 及更早：thinking.type 开关 + effort 七档（max/xhigh/high/medium/low/minimal/none）
/// - Kimi k3 / kimi-for-coding（platform.kimi.com + kimi.com/code）：恒开思考无开关——
///   off→effort none（路由到无思考版），等级 low/high/max（medium 降级 high）
/// - Kimi k2.x：thinking.type 开关（k2.6）；等级档不传（未定义）
/// - MiniMax M2/M3（OpenAI 协议）：仅 thinking.type adaptive(默认)/disabled，无等级（M2.x disabled 忽略）
/// - MiniMax（Anthropic 协议）：thinking{type:enabled,budget_tokens} 全档 2048/8192/16384/32768，off/auto 省略即关闭
/// - StepFun（platform.stepfun.com，含 Step Plan step_plan/v1）：effort low/medium/high
///   （max 降级 high），无开关
/// - Qwen：DashScope 兼容模式对未知字段严格——仅 vLLU 自部署方言 off 开关
///
/// 档位归一：off / auto / low / medium / high / max；旧值 on → high；未知 → auto。
fn thinking_extra_body(model: &str, level: &str, protocol: Protocol) -> Option<Value> {
    let level = match level {
        "off" => "off",
        "on" | "high" => "high",
        "low" => "low",
        "medium" => "medium",
        "max" => "max",
        _ => "auto",
    };
    let m = model.to_ascii_lowercase();
    // Anthropic 协议：思考以 thinking{type:enabled,budget_tokens} 表达。
    // 目前只有 MiniMax 家族在 anthropic 端点上有明确的 thinking 语义（官方文档：
    // "Supports thinking blocks"）；其余模型（含官方 Claude）不注入，保持请求最小化。
    if protocol == Protocol::Anthropic {
        if level == "auto" || !m.contains("minimax") {
            return None;
        }
        if level == "off" {
            return None; // Anthropic：省略 thinking 即关闭
        }
        let budget = match level {
            "low" => 2048,
            "medium" => 8192,
            "high" => 16384,
            "max" => 32768,
            _ => 16384,
        };
        return Some(json!({"thinking": {"type": "enabled", "budget_tokens": budget}}));
    }
    if level == "auto" {
        return None;
    }

    // GLM-5.3 家族（含 5.3-flash，bigmodel/z.ai 同构）：强制思考，仅 low/high/max
    if m.contains("glm-5.3") { // -flash 后缀被前项包含
        return Some(json!({"reasoning_effort": match level {
            "off" | "low" => "low",
            "medium" | "high" => "high",
            _ => "max",
        }}));
    }
    // Kimi k3 / 订阅 kimi-for-coding：恒开思考；off→none（路由无思考版）；无 medium
    if m.contains("k3") || m.contains("kimi-for-coding") {
        return Some(json!({"reasoning_effort": match level {
            "off" => "none",
            "medium" => "high",
            lv => lv,
        }}));
    }
    // Kimi k2.x：仅开关
    if m.contains("kimi") || m.contains("moonshot") {
        if level == "off" {
            return Some(json!({"thinking": {"type": "disabled"}}));
        }
        return None;
    }
    // GLM-5.2 及更早：开关 + 全档 effort
    if m.contains("glm") {
        if level == "off" {
            return Some(json!({"thinking": {"type": "disabled"}}));
        }
        return Some(json!({"reasoning_effort": level}));
    }
    // MiniMax：仅开关，无等级
    if m.contains("minimax") {
        if level == "off" {
            return Some(json!({"thinking": {"type": "disabled"}}));
        }
        return None;
    }
    // StepFun（含 Step Plan）：effort 三档，无开关
    if m.contains("step") {
        return Some(json!({"reasoning_effort": match level {
            "off" | "low" => "low",
            "max" => "high",
            lv => lv,
        }}));
    }
    // DeepSeek：开关 + effort（medium 等由服务端映射）
    if m.contains("deepseek") {
        if level == "off" {
            return Some(json!({"thinking": {"type": "disabled"}}));
        }
        return Some(json!({"reasoning_effort": level}));
    }
    // Qwen：DashScope 严格——仅 vLLM 自部署 off 方言
    if m.contains("qwen") {
        if level == "off" {
            return Some(json!({"chat_template_kwargs": {"enable_thinking": false}}));
        }
        return None;
    }
    // 默认（未知/自定义模型）：OpenAI 标准字段直传，严格端点的 4xx 会透传给用户
    if level == "off" {
        return Some(json!({"thinking": {"type": "disabled"}}));
    }
    Some(json!({"reasoning_effort": level}))
}

/// 只读 op 分类表：命中即走只读路由（session API 或直调导出），不进 apply 分发器。
/// engine-v0.1.1-fix 的 session API 已导出检视面——此前该表只是"不可达"拦截名单，
/// 现已转回路由白名单语义（本注释处的预言成真）。变更类 op 绝不能入表——
/// 入表会被只读分支拦下而非提交。list-tools/doc-json 无对应 wasm 导出，
/// 路由时保持诚实报错（见 moonviz_op 的 unavailable 分支）。
const READONLY_OPS: [&str; 22] = [
    // 无参清点类（list-ops：变更 op 注册表，与 SKILL/INSTRUCTIONS 推荐一致）
    "list", "list-templates", "list-components", "list-tools", "list-tokens", "list-themes",
    "list-ops", "flows", "benchmark",
    // 需 <artboard> 的检视类
    "lint", "critique", "query", "infer", "spec", "missing", "doc-json", "states",
    "interactions", "export-svg", "export-html", "extract-design-system",
    // 需 <artboard> <x> <y> 的模拟类
    "tap",
];

fn is_readonly_op(op: &str) -> bool {
    match op.split_whitespace().next() {
        Some(head) => READONLY_OPS.contains(&head),
        None => false,
    }
}

/// Agent 会话的引擎执行状态。mbt 是会话内唯一事实源（每 op 提交后更新为引擎
/// 回传的 canonical 文本）；last_render 保证终态返回总是带 artboards/svg。
struct EngineState<'a> {
    host: &'a EngineHost,
    mbt: Option<String>,
    last_render: Option<Value>,
    /// last_render 渲染时的 canonical。session 变更路径不逐 op 渲染（省 N-1 次
    /// 全量渲染），终态据此判断 render 是否已过期、要不要补一次 render_mbt。
    rendered_mbt: Option<String>,
    ops: Vec<String>,
}

fn b64_decode(s: &str) -> Result<String, String> {
    use base64::Engine as _;
    BASE64
        .decode(s)
        .map(|b| String::from_utf8_lossy(&b).into_owned())
        .map_err(|e| format!("mbt_b64_invalid:{e}"))
}

fn b64_encode(s: &str) -> String {
    use base64::Engine as _;
    BASE64.encode(s.as_bytes())
}

impl<'a> EngineState<'a> {
    fn new(host: &'a EngineHost, mbt_b64: Option<&str>) -> Result<Self, String> {
        Ok(Self {
            host,
            mbt: match mbt_b64 {
                Some(b) if !b.is_empty() => Some(b64_decode(b)?),
                _ => None,
            },
            last_render: None,
            rendered_mbt: None,
            ops: Vec::new(),
        })
    }

    /// 宿主调用（带 30s 超时与错误归一）。
    async fn call(&self, fn_name: &str, mbt: &str, op: &str) -> Value {
        match tokio::time::timeout(ENGINE_OP_TIMEOUT, self.host.call(fn_name, mbt, op)).await {
            Ok(Ok(v)) => v,
            Ok(Err(e)) => json!({"ok": false, "error": e}),
            Err(_) => json!({"ok": false, "error": "engine_timeout"}),
        }
    }

    /// moonviz_op 工具：空项目种子引导 / 只读拦截 / apply-op 三条路径。
    async fn moonviz_op(&mut self, op: &str) -> Value {
        let op = op.trim();
        if op.is_empty() {
            return json!({"ok": false, "error": "op_invalid"});
        }
        if op.contains('\n') || op.contains('\r') {
            return json!({"ok": false, "error": "op_newline_forbidden"});
        }

        // 空项目起步：template/create 经种子文档引导，与后续 op 同走 **AgentGate**——
        // 系统提示词向模型承诺"每个 op 都经 AgentGate"，首板不是例外（0.1.5-fix-2
        // 修复 moonviz#14 模板内容债后回收；此前因 4 模板自带债被迫走人类门）。
        // 首个 op 落地后立即删除种子画板，canonical 由引擎回传。
        if self.mbt.is_none()
            && matches!(op.split_whitespace().next(), Some("template") | Some("create"))
        {
            let seed = seed_doc(SEED_BOARD, 24, 24);
            let mut r = self.call("apply_agent_op", &seed, op).await;
            if r.get("ok") != Some(&json!(true)) {
                return r;
            }
            let committed = r
                .get("mbt")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            r = self.call("apply_agent_op", &committed, &format!("delete-artboard {SEED_BOARD}")).await;
            if r.get("ok") != Some(&json!(true)) {
                return json!({"ok": false, "error": format!("seed_cleanup_failed:{op}")});
            }
            self.mbt = r.get("mbt").and_then(|v| v.as_str()).map(String::from);
            self.rendered_mbt = self.mbt.clone();
            self.last_render = Some(r.clone());
            self.ops.push(op.to_string());
            return json!({
                "ok": true, "op": op,
                "revision": r.get("revision").cloned().unwrap_or(json!(0)),
                "artboards": r.get("artboards").map(artboard_index).unwrap_or(json!([])),
            });
        }

        let Some(mbt) = self.mbt.clone() else {
            return json!({"ok": false, "error": "no_mbt_loaded"});
        };

        // 只读 op：路由到 session API / 直调导出（engine-v0.1.1-fix 起检视面可达）。
        // 路由表：CLI op 头 → (wasm 导出名, 是否走 session 包装)。session 类导出的
        // 参数（artboard / x y）由 op 的剩余部分携带；宿主按 mbt 键控缓存复用会话
        // （缓存键与变更路径同源——只读突发在变更间免重解析）。
        if is_readonly_op(op) {
            let head = op.split_whitespace().next().unwrap_or("");
            let args = op[head.len()..].trim();
            let (fn_name, _session) = match head {
                // session API（宿主包装生命周期）
                "list" => ("session_list_artboards", true),
                "lint" => ("session_lint", true),
                "critique" => ("session_critique", true),
                "query" => ("session_query_nodes", true),
                "infer" => ("session_infer_page_type", true),
                "spec" => ("session_spec", true),
                "missing" => ("session_infer_missing", true),
                "states" => ("session_states", true),
                "interactions" => ("session_interactions", true),
                "flows" => ("session_flows", true),
                "export-svg" => ("session_export_svg", true),
                // engine-v0.1.6 新增：设计系统提取（颜色/尺寸 token 用量+置信度）
                "extract-design-system" => ("session_extract_design_system", true),
                "tap" => ("session_tap", true),
                "benchmark" => ("session_benchmark", true),
                // 直调导出（无状态）
                "list-templates" => ("list_templates", false),
                "list-components" => ("list_components", false),
                "list-tokens" => ("list_tokens", false),
                "list-themes" => ("list_themes", false),
                "list-ops" => ("list_ops", false),
                "export-html" => ("export_html", false),
                // 无对应 wasm 导出：保持诚实报错（不假装可用）
                "list-tools" | "doc-json" => {
                    return json!({
                        "ok": false, "op": op,
                        "error": "wasm_engine_export_unavailable",
                        "hint": format!("{head} has no wasm export in this engine build — use read_mbt / list-ops style introspection instead"),
                    });
                }
                _ => return json!({"ok": false, "error": format!("unknown_readonly_op:{head}")}),
            };
            // 宿主按 fn 名前缀自行判断 session 包装（元组第二元素因此不用）
            let r = self.call(fn_name, &mbt, args).await;
            // 与变更路径同构的诚实契约：引擎侧失败不得记为已执行的成功 op
            // （r 可能是 {ok:false,error:unknown_artboard:...}）
            if r.get("ok") == Some(&json!(false)) {
                return json!({"ok": false, "op": op, "error": r.get("error").cloned().unwrap_or(json!("readonly_failed"))});
            }
            // 0.1.6-fix/#19：改文档面的只读形态 op（tap 的交互可改文档状态）成功信封
            // 带 canonical——推进自持文档（宿主同句柄已键前移，两侧必须一致，否则下一个
            // 变更 op 会按旧键重开丢掉 tap 的状态变更），并从历史结果剥除 mbt
            // （LLM 不消费全量 canonical；终态经 mbt_b64 统一交付）
            let mut r = r;
            if let Some(m) = r.get("mbt").and_then(|v| v.as_str()).map(String::from) {
                self.mbt = Some(m);
                if let Some(obj) = r.as_object_mut() {
                    obj.remove("mbt");
                }
            }
            self.ops.push(op.to_string());
            // L0 整形：export-* 信封化 / 检视类超限截断（失败信封已在内部原样放行）
            return shape_readonly_result(op, r);
        }

        // constrain：布局意图解析器，session 管道专属——apply 门不认
        // （mbt_operation_unsupported），走 session_constrain（宿主 Arg2 槽：
        // artboard + 意图串）。0.1.6-fix/#19 起成功信封带 canonical → 与变更路径
        // 同构（键前移 + 记 ops）；命中信息（节点/坐标）随信封回传，mbt 剥除。
        // cannot_parse 就地返回意图词表（#17「错误即文档」），模型可据此自纠。
        if op.split_whitespace().next() == Some("constrain") {
            let args = op["constrain".len()..].trim();
            let r = self.call("session_constrain", &mbt, args).await;
            if !(r.get("ok") == Some(&json!(true)) && r.get("mbt").and_then(|v| v.as_str()).is_some()) {
                return r;
            }
            self.mbt = r.get("mbt").and_then(|v| v.as_str()).map(String::from);
            self.ops.push(op.to_string());
            let mut out = json!({"ok": true, "op": op});
            if let (Some(o), Some(src)) = (out.as_object_mut(), r.as_object()) {
                for (k, v) in src {
                    if k != "mbt" {
                        o.insert(k.clone(), v.clone());
                    }
                }
            }
            return out;
        }

        // 变更操作：session_apply_agent（AgentGate——engine-v0.1.1-session 修复
        // 上游 issue #2 的门旁路后，与无状态 apply_agent_op 同门同分发器；引擎
        // 内部经 canonical 往返 + 门检查，CPU 与无状态持平）。宿主按 mbt 键控
        // 复用会话的收益：内存棘轮减半（200 op 实测 +37MB vs +84MB，降低 192MB
        // 实例回收频率）、只读突发（lint/critique/query 连发）免重解析、上游
        // 优化 session 内部实现时零改动受益。信封 {ok,mbt,artboards}（宿主同
        // 句柄补画板索引），无 per-op render——终态经 ensure_render 兜底一次。
        let r = self.call("session_apply_agent", &mbt, op).await;
        if r.get("ok") == Some(&json!(true)) && r.get("mbt").and_then(|v| v.as_str()).is_some() {
            self.mbt = r.get("mbt").and_then(|v| v.as_str()).map(String::from);
            self.ops.push(op.to_string());
            json!({
                "ok": true, "op": op,
                "artboards": r.get("artboards").map(artboard_index).unwrap_or(json!([])),
            })
        } else {
            r
        }
    }

    async fn read_mbt(&self) -> Value {
        match &self.mbt {
            // L0 整形：剥 ```mbt check 围栏块（引擎对节点声明的逐字重复，~40-50%）。
            // ids/属性全保留在视觉声明块里；前端终态仍拿完整 canonical（mbt_b64）。
            Some(m) => json!({
                "ok": true,
                "mbt": strip_mbt_check_blocks(m),
                "note": "'mbt check' test fences stripped to save context (they duplicate the source declarations verbatim); all ids and properties are intact in the visual blocks",
            }),
            None => json!({"ok": false, "error": "no_mbt_loaded"}),
        }
    }

    /// 终态 render 兜底（移植自 JS 桥）：无 apply 渲染的会话（只读尝试/零变更）
    /// 用 render_mbt 补齐，保证前端 applyMbtResult 拿到的不是 null。
    async fn ensure_render(&mut self) {
        let Some(mbt) = self.mbt.clone() else { return };
        if self.last_render.is_some() && self.rendered_mbt.as_deref() == Some(mbt.as_str()) {
            return;
        }
        let rendered = self.call("render_mbt", &mbt, "").await;
        if rendered.get("mbt").is_some_and(|v| v.is_string()) {
            self.last_render = Some(rendered);
            self.rendered_mbt = Some(mbt);
        } else {
            // 渲染失败：清掉陈旧 last_render——宁可诚实 null（前端走本地重渲染
            // 兜底）也不要旧 render 与新 canonical 配对发出（画布会显示变更前画面）
            self.last_render = None;
            self.rendered_mbt = None;
        }
    }

    /// 组件清单：经桥取前端同源快照（sync-engine.mjs 依引擎 list_components
    /// 导出生成；桥不直调 wasm——快照带 description 文案并并入用户组件）。
    async fn list_components(&self) -> Value {
        let r = self.call("list_components", "", "").await;
        match r.get("components").and_then(|v| v.as_array()) {
            Some(arr) => json!({"ok": true, "components": arr}),
            None => json!({"ok": false, "error": r.get("error").cloned().unwrap_or(json!("components_unavailable"))}),
        }
    }
}

fn artboard_index(a: &Value) -> Value {
    match a.as_array() {
        Some(list) => Value::Array(
            list.iter()
                .map(|x| json!({"id": x.get("id").cloned().unwrap_or(json!(null)), "name": x.get("name").cloned().unwrap_or(json!(null))}))
                .collect(),
        ),
        None => json!([]),
    }
}

// ===================== 上下文管理（分层裁剪，设计见 docs/agent-context.md） =====================
// 背景：历史全链路曾零截断——read_mbt 全量 canonical 入历史（其中每画板的
// ```mbt check 围栏块把节点声明逐字重复第二遍，真机实测占 ~40-50%），export-svg/html
// 整段渲染体入历史，200 步上限下历史随轮次线性膨胀。三层确定性裁剪（不做 LLM
// 摘要压缩——那是演进方向）：
//   L0 源头整形：read_mbt 剥 check 围栏块；export-* 只回信封；检视类超限头尾截断。
//   L1 去supersede：同类工具（read_mbt/list_components）的新结果出现后，旧结果占位化。
//   L2 预算守卫：估算超阈值时，最近 RECENT_TOOL_KEEP 条之外的 tool 内容全部占位化。
// 硬约束：只缩 tool 消息的 content，绝不删消息——OpenAI wire 要求每个 tool_call_id
// 都有配对的 tool 消息，删消息 = 协议错误。messages 本体完整保留（轨迹/journal 用），
// 收缩只发生在请求侧副本上。

/// L0：剥除所有 ```mbt check 围栏块。check 块逐字重复源声明的每个 page.add(...)
/// 节点、仅多两行 assert（真机对照实证），剥除不丢任何 id/属性信息。
/// 仅用于 LLM 侧 read_mbt 整形；前端终态 mbt_b64 仍交付完整 canonical。
fn strip_mbt_check_blocks(mbt: &str) -> String {
    let mut out = String::with_capacity(mbt.len());
    let mut rest = mbt;
    while let Some(start) = rest.find("```mbt check") {
        out.push_str(&rest[..start]);
        let after = &rest[start + "```mbt check".len()..];
        match after.find("\n```") {
            Some(end) => rest = &after[end + "\n```".len()..],
            // 没有闭合 fence（畸形输入）：保守起见保留剩余全部
            None => {
                out.push_str(&rest[start..]);
                return out;
            }
        }
    }
    out.push_str(rest);
    out
}

/// L0：检视类结果的体积上限（超限头尾截断，保 [truncated] 标记）。
const READONLY_RESULT_CAP: usize = 12 * 1024;

/// L0：export-svg / export-html 的渲染体对后续设计决策零信息量（LLM 不消费 SVG/HTML
/// 全文），只回信封；其余检视结果（lint/critique/spec/query/...）超 12KB 头尾截断。
/// 失败信封（ok:false）原样放行——错误详情是模型自纠的输入，不得截。
fn shape_readonly_result(op: &str, r: Value) -> Value {
    if r.get("ok") == Some(&json!(false)) {
        return json!({"ok": false, "op": op, "error": r.get("error").cloned().unwrap_or(json!("readonly_failed"))});
    }
    let head = op.split_whitespace().next().unwrap_or(op);
    if head == "export-svg" || head == "export-html" {
        let text = serde_json::to_string(&r).unwrap_or_default();
        return json!({
            "ok": true, "op": op,
            "bytes": text.len(),
            "head": text.chars().take(400).collect::<String>(),
            "note": "render body elided (envelope only); the artifact itself is not needed for further design steps",
        });
    }
    let text = serde_json::to_string(&r).unwrap_or_default();
    if text.len() <= READONLY_RESULT_CAP {
        return json!({"ok": true, "op": op, "result": r});
    }
    let head_len = READONLY_RESULT_CAP - 2 * 1024;
    let head_part: String = text.chars().take(head_len).collect();
    let mut tail_start = text.len().saturating_sub(2 * 1024);
    while tail_start < text.len() && !text.is_char_boundary(tail_start) {
        tail_start += 1;
    }
    let tail_part = &text[tail_start..];
    json!({
        "ok": true, "op": op,
        "result": format!("{head_part}\n…[truncated {} of {} bytes]…\n{tail_part}",
            text.len() - head_part.len() - tail_part.len(), text.len()),
        "truncated": true,
        "bytes": text.len(),
    })
}

/// L1：请求侧历史去supersede。tool 消息 content 为 JSON 字符串——带 "mbt" 键的是
/// read_mbt 结果、带 "components" 键的是 list_components 结果；每类只保留最后一个
/// （最新的才是当前真相），旧的替换为占位。中间过程值对后续轮次无信息量，
/// 却随轮次线性累积（提示词要求 create 后 read、VERIFY 再 read）。
fn supersede_stale_tool_results(messages: &[Value]) -> Vec<Value> {
    fn kind_of(m: &Value) -> Option<&'static str> {
        if m.get("role").and_then(|v| v.as_str()) != Some("tool") {
            return None;
        }
        let c = m.get("content")?.as_str()?;
        let v: Value = serde_json::from_str(c).ok()?;
        if v.get("mbt").is_some() {
            Some("read_mbt")
        } else if v.get("components").is_some() {
            Some("list_components")
        } else {
            None
        }
    }
    let mut last: std::collections::HashMap<&'static str, usize> = Default::default();
    for (i, m) in messages.iter().enumerate() {
        if let Some(k) = kind_of(m) {
            last.insert(k, i);
        }
    }
    messages
        .iter()
        .enumerate()
        .map(|(i, m)| match kind_of(m) {
            Some(k) if last.get(k) != Some(&i) => {
                let mut r = m.clone();
                r["content"] = json!(format!(
                    "[superseded by a later {k} result — call {k} for the current state]"
                ));
                r
            }
            _ => m.clone(),
        })
        .collect()
}

/// L2 预算回落值：128K tokens（模型未命中快照时的保守默认）。
const DEFAULT_CONTEXT_TOKENS: usize = 128 * 1024;
/// 逐模型上下文窗口（models.json 快照的 limit.context，tokens）。模型名可能带
/// provider 前缀（"deepseek/xxx"），取末段做**精确**匹配——快照 id 是闭集，
/// 包含匹配会撞错型号。查不到回落保守默认；查到则设 16K 下限防上游脏数据。
fn model_context_window(model: &str) -> usize {
    let bare = model.trim().rsplit('/').next().unwrap_or("").to_lowercase();
    if bare.is_empty() {
        return DEFAULT_CONTEXT_TOKENS;
    }
    let doc = crate::models::snapshot_document();
    if let Some(providers) = doc.get("providers").and_then(|v| v.as_object()) {
        for p in providers.values() {
            if let Some(models) = p.get("models").and_then(|v| v.as_object()) {
                for (id, m) in models {
                    if id.to_lowercase() == bare {
                        if let Some(ctx) = m.pointer("/limit/context").and_then(|v| v.as_u64()) {
                            return (ctx as usize).max(16 * 1024);
                        }
                    }
                }
            }
        }
    }
    DEFAULT_CONTEXT_TOKENS
}
/// 触发激进裁剪的阈值比例（给摘要/回复留余量）。
const CONTEXT_BUDGET_RATIO: f64 = 0.7;
/// L2 激进裁剪时，最近 N 条 tool 结果保持原样（近期上下文最相关）。
const RECENT_TOOL_KEEP: usize = 6;

fn estimate_context_bytes(messages: &[Value]) -> usize {
    messages
        .iter()
        .map(|m| serde_json::to_string(m).map(|s| s.len()).unwrap_or(0))
        .sum()
}

/// L2：预算超限时把最近 RECENT_TOOL_KEEP 条之外的 tool 消息内容占位化。
/// 返回（收缩后副本, 被占位化的字节数）。
fn elide_stale_tool_contents(messages: &[Value]) -> (Vec<Value>, usize) {
    let keep: std::collections::HashSet<usize> = messages
        .iter()
        .enumerate()
        .filter(|(_, m)| m.get("role").and_then(|v| v.as_str()) == Some("tool"))
        .map(|(i, _)| i)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .take(RECENT_TOOL_KEEP)
        .collect();
    let mut elided = 0usize;
    let out = messages
        .iter()
        .enumerate()
        .map(|(i, m)| {
            if m.get("role").and_then(|v| v.as_str()) == Some("tool") && !keep.contains(&i) {
                let mut r = m.clone();
                let old = r.get("content").and_then(|v| v.as_str()).map(|s| s.len()).unwrap_or(0);
                r["content"] = json!("[elided: stale tool output beyond context budget]");
                elided += old;
                r
            } else {
                m.clone()
            }
        })
        .collect();
    (out, elided)
}

/// OpenAI chat tools 定义：async-openai 类型层构造（wire schema 的权威形态）。
/// 必须用 ChatCompletionTools::Function 包装——裸 ChatCompletionTool 序列化
/// 不带 "type":"function" 判别字段，会改变 wire 格式（兼容网关会拒收）。
fn tools_typed() -> Vec<ChatCompletionTools> {
    let tool = |name: &str, description: &str, parameters: Value| {
        ChatCompletionTools::Function(ChatCompletionTool {
            function: FunctionObject {
                name: name.to_string(),
                description: Some(description.to_string()),
                parameters: Some(parameters),
                ..Default::default()
            },
        })
    };
    vec![
        tool(
            "moonviz_op",
            "Execute one MoonViz MUTATING design operation (validated by the engine gates, committed to .mbt.md): template/create/duplicate/delete-artboard/place/move/update/delete/copy/reorder/flip/group/ungroup/align/resize-canvas/responsive/restyle/constrain/interact/uninteract/state/set-state/flow/theme/token/fix. Also supports READ-ONLY inspection ops routed via the engine session API (no commit): list, flows, list-templates, list-components, list-tokens, list-themes, lint <ab>, critique <ab>, query <ab>, infer <ab>, spec <ab>, missing <ab>, states <ab>, interactions <ab>, export-svg <ab>, export-html, extract-design-system <ab>, tap <ab> <x> <y>, benchmark. Exceptions without wasm exports: list-tools, doc-json.",
            json!({
                "type": "object",
                "properties": {"op": {"type": "string", "description": "One operation string, e.g. \"update login title text=\\\"Sign in\\\"\""}},
                "required": ["op"]
            }),
        ),
        tool(
            "read_mbt",
            "Read the current canonical .mbt.md source of truth (node ids, flows, all screens).",
            json!({"type": "object", "properties": {}}),
        ),
        tool(
            "list_components",
            "List all engine UI component presets (id, category, variants).",
            json!({"type": "object", "properties": {}}),
        ),
    ]
}

/// tools 的序列化形态（anthropic_tools 转换与契约测试消费）。
fn tools_schema() -> Value {
    serde_json::to_value(tools_typed()).expect("tools schema 序列化不可失败（纯数据结构）")
}

/// OpenAI 请求体：SDK 类型骨架 + 原始 messages 逐字合并 + thinking 方言注入。
/// 拆成独立函数是为了 wire 契约测试——typed 骨架不得吞掉 messages 里的非标字段
/// （MiniMax 多轮要求 assistant 消息（含 reasoning_content）完整回传）。
fn openai_request_body(model: &str, thinking: &str, messages: &[Value]) -> Value {
    let typed = CreateChatCompletionRequest {
        model: model.to_string(),
        tools: Some(tools_typed()),
        ..Default::default()
    };
    let mut body =
        serde_json::to_value(&typed).expect("chat 请求骨架序列化不可失败（纯数据结构）");
    body["messages"] = Value::Array(messages.to_vec());
    if let Some(extra) = thinking_extra_body(model, thinking, Protocol::OpenAi) {
        if let (Some(obj), Some(extra_obj)) = (body.as_object_mut(), extra.as_object()) {
            for (k, v) in extra_obj {
                obj.insert(k.clone(), v.clone());
            }
        }
    }
    body
}

/// 模型端点校验：https 任意主机；http 仅放行本机/内网（本地 LLM 如 Ollama/vLLM）。
/// 内网判定用 std::net IP 解析（精确覆盖 10/8、172.16/12、192.168/16 回环与链路本地），
/// 避免 starts_with 前缀误放行公网段（如 172.2.x.x）或 DNS 名（如 10.evil.com）。
fn is_local_host(host: &str) -> bool {
    if host == "localhost" {
        return true;
    }
    let h = host.trim_matches(|c| c == '[' || c == ']');
    match h.parse::<std::net::IpAddr>() {
        Ok(std::net::IpAddr::V4(v4)) => {
            v4.is_loopback() || v4.is_private() || v4.is_link_local()
        }
        Ok(std::net::IpAddr::V6(v6)) => v6.is_loopback(),
        Err(_) => false,
    }
}

fn safe_base_url(u: &str) -> Option<String> {
    let u = u.trim();
    if u.is_empty() {
        return Some("https://api.deepseek.com".into());
    }
    let parsed = reqwest::Url::parse(u).ok()?;
    let host = parsed.host_str()?;
    if parsed.scheme() == "https" || (parsed.scheme() == "http" && is_local_host(host)) {
        Some(parsed.to_string())
    } else {
        None
    }
}

/// 单次 LLM 请求：按 protocol_for 分流——OpenAI Chat Completions（bearer）或
/// Anthropic Messages（x-api-key + anthropic-version）；后者归一化为 OpenAI 形状返回。
async fn chat_once(
    client: &reqwest::Client,
    base_url: &str,
    api_key: &str,
    model: &str,
    thinking: &str,
    messages: &[Value],
) -> Result<Value, String> {
    let protocol = protocol_for(base_url);
    let req = match protocol {
        Protocol::OpenAi => {
            let body = openai_request_body(model, thinking, messages);
            let url = format!("{}/chat/completions", base_url.trim_end_matches('/'));
            client.post(&url).bearer_auth(api_key).json(&body)
        }
        Protocol::Anthropic => {
            let thinking_extra = thinking_extra_body(model, thinking, Protocol::Anthropic);
            // budget_tokens 必须小于 max_tokens（Anthropic 硬约束）：按预算预留余量
            let budget = thinking_extra
                .as_ref()
                .and_then(|v| v.pointer("/thinking/budget_tokens"))
                .and_then(|v| v.as_u64())
                .unwrap_or(0);
            let max_tokens = if budget > 0 { budget + 4096 } else { 8192 };
            let (system, msgs) = to_anthropic_messages(messages);
            let mut body = json!({
                "model": model,
                "max_tokens": max_tokens,
                "messages": msgs,
                "tools": anthropic_tools(),
            });
            if let Some(sys) = system {
                body["system"] = json!(sys);
            }
            if let Some(extra) = thinking_extra {
                body["thinking"] = extra["thinking"].clone();
            }
            // 剥掉尾部 /v1 再拼：用户可能粘贴 models.dev 记录值（.../anthropic/v1），
            // 不剥会出现 /anthropic/v1/v1/messages 的双 /v1
            let base_no_v1 = base_url
                .trim_end_matches('/')
                .strip_suffix("/v1")
                .unwrap_or_else(|| base_url.trim_end_matches('/'));
            let url = format!("{base_no_v1}/v1/messages");
            client
                .post(&url)
                .header("x-api-key", api_key)
                .header("anthropic-version", "2023-06-01")
                .json(&body)
        }
    };
    let resp = req
        .send()
        .await
        .map_err(|e| redact_userinfo(format!("llm_request_failed:{e}")))?;
    let status = resp.status();
    let text = resp
        .text()
        .await
        .map_err(|e| redact_userinfo(format!("llm_read_failed:{e}")))?;
    if !status.is_success() {
        return Err(format!("llm_http_{}:{}", status.as_u16(), text.chars().take(200).collect::<String>()));
    }
    let parsed: Value = serde_json::from_str(&text).map_err(|e| format!("llm_response_invalid:{e}"))?;
    match protocol {
        Protocol::OpenAi => Ok(parsed),
        Protocol::Anthropic => {
            // Anthropic 兼容网关（含 MiniMax /anthropic 代理）可能以 200 返回
            // {"type":"error","error":{...}}（过载/计费/审核）。不拦的话会被
            // 归一化成空回合，主循环误报"LLM did not call any tools"。
            if parsed.get("type").and_then(|v| v.as_str()) == Some("error")
                || parsed.get("error").is_some()
            {
                let msg = parsed
                    .pointer("/error/message")
                    .or_else(|| parsed.pointer("/error"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("unknown");
                let kind = parsed
                    .pointer("/error/type")
                    .and_then(|v| v.as_str())
                    .unwrap_or("api_error");
                return Err(format!("llm_api_error:{kind}:{msg}"));
            }
            Ok(normalize_anthropic_response(&parsed))
        }
    }
}

/// 错误串里的 URL 可能带 userinfo（https://u:p@host，url crate 的 Display 会原样
/// 保留）——回显前脱敏，避免凭据进错误信封/前端 toast。
fn redact_userinfo(s: String) -> String {
    if let Some(scheme_end) = s.find("://") {
        let rest_start = scheme_end + 3;
        if let Some(at) = s[rest_start..].find('@') {
            let cred = &s[rest_start..rest_start + at];
            if !cred.contains('/') && cred.contains(':') {
                return format!("{}//***@{}", &s[..rest_start], &s[rest_start + at + 1..]);
            }
        }
    }
    s
}

/// 瞬时 LLM 错误判定：限流/过载/服务端错误/传输层失败（一轮内重试一次）。
/// 4xx（鉴权/参数）与解析错误是语义性的，重试只会重复失败。
fn is_transient_llm_error(e: &str) -> bool {
    e.starts_with("llm_request_failed")
        || e.starts_with("llm_read_failed")
        || e.contains("llm_http_429")
        || e.contains("llm_http_5")
        || e.contains("overloaded")
}

/// LLM 调用 + 瞬时错误指数退避重试（3 次：0.8s/2.5s/5s）——
/// 本机网络对部分端点存在间歇性 TLS/连接阻断，单发失败不代表性故障
async fn chat_once_with_retry(
    client: &reqwest::Client,
    base: &str,
    api_key: &str,
    model: &str,
    thinking: &str,
    messages: &[Value],
) -> Result<Value, String> {
    let mut last = String::new();
    for wait in [0u64, 800, 2500, 5000] {
        if wait > 0 {
            tokio::time::sleep(std::time::Duration::from_millis(wait)).await;
        }
        match chat_once(client, base, api_key, model, thinking, messages).await {
            Ok(v) => return Ok(v),
            Err(e) => {
                last = e;
                if !is_transient_llm_error(&last) {
                    return Err(last); // 4xx 语义错误不重试
                }
            }
        }
    }
    Err(last)
}

/// 主循环：chat → tool_calls → 引擎执行 → 回填 → 直至 assistant 总结或 maxSteps。
pub async fn run(
    host: &EngineHost,
    instruction: &str,
    mbt_b64: Option<&str>,
    api_key: &str,
    model: &str,
    base_url: &str,
    thinking: &str,
    progress: Option<&(dyn Fn(Value) + Send + Sync)>,
) -> Value {
    if api_key.trim().is_empty() {
        return json!({"ok": false, "error": "api_key_missing"});
    }
    let Some(base) = safe_base_url(base_url) else {
        return json!({"ok": false, "error": "base_url_invalid_https_or_local"});
    };
    let model = if model.trim().is_empty() { "deepseek-chat" } else { model.trim() };
    let mut state = match EngineState::new(host, mbt_b64) {
        Ok(s) => s,
        Err(e) => return json!({"ok": false, "error": e}),
    };

    // 不跟随重定向：safe_base_url 只审计首跳，reqwest 默认会跟 10 跳且剥离名单
    // 不含 x-api-key（跨主机泄 key）/不拦 https→http 降级（泄 bearer）。
    // API 端点不应重定向——真发生时把 3xx 亮给用户，而不是静默带凭据跟跳。
    let Ok(client) = reqwest::Client::builder()
        .timeout(LLM_TIMEOUT)
        .redirect(reqwest::redirect::Policy::none())
        .build()
    else {
        return json!({"ok": false, "error": "client_build_failed", "ops": state.ops, "text": ""});
    };

    let mut messages: Vec<Value> = vec![
        json!({"role": "system", "content": instructions()}),
        json!({"role": "user", "content": instruction}),
    ];
    // 运行日志（stderr → tauri dev 控制台）：无落盘日志时的最小可诊断性——
    // 每次 op 的结果、run 起止与终态。eprintln 只影响调试，不进产品 UI。
    eprintln!(
        "[agent] run start: {:?} (doc {} bytes, model {})",
        instruction.chars().take(60).collect::<String>(),
        mbt_b64.map(|b| b.len()).unwrap_or(0),
        model
    );

    // 实时轨迹推送（前端 Agent 追踪面板）：每步 LLM 回复 / 工具调用 / 结果
    let emit = |typ: &str, v: Value| {
        if let Some(f) = progress {
            let mut full = json!({"type": typ});
            if let (Some(obj), Some(src)) = (full.as_object_mut(), v.as_object()) {
                for (k, val) in src {
                    obj.insert(k.clone(), val.clone());
                }
            }
            f(full);
        }
    };
    let mut seq: usize = 0;
    let mut context_event_sent = false;
    // L2 预算按模型窗口取（tokens → utf-8 字节近似 /3——CJK 精确、英文高估即保守）
    let context_budget_bytes = model_context_window(model) * 3;

    for step in 0..MAX_STEPS {
        // 上下文管理（请求侧收缩；messages 本体完整保留作轨迹/journal）：
        // L1 常态去supersede + L2 预算守卫（逐模型窗口，未命中回落 128K）
        let mut request_messages = supersede_stale_tool_results(&messages);
        let est = estimate_context_bytes(&request_messages);
        if est > (context_budget_bytes as f64 * CONTEXT_BUDGET_RATIO) as usize {
            let (shrunk, elided_bytes) = elide_stale_tool_contents(&request_messages);
            request_messages = shrunk;
            if !context_event_sent {
                context_event_sent = true;
                eprintln!(
                    "[agent] context budget: est ~{} tokens over {:.0}% of {} — elided {} bytes of stale tool output",
                    est / 3,
                    CONTEXT_BUDGET_RATIO * 100.0,
                    context_budget_bytes / 3,
                    elided_bytes
                );
                emit(
                    "context_usage",
                    json!({
                        "est_tokens": est / 3,
                        "budget_tokens": context_budget_bytes / 3,
                        "elided_bytes": elided_bytes,
                        "action": "elide_stale_tool",
                    }),
                );
            }
        }
        // 瞬时错误（限流/过载/网络抖动/TLS 握手被掐）指数退避重试：
        // 本机网络对部分端点间歇阻断，单次 800ms 重试实测不够
        let mut resp = chat_once_with_retry(&client, &base, api_key, model, thinking, &request_messages).await;
        let resp = match resp {
            Ok(r) => r,
            Err(e) => {
                // 中途 LLM 失败：已提交的引擎操作不丢弃（对齐旧桥语义）——
                // 零操作时才整体失败，否则带部分状态返回，前端可应用已完成的变更。
                emit("failed", json!({"error": e}));
                let partial = finish_partial(&mut state, &e).await;
                eprintln!("[agent] run end: stop=error ops={} error={e}", partial.get("ops").and_then(|v| v.as_array()).map(|a| a.len()).unwrap_or(0));
                return partial;
            }
        };
        let Some(msg) = resp
            .pointer("/choices/0/message")
            .and_then(|v| v.as_object().cloned())
        else {
            emit("failed", json!({"error": "llm_no_choice"}));
            return finish_partial(&mut state, "llm_no_choice").await;
        };
        let tool_calls: Vec<Value> = msg
            .get("tool_calls")
            .and_then(|v| v.as_array().cloned())
            .unwrap_or_default();

        // 中间轮的 assistant 文本（计划/说明）进轨迹
        let mid_text = msg.get("content").and_then(|v| v.as_str()).unwrap_or("");
        if !mid_text.trim().is_empty() && !tool_calls.is_empty() {
            emit("assistant_text", json!({"text": mid_text}));
        }

        if tool_calls.is_empty() {
            // 终态：assistant 总结
            let text = msg.get("content").and_then(|v| v.as_str()).unwrap_or("").to_string();
            if state.mbt.is_none() && state.ops.is_empty() {
                // 澄清式回复（CLARIFY-FIRST）：文本即 agent 的提问——照常推送轨迹
                emit("assistant_text", json!({"text": text}));
                emit("done", json!({"stopReason": "clarify", "ops": 0}));
                return json!({
                    "ok": false, "error": "agent_no_mbt",
                    "detail": "LLM did not call any tools",
                    "ops": state.ops, "text": text,
                });
            }
            state.ensure_render().await;
            // 走到这里说明 assistant 已给出自然总结——即便恰在第 MAX_STEPS 轮,
            // 语义是 done;max_turns 只属于循环耗尽仍无总结的路径（循环外兜底）
            let stop = if text.trim().is_empty() && step + 1 >= MAX_STEPS { "max_turns" } else { "done" };
            eprintln!("[agent] run end: stop={stop} ops={} text_len={}", state.ops.len(), text.len());
            emit("assistant_text", json!({"text": text}));
            emit("done", json!({"stopReason": stop, "ops": state.ops.len()}));
            return json!({
                "ok": state.mbt.is_some(),
                "mbt_b64": state.mbt.as_ref().map(|m| b64_encode(m)),
                "render": state.last_render.clone(),
                "ops": state.ops,
                "stopReason": stop,
                "text": text,
            });
        }

        // 回填 assistant 消息（含 tool_calls）后顺序执行每个调用。
        // MiniMax 多轮 tool 对话要求完整回传 assistant 消息以保留推理链。
        messages.push(Value::Object(msg));
        for call in tool_calls {
            let id = call.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let name = call.pointer("/function/name").and_then(|v| v.as_str()).unwrap_or("");
            let args_raw = call.pointer("/function/arguments").and_then(|v| v.as_str()).unwrap_or("{}");
            let trace_op = serde_json::from_str::<Value>(args_raw)
                .ok()
                .and_then(|a| a.get("op").and_then(|v| v.as_str()).map(String::from))
                .unwrap_or_else(|| args_raw.chars().take(60).collect());
            seq += 1;
            let seq_n = seq;
            emit("tool_start", json!({"seq": seq_n, "tool": name, "op": trace_op}));
            let t0 = std::time::Instant::now();
            // 畸形 JSON 带原文片段报错，模型可据此自纠（归并为 op_invalid 会多耗一轮）
            let result = match serde_json::from_str::<Value>(args_raw) {
                Err(_) => json!({"ok": false, "error": format!(
                    "op_arguments_invalid_json:{}", args_raw.chars().take(60).collect::<String>()
                )}),
                Ok(args) => match name {
                    "moonviz_op" => {
                        let op = args.get("op").and_then(|v| v.as_str()).unwrap_or("").to_string();
                        state.moonviz_op(&op).await
                    }
                    "read_mbt" => state.read_mbt().await,
                    "list_components" => state.list_components().await,
                    other => json!({"ok": false, "error": format!("unknown_tool:{other}")}),
                },
            };
            let ms = t0.elapsed().as_millis() as u64;
            let ok = result.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
            let err = result.get("error").and_then(|v| v.as_str()).map(String::from);
            eprintln!(
                "[agent] #{seq} {} `{}` -> {}{}{}",
                name,
                trace_op.chars().take(70).collect::<String>(),
                if ok { "ok" } else { "FAIL" },
                if ok { format!(" {ms}ms") } else { format!(" {}ms", ms) },
                match &err { Some(e) => format!(" error={e}"), None => String::new() },
            );
            let mut ev = json!({"seq": seq_n, "ok": ok, "ms": ms});
            if let Some(e) = &err {
                ev["error"] = json!(e);
            }
            emit("tool_end", ev);
            messages.push(json!({
                "role": "tool",
                "tool_call_id": id,
                "content": serde_json::to_string(&result).unwrap_or_else(|_| "{}".into()),
            }));
        }
    }

    // 跑满步数：尽力返回当前状态
    state.ensure_render().await;
    eprintln!("[agent] run end: stop=max_turns ops={}", state.ops.len());
    json!({
        "ok": state.mbt.is_some(),
        "mbt_b64": state.mbt.as_ref().map(|m| b64_encode(m)),
        "render": state.last_render.clone(),
        "ops": state.ops,
        "stopReason": "max_turns",
        "text": "",
    })
}

/// 中途失败的部分状态返回：零操作 → 纯失败；有已提交工作 → ok:true +
/// partial_error 说明，前端照常应用 mbt_b64/render 并提示部分完成。
async fn finish_partial(state: &mut EngineState<'_>, error: &str) -> Value {
    if state.mbt.is_none() && state.ops.is_empty() {
        return json!({"ok": false, "error": error, "ops": [], "text": ""});
    }
    state.ensure_render().await;
    json!({
        "ok": state.mbt.is_some(),
        "partial_error": error,
        "mbt_b64": state.mbt.as_ref().map(|m| b64_encode(m)),
        "render": state.last_render.clone(),
        "ops": state.ops,
        "stopReason": "error",
        "text": "",
    })
}

/// 终态 rebase（docs/agent-rebase.md 方案 C）：agent run 是秒级长任务，期间人类
/// 画布 op 可能已推进前端 canonical——整体回灌 run 终态文档会覆盖丢失人类编辑。
/// 把 run 的变更 op 流按执行序重放到**最新 canonical** 上：会话复用使命重放
/// 0.37ms/op；AgentGate 逐条重校验，「拒绝即跳过并报告」（op 在新基底上合法失效
/// 不是错误，宁缺勿债绝不留 gate debt）；只读 op 过滤（无副作用）。
/// 失败信封保留引擎错误原文（skipped[].error），供前端轨迹呈现与模型可见性。
pub async fn rebase_ops(host: &EngineHost, latest_mbt: &str, ops: &[String]) -> Value {
    let mut cur = latest_mbt.to_string();
    let mut applied: Vec<Value> = Vec::new();
    let mut skipped: Vec<Value> = Vec::new();
    for op in ops.iter().filter(|o| !is_readonly_op(o)) {
        // host 级失败（trap/腐坏读等 Err）与门拒绝同语义：跳过并保留错误原文，
        // 不中断整个 rebase（宿主随后自会弃缓存，下次按权威 canonical 重开）
        let r = match host.call("session_apply_agent", &cur, op).await {
            Ok(r) => r,
            Err(e) => {
                skipped.push(json!({"op": op, "error": e}));
                continue;
            }
        };
        if r.get("ok") == Some(&json!(true)) && r.get("mbt").and_then(|v| v.as_str()).is_some() {
            cur = r.get("mbt").and_then(|v| v.as_str()).unwrap_or_default().to_string();
            applied.push(json!(op));
        } else {
            skipped.push(json!({
                "op": op,
                "error": r.get("error").cloned().unwrap_or(json!("rebase_op_failed")),
            }));
        }
    }
    json!({
        "ok": true,
        "mbt_b64": b64_encode(&cur),
        "applied": applied,
        "skipped": skipped,
    })
}

/// /models 端点：OpenAI 兼容模型列表（设置面板「获取模型」）。
/// 与 run 路径不同：base_url 必填（空值报错，绝不静默替换默认端点——
/// 用户的 api_key 不能被发往未配置的目的地）。
pub async fn list_models(base_url: &str, api_key: &str) -> Value {
    if api_key.trim().is_empty() {
        return json!({"ok": false, "error": "api_key_missing"});
    }
    if base_url.trim().is_empty() {
        return json!({"ok": false, "error": "models_base_url_required"});
    }
    let Some(base) = safe_base_url(base_url) else {
        return json!({"ok": false, "error": "base_url_must_be_https"});
    };
    // 协议分叉（与 chat_once 一致）：Anthropic 端点列模型在 /v1/models 且用
    // x-api-key；OpenAI 兼容端点保持 {base}/models + bearer。
    // 前端另有快照兜底，但端点可用时不该用错协议去问。
    let protocol = protocol_for(&base);
    let base_no_v1 = base
        .trim_end_matches('/')
        .strip_suffix("/v1")
        .unwrap_or_else(|| base.trim_end_matches('/'));
    let url = match protocol {
        Protocol::OpenAi => format!("{}/models", base.trim_end_matches('/')),
        Protocol::Anthropic => format!("{base_no_v1}/v1/models"),
    };
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .redirect(reqwest::redirect::Policy::none()) // 同 chat client：不跟重定向
        .build();
    let Ok(client) = client else {
        return json!({"ok": false, "error": "client_build_failed"});
    };
    let request = match protocol {
        Protocol::OpenAi => client.get(&url).bearer_auth(api_key),
        Protocol::Anthropic => client
            .get(&url)
            .header("x-api-key", api_key)
            .header("anthropic-version", "2023-06-01"),
    };
    let resp = match request.send().await {
        Ok(r) => r,
        Err(e) => return json!({"ok": false, "error": format!("models_fetch_failed:{e}")}),
    };
    let status = resp.status();
    let body: Value = match resp.json().await {
        Ok(v) => v,
        Err(_) => return json!({"ok": false, "error": format!("models_http_{}", status.as_u16())}),
    };
    if !status.is_success() {
        return json!({"ok": false, "error": format!("models_http_{}", status.as_u16())});
    }
    let arr = body
        .get("data")
        .and_then(|v| v.as_array().cloned())
        .or_else(|| body.get("models").and_then(|v| v.as_array().cloned()))
        .unwrap_or_default();
    let models: Vec<Value> = arr
        .iter()
        .filter_map(|m| {
            let id = m.get("id").and_then(|v| v.as_str())?;
            // 能力字段按需透传（审查 D6）：OpenAI 风格 /models 通常只有 id，但部分
            // 端点（OpenRouter 类）带上下文长度/定价/参数支持——有就带回，没有不造；
            // 档位收紧的权威仍是 models.dev 快照（前端 fillModelHints）
            let mut o = serde_json::Map::new();
            o.insert("id".into(), json!(id));
            for k in ["name", "context_length", "pricing", "supported_parameters", "owned_by"] {
                if let Some(v) = m.get(k) {
                    o.insert(k.into(), v.clone());
                }
            }
            Some(Value::Object(o))
        })
        .collect();
    json!({"ok": true, "models": models})
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    /// wire 契约：类型层 tools 序列化必须保留 "type":"function" 判别字段
    /// （裸 ChatCompletionTool 不带 tag；SDK 升级若改变 wire 形状，此处必红）。
    #[test]
    fn tools_schema_wire_shape_anchor() {
        let arr = tools_schema().as_array().expect("tools 必须是数组").clone();
        assert_eq!(arr.len(), 3, "工具数量变了：{arr:?}");
        let names: Vec<&str> = arr
            .iter()
            .map(|t| t["function"]["name"].as_str().expect("name"))
            .collect();
        assert_eq!(names, vec!["moonviz_op", "read_mbt", "list_components"]);
        for t in &arr {
            assert_eq!(t["type"], "function", "wire 判别字段缺失：{t}");
            assert!(t["function"]["description"].is_string());
            assert!(t["function"]["parameters"].is_object());
        }
        assert_eq!(arr[0]["function"]["parameters"]["required"], json!(["op"]));
    }

    /// wire 契约：typed 骨架不得吞掉 messages 的非标字段——MiniMax 多轮要求
    /// assistant 消息（含 reasoning_content）逐字回传，typed 往返会静默丢字段。
    #[test]
    fn openai_request_body_preserves_raw_messages() {
        let messages = vec![
            json!({"role": "assistant", "content": "plan", "reasoning_content": "chain-of-thought",
                   "tool_calls": [{"id": "c1", "type": "function",
                                   "function": {"name": "moonviz_op", "arguments": "{\"op\":\"list\"}"}}]}),
            json!({"role": "tool", "tool_call_id": "c1", "content": "{\"ok\":true}"}),
        ];
        let body = openai_request_body("MiniMax-M2", "high", &messages);
        assert_eq!(body["model"], "MiniMax-M2");
        let msgs = body["messages"].as_array().expect("messages 数组").clone();
        assert_eq!(msgs.len(), 2);
        assert_eq!(msgs[0]["reasoning_content"], "chain-of-thought");
        assert_eq!(msgs[1]["tool_call_id"], "c1");
        assert_eq!(body["tools"].as_array().expect("tools").len(), 3);
        // 未设置的 optional 字段不得出现在 wire 上（SDK skip_serializing_if 契约）
        assert!(body.get("stream").is_none());
    }

    /// L2：逐模型上下文窗口（models.json limit.context）；未命中/空名回落保守默认，
    /// 带前缀形态（"provider/model"）取末段命中，16K 下限防上游脏数据。
    #[test]
    fn model_context_window_lookup_and_default() {
        assert_eq!(model_context_window("zz-definitely-unknown-9"), DEFAULT_CONTEXT_TOKENS);
        assert_eq!(model_context_window(""), DEFAULT_CONTEXT_TOKENS);
        assert_eq!(model_context_window("   "), DEFAULT_CONTEXT_TOKENS);
        let doc = crate::models::snapshot_document();
        let any = doc
            .get("providers")
            .and_then(|v| v.as_object())
            .and_then(|ps| ps.values().next())
            .and_then(|p| p.get("models"))
            .and_then(|m| m.as_object())
            .and_then(|ms| ms.keys().next().cloned())
            .expect("models.json 快照非空");
        assert!(
            model_context_window(&any) >= 16 * 1024,
            "快照内模型 {any} 应查到窗口（含下限保护）"
        );
        assert!(
            model_context_window(&format!("zz-prefix/{any}")) >= 16 * 1024,
            "带 provider 前缀的模型名应取末段命中"
        );
    }

    /// L0：剥 check 围栏块保 id（fixture 结构照真机 canonical：每画板一对
    /// ```mbt 视觉声明 + ```mbt check 逐字重复声明 + assert）。
    #[test]
    fn strip_mbt_check_blocks_preserves_ids() {
        let fixture = "---\nmoonviz:\n  format: visual-document\n  revision: 11\n---\n\n# doc\n\n\
<!-- moonviz:artboard login -->\n```mbt\nfn visual_login() -> @decl.Prototype {\n  \
let page = @decl.prototype(name=\"login\", width=390.0, height=844.0)\n  \
page.add(@decl.generic_node(id=\"welcome_title\",component=\"heading\"))\n  \
page.add(@decl.generic_node(id=\"email_input\",component=\"text_input\"))\n  page\n}\n```\n\n\
```mbt check\ntest \"login visual declaration\" {\n  \
let page = @decl.prototype(name=\"login\", width=390, height=844)\n  \
page.add(@decl.generic_node(id=\"welcome_title\",component=\"heading\"))\n  \
page.add(@decl.generic_node(id=\"email_input\",component=\"text_input\"))\n  \
assert_eq(page.check().length(), 0)\n}\n```\n";
        let stripped = strip_mbt_check_blocks(fixture);
        assert!(!stripped.contains("```mbt check"), "check 围栏必须全部剥除");
        assert!(stripped.contains("id=\"welcome_title\""), "节点 id 不得丢失");
        assert!(stripped.contains("id=\"email_input\""), "节点 id 不得丢失");
        assert!(stripped.contains("fn visual_login"), "视觉声明块必须保留");
        assert!(stripped.len() < fixture.len() * 3 / 4, "体积应显著缩小");
        // 畸形输入（无闭合 fence）：保守保留
        let malformed = "```mbt check\nnever closed";
        assert!(strip_mbt_check_blocks(malformed).contains("never closed"));
        // 不含 check 块的输入原样返回
        assert_eq!(strip_mbt_check_blocks("plain"), "plain");
    }

    /// L0：export-* 信封化 + 检视类超限截断；失败信封不截。
    #[test]
    fn shape_readonly_result_envelope_and_cap() {
        let env = shape_readonly_result(
            "export-svg wl",
            json!({"ok": true, "svg": "<svg>".repeat(5000)}),
        );
        assert_eq!(env["ok"], json!(true));
        assert!(env["bytes"].as_u64().unwrap() > 20_000);
        assert!(env["head"].as_str().unwrap().chars().count() <= 400);
        assert!(env.get("svg").is_none(), "渲染体不得整段入历史");
        let small = shape_readonly_result("lint wl", json!({"ok": true, "lint": ["x"]}));
        assert_eq!(small["result"]["lint"], json!(["x"]), "小结果原样放行");
        let big = shape_readonly_result(
            "critique wl",
            json!({"ok": true, "issues": "x".repeat(20_000)}),
        );
        assert_eq!(big["truncated"], json!(true));
        assert!(big["result"].as_str().unwrap().contains("[truncated"));
        let fail = shape_readonly_result("lint wl", json!({"ok": false, "error": "unknown_artboard:wl"}));
        assert_eq!(fail["error"], json!("unknown_artboard:wl"), "失败信封必须完整回传");
    }

    /// L1：同类工具只留最新，旧结果占位；消息数与 tool_call_id 配对不变。
    #[test]
    fn supersede_keeps_latest_and_pairing() {
        let tool_msg = |id: &str, content: Value| {
            json!({"role": "tool", "tool_call_id": id, "content": serde_json::to_string(&content).unwrap()})
        };
        let messages = vec![
            json!({"role": "system", "content": "sys"}),
            json!({"role": "user", "content": "go"}),
            json!({"role": "assistant", "content": null, "tool_calls": [
                {"id": "c1", "type": "function", "function": {"name": "read_mbt", "arguments": "{}"}},
                {"id": "c2", "type": "function", "function": {"name": "list_components", "arguments": "{}"}}]}),
            tool_msg("c1", json!({"ok": true, "mbt": "OLD"})),
            tool_msg("c2", json!({"ok": true, "components": [{"id": "badge"}]})),
            json!({"role": "assistant", "content": null, "tool_calls": [
                {"id": "c3", "type": "function", "function": {"name": "read_mbt", "arguments": "{}"}}]}),
            tool_msg("c3", json!({"ok": true, "mbt": "NEW"})),
        ];
        let shaped = supersede_stale_tool_results(&messages);
        assert_eq!(shaped.len(), messages.len(), "绝不删消息（tool_call_id 配对硬约束）");
        assert_eq!(shaped[5]["content"], messages[5]["content"], "最新 read_mbt 原样保留");
        let old = shaped[3]["content"].as_str().unwrap();
        assert!(old.contains("superseded") && old.contains("read_mbt"), "旧 read_mbt 应被占位：{old}");
        assert_eq!(shaped[4]["content"], messages[4]["content"], "唯一的 list_components 保留");
        assert_eq!(shaped[3]["tool_call_id"], json!("c1"), "tool_call_id 不变");
    }

    /// L2：预算超限的激进裁剪只动最近 N 条之外的 tool 内容。
    #[test]
    fn elide_keeps_recent_tool_contents() {
        let messages: Vec<Value> = (0..8)
            .map(|i| {
                json!({"role": "tool", "tool_call_id": format!("c{i}"),
                       "content": format!("{{\\\"payload\\\":\\\"{}\\\"}}", "x".repeat(100))})
            })
            .chain(std::iter::once(json!({"role": "assistant", "content": "done"})))
            .collect();
        let (shaped, elided) = elide_stale_tool_contents(&messages);
        assert_eq!(shaped.len(), messages.len());
        let one = messages[0]["content"].as_str().unwrap().len();
        assert_eq!(elided, 2 * one, "只有最早的 2 条被占位（keep={}）", RECENT_TOOL_KEEP);
        assert!(shaped[0]["content"].as_str().unwrap().contains("elided"));
        assert!(shaped[7]["content"].as_str().unwrap().contains("payload"), "最近结果保留");
        assert_eq!(shaped[8]["content"], json!("done"), "非 tool 消息不动");
    }

    #[test]
    fn thinking_family_table() {
        // auto：任何模型都不注入
        assert_eq!(thinking_extra_body("GLM-5.3", "auto", Protocol::OpenAi), None);
        // GLM-5.3 / 5.3-flash（bigmodel 与 z.ai 同构）：强制思考，off/low→low、medium/high→high、max→max
        assert_eq!(thinking_extra_body("glm-5.3", "off", Protocol::OpenAi), Some(json!({"reasoning_effort": "low"})));
        assert_eq!(thinking_extra_body("GLM-5.3-Flash", "low", Protocol::OpenAi), Some(json!({"reasoning_effort": "low"})));
        assert_eq!(thinking_extra_body("glm-5.3", "medium", Protocol::OpenAi), Some(json!({"reasoning_effort": "high"})));
        assert_eq!(thinking_extra_body("glm-5.3", "max", Protocol::OpenAi), Some(json!({"reasoning_effort": "max"})));
        // GLM-5.2：开关 + 全档
        assert_eq!(thinking_extra_body("glm-5.2", "off", Protocol::OpenAi), Some(json!({"thinking": {"type": "disabled"}})));
        assert_eq!(thinking_extra_body("glm-5.2", "max", Protocol::OpenAi), Some(json!({"reasoning_effort": "max"})));
        assert_eq!(thinking_extra_body("glm-5.2", "medium", Protocol::OpenAi), Some(json!({"reasoning_effort": "medium"})));
        // Kimi k3 / kimi-for-coding（订阅）：恒开，off→none，medium→high
        assert_eq!(thinking_extra_body("kimi-k3", "off", Protocol::OpenAi), Some(json!({"reasoning_effort": "none"})));
        assert_eq!(thinking_extra_body("kimi-k3", "medium", Protocol::OpenAi), Some(json!({"reasoning_effort": "high"})));
        assert_eq!(thinking_extra_body("kimi-k3", "max", Protocol::OpenAi), Some(json!({"reasoning_effort": "max"})));
        assert_eq!(thinking_extra_body("kimi-for-coding", "low", Protocol::OpenAi), Some(json!({"reasoning_effort": "low"})));
        assert_eq!(thinking_extra_body("k3-256k", "high", Protocol::OpenAi), Some(json!({"reasoning_effort": "high"})));
        // Kimi k2.x：仅开关，等级不传
        assert_eq!(thinking_extra_body("kimi-k2.6", "off", Protocol::OpenAi), Some(json!({"thinking": {"type": "disabled"}})));
        assert_eq!(thinking_extra_body("kimi-k2.6", "high", Protocol::OpenAi), None);
        assert_eq!(thinking_extra_body("kimi-k2.7-code", "off", Protocol::OpenAi), Some(json!({"thinking": {"type": "disabled"}})));
        // DeepSeek：开关 + effort（medium 服务端映射）
        assert_eq!(thinking_extra_body("deepseek-flash", "off", Protocol::OpenAi), Some(json!({"thinking": {"type": "disabled"}})));
        assert_eq!(thinking_extra_body("deepseek-flash", "medium", Protocol::OpenAi), Some(json!({"reasoning_effort": "medium"})));
        assert_eq!(thinking_extra_body("deepseek-v4-pro", "high", Protocol::OpenAi), Some(json!({"reasoning_effort": "high"})));
        // MiniMax：仅开关
        assert_eq!(thinking_extra_body("MiniMax-M3", "off", Protocol::OpenAi), Some(json!({"thinking": {"type": "disabled"}})));
        assert_eq!(thinking_extra_body("MiniMax-M3", "high", Protocol::OpenAi), None);
        assert_eq!(thinking_extra_body("MiniMax-M2.7", "max", Protocol::OpenAi), None);
        // StepFun（含 Step Plan）：三档 effort，off→low，max→high
        assert_eq!(thinking_extra_body("step-3.7-flash", "low", Protocol::OpenAi), Some(json!({"reasoning_effort": "low"})));
        assert_eq!(thinking_extra_body("step-3.7-flash", "off", Protocol::OpenAi), Some(json!({"reasoning_effort": "low"})));
        assert_eq!(thinking_extra_body("step-3.7-flash", "medium", Protocol::OpenAi), Some(json!({"reasoning_effort": "medium"})));
        assert_eq!(thinking_extra_body("step-3.5-flash", "max", Protocol::OpenAi), Some(json!({"reasoning_effort": "high"})));
        // Qwen：仅 vLLM 方言 off
        assert_eq!(thinking_extra_body("qwen3-max", "off", Protocol::OpenAi), Some(json!({"chat_template_kwargs": {"enable_thinking": false}})));
        assert_eq!(thinking_extra_body("qwen3-max", "high", Protocol::OpenAi), None);
        // 旧值 on → high
        assert_eq!(thinking_extra_body("deepseek-flash", "on", Protocol::OpenAi), Some(json!({"reasoning_effort": "high"})));
        assert_eq!(thinking_extra_body("MiniMax-M3", "on", Protocol::OpenAi), None); // 开关型家族 on→high 仍不传等级
        // GLM-5.2 low 档 + 未知模型 off(直传标准字段)——方言表覆盖差补锁
        assert_eq!(thinking_extra_body("glm-5.2", "low", Protocol::OpenAi), Some(json!({"reasoning_effort": "low"})));
        assert_eq!(thinking_extra_body("mystery-model", "off", Protocol::OpenAi), Some(json!({"thinking": {"type": "disabled"}})));
        // 未知模型：OpenAI 标准字段直传
        assert_eq!(thinking_extra_body("some-model", "high", Protocol::OpenAi), Some(json!({"reasoning_effort": "high"})));
    }

    /// list_models 也必须协议分叉：Anthropic 端点列模型在 /v1/models + x-api-key，
    /// OpenAI 端点保持 {base}/models + bearer（此前只分裂了 chat_once）。
    #[tokio::test]
    async fn list_models_uses_correct_protocol() {
        let (port, mock, bodies) = spawn_mock_llm(vec![
            json!({"data": [{"id": "MiniMax-M3"}, {"id": "MiniMax-M2.1"}]}),
        ])
        .await;
        // Anthropic 端点（快照记录值形态：尾部带 /v1）
        let out = list_models(&format!("http://127.0.0.1:{port}/anthropic/v1"), "sk-test").await;
        mock.abort();
        assert_eq!(out["ok"], json!(true), "{out}");
        let ids = out["models"]
            .as_array()
            .map(|a| a.iter().filter_map(|m| m.get("id").and_then(|v| v.as_str())).collect::<Vec<_>>())
            .unwrap_or_default();
        assert_eq!(ids, vec!["MiniMax-M3", "MiniMax-M2.1"]);
        let bs = bodies.lock().unwrap();
        assert!(
            bs[0].starts_with("GET /anthropic/v1/models "),
            "Anthropic 端点应请求 /anthropic/v1/models，实际：{}",
            bs[0].lines().next().unwrap_or("")
        );

        // OpenAI 端点回归：/models 路径不变
        let (port2, mock2, bodies2) = spawn_mock_llm(vec![
            json!({"data": [{"id": "deepseek-flash"}]}),
        ])
        .await;
        let out2 = list_models(&format!("http://127.0.0.1:{port2}/v1"), "sk-test").await;
        mock2.abort();
        assert_eq!(out2["ok"], json!(true), "{out2}");
        let bs2 = bodies2.lock().unwrap();
        assert!(
            bs2[0].starts_with("GET /v1/models "),
            "OpenAI 端点应请求 /v1/models，实际：{}",
            bs2[0].lines().next().unwrap_or("")
        );
    }

    #[test]
    fn protocol_detection() {
        assert_eq!(protocol_for("https://api.deepseek.com"), Protocol::OpenAi);
        assert_eq!(protocol_for("https://api.minimax.cn/v1"), Protocol::OpenAi);
        assert_eq!(protocol_for("https://open.bigmodel.cn/api/paas/v4"), Protocol::OpenAi);
        // MiniMax 官方推荐的 Anthropic 兼容端点（含路径段）
        assert_eq!(protocol_for("https://api.minimax.io/anthropic"), Protocol::Anthropic);
        assert_eq!(protocol_for("https://api.minimaxi.com/anthropic"), Protocol::Anthropic);
        // 官方 Anthropic
        assert_eq!(protocol_for("https://api.anthropic.com"), Protocol::Anthropic);
        // 大小写不敏感
        assert_eq!(protocol_for("https://api.minimax.io/ANTHROPIC"), Protocol::Anthropic);
        // 快照记录值形态（尾部带 /v1）也识别
        assert_eq!(protocol_for("https://api.minimax.io/anthropic/v1"), Protocol::Anthropic);
        // 负例：/anthropic 只在路径尾部才算——代理网关名不得误判
        assert_eq!(protocol_for("https://proxy.com/anthropic-proxy/v1"), Protocol::OpenAi);
        assert_eq!(protocol_for("https://gw.corp/api/anthropic-gateway/v1"), Protocol::OpenAi);
        // 负例：host 前缀伪装不得命中
        assert_eq!(protocol_for("https://anthropic.example.com/v1"), Protocol::OpenAi);
        assert_eq!(protocol_for("https://api.anthropic.com.evil.net/v1"), Protocol::OpenAi);
    }

    #[test]
    fn anthropic_thinking_dialect() {
        // MiniMax 家族在 anthropic 端点上：thinking{enabled,budget_tokens}
        assert_eq!(
            thinking_extra_body("MiniMax-M3", "high", Protocol::Anthropic),
            Some(json!({"thinking": {"type": "enabled", "budget_tokens": 16384}}))
        );
        assert_eq!(
            thinking_extra_body("MiniMax-M3", "low", Protocol::Anthropic),
            Some(json!({"thinking": {"type": "enabled", "budget_tokens": 2048}}))
        );
        assert_eq!(thinking_extra_body("MiniMax-M3", "max", Protocol::Anthropic),
            Some(json!({"thinking": {"type": "enabled", "budget_tokens": 32768}})));
        assert_eq!(
            thinking_extra_body("MiniMax-M3", "medium", Protocol::Anthropic),
            Some(json!({"thinking": {"type": "enabled", "budget_tokens": 8192}}))
        );
        // off/auto → 不注入（Anthropic 省略即关闭）
        assert_eq!(thinking_extra_body("MiniMax-M3", "off", Protocol::Anthropic), None);
        assert_eq!(thinking_extra_body("MiniMax-M3", "auto", Protocol::Anthropic), None);
        // 非 MiniMax 模型在 anthropic 上不注入（官方 Claude 无档位知识）
        assert_eq!(thinking_extra_body("claude-4", "high", Protocol::Anthropic), None);
        // OpenAI 协议行为不变（回归锁）
        assert_eq!(
            thinking_extra_body("MiniMax-M3", "off", Protocol::OpenAi),
            Some(json!({"thinking": {"type": "disabled"}}))
        );
    }

    #[test]
    fn anthropic_message_conversion() {
        let msgs = vec![
            json!({"role": "system", "content": "sys prompt"}),
            json!({"role": "user", "content": "hi"}),
            json!({"role": "assistant", "content": "let me", "tool_calls": [
                {"id": "c1", "type": "function", "function": {"name": "read_mbt", "arguments": "{}"}},
                {"id": "c2", "type": "function", "function": {"name": "moonviz_op", "arguments": "{\"op\": \"lint lg\"}"}}
            ]}),
            json!({"role": "tool", "tool_call_id": "c1", "content": "{\"ok\":true}"}),
            json!({"role": "tool", "tool_call_id": "c2", "content": "{\"ok\":true}"}),
        ];
        let (system, out) = to_anthropic_messages(&msgs);
        assert_eq!(system.as_deref(), Some("sys prompt"));
        // user + assistant + 1 条合并后的 tool_result user 消息 = 3 条
        assert_eq!(out.len(), 3, "连续 tool 消息必须合并为单条 user 消息");
        // assistant 消息：text 块 + 2 个 tool_use 块
        let a = &out[1];
        assert_eq!(a["role"], "assistant");
        let blocks = a["content"].as_array().unwrap();
        assert_eq!(blocks.len(), 3);
        assert_eq!(blocks[0]["type"], "text");
        assert_eq!(blocks[1]["type"], "tool_use");
        assert_eq!(blocks[1]["id"], "c1");
        assert_eq!(blocks[1]["name"], "read_mbt");
        assert_eq!(blocks[2]["input"]["op"], "lint lg");
        // tool 结果合并为单条 user 消息，含两个 tool_result 块
        let u = &out[2];
        assert_eq!(u["role"], "user");
        let trs = u["content"].as_array().unwrap();
        assert_eq!(trs.len(), 2);
        assert_eq!(trs[0]["type"], "tool_result");
        assert_eq!(trs[0]["tool_use_id"], "c1");
    }

    #[test]
    fn anthropic_response_normalization() {
        let anthropic = json!({
            "content": [
                {"type": "text", "text": "I will check"},
                {"type": "tool_use", "id": "tu1", "name": "moonviz_op", "input": {"op": "lint lg"}}
            ],
            "stop_reason": "tool_use"
        });
        let norm = normalize_anthropic_response(&anthropic);
        let msg = norm.pointer("/choices/0/message").unwrap();
        assert_eq!(msg["content"], "I will check");
        let tcs = msg["tool_calls"].as_array().unwrap();
        assert_eq!(tcs.len(), 1);
        assert_eq!(tcs[0]["id"], "tu1");
        assert_eq!(tcs[0]["function"]["name"], "moonviz_op");
        // arguments 必须是 JSON 字符串（OpenAI 形状，主循环按此解析）
        assert_eq!(tcs[0]["function"]["arguments"], "{\"op\":\"lint lg\"}");
    }

    #[test]
    fn readonly_routing() {
        // 无参清点类
        assert!(is_readonly_op("list"));
        assert!(is_readonly_op("flows"));
        assert!(is_readonly_op("list-components"));
        assert!(is_readonly_op("list-themes"));
        assert!(is_readonly_op("list-ops"));
        assert!(is_readonly_op("benchmark"));
        // 带画板参数的检视类（引擎 0.1.0 新增：spec/missing/doc-json/states/interactions/export-svg）
        assert!(is_readonly_op("spec login"));
        assert!(is_readonly_op("missing login"));
        assert!(is_readonly_op("doc-json login"));
        assert!(is_readonly_op("states login"));
        assert!(is_readonly_op("interactions login"));
        assert!(is_readonly_op("export-svg login"));
        assert!(is_readonly_op("export-html login"));
        // engine-v0.1.6：设计系统提取（颜色/尺寸 token 用量分析）
        assert!(is_readonly_op("extract-design-system login"));
        // 变更类绝不入表：入表会导致走 load 管道而静默丢弃变更
        assert!(!is_readonly_op("fix login"));
        // constrain 是变更 op（0.1.6-fix/#19 起走 session_constrain 特判路由）——
        // 误入表会被只读分支拦下、canonical 变更被静默丢弃
        assert!(!is_readonly_op("constrain cs 居中"));
        assert!(!is_readonly_op("update login btn fill=#fff"));
        assert!(!is_readonly_op("state login btn pressed fill=#000"));
        assert!(!is_readonly_op("interact login btn tap navigate_to:lg"));
        assert!(!is_readonly_op("group login g1 a b"));
        assert!(!is_readonly_op("responsive login"));
        assert!(!is_readonly_op("token primary #FF0000"));
        assert!(!is_readonly_op(""));
    }

    /// 共享宿主实例：wasmtime 进程内承载 classic wasm（与生产 agent 同路）。
    /// wasm 产物编译期嵌入（缺失=编译失败），调用失败即回归必红。
    const ENGINE: EngineHost = EngineHost;

    /// 引擎 wasm 面契约：经 wasmtime 宿主驱动**真产物**——种子文档可承载 op、
    /// AgentGate 拒绝越界提交、canonical mbt 回传、组件快照非空。
    #[tokio::test]
    async fn wasm_engine_surface_contract() {
        engine_ready().await;
        let _engine_gate = engine_test_gate();

        // 种子文档可承载变更 op（空文档会 mbt_no_visual_blocks——种子引导的前提）
        let r = ENGINE
            .call("apply_human_op", &seed_doc(SEED_BOARD, 390, 844), "template login wl 390 844")
            .await
            .unwrap();
        assert_eq!(r["ok"], json!(true), "种子文档上的 template op 失败：{r}");
        assert!(r["mbt"].as_str().is_some_and(|m| m.contains("wl")), "apply 结果应含 canonical mbt");

        // AgentGate：明显越界的放置必须整体拒绝（双门语义仍在 wasm 面生效；
        // 业务拒绝信封原样透传为 Ok，ok:false 由本测试断言）
        let r = ENGINE
            .call("apply_agent_op", &seed_doc("ov", 390, 844), "place ov button huge - 380 806")
            .await
            .unwrap();
        assert_eq!(r["ok"], json!(false), "AgentGate 应拒绝越界放置：{r}");

        // 组件快照（与前端画布同源）非空
        let comps = ENGINE.call("list_components", "", "").await.unwrap();
        assert!(
            comps["components"].as_array().is_some_and(|a| !a.is_empty()),
            "组件快照为空：{comps}"
        );
    }

    /// 引擎模板清单契约：提示词里的模板 id 集合必须与 wasm list_templates 完全一致。
    /// 提示词漏一个模板 → Agent 永远不会选它；多一个 → Agent 会猜不存在的 id。
    #[tokio::test]
    async fn template_ids_match_engine() {
        engine_ready().await;
        let out = ENGINE.call("list_templates", "", "").await.unwrap();
        let Some(arr) = out.as_array() else {
            panic!("list_templates 未返回数组（引擎契约回归）：{out}");
        };
        let _engine_gate = engine_test_gate();
        let mut engine_ids: Vec<String> = arr
            .iter()
            .filter_map(|t| t.get("id").and_then(|v| v.as_str()).map(String::from))
            .collect();
        engine_ids.sort();

        // 从提示词文本里抽出模板 id。ENGINE_TEMPLATES 的书写形式是 `id(中文名 尺寸)`，
        // 以空白/`|` 切词后每个词形如 `login(登录页)` 或 `web_landing(Web落地页`——
        // 取 `(` 之前的部分即为 id，不含 `(` 的词（尺寸、换行残片）自然被丢弃。
        // 不要改成按"首字母是否大写"过滤中文描述：那是靠大小写巧合成立的。
        let mut prompt_ids: Vec<String> = ENGINE_TEMPLATES
            .split(|c: char| c.is_whitespace() || c == '|')
            .filter_map(|tok| tok.split('(').next())
            .map(str::trim)
            .filter(|id| {
                !id.is_empty()
                    && id
                        .chars()
                        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
            })
            .map(String::from)
            .collect();
        prompt_ids.sort();
        prompt_ids.dedup();

        assert_eq!(
            prompt_ids, engine_ids,
            "提示词模板清单与引擎 wasm 不一致（差集：左=提示词，右=引擎）"
        );
    }

    /// 双门模板债登记（moonviz#14）：14 个内置模板在**人类门**必须全过（欢迎页与
    /// 种子引导的产品承诺）；AgentGate 债清单登记「模板内容自带、过不了代理门」的 id。
    /// **0.1.5-fix-2 已修复 #14（4 项债全清）**——清单保持为空作哨兵：上游若再引入
    /// 自带债的模板，此测试会红并指名该 id（同 models.rs KNOWN_DIVERGENCES 模式）。
    #[tokio::test]
    async fn templates_human_gate_all_pass_agent_gate_debt_registry() {
        engine_ready().await;
        let _engine_gate = engine_test_gate();
        let out = ENGINE.call("list_templates", "", "").await.unwrap();
        let arr = out.as_array().expect("list_templates 未返回数组");
        let ids: Vec<String> = arr
            .iter()
            .filter_map(|t| t.get("id").and_then(|v| v.as_str()).map(String::from))
            .collect();
        assert!(!ids.is_empty());
        const AGENT_GATE_DEBT: [&str; 0] = [];
        for id in &ids {
            let seed = seed_doc(SEED_BOARD, 24, 24);
            let human = ENGINE
                .call("apply_human_op", &seed, &format!("template {id} __t"))
                .await
                .unwrap();
            assert_eq!(
                human.get("ok"),
                Some(&json!(true)),
                "模板 {id} 人类门被拒——欢迎页/种子引导的产品承诺被破坏：{human}"
            );
            let agent = ENGINE
                .call("apply_agent_op", &seed, &format!("template {id} __t"))
                .await
                .unwrap();
            let agent_ok = agent.get("ok") == Some(&json!(true));
            let in_debt = AGENT_GATE_DEBT.contains(&id.as_str());
            assert_eq!(
                agent_ok, !in_debt,
                "模板 {id} 的 AgentGate 行为与债登记清单不符（agent_ok={agent_ok}）——\
                 若上游已修（agent_ok=true 的债模板），清空 AGENT_GATE_DEBT 并把种子引导换回 apply_agent_op；\
                 若是新模板自带债（agent_ok=false 且不在清单），把它的 id 加进 AGENT_GATE_DEBT"
            );
        }
    }

    /// 提示词不得再教 Agent 使用引擎 apply 路径会拒绝的 op。
    #[test]
    fn prompt_avoids_apply_rejected_ops() {
        // 独立 name op 仅存在于 CLI 直连面，apply 路径返回 mbt_operation_unsupported，
        // 提示词必须点名其替代用法；constrain 自 0.1.6-fix/#19 起经 session 路由
        // **可达**，提示词必须作为变更 op 教（含意图词表锚点——漏一个模型就永远不用）。
        assert!(
            INSTRUCTIONS.contains("mbt_operation_unsupported"),
            "提示词必须告知 Agent 存在被引擎拒绝的 op"
        );
        assert!(
            INSTRUCTIONS.contains("update ... name=<id>"),
            "提示词必须点名 name op 的替代用法"
        );
        for token in ["constrain", "居中", "网格", "等间距", "LAYOUT INTENT ONLY"] {
            assert!(INSTRUCTIONS.contains(token), "提示词必须教 constrain 意图词表：{token}");
        }
        // 新语法必须在场
        for token in ["group", "align", "restyle", "interact", "state", "missing", "spec", "token", "export-html"] {
            assert!(INSTRUCTIONS.contains(token), "提示词缺少引擎能力：{token}");
        }
    }

    #[test]
    fn base_url_policy() {
        assert!(safe_base_url("https://api.deepseek.com").is_some());
        assert!(safe_base_url("").is_some());
        assert!(safe_base_url("http://localhost:11434/v1").is_some());
        assert!(safe_base_url("http://192.168.1.5:8000").is_some());
        assert!(safe_base_url("http://evil.example.com").is_none());
        // IP 精确段判定：私有段放行、公网 172.2/172.255 拒绝、DNS 前缀伪装拒绝
        assert!(safe_base_url("http://172.20.1.5:8000").is_some());
        assert!(safe_base_url("http://172.16.0.1").is_some());
        assert!(safe_base_url("http://172.31.255.255").is_some());
        assert!(safe_base_url("http://172.2.3.4").is_none());
        assert!(safe_base_url("http://172.255.0.1").is_none());
        assert!(safe_base_url("http://10.evil.com").is_none());
        assert!(safe_base_url("http://192.168.evil.com").is_none());
        assert!(safe_base_url("http://[::1]:11434").is_some());
        assert!(safe_base_url("ftp://x").is_none());
    }

    /// 引擎门测试串行化：wasmtime 宿主是**进程级常驻单例**，session 缓存计数
    /// （hits/misses）与 session_count_probe 的绝对值断言要求各测试从已知状态
    /// 开始（hard_reset 后串行执行）。锁只包引擎门测试体，非引擎测试
    /// （方言表/协议/模型快照等纯单测）不受影响、照常并行。
    pub(crate) static ENGINE_TEST_GATE: std::sync::Mutex<()> = std::sync::Mutex::new(());
    pub(crate) fn engine_test_gate() -> std::sync::MutexGuard<'static, ()> {
        ENGINE_TEST_GATE.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// 引擎（wasmtime 宿主 × 编译期嵌入的真 wasm 产物）可用性门。
    /// **失败即 panic，无跳过路径**——产物随二进制嵌入不存在"缺失"，
    /// 宿主/编解码损坏是回归不是环境缺失，静默跳过会把真回归伪装成绿灯
    /// （变异实验实证过这一掩蔽路径）。
    async fn engine_ready() {
        match ENGINE.call("version_info", "", "").await {
            Ok(v) if v.get("ok") == Some(&json!(true)) => {}
            bad => panic!("wasm 引擎不可用（嵌入产物损坏或宿主编解码回归，这是回归不是环境缺失）：{bad:?}"),
        }
    }

    /// 端到端 back 任务测试：mock OpenAI 端点（脚本化两轮 tool_calls）× 真实 wasm 引擎。
    /// 覆盖：空项目种子引导 → apply-op → 终态总结 → canonical mbt 契约。
    #[tokio::test]
    async fn agent_loop_with_mock_llm_and_real_engine() {
        engine_ready().await;
        let _engine_gate = engine_test_gate();
        // mock /chat/completions：第 1 轮返回 bootstrap 工具调用，第 2 轮返回总结
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let mock = tokio::spawn(async move {
            use tokio::io::AsyncReadExt;
            for _ in 0..2 {
            let (mut sock, _) = listener.accept().await.unwrap();
            // 读完整 HTTP 请求（header + body）
            let mut raw = Vec::new();
            let mut chunk = [0u8; 16384];
            loop {
                let n = sock.read(&mut chunk).await.unwrap();
                if n == 0 { break; }
                raw.extend_from_slice(&chunk[..n]);
                let s = String::from_utf8_lossy(&raw).into_owned();
                if let Some(pos) = s.find("\r\n\r\n") {
                    let body_start = pos + 4;
                    if let Some(len) = s
                        .lines()
                        .find_map(|l| l.to_ascii_lowercase().strip_prefix("content-length:").map(|v| v.trim().to_string()))
                        .and_then(|v| v.parse::<usize>().ok())
                    {
                        if raw.len() >= body_start + len { break; }
                    }
                }
            }
            let req = String::from_utf8_lossy(&raw).into_owned();
            assert!(req.contains("/chat/completions"), "请求路径错误");
            assert!(req.contains("\"tools\""), "请求缺少工具定义");
            let first_round = !req.contains("\"role\":\"tool\"");
            let body = if first_round {
                serde_json::json!({
                    "choices": [{"message": {"role": "assistant", "content": null, "tool_calls": [
                        {"id": "call_1", "type": "function", "function": {"name": "moonviz_op",
                         "arguments": "{\"op\": \"template login lg\"}"}}
                    ]}}]
                })
            } else {
                serde_json::json!({
                    "choices": [{"message": {"role": "assistant", "content": "已创建登录页 lg（390×844）。"}}]
                })
            };
            let body = serde_json::to_string(&body).unwrap();
            let resp = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            );
            use tokio::io::AsyncWriteExt;
            sock.write_all(resp.as_bytes()).await.unwrap();
            }
        });

        let out = run(
            &ENGINE,
            "建一个登录页",
            None,
            "sk-test",
            "mock-model",
            &format!("http://127.0.0.1:{port}"),
            "auto" ,
            None,
        )
        .await;
        mock.await.unwrap();

        assert_eq!(out["ok"], json!(true), "agent 应成功: {out}");
        assert_eq!(out["stopReason"], json!("done"));
        assert_eq!(out["ops"], json!(["template login lg"]));
        assert_eq!(out["text"], json!("已创建登录页 lg（390×844）。"));
        let mbt = b64_decode(out["mbt_b64"].as_str().unwrap()).unwrap();
        assert!(mbt.contains("lg"), "canonical mbt 应含画板 lg");
        assert!(out["render"]["artboards"].is_array(), "render 应含 artboards");
    }

    /// 可复用 mock LLM：按顺序回放脚本化响应体，读完整请求后返回。
    /// mock OpenAI/Anthropic 端点：按 rounds 依次返回预设响应体，
    /// 同时把每轮收到的**请求行 + 请求体**捕获进 bodies（测试可断言 URL 路径与线上形态）。
    async fn spawn_mock_llm(
        rounds: Vec<Value>,
    ) -> (
        u16,
        tokio::task::JoinHandle<()>,
        std::sync::Arc<std::sync::Mutex<Vec<String>>>,
    ) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let bodies = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let bodies_w = bodies.clone();
        let handle = tokio::spawn(async move {
            use tokio::io::{AsyncReadExt, AsyncWriteExt};
            for body in rounds {
                let Ok((mut sock, _)) = listener.accept().await else { break };
                let mut raw = Vec::new();
                let mut chunk = [0u8; 16384];
                loop {
                    match sock.read(&mut chunk).await {
                        Ok(0) | Err(_) => break,
                        Ok(n) => {
                            raw.extend_from_slice(&chunk[..n]);
                            let s = String::from_utf8_lossy(&raw).into_owned();
                            if let Some(pos) = s.find("\r\n\r\n") {
                                let body_start = pos + 4;
                                match s
                                    .lines()
                                    .find_map(|l| l.to_ascii_lowercase().strip_prefix("content-length:").map(|v| v.trim().to_string()))
                                    .and_then(|v| v.parse::<usize>().ok())
                                {
                                    // 有 body：等收齐（POST）
                                    Some(len) => { if raw.len() >= body_start + len { break; } }
                                    // 无 body（GET，如 list_models）：header 读完即响应
                                    None => break,
                                }
                            }
                        }
                    }
                }
                // 捕获请求行 + 请求体（路径与线上形态断言都需要）
                let s = String::from_utf8_lossy(&raw).into_owned();
                let req_line = s.lines().next().unwrap_or("").to_string();
                if let Some(pos) = s.find("\r\n\r\n") {
                    bodies_w
                        .lock()
                        .unwrap()
                        .push(format!("{req_line}\n{}", &s[pos + 4..]));
                }
                let body_str = serde_json::to_string(&body).unwrap();
                let resp = format!(
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    body_str.len(),
                    body_str
                );
                let _ = sock.write_all(resp.as_bytes()).await;
            }
        });
        (port, handle, bodies)
    }

    /// Anthropic 协议端到端（多轮 + 线上形态断言）：mock 返回 Messages 形态的
    /// tool_use 块，base_url 带 /anthropic 触发协议探测。除跑通全链路外，
    /// 断言**发出去的请求**：URL 路径（无双 /v1）、budget<max_tokens、
    /// system 提取、连续 tool 消息批处理为单条 user 消息、tool_call id 往返。
    #[tokio::test]
    async fn agent_loop_anthropic_protocol_with_mock_llm_and_real_engine() {
        engine_ready().await;
        let _engine_gate = engine_test_gate();
        // 第一轮：同消息两个 tool_use（触发两 tool 结果的批处理路径）
        // 第二轮：单个 tool_use；第三轮：文本总结
        let (port, mock, bodies) = spawn_mock_llm(vec![
            serde_json::json!({
                "content": [
                    {"type": "tool_use", "id": "tu1", "name": "moonviz_op",
                     "input": {"op": "template login rt"}},
                    {"type": "tool_use", "id": "tu2", "name": "moonviz_op",
                     "input": {"op": "theme dark"}}
                ],
                "stop_reason": "tool_use"
            }),
            serde_json::json!({
                "content": [
                    {"type": "tool_use", "id": "tu3", "name": "read_mbt", "input": {}}
                ],
                "stop_reason": "tool_use"
            }),
            serde_json::json!({
                "content": [{"type": "text", "text": "已建好登录页 rt。"}],
                "stop_reason": "end_turn"
            }),
        ])
        .await;
        let out = run(
            &ENGINE,
            "建一个登录页并切换主题",
            None,
            "sk-test",
            "MiniMax-M3",
            &format!("http://127.0.0.1:{port}/anthropic/v1"),
            "high",
            None,
        )
        .await;
        mock.abort();

        // ---- 结果契约 ----
        assert_eq!(out["ok"], json!(true), "{out}");
        assert_eq!(
            out["ops"],
            json!(["template login rt", "theme dark"]),
            "两个 tool_use 应都被归一化并执行"
        );
        assert_eq!(out["stopReason"], json!("done"));
        assert_eq!(out["text"], json!("已建好登录页 rt。"));
        let mbt = b64_decode(out["mbt_b64"].as_str().unwrap()).unwrap();
        assert!(mbt.contains("rt"), "canonical mbt 应含画板 rt");

        // ---- 线上形态断言（mock 捕获的真实请求）----
        let bs = bodies.lock().unwrap();
        assert_eq!(bs.len(), 3, "应发生 3 轮请求，实际 {}", bs.len());

        // 1) URL：POST /anthropic/v1/messages——恰好一个 /v1（双 /v1 拼装回归锁）
        assert!(
            bs[0].starts_with("POST /anthropic/v1/messages "),
            "Anthropic 请求路径错误：{}",
            bs[0].lines().next().unwrap_or("")
        );

        let b1: Value = serde_json::from_str(bs[0].lines().nth(1).unwrap_or("{}")).unwrap();
        // 2) system 提取为顶层字段，messages 内无 system 角色
        assert!(b1.get("system").and_then(|v| v.as_str()).is_some(), "system 应在顶层");
        let msgs = b1["messages"].as_array().unwrap();
        assert!(
            !msgs.iter().any(|m| m.get("role").and_then(|r| r.as_str()) == Some("system")),
            "messages 内不应有 system 角色"
        );
        // 3) thinking.budget_tokens < max_tokens（Anthropic 硬约束）+ high 档预算值
        let budget = b1["thinking"]["budget_tokens"].as_u64().expect("thinking.budget_tokens");
        let max_tokens = b1["max_tokens"].as_u64().expect("max_tokens");
        assert_eq!(budget, 16384, "high 档应为 16384");
        assert!(budget < max_tokens, "budget {budget} 必须小于 max_tokens {max_tokens}");

        // 4) 第二轮请求：两个 tool 结果必须批处理进**单条** user 消息，id 原样往返
        let b2: Value = serde_json::from_str(bs[1].lines().nth(1).unwrap_or("{}")).unwrap();
        let msgs2 = b2["messages"].as_array().unwrap();
        let tool_user_msgs: Vec<&Value> = msgs2
            .iter()
            .filter(|m| {
                m.get("role").and_then(|r| r.as_str()) == Some("user")
                    && m.get("content")
                        .and_then(|c| c.as_array())
                        .is_some_and(|a| a.iter().any(|blk| blk.get("type").and_then(|t| t.as_str()) == Some("tool_result")))
            })
            .collect();
        assert_eq!(tool_user_msgs.len(), 1, "连续 tool 消息必须批处理为单条 user 消息");
        let blocks = tool_user_msgs[0]["content"].as_array().unwrap();
        let ids: Vec<&str> = blocks
            .iter()
            .filter_map(|blk| blk.get("tool_use_id").and_then(|v| v.as_str()))
            .collect();
        assert_eq!(ids, vec!["tu1", "tu2"], "tool_call id 必须原样往返");
        // assistant 消息里应有两个 tool_use 块（归一化→转换的往返锁）
        let asst = msgs2
            .iter()
            .find(|m| m.get("role").and_then(|r| r.as_str()) == Some("assistant"))
            .expect("应有 assistant 消息");
        let tu: Vec<&str> = asst["content"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|blk| blk.get("type").and_then(|t| t.as_str()) == Some("tool_use"))
            .filter_map(|blk| blk.get("id").and_then(|v| v.as_str()))
            .collect();
        assert_eq!(tu, vec!["tu1", "tu2"], "assistant 消息应含两个 tool_use 块");
    }

    /// 只读 op 端到端：Agent 调用 `lint wl` → moonviz_op 路由到 session API →
    /// 结果含检视输出（不再是 wasm_engine_readonly_unavailable 硬拦）。
    /// 断言第二轮请求的消息历史里带着 lint 的 tool 结果（session 面真被打通）。
    #[tokio::test]
    async fn agent_loop_readonly_op_via_session_api() {
        engine_ready().await;
        let _engine_gate = engine_test_gate();
        let (port, mock, bodies) = spawn_mock_llm(vec![
            // 第一轮：bootstrap 建板 + 一个只读 lint（同一消息两个 tool_use）
            serde_json::json!({
                "choices": [{"message": {"role": "assistant", "content": null, "tool_calls": [
                    {"id": "c1", "type": "function", "function": {"name": "moonviz_op",
                     "arguments": "{\"op\": \"template login wl\"}"}},
                    {"id": "c2", "type": "function", "function": {"name": "moonviz_op",
                     "arguments": "{\"op\": \"lint wl\"}"}}
                ]}}]
            }),
            // 第二轮：文本总结
            serde_json::json!({
                "choices": [{"message": {"role": "assistant", "content": "已建板并完成 lint。"}}]
            }),
        ])
        .await;
        let out = run(
            &ENGINE,
            "建登录页并 lint",
            None,
            "sk-test",
            "mock-model",
            &format!("http://127.0.0.1:{port}"),
            "auto",
            None,
        )
        .await;
        mock.abort();
        assert_eq!(out["ok"], json!(true), "{out}");
        assert_eq!(
            out["ops"],
            json!(["template login wl", "lint wl"]),
            "只读 op 应被记录并执行"
        );
        assert_eq!(out["stopReason"], json!("done"));
        // 第二轮请求的历史里必须带着 lint 的 tool 结果（session 面真被打通：
        // 若是硬拦，tool 结果会是 wasm_engine_readonly_unavailable 错误）
        let bs = bodies.lock().unwrap();
        assert!(bs.len() >= 2, "应有 2 轮请求");
        let second = &bs[1];
        // tool 结果在请求体里是转义 JSON 字符串（\"op\":\"lint wl\"），
        // 搜明文 "lint wl" 即可（转义不影响子串匹配）
        assert!(
            second.contains("lint wl"),
            "第二轮请求未含 lint 的 tool 结果：{}",
            &second[..second.len().min(400)]
        );
        assert!(
            !second.contains("unavailable"),
            "只读 op 仍被拦为不可用（session 路由未生效）：{}",
            &second[..second.len().min(400)]
        );
    }

    /// engine-v0.1.6 / 上游 #18：place 支持 [w] [h] 位置参数且门在**最终 bbox** 评估——
    /// 「默认尺寸撞兄弟 + 马上 update 修正」的中间态拒绝形态（真实 run 111 次拒绝的
    /// 根因）整类消除。锚定：默认尺寸相交被拒、带最终尺寸一次过门。
    #[tokio::test]
    async fn place_final_size_gate_evaluates_final_bbox() {
        engine_ready().await;
        let _engine_gate = engine_test_gate();
        let base = seed_doc("ps", 390, 844);
        let r1 = ENGINE.call("apply_agent_op", &base, "place ps button b1 - 150 20").await.unwrap();
        assert_eq!(r1.get("ok"), Some(&json!(true)), "首个 place 应通过：{r1}");
        let doc1 = r1.get("mbt").and_then(|v| v.as_str()).expect("canonical 回传");
        // 同位置默认尺寸（rect 默认 200×100）与 b1 相交 → AgentGate 拒绝（中间态拒绝语义不变）
        let r2 = ENGINE.call("apply_agent_op", doc1, "place ps rect bg2 - 120 50").await.unwrap();
        assert!(
            r2.get("ok") == Some(&json!(false))
                && r2.get("error").map(|e| e.to_string().contains("mbt_gate_block")).unwrap_or(false),
            "默认尺寸相交必须仍被拒（门语义不变）：{r2}"
        );
        // 带最终尺寸 [w] [h] → 一步过门（不再需要 reject+update 两次往返）
        let r3 = ENGINE.call("apply_agent_op", doc1, "place ps rect bg2 - 120 80 150 30").await.unwrap();
        assert_eq!(r3.get("ok"), Some(&json!(true)), "最终尺寸应一次过门：{r3}");
        let doc3 = r3.get("mbt").and_then(|v| v.as_str()).expect("canonical 回传");
        // 几何精确落盘：bg2 的 w/h 是 fixed(150)/fixed(30) 而非组件默认
        assert!(doc3.contains("id=\"bg2\""), "节点落盘");
        let bg2_line = doc3.lines().find(|l| l.contains("id=\"bg2\"")).expect("bg2 声明行");
        assert!(bg2_line.contains("width=@decl.fixed(150)") && bg2_line.contains("height=@decl.fixed(30)"),
            "最终尺寸必须精确落盘：{bg2_line}");
    }

    /// engine-v0.1.6：extract-design-system 经 agent 只读路由（session API）可达——
    /// 结果含 token 用量分析（summary/color_tokens），第二轮请求历史里可验证。
    #[tokio::test]
    async fn extract_design_system_via_session_route() {
        engine_ready().await;
        let _engine_gate = engine_test_gate();
        let (port, mock, bodies) = spawn_mock_llm(vec![
            serde_json::json!({
                "choices": [{"message": {"role": "assistant", "content": null, "tool_calls": [
                    {"id": "c1", "type": "function", "function": {"name": "moonviz_op",
                     "arguments": "{\"op\": \"template login ds\"}"}},
                    {"id": "c2", "type": "function", "function": {"name": "moonviz_op",
                     "arguments": "{\"op\": \"extract-design-system ds\"}"}}
                ]}}]
            }),
            serde_json::json!({
                "choices": [{"message": {"role": "assistant", "content": "已提取设计系统。"}}]
            }),
        ])
        .await;
        let out = run(
            &ENGINE,
            "建登录页并提取设计系统",
            None,
            "sk-test",
            "mock-model",
            &format!("http://127.0.0.1:{port}"),
            "auto",
            None,
        )
        .await;
        mock.abort();
        assert_eq!(out["ok"], json!(true), "{out}");
        assert_eq!(
            out["ops"],
            json!(["template login ds", "extract-design-system ds"]),
            "只读新 op 应被记录并执行"
        );
        let bs = bodies.lock().unwrap();
        assert!(bs.len() >= 2, "应有 2 轮请求");
        let second = &bs[1];
        assert!(
            second.contains("color_tokens") && second.contains("total_colors"),
            "第二轮请求应含 extract-design-system 的 token 用量分析结果"
        );
    }

    /// 0.1.6-fix/#19：constrain 经 session 路由可达，成功信封带 canonical；
    /// 键前移实证（constrain 后同 canonical 的变更 op 必须命中暖会话，而非弃缓存
    /// 重开）；cannot_parse 错误信封自带意图词表（#17 错误即文档）原样透传。
    #[tokio::test]
    async fn constrain_session_route_and_key_advance() {
        engine_ready().await;
        let _engine_gate = engine_test_gate();
        let d0 = ENGINE
            .call("apply_agent_op", &seed_doc("cs", 390, 844), "template login cs")
            .await
            .unwrap();
        let doc0 = d0.get("mbt").and_then(|v| v.as_str()).expect("canonical 回传");
        let r = ENGINE.call("session_constrain", doc0, "cs 居中").await.unwrap();
        assert_eq!(r.get("ok"), Some(&json!(true)), "{r}");
        let doc1 = r
            .get("mbt")
            .and_then(|v| v.as_str())
            .expect("0.1.6-fix/#19：constrain 成功信封必须带 canonical（键前移原料）");
        let stats0 = ENGINE.call("session_cache_stats", "", "").await.unwrap();
        let upd = ENGINE
            .call("session_apply_agent", doc1, "update cs welcome_title text=\"AfterConstrain\"")
            .await
            .unwrap();
        assert_eq!(upd.get("ok"), Some(&json!(true)), "{upd}");
        let stats1 = ENGINE.call("session_cache_stats", "", "").await.unwrap();
        assert!(
            stats1.get("hits").and_then(|v| v.as_u64()).unwrap_or(0)
                > stats0.get("hits").and_then(|v| v.as_u64()).unwrap_or(0),
            "constrain 后同 canonical 的变更 op 应命中暖会话（若仍弃缓存则此断言红）：{stats0} → {stats1}"
        );
        let bad = ENGINE.call("session_constrain", doc1, "cs 乱写的意图").await.unwrap();
        let err = bad.get("error").and_then(|v| v.as_str()).unwrap_or("");
        assert!(
            bad.get("ok") == Some(&json!(false)) && err.contains("cannot_parse") && err.contains("居中"),
            "cannot_parse 错误必须带意图词表：{bad}"
        );
    }

    /// 终态 rebase（docs/agent-rebase.md 方案 C）：人类编辑推进文档后，run 的变更
    /// op 流重放到最新 canonical——保住人类编辑；无冲突 op 应用；与新布局冲突的 op
    /// 被门拒跳过并保留错误原文；只读 op 过滤不进重放流。
    #[tokio::test]
    async fn rebase_ops_replays_onto_latest_and_skips_conflicts() {
        engine_ready().await;
        let _engine_gate = engine_test_gate();
        let d0 = ENGINE
            .call("apply_agent_op", &seed_doc("rb", 390, 844), "template login rb")
            .await
            .unwrap();
        let doc0 = d0.get("mbt").and_then(|v| v.as_str()).expect("canonical 回传");
        // 「人类」在 run 期间推进了文档：把 welcome_title 挪到画布下方空白区
        // （run 终态不知道这件事；坐标避开 logo/email_input 等既有节点）
        let dh = ENGINE
            .call("apply_agent_op", doc0, "move rb welcome_title 20 700")
            .await
            .unwrap();
        let latest = dh.get("mbt").and_then(|v| v.as_str()).expect("canonical 回传");
        let ops = vec![
            "update rb welcome_title text=\"Rebased\"".to_string(),
            // 干净落点（welcome_title 已被人类挪到 y700-736，其余节点 ≤y660）
            "place rb rect rb_extra - 20 760 150 30".to_string(),
            // 与 email_input 部分相交 → no_sibling_overlap 拒绝 → 跳过。
            // 注意：**完全同框**会触发全包含豁免反而过门（#15 语义），样本必须取部分相交
            "place rb rect ov - 30 350 342 52".to_string(),
            "lint rb".to_string(),
        ];
        let out = rebase_ops(&ENGINE, latest, &ops).await;
        assert_eq!(out["ok"], json!(true), "{out}");
        let applied = out["applied"].as_array().expect("applied 数组");
        let skipped = out["skipped"].as_array().expect("skipped 数组");
        assert_eq!(applied.len(), 2, "文本更新与无冲突放置应重放：{out}");
        assert_eq!(skipped.len(), 1, "重叠放置应被门拒跳过：{out}");
        assert!(
            skipped[0]["error"].as_str().unwrap_or("").contains("mbt_gate_block"),
            "skipped 必须保留引擎错误原文：{out}"
        );
        assert!(
            !out.to_string().contains("\"lint rb\""),
            "只读 op 不得进重放流（applied/skipped 均不应出现）：{out}"
        );
        let rebased = b64_decode(out["mbt_b64"].as_str().expect("mbt_b64")).unwrap();
        assert!(rebased.contains("text=\"Rebased\""), "agent 变更应落盘");
        assert!(rebased.contains("id=\"rb_extra\""), "无冲突放置应落盘");
        // 人类编辑保留：welcome_title 的 x=20（move 的结果，未被整体回灌冲掉）
        let title = rebased
            .lines()
            .find(|l| l.contains("id=\"welcome_title\""))
            .expect("welcome_title 在场");
        assert!(title.contains("x=20"), "人类 move 编辑必须保留：{title}");
    }

    /// L0 上下文整形端到端（真机引擎）：模板建板 + read_mbt 后，第二轮请求的
    /// 历史里必须含节点 id（id 可见性）且不含 check 围栏（~40-50% 冗余被剥）。
    #[tokio::test]
    async fn agent_loop_read_mbt_shaping_keeps_ids() {
        engine_ready().await;
        let _engine_gate = engine_test_gate();
        let (port, mock, bodies) = spawn_mock_llm(vec![
            serde_json::json!({
                "choices": [{"message": {"role": "assistant", "content": null, "tool_calls": [
                    {"id": "c1", "type": "function", "function": {"name": "moonviz_op",
                     "arguments": "{\"op\": \"template login cs\"}"}},
                    {"id": "c2", "type": "function", "function": {"name": "read_mbt",
                     "arguments": "{}"}}
                ]}}]
            }),
            serde_json::json!({
                "choices": [{"message": {"role": "assistant", "content": "已读取文档。"}}]
            }),
        ])
        .await;
        let out = run(
            &ENGINE,
            "建登录页并读取文档",
            None,
            "sk-test",
            "mock-model",
            &format!("http://127.0.0.1:{port}"),
            "auto",
            None,
        )
        .await;
        mock.abort();
        assert_eq!(out["ok"], json!(true), "{out}");
        let bs = bodies.lock().unwrap();
        assert!(bs.len() >= 2, "应有 2 轮请求");
        let second = &bs[1];
        assert!(
            second.contains("welcome_title"),
            "整形后的 read_mbt 结果必须保留节点 id（id 可见性是裁剪的硬边界）"
        );
        assert!(
            !second.contains("```mbt check"),
            "check 围栏块（节点声明的逐字重复）必须被剥除（note 文案里的 'mbt check' 字样不算围栏）"
        );
    }

    /// session 面宿主契约：经 ENGINE 宿主（node 驱动真 wasm）走完整 session
    /// 生命周期——open → lint/flows/list_artboards → close 全部可用。
    /// 这是只读路由的宿主层证据（agent.rs 路由 + 宿主包装 + wasm 导出三层）。
    #[tokio::test]
    async fn session_api_host_contract() {
        engine_ready().await;
        let _engine_gate = engine_test_gate();
        let seed = seed_doc("sd", 390, 844);
        // engine-v0.1.1-session 起只读 session 导出统一 {ok,data} 信封（上游 #4C）
        let lint = ENGINE.call("session_lint", &seed, "sd").await.unwrap();
        assert_eq!(lint["ok"], json!(true), "session_lint 应返回信封：{lint}");
        assert!(lint["data"].is_array(), "session_lint 的 data 应为违规数组：{lint}");
        let flows = ENGINE.call("session_flows", &seed, "").await.unwrap();
        assert_eq!(flows["ok"], json!(true), "session_flows 应返回信封：{flows}");
        assert!(flows["data"].is_array(), "session_flows 的 data 应为数组：{flows}");
        let arts = ENGINE.call("session_list_artboards", &seed, "").await.unwrap();
        let arr = arts["data"].as_array().expect("session_list_artboards 的 data 应为数组");
        assert!(arr.iter().any(|a| a.get("id").and_then(|v| v.as_str()) == Some("sd")));
        let bench = ENGINE.call("session_benchmark", &seed, "").await.unwrap();
        assert!(!bench["data"]["avg_score"].is_null(), "session_benchmark 应返回评分对象：{bench}");
        // 直调检视导出
        let tokens = ENGINE.call("list_tokens", "", "").await.unwrap();
        assert!(tokens.get("colors").is_some(), "list_tokens 应返回颜色分组：{tokens}");
        let themes = ENGINE.call("list_themes", "", "").await.unwrap();
        assert!(themes.as_array().is_some_and(|a| a.len() >= 5), "list_themes 应返回 6 主题");
    }

    /// 中途 LLM 失败（第二轮连接被拒）：已提交工作必须保留。
    #[tokio::test]
    async fn mid_run_llm_failure_preserves_committed_work() {
        engine_ready().await;
        let _engine_gate = engine_test_gate();
        // mock 只服务第一轮（bootstrap tool_call），之后 listener 关闭 → 第二轮连接被拒
        let (port, mock, _bodies) = spawn_mock_llm(vec![serde_json::json!({
            "choices": [{"message": {"role": "assistant", "content": null, "tool_calls": [
                {"id": "c1", "type": "function", "function": {"name": "moonviz_op",
                 "arguments": "{\"op\": \"template login lg\"}"}}
            ]}}]
        })]).await;
        let out = run(&ENGINE, "建一个登录页", None, "sk-test", "mock-model", &format!("http://127.0.0.1:{port}"), "auto", None).await;
        mock.abort();
        assert_eq!(out["ok"], json!(true), "部分成功应 ok:true: {out}");
        assert!(out["partial_error"].is_string(), "应带 partial_error: {out}");
        assert_eq!(out["stopReason"], json!("error"));
        assert_eq!(out["ops"], json!(["template login lg"]));
        let mbt = b64_decode(out["mbt_b64"].as_str().unwrap()).unwrap();
        assert!(mbt.contains("lg"), "已提交的 canonical mbt 不得丢失");
        assert!(out["render"]["artboards"].is_array(), "错误路径也要有 render 兜底");
    }

    /// 只读会话（仅 read_mbt）：终态 render 不得为 null（render_mbt 兜底）。
    #[tokio::test]
    async fn readonly_session_gets_render_fallback() {
        engine_ready().await;
        let _engine_gate = engine_test_gate();
        // 输入用静态种子文档（合法 canonical，无需引擎生成）
        let mbt = seed_doc("rt", 390, 844);

        let (port, mock, _bodies) = spawn_mock_llm(vec![
            serde_json::json!({
                "choices": [{"message": {"role": "assistant", "content": null, "tool_calls": [
                    {"id": "c1", "type": "function", "function": {"name": "read_mbt", "arguments": "{}"}}
                ]}}]
            }),
            serde_json::json!({
                "choices": [{"message": {"role": "assistant", "content": "当前文档包含画板 rt。"}}]
            }),
        ]).await;
        let out = run(&ENGINE, "看下现在的文档", Some(&b64_encode(&mbt)), "sk-test", "mock-model", &format!("http://127.0.0.1:{port}"), "auto", None).await;
        mock.abort();
        assert_eq!(out["ok"], json!(true), "{out}");
        assert_eq!(out["stopReason"], json!("done"));
        assert!(out["render"].is_object(), "只读会话 render 必须兜底非 null: {out}");
        assert!(out["render"]["artboards"].is_array(), "兜底 render 应含 artboards");
        assert!(out["mbt_b64"].is_string(), "mbt 应原样回传");
    }

    /// session 泄漏契约（上游 issues #1 补了 session_count 导出后可测）：
    /// 同一宿主进程内 open×2 → count=+2 → close×2 → count 归零。
    /// 引擎没有该导出时此项不可测（变异保持绿），现在锁定防回归。
    #[tokio::test]
    async fn session_count_zero_after_close() {
        engine_ready().await;
        let _engine_gate = engine_test_gate();
        // 常驻实例：前序测试可能留下缓存会话——重置后「初始计数 0」断言才成立
        crate::wasmtime_host::hard_reset();
        let r = ENGINE.call("session_count_probe", &seed_doc(SEED_BOARD, 390, 844), "").await.unwrap();
        assert_eq!(r["before"], json!(0), "独立宿主进程初始计数应为 0：{r}");
        assert_eq!(r["during"], json!(2), "两次 open 后计数应为 2：{r}");
        assert_eq!(r["after"], json!(0), "close 后计数未归零——会话泄漏回归：{r}");
    }

    /// session_tap 只读链（_in 面唯一 f64 直参计划）：双画板 + flow + **非对称
    /// 坐标**断言导航。锁四件事——artboard 是第 1 参、坐标第 2/3 参（8d206b5 曾
    /// 把 artboard 当 x 解析致 tap 全灭）、x/y 不互换（非对称点 (120,30) 命中而
    /// 转置 (30,120) miss，转置 mutation 必红）、tap_in 直参序 [handle,F64,F64]。
    #[tokio::test]
    async fn session_tap_readonly_via_in_face() {
        engine_ready().await;
        let _engine_gate = engine_test_gate();
        // 建目标画板 + 源画板按钮 + 流：tap (120,30)（按钮 [10,130]×[10,54] 内、
        // 转置点 (30,120) 在外）应导航到 __target
        let mut mbt = seed_doc(SEED_BOARD, 390, 844);
        for op in [
            "create __target 390 844",
            "place __seed button tp_b - 10 10",
            "flow __seed __target tp_b",
        ] {
            let r = ENGINE.call("session_apply_agent", &mbt, op).await.unwrap();
            assert_eq!(r["ok"], json!(true), "准备 op «{op}» 失败：{r}");
            mbt = r["mbt"].as_str().unwrap().to_string();
        }
        // 坐标/参数序回归（artboard 当 x、x/y 转置）都会让导航失败 → 这里红
        let r = ENGINE.call("session_tap", &mbt, "__seed 120 30").await.unwrap();
        assert_eq!(r["ok"], json!(true), "tap 应语义性成功：{r}");
        assert!(
            r["changes"].as_array().is_some_and(|c| !c.is_empty()),
            "命中交互流应有变更记录：{r}"
        );
        assert_eq!(r["current"], json!("__target"), "tap 应导航到目标画板：{r}");
        // 参数个数不足的诚实报错（宿主层 Err,不是 ok:false 信封）
        let bad = ENGINE.call("session_tap", &mbt, "__seed").await;
        assert!(bad.is_err(), "缺坐标参数应报错：{bad:?}");
        assert!(bad.unwrap_err().contains("op_missing_args"));
    }

    /// 会话缓存契约（agent 变更路径迁到 session_apply_agent 的核心机制）：
    /// 常驻 wasmtime 实例下，链式变更 op 的第二 op 必须命中缓存（宿主 hits/misses
    /// 计数断言 hits=1/misses=1；若退回逐次 open→close 会 misses=2、hits=0 → 红）。
    /// 静息 session_count 无法区分命中与失配重开（缓存槽两种情况都持有 1 个会话），
    /// 故宿主提供 session_cache_stats。
    #[tokio::test]
    async fn agent_session_cache_reuse() {
        engine_ready().await;
        let _engine_gate = engine_test_gate();
        // 常驻实例：hits/misses 是绝对值断言，重置后从零计数
        crate::wasmtime_host::hard_reset();

        let seed = seed_doc(SEED_BOARD, 390, 844);
        let r1 = ENGINE
            .call("session_apply_agent", &seed, "place __seed button cb_b - 10 10")
            .await
            .unwrap();
        assert_eq!(r1["ok"], json!(true), "首个变更应成功：{r1}");
        assert!(r1["artboards"].is_array(), "宿主应补画板索引：{r1}");
        let mbt1 = r1["mbt"].as_str().unwrap().to_string();

        // 链式第二 op 之前：缓存的会话应存活（静息计数 1，而非 0）
        let c1 = ENGINE.call("session_count_probe", &mbt1, "").await.unwrap();
        assert_eq!(c1["before"], json!(1), "变更后缓存会话应存活（静息计数 1）：{c1}");

        let r2 = ENGINE
            .call("session_apply_agent", &mbt1, "update __seed cb_b text=\"hi\"")
            .await
            .unwrap();
        assert_eq!(r2["ok"], json!(true), "链式第二 op 应命中缓存成功：{r2}");
        assert!(r2["mbt"].as_str().unwrap_or("").contains("hi"), "canonical 应含更新：{r2}");

        // 命中统计：r1 失配开库 1 次，r2 必须命中（hits=1/misses=1）。
        // 静息 session_count 无法区分「命中复用」与「失配重开」，故用宿主计数。
        let st = ENGINE.call("session_cache_stats", "", "").await.unwrap();
        assert_eq!(st["hits"], json!(1), "链式第二 op 必须命中缓存：{st}");
        assert_eq!(st["misses"], json!(1), "只有首次开库应失配：{st}");

        let c2 = ENGINE
            .call("session_count_probe", r2["mbt"].as_str().unwrap_or(""), "")
            .await
            .unwrap();
        assert_eq!(c2["before"], json!(1), "缓存键前移后仍应恰好持有一个会话：{c2}");
    }
}
