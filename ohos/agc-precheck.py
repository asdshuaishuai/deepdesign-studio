# AGC 软件包解析错误码逐条自检（ohos/agc-precheck.sh 调用）。
# 对照文档：developer.huawei.com/consumer/cn/doc/doccenter-operations/
#           agc-help-package-errorcode-0000002312513009
# 覆盖口径：HarmonyOS 应用（bundleType=app，Stage 模型，API≥9），单 entry HAP，
# 无 HSP/无 Android 关联/无 TA/非 In-house —— 元服务专属（5/6/7/8/9/10/11/13/1010/
# 9999）、共享库（1016-1020/7019）、Android 关联（1008/1009/7011-7013/1007）、
# TA（7015）、In-house（7022-7025）、加密（1023）标记 N/A。
import sys, zipfile, json, re, base64, datetime, subprocess, tempfile, os, io

app_f, chain_f, profile_f, expect_bundle = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
results = []   # (错误码, 检查项, PASS/FAIL/None=N-A, 说明)

def mark(codes, name, ok, note=''):
    tag = 'PASS' if ok else ('N/A ' if ok is None else 'FAIL')
    results.append((codes, name, tag, note))

raw = open(app_f, 'rb').read()
z = zipfile.ZipFile(app_f)
names = [i.filename for i in z.infolist()]
pack = json.loads(z.read('pack.info'))
hap_name = [n for n in names if n.endswith('.hap')][0]
inner = zipfile.ZipFile(io.BytesIO(z.read(hap_name)))
mod = json.loads(inner.read('module.json'))

# ── 995/1011：.app 后缀 + 非元服务（installationFree=false、bundleType=app）──
# 注意：hap 内 module.json 是【扁平结构】（installationFree/deviceTypes 在 module 顶层，
# 另有 packageName 字段），与源码 module.json5 的 distro 嵌套不同
inst_free = [m.get('installationFree') for m in [mod['module']]]
bundle_type = pack['summary']['app'].get('bundleType', 'app')
mod_package = mod['module'].get('packageName')
mark('995', '后缀 .app', app_f.endswith('.app'), app_f)
mark('1011/1010', '非元服务（installationFree=false / bundleType=app）',
     all(v is False for v in inst_free) and bundle_type == 'app',
     f'installationFree={inst_free}, bundleType={bundle_type}')

# ── 992/997/1004：包名一致（双源：pack.info summary.app.bundleName +
# hap module.json 顶层 app.bundleName；module.packageName 是模块名不参与比对）──
pn = pack['summary']['app']['bundleName']
app_bundle = mod['app'].get('bundleName')
mark('992/997/1004', f'包名 = {expect_bundle}', pn == expect_bundle and app_bundle == expect_bundle,
     f'pack.info={pn}, module.app.bundleName={app_bundle}；AGC 应用包名需一致（AGC 侧人工确认）')

# ── 998/1012：设备类型 ──
dt = pack['packages'][0].get('deviceType', [])
mod_dt = mod['module'].get('deviceTypes', [])
mark('1012', 'deviceTypes 无 default+phone 并存',
     not ('default' in dt and 'phone' in dt) and not ('default' in mod_dt and 'phone' in mod_dt),
     f'pack.info={dt}, module={mod_dt}')
mark('998', 'deviceTypes 与 AGC 分发设备一致（AGC 侧人工确认）', None, f'{dt}')

# ── 1015：zip 安全 ──
bad = z.testzip()
trav = [n for n in names if n.startswith('/') or '..' in n.split('/')]
mark('1015', 'zip 完整性/无路径穿越', bad is None and not trav, f'testzip={bad}, 可疑条目={trav}')

# ── 991/1014：签名块在场（以 bash 段 verify-app 输出为准——签名块是 EOCD 之前的
# v3 结构，字节层「尾部有数据」判别不适用）──
verify_log = open('verify.log', encoding='utf-8', errors='replace').read()
mark('991/1014', '签名块 v3 在场 + 摘要校验 true',
     'Find Hap Signing Block success' in verify_log and 'Digest verify result: true' in verify_log,
     'verify-app: ' + '；'.join(l.strip() for l in verify_log.splitlines() if 'Signing Block' in l or 'Digest' in l))

# ── 999：Profile 类型 = release ──
prof_txt = open(profile_f, 'rb').read().decode('latin1')
ptype = re.findall(r'"type":"([a-z]+)"', prof_txt)
mark('999', 'Profile 类型 = release', 'release' in ptype, f'{ptype}')

