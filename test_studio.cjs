const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const html=fs.readFileSync(path.join(__dirname,'frontend','index.html'),'utf8');
const source=html.match(/<script>([\s\S]*?)<\/script>/)[1];
const elements=new Map();
function element(id){if(!elements.has(id))elements.set(id,{value:'',style:{},dataset:{},textContent:'',innerHTML:'',className:'',classList:{add(){},remove(){},toggle(){}},setAttribute(){},addEventListener(){},focus(){},querySelectorAll(){return[]},replaceChildren(){}});return elements.get(id)}
const context=vm.createContext({console,window:{addEventListener(){}},document:{documentElement:{classList:{add(){}}},getElementById:element},performance:{now:()=>0},setTimeout,clearTimeout,requestAnimationFrame(){},btoa:s=>Buffer.from(s,'binary').toString('base64'),atob:s=>Buffer.from(s,'base64').toString('binary'),encodeURIComponent,decodeURIComponent,escape,unescape});
function fn(name){const start=source.indexOf('function '+name+'(');assert(start>=0,name);const brace=source.indexOf('){',start)+1;let depth=1,i=brace+1;for(;depth;i++){if(source[i]==='{')depth++;if(source[i]==='}')depth--;}return (source.slice(start-6,start)==='async '?'async ':'')+source.slice(start,i)}
// Use the real state/apply/queue functions, with presentation and engine boundaries stubbed.
vm.runInContext(source.slice(source.indexOf("const APP_VER"),source.indexOf('async function execCli')),context);
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
 assert.equal(fs.readFileSync(path.join(__dirname,'frontend/index.html'),'utf8'),html);
 console.log('Studio regression checks passed: queue, board add, selection, drafts, failed new project, opacity, frontend parity');
})().catch(e=>{console.error(e);process.exitCode=1});
