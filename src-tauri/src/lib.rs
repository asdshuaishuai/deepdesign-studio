//! deepDesign Studio: Tauri 2 桌面应用
//!
//! 架构：
//! - 前端 (纯静态): 多画板页签 + 拖拽画布 + 操作流 + Agent 控制台 + decl 视图
//! - 后端 (Rust): exec_cli（引擎进程）+ 加密 DDP 字节读写 + agent（进程内
//!   Agent 循环：OpenAI chat 兼容工具调用 × MoonViz AgentGate）
//!
//! 引擎 100% MoonBit 独立进程（stdin/stdout JSON 协议）。唯一事实源是
//! MoonBit `.mbt.md`；DDP 只是它的认证加密表示，Rust 不解释视觉语义。
//! Agent 基座 Rust 原生化后无 JS 运行时依赖（node/桥已删除）。

pub mod agent;
pub mod models;

use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use moonviz_ddp::{decrypt_ddp, encrypt_ddp};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use tauri::Manager;
use tauri_plugin_dialog::DialogExt;
use zeroize::Zeroizing;

/// 引擎 CLI 独立二进制定位（无回退——只走二进制产物，不依赖 moon 工具链）：
/// 1) MOONVIZ_CLI 环境变量 → 显式指定的二进制
/// 2) 内嵌引擎二进制（resources 里的 agent/moonviz-cli.exe，
///    由 moon build --release --target native cli 产出的自包含 CLI）
/// 3) dev 布局：兄弟 moonviz 仓库的 _build 产物
pub(crate) fn engine_cli_binary() -> Result<PathBuf, String> {
    if let Ok(cli) = std::env::var("MOONVIZ_CLI") {
        let p = PathBuf::from(&cli);
        if p.is_file() {
            return Ok(p);
        }
        return Err(format!("MOONVIZ_CLI={} 不是可执行文件", cli));
    }
    if let Ok(dir) = engine_bin_dir() {
        return Ok(dir.join("moonviz-cli.exe"));
    }
    let dev = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../moonviz/_build/native/release/build/cli/cli.exe");
    if dev.is_file() {
        return Ok(dev);
    }
    Err(
        "找不到 MoonViz 引擎二进制：内嵌 moonviz-cli.exe 缺失，且兄弟 moonviz 仓库无 \
         _build/native/release/build/cli/cli.exe。请先在引擎仓库执行 \
         `moon build --release --target native cli`，或设置 MOONVIZ_CLI。"
            .into(),
    )
}

/// 执行 MoonViz CLI 命令序列（stdin → stdout JSON 行）
#[tauri::command]
/// 用户组件库（宿主持久化侧）：默认 ~/.moonviz/components，可用 MOONVIZ_USER_LIB 覆盖。
fn user_lib_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("MOONVIZ_USER_LIB") {
        return PathBuf::from(dir);
    }
    PathBuf::from(home_dir()).join(".moonviz").join("components")
}

fn user_lib_b64s() -> Vec<String> {
    let dir = user_lib_dir();
    let mut out = Vec::new();
    if let Ok(entries) = std::fs::read_dir(&dir) {
        let mut paths: Vec<_> = entries.flatten().map(|e| e.path()).collect();
        paths.sort();
        for p in paths {
            if p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.ends_with(".mbt.md")) {
                if let Ok(bytes) = std::fs::read(&p) {
                    out.push(BASE64.encode(bytes));
                }
            }
        }
    }
    out
}

fn is_lib_mutating(cmd: &str) -> bool {
    let head = cmd.split_whitespace().next().unwrap_or("");
    matches!(
        head,
        "component-compile-b64" | "component-import" | "component-delete"
    )
}

