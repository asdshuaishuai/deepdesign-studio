//! 无头演示桥用的真实 agent 运行器（无 Tauri 壳）：
//!   echo '{"instruction":"...","key":"...","model":"...","base":"..."}' \
//!     | cargo run --example demo_agent
//!
//! 与桌面端同一条链路：agent::run_with_mode + EngineHost（wasmtime 进程内引擎）
//! + OpenAI 兼容 LLM。stdout 协议：
//!   EVT <json>      进度事件（与 agent-event 同形状；run id 由桥注入）
//!   RESULT <json>   终态信封（{ok, mbt_b64, render, ops, stopReason, text, ...}）
//! 仅用于演示视频录制；不进产品构建。

use deepdesign_studio_lib::{agent, EngineHost};
use std::io::Read;

#[tokio::main]
async fn main() {
    let mut raw = String::new();
    std::io::stdin()
        .read_to_string(&mut raw)
        .expect("stdin 读取失败");
    let req: serde_json::Value =
        serde_json::from_str(&raw).expect("请求 JSON 解析失败（{instruction,mbt_b64?,key,model,base,thinking?,max_steps?,mode?}）");

    eprintln!("[demo_agent] mode={:?} max_steps_arg={:?} mbt_bytes={}", req["mode"], req["max_steps"], req["mbt_b64"].as_str().map(|m| m.len()).unwrap_or(0));

    let progress = |v: serde_json::Value| {
        // 单行 JSON；桥按行拆分并转发 SSE（agent-event）
        println!("EVT {v}");
    };

    let result = agent::run_with_mode(
        &EngineHost,
        req["instruction"].as_str().unwrap_or(""),
        req["mbt_b64"].as_str(),
        req["key"].as_str().unwrap_or(""),
        req["model"].as_str().unwrap_or(""),
        req["base"].as_str().unwrap_or(""),
        req["thinking"].as_str().unwrap_or("auto"),
        Some(&progress),
        req["max_steps"].as_u64().unwrap_or(500) as usize,
        req["mode"].as_str(),
        None,
    )
    .await;

    println!("RESULT {result}");
}
