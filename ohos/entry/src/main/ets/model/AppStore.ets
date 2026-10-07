// deepDesign 数据模型 —— 与通用版（桌面）状态语义 1:1 对齐的 ArkTS 复刻
// 模板种子对齐原版 TPLS ×14；元素属性对齐原版 inspector 字段；
// 命令流时间线对齐 tl-run 条目；撤销栈对齐 undo 语义。

import { MbtDoc, MbtLayer, MbtFlow } from './MbtDoc';

export interface ElStyle {
  x: number; y: number; w: number; h: number;
  text: string;
  fill: string;          // 填充
  color: string;         // 文字色
  fontSize: number;
  radius: number;
  opacity: number;
  visible: boolean;
  align: string;         // left | center | right
  bold: boolean;
  shadow: string;        // none | sm | lg | xl（batch-5 补顶档 xl；保留 sm/lg 存量值不破坏旧文件——
                         // 桌面命名 e1-e3 差异见 detail-gap-matrix gap-detail-12；batch-10 方案
                         // 定案：「解析归一（batch-5 捕获）+ 渲染单值域」——渲染器只认本值域，
                         // 未知值一律降级 none 不静默错渲（Index.shadowOf 消费））
  dash: string;          // 线型三态：'solid' | 'dashed' | 'dotted'（batch-5 由 boolean 升级；
                         // 旧文件 boolean 经 normalizeLayers 归一 true→'dashed'）
  italic: boolean;       // 斜体
  widthMode: string;     // fixed | hug | fill（hug 在子元素模型落地前按 fixed 呈现）
  layout: string;        // none | vertical | horizontal（子元素模型落地前落数据）
  justify: string;       // start | center | end（batch-5 布局对齐，gap-detail-12；渲染消费登记
                         // 缓做——子元素模型未落地，与 layout/gap/padding 同口径数据先行）
  gap: number;           // 容器间距
  padding: number;       // 容器内边距
  stroke: string;        // 描边色（batch-3 数据面，gap-detail-7；缺省 'none' = 未设——渲染回退
                         // 各类型既有缺省：input 1px 弱边框 / btn·rect 无描边；线框档不受此字段
                         // 影响，仍走强制 #9aa4b2/1（i:627-628）。inspector 描边 UI 行归 batch-5）
  strokeWidth: number;   // 描边宽（batch-3 数据面；缺省 0 = 未设，语义同上）
}

export interface LayerNode {
  id: string;
  name: string;
  type: string;          // frame | text | input | btn | image | rect
  style: ElStyle;
  interactions?: Interaction[];  // 交互绑定（gap-right-3）
  states?: StateDef[];           // 组件状态定义（gap-right-3，演示消费待引擎回收）
}

// 交互绑定：触发器 × 动作 × 目标（navigate_to=boardId / show_toast=文案 / back=''）
export interface Interaction {
  trigger: string;
  action: string;
  target: string;
}

export interface StateDef {
  name: string;
}

/** 画板（@Observed 类，字段不变）：r4 起 rev 由画布 ForEach 键消费（`${b.id}|${docEpoch}|${rev}`，
 * op 后键跳变 → 板卡重建刷新）；@Observed 装饰保留（代理面无害，rehydrateBoard 语义不变）。
 * layers 保持普通引用。JSON 反序列化产普通对象、无观察面，必须经 rehydrateBoard 重建类实例。 */
@Observed
export class Board {
  id: string = '';
  name: string = '';
  kind: string = '';     // mobile | web | pc | adaptive
  width: number = 0;
  height: number = 0;
  rev: number = 0;
  layers: LayerNode[] = [];

  constructor(id: string = '', name: string = '', kind: string = '', width: number = 0,
    height: number = 0, rev: number = 0, layers: LayerNode[] = []) {
    this.id = id;
    this.name = name;
    this.kind = kind;
    this.width = width;
    this.height = height;
    this.rev = rev;
    this.layers = layers;
  }
}

/** JSON 解析目标形状（Board 的裸字段版；ArkTS 类实例不能用对象字面量赋值，
 * JSON.parse 产物先按此形状收窄再 rehydrate）。 */
interface BoardRaw {
  id: string;
  name: string;
  kind: string;
  width: number;
  height: number;
  rev: number;
  layers: LayerNode[];
}

const EMPTY_LAYERS: LayerNode[] = [];

/** 普通对象 → @Observed Board 类实例（浅拷贝；layers 普通引用）。restore/undo/redo/
 * duplicateBoard 的 JSON.parse 产物都必须过此函数（r4 起 @Observed 代理面统一由 rehydrate
 * 重建——普通对象不经 rehydrate 直接入档是历史多板丢 body 事故的前体）。 */
function rehydrateBoard(raw: BoardRaw): Board {
  const b = new Board();
  b.id = raw.id;
  b.name = raw.name;
  b.kind = raw.kind;
  b.width = raw.width;
  b.height = raw.height;
  b.rev = raw.rev;
  b.layers = Array.isArray(raw.layers) ? normalizeLayers(raw.layers) : EMPTY_LAYERS;
  return b;
}

function rehydrateBoards(list: BoardRaw[]): Board[] {
  return list.map((raw: BoardRaw): Board => rehydrateBoard(raw));
}

export interface TlEntry {
  src: string;           // HUMAN | AGENT | TEMPLATE
  op: string;
  rev: number;
  ms: number;
  ok: boolean;
}

// 交互流（gap-canvas-6）：源板某节点 → 目标板。trigger 当前仅 tap（桌面触发器族归 gap-right-3）。
// 持久化（gap-canvas-9）：SerDoc v2 载荷带 flows 字段；v1 旧文件无该字段，restore 按
// Array.isArray 区分——无字段即清空，语义与旧版一致（SER_PREFIX 前缀不变，仅标识 interim 容器）。
export interface Flow {
  id: string;
  fromBoard: string;
  fromNode: string;
  toBoard: string;
  trigger: string;
}

/** canonical 展示投影的归并流条目（gap-mbt-2）：flows 显式连线与 layers 的 navigate_to
 * 绑定统一成 from/to/node 三元组后进 frontmatter flows: 列表（Flow.id 为会话内句柄，
 * canonical 不落）。 */
interface CanonFlow {
  from: string;
  to: string;
  node: string;
}

// 组件快照条目（gap-leftcomp-1）——字段结构对 rawfile/vendor/components.json 实测
// （65 项，六字段齐全；kind ∈ frame|image|rect|text；id 全 ASCII snake_case）。
export interface CompDef {
  id: string;
  kind: string;            // frame | image | rect | text
  category: string;
  variants: string[];
  default_size: number[];  // [w, h]
  description: string;
}

// interim 持久化格式（gap-topbar-1）：
// serialize() 产物 = SER_PREFIX + SerDoc JSON。这是**鸿蒙 interim 明文**而非 canonical mbt，
// 与桌面版 .ddp（canonical mbt 明文）双向不可互解（时间窗与缓解登记见移植计划 dropped 节）。
// 前缀让引擎宿主下沉后的代码可识别旧 interim 文件并提示重建/迁移；打开无前缀文件时
// 上层按「桌面版文件暂不支持」诚实报错（Index.finishOpen）。
export const SER_PREFIX: string = 'DDP-INTERIM-v1\n';

export interface SerDoc {
  projectName: string;
  boards: BoardRaw[];   // 解析目标为裸字段形状；serialize 侧 Board[] 结构兼容直接赋值
  flows?: Flow[];   // v2 载荷（gap-canvas-9）：v1 旧文件无该字段，restore 按 Array.isArray 兼容
  ink?: InkDoc;     // batch-10（spec-ink-1）演示批注墨迹：v1/v2 旧文件无字段兼容（照 flows 先例）
}

