const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const html=fs.readFileSync(path.join(__dirname,'frontend','index.html'),'utf8');
const script=html.match(/<script>([\s\S]*?)<\/script>/)[1];
const markup=html.slice(0,html.indexOf('<script>'));
const source=script;
const elements=new Map();
function element(id){if(!elements.has(id))elements.set(id,{value:'',style:{},dataset:{},textContent:'',innerHTML:'',className:'',classList:{add(){},remove(){},toggle(){}},setAttribute(){},addEventListener(){},focus(){},select(){},querySelectorAll(){return[]},replaceChildren(){}});return elements.get(id)}

/* ---------- 静态防线：引用必须有定义 ----------
 * 历史事故（9f48220「purge dead code」）：批量删函数时删掉了 14 个仍有调用点的定义，
 * 应用能启动、但一点画布就 ReferenceError。当时的测试恰好 stub 了其中三个，
 * 于是完全没拦住。下面四道检查专治这一类。 */

// 集合 1：脚本里所有定义（含 const/let 箭头函数）
const defined=new Set();
for(const m of script.matchAll(/\bfunction\s+([A-Za-z_$][\w$]*)/g))defined.add(m[1]);
for(const m of script.matchAll(/\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=/g))defined.add(m[1]);

// 集合 2：任意作用域的绑定。内联处理器里会出现 `${cb}(...)` 这类由参数拼出的调用，
// 只认顶层定义会误报成悬空，必须把函数参数/解构/catch 绑定也算进来。
const bound=new Set(defined);
for(const m of script.matchAll(/\(([^()]*)\)\s*=>/g))
  for(const x of m[1].matchAll(/([A-Za-z_$][\w$]*)/g))bound.add(x[1]);
for(const m of script.matchAll(/(?:^|[\s(,])([A-Za-z_$][\w$]*)\s*=>/gm))bound.add(m[1]);
for(const m of script.matchAll(/function\s*[\w$]*\s*\(([^)]*)\)/g))
  for(const x of m[1].matchAll(/([A-Za-z_$][\w$]*)/g))bound.add(x[1]);
