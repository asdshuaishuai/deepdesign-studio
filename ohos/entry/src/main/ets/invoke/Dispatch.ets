// ArkTS 命令分发 —— 前端 invoke → OHOS 原生实现 / Rust NAPI core
//
// 实现状态：
//   ✓ set_project_dirty / set_menu_language / confirm_discard / app_exit
//   ✓ save_text_file / model_registry（bundled）
//   ✓ save_ddp / open_ddp —— DDP 编解码走 Rust NAPI（与桌面版 .ddp 互通），
//     文件 IO 走 DocumentViewPicker + fileIo
//   ✓ list_ddp_projects —— 目录扫描（沙箱外目录无权限时报错，前端已容错跳过）
//   ✓ invoke_fx_sdk —— @ohos.net.http 直连 OpenAI 兼容端点（chat + models）
//   ◌ rebase_agent_ops —— 待 wasmtime 引擎宿主下沉（结构化错误，前端有 catch）
//   ✓ open_project_window —— 单窗口模式：聚焦自身

import { http } from '@kit.NetworkKit';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ddpEncrypt, ddpDecrypt } from '../core/CoreBridge';

interface FxModels {
  models: string[];
}

interface AgentResult {
  ok: boolean;
  ops: string[];
  text: string;
  stopReason: string;
  mbtB64: string;
}

interface CmdError {
  error: string;
}

interface SaveFileResult {
  savedTo: string;
}

interface SaveDdpResult {
  ok: boolean;
  path: string;
  bytes: number;
}

interface OpenDdpResult {
  ok: boolean;
  path: string;
  mbtB64: string;
}

interface OpenDdpNeedPassword {
  needPassword: boolean;
  path: string;
}

interface DdpProjectItem {
  file: string;
  path: string;
  size: number;
  modified: number;
}

