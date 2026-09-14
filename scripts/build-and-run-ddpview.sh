#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/../moonviz"
PORT="${MOONVIZ_PORT:-8902}"

command -v moon >/dev/null 2>&1 || {
  echo "moon command not found; install the MoonBit toolchain first" >&2
  exit 1
}
command -v cargo >/dev/null 2>&1 || {
  echo "cargo command not found; install Rust first" >&2
  exit 1
}

printf '%s\n' '[1/2] Checking MoonViz engine'
(cd "$ENGINE" && moon check --target native)
printf '%s\n' '[2/2] Building codec and starting read-only ddpView'
cd "$ROOT"
exec env MOONVIZ_PORT="$PORT" MOONVIZ_DDP_HELPER="$ENGINE/ddp/target/debug/ddp_codec" python3 ddpView.py
