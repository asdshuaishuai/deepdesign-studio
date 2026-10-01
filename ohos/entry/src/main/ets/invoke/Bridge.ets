// ArkTS 桥：javaScriptProxy 暴露给 WebView 的对象（invokeAsync/win/onEvent）
// 持有分发器与 WebviewController（回投句柄由 Index.ets 注入）。
import { CommandDispatch } from './Dispatch';
import { Invoker } from './Invoker';

class HarmonyBridgeImpl {
  private invoker: Invoker;
  private controller: webviewController.WebviewController | null = null;

  constructor() {
    this.invoker = new Invoker(new CommandDispatch());
  }

  attachController(c: webviewController.WebviewController): void {
    this.controller = c;
    this.invoker.attachController(c);
  }

  invokeAsync(rid: string, cmd: string, argsJson: string): void {
    this.invoker.invokeAsync(rid, cmd, argsJson);
  }

  win(action: string): void {
    // 窗口控制转发给宿主 Ability（Index.ets 的 winCtl 等价）
    this.invoker.win(action);
  }

  onEvent(event: string, callbackId: string): string {
    this.invoker.onEvent(event, callbackId);
    return JSON.stringify({ ok: true });
  }
}

export const harmonyBridge = new HarmonyBridgeImpl();
