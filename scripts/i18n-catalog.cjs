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

  /* ── 设置「关于」页（全平台可见；macOS 另有系统级 About，版本同源 APP_VER）── */
  '关于':['について','정보','About','À propos'],
  '更新日志':['更新履歴','업데이트 로그','Changelog','Journal des modifications'],
  '引擎':['エンジン','엔진','Engine','Moteur'],
  '引擎版本':['エンジンバージョン','엔진 버전','Engine version','Version du moteur'],
  '集成模式':['統合モード','통합 모드','Integration mode',"Mode d'intégration"],
  '引擎来源':['エンジンソース','엔진 소스','Engine source','Source du moteur'],
  '开源感谢':['オープンソース謝辞','오픈소스 감사','Open Source Acknowledgements','Remerciements open source'],
  'AI 原生原型设计工具':['AI ネイティブプロトタイピングツール','AI 네이티브 프로토타이핑 도구','AI-native prototyping tool','Outil de prototypage IA natif'],
  '人类画布操作与 Agent 修改都经 MoonViz 引擎双门校验，回写同一份 .mbt.md 视觉文档；.ddp 是它的认证加密容器。':['キャンバス操作も Agent の変更も MoonViz エンジンの二重ゲートで検証され、同一の .mbt.md ビジュアル文書に書き戻されます。.ddp はその認証暗号化コンテナです。','캔버스 조작과 Agent 변경 모두 MoonViz 엔진의 이중 게이트로 검증되어 동일한 .mbt.md 비주얼 문서에 기록됩니다. .ddp는 해당 인증 암호화 컨테이너입니다.','Canvas edits and Agent changes are both validated by the MoonViz engine dual gates and written back to the same .mbt.md visual document; .ddp is its authenticated encrypted container.',"Les modifications du canevas comme celles de l'agent sont validées par les doubles gardes du moteur MoonViz puis réécrites dans le même document visuel .mbt.md ; .ddp en est le conteneur chiffré authentifié."],
  '本应用建立在开源社区之上——以上项目版权归各自作者所有。':['本アプリはオープンソースコミュニティの上に成り立っています。掲載プロジェクトの著作権はそれぞれの作者に帰属します。','이 앱은 오픈소스 커뮤니티 위에 세워졌습니다. 위 프로젝트의 저작권은 각 저자에게 있습니다.','This app stands on the open source community — the projects above remain the property of their respective authors.',"Cette application s'appuie sur la communauté open source — les projets listés restent la propriété de leurs auteurs respectifs."],
  '桌面应用框架（窗口 · 菜单 · 打包）':['デスクトップアプリフレームワーク（ウィンドウ・メニュー・パッケージング）','데스크톱 앱 프레임워크(창 · 메뉴 · 패키징)','Desktop app framework (windows · menus · packaging)',"Framework d'application bureau (fenêtres · menus · packaging)"],
  '进程内 WASM 引擎宿主':['インプロセス WASM エンジンホスト','인프로세스 WASM 엔진 호스트','In-process WASM engine host','Hôte moteur WASM intra-processus'],
  '视觉文档引擎（双门校验 · .mbt.md）':['ビジュアル文書エンジン（二重ゲート検証 · .mbt.md）','비주얼 문서 엔진(이중 게이트 검증 · .mbt.md)','Visual document engine (dual gates · .mbt.md)','Moteur de document visuel (doubles gardes · .mbt.md)'],
  'OpenAI 协议类型层':['OpenAI プロトコル型レイヤー','OpenAI 프로토콜 타입 레이어','OpenAI protocol type layer','Couche de types du protocole OpenAI'],
  'Rust 网络与序列化基座':['Rust のネットワーク・シリアライズ基盤','Rust 네트워크 · 직렬화 기반','Rust networking & serialization core','Socle réseau et sérialisation Rust'],
  '模型元数据快照（多预设对账）':['モデルメタデータスナップショット（複数プリセット照合）','모델 메타데이터 스냅샷(다수 프리셋 대조)','Model metadata snapshot (preset reconciled)','Instantané de métadonnées de modèles (préréglages réconciliés)'],
  'Linux 系统深浅色跟随':['Linux のシステム明暗テーマ追従','Linux 시스템 밝기 테마 따르기','Follows Linux system light/dark theme',"Suit le thème clair/sombre du système sous Linux"],

  /* ── 「关于」页更新日志条目（RELEASE_NOTES；顶端版本须等于 APP_VER，test_studio 检查 N）── */
  '修复双击编辑文字提交失败（影响所有用户）':['ダブルクリック編集のコミット失敗を修正（全ユーザーに影響）','더블클릭 텍스트 편집 커밋 실패 수정(모든 사용자 영향)','Fixed double-click text editing failing to commit (affected all users)',"Correction de l'échec de validation de l'édition par double-clic (affectait tous les utilisateurs)"],
  '版本号统一：仓库根 VERSION 文件为唯一事实源':['バージョン番号を統一：リポジトリ直下の VERSION ファイルが唯一の情報源','버전 번호 통일: 저장소 루트 VERSION 파일이 유일한 기준','Unified versioning: the repository-root VERSION file is the single source of truth',"Version unifiée : le fichier VERSION à la racine du dépôt est la source unique de vérité"],
  '引擎升级 0.1.8：多画板撤销修复':['エンジン 0.1.8 に更新：複数アートボードの取り消しを修正','엔진 0.1.8 업그레이드: 다중 아트보드 실행 취소 수정','Engine upgraded to 0.1.8: multi-artboard undo fix',"Moteur mis à jour en 0.1.8 : correction de l'annulation multi-planches"],
  '鸿蒙版首发；Linux 提供 deb 与 AppImage（玲珑下线）':['HarmonyOS 版を初公開。Linux は deb と AppImage を提供（linyaps 廃止）','HarmonyOS 버전 첫 공개; Linux는 deb 및 AppImage 제공(링롱폐지)','HarmonyOS debut; Linux ships deb and AppImage (linglong retired)','Première version HarmonyOS ; Linux fournit deb et AppImage (linglong abandonné)'],
  '闲置画板清扫：Agent run 前后自动清理空占位':['アイドルアートボードの清掃：Agent run の前後で空きプレースホルダーを自動削除','유휴 아트보드 정리: Agent 실행 전후로 빈 자리표시자 자동 정리','Idle artboard sweep: empty placeholders cleaned around Agent runs',"Nettoyage des planches inactives : les espaces réservés vides sont purgés autour des exécutions de l'agent"],
  '步数上限可调（200/500/1000/2000）':['ステップ上限を調整可能（200/500/1000/2000）','단계 상한 조정 가능(200/500/1000/2000)','Adjustable step limit (200/500/1000/2000)','Limite de pas ajustable (200/500/1000/2000)'],
  '演示模式与 Neu 主题修复':['デモモードと Neu テーマの修正','데모 모드 및 Neu 테마 수정','Demo mode and Neu theme fixes','Corrections du mode démo et du thème Neu'],

  /* ── Agent op → 人类行为字典（轨迹时间线；键 = Lfmt 简中模板，与 AGENT_OP_HUMAN 对账）── */
  '读取文档源码':['文書ソースを読み取り','문서 소스 읽기','Reading document source','Lecture de la source du document'],
  '浏览组件库':['コンポーネントライブラリを閲覧','컴포넌트 라이브러리 탐색','Browsing component library','Navigation dans la bibliothèque de composants'],
  '从模板创建画板 {name}':['テンプレートからボード {name} を作成','템플릿에서 보드 {name} 생성','Creating board {name} from template','Création de la planche {name} depuis un modèle'],
  '创建画板 {name}':['ボード {name} を作成','보드 {name} 생성','Creating board {name}','Création de la planche {name}'],
  '复制画板为 {id}':['ボードを {id} として複製','보드를 {id}(으)로 복제','Duplicating board as {id}','Duplication de la planche en {id}'],
  '删除画板 {id}':['ボード {id} を削除','보드 {id} 삭제','Deleting board {id}','Suppression de la planche {id}'],
  '在画板 {ab} 放置组件 {comp}':['ボード {ab} にコンポーネント {comp} を配置','보드 {ab}에 컴포넌트 {comp} 배치','Placing component {comp} in board {ab}','Placement du composant {comp} dans la planche {ab}'],
  '在画板 {ab} 移动节点 {node}':['ボード {ab} のノード {node} を移動','보드 {ab}의 노드 {node} 이동','Moving node {node} in board {ab}','Déplacement du nœud {node} dans la planche {ab}'],
  '在画板 {ab} 修改节点 {node}':['ボード {ab} のノード {node} を変更','보드 {ab}의 노드 {node} 수정','Updating node {node} in board {ab}','Modification du nœud {node} dans la planche {ab}'],
  '在画板 {ab} 删除节点 {node}':['ボード {ab} のノード {node} を削除','보드 {ab}의 노드 {node} 삭제','Deleting node {node} in board {ab}','Suppression du nœud {node} dans la planche {ab}'],
  '在画板 {ab} 复制节点 {node}':['ボード {ab} のノード {node} をコピー','보드 {ab}의 노드 {node} 복사','Copying node {node} in board {ab}','Copie du nœud {node} dans la planche {ab}'],
  '在画板 {ab} 调整 {node} 的图层顺序':['ボード {ab} の {node} のレイヤー順を調整','보드 {ab}에서 {node}의 레이어 순서 조정','Reordering layer {node} in board {ab}','Réordonnancement du calque {node} dans la planche {ab}'],
  '在画板 {ab} 翻转节点 {node}':['ボード {ab} のノード {node} を反転','보드 {ab}의 노드 {node} 뒤집기','Flipping node {node} in board {ab}','Retournement du nœud {node} dans la planche {ab}'],
  '在画板 {ab} 编组节点':['ボード {ab} でノードをグループ化','보드 {ab}에서 노드 그룹화','Grouping nodes in board {ab}','Groupement de nœuds dans la planche {ab}'],
  '在画板 {ab} 取消编组':['ボード {ab} でグループ化を解除','보드 {ab}에서 그룹 해제','Ungrouping nodes in board {ab}','Dégroupement dans la planche {ab}'],
  '在画板 {ab} 对齐节点':['ボード {ab} でノードを整列','보드 {ab}에서 노드 정렬','Aligning nodes in board {ab}','Alignement de nœuds dans la planche {ab}'],
  '为画板 {ab} 应用布局约束':['ボード {ab} にレイアウト制約を適用','보드 {ab}에 레이아웃 제약 적용','Applying layout constraint to board {ab}',"Application d'une contrainte de mise en page à la planche {ab}"],
  '在画板 {ab} 重设组件 {comp} 的样式':['ボード {ab} のコンポーネント {comp} のスタイルを再設定','보드 {ab}의 컴포넌트 {comp} 스타일 재설정','Restyling component {comp} in board {ab}','Restylisation du composant {comp} dans la planche {ab}'],
  '调整画板 {ab} 的尺寸':['ボード {ab} のサイズを変更','보드 {ab} 크기 조정','Resizing board {ab}','Redimensionnement de la planche {ab}'],
  '为画板 {ab} 生成响应式布局':['ボード {ab} のレスポンシブレイアウトを生成','보드 {ab}의 반응형 레이아웃 생성','Generating responsive layout for board {ab}',"Génération d'une mise en page responsive pour la planche {ab}"],
  '在画板 {ab} 为节点 {node} 添加交互':['ボード {ab} のノード {node} にインタラクションを追加','보드 {ab}의 노드 {node}에 인터랙션 추가','Adding interaction to node {node} in board {ab}',"Ajout d'une interaction au nœud {node} dans la planche {ab}"],
  '在画板 {ab} 移除节点 {node} 的交互':['ボード {ab} のノード {node} のインタラクションを削除','보드 {ab}의 노드 {node} 인터랙션 제거','Removing interaction of node {node} in board {ab}',"Suppression de l'interaction du nœud {node} dans la planche {ab}"],
  '在画板 {ab} 为节点 {node} 添加状态':['ボード {ab} のノード {node} に状態を追加','보드 {ab}의 노드 {node}에 상태 추가','Adding state to node {node} in board {ab}',"Ajout d'un état au nœud {node} dans la planche {ab}"],
  '切换节点 {node} 的状态':['ノード {node} の状態を切り替え','노드 {node}의 상태 전환','Switching state of node {node}',"Basculement de l'état du nœud {node}"],
  '建立画板 {a} 到 {b} 的跳转':['ボード {a} から {b} への遷移を設定','보드 {a}에서 {b}(으)로 이동 연결 설정','Linking board {a} to {b}','Création de la navigation de la planche {a} vers {b}'],
  '移除画板 {a} 到 {b} 的跳转':['ボード {a} から {b} への遷移を削除','보드 {a}에서 {b}(으)로 이동 연결 제거','Unlinking board {a} from {b}','Suppression de la navigation de la planche {a} vers {b}'],
  '应用主题 {t}':['テーマ {t} を適用','테마 {t} 적용','Applying theme {t}','Application du thème {t}'],
  '设置颜色令牌 {t}':['カラートークン {t} を設定','컬러 토큰 {t} 설정','Setting color token {t}','Définition du token de couleur {t}'],
  '自动修复画板 {ab} 的布局':['ボード {ab} のレイアウトを自動修正','보드 {ab}의 레이아웃 자동 수정','Auto-fixing layout of board {ab}','Correction automatique de la mise en page de la planche {ab}'],
  '清点画板':['ボード一覧を取得','보드 목록 조회','Listing boards','Liste des planches'],
  '查看跳转连线':['遷移ワイヤを確認','이동 연결 확인','Checking navigation flows','Vérification des flux de navigation'],
  '浏览模板库':['テンプレートライブラリを閲覧','템플릿 라이브러리 탐색','Browsing template library','Navigation dans la bibliothèque de modèles'],
  '查看设计令牌':['デザイントークンを確認','디자인 토큰 확인','Checking design tokens','Vérification des tokens de design'],
  '查看主题清单':['テーマ一覧を取得','테마 목록 조회','Listing themes','Liste des thèmes'],
  '查询引擎操作清单':['エンジン操作一覧を取得','엔진 작업 목록 조회','Listing engine operations','Liste des opérations du moteur'],
  '检查画板 {ab} 的规范':['ボード {ab} の規範をチェック','보드 {ab} 규범 검사','Linting board {ab}','Vérification des règles de la planche {ab}'],
  '评审画板 {ab} 的设计':['ボード {ab} のデザインをレビュー','보드 {ab} 디자인 검토','Reviewing design of board {ab}','Revue du design de la planche {ab}'],
  '查询画板 {ab} 的信息':['ボード {ab} の情報を照会','보드 {ab} 정보 조회','Querying board {ab}','Interrogation de la planche {ab}'],
  '推断画板 {ab} 的设计规律':['ボード {ab} のデザイン傾向を推測','보드 {ab}의 디자인 패턴 추론','Inferring design patterns of board {ab}','Inférence des motifs de design de la planche {ab}'],
  '读取画板 {ab} 的规格':['ボード {ab} の仕様を読み取り','보드 {ab} 사양 읽기','Reading spec of board {ab}','Lecture des spécifications de la planche {ab}'],
  '检查画板 {ab} 的缺失项':['ボード {ab} の欠落項目をチェック','보드 {ab} 누락 항목 검사','Finding gaps in board {ab}','Recherche des manques dans la planche {ab}'],
  '查看画板 {ab} 的状态':['ボード {ab} の状態を確認','보드 {ab}의 상태 확인','Checking states of board {ab}','Vérification des états de la planche {ab}'],
  '查看画板 {ab} 的交互':['ボード {ab} のインタラクションを確認','보드 {ab}의 인터랙션 확인','Checking interactions of board {ab}','Vérification des interactions de la planche {ab}'],
  '导出画板 {ab} 为 SVG':['ボード {ab} を SVG にエクスポート','보드 {ab}를 SVG로 내보내기','Exporting board {ab} as SVG','Export de la planche {ab} en SVG'],
  '导出 HTML 原型':['HTML プロトタイプをエクスポート','HTML 프로토타입 내보내기','Exporting HTML prototype','Export du prototype HTML'],
  '提取画板 {ab} 的设计系统':['ボード {ab} のデザインシステムを抽出','보드 {ab}의 디자인 시스템 추출','Extracting design system of board {ab}','Extraction du design system de la planche {ab}'],
  '在画板 {ab} 模拟点击':['ボード {ab} でタップをシミュレート','보드 {ab}에서 탭 시뮬레이션','Simulating tap in board {ab}','Simulation de tap dans la planche {ab}'],
  '测量页面性能':['ページ性能を測定','페이지 성능 측정','Benchmarking page performance','Mesure des performances de la page'],
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
