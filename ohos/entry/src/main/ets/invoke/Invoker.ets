// ArkTS 侧 Invoker：分发 + 控制器回投
import { CommandDispatch } from './Dispatch';

export class Invoker {
  private dispatch: CommandDispatch;
  private controller: webviewController.WebviewController | null = null;

  constructor(dispatch: CommandDispatch) {
    this.dispatch = dispatch;
  }

  attachController(c: webviewController.WebviewController): void {
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

  private resolveBack(rid: string, ok: boolean, json: string): void {
    if (!this.controller) return;
    const safe = json.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, '\\n');
    this.controller.runJavaScript(
      `window.__harmony.resolve('${rid}', ${ok}, '${safe}')`).catch(() => {});
  }
}