/// 用同批 library-snapshot 结果全量重写本地库（幂等）。
fn write_user_lib(snap: &serde_json::Value) {
    let dir = user_lib_dir();
    let _ = std::fs::create_dir_all(&dir);
    let mut keep = std::collections::HashSet::new();
    if let Some(items) = snap.get("components").and_then(|c| c.as_array()) {
        for item in items {
            let cid = item.get("id").and_then(|v| v.as_str()).unwrap_or("");
            let src = item.get("source_b64").and_then(|v| v.as_str()).unwrap_or("");
            if cid.is_empty() || src.is_empty() || cid.contains('/') || cid.contains("..") {
                continue;
            }
            let name = format!("{cid}.mbt.md");
            // keep 先于写：decode/写失败时保留既有文件（瞬时故障不得删数据）
            keep.insert(name.clone());
            if let Ok(bytes) = BASE64.decode(src) {
                let _ = std::fs::write(dir.join(&name), bytes);
            }
        }
    }
    if let Ok(entries) = std::fs::read_dir(&dir) {
        for e in entries.flatten() {
            let p = e.path();
            if p.file_name().and_then(|x| x.to_str()).is_some_and(|n| n.ends_with(".mbt.md"))
                && !keep.contains(&p.file_name().unwrap_or_default().to_string_lossy().to_string())
            {
                let _ = std::fs::remove_file(p);
            }
        }
    }
}

#[tauri::command]
fn exec_cli(commands: Vec<String>) -> Result<Vec<serde_json::Value>, String> {
    exec_cli_pipeline(commands)
}

/// 引擎完整管道（用户组件库 restore/snapshot 写回）——画布命令与 Agent 工具共用。
pub(crate) fn exec_cli_pipeline(mut commands: Vec<String>) -> Result<Vec<serde_json::Value>, String> {
    // snapshot 与变更命令同进程：跨进程注入的 restore 只读磁盘旧库，
    // 首次注册会得到空快照（鸡生蛋）。
    let mutating = commands.iter().any(|c| is_lib_mutating(c));
    if mutating {
        commands.push("library-snapshot".to_string());
    }
    let result = exec_cli_inner(commands)?;
    if mutating {
        if let Some(snap) = result
            .iter()
            .find(|r| r.get("op").and_then(|v| v.as_str()) == Some("library-snapshot"))
        {
            write_user_lib(snap);
        }
    }
    Ok(result)
}

fn exec_cli_inner(mut commands: Vec<String>) -> Result<Vec<serde_json::Value>, String> {
    let lib = user_lib_b64s();
    if !lib.is_empty() {
        let mut restore = String::from("library-restore-b64");
        for b in &lib {
            restore.push(' ');
            restore.push_str(b);
        }
        commands.insert(0, restore);
    }
    let cli_bin = engine_cli_binary()?;
    let mut child = Command::new(&cli_bin)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| {
            format!(
                "启动 moonviz CLI 失败（{} 不可执行？）：{e}",
                cli_bin.display()
            )
        })?;

    {
        let stdin = child.stdin.as_mut().unwrap();
        for cmd in &commands {
            writeln!(stdin, "{cmd}").map_err(|e| format!("写入 stdin 失败：{e}"))?;
        }
        writeln!(stdin, "exit").ok();
    }

    let out = child
        .wait_with_output()
        .map_err(|e| format!("等待 CLI 退出失败：{e}"))?;

    let stdout = String::from_utf8_lossy(&out.stdout);
    let mut results = Vec::new();
    for line in stdout.lines() {
        let l = line.trim();
        if l.starts_with('{') || l.starts_with('[') {
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(l) {
                results.push(v);
            }
        }
    }
    if results.is_empty() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        return Err(format!(
            "CLI 无输出。stderr: {}",
            stderr.chars().take(400).collect::<String>()
        ));
    }
    Ok(results)
}

