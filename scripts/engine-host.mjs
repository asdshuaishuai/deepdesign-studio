#!/usr/bin/env node
// engine-host.mjs —— MoonViz **标准** wasm 引擎（classic，宿主中立）的 Node 直查工具。
//
// **调试工具，非运行时依赖**：Rust 侧引擎宿主已迁移到 wasmtime 进程内
// （src-tauri/src/wasmtime_host.rs），cargo test 不再经过本脚本。保留它是为了
// 手动直查引擎产物（行协议模式）。**本脚本的调用语义是 wasmtime_host.rs 的
// 历史参考——仅限读方向与会话缓存编排；写方向两侧有意不同**：生产宿主走
// `_in` 槽契约（engine-v0.1.2），本脚本保留经典内存写作调试对照，勿互相同步
// （改漏会让「调试工具」给出与生产宿主不同的答案）。
//
// classic wasm 无 import、`(i32)->i32` 签名，字符串是 linear memory 对象
// （[refcnt@ptr-8][长度@ptr-4][UTF-16LE@ptr+0]）——字符串进出全部经 makeStrCodec
// 编解码（写入区锚在「当前内存大小 + 余量」之上，防引擎 bump 堆覆盖）。
//
// 两种模式：
//   1. 行协议（长驻）：stdin 每行一个请求 {"id":n,"fn":...,"mbt":...,"op":...}，
//      stdout 回一行 {"id":n,"ok":true,"json":"<结果 JSON 字符串>"}。
//   2. 单发（--once-file <路径>）：请求 JSON 存于文件，stdout 回一行响应后退出。
// fn 取值分三类：
//   1. 经典导出（无状态，每调用传完整 mbt）：apply_agent_op | apply_human_op |
//      render_mbt | validate_mbt | list_templates | export_html | version_info
//   2. 检视直调（arity 0）：list_tokens | list_themes | list_ops；
//      list_components 读同步脚本产出的 components.json 快照（与前端同源）
//   3. session API（有状态）：fn 以 session_ 开头——会话按 **mbt 键控缓存**
//      复用（与前端桥同构）：行协议长驻模式下连续请求命中同一句柄（内存棘轮
//      减半、只读突发免重解析）；--once-file 每次新进程自然不命中，语义等价。
//      args 取自 op 字段（空白切分）；session_apply_agent/human/component_compile_b64
//      的 op 是完整串（含空格），原样单参传入。Rust 侧（agent.rs）的只读 op
//      路由与变更路径（session_apply_agent）依赖这组导出。
import { createInterface } from 'node:readline';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const WASM = join(HERE, '..', 'frontend', 'vendor', 'moonviz.wasm');
const COMPONENTS = join(HERE, '..', 'frontend', 'vendor', 'components.json');

if (!existsSync(WASM)) {
  console.error('[engine-host] frontend/vendor/moonviz.wasm 缺失——先跑 node scripts/sync-engine.mjs');
  process.exit(1);
}
const bytes = readFileSync(WASM);
const ex = new WebAssembly.Instance(new WebAssembly.Module(bytes), {}).exports;

// classic wasm 字符串编解码（与 sync-engine.mjs 同构）：
// 写入区始终锚在「当前内存大小 + 余量」之上——引擎 bump 堆顶不超过当前内存大小，
// 故该区永不与引擎堆碰撞；引擎增长过内存时重新锚定。
const INITIAL_MEM = ex.memory.buffer.byteLength;
let writeOff = INITIAL_MEM + 65536;
let lastMemSize = INITIAL_MEM;
const readStr = (ptr) => {
  const mem = new DataView(ex.memory.buffer);
  // 钳制到内存边界：腐坏指针/长度不再放大成巨型读取
  const len = Math.min(mem.getUint32(ptr - 4, true) & 0x0FFFFFFF, (ex.memory.buffer.byteLength - ptr) / 2);
  let s = '';
  for (let i = 0; i < len; i++) s += String.fromCharCode(mem.getUint16(ptr + i * 2, true));
  return s;
};
const writeStr = (s) => {
  const cur = ex.memory.buffer.byteLength;
  if (cur !== lastMemSize) {
    writeOff = Math.max(writeOff, cur + 65536);
    lastMemSize = cur;
  }
  const need = 16 + s.length * 2;
  if (ex.memory.buffer.byteLength < writeOff + need) {
    ex.memory.grow(Math.ceil((writeOff + need + 65536 - ex.memory.buffer.byteLength) / 65536));
  }
  const mem = new DataView(ex.memory.buffer);
  mem.setUint32(writeOff - 8, 0xFFFFFFE0, true);
  mem.setUint32(writeOff - 4, s.length, true);
  for (let i = 0; i < s.length; i++) mem.setUint16(writeOff + i * 2, s.charCodeAt(i), true);
  const ptr = writeOff;
  writeOff = ptr + need + 4096;
  return ptr;
};

