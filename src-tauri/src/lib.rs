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
use tauri_plugin_dialog::DialogExt;
use zeroize::Zeroizing;

/// 保存唯一事实源：引擎交付 canonical MBT，Rust codec 输出不透明 `.ddp`。
/// async 命令（跑在 tokio worker）：blocking_* 对话框禁止在主线程调用
/// （同步命令在 macOS WKWebView IPC 回调 = 主线程内联执行，sheet 会冻结）。
#[tauri::command]
async fn save_ddp(
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

    let Some(path) = app
        .dialog()
        .file()
        .add_filter("deepDesign 视觉文档", &["ddp"])
        .blocking_save_file()
        .map(|p| {
            let mut s = p.to_string();
            if !s.to_lowercase().ends_with(".ddp") {
                s.push_str(".ddp");
            }
            PathBuf::from(s)
        })
    else {
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
async fn open_ddp(app: tauri::AppHandle, password: String) -> Result<serde_json::Value, String> {
    let Some(path) = app
        .dialog()
        .file()
        .add_filter("deepDesign 视觉文档", &["ddp"])
        .blocking_pick_file()
    else {
        return Ok(serde_json::Value::Null); // 用户取消，见 save_ddp 注释
    };
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            invoke_fx_sdk,
            save_ddp,
            open_ddp,
            model_registry
        ])
        .setup(|app| {
            build_native_menus(app)?;
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

/// Agent 基座入口（进程内，无 JS 运行时）：
/// payload = { mode?:'models', instruction, mbt_b64?, api_key?, model?, base_url?, thinking_level? }
/// 返回契约与原 JS 桥一致：{ok, mbt_b64, render, ops[], stopReason, text} / models 列表。
#[tauri::command]
async fn invoke_fx_sdk(payload: String, api_key: String) -> Result<serde_json::Value, String> {
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
    Ok(agent::run(&EngineHost, instruction, mbt_b64, &key, model, base_url, thinking).await)
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
#[cfg(target_os = "macos")]
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

#[cfg(not(target_os = "macos"))]
fn build_native_menus(_app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
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
