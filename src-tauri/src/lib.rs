//! deepDesign Studio: Tauri 2 桌面应用
//!
//! 架构：
//! - 前端 (纯静态): 多画板页签 + 拖拽画布 + **内嵌 wasm 引擎**（classic 标准产物，
//!   WebView 内进程执行，画布实时编辑）+ Agent 控制台 + decl 视图
//! - 后端 (Rust): DDP 加解密（vendored moonviz-ddp）+ **wasmtime 进程内引擎宿主**
//!   （agent 循环 × 同一份 wasm 产物，纯 Rust 运行时——无 node、无子进程、
//!   无 WebView 往返）+ agent（OpenAI/Anthropic 工具调用）
//!
//! 引擎是 MoonViz 的标准 classic wasm 产物（frontend/vendor/moonviz.wasm，
//! sync-engine.mjs 从 GitHub Releases 拉取 + sha512 + 契约探针，编译期嵌入 Rust、
//! 运行期被前端 fetch 实例化——同一份字节，两个宿主）。唯一事实源是 `.mbt.md`；
//! DDP 只是它的认证加密表示，Rust 不解释视觉语义。无引擎子进程、无 JS 运行时。

pub mod agent;
pub mod models;
mod wasmtime_host;

pub use wasmtime_host::EngineHost;

use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use moonviz_ddp::{decrypt_ddp, encrypt_ddp};
use std::io::Read;
use std::path::PathBuf;
use tauri::Manager;
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
use zeroize::Zeroizing;

