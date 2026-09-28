#!/usr/bin/env node
/* i18n catalog builder：把「运行字典（HTML 注入块）」「gen-i18n.py T 表」「新增 UI 键」
 * 对账合并，产出仓库内两份事实源：
 *   scripts/i18n-full.json  — 全量 zh-CN 键清单（gen-i18n.py 的输入）
 *   scripts/i18n-extra.json — live-only 键的既有翻译移植 + 新增键翻译（ja,ko,en,fr）
 * 之后再跑 `python scripts/gen-i18n.py --write` 重建 HTML 注入块。
 * 重复 T 键、六语言键集合不一致都会让本工具非零退出（漂移必须显性）。 */
const fs=require('fs'),path=require('path');
const ROOT=path.resolve(__dirname,'..');
const html=fs.readFileSync(path.join(ROOT,'frontend','index.html'),'utf8');
const py=fs.readFileSync(path.join(ROOT,'scripts','gen-i18n.py'),'utf8');

/* ── 新增 UI 键（本次修复引入：确认框/文件过滤器/删除画板/相对时间/模板分组）── */
const NEW_ENTRIES={
  '未保存的更改':['変更未保存','저장되지 않은 변경','Unsaved Changes','Modifications non enregistrées'],
  '当前文档有未保存的更改（含源码草稿），确定退出吗？':['未保存の変更（ソース草案を含む）があります。終了しますか？','저장되지 않은 변경(소스 초안 포함)이 있습니다. 종료할까요?','This document has unsaved changes (including source draft). Quit anyway?','Ce document a des modifications non enregistrées (brouillon source inclus). Quitter ?'],
  '当前文档有未保存的更改（含源码草稿），打开新文件将丢弃这些更改。':['未保存の変更（ソース草案を含む）があります。新しいファイルを開くと破棄されます。','저장되지 않은 변경(소스 초안 포함)이 있습니다. 새 파일을 열면 버려집니다.','This document has unsaved changes (including source draft). Opening a new file will discard them.','Ce document a des modifications non enregistrées (brouillon source inclus). Ouvrir un autre fichier les ignorera.'],
  '当前文档有未保存的更改（含源码草稿），新建将丢弃这些更改。':['未保存の変更（ソース草案を含む）があります。新規作成で破棄されます。','저장되지 않은 변경(소스 초안 포함)이 있습니다. 새 프로젝트를 만들면 버려집니다.','This document has unsaved changes (including source draft). Creating a new project will discard them.','Ce document a des modifications non enregistrées (brouillon source inclus). Un nouveau projet les ignorera.'],
  '继续编辑':['編集を続ける','계속 편집','Keep Editing',"Continuer l'édition"],
  '放弃更改':['変更を破棄','변경 사항 버리기','Discard Changes','Abandonner les modifications'],
  '删除画板':['ボードを削除','보드 삭제','Delete Board','Supprimer la planche'],
  '删除画板 {id}？（⌘Z 可撤销）':['ボード {id} を削除？（⌘Z で取り消せます）','보드 {id} 삭제? (⌘Z 실행 취소)','Delete board {id}? (Undo with ⌘Z)','Supprimer la planche {id} ? (⌘Z pour annuler)'],
  '至少保留一个画板':['少なくとも1つのボードを残してください','최소 하나의 보드는 남겨야 합니다','Keep at least one board','Gardez au moins une planche'],
  '画板 {id} 已删除':['ボード {id} を削除しました','보드 {id} 삭제됨','Board {id} deleted','Planche {id} supprimée'],
  'deepDesign 视觉文档':['deepDesign ビジュアル文書','deepDesign 비주얼 문서','deepDesign Visual Document','Document visuel deepDesign'],
  'HTML 原型':['HTML プロトタイプ','HTML 프로토타입','HTML Prototype','Prototype HTML'],
  'SVG 图形':['SVG グラフィック','SVG 그래픽','SVG Graphics','Graphique SVG'],
  '刚刚':['たった今','방금','Just now',"À l'instant"],
  '{n} 分钟前':['{n} 分前','{n}분 전','{n} min ago','il y a {n} min'],
  '{n} 小时前':['{n} 時間前','{n}시간 전','{n} h ago','il y a {n} h'],
  '{n} 天前':['{n} 日前','{n}일 전','{n} d ago','il y a {n} j'],
  '手机原型':['モバイル','모바일','Mobile','Mobile'],
  'Web 页面':['Web ページ','웹 페이지','Web Pages','Pages Web'],
  '桌面 / 自适应':['デスクトップ / アダプティブ','데스크톱 / 적응형','Desktop / Adaptive','Bureau / Adaptatif'],
};

/* ── 解析 HTML 运行字典（注入块 = I18N_DICT['xx']={json} 行）── */
const langs=['zh-TW','zh-HK','en','ja','ko','fr'];
const live={};
for(const m of html.matchAll(/I18N_DICT\['(zh-TW|zh-HK|en|ja|ko|fr)'\]=(\{.*?\});/g)){
  live[m[1]]=JSON.parse(m[2]);
}
const missingLang=langs.filter(l=>!live[l]);
if(missingLang.length){console.error('FATAL 运行字典缺语言对象：'+missingLang);process.exit(1);}
const keysets=langs.map(l=>new Set(Object.keys(live[l])));
const base=keysets[0];
if(keysets.some(s=>s.size!==base.size||[...base].some(k=>!s.has(k)))){
  console.error('FATAL 六语言运行字典键集合不一致');process.exit(1);
}

/* ── 解析 gen-i18n.py T 表键（每行形如 "键":(...)，）── */
const tKeys=[];const dup=[];
for(const m of py.matchAll(/^\s*"((?:[^"\\]|\\.)*)":\(/gm)){
  let k;try{k=JSON.parse('"'+m[1]+'"');}catch{continue;}
  if(tKeys.includes(k))dup.push(k);else tKeys.push(k);
}
if(dup.length){console.error('FATAL T 表重复键（后者静默遮蔽前者）：\n  '+dup.join('\n  '));process.exit(1);}

/* ── live-only 键：把现有翻译移植进 extra，防重建时丢译 ── */
const tSet=new Set(tKeys);
const extra={};
let ported=0;
for(const k of Object.keys(live['en'])){
  if(tSet.has(k))continue;
  extra[k]=[live['ja'][k],live['ko'][k],live['en'][k],live['fr'][k]];
  ported++;
}
for(const[k,v]of Object.entries(NEW_ENTRIES)){
  if(extra[k])console.warn('WARN 新增键已存在于 live 移植：'+k);
  extra[k]=v;
}

/* ── 全量 catalog：live ∪ T ∪ extra（SKIP 由 gen-i18n.py 处理）── */
const all=[...new Set([...Object.keys(live['en']),...tKeys,...Object.keys(extra)])].sort();

/* ── 无翻译落点检查：不在 T 也不在 extra 的键将退回 zh 原文 ── */
const noTrans=all.filter(k=>!tSet.has(k)&&!extra[k]);
if(noTrans.length){console.warn('WARN 以下键无翻译来源（将回退 zh 原文）：\n  '+noTrans.join('\n  '));}

fs.writeFileSync(path.join(ROOT,'scripts','i18n-full.json'),JSON.stringify({all},null,1)+'\n');
fs.writeFileSync(path.join(ROOT,'scripts','i18n-extra.json'),JSON.stringify(extra,null,1)+'\n');
console.log(`catalog: ${all.length} keys | live=${Object.keys(live['en']).length} T=${tKeys.length} ported=${ported} new=${Object.keys(NEW_ENTRIES).length} extra=${Object.keys(extra).length}`);
