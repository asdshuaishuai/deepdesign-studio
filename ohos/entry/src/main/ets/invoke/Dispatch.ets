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
//   ✓ engine_status / engine_apply_human_op —— rust-core engine 模块 NAPI 接线
//     （gap-global-3 M1；引擎不可用诚实降级 available:false/error + console.error，
//     调用方回退本地路径）
//   ✓ open_project_window —— 单窗口模式：聚焦自身

import { http } from '@kit.NetworkKit';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ddpEncrypt, ddpDecrypt } from '../core/CoreBridge';
import { probeEngine, applyHumanOp, renderDoc, historyOp, EngineStatus, EngineApplyResult, agentStart, agentFeedLlm } from '../core/EngineBridge';

interface FxModels {
  models: string[];
  source?: string;   // network | snapshot（batch-5：失败回落 bundled 快照时标注）
}

// bundled models.json 快照的具名形状（provider/model 两层均为动态 id 键表，键层用 Record 承载）
interface ModelSnapshot {
  providers?: Record<string, ModelSnapProvider>;
}

interface ModelSnapProvider {
  models?: Record<string, Object>;
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

/** engine_status 返回形状（Index 按字段鸭子对齐消费）。 */
interface EngineStatusResult {
  available: boolean;
  tag: string;
  version: string;
  reason: string;
}

interface FxResult {
  content: string;
  reasoning: string;
  usage: Object | null;
  message?: Record<string, Object>;   // M3.6.4：原始 assistant 消息
  finishReason?: string;   // M3.6.8：length=截断透传
}

interface FxError {
  error: string;
}

// MoonViz op 动词白名单（提取模型回复/用户输入中的可执行行）
// batch-9（cur-5）：由 CommandDispatch 私有静态公开化为模块级导出——消费方扩展到
// AgentService.execCommandFlow（小艺/云端回复与本地兜底原始指令统一命令行解析）。
const OP_VERBS: string[] = [
  'template', 'create', 'text', 'set', 'move', 'resize', 'style', 'delete', 'delete-artboard',
  'rename', 'add', 'remove', 'update', 'flow', 'link', 'align', 'group', 'order',
  'list', 'list-templates', 'lint', 'critique', 'query', 'states', 'flows', 'export-svg'
];

/** 提取文本中的 MoonViz op 命令行（batch-9 公开化，原 CommandDispatch.extractOps）。 */
export function extractOps(text: string): string[] {
  const ops: string[] = [];
  const lines = text.split('\n');
  for (const raw of lines) {
    const line = raw.trim()
      .replace(/^[-*\d.\s]+/, '')
      .replace(/^`+|`+$/g, '')
      .trim();
    if (!line || line.length > 200) continue;
    const head = line.split(/\s+/)[0].toLowerCase();
    if (OP_VERBS.includes(head)) {
      ops.push(line);
    }
  }
  return ops;
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
      case 'engine_status':
        return this.engineStatus();
      case 'engine_apply_human_op':
        return this.engineApplyHumanOp(args);
      case 'agent_start':
        return this.agentStartCmd(args);
      case 'agent_feed_llm':
        return this.agentFeedCmd(args);
      case 'engine_render':
        return this.engineRenderCmd(args);
      case 'engine_history':
        return this.engineHistoryCmd(args);
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

  // ---- 引擎宿主（gap-global-3 接线，M1：rust-core engine 模块 NAPI 导出）----
  // 诚实降级：引擎不可用（导出缺失/传输失败）时 resolve available:false + reason，
  // **保持现状文案**由调用方执行；此处 console.error 原因（§13：console.error 是
  // 模拟器上可靠日志通道）。门拒绝（信封 ok:false）是合法业务响应，原样透传。

  /** engine_status：真实引擎探针（wasmtime 实例化 + version_info）。首呼含 wasm 编译
   * （秒级，同步 NAPI 阻塞 UI 线程）——调用方须延时到首帧后。 */
  private engineStatus(): Promise<Object | null> {
    return new Promise<Object | null>((resolve) => {
      try {
        const st: EngineStatus = probeEngine();
        if (!st.available) {
          console.error(`[engine] 引擎不可用: ${st.reason}`);
        }
        const out: EngineStatusResult = {
          available: st.available, tag: st.tag, version: st.version, reason: st.reason
        };
        resolve(out);
      } catch (e) {
        console.error(`[engine] 探测异常: ${(e as Error).message}`);
        const out: EngineStatusResult = {
          available: false, tag: '', version: '',
          reason: `engine_probe_threw:${(e as Error).message}`
        };
        resolve(out);
      }
    });
  }

  /** agent_start（M3.6.7）：{ instruction, docB64 } → 建会话，resolve { json }（首动作）。 */
  private agentStartCmd(args: Record<string, Object>): Promise<Object | null> {
    const instruction = String(args['instruction'] ?? '');
    const docB64 = String(args['docB64'] ?? '');
    return new Promise<Object | null>((resolve): void => {
      const r = agentStart(instruction, docB64);
      if (r.ok) {
        const okOut: Record<string, Object> = { 'json': r.envelope };
        resolve(okOut);
      } else {
        const errOut: Record<string, Object> = { 'error': r.error };
        resolve(errOut);
      }
    });
  }

  /** agent_feed_llm（M3.6.7）：{ messageJson } → 喂回 LLM 响应，resolve { json }（下一动作）。
   * 引擎 op 在 TaskPool 工作线程执行（调用方经 agentFeedLlmAsync，UI 线程不阻塞）。 */
  private agentFeedCmd(args: Record<string, Object>): Promise<Object | null> {
    const messageJson = String(args['messageJson'] ?? '');
    return new Promise<Object | null>((resolve): void => {
      const r = agentFeedLlm(messageJson);
      if (r.ok) {
        const okOut: Record<string, Object> = { 'json': r.envelope };
        resolve(okOut);
      } else {
        const errOut: Record<string, Object> = { 'error': r.error };
        resolve(errOut);
      }
    });
  }

  /** engine_apply_human_op：{ docB64, op } → 引擎人类门。成功 resolve 引擎信封
   * （含 ok/mbt_b64 等，ok:false 的门拒绝原样透传）；导出缺失/传输失败 resolve
   * { error }（消费方据此回退本地路径）。 */
  private engineApplyHumanOp(args: Record<string, Object>): Promise<Object | null> {
    return new Promise<Object | null>((resolve) => {
      const docB64 = String(args['docB64'] ?? '');
      const op = String(args['op'] ?? '');
      try {
        const r: EngineApplyResult = applyHumanOp(docB64, op);
        if (!r.ok) {
          const out: CmdError = { error: r.error };
          resolve(out);
          return;
        }
        resolve(JSON.parse(r.envelope) as Object);
      } catch (e) {
        console.error(`[engine] apply 失败: ${op} -> ${(e as Error).message}`);
        const out: CmdError = { error: `engine_apply_failed:${(e as Error).message}` };
        resolve(out);
      }
    });
  }

  /** engine_render（M3）：{ docB64 } → render_mbt 信封（artboards[].svg 供画布高保真层）。 */
  private engineRenderCmd(args: Record<string, Object>): Promise<Object | null> {
    return new Promise<Object | null>((resolve) => {
      const docB64 = String(args['docB64'] ?? '');
      try {
        const r: EngineApplyResult = renderDoc(docB64);
        if (!r.ok) {
          const out: CmdError = { error: r.error };
          resolve(out);
          return;
        }
        resolve(JSON.parse(r.envelope) as Object);
      } catch (e) {
        console.error(`[engine] render 失败: ${(e as Error).message}`);
        const out: CmdError = { error: `engine_render_failed:${(e as Error).message}` };
        resolve(out);
      }
    });
  }

  /** engine_history（M3）：{ docB64, sub } → session_history（按板 init/commit/undo/redo）。
   * undo/redo 改文档 → 信封带 canonical（mbt_b64），消费方合并回灌。 */
  private engineHistoryCmd(args: Record<string, Object>): Promise<Object | null> {
    return new Promise<Object | null>((resolve) => {
      const docB64 = String(args['docB64'] ?? '');
      const sub = String(args['sub'] ?? '');
      try {
        const r: EngineApplyResult = historyOp(docB64, sub);
        if (!r.ok) {
          const out: CmdError = { error: r.error };
          resolve(out);
          return;
        }
        resolve(JSON.parse(r.envelope) as Object);
      } catch (e) {
        console.error(`[engine] history 失败: ${sub} -> ${(e as Error).message}`);
        const out: CmdError = { error: `engine_history_failed:${(e as Error).message}` };
        resolve(out);
      }
    });
  }

  /** invoke_fx_sdk：Agent 聊天/模型列表。云端 OpenAI 兼容直连（batch-9 起：无 key 不再
   * 隐性改道端侧——执行者选择归 AgentService 选定执行者优先链，此处诚实报错兜底）。 */
  private invokeFx(args: Record<string, Object>): Promise<Object | null> {
    return new Promise<Object | null>((resolve) => {
      const payload = JSON.parse(String(args['payload'] ?? '{}')) as Record<string, Object>;
      const apiKey = String(args['apiKey'] ?? '');
      const fromPayload = String(payload['api_key'] ?? '');
      const mode = String(payload['mode'] ?? '');

      if (mode !== 'models' && !apiKey.trim() && !fromPayload.trim()) {
        // batch-9（复审 finding-1 后门收口）：原「无 key→localAgent 隐性改道」分支删除——
        // 执行者选择归 AgentService 选定执行者优先链（provider=xiaoyi 由其直调 chatOnce，
        // 不经本命令）；此处对无 key 云端调用诚实报错，杜绝静默改道击穿执行者诚实语义。
        const out: CmdError = { error: 'api_key_required: 未配置云端 API Key' };
        resolve(out);
        return;
      }
      let baseUrl = String(payload['baseUrl'] ?? args['baseUrl'] ?? 'https://api.deepseek.com');
      if (!/^https?:\/\//.test(baseUrl)) baseUrl = 'https://' + baseUrl;
      if (baseUrl.endsWith('/')) baseUrl = baseUrl.slice(0, -1);

      if (String(payload['mode'] ?? '') === 'models') {
        this.listModels(baseUrl, apiKey).then((v: Object | null): void => {
          // 网络失败/空列表 → 回落 bundled models.json 快照（batch-5 小改，照抄 loadModelRegistry 先例）
          const fm = v as FxModels;
          if (v !== null && Array.isArray(fm.models) && fm.models.length > 0) {
            resolve(v);
            return;
          }
          this.snapshotModels().then((ids: string[]): void => {
            const out: FxModels = { models: ids, source: 'snapshot' };
            resolve(out);
          });
        });
        return;
      }
      const url = baseUrl + '/chat/completions';
      // M3.6.4 agent loop：tools/tool_choice 透传（此前被丢弃——单轮 chat 专用形态）
      const bodyObj: Record<string, Object> = {
        'model': String(payload['model'] ?? ''),
        'messages': (payload['messages'] ?? []) as Object,
        'stream': false,
        'max_tokens': Number(payload['maxTokens'] ?? 4096)
      };
      if (payload['tools'] !== undefined && payload['tools'] !== null) {
        bodyObj['tools'] = payload['tools'];
        bodyObj['tool_choice'] = payload['toolChoice'] ?? 'auto';
      }
      // M3.6.8 review：思考方言键透传（此前 body 白名单丢弃 reasoning_effort/thinking/
      // chat_template_kwargs——thinkingExtraBody 全表变成死代码，恒思考模型稳定性支柱失效）
      for (const dk of ['reasoning_effort', 'thinking', 'chat_template_kwargs']) {
        if (payload[dk] !== undefined && payload[dk] !== null) {
          bodyObj[dk] = payload[dk];
        }
      }
      const body = JSON.stringify(bodyObj);
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
          // review-m37 R12：4xx/5xx 此前被当空回复静默走本地兜底（坏 key/欠费不可见）
          if (resp.responseCode >= 400) {
            const errOut: FxError = { error: `http_${resp.responseCode}: ${String(resp.result).slice(0, 160)}` };
            resolve(errOut);
            return;
          }
          const j = JSON.parse(String(resp.result)) as Record<string, Object>;
          const choices = (j['choices'] as Array<Record<string, Object>>) ?? [];
          const msg = choices[0]?.['message'] as Record<string, Object> | undefined;
          const out: FxResult = {
            content: String(msg?.['content'] ?? ''),
            reasoning: String(msg?.['reasoning_content'] ?? ''),
            usage: j['usage'] ?? null,
            message: msg,   // M3.6.4：完整 assistant 消息（含 tool_calls）供 agent loop 回填
            finishReason: String(choices[0]?.['finish_reason'] ?? '')   // M3.6.8：length=截断
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

  /** bundled models.json 快照（providers{id→{models{id…}}}}）展平全部模型 id，离线兜底。 */
  private snapshotModels(): Promise<string[]> {
    const ctx = this.context;
    if (!ctx) return Promise.resolve([]);
    return ctx.resourceManager.getRawFileContent('models.json').then((data: Uint8Array): string[] => {
      const snap = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(data)) as ModelSnapshot;
      const providers = snap.providers ?? {};
      const ids: string[] = [];
      for (const pid of Object.keys(providers)) {
        const p = providers[pid];
        const models = p?.models ?? {};
        for (const mid of Object.keys(models)) {
          if (!ids.includes(mid)) ids.push(mid);
        }
      }
      return ids;
    }).catch((): string[] => []);
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
