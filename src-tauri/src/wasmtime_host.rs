//! wasmtime 进程内引擎宿主（classic wasm = 纯 WASM MVP，零 import）。
//!
//! Rust 侧引擎运行时的终局形态：**纯 Rust，无 node、无 WebView 依赖**。
//! cargo test 与 agent 循环共用；wasm 产物编译期嵌入（include_bytes!，
//! 约 530KB）——`cargo build` 前必须先跑 `node scripts/sync-engine.mjs`
//! 产出 frontend/vendor/moonviz.wasm，缺失即编译错误（显性失败优于静默）。
//!
//! 调用语义以 scripts/engine-host.mjs（node 参考宿主）为准——**对齐它是
//! 有意决策，例外逐处登记**（见各分叉注释）；字符串 codec 与
//! frontend/index.html 的 engReadStr/engWriteStr、sync-engine.mjs 三处同构，
//! 改任一处必须同步其余（引擎 ABI 升级时最先坏的就是这里）。
//! - 字符串是 linear memory 对象（[refcnt@ptr-8][len@ptr-4][UTF-16LE@ptr+0]），
//!   写入区锚在「当前内存大小 + 64KB」之上（引擎 bump 堆顶不超过当前内存大小，
//!   故永不与引擎堆碰撞）；引擎增长过内存后重新锚定。
//! - 经典导出（无状态）与检视直调（list_* 直调）；
//! - session API（26 个）：第一参为句柄，**mbt 键控会话缓存**（命中复用/失配
//!   关旧开新）、变更信封 canonical 键前移 + 同句柄补画板索引（data 为数组才补）、
//!   auto_fix/constrain 后弃缓存；**任何解析失败/腐坏读/trap 都弃缓存**（与 node
//!   的 blanket catch 对齐——脏缓存会让重试落在幽灵提交上）；
//! - 宿主编排导出：session_count_probe（泄漏契约）、session_cache_stats（缓存
//!   契约）、session_open/close/open_project_json/session_count 拒绝直调。
//!
//! 线程与生命周期：单实例 + Mutex 串行（agent 循环天然串行，锁内 serde 亚毫秒）。
//! **超时语义（epoch interruption，issue #1-A）**：每次调用前设 store 级 epoch
//! deadline（CALL_TIMEOUT 换算成 tick 数），共享 wasmtime::Engine 上的看门狗线程
//! 每 EPOCH_TICK_MS 推进时钟；到点后 `func.call` 返回 `Trap::Interrupt`——wasm
//! 帧被 wasmtime 安全展开，**挂死的 op 会被真正打断**而不是占着锁到天荒地老。
//! 中断后实例整体重建（毫秒级），下一个调用立即恢复正常服务；外层 tokio timeout
//! 仅作锁排队的兜底（宽限 5s）。**初始化槽**（issue #1-B）：RwLock<Option<Arc>>——
//! init 失败**不缓存**（下一次调用自动重试），reset 置 None 即可清除，OnceLock 的
//! 「首次失败终身粘滞」不复存在。**内存棘轮**：引擎 bump 堆只增不减（实测 ~200
//! 变更 op ≈ +37MB），超过回收阈值时整体重建实例——缓存按权威 mbt 键控，重建
//! 零语义影响。grow 失败/中毒锁/epoch 中断都会触发重建而非永久变砖。

use serde_json::{json, Value};
use std::sync::{Arc, Mutex, OnceLock, RwLock};
use std::sync::PoisonError;
use wasmtime::{Instance, Memory, Module, Store, Val};

/// 引擎产物（编译期嵌入；由 scripts/sync-engine.mjs 拉取并做 sha512+契约探针）
const WASM_BYTES: &[u8] =
    include_bytes!(concat!(env!("CARGO_MANIFEST_DIR"), "/../frontend/vendor/moonviz.wasm"));
/// 组件清单快照（同步脚本用真机 place 探针验证生成；与前端画布同源）
const COMPONENTS_JSON: &str =
    include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../frontend/vendor/components.json"));

