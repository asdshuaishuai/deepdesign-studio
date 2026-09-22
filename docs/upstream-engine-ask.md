# 上游需求：moonviz classic wasm ABI 契约化（wasmtime 纯 Rust 宿主的最后一块）

状态：**宿主已实施；写方向契约已解决，返回方向契约保留**（2026-09）。wasmtime 纯
Rust 宿主已接入（`src-tauri/src/wasmtime_host.rs`，wasmtime 49）：agent 循环与 cargo
test 进程内直调 classic wasm，node 子进程宿主与 WebView 事件桥已删除。**engine-v0.1.2
的 `_in` 分块槽契约（上游 issue #8）已接管全部写路径**（8d206b5 接入：wasmtime_host /
前端 engSlotLoad / sync 探针三处消费）——内存写入不变量不再是逆向细节。**剩余诉求仅
返回方向**：引擎分配的字符串指针布局（[refcnt][len][UTF-16LE]）仍靠逆向读解码，下方
`_bytes` 方案保留为该方向的备选路径。

## 背景与动机

classic 产物本身**已经**可被 wasmtime/Boa 等规范运行时加载（零 import、不依赖
JS String Builtins——那是 wasm-gc 变体的事，本仓库不用）。真正的缺口是：
**字符串 ABI 是逆向出来的实现细节，不是受支持的契约**：

- 字符串是 linear memory 对象（`[refcnt@ptr-8][长度@ptr-4][UTF-16LE@ptr+0]`），
  三处宿主（sync-engine / engine-host / 前端桥）各自实现了同构 codec——MoonBit 侧
  字符串布局或 GC 策略一变，所有宿主**静默损坏**（sync-engine 的 sha512 锚点只能
  保证「同一份字节」，拦不住上游新版改布局）；
- 宿主写入区依赖不变量「引擎 bump 堆顶不超过当前内存大小」——同样是实现细节。

ABI 契约化后：Rust 侧用 wasmtime 进程内直调——无 V8（省 30~80MB 安装包）、
无 node、无事件桥，构建/测试/运行全链只剩 Rust + WebView（UI 地基本身）。

## 需求清单（引擎仓库）

1. **首选**：官方文档化并承诺 classic 产物的字符串 ABI（对象布局 / UTF-16LE 编码 /
   写入安全区不变量 / 内存增长语义），把它从实现细节升格为宿主契约；或
2. **替代**：显式字节边界导出——入口收 `(ptr: i32, len: i32)` 的 UTF-8 字节，
   返回值写回线性内存并返回 `(ptr, len)`；导出名加 `_bytes` 后缀
   （`render_mbt_bytes` / `apply_agent_op_bytes` / ...）避免与现有导出冲突
   （保留现有字符串导出给 JS 宿主，两版并存）。
3. 宿主侧分配函数：显式导出 `mv_alloc(len) -> ptr`（或书面确认现有 malloc 语义可依赖）。
4. 版本策略：classic 与 `_bytes` 变体同版本号、同批发布（Release 资产并列）。

## 消费侧（本仓库，待上游就绪后）

- `EngineHost` 增加 `Wasmtime` 变体：`wasmtime::Engine` + 模块编译（一次）+
  store 池；`call()` 直调 `_bytes` 导出。`invoke_fx_sdk` 从 `WebView(app)` 切到
  `Wasmtime`；`node_host.rs` 与 `scripts/engine-host.mjs` 删除。
- `sync-engine.mjs` 契约探针可改由 Rust 测试承担（node 在构建链中彻底退场；
  下载/解包并入 CI 步骤或一个小 Rust 工具）。
- `capabilities/default.json` 与前端 `engine-req` 事件桥监听移除。

## 性能注记

宿主侧字符串编解码是拷贝级开销（KB 级文本、引擎单 op 毫秒级，可忽略）——
classic 与 `_bytes` 两条路线在这点上等价；选择依据是**契约稳定性**，不是速度。
