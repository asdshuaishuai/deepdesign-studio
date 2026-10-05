//! Agent 会话状态机（M3.6.7：桌面 agent.rs 循环架构移植——loop 状态/工具执行/引擎调用
//! 全在 Rust，ArkTS 仅 HTTP 传输泵 + UI；引擎 op 经 NAPI AsyncTask 跑在工作线程，
//! UI 线程不再被批量轮堵死（ANR 根因）。
//!
//! 协议：agent_start(instruction, doc_b64) 建会话 → {"action":"llm","messages",...}；
//! ArkTS 对 messages 发一次 OpenAI 兼容 chat（tools/thinking 由会话下发、方言合并
//! 在传输侧），把返回的 assistant message 原样喂 agent_feed_llm → 引擎 op 在工作线程
//! 执行、事件随信封回传 → 循环直至 {"action":"done","outcome":{...}}。
//!
//! 与桌面 agent.rs 的差异（登记）：无 Anthropic 协议半区（ohos 云端仅 OpenAI 兼容）、
//! max_steps=24 且以「轮」计（桌面 200-2000 以「步」计）、检视类 op 无 wasm 导出面
//! （read_mbt 为唯一检视）。

use serde_json::{json, Value};

const ROUNDS: usize = 24;

pub struct AgentSession {
    pub messages: Vec<Value>,
    pub instruction: String,
    pub doc_b64: Option<String>,
    pub rounds: usize,
    pub ops: usize,
    pub review_done: bool,
    pub finished: bool,
}

static AGENT_SESS: Mutex<Option<AgentSession>> = Mutex::new(None);
// std::sync 顶层引用
use std::sync::Mutex;

/// 系统提示（桌面 INSTRUCTIONS 逐段移植；差异段见模块注释——检视类仅 read_mbt、
/// 批量 op 为鸿蒙扩展）。
const LOOP_SYS: &str = r#"You are the embedded design agent of deepDesign Studio (HarmonyOS), a visual prototyping editor.
You operate as a product designer, not a command executor: interpret what the user wants to
ACHIEVE, decide which screens the experience needs, build them, connect them, and verify the result.
The single source of truth is one MoonBit literate .mbt.md document; every operation you issue is
validated by the engine (AgentGate) and committed immediately, so the user watches progress live.

## Mindset
- Derive intent: "a WeChat-style app" means an experience (login, feed, chat, profile, settings),
  not one artboard. Before the first tool call, state a one-line plan: the screen list and how they connect.
- CLARIFY-FIRST TASKS: when the user explicitly asks you to confirm questions before building,
  reply with those questions as plain text — do NOT call tools and do NOT build yet.
- Think in flows: a prototype is screens + navigation. An unconnected screen is unfinished.
- Write real product copy (realistic labels, names, numbers), never lorem ipsum.
- Full-bleed backgrounds are fine: place a background rect and grow it with
  width_mode=fill & height_mode=fill. Nodes with EXPLICIT sizes must never intersect any
  sibling rect (no_sibling_overlap rejects them): before each place, reserve a
  non-intersecting slot; when you know a node's final size, pass [w] [h] inline.
- Two modes: BUILD requests get the full loop below; TWEAK requests ("make the button green")
  get read_mbt, one targeted op, done.

## Build loop (from empty document)
1. PLAN: choose screens; map each to a template. Available (template <tid> <name> [w] [h]):
   login, login_v2, signup, dashboard, profile, settings, list_detail, onboarding,
   empty_state, web_login, web_landing, web_dashboard, pc_app, adaptive_landing.
   Artboard names become ids after sanitization — ASCII snake_case only (e.g. chat_list);
   Chinese copy belongs in node text values, never in ids.
2. CREATE: one "template <tid> <name> [w] [h]" per screen, then IMMEDIATELY read_mbt —
   node ids are only discoverable there. Artboard id = sanitized name.
