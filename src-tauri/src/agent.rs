//! 进程内 Agent 基座：OpenAI/Anthropic 工具调用循环 × MoonViz wasm 引擎。
//!
//! 引擎是预编译 WasmGC 产物（frontend/vendor/moonviz.wasm），本模块经
//! `EngineHost`（Rusty V8 进程内宿主，与前端画布各自持有实例、只交换
//! canonical 文本）调用：变更 op → apply_agent_op（与 CLI apply-agent-mbt-op-b64
//! 同一分发器，AgentGate），空项目起步 → 种子文档 + apply_human_op 引导。
//! 只读检视面（lint/critique/query/...）经 wasm session API 路由可达
//! （engine-v0.1.1-fix 导出 24 个 session_*；仅 list-tools/doc-json 无对应导出）。
//! 请求体为 OpenAI chat wire format 或 Anthropic Messages wire
//! （协议按 base_url 探测，json! 字面量），thinking 家族等非标字段在构造时
//! 直接注入。返回契约与原 JS 桥一致：{ok, mbt_b64, render, ops[], stopReason, text}。

use serde_json::{json, Value};
use std::time::Duration;

use crate::EngineHost;
use base64::engine::general_purpose::STANDARD as BASE64;

const MAX_STEPS: usize = 20;
const ENGINE_OP_TIMEOUT: Duration = Duration::from_secs(30);
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
- Think in flows: a prototype is screens + navigation. An unconnected screen is unfinished.
- Write real product copy (realistic labels, names, numbers), never lorem ipsum.
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
   "place <artboard> <component> <instance_id> [variant|-] [x] [y]" to add engine components
   (discover ids via list_components; "-" as variant means default).
4. CONNECT: "flow <from> <to> <node>" for every primary CTA (login button, card tap, tab, back).
   Use "interact" for anything richer than navigation (show_toast, set_state, haptic, play_sound) —
   and define the target with "state" first if you want a pressed/selected visual.
5. VERIFY: read_mbt and check flows cover every screen; every primary CTA wired; no dangling refs.
   Run "fix <artboard>" if violations accumulated (on docs carrying human-canvas debt it may be
   rejected — the debt count in each apply result tells you how much is left).
6. REPORT: stop calling tools and summarize: screens built and the flow map.

## Tweak loop (document already loaded)
0. read_mbt FIRST — always ground ids and flows before any op.
1. Make the minimal ops. 2. Report what changed.

