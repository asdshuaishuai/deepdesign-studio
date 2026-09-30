// deepDesign 鸿蒙壳 —— ArkWeb 承载单文件前端 + Tauri invoke 兼容垫片
//
// 分层（见仓库 docs/harmonyos-port.md §4）：
//   L3 壳（本文件）：ArkWeb($rawfile) + javaScriptProxy 桥 + 端侧 AI provider
//   L2 垫片：前端零改动 —— index.html 里的 Tauri invoke 调用由同名桥对象承接
//   L1 core：Rust（ohrs 产 .so，经 NAPI 注册）——当前为骨架，后续由
//            deepdesign-core（wasmtime 宿主 + agent 循环 + DDP）填充
import { webview } from '@kit.ArkWeb';
import { bridge } from '../invoke/Bridge';
import { onDeviceAI } from '../ai/OnDeviceProvider';

@Entry
@Component
struct Index {
  controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    onDeviceAI.probe().catch((e: Error) =>
      console.warn(`[onDeviceAI] probe failed: ${e.message}`));
  }

  build() {
    Column() {
      Web({ src: $rawfile('index.html'), controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .onControllerAttached(() => {
          // Tauri invoke 兼容垫片注册（前端零改动，见 invoke/Bridge.ets）
          this.controller.registerJavaScriptProxy(bridge, 'harmonyBridge',
            ['invoke', 'emitEvent']);
          this.controller.refresh();
        })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
