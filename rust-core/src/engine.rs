//! wasmtime 进程内引擎宿主——移植自桌面版 `src-tauri/src/wasmtime_host.rs`
//! （鸿蒙引擎接线立项 gap-global-3 第一阶段）。
//!
//! 与母本的**有意差异**（其余逐段同构，改母本时回看这里）：
//! - **同步 API，无 tokio**：桌面版的 `invoke` 用 spawn_blocking + tokio timeout
//!   兜「锁排队宽限」；rust-core 无 tokio 依赖，公开面直接走 `invoke_sync`。
//!   真挂死的 wasm 调用仍由 epoch 中断在 CALL_TIMEOUT 处打断（看门狗线程），
//!   锁排队由每次调用自身 30s 的 epoch 上限天然有界——语义等价。
//! - **无 components.json 快照**（桌面版 list_components 信封）——本阶段公开面
//!   只有 init/load/apply_human_op/apply_agent_op/render/list_ops/version，
//!   组件快照接线是后续阶段的事。
//! - **公开面是具名函数**（NAPI 桥下一阶段按 camelCase 导出），不是桌面版的
//!   `EngineHost::call(fn_name, mbt, op)` 通用口；信封在具名层补 `mbt_b64`
//!   （canonical 的 base64），与桌面 invoke 返回契约 `{…, mbt_b64} 同形`。
//!   底层 dispatch 仍是完整 session 路由表（含 tap/constrain/auto_fix 等），
//!   与母本一致。
//! - **wasm 产物**：同一份 `frontend/vendor/moonviz.wasm`（engine-v0.1.6-fix，
//!   sha512 见 frontend/vendor/engine-manifest.json），编译期 include_bytes!
//!   嵌入——产物缺失即编译错误（显性失败优于静默）。
//!
//! 引擎 ABI 契约（与母本同）：
//! - **读方向**：引擎返回字符串指针（[refcnt@ptr-8][len@ptr-4][UTF-16LE@ptr+0]），
//!   read_str 保留布局知识（LEN_MASK 剔除高 4 位标志）。
//! - **写方向走 `_in` 字节契约面**（engine-v0.1.2，上游 issue #8）：文档/op 文本
//!   经 in/arg/arg2 三槽压入（UTF-8 分块，每块小端 4 字节 + 有效长度），
//!   `*_in()` 变体从槽解码调用经典入口——写方向不依赖逆向的字符串内存布局。
//! - **session API**：mbt 键控会话缓存（命中复用/失配关旧开新）、变更信封
//!   canonical 键前移 + 同句柄补画板索引（data 为数组才补）；任何解析失败/
//!   腐坏读/trap 都弃缓存。
//! - **线程与生命周期**：单实例 + Mutex 串行；epoch interruption 超时真中断；
//!   实例槽 RwLock<Option<Arc>>（init 失败不缓存，下次自动重试）；内存棘轮
//!   192MB 超限整体重建（缓存按权威 mbt 键控，重建零语义影响）。
//!
//! **ohos 目标暂不编译本模块**（Cargo.toml 非 ohos 节 + lib.rs cfg 门）：
//! wasmtime 在 OHOS target 上的兼容性是下一阶段探针；探针通过后撤门。

use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex, OnceLock, RwLock};
use wasmtime::{Instance, Memory, Module, Store, Val};

/// 引擎产物（编译期嵌入；由 scripts/sync-engine.mjs 拉取并做 sha512+契约探针）。
/// rust-core 与 frontend 同为仓库根的兄弟目录，相对路径与桌面版一致。
const WASM_BYTES: &[u8] =
    include_bytes!(concat!(env!("CARGO_MANIFEST_DIR"), "/../frontend/vendor/moonviz.wasm"));

// —— classic wasm 字符串读 ABI（返回方向；写方向已由 `_in` 槽契约取代）——
/// 长度字段掩码（高 4 位是引擎内部标志位，读取时剔除）
const LEN_MASK: u32 = 0x0FFF_FFFF;
/// `_in` 槽协议的分块尺寸（引擎约定：每块 ≤4 字节，小端压入 u32）
const SLOT_CHUNK: usize = 4;
/// 线性内存回收阈值：超过即整体重建实例（对齐桌面版与前端 engineRecycleIfNeeded）
const MEMORY_RECYCLE_BYTES: usize = 192 * 1024 * 1024;
/// 单次引擎调用超时（epoch 到点真中断）
const CALL_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(30);
/// epoch tick 周期（看门狗线程推进时钟的粒度；deadline 换算成 tick 数）
const EPOCH_TICK_MS: u64 = 100;

/// 经典导出 arity（字符串全部经编解码；返回值为字符串指针）
fn arity(fn_name: &str) -> Option<usize> {
    Some(match fn_name {
        "list_templates" | "version_info" | "list_tokens" | "list_themes" | "list_ops" => 0,
        "render_mbt" | "validate_mbt" | "export_html" => 1,
        "apply_agent_op" | "apply_human_op" => 2,
        _ => return None,
    })
}
/// 变更类导出（成功信封回传 canonical：缓存键前移 + 补画板索引）。
/// 0.1.6-fix/#19 起全部"改文档面"信封都带 canonical——apply 双门之外，
/// auto_fix/constrain/tap/generate_responsive/component_compile_b64 一并纳入。
/// 与桌面版 wasmtime_host.rs::SESSION_MUTATING 同步维护。
const SESSION_MUTATING: [&str; 8] = [
    "session_apply_agent",
    "session_apply_human",
    "session_auto_fix",
    "session_constrain",
    "session_tap",
    "session_generate_responsive",
    "session_component_compile_b64",
    // M3（gap-global-3）：history undo/redo/checkout 改文档——信封带 canonical 时缓存键
    // 前移（init/commit/log 无 canonical 或 ok:false 时零副作用，双重门在 finish 里）。
    "session_history",
];
/// session_tap 需要的最小 op 参数（artboard + x + y）
const SESSION_TAP_MIN_ARGS: usize = 3;

struct Session {
    handle: i32,
    mbt: String,
}

/// `_in` 调用的槽装载计划（分块字符串槽协议）
enum SlotPlan {
    /// 无文本入参——经典直调
    None,
    /// arg 槽：op / artboard / b64 等单文本
    Arg(String),
    /// arg + arg2 槽：constrain 的 artboard + intent
    Arg2(String, String),
    /// arg 槽 artboard + x/y 直参（tap）
    Tap(f64, f64, String),
}

