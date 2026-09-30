#!/usr/bin/env bash
# CI (ubuntu-24.04) 上安装 linyaps 工具链：ll-cli / ll-box / ll-builder
# 策略：动态依赖用 Ubuntu 自带源；linglong 本体用 deepin crimson 的 deb 解压
# 到 /usr/local + helper 落到 /usr/libexec（ll-builder 硬编码路径）。
set -e

echo "[ci-linyaps] installing runtime deps from ubuntu archive ..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
  libostree-1-1 libqt6core6t64 libqt6dbus6t64 libqt6network6t64 libqt6xml6t64 \
  libyaml-cpp0.8 libgpgme11t64 libavahi-glib1 libb2-1 libdouble-conversion3 \
  libfuse3-3 erofs-utils fuse-overlayfs || true

echo "[ci-linyaps] fetching linglong debs from deepin crimson ..."
WORK="$(mktemp -d)"
BASE="https://ci.deepin.com/repo/deepin/deepin-community/stable/pool/main/l"
cd "$WORK"
sudo mkdir -p /usr/local/linglong /usr/libexec/linglong
ok=0
for f in \
  "linglong/linglong-bin_1.14.3-1_amd64.deb" \
  "linglong-box/linglong-box_2.3.4-1_amd64.deb" \
  "linglong/linglong-builder_1.14.3-1_amd64.deb" \
  "y/yaml-cpp/libyaml-cpp0.7_0.7.0+dfsg-8deepin0_amd64.deb"; do
  curl -4 -fsSL --retry 3 -o pkg.deb "$BASE/$f" || { echo "  !! fetch failed: $f"; continue; }
  sudo dpkg -x pkg.deb /usr/local/linglong
  ok=$((ok+1))
done
[ "$ok" -ge 2 ] || { echo "[ci-linyaps] not enough debs landed"; exit 1; }

# ll-builder 硬编码 helper 路径
sudo cp -a /usr/local/linglong/usr/libexec/linglong/. /usr/libexec/linglong/ 2>/dev/null || true
sudo mkdir -p /usr/local/bin
for b in ll-cli ll-box ll-builder; do
  [ -f "/usr/local/linglong/usr/bin/$b" ] && sudo ln -sf "/usr/local/linglong/usr/bin/$b" "/usr/local/bin/$b"
done

# 动态库：优先 Ubuntu 自带；deepin deb 里多出的库解压副本放 /usr/local/lib
if [ -d /usr/local/linglong/usr/lib/x86_64-linux-gnu ]; then
  sudo mkdir -p /usr/local/lib
  sudo cp -an /usr/local/linglong/usr/lib/x86_64-linux-gnu/*.so.* /usr/local/lib/ 2>/dev/null || true
  sudo ldconfig
fi

echo "[ci-linyaps] verifying ..."
ll-builder --version
echo "[ci-linyaps] ok"
