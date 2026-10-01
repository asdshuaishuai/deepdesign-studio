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
})();
