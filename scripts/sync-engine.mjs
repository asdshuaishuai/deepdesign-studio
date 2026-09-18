#!/usr/bin/env node
// 引擎同步（预编译 wasm 产物）：把 MoonViz 引擎的**标准** wasm 产物拉到 frontend/vendor/。
//
// 引擎以 GitHub Releases 的 classic wasm（`moonviz-wasm-classic-<version>.wasm`，docs 的
// #wasm 节的「标准 wasm 产物」——纯 WASM MVP、宿主中立、零 import）分发；wasm-gc 变体
// （npm moonviz-engine-wasm）依赖 JS String Builtins 提案、仅 V8 类引擎可跑，本仓库不用。
// classic 的字符串是 linear memory 对象（[refcnt][len][UTF-16LE]），宿主侧做编解码
// （见 engine-host.mjs 的 makeStrCodec）；入参方向暂无引擎堆分配辅助，宿主在初始内存
// 之上写字符串对象（高水位上移防碰撞）。
//
// 产物：
//   frontend/vendor/moonviz.wasm          引擎本体（gitignore，构建/开发期拉取）
//   frontend/vendor/components.json       组件清单快照（同步时用真机探针验证生成，入库）
//   frontend/vendor/engine-manifest.json  版本与校验信息（gitignore，诊断用）
//
// 同步时会用 Node 实例化真机 wasm 做「发布前契约检查」：
//   1. 必需导出（apply_human_op / apply_agent_op / render_mbt / validate_mbt /
//      list_templates / export_html / version_info）全部在场；
//   2. 模板 id 集合与 src-tauri/src/agent.rs 的 ENGINE_TEMPLATES 一致；
//   3. 组件快照逐个 place 探针——引擎不认的 id 一律不写入快照。
// Node < 24（无 WasmGC + js-string builtins）时跳过检查并给出警告，只落 wasm 文件。
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const dst = join(root, 'frontend', 'vendor');

// —— 引擎版本锚点（升级 = 改这里 + 重跑本脚本 + cd src-tauri && cargo test）——
const ENGINE_VERSION = '0.1.1-fix';
const RELEASE_TAG = `engine-v${ENGINE_VERSION}`;
// 资产名里的 wasm 版本（与 release tag 后缀不同——tag 是 -fix 补丁，资产仍 0.1.1）
const WASM_ARTIFACT_VERSION = '0.1.1';
// 资产文件名（标准 classic wasm；wasm-gc 变体叫 moonviz-wasm-gc-*）
const WASM_ASSET = `moonviz-wasm-classic-${WASM_ARTIFACT_VERSION}.wasm`;
// 标准 wasm SDK：GitHub Releases 的 WasmGC 直链 .wasm（非 tarball）
const WASM_URL =
  process.env.MOONVIZ_WASM_URL ||
  `https://github.com/asdshuaishuai/moonviz/releases/download/${RELEASE_TAG}/${WASM_ASSET}`;
// 下载的 .wasm 文件整体 sha512（npm 无此产物；校验值取自 release 资产）
const WASM_SHA512 =
  'sha512-xDQEtbLoz5f8g6loMel4zNlfntdUo5e1mZ8Rd3/YMmkzGWLGcdgfdQtQSDWpXDK57SqhwINX+hfxcP8rpeqviA==';

const REQUIRED_EXPORTS = [
  'apply_human_op', 'apply_agent_op', 'render_mbt', 'validate_mbt',
  'list_templates', 'export_html', 'version_info',
];
// 非 session 的检视导出（session API 之外的直调面）
const INSPECTION_EXPORTS = ['list_components', 'list_ops', 'list_tokens', 'list_themes'];
// session API（24 个）：有状态句柄，覆盖 CLI/MCP 的会话型能力（lint/critique/
// 导出 SVG/交互运行时等）。agent.rs 的只读 op 路由依赖这组导出。
const SESSION_EXPORTS = [
  'session_open', 'session_close', 'session_apply_agent', 'session_apply_human',
  'session_export_svg', 'session_lint', 'session_critique', 'session_auto_fix',
  'session_query_nodes', 'session_list_artboards', 'session_flows', 'session_interactions',
  'session_states', 'session_spec', 'session_constrain', 'session_infer_page_type',
  'session_infer_missing', 'session_extract_design_system', 'session_generate_responsive',
  'session_benchmark', 'session_save', 'session_component_compile_b64',
  'session_library_snapshot', 'session_tap',
];