## Operation grammar (one op per moonviz_op call, no newlines)
  template <template_id> <name> [w] [h] | create <name> [w] [h]
  | duplicate <artboard> <new_name> | delete-artboard <artboard>
  | place <artboard> <component> <instance_id> [variant|-] [x] [y]
  | move <artboard> <node> <x> <y> | update <artboard> <node> k=v [k=v ...]
  | delete <artboard> <node> | copy <artboard> <node> <new_id> [dx] [dy]
  | reorder <artboard> <node> front|back|up|down | flip <artboard> <node> h|v|both|none
  | group <artboard> <group_id> <n1> <n2> ... | ungroup <artboard> <group_id>
  | align <artboard> left|right|top|bottom|hcenter|vcenter <n1> <n2> ...
  | restyle <artboard> <component_id> k=v ...   (propagate to that component's instances)
  | resize-canvas <artboard> <w> <h> | responsive <artboard>  (adds _tablet/_desktop variants)
  | interact <artboard> <node> <trigger> <action>  | uninteract <artboard> <node>
  | state <artboard> <node> <state_name> k=v ...   | set-state <node> <state_name> [toggle]
  | flow <from_artboard> <to_artboard> <node>
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
  | benchmark. Use them to ground decisions before mutating (lint catches contrast/touch-target
  debt, missing finds unwired CTAs, query lists nodes, states/interactions show what's wired).
  Exceptions with no wasm export — never call: list-tools, doc-json (use read_mbt / list-ops
  introspection instead). Mutations still go through moonviz_op only.
- update keys: w h text fill text_color stroke stroke_width radius opacity font_size weight
  shadow rotate blur blend line tracking constraint align italic dash visible layout gap
  justify padding width_mode height_mode x_mode y_mode name.
  (align left|center|right; dash solid|dashed|dotted; visible true|false;
   layout vertical|horizontal|none; width_mode/height_mode hug|fill; x_mode/y_mode center|start)
  Quote values with spaces: text="Sign in".
  Unquoted words after a space are silently dropped — always quote multi-word text.
- duplicate is the cheapest way to spawn "a similar screen" before diverging with update.
- The engine REJECTS unsupported ops with mbt_operation_unsupported. Notably "constrain" and a
  standalone "name" op are CLI-only surfaces, NOT reachable here — use "update ... name=<id>".

## Ground truth and errors
- NEVER guess node/component/template/theme ids. Templates: list above; components: list_components;
  everything else: read_mbt. Ids are shared with the human canvas: never rename; new ids = snake_case.
- Errors: unknown_artboard/unknown_node/unknown_component/unknown_template → read_mbt then retry with real ids.
  Predicate violations (overflow, overlap) reject the op with predicate + node_id + detail → adjust values;
  if stuck run fix <artboard>. Never repeat an identical failing op.
- debt = remaining tolerated violations; keep it 0. All changes go through moonviz_op only."#;

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
fn protocol_for(base_url: &str) -> Protocol {
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
    if m.contains("glm-5.3") || m.contains("glm-5.3-flash") {
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
const READONLY_OPS: [&str; 20] = [
    // 无参清点类
    "list", "list-templates", "list-components", "list-tools", "list-tokens", "list-themes",
    "flows", "benchmark",
    // 需 <artboard> 的检视类
    "lint", "critique", "query", "infer", "spec", "missing", "doc-json", "states",
    "interactions", "export-svg", "export-html",
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

        // 空项目起步：template/create 经种子文档引导（人类门语义——画布首板同路），
        // 首个 op 落地后立即删除种子画板，canonical 由引擎回传。
        if self.mbt.is_none()
            && matches!(op.split_whitespace().next(), Some("template") | Some("create"))
        {
            let seed = seed_doc(SEED_BOARD, 24, 24);
            let mut r = self.call("apply_human_op", &seed, op).await;
            if r.get("ok") != Some(&json!(true)) {
                return r;
            }
            let committed = r
                .get("mbt")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            r = self.call("apply_human_op", &committed, &format!("delete-artboard {SEED_BOARD}")).await;
            if r.get("ok") != Some(&json!(true)) {
                return json!({"ok": false, "error": format!("seed_cleanup_failed:{op}")});
            }
            self.mbt = r.get("mbt").and_then(|v| v.as_str()).map(String::from);
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
        // 参数（artboard / x y）由 op 的剩余部分携带，宿主在单次调用内完成
        // open→call→close 生命周期。
        if is_readonly_op(op) {
            let head = op.split_whitespace().next().unwrap_or("");
            let args = op[head.len()..].trim();
            let (fn_name, session) = match head {
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
                "tap" => ("session_tap", true),
                "benchmark" => ("session_benchmark", true),
                // 直调导出（无状态）
                "list-templates" => ("list_templates", false),
                "list-components" => ("list_components", false),
                "list-tokens" => ("list_tokens", false),
                "list-themes" => ("list_themes", false),
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
            let _ = session; // 宿主按 fn 名前缀自行判断 session 包装
            let r = self.call(fn_name, &mbt, args).await;
            self.ops.push(op.to_string());
            return json!({"ok": true, "op": op, "result": r});
        }

        // 变更操作：apply_agent_op（与 CLI apply-agent-mbt-op-b64 同一分发器，AgentGate）
        let r = self.call("apply_agent_op", &mbt, op).await;
        if r.get("ok") == Some(&json!(true)) && r.get("mbt").and_then(|v| v.as_str()).is_some() {
            self.mbt = r.get("mbt").and_then(|v| v.as_str()).map(String::from);
            self.last_render = Some(r.clone());
            self.ops.push(op.to_string());
            json!({
                "ok": true, "op": op,
                "debt": r.get("debt").cloned().unwrap_or(json!(0)),
                "revision": r.get("revision").cloned().unwrap_or(json!(0)),
                "artboards": r.get("artboards").map(artboard_index).unwrap_or(json!([])),
            })
        } else {
            r
        }
    }

    async fn read_mbt(&self) -> Value {
        match &self.mbt {
            Some(m) => json!({"ok": true, "mbt": m}),
            None => json!({"ok": false, "error": "no_mbt_loaded"}),
        }
    }

    /// 终态 render 兜底（移植自 JS 桥）：无 apply 渲染的会话（只读尝试/零变更）
    /// 用 render_mbt 补齐，保证前端 applyMbtResult 拿到的不是 null。
    async fn ensure_render(&mut self) {
        if self.last_render.is_some() {
            return;
        }
        let Some(mbt) = self.mbt.clone() else { return };
        let rendered = self.call("render_mbt", &mbt, "").await;
        if rendered.get("mbt").is_some_and(|v| v.is_string()) {
            self.last_render = Some(rendered);
        }
    }

    /// 组件清单：经桥取前端同源快照（wasm 0.1.1 未导出 list_components；
    /// 快照由 sync-engine.mjs 用真机探针验证生成）。
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

/// OpenAI chat tools 定义（json! 字面量，schema 由契约测试锚定）。
fn tools_schema() -> Value {
    json!([
        {
            "type": "function",
            "function": {
                "name": "moonviz_op",
                "description": "Execute one MoonViz MUTATING design operation (AgentGate-validated, committed to .mbt.md): template/create/duplicate/delete-artboard/place/move/update/delete/copy/reorder/flip/group/ungroup/align/resize-canvas/responsive/restyle/interact/uninteract/state/set-state/flow/theme/token/fix. Also supports READ-ONLY inspection ops routed via the engine session API (no commit): list, flows, list-templates, list-components, list-tokens, list-themes, lint <ab>, critique <ab>, query <ab>, infer <ab>, spec <ab>, missing <ab>, states <ab>, interactions <ab>, export-svg <ab>, export-html, tap <ab> <x> <y>, benchmark. Exceptions without wasm exports: list-tools, doc-json.",
                "parameters": {
                    "type": "object",
                    "properties": {"op": {"type": "string", "description": "One operation string, e.g. \"update login title text=\\\"Sign in\\\"\""}},
                    "required": ["op"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "read_mbt",
                "description": "Read the current canonical .mbt.md source of truth (node ids, flows, all screens).",
                "parameters": {"type": "object", "properties": {}}
            }
        },
        {
            "type": "function",
            "function": {
                "name": "list_components",
                "description": "List all engine UI component presets (id, category, variants).",
                "parameters": {"type": "object", "properties": {}}
            }
        }
    ])
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
            let mut body = json!({"model": model, "messages": messages, "tools": tools_schema()});
            if let Some(extra) = thinking_extra_body(model, thinking, Protocol::OpenAi) {
                if let (Some(obj), Some(extra_obj)) = (body.as_object_mut(), extra.as_object()) {
                    for (k, v) in extra_obj {
                        obj.insert(k.clone(), v.clone());
                    }
                }
            }
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
        .map_err(|e| format!("llm_request_failed:{e}"))?;
    let status = resp.status();
    let text = resp
        .text()
        .await
        .map_err(|e| format!("llm_read_failed:{e}"))?;
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

/// 主循环：chat → tool_calls → 引擎执行 → 回填 → 直至 assistant 总结或 maxSteps。
pub async fn run(
    host: &EngineHost,
    instruction: &str,
    mbt_b64: Option<&str>,
    api_key: &str,
    model: &str,
    base_url: &str,
    thinking: &str,
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

    let Ok(client) = reqwest::Client::builder().timeout(LLM_TIMEOUT).build() else {
        return json!({"ok": false, "error": "client_build_failed", "ops": state.ops, "text": ""});
    };

    let mut messages: Vec<Value> = vec![
        json!({"role": "system", "content": instructions()}),
        json!({"role": "user", "content": instruction}),
    ];

    for step in 0..MAX_STEPS {
        let resp = match chat_once(&client, &base, api_key, model, thinking, &messages).await {
            Ok(r) => r,
            Err(e) => {
                // 中途 LLM 失败：已提交的引擎操作不丢弃（对齐旧桥语义）——
                // 零操作时才整体失败，否则带部分状态返回，前端可应用已完成的变更。
                return finish_partial(&mut state, &e).await;
            }
        };
        let Some(msg) = resp
            .pointer("/choices/0/message")
            .and_then(|v| v.as_object().cloned())
        else {
            return finish_partial(&mut state, "llm_no_choice").await;
        };
        let tool_calls: Vec<Value> = msg
            .get("tool_calls")
            .and_then(|v| v.as_array().cloned())
            .unwrap_or_default();

        if tool_calls.is_empty() {
            // 终态：assistant 总结
            let text = msg.get("content").and_then(|v| v.as_str()).unwrap_or("").to_string();
            if state.mbt.is_none() && state.ops.is_empty() {
                return json!({
                    "ok": false, "error": "agent_no_mbt",
                    "detail": "LLM did not call any tools",
                    "ops": state.ops, "text": text,
                });
            }
            state.ensure_render().await;
            let stop = if step + 1 >= MAX_STEPS { "max_turns" } else { "done" };
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
            let args: Value = serde_json::from_str(args_raw).unwrap_or(json!({}));
            let result = match name {
                "moonviz_op" => {
                    let op = args.get("op").and_then(|v| v.as_str()).unwrap_or("").to_string();
                    state.moonviz_op(&op).await
                }
                "read_mbt" => state.read_mbt().await,
                "list_components" => state.list_components().await,
                other => json!({"ok": false, "error": format!("unknown_tool:{other}")}),
            };
            messages.push(json!({
                "role": "tool",
                "tool_call_id": id,
                "content": serde_json::to_string(&result).unwrap_or_else(|_| "{}".into()),
            }));
        }
    }

    // 跑满步数：尽力返回当前状态
    state.ensure_render().await;
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
        .filter_map(|m| m.get("id").and_then(|v| v.as_str()).map(|id| json!({"id": id})))
        .collect();
    json!({"ok": true, "models": models})
}

#[cfg(test)]
mod tests {
    use super::*;

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
        assert!(is_readonly_op("benchmark"));
        // 带画板参数的检视类（引擎 0.1.0 新增：spec/missing/doc-json/states/interactions/export-svg）
        assert!(is_readonly_op("spec login"));
        assert!(is_readonly_op("missing login"));
        assert!(is_readonly_op("doc-json login"));
        assert!(is_readonly_op("states login"));
        assert!(is_readonly_op("interactions login"));
        assert!(is_readonly_op("export-svg login"));
        assert!(is_readonly_op("export-html login"));
        // 变更类绝不入表：入表会导致走 load 管道而静默丢弃变更
        assert!(!is_readonly_op("fix login"));
        assert!(!is_readonly_op("update login btn fill=#fff"));
        assert!(!is_readonly_op("state login btn pressed fill=#000"));
        assert!(!is_readonly_op("interact login btn tap navigate_to:lg"));
        assert!(!is_readonly_op("group login g1 a b"));
        assert!(!is_readonly_op("responsive login"));
        assert!(!is_readonly_op("token primary #FF0000"));
        assert!(!is_readonly_op(""));
    }

    /// 共享宿主实例：测试无 WebView，走 node 子进程宿主驱动同一份 wasm 产物
    /// （node ≥24）。产物缺失/宿主不可用时调用返回 Err（各测试据此跳过）。
    const ENGINE: EngineHost = EngineHost::NodeWasm;

    /// 引擎 wasm 面契约：经 node 宿主驱动**真产物**——种子文档可承载 op、
    /// AgentGate 拒绝带债提交、canonical mbt 回传、组件快照非空。
    #[tokio::test]
    async fn wasm_engine_surface_contract() {
        let Ok(v) = ENGINE.call("version_info", "", "").await else {
            eprintln!("跳过：V8 宿主不可用");
            return;
        };
        if v.get("ok") != Some(&json!(true)) {
            eprintln!("跳过：wasm 产物不可用（先跑 node scripts/sync-engine.mjs）");
            return;
        }

        // 种子文档可承载变更 op（空文档会 mbt_no_visual_blocks——种子引导的前提）
        let r = ENGINE
            .call("apply_human_op", &seed_doc(SEED_BOARD, 390, 844), "template login wl 390 844")
            .await
            .unwrap();
        assert_eq!(r["ok"], json!(true), "种子文档上的 template op 失败：{r}");
        assert!(r["mbt"].as_str().is_some_and(|m| m.contains("wl")), "apply 结果应含 canonical mbt");

        // AgentGate：明显越界的放置必须整体拒绝（双门语义仍在 wasm 面生效）
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
        let Ok(out) = ENGINE.call("list_templates", "", "").await else {
            eprintln!("跳过：V8 宿主不可用");
            return;
        };
        let Some(arr) = out.as_array() else {
            eprintln!("跳过：wasm 产物不可用");
            return;
        };
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

    /// 提示词不得再教 Agent 使用引擎 apply 路径会拒绝的 op。
    #[test]
    fn prompt_avoids_apply_rejected_ops() {
        // constrain 与独立 name op 仅存在于 CLI 直连面，apply-agent 路径返回
        // mbt_operation_unsupported，提示词必须把它们标为不可达而非教 Agent 使用。
        assert!(
            INSTRUCTIONS.contains("mbt_operation_unsupported"),
            "提示词必须告知 Agent 存在被引擎拒绝的 op"
        );
        assert!(
            INSTRUCTIONS.contains("constrain"),
            "提示词必须点名 constrain 不可达"
        );
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

    /// 引擎（node 宿主 × 真 wasm 产物）可用性探针：不可用即跳过，绿不是假绿。
    async fn engine_ready() -> bool {
        matches!(
            ENGINE.call("version_info", "", "").await,
            Ok(v) if v.get("ok") == Some(&json!(true))
        )
    }

    /// 端到端 back 任务测试：mock OpenAI 端点（脚本化两轮 tool_calls）× 真实 wasm 引擎。
    /// 覆盖：空项目种子引导 → apply-op → 终态总结 → canonical mbt 契约。
    #[tokio::test]
    async fn agent_loop_with_mock_llm_and_real_engine() {
        if !engine_ready().await {
            eprintln!("跳过：V8 宿主或 wasm 产物不可用（node ≥24 + node scripts/sync-engine.mjs）");
            return;
        }
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
            "auto",
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
        if !engine_ready().await {
            eprintln!("跳过：V8 宿主或 wasm 产物不可用");
            return;
        }
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
            // 基址带 /v1 尾缀——正是用户粘贴 models.dev 快照值的形态，
        // 锁死"双 /v1"拼装回归（base_no_v1 strip 逻辑）
        &format!("http://127.0.0.1:{port}/anthropic/v1"),
            "high",
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
        if !engine_ready().await {
            eprintln!("跳过：V8 宿主或 wasm 产物不可用（node ≥24 + node scripts/sync-engine.mjs）");
            return;
        }
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

    /// session 面宿主契约：经 ENGINE 宿主（node 驱动真 wasm）走完整 session
    /// 生命周期——open → lint/flows/list_artboards → close 全部可用。
    /// 这是只读路由的宿主层证据（agent.rs 路由 + 宿主包装 + wasm 导出三层）。
    #[tokio::test]
    async fn session_api_host_contract() {
        if !engine_ready().await {
            eprintln!("跳过：V8 宿主或 wasm 产物不可用");
            return;
        }
        let seed = seed_doc("sd", 390, 844);
        let lint = ENGINE.call("session_lint", &seed, "sd").await.unwrap();
        // lint 返回违规数组（空=无违规）——可解析即通过
        serde_json::from_str::<Value>(lint.to_string().as_str()).unwrap();
        let flows = ENGINE.call("session_flows", &seed, "").await.unwrap();
        serde_json::from_str::<Value>(flows.to_string().as_str()).unwrap();
        let arts = ENGINE.call("session_list_artboards", &seed, "").await.unwrap();
        let arr = arts.as_array().expect("session_list_artboards 应返回数组");
        assert!(arr.iter().any(|a| a.get("id").and_then(|v| v.as_str()) == Some("sd")));
        let bench = ENGINE.call("session_benchmark", &seed, "").await.unwrap();
        assert!(bench.get("avg_score").is_some(), "session_benchmark 应返回评分对象：{bench}");
        // 直调检视导出
        let tokens = ENGINE.call("list_tokens", "", "").await.unwrap();
        assert!(tokens.get("colors").is_some(), "list_tokens 应返回颜色分组：{tokens}");
        let themes = ENGINE.call("list_themes", "", "").await.unwrap();
        assert!(themes.as_array().is_some_and(|a| a.len() >= 5), "list_themes 应返回 6 主题");
    }

    /// 中途 LLM 失败（第二轮连接被拒）：已提交工作必须保留。
    #[tokio::test]
    async fn mid_run_llm_failure_preserves_committed_work() {
        if !engine_ready().await {
            eprintln!("跳过：V8 宿主或 wasm 产物不可用");
            return;
        }
        // mock 只服务第一轮（bootstrap tool_call），之后 listener 关闭 → 第二轮连接被拒
        let (port, mock, _bodies) = spawn_mock_llm(vec![serde_json::json!({
            "choices": [{"message": {"role": "assistant", "content": null, "tool_calls": [
                {"id": "c1", "type": "function", "function": {"name": "moonviz_op",
                 "arguments": "{\"op\": \"template login lg\"}"}}
            ]}}]
        })]).await;
        let out = run(&ENGINE, "建一个登录页", None, "sk-test", "mock-model", &format!("http://127.0.0.1:{port}"), "auto").await;
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
        if !engine_ready().await {
            eprintln!("跳过：V8 宿主或 wasm 产物不可用");
            return;
        }
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
        let out = run(&ENGINE, "看下现在的文档", Some(&b64_encode(&mbt)), "sk-test", "mock-model", &format!("http://127.0.0.1:{port}"), "auto").await;
        mock.abort();
        assert_eq!(out["ok"], json!(true), "{out}");
        assert_eq!(out["stopReason"], json!("done"));
        assert!(out["render"].is_object(), "只读会话 render 必须兜底非 null: {out}");
        assert!(out["render"]["artboards"].is_array(), "兜底 render 应含 artboards");
        assert!(out["mbt_b64"].is_string(), "mbt 应原样回传");
    }
}
