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
  // 模型注册表消费（models.dev 快照；快照缺失时设置面板降级为手输，
  // 但函数缺失会让预设点击后模型清单与提示静默失效）
  'loadModelRegistry','registryProviderFor','registryModelIds','presetRegistryIds',
  'registryModelInfo','thinkingOptionsFor','fillModelHints',
  // restoreThinkingOptions 与 THINK_LABEL 是档位恢复路径的承重符号——
  // 缺失时点预设后 select 静默不收窄/不恢复（9f48220 同类盲区，勿删）
  'restoreThinkingOptions',
];
const SURFACE_CONSTS=['THINK_LABEL'];
// 断言条目数：否则删一个名字会同时缩短清单与提示信息，防线静默变弱
assert.equal(INTERACTIVE_SURFACE.length,35,'交互层清单条目数变了——增删都必须是有意的');
const missingConsts=SURFACE_CONSTS.filter(n=>!new RegExp('(const|let|var)\\s+'+n+'\\b').test(script));
assert.deepEqual(missingConsts,[],`承重常量未定义：${missingConsts}`);
const missingSurface=INTERACTIVE_SURFACE.filter(n=>!defined.has(n));
assert.deepEqual(missingSurface,[],
  `交互层函数未定义：${missingSurface}（历史上因批量删死代码误删，会静默失效）`);

/* 检查 C：本测试自身的 stub 不得掩盖缺失定义。
 * 根因就是"测试替身顶替了真实定义"。凡是 stub 掉的名字，真身必须存在。 */
