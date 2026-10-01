# 鸿蒙（HarmonyOS / OpenHarmony）适配方案

> 状态：**仅方案，未实施**。本文回答"能不能做、怎么做、代价在哪"，不含已落地代码。
> 事实核查日期：2026-09-29（来源见文末，立项前建议复核一遍时效）。

## 1. 结论先行

可行，但不是"Tauri 加个 target"级别的事——Tauri 官方无 HarmonyOS 目标，社区也没有成熟
port。现实路线是**换壳不换核**：

- Rust 核心（wasmtime 引擎宿主 + Agent 循环 + DDP 编解码 + models 快照）下沉为独立
  crate，编译为 OpenHarmony 动态库（`.so`，经 NAPI 暴露给 ArkTS）；
- 壳层用 DevEco Studio 的 **ArkUI Web 组件**（ArkWeb，Chromium 内核）承载现有单文件前端；
- Tauri 的 `invoke` 换成自建 JS 桥（`javaScriptProxy` 进、`runJavaScript` 出）。

事实源不动：还是那份 canonical `.mbt.md` + classic wasm 引擎（宿主中立、零 import 的
设计正好兑现）+ `.ddp` 容器。前端改动量约 20 行（invoke 兼容垫片）。

## 2. 现状资产盘点（什么能直接复用）

| 资产 | 复用度 | 说明 |
|------|--------|------|
| `frontend/index.html` 单文件前端 | 高 | 无打包器/无 HTTP 层；CSP 字符串原样沿用（ArkWeb 是 Chromium 内核，`wasm-unsafe-eval` 语义一致） |
| 引擎 classic wasm 产物 | 高 | WebView 画布实例原样跑，宿主中立是设计目标 |
| `wasmtime_host.rs` / `agent.rs` / vendored DDP | 高（需拆 crate） | 纯 Rust；musl 目标兼容；reqwest 走 rustls 可绕开 OpenSSL |
| `models.json` 快照 + thinking 方言表 | 完全复用 | 数据与纯逻辑，零平台耦合 |
| Tauri 命令层 `lib.rs` | 不可复用 | 换成 ArkTS 桥 + NAPI 门面 |
| 原生菜单 / 多窗口 / 自绘标题栏 | 不可复用 | ArkTS 侧重做；菜单动作入口可复用 `nativeMenuAction(id)` 约定 |

## 3. 已核实的关键技术事实（2026-09-29 检索）

- Rust `aarch64-unknown-linux-ohos` 为 **Tier 2（含 host tools）**：musl libc，
  clippy/rustfmt 可用；文档注明 OpenSSL 需 ohos-openssl——本仓库 reqwest 用 rustls，
  可完全绕开这一依赖。
- **ohos-rs**（napi-rs 的 OpenHarmony fork）生态活跃：`ohrs build` 提供 OHOS 构建环境、
  执行 cargo build、收集 `.so` 产物并生成 ArkTS/TS 类型声明（ohos.rs 站点 2026-07 仍更新）。
- ArkWeb `@ohos.web.webview`：`javaScriptProxy`（注册 JS 侧可调用对象）+
  `runJavaScript`（向页面注入执行 JS）——正好覆盖 invoke（JS→native）与
  agent-event 回投（native→JS）两个方向，无需发明新协议。
- NAPI（Node-API C ABI）是 ArkTS ↔ native 的官方 ABI，宿主无关，运行时不需要 node。
- Tauri 官方与社区（截至核查日）均无 HarmonyOS 支持；Qt 6.11 有官方鸿蒙适配（2026-03），
  但引入 Qt 等于换掉整个 UI 栈，不在考虑范围。
- HarmonyOS 应用默认单实例（UIAbility singleton 启动模式），与
  `tauri-plugin-single-instance` 的语义天然对齐，无需额外实现。

## 4. 架构：四层拆分