3. CUSTOMIZE: "update <artboard> <node> k=v ..." per screen; finish one before the next.
   "place <artboard> <component> <instance_id> [variant|-] [x] [y] [w] [h]" adds engine
   components — component ids appear as component="..." in read_mbt output of template
   boards (badge/heading/body_text/text_input/button/divider at minimum). ALWAYS pass
   the final [w] [h] when you know them — the gate evaluates the FINAL bbox.
4. CONNECT: "flow <from> <to> <node>" for every primary CTA (login button, card tap, tab, back).
5. VERIFY: read_mbt and check flows cover every screen; every primary CTA wired.
   Run "fix <artboard>" if violations accumulated.
6. REPORT: stop calling tools and reply in Chinese: screens built and the flow map.

## Tweak loop (document already loaded)
0. read_mbt FIRST — always ground ids and flows before any op.
1. Make the minimal ops. 2. Report what changed.

## Operation grammar (multiple ops per moonviz_op call ALLOWED on this face: one per line,
executed in order — batch a whole screen per call to minimize round trips)
  template <template_id> <name> [w] [h] | create <name> [w] [h]
  | duplicate <artboard> <new_name> | delete-artboard <artboard>
  | place <artboard> <component> <instance_id> [variant|-] [x] [y] [w] [h]
  | move <artboard> <node> <x> <y> | update <artboard> <node> k=v [k=v ...]
  | delete <artboard> <node> | copy <artboard> <node> <new_id> [dx] [dy]
  | reorder <artboard> <node> front|back|up|down | flip <artboard> <node> h|v|both|none
  | align <artboard> left|right|top|bottom|hcenter|vcenter <n1> <n2> ...
  | resize-canvas <artboard> <w> <h>
  | interact <artboard> <node> <trigger> <action>  | uninteract <artboard> <node>
  | state <artboard> <node> <state_name> k=v ...   | set-state <node> <state_name> [toggle]
  | flow <from_artboard> <to_artboard> <node> | unflow <from_artboard> <to_artboard> <node>
  | theme <name> (light|dark|high_contrast|sepia|nord|sunset) | fix <artboard>
- update keys: w h text fill text_color stroke stroke_width radius opacity font_size weight
  shadow rotate blur blend line tracking constraint align italic dash visible layout gap
  justify padding width_mode height_mode x_mode y_mode name.
  Quote values with spaces: text="Sign in". Unquoted words after a space are silently dropped.
- interact triggers: tap long_press swipe_left swipe_right swipe_up swipe_down scroll_end
  key_enter focus blur. interact actions: back | navigate_to:<board> | show_toast:<msg> | haptic.

## Ground truth and errors
- NEVER guess node/component/template ids: templates are listed above; everything else:
  read_mbt. Ids are shared with the human canvas: never rename; new ids = snake_case.
- Errors: unknown_artboard/unknown_node/unknown_template → read_mbt then retry with real ids.
  Predicate violations (overflow, overlap) reject the op with predicate + node_id → adjust values;
  if stuck run fix <artboard>. Never repeat an identical failing op.
- On this engine face read-only inspection ops (list/lint/query/list-components/...) are NOT
  available — read_mbt is your only introspection tool. Use it liberally.

## HarmonyOS batching note
You are running with a per-round HTTP budget: BATCH AGGRESSIVELY. Build one complete screen
per moonviz_op call (template line, then all place/update lines, then all flow lines). Aim to
finish the whole request in 3-6 calls."#;

fn tools_json() -> Value {
    json!([
        {
            "type": "function",
            "function": {
                "name": "moonviz_op",
                "description": "Execute MoonViz design operations (validated by the engine gates, committed to the canonical document). BATCHING: you MAY put multiple operations in one call — separate them with newlines, one op per line, executed in order. Batch aggressively (e.g. build a whole screen in one call). The full operation grammar is in your system prompt.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "op": { "type": "string", "description": "One or more operation lines, e.g. \"template login login_v2 390 844\"" }
                    },
                    "required": ["op"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "read_mbt",
                "description": "Read a structural outline of the current canonical document (artboards, node ids+components, flows) — call when unsure about ids.",
                "parameters": { "type": "object", "properties": {} }
            }
        }
    ])
}

