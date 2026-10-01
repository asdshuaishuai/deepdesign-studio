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
