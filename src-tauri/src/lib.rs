//! deepDesign Studio: Tauri 2 桌面应用
//!
//! 架构：
//! - 前端 (纯静态): 多画板页签 + 拖拽画布 + 操作流 + Agent 控制台 + decl 视图
//! - 后端 (Rust): exec_cli（引擎进程）+ 加密 DDP 字节读写
//!
//! 引擎 100% MoonBit 独立进程（stdin/stdout JSON 协议）。唯一事实源是
//! MoonBit `.mbt.md`；DDP 只是它的认证加密表示，Rust 不解释视觉语义。

use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use moonviz_ddp::{decrypt_ddp, encrypt_ddp};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use tauri::Manager;
use tauri_plugin_dialog::DialogExt;
use zeroize::Zeroizing;

/// 定位 MoonViz 引擎目录（含 cli/ 包的 moon 仓库）。
fn find_moonviz_dir() -> Result<PathBuf, String> {
    // 引擎 cli 包配置可能是 moon.pkg.json（旧）或 moon.pkg（KDL，moon fmt 新格式）
    fn is_engine_dir(dir: &PathBuf) -> bool {
        dir.join("cli").join("moon.pkg.json").exists() || dir.join("cli").join("moon.pkg").exists()
    }
    if let Ok(dir) = std::env::var("MOONVIZ_DIR") {
        let p = PathBuf::from(&dir);
        if is_engine_dir(&p) {
            return Ok(p);
        }
        return Err(format!("MOONVIZ_DIR={} 不含 cli 包", dir));
    }
    if let Ok(exe) = std::env::current_exe() {
        let mut cur = exe.parent().map(|p| p.to_path_buf());
        while let Some(dir) = cur {
            if is_engine_dir(&dir) {
                return Ok(dir);
            }
            cur = dir.parent().map(|p| p.to_path_buf());
        }
    }
    let dev = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../moonviz");
    if is_engine_dir(&dev) {
        return Ok(dev.canonicalize().unwrap_or(dev));
    }
    Err("找不到 MoonViz 引擎目录：请设置 MOONVIZ_DIR".into())
}

/// 执行 MoonViz CLI 命令序列（stdin → stdout JSON 行）
#[tauri::command]
/// 用户组件库（宿主持久化侧）：默认 ~/.moonviz/components，可用 MOONVIZ_USER_LIB 覆盖。
fn user_lib_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("MOONVIZ_USER_LIB") {
        return PathBuf::from(dir);
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    PathBuf::from(home).join(".moonviz").join("components")
}