struct Engine {
    store: Store<()>,
    instance: Instance,
    memory: Memory,
    sess_cache: Option<Session>,
    /// 常驻 history 会话（M3.5，桌面 histS 同构）：apply 与 history commit/undo/redo
    /// 同会话执行——按板历史栈跨 op 累积。keyed 会话（sess_cache）每 op 按权威文档
    /// 重开 + init 重基线，undo 永远落回本轮基线（M3 验收实证「连续 undo 不生效」
    /// 的根因），故引擎路由 op 一律改走本会话。实例重建（毒化/棘轮/中断）时随之
    /// 销毁，下次 hist_apply 自动重开（撤销栈丢失=可牺牲，同桌面 histS 关闭语义）。
    hist: Option<HistSess>,
    hits: u64,
    misses: u64,
}

#[derive(Clone)]
struct HistSess {
    handle: i32,
    mbt: String,        // 会话当前 canonical（复用判定 + ArkTS 锚一致性）
    initd: Vec<String>, // 已 init 板清单（op 后补 init 只对新建板，防重基线清栈）
}

/// 共享 wasmtime::Engine（epoch 时钟与编译缓存的宿主；实例可重建，engine 不换——
/// 看门狗线程持有的引用因此始终有效）。
static WT_ENGINE: OnceLock<wasmtime::Engine> = OnceLock::new();
/// 引擎实例槽：Option 可清除——init 失败不缓存（下次调用自动重试）。
static ENGINE: RwLock<Option<Arc<Mutex<Engine>>>> = RwLock::new(None);

/// 共享 engine（含看门狗线程的一次性启动：每 tick 推进 epoch，deadline 由
/// 每次调用前按 delta 设置——时钟恒走、闹钟各设各的）。
fn wt_engine() -> &'static wasmtime::Engine {
    WT_ENGINE.get_or_init(|| {
        let mut cfg = wasmtime::Config::new();
        cfg.epoch_interruption(true);
        let engine = wasmtime::Engine::new(&cfg).expect("wasmtime engine build");
        let ticker = engine.clone();
        std::thread::Builder::new()
            .name("moonviz-epoch-tick".into())
            .spawn(move || loop {
                std::thread::sleep(std::time::Duration::from_millis(EPOCH_TICK_MS));
                ticker.increment_epoch();
            })
            .expect("spawn epoch ticker");
        engine
    })
}

fn engine() -> Result<Arc<Mutex<Engine>>, String> {
    if let Some(m) = ENGINE.read().expect("engine rwlock").as_ref() {
        return Ok(m.clone());
    }
    // 双检写：并发首呼只 init 一次；**失败不写槽**——下一次调用自动重试
    let mut w = ENGINE.write().expect("engine rwlock");
    if let Some(m) = w.as_ref() {
        return Ok(m.clone());
    }
    let built = Arc::new(Mutex::new(init()?));
    *w = Some(built.clone());
    Ok(built)
}

fn init() -> Result<Engine, String> {
    let engine = wt_engine().clone();
    let module = Module::new(&engine, WASM_BYTES)
        .map_err(|e| format!("wasm_compile:{e}（产物损坏？重跑 node scripts/sync-engine.mjs）"))?;
    let mut store = Store::new(&engine, ());
    // epoch_interruption 的 store 默认 deadline 为 0——看门狗已在推进时钟，
    // 新 store 一创建即「已到点」，连 Instance::new 的 start 段都会被打断。
    // 实例化前先给足 deadline（之后 dispatch 每次调用前会重设）。
    store.set_epoch_deadline((CALL_TIMEOUT.as_millis() / EPOCH_TICK_MS as u128 + 1) as u64);
    let instance = Instance::new(&mut store, &module, &[])
        .map_err(|e| format!("wasm_instantiate:{e}"))?;
    let memory = instance
        .get_memory(&mut store, "memory")
        .ok_or("wasm_no_memory_export")?;
    Ok(Engine {
        store,
        instance,
        memory,
        sess_cache: None,
        hist: None,
        hits: 0,
        misses: 0,
    })
}

/// 测试辅助：清空实例槽（下次调用重新实例化）——常驻实例下缓存统计的
/// 绝对值断言（hits/misses 从零计数）需要它。
#[cfg(test)]
pub(crate) fn hard_reset() {
    *ENGINE.write().expect("engine rwlock") = None;
}

// ————————————————————————————————————————————————————————————————
// 公开面（NAPI 桥下一阶段按 camelCase 导出：version/listOps/load/
// applyHumanOp/applyAgentOp/render/cacheStats）。文档入参一律 base64
// （前端 btoa 语义，与桌面 invoke 的 mbt_b64 契约同形）；信封原样透传，
// 携带 canonical（mbt 字段）时补 mbt_b64。
// ————————————————————————————————————————————————————————————————

/// 文档入参解码：base64 → UTF-8 canonical。
fn decode_doc(doc_b64: &str) -> Result<String, String> {
    let bytes = BASE64
        .decode(doc_b64.as_bytes())
        .map_err(|e| format!("engine_doc_b64_invalid:{e}"))?;
    String::from_utf8(bytes).map_err(|e| format!("engine_doc_utf8_invalid:{e}"))
}

/// 信封携带 canonical（mbt 字段）时补 mbt_b64——纯 additive，原字段不动。
fn attach_mbt_b64(r: &mut Value) {
    if let Some(m) = r.get("mbt").and_then(|x| x.as_str()) {
        r["mbt_b64"] = json!(BASE64.encode(m.as_bytes()));
    }
}

/// 引擎版本信封 `{ok, engine, version}`（真机探针：{"ok":true,"engine":"moonviz",
/// "version":"0.1.6-fix"}）。
pub fn version() -> Result<Value, String> {
    invoke_sync("version_info", "", "")
}

/// 注册表 op 清单（裸 JSON 数组，引擎原样透传）。
pub fn list_ops() -> Result<Value, String> {
    invoke_sync("list_ops", "", "")
}

/// canonical 建会话：解码 base64 文档 → 经 session_list_artboards 走缓存机制
/// 开库（miss 即 open、命中即复用），返回 `{ok, data:[画板…]}` 信封。
pub fn load(doc_b64: &str) -> Result<Value, String> {
    let doc = decode_doc(doc_b64)?;
    invoke_sync("session_list_artboards", &doc, "")
}

