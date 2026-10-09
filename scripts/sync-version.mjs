#!/usr/bin/env node
// 版本号单一事实源同步：仓库根 VERSION 文件是唯一权威，本脚本把它写进所有下游面。
//
// 为什么需要它：版本号曾散布在 10+ 处（tauri.conf / Cargo.toml×2 / Cargo.lock×2 /
// APP_VER / README / menus.md / 鸿蒙 app.json5 / ohpm 包 / AppStream metainfo），
// 每次都靠人肉逐个 sed，漏一处就出现「关于面板显示 0.4.1、鸿蒙包里是 0.4.0」这种
// 对不上账的事故（2026-10-09 实测）。现在改版本 = 改 VERSION 一个文件，然后跑本脚本。
//
// 用法：
//   node scripts/sync-version.mjs          # 把 VERSION 的版本号写进全部下游面
//   node scripts/sync-version.mjs --check  # 只校验漂移（CI/测试用），不写盘
//
// tauri.conf.json 仍是构建期事实源（build-packages.sh / ohos-release.sh 从它派生产物名），
// 本脚本保证它与 VERSION 永远一致，不改变既有派生链。
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url))); // deepDesign/
const CHECK = process.argv.includes('--check');

const version = readFileSync(join(root, 'VERSION'), 'utf8').trim();
if (!/^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/.test(version)) {
  console.error(`[sync-version] VERSION 内容不是合法语义化版本：${JSON.stringify(version)}`);
  process.exit(1);
}

// 鸿蒙 versionCode 是整数面（AGC 强制递增），沿用既有约定 minor*100 + patch：
// 0.4.0 → 400、0.4.1 → 401。major 不参与（当前恒 0），跳大版本时需人工复核一次。
const [, major, minor, patch] = version.match(/^(\d+)\.(\d+)\.(\d+)/);
const versionCode = Number(minor) * 100 + Number(patch);
if (Number(major) !== 0) {
  console.warn(`[sync-version] ⚠ major=${major}≠0：versionCode 约定（minor*100+patch）需人工复核后再发布`);
}

/** 每个下游面的定位模式必须恰好三组：(前缀)(版本)(后缀)。
 * 读漂移 = 取第 2 组；写 = 前缀 + VERSION + 后缀。个别目标用 write 覆写后缀。 */
const TARGETS = [
  // 打包线事实源：build-packages.sh / ohos-release.sh 从这里派生产物名
  { file: 'src-tauri/tauri.conf.json', pattern: /^(\s*"version":\s*")([^"]*)(")/m },
  // 桌面 Rust 包版本（系统级关于面板读取面）
  { file: 'src-tauri/Cargo.toml', pattern: /^(version\s*=\s*")([^"]*)(")/m },
  // cargo 会按 Cargo.toml 重写自己的包条目；显式同步避免「改了没跑 cargo」的滞后。
  // 换行必须是 \r?\n：Windows 检出（CI 上 core.autocrlf=true）是 CRLF，
  // 写死 \n 会让模式在 windows-latest 上不命中（2026-10-09 首次实测即红）。
  { file: 'src-tauri/Cargo.lock', pattern: /(name = "deepdesign-studio"\r?\nversion = ")([^"]*)(")/ },
  // 鸿蒙 Rust core 包版本
  { file: 'rust-core/Cargo.toml', pattern: /^(version\s*=\s*")([^"]*)(")/m },
  { file: 'rust-core/Cargo.lock', pattern: /(name = "deepdesign_core"\r?\nversion = ")([^"]*)(")/ },
  // 前端顶部常量：file-label 与「关于」tab 的版本展示
  { file: 'frontend/index.html', pattern: /(const APP_VER=')([^']*)(')/ },
  // 鸿蒙 rawfile 前端镜像（与 frontend/index.html 同源，动手改前先看它的 README）
  { file: 'ohos/entry/src/main/resources/rawfile/index.html', pattern: /(const APP_VER=')([^']*)(')/ },
  // 鸿蒙 ArkTS 顶栏版本 chip
  { file: 'ohos/entry/src/main/ets/pages/Index.ets', pattern: /(^\s*'v)([0-9][^']*)(')/m },
  // 鸿蒙打包版本面：versionName 随版本走，versionCode 按 minor*100+patch 派生（AGC 要求递增强制）
  { file: 'ohos/AppScope/app.json5', pattern: /^(\s*"versionName":\s*")([^"]*)(")/m },
  {
    file: 'ohos/AppScope/app.json5',
    label: 'versionCode',
    pattern: /^(\s*"versionCode":\s*)(\d+)(,?)/m,
    value: String(versionCode),
    write: (m) => m[1] + versionCode + m[3],
  },
  // 鸿蒙 ohpm 包版本（三处 staging 副本同源）
  { file: 'rust-core/ohpm-pkg/oh-package.json5', pattern: /^(\s*"version":\s*")([^"]*)(")/m },
  { file: 'rust-core/pkgtmp/package/oh-package.json5', pattern: /^(\s*"version":\s*")([^"]*)(")/m },
  { file: 'ohos/entry/src/main/cpp/types/libdeepdesign_core/oh-package.json5', pattern: /^(\s*"version":\s*")([^"]*)(")/m },
  // 仓库首页的「当前版本」文案
  { file: 'README.md', pattern: /(\*\*当前版本 v)([^*]*)(\*\*)/ },
  // 菜单文档的版本注释（关于面板动态读值，注释仅作现状快照）
  { file: 'docs/menus.md', pattern: /(版本动态读自 tauri\.conf\.json，当前 )([0-9][^）]*)(）)/ },
  // AppStream 元数据：发布记录随版本走，日期取同步当天
  {
    file: 'scripts/packaging/com.deepcode.deepdesign.metainfo.xml',
    pattern: /(<release version=")([^"]*)(" date=")([^"]*)(")/,
    write: (m) => m[1] + version + m[3] + new Date().toISOString().slice(0, 10) + m[5],
    read: (m) => m[2],
  },
];

const drifts = [];
const applied = [];

for (const t of TARGETS) {
  const path = join(root, t.file);
  const before = readFileSync(path, 'utf8');
  const m = before.match(t.pattern);
  if (!m) {
    console.error(
      `[sync-version] ${t.file}：定位模式未命中——结构变了或文件被改坏。请更新 TARGETS 里的 pattern，不要静默跳过`
    );
    process.exit(1);
  }
  const expected = t.value !== undefined ? t.value : version;
  const current = m[2];
  if (current === expected) continue;

  if (CHECK) {
    drifts.push(`${t.file}${t.label ? ' (' + t.label + ')' : ''}: ${current} → ${expected}`);
    continue;
  }
  const after = before.replace(t.pattern, (...args) => (t.write ? t.write(args) : args[1] + version + args[3]));
  writeFileSync(path, after);
  applied.push(t.file);
}

if (CHECK) {
  if (drifts.length) {
    console.error(
      `[sync-version] VERSION=${version}，以下下游面漂移（跑 node scripts/sync-version.mjs 修正）：\n` +
        drifts.map((d) => `  - ${d}`).join('\n')
    );
    process.exit(1);
  }
  console.log(`[sync-version] ✓ ${TARGETS.length} 个下游面与 VERSION=${version} 一致`);
} else if (applied.length) {
  console.log(
    `[sync-version] VERSION=${version} → 已更新 ${applied.length}/${TARGETS.length} 个下游面：\n` +
      applied.map((f) => `  ${f}`).join('\n')
  );
} else {
  console.log(`[sync-version] VERSION=${version}，${TARGETS.length} 个下游面已一致（无改动）`);
}
