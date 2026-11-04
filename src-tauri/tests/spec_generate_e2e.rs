//! #24 规范驱动生成真机 e2e（环境变量门控，不进常规测试面）：
//!   SPEC_E2E=1 DD_BASE=... DD_KEY=... DD_MODEL=... \
//!     cargo test --test spec_generate_e2e -- --nocapture
//!
//! 验证真实模型遵守破坏性契约：**Agent 自己写设计规范 → 每次 generate 带 spec=**
//! （引擎侧无 spec 直接 design_spec_required 拒绝，genUI 首选通道依赖这条）。
//! 断言链：spec 由模型产出 → 生成结果采用 spec 主色 → 无纯黑背景/不可见组件。

use deepdesign_studio_lib::{agent, EngineHost};

const PROMPT: &str = r#"用一句话做原型：城市露营装备租赁小程序的登录页和首页（自然绿色调，主色 #2F6B4F，辅助米白 #F7F4EC）。

硬性要求：
- 先自己写出设计规范（紧凑 JSON：palette/typography/radius），之后**每次 generate 都带 spec=<同一份 JSON>**；
- 只做 2 个页面（登录页 login、首页 home），中文界面，移动端 390x844；
- 禁止纯黑/近黑背景与选中色；文字与背景对比度 ≥ 4.5；
- 圆角只用 0 / 8 / 12 / 16 或 高度÷2，禁止超大圆角（会渲染成极端椭圆）；
- 每个页面生成后 critique 一次，修掉真实偏差，然后收尾。"#;

#[tokio::test(flavor = "multi_thread")]
async fn spec_driven_generate_real_llm() {
    if std::env::var("SPEC_E2E").is_err() {
        eprintln!("跳过：设置 SPEC_E2E=1 与 DD_BASE/DD_KEY/DD_MODEL 后启用");
        return;
    }
    let base = std::env::var("DD_BASE").expect("DD_BASE");
    let key = std::env::var("DD_KEY").expect("DD_KEY");
    let model = std::env::var("DD_MODEL").unwrap_or_else(|_| "step-3.7-flash".into());
    let host = EngineHost;

    let events: std::sync::Mutex<Vec<serde_json::Value>> = std::sync::Mutex::new(Vec::new());
    let progress = |v: serde_json::Value| {
        if let Ok(mut ev) = events.lock() {
            ev.push(v.clone());
        }
        // 精简镜像：只打类型与关键字段（完整事件太多）
        let t = v.get("type").and_then(|x| x.as_str()).unwrap_or("?");
        match t {
            "tool_start" => eprintln!("[ev] tool_start {}", v.get("title").and_then(|x| x.as_str()).unwrap_or("")),
            "tool_end" => eprintln!(
                "[ev] tool_end ok={} {}",
                v.get("ok").and_then(|x| x.as_bool()).unwrap_or(false),
                v.get("title").and_then(|x| x.as_str()).unwrap_or("")
            ),
            "assistant_text" => eprintln!(
                "[ev] text {}",
                v.get("text").and_then(|x| x.as_str()).unwrap_or("").chars().take(120).collect::<String>()
            ),
            "done" | "failed" => eprintln!("[ev] {t} {}", v),
            _ => {}
        }
    };

    let started = std::time::Instant::now();
    let r = agent::run(&host, PROMPT, None, &key, &model, &base, "auto", Some(&progress)).await;
    eprintln!("[e2e] run finished in {:?}", started.elapsed());

    assert_eq!(r["ok"], serde_json::json!(true), "run 应成功：{r}");
    assert_eq!(r["stopReason"], serde_json::json!("done"), "应为正常收尾：{r}");

    let ops: Vec<String> = r["ops"]
        .as_array()
        .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_default();
    let gen_ops: Vec<&String> = ops.iter().filter(|o| o.starts_with("generate ")).collect();
    assert!(!gen_ops.is_empty(), "应使用 genUI 首选通道（generate），实际 ops={ops:?}");
    let with_spec: Vec<&&String> = gen_ops.iter().filter(|o| o.contains(" spec=")).collect();
    assert!(
        !with_spec.is_empty(),
        "#24 契约失败：没有一条 generate 带 spec=（模型未自己写规范）ops={gen_ops:?}"
    );

    // 从模型写的 spec 里取主色 → 生成结果必须真的用了它（规范驱动，而非引擎内置）
    let spec_op = with_spec.last().expect("just checked");
    let spec_str = spec_op.split(" spec=").nth(1).expect("spec= 之后是 JSON").trim();
    let spec: serde_json::Value = serde_json::from_str(spec_str)
        .unwrap_or_else(|e| panic!("模型写出的 spec 不是合法 JSON（{e}）：{spec_str}"));
    let primary = spec["palette"]["primary"]
        .as_str()
        .unwrap_or_else(|| panic!("spec 缺 palette.primary：{spec}"))
        .to_lowercase();
    assert_ne!(primary, "#000000", "主色不得是纯黑");

    use base64::Engine as _;
    let canon = String::from_utf8(
        base64::engine::general_purpose::STANDARD
            .decode(r["mbt_b64"].as_str().unwrap_or_default())
            .expect("mbt_b64 应可解码"),
    )
    .expect("canonical 是 UTF-8");
    assert!(
        canon.to_lowercase().contains(&primary),
        "生成结果未采用 spec 主色 {primary}——规范驱动未生效"
    );
    assert!(
        !canon.contains("fill=\"#000000\"") && !canon.contains("fill=\"#111111\""),
        "生成结果出现纯黑/近黑背景（#23 禁令）"
    );
    let boards = canon.matches("<!-- moonviz:artboard ").count();
    assert!(boards >= 2, "应产出 ≥2 页，实际 {boards}");

    // 逐板 critique：不得出现纯黑背景/不可见组件（#23 检测项）
    for b in ["login", "home"] {
        if !canon.contains(&format!("moonviz:artboard {b}")) {
            continue;
        }
        let c = host.call("session_critique", &canon, b).await.expect("critique 应可调用");
        let text = c.to_string();
        assert!(!text.contains("纯黑/近黑灰背景"), "{b} 出现纯黑背景：{text}");
        assert!(!text.contains("组件不可见"), "{b} 出现不可见组件：{text}");
        eprintln!(
            "[e2e] {b} critique norms: {}",
            c["data"]["results"]
                .as_array()
                .and_then(|a| a.iter().find(|x| x["principle"] == "norms"))
                .and_then(|x| x["advice"].as_str())
                .unwrap_or("-")
        );
    }

    eprintln!(
        "[e2e] ✅ #24 契约通过：{} 条 generate（{} 条带 spec）/ 主色 {primary} 已落地 / {boards} 板",
        gen_ops.len(),
        with_spec.len()
    );
}
