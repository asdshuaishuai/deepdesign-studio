#!/usr/bin/env bash
# deepDesign 鸿蒙 AGC 上架前自检：对照《软件包解析错误码》文档逐条检查
# （https://developer.huawei.com/consumer/cn/doc/doccenter-operations/agc-help-package-errorcode-0000002312513009）
# 用法：./agc-precheck.sh [signed.app]   （默认 outputs/latest deepdesign-0.4.0.app）
# 覆盖错误码 → 检查项映射见 agc-precheck.py 头注；不适用项（元服务专属/Android 关联/
# 共享库/TA/In-house）标注 N/A 并给理由。
set -e
source "$HOME/.local/opt/tauri-env.sh"
export PATH="$HOME/deveco-clt/sdk/default/openharmony/toolchains:$PATH"
LIB="$HOME/deveco-clt/sdk/default/openharmony/toolchains/lib"
PROJ="$HOME/code/deepdesign-studio/ohos"
OUT="$PROJ/entry/build/default/outputs/default"
APP="${1:-$OUT/deepdesign-0.4.0.app}"
[ -f "$APP" ] || { echo "✗ 包不存在：$APP"; exit 1; }
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EXPECTED_BUNDLE="com.deepcode.deepdesign"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp "$APP" "$WORK/pkg.app"

cd "$WORK"
echo "== 签名校验（991 非法软件包 / 1014 HAP 未签名 / 999 Profile 类型 / 1001 证书匹配）=="
"$JAVA_HOME/bin/java" -jar "$LIB/hap-sign-tool.jar" verify-app -inFile ./pkg.app -inForm zip \
  -outCertChain ./chain.cer -outProfile ./profile.p7b > verify.log 2>&1
grep -iE "Signing Block|Digest verify|ERROR" verify.log | head -3

echo
echo "== 逐条错误码检查（python）=="
python3 "$SCRIPT_DIR/agc-precheck.py" ./pkg.app ./chain.cer ./profile.p7b "$EXPECTED_BUNDLE"