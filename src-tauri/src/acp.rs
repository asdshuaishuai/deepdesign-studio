//! ACP（Agent Client Protocol）外部智能体 CLI 接入。
//!
//! 参考姊妹项目 NoNDesign 的 server/acp_bridge.py（用户决策 2026-11-17：借协议与
//! 交互形态，不搬 Python 栈）。零新依赖：ACP 线格式就是 **newline-delimited
//! JSON-RPC**（NoNDesign step_adapter 实证「与 acp SDK 的 stdio framing 一致」），
//! Rust 侧 BufReader::lines + serde_json 自实现。
//!
//! 范围（对标 NoNDesign MVP 并按用户决策补齐）：
//! - 12 项 CLI 目录（claude-code / codex / gemini / qwen / pi / stepcode / dsh /
//!   mcode / kimi / omp / solon + pivot 占位灰），npx 适配器回退
//! - 探测：轻量 argv 查找（秒回）+ 完整握手（initialize → session/new，可显式触发）
//! - 会话：cwd=宿主隔离工作区（canonical 先导出为 mbt.md，DDP 仍是唯一事实源）
//! - 事件：session/update → 与内置 agent-event 同通道（run id 由 sink 闭包注入），
//!   轨迹时间线零改动复用
//! - 权限：request_permission 全量升级为前端确认框（2026-11-17 用户决策，
//!   非 NoNDesign 的自动放行 MVP）；等待期 prompt 挂起（response 在应答后才回）
//! - fs 回调：路径必须落在工作区内，越界即 PermissionError
//! - prompt 终止：读回工作区 mbt.md → EngineHost validate+render → 合成与内置
//!   同形状的终态信封（done 事件）——外接 agent 的修改真正落画布

use serde_json::{json, Value};
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{mpsc, Arc, Mutex};
use std::time::Duration;

// ---------------------------------------------------------------------------
// 目录与探测
// ---------------------------------------------------------------------------

pub struct AcpAgentDef {
    pub id: &'static str,
    pub name: &'static str,
    /// 候选启动 argv（按序探测；含 npx 适配器回退）
    pub candidates: &'static [&'static [&'static str]],
    /// 目录占位（coming soon）——不可选
    pub grayed: bool,
}

/// 12 项目录（对齐 NoNDesign AGENT_CATALOG 同名单）
pub static AGENT_CATALOG: [AcpAgentDef; 12] = [
    AcpAgentDef { id: "qwen", name: "Qwen Code", candidates: &[&["qwen", "--experimental-acp"]], grayed: false },
    AcpAgentDef { id: "pi", name: "Pi", candidates: &[&["pi", "acp"], &["pi-acp"], &["npx", "-y", "pi-acp"]], grayed: false },
    AcpAgentDef { id: "claude-code", name: "Claude Code", candidates: &[&["claude-code-acp"], &["npx", "-y", "@zed-industries/claude-code-acp"]], grayed: false },
    AcpAgentDef { id: "codex", name: "Codex", candidates: &[&["codex-acp"], &["npx", "-y", "@zed-industries/codex-acp"]], grayed: false },
    AcpAgentDef { id: "gemini", name: "Gemini CLI", candidates: &[&["gemini", "--experimental-acp"]], grayed: false },
    AcpAgentDef { id: "stepcode", name: "StepCode", candidates: &[&["step", "acp"]], grayed: false },
    AcpAgentDef { id: "dsh", name: "DSH", candidates: &[&["dsh", "acp"]], grayed: false },
    AcpAgentDef { id: "mcode", name: "MCode", candidates: &[&["mcode", "acp"]], grayed: false },
    AcpAgentDef { id: "kimi", name: "Kimi CLI", candidates: &[&["kimi", "acp"]], grayed: false },
    AcpAgentDef { id: "omp", name: "OMP", candidates: &[&["omp", "acp"]], grayed: false },
    AcpAgentDef { id: "solon", name: "Solon", candidates: &[&["solon", "acp"]], grayed: false },
    AcpAgentDef { id: "pivot", name: "Pivot（即将支持）", candidates: &[], grayed: true },
];

pub fn agent_def(id: &str) -> Option<&'static AcpAgentDef> {
    AGENT_CATALOG.iter().find(|d| d.id == id)
}

/// 子进程 PATH 强化（NoNDesign 同款）：nvm 各版本 bin（版本号降序）→ 登录 shell
/// PATH（zsh -lc，进程内缓存一次）→ 常见目录 → 当前进程 PATH。CLI 多由 nvm 安装，
/// GUI 应用不继承 shell PATH——这一步是「设置里能看到 agent」的生命线。
pub fn child_path() -> String {
    static CACHE: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    CACHE
        .get_or_init(|| {
            let mut segs: Vec<String> = Vec::new();
            if let Ok(home) = std::env::var("HOME") {
                let nvm = Path::new(&home).join(".nvm/versions/node");
                if let Ok(rd) = std::fs::read_dir(&nvm) {
                    let mut dirs: Vec<PathBuf> = rd
                        .filter_map(|e| e.ok())
                        .map(|e| e.path())
                        .filter(|p| p.join("bin").is_dir())
                        .collect();
                    dirs.sort();
                    dirs.reverse();
                    for d in dirs {
                        segs.push(d.join("bin").to_string_lossy().into_owned());
                    }
                }
                for d in [".local/bin", "bin"] {
                    let p = Path::new(&home).join(d);
                    if p.is_dir() {
                        segs.push(p.to_string_lossy().into_owned());
                    }
                }
            }
            if let Ok(out) = Command::new("/bin/zsh").args(["-lc", "echo $PATH"]).output() {
                let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
                if !s.is_empty() {
                    segs.extend(s.split(':').map(String::from));
                }
            }
            for d in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
                segs.push(d.to_string());
            }
            if let Ok(cur) = std::env::var("PATH") {
                segs.extend(cur.split(':').map(String::from));
            }
            let mut seen = std::collections::HashSet::new();
            segs.retain(|s| seen.insert(s.clone()));
            segs.join(":")
        })
        .clone()
}