/// 保存唯一事实源：引擎交付 canonical MBT，Rust codec 输出不透明 `.ddp`。
/// async 命令（跑在 tokio worker）：blocking_* 对话框禁止在主线程调用
/// （同步命令在 macOS WKWebView IPC 回调 = 主线程内联执行，sheet 会冻结）。
#[tauri::command]
async fn save_ddp(
    app: tauri::AppHandle,
    mbt_b64: String,
    password: String,
    path: Option<String>, // 原地保存路径（前端已有 filePath 时传入，跳过对话框）；空/缺省回落对话框
    filter_label: Option<String>,
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

    let via_dialog = path.as_deref().map(|p| p.trim().is_empty()).unwrap_or(true);
    let picked: Option<PathBuf> = match path {
        Some(p) if !p.trim().is_empty() => Some(PathBuf::from(p.trim().to_string())),
        _ => app
            .dialog()
            .file()
            .add_filter(filter_label.as_deref().unwrap_or("deepDesign 视觉文档"), &["ddp"])
            .blocking_save_file()
            .map(|p| {
                let mut s = p.to_string();
                if !s.to_lowercase().ends_with(".ddp") {
                    s.push_str(".ddp");
                }
                PathBuf::from(s)
            }),
    };
    let Some(path) = picked else {
        // 用户取消：Ok(Null) 而非 Err——Err 会 reject 前端 promise 落进 catch 弹「失败」toast
        return Ok(serde_json::Value::Null);
    };
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
async fn open_ddp(
    app: tauri::AppHandle,
    password: String,
    path: Option<String>,
    filter_label: Option<String>,
) -> Result<serde_json::Value, String> {
    let via_dialog = path.as_deref().map(|p| p.trim().is_empty()).unwrap_or(true);
    let picked: Option<PathBuf> = match path {
        Some(p) if !p.trim().is_empty() => Some(PathBuf::from(p.trim().to_string())),
        _ => app
            .dialog()
            .file()
            .add_filter(filter_label.as_deref().unwrap_or("deepDesign 视觉文档"), &["ddp"])
            .blocking_pick_file()
            .and_then(|fp| fp.into_path().ok()),
    };
    let Some(pb) = picked else {
        return Ok(serde_json::Value::Null); // 用户取消，见 save_ddp 注释
    };
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
    let mbt = match decrypt_ddp(&bytes, &password) {
        Ok(m) => m,
        // 口令不符不整单失败：把选中的路径带回，前端据此弹口令框重试——
        // 「先选文件、再按需问密码」；错密码与篡改同报错（无预言机），前端重试一轮即止
        Err(_) if via_dialog => {
            return Ok(serde_json::json!({
                "need_password": true,
                "path": pb.display().to_string(),
            }))
        }
        Err(e) => return Err(e),
    };
    Ok(serde_json::json!({
        "ok": true,
        "path": pb.display().to_string(),
        "mbt_b64": BASE64.encode(mbt.as_bytes()),
    }))
}

/// 扫描工作区目录中的 .ddp 项目文件，返回元数据列表（多项目切换器数据源）。
/// 目录不存在/不可读必须报错而非返回空表——前端用扫描结果对账最近项目，
/// 静默空表会把「移动盘未挂载」洗成「项目全没了」并落盘清空注册表。
#[tauri::command]
fn list_ddp_projects(dir: String) -> Result<serde_json::Value, String> {
    let dir_path = PathBuf::from(dir.trim());
    if !dir_path.is_dir() {
        return Err(format!("dir_not_found:{}", dir_path.display()));
    }
    let mut projects = Vec::new();
    let entries = std::fs::read_dir(&dir_path)
        .map_err(|e| format!("dir_read_failed:{}:{e}", dir_path.display()))?;
    for entry in entries.filter_map(|e| e.ok()) {
        let p = entry.path();
        if p.extension().map(|x| x == "ddp").unwrap_or(false) {
            let meta = entry.metadata().ok();
            projects.push(serde_json::json!({
                "file": p.file_name().unwrap_or_default().to_string_lossy(),
                "path": p.display().to_string(),
                "size": meta.as_ref().map(|m| m.len()).unwrap_or(0),
                "modified": meta.as_ref().and_then(|m| m.modified().ok())
                    .map(|t| t.duration_since(std::time::UNIX_EPOCH)
                        .map(|d| d.as_secs() as i64).unwrap_or(0)).unwrap_or(0),
            }));
        }
    }
    projects.sort_by(|a, b| {
        let da = a.get("modified").and_then(|v| v.as_i64()).unwrap_or(0);
        let db = b.get("modified").and_then(|v| v.as_i64()).unwrap_or(0);
        db.cmp(&da)
    });
    Ok(serde_json::json!({"ok": true, "projects": projects}))
}

/// 保存引擎交付的工件（消费者：export_html 的自包含 HTML 原型 / 当前画板 SVG）。
/// Rust 只做字节搬运与对话框，不解释内容；扩展名以 default_name 为准（补缺省 .html）。
/// 用户取消返回 Null（对齐 save_ddp）。
#[tauri::command]
async fn save_text_file(
    app: tauri::AppHandle,
    default_name: String,
    contents_b64: String,
    html_filter_label: Option<String>,
    svg_filter_label: Option<String>,
) -> Result<serde_json::Value, String> {
    let contents = BASE64
        .decode(contents_b64.as_bytes())
        .map_err(|_| "export_invalid_base64".to_string())?;
    let name_has_ext = PathBuf::from(&default_name)
        .extension()
        .is_some_and(|e| !e.is_empty());
    let Some(path) = app
        .dialog()
        .file()
        .add_filter(html_filter_label.as_deref().unwrap_or("HTML 原型"), &["html"])
        .add_filter(svg_filter_label.as_deref().unwrap_or("SVG 图形"), &["svg"])
        .set_file_name(&default_name)
        .blocking_save_file()
        .map(|p| {
            let mut s = p.to_string();
            if !name_has_ext && !s.to_lowercase().ends_with(".html") {
                s.push_str(".html");
            }
            PathBuf::from(s)
        })
    else {
        return Ok(serde_json::Value::Null);
    };
    std::fs::write(&path, &contents).map_err(|e| format!("export_write_failed:{e}"))?;
    Ok(serde_json::json!({
        "ok": true,
        "path": path.display().to_string(),
        "bytes": contents.len(),
    }))
}

/// 破坏性操作前的原生确认对话框（新建/打开/关窗前的未保存丢弃确认）。
/// 返回 true = 用户选择**继续编辑**（留在当前文档），false = 放弃更改继续操作。
/// 破坏项「放弃更改」故意放 Cancel 位——回车/默认键落在安全侧；前端据此把
/// true 视为"留下"。
#[tauri::command]
async fn confirm_discard(
    app: tauri::AppHandle,
    title: String,
    message: String,
    ok_label: Option<String>,
    cancel_label: Option<String>,
) -> Result<bool, String> {
    Ok(app
        .dialog()
        .message(message)
        .title(title)
        .kind(MessageDialogKind::Warning)
        .buttons(MessageDialogButtons::OkCancelCustom(
            ok_label.unwrap_or_else(|| "继续编辑".into()),
            cancel_label.unwrap_or_else(|| "放弃更改".into()),
        ))
        .blocking_show())
}

/// 前端脏态同步（applyMbtResult 置脏 / 保存·打开·新建清除）：关窗拦截据此决定
/// 前端脏态同步（applyMbtResult 置脏 / 保存·打开·新建清除）：关窗拦截据此决定
/// 是否拦下 CloseRequested。Rust 不解释视觉语义，只存布尔集合。
/// 多窗口（2026-09）：按窗口 label 记脏——每个项目窗口独立拦截自己的关闭。
static DIRTY_WINDOWS: std::sync::LazyLock<std::sync::Mutex<std::collections::HashSet<String>>> =
    std::sync::LazyLock::new(|| std::sync::Mutex::new(std::collections::HashSet::new()));

/// 前端脏态同步（见 DIRTY_WINDOWS）。window 由 Tauri 注入（调用方窗口）。
#[tauri::command]
fn set_project_dirty(dirty: bool, window: tauri::Window) {
    let label = window.label().to_string();
    let mut set = DIRTY_WINDOWS.lock().expect("dirty set poisoned");
    if dirty {
        set.insert(label);
    } else {
        set.remove(&label);
    }
}

/// 在新窗口打开一个项目（多项目多窗口，2026-09）：label 唯一（proj-<epoch>），
/// 前端 index.html 读取 ?project= 查询参数在引擎就绪后自动免对话框打开该项目。
#[tauri::command]
fn open_project_window(app: tauri::AppHandle, path: String) -> Result<(), String> {
    use tauri::WebviewUrl;
    let p = path.trim().to_string();
    if p.is_empty() {
        return Err("open_project_window:empty_path".into());
    }
    let label = format!("proj-{}", now_ms());
    // path 百分号编码（斜杠/中文/空格），前端 decodeURIComponent 还原
    let enc: String = p
        .bytes()
        .map(|b| {
            if b.is_ascii_alphanumeric() || b"-._~".contains(&b) {
                (b as char).to_string()
            } else {
                format!("%{b:02X}")
            }
        })
        .collect();
    let url = format!("index.html?project={enc}");
    let builder = tauri::WebviewWindowBuilder::new(&app, &label, WebviewUrl::App(url.into()))
        .title("deepDesign Studio");
    // Windows：proj 窗必须显式自绘标题栏——tauri.windows.conf.json 只作用于启动的
    // main 窗，运行时建的窗不继承它，漏配会叠出「原生标题栏 + 自绘 topbar 窗控」双栏
    // （前端 IS_WIN 下 topbar 自带窗控与拖拽区）。macOS 保留原生标题栏：mac 的
    // topbar 没有窗控按钮，去装饰反而没法关窗。
    #[cfg(target_os = "windows")]
    let builder = builder.decorations(false);
    builder
        .build()
        .map_err(|e| format!("open_project_window_failed:{e}"))?;
    Ok(())
}

/// ---------- Agent 运行日志（JSONL，宿主侧可诊断性） ----------
/// 每次 agent run 落一个文件：run_start 头 + 每个事件一行 + run_end 尾。
/// 引擎事件（工具调用/失败/澄清）原样入档；保留最近 50 个文件。
fn now_ms() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0)
}