/** 演示批注墨迹（batch-10，spec-ink-1）：坐标归一化 0–1（4 位小数，缩放/换屏重放不糊）。 */
export interface InkDoc {
  v: number;              // 1
  strokes: number[][][];  // 每笔画为点列 [[x,y],…]
}

// 撤销/重做快照（gap-canvas-9）：boards 与 flows 双字段，undo/redo 双回放
// （解析目标为 BoardRaw——JSON.parse 产普通对象，回放经 rehydrateBoards 重建观察面）
interface UndoSnap {
  boards: BoardRaw[];
  flows: Flow[];
}

// ===== 14 模板（对齐原版 TPLS/TPL_SIZE/TPL_GROUPS）=====
export interface TplDef { tid: string; name: string; kind: string; }
export const TPLS: TplDef[] = [
  { tid: 'login', name: '登录页', kind: 'mobile' },
  { tid: 'signup', name: '注册页', kind: 'mobile' },
  { tid: 'dashboard', name: '仪表盘', kind: 'mobile' },
  { tid: 'profile', name: '个人主页', kind: 'mobile' },
  { tid: 'settings', name: '设置页', kind: 'mobile' },   // iss-3：tid 原 'settings_page' → 'settings'
                                                         // 对齐引擎注册表（src-tauri/src/agent.rs:52-54
                                                         // ENGINE_TEMPLATES）；显示名 '设置页' 保留。
                                                         // persist SerDoc 存 boards 不存 tid，存量
                                                         // .ddp 无兼容影响；时间线 op 随 addBoard
                                                         // 自然落引擎注册 id settings
  { tid: 'list_detail', name: '列表-详情', kind: 'mobile' },
  { tid: 'onboarding', name: '引导页', kind: 'mobile' },
  { tid: 'empty_state', name: '空状态页', kind: 'mobile' },
  { tid: 'web_landing', name: 'Web 落地页', kind: 'web' },
  { tid: 'web_login', name: 'Web 登录', kind: 'web' },
  { tid: 'web_dashboard', name: 'Web 仪表盘', kind: 'web' },
  { tid: 'pc_app', name: 'PC 桌面应用', kind: 'pc' },
  { tid: 'adaptive_landing', name: '自适应落地页', kind: 'adaptive' },
  { tid: 'login_v2', name: '登录页 v2', kind: 'adaptive' }
];
export class TplSize {
  static of(kind: string): number[] {
    if (kind === 'mobile') return [390, 844];
    return [1280, 800];
  }
}
export const TPL_FEATURED: string[] = ['web_login', 'adaptive_landing', 'login'];
export const TPL_GROUPS: string[][] = [
  ['mobile', '手机原型'], ['web', 'Web 页面'], ['pc', '桌面 / 自适应']
];

// 显式构造（ArkTS 对象字面量受限）
function st(x: number, y: number, w: number, h: number, text: string, fill: string,
  color: string, fontSize: number, radius: number, opacity: number, visible: boolean,
  align: string, bold: boolean, shadow: string, dash: string, italic: boolean,
  widthMode: string, layout: string, gap: number, padding: number,
  stroke: string = 'none', strokeWidth: number = 0, justify: string = 'start'): ElStyle {
  return {
    x: x, y: y, w: w, h: h, text: text, fill: fill, color: color,
    fontSize: fontSize, radius: radius, opacity: opacity, visible: visible,
    align: align, bold: bold, shadow: shadow, dash: dash, italic: italic,
    widthMode: widthMode, layout: layout, gap: gap, padding: padding,
    stroke: stroke, strokeWidth: strokeWidth, justify: justify
  };
}

function defStyle(): ElStyle {
  return st(0, 0, 120, 18, '', '#f0f0f3', '#1c1c1e', 12, 4, 1, true, 'left', false,
    'none', 'solid', false, 'fixed', 'none', 0, 0, 'none', 0, 'start');
}

/** 层数据面归一（r3 抢修缺口 1 数据面兜底 + batch-5 dash 三态），restore/undo/redo 共用：
 * 1) 非对象/无 id 的脏条目剔除——JSON 反序列化产物不保证形状（同 layerInteractions 的
 *    Array.isArray 防御教训），残条目会让渲染路径（elNode 的 keyGenerator/visible 门）读
 *    字段抛 TypeError → 整板元素渲染中断（多板丢 body 的同型前体）；
 * 2) style 缺失/非对象补 defStyle——全部 '.style' 访问链（keyGenerator、elNode、inspector、
 *    手势回调）从此不可能撞 null/undefined；
 * 3) 旧文件 dash boolean 归一 true→'dashed'、false→'solid'（v1 存量 .ddp 直开兼容）。
 * 运行时旧值是 boolean、静态类型 string，经 Object 中转判型。 */
function normalizeLayers(layers: LayerNode[]): LayerNode[] {
  const out: LayerNode[] = [];
  for (const l of layers) {
    if (l === null || l === undefined || typeof l !== 'object' || typeof l.id !== 'string') {
      continue;
    }
    if (l.style === null || l.style === undefined || typeof l.style !== 'object') {
      l.style = defStyle();
    }
    const dv: Object = l.style.dash;
    if (typeof dv === 'boolean') {
      const legacy: boolean = dv as boolean;
      l.style.dash = legacy ? 'dashed' : 'solid';
    }
    out.push(l);
  }
  return out;
}

function mkLayer(id: string, name: string, type: string, s: PartialEl): LayerNode {
  const d = defStyle();
  const o: ElStyle = {
    x: s.x ?? d.x, y: s.y ?? d.y, w: s.w ?? d.w, h: s.h ?? d.h,
    text: s.text ?? d.text, fill: s.fill ?? d.fill, color: s.color ?? d.color,
    fontSize: s.fontSize ?? d.fontSize, radius: s.radius ?? d.radius,
    opacity: s.opacity ?? d.opacity, visible: s.visible ?? d.visible,
    align: s.align ?? d.align, bold: s.bold ?? d.bold,
    shadow: s.shadow ?? d.shadow, dash: s.dash ?? d.dash, italic: s.italic ?? d.italic,
    widthMode: s.widthMode ?? d.widthMode, layout: s.layout ?? d.layout,
    gap: s.gap ?? d.gap, padding: s.padding ?? d.padding,
    stroke: s.stroke ?? d.stroke, strokeWidth: s.strokeWidth ?? d.strokeWidth,
    justify: s.justify ?? d.justify
  };
  return { id: id, name: name, type: type, style: o };
}

interface PartialEl {
  x?: number; y?: number; w?: number; h?: number; text?: string;
  fill?: string; color?: string; fontSize?: number; radius?: number;
  opacity?: number; visible?: boolean; align?: string; bold?: boolean;
  shadow?: string; dash?: string; italic?: boolean; widthMode?: string;
  layout?: string; gap?: number; padding?: number;
  stroke?: string; strokeWidth?: number;
  justify?: string;
}

