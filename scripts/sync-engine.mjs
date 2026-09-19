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
// 本机无法实例化 wasm 时降级为警告只落文件；实例化成功后探针失败则硬退出（引擎回归）。
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const dst = join(root, 'frontend', 'vendor');

// —— 引擎版本锚点（升级 = 改这里 + 重跑本脚本 + cd src-tauri && cargo test）——
const ENGINE_VERSION = '0.1.1-session';
const RELEASE_TAG = `engine-v${ENGINE_VERSION}`;
// 资产名里的 wasm 版本（release tag 带会话面后缀 -session，资产命名沿用 0.1.1）
const WASM_ARTIFACT_VERSION = '0.1.1';
// 资产文件名（标准 classic wasm；变体叫 moonviz-wasm-gc-*，本仓库不用）
const WASM_ASSET = `moonviz-wasm-classic-${WASM_ARTIFACT_VERSION}.wasm`;
// 标准 wasm SDK：GitHub Releases 的 WasmGC 直链 .wasm（非 tarball）
const WASM_URL =
  process.env.MOONVIZ_WASM_URL ||
  `https://github.com/asdshuaishuai/moonviz/releases/download/${RELEASE_TAG}/${WASM_ASSET}`;
// 下载的 .wasm 文件整体 sha512（npm 无此产物；校验值取自 release 资产）
const WASM_SHA512 =
  'sha512-FzIfadPPU07xIs2+LGB/ky3b724Bl4B2CJzO3ymhdT0ETIZBGLP6XzgSCZezG+/2LK5FPhTqnX/z8A3JegpwYg==';

const REQUIRED_EXPORTS = [
  'apply_human_op', 'apply_agent_op', 'render_mbt', 'validate_mbt',
  'list_templates', 'export_html', 'version_info',
];
// 非 session 的检视导出（session API 之外的直调面）
const INSPECTION_EXPORTS = ['list_components', 'list_ops', 'list_tokens', 'list_themes'];
// session API（26 个）：有状态句柄，覆盖 CLI/MCP 的会话型能力（lint/critique/
// 导出 SVG/交互运行时等）。agent.rs 的只读 op 路由依赖这组导出。
// session_count（泄漏可测）与 session_open_project_json（save→open 回灌）
// 是 engine-v0.1.1-session 新增（上游 issues #1/#4B）。
const SESSION_EXPORTS = [
  'session_open', 'session_close', 'session_apply_agent', 'session_apply_human',
  'session_export_svg', 'session_lint', 'session_critique', 'session_auto_fix',
  'session_query_nodes', 'session_list_artboards', 'session_flows', 'session_interactions',
  'session_states', 'session_spec', 'session_constrain', 'session_infer_page_type',
  'session_infer_missing', 'session_extract_design_system', 'session_generate_responsive',
  'session_benchmark', 'session_save', 'session_component_compile_b64',
  'session_library_snapshot', 'session_tap', 'session_count', 'session_open_project_json',
];

// 组件描述词典（本地展示文案，前端面板 tooltip 与 agent list_components 共用）。
// 组件的存在性/kind/category/variants/default_size 的**事实源是引擎
// list_components 导出**（52 组件注册表）；导出无 description 字段，文案留本地。
const COMPONENT_DESCRIPTIONS = {
  button: '操作按钮。支持 primary/secondary/danger。',
  text_input: '文本输入框。',
  card: '卡片容器。垂直布局。',
  app_bar: '顶部导航栏。',
  divider: '分隔线。',
  heading: '标题。h1=32px h2=24px h3=20px h4=16px。',
  body_text: '正文。body=14px caption=12px。',
  badge: '徽标。',
  rect: '通用矩形：面板/背景条/装饰块。',
  checkbox: '复选框。',
  switch: '开关。',
  radio: '单选圆点。',
  avatar: '头像占位。',
  search_bar: '搜索框（占位文字 text 设置）。',
  progress: '进度条。',
  chip: '筛选/标签 chip。',
  fab: '悬浮操作按钮。',
  list_item: '列表行（text 为标题）。',
  tab_bar: '标签栏容器。',
  image: '图片占位。',
  slider: '滑杆轨道。',
  alert: '警告条。info/success/error/warning。',
  toast: '轻提示。',
  snackbar: '底部通知条。',
  skeleton: '加载骨架。text/circle/block。',
  spinner: '加载指示器。',
  meter: '度量条（用量指示）。',
  dialog: '对话框。default/modal。',
  drawer: '抽屉。left/right。',
  popover: '气泡弹层。',
  tooltip: '深色提示气泡。',
  menu: '下拉菜单。',
  breadcrumb: '面包屑导航。',
  pagination: '分页器。',
  stepper: '步骤指示点。',
  navbar: 'Web 顶部导航条。',
  bottom_nav: '底部导航栏。',
  textarea: '多行文本输入。',
  select: '下拉选择框。',
  combobox: '可输入组合框。',
  datepicker: '日期选择框。',
  file_upload: '文件上传区。default/dashed。',
  rating: '评分。',
  tag: '标签。',
  stat: '数据统计块。',
  kbd: '键盘按键样式。',
  table: '表格。default/striped。',
  accordion: '折叠面板。',
  carousel: '轮播容器。',
  timeline: '时间轴。',
  button_group: '按钮组。default/attached。',
  link: '链接文字。',
};

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