fn journal_dir(app: &tauri::AppHandle) -> Option<std::path::PathBuf> {
    let dir = app.path().app_data_dir().ok()?.join("logs");
    std::fs::create_dir_all(&dir).ok()?;
    // 保留最近 50 个：文件名以 epoch 前缀，字典序即时间序
    if let Ok(entries) = std::fs::read_dir(&dir) {
        let mut files: Vec<_> = entries
            .filter_map(|e| e.ok())
            .filter(|e| e.path().extension().map(|x| x == "jsonl").unwrap_or(false))
            .collect();
        files.sort_by_key(|e| e.file_name());
        while files.len() > 50 {
            if std::fs::remove_file(files.remove(0).path()).is_err() {
                break;
            }
        }
    }
    Some(dir)
}

fn journal_append(dir: &std::path::Path, file: &str, line: &serde_json::Value) {
    use std::io::Write as _;
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(dir.join(file))
    {
        let _ = f.write_all(format!("{line}\n").as_bytes());
    }
}

/// 退出应用（⌘Q 自定义菜单项的终点）。直接 exit 是有意的：调用前置条件是脏拦截
/// 已确认放弃（脏已清）——绕过 CloseRequested 不构成绕过保护。
#[tauri::command]
fn set_menu_language(app: tauri::AppHandle, lang: String) -> Result<(), String> {
    // 前端语言切换时同步重建原生菜单（macOS 菜单栏；Windows 无原生菜单为空操作）
    let norm = match lang.as_str() {
        "zh-TW" | "zh-HK" | "en" | "ja" | "ko" | "fr" => lang,
        _ => "zh-CN".to_string(),
    };
    *APP_MENU_LANG.lock().map_err(|e| e.to_string())? = norm;
    build_native_menus(&app).map_err(|e| e.to_string())
}