/// 人类门变更 op（session_apply_human）：信封 `{ok, mbt, artboards, …}`，
/// 成功时补 mbt_b64；门拒绝原样透传 ok:false。
pub fn apply_human_op(doc_b64: &str, op: &str) -> Result<Value, String> {
    apply_via("session_apply_human", doc_b64, op)
}

/// 代理门变更 op（session_apply_agent）：与 apply_human_op 同构，门更严
/// （只读 op 拒绝、越界放置整体拒绝）。
pub fn apply_agent_op(doc_b64: &str, op: &str) -> Result<Value, String> {
    apply_via("session_apply_agent", doc_b64, op)
}

fn apply_via(fn_name: &str, doc_b64: &str, op: &str) -> Result<Value, String> {
    let doc = decode_doc(doc_b64)?;
    invoke_sync(fn_name, &doc, op).map(|mut r| {
        attach_mbt_b64(&mut r);
        r
    })
}

/// 渲染检视（经典 render_mbt，无状态）：信封 `{ok, entry, revision, blockKinds,
/// flows, mbt, artboards}`，artboard 条目带 id/name/width/height/nodes/svg。
pub fn render(doc_b64: &str) -> Result<Value, String> {
    let doc = decode_doc(doc_b64)?;
    invoke_sync("render_mbt", &doc, "").map(|mut r| {
        attach_mbt_b64(&mut r);
        r
    })
}

/// —— 常驻 history 会话（M3.5，桌面 histS 同构）——
///
/// 引擎路由 op 与 history commit/undo/redo 同会话执行：session_apply_human 就地变更
/// 会话文档，history commit 把变更入按板栈，undo/redo 弹栈——栈跨 op 累积，连续 undo
/// 逐级回退（M3 缺陷「keyed 会话每 op 重开 + init 重基线 → undo 永远落回本轮基线」
/// 的修复）。doc 在会话外变化（本地回退/打开/新建）→ 关旧开新 + 逐板 init 重基线
/// （该点撤销链清空，与桌面 histS 关闭语义一致）。实例重建（毒化/棘轮/中断）同此。
pub fn hist_apply(
    doc_b64: &str,
    op: &str,
    boards_json: &str,
    commit_board: &str,
) -> Result<Value, String> {
    let doc = decode_doc(doc_b64)?;
    let boards: Vec<String> = serde_json::from_str(boards_json)
        .map_err(|e| format!("hist_boards_parse:{e}"))?;
    let engine = engine()?;
    let mut poisoned = false;
    let mut guard = match engine.lock() {
        Ok(g) => g,
        Err(p) => {
            poisoned = true;
            p.into_inner()
        }
    };
    if poisoned || guard.memory.data(&guard.store).len() > MEMORY_RECYCLE_BYTES {
        *guard = init().map_err(|e| format!("engine_rebuild_failed:{e}"))?;
    }
    let reuse = guard.hist.as_ref().map(|h| h.mbt == doc).unwrap_or(false);
    let handle = if reuse {
        guard.hist.as_ref().expect("reuse just checked").handle
    } else {
        if let Some(hs) = guard.hist.take() {
            let _ = guard.call_raw("session_close", &[Val::I32(hs.handle)]);
        }
        if let Err(err) = load_slot(&mut guard, "in_reset", "in_push", &doc) {
            guard.hist = None;
            return Err(err);
        }
        let h = match guard.call_raw("session_open_in", &[]) {
            Ok(h) => h,
            Err(err) => {
                guard.hist = None;
                return Err(err);
            }
        };
        if h < 0 {
            guard.hist = None;
            return Err(format!("hist_session_open_failed:{h}"));
        }
        let initd: Vec<String> = Vec::new();
        guard.hist = Some(HistSess { handle: h, mbt: doc.clone(), initd });
        // 逐板 init（重开会话的重基线点——文档在会话外变化时撤销链清空，语义同桌面
        // histS 关闭重开）
        for b in &boards {
            if let Err(err) = load_slot(&mut guard, "arg_reset", "arg_push", b) {
                guard.hist = None;
                return Err(err);
            }
            let is = match guard
                .call_raw("session_history_in", &[Val::I32(h)])
                .map(|p| guard.read_str(p))
            {
                Ok(s) => s,
                Err(err) => {
                    guard.hist = None;
                    return Err(err);
                }
            };
            // init 信封 ok:false（板在本文档中尚不存在——模板/create 建板场景）不得记入
            // initd：假记录会挡住 apply 后的补充 init → commit 即 history_not_initialized
            // （hist_session_continuous_flow 实证）。ok 未显式 true 一律视为未 init。
            let init_ok = envelope(is.as_str())
                .ok()
                .and_then(|e| e.get("ok").and_then(|x| x.as_bool()))
                == Some(true);
            if init_ok {
                if let Some(hs) = guard.hist.as_mut() {
                    hs.initd.push(b.clone());
                }
            }
        }
        h
    };
    // op 于 hist 会话内执行（op 经 arg 槽，handle 直参）
    if let Err(err) = load_slot(&mut guard, "arg_reset", "arg_push", op) {
        guard.hist = None;
        return Err(err);
    }
    guard.store.set_epoch_deadline(
        (CALL_TIMEOUT.as_millis() / EPOCH_TICK_MS as u128 + 1) as u64,
    );
    let out = match guard.call_raw("session_apply_human_in", &[Val::I32(handle)]).map(|p| guard.read_str(p)) {
        Ok(s) => s,
        Err(trap) => {
            guard.hist = None;
            evict_session(&mut guard);
            return Err(trap);
        }
    };
    if out.is_empty() {
        guard.hist = None;
        evict_session(&mut guard);
        return Err("engine_corrupt_read:empty result".to_string());
    }
    let mut r = envelope(&out)?;
    // 会话文档前移（成功才推进；门拒绝 ok:false 文档未变）
    if r.get("ok").and_then(|x| x.as_bool()) == Some(true) {
        if let Some(m) = r.get("mbt").and_then(|x| x.as_str()) {
            if let Some(hs) = guard.hist.as_mut() {
                hs.mbt = m.to_string();
            }
        }
    }
    attach_mbt_b64(&mut r);
    // op 后补 init（M3.5 根因修复：op 可能创建新画板——open 时该板尚不存在，init
    // 静默 ok:false）。只对**未 init 过**的板补（实测同会话重复 init 会重基线清栈，
    // 这正是 M3「连续 undo 不生效」的根因）；已 init 板严禁重复 init。
    if r.get("ok").and_then(|x| x.as_bool()) == Some(true) {
        let initd_now = guard.hist.as_ref().map(|h| h.initd.clone()).unwrap_or_default();
        for b in &boards {
            if initd_now.contains(b) {
                continue;
            }
            if load_slot(&mut guard, "arg_reset", "arg_push", &format!("init {b}")).is_err() {
                continue;
            }
            let is = match guard
                .call_raw("session_history_in", &[Val::I32(handle)])
                .map(|p| guard.read_str(p))
            {
                Ok(s) => s,
                Err(err) => {
                    guard.hist = None;
                    return Err(err);
                }
            };
            // 同 open 时口径：ok 显式 true 才记 initd（补充 init 本身仍可能 ok:false——
            // op 虽 ok 但目标板未落文档的非常规路径，不记账让下次 op 再补）
            let init_ok = envelope(is.as_str())
                .ok()
                .and_then(|e| e.get("ok").and_then(|x| x.as_bool()))
                == Some(true);
            if init_ok {
                if let Some(hs) = guard.hist.as_mut() {
                    hs.initd.push(b.clone());
                }
            }
        }
    }
    // history commit（apply 不自动入史，显式入栈）
    if r.get("ok").and_then(|x| x.as_bool()) == Some(true) && !commit_board.is_empty() {
        if let Err(err) = load_slot(&mut guard, "arg_reset", "arg_push", &format!("commit {commit_board}")) {
            guard.hist = None;
            return Err(err);
        }
        guard.store.set_epoch_deadline(
            (CALL_TIMEOUT.as_millis() / EPOCH_TICK_MS as u128 + 1) as u64,
        );
        let cres = match guard
            .call_raw("session_history_in", &[Val::I32(handle)])
            .map(|p| guard.read_str(p))
        {
            Ok(s) => s,
            Err(trap) => {
                guard.hist = None;
                return Err(trap);
            }
        };
        if let Ok(cr) = envelope(&cres) {
            if let Some(rev) = cr.get("rev").and_then(|x| x.as_i64()) {
                r["hist_rev"] = json!(rev);
            }
        }
    }
    Ok(r)
}