interface DdpListResult {
  ok: boolean;
  projects: DdpProjectItem[];
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
      case 'save_ddp':
        return this.saveDdp(args);
      case 'open_ddp':
        return this.openDdp(args);
      case 'list_ddp_projects':
        return this.listDdpProjects(String(args['dir'] ?? ''));
      case 'invoke_fx_sdk':
        return this.invokeFx(args);
      case 'open_project_window':
        // 单窗口模式：无独立项目窗口，聚焦自身即满足语义
        return Promise.resolve(null);
      case 'rebase_agent_ops':
        return Promise.reject(
          new Error('UNAVAILABLE_ON_OHOS: rebase_agent_ops（引擎宿主下沉后接入，当前 Agent run 走前端 wasm 路径）'));
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
    // promptAction.showDialog 已弃用 → UIContext.showAlertDialog（经主窗口取 UIContext）
    return new Promise<Object | null>((resolve) => {
      const ctx = this.context;
      if (!ctx) { resolve(false); return; }
      window.getLastWindow(ctx).then((w: window.Window): void => {
        w.getUIContext().showAlertDialog({
          title: '未保存的更改',
          message: '当前文档有未保存的更改，确定丢弃吗？',
          primaryButton: {
            value: '继续编辑',
            action: (): void => resolve(false)
          },
          secondaryButton: {
            value: '放弃更改',
            fontColor: '#e5484d',
            action: (): void => resolve(true)
          }
        });
      }).catch((): void => resolve(false));
    });
  }

  // ---- 文件选择器辅助 ----

  private pickSavePath(defaultName: string): Promise<string> {
    return new Promise<string>((resolve) => {
      const saveOpts = new picker.DocumentSaveOptions();
      saveOpts.newFileNames = [defaultName];
      const docPicker = new picker.DocumentViewPicker();
      docPicker.save(saveOpts).then((uris: Array<string>): void => {
        resolve((uris && uris.length > 0) ? uris[0] : '');
      }).catch((): void => resolve(''));
    });
  }

  private pickOpenPath(): Promise<string> {
    return new Promise<string>((resolve) => {
      const selOpts = new picker.DocumentSelectOptions();
      selOpts.fileSuffixFilters = ['.ddp'];
      selOpts.maxSelectNumber = 1;
      const docPicker = new picker.DocumentViewPicker();
      docPicker.select(selOpts).then((uris: Array<string>): void => {
        resolve((uris && uris.length > 0) ? uris[0] : '');
      }).catch((): void => resolve(''));
    });
  }

  private writeBytes(uri: string, bin: Uint8Array): void {
    const f = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    fs.writeSync(f.fd, bin.buffer as ArrayBuffer);
    fs.closeSync(f);
  }

  private readBytes(uri: string, maxBytes: number): Uint8Array {
    const f = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const stat = fs.statSync(f.fd);
    const len = Math.min(stat.size, maxBytes);
    const buf = new ArrayBuffer(len);
    fs.readSync(f.fd, buf);
    fs.closeSync(f);
    return new Uint8Array(buf);
  }

  private saveTextFile(args: Record<string, Object>): Promise<Object | null> {
    // args: { name, contentsB64 } → DocumentViewPicker 另存为
    const name = String(args['name'] ?? 'export.txt');
    const b64 = String(args['contentsB64'] ?? '');
    return new Promise<Object | null>((resolve) => {
      this.pickSavePath(name).then((uri: string): void => {
        if (!uri) { resolve(null); return; }
        try {
          const helper = new util.Base64Helper();
          const bin: Uint8Array = helper.decodeSync(b64);
          this.writeBytes(uri, bin);
          const out: SaveFileResult = { savedTo: uri };
          resolve(out);
        } catch (e) {
          resolve(null);
        }
      });
    });
  }

  // ---- DDP（加解密在 Rust NAPI，与桌面版 .ddp 互通）----

  private saveDdp(args: Record<string, Object>): Promise<Object | null> {
    const mbtB64 = String(args['mbtB64'] ?? '');
    const password = String(args['password'] ?? '');
    let path = String(args['path'] ?? '').trim();
    return new Promise<Object | null>((resolve) => {
      const proceed = (p: string): void => {
        if (!p) { resolve(null); return; }  // 用户取消：Ok(null) 对齐桌面语义
        try {
          const ddpB64 = ddpEncrypt(mbtB64, password);
          const helper = new util.Base64Helper();
          const bin: Uint8Array = helper.decodeSync(ddpB64);
          this.writeBytes(p, bin);
          const out: SaveDdpResult = { ok: true, path: p, bytes: bin.length };
          resolve(out);
        } catch (e) {
          const cerr: CmdError = { error: `ddp_save_failed:${(e as Error).message}` };
          resolve(cerr);
        }
      };
      if (path) { proceed(path); return; }
      this.pickSavePath('未命名.ddp').then((p: string): void => {
        path = (p && !p.toLowerCase().endsWith('.ddp')) ? p + '.ddp' : p;
        proceed(path);
      });
    });
  }

  private openDdp(args: Record<string, Object>): Promise<Object | null> {
    const password = String(args['password'] ?? '');
    const viaDialog = String(args['path'] ?? '').trim() === '';
    return new Promise<Object | null>((resolve) => {
      const proceed = (p: string): void => {
        if (!p) { resolve(null); return; }  // 用户取消
        try {
          const bin = this.readBytes(p, 16 * 1024 * 1024 + 46);
          const helper = new util.Base64Helper();
          const ddpB64 = helper.encodeToStringSync(bin);
          try {
            const mbtB64 = ddpDecrypt(ddpB64, password);
            const out: OpenDdpResult = { ok: true, path: p, mbtB64: mbtB64 };
            resolve(out);
          } catch (decryptErr) {
            // 口令不符不整单失败：带回路径让前端弹口令框重试（对齐桌面语义）
            if (viaDialog) {
              const out: OpenDdpNeedPassword = { needPassword: true, path: p };
              resolve(out);
            } else {
              const cerr: CmdError = { error: `ddp_decrypt_failed:${(decryptErr as Error).message}` };
              resolve(cerr);
            }
          }
        } catch (e) {
          const cerr: CmdError = { error: `ddp_open_failed:${(e as Error).message}` };
          resolve(cerr);
        }
      };
      const given = String(args['path'] ?? '').trim();
      if (given) { proceed(given); return; }
      this.pickOpenPath().then((p: string): void => proceed(p));
    });
  }

  private listDdpProjects(dir: string): Promise<Object | null> {
    const d = dir.trim();
    if (!d || !fs.accessSync(d)) {
      return Promise.reject(new Error(`dir_not_found:${d}`));
    }
    return new Promise<Object | null>((resolve) => {
      fs.listFile(d).then((names: Array<string>): void => {
        const projects: DdpProjectItem[] = [];
        for (const n of names) {
          if (!n.toLowerCase().endsWith('.ddp')) continue;
          const full = d.endsWith('/') ? d + n : d + '/' + n;
          let size = 0;
          let modified = 0;
          try {
            const st = fs.statSync(full);
            size = st.size;
            modified = Math.floor(st.mtime / 1000);
          } catch (e) { /* 元数据缺失不阻断列表 */ }
          const item: DdpProjectItem = { file: n, path: full, size: size, modified: modified };
          projects.push(item);
        }
        projects.sort((a: DdpProjectItem, b: DdpProjectItem): number => b.modified - a.modified);
        const out: DdpListResult = { ok: true, projects: projects };
        resolve(out);
      }).catch((e: Error): void => {
        const cerr: CmdError = { error: `dir_read_failed:${d}:${e.message}` };
        resolve(cerr);
      });
    });
  }

  // MoonViz op 动词白名单（提取端侧模型回复中的可执行行）
  private static OP_VERBS: string[] = [
    'template', 'create', 'text', 'set', 'move', 'resize', 'style', 'delete', 'delete-artboard',
    'rename', 'add', 'remove', 'update', 'flow', 'link', 'align', 'group', 'order',
    'list', 'list-templates', 'lint', 'critique', 'query', 'states', 'flows', 'export-svg'
  ];

  /** 从端侧模型回复中提取 MoonViz op 命令行。 */
  private static extractOps(text: string): string[] {
    const ops: string[] = [];
    const lines = text.split('\n');
    for (const raw of lines) {
      const line = raw.trim()
        .replace(/^[-*\d.\s]+/, '')
        .replace(/^`+|`+$/g, '')
        .trim();
      if (!line || line.length > 200) continue;
      const head = line.split(/\s+/)[0].toLowerCase();
      if (CommandDispatch.OP_VERBS.includes(head)) {
        ops.push(line);
      }
    }
    return ops;
  }

  /**
   * 端侧系统 AI（localChatModel）执行 Agent 指令——鸿蒙体系下的默认执行者。
   * 返回 undefined = 端侧不可用（模块缺失/模型未就绪），调用方降级。
   */
  private localAgent(payload: Record<string, Object>): Promise<Object | null | undefined> {
    const loadMod: Promise<ESObject> = import('../ai/LocalChatBridge') as Promise<ESObject>;
    return loadMod.then((mod: ESObject): Promise<Object | null | undefined> => {
      return this.runLocalAgent(mod, payload);
    }).catch((): Object | null | undefined => {
      return undefined;  // 系统无 DataAugmentationKit
    });
  }

  private async runLocalAgent(mod: ESObject, payload: Record<string, Object>): Promise<Object | null | undefined> {
    try {
      const instruction = String(payload['instruction'] ?? '');
      const mbtB64 = String(payload['mbt_b64'] ?? '');
      let mbt = '';
      if (mbtB64) {
        const helper = new util.Base64Helper();
        mbt = util.TextDecoder.create("utf-8").decodeToString(helper.decodeSync(mbtB64));
      }
      const text: string | null = await mod.chatOnce(instruction, mbt);
      if (text === null) return undefined;
      const ops = CommandDispatch.extractOps(text);
      const out: AgentResult = {
        ok: true, ops: ops, text: text.trim(), stopReason: 'end', mbtB64: mbtB64
      };
      return out;
    } catch (e) {
      return undefined;
    }
  }

  /** invoke_fx_sdk：Agent 聊天/模型列表。默认执行者 = 端侧系统 AI（免 key、本地化），
   *  用户显式配置云端 key 时走 OpenAI 兼容端点。 */
  private invokeFx(args: Record<string, Object>): Promise<Object | null> {
    return new Promise<Object | null>((resolve) => {
      const payload = JSON.parse(String(args['payload'] ?? '{}')) as Record<string, Object>;
      const apiKey = String(args['apiKey'] ?? '');
      const fromPayload = String(payload['api_key'] ?? '');
      const mode = String(payload['mode'] ?? '');

      if (mode !== 'models' && !apiKey.trim() && !fromPayload.trim()) {
        // 默认执行者：系统级端侧 AI
        this.localAgent(payload).then((r: Object | null | undefined): void => {
          if (r !== undefined) { resolve(r); return; }
          const out: CmdError = { error: 'local_ai_unavailable: 端侧模型不可用，请在设置中配置云端 API Key' };
          resolve(out);
        });
        return;
      }
      let baseUrl = String(payload['baseUrl'] ?? args['baseUrl'] ?? 'https://api.deepseek.com');
      if (!/^https?:\/\//.test(baseUrl)) baseUrl = 'https://' + baseUrl;
      if (baseUrl.endsWith('/')) baseUrl = baseUrl.slice(0, -1);

      if (String(payload['mode'] ?? '') === 'models') {
        this.listModels(baseUrl, apiKey).then((v: Object | null): void => resolve(v));
        return;
      }
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

  private listModels(baseUrl: string, apiKey: string): Promise<Object | null> {
    return new Promise<Object | null>((resolve) => {
      const req = http.createHttp();
      req.request(baseUrl + '/models', {
        method: http.RequestMethod.GET,
        header: { 'Authorization': 'Bearer ' + apiKey } as Record<string, string>,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: 60000,
        connectTimeout: 30000
      }).then((resp: http.HttpResponse): void => {
        try {
          const j = JSON.parse(String(resp.result)) as Record<string, Object>;
          const data = (j['data'] as Array<Record<string, Object>>) ?? [];
          const ids: string[] = data.map((m: Record<string, Object>): string => String(m['id'] ?? ''));
          const out: FxModels = { models: ids };
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
