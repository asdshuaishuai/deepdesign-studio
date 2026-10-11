// deepDesign Studio —— 鸿蒙原生交互层（纯 ArkUI）
// 布局与视觉 1:1 复刻通用版 frontend/index.html：
//   topbar 46 / left 252 / right 360 / statusbar 27，
//   设计 token（色值/字号/圆角/阴影/间距）逐条对应原版 CSS。
// Agent 默认执行者 = 端侧小艺（AgentService → localChatModel）。

import { coreVersion, ddpEncrypt, ddpDecrypt } from '../core/CoreBridge';
import { appStore, Board, LayerNode, TlEntry, Flow, Interaction, StateDef, TplDef, CompDef, TPLS, TplSize, TPL_FEATURED, TPL_GROUPS, SER_PREFIX } from '../model/AppStore';
import { projectRegistry, RecentItem } from '../model/ProjectRegistry';
import { parseMbtDoc } from '../model/MbtDoc';
import { aiConfig, AiConf } from '../model/AiConfig';
import { uiPrefs, UiLook } from '../model/UiPrefs';
import { HMOS_BRAND, HMOS_PRESSED, HMOS_WARNING, HMOS_SUCCESS, HMOS_PURPLE, HMOS_TEXT_PRIMARY,
  HMOS_TEXT_SECONDARY, HMOS_TEXT_TERTIARY, HMOS_BG_PAGE, HMOS_BG_SUB, HMOS_DIALOG_BG,
  HMOS_COMPONENT_NORMAL, HMOS_SEPARATOR, HMOS_DIALOG_MASK, HMOS_ON_ACCENT,
  HMOS_RADIUS_CARD, HMOS_RADIUS_DIALOG, HMOS_RADIUS_MENU, HMOS_RADIUS_BUTTON, HMOS_RADIUS_CHIP,
  HMOS_RADIUS_TEXT_FIELD, HMOS_RADIUS_ICON, HMOS_FONT_DIALOG_TITLE, HMOS_FONT_BUTTON,
  HMOS_PRESS_SCALE, HmosSizePair, hmosStepDown, HMOS_F_MENU_ROW,
  F_DOCK_QUICK, F_DOCK_CHIP, F_DOCK_ICON, F_DOCK_INPUT, F_KBD, F_DOCK_HINT, F_AGENTMSG,
  F_CLARIFY_HEAD, F_CLARIFY_INPUT, F_TRACK_HEAD, F_TRACK_BODY, F_TRACK_MID, F_TRACK_DETAIL,
  F_TRACK_MS, F_TRACK_FINAL, F_TRACK_FINAL_SUB, F_TOOLBAR, F_TOOLBAR_BADGE,
  F_PROJNAME, F_PROJNAME_L, HMOS_H_CHIP, PAD_CHIP, H_DOCK_INPUT, H_CLARIFY,
  PAD_TRACK_CARD_H, PAD_TRACK_CARD_V, PAD_TRACK_FINAL_H, PAD_TRACK_FINAL_V,
  F_FILECHIP, F_TOOLBAR_GLYPH, H_TOPBAR, H_FILECHIP, H_PILL, T_ICON_TBTN, SH_SEG_SELECTED,
  F_TOOLROW, F_TOOLROW_ICON, F_TOOLROW_FIT, F_ZOOM_GLYPH, F_ZOOM, F_TPL, F_TPL_META, F_GHOST, F_GHOST_DIM,
  F_IA, F_IA_HEAD, F_IA_MINI, F_IA_CHIP, F_WELCOME_SUB, F_WELCOME_KBD, F_WELCOME_SEC,
  F_WELCOME, F_WELCOME_NAME, F_WELCOME_TIME, F_TAIL, F_CLARIFY_GLYPH, F_CLARIFY_X,
  H_TOOLBTN, H_IA, H_WELCOME_ROW, H_TAIL, SH_TOOL_SELECTED, SH_PMAIN_FOCUS,
  F_COMPCELL, F_COMPCELL_SUB, F_LAYER, F_LAYER_NAME, F_LAYER_X, F_LPROJ_ARROW, F_LBTN,
  F_LSEC_MINI, F_LRECENT_HEAD, F_LRECENT_CHECK, F_LRECENT, F_LTAB, F_LSEC,
  F_LBOARD, F_LBOARD_MINI, F_LBOARD_DIM, F_LBOARD_X, F_LEMPTY, F_LSEARCH, F_INSP_LABEL,
  F_LCOMP_NOTE, F_LCOMP_HOW, F_LCOMP_MINI, F_LCOMP_CAT, F_LCOMP_COUNT, F_LFLOW, F_LFLOW_ID,
  F_LHINT, F_LHINT_SUB, F_LSTATUS, LH_LEMPTY,
  H_LBTN, H_LRECENT_ROW, H_LTAB, H_LBOARD_ROW, H_LSEARCH, H_LAYER_ROW,
  F_EMPTY_HEAD, F_EMPTY_DESC, F_EMPTY_HINT, F_EMPTY_KBD, F_SEGCHIP, F_INSP_INPUT,
  F_INSP_HEAD, F_INSP_MINI, F_INSP_VAL, F_INSP_ACT, F_DECL_HEAD, F_DECL, F_DECL_GLYPH,
  LH_DECL, F_INSP_MONO_MINI, F_INSP_MONO, F_RBTN, F_RBTN_ACC, F_RTRACK_HEAD, F_RTRACK_CLR,
  F_RSTATUS_MINI, F_RSTATUS, F_TRACK_SRC, F_TRACK_FINAL_GLYPH, F_RTAB,
  H_SEG, H_SHADOW_ROW, H_DRAFT_INPUT, H_BIND_CHIP, H_BIND_ROW, H_DECL_BTN,
  H_RBTN, H_RBTN_ACC, H_RSTATUS, H_RTAB,
  F_MENU_KBD, F_MENU_TITLE, F_DD_CHECK, F_TOAST, F_DEMO_TITLE, F_DEMO_HEAD, F_DEMO,
  F_DEMO_HINT, F_RMENU_HEAD, F_RMENU, F_RMENU_NAME, F_RMENU_TIME,
  H_MENU_ROW, H_RMENU_ROW,
  F_MODAL_OPT, F_MODAL_DESC, F_MODAL_SUB, F_MODAL_BTN, F_PWD_SUB, F_PWD_TRIES,
  F_SET_CLOSE, F_SET_HEAD, F_SET_VAL, F_SET_MINI,
  F_SET_SEC, F_SET_LABEL, F_SET_MONO_URL, F_SET_MONO_VAL, F_SET_SELECT, F_SET_BTN,
  F_SET_TAG, F_SET_KBD, F_STAB,
  H_EXPORT_OPT, H_PWD_INPUT, H_DLG_BTN, H_SET_FIELD, H_SET_BTN, H_STAB,
  G_SET_FIELD, G_SET_BLOCK } from '../model/Theme';
import { CommandDispatch } from '../invoke/Dispatch';
import { agentService, AgentStep, LineExecOutcome } from '../ai/AgentService';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KeyCode } from '@kit.InputKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';

// Dispatch 返回值的具名形状（Dispatch.ets 内部接口未导出，此处按字段鸭子对齐）：
interface OpenDdpOutcome {
  ok?: boolean;            // OpenDdpResult
  path?: string;           // OpenDdpResult / OpenDdpNeedPassword
  mbtB64?: string;         // OpenDdpResult
  needPassword?: boolean;  // OpenDdpNeedPassword（仅对话框首开；带 path 重试口令不符走 error）
  error?: string;          // CmdError（ddp_decrypt_failed:* / ddp_open_failed:*）
}

interface SaveDdpOutcome {
  ok?: boolean;
  path?: string;
  bytes?: number;
  error?: string;
}

// 引擎命令返回形状（gap-global-3 接线；Dispatch.ets 内部接口未导出，鸭子对齐同上）：
interface EngineStatusReply {
  available?: boolean;
  tag?: string;
  version?: string;
  reason?: string;
}

// engine_apply_human_op 信封（引擎原样透传：ok:false=门拒绝；成功带 mbt_b64 canonical；
// CmdError 形态 error 字段=导出缺失/传输失败，走本地回退）。
interface EngineApplyReply {
  ok?: boolean;
  mbt_b64?: string;
  error?: string;
}

// 统一弹层菜单原语数据形状（batch-2，dd-menu-export/dd-menu-recent）：ddMenuPanel/ddMenuRow
// 消费——导出菜单试点收编 + 后续弹层批次共用。接口显式字段（ArkTS 禁 as Record/any）。
interface DdMenuItem {
  label: string;        // 行文案（逐字对齐原 MenuElement.value）
  kbd: string;          // 右注键位（''=不显；menuRow 同款 monospace 9）
  selected: boolean;    // 选中态：✓列 + accSoft 底 + 600 字重
  danger: boolean;      // 危险动作恒红（同 menuRow 登记口径）
  disabled: boolean;    // 置灰：tx3 + opacity 0.4 + 点击旁路
  action: () => void;   // 行动作（disabled 时旁路不触达）
}

interface DdMenuGroup {
  title: string;        // 组标题（''=不出 menuTitle 行，组分隔线照出）
  items: Array<DdMenuItem>;
}

// ===== 主题（batch-1，audit-modal-3/4 全量重做；原 gap-settings-2 修订 4 收编基础扩容）=====
// 6 主题 × 深/浅 = 12 表，逐变量对齐通用版 frontend/index.html（只读规范，行号为当轮实读）：
//   hmos 浅/深（iss-4：鸿蒙原生 token，值取自 ../model/Theme 常量=baseline 条目，
//   与 resources/base|dark/element/color.json dd_* 同名同值镜像——资源=系统面事实源）
//   mac 浅 i:527-532 · mac 深 i:668-679 · deep 浅 i:536-560 · deep 深 i:681-707 ·
//   neu 浅 i:563-577 · neu 深 i:709-724 · glass 浅 i:579-597 · glass 深 i:721-729 ·
//   win11 浅 i:737-749 · win11 深 i:686-694（深档设置面板覆写 i:746-751）。
// 桌面无规范值的鸿蒙扩展 token（wireText/wireStroke/dim/danger 族/阴影/柔和衍生色等）
// 逐主题登记推导依据；无登记的自造值一律不留。
// 扩容纪律：新增字段（本批 cvs/grad、iss-4 chipLine/chipTx）必须 12 表全填，缺任一表即编译失败。
/** 阴影四元组（batch-3，iss 视觉 token：radius/offsetX/offsetY/color 与 ArkUI ShadowOptions
 * 同形，消费点直传 .shadow(this.T().shXxx)）。 */
interface ShadowSpec {
  radius: number;
  offsetX: number;
  offsetY: number;
  color: string;
}

interface ThemeColors {
  base: string;        // 窗口 chrome 底（--base）
  cvs: string;         // 画布区底（--cvs）。base/cvs 桌面本就是两 token（mac 浅同值 i:527-528，
                       // mac 深分离 #212125/#26262b i:668）——本批拆分，:3909/:3600 消费点换 cvs
  grad: string[];      // 根容器 135° 渐变 4 停靠点：glass 全屏渐变底近似（i:586 浅/i:727 深，
                       // ArkUI linearGradient 单向近似，登记不再立项）；其余主题取 4×cvs 纯色等价
  panelS: string;      // 侧栏半透明
  panelT: string;      // 顶栏毛玻璃底
  tx: string; tx2: string; tx3: string;
  acc: string; accTx: string; purple: string; ok: string; okText: string;
  bd: string;          // 分隔线/弱边框（--bd 色段）
  shsm: string;        // 小阴影色
  shadowMd: string; shadowLg: string;
  card: string;        // 卡片/浮层实底
  onAcc: string;       // 强调底上的前景（桌面 --acc-contrast，缺省 #fff）
  subtle: string;      // 弱填充（tab 条/chip 底）
  line: string;        // 输入框边/卡片边（≈--panel-line）
  lineStrong: string;  // 强边框
  wireStroke: string;  // 线框描边（浅 #9aa4b2 = i:627 强制色；深为鸿蒙扩展同系灰蓝）
  dim: string;         // 弱化点/幽灵（0.18）
  floatBg: string;     // czoom/ctools 悬浮底
  tailBg: string;      // canvas-tail 信息条底（--tail-bg i:53 浅 rgba(255,255,255,.9)/i:63 深
                       // rgba(28,29,34,.94)；deep i:541、glass i:587 有主题级覆写，级联实证见各表）
  modalMask: string;   // 弹层遮罩（batch-3，audit-modal-8：22% 暗化 rgba(20,24,32,.22)+backdropBlur
                       // 近似——原 wireStroke 灰蓝不透明为自造值；桌面遮罩不分主题，10 表同值；
                       // 设置/导出遮罩用 0.24（modal-1 规格另行 +0.02），见 settingsModal 注释
  toastBg: string;     // ok toast 底（i:648 #20252d 固定色，主题无关——audit-modal-12）
  demoBg: string; demoTopBg: string; demoText: string; demoExitBg: string;
  accSoft: string; purpleBorder: string;
  danger: string; dangerSoft: string; dangerBorder: string;
  okSoft: string; okBorder: string;
  trans: string;       // 全透明占位
  wireText: string;    // 线框档文字
  chromeBg: string;        // 画板卡标题栏灰条（非 active；i:212 浅 #f0f1f5）
  chromeBgActive: string;  // active 标题栏（i:213 白底；深档级联详见各表登记）
  chromeAccBorder: string; // active 标题栏边框（i:213 rgba(0,122,255,.45) 固定蓝）
  flowStroke: string;      // 连线专线色 #3f8fff（i:1896/:1855/:1904 主线/箭头/源点同色）——
                           // 不随主题（batch-4，gap-detail-10：两主题同值，字面量登记）
  toastErrBg: string;      // err toast 深红底（i:647 #3d1420，固定色两主题同值——batch-5 gap-detail-13）
  toastErrBorder: string;  // err toast 红边（i:647 #e05252）
  toastErrText: string;    // err toast 字色（i:647 #ffd7d7）
  purpleSoft: string;      // AGENT tag 紫底（batch-5 gap-detail-15；状态栏 busy 态）
  chipLine: string;        // iss-4：chip 族边框 token（pchip/flowrow/compsearch 未聚焦）——桌面硬编码
                           // rgba(0,0,0,0.07) 在深档不可见（iss-4 判负条件），token 化后 12 表逐表照填
  chipTx: string;          // iss-4：pchip 字色 token（桌面 i:245 var(--tx)，深色补丁 i:708 切 var(--tx2)）
  // —— batch-3 视觉 token 逐域应用（按表面拆字段，禁共享几何字段）——
  // 纪律：既有 10 表=该表面当前内联现值（防静默漂移）；HMOS 表=baseline §4/§6 值；
  // 同一字段只允许「现值相同且 HMOS 目标相同」的表面合并，否则拆字段（rTplCard 合并
  // tplCard+ghost、rBtnDialog 合并 发送/澄清回答/口令输入框、rBtnSecondary 合并
  // 重新序列化/＋新建/打开、shDialog 合并 veil+五弹层——均现值相同）。
  // 登记不 token 化（dropped，batch-3）：微控件阴影（modeSeg 选中 :3639、toolBtn 选中
  // :3776、pmain 微影 :5526、时间线卡 :4006、elNode 画布元素阴影 :3244/:3279）——
  // 视觉影响微小/画布数据，触面/收益比不成立；字号阶梯其余 inline fontSize 保持桌面
  // 原值；字重保持既有 500/600 体系（符合 baseline §3 控件默认 500 锚点，登记）。
  rVeil: number;           // veil 卡圆角：桌面 22 → HMOS 24（§4 card）
  rDialog: number;         // 五弹层容器圆角（设置导出口令/输入口令/恢复/确认）：桌面 14 → HMOS 24（§4 dialog；r12 fix-aitab-6 起设置卡退出本档——radius 14 桌面单值显性改回并登记）
  rTplCard: number;        // 模板卡+ghost 新建卡圆角（现值同 12 合并）：桌面 12 → HMOS 24
  rBoardFrame: number;     // 板框圆角（板框/chrome 顶角 topLeft/topRight/demo）：桌面 10 → HMOS 24
  rMenuPanel: number;      // 菜单容器圆角（ctx 菜单×4+最近项目下拉）：桌面 10 → HMOS 20（§4 menu）
  rFloatBar: number;       // ctools/czoom 悬浮条圆角：桌面 12 → HMOS 20（§4 button 档）
  rBtnPrimary: number;     // 一键生成主钮圆角：桌面 9 → HMOS 20（§4 button）
  rBtnDialog: number;      // 弹层钮/口令输入圆角（发送/澄清回答/口令输入框×2，现值同 8 合并）：桌面 8 → HMOS 20
  rBtnSecondary: number;   // 次钮圆角（重新序列化刷新/＋新建/打开，现值同 7 合并）：桌面 7 → HMOS 14（§4 small_button/piece）
  rChipPill: number;       // 芯片胶囊圆角（pchip/行内 chips/设置主题+深浅 chips）：桌面 99 → HMOS 14
                           // （登记：胶囊 99→14 为形态变更，§4 piece 档；pchip 高 30/padding 13 不动）
  rInput: number;          // compsearch 输入框圆角：桌面 7 → HMOS 20（§4 text_field）
  rPmain: number;          // pmain 容器圆角：桌面 12 → HMOS 20
  rIcon: number;           // 顶栏 logo 底圆角：桌面 5 → HMOS 8（§4 icon）。
                           // veil 徽标（现值 8）按「现值相同方可合并」规则不并入本字段——其现值
                           // 已等于 HMOS 目标 8，保持 inline 零漂移（登记，见 veil 消费点注释）
  fDialogTitle: number;    // 弹层标题字号（设置导出口令/输入口令/恢复三处）：桌面 15 → HMOS 20（§3 dialog_tittle）
  fBtnPrimary: number;     // 一键生成字号：桌面 13 → HMOS 16（§3 button 默认档）
  shFloat: ShadowSpec;     // 悬浮条阴影（ctools/czoom）：桌面 {12,0,0,shadowMd} → HMOS sm 40/(0,10)（§6）
  shMenu: ShadowSpec;      // 菜单阴影（ctx 菜单×4+最近项目下拉）：桌面 {12,0,0,shadowMd} → HMOS md 60/(0,10)
  shPop: ShadowSpec;       // 行内编辑面板/行内 Agent 浮层阴影：桌面 {16,0,0,shadowLg} → HMOS md 60/(0,10)
  shDock: ShadowSpec;      // dock 壳阴影：桌面 {16,0,0,shadowLg} → HMOS lg 100/(0,20)
  shDialog: ShadowSpec;    // veil+五弹层阴影（现值同 24 合并）：桌面 {24,0,0,shadowLg} → HMOS lg 100/(0,20)
  shCard: ShadowSpec;      // 模板卡阴影：桌面 {2,0,1,shsm} → HMOS 无阴影（radius 0+透明色表达；
                           // §6 落地建议：普通卡片默认无阴影用 sub_background 分层——登记）
  modalMaskStrong: string; // settings/export 强遮罩：桌面 rgba(20,24,32,0.24) 不分主题 →
                           // HMOS #33000000/#66000000（与 modalMask 同值；登记：+0.02 强档为
                           // 桌面 modal-1 规格，鸿蒙蒙层阶梯 20/40/60/80% 无对应强档，收编单档）
  pressFill: string;       // batch-4 iss-5：中性面按压底（subtle 提一档，B 底色叠加式的中性档）——
                           // 既有 10 表=各自 subtle 的 alpha 提档（登记推导）；HMOS=20% 主色
                           // （subtle 10% 提一档；浅档与蒙层薄同值、深档与分隔线同值——值复用登记）
                           // batch-4 登记：hover 鼠标形态仍归 2in1 真机清单（触屏无 hover 既有登记
                           // 不回填）；丢弃钮（dangerSoft 底）无 danger 按压 token 不铺开（同发
                           // 送/行内 Agent ↗ 未列明面）；绿胶囊/时间线卡/toast 非钮不加。
                           // 【验收登记】按压帧注入限制：devecocli ui layout/click/screenshot 瞬时
                           // click 拍不到 pressed 帧（r7 审计实证）——r8 复核：uiInput longClick
                           // 被手势抢占（长按 pchip 弹出画布菜单而非按压态）、0.26s snapshot 连拍
                           // 未获决定性按压帧；机制代码在场（stateStyles 29 处+HMOS_PRESS_SCALE
                           // +dd_pressed 资源），视觉帧不可达归因注入器能力，按 batch-4 instructions
                           // ③降级为「stateStyles 在场（静态）+ 行为回归」验收，非应用缺陷判负
}

// 设置外观区主题 chip 文案（batch-1，audit-modal-4，对齐 i:1107-1111 逐字）
interface ThemeChipDef {
  id: string;
  label: string;
}
const THEME_CHIPS: ThemeChipDef[] = [
  { id: 'hmos', label: 'HarmonyOS · 鸿蒙原生' },   // iss-4 前插：鸿蒙原生主题（默认选中）
  { id: 'win11', label: 'Win11 · Fluent' },
  { id: 'mac', label: 'Mac · macOS Light' },
  { id: 'deep', label: 'Deep · 深色专业' },
  { id: 'neu', label: 'Neu · 软拟物' },
  { id: 'glass', label: 'Glass · 玻璃' }
];

// ---- mac 浅（i:527-532；浅色档原已对齐，防回归——只增 cvs/grad 并修正 toastBg）----
const THEME_MAC_L: ThemeColors = {
  tailBg: 'rgba(255,255,255,0.9)',   // i:53 --tail-bg 浅
  base: '#f2f3f7',
  cvs: '#f2f3f7',   // i:527-528 mac 浅 base/cvs 同值
  grad: ['#f2f3f7', '#f2f3f7', '#f2f3f7', '#f2f3f7'],
  panelS: 'rgba(255,255,255,0.92)',   // i:122/:282 .left/.right
  panelT: 'rgba(255,255,255,0.85)',   // i:67 .topbar
  tx: '#1c1c1e', tx2: '#636366', tx3: '#686873',
  acc: '#007aff', accTx: '#0066d6', purple: '#9d4edd', ok: '#28a745',
  okText: '#1d6b41',   // 状态栏 READY 字（i:374 tag.h 固定色）
  bd: 'rgba(0,0,0,0.08)', shsm: 'rgba(0,0,0,0.05)',
  shadowMd: 'rgba(0,0,0,0.12)', shadowLg: 'rgba(0,0,0,0.18)',
  card: '#ffffff', onAcc: '#ffffff',   // i:174 compcell 白
  subtle: 'rgba(0,0,0,0.05)', line: 'rgba(0,0,0,0.12)', lineStrong: 'rgba(0,0,0,0.14)',
  wireStroke: '#9aa4b2', dim: 'rgba(0,0,0,0.18)',   // 线框描边对齐 i:627 强制色（batch-3，gap-detail-6）
  floatBg: 'rgba(255,255,255,0.9)',   // i:196 ctools
  modalMask: 'rgba(20,24,32,0.22)',   // 桌面遮罩不分主题（登记同值）
  toastBg: '#20252d',   // i:648 固定色（原 rgba(28,28,30,.92) 偏移，audit-modal-12 修正）
  demoBg: '#101013', demoTopBg: 'rgba(16,16,19,0.72)', demoText: '#9a9aa2', demoExitBg: 'rgba(255,255,255,0.16)',
  accSoft: 'rgba(0,102,214,0.08)', purpleBorder: 'rgba(157,78,221,0.35)',
  danger: '#e5484d', dangerSoft: 'rgba(229,72,77,0.08)', dangerBorder: 'rgba(229,72,77,0.30)',
  okSoft: 'rgba(40,167,69,0.10)', okBorder: 'rgba(40,167,69,0.35)',
  trans: 'rgba(0,0,0,0)',
  wireText: '#52606d',   // 线框文字对齐 i:628 强制色（batch-3，gap-detail-6）
  chromeBg: '#f0f1f5', chromeBgActive: '#ffffff', chromeAccBorder: 'rgba(0,122,255,0.45)',   // i:212/213
  flowStroke: '#3f8fff',   // 连线专线色，不随主题（i:1896）
  toastErrBg: '#3d1420', toastErrBorder: '#e05252', toastErrText: '#ffd7d7',   // i:647 固定色
  purpleSoft: 'rgba(157,78,221,0.12)',
  // iss-4 chip token：浅档=桌面原值（i:164/:183/:245 边 rgba(0,0,0,.07)、字 var(--tx)）
  chipLine: 'rgba(0,0,0,0.07)', chipTx: '#1c1c1e',
  pressFill: 'rgba(0,0,0,0.08)',        // subtle 0.05 提一档（batch-4 iss-5）
  // batch-3 表面字段（既有主题=当前内联现值，防漂移；HMOS 目标见接口登记）
  rVeil: 22, rDialog: 14, rTplCard: 12, rBoardFrame: 10, rMenuPanel: 10, rFloatBar: 12,
  rBtnPrimary: 9, rBtnDialog: 8, rBtnSecondary: 7, rChipPill: 99, rInput: 7, rPmain: 12,
  rIcon: 5, fDialogTitle: 15, fBtnPrimary: 13,
  shFloat: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.12)' },   // =shadowMd 现值
  shMenu: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.12)' },
  shPop: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.18)' },     // =shadowLg 现值
  shDock: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.18)' },
  shDialog: { radius: 24, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.18)' },
  shCard: { radius: 2, offsetX: 0, offsetY: 1, color: 'rgba(0,0,0,0.05)' },     // =shsm 现值
  modalMaskStrong: 'rgba(20,24,32,0.24)'   // 桌面 modal-1 规格不分主题（原值）
};

// ---- mac 深（i:668-679 逐变量对齐；audit-modal-3 修正：旧表自造值全部替换）----
const THEME_MAC_D: ThemeColors = {
  tailBg: 'rgba(28,29,34,0.94)',   // i:63 --tail-bg 深
  base: '#212125',   // i:668 --base
  cvs: '#26262b',    // i:668 --cvs（与 base 分离；验收采样点）
  grad: ['#26262b', '#26262b', '#26262b', '#26262b'],
  panelS: 'rgba(30,30,34,0.94)',   // i:677 侧栏 rgba(30,30,34,.94)——panel #2a2a2e 的实侧栏
                                   // 换算基准（登记：桌面侧栏规则优先于 --panel 字面值）
  panelT: 'rgba(30,30,34,0.94)',   // i:677 .topbar 同一条规则
  tx: '#e8e8ec', tx2: '#9a9aa2', tx3: '#8f8f97',   // i:671-672
  acc: '#0a84ff', accTx: '#2f97ff', purple: '#9d4edd', ok: '#28a745',
  //   accTx = i:675 --acc-tx:#2f97ff（旧值 #409cff 误取 --acc-h）；purple/ok 深 mac 未覆写
  //   →继承浅档 i:527-532（旧自造值 #b57bff/#30d158 替换）
  okText: '#4ade80',   // 深档状态栏 READY 字（暗底可读绿，鸿蒙扩展登记；桌面 tag.h 无深色覆写）
  bd: '#34343a',   // i:675 --bd 实色
  shsm: 'rgba(0,0,0,0.35)',
  shadowMd: 'rgba(0,0,0,0.45)', shadowLg: 'rgba(0,0,0,0.60)',   // 暗档阴影加深（鸿蒙扩展，全深档共用）
  card: '#28282d',   // i:676 compcell/tpl-card 实底
  onAcc: '#ffffff',   // mac 无 --acc-contrast → #fff 兜底（i:471）
  subtle: 'rgba(255,255,255,0.06)',   // 深档弱填充（通用深色补丁 0.06-0.07 区间，登记）
  line: '#3a3a40',       // i:669 --panel-line
  lineStrong: '#3a3a3f', // i:676 compcell 边
  wireStroke: '#8b96a5', dim: 'rgba(255,255,255,0.24)',   // 深色档鸿蒙扩展：与浅色 #9aa4b2 同系灰蓝
                                                          // （通用版 wireframe 强制色 i:627-628 仅浅色档，深色无规范值——登记取舍）
  floatBg: 'rgba(28,29,34,0.92)',   // i:710 通用深色补丁 .ctools/.czoom（mac 深无主题级覆写）
  modalMask: 'rgba(20,24,32,0.22)',   // 桌面遮罩不分主题（登记同值）
  toastBg: '#20252d',   // i:648 固定色
  demoBg: '#101013', demoTopBg: 'rgba(16,16,19,0.72)', demoText: '#9a9aa2', demoExitBg: 'rgba(255,255,255,0.16)',
  accSoft: 'rgba(47,151,255,0.16)',   // accTx #2f97ff 同源 tint，暗档 alpha 0.16
  purpleBorder: 'rgba(157,78,221,0.40)',   // 继承 purple 同源 tint，暗档 alpha 0.40
  danger: '#ff6369', dangerSoft: 'rgba(255,99,105,0.14)', dangerBorder: 'rgba(255,99,105,0.35)',   // 鸿蒙扩展（桌面 danger 固定不随主题）
  okSoft: 'rgba(40,167,69,0.14)', okBorder: 'rgba(40,167,69,0.35)',   // 继承 ok 同源 tint，暗档 alpha 0.14
  trans: 'rgba(0,0,0,0)',
  wireText: '#aab4c0',   // 深色档鸿蒙扩展：与浅色 #52606d 同系灰蓝、暗底可读（同上登记）
  chromeBg: '#28282d',        // i:679 frame-chrome
  chromeBgActive: '#28282d',  // mac 深无 active 独立值：i:679 特异性(0,3,1)压过 active i:213 (0,3,0)
                              // （级联实证登记）——active 区分由画板 body 2px acc 边承担
  chromeAccBorder: '#3a3a3f', // 同上：active 边框被 i:679 border-color 覆压
  flowStroke: '#3f8fff',
  toastErrBg: '#3d1420', toastErrBorder: '#e05252', toastErrText: '#ffd7d7',
  purpleSoft: 'rgba(157,78,221,0.20)',
  // iss-4 chip token：深档 mac 实色边 #3a3a3f（i:676/:678——#3a3a3f 系）；字=var(--tx2)（通用深色补丁 i:708）
  chipLine: '#3a3a3f', chipTx: '#9a9aa2',
  pressFill: 'rgba(255,255,255,0.10)',  // subtle 0.06 提一档
  // batch-3 表面字段（同 mac 浅口径，阴影色=本表深档现值）
  rVeil: 22, rDialog: 14, rTplCard: 12, rBoardFrame: 10, rMenuPanel: 10, rFloatBar: 12,
  rBtnPrimary: 9, rBtnDialog: 8, rBtnSecondary: 7, rChipPill: 99, rInput: 7, rPmain: 12,
  rIcon: 5, fDialogTitle: 15, fBtnPrimary: 13,
  shFloat: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.45)' },
  shMenu: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.45)' },
  shPop: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shDock: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shDialog: { radius: 24, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shCard: { radius: 2, offsetX: 0, offsetY: 1, color: 'rgba(0,0,0,0.35)' },
  modalMaskStrong: 'rgba(20,24,32,0.24)'
};

// ---- win11 浅（i:737-749 Fluent Mica）----
const THEME_WIN11_L: ThemeColors = {
  tailBg: 'rgba(255,255,255,0.9)',   // i:53 --tail-bg 浅（win11 无覆写）
  base: '#F3F3F3',   // i:739
  cvs: '#F6F7F9',    // i:739 --cvs 与 base 分离
  grad: ['#F6F7F9', '#F6F7F9', '#F6F7F9', '#F6F7F9'],
  panelS: 'rgba(243,243,243,0.96)',   // i:744 .left/.right
  panelT: 'rgba(243,243,243,0.96)',   // i:744 .topbar
  tx: '#1B1B1B', tx2: '#5C5C5C', tx3: '#8A8A8A',   // i:740
  acc: '#0067C0', accTx: '#0067C0', purple: '#8B5CF6', ok: '#0F7B0F',   // i:740-742
  okText: '#1d6b41',   // i:374 tag.h 固定色（win11 ok 本身深绿，文字档沿用桌面固定值）
  bd: 'rgba(0,0,0,0.07)',   // i:742 --bd
  shsm: 'rgba(0,0,0,0.05)', shadowMd: 'rgba(0,0,0,0.12)', shadowLg: 'rgba(0,0,0,0.18)',
  //   阴影无 win11 规范值 → 浅档共用 mac 基准（鸿蒙扩展登记）
  card: '#ffffff',   // i:174 compcell 白（win11 无覆写）
  onAcc: '#ffffff',  // win11 浅无 --acc-contrast → #fff 兜底
  subtle: 'rgba(0,0,0,0.05)',
  line: 'rgba(0,0,0,0.08)',       // i:737 --panel-line
  lineStrong: 'rgba(0,0,0,0.14)', // 强边鸿蒙扩展（浅档统一）
  wireStroke: '#9aa4b2', dim: 'rgba(0,0,0,0.18)',
  floatBg: 'rgba(251,251,251,0.92)',   // i:749 mac-glass/ctools/czoom
  modalMask: 'rgba(20,24,32,0.22)',   // 桌面遮罩不分主题（登记同值）
  toastBg: '#20252d',
  demoBg: '#101013', demoTopBg: 'rgba(16,16,19,0.72)', demoText: '#9a9aa2', demoExitBg: 'rgba(255,255,255,0.16)',
  accSoft: 'rgba(0,103,192,0.08)', purpleBorder: 'rgba(139,92,246,0.35)',
  danger: '#e5484d', dangerSoft: 'rgba(229,72,77,0.08)', dangerBorder: 'rgba(229,72,77,0.30)',
  okSoft: 'rgba(15,123,15,0.10)', okBorder: 'rgba(15,123,15,0.35)',   // ok 同源 tint
  trans: 'rgba(0,0,0,0)',
  wireText: '#52606d',
  chromeBg: '#FBFBFB',        // i:748 frame-chrome
  chromeBgActive: '#ffffff',  // i:213（win11 浅 chrome 规则(0,2,1)不敌 active (0,3,0)）
  chromeAccBorder: 'rgba(0,122,255,0.45)',   // i:213 边框胜 i:748（级联实证）
  flowStroke: '#3f8fff',
  toastErrBg: '#3d1420', toastErrBorder: '#e05252', toastErrText: '#ffd7d7',
  purpleSoft: 'rgba(139,92,246,0.12)',
  // iss-4 chip token：浅档=桌面原值 rgba(0,0,0,0.07)/var(--tx)（同 mac 浅口径）
  chipLine: 'rgba(0,0,0,0.07)', chipTx: '#1B1B1B',
  pressFill: 'rgba(0,0,0,0.08)',        // subtle 0.05 提一档
  // batch-3 表面字段（同 mac 浅口径）
  rVeil: 22, rDialog: 14, rTplCard: 12, rBoardFrame: 10, rMenuPanel: 10, rFloatBar: 12,
  rBtnPrimary: 9, rBtnDialog: 8, rBtnSecondary: 7, rChipPill: 99, rInput: 7, rPmain: 12,
  rIcon: 5, fDialogTitle: 15, fBtnPrimary: 13,
  shFloat: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.12)' },
  shMenu: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.12)' },
  shPop: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.18)' },
  shDock: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.18)' },
  shDialog: { radius: 24, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.18)' },
  shCard: { radius: 2, offsetX: 0, offsetY: 1, color: 'rgba(0,0,0,0.05)' },
  modalMaskStrong: 'rgba(20,24,32,0.24)'
};

// ---- win11 深（i:686-694 + i:747 设置面板覆写）----
const THEME_WIN11_D: ThemeColors = {
  tailBg: 'rgba(28,29,34,0.94)',   // i:63 --tail-bg 深（win11 无覆写）
  base: '#202020',   // i:689
  cvs: '#1C1C1C',    // i:689
  grad: ['#1C1C1C', '#1C1C1C', '#1C1C1C', '#1C1C1C'],
  panelS: 'rgba(32,32,32,0.96)',   // i:688 .left/.right
  panelT: 'rgba(32,32,32,0.96)',   // i:688 .topbar
  tx: '#FFFFFF', tx2: '#C8C8C8', tx3: '#9A9A9A',   // i:690
  acc: '#4CC2FF', accTx: '#4CC2FF', purple: '#8B5CF6', ok: '#6CCB5F',
  //   acc/accTx = i:690；purple 深 win11 未覆写→继承 i:743；ok = i:691
  okText: '#6CCB5F',   // =ok（Fluent 深档绿本身亮绿，文字直用）
  bd: 'rgba(255,255,255,0.07)',   // i:692 --bd
  shsm: 'rgba(0,0,0,0.35)', shadowMd: 'rgba(0,0,0,0.45)', shadowLg: 'rgba(0,0,0,0.60)',
  card: '#2B2B2B',   // i:693 compcell
  onAcc: '#003A66',  // i:691 --acc-contrast
  subtle: 'rgba(255,255,255,0.06)',
  line: 'rgba(255,255,255,0.08)',       // i:687/:747 --panel-line
  lineStrong: 'rgba(255,255,255,0.14)', // 强边鸿蒙扩展（深档统一）
  wireStroke: '#8b96a5', dim: 'rgba(255,255,255,0.24)',
  floatBg: 'rgba(43,43,43,0.94)',   // i:694 mac-glass/ctools/czoom
  modalMask: 'rgba(20,24,32,0.22)',   // 桌面遮罩不分主题（登记同值）
  toastBg: '#20252d',
  demoBg: '#101013', demoTopBg: 'rgba(16,16,19,0.72)', demoText: '#9a9aa2', demoExitBg: 'rgba(255,255,255,0.16)',
  accSoft: 'rgba(76,194,255,0.16)', purpleBorder: 'rgba(139,92,246,0.40)',
  danger: '#ff6369', dangerSoft: 'rgba(255,99,105,0.14)', dangerBorder: 'rgba(255,99,105,0.35)',
  okSoft: 'rgba(108,203,95,0.14)', okBorder: 'rgba(108,203,95,0.35)',
  trans: 'rgba(0,0,0,0)',
  wireText: '#aab4c0',
  chromeBg: '#2B2B2B',        // i:667 frame-chrome
  chromeBgActive: '#2B2B2B',  // i:667 (0,3,1) 压过 active i:213（级联实证，同 mac 深登记）
  chromeAccBorder: 'rgba(255,255,255,0.08)',   // i:667 border-color 覆压 active 边
  flowStroke: '#3f8fff',
  toastErrBg: '#3d1420', toastErrBorder: '#e05252', toastErrText: '#ffd7d7',
  purpleSoft: 'rgba(139,92,246,0.20)',
  // iss-4 chip token：深档=通用深色补丁 rgba(255,255,255,0.08)（i:708；win11 深 flowrow 边 i:664 同值）；字=var(--tx2)（i:708）
  chipLine: 'rgba(255,255,255,0.08)', chipTx: '#C8C8C8',
  pressFill: 'rgba(255,255,255,0.10)',  // subtle 0.06 提一档
  // batch-3 表面字段（同 mac 浅口径，阴影色=本表深档现值）
  rVeil: 22, rDialog: 14, rTplCard: 12, rBoardFrame: 10, rMenuPanel: 10, rFloatBar: 12,
  rBtnPrimary: 9, rBtnDialog: 8, rBtnSecondary: 7, rChipPill: 99, rInput: 7, rPmain: 12,
  rIcon: 5, fDialogTitle: 15, fBtnPrimary: 13,
  shFloat: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.45)' },
  shMenu: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.45)' },
  shPop: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shDock: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shDialog: { radius: 24, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shCard: { radius: 2, offsetX: 0, offsetY: 1, color: 'rgba(0,0,0,0.35)' },
  modalMaskStrong: 'rgba(20,24,32,0.24)'
};

// ---- deep 浅（i:536-560；deep 本体即暗色 chrome，柔和衍生/线框扩展取深档值——登记）----
const THEME_DEEP_L: ThemeColors = {
  tailBg: 'rgba(23,25,30,0.94)',   // i:541 canvas-tail 主题覆写（不分 mode）
  base: '#17191e',   // i:537
  cvs: '#121317',    // i:537
  grad: ['#121317', '#121317', '#121317', '#121317'],
  panelS: 'rgba(23,25,30,0.94)',   // i:555 .left/.right
  panelT: 'rgba(23,25,30,0.94)',   // i:555 .topbar
  tx: '#e4e7ec', tx2: '#9aa1ab', tx3: '#878f9b',   // i:538
  acc: '#4a6bfb', accTx: '#6883fc', purple: '#8b5cf6', ok: '#34c07c',   // i:539-540
  okText: '#34c07c',   // deep 全暗 chrome，READY 字直用 ok（亮绿暗底可读）——登记
  bd: '#262a31',   // i:541 --bd
  shsm: 'rgba(0,0,0,0.35)', shadowMd: 'rgba(0,0,0,0.45)', shadowLg: 'rgba(0,0,0,0.60)',
  //   暗色 chrome 上的阴影取暗档值（鸿蒙扩展登记）
  card: '#1f2228',   // i:558 compcell
  onAcc: '#ffffff',  // deep 浅无 --acc-contrast → #fff 兜底
  subtle: 'rgba(255,255,255,0.06)',
  line: '#2c313a',     // i:536 --panel-line（亦 i:558 compcell 边）
  lineStrong: '#2c313a',
  wireStroke: '#8b96a5', dim: 'rgba(255,255,255,0.24)',
  //   暗底 chrome → 线框/dim 取深档扩展值（同 THEME_MAC_D 登记）
  floatBg: 'rgba(31,34,40,0.95)',   // i:556 mac-glass/ctools/czoom/empty-card
  modalMask: 'rgba(20,24,32,0.22)',   // 桌面遮罩不分主题（登记同值）
  toastBg: '#20252d',
  demoBg: '#101013', demoTopBg: 'rgba(16,16,19,0.72)', demoText: '#9a9aa2', demoExitBg: 'rgba(255,255,255,0.16)',
  accSoft: 'rgba(104,131,252,0.16)', purpleBorder: 'rgba(139,92,246,0.40)',
  //   暗色 chrome → 柔和衍生色取暗档 alpha（登记，下同）
  danger: '#ff6369', dangerSoft: 'rgba(255,99,105,0.14)', dangerBorder: 'rgba(255,99,105,0.35)',
  okSoft: 'rgba(52,192,124,0.14)', okBorder: 'rgba(52,192,124,0.35)',
  trans: 'rgba(0,0,0,0)',
  wireText: '#aab4c0',
  chromeBg: '#1f2228',        // i:557 frame-chrome
  chromeBgActive: '#24272e',  // i:544 active（特异性(0,4,1)胜 i:557）
  chromeAccBorder: 'rgba(0,122,255,0.45)',   // i:213 边框胜 i:557（级联实证）
  flowStroke: '#3f8fff',
  toastErrBg: '#3d1420', toastErrBorder: '#e05252', toastErrText: '#ffd7d7',
  purpleSoft: 'rgba(139,92,246,0.20)',
  // iss-4 chip token：浅档=指令固定 rgba(0,0,0,0.07)（deep 浅桌面实值 #2c313a i:546/:551/:555
  // 未取——维持现移植行为零变化，登记简化）；字=var(--tx)（i:245 原值，i:555 无 color 覆写）
  chipLine: 'rgba(0,0,0,0.07)', chipTx: '#e4e7ec',
  pressFill: 'rgba(255,255,255,0.10)',  // subtle 0.06 提一档（deep 暗底 chrome）
  // batch-3 表面字段（同 mac 浅口径，阴影色=本表现值——deep 暗色 chrome 取暗档阴影）
  rVeil: 22, rDialog: 14, rTplCard: 12, rBoardFrame: 10, rMenuPanel: 10, rFloatBar: 12,
  rBtnPrimary: 9, rBtnDialog: 8, rBtnSecondary: 7, rChipPill: 99, rInput: 7, rPmain: 12,
  rIcon: 5, fDialogTitle: 15, fBtnPrimary: 13,
  shFloat: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.45)' },
  shMenu: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.45)' },
  shPop: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shDock: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shDialog: { radius: 24, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shCard: { radius: 2, offsetX: 0, offsetY: 1, color: 'rgba(0,0,0,0.35)' },
  modalMaskStrong: 'rgba(20,24,32,0.24)'
};

// ---- deep 深（i:681-707）----
const THEME_DEEP_D: ThemeColors = {
  tailBg: 'rgba(23,25,30,0.94)',   // i:541 同上（深档仍由该规则兜住）
  base: '#16171c',   // i:682
  cvs: '#111217',    // i:682
  grad: ['#111217', '#111217', '#111217', '#111217'],
  panelS: 'rgba(22,23,28,0.96)',   // i:702 .left/.right
  panelT: 'rgba(22,23,28,0.96)',   // i:702 .topbar
  tx: '#e6e8ef', tx2: '#98a0ad', tx3: '#838b9a',   // i:683
  acc: '#6a86ff', accTx: '#6a86ff', purple: '#8b5cf6', ok: '#34c07c',
  //   acc/accTx = i:684；purple/ok 未覆写→继承浅档 i:539-540
  okText: '#34c07c',
  bd: '#262a33',   // i:684 --bd
  shsm: 'rgba(0,0,0,0.35)', shadowMd: 'rgba(0,0,0,0.45)', shadowLg: 'rgba(0,0,0,0.60)',
  card: '#1e2027',   // i:703 compcell
  onAcc: '#101532',  // i:685 --acc-contrast
  subtle: 'rgba(255,255,255,0.06)',
  line: '#2a2e38',     // i:703 compcell 边（= i:747 --panel-line）
  lineStrong: '#2a2e38',
  wireStroke: '#8b96a5', dim: 'rgba(255,255,255,0.24)',
  floatBg: 'rgba(28,29,34,0.92)',
  //   i:710 通用深色补丁兜底：deep 深无主题级 ctools 覆写，与 i:556 同特异性(0,2,1)、
  //   后者在文件更后 → 级联取 i:710（实证登记，下同）
  modalMask: 'rgba(20,24,32,0.22)',   // 桌面遮罩不分主题（登记同值）
  toastBg: '#20252d',
  demoBg: '#101013', demoTopBg: 'rgba(16,16,19,0.72)', demoText: '#9a9aa2', demoExitBg: 'rgba(255,255,255,0.16)',
  accSoft: 'rgba(106,134,255,0.16)', purpleBorder: 'rgba(139,92,246,0.40)',
  danger: '#ff6369', dangerSoft: 'rgba(255,99,105,0.14)', dangerBorder: 'rgba(255,99,105,0.35)',
  okSoft: 'rgba(52,192,124,0.14)', okBorder: 'rgba(52,192,124,0.35)',
  trans: 'rgba(0,0,0,0)',
  wireText: '#aab4c0',
  chromeBg: '#1e2027',        // i:707 frame-chrome
  chromeBgActive: '#24272e',  // i:544 active（0,4,1)仍胜深档 (0,3,1)
  chromeAccBorder: '#2a2e38', // i:707 border-color 覆压 active 边（级联实证）
  flowStroke: '#3f8fff',
  toastErrBg: '#3d1420', toastErrBorder: '#e05252', toastErrText: '#ffd7d7',
  purpleSoft: 'rgba(139,92,246,0.20)',
  // iss-4 chip token：深档实色边 #2a2e38（i:688/:689——#3a3a3f 系同族逐表照填）；字=var(--tx2)（i:708）
  chipLine: '#2a2e38', chipTx: '#98a0ad',
  pressFill: 'rgba(255,255,255,0.10)',  // subtle 0.06 提一档
  // batch-3 表面字段（同 mac 浅口径，阴影色=本表现值）
  rVeil: 22, rDialog: 14, rTplCard: 12, rBoardFrame: 10, rMenuPanel: 10, rFloatBar: 12,
  rBtnPrimary: 9, rBtnDialog: 8, rBtnSecondary: 7, rChipPill: 99, rInput: 7, rPmain: 12,
  rIcon: 5, fDialogTitle: 15, fBtnPrimary: 13,
  shFloat: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.45)' },
  shMenu: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.45)' },
  shPop: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shDock: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shDialog: { radius: 24, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shCard: { radius: 2, offsetX: 0, offsetY: 1, color: 'rgba(0,0,0,0.35)' },
  modalMaskStrong: 'rgba(20,24,32,0.24)'
};

// ---- neu 浅（i:563-577 软拟物；双向阴影以单向软阴影近似——登记不再立项）----
const THEME_NEU_L: ThemeColors = {
  tailBg: 'rgba(255,255,255,0.9)',   // i:53 --tail-bg 浅（neu 无覆写）
  base: '#e0e5ec',   // i:565
  cvs: '#e0e5ec',    // i:565
  grad: ['#e0e5ec', '#e0e5ec', '#e0e5ec', '#e0e5ec'],
  panelS: '#e0e5ec',   // i:563 .left/.right 实色（含 box-shadow 白高光，ArkUI 近似略）
  panelT: '#e0e5ec',   // i:563 .topbar
  tx: '#3a4a5c', tx2: '#536073', tx3: '#506078',   // i:566
  acc: '#5b5bf6', accTx: '#4848f5', purple: '#8b5cf6', ok: '#1e9e63',   // i:566-568
  okText: '#1d6b41',   // i:374 tag.h 固定色
  bd: 'rgba(0,0,0,0)',   // i:569 --bd:0 无边框（拟物无界设计）→ 透明近似，登记
  shsm: 'rgba(163,177,198,0.35)',
  shadowMd: 'rgba(163,177,198,0.55)', shadowLg: 'rgba(163,177,198,0.55)',
  //   i:567 双向阴影（-8px 白高光/8px 暗影）以暗影单向软阴影近似——ArkUI 单 shadow
  //   不支持双向，亮影侧不可表达，登记取舍
  card: '#ffffff',   // i:174 compcell 白（neu 无底色覆写：白卡+拟物阴影）
  onAcc: '#ffffff',
  subtle: 'rgba(0,0,0,0.05)',
  line: 'rgba(163,177,198,0.4)',        // i:564 --panel-line
  lineStrong: 'rgba(163,177,198,0.55)', // 衍生：panel-line 提段（无边框主题仍需可辨强边，登记）
  wireStroke: '#9aa4b2', dim: 'rgba(0,0,0,0.18)',
  floatBg: '#e0e5ec',   // i:568 ctools/promptbar 实色
  modalMask: 'rgba(20,24,32,0.22)',   // 桌面遮罩不分主题（登记同值）
  toastBg: '#20252d',
  demoBg: '#101013', demoTopBg: 'rgba(16,16,19,0.72)', demoText: '#9a9aa2', demoExitBg: 'rgba(255,255,255,0.16)',
  accSoft: 'rgba(72,72,245,0.08)', purpleBorder: 'rgba(139,92,246,0.35)',
  danger: '#e5484d', dangerSoft: 'rgba(229,72,77,0.08)', dangerBorder: 'rgba(229,72,77,0.30)',
  okSoft: 'rgba(30,158,99,0.10)', okBorder: 'rgba(30,158,99,0.35)',
  trans: 'rgba(0,0,0,0)',
  wireText: '#52606d',
  chromeBg: '#f0f1f5',        // i:212 基准（neu 无 frame-chrome 覆写）
  chromeBgActive: '#ffffff',  // i:213
  chromeAccBorder: 'rgba(0,122,255,0.45)',
  flowStroke: '#3f8fff',
  toastErrBg: '#3d1420', toastErrBorder: '#e05252', toastErrText: '#ffd7d7',
  purpleSoft: 'rgba(139,92,246,0.12)',
  // iss-4 chip token：浅档=指令固定 rgba(0,0,0,0.07)（neu 浅 flowrow 桌面 border:none i:569
  // 未取——维持现移植行为零变化，登记简化）；字=var(--tx)（i:245 原值）
  chipLine: 'rgba(0,0,0,0.07)', chipTx: '#3a4a5c',
  pressFill: 'rgba(0,0,0,0.08)',        // subtle 0.05 提一档（拟物弱填充同档）
  // batch-3 表面字段（同 mac 浅口径，阴影色=本表现值——neu 拟物软阴影族）
  rVeil: 22, rDialog: 14, rTplCard: 12, rBoardFrame: 10, rMenuPanel: 10, rFloatBar: 12,
  rBtnPrimary: 9, rBtnDialog: 8, rBtnSecondary: 7, rChipPill: 99, rInput: 7, rPmain: 12,
  rIcon: 5, fDialogTitle: 15, fBtnPrimary: 13,
  shFloat: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(163,177,198,0.55)' },
  shMenu: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(163,177,198,0.55)' },
  shPop: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(163,177,198,0.55)' },
  shDock: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(163,177,198,0.55)' },
  shDialog: { radius: 24, offsetX: 0, offsetY: 0, color: 'rgba(163,177,198,0.55)' },
  shCard: { radius: 2, offsetX: 0, offsetY: 1, color: 'rgba(163,177,198,0.35)' },
  modalMaskStrong: 'rgba(20,24,32,0.24)'
};

// ---- neu 深（i:709-724 深色软拟物，阴影反转）----
const THEME_NEU_D: ThemeColors = {
  tailBg: 'rgba(28,29,34,0.94)',   // i:63 --tail-bg 深（neu 无覆写）
  base: '#262932',   // i:711
  cvs: '#262932',    // i:711
  grad: ['#262932', '#262932', '#262932', '#262932'],
  panelS: '#262932',   // i:713 实色
  panelT: '#262932',   // i:713
  tx: '#e6e9f0', tx2: '#a8aeba', tx3: '#8d939f',   // i:712
  acc: '#6d8dff', accTx: '#6d8dff', purple: '#8b5cf6', ok: '#1e9e63',
  //   acc/accTx = i:713；purple/ok 未覆写→继承浅档
  okText: '#4bb182',   // 衍生：ok #1e9e63 提亮 ~20% 白混（暗底可读），登记
  bd: 'rgba(0,0,0,0)',   // --bd:0 继承浅档；neu 深块亦全 border:none（i:715）
  shsm: 'rgba(0,0,0,0.35)',
  shadowMd: 'rgba(0,0,0,0.55)', shadowLg: 'rgba(0,0,0,0.60)',
  //   i:715 暗拟物阴影（白 0.05/黑 0.55-0.6）单向近似，登记
  card: '#262932',   // i:715 compcell
  onAcc: '#131a3a',  // i:713 --acc-contrast
  subtle: 'rgba(255,255,255,0.06)',
  line: 'rgba(255,255,255,0.09)',       // i:747 --panel-line
  lineStrong: 'rgba(255,255,255,0.14)', // 衍生提段
  wireStroke: '#8b96a5', dim: 'rgba(255,255,255,0.24)',
  floatBg: '#262932',   // i:717 ctools/czoom 实色（(0,3,1) 主题级胜 i:710）
  modalMask: 'rgba(20,24,32,0.22)',   // 桌面遮罩不分主题（登记同值）
  toastBg: '#20252d',
  demoBg: '#101013', demoTopBg: 'rgba(16,16,19,0.72)', demoText: '#9a9aa2', demoExitBg: 'rgba(255,255,255,0.16)',
  accSoft: 'rgba(109,141,255,0.16)', purpleBorder: 'rgba(139,92,246,0.40)',
  danger: '#ff6369', dangerSoft: 'rgba(255,99,105,0.14)', dangerBorder: 'rgba(255,99,105,0.35)',
  okSoft: 'rgba(30,158,99,0.14)', okBorder: 'rgba(30,158,99,0.35)',
  trans: 'rgba(0,0,0,0)',
  wireText: '#aab4c0',
  chromeBg: '#262932',        // i:715 frame-chrome
  chromeBgActive: '#262932',  // i:715 (0,3,1) 压过 active（级联实证）
  chromeAccBorder: 'rgba(0,0,0,0)',   // i:715 border:none → 透明边近似
  flowStroke: '#3f8fff',
  toastErrBg: '#3d1420', toastErrBorder: '#e05252', toastErrText: '#ffd7d7',
  purpleSoft: 'rgba(139,92,246,0.20)',
  // iss-4 chip token：深档拟物无界 border:none/transparent（i:699/:705）→ 透明近似（同 bd 口径登记）；
  // 字=#b6bcc8（i:705 neu 深显式覆写，非通用补丁 var(--tx2)）
  chipLine: 'rgba(0,0,0,0)', chipTx: '#b6bcc8',
  pressFill: 'rgba(255,255,255,0.10)',  // subtle 0.06 提一档
  // batch-3 表面字段（同 mac 浅口径，阴影色=本表现值——neu 深拟物阴影反转族）
  rVeil: 22, rDialog: 14, rTplCard: 12, rBoardFrame: 10, rMenuPanel: 10, rFloatBar: 12,
  rBtnPrimary: 9, rBtnDialog: 8, rBtnSecondary: 7, rChipPill: 99, rInput: 7, rPmain: 12,
  rIcon: 5, fDialogTitle: 15, fBtnPrimary: 13,
  shFloat: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.55)' },
  shMenu: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.55)' },
  shPop: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shDock: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shDialog: { radius: 24, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shCard: { radius: 2, offsetX: 0, offsetY: 1, color: 'rgba(0,0,0,0.35)' },
  modalMaskStrong: 'rgba(20,24,32,0.24)'
};

// ---- glass 浅（i:579-597 玻璃；全屏渐变以 grad 字段近似 i:586）----
const THEME_GLASS_L: ThemeColors = {
  tailBg: 'rgba(18,14,44,0.55)',   // i:587 canvas-tail 随 topbar 组
  base: '#2a2350',      // i:583
  cvs: 'rgba(0,0,0,0)', // i:583 --cvs:transparent——画布透出根容器全屏渐变（grad）
  grad: ['#3b2f7d', '#6d4fc4', '#c76bd8', '#ff9a76'],   // i:586 135° 四停靠点逐值
  panelS: 'rgba(18,14,44,0.55)',   // i:587 .left/.right（backdrop blur ArkUI 近似略，登记）
  panelT: 'rgba(18,14,44,0.55)',   // i:587 .topbar
  tx: '#f4f2ff', tx2: '#c9c2ef', tx3: '#9a93be',   // i:584
  acc: '#8b7bff', accTx: '#9485ff', purple: '#a78bfa', ok: '#4ade80',   // i:584-585
  okText: '#4ade80',   // glass chrome 暗底，READY 字直用 ok
  bd: 'rgba(255,255,255,0.22)',   // i:585 --bd
  shsm: 'rgba(0,0,0,0.35)', shadowMd: 'rgba(0,0,0,0.45)', shadowLg: 'rgba(0,0,0,0.60)',
  card: 'rgba(255,255,255,0.10)',   // i:590 compcell 半透。登记取舍：桌面 frame-body 白底（i:220）
                                    // 与 compcell 半透是两个值，单 card token 取卡片族锚点，画板卡随之半透
  onAcc: '#1e1650',  // i:585 --acc-contrast
  subtle: 'rgba(255,255,255,0.10)',   // i:590 mode-seg 半透白
  line: 'rgba(255,255,255,0.22)',       // i:582 --panel-line
  lineStrong: 'rgba(255,255,255,0.25)', // i:588 浮层边
  wireStroke: '#8b96a5', dim: 'rgba(255,255,255,0.24)',   // 暗底 chrome → 深档扩展值（登记）
  floatBg: 'rgba(22,15,56,0.5)',   // i:588 ctools/czoom/promptbar
  modalMask: 'rgba(20,24,32,0.22)',   // 桌面遮罩不分主题（登记同值）
  toastBg: '#20252d',
  demoBg: '#101013', demoTopBg: 'rgba(16,16,19,0.72)', demoText: '#9a9aa2', demoExitBg: 'rgba(255,255,255,0.16)',
  accSoft: 'rgba(148,133,255,0.16)', purpleBorder: 'rgba(167,139,250,0.40)',
  danger: '#ff6369', dangerSoft: 'rgba(255,99,105,0.14)', dangerBorder: 'rgba(255,99,105,0.35)',
  okSoft: 'rgba(74,222,128,0.14)', okBorder: 'rgba(74,222,128,0.35)',
  trans: 'rgba(0,0,0,0)',
  wireText: '#aab4c0',
  chromeBg: 'rgba(22,15,56,0.48)',        // i:589 frame-chrome
  chromeBgActive: 'rgba(22,15,56,0.62)',  // i:590 active（(0,4,1) 胜）
  chromeAccBorder: 'rgba(0,122,255,0.45)',   // i:213 边框胜 i:589（级联实证）
  flowStroke: '#3f8fff',
  toastErrBg: '#3d1420', toastErrBorder: '#e05252', toastErrText: '#ffd7d7',
  purpleSoft: 'rgba(167,139,250,0.20)',
  // iss-4 chip token：浅档=桌面原值 rgba(0,0,0,0.07)/var(--tx)（glass 浅 pchip 无主题覆写，i:245 兜底）
  chipLine: 'rgba(0,0,0,0.07)', chipTx: '#f4f2ff',
  pressFill: 'rgba(255,255,255,0.16)',  // subtle 0.10 提一档（glass 半透白档）
  // batch-3 表面字段（同 mac 浅口径，阴影色=本表现值）
  rVeil: 22, rDialog: 14, rTplCard: 12, rBoardFrame: 10, rMenuPanel: 10, rFloatBar: 12,
  rBtnPrimary: 9, rBtnDialog: 8, rBtnSecondary: 7, rChipPill: 99, rInput: 7, rPmain: 12,
  rIcon: 5, fDialogTitle: 15, fBtnPrimary: 13,
  shFloat: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.45)' },
  shMenu: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.45)' },
  shPop: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shDock: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shDialog: { radius: 24, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shCard: { radius: 2, offsetX: 0, offsetY: 1, color: 'rgba(0,0,0,0.35)' },
  modalMaskStrong: 'rgba(20,24,32,0.24)'
};

// ---- glass 深（i:721-729 夜空玻璃）----
const THEME_GLASS_D: ThemeColors = {
  tailBg: 'rgba(18,14,44,0.55)',   // i:587（dark glass 组 i:726 不含 canvas-tail，级联实证）
  base: '#0d0a20',      // i:723
  cvs: 'rgba(0,0,0,0)', // i:723
  grad: ['#0a0820', '#231a52', '#3d2a6e', '#51307a'],   // i:727 四停靠点逐值
  panelS: 'rgba(10,8,26,0.66)',   // i:726 .left/.right
  panelT: 'rgba(10,8,26,0.66)',   // i:726 .topbar
  tx: '#f0edff', tx2: '#bcb4e6', tx3: '#958eb8',   // i:724
  acc: '#9a8bff', accTx: '#9a8bff', purple: '#a78bfa', ok: '#4ade80',
  //   acc/accTx = i:725；purple/ok 未覆写→继承浅档 i:585
  okText: '#4ade80',
  bd: 'rgba(255,255,255,0.18)',   // i:725 --bd
  shsm: 'rgba(0,0,0,0.35)', shadowMd: 'rgba(0,0,0,0.45)', shadowLg: 'rgba(0,0,0,0.60)',
  card: 'rgba(255,255,255,0.07)',   // i:729 compcell（同 glass 浅 token 取舍登记）
  onAcc: '#191243',  // i:726 --acc-contrast
  subtle: 'rgba(255,255,255,0.10)',   // 继承 glass 浅 mode-seg 值（深档无覆写）
  line: 'rgba(255,255,255,0.18)',       // i:747 --panel-line
  lineStrong: 'rgba(255,255,255,0.16)', // i:729 compcell 边
  wireStroke: '#8b96a5', dim: 'rgba(255,255,255,0.24)',
  floatBg: 'rgba(28,29,34,0.92)',   // i:710 通用深色补丁兜底（glass 深无主题级 ctools 覆写，级联实证登记）
  modalMask: 'rgba(20,24,32,0.22)',   // 桌面遮罩不分主题（登记同值）
  toastBg: '#20252d',
  demoBg: '#101013', demoTopBg: 'rgba(16,16,19,0.72)', demoText: '#9a9aa2', demoExitBg: 'rgba(255,255,255,0.16)',
  accSoft: 'rgba(154,139,255,0.16)', purpleBorder: 'rgba(167,139,250,0.40)',
  danger: '#ff6369', dangerSoft: 'rgba(255,99,105,0.14)', dangerBorder: 'rgba(255,99,105,0.35)',
  okSoft: 'rgba(74,222,128,0.14)', okBorder: 'rgba(74,222,128,0.35)',
  trans: 'rgba(0,0,0,0)',
  wireText: '#aab4c0',
  chromeBg: 'rgba(255,255,255,0.07)',     // i:729 frame-chrome
  chromeBgActive: 'rgba(22,15,56,0.62)',  // i:590 active（0,4,1)仍胜深档 i:729（级联实证）
  chromeAccBorder: 'rgba(255,255,255,0.16)',   // i:729 边框覆压 active 边
  flowStroke: '#3f8fff',
  toastErrBg: '#3d1420', toastErrBorder: '#e05252', toastErrText: '#ffd7d7',
  purpleSoft: 'rgba(167,139,250,0.20)',
  // iss-4 chip token：深档玻璃实边 rgba(255,255,255,0.16)（i:742 flowrow 主题规则胜通用补丁，
  // 单 token 取卡片族锚点——同 card 字段取舍口径登记）；字=var(--tx2)（i:708）
  chipLine: 'rgba(255,255,255,0.16)', chipTx: '#bcb4e6',
  pressFill: 'rgba(255,255,255,0.16)',  // subtle 0.10 提一档
  // batch-3 表面字段（同 mac 浅口径，阴影色=本表现值）
  rVeil: 22, rDialog: 14, rTplCard: 12, rBoardFrame: 10, rMenuPanel: 10, rFloatBar: 12,
  rBtnPrimary: 9, rBtnDialog: 8, rBtnSecondary: 7, rChipPill: 99, rInput: 7, rPmain: 12,
  rIcon: 5, fDialogTitle: 15, fBtnPrimary: 13,
  shFloat: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.45)' },
  shMenu: { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.45)' },
  shPop: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shDock: { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shDialog: { radius: 24, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0.60)' },
  shCard: { radius: 2, offsetX: 0, offsetY: 1, color: 'rgba(0,0,0,0.35)' },
  modalMaskStrong: 'rgba(20,24,32,0.24)'
};

// ---- hmos 浅（batch-1，iss-4：鸿蒙原生 token——值取自 ../model/Theme 常量=baseline 条目，
//      与 resources/base/element/color.json dd_* 同名同值镜像；风格偏离逐字段登记）----
const THEME_HMOS_L: ThemeColors = {
  tailBg: 'rgba(255,255,255,0.9)',   // 画布上模糊材质与 floatBg 同族；浅档=桌面 i:53 原值同值（无偏离）
  base: HMOS_BG_PAGE.light,          // 偏离 mac #f2f3f7 → #FFFFFF（baseline 2.5 页面背景）
  cvs: HMOS_BG_SUB.light,            // 偏离 mac #f2f3f7 → #F1F3F5（baseline 2.5 次级背景承载画布；验收采样点）
  grad: ['#F1F3F5', '#F1F3F5', '#F1F3F5', '#F1F3F5'],   // 非玻璃主题 4×cvs 纯色等价（沿用既有口径）
  panelS: HMOS_BG_SUB.light,         // 偏离 mac 半透白 rgba(255,255,255,0.92) → 实底 #F1F3F5
                                     // （登记：改实底分层+backdropBlur 保留沉浸光感，baseline 2.5 次级背景）
  panelT: HMOS_BG_SUB.light,         // 偏离 mac rgba(255,255,255,0.85) → 实底（同上登记）
  tx: HMOS_TEXT_PRIMARY.light,       // 偏离 mac #1c1c1e 纯黑系 → #182431 墨蓝黑非纯黑（baseline 2.1）
  tx2: HMOS_TEXT_SECONDARY.light,    // 偏离 mac #636366 独立灰 → 主色 60% alpha（baseline 2.1 层级靠 alpha）
  tx3: HMOS_TEXT_TERTIARY.light,     // 主色 40% alpha（baseline 2.1）
  acc: HMOS_BRAND.light,             // 偏离 mac #007aff → #007DFF（baseline 2.2 brand）
  accTx: HMOS_PRESSED.light,         // 偏离 mac #0066d6 → #0070E5（鸿蒙按压态 token 承担「强调深一档」语义，baseline 2.2）
  purple: HMOS_PURPLE.light,         // 偏离 mac #9d4edd → #8A2BE2（baseline 2.4 palette6）
  ok: HMOS_SUCCESS.light,            // 偏离 mac #28a745 → #47CC47（系统无 success token [C]，palette4 充任，baseline 2.3/2.4）
  okText: '#1d6b41',                 // 状态栏 READY 字桌面固定色 i:374 原值（非主题变量，不动）
  bd: HMOS_SEPARATOR.light,          // 偏离 mac rgba(0,0,0,0.08) → #33182431（baseline 2.6 列表分隔线承载 --bd）
  shsm: '#0C000000',                 // 偏离 mac rgba(0,0,0,0.05) → [A1] 阴影色锚点 5% 黑（baseline 6）
  shadowMd: '#1A000000',             // #0C000000 同系 10% 提档（三档递进以 alpha 阶梯保留，登记推导）
  shadowLg: '#26000000',             // 同系 15% 提档（登记推导）
  card: HMOS_DIALOG_BG.light,        // #FFFFFF 卡片/浮层实底=对话框背景浅档（同值无偏离）
  onAcc: HMOS_ON_ACCENT.light,       // font_on_primary 白（baseline 9；A1 font_on 浅=#ffffff）
  subtle: HMOS_COMPONENT_NORMAL.light,  // 偏离 mac rgba(0,0,0,0.05) → 10% 墨（baseline 2.5 普通控件底）
  line: HMOS_SEPARATOR.light,        // 偏离 mac rgba(0,0,0,0.12) → #33182431（baseline 2.6）
  lineStrong: '#4D182431',           // 偏离 mac rgba(0,0,0,0.14) → 30% 墨（separator 上探一档，鸿蒙无强边 token，登记推导）
  wireStroke: '#9aa4b2',             // 线框描边 i:627 桌面强制色原值（画布数据不动，无鸿蒙 token）
  dim: 'rgba(0,0,0,0.18)',           // 弱化点桌面原值（同 mac 浅）
  floatBg: 'rgba(255,255,255,0.9)',  // 模糊材质载体：悬浮底半透+backgroundBlurStyle（baseline 9 模糊材质；浅档=桌面 i:196 同值）
  modalMask: HMOS_DIALOG_MASK.light, // 偏离桌面 rgba(20,24,32,0.22) → #33000000（baseline 2.6 对话框蒙层）
  toastBg: '#20252d',                // i:648 固定色不分主题（不动）
  demoBg: '#101013', demoTopBg: 'rgba(16,16,19,0.72)', demoText: '#9a9aa2', demoExitBg: 'rgba(255,255,255,0.16)',
                                     // 演示模式固定色组（全部主题同值，不动）
  accSoft: 'rgba(0,125,255,0.08)',   // brand 同源 tint，alpha 沿用桌面浅档 0.08 档位（登记推导；偏离 mac rgba(0,102,214,0.08)）
  purpleBorder: 'rgba(138,43,226,0.35)',  // purple 同源 tint，alpha 沿用桌面 0.35 档位（登记推导）
  danger: HMOS_WARNING.light,        // 偏离 mac #e5484d → #FA2A2D（baseline 2.3 warning）
  dangerSoft: 'rgba(250,42,45,0.08)',     // warning 同源 tint，alpha 桌面浅档档位（登记推导）
  dangerBorder: 'rgba(250,42,45,0.30)',   // 同上
  okSoft: 'rgba(71,204,71,0.10)',    // palette4 同源 tint，alpha 桌面浅档档位（登记推导）
  okBorder: 'rgba(71,204,71,0.35)',  // 同上
  trans: 'rgba(0,0,0,0)',
  wireText: '#52606d',               // 线框文字 i:628 桌面强制色原值（画布数据不动）
  chromeBg: HMOS_BG_SUB.light,       // 偏离 mac #f0f1f5 → #F1F3F5（画板卡标题栏灰条=次级背景，baseline 2.5）
  chromeBgActive: HMOS_DIALOG_BG.light,  // #FFFFFF（i:213 active 白底，同 card 无偏离）
  chromeAccBorder: 'rgba(0,125,255,0.45)',  // i:213 固定蓝 0.45 档位换 brand 同源 tint（登记：rgba(0,122,255,0.45)→rgba(0,125,255,0.45)，baseline 2.2）
  flowStroke: '#3f8fff',             // 连线专线色不随主题（i:1896，画布数据不动）
  toastErrBg: '#3d1420', toastErrBorder: '#e05252', toastErrText: '#ffd7d7',   // i:647 固定色（不动）
  purpleSoft: 'rgba(138,43,226,0.12)',    // purple tint，alpha 桌面浅档档位（登记推导）
  // iss-4 chip token：chipLine=鸿蒙分隔线（偏离桌面 rgba(0,0,0,0.07)，baseline 2.6）；
  // chipTx=主文本（桌面 i:245 var(--tx) 原值语义——浅档不切次级，深档才切，见 D 表）
  chipLine: HMOS_SEPARATOR.light,
  chipTx: HMOS_TEXT_PRIMARY.light,
  pressFill: '#33182431',           // subtle #19182431 → 20% 墨提一档（与蒙层薄浅同值复用，登记）
  // batch-3 表面字段（HMOS=baseline §4/§6 值；radius/字号档位引用 Theme.ets 常量）
  rVeil: HMOS_RADIUS_CARD,            // 22→24（§4 card）
  rDialog: HMOS_RADIUS_DIALOG,        // 14→24（§4 dialog）
  rTplCard: HMOS_RADIUS_CARD,         // 12→24
  rBoardFrame: HMOS_RADIUS_CARD,      // 10→24
  rMenuPanel: HMOS_RADIUS_MENU,       // 10→20（§4 menu）
  rFloatBar: HMOS_RADIUS_BUTTON,      // 12→20（§4 button 档）
  rBtnPrimary: HMOS_RADIUS_BUTTON,    // 9→20
  rBtnDialog: HMOS_RADIUS_BUTTON,     // 8→20
  rBtnSecondary: HMOS_RADIUS_CHIP,    // 7→14（§4 small_button/piece）
  rChipPill: HMOS_RADIUS_CHIP,        // 99→14（胶囊→芯片形态变更，登记）
  rInput: HMOS_RADIUS_TEXT_FIELD,     // 7→20（§4 text_field）
  rPmain: HMOS_RADIUS_TEXT_FIELD,     // 12→20
  rIcon: HMOS_RADIUS_ICON,            // 5→8（§4 icon）
  fDialogTitle: HMOS_FONT_DIALOG_TITLE,   // 15→20（§3 dialog_tittle）
  fBtnPrimary: HMOS_FONT_BUTTON,      // 13→16（§3 button 默认档）
  shFloat: { radius: 40, offsetX: 0, offsetY: 10, color: '#0C000000' },    // §6 sm 档（=shsm 色阶）
  shMenu: { radius: 60, offsetX: 0, offsetY: 10, color: '#1A000000' },     // §6 md 档（=shadowMd 色阶）
  shPop: { radius: 60, offsetX: 0, offsetY: 10, color: '#1A000000' },
  shDock: { radius: 100, offsetX: 0, offsetY: 20, color: '#26000000' },    // §6 lg 档（=shadowLg 色阶）
  shDialog: { radius: 100, offsetX: 0, offsetY: 20, color: '#26000000' },
  shCard: { radius: 0, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0)' },   // 无阴影（§6 落地建议）
  modalMaskStrong: HMOS_DIALOG_MASK.light   // #33000000（与 modalMask 同值，强档收编单档）
};

// ---- hmos 深（batch-1，iss-4：同浅档口径，值取自 Theme.ets 常量 dark 档=baseline 深色列）----
const THEME_HMOS_D: ThemeColors = {
  tailBg: 'rgba(28,29,34,0.92)',     // 与 floatBg 深档同值（偏离桌面 i:63 rgba(28,29,34,0.94)——模糊材质同族统一，登记）
  base: HMOS_BG_PAGE.dark,           // 偏离 mac #212125 → #18181A（baseline 2.5 页面背景深=非纯黑）
  cvs: HMOS_BG_SUB.dark,             // 偏离 mac #26262b → #000000（baseline 2.5 次级背景深；验收采样点）
  grad: ['#000000', '#000000', '#000000', '#000000'],
  panelS: HMOS_BG_SUB.dark,          // 偏离 mac rgba(30,30,34,0.94) → 实底 #000000（实底分层+backdropBlur，同浅档登记）
  panelT: HMOS_BG_SUB.dark,          // 同上
  tx: HMOS_TEXT_PRIMARY.dark,        // 偏离 mac #e8e8ec → #DBFFFFFF 86% 白非纯白（baseline 2.1）
  tx2: HMOS_TEXT_SECONDARY.dark,     // 60% 白（baseline 2.1）
  tx3: HMOS_TEXT_TERTIARY.dark,      // 40% 白（baseline 2.1）
  acc: HMOS_BRAND.dark,              // 偏离 mac #0a84ff → #006CDE（brand 深色加深避免暗底过亮，baseline 2.2）
  accTx: HMOS_PRESSED.dark,          // 偏离 mac #2f97ff → #1A7AE1（按压态深档，baseline 2.2）
  purple: HMOS_PURPLE.dark,          // #8A2BE2（palette6 深档 A1 提取实证同值——Theme.ets 登记提取）
  ok: HMOS_SUCCESS.dark,             // 偏离 mac #28a745 → #007900（palette4 深档 A1 dark/element/color.json 提取）
  okText: HMOS_SUCCESS.light,        // #47CC47：暗底 READY 字取 palette4 亮档保可读（#007900 暗底不可读，登记推导，同 mac 深 okText 口径）
  bd: HMOS_SEPARATOR.dark,           // #33FFFFFF（baseline 2.6）
  shsm: '#26000000',                 // #0C000000 系暗档 15%（暗档加深沿用桌面深档精神，登记推导）
  shadowMd: '#40000000',             // 同系 25%（登记推导）
  shadowLg: '#59000000',             // 同系 35%（登记推导）
  card: HMOS_DIALOG_BG.dark,         // 偏离 mac #28282d → #202224（baseline 2.5 对话框背景深=卡片/浮层实底锚点）
  onAcc: HMOS_ON_ACCENT.dark,        // font_on_primary 白（A1 dark font_on=#ffffff）
  subtle: HMOS_COMPONENT_NORMAL.dark,  // 偏离 mac rgba(255,255,255,0.06) → 10% 白（baseline 2.5 component_normal 深）
  line: HMOS_SEPARATOR.dark,         // 偏离 mac #3a3a40 → #33FFFFFF（baseline 2.6）
  lineStrong: '#4DFFFFFF',           // 偏离 mac #3a3a3f → 30% 白（separator 上探一档，登记推导）
  wireStroke: '#8b96a5',             // 线框深档鸿蒙扩展（同 THEME_MAC_D 口径，画布数据不动）
  dim: 'rgba(255,255,255,0.24)',     // 同 mac 深
  floatBg: 'rgba(28,29,34,0.92)',    // 模糊材质载体（指令给定值）+backgroundBlurStyle 保留（baseline 9）
  modalMask: HMOS_DIALOG_MASK.dark,  // 偏离桌面 rgba(20,24,32,0.22) → #66000000（baseline 2.6 对话框蒙层深）
  toastBg: '#20252d',                // i:648 固定色（不动）
  demoBg: '#101013', demoTopBg: 'rgba(16,16,19,0.72)', demoText: '#9a9aa2', demoExitBg: 'rgba(255,255,255,0.16)',
  accSoft: 'rgba(0,108,222,0.16)',   // acc 深档同源 tint，alpha 桌面深档 0.16 档位（登记推导）
  purpleBorder: 'rgba(138,43,226,0.40)',  // alpha 深档档位（登记推导）
  danger: HMOS_WARNING.dark,         // 偏离 mac #ff6369 → #E64548（baseline 2.3 warning 深）
  dangerSoft: 'rgba(230,69,72,0.14)',     // warning 同源 tint，alpha 桌面深档档位（登记推导）
  dangerBorder: 'rgba(230,69,72,0.35)',   // 同上
  okSoft: 'rgba(71,204,71,0.14)',    // tint 源取 palette4 亮档保暗底可见（#007900 tint 不可见，登记推导）
  okBorder: 'rgba(71,204,71,0.35)',  // 同上
  trans: 'rgba(0,0,0,0)',
  wireText: '#aab4c0',
  chromeBg: HMOS_DIALOG_BG.dark,     // 画板卡标题栏=card 实底（同 mac 深 chrome=card 口径，登记推导）
  chromeBgActive: HMOS_DIALOG_BG.dark,   // 同 mac 深：active 区分由画板 acc 边承担（级联口径登记）
  chromeAccBorder: 'rgba(0,108,222,0.45)',  // brand 深档 tint 0.45 档（登记推导）
  flowStroke: '#3f8fff',
  toastErrBg: '#3d1420', toastErrBorder: '#e05252', toastErrText: '#ffd7d7',
  purpleSoft: 'rgba(138,43,226,0.20)',
  // iss-4 chip token：chipLine=鸿蒙分隔线深档 #33FFFFFF（iss-4 判负条件消除：深档边框可见）；
  // chipTx=次级文本 60% 白（深色补丁 i:708 var(--tx2) 语义 → 鸿蒙次级文本，baseline 2.1）
  chipLine: HMOS_SEPARATOR.dark,
  chipTx: HMOS_TEXT_SECONDARY.dark,
  pressFill: '#33FFFFFF',           // subtle #19FFFFFF → 20% 白提一档（与分隔线深同值复用，登记）
  // batch-3 表面字段（同浅档口径，阴影色=本表深档色阶）
  rVeil: HMOS_RADIUS_CARD,            // 22→24（§4 card）
  rDialog: HMOS_RADIUS_DIALOG,        // 14→24（§4 dialog）
  rTplCard: HMOS_RADIUS_CARD,         // 12→24
  rBoardFrame: HMOS_RADIUS_CARD,      // 10→24
  rMenuPanel: HMOS_RADIUS_MENU,       // 10→20（§4 menu）
  rFloatBar: HMOS_RADIUS_BUTTON,      // 12→20（§4 button 档）
  rBtnPrimary: HMOS_RADIUS_BUTTON,    // 9→20
  rBtnDialog: HMOS_RADIUS_BUTTON,     // 8→20
  rBtnSecondary: HMOS_RADIUS_CHIP,    // 7→14（§4 small_button/piece）
  rChipPill: HMOS_RADIUS_CHIP,        // 99→14（胶囊→芯片形态变更，登记）
  rInput: HMOS_RADIUS_TEXT_FIELD,     // 7→20（§4 text_field）
  rPmain: HMOS_RADIUS_TEXT_FIELD,     // 12→20
  rIcon: HMOS_RADIUS_ICON,            // 5→8（§4 icon）
  fDialogTitle: HMOS_FONT_DIALOG_TITLE,   // 15→20（§3 dialog_tittle）
  fBtnPrimary: HMOS_FONT_BUTTON,      // 13→16（§3 button 默认档）
  shFloat: { radius: 40, offsetX: 0, offsetY: 10, color: '#26000000' },    // §6 sm 档（深档色阶）
  shMenu: { radius: 60, offsetX: 0, offsetY: 10, color: '#40000000' },     // §6 md 档
  shPop: { radius: 60, offsetX: 0, offsetY: 10, color: '#40000000' },
  shDock: { radius: 100, offsetX: 0, offsetY: 20, color: '#59000000' },    // §6 lg 档
  shDialog: { radius: 100, offsetX: 0, offsetY: 20, color: '#59000000' },
  shCard: { radius: 0, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0)' },   // 无阴影（§6 落地建议）
  modalMaskStrong: HMOS_DIALOG_MASK.dark    // #66000000（与 modalMask 同值，强档收编单档）
};

// 交互触发器族（gap-right-3，对齐通用版 trigger select 档位）
const TRIGGERS: string[] = ['tap', 'long_press', 'swipe_left', 'swipe_right', 'swipe_up',
  'swipe_down', 'scroll_end', 'key_enter', 'focus', 'blur'];
const ACTIONS: string[] = ['navigate_to', 'show_toast', 'back'];
// pmain 主输入占位文案（dock 等比字号适配与 TextInput placeholder 共用单一事实源——
// 两处各写一份字面量会漂移，emWidth 估的就是它）
const DOCK_PH: string = '描述意图（如：生成 Web 登录页 / 一键修复 / 深色主题）…';

// ===== 画布几何常量（batch-2，iss-2 方案 A：工具行入流后 boardOrigin y 的单一推导源）=====
// 【复审修订】不把 108 当拍定值：此处常量推导 + 模拟器 dump 实测双重校验（boardOrigin 有真实
// 回归前科——boards Row 顶对齐修复注记见画布构建区），单一常量源、消费点禁止散落魔数。
const CANVAS_TOOLBAR_TOP: number = 36;    // Scroll 内容首行 wrapper padding-top（让位尾栏 overlay 32+4 间距）
const CANVAS_TOOLBAR_H: number = 34;      // ctools/czoom bar 显式高（bar padding 5+5+内容 24=34，与原内禀高一致）
const CANVAS_BOARDS_PAD_TOP: number = 8;  // 板横排 Row padding-top（原 56 是绝对定位工具行让位口径，入流后收窄）
const BOARD_CHROME_H: number = 30;        // 板标题栏恒高（boardOrigin 既有口径，不随 zoom）
// 工具块总高（wrapper padding-top + 工具行高）= 70：iss-1 veil minHeight 扣除项（与 boardOrigin 同源）
const CANVAS_TOOLBLOCK_H: number = CANVAS_TOOLBAR_TOP + CANVAS_TOOLBAR_H;
// boardOrigin y = 工具块 70 + 板排 padding-top 8 + chrome 30 = 108（旧口径 56+30=86）
const CANVAS_BOARD_TOP: number = CANVAS_TOOLBLOCK_H + CANVAS_BOARDS_PAD_TOP + BOARD_CHROME_H;

// ===== 三区等比适配常量（batch-7 cur-1：窄窗响应式显性扩展决策，沿用顶栏 isNarrowBar 先例）=====
// 桌面左右栏为固定 252/360px（还原窗 980vp 下画布仅剩 368vp=37.6%，r8 §1 判负根因）。
// 鸿蒙自由窗口改按窗宽等比折算：基准 1280vp（桌面设计宽，252+360 下画布 52%），≥1280 恒
// 桌面同宽（1620 全幅=桌面形态逐值一致）；下限按还原窗 980 校准——196+276=472（48.2%≤55%）
// → 画布 508（51.8%≥45%，验收判据 1）。数值来源=公式推导（r4 §4.1 教训：坐标逐构建漂移，
// 不拍死 dump 瞬时值），模拟器验收若越判据界再回查此组常量（ddCols 日志已埋，见 applyWindowW）。
const COL_REF_W: number = 1280;      // 等比基准窗宽（vp）
const LEFT_W_MAX: number = 252;      // 桌面左栏宽（折算上限=桌面同宽）
const RIGHT_W_MAX: number = 360;     // 桌面右栏宽
const LEFT_W_MIN: number = 196;      // 还原窗 980 折算下限（252×0.766=193 → 取整 196）
const RIGHT_W_MIN: number = 276;     // 360×0.766=276
// 画布最小可用宽门控（cur-1 判负消除 + 右栏折叠共用阈）：工具行自然宽（r8 boot dump 实测
// ctools 五钮条 330.5vp + 分隔线/⤢ ~69 + czoom ~148 = ~548 内容宽）+ 呼吸余量 28 → 576。
// 消费一：cw<此阈时 ctools/czoom 行转横向 Scroll（撑压裁切碎片根治，见 toolRowScroll）；
// 消费二：winW<左+右+此阈时门控触发，未选中元素态右栏折叠（rightFolded）。dump 校准待
// 模拟器（本批后验收），偏差大先回查此值。
const CANVAS_MIN_W: number = 576;

// 服务商预设（batch-3，audit-modal-6 扩到 14 项对齐桌面 i:1138-1154：13 预设+自定义；
// baseUrl/model 逐项对齐桌面 PROVIDERS i:3978-3994，勿做成总共 13 项）。
// snap=models.json 快照 provider 键（能力提示查表，i:1157-1164 语义）。
// batch-9 平级化（用户 2026-10-04 显性决策，偏离登记：桌面默认 deepseek 且无小艺条目，
// r8-general-spec spec-settings-3 实证「小艺不在通用版列表」——鸿蒙侧首项插 xiaoyi 档，
// 其余 14 项与桌面同 id 同序不动；DeepSeek 名内「（默认）」后缀随默认位让渡摘除。
// id 集合与 AiConfig.PROVIDER_IDS 净化白名单耦合（两处同步扩）。
interface ProviderPreset {
  id: string;      // 对齐桌面 applyProvider 键
  name: string;    // 菜单显示名（i:1140-1153 逐字）
  baseUrl: string;
  model: string;   // 预设默认模型（桌面 PROVIDERS 同款）
  snap: string;    // rawfile/models.json 的 provider 键；custom 为 ''
}
const PRESETS: ProviderPreset[] = [
  { id: 'xiaoyi', name: '小艺 · 端侧（免配置）', baseUrl: '', model: '', snap: '' },
  { id: 'deepseek', name: 'DeepSeek', baseUrl: 'https://api.deepseek.com', model: 'deepseek-flash', snap: 'deepseek' },
  { id: 'glm', name: 'GLM', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-5.3', snap: 'zhipuai' },
  { id: 'glm-coding', name: 'GLM Coding', baseUrl: 'https://open.bigmodel.cn/api/coding/paas/v4', model: 'glm-5.3', snap: 'zhipuai-coding-plan' },
  { id: 'zai', name: 'z.ai', baseUrl: 'https://api.z.ai/api/paas/v4', model: 'glm-5.3', snap: 'zai' },
  { id: 'zai-coding', name: 'z.ai Coding', baseUrl: 'https://api.z.ai/api/coding/paas/v4', model: 'glm-5.3', snap: 'zai-coding-plan' },
  { id: 'kimi', name: 'Kimi API', baseUrl: 'https://api.moonshot.cn/v1', model: 'kimi-k3', snap: 'moonshotai-cn' },
  { id: 'kimi-plan', name: 'Kimi 订阅', baseUrl: 'https://api.kimi.com/coding/v1', model: 'kimi-for-coding', snap: 'kimi-code-plan-cn' },
  { id: 'minimax', name: 'MiniMax', baseUrl: 'https://api.minimax.cn/v1', model: 'MiniMax-M3', snap: 'minimax-cn' },
  { id: 'minimax-intl', name: 'MiniMax 国际', baseUrl: 'https://api.minimax.io/v1', model: 'MiniMax-M3', snap: 'minimax' },
  { id: 'minimax-anthropic', name: 'MiniMax（Anthropic）', baseUrl: 'https://api.minimaxi.com/anthropic', model: 'MiniMax-M3', snap: 'minimax' },
  { id: 'minimax-anthropic-intl', name: 'MiniMax（Anthropic 国际）', baseUrl: 'https://api.minimax.io/anthropic', model: 'MiniMax-M3', snap: 'minimax' },
  { id: 'stepfun', name: 'StepFun', baseUrl: 'https://api.stepfun.com/v1', model: 'step-3.7-flash', snap: 'stepfun' },
  { id: 'stepfun-plan', name: 'StepFun 订阅', baseUrl: 'https://api.stepfun.com/step_plan/v1', model: 'step-3.7-flash', snap: 'stepfun-step-plan' },
  { id: 'custom', name: '自定义 / 其他端点', baseUrl: '', model: '', snap: '' }
];

// `set` 命令行支持的属性白名单（batch-9 cur-5）——与 AppStore.setStyle 的分支键集一一同面
// （AppStore.ets:932-963）；白名单外诚实拒绝，防 setStyle 静默 no-op 仍记 undo/rev。
interface HSvg {
  id: string;   // 画板 id
  b64: string;  // 引擎 render svg 的 base64（Image data URL 源）
}
interface EngineHistoryReply {
  ok?: boolean;
  artboard?: string;
  rev?: number;
  mbt?: string;
  mbt_b64?: string;
  error?: string;
}
interface EngineRenderBoard {
  id?: string;
  name?: string;
  width?: number;
  height?: number;
  svg?: string;
}
interface EngineRenderReply {
  ok?: boolean;
  entry?: string;
  revision?: number;
  artboards?: EngineRenderBoard[];
  error?: string;
}
const SET_KEYS: string[] = ['x', 'y', 'w', 'h', 'fontSize', 'radius', 'opacity', 'text', 'fill',
  'color', 'align', 'visible', 'bold', 'shadow', 'dash', 'italic', 'widthMode', 'layout',
  'justify', 'gap', 'padding', 'stroke', 'strokeWidth'];

// 思考等级 6 档（batch-3，audit-modal-6，i:1166-1175 逐字；方言收窄归 gap-global-3）
interface ThinkLevelDef {
  id: string;
  label: string;
}
const THINK_LEVELS: ThinkLevelDef[] = [
  { id: 'auto', label: 'auto · 自适应（默认）' },
  { id: 'low', label: 'low · 浅思考' },
  { id: 'medium', label: 'medium · 中' },
  { id: 'high', label: 'high · 深（推荐）' },
  { id: 'max', label: 'max · 最深' },
  { id: 'off', label: 'off · 关闭思考' }
];
const THINK_NOTE: string = '等级经 reasoning_effort 下发（DeepSeek/Kimi/GLM-5.2+）；MiniMax 仅支持开关。GLM-5.3 不支持关闭。';

// mode-seg 三钮 SVG path（batch-4，audit-topbar-6，抄 i:811/814/817；与 this.modes 按下标对应）
const MODE_ICON_PATHS: string[] = [
  'M4 4h16v16H4z M8 4v16 M16 4v16 M4 9h16 M4 15h16',
  'M4 5.5A2.5 2.5 0 0 1 6.5 3h11A2.5 2.5 0 0 1 20 5.5v13a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 18.5z M8 7h8 M8 11h8 M8 15h5',
  'M16 18l6-6-6-6 M8 6l-6 6 6 6'
];

// 步数上限 4 档（batch-3，audit-modal-6，i:1176-1183 逐字）
interface StepCapDef {
  steps: number;
  label: string;
}
const STEP_CAPS: StepCapDef[] = [
  { steps: 200, label: '200 步 · 轻量任务' },
  { steps: 500, label: '500 步 · 常规（默认）' },
  { steps: 1000, label: '1000 步 · 复杂应用' },
  { steps: 2000, label: '2000 步 · 极限' }
];

// invoke_fx_sdk models 返回的具名形状
interface ModelsOutcome {
  models?: string[];
  source?: string;
  error?: string;
}

// ===== 模型能力提示（batch-3，audit-modal-6；桌面 #agent-model-hint/fillModelHints i:1157-1164 等价）=====
// rawfile/models.json（models.dev 裁剪快照）providers.{p}.models.{m} 动态键对象用 Record 承载
// （ArkTS 动态键正道；House 禁的是 Record 强转断言写法，非 Record 类型标注）。
// batch-6 登记：原注释含该断言写法的字面量，为使全量 grep 纪律判据（instructions ③口径二）
// 归零而改写措辞——语义不变，静态核对口径自此全量 grep 与非注释行口径双零。
interface CapLimit {
  context?: number;
}
interface ReasoningOption {
  type?: string;       // effort | toggle
  values?: string[];
}
interface CapModel {
  tool_call?: boolean;
  structured_output?: boolean;
  reasoning_options?: ReasoningOption[];   // batch-12（spec-settings-2）：思考档位收紧数据源
  limit?: CapLimit;
}
interface CapProvider {
  models?: Record<string, CapModel>;
}
interface CapRoot {
  providers?: Record<string, CapProvider>;
}
/** 展示层能力元组（上下文窗口/工具调用/结构化/思考档收紧输入）。 */
interface ModelCap {
  context: number;   // tokens；0=快照未记
  toolCall: boolean;
  structured: boolean;
  reasoningEffort: string[];   // effort 型实测档（batch-12）
  reasoningToggle: boolean;    // toggle 型在案（batch-12）
}

// 澄清多轮挂起（gap-bottom-1）
interface ClarifyPending {
  task: string;      // 原指令
  question: string;  // 提问全文
}

// save_text_file 返回的具名形状
interface SavedFile {
  savedTo?: string;
}

// inspector 行 @Builder 的参数形状（batch-5 起仅 DraftRowSpec/SegChipsSpec 在用；
// 按引用传参规则同前：单对象字面量属性读取 @State，状态变化即刷新 builder 内容）。

interface DraftRowSpec {
  label: string;
  val: string;
  onCh: (v: string) => void;
}

interface SegChipsSpec {
  label: string;
  values: string[];
  labels: string[];
  current: string;
  onPick: (v: string) => void;
}

// MBT 源码高亮（gap-mbt-7）：切片区间（半开 [s,e)），七类 token 同名桌面 tok-*（去前缀）
interface MbtSpan {
  s: number;
  e: number;
  cls: string;   // comment | string | number | keyword | type | yaml-key | yaml-val
}

// 高亮按行渲染片段（Span 内 \n 渲染 d.ts 无契约 → 按行拆分，每行一组 DeclPiece 堆叠）
interface DeclPiece {
  t: string;
  cls: string;   // '' = 正文（T().tx 着色）
}


// 快捷键说明表（设置 sheet §8.4 对齐；⇧E/⇧H 对齐桌面 export-html/svg 键位）
// 快捷键说明表（M3.6.2：鸿蒙 2in1 键盘适配——显示层 ⌘ 系字形改 Ctrl 系；行为层
// onPlanKey :3155 本就双兼容 Ctrl/Meta，不改。桌面同键位语义，仅字形按平台惯例）
const KEYMAP: string[][] = [
  ['Ctrl+Z / Ctrl+Shift+Z', '撤销 / 重做'],
  ['Ctrl+S', '保存'],
  ['Ctrl+K', '聚焦指令条'],
  ['Ctrl+N / Ctrl+Shift+N', '新建项目 / 新建画板'],
  ['Ctrl+O', '打开 DDP'],
  ['Ctrl+Shift+D', '复制当前画板'],
  ['Ctrl+1 / Ctrl+2 / Ctrl+3', '线框图 / 高保真 / 源码视图'],
  ['Ctrl+4', '演示模式'],
  ['Ctrl+Shift+Del', '删除当前画板'],
  ['Ctrl+- / Ctrl++ / Ctrl+0', '缩放 / 适配窗口'],
  ['Del / Backspace', '删除选中元素'],
  ['方向键', '移动 1vp（Shift=10）'],
  ['V / T', '选择 / 文本工具'],
  ['Ctrl+Shift+F', '自动修复'],   // batch-3，audit-modal-9：KEYMAP 与 onPlanKey 双缺补齐
  ['Esc', '返回上一层 / 退出连接模式'],
  ['Ctrl+/', '快捷键（设置内）'],   // 诚实化（batch-6，gap-detail-22）：onPlanKey 对 / 与 , 同开
                                    // 设置 sheet（鸿蒙无独立快捷键 modal，拆分滚动高亮方案成本高
                                    // 登记不取）——文案与行为一致；KEYMAP 全表视觉核对归 2in1 真机
  ['Ctrl+,', '设置'],
  ['Shift+E / Shift+H', '导出 DDP / HTML']
];

/**
 * 画板卡薄壳 BoardFrame（batch-1 引入的 @ObjectLink + @BuilderParam content 箭头闭包外壳）
 * 【r4 摘除，r5 修订定性】——r4 曾认定「外来组件构建上下文吞嵌套 builder 节点」为根因，
 * r5 复测证伪（摘除后编辑壳仍不构建）。摘除本身保留：外壳少一层间接、刷新改由 ForEach 键
 * 携带 rev（`${b.id}|${docEpoch}|${rev}`，op 后该板键跳变 → 板卡重建，与 rev 推送逐 op 等价）。
 * 【r5 再修】键再并入 zoom（`${b.id}|${docEpoch}|${rev}|${round(zoomOf*100)}`）：还原态实证
 * 属性级细粒度更新不回填 .scale（元素挂载但不可见不可点、resize 重建翻转），缩放变更即强制
 * 板卡重建换新属性——详见 boardContent ForEach 处登记。
 * r5 证据链把边界收进 elNode 编辑壳分支体（同 Stack 的 selOverlay/chrome 正常、demo 壳同一
 * elNode 链正常），r6 对属性面逐项对账后弃 GestureGroup 改双 .gesture()（结案定性见
 * elNodeEdit 注）。chrome 视觉成果（恒高标题栏/收边）未动。
 */

// 瞬态防护兜底（batch-repair）：ArkUI 细粒度更新下条件门与分支内表达式求值非原子，
// inspector/bindSection 等 builder 参数改传兜底实例而非 `!` 裸断言——杜绝
// 'Cannot read property style of null' 崩溃类（r3 验收 👁 崩溃实锤 Index.ets:3746）。
const FALLBACK_BOARD: Board = new Board('', '', '', 0, 0, 0, []);
const FALLBACK_LAYER: LayerNode = {
  id: '', name: '', type: 'rect',
  style: {
    x: 0, y: 0, w: 0, h: 0, text: '', fill: '#f0f0f3', color: '#1c1c1e',
    fontSize: 12, radius: 0, opacity: 1, visible: true, align: 'left', bold: false,
    shadow: 'none', dash: 'solid', italic: false, widthMode: 'fixed', layout: 'none',
    justify: 'start', gap: 0, padding: 0, stroke: 'none', strokeWidth: 0
  }
};

@Entry
@Component
struct Index {
  @State coreTag: string = '';
  // 引擎状态行（gap-global-3 接线）：设置页「引擎」行值位。默认=接线前现状文案（诚实降级：
  // 探测失败/不可用时保持它，不假装引擎在场）；探测成功经 dispatch('engine_status') 接
  // 真实 engineVersion（设置页空间可容全串，lfoot 是耗时位归 engApply 实测批次不在此接）。
  @State engineTag: string = 'moonviz · wasmtime 宿主 L1 下沉中';
  private engineOk: boolean = false;   // 探测结果（引擎通路的门；非 @State——不直接驱动 UI）
  // M2（gap-global-3）：命令流引擎优先通路的会话锚——M1 种子链/成功 op 回填，''=本地模式。
  // 投影模型：每 op 前 toCanonicalText 投影当前文档为 docB64（人手 inspector 编辑与 Agent
  // op 共用同一事实源，无分歧），引擎门执行成功后 canonical 合并回灌（mergeCanonical）。
  private lastCanonicalB64: string = '';
  // M3：引擎渲染层（线框+高保真视觉真相=引擎 render SVG）与历史会话状态
  @State hifiSvgs: HSvg[] = [];
  private histReady: boolean = false;
  private pendingEngSel: string = '';   // 引擎新建画板 id（合并回灌后选中落点）
  @State boards: Board[] = [];
  @State selBoard: string = '';
  @State selLayer: string = '';
  @State tabIdx: number = 0;
  @State modeIdx: number = 0;
  @State timeline: TlEntry[] = [];
  @State prompt: string = '';
  @State busy: boolean = false;
  @State agentMsg: string = '';
  @State xiaoyiState: string = '探测中…';
  @State showSettings: boolean = false;
  @State showAllTpl: boolean = false;
  @State zoom: number = 100;
  @State projName: string = '未命名项目';
  @State dirty: boolean = false;
  @State canUndo: boolean = false;
  @State canRedo: boolean = false;
  @State recent: RecentItem[] = [];
  @State showExport: boolean = false;     // 导出 DDP 加密/免密选择浮层
  @State exportPwd: string = '';          // 浮层口令输入（可选，免密=留空）
  @State showPwdAsk: boolean = false;     // DDP 口令重试弹层
  @State pwdInput: string = '';
  @State pwdFor: string = '';             // 待解锁文件路径
  @State showRecoverAsk: boolean = false; // 自恢复询问弹层
  @State cw: number = 0;                  // 画布容器实测宽（vp，gap-canvas-5 适配窗口用）
  @State ch: number = 0;                  // 画布容器实测高
  @State topW: number = 0;                // 顶栏实测宽（vp，batch-1 iss-5 窄窗折叠判定输入）
  // 三区等比适配（batch-7 cur-1）：窗 onAreaChange 重算（applyWindowW），未实测首帧=桌面同宽
  // （r5b 未实测回退设计值先例，防 0 宽退化）；winW 为折叠门控输入（canvasGate）。
  @State winW: number = 0;                // 窗内容区实测宽（vp）
  @State leftW: number = LEFT_W_MAX;      // 左栏宽（196–252 等比折算）
  @State rightW: number = RIGHT_W_MAX;    // 右栏宽（276–360 等比折算；折叠期不构建，值保留供门控）
  @State fitMode: boolean = false;        // 读数「适配 xx%」标记（±/1:1 操作即退出）
  @State dragId: string = '';             // 跟手拖拽中的图层 id（gap-canvas-2）
  @State dragX: number = 0;
  @State dragY: number = 0;
  @State boardOffsets: Array<[string, number, number]> = [];  // 画板视图偏移（纯视图层，不入 AppStore）
  @State comps: CompDef[] = [];           // 组件快照（rawfile/vendor/components.json，65 项）
  @State compQuery: string = '';          // 组件搜索子串
  @State compSearchFocused: boolean = false;  // 搜索框聚焦（batch-6，audit-left-11 focus 白底+acc 边）
  @State dragGhostCid: string = '';       // 组件拖拽幽灵（batch-6，audit-left-10；''=无）
  @State ghostX: number = 0;              // 幽灵 pill 页面坐标（构建门修正：GestureEvent 无
                                          // windowX/Y——用 Area.globalPosition 锚点+Pan offset 平移）
  @State ghostY: number = 0;
  @State ghostAnchorX: number = 0;        // 长按起拖时的格中心锚点（页面相对）
  @State ghostAnchorY: number = 0;
  private cellPos: Map<string, number[]> = new Map();   // 每格中心（globalPosition，onAreaChange 实测）
  @State closedCats: string[] = [];       // 折叠的分类（默认全展开）
  @State toolMode: string = 'select';     // ctools 状态机：select|board|text|link|fix（fix 点按即返）
  @State flows: Flow[] = [];              // 交互流镜像（AppStore.flows）
  @State showDemo: boolean = false;       // 演示模式（batch-repair 起=build 根内 z 顶条件叠层）
  @State demoBoard: string = '';          // 演示当前板
  @State demoStack: string[] = [];        // 演示返回栈（含当前板，栈底=起点页；gap-canvas-7）
  @State demoHideHot: boolean = false;    // 演示热区视觉开关（gap-canvas-8）
  @State demoInk: boolean = false;        // 演示批注开启（batch-10 spec-ink-1；开启=热区暂停、Esc 先退标注）
  @State inkStrokes: number[][][] = [];   // 已落墨迹（归一化 0–1 点列；进演示从 AppStore.ink 重放）
  @State demoDir: number = 1;             // batch-5 iss-6：演示切板方向（push=1/demoBack=-1），
                                          // 驱动 demoCover 板卡 asymmetric 进入 translate x 方向
  @State hoverFlow: string = '';          // 悬停中的连线 id（gap-canvas-6：药丸显隐/主线提亮）
  @State dw: number = 0;                  // 演示 cover 实测尺寸
  @State dh: number = 0;
  @State showInline: boolean = false;     // 双击内联改字浮层
  @State inlineVal: string = '';
  @State inlineX: number = 0;             // 内容坐标（flow Stack 同系）
  @State inlineY: number = 0;
  @State toastMsg: string = '';           // 最小 toast（gap-global-2 完整体系归 batch-6）
  @State rightTab: string = 'insp';       // 右栏互斥 tab：insp=属性 | track=Agent 追踪（gap-right-1）
  @State showRecentList: boolean = false; // proj-card 可折叠最近列表（batch-5 gap-detail-16，默认折叠）
  @State declText: string = '';           // MBT 源码视图文本（canonical 展示形态，gap-topbar-3/
                                          // gap-mbt-1：展示=toCanonicalText 投影；.ddp 持久化仍 interim serialize）
                                          // batch-4（gap-mbt-11）：declDirty 清空编辑器门随草稿态移除——
                                          // 应用路径（JSON.parse→restore）已删，视图恒只读重灌
  @State draftX: string = '';             // 数值草稿态（gap-right-2：消除 onChange 直写被 sync 重建丢字）
  @State draftY: string = '';
  @State draftW: string = '';
  @State draftH: string = '';
  @State draftFontSize: string = '';
  @State draftRadius: string = '';
  @State draftOp: string = '';            // batch-5（audit-right-8）：0-1 口径（桌面 step 0.1 min 0）
  @State draftText: string = '';          // batch-5（audit-right-7）：提交模型统一草稿+应用
  @State draftFill: string = '';
  @State draftColor: string = '';
  @State draftStroke: string = '';
  @State draftStrokeW: string = '';
  @State draftGap: string = '';
  @State draftPad: string = '';
  @State expandedStep: string = '';       // track 步骤展开态（batch-5，audit-right-10：键=步骤 key）
  @State bindTrigger: string = 'tap';     // 绑定区待提交触发器
  @State bindAction: string = 'navigate_to';
  @State bindTarget: string = '';         // navigate_to=boardId / show_toast=文案
  @State stateName: string = '';          // 状态定义输入
  @State agentSteps: AgentStep[] = [];    // 实时轨迹步骤（gap-right-4）
  @State pending: ClarifyPending | null = null;  // 澄清挂起（gap-bottom-1）
  @State clarifyAnswer: string = '';
  @State msgExpanded: boolean = false;    // agentMsg 单行/多行展开
  @State inlineAgent: boolean = false;    // 行内 Agent 浮层（gap-right-5）
  @State iaBoard: string = '';
  @State iaLayer: string = '';
  @State iaX: number = 0;
  @State iaY: number = 0;
  @State iaInput: string = '';
  @State iaFocused: boolean = false;   // M3.6.9：输入聚焦紫态（i:268 .ap-input:focus）
  @State cfgProvider: string = 'xiaoyi';  // 设置 AI 区（gap-settings-1；batch-9 默认 xiaoyi——
                                          // 初值仅首帧兜底，aboutToAppear 经 aiConfig.load() 覆写）
  @State cfgBaseUrl: string = 'https://api.deepseek.com';
  @State cfgApiKey: string = '';
  @State cfgModel: string = '';
  @State cfgModels: string[] = [];        // 「获取模型」结果
  @State fetchBusy: boolean = false;      // 获取模型在飞守卫（batch-13）
  @State cfgThinking: string = 'auto';    // 思考等级（batch-3，audit-modal-6：off|auto|low|medium|high|max）
  @State cfgMaxSteps: number = 500;       // 步数上限（batch-3，audit-modal-6：200|500|1000|2000）
  @State cfgThinkOptions: string[] = THINK_LEVELS.map((t: ThinkLevelDef): string => t.id);
  // ↑ batch-12（spec-settings-2）：收紧后可选档位（restrictThinking 先赋选项再钳值，防静默降级）
  @State settingsTab: string = 'look';    // 设置卡双 tab：look（外观）| ai（AI 端点）
  @State exportStep: string = 'choice';   // 导出浮层两步：choice（选项卡）| pwd（密码框）
  @State capLoaded: boolean = false;      // models.json 快照已解析（能力提示刷新触发器）
  @State promptFocused: boolean = false;  // pmain 聚焦态（batch-4，audit-topbar-7：蓝边+光环）
  @State tplThumbsProbed: boolean = false;  // 模板缩略图 rawfile 探测完成（模板卡重建触发器）
  @State themeId: string = 'hmos';        // 主题：hmos|mac|win11|deep|neu|glass（batch-1，audit-modal-4；
                                          // iss-4 默认改 hmos——鸿蒙原生观感优先，与 UiPrefs.load() def 同步）
  @State themeChoice: string = 'light';   // 深/浅两档：light|dark（'system' 旧值仅 isDark 兼容残留；
                                          // gap-settings-2 → batch-1 改双档，桌面深色模式 select 同为双选项）
  @StorageProp('ddSysDark') sysDark: boolean = false;  // 系统深浅（EntryAbility onConfigurationUpdate 写入）
  @StorageProp('ddWantDdpB64') @Watch('onWantDdp') wantDdpB64: string = '';
  // ↑ batch-13：want 注入 .ddp（EntryAbility onCreate/onNewWant 写入；热启动经 @Watch、
  // 冷启动在 aboutToAppear 尾手动消费一次）
  @StorageProp('ddKeyEvt') @Watch('onKeyEvtParam') keyEvtParam: string = '';
  // ↑ r11 验收修复轮：dd_key 快捷键驱动通道（EntryAbility stashWantDdp 写入；热启动经
  // @Watch、冷启动 aboutToAppear 显式消费——同 wantDdpB64 双通道口径）
  @State inputFocused: boolean = false;   // TextInput 聚焦守卫（gap-kbd-1：聚焦时跳过编辑类键）
  @State lastOp: string = '';             // statusbar 真实回显（gap-global-2，batch-1 字段消费）
  @State lastErr: string = '';
  @State lastCmdSrc: string = '';         // 最近命令来源（batch-4，audit-topbar-8 HUMAN 态）
  @State tailRev: number = 0;             // canvas-tail rev 读数镜像（batch-4，iss-7：appStore 非
                                          // 响应式依赖，Text 直调 totalRev() 零依赖初渲 0 永不重绘；
                                          // 改经 sync() 镜像，同 lastCmdSrc 先例）
  @State toastKind: string = 'ok';        // ok | err（err 红染 4.2s）
  private dispatch: CommandDispatch = new CommandDispatch();
  private sessionPwd: string = '';        // 当前绑定项目的会话口令（仅内存，不持久化明文）
  private pwdByPath: Map<string, string> = new Map();  // 本会话内 per-path 口令映射（对齐桌面）
  private openTries: number = 0;          // 口令重试计数（上限 3，防死循环）
  private recoverJson: string = '';       // 待恢复的 autorecover 原文
  private dragBoardId: string = '';       // 标题栏拖移中的画板 id（手势簿记）
  private boardDragBase: [number, number] = [0, 0];  // 该画板拖移起点时的已有偏移
  @State pendingFromBoard: string = '';   // link 模式：已选源节点所属板（batch-4 转 @State：
                                          // linking affordance 需随选源即时重渲染）
  @State pendingFromNode: string = '';    // link 模式：已选源节点 id（同上）
  private demoFromBoard: string = '';     // 进演示前的视图（退出恢复）
  private demoFromLayer: string = '';
  // batch-4（gap-mbt-11）：declCtrl/declSelArmed 全选链路随 declMenu「⌿ 全选」移除——
  // 只读 Text+Span 形态无 TextArea 可聚焦/选择（评估留痕见 declMenu 注释）
  private inlineCtrl: TextInputController = new TextInputController();  // 内联编辑全选（gap-canvas-18：
  // controller 是 TextInputOptions 构造参数字段 text_input.d.ts:769，TextInputAttribute 无属性版——同 TextArea）
  private inlineSelArmed: boolean = false;  // 打开即全选原文：armed 置位、用后即清（防打字重选）
  private boardPanTs: number = 0;         // 标题栏拖移结束时间戳（gap-canvas-16：250ms 防误切）
  private inlineBoard: string = '';       // 内联编辑目标
  private inlineLayer: string = '';
  private toastTimer: number = -1;
  private clickGateTs: number = 0;        // 子树已消费点击的时间戳（本 SDK ClickEvent 无 stopPropagation 的替代）
  private draftLoadedFor: string = '';    // 草稿所属节点（board/layer 切换时重载）
  private lastTask: string = '';          // 最近一次指令原文（澄清 pending.task 用）
  private tabs: string[] = ['图层', 'AI 组件', '流程'];
  private modes: string[] = ['线框图', '高保真', 'MBT 源码'];
  private pchips: string[] = ['+ Web 登录页', '+ 手机登录', '+ 仪表盘', '💬 微信社交', '⚡ 自动修复'];

  aboutToAppear(): void {
    try {
      this.coreTag = coreVersion();
      const enc = ddpEncrypt('# Board\n\nselftest', 't');
      ddpDecrypt(enc, 't');
      this.coreTag += ' · ddp:ok';
    } catch (e) {
      this.coreTag = 'NAPI 异常: ' + (e as Error).message;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    this.dispatch.setContext(ctx);
    projectRegistry.init(ctx);
    aiConfig.init(ctx);
    agentService.attachDispatch(this.dispatch);
    // batch-9 cur-5：命令行执行器注入——AgentService 命令流（extractOps 产物）逐行回调
    agentService.attachLineExec((line: string): LineExecOutcome => { return this.execCommandLine(line); });
    agentService.attachDocFlush((docB64: string): void => {
      // M3.6.7 会话 canonical 回灌（活进度）：merge + 引擎 SVG 刷新 + sync（UI 线程轻量）
      try {
        const dec = new util.Base64Helper().decodeSync(docB64);
        const canonical = util.TextDecoder.create('utf-8').decodeToString(dec);
        const parsed = parseMbtDoc(canonical);
        if (parsed.ok) {
          appStore.docEpoch += 1;   // R10 缓解：mergeCanonical rev=0 不再依赖偶然再键——每轮强制板卡重建（线框活进度）
          appStore.mergeCanonical(parsed);
          this.lastCanonicalB64 = docB64;   // M3.6.8 review-F3：锚点随会话推进（hifi SVG/⌘Z 数据源）
          this.refreshEngineSvg();
          this.sync();
        }
      } catch (e) { /* 单轮回灌失败不阻断 run（下一轮覆盖） */ }
    });
    const conf = aiConfig.load();
    this.cfgProvider = conf.provider;
    this.cfgBaseUrl = conf.baseUrl;
    this.cfgApiKey = conf.apiKey;
    this.cfgModel = conf.model;
    this.cfgThinking = conf.thinkingLevel;   // batch-3，audit-modal-6：思考等级/步数持久化回载
    this.cfgMaxSteps = conf.maxSteps;
    this.restrictThinking();   // batch-12：回载后按快照收紧（快照未到先全档，到档补钳）
    uiPrefs.init(ctx);
    const look: UiLook = uiPrefs.load();
    this.themeId = look.themeId;      // 杀进程重启后主题与深浅档保持（batch-1，audit-modal-4）
    this.themeChoice = look.mode;
    this.applyColorMode();   // iss-4：应用态覆写启动默认（EntryAbility onCreate 每次重置 NOT_SET，
                             // 启动窗在本次覆写前按系统档渲染——见 applyColorMode 待验证登记）
    this.recent = projectRegistry.list();
    this.checkAutorecover(ctx);
    this.loadComps(ctx);
    this.loadCapSnapshot(ctx);   // 能力提示快照（batch-3，audit-modal-6）
    this.probeTplThumbs(ctx);    // 模板缩略图在场探测（batch-3，audit-modal-10）
    this.sync();
    this.projName = appStore.projectName;
    this.onWantDdp();   // batch-13：冷启动 want 注入消费（@StorageProp 初值已带，@Watch 只覆盖热启动）
    // 引擎探针（gap-global-3 接线，M1）：延时到首帧后——首次探测含 wasm 编译（rust-core
    // wasmtime 实例化，秒级；同步 NAPI 阻塞 UI 线程是 M1 已知代价，Promise 化归后续批次）。
    // 可用 → 设置页引擎行接真实 engineVersion、engineOk 亮灯（模板建板走引擎通路）；
    // 不可用 → engineTag 保持现状文案（诚实降级，不假装），原因已在 Dispatch console.error。
    setTimeout((): void => {
      const probeArgs: Record<string, Object> = {};
      this.dispatch.dispatch('engine_status', probeArgs).then((v: Object | null): void => {
        if (v === null) return;
        const r = v as EngineStatusReply;
        if (r.available === true && typeof r.tag === 'string' && r.tag !== '') {
          this.engineTag = r.tag;
          this.engineOk = true;
        }
      });
    }, 800);
    this.onKeyEvtParam();   // r11：冷启动 dd_key 通道消费（同上口径，@Watch 只覆盖热启动）
    agentService.probe().then((ok: boolean): void => {
      // r11 去兜底化（gap-r11-3）：不可用态措辞中性化；本串现无文本呈现面（batch-1 已删
      // Agent 执行者块），唯一消费点顶栏徽章 includes('就绪') 只读取色——就绪态串不变
      this.xiaoyiState = ok ? '小艺 · 就绪' : '小艺 · 暂不可用';
    });
  }

  /** want 注入 .ddp 消费（batch-13，验收可测性通道）：EntryAbility 把 `--ps ddp_b64 <base64>`
   * 暂存 AppStorage；此处解码落沙箱文件后走既有 openVia 链（DDP2 免密试链→finishOpen→
   * canonical 解析/损坏诚实 toast 全复用）。一次性消费（清键防重入）。 */
  private onWantDdp(): void {
    const b64 = this.wantDdpB64;
    if (b64 === '') return;
    AppStorage.setOrCreate('ddWantDdpB64', '');
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const p = ctx.filesDir + '/ddp-external.ddp';
      const helper = new util.Base64Helper();
      const bytes = helper.decodeSync(b64);
      hilog.info(0x0000, 'ddWant', 'consume bytes=%{public}d -> %{public}s', bytes.length, p);
      const f = fs.openSync(p, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, bytes.buffer as ArrayBuffer);
      fs.closeSync(f);
      this.openVia(p, '');
    } catch (e) {
      const msg: string = '外部打开失败：' + (e as Error).message;
      this.agentMsg = msg;
      appStore.logCmd('HUMAN', msg, false);
      this.sync();
    }
  }

  /** dd_key 快捷键驱动通道消费（r11 验收修复轮，batch-13 ddp_b64 同构）：模拟器 uitest/
   * uinput 注入不携带修饰态——Ctrl+/（含对照 ⇧E）组合键全灭，物理键路径归 2in1 真机
   * （r2 §六.6/r3 通道限制先例）；本通道经 `aa start --ps dd_key slash` 驱动与 onPlanKey
   * Ctrl+/ 分支完全相同的分支体（openKeymapSettings），使「打开设置后
   * settingsTab==='look'」在模拟器端到端可断言。值格式 'slash'|'comma'（EntryAbility 已拼
   * '#epoch' nonce 强制 @Watch 同值重触发）。一次性消费（清键防重入），正常启动零影响。 */
  private onKeyEvtParam(): void {
    const raw = this.keyEvtParam;
    if (raw === '') return;
    AppStorage.setOrCreate('ddKeyEvt', '');
    const hash: number = raw.indexOf('#');
    const evt: string = hash >= 0 ? raw.substring(0, hash) : raw;
    if (evt === 'slash') {
      this.openKeymapSettings();   // 与 onPlanKey Ctrl+/ 分支同体
      hilog.info(0x0000, 'ddWant', 'dd_key slash -> settings look');
    } else if (evt === 'comma') {
      this.showSettings = true;   // 与 onPlanKey Ctrl+, 分支同体（保持当前 tab）
      hilog.info(0x0000, 'ddWant', 'dd_key comma -> settings keep tab');
    } else if (evt === 'z') {
      this.undoOp();   // M3：模拟器注入带不了修饰键——⌘Z 语义经 dd_key 通道直达 undoOp
      hilog.info(0x0000, 'ddWant', 'dd_key z -> undoOp');
    } else if (evt === 'Z') {
      this.redoOp();
      hilog.info(0x0000, 'ddWant', 'dd_key Z -> redoOp');
    } else {
      hilog.info(0x0000, 'ddWant', 'dd_key unknown %{public}s', evt);
    }
  }

  private sync(): void {
    this.boards = appStore.boards.slice();
    // 诊断埋点（batch-repair-2）：键成分与板数随每次同步留痕。r4 起 rev 入板级 ForEach 键
    // （BoardFrame/@ObjectLink 摘除，见文件头说明），此日志是键跳变时序的对照面
    hilog.info(0x0000, 'ddSync', 'boards=%{public}d epoch=%{public}d selBoard=%{public}s selLayer=%{public}s',
      this.boards.length, appStore.docEpoch, this.selBoard, this.selLayer);
    this.timeline = appStore.timeline.slice();
    this.flows = appStore.flows.slice();
    this.dirty = appStore.dirty;
    this.lastOp = appStore.lastOp;
    this.lastErr = appStore.lastErr;
    this.lastCmdSrc = appStore.lastCmdSrc;   // batch-4，audit-topbar-8 镜像
    this.tailRev = appStore.totalRev();   // batch-4，iss-7：rev 读数镜像（sync 全路径调用，随 op 刷新；
                                          // undo 经 rehydrateBoards 带回快照 rev，读数同步回退）
    // M3：引擎会话下撤销/重做走 session_history（栈在引擎），本地快照栈仅引擎离线兜底
    this.canUndo = (this.engineOk && this.lastCanonicalB64 !== '') || appStore.undoStack.length > 0;
    this.canRedo = (this.engineOk && this.lastCanonicalB64 !== '') || appStore.redoStack.length > 0;
    if (this.selBoard !== '' && this.curBoard() === null) {
      this.selBoard = '';
      this.selLayer = '';
    }
    if (this.selBoard === '' && this.boards.length > 0) {
      this.selBoard = this.boards[0].id;   // 永远有 active 板（非 active 0.82 系数/0.94 透明度区分主次）
    }
    if (this.selLayer !== '' && this.curLayer() === null) {
      this.selLayer = '';
    }
    if (this.modeIdx === 2) {
      this.declText = appStore.toCanonicalText();   // 源码视图随文档实时刷新（canonical 展示投影，gap-mbt-1
                                                    // ——持久化 serialize 不动；batch-4 gap-mbt-11：declDirty
                                                    // 门移除，画布→源码单向可信恒开）
    }
    const cl = this.curLayer();
    if (cl === null && this.selLayer === '') {
      this.draftLoadedFor = '';   // 空选即作废草稿归属：重选同一节点必重载（防切板/删除/undo 后残值）
    }
    if (cl !== null && this.draftLoadedFor !== this.selBoard + '/' + this.selLayer) {
      this.loadDrafts(cl);   // 选中节点切换时重载数值草稿
    }
  }

  private curBoard(): Board | null {
    return this.boards.find((b: Board): boolean => b.id === this.selBoard) ?? null;
  }

  private curLayer(): LayerNode | null {
    const b = this.curBoard();
    return b?.layers.find((l: LayerNode): boolean => l.id === this.selLayer) ?? null;
  }

  private addTpl(tid: string): void {
    const def = TPLS.find((t: TplDef): boolean => t.tid === tid);
    if (!def) return;
    this.addTplViaEngine(tid, def);
  }

  /** 本地建板路径（引擎通路的保底，行为=接线前 addTpl 逐字保留——回退不是删功能）。 */
  private addTplLocal(tid: string, def: TplDef): Board {
    const b = appStore.addBoard(tid, def.name, def.kind, 'TEMPLATE');
    this.sync();
    this.selBoard = b.id;
    this.selLayer = '';
    return b;
  }

  /**
   * 模板建板引擎通路（gap-global-3 接线，M1）：空项目首板走真实引擎人类门
   * `template <tid> <id> <w> <h>`——种子文档（__seed 占位板，与桌面 seed_doc 逐字同构）
   * 承载 op（引擎要求文档至少一个视觉块），成功后链式 `delete-artboard __seed` 清占位，
   * 回传 canonical 经既有导入路径（parseMbtDoc → restoreCanonical）回灌 AppStore，
   * 命令流以 ENGINE 来源留痕。任何一步失败（导出缺失/门拒绝/解析失败/新板不在场）→
   * console.error 原因 + 现有本地路径兜底（引擎尝试失败在时间线诚实留 ✗ 记录）。
   * M1 边界：仅空项目走引擎——非空项目的整文档替换会丢弃 AppStore 独有态
   * （interactions/states/ink 无 canonical 承载，有损回灌），完整回灌归后续迭代；
   * 命令流执行器（execCommandLine）的 template 分支同批暂留本地路径。
   */
  private addTplViaEngine(tid: string, def: TplDef): void {
    if (!this.engineOk || appStore.boards.length > 0) {
      this.addTplLocal(tid, def);
      return;
    }
    const size = TplSize.of(def.kind);
    const newId = `eng${Date.now().toString(36)}`;   // ASCII snake_case（引擎节点/画板 id 约定）
    const op = `template ${tid} ${newId} ${size[0]} ${size[1]}`;
    const seed = this.engineSeedDoc();
    const probeArgs: Record<string, Object> = { 'docB64': this.utf8B64(seed), 'op': op };
    this.dispatch.dispatch('engine_apply_human_op', probeArgs).then((v: Object | null): void => {
      const failLocal = (why: string): void => {
        console.error(`[engine] template op 回退本地: ${why}`);
        appStore.logCmd('ENGINE', `${op}（引擎失败，本地兜底）`, false);
        this.addTplLocal(tid, def);
      };
      if (v === null) { failLocal('null reply'); return; }
      const r1 = v as EngineApplyReply;
      if (typeof r1.error === 'string' && r1.error !== '') { failLocal(r1.error); return; }
      if (r1.ok !== true || typeof r1.mbt_b64 !== 'string' || r1.mbt_b64 === '') {
        failLocal(`gate_reject:${JSON.stringify(r1).slice(0, 120)}`);
        return;
      }
      // 链式第二 op：清种子占位板（canonical1 的 mbt_b64 即下次调用的 docB64——session 缓存按键前移命中）
      const op2Args: Record<string, Object> = { 'docB64': r1.mbt_b64, 'op': `delete-artboard __seed` };
      this.dispatch.dispatch('engine_apply_human_op', op2Args).then((v2: Object | null): void => {
        if (v2 === null) { failLocal('null reply on cleanup'); return; }
        const r2 = v2 as EngineApplyReply;
        if (typeof r2.error === 'string' && r2.error !== '') { failLocal(r2.error); return; }
        if (r2.ok !== true || typeof r2.mbt_b64 !== 'string' || r2.mbt_b64 === '') {
          failLocal(`gate_reject_cleanup:${JSON.stringify(r2).slice(0, 120)}`);
          return;
        }
        // canonical 回灌既有导入路径（与打开 canonical 文件同一链路）
        let canonical = '';
        try {
          const dec = new util.Base64Helper().decodeSync(r2.mbt_b64);
          canonical = util.TextDecoder.create('utf-8').decodeToString(dec);
        } catch (e) {
          failLocal(`b64_decode:${(e as Error).message}`);
          return;
        }
        const parsed = parseMbtDoc(canonical);
        if (!parsed.ok || !appStore.restoreCanonical(parsed)) {
          failLocal('canonical_parse_or_restore_failed');
          return;
        }
        const landed = appStore.boards.some((b: Board): boolean => b.id === newId);
        if (!landed) {
          failLocal('new_board_missing_in_canonical');
          return;
        }
        appStore.logCmd('ENGINE', op, true, appStore.docRev);
        this.lastCanonicalB64 = r2.mbt_b64;   // M2：会话锚回填——后续命令流 op 投影即从本文档起
        this.histTouch(r2.mbt_b64, newId);   // M3：历史 init 全板 + commit 新板
        this.refreshEngineSvg();             // M3：引擎 SVG 渲染层首刷
        this.sync();
        this.selBoard = newId;
        this.selLayer = '';
      });
    });
  }

  /** 引擎种子文档（__seed 占位板）：与 rust-core/src/engine.rs seed_doc / 桌面
   * agent.rs::seed_doc / frontend seedDoc 逐字同构——引擎要求文档至少一个视觉块，
   * 空(op)项目由它引导，模板 op 成功后链式删除。 */
  private engineSeedDoc(): string {
    const L: string[] = [];
    L.push('---');
    L.push('moonviz:');
    L.push('  format: visual-document');
    L.push('  revision: 1');
    L.push('  entry: __seed');
    L.push('---');
    L.push('');
    L.push('# __seed');
    L.push('');
    L.push('<!-- moonviz:artboard __seed -->');
    L.push('```mbt');
    L.push('fn visual___seed() -> @decl.Prototype {');
    L.push('  let page = @decl.prototype(name="__seed", width=390.0, height=844.0)');
    L.push('  page');
    L.push('}');
    L.push('```');
    return L.join('\n') + '\n';
  }

  private usePrompt(t: string): void {
    this.prompt = '';
    // pchip 语义 = 填充并执行（对齐 usePrompt）
    this.prompt = t;
    this.runPrompt();
  }

  private runPrompt(): void {
    const t = this.prompt.trim();
    if (!t || this.busy) return;
    const mbt = `画布 ${this.boards.length} 板；当前 ${this.curBoard()?.name ?? '无'}`;
    this.runAgent(t, mbt);
    this.prompt = '';
  }

  /** 澄清续轮入口（batch-5，audit-right-10）：不清 agentSteps，仅追加 ↳ 回答行（runAgent 续轮旁路）。 */
  private runPromptFollowup(answer: string): void {
    const t = this.prompt.trim();
    if (!t || this.busy) return;
    const mbt = `画布 ${this.boards.length} 板；当前 ${this.curBoard()?.name ?? '无'}`;
    this.pushStep({ kind: 'instruction', label: `↳ 回答：${answer}`, detail: '', ms: 0, ok: true });
    this.runAgent(t, mbt, true);
    this.prompt = '';
  }

  /**
   * Agent 运行统一链（指令条与行内 Agent 共用）：轨迹推送、澄清挂起、done/failed 汇总。
   * 用户发新指令即清 pending（对齐桌面失败路径防污染）。
   * batch-5（audit-right-10）：isFollowup=澄清续轮旁路——续轮不重置 agentSteps（原卡追加），
   * 首轮照旧清空并起手 push ▸ 指令步骤；续轮由 sendClarify push「↳ 回答：」行。
   */
  private runAgent(task: string, mbt: string, isFollowup: boolean = false): void {
    this.busy = true;
    this.rightTab = 'track';   // agent run 自动切追踪页（对齐通用版，gap-right-1）
    this.agentMsg = '';
    // M3.6.8 review-F2：run 起点单次撤销快照（整个 run 一个撤销边界；续轮不重复压栈）
    if (!isFollowup) {
      appStore.pushUndoExternal();
    }
    if (isFollowup) {
      // 续轮：保留此前步骤不清空；「↳ 回答：」行由调用方（runPromptFollowup）push
    } else {
      this.agentSteps = [];
      this.pushStep({ kind: 'instruction', label: task, detail: '', ms: 0, ok: true });   // ▸ 指令行
    }
    this.msgExpanded = false;
    this.pending = null;
    this.lastTask = task;
    const t0 = Date.now();
    agentService.run(task, mbt,
      // M2（gap-global-3）：意图三闭包改道 execCommandLine——模板/改色/改文字统一经
      // 命令流路由（engineOk 时走真实引擎人类门 + canonical 合并回灌；否则本地分支），
      // 杜绝意图链旁路引擎。
      (tid: string): boolean => { return this.execCommandLine(`template ${tid}`).ok; },
      (text: string): boolean => { return this.applyTextIntent(text); },
      (color: string): boolean => {
        const b = this.curBoard();
        const l = this.intentTargetLayer(b);
        if (b === null || l === null) return false;
        return this.execCommandLine(`set ${b.id} ${l.id} color ${color}`).ok;
      },
      (ev: AgentStep): void => { this.pushStep(ev); },
      { thinkingLevel: this.cfgThinking, maxSteps: this.cfgMaxSteps },   // batch-3 透传（audit-modal-6）
      this.utf8B64(appStore.toCanonicalText())   // M3.6.7：会话初始 canonical（Rust 侧种子引导兜底）
    ).then((r) => {
      this.agentMsg = r.reply;
      if (r.ok && !r.executed) {
        this.pending = { task: this.lastTask, question: r.reply };   // 澄清挂起（全文不截断）
      }
      // done 绿胶囊文案（batch-5，audit-right-11）：消费 AgentOutcome.ops——
      // 「运行完成 · N op(s) · 画板 N」；清理闲置无引擎不显（interim 口径见 AgentOutcome.ops 登记）
      const opWord = r.ops === 1 ? 'op' : 'ops';
      this.pushStep({
        kind: r.ok ? 'done' : 'failed',
        label: r.ok ? `运行完成 · ${r.ops} ${opWord} · 画板 ${appStore.boardCount()}` : '失败',
        detail: r.ok ? (r.executed ? '' : '澄清待回答') : r.reply.slice(0, 60),
        ms: Date.now() - t0,
        ok: r.ok
      });
      this.sync();
      this.busy = false;
    }).catch((e: Error): void => {
      // review-m37 R13：run 链异常曾致 busy 永久锁——兜底落轨迹并解锁
      this.pushStep({ kind: 'failed', label: '失败', detail: (e as Error).message.slice(0, 60), ms: Date.now() - t0, ok: false });
      this.agentMsg = `运行异常：${(e as Error).message.slice(0, 60)}`;
      this.busy = false;
      this.sync();
    });
  }

  private pushStep(ev: AgentStep): void {
    this.agentSteps.push(ev);
    if (this.agentSteps.length > 40) this.agentSteps.shift();
  }

  /** 命令行执行器（batch-9 cur-5，AgentService.attachLineExec 注入）：命令流逐行 →
   * AppStore 支持子集。支持 template/create/text/set/move/delete/delete-artboard/flow；
   * list/lint 检视类与其余动词诚实返回不执行（计数进回复与轨迹）。
   * 登记对账差异：template 的显式画板 id/宽高被 AppStore 忽略（addBoard 生成 id、尺寸走
   * TplSize.of(kind)，AppStore.ets:669-680 不接受显式宽高）——命令行参数与落盘 id 的
   * 差异以回执 note 呈现实际板 id；move 为相对位移 dx/dy（与 AppStore.moveLayer 同语义）。 */
  /** M2 引擎 op 翻译（gap-global-3，词表=SKILL.md）：命令行 → 引擎人类门 op。
   * 返回 null = 不可引擎路由（本地分支处理，含参数校验失败——本地错误注记更友好）。
   * 键映射（engine update 29 键）：color→text_color、fontSize→font_size、strokeWidth→
   * stroke_width、widthMode→width_mode、bold→weight(700/400)；text 恒带引号（转义先
   * 反斜杠后引号）；x/y 不在 update 键面 → set x/y 与 move 一律翻译为绝对坐标
   * `move <ab> <node> <x> <y>`（桌面 i:2174 同构：当前+位移钳 ≥0）。 */
  private engineOpFor(parts: string[]): string | null {
    const verb = (parts[0] ?? '').toLowerCase();
    if (verb === 'template') {
      const key = parts[1] ?? '';
      const t = TPLS.find((x: TplDef): boolean => x.tid === key || x.name === key);
      if (!t) return null;
      const size = TplSize.of(t.kind);
      const newId = `eng${Date.now().toString(36)}`;
      this.pendingEngSel = newId;
      return `template ${t.tid} ${newId} ${size[0]} ${size[1]}`;
    }
    if (verb === 'create') {
      const w = Number(parts[2] ?? '0');
      const h = Number(parts[3] ?? '0');
      const newId = `eng${Date.now().toString(36)}`;
      this.pendingEngSel = newId;
      return `create ${newId} ${w > 0 ? w : 390} ${h > 0 ? h : 844}`;
    }
    if (verb === 'text') {
      const boardId = parts[1] ?? '';
      const layerId = parts[2] ?? '';
      let content = parts.slice(3).join(' ').trim();
      if (content.length >= 2 &&
        ((content.startsWith('"') && content.endsWith('"')) ||
          (content.startsWith('「') && content.endsWith('」')))) {
        content = content.slice(1, -1);
      }
      if (content === '') return null;
      const esc = content.split('\\').join('\\\\').split('"').join('\\"');
      const b = appStore.boards.find((x: Board): boolean => x.id === boardId);
      if (!b) return null;
      const l = b.layers.find((x: LayerNode): boolean => x.id === layerId);
      if (l) return `update ${boardId} ${layerId} text="${esc}"`;
      const engLid = `eng${Date.now().toString(36)}`;
      this.pendingEngSel = engLid;
      return `place ${boardId} body_text ${engLid} - 40 40 200 28 text="${esc}"`;
    }
    if (verb === 'set') {
      const boardId = parts[1] ?? '';
      const layerId = parts[2] ?? '';
      const key = parts[3] ?? '';
      const value = parts.slice(4).join(' ').trim();
      if (boardId === '' || layerId === '' || key === '' || value === '') return null;
      if (!SET_KEYS.includes(key)) return null;
      const b = appStore.boards.find((x: Board): boolean => x.id === boardId);
      const l = b?.layers.find((x: LayerNode): boolean => x.id === layerId);
      if (!b || !l) return null;
      if (key === 'x') {
        const nx = Math.max(0, l.style.x + Number(value));
        return `move ${boardId} ${layerId} ${nx} ${Math.max(0, l.style.y)}`;
      }
      if (key === 'y') {
        const ny = Math.max(0, l.style.y + Number(value));
        return `move ${boardId} ${layerId} ${Math.max(0, l.style.x)} ${ny}`;
      }
      if (key === 'bold') return `update ${boardId} ${layerId} weight=${value === 'true' ? '700' : '400'}`;
      if (key === 'text') {
        const esc = value.split('\\').join('\\\\').split('"').join('\\"');
        return `update ${boardId} ${layerId} text="${esc}"`;
      }
      const pairs: string[][] = [
        ['color', 'text_color'], ['fontSize', 'font_size'], ['strokeWidth', 'stroke_width'],
        ['widthMode', 'width_mode']
      ];
      let engKey = key;
      for (const pr of pairs) {
        if (pr[0] === key) {
          engKey = pr[1];
          break;
        }
      }
      return `update ${boardId} ${layerId} ${engKey}=${value}`;
    }
    if (verb === 'move') {
      const boardId = parts[1] ?? '';
      const layerId = parts[2] ?? '';
      const dx = Number(parts[3] ?? 'NaN');
      const dy = Number(parts[4] ?? 'NaN');
      if (!Number.isFinite(dx) || !Number.isFinite(dy)) return null;
      const b = appStore.boards.find((x: Board): boolean => x.id === boardId);
      const l = b?.layers.find((x: LayerNode): boolean => x.id === layerId);
      if (!b || !l) return null;
      const nx = Math.max(0, Math.round(l.style.x + dx));
      const ny = Math.max(0, Math.round(l.style.y + dy));
      return `move ${boardId} ${layerId} ${nx} ${ny}`;
    }
    if (verb === 'delete') {
      const boardId = parts[1] ?? '';
      const layerId = parts[2] ?? '';
      const b = appStore.boards.find((x: Board): boolean => x.id === boardId);
      const l = b?.layers.find((x: LayerNode): boolean => x.id === layerId);
      if (!b || !l) return null;
      return `delete ${boardId} ${layerId}`;
    }
    if (verb === 'delete-artboard') {
      const boardId = parts[1] ?? '';
      const b = appStore.boards.find((x: Board): boolean => x.id === boardId);
      if (!b) return null;
      return `delete-artboard ${boardId}`;
    }
    if (verb === 'flow') {
      const fromBoard = parts[1] ?? '';
      const fromNode = parts[2] ?? '';
      const toBoard = parts[3] ?? '';
      const fb = appStore.boards.find((x: Board): boolean => x.id === fromBoard);
      const tb = appStore.boards.find((x: Board): boolean => x.id === toBoard);
      const fn = fb?.layers.find((x: LayerNode): boolean => x.id === fromNode);
      if (!fb || !tb || !fn) return null;
      return `flow ${fromBoard} ${toBoard} ${fromNode}`;
    }
    return null;
  }

  /** M2 引擎执行链：投影当前文档（toCanonicalText——人手 inspector 编辑与 Agent op 同一
   * 事实源，无分歧）→ 引擎人类门 → canonical 合并回灌（mergeCanonical：interactions/
   * states 重挂、ink/撤销保留；回灌前 pushUndoExternal 保证 ⌘Z 可回退本 op）。乐观返回
   * outcome（agentService 同步契约）；异步失败回退 execCommandLineLocal 并在时间线诚实
   * 留 ✗ ENGINE 记录（与 M1 同构）。 */
  /** UTF-8 → base64（引擎 docB64 契约；TextEncoder 真编码，禁 charCodeAt 截断）。 */
  private utf8B64(text: string): string {
    const enc = new util.TextEncoder();
    const buf = new Uint8Array(text.length * 4 + 3);
    const r = enc.encodeInto(text, buf);
    return new util.Base64Helper().encodeToStringSync(buf.subarray(0, r.written));
  }

  /** M3 历史触碰（桌面 histEnsure+histCommit 同构）：fresh history session 逐板 init
   * （引擎按画板全局维护栈，init=确保基线）+ commit 受影响板（信封 rev 回填 docRev——
   * 时间线 ENGINE 条目读数数据源）。fire-and-forget：历史失败不阻断主链路。 */
  private histTouch(canonicalB64: string, commitBoard: string): void {
    const ids: string[] = appStore.boards.map((x: Board): string => x.id);
    for (const id of ids) {
      const a: Record<string, Object> = { 'docB64': canonicalB64, 'sub': 'init ' + id };
      this.dispatch.dispatch('engine_history', a);
    }
    if (commitBoard === '') return;
    const c: Record<string, Object> = { 'docB64': canonicalB64, 'sub': 'commit ' + commitBoard };
    this.dispatch.dispatch('engine_history', c).then((v: Object | null): void => {
      if (v === null) return;
      const r = v as EngineHistoryReply;
      if (typeof r.rev === 'number' && r.rev > 0) {
        appStore.docRev = r.rev;   // 时间线 rev 读数数据源（修 r10 起恒 0）
      }
    });
  }

  private hifiSvgOf(id: string): string {
    const h = this.hifiSvgs.find((x: HSvg): boolean => x.id === id);
    return h ? h.b64 : '';
  }

  /** M3 引擎渲染层刷新：engine_render 全板 SVG → hifiSvgs（画板 body 叠加层消费）。
   * 失败静默（渲染层缺失=回退原生渲染，不阻断）。 */
  private refreshEngineSvg(): void {
    if (!(this.engineOk && this.lastCanonicalB64 !== '')) return;
    const args: Record<string, Object> = { 'docB64': this.lastCanonicalB64 };
    this.dispatch.dispatch('engine_render', args).then((v: Object | null): void => {
      if (v === null) return;
      const r = v as EngineRenderReply;
      if (r.ok !== true || !Array.isArray(r.artboards)) return;
      const list: HSvg[] = [];
      for (const a of r.artboards) {
        if (typeof a.id === 'string' && typeof a.svg === 'string' && a.svg !== '') {
          list.push({ id: a.id, b64: this.utf8B64(a.svg) });
        }
      }
      this.hifiSvgs = list;
    });
  }

  /** M3.5 撤销路由（混合两级）：引擎会话在手先试 session_history undo（单级，引擎
   * 按板栈跨 apply 失效——上游语义，见 r12 报告 M3.5 节）；引擎报「无可撤销/未初
   * 始化」或失败 → 接续本地快照栈（pushUndoExternal 每个 engine op 前都压栈，深链
   * 完整）。两路都空 → toast。 */
  private undoOp(): void {
    if (!(this.engineOk && this.lastCanonicalB64 !== '')) {
      if (appStore.undo()) { this.sync(); }
      return;
    }
    const args: Record<string, Object> = { 'docB64': this.lastCanonicalB64, 'sub': 'undo ' + this.selBoard };
    this.dispatch.dispatch('engine_history', args).then((v: Object | null): void => {
      let engineMiss = v === null;
      if (v !== null) {
        const r = v as EngineHistoryReply;
        if (r.ok === true && typeof r.mbt === 'string' && r.mbt !== '') {
          const prev = (() => {
            try {
              const dec = new util.Base64Helper().decodeSync(this.lastCanonicalB64);
              return util.TextDecoder.create('utf-8').decodeToString(dec);
            } catch (e) { return ''; }
          })();
          if (r.mbt !== prev) {
            const parsed = parseMbtDoc(r.mbt);
            if (parsed.ok && appStore.mergeCanonical(parsed)) {
              if (typeof r.mbt_b64 === 'string' && r.mbt_b64 !== '') this.lastCanonicalB64 = r.mbt_b64;
              if (typeof r.rev === 'number' && r.rev > 0) appStore.docRev = r.rev;
              this.refreshEngineSvg();
              this.sync();
              return;
            }
          }
          engineMiss = true;   // 引擎栈空（nothing_to_undo）/canonical 未变/合并失败
        } else if (typeof r.error === 'string' && r.error.includes('not_initialized')) {
          engineMiss = true;   // 引擎按板栈已失效（apply 后未重 init 的上游语义）
        }
      }
      // 本地快照栈接续（engine op 前的 pushUndoExternal 深链）
      if (appStore.undo()) { this.sync(); } else { this.toast('没有可撤销的操作'); }
    });
  }

  /** M3.5 重做路由（undoOp 对偶）：引擎 redo 优先，空则本地快照栈接续。 */
  private redoOp(): void {
    if (!(this.engineOk && this.lastCanonicalB64 !== '')) {
      if (appStore.redo()) { this.sync(); }
      return;
    }
    const args: Record<string, Object> = { 'docB64': this.lastCanonicalB64, 'sub': 'redo ' + this.selBoard };
    this.dispatch.dispatch('engine_history', args).then((v: Object | null): void => {
      let engineMiss = v === null;
      if (v !== null) {
        const r = v as EngineHistoryReply;
        if (r.ok === true && typeof r.mbt === 'string' && r.mbt !== '') {
          const prev = (() => {
            try {
              const dec = new util.Base64Helper().decodeSync(this.lastCanonicalB64);
              return util.TextDecoder.create('utf-8').decodeToString(dec);
            } catch (e) { return ''; }
          })();
          if (r.mbt !== prev) {
            const parsed = parseMbtDoc(r.mbt);
            if (parsed.ok && appStore.mergeCanonical(parsed)) {
              if (typeof r.mbt_b64 === 'string' && r.mbt_b64 !== '') this.lastCanonicalB64 = r.mbt_b64;
              if (typeof r.rev === 'number' && r.rev > 0) appStore.docRev = r.rev;
              this.refreshEngineSvg();
              this.sync();
              return;
            }
          }
          engineMiss = true;
        } else if (typeof r.error === 'string' && r.error.includes('not_initialized')) {
          engineMiss = true;
        }
      }
      if (appStore.redo()) { this.sync(); } else { this.toast('没有可重做的操作'); }
    });
  }

  private execViaEngine(engOp: string, line: string, parts: string[]): LineExecOutcome {
    const proj = appStore.toCanonicalText();
    // UTF-8 真编码（r12 验收实测：charCodeAt & 0xff 单字节截断在投影含中文——项目名/节点
    // 文案——时产出非法 UTF-8，引擎正确拒绝 engine_doc_utf8_invalid）。
    const args: Record<string, Object> = { 'docB64': this.utf8B64(proj), 'op': engOp };
    this.dispatch.dispatch('engine_apply_human_op', args).then((v: Object | null): void => {
      const failLocal = (why: string): void => {
        console.error(`[engine] op 回退本地: ${why}`);
        appStore.logCmd('ENGINE', `${engOp}（引擎失败，本地兜底）`, false);
        this.execCommandLineLocal(line, parts);
        this.sync();
      };
      if (v === null) { failLocal('null reply'); return; }
      const r = v as EngineApplyReply;
      if (typeof r.error === 'string' && r.error !== '') { failLocal(r.error); return; }
      if (r.ok !== true || typeof r.mbt_b64 !== 'string' || r.mbt_b64 === '') {
        failLocal(`gate_reject:${JSON.stringify(r).slice(0, 120)}`);
        return;
      }
      let canonical = '';
      try {
        const dec = new util.Base64Helper().decodeSync(r.mbt_b64);
        canonical = util.TextDecoder.create('utf-8').decodeToString(dec);
      } catch (e) {
        failLocal(`b64_decode:${(e as Error).message}`);
        return;
      }
      const parsed = parseMbtDoc(canonical);
      if (!parsed.ok) { failLocal('canonical_parse_failed'); return; }
      appStore.pushUndoExternal();   // ⌘Z 语义：快照进栈在合并前（栈内容=op 前态）
      if (!appStore.mergeCanonical(parsed)) { failLocal('merge_failed'); return; }
      this.lastCanonicalB64 = r.mbt_b64;
      // M3：历史 commit（受影响板=op 目标板）+ 引擎 SVG 刷新 + docRev/时间线读数
      this.histTouch(r.mbt_b64, parts.length > 1 ? parts[1] : '');
      this.refreshEngineSvg();
      appStore.logCmd('ENGINE', engOp, true, appStore.docRev);
      if (this.pendingEngSel !== '') {
        if (appStore.boards.some((x: Board): boolean => x.id === this.pendingEngSel)) {
          this.selBoard = this.pendingEngSel;
          this.selLayer = '';
        } else {
          const cb = this.curBoard();
          if (cb !== null && cb.layers.some((x: LayerNode): boolean => x.id === this.pendingEngSel)) {
            this.selBoard = cb.id;
            this.selLayer = this.pendingEngSel;
          }
        }
        this.pendingEngSel = '';
      }
      this.sync();
    });
    return { ok: true, note: `ENGINE ${engOp}` };
  }

  private execCommandLine(line: string): LineExecOutcome {
    const parts = line.split(/\s+/);
    const verb = (parts[0] ?? '').toLowerCase();
    // M2 引擎优先路由：engineOk 且引擎会话在手（或空项目可走 M1 种子链）且动词可翻译
    // → 真实引擎人类门；否则/失败 → execCommandLineLocal（原有本地分支，零改动）。
    if (this.engineOk && verb === 'template') {
      const key = parts[1] ?? '';
      const t = TPLS.find((x: TplDef): boolean => x.tid === key || x.name === key);
      if (t && appStore.boards.length === 0 && this.lastCanonicalB64 === '') {
        this.addTplViaEngine(t.tid, t);   // M1 种子链（自含种子文档/清占位/回灌/锚回填）
        return { ok: true, note: `ENGINE template ${t.tid}` };
      }
      if (t && this.lastCanonicalB64 !== '') {
        const eng = this.engineOpFor(parts);
        if (eng !== null) return this.execViaEngine(eng, line, parts);
      }
    }
    if (this.engineOk && this.lastCanonicalB64 !== '' && verb !== 'template') {
      const eng = this.engineOpFor(parts);
      if (eng !== null) return this.execViaEngine(eng, line, parts);
    }
    return this.execCommandLineLocal(line, parts);
  }

  /** 本地命令分支（M2 前的 execCommandLine 原体，零改动——引擎失败回退与引擎不可用
   * 项目的唯一执行路径）。 */
  private execCommandLineLocal(line: string, parts: string[]): LineExecOutcome {
    const verb = (parts[0] ?? '').toLowerCase();
    if (verb === 'template') {
      const key = parts[1] ?? '';
      const t = TPLS.find((x: TplDef): boolean => x.tid === key || x.name === key);
      if (!t) return { ok: false, note: `未知模板 ${key}` };
      const b = appStore.addBoard(t.tid, t.name, t.kind, 'AGENT');
      return { ok: true, note: `+${t.name} ${b.id}` };
    }
    if (verb === 'create') {
      const w = Number(parts[2] ?? '0');
      const h = Number(parts[3] ?? '0');
      const b = appStore.addBlankBoard(w > 0 ? w : 390, h > 0 ? h : 844, 'AGENT');
      return { ok: true, note: `+空板 ${b.id}` };
    }
    if (verb === 'text') {
      const boardId = parts[1] ?? '';
      const layerId = parts[2] ?? '';
      const b = appStore.boards.find((x: Board): boolean => x.id === boardId);
      if (!b) return { ok: false, note: `画板 ${boardId} 不存在` };
      let content = parts.slice(3).join(' ').trim();
      if (content.length >= 2 &&
        ((content.startsWith('"') && content.endsWith('"')) ||
          (content.startsWith('「') && content.endsWith('」')))) {
        content = content.slice(1, -1);
      }
      if (content === '') return { ok: false, note: 'text 缺文案' };
      const l = b.layers.find((x: LayerNode): boolean => x.id === layerId);
      if (l) {
        appStore.setStyle(boardId, layerId, 'text', content);
        return { ok: true, note: `改字 ${layerId}` };
      }
      const nl = appStore.placeLayerText(boardId, 40, 40);
      if (nl === null) return { ok: false, note: '落字失败' };
      appStore.setStyle(boardId, nl.id, 'text', content);
      return { ok: true, note: `+文字 ${nl.id}` };
    }
    if (verb === 'set') {
      const boardId = parts[1] ?? '';
      const layerId = parts[2] ?? '';
      const key = parts[3] ?? '';
      const value = parts.slice(4).join(' ').trim();
      if (boardId === '' || layerId === '' || key === '' || value === '') {
        return { ok: false, note: 'set 参数不全' };
      }
      if (!SET_KEYS.includes(key)) return { ok: false, note: `不支持属性 ${key}` };
      const b = appStore.boards.find((x: Board): boolean => x.id === boardId);
      const l = b?.layers.find((x: LayerNode): boolean => x.id === layerId);
      if (!b || !l) return { ok: false, note: `${layerId} 不存在` };
      appStore.setStyle(boardId, layerId, key, value);
      return { ok: true, note: `${layerId}.${key}=${value}` };
    }
    if (verb === 'move') {
      const boardId = parts[1] ?? '';
      const layerId = parts[2] ?? '';
      const dx = Number(parts[3] ?? 'NaN');
      const dy = Number(parts[4] ?? 'NaN');
      if (!Number.isFinite(dx) || !Number.isFinite(dy)) return { ok: false, note: 'move 位移非法' };
      const b = appStore.boards.find((x: Board): boolean => x.id === boardId);
      const l = b?.layers.find((x: LayerNode): boolean => x.id === layerId);
      if (!b || !l) return { ok: false, note: `${layerId} 不存在` };
      appStore.moveLayer(boardId, layerId, dx, dy);
      return { ok: true, note: `move ${layerId} (${dx},${dy})` };
    }
    if (verb === 'delete') {
      const boardId = parts[1] ?? '';
      const layerId = parts[2] ?? '';
      const b = appStore.boards.find((x: Board): boolean => x.id === boardId);
      const l = b?.layers.find((x: LayerNode): boolean => x.id === layerId);
      if (!b || !l) return { ok: false, note: `${layerId} 不存在` };
      appStore.deleteLayer(boardId, layerId);
      return { ok: true, note: `-元素 ${layerId}` };
    }
    if (verb === 'delete-artboard') {
      const boardId = parts[1] ?? '';
      const b = appStore.boards.find((x: Board): boolean => x.id === boardId);
      if (!b) return { ok: false, note: `画板 ${boardId} 不存在` };
      appStore.removeBoard(boardId);   // 级联删流在 removeBoard 内（AppStore.ets:682-690）
      return { ok: true, note: `-画板 ${boardId}` };
    }
    if (verb === 'flow') {
      const fromBoard = parts[1] ?? '';
      const fromNode = parts[2] ?? '';
      const toBoard = parts[3] ?? '';
      const fb = appStore.boards.find((x: Board): boolean => x.id === fromBoard);
      const tb = appStore.boards.find((x: Board): boolean => x.id === toBoard);
      const fn = fb?.layers.find((x: LayerNode): boolean => x.id === fromNode);
      if (!fb || !tb || !fn) return { ok: false, note: 'flow 源/目标不存在' };
      const f = appStore.createFlow(fromBoard, fromNode, toBoard);
      if (f === null) return { ok: false, note: '重复流已存在' };
      return { ok: true, note: `flow→${toBoard}` };
    }
    if (verb === 'list' || verb === 'lint') {
      return { ok: false, note: `${verb} 检视类暂不执行` };
    }
    return { ok: false, note: `暂不支持 ${verb}` };
  }

  /** 显式改字执行（修订 1：仅显式改字句式走此链并提取目标文案；无句式匹配=不劫持，返 false）。 */
  /** 意图层目标选择（batch-9：从写死 /title|welcome/ 单层扩为兜底链）：
   * 当前选中节点 → 名称/文案关键词（title/welcome/标题）→ 首文本层。 */
  private intentTargetLayer(b: Board | null): LayerNode | null {
    if (b === null) return null;
    if (this.selLayer !== '') {
      const sel = b.layers.find((x: LayerNode): boolean => x.id === this.selLayer);
      if (sel) return sel;
    }
    const kw = b.layers.find((x: LayerNode): boolean =>
      /title|welcome|标题/.test(x.name) || /title|welcome|标题/.test(x.style.text));
    if (kw) return kw;
    const txt = b.layers.find((x: LayerNode): boolean => x.type === 'text');
    return txt ?? null;
  }

  private applyTextIntent(text: string): boolean {
    const b = this.curBoard();
    const l = this.intentTargetLayer(b);
    if (!b || !l) return false;
    const m = text.match(/(?:改成|改为|设为|设置为|换成|写作|文案[:：]|标题[:：])\s*["'「『]?([^"'」』]+)["'」』]?\s*$/);
    if (m === null || m.length < 2) return false;   // 非显式改字句式：不把整句落盘
    const content = m[1].trim();
    if (content === '') return false;
    // M2（gap-global-3）：改文字意图经命令流路由（engineOk 时走真实引擎 update text；
    // 引擎不可用/会话不在 → execCommandLineLocal 本地分支，行为不变）。
    return this.execCommandLine(`text ${b.id} ${l.id} "${content}"`).ok;
  }

  private applyColorIntent(color: string): boolean {
    const b = this.curBoard();
    const l = this.intentTargetLayer(b);
    if (!b || !l) return false;
    appStore.setStyle(b.id, l.id, 'color', color);
    this.sync();
    return true;
  }

  // ===== 澄清多轮（gap-bottom-1）=====

  private sendClarify(): void {
    const p = this.pending;
    if (!p || this.busy) return;
    const answer = this.clarifyAnswer.trim();
    if (answer === '') {
      this.toast('请输入回答');
      return;
    }
    const merged = `${p.task}\n【追问】${p.question}\n【回答】${answer}`;
    const answerLine = answer;   // 续轮轨迹行用原文（merged 太长）
    this.pending = null;
    this.clarifyAnswer = '';
    this.prompt = merged;
    this.runPromptFollowup(answerLine);
  }

  // ===== 行内 Agent（gap-right-5）=====

  private openInlineAgent(b: Board, l: LayerNode): void {
    const org = this.boardOriginStack(b);   // batch-6：Stack-local 换基（浮层 .position 在内容 Stack 内）
    const z = this.zoomOf(b);
    this.iaBoard = b.id;
    this.iaLayer = l.id;
    this.iaInput = '';
    // M3.6.9：四向钳制——X 右缘不入右栏、Y 底缘不入 dock 带（用户截图：浮层输入行
    // 被 pchips/指令条遮挡）。POP_H≈浮层实测高（head+chips+input+padding）、
    // DOCK_BAND=dock 带 106 + 底距 12 + 余量
    const POP_W = 320;
    const POP_H = 150;
    const DOCK_BAND = 130;
    this.iaX = Math.max(8, Math.min(org[0] + (l.style.x + l.style.w) * z + 6, this.cw - POP_W - 8));
    this.iaY = Math.max(8, Math.min(org[1] + l.style.y * z, this.ch - DOCK_BAND - POP_H));
    this.inlineAgent = true;
  }

  private iaContext(): string {
    const b = this.boards.find((x: Board): boolean => x.id === this.iaBoard);
    const l = b?.layers.find((x: LayerNode): boolean => x.id === this.iaLayer);
    if (!b || !l) return '';
    return `${l.id} · ${l.type} · ${b.name}`;
  }

  /** 快捷 chips：映射现有 setStyle/内联编辑链（不经 LLM）。 */
  private inlineAction(kind: string): void {
    const b = this.boards.find((x: Board): boolean => x.id === this.iaBoard);
    const l = b?.layers.find((x: LayerNode): boolean => x.id === this.iaLayer);
    if (!b || !l) {
      this.inlineAgent = false;
      return;
    }
    if (kind === 'copy') {          // 改文案：复用双击内联编辑链
      this.inlineAgent = false;
      this.startInlineEdit(b, l);
      return;
    }
    if (kind === 'color') {         // 换色：词表轮转
      const palette: string[] = [this.T().acc, this.T().danger, this.T().ok, this.T().purple, this.T().tx];
      const i = palette.indexOf(l.style.color);
      const next = palette[(i + 1) % palette.length];
      appStore.setStyle(b.id, l.id, 'color', next);
      this.inlineAgent = false;
      this.sync();
      this.toast(`颜色已换为 ${next}`);
      return;
    }
    if (kind === 'delete') {
      appStore.deleteLayer(b.id, l.id);
      this.selLayer = '';
      this.inlineAgent = false;
      this.sync();
      this.toast('已删除节点');
      return;
    }
    if (kind === 'grow') {          // 放大 1.2×
      appStore.setStyle(b.id, l.id, 'w', Math.round(l.style.w * 1.2));
      appStore.setStyle(b.id, l.id, 'h', Math.round(l.style.h * 1.2));
      this.inlineAgent = false;
      this.sync();
      this.toast('已放大 1.2×');
    }
  }

  private sendInlineAgent(): void {
    const q = this.iaInput.trim();
    if (q === '' || this.busy) return;
    const b = this.boards.find((x: Board): boolean => x.id === this.iaBoard);
    const l = b?.layers.find((x: LayerNode): boolean => x.id === this.iaLayer);
    if (!b || !l) {
      this.inlineAgent = false;
      return;
    }
    this.inlineAgent = false;
    // Target 上下文并入 mbtSummary（gap-right-5），终态走同一回灌链
    const mbt = `画布 ${this.boards.length} 板；当前 ${b.name}；` +
      `Target: ${b.id}/${l.id}(${l.type}) 名称 ${l.name}，文本「${l.style.text}」颜色 ${l.style.color}`;
    this.runAgent(q, mbt);
  }

  // ===== 设置 AI 区（gap-settings-1）=====

  /** 服务商组（batch-4 dd-menu-preset）：PRESETS 15 条目同序拆三组——端侧=[xiaoyi]、
   * 云端=[deepseek…stepfun-plan 13 项]、自定义=[custom]（r9-sweep 写「14 预设」系其
   * 计数误差，以代码 15 条为准）。选中态由 '✓ '+name 文本前缀（旧 MenuElement 形态）
   * 改行内样式（selected: accSoft+✓列+600，ddMenuRow 原语自带）；action 维持
   * applyProvider（batch-12 槽位切换语义随迁）。 */
  private presetMenuGroups(): Array<DdMenuGroup> {
    const edge: DdMenuGroup = { title: '端侧', items: [] };
    const cloud: DdMenuGroup = { title: '云端', items: [] };
    const custom: DdMenuGroup = { title: '自定义', items: [] };
    for (const p of PRESETS) {
      const g: DdMenuGroup = p.id === 'xiaoyi' ? edge : (p.id === 'custom' ? custom : cloud);
      g.items.push({
        label: p.name,
        kbd: '',
        selected: this.cfgProvider === p.id,
        danger: false,
        disabled: false,
        action: (): void => { this.applyProvider(p.id); }   // batch-12：槽位切换语义
      });
    }
    return [edge, cloud, custom];
  }

  /** 服务商面板：232 宽三组（menuTitle 分组头+组间 menuDivider 原语自带）。 */
  @Builder
  presetMenuPanel() {
    this.ddMenuPanel(232, this.presetMenuGroups())
  }

  /** 思考档位收紧（batch-12，spec-settings-2 行为内核）：按 rawfile/models.json 快照
   * reasoning_options 收紧——effort 型→auto+实测档（glm-5.3=['low','high','max']→
   * auto/low/high/max）、仅 toggle 型→auto/off（glm-5 类）、双型并存→auto/off+实测档
   * （deepseek-v4/kimi-k3）；minimax-anthropic / minimax-anthropic-intl 两预设（Anthropic
   * 协议 thinking 语义独立）不收紧；快照未收录/空 → 全档。恢复顺序=先赋选项列表再钳
   * 当前值（防静默降级，对齐桌面 restoreThinkingOptions）；收紧结果经 cfgThinking 随
   * saveAiConf 写回 AiConf.thinkingLevel。 */
  private restrictThinking(): void {
    let options: string[] = THINK_LEVELS.map((t: ThinkLevelDef): string => t.id);
    if (this.cfgProvider !== 'minimax-anthropic' && this.cfgProvider !== 'minimax-anthropic-intl') {
      const key = this.cfgModel.trim();
      const cap = this.capByModel.get(key) ?? this.capByModel.get(key.toLowerCase());
      if (cap !== undefined && (cap.reasoningEffort.length > 0 || cap.reasoningToggle)) {
        options = ['auto'];
        if (cap.reasoningToggle) {
          options.push('off');
        }
        for (const v of cap.reasoningEffort) {
          if (!options.includes(v)) {
            options.push(v);
          }
        }
      }
    }
    const joined = options.join(',');
    if (joined !== this.cfgThinkOptions.join(',')) {
      this.cfgThinkOptions = options;   // 先渲染收紧档（值不变不重赋——防设置面板无谓重建吞点击，
                                        // r8 观察到 GLM 档 Select 点击未展开的缓解项）
    }
    if (!options.includes(this.cfgThinking)) {
      this.cfgThinking = 'auto';      // 再钳值（无静默降级：非法值显式回 auto）
    }
  }

  private thinkLabel(id: string): string {
    const t = THINK_LEVELS.find((x: ThinkLevelDef): boolean => x.id === id);
    return t !== undefined ? t.label : id;
  }

  private stepLabel(steps: number): string {
    const s = STEP_CAPS.find((x: StepCapDef): boolean => x.steps === steps);
    return s !== undefined ? s.label : `${steps} 步`;
  }

  private pickModel(m: string): void {
    if (m === '') return;
    this.cfgModel = m;
    this.restrictThinking();   // 选择即生效：档位随模型收紧
  }

  private normUrl(u: string): string {
    return u.trim().replace(/\/+$/, '').replace(/\/v1$/, '');   // 剥尾 /v1 归一
  }

  /** Base URL 反查回显 provider（batch-12）：剥尾 /v1 归一后与 PRESETS 比对；positive
   * 匹配即切槽标记回显（不覆盖表单——URL 已是用户所粘）；fallbackCustom=true 时对不上
   * 显 custom（仅失焦时机调用，防逐字符 onChange 误翻）。 */
  private detectProviderFromUrl(fallbackCustom: boolean): void {
    const u = this.normUrl(this.cfgBaseUrl);
    if (u === '') return;
    for (const p of PRESETS) {
      if (p.id === 'xiaoyi' || p.id === 'custom' || p.baseUrl === '') continue;
      if (this.normUrl(p.baseUrl) === u) {
        if (this.cfgProvider !== p.id) {
          this.cfgProvider = p.id;
          this.restrictThinking();
        }
        return;
      }
    }
    if (fallbackCustom && this.cfgProvider !== 'xiaoyi' && this.cfgProvider !== 'custom') {
      this.cfgProvider = 'custom';
    }
  }

  /** 表单当前内容存回切走前槽位（batch-12 槽位并存）；xiaoyi 槽位 URL/Key/Model 恒空。 */
  private stashCurrentSlot(): void {
    const isXy = this.cfgProvider === 'xiaoyi';
    const conf: AiConf = {
      provider: this.cfgProvider,
      baseUrl: isXy ? '' : this.cfgBaseUrl.trim(),
      apiKey: isXy ? '' : this.cfgApiKey,
      model: isXy ? '' : this.cfgModel.trim(),
      thinkingLevel: this.cfgThinking,
      maxSteps: this.cfgMaxSteps
    };
    aiConfig.saveSlot(this.cfgProvider, conf);
  }

  /** 服务商切换（batch-12 槽位并存，spec-settings-2）：表单内容存回切走前槽位 → 载入
   * 目标槽位（未配置过用 PRESETS 默认 baseUrl/model，apiKey 留空）→ setActive（选择即
   * 生效）→ 档位随目标槽模型收紧。 */
  private applyProvider(id: string): void {
    if (id === this.cfgProvider) return;
    this.stashCurrentSlot();
    const p = PRESETS.find((x: ProviderPreset): boolean => x.id === id);
    if (p === undefined) return;
    this.cfgProvider = p.id;
    const slot = aiConfig.loadSlot(id);
    if (slot.baseUrl !== '' || slot.apiKey !== '' || slot.model !== '') {
      this.cfgBaseUrl = slot.baseUrl;   // 已配置过：整槽回装（Key 不丢）
      this.cfgApiKey = slot.apiKey;
      this.cfgModel = slot.model;
      this.cfgThinking = slot.thinkingLevel;
      this.cfgMaxSteps = slot.maxSteps;
    } else {
      this.cfgBaseUrl = p.baseUrl;      // 未配置过：PRESETS 默认 baseUrl/model（:877-892 表）
      this.cfgApiKey = '';
      this.cfgModel = p.model;
    }
    // batch-13（验收缓解）：模型列表按端点归属——换槽后旧 provider 列表陈旧，清空重取
    //（防 Select 误显旧端点模型；r8 观察到 GLM 档下拉未展开疑与陈旧列表/重建竞态相关）
    this.cfgModels = [];
    aiConfig.setActive(id);
    this.restrictThinking();
    this.toast(`已选预设 ${p.name}`);
  }

  /** 保存 AI 配置并关闭（batch-3，audit-modal-6：反馈=关闭本身，不 toast——对齐 i:4177；
   * 校验失败仍 toast（那是错误反馈，非成功反馈）。取消=不保存直接关闭。 */
  private saveAiConf(): void {
    if (this.cfgProvider !== 'xiaoyi' && this.cfgBaseUrl.trim() === '') {
      // batch-9：小艺档免 baseUrl，跳过必填校验（其余预设仍要求端点）
      this.toast('请填写 BaseUrl 或选择预设');
      return;
    }
    const conf: AiConf = {
      provider: this.cfgProvider,
      baseUrl: this.cfgBaseUrl.trim(),
      apiKey: this.cfgApiKey,
      model: this.cfgModel.trim(),
      thinkingLevel: this.cfgThinking,
      maxSteps: this.cfgMaxSteps
    };
    aiConfig.save(conf);
    this.showSettings = false;
  }

  private fetchModels(): void {
    if (this.cfgBaseUrl.trim() === '') {
      this.toast('请先填写 BaseUrl');
      return;
    }
    if (this.fetchBusy) {
      this.toast('获取中，请稍候');   // batch-13：在飞守卫（防「挂起态」期间重复请求堆积）
      return;
    }
    this.fetchBusy = true;
    const payload: Record<string, Object> = { 'mode': 'models', 'baseUrl': this.cfgBaseUrl.trim() };
    const args: Record<string, Object> = { 'apiKey': this.cfgApiKey, 'payload': JSON.stringify(payload) };
    this.dispatch.dispatch('invoke_fx_sdk', args).then((v: Object | null): void => {
      this.fetchBusy = false;
      if (v === null) {
        this.toast('获取模型失败');
        return;
      }
      const r = v as ModelsOutcome;
      if (Array.isArray(r.models) && r.models.length > 0) {
        this.cfgModels = r.models;
        this.toast(r.source === 'snapshot' ? `已回落本地快照（${r.models.length} 个）` : `获取到 ${r.models.length} 个模型`);
      } else {
        this.toast('获取模型失败：' + String(r.error ?? '空列表'));
      }
    }).catch((e: Error): void => {
      this.fetchBusy = false;
      this.toast('获取模型失败：' + e.message);
    });
  }

  // ===== 文件生命周期（gap-topbar-1 / gap-topbar-2 / gap-global-4）=====

  private baseName(p: string): string {
    let s = p;
    const i = s.lastIndexOf('/');
    if (i >= 0) s = s.substring(i + 1);
    // URL 解码（batch-5，gap-detail-17，r2 §六.5/4a 实录「%E6%9C%AA…」形态）：
    // DocumentViewPicker 返回 percent 编码路径——末段解码显示中文名；非法序列兜底原串。
    // finishOpen/saveTo 全走本函数，改此一处全链生效。
    try {
      s = decodeURIComponent(s);
    } catch (e) { /* 非法 percent 序列：保留原串 */ }
    if (s.toLowerCase().endsWith('.ddp')) s = s.substring(0, s.length - 4);
    return s;
  }

  /** 相对时间（batch-3，audit-modal-11）：最近行第三列 path → 分/时/天档；
   * >30 天粗化为月档（注册表容量 10、高频使用场景月档极少见，登记）。 */
  private relTime(ts: number): string {
    const d = Date.now() - ts;
    if (d < 60000) return '刚刚';
    if (d < 3600000) return `${Math.floor(d / 60000)} 分钟前`;
    if (d < 86400000) return `${Math.floor(d / 3600000)} 小时前`;
    if (d < 2592000000) return `${Math.floor(d / 86400000)} 天前`;
    return `${Math.floor(d / 2592000000)} 个月前`;
  }

  private utf8ToB64(s: string): string {
    const enc = new util.TextEncoder();
    return new util.Base64Helper().encodeToStringSync(enc.encodeInto(s));
  }

  /** 脏确认（复用 Dispatch.confirm_discard 红染框）；放弃更改时执行 doAct。 */
  private confirmThen(doAct: () => void): void {
    if (!appStore.dirty) {
      doAct();
      return;
    }
    const noArgs: Record<string, Object> = {};
    this.dispatch.dispatch('confirm_discard', noArgs).then((v: Object | null): void => {
      if (v === true) doAct();   // true = 放弃更改
    });
  }

  /** 新建：dirty 确认后清空回欢迎态（验收 1）。 */
  private actNew(): void {
    if (this.busy) return;   // agentBusy 在飞门（对齐桌面）
    this.confirmThen((): void => {
      appStore.newProject();
      this.sessionPwd = '';
      this.selBoard = '';
      this.selLayer = '';
      this.sync();
      this.projName = appStore.projectName;
    });
  }

  /** 打开 DDP：无 path = 对话框选文件 + 空口令试探；dirty 先过确认。 */
  private actOpen(): void {
    if (this.busy) return;
    this.confirmThen((): void => {
      this.openTries = 0;
      this.openVia('', '');
    });
  }

  /** 项目名下拉 / 欢迎页行点击：就地热切换（不重启）。 */
  private hotSwitch(path: string): void {
    if (this.busy) return;
    if (path === appStore.filePath) return;   // 当前项目：幂等跳过
    this.confirmThen((): void => {
      this.openTries = 0;
      this.openVia(path, this.pwdByPath.get(path) ?? '');
    });
  }

  /**
   * 打开链路。注意分支差异（修订 8）：首次无 path 打开口令不符 Dispatch 返回
   * {needPassword:true,path}（Dispatch.ets:263-265）；带 path 重试口令不符返回的是
   * CmdError{error:'ddp_decrypt_failed:…'}（Dispatch.ets:266-269）——两条路都必须
   * 再弹口令框，上限 3 次。
   */
  private openVia(path: string, pwd: string): void {
    const args: Record<string, Object> = {};
    if (path !== '') {
      args['path'] = path;
      args['password'] = pwd;
    }
    this.dispatch.dispatch('open_ddp', args).then((v: Object | null): void => {
      if (v === null) return;   // 用户取消（Ok(null) 对齐桌面语义）
      const r = v as OpenDdpOutcome;
      if (r.needPassword === true) {
        this.askPwd(String(r.path ?? ''), 1);
        return;
      }
      if (typeof r.error === 'string' && r.error.startsWith('ddp_decrypt_failed')) {
        this.askPwd(path, this.openTries + 1);
        return;
      }
      if (typeof r.error === 'string') {
        this.agentMsg = '打开失败：' + r.error;
        appStore.logCmd('HUMAN', r.error, false);
        this.sync();   // batch-repair：logCmd 后必须 sync，否则 statusbar op 行（✗ 形态）不刷新
        return;
      }
      if (r.ok === true) {
        this.finishOpen(String(r.path ?? ''), String(r.mbtB64 ?? ''), pwd);
      }
    }).catch((e: Error): void => {
      const msg: string = '打开失败：' + e.message;
      this.agentMsg = msg;
      appStore.logCmd('HUMAN', msg, false);   // batch-2，iss-6：失败 op 接状态栏 ✗ 行（同上 r.error 分支）
      this.sync();
    });
  }

  private askPwd(path: string, tries: number): void {
    if (tries > 3) {
      const msg: string = '口令重试超过 3 次，已取消打开';
      this.agentMsg = msg;
      appStore.logCmd('HUMAN', msg, false);   // batch-2，iss-6：失败 op 接状态栏 ✗ 行（同 openVia 先例）
      this.sync();
      this.openTries = 0;
      return;
    }
    this.openTries = tries;
    this.pwdFor = path;
    this.pwdInput = '';
    this.showPwdAsk = true;
  }

  private confirmPwd(): void {
    const p = this.pwdFor;
    const w = this.pwdInput;
    this.showPwdAsk = false;
    this.openVia(p, w);
  }

  /** 解码 + 剥版本前缀 + restore + 绑定 path/口令 + 注册表 upsert。 */
  private finishOpen(path: string, mbtB64: string, pwd: string): void {
    let json = '';
    try {
      const helper = new util.Base64Helper();
      json = util.TextDecoder.create('utf-8').decodeToString(helper.decodeSync(mbtB64));
    } catch (e) {
      this.agentMsg = '项目数据解码失败';
      return;
    }
    if (json.startsWith(SER_PREFIX)) {
      if (!appStore.restore(json.substring(SER_PREFIX.length))) {
        const msg: string = '项目文件无法解析（格式损坏）';
        this.agentMsg = msg;
        appStore.logCmd('HUMAN', msg, false);   // batch-2，iss-6：失败 op 接状态栏 ✗ 行（同 openVia 先例）
        this.sync();
        return;
      }
    } else {
      // batch-11（cur-4/spec-ddp-1）：无 interim 前缀 = 桌面 canonical mbt → 本地解析器
      //（MbtDoc.parseMbtDoc，结构基准 canonical-sample.mbt.md）。成功→restoreCanonical
      //（entryBoard=frontmatter entry、isCanonicalSource=true）→ 走与 interim 相同的绑定尾；
      // 失败→诚实报错，不假装打开。原「暂不支持打开桌面版 .ddp」分支废止。
      const parsed = parseMbtDoc(json);
      if (!parsed.ok || !appStore.restoreCanonical(parsed)) {
        const msg: string = '无法解析（既非 interim 也非 canonical mbt）';
        this.agentMsg = msg;
        appStore.logCmd('HUMAN', msg, false);
        this.sync();
        return;
      }
    }
    const name = this.baseName(path);
    appStore.filePath = path;
    appStore.projectName = name;
    this.pwdByPath.set(path, pwd);
    this.sessionPwd = pwd;
    projectRegistry.upsert(path, name);
    this.recent = projectRegistry.list();
    this.selBoard = '';
    this.selLayer = '';
    appStore.logCmd('HUMAN', `open ${name}`);
    this.sync();
    this.projName = name;
  }

  /** 保存：有 filePath 原地回写；无 path 转导出浮层。 */
  private actSave(): void {
    if (appStore.filePath === '') {
      this.showExport = true;
      return;
    }
    if (appStore.isCanonicalSource) {
      // batch-11（复审 finding-6 防覆写守门）：canonical 来源项目不原地覆写——saveTo 的
      // preBound 语义只防改绑不防覆写，interim 载荷覆写桌面 canonical 文件 = 桌面文件损坏
      // （interim 与 canonical 双向不可互解）。一律转另存浮层写新文件。自动恢复链
      //（EntryAbility.onBackground → filesDir/autorecover.json）为应用沙箱内部文件，
      // 不在守门范围（登记）。
      this.showExport = true;
      return;
    }
    this.saveTo(appStore.filePath, this.sessionPwd);
  }

  /** 导出浮层确认（加密步）：口令仅存内存态，不持久化明文。 */
  private confirmExport(): void {
    this.showExport = false;
    const pwd = this.exportPwd;
    this.exportPwd = '';
    this.exportStep = 'choice';   // 两步浮层复位（下次打开回选项卡）
    this.saveTo('', pwd);
  }

  /**
   * save_ddp 分发。绑定边界（修订 7，对齐桌面防错文件语义）：仅 filePath 为空
   * （从未保存）时导出/保存成功才接管绑定 filePath + 会话口令；已绑定项目的导出
   * 是纯副本，不改绑保存目标。导出/保存成功均清 dirty + 注册表 upsert。
   */
  private saveTo(targetPath: string, pwd: string): void {
    const preBound = appStore.filePath;
    const args: Record<string, Object> = {
      'mbtB64': this.utf8ToB64(appStore.serialize()),
      'password': pwd,
      'path': targetPath
    };
    this.dispatch.dispatch('save_ddp', args).then((v: Object | null): void => {
      if (v === null) return;   // 用户取消
      const r = v as SaveDdpOutcome;
      if (r.ok !== true) {
        const err = String(r.error ?? 'ddp_save_failed:未知错误');
        appStore.logCmd('HUMAN', err, false);
        this.agentMsg = '保存失败：' + err;
        this.sync();
        return;
      }
      const p = String(r.path ?? '');
      if (preBound === '') {
        appStore.filePath = p;
        this.sessionPwd = pwd;
        appStore.projectName = this.baseName(p);
      }
      appStore.dirty = false;
      projectRegistry.upsert(p, this.baseName(p));
      this.recent = projectRegistry.list();
      appStore.logCmd('HUMAN', `save ${this.baseName(p)}`);
      this.sync();
      this.projName = appStore.projectName;
    }).catch((e: Error): void => {
      this.agentMsg = '保存失败：' + e.message;
    });
  }

  // ===== 自恢复（gap-global-4 兜底：windowWillClose 不派发时也不静默丢失）=====

  private checkAutorecover(ctx: common.UIAbilityContext): void {
    try {
      const p = ctx.filesDir + '/autorecover.json';
      if (!fs.accessSync(p)) return;
      const f = fs.openSync(p, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(f.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(f.fd, buf);
      fs.closeSync(f);
      const json = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
      fs.unlinkSync(p);   // 读出即删：无论恢复与否不留旧件（避免重复询问）
      if (json.trim() === '') return;
      this.recoverJson = json;
      this.showRecoverAsk = true;
    } catch (e) { /* 自恢复文件缺失/损坏直接跳过 */ }
  }

  private doRecover(): void {
    this.showRecoverAsk = false;
    let payload = this.recoverJson;
    this.recoverJson = '';
    if (payload.startsWith(SER_PREFIX)) payload = payload.substring(SER_PREFIX.length);
    if (!appStore.restore(payload)) {
      this.agentMsg = '自动恢复数据无法解析，已丢弃';
      return;
    }
    appStore.dirty = true;   // 恢复的是未保存工作，必须继续视为脏
    this.selBoard = '';
    this.selLayer = '';
    this.sync();
    this.projName = appStore.projectName;
  }

  // ===== 真缩放（gap-canvas-5；FIT 逐板适配 gap-canvas-1）=====

  /** 逐板适配系数（batch-7 cur-2/spec-fit-1：余量常数逐值对齐桌面 frontend/index.html:1708-1714
   * sed 实读——宽项 (clientWidth−120)/n 摊板数、高项 clientHeight−200；batch-repair 旧放宽
   * 扣减（单板 −128/ghost 150/板间 96n、高 −48−30）废止）。n=板数下限 1（桌面 max(1,len)
   * :1711 同构，空表防除零）；结果钳 0.18–8（桌面只有 0.18 下钳，8 上钳为 FIT 魔法数
   * zoom=64 语义下的本侧保险，登记保留）；容器未测得(<=0)时返回 1——r5b 教训：原 8 是
   * 「不缩」的误设（8×放大 65×面积 → 元素远超窗界、dump 舍弃+点击全脱靶），改 1:1
   * 渲染可见可点（demoZoom 未实测回退 1 同款先例），实测后经 zoom 入键重建校正。 */
  private fitOf(b: Board): number {
    if (this.cw <= 0 || this.ch <= 0) return 1;
    const n: number = Math.max(1, this.boards.length);
    const fz: number = Math.min((this.cw - 120) / n / b.width, (this.ch - 200) / b.height);
    return Math.max(0.18, Math.min(8, fz));
  }

  /** 画板渲染缩放系数（batch-7 cur-2/spec-fit-1：恢复桌面 frameScale 上限式自适应）。
   * scale = min(zoom/100, max(0.18, min((ch−200)/b.height, ((cw−120)/n)/b.width)))，
   * n=板数；非活动板 ×0.82（桌面 renderStage i:1732 `frameScale(sess)*(isActive?1:0.82)`
   * sed 实读——系数乘在钳顶之后，与桌面包络一致）；演示态 demoZoom cover 不走本函数，不动。
   * 【登记一 · r5b 摘钳的反转】本轮依据 r8 实读桌面源码 frontend/index.html:1708-1714
   * （frameScale=min(zoom, max(0.18, min((clientHeight-200)/h, ((clientWidth-120)/n)/w)))，
   * 本轮 sed 实跑核对原文）恢复钳顶：r5b 摘除 min(disp,fitOf) 的理由是「读数=zoom 状态」
   * 与「渲染被 fitOf 入框」两口径分裂（⤢ 前后读数跳变而渲染不变）；但桌面本就两口径并存
   * ——zoom 是上限、fit 因子只在板大于视口时往下压、永不放大超过 zoom（spec-fit-1），
   * 摘钳反而使「打开后整页平铺」（cur-2）失效：非 FIT 态 zoom=100% 原样渲染 1280×800 板，
   * 还原窗画布只装得下 ~30%。钳顶恢复后 gap-canvas-1「每板各自完整入框」回归桌面语义。
   * cw/ch 未实测（<=0 或低于余量常数）时跳过钳顶回退纯 zoom——r5b「未实测不缩放」先例，
   * 防负数/零除产生退化比例。
   * 【登记二 · 读数分歧】钳顶恢复后默认态读数=zoom 状态值 ≠ 实际生效比例（还原窗
   * web_login 1280×800 实算：r8 旧画布 368vp 时 min(357/800, 248/1280)≈19%；cur-1 后画布
   * 508vp 时 (388/1280)≈30%）——这与桌面 applyZoom（frontend/index.html:3319-3323 sed 实读：
   * 非 FIT 态直显 zoom%、仅 FIT 态读 frameScale 实际生效比例）行为一致，属对齐桌面语义，
   * zoomLabel 非 FIT 分支不改；r5 期「读数=几何自洽」口径仅在 FIT 态保持。
   * 【无主动 fit 调用】打开 DDP/启动恢复/ghost 新建均不需 fit——上限式自适应随 cw/ch
   * 每帧生效即得「打开后最小整页平铺」（桌面 zoomFit 全部调用点均为手动入口，spec-fit-1）。 */
  private zoomOf(b: Board): number {
    const base = this.zoom / 100;
    if (this.fitMode) {
      return this.fitOf(b);
    }
    if (this.cw <= 120 || this.ch <= 200) {
      return b.id === this.selBoard ? base : base * 0.82;
    }
    const n: number = Math.max(1, this.boards.length);
    const cap: number = Math.max(0.18,
      Math.min((this.ch - 200) / b.height, (this.cw - 120) / n / b.width));
    const scale: number = Math.min(base, cap);
    return b.id === this.selBoard ? scale : scale * 0.82;
  }

  /** 适配窗口：只置 FIT 态（zoom=100）——生效比例=fitOf，可放大超 100%（audit-canvas-4）。 */
  private fitWindow(): void {
    this.fitMode = true;
    this.zoom = 100;
    // batch-3 iss-4 兜底诊断 + batch-5（iss-4 复验定案）口径修正：本日志 round(fit×100) 应与
    // ⤢ 后 czoom dump 读数恒等（读数与几何自洽=判据口径）。旧注释「最大化预期 ≈105%、
    // ch≈967」系假设窗高与实际 1955 不符（r5 #13 判据口径已废）——读数 <100% 不再构成
    // 判负项，仅日志与 dump 背离才复复查扣减。batch-5 树内复验：fitWindow/resize 双 ddFit
    // 埋点、landFit 一次落比例、ddZoom fitMode=on/off 消歧、zoomOf 摘钳+zoom 入键
    // （:4907）均在场，复测定案归模拟器（对账三链见 batch-5 报告）。
    const cb = this.curBoard();
    if (cb !== null) {
      hilog.info(0x0000, 'ddFit', 'fitWindow cw=%{public}s ch=%{public}s fit=%{public}s boards=%{public}d',
        this.cw.toString(), this.ch.toString(), this.fitOf(cb).toString(), this.boards.length);
    }
  }

  /** FIT 态步进先落活动板实际生效比例再乘，防跳变（对齐桌面 zoomStep）。 */
  private landFit(): void {
    if (!this.fitMode) return;
    let cb = this.curBoard();
    if (cb === null && this.boards.length > 0) {
      cb = this.boards[0];   // r5（判据 E）：演示进出等瞬态 selBoard 丢失改落首板实际比例，
                             // 防「−」从状态 zoom=100 步进出 83%（r5 实证判负形态）
    }
    if (cb !== null) {
      this.zoom = Math.round(this.zoomOf(cb) * 100);
    }
    this.fitMode = false;
  }

  /** czoom 读数：FIT 态显示活动板实际生效比例（对齐桌面 applyZoom）。 */
  private zoomLabel(): string {
    if (!this.fitMode) return `${this.zoom}%`;
    let cb = this.curBoard();
    if (cb === null && this.boards.length > 0) {
      cb = this.boards[0];   // r5（判据 E）：瞬态 selBoard 丢失不再回退显示状态 zoom=100，
                             // 改取首板实际生效比例（与画布渲染同源 zoomOf，读数=几何）
    }
    if (cb === null) return `适配 ${this.zoom}%`;
    return `适配 ${Math.round(this.zoomOf(cb) * 100)}%`;
  }

  /** 切画板统一清理：清选中 + 关行内 Agent 浮层（gap-canvas-3，对齐桌面 switchSession 语义）。 */
  private clearBoardSwitchState(): void {
    this.selLayer = '';
    this.inlineAgent = false;
  }

  /** 层交互列表：restore 往返可能产生非数组脏值，Array.isArray 收窄防运行时抛（r2 验收教训）。 */
  private layerInteractions(l: LayerNode): Interaction[] {
    if (Array.isArray(l.interactions)) {
      return l.interactions;
    }
    return [];
  }

  // ===== 画板视图偏移（gap-canvas-7：标题栏拖移，纯视图层不记 op）=====

  private boardOffset(bid: string): [number, number] {
    const hit = this.boardOffsets.find((o: [string, number, number]): boolean => o[0] === bid);
    return hit ? [hit[1], hit[2]] : [0, 0];
  }

  /** 整组替换触发 @State（元组内元素原地改不保证观察）。
   * 边界钳制（gap-canvas-16 + gap-detail-18，对齐 i:1774-1775/1788-1789 双钳 sed 实证）：
   * baseX/baseY=该板无偏移原点（boardOrigin，y 已含恒高 chrome 30），x/y 各钳
   * [-(base-80), 4000]——板缘最多拖到画布 80px 余量处；此前「y 不钳（通用版只钳 x）」
   * 为对通用版源码的误读（minDx/minDy 双钳实锤），已纠正。 */
  private setBoardOffset(bid: string, x: number, y: number): void {
    const idx = this.boardOffsets.findIndex((o: [string, number, number]): boolean => o[0] === bid);
    const next: Array<[string, number, number]> = this.boardOffsets.slice();
    const b = this.boards.find((bd: Board): boolean => bd.id === bid);
    if (b) {
      const cur = this.boardOffset(bid);
      const org = this.boardOrigin(b);
      const minX = -(org[0] - cur[0] - 80);
      const minY = -(org[1] - cur[1] - 80);
      if (x < minX) { x = minX; }
      if (x > 4000) { x = 4000; }
      if (y < minY) { y = minY; }
      if (y > 4000) { y = 4000; }
    }
    if (idx >= 0) {
      next[idx] = [bid, x, y];
    } else {
      next.push([bid, x, y]);
    }
    this.boardOffsets = next;
  }

  // ===== 组件面板（gap-leftcomp-1）=====

  private loadComps(ctx: common.UIAbilityContext): void {
    ctx.resourceManager.getRawFileContent('vendor/components.json').then((data: Uint8Array): void => {
      try {
        const json = util.TextDecoder.create('utf-8').decodeToString(data);
        const arr = JSON.parse(json) as CompDef[];
        this.comps = Array.isArray(arr) ? arr : [];
      } catch (e) {
        this.comps = [];   // 快照损坏：面板空态，不阻断
      }
    }).catch((): void => { /* rawfile 缺失：面板空态 */ });
  }

  /** 模型能力快照（batch-3，audit-modal-6）：rawfile/models.json 摊平成 modelId→能力 的
   * Map 供设置卡能力提示查表（桌面 fillModelHints 经 model_registry 下发，鸿蒙直读
   * rawfile 同源快照）。损坏/缺失降级为空 Map → 提示行显示「快照未收录」。 */
  private capByModel: Map<string, ModelCap> = new Map();

  private loadCapSnapshot(ctx: common.UIAbilityContext): void {
    ctx.resourceManager.getRawFileContent('models.json').then((data: Uint8Array): void => {
      try {
        const json = util.TextDecoder.create('utf-8').decodeToString(data);
        const root = JSON.parse(json) as CapRoot;
        if (root.providers === undefined) {
          this.capLoaded = true;
          return;
        }
        const pkeys: string[] = Object.keys(root.providers);
        for (const pk of pkeys) {
          const pv: CapProvider | undefined = root.providers[pk];
          if (pv === undefined || pv.models === undefined) continue;
          const mkeys: string[] = Object.keys(pv.models);
          for (const mk of mkeys) {
            const mo: CapModel | undefined = pv.models[mk];
            if (mo === undefined) continue;
            // batch-12：reasoning_options 解析（effort 实测档 + toggle 在案；二者可并存，
            // 如 deepseek-v4/kimi-k3）——思考档位收紧数据源
            const effort: string[] = [];
            let toggle = false;
            const ros: ReasoningOption[] = mo.reasoning_options ?? [];
            for (const ro of ros) {
              if (ro.type === 'effort') {
                const vs: string[] = ro.values ?? [];
                for (const v of vs) {
                  effort.push(v);
                }
              } else if (ro.type === 'toggle') {
                toggle = true;
              }
            }
            this.capByModel.set(mk, {
              context: mo.limit?.context ?? 0,
              toolCall: mo.tool_call === true,
              structured: mo.structured_output === true,
              reasoningEffort: effort,
              reasoningToggle: toggle
            });
          }
        }
        this.capLoaded = true;   // @State 翻转触发能力提示行重建
        this.restrictThinking();   // batch-12：快照晚于表单载入时补收紧（无静默降级）
      } catch (e) {
        this.capLoaded = true;   // 快照损坏：空 Map → 未收录降级文案
      }
    }).catch((): void => {
      this.capLoaded = true;     // rawfile 缺失：同上
    });
  }

  /** 能力提示主行（i:1157-1164 语义）：`上下文 XK · 工具调用 ✓/✗ · 结构化 ✓/✗`；
   * base/model 未填返回空；快照无此模型返回未收录降级文案。 */
  private capHintMain(): string {
    const model = this.cfgModel.trim();
    if (model === '' || this.cfgBaseUrl.trim() === '') return '';
    const cap = this.capByModel.get(model);
    if (cap === undefined) {
      return '快照未收录该模型——可手动输入，但能力与思考档位无法校验';
    }
    const parts: string[] = [];
    if (cap.context > 0) parts.push(`上下文 ${Math.round(cap.context / 1000)}K`);
    parts.push(`工具调用 ${cap.toolCall ? '✓' : '✗'}`);
    parts.push(`结构化 ${cap.structured ? '✓' : '✗'}`);
    return parts.join(' · ');
  }

  /** 能力警告行：快照内模型不支持工具调用时警告（Agent 循环依赖工具调用，桌面同语义）。 */
  private capHintWarn(): string {
    const model = this.cfgModel.trim();
    if (model === '' || this.cfgBaseUrl.trim() === '') return '';
    const cap = this.capByModel.get(model);
    if (cap !== undefined && !cap.toolCall) return '— 不支持工具调用，Agent 循环会失效';
    return '';
  }

  /** 模板缩略图在场探测（batch-3，audit-modal-10）：逐 tid 试读 rawfile/tplthumbs/<tid>.svg，
   * 在场 → tplThumb 渲染引擎真实 SVG；缺失 → 假线框回退（wasm 不在场的历史镜像）。 */
  private tplThumbIds: Set<string> = new Set();

  private probeTplThumbs(ctx: common.UIAbilityContext): void {
    for (const t of TPLS) {
      try {
        ctx.resourceManager.getRawFileContentSync(`tplthumbs/${t.tid}.svg`);
        this.tplThumbIds.add(t.tid);
      } catch (e) {
        /* 缺失：该 tid 回退假线框 */
      }
    }
    this.tplThumbsProbed = true;   // @State 翻转触发模板卡重建
  }

  private compCats(): string[] {
    const out: string[] = [];
    for (const c of this.comps) {
      if (!out.includes(c.category)) out.push(c.category);
    }
    return out;
  }

  private compsIn(cat: string): CompDef[] {
    const q = this.compQuery.trim().toLowerCase();
    return this.comps.filter((c: CompDef): boolean => {
      if (c.category !== cat) return false;
      if (q === '') return true;
      return c.id.toLowerCase().includes(q) || c.description.includes(q);
    });
  }

  private compCount(cat: string): number {
    return this.compsIn(cat).length;
  }

  private toggleCat(cat: string): void {
    this.closedCats = this.closedCats.includes(cat)
      ? this.closedCats.filter((c: string): boolean => c !== cat)
      : this.closedCats.concat([cat]);
  }

  /** 点击组件格 → 放到 active 板中心附近（拖拽幽灵 pill 为 dropped 可选打磨，本轮点击放置）。 */
  /** 组件点击放置（batch-6，audit-left-10 兜底通道：活动板中心；拖拽通道见 dropCompAtWindow）。 */
  private placeComp(c: CompDef): void {
    const b = this.curBoard();
    if (!b) {
      this.agentMsg = '请先创建画板，再放置组件';
      return;
    }
    const w = c.default_size.length > 0 ? c.default_size[0] : 120;
    const h = c.default_size.length > 1 ? c.default_size[1] : 32;
    const x = Math.max(0, Math.round((b.width - w) / 2));
    const y = Math.max(0, Math.round((b.height - h) / 2));
    const placed = appStore.placeLayer(b.id, c, x, y);
    if (placed) {
      this.selLayer = placed.id;
    }
    this.sync();
  }

  /** 组件拖拽落点换算（batch-6，audit-left-10）：窗口坐标 → 画布内容系（flowFrom 口径：
   * 左栏实测宽 leftW+右缘 1 + 顶栏 46 + tail 32 常量相减——登记近似：canvas Scroll 滚动
   * 偏移未计入，模拟器实证后若偏差大改绑 scroller offset）。batch-7 cur-1：左栏 252 改
   * 动态 leftW（等比折算后 196–252，硬编码 253 在窄窗漏算 → 落点系统性右偏）。
   * 命中板 → 板内落点 placeLayer；未命中任何板 → 活动板中心（placeComp 既有路径）。 */
  private dropCompAtWindow(wx: number, wy: number, c: CompDef): void {
    const contentX = wx - (this.leftW + 1);
    const contentY = wy - 78;
    for (const b of this.boards) {
      const org = this.boardOrigin(b);
      const z = this.zoomOf(b);
      const lx = (contentX - org[0]) / z;
      const ly = (contentY - org[1]) / z;
      if (lx >= 0 && ly >= 0 && lx <= b.width && ly <= b.height) {
        const w0 = c.default_size.length > 0 ? c.default_size[0] : 120;
        const h0 = c.default_size.length > 1 ? c.default_size[1] : 32;
        const px = Math.max(0, Math.round(lx - w0 / 2));
        const py = Math.max(0, Math.round(ly - h0 / 2));
        const placed = appStore.placeLayer(b.id, c, px, py);
        if (placed) {
          this.selBoard = b.id;
          this.selLayer = placed.id;
        }
        this.sync();
        this.toast(`已放置 ${c.id} 到 ${b.name}`);
        return;
      }
    }
    this.placeComp(c);
  }

  // ===== toast（gap-global-2 正式化：err 红染 4.2s / 常规 2.4s）=====

  private toast(m: string, kind: string = 'ok'): void {
    this.toastMsg = m;
    this.toastKind = kind;
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
    }
    this.toastTimer = setTimeout((): void => {
      this.toastMsg = '';
      this.toastTimer = -1;
    }, kind === 'err' ? 4200 : 2400);
  }

  // ===== 键盘面（gap-kbd-1；修订 5 焦点策略）=====

  private onPlanKey(e: KeyEvent): void {
    if (e.type !== KeyType.Down) return;
    const code = e.keyCode;
    if (code === KeyCode.KEYCODE_ESCAPE) {
      if (this.showSettings) { this.showSettings = false; return; }   // Esc 关设置（batch-3，i:2443-2446；焦点在 TextInput 时根收不到，走钮兜底——登记）
      if (this.showExport) {
        this.showExport = false;
        this.exportStep = 'choice';
        return;
      }
      if (this.showDemo) { this.demoBack(); return; }   // Esc=返回上一层；退出唯一入口=HUD 退出按钮（i:2447-2448）
      if (this.toolMode !== 'select') {
        this.toolMode = 'select';
        this.pendingFromBoard = '';
        this.pendingFromNode = '';
        return;
      }
      if (this.showInline) { this.cancelInline(); return; }
      if (this.inlineAgent) { this.inlineAgent = false; return; }
      return;
    }
    if (this.inputFocused) return;   // 文本输入中：编辑类键不抢（修订 5 守卫）
    // 修饰键：getModifierKeyState 为可选方法（common.d.ts:8166），控制流收窄后调用。
    // 显式 boolean 注解是必须的：编译器对可选方法调用结果不做有效推断，
    // 裸 let 初始化会被毒化为非 boolean，连带 -step 报 arkts-no-polymorphic-unops。
    let ctrl: boolean = false;
    let shift: boolean = false;
    if (e.getModifierKeyState !== undefined) {
      const keysCtrl: Array<string> = ['Ctrl'];
      const keysShift: Array<string> = ['Shift'];
      ctrl = e.getModifierKeyState(keysCtrl) || e.metaKey === 1;
      shift = e.getModifierKeyState(keysShift);
    }
    if (ctrl) {
      if (code === KeyCode.KEYCODE_Z) {
        if (shift) {
          this.redoOp();   // M3：引擎会话走 session_history；否则本地快照栈（undoOp/redoOp 内路由）
        } else {
          this.undoOp();
        }
        return;
      }
      if (code === KeyCode.KEYCODE_S) { this.actSave(); return; }
      if (code === KeyCode.KEYCODE_K) {
        this.getUIContext().getFocusController().requestFocus('promptInput');
        return;
      }
      if (code === KeyCode.KEYCODE_MINUS) {
        if (this.fitMode) { this.landFit(); return; }   // r5：FIT 首步只落比例不步进（同 czoom ±）
        this.zoom = Math.max(18, Math.round(this.zoom / 1.2)); return;
      }
      if (code === KeyCode.KEYCODE_EQUALS) {
        if (this.fitMode) { this.landFit(); return; }
        this.zoom = Math.min(800, Math.round(this.zoom * 1.2)); return;
      }
      if (code === KeyCode.KEYCODE_0) { this.fitWindow(); return; }   // ⌘0=适配窗口，复位 100% 只在 1:1 钮（gap-canvas-1）
      if (code === KeyCode.KEYCODE_N) {   // gap-canvas-11：⌘N 新建项目 / ⇧⌘N 新建画板（对齐 i:2458-2477）
        if (shift) {
          const nb = appStore.addBlankBoard();
          this.sync();
          this.selBoard = nb.id;
          this.selLayer = '';
        } else {
          this.actNew();
        }
        return;
      }
      if (code === KeyCode.KEYCODE_O) { this.actOpen(); return; }   // ⌘O 打开（gap-canvas-11）
      if (shift && code === KeyCode.KEYCODE_F) { this.runFix(); return; }   // ⇧⌘F 自动修复（batch-3，audit-modal-9 对齐桌面 'F':runFix）
      if (shift && code === KeyCode.KEYCODE_D) {   // ⇧⌘D 复制当前画板（gap-canvas-11）
        if (this.selBoard !== '') {
          const nb = appStore.duplicateBoard(this.selBoard);
          if (nb !== null) {
            this.selBoard = nb.id;
            this.selLayer = '';
          }
          this.sync();
        }
        return;
      }
      if (!shift && code === KeyCode.KEYCODE_1) { this.modeIdx = 0; return; }   // ⌘1/⌘2/⌘3 模式（对齐 i:2472）
      if (!shift && code === KeyCode.KEYCODE_2) { this.modeIdx = 1; return; }
      if (!shift && code === KeyCode.KEYCODE_3) {
        this.declText = appStore.toCanonicalText();   // 进入源码视图刷新（同 mode-seg 链；canonical 展示投影）
        this.modeIdx = 2;
        return;
      }
      if (!shift && code === KeyCode.KEYCODE_4) { this.actDemoEntry(); return; }   // ⌘4 演示即第 4 模式
      if (shift && (code === KeyCode.KEYCODE_FORWARD_DEL || code === KeyCode.KEYCODE_DEL)) {   // ⇧⌘⌫ 删活动画板（含守卫）
        if (this.selBoard !== '') { this.confirmDeleteBoard(this.selBoard); }
        return;
      }
      if (code === KeyCode.KEYCODE_SLASH) {   // Ctrl+/ 快捷键说明（r11 归外观 tab：先切 look 再开）
        this.openKeymapSettings();   // r11 修复轮：分支体抽方法，与 dd_key 验收通道共用单一事实源
        return;
      }
      if (code === KeyCode.KEYCODE_COMMA) {   // Ctrl+, 设置（保持当前 tab，不强制切）
        this.showSettings = true;
        return;
      }
      return;
    }
    // ⇧E / ⇧H：导出 DDP / HTML（对齐桌面 'e':exportDdp / 'h':exportHtmlProto，i:2464/:2466；SVG 不设键位，gap-canvas-12）
    if (!ctrl && shift && code === KeyCode.KEYCODE_E) { this.showExport = true; return; }
    if (!ctrl && shift && code === KeyCode.KEYCODE_H) { this.exportHtmlProto(); return; }
    // V / T：无修饰键单键（不含修饰键，避免吃掉 Ctrl+V 粘贴，对齐 i:2480-2486；gap-canvas-12 移出 ctrl 分支）
    if (!ctrl && !shift && code === KeyCode.KEYCODE_V) { this.toolMode = 'select'; return; }
    if (!ctrl && !shift && code === KeyCode.KEYCODE_T) { this.toolMode = 'text'; return; }
    // 非组合键
    if (code === KeyCode.KEYCODE_FORWARD_DEL || code === KeyCode.KEYCODE_DEL) {
      const b = this.curBoard();
      const l = this.curLayer();
      if (b && l) {
        appStore.deleteLayer(b.id, l.id);
        this.selLayer = '';
        this.sync();
      }
      return;
    }
    const step: number = shift ? 10 : 1;
    const b = this.curBoard();
    const l = this.curLayer();
    if (b && l) {
      if (code === KeyCode.KEYCODE_DPAD_UP) { appStore.moveLayer(b.id, l.id, 0, -step); this.sync(); return; }
      if (code === KeyCode.KEYCODE_DPAD_DOWN) { appStore.moveLayer(b.id, l.id, 0, step); this.sync(); return; }
      if (code === KeyCode.KEYCODE_DPAD_LEFT) { appStore.moveLayer(b.id, l.id, -step, 0); this.sync(); return; }
      if (code === KeyCode.KEYCODE_DPAD_RIGHT) { appStore.moveLayer(b.id, l.id, step, 0); this.sync(); return; }
    }
  }

  /** Ctrl+/ 分支体（r11 修复轮自 onPlanKey 抽出）：快捷键说明强制 look tab 再开设置——
   * 物理键路径（onPlanKey Ctrl+/ 分支）与 dd_key 验收通道（onKeyEvtParam 'slash'）共用
   * 本方法，单一事实源防双处分叉。 */
  private openKeymapSettings(): void {
    this.settingsTab = 'look';
    this.showSettings = true;
  }

  // ===== 删板确认（gap-global-2）=====

  private confirmDeleteBoard(id: string): void {
    if (this.boards.length <= 1) {
      this.toast('至少保留一个画板', 'err');   // gap-canvas-10，对齐通用版 i:2345
      return;
    }
    const b = this.boards.find((x: Board): boolean => x.id === id);
    if (!b) return;
    this.getUIContext().showAlertDialog({
      title: '删除画板',
      message: `确定删除「${b.name}」？可经 ↶ 撤销。`,
      primaryButton: {
        value: '取消',
        action: (): void => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: this.T().danger,
        action: (): void => {
          appStore.removeBoard(id);
          // 视图态残留清理（r2 缺口 3b：多板反复操作后状态残留）：已删板的视图偏移、
          // 以该板为源/目标的连线挂起态一并作废，防止后续误建悬空流。
          this.boardOffsets = this.boardOffsets.filter((o: [string, number, number]): boolean => o[0] !== id);
          if (this.pendingFromBoard === id) {
            this.pendingFromBoard = '';
            this.pendingFromNode = '';
          }
          this.toast(`已删除画板 ${b.name}`);
          this.sync();
        }
      }
    });
  }

  // ===== 导出 HTML/SVG（gap-topbar-4；引擎 render 产物归 gap-global-3 回收）=====

  private escXml(s: string): string {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  /** 当前画板 → 静态 SVG（与 elNode 渲染字段一一对应）。 */
  private buildSvg(b: Board): string {
    const p: string[] = [];
    p.push(`<svg xmlns="http://www.w3.org/2000/svg" width="${b.width}" height="${b.height}" viewBox="0 0 ${b.width} ${b.height}">`);
    p.push('<rect x="0" y="0" width="' + b.width + '" height="' + b.height + '" fill="#ffffff"/>');
    for (const l of b.layers) {
      const s = l.style;
      // stroke 语义同步（batch-3，gap-detail-7）+ 线型三态（batch-5）：描边字段 >0 读之；
      // 未设维持旧 dash 缺省
      let strokeAttr = '';
      if (s.strokeWidth > 0) {
        strokeAttr = ` stroke="${s.stroke}" stroke-width="${s.strokeWidth}"` +
          (s.dash !== 'solid' ? ` stroke-dasharray="${this.dashArray(s.dash)[0]} ${this.dashArray(s.dash)[1]}"` : '');
      } else if (s.dash !== 'solid') {
        strokeAttr = ` stroke="#333333" stroke-dasharray="${this.dashArray(s.dash)[0]} ${this.dashArray(s.dash)[1]}"`;
      }
      if (l.type === 'image') {
        p.push(`<circle cx="${s.x + s.w / 2}" cy="${s.y + s.h / 2}" r="${Math.min(s.w, s.h) / 2}" fill="${s.fill}"/>`);
        continue;
      }
      p.push(`<rect x="${s.x}" y="${s.y}" width="${s.w}" height="${s.h}" rx="${s.radius}" fill="${s.fill}"${strokeAttr}/>`);
      if (s.text !== '') {
        const anchor = s.align === 'center' ? 'middle' : s.align === 'right' ? 'end' : 'start';
        const tx = s.align === 'center' ? s.x + s.w / 2 : s.align === 'right' ? s.x + s.w : s.x;
        p.push(`<text x="${tx}" y="${s.y + s.h / 2 + s.fontSize * 0.36}" font-size="${s.fontSize}" fill="${s.color}"${s.bold ? ' font-weight="bold"' : ''}${s.italic ? ' font-style="italic"' : ''} text-anchor="${anchor}">${this.escXml(s.text)}</text>`);
      }
    }
    p.push('</svg>');
    return p.join('');
  }

  /** 全部画板 → 静态 HTML 原型（按 flows 生成板间点击跳转脚本）。 */
  private buildHtml(): string {
    const pairs: string[] = [];
    for (const fl of appStore.flows) {
      pairs.push(`"${fl.fromBoard}/${fl.fromNode}":"${fl.toBoard}"`);
    }
    const pages: string[] = [];
    const navs: string[] = [];
    for (const b of this.boards) {
      const nodes: string[] = [];
      for (const l of b.layers) {
        const s = l.style;
        nodes.push(`<div data-b="${b.id}" data-n="${l.id}" style="position:absolute;left:${s.x}px;top:${s.y}px;width:${s.widthMode === 'fill' ? b.width : s.w}px;height:${s.h}px;background:${s.fill};border-radius:${s.radius}px;opacity:${s.opacity};display:${s.visible ? 'block' : 'none'};color:${s.color};font-size:${s.fontSize}px;font-weight:${s.bold ? 700 : 400};text-align:${s.align};overflow:hidden">${this.escXml(s.text)}</div>`);
      }
      pages.push(`<section class="board" id="${b.id}" style="display:${b.id === this.selBoard ? 'block' : 'none'}"><h3>${this.escXml(b.name)}</h3><div style="position:relative;width:${b.width}px;height:${b.height}px;background:#ffffff">${nodes.join('')}</div></section>`);
      navs.push(`<button onclick="go('${b.id}')">${this.escXml(b.name)}</button>`);
    }
    return '<!DOCTYPE html><html><head><meta charset="utf-8">' +
      `<title>${this.escXml(appStore.projectName)}</title>` +
      '<style>body{font-family:system-ui;margin:16px;background:#f2f3f7}.board{margin-bottom:24px}.canvas{box-shadow:0 1px 4px rgba(0,0,0,0.12)}button{margin-right:8px;padding:4px 10px}</style>' +
      '</head><body><h2>' + this.escXml(appStore.projectName) + '</h2><nav>' + navs.join('') + '</nav>' +
      pages.join('') +
      '<script>var F={' + pairs.join(',') + '};' +
      'function go(id){var bs=document.querySelectorAll(".board");for(var i=0;i<bs.length;i++){bs[i].style.display=(bs[i].id===id?"block":"none");}}' +
      'document.addEventListener("DOMContentLoaded",function(){document.querySelectorAll("[data-b]").forEach(function(e){e.addEventListener("click",function(){var k=e.getAttribute("data-b")+"/"+e.getAttribute("data-n");if(F[k]){go(F[k]);}});});});' +
      '</script></body></html>';
  }

  private saveVia(name: string, content: string, label: string): void {
    const args: Record<string, Object> = { 'name': name, 'contentsB64': this.utf8ToB64(content) };
    this.dispatch.dispatch('save_text_file', args).then((v: Object | null): void => {
      if (v === null) {
        this.toast('已取消保存');
        return;
      }
      const r = v as SavedFile;
      this.toast(`${label} 已保存：${this.baseName(String(r.savedTo ?? ''))}`);
    }).catch((e: Error): void => {
      this.toast(`${label} 保存失败：` + e.message, 'err');
    });
  }

  private exportSvg(): void {
    const b = this.curBoard();
    if (!b) {
      this.toast('先选中一块画板再导出 SVG', 'err');
      return;
    }
    this.saveVia(`${appStore.projectName}.svg`, this.buildSvg(b), 'SVG');
  }

  private exportHtmlProto(): void {
    if (this.boards.length === 0) {
      this.toast('先创建画板再导出 HTML', 'err');
      return;
    }
    this.saveVia(`${appStore.projectName}.html`, this.buildHtml(), 'HTML');
  }

  private exportMenu(): Array<DdMenuGroup> {
    const groups: Array<DdMenuGroup> = [];
    // 撤销/重做收留（batch-4，audit-topbar-12 显性扩展决策登记）：通用版顶栏无撤销/重做钮
    //（↶↷ 系鸿蒙侧自造，本批移出顶栏）；桌面同类动作挂「文件 ▾」菜单（undoMbt/redoMbt），
    // 鸿蒙无该菜单，就近收留于「导出▾」保可达性。batch-2 dd-menu-export：改产 DdMenuGroup，
    // canUndo/canRedo=false 行 disabled=true 且文案维持「（无可用步）」不回退——行可点
    // 但动作旁路（ddMenuRow disabled 语义）。
    groups.push({
      title: '',
      items: [
        {
          label: this.canUndo ? '撤销' : '撤销（无可用步）',
          kbd: '',
          selected: false,
          danger: false,
          disabled: !this.canUndo,
          action: (): void => {
            this.undoOp();
          }
        },
        {
          label: this.canRedo ? '重做' : '重做（无可用步）',
          kbd: '',
          selected: false,
          danger: false,
          disabled: !this.canRedo,
          action: (): void => {
            this.redoOp();
          }
        }
      ]
    });
    groups.push({
      title: '',
      items: [
        {
          label: '导出 SVG（当前画板）…',
          kbd: '',
          selected: false,
          danger: false,
          disabled: false,
          action: (): void => { this.exportSvg(); }
        },
        {
          label: '导出 HTML 原型…',
          kbd: '',
          selected: false,
          danger: false,
          disabled: false,
          action: (): void => { this.exportHtmlProto(); }
        }
      ]
    });
    // 窄窗收留（batch-1，iss-5 响应式折叠）：顶栏隐藏的 ⚙ 设置/▶ 演示改挂本菜单——
    // 复用「导出▾」作溢出菜单不新增 ⋯ 钮省宽度，与 ↶↷ 收留同例（audit-topbar-12）。
    // 宽窗（topW≥1200）顶栏全集在场，菜单不重复出这两条。
    return groups;
  }

  // ===== ctools 工具条（gap-canvas-1）=====

  private pickTool(mode: string): void {
    this.refocusRoot();   // 修订 5：工具条交互后回焦根
    if (mode === 'fix') {
      this.runFix();   // fix 点按即执行，不驻留模式（引擎 fix op 归 gap-global-3 回收）
      return;
    }
    if (this.toolMode === mode) {   // 再点同钮回选择，免卡死在模式里
      this.toolMode = 'select';
      this.pendingFromBoard = '';
      this.pendingFromNode = '';
      return;
    }
    this.toolMode = mode;
    this.pendingFromBoard = '';
    this.pendingFromNode = '';
    if (mode === 'link') this.toast('连接模式：点击源节点，再点目标画板');
    if (mode === 'text') this.toast('文本模式：点击画布空白放置文本');
  }

  /** fix 钮：暂复用 pchip「一键修复」本地兜底链（Index pchips 现有路径）。 */
  private runFix(): void {
    if (this.busy) return;
    if (this.curBoard() === null) {
      this.toast('先创建画板，再自动修复');
      return;
    }
    this.toast('自动修复：交给小艺…');
    this.usePrompt('一键修复');
  }

  /** link 模式第二段：点目标板建流并回 select。toast 文案对齐 i:1991「{node} → {to} 连接已写入
   * MBT」（batch-6，gap-detail-19）：node/to 与药丸标签同源（flowLabelTl/板 id），避免口径互斥。 */
  private finishLink(toBoard: string): void {
    const f = appStore.createFlow(this.pendingFromBoard, this.pendingFromNode, toBoard);
    this.pendingFromBoard = '';
    this.pendingFromNode = '';
    this.toolMode = 'select';
    if (f === null) {
      this.toast('该连接已存在，已忽略');
    } else {
      this.toast(`${this.flowLabelTl(f)} → ${f.toBoard} 连接已写入 MBT`);
    }
    this.sync();
  }

  private boardName(bid: string): string {
    const b = this.boards.find((x: Board): boolean => x.id === bid);
    return b ? b.name : bid;
  }

  // ===== 交互流几何（gap-canvas-6：端点计入 zoom/boardOffsets，拖移缩放跟随）=====
  // 坐标系 = 画布内容 Stack（TopStart），与 flow Stack 原点一致（含 Row padding 64/56）。

  /** 板缩放 body 的视觉左上原点（batch-1 chrome 外提后重定义：y 含恒高标题栏，不随 zoom 缩放；
   * x 累计口径不变——body 宽=板宽×zoomOf）。batch-2 iss-2：y 改由画布几何常量推导
   * （CANVAS_BOARD_TOP=工具块 36+34 + 板排 padding-top 8 + chrome 30=108，旧口径 56+30=86），
   * 模拟器 dump 实测与推导偏差 >2vp 即回查常量。消费点全清单同此口径：
   * flowFrom/flowTo（连线端点）、startInlineEdit（双击编辑框）、openInlineAgent（行内
   * Agent 浮层）、setBoardOffset（拖移钳制基准）。
   * batch-7（cur-10 复测登记）：zoomOf 引入 frameScale 钳顶后 x 累计（板宽×zoomOf）与
   * 选中态 0.82 系数的换算值随 cw/ch 变化——换基消费点（boardOriginStack 三处 + 拖移钳制）
   * 代码零改动、几何值随函数单一源自动跟随；r7 §7.1 清单 1 的连线端点/药丸 y/双击编辑框/
   * 行内 Agent 浮层落点 dump 对比推导值（门槛 ≤2vp）归本批后模拟器复测。 */
  private boardOrigin(b: Board): [number, number] {
    let x = 64;
    for (const ob of this.boards) {
      if (ob.id === b.id) break;
      x += ob.width * this.zoomOf(ob) + 96;
    }
    return [x + this.boardOffset(b.id)[0], CANVAS_BOARD_TOP + this.boardOffset(b.id)[1]];
  }

  /** 内容 Stack-local 板原点（batch-6 验收修正，r8 实测 +70vp 回归根因）：连线/药丸/
   * 内联编辑/行内 Agent 经 .position() 消费，坐标系 = 内容 Stack TopStart——iss-2 工具行
   * 入流后 Stack 原点已下移到 scroll-content y=工具块 70 下缘，y 需 −CANVAS_TOOLBLOCK_H
   * 换基（x 无水平偏移两帧同值）。boardOrigin 本体保持 canvas-local：dropCompAtWindow
   * 命中测试与 setBoardOffset 拖移钳制（板缘 80px 余量语义，钳的是 canvas-local 视觉位）
   * 消费的就是该帧——两帧各有所主，勿"顺手统一"。 */
  private boardOriginStack(b: Board): [number, number] {
    const org = this.boardOrigin(b);
    return [org[0], org[1] - CANVAS_TOOLBLOCK_H];
  }

  private flowValid(f: Flow): boolean {
    return this.boards.some((b: Board): boolean => b.id === f.fromBoard) &&
      this.boards.some((b: Board): boolean => b.id === f.toBoard);
  }

  /** 源节点右缘中点；节点被删则退化为源板右缘中点。同源多条按序号 y -= k*12 向上扇开
   * （batch-4，gap-detail-10 对齐 i:1882 lift=(ix-1)*12 上错开——原向下 +k*12 为方向误读）。
   * k 为该流在同源流中的序号（0,1,…→偏移 0,12,…）；findIndex 意外 -1（undo/redo 瞬态）钳 0 防反向错开。 */
  private flowFrom(f: Flow): [number, number] {
    const b = this.boards.find((x: Board): boolean => x.id === f.fromBoard);
    if (!b) return [0, 0];
    const org = this.boardOriginStack(b);   // batch-6：Stack-local 换基（r8 实测修正）
    const z = this.zoomOf(b);
    const n = b.layers.find((l: LayerNode): boolean => l.id === f.fromNode);
    if (!n) return [org[0] + b.width * z, org[1] + b.height * z / 2];
    const k = Math.max(0, this.flows
      .filter((x: Flow): boolean => x.fromBoard === f.fromBoard && x.fromNode === f.fromNode)
      .findIndex((x: Flow): boolean => x.id === f.id));
    return [org[0] + (n.style.x + n.style.w) * z, org[1] + (n.style.y + n.style.h / 2) * z - k * 12];
  }

  /** 目标板左缘中点。 */
  private flowTo(f: Flow): [number, number] {
    const b = this.boards.find((x: Board): boolean => x.id === f.toBoard);
    if (!b) return [0, 0];
    const org = this.boardOriginStack(b);   // batch-6：Stack-local 换基（r8 实测修正）
    return [org[0], org[1] + b.height * this.zoomOf(b) / 2];
  }

  private flowMin(f: Flow): [number, number] {
    const a = this.flowFrom(f);
    const t = this.flowTo(f);
    return [Math.min(a[0], t[0]), Math.min(a[1], t[1])];
  }

  /** 贝塞尔命令串（局部坐标：源右缘 → 目标左缘，水平控制点）。 */
  private flowCmds(f: Flow): string {
    const a = this.flowFrom(f);
    const t = this.flowTo(f);
    const mn = this.flowMin(f);
    const x1 = a[0] - mn[0];
    const y1 = a[1] - mn[1];
    const x2 = t[0] - mn[0];
    const y2 = t[1] - mn[1];
    const cx = (x2 - x1) * 0.45;
    return `M ${x1} ${y1} C ${x1 + cx} ${y1}, ${x2 - cx} ${y2}, ${x2} ${y2}`;
  }

  private flowFromName(f: Flow): string {
    const b = this.boards.find((x: Board): boolean => x.id === f.fromBoard);
    const n = b?.layers.find((l: LayerNode): boolean => l.id === f.fromNode);
    return n ? n.name : f.fromNode;
  }

  private flowToName(f: Flow): string {
    return this.boardName(f.toBoard);
  }

  /** 药丸/建流 toast 共用的触发语料（batch-4 定义、batch-6 复用避免口径互斥）：触发节点文字
   * trim 后前 10 字（无文字回退节点 id，再兜底 'tap'）。 */
  private flowLabelTl(f: Flow): string {
    const b = this.boards.find((x: Board): boolean => x.id === f.fromBoard);
    const n = b?.layers.find((l: LayerNode): boolean => l.id === f.fromNode);
    let tl = '';
    if (n) {
      tl = n.style.text.trim().slice(0, 10);
      if (tl === '') tl = n.id;
    }
    if (tl === '') tl = 'tap';
    return tl;
  }

  /** 药丸标签（batch-4，gap-detail-10 后半，对齐 i:1909-1910）：触发语料 → 目标板 **id**
   * （板 id 对用户定位画布卡片更直接，桌面同款）。左栏流程行维持 name→板名 可读语义，
   * 两处差异已在行处注释登记。 */
  private flowPillLabel(f: Flow): string {
    return `${this.flowLabelTl(f)} → ${f.toBoard}`;
  }

  /** 连线药丸实测宽（batch-2，audit-canvas-9）：每条流挂载时 onAreaChange 实测入 Map，
   * x=曲线中点−w/2 居中消费；未测得（首帧竞态）回退 120——与旧固定 −60 等宽。 */
  private pillW: Map<string, number> = new Map();

  private flowPillW(f: Flow): number {
    return this.pillW.get(f.id) ?? 120;
  }

  /** 触发节点出向流清单（batch-4 触发标注消费）。 */
  private flowsFrom(b: Board, l: LayerNode): Flow[] {
    return this.flows.filter((f: Flow): boolean => f.fromBoard === b.id && f.fromNode === l.id);
  }

  /** 触发标注小绿字文案（batch-4，gap-detail-11，对齐 i:1841 实文含「点击「」包裹）：
   * 触发节点文字 trim 前 12 字 → 「点击「前12字」 → 目标板id」；无文字回退 `trigger → 板id`。 */
  private flowTriggerLabel(f: Flow): string {
    const b = this.boards.find((x: Board): boolean => x.id === f.fromBoard);
    const n = b?.layers.find((l: LayerNode): boolean => l.id === f.fromNode);
    const t = n !== undefined && n.style.text !== '' ? n.style.text.trim().slice(0, 12) : '';
    return t !== '' ? `点击「${t}」 → ${f.toBoard}` : `${f.trigger || 'tap'} → ${f.toBoard}`;
  }

  // ===== 演示模式（gap-canvas-7/8：起点页进入 + 返回栈 + interact 消费 + back 兜底）=====

  private exitDemo(): void {
    this.showDemo = false;
    // batch-10（spec-ink-1）：退出演示置脏——墨迹为本批新增持久化载荷，统一在出口落脏
    //（blanket 登记：非批注演示也置脏，宁误脏不丢墨）；标注态一并复位（热区恢复交互）
    this.demoInk = false;
    appStore.dirty = true;
    this.selBoard = this.demoFromBoard !== '' && this.boards.some((b: Board): boolean => b.id === this.demoFromBoard)
      ? this.demoFromBoard : (this.boards.length > 0 ? this.boards[0].id : '');
    this.selLayer = this.demoFromLayer;
    this.refocusRoot();   // 焦点归还 planRoot：演示叠层的焦点锚随叠层销毁，不回焦则键盘链失活
  }

  /** 演示唯一入口（顶栏 ▶ / 右键菜单共用）：永远从起点页=第一板开始，带返回栈；
   * 非 tap 绑定如实计数提示（对齐 i:2898-2899）。 */
  private actDemoEntry(): void {
    if (this.boards.length === 0) {
      this.toast('先创建画板，再进入演示');
      return;
    }
    let nonTap = 0;
    for (const b of this.boards) {
      for (const l of b.layers) {
        nonTap += this.layerInteractions(l).filter((ix: Interaction): boolean => ix.trigger !== 'tap').length;
      }
    }
    if (nonTap > 0) {
      this.toast(`${nonTap} 个非 tap 绑定在演示中不生效`);
    }
    this.demoFromBoard = this.selBoard;
    this.demoFromLayer = this.selLayer;
    this.selLayer = '';
    this.pendingFromBoard = '';
    this.pendingFromNode = '';
    this.toolMode = 'select';
    // 内联编辑/行内 Agent 浮层若在进演示前开启：一并收起（r3 抢修缺口 3 可达性）——
    // 两者与 demoCover 同页竞争 defaultFocus(true)，焦点落点不定会让 Esc 键锚失效；
    // 浮层 z 在演示叠层之下，留着也只是不可达残影。
    this.cancelInline();
    this.inlineAgent = false;
    // batch-11（spec-demo-2 起点页铁律）：演示永远从 entryBoard 开始（canonical=frontmatter
    // entry；interim/新建=首板，失存兜底回首板——行为不回退）
    const start = appStore.entryBoard !== '' &&
      this.boards.some((b: Board): boolean => b.id === appStore.entryBoard)
      ? appStore.entryBoard : this.boards[0].id;
    this.demoStack = [start];
    this.demoBoard = start;
    // batch-10（spec-ink-1）：进演示重放既有墨迹（AppStore.ink 内存态；标注态默认关）
    this.demoInk = false;
    this.inkStrokes = appStore.ink.strokes.map((s: number[][]): number[][] => s.slice());
    this.showDemo = true;
    // batch-13（验收 r8「首进 0/11」加固）：onReady/背景 onAreaChange 双钩子之外再加两拍
    // 延迟重放——覆盖 Canvas 内部异步沉降/焦点切换等未知时序（宁多绘一次不欠绘）；
    // 退出演示后不再绘（showDemo 门），ddInk 日志可判每次重放的笔数与尺寸
    setTimeout((): void => {
      if (this.showDemo) {
        this.redrawInk();
      }
    }, 120);
    setTimeout((): void => {
      if (this.showDemo) {
        this.redrawInk();
      }
    }, 400);
  }

  /** 返回上一层：弹栈回上一板；栈底提示不退出（退出唯一入口=HUD 退出按钮，对齐 i:3553-3564）。
   * 栈底文案对齐 gap-detail-19 登记的触屏改写：HUD 有退出钮，提示用户出口在哪。 */
  private demoBack(): void {
    if (this.demoStack.length > 1) {
      this.demoDir = -1;   // batch-5 iss-6：返回=反向入场（playInBack 语义）
      this.demoStack.splice(this.demoStack.length - 1, 1);
      this.demoBoard = this.demoStack[this.demoStack.length - 1];
    } else {
      this.toast('已是起始页 · 点退出演示结束');
    }
  }

  // ===== 演示批注墨迹（batch-10，spec-ink-1）=====
  private inkCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private inkDrawing: boolean = false;     // 当前笔迹进行中（Down→Up）
  private inkCurrent: number[][] = [];     // 当前笔迹点列（归一化 0–1）
  private inkReady: boolean = false;       // Canvas onReady 已过（batch-13 诊断：ddInk 日志判据）

  /** 标注开关：开启=墨迹层吃触摸（热区暂停、标注优先），关闭=恢复交互；toast 即时反馈。 */
  private toggleInk(): void {
    this.demoInk = !this.demoInk;
    this.toast(this.demoInk ? '标注开启 · 热区交互已暂停（Esc 退出标注）' : '标注关闭');
  }

  /** 清除：仅清内存墨迹（AppStore.ink 同步清空；dirty 在 exitDemo 统一置）。 */
  private clearInk(): void {
    this.inkStrokes = [];
    this.inkCurrent = [];
    this.inkDrawing = false;
    appStore.setInk([]);
    this.redrawInk();
    this.toast('已清除批注');
  }

  private inkNormX(px: number): number {
    return this.dw > 0 ? Math.round((px / this.dw) * 10000) / 10000 : 0;
  }

  private inkNormY(py: number): number {
    return this.dh > 0 ? Math.round((py / this.dh) * 10000) / 10000 : 0;
  }

  /** 画笔样式（橙 #E67E22 / 2.6 / 圆头圆角——桌面 ink 同参数）。 */
  private inkStyle(): void {
    this.inkCtx.lineWidth = 2.6;
    this.inkCtx.strokeStyle = '#E67E22';
    this.inkCtx.lineCap = 'round';
    this.inkCtx.lineJoin = 'round';
  }

  /** 全量重放（onReady/onAreaChange/清除后）：已落笔迹 + 进行中笔迹按当前封面尺寸重画。 */
  private redrawInk(): void {
    const w = this.dw;
    const h = this.dh;
    if (w <= 0 || h <= 0) return;
    this.inkCtx.clearRect(0, 0, w, h);
    this.inkStyle();
    const all = this.inkDrawing && this.inkCurrent.length > 1
      ? this.inkStrokes.concat([this.inkCurrent]) : this.inkStrokes;
    // batch-13 诊断（验收 r8「首进 0/11」复测判据）：每次重放留痕——笔数与实测尺寸，
    // 若复测仍空而本日志 strokes>0 且 dw/dh>0，即坐实「绘了但被清/被盖」而非「未绘」
    hilog.info(0x0000, 'ddInk', 'redraw strokes=%{public}d dw=%{public}s dh=%{public}s ready=%{public}s',
      all.length, w.toString(), h.toString(), this.inkReady.toString());
    for (const s of all) {
      if (s.length < 2) continue;
      this.inkCtx.beginPath();
      this.inkCtx.moveTo(s[0][0] * w, s[0][1] * h);
      if (s.length === 2) {
        this.inkCtx.lineTo(s[1][0] * w, s[1][1] * h);
      } else {
        // 中点二次贝塞尔平滑：相邻中点为端点、原点为控制点（桌面 ink 同算法）
        for (let i = 1; i < s.length - 1; i++) {
          const mx = (s[i][0] + s[i + 1][0]) / 2;
          const my = (s[i][1] + s[i + 1][1]) / 2;
          this.inkCtx.quadraticCurveTo(s[i][0] * w, s[i][1] * h, mx * w, my * h);
        }
        this.inkCtx.lineTo(s[s.length - 1][0] * w, s[s.length - 1][1] * h);
      }
      this.inkCtx.stroke();
    }
  }

  /** 增量画尾段（Move）：只画最新中点二次段，免全量重放卡顿。 */
  private drawStrokeTail(): void {
    const w = this.dw;
    const h = this.dh;
    if (w <= 0 || h <= 0) return;
    const s = this.inkCurrent;
    const n = s.length;
    if (n < 2) return;
    this.inkCtx.beginPath();
    if (n === 2) {
      this.inkCtx.moveTo(s[0][0] * w, s[0][1] * h);
      this.inkCtx.lineTo(s[1][0] * w, s[1][1] * h);
    } else {
      const m1x = (s[n - 3][0] + s[n - 2][0]) / 2;
      const m1y = (s[n - 3][1] + s[n - 2][1]) / 2;
      const m2x = (s[n - 2][0] + s[n - 1][0]) / 2;
      const m2y = (s[n - 2][1] + s[n - 1][1]) / 2;
      this.inkCtx.moveTo(m1x * w, m1y * h);
      this.inkCtx.quadraticCurveTo(s[n - 2][0] * w, s[n - 2][1] * h, m2x * w, m2y * h);
    }
    this.inkCtx.stroke();
  }

  /** 形似返回的元素兜底挂 back（对齐桌面 isBackish i:3545-3551，词边界匹配）。 */
  private isBackish(l: LayerNode): boolean {
    const t = `${l.name} ${l.style.text}`;
    return /(^|[^a-za-z])(back|prev|返回|←)(?![a-za-z])/i.test(t);
  }

  /** 演示可点节点：有 flow / 有 tap 绑定 / isBackish（热区视觉与点击消费同表）。 */
  private demoClickable(b: Board, l: LayerNode): boolean {
    if (this.flows.some((f: Flow): boolean => f.fromBoard === b.id && f.fromNode === l.id)) return true;
    if (this.layerInteractions(l).some((ix: Interaction): boolean => ix.trigger === 'tap')) return true;
    return this.isBackish(l);
  }

  private demoCur(): Board | null {
    return this.boards.find((b: Board): boolean => b.id === this.demoBoard) ?? null;
  }

  /** 演示适配：板完整入 cover（batch-2，audit-canvas-4：去 min(…,1) 上限——桌面 play
   * 适配可放大铺满，小板不再钳 100%）。 */
  private demoZoom(): number {
    const b = this.demoCur();
    if (!b || this.dw <= 0 || this.dh <= 0) return 1;
    return Math.min((this.dw - 64) / b.width, (this.dh - 96) / b.height);
  }

  /** 演示当前板的单元素列表（batch-repair）：供 ForEach([board]) 模式取非空局部 b——
   * 替代分支内 `demoCur()!` 裸断言（细粒度更新瞬态 null 即崩，同 selLayerOf 防护口径）。 */
  private demoBoardList(): Board[] {
    const b = this.demoCur();
    return b !== null ? [b] : [];
  }

  /** 演示中点击节点：flow 优先；其次 tap 绑定 navigate_to/show_toast/back；
   * isBackish 兜底 back；无绑定如实提示（set_text/set_state ohos 面不存在）。 */
  private demoTap(fromBoard: string, fromNode: string): void {
    const f = this.flows.find((x: Flow): boolean => x.fromBoard === fromBoard && x.fromNode === fromNode);
    if (f) {
      if (f.toBoard !== this.demoBoard) {
        this.demoDir = 1;   // batch-5 iss-6：前进=正向入场
        this.demoStack.push(f.toBoard);
        this.demoBoard = f.toBoard;
      }
      this.toast(`跳转 → ${this.boardName(f.toBoard)}`);
      return;
    }
    const b = this.boards.find((x: Board): boolean => x.id === fromBoard);
    const l = b?.layers.find((x: LayerNode): boolean => x.id === fromNode);
    if (!b || !l) return;
    const ix = this.layerInteractions(l).find((it: Interaction): boolean => it.trigger === 'tap');
    if (ix) {
      if (ix.action === 'navigate_to') {
        if (ix.target === '') {
          this.toast('该绑定未设置目标画板');
          return;
        }
        this.demoStack.push(ix.target);
        this.demoDir = 1;   // batch-5 iss-6：前进=正向入场
        this.demoBoard = ix.target;
        this.toast(`跳转 → ${this.boardName(ix.target)}`);
      } else if (ix.action === 'show_toast') {
        this.toast(ix.target);
      } else if (ix.action === 'back') {
        this.demoBack();
      }
      return;
    }
    if (this.isBackish(l)) {
      this.demoBack();
      return;
    }
    this.toast(`「${l.id}」未链接交互流`);   // 文案对齐 i:3541（batch-6，gap-detail-19）
  }

  // ===== 双击内联改字（gap-canvas-3）=====

  private startInlineEdit(b: Board, l: LayerNode): void {
    if (this.showDemo) return;
    if (l.type === 'image') {
      this.toast('图片节点请使用 Agent 添加说明');   // 文案对齐 i:2233（batch-6，gap-detail-19）
      return;
    }
    const org = this.boardOriginStack(b);   // batch-6：Stack-local 换基（编辑框 .position 在内容 Stack 内）
    const z = this.zoomOf(b);
    this.inlineBoard = b.id;
    this.inlineLayer = l.id;
    this.inlineVal = l.style.text;
    // 右/下界钳制（gap-canvas-18，对齐 i:2238-2239）：编辑框不出画布
    this.inlineX = Math.min(Math.max(8, org[0] + l.style.x * z), Math.max(8, this.cw - 230));
    this.inlineY = Math.min(Math.max(40, org[1] + l.style.y * z), Math.max(40, this.ch - 46));
    this.selLayer = l.id;
    this.sync();   // 双击编辑同时改变选中：inspector 草稿同步装载（同 canvas 点击路径）
    this.inlineSelArmed = true;   // 打开即全选原文（onFocus armed 门控，用后即清）
    this.showInline = true;
  }

  private commitInline(): void {
    const b = this.inlineBoard;
    const l = this.inlineLayer;
    const v = this.inlineVal;
    this.showInline = false;
    this.inlineBoard = '';
    this.inlineLayer = '';
    if (b === '' || l === '') return;
    appStore.setStyle(b, l, 'text', v);
    this.sync();
  }

  private cancelInline(): void {
    this.showInline = false;
    this.inlineBoard = '';
    this.inlineLayer = '';
  }

  // ===== 点击消费门（替代 stopPropagation：本 SDK ClickEvent 无该方法，编译门实证）=====

  /** 子层（节点/✕）已处理点击时调用；父层随后用 clickConsumed() 识别并跳过。 */
  private consumeClick(): void {
    this.clickGateTs = Date.now();
  }

  /** 250ms 窗口内视为被子层消费；未配对消费时窗口自愈，不留死门。 */
  private clickConsumed(): boolean {
    if (Date.now() - this.clickGateTs < 250) {
      this.clickGateTs = 0;
      return true;
    }
    return false;
  }

  // ===== 三模式（gap-topbar-3）=====

  private isWire(): boolean {
    return this.modeIdx === 0;
  }

  /** 左栏 tab 选中分色（batch-6，audit-left-2 对齐 i:125-127）：图层=accTx（浅 #0066d6）/
   * AI 组件=#7c3aed（字面量两主题同值——现 purple #9d4edd 色相偏，登记同 flowStroke 法）/
   * 流程=ok。 */
  private tabColor(i: number): string {
    if (i === 1) return '#7c3aed';
    if (i === 2) return this.T().ok;
    return this.T().accTx;
  }

  /** 左栏 tab on 态 tint 底（batch-6，audit-left-2：按 tab 分色同源 4% 透明度）。 */
  private tabTint(i: number): string {
    if (i === 1) return 'rgba(124,58,237,0.04)';
    if (i === 2) return 'rgba(40,167,69,0.04)';
    return 'rgba(0,122,255,0.04)';
  }

  /** 类别名中文映射（batch-6，audit-left-8 对齐 i:2940 COMP_META：九类，未知回退原文）。 */
  private catLabel(cat: string): string {
    if (cat === 'user') return '我的组件';
    if (cat === 'actions') return '操作';
    if (cat === 'inputs') return '输入';
    if (cat === 'selection') return '选择';
    if (cat === 'display') return '展示';
    if (cat === 'layout') return '布局';
    if (cat === 'navigation') return '导航';
    if (cat === 'feedback') return '反馈';
    if (cat === 'overlay') return '浮层';
    return cat;
  }

  /** 图层行图标字符（batch-6，audit-left-4 对齐 i:2065-2081 layerIcon 同表关键词扩 10 类+
   * 兜底；字符近似——nav/switch/feedback 必须可辨（泛型 ▢ 不再出现于这三类）。
   * 关键词源=type+name（LayerNode 无 component 字段——引擎侧归 gap-global-3 接线）。 */
  private layerIcon(l: LayerNode): string {
    const c = (l.type + ' ' + l.name).toLowerCase();
    const has = (...ws: string[]): boolean => ws.some((w: string): boolean => c.includes(w));
    if (has('input', 'search', 'textarea')) return '▭';
    if (has('button', 'fab', 'cta')) return '⬒';
    if (has('image', 'photo')) return '◉';
    if (has('divider')) return '—';
    if (has('switch', 'checkbox', 'radio', 'check')) return '☑';
    if (has('badge', 'tag', 'chip')) return '●';
    if (has('nav', 'tab')) return '▤';
    if (has('progress', 'spinner', 'toast', 'dialog', 'sheet', 'snack', 'feedback')) return '⚑';
    if (has('icon')) return '★';
    if (l.type === 'text' || has('text', 'heading', 'label', 'title', 'caption', 'body')) return 'T';
    return '▢';
  }

  /** 组件格预览（batch-6，audit-left-8：按组件 id 关键词建映射——button/input/search/slider/
   * checkbox/switch 可辨；未命中回退 kind 泛型）。 */
  @Builder
  compPrev(c: CompDef) {
    if (c.id.includes('button') || c.id.includes('btn')) {
      Rect({ width: 26, height: 10 }).radius(5).fill(this.T().acc).opacity(0.85)
    } else if (c.id.includes('search')) {
      Row({ space: 2 }) {
        Rect({ width: 16, height: 10 }).radius(2).fill(this.T().card).stroke(this.T().lineStrong)
        Circle({ width: 7, height: 7 }).fill(this.T().accSoft).stroke(this.T().lineStrong)
      }.alignItems(VerticalAlign.Center)
    } else if (c.id.includes('input') || c.id.includes('textarea')) {
      Column({ space: 2 }) {
        Rect({ width: 26, height: 10 }).radius(2).fill(this.T().card).stroke(this.T().lineStrong)
        Rect({ width: 16, height: 1.5 }).fill(this.T().tx3).opacity(0.5)
      }
    } else if (c.id.includes('slider')) {
      Stack({ alignContent: Alignment.Start }) {
        Rect({ width: 26, height: 2 }).fill(this.T().lineStrong)
        Circle({ width: 8, height: 8 }).fill(this.T().acc).margin({ left: 9 })
      }.width(26).height(10)
    } else if (c.id.includes('checkbox') || c.id.includes('check')) {
      Row({ space: 2 }) {
        Rect({ width: 9, height: 9 }).radius(2).fill(this.T().card).stroke(this.T().acc)
        Rect({ width: 14, height: 2 }).radius(1).fill(this.T().tx3).opacity(0.5)
      }.alignItems(VerticalAlign.Center)
    } else if (c.id.includes('switch')) {
      Stack({ alignContent: Alignment.End }) {
        Rect({ width: 20, height: 10 }).radius(5).fill(this.T().acc).opacity(0.55)
        Circle({ width: 8, height: 8 }).fill(this.T().card).margin({ right: 1 })
      }.width(20).height(10)
    } else if (c.kind === 'text') {
      Text('T').fontSize(14).fontWeight(700).fontColor(this.T().accTx).height(22)
    } else if (c.kind === 'image') {
      Circle({ width: 20, height: 20 }).fill(this.T().accSoft)
    } else if (c.kind === 'frame') {
      Rect({ width: 26, height: 18 }).radius(3).fill(this.T().subtle).stroke(this.T().acc)
    } else {
      Rect({ width: 24, height: 16 }).radius(3).fill(this.T().accSoft)
    }
  }

  /** 线型三态 dasharray 映射（batch-5，gap-detail-12）：dashed 4/3（旧布尔真值同款）、
   * dotted 1/3（近似登记——SVG 点线视觉）、solid 无（[1,0] 实线）。 */
  private dashArray(dash: string): number[] {
    if (dash === 'dashed') return [4, 3];
    if (dash === 'dotted') return [1, 3];
    return [1, 0];
  }

  /** 阴影三档（batch-10，复审 finding-4 补全参数）。引擎滤镜实参（本轮 wasm 探针实跑
   * web_login defs 提取：e1 dy=1/σ=2/α=0.07、e2 dy=4/σ=10/α=0.10、e3 dy=14/σ=28/α=0.16，
   * 区域 x/y=-30% width=160%）→ ArkUI radius≈2σ 折算：sm→e1{radius 4, offsetY 1,
   * #12000000}、lg→e2{radius 20, offsetY 4, #1A000000}、xl→e3{radius 56, offsetY 14,
   * #29000000}（α×255 取整；视觉校准归模拟器）。值域约定（双批协同）：渲染器只认
   * none|sm|lg|xl（ElStyle.shadow 现值域），未知值一律降级 none——桌面 canonical 的
   * e1/e2/e3 命名由解析边界归一（batch-5 捕获），渲染侧不静默错渲；gap-detail-12 值域
   * 差异登记更新为「解析归一 + 渲染单值域」方案。仅高保真档渲染（消费点两壳 isWire
   * 门控），线框档不挂（桌面 filter:none）。 */
  private shadowOf(v: string): ShadowOptions {
    if (v === 'sm') return { radius: 4, offsetX: 0, offsetY: 1, color: '#12000000' };
    if (v === 'lg') return { radius: 20, offsetX: 0, offsetY: 4, color: '#1A000000' };
    if (v === 'xl') return { radius: 56, offsetX: 0, offsetY: 14, color: '#29000000' };
    return { radius: 0, offsetX: 0, offsetY: 0, color: this.T().trans };
  }

  // ===== 主题（batch-1，audit-modal-3/4：5 主题×深浅分发；原 gap-settings-2 双档）=====

  private isDark(): boolean {
    return this.themeChoice === 'dark' || (this.themeChoice === 'system' && this.sysDark);
  }

  private T(): ThemeColors {
    const dark: boolean = this.isDark();
    if (this.themeId === 'hmos') {
      // iss-4：鸿蒙原生主题（缺此分支会静默回落 mac 表——分支只路由 win11/deep/neu/glass 的旧现状）
      return dark ? THEME_HMOS_D : THEME_HMOS_L;
    }
    if (this.themeId === 'win11') {
      return dark ? THEME_WIN11_D : THEME_WIN11_L;
    }
    if (this.themeId === 'deep') {
      return dark ? THEME_DEEP_D : THEME_DEEP_L;
    }
    if (this.themeId === 'neu') {
      return dark ? THEME_NEU_D : THEME_NEU_L;
    }
    if (this.themeId === 'glass') {
      return dark ? THEME_GLASS_D : THEME_GLASS_L;
    }
    return dark ? THEME_MAC_D : THEME_MAC_L;
  }

  /** 外观偏好落盘（batch-1，audit-modal-4：主题与深浅档经 preferences 持久化）。 */
  private saveLook(): void {
    const look: UiLook = { themeId: this.themeId, mode: this.themeChoice === 'dark' ? 'dark' : 'light' };
    uiPrefs.save(look);
    this.applyColorMode();   // iss-4：深浅档切换同步覆写应用颜色模式（dd_* 资源自动换值）
  }

  /**
   * 深浅色资源化接线（batch-1，iss-4）：应用态覆写颜色模式——EntryAbility.onCreate 每次启动
   * 重置 NOT_SET（启动窗按系统档渲染），此处由应用态覆写，resources base/dark 的 dd_* 资源
   * 随之自动换值（baseline §7.1 同名异值机制）。
   * 登记 baseline §7.4：手动 setColorMode 后 onConfigurationUpdate 不再回调——
   * @StorageProp ddSysDark 仅 isDark() 的 legacy 'system' 分支消费，themeChoice 已归一
   * light|dark 双档，该分支不可达（登记为已知不可达）。
   * 【待模拟器验证】setColorMode 跨重启持久性未验证（验收判据 3）：本实现保留 onCreate
   * 重置 + aboutToAppear 应用态覆写的双段语义；若验证发现持久且覆写引入启动窗闪烁，
   * 按复审修订评估移除 onCreate 重置/门控，禁止静默。
   */
  private applyColorMode(): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.getApplicationContext().setColorMode(this.themeChoice === 'dark'
        ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } catch (e) {
      hilog.error(0x0000, 'ddLook', 'setColorMode failed: %{public}s', (e as Error).message);
    }
  }

  /**
   * 滚动条 thumb 色（batch-1，audit-left-12 对齐 i:24-33）：浅 rgba(0,0,0,.18) /
   * 深 rgba(255,255,255,.22)；deep/glass 浅档本身即暗底主题，桌面选择器同样命中白 thumb
   * （i:29-30 data-theme 深底主题并列）。hover 加深档（i:32-33）ArkUI scrollBar 无 hover 态，
   * 登记不取；thumb 圆角为 scrollBar 固有样式（width 6px 即细圆条）。
   * iss-4：HMOS 主题无需特判——浅档画布 #F1F3F5 为浅底走默认浅 thumb 分支，
   * 深档由 isDark() 分支覆盖。
   */
  private scrollThumb(): string {
    if (this.isDark() || this.themeId === 'deep' || this.themeId === 'glass') {
      return 'rgba(255,255,255,0.22)';
    }
    return 'rgba(0,0,0,0.18)';
  }

  // ===== MBT 源码查看器（gap-mbt-7/9/10：token 色 / 代码面双档 / stage-veil）=====

  /** 七类 token 色（gap-mbt-7）：按 isDark() 双档，值实测抄录 i:48-49（亮）/ i:59-60（暗）；
   * yaml-key 同 keyword、yaml-val 同 string（桌面 --tok-* 别名同构）。 */
  private tokColor(cls: string): string {
    const dark: boolean = this.isDark();
    if (cls === 'comment') {
      return dark ? '#6B7A93' : '#8A94A6';
    }
    if (cls === 'string') {
      return dark ? '#9ECE6A' : '#0A7D33';
    }
    if (cls === 'number') {
      return dark ? '#FF9E64' : '#B3541E';
    }
    if (cls === 'keyword' || cls === 'yaml-key') {
      return dark ? '#BB9AF7' : '#8250DF';
    }
    if (cls === 'type') {
      return dark ? '#7DCFFF' : '#0550AE';
    }
    return dark ? '#9ECE6A' : '#0A7D33';   // yaml-val 同 string
  }

  /** 代码面底/边色（gap-mbt-10）：--code-bg/--code-line 双档（i:45-46 亮 / i:57-58 暗）。 */
  private codeBg(): string {
    return this.isDark() ? '#0F1420' : '#FCFDFF';
  }

  private codeLine(): string {
    return this.isDark() ? '#232A38' : 'rgba(15,23,42,0.14)';
  }

  /** stage-veil 底色（gap-mbt-10）：i:50 亮 rgba(255,255,255,.6) / i:61 暗 rgba(13,15,22,.55)。 */
  private stageVeil(): string {
    return this.isDark() ? 'rgba(13,15,22,0.55)' : 'rgba(255,255,255,0.6)';
  }

  /**
   * MBT 源码切片（gap-mbt-7）：桌面 mbtHighlight（frontend i:2678-2737）的 ArkTS 移植，
   * 七类 token。本实现已与桌面原版在 7 组输入上逐 span 对拍一致
   * （canonical 全文 / 带 flows canonical / 无 frontmatter / 未闭合字符串 / 跨行块注释 /
   * 字符串内 // / 非 --- 开头）。
   * ⚠️ 返回序=桌面同款插入序（base 段在前、yaml 段追加在后，未排序）——消费侧
   * （declPieceRows）必须先排序再 emit（桌面 mbtHighlightHTML 未排序是潜在缺陷，
   * 登记 gap-mbt-7 注释；桌面 decl 视图常显 interim 文本从未触发）。
   * 桌面 quirk 同构保留（不擅自改语义，引擎接线后若桌面修切器同步对齐）：
   * yaml-key 命中区间=「键尾+冒号」（keyRe 捕获组偏移所致，顶层键即冒号本身）；
   * yaml-val 仅命中「- 值」列表行——「键: 值」行的值因 (?=\s*$) 前瞻被冒号挡住不着
   * yaml-val 色，数字值经缝隙 classify 落 tok-number（桌面实测一致）。
   */
  private mbtSpans(text: string): MbtSpan[] {
    const spans: MbtSpan[] = [];
    let i = 0;
    const n = text.length;
    while (i < n) {
      const ch = text.charAt(i);
      if (ch === '/' && i + 1 < n && text.charAt(i + 1) === '/') {
        let j = text.indexOf('\n', i);
        if (j < 0) {
          j = n;
        }
        spans.push({ s: i, e: j, cls: 'comment' });
        i = j;
        continue;
      }
      if (ch === '/' && i + 1 < n && text.charAt(i + 1) === '*') {
        let j = text.indexOf('*/', i + 2);
        j = j < 0 ? n : j + 2;
        spans.push({ s: i, e: j, cls: 'comment' });
        i = j;
        continue;
      }
      if (ch === '"') {
        let j = i + 1;
        while (j < n) {
          if (text.charAt(j) === '\\') {
            j += 2;
          } else if (text.charAt(j) === '"') {
            j++;
            break;
          } else {
            j++;
          }
        }
        spans.push({ s: i, e: j, cls: 'string' });
        i = j;
        continue;
      }
      i++;
    }
    // frontmatter（首个 --- ... ---）YAML key/val（桌面同构，含上述 quirk）
    if (text.startsWith('---')) {
      let fmEnd = text.indexOf('\n---', 3);
      fmEnd = fmEnd < 0 ? 0 : fmEnd + 5;
      if (fmEnd > 0) {
        const fm = text.substring(0, fmEnd);
        const keyRe = new RegExp('^\\s*([A-Za-z_][\\w-]*)(:)', 'gm');
        let m = keyRe.exec(fm);
        while (m !== null) {
          spans.push({ s: m.index + m[1].length, e: m.index + m[0].length, cls: 'yaml-key' });
          m = keyRe.exec(fm);
        }
        const valRe = new RegExp('^\\s+(?:-\\s+)?([\\w.\\/\\-]+)(?=\\s*$)', 'gm');
        m = valRe.exec(fm);
        while (m !== null) {
          spans.push({ s: m.index + m[0].length - m[1].length, e: m.index + m[0].length, cls: 'yaml-val' });
          m = valRe.exec(fm);
        }
      }
    }
    // 缝隙区 classify：keyword/type/number 三族标记按起点排序后不重叠输出（桌面 classify 同构）
    const out: MbtSpan[] = [];
    const kwRe = new RegExp('\\b(?:fn|let|mut|struct|enum|trait|impl|if|else|match|while|for|in|loop|return|break|continue|type|pub|priv|const|static|as|is|and|or|not|xor|test|init|async|await|throw|try|catch|guard|using|sub|with|derive)\\b', 'g');
    const tyRe = new RegExp('\\b[A-Z][A-Za-z0-9_]*\\b', 'g');
    const numRe = new RegExp('\\b(?:0x[0-9a-fA-F_]+|0o[0-7_]+|0b[01_]+|\\d[\\d_]*(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b', 'g');
    const classify = (a: number, b: number): void => {
      if (a >= b) {
        return;
      }
      const seg = text.substring(a, b);
      const marks: MbtSpan[] = [];
      let m = kwRe.exec(seg);
      while (m !== null) {
        marks.push({ s: m.index, e: m.index + m[0].length, cls: 'keyword' });
        m = kwRe.exec(seg);
      }
      m = tyRe.exec(seg);
      while (m !== null) {
        marks.push({ s: m.index, e: m.index + m[0].length, cls: 'type' });
        m = tyRe.exec(seg);
      }
      m = numRe.exec(seg);
      while (m !== null) {
        marks.push({ s: m.index, e: m.index + m[0].length, cls: 'number' });
        m = numRe.exec(seg);
      }
      marks.sort((x: MbtSpan, y: MbtSpan): number => x.s - y.s || y.e - x.e);
      let p = 0;
      for (const mk of marks) {
        if (mk.s >= p) {
          out.push({ s: a + mk.s, e: a + mk.e, cls: mk.cls });
          p = mk.e;
        }
      }
    };
    let last = 0;
    for (const sp of spans) {
      if (sp.s > last) {
        classify(last, sp.s);
      }
      out.push({ s: sp.s, e: sp.e, cls: sp.cls });
      last = sp.e;
    }
    if (last < n) {
      classify(last, n);
    }
    return out;
  }

  /**
   * 高亮按行拆分（gap-mbt-7）：Span 内 \n 渲染 d.ts 无契约（留待模拟器实测）——直接采用
   * 按行拆分渲染（每行一个 Text 承载一组 Span，Column 堆叠），跨行选择诚实降级，
   * 复制源码仍走 copySource 全文通道。空行补单空格片段保行高。
   */
  private declPieceRows(): DeclPiece[][] {
    const text = this.declText;
    const rows: DeclPiece[][] = [];
    let cur: DeclPiece[] = [];
    const emit = (t: string, cls: string): void => {
      let start = 0;
      for (let k = 0; k < t.length; k++) {
        if (t.charAt(k) === '\n') {
          if (k > start) {
            cur.push({ t: t.substring(start, k), cls: cls });
          }
          rows.push(cur);
          cur = [];
          start = k + 1;
        }
      }
      if (start < t.length) {
        cur.push({ t: t.substring(start), cls: cls });
      }
    };
    const spans = this.mbtSpans(text);
    // 消费前排序+重叠防护（登记性修正）：桌面 mbtHighlight 把 yaml 段追加在 base 段之后
    // 且 mbtHighlightHTML 按插入序消费——canonical 输入（frontmatter+正文串并存）上会重复
    // 染色重排文本（node 实证 8.7KB→42.8KB）；桌面 decl 视图常显 interim 文本从未触发。
    // 本侧排序后emit，畸形输入经 last 钳制永不重染。
    spans.sort((x: MbtSpan, y: MbtSpan): number => x.s - y.s || y.e - x.e);
    let last = 0;
    for (const sp of spans) {
      if (sp.e <= last) {
        continue;   // 完全被前段覆盖：跳过
      }
      if (sp.s > last) {
        emit(text.substring(last, sp.s), '');
      }
      const from: number = Math.max(sp.s, last);
      emit(text.substring(from, sp.e), sp.cls);
      last = sp.e;
    }
    if (last < text.length) {
      emit(text.substring(last), '');
    }
    rows.push(cur);
    return rows.map((row: DeclPiece[]): DeclPiece[] => row.length > 0 ? row : [{ t: ' ', cls: '' }]);
  }

  // ===== 焦点管理（修订 5：按键只派发给焦点组件，交互后必须显式回焦）=====

  private refocusRoot(): void {
    try {
      this.getUIContext().getFocusController().requestFocus('planRoot');
    } catch (e) {
      // 部分窗口态（sheet/cover 等模态在场）requestFocus 抛 150002（r2 验收实证）——
      // 吞掉：焦点回焦尽力而为，不阻断调用方 onClick 的后续语句。
    }
  }

  private onInputFocus(): void {
    this.inputFocused = true;
  }

  private onInputBlur(): void {
    this.inputFocused = false;
    // 延迟回焦：若焦点已移入另一输入框（inputFocused=true）则不抢
    setTimeout((): void => {
      if (!this.inputFocused) {
        this.refocusRoot();
      }
    }, 80);
  }

  /** 复制源码到系统剪贴板（@ohos.pasteboard）。 */
  private copySource(): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.declText);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.toast('源码已复制到剪贴板');
    }).catch((): void => {
      this.toast('复制失败');
    });
  }

  // batch-4（gap-mbt-11）：declSelectAll（⌘A 全选，gap-canvas-5）随「⌿ 全选」菜单项移除——
  // 只读 Text+Span 形态无 TextArea 可聚焦/选择（batch-3 起即 try/catch 兜底无操作），
  // 复制源码（copySource 全文）是复制能力的唯一通道，去留评估留痕见 declMenu 注释。

  /**
   * 重新序列化刷新（batch-4，gap-mbt-11；原 validateSource 重写，旧名 retire）：以画布
   * 当前态为事实源——toCanonicalText() 重投影 declText + sync() + 时间线 revalidate 留痕，
   * 对齐桌面「画布→源码单向可信」。差异登记：桌面此入口可编辑草稿并走引擎全链校验渲染，
   * 本侧引擎未接线，改纯重投影（gap-global-3 引擎宿主下沉后回收完整链）。
   * JSON.parse→restore 应用路径移除（canonical 形状文本本就无法 JSON.parse，SER_PREFIX
   * 前缀检查随之失去意义）；appStore.restore 仅剩 persist 打开/自动恢复两个调用点。
   */
  private revalidateSource(): void {
    this.declText = appStore.toCanonicalText();
    this.sync();
    appStore.logCmd('HUMAN', 'revalidate', true);
    this.toast('已按画布当前态重新生成；引擎校验归引擎宿主下沉（gap-global-3）');
  }

  // ===== inspector 数值草稿态（gap-right-2：对齐「应用到中间态」）=====

  private loadDrafts(l: LayerNode): void {
    this.draftX = String(Math.round(l.style.x));
    this.draftY = String(Math.round(l.style.y));
    this.draftW = String(l.style.w);
    this.draftH = String(l.style.h);
    this.draftFontSize = String(l.style.fontSize);
    this.draftRadius = String(l.style.radius);
    this.draftOp = String(l.style.opacity);   // batch-5（audit-right-8）：0-1 口径（桌面同款）
    this.draftText = l.style.text;            // batch-5（audit-right-7）：草稿族扩容
    this.draftFill = l.style.fill;
    this.draftColor = l.style.color;
    this.draftStroke = l.style.stroke;
    this.draftStrokeW = String(l.style.strokeWidth);
    this.draftGap = String(l.style.gap);
    this.draftPad = String(l.style.padding);
    this.draftLoadedFor = this.selBoard + '/' + this.selLayer;
  }

  /** diff 后一次提交（仅变更项走 setStyle，一次 sync）。batch-5（audit-right-7）扩全字段：
   * 文本/填充/文字色/描边色/描边宽/间距/内边距入草稿组；透明度 0-1 去 0.05 下限钳
   * （audit-right-8：桌面 min 0，0 可提交节点消失）。 */
  private applyDrafts(): void {
    const b = this.curBoard();
    const l = this.curLayer();
    if (!b || !l) return;
    const num = (v: string, d: number): number => {
      const n = Number(v);
      return Number.isFinite(n) ? n : d;
    };
    const x = Math.max(0, num(this.draftX, l.style.x));
    const y = Math.max(0, num(this.draftY, l.style.y));
    const w = Math.max(1, num(this.draftW, l.style.w));
    const h = Math.max(1, num(this.draftH, l.style.h));
    const fsize = Math.max(1, num(this.draftFontSize, l.style.fontSize));
    const rad = Math.max(0, num(this.draftRadius, l.style.radius));
    const op = Math.min(1, Math.max(0, num(this.draftOp, l.style.opacity)));   // 0-1 无下限钳
    const sw = Math.max(0, num(this.draftStrokeW, l.style.strokeWidth));
    const gap = Math.max(0, num(this.draftGap, l.style.gap));
    const pad = Math.max(0, num(this.draftPad, l.style.padding));
    let n = 0;
    if (x !== l.style.x) { appStore.setStyle(b.id, l.id, 'x', x); n++; }
    if (y !== l.style.y) { appStore.setStyle(b.id, l.id, 'y', y); n++; }
    if (w !== l.style.w) { appStore.setStyle(b.id, l.id, 'w', w); n++; }
    if (h !== l.style.h) { appStore.setStyle(b.id, l.id, 'h', h); n++; }
    if (fsize !== l.style.fontSize) { appStore.setStyle(b.id, l.id, 'fontSize', fsize); n++; }
    if (rad !== l.style.radius) { appStore.setStyle(b.id, l.id, 'radius', rad); n++; }
    if (Math.abs(op - l.style.opacity) > 0.001) { appStore.setStyle(b.id, l.id, 'opacity', op); n++; }
    if (this.draftText !== l.style.text) { appStore.setStyle(b.id, l.id, 'text', this.draftText); n++; }
    // 颜色族：空串视为未填不提交（避免无效 hex 落盘）
    if (this.draftFill.trim() !== '' && this.draftFill !== l.style.fill) {
      appStore.setStyle(b.id, l.id, 'fill', this.draftFill.trim()); n++;
    }
    if (this.draftColor.trim() !== '' && this.draftColor !== l.style.color) {
      appStore.setStyle(b.id, l.id, 'color', this.draftColor.trim()); n++;
    }
    if (this.draftStroke.trim() !== '' && this.draftStroke !== l.style.stroke) {
      appStore.setStyle(b.id, l.id, 'stroke', this.draftStroke.trim()); n++;
    }
    if (sw !== l.style.strokeWidth) { appStore.setStyle(b.id, l.id, 'strokeWidth', sw); n++; }
    if (gap !== l.style.gap) { appStore.setStyle(b.id, l.id, 'gap', gap); n++; }
    if (pad !== l.style.padding) { appStore.setStyle(b.id, l.id, 'padding', pad); n++; }
    this.sync();
    this.toast(n > 0 ? `已应用 ${n} 项变更` : '无变更');
  }

  // ===== 交互绑定（gap-right-3）=====

  /** 触发器组（batch-4 dd-menu-trigger）：TRIGGERS 全档单组；选中态行内样式（原语
   * ✓列+accSoft+600，替旧 '✓ ' 文本前缀）。 */
  private triggerMenuGroups(): Array<DdMenuGroup> {
    const items: Array<DdMenuItem> = TRIGGERS.map((t: string): DdMenuItem => {
      return {
        label: t,
        kbd: '',
        selected: this.bindTrigger === t,
        danger: false,
        disabled: false,
        action: (): void => { this.bindTrigger = t; }
      };
    });
    const g: DdMenuGroup = { title: '', items: items };
    return [g];
  }

  /** 触发器面板：168 宽单组。 */
  @Builder
  triggerMenuPanel() {
    this.ddMenuPanel(168, this.triggerMenuGroups())
  }

  /** 目标画板组（batch-4 dd-menu-board）：boards 动态单组（label=b.name）；boards 空时
   * 空组（旧 MenuElement 空数组同行为）。 */
  private boardMenuGroups(): Array<DdMenuGroup> {
    const items: Array<DdMenuItem> = this.boards.map((b: Board): DdMenuItem => {
      return {
        label: b.name,
        kbd: '',
        selected: this.bindTarget === b.id,
        danger: false,
        disabled: false,
        action: (): void => { this.bindTarget = b.id; }
      };
    });
    const g: DdMenuGroup = { title: '', items: items };
    return [g];
  }

  /** 目标画板面板：176 宽单组。 */
  @Builder
  boardMenuPanel() {
    this.ddMenuPanel(176, this.boardMenuGroups())
  }

  private addBinding(): void {
    const b = this.curBoard();
    const l = this.curLayer();
    if (!b || !l) return;
    let target = this.bindTarget;
    if (this.bindAction === 'navigate_to' && target === '') {
      this.toast('请先选择目标画板');
      return;
    }
    if (this.bindAction === 'show_toast' && target.trim() === '') {
      this.toast('请输入 toast 文案');
      return;
    }
    if (this.bindAction === 'back') target = '';
    const ok = appStore.addInteraction(b.id, l.id, this.bindTrigger, this.bindAction, target);
    if (ok) {
      this.toast('已添加绑定');
      this.sync();
    } else {
      this.toast('该绑定已存在');
    }
  }

  private hasFlowOn(b: Board, l: LayerNode): boolean {
    return this.flows.some((f: Flow): boolean => f.fromBoard === b.id && f.fromNode === l.id);
  }

  /** 当前选中节点（batch-3 未缩放 overlay 消费，gap-detail-8）：仅 active 板；visible=false
   * 不返回——引擎「停止渲染」语义下不画空选框（gap-detail-21 同源取舍）；inspector 行仍按
   * id 可达，visible 切回即恢复选框。 */
  private selLayerOf(b: Board): LayerNode | null {
    if (b.id !== this.selBoard || this.selLayer === '') return null;
    const l = b.layers.find((x: LayerNode): boolean => x.id === this.selLayer) ?? null;
    if (l === null || !l.style.visible) return null;
    return l;
  }

  /** linking affordance 判定（batch-4，gap-detail-20 对齐 i:643-644）：连接模式已选源节点时，
   * 非源画板呈 2vp dashed acc 描边态（chrome+body 双处消费）；源板不加。crosshair 光标
   * （i:643）触屏无 hover 语义——登记降级，鼠标形态归 2in1 真机。 */
  private linkTargeting(b: Board): boolean {
    return this.toolMode === 'link' && this.pendingFromNode !== '' && b.id !== this.pendingFromBoard;
  }

  // ===== 画布元素（按 style 精确渲染；wireframe/hifi 由 modeIdx 驱动，gap-topbar-3）=====
  /**
   * 共享视觉体（batch-2 拆壳）：type 分支内容 + 尺寸 chip + flow 触发标注绘制——被演示壳/
   * 编辑壳共用，不含任何事件/手势/菜单属性（@Builder 调用不可链属性，壳层各自持有）。
   */
  @Builder
  elNodeVisual(b: Board, l: LayerNode) {
    if (l.type === 'input') {
      Row() {
        // 字号直读（batch-3，gap-detail-6）：×0.92 自造折算去除——input 字号两档一致
        Text(l.style.text).fontSize(l.style.fontSize)
          .fontColor(this.isWire() ? this.T().wireText :
            this.hasFlowOn(b, l) ? '#1F7A38' : l.style.color)   // 触发态文字绿染（i:508）
          .fontWeight(l.style.bold ? 700 : 400)
          .fontStyle(l.style.italic ? FontStyle.Italic : FontStyle.Normal)
          .maxLines(1)
      }.width('100%').height('100%').padding({ left: 9 + l.style.padding })
      // batch-10（cur-7 hifi）：背景 hifi 读 style.fill——哨兵约定：fill==='none'||''
      // （未设置语义）回退 card。ElStyle.fill 恒有值（defStyle '#f0f0f3'，AppStore.ets），
      // 按现数据 hifi input 呈 #f0f0f3 浅灰底=数据面真值（复审 finding-5 实证登记）；
      // 线框档保持强制白底。诚实边界：引擎宿主 gap-global-3 下沉前的产品面对齐，
      // 不承诺引擎产出像素级一致。
      .backgroundColor(this.isWire() ? this.T().card :
        (l.style.fill !== 'none' && l.style.fill !== '' ? l.style.fill : this.T().card))
      .borderRadius(l.style.radius)
      .border({
        // 线框档强制 1px #9aa4b2 系（i:627）；高保真档设了描边字段读之，未设回退既有 1px 弱边框
        width: this.isWire() ? 1 : (l.style.strokeWidth > 0 ? l.style.strokeWidth : 1),
        color: this.isWire() ? this.T().wireStroke :
          (l.style.strokeWidth > 0 ? l.style.stroke : this.T().lineStrong),
        // 线型三态（batch-5）：dotted BorderStyle.Dotted（近似登记，dasharray 见 rect 支）
        style: l.style.dash === 'dashed' ? BorderStyle.Dashed :
          l.style.dash === 'dotted' ? BorderStyle.Dotted : BorderStyle.Solid
      })
    } else if (l.type === 'btn') {
      Row() {
        Text(l.style.text).fontSize(l.style.fontSize)
          .fontColor(this.isWire() ? this.T().wireText :
            this.hasFlowOn(b, l) ? '#1F7A38' : l.style.color)   // 触发态文字绿染（i:508）
          .fontWeight(l.style.bold ? 700 : 400)   // 引擎按钮文字同样吃 bold（batch-3，gap-detail-7）
          .fontStyle(l.style.italic ? FontStyle.Italic : FontStyle.Normal)
          .maxLines(Math.max(1, l.style.text.split('\n').length))   // 授权换行随行数（\n 解码后多行文案不被截，自造折行仍无）
      }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      .backgroundColor(this.isWire() ? this.T().card : l.style.fill).borderRadius(l.style.radius)
      .border(this.isWire() ? { width: 1, color: this.T().wireStroke } :
        l.style.strokeWidth > 0 ? { width: l.style.strokeWidth, color: l.style.stroke } : { width: 0 })
    } else if (l.type === 'text') {
      Row() {
        Text(l.style.text).fontSize(l.style.fontSize)
          .fontColor(this.isWire() ? this.T().wireText :
            this.hasFlowOn(b, l) ? '#1F7A38' : l.style.color)   // 触发态文字绿染（i:508）
          .fontWeight(l.style.bold ? 700 : 400)
          .fontStyle(l.style.italic ? FontStyle.Italic : FontStyle.Normal)
          .maxLines(Math.max(1, l.style.text.split('\n').length))   // 单行语义=无自造折行；授权 \n（引擎 tspan 多行）随行数放开
      }.width('100%').justifyContent(l.style.align === 'center' ? FlexAlign.Center :
        l.style.align === 'right' ? FlexAlign.End : FlexAlign.Start)
    } else if (l.type === 'image') {
      if (this.isWire()) {
        // 线框档：隐藏图片圆，呈灰盒描边
        Rect().width('100%').height('100%').radiusWidth(l.style.radius).radiusHeight(l.style.radius)
          .fill(this.T().card)
          .stroke(this.T().wireStroke).strokeWidth(1)
          .strokeDashArray(this.dashArray(l.style.dash))
      } else {
        // batch-10（cur-7 hifi）：弃纯色 Circle → 引擎占位 rect 形态。引擎证据（本轮
        // node out/harmony-parity/r8-engine-probe.cjs 实跑 web_login：image:0、rx:7——
        // 引擎 SVG 无 <image>，图片节点=圆角占位 rect）：Rect+radius+fill+描边。
        Rect().width('100%').height('100%').radiusWidth(l.style.radius).radiusHeight(l.style.radius)
          .fill(l.style.fill)
          .stroke(l.style.strokeWidth > 0 ? l.style.stroke : this.T().lineStrong)
          .strokeWidth(l.style.strokeWidth > 0 ? l.style.strokeWidth : 1)
          .strokeDashArray(this.dashArray(l.style.dash))
      }
    } else {
      Rect().width('100%').height('100%').radiusWidth(l.style.radius).radiusHeight(l.style.radius)
        .fill(this.isWire() ? this.T().card : l.style.fill)
        // 线框档强制 1px #9aa4b2 系；高保真档描边字段 >0 读之，未设维持旧缺省（dash 1px / 无）
        .stroke(this.isWire() ? this.T().wireStroke :
          l.style.strokeWidth > 0 ? l.style.stroke : this.T().wireStroke)
        .strokeWidth(this.isWire() ? 1 :
          l.style.strokeWidth > 0 ? l.style.strokeWidth : (l.style.dash !== 'solid' ? 1 : 0))
        .strokeDashArray(this.dashArray(l.style.dash))
    }
    // 触发标注（batch-4 改造，gap-detail-11 对齐 i:507-508）：右缘 2px 竖条删除（自造形态），
    // 改为节点下方小绿字标签「点击「触发文案前 12 字」 → 目标板id」（i:1841 实文含包裹号；
    // flowTriggerLabel 无文字回退 `trigger → 板id`）——随内层缩放系（通用版同为 svg 内标注）。
    // 演示态不渲染（演示用热区绿框，i:503-504 同为档位切换）。
    // （尺寸 chip 已外提未缩放层——batch-3 gap-detail-8，见 boardContent 的 selOverlay）
    if (!this.showDemo && this.flowsFrom(b, l).length > 0) {
      ForEach(this.flowsFrom(b, l), (f: Flow) => {
        Text(this.flowTriggerLabel(f))
          .fontSize(10).fontColor('#1F7A38')
          .maxLines(1)
          .position({ x: 0, y: l.style.h + 2 })
      }, (f: Flow) => f.id)
    }
  }

  /**
   * 画布元素双壳（batch-2，gap-verify-2）：演示态仅挂纯 onClick 热区——对齐通用版演示点击
   * = .pm-hot 纯 click 热区（i:3392-3401），无拖拽/双击手势竞争（GestureGroup 摘除后，触屏
   * 微位移 >3vp 不再激活 pan 吞掉 onClick→demoTap，双击判定窗口不再延迟单击派发——r2 三轮
   * 「封面板区节点点击不派发」的根因消除）；编辑态保留完整手势组（双击内联 + 拖拽）与
   * 右键/长按菜单双通道，行为与拆壳前逐字一致。
   */
  /**
   * elNode 门控（batch-repair 再修，audit 复测阶梯执行；r6 修订）：两个【平铺顶层 if、无
   * else、无嵌套】，壳体各为独立 builder 直线代码；visible 用 `!== false` 宽松门（缺字段按
   * 可见渲染——桌面缺省语义，数据面 mkLayer 已必填，双保险）。
   * 假设台账（诚实记录，防再绕路）：r4 定性「BoardFrame 外来构建上下文吞嵌套 builder 节点」
   * 并摘除外壳——r5 复测证伪（无 BoardFrame 仍不构建），该假设出局；r5 同轮证据把边界收进
   * 编辑壳分支体（同 Stack 的 selOverlay if+@Builder 正常、demo 壳同一 elNode 链正常），唯一
   * 无实证构件 = GestureGroup → r6 拆为双 .gesture()（详见 elNodeEdit 注）。
   */
  @Builder
  elNode(b: Board, l: LayerNode) {
    if (l.style.visible !== false && !this.showDemo) {
      this.elNodeEdit(b, l)
    }
    if (l.style.visible !== false && this.showDemo) {
      this.elNodeDemo(b, l)
    }
  }

  /** 演示壳（batch-2 gap-canvas-8）：纯 onClick 热区，无手势/菜单。 */
  @Builder
  elNodeDemo(b: Board, l: LayerNode) {
        // —— 演示壳：无 GestureGroup / 无 bindContextMenu ——
        Stack() {
          this.elNodeVisual(b, l)
        }
        .width(l.style.widthMode === 'fill' ? '100%' : l.style.w)
        .height(l.style.h)
        // batch-10：阴影三档走 shadowOf（引擎 e1-e3 实参折算）+ 线框档不挂（桌面 filter:none）
        .shadow(this.isWire() ? { radius: 0, offsetX: 0, offsetY: 0, color: this.T().trans } :
          this.shadowOf(l.style.shadow))
        .position({ x: l.style.x, y: l.style.y })
        .opacity(l.style.opacity)
        .border(!this.demoHideHot && this.demoClickable(b, l) ?
          { width: 1.5, color: this.T().ok, style: BorderStyle.Dashed, radius: l.style.radius + 2 } :   // 演示热区 .pm-hot（gap-canvas-8）
          { width: 0 })
        .onClick(() => {
          this.demoTap(b.id, l.id);   // 演示中：flow/tap 绑定/back 兜底消费（demoTap）
        })
  }

  /**
   * 编辑壳（r6 属性面归一定性）：r5 复测证伪 r4 的「外来构建上下文」根因——BoardFrame 摘除后
   * 编辑壳仍不构建，而同一 body Stack 内的 selOverlay（if+@Builder）与 chrome 全部正常，边界
   * 锁定到本分支体内。逐属性对账本应用内实证面：translate=boardContent 外层 Column 已证；
   * bindContextMenu×2=chrome Row 已证；onClick=demo 壳与 compCell 已证；唯 GestureGroup 全
   * 应用无实证（demo 壳注释自证其已摘除、chrome 用普通 PanGesture、compCell 用双 .gesture()）。
   * 故本轮把 {双击,拖拽} 拆为两条独立 .gesture()（compCell 实证形态）、弃 GestureGroup，绑定
   * 顺序对齐 chrome（gesture 先于 bindContextMenu）。交互语义不变（等价性登记见属性注释）。
   * 选中框/光晕已外提未缩放层（batch-3，gap-detail-8）。
   */
  @Builder
  elNodeEdit(b: Board, l: LayerNode) {
        // —— 编辑壳：完整交互（r6 起双击/拖拽为两条独立 .gesture()，见上注）；选中框/光晕已外提未缩放层（batch-3，gap-detail-8）——
        Stack() {
          this.elNodeVisual(b, l)
        }
        .width(l.style.widthMode === 'fill' ? '100%' : l.style.w)
        .height(l.style.h)
        // batch-10：阴影三档走 shadowOf（引擎 e1-e3 实参折算）+ 线框档不挂（桌面 filter:none）
        .shadow(this.isWire() ? { radius: 0, offsetX: 0, offsetY: 0, color: this.T().trans } :
          this.shadowOf(l.style.shadow))
        .position({ x: l.style.x, y: l.style.y })
        // 跟手叠加（gap-canvas-2）：拖动中 translate 实时偏移，不改 style 不触发 ForEach key
        .translate({
          x: this.dragId === l.id ? this.dragX : 0,
          y: this.dragId === l.id ? this.dragY : 0
        })
        .opacity(l.style.opacity)
        .border(this.hasFlowOn(b, l) ?
          { width: 3, color: '#22C55E', style: BorderStyle.Dashed } :   // 触发标注 3px 绿虚线（batch-4，gap-detail-11 对齐 i:507 stroke-width:3；固定色不进 ThemeColors）
          { width: 0 })
      .onClick(() => {
        if (this.toolMode === 'link') {
          this.pendingFromBoard = b.id;
          this.pendingFromNode = l.id;
          this.toast(`已选 ${l.name}，再点目标画板完成连接`);
          this.consumeClick();   // 阻止冒泡到板级处理（select 源板）
          return;
        }
        if (this.toolMode === 'text') {
          this.consumeClick();   // 文本模式点节点=选中，不在节点下落文本
        }
        if (this.selBoard !== b.id) { this.selBoard = b.id; }   // inspector 按板取层，须同步
        if (this.selLayer !== l.id) { this.selLayer = l.id; }
        this.sync();   // 选中即重载 inspector 草稿（r2 实证：无 sync 时草稿滞后一拍显示上一节点值）
        this.openInlineAgent(b, l);   // 点选节点即弹行内 Agent（gap-right-5）
        this.refocusRoot();   // 修订 5：交互后回焦根，保键盘链可用
      })
        // —— r6 属性面归一（见 builder 上方结案注）：双击与拖拽拆成两条独立 .gesture() 绑定，
        // 弃 GestureGroup 包装——本应用内「一组件多条 .gesture() 绑定」由左栏组件格 compCell
        // 实证可挂载可触发（LongPress+Pan 双绑定，Index.ets compCell / 编译产物 compCell 节），
        // GestureGroup 是编辑壳上唯一无实证的构件。语义等价登记：GestureMode.Exclusive 对
        // {双击, 平移} 的互斥 ≈ 框架默认仲裁「先成功先响应」（双击需静止 300ms 窗口、平移需
        // 位移过 3vp 阈值，二者天然互斥）；单机 onClick 是内建识别器，与组无关，行为不变。
        // 绑定顺序对齐 chrome 实证形态（gesture 在 bindContextMenu 之前，Index.ets boardContent chrome）。
      .gesture(TapGesture({ count: 2 })
        .onAction(() => { this.startInlineEdit(b, l); }))
      .gesture(PanGesture({ fingers: 1, distance: 3 })
        .onActionStart(() => {
          this.dragId = l.id;
          this.dragX = 0;
          this.dragY = 0;
        })
        .onActionUpdate((e: GestureEvent) => {
          if (this.dragId !== l.id) return;
          // PanGesture 在 .scale(z) 祖先内上报的 offsetX/Y 已是组件本地系（=板坐标系）位移，
          // 不再除 zoomOf——模拟器实证再除即过冲 1/z（r2 验收 batch-1 判据）。
          this.dragX = e.offsetX;
          this.dragY = e.offsetY;
        })
        .onActionEnd((e: GestureEvent) => {
          this.dragId = '';
          this.dragX = 0;
          this.dragY = 0;
          // 提交量与视觉量同系（本地系）：钳 ≥0 在 moveLayer 内；pushUndo 已在 batch-1 落地
          appStore.moveLayer(b.id, l.id, e.offsetX, e.offsetY);
          this.sync();
        })
        .onActionCancel(() => {
          this.dragId = '';
          this.dragX = 0;
          this.dragY = 0;
        }))
      .bindContextMenu(this.nodeMenu(b, l), ResponseType.RightClick)
      .bindContextMenu(this.nodeMenu(b, l), ResponseType.LongPress)   // 触屏长按通道（r2 验收：注入长按不映射 RightClick）
        // 挂载探针（r7，复测后可摘）：onAreaChange 仅在组件完成布局后回调——下轮 dump 仍空时
        // 以此判向：有 ddElNode mount 日志=Stack 已挂载（看 w×h 是否正常）；零条=条目从未构建
        // （ForEach 数据/diff 层）。事件回调属性，compCell 同型已证可编译可触发。
      .onAreaChange((o: Area, n: Area): void => {
        // r5b 修正：hilog_rs 不支持 %{public}f（输出 "}f" 且后续参数错位），浮点一律 toString
        // 走 %{public}s（ddFit/ddDemo/ddTopBar/ddZoom 同批修正）。r5b 追加 globalPosition：
        // mount w/h 已证正常而 dump 无节点，位置是「不可见」vs「不在窗内」的分界证据
        hilog.info(0x0000, 'ddElNode', 'mount board=%{public}s layer=%{public}s w=%{public}s h=%{public}s px=%{public}s,%{public}s',
          b.id, l.id, Number(n.width).toString(), Number(n.height).toString(),
          Number(n.globalPosition.x).toString(), Number(n.globalPosition.y).toString());
      })
  }

  /**
   * 选中框 + 尺寸 chip 未缩放 overlay（batch-3，gap-detail-8）：挂在 body 收边层内（未缩放
   * 坐标系——与通用版把 seloverlay/chip append 进 frame-body 同构 i:2208-2209，同受板裁剪），
   * 坐标按 zoomOf 换算，线宽/字号/圆角恒定——fit 态可读。参数逐条对齐通用版 cssText：
   * 选框 i:2203（1.5px acc 边 / radius 2 / 光晕 0 0 0 3px rgba(0,122,255,.15) / 尺寸最小 6px）、
   * chip i:2206（10px/600/ui-monospace / padding 2×6 / radius 4 / 节点下方 +6 / 左缘对齐节点）。
   * pointer-events:none → hitTestBehavior None，不挡节点命中。
   */
  @Builder
  selOverlay(b: Board) {
    // 瞬态防护（batch-repair）：细粒度更新下条件门与分支表达式求值非原子——挂载点判空后
    // 分支内仍可能瞬态 null，裸断言 `!` 会抛 'Cannot read property style of null' 并废弃
    // BoardFrame 子树（多板丢 body 的实证根因类）。全部改可选链+兜底。
    Stack() {
      Stack()
        .width(Math.max(6, (this.selLayerOf(b)?.style.w ?? 0) * this.zoomOf(b)))
        .height(Math.max(6, (this.selLayerOf(b)?.style.h ?? 0) * this.zoomOf(b)))
        .position({
          // 拖拽跟随（batch-2，audit-canvas-1）：拖动选中的节点时叠加上跟手位移——elNode 的
          // translate(dragX,dragY) 在板本地系、经祖先 .scale(zoomOf) 放大，本 overlay 挂未缩放
          // 收边层（坐标已 ×zoomOf），故同乘 zoomOf 换算后叠加，视觉与节点逐帧对齐
          x: (this.selLayerOf(b)?.style.x ?? 0) * this.zoomOf(b) +
            (this.dragId === this.selLayerOf(b)?.id ? this.dragX * this.zoomOf(b) : 0),
          y: (this.selLayerOf(b)?.style.y ?? 0) * this.zoomOf(b) +
            (this.dragId === this.selLayerOf(b)?.id ? this.dragY * this.zoomOf(b) : 0)
        })
        .border({ width: 1.5, color: this.T().acc, radius: 2 })
        .shadow({ radius: 3, offsetX: 0, offsetY: 0, color: 'rgba(0,122,255,0.15)' })
        .hitTestBehavior(HitTestMode.None)
      Row() {
        Text(`${Math.round(this.selLayerOf(b)?.style.w ?? 0)} × ${Math.round(this.selLayerOf(b)?.style.h ?? 0)}`)
          .fontSize(10).fontWeight(600).fontColor(this.T().onAcc)
          .fontFamily('monospace')
          .backgroundColor(this.T().acc).borderRadius(4)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      }
      .position({
        x: (this.selLayerOf(b)?.style.x ?? 0) * this.zoomOf(b) +
          (this.dragId === this.selLayerOf(b)?.id ? this.dragX * this.zoomOf(b) : 0),
        y: ((this.selLayerOf(b)?.style.y ?? 0) + (this.selLayerOf(b)?.style.h ?? 0)) * this.zoomOf(b) + 6 +
          (this.dragId === this.selLayerOf(b)?.id ? this.dragY * this.zoomOf(b) : 0)
      })
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%').height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  /**
   * 画板卡内容体（batch-1 chrome 改造；r4 起由 boards ForEach 直挂在 Index 自身构建树，
   * 原 BoardFrame 薄壳摘除见文件头说明）：双行结构——恒高 chrome 标题栏（未缩放）
   * + 缩放 body。标题栏外提缩放系后任何 zoom 下命中区恒 30vp（gap-verify-1：fit 态长按菜单/
   * 拖移热区不再缩没）；chrome 样式逐条对齐 i:212-219（gap-detail-3），body 收边对齐 i:220
   * （gap-detail-2）。
   */
  @Builder
  boardContent(b: Board) {
    // 外层：缩后布局尺寸（body 缩放高 + chrome 恒高 30，防缩后仍占原位留白）+ 画板视图偏移 + 主次透明度
    Column() {
      // 标题栏 chrome（未缩放恒高）= 画板拖移热区（gap-canvas-7：纯视图偏移，不入 AppStore 不记 op）
      Row({ space: 8 }) {   // chrome 项间距（i:212 gap:8px）
        Row({ space: 5 }) {   // 三色点内部间距（i:215 fc-dots gap:5px）
          Circle({ width: 9, height: 9 }).fill('#ff5f56')   // 通用版 CSS 固定色，不进 ThemeColors（i:217）
          Circle({ width: 9, height: 9 }).fill('#ffbd2e')
          Circle({ width: 9, height: 9 }).fill('#27c93f')
        }
        Text(b.name)
          .fontSize(11.5).fontWeight(600)
          .fontFamily('monospace')   // i:218 .fc-name ui-monospace（batch-2，audit-canvas-6）
          .fontColor(b.id === this.selBoard ? this.T().accTx : this.T().tx2)   // 名称 active 变色（i:214/218）
          .maxLines(1).layoutWeight(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${b.width} × ${b.height}`)
          .fontSize(9.5).fontColor(this.T().tx3)   // 尺寸独立段右置（i:219）
          .fontFamily('monospace')   // i:219 .fc-size ui-monospace（batch-2，audit-canvas-6）
      }
      .width('100%').height(30)   // 恒高（i:212 padding 7px×2 + 行高 ≈30）
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(b.id === this.selBoard ? this.T().chromeBgActive : this.T().chromeBg)   // 灰条/active 白底（i:212/213）
      .borderRadius({ topLeft: this.T().rBoardFrame, topRight: this.T().rBoardFrame })   // batch-3：chrome 顶角 10→HMOS 24（§4 card）；底缘让位 body 收边
      .border(this.linkTargeting(b) ?
        // linking affordance（batch-4，gap-detail-20 对齐 i:644）：连接选源后非源画板 chrome
        // 2vp dashed acc 描边（outline-offset 触屏无等价，登记省略）；源板不加
        { width: 2, color: this.T().acc, style: BorderStyle.Dashed } :
        {
          width: { left: 1, right: 1, top: 1 },   // border-bottom:none（i:212），底缘由 body 收边衔接
          color: b.id === this.selBoard ? this.T().chromeAccBorder : this.T().line   // active rgba(acc,.45)（i:213）
        })
      // direction Horizontal：与外层垂直 Scroll 的手势仲裁解耦（r2 验收：注入拖拽被 Scroll 吞，
      // report-r2.md:182 实录）。方向仲裁显性登记（gap-detail-18）：纯纵向拖板手势仍会被 Scroll
      // 吞（pan 不激活），仅横向主导的拖拽可带出纵向位移（offsetY 随事件上报）；改回 All 的前置
      // 门 = 模拟器实证注入 drag 不被 Scroll 吞并留验证记录，未实证前维持 Horizontal。
      // batch-5 iss-6 登记：画布拖拽跟手不加弹簧动画——responsiveSpringMotion 适用于带回弹的
      // 跟手场景，现有 onActionUpdate 直跟手语义（offset 直写 boardOffsets，零动画中介）不动。
      .gesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 3 })
        .onActionStart(() => {
          this.dragBoardId = b.id;
          this.boardDragBase = this.boardOffset(b.id);
        })
        .onActionUpdate((e: GestureEvent) => {
          if (this.dragBoardId !== b.id) return;
          // 标题栏已外提缩放系（batch-1）：offsetX/Y 即屏幕位移，与 boardOffsets 的外层
          // translate 同一坐标系——不再乘 zoomOf 折算
          this.setBoardOffset(b.id, this.boardDragBase[0] + e.offsetX, this.boardDragBase[1] + e.offsetY);
        })
        .onActionEnd(() => {
          this.dragBoardId = '';
          this.boardPanTs = Date.now();   // 拖后 250ms 屏蔽 click 防误切（gap-canvas-16）
        })
        .onActionCancel(() => {
          this.dragBoardId = '';
          this.boardPanTs = Date.now();
        }))
      .bindContextMenu(this.boardMenuCtx(b), ResponseType.RightClick)   // 菜单随行迁移（通用版 contextmenu 挂 chrome，i:1743）
      .bindContextMenu(this.boardMenuCtx(b), ResponseType.LongPress)   // 触屏长按通道（gap-verify-1：恒 30vp 命中区）
      // 缩放 body（gap-detail-2 收边，对齐 i:220）：白底+1px 弱边框+底部圆角挂未缩放层；
      // active 1.5 acc 描边同挂此处（二选一，无双描边）
      Stack() {
        // 原尺寸渲染，左上锚点缩放（ScaleOptions.centerX/centerY=0，免 translate 补偿）
        Stack() {
          // 键带 `${b.id}/` 板前缀（r3 抢修缺口 2 根因修复）：多板同模板（如 登录页 + 手机登录
          // 卡都是 login 种子）时两板图层 id 与全字段值完全相同，裸 l.id 签名键跨板全同——
          // ForEach 同键复用不重执行 itemGenerator（arkts-rendering-control-foreach.md:163），
          // 复用条目 position 等参数不回填 → 元素丢失/贴板左缘/特定层缺失（r3 验收 ≥3 板
          // 整体消失、undo/删板至 ≤2 恢复的实证链）。板前缀使各板键空间必然不相交。
          ForEach(b.layers, (l: LayerNode) => {
            // r7 修正：itemGenerator 体被 ArkTS 编译器强制 UI 组件语法（r6 的 hilog 语句探针
            // 编译门失败实证，10905204 does not meet UI component syntax），普通语句不可落——
            // 挂载探针改走 elNodeEdit 的 .onAreaChange（属性事件回调，compCell 同型已证）。
            this.elNode(b, l)
          }, (l: LayerNode) => `${b.id}/${l.id}|${Math.round(l.style.x)}|${Math.round(l.style.y)}|${Math.round(l.style.w)}|${Math.round(l.style.h)}|${l.style.widthMode}|${l.style.text}|${l.style.color}|${l.style.fill}|${l.style.fontSize}|${l.style.radius}|${l.style.opacity}|${l.style.visible ? 1 : 0}|${l.style.bold ? 1 : 0}|${l.style.italic ? 1 : 0}|${l.style.dash}|${l.style.shadow}|${l.style.align}|${l.style.padding}|${l.style.stroke}|${l.style.strokeWidth}|${l.style.justify}`)
          // M3 引擎渲染层（gap-global-3）：视觉真相=引擎 render SVG（随每 op/undo/redo 刷新）。
          // hitTest None：触摸穿透到下方原生层（交互零改动）；选中时 0.35 透明让原生
          // 选中描边/chip 透出。SVG 缺失（引擎离线/未刷新）=原生渲染兜底，不阻断。
          // 【仅高保真档挂（用户实测：线框图/高保真两档同图）】桌面线框档经 CSS !important
          // 把同一份 SVG 强制改色（mode-wireframe rect 白底/#9aa4b2 边/text #52606d）；
          // 鸿蒙 SVG 走 Image 无法等价覆盖，线框视觉由下方原生层 isWire 门控承担——
          // SVG 门曾是 modeIdx!==2，线框档也被高保真 SVG 整盖（两档恒同图、选中 0.35
          // 半透明叠原生线框=整板「洗白」观感，用户截图点名），改 modeIdx===1 归位。
          if (this.modeIdx === 1 && this.hifiSvgOf(b.id) !== '') {
            Image('data:image/svg+xml;base64,' + this.hifiSvgOf(b.id))
              .width(b.width).height(b.height)
              .hitTestBehavior(HitTestMode.None)
              .opacity(this.selLayer !== '' ? 0.35 : 1)
            // ArkUI Image 的 SVG 解析不支持 <text>（实测文字缺失）——文字层原生补绘在
            // SVG 之上（hitTest None 双保险；样式镜像 elNodeVisual 非 wire 档）
            ForEach(b.layers.filter((x: LayerNode): boolean =>
              (x.type === 'text' || x.type === 'input' || x.type === 'btn') && x.style.visible !== false), (l: LayerNode) => {
              Text(l.style.text).fontSize(l.style.fontSize)
                .fontColor(l.style.color)
                .fontWeight(l.style.bold ? 700 : 400)
                .fontStyle(l.style.italic ? FontStyle.Italic : FontStyle.Normal)
                .width(l.style.w)
                .height(l.style.h)
                .padding(l.type === 'input' ? { left: 9 + l.style.padding } : { left: 0 })
                .textAlign(l.type === 'btn' ? TextAlign.Center :
                  l.style.align === 'center' ? TextAlign.Center :
                  l.style.align === 'right' ? TextAlign.End : TextAlign.Start)
                .maxLines(Math.max(1, l.style.text.split('\n').length))   // 与线框档同口径：授权换行随行数
                .position({ x: l.style.x, y: l.style.y })
                .hitTestBehavior(HitTestMode.None)
                .opacity(this.selLayer !== '' ? 0.35 : 1)
            }, (l: LayerNode) => `${b.id}/txt/${l.id}|${l.style.text}|${Math.round(l.style.x)}|${Math.round(l.style.y)}|${l.style.fontSize}|${l.style.color}`)
          }
        }
        .width(b.width).height(b.height)
        .scale({
          x: this.zoomOf(b), y: this.zoomOf(b), centerX: 0, centerY: 0
        })
        // 选中框+尺寸 chip 未缩放 overlay（batch-3，gap-detail-8）：通用版 append 进 frame-body
        // （i:2208-2209），受板裁剪同构；selLayerOf 门=演示/切板/隐藏节点不画
        if (this.selLayerOf(b) !== null) {
          this.selOverlay(b)
        }
      }
      // r6 终裁修复（非 active 板顶缘元素整裁，body 壳溢出对齐）：壳 Stack 默认 Center 把内层
      // 390×844 的【未缩放布局框】在壳（w×z × h×z）内居中——z=0.82 时纵向溢出
      // (844−844×0.82)/2=75.96vp、横向溢出 (390−390×0.82)/2=35.1vp；内层 .scale 用左上锚点
      // （centerX/centerY=0），视觉内容以布局框左上为原点随之负偏 → 顶缘元素 board-y×z<75.96
      // （board-y<92.6）被 .clip(true) 整裁。r6 同帧三通道实证：logo y=64 四个非 active 态
      // mount=7 在场/dump 缺 logo/像素无，welcome_title y=158.94 在阈外独存；active 态 z=1
      // 布局框=壳恒同位不受影响（S1/S3a/S4 全在）。TopStart 把布局框左上钉在壳原点，与缩放锚点
      // 重合 → 视觉内容恰铺满 [0,w×z]×[0,h×z]，任意 z（含 >100% 反向溢出）无居中偏置，裁剪
      // 边界回归板边界（与通用版 append 进 frame-body 同构）；同型先例=demoCover r5 判据 D。
      // selOverlay 根 100%×100% 与壳同尺寸，置位不受 alignContent 影响。
      .alignContent(Alignment.TopStart)
      .width('100%').height(b.height * this.zoomOf(b))
      // r5 渲染诊断（render 判据）：壳高=板高×生效缩放，实测反推 z 与 zoomOf 理论值对账——
      // 背离即坐实属性不回填类（键已并入 zoom 强制重建，正常应恒等）
      .onAreaChange((o: Area, n: Area): void => {
        // r5b：原 fit= 字段实为 fitMode 标志（'0'=非 FIT，验收误读为「fitOf=0 与钳位矛盾」的
        // 口径异常）——改名 fitMode=on/off 消歧；追加壳 w 与 globalPosition：mount w/h 已证
        // 正常而 dump 无节点，位置是「不可见」vs「不在窗内」的分界证据
        hilog.info(0x0000, 'ddZoom', 'shell board=%{public}s w=%{public}s h=%{public}s z=%{public}s cw=%{public}s ch=%{public}s fitMode=%{public}s px=%{public}s,%{public}s',
          b.id, Number(n.width).toString(), Number(n.height).toString(), this.zoomOf(b).toString(),
          this.cw.toString(), this.ch.toString(), this.fitMode ? 'on' : 'off',
          Number(n.globalPosition.x).toString(), Number(n.globalPosition.y).toString());
      })
      .clip(true)
      .backgroundColor(this.T().card)   // 画板恒白底（i:220 #fff）——空板不再透出画布灰底
      .borderRadius({ bottomLeft: 10, bottomRight: 10 })
      .border(this.linkTargeting(b) ?
        { width: 2, color: this.T().acc, style: BorderStyle.Dashed } :   // linking affordance 随 body 同步（gap-detail-20）
        b.id === this.selBoard ?
          { width: 1, color: this.T().acc } :   // active 外框 1px acc 边（batch-6，gap-detail-4 双层近似之外框）
          { width: 1, color: this.T().line })   // 非 active 弱边框（i:220 2px rgba(0,0,0,.09)）
      // 非 active 主次透明度（batch-6，gap-detail-4 对齐 i:225 svg opacity .94）：改挂缩放 body
      // ——标题栏 chrome 恒 1 不随暗（原整卡 0.85 连标题一起压暗为误读）
      .opacity(b.id === this.selBoard ? 1 : 0.94)
    }
    .width(b.width * this.zoomOf(b)).height(30 + b.height * this.zoomOf(b))
    .translate({
      x: this.boardOffset(b.id)[0], y: this.boardOffset(b.id)[1]
    })
    // active 光晕双层近似（batch-6，gap-detail-4 对齐 i:221 三层光晕）：外框 1px acc 边在
    // chrome/body 各自 border，内圈 5px accSoft 环挂整卡（alpha 叠加近似 0 0 0 5px 环）；
    // 第三层 0 18px 48px 投影与 hover 阴影（i:227）触屏无语义登记省略
    .border(b.id === this.selBoard ?
      { width: 5, color: this.T().accSoft } : { width: 0, color: this.T().trans })
    .borderRadius(this.T().rBoardFrame)   // batch-3：板框圆角 10→HMOS 24（baseline §4 card）
    .padding(0)
    .onClick((e: ClickEvent) => {
      if (Date.now() - this.boardPanTs < 250) { return; }   // 拖后防误切窗口（gap-canvas-16，复用 clickGateTs 模式）
      this.hoverFlow = '';   // 点画布收起触屏药丸（batch-4 触屏降级通道的收起侧）
      if (this.showInline) {
        this.cancelInline();   // 点空白取消内联编辑（gap-canvas-3）
        return;
      }
      if (this.toolMode === 'text') {
        if (this.clickConsumed()) return;   // 点在节点上：子层已选中，不落文本
        // 按板内坐标换算：减板原点（组件相对坐标）、减 boardOffsets、除 zoom/100；
        // 再减 chrome 恒高 30（batch-1：标题栏外提后 body 自第 30vp 起，e.y 含 chrome 带，
        // chrome 未缩放故减常量、不除 zoom——漏减则文本落点整体偏移 30）
        const z = this.zoomOf(b);
        const off = this.boardOffset(b.id);
        const sx = Math.min(b.width, Math.max(0, Math.round((e.x - off[0]) / z)));
        const sy = Math.min(b.height, Math.max(0, Math.round((e.y - off[1] - 30) / z)));
        appStore.placeLayerText(b.id, sx, sy);
        this.toast(`已放置文本 (${sx}, ${sy})`);
        this.sync();
        return;
      }
      if (this.toolMode === 'link' && this.pendingFromNode !== '' && b.id !== this.pendingFromBoard) {
        this.finishLink(b.id);   // link 第二段：点目标板建流
        return;
      }
      if (this.selBoard !== b.id) {
        this.selBoard = b.id;   // 点非 active 板整卡切换（保留）
        this.clearBoardSwitchState();   // 切板清选中+行内 Agent 浮层（gap-canvas-3）
      }
      this.refocusRoot();   // 修订 5 键盘焦点链回焦出口，不可丢
    })
  }

  /** 顶栏窄窗判定（batch-1，iss-5 响应式折叠）。桌面无窄窗概念（还原态即最宽窗），鸿蒙
   * 自由窗口还原态 931vp / 最大化 1560vp 所迫——topW<1200 视为窄窗，低频项（小艺徽章/
   * ▶ 演示/⚙ 设置）折叠进「导出▾」菜单保可达。显性扩展决策登记：通用版 frontend 无此行为。
   * topW=0（首帧尚未实测）按宽窗渲染，防首帧闪折。 */
  private isNarrowBar(): boolean {
    return this.topW > 0 && this.topW < 1200;
  }

  /** 断点字号/尺寸拾取器（batch-1 断点，r9-sweep §3.3 两档离散口径）：复用 isNarrowBar
   * 两态门（topW 源 :5784-5789 顶栏横贯全窗实测宽；topW=0 首帧按宽窗防闪折）——
   * narrow=窄窗档、wide=宽窗档（=全部主题现 inline 值，非窄窗零漂移）。断点几何与主题色
   * 正交：12 张主题表（THEME_MAC_L :191 至 THEME_HMOS_D :792）不扩字段。禁入站点见
   * Theme.ets 断点层头注（画布数据 fontSize×3 / ≥16 图标徽标 / fDialogTitle 弹层标题）。
   * 消费进度：batch-2 起 fp 首站点=ddMenuRow 菜单行（HMOS_F_MENU_ROW）；sd 仍零消费
   * （fBtnPrimary 接线待后续批次）。 */
  private fp(p: HmosSizePair): number {
    return this.isNarrowBar() ? p.narrow : p.wide;
  }

  /** 主题变量字号离散降档（仅 fBtnPrimary 一键生成钮：HMOS 16→14 / 桌面 13→12，
   * hmosStepDown；宽窗原值直通零漂移）。 */
  private sd(v: number): number {
    return this.isNarrowBar() ? hmosStepDown(v) : v;
  }

  /** 尺寸族拾取（batch-5）：与 fp 同门同两态——命名区分字号/尺寸族，ddFont 断言对账
   * 直读（r9-sweep §3.3 要点 3：高度/内边距联动同改防「小字大框」）。 */
  private sp(p: HmosSizePair): number {
    return this.fp(p);
  }

  /** 字符串 em 宽估算（CJK/全角 1.0、ASCII 0.65、空格 0.3）：HarmonyOS Sans 的近似
   * **上界**——估算偏宽只会让下方适配字号偏小半档，方向安全（宁可字小不可截断）。
   * 不用 getMeasureUtils().measureText：单位语义（px/vp）跨版本有歧义，而本场景只需
   * 确定性的 em×fp 算术。 */
  private emWidth(s: string): number {
    let em: number = 0;
    for (let i = 0; i < s.length; i++) {
      const c: number = s.charCodeAt(i);
      em += c === 0x20 ? 0.3 : (c < 0x7f ? 0.65 : 1.0);
    }
    return em;
  }

  /** dock 主输入可用宽估算（vp）：壳定宽链（min(680,max(320,cw−24))，与 pmain 壳同式）
   * −外层 padding 6−行 padding 18−三个固定兄弟（✦ 图标/Ctrl+K 键帽/⚡一键生成钮，文字部分
   * 按 emWidth×档位字号，框体 padding/边按实值）−行间距 3×8−TextInput **内建水平内边距
   * 30**（模拟器 dump 实测：字形墨迹距组件边 ~16vp/侧，默认 padding 不随档位变）−10vp
   * 余量。窄/宽窗档联动 isNarrowBar（kbd 字号/钮 padding/fBtnPrimary 降档同源）。只服务
   * placeholder 等比字号，不参与布局。 */
  private dockInputAvailW(): number {
    const shell: number = Math.min(680, Math.max(320, this.cw - 24));
    const kbd: number = this.emWidth('Ctrl+K') * this.fp(F_KBD) + 14;   // 键帽 padding 6×2+边框 2
    const btn: number = this.emWidth('⚡一键生成') * this.sd(this.T().fBtnPrimary) +
      (this.isNarrowBar() ? 24 : 36) + 6;                               // 主钮 padding + ⚡与文字 space 6
    return shell - 6 - 18 - this.fp(F_DOCK_ICON) - kbd - btn - 24 - 30 - 10;
  }

  /** 主输入 placeholder 等比字号（用户点名：占位文案保持等比、完整可见于输入框内）。
   * 基准=输入框同档 F_DOCK_INPUT（placeholderFont 此前缺失——ArkUI 占位字号独立默认
   * 16，2997e4d 批漏改本处，截图实证「描述意图（如：生成 Web 登…」以大字号被截）；
   * 估宽超可用宽时随可用宽**线性等比缩**，0.5 步进【向下】取整（向上取会在量化处
   * 反超 1-2vp 复截，模拟器实测），下限 8（字号族最低档 F_TRACK_DETAIL.narrow 贴地）
   * ——极限窄浮窗宁可回到截断也不再缩。 */
  private dockPhFont(): number {
    const base: number = this.fp(F_DOCK_INPUT);
    const avail: number = this.dockInputAvailW();
    const need: number = this.emWidth(DOCK_PH) * base;
    const v: number = need <= avail ? base : Math.max(8, Math.floor((base * avail / need) * 2) / 2);
    hilog.info(0x0000, 'ddDock', 'phFont base=%{public}s avail=%{public}s need=%{public}s -> %{public}s',
      base.toString(), avail.toString(), need.toString(), v.toString());
    return v;
  }

  /** 断点全 token applied 值留痕（batch-5 ④，r9-sweep §3.3）：挂 applyWindowW 尾部随窗
   * 宽变化一次性输出字号/尺寸两族当前 applied 值 + narrow 布尔——两态各抓一次即可断言
   * 全部映射，无需逐点埋桩（ddCols 同位先例；分条输出防 hilog 单条占位符过长）。 */
  private logBreakpointTokens(): void {
    const n: string = this.isNarrowBar().toString();
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s menuRow=%{public}s quick=%{public}s chip=%{public}s icon=%{public}s input=%{public}s kbd=%{public}s',
      n, this.fp(HMOS_F_MENU_ROW).toString(), this.fp(F_DOCK_QUICK).toString(), this.fp(F_DOCK_CHIP).toString(),
      this.fp(F_DOCK_ICON).toString(), this.fp(F_DOCK_INPUT).toString(), this.fp(F_KBD).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s hint=%{public}s agentMsg=%{public}s clarifyHead=%{public}s clarifyInput=%{public}s',
      n, this.fp(F_DOCK_HINT).toString(), this.fp(F_AGENTMSG).toString(),
      this.fp(F_CLARIFY_HEAD).toString(), this.fp(F_CLARIFY_INPUT).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s trackHead=%{public}s trackBody=%{public}s trackMid=%{public}s trackDetail=%{public}s trackMs=%{public}s',
      n, this.fp(F_TRACK_HEAD).toString(), this.fp(F_TRACK_BODY).toString(), this.fp(F_TRACK_MID).toString(),
      this.fp(F_TRACK_DETAIL).toString(), this.fp(F_TRACK_MS).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s trackFinal=%{public}s trackFinalSub=%{public}s toolbar=%{public}s toolbarBadge=%{public}s projName=%{public}s projNameL=%{public}s btnPrimary=%{public}s',
      n, this.fp(F_TRACK_FINAL).toString(), this.fp(F_TRACK_FINAL_SUB).toString(),
      this.fp(F_TOOLBAR).toString(), this.fp(F_TOOLBAR_BADGE).toString(),
      this.fp(F_PROJNAME).toString(), this.fp(F_PROJNAME_L).toString(), this.sd(this.T().fBtnPrimary).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s hChip=%{public}s padChip=%{public}s hDockInput=%{public}s hClarify=%{public}s',
      n, this.sp(HMOS_H_CHIP).toString(), this.sp(PAD_CHIP).toString(),
      this.sp(H_DOCK_INPUT).toString(), this.sp(H_CLARIFY).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s padTrackCardH=%{public}s padTrackCardV=%{public}s padTrackFinalH=%{public}s padTrackFinalV=%{public}s',
      n, this.sp(PAD_TRACK_CARD_H).toString(), this.sp(PAD_TRACK_CARD_V).toString(),
      this.sp(PAD_TRACK_FINAL_H).toString(), this.sp(PAD_TRACK_FINAL_V).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s filechip=%{public}s toolbarGlyph=%{public}s topbarH=%{public}s filechipH=%{public}s pillH=%{public}s tIcon=%{public}s',
      n, this.fp(F_FILECHIP).toString(), this.fp(F_TOOLBAR_GLYPH).toString(),
      this.sp(H_TOPBAR).toString(), this.sp(H_FILECHIP).toString(), this.sp(H_PILL).toString(),
      this.sp(T_ICON_TBTN).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s toolRow=%{public}s toolRowFit=%{public}s zoomGlyph=%{public}s zoom=%{public}s tpl=%{public}s tplMeta=%{public}s',
      n, this.fp(F_TOOLROW).toString(), this.fp(F_TOOLROW_FIT).toString(),
      this.fp(F_ZOOM_GLYPH).toString(), this.fp(F_ZOOM).toString(),
      this.fp(F_TPL).toString(), this.fp(F_TPL_META).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s ghost=%{public}s ghostDim=%{public}s ia=%{public}s iaHead=%{public}s iaMini=%{public}s iaChip=%{public}s',
      n, this.fp(F_GHOST).toString(), this.fp(F_GHOST_DIM).toString(),
      this.fp(F_IA).toString(), this.fp(F_IA_HEAD).toString(), this.fp(F_IA_MINI).toString(), this.fp(F_IA_CHIP).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s welSub=%{public}s welKbd=%{public}s welSec=%{public}s wel=%{public}s welName=%{public}s welTime=%{public}s tail=%{public}s',
      n, this.fp(F_WELCOME_SUB).toString(), this.fp(F_WELCOME_KBD).toString(), this.fp(F_WELCOME_SEC).toString(),
      this.fp(F_WELCOME).toString(), this.fp(F_WELCOME_NAME).toString(), this.fp(F_WELCOME_TIME).toString(),
      this.fp(F_TAIL).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s claGlyph=%{public}s claX=%{public}s hToolBtn=%{public}s hIa=%{public}s hWelRow=%{public}s hTail=%{public}s',
      n, this.fp(F_CLARIFY_GLYPH).toString(), this.fp(F_CLARIFY_X).toString(),
      this.sp(H_TOOLBTN).toString(), this.sp(H_IA).toString(), this.sp(H_WELCOME_ROW).toString(), this.sp(H_TAIL).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s compcell=%{public}s compcellSub=%{public}s layer=%{public}s layerName=%{public}s layerX=%{public}s lprojArrow=%{public}s lbtn=%{public}s',
      n, this.fp(F_COMPCELL).toString(), this.fp(F_COMPCELL_SUB).toString(),
      this.fp(F_LAYER).toString(), this.fp(F_LAYER_NAME).toString(), this.fp(F_LAYER_X).toString(),
      this.fp(F_LPROJ_ARROW).toString(), this.fp(F_LBTN).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s lsecMini=%{public}s lrecentHead=%{public}s lrecentCheck=%{public}s lrecent=%{public}s ltab=%{public}s lsec=%{public}s lboard=%{public}s',
      n, this.fp(F_LSEC_MINI).toString(), this.fp(F_LRECENT_HEAD).toString(),
      this.fp(F_LRECENT_CHECK).toString(), this.fp(F_LRECENT).toString(), this.fp(F_LTAB).toString(),
      this.fp(F_LSEC).toString(), this.fp(F_LBOARD).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s lboardMini=%{public}s lboardDim=%{public}s lboardX=%{public}s lempty=%{public}s lhLempty=%{public}s lsearch=%{public}s inspLabel=%{public}s',
      n, this.fp(F_LBOARD_MINI).toString(), this.fp(F_LBOARD_DIM).toString(), this.fp(F_LBOARD_X).toString(),
      this.fp(F_LEMPTY).toString(), this.fp(LH_LEMPTY).toString(),
      this.fp(F_LSEARCH).toString(), this.fp(F_INSP_LABEL).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s lcompNote=%{public}s lcompHow=%{public}s lcompMini=%{public}s lcompCat=%{public}s lcompCount=%{public}s lflow=%{public}s lflowId=%{public}s',
      n, this.fp(F_LCOMP_NOTE).toString(), this.fp(F_LCOMP_HOW).toString(),
      this.fp(F_LCOMP_MINI).toString(), this.fp(F_LCOMP_CAT).toString(), this.fp(F_LCOMP_COUNT).toString(),
      this.fp(F_LFLOW).toString(), this.fp(F_LFLOW_ID).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s lhint=%{public}s lhintSub=%{public}s lstatus=%{public}s hLbtn=%{public}s hLrecentRow=%{public}s hLtab=%{public}s hLboardRow=%{public}s hLsearch=%{public}s hLayerRow=%{public}s',
      n, this.fp(F_LHINT).toString(), this.fp(F_LHINT_SUB).toString(), this.fp(F_LSTATUS).toString(),
      this.sp(H_LBTN).toString(), this.sp(H_LRECENT_ROW).toString(), this.sp(H_LTAB).toString(),
      this.sp(H_LBOARD_ROW).toString(), this.sp(H_LSEARCH).toString(), this.sp(H_LAYER_ROW).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s emptyHead=%{public}s emptyDesc=%{public}s emptyHint=%{public}s emptyKbd=%{public}s segchip=%{public}s inspLabel=%{public}s inspInput=%{public}s',
      n, this.fp(F_EMPTY_HEAD).toString(), this.fp(F_EMPTY_DESC).toString(),
      this.fp(F_EMPTY_HINT).toString(), this.fp(F_EMPTY_KBD).toString(), this.fp(F_SEGCHIP).toString(),
      this.fp(F_INSP_LABEL).toString(), this.fp(F_INSP_INPUT).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s inspHead=%{public}s inspMini=%{public}s inspVal=%{public}s inspAct=%{public}s declHead=%{public}s decl=%{public}s declGlyph=%{public}s lhDecl=%{public}s',
      n, this.fp(F_INSP_HEAD).toString(), this.fp(F_INSP_MINI).toString(),
      this.fp(F_INSP_VAL).toString(), this.fp(F_INSP_ACT).toString(),
      this.fp(F_DECL_HEAD).toString(), this.fp(F_DECL).toString(), this.fp(F_DECL_GLYPH).toString(),
      this.fp(LH_DECL).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s inspMonoMini=%{public}s inspMono=%{public}s rbtn=%{public}s rbtnAcc=%{public}s rtrackHead=%{public}s rtrackClr=%{public}s rstatusMini=%{public}s rstatus=%{public}s',
      n, this.fp(F_INSP_MONO_MINI).toString(), this.fp(F_INSP_MONO).toString(),
      this.fp(F_RBTN).toString(), this.fp(F_RBTN_ACC).toString(),
      this.fp(F_RTRACK_HEAD).toString(), this.fp(F_RTRACK_CLR).toString(),
      this.fp(F_RSTATUS_MINI).toString(), this.fp(F_RSTATUS).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s trackSrc=%{public}s trackFinalGlyph=%{public}s rtab=%{public}s hSeg=%{public}s hShadowRow=%{public}s hDraftInput=%{public}s hBindChip=%{public}s hBindRow=%{public}s hDeclBtn=%{public}s hRbtn=%{public}s hRbtnAcc=%{public}s hRstatus=%{public}s hRtab=%{public}s',
      n, this.fp(F_TRACK_SRC).toString(), this.fp(F_TRACK_FINAL_GLYPH).toString(), this.fp(F_RTAB).toString(),
      this.sp(H_SEG).toString(), this.sp(H_SHADOW_ROW).toString(), this.sp(H_DRAFT_INPUT).toString(),
      this.sp(H_BIND_CHIP).toString(), this.sp(H_BIND_ROW).toString(), this.sp(H_DECL_BTN).toString(),
      this.sp(H_RBTN).toString(), this.sp(H_RBTN_ACC).toString(), this.sp(H_RSTATUS).toString(), this.sp(H_RTAB).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s menuKbd=%{public}s menuTitle=%{public}s ddCheck=%{public}s toast=%{public}s demoTitle=%{public}s demoHead=%{public}s demo=%{public}s demoHint=%{public}s',
      n, this.fp(F_MENU_KBD).toString(), this.fp(F_MENU_TITLE).toString(), this.fp(F_DD_CHECK).toString(),
      this.fp(F_TOAST).toString(), this.fp(F_DEMO_TITLE).toString(), this.fp(F_DEMO_HEAD).toString(),
      this.fp(F_DEMO).toString(), this.fp(F_DEMO_HINT).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s rmenuHead=%{public}s rmenu=%{public}s rmenuName=%{public}s rmenuTime=%{public}s hMenuRow=%{public}s hRmenuRow=%{public}s',
      n, this.fp(F_RMENU_HEAD).toString(), this.fp(F_RMENU).toString(),
      this.fp(F_RMENU_NAME).toString(), this.fp(F_RMENU_TIME).toString(),
      this.sp(H_MENU_ROW).toString(), this.sp(H_RMENU_ROW).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s modalOpt=%{public}s modalDesc=%{public}s modalSub=%{public}s modalBtn=%{public}s pwdSub=%{public}s pwdTries=%{public}s setClose=%{public}s setHead=%{public}s',
      n, this.fp(F_MODAL_OPT).toString(), this.fp(F_MODAL_DESC).toString(),
      this.fp(F_MODAL_SUB).toString(), this.fp(F_MODAL_BTN).toString(),
      this.fp(F_PWD_SUB).toString(), this.fp(F_PWD_TRIES).toString(),
      this.fp(F_SET_CLOSE).toString(), this.fp(F_SET_HEAD).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s setVal=%{public}s setMini=%{public}s setSec=%{public}s setLabel=%{public}s setMonoUrl=%{public}s setMonoVal=%{public}s setSelect=%{public}s setBtn=%{public}s setTag=%{public}s setKbd=%{public}s stab=%{public}s',
      n, this.fp(F_SET_VAL).toString(), this.fp(F_SET_MINI).toString(),
      this.fp(F_SET_SEC).toString(), this.fp(F_SET_LABEL).toString(),
      this.fp(F_SET_MONO_URL).toString(), this.fp(F_SET_MONO_VAL).toString(),
      this.fp(F_SET_SELECT).toString(), this.fp(F_SET_BTN).toString(),
      this.fp(F_SET_TAG).toString(), this.fp(F_SET_KBD).toString(), this.fp(F_STAB).toString());
    hilog.info(0x0000, 'ddFont', 'narrow=%{public}s hExportOpt=%{public}s hPwdInput=%{public}s hDlgBtn=%{public}s hSetField=%{public}s hSetBtn=%{public}s hStab=%{public}s gSetField=%{public}s gSetBlock=%{public}s',
      n, this.sp(H_EXPORT_OPT).toString(), this.sp(H_PWD_INPUT).toString(), this.sp(H_DLG_BTN).toString(),
      this.sp(H_SET_FIELD).toString(), this.sp(H_SET_BTN).toString(), this.sp(H_STAB).toString(),
      this.sp(G_SET_FIELD).toString(), this.sp(G_SET_BLOCK).toString());
  }

  /** 三区等比适配（batch-7 cur-1）：窗 onAreaChange 输入窗内容宽，折算左右栏（常量组见
   * CANVAS_MIN_W 上方登记）。ddCols 日志供模拟器 dump 对账（r4 §4.1：坐标逐构建漂移，
   * 验收每次 dump 新坐标——栏宽实测若越 45%/55% 判据界先回查常量组）。 */
  private applyWindowW(w: number): void {
    this.winW = w;
    const s: number = w / COL_REF_W;
    this.leftW = Math.max(LEFT_W_MIN, Math.min(LEFT_W_MAX, Math.round(LEFT_W_MAX * s)));
    this.rightW = Math.max(RIGHT_W_MIN, Math.min(RIGHT_W_MAX, Math.round(RIGHT_W_MAX * s)));
    hilog.info(0x0000, 'ddCols', 'winW=%{public}s leftW=%{public}s rightW=%{public}s fold=%{public}s',
      w.toString(), this.leftW.toString(), this.rightW.toString(),
      this.rightFolded() ? 'right' : 'none');
    this.logBreakpointTokens();   // batch-5 ④：断点全 token applied 值留痕（ddCols 同位）
  }

  /** 画布最小宽门控（折叠判定输入）：winW<左+右+CANVAS_MIN_W 时触发。输入全部为窗宽
   * 折算值（不含折叠后实际画布宽）——防「折叠→画布变宽→门控解除→回弹」振荡。 */
  private canvasGate(): boolean {
    return this.winW > 0 && this.winW < this.leftW + this.rightW + CANVAS_MIN_W;
  }

  /** 工具行横向 Scroll 兜底判定（cur-1 判负消除）：画布实测宽 < CANVAS_MIN_W（工具行自然
   * 宽 ~548+余量放不下 SpaceBetween 一行，r8 实证 czoom 被撑压到 11.6vp 碎片）。cw=0
   * （首帧未实测）按窄渲染——首帧 Scroll 分支内容即完整布局，实测转宽后一帧切回
   * SpaceBetween，与 isNarrowBar 首帧宽窗口径同理不闪断。 */
  private toolRowScroll(): boolean {
    return this.cw > 0 && this.cw < CANVAS_MIN_W;
  }

  /** 右栏折叠判定：门控触发 且 未选中元素 且 track 页不在看（Agent 留痕在看=面板在用，
   * 不折叠）。选中元素即展开（inspector 优先于画布最小宽——登记取舍：选中态画布暂时
   * 窄于 CANVAS_MIN_W 由工具行 Scroll 分支兜底）。空态引导移左栏见 build 内折叠提示块。 */
  private rightFolded(): boolean {
    // M3.6（用户决策）：右栏固定不消失——窄窗不再折叠属性/Agent 面板，两侧栏恒在，
    // 画布居中自适应。canvasGate/折叠提示块保留作登记录径（恒 false 不构建）。
    return false;
  }

  /** 顶栏左簇（r5 重构抽出）：brand+tsep+项目名+filechip——宽窄两态共用。 */
  @Builder
  topbarLeft() {
    // M3.6.2：品牌块拆除（用户决策）——鸿蒙有系统标题栏（native「deepDesign」+ 图标，
    // M3.6.1 修复后正常显示），应用顶栏再放 logo+deepDesign STUDIO 属完全冗余；项目 chip
    // 前移至最左（原品牌位）。副产：还原态 980 最小档入流预算富余 ~150vp，窄窗压缩
    // 随之拆除（药丸 padding 13/操作组间距 6/演示 10/导出▾ 8/导出DDP 12 恢复桌面常量）。
    // 项目名裸文字 + ▾ 下拉（batch-4，audit-topbar-5：名称移出 chip——桌面 .proj> b
    // i:786 语义）；filechip 只承担脏标/版本
    Row({ space: 5 }) {
      Text(this.projName).fontSize(this.fp(F_PROJNAME)).fontWeight(600).fontColor(this.T().tx).maxLines(1)   // batch-5：断点字号（r9-sweep §3.3，12↔11）
      Text('▾').fontSize(8).fontColor(this.T().tx2)
    }
    .bindMenu(this.recentMenu)   // 最近项目下拉保留（gap-topbar-2）
    Row({ space: 4 }) {
      Text(this.dirty ?
        `● ${appStore.filePath !== '' ? this.baseName(appStore.filePath) : this.projName}` :
        'v0.4.2')
        .fontSize(this.fp(F_FILECHIP)).fontFamily('monospace').fontColor(this.T().tx2).maxLines(1)   // r10 sz-topbar-2：路径 chip 断点字号（10.5↔9.5）
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }.height(this.sp(H_FILECHIP)).padding({ left: 9, right: 9, top: 0, bottom: 0 }).borderRadius(99)   // r10 h-topbar-2：chip 断点高（22↔20）
    .backgroundColor(this.T().subtle)
    .constraintSize({ maxWidth: 200 })   // i:86 .filechip max-width:200px
  }

  /** mode-seg（r5 重构抽出）：三模式钮——宽窗居中 overlay 与窄窗滚动内容共用。 */
  @Builder
  modeSeg() {
    // mode-seg（三模式，batch-4 audit-topbar-6：13×13 图标 i:811/814/817）
    Row({ space: 2 }) {
      ForEach(this.modes, (m: string, i: number) => {
        Row({ space: 5 }) {
          this.modeIcon(i)
          Text(m).fontSize(this.fp(F_TOOLBAR)).fontWeight(this.modeIdx === i ? 600 : 500)   // batch-5：modeSeg 断点字号（§3.3 fToolLabel，12.5↔11.5）
            .fontColor(this.modeIdx === i ? this.T().tx : this.T().tx2)
        }.height(this.sp(H_PILL)).padding({ left: 13, right: 13 }).borderRadius(8)   // r10 h-topbar-3：药丸断点高（28↔25）
        .backgroundColor(this.modeIdx === i ? this.T().card : Color.Transparent)
        .shadow(this.modeIdx === i ?
          { radius: SH_SEG_SELECTED.radius, offsetX: SH_SEG_SELECTED.dx, offsetY: SH_SEG_SELECTED.dy, color: this.T().shadowMd } :
          { radius: 0, offsetX: 0, offsetY: 0, color: this.T().trans })   // r10 sh-1：几何 token SH_SEG_SELECTED（3/(0,1)，色已走主题）
        .stateStyles({
          pressed: { .scale({ x: HMOS_PRESS_SCALE, y: HMOS_PRESS_SCALE }) },   // batch-4 iss-5：A 缩放式（段钮）
          normal: { .scale({ x: 1, y: 1 }) }
        })
        .onClick(() => {
          this.modeIdx = i;
          if (i === 2) { this.declText = appStore.toCanonicalText(); }   // 进入源码视图刷新（canonical 展示投影）
        })
      }, (m: string) => m)
    }.padding(2).borderRadius(9).backgroundColor(this.T().subtle)
    .border({ width: 1, color: this.T().shsm })
  }

  /** 顶栏操作组（r5 重构抽出）：小艺(窄隐)+新建/打开/保存+⚙(窄隐)+tsep+演示(窄隐)+
   * 导出▾+导出 DDP——宽窄两态共用；窄隐条件在宽窗分支恒真、窄窗分支恒假，保留作
   * topW 跨阈值切换时的一致性护栏。 */
  @Builder
  opsGroup() {
    Row({ space: 6 }) {
      // 小艺徽章折叠为圆点+短文案（batch-4，audit-topbar-2：全文案入设置卡）
      // 窄窗隐藏（batch-1，iss-5 响应式折叠）：还原态 931vp 宽度预算不足，低频项让位，
      // 状态文案仍可在设置卡查看；宽窗（topW≥1200）原样保留
      Row({ space: 4 }) {
        Circle({ width: 6, height: 6 })
          .fill(this.xiaoyiState.includes('就绪') ? this.T().ok : this.T().tx3)
        Text('小艺').fontSize(this.fp(F_TOOLBAR_BADGE)).fontColor(this.T().tx2)   // batch-5：徽章断点字号（§3.3，11↔10）
      }
      // M3.6：窄隐拆除（用户决策）——两态图标全集一致
      this.tbtn('M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z M14 3v5h5',
        (): void => { this.actNew(); })
      this.tbtn('M3 8a2 2 0 0 1 2-2h4l2 3h8a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
        (): void => { this.actOpen(); })
      this.tbtn(
        'M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z M17 21v-8H7v8 M7 3v5h8',
        (): void => { this.actSave(); })
      // M3.6：⚙ 窄窗折叠拆除（用户决策：两态图标全集一致）
      this.tbtn(
        'M12 8.8a3.2 3.2 0 1 0 0 6.4a3.2 3.2 0 1 0 0-6.4z M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z',
        (): void => { this.showSettings = true; })
      this.tsep()   // i:825：图标组与演示/导出组之间
      // 演示：▶ 文字换三角图标（i:825 path；桌面 tbtn 带文字「演示」；viewPort 归
      // Shape 容器，同 tbtn 构建门修正）。r12 fix-topbar-2：同 tbtn B 案（24×24 基底+
      // .scale 单倍缩放，S=sp(T_ICON_TBTN)；三角 13×15u→8.1×9.4vp=桌面应值）；外包 S×S
      // Stack 保布局——Row space 5 与文字间距按 S 计，Shape 24 布局盒不参与排布
      // M3.6：演示窄隐拆除（两态图标全集一致）+ 渲染换 Image-SVG（S=15 同 tbtn）
      Row({ space: 5 }) {
        Image(this.svgIcon('M6 4.5v15l13-7.5z', 15, this.T().tx2))
          .width(15).height(15)
          .draggable(false)
          .interpolation(ImageInterpolation.Medium)
        Text('演示').fontSize(this.fp(F_TOOLBAR)).fontWeight(500).fontColor(this.T().tx2)   // batch-5：工具行断点字号（§3.3，12.5↔11.5）
      }.height(this.sp(H_PILL)).padding({ left: 10, right: 10 }).borderRadius(8)   // r10 h-topbar-3：演示药丸断点高（28↔25）
      .onClick(() => { this.actDemoEntry(); })   // gap-canvas-7：唯一入口，起点页进入
      Row({ space: 4 }) {
        Text('⇩').fontSize(this.fp(F_TOOLBAR_BADGE)).fontColor(this.T().tx2)   // batch-5：徽章档（§3.3，11↔10）
        Text('导出').fontSize(this.fp(F_TOOLBAR)).fontWeight(500).fontColor(this.T().tx2)   // batch-5：工具行断点字号（§3.3，12.5↔11.5）
        Text('▾').fontSize(8).fontColor(this.T().tx2)   // r10 sz-topbar-3：箭头 8 两态同值保底不接 token
      }.height(this.sp(H_PILL)).padding({ left: 8, right: 8, top: 0, bottom: 0 }).borderRadius(7)   // r10 h-topbar-3：导出▾ 药丸断点高（28↔25）
      .bindMenu(this.exportMenuPanel)   // batch-2 dd-menu-export：自绘面板（r9 实测修正：箭头形 bindMenu builder 零求值 6 处全死，统一改引用形=recentMenu 顶栏先例；builder 展开时求值，canUndo 仍读当帧值）
      Row({ space: 5 }) {
        Text('↧').fontSize(this.fp(F_TOOLBAR_GLYPH)).fontColor(this.T().onAcc)   // r10 sz-topbar-3：字形断点（12↔11）
        Text('导出 DDP').fontSize(this.fp(F_TOOLBAR)).fontWeight(600).fontColor(this.T().onAcc)   // batch-5：工具行断点字号（§3.3，12.5↔11.5）
      }.height(this.sp(H_PILL)).padding({ left: 12, right: 12 }).borderRadius(8)   // r10 h-topbar-3：导出DDP 药丸断点高（28↔25）
      .backgroundColor(this.T().acc)
      .onClick(() => { this.showExport = true; })
    }
  }

  /** 顶栏竖分隔线（batch-4，audit-topbar-12 对齐 i:72 .tsep：1×18 rgba(0,0,0,.09) margin 0 5px；
   * 桌面固定色不分主题——字面量登记同 flowStroke 法）。 */
  @Builder
  tsep() {
    Divider().vertical(true).strokeWidth(1).height(18)
      .color('rgba(0,0,0,0.09)').margin({ left: 5, right: 5 })
  }

  /** 顶栏 28×28 图标钮（batch-4，audit-topbar-2：SVG path 描边式图标，触屏命中区 28 达标；
   * path 逐字抄 frontend/index.html i:821-824）。r12 fix-topbar-1 墨迹双重缩放根因修复：
   * Path-in-Shape 实测定律 墨迹=path单位×(Shape边长/24)²、与内层 Path 尺寸无关
   * （r11-max-topbar.png 七站点拟合，spec §一），容器 dump 三轮验不出——改 spec B 案
   * 确定性还原：Shape/Path 全 24×24+viewPort 24（基底恒等，墨迹=path 单位）+ Shape
   * .scale(S/24)（S=sp(T_ICON_TBTN)，渲染级单倍缩放：folder 18u→11.25vp=桌面 i:34
   * .ic 15px 盒内应值；A 案 viewPort 改 S 对该定律情形无效，spec §六，未采）。
   * strokeWidth 1.7 不动（viewBox 单位，随 .scale 单倍还原后有效 ≈1.06=桌面同值）。
   * 验收=截图量墨迹（宽态 folder ≥10.5vp），容器 dump 不作通过依据。 */
  /** 图标 SVG data URL（M3.6 渲染路径更换）：Shape/Path/.scale 组合在 ArkUI 下墨迹
   * 尺寸经 r11/r12 两轮修复仍不稳定（.scale 变换与 Shape/Path 双重布局的交互依赖
   * 渲染时序，截图实测 15px≠数学预期 21.4px）——改 Image-SVG data URL：viewBox 24
   * + Image 精确 S×S，单次比例缩放零歧义（Image SVG 支持 path/stroke，无 <text>
   * 需求）。S 恒定 15（桌面 i:34 .ic 15×15 无断点同构，最大/还原两态一致=用户诉求）。 */
  private svgIcon(d: string, size: number, stroke: string): string {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="' + size + '" height="' + size + '" fill="none" stroke="' + stroke + '" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="' + d + '"/></svg>';
    return 'data:image/svg+xml;base64,' + this.utf8B64(svg);
  }

  @Builder
  tbtn(d: string, action: () => void) {
    Column() {
      Image(this.svgIcon(d, 15, this.T().tx2))
        .width(15).height(15)
        .draggable(false)
        .interpolation(ImageInterpolation.Medium)
    }.width(28).height(this.sp(H_PILL)).borderRadius(7)   // r10 h-tbtn-1：图标钮断点高（28↔25；宽 28 保持横向命中区）
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .stateStyles({
      pressed: { .scale({ x: HMOS_PRESS_SCALE, y: HMOS_PRESS_SCALE }) },   // batch-4 iss-5：A 缩放式（图标钮，桌面 .czoom button:active scale(.94) 同族 i:205）
      normal: { .scale({ x: 1, y: 1 }) }
    })
    .onClick(() => { action(); })
  }

  /** mode-seg 三钮 13×13 图标（batch-4，audit-topbar-6；path 抄 i:811/814/817，按下标取；
   * viewPort 归 Shape 容器，同 tbtn 修正登记；13×13=spec-icon-1 mode 类基准不变）。
   * r12 fix-topbar-3：同 tbtn B 案——Path==Shape 13 也受双重缩放定律制约（spec §一左栏
   * tab 实测 5.8vp 佐证），改 24×24 基底+.scale(13/24)（16u 线框矩形→8.7vp=桌面 i:85
   * .mode-btn .ic 13×13 应值），外包 13×13 Stack 保 mode 钮 Row 布局。
   * strokeWidth 1.7 不动（viewBox 单位，单倍还原后有效 ≈0.92=桌面 1.7@13px 同值）。 */
  @Builder
  modeIcon(i: number) {
    Stack() {
      Image(this.svgIcon(MODE_ICON_PATHS[i], 13, this.modeIdx === i ? this.T().tx : this.T().tx2))
        .width(13).height(13)
        .draggable(false)
        .interpolation(ImageInterpolation.Medium)
    }.width(13).height(13)
  }

  /**
   * ctools 单钮（batch-2，audit-canvas-5 对齐 i:197-200）：选中态实心 acc 底 + onAcc 前景
   * （--acc-contrast 语义）+ 投影 0 1px 4px rgba(0,122,255,.4)；静息 tx2。
   * magic=✨ 自动修复：静息恒 #7c3aed（i:200 .ctool.magic 固定紫）——桌面级联里 .on 的
   * magic 钮字色仍是紫（i:200 后于 i:199），实心蓝底紫字对比差，按选中态统一 onAcc
   * （触屏可读性优先，登记分歧）。
   */
  @Builder
  toolBtn(icon: string, label: string, mode: string, magic: boolean) {
    Row({ space: 4 }) {
      Text(icon).fontSize(this.fp(F_TOOLROW_ICON))   // M3.6.9：icon 独立降档（Unicode 符号字形天然偏高，与 label 同档臃肿——用户圈点 ctools）
        .fontColor(this.toolMode === mode ? this.T().onAcc : (magic ? '#7c3aed' : this.T().tx2))
      Text(label).fontSize(this.fp(F_TOOLROW)).fontWeight(this.toolMode === mode ? 600 : 500)   // r10 sz-ctools-1：label 断点（11.5↔10.5）
        .fontColor(this.toolMode === mode ? this.T().onAcc : (magic ? '#7c3aed' : this.T().tx2))
    }.height(this.sp(H_TOOLBTN)).padding({ left: 9, right: 9, top: 0, bottom: 0 }).borderRadius(7)   // r10 h-toolbtn-1：断点高（24↔22）
    .backgroundColor(this.toolMode === mode ? this.T().acc : Color.Transparent)
    .shadow(this.toolMode === mode ?
      { radius: SH_TOOL_SELECTED.radius, offsetX: SH_TOOL_SELECTED.dx, offsetY: SH_TOOL_SELECTED.dy, color: this.T().shadowMd } :
      { radius: 0, offsetX: 0, offsetY: 0, color: this.T().trans })   // r10 sh-2：几何 SH_TOOL_SELECTED（4/(0,1) 不变）；取色硬编码蓝 rgba(0,122,255,0.4)→主题 shadowMd（§五行为修正）
    .stateStyles({
      pressed: { .scale({ x: HMOS_PRESS_SCALE, y: HMOS_PRESS_SCALE }) },   // batch-4 iss-5：A 缩放式（图标钮）
      normal: { .scale({ x: 1, y: 1 }) }
    })
    .onClick(() => { this.pickTool(mode); })
  }

  /** ctools 条（batch-7 cur-1 判负消除抽出：宽窄两态共用，防分支重复 45 行）。内容与
   * 壳样式原样（选择/画板/文本/连接/自动修复 + 分隔线 + ⤢ 适配），iss-2 入流口径不变。 */
  @Builder
  ctoolsBar() {
    Row({ space: 6 }) {
      this.toolBtn('◈', '选择', 'select', false)
      this.toolBtn('▭', '画板', 'board', false)   // 与通用版一致为占位
      this.toolBtn('T', '文本', 'text', false)
      this.toolBtn('⇄', '连接', 'link', false)
      this.toolBtn('✨', '自动修复', 'fix', true)   // magic 紫（i:200，audit-canvas-5）
      Divider().vertical(true).height(12).color(this.T().bd)
      Text('⤢ 适配').fontSize(this.fp(F_TOOLROW_FIT)).fontColor(this.T().tx2)   // r10 sz-ctools-1：断点字号（11↔10，F_TOOLROW_FIT 独立档）
        .onClick(() => { this.fitWindow(); })
    }.padding(this.isNarrowBar() ? { left: 7, right: 7, top: 4, bottom: 4 } : { left: 10, right: 10, top: 5, bottom: 5 }).height(CANVAS_TOOLBAR_H)   // M3.6.9：窄窗收紧（窄画布占比失衡——用户圈点）
    .borderRadius(this.T().rFloatBar)   // batch-3：悬浮条圆角 12→HMOS 20（§4 button 档）
    .backgroundColor(this.T().floatBg).border({ width: 1, color: this.T().line })
    .shadow(this.T().shFloat)   // batch-3：{12,0,0,shadowMd}→shFloat sm 档 40/(0,10)（§6）
  }

  /** czoom 条（batch-7 抽出同 ctoolsBar）：−/读数/＋/1:1 四件，语义不动（spec-fit-2）。
   * token 对齐——真缩放（gap-canvas-5）；batch-2（audit-canvas-5）：删「⤢ 适配窗口」（桌面
   * czoom 只有 −/pct/＋/1:1 四件，i:902-907，适配入口在 ctools「⤢ 适配」）；pct 读数
   * 11.5/600/tx/minWidth 56 monospace（i:206）；1:1 改 10.5/700/tx3（i:207 .fit）。 */
  @Builder
  czoomBar() {
    Row({ space: this.isNarrowBar() ? 5 : 8 }) {
      Text('−').fontSize(this.fp(F_ZOOM_GLYPH)).fontColor(this.T().tx2)   // r10 sz-czoom-1：断点字号（13↔12）
        .onClick(() => {
          // r5（判据 E）：FIT 态首步只落实际比例退出、不连乘步进（对齐桌面 zoomStep
          // 「一次落实际比例」——r5 实证 100/1.2=83% 判负形态）
          if (this.fitMode) { this.landFit(); return; }
          this.zoom = Math.max(18, Math.round(this.zoom / 1.2));
        })
      Text(this.zoomLabel())
        .fontSize(this.fp(F_TOOLROW)).fontWeight(600).fontColor(this.T().tx)   // r10 sz-czoom-1：百分比读数断点（11.5↔10.5，复用 F_TOOLROW）
        .fontFamily('monospace')   // i:206 .pct ui-monospace（audit-canvas-6）
        .constraintSize({ minWidth: 56 }).textAlign(TextAlign.Center)
      Text('＋').fontSize(this.fp(F_ZOOM_GLYPH)).fontColor(this.T().tx2)   // r10 sz-czoom-1：断点字号（13↔12）
        .onClick(() => {
          if (this.fitMode) { this.landFit(); return; }   // r5：同「−」，首步只落比例
          this.zoom = Math.min(800, Math.round(this.zoom * 1.2));
        })
      Divider().vertical(true).height(12).color(this.T().bd)
      Text('1:1').fontSize(this.fp(F_ZOOM)).fontWeight(700).fontColor(this.T().tx3)   // r10 sz-czoom-1：断点字号（10.5↔9.5）
        .onClick(() => {
          this.zoom = 100;
          this.fitMode = false;
        })
    }.padding(this.isNarrowBar() ? { left: 7, right: 7, top: 4, bottom: 4 } : { left: 10, right: 10, top: 5, bottom: 5 }).height(CANVAS_TOOLBAR_H)   // M3.6.9：窄窗收紧（窄画布占比失衡——用户圈点）
    .borderRadius(this.T().rFloatBar)   // batch-3：悬浮条圆角 12→HMOS 20（§4 button 档）
    .backgroundColor(this.T().floatBg).border({ width: 1, color: this.T().line })
    .shadow(this.T().shFloat)   // batch-3：{12,0,0,shadowMd}→shFloat sm 档 40/(0,10)（§6）
  }

  /** 交互流连线（gap-canvas-6 + batch-4 gap-detail-10）：静音细线+终点箭头+源点圆点，专线色
   * #3f8fff 不随主题（i:1896/:1855/:1904）；药丸深蓝底白字 11 号骑曲线中点上方（i:1914-1918）；
   * 14px 透明描边感知悬停（+触屏 onClick 等价通道：通用版 hover 的触屏形态，点线开药丸/
   * 再点收起，鼠标 hover 形态归 2in1 真机）；外层 Transparent——画布点击仍穿透。
   * hover 源点放大 r4（i:638）登记省略（触屏无 hover，2in1 归后期）。 */
  @Builder
  flowLine(f: Flow) {
    if (this.flowValid(f)) {
      Stack() {
        Path()
          .commands(this.flowCmds(f))
          .width(Math.max(1, Math.abs(this.flowTo(f)[0] - this.flowFrom(f)[0])))
          .height(Math.max(1, Math.abs(this.flowTo(f)[1] - this.flowFrom(f)[1])))
          .position({ x: this.flowMin(f)[0], y: this.flowMin(f)[1] })
          .stroke(this.T().flowStroke)
          .strokeWidth(this.hoverFlow === f.id ? 2 : 1.5)
          .strokeOpacity(this.hoverFlow === f.id ? 0.9 : 0.38)
          .fillOpacity(0)
          .hitTestBehavior(HitTestMode.None)
        // 悬停感知层：同几何的 14px 近透明描边（自身响应 hover/点击，不阻塞兄弟）
        Path()
          .commands(this.flowCmds(f))
          .width(Math.max(1, Math.abs(this.flowTo(f)[0] - this.flowFrom(f)[0])))
          .height(Math.max(1, Math.abs(this.flowTo(f)[1] - this.flowFrom(f)[1])))
          .position({ x: this.flowMin(f)[0], y: this.flowMin(f)[1] })
          .stroke(this.T().flowStroke)
          .strokeWidth(14)
          .strokeOpacity(0.02)
          .fillOpacity(0)
          .onHover((isHover: boolean): void => {
            this.hoverFlow = isHover ? f.id : '';
          })
          .onClick(() => {
            // 触屏降级通道（登记）：注入/触屏无 hover——点线开药丸，再点同线收起；
            // 点画布空白由 boardContent onClick 收起
            this.hoverFlow = this.hoverFlow === f.id ? '' : f.id;
          })
        // 源点圆点（直径 6，i:1904 r=3；hover 放大 r4 登记省略）
        Circle({ width: 6, height: 6 })
          .fill(this.T().flowStroke)
          .opacity(this.hoverFlow === f.id ? 0.9 : 0.38)
          .position({ x: this.flowFrom(f)[0] - 3, y: this.flowFrom(f)[1] - 3 })
          .hitTestBehavior(HitTestMode.None)
        // 终点箭头：小三角，尖端触目标板左缘，方向随末端水平切线（x2−x1 符号）
        Polygon({ width: 8, height: 8 })
          .points(this.flowTo(f)[0] >= this.flowFrom(f)[0]
            ? [[0, 0], [8, 4], [0, 8]]
            : [[8, 0], [0, 4], [8, 8]])
          .fill(this.T().flowStroke)
          .opacity(this.hoverFlow === f.id ? 0.9 : 0.38)
          .position({
            x: this.flowTo(f)[0] - (this.flowTo(f)[0] >= this.flowFrom(f)[0] ? 8 : 0),
            y: this.flowTo(f)[1] - 4
          })
          .hitTestBehavior(HitTestMode.None)
        // 悬停药丸（i:1914-1918）：深蓝底白字 11/500 radius 9.5，骑曲线中点上方（y=中点-13 口径）；
        // 标签语义=触发节点文字 trim 前 10 字（回退节点 id→'tap'）→ 目标板 id（i:1909-1910）。
        // x 居中（batch-2，audit-canvas-9）：原 x=中点−60 固定左移，改为 onAreaChange 实测
        // 药丸宽后 x=中点−w/2——宽随标签长度自适应，短/长标签均以曲线中点居中（每条流挂载
        // 即实测入 Map，hover 切换直接命中已测值；未测得回退 120 半宽）
        Text(this.flowPillLabel(f))
          .fontSize(11).fontWeight(500).fontColor('#ffffff')
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .borderRadius(9.5).backgroundColor('rgba(4,76,166,0.95)')
          .position({
            x: (this.flowFrom(f)[0] + this.flowTo(f)[0]) / 2 - this.flowPillW(f) / 2,
            y: (this.flowFrom(f)[1] + this.flowTo(f)[1]) / 2 - 13
          })
          .onAreaChange((o: Area, n: Area): void => {
            this.pillW.set(f.id, Number(n.width));
          })
          .opacity(this.hoverFlow === f.id ? 1 : 0)
          .hitTestBehavior(HitTestMode.None)
      }.hitTestBehavior(HitTestMode.Transparent)
    }
  }

  /** 组件格（gap-leftcomp-1；batch-6，audit-left-8/10：预览按组件 id 关键词映射（compPrev，
   * button/input/search/slider/checkbox/switch 可辨）+名称行 10/600；长按起拖+Pan 跟手、
   * 松手 dropCompAtWindow 落板——点击放置保留为保底通道（引导卡已注明，手势仲裁实测定）。 */
  @Builder
  compCell(c: CompDef) {
    Column({ space: 3 }) {
      this.compPrev(c)
      Text(c.id).fontSize(this.fp(F_COMPCELL)).fontWeight(600).fontColor(this.T().tx).maxLines(1)   // r10 sz-compcell-1：id 断点（10↔9）
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(`${c.default_size[0]} × ${c.default_size[1]}`).fontSize(this.fp(F_COMPCELL_SUB)).fontColor(this.T().tx3)   // r10 sz-compcell-1：尺寸行断点（8.5↔8）
    }
    .width(this.isNarrowBar() ? 88 : 106).padding({ top: 8, bottom: 7 })   // M3.6.9：窄窗 106→88（左栏 220 下 2 列卡占满失衡——用户圈点）
    .borderRadius(9).backgroundColor(this.T().card)
    .border({ width: 1, color: this.T().bd })
    .alignItems(HorizontalAlign.Center)
    .margin({ right: 6, bottom: 6 })
    .onClick(() => { this.placeComp(c); })
    // 格中心锚点（batch-6 构建门修正：GestureEvent 无 windowX/windowY——本 SDK 字段不存在；
    // 改 Area.globalPosition（页面相对）记录格中心 + Pan 累计 offset 平移，见 ghostAnchor）
    .onAreaChange((o: Area, n: Area): void => {
      this.cellPos.set(c.id, [
        Number(n.globalPosition.x) + Number(n.width) / 2,
        Number(n.globalPosition.y) + Number(n.height) / 2
      ]);
    })
    .gesture(LongPressGesture({ repeat: false, duration: 250 })
      .onAction(() => {
        // 长按起拖：幽灵 pill 锚定格中心（audit-left-10）
        const pos = this.cellPos.get(c.id);
        this.ghostAnchorX = pos ? pos[0] : 0;
        this.ghostAnchorY = pos ? pos[1] : 0;
        this.ghostX = this.ghostAnchorX;
        this.ghostY = this.ghostAnchorY;
        this.dragGhostCid = c.id;
      }))
    .gesture(PanGesture({ fingers: 1, distance: 2 })
      .onActionUpdate((e: GestureEvent) => {
        if (this.dragGhostCid !== c.id) { return; }   // 仅长按已起拖才跟手
        this.ghostX = this.ghostAnchorX + e.offsetX;
        this.ghostY = this.ghostAnchorY + e.offsetY;
      })
      .onActionEnd((e: GestureEvent) => {
        if (this.dragGhostCid !== c.id) { return; }
        this.dragGhostCid = '';
        this.dropCompAtWindow(this.ghostAnchorX + e.offsetX, this.ghostAnchorY + e.offsetY, c);
      })
      .onActionCancel(() => {
        this.dragGhostCid = '';
      }))
  }

  // ===== 模板缩略（batch-3，audit-modal-10：优先引擎真实渲染 SVG；wasm 不在场的历史镜像
  // 回退假线框——本仓库 rawfile/tplthumbs/ 已随批内置 14 张离线预渲染产物（frontend/vendor/
  // moonviz.wasm 经 engine-host 行协议 `template <tid> __t_<tid> <w> <h>` + export-svg 生成），
  // 回退分支仅为缺资源兜底）=====
  @Builder
  tplThumb(tid: string, kind: string, compact: boolean) {
    Column({ space: compact ? 3 : 4 }) {
      if (this.tplThumbsProbed && this.tplThumbIds.has(tid)) {
        // 引擎真实渲染缩略：白底容器内 objectFit.Contain（74/56 容器保留，桌面 .th 同构）
        Image($rawfile(`tplthumbs/${tid}.svg`))
          .width('100%').height('100%')
          .objectFit(ImageFit.Contain)
      } else if (kind === 'mobile') {
        Circle({ width: compact ? 10 : 13, height: compact ? 10 : 13 }).fill(this.T().line)
        Rect({ width: '62%', height: compact ? 5 : 7 }).radius(2).fill(this.T().lineStrong)
        Rect({ width: '44%', height: compact ? 4 : 5 }).radius(2).fill(this.T().bd)
        Rect({ width: '74%', height: compact ? 10 : 13 }).radius(3).fill(this.T().onAcc).stroke(this.T().shadowMd)
        Rect({ width: '74%', height: compact ? 10 : 13 }).radius(3).fill(this.T().onAcc).stroke(this.T().shadowMd)
        Rect({ width: '74%', height: compact ? 11 : 14 }).radius(3).fill(this.T().acc).opacity(0.88)
      } else {
        Row({ space: 3 }) {
          Rect({ width: compact ? 8 : 10, height: 4 }).radius(1).fill(this.T().lineStrong)
          Blank()
          Rect({ width: compact ? 11 : 14, height: 4 }).radius(1).fill(this.T().acc).opacity(0.75)
        }.width('100%')
        Rect({ width: '50%', height: compact ? 5 : 7 }).radius(2).fill(this.T().lineStrong)
        Rect({ width: '36%', height: compact ? 4 : 5 }).radius(2).fill(this.T().bd)
        Row({ space: 4 }) {
          Rect({ width: compact ? 20 : 26, height: compact ? 9 : 12 }).radius(3).fill(this.T().acc).opacity(0.88)
          Rect({ width: compact ? 20 : 26, height: compact ? 9 : 12 }).radius(3).fill(this.T().onAcc).stroke(this.T().shadowMd)
        }
      }
    }.width('100%').height('100%').padding(6)
    .backgroundColor(this.T().card)
    .borderRadius(8)
    .border({ width: 1, color: this.T().line })
    .alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
  }

  @Builder
  tplCard(t: TplDef, compact: boolean) {
    Column() {
      Column() {
        this.tplThumb(t.tid, t.kind, compact)
      }.width('100%').height(compact ? 56 : 74).margin({ bottom: compact ? 6 : 9 })

      Text(t.name).fontSize(this.fp(F_TPL)).fontWeight(600).fontColor(this.T().tx)   // r10 sz-tpl-1：卡名断点（11.5↔10.5）
        .maxLines(1).alignSelf(ItemAlign.Start)
      Text(`${t.kind} · ${TplSize.of(t.kind)[0]} × ${TplSize.of(t.kind)[1]}`)
        .fontSize(this.fp(F_TPL_META)).fontColor(this.T().tx2).margin({ top: 1 }).alignSelf(ItemAlign.Start)   // r10 sz-tpl-1：meta 断点（9↔8）
    }
    .width(compact ? 96 : 126).padding(compact ? 8 : 11)
    .backgroundColor(this.T().card)
    .borderRadius(this.T().rTplCard)   // batch-3：模板卡圆角 12→HMOS 24（§4 card；与 ghost 合并同字段）
    .border({ width: 1, color: this.T().bd })
    .shadow(this.T().shCard)   // batch-3：{2,0,1,shsm}→HMOS 无阴影（radius 0+透明色，§6 落地建议：普通卡片用 sub_background 分层）
    .stateStyles({
      pressed: { .backgroundColor(this.T().pressFill) },   // batch-4 iss-5：B 底色叠加（卡面=subtle 提一档）
      normal: { .backgroundColor(this.T().card) }
    })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.addTpl(t.tid))
  }

  /** 图层行（batch-6，audit-left-4 对齐 i:157-162 .layerrow：mono、radius 7、行首宽 15、
   * 选中 600+accTx+rgba(0,122,255,.09) 底；图标按 layerIcon 同表关键词 10 类+兜底）。 */
  @Builder
  layerRow(l: LayerNode) {
    Row({ space: 7 }) {
      Text(this.layerIcon(l))
        .fontSize(this.fp(F_LAYER)).fontColor(this.selLayer === l.id ? this.T().accTx : this.T().tx3)   // r10 sz-layer-1：icon/类型断点（11↔10）
        .opacity(0.75).width(15).textAlign(TextAlign.Center)
      Text(l.name).fontSize(this.fp(F_LAYER_NAME)).fontFamily('monospace')   // r10 sz-layer-1：名断点（12↔11）
        .fontWeight(this.selLayer === l.id ? 600 : 400)
        .fontColor(this.selLayer === l.id ? this.T().accTx : this.T().tx2).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      if (this.selLayer === l.id) {
        Text('✕').fontSize(this.fp(F_LAYER_X)).fontColor(this.T().tx3)   // r10 sz-layer-1：✕ 断点（10↔9）
          .onClick(() => {
            const b = this.curBoard();
            if (b) { appStore.deleteLayer(b.id, l.id); this.selLayer = ''; this.sync(); }
          })
      }
    }.width('100%').height(this.sp(H_LAYER_ROW)).borderRadius(7).padding({ left: 5, right: 5 })   // r10 h-layer-1：行断点高（27↔24）
    .backgroundColor(this.selLayer === l.id ? 'rgba(0,122,255,0.09)' : Color.Transparent)
    .stateStyles({
      pressed: { .backgroundColor(this.selLayer === l.id ? 'rgba(0,122,255,0.09)' : this.T().pressFill) },   // batch-4 iss-5：B 底色叠加（选中态保选色，未选中=subtle 提一档）
      normal: { .backgroundColor(this.selLayer === l.id ? 'rgba(0,122,255,0.09)' : Color.Transparent) }
    })
    .onClick(() => { this.selLayer = l.id; this.sync(); })   // sync→loadDrafts：行选也要装载 inspector 草稿（r2 缺口：此路径漏 sync）
  }

  @Builder
  tlCard(e: TlEntry) {
    Column() {
      Text(`${e.src === 'AGENT' ? 'AGENT' : e.src === 'TEMPLATE' ? 'TEMPLATE' : e.src === 'ENGINE' ? 'ENGINE' : 'HUMAN'} · rev ${e.rev} · ${e.ms}ms`)
        .fontSize(this.fp(F_TRACK_HEAD)).fontWeight(700).fontColor(this.T().tx).margin({ bottom: 4 })   // batch-5：留痕卡头行（§3.3 fTrackHead，11.5↔10.5）
      Row({ space: 5 }) {
        Text(e.src === 'AGENT' ? '◆' : e.src === 'TEMPLATE' || e.src === 'ENGINE' ? '◇' : '●')
          .fontSize(this.fp(F_TRACK_SRC)).fontColor(e.src === 'AGENT' ? this.T().purple : e.src === 'TEMPLATE' || e.src === 'ENGINE' ? this.T().ok : this.T().acc)   // r10 sz-track-1：源 tag 断点（9↔8）。ENGINE 复用 TEMPLATE 视觉（◇ 绿）——数据可见性映射，非布局改动（gap-global-3）
        Text(e.op).fontSize(this.fp(F_TRACK_BODY)).fontColor(this.T().tx2).maxLines(1)   // batch-5：op 行（§3.3，10.5↔9.5）
          .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      }.width('100%')
    }.width('100%').padding({ left: this.sp(PAD_TRACK_CARD_H), right: this.sp(PAD_TRACK_CARD_H),
      top: this.sp(PAD_TRACK_CARD_V), bottom: this.sp(PAD_TRACK_CARD_V) })   // batch-5：收紧并做（§3.3 要点 3，11/9↔8/7）
    .borderRadius(12).backgroundColor(this.T().card)
    .border({ width: 1, color: this.T().line })
    .margin({ bottom: 8 })
  }

  // ===== 右键菜单体系（gap-canvas-5：自绘 Column builder，对齐通用版 标题行/kbd 右注/分隔线）=====

  /** 菜单动作行：左 label（batch-2，audit-canvas-8：静息 tx2、行高 26）+ 右 kbd 右注
   *（fontSize 9 tx3 monospace，无键位不显）。danger 恒红保留——桌面 danger 项同样恒红
   *（删除系无静息/悬停双色之分），触屏无 hover 态，恒红即触屏等价呈现（登记）。 */
  @Builder
  menuRow(label: string, kbd: string, danger: boolean, action: () => void) {
    Row() {
      Text(label).fontSize(this.fp(HMOS_F_MENU_ROW))   // r10 sz-menurow-1：label 断点（复用 HMOS_F_MENU_ROW，11.5↔10.5）
        .fontColor(danger ? this.T().danger : this.T().tx2).maxLines(1)
      Blank()
      if (kbd !== '') {
        Text(kbd).fontSize(this.fp(F_MENU_KBD)).fontColor(this.T().tx3).fontFamily('monospace')   // r10 sz-menurow-1：kbd 断点（9↔8）
      }
    }.width('100%').height(this.sp(H_MENU_ROW)).padding({ left: 12, right: 12 })   // r10 h-menu-1：菜单行断点高（26↔24，与 HMOS_F_MENU_ROW 联动）；batch-3 误挂 H_LRECENT_ROW 就此修正（宽窗 26 两 token 同值零漂移）
    .stateStyles({
      pressed: { .scale({ x: HMOS_PRESS_SCALE, y: HMOS_PRESS_SCALE }) },   // batch-4 iss-5：A 缩放式（菜单行）
      normal: { .scale({ x: 1, y: 1 }) }
    })
    .onClick(() => { action(); })
  }

  /** 菜单组分隔线。 */
  @Builder
  menuDivider() {
    Divider().color(this.T().bd).margin({ left: 10, right: 10, top: 3, bottom: 3 })
  }

  /** 菜单标题行（=上下文 id/名称）；底线对齐 i:387（batch-6，gap-detail-9）。
   * batch-2（audit-canvas-8）：10.5 + monospace。 */
  @Builder
  menuTitle(title: string) {
    Text(title).fontSize(this.fp(F_MENU_TITLE)).fontColor(this.T().tx3).fontFamily('monospace')   // r10 sz-menurow-2：分组题断点（10.5↔9.5）
      .width('100%').maxLines(1)
      .padding({ left: 12, right: 12, top: 8, bottom: 3 })
      .margin({ bottom: 3 })
      .border({ width: { bottom: 1 }, color: this.T().bd })
  }

  // ===== 统一弹层菜单原语（batch-2，dd-menu-export 试点收编）=====

  /** ddFont 测量日志透传（batch-2）：面板每次构建（=每次展开）记菜单行 applied 字号与
   * narrow 布尔，供还原态/最大化两态断言（ddDemo/ddInk hilog 先例）。@Builder 体仅 UI
   * 语法，故经容器首属性 .width 透传执行——返回值恒等入参，零视觉副作用。 */
  private ddFontProbe(w: number): number {
    hilog.info(0x0000, 'ddFont', 'menuRow applied=%{public}s narrow=%{public}s',
      this.fp(HMOS_F_MENU_ROW).toString(), this.isNarrowBar().toString());
    return w;
  }

  /** 统一菜单动作行（ddMenuRow）：✓列 + label（断点字号 fp(HMOS_F_MENU_ROW) 11.5↔10.5，
   * r9-sweep §3.3 menuRow 族）+ kbd 右注（menuRow 同款 monospace 9）。选中态 accSoft 底/
   * 600；danger 恒红（同 menuRow 登记）；disabled=tx3+opacity 0.4+点击旁路。行高 26/
   * 左右 12/圆角 7/stateStyles 按压缩放全对齐 menuRow（旧三件套并存，后续批次逐菜单迁移）。 */
  @Builder
  ddMenuRow(item: DdMenuItem) {
    Row() {
      Text(item.selected ? '✓' : '')
        .fontSize(this.fp(F_DD_CHECK)).fontColor(this.T().accTx).width(16).textAlign(TextAlign.Center)   // r10 sz-ddmenu-1：✓列断点（11↔10）
      Text(item.label)
        .fontSize(this.fp(HMOS_F_MENU_ROW))
        .fontWeight(item.selected ? 600 : 400)
        .fontColor(item.disabled ? this.T().tx3 : (item.danger ? this.T().danger : this.T().tx2))
        .maxLines(1)
        .layoutWeight(1)
      if (item.kbd !== '') {
        Text(item.kbd).fontSize(this.fp(F_MENU_KBD)).fontColor(this.T().tx3).fontFamily('monospace')   // r10 sz-ddmenu-1：kbd 断点（9↔8，F_MENU_KBD 共用）
      }
    }.width('100%').height(this.sp(H_MENU_ROW)).padding({ left: 12, right: 12 }).borderRadius(7)   // r10 h-menu-1：下拉行断点高（26↔24）
    .backgroundColor(item.selected ? this.T().accSoft : Color.Transparent)
    .opacity(item.disabled ? 0.4 : 1)
    .stateStyles({
      pressed: { .scale({ x: HMOS_PRESS_SCALE, y: HMOS_PRESS_SCALE }) },
      normal: { .scale({ x: 1, y: 1 }) }
    })
    .onClick(() => {
      if (!item.disabled) { item.action(); }
    })
  }

  /** 统一弹层面板（ddMenuPanel）：组间 menuDivider（gi>0）、组标题可选（title!=='' 才出
   * menuTitle 行）、组内 ddMenuRow。容器=card 底/rMenuPanel（HMOS 20 §4 menu）/1px line 边/
   * shMenu（md 60/(0,10)）——与 recentMenu 容器同规。ddFontProbe 挂首属性（见函数注）。 */
  @Builder
  ddMenuPanel(width: number, groups: Array<DdMenuGroup>) {
    Column() {
      ForEach(groups, (g: DdMenuGroup, gi: number) => {
        if (gi > 0) {
          this.menuDivider()
        }
        if (g.title !== '') {
          this.menuTitle(g.title)
        }
        ForEach(g.items, (item: DdMenuItem) => {
          this.ddMenuRow(item)
        }, (item: DdMenuItem) => item.label)
      }, (g: DdMenuGroup, gi: number) => 'g' + String(gi))
    }
    .width(this.ddFontProbe(width))
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.T().card)
    .borderRadius(this.T().rMenuPanel)
    .border({ width: 1, color: this.T().line })
    .shadow(this.T().shMenu)
  }

  /** 「导出▾」自绘面板（batch-2 dd-menu-export 试点收编）：200 宽三组——撤销/重做｜
   * 导出 SVG/HTML｜窄窗收留设置/演示（组数据见 exportMenu()）。
   * 测量通道登记（batch-2 ④，复审实跑证据）：uitest dump 全树仅 bounds/children/clickable/
   * hitTestBehavior/id/longClickable/scrollable/text/type 直读（无 fontSize/padding/
   * borderRadius/shadow/fontWeight）——本面板判据分通道：行 bounds+backgroundColor+
   * opacity+text 直读；字号断 ddFont applied 值；圆角/阴影走截图采样（r7 §2.2 先例）或
   * 静态 grep token 消费在场。自绘 @Builder 面板入 dump 与否本批首验：不可见时
   * `ui layout --all-windows` 重取，仍不可见则该锚点降级截图+ddFont 日志。 */
  @Builder
  exportMenuPanel() {
    this.ddMenuPanel(200, this.exportMenu())
  }

  // ===== 设置面板三枚 Select 收编（batch-3，dd-select-model/thinking/steps）=====
  // 触发框=现 Select 形态照搬（h30/r6/card 底/字号 11.5+▾，无 border——复审修正：
  // border() 属新增视觉元素与「维持现 token」冲突，现 Select 亦无边框；provider 框
  // h24/subtle 不可作模板）。弹层复用 ddMenuPanel（232 宽单组，ddMenuRow 自动带
  // fMenuRow 两档字号 + ddFont 留痕 + 按压态）。

  /** 模型组：cfgModels 全量单组；selected=当前模型；action→pickModel（链路原样，
   * restrictThinking 随选收紧）。 */
  private modelMenuGroups(): Array<DdMenuGroup> {
    const items: Array<DdMenuItem> = this.cfgModels.map((m: string): DdMenuItem => {
      return {
        label: m,
        kbd: '',
        selected: m === this.cfgModel,
        danger: false,
        disabled: false,
        action: (): void => { this.pickModel(m); }
      };
    });
    const g: DdMenuGroup = { title: '', items: items };
    return [g];
  }

  /** 思考档组：档位=cfgThinkOptions（restrictThinking 收紧产物），label 经 thinkLabel；
   * action 闭包直赋（项非空——Select 时代的 index??'auto' 防御不再需要）。 */
  private thinkMenuGroups(): Array<DdMenuGroup> {
    const items: Array<DdMenuItem> = this.cfgThinkOptions.map((o: string): DdMenuItem => {
      return {
        label: this.thinkLabel(o),
        kbd: '',
        selected: o === this.cfgThinking,
        danger: false,
        disabled: false,
        action: (): void => { this.cfgThinking = o; }
      };
    });
    const g: DdMenuGroup = { title: '', items: items };
    return [g];
  }

  /** 步数组：STEP_CAPS 四档 label；action 闭包直赋（项非空——index??500 防御不再需要）；
   * 触发框文案仍走 stepLabel（保留）。 */
  private stepMenuGroups(): Array<DdMenuGroup> {
    const items: Array<DdMenuItem> = STEP_CAPS.map((s: StepCapDef): DdMenuItem => {
      return {
        label: s.label,
        kbd: '',
        selected: s.steps === this.cfgMaxSteps,
        danger: false,
        disabled: false,
        action: (): void => { this.cfgMaxSteps = s.steps; }
      };
    });
    const g: DdMenuGroup = { title: '', items: items };
    return [g];
  }

  /** 三面板：232 宽单组（触发锚 bindMenu 箭头形引用）。 */
  @Builder
  modelMenuPanel() {
    this.ddMenuPanel(232, this.modelMenuGroups())
  }

  @Builder
  thinkMenuPanel() {
    this.ddMenuPanel(232, this.thinkMenuGroups())
  }

  @Builder
  stepMenuPanel() {
    this.ddMenuPanel(232, this.stepMenuGroups())
  }

  /** 节点右键菜单（触屏长按/鼠标右键由 bindContextMenu 适配）：10 动作项+2 分隔线
   * （batch-2 删链接↔删除间线，audit-canvas-7——桌面同组 i:2302-2319）；emoji 前缀逐项
   * 对齐 i:2305-2319（batch-6，gap-detail-9）。 */
  @Builder
  nodeMenu(b: Board, l: LayerNode) {
    Column() {
      this.menuTitle(l.id)
      this.menuRow('✏️ 编辑文字', '双击', false, (): void => { this.startInlineEdit(b, l); })
      this.menuRow('⧉ 复制元素', '', false, (): void => {
        appStore.copyLayer(b.id, l.id);
        this.toast('已复制节点');
        this.sync();
      })
      this.menuRow('⬆ 置顶', '', false, (): void => {
        appStore.reorderLayer(b.id, l.id, true);
        this.sync();
      })
      this.menuRow('⬇ 置底', '', false, (): void => {
        appStore.reorderLayer(b.id, l.id, false);
        this.sync();
      })
      this.menuDivider()
      this.menuRow('↔ 水平居中', '', false, (): void => {
        appStore.alignLayer(b.id, l.id, true);
        this.sync();
      })
      this.menuRow('↕ 垂直居中', '', false, (): void => {
        appStore.alignLayer(b.id, l.id, false);
        this.sync();
      })
      this.menuRow('⇋ 水平翻转', '', false, (): void => {
        appStore.flipLayer(b.id, l.id, 'h');
        this.sync();
      })
      this.menuRow('⇵ 垂直翻转', '', false, (): void => {
        appStore.flipLayer(b.id, l.id, 'v');
        this.sync();
      })
      this.menuDivider()
      this.menuRow('🔗 从这里链接交互…', '', false, (): void => {
        this.toolMode = 'link';
        this.pendingFromBoard = b.id;
        this.pendingFromNode = l.id;
        this.toast(`已选 ${l.name}，再点目标画板完成连接`);
      })
      // 分隔线已删（batch-2，audit-canvas-7：桌面链接与删除同组，i:2302-2319 无此线）
      this.menuRow('🗑 删除元素', '⌫', true, (): void => {
        appStore.deleteLayer(b.id, l.id);
        this.selLayer = '';
        this.sync();
      })
    }.width(216).padding({ bottom: 6 }).backgroundColor(this.T().card).borderRadius(this.T().rMenuPanel)
    // batch-3：菜单容器圆角 10→HMOS 20（baseline §4 menu）；阴影 {12,0,0,shadowMd}→shMenu md 档 60/(0,10)
    .border({ width: 1, color: this.T().line })
    .shadow(this.T().shMenu)
  }

  /** 画板卡右键菜单：5 动作项+2 分隔线，对齐 i:2333-2343；emoji/措辞逐项对齐（batch-6）。
   * batch-2（audit-canvas-7）：复制提前到切换后——分组 [切换,复制 | 演示,复位 | 删除]
   * （原 演示↔复制 换序）。 */
  @Builder
  boardMenuCtx(b: Board) {
    Column() {
      this.menuTitle(b.name)
      this.menuRow('→ 切换到此画板', '', false, (): void => {
        this.selBoard = b.id;
        this.clearBoardSwitchState();
        this.sync();
      })
      this.menuRow('⧉ 复制此画板', '', false, (): void => {
        const nb = appStore.duplicateBoard(b.id);
        if (nb !== null) { this.selBoard = nb.id; }
        this.toast('已复制画板');
        this.sync();
      })
      this.menuDivider()
      this.menuRow('▶ 从起点页演示', '', false, (): void => { this.actDemoEntry(); })
      this.menuRow('⌖ 复位画板位置', '', false, (): void => {
        this.setBoardOffset(b.id, 0, 0);
      })
      this.menuDivider()   // [切换,复制 | 演示,复位 | 删除]（batch-2，audit-canvas-7）
      this.menuRow('🗑 删除此画板', 'Ctrl+Shift+Del', true, (): void => {
        this.confirmDeleteBoard(b.id);
      })
    }.width(216).padding({ bottom: 6 }).backgroundColor(this.T().card).borderRadius(this.T().rMenuPanel)
    // batch-3：菜单容器圆角 10→HMOS 20（baseline §4 menu）；阴影 {12,0,0,shadowMd}→shMenu md 档 60/(0,10)
    .border({ width: 1, color: this.T().line })
    .shadow(this.T().shMenu)
  }

  /** 画布空白右键菜单：7 动作项+3 分隔线（batch-2 补齐第三条，audit-canvas-7），对齐
   * i:2320-2332；emoji 前缀 + 互切项动态 label（batch-6，gap-detail-9 对齐 i:2325 三态文案）。 */
  @Builder
  canvasMenu() {
    Column() {
      this.menuTitle('画布')
      this.menuRow('✚ 新建画板', 'Ctrl+Shift+N', false, (): void => {
        const nb = appStore.addBlankBoard();
        this.sync();
        this.selBoard = nb.id;
        this.selLayer = '';
      })
      this.menuRow('⧉ 复制当前画板', 'Ctrl+Shift+D', false, (): void => {
        if (this.selBoard === '') {
          this.toast('无画板可复制');
          return;
        }
        const nb = appStore.duplicateBoard(this.selBoard);
        if (nb !== null) { this.selBoard = nb.id; }
        this.toast('已复制画板');
        this.sync();
      })
      this.menuDivider()
      this.menuRow(this.modeIdx === 0 ? '🎨 切换到高保真' : '◻ 切换到线框图', '', false, (): void => {
        this.modeIdx = this.modeIdx === 0 ? 1 : 0;
      })
      this.menuRow('‹/› 查看 MBT 源码', 'Ctrl+3', false, (): void => {
        this.declText = appStore.toCanonicalText();   // canonical 展示投影（gap-mbt-1）
        this.modeIdx = 2;
      })
      this.menuDivider()
      this.menuRow('↻ 重新序列化刷新', '', false, (): void => {
        this.revalidateSource();   // 三入口统一（gap-mbt-11）：画布右键/源码右键/顶部按钮同一刷新函数
      })
      this.menuRow('▶ 演示模式', 'Ctrl+4', false, (): void => { this.actDemoEntry(); })
      this.menuDivider()   // 分组线补齐（batch-2，audit-canvas-7）：[新建,复制 | 互切,源码 | 校验,演示 | 适配]
      this.menuRow('⛶ 适配窗口', 'Ctrl+0', false, (): void => { this.fitWindow(); })
    }.width(216).padding({ bottom: 6 }).backgroundColor(this.T().card).borderRadius(this.T().rMenuPanel)
    // batch-3：菜单容器圆角 10→HMOS 20（baseline §4 menu）；阴影 {12,0,0,shadowMd}→shMenu md 档 60/(0,10)
    .border({ width: 1, color: this.T().line })
    .shadow(this.T().shMenu)
  }

  /** decl 源码视图右键菜单（batch-4，gap-mbt-11 收口为三件套：复制源码 | ↻ 重新序列化刷新 + 分隔线）。
   * 结构变更留痕（原「已对齐无差距」四动作项+1 分隔线）：
   * - 「⌿ 全选」移除：declSelectAll 全选链路随只读 Text+Span 形态去留评估为移——无 TextArea
   *   可聚焦/选择（requestFocus('declArea') 必抛 150002，batch-3 起 try/catch 兜底无操作），
   *   复制能力由「⧉ 复制源码」全文通道承载；
   * - 「🗑 清空编辑器」移除：应用路径（JSON.parse→restore）已删，清空态无消费者——
   *   「只读态下清空编辑器无对象」（gap-mbt-11 实施指令③），declDirty 门随之移除。
   * 与桌面差异：桌面校验草稿走引擎全链（i:2350-2358），归 gap-global-3 回收。 */
  @Builder
  declMenu() {
    Column() {
      this.menuTitle('MBT 源码 · 唯一事实源')
      this.menuRow('⧉ 复制源码', '', false, (): void => { this.copySource(); })
      this.menuDivider()
      this.menuRow('↻ 重新序列化刷新', '', false, (): void => {
        this.revalidateSource();   // 三入口统一（gap-mbt-11）：画布右键/源码右键/顶部按钮同一刷新函数
      })
    }.width(216).padding({ bottom: 6 }).backgroundColor(this.T().card).borderRadius(this.T().rMenuPanel)
    // batch-3：菜单容器圆角 10→HMOS 20（baseline §4 menu）；阴影 {12,0,0,shadowMd}→shMenu md 档 60/(0,10)
    .border({ width: 1, color: this.T().line })
    .shadow(this.T().shMenu)
  }

  /** 文本折叠（batch-5，audit-right-10）：超限截断 + …；展开态由 expandedStep 键控制。 */
  private foldText(t: string, cap: number): string {
    return t.length > cap ? t.slice(0, cap) + '…' : t;
  }

  /**
   * 实时轨迹步骤行（gap-right-4；batch-5 audit-right-10 重构）：instruction=▸ 指令行
   * （>100 字折叠、点击行展开全文）；tool_start/end 常规行（detail>150 字同折叠）；
   * done 分流 tlFinal 绿胶囊（audit-right-11）；failed 红染行保留。
   */
  /** M3.6.4 轨迹三段分桶：plan=计划（指令/计划/调优）、exec=执行（请求/回复/模板/
   * 命令流/澄清）、review=审查修复、tail=done/failed 尾卡。 */
  private stepsOfPhase(p: string): AgentStep[] {
    return this.agentSteps.filter((s: AgentStep): boolean => {
      if (p === 'plan') return s.kind === 'plan' || s.kind === 'instruction';
      if (p === 'exec') return s.kind === 'tool_start' || s.kind === 'tool_end';
      if (p === 'review') return s.kind === 'review';
      return s.kind === 'done' || s.kind === 'failed';
    });
  }

  /** 段头：小标签+发丝线（模块边界视觉锚，主题切换不清问题兜底）。 */
  @Builder
  phaseHead(label: string, color: ResourceColor) {
    Row({ space: 8 }) {
      Text(label).fontSize(this.fp(F_TRACK_MID)).fontWeight(700).fontColor(color).letterSpacing(1.5)
      Divider().layoutWeight(1).strokeWidth(1).color(this.T().line)
    }.width('100%').margin({ top: 1, bottom: 1 })
  }

  @Builder
  stepRow(s: AgentStep) {
    if (s.kind === 'done') {
      this.tlFinal(s)
    } else {
      Column() {
        Row({ space: 7 }) {
          Text(s.kind === 'instruction' ? '▸' :
            s.kind === 'review' ? '🔎' :
            s.kind === 'tool_start' ? '⏳' : (s.ok ? '✓' : '✗'))
            .fontSize(this.fp(F_TRACK_MID))   // batch-5：图标档（复审修正：现值 10，挂 F_TRACK_MID 防误挂 F_TRACK_BODY 致宽窗 10→10.5 漂移）
            .fontColor(s.ok ? this.T().accTx : this.T().danger)
            .width(16)
          Column({ space: 1 }) {
            Text(s.kind === 'instruction' ? this.foldText(s.label, 100) : s.label)
              .fontSize(this.fp(F_TRACK_BODY))   // batch-5：步骤 label（§3.3，10.5↔9.5）
              .fontWeight(s.kind === 'failed' ? 700 : (s.kind === 'review' ? 600 : 500))
              .fontColor(s.kind === 'failed' ? this.T().danger : this.T().tx)
              .maxLines(1)
            if (s.detail !== '') {
              Text(this.foldText(s.detail, 150)).fontSize(this.fp(F_TRACK_DETAIL)).fontColor(this.T().tx3)   // batch-5：detail（§3.3，9↔8）
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          if (s.ms > 0) {
            Text(`${s.ms}ms`).fontSize(this.fp(F_TRACK_MS)).fontColor(this.T().tx3)   // batch-5：ms 角标（§3.3，8.5↔8 贴地档）
          }
        }.width('100%')
        // 展开全文（仅超限字段；点击行切换 expandedStep 键）
        if (this.expandedStep === s.kind + s.label + String(s.ms) + s.detail) {
          Column({ space: 2 }) {
            if (s.kind === 'instruction' && s.label.length > 100) {
              Text(s.label).fontSize(this.fp(F_TRACK_MID)).fontColor(this.T().tx2)   // batch-5：展开标签（复审修正：现值 10，挂 F_TRACK_MID 防误挂 F_TRACK_DETAIL 致宽窗 10→9 漂移）
            }
            if (s.detail.length > 150) {
              Text(s.detail).fontSize(this.fp(F_TRACK_DETAIL)).fontColor(this.T().tx3)   // batch-5：展开 detail（现值 9 零漂移，§3.3）
            }
          }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 4 })
        }
      }.width('100%').padding({ left: 8, right: 8, top: 5, bottom: 5 })
      .borderRadius(8)
      .backgroundColor(s.kind === 'failed' ? this.T().dangerSoft : this.T().card)
      .border({ width: 1, color: s.kind === 'failed' ? this.T().dangerBorder :
        (s.kind === 'review' ? this.T().accTx : this.T().line) })   // M3.6.4：审查卡蓝边与执行卡区分
      .onClick(() => {
        const k = s.kind + s.label + String(s.ms) + s.detail;
        this.expandedStep = this.expandedStep === k ? '' : k;
      })
    }
  }

  /** done 绿胶囊（batch-5，audit-right-11 对齐 i:352-358 .tl-final）：全宽渐变绿 + 24px ✔
   * 圆徽 #10B981 + tlFinalPop .35s 入场（transition 键控重挂触发近似）；深色档 i:358 换算。 */
  @Builder
  tlFinal(s: AgentStep) {
    Row({ space: 11 }) {
      Text('✔')
        .fontSize(this.fp(F_TRACK_FINAL_GLYPH)).fontWeight(900).fontColor('#ffffff')   // r10 sz-track-2：✔ 字形断点（14↔13）；旁 24 高图标容器禁改
        .width(24).height(24).borderRadius(12)
        .backgroundColor('#10B981')
        .textAlign(TextAlign.Center)
        .shadow({ radius: 10, offsetY: 2, color: 'rgba(16,185,129,0.5)' })
      Column({ space: 1 }) {
        Text(s.label)
          .fontSize(this.fp(F_TRACK_FINAL)).fontWeight(800)   // batch-5：tlFinal 主行（§3.3，13.5↔12.5）
          .fontColor(this.isDark() ? '#D1FAE5' : '#065F46')
          .maxLines(2)
        if (s.detail !== '') {
          Text(s.detail).fontSize(this.fp(F_TRACK_FINAL_SUB)).fontColor(this.isDark() ? '#D1FAE5' : '#065F46').opacity(0.75)   // batch-5：副行（9.5↔9 贴地档）
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
    }.width('100%').padding({ left: this.sp(PAD_TRACK_FINAL_H), right: this.sp(PAD_TRACK_FINAL_H),
      top: this.sp(PAD_TRACK_FINAL_V), bottom: this.sp(PAD_TRACK_FINAL_V) })   // batch-5：收紧并做（§3.3 要点 3 tlFinal padding 13→10，16/13↔12/10）
    .borderRadius(14)
    .linearGradient({
      angle: 120,
      colors: this.isDark() ?
        [['rgba(16,185,129,0.26)', 0.0], ['rgba(52,211,153,0.10)', 1.0]] :
        [['rgba(52,211,153,0.28)', 0.0], ['rgba(167,243,208,0.14)', 1.0]]
    })
    .border({ width: 1, color: 'rgba(16,185,129,0.55)' })
    .shadow({ radius: 28, offsetY: 8, color: 'rgba(16,185,129,0.22)' })
    .margin({ top: 12 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 }))
      .animation({ duration: 350, curve: Curve.Friction }))   // tlFinalPop .35s 近似
  }

  /** 右栏空态卡（batch-5，audit-right-12 对齐 i:328-334 .empty-insp：dashed 边框卡+26px
   * 图标+居中；深色档 i:332-333 换算）。showKbd=insp 专属 kbd 两行（删除元素 Del/改文字 双击）。 */
  @Builder
  emptyCard(icon: string, title: string, desc: string, showKbd: boolean) {
    Column({ space: 6 }) {
      Text(icon).fontSize(26)
        .fontColor(this.isDark() ? 'rgba(255,255,255,0.22)' : 'rgba(0,0,0,0.18)')
      Text(title).fontSize(this.fp(F_EMPTY_HEAD)).fontWeight(600).fontColor(this.T().tx2)   // r10 sz-empty-1：题断点（12.5↔11.5）
      Text(desc).fontSize(this.fp(F_EMPTY_DESC)).fontColor(this.T().tx3).textAlign(TextAlign.Center)   // r10 sz-empty-1：描述断点（11↔10）
      if (showKbd) {
        Column({ space: 6 }) {
          Row() {
            Text('删除元素').fontSize(this.fp(F_EMPTY_HINT)).fontColor(this.T().tx3)   // r10 sz-empty-1：提示断点（10.5↔9.5）
            Blank()
            Text('Del').fontSize(this.fp(F_EMPTY_KBD)).fontColor(this.T().tx2)   // r10 sz-empty-1：kbd 断点（9.5↔9）
              .fontFamily('monospace')
              .padding({ left: 5, right: 5, top: 1, bottom: 1 }).borderRadius(4)
              .backgroundColor(this.isDark() ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.05)')
              .border({ width: 1, color: this.isDark() ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.08)' })
          }.width('100%')
          Row() {
            Text('改文字').fontSize(this.fp(F_EMPTY_HINT)).fontColor(this.T().tx3)   // r10 sz-empty-1
            Blank()
            Text('双击').fontSize(this.fp(F_EMPTY_KBD)).fontColor(this.T().tx2)   // r10 sz-empty-1
              .fontFamily('monospace')
              .padding({ left: 5, right: 5, top: 1, bottom: 1 }).borderRadius(4)
              .backgroundColor(this.isDark() ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.05)')
              .border({ width: 1, color: this.isDark() ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.08)' })
          }.width('100%')
        }.width('100%').margin({ top: 6 })
      }
    }.width('100%')
    .padding({ top: 22, bottom: 22, left: 10, right: 10 })
    .margin({ top: 10 })
    .borderRadius(12)
    .backgroundColor(this.isDark() ? 'rgba(255,255,255,0.045)' : 'rgba(0,0,0,0.015)')
    .border({ width: 1, style: BorderStyle.Dashed, color: this.isDark() ? 'rgba(255,255,255,0.17)' : 'rgba(0,0,0,0.1)' })
    .alignItems(HorizontalAlign.Center)
  }

  // ===== 右栏段钮族/单列行 builders（batch-5，audit-right-1/2/9）=====

  /** seg2 单钮（batch-5，audit-right-2 对齐 i:308-312 .seg2 button：高 26/1px rgba(0,0,0,.1)
   * 边/card 底/radius 7/10.5-600-tx2；on=acc 底白字+accTx 边；深色档 i:311 card 系近似）。
   * 【形态统一（用户截图点名「胶囊容器不协调」）】桌面 button flex:1 等宽；鸿蒙侧 Text
   * 自适应宽——单字钮（左/定/无…）宽≈字宽 < 高 26，radius 7 被钳制半宽渲染成**竖向小胶囊**，
   * 与「I 斜体/● 可见」宽钮（横向圆角矩形）同排混杂。width 100% 填满均分列回到桌面同形：
   * 全体等宽横向圆角矩形（宽>高，radius 7 不再触钳制）。 */
  @Builder
  segBtn(label: string, on: boolean, action: () => void) {
    Text(label)
      .fontSize(this.fp(F_INSP_LABEL)).fontWeight(600)   // r10 sz-insp-1：段钮断点字号（10.5↔9.5，复用 F_INSP_LABEL）
      .fontColor(on ? this.T().onAcc : this.T().tx2)
      .textAlign(TextAlign.Center)
      .width('100%')
      .height(this.sp(H_SEG)).borderRadius(7)   // r10 h-insp-1：段钮断点高（26↔23）
      .backgroundColor(on ? this.T().acc : this.T().card)
      .border({ width: 1, color: on ? this.T().accTx : 'rgba(0,0,0,0.1)' })
      .stateStyles({
        pressed: { .backgroundColor(on ? this.T().accTx : this.T().pressFill) },   // batch-4 iss-5：B 底色叠加（on 态 acc→按压色 accTx；HMOS=§9 按压实证 #0070E5/#1A7AE1）
        normal: { .backgroundColor(on ? this.T().acc : this.T().card) }
      })
      .onClick(() => { action(); })
  }

  /** 单列段钮行：label 52 固定列 + 均分段钮（对齐 .frow grid 52px 起始列）。 */
  @Builder
  segRow(label: string, sp: SegChipsSpec) {
    Row({ space: 6 }) {
      Text(label).fontSize(this.fp(F_INSP_LABEL)).fontWeight(500).fontColor(this.T().tx2).width(this.isNarrowBar() ? 40 : 52)   // r10 sz-insp-1/2：行标断点（10.5↔9.5）
      ForEach(sp.values, (v: string, i: number) => {
        Column() {
          this.segBtn(sp.labels[i], sp.current === v, (): void => { sp.onPick(v); })
        }.layoutWeight(1)
      }, (v: string) => v)
    }.width('100%').margin({ top: 6 })
  }

  /** 阴影 4 等分档钮（batch-5，audit-right-2 对齐 i:315-321 .segshadow）：40 高钮内叠
   * 24×9 演示块（#007aff 底）+按档递增阴影预览（e1/e2/e3 即 sm/lg/xl）；on=accTx 边+
   * rgba(0,122,255,.06) 底。 */
  @Builder
  shadowSegRow(label: string, sp: SegChipsSpec) {
    Row({ space: 6 }) {
      Text(label).fontSize(this.fp(F_INSP_LABEL)).fontWeight(500).fontColor(this.T().tx2).width(this.isNarrowBar() ? 40 : 52)   // r10 sz-insp-1/2：行标断点（10.5↔9.5）
      ForEach(sp.values, (v: string, i: number) => {
        Column({ space: 3 }) {
          // demo 块阴影随档递增（i:317-319 逐值）
          Column()
            .width(24).height(9).borderRadius(3)
            .backgroundColor('#007aff')
            .shadow(i === 1 ? { radius: 3, offsetY: 1, color: 'rgba(0,0,0,0.35)' } :
              i === 2 ? { radius: 9, offsetY: 4, color: 'rgba(0,0,0,0.4)' } :
              i === 3 ? { radius: 16, offsetY: 7, color: 'rgba(0,0,0,0.45)' } :
                { radius: 0, offsetX: 0, offsetY: 0, color: this.T().trans })
          Text(sp.labels[i]).fontSize(this.fp(F_SEGCHIP)).fontWeight(600)   // r10 sz-insp-1：档 chip 字断点（9↔8）；上半 3/9/16 阴影半径=预览数据禁改（sh-excl-1）
            .fontColor(sp.current === v ? this.T().accTx : this.T().tx2)
        }.justifyContent(FlexAlign.Center)
        .height(this.sp(H_SHADOW_ROW)).padding({ top: 5 }).borderRadius(8)   // r10 h-insp-2：预览行断点高（40↔36）
        .backgroundColor(sp.current === v ? 'rgba(0,122,255,0.06)' : this.T().card)
        .border({ width: 1, color: sp.current === v ? this.T().accTx : 'rgba(0,0,0,0.1)' })
        .layoutWeight(1)
        .onClick(() => { sp.onPick(v); })
      }, (v: string) => v)
    }.width('100%').margin({ top: 6 })
  }

  /** 单列双输入行：label 52 + 两输入均分（位置/尺寸/圆角透明/字号描边宽/间距内边距）。 */
  @Builder
  draftPairRow(label: string, a: DraftRowSpec, b2: DraftRowSpec) {
    Row({ space: 6 }) {
      Text(label).fontSize(this.fp(F_INSP_LABEL)).fontWeight(500).fontColor(this.T().tx2).width(this.isNarrowBar() ? 40 : 52)   // r10 sz-insp-1/2：行标断点（10.5↔9.5）
      TextInput({ text: a.val })
        .fontSize(this.fp(F_INSP_INPUT)).height(this.sp(H_DRAFT_INPUT)).borderRadius(7).layoutWeight(1)   // r10 sz-insp-2 + h-insp-3：草稿输入断点（11.5↔10.5 + 27↔24 同行联动）
        .fontFamily('monospace')
        .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
        .padding({ left: 7, right: 7, top: 0, bottom: 0 })
        .onChange((v: string) => {
          if (v === a.val) { return; }   // 程序化回声守卫（同 draftRow）
          a.onCh(v);
        })
        .onFocus(() => { this.onInputFocus(); })
        .onBlur(() => { this.onInputBlur(); })
      TextInput({ text: b2.val })
        .fontSize(this.fp(F_INSP_INPUT)).height(this.sp(H_DRAFT_INPUT)).borderRadius(7).layoutWeight(1)   // r10 sz-insp-2 + h-insp-3：草稿输入断点（11.5↔10.5 + 27↔24 同行联动）
        .fontFamily('monospace')
        .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
        .padding({ left: 7, right: 7, top: 0, bottom: 0 })
        .onChange((v: string) => {
          if (v === b2.val) { return; }
          b2.onCh(v);
        })
        .onFocus(() => { this.onInputFocus(); })
        .onBlur(() => { this.onInputBlur(); })
    }.width('100%').margin({ top: 6 })
  }

  /** 单列单输入行：label 52 + 输入占满（文本行）。 */
  @Builder
  draftSingleRow(label: string, sp: DraftRowSpec) {
    Row({ space: 6 }) {
      Text(label).fontSize(this.fp(F_INSP_LABEL)).fontWeight(500).fontColor(this.T().tx2).width(this.isNarrowBar() ? 40 : 52)   // r10 sz-insp-1/2：行标断点（10.5↔9.5）
      TextInput({ text: sp.val })
        .fontSize(this.fp(F_INSP_INPUT)).height(this.sp(H_DRAFT_INPUT)).borderRadius(7).layoutWeight(1)   // r10 sz-insp-2 + h-insp-3：草稿输入断点（11.5↔10.5 + 27↔24 同行联动）
        .fontFamily('monospace')
        .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
        .padding({ left: 7, right: 7, top: 0, bottom: 0 })
        .onChange((v: string) => {
          if (v === sp.val) { return; }
          sp.onCh(v);
        })
        .onFocus(() => { this.onInputFocus(); })
        .onBlur(() => { this.onInputBlur(); })
    }.width('100%').margin({ top: 6 })
  }

  /** 色板词表（batch-5，gap-detail-12）：预设轮换口径同 inlineAction（acc/danger/ok/purple/tx）
   * + card（登记扩展，深色卡面上第 6 档可见）。构建门修正：该方法随上一轮死代码清除被误删
   * （colorDraftRow 色块轮换仍引用）——按原登记口径恢复。 */
  private colorPalette(): string[] {
    return [this.T().acc, this.T().danger, this.T().ok, this.T().purple, this.T().tx, this.T().card];
  }

  /** 当前色的下一档（词表轮换；不在表中从头开始——同 inlineAction 取模口径）。 */
  private nextPaletteColor(current: string): string {
    const pal = this.colorPalette();
    const i = pal.indexOf(current);
    return pal[(i + 1) % pal.length];
  }

  /** 单列颜色草稿行：label + hex 输入 + 24 色块（点击词表轮换——仅写草稿，随应用提交）。 */
  @Builder
  colorDraftRow(label: string, sp: DraftRowSpec) {
    Row({ space: 6 }) {
      Text(label).fontSize(this.fp(F_INSP_LABEL)).fontWeight(500).fontColor(this.T().tx2).width(this.isNarrowBar() ? 40 : 52)   // r10 sz-insp-1/2：行标断点（10.5↔9.5）
      TextInput({ text: sp.val })
        .fontSize(this.fp(F_INSP_INPUT)).height(this.sp(H_DRAFT_INPUT)).borderRadius(7).layoutWeight(1)   // r10 sz-insp-2 + h-insp-3：草稿输入断点（11.5↔10.5 + 27↔24 同行联动）
        .fontFamily('monospace')
        .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
        .padding({ left: 7, right: 7, top: 0, bottom: 0 })
        .onChange((v: string) => {
          if (v === sp.val) { return; }
          sp.onCh(v);
        })
        .onFocus(() => { this.onInputFocus(); })
        .onBlur(() => { this.onInputBlur(); })
      Circle({ width: 24, height: 24 })
        .fill(sp.val.trim() !== '' ? sp.val : this.T().trans)
        .onClick(() => { sp.onCh(this.nextPaletteColor(sp.val.trim() !== '' ? sp.val : '#007aff')); })
    }.width('100%').margin({ top: 6 })
  }

  /** 可见性独立行（batch-5，audit-right-9 对齐 i:3189 可见性行 seg2 单钮）：● 可见/○ 已隐藏。 */
  @Builder
  visibilityRow() {
    Row({ space: 6 }) {
      Text('可见性').fontSize(this.fp(F_INSP_LABEL)).fontWeight(500).fontColor(this.T().tx2).width(this.isNarrowBar() ? 40 : 52)   // r10 sz-insp-2：行标断点（10.5↔9.5）
      Column() {
        this.segBtn((this.curLayer()?.style.visible ?? true) ? '● 可见' : '○ 已隐藏',
          this.curLayer()?.style.visible ?? true, (): void => {
            const b = this.curBoard(); const l = this.curLayer();
            if (b && l) { appStore.setStyle(b.id, l.id, 'visible', !l.style.visible); this.sync(); }
          })
      }.layoutWeight(1)
    }.width('100%').margin({ top: 6 })
  }

  /** 交互绑定与状态区（gap-right-3）。 */
  @Builder
  bindSection(b: Board, l: LayerNode) {
    Column({ space: 7 }) {
      Text('交互绑定').fontSize(this.fp(F_INSP_HEAD)).fontWeight(600).fontColor(this.T().tx)   // r10 sz-bind-1：段题断点（12.5↔11.5）
      Row({ space: 6 }) {
        Text('触发').fontSize(this.fp(F_INSP_MINI)).fontColor(this.T().tx2).width(30)   // r10 sz-bind-1：行标断点（9.5↔9）
        Row({ space: 4 }) {
          Text(this.bindTrigger).fontSize(this.fp(F_INSP_VAL)).fontColor(this.T().tx).maxLines(1)   // r10 sz-bind-1：值断点（10.5↔9.5）
          Text('▾').fontSize(8).fontColor(this.T().tx2)   // r10 sz-bind-1：箭头 8 两态同值保底
        }.height(this.sp(H_BIND_CHIP)).padding({ left: 8, right: 8, top: 0, bottom: 0 }).borderRadius(6)   // r10 h-bind-1：胶囊断点高（24↔21）
        .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
        .bindMenu(this.triggerMenuPanel)   // batch-4 dd-menu-trigger：自绘面板 168 宽（r9 修正：箭头形→引用形，同 exportMenuPanel）
      }.width('100%')
      Row({ space: 6 }) {
        Text('动作').fontSize(this.fp(F_INSP_MINI)).fontColor(this.T().tx2).width(30)   // r10 sz-bind-1
        ForEach(ACTIONS, (a: string) => {
          Text(a).fontSize(this.fp(F_INSP_ACT)).fontWeight(500)   // r10 sz-bind-1：动作项断点（10↔9）
            .fontColor(this.bindAction === a ? this.T().accTx : this.T().tx2)
            .padding({ left: 7, right: 7, top: 3, bottom: 3 }).borderRadius(5)
            .backgroundColor(this.bindAction === a ? this.T().accSoft : Color.Transparent)
            .onClick(() => { this.bindAction = a; })
        }, (a: string) => a)
      }.width('100%')
      if (this.bindAction === 'navigate_to') {
        Row({ space: 6 }) {
          Text('目标').fontSize(this.fp(F_INSP_MINI)).fontColor(this.T().tx2).width(30)   // r10 sz-bind-1
          Row({ space: 4 }) {
            Text(this.bindTarget === '' ? '选择画板…' : this.boardName(this.bindTarget))
              .fontSize(this.fp(F_INSP_VAL)).fontColor(this.bindTarget === '' ? this.T().tx3 : this.T().tx).maxLines(1)   // r10 sz-bind-1
            Text('▾').fontSize(8).fontColor(this.T().tx2)   // 保底 8
          }.height(this.sp(H_BIND_CHIP)).padding({ left: 8, right: 8, top: 0, bottom: 0 }).borderRadius(6)   // r10 h-bind-1
          .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
          .bindMenu(this.boardMenuPanel)   // batch-4 dd-menu-board：自绘面板 176 宽（boards 空时空组；箭头形→引用形）
        }.width('100%')
      } else if (this.bindAction === 'show_toast') {
        Row({ space: 6 }) {
          Text('文案').fontSize(this.fp(F_INSP_MINI)).fontColor(this.T().tx2).width(30)   // r10 sz-bind-1
          TextInput({ placeholder: 'toast 文案', text: this.bindTarget })
            .onChange((v: string) => { this.bindTarget = v; })
            .onFocus(() => { this.onInputFocus(); })
            .onBlur(() => { this.onInputBlur(); })
            .fontSize(this.fp(F_INSP_VAL)).placeholderFont({ size: this.fp(F_INSP_VAL) }).height(this.sp(H_BIND_CHIP)).lineHeight(this.sp(H_BIND_CHIP)).borderRadius(6).layoutWeight(1)   // r10 sz-bind-1 + h-bind-1：输入断点（10.5↔9.5 + 24↔21 同行联动）
            .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
            .padding({ left: 7, right: 7, top: 0, bottom: 0 })
        }.width('100%')
      }
      Row() {
        Blank()
        Text('+ 添加绑定').fontSize(this.fp(F_INSP_VAL)).fontWeight(600).fontColor(this.T().onAcc)   // r10 sz-bind-1：复审补挂站点断点（10.5↔9.5）
          .padding({ left: 10, right: 10, top: 4, bottom: 4 }).borderRadius(6)
          .backgroundColor(this.T().acc)
          .onClick(() => { this.addBinding(); })
      }.width('100%')
      // 已绑清单（只读 + 删除；同节点有 flow 时如实标注 flow 优先）
      if ((l.interactions ?? []).length > 0 || this.hasFlowOn(b, l)) {
        Column({ space: 4 }) {
          ForEach(l.interactions ?? [], (it: Interaction, i: number) => {
            Row({ space: 5 }) {
              Text(it.trigger).fontSize(this.fp(F_TRACK_DETAIL)).fontColor(this.T().purple)   // r10 sz-bind-1：触发 tag 断点（9↔8，复用 F_TRACK_DETAIL）
              Text(it.action === 'navigate_to' ? `${it.action} · ${this.boardName(it.target)}` :
                (it.target !== '' ? `${it.action} · ${it.target}` : it.action))
                .fontSize(this.fp(F_INSP_ACT)).fontColor(this.T().tx).maxLines(1).layoutWeight(1)   // r10 sz-bind-1：动作断点（10↔9）
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('✕').fontSize(8).fontColor(this.T().tx3)
                .onClick(() => {
                  appStore.removeInteraction(b.id, l.id, i);
                  this.sync();
                })
            }.width('100%').height(this.sp(H_BIND_ROW)).padding({ left: 6, right: 6 })   // r10 h-bind-2：绑定行断点高（22↔20）
            .borderRadius(5).backgroundColor(this.T().subtle)
          }, (it: Interaction) => it.trigger + it.action + it.target)
          if (this.hasFlowOn(b, l)) {
            Text('flow 优先：该节点已有画布连线，演示时连线跳转优先于绑定')
              .fontSize(this.fp(F_TRACK_MS)).fontColor(this.T().purple).width('100%')   // r10 sz-bind-1：flow 优先注断点（8.5↔8，复用 F_TRACK_MS）
          }
        }.width('100%')
      }
      Divider().color(this.T().bd).margin({ top: 2, bottom: 2 })
      Text('状态').fontSize(this.fp(F_INSP_HEAD)).fontWeight(600).fontColor(this.T().tx)   // r10 sz-bind-1：段题断点（12.5↔11.5）
      Row({ space: 6 }) {
        TextInput({ placeholder: '状态名（如 pressed）', text: this.stateName })
          .onChange((v: string) => { this.stateName = v; })
          .onFocus(() => { this.onInputFocus(); })
          .onBlur(() => { this.onInputBlur(); })
          .fontSize(this.fp(F_INSP_VAL)).placeholderFont({ size: this.fp(F_INSP_VAL) }).height(this.sp(H_BIND_CHIP)).lineHeight(this.sp(H_BIND_CHIP)).borderRadius(6).layoutWeight(1)   // r10 sz-bind-1 + h-bind-1：输入断点（10.5↔9.5 + 24↔21 同行联动）
          .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
          .padding({ left: 7, right: 7, top: 0, bottom: 0 })
        Text('+ 定义').fontSize(this.fp(F_INSP_ACT)).fontWeight(600).fontColor(this.T().accTx)   // r10 sz-bind-1：断点（10↔9）
          .padding({ left: 8, right: 8, top: 4, bottom: 4 }).borderRadius(6)
          .backgroundColor(this.T().accSoft)
          .onClick(() => {
            const ok = appStore.addState(b.id, l.id, this.stateName);
            if (ok) {
              this.stateName = '';
              this.toast('已定义状态');
              this.sync();
            } else {
              this.toast('状态名为空或已存在');
            }
          })
      }.width('100%')
      if ((l.states ?? []).length > 0) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(l.states ?? [], (s: StateDef) => {
            Text(`set-state ${s.name} toggle`).fontSize(this.fp(F_TRACK_DETAIL)).fontColor(this.T().tx)   // r10 sz-bind-1：状态 chip 断点（9↔8）
              .padding({ left: 7, right: 7, top: 3, bottom: 3 }).borderRadius(99)
              .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
              .margin({ right: 5, bottom: 5 })
              .onClick(() => {
                appStore.setStateToggle(b.id, l.id, s.name);   // 演示消费留待引擎回收
                this.toast(`set-state ${s.name} toggle`);
              })
          }, (s: StateDef) => s.name)
        }.width('100%')
      }
    }.width('100%').margin({ top: 10 })
  }

  /** MBT 源码大视图（gap-topbar-3 decl 态；gap-mbt-7/8/9/10 查看器 UI；batch-4 gap-mbt-11 行为收口）。
   * 只读唯一形态：Text+Span 高亮树，视图内无编辑组件——键盘编辑天然不可能（验收判据 4）。 */
  @Builder
  declView() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text('MBT 源码 · 唯一事实源').fontSize(this.fp(F_DECL_HEAD)).fontWeight(600).fontColor(this.T().tx)   // gap-mbt-8 + r10 sz-decl-1：题断点（14↔13）
        Blank()
        Text('⧉ 复制源码').fontSize(this.fp(F_DECL)).fontColor(this.T().accTx)   // r10 sz-decl-1：断点（11.5↔10.5）
          .onClick(() => { this.copySource(); })
        Row({ space: 4 }) {
          Text('↻').fontSize(this.fp(F_DECL_GLYPH)).fontColor(this.T().onAcc)   // r10 sz-decl-1：字形断点（11↔10）
          Text('重新序列化刷新').fontSize(this.fp(F_DECL)).fontWeight(600).fontColor(this.T().onAcc)   // gap-mbt-11 文案 + r10 sz-decl-1：断点（11.5↔10.5）
        }.height(this.sp(H_DECL_BTN)).padding({ left: 11, right: 11 }).borderRadius(this.T().rBtnSecondary)   // batch-3：次钮圆角 7→HMOS 14（§4 small_button/piece）+ r10 h-decl-1：断点高（26↔23）
        .backgroundColor(this.T().acc)
        .onClick(() => { this.revalidateSource(); })   // 三入口统一（gap-mbt-11）
      }.width('100%')
      // gap-mbt-8：interim 免责说明行整行删除（降级说明只留校验失败 toast）。
      // 只读展示态（gap-mbt-7）：Text+Span 七类 token 高亮，按行拆分渲染（每行一个 Text，
      // 见 declPieceRows）；跨行选择诚实降级，复制源码走 copySource 全文通道。
      // 行键含内容（同 r4 docEpoch 教训：同键 ForEach 不回填参数，纯 idx 键会漏染新文本）。
      // batch-4 只读优先取舍登记（gap-mbt-11 ③）：declDirty 草稿 TextArea 整支移除——应用路径
      // （JSON.parse→restore）已删、清空编辑器菜单已移除，草稿态不可达，.enabled(false) 随
      // TextArea 无对象；Text+Span 即实施指令预留的「唯一形态」降级路线：键盘编辑天然不可能，
      // 选择/复制经右键菜单 copySource 全文通道兜底（r2 已证伪的 .closable 不采用）。
      Scroll() {
        Column() {
          ForEach(this.declPieceRows(), (row: DeclPiece[], idx: number) => {
            Text() {
              ForEach(row, (p: DeclPiece, pi: number) => {
                Span(p.t)
                  .fontColor(p.cls === '' ? this.T().tx : this.tokColor(p.cls))
                  .fontStyle(p.cls === 'comment' ? FontStyle.Italic : FontStyle.Normal)
                  .fontWeight(p.cls === 'keyword' || p.cls === 'yaml-key' ? 600 : 400)
              }, (p: DeclPiece, pi: number): string => `${pi}|${p.cls}|${p.t}`)
            }
              .fontSize(this.fp(F_DECL)).lineHeight(this.fp(LH_DECL)).fontFamily('monospace')   // gap-mbt-9：11.5×1.65≈19（i:368）+ r10 sz-decl-1：正文断点（11.5↔10.5）+ 行距联动（19↔17，LH_DECL）
              .width('100%')
          }, (row: DeclPiece[], idx: number): string => {
            let k = `r${idx}|`;
            for (const p of row) {
              k += p.cls + ':' + p.t + '§';
            }
            return k;
          })
        }.width('100%')
      }
        .width('100%').layoutWeight(1)
        .scrollBar(BarState.Auto).scrollBarWidth(6).scrollBarColor(this.scrollThumb())
        .backgroundColor(this.codeBg()).borderRadius(10)   // gap-mbt-10：--code-bg/--code-line
        .border({ width: 1, color: this.codeLine() })
        .padding(14)   // gap-mbt-9：10→14（i:368 padding:14px）
        .bindContextMenu(this.declMenu(), ResponseType.RightClick)
    }.width('100%').height('100%').padding(16)
    // gap-mbt-10：stage-veil 底色（i:50 亮/i:61 暗）+ 毛玻璃。BlurStyle.Regular 兼容本仓两套
    // SDK 声明面（linter 副本枚举仅 Thin/Regular/Thick，无 ComponentRegular）。fadeUp ~180ms
    // 对齐 toast popIn 先例（opacity+translateY，去 scale）。
    .backgroundColor(this.stageVeil())
    .backgroundBlurStyle(BlurStyle.Regular)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 6 }))
      .animation({ duration: 180, curve: Curve.Friction }))
  }

  build() {
    Stack() {
      Column() {
      // ===== topbar（46px，token 对齐；batch-4 audit-topbar-1/2/3/5/6/12 重排）=====
      // 宽度预算：文字钮改 28×28 图标钮（SVG path 抄 i:821-824）、小艺徽章折叠、↶↷ 移出
      // （收进「导出▾」菜单——通用版顶栏无撤销/重做钮的显性扩展决策，见 exportMenu 登记）、
      // 两条 tsep（brand 后 i:785 / 设置组后 i:825）、操作组套横向 Scroll 兜底（audit-topbar-1
      // 还原态右端被裁的兜底通道）。
      // 响应式折叠（batch-1，iss-5，显性扩展决策）：通用版桌面无窄窗概念，鸿蒙自由窗口
      // 还原态 931vp 放不下全集（Scroll 只保证可达不保证初始可见，r4 验收 #16 判负口径是
      // 「不滚动即完整可见」）——topW<1200（isNarrowBar）时隐藏小艺徽章/▶ 演示/⚙ 设置，
      // 后两者收留「导出▾」菜单（exportMenu 窄窗分支）；宽窗（topW≥1200，最大化 1560vp）
      // 全集与双 Blank 居中保持原样。校准预案：dump 仍断溢出则续折「保存」tbtn 入菜单、
      // 窄窗隐藏 filechip（r4 §4.1 教训：坐标逐构建漂移，验收每次 dump 新坐标）。
      // r5 重构（batch-1 判据 B 复负修复）：原「整段 Scroll + 内层 Row minWidth '100%'」实测
      // 失效——横向 Scroll 主轴约束无穷，百分比 minWidth 无解析基准，内层 Row 退化为内容宽，
      // Blank 零宽 → mode-seg/操作组全组紧排靠左（r5 dump：mode-seg 中心 917.5≠窗心 1560、
      // DDP 右缘 1968）。改两态：宽窗（topW≥1200）弃 Scroll——左簇+Blank+操作组直接排布，
      // mode-seg 走全宽居中 overlay（窗口绝对居中，判据口径；桌面 margin:auto 在左右簇不等宽
      // 时亦不落窗心，此处显性取窗心=显性扩展决策登记）；窄窗保留整段 Scroll 作可达兜底。
      // M3.6.1：mode-seg 回归桌面入流居中——桌面 i:787 实构为
      // [左簇][spacer flex:1][mode-seg][spacer flex:1][右簇]（双 spacer 夹持居中）。
      // r5 的「全宽窗心 overlay」与本窗实测冲突：还原态 topW≈1170 时 seg 实测 [565..845]
      // 与 opsGroup [771..1181] 物理重叠 74vp——MBT 源码药丸压住小艺徽章/新建钮
      // （2026-10-05 用户截图红框点名；overlay 透明底穿帮）。入流后 Row 顺序布局
      // 不可能重叠；Blank×layoutWeight(1) 均分剩余空间=桌面双 spacer 同构，
      // 左右簇不等宽时 seg 中心≠窗心（=桌面 margin:auto 真实语义，撤销 r5
      // 「显性取窗心」偏离登记）。窄窗压缩：药丸 padding 13→10、操作组间距 6→4，
      // 使 minWidth 980 档溢出从 ~65vp 收敛到 ~39vp（<1010vp 角落导出DDP 右缘
      // 轻裁=桌面同族物理，全集恒在不隐藏不滚动）。
      Row({ space: 6 }) {
        this.topbarLeft()
        Blank().layoutWeight(1)
        this.modeSeg()
        Blank().layoutWeight(1)
        this.opsGroup()
      }
      .width('100%').height(this.sp(H_TOPBAR)).padding({ left: 12, right: 14 })   // r10 h-topbar-1：顶栏壳断点高（46↔40）
      .backgroundColor(this.T().panelT).border({ width: { bottom: 1 }, color: this.T().bd })
      .alignItems(VerticalAlign.Center)
      // 顶栏实测宽（batch-1，iss-5）：isNarrowBar 折叠判定输入；r4 §4.1 教训——坐标逐构建
      // 漂移，验收每次 dump 新坐标，故此处 hilog 记 topW 与当帧折叠集合供 dump 对账
      .onAreaChange((o: Area, n: Area): void => {
        this.topW = Number(n.width);
        hilog.info(0x0000, 'ddTopBar', 'topW=%{public}s fold=full-set(inflow)', Number(n.width).toString());
      })

      // ===== 主区 =====
      Row() {
        // ---- left 252px ----
        Column() {
          // proj-card 常驻项目区（batch-6，audit-left-1 对齐 i:838-847：拆两行——头行 pc-head
          // 项目名 12.5/600+caret 10 bindMenu 整行可点 / 第二行两枚等宽 28 高钮「＋ 新建」「打开…」；
          // 可折叠最近列表与 batch-3 relTime 保留）
          Column({ space: 5 }) {
            Row({ space: 7 }) {
              Text(this.projName).fontSize(this.fp(F_PROJNAME_L)).fontWeight(600).fontColor(this.T().tx)   // batch-5：左栏项目区大字（§3.2/:5636 旧载，12.5↔11.5）
                .maxLines(1).layoutWeight(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('▾').fontSize(this.fp(F_LPROJ_ARROW)).fontColor(this.T().tx3)   // r10 sz-lproj-1：▾ 断点（10↔9）
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding({ left: 5, right: 5, top: 3, bottom: 3 }).borderRadius(7)
            .bindMenu(this.recentMenu())
            .onClick(() => { this.recent = projectRegistry.list(); })   // 整行可点（下拉同锚）
            Row({ space: 6 }) {
              Text('＋ 新建').fontSize(this.fp(F_LBTN)).fontWeight(500).fontColor(this.T().tx2)   // r10 sz-lproj-2：断点字号（11.5↔10.5）
                .textAlign(TextAlign.Center)
                .height(this.sp(H_LBTN)).lineHeight(this.sp(H_LBTN)).borderRadius(this.T().rBtnSecondary).layoutWeight(1)   // batch-3：＋新建/打开 7→HMOS 14（§4 small_button；两处合并）+ r10 h-lbtn-1：断点高（28↔25）
                .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
                .stateStyles({
                  pressed: { .backgroundColor(this.T().pressFill) },   // batch-4 iss-5：B 底色叠加（中性钮=subtle 提一档）
                  normal: { .backgroundColor(this.T().card) }
                })
                .onClick(() => { this.actNew(); })
              Text('打开…').fontSize(this.fp(F_LBTN)).fontWeight(500).fontColor(this.T().tx2)   // r10 sz-lproj-2：断点字号（11.5↔10.5）
                .textAlign(TextAlign.Center)
                .height(this.sp(H_LBTN)).lineHeight(this.sp(H_LBTN)).borderRadius(this.T().rBtnSecondary).layoutWeight(1)   // batch-3：＋新建/打开 7→HMOS 14（§4 small_button；两处合并）+ r10 h-lbtn-1：断点高（28↔25）
                .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
                .stateStyles({
                  pressed: { .backgroundColor(this.T().pressFill) },   // batch-4 iss-5：B 底色叠加（同上）
                  normal: { .backgroundColor(this.T().card) }
                })
                .onClick(() => { this.actOpen(); })
            }.width('100%')
            if (this.recent.length > 0) {
              Row({ space: 4 }) {
                Text(this.showRecentList ? '▾' : '▸').fontSize(this.fp(F_LSEC_MINI)).fontColor(this.T().tx3)   // r10 sz-lproj-3：▸▾ 断点（8.5↔8）
                Text(`最近项目（${this.recent.length}）`).fontSize(this.fp(F_LRECENT_HEAD)).fontColor(this.T().tx3)   // r10 sz-lproj-3：头断点（9.5↔9，F_LRECENT_HEAD 消歧改名）
              }
              .onClick(() => { this.showRecentList = !this.showRecentList; })
            }
            if (this.showRecentList) {
              ForEach(this.recent, (it: RecentItem) => {
                Row({ space: 6 }) {
                  Text(it.path === appStore.filePath ? '✓' : '')
                    .fontSize(this.fp(F_LRECENT_CHECK)).fontColor(this.T().accTx).width(14).textAlign(TextAlign.Center)   // r10 sz-lproj-4：✓列断点（10↔9，F_LRECENT_CHECK 拆分）
                  Text(it.name).fontSize(this.fp(F_LRECENT))
                    .fontWeight(it.path === appStore.filePath ? 600 : 400).fontColor(this.T().tx)
                    .maxLines(1).layoutWeight(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }.width('100%').height(this.sp(H_LRECENT_ROW)).borderRadius(6)   // r10 h-lproj-1：最近行断点高（26↔23）；batch-3 误挂 menuRow 后本站补收（h-lproj-1 原站点）
                .stateStyles({
                  pressed: { .backgroundColor(it.path === appStore.filePath ? this.T().accSoft : this.T().pressFill) },   // batch-4 iss-5：B 底色叠加（当前项保色）
                  normal: { .backgroundColor(it.path === appStore.filePath ? this.T().accSoft : Color.Transparent) }
                })
                .onClick(() => { this.hotSwitch(it.path); })
              }, (it: RecentItem) => it.path + String(it.ts))
            }
          }.width('100%')
          .padding({ left: 10, right: 10, top: 9, bottom: 8 })
          .backgroundColor(this.isDark() ? 'rgba(255,255,255,0.02)' : 'rgba(0,0,0,0.015)')
          .border({ width: { bottom: 1 }, color: this.T().bd })
          // 左栏三 tab（batch-6，audit-left-2 对齐 i:123-128 .ltabs/.ltab：13×13 线性图标
          // 菱形堆/四宫格/流程折线（i:850-852 path 逐字）+on 态分色 600+tint 底+底部 2px 分色条；
          // 图标 viewPort 归 Shape 容器——batch-4 构建门教训）。r12 fix-topbar-3 同案：
          // Path==Shape 13 也中双重缩放定律（spec §一实测 5.8vp）——24×24 基底+.scale(13/24)
          // +13×13 Stack 保布局（space 5 间距按 13 计）
          Row() {
            ForEach(this.tabs, (t: string, i: number) => {
              Row({ space: 5 }) {
                Stack() {
                  Shape() {
                    Path().commands(i === 0 ? 'M12 3l9 5-9 5-9-5z M3 13l9 5 9-5' :
                      i === 1 ? 'M3.5 3.5h7v7h-7z M13.5 3.5h7v7h-7z M3.5 13.5h7v7h-7z M13.5 13.5h7v7h-7z' :
                        'M9 6a3 3 0 1 0-6 0a3 3 0 1 0 6 0z M21 18a3 3 0 1 0-6 0a3 3 0 1 0 6 0z M6 9v3a3 3 0 0 0 3 3h6')
                      .width(24).height(24)
                      .fillOpacity(0)
                      .stroke(this.tabIdx === i ? this.tabColor(i) : this.T().tx2).strokeWidth(1.7)
                      .strokeLineCap(LineCapStyle.Round).strokeLineJoin(LineJoinStyle.Round)
                  }
                  .viewPort({ x: 0, y: 0, width: 24, height: 24 })
                  .width(24).height(24)
                  .scale({ x: 13 / 24, y: 13 / 24 })   // r12 fix-topbar-3：B 案（S=13=桌面 .ltab .ic）
                }.width(13).height(13)
                Text(t).fontSize(this.fp(F_LTAB))
                  .fontWeight(this.tabIdx === i ? 600 : 500)   // r10 sz-ltab-1：tab 断点字号（12↔11）
                  .fontColor(this.tabIdx === i ? this.tabColor(i) : this.T().tx2)
              }.justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
              .layoutWeight(1).height(this.sp(H_LTAB))   // r10 h-ltab-1：tab 断点高（37↔33）
              .border({ width: { bottom: 2 }, color: this.tabIdx === i ? this.tabColor(i) : this.T().trans })
              .backgroundColor(this.tabIdx === i ? this.tabTint(i) : Color.Transparent)
              .onClick(() => { this.tabIdx = i; })
            }, (t: string) => t)
          }.width('100%').backgroundColor('rgba(0,0,0,0.02)')
          .border({ width: { bottom: 1 }, color: this.T().bd })
          Scroll() {
            Column() {
              if (this.tabIdx === 0) {
                // 画板组（sec 节头 batch-6，audit-left-11 对齐 i:143 .sec：10/700/tx3/大写距
                // .08em/margin 10 4 7；计数 600）
                Row() {
                  Text('画布页面').fontSize(this.fp(F_LSEC)).fontWeight(700).fontColor(this.T().tx3).letterSpacing(0.8)   // r10 sz-lboard-1：分区头断点（10↔9）
                  Blank()
                  Text(String(this.boards.length)).fontSize(this.fp(F_LSEC)).fontWeight(600).fontColor(this.T().tx3)   // r10 sz-lboard-1：计数断点（10↔9）
                }.width('100%').margin({ top: 10, bottom: 7, left: 4, right: 4 })
                ForEach(this.boards, (b: Board) => {
                  // 画板行（batch-6，audit-left-3 对齐 i:150-155 .abrow：选中 1px rgba(0,122,255,.35)
                  // 边（深色 rgba(10,132,255,.45)）+12×12 圆角矩形描边板图标（active acc/否则 tx3）+
                  // ⛓ 药丸徽标（700/padding 1×6/radius 99/accSoft 底 accTx 字）+尺寸 9.5 monospace
                  Row({ space: 8 }) {
                    // 板图标：12×12 圆角矩形描边符号（替 Circle 6×6 圆点）
                    Rect({ width: 12, height: 12 }).radius(3)
                      .fill(Color.Transparent)
                      .stroke(b.id === this.selBoard ? this.T().acc : this.T().tx3).strokeWidth(1.6)
                      Text(b.name).fontSize(this.fp(F_LBOARD)).fontWeight(b.id === this.selBoard ? 600 : 400)   // r10 sz-lboard-1：板名断点（12↔11）
                      .fontColor(b.id === this.selBoard ? this.T().accTx : this.T().tx).maxLines(1)
                      .layoutWeight(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    // ⛓N 出向流计数药丸（>0 才显）+「当前」徽标+尺寸（gap-canvas-14；rev 退役登记同前）
                    if (this.flows.filter((f: Flow): boolean => f.fromBoard === b.id).length > 0) {
                      Text(`⛓${this.flows.filter((f: Flow): boolean => f.fromBoard === b.id).length}`)
                        .fontSize(this.fp(F_LBOARD_MINI)).fontWeight(700).fontColor(this.T().accTx)   // r10 sz-lboard-1：⛓徽章断点（8.5↔8）
                        .padding({ left: 6, right: 6, top: 1, bottom: 1 }).borderRadius(99)
                        .backgroundColor(this.T().accSoft)
                    }
                    if (b.id === this.selBoard) {
                      Text('当前').fontSize(this.fp(F_LBOARD_MINI)).fontColor(this.T().okText)   // r10 sz-lboard-1：当前徽章断点（8.5↔8）
                        .padding({ left: 6, right: 6, top: 1, bottom: 1 }).borderRadius(99)
                        .backgroundColor(this.T().okSoft)
                    }
                    Text(`${b.width}×${b.height}`)
                      .fontSize(this.fp(F_LBOARD_DIM)).fontFamily('monospace').fontColor(this.T().tx3)   // r10 sz-lboard-1：尺寸断点（9.5↔9）
                    Text('✕').fontSize(this.fp(F_LBOARD_X)).fontColor(this.T().tx3)   // r10 sz-lboard-1：✕ 断点（9↔8）
                      .onClick(() => { this.confirmDeleteBoard(b.id); })   // gap-global-2：删板红染确认
                  }.width('100%').height(this.sp(H_LBOARD_ROW)).borderRadius(6)   // r10 h-lboard-1：行断点高（28↔25）
                  .padding({ left: 6, right: 6 }).margin({ bottom: 2 })
                  .backgroundColor(b.id === this.selBoard ? 'rgba(0,122,255,0.08)' : Color.Transparent)
                  .border({
                    width: 1,
                    color: b.id === this.selBoard ?
                      (this.isDark() ? 'rgba(10,132,255,0.45)' : 'rgba(0,122,255,0.35)') : Color.Transparent
                  })
                  .stateStyles({
                    pressed: { .backgroundColor(b.id === this.selBoard ? 'rgba(0,122,255,0.08)' : this.T().pressFill) },   // batch-4 iss-5：B 底色叠加（选中态保选色）
                    normal: { .backgroundColor(b.id === this.selBoard ? 'rgba(0,122,255,0.08)' : Color.Transparent) }
                  })
                  .onClick(() => { this.selBoard = b.id; this.clearBoardSwitchState(); })
                  // 画板菜单双通道（batch-1 后板卡 chrome 已恒高 30vp、长按可达；左栏仍保留同锚点）
                  .bindContextMenu(this.boardMenuCtx(b), ResponseType.RightClick)
                  .bindContextMenu(this.boardMenuCtx(b), ResponseType.LongPress)
                }, (b: Board) => `${b.id}|${b.rev}`)
                if (this.boards.length === 0) {
                  // 空态 hintbox 左对齐（batch-6，audit-left-7 对齐 i:187 .hintbox：11/1.8/padding 6×4）
                  Text('无画板 — 点下方模板卡或 Prompt 生成')
                    .fontSize(this.fp(F_LEMPTY)).fontColor(this.T().tx3)   // r10 sz-lboard-2：空态断点（11↔10）
                    .lineHeight(this.fp(LH_LEMPTY)).padding({ left: 4, right: 4, top: 6, bottom: 6 }).width('100%')   // r10 ③：空态行距联动（20↔18，LH_LEMPTY）
                }
                Divider().color(this.T().bd).margin({ top: 10, bottom: 10 })
                // 图层组
                Row() {
                  Text('图层').fontSize(this.fp(F_LSEC)).fontWeight(700).fontColor(this.T().tx3).letterSpacing(0.8)   // r10 sz-lboard-2：分区头断点（10↔9）
                  Blank()
                  Text(String(this.curBoard()?.layers.length ?? 0)).fontSize(this.fp(F_LSEC)).fontWeight(600).fontColor(this.T().tx3)   // r10 sz-lboard-2：计数断点（10↔9）
                }.width('100%').margin({ top: 10, bottom: 7, left: 4, right: 4 })
                // 图层树空态兜底（batch-6，audit-left-7：无板→「无画板」/空板→「空画板」hintbox）
                if (this.boards.length === 0) {
                  Text('无画板').fontSize(this.fp(F_LEMPTY)).fontColor(this.T().tx3)   // r10 sz-lboard-2：空态断点（11↔10）
                    .lineHeight(this.fp(LH_LEMPTY)).padding({ left: 4, right: 4, top: 6, bottom: 6 }).width('100%')   // r10 ③：空态行距联动（20↔18，LH_LEMPTY）
                } else if ((this.curBoard()?.layers.length ?? 0) === 0) {
                  Text('空画板 — 点组件格或对 Agent 说「做一个 XX 组件」')
                    .fontSize(this.fp(F_LEMPTY)).fontColor(this.T().tx3)   // r10 sz-lboard-2：空态断点（11↔10）
                    .lineHeight(this.fp(LH_LEMPTY)).padding({ left: 4, right: 4, top: 6, bottom: 6 }).width('100%')   // r10 ③：空态行距联动（20↔18，LH_LEMPTY）
                }
                ForEach(this.curBoard()?.layers ?? [], (l: LayerNode) => {
                  this.layerRow(l)
                }, (l: LayerNode) => `${this.selBoard}/${l.id}`)
              } else if (this.tabIdx === 1) {
                // 组件面板（gap-leftcomp-1）：搜索 + stub 双钮 + 虚线引导卡 + 分类折叠组 +
                // 组件格网格（batch-6，audit-left-9/11）
                Column({ space: 8 }) {
                  TextInput({ placeholder: '搜索组件…', text: this.compQuery })
                    .onChange((v: string) => { this.compQuery = v; })
                    .onFocus(() => {
                      this.onInputFocus();
                      this.compSearchFocused = true;
                    })
                    .onBlur(() => {
                      this.onInputBlur();
                      this.compSearchFocused = false;
                    })
                    .fontSize(this.fp(F_LSEARCH)).placeholderFont({ size: this.fp(F_LSEARCH) }).height(this.sp(H_LSEARCH)).borderRadius(this.T().rInput)   // r10 sz-lsearch-1 + h-lsearch-1：断点（12↔11 + 30↔27 同行联动）；占位字号对齐（2997e4d 同类漏网补齐）
                    // batch-3：输入框圆角 7→HMOS 20（§4 text_field）。
                    // i:164 .compsearch：rgba(0,0,0,.045) 弱填充底/focus 白底+acc 边（batch-6 audit-left-11）
                    .backgroundColor(this.compSearchFocused ? this.T().card : (this.isDark() ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.045)'))
                    .border({ width: 1, color: this.compSearchFocused ? this.T().accTx : this.T().chipLine })   // 未聚焦边 iss-4 token 化（原 rgba(0,0,0,0.07) 深档不可见）
                    .padding({ left: 8, right: 8, top: 0, bottom: 0 })
                  // stub 双钮（batch-6，audit-left-9 对齐 i:856-858：◆ 画板→组件 acc 描边 tint 底
                  // flex 1.2 / 导入 MCF；点击统一诚实降级 toast——USERCOMP_UNAVAILABLE 语义）
                  Row({ space: 6 }) {
                    Text('◆ 画板 → 组件').fontSize(this.fp(F_INSP_LABEL)).fontWeight(500).fontColor(this.T().accTx)   // r10 sz-lcomp-1：断点字号（10.5↔9.5）
                      .textAlign(TextAlign.Center)
                      .height(this.sp(H_LBTN)).lineHeight(this.sp(H_LBTN)).borderRadius(7).layoutWeight(1.2)   // r10 h-lbtn-1：画板→组件断点高（28↔25）
                      .backgroundColor('rgba(0,122,255,0.06)')
                      .border({ width: 1, color: 'rgba(0,122,255,0.3)' })
                      .onClick(() => { this.toast('用户组件库尚未接线——画板沉淀暂不可用'); })
                    Text('导入 MCF').fontSize(this.fp(F_INSP_LABEL)).fontWeight(500).fontColor(this.T().tx2)   // r10 sz-lcomp-1：断点字号（10.5↔9.5）
                      .textAlign(TextAlign.Center)
                      .height(this.sp(H_LBTN)).lineHeight(this.sp(H_LBTN)).borderRadius(7).layoutWeight(1)   // batch-3 登记：导入 MCF stub 未列明于 rBtnSecondary 表面清单，保持桌面现值 7 不动 + r10 h-lbtn-1：断点高（28↔25）
                      .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
                      .onClick(() => { this.toast('用户组件库尚未接线——MCF 导入暂不可用'); })
                  }.width('100%')
                  // 虚线引导卡（i:861-872 逐字；⚠ 登记触屏点击放置为保底通道——拖拽见 compCell 手势）
                  Column({ space: 2 }) {
                    Text('如何自定义组件').fontSize(this.fp(F_INSP_LABEL)).fontWeight(700).fontColor(this.T().accTx)   // r10 sz-lcomp-1：断点字号（10.5↔9.5）
                    Text('① 在画布中设计好你的组件样式').fontSize(this.fp(F_INSP_LABEL)).fontColor(this.T().tx3)   // r10 sz-lcomp-1：三步断点（10.5↔9.5）
                    Text('② 点上方「画板 → 组件」保存到本地').fontSize(this.fp(F_INSP_LABEL)).fontColor(this.T().tx3)   // r10 sz-lcomp-1
                    Text('③ 在下方「我的组件」分区拖入复用').fontSize(this.fp(F_INSP_LABEL)).fontColor(this.T().tx3)   // r10 sz-lcomp-1
                    Text('Agent 也能帮你生成：对 Prompt 说「做一个 XX 组件」')
                      .fontSize(this.fp(F_LCOMP_NOTE)).fontColor(this.T().tx3).opacity(0.75).margin({ top: 2 })   // r10 sz-lcomp-1：注释行断点（9.5↔9）
                    Text('⚠ 用户组件库尚未接线——上述按钮当前会提示不可用')
                      .fontSize(this.fp(F_LCOMP_NOTE)).fontColor(this.T().tx3).opacity(0.75)   // r10 sz-lcomp-1：注释行断点（9.5↔9）
                    Text('组件格点击 = 放置到活动画板中心（保底通道）；长按拖拽可落到指定画板')
                      .fontSize(this.fp(F_LCOMP_NOTE)).fontColor(this.T().tx3).opacity(0.75)   // r10 sz-lcomp-1：注释行断点（9.5↔9）
                  }.width('100%').alignItems(HorizontalAlign.Start)
                  .padding({ left: 10, right: 10, top: 8, bottom: 8 }).borderRadius(9)
                  .backgroundColor('rgba(0,122,255,0.03)')
                  .border({ width: 1, style: BorderStyle.Dashed, color: 'rgba(0,122,255,0.25)' })
                  if (this.comps.length === 0) {
                    Text('组件库加载中…（rawfile/vendor/components.json）')
                      .fontSize(this.fp(F_LCOMP_HOW)).fontColor(this.T().tx3).padding({ top: 8 }).width('100%')   // r10 sz-lcomp-1：注断点（11↔10）
                      .textAlign(TextAlign.Center)
                  }
                  ForEach(this.compCats(), (cat: string) => {
                    if (this.compCount(cat) > 0) {
                      Column({ space: 6 }) {
                        Row({ space: 5 }) {
                          Text(this.closedCats.includes(cat) ? '▸' : '▾').fontSize(this.fp(F_LCOMP_MINI)).fontColor(this.T().tx3)   // r10 sz-lcomp-2：▸▾ 断点（9↔8）
                          Text(this.catLabel(cat)).fontSize(this.fp(F_LCOMP_CAT)).fontWeight(600).fontColor(this.T().tx2)   // r10 sz-lcomp-2：组名断点（11↔10）
                          Blank()
                          Text(String(this.compCount(cat))).fontSize(this.fp(F_LCOMP_COUNT)).fontColor(this.T().tx3)   // r10 sz-lcomp-2：计数断点（10↔9，F_LCOMP_COUNT 拆分）
                        }.width('100%')
                        .onClick(() => { this.toggleCat(cat); })
                        if (!this.closedCats.includes(cat)) {
                          if (this.compsIn(cat).length === 0) {
                            // 「我的组件」空类目引导 hint（batch-6，audit-left-9）
                            Text('空 — 沉淀画板或导入 MCF 后出现在这里')
                              .fontSize(this.fp(F_LEMPTY)).fontColor(this.T().tx3)   // r10 sz-lcomp-2：空态断点（11↔10）
                              .lineHeight(this.fp(LH_LEMPTY)).padding({ left: 4, right: 4, top: 6, bottom: 6 }).width('100%')   // r10 ③：空态行距联动（20↔18，LH_LEMPTY）
                          }
                          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                            ForEach(this.compsIn(cat), (c: CompDef) => {
                              this.compCell(c)
                            }, (c: CompDef) => c.id)
                          }.width('100%')
                        }
                      }.width('100%')
                    }
                  }, (cat: string) => cat)
                }.width('100%').padding({ top: 2 })
              } else {
                // 流程面板（batch-6，audit-left-5/6/7 对齐 i:874-880）：「交互流 N」计数头 +
                // 单行 ⛓ monospace 白底边框流程卡 + 尾部「Story / 意图」sec 与 hintbox。
                // 行语义登记（batch-4，gap-detail-10 后半）：维持 name→板名 可读语义（人读清单）；
                // 画布药丸用 触发文字前10字→板id（flowPillLabel）——两处取值口径有意不同。
                Row() {
                  Text('交互流').fontSize(this.fp(F_LSEC)).fontWeight(700).fontColor(this.T().tx3).letterSpacing(0.8)   // r10 sz-lflow-1：分区头断点（10↔9）
                  Blank()
                  Text(String(this.flows.length)).fontSize(this.fp(F_LSEC)).fontWeight(600).fontColor(this.T().tx3)   // r10 sz-lflow-1：计数断点（10↔9）
                }.width('100%').margin({ top: 10, bottom: 7, left: 4, right: 4 })
                if (this.flows.length === 0) {
                  // 空态逐字 i:877（b 加粗片段以 fontWeight 拼行，左对齐 hintbox；
                  // alignItems 为 Flex 构造参数——构建门修正：FlexAttribute 无 alignItems 属性）
                  Flex({
                    wrap: FlexWrap.Wrap,
                    justifyContent: FlexAlign.Start,
                    alignItems: ItemAlign.Center
                  }) {
                    Text('暂无跳转。选中按钮后对 Agent 说「').fontSize(this.fp(F_LFLOW)).fontColor(this.T().tx3)   // r10 sz-lflow-1：空态断点（11↔10）
                    Text('链接 p2').fontSize(this.fp(F_LFLOW)).fontWeight(700).fontColor(this.T().tx2)   // r10 sz-lflow-1
                    Text('」，或 Ctrl+K → ').fontSize(this.fp(F_LFLOW)).fontColor(this.T().tx3)   // r10 sz-lflow-1
                    Text('flow p1 p2 节点').fontSize(this.fp(F_LFLOW)).fontWeight(700).fontColor(this.T().tx2)   // r10 sz-lflow-1
                  }
                  .padding({ left: 4, right: 4, top: 6, bottom: 6 }).width('100%')
                }
                ForEach(this.flows, (f: Flow) => {
                  // 单行 ⛓ 卡（audit-left-5 对齐 i:183 .flowrow：mono 10.5/白卡底/1px rgba(0,0,0,.07)
                  // 边/radius 9/padding 7×9；✕ opacity .55）
                  Row({ space: 7 }) {
                    Text('⛓').fontSize(this.fp(F_LFLOW_ID))   // r10 sz-lflow-1：⛓ 断点（10.5↔9.5）
                    Text(`${this.flowFromName(f)} → ${this.flowToName(f)}（${f.trigger}）`)
                      .fontSize(this.fp(F_LFLOW_ID)).fontFamily('monospace').fontColor(this.T().tx2)   // r10 sz-lflow-1：id 断点（10.5↔9.5）
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                    Text('✕').fontSize(this.fp(F_LFLOW)).fontColor('#cc3333').opacity(0.55)   // r10 sz-lflow-1：✕ 断点（11↔10）
                      .padding({ left: 3, right: 3 })
                      .onClick(() => {
                        this.consumeClick();   // 阻止冒泡到行级跳转
                        appStore.unflow(f.id);
                        this.sync();
                        this.toast('已删除交互流');
                      })
                  }.width('100%').padding({ left: 9, right: 9, top: 7, bottom: 7 })
                  .borderRadius(9)
                  .backgroundColor(this.T().card)
                  .border({ width: 1, color: this.T().chipLine })   // iss-4：flowrow 边框 token 化（原硬编码 rgba(0,0,0,0.07)）
                  .margin({ bottom: 3 })
                  .alignItems(VerticalAlign.Center)
                  .onClick(() => {
                    if (this.clickConsumed()) return;   // ✕ 已消费本次点击
                    this.selBoard = f.toBoard;   // 行点击跳目标板
                    this.clearBoardSwitchState();   // 切板清选中+行内 Agent 浮层（gap-canvas-3）
                    this.sync();
                  })
                }, (f: Flow) => f.id)
                // Story / 意图 sec + hintbox（audit-left-6，i:879-880 逐字）
                Row() {
                  Text('Story / 意图').fontSize(this.fp(F_LSEC)).fontWeight(700).fontColor(this.T().tx3).letterSpacing(0.8)   // r10 sz-lflow-2：分区头断点（10↔9）
                }.width('100%').margin({ top: 10, bottom: 7, left: 4, right: 4 })
                Column({ space: 2 }) {
                  Text('用底部 Prompt 条描述流程意图：').fontSize(this.fp(F_LFLOW)).fontColor(this.T().tx3)   // r10 sz-lflow-2：断点（11↔10）
                  Text('「登录后跳转仪表盘」→ Agent 自动建立交互流。').fontSize(this.fp(F_LFLOW)).fontColor(this.T().tx3)   // r10 sz-lflow-2
                }.width('100%').alignItems(HorizontalAlign.Start)
                .padding({ left: 4, right: 4, top: 6, bottom: 6 })
              }
            }.width('100%').padding(10)
          }.layoutWeight(1).scrollBar(BarState.Auto)
          .scrollBarWidth(6).scrollBarColor(this.scrollThumb())   // i:24-25 6px 淡灰 thumb（batch-1，audit-left-12）
          // batch-7 cur-1：右栏折叠期空态引导移左栏（原右栏 emptyCard「未选中元素」文案收窄
          // 为两行提示块；「移左栏/toast」取左栏常驻形态——toast 会因选中/取消反复弹打搅）。
          // M3.6：右栏折叠提示块拆除（rightFolded 恒 false，右栏恒在）
          // lfoot（引擎状态；batch-6，audit-left-11+topbar-10 对齐 i:145-148 .lfoot：border-top bd+
          // bg rgba(0,0,0,.02)（深色换算）/padding 8×12/10.5 monospace tx3/eng 名 600/dot 7×7。
          // 耗时文案「本地执行」（batch-5，gap-detail-15）：明示非引擎耗时——严禁绑
          // AppStore.lastMs（6-13ms 随机模拟值），真实引擎耗时归 gap-global-3 换 engApply 实测。
          // dot 失败变红分支预留（i:148 .dot.bad #e0483e——lastErr 语义接好后启用，注释即登记）
          Row({ space: 6 }) {
            Row({ space: 6 }) {
              Circle({ width: 7, height: 7 }).fill(this.T().ok)
              Text('deepDesign Engine').fontSize(this.fp(F_LSTATUS)).fontWeight(600).fontColor(this.T().tx3).maxLines(1)   // r10 sz-lstatus-1：断点（10.5↔9.5）
            }.alignItems(VerticalAlign.Center)
            Blank()
            Text('本地执行').fontSize(this.fp(F_LSTATUS)).fontFamily('monospace').fontColor(this.T().tx3)   // r10 sz-lstatus-1：断点（10.5↔9.5）
          }.width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.isDark() ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)')
          .border({ width: { top: 1 }, color: this.T().bd })
          .alignItems(VerticalAlign.Center)
        }.width(this.leftW).height('100%').backgroundColor(this.T().panelS)   // batch-7 cur-1：252→等比折算
        .border({ width: { right: 1 }, color: this.T().bd }).alignItems(HorizontalAlign.Start)

        // ---- 中央画布（Stack：画布/源码视图 + 尾栏 overlay + dock；iss-2 后 ctools/czoom
        //      入 Scroll 内容首行，随内容滚动——sticky 钉住语义登记后议）----
        Stack({ alignContent: Alignment.TopEnd }) {
          if (this.modeIdx !== 2) {
          Scroll() {
            Column() {
              // iss-2（方案 A）：工具行入流首行——原 ctools .position({x:12,y:44})/czoom
              // .margin({top:44,right:12}) 绝对悬浮于尾栏 overlay 之下（y=44=尾栏 32+12），还原态
              // dump 实证与板 chrome 相交 ~48px（r7-audit-settings-tpl.txt:71-72）。入流后 wrapper
              // padding-top 36 让位尾栏（32+4 间距），ctools 居左/czoom 居右（原 x:12/right:12 内缩
              // 移入 wrapper 左右 padding）；壳样式不动，仅显式 .height(CANVAS_TOOLBAR_H)。
              // 登记偏离：桌面 ctools 为 sticky 悬浮（i:197 top:12）随滚动钉住、鸿蒙入流后随内容
              // 滚走——sticky 钉住语义登记后议（尾栏 overlay 为 r6 batch-2 既有取舍，同源登记）。
              // batch-7 cur-1 判负消除（两态，照抄顶栏窄窗 Scroll 先例 :4996-5010）：r8 实证还原
              // 态画布 368vp 放不下整行（自然宽 ~548），SpaceBetween 把 czoom 撑压到 11.6vp 碎片、
              // ⤢ 适配只剩 3.2vp（r8-layout-boot.json 实测 bounds）——cw<CANVAS_MIN_W 时整行转
              // 横向 Scroll 兜底（内容完整布局、可滚可达，「3.2vp 碎片/整段不可见」结构性消除）；
              // 宽画布保持 SpaceBetween 原形态。Scroll 分支内层 Row 无 minWidth——r5 实证横向
              // Scroll 主轴约束无穷、百分比无解析基准退化为内容宽（此处正要内容宽，窄窗不追求
              // 居中、只保不裁，与顶栏窄窗同口径登记）。
              if (this.toolRowScroll()) {
                Scroll() {
                  Row() {
                    this.ctoolsBar()
                    this.czoomBar()
                  }
                  .padding({ top: CANVAS_TOOLBAR_TOP, left: 12, right: 12 })
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .width('100%')
              } else {
                Row() {
                  this.ctoolsBar()
                  this.czoomBar()
                }.width('100%').justifyContent(FlexAlign.SpaceBetween)
                .padding({ top: CANVAS_TOOLBAR_TOP, left: 12, right: 12 })
              }

              if (this.boards.length > 0) {
                // 内容 Stack：板横排 + 连线层（TopStart 同原点，端点随 zoom/boardOffsets 跟随）
                Stack({ alignContent: Alignment.TopStart }) {
                  Row({ space: 96 }) {
                    ForEach(this.boards, (b: Board) => {
                      // 直挂（r4 根治）：boardContent 在 Index 自身构建树内执行（原 BoardFrame
                      // @BuilderParam 闭包 = 外来组件构建上下文，嵌套 builder 节点静默丢失——
                      // 见文件头 BoardFrame 摘除说明）。键 = id|docEpoch|rev：docEpoch 管文档级
                      // 替换（restore/undo/redo/新建），rev 管单板 op 刷新——每个变更 op 后该板
                      // 键跳变 → 板卡全量重建，与原「rev 经 @ObjectLink 通知 → content 重画」
                      // 逐 op 等价；拖拽/画板平移等纯视图态不触键（translate/属性级细粒度
                      // 更新承担），手势链中途无重建。
                      // r5 追加 zoom 入键（render 判据）：还原态首建后实测属性级细粒度更新不
                      // 回填 .scale（元素挂载但不可见不可点、resize 重建后行为翻转的实证根因
                      // 归入此类）——生效缩放变更（窗尺寸/±/FIT/选中主次系数）即强制板卡重建
                      // 换新属性。缩放只经按钮/键盘变更，拖拽手势期间不可能变化，无重建撕手势
                      // 风险；选中态切换引发的他板 0.82 系数重建为点击频度，可接受。
                      this.boardContent(b)
                    }, (b: Board) => `${b.id}|${appStore.docEpoch}|${b.rev}|${Math.round(this.zoomOf(b) * 100)}`)
                    // ghost 占位卡（gap-canvas-7）：一键建 390×844 空板；尺寸 150×220 对齐
                    // i:228（batch-6，gap-detail-5），border 2 dashed ≈T().dim
                    Column({ space: 6 }) {
                      Text('+').fontSize(28).fontColor(this.T().tx3)
                      Text('新建画板').fontSize(this.fp(F_GHOST)).fontWeight(600).fontColor(this.T().tx2)   // r10 sz-welcome-1：题断点（11.5↔10.5）
                      Text('390 × 844 · 空白').fontSize(this.fp(F_GHOST_DIM)).fontColor(this.T().tx3)   // r10 sz-welcome-1：尺寸行断点（9↔8）
                    }
                    .width(150).height(220).justifyContent(FlexAlign.Center)
                    .backgroundColor(this.T().card).borderRadius(this.T().rTplCard)   // batch-3：ghost 新建卡 12→HMOS 24（§4 card；与模板卡合并同字段）
                    .border({ width: 2, color: this.T().dim, style: BorderStyle.Dashed })
                    .onClick(() => {
                      const nb = appStore.addBlankBoard();
                      this.sync();
                      this.selBoard = nb.id;
                      this.selLayer = '';
                    })
                  }.padding({ top: CANVAS_BOARDS_PAD_TOP, bottom: 130, left: 64, right: 64 })
                  .alignItems(VerticalAlign.Top)   // 板横排顶对齐（batch-2，audit-canvas-2：Row 默认
                                                   // 垂直居中使多板顶缘错线、且偏离 boardOrigin 的
                                                   // y 假设——顶对齐后连线端点与板缘重新吻合；
                                                   // iss-2 后 padding-top=常量 8，boardOrigin 同源推导）

                  // 连线层（gap-canvas-6）：贝塞尔 + 常显药丸，纯展示不拦截点击
                  ForEach(this.flows, (f: Flow) => {
                    this.flowLine(f)
                  }, (f: Flow) => f.id)

                  // 双击内联改字浮层（gap-canvas-3）：定位到节点上方，随内容滚动。
                  // batch-2（audit-canvas-10 对齐 i:383-384）：外包白底面板（radius 9、pop 阴影
                  // +0 0 0 1px rgba(0,122,255,.35) 发丝圈以 1px border 等价、padding 4），输入框
                  // 去边框改 monospace 12；面板 top=节点顶−6（i:2366 y-6 口径，原 −38 为自造）
                  // controller 走 TextInputOptions 构造参数（text_input.d.ts:769；属性版不存在，同 TextArea 教训）
                  if (this.showInline) {
                    Column() {
                      TextInput({ text: this.inlineVal, controller: this.inlineCtrl })
                        .defaultFocus(true)   // 打开即聚焦（gap-canvas-18，对齐行内 Agent 输入）
                        .onChange((v: string) => { this.inlineVal = v; })
                        .onSubmit(() => { this.commitInline(); })
                        .onFocus(() => {
                          this.onInputFocus();
                          if (this.inlineSelArmed) {   // 聚焦后全选原文；armed 用后即清防打字重选
                            this.inlineSelArmed = false;
                            this.inlineCtrl.setTextSelection(0, this.inlineVal.length);
                          }
                        })
                        .onBlur(() => { this.onInputBlur(); })
                        .onKeyEvent((e: KeyEvent): void => {
                          if (e.type === KeyType.Down && e.keyCode === KeyCode.KEYCODE_ESCAPE) {
                            this.cancelInline();   // Esc 取消
                          }
                        })
                        .fontSize(12).height(30).width(220)
                        .fontFamily('monospace')   // i:384 ui-monospace 12（audit-canvas-6）
                        .backgroundColor(Color.Transparent)
                        .border({ width: 0 })
                        .padding({ left: 8, right: 8, top: 0, bottom: 0 })
                    }
                    .padding(4)   // i:383
                    .borderRadius(9)
                    .backgroundColor(this.T().card)   // i:383 background var(--panel)
                    .border({ width: 1, color: 'rgba(0,122,255,0.35)' })   // 发丝圈（i:383 spread ring 等价）
                    .shadow(this.T().shPop)   // batch-3：{16,0,0,shadowLg}→shPop md 档 60/(0,10)（§6）
                    .position({ x: this.inlineX, y: Math.max(8, this.inlineY - 6) })
                  }

                  // 行内 Agent 浮层（gap-right-5）：点选节点即弹，上下文行 + 快捷 chips + 指令
                  // M3.6.9 视觉优化（对齐桌面 #agent-pop i:258-271）：宽 250→320、
                  // 紫渐变星芒方块（22/7/白✦）、标题+mono 上下文行、聚焦紫态、
                  // 紫描边环（border rgba(157,78,221,.25) 等价桌面 0 0 0 1px ring）
                  if (this.inlineAgent) {
                    Column({ space: 7 }) {
                      Row({ space: 7 }) {
                        Column() {
                          Text('✦').fontSize(12).fontColor(Color.White)
                        }
                        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
                        .width(22).height(22).borderRadius(7)
                        .linearGradient({ angle: 135, colors: [['#9d4edd', 0.0], ['#6d28d9', 1.0]] })   // i:261 .spark 渐变
                        Column({ space: 1 }) {
                          Text('行内 Agent').fontSize(this.fp(F_IA_HEAD)).fontWeight(700).fontColor(this.T().tx)   // r10 sz-ia-1：题断点（10↔9）
                          Text(this.iaContext()).fontSize(this.fp(F_IA_MINI)).fontColor(this.T().tx3)   // r10 sz-ia-1：上下文行（9↔8）
                            .fontFamily('monospace').maxLines(1).width('100%')
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                        Text('✕').fontSize(this.fp(F_IA_MINI) + 2).fontColor(this.T().tx3)   // i:264 .x 14px→断点+2
                          .padding({ left: 4, right: 4, top: 1, bottom: 1 }).borderRadius(6)
                          .onClick(() => { this.inlineAgent = false; })
                      }.width('100%')
                      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                        ForEach(['改文案', '换色', '删除', '放大'], (c: string) => {
                          Text(c).fontSize(this.fp(F_IA_CHIP)).fontColor(this.T().tx2)   // r10 sz-ia-1：chip 断点（9.5↔9）
                            .padding({ left: 9, right: 9, top: 3, bottom: 3 }).borderRadius(this.T().rChipPill)   // batch-3：行内 chips 胶囊 99→HMOS 14（§4 piece）
                            .backgroundColor(this.T().subtle)
                            .border({ width: 1, color: Color.Transparent })   // i:270 .ap-chip border transparent
                            .margin({ right: 4, bottom: 2 })
                            .stateStyles({
                              pressed: { .scale({ x: HMOS_PRESS_SCALE, y: HMOS_PRESS_SCALE }) },   // batch-4 iss-5：A 缩放式（chips）
                              normal: { .scale({ x: 1, y: 1 }) }
                            })
                            .onClick(() => {
                              this.inlineAction(c === '改文案' ? 'copy' :
                                c === '换色' ? 'color' : c === '删除' ? 'delete' : 'grow');
                            })
                        }, (c: string) => c)
                      }.width('100%')
                      Row({ space: 6 }) {
                        TextInput({ placeholder: '对这个节点下指令…', text: this.iaInput })
                          .onChange((v: string) => { this.iaInput = v; })
                          .onSubmit(() => { this.sendInlineAgent(); })
                          .onFocus(() => { this.onInputFocus(); this.iaFocused = true; })
                          .onBlur(() => { this.onInputBlur(); this.iaFocused = false; })
                          .fontSize(this.fp(F_IA)).placeholderFont({ size: this.fp(F_IA) }).height(this.sp(H_IA)).layoutWeight(1).borderRadius(7)   // r10 sz-ia-1 + h-ia-1：输入断点（11↔10 + 高 28 两态同值——用户点名内框偏小）
                          .backgroundColor(this.iaFocused ? this.T().card : this.T().subtle)   // i:267 bg rgba(0,0,0,.02)→subtle；focus #fff
                          .border({ width: 1.5, color: this.iaFocused ? '#9d4edd' : this.T().line })   // i:267/.ap-input:focus 紫态
                          .padding({ left: 9, right: 9, top: 0, bottom: 0 })
                          .defaultFocus(true)
                        Text('↗').fontSize(this.fp(F_IA)).fontColor(this.T().onAcc)   // r10 sz-ia-1：↗ 断点（11↔10）
                          .width(28).height(this.sp(H_IA)).textAlign(TextAlign.Center).borderRadius(7)   // r10 h-ia-1：发送钮断点高（随输入 28 两态同值；宽 28 保持命中区）
                          .backgroundColor(this.T().purple)
                          .onClick(() => { this.sendInlineAgent(); })
                      }.width('100%')
                    }.width(320).padding(10).borderRadius(12)
                    .backgroundColor(this.T().card)
                    .border({ width: 1, color: 'rgba(157,78,221,0.25)' })   // i:258 紫描边环（桌面 0 0 0 1px ring 等价）
                    .shadow(this.T().shPop)   // batch-3：行内 Agent 浮层阴影→shPop md 档（§6；同上合并）
                    // batch-5 iss-7 入场（popIn 族近似：淡入+0.97 缩放，物理弹性同 veil）
                    .transition(TransitionEffect.OPACITY
                      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
                      .animation({ curve: curves.springMotion(0.55, 0.825) }))
                    // M3.6.9 同步缩放：浮层随画布宽等比（maximized 1640→1.0，窄窗→0.72 下限），
                    // 渲染级 transform——文字矢量缩放不糊；位置钳制按未缩放 320 保守即可
                    .position({ x: this.iaX, y: this.iaY })
                  }
                }
              } else {
                // 欢迎页 veil 卡片容器（batch-6，gap-detail-5 对齐 i:406-411）：半透明卡底+
                // blur+吉祥物徽标（batch-6 iss-8 前为旋转方块 logo）；画布点阵背景（i:194-195
                // radial-gradient 22px 网格）工程成本高——登记省略（低优）
                Column() {
                  Column() {
                    // batch-6 iss-8 品牌统一：dD 菱形蓝方块（Text+双向 45° 旋转）整体弃用 →
                    // 海豹吉祥物 Image（与顶栏 :3599 同源 app.media.app_logo），消除同屏双形象
                    // （r4 audit-topbar-11 待裁决项就此定案为统一吉祥物——登记偏离：品牌形象
                    // dD 蓝方块 → 海豹吉祥物）。圆角走 batch-3 rIcon token（HMOS 8，§4 icon；
                    // 既有主题随 token 取桌面档 5，旧造型现值 8 随品牌替换一并让位）；阴影沿用
                    // 卡片影 shCard（HMOS 档=无阴影 radius 0+透明，语义登记）。
                    Image($r('app.media.app_logo'))
                      .width(40).height(40).borderRadius(this.T().rIcon)
                      .shadow(this.T().shCard)
                      .margin({ bottom: 18 })
                    Text('从 deepDesign 开始').fontSize(21).fontWeight(700).fontColor(this.T().tx)
                    // ⌘K 套 kbd 等价样式（batch-3，audit-modal-11：灰底/radius 5/monospace 10.5）
                    Row({ space: 4 }) {
                      Text('选择模板即刻开始，或按')
                        .fontSize(this.fp(F_WELCOME_SUB)).fontColor(this.T().tx2)   // r10 sz-welcome-2：副题断点（12.5↔11.5）
                      Text('Ctrl+K')
                        .fontSize(this.fp(F_WELCOME_KBD)).fontFamily('monospace').fontColor(this.T().tx2)   // r10 sz-welcome-2：键帽断点（10.5↔9.5）
                        .backgroundColor(this.T().subtle).borderRadius(5)
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      Text('直接对 Agent 下命令')
                        .fontSize(this.fp(F_WELCOME_SUB)).fontColor(this.T().tx2)   // r10 sz-welcome-2：副题断点（12.5↔11.5）
                    }.margin({ top: 8 })
                  // 精选模板换 Flex wrap（batch-3，audit-modal-5：窄窗口 Row 不再横向溢出）
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
                    ForEach(TPLS.filter((t: TplDef): boolean => TPL_FEATURED.includes(t.tid)), (t: TplDef) => {
                      this.tplCard(t, false)
                    }, (t: TplDef) => t.tid)
                  }.margin({ top: 30 })
                  if (this.showAllTpl) {
                    Column() {
                      ForEach(TPL_GROUPS, (g: string[]) => {
                        Column() {
                          Text(`${g[1]} · ${TPLS.filter((t: TplDef): boolean => t.kind === g[0]).length}`)
                            .fontSize(this.fp(F_WELCOME_SEC)).fontWeight(600).fontColor(this.T().tx3)   // r10 sz-welcome-2：分组题断点（10.5↔9.5，F_WELCOME_SEC 复审拆分档）
                            .margin({ top: 14, bottom: 8 }).width('100%')
                          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                            ForEach(TPLS.filter((t: TplDef): boolean => t.kind === g[0]), (t: TplDef) => {
                              this.tplCard(t, true)
                            }, (t: TplDef) => t.tid)
                          }.width('100%')
                        }.width(560)
                      }, (g: string[]) => g[0])
                    }.margin({ top: 20 })
                  }
                  // batch-8（cur-6/spec-welcome-2）：展开区形态定案=桌面同构（frontend/index.html:
                  // 4409-4422 sed 实读：TPL_GROUPS 三组全量平铺、组头 `label · N` 动态计数、
                  // 无组内折叠/限高滚动——cur-6 hint 的「组内再收/限高」不取，以 spec-welcome-2
                  // 为准）。双端怪癖登记（本轮 sed 实证同病，对齐优先不修）：第三组 g='pc' 过滤
                  // t.kind==='pc' 漏 kind='adaptive' 的 adaptive_landing/login_v2——按钮计数
                  // TPLS.length=14 而展开网格只呈现 12（手机·8/Web·3/桌面·1），桌面同款
                  // （frontend/index.html:4410-4422 filter dev===g 同漏）；login_v2 两端均无法从
                  // 欢迎网格触达（仅 Agent 词表可达）。桌面侧修复项 + ohos 超集修正待裁决，
                  // acceptance 按现状过滤行为断言。
                  Text(this.showAllTpl ? '收起 ▴' : `浏览全部模板（${TPLS.length}）▾`)   // batch-8 spec-welcome-2：计数不写死（14=TPLS.length，AppStore TPLS 14 项）
                    .fontSize(this.fp(F_WELCOME_NAME)).fontWeight(500)   // r10 sz-welcome-2：断点（12↔11，F_WELCOME_NAME）
                    .fontColor(this.showAllTpl ? this.T().accTx : this.T().tx3)   // 展开态才亮（batch-3，audit-modal-11）
                    .margin({ top: 18 })
                    .onClick(() => { this.showAllTpl = !this.showAllTpl; })
                  // 最近项目区（gap-topbar-2：与项目名下拉同一数据源，渲染前 6 条）
                  if (this.recent.length > 0) {
                    Column({ space: 7 }) {
                      Text('最近项目').fontSize(this.fp(F_WELCOME)).fontWeight(600).fontColor(this.T().tx3)   // r10 sz-welcome-2：题断点（11↔10）
                        .width('100%').textAlign(TextAlign.Start).padding({ left: 4 })
                      ForEach(this.recent.slice(0, 6), (it: RecentItem) => {
                        Row({ space: 8 }) {
                          Text(it.path === appStore.filePath ? '✓' : '·')
                            .fontSize(this.fp(F_WELCOME)).fontColor(this.T().accTx).width(14).textAlign(TextAlign.Center)   // r10 sz-welcome-2：✓列断点（11↔10）
                          Text(it.name).fontSize(this.fp(F_WELCOME_NAME)).fontColor(this.T().tx).maxLines(1)   // r10 sz-welcome-2：名断点（12↔11）
                            .constraintSize({ maxWidth: 140 })
                          Text(this.relTime(it.ts)).fontSize(this.fp(F_WELCOME_TIME)).fontColor(this.T().tx3).layoutWeight(1)   // r10 sz-welcome-2：时间断点（9↔8）
                            // path → 相对时间（batch-3，audit-modal-11：完整路径泄露+无信息量）
                            .textAlign(TextAlign.End)
                        }.width(420).height(this.sp(H_WELCOME_ROW)).padding({ left: 12, right: 12 }).borderRadius(8)   // r10 h-welcome-1：最近行断点高（30↔27）
                        .backgroundColor(this.T().card).border({ width: 1, color: this.T().bd })
                        .stateStyles({
                          pressed: { .backgroundColor(this.T().pressFill) },   // batch-4 iss-5：B 底色叠加（卡面=subtle 提一档）
                          normal: { .backgroundColor(this.T().card) }
                        })
                        .onClick(() => { this.hotSwitch(it.path); })
                      }, (it: RecentItem) => it.path + String(it.ts))
                    }.width('100%').margin({ top: 26 })
                  }
                  }.width('92%').constraintSize({ maxWidth: 680 })   // 自适应（batch-3，audit-modal-5：
                                                                     // 固定 680 在还原态窗口被左右栏裁剪）
                  .padding({ top: 34, bottom: 120, left: 30, right: 30 })
                  // batch-7 cur-11（必做项）bottom 160→120 重算推导——锚点与几何模型：
                  // ① 锚点（r8 登记）：padB=120 时 dock 全带（boot dump 实测壳高 124.7vp，含
                  //    提示行 11.6+gap 7）下最近项目行底部被遮 ~28vp → 全带 padB_min=148；
                  // ② 本批 dock 紧凑化：提示行改 link/澄清条件显示（welcome 首屏不在场），
                  //    带高回收 ~18.6 → 紧凑带 ≈106；
                  // ③ 居中态几何（veil 卡高 ≤ wrapper minHeight 时卡在 wrapper 内垂直居中）：
                  //    内容底 y=(ch+C+104−padB)/2，须 ≤ dock 顶 ch−12−带高 → padB ≥ C−ch+128+
                  //    2×带高 → 带高每收 1vp，padB_min 降 2vp：padB_min′=148−2×18.6≈110.8，
                  //    取 120（+9vp 漂移余量，r4 §4.1 坐标逐构建漂移教训）。
                  // ④ 边界登记：还原窗 980×603（画布 ch≈530）下 veil 内容（~427vp+padTop 34）
                  //    超 wrapper minHeight（ch−70=460）——卡顶锚定 y=70（justifyContent Center
                  //    仅在卡矮于 wrapper 时生效），「浏览全部模板」按钮 y=padB 无关（顶部
                  //    锚定流式布局），清 dock 带由紧凑化本身达成（推算按钮底 ≈530 视口底 vs
                  //    dock 底 ≈518，余量 ~2vp 偏薄，ddVeil/ddDock 日志+模拟器验收复测；若仍
                  //    相交，升级杠杆=精选模板行数压缩（cur-6 范围，非本批）。带内 recents
                  //    展开时（高窗居中态）按 ③ 式 120 覆盖。
                  // 历史：iss-1 bottom 30→120 给 dock 卡带让位；batch-6 验收修正 120→160。
                  .borderRadius(this.T().rVeil)   // batch-3：veil 圆角 22→HMOS 24（baseline §4 card）；i:406-411
                  .backgroundColor(this.T().panelS)   // 半透明卡底
                  .backdropBlur(14)
                  .border({ width: 1, color: this.T().line })
                  .shadow(this.T().shDialog)   // batch-3：veil+五弹层 lg 档 100/(0,20)（§6；桌面 {24,0,0,shadowLg} 现值同合并）
                  // batch-7 cur-11 校准埋点：卡实测高（>ch−70 即顶锚定态，padB 不影响按钮位，
                  // 见上方推导 ④）+ ch，供模拟器 dump 对账「浏览全部模板 vs dock 带」判据
                  .onAreaChange((o: Area, n: Area): void => {
                    hilog.info(0x0000, 'ddVeil', 'w=%{public}s h=%{public}s ch=%{public}s',
                      Number(n.width).toString(), Number(n.height).toString(), this.ch.toString());
                  })
                }
                // iss-1：height('100%') 改数值化最小高度（Math.max(240, ch−70)——70=工具块
                // CANVAS_TOOLBLOCK_H 常量与 boardOrigin 推导同源），规避「百分比 minHeight 在
                // 插入工具行后的 Scroll 内容 Column 内能否解析为视口高」的未验证问题；
                // 构建门修正：ColumnAttribute 无 .minHeight 属性（SDK 实测报错），走通用
                // constraintSize({minHeight})（同 veil 内层 maxWidth 先例）——height 不设即
                // auto ≥ 下限，语义不变。justifyContent 居中保留，内容超高时容器随内容增高、
                // 外层 Scroll 纵向可滚。
                // 登记：veil 视觉中心随工具行入流下移 ~半行高（桌面 empty-stage 为 absolute
                // inset:0 居中 + ctools sticky 悬浮其上 i:406/:197；桌面欢迎页同样呈现工具行，取向同构）。
                .width('100%').constraintSize({ minHeight: Math.max(240, this.ch - CANVAS_TOOLBLOCK_H) })
                .justifyContent(FlexAlign.Center)
                // batch-5 iss-7 入场（登记偏离：桌面 fadeUp .4s ease → springMotion(0.55,0.825)
                // 物理弹性默认参数，duration 不生效由曲线决定，baseline §8.1/§8.3）
                .transition(TransitionEffect.OPACITY
                  .combine(TransitionEffect.translate({ y: 10 }))
                  .animation({ curve: curves.springMotion(0.55, 0.825) }))
              }
            }.width('100%')
          }.width('100%').height('100%').scrollBar(BarState.Auto)
          .scrollBarWidth(6).scrollBarColor(this.scrollThumb())   // i:24-25（batch-1，audit-left-12）
          .align(Alignment.TopStart)   // 内容顶对齐（batch-2，audit-canvas-2：桌面画布内容顶到
                                       // 容器上缘，boardOrigin y 口径依赖此锚；iss-2 后 y=工具块
                                       // 36+34 + 板排 8 + chrome 30，几何常量单一推导源）

          // canvas-tail 信息条（batch-2，audit-canvas-3 对齐 i:192-193：三段合一行拆开——
          // 板名 <b> 600/tx、尺寸 tx2、rev 右置；11px ui-monospace；--tail-bg 底 + 底部 1px bd；
          // 纯信息不拦点击。滚动遮挡：本行是 Stack 内 Scroll 之后的兄弟节点，天然盖在滚动
          // 内容之上（None 仅放行命中，不降层级））
          Row({ space: 8 }) {
            Text(this.curBoard()?.name ?? '—')
              .fontSize(this.fp(F_TAIL)).fontWeight(600).fontColor(this.T().tx).maxLines(1)   // r10 sz-tail-1：板名断点（11↔10）
              .fontFamily('monospace')
              .hitTestBehavior(HitTestMode.None)   // None 包裹层内子组件仍参与命中（Default 阻塞兄弟），须显式穿透
            Text(`${this.curBoard()?.width ?? 0} × ${this.curBoard()?.height ?? 0}`)
              .fontSize(this.fp(F_TAIL)).fontColor(this.T().tx2).maxLines(1)   // r10 sz-tail-1：尺寸断点（11↔10）
              .fontFamily('monospace')
              .hitTestBehavior(HitTestMode.None)
            Blank()
            Text(`rev ${this.tailRev}`)   // batch-4，iss-7：镜像 @State（sync 随 op 刷新），直调
                                          // appStore.totalRev() 非响应式依赖永不重绘（根因登记）
              .fontSize(this.fp(F_TAIL)).fontColor(this.T().tx2).maxLines(1)   // r10 sz-tail-1：rev 断点（11↔10）
              .fontFamily('monospace')
              .hitTestBehavior(HitTestMode.None)
          }.width('100%').height(this.sp(H_TAIL))   // r10 h-tail-1：尾栏断点高（32↔28）
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.T().tailBg)
          .border({ width: { bottom: 1 }, color: this.T().bd })
          .hitTestBehavior(HitTestMode.None)
          // iss-2 登记偏离：桌面尾栏为 flex-shrink:0 文档流兄弟（frontend/index.html:192-194 实读），
          // 鸿蒙侧尾栏保持 Stack overlay（r6 batch-2 既有登记取舍），画布内容以 padding-top 让位
          // （工具行 wrapper 36 + 板排 8），滚动内容 y0-32 被本行覆盖属既定形态。
          }

          // MBT 源码视图（gap-topbar-3 decl 态：interim serialize + 复制/校验）
          if (this.modeIdx === 2) {
            this.declView()
          }

          // canvas-dock（底部居中悬浮：澄清面板 + pchips + pmain）
          // batch-4（audit-topbar-4）：外包 promptbar 卡片壳——对齐 i:242 .promptbar：
          // radius 16 / bg rgba(255,255,255,.92)+backdropBlur(20) / 边 rgba(0,0,0,.08) /
          // pop 阴影 / padding 9 / gap 7 / maxWidth 680；深色档按桌面深色精修 i:757 换算
          // （bg rgba(26,27,32,.97) / 边 rgba(255,255,255,.12)）。还原态「一键生成」被右栏
          // 裁切随壳约束一并收口。gap-bottom-2：底部锚定，外壳不挡命中
          Column() {
            Column({ space: 7 }) {
            // 澄清面板（gap-bottom-1）：提问全文多行 + 回答续跑
            if (this.pending !== null) {
              Column({ space: 8 }) {
                Row({ space: 5 }) {
                  Text('🤔').fontSize(this.fp(F_CLARIFY_GLYPH))   // r10 sz-dock-1：🤔 断点（12↔11）
                  Text('Agent 需要澄清').fontSize(this.fp(F_CLARIFY_HEAD)).fontWeight(700).fontColor(this.T().purple)   // batch-5：澄清面板头（§3.3，11↔10）
                  Blank()
                  Text('✕').fontSize(this.fp(F_CLARIFY_X)).fontColor(this.T().tx3)   // r10 sz-dock-1：✕ 断点（10↔9）
                    .onClick(() => { this.pending = null; })
                }.width('100%')
                Text(this.pending.question).fontSize(this.fp(F_CLARIFY_HEAD)).fontColor(this.T().tx)   // batch-5：提问全文（§3.3，11↔10）
                  .width('100%').maxLines(8)
                Row({ space: 8 }) {
                  TextInput({ placeholder: '回答 Agent 的问题…', text: this.clarifyAnswer })
                    .onChange((v: string) => { this.clarifyAnswer = v; })
                    .onSubmit(() => { this.sendClarify(); })
                    .onFocus(() => { this.onInputFocus(); })
                    .onBlur(() => { this.onInputBlur(); })
                    .fontSize(this.fp(F_CLARIFY_INPUT)).placeholderFont({ size: this.fp(F_CLARIFY_INPUT) }).height(this.sp(H_CLARIFY)).layoutWeight(1).borderRadius(this.T().rBtnDialog)   // batch-3 圆角；batch-5：字号/高断点（§3.3，12↔11 + 32↔28）
                    .backgroundColor(this.T().card)
                    .border({ width: 1, color: this.T().purpleBorder })
                    .padding({ left: 9, right: 9, top: 0, bottom: 0 })
                  Row({ space: 4 }) {
                    Text('↗').fontSize(this.fp(F_CLARIFY_HEAD)).fontColor(this.T().onAcc)   // r10 sz-dock-1：↗ 断点（11↔10，复用 F_CLARIFY_HEAD）
                    Text('发送').fontSize(this.fp(F_CLARIFY_INPUT)).fontWeight(600).fontColor(this.T().onAcc)   // batch-5：发送钮字号（§3.3，12↔11）
                  }.height(this.sp(H_CLARIFY)).padding({ left: 13, right: 13 }).borderRadius(this.T().rBtnDialog)   // batch-3 圆角；batch-5：高断点（§3.3，32↔28）
                  .backgroundColor(this.T().purple)
                  .onClick(() => { this.sendClarify(); })
                }.width('100%')
              }.width('100%').padding(11).borderRadius(12)
              .backgroundColor(this.T().card)
              .border({ width: 1, color: this.T().purpleBorder })
              .shadow({ radius: 12, color: this.T().shadowMd })
              .constraintSize({ maxWidth: 640 })
            }
            // canvas-hint 提示行（batch-4，gap-detail-14 对齐 i:942/2141）：batch-7 cur-3/cur-11
            // dock 紧凑化——常驻改条件显示（仅 link 模式/澄清挂起时在场，回收 ~19vp 带高）。
            // 登记偏离：桌面 hint 常驻（i:942），鸿蒙窄窗 dock 常驻带挤压 veil/板面（r8 §1
            // 实测与 veil 首屏叠 ~110vp）——默认引导语义由 pchips/pmain placeholder 承担，
            // link 模式引导仍常驻本行（连接选源后切「源节点 xx 已选择 · …」，与 2.4s toast
            // 双通道并存不变；i:2141 xx=节点 id）。同时去 width('100%')（cur-3 居中修复：
            // constraintSize 内容宽壳 + 内层 width('100%') 链即 r8 实测 alignItems(Center)
            // 偏左 ~22vp 的失效组合，壳内改内容自适应，见壳注释）。
            if (this.toolMode === 'link' || this.pending !== null) {
              Text(this.toolMode === 'link' && this.pendingFromNode !== '' ?
                `源节点 ${this.pendingFromNode} 已选择 · 点击目标画板的标题栏完成连接` :
                '选择元素后可用悬浮 Agent 修改 · 连接工具建立交互流')
                .fontSize(this.fp(F_DOCK_HINT)).fontColor(this.T().tx3)   // batch-5：canvas-hint（§3.3，10↔9）
                .maxLines(1).textAlign(TextAlign.Center)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            // pchips（batch-4，audit-topbar-3 对齐 i:243-245）：横向 Scroll（溢出可滚不换行）、
            // 行首「快捷」label（10.5/700/tx3/.06em）、容器 gap 5、chip 边 rgba(0,0,0,.07)、
            // 单行 30 高 maxLines(1)
            Scroll() {
              Row({ space: 5 }) {
                Text('快捷')
                  .fontSize(this.fp(F_DOCK_QUICK)).fontWeight(700).fontColor(this.T().tx3)   // batch-5：pchips 行首 label（§3.3，10.5↔9.5）
                  .letterSpacing(0.6)
                ForEach(this.pchips, (c: string) => {
                  Text(c).fontSize(this.fp(F_DOCK_CHIP)).fontWeight(500).fontColor(this.T().chipTx)   // iss-4 字色 token；batch-5：pchip 字号断点（§3.3 fDockChip，12↔11）
                    .maxLines(1)
                    .height(this.sp(HMOS_H_CHIP)).padding({ left: this.sp(PAD_CHIP), right: this.sp(PAD_CHIP) }).borderRadius(this.T().rChipPill)   // batch-3 圆角；batch-5：高/padding 断点（§3.3 要点 3 chip h30→27，30/13↔27/11）
                    .backgroundColor(this.T().subtle)
                    .border({ width: 1, color: this.T().chipLine })   // iss-4：pchip 边框 token 化（原硬编码 rgba(0,0,0,0.07)）
                    .stateStyles({
                      pressed: { .scale({ x: HMOS_PRESS_SCALE, y: HMOS_PRESS_SCALE }) },   // batch-4 iss-5：A 缩放式（桌面 .pchip:active scale(.96) i:247）
                      normal: { .scale({ x: 1, y: 1 }) }
                    })
                    .onClick(() => {
                      if (c.includes('Web 登录')) this.usePrompt('生成 Web 登录页');
                      else if (c.includes('手机')) this.usePrompt('生成手机登录页');
                      else if (c.includes('仪表盘')) this.usePrompt('生成仪表盘页面');
                      else if (c.includes('微信')) this.usePrompt('做一个微信风格的社交应用原型：聊天列表、会话页、发现页、我的页面，相互可跳转');
                      else this.usePrompt('一键修复');
                    })
                }, (c: string) => c)
              }
            }.scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
            // M3.6：恢复 width('100%')——pchips 内容自适应宽与 pmain width('100%') 组合下
            // 两卡宽度不一致（最大化态指令条 680 > chips 内容宽 ~520，用户红框点名）。统一
            // 100% 后两卡恒同宽；r8 时代的居中偏移已由壳宽 cw 自适应（下）另路收口。
            if (this.agentMsg !== '') {
              Text(this.agentMsg).fontSize(this.fp(F_AGENTMSG)).fontColor(this.T().purple)   // batch-5：agentMsg（§3.3，11↔10）
                .maxLines(this.msgExpanded ? 12 : 1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).padding({ left: 8, right: 8, top: 0, bottom: 0 })
                .width('100%')
                .onClick(() => { this.msgExpanded = !this.msgExpanded; })   // 点击展开多行（gap-bottom-1）
            }
            // pmain（输入条；batch-4，audit-topbar-7 对齐 i:250 .pmain:focus-within：聚焦蓝边
            // accTx + 3px rgba(0,122,255,.12) 光环——双层容器模拟光环；audit-topbar-4：输入框
            // 去 minWidth 280 改纯 layoutWeight(1)，容器 maxWidth 640→680 随壳）
            Column() {
              Row({ space: 8 }) {
                Text('✦').fontSize(this.fp(F_DOCK_ICON)).fontColor(this.T().purple)   // batch-5：dock 图标字形（§3.3，14↔13）
                TextInput({ placeholder: DOCK_PH, text: this.prompt })
                  .onChange((v: string) => { this.prompt = v; })
                  .onSubmit(() => this.runPrompt())
                  .onFocus(() => {
                    this.onInputFocus();
                    this.promptFocused = true;
                  })
                  .onBlur(() => {
                    this.onInputBlur();
                    this.promptFocused = false;
                  })
                  .fontSize(this.fp(F_DOCK_INPUT)).placeholderFont({ size: this.dockPhFont() }).height(this.sp(H_DOCK_INPUT)).layoutWeight(1)   // batch-5：pmain 输入断点（§3.3 fDockInput 13↔12 + 高 34↔31，窄窗回调用户点名内框偏小）；占位字号=dockPhFont 等比适配（用户点名完整可见，见 helper 注）
                  .backgroundColor(Color.Transparent).border({ width: 0 })
                  .placeholderColor(this.T().tx3)
                Text('Ctrl+K').fontSize(this.fp(F_KBD)).fontColor(this.T().tx3)   // batch-5：kbd 键帽（§3.3，10↔9）
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(5)
                  .backgroundColor(this.T().subtle).border({ width: 1, color: this.T().line })
                  .onClick(() => {
                    // 与 ⌘K 键位等价的 UI 入口（gap-kbd-1：无键盘环境可验证同链路）
                    this.getUIContext().getFocusController().requestFocus('promptInput');
                  })
                Row({ space: 6 }) {
                  Text('⚡').fontSize(this.fp(F_DOCK_CHIP)).fontColor(this.T().onAcc)   // batch-5：chip 档（§3.3，12↔11）
                  Text('一键生成').fontSize(this.sd(this.T().fBtnPrimary)).fontWeight(600).fontColor(this.T().onAcc)   // batch-3：13→HMOS 16（§3 button 档）；batch-5：主题变量走 sd 离散降档（HMOS 16→14/桌面 13→12，r9-sweep §3.3 要点 3）
                }.height(this.sp(H_DOCK_INPUT)).padding({ left: this.isNarrowBar() ? 12 : 18, right: this.isNarrowBar() ? 12 : 18 }).borderRadius(this.T().rBtnPrimary)   // batch-3 圆角；batch-5：主钮高随输入条（§3.3，34↔31 同高联动）；M3.6.9 窄窗 padding 18→12
                .backgroundColor(this.T().acc)
                .stateStyles({
                  pressed: { .backgroundColor(this.T().accTx) },   // batch-4 iss-5：B 底色叠加（acc 主钮按压色=accTx；HMOS=悬浮按钮 pressed #0070E5/#1A7AE1，§9 实证）
                  normal: { .backgroundColor(this.T().acc) }
                })
                .onClick(() => this.runPrompt())
              }.width('100%')
              .padding({ left: 13, right: 5, top: 5, bottom: 5 }).borderRadius(this.T().rPmain)   // batch-3：pmain 容器圆角 12→HMOS 20（§4 text_field）
              .backgroundColor(this.T().card)
              .border({ width: 1, color: this.promptFocused ? this.T().accTx : this.T().line })
              .shadow({ radius: SH_PMAIN_FOCUS.radius, offsetX: SH_PMAIN_FOCUS.dx, offsetY: SH_PMAIN_FOCUS.dy, color: this.T().shsm })   // r10 sh-5：几何 SH_PMAIN_FOCUS（2/(0,1)，色已走主题纯搬迁）
            }
            .width('100%')
            .padding(3).borderRadius(15)
            .backgroundColor(this.promptFocused ? 'rgba(0,122,255,0.12)' : this.T().trans)
            }
            // batch-7 cur-3 居中修复：壳用【定宽】width(min(680,max(320,cw−24)))——M3.6 复验：
            // constraintSize 内容自适应壳下 pmain width('100%') 不以壳为基准（uitest dump 实测
            // 壳 679vp 而 pmain 1010vp，对称溢出 ±165vp，「指令条超出组件组」用户红框点名）；
            // constraintSize 只钳壳自身测量、管不住百分比子组件。定宽后 100% 链有确定基准，
            // pchips/pmain 恒等于壳内宽，alignItems(Center) 居中确定性恢复（r8 偏移即自适应
            // 壳的伴生症状，一并消除）。cw 由画布 onAreaChange 实测回填（还原 368→344、
            // 最大化 1030→680，ddDock 历史日志两态均已验）。
            .width(Math.min(680, Math.max(320, this.cw - 24)))
            // M3.6.9 同步缩放：dock 整体（chips/输入/文案/间距）随画布宽等比缩放，
            // 底部中心原点（钉底不漂移）——字体/组件/文案一个机制整体缩，不再降档打架
            .padding(9)   // i:242 .promptbar padding:9
            .borderRadius(16)
            .backgroundColor(this.isDark() ? 'rgba(26,27,32,0.97)' : 'rgba(255,255,255,0.92)')
            .backdropBlur(20)
            .border({ width: 1, color: this.isDark() ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.08)' })
            .shadow(this.T().shDock)   // batch-3：dock 壳 {16,0,0,shadowLg}→shDock lg 档 100/(0,20)（§6）
            // batch-5 iss-7 入场（同 veil 口径：springMotion(0.55,0.825)；dock 卡当前无条件
            // 构建，transition 于插入/重建事件触发——与 veil/浮层同族入场语义保持）
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.translate({ y: 10 }))
              .animation({ curve: curves.springMotion(0.55, 0.825) }))
            // batch-7 cur-3/cur-11 校准埋点（ddTopBar/ddCanvas 先例）：壳实测宽高 + 画布宽，
            // 供 dump 对账居中偏差与 veil bottom 推导（带高实测值直接可查）
            .onAreaChange((o: Area, n: Area): void => {
              hilog.info(0x0000, 'ddDock', 'w=%{public}s h=%{public}s cw=%{public}s',
                Number(n.width).toString(), Number(n.height).toString(), this.cw.toString());
            })
          }.width('100%').height('100%')
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.Center)
          .padding({ bottom: 12 })
          .hitTestBehavior(HitTestMode.None)   // 外壳不挡命中（点击穿透到画布），子节点 dock 正常交互（gap-bottom-2）
        }.layoutWeight(1).height('100%').backgroundColor(this.T().cvs)   // 画布区=--cvs（batch-1 拆分）
        .onAreaChange((o: Area, n: Area) => {
          this.cw = Number(n.width);   // 容器实测 vp（gap-canvas-5 适配窗口输入）
          this.ch = Number(n.height);
          // r5b：无条件留痕每次实测（判据 E 定界数据：还原态 cw=368 与 dump 反推 349.5 差
          // ~5%、最大化适配读数 72% 与理论 fitOf≈101% 矛盾——若窗尺寸变化后本日志不再出现，
          // 即坐实 onAreaChange 冻结/不重放类，fitOf 口径争议随之定界）
          hilog.info(0x0000, 'ddCanvas', 'w=%{public}s h=%{public}s', this.cw.toString(), this.ch.toString());
          // batch-3 iss-4 兜底诊断：窗变随记（还原态点适配进 FIT 再切最大化形态的读数路径，
          // zoomLabel 实时重算无点按日志可锚）——与 fitWindow 日志同 tag 对账
          if (this.fitMode) {
            const cb = this.curBoard();
            if (cb !== null) {
              hilog.info(0x0000, 'ddFit', 'resize cw=%{public}s ch=%{public}s fit=%{public}s',
                this.cw.toString(), this.ch.toString(), this.fitOf(cb).toString());
            }
          }
        })
        .bindContextMenu(this.canvasMenu(), ResponseType.RightClick)
        .bindContextMenu(this.canvasMenu(), ResponseType.LongPress)   // 触屏长按通道（空白区长按弹画布菜单）

        // ---- right 360px（batch-7 cur-1：宽度 360→等比折算 rightW；窄窗门控且未选中元素
        // 且 track 页不在看时整栏不构建（rightFolded）——显性扩展决策沿用 isNarrowBar 先例，
        // 空态引导移左栏见左栏折叠提示块）----
        if (!this.rightFolded()) {
        Column() {
          // tabs（batch-5，audit-right-3 对齐 i:283-288 .rtabs/.rtab：flex 均分+内容居中+
          // 13px 图标+on 态 accTx/600/rgba(0,122,255,.04) 淡底+底部 2px accTx 条）
          Row() {
            this.rtab('属性', 'insp', 'M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6')
            this.rtab('Agent 追踪', 'track', 'M12 3l1.9 5.8 5.8 1.9-5.8 1.9L12 18.4l-1.9-5.8L4.3 10.7l5.8-1.9z')
          }.width('100%').backgroundColor('rgba(0,0,0,0.02)')
          .border({ width: { bottom: 1 }, color: this.T().bd })
          Scroll() {
            Column() {
              if (this.rightTab === 'insp') {
              if (this.selLayer !== '' && this.curLayer()) {
                // 瞬态防护（batch-repair）：门内表达式全部可选链+兜底——细粒度更新下门与表达式
                // 求值非原子，裸断言在 curLayer() 瞬态 null 时即崩（r3 验收 👁 崩溃实锤）
                // nodecard 节点头卡（batch-5，audit-right-4 对齐 i:290-293 .nodecard）：lbl mono
                // 大写 + 节点 id 12 mono 700 + 右侧类型 tag chip；去 rev 副行
                Row() {
                  Column({ space: 2 }) {
                    Text('当前选中节点')
                      .fontSize(this.fp(F_INSP_MONO_MINI)).fontFamily('monospace').fontWeight(700).fontColor(this.T().tx3)   // r10 sz-rcons-1：mono 小字断点（9↔8）
                    Text(this.curLayer()?.name ?? '')
                      .fontSize(this.fp(F_INSP_MONO)).fontFamily('monospace').fontWeight(700).fontColor(this.T().tx)   // r10 sz-rcons-1：mono 主字断点（12↔11）
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Text(this.curLayer()?.type ?? '')
                    .fontSize(this.fp(F_INSP_MONO_MINI)).fontFamily('monospace').fontWeight(600).fontColor(this.T().accTx)   // r10 sz-rcons-1：mono 小字断点（9↔8）
                    .backgroundColor('rgba(0,122,255,0.1)')
                    .padding({ left: 7, right: 7, top: 2, bottom: 2 }).borderRadius(6)
                }.width('100%').padding({ top: 9, bottom: 9, left: 11, right: 11 })
                .borderRadius(12)
                .backgroundColor(this.isDark() ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.035)')
                .border({ width: 1, color: this.isDark() ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)' })
                .margin({ bottom: 11 })
                // 单列行序（batch-5，audit-right-1 对齐 i:3175-3191）：约束→位置→尺寸→文本→
                // 填充→文字色→圆角/透明→阴影→字号/描边→描边色→对齐→斜体/线型→可见性→
                // 尺寸模式→容器布局→间距/内边距→布局对齐（加粗为鸿蒙数据入口保留表尾——登记）
                // 约束只读行（batch-5，gap-detail-12）：widthMode·layout 现值只读；constraints
                // 谓词语义差距登记归 gap-global-3（引擎接线回收）
                Row({ space: 6 }) {
                  Text('约束').fontSize(this.fp(F_INSP_LABEL)).fontWeight(500).fontColor(this.T().tx2).width(this.isNarrowBar() ? 40 : 52)   // r10 sz-rcons-1：行标断点（10.5↔9.5）
                  Text(`${this.curLayer()?.style.widthMode ?? 'fixed'} · ${this.curLayer()?.style.layout ?? 'none'}`)
                    .fontSize(this.fp(F_INSP_INPUT)).fontFamily('monospace').fontColor(this.T().tx3).layoutWeight(1)   // r10 sz-rcons-1：约束值断点（11.5↔10.5）
                }.width('100%').margin({ top: 6 })
                this.draftPairRow('位置',
                  { label: 'X', val: this.draftX, onCh: (v: string): void => { this.draftX = v; } },
                  { label: 'Y', val: this.draftY, onCh: (v: string): void => { this.draftY = v; } })
                this.draftPairRow('尺寸',
                  { label: 'W', val: this.draftW, onCh: (v: string): void => { this.draftW = v; } },
                  { label: 'H', val: this.draftH, onCh: (v: string): void => { this.draftH = v; } })
                this.draftSingleRow('文本',
                  { label: '文本', val: this.draftText, onCh: (v: string): void => { this.draftText = v; } })
                this.colorDraftRow('填充',
                  { label: '填充', val: this.draftFill, onCh: (v: string): void => { this.draftFill = v; } })
                this.colorDraftRow('文字色',
                  { label: '文字色', val: this.draftColor, onCh: (v: string): void => { this.draftColor = v; } })
                // 圆角/透明（batch-5，audit-right-8：透明度 0-1 step 0.1 数字输入，进草稿组；
                // Slider 留作触屏增强双通道同步）
                this.draftPairRow('圆角/透明',
                  { label: '圆角', val: this.draftRadius, onCh: (v: string): void => { this.draftRadius = v; } },
                  { label: '透明', val: this.draftOp, onCh: (v: string): void => { this.draftOp = v; } })
                Column({ space: 2 }) {
                  Text(`${Math.round((Number(this.draftOp) || 0) * 100)}%`)
                    .fontSize(this.fp(F_INSP_MONO_MINI)).fontColor(this.T().tx3).width('100%').textAlign(TextAlign.End)   // r10 sz-rcons-1：数值小字断点（9↔8）
                  Slider({ value: Math.round(Math.min(1, Math.max(0, Number(this.draftOp) || 0)) * 100), min: 0, max: 100, step: 1 })
                    .onChange((v: number) => { this.draftOp = String(Math.round(v) / 100); })
                    .width('100%').height(this.sp(H_BIND_ROW))   // r10 h-bind-2：约束行断点高（22↔20）
                }.width('100%').padding({ left: this.isNarrowBar() ? 46 : 58, right: 0 })
                // 阴影 4 等分演示档（audit-right-2 对齐 i:315-321）；保留存量 sm/lg 值不破坏
                // 旧文件；xl 顶档渲染 radius 18/offsetY 8（桌面 e1-e3 命名差异登记）
                this.shadowSegRow('阴影', {
                  label: '阴影', values: ['none', 'sm', 'lg', 'xl'], labels: ['无', '小', '大', '顶'],
                  current: this.curLayer()?.style.shadow ?? 'none',
                  onPick: (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'shadow', v); this.sync(); }
                  }
                })
                this.draftPairRow('字号/描边',
                  { label: '字号', val: this.draftFontSize, onCh: (v: string): void => { this.draftFontSize = v; } },
                  { label: '描边宽', val: this.draftStrokeW, onCh: (v: string): void => { this.draftStrokeW = v; } })
                this.colorDraftRow('描边色',
                  { label: '描边色', val: this.draftStroke, onCh: (v: string): void => { this.draftStroke = v; } })
                // 对齐（三段钮）
                this.segRow('对齐', {
                  label: '对齐', values: ['left', 'center', 'right'], labels: ['左', '中', '右'],
                  current: this.curLayer()?.style.align ?? 'left',
                  onPick: (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'align', v); this.sync(); }
                  }
                })
                // 斜体/线型（斜体单钮 + 线型三钮同排，i:3188 双 seg2 组合）
                Row({ space: 6 }) {
                  Text('斜体/线型').fontSize(this.fp(F_INSP_LABEL)).fontWeight(500).fontColor(this.T().tx2).width(this.isNarrowBar() ? 40 : 52)   // r10 sz-rcons-1：行标断点（10.5↔9.5）
                  Column() {
                    this.segBtn('I 斜体', this.curLayer()?.style.italic ?? false, (): void => {
                      const b = this.curBoard(); const l = this.curLayer();
                      if (b && l) { appStore.setStyle(b.id, l.id, 'italic', !(l.style.italic ?? false)); this.sync(); }
                    })
                  }.layoutWeight(1)
                  Row({ space: 4 }) {
                    ForEach(['solid', 'dashed', 'dotted'], (v: string, i: number) => {
                      Column() {
                        this.segBtn(['实', '虚', '点'][i], (this.curLayer()?.style.dash ?? 'solid') === v, (): void => {
                          const b = this.curBoard(); const l = this.curLayer();
                          if (b && l) { appStore.setStyle(b.id, l.id, 'dash', v); this.sync(); }
                        })
                      }.layoutWeight(1)
                    }, (v: string) => v)
                  }.layoutWeight(2)
                }.width('100%').margin({ top: 6 })
                // 可见性独立行（audit-right-9；对齐行尾 👁 已移除）
                this.visibilityRow()
                this.segRow('尺寸模式', {
                  label: '尺寸模式', values: ['fixed', 'hug', 'fill'], labels: ['定', '包', '撑'],
                  current: this.curLayer()?.style.widthMode ?? 'fixed',
                  onPick: (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'widthMode', v); this.sync(); }
                  }
                })
                this.segRow('容器布局', {
                  label: '容器布局', values: ['none', 'vertical', 'horizontal'], labels: ['无', '纵', '横'],
                  current: this.curLayer()?.style.layout ?? 'none',
                  onPick: (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'layout', v); this.sync(); }
                  }
                })
                this.draftPairRow('间距/内边距',
                  { label: '间距', val: this.draftGap, onCh: (v: string): void => { this.draftGap = v; } },
                  { label: '内边距', val: this.draftPad, onCh: (v: string): void => { this.draftPad = v; } })
                // 布局对齐（batch-5，gap-detail-12 对齐 i:3191 start/center/end）：数据面先行，
                // 渲染消费缓做（子元素模型未落地——与 layout/gap/padding 同口径登记）
                this.segRow('布局对齐', {
                  label: '布局对齐', values: ['start', 'center', 'end'], labels: ['起', '中', '末'],
                  current: this.curLayer()?.style.justify ?? 'start',
                  onPick: (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'justify', v); this.sync(); }
                  }
                })
                // 加粗（batch-3 数据入口保留表尾；桌面 inspector 无此行——鸿蒙扩展登记）
                this.segRow('加粗', {
                  label: '加粗', values: ['是', '否'], labels: ['是', '否'],
                  current: (this.curLayer()?.style.bold ?? false) ? '是' : '否',
                  onPick: (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'bold', v === '是'); this.sync(); }
                  }
                })
                // 交互绑定与状态（gap-right-3）
                this.bindSection(this.curBoard() ?? FALLBACK_BOARD, this.curLayer() ?? FALLBACK_LAYER)
                // insp-actions 拆两行（batch-5，audit-right-6 对齐 i:322-325 .insp-actions/.ibtn：
                // 水平/垂直两等分 + 删除元素独占全宽第二行；钮高 29/radius 8/card 底 1px line 边；
                // 删除常态白底 tx2——danger 仅 hover 字色语义，触屏无 hover 登记）
                Row({ space: 6 }) {
                  Column() {
                    this.segBtn('水平居中', false, (): void => {
                      const b = this.curBoard(); const l = this.curLayer();
                      if (b && l) { appStore.alignLayer(b.id, l.id, true); this.sync(); }
                    })
                  }.layoutWeight(1)
                  Column() {
                    this.segBtn('垂直居中', false, (): void => {
                      const b = this.curBoard(); const l = this.curLayer();
                      if (b && l) { appStore.alignLayer(b.id, l.id, false); this.sync(); }
                    })
                  }.layoutWeight(1)
                }.width('100%').margin({ top: 9 })
                Row() {
                  Text('删除元素').fontSize(this.fp(F_RBTN)).fontWeight(500).fontColor(this.T().tx2)   // r10 sz-rbottom-1：断点（11↔10）
                    .textAlign(TextAlign.Center)
                    .height(this.sp(H_RBTN)).borderRadius(8).layoutWeight(1)   // r10 h-rbottom-1：删钮断点高（29↔26）
                    .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
                    .onClick(() => {
                      const b = this.curBoard(); const l = this.curLayer();
                      if (b && l) {
                        appStore.deleteLayer(b.id, l.id);
                        this.selLayer = '';
                        this.sync();
                      }
                    })
                }.width('100%').margin({ top: 6 })
                // 「应用到中间态」（batch-5，audit-right-5 对齐 i:326 .apply）：面板最末全宽
                // 31/radius 8/12-600/acc 底，去 ↧；草稿 diff 一次提交（audit-right-7）
                Text('应用到中间态')
                  .fontSize(this.fp(F_RBTN_ACC)).fontWeight(600).fontColor(this.T().onAcc)   // r10 sz-rbottom-1：断点（12↔11）
                  .textAlign(TextAlign.Center)
                  .width('100%').height(this.sp(H_RBTN_ACC)).borderRadius(8).margin({ top: 8 })   // r10 h-rbottom-1：应用钮断点高（31↔27）
                  .backgroundColor(this.T().acc)
                  .onClick(() => { this.applyDrafts(); })
              } else {
                // 空态卡（batch-5，audit-right-12 对齐 i:971-973 .empty-insp）
                this.emptyCard('▢', '未选中元素', '在画布中点选任意元素\n属性与交互将在此显示', true)
              }
              } else {
                // 实时轨迹（gap-right-4）+ 命令流时间线（track tab 独占）
                // 头部（batch-5，audit-right-10 对齐 i:978 track-head）：「Agent 运行留痕」+清空 tbtn
                Row({ space: 6 }) {
                  Text('Agent 运行留痕').fontSize(this.fp(F_RTRACK_HEAD)).fontWeight(600).fontColor(this.T().tx)   // r10 sz-rtrack-1：题断点（11↔10）
                  Blank()
                  Text('清空').fontSize(this.fp(F_RTRACK_CLR)).fontColor(this.T().tx2)   // r10 sz-rtrack-1：清空断点（10.5↔9.5）
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 }).borderRadius(6)
                    .backgroundColor(this.T().subtle)
                    .onClick(() => {
                      this.agentSteps = [];
                      this.expandedStep = '';
                      appStore.timeline.splice(0);
                      this.sync();
                    })
                }.width('100%').margin({ bottom: 6 })
                if (this.agentSteps.length > 0) {
                  // M3.6.4 三段分组（对齐桌面 计划/执行/收尾审查三段语义）：段头=小标签
                  // +发丝线，空段整段不渲染；done/failed 绿胶囊/红染留段外作尾卡——
                  // 主题切换后卡片边界不清（用户截图点名）由段头+分组间距双重兜底
                  Column({ space: 7 }) {
                    if (this.stepsOfPhase('plan').length > 0) {
                      Column({ space: 5 }) {
                        this.phaseHead('计划', this.T().purple)
                        ForEach(this.stepsOfPhase('plan'), (s: AgentStep) => {
                          this.stepRow(s)
                        }, (s: AgentStep) => s.kind + s.label + String(s.ms) + s.detail)
                      }.width('100%')
                    }
                    if (this.stepsOfPhase('exec').length > 0) {
                      Column({ space: 5 }) {
                        this.phaseHead('执行', this.T().accTx)
                        ForEach(this.stepsOfPhase('exec'), (s: AgentStep) => {
                          this.stepRow(s)
                        }, (s: AgentStep) => s.kind + s.label + String(s.ms) + s.detail)
                      }.width('100%')
                    }
                    if (this.stepsOfPhase('review').length > 0) {
                      Column({ space: 5 }) {
                        this.phaseHead('审查修复', this.T().okText)
                        ForEach(this.stepsOfPhase('review'), (s: AgentStep) => {
                          this.stepRow(s)
                        }, (s: AgentStep) => s.kind + s.label + String(s.ms) + s.detail)
                      }.width('100%')
                    }
                    if (this.stepsOfPhase('tail').length > 0) {
                      Column({ space: 5 }) {
                        ForEach(this.stepsOfPhase('tail'), (s: AgentStep) => {
                          this.stepRow(s)
                        }, (s: AgentStep) => s.kind + s.label + String(s.ms) + s.detail)
                      }.width('100%')
                    }
                  }.width('100%').margin({ bottom: 10 })
                }
                if (this.timeline.length === 0 && this.agentSteps.length === 0) {
                  // 空态卡（batch-5，audit-right-12）：星芒图标+留痕链文案
                  this.emptyCard('✦', 'Agent 修改实时留痕', '指令 → 计划 → 引擎命令', false)
                }
                ForEach(this.timeline.slice(0, 12), (e: TlEntry) => {
                  this.tlCard(e)
                }, (e: TlEntry) => e.op + e.rev)
              }
            }.width('100%').padding(10).alignItems(HorizontalAlign.Start)
          }.layoutWeight(1).scrollBar(BarState.Auto)
          .scrollBarWidth(6).scrollBarColor(this.scrollThumb())   // i:24-25（batch-1，audit-left-12）
        }.width(this.rightW).height('100%').backgroundColor(this.T().panelS)   // batch-7 cur-1：360→等比折算
        .border({ width: { left: 1 }, color: this.T().bd }).alignItems(HorizontalAlign.Start)
        }
      }.layoutWeight(1)

      // ===== statusbar（27px，token 对齐）=====
      Row({ space: 10 }) {
        // tag 三态（batch-4，audit-topbar-8 对齐 i:373-375）：busy=AGENT 紫 / 人类操作后=
        // HUMAN 绿（okSoft/okText 恰为 tag.h 实值 rgba(40,167,69,.12)/#1d6b41）/ 否则 READY。
        // AGENT 用固定 #7c3aed/rgba(124,58,237,.12)（i:375 tag.a 实值；现 purple #9d4edd 色相
        // 偏——字面量+注释登记，同 flowStroke 法）
        Text(this.busy ? 'AGENT' : (this.lastCmdSrc === 'HUMAN' ? 'HUMAN' : 'READY'))
          .fontSize(this.fp(F_RSTATUS_MINI)).fontWeight(800)   // r10 sz-rstatus-1：徽章断点（8.5↔8）
          .fontColor(this.busy ? '#7c3aed' : this.T().okText).letterSpacing(0.5)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 }).borderRadius(99)
          .backgroundColor(this.busy ? 'rgba(124,58,237,0.12)' : this.T().okSoft)
        // op 行（batch-4，audit-topbar-9）：去「最近：」前缀；失败呈 `${op} ✗ ${err}` 尾缀形态；
        // err 色 #e05252（i:377 .op.err 实值，固定色字面量登记——现 danger #e5484d 色值偏）
        Text(this.lastErr !== '' ? `${this.lastOp} ✗ ${this.lastErr}` :
          (this.lastOp !== '' ? this.lastOp : '三条输入汇入同一命令流：人类拖拽 · Agent 指令 · 模板'))
          .fontSize(this.fp(F_RSTATUS))   // r10 sz-rstatus-1：消息断点（10.5↔9.5）
          .fontColor(this.lastErr !== '' ? '#e05252' : this.T().tx2)
          .fontFamily('monospace').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        Text(this.coreTag).fontSize(this.fp(F_RSTATUS)).fontColor(this.T().tx3).fontFamily('monospace')   // r10 sz-rstatus-1：coreTag 断点（10.5↔9.5）
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').height(this.sp(H_RSTATUS)).padding({ left: 12, right: 12 })   // r10 h-rstatus-1：状态条断点高（27↔24）
      .backgroundColor(this.T().panelS).border({ width: { top: 1 }, color: this.T().bd })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%').height('100%').backgroundColor(this.T().cvs)   // 根底=--cvs（batch-1 拆分）
    // 窗内容区实测宽（batch-7 cur-1）：三区等比折算输入（applyWindowW 折算 leftW/rightW +
    // ddCols 日志）。自由窗口拖拽缩放每次触发；首帧前 leftW/rightW=桌面默认值（@State 初值）。
    .onAreaChange((o: Area, n: Area): void => {
      this.applyWindowW(Number(n.width));
    })
    // 全屏渐变底（batch-1，audit-modal-4）：glass 主题 i:586/:727 的 135° 渐变近似
    // （ArkUI angle 与 CSS 同基准 0°=自下而上，135°≈左上→右下）；其余主题 grad=4×cvs 纯色等价
    .linearGradient({
      angle: 135,
      colors: [
        [this.T().grad[0], 0.0], [this.T().grad[1], 0.30],
        [this.T().grad[2], 0.62], [this.T().grad[3], 1.0]
      ]
    })
    .id('planRoot')
    .focusable(true)
    .onKeyEvent((e: KeyEvent): void => {
      this.onPlanKey(e);
    })
    // 设置/导出弃 bindSheet 改根内条件叠层（batch-3，audit-modal-1/2：bindSheet 无遮罩且
    // 最大化窗口形态整体不呈现——已两轮实证；demoCover 已证根内叠层模式，见下注）
    // 演示呈现改根内条件叠层（batch-repair）：r3 验收实证 bindContentCover 模态在本镜像
    // 全屏/还原两形态均不呈现（showDemo=true 截图仍为编辑器，r2 §24 隐藏前端三键后 □=web
    // Fullscreen 等价通道消失）——改为页面内 z 顶叠层（build 根 Stack 最后一个子节点），
    // 视觉/交互等价（全屏接管+自带 toast/HUD/键盘锚），不依赖平台模态管线。

    // ===== 口令重试弹层（修订 8）=====
    if (this.showPwdAsk) {
      this.pwdModal()
    }
    // ===== 自恢复询问弹层（gap-global-4 兜底）=====
    if (this.showRecoverAsk) {
      this.recoverModal()
    }
    // ===== 设置/导出根内叠层（batch-3，audit-modal-1/2）：z 序在 pwd/recover 之上、
    // toast 之下；Esc/遮罩/卡样式见各 builder 注释 =====
    if (this.showSettings) {
      this.settingsModal()
    }
    if (this.showExport) {
      this.exportModal()
    }
    // 组件拖拽幽灵 pill（batch-6，audit-left-10）：「＋ cid」跟手，None 不拦命中
    if (this.dragGhostCid !== '') {
      Text(`＋ ${this.dragGhostCid}`)
        .fontSize(11).fontWeight(600).fontColor(this.T().onAcc)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 }).borderRadius(99)
        .backgroundColor(this.T().acc)
        .shadow({ radius: 8, color: this.T().shadowMd })
        .position({ x: this.ghostX - 30, y: this.ghostY - 16 })
        .hitTestBehavior(HitTestMode.None)
    }
    // ===== 最小 toast（顶层、不拦截点击；batch-1 audit-modal-12 对齐 i:648：底 #20252d
    // （ThemeColors.toastBg 固定色）、padding 18/9、max-width 80vw 等价、bottom 56；
    // err 红染 batch-5 gap-detail-13 对齐 i:647；ok 字色=#fff（i:648 color:#fff 固定——
    // 非 onAcc：glass 等主题 acc-contrast 为深色，落在深灰药丸上会隐形））=====
    if (this.toastMsg !== '') {
      Column() {
        // ForEach 单元素键=文案|档位：toast() 换文案即换键重挂 → 入场 transition 重放
        // （对齐桌面 #toast animation:popIn .18s 在换文案时的重放语义）
        ForEach([this.toastMsg + '|' + this.toastKind], (m: string) => {
          Text((this.toastKind === 'err' ? '✕ ' : '') + this.toastMsg)
            .fontSize(this.fp(F_TOAST))   // r10 sz-toast-1：断点（12↔11）；瞬时态不可 dump——以 ddFont+代码走查验证（复审确认）
            .fontColor(this.toastKind === 'err' ? this.T().toastErrText : '#ffffff')
            .padding({ left: 18, right: 18, top: 9, bottom: 9 })   // i:648 9px 18px
            .backgroundColor(this.toastKind === 'err' ? this.T().toastErrBg : this.T().toastBg)
            .borderRadius(99)
            .border({
              width: this.toastKind === 'err' ? 1 : 0,
              color: this.toastKind === 'err' ? this.T().toastErrBorder : this.T().trans
            })
            .constraintSize({ maxWidth: '80%' })   // i:648 max-width:80vw 等价（满宽容器内 80%）
            // popIn 近似（i:259：opacity 0→1 / translateY(6px) / scale(.97)，.18s）：
            // 过冲贝塞尔 cubic-bezier(.2,.9,.3,1.2) 无内置等价 → Curve.Friction 近似，登记。
            // batch-5 iss-6 登记：既有 4 处 transition（主/演示 toast、decl veil、绿胶囊）
            // 曲线不动——Curve.Friction 既有登记，呈现一致性优先；是否统一物理曲线待项目主人裁决
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.translate({ y: 6 }))
              .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
              .animation({ duration: 180, curve: Curve.Friction }))
        }, (m: string) => m)
      }.width('100%').height('100%').justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.None)
      .padding({ bottom: 56 })   // i:648 bottom:56px。构建门修正：原 margin({bottom:56}) 挂在
                                 // height('100%') 子树上被居中 Stack 溢出对半吃掉（实测底部仅 28.6vp）
                                 // ——改 padding 不参与溢出，56 精确生效
    }
    // ===== 演示全屏叠层（batch-repair：替代 bindContentCover，见上注；z 顶=根 Stack 末子）=====
    if (this.showDemo) {
      this.demoCover()
    }
    }.width('100%').height('100%')
  }

  /** 演示全屏 cover（gap-canvas-8）：起点板居中适配，flow/tap 绑定消费，顶部板名 + 底部 HUD + 演示内 toast。
   * 板卡居中 = 外层缩后框 alignItems(Start) + 百分比 position('50%/50%') + markAnchor(缩后宽高/2)。
   * r7 定案（iss-3 真根因，r4/r5/r6 同指纹闭环）：偏左与 alignContent/数值 position/滞留 dw
   * 均无关——外层框（缩后 bw·z×bh·z）的内层 Stack 是未缩布局框（bw×bh），子宽>父宽按 size
   * 契约画出父范围（ts-universal-attributes-size：子宽大于父组件宽则画出父范围），Column
   * 默认 alignItems(Center) 把超界子横向居中 → 内层布局框横移 bw(z−1)/2（z<1 左移）；
   * 视觉缩放又锚在内层自身左上（centerX/Y=0）→ 板框视觉位 = W/2−bw·z/2 − bw(z−1)/2 =
   * W/2−bw/2，与 z 无关。r6 反推「dw'≈823vp」即此 z 消失式的误读：还原态 980/2−195=295vp
   * =560.5px（对 dump 板框节点 1067.5 ✓）、最大化 1642.1/2−195=626.05vp=1189.5px（|差|≈46 ✓）
   * ——两态逐 px 对账；纵向 justifyContent 默认 Start 无位移，垂直三轮全对即同构佐证
   * （r5「一板宽/3」= z 恰 0.6007 时 bw(1−z)/2 = 缩放板宽/3 的算术巧合，非 Stack 测量缺陷）。
   * 修法 = alignItems(Start)：内层布局框回到容器左上，视觉框=布局框=50% 居中盒，z<1/z>1
   * 同式成立；百分比锚定保留（50% 布局现算，零 @State 时序依赖）。TopStart（r5 判据 D）
   * 仍保留：顶部 HUD 行归位顶部 + position 为板卡唯一置位者。 */
  @Builder
  demoCover() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%').height('100%').backgroundColor(this.T().demoBg)
        .onAreaChange((o: Area, n: Area) => {
          this.dw = Number(n.width);
          this.dh = Number(n.height);
          // batch-3 iss-3 兜底诊断：r4 实证水平左偏（左 560px/右 857px）——留痕封面实测尺寸
          // 与适配系数供 bbox dump 对账；若 dump 仍左偏且此值与封面实际不符，即坐实
          // onAreaChange 首帧滞留旧值疑点。测量点已在本 Stack 全屏首子（兜底预案的迁移目标
          // 即此处，无更上游可迁）
          // batch-5（iss-3 复验定案）兜底预案登记（先复测再动刀，行为未改）：树内实证
          // actDemoEntry（:2222-2250）不复位 dw/dh，且 dw/dh 为跨演示会话存续的 @State——
          // 还原态↔最大化换形态重进演示时，onAreaChange 首帧前必以旧值算 position（结构性
          // 旧值首帧）。预案：复测仍偏左且 ddDemo 日志值≠dump 反推封面实测时，在
          // actDemoEntry 尾部置 this.dw=0; this.dh=0 强制先走空占位一帧再实测（复用现有
          // dw>0&&dh>0 守卫，demoZoom 未实测回 1 同款先例）。注意冻结测量场景的代价：若
          // onAreaChange 换形态后根本不重放，复位会把「旧值错位」变「恒空占位」——故须
          // 先以日志对账坐实病根再动刀，不可跳过复测直接落预案。
          // batch-5 定案（r6 验收坐实上述判病条件：还原态 dw=980 日志一致但 position 反推
          // dw'≈823）：复位方案作废——两阶段 onAreaChange（布局沉降期瞬态值→settled 值）下
          // 复位只清首帧、清不掉中间帧；改「百分比 position + markAnchor」把居中从状态消费
          // 改为布局解析（见条目内注），dw/dh 仅供本日志与 dw>0 首帧守卫/demoZoom。
          // r7 定案再修：「滞留 dw」定性作废——真根因=外层框 alignItems(Center) 对超界内层
          // 的居中位移（与 dw 时序无关，公式与两态对账见 ForEach 条目注/builder 注）；
          // 百分比锚定保留并补 Start 对齐。
          const dz: number = this.demoZoom();
          hilog.info(0x0000, 'ddDemo', 'cover dw=%{public}s dh=%{public}s zoom=%{public}s',
            this.dw.toString(), this.dh.toString(), dz.toString());
          // batch-13（验收修复，r8 实证「首进墨迹 0/11、再进 11/11」根因）：首次进演示时
          // 墨迹 Canvas 的 onReady/onAreaChange 早于本回调（同帧布局竞态），redrawInk 读到
          // dw=0 早退且此后无重绘钩子——inkStrokes 已装载但画布未绘；二次进演示 dw/dh 残留
          // 旧值即正常。修法=尺寸实测赋值处补一次重放（onReady 侧钩子保留，两序皆覆盖）。
          if (this.showDemo) {
            this.redrawInk();
          }
        })
      if (this.demoBoardList().length > 0) {
        if (this.dw > 0 && this.dh > 0) {
          // ForEach([board]) 模式（batch-repair）：itemGenerator 局部 b 非空，分支内零断言
          ForEach(this.demoBoardList(), (b: Board) => {
            // 外层 = 缩后布局尺寸(bw·z×bh·z)；内层原尺寸(bw×bh) + 左上锚点缩放。
            // r7 定案（iss-3）：z<1 时内层宽>外层宽（溢出画出父范围），Column 默认
            // alignItems(Center) 对超界子的横向居中位移 = 板框偏左真根因（视觉位恒
            // W/2−bw/2，两态 dump 逐 px 对账，详见 builder 注）——Start 对齐消位移。
            Column() {
              Stack() {
                ForEach(b.layers, (l: LayerNode) => {
                  this.elNode(b, l)
                }, (l: LayerNode) => `${b.id}/${l.id}|${Math.round(l.style.x)}|${Math.round(l.style.y)}|${l.style.text}|${l.style.color}`)
              }
              .width(b.width).height(b.height)
              .scale({ x: this.demoZoom(), y: this.demoZoom(), centerX: 0, centerY: 0 })
              .clip(true)
              .backgroundColor(this.T().card)
              .borderRadius(this.T().rBoardFrame)   // batch-3：demo 板框圆角 10→HMOS 24（§4 card）
            }
            .alignItems(HorizontalAlign.Start)
            .width(b.width * this.demoZoom())
            .height(b.height * this.demoZoom())
            // 居中=百分比 50%/50% + markAnchor 缩后/2（≡(W−bw·z)/2，布局系统按父容器现宽
            // 现高解析，零 @State 消费）；r6 的「滞留 dw」定性作废（真根因见上 alignItems 注）。
            // TopStart 下 position 仍是板卡唯一置位者（判据 D 约束保持）。
            .position({
              x: '50%',
              y: '50%'
            })
            .markAnchor({
              x: b.width * this.demoZoom() / 2,
              y: b.height * this.demoZoom() / 2
            })
            // batch-5 iss-6 切板方向过渡（登记偏离：桌面 playInFwd/Back .22s translateX ±26px
            // 淡入 → springMotion(0.6, 0.8)，baseline §8.2 模态转场条目；demoDir 由 demoTap
            // push 置 1/demoBack 置 -1，换板 ForEach 键重建触发 transition 重放的机制不变）
            .transition(TransitionEffect.asymmetric(
              TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 26 * this.demoDir })),
              TransitionEffect.OPACITY)
              .animation({ curve: curves.springMotion(0.6, 0.8) }))
            // r7 取证：板框最终落位直读（globalPosition=放置后全局位，vp；×密度≈px 与 dump
            // 同系）——验证员对账免 hotzone 反推；纯日志零布局影响（背景列 ddDemo 先例）。
            .onAreaChange((o: Area, n: Area) => {
              hilog.info(0x0000, 'ddDemo',
                'board L=%{public}s T=%{public}s w=%{public}s h=%{public}s b=%{public}s',
                Number(n.globalPosition.x).toString(), Number(n.globalPosition.y).toString(),
                Number(n.width).toString(), Number(n.height).toString(), b.id);
            })
          }, (b: Board) => `${b.id}|${Math.round(this.demoZoom() * 1000)}`)
          // 键=r5 判据 D 修订的再替代：原 dw/dh 入键在 r6 验收中恰是失效路径（dw 跳变未传播
          // 重建，见上注）——改并入 demoZoom 千分位：仅标度真变（切板/跨 min 项窗变）时重建
          // 条目，markAnchor/width/scale 输入随之刷新；dw/dh 微抖不再触发无效重建。残余风险
          // 登记：若 z 变重建亦失效，markAnchor 暂态旧值最多致 Δz·宽/2 级偏心（远小于旧病），且
          // 位置本体（50%）仍精确。
        }
        // dw/dh 未测得（onAreaChange 首帧前）：先渲染空占位——demoZoom 瞬态回 1 会闪一帧
        // 全尺寸板（gap-verify-5 配套）
      } else {
        Column() {
          Text('该画板已删除').fontSize(this.fp(F_DEMO_TITLE)).fontColor(this.T().demoText)   // r10 sz-demo-1：题断点（14↔13）
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      }
      // 演示批注墨迹层（batch-10，spec-ink-1 定案：通用版「批注」真身=演示模式标注墨迹层）：
      // 全屏 Canvas 夹在板卡与 HUD 之间——标注开启时 Default 吃掉触摸（热区暂停=标注优先、
      // 交互暂停），关闭时 None 放行热区；HUD/顶栏/退出为其上兄弟不受影响。橙 #E67E22、
      // lineWidth 2.6、round cap/join、中点二次贝塞尔平滑（drawStrokeTail/redrawInk）；
      // 坐标归一化 0–1 存 AppStore.ink（4 位小数，缩放/换屏重放不糊，onAreaChange 重放）。
      Canvas(this.inkCtx)
        .width('100%').height('100%')
        .hitTestBehavior(this.demoInk ? HitTestMode.Default : HitTestMode.None)
        .onReady((): void => {
          this.inkReady = true;
          this.redrawInk();
        })
        .onAreaChange((o: Area, n: Area): void => { this.redrawInk(); })
        .onTouch((e: TouchEvent): void => {
          if (!this.demoInk) return;
          if (e.touches.length === 0) return;
          const t = e.touches[0];
          if (e.type === TouchType.Down) {
            this.inkDrawing = true;
            this.inkCurrent = [[this.inkNormX(t.x), this.inkNormY(t.y)]];
            this.inkStyle();
          } else if (e.type === TouchType.Move && this.inkDrawing) {
            this.inkCurrent.push([this.inkNormX(t.x), this.inkNormY(t.y)]);
            this.drawStrokeTail();
          } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            if (this.inkDrawing && this.inkCurrent.length > 1) {
              this.inkStrokes = this.inkStrokes.concat([this.inkCurrent]);
              appStore.setInk(this.inkStrokes);   // 仅内存态；dirty 在 exitDemo 统一置
            }
            this.inkDrawing = false;
            this.inkCurrent = [];
          }
        })

      Row() {
        // 演示 HUD 全部坐固定深底（demoTopBg）——字色用固定白而非 onAcc：glass 等主题
        // acc-contrast 为深色（#1e1650 族），落在深底上会隐形（batch-1 主题扩容引入的修正）
        Text(`演示 · ${this.boardName(this.demoBoard)}`).fontSize(this.fp(F_DEMO_HEAD)).fontWeight(600)   // r10 sz-demo-1：题断点（12↔11）
          .fontColor('#ffffff').maxLines(1)
      }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .backgroundColor(this.T().demoTopBg)

      // 底部 HUD（gap-canvas-8，对齐 play-bar i:1190-1199）：返回/面包屑/绿框提示/热区开关/退出。
      // 包裹层 hitTestBehavior None + justifyContent End——不放 Blank()：Blank 以 Default 模式充满
      // 剩余空间会阻塞兄弟（封面板区）命中，r2 实证节点点击不派发 demoTap 的根因。
      Column() {
        Row({ space: 10 }) {
          Text('◀').fontSize(this.fp(F_DEMO_HEAD))   // r10 sz-demo-1：返回字形断点（12↔11）
            .fontColor(this.demoStack.length > 1 ? '#ffffff' : this.T().tx3)   // HUD 固定白（同上演示 HUD 修正）
            .stateStyles({
              pressed: { .scale({ x: HMOS_PRESS_SCALE, y: HMOS_PRESS_SCALE }) },   // batch-4 iss-5：A 缩放式（HUD 钮）
              normal: { .scale({ x: 1, y: 1 }) }
            })
            .onClick(() => { this.demoBack(); })   // 无条件调：栈底由 demoBack toast「已是起始页 · 点退出演示结束」不退出（r2 实证调用侧守卫吞掉了栈底反馈）
          Text(this.demoStack.map((id: string): string => this.boardName(id)).join(' › '))
            .fontSize(this.fp(F_DEMO)).fontColor('#ffffff').maxLines(1)   // r10 sz-demo-1：面包屑断点（11↔10）
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          Text('绿框 = 可点击交互 · Esc 返回上一页').fontSize(this.fp(F_DEMO_HINT)).fontColor(this.T().ok)   // 文案对齐 i:1193（batch-6，gap-detail-19；Esc 半句随 batch-2 键盘承载成立）+ r10 sz-demo-1：提示断点（10↔9）
          Text(this.demoHideHot ? '显示热区' : '隐藏热区').fontSize(this.fp(F_DEMO)).fontColor('#ffffff')   // r10 sz-demo-1：热区钮断点（11↔10）
            .stateStyles({
              pressed: { .scale({ x: HMOS_PRESS_SCALE, y: HMOS_PRESS_SCALE }) },   // batch-4 iss-5：A 缩放式（HUD 钮）
              normal: { .scale({ x: 1, y: 1 }) }
            })
            .onClick(() => { this.demoHideHot = !this.demoHideHot; })
          // batch-10（spec-ink-1）：演示批注两钮——标注开关（开启=热区暂停）+ 清除
          //（仅标注开启时可见，对齐桌面 play-bar 标注语义）
          Text(this.demoInk ? '✏ 标注中' : '✏ 标注')
            .fontSize(this.fp(F_DEMO)).fontColor(this.demoInk ? this.T().ok : '#ffffff')   // r10 sz-demo-1：标注钮断点（11↔10）
            .stateStyles({
              pressed: { .scale({ x: HMOS_PRESS_SCALE, y: HMOS_PRESS_SCALE }) },
              normal: { .scale({ x: 1, y: 1 }) }
            })
            .onClick(() => { this.toggleInk(); })
          if (this.demoInk) {
            Text('🧹 清除').fontSize(this.fp(F_DEMO)).fontColor('#ffffff')   // r10 sz-demo-1：清除钮断点（11↔10）
              .stateStyles({
                pressed: { .scale({ x: HMOS_PRESS_SCALE, y: HMOS_PRESS_SCALE }) },
                normal: { .scale({ x: 1, y: 1 }) }
              })
              .onClick(() => { this.clearInk(); })
          }
          Row({ space: 5 }) {
            Text('✕').fontSize(this.fp(F_DEMO)).fontColor('#ffffff')   // r10 sz-demo-1：✕ 断点（11↔10）
            Text('退出演示').fontSize(this.fp(F_DEMO)).fontColor('#ffffff')   // r10 sz-demo-1：退出钮断点（11↔10）
          }.padding({ left: 10, right: 10, top: 5, bottom: 5 }).borderRadius(99)
          .backgroundColor(this.T().demoExitBg)
          .stateStyles({
            pressed: { .scale({ x: HMOS_PRESS_SCALE, y: HMOS_PRESS_SCALE }) },   // batch-4 iss-5：A 缩放式（HUD 退出钮）
            normal: { .scale({ x: 1, y: 1 }) }
          })
          .onClick(() => { this.exitDemo(); })
        }.width('100%').padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .borderRadius(99).backgroundColor(this.T().demoTopBg)
      }.width('100%').height('100%').justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 16, right: 16, bottom: 14 })
      .hitTestBehavior(HitTestMode.None)

      // 演示期 toast 呈现面（gap-canvas-7）：页面级 toast 在 cover 之下不可见，演示内 toast 全部落此。
      // err 红染与主 toast 同款（batch-5，gap-detail-13）；ok 档/入场动画与主 toast 同步
      // （batch-1，audit-modal-12 对齐 i:648——键控重放 + popIn 近似，注释见主 toast 处）。
      if (this.toastMsg !== '') {
        Column() {
          ForEach([this.toastMsg + '|' + this.toastKind], (m: string) => {
            Text((this.toastKind === 'err' ? '✕ ' : '') + this.toastMsg)
              .fontSize(this.fp(F_DEMO_HEAD))   // r10 sz-demo-1（sweep :7443 模层 toast 副本）：断点（12↔11，F_DEMO_HEAD 与 F_TOAST 同档）
              .fontColor(this.toastKind === 'err' ? this.T().toastErrText : '#ffffff')
              .padding({ left: 18, right: 18, top: 9, bottom: 9 })
              .backgroundColor(this.toastKind === 'err' ? this.T().toastErrBg : this.T().toastBg)
              .borderRadius(99)
              .border({
                width: this.toastKind === 'err' ? 1 : 0,
                color: this.toastKind === 'err' ? this.T().toastErrBorder : this.T().trans
              })
              .constraintSize({ maxWidth: '80%' })
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.translate({ y: 6 }))
                .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
                .animation({ duration: 180, curve: Curve.Friction }))
          }, (m: string) => m)
        }.width('100%').height('100%').justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.None)
        .padding({ bottom: 56 })   // 同主 toast：margin 溢出对半修正
      }
    }
    .width('100%').height('100%')
    // 键盘承载（batch-2，gap-verify-3；batch-repair 起演示=根内叠层，不依赖平台模态焦点）：
    // 叠层顶层自带焦点锚：focusable 可持有焦点 + defaultFocus 打开即入焦（同内联编辑 TextInput
    // 先例），Esc→demoBack 与 planRoot 分支（onPlanKey showDemo 分支）同语义双保险。
    // 2in1 真机 Esc 列最终验收清单；模拟器先行 uitest keyCode 2070 注入验证。
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((e: KeyEvent): void => {
      if (e.type !== KeyType.Down) return;
      if (e.keyCode === KeyCode.KEYCODE_ESCAPE) {
        // batch-10（spec-ink-1）：Esc 先退标注再返回——标注开启时第一击只关标注（恢复热区），
        // 第二击起恢复既有返回语义（返回上一层；栈底由 demoBack toast 不退出；
        // 退出唯一入口=HUD 退出按钮）
        if (this.demoInk) {
          this.toggleInk();
          return;
        }
        this.demoBack();
      }
    })
  }

  /** 项目名 chip 的最近项目下拉（bindMenu 自定义 builder；当前项 ✓、空态引导文案）。 */
  @Builder
  recentMenu() {
    Column() {
      Text('最近项目').fontSize(this.fp(F_RMENU_HEAD)).fontWeight(600).fontColor(this.T().tx3)   // r10 sz-recentmenu-1：题断点（9.5↔9）
        .width('100%').padding({ left: 10, top: 6, bottom: 3 })
      if (this.recent.length === 0) {
        Text('暂无最近项目\n保存或打开 .ddp 后出现在这里')
          .fontSize(this.fp(F_RMENU)).fontColor(this.T().tx3).padding(14).textAlign(TextAlign.Center)   // r10 sz-recentmenu-1：空态断点（11↔10）
      }
      ForEach(this.recent, (it: RecentItem) => {
        Row({ space: 6 }) {
          Text(it.path === appStore.filePath ? '✓' : '')
            .fontSize(this.fp(F_RMENU)).fontColor(this.T().accTx).width(16).textAlign(TextAlign.Center)   // r10 sz-recentmenu-1：✓列断点（11↔10）
          Text(it.name).fontSize(this.fp(F_RMENU_NAME))
            .fontWeight(it.path === appStore.filePath ? 600 : 400).fontColor(this.T().tx)   // r10 sz-recentmenu-1：名断点（12↔11）
            .maxLines(1).layoutWeight(1)
          Text(this.relTime(it.ts)).fontSize(this.fp(F_RMENU_TIME)).fontColor(this.T().tx3)   // 行尾相对时间（batch-3，audit-modal-11）+ r10 sz-recentmenu-1：时间断点（9↔8）
        }.width(216).height(this.sp(H_RMENU_ROW)).padding({ left: 8, right: 8, top: 0, bottom: 0 }).borderRadius(7)   // r10 h-recentmenu-1：菜单行断点高（30↔27）
        .backgroundColor(it.path === appStore.filePath ? this.T().accSoft : Color.Transparent)
        .stateStyles({
          pressed: { .scale({ x: HMOS_PRESS_SCALE, y: HMOS_PRESS_SCALE }) },   // batch-2 dd-menu-recent：按压态补齐（对照 menuRow；顶栏/左栏项目区两锚点共用本 builder）
          normal: { .scale({ x: 1, y: 1 }) }
        })
        .onClick(() => { this.hotSwitch(it.path); })
      }, (it: RecentItem) => it.path + String(it.ts))
    }.padding({ bottom: 6 }).backgroundColor(this.T().card).borderRadius(this.T().rMenuPanel)
    // batch-3：最近项目下拉=菜单族第 5 处，圆角 10→HMOS 20（§4 menu）；阴影→shMenu md 档
    .border({ width: 1, color: this.T().line })
    .shadow(this.T().shMenu)
  }

  /**
   * 导出 DDP 两步浮层（batch-3，audit-modal-7 对齐 i:1073-1083：桌面为「加密/免密选项卡 →
   * 密码框」两步流，原单表单为自造；文案逐字对齐）。弃 bindSheet 改根内叠层（同设置卡，
   * audit-modal-2：最大化窗口形态 bindSheet 不呈现）。免密直走 saveTo('','')；加密第二层
   * 复用 pwdModal 骨架。Esc 关闭双通道同设置卡。
   */
  @Builder
  exportModal() {
    Column() {
      if (this.exportStep === 'choice') {
        Column({ space: 14 }) {
          Row({ space: 10 }) {
            // 渐变图标头 38×38 #007aff→#9d4edd（桌面 .ec-head 同款固定色，不进 ThemeColors）
            Stack() {
              Text('↧').fontSize(18).fontWeight(700).fontColor('#ffffff')
            }.width(38).height(38).borderRadius(10)
            .linearGradient({ angle: 135, colors: [['#007aff', 0.0], ['#9d4edd', 1.0]] })
            Text('导出 DDP').fontSize(16).fontWeight(700).fontColor(this.T().tx)
          }.width('100%')
          // 选项卡一：加密导出（文案逐字 i:1075-1076）
          Column({ space: 3 }) {
            Text('🔐 加密导出（推荐）').fontSize(this.fp(F_MODAL_OPT)).fontWeight(600).fontColor(this.T().tx)   // r10 sz-export-1：选项钮断点（13↔12）
            Text('设置密码，Argon2id + XChaCha20 加密，需要密码才能打开')
              .fontSize(this.fp(F_MODAL_DESC)).fontColor(this.T().tx2)   // r10 sz-export-1：描述断点（11↔10）
          }.width('100%').padding(12).borderRadius(10)
          .backgroundColor(this.T().subtle).border({ width: 1, color: this.T().line })
          .onClick(() => { this.exportStep = 'pwd'; })
          // 选项卡二：免密导出（文案逐字 i:1078-1079；直走 saveTo('','')）
          Column({ space: 3 }) {
            Text('📄 免密导出').fontSize(this.fp(F_MODAL_OPT)).fontWeight(600).fontColor(this.T().tx)   // r10 sz-export-1
            Text('仅压缩 + 完整性校验（DDP2），任何 ddpView 可直接打开')
              .fontSize(this.fp(F_MODAL_DESC)).fontColor(this.T().tx2)   // r10 sz-export-1
          }.width('100%').padding(12).borderRadius(10)
          .backgroundColor(this.T().subtle).border({ width: 1, color: this.T().line })
          .onClick(() => {
            this.showExport = false;
            this.exportStep = 'choice';
            this.saveTo('', '');
          })
          Row() {
            Blank()
            Text('取消').fontSize(this.fp(F_MODAL_OPT)).fontWeight(500).fontColor(this.T().tx2)   // r10 sz-export-1
              .height(this.sp(H_EXPORT_OPT)).padding({ left: 16, right: 16 }).borderRadius(8)   // r10 h-export-1：选项钮断点高（32↔28）
              .backgroundColor(this.T().subtle)
              .stateStyles({
                pressed: { .backgroundColor(this.T().pressFill) },   // batch-4 iss-5：B 底色叠加（中性钮）
                normal: { .backgroundColor(this.T().subtle) }
              })
              .onClick(() => { this.showExport = false; })
          }.width('100%')
        }.width(400).padding(18)
        .backgroundColor(this.T().card).borderRadius(this.T().rDialog)   // batch-3：弹层圆角 14→HMOS 24（§4 dialog）
        .border({ width: 1, color: this.T().bd })
        .shadow(this.T().shDialog)   // batch-3：veil+五弹层 lg 档 100/(0,20)（§6；桌面 {24,0,0,shadowLg} 现值同合并）
        .constraintSize({ maxWidth: '92%' })
      } else {
        // 第二层：密码框（pwdModal 骨架；说明含 i:1088 逐字句）
        Column({ space: 12 }) {
          Text('设置导出口令').fontSize(this.T().fDialogTitle).fontWeight(700).fontColor(this.T().tx)   // batch-3：弹层标题 15→HMOS 20（§3 dialog_tittle）
          Text('为导出的 .ddp 设置口令，打开时需输入。密码只用于本次解密，不会存储。')
            .fontSize(this.fp(F_MODAL_SUB)).fontColor(this.T().tx2).width('100%')   // r10 sz-export-1：说明断点（11.5↔10.5，F_MODAL_SUB 补枚档）
          TextInput({ placeholder: 'DDP 口令', text: this.exportPwd })
            .type(InputType.Password)
            .onChange((v: string) => { this.exportPwd = v; })
            .fontSize(this.fp(F_MODAL_OPT)).placeholderFont({ size: this.fp(F_MODAL_OPT) }).height(this.sp(H_PWD_INPUT)).width('100%').borderRadius(this.T().rBtnDialog)   // batch-3：口令输入框圆角 8→HMOS 20（§4 text_field；两处口令框合并）+ r10 sz-export-1/h-pwd-1：断点（13↔12 + 36↔32 同行联动）
            .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
            .padding({ left: 10, right: 10 })
          Row({ space: 10 }) {
            Text('上一步').fontSize(this.fp(F_MODAL_OPT)).fontWeight(500).fontColor(this.T().tx2)   // r10 sz-export-1
              .height(this.sp(H_DLG_BTN)).padding({ left: 18, right: 18 }).borderRadius(9)   // r10 h-dlgbtn-1：主按钮断点高（34↔30）
              .backgroundColor(this.T().subtle)
              .stateStyles({
                pressed: { .backgroundColor(this.T().pressFill) },   // batch-4 iss-5：B 底色叠加（中性钮）
                normal: { .backgroundColor(this.T().subtle) }
              })
              .onClick(() => { this.exportStep = 'choice'; this.exportPwd = ''; })
            Row({ space: 6 }) {
              Text('↧').fontSize(this.fp(F_MODAL_BTN)).fontColor(this.T().onAcc)   // r10 sz-export-1：↧ 断点（12↔11）
              Text('导出').fontSize(this.fp(F_MODAL_OPT)).fontWeight(600).fontColor(this.T().onAcc)   // r10 sz-export-1
            }.height(this.sp(H_DLG_BTN)).padding({ left: 18, right: 18 }).borderRadius(9)   // r10 h-dlgbtn-1
            .backgroundColor(this.T().acc)
            .stateStyles({
              pressed: { .backgroundColor(this.T().accTx) },   // batch-4 iss-5：B 底色叠加（acc 主钮→按压色）
              normal: { .backgroundColor(this.T().acc) }
            })
            .onClick(() => { this.confirmExport(); })
          }.margin({ top: 4 })
        }.width(320).padding(18)
        .backgroundColor(this.T().card).borderRadius(this.T().rDialog)   // batch-3：弹层圆角 14→HMOS 24（§4 dialog）
        .border({ width: 1, color: this.T().bd })
        .shadow(this.T().shDialog)   // batch-3：veil+五弹层 lg 档 100/(0,20)（§6；桌面 {24,0,0,shadowLg} 现值同合并）
      }
    }
    .width('100%').height('100%')
    .backgroundColor(this.T().modalMaskStrong)   // batch-3：modal-1 强遮罩 token（桌面 0.24 不分主题原值；HMOS #33000000/#66000000）
    .backdropBlur(6)
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((e: KeyEvent): void => {
      if (e.type === KeyType.Down && e.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.showExport = false;
        this.exportStep = 'choice';
      }
    })
  }

  /** DDP 口令重试弹层（showAlertDialog 无输入框能力，用声明式浮层）。 */
  @Builder
  pwdModal() {
    Column() {
      Column({ space: 12 }) {
        Text('输入口令').fontSize(this.T().fDialogTitle).fontWeight(700).fontColor(this.T().tx)   // batch-3：弹层标题 15→HMOS 20（§3 dialog_tittle）
        Text(this.pwdFor).fontSize(this.fp(F_PWD_SUB)).fontColor(this.T().tx3).maxLines(1)   // r10 sz-pwd-1：项目名断点（10.5↔9.5）
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        TextInput({ placeholder: 'DDP 口令', text: this.pwdInput })
          .type(InputType.Password)
          .onChange((v: string) => { this.pwdInput = v; })
          .fontSize(this.fp(F_MODAL_OPT)).placeholderFont({ size: this.fp(F_MODAL_OPT) }).height(this.sp(H_PWD_INPUT)).width('100%').borderRadius(this.T().rBtnDialog)   // batch-3：口令输入框圆角 8→HMOS 20（§4 text_field）+ r10 sz-pwd-1/h-pwd-1：断点（13↔12 + 36↔32 同行联动）
          .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
          .padding({ left: 10, right: 10 })
        Text(`第 ${this.openTries} 次 / 上限 3 次`).fontSize(this.fp(F_PWD_TRIES)).fontColor(this.T().tx3)   // r10 sz-pwd-1：次数断点（9.5↔9）
          .width('100%')
        Row({ space: 10 }) {
          Text('取消').fontSize(this.fp(F_MODAL_OPT)).fontWeight(500).fontColor(this.T().tx2)   // r10 sz-pwd-1
            .height(this.sp(H_DLG_BTN)).padding({ left: 18, right: 18 }).borderRadius(9)   // r10 h-dlgbtn-1
            .backgroundColor(this.T().subtle)
            .stateStyles({
              pressed: { .backgroundColor(this.T().pressFill) },   // batch-4 iss-5：B 底色叠加（中性钮）
              normal: { .backgroundColor(this.T().subtle) }
            })
            .onClick(() => { this.showPwdAsk = false; this.openTries = 0; })
          Text('解锁').fontSize(this.fp(F_MODAL_OPT)).fontWeight(600).fontColor(this.T().onAcc)   // r10 sz-pwd-1
            .height(this.sp(H_DLG_BTN)).padding({ left: 18, right: 18 }).borderRadius(9)   // r10 h-dlgbtn-1
            .backgroundColor(this.T().acc)
            .stateStyles({
              pressed: { .backgroundColor(this.T().accTx) },   // batch-4 iss-5：B 底色叠加（acc 主钮→按压色）
              normal: { .backgroundColor(this.T().acc) }
            })
            .onClick(() => { this.confirmPwd(); })
        }.margin({ top: 4 })
      }.width(320).padding(18).backgroundColor(this.T().card).borderRadius(this.T().rDialog)   // batch-3：弹层圆角 14→HMOS 24（§4 dialog）
      .border({ width: 1, color: this.T().bd })
      .shadow(this.T().shDialog)   // batch-3：veil+五弹层 lg 档 100/(0,20)（§6；桌面 {24,0,0,shadowLg} 现值同合并）
    }.width('100%').height('100%').backgroundColor(this.T().modalMask)   // 22% 暗化（batch-3，audit-modal-8：
                                                                          // 原 wireStroke 不透明灰蓝为自造值）
    .backdropBlur(6)   // 桌面遮罩 backdrop-filter blur 等价
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }

  /** 自恢复询问弹层（aboutToAppear 检测到 autorecover.json）。 */
  @Builder
  recoverModal() {
    Column() {
      Column({ space: 12 }) {
        Text('恢复上次未保存的项目？').fontSize(this.T().fDialogTitle).fontWeight(700).fontColor(this.T().tx)   // batch-3：弹层标题 15→HMOS 20（§3 dialog_tittle）
        Text('检测到上次退出时未保存的工作，可恢复到画布继续编辑。')
          .fontSize(this.fp(F_MODAL_SUB)).fontColor(this.T().tx2)   // r10 sz-recover-1：描述断点（11.5↔10.5，F_MODAL_SUB）
        Row({ space: 10 }) {
          Text('丢弃').fontSize(this.fp(F_MODAL_OPT)).fontWeight(500).fontColor(this.T().danger)   // r10 sz-recover-1
            .height(this.sp(H_DLG_BTN)).padding({ left: 18, right: 18 }).borderRadius(9)   // r10 h-dlgbtn-1
            .backgroundColor(this.T().dangerSoft)
            .onClick(() => { this.showRecoverAsk = false; })
          Text('恢复').fontSize(this.fp(F_MODAL_OPT)).fontWeight(600).fontColor(this.T().onAcc)   // r10 sz-recover-1
            .height(this.sp(H_DLG_BTN)).padding({ left: 18, right: 18 }).borderRadius(9)   // r10 h-dlgbtn-1
            .backgroundColor(this.T().acc)
            .stateStyles({
              pressed: { .backgroundColor(this.T().accTx) },   // batch-4 iss-5：B 底色叠加（acc 主钮→按压色）
              normal: { .backgroundColor(this.T().acc) }
            })
            .onClick(() => { this.doRecover(); })
        }.margin({ top: 4 })
      }.width(320).padding(18).backgroundColor(this.T().card).borderRadius(this.T().rDialog)   // batch-3：弹层圆角 14→HMOS 24（§4 dialog）
      .border({ width: 1, color: this.T().bd })
      .shadow(this.T().shDialog)   // batch-3：veil+五弹层 lg 档 100/(0,20)（§6；桌面 {24,0,0,shadowLg} 现值同合并）
    }.width('100%').height('100%').backgroundColor(this.T().modalMask)   // 22% 暗化（batch-3，audit-modal-8：
                                                                          // 原 wireStroke 不透明灰蓝为自造值）
    .backdropBlur(6)   // 桌面遮罩 backdrop-filter blur 等价
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }

  /**
   * 设置卡（batch-3，audit-modal-1/2：弃 bindSheet 改根内条件叠层——bindSheet 在最大化窗口
   * 形态不呈现（已两轮实证）且无遮罩；demoCover 已证根内叠层模式）。对齐桌面 settings-box：
   * 居中卡 maxWidth 560/radius 14/card 底/shadowLg + 全屏遮罩（r12 fix-aitab-6：i:454
   * min(560px,100vw-32)/padding 20/radius 14——rDialog(HMOS 24) 在此站显性改回并登记）。
   * 信息架构（r11，gap-r11-2/4，用户 2026-10-04 指定）：双 tab 各归其位、无常驻区——
   * 「外观」tab = 主题/外观（5 主题 chips+深浅档，batch-1 产物）+ 引擎/DDP 加密/Rust core
   * 状态三行 + 快捷键 KEYMAP（同一 86% 基准列）；「Agent 执行者」块删除（通用版外观页无此块，
   * r8-general-spec.md:249-253 阴性核对；执行者语义由 AI tab provider 序列 xiaoyi 档承接，
   * presetMenuGroups 已在位）；「AI 端点」tab = 服务商预设 14/BaseUrl/Key/Model/获取模型/
   * 能力提示/思考等级 6 档/步数上限 4 档/保存设置/取消（r12 fix-aitab-1~6 桌面字段结构
   * 复刻：sec 小题+字段标签行+h32 单值几何；「⌘保存并关闭」→「保存设置」，底部「⚡完成」
   * 钮删除——桌面无此钮，与取消/✕/Esc 重复）。快捷键可达判据归属 r4：判据 #13 ✅「KEYMAP
   * 末行 ⇧E/⇧H 可达 17 行全表」（report-r4.md:134；
   * report-r3.md 判据表该行实记 ✗ sheet 打不开归 2in1 真机）——不回退；Ctrl+/、Ctrl+, 呈现面
   * 不得回退（gap-detail-22 裁决）；语言 7 选不造（dropped 登记）。
   * Esc 关闭双通道：叠层根 onKeyEvent（对齐 i:2443-2446）+ onPlanKey Esc 分支（焦点在
   * TextInput 时根收不到键——该态以 取消/✕ 钮兜底，登记；r12 fix-aitab-6 起无完成钮）。
   */
  @Builder
  settingsModal() {
    Column() {
      Column({ space: 11 }) {
        Row() {
          Text('设置').fontSize(15).fontWeight(700).fontColor(this.T().tx)   // r12 fix-aitab-6：i:455 .settings-head h3 15px（16 退役）
          Blank()
          Text('✕').fontSize(this.fp(F_SET_CLOSE)).fontColor(this.T().tx3)   // r12 fix-aitab-6：F_SET_CLOSE 20↔22（桌面 i:455 .icon-close 22px，旧 14↔13 退役）
            .onClick(() => { this.showSettings = false; })
        }.width('100%')
        // 双 tab（桌面 .stabs 形态 i:462-464：容器 subtle 底 padding 3 radius 9，on 态 card 底）
        Row({ space: 4 }) {
          this.stab('外观', 'look')
          this.stab('AI 端点', 'ai')
        }.width('100%').padding(3).borderRadius(9).backgroundColor(this.T().subtle)
        Scroll() {
        Column({ space: 11 }) {
          if (this.settingsTab === 'look') {
            // 外观 pane（r11 IA，gap-r11-2/4：主题/外观 + 引擎/DDP/Rust core 状态三行 +
            // 快捷键 KEYMAP 各归外观 tab。包一层 100% 列防「86%×86%≈74%」缩窄陷阱——
            // 移入块与主题区同一 86% 基准（卡内容宽），与移入前逐像素同宽。
            // Agent 执行者块删除：通用版外观页无此块（r8-general-spec.md:249-253 阴性
            // 核对），执行者语义由 AI tab provider 序列 xiaoyi 档承接（presetMenuGroups））
            Column({ space: 11 }) {
              // 主题/外观（batch-1 产物：5 主题 chips + 深/浅两档）
              Column({ space: 7 }) {
                Text('主题').fontSize(this.fp(F_SET_HEAD)).fontColor(this.T().tx)
                  .width('100%').textAlign(TextAlign.Start)
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                  ForEach(THEME_CHIPS, (c: ThemeChipDef) => {
                    Text(c.label)
                      .fontSize(this.fp(F_SET_VAL)).fontWeight(500)   // r10 sz-settings-3：主题 chip 断点（11↔10）
                      .fontColor(this.themeId === c.id ? this.T().onAcc : this.T().accTx)
                      .padding({ left: 12, right: 12, top: 4, bottom: 4 }).borderRadius(this.T().rChipPill)   // batch-3：主题 chips 胶囊 99→HMOS 14（§4 piece）
                      .backgroundColor(this.themeId === c.id ? this.T().acc : this.T().accSoft)
                      .border({
                        width: 1,
                        color: this.themeId === c.id ? this.T().accTx : this.T().accSoft
                      })
                      .stateStyles({
                        pressed: { .scale({ x: HMOS_PRESS_SCALE, y: HMOS_PRESS_SCALE }) },   // batch-4 iss-5：A 缩放式（chips）
                        normal: { .scale({ x: 1, y: 1 }) }
                      })
                      .margin({ right: 6, bottom: 4 })
                      .onClick(() => {
                        this.themeId = c.id;
                        this.saveLook();
                      })
                  }, (c: ThemeChipDef) => c.id)
                }.width('100%')
                Row({ space: 6 }) {
                  Text('外观').fontSize(this.fp(F_SET_HEAD)).fontColor(this.T().tx)
                  Blank()
                  ForEach(['light', 'dark'], (m: string) => {
                    Text(m === 'light' ? '浅色' : '深色')
                      .fontSize(this.fp(F_SET_MINI)).fontWeight(500)   // r10 sz-settings-3：chips 行断点（10.5↔9.5）
                      .fontColor(this.themeChoice === m ? this.T().onAcc : this.T().tx2)
                      .padding({ left: 9, right: 9, top: 4, bottom: 4 }).borderRadius(this.T().rChipPill)
                      // batch-3：深浅 chips 胶囊 99→HMOS 14（§4 piece；仅外观 pane 这两枚——AI pane 同形 chips 未列明不动）
                      .backgroundColor(this.themeChoice === m ? this.T().acc : this.T().subtle)
                      .border({
                        width: 1,
                        color: this.themeChoice === m ? this.T().accTx : this.T().trans
                      })
                      .stateStyles({
                        pressed: { .scale({ x: HMOS_PRESS_SCALE, y: HMOS_PRESS_SCALE }) },   // batch-4 iss-5：A 缩放式（chips）
                        normal: { .scale({ x: 1, y: 1 }) }
                      })
                      .onClick(() => {
                        this.themeChoice = m;
                        this.saveLook();
                      })
                  }, (m: string) => m)
                }.width('100%')
              }.width('86%')
              // 状态说明三行（r11 自常驻区归位外观 tab：引擎 / DDP 加密 / Rust core）
              Divider().color(this.T().bd).width('86%')
              Row() {
                Text('引擎').fontSize(this.fp(F_SET_HEAD)).fontColor(this.T().tx)
                Blank()
                Text(this.engineTag).fontSize(this.fp(F_SET_VAL)).fontColor(this.T().tx2)   // r10 sz-settings-5：断点（11↔10）。gap-global-3：值位接真实 engineVersion 探针（默认=接线前文案，探测失败保持——诚实降级）
              }.width('86%')
              Row() {
                Text('DDP 加密').fontSize(this.fp(F_SET_HEAD)).fontColor(this.T().tx)
                Blank()
                Text('Argon2id + XChaCha20 · 已接通').fontSize(this.fp(F_SET_VAL)).fontColor(this.T().okText)   // r10 sz-settings-5：断点（11↔10）
              }.width('86%')
              Row() {
                Text('Rust core').fontSize(this.fp(F_SET_HEAD)).fontColor(this.T().tx)
                Blank()
                Text(this.coreTag).fontSize(this.fp(F_SET_TAG)).fontColor(this.T().tx3).maxLines(2)   // r10 sz-settings-5：tag 断点（9↔8）
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 190 })
              }.width('86%')
              Divider().color(this.T().bd).width('86%')
              // 快捷键（可达判据归属 r4：#13 ✅「KEYMAP 末行 ⇧E/⇧H 可达 17 行全表」
              // report-r4.md:134；report-r3.md 判据表该行实记 ✗ sheet 打不开归 2in1 真机）
              Column({ space: 4 }) {
                Text('快捷键').fontSize(this.fp(F_SET_HEAD)).fontWeight(600).fontColor(this.T().tx)
                  .width('100%')
                ForEach(KEYMAP, (kv: string[]) => {
                  Row() {
                    Text(kv[0]).fontSize(this.fp(F_SET_KBD)).fontFamily('monospace').fontColor(this.T().accTx)   // r10 sz-settings-6：键列断点（10↔9）
                    Blank()
                    Text(kv[1]).fontSize(this.fp(F_SET_KBD)).fontColor(this.T().tx2)   // r10 sz-settings-6：义列断点（10↔9）
                  }.width('100%')
                }, (kv: string[]) => kv[0])
              }.width('86%').alignItems(HorizontalAlign.Start)
            }.width('100%').alignItems(HorizontalAlign.Center)
          } else {
            // AI 端点 pane（batch-3，audit-modal-6。r12 fix-aitab-1/2/3/4/5 恢复桌面字段
            // 分组：唯一分区小题「AI 端点（Agent）」（i:469 .settings-sec 10.5/700/tx3 字距
            // .07em）+ 说明段 i:1135 全文 11px/tx3/行高1.6（i:455）+ 每字段 11px/tx2 标签行、
            // 标签-框距 5=G_SET_FIELD（i:466）；输入框桌面单值几何 h32/padding 9/radius 8+
            // monospace（fix-aitab-2：URL/Model 11.5、Token 12；H_SET_INPUT/F_SET_INPUT/
            // rIcon 圆角退役见 Theme.ets 退役注）；服务商预设全宽 select 行（fix-aitab-3）；
            // 获取模型中性钮 h28（fix-aitab-4）；块间距 12=G_SET_BLOCK（fix-aitab-5，桌面
            // 相邻框节距 15+5+32+12=64px）。G_SET_SECT/G_SET_ROWS/H_SET_PILL 退役登记。）
            Column({ space: this.sp(G_SET_BLOCK) }) {
              // 分区小题（桌面唯一，i:469 margin 14 0 2——面板首题 top 2 免记；sec→note
              // 2+10=12=G_SET_BLOCK 由容器承担）
              Text('AI 端点（Agent）')
                .fontSize(this.fp(F_SET_SEC)).fontWeight(700).fontColor(this.T().tx3)
                .letterSpacing(0.735).width('100%')   // i:469 letter-spacing .07em@10.5px=0.735
              // 说明段（i:1135 原文恢复；11px/tx3/行高1.6/margin 10 0 16（i:455）——上邻
              // 距由容器 12 承担（=sec 2+note 10），下补 4 凑 16）
              Text('Agent 为本应用内置的 Rust 进程内循环（wasmtime 引擎宿主），变更经 MoonViz 引擎门校验后写回唯一事实源 .mbt.md。此处配置 LLM 驱动端点：URL 含 /anthropic 走 Anthropic Messages 协议（x-api-key），其余按 OpenAI chat 兼容格式处理。')
                .fontSize(this.fp(F_SET_LABEL)).fontColor(this.T().tx3).lineHeight(17.6)   // 11px×1.6=17.6（i:455）
                .margin({ bottom: 4 }).width('100%')
              // 服务商预设（fix-aitab-3：桌面 i:1137-1154 字段块=标签+.settings-select 全宽
              // max-width 420/h≈32/padding 7 10/12.5px/radius 9；右置 H_SET_PILL 小药丸退役。
              // 小艺首项平级语义不回退——batch-9 用户显性决策，登记偏离桌面 13 档无小艺）
              Column({ space: this.sp(G_SET_FIELD) }) {
                Text('服务商预设').fontSize(this.fp(F_SET_LABEL)).fontColor(this.T().tx2).width('100%')
                Row() {
                  Text(this.cfgProvider === 'custom' ? '自定义 / 其他端点' : this.presetNameOf(this.cfgProvider))
                    .fontSize(this.fp(F_SET_SELECT)).fontColor(this.T().tx).maxLines(1).layoutWeight(1)
                  Text('▾').fontSize(8).fontColor(this.T().tx2)   // 保底 8
                }.width('100%').height(this.sp(H_SET_FIELD)).padding({ left: 10, right: 10 })
                .borderRadius(9)   // i:114 .settings-select radius var(--r-md)=9
                .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
                .constraintSize({ maxWidth: 420 })   // i:114 max-width:420px
                .bindMenu(this.presetMenuPanel)   // batch-4 dd-menu-preset：自绘面板 232 宽三组（引用形；14 档菜单数据不动）
              }.width('100%')
              // batch-9：小艺档条件注行（选中即展示——端侧免配置语义显性化；
              // r12 fix-aitab-1：对齐 hint 档 10.5px/tx3，原 tx2）
              if (this.cfgProvider === 'xiaoyi') {
                Text('端侧模型：无需 Base URL / API Token / Model ID')
                  .fontSize(this.fp(F_SET_SEC)).fontColor(this.T().tx3).width('100%')
              }
              // M3.6.2：小艺端侧档整段隐藏云端三项（用户决策——免配置档不该再看到
              // Base URL/API Token/Model ID 输入框，原 batch-9 仅 .enabled(false) 禁用
          //   态仍然全量渲染，语义矛盾）；思考等级/步数上限通用保留。
              if (this.cfgProvider !== 'xiaoyi') {
              // Base URL 字段块（fix-aitab-1 标签行 11px/tx2+框距 5；fix-aitab-2 桌面单值
              // 几何 h32/padding 0 9/radius 8/11.5px ui-monospace（i:466），占位=桌面 :1155
              // 原文；框下注行保留作长占位可见化替身，11px/tx3/行高1.6）
              Column({ space: this.sp(G_SET_FIELD) }) {
                Text('Base URL').fontSize(this.fp(F_SET_LABEL)).fontColor(this.T().tx2).width('100%')
                TextInput({ placeholder: '留空 = https://api.deepseek.com（DeepSeek 默认）；支持任意 OpenAI 兼容端点，或 .../anthropic 端点（自动走 Messages 协议）；本地 http 仅限内网地址', text: this.cfgBaseUrl })
                  .onChange((v: string) => {
                    this.cfgBaseUrl = v;
                    this.detectProviderFromUrl(false);   // batch-12：positive 反查（逐字符时机不误翻 custom）
                  })
                  .onBlur((): void => { this.detectProviderFromUrl(true); })   // batch-12：失败回落 custom
                  .fontSize(this.fp(F_SET_MONO_URL)).placeholderFont({ size: this.fp(F_SET_MONO_URL) }).fontFamily('monospace')
                  .height(this.sp(H_SET_FIELD)).borderRadius(8).width('100%')   // r12 fix-aitab-2：i:466 h32/radius 8 单值（T().rIcon 非 hmos=5 退役）
                  .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
                  .padding({ left: 9, right: 9, top: 0, bottom: 0 })   // i:466 padding 0 9
                  .enabled(this.cfgProvider !== 'xiaoyi')   // batch-9：小艺档免 baseUrl（零回退门）
                if (this.cfgProvider !== 'xiaoyi') {
                  Text('留空=DeepSeek 默认；本地地址仅限内网')
                    .fontSize(this.fp(F_SET_LABEL)).fontColor(this.T().tx3).lineHeight(17.6).width('100%')   // r12 fix-aitab-2：11px/tx3/行高1.6
                }
              }.width('100%')
              // API Token 字段块（占位=桌面 :1156 原文；12px ui-monospace=.settings-grid
              // 基准档 i:466；注行同上保留）
              Column({ space: this.sp(G_SET_FIELD) }) {
                Text('API Token').fontSize(this.fp(F_SET_LABEL)).fontColor(this.T().tx2).width('100%')
                TextInput({ placeholder: '仅本机保存；留空则用环境变量 AI_GATEWAY_API_KEY；订阅计划填专属 Key（MiniMax 为 sk-cp- 前缀）', text: this.cfgApiKey })
                  .type(InputType.Password)
                  .onChange((v: string) => { this.cfgApiKey = v; })
                  .fontSize(this.fp(F_SET_MONO_VAL)).placeholderFont({ size: this.fp(F_SET_MONO_VAL) }).fontFamily('monospace')
                  .height(this.sp(H_SET_FIELD)).borderRadius(8).width('100%')
                  .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
                  .padding({ left: 9, right: 9, top: 0, bottom: 0 })
                  .enabled(this.cfgProvider !== 'xiaoyi')   // batch-9：小艺档免 Key（零回退门）
                if (this.cfgProvider !== 'xiaoyi') {
                  Text('仅本机保存；订阅计划填专属 Key（sk-cp-…）')
                    .fontSize(this.fp(F_SET_LABEL)).fontColor(this.T().tx3).lineHeight(17.6).width('100%')
                }
              }.width('100%')
              // Model ID 字段块（label+框+获取模型 gap 6（i:1160 span flex gap:6）；
              // fix-aitab-4 获取模型中性化：桌面 i:1161 .tbtn h28/padding 0 10/radius 6/
              // 11px/500/tx2 透明底（accSoft 蓝底满高退役）；xiaoyi opacity 0.5+return
              // 守卫不动；模型触发行=桌面 datalist 的鸿蒙替身（值 11.5 mono 同
              // #agent-model 档）；#agent-model-hint（10.5/tx3/lh1.55/mt5 i:463）归位本块）
              Column({ space: this.sp(G_SET_FIELD) }) {
                Text('Model ID').fontSize(this.fp(F_SET_LABEL)).fontColor(this.T().tx2).width('100%')
                Row({ space: 6 }) {
                  TextInput({ placeholder: '如 MiniMax-M3 / deepseek-chat / glm-4.7（MiniMax 可点右侧获取）', text: this.cfgModel })
                    .onChange((v: string) => {
                      this.cfgModel = v;
                      this.restrictThinking();   // batch-12：手输模型随收档位（零回退门）
                    })
                    .fontSize(this.fp(F_SET_MONO_URL)).placeholderFont({ size: this.fp(F_SET_MONO_URL) }).fontFamily('monospace')
                    .height(this.sp(H_SET_FIELD)).borderRadius(8).layoutWeight(1)
                    .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
                    .padding({ left: 9, right: 9, top: 0, bottom: 0 })
                    .enabled(this.cfgProvider !== 'xiaoyi')   // batch-9：小艺档免 model（零回退门）
                  // M3.6.3：▾ 帽内嵌输入行（用户决策）——获取模型成功后出现在输入框尾部，
                  // 点击展开模型清单（bindMenu 引用形），选中经 pickModel 回填本输入框；
                  // 输入框手输名义不变。原输入框下方的独立模型触发行拆除（与输入框双框
                  // 同值显示，用户红框点名冗余）
                  if (this.cfgModels.length > 0) {
                    Text('▾').fontSize(10).fontColor(this.T().tx2)
                      .height(this.sp(H_SET_FIELD))
                      .padding({ left: 2, right: 10 })
                      .bindMenu(this.modelMenuPanel)
                  }
                  Text('获取模型').fontSize(this.fp(F_SET_LABEL)).fontWeight(500).fontColor(this.T().tx2)
                    .height(this.sp(H_SET_BTN)).padding({ left: 10, right: 10 }).borderRadius(6)   // r12 fix-aitab-4：i:1161 inline font 11/padding 0 10 + .tbtn h28 r6
                    .stateStyles({
                      pressed: { .backgroundColor(this.T().pressFill) },   // batch-4 iss-5：B 底色叠加（中性钮）
                      normal: { .backgroundColor(Color.Transparent) }
                    })
                    .opacity(this.cfgProvider === 'xiaoyi' ? 0.5 : 1)
                    .onClick(() => {
                      if (this.cfgProvider === 'xiaoyi') return;   // batch-9：小艺档禁获取（零回退门）
                      this.fetchModels();
                    })
                }.width('100%')
                // （独立模型触发行已于 M3.6.3 拆除——▾ 帽内嵌 Model ID 输入行，见上）
                // 能力提示（i:1157-1164 #agent-model-hint 等价；batch-3 audit-modal-6；
                // r12 fix-aitab-1：10.5/tx3=F_SET_SEC+行高1.55，归位 Model ID 字段块，
                // 原非缺失态 tx2 对齐桌面 tx3）
                if (this.capHintMain() !== '') {
                  Text(this.capHintMain())
                    .fontSize(this.fp(F_SET_SEC)).lineHeight(16.3)
                    .fontColor(this.T().tx3)
                    .width('100%')
                }
                if (this.capHintWarn() !== '') {
                  Text(this.capHintWarn()).fontSize(this.fp(F_SET_SEC)).lineHeight(16.3).fontColor(this.T().danger).width('100%')
                }
              }.width('100%')
              }   // M3.6.2 小艺档包裹层闭合（if cfgProvider !== 'xiaoyi'，:8502 开）

              // 思考等级（i:1165-1175；batch-12 cur-9：chips → Select 组件=桌面 <select> 语义；
              // 档位经 restrictThinking 按快照 reasoning_options 收紧。
              // batch-3 dd-select-thinking：Select → ddMenuPanel 自绘弹层（同构模型档）。
              // restrictThinking（:1732）本体与「档位不变不重赋」缓解项（:1750-1753）本批
              // 不删（语义随迁）——自绘弹层后「Select 面板重建吞点击」原始病理不复存在，
              // 该守卫是否仍适用/可回收随本批验收结论登记：r8 GLM 档点击未展开现象若消失
              // 即为 Select 特异性佐证，回收留下轮。r12 fix-aitab-1：F_SET_HEAD 题降格
              // 11px 字段标签；触发框随字段几何 h32/radius 8/padding 9/border，值 12px mono
              // （.settings-grid select 基准档 i:466）；hint 10.5/tx3（:1175））
              Column({ space: this.sp(G_SET_FIELD) }) {
                Text('思考等级').fontSize(this.fp(F_SET_LABEL)).fontColor(this.T().tx2).width('100%')
                Row() {
                  Text(this.thinkLabel(this.cfgThinking))
                    .fontSize(this.fp(F_SET_MONO_VAL)).fontFamily('monospace')
                    .fontColor(this.T().tx).maxLines(1).layoutWeight(1)
                  Text('▾').fontSize(8).fontColor(this.T().tx2)
                }.width('100%').height(this.sp(H_SET_FIELD)).padding({ left: 9, right: 9, top: 0, bottom: 0 }).borderRadius(8)
                .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
                .bindMenu(this.thinkMenuPanel)   // 箭头形→引用形（r9 实测箭头形 builder 不求值）
                Text(THINK_NOTE).fontSize(this.fp(F_SET_SEC)).fontColor(this.T().tx3).width('100%')   // :1175 等级说明 10.5/tx3
              }.width('100%')
              // 步数上限 4 档（i:1176-1183；batch-12 cur-9：chips → Select；
              // batch-3 dd-select-steps：Select → ddMenuPanel 自绘弹层，触发框文案走 stepLabel；
              // r12 fix-aitab-1：同思考等级字段化——11px 标签+12px mono 触发值）
              Column({ space: this.sp(G_SET_FIELD) }) {
                Text('步数上限').fontSize(this.fp(F_SET_LABEL)).fontColor(this.T().tx2).width('100%')
                Row() {
                  Text(this.stepLabel(this.cfgMaxSteps))
                    .fontSize(this.fp(F_SET_MONO_VAL)).fontFamily('monospace')
                    .fontColor(this.T().tx).maxLines(1).layoutWeight(1)
                  Text('▾').fontSize(8).fontColor(this.T().tx2)
                }.width('100%').height(this.sp(H_SET_FIELD)).padding({ left: 9, right: 9, top: 0, bottom: 0 }).borderRadius(8)
                .backgroundColor(this.T().card).border({ width: 1, color: this.T().line })
                .bindMenu(this.stepMenuPanel)   // 箭头形→引用形（r9 实测箭头形 builder 不求值）
              }.width('100%')
              // 动作行（r12 fix-aitab-6：右对齐 gap 8/mt 18（i:472 .settings-actions），
              // 取消+保存设置=.tbtn/.tbtn.pri h28 r6（i:75/i:79/:1186）；主钮文案
              // 「保存设置」（「⌘保存并关闭」退役）；取消透明底 tx2、保存 acc 底 onAcc，
              // 字 12/500（F_SET_BTN）。桌面 .tbtn.pri shadow 0 1 3 未复刻——非 approach
              // 清单项，登记未做。保存=关闭本身不 toast（i:4177）；取消不保存直接关）
              Row({ space: 8 }) {
                Blank()
                Text('取消').fontSize(this.fp(F_SET_BTN)).fontWeight(500).fontColor(this.T().tx2)
                  .height(this.sp(H_SET_BTN)).padding({ left: 10, right: 10 }).borderRadius(6)   // i:75 .tbtn h28/padding 0 10/radius var(--r-sm)=6（H_SET_CTRL 27/30 退役）
                  .stateStyles({
                    pressed: { .backgroundColor(this.T().pressFill) },   // batch-4 iss-5：B 底色叠加（中性钮）
                    normal: { .backgroundColor(Color.Transparent) }
                  })
                  .onClick(() => { this.showSettings = false; })
                Text('保存设置').fontSize(this.fp(F_SET_BTN)).fontWeight(500).fontColor(this.T().onAcc)
                  .height(this.sp(H_SET_BTN)).padding({ left: 10, right: 10 }).borderRadius(6)
                  .backgroundColor(this.T().acc)
                  .stateStyles({
                    pressed: { .backgroundColor(this.T().accTx) },   // batch-4 iss-5：B 底色叠加（acc 主钮→按压色）
                    normal: { .backgroundColor(this.T().acc) }
                  })
                  .onClick(() => { this.saveAiConf(); })
              }.width('100%').margin({ top: 6 })   // 容器块距 12+6=18=i:472 margin-top 18
            }.width('86%')
          }
          // r11：原「常驻区」（Agent 执行者三行 + 引擎/DDP/Rust core 三行 + 快捷键 KEYMAP）
          // 已拆除——状态三行与快捷键归位 look 分支（同一 86% 基准），Agent 执行者块删除。
        }.width('100%').alignItems(HorizontalAlign.Center)
        }.width('100%').layoutWeight(1).align(Alignment.Top)
        .scrollBar(BarState.Auto)   // 滚动条可视反馈（与左右栏 Scroll 一致）
        .scrollBarWidth(6).scrollBarColor(this.scrollThumb())   // i:24-25（batch-1，audit-left-12）；
                                                                // 自 bindSheet 迁移保留（batch-3 防返工锚）
        .nestedScroll({
          scrollForward: NestedScrollMode.PARENT_FIRST,
          scrollBackward: NestedScrollMode.SELF_FIRST
        })
        // r12 fix-aitab-6：底部「⚡完成」钮删除——桌面无此钮（i:1186 settings-actions 后
        // settings-box 即收尾），与取消/✕/Esc 三关闭路径重复；触屏兜底=取消/✕（下注
        // 「焦点在 TextInput 时根收不到键」的旧三钮登记同步改写）。F_SET_DONE/F_SET_DONE_L
        // 随钮退役（Theme.ets 退役注）。
      }
      .width('92%').height('80%')
      .constraintSize({ maxWidth: 560, maxHeight: 640 })   // r12 fix-aitab-6：i:454 width min(560px,100vw-32)——maxWidth 680→560
      .padding(20)   // r12 fix-aitab-6：i:454 padding 20（16 退役）
      .backgroundColor(this.T().card).borderRadius(14)   // r12 fix-aitab-6：i:454 radius 14——rDialog(HMOS 24) 在此站显性改回桌面单值并登记（batch-3 §4 dialog 断点链破例站）
      .border({ width: 1, color: this.T().bd })
      .shadow(this.T().shDialog)   // batch-3：veil+五弹层 lg 档 100/(0,20)（§6；桌面 {24,0,0,shadowLg} 现值同合并）
    }
    .width('100%').height('100%')
    .backgroundColor(this.T().modalMaskStrong)   // batch-3：modal-1 强遮罩 token（桌面 0.24 不分主题原值；HMOS #33000000/#66000000）
    .backdropBlur(6)   // 背后编辑器隐约可见（audit-modal-1 居中模态卡+遮罩）
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((e: KeyEvent): void => {
      if (e.type === KeyType.Down && e.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.showSettings = false;   // i:2443-2446 Esc 关设置
      }
    })
  }

  /** 右栏 tab 单钮（batch-5，audit-right-3 对齐 i:286-288 .rtab：flex 均分+居中+13px 图标+
   * on 态 accTx/600/淡蓝底/底部 2px accTx 条；图标 viewPort 归 Shape 容器——batch-4 构建门教训）。
   * r12 fix-topbar-3 同案：24×24 基底+.scale(13/24)（双重缩放定律，spec §一）+13×13 Stack
   * 保布局（下方「13 高图标容器」判据仍成立）；strokeWidth 2 非本轮范围不动。 */
  @Builder
  rtab(label: string, id: string, icon: string) {
    Row({ space: 5 }) {
      Stack() {
        Shape() {
          Path().commands(icon)
            .width(24).height(24)
            .fillOpacity(0)
            .stroke(this.rightTab === id ? this.T().accTx : this.T().tx2).strokeWidth(2)
            .strokeLineCap(LineCapStyle.Round).strokeLineJoin(LineJoinStyle.Round)
        }
        .viewPort({ x: 0, y: 0, width: 24, height: 24 })
        .width(24).height(24)
        .scale({ x: 13 / 24, y: 13 / 24 })   // r12 fix-topbar-3：B 案（S=13=桌面 .rtab .ic）
      }.width(13).height(13)
      Text(label).fontSize(this.fp(F_RTAB))   // r10 sz-rtab-1：tab 断点字号（12.5↔11.5）
        .fontWeight(this.rightTab === id ? 600 : 500)
        .fontColor(this.rightTab === id ? this.T().accTx : this.T().tx2)
    }.justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
    .layoutWeight(1).height(this.sp(H_RTAB))   // r10 h-rtab-1：tab 断点高（37↔33）；上方 13 高图标容器禁改（sz-excl）
    .border({ width: { bottom: 2 }, color: this.rightTab === id ? this.T().accTx : this.T().trans })
    .backgroundColor(this.rightTab === id ? 'rgba(0,122,255,0.04)' : Color.Transparent)
    .onClick(() => { this.rightTab = id; })
  }

  /** 设置卡双 tab 单钮（桌面 .stab 形态）。 */
  @Builder
  stab(label: string, id: string) {
    Text(label)
      .fontSize(this.fp(F_STAB)).fontWeight(600)   // r10 sz-stab-1：tab 断点字号（12↔11）
      .fontColor(this.settingsTab === id ? this.T().tx : this.T().tx2)
      .textAlign(TextAlign.Center).height(this.sp(H_STAB)).layoutWeight(1).borderRadius(7)   // r10 h-stab-1：tab 断点高（30↔27）
      .backgroundColor(this.settingsTab === id ? this.T().card : Color.Transparent)
      .shadow(this.settingsTab === id ?
        { radius: SH_SEG_SELECTED.radius, offsetX: SH_SEG_SELECTED.dx, offsetY: SH_SEG_SELECTED.dy, color: this.T().shadowMd } :
        { radius: 0, offsetX: 0, offsetY: 0, color: this.T().trans })   // r10 sh-3：复用 SH_SEG_SELECTED（3/(0,1)，色已走主题）
      .onClick(() => { this.settingsTab = id; })
  }

  /** 预设 id → 显示名（设置卡服务商 chip 用；未知 id 显示原值）。 */
  private presetNameOf(id: string): string {
    const p = PRESETS.find((x: ProviderPreset): boolean => x.id === id);
    return p ? p.name : id;
  }
}
