# 产品完备性与连通性审查

审查时间：2026-09-24（分支 fix/restore-purged-interaction-layer，提交 08a85a7 之后）。
方法：逐表面清点（Tauri 命令 / 原生菜单 / 前端菜单与面板 / Agent 工具面），
每个条目标注状态并以代码为证。三档状态：

- **闭环**：入口 → 命令/引擎 → 反馈全链路可用，且有测试或结构性防线锚定。
- **诚实降级**：功能缺失但有明确提示文案，不假装可用。
- **待设计**：依赖上游/架构决策，明确不做静默绕过。

## 1. Tauri 命令 ⇄ 消费者矩阵（Rust lib.rs ⇄ frontend/index.html）

| 命令 | 用途 | 前端消费点 | 状态 |
|------|------|-----------|------|
| `invoke_fx_sdk` | agent run / list_models 透传 | askFxSdk / fetchFxModels | 闭环（4 mock e2e + camping e2e 门控） |
| `save_ddp` | 加密保存（支持 path 原地回写） | saveProject / exportDdpNow | 闭环 |
| `open_ddp` | 解密打开（支持 path 免对话框） | openProject（含 recents 切换） | 闭环（P1 接线） |
| `list_ddp_projects` | 目录扫描 .ddp 元数据 | refreshRecents（磁盘对账） | 闭环（P1 接线，此前零消费者） |
| `save_text_file` | HTML 原型 / SVG 落盘 | exportHtmlProto / exportSvg | 闭环 |
| `confirm_discard` | 脏文档原生确认 | 打开/新建/退出/关窗 4 处守卫 | 闭环 |
| `set_project_dirty` | 关窗拦截的 Rust 侧镜像 | 3 处 | 闭环 |
| `app_exit` | 自定义退出 | quitApp | 闭环 |
| `model_registry` | models.dev 快照下发 | loadModelRegistry | 闭环（5 快照契约测试） |

## 2. 菜单连通性

- **原生菜单（macOS，lib.rs）**：21 个 `MenuItem::with_id` 全部被
  `nativeMenuAction` 映射（test_studio 检查 D 锚定；映射体调用目标存在性由
  检查 G 锚定——P3 新增）。含 `open-recent`（P1 新增）。
- **前端文件菜单（fmenu-pop）**：13 项，`fmAct('name')` 字符串分发；
  目标必须是顶层 function 声明（检查 G，P3 新增——此前是 9f48220 同构盲区）。
  含最近项目动态区（P1 新增）。
- **右键菜单族**（nodeMenu/canvasMenu/artboardMenu/declMenu）：闭环。
- 文档：docs/menus.md 与 lib.rs/前端同步（本次已更新 open-recent 行）。

## 3. 项目生命周期（P1 后）

| 流程 | 状态 |
|------|------|
| 新建（⌘N）→ 模板/空白/Agent 起步 | 闭环；状态归零含残留复活通道（nodes/studioFlows/declDraftDirty） |
| 打开（⌘O：先密码后对话框 / recents：免对话框先试后问） | 闭环 |
| 最近项目（localStorage 注册表 + list_ddp_projects 磁盘对账） | 闭环；欢迎面板 + 文件菜单双呈现位 |
| 保存（⌘S 原地回写）/ 导出（纯副本，不改绑保存目标） | 闭环；P1 修复导出劫持 ⌘S 的错文件事故源 |
| 标题同步（#proj-name / document.title / 原生窗口标题） | 闭环（P1；capabilities 增 set-title 单权限） |
| 脏态守卫（打开/新建/退出/关窗） | 闭环 |
| 会话口令（单槽 + per-path 映射，均不持久化明文） | 闭环 |
| 启动自动执行 | **仅** dd-dev-autorun 开关门（一次性用后即焚）；无条件 autorun 残留已删（P0），检查 F 锚定 |

## 4. Agent 工具面（agent.rs）

| 工具 | 状态 |
|------|------|
| `moonviz_op`（变更经 AgentGate + 只读经 session API 路由） | 闭环；READONLY_OPS 表 22 项（0.1.6 增 `extract-design-system`） |
| `read_mbt` | 闭环；L0 整形（剥 check 围栏，ids 全保留，真机 e2e 锚定） |
| `list_components` | 闭环（components.json 快照） |
| `extract-design-system <ab>`（0.1.6 新增） | 闭环；颜色/尺寸 token 用量+置信度，e2e 锚定 |
| place 最终尺寸语法（0.1.6/#18） | 闭环；`[w] [h]` 位置参数 + 门评估最终 bbox，提示词已教，测试锚定 |
| `constrain`（0.1.6/#17） | **待上游**：意图词表已文档化，但成功信封不回传 canonical（键控宿主取不回变更，[#19](https://github.com/asdshuaishuai/moonviz/issues/19) 未修）；提示词引导用 align/update/place[w h] |
| `list-tools` / `doc-json`（op 形态） | **诚实降级**：`wasm_engine_export_unavailable`（无 wasm 导出，提示词同步禁用） |
| 上下文管理 | L0/L1/L2 三层（docs/agent-context.md），L2 预算逐模型窗口（models.json limit.context）；测试锚定 |

