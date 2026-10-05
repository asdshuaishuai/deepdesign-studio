// 最近项目注册表（gap-topbar-2）—— 对齐桌面版 localStorage dd-recent-projects 语义：
// path/name/ts，容量 10，ts 倒序；@ohos.data.preferences 持久化（应用沙箱内，跨启动存活）。
// 只登记「保存/导出/打开成功」真实落盘的 .ddp；当前绑定项的 ✓ 标记由 UI 层按
// AppStore.filePath 比对（注册表不存「当前项」概念，与桌面一致）。

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export interface RecentItem {
  path: string;
  name: string;
  ts: number;
}

const MAX_RECENT: number = 10;
const PREF_NAME: string = 'dd-recent-projects';
const KEY_ITEMS: string = 'items';

export class ProjectRegistry {
  private prefs: preferences.Preferences | null = null;

  /** 在 EntryAbility/页面拿到 UIAbilityContext 后调用一次；失败降级为内存不存（list 恒空）。 */
  init(context: common.UIAbilityContext): void {
    try {
      const opts: preferences.Options = { name: PREF_NAME };
      this.prefs = preferences.getPreferencesSync(context, opts);
    } catch (e) {
      this.prefs = null;
    }
  }

  /** 全量最近项目，ts 倒序；损坏/缺失返回空数组（不抛错）。 */
  list(): RecentItem[] {
    if (!this.prefs) return [];
    try {
      const raw = this.prefs.getSync(KEY_ITEMS, '[]');
      const items = JSON.parse(String(raw)) as RecentItem[];
      if (!Array.isArray(items)) return [];
      const clean: RecentItem[] = [];
      for (const it of items) {
        if (typeof it?.path === 'string' && it.path !== '' &&
          typeof it?.name === 'string' && typeof it?.ts === 'number') {
          clean.push({ path: it.path, name: it.name, ts: it.ts });
        }
      }
      clean.sort((a: RecentItem, b: RecentItem): number => b.ts - a.ts);
      return clean;
    } catch (e) {
      return [];
    }
  }

  /** 打开/保存/导出成功后登记：同 path 去重置顶，容量 10。 */
  upsert(path: string, name: string): void {
    if (!path || path === '') return;
    const items: RecentItem[] = this.list().filter((i: RecentItem): boolean => i.path !== path);
    items.unshift({ path: path, name: name, ts: Date.now() });
    if (items.length > MAX_RECENT) items.splice(MAX_RECENT);
    this.save(items);
  }

  remove(path: string): void {
    this.save(this.list().filter((i: RecentItem): boolean => i.path !== path));
  }

  private save(items: RecentItem[]): void {
    if (!this.prefs) return;
    try {
      this.prefs.putSync(KEY_ITEMS, JSON.stringify(items));
      this.prefs.flush().catch((): void => { /* 刷盘失败不阻断；下次 upsert 会再 flush */ });
    } catch (e) { /* 写失败不阻断主流程 */ }
  }
}

export const projectRegistry: ProjectRegistry = new ProjectRegistry();
