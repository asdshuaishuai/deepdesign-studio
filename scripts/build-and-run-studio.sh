#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/../moonviz"
PORT="${MOONVIZ_PORT:-8903}"

command -v moon >/dev/null 2>&1 || {
  echo "moon command not found; install the MoonBit toolchain first" >&2
  exit 1
}
command -v cargo >/dev/null 2>&1 || {
  echo "cargo command not found; install Rust first" >&2
  exit 1
}

printf '%s\n' '[1/3] Checking MoonViz engine'
(cd "$ENGINE" && moon check --target native)
printf '%s\n' '[2/3] Building DDP codec'
(cargo build --manifest-path "$ENGINE/ddp/Cargo.toml" --bin ddp_codec)
printf '%s\n' '[3/3] Starting Studio browser mode'
cd "$ROOT"
exec env MOONVIZ_PORT="$PORT" MOONVIZ_DDP_HELPER="$ENGINE/ddp/target/debug/ddp_codec" python3 server.py