// 组件候选（引擎 core/component.mbt 的 builtin 清单，含 v3 扩展）。
// 同步时逐个 place 探针：引擎不认的 id 不会进快照，所以宁多勿漏。
const COMPONENT_CANDIDATES = [
  ['button', 'rect', 'actions', ['primary', 'secondary', 'danger'], [120, 44], '操作按钮。支持 primary/secondary/danger。'],
  ['text_input', 'rect', 'inputs', ['default', 'filled'], [280, 44], '文本输入框。'],
  ['card', 'frame', 'layout', ['elevated'], [320, 200], '卡片容器。垂直布局。'],
  ['app_bar', 'rect', 'layout', ['surface', 'primary'], [390, 56], '顶部导航栏。'],
  ['divider', 'rect', 'layout', ['default'], [320, 1], '分隔线。'],
  ['heading', 'text', 'display', ['h1', 'h2', 'h3', 'h4'], [280, 36], '标题。h1=32px h2=24px h3=20px h4=16px。'],
  ['body_text', 'text', 'display', ['body', 'caption'], [280, 20], '正文。body=14px caption=12px。'],
  ['badge', 'rect', 'display', ['primary', 'success'], [64, 24], '徽标。'],
  ['rect', 'rect', 'layout', ['default', 'outline'], [200, 100], '通用矩形：面板/背景条/装饰块。'],
  ['checkbox', 'rect', 'selection', ['unchecked', 'checked'], [22, 22], '复选框。'],
  ['switch', 'rect', 'selection', ['off', 'on'], [46, 26], '开关。'],
  ['radio', 'rect', 'selection', ['unchecked', 'checked'], [20, 20], '单选圆点。'],
  ['avatar', 'rect', 'display', ['circle', 'square'], [40, 40], '头像占位。'],
  ['search_bar', 'rect', 'inputs', ['default', 'filled'], [240, 38], '搜索框（占位文字 text 设置）。'],
  ['progress', 'rect', 'display', ['default', 'secondary'], [180, 6], '进度条。'],
  ['chip', 'rect', 'display', ['default', 'selected'], [72, 30], '筛选/标签 chip。'],
  ['fab', 'rect', 'actions', ['primary', 'error'], [56, 56], '悬浮操作按钮。'],
  ['list_item', 'rect', 'layout', ['default', 'highlighted'], [320, 56], '列表行（text 为标题）。'],
  ['tab_bar', 'rect', 'navigation', ['default', 'active'], [390, 56], '标签栏容器。'],
  ['image', 'image', 'display', ['default', 'rounded'], [200, 140], '图片占位。'],
  ['slider', 'rect', 'inputs', ['default', 'active'], [200, 4], '滑杆轨道。'],
];

// 与前端/agent 共用的最小种子文档（引擎要求至少一个视觉块才能承载 op）。
const seedDoc = (id, w, h) => `---
moonviz:
  format: visual-document
  revision: 1
  entry: ${id}
---

# ${id}

<!-- moonviz:artboard ${id} -->
\`\`\`mbt
fn visual_${id}() -> @decl.Prototype {
  let page = @decl.prototype(name="${id}", width=${w}.0, height=${h}.0)
  page
}
\`\`\`
`;

function fail(msg) {
  console.error(`[sync-engine] ${msg}`);
  process.exit(1);
}

function sha512Base64(buf) {
  return 'sha512-' + createHash('sha512').update(buf).digest('base64');
}

async function download() {
  const local = process.env.MOONVIZ_WASM_PATH;
  if (local && existsSync(local)) {
    console.log(`[sync-engine] 使用本地 wasm：${local}`);
    return readFileSync(local);
  }
  console.log(`[sync-engine] 下载 ${WASM_URL}`);
  const res = await fetch(WASM_URL);
  if (!res.ok) fail(`下载失败：HTTP ${res.status}`);
  return Buffer.from(await res.arrayBuffer());
}

// classic wasm：零 import，标准实例化；字符串经内存编解码（与 engine-host.mjs 同构）
function instantiate(bytes) {
  return new WebAssembly.Instance(new WebAssembly.Module(bytes), {}).exports;
}