# ── 1000：Profile 有效期 ──
validity = re.findall(r'"validity":\{[^}]*\}', prof_txt)
ok_1000, note_1000 = None, 'Profile 未内嵌有效期字段（随证书有效期，AGC 侧裁决）'
if validity:
    kv = re.findall(r'"(notBefore|notAfter)":(\d+)', validity[0])
    if kv:
        d = {k: datetime.datetime.fromtimestamp(int(v) / 1000) for k, v in kv}
        now = datetime.datetime.utcnow()
        ok_1000 = d.get('notAfter', now) > now and d.get('notBefore', now - datetime.timedelta(days=1)) <= now
        note_1000 = str(d)
mark('1000', 'Profile 未过期', ok_1000, note_1000)

# ── 1002/1003/1005：叶子证书有效期/生效/合法性 ──
chain_certs = re.findall(rb'-----BEGIN CERTIFICATE-----\r?\n(.*?)\r?\n-----END CERTIFICATE-----',
                         open(chain_f, 'rb').read(), re.S)
leaf_path = os.path.join(tempfile.gettempdir(), 'pc-leaf.cer')
open(leaf_path, 'wb').write(base64.b64decode(b''.join(chain_certs[-1].split())))
out = subprocess.run(['openssl', 'x509', '-in', leaf_path, '-noout', '-subject', '-dates'],
                     capture_output=True, text=True).stdout
nb_s = re.search(r'notBefore=(.*)', out).group(1).strip()
na_s = re.search(r'notAfter=(.*)', out).group(1).strip()
nb = datetime.datetime.strptime(nb_s, '%b %d %H:%M:%S %Y GMT')
na = datetime.datetime.strptime(na_s, '%b %d %H:%M:%S %Y GMT')
now = datetime.datetime.utcnow()
mark('1002/1003/1005', '叶子证书在有效期内', nb <= now <= na, f'{nb_s} → {na_s}')
mark('1001', 'Profile 与证书匹配（verify-app Digest=true 即匹配）', None,
     '以 bash 段 verify-app 的「Digest verify result」为准')

# ── 7014：包内权限 ⊆ Profile 申请权限（无 ACL 受限权限）──
perms = [p['name'] for p in mod['module'].get('requestPermissions', [])]
normal = {'ohos.permission.INTERNET', 'ohos.permission.GET_NETWORK_INFO'}
restricted = [p for p in perms if p not in normal]
mark('7014', '权限均为普通权限（无 ACL 受限权限）', not restricted, f'{perms}；受限={restricted or "无"}')

# ── 1006：HAP 大小（应用包无元服务 2/10MB 限制）──
mark('1006', 'HAP 大小（应用包无元服务限制）', None, f'{z.getinfo(hap_name).file_size/1048576:.1f} MB')

# ── 1021：API ≥10 ──
api = pack['summary']['modules'][0]['apiVersion']
mark('1021', 'API 级别 ≥10', api['compatible'] >= 10, f"compatible={api['compatible']}, target={api['target']}")

# ── N/A 项（口径外）──
for codes, why in [
    ('5/6/13', '元服务卡片规范'), ('7/8', '元服务 2/10MB 限制'), ('9', '元服务包依赖'),
    ('10/11', '元服务 FA 模型 entry 约束'), ('9999', '元服务 API 检测'),
    ('1008/1009/7011/7012/7013/1007', 'Android 关联应用（未关联）'),
    ('1016/1017/1018/1019/1020/7019', '共享库 HSP（未使用）'),
    ('7015', 'TA 可信应用（无 .sec）'), ('7022/7023/7024/7025', 'In-house 分发类型（release 上架包）'),
    ('1023', '自定义加密（未配置）'), ('7020', '非 HSP 包混入（单 HAP）'),
    ('4/996/7021', '系统异常类（重传即可）'), ('994', '上传文件存在性（表单机制）'),
    ('1004', 'AGC 应用重复创建（首次创建）'),
]:
    mark(codes, 'N/A —— ' + why, None)

fails = [r for r in results if r[2] == 'FAIL']
for codes, name, tag, note in results:
    print(f'[{tag:4}] {codes:<18} {name}' + (f'  — {note}' if note else ''))
print(f'\n== 结果：{len(results)} 项，FAIL {len(fails)} ==')
sys.exit(1 if fails else 0)