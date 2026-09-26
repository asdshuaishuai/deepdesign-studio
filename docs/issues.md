# 审查问题清单

审查时间：2026-09-26（提交 `f5c51f4` 之后的工作区状态）。
方法：五个维度并行审查（功能完整性 / 产品完备性 / 死代码 / 连通性 / agent 可靠性与低幻觉 / 代码规范性），
再对每条 P0/P1 结论回验源码。**本清单只登记问题，不含修复。**

核实状态标记：

- **[已验]** —— 审查者亲自读过源码确认，行号可点。
- **[转述]** —— 来自并行审查的行号引用，审查者未亲自打开（置信度中等）。
- **[误报-已撤回]** —— 初版报告有误，复查推翻。

---

## 修复记录（2026-09-26，核查后第一批）

**已修（26 项）**：P0 全部四条——
1 `list_ddp_projects` 失败返回 Err + 前端对账「任一目录失败不落盘」；
2 capabilities `windows: ["main","proj-*"]`；
3 preview 竞态 viewEpoch 守卫（调度/落地双比对）+ inkPersist 入队 + declMenu 补同步；
4 `studioFlows` 影子整体删除。
P1：5（Mindset 段改教 [w][h] 一步到位）、6（`askFxSdk` 对 agent_no_mbt 透传 clarifyText，
sendAgent catch 走澄清流）、8（`applyAgentTerminal` 公共函数，sendAgent 同享 rebase 保护）、
9（inspection 枚举补 list-ops）、10（Anthropic finish_reason 透传 + 截断标注进总结文本）、
11（回落 128K→64K）、14（state.revision 计数，四个成功点 +1，终态/finish_partial 信封带出，
前端优先读顶层 revision）。
P2：17（「校验并渲染」顺带 session lint 亮债数）、19（zoomFit 真适配，⌘0/右键/工具栏接线，1:1 保留）、
20（⇧⌘⌫/⇧⌘Backspace 双平台绑定 + confirm 防误按）、22（组件点选 'agent'→'human' 门统一）、
24（APP_VER '6.0'→'0.3.0'）。
P3：25（placeMode/opCmds/scale/INK_MARK/window.__state/sessions.baseCmd 字段全删）、
26（forgetProject 删）、27（AGENT_GATE_DEBT 改 `&[&str]`，注释指示的修复路径可达）。
P4：33（`sanitizeSvg`：属性值裸引号归一 + 剥 script/on\*，两处 innerHTML 接线）、
36（Rust 两处 emit 吞错改 eprintln、前端 dirty 同步与 trace listen 失败改 console.warn）、
38（win.eval 改 serde_json 字符串编码）。
另：12（探针加 AgentGate 观察计数——真机实证 7 个 fill 宽组件在统一位置被拒系位置 artifact，
登记警告不 fail）、13（e2e 补 done 收尾断言 + events 内存副本）、28（models.rs 双清单交叉注释）。

