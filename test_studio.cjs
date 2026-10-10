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
  // 交付导出（fmAct 以字符串分发，检查 A 扫不到——真身存在性由本清单锚定）
  'exportHtmlProto','exportSvg',
  // 文档级撤销/重做（原生菜单直调，typeof 守卫下缺失即静默）
  'undoMbt','redoMbt',
  // 模型注册表消费（models.dev 快照；快照缺失时设置面板降级为手输，
  // 但函数缺失会让预设点击后模型清单与提示静默失效）
  'loadModelRegistry','registryProviderFor','registryModelIds','presetRegistryIds',
  'registryModelInfo','thinkingOptionsFor','fillModelHints',
  // restoreThinkingOptions 与 THINK_LABEL 是档位恢复路径的承重符号——
  // 缺失时点预设后 select 静默不收窄/不恢复（9f48220 同类盲区，勿删）
  'restoreThinkingOptions',
  // agent 引擎桥已随 wasmtime 纯 Rust 宿主删除（agent 不再经前端桥执行，
  // agentSession/sessCache 等桥侧符号一并移除——2026-09 wasmtime 迁移）
];
const SURFACE_CONSTS=['THINK_LABEL'];
// 断言条目数：否则删一个名字会同时缩短清单与提示信息，防线静默变弱
assert.equal(INTERACTIVE_SURFACE.length,39,'交互层清单条目数变了——增删都必须是有意的');
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

/* 检查 F：启动期自动执行守卫。引用 runGlobalPrompt 的 setTimeout/setInterval 回调
 * 只允许出现在 dd-dev-autorun 开关门内（一次性、用后即焚）。
 * 事故形态：露营 e2e 调试残留以无条件 setTimeout(…,1500) 提交入库，每次启动自动
 * 跑真实 LLM run；vm 动态切片不执行脚本尾部，所以当时全部防线绿灯——必须静态拦。 */
const autorunGuardStart=script.indexOf("localStorage.getItem('dd-dev-autorun')");
const autorunGuardEnd=autorunGuardStart>=0?script.indexOf('catch(_){ }',autorunGuardStart):-1;
assert(autorunGuardStart>=0&&autorunGuardEnd>autorunGuardStart,
  'dd-dev-autorun 开关门不存在或结构变了——请同步更新检查 F');
