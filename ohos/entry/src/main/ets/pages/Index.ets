// deepDesign 鸿蒙版 —— ArkWeb 承载原版前端（UI/交互与桌面版一字不差）
//
// 架构：原生壳（窗口/生命周期）+ ArkWeb（frontend/index.html 全量渲染）
//   + invoke 管线（window.__TAURI__ → harmonyBridge → Dispatch/NAPI core）
// 前端以 IS_TAURI=true 原生模式启动：invoke 命令经 shim 进 ArkTS，
// 引擎/加密类命令走 Rust NAPI core，系统能力走 OHOS 原生实现。
import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { harmonyBridge } from '../invoke/Bridge';
import { coreVersion } from '../core/CoreBridge';

const RAW_PREFIX = 'https://appassets.deepdesign.local/';

function mimeOf(path: string): string {
  if (path.endsWith('.wasm')) return 'application/wasm';
  if (path.endsWith('.json')) return 'application/json';
  if (path.endsWith('.js')) return 'text/javascript';
  if (path.endsWith('.html')) return 'text/html';
  if (path.endsWith('.css')) return 'text/css';
  if (path.endsWith('.png')) return 'image/png';
  if (path.endsWith('.svg')) return 'image/svg+xml';
  return 'application/octet-stream';
}

@Entry
@Component
struct Index {
  controller: webview.WebviewController = new webview.WebviewController();
  @State shimJs: string = '';
  @State probeInfo: string = '';
  coreTag: string = '';
  winObj: window.Window | null = null;

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    // shim 必须在页面任何脚本执行前注入（documentStart），故先读后渲染 Web
    ctx.resourceManager.getRawFileContent('invoke-shim.js').then((buf: Uint8Array) => {
      const dec = util.TextDecoder.create('utf-8');
      this.shimJs = dec.decodeToString(buf);
    }).catch((e: Error) => {
      hilog.error(0x0000, 'deepdesign', 'read shim failed: %{public}s', e.message);
    });
    window.getLastWindow(ctx).then((w: window.Window) => {
      this.winObj = w;
      harmonyBridge.setWinHandler((action: string) => this.onWin(action));
    }).catch(() => {});
    harmonyBridge.attachController(this.controller);
    try {
      this.coreTag = coreVersion();
      console.error('[core] ' + this.coreTag);
    } catch (e) {
      console.error('[core-fail] ' + (e as Error).message);
    }
  }

  private onWin(action: string): void {
    if (!this.winObj) return;
    if (action === 'minimize') {
      this.winObj.minimize();
    } else if (action === 'close') {
      this.winObj.destroyWindow().catch(() => {});
    } else if (action.startsWith('title:')) {
      // 标题由前端 document.title 自管，原生侧无需处理
    }
  }

  build() {
    Stack() {
      if (this.shimJs !== '') {
        Web({ src: RAW_PREFIX + 'index.html', controller: this.controller })
          .width('100%').height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(true)
          .zoomAccess(false)
          .overviewModeAccess(true)
          .javaScriptProxy({
            object: harmonyBridge,
            name: 'harmonyBridge',
            methodList: ['invokeAsync', 'win', 'onEvent'],
            controller: this.controller,
            asyncMethodList: []
          })
          .javaScriptOnDocumentStart([
            { script: this.shimJs, scriptRules: ['*'] }
          ])
          .onInterceptRequest((event) => {
            // resource://rawfile/ 下的子资源（fetch/XHR/wasm 不走静态资源栈）统一拦截回供
            const url: string = event.request.getRequestUrl();
            if (!url.startsWith(RAW_PREFIX)) return null;
            const path = decodeURIComponent(url.slice(RAW_PREFIX.length).split('?')[0].split('#')[0]);
            if (path === '') return null;
            try {
              const ctx = getContext(this) as common.UIAbilityContext;
              const buf: Uint8Array = ctx.resourceManager.getRawFileContentSync(path);
              const resp = new WebResourceResponse();
              resp.setResponseData(buf.buffer as ArrayBuffer);
              resp.setResponseEncoding('utf-8');
              resp.setResponseMimeType(mimeOf(path));
              resp.setResponseHeader([
                { headerKey: 'Access-Control-Allow-Origin', headerValue: '*' }
              ]);
              resp.setResponseCode(200);
              resp.setReasonMessage('OK');
              return resp;
            } catch (e) {
              console.error('[rawfile-miss] ' + path);
              return null;
            }
          })
          .onPageEnd(() => {
            this.controller.runJavaScript(
              `JSON.stringify({url: location.href, tauri: !!window.__TAURI__, bridge: !!(window.harmonyBridge&&window.harmonyBridge.invokeAsync), eng: (document.getElementById('eng-dot')||{}).className, qs: typeof quickStart})`)
              .then((v: string): void => { this.probeInfo = v; console.error('[page] ' + v); })
              .catch((e: Error): void => console.error('[js-err] ' + e.message));
          })
          .onConsole((e) => {
            hilog.info(0x0000, 'deepdesign-web', '%{public}s', e.message);
            return false;
          })
          .onControllerAttached(() => {
            console.error('[attached] controller ready');
          })
      } else {
        // shim 就绪前的占位（毫秒级）
        Column() {
          Text('deepDesign').fontSize(20).fontWeight(700).fontColor('#1c1c1e')
          Text('starting engine…').fontSize(12).fontColor('#636366').margin({ top: 8 })
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor('#f4f4f6')
      }
    }
    .width('100%').height('100%').backgroundColor('#f4f4f6')
    .overlay(this.probeOverlay(), { align: Alignment.Top })
  }

  @Builder
  probeOverlay() {
    if (this.probeInfo !== '' && (this.probeInfo.includes('bad') || this.probeInfo.includes(':false') || this.probeInfo.includes('"err"'))) {
      Text(this.probeInfo)
        .fontSize(8).fontColor('#e5484d').maxLines(3)
        .padding(4).backgroundColor('rgba(255,255,255,0.85)')
    }
  }
}