fn review_prompt(goal: &str) -> String {
    format!(
        "[收尾审查] 设计实现已完成。执行强制收尾审查——不得提问，直接用工具修复：\n\
         1) 需求完整度：目标「{goal}」是否全部落实，缺项直接补建；\n\
         2) 操作逻辑连线：可交互元素（按钮/链接）是否已用 flow 建立交互流，缺则补齐；\n\
         3) 综合修复：布局重叠、明显对齐与配色问题。\n\
         修复完成后给出简短中文报告；若无任何问题，只回复「审查通过」。"
    )
}

/// 修订 1 澄清门（ArkTS 同构）：问句特征或征询词判澄清（【回答】续跑放行）。
fn is_clarify(s: &str) -> bool {
    if s.contains("【回答】") {
        return false;
    }
    if s.ends_with('？') || s.ends_with('?') {
        return true;
    }
    for k in ["需要", "是否", "想要", "偏好", "可以告诉我", "还是", "哪一", "哪种", "多少"] {
        if s.contains(k) {
            return true;
        }
    }
    false
}

/// read_mbt 精简大纲：板/节点(id+component)/flows 全量 id 在场，体积 ~4KB
/// （全文回灌撑爆上下文、轮次时延爆炸的实证根因）。
fn outline(doc_b64: &str) -> String {
    let doc = crate::engine::decode_doc(doc_b64).unwrap_or_default();
    let lines: Vec<String> = doc
        .lines()
        .filter(|l| {
            l.starts_with("## ") || l.contains("id=\"") || l.contains("component=\"") || l.starts_with("flow ")
        })
        .map(|l| l.trim().to_string())
        .collect();
    let mut out = lines.join("\n");
    if out.len() > 4000 {
        out = out.chars().take(4000).collect();
    }
    out
}

/// 空/种子文档：会话无文档时以种子承载首 op（桌面 agent.rs::seed_doc 同构）。
fn seed_doc_b64() -> String {
    let d = "---\nmoonviz:\n  format: visual-document\n  revision: 1\n  entry: __seed\n---\n\n# __seed\n\n<!-- moonviz:artboard __seed -->\n```mbt\nfn visual___seed() -> @decl.Prototype {\n  let page = @decl.prototype(name=\"__seed\", width=390.0, height=844.0)\n  page\n}\n```\n";
    use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
    B64.encode(d.as_bytes())
}

/// 单 op 引擎执行（会话 doc 推进 + 种子承载 + __seed 清理标记）。
/// 返回 {ok, note}。__seed 清理不在此处——由 agent_feed 在 op 成功后按需追加。
fn apply_op(sess: &mut AgentSession, line: &str) -> Value {
    let doc = sess.doc_b64.clone().unwrap_or_else(seed_doc_b64);
    match crate::engine::apply_human_op(&doc, line) {
        Err(e) => json!({"ok": false, "note": e}),
        Ok(env) => {
            let ok = env.get("ok").and_then(|x| x.as_bool()).unwrap_or(false);
            if !ok {
                let detail = serde_json::to_string(&env).unwrap_or_default();
                return json!({"ok": false, "note": detail.chars().take(140).collect::<String>()});
            }
            if let Some(m) = env.get("mbt_b64").and_then(|x| x.as_str()) {
                sess.doc_b64 = Some(m.to_string());
            }
            json!({"ok": true, "note": format!("ENGINE {}", line.chars().take(60).collect::<String>())})
        }
    }
}

fn ev(kind: &str, label: &str, detail: &str, ok: bool) -> Value {
    json!({"kind": kind, "label": label, "detail": detail, "ok": ok})
}

