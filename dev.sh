#!/usr/bin/env bash
# deepDesign Studio — debug 模式编译启动（非 release）
# 用法：./dev.sh [--web]
#   默认：tauri dev（debug 编译 + 启动原生客户端 + 热重载）
#   --web：免编译网页模式（server.py）
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
export MOONVIZ_DIR="${MOONVIZ_DIR:-$(cd "$ROOT/../moonviz" 2>/dev/null && pwd)}"
export MOONVIZ_DDP_HELPER="${MOONVIZ_DDP_HELPER:-$MOONVIZ_DIR/ddp/target/release/ddp_codec}"

if [ ! -d "$MOONVIZ_DIR/cli" ]; then
  echo "✗ 找不到引擎目录（需要含 cli/）：设置 MOONVIZ_DIR" >&2
  exit 1
fi

# tauri CLI 探测：本地 tauri → npx
TAURI_BIN="$(command -v tauri || true)"
if [ -z "$TAURI_BIN" ]; then
  if [ -x "$ROOT/node_modules/.bin/tauri" ]; then
    TAURI_BIN="$ROOT/node_modules/.bin/tauri"
  else
    echo "→ 未找到 tauri CLI，改用 npx @tauri-apps/cli（首次会拉包）"
    TAURI_BIN="npx"
    cd "$ROOT" && exec npx @tauri-apps/cli dev
  fi
fi

if [ "${1:-}" = "--web" ]; then
  echo "→ 网页模式（debug 数据流同源，免 Rust 编译）"
  exec python3 "$ROOT/server.py"
fi

echo "→ debug 模式编译并启动 deepDesign Studio（引擎：$MOONVIZ_DIR）"
cd "$ROOT" && exec "$TAURI_BIN" dev
