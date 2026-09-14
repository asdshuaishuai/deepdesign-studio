#!/usr/bin/env bash
# deepDesign Studio — debug 模式编译启动（非 release）
# 用法：./dev.sh [--web] [--fresh]
#   默认：tauri dev（debug 编译 + 启动原生客户端）
#   --fresh：先 kill 旧进程 + 清 WebView 缓存，确保加载最新前端
#   --web  ：免编译网页模式（server.py）
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
export MOONVIZ_DIR="${MOONVIZ_DIR:-$(cd "$ROOT/../moonviz" 2>/dev/null && pwd)}"
export MOONVIZ_DDP_HELPER="${MOONVIZ_DDP_HELPER:-$MOONVIZ_DIR/ddp/target/release/ddp_codec}"

if [ ! -d "$MOONVIZ_DIR/cli" ]; then
  echo "✗ 找不到引擎目录（需要含 cli/）：设置 MOONVIZ_DIR" >&2
  exit 1
fi

if [ "${1:-}" = "--web" ]; then
  echo "→ 网页模式（免 Rust 编译，改前端刷新即生效）"
  exec python3 "$ROOT/server.py"
fi

# --fresh 或检测到旧进程：清理
if [ "${1:-}" = "--fresh" ] || pgrep -f "deepDesign Studio" >/dev/null 2>&1 || pgrep -f "tauri dev" >/dev/null 2>&1; then
  echo "→ 清理旧进程与 WebView 缓存…"
  pkill -f "deepDesign Studio" 2>/dev/null || true
  pkill -f "tauri dev" 2>/dev/null || true
  sleep 0.5
  rm -rf "$HOME/Library/WebKit/com.deepcode.deepdesign" 2>/dev/null || true
  rm -rf "$HOME/Library/Caches/com.deepcode.deepdesign" 2>/dev/null || true
fi

# tauri CLI 探测：全局 tauri → npx
TAURI_BIN="$(command -v tauri || true)"
if [ -z "$TAURI_BIN" ]; then
  if [ -x "$ROOT/node_modules/.bin/tauri" ]; then
    TAURI_BIN="$ROOT/node_modules/.bin/tauri"
  else
    echo "→ 未找到 tauri CLI，改用 npx @tauri-apps/cli（首次会拉包）"
    cd "$ROOT" && exec npx @tauri-apps/cli dev
  fi
fi

echo "→ debug 模式编译并启动 deepDesign Studio"
echo "  引擎：$MOONVIZ_DIR"
echo "  提示：tauri dev 只 watch src-tauri/；改 frontend/ 后请在窗口按 ⌘R 刷新"
cd "$ROOT" && exec "$TAURI_BIN" dev