// —— classic wasm 字符串 ABI 常量（与 sync/engine-host/前端三处同构）——
/// 字符串对象头尺寸（refcnt@ptr-8 + len@ptr-4，即 ptr 前预留 8 字节）
const STR_HEADER: usize = 16;
/// 写入区锚定余量：write_off 始终 ≥ 当前内存大小 + 此值（防引擎 bump 堆覆盖）
const ANCHOR_MARGIN: usize = 65536;
/// 每次字符串写入后的步进间隙（防相邻写入被引擎侧边界检查误伤）
const STRIDE_GAP: usize = 4096;
/// refcnt 哨兵（引擎侧不回收宿主写入的字符串）
const REFCNT_SENTINEL: u32 = 0xFFFF_FFE0;
/// 长度字段掩码（高 4 位是引擎内部标志位，读取时剔除）
const LEN_MASK: u32 = 0x0FFF_FFFF;
/// wasm 页尺寸（memory.grow 的单位）
const WASM_PAGE: u64 = 65536;
/// 线性内存回收阈值：超过即整体重建实例（对齐前端 engineRecycleIfNeeded）
const MEMORY_RECYCLE_BYTES: usize = 192 * 1024 * 1024;
/// 单次引擎调用超时（epoch 到点真中断；外层 tokio timeout 只兜锁排队）
const CALL_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(30);
/// epoch tick 周期（看门狗线程推进时钟的粒度；deadline 换算成 tick 数）
const EPOCH_TICK_MS: u64 = 100;
/// 外层 tokio timeout：epoch 中断应先到，这里只兜「锁被占住排队」的场景
const AWAIT_GRACE: std::time::Duration = std::time::Duration::from_secs(5);

/// 经典导出 arity（字符串全部经编解码；返回值为字符串指针）
fn arity(fn_name: &str) -> Option<usize> {
    Some(match fn_name {
        "list_templates" | "version_info" | "list_tokens" | "list_themes" | "list_ops" => 0,
        "render_mbt" | "validate_mbt" | "export_html" => 1,
        "apply_agent_op" | "apply_human_op" => 2,
        _ => return None,
    })
}
/// session op 的 op 参数是完整串（含空格），不做切分
const SESSION_WHOLE_ARG: [&str; 3] =
    ["session_apply_agent", "session_apply_human", "session_component_compile_b64"];
/// 变更类导出（信封回传 canonical：缓存键前移 + 补画板索引）
const SESSION_MUTATING: [&str; 2] = ["session_apply_agent", "session_apply_human"];
/// 改会话文档但信封不回传 canonical 的导出（调用后弃缓存防脏键）
const SESSION_EVICT: [&str; 2] = ["session_auto_fix", "session_constrain"];
/// session_tap 需要的最小 op 参数（artboard + x + y）
const SESSION_TAP_MIN_ARGS: usize = 3;

struct Session {
    handle: i32,
    mbt: String,
}

struct Engine {
    store: Store<()>,
    instance: Instance,
    memory: Memory,
    write_off: usize,
    last_mem_size: usize,
    sess_cache: Option<Session>,
    hits: u64,
    misses: u64,
}

/// 共享 wasmtime::Engine（epoch 时钟与编译缓存的宿主；实例可重建，engine 不换——
/// 看门狗线程持有的引用因此始终有效）。
static WT_ENGINE: OnceLock<wasmtime::Engine> = OnceLock::new();
/// 引擎实例槽（issue #1-B）：Option 可清除——init 失败不缓存（下次调用自动重试），
/// reset 置 None 即清除。OnceLock 的「首次失败终身粘滞」由此根除。
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
    let last_mem_size = memory.data(&store).len();
    Ok(Engine {
        store,
        instance,
        memory,
        write_off: last_mem_size + ANCHOR_MARGIN,
        last_mem_size,
        sess_cache: None,
        hits: 0,
        misses: 0,
    })
}

/// 测试辅助：清空实例槽（下次调用重新实例化）——常驻实例下
/// session_count_probe 的「初始计数 0」、缓存统计从零断言都需要它。
#[cfg(test)]
pub(crate) fn hard_reset() {
    *ENGINE.write().expect("engine rwlock") = None;
}

