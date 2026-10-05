#!/usr/bin/env bash
# deepDesign 鸿蒙模拟器一键启动 + 装机脚本
# 用法：
#   ./ohos-run.sh              启动模拟器（前台窗口，Ctrl+C 不杀模拟器）
#   ./ohos-run.sh --install    构建签名 HAP 并安装启动 deepDesign 壳
#
# 签名说明：使用 SDK 自带的 OpenHarmony 调试密钥（OpenHarmony.p12）本地签发，
# 无需华为开发者账号。签名材料在 /tmp/ohsign/（首次运行自动生成）。
set -e
source "$HOME/.local/opt/tauri-env.sh"    # DEVECO_CLI_CLT_PATH / OHOS_NDK_HOME / JAVA_HOME / PATH
# Emulator 自带 Qt/qemu 库解析（devecocli spawn 环境缺 libatomic 时兜底）
export LD_LIBRARY_PATH="$HOME/deveco-clt/emulator/lib:$HOME/.local/opt/tauri-deps/usr/lib/x86_64-linux-gnu:$HOME/.local/opt/tauri-deps/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$HOME/deveco-clt/sdk/default/openharmony/toolchains:$PATH"   # hdc
PROJ="$HOME/code/deepdesign-studio/ohos"
OUT="$PROJ/entry/build/default/outputs/default"
HAP_SRC="$OUT/entry-default-unsigned.hap"
HAP_SIGNED="$OUT/entry-default-signed.hap"
SIGN_DIR=/tmp/ohsign
LIB="$HOME/deveco-clt/sdk/default/openharmony/toolchains/lib"

prepare_signing() {
  [ -f "$SIGN_DIR/debug-profile.p7b" ] && return 0
  mkdir -p "$SIGN_DIR"
  local UDID
  UDID="$(hdc -t 127.0.0.1:5555 shell 'param get const.product.udid' 2>/dev/null | tr -d '\r\n ' || true)"
  python3 - "$SIGN_DIR" "$UDID" <<'EOF'
import json, sys, os
sign_dir, udid = sys.argv[1], sys.argv[2]
tpl = json.load(open(os.path.expanduser('~') + '/deveco-clt/sdk/default/openharmony/toolchains/lib/UnsgnedDebugProfileTemplate.json'))
open(f'{sign_dir}/app-release.cer', 'w').write(tpl['bundle-info']['development-certificate'])
tpl['bundle-info']['bundle-name'] = 'com.deepcode.deepdesign'
tpl['validity']['not-before'] = 1610519532
tpl['validity']['not-after'] = 2524600800   # 2050-01-01
tpl['debug-info']['device-ids'] = [udid] if udid else []
json.dump(tpl, open(f'{sign_dir}/debug-profile.json', 'w'), indent=2)
EOF
  "$JAVA_HOME/bin/keytool" -exportcert -rfc -alias cacert -keystore "$LIB/OpenHarmony.p12" -storepass 123456 -file "$SIGN_DIR/ca.cer" >/dev/null 2>&1
  "$JAVA_HOME/bin/keytool" -exportcert -rfc -alias rootcacert -keystore "$LIB/OpenHarmony.p12" -storepass 123456 -file "$SIGN_DIR/root.cer" >/dev/null 2>&1
  cat "$SIGN_DIR/app-release.cer" "$SIGN_DIR/ca.cer" "$SIGN_DIR/root.cer" > "$SIGN_DIR/app-release-chain.cer"
  "$JAVA_HOME/bin/java" -jar "$LIB/hap-sign-tool.jar" sign-profile \
    -keyAlias "openharmony application profile debug" -signAlg "SHA256withECDSA" -mode localSign \
    -profileCertFile "$LIB/OpenHarmonyProfileDebug.pem" -inFile "$SIGN_DIR/debug-profile.json" \
    -keystoreFile "$LIB/OpenHarmony.p12" -outFile "$SIGN_DIR/debug-profile.p7b" \
    -keyPwd 123456 -keystorePwd 123456 >/dev/null 2>&1
  echo "✓ 签名材料就绪（$SIGN_DIR）"
}

sign_hap() {
  "$JAVA_HOME/bin/java" -jar "$LIB/hap-sign-tool.jar" sign-app \
    -keyAlias "openharmony application release" -signAlg "SHA256withECDSA" -mode localSign \
    -appCertFile "$SIGN_DIR/app-release-chain.cer" -profileFile "$SIGN_DIR/debug-profile.p7b" \
    -inFile "$HAP_SRC" -keystoreFile "$LIB/OpenHarmony.p12" -outFile "$HAP_SIGNED" \
    -keyPwd 123456 -keystorePwd 123456 2>&1 | grep -E 'sign-app success' || { echo "✗ 签名失败"; exit 1; }
}

case "${1:-}" in
  --install)
    prepare_signing
    echo "→ rust-core 引擎交叉编译（双目标）+ 替换 rust-libs（gap-global-3：防 .so 陈旧）..."
    (cd "$HOME/code/deepdesign-studio/rust-core" && PATH="$HOME/.cargo/bin:$PATH" \
      cargo build --release --target x86_64-unknown-linux-ohos --target aarch64-unknown-linux-ohos) || {
      echo "✗ rust-core 交叉编译失败"; exit 1; }
    cp "$HOME/code/deepdesign-studio/rust-core/target/x86_64-unknown-linux-ohos/release/libdeepdesign_core.so" \
       "$PROJ/entry/src/main/cpp/rust-libs/x86_64/libdeepdesign_core.so"
    cp "$HOME/code/deepdesign-studio/rust-core/target/aarch64-unknown-linux-ohos/release/libdeepdesign_core.so" \
       "$PROJ/entry/src/main/cpp/rust-libs/arm64-v8a/libdeepdesign_core.so"
    echo "→ 构建 HAP（hvigor，ArkTS + NAPI）..."
    (cd "$PROJ" && devecocli build)
    echo "→ 本地签名（SDK OpenHarmony 调试密钥，免华为账号）..."
    sign_hap
    echo "→ 安装并启动 ..."
    # R3（review-m37）：不 uninstall——签名材料确定性生成，install -r 即可增量升级；
    # uninstall 会抹掉沙箱用户数据与 batch-13 的 ddp-external.ddp 注入通道
    hdc -t 127.0.0.1:5555 install -r "$HAP_SIGNED" \
      && hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.deepcode.deepdesign
    echo "✓ deepDesign 已启动（ArkUI 原生壳 + Rust NAPI core）"
    ;;
  *)
    echo "→ 启动 PC 模拟器 DeepDesignPC (2in1)（协议已置 agree）..."
    exec devecocli emulator start DeepDesignPC
    ;;
esac
