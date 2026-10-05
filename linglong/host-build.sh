#!/usr/bin/env bash
# deepDesign Studio 玲珑打包 —— 在正常 deepin 25 (crimson) 宿主机上执行
# 前置：系统已安装 linglong（ll-builder ≥1.14），网络可达官方仓库
# 用法：cd linglong && ./host-build.sh
set -e
cd "$(dirname "$0")"

# 1. 构建进容器（正常宿主上直接走通；本目录 package/ 内是预构建产物）
ll-builder build

# 2. 导出 .layer（可 ll-cli install 分发）
ll-builder export ../com.deepcode.deepdesign_0.4.0-beta_x86_64.layer
echo "产物: com.deepcode.deepdesign_0.4.0-beta_x86_64.layer"

# 3. （可选）导出 .uab 免安装分发包
# ll-builder export --uab ../com.deepcode.deepdesign_0.4.0-beta_x86_64.uab

# 4. 本地验证
# ll-builder run bash   # 进容器检查 /opt/apps/com.deepcode.deepdesign/files
# ll-cli install ../com.deepcode.deepdesign_0.4.0-beta_x86_64.layer
# ll-cli run com.deepcode.deepdesign
