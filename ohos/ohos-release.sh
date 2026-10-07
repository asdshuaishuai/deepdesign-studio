#!/usr/bin/env bash
# deepDesign 鸿蒙 AGC 上架打包脚本
# 用法：./ohos-release.sh   （构建 release HAP → 发布证书签名 → 打 .app 上架包）
#
# 前置（一次性）：
#   1. ~/ohos-signing/deepdesign/deepdesign-release.p12 + store-password.txt
#      —— 本机已生成（generate-keypair，ECC P-256，alias=deepdesign-release）
#   2. AGC 证书管理上传 deepdesign-release.csr 申请「发布证书」→ 下载 .cer
#      存为 ~/ohos-signing/deepdesign/deepdesign-release.cer
#   3. AGC 创建 APP ID（com.deepcode.deepdesign）→ 创建「发布 Profile」
#      （绑 APP ID + 发布证书）→ 下载 .p7b
#      存为 ~/ohos-signing/deepdesign/deepdesign-release.p7b
# 与 ohos-run.sh 的调试签名（/tmp/ohsign，SDK 调试密钥）有意分开：上架签名材料
# 是发布身份，留在仓库外、不进 git。
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

# 证书自检（AGC 991 实测防回归）：下载到 .cer 必须是【从本 CSR 签发的发布证书】
# （subject 含 O=deepcode），不是华为根证书（CN=Huawei CBG Root CA G2，证书管理页
# 另有根证书下载入口，点错文件 = 签名校验必然失败 = 991 非法软件包）
CERT_SUBJECT=$(openssl x509 -in "$CER" -noout -subject 2>/dev/null)
echo "$CERT_SUBJECT" | grep -q "O=deepcode" || {
  echo "✗ $CER 不是从本 CSR 签发的发布证书（subject: ${CERT_SUBJECT:-读取失败}）"
  echo "  请在 AGC 证书管理找到状态「已生效」的发布证书重新下载覆盖"
  exit 1
}

echo "→ rust-core 引擎交叉编译（双目标）+ 替换 rust-libs..."
(cd "$HOME/code/deepdesign-studio/rust-core" && PATH="$HOME/.cargo/bin:$PATH" \
  cargo build --release --target x86_64-unknown-linux-ohos --target aarch64-unknown-linux-ohos) || {
  echo "✗ rust-core 交叉编译失败"; exit 1; }
cp "$HOME/code/deepdesign-studio/rust-core/target/x86_64-unknown-linux-ohos/release/libdeepdesign_core.so" \
   "$PROJ/entry/src/main/cpp/rust-libs/x86_64/libdeepdesign_core.so"
cp "$HOME/code/deepdesign-studio/rust-core/target/aarch64-unknown-linux-ohos/release/libdeepdesign_core.so" \
   "$PROJ/entry/src/main/cpp/rust-libs/arm64-v8a/libdeepdesign_core.so"

echo "→ 构建 release HAP（未签名）..."
(cd "$PROJ" && devecocli build --build-mode release)
HAP_SRC="$OUT/entry-default-unsigned.hap"
HAP_SIGNED="$OUT/entry-default-release-signed.hap"
APP_OUT="$OUT/deepdesign-0.4.0.app"

echo "→ 发布证书签名..."
(cd "$OUT" && unzip -o -q "$HAP_SRC" pack.info)
"$JAVA_HOME/bin/java" -jar "$LIB/hap-sign-tool.jar" sign-app \
  -keyAlias "deepdesign-release" -signAlg "SHA256withECDSA" -mode localSign \
  -appCertFile "$CER" -profileFile "$P7B" \
  -inFile "$HAP_SRC" -keystoreFile "$KS" -outFile "$HAP_SIGNED" \
  -keyPwd "$STORE_PWD" -keystorePwd "$STORE_PWD" 2>&1 | grep -E 'sign-app success' || { echo "✗ 签名失败"; exit 1; }

echo "→ 打 .app 上架包..."
"$JAVA_HOME/bin/java" -jar "$LIB/app_packing_tool.jar" --mode app \
  --out-path "$APP_OUT" --force true \
  --hap-path "$HAP_SIGNED" --pack-info-path "$OUT/pack.info" >/dev/null

# 打包自检（991 实测防回归）：app_packing_tool 遇无效签名会静默剥签名块——.app 内
# HAP 必须与签名产物逐字节一致，且内嵌发布证书 subject（缺一即上架 991「未签名」）
python3 - "$APP_OUT" "$HAP_SIGNED" <<'PY'
import sys, zipfile, hashlib
app, signed = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(app)
inner_name = [i.filename for i in z.infolist() if i.filename.endswith('.hap')][0]
inner = z.read(inner_name)
on_disk = open(signed, 'rb').read()
assert inner == on_disk, f'.app 内 HAP 与签名产物不一致（{len(inner)} vs {len(on_disk)}）——打包工具剥了签名'
assert 'O=deepcode' in inner.decode('latin1'), '签名块内未找到发布证书 subject——证书/私钥不匹配'
print(f'✓ 打包自检通过：{inner_name} {len(inner)} bytes（含发布证书签名块）')
PY

echo "✓ 上架包就绪：$APP_OUT"
echo "  （AGC → 我的应用 → 版本管理 上传；上架材料另需：ICP 备案号/软著或承诺函/隐私政策 URL）"
