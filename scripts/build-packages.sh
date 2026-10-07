#!/usr/bin/env bash
# deepDesign Studio —— Linux 打包脚本
# 产物：
#   deb       标准 FHS 布局（/usr/bin + /usr/lib/deepdesign-studio，自带 WebKit 运行库，
#             不依赖系统 webkit；任何 glibc >= 2.38 的 Debian 系可安装）
#   AppImage  免安装单文件（自带全部运行库，通用 Linux）
# 用法：
#   scripts/build-packages.sh [--rebuild] [--deb] [--appimage] [--all]
#   默认 --all。（玲珑/linyaps 支持已移除——用户决策 2026-10-07，历史见 git log）
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# 打包线版本取自 src-tauri/tauri.conf.json（版本单一事实源，当前 0.4.1）。
# 注意 dpkg 语义：曾以 0.4.0-beta 存量的机器上，裸 0.4.1 > 0.4.0-beta ✓ 平滑升级。
VERSION="$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$ROOT/src-tauri/tauri.conf.json" | head -1)"
[ -n "$VERSION" ] || die "cannot read version from src-tauri/tauri.conf.json"
ID="com.deepcode.deepdesign"
PKGNAME="deepdesign-studio"
APPNAME="deepDesign-Studio-${VERSION}-x86_64"
DIST="$ROOT/dist"
STAGE="$(mktemp -d)/stage"
PKGDIR="$ROOT/scripts/packaging"

WANT_DEB=0; WANT_APPIMAGE=0; REBUILD=0
[ $# -eq 0 ] && set -- --all
for arg in "$@"; do
  case "$arg" in
    --rebuild) REBUILD=1 ;;
    --deb) WANT_DEB=1 ;;
    --appimage) WANT_APPIMAGE=1 ;;
    --all) WANT_DEB=1; WANT_APPIMAGE=1 ;;
    *) echo "unknown option: $arg"; exit 1 ;;
  esac
done

