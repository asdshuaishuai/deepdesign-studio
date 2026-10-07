// deepDesign core NAPI 类型声明（rust-core/deepdesign_core 的 #[napi] 导出）
// 注意：napi-ohos 默认按 camelCase 导出（core_version -> coreVersion）
export const coreVersion: () => string;
export const corePing: (payload: string) => string;
// DDP 认证加密容器（与桌面版 .ddp 互通；空密码 = DDP2 无密码模式）
export const ddpEncrypt: (mbt: string, password: string) => string;
export const ddpDecrypt: (ddpB64: string, password: string) => string;
// 引擎宿主（gap-global-3 接线）：wasmtime 进程内承载 moonviz classic wasm。
// 信封统一 String（JSON）回传；Err 仅传输层失败（b64/编解码/wasm 编译/实例化/超时），
// ok:false 的门拒绝是合法业务信封（正常返回透传），调用方按信封 ok 字段判定。
// 同步 NAPI：首次调用含 wasm 编译（秒级），调用方须延时到首帧后。
export const engineVersion: () => string;
export const engineListOps: () => string;
export const engineApplyHumanOp: (docB64: string, op: string) => string;
export const engineApplyAgentOp: (docB64: string, op: string) => string;
export const engineRender: (docB64: string) => string;
// 会话历史（M3）：sub ∈ init|commit|log|undo|redo|checkout|diff（arg 槽 `<sub> [artboard]`）。
// apply 不自动入史须显式 commit；undo/redo 信封带 canonical（mbt/mbt_b64）。
export const engineHistory: (docB64: string, sub: string) => string;

/** Agent 会话启动（M3.6.7）：建会话返回首动作 JSON（{"action":"llm","messages",...}）。 */
export function agentStart(instruction: string, docB64: string): string;
/** Agent 喂回 LLM 响应（同步 NAPI；工作线程执行由 ArkTS TaskPool 承担）：返回下一动作 JSON。 */
export function agentFeedLlm(messageJson: string): string;