fn child_env() -> HashMap<String, String> {
    let mut env: HashMap<String, String> = std::env::vars().collect();
    env.insert("PATH".into(), child_path());
    env
}

/// 轻量探测：在强化 PATH 里找候选 argv 的首个可执行文件（秒回，不做握手）。
/// npx 候选：npx 可达即视作可用——真伪由完整握手（acp_probe/建会话）兜底。
pub fn find_agent_argv(def: &AcpAgentDef) -> Option<Vec<String>> {
    if def.grayed || def.candidates.is_empty() {
        return None;
    }
    let path = child_path();
    for cand in def.candidates {
        let bin = cand[0];
        if bin == "npx" {
            if path.split(':').any(|d| Path::new(d).join("npx").exists()) {
                return Some(cand.iter().map(|s| s.to_string()).collect());
            }
            continue;
        }
        if path.split(':').any(|d| Path::new(d).join(bin).exists()) {
            return Some(cand.iter().map(|s| s.to_string()).collect());
        }
    }
    None
}

/// 探测缓存：Verified（实测命令）/ Missing / Grayed
#[derive(Clone, Debug)]
pub enum ProbeState {
    Verified { argv: Vec<String> },
    Missing,
    Grayed,
}

static PROBES: std::sync::OnceLock<Mutex<HashMap<String, ProbeState>>> = std::sync::OnceLock::new();
fn probes() -> &'static Mutex<HashMap<String, ProbeState>> {
    PROBES.get_or_init(|| Mutex::new(HashMap::new()))
}

pub fn cached_probe(id: &str) -> Option<ProbeState> {
    probes().lock().unwrap().get(id).cloned()
}

pub fn set_probe(id: &str, st: ProbeState) {
    probes().lock().unwrap().insert(id.to_string(), st);
}

/// 完整握手探测：spawn → initialize → session/new → 关闭。npx 90s / native 20s。
/// 成功后 Verified 缓存的是**实测可用**的 argv。
pub fn probe_agent_full(def: &AcpAgentDef) -> ProbeState {
    if def.grayed {
        return ProbeState::Grayed;
    }
    let timeout = if def.candidates.iter().any(|c| c[0] == "npx") {
        Duration::from_secs(90)
    } else {
        Duration::from_secs(20)
    };
    let def_id = def.id;
    let argv = match find_agent_argv(def) {
        Some(a) => a,
        None => {
            set_probe(def_id, ProbeState::Missing);
            return ProbeState::Missing;
        }
    };
    let child = match spawn_child(&argv, std::env::temp_dir().as_path()) {
        Ok(c) => Arc::new(Mutex::new(c)),
        Err(_) => {
            set_probe(def_id, ProbeState::Missing);
            return ProbeState::Missing;
        }
    };
    let (tx, rx) = mpsc::channel::<ProbeState>();
    let child_t = child.clone();
    std::thread::spawn(move || {
        let st = match handshake_probe(&child_t) {
            Ok(()) => ProbeState::Verified { argv },
            Err(_) => ProbeState::Missing,
        };
        let _ = tx.send(st);
    });
    let st = match rx.recv_timeout(timeout) {
        Ok(st) => st,
        Err(_) => {
            // 超时：探测线程仍阻塞在 stdout 读循环（挂死的 agent 永不 EOF）——
            // 从外部 kill 关管道触发收口，否则每次对挂死 CLI 的探测泄漏一个子进程
            // （2026-11-17 审查）
            if let Ok(mut c) = child.lock() {
                let _ = c.kill();
                let _ = c.wait();
            }
            ProbeState::Missing
        }
    };
    set_probe(def_id, st.clone());
    st
}

/// child 经 Arc<Mutex<>> 共享：recv_timeout 超时方要能拿到它去 kill
/// （kill 关 stdout 管道 → 读循环 EOF → 探测线程退出）。
fn handshake_probe(child: &Arc<Mutex<Child>>) -> Result<(), String> {
    let mut c = child.lock().map_err(|_| "child_poisoned".to_string())?;
    let mut w = c.stdin.take().ok_or("stdin")?;
    send_msg(
        &mut w,
        &json!({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{"fs":{"readTextFile":true,"writeTextFile":true}}}}),
    )
    .map_err(|e| format!("write:{e}"))?;
    send_msg(
        &mut w,
        &json!({"jsonrpc":"2.0","id":2,"method":"session/new","params":{"cwd":std::env::temp_dir().to_string_lossy(),"mcpServers":[]}}),
    )
    .map_err(|e| format!("write:{e}"))?;
    // 不 drop w：保持 stdin 打开直到读完响应（有些 agent 收 EOF 即退出）——
    // 此前内层块提前析构使注释意图落空（2026-11-17 审查）
    w.flush().ok();
    let out = c.stdout.take().ok_or("stdout")?;
    drop(c); // 释放锁：超时方 kill 时要能拿到 child
    let rd = BufReader::new(out);
    let mut got_init = false;
    let mut got_session = false;
    for line in rd.lines() {
        let line = line.map_err(|e| format!("read:{e}"))?;
        let Ok(v) = serde_json::from_str::<Value>(&line) else { continue };
        if v.get("method").is_some() {
            continue; // 探测期不回应通知/请求
        }
        match v.get("id").and_then(|x| x.as_u64()) {
            Some(1) => got_init = v.get("error").is_none(),
            Some(2) => {
                got_session = v.get("error").is_none();
                break;
            }
            _ => {}
        }
    }
    // 收口：无论成败都 kill + wait（防僵尸）；超时路径已被外层 kill，幂等无害
    if let Ok(mut c) = child.lock() {
        let _ = c.kill();
        let _ = c.wait();
    }
    drop(w); // 显式标注 stdin 的实际析构点（读完响应才关）
    if got_init && got_session {
        Ok(())
    } else {
        Err("handshake_incomplete".into())
    }
}