fn user_lib_b64s() -> Vec<String> {
    let dir = user_lib_dir();
    let mut out = Vec::new();
    if let Ok(entries) = std::fs::read_dir(&dir) {
        let mut paths: Vec<_> = entries.flatten().map(|e| e.path()).collect();
        paths.sort();
        for p in paths {
            if p.file_name().and_then(|n| n.to_str()).map_or(false, |n| n.ends_with(".mbt.md")) {
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
            if p.file_name().and_then(|x| x.to_str()).map_or(false, |n| n.ends_with(".mbt.md"))
                && !keep.contains(&p.file_name().unwrap_or_default().to_string_lossy().to_string())
            {
                let _ = std::fs::remove_file(p);
            }
        }
    }
}

#[tauri::command]
fn exec_cli(mut commands: Vec<String>) -> Result<Vec<serde_json::Value>, String> {
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
    let dir = find_moonviz_dir()?;
    let moon = {
        let m = which_moon();
        if m.is_empty() {
            return Err(
                "找不到 moon 命令——请确认 MoonBit 工具链已安装，或在 shell 中启动应用".into(),
            );
        }
        m
    };
    let mut child = Command::new(&moon)
        .args(["run", "--target", "native", "cli"])
        .current_dir(&dir)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("启动 moonviz CLI 失败（moon 不在 PATH？）：{e}"))?;

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

/// 调用用户指定的 fx Agent 基座；fx 负责模型/Provider/会话，MoonViz 负责执行和校验返回的操作。
#[tauri::command]
fn invoke_fx(prompt: String, fx_path: String, cwd: String) -> Result<String, String> {
    let binary = if fx_path.trim().is_empty() {
        "fx"
    } else {
        fx_path.trim()
    };
    let working_dir = if cwd.trim().is_empty() {
        find_moonviz_dir()?
    } else {
        PathBuf::from(cwd.trim())
    };
    let output = Command::new(binary)
        .args(["ask", "--no-save", &prompt])
        .current_dir(&working_dir)
        .output()
        .map_err(|e| format!("fx_unavailable:{e}"))?;
    if !output.status.success() {
        return Err(format!(
            "fx_failed:{}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// Tauri 端 fx SDK 桥：与 server.py 的 /api/fx/agent 等价，通过 node 运行
/// agent/fx-agent.mjs（libfx 嵌入），fx 的每次工具调用都在桥内经
/// MoonViz AgentGate 并返回 canonical MBT。Rust 只传输 JSON 字节。
/// 定位 fx-agent.mjs 所在的 agent 目录：
/// 1) dev：编译清单目录的上一级（<deepDesign>/agent——CARGO_MANIFEST_DIR 是 src-tauri）
/// 2) 打包回退：从可执行文件向上逐级找 agent/fx-agent.mjs（extraResources 布局）
fn fx_agent_root() -> Result<PathBuf, String> {
    let dev = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..").join("agent");
    if dev.join("fx-agent.mjs").exists() {
        return Ok(dev);
    }
    if let Ok(exe) = std::env::current_exe() {
        let mut dir = exe.parent().map(|p| p.to_path_buf());
        for _ in 0..4 {
            if let Some(d) = dir {
                let cand = d.join("agent");
                if cand.join("fx-agent.mjs").exists() {
                    return Ok(cand);
                }
                dir = d.parent().map(|p| p.to_path_buf());
            }
        }
    }
    Err("fxsdk_bridge_missing".into())
}

#[tauri::command]
fn invoke_fx_sdk(payload: String, api_key: String) -> Result<serde_json::Value, String> {
    let app_root = fx_agent_root()?;
    let bridge = app_root.join("fx-agent.mjs");
    let node = which_node().ok_or("node_unavailable")?;
    let mut env: Vec<(String, String)> = std::env::vars().collect();
    if !api_key.trim().is_empty() {
        env.retain(|(k, _)| k != "AI_GATEWAY_API_KEY");
        env.push(("AI_GATEWAY_API_KEY".to_string(), api_key));
    }
    let mut child = Command::new(&node)
        .arg(&bridge)
        .current_dir(&app_root)
        .envs(env)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("fxsdk_spawn_failed:{e}"))?;
    if let Some(stdin) = child.stdin.as_mut() {
        stdin
            .write_all(payload.as_bytes())
            .map_err(|e| format!("fxsdk_write_failed:{e}"))?;
    }
    let output = child
        .wait_with_output()
        .map_err(|e| format!("fxsdk_wait_failed:{e}"))?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    match serde_json::from_str::<serde_json::Value>(stdout.trim()) {
        Ok(value) if value.is_object() => Ok(value),
        _ => Err(format!(
            "fxsdk_bridge_failed:{}",
            String::from_utf8_lossy(&output.stderr).trim()
        )),
    }
}

/// Locate a usable node binary for the fx SDK bridge.
fn which_node() -> Option<String> {
    if let Ok(path) = std::env::var("PATH") {
        for dir in path.split(':') {
            let p = PathBuf::from(dir).join("node");
            if p.exists() {
                return Some(p.display().to_string());
            }
        }
    }
    let home = std::env::var("HOME").unwrap_or_default();
    for p in [
        format!("{home}/.volta/bin/node"),
        "/opt/homebrew/bin/node".into(),
        "/usr/local/bin/node".into(),
    ] {
        let p = PathBuf::from(p);
        if p.exists() {
            return Some(p.display().to_string());
        }
    }
    None
}

#[tauri::command]
fn diagnostics() -> serde_json::Value {
    let engine = find_moonviz_dir()
        .map(|p| p.display().to_string())
        .unwrap_or_default();
    let moon = which_moon();
    serde_json::json!({
        "engine_dir": engine,
        "moon": moon,
        "version": env!("CARGO_PKG_VERSION"),
    })
}

fn which_moon() -> String {
    if let Ok(path) = std::env::var("PATH") {
        for dir in path.split(':') {
            let p = PathBuf::from(dir).join("moon");
            if p.exists() {
                return p.display().to_string();
            }
        }
    }
    // GUI 启动的 app 继承的 PATH 不含用户 shell 的 bin——探测常见位置
    let home = std::env::var("HOME").unwrap_or_default();
    for p in [
        format!("{home}/.cargo/bin/moon"),
        format!("{home}/.moon/bin/moon"),
        "/opt/homebrew/bin/moon".into(),
        "/usr/local/bin/moon".into(),
    ] {
        let p = PathBuf::from(p);
        if p.exists() {
            return p.display().to_string();
        }
    }
    // login shell 取真实 PATH（兜底）
    if let Ok(out) = Command::new("sh")
        .args(["-lc", "which moon 2>/dev/null"])
        .output()
    {
        let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if !s.is_empty() {
            return s;
        }
    }
    String::new()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            exec_cli,
            invoke_fx,
            invoke_fx_sdk,
            save_ddp,
            open_ddp,
            diagnostics
        ])
        .setup(|app| {
            build_native_menus(app)?;
            Ok(())
        })
        .on_menu_event(|app, event| {
            // 原生菜单 → 前端动作桥：直接 eval 前端全局映射函数（比事件通道更直接）
            let id = event.id().as_ref().to_string();
            if let Some(win) = app.get_webview_window("main") {
                let _ = win.eval(&format!(
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
