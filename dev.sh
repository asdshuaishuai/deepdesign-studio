#!/usr/bin/env bash
# deepDesign Studio — debug 模式编译启动（非 release）
# 用法：./dev.sh [--fresh]
#   默认：tauri dev（debug 编译 + 启动原生客户端）
#   --fresh：先 kill 旧进程 + 清 WebView 缓存，确保加载最新前端
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"

# 引擎为预编译 wasm 产物（frontend/vendor/moonviz.wasm）：
# 缺失时现场拉取（npm moonviz-engine-wasm，sha512 校验 + 真机契约探针，需 node（classic wasm 无版本门槛））
if [ ! -f "$ROOT/frontend/vendor/moonviz.wasm" ]; then
  echo "→ 引擎 wasm 产物缺失，同步中（node scripts/sync-engine.mjs）…"
  (cd "$ROOT" && node scripts/sync-engine.mjs)
fi
echo "→ 引擎产物：frontend/vendor/moonviz.wasm（WebView 内进程执行）"

# --fresh 或检测到旧进程：清理
if [ "${1:-}" = "--fresh" ] || pgrep -f "deepDesign Studio" >/dev/null 2>&1 || pgrep -f "tauri dev" >/dev/null 2>&1; then
  echo "→ 清理旧进程与 WebView 缓存…"
  pkill -f "deepDesign Studio" 2>/dev/null || true
  pkill -f "tauri dev" >/dev/null 2>&1 || true
  sleep 0.5
  rm -rf "$HOME/Library/WebKit/com.deepcode.deepdesign" 2>/dev/null || true
  rm -rf "$HOME/Library/Caches/com.deepcode.deepdesign" 2>/dev/null || true
fi

# tauri CLI 探测：全局 tauri → npx
TAURI_BIN="$(command -v tauri || true)"
if [ -z "$TAURI_BIN" ]; then
  echo "→ 未找到 tauri CLI，改用 npx @tauri-apps/cli（首次会拉包）"
  cd "$ROOT" && exec npx @tauri-apps/cli dev
fi

echo "→ debug 模式编译并启动 deepDesign Studio"
echo "  提示：tauri dev 只 watch src-tauri/；改 frontend/ 后请在窗口按 ⌘R 刷新"
cd "$ROOT" && exec "$TAURI_BIN" dev