## 5. 诚实降级项（保持现状，有明确文案）

| 项 | 降级形态 | 依据 |
|----|---------|------|
| 用户组件三入口（saveAsComponent/exportMcf/importMcf/deleteUserComponent） | `USERCOMP_UNAVAILABLE` toast | 引擎 session 注册表只存活会话内，持久化模型（全局注册表 vs 文档嵌入）待上游决策 |
| `list-tools` / `doc-json` | 诚实报错 | 无对应 wasm 导出 |
| 快照不可用时的模型面板 | 降级手输 | models.json 快照 + MiniMax 静态清单兜底 |

## 6. 待设计项（明确不做静默绕过）

| 项 | 边界 | 备注 |
|----|------|------|
| Agent 在飞时切换/新建/撤销 | 硬拦截 + toast | 丢更新风险；rebase/合并机制属设计决策（AGENTS.md 已登记） |
| 切换项目重置撤销栈 | 引擎 history 按画板分栈、宿主边界 | 多板全局线性撤销待上游 history 持久化方向 |
| 多窗口/并排项目 | 单窗口模型 | 本期范围外；多项目 = 换文档 |
| 跨 run 对话记忆 | 每次 run 全新 payload | ChatGPT 式连续对话是演进方向（Rust 侧历史 + 对话视图） |
| apiKey 明文 localStorage | 桌面单用户常见做法 | OS keychain 属增强项，未排期 |

## 7. 本轮修复清单（对照审查发现）

1. **[P0]** 无条件露营 autorun 残留（每次启动跑真实 LLM run）→ 删除 + 检查 F 静态守卫（变异验证）。
2. **[P1]** `list_ddp_projects` / `open_ddp path` 零消费者 → recents 注册表 + 免对话框切换接线。
3. **[P1]** 导出 DDP 静默改绑 `filePath`（此后 ⌘S 写错文件）→ 仅首次落盘才接管。
4. **[P1]** 打开 DDP 不更新 `#proj-name`、窗口标题静态 → 三处同步。
5. **[P2]** async-openai 裸依赖零使用（虚报 foundation）→ types-only 真接线 + wire 契约测试。
6. **[P3]** renderGeneration 死存储（作废机制半成品）→ renderStage 转纯同步。
7. **[P3]** `model_reasoning_options` 零调用、e2e 死变量、空 bin/ 目录、系统提示词重复段 → 清理。
8. **[P3]** fmAct/nativeMenuAction 字符串分发目标无锚 → 检查 G（变异验证）。
9. **[P4]** 工具结果零截断（check 围栏 ~48% 冗余、export 全文入历史）→ 三层裁剪 + 设计文档。
10. **[引擎 v0.1.6]** place 不接受 w/h（真实 run 111 次拒绝根因，#18）→ 升级引擎 + 提示词教最终尺寸语法 + 门语义测试锚定。
11. **[引擎 v0.1.6]** 设计系统提取不可达 → `extract-design-system` 接入只读路由（session_extract_design_system）。
12. **[本轮]** L2 预算固定 128K → 逐模型窗口（models.json `limit.context`，16K 下限）；camping e2e 断言从"文档非空"强化为结构断言（≥4 板、主色落盘、引擎校验通过）。

## 8. 结构性防线台账（test_studio.cjs）

| 检查 | 防什么 | 引入背景 |
|------|--------|---------|
| A 内联处理器引用 | 删函数 → ReferenceError | 9f48220 事故 |
| B INTERACTIVE_SURFACE（39 项） | 交互层入口被误删 | 9f48220 事故 |
| C stub 掩盖 | 测试替身顶替真身 | 9f48220 事故（当时恰好 stub 了 3 个被删函数） |
| D 原生菜单 id 映射 | typeof 守卫下静默变哑 | 9f48220 事故 |
| E 引擎写路径符号 | engWriteStr 残留 / _in 槽缺失 | engine-v0.1.2 迁移 |
| F 启动自动执行守卫 | 无条件 setTimeout autorun 残留 | 露营 e2e 残留（P0，变异验证） |
| G 字符串分发目标存在性 | fmAct/菜单映射目标缺失 | 9f48220 同构盲区（P3，变异验证） |
| 动态状态机切片 | 队列/种子/选区/draft/opacity | 基线 |
| wasm 真机契约 | 导出面/模板双向/组件快照 | 引擎同步 |
