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
import { coreVersion, ddpEncrypt, ddpDecrypt } from '../core/CoreBridge';

const RAW_PREFIX = 'https://appassets.deepdesign.local/';
// synthetic 输入转发开关（模拟器镜像缺输入派发；真机若原生正常可置 false）
const INPUT_FORWARD = true;

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
      // DDP NAPI 自测（roundtrip）：通过则静默，失败进探针/日志
      const enc = ddpEncrypt('IyBCb2FyZAoKaGVsbG8=', 'selftest');
      const dec = ddpDecrypt(enc, 'selftest');
      this.coreTag += (dec === 'IyBCb2FyZAoKaGVsbG8=') ? ' · ddp:ok' : ' · ddp:mismatch';
    } catch (e) {
      this.coreTag += ' · ddp:FAIL';
      console.error('[ddp-selftest] ' + (e as Error).message);
    }
    console.error('[core] ' + this.coreTag);
  }

  private maximized: boolean = false;

  private onWin(action: string): void {
    if (!this.winObj) return;
    if (action === 'minimize') {
      this.winObj.minimize();
    } else if (action === 'close') {
      this.winObj.destroyWindow().catch(() => {});
    } else if (action === 'maximize') {
      // 前端顶栏 □ 按钮：自由窗口 ↔ 全屏切换
      this.maximized = !this.maximized;
      this.winObj.setFullScreen(this.maximized).catch((): void => {});
      if (!this.maximized) {
        this.winObj.resize(1360, 900);
      }
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
            // 就绪状态采集（只读）：异常时探针 overlay 才会显示
            const probe = `JSON.stringify({tauri: !!window.__TAURI__, bridge: !!(window.harmonyBridge&&window.harmonyBridge.invokeAsync), eng: (document.getElementById('eng-dot')||{}).className, qs: typeof quickStart, ddp: typeof window.__HARMONY__})`;
            this.controller.runJavaScript(probe)
              .then((v: string): void => { this.probeInfo = v; console.error('[ready] ' + v); })
              .catch((e: Error): void => console.error('[js-err] ' + e.message));
          })
          // 模拟器镜像缺陷兜底：PC 形态 web_render 下触摸/鼠标不派发给 ArkWeb 内部，
          // ArkUI 层捕获坐标后转发为 synthetic 鼠标事件（elementFromPoint+click）。
          // 真机 ArkWeb 若原生分发正常，可在 Index 顶部 INPUT_FORWARD=false 关闭。
          .onTouch((e) => {
            if (e.type === TouchType.Down || e.type === TouchType.Up) {
              if (!INPUT_FORWARD) return;
              const x = Math.round(e.touches[0].x);
              const y = Math.round(e.touches[0].y);
              const type = e.type === TouchType.Down ? 'mousedown' : 'mouseup';
              const js = `(function(){try{const el=document.elementFromPoint(${x},${y});if(!el)return;const o={bubbles:true,cancelable:true,clientX:${x},clientY:${y},button:0,view:window};el.dispatchEvent(new MouseEvent('${type}',o));el.dispatchEvent(new PointerEvent('pointer${type === 'mousedown' ? 'down' : 'up'}',o));if('${type}'==='mouseup'){el.dispatchEvent(new MouseEvent('click',o));}}catch(e){}})()`;
              this.controller.runJavaScript(js).catch((): void => {});
            }
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
  }
}
