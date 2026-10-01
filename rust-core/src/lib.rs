//! deepDesign core — 鸿蒙侧 NAPI 门面
//!
//! 后端核心（wasmtime 引擎宿主 + Agent 循环 + DDP 编解码）从 src-tauri 下沉到
//! deepdesign-core crate（见 docs/harmonyos-port.md §4 L1）。本 crate 只做
//! NAPI 类型转换，逐步把已拆分的模块 re-export 出去。
//! 当前为 M1 骨架：版本探测 + 最小命令回显，验证 NAPI 链路。

use napi_derive_ohos::napi;

#[napi]
pub fn core_version() -> String {
    format!("deepdesign-core-ohos {} (engine: moonviz wasm, host: wasmtime)", env!("CARGO_PKG_VERSION"))
}

/// 引擎契约探针的最小等价物：接收 JS 侧传入的命令，返回结构化回执。
/// L1 推进时由 wasmtime 宿主的真实契约响应替换。
#[napi]
pub fn core_ping(payload: String) -> String {
    format!("pong:{}", payload)
}