```
L3 壳（ArkTS / DevEco 工程）
    ArkUI Web($rawfile('index.html')) + javaScriptProxy 桥 + 菜单/对话框/权限
L2 门面 ×2（薄）
    tauri-facade（现有 lib.rs 瘦身而来，桌面行为零变化）
    ohos-facade（NAPI 暴露 core；ohrs 产 .so + ArkTS 声明）
L1 deepdesign-core（新 crate，从 src-tauri 下沉）
    EngineHost / agent 循环 / DDP 编解码 / 命令实现
    （invoke_fx_sdk、save_ddp、open_ddp、list_ddp_projects、save_text_file、
     rebase_agent_ops、model_registry、set_project_dirty…；对话框除外，见 §5-2）
L0 事实源（不动）
    canonical .mbt.md / classic wasm / .ddp
```

前端兼容垫片（示意，放在 i18n 标记块之外、主脚本之前）：

```js
window.__TAURI__ ??= {
  core: { invoke: (cmd, args) => window.__DD_BRIDGE__.invoke(cmd, JSON.stringify(args ?? {}))
              .then(JSON.parse) }
};
```

## 5. 难点与对策（按风险排序）

1. **wasmtime 在 OHOS/musl 上的编译与运行**——最大不确定项。cranelift 的 aarch64 后端
   成熟、musl 支持良好，但 OHOS 的 JIT 内存权限策略（W^X 类限制）需真机验证。
   对策：P0 探针周专门验证（把 wasm 契约测试编译到 ohos target 在真机/模拟器跑通）。
   回退（last resort）：agent 侧引擎调用经 JS 桥复用 WebView 实例（两实例合一）——
   代价是 agent op 走 wire、性能损失约一个数量级，且背弃"纯 Rust 运行时"的架构承诺，
   仅在 wasmtime 确认不可行时启用。
2. **对话框上移**：`confirm_discard` / `save_ddp` / `open_ddp` 的保存/打开/确认框现在
   在 Rust 侧（tauri dialog）。core 化后 Rust 无窗口能力，对话框必须由壳层出：命令拆
   两段（core 返回"需要对话框"的信封 → 壳层弹 ArkUI DocumentViewPicker → 结果回传
   core）。这是 L1 拆分中**唯一的接口改造**，其余命令是纯搬迁。
3. **agent-event 事件流**：Rust progress 回调 → NAPI threadsafe function → ArkTS →
   `runJavaScript('window.__DD_onAgentEvent(...)')`。run id 过滤逻辑留前端不动，
   丢 run id = 时间线失效的历史教训在哪个平台都成立。
4. **菜单与快捷键**：ArkTS 侧 Menu 组件重做；动作入口仍走
   `runJavaScript("nativeMenuAction('<id>')")`——与 `lib.rs::on_menu_event` 现有桥同构，
   test_studio 检查 D 的 id→函数映射表可平移复用；`set_menu_language` 同理映射 ArkTS
   资源。键盘快捷键在带键盘的平板上经 ArkWeb 传递，纯触屏以工具栏按钮兜底。
5. **窗口形态**：自绘标题栏（Overlay）改为 ArkUI 沉浸式 + 自绘；多窗口
   （`open_project_window`）v1 不做——"最近项目"热切换已覆盖主场景。
6. **网络权限**：agent 的 LLM 出网需 `ohos.permission.INTERNET`，无其他特殊能力。

## 6. 阶段计划（人力：1 名熟悉本仓库的开发者）

| 阶段 | 内容 | 出口判据 | 预估 |
|------|------|----------|------|
| P0 探针 | OHOS SDK + `rustup target add aarch64-unknown-linux-ohos` + wasmtime/引擎契约测试上真机 | wasm 契约测试在设备绿 | 1 周 |
| P1 core 拆分 | `src-tauri` → `deepdesign-core` + tauri 门面（纯重构 + 对话框信封改造） | `cargo test` 43 项全绿、桌面行为零变化 | 1–2 周 |
| P2 壳与桥 | DevEco 工程、NAPI 门面、JS 桥 + invoke 垫片、文件对话框、菜单、事件流 | 真机完成一次完整 agent run（含 preview 刷新） | 3–4 周 |
| P3 打包分发 | hap 签名（AGC 证书/Profile）、上架材料、CI 加 ohos job | AGC 提审通过 | 1 周 |

