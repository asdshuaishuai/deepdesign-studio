//! deepDesign core — 鸿蒙侧 NAPI 门面
//!
//! DDP codec 与桌面版共用 vendor/moonviz-ddp——同一 .ddp 文件两端互通（纯逻辑在
//! ddp 模块，host 测试覆盖）；NAPI 导出遵循 napi-ohos 默认 camelCase
//! （core_version -> coreVersion），d.ts（ohos/entry/src/main/cpp/types/
//! libdeepdesign_core/index.d.ts）须同步。

pub mod ddp;

// 引擎宿主（wasmtime 进程内承载 classic wasm）——纯逻辑，host 测试覆盖
// （--no-default-features 同 ddp 口径）。gap-global-3 第二阶段探针：
// ohos 交叉编译面已放开（cfg(not(ohos)) 门撤除），双端同一实现。
pub mod engine;

// Agent 会话状态机（M3.6.7：桌面 agent.rs 循环架构移植——loop 状态机/工具执行/引擎
// 调用全在 Rust；ArkTS 仅 HTTP 传输泵 + UI。宿主测试覆盖，见 agent.rs tests）。
pub mod agent;

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

    // —— 引擎宿主导出（gap-global-3 接线：engine.rs 公开面的 camelCase NAPI 桥）——
    // 信封统一 String（serde_json 序列化）回传，与 DDP 导出的 String 面、Dispatch 侧
    // JSON.parse 判型惯例同构。分层语义：Err 仅传输层失败（b64/编解码/wasm 编译/实例化/
    // 超时）；ok:false 的门拒绝是**合法业务信封**（Ok 透传），调用方按信封 ok 字段判定——
    // 与桌面 invoke 契约一致，ArkTS 侧不得把门拒绝当引擎不可用。

    /// 真实引擎探针：wasmtime 实例化 + version_info 调用。信封 {ok, engine, version}
    /// （真机探锚 {"ok":true,"engine":"moonviz","version":"0.1.6-fix"}）。首次调用含
    /// wasm 编译（秒级，同步 NAPI 阻塞 UI 线程——调用方须延时到首帧后；Promise 化归后续）。
    #[napi]
    pub fn engine_version() -> napi_ohos::Result<String> {
        crate::engine::version().map(|v| v.to_string()).map_err(napi_ohos::Error::from_reason)
    }

    /// 注册表 op 清单（引擎原样透传的裸 JSON 数组）。
    #[napi]
    pub fn engine_list_ops() -> napi_ohos::Result<String> {
        crate::engine::list_ops().map(|v| v.to_string()).map_err(napi_ohos::Error::from_reason)
    }

    /// 人类门变更 op（session_apply_human）：canonical b64 文档 + op 行。成功信封带
    /// mbt_b64（canonical），门拒绝原样透传 ok:false。
    #[napi]
    pub fn engine_apply_human_op(doc_b64: String, op: String) -> napi_ohos::Result<String> {
        crate::engine::apply_human_op(&doc_b64, &op)
            .map(|v| v.to_string())
            .map_err(napi_ohos::Error::from_reason)
    }

    /// 代理门变更 op（session_apply_agent）：与 engineApplyHumanOp 同构，门更严
    /// （只读 op 拒绝、越界放置整体拒绝）。
    #[napi]
    pub fn engine_apply_agent_op(doc_b64: String, op: String) -> napi_ohos::Result<String> {
        crate::engine::apply_agent_op(&doc_b64, &op)
            .map(|v| v.to_string())
            .map_err(napi_ohos::Error::from_reason)
    }

    /// 渲染检视（经典 render_mbt，无状态）：信封 {ok, entry, revision, blockKinds, flows,
    /// mbt, mbt_b64, artboards}，artboard 条目带 id/name/width/height/nodes/svg。
    #[napi]
    pub fn engine_render(doc_b64: String) -> napi_ohos::Result<String> {
        crate::engine::render(&doc_b64).map(|v| v.to_string()).map_err(napi_ohos::Error::from_reason)
    }

    /// 会话历史（M3）：sub ∈ init|commit|log|undo|redo|checkout|diff。apply 不自动入史
    /// 须显式 commit；undo/redo 信封带 canonical（mbt_b64）由 ArkTS 合并回灌。
    #[napi]
    pub fn engine_history(doc_b64: String, sub: String) -> napi_ohos::Result<String> {
        crate::engine::history(&doc_b64, &sub)
            .map(|v| v.to_string())
            .map_err(napi_ohos::Error::from_reason)
    }

    /// Agent 会话启动（M3.6.7）：建会话返回首动作 JSON（{"action":"llm",...}）。
    #[napi]
    pub fn agent_start(instruction: String, doc_b64: String) -> napi_ohos::Result<String> {
        crate::agent::agent_start(&instruction, &doc_b64).map(|v| v.to_string()).map_err(napi_ohos::Error::from_reason)
    }

    /// Agent 喂回 LLM 响应（同步 NAPI；工作线程执行由 ArkTS TaskPool 承担——引擎 op
    /// 不上 UI 线程，批量轮 ANR 根因修复）。
    #[napi]
    pub fn agent_feed_llm(message_json: String) -> napi_ohos::Result<String> {
        crate::agent::agent_feed(&message_json).map(|v| v.to_string()).map_err(napi_ohos::Error::from_reason)
    }
}