/// 保存唯一事实源：引擎交付 canonical MBT，Rust codec 输出不透明 `.ddp`。
#[tauri::command]
fn save_ddp(
    app: tauri::AppHandle,
    mbt_b64: String,
    password: String,
) -> Result<serde_json::Value, String> {
    let password = Zeroizing::new(password);
    let mbt_b64 = Zeroizing::new(mbt_b64);
    if mbt_b64.len() > 12 * 1024 * 1024 {
        return Err("ddp_mbt_too_large".into());
    }
    let mbt_bytes = Zeroizing::new(
        BASE64
            .decode(mbt_b64.as_bytes())
            .map_err(|_| "ddp_transport_invalid_base64".to_string())?,
    );
    let mbt = std::str::from_utf8(&mbt_bytes).map_err(|_| "ddp_mbt_not_utf8".to_string())?;
    let ddp = encrypt_ddp(mbt, &password)?;

    let path = app
        .dialog()
        .file()
        .add_filter("deepDesign 加密视觉文档", &["ddp"])
        .blocking_save_file()
        .map(|p| {
            let mut s = p.to_string();
            if !s.ends_with(".ddp") {
                s.push_str(".ddp");
            }
            PathBuf::from(s)
        })
        .ok_or("canceled")?;
    std::fs::write(&path, &ddp).map_err(|e| format!("ddp_write_failed:{e}"))?;
    Ok(serde_json::json!({
        "ok": true,
        "path": path.display().to_string(),
        "bytes": ddp.len(),
    }))
}

/// 打开不透明 DDP，并把解密后的 MBT 作为 Base64 传回给 Moonviz 引擎验证。
/// Rust 不解释 Markdown、MoonBit block 或视觉语义。
#[tauri::command]
fn open_ddp(app: tauri::AppHandle, password: String) -> Result<serde_json::Value, String> {
    let path = app
        .dialog()
        .file()
        .add_filter("deepDesign 加密视觉文档", &["ddp"])
        .blocking_pick_file()
        .ok_or("canceled")?;
    let pb = path
        .into_path()
        .map_err(|e| format!("ddp_path_invalid:{e}"))?;
    let password = Zeroizing::new(password);
    if std::fs::metadata(&pb).map_err(|e| e.to_string())?.len() > 16 * 1024 * 1024 + 45 {
        return Err("ddp_container_invalid".into());
    }
    let mut bytes = Vec::new();
    std::fs::File::open(&pb)
        .map_err(|e| format!("ddp_read_failed:{e}"))?
        .take(16 * 1024 * 1024 + 46)
        .read_to_end(&mut bytes)
        .map_err(|e| format!("ddp_read_failed:{e}"))?;
    let mbt = decrypt_ddp(&bytes, &password)?;
    Ok(serde_json::json!({
        "ok": true,
        "path": pb.display().to_string(),
        "mbt_b64": BASE64.encode(mbt.as_bytes()),
    }))
}

/// 内嵌引擎二进制所在目录（tauri resources 布局）：
/// 1) dev：编译清单目录的上一级（<deepDesign>/engine——CARGO_MANIFEST_DIR 是 src-tauri）
/// 2) 打包回退：从可执行文件向上逐级找 engine/moonviz-cli.exe
///    - Windows（NSIS）：resources 落在 exe 旁 → dir/engine 直接命中
///    - macOS（.app）：resources 落在 Contents/Resources/engine → 补查 dir/Resources/engine
fn engine_bin_dir() -> Result<PathBuf, String> {
    let dev = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("engine");
    if dev.join("moonviz-cli.exe").exists() {
        return Ok(dev);
    }
    if let Ok(exe) = std::env::current_exe() {
        let mut dir = exe.parent().map(|p| p.to_path_buf());
        for _ in 0..4 {
            if let Some(d) = dir {
                let cand = d.join("engine");
                if cand.join("moonviz-cli.exe").exists() {
                    return Ok(cand);
                }
                let res_cand = d.join("Resources").join("engine");
                if res_cand.join("moonviz-cli.exe").exists() {
                    return Ok(res_cand);
                }
                dir = d.parent().map(|p| p.to_path_buf());
            }
        }
    }
    Err("engine_bin_missing".into())
}