## 7. 测试策略

- `test_studio.cjs`：不动（前端只加垫片；注意检查 I 的"函数不得重复定义"约束——
  垫片用赋值表达式而非 `function` 声明，且放在动态切片区间之外）。
- core 契约测试：host 上照跑（P1 出口）；ohos target 上跑 wasm 契约子集（P0 出口）。
- 真机 e2e：hdc + hypium（社区鸿蒙自动化链路）。
- 桌面回归：P1/P2 期间桌面版必须零行为变化——tauri 门面是唯一允许的改动面。

## 8. 明确不做（v1 非目标）

- 手机竖屏形态（主窗 1360×900 / min 980×640，面向平板与折叠屏展开态）
- 同项目多窗口、系统级全局快捷键
- 用户组件库持久化（上游引擎未决，与桌面同状态）

## 9. 事实来源

- rustc 平台支持表：doc.rust-lang.org/rustc/platform-support（OpenHarmony 节：Tier 2
  with host tools、musl、ohos-openssl 注意事项）
- ohos.rs / github.com/ohos-rs（napi-rs 的 OHOS fork、`ohrs build` 产物链）
- developer.huawei.com ArkTS API（`@ohos.web.webview` 模块：javaScriptProxy /
  runJavaScript）
- "Tauri 无 OHOS 目标、无成熟社区 port"为 2026-09-29 检索结论，立项前复核

## 11. 模拟器实测记录（2026-10-01）

- 环境：devecocli 1.3.4 + CLT 26.0.0.851(linux-x64) + DeepDesignPC(2in1) 模拟器
  （HarmonyOS 7.0.0.107, x86_64, 3120×2080）
- 已打通：ArkUI 原生壳（1360×900 桌面窗口/deepDesign 标题/最大化修复/全量布局）
  构建→装机→启动→前端渲染全部成功；HAP 内 libs/{arm64-v8a,x86_64}/ 含
  libc++_shared 与 libdeepdesign_core.so（externalNativeOptions+CMake 集成生效）
- 未通：NAPI import 返回 undefined。`bm dump` 显示安装后 `nativeLibraryPath: ""`——
  **模拟器安装器对完全未签名（unsigned）HAP 不做 native 库解压登记**。
  修复路径：`devecocli auth login` 登录华为账号 → `devecocli signature generate`
  生成调试签名材料 → build-profile.json5 填入 signingConfigs → 构建签名 HAP 安装。
  该步骤需要华为账号登录，属于一次性人工操作，之后 CI 可复用签名材料。

## 12. NAPI 链路打通实录（2026-10-01，M1 完成）

**结论：Rust NAPI core 已在 2in1 模拟器上真实加载并返回数据**（顶栏
`core: deepdesign-core-ohos 0.4.0-beta (engine: moonviz wasm, host: wasmtime)`）。

### 根因（三层叠加，逐层剥开）

1. **HAP 未签名 → native 库不解压**（§11 遗留）。修复：不用华为账号，改用
   **SDK 自带的 OpenHarmony 调试密钥本地签发**——`toolchains/lib/` 下的
   `OpenHarmony.p12`（密码 123456）+ `OpenHarmonyProfileDebug.pem` +
   `UnsgnedDebugProfileTemplate.json`。流程：抽取模板内嵌证书 → 拼 3 级证书链
   （leaf+cacert+rootcacert）→ `hap-sign-tool sign-profile` 签发定制 profile
   （bundleName=com.deepcode.deepdesign、有效期至 2050）→ `sign-app` 签 HAP。
   已封装进 `ohos/ohos-run.sh --install`，全程免账号。
2. **so 陈旧**：rust-libs 里的 x86_64 so 是 crate 改名前的产物，NAPI 注册名是
   `deepdesign_core_ohos` ≠ import 期待名。重编替换后消除。
3. **导出名大小写（真正根因）**：napi-ohos 的 `#[napi]` 默认把 rust snake_case
   转成 **camelCase** 导出——`core_version` 注册为 **`coreVersion`**。ArkTS 侧
   一直按 snake_case 调用，永远 undefined。d.ts 声明与 ArkTS 调用改 camelCase
   后一次打通。