/// 建会话：doc_b64 为空 = 空项目（首 op 由种子承载）。返回首动作信封。
pub fn agent_start(instruction: &str, doc_b64: &str) -> Result<Value, String> {
    let mut guard = AGENT_SESS.lock().map_err(|e| format!("agent_lock:{e}"))?;
    // 空文档检测：canonical 无 moonviz:artboard 标记 = 无板（引擎要求至少一个视觉块，
    // session_open 直接失败）→ 会话以种子承载首 op（桌面 agent.rs::seed_doc 同构）
    let has_board = crate::engine::decode_doc(doc_b64)
        .map(|d| d.contains("moonviz:artboard"))
        .unwrap_or(false);
    let doc = if has_board { Some(doc_b64.to_string()) } else { None };
    *guard = Some(AgentSession {
        messages: vec![
            json!({"role": "system", "content": LOOP_SYS}),
            json!({"role": "user", "content": instruction}),
        ],
        instruction: instruction.to_string(),
        doc_b64: doc,
        rounds: 0,
        ops: 0,
        review_done: false,
        finished: false,
    });
    let sess = guard.as_ref().expect("session just set");
    Ok(json!({
        "action": "llm",
        "messages": sess.messages,
        "tools": tools_json(),
        "events": [],
        "doc_b64": sess.doc_b64.clone().unwrap_or_default(),
    }))
}

