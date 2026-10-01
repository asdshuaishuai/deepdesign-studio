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
      // 前端顶栏自带窗口控制（shim → harmonyBridge.win → Index.onWin），
      // 系统标题栏去掉避免双层；容错：个别形态不支持 decor 隐藏时保留系统栏
      try {
        mainWindow.setWindowDecorVisible(false);
      } catch (e) {
        hilog.warn(DOMAIN, 'deepdesign', 'setWindowDecorVisible unsupported: %{public}s', JSON.stringify(e));
      }
      // 2in1 桌面体验：启动即最大化（保持自由窗口形态，标题栏/ dock 悬停显示）；
      // 前端 □ 按钮可切换（maximize/restore 均为系统自由窗口语义，不碎裂）
      try {
        mainWindow.maximize(window.MaximizePresentation.EXIT_IMMERSIVE);
      } catch (e) {
        mainWindow.resize(900, 600);
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