/// 常驻 history 会话的 undo/redo（M3.5）：kind ∈ undo|redo。返回信封带 mbt/mbt_b64
/// （回退/重做后的 canonical），ArkTS 合并回灌。会话不在（未 apply 过/实例重建）→
/// Err 由调用方回退本地栈。
pub fn hist_move(kind: &str, board: &str) -> Result<Value, String> {
    let engine = engine()?;
    let mut poisoned = false;
    let mut guard = match engine.lock() {
        Ok(g) => g,
        Err(p) => {
            poisoned = true;
            p.into_inner()
        }
    };
    if poisoned || guard.memory.data(&guard.store).len() > MEMORY_RECYCLE_BYTES {
        *guard = init().map_err(|e| format!("engine_rebuild_failed:{e}"))?;
    }
    let handle = guard.hist.as_ref().map(|h| h.handle).ok_or("hist_session_missing")?;
    if let Err(err) = load_slot(&mut guard, "arg_reset", "arg_push", &format!("{kind} {board}")) {
        guard.hist = None;
        return Err(err);
    }
    guard.store.set_epoch_deadline(
        (CALL_TIMEOUT.as_millis() / EPOCH_TICK_MS as u128 + 1) as u64,
    );
    let out = match guard
        .call_raw("session_history_in", &[Val::I32(handle)])
        .map(|p| guard.read_str(p))
    {
        Ok(s) => s,
        Err(trap) => {
            guard.hist = None;
            evict_session(&mut guard);
            return Err(trap);
        }
    };
    if out.is_empty() {
        guard.hist = None;
        evict_session(&mut guard);
        return Err("engine_corrupt_read:empty result".to_string());
    }
    let mut r = envelope(&out)?;
    if r.get("ok").and_then(|x| x.as_bool()) == Some(true) {
        if let Some(m) = r.get("mbt").and_then(|x| x.as_str()) {
            if let Some(hs) = guard.hist.as_mut() {
                hs.mbt = m.to_string();
            }
        }
    }
    attach_mbt_b64(&mut r);
    Ok(r)
}

/// 会话历史（0.1.5-fix-2 起 wasm 导出 session_history[_in]，arg 槽 `<sub> [artboard]]`）：
/// sub ∈ init|commit|log|undo|redo|checkout|diff。**apply 不自动入史，须显式 commit**；
/// undo/redo/checkout 改文档 → 信封带 canonical 时补 mbt_b64（缓存键经 SESSION_MUTATING
/// 前移，init/commit/log 无 canonical 零副作用）。
pub fn history(doc_b64: &str, sub: &str) -> Result<Value, String> {
    let doc = decode_doc(doc_b64)?;
    invoke_sync("session_history", &doc, sub).map(|mut r| {
        attach_mbt_b64(&mut r);
        r
    })
}

/// 会话缓存命中统计 `{ok, hits, misses}`（契约测试与诊断用）。
pub fn cache_stats() -> Result<Value, String> {
    invoke_sync("session_cache_stats", "", "")
}

// ————————————————————————————————————————————————————————————————
// 宿主内核（与桌面版 wasmtime_host.rs 逐段同构）
// ————————————————————————————————————————————————————————————————

/// 业务信封**原样透传**（含 ok:false 的门拒绝、无 ok 字段的裸对象如
/// list_tokens 的 colors 分组）——传输层只负责搬运与解析失败，业务语义由
/// 调用方判断。
fn envelope(json_str: &str) -> Result<Value, String> {
    serde_json::from_str(json_str).map_err(|e| format!("engine_result_parse:{e}"))
}

fn invoke_sync(fn_name: &str, mbt: &str, op: &str) -> Result<Value, String> {
    let engine = engine()?;
    // 中毒锁恢复：panic 源头是被毒化的实例状态，拿回锁并重建实例即为修复
    let mut poisoned = false;
    let mut guard = match engine.lock() {
        Ok(g) => g,
        Err(p) => {
            poisoned = true;
            p.into_inner()
        }
    };
    if poisoned || guard.memory.data(&guard.store).len() > MEMORY_RECYCLE_BYTES {
        // 生命周期阀：毒化实例 / 内存棘轮超阈值 → 整体重建（缓存按权威 mbt 键控，零语义影响）
        *guard = init().map_err(|e| format!("engine_rebuild_failed:{e}"))?;
    }
    // epoch deadline：本次调用的中断闹钟——看门狗每 tick 推进时钟，
    // 到点后 func.call 返回 Trap::Interrupt，wasm 帧被安全展开
    guard.store.set_epoch_deadline(
        (CALL_TIMEOUT.as_millis() / EPOCH_TICK_MS as u128 + 1) as u64,
    );
    let result = dispatch(&mut guard, fn_name, mbt, op);
    if let Err(msg) = &result {
        if msg.starts_with("engine_interrupted") {
            // 被中断的实例不再复用（毫秒级重建）：下一个调用立即恢复正常服务
            *guard = init().map_err(|e| format!("engine_rebuild_failed:{e}"))?;
        }
    }
    result
}