/// 喂回 LLM 响应（assistant message 原样 JSON）：执行工具调用（引擎人类门）、
/// 推进审查/报告/澄清状态机。返回下一动作 + 轨迹事件。
pub fn agent_feed(message_json: &str) -> Result<Value, String> {
    let mut guard = AGENT_SESS.lock().map_err(|e| format!("agent_lock:{e}"))?;
    let sess = guard.as_mut().ok_or("agent_no_session")?;
    let msg: Value = serde_json::from_str(message_json).map_err(|e| format!("agent_feed_parse:{e}"))?;

    let tcs = msg
        .get("tool_calls")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let content = msg
        .get("content")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    // 空消息（推理 token 耗尽/网关异常）：不 break 不计报告——注入推进提示继续
    if tcs.is_empty() && content.trim().is_empty() {
        sess.messages.push(msg);
        sess.messages.push(json!({"role": "user", "content": "继续：调用 moonviz_op 工具执行设计操作，或给出中文报告。"}));
        return Ok(json!({"action": "llm", "messages": sess.messages, "events": [], "doc_b64": sess.doc_b64.clone().unwrap_or_default()}));
    }

    if tcs.is_empty() {
        // 无工具调用：审查注入点（桌面 review 语义，单次）或收报告
        if !sess.review_done && sess.ops > 0 {
            sess.review_done = true;
            sess.messages.push(msg);
            sess.messages.push(json!({"role": "user", "content": review_prompt(&sess.instruction)}));
            return Ok(json!({"action": "llm", "doc_b64": sess.doc_b64.clone().unwrap_or_default(), "events": [ev("review", "🔎 收尾审查", "需求完整度 · 连线完整度 · 综合修复", true)]}));
        }
        sess.messages.push(msg);
        if sess.ops == 0 && is_clarify(&content) {
            sess.finished = true;
            return Ok(json!({"action": "done", "doc_b64": sess.doc_b64.clone().unwrap_or_default(), "events": [ev("tool_end", "澄清", "模型请求补充信息", true)],
                "outcome": {"ok": true, "reply": content, "executed": false, "ops": 0}}));
        }
        sess.finished = true;
        return Ok(json!({"action": "done", "doc_b64": sess.doc_b64.clone().unwrap_or_default(), "events": [ev("tool_end", "云端回复", content.chars().take(80).collect::<String>().as_str(), true)],
            "outcome": {"ok": true, "reply": content, "executed": sess.ops > 0, "ops": sess.ops}}));
    }

    // assistant(tool_calls) 原样回填（wire 契约：后续 role:'tool' 与 id 配对）
    sess.messages.push(msg);
    let mut events = Vec::new();
    for tc in &tcs {
        let func = tc.get("function").cloned().unwrap_or(json!({}));
        let name = func.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string();
        let tc_id = tc.get("id").and_then(|v| v.as_str()).unwrap_or("call").to_string();
        if name == "read_mbt" {
            let doc = sess.doc_b64.clone().unwrap_or_else(seed_doc_b64);
            let o = outline(&doc);
            events.push(ev("tool_end", "read_mbt", format!("{} 字节（大纲）", o.len()).as_str(), true));
            sess.messages.push(json!({"role": "tool", "tool_call_id": tc_id, "content": o}));
            continue;
        }
        let args: Value = serde_json::from_str(func.get("arguments").and_then(|v| v.as_str()).unwrap_or("{}"))
            .unwrap_or(json!({}));
        let op = args.get("op").and_then(|v| v.as_str()).unwrap_or("").to_string();
        if op.trim().is_empty() {
            sess.messages.push(json!({"role": "tool", "tool_call_id": tc_id, "content": "{\"ok\":false,\"error\":\"empty op\"}"}));
            continue;
        }
        // 批量执行：一行一命令，顺序过引擎人类门；逐行事件 + 聚合一笔 role:'tool'
        let mut done = 0usize;
        let total = op.lines().filter(|l: &&str| !l.trim().is_empty()).count();
        let mut details: Vec<String> = Vec::new();
        for line in op.lines() {
            let one = line.trim();
            if one.is_empty() {
                continue;
            }
            let r = apply_op(sess, one);
            let ok = r.get("ok").and_then(|x| x.as_bool()).unwrap_or(false);
            if ok {
                sess.ops += 1;
                done += 1;
            }
            let note = r.get("note").and_then(|x| x.as_str()).unwrap_or("").to_string();
            events.push(ev(
                "tool_end",
                &format!("{} {}", if ok { "✓" } else { "✗" }, one.chars().take(44).collect::<String>()),
                &note,
                ok,
            ));
            details.push(format!(
                "{} {} :: {}",
                if ok { "✓" } else { "✗" },
                one.chars().take(40).collect::<String>(),
                note.replace('"', "'")
            ));
        }
        let detail = details.join("\\n").chars().take(1800).collect::<String>();
        sess.messages.push(json!({"role": "tool", "tool_call_id": tc_id,
            "content": format!("{{\"ok\":{},\"executed\":{},\"total\":{},\"detail\":\"{}\"}}", done > 0, done, total, detail)}));
    }

    sess.rounds += 1;
    if sess.rounds >= ROUNDS {
        sess.finished = true;
        events.push(ev("failed", "失败", "轮次预算内无可执行操作", false));
        return Ok(json!({"action": "done", "doc_b64": sess.doc_b64.clone().unwrap_or_default(),
            "outcome": {"ok": sess.ops > 0, "reply": format!("已完成 {} 项操作（轮次预算用尽）", sess.ops),
                "executed": sess.ops > 0, "ops": sess.ops}}));
    }
    Ok(json!({"action": "llm", "doc_b64": sess.doc_b64.clone().unwrap_or_default(), "messages": sess.messages, "events": events}))
}