**登记不修（附理由）**：
- P1-7 护栏体系（熔断/op 指纹去重/deadline/取消令牌）——设计任务，单独排期；
- P2-15/16 组件库持久化与画板工具——依赖引擎侧持久化设计（AGENTS.md 已登记 USERCOMP_UNAVAILABLE）；
- P2-18 产品缺口清单——产品 backlog 性质；
- P2-21 非 tap 交互的演示执行——演示播放器限制，提示词侧已诚实标注，播放器增强另排；
- P2-23 Windows 原生菜单——与标题栏合并方案冲突，等方向；
- P3-29 session_generate_responsive 预留槽——无害（变更统一走 session_apply_agent），登记；
- P3-30/31 test_studio 结构性增强（前端零引用检测、切片机制替换）——防线工程单独做；
- P3-34 undo/redo 合并——纯重复无行为风险，低收益重构；
- P3-37 路径白名单——桌面场景 path 均来自用户对话框/注册表，即选即授权；
  错误面已由 P0-1 收口（canonicalize 的 symlink 语义反而在 Windows 产 `\\?\` 前缀破坏路径显示）。

回归：`cargo test` 42 全绿、`node test_studio.cjs` 通过、`sync-engine` 探针通过
（真机实证：探针新断言首跑即抓到 app_bar 等位置 artifact，按设计降为警告）。

---

## 核查记录（2026-09-26，基准 `f5c51f4`，与审查基准一致）

三片并行回验（前端 18 项 / Rust 侧 20 项 / 脚本与文档 12 项），全部 50 项声明逐条对照源码。
**总裁决：行号零实质漂移（仅两处 ±5 行内偏差）；成立 36、部分成立 9、撤销 2；P0 四条全部维持。**
以下为逐条勘误，正文保持审查时点原文。

**P0 勘误：**

- **条目 3**：`declMenu` 清空编辑器**有置脏**（`declDraftDirty=true`，进 anyDirty 守卫）——真实缺口是清空后不调
  `syncFileLabel`/`syncDirtyRemote`（UI 与 Rust 侧脏态失步），且不触碰 `mbtText`/`nodes`，「不置脏」定性不实；
  `switchSession` 行号应为 1750-1757。其余三处绕过（schedulePreview/paintPreview、inkPersist）与 `!preview`
  守卫行号逐字命中。
- **条目 4**：完全成立。`studioFlows=flows.slice()` 在 `if(!preview)` 之外，5 个读点全为恒取第一支的三元。

**P1 勘误：**

- **条目 5**：结论方向成立、证据半边引错。`agent.rs:96-99` 恰是**教 #18 修复后新行为**的正面教学
  （"ALWAYS pass the final [w][h]… the gate evaluates the FINAL bbox (engine-v0.1.6, issue #18)"），
  不是反模式；真正与它对立的只有 Mindset 段 `73-74`（"run query…then update w/h right after placing"）。
  即：两段指令矛盾属实，但矛盾形态是「旧残留 vs 新正解」，非「两段都教反模式」。
- **条目 6**：核心事实成立（`agent.rs:1331-1339` 触发条件、产品路径恒有文档、前端 2490 启发式是活的、
  `askFxSdk` throw 丢弃 `data.text`）。两点修正：① throw 前已 emit 过 assistant_text 轨迹行，
  提问文本是「不进澄清流」而非「完全不可见」；② **文档漂移 5 应撤销**——AGENTS.md 212-217 描述的就是
  前端启发式数据流（且自陈「提示词级实现/启发式触发」），与实现一致，「契约层从未接通」指 Rust clarify
  分支不可达，但文档从未声称它生效。
- **条目 7**：成立，且最坏估计还**低估**：`chat_once_with_retry` 瞬时错误最多重试 4 次（每次独立 180s 超时
  + 0.8/2.5/5s 退避），单轮回复可携带多个 tool_calls 各占 45s 引擎时限。
- **条目 9**：`prompt_avoids_apply_rejected_ops` 断言 **16** 个 token 非 15。`list-ops` 缺席的只是
  **提示词 inspection 枚举**（`agent.rs:144-151`，且 `:152` 自相引用地提到了它）——路由表 `READONLY_OPS`
  （455-464）**含 list-ops** 且有测试锚定（1933 行）。即：运行时可达，缺口是「提示词未向模型宣讲该检视能力」，
  「运行时注册表缺席」的表述不成立。
- **条目 10**：成立。补一处细节：`max_tokens` 在无思考预算时固定 8192，非一律 budget+4096。
- **条目 12**：机制成立（探针 `sync-engine.mjs:344-347` 走 `apply_human_op`、只看 `r.ok`）；
  「可能含 AgentGate 必拒 id」无实证（`AGENT_GATE_DEBT` 为空且只登记模板 id；空种子单 place 通常无债），
  **降级为低**。
- **条目 13**：断言实为 **4** 条（100 行非空断言 + 3 条结构断言）；负面清单（不断言幻觉 op/门拒/死链/
  stopReason/审查层）全部属实。
- **条目 14**：成立，行号逐字命中；max_turns 兜底返回（1423-1430）同样无 revision。

**P2 勘误：**

- **条目 15**：四个 handler 全部只 toast 属实（`saveAsComponent` 另有活动画板前置守卫）；但「4 个可见入口」
  不准——静态面板只有「画板→组件」「导入 MCF」2 个可见按钮，「导出 MCF」「删除组件」在用户组件动态卡片里
  （2731/2735），组件库恒空时**不可达**。文案自相矛盾（813-818）成立。
- **条目 24**：当前漂移实为两派——`APP_VER='6.0'`（UI 显示）vs `tauri.conf.json` 与 AboutMetadata
  **一致的 0.3.0**。三处两个值，非三个值。

**P3 勘误：**

- **条目 25**：六个死变量全部成立（逐一复核，含赋值点/读点穷举）。
- **条目 26**：成立（含字符串分发与 onclick 属性面的全域搜索）。
- **条目 28**：「内容完全重复」过强——两个白名单覆盖同两个 id（minimax/minimax-intl），但元组形状不同、
  登记的是两条分歧轴（npm 协议族 vs api 端点）、喂给两个不同检查。维护性担忧成立，重复定性撤销。
- **条目 30**：「没有一条零引用断言」**不成立**——检查 H（test_studio.cjs:154-166）就是孤儿检测
  （Rust 命令无前端消费者 = 死命令 + 反向未注册 invoke）。缺口收窄为：**前端函数**层面无零引用检测
  （H 只覆盖 Tauri 命令）。另检查 E 是反向缺席断言、检查 F 是守卫扫描，「全部是存在性断言」不严格。
  检查 G 的 mapCalls 以全局 `const|let|var` 收集的 `defined` 为白名单，稀释效应属实。

**P4 勘误：**

- **条目 32**：192MB 阈值仅 `wasmtime_host.rs:57` 与 `index.html:1290` **两处**（sync-engine.mjs 无 192）；
  掩码与槽步确实是三处（host/前端/脚本）。「三处硬编码」应表述为「掩码+槽步三处、回收阈值两处」。
- **条目 33**：两处 innerHTML 直灌属实（1626/3828）；「前端其他拼接处都走 escHtml/escAttr」**不实**——
  另有同类未转义：2701（`err.message` 直插）、3677（API 返回模型 id 进 `option value`）、1542（仅转义 `<`）。
  条目的真实版本应是「引擎 SVG 是**最大的**未转义注入面」而非「唯一的」。
- **条目 34**：重复属实，但两函数**各 19 行**（合计跨度 38 行），非「各 38 行」。
- **条目 35**：8/11 命令为 `Result<_, String>`；`set_project_dirty`/`app_exit` 无返回值、`model_registry`
  直接返回 Value——「全部」不实，is_transient_llm_error 字符串匹配属实。
- **条目 36**：index.html:1228 实为内部 `invoke('set_project_dirty',…).catch(()=>{})`（表述走样、吞错属实）；
  1405 引擎失败时另记录 `engineFailed` 变量供后续文案（非纯变色）。其余（2341/2369 TRACE.tried 锁死、
  2.4s toast、clipboard 两处、apiKey 明文+旧键未删）全部成立。

**未验证项裁决：**

- **A（list-ops 缺席 inspection 清单）**：**部分成立→收窄**。READONLY_OPS 在场 + 测试锚定；
  仅提示词枚举缺席（见条目 9 勘误）。
- **B（菜单「适配窗口」）**：**成立**。`lib.rs:670-676` id=`view-fit`、文案「适配窗口」、快捷键 CmdOrCtrl+0。
- **C（ops ≥25 数量下限）**：**成立**。`sync-engine.mjs:318-321`，`ops` 全文件仅此一处消费、无集合对账。

**文档漂移裁决：**

- 漂移 1/2/3/4 **成立**（命令矩阵 9 vs 实际 11，差异恰为 `rebase_agent_ops`/`open_project_window`；
  漂移 4 行号修正：AGENTS.md:265-266、前端 renderLayers 1798-1816 且 1813-1814 注释与文档直接矛盾）。
- **漂移 5 撤销**（见条目 6 勘误②：文档描述与实现一致，且文档已自我声明为启发式）。

**补强确认（条目 2）**：capabilities/ 目录仅 default.json 一个文件，`proj-*` 零覆盖确凿；
前端消费面（`winCtl` minimize/close、`setTitle`、`listen('agent-event')`、`listen('app-close-request')`）
全部依赖被 ACL 拦截的权限，P0 定级维持。

---

## P0 — 数据丢失或功能静默失效

### 1. `list_ddp_projects` 把"读不到目录"报成成功空列表 **[已验]**

`src-tauri/src/lib.rs:121-123` 目录不存在时返回 `{"ok":true,"projects":[]}`；
`:125` 的 `if let Ok(entries) = std::fs::read_dir(...)` 又把读取失败吞掉。
前端 `frontend/index.html:3250-3251` 用 `found.has(p.path)` 过滤并 `saveRecents(next)` 落盘。

后果：父目录瞬时不可读（移动盘未挂载 / 网络盘断连 / 权限变更）时，
**最近项目列表被静默清空且无法恢复**，而引擎层返回的是 `ok:true`。

修法方向：失败返回 `Err` 而非 `Ok(空)`。

### 2. capabilities 未覆盖 `proj-*` 窗口，多窗口功能半残 **[已验]**

`src-tauri/capabilities/default.json:5` 是 `"windows": ["main"]`，
而 `open_project_window`（`lib.rs:232-257`）建的是 `proj-<epoch>` 窗口，不在覆盖内。

后果链（三条均静默）：

- 缺 `core:event:allow-listen` → `index.html:3764` 的 `app-close-request` 监听失效
  → **新窗口关窗时脏文档确认框不弹，未保存内容直接丢**；
- 同一权限缺失 → `index.html:2352` 的 `agent-event` 监听失效
  → **新窗口 Agent 实时轨迹全程空白**；
- 缺 `core:window:allow-minimize/close/set-title` → `winCtl`（`index.html:1158`）
  的 `console.warn` 吞掉 → **新窗口标题栏按钮全哑、标题永不同步**。

`AGENTS.md` 宣称"capabilities 最小集"是设计选择，但 `"windows":["main"]` 与
"多窗口已落地"不能同时成立——本条是两者之间未对账的缺口。

修法方向：按窗口标签放宽覆盖范围。

### 3. 串行化纪律在四处实际失效 **[已验]**

`AGENTS.md:276` 声称"所有会改项目的操作必须经 `serializeProject(task)`"。
实际绕过点：

| 位置 | 绕过内容 |
|---|---|
| `index.html:1515-1526` | `schedulePreview` / `paintPreview` —— 900ms `setTimeout` 触发 `applyMbtResult` |
| `index.html:3131-3135` | `inkPersist` —— 直写 `mbtText` + `projectDirty` + `syncDirtyRemote` |
| `index.html:1755` | `switchSession` → `refresh`，不经队列改写 `nodes` / `currentSvg` |
| `index.html:2092` | `declMenu` 清空编辑器 —— 不置脏、不同步 `syncFileLabel`/`syncDirtyRemote` |

`paintPreview` 已有 `!preview` 守卫（`:1493` 不写 `mbtText`、`:1495` 不置脏、
`:1498` 不动 `decl.value`），**不构成数据丢失**。真实竞态是显示失步：
人类 op 完成更新画布后，一个更早的 agent 预览渲染落地，把画布显示覆盖成陈旧内容，
直到下一次真实 op 才自愈。

### 4. `studioFlows` 是不变量为空却被 6 处消费的冗余影子 **[已验]**

`index.html:1503`：`if(!preview)flows=...; studioFlows=flows.slice();` —— `studioFlows`
恒等于 `flows`（每次 `applyMbtResult` 都重新拷贝）。读点全部是
`studioFlows.length?studioFlows:flows`（`:1630`、`:1660`、`:2951`、`:3034`、`:3143`），
三元恒取第一支。

`index.html:1168` 的注释写 "canonical flow state now lives in mbtText"，
但 `studioFlows` 仍在运行时被持续赋值与消费——注释在陈述一个未完成的重构。

> **[误报-已撤回]** 初版报告称"preview 后 `flows` 与 `studioFlows` 语义分叉"。**不成立**——
> `studioFlows=flows.slice()` 在 `if(!preview)` 之外，preview 时只是重复拷贝了同样的 `flows`，
> 两者内容恒等，从未分叉。

---

## P1 — Agent 可靠性与低幻觉

### 5. 提示词仍在教 #18 刚消灭的反模式，两段指令直接对立 **[已验]**

- `agent.rs:73-74`（Mindset 段）："run query to learn actual sizes, then
  **update w/h right after placing**"
- `agent.rs:96-99`（Build loop 第 3 步）："a place that collides at component-default
  size is **rejected even if you meant to resize right after**"

`AGENTS.md:200-201` 记载"真实 run 111 次拒绝的根因整类消除"正是靠 #18。
#18 修好了引擎，**但提示词里教这条反模式的句子没删**。模型同时收到两条相反指令。

### 6. CLARIFY-FIRST 契约层从未接通 **[已验]**

Rust 侧澄清分支（`agent.rs:1331-1339`）的触发条件是
`state.mbt.is_none() && state.ops.is_empty()`。但两个前端入口都在调 agent 前
保证文档非空——`runGlobalPrompt:2474-2479` 自动建板，
`sendAgent:2247-2248` 要求 `selected` 存在（必然有文档）。

故 `mbt.is_none()` 恒假，**`agent.rs:1335-1339` 的 `agent_no_mbt` /
`stopReason:"clarify"` 在产品路径上永远走不到**。

而前端 `index.html:2490` 的 `(!r.ops.length) && r.text` 分支**是活的**——
它走 Rust 的 `ok:true` 正常返回路径（文档非空、模型只提问不调工具）。

结论：`AGENTS.md:212-217` 描述的「Rust 返回 clarify → 前端挂起」数据流**从未存在过**；
实际生效的是一条纯前端的、判据完全不同的启发式。`AGENTS.md` 关于"单槽 pending /
未验证模型意图"的自我批评方向对，但低估了程度——不是启发式粗糙，是契约层从未接通。

另：`agent_no_mbt` 触发时 `askFxSdk`（`index.html:3708-3711`）会 `throw`，
模型的实际提问文本被整段丢弃，用户只看到泛化错误
`Agent 不可用：agent_no_mbt: LLM did not call any tools`。

### 7. 主循环无任何失败护栏 **[转述]**

`agent.rs:27` `MAX_STEPS=200`，`:1245-1418` 循环内除步数外无退出分支。缺：

- 连续失败计数 / 熔断
- 相同 op 指纹去重（`:172-174` 的 "Never repeat an identical failing op"
  只是提示词祈使句，运行时零强制）
- 总墙钟 deadline、总 token / 成本预算
- run 级取消令牌（`invoke_fx_sdk`（`lib.rs:417`）无取消挂载，关窗不中止 run）

最坏 `200 × (180s LLM + 45s 引擎) ≈ 12 小时`，期间 `EngineHost` 全局 `Mutex`
（`wasmtime_host.rs:121`）被独占。

### 8. 终态 rebase 只接了全局 Prompt，行内 Agent 无同款保护 **[转述]**

`rebase_agent_ops` 只在 `index.html:2516`（`runGlobalPrompt`）接线。
`sendAgent`（`:2274-2280`）无起点快照比对、无 rebase，且 render 缺失时走 `:2279`
直写 `mbtText` 绕过 `applyMbtResult`。**同一条丢失更新路径两个 Agent 入口只堵了一个。**

### 9. 幻觉防线只有"数量下限"，无集合对账 **[转述]**

- `sync-engine.mjs:319-321` 只断言 `ops.length >= 25`
- `agent.rs:2079-2098` `prompt_avoids_apply_rejected_ops` 只断言 15 个 token **在场**

引擎新增 / 改名 / 删除一个 mutating op，三方全绿但提示词已过时。
反向的 `list-ops`（唯一能防模型编造 op 名的运行时注册表）在 `agent.rs:145-148`
的 inspection 清单里缺席，只在 `:152` 的一句错误提示里被顺带提到。

### 10. Anthropic 分支输出预算被压到 4096，且截断信号被丢弃 **[已验]**

`agent.rs:1034` `max_tokens = thinking_budget + 4096`（max 档 32768+4096）。
`normalize_anthropic_response`（`:296-331`）逐块 match，**完全不读 `stop_reason`**，
所以 `max_tokens` 截断对主循环不可见——半截 `tool_use` 会被当正常调用，
空 content 会被当"模型总结了"。

另：`chat_once`（`:959-976`）不发 `max_tokens`，OpenAI 侧无输出上限。

### 11. `model_context_window` 对快照外模型过于乐观 **[已验]**

`agent.rs:849-869` 按 `/` 末段精确匹配窗口，命中时返回快照真值（含 `context: 64000`
的条目会正确返回 64000）；未命中回落 `DEFAULT_CONTEXT_TOKENS = 128K`（`:845`）。

缺陷只在**快照外的模型**（自部署 / 新模型）：若实际窗口是 32K，
按 128K 算 0.7 阈值 = 89K 才裁剪 → 请求直接 400，L2 形同虚设。
单测 `:1612` 只断言 `>= 16K`，测不出这个偏差。

> **[误报-已撤回]** 初版报告称"存在 64000 条目所以误判"。**不成立**——命中时返回的
> 就是快照里的真值。真实缺陷仅在未命中路径。

### 12. 组件快照只过人类门，不过 AgentGate **[转述]**

`sync-engine.mjs:344-349` 探针用 `apply_human_op` 逐个 place。
`components.json` 可能含"人类门可 place、AgentGate 必拒"的 id，
模型据此生成必然被拒的 op。

### 13. 真机 e2e 默认永不执行，断言极弱 **[转述]**

`tests/agent_llm_e2e.rs:25-28` 环境变量门控，CI 也不跑（`AGENTS.md:336-338`）。
断言仅 3 条（板数 ≥4 / 主色 hex 存在 / `validate_mbt` 通过），
不断言幻觉 op、门拒绝次数、死链占位名、`stopReason`、审查层行为。
**提示词工程的所有问题在自动化里零反馈。**

### 14. agent 终态信封无 `revision`，连带状态栏 rev 归零 **[已验]**

`agent.rs:1348-1355` 终态返回 `mbt_b64` / `render` / `ops` / `stopReason` / `text`，
**无 `revision`**。前端 `index.html:2524` 读 `render.revision` → undefined
→ `applyMbtResult:1493` 的 `mbtRevision=Number(undefined)||0` → 状态栏 `:1545` 的
rev 显示被清空。`runAutoFix`（`:1845`）比较 `mbtRevision` 的逻辑随之失真。

对照：`undoMbt/redoMbt`（`:1352`、`:1371`）用 `r.rev||r.revision` 双键兜底，
说明作者自己不确定引擎发哪个键名。

---

## P2 — 产品完备性

### 15. 用户组件库 4 个可见入口全是 toast 空实现，且面板文案自相矛盾 **[转验]**

`index.html:809-818` 有「画板→组件」「导入 MCF」「导出 MCF」「删除组件」4 个真实按钮
+ 一个 `.mcf` file input，`:2761-2770` 全部只 `toast(USERCOMP_UNAVAILABLE)`。
`:813-817` 仍在教用户走这三步，`:818` 才说"上述按钮当前会提示不可用"。

引擎导出 `session_component_compile_b64` / `session_library_snapshot` 已在产物中
且 `wasmtime_host.rs:367-370` 已实现路由——**路由有、调用方没有**。

### 16. 画板工具（frame）是永久占位 **[转述]**

`index.html:842` 按钮常驻可见，`:2810` 只 toast。`:2207-2208` 注释
"画板工具未实现，不绑 A"。同时 `placeMode`（`:1167`）因此永远为 `null`。

### 17. 「校验并渲染」绕过 AgentGate **[转述]**

`validateMbtNow`（`:2604-2616`）只做 `validate_mbt_in` + `render_mbt_in`。
`AGENTS.md:232` 明确 `apply-agent-mbt-b64` 比 op 路径更严
（`no_sibling_overlap` 硬拦），此处被 `render_mbt` 替代，
`:2608-2609` 自承"视觉债的硬拒绝语义待引擎补"。UI 却给用户绿灯。

### 18. 产品缺口清单 **[转述]**

均为高：

- **无裸 `.mbt.md` 打开入口** —— 而 `.mbt.md` 是文档公开宣称的唯一事实源格式
- **无位图 / PDF 导出、无剪贴板粘贴** —— 全仓 `navigator.clipboard` 仅 2 处
  `writeText`（`:2089`、`:2601`）
- **无自动保存 / 崩溃恢复** —— 只有 `projectDirty` 布尔
- **错误码直抛用户** —— `ddp_authentication_failed` 等经 `index.html:3357/3407`
  的 `.slice(0,80)` 显示，密码错与文件损坏无法区分
- **错误通道只有 2.4s toast**（`:1254`）—— 无面板、无重试、无诊断导出
- **引擎加载失败只把 `#eng-dot` 变红**（`:1405`），无任何用户可见说明
- **apiKey 明文 localStorage 多槽**（`:3502-3514`），且旧单槽
  `deepdesign-fx-config` 迁移后**从未 `removeItem`**