fn dispatch(e: &mut Engine, fn_name: &str, mbt: &str, op: &str) -> Result<Value, String> {
    match fn_name {
        // —— 宿主编排导出 ——
        "session_open" | "session_close" | "session_open_project_json" | "session_count" => {
            return Err(format!("host_orchestrated_fn:{fn_name}"));
        }
        "session_cache_stats" => {
            return Ok(json!({ "ok": true, "hits": e.hits, "misses": e.misses }));
        }
        "session_count_probe" => {
            let before = e.call_raw("session_count", &[])?;
            load_slot(e, "in_reset", "in_push", mbt)?;
            let h1 = e.call_raw("session_open_in", &[])?;
            // h1 已开：第二次装载/open 失败时必须先回收 h1（探针自身不做泄漏源）
            if let Err(err) = load_slot(e, "in_reset", "in_push", mbt) {
                let _ = e.call_raw("session_close", &[Val::I32(h1)]);
                return Err(err);
            }
            let h2 = match e.call_raw("session_open_in", &[]) {
                Ok(h) => h,
                Err(err) => {
                    let _ = e.call_raw("session_close", &[Val::I32(h1)]);
                    return Err(err);
                }
            };
            // 负句柄（引擎对非法输入的返回形态）同样不泄漏另一合法句柄
            match (h1 < 0, h2 < 0) {
                (false, false) => {}
                (true, false) => {
                    let _ = e.call_raw("session_close", &[Val::I32(h2)]);
                }
                (false, true) => {
                    let _ = e.call_raw("session_close", &[Val::I32(h1)]);
                }
                _ => {}
            }
            if h1 < 0 || h2 < 0 {
                return Err(format!("session_open_failed:{h1}/{h2}"));
            }
            let during = e.call_raw("session_count", &[])?;
            let _ = e.call_raw("session_close", &[Val::I32(h1)]);
            let _ = e.call_raw("session_close", &[Val::I32(h2)]);
            let after = e.call_raw("session_count", &[])?;
            return Ok(json!({ "ok": true, "before": before, "during": during, "after": after }));
        }
        _ => {}
    }

    // —— session API（mbt 键控缓存编排）——
    if fn_name.starts_with("session_") {
        // 先验证导出存在（未知 session_* 不得污染缓存计数、不得开真实会话）
        // （Instance 是 Copy 句柄：先复制再可变借用 store，避免借用交叠）
        let inst = e.instance;
        if inst.get_func(&mut e.store, fn_name).is_none() {
            return Err(format!("unknown_fn:{fn_name}"));
        }
        // 缓存：命中复用句柄；失配关旧开新（open 走 _in：mbt 经主槽）
        let cached = e.sess_cache.as_ref().map(|s| s.mbt == mbt);
        let handle = if cached == Some(true) {
            e.hits += 1;
            e.sess_cache.as_ref().expect("cached just checked").handle
        } else {
            e.misses += 1;
            evict_session(e);
            load_slot(e, "in_reset", "in_push", mbt)?;
            let h = e.call_raw("session_open_in", &[])?;
            if h < 0 {
                return Err(format!("session_open_failed:{h}"));
            }
            e.sess_cache = Some(Session { handle: h, mbt: mbt.to_string() });
            // 装载+open（全量解析）已消耗共享预算——后续业务 op 调用重置计时
            e.store.set_epoch_deadline(
                (CALL_TIMEOUT.as_millis() / EPOCH_TICK_MS as u128 + 1) as u64,
            );
            h
        };

        let parts: Vec<&str> = op.split_whitespace().filter(|s| !s.is_empty()).collect();
        if fn_name == "session_tap" && parts.len() < SESSION_TAP_MIN_ARGS {
            return Err(format!(
                "op_missing_args:{fn_name} 需要 {SESSION_TAP_MIN_ARGS} 个参数，得到 {}",
                parts.len()
            ));
        }
        let parse_xy = |s: Option<&&str>| -> Result<f64, String> {
            let raw = s.copied().unwrap_or("");
            raw.parse()
                .map_err(|_| format!("op_invalid_number:{fn_name} 的坐标参数 «{raw}» 不是数字"))
        };
        // `_in` 槽计划：参数文本进 arg/arg2 槽，handle/坐标走直参。
        // SlotPlan::None 的 session 导出（flows/benchmark/list_artboards/save/
        // library_snapshot）无文本入参，in_name 即经典名，直调。
        let (in_name, plan): (String, SlotPlan) = match fn_name {
            "session_apply_agent" | "session_apply_human" | "session_component_compile_b64" => {
                (fn_name.to_owned() + "_in", SlotPlan::Arg(op.to_string()))
            }
            "session_tap" => (
                "session_tap_in".to_string(),
                // op 形如 `tap <ab> <x> <y>`：artboard 走 arg 槽，x/y 是第 2/3 个 token
                SlotPlan::Tap(parse_xy(parts.get(1))?, parse_xy(parts.get(2))?, parts.first().copied().unwrap_or("").to_string()),
            ),
            "session_constrain" => (
                "session_constrain_in".to_string(),
                SlotPlan::Arg2(
                    parts.first().copied().unwrap_or("").to_string(),
                    parts.iter().skip(1).copied().collect::<Vec<_>>().join(" "),
                ),
            ),
            "session_lint" | "session_critique" | "session_spec" | "session_query_nodes"
            | "session_states" | "session_interactions" | "session_infer_page_type"
            | "session_infer_missing" | "session_extract_design_system"
            | "session_generate_responsive" | "session_export_svg" | "session_auto_fix"
            // M3：history（init/commit/log/undo/redo/checkout/diff）arg 槽 `<sub> [artboard]`
            // ——undo/redo 改文档，canonical 随 SESSION_MUTATING 前移
            | "session_history" => {
                (fn_name.to_owned() + "_in", SlotPlan::Arg(parts.join(" ")))
            }
            // 无文本入参（无 _in 变体）：经典直调。**显式枚举**——未来引擎新增
            // 带文本的 session 导出时，落到这里会得到明确错误而不是被当无文本
            // 误调出不透明 trap。（session_history 已 M3 路由入 Arg 组）
            "session_flows" | "session_benchmark" | "session_list_artboards"
            | "session_save" | "session_library_snapshot" => (fn_name.to_string(), SlotPlan::None),
            other => return Err(format!("unknown_session_fn:{other}")),
        };
        match &plan {
            SlotPlan::None => {}
            // 槽装载失败 = 引擎表现出异常 → 与业务调用 trap 同策略弃缓存
            SlotPlan::Arg(text) => load_slot(e, "arg_reset", "arg_push", text)
                .inspect_err(|_| evict_session(e))?,
            SlotPlan::Arg2(a, b) => {
                load_slot(e, "arg_reset", "arg_push", a).inspect_err(|_| evict_session(e))?;
                load_slot(e, "arg2_reset", "arg2_push", b).inspect_err(|_| evict_session(e))?;
            }
            SlotPlan::Tap(x, y, ab) => {
                load_slot(e, "arg_reset", "arg_push", ab).inspect_err(|_| evict_session(e))?;
                let mut vals = vec![Val::I32(handle), Val::F64(f64::to_bits(*x)), Val::F64(f64::to_bits(*y))];
                return finish_session_call(e, fn_name, &in_name, handle, &mut vals);
            }
        }
        return finish_session_call(e, fn_name, &in_name, handle, &mut vec![Val::I32(handle)]);
    }

    // —— 经典导出（文本入参走 in 槽 + _in 变体）/ 检视直调（无文本入参）——
    let n = arity(fn_name).ok_or_else(|| format!("unknown_fn:{fn_name}"))?;
    let (call_name, vals): (String, Vec<Val>) = match n {
        0 => (fn_name.to_string(), vec![]),
        1 => {
            load_slot(e, "in_reset", "in_push", mbt)
                .inspect_err(|_| evict_session(e))?;
            (fn_name.to_owned() + "_in", vec![])
        }
        _ => {
            // 无状态导出不触碰会话表，但装载/调用失败同样按保守姿态弃缓存
            load_slot(e, "in_reset", "in_push", mbt)
                .inspect_err(|_| evict_session(e))?;
            load_slot(e, "arg_reset", "arg_push", op)
                .inspect_err(|_| evict_session(e))?;
            (fn_name.to_owned() + "_in", vec![])
        }
    };
    // 与 session 路径对称：装载（大文档可达百万次 push）不蚕食业务调用的预算
    e.store.set_epoch_deadline(
        (CALL_TIMEOUT.as_millis() / EPOCH_TICK_MS as u128 + 1) as u64,
    );
    let out = match e.call_raw(&call_name, &vals).map(|ptr| e.read_str(ptr)) {
        Ok(s) => s,
        Err(trap) => {
            // 对齐 node 宿主的 blanket catch：无状态导出虽不触碰会话表，
            // 但实例已表现出异常——弃缓存是更保守的恢复姿态
            evict_session(e);
            return Err(trap);
        }
    };
    if out.is_empty() {
        evict_session(e);
        return Err("engine_corrupt_read:empty result".to_string());
    }
    envelope(&out)
}

