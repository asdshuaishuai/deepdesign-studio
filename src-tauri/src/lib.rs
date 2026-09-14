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

/// 引擎 CLI 独立二进制定位（无回退——只走二进制产物，不依赖 moon 工具链）：
/// 1) MOONVIZ_CLI 环境变量 → 显式指定的二进制
/// 2) 内嵌引擎二进制（resources 里的 agent/moonviz-cli.exe，
///    由 moon build --release --target native cli 产出的自包含 CLI）
/// 3) dev 布局：兄弟 moonviz 仓库的 _build 产物
fn engine_cli_binary() -> Result<PathBuf, String> {
    if let Ok(cli) = std::env::var("MOONVIZ_CLI") {
        let p = PathBuf::from(&cli);
        if p.is_file() {
            return Ok(p);
        }
        return Err(format!("MOONVIZ_CLI={} 不是可执行文件", cli));
    }
    if let Ok(agent) = fx_agent_root() {
        let bundled = agent.join("moonviz-cli.exe");
        if bundled.is_file() {
            return Ok(bundled);
        }
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

/// Tauri 端 fx SDK 桥：与 server.py 的 /api/fx/agent 等价，通过 node 运行
/// agent/agent-bridge.mjs（@open-agent-loops/core 桥），fx 的每次工具调用都在桥内经
/// MoonViz AgentGate 校验并写回 canonical MBT。Rust 只传输 JSON 字节。
/// 定位 agent-bridge.mjs 所在的 agent 目录：
/// 1) dev：编译清单目录的上一级（<deepDesign>/agent——CARGO_MANIFEST_DIR 是 src-tauri）
/// 2) 打包回退：从可执行文件向上逐级找 agent/agent-bridge.mjs
///    - Windows（NSIS）：resources 落在 exe 旁 → dir/agent 直接命中
///    - macOS（.app）：resources 落在 Contents/Resources/agent → 补查 dir/Resources/agent
fn fx_agent_root() -> Result<PathBuf, String> {
    let dev = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("agent");
    if dev.join("agent-bridge.mjs").exists() {
        return Ok(dev);
    }
    if let Ok(exe) = std::env::current_exe() {
        let mut dir = exe.parent().map(|p| p.to_path_buf());
        for _ in 0..4 {
            if let Some(d) = dir {
                let cand = d.join("agent");
                if cand.join("agent-bridge.mjs").exists() {
                    return Ok(cand);
                }
                let res_cand = d.join("Resources").join("agent");
                if res_cand.join("agent-bridge.mjs").exists() {
                    return Ok(res_cand);
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
    let bridge = app_root.join("agent-bridge.mjs");
    let node = which_node().ok_or("node_unavailable")?;
    let mut env: Vec<(String, String)> = std::env::vars().collect();
    if !api_key.trim().is_empty() {
        env.retain(|(k, _)| k != "AI_GATEWAY_API_KEY");
        env.push(("AI_GATEWAY_API_KEY".to_string(), api_key));
    }
    // 桥与画布共用同一引擎调用：内嵌二进制存在时让桥直接 spawn 它
    // （独立二进制无需引擎源码目录与 moon 工具链）。
    if std::env::var("MOONVIZ_CLI").is_err() {
        if let Ok(agent) = fx_agent_root() {
            let bundled = agent.join("moonviz-cli.exe");
            if bundled.is_file() {
                env.retain(|(k, _)| k != "MOONVIZ_CLI");
                env.push(("MOONVIZ_CLI".to_string(), bundled.display().to_string()));
            }
        }
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
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(payload.as_bytes())
            .map_err(|e| format!("fxsdk_write_failed:{e}"))?;
        // 显式关闭 stdin：桥的 readStdin() 依赖 EOF 才会开始执行
        drop(stdin);
    }
    let output = wait_child_output(child, std::time::Duration::from_secs(300))?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    match serde_json::from_str::<serde_json::Value>(stdout.trim()) {
        Ok(value) if value.is_object() => Ok(value),
        _ => Err(format!(
            "fxsdk_bridge_failed:{}",
            String::from_utf8_lossy(&output.stderr).trim()
        )),
    }
}

/// 带超时的 wait_with_output：管道由后台线程读取（避免子进程写满管道死锁），
/// 主循环轮询 try_wait，超时 kill。原版 wait_with_output 无界等待，
/// 桥内 maxSteps×每步 LLM+CLI 可能长时间运行。
fn wait_child_output(
    mut child: std::process::Child,
    timeout: std::time::Duration,
) -> Result<std::process::Output, String> {
    let mut stdout_pipe = child.stdout.take();
    let mut stderr_pipe = child.stderr.take();
    let out_handle = std::thread::spawn(move || {
        let mut buf = Vec::new();
        if let Some(p) = stdout_pipe.as_mut() {
            let _ = p.read_to_end(&mut buf);
        }
        buf
    });
    let err_handle = std::thread::spawn(move || {
        let mut buf = Vec::new();
        if let Some(p) = stderr_pipe.as_mut() {
            let _ = p.read_to_end(&mut buf);
        }
        buf
    });
    let deadline = std::time::Instant::now() + timeout;
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let stdout = out_handle.join().unwrap_or_default();
                let stderr = err_handle.join().unwrap_or_default();
                return Ok(std::process::Output {
                    status,
                    stdout,
                    stderr,
                });
            }
            Ok(None) => {
                if std::time::Instant::now() >= deadline {
                    let _ = child.kill();
                    let _ = out_handle.join();
                    let _ = err_handle.join();
                    return Err("fxsdk_timeout".into());
                }
                std::thread::sleep(std::time::Duration::from_millis(100));
            }
            Err(e) => return Err(format!("fxsdk_wait_failed:{e}")),
        }
    }
}

/// 跨平台 home 目录：Windows 用 USERPROFILE，Unix 用 HOME。
fn home_dir() -> String {
    std::env::var("USERPROFILE")
        .or_else(|_| std::env::var("HOME"))
        .unwrap_or_default()
}

/// 在 PATH 中查找可执行文件（split_paths 处理 Unix ':' 与 Windows ';'，Windows 自动补 .exe）。
fn find_in_path(name: &str) -> Option<String> {
    let exe = if cfg!(windows) {
        format!("{name}.exe")
    } else {
        name.to_string()
    };
    let path = std::env::var_os("PATH")?;
    for dir in std::env::split_paths(&path) {
        let p = dir.join(&exe);
        if p.is_file() {
            return Some(p.display().to_string());
        }
    }
    None
}

/// Locate a usable node binary for the fx SDK bridge.
fn which_node() -> Option<String> {
    if let Some(p) = find_in_path("node") {
        return Some(p);
    }
    // GUI 启动的 app 继承的 PATH 可能不含用户 shell 的 bin——探测常见安装位置
    let home = home_dir();
    #[cfg(windows)]
    let candidates: Vec<PathBuf> = {
        let program_files =
            std::env::var("ProgramFiles").unwrap_or_else(|_| r"C:\Program Files".into());
        vec![
            PathBuf::from(program_files).join("nodejs").join("node.exe"),
            PathBuf::from(&home)
                .join("scoop")
                .join("apps")
                .join("nodejs")
                .join("current")
                .join("node.exe"),
        ]
    };
    #[cfg(not(windows))]
    let candidates: Vec<PathBuf> = vec![
        PathBuf::from(&home).join(".volta").join("bin").join("node"),
        PathBuf::from("/opt/homebrew/bin/node"),
        PathBuf::from("/usr/local/bin/node"),
    ];
    candidates
        .into_iter()
        .find(|p| p.is_file())
        .map(|p| p.display().to_string())
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
