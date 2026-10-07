#!/usr/bin/env bash
# deepDesign 鸿蒙 AGC 上架打包脚本
# 用法：./ohos-release.sh   （构建 release HAP → 打 .app → 对 .app 签名）
#
# 【流程顺序是硬约束（AGC 991 实测复盘）】app_packing_tool 打 .app 时会重建 HAP
# （注入 pack.info）并【剥掉 HAP 尾部签名块】——所以必须【先打包未签名 .app，再对
# .app 整体 sign-app】；「先签 HAP 再打包」会产出内层无签名包 = AGC 991「软件包
# 未签名」。签名材料（p12/cer/p7b）在 ~/ohos-signing/deepdesign/，仓库外不进 git：
#   deepdesign-release.p12 + store-password.txt —— 本机 generate-keypair（ECC P-256，
#                                                  alias=deepdesign-release）
#   deepdesign-release.cer —— AGC 证书管理下载的发布证书链（根→中间→叶子，叶子=
#                             CSR 对应的开发者发布证书）
#   deepdesign-release.p7b —— AGC 发布 Profile（绑 com.deepcode.deepdesign）
set -e
source "$HOME/.local/opt/tauri-env.sh"    # DEVECO_CLI_CLT_PATH / OHOS_NDK_HOME / JAVA_HOME / PATH
export LD_LIBRARY_PATH="$HOME/deveco-clt/emulator/lib:$HOME/.local/opt/tauri-deps/usr/lib/x86_64-linux-gnu:$HOME/.local/opt/tauri-deps/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$HOME/deveco-clt/sdk/default/openharmony/toolchains:$PATH"   # hdc
PROJ="$HOME/code/deepdesign-studio/ohos"
OUT="$PROJ/entry/build/default/outputs/default"
LIB="$HOME/deveco-clt/sdk/default/openharmony/toolchains/lib"
SIGN_DIR="$HOME/ohos-signing/deepdesign"
KS="$SIGN_DIR/deepdesign-release.p12"
CER="$SIGN_DIR/deepdesign-release.cer"
P7B="$SIGN_DIR/deepdesign-release.p7b"
STORE_PWD="$(cat "$SIGN_DIR/store-password.txt")"

for f in "$CER" "$P7B"; do
  [ -f "$f" ] || { echo "✗ 缺 $f —— 见脚本头注（AGC 上传 CSR 后下载，放入 $SIGN_DIR/）"; exit 1; }
done

# 证书链自检：≥3 张（根→中间→叶子）且叶子是发布证书（Developer Relations CA 签发、
# subject 带 Release）——防下载到孤立根证书或调试 Profile
CERTS=$(openssl crl2pkcs7 -nocrl -certfile "$CER" 2>/dev/null | openssl pkcs7 -print_certs -noout 2>/dev/null | grep -c "subject")
[ "$CERTS" -ge 3 ] || { echo "✗ $CER 证书链不完整（$CERTS 张，需 ≥3：根/中间/叶子）"; exit 1; }
openssl crl2pkcs7 -nocrl -certfile "$CER" 2>/dev/null | openssl pkcs7 -print_certs -noout 2>/dev/null | \
  grep -q "CN=Huawei CBG Developer Relations CA G2" || { echo "✗ $CER 无 Developer Relations CA 签发的证书——不是发布证书链"; exit 1; }

echo "→ rust-core 引擎交叉编译（双目标）+ 替换 rust-libs..."
(cd "$HOME/code/deepdesign-studio/rust-core" && PATH="$HOME/.cargo/bin:$PATH" \
  cargo build --release --target x86_64-unknown-linux-ohos --target aarch64-unknown-linux-ohos) || {
  echo "✗ rust-core 交叉编译失败"; exit 1; }
cp "$HOME/code/deepdesign-studio/rust-core/target/x86_64-unknown-linux-ohos/release/libdeepdesign_core.so" \
   "$PROJ/entry/src/main/cpp/rust-libs/x86_64/libdeepdesign_core.so"
cp "$HOME/code/deepdesign-studio/rust-core/target/aarch64-unknown-linux-ohos/release/libdeepdesign_core.so" \
   "$PROJ/entry/src/main/cpp/rust-libs/arm64-v8a/libdeepdesign_core.so"

echo "→ 构建 release HAP（未签名；.app 打包工具会剥 HAP 签名，签 .app 而非签 HAP）..."
(cd "$PROJ" && devecocli build --build-mode release)
HAP_SRC="$OUT/entry-default-unsigned.hap"
APP_UNSIGNED="$OUT/deepdesign-0.4.0-unsigned.app"
APP_SIGNED="$OUT/deepdesign-0.4.0.app"

echo "→ 打未签名 .app（工具注入 pack.info）..."
(cd "$OUT" && unzip -o -q "$HAP_SRC" pack.info)
"$JAVA_HOME/bin/java" -jar "$LIB/app_packing_tool.jar" --mode app \
  --out-path "$APP_UNSIGNED" --force true \
  --hap-path "$HAP_SRC" --pack-info-path "$OUT/pack.info" >/dev/null

echo "→ 对 .app 整体签名（发布证书链）..."
"$JAVA_HOME/bin/java" -jar "$LIB/hap-sign-tool.jar" sign-app \
  -keyAlias "deepdesign-release" -signAlg "SHA256withECDSA" -mode localSign \
  -appCertFile "$CER" -profileFile "$P7B" \
  -inFile "$APP_UNSIGNED" -keystoreFile "$KS" -outFile "$APP_SIGNED" \
  -keyPwd "$STORE_PWD" -keystorePwd "$STORE_PWD" 2>&1 | grep -E 'sign-app success' || { echo "✗ 签名失败"; exit 1; }

# 打包自检（991 实测防回归）：签名 .app ≥ 未签名 +5KB（签名块）；叶子证书字节在场；
# 包结构 = 内层 HAP + pack.info 两条目
python3 - "$APP_SIGNED" "$APP_UNSIGNED" "$CER" <<'PY'
import sys, zipfile, hashlib, re
signed_f, unsigned_f, cer_f = sys.argv[1], sys.argv[2], sys.argv[3]
signed, unsigned = open(signed_f, 'rb').read(), open(unsigned_f, 'rb').read()
assert len(signed) >= len(unsigned) + 5 * 1024, f'签名块缺失（{len(signed)} vs 未签名 {len(unsigned)}）'
cer = open(cer_f, 'rb').read()
leaf_der = re.findall(rb'-----BEGIN CERTIFICATE-----\r?\n(.*?)\r?\n-----END CERTIFICATE-----', cer, re.S)[-1]
import base64
leaf = base64.b64decode(b''.join(leaf_der.split()))
assert leaf in signed, '叶子证书（开发者发布证书）不在签名块内——签名绑错证书'
z = zipfile.ZipFile(signed_f)
names = [i.filename for i in z.infolist()]
hap = [n for n in names if n.endswith('.hap')][0]
assert sorted(names) == sorted([hap, 'pack.info']), f'.app 结构异常：{names}'
print(f'✓ 打包自检通过：{len(signed)} bytes，内层 {names[0]}（{z.getinfo(names[0]).file_size} bytes，'
      f'未签名由 .app 签名块整体覆盖），叶子证书在场')
PY

echo "✓ 上架包就绪：$APP_SIGNED"
echo "  （AGC → 我的应用 → 版本管理 上传；上架材料另需：ICP 备案号/软著或承诺函/隐私政策 URL）"