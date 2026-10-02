// deepDesign 前端 Tauri 兼容垫片 —— 在页面脚本执行前注入（javaScriptOnDocumentStart）
// 作用：
//   1. 构造 window.__TAURI__（core.invoke / window 控制 / event.listen），
//      使原版前端以 IS_TAURI=true 的原生模式启动，UI/交互与桌面版一致；
//   2. invoke 走 harmonyBridge.invokeAsync(rid, cmd, argsJson)（ArkTS 分发：
//      文件/设置/HTTP 走 OHOS 原生实现，引擎/加密走 NAPI core），结果经
//      window.__harmony.resolve(rid, ok, json) 回投。
(function () {
  'use strict';
  if (window.__TAURI__) return; // 真 Tauri 环境（桌面）不注入

  // PC 视口修正：原版为桌面页面无 viewport meta。ArkWeb 的 devicePixelRatio
  // 与系统 density 不一致，device-width 会被二次缩放——改由宿主把窗口实际
  // vp 宽写入 __DD_VIEWPORT_W__（shim 注入前替换占位符），viewport 固定为
  // 该值：1 CSS px = 1 vp（无缩放，字体/图标原生大小）；窄于该值的窗口
  // 横向滚动（桌面浏览器自然行为），绝不压缩。
  document.documentElement.classList.add('harmony');
  function hideWinctl() {
    try {
      var css = document.createElement('style');
      // 系统标题栏负责窗口控制——前端顶栏 — □ × 隐藏（仅鸿蒙）。
      // 双保险：UA 已不含 Linux/Win 标识（IS_LINUX/IS_WIN=false，
      // winctl 默认 display:none），此 CSS 兜底。
      css.textContent = 'html.harmony .winctl{display:none!important}';
      (document.head || document.documentElement).appendChild(css);
    } catch (e) {}
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', hideWinctl);
  } else {
    hideWinctl();
  }
  try {
    var w = window.__DD_VIEWPORT_W__ || 960;
    var m = document.createElement('meta');
    m.setAttribute('name', 'viewport');
    m.setAttribute('content', 'width=' + w + ', initial-scale=1');
    (document.head || document.documentElement).appendChild(m);
  } catch (e) {}

  var seq = 0;
  var pending = {};            // rid -> resolve
  var listeners = {};          // event -> [fn]

  function emit(event, payloadJson) {
    var arr = listeners[event];
    if (!arr) return;
    var payload = null;
    try { payload = payloadJson ? JSON.parse(payloadJson) : null; } catch (e) { payload = null; }
    for (var i = 0; i < arr.length; i++) {
      try { arr[i]({ payload: payload, id: String(seq++), event: event }); } catch (e) {}
    }
  }

  window.__harmony = {
    // ArkTS 回投：结果（InvokeResult JSON：{ok,payload?,error?}）
    resolve: function (rid, ok, payloadJson) {
      var p = pending[rid];
      if (!p) return;
      delete pending[rid];
      if (ok) {
        var v = null;
        try { v = payloadJson ? JSON.parse(payloadJson) : null; } catch (e) { v = null; }
        p(v);
      } else {
        p(new Error(payloadJson || 'bridge error'));
      }
    },
    // ArkTS 回投：后端事件
    emit: emit
  };

  function callNative(cmd, args) {
    return new Promise(function (resolve, reject) {
      var rid = 'r' + (++seq);
      pending[rid] = function (v) {
        if (v instanceof Error) reject(v); else resolve(v);
      };
      if (window.harmonyBridge && window.harmonyBridge.invokeAsync) {
        window.harmonyBridge.invokeAsync(rid, cmd, JSON.stringify(args || {}));
      } else {
        reject(new Error('bridge not ready'));
      }
    });
  }

  var currentWindow = {
    minimize: function () { if (window.harmonyBridge) window.harmonyBridge.win('minimize'); },
    maximize: function () { if (window.harmonyBridge) window.harmonyBridge.win('maximize'); },
    close: function () { if (window.harmonyBridge) window.harmonyBridge.win('close'); },
    // decor 隐藏后的桌面手感：顶栏空白区拖动 = 移动窗口；双击 = 最大化切换
    startDragging: function () { if (window.harmonyBridge) window.harmonyBridge.win('move'); },
    setTitle: function (t) { document.title = t; if (window.harmonyBridge) window.harmonyBridge.win('title:' + t); },
    show: function () {}, hide: function () {}, destroy: function () {},
    setFullscreen: function () {}, isFullscreen: function () { return Promise.resolve(false); },
    innerPosition: function () { return Promise.resolve({}); },
    onResized: function () { return Promise.resolve(); },
    listen: function (ev, fn) { return Promise.resolve(function () {}); }
  };

  window.__TAURI__ = {
    core: {
      invoke: function (cmd, args) { return callNative(cmd, args); },
      convertFileSrc: function (p) { return p; }
    },
    window: {
      getCurrentWindow: function () { return currentWindow; },
      getCurrent: function () { return currentWindow; }
    },
    event: {
      listen: function (event, fn) {
        (listeners[event] = listeners[event] || []).push(fn);
        return Promise.resolve(function () {
          var a = listeners[event] || [];
          var i = a.indexOf(fn);
          if (i >= 0) a.splice(i, 1);
        });
      },
      emit: function (event, payload) { emit(event, JSON.stringify(payload || null)); }
    },
    path: { appDataDir: function () { return Promise.resolve('/data/storage/'); } }
  };

  // 原生模式标记（前端据此启用 native UI）
  window.__HARMONY__ = true;

  // ---- 顶栏原生窗口手感（decor 隐藏后）----
  // 顶栏空白区：mousedown 拖动 = 移动窗口；双击 = 最大化切换。
  // 只挂在 .topbar 空白区（target 直命中 topbar 本身，避开按钮/输入）。
  function setupTopbarDragging() {
    var tb = document.querySelector('.topbar, header, #topbar');
    if (!tb) { setTimeout(setupTopbarDragging, 500); return; }
    var lastClick = 0;
    tb.addEventListener('mousedown', function (e) {
      if (e.button !== 0) return;
      // 只在直接点中顶栏容器（非子控件）时生效
      if (e.target !== tb) return;
      var now = Date.now();
      if (now - lastClick < 350) {
        // 双击：最大化切换
        if (window.harmonyBridge) window.harmonyBridge.win('maximize');
        lastClick = 0;
        return;
      }
      lastClick = now;
      if (window.harmonyBridge) window.harmonyBridge.win('move');
    });
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', setupTopbarDragging);
  } else {
    setupTopbarDragging();
  }
})();