// 模板种子文档（结构与原版 wasm template op 产出对齐）
function seedLayers(tid: string, w: number): LayerNode[] {
  const cx = w / 2;
  const loginSeeds = (): LayerNode[] => [
    mkLayer('logo', 'logo', 'image', { x: cx - 14, y: 64, w: 28, h: 28, radius: 14, fill: '#e8e8ec' }),
    mkLayer('welcome_title', 'welcome_title', 'text', { x: cx - 80, y: 120, w: 160, h: 20, text: 'Welcome Back', fontSize: 17, bold: true, align: 'center' }),
    mkLayer('welcome_sub', 'welcome_sub', 'text', { x: cx - 90, y: 146, w: 180, h: 14, text: 'Sign in to continue', fontSize: 11, color: '#8e8e93', align: 'center' }),
    mkLayer('email_input', 'email_input', 'input', { x: cx - 130, y: 200, w: 260, h: 34, text: 'Email address', color: '#aeaeb2' }),
    mkLayer('pwd_input', 'pwd_input', 'input', { x: cx - 130, y: 244, w: 260, h: 34, text: 'Password', color: '#aeaeb2' }),
    mkLayer('login_btn', 'login_btn', 'btn', { x: cx - 130, y: 300, w: 260, h: 38, text: 'Sign In', fill: '#007aff', color: '#ffffff', radius: 8 }),
    mkLayer('create_link', 'create_link', 'text', { x: cx - 70, y: 352, w: 140, h: 14, text: 'Create Account', fontSize: 11, color: '#007aff', align: 'center' })
  ];
  const signupSeeds = (): LayerNode[] => [
    mkLayer('logo', 'logo', 'image', { x: cx - 14, y: 64, w: 28, h: 28, radius: 14, fill: '#e8e8ec' }),
    mkLayer('title', 'title', 'text', { x: cx - 90, y: 120, w: 180, h: 20, text: 'Create Account', fontSize: 17, bold: true, align: 'center' }),
    mkLayer('subtitle', 'subtitle', 'text', { x: cx - 100, y: 146, w: 200, h: 14, text: 'Sign up to get started', fontSize: 11, color: '#8e8e93', align: 'center' }),
    mkLayer('name_input', 'name_input', 'input', { x: cx - 130, y: 196, w: 260, h: 32, text: 'Full name', color: '#aeaeb2' }),
    mkLayer('email_input', 'email_input', 'input', { x: cx - 130, y: 236, w: 260, h: 32, text: 'Email address', color: '#aeaeb2' }),
    mkLayer('pwd_input', 'pwd_input', 'input', { x: cx - 130, y: 276, w: 260, h: 32, text: 'Password', color: '#aeaeb2' }),
    mkLayer('signup_btn', 'signup_btn', 'btn', { x: cx - 130, y: 330, w: 260, h: 38, text: 'Sign Up', fill: '#007aff', color: '#ffffff', radius: 8 })
  ];
  const generic = (label: string): LayerNode[] => [
    mkLayer('title', 'title', 'text', { x: cx - 90, y: 90, w: 180, h: 20, text: label, fontSize: 16, bold: true, align: 'center' }),
    mkLayer('subtitle', 'subtitle', 'text', { x: cx - 110, y: 118, w: 220, h: 13, text: 'Generated from template', fontSize: 10, color: '#8e8e93', align: 'center' }),
    mkLayer('main_btn', 'main_btn', 'btn', { x: cx - 100, y: 170, w: 200, h: 34, text: 'Get Started', fill: '#007aff', color: '#ffffff', radius: 8 }),
    mkLayer('card_1', 'card_1', 'rect', { x: cx - 140, y: 230, w: 280, h: 60, fill: '#f4f4f6', radius: 8 })
  ];
  const webSeeds = (heroTitle: string): LayerNode[] => [
    mkLayer('nav_bar', 'nav_bar', 'rect', { x: 0, y: 0, w: w, h: 44, fill: '#ffffff', radius: 0 }),
    mkLayer('brand', 'brand', 'text', { x: 24, y: 15, w: 90, h: 16, text: 'MoonViz', fontSize: 13, bold: true }),
    mkLayer('nav_cta', 'nav_cta', 'btn', { x: w - 120, y: 9, w: 92, h: 26, text: 'Get Started', fill: '#007aff', color: '#ffffff', radius: 6, fontSize: 11 }),
    mkLayer('hero_title', 'hero_title', 'text', { x: w / 2 - 200, y: 120, w: 400, h: 28, text: heroTitle, fontSize: 20, bold: true, align: 'center' }),
    mkLayer('hero_sub', 'hero_sub', 'text', { x: w / 2 - 220, y: 156, w: 440, h: 16, text: 'Human drags, agent commands — one source of truth.', fontSize: 12, color: '#636366', align: 'center' }),
    mkLayer('email_input', 'email_input', 'input', { x: w / 2 - 130, y: 210, w: 260, h: 34, text: 'Email address', color: '#aeaeb2' }),
    mkLayer('pwd_input', 'pwd_input', 'input', { x: w / 2 - 130, y: 252, w: 260, h: 34, text: 'Password', color: '#aeaeb2' }),
    mkLayer('signin_btn', 'signin_btn', 'btn', { x: w / 2 - 130, y: 306, w: 260, h: 36, text: 'Sign In', fill: '#007aff', color: '#ffffff', radius: 8 }),
    mkLayer('footer', 'footer', 'rect', { x: 0, y: 720, w: w, h: 80, fill: '#f7f7f9', radius: 0 })
  ];
  const mobileFn = (k: string): LayerNode[] => {
    if (k === 'login') return loginSeeds();
    if (k === 'signup') return signupSeeds();
    if (k === 'dashboard') return generic('Dashboard');
    if (k === 'profile') return generic('Profile');
    if (k === 'settings') return generic('Settings');   // iss-3：seedLayers 键随 tid 对齐（原 settings_page）
    if (k === 'list_detail') return generic('List');
    if (k === 'onboarding') return generic('Welcome');
    if (k === 'empty_state') return generic('Nothing here yet');
    return [];
  };
  const webHero = (k: string): string => {
    if (k === 'web_login' || k === 'login_v2') return 'Welcome back';
    if (k === 'web_dashboard') return 'Analytics Dashboard';
    if (k === 'pc_app') return 'Desktop App';
    return 'Prototype at the speed of thought';
  };
  const mob = mobileFn(tid);
  if (mob.length > 0) return mob;
  return webSeeds(webHero(tid));
}

/**
 * 节点行映射（gap-mbt-4）：LayerNode → canonical generic_node 行，视觉块与 mbt check 块
 * 复用同一产物（gap-mbt-5）。28 键固定序（canonical-sample.mbt.md:28 实测序），逗号后无
 * 空格，行首 2 空格缩进。
 *
 * 三段式映射（可映射 21 键）：
 *   - type→kind：image/btn/input/rect→"rect"、text→"text"；
 *   - component 为**近似映射、非引擎权威**（引擎真实 component 词表未知，接线后对账回收）：
 *     btn→button、input→text_input、text→body_text、image→badge、rect→rect；
 *   - color→text_color、fontSize→font_size、align→text_align；
 *   - bold→font_weight（normal/bold）、italic→font_style（normal/italic，斜体必须落否则
 *     静默丢数据）；
 *   - dash→stroke_dash 直传（solid/dashed/dotted）；stroke/strokeWidth→stroke/stroke_width；
 *   - text（内嵌 \ 与 " 转义）/fill/radius/opacity/visible 直传；
 *   - shadow 非 none 值**诚实降级**为 "none"——canonical 阴影档位名未知（值域差异登记），
 *     引擎补档位名后回收。
 * 缺省补齐 6 键：rotate=0/blur=0/blend="normal"/line_height=1.5/tracking=0/flip="none"；
 * constraint 单列恒 "lt"。w/h 经 @decl.fixed(Math.round(N))，x/y 取整（整数不带 .0）。
 *
 * 不落字段丢弃清单（canonical 无对应键，如实丢弃）：
 *   - widthMode/layout/justify/gap/padding（本文件 ElStyle 定义处，子元素模型数据先行）；
 *   - interactions（走 frontmatter flows: 通道，见 toCanonicalText）/states（LayerNode 定义处，
 *     演示消费待引擎回收）；
 *   - name（canonical 节点行无 name 键，节点 id 即标识）。
 */
