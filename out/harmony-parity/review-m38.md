# 鸿蒙审查第二轮（review-m38，2026-10-06，基准 f868d7e → 修复后）

范围：M3.6.2 以来全部新增面（Rust agent 状态机/TaskPool/会话泵/消毒层/docFlush 回灌）
+ review-m37 遗留 16 项复核。方法：4 路并行深审 + 主代理逐条实证。

## 新发现（本轮修复 ✅ 的）

| # | 级 | 发现 | 根因 | 修复 |
|---|----|------|------|------|
| 1 | **P0** | **tools 第 2 轮起全空——loop 第 1 轮后即死**（模型无工具可调，只剩文本） | agent_feed 的 llm 信封不带 tools；泵每轮从当前信封重读 `sess['tools'] ?? []` → 24 轮全空数组 | Rust 三处 llm 信封回带 `tools_json()`（Rust 权威） |
| 2 | **P1** | **思考方言表是死代码**——reasoning_effort/thinking/chat_template_kwargs 被 invokeFx body 白名单丢弃，恒思考模型稳定性支柱失效（batch-3 欠账的隐藏层） | Dispatch 白名单重建 body | 白名单外键全透传 |
| 3 | **P1** | 泵 done 分支意图兜底无澄清守卫——模型澄清问句被 matchTpl 成模板落板 + 澄清面板永不出现 | reviewExec 直接吃 reply | isClarify 原样交还触发 pending |
| 4 | **P1** | docFlush 不更新 lastCanonicalB64——hifi SVG 渲染 run 前文档 + ⌘Z 锚点中毒（一轮 ⌘Z 丢整个 run 产出） | 回灌闭包漏锚点 | `this.lastCanonicalB64 = docB64` |
| 5 | **P1** | 「run 起点单次撤销快照」从未落地（注释声称有，grep 无）——run 不可撤销 | M3.6.7 重写时丢失 | runAgent 非 followup 起点恢复 pushUndoExternal |
| 6 | **P1** | 工具结果 JSON 手拼 format!——`text="..."` 引号 op 打穿 JSON 结构 | 未用 serde_json | json! 序列化；顺修 `join("\\n")` 字面反斜杠 bug |
| 7 | **P1** | AGENT_SESS 毒锁无恢复——一次 panic 全会话期 agent 不可用 | map_err 致命化 | into_inner 恢复（engine.rs 先例） |
| 8 | **P2** | agent_start 失败信封被忽略 → 空 messages 打 HTTP，根因被供应商错误掩盖 | 未查 st['error'] | （本轮登记，随 #1 tools 修复后 session 必有 json；后续补显式检查） |
| 9 | **P2** | done 信封 events 不渲染（预算耗尽标记/澄清标记丢轨迹） | done 分支提前 return | 事件渲染上移至 action 判定前 |
| 10 | **P2** | 预算可吞审查报告（轮 23 注入 → 修复轮撞 24 上限） | 无 REVIEW_STEPS 预留 | 审查注入时预留 3 轮（桌面同语义） |
| 11 | **P2** | 截断轮不进轮预算（+空回复轮）→ 64 泵 guard 才收敛 | rounds 仅工具轮递增 | 登记（泵 guard 兜底，可接受） |

## 实证修复效果（StepFun 实跑同一需求）
- wire 诊断：审查注入请求消息完整（assistant+user:216 审查提示），400 消失
- 审查轮经 Rust 会话完整执行（13004ms）
- 2 画板落布、✅ 运行完成 · 2 ops、无 ANR

## review-m37 遗留复核
- FIXED：R3（uninstall）、R13（.catch）、R12-主路径（chat 状态码）、R5-部分（initd 门控+println）
- STILL OPEN：R1（锚点跨项目——本轮 #4 修复了 loop 内锚点推进，跨项目重置仍开）、R4（flows 双计）、R6（UDID）、R8/R9（histTouch 记账——新 raw 路径 :2086 复刻同病）、R10（rev=0 条件性）、R11、R14、R15、R16 全部子项
- R2 确认未变（hist NAPI 仍未接线）；R7 登记未变

## 新登记（✅ 已全部修复，见 8214f80 后续提交）
- N1 P1 ✅：截断/空回复轮计入轮预算 + 预算耗尽诚实收尾（Rust agent.rs nudge 分支）
- N2 P1 ✅：loopChat 429/5xx 单次 2.5s 退避重试（4xx 参数类不重试）
- N3 P2 ✅：泵 agent_start 失败信封显式检查（先查 error 再 parse json）
- N4 P2 ✅：execEngineOpRawAsync 死代码删除；SH_LOGO 导入移除 + Theme token 退役标注
- 附带：docFlush 回灌前 appStore.docEpoch += 1（R10 缓解——线框活进度每轮强制板卡重建，
  不再依赖 rev/zoom 偶然再键）

## review-m39（2026-10-06，复审后补丁批）——复审抓到「修复未落盘」并全部重落
四路复审发现 8214f80 批次中 tools 回传/毒锁恢复/预算保审查三修因 python 断言中断未写盘
（仅 JSON 转义经 Edit 落盘）——本批重落 + 收尾：
- 重新落地：tools 全轮回传（4 处 llm 信封）/毒锁 into_inner 恢复（3 处）/预算保审查
- 收尾新修：tool-budget done 信封补 events（失败事件丢轨迹）；泵事件渲染上移至
  error throw 前（error 信封事件进轨迹）；partialOps 计数——loop 中断且已有产出时
  不再重复执行兜底链（防模板重复落板）；消毒器空 tool_calls 数组视同无工具
  （部分供应商 400）；session_stats 毒锁恢复；游离测试归位 mod tests
- 契约测试 11/11 绿；e2e：11 ops · 4 画板交付，错误回喂→read_mbt→真 id 重试
  自纠错闭环实证，无 ANR
