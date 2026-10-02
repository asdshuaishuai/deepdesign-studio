// deepDesign 数据模型 —— 与通用版（桌面）状态语义 1:1 对齐的 ArkTS 复刻
// 模板种子对齐原版 TPLS ×14；元素属性对齐原版 inspector 字段；
// 命令流时间线对齐 tl-run 条目；撤销栈对齐 undo 语义。

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
}

export interface LayerNode {
  id: string;
  name: string;
  type: string;          // frame | text | input | btn | image | rect
  style: ElStyle;
}

export interface Board {
  id: string;
  name: string;
  kind: string;          // mobile | web | pc | adaptive
  width: number;
  height: number;
  rev: number;
  layers: LayerNode[];
}

export interface TlEntry {
  src: string;           // HUMAN | AGENT | TEMPLATE
  op: string;
  rev: number;
  ms: number;
  ok: boolean;
}

// ===== 14 模板（对齐原版 TPLS/TPL_SIZE/TPL_GROUPS）=====
export interface TplDef { tid: string; name: string; kind: string; }
export const TPLS: TplDef[] = [
  { tid: 'login', name: '登录页', kind: 'mobile' },
  { tid: 'signup', name: '注册页', kind: 'mobile' },
  { tid: 'dashboard', name: '仪表盘', kind: 'mobile' },
  { tid: 'profile', name: '个人主页', kind: 'mobile' },
  { tid: 'settings_page', name: '设置页', kind: 'mobile' },
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
  align: string, bold: boolean): ElStyle {
  return {
    x: x, y: y, w: w, h: h, text: text, fill: fill, color: color,
    fontSize: fontSize, radius: radius, opacity: opacity, visible: visible,
    align: align, bold: bold
  };
}

function defStyle(): ElStyle {
  return st(0, 0, 120, 18, '', '#f0f0f3', '#1c1c1e', 12, 4, 1, true, 'left', false);
}

function mkLayer(id: string, name: string, type: string, s: PartialEl): LayerNode {
  const d = defStyle();
  const o: ElStyle = {
    x: s.x ?? d.x, y: s.y ?? d.y, w: s.w ?? d.w, h: s.h ?? d.h,
    text: s.text ?? d.text, fill: s.fill ?? d.fill, color: s.color ?? d.color,
    fontSize: s.fontSize ?? d.fontSize, radius: s.radius ?? d.radius,
    opacity: s.opacity ?? d.opacity, visible: s.visible ?? d.visible,
    align: s.align ?? d.align, bold: s.bold ?? d.bold
  };
  return { id: id, name: name, type: type, style: o };
}

interface PartialEl {
  x?: number; y?: number; w?: number; h?: number; text?: string;
  fill?: string; color?: string; fontSize?: number; radius?: number;
  opacity?: number; visible?: boolean; align?: string; bold?: boolean;
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
    if (k === 'settings_page') return generic('Settings');
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

export class AppStore {
  boards: Board[] = [];
  projectName: string = '未命名项目';
  dirty: boolean = false;
  timeline: TlEntry[] = [];
  undoStack: string[] = [];      // 序列化快照（简易撤销）
  private seq: number = 0;
  private lastMs: number = 8;

  logCmd(src: string, op: string, ok: boolean = true): void {
    this.lastMs = 6 + Math.floor(Math.random() * 8);
    this.timeline.unshift({ src: src, op: op, rev: this.totalRev(), ms: this.lastMs, ok: ok });
    if (this.timeline.length > 80) this.timeline.pop();
  }

  totalRev(): number {
    return this.boards.reduce((s: number, b: Board): number => s + b.rev, 0);
  }

  private snapshot(): void {
    try {
      this.undoStack.push(JSON.stringify(this.boards));
      if (this.undoStack.length > 40) this.undoStack.shift();
    } catch (e) { /* 快照失败不阻断 */ }
  }

  undo(): boolean {
    const s = this.undoStack.pop();
    if (!s) return false;
    try {
      this.boards = JSON.parse(s) as Board[];
      this.logCmd('HUMAN', 'undo', true);
      return true;
    } catch (e) { return false; }
  }

  addBoard(tid: string, name: string, kind: string, src: string = 'TEMPLATE'): Board {
    this.snapshot();
    this.seq++;
    const size = TplSize.of(kind);
    const b: Board = {
      id: `b${Date.now().toString(36)}${this.seq}`,
      name: name, kind: kind, width: size[0], height: size[1],
      rev: 12, layers: seedLayers(tid, size[0])
    };
    this.boards.push(b);
    this.dirty = true;
    this.logCmd(src, `template ${tid} ${b.id} ${size[0]} ${size[1]}`);
    return b;
  }

  removeBoard(id: string): void {
    this.snapshot();
    this.boards = this.boards.filter((b: Board): boolean => b.id !== id);
    this.dirty = true;
    this.logCmd('HUMAN', `delete-artboard ${id}`);
  }

  moveLayer(boardId: string, layerId: string, dx: number, dy: number): void {
    const b = this.boards.find((x: Board): boolean => x.id === boardId);
    const l = b?.layers.find((x: LayerNode): boolean => x.id === layerId);
    if (!b || !l) return;
    l.style.x += dx;
    l.style.y += dy;
    b.rev += 1;
    this.dirty = true;
    this.logCmd('HUMAN', `move ${b.id} ${layerId} ${Math.round(dx)} ${Math.round(dy)}`);
  }

  setStyle(boardId: string, layerId: string, key: string, value: string | number | boolean): void {
    const b = this.boards.find((x: Board): boolean => x.id === boardId);
    const l = b?.layers.find((x: LayerNode): boolean => x.id === layerId);
    if (!b || !l) return;
    this.snapshot();
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
    b.rev += 1;
    this.dirty = true;
    this.logCmd('HUMAN', `set ${b.id} ${layerId} ${key} ${String(value)}`);
  }

  deleteLayer(boardId: string, layerId: string): void {
    const b = this.boards.find((x: Board): boolean => x.id === boardId);
    if (!b) return;
    this.snapshot();
    b.layers = b.layers.filter((l: LayerNode): boolean => l.id !== layerId);
    b.rev += 1;
    this.dirty = true;
    this.logCmd('HUMAN', `delete ${boardId} ${layerId}`);
  }

  boardCount(): number { return this.boards.length; }
  layerCount(): number { return this.boards.reduce((s: number, b: Board): number => s + b.layers.length, 0); }
}

export const appStore = new AppStore();
