// 外观偏好持久化（batch-1，audit-modal-4）——主题 id 与深浅档经 Preferences 落盘，
// 杀进程重启后保持。照 AiConfig.ets getPreferencesSync 先例（应用沙箱内明文，键 dd-ui-look）。

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export interface UiLook {
  themeId: string;   // hmos | mac | win11 | deep | neu | glass（iss-4 增 hmos 鸿蒙原生主题）
  mode: string;      // light | dark
}

const PREF_NAME: string = 'dd-ui-look';
const KEY_LOOK: string = 'look';
const THEME_IDS: string[] = ['hmos', 'mac', 'win11', 'deep', 'neu', 'glass'];   // iss-4 前插 hmos
//   （缺它 load() 净化会把持久化的 hmos 回落默认）

export class UiPrefsStore {
  private prefs: preferences.Preferences | null = null;

  init(context: common.UIAbilityContext): void {
    try {
      const opts: preferences.Options = { name: PREF_NAME };
      this.prefs = preferences.getPreferencesSync(context, opts);
    } catch (e) {
      this.prefs = null;
    }
  }

  /** 读取外观；缺失/损坏/越界回落 hmos+浅色（白名单净化，对齐 AiConfig.load 字段级净化；
   *  iss-4：默认主题 mac → hmos，与 Index.ets @State themeId 初始值同步）。 */
  load(): UiLook {
    const def: UiLook = { themeId: 'hmos', mode: 'light' };
    if (!this.prefs) return def;
    try {
      const raw = this.prefs.getSync(KEY_LOOK, '');
      if (typeof raw !== 'string' || raw === '') return def;
      const v = JSON.parse(raw) as UiLook;
      return {
        themeId: THEME_IDS.includes(v.themeId) ? v.themeId : def.themeId,
        mode: v.mode === 'dark' ? 'dark' : def.mode
      };
    } catch (e) {
      return def;
    }
  }

  save(look: UiLook): void {
    if (!this.prefs) return;
    try {
      this.prefs.putSync(KEY_LOOK, JSON.stringify(look));
      this.prefs.flush().catch((): void => { /* 刷盘失败不阻断 */ });
    } catch (e) { /* 写失败不阻断 */ }
  }
}

export const uiPrefs: UiPrefsStore = new UiPrefsStore();
