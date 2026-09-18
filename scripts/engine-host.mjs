#!/usr/bin/env node
// engine-host.mjs —— MoonViz wasm 引擎的 Node 宿主。
//
// 生产环境引擎跑在 WebView（frontend 内嵌 wasm）；Rust 侧（agent.rs）通过
// Tauri 事件桥调用。本脚本是同一份 wasm 的命令行宿主，供 cargo test 在无
// WebView 的环境里驱动「真引擎」跑端到端与契约测试（node ≥ 24）。
//
// 两种模式：
//   1. 行协议（长驻）：stdin 每行一个请求 {"id":n,"fn":...,"mbt":...,"op":...}，
//      stdout 回一行 {"id":n,"ok":true,"json":"<结果 JSON 字符串>"}。
//   2. 单发（--once-file <路径>）：请求 JSON 存于文件（Rust 侧写入临时文件，
//      argv 只传我们生成的路径，不携带文档内容），stdout 回一行响应后退出。
//      cargo test 用这种模式。
// fn 取值分三类：
//   1. 经典导出（无状态，每调用传完整 mbt）：apply_agent_op | apply_human_op |
//      render_mbt | validate_mbt | list_templates | export_html | version_info
//   2. 检视直调（arity 0）：list_tokens | list_themes | list_ops；
//      list_components 读同步脚本产出的 components.json 快照（与前端同源）
//   3. session API（有状态）：fn 以 session_ 开头——宿主在单次调用内完成
//      session_open(mbt) → session_X(handle, ...args) → session_close 生命周期。
//      args 取自 op 字段（空白切分）；session_apply_agent/human/component_compile_b64
//      的 op 是完整串（含空格），原样单参传入。Rust 侧（agent.rs）的只读 op
//      路由依赖这组导出——wasm session 面已导出全部检视命令。
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
const mod = new WebAssembly.Module(bytes, { builtins: ['js-string'], importedStringConstants: '_' });
const ex = new WebAssembly.Instance(mod, {}).exports;

const ARITY = {
  apply_agent_op: 2, apply_human_op: 2, render_mbt: 1, validate_mbt: 1,
  export_html: 1, list_templates: 0, version_info: 0,
  list_tokens: 0, list_themes: 0, list_ops: 0,
};
// session op 的 op 参数是完整串（含空格），不做切分
const SESSION_WHOLE_ARG = new Set([
  'session_apply_agent', 'session_apply_human', 'session_component_compile_b64',
]);

function handle(req) {
  const { id, fn } = req;
  if (fn === 'list_components') {
    const comps = existsSync(COMPONENTS) ? readFileSync(COMPONENTS, 'utf8') : '[]';
    return { id, ok: true, json: JSON.stringify({ ok: true, components: JSON.parse(comps) }) };
  }
  if (!(fn in ARITY) && !fn.startsWith('session_')) {
    return { id, ok: false, error: `unknown_fn:${fn}` };
  }
  if (typeof ex[fn] !== 'function') {
    return { id, ok: false, error: `unknown_fn:${fn}` };
  }
  // session API：单次调用内完成 open → op → close 生命周期
  if (fn.startsWith('session_')) {
    try {
      const handle = ex.session_open(req.mbt ?? '');
      if (!Number.isInteger(handle) || handle < 0) {
        return { id, ok: false, error: `session_open_failed:${handle}` };
      }
      const op = String(req.op ?? '');
      const args = SESSION_WHOLE_ARG.has(fn)
        ? [op]
        : op.split(/\s+/).filter(Boolean);
      const out = ex[fn](handle, ...args);
      ex.session_close(handle);
      return { id, ok: true, json: out };
    } catch (e) {
      return { id, ok: false, error: `wasm_panic:${e.message}` };
    }
  }
  const args = ARITY[fn] === 0 ? [] : ARITY[fn] === 1 ? [req.mbt ?? ''] : [req.mbt ?? '', req.op ?? ''];
  try {
    return { id, ok: true, json: ex[fn](...args) };
  } catch (e) {
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