const HARNESS_STUBS=['renderStage','renderAbs','renderFlows','renderInspector',
  'renderLayersIfOpen','updateSel','setStatus','closeAgentPop','cancelInline',
  'switchSession'];
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
// Use the real state/engine-seam/apply/queue functions, with presentation stubbed.
vm.runInContext(script.slice(script.indexOf("const APP_VER"),script.indexOf('function mbtResult(')),context);
vm.runInContext(['newId','mbtResult','applyMbtResult','serializeProject','runOp','runOpNow','addBoard','quickStart','createBlank','newProject'].map(fn).join('\n'),context);
vm.runInContext(`
function renderStage(){} function renderAbs(){} function renderFlows(){} function renderInspector(){} function renderLayersIfOpen(){} function updateSel(){} function setStatus(){} function closeAgentPop(){} function cancelInline(){}
async function switchSession(id){active=id}
let history=[];
// 引擎接缝桩：镜像 wasm apply/render 的返回契约（mbt 拼接语义与旧 execCli 桩一致）
window.__ENGINE_STUB__={
  apply:(gate,mbt,op)=>{history.push((gate==='agent'?'a:':'h:')+op);return {ok:true,debt:0,mbt:mbt+';'+op,revision:1,entry:'a',artboards:[{id:'a',name:'a',width:390,height:844,nodes:[]},{id:'b',name:'b',width:390,height:844,nodes:[{id:'selected'}]}],flows:[]};},
  render:(mbt)=>{history.push('render');return {ok:true,mbt,revision:1,entry:'a',artboards:[{id:'a',name:'a',width:390,height:844,nodes:[]},{id:'b',name:'b',width:390,height:844,nodes:[{id:'selected'}]}],flows:[]};}
};
sessions={a:{},b:{}};active='b';selected='selected';mbtText='start';declDraftDirty=true;$('decl-text').value='unsubmitted draft';
applyMbtResult({ok:true,mbt:'canonical',entry:'a',revision:1,artboards:[{id:'a',name:'a',width:390,height:844,nodes:[]},{id:'b',name:'b',width:390,height:844,nodes:[{id:'selected'}]}],flows:[]});
`,context);
(async()=>{
 assert.equal(vm.runInContext('active',context),'b');assert.equal(vm.runInContext('selected',context),'selected');assert.equal(element('decl-text').value,'unsubmitted draft');
 await vm.runInContext("Promise.all([runOp('first','human'),runOp('second','human')])",context);
 assert.equal(vm.runInContext('mbtText',context),'canonical;first;second');
 await vm.runInContext('newProject()',context);assert.equal(vm.runInContext('mbtText',context),'');assert.equal(vm.runInContext('active',context),'');
 // 空项目模板起步：经种子文档引导（template op → 删除种子板），全程人类门
 await vm.runInContext("quickStart('login',390,844)",context);
 assert.match(vm.runInContext('history.at(-1)',context),/^h:delete-artboard __seed$/);
 assert(vm.runInContext('history.some(h=>/^h:template login /.test(h))',context),'模板 op 未经种子引导');
 // 有文档后 createBlank 直接走 apply 人类门
 await vm.runInContext('createBlank()',context);
 assert.match(vm.runInContext('history.at(-1)',context),/^h:create /);
 assert(html.includes("['p-op','opacity',n.style.opacity??1]"));
 // 跨文件契约：tauri.conf.json 的 frontendDist 必须指向本文件所在目录。
 // （不要写成读同一路径跟自身比较——9f48220 就是这么把真 parity 检查变成恒真式的）
 const conf=JSON.parse(fs.readFileSync(path.join(__dirname,'src-tauri','tauri.conf.json'),'utf8'));
 assert.equal(conf.build.frontendDist,'../frontend','frontendDist 未指向 frontend/（前端可能已搬家或换副本）');
 // CSP 契约：wasm 引擎在 WebView 内实例化，script-src 必须带 'wasm-unsafe-eval'
 assert.match(conf.app.security.csp,/script-src[^;]*'wasm-unsafe-eval'/,"CSP script-src 缺 'wasm-unsafe-eval'——wasm 引擎将无法编译");
 // —— wasm 引擎真机契约（Node ≥ 24；产物缺失/宿主过旧时跳过并提示，不误报绿）——
 const wasmPath=path.join(__dirname,'frontend','vendor','moonviz.wasm');
 if(!fs.existsSync(wasmPath)){
   console.warn('跳过 wasm 契约：frontend/vendor/moonviz.wasm 缺失（先跑 node scripts/sync-engine.mjs）');
 }else{
   let ex;
   try{
     // 标准 classic wasm：零 import，标准实例化（wasm-gc 变体才需要 js-string builtins）
     ex=new WebAssembly.Instance(new WebAssembly.Module(fs.readFileSync(wasmPath)),{}).exports;
   }catch(e){
     console.warn('跳过 wasm 契约：无法实例化 wasm 产物：'+e.message);
   }
   if(ex){
     for(const name of ['apply_human_op','apply_agent_op','render_mbt','validate_mbt','list_templates','export_html','version_info'])
       assert.equal(typeof ex[name],'function',`wasm 缺导出 ${name}——引擎产物面变了，同步前端与 agent`);
     // classic wasm 字符串是 linear memory 对象：header(长度)@ptr-4、UTF-16LE@ptr+0
     const readStr=(ptr)=>{const mem=new DataView(ex.memory.buffer);
       const len=mem.getUint32(ptr-4,true)&0x0FFFFFFF;let s='';
       for(let i=0;i<len;i++)s+=String.fromCharCode(mem.getUint16(ptr+i*2,true));return s;};
     const engineIds=JSON.parse(readStr(ex.list_templates())).map(t=>t.id??t.template_id??t);
     const agentSrc=fs.readFileSync(path.join(__dirname,'src-tauri','src','agent.rs'),'utf8');
     const tplBlock=agentSrc.match(/const ENGINE_TEMPLATES[^=]*=\s*r?"([\s\S]*?)";/);
     assert(tplBlock,'无法从 agent.rs 解析 ENGINE_TEMPLATES');
     const agentIds=[...tplBlock[1].matchAll(/[a-z0-9_]+(?=\()/g)].map(m=>m[0]);
     const drift=engineIds.filter(x=>!agentIds.includes(x)).concat(agentIds.filter(x=>!engineIds.includes(x)));
     assert.deepEqual(drift,[],`模板清单与 agent.rs 漂移：${drift}——两边必须一起改`);
     const comps=JSON.parse(fs.readFileSync(path.join(__dirname,'frontend','vendor','components.json'),'utf8'));
     assert(comps.length>0,'components.json 为空——sync-engine 探针异常');
   }
 }
 console.log(`Studio checks passed: ${INTERACTIVE_SURFACE.length} 个交互层函数在场、${menuIds.length} 个原生菜单 id 全映射、内联处理器无悬空引用；状态机：队列、种子引导、选区、draft、opacity`);
})().catch(e=>{console.error(e);process.exitCode=1});