/// Agent 基座入口（进程内，无 JS 运行时）：
/// payload = { mode?:'models', instruction, mbt_b64?, api_key?, model?, base_url?, thinking_level? }
/// 返回契约与原 JS 桥一致：{ok, mbt_b64, render, ops[], stopReason, text} / models 列表。
#[tauri::command]
async fn invoke_fx_sdk(payload: String, api_key: String) -> Result<serde_json::Value, String> {
    let p: serde_json::Value =
        serde_json::from_str(&payload).map_err(|e| format!("fxsdk_payload_invalid:{e}"))?;
    let key = if !api_key.trim().is_empty() {
        api_key
    } else {
        // 三档：invoke 参数 > payload 字段 > 环境变量（设置面板文案承诺的回退）
        let from_payload = p.get("api_key").and_then(|v| v.as_str()).unwrap_or("");
        if !from_payload.trim().is_empty() {
            from_payload.to_string()
        } else {
            std::env::var("AI_GATEWAY_API_KEY").unwrap_or_default()
        }
    };
    if p.get("mode").and_then(|v| v.as_str()) == Some("models") {
        let base = p.get("base_url").and_then(|v| v.as_str()).unwrap_or("");
        return Ok(agent::list_models(base, &key).await);
    }
    let instruction = p.get("instruction").and_then(|v| v.as_str()).unwrap_or("");
    let mbt_b64 = p.get("mbt_b64").and_then(|v| v.as_str());
    let model = p.get("model").and_then(|v| v.as_str()).unwrap_or("");
    let base_url = p.get("base_url").and_then(|v| v.as_str()).unwrap_or("");
    let thinking = p.get("thinking_level").and_then(|v| v.as_str()).unwrap_or("auto");
    Ok(agent::run(instruction, mbt_b64, &key, model, base_url, thinking).await)
}

/// 模型元数据注册表（vendored models.dev 快照）下发给前端：
/// 设置面板据此展示可用模型、能力标签（tool_call/structured_output/上下文长度）
/// 与思考等级档位约束，无需运行时联网。
#[tauri::command]
fn model_registry() -> serde_json::Value {
    let map: serde_json::Map<String, serde_json::Value> = models::PRESET_PROVIDER_MAP
        .iter()
        .map(|(k, v)| ((*k).to_string(), serde_json::json!((*v))))
        .collect();
    serde_json::json!({
        "ok": true,
        "providers": models::snapshot_document().get("providers").cloned().unwrap_or(serde_json::json!({})),
        "provider_map": map,
        "fetched_at": models::snapshot_document().get("fetched_at").cloned().unwrap_or(serde_json::json!("")),
    })
}

/// 跨平台 home 目录：Windows 用 USERPROFILE，Unix 用 HOME。
fn home_dir() -> String {
    std::env::var("USERPROFILE")
        .or_else(|_| std::env::var("HOME"))
        .unwrap_or_default()
}