log() { printf '\033[1;36m[packages]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[packages]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 0. 前置：release 二进制 + wasm 引擎 ----------
cd "$ROOT"
if [ ! -x src-tauri/target/release/deepdesign-studio ] || [ "$REBUILD" = 1 ]; then
  log "building release binary (cargo build --release) ..."
  # 本地工具链环境（可选：PKG_CONFIG_PATH 等；真机系统安装时无需）
  [ -f "$HOME/.local/opt/tauri-env.sh" ] && source "$HOME/.local/opt/tauri-env.sh"
  (cd src-tauri && cargo build --release)
fi
[ -f frontend/vendor/moonviz.wasm ] || { log "syncing engine wasm ..."; node scripts/sync-engine.mjs; }

# ---------- 1. 组装产物 staging（deb/AppImage 共用同一份内容） ----------
# 自带 WebKitGTK 运行库（无系统 webkit 依赖）。来源：从 deepin 仓库现场收集
# （一次性 ~120MB，deb/AppImage 两种产物共用；无本地缓存目录）。
ensure_webkit_bundle() {
  local dest="$1"
  log "collecting bundled WebKitGTK runtime from deepin repo (one-time, ~120MB) ..."
  local repo="https://ci.deepin.com/repo/deepin/deepin-community/stable"
  local work="$STAGE/collect"
  mkdir -p "$work/root" "$dest/webkit-helpers/usr/lib/x86_64-linux-gnu" "$dest/webkit-helpers/usr/bin"
  curl -4 -sL -o "$work/Packages.gz" "$repo/dists/crimson/release/main/binary-amd64/Packages.gz"
  gzip -d -f "$work/Packages.gz"
  local pkgs=(
    libwebkit2gtk-4.1-0 libjavascriptcoregtk-4.1-0 libsoup-3.0-0
    libglib2.0-0 
    libdbus-1-3 zlib1g libx11-6 libxext6 libxrender1 libxcb1
    libatomic1 libavif15 libenchant-2-2 libflite1 libgstreamer-plugins-base1.0-0
    libgstreamer-plugins-bad1.0-0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good
    libhyphen0 libmanette-0.2-0 libsecret-1-0 libwoff1 libxslt1.1
    libevdev2 libgav1-0 libgstreamer-gl1.0-0 libgudev-1.0-0 libyuv0
    bubblewrap xdg-dbus-proxy 
  )
  local p file
  for p in "${pkgs[@]}"; do
    file=$(awk -v pkg="$p" 'BEGIN{RS=""} $0 ~ ("^Package: " pkg "\n") || $0 ~ ("^Package: " pkg "$") {
      if (match($0, /Filename: [^\n]+/)) print substr($0, RSTART+10, RLENGTH-10); exit }' "$work/Packages")
    [ -n "$file" ] || { log "  !! package not in repo: $p"; continue; }
    curl -4 -sL -o "$work/pkg.deb" "$repo/$file"
    dpkg-deb -x "$work/pkg.deb" "$work/root"
  done
  cp -a "$work/root/usr/lib/x86_64-linux-gnu/." "$dest/"
  rm -rf "$dest/pkgconfig"
  # helpers：webkit2gtk-4.1 目录（WebProcess/NetworkProcess/injected-bundle 等）真拷贝
  cp -a "$dest/webkit2gtk-4.1" "$dest/webkit-helpers/usr/lib/x86_64-linux-gnu/"
  cp "$work/root/usr/bin/bwrap" "$work/root/usr/bin/xdg-dbus-proxy" "$dest/webkit-helpers/usr/bin/" 2>/dev/null || true
  # 预编译优先（scripts/redirect.so）；无则现场编译（需 gcc）
  if [ -f "$ROOT/scripts/redirect.so" ]; then
    install -m644 "$ROOT/scripts/redirect.so" "$dest/redirect.so"
  else
    gcc -shared -fPIC -O2 -o "$dest/redirect.so" "$ROOT/scripts/redirect.c" -ldl
  fi
  log "  webkit runtime collected → $(du -sh "$dest" | cut -f1)"
}

STAGE_FILES="$STAGE/files"
mkdir -p "$STAGE_FILES/bin" \
         "$STAGE_FILES/share/$PKGNAME/frontend/vendor" \
         "$STAGE_FILES/lib/deepdesign" \
         "$STAGE_FILES/share/icons/hicolor/512x512/apps" \
         "$STAGE_FILES/share/metainfo"

# desktop 生成（按产物格式注入 Exec——991 时代教训：deb 复用玲珑模板的
# /opt/apps Exec 导致装完图标点不开；Exec 必须与真实安装前缀一致）
write_desktop() {
  local dest="$1" exec_path="$2"
  sed "s|@RUNTIME_EXEC@|$exec_path|" "$PKGDIR/com.deepcode.deepdesign.desktop" > \
    "$dest/com.deepcode.deepdesign.desktop"
}
install -m755 "$PKGDIR/run.sh" "$STAGE_FILES/bin/run.sh"
install -m755 src-tauri/target/release/deepdesign-studio "$STAGE_FILES/bin/deepdesign-studio"
cp frontend/index.html "$STAGE_FILES/share/$PKGNAME/frontend/"
cp frontend/vendor/* "$STAGE_FILES/share/$PKGNAME/frontend/vendor/"
ensure_webkit_bundle "$STAGE_FILES/lib/deepdesign"
install -m644 src-tauri/icons/icon.png "$STAGE_FILES/share/icons/hicolor/512x512/apps/com.deepcode.deepdesign.png"
install -m644 "$PKGDIR/com.deepcode.deepdesign.metainfo.xml" "$STAGE_FILES/share/metainfo/"

# ---------- 2. deb（标准 FHS 布局） ----------
build_deb() {
  local debroot="$STAGE/debroot/$PKGNAME_${VERSION}_amd64"
  rm -rf "$debroot"; mkdir -p "$debroot/DEBIAN"
  # /usr/lib/deepdesign-studio：全部内容
  mkdir -p "$debroot/usr/lib/$PKGNAME" "$debroot/usr/share" "$debroot/usr/bin"
  cp -a "$STAGE_FILES/." "$debroot/usr/lib/$PKGNAME/"
  # 入口：wrapper（即 run.sh 的相对路径解析）+ desktop/icon 标准位
  ln -sf /usr/lib/$PKGNAME/bin/run.sh "$debroot/usr/bin/$PKGNAME"
  cp -r "$debroot/usr/lib/$PKGNAME/share/icons" "$debroot/usr/share/"
  # desktop：Exec 必须指向 FHS 真实安装位（/usr/lib/...），勿复用玲珑 /opt/apps 模板
  mkdir -p "$debroot/usr/share/applications"
  write_desktop "$debroot/usr/share/applications" "/usr/lib/$PKGNAME/bin/run.sh"
  cat > "$debroot/DEBIAN/control" << CTRL
Package: $PKGNAME
Version: $VERSION
Section: devel
Priority: optional
Architecture: amd64
Installed-Size: 240000
Depends: libc6 (>= 2.38), libstdc++6, libgcc-s1
Suggests: gstreamer1.0-plugins-base, gstreamer1.0-plugins-good
Recommends: fuse3 | fusermount
Built-Using: bundled-webkit2gtk-4.1
Maintainer: asdshuaishuai <demo@demo>
Homepage: https://asdshuaishuai.github.io/deepdesign-studio/
Description: AI-native prototyping desktop studio (Tauri 2)
 deepDesign Studio is the desktop client of the AI-native prototyping tool,
 powered by the pure-MoonBit MoonViz engine. The .mbt.md document is the
 single source of truth; human canvas edits and Agent changes both pass
 engine validation before writing back.
 .
 WebKitGTK runtime libraries are bundled under /usr/lib/$PKGNAME/lib/deepdesign
 (no system webkit dependency required). Standard FHS layout, not distro-specific.
Package-List:
 $PKGNAME deb devel optional arch=amd64
CTRL
  cat > "$debroot/DEBIAN/postinst" << 'EOF'
#!/bin/sh
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -f /usr/share/icons/hicolor 2>/dev/null || true
exit 0
EOF
  chmod 755 "$debroot/DEBIAN/postinst"
  mkdir -p "$DIST"
  dpkg-deb --build --root-owner-group "$debroot" "$DIST/${PKGNAME}_${VERSION}_amd64.deb" > /dev/null
  log "deb        → dist/${PKGNAME}_${VERSION}_amd64.deb ($(du -h "$DIST/${PKGNAME}_${VERSION}_amd64.deb" | cut -f1))"
}

# ---------- 3. AppImage ----------
ensure_appimagetool() {
  if [ -n "$APPIMAGETOOL" ] && [ -x "$APPIMAGETOOL" ]; then APPIMAGETOOL_BIN="$APPIMAGETOOL"; return 0; fi
  local cache="${APPIMAGETOOL_CACHE:-$HOME/.cache/appimagetool}"
  APPIMAGETOOL_BIN="$cache/appimagetool-x86_64.AppImage"
  if [ ! -x "$APPIMAGETOOL_BIN" ]; then
    log "fetching appimagetool ..."
    mkdir -p "$cache"
    local base="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
    curl -4 -sL --retry 3 -o "$APPIMAGETOOL_BIN" "$base" \
      || curl -4 -sL --retry 3 -o "$APPIMAGETOOL_BIN" "https://gh-proxy.com/$base" \
      || die "cannot download appimagetool (set APPIMAGETOOL=<path> to override)"
    chmod +x "$APPIMAGETOOL_BIN"
  fi
  # 无 FUSE 的环境自动走 extract-and-run
  if "$APPIMAGETOOL_BIN" --version >/dev/null 2>&1; then
    AIT_RUN=()
  else
    AIT_RUN=(--appimage-extract-and-run)
  fi
}

build_appimage() {
  ensure_appimagetool
  local appdir="$STAGE/appdir"
  rm -rf "$appdir"; mkdir -p "$appdir/usr"
  # 内容放在 AppDir/opt/apps/<id>/files（AppRun 相对解析）
  mkdir -p "$appdir/opt/apps/$ID"
  cp -a "$STAGE_FILES" "$appdir/opt/apps/$ID/files"
  write_desktop "$appdir" "deepdesign-studio"
  install -m644 "$PKGDIR/com.deepcode.deepdesign.png" "$appdir/${ID}.png"
  cat > "$appdir/AppRun" << EOF
#!/bin/bash
SELF="\$(readlink -f "\$0")"
DIR="\$(dirname "\$SELF")"
exec "\$DIR/opt/apps/$ID/files/bin/run.sh" "\$@"
EOF
  chmod +x "$appdir/AppRun"
  mkdir -p "$DIST"
  (cd "$STAGE" && ARCH=x86_64 "$APPIMAGETOOL_BIN" "${AIT_RUN[@]}" appdir "$DIST/$APPNAME.AppImage") > /dev/null
  log "AppImage   → dist/$APPNAME.AppImage ($(du -h "$DIST/$APPNAME.AppImage" | cut -f1))"
}

# ---------- 执行 ----------
mkdir -p "$DIST"
[ "$WANT_DEB" = 1 ] && build_deb
[ "$WANT_APPIMAGE" = 1 ] && build_appimage
log "done. artifacts in dist/"
