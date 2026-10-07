#!/bin/bash
# deepDesign Studio 启动脚本（deb / AppImage / 玲珑通用）
# 相对自身解析安装前缀；装配随包 WebKitGTK 运行库 + exec 路径重定向 shim
set -e
SELF="$(readlink -f "$0")"
PREFIX="$(dirname "$(dirname "$SELF")")"          # .../files
# 库目录自适应：deb/AppImage 布局 lib/deepdesign/，玲珑布局 lib/
if [ -d "$PREFIX/lib/deepdesign" ]; then LIB="$PREFIX/lib/deepdesign"; else LIB="$PREFIX/lib"; fi

export LD_LIBRARY_PATH="$LIB:/runtime/lib/x86_64-linux-gnu:/runtime/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# WebKit 硬编码 /usr helper 路径重定向到随包目录（TAURI_DEPS 指映射前缀）
export TAURI_DEPS="$LIB/webkit-helpers"
export LD_PRELOAD="$LIB/redirect.so${LD_PRELOAD:+:$LD_PRELOAD}"
export WEBKIT_INJECTED_BUNDLE_PATH="$LIB/webkit-helpers/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1/injected-bundle"
export APPDIR="$PREFIX"

exec "$PREFIX/bin/deepdesign-studio" "$@"
