# Agent 终态 Rebase（run 中人类编辑不再丢失）

状态：**已决策（方案 C），待上游 [#19](https://github.com/asdshuaishuai/moonviz/issues/19)
落地后实施**（引擎升级中，2026-09）。本文档是决策记录 + 实施清单——#19 发布后按清单直接开工，不再重新评估。

## 问题

agent run 以请求起点的 `mbtText` 快照驱动（`EngineState` 每请求重建），run 结束后终态文档
**整体回灌**画布——秒级窗口内人类提交的画布 op 会被静默覆盖。
现行交互缓解：在飞门（agentBusy）拦截并发 run 与 run 中的新建/打开；画布编辑虽允许但建议等 run 结束。

## 事实基础（2026-09 实测，勿凭印象重推）

- 宿主会话缓存**内容寻址、进程级存活**（`wasmtime_host.rs` 的 `static ENGINE`），不是每请求重建：
  - run 内：变更 op 成功后缓存键前移到新 canonical（`SESSION_MUTATING`），run 内第 2 个 op 起
    全部命中——实测 0.37ms/op vs 无状态 2.62ms/op（7.1×）；
  - 跨 run：文档未变则首次调用命中暖会话；重解析只在文档真变过时发生（任何架构下不可避免）。
- run 的 op 流全程有记录：`state.ops`（返回契约）、agent-event、JSONL journal——重放原料现成。
  注意 `state.ops` **混有只读 op**（readonly 路由也 push），重放前须经 `is_readonly_op` 过滤。
- 引擎 session 面其余闲置状态：`session_history`（前端已自开常驻 history 会话给人类撤销）、
  `session_save`（回 project JSON **非** canonical，不能当事实源通道）、会话内组件注册表
  （USERCOMP 持久化未决）。

## 路线评估与决策

| 路线 | 决策 | 理由 |
|------|------|------|
| A. 全部写收敛到宿主常驻会话（真·单写者） | **否** | 人类画布 op 必须留 WebView 同步渲染（会话信封不带 render，迁移反而每 op 多一次 `render_mbt` 往返——AGENTS.md 画布边界）；不走宿主则宿主"活文档"必与前端漂移 |
| B. op 流复制（前端转发人类 op，宿主成活镜像，agent 在活文档上跑） | **缓** | 根治丢更新 + 免重解析，但每画布 op 加 Rust 转发链、op 顺序/分叉/恢复语义——为一类秒级窗口竞态上复制状态机，投入产出不称 |
| **C. 快照起点 + 终态 rebase** | **采纳** | 关闭缺口的最小充分改动；重放原料（ops[]）现成；会话复用使重放 0.37ms/op；同步点天然在 serializeProject 队列；零新引擎能力依赖（仅依赖 #19 的信封契约） |

**明确不做**：用引擎 history 给 agent run 做撤销（与前端 history 会话双头记账；上游按画板分栈
语义未收敛）；把 `session_save` 当 canonical 回读通道。

## 方案 C 设计

数据流（run 终态应用时）：

```
agent run 返回 {mbt_b64, ops[], stopReason, …}
  └► 前端（serializeProject 队列内）比对：run 起点 mbtText vs 当前 mbtText
      ├─ 相同（绝大多数）→ 现有快路径，整体回灌（零改动）
      └─ 不同 → invoke('rebase_agent_ops', { latestMbtB64, opsB64 })
            └► 宿主：以最新 canonical 开新会话，逐条 session_apply_agent 重放变更 ops
                 ├─ op 通过 → canonical 链前移（#19 信封）
                 └─ op 被门拒绝 / id 冲突 → 跳过并记录（宁缺勿债，绝不留 gate debt）
            ◄─ {ok, mbt_b64, applied[], skipped:[{op, error}]}
  └► 前端应用 rebased 文档；skipped 非空 → toast + 轨迹报告「N 条 op 因人类编辑失效已跳过」
```

策略规则（显式，实施照此）：
1. **拒绝即跳过**：op 在新基底上合法失效（如人类挪动导致 overlap）不是错误，跳过 + 报告；
2. **顺序重放**：严格按 run 内执行序（ops[] 已有序）；
3. **只重放变更 op**：`is_readonly_op` 过滤（read_mbt/list_components 工具与只读 moonviz_op
   均无副作用，不入重放流）；
4. **失败兜底**：rebase 服务整体异常 → 回退现行为（应用 run 终态文档）+ 诚实警告，不静默。

前置条件：
- **#19**（引擎升级中）：所有变更类信封带 canonical——键控世界（含 rebase 重放）的硬前提；
- 附带回收：#19 所在引擎版本发布后，按实施清单一并接 constrain（此前挂起项）。

落地后行为变化：run 中画布编辑从「允许但会被覆盖（建议等待）」变为「安全——终态 rebase 保留
人类编辑」；**run 中新建/打开的 agentBusy 拦截保留**（整文档替换/切换问题，超出 rebase 范围）。

## 实施清单（#19 发布后）

1. `scripts/sync-engine.mjs` 锚点升级 → 契约探针 → 双侧测试绿；
2. `wasmtime_host.rs`：`session_constrain`/`session_auto_fix` 从 `SESSION_EVICT` 改为信封
   canonical 键前移（`engine-host.mjs` 调试工具同步——两边语义必须一致，改漏会让调试工具
   给出与生产宿主不同的答案）；
3. `agent.rs`：constrain 变更分支特判路由（**不进 READONLY_OPS**）+ INSTRUCTIONS 教 14 种
   意图词表（同步 `prompt_avoids_apply_rejected_ops` 断言）+ 真机门测试；
4. rebase：新 Tauri 命令 `rebase_agent_ops`（latest canonical b64 + ops[]）+ 前端终态比对/调用
   + skipped 呈现；mock e2e：模拟 run 中文档前进 → 断言变更 ops 重放到新基底、失效 op 跳过并报告；
5. 文档回收：本文件状态改「已实施」、AGENTS.md 已知缺口条目关闭、`docs/product-audit.md`
   待设计项更新。

## 测试锚（实施时新增）

- 重放保序与跳过：新基底上合法 op 全应用、失效 op 跳过且 skipped 带引擎错误原文；
- 快路径零回归：文档未变时不触发 rebase；
- 只读 op 过滤：ops[] 里的 lint/query 等不进重放流；
- 整体失败兜底：rebase 服务异常时回退现行为 + 警告；
- constrain 键前移：调用后同 canonical 会话命中（session_cache_stats 断言，EVICT 移除后必变）。