/// session 调用的公共尾部：调 `_in`/经典导出 → 读串 → trap/腐坏读弃缓存。
/// `vals` 的首元素必须是 handle（Tap 计划里已带坐标直参）。
fn finish_session_call(
    e: &mut Engine,
    fn_name: &str,
    in_name: &str,
    handle: i32,
    vals: &mut Vec<Val>,
) -> Result<Value, String> {
    // 槽装载（大文档可达百万次 push）已消耗共享 deadline——业务调用前重设，
    // 恢复「30s 归业务调用」语义
    e.store.set_epoch_deadline(
        (CALL_TIMEOUT.as_millis() / EPOCH_TICK_MS as u128 + 1) as u64,
    );
    let out = match e.call_raw(in_name, vals) {
        Ok(ptr) => e.read_str(ptr),
        Err(trap) => {
            // trap 后会话状态不可信 → 弃缓存，下次按权威 mbt 重开
            evict_session(e);
            return Err(trap);
        }
    };
    // 腐坏读（空串=腐坏指针的 read_str 结果）：引擎状态不可信 → 弃缓存
    if out.is_empty() {
        evict_session(e);
        return Err("engine_corrupt_read:empty result".to_string());
    }

    if SESSION_MUTATING.contains(&fn_name) {
        let mut r: Value = match serde_json::from_str(&out) {
            Ok(v) => v,
            Err(_) => {
                // 信封非 JSON：引擎状态不可信 → 弃缓存，原样透传原始串错误
                evict_session(e);
                return Err(format!("engine_result_parse:{out}"));
            }
        };
        let committed_ok = r.get("ok").and_then(|x| x.as_bool()) == Some(true);
        if committed_ok {
            if let Some(m) = r.get("mbt").and_then(|x| x.as_str()) {
                if let Some(s) = e.sess_cache.as_mut() {
                    s.mbt = m.to_string();
                }
            }
        }
        // 同句柄补画板索引（内存查询，无重解析）。ok 且 data 是数组才补
        // （不伪造空数组掩盖引擎回归）；la 解析失败/读失败 → 弃缓存。
        match e.call_raw("session_list_artboards", &[Val::I32(handle)]).map(|p| e.read_str(p)) {
            Ok(la) => match serde_json::from_str::<Value>(&la) {
                Ok(la)
                    if la.get("ok").and_then(|x| x.as_bool()) == Some(true)
                        && committed_ok
                        && !r.is_null()
                        && la.get("data").is_some_and(|d| d.is_array()) =>
                {
                    r["artboards"] = la["data"].clone();
                    return Ok(r);
                }
                Ok(_) => {} // la 形状不符：不补，信封原样返回
                Err(_) => evict_session(e),
            },
            Err(_) => evict_session(e),
        }
    }
    envelope(&out)
}

/// `_in` 槽装载：reset → UTF-8 分块（每块 ≤4 字节，小端压入 u32 + 有效长度）。
/// 协议见引擎 wasm/main.mbt「写路径：分块字符串槽」。
fn load_slot(e: &mut Engine, reset_fn: &str, push_fn: &str, text: &str) -> Result<(), String> {
    e.call_raw(reset_fn, &[])?;
    let bytes = text.as_bytes();
    for chunk in bytes.chunks(SLOT_CHUNK) {
        let mut le = [0u8; SLOT_CHUNK];
        le[..chunk.len()].copy_from_slice(chunk);
        e.call_raw(push_fn, &[Val::I32(u32::from_le_bytes(le) as i32), Val::I32(chunk.len() as i32)])?;
    }
    Ok(())
}