const ARITY = {
  apply_agent_op: 2, apply_human_op: 2, render_mbt: 1, validate_mbt: 1,
  export_html: 1, list_templates: 0, version_info: 0,
  list_tokens: 0, list_themes: 0, list_ops: 0,
};
// session op 的 op 参数是完整串（含空格），不做切分
const SESSION_WHOLE_ARG = new Set([
  'session_apply_agent', 'session_apply_human', 'session_component_compile_b64',
]);
// 变更类导出（信封回传 canonical）：成功后缓存键前移到新 canonical
// 变更类导出（成功信封回传 canonical：缓存键前移）。0.1.6-fix/#19 起**全部**
// 改文档面（apply 双门/auto_fix/constrain/tap/generate_responsive/component_compile）
// 信封都带 canonical——与 wasmtime_host.rs 的 SESSION_MUTATING 同步维护。
const SESSION_MUTATING = new Set([
  'session_apply_agent', 'session_apply_human', 'session_auto_fix',
  'session_constrain', 'session_tap', 'session_generate_responsive',
  'session_component_compile_b64',
]);
// （SESSION_EVICT 已随 0.1.6-fix/#19 移除：此前 auto_fix/constrain 改文档但信封
// 不回传 canonical，只能弃缓存防脏键；信封补齐后统一走上方键前移。）

// mbt 键控会话缓存：命中即复用句柄；失配即关旧开新（缓存至多持有一个活会话，
// 不会泄漏）。与 frontend/index.html 桥的 agentSession 同构。hits/misses 计数
// 供 cargo test 的缓存契约断言（静息 session_count 无法区分命中与失配重开）。
let sessCache = null;
const cacheStats = { hits: 0, misses: 0 };
function cachedSession(mbt) {
  if (sessCache && sessCache.mbt === mbt) {
    cacheStats.hits += 1;
    return sessCache.handle;
  }
  cacheStats.misses += 1;
  if (sessCache) ex.session_close(sessCache.handle);
  const h = ex.session_open(writeStr(mbt));
  if (!Number.isInteger(h) || h < 0) {
    sessCache = null;
    return -1;
  }
  sessCache = { handle: h, mbt };
  return h;
}