### 19. `zoomReset` 名不副实，五处文案互相矛盾 **[部分转述]**

`:2997` 实为 `zoom=1`（1:1），而菜单「适配窗口 ⌘0」（`lib.rs:670-676` [转述]）、
画布右键「⛶ 适配窗口」、帮助弹窗、工具栏 title 全部承诺 fit 适配。
即使 `lib.rs` 侧未核实，`:2997` 的实现与"适配窗口"命名不符已成立。

### 20. `⇧⌘⌫` 删除画板，两个平台都按不出 **[转述]**

`:2078` 菜单 kbd 承诺 `⇧⌘⌫`；`:2186-2205` keydown 分发表无 `Backspace`/`Delete`
任何组合键绑定。`:1134` 的 Windows 修正表还把它映射成 `Ctrl+Shift+Del` —— 同样无绑定。

### 21. 非 tap 交互可绑定但永不响应 **[转述]**

`:2866` Inspector 下拉列 10 个 trigger，只有 `tap` 在演示中可执行。
`agent.rs:141-143` 仍向 LLM 宣称 `haptic` / `play_sound` / `toggle_state` 可用。

### 22. 人类操作走 Agent 门 **[转述]**

`:2742` 组件面板点选用 `runOp(..., 'agent')`，而 `:2797` 拖入是 `'human'` ——
同一动作两条门，与 `AGENTS.md:24-26` 的"人类走 apply_human_op"边界冲突。

