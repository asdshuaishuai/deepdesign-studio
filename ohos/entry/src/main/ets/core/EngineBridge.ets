// 引擎宿主桥（gap-global-3 接线，M1）—— rust-core engine 模块的 NAPI camelCase 导出消费层
//
// 独立模块 + 调用点优雅降级（形态对齐 ai/LocalChatBridge.ets 的「独立模块 + 失败诚实
// 回报」）：engine 导出随 libdeepdesign_core.so 分发，但**存量 so 可能没有这批导出**
// （旧产物，NAPI 导出表缺项不会让模块加载失败、调用时才 TypeError）——因此每个调用点
// 先 typeof 收窄导出在场，再 try-catch 包住传输层 Err。任何失败都以 reason/error
// 诚实回报，调用方（Dispatch → Index）据此降级到本地路径，不假装引擎在场。
//
// 信封分层（与 rust-core/src/lib.rs 引擎导出注释同构）：
//   - Err（NAPI throw）= 传输层失败（wasm 编译/实例化/超时/b64 损坏）→ catch 成 reason；
//   - 信封 ok:false = 门拒绝（合法业务响应）→ 原样透传给消费方判定，不在本层吞掉。

import core from 'libdeepdesign_core.so';

/** 引擎状态（probeEngine 产物）：available=false 时 reason 即降级原因（状态行保持现状
 * 文案 + console.error 消费）。tag 为引擎可用时状态行文案。 */
export interface EngineStatus {
  available: boolean;
  tag: string;      // engine: <engine> wasm, host: wasmtime
  version: string;  // 引擎信封 version 字段（不可用为空串）
  reason: string;   // 不可用原因（可用为空串）
}

/** apply op 回执：ok=传输层成功（NAPI 未 throw）。envelope 为引擎信封原样 JSON 串——
 * ok:false 的门拒绝也在其中（消费方 parse 后按信封 ok 判定）；error 传输失败原因。 */
export interface EngineApplyResult {
  ok: boolean;
  envelope: string;
  error: string;
}

/** version_info 信封（逐键判型收窄，JSON.parse 产物不保证形状）。 */
interface VersionEnvelope {
  ok?: boolean;
  engine?: string;
  version?: string;
}

/** 引擎导出在場检查（旧 so 防线）：NAPI 模块导出对象缺属性不炸加载，调用时才炸。 */
function engineExportReady(fn: Object): boolean {
  return typeof fn === 'function';
}

/** 真实引擎探针：wasmtime 实例化 + version_info。首呼含 wasm 编译（秒级，同步 NAPI
 * 阻塞 UI 线程——调用方须延时到首帧后；Promise 化归后续批次）。 */
export function probeEngine(): EngineStatus {
  if (!engineExportReady(core.engineVersion)) {
    return {
      available: false, tag: '', version: '',
      reason: 'engine_export_missing:libdeepdesign_core.so 无 engineVersion 导出（so 陈旧，需重编 rust-core 并替换 rust-libs）'
    };
  }
  try {
    const j = JSON.parse(core.engineVersion()) as VersionEnvelope;
    if (j.ok !== true || typeof j.engine !== 'string' || j.engine === '') {
      return {
        available: false, tag: '', version: '',
        reason: 'engine_version_bad_envelope:' + JSON.stringify(j)
      };
    }
    return {
      available: true,
      tag: `engine: ${j.engine} wasm, host: wasmtime`,
      version: typeof j.version === 'string' ? j.version : '',
      reason: ''
    };
  } catch (e) {
    return {
      available: false, tag: '', version: '',
      reason: 'engine_version_failed:' + (e as Error).message
    };
  }
}

/** 人类门变更 op（session_apply_human）：canonical b64 文档 + op 行。ok=传输层成功；
 * 门拒绝不在此判定（envelope 内 ok:false 透传）。 */
export function applyHumanOp(docB64: string, op: string): EngineApplyResult {
  if (!engineExportReady(core.engineApplyHumanOp)) {
    return { ok: false, envelope: '', error: 'engine_export_missing:engineApplyHumanOp' };
  }
  try {
    return { ok: true, envelope: core.engineApplyHumanOp(docB64, op), error: '' };
  } catch (e) {
    return { ok: false, envelope: '', error: 'engine_apply_failed:' + (e as Error).message };
  }
}

/** 渲染检视（M3）：canonical b64 → render_mbt 信封（{ok, entry, revision, artboards[]}
 * ——artboard 条目带 id/name/width/height/nodes/svg）。ok=传输层成功。 */
export function renderDoc(docB64: string): EngineApplyResult {
  if (!engineExportReady(core.engineRender)) {
    return { ok: false, envelope: '', error: 'engine_export_missing:engineRender' };
  }
  try {
    return { ok: true, envelope: core.engineRender(docB64), error: '' };
  } catch (e) {
    return { ok: false, envelope: '', error: 'engine_render_failed:' + (e as Error).message };
  }
}

/** 会话历史（M3）：sub ∈ init|commit|log|undo|redo|checkout|diff（按板）。undo/redo
 * 改文档 → envelope 带 canonical（mbt/mbt_b64）。 */
export function historyOp(docB64: string, sub: string): EngineApplyResult {
  if (!engineExportReady(core.engineHistory)) {
    return { ok: false, envelope: '', error: 'engine_export_missing:engineHistory' };
  }
  try {
    return { ok: true, envelope: core.engineHistory(docB64, sub), error: '' };
  } catch (e) {
    return { ok: false, envelope: '', error: 'engine_history_failed:' + (e as Error).message };
  }
}