fn spawn_child(argv: &[String], cwd: &Path) -> Result<Child, String> {
    Command::new(&argv[0])
        .args(&argv[1..])
        .current_dir(cwd)
        .envs(child_env())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        // stderr 必须 null：PIPE 写满会死锁（NoNDesign 实证教训）
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("spawn:{e}"))
}

/// 宽松终止 CLI 进程（避免引 libc：kill(1) 双路径）
fn kill_pid(pid: u32) {
    for bin in ["/bin/kill", "/usr/bin/kill"] {
        if Command::new(bin).args(["-9", &pid.to_string()]).output().is_ok() {
            return;
        }
    }
}

// ---------------------------------------------------------------------------
// ndjson 帧
// ---------------------------------------------------------------------------

fn send_msg<W: Write>(w: &mut W, v: &Value) -> std::io::Result<()> {
    let mut line = serde_json::to_string(v)?;
    line.push('\n');
    w.write_all(line.as_bytes())
}

/// 解析一行 ndjson；非 JSON 行返回 None（agent 杂音不得炸泵）。
pub fn parse_line(line: &str) -> Option<Value> {
    serde_json::from_str(line).ok()
}

/// fs 回调路径必须落在工作区内：resolve 后前缀校验，越界 None。
pub fn path_in_workspace(ws: &Path, p: &str) -> Option<PathBuf> {
    let raw = Path::new(p);
    let resolved = if raw.is_absolute() { raw.to_path_buf() } else { ws.join(raw) };
    let ws_can = ws.canonicalize().ok()?;
    // 工作区内尚不存在的文件 canonicalize 必败——保留非规范化原路径做 starts_with
    // 会与 canonical 的 ws_can 组件级失配：工作区根任一路径段是符号链接
    // （macOS temp_dir /var→/private/var）时，agent 每写一个新文件都被误判越界
    // （2026-11-17 审查）。改为 canonicalize 最深存在祖先 + 回拼剩余段。
    let mut tail: Vec<std::ffi::OsString> = Vec::new();
    let mut probe = resolved.clone();
    let base = loop {
        match probe.canonicalize() {
            Ok(c) => break c,
            Err(_) => {
                let name = probe.file_name()?.to_owned();
                probe = probe.parent()?.to_path_buf();
                tail.push(name);
            }
        }
    };
    let mut resolved_can = base;
    for seg in tail.iter().rev() {
        resolved_can = resolved_can.join(seg);
    }
    if resolved_can.starts_with(&ws_can) {
        Some(resolved_can)
    } else {
        None
    }
}

/// JSON-RPC id 匹配：数字原样，字符串数字也接受（部分 CLI 会字符串化回显；
/// 协议允许 String id，此前 as_u64 单一判定把字符串 id 全部静默丢弃）。
fn id_matches(v: Option<&Value>, n: u64) -> bool {
    match v {
        Some(Value::Number(x)) => x.as_u64() == Some(n),
        Some(Value::String(s)) => s.parse::<u64>() == Ok(n),
        _ => false,
    }
}

// ---------------------------------------------------------------------------
// 会话
// ---------------------------------------------------------------------------

pub type Sink = Arc<dyn Fn(Value) + Send + Sync>;

struct Pending {
    tx: mpsc::Sender<Value>,
}

pub struct AcpSession {
    /// ACP sessionId（session/new 返回；握手完成后写入）
    sid: Mutex<String>,
    pub agent: String,
    pub workspace: PathBuf,
    /// 在飞 run id + 事件出口（**每次 prompt 置换**——旧实现绑死建会话时刻的
    /// run id，第二次 prompt 的全部事件带旧 run → 前端 acpRun 永不匹配、
    /// agentBusy 卡死、轨迹串块。2026-11-17 审查修复）
    flight: Mutex<(u64, Sink)>,
    /// tokio handle（finalize 在泵线程做 EngineHost render——block_on 需要）
    rt: Option<tokio::runtime::Handle>,
    writer: mpsc::Sender<Value>,
    pending: Arc<Mutex<HashMap<u64, Pending>>>,
    /// 在飞的 session/prompt 请求 id（泵线程特判 finalize 用；单会话串行 prompt）
    prompt_req: AtomicU64,
    req_seq: AtomicU64,
    tool_seq: AtomicU64,
    tool_map: Mutex<HashMap<String, u64>>,
    alive: Arc<AtomicBool>,
    child_pid: Mutex<Option<u32>>,
}

impl Drop for AcpSession {
    fn drop(&mut self) {
        self.alive.store(false, Ordering::Relaxed);
        if let Some(pid) = self.child_pid.lock().unwrap().take() {
            kill_pid(pid);
        }
    }
}

impl AcpSession {
    pub fn sid(&self) -> String {
        self.sid.lock().unwrap().clone()
    }

    fn flight_snapshot(&self) -> (u64, Sink) {
        let f = self.flight.lock().unwrap();
        (f.0, f.1.clone())
    }