### 23. Windows 侧无原生菜单栏无关于面板 **[转述]**

`lib.rs:729-733` 空实现，21 个菜单项 Windows 只有 12 个有文件菜单等价物。

### 24. 版本号三处不一致 **[转述]**

`APP_VER='6.0'`（`:1123`）vs `tauri.conf.json` `0.3.0` vs `lib.rs:534`
AboutMetadata `0.3.0`。UI 显示 v6.0，关于面板显示 0.3.0。

---

## P3 — 死代码与无效代码

> 正面记录：`9f48220` 事故级别的批量死函数**未复发**。
> `INTERACTIVE_SURFACE` 39 项 + 检查 A/C/D/F/G 当前有效。

### 25. 死状态变量（均在 test_studio 保护范围之外）**[已验]**

| 变量 | 位置 | 证据 |
|---|---|---|
| `placeMode` | `:1167` | 声明为 `null`；`:1488`、`:3437` 只赋 `null`，全文无真值赋值 → `:2214` 的 Escape 分支半边不可达 |
| `INK_MARK` | `:1193` | 全仓仅声明行命中；`inkExtract`/`inkInject` 靠 3 处手写字面量 |
| `window.__state` | `:3749` | 全仓零消费者（test_studio 改用 `vm.runInContext` 直读） |
| `opCmds` | `:1163` | 唯一读点在已死的 `__state` 内 → 实际只写不读 |
| `scale` | `:1165` | 只初始化从不赋值（`:1868` 的 `(scale\|\|1)` 恒返回 1） |
| `sessions[id].baseCmd` | `:1501` | 恒为常量 `'__mbt__'`，无信息量 |