### 排障方法论（复用价值）

- `hilog` 里应用 console 输出的 tag 是 **A03d00/JSAPP**（不是 JSAPP）
- JCE 断链（玲珑容器内 JDK）：`$JAVA_HOME/conf/security/policy/unlimited/*.policy`
  是指向 /etc 的死链，需写实体文件 `grant { permission javax.crypto.CryptoAllPermission; };`
- 设备端 dlopen 探针：交叉编译 30 行 C（`--target=x86_64-linux-ohos`）push 到
  /data/local/tmp 执行，可验证依赖/注册符号；注意 shell 命名空间看不到
  /system/lib64/platformsdk，报 `libark_jsruntime.so` 缺失属预期，不代表 app 进程失败
- 插桩 napi-ohos（`[patch.crates-io]` 指向本地 fork + hilog-binding）可确认
  `napi_register_module_v1` 是否被 runtime 调用、回调表长度；插桩日志若含
  `format!` 注意 napi_derive 生成的名字带**尾随 \0**，拼进 CString 会 panic
- panic 穿越 `extern "C"` 会 SIGABRT 且 stderr 不可见：rust 侧 ctor 里
  `std::panic::set_hook` 把 panic 详情打进 hilog 是必备基建
- 对照实验：同 app 内放一个官方模板结构的 C++ NAPI 模块（entry.cpp），
  C++ 通/Rust 不通即可把问题锁进 so 差异——本次即靠它定位到命名大小写
- `JSON.stringify` 会跳过函数属性，`{}` 不代表对象为空；用 `typeof` 逐属性探测
- 模拟器为 undebuggable 版（hdc smode 失败），shell 无 root，读
  /data/log/faultlog 需用 `hdc file recv`（faultlogger 目录可拉）

### 遗留

- `opt-level=3, lto=false`（原 `z+fat-lto` 在 napi-ohos 生态有 panic 风险，保守起见未开）
- C++ 对照模块 entry.cpp/libentry.so 保留在工程中作回归探针

## 13. 原版前端 ArkWeb 承载（2026-10-02，M1.5 完成）

**结论：frontend/index.html 以 ArkWeb 全屏承载，UI/交互与桌面版一字不差；
moonviz wasm 引擎在模拟器上完整工作（建板/模板/图层树/画布渲染/命令流）。**

### 架构

原生壳（窗口/生命周期/签名分发）+ ArkWeb 全屏（原版前端）+ invoke 管线
（`__TAURI__` shim → `harmonyBridge`(javaScriptProxy) → Dispatch/NAPI core）。
前端以 `IS_TAURI=true` 原生模式启动，命令经 shim 进 ArkTS：系统能力走 OHOS
原生实现，引擎/加密类走 Rust NAPI core（camelCase 导出，见 §12）。

### 关键点（复用价值）

- **离线包必须用自定义 https 域名 + onInterceptRequest 全量回供**：
  `$rawfile` 加载的 `resource://` 页面，其 fetch/XHR/wasm 子请求**不触发
  onInterceptRequest**（静态资源可以，动态请求不行）。改为
  `https://appassets.deepdesign.local/` 域名 + 拦截器按路径回 rawfile 字节，
  fetch(wasm) 即刻恢复。这是 ArkWeb 离线包标准解法。
- `javaScriptOnDocumentStart` 注入 shim（ScriptItem.scriptRules=['*']）；
  `javaScriptProxy` 暴露 harmonyBridge；`onConsole` 桥接前端 console。
- 该镜像上 ArkTS 侧 `hilog.info` 不可见（疑似 release 域日志策略），
  **console.error（A03d00/JSAPP）是可靠通道**；web_render 进程日志巨量会
  触发 LOGS OVER PROC QUOTA 丢日志——UI overlay 直显探针最可靠。
- **模拟器 Meta 键粘滞**：uitest 键盘事件后 Meta 置位不释放，后续点击被
  当作窗口拖动手势拦截（web 收不到触摸）。`uitest uiInput keyEvent 1251`
  注入 Meta up 清除。真人不走此通道，不受影响。