const strayAutorun=[];
// 括号平衡取完整调用参数区间（正则非贪婪会被无大括号箭头体骗过吞到别处的 `}`）。
// openAt 必须指向调用自身的 '('：深度从 1 起算，遇到配对的 ')' 才闭合。
function callSpan(src,openAt){
  let depth=1;
  for(let i=openAt+1;i<src.length&&i<openAt+2000;i++){
    if(src[i]==='(')depth++;
    else if(src[i]===')'){depth--;if(depth===0)return src.slice(openAt,i+1);}
  }
  return null;
}
for(const m of script.matchAll(/\b(?:setTimeout|setInterval)\s*\(/g)){
  const body=callSpan(script,m.index+m[0].length-1);
  if(body&&/runGlobalPrompt\s*\(/.test(body)&&!(m.index>autorunGuardStart&&m.index<autorunGuardEnd))
    strayAutorun.push(script.slice(m.index,m.index+60));
}
assert.deepEqual(strayAutorun,[],
  `守卫块外发现引用 runGlobalPrompt 的延时自动执行（启动期自动跑 agent）：${strayAutorun}`);

/* 检查 G：字符串分发的菜单目标必须在场（9f48220 同构盲区）。
 * fmAct('fn') 以带引号字符串经 window[fn] 分发——检查 A 的调用点扫描看不见；
 * nativeMenuAction 映射体的箭头目标同理（检查 D 只验证 id 有键，不验证目标函数存在）。
 * 删掉任一目标 = 文件菜单/原生菜单静默变哑，点开才 ReferenceError。 */
const fmTargets=[...new Set([markup,script].flatMap(src=>
  [...src.matchAll(/\bfmAct\('([A-Za-z0-9_]+)'\)/g)].map(m=>m[1])))];
assert(fmTargets.length>0,'未能提取 fmAct 字符串分发目标（结构变了请同步检查 G）');
// window[fn] 要求目标是顶层 function 声明（const 箭头不挂 window）
const missingFm=fmTargets.filter(n=>!new RegExp('function\\s+'+n+'\\s*\\(').test(script));
assert.deepEqual(missingFm,[],`fmAct 字符串分发目标不是顶层 function 声明（window[fn] 不可达）：${missingFm}`);
const mapBodyG=(script.match(/function nativeMenuAction\(id\)\{[\s\S]*?\n\}/)||[''])[0];
const mapCalls=[...new Set([...mapBodyG.matchAll(/([A-Za-z_$][\w$]*)\s*\(/g)].map(m=>m[1]))];
assert(mapCalls.length>0,'未能提取 nativeMenuAction 映射体调用目标（结构变了请同步检查 G）');
const missingMap=mapCalls.filter(n=>!defined.has(n)&&!bound.has(n)&&!GLOBALS.has(n)&&!KEYWORDS.has(n));
assert.deepEqual(missingMap,[],`nativeMenuAction 映射体调用了未定义函数：${missingMap}`);

/* 检查 L：会话写路径的响应变量必须是 let——`const out=…` 被下方 artboard 富集分支
 * 重赋值时抛 TypeError，且**只在响应不带 artboards 时触发**（引擎对部分 op 不回该索引），
 * 于是表现为「双击改文字提交必然失败」这类条件性故障，静态扫描与状态机桩都撞不到
 * （桩恒返回 artboards，永远走不到富集分支）。2026-10-09 已发布包实测踩过。
 * 这条锁死结构：engApplySession 内出现 const 绑定的引擎响应即失败。 */
{
  // 两份 engApplySession：桌面 frontend/index.html 与鸿蒙 rawfile 镜像（同源代码 fork）。
  // 两处都查——鸿蒙镜像曾在桌面修好后继续带着同一个 bug 发货。
  const copies=[['frontend/index.html',script]];
  const rawfilePath=path.join(__dirname,'ohos','entry','src','main','resources','rawfile','index.html');
  if(fs.existsSync(rawfilePath)){
    const rawHtml=fs.readFileSync(rawfilePath,'utf8');
    copies.push(['ohos/.../rawfile/index.html',(rawHtml.match(/<script>([\s\S]*?)<\/script>/)||['',''])[1]]);
  }
  for(const [label,src] of copies){
    const sessStart=src.indexOf('async function engApplySession(');
    assert(sessStart>=0,`${label}: engApplySession 未定义——会话写路径是承重函数，请同步检查 L`);
    const sessEnd=src.indexOf('\nasync function ',sessStart+1);
    const sess=src.slice(sessStart,sessEnd>0?sessEnd:sessStart+2000);
    assert(/let out=JSON\.parse\(/.test(sess),
      `${label}: engApplySession 的响应变量必须是 let（artboard 富集分支会整体替换它）；const 会在响应无 artboards 时抛 TypeError，请同步检查 L`);
    assert(/out=\{\.\.\.out,entry:/.test(sess),
      `${label}: engApplySession 的 artboard 富集分支结构变了——若已移除该分支，请重新评估检查 L 的必要性`);
  }
}

/* 检查 M：版本号单一事实源——仓库根 VERSION 是权威，其余 16 个下游面必须与它一致。
 * 2026-10 的 v0.4.1 实测：鸿蒙包与 AppStream 元数据停在 0.4.0 而桌面显示 0.4.1，
 * 同一版本号在产物间对不上账。node scripts/sync-version.mjs --check 是权威判定。 */
{
  const versionFile=fs.readFileSync(path.join(__dirname,'VERSION'),'utf8').trim();
  assert(/^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/.test(versionFile),
    `VERSION 不是合法语义化版本：${JSON.stringify(versionFile)}`);
  const { execFileSync } = require('node:child_process');
  try{
    execFileSync(process.execPath,[path.join(__dirname,'scripts','sync-version.mjs'),'--check'],{stdio:'pipe'});
  }catch(e){
    assert.fail('版本号下游面漂移（跑 node scripts/sync-version.mjs 修正）：\n'+
      String((e.stderr||e.stdout||e.message)).trim());
  }
}

/* 检查 N：「关于」页更新日志的顶端条目必须等于 APP_VER。
 * 发新版的完整动作是 VERSION 改号 → sync-version → RELEASE_NOTES 顶端加一条；
 * 忘了 latter 时关于页会给用户展示旧版本的日志——和 v0.4.1「两个版本号」事故
 * 同构（展示面与事实源脱节），所以在测试门锁死。 */
{
  const appVer=(script.match(/const APP_VER='([^']*)'/)||[])[1];
  assert(appVer,'未能提取 APP_VER（结构变了请同步检查 N）');
  const relSrc=script.slice(script.indexOf('const RELEASE_NOTES'),script.indexOf('function renderAboutLog('));
  assert(relSrc.includes('const RELEASE_NOTES'),'RELEASE_NOTES 未定义——「关于」页更新日志是承重数据，请同步检查 N');
  const topVer=(relSrc.match(/\{v:'([^']*)'/)||[])[1];
  assert.equal(topVer,appVer,
    `更新日志顶端条目 (v${topVer}) 与 APP_VER (v${appVer}) 不一致——发新版须在 RELEASE_NOTES 顶端补条目，请同步检查 N`);
}

/* 检查 O：热区标注与 UI 解耦——热区是热区，UI 是 UI。
 * 旧实现把交互标注直接刷在 UI 节点本体上（g[data-flow-trigger]>rect 改描边、
 * >text 改字色），「隐藏热区」更是把 UI 的 rect/text 刷透明——一隐藏整个
 * 原型白板（2026-10-10 实测）。锁死两条：交互标注只允许画在独立覆盖层
 * （.flow-hot-outline）；play-hide-hot 只允许隐藏热区层，不得触碰 UI 本体。 */
{
  assert(!/g\[data-flow-trigger\]\s*>\s*(rect|text)\s*\{/.test(html),
    '热区标注不得改写 UI 节点本体（g[data-flow-trigger]>rect/text 选择器已废）——交互标注必须走 .flow-hot-outline 独立覆盖层，请同步检查 O');
  assert(!/play-hide-hot[^{]*>\s*(rect|text)\s*\{/.test(html),
    'play-hide-hot 只允许隐藏热区标注层（.pm-hot / .flow-hot-outline），不得把 UI 本体刷透明，请同步检查 O');
  assert(/\.frame-wrap svg g\[data-flow-trigger\] \.flow-hot-outline\{[^}]*stroke:#22C55E/.test(html),
    '热区覆盖层样式缺失（.flow-hot-outline 虚线描边）——请同步检查 O');
  assert(/body\.play-hide-hot \.frame-wrap svg \.flow-hot-outline\{display:none\}/.test(html),
    'play-hide-hot 未隐藏热区覆盖层——请同步检查 O');
  assert(/flow-hot-outline/.test(script),
    'renderStage 未注入热区覆盖 rect（flow-hot-outline）——请同步检查 O');
  // 演示起点与栈底返回按交互图判定（demoStartBoard/demoInbound）——否则
  // 「选中第二页进演示」会把入口/细节页当栈底，返回无效（2026-10-10 实测）
  assert(/function demoTapGraph\(/.test(script)&&/function demoInbound\(/.test(script)&&/function demoStartBoard\(/.test(script),
    '演示导航交互图工具缺失（demoTapGraph/demoInbound/demoStartBoard）——请同步检查 O');
  assert(/const startAb=demoStartBoard\(\)/.test(script),
    '演示起点未按交互图判定（demoStartBoard）——请同步检查 O');
  // 返回判定单源于引擎（session_interactions 导出 builtin back）——客户端
  // isBackish 启发式已退役，重新出现即双源漂移（2026-10-11 用户决策）
  assert(!/function isBackish/.test(script),
    '客户端 isBackish 启发式已退役——返回判定单源于引擎 interactions 导出，请同步检查 O');
  assert(/hit\.builtin==='back'/.test(script)&&/act==='back'/.test(script),
    'playTap 未消费引擎 builtin back 导出——返回点击链路断裂，请同步检查 O');
}

/* 检查 P：引擎信息与 dev 渠道标识——本地集成模式（ENGINE_LOCAL 标记 → manifest
 * releaseTag='local-dev'）下顶栏常显 DEV 徽标，关于页展示引擎版本/集成模式/来源
 * （用户决策 2026-10-10：dev 渠道明确化）。信息源 vendor/engine-manifest.json 与
 * wasm 同批写入、不会漂移；徽标缺失=测试期分不清本地构建与正式发布。 */
{
  assert(/function initEngineInfo\(/.test(script)&&/function renderEngineInfo\(/.test(script),
    '引擎信息函数缺失（initEngineInfo/renderEngineInfo）——请同步检查 P');
  assert(/initEngineInfo\(\);/.test(script),
    'initEngineInfo 未在启动路径调用——dev 渠道标识失效，请同步检查 P');
  assert(/id="dev-chip"/.test(html)&&/id="eng-ver"/.test(html)&&/id="eng-mode"/.test(html)&&/id="eng-src"/.test(html),
    'dev 徽标/引擎信息 UI（dev-chip/eng-ver/eng-mode/eng-src）缺失——请同步检查 P');
  assert(/releaseTag==='local-dev'/.test(script),
    'dev 渠道判定缺失（releaseTag local-dev）——请同步检查 P');
}

/* 检查 J：Agent 预览必须按 run/generation/序列收口，禁止迟到帧回写终态。 */
assert.match(script,/schedulePreview\(p\.mbt_b64,p\.run,p\.preview_seq\)/,'preview 事件未携带 run/序列进入调度');
assert.match(script,/p\.generation!==previewGeneration\|\|p\.epoch!==viewEpoch/,'paintPreview 缺少 generation/epoch 新鲜度校验');
assert.match(script,/p\.seq<latestPreviewSeq/,'paintPreview 缺少 preview 序列校验');
assert.match(script,/if\(!preview&&typeof invalidatePreview==='function'\)invalidatePreview\(\)/,'事实源提交未失效旧 preview');
assert.match(script,/if\(terminalCommitted\)\{if\(typeof invalidatePreview==='function'\)invalidatePreview\(\);\}/,'Agent 成功终态仍可能无条件 rollback');
assert.match(script,/boardDragRaf/,'画板拖拽缺少 RAF 合帧');
assert.match(script,/let moved=false,dragRaf=0,lastX=/,'组件拖拽缺少 RAF 状态');

/* 检查 K：i18n 闭环契约——生成标记/确认框收口/过滤器 label/菜单表方向/多窗口同步 */
assert.match(script,/\/\* I18N_GENERATED_START/,'字典生成标记缺失（scripts/gen-i18n.py --write 无法回写 HTML）');
assert.match(script,/\/\* I18N_GENERATED_END \*\//,'字典生成结束标记缺失');
assert.equal((script.match(/invoke\('confirm_discard'/g)||[]).length,1,'confirm_discard 必须唯一经 confirmDiscard() helper 调用（绕过 helper 即漏翻译）');
assert.match(script,/function confirmDiscard\(title,message,labels\)/,'confirmDiscard helper 结构变了（请同步检查 K）');
assert.match(script,/okLabel:ok,cancelLabel:cancel/,'确认框按钮文案未参数化（非中文仍弹中文按钮）');
assert.match(script,/filterLabel:L\('deepDesign 视觉文档'\)/,'DDP 对话框过滤器未本地化');
assert.match(script,/htmlFilterLabel:L\('HTML 原型'\)/,'导出对话框过滤器未本地化');
assert.match(script,/addEventListener\('storage',ev=>\{/,'多窗口偏好同步（storage 监听）缺失');
assert.match(script,/dd-lang'&&ev\.newValue\)setLang\(ev\.newValue,false\)/,'语言跨窗口同步结构变了（请同步检查 K）');
assert.match(script,/function Lfmt\(text,params\)/,'模板翻译助手 Lfmt 缺失（带变量文案整句查字典永远查不中）');
assert.match(script,/p\.closest\('\.declview'\)\|\|p\.closest\('#stage'\)\|\|p\.closest\('#decl-stage'\)/,'applyI18n 未排除画布/源码区（用户与 MBT 内容会被误翻）');
assert.match(script,/return L\('刚刚'\);/,'relTime 未走翻译 choke point（非中文时间残留）');
assert(libRs.includes('("檔案","文件")')&&!libRs.includes('("文件","檔案")'),'zh-TW/HK 菜单表方向反了——menu_t 按 (译文, zh-CN 键) 匹配');

/* 检查 I：函数不得重复定义。内联单文件无打包器/linter，`function applyI18n()`
 * 写两遍时后者静默遮蔽前者（2026-09 i18n 事故：带快照恢复的新实现被文件尾部的
 * 旧实现覆盖，切回简中永久失效）——vm 只执行其中之一，其余防线全部看不见。 */
{
  const names=[...script.matchAll(/\bfunction\s+([A-Za-z_$][\w$]*)\s*\(/g)].map(m=>m[1]);
  const dup={};
  names.forEach(n=>{if(names.filter(x=>x===n).length>1)dup[n]=names.filter(x=>x===n).length;});
  assert.deepEqual(Object.keys(dup),[],`函数重复定义（后者静默遮蔽前者）：${JSON.stringify(dup)}`);
}

/* 检查 H：Tauri 命令 ↔ 前端 invoke 双向 parity。
 * 正向：lib.rs 注册但前端零调用的命令 = 死命令（list_ddp_projects 曾作为
 * "多项目地基"裸奔无消费者）；反向：前端 invoke 未注册命令 = 运行时必炸
 * （自定义命令不经 ACL，无编译期保护，全靠这条对账）。 */
const handlerList=(libRs.match(/generate_handler!\s*\[([\s\S]*?)\]/)||[])[1]||'';
const rustCmds=new Set([...handlerList.matchAll(/([a-z_][a-z0-9_]*)/g)].map(m=>m[1]));
const feCmds=new Set([...script.matchAll(/\binvoke\('([a-z_][a-z0-9_]*)'/g)].map(m=>m[1]));
assert(rustCmds.size>0,'未能从 lib.rs 提取命令注册表（提取逻辑失效，请同步更新检查 H）');
assert(feCmds.size>0,'未能从前端提取 invoke 调用（提取逻辑失效，请同步更新检查 H）');
const unreferenced=[...rustCmds].filter(c=>!feCmds.has(c));
const unregistered=[...feCmds].filter(c=>!rustCmds.has(c));
assert.deepEqual(unreferenced,[],`Rust 命令无前端消费者（死命令）：${unreferenced}`);
assert.deepEqual(unregistered,[],`前端 invoke 了未注册命令（运行时必炸）：${unregistered}`);

/* ---------- 动态检查：真实状态机 ---------- */
function fn(name){const start=script.indexOf('function '+name+'(');assert(start>=0,name);const brace=script.indexOf('){',start)+1;let depth=1,i=brace+1;for(;depth;i++){if(script[i]==='{')depth++;if(script[i]==='}')depth--;}return (script.slice(start-6,start)==='async '?'async ':'')+script.slice(start,i)}
const context=vm.createContext({console,window:{addEventListener(){}},document:{addEventListener(){},querySelectorAll:()=>[],body:{nodeType:1,querySelectorAll:()=>[]},createTreeWalker:()=>({nextNode:()=>null}),documentElement:{classList:{add(){}}},getElementById:element},navigator:{platform:'Win32',userAgent:'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},performance:{now:()=>0},setTimeout,clearTimeout,requestAnimationFrame(fn){if(typeof fn==='function')fn();},MutationObserver:class{observe(){}},NodeFilter:{SHOW_TEXT:4},btoa:s=>Buffer.from(s,'binary').toString('base64'),atob:s=>Buffer.from(s,'base64').toString('binary'),encodeURIComponent,decodeURIComponent,escape,unescape});
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
 // 批注持久化注入层（moonviz#20 过渡）：合成/提取/幂等往返——引擎 canonical 丢注释，
 // 前端 inject 层必须保持批注块随 mbtText 存活（丢锚 = DDP 批注静默丢失）
 const canonSample='---\nmoonviz:\n  format: visual-document\n  revision: 1\n  entry: a\n---\n\n# a\n';
 const vset=expr=>vm.runInContext(expr,context);
 Object.assign(context,{canonSample});
 vset('inkPaths=[[{x:.1,y:.2},{x:.5,y:.6}]]');
 const withInk=vset('inkInject(canonSample)');
 assert(withInk.includes('<!-- deepdesign:ink '),'批注块未注入');
 Object.assign(context,{withInk});
 assert(vset('inkInject(withInk)===withInk')===true,'同路径重复注入应幂等（字节不变）');
 vset('inkPaths=[[{x:.3,y:.4},{x:.7,y:.8}]]');
 const reInk=vset('inkInject(withInk)');
 assert((reInk.match(/deepdesign:ink/g)||[]).length===1,'旧块应被替换而非叠加');
 Object.assign(context,{reInk});
 assert(vset('inkRestore(reInk)')===true,'提取恢复');
 assert(vset('inkPaths[0][0].x')===.3,'恢复坐标正确');
 vset('inkPaths=[]');
 assert(!vset('inkInject(reInk)').includes('deepdesign:ink'),'清空批注后注入应移除块');
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
 // 检查 E：引擎写路径已迁 _in 槽契约（engine-v0.1.2）——承重符号必须在场，
// 退役的写方向编码器不得残留引用（删函数漏引用是 9f48220 类事故的形态）
assert(!/engWriteStr/.test(script), 'engWriteStr 已退役（写方向走 engSlotLoad/_in 槽），不得残留引用');
assert(/function engSlotLoad\(/.test(script), 'engSlotLoad 未定义——_in 槽装载是 engApply/engRender/engValidate 的承重路径');
assert(/apply_agent_op_in/.test(script) && /render_mbt_in/.test(script) && /validate_mbt_in/.test(script), 'engApply/engRender/engValidate 必须走 *_in 变体');

console.log(`Studio checks passed: ${INTERACTIVE_SURFACE.length} 个交互层函数在场、${menuIds.length} 个原生菜单 id 全映射、内联处理器无悬空引用；状态机：队列、种子引导、选区、draft、opacity`);
})().catch(e=>{console.error(e);process.exitCode=1});