/// 测试钩子：无 LLM 下直接查会话计数（契约测试消费）。
pub fn session_stats() -> Value {
    let guard = AGENT_SESS.lock().map_err(|e| format!("agent_lock:{e}"));
    match guard {
        Ok(g) => match g.as_ref() {
            Some(s) => json!({"rounds": s.rounds, "ops": s.ops, "has_doc": s.doc_b64.is_some(), "messages": s.messages.len()}),
            None => json!({"rounds": -1}),
        },
        Err(e) => json!({"error": format!("agent_lock:{e}")}),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// M3.6.7 会话状态机契约：start → 工具调用轮（模板落板）→ 报告收尾；
    /// 批量 op 一轮多项；澄清门放行；空消息推进。
    #[test]
    fn agent_session_state_machine() {
        let s0 = agent_start("生成登录页", "").expect("agent_start 必须送达");
        assert_eq!(s0["action"], "llm", "首动作=llm：{s0}");
        assert_eq!(s0["messages"].as_array().map(|a| a.len()), Some(2), "system+user");

        // 第 1 喂：批量工具调用（2 op 一轮）
        let feed1 = json!({"role": "assistant", "content": "", "tool_calls": [
            {"id": "c1", "type": "function",
             "function": {"name": "moonviz_op", "arguments": "{\"op\": \"template login 登录页 390 844\\ntemplate signup 注册页 390 844\"}"}},
            {"id": "c2", "type": "function",
             "function": {"name": "read_mbt", "arguments": "{}"}}
        ]});
        let s1 = agent_feed(&feed1.to_string()).expect("feed1 必须送达");
        assert_eq!(s1["action"], "llm", "工具调用后继续 llm：{s1}");
        let evs = s1["events"].as_array().expect("feed1 必须带事件");
        let oks = evs.iter().filter(|e| e["ok"] == json!(true)).count();
        assert!(oks >= 3, "批量 2 op + read_mbt 至少 3 个成功事件：{s1}");
        let st = session_stats();
        assert_eq!(st["ops"], json!(2), "批量 2 op 计数：{st}");
        assert_eq!(st["has_doc"], json!(true), "引擎回包推进会话文档");

        // 第 2 喂：纯文本报告 → 审查注入（桌面 review 语义，单次）→ 报告收尾 done
        let feed2 = json!({"role": "assistant", "content": "已生成登录页与注册页。"});
        let s2 = agent_feed(&feed2.to_string()).expect("feed2 必须送达");
        assert_eq!(s2["action"], "llm", "首报告触发审查注入：{s2}");
        assert!(s2["events"].to_string().contains("收尾审查"), "必须带审查事件");
        let feed3 = json!({"role": "assistant", "content": "审查通过：登录页与注册页已建，导航流已连。"});
        let s3 = agent_feed(&feed3.to_string()).expect("feed3 必须送达");
        assert_eq!(s3["action"], "done", "二报告收尾：{s3}");
        let oc = s3["outcome"].as_object().expect("done 必须带 outcome");
        assert_eq!(oc["executed"], json!(true));
        assert_eq!(oc["ops"], json!(2));

        // 新会话：澄清门（纯文本问句 + 0 op → done(executed=false, reply=原文)）
        let c0 = agent_start("你要什么风格？", "").expect("澄清会话必须送达");
        assert_eq!(c0["action"], "llm");
        let c1 = agent_feed(&json!({"role": "assistant", "content": "你想要深色还是浅色？"}).to_string())
            .expect("澄清喂入必须送达");
        assert_eq!(c1["action"], "done", "澄清收尾：{c1}");
        assert_eq!(c1["outcome"]["executed"], json!(false));
        assert_eq!(c1["outcome"]["reply"], json!("你想要深色还是浅色？"));
    }

    /// 空消息推进守卫：无 tool_calls 且 content 空 → 不收报告，注入推进提示继续。
    #[test]
    fn agent_session_empty_message_nudge() {
        let _ = agent_start("生成登录页", "").expect("start");
        let e = json!({"role": "assistant", "content": ""});
        let s = agent_feed(&e.to_string()).expect("feed");
        assert_eq!(s["action"], "llm", "空消息必须推进而不是收报告：{s}");
        let last = s["messages"].as_array().expect("messages").last().expect("nudge");
        assert!(last["content"].as_str().unwrap_or("").contains("继续"), "必须带推进提示：{last}");
    }
}
