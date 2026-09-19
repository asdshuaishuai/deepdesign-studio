//! node 子进程引擎宿主（cargo test 专用）。
//!
//! 生产引擎是 WebView 内的 wasm 实例，经 Tauri 事件桥调用（lib.rs）。
//! 测试没有 WebView：用 `node scripts/engine-host.mjs --once-file <临时文件>`
//! 驱动**同一份** frontend/vendor/moonviz.wasm，保证契约/端到端测试
//! 面对的是真引擎产物而非测试替身。
//!
//! 请求载荷写入临时文件——进程参数只有固定的程序名（node）、脚本路径与
//! 我们生成的临时文件路径，不携带任何文档内容；每次调用独立进程、无状态。
//! classic wasm 无 WasmGC 要求，任何现代 node 均可驱动。

/// 单发调用：返回 wasm 导出函数的结果对象。
/// 进程类失败（spawn/输出缺失，并行测试下 node 争抢的瞬态错误）重试一次；
/// 引擎返回的 JSON 错误不在此层——那是业务结果，原样透传不重试。
pub(super) async fn call(fn_name: &str, mbt: &str, op: &str) -> Result<serde_json::Value, String> {
    let first = call_once(fn_name, mbt, op).await;
    match first {
        Ok(v) => Ok(v),
        Err(e) if is_transport_error(&e) => {
            tokio::time::sleep(std::time::Duration::from_millis(300)).await;
            call_once(fn_name, mbt, op).await
        }
        Err(e) => Err(e),
    }
}

/// 仅进程/传输类错误重试：node 启动失败、无输出、超时。JSON 解析失败也可能是
/// 输出被截断的传输症状，一并重试；业务层错误（引擎返回的错误对象）不会走到这。
fn is_transport_error(e: &str) -> bool {
    e.starts_with("node_host_spawn_failed")
        || e.starts_with("node_host_no_output")
        || e.starts_with("node_host_bad_json")
        || e == "engine_timeout"
}

async fn call_once(fn_name: &str, mbt: &str, op: &str) -> Result<serde_json::Value, String> {
    let fn_name = fn_name.to_string();
    let mbt = mbt.to_string();
    let op = op.to_string();
    tokio::time::timeout(
        std::time::Duration::from_secs(30),
        tokio::task::spawn_blocking(move || call_sync(&fn_name, &mbt, &op)),
    )
    .await
    .map_err(|_| "engine_timeout".to_string())?
    .map_err(|e| format!("node_host_join:{e}"))?
}

fn call_sync(fn_name: &str, mbt: &str, op: &str) -> Result<serde_json::Value, String> {
    let script = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("scripts")
        .join("engine-host.mjs");
    if !script.is_file() {
        return Err("node_host_script_missing（scripts/engine-host.mjs）".into());
    }
    // 载荷落临时文件：fn/mbt/op 可能携带用户文本，绝不让它们出现在进程参数里
    let mut req_path = std::env::temp_dir();
    req_path.push(format!(
        "moonviz-req-{}-{}.json",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
    ));
    let request = serde_json::json!({ "id": 1, "fn": fn_name, "mbt": mbt, "op": op });
    // 载荷含用户文档全文——0600 落盘（默认 0644 会短驻泄露给本机其他用户；
    // 崩溃残留时同样受此保护，下次同进程 id 才可能覆盖）
    #[cfg(unix)]
    let write_req = || {
        use std::io::Write as _;
        use std::os::unix::fs::OpenOptionsExt as _;
        std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(&req_path)
            .and_then(|mut f| f.write_all(request.to_string().as_bytes()))
    };
    #[cfg(not(unix))]
    let write_req = || std::fs::write(&req_path, request.to_string());
    write_req().map_err(|e| format!("node_host_req_write:{e}"))?;
    let result = run_once(&script, &req_path);
    let _ = std::fs::remove_file(&req_path);
    result
}

fn run_once(
    script: &std::path::Path,
    req_path: &std::path::Path,
) -> Result<serde_json::Value, String> {
    let output = std::process::Command::new("node")
        .arg(script)
        .arg("--once-file")
        .arg(req_path)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .output()
        .map_err(|e| format!("node_host_spawn_failed:{e}（node 在 PATH？需要 ≥24）"))?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    let line = stdout
        .lines()
        .rev()
        .find(|l| l.trim_start().starts_with('{'))
        .ok_or_else(|| {
            format!(
                "node_host_no_output。stderr: {}",
                String::from_utf8_lossy(&output.stderr)
                    .chars()
                    .take(300)
                    .collect::<String>()
            )
        })?;
    let envelope: serde_json::Value =
        serde_json::from_str(line.trim()).map_err(|e| format!("node_host_bad_json:{e}"))?;
    if envelope.get("ok").and_then(|x| x.as_bool()) != Some(true) {
        return Err(envelope
            .get("error")
            .and_then(|x| x.as_str())
            .unwrap_or("node_host_error")
            .to_string());
    }
    let json = envelope
        .get("json")
        .and_then(|x| x.as_str())
        .unwrap_or("{}");
    serde_json::from_str(json).map_err(|e| format!("node_host_result_parse:{e}"))
}
