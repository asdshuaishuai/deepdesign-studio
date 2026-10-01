// deepDesign 鸿蒙版 —— ArkWeb 承载原版前端（UI/交互与桌面版一字不差）
//
// 架构：原生壳（窗口/生命周期）+ ArkWeb（frontend/index.html 全量渲染）
//   + invoke 管线（window.__TAURI__ → harmonyBridge → Dispatch/NAPI core）
// 前端以 IS_TAURI=true 原生模式启动：invoke 命令经 shim 进 ArkTS，
// 引擎/加密类命令走 Rust NAPI core，系统能力走 OHOS 原生实现。
import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { harmonyBridge } from '../invoke/Bridge';
import { coreVersion, ddpEncrypt, ddpDecrypt } from '../core/CoreBridge';
import { probeLocalAi } from '../ai/LocalChatProbe';

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
  private abilityCtx: common.UIAbilityContext | null = null;
  @State shimJs: string = '';
  @State probeInfo: string = '';
  coreTag: string = '';
  winObj: window.Window | null = null;

  aboutToAppear(): void {
    // getContext 已弃用 → getUIContext().getHostContext()；缓存供拦截器复用
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.abilityCtx = ctx;
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
    // 原生输入浮层（web 输入元素被点中时接替，规避 web IME 渲染挂起）
    harmonyBridge.setNativeInputHandler((x: number, y: number, current: string): void => {
      console.error('[native-input] hit ' + x + ',' + y);
      this.inputTargetX = x;
      this.inputTargetY = y;
      this.nativeInputText = current;
      this.showNativeInput = true;
    });
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
    // 系统级端侧 AI（localChatModel）就绪探测——Agent 默认执行者可用性
    probeLocalAi().then((ok: boolean): void => {
      this.coreTag += ok ? ' · 端侧AI:就绪' : ' · 端侧AI:不可用';
      console.error('[local-ai] ready=' + ok);
      this.showBadge(this.coreTag, ok ? 8000 : 0);  // 正常 8s 自隐；异常常驻可点掉
    });
  }

  /** 状态徽章：右上角小字（不遮挡顶栏操作区），点击消失；诊断默认 8s 自动隐藏 */
  private showBadge(text: string, autoHideMs: number = 0): void {
    const js = `(function(){try{
      var old=document.getElementById('harmony-badge');if(old){old.remove();}
      var b=document.createElement('div');b.id='harmony-badge';
      b.style.cssText='position:fixed;top:38px;right:10px;font-size:10px;color:#6b6b70;background:rgba(255,255,255,0.9);border:1px solid rgba(0,0,0,0.08);padding:2px 8px;border-radius:8px;z-index:2147483647;max-width:46vw;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;box-shadow:0 1px 4px rgba(0,0,0,0.12)';
      b.textContent=${JSON.stringify(text)};
      b.onclick=function(){b.remove();};
      document.body.appendChild(b);
      if(${autoHideMs}>0){setTimeout(function(){var e=document.getElementById('harmony-badge');if(e)e.remove();},${autoHideMs});}
    }catch(e){}})()`;
    this.controller.runJavaScript(js).catch((): void => {});
  }

  private maximized: boolean = false;
  // 原生输入浮层状态（IME 黑屏规避）
  @State showNativeInput: boolean = false;
  @State nativeInputText: string = '';
  private inputTargetX: number = 0;
  private inputTargetY: number = 0;
  private inputController: TextInputController = new TextInputController();

  /** 浮层提交：写回 web 输入元素（native setter + input 事件），execute 时派发 Enter */
  private submitNativeInput(execute: boolean): void {
    const x = this.inputTargetX;
    const y = this.inputTargetY;
    const val = this.nativeInputText;
    this.showNativeInput = false;
    const escaped = JSON.stringify(val);
    const js = `(function(){try{
      var el=document.elementFromPoint(${x},${y});
      if(!el){var g=document.getElementById('gp-input');el=g||el;}
      if(!el)return;
      var proto=el.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;
      var setter=Object.getOwnPropertyDescriptor(proto,'value').set;
      setter.call(el,${escaped});
      el.dispatchEvent(new Event('input',{bubbles:true}));
      el.dispatchEvent(new Event('change',{bubbles:true}));
      if(${execute ? 'true' : 'false'}){
        var kd=new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true,cancelable:true});
        el.dispatchEvent(kd);
      }
    }catch(e){}})()`;
    this.controller.runJavaScript(js).catch((): void => {});
  }

  private onWin(action: string): void {
    const w = this.winObj;
    if (!w) return;
    if (action === 'minimize') {
      w.minimize();
    } else if (action === 'close') {
      w.destroyWindow().catch(() => {});
    } else if (action === 'move') {
      // 顶栏空白区拖动热区：交给系统窗口管理（decor 隐藏后的原生手感）
      w.startMoving().catch((): void => {});
    } else if (action === 'maximize') {
      // 前端顶栏 □ 按钮：自由窗口最大化 ↔ 还原（系统语义，不碎裂）
      this.maximized = !this.maximized;
      if (this.maximized) {
        w.maximize(window.MaximizePresentation.EXIT_IMMERSIVE).catch((): void => {});
      } else {
        w.restore().then((): void => {
          w.resize(1360, 900);
        }).catch((): void => {});
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
          .darkMode(WebDarkMode.Auto)
          .forceDarkAccess(false)
          .verticalScrollBarAccess(true)
          .horizontalScrollBarAccess(false)
          .overScrollMode(OverScrollMode.NEVER)
          .javaScriptProxy({
            object: harmonyBridge,
            name: 'harmonyBridge',
            methodList: ['invokeAsync', 'win', 'onEvent', 'nativeInput'],
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
              const ctx = this.abilityCtx;
              if (!ctx) return null;
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
            // 就绪状态采集（只读）+ 徽章首显（探测完成后更新内容）
            const probe = `JSON.stringify({tauri: !!window.__TAURI__, bridge: !!(window.harmonyBridge&&window.harmonyBridge.invokeAsync), eng: (document.getElementById('eng-dot')||{}).className, qs: typeof quickStart})`;
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
              const tp = (e.touches.length > 0) ? e.touches[0] : e.changedTouches[0];
              if (!tp) return;
              const x = Math.round(tp.x);
              const y = Math.round(tp.y);
              const type = e.type === TouchType.Down ? 'mousedown' : 'mouseup';
              // vp → web CSS 坐标换算：web 的 CSS viewport 与组件 vp 宽解耦
              //（窄窗口仍渲染桌面布局），须按 clientWidth 比例缩放
              let vpW = 960;
              try {
                const rect = this.winObj?.getWindowProperties().windowRect;
                const d = display.getDefaultDisplaySync().densityPixels;
                if (rect && d > 0) { vpW = rect.width / d; }
              } catch (err) { /* 默认 960vp */ }
              // 输入元素不转发点击（web IME 在部分形态会挂起渲染）——改走原生输入浮层；
              // 其余元素正常合成鼠标事件
              const js = `(function(){try{var s=document.documentElement.clientWidth/${vpW};var x=Math.round(${x}*s),y=Math.round(${y}*s);var el=document.elementFromPoint(x,y);if(!el)return;var t=(el.tagName||'').toUpperCase();if(t==='INPUT'||t==='TEXTAREA'||el.isContentEditable){if(window.harmonyBridge&&window.harmonyBridge.nativeInput){window.harmonyBridge.nativeInput(x,y,String(el.value||el.placeholder||''));}return;}var o={bubbles:true,cancelable:true,clientX:x,clientY:y,button:0,view:window};el.dispatchEvent(new MouseEvent('${type}',o));el.dispatchEvent(new PointerEvent('pointer${type === 'mousedown' ? 'down' : 'up'}',o));if('${type}'==='mouseup'){el.dispatchEvent(new MouseEvent('click',o));}}catch(e){}})()`;
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

      // ---- 原生输入浮层（IME 黑屏规避：web 输入元素由原生接替）----
      if (this.showNativeInput) {
        Column() {
          Row() {
            Text('输入').fontSize(13).fontWeight(600).fontColor('#1c1c1e')
            Blank()
            Text('Enter 执行 · Shift+Enter 换行').fontSize(9).fontColor('#8e8e93')
          }.width('100%')
          TextInput({ text: this.nativeInputText, controller: this.inputController,
              placeholder: '输入内容…' })
            .fontSize(13)
            .height(40)
            .backgroundColor('#ffffff')
            .borderRadius(8)
            .border({ width: 1, color: 'rgba(0,0,0,0.12)' })
            .onChange((v: string): void => { this.nativeInputText = v; })
            .onSubmit((): void => this.submitNativeInput(true))
            .defaultFocus(true)
          Row({ space: 8 }) {
            Button('取消')
              .fontSize(12).height(32).backgroundColor('#ffffff').fontColor('#1c1c1e')
              .borderRadius(6).border({ width: 1, color: 'rgba(0,0,0,0.12)' })
              .onClick((): void => { this.showNativeInput = false; })
            Button('填入')
              .fontSize(12).height(32).backgroundColor('#f0f0f2').fontColor('#1c1c1e')
              .borderRadius(6)
              .onClick((): void => this.submitNativeInput(false))
            Button('⏎ 执行')
              .fontSize(12).height(32).backgroundColor('#9d4edd').fontColor('#ffffff')
              .borderRadius(6)
              .onClick((): void => this.submitNativeInput(true))
          }.width('100%').margin({ top: 8 }).justifyContent(FlexAlign.End)
        }
        .width('46%')
        .padding(12)
        .backgroundColor('rgba(250,250,252,0.98)')
        .borderRadius(12)
        .border({ width: 1, color: 'rgba(0,0,0,0.10)' })
        .shadow({ radius: 16, color: 'rgba(0,0,0,0.18)' })
        .position({ x: '27%', y: '58%' })
      }
    }
    .width('100%').height('100%').backgroundColor('#f4f4f6')
  }
}