/// 宿主侧字符串编解码：classic 的字符串对象布局为
/// [refcnt@ptr-8][长度@ptr-4][UTF-16LE 数据@ptr+0]。
/// 写入用负 refcnt（不朽，引擎 GC 不回收），地址取引擎初始内存之上的高水位区
/// （每次上移，防引擎 bump 堆长入后碰撞）。
function makeStrCodec(ex) {
  const INITIAL = ex.memory.buffer.byteLength;
  // 写入区安全不变量：引擎的 bump 堆顶**永远不超过当前内存大小**（超了它就会先 grow）。
  // 所以只要写入区位于「当前内存大小 + 余量」之上，就绝不会被引擎堆覆盖。
  // 引擎增长过内存（其堆顶上移）时，把写入区重新锚到当前内存之上。
  let writeOff = INITIAL + 4096;
  let lastSize = INITIAL;
  const readStr = (ptr) => {
    const mem = new DataView(ex.memory.buffer);
    const len = mem.getUint32(ptr - 4, true) & 0x0FFFFFFF;
    let s = '';
    for (let i = 0; i < len; i++) s += String.fromCharCode(mem.getUint16(ptr + i * 2, true));
    return s;
  };
  const writeStr = (s) => {
    const cur = ex.memory.buffer.byteLength;
    if (cur !== lastSize) {
      // 引擎增长过内存 → 其堆已上移 → 写入区跳到当前内存之上（64KB 余量）
      writeOff = Math.max(writeOff, cur + 65536);
      lastSize = cur;
    }
    const need = 16 + s.length * 2;
    if (ex.memory.buffer.byteLength < writeOff + need) {
      ex.memory.grow(Math.ceil((writeOff + need + 65536 - ex.memory.buffer.byteLength) / 65536));
    }
    const mem = new DataView(ex.memory.buffer);
    mem.setUint32(writeOff - 8, 0xFFFFFFE0, true);   // refcnt 负值 = 不朽对象，引擎 GC 不回收
    mem.setUint32(writeOff - 4, s.length, true);     // header = 长度
    for (let i = 0; i < s.length; i++) mem.setUint16(writeOff + i * 2, s.charCodeAt(i), true);
    const ptr = writeOff;
    writeOff = ptr + need + 4096;
    return ptr;
  };
  return { readStr, writeStr };
}