/// 关闭当前缓存会话并弃置缓存（任何「引擎状态不可信」路径的统一出口）。
fn evict_session(e: &mut Engine) {
    if let Some(s) = e.sess_cache.take() {
        let _ = e.call_raw("session_close", &[Val::I32(s.handle)]);
    }
}

impl Engine {
    fn call_raw(&mut self, fn_name: &str, args: &[Val]) -> Result<i32, String> {
        let func = self
            .instance
            .get_func(&mut self.store, fn_name)
            .ok_or_else(|| format!("unknown_fn:{fn_name}"))?;
        // 槽协议的 reset/push 返回 Unit（0 结果）；业务导出返回 Int 指针/句柄
        if func.ty(&self.store).results().len() == 0 {
            return func
                .call(&mut self.store, args, &mut [])
                .map(|_| 0)
                .map_err(Self::trap_err);
        }
        let mut results = [Val::I32(0)];
        match func.call(&mut self.store, args, &mut results) {
            Ok(()) => Ok(results[0].i32().unwrap_or(0)),
            Err(err) => Err(Self::trap_err(err)),
        }
    }

    /// trap 分类：epoch 到点 → engine_interrupted（超时语义，invoke_sync 据此
    /// 重建实例）；其余 → wasm_panic（引擎腐坏，同样触发弃缓存/重建）。
    fn trap_err(err: wasmtime::Error) -> String {
        if err.downcast_ref::<wasmtime::Trap>().is_some_and(|t| *t == wasmtime::Trap::Interrupt) {
            "engine_interrupted:epoch deadline exceeded".into()
        } else {
            format!("wasm_panic:{err}")
        }
    }

    /// 引擎字符串指针解码：[len@ptr-4 & LEN_MASK][UTF-16LE@ptr+0]，
    /// 钳制到内存边界（腐坏指针/长度不再放大成巨型读取）。
    fn read_str(&self, ptr: i32) -> String {
        let ptr = ptr as usize;
        let data = self.memory.data(&self.store);
        if ptr < 4 || ptr > data.len() {
            return String::new();
        }
        let len = u32::from_le_bytes([data[ptr - 4], data[ptr - 3], data[ptr - 2], data[ptr - 1]])
            & LEN_MASK;
        let len = (len as usize).min((data.len() - ptr) / 2);
        let units: Vec<u16> = (0..len)
            .map(|i| u16::from_le_bytes([data[ptr + i * 2], data[ptr + i * 2 + 1]]))
            .collect();
        String::from_utf16_lossy(&units)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::PoisonError;

    /// 引擎门测试串行化（同桌面 agent.rs::ENGINE_TEST_GATE 语义）：宿主是
    /// 进程级常驻单例，缓存计数（hits/misses）与 epoch deadline 都是全局态，
    /// 各测试从已知状态开始（hard_reset 后串行执行）。
    static ENGINE_TEST_GATE: Mutex<()> = Mutex::new(());

    static ENGINE_TEST_SEQ: std::sync::Mutex<()> = std::sync::Mutex::new(());
    fn engine_test_seq() -> std::sync::MutexGuard<'static, ()> {
        ENGINE_TEST_SEQ.lock().unwrap_or_else(|p| p.into_inner())
    }
    fn engine_test_gate() -> std::sync::MutexGuard<'static, ()> {
        ENGINE_TEST_GATE.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// 最小种子文档（canonical 格式：frontmatter + 单画板 ```mbt 块）。
    /// 与 frontend/index.html::seedDoc / src-tauri/agent.rs::seed_doc 逐字对齐。
    fn seed_doc(id: &str, w: i64, h: i64) -> String {
        format!(
            "---\nmoonviz:\n  format: visual-document\n  revision: 1\n  entry: {id}\n---\n\n# {id}\n\n<!-- moonviz:artboard {id} -->\n```mbt\nfn visual_{id}() -> @decl.Prototype {{\n  let page = @decl.prototype(name=\"{id}\", width={w}.0, height={h}.0)\n  page\n}}\n```\n"
        )
    }

    fn b64(s: &str) -> String {
        BASE64.encode(s.as_bytes())
    }

    fn unb64(s: &str) -> String {
        String::from_utf8(BASE64.decode(s.as_bytes()).expect("b64 decode")).expect("utf8")
    }

    /// 契约 1——版本非空：version_info 信封 {ok, engine:"moonviz", version}，
    /// 真机探锚 `{"ok":true,"engine":"moonviz","version":"0.1.6-fix"}`。

    #[test]
    fn svg_text_probe() {
        let _seq = engine_test_seq();
        let _gate = engine_test_gate();
        let seed = b64(&seed_doc("sd", 390, 844));
        let r = apply_human_op(&seed, "template login wl 390 844").unwrap();
        let c = unb64(r["mbt_b64"].as_str().unwrap());
        let rd = render(&b64(&c)).unwrap();
        let arts = rd["artboards"].as_array().unwrap();
        for a in arts {
            let svg = a["svg"].as_str().unwrap_or("");
            println!("BOARD {} svg_len={} has_text_el={} has_text_content={}",
                a["id"], svg.len(), svg.contains("<text"), svg.contains("Welcome"));
        }
    }


