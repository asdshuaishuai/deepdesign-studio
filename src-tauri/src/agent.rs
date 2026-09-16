//! 进程内 Agent 基座：OpenAI chat-completions 工具循环 × MoonViz 引擎管道。
//!
//! 取代原 node + agent-bridge.mjs 子进程桥（85MB JS 运行时）。
//! 请求体为 OpenAI chat wire format（json! 字面量），thinking 家族等非标
//! 字段在构造时直接注入；引擎调用复用 exec_cli 完整管道（用户组件库
//! restore/snapshot 写回、AgentGate 校验、canonical .mbt.md 提交）。
//! 返回契约与原 JS 桥一致：{ok, mbt_b64, render, ops[], stopReason, text}。

use serde_json::{json, Value};
use std::time::Duration;

use crate::exec_cli_pipeline;
use base64::engine::general_purpose::STANDARD as BASE64;

const MAX_STEPS: usize = 20;
const ENGINE_OP_TIMEOUT: Duration = Duration::from_secs(30);
const LLM_TIMEOUT: Duration = Duration::from_secs(180);

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
   Run "missing <artboard>" to catch unwired CTAs, "fix <artboard>" if violations accumulated
   (fix commits when it strictly reduces them).
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
  primary... — full list via list-tokens, use the flat "colors" names). Spacing/radii/typography
  tokens are NOT settable (unknown_token). The override recolors immediately, persists in the
  document's frontmatter tokens: section, and setting the value back to its default removes it.
- interact triggers: tap long_press swipe_left swipe_right swipe_up swipe_down scroll_end
  key_enter focus blur. interact actions: back | haptic | navigate_to:<board>
  | show_toast:<msg> | set_text:<node>:<text> | set_state:<node>:<state>
  | toggle_state:<node> | play_sound:<name>. Define the state via "state" BEFORE
  set_state/toggle_state can target it; call set-state only after a state exists.
- read-only inspection ops (no document change):
  list | flows | list-templates | list-components | list-tools | list-tokens | list-themes
  | lint <artboard> | critique <artboard> | query <artboard> | infer <artboard>
  | spec <artboard> | missing <artboard> | doc-json <artboard> | states <artboard>
  | interactions <artboard> | export-svg <artboard> | export-html <artboard>
  | tap <artboard> <x> <y> | benchmark
