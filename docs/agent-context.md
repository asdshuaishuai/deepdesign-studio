# Agent 上下文管理（分层裁剪）

状态：**已实施**（L0/L1/L2 三层确定性裁剪，`agent.rs`，2026-09）。设计取舍与边界记录在案。

## 问题（实施前的实测基线）

- 历史全链路零截断：assistant/tool 消息原文入历史，每轮全量重发，MAX_STEPS=200。
- `read_mbt` 回**全量 canonical**。canonical 中**每个画板**有一对围栏块：
  ` ```mbt `（视觉声明）+ ` ```mbt check `（测试块）——check 块把该画板每个
  `page.add(@decl.generic_node(...))` **逐字重复第二遍**，仅多两行 assert。
  真机实测（template login + 种子板）：canonical 9102B 中 check 围栏合计占比随节点数
  上升至 ~40-50%（探索报告对 login+4 place 的文档实测 48.1%）。
- `export-svg` / `export-html` 的整段 SVG/HTML 全文入历史（LLM 不消费渲染体）。
- 提示词要求 create 后 read、VERIFY 步再 read——多屏任务每轮把 canonical 重新塞进
  历史，token 成本随步数超线性。

## 三层裁剪（全部确定性、可单测；无 LLM 摘要调用）

### L0 源头整形（结果产生时）

| 对象 | 策略 | 理由 |
|------|------|------|
| `read_mbt` | 剥除所有 ` ```mbt check ` 围栏块，附 note 说明 | check 是引擎对声明的逐字重复（真机对照实证），剥除零信息损失；ids/属性全在视觉声明块 |
| `export-svg` / `export-html` | 只回信封 `{ok,op,bytes,head≤400}` | 渲染体对后续设计决策零信息量 |
| 其余检视 op（lint/critique/spec/query/…） | >12KB 头尾截断（`[truncated N of M bytes]` 标记） | 保反馈全文的同时设上限 |
| 失败信封（ok:false） | **原样放行不截** | 错误详情是模型自纠的输入 |

硬边界：**前端终态（`mbt_b64`）仍交付完整 canonical**——整形只发生在 LLM 侧工具结果。

### L1 去supersede（每次请求前）

同类工具（`read_mbt` / `list_components`）出现新结果后，旧结果的 tool 消息内容替换为
占位 `[superseded by a later read_mbt result — …]`。中间过程值对后续轮次无信息量。

### L2 预算守卫（每次请求前）

- 估算：消息序列化字节数（utf-8 字节/3 ≈ tokens，CJK 精确、英文高估即保守）。
- 预算：128K tokens 固定保守值；超 70% 触发激进裁剪——最近 6 条 tool 结果之外的
  tool 内容全部占位化（`[elided: stale tool output beyond context budget]`）。
- 触发时发一次 `context_usage` 轨迹事件（est_tokens/budget_tokens/elided_bytes）+
  stderr `[agent] context budget` 行。

### 通用硬约束

**只缩 tool 消息的 content，绝不删消息**——OpenAI wire 要求每个 `tool_call_id` 都有
配对的 tool 消息，删消息 = 协议错误。收缩只发生在**请求侧副本**上；`messages` 本体
完整保留（轨迹/journal/排障用）。

## 明确不做（演进方向）

- **LLM 摘要压缩**（把被裁剪的历史摘要成 digest 消息）：成本与复杂度换不来
  确定性收益，L1+L2 已覆盖线性膨胀的主项。
- **逐模型上下文窗口**：models.json 有 per-model context 长度，贯通前端 →
  run() 参数 → Rust 预算是接线工作，当前固定保守值先行。
- Anthropic 侧 `to_anthropic_messages` 不裁剪：L1/L2 在其上游生效（收缩后的
  request_messages 才进协议转换）。

## 测试锚

`strip_mbt_check_blocks_preserves_ids`（fixture 照真机结构）·
`shape_readonly_result_envelope_and_cap` · `supersede_keeps_latest_and_pairing` ·
`elide_keeps_recent_tool_contents` · `agent_loop_read_mbt_shaping_keeps_ids`
（真机 e2e：第二轮请求含节点 id 且不含 check 围栏）。