for(const m of script.matchAll(/\bcatch\s*\(\s*([A-Za-z_$][\w$]*)/g))bound.add(m[1]);
for(const m of script.matchAll(/\bfor\s*\(\s*(?:const|let|var)\s+([A-Za-z_$][\w$]*)/g))bound.add(m[1]);

/* 检查 A：内联处理器（onclick="f()"）引用的函数必须有定义。
 * 两个来源都要扫——(1) HTML 标记里的静态处理器；(2) 脚本模板串里**生成**的处理器
 * （renderInspector / nodeMenu 等用 innerHTML 拼出来的 onclick）。
 * 只扫 (1) 会漏掉整整一类：setProp/setShadow/alignH/alignV/delSelected 等
 * 只被生成型处理器调用，删掉它们测试照样全绿（已用变异测试证明）。 */
const KEYWORDS=new Set(['if','else','for','while','do','switch','case','break','continue','return',
  'typeof','instanceof','in','of','new','delete','void','this','function','var','let','const',
  'class','await','async','yield','try','catch','finally','throw']);
const GLOBALS=new Set(['event','window','document','navigator','localStorage','String','Number',
  'Boolean','Array','Object','JSON','Math','Date','parseInt','parseFloat','isNaN','Infinity','NaN',
  'encodeURIComponent','decodeURIComponent','setTimeout','clearTimeout','setInterval','clearInterval',
  'alert','confirm','prompt','console','btoa','atob','escape','unescape']);
const danglingHandlers=[];
for(const src of [markup,script]){
  for(const m of src.matchAll(/\son[a-z]+\s*=\s*"([^"]*)"/g)){
    for(const c of m[1].matchAll(/(^|[^.\w$])([A-Za-z_$][\w$]*)\s*\(/g)){
      const n=c[2];
      if(!bound.has(n)&&!GLOBALS.has(n)&&!KEYWORDS.has(n))danglingHandlers.push(n);
    }
  }
}
assert.deepEqual([...new Set(danglingHandlers)].sort(),[],
  `内联处理器引用了未定义的函数（运行时必 ReferenceError）：${[...new Set(danglingHandlers)]}`);

/* 检查 B：交互层函数清单必须真实存在。
 * 这份清单是"删了就坏"的最小集合——不是内部工具函数，而是 DOM 事件/内联处理器直接调用的入口。
 * stub 掉它们等于把应用变成哑巴，所以它们永远不允许缺失。 */
const INTERACTIVE_SURFACE=[
  // 画布点选/拖拽/双击（bindStageSvg 直接以值传给 addEventListener，只扫 name( 会漏掉）
  'nodeOf','activeDisplayScale','onDown','onCtx','onDblClick',
  'select','updateSel','commitInline','cancelInline',
  // 右键菜单族
  'showMenu','hideMenu','nodeMenu','canvasMenu','artboardMenu','declMenu',
  'startInlineEdit','ctxDo','deleteBoard','duplicateBoard','duplicateActiveBoard',
  // 原生菜单桥（Rust lib.rs 经 webview.eval 调用；有 typeof 守卫所以缺失时完全静默）
  'nativeMenuAction','openShortcuts','closeShortcuts',
  // 悬浮 Agent
  'openAgentPop','closeAgentPop','sendAgent','trackAgent',
];
// 断言条目数：否则删一个名字会同时缩短清单与提示信息，防线静默变弱
assert.equal(INTERACTIVE_SURFACE.length,27,'交互层清单条目数变了——增删都必须是有意的');
const missingSurface=INTERACTIVE_SURFACE.filter(n=>!defined.has(n));
assert.deepEqual(missingSurface,[],
  `交互层函数未定义：${missingSurface}（历史上因批量删死代码误删，会静默失效）`);

/* 检查 C：本测试自身的 stub 不得掩盖缺失定义。
 * 根因就是"测试替身顶替了真实定义"。凡是 stub 掉的名字，真身必须存在。 */
const HARNESS_STUBS=['renderStage','renderAbs','renderFlows','renderInspector',
  'renderLayersIfOpen','updateSel','setStatus','closeAgentPop','cancelInline',
  'mbtResult','switchSession','execCli'];
const stubMasking=HARNESS_STUBS.filter(n=>!defined.has(n));
assert.deepEqual(stubMasking,[],
  `测试替身掩盖了不存在的定义：${stubMasking}——请先修实现，不要改测试`);

/* 检查 D：跨文件契约——Rust 原生菜单 id 必须都被 nativeMenuAction 处理。
 * lib.rs 用 typeof 守卫兜底，所以漏映射时菜单静默失效，任何前端自测都发现不了。 */
const libRs=fs.readFileSync(path.join(__dirname,'src-tauri','src','lib.rs'),'utf8');
// id 允许大小写/数字/下划线：只收 [a-z-] 会让 "open_ddp2" 这类 id 静默逃过契约检查
const menuIds=[...libRs.matchAll(/MenuItem::with_id\(\s*app,\s*"([A-Za-z0-9_-]+)"/g)].map(m=>m[1]);
assert(menuIds.length>0,'未能从 lib.rs 解析出菜单 id（提取逻辑失效，请同步更新本测试）');
const mapBody=(script.match(/function nativeMenuAction\(id\)\{[\s\S]*?\n\}/)||[''])[0];
const mappedIds=new Set([...mapBody.matchAll(/'([A-Za-z0-9_-]+)'\s*:/g)].map(m=>m[1]));
const unmapped=menuIds.filter(id=>!mappedIds.has(id));
assert.deepEqual(unmapped,[],`原生菜单 id 未在 nativeMenuAction 中映射：${unmapped}`);

/* ---------- 动态检查：真实状态机 ---------- */
function fn(name){const start=script.indexOf('function '+name+'(');assert(start>=0,name);const brace=script.indexOf('){',start)+1;let depth=1,i=brace+1;for(;depth;i++){if(script[i]==='{')depth++;if(script[i]==='}')depth--;}return (script.slice(start-6,start)==='async '?'async ':'')+script.slice(start,i)}
const context=vm.createContext({console,window:{addEventListener(){}},document:{documentElement:{classList:{add(){}}},getElementById:element},performance:{now:()=>0},setTimeout,clearTimeout,requestAnimationFrame(){},btoa:s=>Buffer.from(s,'binary').toString('base64'),atob:s=>Buffer.from(s,'base64').toString('binary'),encodeURIComponent,decodeURIComponent,escape,unescape});
// Use the real state/apply/queue functions, with presentation and engine boundaries stubbed.
vm.runInContext(script.slice(script.indexOf("const APP_VER"),script.indexOf('async function execCli')),context);
vm.runInContext(['newId','applyMbtResult','serializeProject','runOp','runOpNow','addBoard','quickStart','createBlank','newProject'].map(fn).join('\n'),context);
vm.runInContext(`
function renderStage(){} function renderAbs(){} function renderFlows(){} function renderInspector(){} function renderLayersIfOpen(){} function updateSel(){} function setStatus(){} function closeAgentPop(){} function cancelInline(){} function mbtResult(rs){return rs.find(r=>r.mbt)}
async function switchSession(id){active=id}
let history=[];
async function execCli(commands){history.push(commands[0]);await new Promise(r=>setTimeout(r,5));const c=commands[0];if(c.startsWith('create '))throw Error('simulated failure');const parts=c.split(' '),input=b64ToUtf8(parts[1]),op=b64ToUtf8(parts[2]);return [{ok:true,mbt:input+';'+op,entry:'a',artboards:[{id:'a',nodes:[]},{id:'b',nodes:[{id:'selected'}]}]}];}
sessions={a:{},b:{}};active='b';selected='selected';mbtText='start';declDraftDirty=true;$('decl-text').value='unsubmitted draft';
applyMbtResult({ok:true,mbt:'canonical',entry:'a',artboards:[{id:'a',nodes:[]},{id:'b',nodes:[{id:'selected'}]}]});
`,context);
(async()=>{
 assert.equal(vm.runInContext('active',context),'b');assert.equal(vm.runInContext('selected',context),'selected');assert.equal(element('decl-text').value,'unsubmitted draft');
 await vm.runInContext("Promise.all([runOp('first','human'),runOp('second','human')])",context);
 assert.equal(vm.runInContext('mbtText',context),'canonical;first;second');
 await vm.runInContext('newProject()',context);assert.equal(vm.runInContext('mbtText',context),'');assert.equal(vm.runInContext('active',context),'');
 await vm.runInContext("quickStart('login',390,844)",context);assert.match(vm.runInContext('history.at(-1)',context),/^apply-human-mbt-op-b64 /);
 await vm.runInContext('createBlank()',context);assert.match(vm.runInContext('history.at(-1)',context),/^apply-human-mbt-op-b64 /);
 assert(html.includes("['p-op','opacity',n.style.opacity??1]"));
 // 跨文件契约：tauri.conf.json 的 frontendDist 必须指向本文件所在目录。
 // （不要写成读同一路径跟自身比较——9f48220 就是这么把真 parity 检查变成恒真式的）
 const conf=JSON.parse(fs.readFileSync(path.join(__dirname,'src-tauri','tauri.conf.json'),'utf8'));
 assert.equal(conf.build.frontendDist,'../frontend','frontendDist 未指向 frontend/（前端可能已搬家或换副本）');
 console.log(`Studio checks passed: ${INTERACTIVE_SURFACE.length} 个交互层函数在场、${menuIds.length} 个原生菜单 id 全映射、内联处理器无悬空引用；状态机：队列、新建画板、选区、draft、失败回滚、opacity`);
})().catch(e=>{console.error(e);process.exitCode=1});
