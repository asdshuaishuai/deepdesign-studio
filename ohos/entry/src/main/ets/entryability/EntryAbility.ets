/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CommandDispatch } from '../invoke/Dispatch';
import { appStore } from '../model/AppStore';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // iss-4 登记：启动默认 NOT_SET（跟随系统），由 Index.aboutToAppear/saveLook 经
    // applicationContext.setColorMode 应用态覆写（深浅色资源 dd_* 随之换值）。
    // baseline §7.4：手动 setColorMode 后 onConfigurationUpdate 不再回调（下方
    // onConfigurationUpdate 写入的 ddSysDark 仅 legacy 'system' 分支消费、不可达）。
    // 【待模拟器验证】setColorMode 跨重启持久性未验证（batch-1 验收判据 3）——
    // onCreate 每次重置 NOT_SET，启动窗在 aboutToAppear 覆写前按系统档渲染；
    // 若验证发现持久化语义与该双段实现冲突（如启动窗闪烁/覆写多余），按复审修订
    // 评估移除本重置或门控，禁止静默。
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    // batch-13（验收修复轮）：want 参数打开通道——`aa start --ps ddp_b64 <base64>` 把外部
    // 构造的 .ddp 字节带入应用可读域（模拟器沙箱对 hdc push 路径均 Permission denied，
    // DocumentViewPicker 不可达 /data/local/tmp——验收 harness 指名的可测性缺口）。
    // Index 侧经 @StorageProp('ddWantDdpB64')+@Watch 消费：解码落沙箱后走既有 openVia 链
    //（DDP2 免密试链/canonical 解析/损坏诚实 toast 全复用）。一次性消费，正常启动零影响。
    this.stashWantDdp(want);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  /** 冷启动（onCreate）与热启动（onNewWant）共用的 want 参数暂存。 */
  private stashWantDdp(want: Want): void {
    try {
      const params = want.parameters;
      if (params === undefined || params === null) return;
      const v = params['ddp_b64'];
      if (typeof v === 'string' && v !== '') {
        // batch-13 诊断：通道收据（harness 对账「--ps 已传但未打开」类问题先查此日志）
        hilog.info(0x0000, 'ddWant', 'ddp_b64 received len=%{public}d', v.length);
        AppStorage.setOrCreate('ddWantDdpB64', v);
      }
      const k = params['dd_key'];
      if (typeof k === 'string' && k !== '') {
        // r11 验收修复轮：`--ps dd_key slash|comma` 快捷键驱动通道——模拟器 uitest/uinput
        // 注入不携带修饰态（Ctrl+/ 与对照 ⇧E 组合键全灭，工具限制非应用缺陷），物理键
        // 路径留 2in1 真机验收（r2 §六.6/r3 通道限制先例）；本通道经同一 want pipe 驱动
        // onPlanKey 同名分支体（batch-13 ddp_b64 可测性通道同构）。值拼 epoch nonce：
        // 同值重复 aa start 也强制 @Watch 重触发。
        const evt: string = k + '#' + Date.now().toString();
        hilog.info(0x0000, 'ddWant', 'dd_key received %{public}s', evt);
        AppStorage.setOrCreate('ddKeyEvt', evt);
      }
    } catch (e) {
      /* 无参数/类型不符：静默跳过（非打开意图） */
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.stashWantDdp(want);   // 应用在跑时二次 aa start 注入：经 @StorageProp @Watch 触发消费
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      // 2in1/PC 桌面形态：窗口 1360x900（与桌面版一致），最小 980x640
      const mainWindow = windowStage.getMainWindowSync();
      // 使用系统标题栏（原生三键 + 拖动 + 双击最大化）；前端顶栏的
      // — □ × 由 shim 注入 CSS 隐藏（html.harmony .winctl{display:none}）
      // PC 桌面形态：直接 resize 横屏全幅（vp）。
      // 不用 maximize()——系统对本 app 按手机应用归类，maximize 会给
      // 竖屏手机比例的最大化窗口（1260x2720 + 0.589 缩放），画面竖条居中。
      try {
        // 先退出系统最大化态（Mode=102 下 resize 会被钳制），再设横屏全幅
        mainWindow.restore().then((): void => {
          mainWindow.resize(1620, 1080);
        }).catch((): void => {
          mainWindow.resize(1620, 1080);
        });
      } catch (e) {
        mainWindow.resize(1200, 800);
      }
      mainWindow.setWindowLimits({
        minWidth: 980, minHeight: 640,
        maxWidth: 3840, maxHeight: 2160,
        pixelUnit: window.PixelUnit.VP
      });
      // gap-global-4 关窗脏确认：仅系统标题栏关闭钮触发（三键本尊不碰，只拦关闭行为）。
      // 修订 9a：必须在 loadContent 回调内注册——过早注册拿不到可用 UIContext 弹 AlertDialog。
      // SDK 契约（@ohos.window.d.ts:6154，@since 15，compatibleSdkVersion 26.0.0 满足）：
      // 回调返回 Promise<boolean>，resolve(true)=不关闭、resolve(false)/reject=继续关闭。
      mainWindow.on('windowWillClose', (): Promise<boolean> => {
        if (!appStore.dirty) {
          return Promise.resolve(false);   // 非 dirty 直接放行
        }
        return new Promise<boolean>((resolve) => {
          // 复用 Dispatch.confirm_discard 的红染确认框（同一代码路径与文案/样式）；
          // 其语义：resolve(true)=放弃更改、false=继续编辑 → 翻译到关窗语义：
          // 放弃更改=放行关闭（false），继续编辑=阻止关闭（true）。
          const d = new CommandDispatch();
          d.setContext(this.context);
          const noArgs: Record<string, Object> = {};
          d.dispatch('confirm_discard', noArgs).then((v: Object | null): void => {
            if (v === true) {
              appStore.dirty = false;   // 先清脏再放行，防 onBackground 兜底又把已放弃内容落盘
              resolve(false);
            } else {
              resolve(true);
            }
          }).catch((): void => {
            resolve(true);   // 确认框异常时宁可留住文档，不静默丢
          });
        });
      });
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // gap-settings-2：系统深浅色变化写入 AppStorage，Index @StorageProp('ddSysDark') 消费
    // （应用保持 COLOR_MODE_NOT_SET，未主动选择时跟随系统）
    AppStorage.setOrCreate('ddSysDark', newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onBackground(): void {
    // gap-global-4 兜底自恢复：windowWillClose 个别平台不派发时也不静默丢失。
    // dirty → serialize()（带 DDP-INTERIM-v1 前缀）落 filesDir/autorecover.json；
    // 非 dirty → 清掉残留自恢复文件（防下次启动误报恢复已保存/已放弃的内容）。
    // Index.aboutToAppear 检测到该文件即弹「恢复上次未保存的项目？」。
    try {
      const p = this.context.filesDir + '/autorecover.json';
      if (appStore.dirty && appStore.boards.length > 0) {
        const f = fs.openSync(p, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        fs.writeSync(f.fd, appStore.serialize());
        fs.closeSync(f);
      } else if (fs.accessSync(p)) {
        fs.unlinkSync(p);
      }
    } catch (e) {
      // 自恢复落盘失败不阻断后台化
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}