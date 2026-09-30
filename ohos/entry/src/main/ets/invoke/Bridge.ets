// Tauri invoke 兼容垫片（L2 门面）
//
// 前端约定（frontend/index.html）：`window.__TAURI__.core.invoke(cmd, args)` 返回
// Promise；本桥以 `harmonyBridge.invoke(cmd, argsJson)` 同语义承接（参数走 JSON 字符串，
// 因 javaScriptProxy 仅支持可序列化字面量）。注册进 WebView 的对象在页面加载前注入，
// 前端垫片（invoke-shim.js，随 rawfile 一并下发）把它挂到 `window.__TAURI__.core`。
//
// L1 core 尚未接入：当前所有命令回 `UNSUPPORTED_ON_OHOS`；deepdesign-core（ohrs 产
// .so）经 import 接入后逐命令替换实现（见 docs/harmonyos-port.md §4 L1）。

interface InvokeResult {
  ok: boolean;
  payload?: string;   // JSON 序列化的返回值
  error?: string;
}

class HarmonyBridge {
  private listeners: Map<string, string> = new Map();

  /**
   * 对应 Tauri invoke(cmd, args)。argsJson 为 JSON 字符串（可为 ''）。
   * 返回 JSON 字符串的 InvokeResult。
   */
  invoke(cmd: string, argsJson: string): string {
    const args: Record<string, Object> = argsJson && argsJson.length > 0
      ? JSON.parse(argsJson) as Record<string, Object> : {};
    console.info(`[bridge] invoke(${cmd})`);
    // TODO(P1): deepdesign-core NAPI 接入后按命令分发；命令清单与
    // src-tauri/lib.rs 的 generate_handler 一致。
    const unsupported: InvokeResult = { ok: false, error: `UNSUPPORTED_ON_OHOS: ${cmd}` };
    return JSON.stringify(unsupported);
  }

  /** 对应 Tauri emit（前端 → 后端事件）。 */
  emitEvent(event: string, payloadJson: string): string {
    console.info(`[bridge] emitEvent(${event})`);
    return JSON.stringify({ ok: true });
  }

  /** 前端垫片订阅后端事件（agent-event 回投等）。L1 接入后由 NAPI 回调驱动。 */
  onEvent(event: string, callbackId: string): string {
    this.listeners.set(event, callbackId);
    return JSON.stringify({ ok: true });
  }

  /** javaScriptProxy 注册入口（Index.ets 使用）。 */
  getProxy(): HarmonyBridge {
    return this;
  }
}

export const bridge = new HarmonyBridge();
