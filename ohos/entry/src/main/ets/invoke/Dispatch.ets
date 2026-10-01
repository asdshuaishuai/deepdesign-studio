// ArkTS 命令分发 —— 前端 invoke → OHOS 原生实现
//
// 实现状态：
//   ✓ set_project_dirty / set_menu_language / confirm_discard / app_exit
//   ✓ save_text_file / model_registry（bundled）
//   ◌ save_ddp / open_ddp / list_ddp_projects —— P1：NAPI core 接入后走
//     Argon2id+XChaCha20（当前返回结构化错误，前端有 catch 显示）
//   ✓ invoke_fx_sdk —— @ohos.net.http 直连 OpenAI 兼容端点（Agent 聊天真实可用）
//   ◌ rebase_agent_ops —— P1
//   ✓ open_project_window —— 单窗口模式：聚焦自身

import { http } from '@kit.NetworkKit';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

interface SaveFileResult {
  savedTo: string;
}

interface FxResult {
  content: string;
  reasoning: string;
  usage: Object | null;
}

interface FxError {
  error: string;
}

export class CommandDispatch {
  private context: common.UIAbilityContext | null = null;
  private dirty: boolean = false;
  private lang: string = 'zh-CN';

  setContext(ctx: common.UIAbilityContext): void {
    this.context = ctx;
  }

  /** 分发入口。返回 Tauri 语义的返回值（将 JSON 序列化后 resolve 给前端）。 */
  dispatch(cmd: string, args: Record<string, Object>): Promise<Object | null> {
    switch (cmd) {
      case 'set_project_dirty':
        this.dirty = (args as Record<string, boolean>)['dirty'] ?? false;
        return Promise.resolve(null);
      case 'set_menu_language':
        this.lang = String((args as Record<string, string>)['lang'] ?? this.lang);
        return Promise.resolve(null);
      case 'confirm_discard':
        return this.confirmDiscard();
      case 'app_exit':
        this.context?.terminateSelf();
        return Promise.resolve(null);
      case 'model_registry':
        return this.loadModelRegistry();
      case 'save_text_file':
        return this.saveTextFile(args);
      case 'invoke_fx_sdk':
        return this.invokeFx(args);
      default:
        return Promise.reject(new Error(`UNAVAILABLE_ON_OHOS: ${cmd}（该能力将在后续版本接入）`));
    }
  }

  private loadModelRegistry(): Promise<Object | null> {
    const ctx = this.context;
    if (!ctx) return Promise.resolve(null);
    return ctx.resourceManager.getRawFileContent('models.json').then((data: Uint8Array) => {
      const dec = util.TextDecoder.create('utf-8');
      return JSON.parse(dec.decodeToString(data)) as Object;
    }).catch((): Object | null => null);
  }

  private confirmDiscard(): Promise<Object | null> {
    return new Promise<Object | null>((resolve) => {
      promptAction.showDialog({
        title: '未保存的更改',
        message: '当前文档有未保存的更改，确定丢弃吗？',
        buttons: [{ text: '继续编辑', color: '#007aff' }, { text: '放弃更改', color: '#e5484d' }]
      }).then((r: promptAction.ShowDialogSuccessResponse): void => resolve(r.index === 1))
        .catch((): void => resolve(false));
    });
  }

  private saveTextFile(args: Record<string, Object>): Promise<Object | null> {
    // args: { name, contentsB64 } → DocumentViewPicker 另存为
    const name = String(args['name'] ?? 'export.txt');
    const b64 = String(args['contentsB64'] ?? '');
    return new Promise<Object | null>((resolve) => {
      const saveOpts = new picker.DocumentSaveOptions();
      saveOpts.newFileNames = [name];
      const docPicker = new picker.DocumentViewPicker();
      docPicker.save(saveOpts).then((uris: Array<string>): void => {
        if (!uris || uris.length === 0 || !uris[0]) { resolve(null); return; }
        const uri = uris[0];
        try {
          const helper = new util.Base64Helper();
          const bin: Uint8Array = helper.decodeSync(b64);
          const f = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
          fs.writeSync(f.fd, bin.buffer as ArrayBuffer);
          fs.closeSync(f);
          const out: SaveFileResult = { savedTo: uri };
          resolve(out);
        } catch (e) {
          resolve(null);
        }
      }).catch((): void => resolve(null));
    });
  }

  /** invoke_fx_sdk：Agent 聊天的云端 LLM 调用（OpenAI 兼容 /v1/chat/completions）。 */
  private invokeFx(args: Record<string, Object>): Promise<Object | null> {
    return new Promise<Object | null>((resolve) => {
      const payload = JSON.parse(String(args['payload'] ?? '{}')) as Record<string, Object>;
      const apiKey = String(args['apiKey'] ?? '');
      let baseUrl = String(payload['baseUrl'] ?? args['baseUrl'] ?? 'https://api.deepseek.com');
      if (!/^https?:\/\//.test(baseUrl)) baseUrl = 'https://' + baseUrl;
      if (baseUrl.endsWith('/')) baseUrl = baseUrl.slice(0, -1);
      const url = baseUrl + '/chat/completions';
      const body = JSON.stringify({
        model: payload['model'] ?? '',
        messages: payload['messages'] ?? [],
        stream: false,
        max_tokens: Number(payload['maxTokens'] ?? 4096)
      });
      const req = http.createHttp();
      req.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + apiKey
        } as Record<string, string>,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: 300000,
        connectTimeout: 30000
      }).then((resp: http.HttpResponse): void => {
        try {
          const j = JSON.parse(String(resp.result)) as Record<string, Object>;
          const choices = (j['choices'] as Array<Record<string, Object>>) ?? [];
          const msg = choices[0]?.['message'] as Record<string, string> | undefined;
          const out: FxResult = {
            content: msg?.['content'] ?? '',
            reasoning: msg?.['reasoning_content'] ?? '',
            usage: j['usage'] ?? null
          };
          resolve(out);
        } finally {
          req.destroy();
        }
      }).catch((e: Error): void => {
        req.destroy();
        const out: FxError = { error: e.message };
        resolve(out);
      });
    });
  }

  get isDirty(): boolean { return this.dirty; }
  get language(): string { return this.lang; }
}