#[tauri::command]
fn app_exit(app: tauri::AppHandle) {
    app.exit(0);
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // 单实例保证：二次启动（任何来源/路径）不再并跑，聚焦既有主窗
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.set_focus();
            }
        }))
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            invoke_fx_sdk,
            save_ddp,
            open_ddp,
            save_text_file,
            confirm_discard,
            set_project_dirty,
            app_exit,
            set_menu_language,
            list_ddp_projects,
            rebase_agent_ops,
            open_project_window,
            model_registry
        ])
        .on_window_event(|window, event| {
            // 脏文档关窗拦截：有未保存更改时拦下系统关闭，交前端确认（Rust 不解释
            // 语义）；确认放弃后前端清脏再触发关闭，第二次 CloseRequested 直接放行。
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                let dirty = DIRTY_WINDOWS
                    .lock()
                    .expect("dirty set poisoned")
                    .contains(window.label());
                if dirty {
                    api.prevent_close();
                    use tauri::Emitter as _;
                    if let Err(e) = window.emit("app-close-request", ()) {
                        eprintln!("[app] app-close-request 投递失败（脏文档确认可能不弹）: {e}");
                    }
                }
            }
        })
        .setup(|app| {
            build_native_menus(app.handle())?;
            // Windows：按主显示器分辨率比例定启动尺寸（82%×86%，clamp 到可见
            // 范围）并居中——任何分辨率下 UI 完全可见、与屏幕保持比例。
            // 窗口 visible:false（见 tauri.windows.conf.json）：尺寸就绪后再显示，
            // 避免慢机上闪现一帧默认尺寸
            #[cfg(target_os = "windows")]
            {
                if let Some(win) = app.get_webview_window("main") {
                    if let Ok(Some(m)) = win.current_monitor() {
                        let sf = m.scale_factor();
                        let lw = m.size().width as f64 / sf;
                        let lh = m.size().height as f64 / sf;
                        let w = ((lw * 0.82).min(1600.0)).max(980.0).min((lw - 24.0).max(980.0));
                        let h = ((lh * 0.86).min(1000.0)).max(640.0).min((lh - 24.0).max(640.0));
                        let _ = win.set_size(tauri::LogicalSize::new(w, h));
                        let _ = win.center();
                    }
                    let _ = win.show();
                }
            }
            Ok(())
        })
        .on_menu_event(|app, event| {
            // 原生菜单 → 前端动作桥：直接 eval 前端全局映射函数（比事件通道更直接）。
            // 多窗口：菜单动作派发给**聚焦中的**项目窗口（各窗同构前端），无聚焦回落 main。
            let id = event.id().as_ref().to_string();
            let target = app
                .webview_windows()
                .values()
                .find(|w| w.is_focused().unwrap_or(false))
                .cloned()
                .or_else(|| app.get_webview_window("main"));
            if let Some(win) = target {
                // serde_json 字符串编码保证合法 JS 字面量（{:?} 的 \u{…} 转义在 JS 里非法）
                let lit = serde_json::to_string(&id).unwrap_or_else(|_| "\"unknown\"".into());
                let _ = win.eval(format!(
                    "if(typeof nativeMenuAction==='function')nativeMenuAction({lit})"
                ));
            }
        })
        .on_page_load(|webview, payload| {
            // 资产协议无缓存头，WKWebView 可能滞留旧页：首载完成后强制带版本参数重载一次。
            // 多窗口：?project=<路径> 的项目窗口保留既有 query，仅追加 v=（?project= 仍生效）
            if payload.event() == tauri::webview::PageLoadEvent::Finished {
                webview.eval(
                    "if(!(/[?&]v=/.test(location.search)))location.replace(location.href+(location.href.includes('?')?'&':'?')+'v='+Date.now())",
                )
                .ok();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

/// 终态 rebase（docs/agent-rebase.md 方案 C）：agent run 是秒级长调用，期间人类
/// 画布 op 可能已推进前端 canonical——整体回灌 run 终态会覆盖丢失人类编辑。
/// 前端在终态应用前比对起点快照，检测到推进时把 run 的变更 op 流交到这里重放到
/// 最新 canonical（AgentGate 逐条重校验，拒绝即跳过并报告；只读 op 由 Rust 侧过滤）。
#[tauri::command]
async fn rebase_agent_ops(
    latest_mbt_b64: String,
    ops: Vec<String>,
) -> Result<serde_json::Value, String> {
    // 传输门（对齐 invoke_fx_sdk 的 12MB）：异常输入不得直通引擎内存增长
    if latest_mbt_b64.len() > 12 * 1024 * 1024 {
        return Err("rebase_payload_too_large".into());
    }
    let latest = String::from_utf8(
        BASE64
            .decode(latest_mbt_b64.as_bytes())
            .map_err(|e| format!("rebase_b64_invalid:{e}"))?,
    )
    .map_err(|e| format!("rebase_utf8_invalid:{e}"))?;
    Ok(agent::rebase_ops(&EngineHost, &latest, &ops).await)
}

/// Agent 基座入口（进程内，无 JS 运行时）：
/// payload = { mode?:'models', instruction, mbt_b64?, api_key?, model?, base_url?, thinking_level? }
/// 返回契约与原 JS 桥一致：{ok, mbt_b64, render, ops[], stopReason, text} / models 列表。
#[tauri::command]
async fn invoke_fx_sdk(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    payload: String,
    api_key: String,
) -> Result<serde_json::Value, String> {
    // 传输门（对齐 save_ddp 的 12MB）：payload 含 mbt_b64（宿主按 UTF-16 写入
    // wasm 内存约 2 倍放大），无门会让异常输入直通引擎内存增长
    if payload.len() > 12 * 1024 * 1024 {
        return Err("fxsdk_payload_too_large".into());
    }
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
    // 实时轨迹：agent 循环每步经 progress 回调 → Tauri 事件 agent-event → 前端时间线；
    // 同一事件流落 JSONL 运行日志（app_data/logs/，保留 50 个），供事后诊断
    let run_id = p.get("run").and_then(|v| v.as_u64()).unwrap_or(0);
    // 多窗口：agent 轨迹只投递给发起 run 的窗口（emit_to），不广播串窗
    let target_label = window.label().to_string();
    let emitter = app.clone();
    let journal = journal_dir(&app);
    let journal_file = journal
        .as_ref()
        .map(|_| format!("agent-{}-{run_id}.jsonl", now_ms()));
    if let (Some(dir), Some(file)) = (&journal, &journal_file) {
        journal_append(
            dir,
            file,
            &serde_json::json!({
                "ts": now_ms(), "type": "run_start", "run": run_id,
                "instruction": instruction.chars().take(200).collect::<String>(),
                "model": model, "thinking": thinking,
                "mbt_bytes": mbt_b64.map(|b| b.len()).unwrap_or(0),
            }),
        );
    }
    let cb_journal = journal.clone();
    let cb_file = journal_file.clone();
    let progress = move |mut v: serde_json::Value| {
        use tauri::Emitter as _;
        // run id 必须注入每个事件（前端按它过滤归属自己那次 run）
        if let Some(obj) = v.as_object_mut() {
            obj.insert("run".into(), serde_json::json!(run_id));
            obj.insert("ts".into(), serde_json::json!(now_ms()));
        }
        if let Err(e) = emitter.emit_to(target_label.as_str(), "agent-event", &v) {
            eprintln!("[agent] agent-event 投递失败（{target_label}）: {e}");
        }
        if let (Some(dir), Some(file)) = (&cb_journal, &cb_file) {
            journal_append(dir, file, &v);
        }
    };
    let result =
        agent::run(&EngineHost, instruction, mbt_b64, &key, model, base_url, thinking, Some(&progress))
            .await;
    if let (Some(dir), Some(file)) = (&journal, &journal_file) {
        journal_append(
            dir,
            file,
            &serde_json::json!({
                "ts": now_ms(), "type": "run_end", "run": run_id,
                "ok": result.get("ok").and_then(|v| v.as_bool()).unwrap_or(false),
                "stopReason": result.get("stopReason").cloned().unwrap_or(serde_json::json!(null)),
                "ops": result.get("ops").and_then(|v| v.as_array()).map(|a| a.len()).unwrap_or(0),
                "error": result.get("error").cloned().unwrap_or(serde_json::json!(null)),
            }),
        );
    }
    Ok(result)
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

/// 原生菜单栏（**仅 macOS**：全局菜单 + 应用菜单是 macOS 惯例）。菜单项只负责
/// 发事件，动作在前端 nativeMenuAction 执行。Windows 上不构建菜单栏——
/// 标题栏与工具栏合并（tauri.windows.conf.json decorations=false，topbar 即
/// 标题栏），原菜单功能由前端「文件 ▾」下拉承载（frontend fmAct）。
/* ── 原生菜单 i18n：当前语言 + 七语言标签表（值=zh-CN 原文键）。语言状态不
 * cfg 门控——set_menu_language 双平台注册，Windows 上写入后重建走空 stub；
 * menu_t 与菜单构建本身仅 macOS。 ── */
static APP_MENU_LANG: std::sync::Mutex<String> = std::sync::Mutex::new(String::new());
#[cfg(target_os = "macos")]
fn menu_t(zh: &str) -> String {
    let lang = APP_MENU_LANG.lock().unwrap_or_else(|e| e.into_inner()).clone();
    let lang = lang.as_str();
    let table: &[(&str, &str)] = match lang {
        "zh-TW" => &[
            ("檔案","文件"),("編輯","编辑"),("檢視","视图"),("畫板","画板"),("說明","帮助"),
            ("新增專案…","新建项目…"),("開啟 DDP…","打开 DDP…"),("開啟最近的專案…","打开最近的项目…"),
            ("儲存","保存"),("匯出 DDP…","导出 DDP…"),("匯出 HTML 原型…","导出 HTML 原型…"),
            ("匯出 SVG（目前畫板）…","导出 SVG（当前画板）…"),("還原","撤销"),("重做","重做"),
            ("剪下","剪切"),("複製","复制"),("貼上","粘贴"),("全選","全选"),
            ("線框圖","线框图"),("高傳真","高保真"),("MBT 原始碼","MBT 源码"),("適應視窗","适配窗口"),
            ("示範模式","演示模式"),("新增畫板","新建画板"),("複製目前畫板","复制当前画板"),
            ("校驗並渲染","校验并渲染"),("自動修復（引擎還債）","自动修复（引擎还债）"),
            ("設定…","设置…"),("結束 deepDesign","退出 deepDesign"),("快捷鍵與選單說明","快捷键与菜单说明"),
        ],
        "zh-HK" => &[
            ("檔案","文件"),("編輯","编辑"),("檢視","视图"),("畫板","画板"),("說明","帮助"),
            ("新增專案…","新建项目…"),("開啟 DDP…","打开 DDP…"),("開啟最近的專案…","打开最近的项目…"),
            ("儲存","保存"),("匯出 DDP…","导出 DDP…"),("匯出 HTML 原型…","导出 HTML 原型…"),
            ("匯出 SVG（目前畫板）…","导出 SVG（当前画板）…"),("復原","撤销"),("重做","重做"),
            ("剪下","剪切"),("複製","复制"),("貼上","粘贴"),("全選","全选"),
            ("線框圖","线框图"),("高傳真","高保真"),("MBT 原始碼","MBT 源码"),("適應視窗","适配窗口"),
            ("示範模式","演示模式"),("新增畫板","新建画板"),("複製目前畫板","复制当前画板"),
            ("校驗並渲染","校验并渲染"),("自動修復（引擎還債）","自动修复（引擎还债）"),
            ("設定…","设置…"),("結束 deepDesign","退出 deepDesign"),("快捷鍵與選單說明","快捷键与菜单说明"),
        ],
        "ja" => &[
            ("ファイル","文件"),("編集","编辑"),("表示","视图"),("ボード","画板"),("ヘルプ","帮助"),
            ("新規プロジェクト…","新建项目…"),("DDP を開く…","打开 DDP…"),("最近のプロジェクトを開く…","打开最近的项目…"),
            ("保存","保存"),("DDP を書き出す…","导出 DDP…"),("HTML プロトタイプを書き出す…","导出 HTML 原型…"),
            ("SVG を書き出す（現在のボード）…","导出 SVG（当前画板）…"),("取り消す","撤销"),("やり直す","重做"),
            ("カット","剪切"),("コピー","复制"),("ペースト","粘贴"),("すべて選択","全选"),
            ("ワイヤーフレーム","线框图"),("ハイファイ","高保真"),("MBT ソース","MBT 源码"),("ウィンドウに合わせる","适配窗口"),
            ("デモモード","演示模式"),("新規ボード","新建画板"),("現在のボードを複製","复制当前画板"),
            ("検証して描画","校验并渲染"),("自動修復（エンジン負債解消）","自动修复（引擎还债）"),
            ("設定…","设置…"),("deepDesign を終了","退出 deepDesign"),("ショートカットとメニューの説明","快捷键与菜单说明"),
        ],
        "ko" => &[
            ("파일","文件"),("편집","编辑"),("보기","视图"),("보드","画板"),("도움말","帮助"),
            ("새 프로젝트…","新建项目…"),("DDP 열기…","打开 DDP…"),("최근 프로젝트 열기…","打开最近的项目…"),
            ("저장","保存"),("DDP 내보내기…","导出 DDP…"),("HTML 프로토타입 내보내기…","导出 HTML 原型…"),
            ("SVG 내보내기(현재 보드)…","导出 SVG（当前画板）…"),("실행 취소","撤销"),("다시 실행","重做"),
            ("잘라내기","剪切"),("복사","复制"),("붙여넣기","粘贴"),("모두 선택","全选"),
            ("와이어프레임","线框图"),("하이파이","高保真"),("MBT 소스","MBT 源码"),("창에 맞춤","适配窗口"),
            ("데모 모드","演示模式"),("새 보드","新建画板"),("현재 보드 복제","复制当前画板"),
            ("검증 후 렌더링","校验并渲染"),("자동 수정(엔진 부채 해소)","自动修复（引擎还债）"),
            ("설정…","设置…"),("deepDesign 종료","退出 deepDesign"),("단축키 및 메뉴 안내","快捷键与菜单说明"),
        ],
        "fr" => &[
            ("Fichier","文件"),("Édition","编辑"),("Affichage","视图"),("Planche","画板"),("Aide","帮助"),
            ("Nouveau projet…","新建项目…"),("Ouvrir un DDP…","打开 DDP…"),("Ouvrir un projet récent…","打开最近的项目…"),
            ("Enregistrer","保存"),("Exporter en DDP…","导出 DDP…"),("Exporter le prototype HTML…","导出 HTML 原型…"),
            ("Exporter en SVG (planche actuelle)…","导出 SVG（当前画板）…"),("Annuler","撤销"),("Rétablir","重做"),
            ("Couper","剪切"),("Copier","复制"),("Coller","粘贴"),("Tout sélectionner","全选"),
            ("Wireframe","线框图"),("Haute fidélité","高保真"),("Source MBT","MBT 源码"),("Ajuster à la fenêtre","适配窗口"),
            ("Mode démo","演示模式"),("Nouvelle planche","新建画板"),("Dupliquer la planche","复制当前画板"),
            ("Valider et rendre","校验并渲染"),("Correction auto (dette moteur)","自动修复（引擎还债）"),
            ("Réglages…","设置…"),("Quitter deepDesign","退出 deepDesign"),("Raccourcis et menus","快捷键与菜单说明"),
        ],
        "en" => &[
            ("File","文件"),("Edit","编辑"),("View","视图"),("Board","画板"),("Help","帮助"),
            ("New Project…","新建项目…"),("Open DDP…","打开 DDP…"),("Open Recent…","打开最近的项目…"),
            ("Save","保存"),("Export DDP…","导出 DDP…"),("Export HTML Prototype…","导出 HTML 原型…"),
            ("Export SVG (Current Board)…","导出 SVG（当前画板）…"),("Undo","撤销"),("Redo","重做"),
            ("Cut","剪切"),("Copy","复制"),("Paste","粘贴"),("Select All","全选"),
            ("Wireframe","线框图"),("High-Fidelity","高保真"),("MBT Source","MBT 源码"),("Fit Window","适配窗口"),
            ("Demo Mode","演示模式"),("New Board","新建画板"),("Duplicate Board","复制当前画板"),
            ("Validate & Render","校验并渲染"),("Auto-Fix (engine debt)","自动修复（引擎还债）"),
            ("Settings…","设置…"),("Quit deepDesign","退出 deepDesign"),("Shortcuts & Menus","快捷键与菜单说明"),
        ],
        _ => &[],
    };
    if lang == "zh-CN" { return zh.to_string(); }
    for (loc, zh_key) in table {
        if *zh_key == zh { return loc.to_string(); }
    }
    zh.to_string()
}

#[cfg(target_os = "macos")]
fn build_native_menus(app: &tauri::AppHandle) -> Result<(), Box<dyn std::error::Error>> {
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
            &menu_t("设置…"),
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
        // 自定义退出（不用预置 .quit()）：terminate: 不走 windowShouldClose，
        // CloseRequested 拦截对 ⌘Q/dock-Quit 完全失效——改为经前端确认流后再 app_exit
        .item(&MenuItem::with_id(
            app,
            "quit-app",
            &menu_t("退出 deepDesign"),
            true,
            Some("CmdOrCtrl+Q"),
        )?)
        .build()?;

    let file = SubmenuBuilder::new(app, &menu_t("文件"))
        .item(&MenuItem::with_id(
            app,
            "new-project",
            &menu_t("新建项目…"),
            true,
            Some("CmdOrCtrl+N"),
        )?)
        .item(&MenuItem::with_id(
            app,
            "open-ddp",
            &menu_t("打开 DDP…"),
            true,
            Some("CmdOrCtrl+O"),
        )?)
        .item(&MenuItem::with_id(
            app,
            "open-recent",
            &menu_t("打开最近的项目…"),
            true,
            None::<&str>,
        )?)
        .item(&MenuItem::with_id(
            app,
            "save",
            &menu_t("保存"),
            true,
            Some("CmdOrCtrl+S"),
        )?)
        .separator()
        .item(&MenuItem::with_id(
            app,
            "export-ddp",
            &menu_t("导出 DDP…"),
            true,
            Some("CmdOrCtrl+Shift+E"),
        )?)
        .item(&MenuItem::with_id(
            app,
            "export-html",
            &menu_t("导出 HTML 原型…"),
            true,
            Some("CmdOrCtrl+Shift+H"),
        )?)
        .item(&MenuItem::with_id(
            app,
            "export-svg",
            &menu_t("导出 SVG（当前画板）…"),
            true,
            None::<&str>,
        )?)
        .build()?;

    let edit = SubmenuBuilder::new(app, &menu_t("编辑"))
        // 自定义撤销/重做（文档级，走前端历史会话）：预置项只作用于焦点文本框，
        // 会让 ⌘Z 被文本语义吞掉；undoMbt 对输入框焦点回退 execCommand 文本撤销
        .item(&MenuItem::with_id(
            app,
            "edit-undo",
            &menu_t("撤销"),
            true,
            Some("CmdOrCtrl+Z"),
        )?)
        .item(&MenuItem::with_id(
            app,
            "edit-redo",
            &menu_t("重做"),
            true,
            Some("CmdOrCtrl+Shift+Z"),
        )?)
        .separator()
        .item(&PredefinedMenuItem::cut(app, Some(&menu_t("剪切")))?)
        .item(&PredefinedMenuItem::copy(app, Some(&menu_t("复制")))?)
        .item(&PredefinedMenuItem::paste(app, Some(&menu_t("粘贴")))?)
        .item(&PredefinedMenuItem::select_all(app, Some(&menu_t("全选")))?)
        .build()?;

    let view = SubmenuBuilder::new(app, &menu_t("视图"))
        .item(&MenuItem::with_id(
            app,
            "view-wireframe",
            &menu_t("线框图"),
            true,
            Some("CmdOrCtrl+1"),
        )?)
        .item(&MenuItem::with_id(
            app,
            "view-hifi",
            &menu_t("高保真"),
            true,
            Some("CmdOrCtrl+2"),
        )?)
        .item(&MenuItem::with_id(
            app,
            "view-decl",
            &menu_t("MBT 源码"),
            true,
            Some("CmdOrCtrl+3"),
        )?)
        .item(&MenuItem::with_id(
            app,
            "view-play",
            &menu_t("演示模式"),
            true,
            Some("CmdOrCtrl+4"),
        )?)
        .separator()
        .item(&MenuItem::with_id(
            app,
            "view-fit",
            &menu_t("适配窗口"),
            true,
            Some("CmdOrCtrl+0"),
        )?)
        .build()?;

    let board = SubmenuBuilder::new(app, &menu_t("画板"))
        .item(&MenuItem::with_id(
            app,
            "board-new",
            &menu_t("新建画板"),
            true,
            Some("CmdOrCtrl+Shift+N"),
        )?)
        .item(&MenuItem::with_id(
            app,
            "board-dup",
            &menu_t("复制当前画板"),
            true,
            Some("CmdOrCtrl+Shift+D"),
        )?)
        .separator()
        .item(&MenuItem::with_id(
            app,
            "autofix",
            &menu_t("自动修复（引擎还债）"),
            true,
            Some("CmdOrCtrl+Shift+F"),
        )?)
        .separator()
        .item(&MenuItem::with_id(
            app,
            "validate",
            &menu_t("校验并渲染"),
            true,
            None::<&str>,
        )?)
        .build()?;

    let help = SubmenuBuilder::new(app, &menu_t("帮助"))
        .item(&MenuItem::with_id(
            app,
            "shortcuts",
            &menu_t("快捷键与菜单说明"),
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

#[cfg(not(target_os = "macos"))]
fn build_native_menus(_app: &tauri::AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    // Windows：无原生菜单栏（标题栏合并，见函数文档）；原菜单功能由前端「文件 ▾」下拉承载
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// DDP 容器往返契约（仓库唯一密码学代码的回归守护）：vendor crate 自带的
    /// 5 个单测不在默认测试面（非 workspace 成员，`cd src-tauri && cargo test`
    /// 不会跑路径依赖的单元测试），这里把加解密往返 + 错密码/篡改拒绝锁进主套件。
    #[test]
    fn ddp_roundtrip_and_rejects() {
        let mbt = "---
moonviz:
  format: visual-document
".repeat(64);
        let ddp = encrypt_ddp(&mbt, "pw").expect("encrypt");
        assert_eq!(decrypt_ddp(&ddp, "pw").expect("decrypt").to_string(), mbt, "往返必须无损");
        assert_eq!(
            decrypt_ddp(&ddp, "wrong"),
            Err("ddp_authentication_failed".to_string()),
            "错密码与篡改同报错（无预言机）"
        );
        let mut tampered = ddp.clone();
        let last = tampered.len() - 1;
        tampered[last] ^= 0xFF;
        assert!(decrypt_ddp(&tampered, "pw").is_err(), "篡改任意字节必须拒绝");
    }
}
