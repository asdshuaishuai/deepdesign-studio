// canonical .mbt.md 本地解析器（batch-11，cur-4/spec-ddp-1/2/3）
//
// 结构基准 = out/harmony-parity/canonical-sample.mbt.md（只读规范）：① `---` frontmatter
// （moonviz.format/revision/title/entry + artboards 列表 + flows[from/to/trigger: tap:<node>]）；
// ② `<!-- moonviz:artboard <id> -->` + ```mbt 围栏内 fn visual_<id>() 的
// @decl.prototype(name=,width=,height=) 与 page.add(@decl.generic_node(…)) 行；
// ③ 节点行 28 键逆映射（AppStore.genericNodeRow 正表的逆，逐键对账）；④ ```mbt check
// 围栏跳过；⑤ `<!-- deepdesign:ink {…} -->` 原样捕获暂存（spec-ddp-3 roundtrip 项，
// 本轮只捕获不回写）。
// 排除清单（spec-ddp-3）：不支持 @decl 组件编译细节 / generate_responsive / constrain。
// 诚实边界：本地解析器面向 generic_node 平铺文档；未收录 component 经 kind 兜底 rect/text
// 可呈现，不承诺引擎全部产出形态。
// ArkTS 纪律：禁 as Record/any；数值/布尔逐键判型收窄，缺键回落默认值。
// 本文件不 import AppStore（AppStore 单向依赖本文件，防循环 import）。

// 节点行解析产物（plain 形状；AppStore.restoreCanonical 经 mkLayer 落 ElStyle）
export interface MbtLayer {
  id: string;
  name: string;
  type: string;        // btn | input | image | text | rect
  x: number;
  y: number;
  w: number;
  h: number;
  text: string;
  fill: string;
  color: string;
  fontSize: number;
  radius: number;
  opacity: number;
  visible: boolean;
  align: string;
  bold: boolean;
  shadow: string;      // 已值域归一：e1/e2/e3→sm/lg/xl，未知→none（batch-4 值域约定）
  dash: string;        // solid | dashed | dotted（未知→solid）
  italic: boolean;
  stroke: string;
  strokeWidth: number;
}

export interface MbtBoard {
  id: string;
  name: string;
  kind: string;        // 390×844→mobile，其余→adaptive（web/pc 不可辨，登记近似）
  width: number;
  height: number;
  layers: MbtLayer[];
}

export interface MbtFlow {
  from: string;
  to: string;
  node: string;        // trigger `tap:<node>` 的 node 段
}

export interface MbtDoc {
  ok: boolean;
  title: string;
  entry: string;
  boards: MbtBoard[];
  flows: MbtFlow[];
  inkJson: string;     // `<!-- deepdesign:ink {…} -->` 原样捕获（只捕获不回写，spec-ddp-3）
}

// component → type 逆表（与 genericNodeRow 正表互逆：btn→button/input→text_input/
// text→body_text/image→badge/rect→rect）
const COMPONENT_INVERSE: Record<string, string> = {
  'button': 'btn',
  'text_input': 'input',
  'badge': 'image',
  'body_text': 'text',
  'rect': 'rect'
};

// shadow 值域归一（batch-4 值域约定的解析侧）：桌面 canonical e1/e2/e3 → sm/lg/xl；
// 本侧值域原样；未知值→none，杜绝跨值域直灌。
function normalizeShadow(v: string): string {
  if (v === 'e1') return 'sm';
  if (v === 'e2') return 'lg';
  if (v === 'e3') return 'xl';
  if (v === 'sm' || v === 'lg' || v === 'xl') return v;
  return 'none';
}

function normalizeDash(v: string): string {
  if (v === 'dashed' || v === 'dotted') return v;
  return 'solid';
}

/** "…" 字段值还原：逐字符扫描，反斜杠转义取后一字（\"→"、\\→\；顺序安全）。 */
function unquote(s: string): string {
  if (s.length < 2 || s.charAt(0) !== '"') return s;
  const body = s.substring(1, s.length - 1);
  let out = '';
  for (let i = 0; i < body.length; i++) {
    const c = body.charAt(i);
    if (c === '\\' && i + 1 < body.length) {
      i++;
      out += body.charAt(i);
    } else {
      out += c;
    }
  }
  return out;
}

