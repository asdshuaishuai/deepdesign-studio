// ArkTS 侧 Invoker：分发 + 控制器回投
import { webview } from '@kit.ArkWeb';
import { CommandDispatch } from './Dispatch';
import { coreVersion, corePing } from '../core/CoreBridge';

export class Invoker {
  private dispatch: CommandDispatch;
  private controller: webview.WebviewController | null = null;
  private eventListeners: Map<string, string> = new Map(); // event -> callbackId
  // 宿主（Index.ets/EntryAbility）注册的窗口控制处理器：min/max/close/move
  winHandler: ((action: string) => void) | null = null;
  // 原生输入处理器（web 输入元素被点中 → Index 弹原生浮层）
  nativeInputHandler: ((x: number, y: number, current: string) => void) | null = null;

  constructor(dispatch: CommandDispatch) {
    this.dispatch = dispatch;
  }

  attachController(c: webview.WebviewController): void {
    this.controller = c;
  }

  invokeAsync(rid: string, cmd: string, argsJson: string): void {
    let args: Record<string, Object> = {};
    try { args = argsJson ? JSON.parse(argsJson) as Record<string, Object> : {}; } catch (e) { args = {}; }

    // NAPI core 本地命令（同步直通）
    try {
      if (cmd === '__core_version') {
        this.resolveBack(rid, true, JSON.stringify(coreVersion()));
        return;
      }
      if (cmd === '__core_ping') {
        this.resolveBack(rid, true, JSON.stringify(corePing(String(args['payload'] ?? ''))));
        return;
      }
    } catch (e) {
      this.resolveBack(rid, false, JSON.stringify({ ok: false, error: `napi: ${(e as Error).message}` }));
      return;
    }

    this.dispatch.dispatch(cmd, args).then((v: Object | null) => {
      this.resolveBack(rid, true, v === null ? 'null' : JSON.stringify(v));
    }).catch((e: Error) => {
      this.resolveBack(rid, false, JSON.stringify({ ok: false, error: e.message }));
    });
  }

  // 前端 winctl：窗口控制转发（Bridge.win → 这里 → 宿主注册的 handler）
  win(action: string): void {
    if (this.winHandler) {
      this.winHandler(action);
    }
  }

  onEvent(event: string, callbackId: string): void {
    this.eventListeners.set(event, callbackId);
  }

  nativeInput(x: number, y: number, current: string): void {
    if (this.nativeInputHandler) {
      this.nativeInputHandler(x, y, current);
    }
  }

  private resolveBack(rid: string, ok: boolean, json: string): void {
    if (!this.controller) return;
    const safe = json.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, '\\n');
    this.controller.runJavaScript(
      `window.__harmony.resolve('${rid}', ${ok}, '${safe}')`).catch(() => {});
  }
}
