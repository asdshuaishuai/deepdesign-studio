// Agent 喂回工作线程封装（M3.6.7）：agent_feed_llm 同步 NAPI 经 TaskPool 跑在
// 工作线程——批量轮几十个引擎 op 不上 UI 线程（ANR 根因修复）。
// @Concurrent 限制：函数须模块级、仅依赖模块级导入（native .so 函数受支持）。

import { taskpool } from '@kit.ArkTS';
import { agentFeedLlm } from 'libdeepdesign_core.so';

/** 喂回执行体（TaskPool 工作线程）：同步 NAPI agent_feed_llm，返回下一动作 JSON。
 * 引擎报错已在 Rust 侧折进返回 JSON（{"action":"error","error":..}），此处不抛。 */
@Concurrent
function agentFeedConcurrent(messageJson: string): string {
  return agentFeedLlm(messageJson);
}

/** UI 线程入口：TaskPool 执行喂回，返回下一动作 JSON。TaskPool 不可用/失败时
 * 诚实抛错（调用方降级），不静默回退 UI 线程同步执行（宁可失败不 ANR）。 */
export function agentFeedOnWorker(messageJson: string): Promise<string> {
  const task: taskpool.Task = new taskpool.Task(agentFeedConcurrent, messageJson);
  return taskpool.execute(task) as Promise<string>;
}
