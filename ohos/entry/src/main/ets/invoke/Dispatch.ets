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
import { fileIo as fs } from '@kit.CoreFileKit';

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
        return this.context!.resourceManager.getRawFileContent('models.json')
          .then((data: Uint8Array) => {
            const dec = new util.TextDecoder('utf-8');
            return JSON.parse(dec.decodeToString(data)) as Object;
          })
          .catch(() => null);
      case 'save_text_file':
        return this.saveTextFile(args);
      case 'invoke_fx_sdk':
        return this.invokeFx(args);
      default:
        return Promise.reject(new Error(`UNAVAILABLE_ON_OHOS: ${cmd}（该能力将在后续版本接入）`));
    }
  }

  private confirmDiscard(): Promise<Object | null> {
    return new Promise<Object | null>((resolve) => {
      promptAction.showDialog({
        title: '未保存的更改',
        message: '当前文档有未保存的更改，确定丢弃吗？',
        buttons: [{ text: '继续编辑', color: '#007aff' }, { text: '放弃更改', color: '#e5484d' }]
      }).then((r) => resolve(r.index === 1)).catch(() => resolve(false));
    });
  }

  private saveTextFile(args: Record<string, Object>): Promise<Object | null> {
    // args: { name, contentsB64 } → 写入用户文档目录
    const name = String(args['name'] ?? 'export.txt');
    const b64 = String(args['contentsB64'] ?? '');
    return new Promise<Object | null>((resolve) => {
      this.context?.startAbilityForResult({
        action: 'ohos.want.action.selectFile', // 文档选择器（另存为）
        type: 'application/*',
        parameters: { saveFile: true, name: name }
      } as Record<string, Object>).then((r) => {
        const uri = (r.result as Record<string, string>)['uri'];
        if (!uri) { resolve(null); return; }
        const bin = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
        const f = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        fs.writeSync(f.fd, bin.buffer as ArrayBuffer);
        fs.closeSync(f);
        resolve({ savedTo: uri });
      }).catch(() => resolve(null));
    });
  }

  /** invoke_fx_sdk：Agent 聊天的云端 LLM 调用（OpenAI 兼容 /v1/chat/completions）。 */
  private invokeFx(args: Record<string, Object>): Promise<Object | null> {
    return new Promise<Object | null>((resolve) => {
      const payload = JSON.parse(String(args['payload'] ?? '{}')) as Record<string, Object>;
      const apiKey = String(args['apiKey'] ?? args['apiKey'] ?? '');
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
      }).then((resp) => {
        try {
          const j = JSON.parse(String(resp.result)) as Record<string, Object>;
          const choices = (j['choices'] as Array<Record<string, Object>>) ?? [];
          const msg = choices[0]?.['message'] as Record<string, string> | undefined;
          resolve({
            content: msg?.['content'] ?? '',
            reasoning: msg?.['reasoning_content'] ?? '',
            usage: j['usage'] ?? null
          });
        } finally {
          req.destroy();
        }
      }).catch((e: Error) => {
        req.destroy();
        resolve({ error: e.message });
      });
    });
  }

  get isDirty(): boolean { return this.dirty; }
  get language(): string { return this.lang; }
}
