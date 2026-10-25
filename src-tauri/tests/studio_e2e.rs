//! 两阶段工作室端到端（真实 LLM，环境变量门控）：
//!   STUDIO_E2E=1 DD_BASE=... DD_KEY=... DD_MODEL=... \
//!     cargo test --test studio_e2e -- --nocapture
//!
//! 验证「一句话 → PRD → UI 设计文档 → 可交互原型」的完整链路：
//!   阶段1 prd：只产出文档，画布必须零变化
//!   阶段2 ui ：基于 PRD 产出设计文档
//!   阶段3 建画布：带两份文档约束，产出真实 op 与可渲染画板
//! 断言重点是**阶段隔离**：文档阶段的 ops 必须为空、mbt 不变。

use deepdesign_studio_lib::{agent, EngineHost};

const IDEA: &str = "城市露营装备租赁小程序，5 个页面，自然绿色调，面向周末轻露营的年轻人";

#[tokio::test(flavor = "multi_thread")]
async fn studio_two_phase_real_llm_e2e() {
    if std::env::var("STUDIO_E2E").is_err() {
        eprintln!("跳过：设置 STUDIO_E2E=1 与 DD_BASE/DD_KEY/DD_MODEL 后启用");
        return;
    }
    let base = std::env::var("DD_BASE").expect("DD_BASE");
    let key = std::env::var("DD_KEY").expect("DD_KEY");
    let model = std::env::var("DD_MODEL").unwrap_or_else(|_| "step-3.7-flash".into());
    let host = EngineHost;

    let progress = |v: serde_json::Value| {
        let t = v.get("type").and_then(|x| x.as_str()).unwrap_or("?");
        if t == "done" || t == "failed" || t == "doc_written" || t == "assistant_text" {
            let brief = match t {
                "doc_written" => format!("kind={} chars={}", v.get("kind").and_then(|x| x.as_str()).unwrap_or(""),
                                         v.get("chars").and_then(|x| x.as_u64()).unwrap_or(0)),
                "assistant_text" => v.get("text").and_then(|x| x.as_str()).unwrap_or("").chars().take(80).collect(),
                _ => format!("stop={} ops={}", v.get("stopReason").and_then(|x| x.as_str()).unwrap_or("-"),
                              v.get("ops").and_then(|x| x.as_u64()).unwrap_or(0)),
            };
            eprintln!("[e2e] {t}: {brief}");
        }
    };

    // ── 阶段 1：PRD ──
    let r1 = agent::run_with_mode(
        &host, IDEA, None, &key, &model, &base, "auto", Some(&progress), 120, Some("prd"),
    )
    .await;
    let prd = r1.pointer("/docs/prd").and_then(|v| v.as_str()).unwrap_or("");
    eprintln!("[e2e] stage1: stop={} prd={} chars", r1["stopReason"], prd.chars().count());
    assert_eq!(r1["ok"], serde_json::json!(true), "阶段1 应成功: {r1}");
    assert_eq!(r1["stopReason"], serde_json::json!("done"));
    assert!(prd.chars().count() > 300, "PRD 太短，模型没真写文档（{} chars）", prd.chars().count());
    // 阶段隔离：文档阶段绝不能产出画布变更
    assert_eq!(r1["ops"], serde_json::json!([]), "文档阶段产生了 ops——隔离失效: {r1}");
    assert!(r1.get("mbt_b64").is_none(), "文档阶段不得返回文档本体");

    // ── 阶段 2：UI 设计文档 ──
    let ui_instr = format!("【已确认的 PRD】\n{prd}\n\n请据此产出 UI 设计文档。");
    let r2 = agent::run_with_mode(
        &host, &ui_instr, None, &key, &model, &base, "auto", Some(&progress), 120, Some("ui"),
    )
    .await;
    let ui = r2.pointer("/docs/ui").and_then(|v| v.as_str()).unwrap_or("");
    eprintln!("[e2e] stage2: stop={} ui={} chars", r2["stopReason"], ui.chars().count());
    assert_eq!(r2["ok"], serde_json::json!(true), "阶段2 应成功: {r2}");
    assert!(ui.chars().count() > 300, "UI 设计文档太短（{} chars）", ui.chars().count());
    assert_eq!(r2["ops"], serde_json::json!([]), "文档阶段产生了 ops: {r2}");

    // ── 阶段 3：按文档建画布 ──
    // 步数预算：五页高保真原型实测需要 ~250-400 步（每节点一次 place/update）。
    // 这里给 500（与前端默认 maxSteps 一致），避免把预算不足误判成能力缺陷。
    let build_instr = format!(
        "【PRD】\n{prd}\n\n【UI 设计文档（逐条落实）】\n{ui}\n\n请严格按上述文档建出完整可交互原型。"
    );
    let r3 = agent::run_with_mode(
        &host, &build_instr, None, &key, &model, &base, "auto", Some(&progress), 500, None,
    )
    .await;
    let ops = r3["ops"].as_array().map(|a| a.len()).unwrap_or(0);
    let stop = r3["stopReason"].as_str().unwrap_or("?");
    eprintln!("[e2e] stage3: stop={stop} ops={ops} boards={}", r3["boards"]);
    assert_eq!(r3["ok"], serde_json::json!(true), "阶段3 应成功: {r3}");
    assert!(ops > 3, "建画布阶段产出过少（{ops} ops）");
    let render = &r3["render"];
    assert!(render["artboards"].is_array(), "终态必须带可渲染画板");
    let boards = render["artboards"].as_array().map(|a| a.len()).unwrap_or(0);
    assert!(boards >= 2, "应产出多页原型，实际 {boards} 板");
    // 每条画板都要有真实 SVG（不是空壳）
    for ab in render["artboards"].as_array().unwrap() {
        let svg = ab.get("svg").and_then(|v| v.as_str()).unwrap_or("");
        assert!(svg.len() > 100, "画板 {} 的 SVG 为空", ab.get("id").and_then(|v| v.as_str()).unwrap_or("?"));
    }
    eprintln!("[e2e] ✅ 三阶段通过：PRD {} 字 · UI 文档 {} 字 · {boards} 画板 / {ops} ops", prd.chars().count(), ui.chars().count());
}
