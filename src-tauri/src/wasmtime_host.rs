//! wasmtime 进程内引擎宿主（classic wasm = 纯 WASM MVP，零 import）。
//!
//! Rust 侧引擎运行时的终局形态：**纯 Rust，无 node、无 WebView 依赖**。
//! cargo test 与 agent 循环共用；wasm 产物编译期嵌入（include_bytes!，
//! 约 530KB）——`cargo build` 前必须先跑 `node scripts/sync-engine.mjs`
//! 产出 frontend/vendor/moonviz.wasm，缺失即编译错误（显性失败优于静默）。
//!
//! 调用语义与 scripts/engine-host.mjs（node 参考宿主）1:1：
//! - 字符串是 linear memory 对象（[refcnt@ptr-8][len@ptr-4][UTF-16LE@ptr+0]），
//!   写入区锚在「当前内存大小 + 64KB」之上（引擎 bump 堆顶不超过当前内存大小，
//!   故永不与引擎堆碰撞）；引擎增长过内存后重新锚定。
//! - 经典导出（无状态）与检视直调（list_* 直调）；
//! - session API（26 个）：第一参为句柄，**mbt 键控会话缓存**（命中复用/失配
//!   关旧开新）、变更信封 canonical 前移 + 同句柄补画板索引、auto_fix/constrain
//!   后弃缓存、wasm trap 后弃缓存；
//! - 宿主编排导出：session_count_probe（泄漏契约）、session_cache_stats（缓存
//!   契约）、session_open/close/open_project_json/session_count 拒绝直调。
//!
//! 线程模型：V8 isolate 换成 wasmtime 后一样——单实例 + Mutex 串行，
//! 调用统一走 spawn_blocking（引擎单 op 毫秒级）。wasm trap 可恢复（实例
//! 状态不因 trap 损坏），无需重启进程。

use serde_json::{json, Value};
use std::sync::{Mutex, OnceLock};
use wasmtime::{Instance, Memory, Module, Store, Val};

/// 引擎产物（编译期嵌入；由 scripts/sync-engine.mjs 拉取并做 sha512+契约探针）
const WASM_BYTES: &[u8] =
    include_bytes!(concat!(env!("CARGO_MANIFEST_DIR"), "/../frontend/vendor/moonviz.wasm"));
/// 组件清单快照（同步脚本用真机 place 探针验证生成；与前端画布同源）
const COMPONENTS_JSON: &str =
    include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../frontend/vendor/components.json"));

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
const SESSION_MIN_ARGS: u8 = 3; // 仅 session_tap（str + f64 + f64）；其余 0/1 参皆合法

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

static ENGINE: OnceLock<Result<Mutex<Engine>, String>> = OnceLock::new();

fn engine() -> Result<&'static Mutex<Engine>, String> {
    match ENGINE.get() {
        Some(Ok(m)) => Ok(m),
        Some(Err(e)) => Err(e.clone()),
        None => {
            let built = init().map(Mutex::new);
            let _ = ENGINE.set(built);
            match ENGINE.get().expect("just set") {
                Ok(m) => Ok(m),
                Err(e) => Err(e.clone()),
            }
        }
    }
}

fn init() -> Result<Engine, String> {
    let engine = wasmtime::Engine::default();
    let module = Module::new(&engine, WASM_BYTES)
        .map_err(|e| format!("wasm_compile:{e}（产物损坏？重跑 node scripts/sync-engine.mjs）"))?;
    let mut store = Store::new(&engine, ());
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
        write_off: last_mem_size + 65536,
        last_mem_size,
        sess_cache: None,
        hits: 0,
        misses: 0,
    })
}

/// 测试辅助：丢弃整个实例（下次调用重新实例化）——常驻实例下
/// session_count_probe 的「初始计数 0」、缓存统计从零断言都需要它。
#[cfg(test)]
pub(crate) fn hard_reset() {
    if let Some(Ok(m)) = ENGINE.get() {
        if let Ok(mut guard) = m.lock() {
            *guard = init().expect("hard_reset: 重新实例化失败");
        }
    }
}