function genericNodeRow(l: LayerNode): string {
  const s = l.style;
  let kind: string = 'rect';   // image/btn/input/rect 共享 rect 底座
  if (l.type === 'text') {
    kind = 'text';
  }
  let component: string = 'rect';   // 近似映射、非引擎权威（见头注释）
  if (l.type === 'btn') {
    component = 'button';
  } else if (l.type === 'input') {
    component = 'text_input';
  } else if (l.type === 'text') {
    component = 'body_text';
  } else if (l.type === 'image') {
    component = 'badge';
  }
  // 转义顺序：先反斜杠后引号（引号转义引入的反斜杠不得被二次翻倍）
  const txt = s.text.split('\\').join('\\\\').split('"').join('\\"');
  const kvs: string[] = [
    `id="${l.id}"`,
    `component="${component}"`,
    `kind="${kind}"`,
    `width=@decl.fixed(${Math.round(s.w)})`,
    `height=@decl.fixed(${Math.round(s.h)})`,
    `x=${Math.round(s.x)}`,
    `y=${Math.round(s.y)}`,
    `text="${txt}"`,
    `fill="${s.fill}"`,
    `stroke="${s.stroke}"`,
    `stroke_width=${s.strokeWidth}`,
    `radius=${s.radius}`,
    `opacity=${s.opacity}`,
    `font_size=${s.fontSize}`,
    `text_color="${s.color}"`,
    `font_weight="${s.bold ? 'bold' : 'normal'}"`,
    `shadow="none"`,   // 诚实降级（值域差异登记见头注释）
    `rotate=0`,
    `blur=0`,
    `blend="normal"`,
    `line_height=1.5`,
    `tracking=0`,
    `flip="none"`,
    `text_align="${s.align}"`,
    `font_style="${s.italic ? 'italic' : 'normal'}"`,
    `stroke_dash="${s.dash}"`,
    `visible=${s.visible}`,
    `constraint="lt"`
  ];
  return `  page.add(@decl.generic_node(${kvs.join(',')}))`;
}

export class AppStore {
  boards: Board[] = [];
  projectName: string = '未命名项目';
  dirty: boolean = false;
  timeline: TlEntry[] = [];
  flows: Flow[] = [];            // 交互流（gap-canvas-6，会话内态）
  ink: InkDoc = { v: 1, strokes: [] };   // 演示批注墨迹（batch-10 spec-ink-1，内存态）——
                                         // 写入不置脏不入撤销栈（批注非画布文档操作），
                                         // dirty 在退出演示统一置（Index.exitDemo）
  undoStack: string[] = [];      // 序列化快照（简易撤销）
  redoStack: string[] = [];      // 重做栈：undo 弹栈前压入当前态；新变更（pushUndo）即清空
  docRev: number = 0;            // 引擎会话文档修订（gap-global-3 M3）：history commit 信封
                                 // rev 回填，时间线 ENGINE 条目读数消费；本地会话恒 0
  filePath: string = '';         // 当前绑定的 .ddp 绝对路径；'' = 从未保存（导出成功才接管绑定）
  lastOp: string = '';           // 最近一条成功命令（batch-6 statusbar 消费）
  lastErr: string = '';          // 最近一条失败命令（空串 = 无失败；batch-6 红字回显）
  lastCmdSrc: string = '';       // 最近命令来源（batch-4，audit-topbar-8：HUMAN→statusbar
                                 // HUMAN 态；logCmd 统一写入，Index sync 镜像）
  docEpoch: number = 0;          // 文档纪元（batch-1 刷新机制）：restore/undo/redo/newProject 四处
                                 // +1——板级 ForEach 键成分 `${b.id}|${appStore.docEpoch}|${b.rev}`
                                 // （r4 起 rev 同入键，BoardFrame/@ObjectLink 已摘除），板实例替换点
                                 // 键跳变 → 全量重建，规避同键复用不回填参数的陷阱
  private seq: number = 0;
  private lastMs: number = 8;
  // batch-11（cur-4/spec-ddp-2）：canonical 打开态——entryBoard=frontmatter entry 且在 boards
  // 内（否则首板；interim/新建=首板，见各复位点）；isCanonicalSource=文档来自本地 canonical
  // 解析（restoreCanonical 置 true；restore interim 链/undo/redo/newProject 复位 false）——
  // Index.actSave 据此守门：canonical 项目 ⌘S 一律转另存浮层，不原地覆写桌面文件（interim
  // 载荷覆写 canonical = 桌面文件损坏，复审 finding-6）。
  entryBoard: string = '';
  isCanonicalSource: boolean = false;

  /** 文档整体替换后的统一复位（docEpoch 推进、清撤销/重做栈、isCanonicalSource、
   * entryBoard=canonical 指定板或首板）。restore interim/undo/redo/newProject/restoreCanonical 消费。 */
  private resetAfterDocReplace(canonical: boolean, entryId: string): void {
    this.docEpoch += 1;
    this.docRev = 0;   // 引擎会话修订随文档替换归零（M3：commit rev 回填）
    this.undoStack.splice(0);
    this.redoStack.splice(0);
    this.isCanonicalSource = canonical;
    this.entryBoard = entryId !== '' && this.boards.some((b: Board): boolean => b.id === entryId)
      ? entryId : (this.boards.length > 0 ? this.boards[0].id : '');
  }

  /** canonical mbt.md 解析产物入档（batch-11，spec-ddp-2）：boards（经 mkLayer 落 ElStyle
   * 缺省，画板 kind 为近似归一——390×844→mobile/其余→adaptive，MbtDoc 登记）/flows/
   * projectName(title)/entryBoard 填充；对齐 restore 口径清撤销/重做栈、dirty=false、
   * docEpoch+=1。isCanonicalSource=true（Index.actSave 防覆写守门输入）。 */
  restoreCanonical(mbt: MbtDoc): boolean {
    if (!mbt.ok || mbt.boards.length === 0) return false;
    const boards: Board[] = [];
    for (const mb of mbt.boards) {
      const b = new Board(mb.id, mb.name, mb.kind, mb.width, mb.height, 0, []);
      for (const ml of mb.layers) {
        b.layers.push(mkLayer(ml.id, ml.name, ml.type, {
          x: ml.x, y: ml.y, w: ml.w, h: ml.h,
          text: ml.text, fill: ml.fill, color: ml.color,
          fontSize: ml.fontSize, radius: ml.radius, opacity: ml.opacity, visible: ml.visible,
          align: ml.align, bold: ml.bold, shadow: ml.shadow, dash: ml.dash, italic: ml.italic,
          stroke: ml.stroke, strokeWidth: ml.strokeWidth
        }));
      }
      boards.push(b);
    }
    this.boards = boards;
    const flows: Flow[] = [];
    for (let i = 0; i < mbt.flows.length; i++) {
      const f: MbtFlow = mbt.flows[i];
      flows.push({
        id: `f${this.seq + i + 1}`,
        fromBoard: f.from, fromNode: f.node, toBoard: f.to, trigger: 'tap'
      });
    }
    this.seq += mbt.flows.length;
    this.flows = flows;
    this.ink = { v: 1, strokes: [] };   // 批注以 SerDoc/canonical ink 捕获回写为准，本轮不回写（spec-ddp-3）
    if (mbt.title !== '') this.projectName = mbt.title;
    this.resetAfterDocReplace(true, mbt.entry);
    this.dirty = false;
    return true;
  }

