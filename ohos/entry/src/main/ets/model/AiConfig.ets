// AI 服务商配置（gap-settings-1）—— Preferences 持久化。
// 注意：apiKey 按 ProjectRegistry 同款 Preferences 明文落盘（应用沙箱内）；
// 桌面版同为 localStorage 明文分槽，keychain 强化属后续增强（见桌面已知缺口登记）。
// batch-3（audit-modal-6）：扩 thinkingLevel/maxSteps——思考等级 6 档/步数上限 4 档
// （i:1166-1183），持久化+字段级净化同 provider 先例；方言注入（reasoning_effort 等）
// 归 gap-global-3，本批 UI 与透传先行。

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export interface AiConf {
  provider: string;    // xiaoyi（batch-9 平级化默认档）| 13 预设 id | custom（对齐 Index PRESETS）
  baseUrl: string;
  apiKey: string;
  model: string;
  thinkingLevel: string;  // off|auto|low|medium|high|max（默认 auto）
  maxSteps: number;       // 200|500|1000|2000（默认 500）
}

const PREF_NAME: string = 'dd-ai-config';
const KEY_CONF: string = 'conf';
const THINK_IDS: string[] = ['off', 'auto', 'low', 'medium', 'high', 'max'];
const STEP_VALUES: number[] = [200, 500, 1000, 2000];
// provider 净化白名单（batch-9）：xiaoyi + 13 预设 id + custom——与 Index.ets PRESETS 的 id
// 集合同源同序（PRESETS 是显示/菜单事实源，此处是持久化净化面；两处必须同步扩，耦合登记）。
// 偏离登记（spec-settings-3）：桌面默认 deepseek 且无小艺条目（r8-general-spec 实证「小艺不在
// 通用版列表」）——鸿蒙侧把小艺平级化为首选执行者是用户 2026-10-04 显性决策（零配置开箱
// 可用），桌面列表不动。
const PROVIDER_IDS: string[] = ['xiaoyi', 'deepseek', 'glm', 'glm-coding', 'zai', 'zai-coding',
  'kimi', 'kimi-plan', 'minimax', 'minimax-intl', 'minimax-anthropic', 'minimax-anthropic-intl',
  'stepfun', 'stepfun-plan', 'custom'];

export function emptyConf(): AiConf {
  // batch-9：默认 provider 改 xiaoyi（免 key 免 baseUrl 免 model、免 thinking/maxSteps 适配
  // ——thinkingLevel/maxSteps 字段保留默认值，仅云端渠道消费）
  return { provider: 'xiaoyi', baseUrl: '', apiKey: '', model: '',
    thinkingLevel: 'auto', maxSteps: 500 };
}

/** 多服务商槽位（batch-12，spec-settings-2 存储内核）：对齐桌面
 * deepdesign-fx-providers（provider→conf 分槽）/ deepdesign-fx-active（当前启用）双键语义。 */
export interface AiSlots {
  active: string;
  slots: Record<string, AiConf>;
}

export class AiConfigStore {
  private prefs: preferences.Preferences | null = null;

  init(context: common.UIAbilityContext): void {
    try {
      const opts: preferences.Options = { name: PREF_NAME };
      this.prefs = preferences.getPreferencesSync(context, opts);
    } catch (e) {
      this.prefs = null;
    }
  }

  /** 单字段净化（原 load() 主体抽出，槽位逐槽复用）。 */
  private sanitize(c: AiConf, def: AiConf): AiConf {
    return {
      provider: PROVIDER_IDS.includes(c.provider) ? c.provider : def.provider,
      baseUrl: typeof c.baseUrl === 'string' ? c.baseUrl : def.baseUrl,
      apiKey: typeof c.apiKey === 'string' ? c.apiKey : '',
      model: typeof c.model === 'string' ? c.model : '',
      thinkingLevel: THINK_IDS.includes(c.thinkingLevel) ? c.thinkingLevel : def.thinkingLevel,
      maxSteps: STEP_VALUES.includes(c.maxSteps) ? c.maxSteps : def.maxSteps
    };
  }

