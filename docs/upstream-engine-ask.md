# 上游需求：moonviz 字节边界 wasm 变体（wasmtime 可加载）

状态：**另行立项**（2026-09 定案）。过渡期 studio 用 WebView 事件桥 + node 测试宿。

## 背景与动机

moonviz.wasm 当前按 JS 宿主编译：WasmGC + **js-string builtins**
（`wasm/moon.pkg` 的 `use-js-builtin-string: true`）。字符串表示内置于 JS 引擎，
导致：

- wasmtime/Boa 等非 JS 运行时**无法加载**该产物；
- studio 的 Rust 侧（agent 循环）只能经 WebView 事件桥或 node 子进程访问引擎；
- 测试与 CI 依赖 node ≥24。

字节边界变体落地后：Rust 侧用 wasmtime 进程内直调——无 V8（省 30~80MB 安装包）、
无 node、无事件桥，构建/测试/运行全链只剩 Rust + WebView（UI 地基本身）。

## 需求清单（引擎仓库）

1. `wasm/moon.pkg`：`use-js-builtin-string` 关掉的变体构建
   （保留现有 js-string 版给浏览器——零拷贝更快，两版并存）。
2. `wasm/main.mbt`：字节↔字符串边界包装——入口收
   `(ptr: i32, len: i32)` 的 UTF-8 字节，内部解码为 String；返回值写回
   线性内存并返回 `(ptr,len)`（或约定返回区偏移）。导出名建议加 `_bytes` 后缀
   （`render_mbt_bytes` / `apply_agent_op_bytes` / ...），避免与现有导出冲突。
3. 宿主需要引擎导出 `memory` 与分配/释放函数（MoonBit 默认导出 malloc 语义
   需确认；若无可显式导出一个 `mv_alloc(len) -> ptr`）。
4. 版本策略：两变体同一版本号、同批发布（npm `moonviz-engine-wasm` 可加
   `dist/bytebound/moonviz.wasm` 或独立包名）。

## 消费侧（本仓库，待上游就绪后）

- `EngineHost` 增加 `Wasmtime` 变体：`wasmtime::Engine` + 模块编译（一次）+
  store 池；`call()` 直调 `_bytes` 导出。`invoke_fx_sdk` 从 `WebView(app)` 切到
  `Wasmtime`；`node_host.rs` 与 `scripts/engine-host.mjs` 删除。
- `sync-engine.mjs` 契约探针可改由 Rust 测试承担（node 在构建链中彻底退场；
  下载/解包并入 CI 步骤或一个小 Rust 工具）。
- `capabilities/default.json` 与前端 `__engineBridge` 监听移除。

## 性能注记

字节边界字符串需 UTF-8 拷贝（js-string 版零拷贝）。引擎单 op 毫秒级，
拷贝开销（KB 级文本）可忽略；浏览器端继续用 js-string 版，不受影响。
