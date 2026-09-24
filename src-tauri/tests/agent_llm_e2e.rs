//! 真实 LLM 端到端测试（环境变量门控，不进常规测试面）：
//!   CAMPING_E2E=1 DD_BASE=... DD_KEY=... DD_MODEL=... cargo test --test agent_llm_e2e -- --nocapture
//! 用持久化的 MiniMax Anthropic 端点驱动 agent::run 跑完整露营需求，
//! 事件流落 /tmp/camping-journal.jsonl，stdout 同步镜像。

use deepdesign_studio_lib::{agent, EngineHost};

const CAMPING_PROMPT: &str = r#"请根据以下需求，生成一个“城市露营装备租赁”移动端小程序的高保真可交互原型。要求范围克制，但核心流程完整。

【产品定位】面向城市年轻人的轻露营装备租赁小程序，解决临时露营装备购买贵、使用频率低、闲置浪费的问题。
【目标用户】20-35 岁城市上班族、露营新手，周末短途露营，预算有限，重视便捷和颜值。
【核心流程】首页浏览 -> 分类/搜索 -> 装备详情 -> 选择租期和数量 -> 确认订单 -> 订单详情。
【页面范围】只做 5 个页面，不要扩展登录、支付、后台管理等额外模块：
1. 首页：定位、搜索框、分类入口、热门装备卡片、底部导航。
2. 分类/搜索页：关键词搜索、分类筛选、装备列表。
3. 装备详情页：装备图片、名称、日租金、押金、规格参数、租期选择、数量选择、立即租赁按钮。
4. 确认订单页：装备摘要、租期、取还方式、联系人、费用明细、提交订单。
5. 订单详情页：订单状态、装备信息、取还时间地点、费用明细、联系客服。
【交互要求】页面之间可点击跳转。租期、数量可切换，并实时更新价格。提交订单后进入订单详情页。至少包含加载状态、空状态、错误提示各一处。按钮需有默认、点击、禁用状态。使用 mock 数据，至少 6 件装备、3 个分类。
【视觉风格】户外自然风，主色深绿 #2F6B4F，辅助米白 #F7F4EC、橙色 #E67E22。圆角卡片、轻阴影、简洁图标，整体清爽但不花哨。移动端尺寸 375x812，中文界面。
【输出要求】先给出简要信息架构和页面流，再逐页生成可交互原型。"#;

#[tokio::test(flavor = "multi_thread")]
async fn camping_real_llm_e2e() {
    if std::env::var("CAMPING_E2E").is_err() {
        eprintln!("跳过：设置 CAMPING_E2E=1 与 DD_BASE/DD_KEY/DD_MODEL 后启用");
        return;
    }
    let base = std::env::var("DD_BASE").expect("DD_BASE");
    let key = std::env::var("DD_KEY").expect("DD_KEY");
    let model = std::env::var("DD_MODEL").unwrap_or_else(|_| "MiniMax-M3".into());

    let host = EngineHost;
    let started = std::time::Instant::now();
    let journal = std::sync::Mutex::new(std::io::BufWriter::new(
        std::fs::File::create("/tmp/camping-journal.jsonl").unwrap(),
    ));
    let progress = |mut v: serde_json::Value| {
        if let Some(o) = v.as_object_mut() {
            o.insert(
                "ts".into(),
                serde_json::json!(std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_millis())
                    .unwrap_or(0)),
            );
        }
        eprintln!("[agent] {}", v);
        if let Ok(mut w) = journal.lock() {
            use std::io::Write as _;
            let _ = writeln!(w, "{v}");
            let _ = w.flush();
        }
    };

    let mut mbt: Option<String> = None;
    let mut instruction = CAMPING_PROMPT.to_string();
    for round in 1..=6 {
        let round_start = std::time::Instant::now();
        let result = agent::run(
            &host,
            &instruction,
            mbt.as_deref(),
            &key,
            &model,
            &base,
            "auto",
            Some(&progress),
        )
        .await;
        let ops = result.get("ops").and_then(|v| v.as_array()).map(|a| a.len()).unwrap_or(0);
        let stop = result.get("stopReason").and_then(|v| v.as_str()).unwrap_or("?").to_string();
        eprintln!(
            "[e2e] round {round} in {:?}: stop={stop} ops={ops} (累计上限 4 轮)",
            round_start.elapsed()
        );
        if result.get("ok").and_then(|v| v.as_bool()) != Some(true) {
            eprintln!("[e2e] round {round} 失败，停止续跑");
            break;
        }
        mbt = result
            .get("mbt_b64")
            .and_then(|v| v.as_str())
            .map(String::from)
            .or(mbt);
        if stop != "max_turns" {
            eprintln!("[e2e] round {round} 模型报告完成（stop={stop}）");
            break;
        }
        instruction = format!(
            "{CAMPING_PROMPT}\n\n[续跑说明] 以上需求你已完成一部分（见当前文档）。\
             请先 read_mbt 盘点已有页面与节点，然后直接继续完成剩余页面与交互\
             （目标是全部 5 个页面：home/search/detail/order/order_detail，\
             6 件露营装备 mock 数据、3 个分类、全部核心跳转），\
             不要提问、不要复述计划，完成后给出简要总结。"
        );
    }
    let final_doc = mbt.unwrap_or_default();
    eprintln!(
        "[e2e] 最终文档 {} bytes，画板数≈{}",
        final_doc.len(),
        final_doc.matches("moonviz:artboard").count()
    );
    let ops_total = 0;
    let _ = ops_total;
    assert!(!final_doc.is_empty(), "真实 LLM run 未产出任何文档");
}
