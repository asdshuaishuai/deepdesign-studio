#!/usr/bin/env node
// 将 agent/ 桥打包为单文件并复制到 src-tauri/agent/agent-bridge.mjs。
// esbuild 把 @open-agent-loops/core/zod/openai 全部内联，打包产物
// 无需 node_modules——tauri resources 只需携带这一个文件。
// （tauri resources glob 不支持 .. 路径，故复制进 src-tauri 再引用。）
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

// 1) esbuild 单文件打包（cross-platform 经 npm script 调用本地 bin）
const r = spawnSync('npm', ['run', 'bundle'], { cwd: src, stdio: 'inherit', shell: process.platform === 'win32' });
if (r.status !== 0) {
  console.error('[sync-agent] npm run bundle 失败');
  process.exit(1);
}

// 2) 产物以 agent-bridge.mjs 之名放入 src-tauri/agent/（运行时 fx_agent_root 按此名查找）
rmSync(dst, { recursive: true, force: true });
mkdirSync(dst, { recursive: true });
copyFileSync(join(src, 'agent-bridge.bundle.mjs'), join(dst, 'agent-bridge.mjs'));
console.log('[sync-agent] agent-bridge.bundle.mjs -> src-tauri/agent/agent-bridge.mjs');