  /**
   * 合并式 canonical 回灌（gap-global-3 M2，引擎每 op 通路专用）：引擎为几何/样式
   * 事实源，但 per-layer interactions/states 无 canonical 承载（toCanonicalText 丢弃
   * 清单见本文件头注）——按 板/层 id 从旧状态重挂；flows 以 canonical 为准重建；
   * ink 演示批注与选择/撤销语义保留（不走 resetAfterDocReplace——编辑通路不清批注、
   * 不清撤销栈；打开/恢复路径仍走 restoreCanonical 全量替换）。projectName 不动
   * （op 通路不改项目名）。返回 false = canonical 不可用（调用方回退本地）。
   */
  mergeCanonical(mbt: MbtDoc): boolean {
    if (!mbt.ok || mbt.boards.length === 0) return false;
    const prevBoards = this.boards;
    const boards: Board[] = [];
    for (const mb of mbt.boards) {
      const pb = prevBoards.find((x: Board): boolean => x.id === mb.id);
      const b = new Board(mb.id, mb.name, mb.kind, mb.width, mb.height, 0, []);
      for (const ml of mb.layers) {
        const nl = mkLayer(ml.id, ml.name, ml.type, {
          x: ml.x, y: ml.y, w: ml.w, h: ml.h,
          text: ml.text, fill: ml.fill, color: ml.color,
          fontSize: ml.fontSize, radius: ml.radius, opacity: ml.opacity, visible: ml.visible,
          align: ml.align, bold: ml.bold, shadow: ml.shadow, dash: ml.dash, italic: ml.italic,
          stroke: ml.stroke, strokeWidth: ml.strokeWidth
        });
        const pl = pb?.layers.find((x: LayerNode): boolean => x.id === ml.id);
        if (pl && pl.interactions && pl.interactions.length > 0) nl.interactions = pl.interactions;
        if (pl && pl.states && pl.states.length > 0) nl.states = pl.states;
        b.layers.push(nl);
      }
      boards.push(b);
    }
    this.boards = boards;
    const flows: Flow[] = [];
    for (let i = 0; i < mbt.flows.length; i++) {
      const f: MbtFlow = mbt.flows[i];
      flows.push({
        id: `f${this.seq + i + 1}`,
        fromBoard: f.from, fromNode: f.node, toBoard: f.to, trigger: 'tap'
      });
    }
    this.seq += mbt.flows.length;
    this.flows = flows;
    this.dirty = true;
    return true;
  }

  /** 引擎通路撤销桥（gap-global-3 M2）：engine op 合并回灌前由 Index 调用——
   * 与 pushUndo 同体（公开薄包装），保证 ⌘Z 能回退经引擎执行的 op。 */
  pushUndoExternal(): void {
    this.pushUndo();
  }

  logCmd(src: string, op: string, ok: boolean = true, revOverride: number = -1): void {
    this.lastCmdSrc = src;   // batch-4，audit-topbar-8：statusbar HUMAN/READY 三分支数据源
    this.lastMs = 6 + Math.floor(Math.random() * 8);
    // M3：ENGINE 条目 revOverride=引擎 history commit rev；本地条目 -1=totalRev 原语义
    this.timeline.unshift({ src: src, op: op, rev: revOverride >= 0 ? revOverride : this.totalRev(), ms: this.lastMs, ok: ok });
    if (this.timeline.length > 80) this.timeline.pop();
    if (ok) {
      this.lastOp = op;
      this.lastErr = '';
    } else {
      this.lastErr = op;
    }
  }

  totalRev(): number {
    return this.boards.reduce((s: number, b: Board): number => s + b.rev, 0);
  }

  // ===== interim 持久化（gap-topbar-1）=====

  /** 批注墨迹写入（batch-10）：仅内存态——不 pushUndo（批注非画布文档操作）、不置脏；
   * dirty 由 Index.exitDemo 统一置（「退出演示置 dirty」语义）。 */
  setInk(strokes: number[][][]): void {
    this.ink = { v: 1, strokes: strokes.map((s: number[][]): number[][] => s.slice()) };
  }

  serialize(): string {
    // v2 载荷：flows 随文档持久化（gap-canvas-9）；SER_PREFIX 前缀不变（标识 interim 容器格式，
    // 新旧以 flows 字段在否区分）。batch-10：ink 演示批注随载荷持久化（SerDoc.ink 可选字段，
    // v1/v2 旧文件无字段兼容）。登记：桌面 canonical `<!-- deepdesign:ink -->` 注释块注入/
    // 恢复待 canonical 写路径（见移植计划 dropped 与 batch-5 捕获），本轮 interim-only。
    const doc: SerDoc = { projectName: this.projectName, boards: this.boards, flows: this.flows, ink: this.ink };
    return SER_PREFIX + JSON.stringify(doc);
  }

  /** 解析 interim JSON 回写 boards/flows/projectName；清撤销/重做栈、dirty=false；失败返 false。
   * batch-4（gap-mbt-11）：不再被源码视图校验路径调用（canonical 展示文本本就无法 JSON.parse，
   * Index.revalidateSource 为纯重投影）——仅 persist 打开（Index.finishOpen）与自动恢复
   * （Index.doRecover）两个调用点。 */
  restore(json: string): boolean {
    try {
      const doc = JSON.parse(json) as SerDoc;
      if (!Array.isArray(doc.boards)) return false;
      this.boards = rehydrateBoards(doc.boards);   // 普通对象重建为 @Observed 类实例
      // v2 载荷带回交互流；v1 旧文件无该字段清空——「换文档旧流失效」语义不变（gap-canvas-9）
      this.flows = Array.isArray(doc.flows) ? doc.flows.slice() : [];
      // batch-10：墨迹带回；v1/v2 旧文件无字段或形状不符清空（照 flows 兼容先例）
      this.ink = doc.ink !== undefined && doc.ink.v === 1 && Array.isArray(doc.ink.strokes)
        ? { v: 1, strokes: doc.ink.strokes } : { v: 1, strokes: [] };
      if (typeof doc.projectName === 'string' && doc.projectName !== '') {
        this.projectName = doc.projectName;
      }
      // batch-11：interim 链复位（isCanonicalSource=false、entryBoard=首板）；docEpoch/清栈
      // 收敛到统一复位点
      this.resetAfterDocReplace(false, '');
      this.dirty = false;
      return true;
    } catch (e) { return false; }
  }

  // ===== canonical 展示序列化（gap-mbt-1/2/6 frontmatter+正文；gap-mbt-3/4/5 画板块+节点行+check 块）=====