### 实测证据（截图 + 探针）

- `{"tauri":true,"bridge":true,"eng":"dot"}`（shim/proxy/引擎三通）
- 引擎绿点 8-10ms；模板缩略图由 wasm 真实生成
- quickStart('login')：图层树 9 元素、画布渲染、rev 12、
  命令流 `HUMAN · template login <id> 390 844`

### 下一步（P2）

- Dispatch 补 `save_ddp/open_ddp/list_ddp_projects/rebase_agent_ops`
  （依赖 rust-core 下沉 DDP/agent 能力）
- 悬浮 Agent / 一键生成 走 invoke_fx_sdk（云端 LLM）或端侧小艺
- 真人手测：画布拖拽/改文字/导出 DDP/设置对话框

## 14. DDP 全链路 + 端到端冒烟（2026-10-02）

**rust-core 下沉 DDP 编解码（与桌面版同一 vendored moonviz-ddp，.ddp 两端互通）**：
- NAPI 导出 `ddpEncrypt/ddpDecrypt`（camelCase，b64 进出）；纯逻辑独立 `ddp`
  模块 + `--no-default-features` host 测试（4/4：带密码往返/DDP2 无密码/
  错密码拒绝/大文档）
- OHOS 交叉编译要点：zstd-sys 需 `CC_<target>`/`CFLAGS_<target>`/`AR_<target>`
  指向 OHOS clang；getrandom/argon2 直接编过
- `hilog-binding` 限定 `cfg(target_env = "ohos")`（host 测试不链接 OHOS 系统库；
  注意 ohos target 的 `target_os` 仍是 "linux"）

**Dispatch 补齐桌面命令面**：save_ddp（NAPI 加密 + DocumentViewPicker 另存）、
open_ddp（选文件 → 解密，口令错回 `needPassword` 重试语义）、list_ddp_projects
（目录扫描，沙箱外目录报错由前端容错）、invoke_fx_sdk 补 models 列表分支、
open_project_window（单窗口聚焦语义）。rebase_agent_ops 待 wasmtime 宿主下沉。

**端到端冒烟（JS 注入驱动，绕开 uitest 触摸通道限制）**：建板 → 图层树 9 元素
→ 画布渲染登录页 → rev 12 → 命令流 `HUMAN · template login <id> 390 844` →
设置对话框开关，全部通过；DDP roundtrip 装机自测 `ddp:ok`。

**装机**：`ohos-run.sh --install`（本地签名免账号）。

## 15. 双层标题栏修复 + 点击问题处置（2026-10-02）

**双层标题栏**：自由窗口默认带系统标题栏（与前端顶栏重复）——
`mainWindow.setWindowDecorVisible(false)` 隐藏。窗口控制由前端顶栏
（— □ ×）经 shim → harmonyBridge.win → Index.onWin 驱动原生 API
（minimize/close 已通；maximize 切 setFullScreen——注意该 API 在
PCEMU 镜像上表现不稳，全屏后布局破碎，已回退为 resize 行为）。

**点击问题**：模拟器 PC 形态（web_render + ozone headless 架构）下，
触摸/鼠标事件不派发给 ArkWeb 内部——键盘可进（WebSendKeyEvent），
触摸经 WMS 记录（uitest touchItem）但不达 web；XTest/uinput 各通道
均无法穿透。应用侧兜底：ArkUI `onTouch` 捕获 Down/Up 坐标 →
`runJavaScript` 转 synthetic MouseEvent+PointerEvent+click
（elementFromPoint），开关 `INPUT_FORWARD`（真机原生分发正常时可关）。
另：模拟器存在 **Meta 键粘滞**（uitest 键盘注入后 Meta 不释放，
点击被当窗口拖动手势），`uitest uiInput keyEvent 1251` 清除。

## 16. deveco 工具链实测结论（2026-10-02）

**`devecocli ui` 是 PC 模拟器交互验证的正确通道**（uitest/uinput/XTest 均不可靠）：
- `ui layout`：dump 完整 UI 树，**ArkWeb 内部 DOM 节点可见**（heading/button/
  staticText 带物理坐标）——找点击目标的唯一可靠手段
