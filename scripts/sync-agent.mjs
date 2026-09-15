#!/usr/bin/env node
// 打包前置同步（产物统一落在 src-tauri/agent/，tauri resources 携带）：
// 1) agent/ 桥 → esbuild 单文件 → agent-bridge.mjs（无需 node_modules）
// 2) MoonViz 引擎独立二进制 → moonviz-cli.exe（moon build --target native 产物）
// 3) node 运行时 → node.exe（从 nodejs.org 官方 dist 下载，桥的自包含 JS 引擎）
// 最终用户无需安装 MoonBit 工具链、引擎源码或 Node.js。
import { copyFileSync, chmodSync, rmSync, mkdirSync, existsSync, createWriteStream } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { pipeline } from 'node:stream/promises';

const NODE_VERSION = 'v20.19.0'; // LTS，与本地开发一致

const root = dirname(dirname(fileURLToPath(import.meta.url))); // deepDesign/
const src = join(root, 'agent');
const dst = join(root, 'src-tauri', 'agent');

function fail(msg) {
  console.error(`[sync-agent] ${msg}`);
  process.exit(1);
}

if (!existsSync(join(src, 'agent-bridge.mjs'))) fail('找不到 agent/agent-bridge.mjs');
if (!existsSync(join(src, 'node_modules'))) fail('agent/node_modules 缺失：请先在 agent/ 目录运行 npm ci');

// ---- 1) 桥单文件打包 ----
const r = spawnSync('npm', ['run', 'bundle'], { cwd: src, stdio: 'inherit', shell: process.platform === 'win32' });
if (r.status !== 0) fail('npm run bundle 失败');

// ---- 2) 引擎二进制定位（本地与 CI 同为 <root>/../moonviz 兄弟布局）----
const engineBinCandidates = [
  process.env.MOONVIZ_CLI,
  join(root, '..', 'moonviz', '_build', 'native', 'release', 'build', 'cli', 'cli.exe'),
].filter(Boolean);
const engineBin = engineBinCandidates.find(p => existsSync(p));
if (!engineBin) {
  fail(
    '找不到引擎二进制：请在兄弟目录 moonviz/ 运行 ' +
    '`moon build --release --target native cli`（产物 _build/native/release/build/cli/cli.exe），' +
    '或设置 MOONVIZ_CLI 指向已有二进制。'
  );
}

// ---- 3) node 运行时（可由 MOONVIZ_NODE 直接指定，否则从官方 dist 下载）----
function nodeDist() {
  const { platform: p, arch } = process;
  if (p === 'darwin') return { id: `darwin-${arch}`, ext: 'tar.gz', bin: `node-${NODE_VERSION}-darwin-${arch}/bin/node` };
  if (p === 'win32') return { id: 'win-x64', ext: 'zip', bin: `node-${NODE_VERSION}-win-x64/node.exe` };
  return { id: `linux-${arch}`, ext: 'tar.gz', bin: `node-${NODE_VERSION}-linux-${arch}/bin/node` };
}

async function fetchNodeRuntime(dstNode) {
  const dist = nodeDist();
  const url = `https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-${dist.id}.${dist.ext}`;
  const work = join(tmpdir(), `deepdesign-node-${NODE_VERSION}-${dist.id}`);
  const archive = `${work}.${dist.ext}`;
  if (!existsSync(archive)) {
    console.log(`[sync-agent] 下载 ${url}`);
    const res = await fetch(url);
    if (!res.ok) fail(`下载 node 失败：HTTP ${res.status}`);
    rmSync(work, { recursive: true, force: true });
    await pipeline(res.body, createWriteStream(archive));
  }
  const t = spawnSync('tar', ['-xf', archive, '-C', tmpdir()]);
  if (t.status !== 0) fail(`解压 node 失败：${t.stderr}`);
  const extracted = join(tmpdir(), dist.bin);
  if (!existsSync(extracted)) fail(`解压后找不到 ${extracted}`);
  copyFileSync(extracted, dstNode);
  console.log(`[sync-agent] node ${NODE_VERSION} (${dist.id}) -> ${dstNode}`);
}

// ---- 落位（统一 .exe 后缀命名，跨平台免判断）----
mkdirSync(dst, { recursive: true });
copyFileSync(join(src, 'agent-bridge.bundle.mjs'), join(dst, 'agent-bridge.mjs'));
copyFileSync(engineBin, join(dst, 'moonviz-cli.exe'));
chmodSync(join(dst, 'moonviz-cli.exe'), 0o755);

const dstNode = join(dst, 'node.exe');
try {
  if (process.env.MOONVIZ_NODE && existsSync(process.env.MOONVIZ_NODE)) {
    copyFileSync(process.env.MOONVIZ_NODE, dstNode);
    console.log(`[sync-agent] MOONVIZ_NODE -> ${dstNode}`);
  } else if (!existsSync(dstNode)) {
    await fetchNodeRuntime(dstNode);
  } else {
    console.log(`[sync-agent] node.exe 已缓存，跳过下载`);
  }
  chmodSync(dstNode, 0o755);
} catch (e) {
  fail(`node 运行时准备失败：${e.message}`);
}

console.log('[sync-agent] 同步完成：agent-bridge.mjs + moonviz-cli.exe + node.exe');