impl Engine {
    fn call_raw(&mut self, fn_name: &str, args: &[Val]) -> Result<i32, String> {
        let func = self
            .instance
            .get_func(&mut self.store, fn_name)
            .ok_or_else(|| format!("unknown_fn:{fn_name}"))?;
        let mut results = [Val::I32(0)];
        func.call(&mut self.store, args, &mut results)
            .map_err(|e| format!("wasm_panic:{e}"))?;
        Ok(results[0].i32().unwrap_or(0))
    }

    fn read_str(&self, ptr: i32) -> String {
        let ptr = ptr as usize;
        let data = self.memory.data(&self.store);
        if ptr < 4 || ptr > data.len() {
            return String::new();
        }
        let len = u32::from_le_bytes([data[ptr - 4], data[ptr - 3], data[ptr - 2], data[ptr - 1]])
            & 0x0FFF_FFFF;
        let len = (len as usize).min((data.len() - ptr) / 2);
        let units: Vec<u16> = (0..len)
            .map(|i| u16::from_le_bytes([data[ptr + i * 2], data[ptr + i * 2 + 1]]))
            .collect();
        String::from_utf16_lossy(&units)
    }

    fn write_str(&mut self, s: &str) -> i32 {
        let cur = self.memory.data(&self.store).len();
        if cur != self.last_mem_size {
            self.write_off = self.write_off.max(cur + 65536);
            self.last_mem_size = cur;
        }
        let units: Vec<u16> = s.encode_utf16().collect();
        let need = 16 + units.len() * 2;
        if self.memory.data(&self.store).len() < self.write_off + need {
            let delta = (self.write_off + need + 65536 - self.memory.data(&self.store).len())
                .div_ceil(65536) as u64;
            self.memory
                .grow(&mut self.store, delta)
                .expect("memory grow");
            self.last_mem_size = self.memory.data(&self.store).len();
        }
        let ptr = self.write_off;
        {
            let data = self.memory.data_mut(&mut self.store);
            // refcnt 写 0xFFFFFFE0（对齐 node 宿主；引擎侧不回收宿主写入的字符串）
            data[ptr - 8..ptr - 4].copy_from_slice(&0xFFFF_FFE0u32.to_le_bytes());
            data[ptr - 4..ptr].copy_from_slice(&(units.len() as u32).to_le_bytes());
            for (i, u) in units.iter().enumerate() {
                data[ptr + i * 2..ptr + i * 2 + 2].copy_from_slice(&u.to_le_bytes());
            }
        }
        self.write_off = ptr + need + 4096;
        ptr as i32
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

/// 供 lib.rs::EngineHost 委托的调用入口（30s 超时兜底；EngineState::call 外层还有一层）。
pub(super) async fn invoke(fn_name: &str, mbt: &str, op: &str) -> Result<Value, String> {
    let fn_name = fn_name.to_string();
    let mbt = mbt.to_string();
    let op = op.to_string();
    tokio::time::timeout(
        std::time::Duration::from_secs(30),
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
    let mut e = engine.lock().map_err(|_| "engine_poisoned".to_string())?;

    // —— 宿主编排导出 ——
    if fn_name == "list_components" {
        let comps: Value = serde_json::from_str(COMPONENTS_JSON)
            .map_err(|e| format!("components_snapshot_parse:{e}"))?;
        return Ok(json!({ "ok": true, "components": comps }));
    }
    if matches!(
        fn_name,
        "session_open" | "session_close" | "session_open_project_json" | "session_count"
    ) {
        return Err(format!("host_orchestrated_fn:{fn_name}"));
    }
    if fn_name == "session_cache_stats" {
        return Ok(json!({ "ok": true, "hits": e.hits, "misses": e.misses }));
    }
    if fn_name == "session_count_probe" {
        let before = e.call_raw("session_count", &[])?;
        let mbt_val = e.write_str(mbt);
        let h1 = e.call_raw("session_open", &[Val::I32(mbt_val)])?;
        let mbt_val2 = e.write_str(mbt);
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

    // —— session API（mbt 键控缓存编排）——
    if fn_name.starts_with("session_") {
        // 缓存：命中复用句柄；失配关旧开新（先判断后取值，避免借用交叠）
        let cached = e.sess_cache.as_ref().map(|s| s.mbt == mbt);
        let handle = if cached == Some(true) {
            e.hits += 1;
            e.sess_cache.as_ref().expect("cached just checked").handle
        } else {
            e.misses += 1;
            if let Some(old) = e.sess_cache.take() {
                let _ = e.call_raw("session_close", &[Val::I32(old.handle)]);
            }
            let ptr = e.write_str(mbt);
            let h = e.call_raw("session_open", &[Val::I32(ptr)])?;
            if h < 0 {
                return Err(format!("session_open_failed:{h}"));
            }
            e.sess_cache = Some(Session { handle: h, mbt: mbt.to_string() });
            h
        };

        let parts: Vec<&str> = op.split_whitespace().filter(|s| !s.is_empty()).collect();
        if fn_name == "session_tap" && parts.len() < SESSION_MIN_ARGS as usize {
            return Err(format!(
                "op_missing_args:{fn_name} 需要 {SESSION_MIN_ARGS} 个参数，得到 {}",
                parts.len()
            ));
        }
        let arg_vals: Vec<Val> = if fn_name == "session_tap" {
            // Val::F64 在 wasmtime 49 是位模式构造（f64::to_bits）
            vec![
                Val::I32(e.write_str(parts.first().copied().unwrap_or(""))),
                Val::F64(f64::to_bits(parts.get(1).and_then(|s| s.parse().ok()).unwrap_or(0.0))),
                Val::F64(f64::to_bits(parts.get(2).and_then(|s| s.parse().ok()).unwrap_or(0.0))),
            ]
        } else if SESSION_WHOLE_ARG.contains(&fn_name) {
            vec![Val::I32(e.write_str(op))]
        } else {
            parts.iter().map(|p| Val::I32(e.write_str(p))).collect()
        };

        let mut vals = vec![Val::I32(handle)];
        vals.extend(arg_vals);
        let out = match e.call_raw(fn_name, &vals) {
            Ok(ptr) => e.read_str(ptr),
            Err(trap) => {
                // trap 后会话状态不可信 → 弃缓存，下次按权威 mbt 重开
                if let Some(s) = e.sess_cache.take() {
                    let _ = e.call_raw("session_close", &[Val::I32(s.handle)]);
                }
                return Err(trap);
            }
        };

        if SESSION_MUTATING.contains(&fn_name) {
            let mut r: Value = serde_json::from_str(&out).unwrap_or(Value::Null);
            let committed_ok = r.get("ok").and_then(|x| x.as_bool()) == Some(true);
            if committed_ok {
                if let Some(m) = r.get("mbt").and_then(|x| x.as_str()) {
                    if let Some(s) = e.sess_cache.as_mut() {
                        s.mbt = m.to_string();
                    }
                }
            }
            // 同句柄补画板索引（内存查询，无重解析）；best-effort——失败不得把
            // 已提交的 op 报成失败，但 trap 后会话不可信 → 弃缓存
            match e.call_raw("session_list_artboards", &[Val::I32(handle)]).map(|p| e.read_str(p)) {
                Ok(la) => {
                    if let Ok(la) = serde_json::from_str::<Value>(&la) {
                        if la.get("ok").and_then(|x| x.as_bool()) == Some(true)
                            && committed_ok
                            && !r.is_null()
                        {
                            r["artboards"] = la.get("data").cloned().unwrap_or(json!([]));
                            return envelope(&r.to_string()).or_else(|_| envelope(&out));
                        }
                    }
                }
                Err(_) => {
                    if let Some(s) = e.sess_cache.take() {
                        let _ = e.call_raw("session_close", &[Val::I32(s.handle)]);
                    }
                }
            }
        } else if SESSION_EVICT.contains(&fn_name) {
            if let Some(s) = e.sess_cache.take() {
                let _ = e.call_raw("session_close", &[Val::I32(s.handle)]);
            }
        }
        return envelope(&out);
    }

    // —— 经典导出 / 检视直调 ——
    let n = arity(fn_name).ok_or_else(|| format!("unknown_fn:{fn_name}"))?;
    let vals: Vec<Val> = match n {
        0 => vec![],
        1 => vec![Val::I32(e.write_str(mbt))],
        _ => vec![Val::I32(e.write_str(mbt)), Val::I32(e.write_str(op))],
    };
    let ptr = e.call_raw(fn_name, &vals)?;
    envelope(&e.read_str(ptr))
}
