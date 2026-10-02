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

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
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

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}