    /// 契约 7（M3.5）——常驻 history 会话全链（hist_apply/hist_move）：模板→改色→
    /// 改文字 三连 op 栈累积；连续两次 undo 逐级回退（M3 缺陷回归锚：M3 每轮 init
    /// 重基线导致第二轮 undo 空转——本测试直接锁死）；redo 恢复；apply 门拒绝不推进栈。
    #[test]
    fn hist_session_continuous_flow() {
        let _seq = engine_test_seq();
        let _gate = engine_test_gate();
        hard_reset();
        let seed = b64(&seed_doc("sd", 390, 844));
        // op1：模板建板
        let r1 = hist_apply(&seed, "template login wl 390 844", "[\"wl\"]", "wl")
            .expect("hist_apply op1 必须送达");
        assert_eq!(r1["ok"], serde_json::json!(true), "{r1}");
        assert_eq!(r1["hist_rev"], serde_json::json!(1), "首 commit rev=1：{r1}");
        let c1 = unb64(r1["mbt_b64"].as_str().expect("op1 必须带 canonical"));
        assert!(c1.contains("wl"));
        // op2：改色
        let r2 = hist_apply(&b64(&c1), "update wl welcome_title text_color=#007aff", "[\"wl\"]", "wl")
            .expect("hist_apply op2 必须送达");
        assert_eq!(r2["ok"], serde_json::json!(true), "{r2}");
        assert_eq!(r2["hist_rev"], serde_json::json!(2), "次 commit rev=2：{r2}");
        let c2 = unb64(r2["mbt_b64"].as_str().expect("op2 必须带 canonical"));
        assert!(c2.contains("text_color=#007aff") || c2.contains("#007aff"), "canonical 应含改色：{c2}");
        // op3：改文字
        let r3 = hist_apply(&b64(&c2), "update wl welcome_title text=\"你好引擎\"", "[\"wl\"]", "wl")
            .expect("hist_apply op3 必须送达");
        assert_eq!(r3["hist_rev"], serde_json::json!(3), "三 commit rev=3：{r3}");
        let c3 = unb64(r3["mbt_b64"].as_str().expect("op3 必须带 canonical"));
        assert!(c3.contains("你好引擎"), "canonical 应含改文字：{c3}");
        // 连续两次 undo（M3.5 回归锚：第二轮必须仍回退）
        let u1 = hist_move("undo", "wl").expect("undo1 必须送达");
        let m1 = u1.get("mbt").and_then(|x| x.as_str()).expect("undo1 必须带 mbt");
        assert!(!m1.contains("你好引擎"), "undo1 应回退改文字：{m1}");
        assert!(m1.contains("#007aff"), "undo1 应停在改色态：{m1}");
        let u2 = hist_move("undo", "wl").expect("undo2 必须送达");
        let m2 = u2.get("mbt").and_then(|x| x.as_str()).expect("undo2 必须带 mbt");
        assert!(!m2.contains("你好引擎"), "undo2 不得含改文字：{m2}");
        assert!(!m2.contains("#007aff"), "undo2 应回退改色：{m2}");
        // redo 单步前移（标准栈语义：r1 →redo→ r2 改色态，不跳两级到 r3——
        // 初版断言误写「回到改文字态」，与引擎及常规 undo/redo 语义不符，已修正）
        let rd = hist_move("redo", "wl").expect("redo 必须送达");
        let mr = rd.get("mbt").and_then(|x| x.as_str()).expect("redo 必须带 mbt");
        assert!(mr.contains("#007aff"), "redo 应前移到改色态：{mr}");
        assert!(!mr.contains("你好引擎"), "redo 单步不得越过改色直达改文字：{mr}");
        // 再 undo（第三轮，跨 commit/undo/redo 混合后仍逐级）
        let u3 = hist_move("undo", "wl").expect("undo3 必须送达");
        let m3 = u3.get("mbt").and_then(|x| x.as_str()).expect("undo3 必须带 mbt");
        assert!(!m3.contains("你好引擎"), "undo3 应回退改文字：{m3}");
        // 门拒绝不推进栈：非法 op（节点不存在）→ ok:false，hist_rev 不变
        let rj = hist_apply(&b64(&unb64(u3["mbt_b64"].as_str().expect("undo3 必须带 b64"))),
            "update wl no_such_node text=\"x\"", "[\"wl\"]", "wl").expect("门拒绝信封必须送达");
        assert_eq!(rj["ok"], serde_json::json!(false), "非法 op 应门拒绝：{rj}");
        let u4 = hist_move("undo", "wl").expect("门拒绝后 undo 必须送达");
        let m4 = u4.get("mbt").and_then(|x| x.as_str()).expect("undo4 必须带 mbt");
        assert!(!m4.contains("你好引擎"), "门拒绝不得改变文档态：{m4}");
    }

    /// 契约 6（M3）——history 按板序列（桌面 histEnsure/histCommit 同构实测语义）：
    /// init 板 → apply → commit 板（rev 1）→ apply → commit 板（rev 2）→ undo 板
    /// （ok:true 且 canonical 回退，带 mbt_b64）→ redo 板（恢复）。逐板栈：init/commit/
    /// undo/redo 均须带板名（裸 commit 不入板栈、未 init 的板 undo 空转）。
    #[test]
    fn history_board_scoped_roundtrip() {
        let _seq = engine_test_seq();
        let _gate = engine_test_gate();
        let seed = b64(&seed_doc("sd", 390, 844));
        assert_eq!(
            history(&seed, "init sd").map(|v| v["ok"].clone()).unwrap_or_default(),
            serde_json::json!(true),
            "history init 板必须成功"
        );
        let r1 = apply_human_op(&seed, "template login wl 390 844").unwrap();
        let c1 = unb64(r1["mbt_b64"].as_str().expect("apply 必须带 canonical"));
        assert_eq!(
            history(&b64(&c1), "init wl").map(|v| v["ok"].clone()).unwrap_or_default(),
            serde_json::json!(true),
            "新板 init 必须 successful"
        );
        assert_eq!(
            history(&b64(&c1), "commit wl").map(|v| v["rev"].clone()).unwrap_or_default(),
            serde_json::json!(1),
            "首 commit rev 应为 1"
        );
        let r2 = apply_human_op(&b64(&c1), "update wl welcome_title text=\"HELLO\"").unwrap();
        let c2 = unb64(r2["mbt_b64"].as_str().expect("update 必须带 canonical"));
        assert!(c2.contains("HELLO"));
        assert_eq!(
            history(&b64(&c2), "commit wl").map(|v| v["rev"].clone()).unwrap_or_default(),
            serde_json::json!(2),
            "次 commit rev 应为 2"
        );
        let u = history(&b64(&c2), "undo wl").expect("undo 调用必须送达");
        assert_eq!(u["ok"], serde_json::json!(true));
        let m = u.get("mbt").and_then(|x| x.as_str()).expect("undo 必须带 mbt");
        assert!(!m.contains("HELLO"), "undo 应回退 HELLO：{m}");
        let ub = unb64(u["mbt_b64"].as_str().expect("undo 改文档面必须带 mbt_b64"));
        let rd = history(&b64(&ub), "redo wl").expect("redo 调用必须送达");
        let rm = rd.get("mbt").and_then(|x| x.as_str()).expect("redo 必须带 mbt");
        assert!(rm.contains("HELLO"), "redo 应回复 HELLO：{rm}");
    }
}