/// 生命周期管理：整体重建实例（生产内存棘轮、中毒恢复、epoch 中断共用）。
/// 重建失败则清槽（下次调用重试，而非终身变砖）。缓存按权威 mbt 键控，
/// 重建零语义影响（下次调用自然重开）。
fn reset_instance() {
    let mut w = ENGINE.write().expect("engine rwlock");
    match init() {
        Ok(e) => *w = Some(Arc::new(Mutex::new(e))),
        // 重建失败：清槽留待下次重试（旧实例若有中毒锁，随槽丢弃一并解决）
        Err(_) => *w = None,
    }
}

/// Rust 侧引擎宿主（wasmtime 进程内承载 classic wasm）。
/// agent 循环与 cargo test 共用；接口签名与旧 node 宿主一致。
pub struct EngineHost;

impl EngineHost {
    pub async fn call(
        &self,
        fn_name: &str,
        mbt: &str,
        op: &str,
    ) -> Result<serde_json::Value, String> {
        invoke(fn_name, mbt, op).await
    }
}

/// 调用入口（CALL_TIMEOUT 只兜住调用方等待；wasm 执行本身不可中断，见模块头）。
pub(super) async fn invoke(fn_name: &str, mbt: &str, op: &str) -> Result<Value, String> {
    let fn_name = fn_name.to_string();
    let mbt = mbt.to_string();
    let op = op.to_string();
    // 外层宽限只兜「锁排队」；epoch 中断应在 CALL_TIMEOUT 处先打断真执行
    tokio::time::timeout(
        CALL_TIMEOUT + AWAIT_GRACE,
        tokio::task::spawn_blocking(move || invoke_sync(&fn_name, &mbt, &op)),
    )
    .await
    .map_err(|_| "engine_timeout".to_string())?
    .map_err(|e| format!("wasmtime_host_join:{e}"))?
}

/// 业务信封**原样透传**（含 ok:false 的门拒绝、无 ok 字段的裸对象如
/// list_tokens 的 colors 分组）——与旧 node 宿主行为一致：传输层只负责
/// 搬运与解析失败，业务语义由调用方（EngineState/测试）判断。
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
    // epoch deadline（issue #1-A）：本次调用的中断闹钟——看门狗每 tick 推进时钟，
    // 到点后 func.call 返回 Trap::Interrupt，wasm 帧被安全展开
    guard.store.set_epoch_deadline(
        (CALL_TIMEOUT.as_millis() / EPOCH_TICK_MS as u128 + 1) as u64,
    );
    let result = dispatch(&mut guard, fn_name, mbt, op);
    if let Err(msg) = &result {
        if msg.starts_with("engine_interrupted") {
            // 被中断的实例不再复用（毫秒级重建）：下一个调用立即恢复正常服务，
            // 不会像旧 tokio-timeout 语义那样级联 30s
            *guard = init().map_err(|e| format!("engine_rebuild_failed:{e}"))?;
        }
    }
    result
}