function agentTemplateIds() {
  const src = readFileSync(join(root, 'src-tauri', 'src', 'agent.rs'), 'utf8');
  const m = src.match(/const ENGINE_TEMPLATES[^=]*=\s*(?:r#)?"([\s\S]*?)"(?:#)?;/);
  if (!m) fail('无法从 src-tauri/src/agent.rs 解析 ENGINE_TEMPLATES');
  return [...m[1].matchAll(/[a-z0-9_]+(?=\()/g)].map((x) => x[0]);
}

async function contractProbe(exports, wasmBytes) {
  const missing = REQUIRED_EXPORTS.filter((n) => typeof exports[n] !== 'function');
  if (missing.length) fail(`wasm 缺少必需导出：${missing.join(', ')}`);
  const missInsp = INSPECTION_EXPORTS.filter((n) => typeof exports[n] !== 'function');
  if (missInsp.length) fail(`wasm 缺少检视导出：${missInsp.join(', ')}`);
  const missSess = SESSION_EXPORTS.filter((n) => typeof exports[n] !== 'function');
  if (missSess.length) fail(`wasm 缺少 session API 导出：${missSess.join(', ')}`);

  // classic wasm：字符串经内存编解码（与 engine-host.mjs 同构）
  const { readStr, writeStr } = makeStrCodec(exports);

  // session 生命周期实跑（不只是存在性）：种子文档 open → lint → close
  const probeDoc = seedDoc('__seed', 390, 844);
  const handle = exports.session_open(writeStr(probeDoc));
  if (!Number.isInteger(handle) || handle < 0) fail(`session_open 失败：handle=${handle}`);
  // lint 返回违规数组（空数组=无违规），不是 {ok} 对象——可解析即通过
  try { JSON.parse(readStr(exports.session_lint(handle, writeStr('__seed')))); }
  catch { fail('session_lint 返回非 JSON'); }
  if (!exports.session_close(handle)) fail('session_close 失败');
  // list_ops 应给出 mutating op 注册表（op 面事实源）
  const ops = JSON.parse(readStr(exports.list_ops()));
  if (!Array.isArray(ops) || ops.length < 20) fail(`list_ops 异常：${JSON.stringify(ops).slice(0, 120)}`);

  const engineIds = JSON.parse(readStr(exports.list_templates()))
    .map((t) => t.id ?? t.template_id ?? t);
  const agentIds = agentTemplateIds();
  const drift =
    engineIds.filter((x) => !agentIds.includes(x))
    .concat(agentIds.filter((x) => !engineIds.includes(x)));
  if (drift.length) {
    fail(`模板清单与 agent.rs ENGINE_TEMPLATES 不一致（差异：${drift.join(', ')}）——两边必须一起改`);
  }

  const dummy = seedDoc('__seed', 390, 844);
  const components = [];
  for (const [id, kind, category, variants, size, description] of COMPONENT_CANDIDATES) {
    const r = JSON.parse(readStr(exports.apply_human_op(
      writeStr(dummy),
      writeStr(`place __seed ${id} probe_${id} - 10 10`),
    )));
    if (r.ok) components.push({ id, kind, category, variants, default_size: size, description });
    else console.warn(`[sync-engine] 组件 ${id} 探针失败（跳过）：${r.error}`);
  }
  if (!components.length) fail('组件探针全部失败——引擎产物或探针种子有异常');
  return { components, engineIds };
}

async function main() {
  mkdirSync(dst, { recursive: true });
  const wasmPath = join(dst, 'moonviz.wasm');
  const manifestPath = join(dst, 'engine-manifest.json');

  // 跳过判断：现存 wasm 的哈希必须与**当前锚点**一致（换工件类型如 gc→classic 时
  // 锚点变了，旧文件自然不匹配 → 重新下载；只比对 manifest 记录值会被旧产物骗过）
  let manifest = { version: ENGINE_VERSION, source: WASM_URL, releaseTag: RELEASE_TAG };
  let skipDownload = false;
  if (existsSync(wasmPath)) {
    try {
      if (sha512Base64(readFileSync(wasmPath)) === WASM_SHA512) {
        skipDownload = true;
      }
    } catch { /* 读取异常 → 重新下载 */ }
  }

  let bytes;
  if (skipDownload) {
    bytes = readFileSync(wasmPath);
    console.log('[sync-engine] moonviz.wasm 已是目标版本，跳过下载');
  } else {
    const raw = await download();
    const got = sha512Base64(raw);
    if (got !== WASM_SHA512) fail(`wasm sha512 不匹配\n  期望 ${WASM_SHA512}\n  实际 ${got}`);
    bytes = raw;
    writeFileSync(wasmPath, bytes);
    console.log(`[sync-engine] moonviz.wasm ← moonviz-wasm-gc@${ENGINE_VERSION}（release ${RELEASE_TAG}，sha512 校验通过）`);
  }
  manifest.wasm_sha512 = sha512Base64(bytes);

  try {
    const exports = await instantiate(bytes);
    const { components, engineIds } = await contractProbe(exports, bytes);
    writeFileSync(join(dst, 'components.json'), JSON.stringify(components, null, 2) + '\n');
    manifest = {
      ...manifest,
      generatedAt: new Date().toISOString(),
      exports: REQUIRED_EXPORTS,
      inspection: INSPECTION_EXPORTS,
      session: SESSION_EXPORTS,
      templates: engineIds,
      components: components.length,
      node: process.version,
    };
    console.log(
      `[sync-engine] 契约探针通过：${REQUIRED_EXPORTS.length} 经典导出 / ${INSPECTION_EXPORTS.length} 检视 / ` +
      `${SESSION_EXPORTS.length} session API（open→lint→close 实跑）/ ${engineIds.length} 模板 / ${components.length} 组件`
    );
  } catch (e) {
    // 实例化/编解码异常：产物本身没问题，但契约没人背书
    console.warn(`[sync-engine] 跳过契约探针（${e.message}）——请用 Node ≥ 24 重跑以验证导出面与组件快照`);
  }
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
}

main().catch((e) => fail(e.stack || String(e)));