### 26. 零引用孤儿函数 **[已验]**

`forgetProject`（`:3240`）—— 全仓仅定义行命中。
不存在批量死函数，这是当前状态良好的证明。

### 27. `AGENT_GATE_DEBT` 修复路径类型层面不可达 **[转述]**

`agent.rs:2050` `const AGENT_GATE_DEBT: [&str; 0] = [];`。
哨兵清空为设计，但 `:2072` 注释指示的"把 id 加进 AGENT_GATE_DEBT"
在 `[&str; 0]` 类型下编译不过。真出现债模板时测试会红但无法按注释修复
（需先改类型为 `&[&str]`）。

### 28. `models.rs` 双重分歧登记 **[转述]**

`KNOWN_FAMILY_DIVERGENCES`（`:35-38`）与 `KNOWN_DIVERGENCES`（`:121-135`）
内容完全重复，一个比 npm 家族一个比 URL。任一表加了条目另一表不加就分叉。

### 29. `session_generate_responsive` 两处契约矛盾 **[转述]**

宿主备了路由槽（`wasmtime_host.rs:84`），但 `agent.rs:127` 教给模型、
`:1954` 断言它不是只读，变更分支只调 `session_apply_agent` ——
**该 fn_name 永远不会被路由到**。

### 30. `test_studio.cjs` 没有一条"零引用"断言 **[转述]**

