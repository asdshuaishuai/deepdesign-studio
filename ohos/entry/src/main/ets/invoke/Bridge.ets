// ArkTS 桥：javaScriptProxy 暴露给 WebView 的对象（invokeAsync/win/onEvent）
// 持有分发器与 WebviewController（回投句柄由 Index.ets 注入）。
import { webview } from '@kit.ArkWeb';
import { CommandDispatch } from './Dispatch';
import { Invoker } from './Invoker';

class HarmonyBridgeImpl {
  private invoker: Invoker;
  private controller: webview.WebviewController | null = null;

  constructor() {
    this.invoker = new Invoker(new CommandDispatch());
  }

  attachController(c: webview.WebviewController): void {
    this.controller = c;
    this.invoker.attachController(c);
  }

  // 宿主注册窗口控制（min/max/close/move → 原生 window API）
  setWinHandler(h: (action: string) => void): void {
    this.invoker.winHandler = h;
  }

  // 宿主注册原生输入处理器（web 输入元素被点中 → 原生浮层接替，规避 web IME 挂起）
  setNativeInputHandler(h: (x: number, y: number, current: string) => void): void {
    this.invoker.nativeInputHandler = h;
  }

  invokeAsync(rid: string, cmd: string, argsJson: string): void {
    this.invoker.invokeAsync(rid, cmd, argsJson);
  }

  win(action: string): void {
    this.invoker.win(action);
  }

  nativeInput(x: number, y: number, current: string): void {
    this.invoker.nativeInput(x, y, current);
  }

  onEvent(event: string, callbackId: string): string {
    this.invoker.onEvent(event, callbackId);
    return JSON.stringify({ ok: true });
  }
}

export const harmonyBridge = new HarmonyBridgeImpl();
