# 版本号（单一事实源）

**当前版本：0.4.1**

## 铁律

**仓库根 `VERSION` 文件是版本号的唯一权威。** 任何地方要读版本号，都以它为准；
任何地方要改版本号，只改它，然后跑同步脚本落地到全部下游面。

```bash
# 改版本：编辑 VERSION 后执行
node scripts/sync-version.mjs

# 校验漂移（不写盘；CI 与 test_studio.cjs 都跑这个）
node scripts/sync-version.mjs --check
```

`--check` 有任何漂移即非零退出——漂移不可能静默溜进发布产物。

## 为什么要有它

版本号曾经散布在十几个文件里，每次发布靠人肉逐个 `sed`。2026-10 的 v0.4.1 实测踩到后果：
发布的鸿蒙包与 AppStream 元数据停在 `0.4.0`，而桌面「关于」面板显示 `0.4.1`——
同一个版本号在不同产物里对不上账，用户看到哪个取决于装的是哪个包。

同步脚本把「改版本」从 16 处手改收敛成 1 处，并且漏改会直接让测试变红。

## 下游面清单（脚本自动维护，共 16 处）

| 文件 | 面 | 说明 |
|---|---|---|
| `VERSION` | **权威源** | 只写一个语义化版本号，别无他物 |
| `src-tauri/tauri.conf.json` | 桌面打包 | **构建期事实源**：`build-packages.sh` 从它派生产物名 |
| `src-tauri/Cargo.toml` | 桌面 Rust 包 | 系统级「关于」面板读它 |
| `src-tauri/Cargo.lock` | 桌面锁 | `deepdesign-studio` 包条目 |
| `rust-core/Cargo.toml` | 鸿蒙 Rust core | |
| `rust-core/Cargo.lock` | 鸿蒙锁 | `deepdesign_core` 包条目 |
| `frontend/index.html` | 前端 `APP_VER` | 文件名 chip 与「关于」tab 展示 |
| `ohos/entry/src/main/resources/rawfile/index.html` | 鸿蒙前端镜像 | 与 `frontend/index.html` 同源的 rawfile 副本，只同步版本行 |
| `ohos/entry/src/main/ets/pages/Index.ets` | 鸿蒙 ArkTS 顶栏 | 版本 chip |
| `ohos/AppScope/app.json5` | 鸿蒙打包 | `versionName` + `versionCode` |
| `rust-core/ohpm-pkg/oh-package.json5` | 鸿蒙 ohpm 包 | |
| `rust-core/pkgtmp/package/oh-package.json5` | 鸿蒙 ohpm staging | |
| `ohos/entry/src/main/cpp/types/libdeepdesign_core/oh-package.json5` | 鸿蒙类型声明包 | |
| `README.md` | 仓库首页 | 「当前版本」文案 |
| `docs/menus.md` | 菜单文档 | 关于面板版本注释 |
| `scripts/packaging/com.deepcode.deepdesign.metainfo.xml` | Linux AppStream | `<release version date>`（日期取同步当天） |

## 两条派生链（不动，只做一致性保证）

- **桌面/Linux**：`tauri.conf.json` → `scripts/build-packages.sh`（deb / AppImage 产物名）；
  `.github/workflows/release-all.yml` 的产物名则取自 git tag（`v*`）。
- **鸿蒙**：`ohos/AppScope/app.json5` 的 `versionName` → `ohos/ohos-release.sh` 产物名。

这两条链各自从自己的文件派生，脚本只保证它们与 `VERSION` 永远一致。

## 鸿蒙 versionCode（AGC 强制递增）

`versionCode` 是整数面，不能在 AGC 上重复或回退，按 `minor*100 + patch` 派生：

| 版本 | versionCode |
|---|---|
| 0.4.0 | 400 |
| 0.4.1 | 401 |
| 0.4.2 | 402 |

跳大版本（`major ≥ 1`）时约定需人工复核——脚本会打印警告，不会静默按老公式算。

## 发布流程（与分支纪律配套）

见 `AGENTS.md`「分支纪律」与「发布完整性」两节。简版：

1. 在 `dev` 上开发，测试全绿（`node test_studio.cjs` 内含版本漂移检查）。
2. 编辑 `VERSION` → `node scripts/sync-version.mjs` → 提交。
3. `dev` 合并进 `main`（发布分支）。
4. 在 `main` 上打 tag `v<版本>`，推送——`release-all.yml` 自动构建
   Windows NSIS / macOS DMG / Linux deb+AppImage 并附到 GitHub Release。
5. 鸿蒙 `.app.zip` 走本机 `ohos/ohos-release.sh` 签名打包后 `gh release upload` 补传。
6. 在 `AGENTS.md`「当前版本」处写明本次发布的版本号与日期。