检查 A/B/C/D/E/F/G 全是"存在性"断言（被引用的必须存在）。
第 25/26 条能长期存活正是因为这个结构性缺口。
另：检查 G 的 `mapCalls` 提取会把 `let x =` 的任意变量收进 `defined`，有效性被稀释。

---

## P4 — 规范性

### 31. `test_studio.cjs:172` 的 `indexOf` 动态切片是全仓最大测试脆弱点 **[转述]**

`AGENTS.md` 自陈"会静默取到错东西"。历史事故 `9f48220` 与露营 e2e 残留
**两次由它漏过**，根因（切片机制）仍在。
`:169` 的 `fn(name)` 抽取器只认 `function NAME(` 形式 + `indexOf('){')` 定位。

### 32. 引擎 ABI 协议常量三处硬编码，无对账测试 **[转述]**

`LEN_MASK` / `SLOT_CHUNK` / `192MB` 阈值分散在
`wasmtime_host.rs:53/55/57`、`index.html:1270/1280/1290`、`sync-engine.mjs`。
ABI 一改三处同坏。`wasmtime_host.rs:8-11` 模块头已自承"引擎 ABI 升级时最先坏的就是这几处 codec"。

### 33. 引擎产出 SVG 直接进 `innerHTML` **[已验]**

`index.html:1626` `body.innerHTML=sourceSvg`、`:3828` `el.innerHTML=art.svg`，
**无任何转义**。而 `AGENTS.md:279-282` 明确记录节点 id 不做清洗，
`place … 'x"><img src=y onerror=…>'` 会被原样写进 SVG 的 `<g id="n_…">` 并突破属性引号。