function handle(req) {
  const { id, fn } = req;
  if (fn === 'list_components') {
    const comps = existsSync(COMPONENTS) ? readFileSync(COMPONENTS, 'utf8') : '[]';
    return { id, ok: true, json: JSON.stringify({ ok: true, components: JSON.parse(comps) }) };
  }
  // 宿主编排型导出：句柄与计数由宿主管理（缓存生命周期），经通用 session 分支
  // 直调会以 i32/bool 返回值当字符串指针解读出垃圾——明确拒绝。需要 count 时
  // 用 session_count_probe（宿主侧 open×2/close×2 编排）。
  if (fn === 'session_open' || fn === 'session_close' ||
      fn === 'session_open_project_json' || fn === 'session_count') {
    return { id, ok: false, error: `host_orchestrated_fn:${fn}` };
  }
  // 缓存命中统计（cargo test 的 agent_session_cache_reuse 断言）：
  // 链式 op 必须 hits ≥ 1（失配重开则 misses 增长、hits 恒 0 → 测试红）。
  if (fn === 'session_cache_stats') {
    return { id, ok: true, json: JSON.stringify({ ok: true, ...cacheStats }) };
  }
  // 泄漏契约探针（上游 #1 提供 session_count 后可测）：同一进程内 open×2 →
  // count +2 → close×2 → count 归零。Rust 侧断言 before/during/after。
  if (fn === 'session_count_probe') {
    const before = ex.session_count();
    const h1 = ex.session_open(writeStr(req.mbt ?? ''));
    // 对齐 wasmtime_host:h1 已开后,第二次 open 失败先回收 h1(探针自身不做泄漏源);
    // 负句柄分支同样互不泄漏
    let h2;
    try {
      h2 = ex.session_open(writeStr(req.mbt ?? ''));
    } catch (err) {
      try { ex.session_close(h1); } catch (_) { /* 实例已不可用 */ }
      return { id, ok: false, error: `session_open_failed:${err && err.message || err}` };
    }
    if (!Number.isInteger(h1) || h1 < 0 || !Number.isInteger(h2) || h2 < 0) {
      if (Number.isInteger(h1) && h1 >= 0) { try { ex.session_close(h1); } catch (_) {} }
      if (Number.isInteger(h2) && h2 >= 0) { try { ex.session_close(h2); } catch (_) {} }
      return { id, ok: false, error: `session_open_failed:${h1}/${h2}` };
    }
    const during = ex.session_count();
    ex.session_close(h1);
    ex.session_close(h2);
    return { id, ok: true, json: JSON.stringify({ before, during, after: ex.session_count() }) };
  }
  if (!(fn in ARITY) && !fn.startsWith('session_')) {
    return { id, ok: false, error: `unknown_fn:${fn}` };
  }
  if (typeof ex[fn] !== 'function') {
    return { id, ok: false, error: `unknown_fn:${fn}` };
  }
  // 全部调用经编解码（classic wasm 字符串是内存对象）；返回值为字符串指针。
  // session_tap 例外：artboard 是字符串，x/y 是 f64 参数（不能当指针传）。
  // 参数个数校验：缺参会以指针 0 触发不透明的 wasm trap——转成明确错误。
  const SESSION_MIN_ARGS = { session_tap: 3 };  // 其余 session_<ab> 类：0 或 1 参皆合法
  try {
    if (fn.startsWith('session_')) {
      const handle = cachedSession(req.mbt ?? '');
      if (!Number.isInteger(handle) || handle < 0) {
        return { id, ok: false, error: `session_open_failed:${handle}` };
      }
      const op = String(req.op ?? '');
      const parts = op.split(/\s+/).filter(Boolean);
      const minArgs = SESSION_MIN_ARGS[fn] ?? 0;
      if (parts.length < minArgs) {
        return { id, ok: false, error: `op_missing_args:${fn} 需要 ${minArgs} 个参数，得到 ${parts.length}` };
      }
      let args;
      if (fn === 'session_tap') {
        args = [writeStr(parts[0]), Number(parts[1]), Number(parts[2])];
      } else {
        args = SESSION_WHOLE_ARG.has(fn)
          ? [writeStr(op)]
          : parts.map(writeStr);
      }
      let outStr;
      try {
        outStr = readStr(ex[fn](handle, ...args));
      } catch (e) {
        // wasm trap/半途失败：会话状态不可信 → 弃缓存，下次按权威 mbt 重开
        try { ex.session_close(handle); } catch (_) { /* 实例已不可用 */ }
        sessCache = null;
        return { id, ok: false, error: `wasm_panic:${e.message}` };
      }
      if (SESSION_MUTATING.has(fn)) {
        let r = null;
        try {
          r = JSON.parse(outStr);
        } catch { /* 信封形状异常：原样透传给调用方判断 */ }
        if (r && r.ok === true && typeof r.mbt === 'string') {
          sessCache.mbt = r.mbt;
        }
        if (fn === 'session_apply_agent' || fn === 'session_apply_human') {
          // session 信封只有 {ok,mbt}——同句柄补画板索引（内存查询，无重解析）。
          // best-effort：补索引失败不得把**已提交**的 op 报成失败（响应保持 ok），
          // 但 wasm trap 后会话状态不可信 → 弃缓存（下次按权威 mbt 重开）。
          try {
            const la = JSON.parse(readStr(ex.session_list_artboards(handle)));
            if (la.ok === true && Array.isArray(la.data) && r && r.ok === true) {
              r.artboards = la.data;
              outStr = JSON.stringify(r);
            }
          } catch (_) {
            try { ex.session_close(handle); } catch (_) { /* 实例已不可用 */ }
            sessCache = null;
          }
        }
      }
      return { id, ok: true, json: outStr };
    }
    const args = ARITY[fn] === 0
      ? []
      : ARITY[fn] === 1
        ? [writeStr(req.mbt ?? '')]
        : [writeStr(req.mbt ?? ''), writeStr(req.op ?? '')];
    return { id, ok: true, json: readStr(ex[fn](...args)) };
  } catch (e) {
    // 异常后会话状态不可信（含 cachedSession 内 close/open 自身 trap）→ 弃缓存，
    // 下次按权威 mbt 重开（对齐前端桥的外层 catch 语义）
    try { if (sessCache) ex.session_close(sessCache.handle); } catch (_) { /* 实例已不可用 */ }
    sessCache = null;
    return { id, ok: false, error: `wasm_panic:${e.message}` };
  }
}

const once = process.argv[2];
if (once === '--once-file') {
  try {
    const req = JSON.parse(readFileSync(process.argv[3] ?? '', 'utf8'));
    process.stdout.write(JSON.stringify(handle(req)) + '\n');
  } catch (e) {
    process.stdout.write(JSON.stringify({ id: null, ok: false, error: `bad_request:${e.message}` }) + '\n');
  }
  process.exit(0);
}

const rl = createInterface({ input: process.stdin });
rl.on('line', (line) => {
  const s = line.trim();
  if (!s) return;
  let req;
  try {
    req = JSON.parse(s);
  } catch {
    process.stdout.write(JSON.stringify({ id: null, ok: false, error: 'bad_json' }) + '\n');
    return;
  }
  process.stdout.write(JSON.stringify(handle(req)) + '\n');
});
rl.on('close', () => process.exit(0));
