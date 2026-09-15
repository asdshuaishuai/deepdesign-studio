#!/usr/bin/env node
// 打包前置同步：将 MoonViz 引擎独立二进制 staging 到 src-tauri/engine/。
// （Agent 基座已 Rust 原生化——无 JS 桥、无 node 运行时，此脚本是唯一打包产物。）
// 产物：moon build --release --target native cli 的自包含 CLI，
// 运行时直接执行，最终用户无需 MoonBit 工具链。
import { copyFileSync, chmodSync, rmSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url))); // deepDesign/
const dst = join(root, 'src-tauri', 'engine');

function fail(msg) {
  console.error(`[sync-engine] ${msg}`);
  process.exit(1);
}

// 本地与 CI 同为 <root>/../moonviz 兄弟布局
const candidates = [
  process.env.MOONVIZ_CLI,
  join(root, '..', 'moonviz', '_build', 'native', 'release', 'build', 'cli', 'cli.exe'),
].filter(Boolean);
const engineBin = candidates.find(p => existsSync(p));
if (!engineBin) {
  fail(
    '找不到引擎二进制：请在兄弟目录 moonviz/ 运行 ' +
    '`moon build --release --target native cli`（产物 _build/native/release/build/cli/cli.exe），' +
    '或设置 MOONVIZ_CLI 指向已有二进制。'
  );
}

rmSync(dst, { recursive: true, force: true });
mkdirSync(dst, { recursive: true });
copyFileSync(engineBin, join(dst, 'moonviz-cli.exe'));
chmodSync(join(dst, 'moonviz-cli.exe'), 0o755);
console.log(`[sync-engine] ${engineBin} -> src-tauri/engine/moonviz-cli.exe`);
