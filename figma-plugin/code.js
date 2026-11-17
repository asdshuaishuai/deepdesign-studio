// deepDesign Bridge — Figma 双向插件
// Import：读 deepdesign.json（deepDesign 导出包）→ 逐板建真实可编辑 Figma Frame。
// Export：把当前页选区序列化成 deepDesign 节点 JSON → 下载，供 deepDesign 导入落画布。
// 纯手工节点映射，零网络（manifest networkAccess=["none"]）。

figma.showUI(__html__, { width: 360, height: 420 });

figma.ui.onmessage = async (msg) => {
  if (msg.type === 'import') {
    const data = msg.data; // { boards: [{ id, name, width, height, background, nodes: [...] }] }
    const root = figma.currentPage;
    let made = 0;
    for (const b of data.boards || []) {
      const frame = figma.createFrame();
      frame.name = b.name || b.id;
      frame.x = 100 + (made % 4) * ((b.width || 390) + 80);
      frame.y = 100 + Math.floor(made / 4) * ((b.height || 844) + 80);
      frame.resize(b.width || 390, b.height || 844);
      frame.fills = [{ type: 'SOLID', color: hexToRgb(b.background || '#FFFFFF') }];
      let placed = 0;
      for (const n of b.nodes || []) {
        if (n.style && n.style.visible === false) continue;
        const node = makeNode(n);
        if (node) { frame.appendChild(node); placed++; }
      }
      root.appendChild(frame);
      made++;
      figma.currentPage.selection = [frame];
      figma.viewport.scrollAndZoomIntoView([frame]);
      figma.notify('deepDesign: ' + (b.name || b.id) + ' — ' + placed + ' 节点');
    }
    figma.notify('deepDesign: 导入完成 ' + made + ' 板');
    return;
  }
  if (msg.type === 'export-selection') {
    const sel = figma.currentPage.selection;
    const out = [];
    function walk(node, depth) {
      if (depth > 6) return;
      const isText = node.type === 'TEXT';
      const item = {
        id: node.id,
        component: isText ? 'body_text' : 'card',
        x: Math.round(node.x), y: Math.round(node.y),
        w: Math.round(node.width), h: Math.round(node.height),
        text: isText ? node.characters : '',
        style: {
          fill: node.fills && node.fills[0] && node.fills[0].type === 'SOLID'
            ? rgbToHex(node.fills[0].color) : '#FFFFFF',
          text_color: isText && node.fills[0] && node.fills[0].type === 'SOLID'
            ? rgbToHex(node.fills[0].color) : '#14201A',
          font_size: isText ? Math.round(node.fontSize) : 14,
          radius: node.cornerRadius !== undefined && typeof node.cornerRadius === 'number'
            ? Math.round(node.cornerRadius) : 8,
          opacity: node.opacity !== undefined ? node.opacity : 1,
          visible: node.visible !== false,
        },
      };
      out.push(item);
      if ('children' in node) for (const c of node.children) walk(c, depth + 1);
    }
    const target = sel.length ? sel : figma.currentPage.children;
    for (const n of target) if ('width' in n) walk(n, 0);
    figma.ui.postMessage({ type: 'export-done', json: JSON.stringify({ boards: [{ id: 'figma', name: 'Figma 导入', width: 1440, height: 900, nodes: out }] }, null, 1) });
  }
};

// 引擎 manifest 的几何在 n.rect（{x,y,w,h}），不是顶层字段——
// 顶层读取曾让所有导入图层塌到 (0,0)（NoNDesign 实证，同构保留）。
function geomOf(n) {
  const r = n.rect || n;
  return {
    x: typeof r.x === 'number' ? r.x : 0,
    y: typeof r.y === 'number' ? r.y : 0,
    w: typeof r.w === 'number' && r.w > 0 ? r.w : 100,
    h: typeof r.h === 'number' && r.h > 0 ? r.h : 40,
  };
}

function makeNode(n) {
  const st = n.style || {};
  const g = geomOf(n);
  const txt = (n.text || '').trim();
  const isPlain = n.kind === 'text' || n.component === 'body_text' || n.component === 'heading';
  if (isPlain && txt) {
    const t = figma.createText();
    t.characters = txt;
    t.fontSize = st.font_size || 14;
    t.fills = [{ type: 'SOLID', color: hexToRgb(st.text_color || '#14201A') }];
    t.x = g.x; t.y = g.y;
    try { t.resize(g.w, g.h); } catch (e) {}
    return t;
  }
  if (txt) {
    // 带文案的实体组件（按钮/chip…）：Frame 底色 + Text 子节点，两个都真实可编辑。
    const f = figma.createFrame();
    f.x = g.x; f.y = g.y;
    f.resize(g.w, g.h);
    f.cornerRadius = normRadius(st.radius, g);
    f.fills = [{ type: 'SOLID', color: hexToRgb(normFill(st.fill)) }];
    const t = figma.createText();
    t.characters = txt;
    t.fontSize = st.font_size || 14;
    t.fills = [{ type: 'SOLID', color: hexToRgb(st.text_color || '#14201A') }];
    f.appendChild(t);
    t.x = Math.max(0, (g.w - t.width) / 2);
    t.y = Math.max(0, (g.h - t.height) / 2);
    return f;
  }
  const r = figma.createRectangle();
  r.resize(g.w, g.h);
  r.x = g.x; r.y = g.y;
  r.cornerRadius = normRadius(st.radius, g);
  r.fills = [{ type: 'SOLID', color: hexToRgb(normFill(st.fill)) }];
  return r;
}

// 圆角钳制（与引擎 norms 同语义）：999=胶囊 → min(w,h)/2；其余夹 min(w,h)/2
function normRadius(radius, g) {
  const cap = Math.min(g.w, g.h) / 2;
  const r = radius >= 999 ? cap : Math.min(radius || 0, cap);
  return Math.max(0, r);
}
// fill 缺省/非 hex（"none" 等）→ 浅灰兜底
function normFill(fill) {
  return fill && fill[0] === '#' ? fill : '#EDEDF2';
}

function hexToRgb(hex) {
  hex = (hex || '#FFFFFF').replace('#', '');
  if (hex.length === 3) hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2];
  const n = parseInt(hex, 16) || 0;
  return { r: ((n >> 16) & 255) / 255, g: ((n >> 8) & 255) / 255, b: (n & 255) / 255 };
}
function rgbToHex(c) {
  const h = (v) => Math.round(v * 255).toString(16).padStart(2, '0');
  return '#' + h(c.r) + h(c.g) + h(c.b);
}