    /// spawn + initialize + session/new（阻塞握手；调用方放 spawn_blocking）。
    /// `rt`：tokio handle（finalize 的 EngineHost render 用；测试可传 None——
    /// 无 handle 时 finalize 降级为「不回灌」信封）。
    pub fn spawn_session(
        agent_id: &str,
        workspace: &Path,
        run_id: u64,
        rt: Option<tokio::runtime::Handle>,
        sink: Sink,
    ) -> Result<Arc<AcpSession>, String> {
        let def = agent_def(agent_id).ok_or("unknown_agent")?;
        if def.grayed {
            return Err("agent_grayed".into());
        }
        let argv = match cached_probe(agent_id) {
            Some(ProbeState::Verified { argv }) => Some(argv),
            _ => find_agent_argv(def),
        }
        .ok_or("agent_not_found")?;
        // 工作区目录必须先建：spawn_child 的 current_dir 指向不存在的目录时 spawn
        // 直接报错（Errno 2）。生产路径此前从不建目录——唯一的 mkdir 在 acp_prompt，
        // 而它要求会话已在注册表，会话又只能由本函数创建（鸡生蛋死锁），
        // 每次建会话都确定性失败（2026-11-17 审查）
        std::fs::create_dir_all(workspace).map_err(|e| format!("workspace:{e}"))?;
        pump_and_handshake(spawn_child(&argv, workspace)?, workspace, run_id, agent_id, rt, sink)
    }

    /// session/prompt：发请求即返回；response 到达由泵线程 finalize（done/failed 信封）。
    /// 每次 prompt 前由命令层调用：换绑在飞 run 与事件出口（BUG1 修复落点）。
    pub fn rebind_flight(&self, run_id: u64, sink: Sink) {
        *self.flight.lock().unwrap() = (run_id, sink);
    }

    pub fn prompt(&self, text: &str) -> Result<(), String> {
        let id = self.req_seq.fetch_add(1, Ordering::Relaxed) + 1;
        // 在飞单飞守卫：CAS 0→id 原子占位。并发 prompt 会覆盖 prompt_req——
        // 先发请求的响应匹配失败被静默丢弃、该 run 永不收口（无终态信封）；
        // 「单会话串行 prompt」的约定此前只靠前端 agentBusy 兜底（2026-11-17 审查）
        if self
            .prompt_req
            .compare_exchange(0, id, Ordering::Relaxed, Ordering::Relaxed)
            .is_err()
        {
            return Err("acp_prompt_in_flight".into());
        }
        if self
            .writer
            .send(json!({
                "jsonrpc":"2.0","id":id,"method":"session/prompt",
                "params":{"sessionId":self.sid(),"prompt":[{"type":"text","text":text}]}
            }))
            .is_err()
        {
            self.prompt_req.store(0, Ordering::Relaxed); // 发送失败回滚占位
            return Err("writer_closed".into());
        }
        Ok(())
    }

    pub fn cancel(&self) {
        let _ = self.writer.send(json!({
            "jsonrpc":"2.0","method":"session/cancel","params":{"sessionId":self.sid()}
        }));
    }

    /// 权限确认框应答（前端 acp_permission_reply → 命令层）。
    /// 线格式按 ACP 协议：result 必须是 outcome 包裹对象——
    /// `{"outcome":{"outcome":"selected","optionId":…}}` / `{"outcome":{"outcome":"cancelled"}}`。
    /// 裸 `{"optionId":…}` 会被 SDK 系 agent 的 RequestPermissionResponse 模式校验
    /// 拒绝（pydantic ValidationError 实证），用户点「允许」后 agent 侧挂起
    /// （2026-11-17 审查）。option_id None = 用户取消（拒绝框/Esc）。
    pub fn reply(&self, request_id: Value, option_id: Option<&str>) {
        let outcome = match option_id {
            Some(id) => json!({"outcome":"selected","optionId":id}),
            None => json!({"outcome":"cancelled"}),
        };
        let _ = self.writer.send(json!({
            "jsonrpc":"2.0","id":request_id,"result":{"outcome":outcome}
        }));
    }

    pub fn shutdown(&self) {
        self.alive.store(false, Ordering::Relaxed);
        if let Some(pid) = self.child_pid.lock().unwrap().take() {
            kill_pid(pid);
        }
    }
}