#[tauri::command]
fn diagnostics() -> serde_json::Value {
    let engine_bin = engine_cli_binary()
        .map(|p| p.display().to_string())
        .unwrap_or_default();
    serde_json::json!({
        "engine_cli": engine_bin,
        "version": env!("CARGO_PKG_VERSION"),
    })
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            exec_cli,
            invoke_fx_sdk,
            save_ddp,
            open_ddp,
            diagnostics,
            model_registry
        ])
        .setup(|app| {
            build_native_menus(app)?;
            Ok(())
        })
        .on_menu_event(|app, event| {
            // 原生菜单 → 前端动作桥：直接 eval 前端全局映射函数（比事件通道更直接）
            let id = event.id().as_ref().to_string();
            if let Some(win) = app.get_webview_window("main") {
                let _ = win.eval(format!(
                    "if(typeof nativeMenuAction==='function')nativeMenuAction({:?})",
                    id
                ));
            }
        })
        .on_page_load(|webview, payload| {
            // 资产协议无缓存头，WKWebView 可能滞留旧页：首载完成后强制带版本参数重载一次
            if payload.event() == tauri::webview::PageLoadEvent::Finished {
                webview.eval(
                    "if(!location.search)location.replace(location.href.split('?')[0]+'?v='+Date.now())",
                )
                .ok();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

/// 原生菜单栏（macOS 全局菜单）。菜单项只负责发事件，动作在前端执行，
/// 保持「引擎唯一事实源 + 壳只做具现化」的边界。
fn build_native_menus(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    use tauri::menu::{AboutMetadata, MenuBuilder, MenuItem, PredefinedMenuItem, SubmenuBuilder};

    let app_menu = SubmenuBuilder::new(app, "deepDesign Studio")
        .about(Some(AboutMetadata {
            name: Some("deepDesign Studio".into()),
            version: Some("0.3.0".into()),
            ..Default::default()
        }))
        .separator()
        .item(&MenuItem::with_id(
            app,
            "settings",
            "设置…",
            true,
            Some("CmdOrCtrl+Comma"),
        )?)
        .separator()
        .services()
        .separator()
        .hide()
        .hide_others()
        .show_all()
        .separator()
        .quit()
        .build()?;

    let file = SubmenuBuilder::new(app, "文件")
        .item(&MenuItem::with_id(
            app,
            "new-project",
            "新建项目…",
            true,
            Some("CmdOrCtrl+N"),
        )?)
        .item(&MenuItem::with_id(
            app,
            "open-ddp",
            "打开 DDP…",
            true,
            Some("CmdOrCtrl+O"),
        )?)
        .item(&MenuItem::with_id(
            app,
            "save",
            "保存（导出 DDP）…",
            true,
            Some("CmdOrCtrl+S"),
        )?)
        .separator()
        .item(&MenuItem::with_id(
            app,
            "export-ddp",
            "导出 DDP…",
            true,
            Some("CmdOrCtrl+Shift+E"),
        )?)
        .build()?;

    let edit = SubmenuBuilder::new(app, "编辑")
        .item(&PredefinedMenuItem::undo(app, Some("撤销"))?)
        .item(&PredefinedMenuItem::redo(app, Some("重做"))?)
        .separator()
        .item(&PredefinedMenuItem::cut(app, Some("剪切"))?)
        .item(&PredefinedMenuItem::copy(app, Some("复制"))?)
        .item(&PredefinedMenuItem::paste(app, Some("粘贴"))?)
        .item(&PredefinedMenuItem::select_all(app, Some("全选"))?)
        .build()?;

    let view = SubmenuBuilder::new(app, "视图")
        .item(&MenuItem::with_id(
            app,
            "view-wireframe",
            "线框图",
            true,
            Some("CmdOrCtrl+1"),
        )?)
        .item(&MenuItem::with_id(
            app,
            "view-hifi",
            "高保真",
            true,
            Some("CmdOrCtrl+2"),
        )?)
        .item(&MenuItem::with_id(
            app,
            "view-decl",
            "MBT 源码",
            true,
            Some("CmdOrCtrl+3"),
        )?)
        .item(&MenuItem::with_id(
            app,
            "view-play",
            "演示模式",
            true,
            Some("CmdOrCtrl+4"),
        )?)
        .separator()
        .item(&MenuItem::with_id(
            app,
            "view-fit",
            "适配窗口",
            true,
            Some("CmdOrCtrl+0"),
        )?)
        .build()?;

    let board = SubmenuBuilder::new(app, "画板")
        .item(&MenuItem::with_id(
            app,
            "board-new",
            "新建画板",
            true,
            Some("CmdOrCtrl+Shift+N"),
        )?)
        .item(&MenuItem::with_id(
            app,
            "board-dup",
            "复制当前画板",
            true,
            Some("CmdOrCtrl+Shift+D"),
        )?)
        .separator()
        .item(&MenuItem::with_id(
            app,
            "autofix",
            "自动修复（引擎还债）",
            true,
            Some("CmdOrCtrl+Shift+F"),
        )?)
        .separator()
        .item(&MenuItem::with_id(
            app,
            "validate",
            "校验并渲染（AgentGate）",
            true,
            None::<&str>,
        )?)
        .build()?;

    let help = SubmenuBuilder::new(app, "帮助")
        .item(&MenuItem::with_id(
            app,
            "shortcuts",
            "快捷键与菜单说明",
            true,
            Some("CmdOrCtrl+/"),
        )?)
        .build()?;

    let menu = MenuBuilder::new(app)
        .items(&[&app_menu, &file, &edit, &view, &board, &help])
        .build()?;
    app.set_menu(menu)?;
    Ok(())
}
