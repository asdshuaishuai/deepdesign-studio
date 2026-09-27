#!/usr/bin/env bash
# deepDesign Studio 唯一安装器：本机任何时刻只允许存在一份应用。
# 流程：停实例 → 卸 DMG 残挂 → 注销全部 LaunchServices 注册 → 删旧包 → 装新包
#       → 重签 → 注册 → 剪掉 dev bundle 副本 → 验证「恰好一份」。
# 用法：
#   scripts/install-app.sh                # 用 target/release 的最新 bundle 安装
#   scripts/install-app.sh <bundle.app>   # 指定 bundle 路径（如 DMG 解出的副本）
#   scripts/install-app.sh --uninstall    # 彻底卸载（含数据目录可选 --purge）
set -euo pipefail

APP_NAME="deepDesign Studio.app"
DEST="/Applications/$APP_NAME"
BUNDLE="${2:-}"
MODE="${1:-install}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_BUNDLE="$ROOT/src-tauri/target/release/bundle/macos/$APP_NAME"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

say(){ printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[install:FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

# 0) 停掉在跑实例（任何路径来源）
if pgrep -f "deepdesign-studio" >/dev/null 2>&1; then
  say "停止运行中的实例…"
  pkill -f "deepdesign-studio" || true
  sleep 1.5
fi

# 1) 卸掉残留 DMG 挂载卷（历史幽灵注册的主要来源；卷名可能是 dmg.* 或产品名）
for vol in /Volumes/dmg.* "/Volumes/deepDesign Studio"; do
  [ -d "$vol" ] || continue
  say "弹出残留挂载 $vol"
  diskutil unmount "$vol" >/dev/null 2>&1 || hdiutil detach "$vol" -quiet >/dev/null 2>&1 || true
done

# 2) 注销 LaunchServices 里本应用的**全部**注册（/Applications、target bundle、DMG 卷…）
say "清点并注销全部 LaunchServices 注册…"
if [ -x "$LSREG" ]; then
  # shellcheck disable=SC2013
  "$LSREG" -dump 2>/dev/null | grep -i "path:" | grep -i "deepdesign" \
    | sed 's/^ *path: *//; s/ (0x[0-9a-f]*)$//' | sort -u | while IFS= read -r p; do
      say "  注销: $p"
      "$LSREG" -u "$p" >/dev/null 2>&1 || true
    done
fi

# 2.5) 解析并暂存来源 bundle（必须在清理之前：来源可能就是 target 里的 dev bundle，先删后取会自毁）
SRC="${BUNDLE:-$DEFAULT_BUNDLE}"
[ "$MODE" = "--uninstall" ] || {
  [ -e "$SRC" ] || die "找不到 bundle：${SRC}（先跑 npx @tauri-apps/cli build）"
  STAGE="$(mktemp -d)/stage.app"
  say "暂存来源 bundle…"
  cp -R "$SRC" "$STAGE"
}

# 3) 删旧包（/Applications 与仓库内 dev bundle 一起清——dev bundle 被 Finder 打开过就会再注册）
for old in "$DEST" \
  "$ROOT/src-tauri/target/release/bundle/macos/$APP_NAME" \
  "$ROOT/src-tauri/target/debug/bundle/macos/$APP_NAME"; do
  if [ -e "$old" ]; then say "删除旧副本: $old"; rm -rf "$old"; fi
done

if [ "$MODE" = "--uninstall" ]; then
  if [ "${3:-}" = "--purge" ]; then
    say "清除用户数据目录（最近项目/端点配置将丢失）…"
    rm -rf ~/Library/WebKit/com.deepcode.deepdesign ~/Library/WebKit/deepdesign-studio \
           ~/Library/Caches/com.deepcode.deepdesign 2>/dev/null || true
  fi
  say "已彻底卸载。"
  exit 0
fi

# 4) 装新包（来源已在清理前暂存，见上）
say "安装 → $DEST"
cp -R "$STAGE" "$DEST"

# 5) 重签（ad-hoc）+ 注册唯一副本
codesign --force --deep -s - "$DEST" >/dev/null 2>&1 || die "codesign 失败"
[ -x "$LSREG" ] && "$LSREG" -f "$DEST" >/dev/null 2>&1 || true

# 6) 剪掉来源 bundle（防止之后被误 open 再注册）
case "$SRC" in
  "$ROOT"/*) : ;;                                # 仓库内 target 产物：保留也无妨？不——删除防误开
esac
if [[ "$SRC" == "$ROOT"* ]]; then rm -rf "$SRC"; say "已移除来源 dev bundle（防误开重复注册）"; fi
rm -rf "$(dirname "$STAGE")"

# 7) 验证：磁盘与注册表各自恰好一份
sleep 1
# 只统计路径真实存在的注册：卸载后的 DMG 卷会留下系统异步回收的卷级幽灵条目
# （lsregister -u 清不掉、Finder eject 也清不掉），它不可达、不构成可启动的第二副本
COUNT_LS=0
if [ -x "$LSREG" ]; then
  COUNT_LS=$("$LSREG" -dump 2>/dev/null | grep -i "path:" | grep -i "deepdesign" \
    | sed 's/^ *path: *//; s/ (0x[0-9a-f]*)$//' | sort -u \
    | while IFS= read -r rp; do [ -e "$rp" ] && echo "$rp"; done | wc -l | tr -d ' ')
fi
COUNT_DISK=$(ls -d /Applications/*deep* 2>/dev/null | wc -l | tr -d ' ')
say "验证：磁盘副本=$COUNT_DISK  LaunchServices 注册=$COUNT_LS"
[ "$COUNT_DISK" = "1" ] || die "磁盘副本数 ≠ 1（=${COUNT_DISK}）"
[ "$COUNT_LS" -le "1" ] || die "注册数 > 1（=${COUNT_LS}）——存在重复注册"

# 8) 启动
say "启动应用…"
open -a "$DEST"
say "完成：唯一副本已安装并运行。"