fn dispatch_msg(
    sess: &Arc<AcpSession>,
    pending: &Mutex<HashMap<u64, Pending>>,
    v: Value,
) {
    let (run, sink) = sess.flight_snapshot();
    // ── 通知 session/update 先于通配分发（无 id 通知曾被 `_ => return` 吞掉——
    // 思考/工具/文本事件全丢，只有带 id 的 permission/fs 存活的实证）──
    if v.get("method").and_then(|m| m.as_str()) == Some("session/update") {
        let upd = v.pointer("/params/update").cloned().unwrap_or(json!({}));
        handle_update(sess, &sink, &upd);
        return;
    }
    // ── agent 发来的请求（需应答）──
    // id 保留原始 Value：JSON-RPC 2.0 允许 String id，as_u64 单一判定会把
    // 字符串 id 的请求全部落进 `_ => return`——权限请求无应答 agent 挂死、
    // fs 回调无响应 agent 卡死（2026-11-17 审查）
    if let Some(method) = v.get("method").and_then(|m| m.as_str()) {
        let rid = v.get("id").cloned();
        let params = v.get("params").cloned().unwrap_or(json!({}));
        match (method, rid) {
            ("session/request_permission", Some(rid)) => {
                // 真实请求字段是 toolCall（其 title 才是工具上下文）；顶层 title
                // 非协议字段——仅作兼容回退读（2026-11-17 审查）
                let title = params
                    .get("title")
                    .or_else(|| params.pointer("/toolCall/title"))
                    .cloned()
                    .unwrap_or(json!("外部智能体请求权限"));
                sink(json!({
                    "type": "acp-permission", "run": run,
                    "request_id": rid, "session": sess.sid(),
                    "title": title,
                    "options": params.get("options").cloned().unwrap_or(json!([])),
                }));
                // 应答由前端 acp_permission_reply → sess.reply 直接写 response 行
                return;
            }
            ("fs/read_text_file", Some(rid)) => {
                let p = params.get("path").and_then(|x| x.as_str()).unwrap_or("");
                match path_in_workspace(&sess.workspace, p) {
                    Some(path) => match std::fs::read_to_string(&path) {
                        Ok(content) => {
                            let _ = sess.writer.send(json!({"jsonrpc":"2.0","id":rid,"result":{"content":content}}));
                        }
                        Err(e) => {
                            let _ = sess.writer.send(json!({"jsonrpc":"2.0","id":rid,"error":{"code":-32000,"message":format!("read_failed:{e}")}}));
                        }
                    },
                    None => {
                        let _ = sess.writer.send(json!({"jsonrpc":"2.0","id":rid,"error":{"code":-32001,"message":"PermissionError: path outside workspace"}}));
                    }
                }
                return;
            }
            ("fs/write_text_file", Some(rid)) => {
                let p = params.get("path").and_then(|x| x.as_str()).unwrap_or("");
                let content = params.get("content").and_then(|x| x.as_str()).unwrap_or("");
                match path_in_workspace(&sess.workspace, p) {
                    Some(path) => match std::fs::write(&path, content) {
                        Ok(_) => {
                            let _ = sess.writer.send(json!({"jsonrpc":"2.0","id":rid,"result":{}}));
                            sink(json!({"type":"tool_start","run":run,"tool":"acp_tool","op":"写入工作区文件"}));
                            sink(json!({"type":"tool_end","run":run,"ok":true,"ms":0}));
                        }
                        Err(e) => {
                            let _ = sess.writer.send(json!({"jsonrpc":"2.0","id":rid,"error":{"code":-32000,"message":format!("write_failed:{e}")}}));
                        }
                    },
                    None => {
                        let _ = sess.writer.send(json!({"jsonrpc":"2.0","id":rid,"error":{"code":-32001,"message":"PermissionError: path outside workspace"}}));
                    }
                }
                return;
            }
            (_, Some(rid)) => {
                let _ = sess.writer.send(json!({"jsonrpc":"2.0","id":rid,"error":{"code":-32601,"message":"method_not_found"}}));
                return;
            }
            _ => return, // 无 id 的未知通知忽略
        }
    }
    // ── 响应（id 数字或字符串数字都匹配，见 id_matches）──
    if v.get("method").is_none() && v.get("id").is_some() {
        // prompt 主请求：response 到达 = 终止 → finalize
        let inflight = sess.prompt_req.load(Ordering::Relaxed);
        if inflight != 0 && id_matches(v.get("id"), inflight) {
            sess.prompt_req.store(0, Ordering::Relaxed);
            if v.get("error").is_some() {
                // failed 信封 error 统一字符串形状（前端红卡 String(p.error) 直显；
                // 原始 JSON-RPC 错误对象会渲染成 [object Object]——2026-11-17 审查）
                let msg = v
                    .pointer("/error/message")
                    .and_then(|x| x.as_str())
                    .map(|s| format!("acp_prompt_failed:{s}"))
                    .unwrap_or_else(|| "acp_prompt_failed".to_string());
                sink(json!({"type":"failed","run":run,"error":msg}));
            } else {
                let stop = v
                    .pointer("/result/stopReason")
                    .and_then(|x| x.as_str())
                    .unwrap_or("end_turn")
                    .to_string();
                finalize_done(sess, &sink, &stop);
            }
            return;
        }
        // 其余响应（initialize/session/new）按 req_seq 的数字 id 匹配 pending。
        // 两次加锁必须拆成两条语句：同一 let 语句里第一个临时 MutexGuard 存活到
        // 语句结束，闭包里再 lock 即自死锁（reader 线程卡死在首条响应上，
        // 握手超时路径的 pending.lock 也跟着卡死——2026-11-17 实测复现）
        let matched = pending
            .lock()
            .unwrap()
            .keys()
            .copied()
            .find(|k| id_matches(v.get("id"), *k));
        let waiter = matched.and_then(|k| pending.lock().unwrap().remove(&k));
        if let Some(w) = waiter {
            let _ = w.tx.send(v);
        }
        return;
    }
}

fn handle_update(sess: &AcpSession, sink: &Sink, upd: &Value) {
    let (run, _) = sess.flight_snapshot();
    match upd.get("sessionUpdate").and_then(|x| x.as_str()) {
        Some("agent_message_chunk") => {
            let text = upd.pointer("/content/text").and_then(|x| x.as_str()).unwrap_or("");
            if !text.is_empty() {
                sink(json!({"type":"assistant_delta","run":run,"text":text}));
            }
        }
        Some("agent_thought_chunk") => {
            let text = upd.pointer("/content/text").and_then(|x| x.as_str()).unwrap_or("");
            if !text.is_empty() {
                sink(json!({"type":"assistant_thinking","run":run,"text":text}));
            }
        }
        Some("tool_call") => {
            let tid = upd.get("toolCallId").and_then(|x| x.as_str()).unwrap_or("").to_string();
            let title = upd.get("title").and_then(|x| x.as_str()).unwrap_or("tool").to_string();
            let seq = sess.tool_seq.fetch_add(1, Ordering::Relaxed) + 1;
            sess.tool_map.lock().unwrap().insert(tid, seq);
            sink(json!({"type":"tool_start","run":run,"seq":seq,"tool":"acp_tool","op":title}));
        }
        Some("tool_call_update") => {
            let tid = upd.get("toolCallId").and_then(|x| x.as_str()).unwrap_or("").to_string();
            let seq = sess.tool_map.lock().unwrap().get(&tid).copied();
            let status = upd.get("status").and_then(|x| x.as_str()).unwrap_or("completed");
            if let Some(seq) = seq {
                sink(json!({"type":"tool_end","run":run,"seq":seq,"ok":status=="completed","ms":0}));
            }
        }
        Some("plan") => {
            let entries = upd.get("entries").and_then(|x| x.as_array()).cloned().unwrap_or_default();
            let lines: Vec<String> = entries
                .iter()
                .filter_map(|e| e.get("content").and_then(|x| x.as_str()).map(String::from))
                .collect();
            if !lines.is_empty() {
                sink(json!({"type":"assistant_text","run":run,"text":format!("📋 计划：{}", lines.join(" · "))}));
            }
        }
        _ => {}
    }
}

