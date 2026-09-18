#!/usr/bin/env node
// 引擎同步（预编译 wasm 产物）：把 MoonViz 引擎的官方 WasmGC 产物拉到 frontend/vendor/。
//
// 引擎不再以兄弟仓库源码 + MoonBit 现场构建的方式集成；唯一分发物是
// npm `moonviz-engine-wasm`（与 GitHub Releases engine-v* 同源），一份 wasm
// 全平台通用（WebView 内进程执行），无子进程、无工具链。
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
const ENGINE_VERSION = '0.1.1';
const NPM_TARBALL =
  process.env.MOONVIZ_WASM_URL ||
  `https://registry.npmjs.org/moonviz-engine-wasm/-/moonviz-engine-wasm-${ENGINE_VERSION}.tgz`;
// tarball 整体的 npm dist.integrity（sha512-base64）——对下载的 .tgz 校验
const TARBALL_SHA512 =
  'sha512-WwWS6qal44/kNkJm72frWLVHZes+gdzQh7q9cCdyPh5icY5d74tIeledlZRc4bcydTvwEBWX7cyiyVpDPc35vg==';

const REQUIRED_EXPORTS = [
  'apply_human_op', 'apply_agent_op', 'render_mbt', 'validate_mbt',
  'list_templates', 'export_html', 'version_info',
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
    console.log(`[sync-engine] 使用本地 tarball：${local}`);
    return readFileSync(local);
  }
  console.log(`[sync-engine] 下载 ${NPM_TARBALL}`);
  const res = await fetch(NPM_TARBALL);
  if (!res.ok) fail(`下载失败：HTTP ${res.status}`);
  return Buffer.from(await res.arrayBuffer());
}

function extractWasm(tarball) {
  const tmp = join(tmpdir(), `moonviz-wasm-${Date.now()}`);
  mkdirSync(tmp, { recursive: true });
  const tgz = join(tmp, 'engine.tgz');
  writeFileSync(tgz, tarball);
  // bsdtar：Windows 10+/macOS/Linux CI 均自带
  execFileSync('tar', ['-xzf', tgz, '-C', tmp], { stdio: 'pipe' });
  const inner = join(tmp, 'package', 'dist', 'moonviz.wasm');
  if (!existsSync(inner)) fail('tarball 中没有 package/dist/moonviz.wasm');
  const bytes = readFileSync(inner);
  rmSync(tmp, { recursive: true, force: true });
  return bytes;
}

async function instantiate(bytes) {
  const mod = new WebAssembly.Module(bytes, {
    builtins: ['js-string'],
    importedStringConstants: '_',
  });
  return new WebAssembly.Instance(mod, {}).exports;
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

  const engineIds = JSON.parse(exports.list_templates())
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
    const r = JSON.parse(exports.apply_human_op(dummy, `place __seed ${id} probe_${id} - 10 10`));
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

  // 跳过判断：现存 wasm 的哈希与上次 manifest 记录一致且版本未变 → 不再下载
  let manifest = { version: ENGINE_VERSION, source: NPM_TARBALL };
  let skipDownload = false;
  if (existsSync(wasmPath) && existsSync(manifestPath)) {
    try {
      const prev = JSON.parse(readFileSync(manifestPath, 'utf8'));
      if (prev.version === ENGINE_VERSION && prev.wasm_sha512 === sha512Base64(readFileSync(wasmPath))) {
        skipDownload = true;
      }
    } catch { /* manifest 损坏 → 重新下载 */ }
  }

  let bytes;
  if (skipDownload) {
    bytes = readFileSync(wasmPath);
    console.log('[sync-engine] moonviz.wasm 已是目标版本，跳过下载');
  } else {
    const tarball = await download();
    const got = sha512Base64(tarball);
    if (got !== TARBALL_SHA512) fail(`tarball sha512 不匹配\n  期望 ${TARBALL_SHA512}\n  实际 ${got}`);
    bytes = extractWasm(tarball);
    writeFileSync(wasmPath, bytes);
    console.log(`[sync-engine] moonviz.wasm ← moonviz-engine-wasm@${ENGINE_VERSION}（tarball sha512 校验通过）`);
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
      templates: engineIds,
      components: components.length,
      node: process.version,
    };
    console.log(`[sync-engine] 契约探针通过：${REQUIRED_EXPORTS.length} 导出 / ${engineIds.length} 模板 / ${components.length} 组件`);
  } catch (e) {
    // Node < 24 无法实例化 WasmGC + js-string：产物本身没问题，但契约没人背书
    console.warn(`[sync-engine] 跳过契约探针（${e.message}）——请用 Node ≥ 24 重跑以验证导出面与组件快照`);
  }
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
}

main().catch((e) => fail(e.stack || String(e)));