/** 括号内参数串按顶层逗号切分（引号内逗号不切）。 */
function splitTopLevel(s: string): string[] {
  const parts: string[] = [];
  let cur = '';
  let inQuote = false;
  for (let i = 0; i < s.length; i++) {
    const c = s.charAt(i);
    if (inQuote) {
      cur += c;
      if (c === '\\') {
        i++;
        if (i < s.length) cur += s.charAt(i);
      } else if (c === '"') {
        inQuote = false;
      }
    } else if (c === '"') {
      inQuote = true;
      cur += c;
    } else if (c === ',') {
      parts.push(cur);
      cur = '';
    } else {
      cur += c;
    }
  }
  parts.push(cur);
  return parts;
}

function parseNumber(v: string, def: number): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : def;
}

function parseBool(v: string): boolean {
  return v === 'true';
}

/** 解析一条 generic_node 参数串为 MbtLayer（28 键逆映射；缺键回落渲染缺省）。 */
function parseNode(args: string): MbtLayer | null {
  const kv = new Map<string, string>();
  for (const pair of splitTopLevel(args)) {
    const eq = pair.indexOf('=');
    if (eq <= 0) continue;
    const key = pair.substring(0, eq).trim();
    let val = pair.substring(eq + 1).trim();
    if (val.startsWith('@decl.fixed(') && val.endsWith(')')) {
      val = val.substring('@decl.fixed('.length, val.length - 1);
    }
    kv.set(key, val);
  }
  const id = unquote(kv.get('id') ?? '""');
  if (id === '') return null;
  const component = unquote(kv.get('component') ?? '""');
  const kind = unquote(kv.get('kind') ?? '""');
  let type = COMPONENT_INVERSE[component];
  if (type === undefined) {
    type = kind === 'text' ? 'text' : 'rect';   // 未收录 component 经 kind 兜底可呈现
  }
  return {
    id: id,
    name: id,
    type: type,
    x: parseNumber(kv.get('x') ?? '', 0),
    y: parseNumber(kv.get('y') ?? '', 0),
    w: parseNumber(kv.get('width') ?? '', 120),
    h: parseNumber(kv.get('height') ?? '', 18),
    text: unquote(kv.get('text') ?? '""'),
    fill: unquote(kv.get('fill') ?? '""'),
    color: unquote(kv.get('text_color') ?? '""'),
    fontSize: parseNumber(kv.get('font_size') ?? '', 12),
    radius: parseNumber(kv.get('radius') ?? '', 4),
    opacity: parseNumber(kv.get('opacity') ?? '', 1),
    visible: kv.has('visible') ? parseBool(kv.get('visible') ?? 'true') : true,
    align: unquote(kv.get('text_align') ?? '"left"'),
    bold: unquote(kv.get('font_weight') ?? '"normal"') === 'bold',
    shadow: normalizeShadow(unquote(kv.get('shadow') ?? '"none"')),
    dash: normalizeDash(unquote(kv.get('stroke_dash') ?? '"solid"')),
    italic: unquote(kv.get('font_style') ?? '"normal"') === 'italic',
    stroke: unquote(kv.get('stroke') ?? '"none"'),
    strokeWidth: parseNumber(kv.get('stroke_width') ?? '', 0)
  };
}

function emptyDoc(): MbtDoc {
  return { ok: false, title: '', entry: '', boards: [], flows: [], inkJson: '' };
}