/// prompt 终止：读回工作区 mbt.md → EngineHost validate+render → done 信封。
/// 无 mbt.md（agent 未动文件）→ done 但 mbt_b64 空串（前端跳过应用，仅收轨迹）；
/// 无 tokio handle（测试环境）→ 同样降级为不回灌。
fn finalize_done(sess: &AcpSession, sink: &Sink, stop: &str) {
    let (run, _) = sess.flight_snapshot();
    let file = sess.workspace.join("mbt.md");
    let content = std::fs::read_to_string(&file).unwrap_or_default();
    if content.is_empty() {
        sink(json!({"type":"done","run":run,"ops":0,"stopReason":stop,"ok":true,
            "text":"外部智能体完成（未改动项目文件）","mbt_b64":"","render":null}));
        return;
    }
    let render = match &sess.rt {
        Some(h) => h.block_on(async { crate::EngineHost.call("render_mbt", &content, "").await })
            .unwrap_or_else(|e| json!({"ok":false,"error":e})),
        None => json!(null),
    };
    let ok = render.get("ok").and_then(|x| x.as_bool()).unwrap_or(false);
    if !ok {
        sink(json!({"type":"failed","run":run,"error":format!("acp_result_invalid_mbt:{}", render.get("error").and_then(|x| x.as_str()).unwrap_or("render_unavailable"))}));
        return;
    }
    let b64 = {
        use base64::Engine as _;
        base64::engine::general_purpose::STANDARD.encode(&content)
    };
    sink(json!({
        "type":"done","run":run,"ops":0,"stopReason":stop,"ok":true,
        "text":"外部智能体完成——改动已回灌画布（AgentGate 校验）",
        "mbt_b64": b64, "render": render,
    }));
}

// ---------------------------------------------------------------------------
// 注册表
// ---------------------------------------------------------------------------

#[derive(Default)]
pub struct AcpRegistry {
    pub sessions: Mutex<HashMap<String, Arc<AcpSession>>>,
    /// 工作区根（lib.rs 注入 app_data/acp-workspace）
    pub root: Mutex<Option<PathBuf>>,
}