- `ui click/drag/text`：click/drag 实测有效（建板成功、元素选中 +
  属性面板激活 + 悬浮 Agent 行内编辑弹出——完整交互链验证通过）
- **`ui text` 触发 IME 会让 web_render 渲染挂起 → 应用黑屏**
  （进程存活，force-stop 重开恢复）——镜像级 bug，真人 IME 输入同样有此风险
- `devecocli log --bundle-name`：按应用过滤日志（含 JS console/hilog）
- `ui screenshot`、`window`、`device sqlite3`、`emulator scene/battery` 等
  按需可用；`skills list/find` 内置 43 个鸿蒙技能（崩溃分析/NAPI 内存等）

## 17. 系统级端侧 AI 作为 Agent 默认执行者（2026-10-02）

**分层执行策略**（`invoke_fx_sdk` 分发）：
1. **默认 = 系统级端侧 AI**（`localChatModel` / Data Augmentation Kit，
   API 20+；免 API key、数据本地化）——`init()` 就绪后 `chat()` 生成
   MoonViz op 命令流，白名单提取后按桌面契约
   `{ok, ops[], text, stopReason, mbt_b64}` 返回，前端 wasm 引擎重放
2. 用户显式配置云端 key → OpenAI 兼容端点（chat + models）
3. 端侧不可用 → 结构化提示「端侧模型不可用，请在设置中配置云端 API Key」

**工程要点**：
- OpenHarmony SDK 不含 Data Augmentation Kit——自建 ambient d.ts
  （`declare module '@kit.DataAugmentationKit'`）+ **动态 import 独立模块**
  （LocalChatBridge）：系统无该模块时加载失败被 catch 优雅降级，
  静态 import 会让整个页面模块加载失败
- init/chat 全部带超时护栏（init 10s / chat 30s）——模拟器无模型管理
  应用时 init 会挂起，无护栏则 Agent 永久无响应
- PCEMU 镜像实测 `端侧AI:不可用`（无模型管理服务，符合预期）；
  HarmonyOS NEXT 真机自动就绪
- 状态徽章注入 web 页面内显示（ArkUI overlay 会被同层渲染的 Web 盖住）：
  `core 版本 · ddp:ok · 端侧AI:状态`

## 18. deveco 全量审查与 UX 修复（2026-10-02）

**审查工具链**：`check arkts`（12 文件 17 警告）+ `check lint`（2 错误）+
`ui layout`（ArkWeb DOM 树逐节点坐标审计）+ `ui screenshot` 视觉对比。
（`check compat` 仅 macOS/Windows，linux 不支持）

**修复清单**：
1. 窗口启动即最大化（`maximize(EXIT_IMMERSIVE)`，保持自由窗口形态）——
   此前 1360×900 在 960vp 虚拟屏上会裁掉右侧属性面板/Agent 追踪
2. 前端 □ 按钮 → `maximize()/restore()` 系统语义（原 setFullScreen 在
   PCEMU 上布局碎裂）；move → `startMoving()`（顶栏空白拖动窗口）
3. 顶栏原生手感：shim 注入 mousedown 拖动 + 双击最大化热区
   （`e.target === topbar` 才触发，避开子控件）
4. 状态徽章：顶中遮顶栏文字 → 右上角、点击关闭、正常信息 8s 自动隐藏
5. Web UX 属性：darkMode(Auto) 跟随系统深色、竖向滚动条开、
   overScroll NEVER（防橡皮筋）、zoomAccess 关（防滚轮误触）
6. `setWindowDecorVisible` 容错（个别形态不支持时保留系统栏）
7. lint 两处 await-thenable 误报（dynamic import ESObject 用 Promise 包装）

**验证**（devecocli ui 实测）：最大化形态下模板卡建板 ✓、
元素拖拽（命令流 HUMAN · move + 悬浮 Agent 编辑条弹出）✓、
右侧属性面板完整显示 ✓、无双层标题栏/残留系统按钮 ✓。