  /**
   * 展示专用纯读：把会话态投影成 canonical .mbt.md 文本，仅供「MBT 源码」视图/复制出口
   * 消费，不写任何状态。持久化链刻意分离——.ddp 保存/打开/自恢复仍走 interim
   * serialize()/restore()（DDP-INTERIM-v1 容器，与 canonical 双向不可互解，见 serialize() 注释）。
   * 块结构以 out/harmony-parity/canonical-sample.mbt.md 为基准；画板 8 行骨架（gap-mbt-3）/
   * 节点行 28 键三段式映射（gap-mbt-4）/mbt check 块（gap-mbt-5）见 genericNodeRow 与正文循环。
   *
   * 交互流丢弃清单（canonical 无对应物，如实丢弃，不假装可表达；引擎宿主接线后若补
   * toast/back 语义在此回收）：
   *   - Interaction.action === 'show_toast'（toast 文案无 canonical 承载）；
   *   - Interaction.action === 'back'（返回语义无 canonical op）。
   *   droppedInteractions 为逐次调用的丢弃计数（局部登记，见方法体）。
   */
  toCanonicalText(): string {
    if (this.boards.length === 0) {
      return '（先创建画板或打开 DDP）';   // 对齐通用版 loadDeclMain 空态文案（frontend i:2914）
    }
    // flows 双通道归并（gap-mbt-2）：flows 显式连线在前，逐板 navigate_to 绑定在后；
    // trigger 词汇当前仅 tap（桌面触发器族归 gap-right-3），两侧统一 tap:<源节点 id>。
    const cf: CanonFlow[] = [];
    let droppedInteractions = 0;
    for (const f of this.flows) {
      cf.push({ from: f.fromBoard, to: f.toBoard, node: f.fromNode });
    }
    for (const b of this.boards) {
      for (const l of b.layers) {
        if (Array.isArray(l.interactions)) {   // restore 往返脏值收窄（同 Index.layerInteractions 先例）
          for (const it of l.interactions) {
            if (it.action === 'navigate_to') {
              cf.push({ from: b.id, to: it.target, node: l.id });
            } else if (it.action === 'show_toast' || it.action === 'back') {
              droppedInteractions += 1;   // 丢弃计数（清单见方法头注释）
            }
          }
        }
      }
    }
    // entry：首条流起点板在场则取之，否则首板（对齐 canonical-sample 语义）
    let entry: string = this.boards[0].id;
    for (const f of cf) {
      const hit = this.boards.find((b: Board): boolean => b.id === f.from);
      if (hit) {
        entry = f.from;
        break;
      }
    }
    const L: string[] = [];
    L.push('---');
    // moonbit 节固定 6 行照抄 canonical-sample.mbt.md:2-6（引擎侧 backend/import 声明）
    L.push('moonbit:');
    L.push('  backend: native');
    L.push('  import:');
    L.push('    - path: moonviz/decl');
    L.push('      alias: decl');
    L.push('moonviz:');
    L.push('  format: visual-document');
    // revision 为会话内近似值（各板 rev 之和），非引擎权威 revision——引擎未接线前的占位口径
    L.push(`  revision: ${this.totalRev()}`);
    L.push('  theme: light');   // 固定照抄样例；主题联动归引擎接线后批次
    L.push(`  title: ${this.projectName}`);
    L.push(`  entry: ${entry}`);
    L.push('  artboards:');
    for (const b of this.boards) {
      L.push(`    - ${b.id}`);   // 逐板 4 空格缩进（canonical-sample.mbt.md:14 同构）
    }
    if (cf.length > 0) {
      L.push('  flows:');
      for (const f of cf) {
        L.push(`    - from: ${f.from}`);
        L.push(`      to: ${f.to}`);
        L.push(`      trigger: tap:${f.node}`);
      }
    }
    L.push('---');
    // 正文（gap-mbt-6）：H1 + 固定说明段照抄 canonical-sample.mbt.md:17-19 逐字 +
    // 每板 8 行骨架（gap-mbt-3）+ mbt check 块（gap-mbt-5）
    L.push('');
    L.push(`# ${this.projectName}`);
    L.push('');
    L.push('这是一份 MoonBit `.mbt.md` 视觉文档。人类画布操作与 Agent 修改都必须回写到本文件；Moonviz 只从本文件重新构建和渲染画布。');
    for (const b of this.boards) {
      // 骨架（gap-mbt-3）：## + 空行 + artboard 注释 + ```mbt + 装饰器 + fn + prototype 行 +
      // 节点行 + page/} + 围栏闭合。id 直接拼接（样例 __t_login → visual___t_login 三下划线
      // 属正常）；prototype name 取中文板名 Board.name（任务 approach，非样例的 id），
      // ## 标题用板 id——两者不混（验收判据 4）。
      // 节点行先收集为 rows，视觉块与 check 块复用同一产物（gap-mbt-5，两块逐字一致）。
      L.push('');
      L.push(`## ${b.id}`);
      L.push('');
      L.push(`<!-- moonviz:artboard ${b.id} -->`);
      L.push('```mbt');
      L.push(`///| @moonviz:visual ${b.id}`);
      L.push(`fn visual_${b.id}() -> @decl.Prototype {`);
      const proto = `  let page = @decl.prototype(name="${b.name}", width=${Math.round(b.width)}, height=${Math.round(b.height)})`;
      const rows: string[] = [];
      for (const l of b.layers) {
        rows.push(genericNodeRow(l));
      }
      L.push(proto);
      for (const r of rows) {
        L.push(r);
      }
      L.push('  page');
      L.push('}');
      L.push('```');
      // check 块（gap-mbt-5）：与视觉块同构的纯展示围栏——不承担引擎测试语义，
      // 不承诺与引擎产物字节级等价。
      L.push('');
      L.push('```mbt check');
      L.push(`test "${b.id} visual declaration" {`);
      L.push(proto);
      for (const r of rows) {
        L.push(r);
      }
      L.push('  assert_eq(page.check().length(), 0)');
      L.push('  assert_true(page.render().contains("<svg"))');
      L.push('}');
      L.push('```');
    }
    return L.join('\n') + '\n';
  }

  /** 清空回欢迎态（boards=[] 触发 Index 欢迎模板页）；清栈、清 filePath。 */
  newProject(): void {
    this.boards = [];
    this.projectName = '未命名项目';
    this.filePath = '';
    this.dirty = false;
    this.timeline.splice(0);
    this.flows.splice(0);
    // batch-11：docEpoch/清撤销重做栈/isCanonicalSource=false/entryBoard 清空收敛到统一复位点
    this.resetAfterDocReplace(false, '');
  }

  // ===== 撤销 / 重做（gap-global-1）=====

  /**
   * 变更前打快照进撤销栈（容量 40），boards 与 flows 双字段（gap-canvas-9：撤销覆盖交互流）。
   * 必须同时清空重做栈：否则 undo 后任意新编辑再 ↷ 会复活过期未来态、
   * 并把新编辑挤出撤销链（验收判据 4 锚定）。
   */
  private pushUndo(): void {
    try {
      const snap: UndoSnap = { boards: this.boards, flows: this.flows };
      this.undoStack.push(JSON.stringify(snap));
      if (this.undoStack.length > 40) this.undoStack.shift();
      this.redoStack.splice(0);
    } catch (e) { /* 快照失败不阻断 */ }
  }

  undo(): boolean {
    const s = this.undoStack.pop();
    if (!s) return false;
    try {
      const cur: UndoSnap = { boards: this.boards, flows: this.flows };
      this.redoStack.push(JSON.stringify(cur));
      const snap = JSON.parse(s) as UndoSnap;
      if (!Array.isArray(snap.boards)) return false;   // 形状不符按解析失败处理（保持返 false 契约）
      this.boards = rehydrateBoards(snap.boards);   // 普通对象重建为 @Observed 类实例
      this.docEpoch += 1;   // 板实例全量替换：键跳变驱动画布全量重建 + @ObjectLink 重连
      this.flows = Array.isArray(snap.flows) ? snap.flows.slice() : [];   // 双回放（gap-canvas-9）
      // batch-11：undo/redo 复位 canonical 标记；entryBoard 失存则回首板（保持可用起点）
      this.isCanonicalSource = false;
      if (this.entryBoard === '' || !this.boards.some((b: Board): boolean => b.id === this.entryBoard)) {
        this.entryBoard = this.boards.length > 0 ? this.boards[0].id : '';
      }
      this.dirty = true;
      this.logCmd('HUMAN', 'undo', true);
      return true;
    } catch (e) { return false; }
  }

  redo(): boolean {
    const s = this.redoStack.pop();
    if (!s) return false;
    try {
      const cur: UndoSnap = { boards: this.boards, flows: this.flows };
      this.undoStack.push(JSON.stringify(cur));
      const snap = JSON.parse(s) as UndoSnap;
      if (!Array.isArray(snap.boards)) return false;   // 形状不符按解析失败处理（保持返 false 契约）
      this.boards = rehydrateBoards(snap.boards);   // 普通对象重建为 @Observed 类实例
      this.docEpoch += 1;   // 板实例全量替换：键跳变驱动画布全量重建 + @ObjectLink 重连
      this.flows = Array.isArray(snap.flows) ? snap.flows.slice() : [];   // 双回放（gap-canvas-9）
      // batch-11：同 undo 复位口径
      this.isCanonicalSource = false;
      if (this.entryBoard === '' || !this.boards.some((b: Board): boolean => b.id === this.entryBoard)) {
        this.entryBoard = this.boards.length > 0 ? this.boards[0].id : '';
      }
      this.dirty = true;
      this.logCmd('HUMAN', 'redo', true);
      return true;
    } catch (e) { return false; }
  }