前端自己拼的每一处 innerHTML 都走了 `escHtml` / `escAttr`，
**唯独这条最大的没走**。

威胁模型（较初版收窄）：注入需要用户自己文档里出现恶意节点 id，
或用户粘贴的 prompt 诱导 agent 生成。不是远程可利用漏洞，
是自伤 + prompt 注入中介的路径。仍该修（引擎不清洗 id 是外部事实）。

### 34. `undoMbt` / `redoMbt` 近乎逐行重复 **[转述]**

`index.html:1338-1356` ⟷ `:1357-1375`，各 38 行，仅 op 名与文案不同。

### 35. Rust 只有一种 error type **[转述]**

全部命令 `Result<_, String>`，错误码靠 `snake_case` 前缀 + 冒号参数。
`is_transient_llm_error` 直接对错误串做 `starts_with` / `contains` ——
任何重构都会静默改变重试行为。

### 36. 高风险链路的静默失败 **[转述]**

- `lib.rs:482` `let _ = emitter.emit_to(...)` —— `AGENTS.md` 认定的最高风险链路
- `lib.rs:334` `let _ = window.emit("app-close-request", ())` ——
  脏文档关窗变"点关闭没反应"
- `index.html:1228` `syncDirtyRemote().catch(()=>{})` ——
  Rust 侧脏态永不更新，关窗保护静默失效