impl AcpRegistry {
    pub fn workspace_for(&self, project_label: &str) -> PathBuf {
        let root = self
            .root
            .lock()
            .unwrap()
            .clone()
            .unwrap_or_else(|| std::env::temp_dir().join("dd-acp-workspace"));
        let slug: String = project_label
            .chars()
            .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '-' })
            .collect();
        root.join(slug)
    }

    /// 关闭指定项目窗口名下的全部 ACP 会话（lib.rs 窗口 Destroyed 钩子调用）。
    /// 会话按 agent 返回的 sid 键控、不知道窗口 label，但工作区按 label 派生
    /// （workspace_for）——按 workspace 归属过滤。窗口关闭时不清的话，CLI 子进程
    /// 与泵/守护/写三线程随注册表残留至应用退出，子进程持续运行（2026-11-17 审查）
    pub fn shutdown_for_label(&self, project_label: &str) {
        let ws = self.workspace_for(project_label);
        let stale: Vec<String> = {
            let sessions = self.sessions.lock().unwrap();
            sessions
                .iter()
                .filter(|(_, s)| s.workspace == ws)
                .map(|(k, _)| k.clone())
                .collect()
        };
        for k in stale {
            if let Some(s) = self.sessions.lock().unwrap().remove(&k) {
                s.shutdown();
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 内部：握手 + 泵（spawn_session 与测试共用）
// ---------------------------------------------------------------------------

fn pump_and_handshake(
    mut child: Child,
    workspace: &Path,
    run_id: u64,
    agent_label: &str,
    rt: Option<tokio::runtime::Handle>,
    sink: Sink,
) -> Result<Arc<AcpSession>, String> {
    let pid = child.id();
    let (writer_tx, writer_rx) = mpsc::channel::<Value>();
    let sess = Arc::new(AcpSession {
        sid: Mutex::new(String::new()),
        agent: agent_label.to_string(),
        workspace: workspace.to_path_buf(),
        flight: Mutex::new((run_id, sink.clone())),
        rt,
        writer: writer_tx,
        pending: Arc::new(Mutex::new(HashMap::new())),
        prompt_req: AtomicU64::new(0),
        req_seq: AtomicU64::new(10),
        tool_seq: AtomicU64::new(0),
        tool_map: Mutex::new(HashMap::new()),
        alive: Arc::new(AtomicBool::new(true)),
        child_pid: Mutex::new(Some(pid)),
    });
    // writer 线程：独占 child.stdin（mpsc 序列化并发写）。
    // 两个早期失败面（stdin/stdout 缺失）在任何线程 spawn 前返回——child 会被
    // 裸 drop（std 不 kill），先 kill+wait 防僵尸（2026-11-17 审查）
    let mut stdin = match child.stdin.take() {
        Some(s) => s,
        None => {
            let _ = child.kill();
            let _ = child.wait();
            return Err("stdin".into());
        }
    };
    let alive_w = sess.alive.clone();
    std::thread::spawn(move || {
        while let Ok(v) = writer_rx.recv() {
            if !alive_w.load(Ordering::Relaxed) {
                break;
            }
            if send_msg(&mut stdin, &v).is_err() {
                break;
            }
        }
    });
    // reader 泵线程（先 take stdout 再移交 child 给回收守护）
    let stdout = match child.stdout.take() {
        Some(s) => s,
        None => {
            let _ = child.kill();
            let _ = child.wait();
            return Err("stdout".into());
        }
    };
    let sess_r = sess.clone();
    let alive_r = sess.alive.clone();
    let pending_r = sess.pending.clone();
    // child 回收守护（Drop 走 kill_pid；try_wait 轮询 + 终态 wait 防僵尸）
    let alive_g = sess.alive.clone();
    std::thread::spawn(move || {
        while alive_g.load(Ordering::Relaxed) {
            match child.try_wait() {
                Ok(Some(_)) => break,
                Ok(None) => std::thread::sleep(Duration::from_millis(300)),
                Err(_) => break,
            }
        }
        let _ = child.kill();
        let _ = child.wait();
    });
    std::thread::spawn(move || {
        let rd = BufReader::new(stdout);
        for line in rd.lines() {
            if !alive_r.load(Ordering::Relaxed) {
                break;
            }
            let Ok(line) = line else { break };
            let Some(v) = parse_line(&line) else { continue };
            dispatch_msg(&sess_r, &pending_r, v);
        }
        // 进程退出：未完成的 prompt 以 failed 收口（alive 未被主动关闭时）
        if alive_r.swap(false, Ordering::Relaxed) {
            let (run, sink) = sess_r.flight_snapshot();
            sink(json!({"type": "failed", "run": run, "error": "acp_agent_exited"}));
        }
    });
    // initialize + session/new（阻塞等待）
    let handshake = (|| -> Result<String, String> {
        let init = sess
            .request("initialize", json!({"protocolVersion":1,"clientCapabilities":{"fs":{"readTextFile":true,"writeTextFile":true}}}), Duration::from_secs(30))?;
        if init.get("error").is_some() {
            return Err("initialize_rejected".into());
        }
        let ws_str = workspace.to_string_lossy().into_owned();
        let new_s = sess.request(
            "session/new",
            json!({"cwd": ws_str, "mcpServers": []}),
            Duration::from_secs(30),
        )?;
        new_s
            .pointer("/result/sessionId")
            .and_then(|v| v.as_str())
            .map(String::from)
            .ok_or_else(|| "session_new_no_id".to_string())
    })();
    let sid = match handshake {
        Ok(sid) => sid,
        Err(e) => {
            // 握手失败必须显式收口：reader 泵线程持有 sess Arc，Drop 永不可达——
            // alive 恒 true、守护线程永不 kill，child + 3 线程随每次失败泄漏，
            // 重试线性累积（2026-11-17 审查）。shutdown 置 alive=false 并 kill：
            // 管道 EOF 让 reader 退出 → Arc 归零 → 线程全部收口
            sess.shutdown();
            return Err(e);
        }
    };
    *sess.sid.lock().unwrap() = sid;
    Ok(sess)
}

impl AcpSession {
    fn request(&self, method: &str, params: Value, timeout: Duration) -> Result<Value, String> {
        let id = self.req_seq.fetch_add(1, Ordering::Relaxed) + 1;
        let (tx, rx) = mpsc::channel();
        self.pending.lock().unwrap().insert(id, Pending { tx });
        let msg = json!({"jsonrpc":"2.0","id":id,"method":method,"params":params});
        self.writer.send(msg).map_err(|_| "writer_closed".to_string())?;
        match rx.recv_timeout(timeout) {
            Ok(v) => Ok(v),
            Err(_) => {
                self.pending.lock().unwrap().remove(&id);
                Err(format!("request_timeout:{method}"))
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 测试
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_line_tolerates_noise() {
        assert!(parse_line("not json").is_none());
        let v = parse_line("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}").unwrap();
        assert_eq!(v["id"], 1);
    }

    #[test]
    fn path_confinement_rejects_escape() {
        let ws = std::env::temp_dir().join(format!("dd-acp-test-{}", std::process::id()));
        std::fs::create_dir_all(&ws).unwrap();
        std::fs::write(ws.join("a.md"), "x").unwrap();
        assert!(path_in_workspace(&ws, "a.md").is_some());
        let abs_in = ws.join("a.md").to_string_lossy().into_owned();
        assert!(path_in_workspace(&ws, &abs_in).is_some());
        let abs_out = std::env::temp_dir().join("outside-acp.md");
        std::fs::write(&abs_out, "y").unwrap();
        assert!(path_in_workspace(&ws, &abs_out.to_string_lossy()).is_none());
        assert!(path_in_workspace(&ws, "../../etc/passwd").is_none());
        // 工作区内**尚不存在**的新文件：canonicalize 失败曾保留非规范化原路径，
        // 与 canonical 的 ws_can 做前缀比较——macOS temp_dir 在 /var→/private/var
        // 符号链接下，agent 每写一个新文件都被误判越界拒绝（2026-11-17 审查）
        let new_in = ws.join("sub").join("new.md");
        assert!(
            path_in_workspace(&ws, &new_in.to_string_lossy()).is_some(),
            "工作区内新文件不应被误判越界：{}",
            new_in.display()
        );
        // 越界的新文件仍要拒绝（最深存在祖先解析后前缀不匹配）
        let new_out = std::env::temp_dir().join("outside-acp-new").join("x.md");
        assert!(path_in_workspace(&ws, &new_out.to_string_lossy()).is_none());
        let _ = std::fs::remove_dir_all(&ws);
    }

    #[test]
    fn catalog_shape_is_locked() {
        assert_eq!(AGENT_CATALOG.len(), 12);
        for need in ["claude-code", "codex", "gemini", "dsh", "kimi", "stepcode", "qwen", "pi"] {
            assert!(agent_def(need).is_some(), "缺 {need}");
        }
        assert!(agent_def("pivot").unwrap().grayed, "pivot 应为占位灰");
        for d in AGENT_CATALOG.iter() {
            if !d.grayed {
                assert!(!d.candidates.is_empty(), "{} 无候选", d.id);
            }
        }
    }

    /// 假 agent 全链：tests/fixtures/fake_acp_agent.py 讲最小 ACP——
    /// initialize/session-new 应答 → prompt 期间发思考/文本/工具事件 + 权限请求
    /// （**阻塞等待应答**）→ 客户端 write mbt.md（fs 回调落盘）→ end_turn。
    #[tokio::test(flavor = "multi_thread")]
    async fn fake_agent_full_chain_probe_prompt_permission() {
        let manifest = env!("CARGO_MANIFEST_DIR");
        let fixture = format!("{}/tests/fixtures/fake_acp_agent.py", manifest);
        assert!(Path::new(&fixture).exists(), "夹具缺失：{fixture}");
        let ws = std::env::temp_dir().join(format!("dd-acp-chain-{}", std::process::id()));
        std::fs::create_dir_all(&ws).unwrap();
        std::fs::write(ws.join("mbt.md"), "---\nmoonviz:\n  format: visual-document\n---\n\n# w\n").unwrap();
        let events: Arc<Mutex<Vec<Value>>> = Arc::new(Mutex::new(Vec::new()));
        let ev_c = events.clone();
        let sink: Sink = Arc::new(move |v: Value| {
            ev_c.lock().unwrap().push(v);
        });
        let argv = vec!["python3".to_string(), "-u".to_string(), fixture];
        let sess = pump_and_handshake(
            spawn_child(&argv, &ws).expect("spawn 失败"),
            &ws,
            77,
            "fake",
            Some(tokio::runtime::Handle::current()),
            sink,
        )
        .expect("握手失败");
        assert!(!sess.sid().is_empty(), "session id 未获得");
        sess.prompt("请改一下").expect("prompt 发送失败");
        let deadline = std::time::Instant::now() + Duration::from_secs(60);
        let mut done = None;
        let mut replied = false;
        while std::time::Instant::now() < deadline {
            {
                let evs = events.lock().unwrap();
                if let Some(e) = evs.iter().find(|e| e["type"] == json!("done")) {
                    done = Some(e.clone());
                }
            }
            if !replied {
                let req_id = {
                    let evs = events.lock().unwrap();
                    evs.iter()
                        .find(|e| e["type"] == json!("acp-permission"))
                        .and_then(|e| e.get("request_id").and_then(|x| x.as_u64()))
                };
                if let Some(rid) = req_id {
                    sess.reply(json!(rid), Some("allow_once"));
                    replied = true;
                }
            }
            if done.is_some() {
                break;
            }
            std::thread::sleep(Duration::from_millis(120));
        }
        let d = done.expect("60s 内未收到 done");
        assert_eq!(d["stopReason"], json!("end_turn"), "{d}");
        assert!(
            d["mbt_b64"].as_str().is_some_and(|s| !s.is_empty()),
            "done 应回灌 mbt_b64：{d}"
        );
        assert!(d["render"].get("ok").and_then(|x| x.as_bool()) == Some(true), "render 应成功：{d}");
        let evs = events.lock().unwrap();
        assert!(evs.iter().any(|e| e["type"] == json!("assistant_delta")), "缺流式文本事件");
        assert!(evs.iter().any(|e| e["type"] == json!("assistant_thinking")), "缺思考事件");
        assert!(evs.iter().any(|e| e["type"] == json!("tool_start")), "缺工具事件");
        assert!(evs.iter().any(|e| e["type"] == json!("acp-permission")), "缺权限请求事件");
        // ── BUG1 回归锚定：第二次 prompt 换绑新 run=88 + 全新 sink（生产语义：
        // 每次 prompt 换新事件出口；也避开测试夹具 events 锁与 block_on 交织）──
        let events2: Arc<Mutex<Vec<Value>>> = Arc::new(Mutex::new(Vec::new()));
        let ev_c2 = events2.clone();
        let sink2: Sink = Arc::new(move |v: Value| {
            ev_c2.lock().unwrap().push(v);
        });
        sess.rebind_flight(88, sink2);
        sess.prompt("再来一次").expect("第二次 prompt 发送失败");
        let deadline2 = std::time::Instant::now() + Duration::from_secs(30);
        let mut done2 = false;
        let mut replied2 = false;
        while std::time::Instant::now() < deadline2 {
            {
                let evs = events2.lock().unwrap();
                if evs.iter().any(|e| e["type"] == json!("done")) {
                    done2 = true;
                }
            }
            if !replied2 {
                let req_id = {
                    let evs = events2.lock().unwrap();
                    evs.iter()
                        .find(|e| e["type"] == json!("acp-permission"))
                        .and_then(|e| e.get("request_id").and_then(|x| x.as_u64()))
                };
                if let Some(rid) = req_id {
                    sess.reply(json!(rid), Some("allow_once"));
                    replied2 = true;
                }
            }
            if done2 {
                break;
            }
            std::thread::sleep(Duration::from_millis(120));
        }
        assert!(done2, "第二次 prompt 未收口");
        let evs2 = events2.lock().unwrap();
        assert!(
            evs2.iter().all(|e| e["run"] == json!(88)),
            "BUG1：第二次 prompt 的事件必须全部带新 run=88：{:?}",
            evs2.iter().map(|e| (e["type"].clone(), e["run"].clone())).collect::<Vec<_>>()
        );
        assert!(
            evs2.iter().any(|e| e["type"] == json!("assistant_delta")),
            "第二次 prompt 应有流式事件"
        );
        sess.shutdown();
        let _ = std::fs::remove_dir_all(&ws);
    }
}