  addBoard(tid: string, name: string, kind: string, src: string = 'TEMPLATE'): Board {
    this.pushUndo();
    this.seq++;
    const size = TplSize.of(kind);
    // 类构造（batch-1：Board 为 @Observed 类，对象字面量不再可用）
    const b: Board = new Board(`b${Date.now().toString(36)}${this.seq}`, name, kind,
      size[0], size[1], 12, seedLayers(tid, size[0]));
    this.boards.push(b);
    this.dirty = true;
    this.logCmd(src, `template ${tid} ${b.id} ${size[0]} ${size[1]}`);
    return b;
  }

  removeBoard(id: string): void {
    this.pushUndo();
    this.boards = this.boards.filter((b: Board): boolean => b.id !== id);
    // 级联：引用该板的交互流一并删除（防悬空连线）
    this.flows = this.flows.filter((f: Flow): boolean => f.fromBoard !== id && f.toBoard !== id);
    this.dirty = true;
    this.logCmd('HUMAN', `delete-artboard ${id}`);
  }

  /** 建流（gap-canvas-6）。防双提交：同 fromNode+toBoard 已存在返回 null（上层 toast 忽略）。 */
  createFlow(fromBoard: string, fromNode: string, toBoard: string, trigger: string = 'tap'): Flow | null {
    const dup = this.flows.find((f: Flow): boolean => f.fromNode === fromNode && f.toBoard === toBoard);
    if (dup) return null;
    this.pushUndo();
    this.seq++;
    const f: Flow = {
      id: `f${this.seq}`, fromBoard: fromBoard, fromNode: fromNode,
      toBoard: toBoard, trigger: trigger
    };
    this.flows.push(f);
    this.dirty = true;
    this.logCmd('HUMAN', `flow ${fromNode} ${toBoard}`);
    return f;
  }

  unflow(id: string): void {
    const hit = this.flows.find((f: Flow): boolean => f.id === id);
    if (!hit) return;
    this.pushUndo();
    this.flows = this.flows.filter((f: Flow): boolean => f.id !== id);
    this.dirty = true;
    this.logCmd('HUMAN', `unflow ${id}`);
  }

  /** 文本工具落点放置（gap-canvas-1）：body_text 种子样式。 */
  placeLayerText(boardId: string, x: number, y: number): LayerNode | null {
    const b = this.boards.find((bd: Board): boolean => bd.id === boardId);
    if (!b) return null;
    this.pushUndo();
    this.seq++;
    const id = `body_text_${this.seq}`;
    const l = mkLayer(id, '正文', 'text', {
      x: x, y: y, w: 160, h: 18,
      text: '双击编辑文本', fontSize: 12, color: '#1c1c1e', align: 'left'
    });
    b.layers.push(l);
    b.rev += 1;
    this.dirty = true;
    this.logCmd('HUMAN', `text ${b.id} ${id} ${x} ${y}`);
    return l;
  }

  // ===== 右键菜单动作（gap-canvas-4）=====

  /** 复制节点：深拷贝、新 id、偏移 (+12,+12)、插在原节点之后。 */
  copyLayer(boardId: string, layerId: string): LayerNode | null {
    const b = this.boards.find((bd: Board): boolean => bd.id === boardId);
    if (!b) return null;
    const idx = b.layers.findIndex((x: LayerNode): boolean => x.id === layerId);
    if (idx < 0) return null;
    this.pushUndo();
    this.seq++;
    const copy = JSON.parse(JSON.stringify(b.layers[idx])) as LayerNode;
    copy.id = `${layerId}_c${this.seq}`;
    copy.style.x += 12;
    copy.style.y += 12;
    b.layers.splice(idx + 1, 0, copy);
    b.rev += 1;
    this.dirty = true;
    this.logCmd('HUMAN', `copy ${boardId} ${layerId} ${copy.id}`);
    return copy;
  }

  /** 置顶/置底（z-order = 图层顺序）。 */
  reorderLayer(boardId: string, layerId: string, toTop: boolean): void {
    const b = this.boards.find((bd: Board): boolean => bd.id === boardId);
    const idx = b?.layers.findIndex((x: LayerNode): boolean => x.id === layerId) ?? -1;
    if (!b || idx < 0) return;
    this.pushUndo();
    const hit = b.layers[idx];
    b.layers.splice(idx, 1);
    if (toTop) {
      b.layers.push(hit);
    } else {
      b.layers.unshift(hit);
    }
    b.rev += 1;
    this.dirty = true;
    this.logCmd('HUMAN', `order ${boardId} ${layerId} ${toTop ? 'top' : 'bottom'}`);
  }

  /** 居中：horiz=水平（板宽内），否则垂直（板高内）。 */
  alignLayer(boardId: string, layerId: string, horiz: boolean): void {
    const b = this.boards.find((bd: Board): boolean => bd.id === boardId);
    const l = b?.layers.find((x: LayerNode): boolean => x.id === layerId);
    if (!b || !l) return;
    this.pushUndo();
    if (horiz) {
      l.style.x = Math.max(0, Math.round((b.width - l.style.w) / 2));
    } else {
      l.style.y = Math.max(0, Math.round((b.height - l.style.h) / 2));
    }
    b.rev += 1;
    this.dirty = true;
    this.logCmd('HUMAN', `align ${boardId} ${layerId} ${horiz ? 'h' : 'v'}`);
  }

  /** 翻转：axis='h' 板宽内水平镜像（x 镜像），否则板高内垂直镜像（y 镜像）。 */
  flipLayer(boardId: string, layerId: string, axis: string): void {
    const b = this.boards.find((bd: Board): boolean => bd.id === boardId);
    const l = b?.layers.find((x: LayerNode): boolean => x.id === layerId);
    if (!b || !l) return;
    this.pushUndo();
    if (axis === 'h') {
      l.style.x = Math.max(0, b.width - l.style.x - l.style.w);
    } else {
      l.style.y = Math.max(0, b.height - l.style.y - l.style.h);
    }
    b.rev += 1;
    this.dirty = true;
    this.logCmd('HUMAN', `flip ${boardId} ${layerId} ${axis}`);
  }

  /** 复制画板：深拷贝（含图层），新 id/name，flows 不随拷。 */
  duplicateBoard(boardId: string): Board | null {
    const b = this.boards.find((bd: Board): boolean => bd.id === boardId);
    if (!b) return null;
    this.pushUndo();
    this.seq++;
    // JSON 深拷贝产普通对象，经 rehydrate 重建 @Observed 类实例（batch-1）
    const copy = rehydrateBoard(JSON.parse(JSON.stringify(b)) as BoardRaw);
    copy.id = `${boardId}_c${this.seq}`;
    copy.name = `${b.name} 副本`;
    copy.rev = 1;
    this.boards.splice(this.boards.indexOf(b) + 1, 0, copy);
    this.dirty = true;
    this.logCmd('HUMAN', `duplicate-board ${boardId} ${copy.id}`);
    return copy;
  }

  // ===== 交互绑定与状态（gap-right-3）=====

