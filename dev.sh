#!/usr/bin/env bash
# deepDesign Studio — debug 模式编译启动（非 release）
# 用法：./dev.sh [--fresh]
#   默认：tauri dev（debug 编译 + 启动原生客户端）
#   --fresh：先 kill 旧进程 + 清 WebView 缓存，确保加载最新前端
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"

# Windows：tauri/webview2 与 wasmtime(ittapi) 的静态库只有 MSVC 形态，
# 默认 GNU 工具链会在链接期失败——自动定向（仅本进程，不改全局默认）
if command -v rustup >/dev/null 2>&1; then
  ACTIVE="$(rustup show active-toolchain 2>/dev/null || true)"
  case "$ACTIVE" in
    *gnu*)
      export RUSTUP_TOOLCHAIN=stable-x86_64-pc-windows-msvc
      echo "→ 检测到 GNU 工具链，本次使用 MSVC（$RUSTUP_TOOLCHAIN）"
      ;;
  esac
fi

# 引擎为预编译 wasm 产物（frontend/vendor/moonviz.wasm）：
# 缺失时现场拉取（GitHub Releases 直链 classic wasm，sha512 锚定 + 真机契约探针；
# 需 node——classic 产物无 WasmGC 门槛。注意 --fresh 的缓存清理路径仅 macOS，
# Windows 的 WKWebView 缓存在 %LOCALAPPDATA%，Git Bash 下清不掉、用 ?v= 时间戳重载兜底）
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