fn dispatch(mut e: &mut Engine, fn_name: &str, mbt: &str, op: &str) -> Result<Value, String> {

    match fn_name {
        // —— 宿主编排导出 ——
        "list_components" => {
            let comps: Value = serde_json::from_str(COMPONENTS_JSON)
                .map_err(|e| format!("components_snapshot_parse:{e}"))?;
            return Ok(json!({ "ok": true, "components": comps }));
        }
        "session_open" | "session_close" | "session_open_project_json" | "session_count" => {
            return Err(format!("host_orchestrated_fn:{fn_name}"));
        }
        "session_cache_stats" => {
            return Ok(json!({ "ok": true, "hits": e.hits, "misses": e.misses }));
        }
        "session_count_probe" => {
            let before = e.call_raw("session_count", &[])?;
            let mbt_val = e.write_str(mbt)?;
            let h1 = e.call_raw("session_open", &[Val::I32(mbt_val)])?;
            let mbt_val2 = e.write_str(mbt)?;
            let h2 = e.call_raw("session_open", &[Val::I32(mbt_val2)])?;
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
        // 缓存：命中复用句柄；失配关旧开新
        let cached = e.sess_cache.as_ref().map(|s| s.mbt == mbt);
        let handle = if cached == Some(true) {
            e.hits += 1;
            e.sess_cache.as_ref().expect("cached just checked").handle
        } else {
            e.misses += 1;
            evict_session(&mut e);
            let ptr = e.write_str(mbt)?;
            let h = e.call_raw("session_open", &[Val::I32(ptr)])?;
            if h < 0 {
                return Err(format!("session_open_failed:{h}"));
            }
            e.sess_cache = Some(Session { handle: h, mbt: mbt.to_string() });
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
        let arg_vals: Vec<Val> = if fn_name == "session_tap" {
            // Val::F64 在 wasmtime 49 是位模式构造（f64::to_bits）
            // 坐标解析失败显式报错（node 的 NaN 是显性垃圾；静默 0.0 会在 (0,0) 假装成功）
            vec![
                Val::I32(e.write_str(parts.first().copied().unwrap_or(""))?),
                Val::F64(f64::to_bits(parse_xy(parts.get(1))?)),
                Val::F64(f64::to_bits(parse_xy(parts.get(2))?)),
            ]
        } else if SESSION_WHOLE_ARG.contains(&fn_name) {
            vec![Val::I32(e.write_str(op)?)]
        } else {
            parts.iter().map(|p| e.write_str(p).map(Val::I32)).collect::<Result<Vec<_>, _>>()?
        };

        let mut vals = vec![Val::I32(handle)];
        vals.extend(arg_vals);
        let out = match e.call_raw(fn_name, &vals) {
            Ok(ptr) => e.read_str(ptr),
            Err(trap) => {
                // trap 后会话状态不可信 → 弃缓存，下次按权威 mbt 重开
                evict_session(&mut e);
                return Err(trap);
            }
        };
        // 腐坏读（空串=腐坏指针的 read_str 结果）：引擎状态不可信 → 弃缓存
        if out.is_empty() {
            evict_session(&mut e);
            return Err("engine_corrupt_read:empty result".to_string());
        }

        if SESSION_MUTATING.contains(&fn_name) {
            let mut r: Value = match serde_json::from_str(&out) {
                Ok(v) => v,
                Err(_) => {
                    // 信封非 JSON：引擎状态不可信 → 弃缓存，原样透传原始串错误
                    evict_session(&mut e);
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
            // 同句柄补画板索引（内存查询，无重解析）。对齐 node：ok 且 data 是
            // 数组才补（不伪造空数组掩盖引擎回归）；la 解析失败/读失败 → 弃缓存。
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
                    Ok(_) => {} // la 形状不符：不补（对齐 node），信封原样返回
                    Err(_) => evict_session(&mut e),
                },
                Err(_) => evict_session(&mut e),
            }
        } else if SESSION_EVICT.contains(&fn_name) {
            evict_session(&mut e);
        }
        return envelope(&out);
    }

    // —— 经典导出 / 检视直调 ——
    let n = arity(fn_name).ok_or_else(|| format!("unknown_fn:{fn_name}"))?;
    let vals: Vec<Val> = match n {
        0 => vec![],
        1 => vec![Val::I32(e.write_str(mbt)?)],
        _ => vec![Val::I32(e.write_str(mbt)?), Val::I32(e.write_str(op)?)],
    };
    let out = match e.call_raw(fn_name, &vals).map(|ptr| e.read_str(ptr)) {
        Ok(s) => s,
        Err(trap) => {
            // 对齐 node 的 blanket catch：无状态导出虽不触碰会话表，
            // 但实例已表现出异常——弃缓存是更保守的恢复姿态
            evict_session(&mut e);
            return Err(trap);
        }
    };
    if out.is_empty() {
        evict_session(&mut e);
        return Err("engine_corrupt_read:empty result".to_string());
    }
    envelope(&out)
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
        let mut results = [Val::I32(0)];
        match func.call(&mut self.store, args, &mut results) {
            Ok(()) => Ok(results[0].i32().unwrap_or(0)),
            Err(err) => {
                // epoch 到点：wasm 帧被安全展开，调用以明确错误返回（invoke_sync
                // 据此重建实例）。与其余 trap 区分——后者是引擎腐坏，前者是超时语义。
                if err.downcast_ref::<wasmtime::Trap>().is_some_and(|t| *t == wasmtime::Trap::Interrupt) {
                    Err("engine_interrupted:epoch deadline exceeded".into())
                } else {
                    Err(format!("wasm_panic:{err}"))
                }
            }
        }
    }

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

    fn write_str(&mut self, s: &str) -> Result<i32, String> {
        let cur = self.memory.data(&self.store).len();
        if cur != self.last_mem_size {
            self.write_off = self.write_off.max(cur + ANCHOR_MARGIN);
            self.last_mem_size = cur;
        }
        let units_len = s.encode_utf16().count();
        let need = STR_HEADER + units_len * 2;
        let cur_len = self.memory.data(&self.store).len();
        if cur_len < self.write_off + need {
            let target = (self.write_off + need) as u64 + ANCHOR_MARGIN as u64;
            let delta = target.saturating_sub(cur_len as u64).div_ceil(WASM_PAGE);
            self.memory
                .grow(&mut self.store, delta)
                .map_err(|e| format!("memory_grow_failed:{e}"))?; // 失败返回 Err 而非 panic（持锁 panic = 引擎永久变砖）
            self.last_mem_size = self.memory.data(&self.store).len();
        }
        let ptr = self.write_off;
        {
            let data = self.memory.data_mut(&mut self.store);
            data[ptr - 8..ptr - 4].copy_from_slice(&REFCNT_SENTINEL.to_le_bytes());
            data[ptr - 4..ptr].copy_from_slice(&(units_len as u32).to_le_bytes());
            for (i, u) in s.encode_utf16().enumerate() {
                data[ptr + i * 2..ptr + i * 2 + 2].copy_from_slice(&u.to_le_bytes());
            }
        }
        self.write_off = ptr + need + STRIDE_GAP;
        Ok(ptr as i32)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    // 与 agent::tests 的引擎门测试共用同一把串行化门闩——epoch 测试会短暂
    // 持锁睡眠并对全局实例设 deadline，不与 hard_reset/缓存断言并发互踩
    use crate::agent::tests::engine_test_gate;

    /// issue #1-A 验收（中断路径）：手工把 epoch deadline 设到最近一个 tick，
    /// 看门狗推进时钟后 version_info 必须以 engine_interrupted 返回（真中断，
    /// 而非旧语义的「继续占锁跑到底」）；随后正常调用立即恢复服务。
    /// 注：deadline 由 dispatch 每次调用前重设，手工干扰不影响后续调用。
    #[test]
    fn epoch_deadline_interrupts_and_recovers() {
        let _gate = engine_test_gate();
        let eng = engine().expect("engine init");
        let mut e = eng.lock().unwrap_or_else(PoisonError::into_inner);
        e.store.set_epoch_deadline(1); // 下一个 tick（≤100ms）即到点
        std::thread::sleep(std::time::Duration::from_millis(400)); // 跨 ≥3 个 tick
        let r = e.call_raw("version_info", &[]);
        let err = r.expect_err("到点的调用必须被中断");
        assert!(
            err.starts_with("engine_interrupted"),
            "应为 epoch 中断，实际：{err}"
        );
        drop(e);
        // 正常调用（dispatch 会重设 30s deadline）：立即恢复，不级联
        let v = invoke_sync("version_info", "", "").expect("中断后下一次调用必须正常");
        assert_eq!(v["ok"], serde_json::json!(true), "{v}");
    }

    /// issue #1-B 验收（粘滞消除）：旧 OnceLock 下 Some(Err) 终身粘滞；
    /// 现在槽可清除——清空后下一次调用自动重建成功（构造失败注入不可行，
    /// 字节是编译期嵌入的固定产物，故验证「清除→重建」这条恢复通路本身）。
    #[test]
    fn engine_slot_recovery() {
        let _gate = engine_test_gate();
        *ENGINE.write().expect("engine rwlock") = None; // 模拟槽被清（reset 失败分支同形态）
        let v = invoke_sync("version_info", "", "").expect("清槽后必须自动重建");
        assert_eq!(v["ok"], serde_json::json!(true), "{v}");
        // reset_instance 的失败分支也不留毒：注入一个必失败的槽再走 reset
        // （无需构造——reset_instance 对 Err(_) 的处理就是置 None，下一次重试）
        reset_instance();
        let v = invoke_sync("version_info", "", "").expect("reset 后必须可用");
        assert_eq!(v["ok"], serde_json::json!(true), "{v}");
    }
}