  /** 加绑定。完全重复（trigger+action+target）返 false 由上层 toast；pushUndo+timeline。 */
  addInteraction(boardId: string, layerId: string, trigger: string, action: string, target: string): boolean {
    const b = this.boards.find((bd: Board): boolean => bd.id === boardId);
    const l = b?.layers.find((x: LayerNode): boolean => x.id === layerId);
    if (!b || !l) return false;
    const list = l.interactions ?? [];
    const dup = list.find((it: Interaction): boolean =>
      it.trigger === trigger && it.action === action && it.target === target);
    if (dup) return false;
    this.pushUndo();
    const it: Interaction = { trigger: trigger, action: action, target: target };
    if (l.interactions) {
      l.interactions.push(it);
    } else {
      l.interactions = [it];
    }
    b.rev += 1;
    this.dirty = true;
    this.logCmd('HUMAN', `interact ${layerId} ${trigger} ${action} ${target}`);
    return true;
  }

  removeInteraction(boardId: string, layerId: string, idx: number): void {
    const b = this.boards.find((bd: Board): boolean => bd.id === boardId);
    const l = b?.layers.find((x: LayerNode): boolean => x.id === layerId);
    if (!b || !l || !l.interactions || idx < 0 || idx >= l.interactions.length) return;
    this.pushUndo();
    const it = l.interactions[idx];
    l.interactions.splice(idx, 1);
    b.rev += 1;
    this.dirty = true;
    this.logCmd('HUMAN', `uninteract ${layerId} ${it.trigger} ${it.action}`);
  }

  /** 定义状态。重名返 false 由上层 toast；pushUndo+timeline。 */
  addState(boardId: string, layerId: string, name: string): boolean {
    const b = this.boards.find((bd: Board): boolean => bd.id === boardId);
    const l = b?.layers.find((x: LayerNode): boolean => x.id === layerId);
    const n = name.trim();
    if (!b || !l || n === '') return false;
    const list = l.states ?? [];
    if (list.some((s: StateDef): boolean => s.name === n)) return false;
    this.pushUndo();
    if (l.states) {
      l.states.push({ name: n });
    } else {
      l.states = [{ name: n }];
    }
    b.rev += 1;
    this.dirty = true;
    this.logCmd('HUMAN', `state ${layerId} ${n}`);
    return true;
  }

  /** `set-state <name> toggle`：命令流记录（演示态消费留待引擎接线回收）。 */
  setStateToggle(boardId: string, layerId: string, name: string): void {
    this.logCmd('HUMAN', `set-state ${name} toggle`);
  }

  /** ghost 占位卡新建（gap-canvas-7）：390×844 空板。 */
  addBlankBoard(w: number = 390, h: number = 844, src: string = 'HUMAN'): Board {
    this.pushUndo();
    this.seq++;
    // 类构造（batch-1：Board 为 @Observed 类，对象字面量不再可用）
    const b: Board = new Board(`b${Date.now().toString(36)}${this.seq}`,
      `画板 ${this.boards.length + 1}`, 'mobile', w, h, 1, []);
    this.boards.push(b);
    this.dirty = true;
    this.logCmd(src, `create ${b.id} ${w} ${h}`);
    return b;
  }

  /**
   * 组件快照放置（gap-leftcomp-1）：按 CompDef 展开为 LayerNode。
   * id = `<comp.id>_<seq>`（ASCII snake_case——引擎节点 id 不清洗是约定，鸿蒙侧同守）。
   */
  placeLayer(boardId: string, comp: CompDef, x: number, y: number): LayerNode | null {
    const b = this.boards.find((bd: Board): boolean => bd.id === boardId);
    if (!b) return null;
    this.pushUndo();
    this.seq++;
    const sz = comp.default_size;
    const w = sz.length > 0 ? sz[0] : 120;
    const h = sz.length > 1 ? sz[1] : 32;
    const id = `${comp.id}_${this.seq}`;
    const l = mkLayer(id, id, comp.kind, { x: x, y: y, w: w, h: h });
    if (comp.kind === 'text') {
      l.style.text = comp.id;   // 文本类组件给可见占位文字
    }
    b.layers.push(l);
    b.rev += 1;
    this.dirty = true;
    this.logCmd('HUMAN', `place ${comp.id} ${b.id} ${id} ${x} ${y}`);
    return l;
  }

  moveLayer(boardId: string, layerId: string, dx: number, dy: number): void {
    const b = this.boards.find((x: Board): boolean => x.id === boardId);
    const l = b?.layers.find((x: LayerNode): boolean => x.id === layerId);
    if (!b || !l) return;
    this.pushUndo();   // 拖拽前补打快照（gap-global-1：最常用的拖拽必须可撤销）
    l.style.x = Math.max(0, l.style.x + dx);   // 钳 ≥0：不落板外负坐标
    l.style.y = Math.max(0, l.style.y + dy);
    b.rev += 1;
    this.dirty = true;
    this.logCmd('HUMAN', `move ${b.id} ${layerId} ${Math.round(dx)} ${Math.round(dy)}`);
  }

  setStyle(boardId: string, layerId: string, key: string, value: string | number | boolean): void {
    const b = this.boards.find((x: Board): boolean => x.id === boardId);
    const l = b?.layers.find((x: LayerNode): boolean => x.id === layerId);
    if (!b || !l) return;
    this.pushUndo();
    if (key === 'x') { l.style.x = Number(value); }
    else if (key === 'y') { l.style.y = Number(value); }
    else if (key === 'w') { l.style.w = Number(value); }
    else if (key === 'h') { l.style.h = Number(value); }
    else if (key === 'fontSize') { l.style.fontSize = Number(value); }
    else if (key === 'radius') { l.style.radius = Number(value); }
    else if (key === 'opacity') { l.style.opacity = Number(value); }
    else if (key === 'text') { l.style.text = String(value); }
    else if (key === 'fill') { l.style.fill = String(value); }
    else if (key === 'color') { l.style.color = String(value); }
    else if (key === 'align') { l.style.align = String(value); }
    else if (key === 'visible') { l.style.visible = Boolean(value); }
    else if (key === 'bold') { l.style.bold = Boolean(value); }
    else if (key === 'shadow') { l.style.shadow = String(value); }
    else if (key === 'dash') { l.style.dash = String(value); }             // batch-5：三态 'solid'|'dashed'|'dotted'
    else if (key === 'italic') { l.style.italic = Boolean(value); }
    else if (key === 'widthMode') { l.style.widthMode = String(value); }
    else if (key === 'layout') { l.style.layout = String(value); }
    else if (key === 'justify') { l.style.justify = String(value); }       // batch-5 布局对齐（渲染消费缓做，数据先行）
    else if (key === 'gap') { l.style.gap = Number(value); }
    else if (key === 'padding') { l.style.padding = Number(value); }
    else if (key === 'stroke') { l.style.stroke = String(value); }         // batch-3（gap-detail-7）
    else if (key === 'strokeWidth') { l.style.strokeWidth = Number(value); }   // batch-3（gap-detail-7）
    b.rev += 1;
    this.dirty = true;
    this.logCmd('HUMAN', `set ${b.id} ${layerId} ${key} ${String(value)}`);
  }

  deleteLayer(boardId: string, layerId: string): void {
    const b = this.boards.find((x: Board): boolean => x.id === boardId);
    if (!b) return;
    this.pushUndo();
    b.layers = b.layers.filter((l: LayerNode): boolean => l.id !== layerId);
    b.rev += 1;
    this.dirty = true;
    this.logCmd('HUMAN', `delete ${boardId} ${layerId}`);
  }

  boardCount(): number { return this.boards.length; }
  layerCount(): number { return this.boards.reduce((s: number, b: Board): number => s + b.layers.length, 0); }
}

export const appStore = new AppStore();