  /** 读取槽位表（batch-12）：新格式 {active,slots}；旧单槽 dd-ai-config（AiConf 形态）
   * 首载迁移——旧 conf 整体入其 provider 槽并置 active（一次性，写回即新格式）。 */
  loadAll(): AiSlots {
    const def = emptyConf();
    const empty: AiSlots = { active: def.provider, slots: {} };
    if (!this.prefs) return empty;
    try {
      const raw = this.prefs.getSync(KEY_CONF, '');
      if (typeof raw !== 'string' || raw === '') {
        const c = def;
        empty.slots[c.provider] = c;
        return empty;
      }
      const obj = JSON.parse(raw) as Object;
      const rec = obj as Record<string, Object>;
      if (rec['slots'] !== undefined && rec['slots'] !== null && typeof rec['active'] === 'string') {
        // 新格式：逐槽净化
        const rawSlots = rec['slots'] as Record<string, Object>;
        const out: Record<string, AiConf> = {};
        for (const pid of Object.keys(rawSlots)) {
          const sc = rawSlots[pid] as AiConf;
          if (sc === null || sc === undefined || typeof sc !== 'object') continue;
          out[pid] = this.sanitize(sc, def);
        }
        const active = PROVIDER_IDS.includes(String(rec['active'])) ? String(rec['active']) : def.provider;
        if (out[active] === undefined) {
          out[active] = def;
        }
        return { active: active, slots: out };
      }
      // 旧单槽迁移（batch-3 前格式）：整体入其 provider 槽
      const legacy = this.sanitize(obj as AiConf, def);
      const slots: Record<string, AiConf> = {};
      slots[legacy.provider] = legacy;
      return { active: legacy.provider, slots: slots };
    } catch (e) {
      const c = def;
      empty.slots[c.provider] = c;
      return empty;
    }
  }

  private persistAll(slots: AiSlots): void {
    if (!this.prefs) return;
    try {
      this.prefs.putSync(KEY_CONF, JSON.stringify(slots));
      this.prefs.flush().catch((): void => { /* 刷盘失败不阻断 */ });
    } catch (e) { /* 写失败不阻断 */ }
  }

  /** 读取当前启用槽（AgentService 等既有单槽消费点兼容 API）。 */
  load(): AiConf {
    const all = this.loadAll();
    const c = all.slots[all.active];
    return c !== undefined ? c : emptyConf();
  }

  /** 读取指定槽（未配置过返回带 provider 的空表单——PRESETS 默认值由 Index 补）。 */
  loadSlot(provider: string): AiConf {
    const all = this.loadAll();
    const c = all.slots[provider];
    if (c !== undefined) return c;
    const def = emptyConf();
    return { provider: provider, baseUrl: '', apiKey: '', model: '',
      thinkingLevel: def.thinkingLevel, maxSteps: def.maxSteps };
  }

  /** 写指定槽（不影响 active）。 */
  saveSlot(provider: string, conf: AiConf): void {
    const all = this.loadAll();
    all.slots[provider] = this.sanitize(conf, emptyConf());
    this.persistAll(all);
  }

  /** 切换当前启用槽（选择即生效语义的持久化侧）。 */
  setActive(provider: string): void {
    const all = this.loadAll();
    if (!PROVIDER_IDS.includes(provider)) return;
    all.active = provider;
    if (all.slots[provider] === undefined) {
      const def = emptyConf();
      all.slots[provider] = { provider: provider, baseUrl: '', apiKey: '', model: '',
        thinkingLevel: def.thinkingLevel, maxSteps: def.maxSteps };
    }
    this.persistAll(all);
  }

  /** 兼容 API：写当前启用槽并置 active（Index.saveAiConf 单槽语义保持）。 */
  save(conf: AiConf): void {
    if (!this.prefs) return;
    const all = this.loadAll();
    const pid = PROVIDER_IDS.includes(conf.provider) ? conf.provider : all.active;
    all.slots[pid] = this.sanitize(conf, emptyConf());
    all.active = pid;
    this.persistAll(all);
  }
}

export const aiConfig: AiConfigStore = new AiConfigStore();
