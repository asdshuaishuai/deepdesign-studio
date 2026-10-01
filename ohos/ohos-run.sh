#!/usr/bin/env bash
# deepDesign 鸿蒙模拟器一键启动 + 装机脚本
# 用法：
#   ./ohos-run.sh          启动模拟器（前台窗口，Ctrl+C 不杀模拟器）
#   ./ohos-run.sh --install  模拟器已运行时：构建 HAP 并安装启动 deepDesign 壳
set -e
source "$HOME/.local/opt/tauri-env.sh"    # DEVECO_CLI_CLT_PATH / OHOS_NDK_HOME / JAVA_HOME / PATH
# Emulator 自带 Qt/qemu 库解析（devecocli spawn 环境缺 libatomic 时兜底）
export LD_LIBRARY_PATH="$HOME/deveco-clt/emulator/lib:$HOME/.local/opt/tauri-deps/usr/lib/x86_64-linux-gnu:$HOME/.local/opt/tauri-deps/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
PROJ="$HOME/code/deepdesign-studio/ohos"
HAP_SRC="$PROJ/entry/build/default/outputs/default/entry-default-unsigned.hap"

case "${1:-}" in
  --install)
    echo "→ 同步最新前端到 rawfile ..."
    FE="$HOME/code/deepdesign-studio/frontend"
    RF="$PROJ/entry/src/main/resources/rawfile"
    mkdir -p "$RF/vendor"
    cp "$FE/index.html" "$RF/index.html"
    cp "$FE"/vendor/moonviz.wasm "$FE"/vendor/components.json "$FE"/vendor/engine-manifest.json "$RF/vendor/ 2>/dev/null" 2>/dev/null || true
    cp "$FE"/vendor/*.json "$RF/vendor/" 2>/dev/null || true
    echo "→ 构建 HAP（hvigor，ArkTS）..."
    (cd "$PROJ" && devecocli build)
    echo "→ 安装并启动 ..."
    devecocli run --project-path "$PROJ" || {
      SER="$(devecocli device list | grep -oE '127\.0\.0\.1:[0-9]+' | head -1)"
      [ -n "$SER" ] && hdc -t "$SER" install -r "$HAP_SRC" \
        && hdc -t "$SER" shell aa start -a EntryAbility -b com.deepcode.deepdesign
    }
    echo "✓ deepDesign 壳已启动（ArkWeb 加载 rawfile/index.html）"
    ;;
  *)
    echo "→ 启动模拟器 DeepDesignPhone（协议已置 agree）..."
    exec devecocli emulator start DeepDesignPhone
    ;;
esac
