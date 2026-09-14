#!/usr/bin/env node
// 打包前置同步：
// 1) agent/ 桥 → esbuild 单文件 → src-tauri/agent/agent-bridge.mjs
//    （tauri resources glob 不支持 .. 路径；单文件无需 node_modules）
// 2) MoonViz 引擎独立二进制 → src-tauri/agent/moonviz-cli.exe
//    （moon build --release --target native cli 的自包含产物，
//     运行时优先于 moon run，最终用户无需 MoonBit 工具链）
import { copyFileSync, rmSync, mkdirSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url))); // deepDesign/
const src = join(root, 'agent');
const dst = join(root, 'src-tauri', 'agent');

if (!existsSync(join(src, 'agent-bridge.mjs'))) {
  console.error('[sync-agent] 找不到 agent/agent-bridge.mjs');
  process.exit(1);
}
if (!existsSync(join(src, 'node_modules'))) {
  console.error('[sync-agent] agent/node_modules 缺失：请先在 agent/ 目录运行 npm ci');
  process.exit(1);
}

// ---- 1) 桥单文件打包 ----
const r = spawnSync('npm', ['run', 'bundle'], { cwd: src, stdio: 'inherit', shell: process.platform === 'win32' });
if (r.status !== 0) {
  console.error('[sync-agent] npm run bundle 失败');
  process.exit(1);
}

// ---- 2) 引擎二进制定位（本地与 CI 同为 <root>/../moonviz 兄弟布局）----
const engineBinCandidates = [
  process.env.MOONVIZ_CLI,
  join(root, '..', 'moonviz', '_build', 'native', 'release', 'build', 'cli', 'cli.exe'),
].filter(Boolean);
const engineBin = engineBinCandidates.find(p => existsSync(p));
if (!engineBin) {
  console.error(
    '[sync-agent] 找不到引擎二进制：请在兄弟目录 moonviz/ 运行 ' +
    '`moon build --release --target native cli`（产物 _build/native/release/build/cli/cli.exe），' +
    '或设置 MOONVIZ_CLI 指向已有二进制。'
  );
  process.exit(1);
}

// ---- 3) 落位（统一命名 moonviz-cli.exe，与引擎自身产物命名一致，跨平台免后缀判断）----
rmSync(dst, { recursive: true, force: true });
mkdirSync(dst, { recursive: true });
copyFileSync(join(src, 'agent-bridge.bundle.mjs'), join(dst, 'agent-bridge.mjs'));
copyFileSync(engineBin, join(dst, 'moonviz-cli.exe'));
console.log(`[sync-agent] agent-bridge.bundle.mjs -> src-tauri/agent/agent-bridge.mjs`);
console.log(`[sync-agent] ${engineBin} -> src-tauri/agent/moonviz-cli.exe`);
