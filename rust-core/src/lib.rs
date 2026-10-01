//! deepDesign core — 鸿蒙侧 NAPI 门面
//!
//! DDP codec 与桌面版共用 vendor/moonviz-ddp——同一 .ddp 文件两端互通（纯逻辑在
//! ddp 模块，host 测试覆盖）；NAPI 导出遵循 napi-ohos 默认 camelCase
//! （core_version -> coreVersion），d.ts（ohos/entry/src/main/cpp/types/
//! libdeepdesign_core/index.d.ts）须同步。

pub mod ddp;

// NAPI 门面仅设备构建启用（host 测试/CI：--no-default-features，
// 避免 libace_napi.z.so 链接依赖）
#[cfg(feature = "napi")]
mod napi_facade {
    use super::ddp;
    use napi_derive_ohos::napi;

    // 设备上 stderr 不可见：panic 详情打进 hilog（tag hilog_rs），结合 faultlog 定位
    #[used]
    #[link_section = ".init_array"]
    static __CORE_CTOR: extern "C" fn() = {
        extern "C" fn __core_init() {
            std::panic::set_hook(Box::new(|info| {
                let loc = info
                    .location()
                    .map(|l| format!("{}:{}", l.file(), l.line()))
                    .unwrap_or_default();
                let msg = format!("deepdesign_core PANIC: {} @ {}", info, loc);
                hilog_binding::error(msg.as_str(), None);
            }));
            hilog_binding::info("deepdesign_core: module loaded", None);
        }
        __core_init
    };

    #[napi]
    pub fn core_version() -> String {
        format!(
            "deepdesign-core-ohos {} (engine: moonviz wasm, host: wasmtime)",
            env!("CARGO_PKG_VERSION")
        )
    }

    /// 引擎契约探针的最小等价物。L1 推进时由 wasmtime 宿主真实契约响应替换。
    #[napi]
    pub fn core_ping(payload: String) -> String {
        format!("pong:{}", payload)
    }

    /// MBT 源 → DDP 容器（base64）。空密码走 DDP2 无密码模式，与桌面版一致。
    #[napi]
    pub fn ddp_encrypt(mbt: String, password: String) -> napi_ohos::Result<String> {
        ddp::encrypt_b64(&mbt, &password).map_err(napi_ohos::Error::from_reason)
    }

    /// DDP 容器（base64）→ MBT 源。口令不符/损坏返回 Err（消息即错误码）。
    #[napi]
    pub fn ddp_decrypt(ddp_b64: String, password: String) -> napi_ohos::Result<String> {
        ddp::decrypt_b64(&ddp_b64, &password).map_err(napi_ohos::Error::from_reason)
    }
}