- `index.html:2341/2369` `event.listen(...).catch(()=>{})` 且
  `TRACE.tried=true` 锁死不再重试 → 实时轨迹永久空白

### 37. 路径参数无规范化 **[转述]**

`open_ddp` / `list_ddp_projects` 的 `path` / `dir` 参数无 `canonicalize`、
无根目录白名单。`list_ddp_projects` 会对调用方指定的任意目录做完整枚举
并把绝对路径回传前端。

### 38. `win.eval` 依赖 `{:?}` 恰为合法 JS 字面量 **[转述]**

`lib.rs:372-375`。当前 id 全 ASCII kebab-case 故安全，
但约束在**测试正则**（`test_studio.cjs:104`）里而非类型里。

---

## 已撤回 / 误报

| 初版结论 | 判定 | 依据 |
|---|---|---|
| "preview 后 `flows` 与 `studioFlows` 语义分叉" | **误报** | `index.html:1503` 的 `studioFlows=flows.slice()` 在 `if(!preview)` **之外**，preview 时只是重复拷贝同样的 `flows`，两者恒等 |
| "`save_ddp` 用户取消导致误标已保存" | **误报** | `index.html:3352` 只在 `filePath` 非空时进入，`picked` 必为 `Some`，不会返回 `Null` |
| "上下文窗口 64K 误判" | **降级为低** | 命中时返回快照真值；缺陷仅在快照外模型回落 128K |
| "`paintPreview` 整份替换项目状态导致丢更新" | **降级为中** | `!preview` 守卫使 preview 不写 `mbtText` / 不置脏 / 不进撤销栈 / 不动 `decl.value`。真实问题是显示失步 |
| "引擎 SVG innerHTML = 高危漏洞" | **降级为中** | 需用户文档含恶意 id，非远程可利用 |

---

## 未验证项（已裁决，见文首核查记录：A 收窄成立、B/C 成立）

以下三条只有行号引用，未亲自打开：

- `list-ops` 缺席 inspection 清单（`agent.rs:145-148`）
- `sync-engine.mjs:319-321` 的 `ops.length >= 25` 数量下限
- `lib.rs:670-676` 原生菜单「适配窗口」项文案

前两条若成立，是幻觉防线的真实缺口。

---

## 文档漂移（已裁决，见文首核查记录：1/2/3/4 成立、5 撤销）

| 文档说法 | 实际 |
|---|---|
| `product-audit.md:77` "多窗口 = 单窗口模型，本期范围外" | 已实现（`lib.rs:232`），且因 P0-2 半残 |
| `product-audit.md` 命令矩阵 9 条 | 实际 11 条（多 `rebase_agent_ops`、`open_project_window`） |
| `AGENTS.md:11` 同上 | 同上 |
| `AGENTS.md:264` "session_query_nodes 已带 parent，图层树层级可重建" | `:1806-1815` 仍渲染扁平清单，未接线 |
| `AGENTS.md:212-217` CLARIFY-FIRST 数据流 | 契约层从未接通（见 P1-6） |

> 行数 / 测试条数一类的偶发数字漂移按惯例不登记。