/** 解析 canonical mbt.md 文本。ok=true 要求至少一块画板且 prototype 尺寸合法。 */
export function parseMbtDoc(text: string): MbtDoc {
  const doc = emptyDoc();
  if (typeof text !== 'string' || text === '') return doc;
  const lines = text.split('\n');

  // ① frontmatter：首个 `---` 到下一个 `---` 行
  if (lines[0] !== '---' && lines[0] !== '---\r') return doc;
  let fmEnd = -1;
  for (let i = 1; i < lines.length; i++) {
    const t = lines[i].trim();
    if (t === '---') {
      fmEnd = i;
      break;
    }
  }
  if (fmEnd < 0) return doc;
  let section = '';
  let curFlow: MbtFlow | null = null;
  for (let i = 1; i < fmEnd; i++) {
    const line = lines[i].replace(/\r$/, '');
    if (line.startsWith('  flows:')) {
      section = 'flows';
      continue;
    }
    if (line.startsWith('  artboards:')) {
      section = 'artboards';
      continue;
    }
    if (line.startsWith('  entry:')) {
      doc.entry = line.substring('  entry:'.length).trim();
      section = '';
      continue;
    }
    if (line.startsWith('  title:')) {
      let t = line.substring('  title:'.length).trim();
      if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
        t = t.substring(1, t.length - 1);
      }
      doc.title = t;
      section = '';
      continue;
    }
    if (section === 'artboards' && line.startsWith('    - ')) {
      // 画板 id 列表（呈现顺序参考；板本体以 body 画板块为准）
      continue;
    }
    if (section === 'flows') {
      if (line.startsWith('    - ')) {
        if (curFlow !== null) doc.flows.push(curFlow);
        curFlow = { from: line.substring(5).trim(), to: '', node: '' };
      } else if (curFlow !== null && line.startsWith('      to:')) {
        curFlow.to = line.substring('      to:'.length).trim();
      } else if (curFlow !== null && line.startsWith('      trigger:')) {
        const trig = line.substring('      trigger:'.length).trim();   // 形如 tap:<node>
        const colon = trig.indexOf(':');
        curFlow.node = colon >= 0 ? trig.substring(colon + 1) : trig;
      } else if (line.trim() !== '' && !line.startsWith(' ')) {
        if (curFlow !== null) doc.flows.push(curFlow);
        curFlow = null;
        section = '';
      }
    }
  }
  if (curFlow !== null) doc.flows.push(curFlow);

  // ② body 扫描：ink 捕获 + 画板块（artboard 注释 → ```mbt 围栏）+ check 围栏跳过
  let board: MbtBoard | null = null;
  let inVisual = false;   // 正在收集 visual ```mbt 围栏
  let inSkip = false;     // ```mbt check 等非 visual 围栏
  for (let i = fmEnd + 1; i < lines.length; i++) {
    const raw = lines[i].replace(/\r$/, '');
    const t = raw.trim();
    if (inSkip) {
      if (t === '```') inSkip = false;
      continue;
    }
    if (inVisual) {
      const proto = raw.match(/@decl\.prototype\(name="([^"]*)",\s*width=(\d+(?:\.\d+)?),\s*height=(\d+(?:\.\d+)?)\)/);
      if (proto !== null && board !== null) {
        board.id = proto[1] !== '' ? proto[1] : board.id;
        board.name = board.id;
        board.width = Number(proto[2]);
        board.height = Number(proto[3]);
        board.kind = board.width === 390 && board.height === 844 ? 'mobile' : 'adaptive';
      }
      const addIdx = raw.indexOf('@decl.generic_node(');
      if (addIdx >= 0 && board !== null) {
        const node = parseNode(raw.substring(addIdx + '@decl.generic_node('.length)
          .replace(/\)\s*$/, ''));
        if (node !== null) board.layers.push(node);
      }
      if (t === '```') {
        if (board !== null && board.width > 0 && board.height > 0) {
          doc.boards.push(board);
        }
        board = null;
        inVisual = false;
      }
      continue;
    }
    if (t.startsWith('<!-- deepdesign:ink ') && t.endsWith('-->') && doc.inkJson === '') {
      doc.inkJson = t.substring('<!--'.length, t.length - '-->'.length).trim();   // 含前导 deepdesign:ink 字样原样
      continue;
    }
    const art = t.match(/^<!--\s*moonviz:artboard\s+(\S+)\s*-->$/);
    if (art !== null) {
      board = { id: art[1], name: art[1], kind: 'adaptive', width: 0, height: 0, layers: [] };
      continue;
    }
    if (t === '```mbt') {
      inVisual = board !== null;   // 无 artboard 前导的散 ```mbt 不作为画板 body 收集
      continue;
    }
    if (t.startsWith('```mbt ')) {
      // ```mbt check 等派生围栏整体跳过；弃挂起的空板（派生围栏非画板 body，防误挂后续围栏）
      inSkip = true;
      board = null;
      continue;
    }
  }
  doc.ok = doc.boards.length > 0;
  return doc;
}