- export-html <artboard>: self-contained interactive HTML prototype (node-level tap bindings
  + component states as CSS variants). Use it when the user wants a shareable/runnable demo.
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
/// - MiniMax M2/M3：仅 thinking.type adaptive(默认)/disabled，无等级（M2.x disabled 忽略）
/// - StepFun（platform.stepfun.com，含 Step Plan step_plan/v1）：effort low/medium/high
///   （max 降级 high），无开关
/// - Qwen：DashScope 兼容模式对未知字段严格——仅 vLLU 自部署方言 off 开关
///
/// 档位归一：off / auto / low / medium / high / max；旧值 on → high；未知 → auto。
fn thinking_extra_body(model: &str, level: &str) -> Option<Value> {
    let level = match level {
        "off" => "off",
        "on" | "high" => "high",
        "low" => "low",
        "medium" => "medium",
        "max" => "max",
        _ => "auto",
    };
    if level == "auto" {
        return None;
    }
    let m = model.to_ascii_lowercase();

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

/// 只读命令白名单：**路由契约**——引擎的 `apply-agent-mbt-op-b64` 只接受变更类操作，
/// 任何未列于此的只读 op 都会被它拒绝（`mbt_operation_unsupported`）。
/// 注意 `fix` 不在此列——引擎在 apply 路径为 fix 实现了「违规严格下降才提交」的还债语义，
/// 走只读管道会丢弃变更。反之变更类 op（state/interact/group/responsive…）绝不能入表，
/// 否则变更被静默丢弃且不报错。
/// 提到模块级是为了让 `readonly_whitelist_matches_engine_surface` 能把它与探针集合严格比对。
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

/// Agent 会话的引擎执行状态（对齐 JS 桥 makeExecutor 的语义）。
struct EngineState {
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

impl EngineState {
    fn new(mbt_b64: Option<&str>) -> Result<Self, String> {
        Ok(Self {
            mbt: match mbt_b64 {
                Some(b) if !b.is_empty() => Some(b64_decode(b)?),
                _ => None,
            },
            last_render: None,
            ops: Vec::new(),
        })
    }

    /// 与 exec_cli 相同的完整管道（含用户组件库 restore/snapshot），带 30s 超时。
    async fn exec(&self, commands: Vec<String>) -> Result<Vec<Value>, String> {
        tokio::time::timeout(
            ENGINE_OP_TIMEOUT,
            tokio::task::spawn_blocking(move || exec_cli_pipeline(commands)),
        )
        .await
        .map_err(|_| "engine_timeout".to_string())?
        .map_err(|e| format!("engine_join_failed:{e}"))?
    }

    /// moonviz_op 工具：空项目 bootstrap / 只读路由 / apply-op 三条路径。
    async fn moonviz_op(&mut self, op: &str) -> Value {
        let op = op.trim();
        if op.is_empty() {
            return json!({"ok": false, "error": "op_invalid"});
        }
        if op.contains('\n') || op.contains('\r') {
            return json!({"ok": false, "error": "op_newline_forbidden"});
        }

        // 空项目起步：template/create 可直接引导
        if self.mbt.is_none() && matches!(op.split_whitespace().next(), Some("template") | Some("create")) {
            let rs = self.exec(vec![op.to_string(), "export-mbt-human".into()]).await;
            match rs {
                Ok(rs) => {
                    if let Some(boot) = rs
                        .iter()
                        .find(|r| r.get("mbt").map(|v| v.is_string()).unwrap_or(false) && r.get("ok") == Some(&json!(true)))
                    {
                        self.mbt = boot.get("mbt").and_then(|v| v.as_str()).map(String::from);
                        self.last_render = Some(boot.clone());
                        self.ops.push(op.to_string());
                        return json!({
                            "ok": true, "op": op,
                            "revision": boot.get("revision").cloned().unwrap_or(json!(0)),
                            "artboards": boot.get("artboards").map(artboard_index).unwrap_or(json!([])),
                        });
                    }
                    let err = rs.iter().find(|r| r.get("error").is_some());
                    return json!({"ok": false, "error": err.and_then(|r| r.get("error").cloned()).unwrap_or(json!("boot_failed"))});
                }
                Err(e) => return json!({"ok": false, "error": e}),
            }
        }

        let Some(mbt) = self.mbt.clone() else {
            return json!({"ok": false, "error": "no_mbt_loaded"});
        };

        // 只读命令：引擎输出顺序 banner → load ack → 命令结果，取最后一个非 banner 对象。
        if is_readonly_op(op) {
            let rs = self
                .exec(vec![format!("load-mbt-b64 {}", b64_encode(&mbt)), op.to_string()])
                .await;
            match rs {
                Ok(rs) => {
                    let non_banner: Vec<&Value> =
                        rs.iter().filter(|r| r.get("moonviz").is_none()).collect();
                    let Some(result) = non_banner.last() else {
                        return json!({"ok": false, "error": "readonly_no_output"});
                    };
                    if result.get("error").is_some() {
                        return json!({"ok": false, "error": result.get("error").cloned().unwrap()});
                    }
                    self.ops.push(op.to_string());
                    return if result.is_array() {
                        json!({"ok": true, "result": result})
                    } else {
                        (*result).clone()
                    };
                }
                Err(e) => return json!({"ok": false, "error": e}),
            }
        }

        // 变更操作：apply-agent-mbt-op-b64
        let rs = self
            .exec(vec![format!(
                "apply-agent-mbt-op-b64 {} {}",
                b64_encode(&mbt),
                b64_encode(op)
            )])
            .await;
        match rs {
            Ok(rs) => {
                let result = rs.iter().find(|r| r.get("mbt").is_some());
                match result {
                    Some(r) if r.get("ok") == Some(&json!(true)) => {
                        self.mbt = r.get("mbt").and_then(|v| v.as_str()).map(String::from);
                        self.last_render = Some(r.clone());
                        self.ops.push(op.to_string());
                        json!({
                            "ok": true, "op": op,
                            "debt": r.get("debt").cloned().unwrap_or(json!(0)),
                            "revision": r.get("revision").cloned().unwrap_or(json!(0)),
                            "artboards": r.get("artboards").map(artboard_index).unwrap_or(json!([])),
                        })
                    }
                    _ => {
                        let err = rs.iter().find(|r| r.get("error").is_some());
                        json!({"ok": false, "error": err.and_then(|r| r.get("error").cloned()).unwrap_or(json!("agent_op_failed"))})
                    }
                }
            }
            Err(e) => json!({"ok": false, "error": e}),
        }
    }

    async fn read_mbt(&self) -> Value {
        match &self.mbt {
            Some(m) => json!({"ok": true, "mbt": m}),
            None => json!({"ok": false, "error": "no_mbt_loaded"}),
        }
    }

    /// 终态 render 兜底（移植自 JS 桥）：只读会话（仅 lint/query/flows 等）
    /// 不产生 apply 渲染——用 render-mbt-b64 补齐，保证前端 applyMbtResult
    /// 始终拿到含 artboards/svg 的 render 而不是 null。
    async fn ensure_render(&mut self) {
        if self.last_render.is_some() {
            return;
        }
        let Some(mbt) = self.mbt.clone() else { return };
        let Ok(rs) = self.exec(vec![format!("render-mbt-b64 {}", b64_encode(&mbt))]).await
        else {
            return;
        };
        if let Some(rendered) = rs
            .iter()
            .find(|r| r.get("mbt").map(|v| v.is_string()).unwrap_or(false))
        {
            self.last_render = Some(rendered.clone());
        }
    }

    async fn list_components(&self) -> Value {
        match self.exec(vec!["list-components".into()]).await {
            Ok(rs) => match rs.iter().find(|r| r.is_array()) {
                Some(arr) => json!({"ok": true, "components": arr}),
                None => json!({"ok": true, "components": []}),
            },
            Err(e) => json!({"ok": false, "error": e}),
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
                "description": "Execute one MoonViz design operation (validated by AgentGate, committed to .mbt.md). Also supports read-only inspection ops (no commit): list, flows, list-templates, list-components, list-tools, list-tokens, list-themes, lint <ab>, critique <ab>, query <ab>, infer <ab>, spec <ab>, missing <ab>, doc-json <ab>, states <ab>, interactions <ab>, export-svg <ab>, export-html <ab>, tap <ab> <x> <y>, benchmark.",
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

/// 单次 chat-completions 请求（OpenAI wire format + 非标字段注入）。
async fn chat_once(
    client: &reqwest::Client,
    base_url: &str,
    api_key: &str,
    model: &str,
    thinking: &str,
    messages: &[Value],
) -> Result<Value, String> {
    let mut body = json!({"model": model, "messages": messages, "tools": tools_schema()});
    if let Some(extra) = thinking_extra_body(model, thinking) {
        if let (Some(obj), Some(extra_obj)) = (body.as_object_mut(), extra.as_object()) {
            for (k, v) in extra_obj {
                obj.insert(k.clone(), v.clone());
            }
        }
    }
    let url = format!("{}/chat/completions", base_url.trim_end_matches('/'));
    let resp = client
        .post(&url)
        .bearer_auth(api_key)
        .json(&body)
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
    serde_json::from_str(&text).map_err(|e| format!("llm_response_invalid:{e}"))
}

/// 主循环：chat → tool_calls → 引擎执行 → 回填 → 直至 assistant 总结或 maxSteps。
pub async fn run(
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
    let mut state = match EngineState::new(mbt_b64) {
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
async fn finish_partial(state: &mut EngineState, error: &str) -> Value {
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
    let url = format!("{}/models", base.trim_end_matches('/'));
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .build();
    let Ok(client) = client else {
        return json!({"ok": false, "error": "client_build_failed"});
    };
    let resp = match client.get(&url).bearer_auth(api_key).send().await {
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
        assert_eq!(thinking_extra_body("GLM-5.3", "auto"), None);
        // GLM-5.3 / 5.3-flash（bigmodel 与 z.ai 同构）：强制思考，off/low→low、medium/high→high、max→max
        assert_eq!(thinking_extra_body("glm-5.3", "off"), Some(json!({"reasoning_effort": "low"})));
        assert_eq!(thinking_extra_body("GLM-5.3-Flash", "low"), Some(json!({"reasoning_effort": "low"})));
        assert_eq!(thinking_extra_body("glm-5.3", "medium"), Some(json!({"reasoning_effort": "high"})));
        assert_eq!(thinking_extra_body("glm-5.3", "max"), Some(json!({"reasoning_effort": "max"})));
        // GLM-5.2：开关 + 全档
        assert_eq!(thinking_extra_body("glm-5.2", "off"), Some(json!({"thinking": {"type": "disabled"}})));
        assert_eq!(thinking_extra_body("glm-5.2", "max"), Some(json!({"reasoning_effort": "max"})));
        assert_eq!(thinking_extra_body("glm-5.2", "medium"), Some(json!({"reasoning_effort": "medium"})));
        // Kimi k3 / kimi-for-coding（订阅）：恒开，off→none，medium→high
        assert_eq!(thinking_extra_body("kimi-k3", "off"), Some(json!({"reasoning_effort": "none"})));
        assert_eq!(thinking_extra_body("kimi-k3", "medium"), Some(json!({"reasoning_effort": "high"})));
        assert_eq!(thinking_extra_body("kimi-k3", "max"), Some(json!({"reasoning_effort": "max"})));
        assert_eq!(thinking_extra_body("kimi-for-coding", "low"), Some(json!({"reasoning_effort": "low"})));
        assert_eq!(thinking_extra_body("k3-256k", "high"), Some(json!({"reasoning_effort": "high"})));
        // Kimi k2.x：仅开关，等级不传
        assert_eq!(thinking_extra_body("kimi-k2.6", "off"), Some(json!({"thinking": {"type": "disabled"}})));
        assert_eq!(thinking_extra_body("kimi-k2.6", "high"), None);
        assert_eq!(thinking_extra_body("kimi-k2.7-code", "off"), Some(json!({"thinking": {"type": "disabled"}})));
        // DeepSeek：开关 + effort（medium 服务端映射）
        assert_eq!(thinking_extra_body("deepseek-flash", "off"), Some(json!({"thinking": {"type": "disabled"}})));
        assert_eq!(thinking_extra_body("deepseek-flash", "medium"), Some(json!({"reasoning_effort": "medium"})));
        assert_eq!(thinking_extra_body("deepseek-v4-pro", "high"), Some(json!({"reasoning_effort": "high"})));
        // MiniMax：仅开关
        assert_eq!(thinking_extra_body("MiniMax-M3", "off"), Some(json!({"thinking": {"type": "disabled"}})));
        assert_eq!(thinking_extra_body("MiniMax-M3", "high"), None);
        assert_eq!(thinking_extra_body("MiniMax-M2.7", "max"), None);
        // StepFun（含 Step Plan）：三档 effort，off→low，max→high
        assert_eq!(thinking_extra_body("step-3.7-flash", "low"), Some(json!({"reasoning_effort": "low"})));
        assert_eq!(thinking_extra_body("step-3.7-flash", "off"), Some(json!({"reasoning_effort": "low"})));
        assert_eq!(thinking_extra_body("step-3.7-flash", "medium"), Some(json!({"reasoning_effort": "medium"})));
        assert_eq!(thinking_extra_body("step-3.5-flash", "max"), Some(json!({"reasoning_effort": "high"})));
        // Qwen：仅 vLLM 方言 off
        assert_eq!(thinking_extra_body("qwen3-max", "off"), Some(json!({"chat_template_kwargs": {"enable_thinking": false}})));
        assert_eq!(thinking_extra_body("qwen3-max", "high"), None);
        // 旧值 on → high
        assert_eq!(thinking_extra_body("deepseek-flash", "on"), Some(json!({"reasoning_effort": "high"})));
        // 未知模型：OpenAI 标准字段直传
        assert_eq!(thinking_extra_body("some-model", "high"), Some(json!({"reasoning_effort": "high"})));
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

    /// 引擎命令面契约：白名单里每个 op 都必须在 load 管道上被引擎接受。
    /// 引擎拒绝则说明白名单过时（该 op 已改名或下架）——本机无引擎时跳过。
    #[tokio::test]
    async fn readonly_whitelist_matches_engine_surface() {
        if crate::engine_cli_binary().is_err() {
            eprintln!("跳过：本机无引擎二进制");
            return;
        }
        let rs = tokio::task::spawn_blocking(move || {
            crate::exec_cli_pipeline(vec!["template login wl".into(), "export-mbt-human".into()])
        })
        .await
        .unwrap();
        let Ok(rs) = rs else { eprintln!("跳过：引擎未产出文档"); return };
        let Some(mbt) = rs
            .iter()
            .find(|r| r.get("mbt").map(|v| v.is_string()).unwrap_or(false))
            .and_then(|r| r.get("mbt").and_then(|v| v.as_str()).map(String::from))
        else {
            eprintln!("跳过：引擎未产出 mbt");
            return;
        };

        // 每个白名单 op 的探针形态（占位符换成真实画板/节点）
        let probes = [
            "list", "list-templates", "list-components", "list-tools", "list-tokens",
            "list-themes", "flows", "benchmark", "lint wl", "critique wl", "query wl",
            "infer wl", "spec wl", "missing wl", "doc-json wl", "states wl",
            "interactions wl", "export-svg wl", "export-html wl", "tap wl 10 10",
        ];
        // 双向校验：只断言 probes ⊆ READONLY 是不够的——白名单新增一项却忘了加探针时，
        // 那一项完全不被引擎校验，测试却仍然全绿。两个集合必须严格相等。
        let mut probe_heads: Vec<&str> =
            probes.iter().filter_map(|p| p.split_whitespace().next()).collect();
        probe_heads.sort_unstable();
        let mut whitelist: Vec<&str> = READONLY_OPS.to_vec();
        whitelist.sort_unstable();
        assert_eq!(
            probe_heads, whitelist,
            "探针集合与 READONLY_OPS 不一致：白名单加项必须同步加探针（左=探针，右=白名单）"
        );
        for op in probes {
            let out = crate::exec_cli_pipeline(vec![
                format!("load-mbt-b64 {}", b64_encode(&mbt)),
                op.to_string(),
            ]);
            let out = out.unwrap_or_else(|e| panic!("{op}: 引擎调用失败 {e}"));
            // banner / load ack 之后取最后一个非 banner 结果
            let last = out
                .iter()
                .filter(|r| r.get("moonviz").is_none())
                .next_back();
            let Some(last) = last else { panic!("{op}: 无输出") };
            assert!(
                last.get("error").is_none(),
                "{op} 在引擎上失败（白名单过时？）：{last}"
            );
        }
    }

    /// 引擎模板清单契约：提示词里的模板 id 集合必须与引擎 list-templates 完全一致。
    /// 提示词漏一个模板 → Agent 永远不会选它；多一个 → Agent 会猜不存在的 id。
    #[tokio::test]
    async fn template_ids_match_engine() {
        if crate::engine_cli_binary().is_err() {
            eprintln!("跳过：本机无引擎二进制");
            return;
        }
        let out = tokio::task::spawn_blocking(|| {
            crate::exec_cli_pipeline(vec!["list-templates".into()])
        })
        .await
        .unwrap()
        .expect("list-templates 失败");
        let arr = out
            .iter()
            .find(|r| r.is_array())
            .and_then(|r| r.as_array())
            .expect("list-templates 未返回数组");
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
            "提示词模板清单与引擎不一致（差集：左=提示词，右=引擎）"
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

    /// 解析仓库根 SKILL.md（引擎能力字典，vendored 副本）文末的机器可读清单块。
    /// 块形如：`mutating: a b ...` 后跟缩进续行，直到 ``` 收束。
    fn skill_op_lists() -> (Vec<String>, Vec<String>, Vec<String>) {
        let skill = include_str!("../../SKILL.md");
        let mut mutating = Vec::new();
        let mut readonly = Vec::new();
        let mut cli_only = Vec::new();
        let mut in_block = false;
        let mut cur: Option<&mut Vec<String>> = None;
        for line in skill.lines() {
            let (key, rest) = if let Some(r) = line.strip_prefix("mutating:") {
                in_block = true;
                (0usize, r)
            } else if let Some(r) = line.strip_prefix("readonly:") {
                (1usize, r)
            } else if let Some(r) = line.strip_prefix("cli_only:") {
                (2usize, r)
            } else if line.trim() == "```" && in_block {
                break;
            } else {
                (usize::MAX, "")
            };
            if key != usize::MAX {
                cur = Some(match key {
                    0 => &mut mutating,
                    1 => &mut readonly,
                    _ => &mut cli_only,
                });
            }
            if let Some(list) = cur.as_deref_mut() {
                if !rest.is_empty() || key == usize::MAX {
                    let src = if key == usize::MAX { line.trim() } else { rest.trim() };
                    if !src.is_empty() {
                        list.extend(src.split_whitespace().map(String::from));
                    }
                }
            }
        }
        (mutating, readonly, cli_only)
    }

    /// SKILL.md 字典契约——让字典变成 load-bearing 而非文档摆设：
    /// 1. 字典的 readonly 集合必须与 READONLY_OPS **严格相等**（双向，防单边漂移）；
    /// 2. 字典的每个 mutating op 必须出现在 INSTRUCTIONS 提示词里（字典更新→提示词跟进）；
    /// 3. 引擎实测：mutating op 走 apply 路径被接受（ok 或谓词拦截皆算语法接受）；
    ///    readonly op 走 load 路径可用、走 apply 路径必须 `mbt_operation_unsupported`；
    ///    cli_only op 走 apply 路径必须 `mbt_operation_unsupported`。
    /// 引擎更新后任何一项失配都会红——这就是"新命令无人采纳"盲区的哨兵。
    #[tokio::test]
    async fn skill_dictionary_matches_engine_and_agent() {
        let (mutating, mut readonly, cli_only) = skill_op_lists();
        assert!(!mutating.is_empty() && !readonly.is_empty() && !cli_only.is_empty(),
            "SKILL.md 机器可读清单块缺失或为空——文件被改动时请同步解析逻辑");

        // 1) 字典 readonly ⇔ READONLY_OPS 严格相等
        let mut skill_ro = readonly.clone();
        skill_ro.sort();
        skill_ro.dedup();
        let mut wl: Vec<&str> = READONLY_OPS.to_vec();
        wl.sort();
        assert_eq!(skill_ro, wl,
            "SKILL.md readonly 清单与 READONLY_OPS 不一致（左=字典，右=白名单）——两边必须一起改");

        // 2) 提示词必须教会字典里的每个变更 op（词边界匹配：
        //    子串会让 "list-tokens" 误满足 "token"，也会被顺带的解释文字糊弄过去）
        let contains_word = |hay: &str, needle: &str| {
            hay.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_' || c == '-'))
                .any(|w| w == needle)
        };
        for op in &mutating {
            assert!(contains_word(INSTRUCTIONS, op),
                "SKILL.md 已收录变更 op `{op}`，但 INSTRUCTIONS 提示词未提及——Agent 永远用不到它");
        }

        if crate::engine_cli_binary().is_err() {
            eprintln!("跳过引擎探针：本机无引擎二进制（静态断言已通过）");
            return;
        }

        // 3) 引擎实测。造一篇两画板文档（delete-artboard/flow 需要）。
        let rs = tokio::task::spawn_blocking(move || {
            crate::exec_cli_pipeline(vec![
                "template login lg".into(),
                "template login lg2".into(),
                "export-mbt-human".into(),
            ])
        })
        .await
        .unwrap();
        let rs = rs.expect("构造探针文档失败");
        let mbt = rs
            .iter()
            .find(|r| r.get("mbt").map(|v| v.is_string()).unwrap_or(false))
            .and_then(|r| r.get("mbt").and_then(|v| v.as_str()).map(String::from))
            .expect("引擎未产出 mbt");
        let b = b64_encode(&mbt);

        let apply_probe = |op: &str| -> String {
            let out = crate::exec_cli_pipeline(vec![format!(
                "apply-agent-mbt-op-b64 {b} {}",
                b64_encode(op)
            )])
            .expect("引擎调用失败");
            let last = out.last().cloned().unwrap_or(json!(null));
            last.get("error").and_then(|v| v.as_str()).unwrap_or("OK").to_string()
        };
        let load_probe = |op: &str| -> String {
            let out = crate::exec_cli_pipeline(vec![
                format!("load-mbt-b64 {b}"),
                op.to_string(),
            ])
            .expect("引擎调用失败");
            let last = out
                .iter()
                .filter(|r| r.get("moonviz").is_none())
                .next_back()
                .cloned()
                .unwrap_or(json!(null));
            last.get("error").and_then(|v| v.as_str()).unwrap_or("OK").to_string()
        };

        // 变更 op → 具体探针形态（ok 或谓词/语义错误都算语法接受，唯独 unsupported 不算）
        let mutating_probes: &[(&str, &str)] = &[
            ("create", "create p3 200 300"),
            ("template", "template login p4"),
            ("place", "place lg button b1 - 10 700"),
            ("duplicate", "duplicate lg p5"),
            ("delete-artboard", "delete-artboard lg2"),
            ("move", "move lg logo 3 3"),
            ("copy", "copy lg logo logo_c 5 5"),
            ("delete", "delete lg logo"),
            ("reorder", "reorder lg logo front"),
            ("flip", "flip lg logo h"),
            ("group", "group lg gg logo subtitle"),
            ("ungroup", "ungroup lg gg"),
            ("align", "align lg left logo subtitle"),
            ("resize-canvas", "resize-canvas lg 400 900"),
            ("responsive", "responsive lg"),
            ("restyle", "restyle lg button fill=#00ff00"),
            ("interact", "interact lg logo tap show_toast:hi"),
            ("uninteract", "uninteract lg logo"),
            ("state", "state lg logo pressed fill=#000000"),
            ("set-state", "set-state logo pressed"),
            ("flow", "flow lg lg2 logo"),
            ("theme", "theme dark"),
            ("token", "token primary #FF0000"),
            ("fix", "fix lg"),
            ("update", "update lg logo fill=#123456"),
        ];
        for (head, probe) in mutating_probes {
            assert!(mutating.iter().any(|m| m == head), "探针表含字典外的 op：{head}");
            let err = apply_probe(probe);
            assert!(!err.contains("mbt_operation_unsupported"),
                "`{probe}` 被 apply 路径拒绝（{err}）——字典把它标为变更类，但引擎不认");
        }
        for op in &mutating {
            assert!(mutating_probes.iter().any(|(h, _)| h == op),
                "SKILL.md 新增变更 op `{op}` 但探针表没有它——加探针，别删断言");
        }

        // 只读 op：load 路径必须可用，apply 路径必须 unsupported（路由契约双向锁定）
        let readonly_probes: &[(&str, &str)] = &[
            ("list", "list"),
            ("flows", "flows"),
            ("list-templates", "list-templates"),
            ("list-components", "list-components"),
            ("list-tools", "list-tools"),
            ("list-tokens", "list-tokens"),
            ("list-themes", "list-themes"),
            ("benchmark", "benchmark"),
            ("lint", "lint lg"),
            ("critique", "critique lg"),
            ("query", "query lg"),
            ("infer", "infer lg"),
            ("spec", "spec lg"),
            ("missing", "missing lg"),
            ("doc-json", "doc-json lg"),
            ("states", "states lg"),
            ("interactions", "interactions lg"),
            ("export-svg", "export-svg lg"),
            ("export-html", "export-html lg"),
            ("tap", "tap lg 10 10"),
        ];
        for op in &readonly {
            let Some((_, probe)) = readonly_probes.iter().find(|(h, _)| h == op) else {
                panic!("SKILL.md 新增只读 op `{op}` 但探针表没有它——加探针，别删断言");
            };
            let load_err = load_probe(probe);
            assert_eq!(load_err, "OK", "只读 op `{probe}` 在 load 路径失败：{load_err}");
            let apply_err = apply_probe(probe);
            assert!(apply_err.contains("mbt_operation_unsupported"),
                "只读 op `{probe}` 走 apply 路径应被拒绝，实际返回：{apply_err}——若引擎已把它变为变更类，请同步字典与白名单");
        }
        assert_eq!(readonly_probes.len(), readonly.len(),
            "只读探针表与字典条目数不一致——探针表不得收录字典外的 op");

        // cli_only：apply 路径一律 unsupported
        for op in &cli_only {
            let err = apply_probe(op);
            assert!(err.contains("mbt_operation_unsupported"),
                "cli_only 项 `{op}` 在 apply 路径应返回 unsupported，实际：{err}");
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

    /// 端到端 back 任务测试：mock OpenAI 端点（脚本化两轮 tool_calls）× 真实引擎二进制。
    /// 覆盖：空项目 bootstrap → apply-op → 终态总结 → canonical mbt 契约。
    #[tokio::test]
    async fn agent_loop_with_mock_llm_and_real_engine() {
        if crate::engine_cli_binary().is_err() {
            eprintln!("跳过：本机无引擎二进制");
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
    async fn spawn_mock_llm(rounds: Vec<Value>) -> (u16, tokio::task::JoinHandle<()>) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
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
                                if let Some(len) = s
                                    .lines()
                                    .find_map(|l| l.to_ascii_lowercase().strip_prefix("content-length:").map(|v| v.trim().to_string()))
                                    .and_then(|v| v.parse::<usize>().ok())
                                {
                                    if raw.len() >= body_start + len { break; }
                                }
                            }
                        }
                    }
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
        (port, handle)
    }

    /// 中途 LLM 失败（第二轮连接被拒）：已提交工作必须保留。
    #[tokio::test]
    async fn mid_run_llm_failure_preserves_committed_work() {
        if crate::engine_cli_binary().is_err() {
            eprintln!("跳过：本机无引擎二进制");
            return;
        }
        // mock 只服务第一轮（bootstrap tool_call），之后 listener 关闭 → 第二轮连接被拒
        let (port, mock) = spawn_mock_llm(vec![serde_json::json!({
            "choices": [{"message": {"role": "assistant", "content": null, "tool_calls": [
                {"id": "c1", "type": "function", "function": {"name": "moonviz_op",
                 "arguments": "{\"op\": \"template login lg\"}"}}
            ]}}]
        })]).await;
        let out = run("建一个登录页", None, "sk-test", "mock-model", &format!("http://127.0.0.1:{port}"), "auto").await;
        mock.abort();
        assert_eq!(out["ok"], json!(true), "部分成功应 ok:true: {out}");
        assert!(out["partial_error"].is_string(), "应带 partial_error: {out}");
        assert_eq!(out["stopReason"], json!("error"));
        assert_eq!(out["ops"], json!(["template login lg"]));
        let mbt = b64_decode(out["mbt_b64"].as_str().unwrap()).unwrap();
        assert!(mbt.contains("lg"), "已提交的 canonical mbt 不得丢失");
        assert!(out["render"]["artboards"].is_array(), "错误路径也要有 render 兜底");
    }

    /// 只读会话（仅 read_mbt）：终态 render 不得为 null（render-mbt-b64 兜底）。
    #[tokio::test]
    async fn readonly_session_gets_render_fallback() {
        if crate::engine_cli_binary().is_err() {
            eprintln!("跳过：本机无引擎二进制");
            return;
        }
        // 用真实引擎生成一个 mbt 文档作为输入
        let rs = tokio::task::spawn_blocking(move || {
            crate::exec_cli_pipeline(vec!["template login rt".into(), "export-mbt-human".into()])
        })
        .await
        .unwrap();
        let mbt_b64 = match rs {
            Ok(rs) => rs.iter().find(|r| r.get("mbt").map(|v| v.is_string()).unwrap_or(false))
                .and_then(|r| r.get("mbt").and_then(|v| v.as_str()).map(String::from)),
            Err(_) => None,
        };
        let Some(mbt) = mbt_b64 else { eprintln!("跳过：引擎未产出 mbt"); return };

        let (port, mock) = spawn_mock_llm(vec![
            serde_json::json!({
                "choices": [{"message": {"role": "assistant", "content": null, "tool_calls": [
                    {"id": "c1", "type": "function", "function": {"name": "read_mbt", "arguments": "{}"}}
                ]}}]
            }),
            serde_json::json!({
                "choices": [{"message": {"role": "assistant", "content": "当前文档包含登录页 rt。"}}]
            }),
        ]).await;
        let out = run("看下现在的文档", Some(&b64_encode(&mbt)), "sk-test", "mock-model", &format!("http://127.0.0.1:{port}"), "auto").await;
        mock.abort();
        assert_eq!(out["ok"], json!(true), "{out}");
        assert_eq!(out["stopReason"], json!("done"));
        assert!(out["render"].is_object(), "只读会话 render 必须兜底非 null: {out}");
        assert!(out["render"]["artboards"].is_array(), "兜底 render 应含 artboards");
        assert!(out["mbt_b64"].is_string(), "mbt 应原样回传");
    }
}