// classic wasm：零 import，标准实例化；字符串经内存编解码（三宿主同构）
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
  let writeOff = INITIAL + 65536;
  let lastSize = INITIAL;
  const readStr = (ptr) => {
    const mem = new DataView(ex.memory.buffer);
    const len = Math.min(mem.getUint32(ptr - 4, true) & 0x0FFFFFFF, (ex.memory.buffer.byteLength - ptr) / 2);
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

  // session 生命周期实跑（不只是存在性）：种子文档 open → lint → save 回灌 → close
  const probeDoc = seedDoc('__seed', 390, 844);
  const count0 = exports.session_count();
  if (typeof count0 !== 'number') fail(`session_count 应返回裸数字，得到 ${typeof count0}`);
  const handle = exports.session_open(writeStr(probeDoc));
  if (!Number.isInteger(handle) || handle < 0) fail(`session_open 失败：handle=${handle}`);
  if (exports.session_count() !== count0 + 1) fail('session_count 未随 open 递增（上游 #1 回归）');
  // lint 自 engine-v0.1.1-session 起经 {ok,data} 信封返回（data=违规数组）——可解析即通过
  try { JSON.parse(readStr(exports.session_lint(handle, writeStr('__seed')))); }
  catch { fail('session_lint 返回非 JSON'); }
  // save→open 回灌（上游 #4B）：session_save 的 data 必须经 session_open_project_json 还原
  const sv = JSON.parse(readStr(exports.session_save(handle)));
  if (sv.ok !== true || typeof sv.data !== 'string' || !sv.data) {
    fail(`session_save 信封异常：${JSON.stringify(sv).slice(0, 120)}`);
  }
  const hRe = exports.session_open_project_json(writeStr(sv.data));
  if (!Number.isInteger(hRe) || hRe < 0) fail(`session_open_project_json 回灌失败：handle=${hRe}`);
  if (exports.session_count() !== count0 + 2) fail('session_count 未计入回灌会话');
  if (!exports.session_close(hRe)) fail('回灌会话 close 失败');
  if (!exports.session_close(handle)) fail('session_close 失败');
  if (exports.session_count() !== count0) fail('session_close 后计数未归零（会话泄漏回归）');
  // list_ops 应给出 mutating op 注册表（op 面事实源）
  const ops = JSON.parse(readStr(exports.list_ops()));
  // SKILL/AGENTS 承诺 ≥25（引擎 v0.1.1-session 实际 25 op）——探针与文档口径一致
  if (!Array.isArray(ops) || ops.length < 25) fail(`list_ops 注册表收缩（期望 ≥25）：${JSON.stringify(ops).slice(0, 120)}`);

  const engineIds = JSON.parse(readStr(exports.list_templates()))
    .map((t) => t.id ?? t.template_id ?? t);
  const agentIds = agentTemplateIds();
  const drift =
    engineIds.filter((x) => !agentIds.includes(x))
    .concat(agentIds.filter((x) => !engineIds.includes(x)));
  if (drift.length) {
    fail(`模板清单与 agent.rs ENGINE_TEMPLATES 不一致（差异：${drift.join(', ')}）——两边必须一起改`);
  }

  // 组件清单：引擎 list_components 导出是**事实源**（完整注册表，本仓库不再
  // 手工维护候选清单），逐个 place 探针验证可放置（自动裁剪异常 id），
  // description 取本地 COMPONENT_DESCRIPTIONS（导出无此字段）。
  const listed = JSON.parse(readStr(exports.list_components()));
  if (!Array.isArray(listed) || !listed.length) fail(`list_components 异常：${JSON.stringify(listed).slice(0, 120)}`);
  const dummy = seedDoc('__seed', 390, 844);
  const components = [];
  for (const c of listed) {
    if (!c || typeof c.id !== 'string' || !Array.isArray(c.variants)) {
      fail(`list_components 条目形状异常：${JSON.stringify(c).slice(0, 80)}`);
    }
    const r = JSON.parse(readStr(exports.apply_human_op(
      writeStr(dummy),
      writeStr(`place __seed ${c.id} probe_${c.id} - 10 10`),
    )));
    if (r.ok) {
      if (!COMPONENT_DESCRIPTIONS[c.id]) {
        console.warn(`[sync-engine] 组件 ${c.id} 无本地描述文案（tooltip 将为空）——补 COMPONENT_DESCRIPTIONS`);
      }
      components.push({
        id: c.id, kind: c.kind, category: c.category,
        variants: c.variants, default_size: c.default_size,
        description: COMPONENT_DESCRIPTIONS[c.id] || '',
      });
    } else {
      console.warn(`[sync-engine] 组件 ${c.id} place 探针失败（跳过）：${r.error}`);
    }
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
    console.log(`[sync-engine] moonviz.wasm ← ${WASM_ASSET}（release ${RELEASE_TAG}，sha512 校验通过）`);
  }
  manifest.wasm_sha512 = sha512Base64(bytes);

  let exports = null;
  try {
    exports = await instantiate(bytes);
  } catch (e) {
    // 只有「无法实例化」才是环境问题（降级为警告落文件）
    console.warn(`[sync-engine] 本机无法实例化 wasm（${e.message}）——产物已落盘但契约未验证`);
  }
  if (exports) {
    // 实例化成功后的探针失败 = 引擎产物回归（输出形状变了/导出缺失/模板漂移），
    // 必须硬失败退出——否则新 wasm 配旧 components.json 静默下游消费
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
  }
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
}

main().catch((e) => fail(e.stack || String(e)));
