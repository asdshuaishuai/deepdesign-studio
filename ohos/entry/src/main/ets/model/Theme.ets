// ===== 鸿蒙设计 token 常量层（batch-1，iss-4）=====
// 事实源：out/harmony-parity/hmos-design-baseline.md（只读规范），逐条注明 baseline 条目；
// 浅/深两档成对给出（baseline 第 2 节 [A1] = global_system_resources 仓库直读值）。
// 与 resources/base|dark/element/color.json 的 dd_* 资源为「同名同值」镜像对账
// （资源=系统面事实源）；Index.ets 的 THEME_HMOS_L/D 主题表按本层常量取值。
// 纪律：Index.ets 主题表 ThemeColors 保持 string——不引入 $r('sys.*')/$r('app.*') 资源符号
// 进表：acc/danger/ok/purple/tx/card 会被当画布数据字符串消费（inlineAgent 换色、
// colorPalette→appStore.setStyle 写层样式），资源符号会污染画布数据。

/** 浅/深两档成对色值（baseline 第 2 节口径：深色不是简单黑白反转）。 */
export interface HmosColorPair {
  light: string;
  dark: string;
}

/** 阴影几何（baseline 第 6 节：radius 即 blur，offset 单位 vp）。 */
export interface HmosShadow {
  radius: number;
  dx: number;
  dy: number;
}

// —— 2.2 品牌色与强调色 [A1]（品牌色深色模式加深，避免暗底过亮）——
export const HMOS_BRAND: HmosColorPair = { light: '#007DFF', dark: '#006CDE' };                // sys.color.brand / ohos_id_color_emphasize
export const HMOS_COMPONENT_ACTIVATED: HmosColorPair = { light: '#007DFF', dark: '#317AF7' };  // ohos_id_color_component_activated
export const HMOS_FOCUS: HmosColorPair = { light: '#007DFF', dark: '#3F97E9' };                // ohos_id_color_focused_outline
export const HMOS_PRESSED: HmosColorPair = { light: '#0070E5', dark: '#1A7AE1' };              // ohos_id_color_floating_button_bg_pressed（主色加深一档）

// —— 2.3 语义色 [A1]（注意：系统 warning 即红系危险，alert 才是橙警告）——
export const HMOS_WARNING: HmosColorPair = { light: '#FA2A2D', dark: '#E64548' };  // ohos_id_color_warning（危险/错误）
export const HMOS_ALERT: HmosColorPair = { light: '#FF7500', dark: '#BA5500' };    // ohos_id_color_alert（橙警告）
// 成功色：系统资源表无 success 语义 token（baseline 2.3 [C] 全表扫描无果，勿编造）——
// 取官方色板充任；深档值为 A1 dark/element/color.json 提取（本会话 sparse clone 实证
// ohos_id_color_palette4 dark = #ff007900）。
export const HMOS_SUCCESS: HmosColorPair = { light: '#47CC47', dark: '#007900' };  // 2.3[C] 缺口 → 2.4 ohos_id_color_palette4

// purple（AGENT tag/发送钮/✦）：baseline 2.4 palette6；深档同为 #8A2BE2（A1 dark
// ohos_id_color_palette6 = #ff8a2be2 实证——非「沿用浅值」的估算，提取登记）。
export const HMOS_PURPLE: HmosColorPair = { light: '#8A2BE2', dark: '#8A2BE2' };   // 2.4 ohos_id_color_palette6

// —— 2.1 文本与中性色 [A1]（层级=同一主色的 alpha：次 60% / 三级 40%）——
export const HMOS_TEXT_PRIMARY: HmosColorPair = { light: '#182431', dark: '#DBFFFFFF' };      // ohos_id_color_text_primary（浅=墨蓝黑非纯黑，深=86% 白非纯白）
export const HMOS_TEXT_SECONDARY: HmosColorPair = { light: '#99182431', dark: '#99FFFFFF' };  // ohos_id_color_text_secondary
export const HMOS_TEXT_TERTIARY: HmosColorPair = { light: '#66182431', dark: '#66FFFFFF' };   // ohos_id_color_text_tertiary / text_hint

// —— 2.5 背景与表面 [A1] ——
export const HMOS_BG_PAGE: HmosColorPair = { light: '#FFFFFF', dark: '#18181A' };           // ohos_id_color_background（页面背景，深=非纯黑）
export const HMOS_BG_SUB: HmosColorPair = { light: '#F1F3F5', dark: '#000000' };            // ohos_id_color_sub_background（次级背景/分区）
export const HMOS_INPUT_BG: HmosColorPair = { light: '#FFFFFF', dark: '#19FFFFFF' };        // ohos_id_color_text_field_bg（输入框背景）
export const HMOS_INPUT_SUB_BG: HmosColorPair = { light: '#0C182431', dark: '#19FFFFFF' };  // ohos_id_color_text_field_sub_bg（输入框次级背景，浅=5% 墨）
export const HMOS_DIALOG_BG: HmosColorPair = { light: '#FFFFFF', dark: '#202224' };         // ohos_id_color_dialog_bg（对话框背景）
export const HMOS_COMPONENT_NORMAL: HmosColorPair = { light: '#19182431', dark: '#19FFFFFF' };  // ohos_id_color_component_normal（普通控件底，10% 主色）

// —— 2.6 蒙层与分隔线 [A1] ——
export const HMOS_SEPARATOR: HmosColorPair = { light: '#33182431', dark: '#33FFFFFF' };    // ohos_id_color_list_separator（列表分隔线）
export const HMOS_MASK_THIN: HmosColorPair = { light: '#33182431', dark: '#66000000' };       // ohos_id_color_mask_thin（蒙层 20%）
export const HMOS_MASK_LIGHT: HmosColorPair = { light: '#66182431', dark: '#99000000' };      // ohos_id_color_mask_light（40%）
export const HMOS_MASK_REGULAR: HmosColorPair = { light: '#99182431', dark: '#B2000000' };    // ohos_id_color_mask_regular（60%）
export const HMOS_MASK_THICK: HmosColorPair = { light: '#CC182431', dark: '#E5000000' };      // ohos_id_color_mask_thick（80%）
export const HMOS_DIALOG_MASK: HmosColorPair = { light: '#33000000', dark: '#66000000' };     // ohos_id_dialog_mask_color_end（对话框蒙层）

// —— 9. 控件质感 [A1]/[A2]：强调底上的前景（font_on_primary，A1 font_on 浅深均 #ffffff）——
export const HMOS_ON_ACCENT: HmosColorPair = { light: '#FFFFFF', dark: '#FFFFFF' };  // baseline 9 文字色默认

// —— 4. 圆角阶梯 [A1]（sys.float.ohos_id_corner_radius_*，vp；离散档位=偶数阶梯）——
export const HMOS_RADIUS_XS: number = 4;             // corner_radius_default_xs（checkbox/subtab/mark）
export const HMOS_RADIUS_S: number = 12;             // corner_radius_default_s（grid）
export const HMOS_RADIUS_M: number = 18;             // corner_radius_default_m（banner）
export const HMOS_RADIUS_L: number = 24;             // corner_radius_default_l
export const HMOS_RADIUS_XL: number = 36;            // corner_radius_default_xl
export const HMOS_RADIUS_CARD: number = 24;          // corner_radius_card（卡片）
export const HMOS_RADIUS_DIALOG: number = 24;        // corner_radius_dialog（对话框）
export const HMOS_RADIUS_PANEL: number = 32;         // corner_radius_panel（面板/半模态）
export const HMOS_RADIUS_MENU: number = 20;          // corner_radius_menu（菜单）
export const HMOS_RADIUS_BUTTON: number = 20;        // corner_radius_button / ohos_id_button_corner_radius
export const HMOS_RADIUS_TEXT_FIELD: number = 20;    // corner_radius_text_field（输入框）
export const HMOS_RADIUS_CHIP: number = 14;          // corner_radius_small_button/toggle_button/piece（小钮/芯片）
export const HMOS_RADIUS_NOTIFICATION: number = 16;  // corner_radius_notification（通知卡片）
export const HMOS_RADIUS_ICON: number = 8;           // corner_radius_icon（图标底）

// —— 5. 间距体系 [A1]（官方间距全部落在 4 的倍数栅格，vp）——
export const HMOS_SPACE_XS: number = 4;    // ohos_id_elements_margin_horizontal/vertical_s
export const HMOS_SPACE_S: number = 8;     // ohos_id_elements_margin_horizontal/vertical_m
export const HMOS_SPACE_M: number = 12;    // ohos_id_default_padding_start/end/top、card_margin
export const HMOS_SPACE_L: number = 16;    // ohos_id_elements_margin_horizontal/vertical_l、dialog bottom
export const HMOS_SPACE_XL: number = 24;   // ohos_id_max_padding_start/end、default_padding_bottom_fixed

// —— 6. 阴影与层级 [A1]（radius 即 blur；颜色锚点=A1 ohos_id_checkbox/switch_shadow_color
//      #0c000000=5% 黑，本会话 dark/element/color.json 同值实证）——
export const HMOS_SHADOW_SM: HmosShadow = { radius: 40, dx: 0, dy: 10 };   // ohos_id_shadow_default_sm
export const HMOS_SHADOW_MD: HmosShadow = { radius: 60, dx: 0, dy: 10 };   // ohos_id_shadow_default_md
export const HMOS_SHADOW_LG: HmosShadow = { radius: 100, dx: 0, dy: 20 };  // ohos_id_shadow_default_lg
export const HMOS_SHADOW_COLOR: string = '#0C000000';                      // 阴影色锚点（5% 黑）

// —— 3. 字体 [A1]/[A2]（fp 随系统字号缩放；HarmonyOS Sans 系统默认，不指定 fontFamily 即用）——
export const HMOS_FONT_BODY_L: number = 16;            // ohos_id_text_size_body1
export const HMOS_FONT_BODY_M: number = 14;            // ohos_id_text_size_body2
export const HMOS_FONT_BODY_S: number = 12;            // ohos_id_text_size_body3
export const HMOS_FONT_BUTTON: number = 16;            // ohos_id_button_font_size
export const HMOS_FONT_DIALOG_TITLE: number = 20;      // ohos_id_text_size_dialog_tittle
export const HMOS_FONT_WEIGHT_CONTROL: number = 500;   // 控件字重默认 Medium（ts-basic-components-button fontWeight 默认值 [A2]）

// —— 按压态原子（batch-4，iss-5）——
// A 缩放式 pressed scale：对齐桌面 .pchip:active scale(.96)（i:247）/.czoom button:active
// scale(.94)（i:205）——两档取 0.96 统一（登记取舍：芯片/图标钮/段钮/菜单行共用一档）。
// B 底色叠加式：鸿蒙机制=在最终背景色上叠加按压色（baseline §9 stateEffect）；acc 实底钮
// 按压色走 ThemeColors.accTx（HMOS=ohos_id_color_floating_button_bg_pressed #0070E5/#1A7AE1
// 实证条目），中性行按压底走 ThemeColors.pressFill（subtle 提一档）。
export const HMOS_PRESS_SCALE: number = 0.96;

// ===== 断点两档字号/控件尺寸层（batch-1 断点，r9-sweep §3.3）=====
// 口径：两档离散映射（非连续函数——字号即布局度量，§3.3 要点 1），拾取门复用
// Index.ets isNarrowBar() 两态门（topW<1200 视为窄窗；topW 源 :5784-5789 顶栏横贯全窗
// 实测宽，topW=0 首帧按宽窗防闪折），不新造第三档。
// 与主题色正交：12 张主题表（THEME_MAC_L :191 至 THEME_HMOS_D :792）不扩字段——
// wide 档=全部主题现 inline 值（零漂移），非窄窗渲染逐像素不变。
// 禁入（§3.3 要点 5 + AGENTS.md「画布显示≠UI」纪律，本层永不接线）：画布数据
// fontSize(l.style.fontSize)×3（Index.ets :3960/:3986/:3998，input/btn/text 三类）、
// ≥16 图标/徽标字号 6 处（视觉锚点不随窗缩）、fDialogTitle 弹层标题 3 处（§3 已对齐档）。
// 消费：Index.ets fp()/sd() 拾取器——fp 首站点=batch-2 ddMenuRow 菜单行
//（HMOS_F_MENU_ROW）；sd 零消费（fBtnPrimary 接线待后续批次）。行号为 batch-2 收编
// 后位次，后续批次插入会整体下移（坐标逐构建漂移，以 grep 锚为准）。

/** 窄/宽两档尺寸对（r9-sweep §3.3 两档离散口径；门=Index.ets isNarrowBar topW<1200）。 */
export interface HmosSizePair {
  narrow: number;
  wide: number;
}

// —— 字号族（wide=现 inline 值零漂移；narrow 按降档规则：整数 −1 / 半整数 −1；
//      8.5/9.5 两小档贴地取整不下穿 0.5 步进——值以本清单为准）——
export const HMOS_F_MENU_ROW: HmosSizePair = { narrow: 10.5, wide: 11.5 };    // 菜单行/下拉收编共用（§3.2 menuRow）
export const F_DOCK_QUICK: HmosSizePair = { narrow: 9.5, wide: 10.5 };        // dock 快捷区文字
export const F_DOCK_CHIP: HmosSizePair = { narrow: 11, wide: 12 };            // pchip/行内 chips（§3.3 fDockChip 12↔11）
export const F_DOCK_ICON: HmosSizePair = { narrow: 13, wide: 14 };            // dock 图标字形
export const F_DOCK_INPUT: HmosSizePair = { narrow: 12, wide: 13 };           // pmain 指令条（§3.3 fDockInput 13↔12）；M3.6.9 缩放改由组件级 transform 承担（勿在此降档）
export const F_KBD: HmosSizePair = { narrow: 9, wide: 10 };                   // kbd 键帽
export const F_DOCK_HINT: HmosSizePair = { narrow: 9, wide: 10 };             // dock 提示行
export const F_AGENTMSG: HmosSizePair = { narrow: 10, wide: 11 };             // 行内 Agent 消息
export const F_CLARIFY_HEAD: HmosSizePair = { narrow: 10, wide: 11 };         // 澄清浮层标题
export const F_CLARIFY_INPUT: HmosSizePair = { narrow: 11, wide: 12 };        // 澄清回答输入框
export const F_TRACK_HEAD: HmosSizePair = { narrow: 10.5, wide: 11.5 };       // 留痕卡头行（§3.3 fTrackHead）
export const F_TRACK_BODY: HmosSizePair = { narrow: 9.5, wide: 10.5 };        // 留痕卡正文/op 行
export const F_TRACK_MID: HmosSizePair = { narrow: 9, wide: 10 };             // 留痕卡中档（复审修正新增：
                                                                              //  供现值 10 的站点专用——防误挂
                                                                              //  10.5↔9.5 / 9↔8 族致 wide 漂移）
export const F_TRACK_DETAIL: HmosSizePair = { narrow: 8, wide: 9 };           // 留痕卡细节行
export const F_TRACK_MS: HmosSizePair = { narrow: 8, wide: 8.5 };             // 留痕卡耗时 ms 角标（贴地取整）
export const F_TRACK_FINAL: HmosSizePair = { narrow: 12.5, wide: 13.5 };      // tl-final 收尾主行
export const F_TRACK_FINAL_SUB: HmosSizePair = { narrow: 9, wide: 9.5 };      // tl-final 副行（贴地取整）
export const F_TOOLBAR: HmosSizePair = { narrow: 11.5, wide: 12.5 };          // 顶栏工具行 modeSeg/opsGroup（§3.3 fToolLabel）
export const F_TOOLBAR_BADGE: HmosSizePair = { narrow: 10, wide: 11 };        // 顶栏小艺徽章
export const F_PROJNAME: HmosSizePair = { narrow: 11, wide: 12 };             // 顶栏项目名
export const F_PROJNAME_L: HmosSizePair = { narrow: 11.5, wide: 12.5 };       // 左栏项目区大字（§3.2 :5636）

// —— 尺寸族（与字号降档联动同改防「小字大框」，§3.3 要点 3；按列值，不套字号降档规则）——
export const HMOS_H_CHIP: HmosSizePair = { narrow: 27, wide: 30 };     // pchip 高（§3.3 chip h30→27）
export const PAD_CHIP: HmosSizePair = { narrow: 11, wide: 13 };        // pchip/发送钮水平 padding
export const H_DOCK_INPUT: HmosSizePair = { narrow: 30, wide: 34 };    // pmain 指令条高（§3.3 pmain h34→30）；缩放由组件 transform 承担
export const H_CLARIFY: HmosSizePair = { narrow: 28, wide: 32 };       // 澄清回答框/发送钮高
export const PAD_TRACK_CARD_H: HmosSizePair = { narrow: 8, wide: 11 };   // tlCard 水平 padding（§3.2 11×2）
export const PAD_TRACK_CARD_V: HmosSizePair = { narrow: 7, wide: 9 };    // tlCard 垂直 padding
export const PAD_TRACK_FINAL_H: HmosSizePair = { narrow: 12, wide: 16 }; // tlFinal 水平 padding
export const PAD_TRACK_FINAL_V: HmosSizePair = { narrow: 10, wide: 13 }; // tlFinal 垂直 padding（§3.3 13→10）

// —— 主题变量字号离散降档（仅 fBtnPrimary 一键生成钮：HMOS 16→14 / 桌面 13→12，
//      §3.3 要点 3——16 是「控件默认」档，窄窗降档与 baseline 不冲突；
//      Index.ets ThemeColors.fBtnPrimary 字段注释 + THEME_HMOS_L/D 两表
//      HMOS_FONT_BUTTON 值匹配）——
export function hmosStepDown(v: number): number {
  return v >= 15 ? v - 2 : v - 1;
}

// ===== 顶栏族（batch-1 r10 收编：sz-topbar-2/3 + h-topbar-1/2/3 + h-tbtn-1，r10-sweep §二/§四）=====
// 站点锚=Index.ets（r10-sweep 基线行号：filechip :4584/:4586、↧ :4673、壳 :5906/:5914/:5935、
// 药丸 :4601/:4663/:4670/:4675、图标钮 :4707；前批插入会整体漂移——以 sweep 行片段 grep 锚为准）。
// wide 档=现 inline 值（宽窗零漂移不变量），narrow 档命中 isNarrowBar()（topW<1200）；
// 箭头 ▾ 8 两处（:4577/:4669）保底不缩放（两态同值，不接 token）。
export const F_FILECHIP: HmosSizePair = { narrow: 9.5, wide: 10.5 };    // 顶栏路径 chip 文字（sz-topbar-2）
export const F_TOOLBAR_GLYPH: HmosSizePair = { narrow: 11, wide: 12 };  // opsGroup ↧ 导出 DDP 字形（sz-topbar-3）
export const H_TOPBAR: HmosSizePair = { narrow: 40, wide: 46 };         // 顶栏壳高 ×3（宽窗行/modeSeg overlay/窄窗行，h-topbar-1）
export const H_FILECHIP: HmosSizePair = { narrow: 20, wide: 22 };       // 路径 chip 高（h-topbar-2）
export const H_PILL: HmosSizePair = { narrow: 25, wide: 28 };           // 顶栏药丸 ×4 + 28×28 图标钮高（h-topbar-3 + h-tbtn-1，同形 28→25 共用）
export const T_ICON_TBTN: HmosSizePair = { narrow: 14, wide: 15 };      // 顶栏 tbtn 类 SVG 图标边长（spec-icon-1 .ic 15×15，r11：
                                                                        // wide=15 用户点名修正——登记打破 wide=现值零漂移不变量；
                                                                        // narrow=14=tbtn 前值；演示三角同族消费，旧 13 恒值退役）

// ===== 微控件阴影 token（batch-1 r10 §五：r7 搁置项清账）=====
// 层级线索非布局度量——不随窗断点缩放（两态同值）。几何=HmosShadow{radius,dx,dy}；
// 颜色不进 token——消费点从主题表取色：.shadow({ radius: T.radius, offsetX: T.dx,
// offsetY: T.dy, color: this.T().shadowMd })（ArkTS 禁对象展开，逐字段显式）。
export const SH_SEG_SELECTED: HmosShadow = { radius: 3, dx: 0, dy: 1 };  // modeSeg 选中态（色已走 T().shadowMd）
// [退役 M3.6.2] SH_LOGO：顶栏品牌块拆除（fe492f5）后无消费方——保留导出防破坏外部引用，勿再使用
export const SH_LOGO: HmosShadow = { radius: 4, dx: 0, dy: 1 };

// ===== 画布周边族（batch-2 r10 收编：sz-ctools-1/sz-czoom-1/sz-tpl-1/sz-welcome-1/
//      sz-welcome-2/sz-ia-1/sz-tail-1/sz-dock-1，r10-sweep §二；wide=现 inline 值零漂移）=====
export const F_TOOLROW: HmosSizePair = { narrow: 10.5, wide: 11.5 };     // toolBtn 图标/label + 缩放百分比读数（复用）
export const F_TOOLROW_FIT: HmosSizePair = { narrow: 10, wide: 11 };     // ⤢ 适配（11→10——sweep 单名 F_TOOLROW 盖不住，拆分登记）
export const F_ZOOM_GLYPH: HmosSizePair = { narrow: 12, wide: 13 };      // 缩放条 −/＋
export const F_ZOOM: HmosSizePair = { narrow: 9.5, wide: 10.5 };         // 缩放条 1:1
export const F_TPL: HmosSizePair = { narrow: 10.5, wide: 11.5 };         // 模板卡名
export const F_TPL_META: HmosSizePair = { narrow: 8, wide: 9 };          // 模板卡 meta（kind · 尺寸）
export const F_GHOST: HmosSizePair = { narrow: 10.5, wide: 11.5 };       // ghost 新建画板卡题
export const F_GHOST_DIM: HmosSizePair = { narrow: 8, wide: 9 };         // ghost 卡尺寸行
export const F_IA: HmosSizePair = { narrow: 10, wide: 11 };              // 行内 Agent ✦/输入/↗；缩放由浮层 transform 承担
export const F_IA_HEAD: HmosSizePair = { narrow: 9, wide: 10 };          // 行内 Agent 题
export const F_IA_MINI: HmosSizePair = { narrow: 8, wide: 9 };           // 行内 Agent ✕/上下文行
export const F_IA_CHIP: HmosSizePair = { narrow: 9, wide: 9.5 };         // 行内快捷 chips
export const F_WELCOME_SUB: HmosSizePair = { narrow: 11.5, wide: 12.5 }; // 欢迎副题 ×2
export const F_WELCOME_KBD: HmosSizePair = { narrow: 9.5, wide: 10.5 };  // ⌘K 键帽
export const F_WELCOME_SEC: HmosSizePair = { narrow: 9.5, wide: 10.5 };  // veil 模板分组题（复审拆分：现值 10.5 非 11，原并 F_WELCOME 会宽窗漂移）
export const F_WELCOME: HmosSizePair = { narrow: 10, wide: 11 };         // 欢迎最近项目题/✓列
export const F_WELCOME_NAME: HmosSizePair = { narrow: 11, wide: 12 };    // 浏览全部模板行/最近行名
export const F_WELCOME_TIME: HmosSizePair = { narrow: 8, wide: 9 };      // 最近行相对时间
export const F_TAIL: HmosSizePair = { narrow: 10, wide: 11 };            // 板尾栏 板名/尺寸/rev ×3
export const F_CLARIFY_GLYPH: HmosSizePair = { narrow: 11, wide: 12 };   // 澄清面板 🤔
export const F_CLARIFY_X: HmosSizePair = { narrow: 9, wide: 10 };        // 澄清面板 ✕（↗ 复用 F_CLARIFY_HEAD）

// —— 高度族（batch-2 r10 §四 A 组）——
export const H_TOOLBTN: HmosSizePair = { narrow: 22, wide: 24 };         // 画布工具钮高
export const H_IA: HmosSizePair = { narrow: 25, wide: 28 };              // 行内 Agent 输入/发送钮高
export const H_WELCOME_ROW: HmosSizePair = { narrow: 27, wide: 30 };     // 欢迎最近行高
export const H_TAIL: HmosSizePair = { narrow: 28, wide: 32 };            // 板尾栏高

// —— 微控件阴影（batch-2 r10 §五续：sh-2 收编+取色修正；sh-5 纯搬迁；
//      sh-6 选区光环复审移出不收——shadowMd 固定 10% 黑不随 acc，映射致选区强调 cue 语义损失）——
export const SH_TOOL_SELECTED: HmosShadow = { radius: 4, dx: 0, dy: 1 }; // toolBtn 选中态（取色 rgba(0,122,255,0.4) 硬编码→T().shadowMd，行为修正）
export const SH_PMAIN_FOCUS: HmosShadow = { radius: 2, dx: 0, dy: 1 };   // pmain 指令条聚焦微影（色已走 T().shsm，纯搬迁）

// ===== 左栏族（batch-3 r10 收编：sz-compcell-1/sz-layer-1/sz-lproj-1~4/sz-ltab-1/
//      sz-lboard-1/2/sz-lsearch-1/sz-lcomp-1/2/sz-lflow-1/2/sz-lhint-1/sz-lstatus-1，
//      r10-sweep §二；wide=现 inline 值零漂移）=====
export const F_COMPCELL: HmosSizePair = { narrow: 9, wide: 10 };         // AI 组件格 id
export const F_COMPCELL_SUB: HmosSizePair = { narrow: 8, wide: 8.5 };    // 组件格尺寸行
export const F_LAYER: HmosSizePair = { narrow: 10, wide: 11 };           // 图层行 icon/类型
export const F_LAYER_NAME: HmosSizePair = { narrow: 11, wide: 12 };      // 图层行名
export const F_LAYER_X: HmosSizePair = { narrow: 9, wide: 10 };          // 图层行 ✕
export const F_LPROJ_ARROW: HmosSizePair = { narrow: 9, wide: 10 };      // 左栏项目区 ▾
export const F_LBTN: HmosSizePair = { narrow: 10.5, wide: 11.5 };        // ＋新建/打开…/画板→组件/导入MCF ×4
export const F_LSEC_MINI: HmosSizePair = { narrow: 8, wide: 8.5 };       // 最近列表折叠头 ▸▾
export const F_LRECENT_HEAD: HmosSizePair = { narrow: 9, wide: 9.5 };    // 最近项目（N）头（sweep 名 F_LSEC 与 lboard/lflow 撞名，消歧改名）
export const F_LRECENT_CHECK: HmosSizePair = { narrow: 9, wide: 10 };    // 最近行 ✓列（sweep 单名盖不住 10→9，拆分）
export const F_LRECENT: HmosSizePair = { narrow: 10, wide: 11 };         // 最近行名
export const F_LTAB: HmosSizePair = { narrow: 11, wide: 12 };            // 左栏三 tab
export const F_LSEC: HmosSizePair = { narrow: 9, wide: 10 };             // 分区头/计数（画布页面/图层/交互流/Story ×7）
export const F_LBOARD: HmosSizePair = { narrow: 11, wide: 12 };          // 画板行板名
export const F_LBOARD_MINI: HmosSizePair = { narrow: 8, wide: 8.5 };     // 画板行 ⛓徽章/当前
export const F_LBOARD_DIM: HmosSizePair = { narrow: 9, wide: 9.5 };      // 画板行尺寸
export const F_LBOARD_X: HmosSizePair = { narrow: 8, wide: 9 };          // 画板行 ✕
export const F_LEMPTY: HmosSizePair = { narrow: 10, wide: 11 };          // 画板/图层/组件空态 ×4
export const F_LSEARCH: HmosSizePair = { narrow: 11, wide: 12 };         // 左栏搜索框
export const F_INSP_LABEL: HmosSizePair = { narrow: 9.5, wide: 10.5 };   // 组件区说明钮/三步（batch-4 检视 label 复用同档）
export const F_LCOMP_NOTE: HmosSizePair = { narrow: 9, wide: 9.5 };      // 组件区注释行 ×3
export const F_LCOMP_HOW: HmosSizePair = { narrow: 10, wide: 11 };       // 「如何自定义组件」注
export const F_LCOMP_MINI: HmosSizePair = { narrow: 8, wide: 9 };        // 组件组行 ▸▾
export const F_LCOMP_CAT: HmosSizePair = { narrow: 10, wide: 11 };       // 组件组行组名
export const F_LCOMP_COUNT: HmosSizePair = { narrow: 9, wide: 10 };      // 组件组行计数（实际 10→9，拆分）
export const F_LFLOW: HmosSizePair = { narrow: 10, wide: 11 };           // 流程行/空态/Story ×7
export const F_LFLOW_ID: HmosSizePair = { narrow: 9.5, wide: 10.5 };     // 流程行 ⛓/id
export const F_LHINT: HmosSizePair = { narrow: 9.5, wide: 10.5 };        // 右栏折叠空态题
export const F_LHINT_SUB: HmosSizePair = { narrow: 9, wide: 10 };        // 右栏折叠空态副文
export const F_LSTATUS: HmosSizePair = { narrow: 9.5, wide: 10.5 };      // 左栏状态行 ×2

// —— lineHeight 联动（batch-3 复审修订：F_LEMPTY 四站点下行距，11→10 字号下 20→18
//      保持 ~1.82 比例，与 LH_DECL 同策；类型沿用 HmosSizePair，拾取走 fp()）——
export const LH_LEMPTY: HmosSizePair = { narrow: 18, wide: 20 };

// —— 高度族（batch-3 r10 §四 A 组）——
export const H_LBTN: HmosSizePair = { narrow: 25, wide: 28 };            // ＋新建/打开…/画板→组件/导入MCF ×4
export const H_LRECENT_ROW: HmosSizePair = { narrow: 23, wide: 26 };     // 左栏最近行高
export const H_LTAB: HmosSizePair = { narrow: 33, wide: 37 };            // 左栏三 tab 高
export const H_LBOARD_ROW: HmosSizePair = { narrow: 25, wide: 28 };      // 画板行高
export const H_LSEARCH: HmosSizePair = { narrow: 27, wide: 30 };         // 左栏搜索框高（与 F_LSEARCH 同行联动）
export const H_LAYER_ROW: HmosSizePair = { narrow: 24, wide: 27 };       // 图层行高

// ===== 右栏检视族（batch-4 r10 收编：sz-empty-1/sz-insp-1/2/sz-bind-1（补挂 :5745）/
//      sz-decl-1/sz-rcons-1/sz-rbottom-1/sz-rtrack-1/sz-rstatus-1/sz-rtab-1/sz-track-1/
//      sz-track-2，r10-sweep §二；wide=现 inline 值零漂移；复用 batch-3 F_INSP_LABEL 与
//      断点层既有 F_TRACK_DETAIL/F_TRACK_MS）=====
export const F_EMPTY_HEAD: HmosSizePair = { narrow: 11.5, wide: 12.5 };  // 右栏空态卡题
export const F_EMPTY_DESC: HmosSizePair = { narrow: 10, wide: 11 };      // 空态描述
export const F_EMPTY_HINT: HmosSizePair = { narrow: 9.5, wide: 10.5 };   // 空态快捷提示 ×2
export const F_EMPTY_KBD: HmosSizePair = { narrow: 9, wide: 9.5 };       // 空态 kbd ×2
export const F_SEGCHIP: HmosSizePair = { narrow: 8, wide: 9 };           // 阴影档预览 chip 字
export const F_INSP_INPUT: HmosSizePair = { narrow: 10.5, wide: 11.5 };  // 检视草稿输入 ×4 + 约束值
export const F_INSP_HEAD: HmosSizePair = { narrow: 11.5, wide: 12.5 };   // 交互绑定/状态 段题 ×2
export const F_INSP_MINI: HmosSizePair = { narrow: 9, wide: 9.5 };       // 触发/动作/目标/文案 行标 ×4
export const F_INSP_VAL: HmosSizePair = { narrow: 9.5, wide: 10.5 };     // 绑定值/输入/＋添加绑定 ×5（:5745 复审补挂）
export const F_INSP_ACT: HmosSizePair = { narrow: 9, wide: 10 };         // 动作项/绑定行动作/＋定义 ×3
export const F_DECL_HEAD: HmosSizePair = { narrow: 13, wide: 14 };       // MBT 源码题
export const F_DECL: HmosSizePair = { narrow: 10.5, wide: 11.5 };        // 复制/重序列化/正文 ×3
export const F_DECL_GLYPH: HmosSizePair = { narrow: 10, wide: 11 };      // ↻ 字形
export const F_INSP_MONO_MINI: HmosSizePair = { narrow: 8, wide: 9 };    // 约束 mono 小字 ×3
export const F_INSP_MONO: HmosSizePair = { narrow: 11, wide: 12 };       // 约束 mono 主字
export const F_RBTN: HmosSizePair = { narrow: 10, wide: 11 };            // 删除元素钮
export const F_RBTN_ACC: HmosSizePair = { narrow: 11, wide: 12 };        // 应用到中间态钮
export const F_RTRACK_HEAD: HmosSizePair = { narrow: 10, wide: 11 };     // 留痕头题
export const F_RTRACK_CLR: HmosSizePair = { narrow: 9.5, wide: 10.5 };   // 清空
export const F_RSTATUS_MINI: HmosSizePair = { narrow: 8, wide: 8.5 };    // 状态条 READY 徽章
export const F_RSTATUS: HmosSizePair = { narrow: 9.5, wide: 10.5 };      // 状态条消息/coreTag ×2
export const F_TRACK_SRC: HmosSizePair = { narrow: 8, wide: 9 };         // 留痕卡源 tag
export const F_TRACK_FINAL_GLYPH: HmosSizePair = { narrow: 13, wide: 14 }; // 收尾胶囊 ✔
export const F_RTAB: HmosSizePair = { narrow: 11.5, wide: 12.5 };        // 右栏 tab

// —— lineHeight 联动（batch-4：MBT 正文 11.5→10.5 下 19→17 保持 ~1.65 比例，gap-mbt-9）——
export const LH_DECL: HmosSizePair = { narrow: 17, wide: 19 };

// —— 高度族（batch-4 r10 §四 A 组；:5580-5582 阴影档预览 chip 半径 3/9/16 属预览数据不改）——
export const H_SEG: HmosSizePair = { narrow: 23, wide: 26 };             // 检视段钮高
export const H_SHADOW_ROW: HmosSizePair = { narrow: 36, wide: 40 };      // 阴影档预览行高
export const H_DRAFT_INPUT: HmosSizePair = { narrow: 24, wide: 27 };     // 草稿输入高 ×4（与 F_INSP_INPUT 同行联动）
export const H_BIND_CHIP: HmosSizePair = { narrow: 21, wide: 24 };       // 绑定胶囊/输入高 ×4
export const H_BIND_ROW: HmosSizePair = { narrow: 20, wide: 22 };        // 绑定行/约束行高 ×2
export const H_DECL_BTN: HmosSizePair = { narrow: 23, wide: 26 };        // 重新序列化钮高
export const H_RBTN: HmosSizePair = { narrow: 26, wide: 29 };            // 删除元素钮高
export const H_RBTN_ACC: HmosSizePair = { narrow: 27, wide: 31 };        // 应用到中间态钮高
export const H_RSTATUS: HmosSizePair = { narrow: 24, wide: 27 };         // 右栏状态条高
export const H_RTAB: HmosSizePair = { narrow: 33, wide: 37 };            // 右栏 tab 高

// ===== 菜单与覆盖层族（batch-5 r10 收编：sz-menurow-1/2/sz-ddmenu-1/sz-toast-1/
//      sz-demo-1/sz-recentmenu-1，r10-sweep §二；wide=现 inline 值零漂移；
//      右键菜单 label 复用断点层既有 HMOS_F_MENU_ROW）=====
export const F_MENU_KBD: HmosSizePair = { narrow: 8, wide: 9 };          // kbd 键帽（menuRow/ddMenuRow 共用）
export const F_MENU_TITLE: HmosSizePair = { narrow: 9.5, wide: 10.5 };   // 菜单分组题
export const F_DD_CHECK: HmosSizePair = { narrow: 10, wide: 11 };        // 下拉行 ✓列
export const F_TOAST: HmosSizePair = { narrow: 11, wide: 12 };           // 全局 toast（主渲染位）
export const F_DEMO_TITLE: HmosSizePair = { narrow: 13, wide: 14 };      // 演示「该画板已删除」题
export const F_DEMO_HEAD: HmosSizePair = { narrow: 11, wide: 12 };       // 演示题/◀/模层 toast 副本 ×3
export const F_DEMO: HmosSizePair = { narrow: 10, wide: 11 };            // 演示 HUD 钮 ×6
export const F_DEMO_HINT: HmosSizePair = { narrow: 9, wide: 10 };        // 绿框提示行
export const F_RMENU_HEAD: HmosSizePair = { narrow: 9, wide: 9.5 };      // 最近项目菜单题
export const F_RMENU: HmosSizePair = { narrow: 10, wide: 11 };           // 菜单空态/✓列 ×2
export const F_RMENU_NAME: HmosSizePair = { narrow: 11, wide: 12 };      // 菜单行名
export const F_RMENU_TIME: HmosSizePair = { narrow: 8, wide: 9 };        // 菜单行相对时间

// —— 高度族（batch-5 r10 §四 A 组；与 HMOS_F_MENU_ROW 联动防小字大框）——
export const H_MENU_ROW: HmosSizePair = { narrow: 24, wide: 26 };        // 右键菜单行/下拉行高 ×2
export const H_RMENU_ROW: HmosSizePair = { narrow: 27, wide: 30 };       // 最近项目菜单行高

// ===== 弹层族（batch-6 r10 收编：sz-export-1/sz-pwd-1/sz-recover-1/sz-settings-1~7/
//      sz-stab-1，r10-sweep §二；wide=现 inline 值零漂移；fDialogTitle 弹层题 3 处
//      与 ≥16 图标仍禁入——Theme.ets 断点层头注）=====
export const F_MODAL_OPT: HmosSizePair = { narrow: 12, wide: 13 };       // 弹层选项钮/取消/上一步/导出/解锁/丢弃/恢复/口令输入 ×11
export const F_MODAL_DESC: HmosSizePair = { narrow: 10, wide: 11 };      // 导出选项描述 ×2
export const F_MODAL_SUB: HmosSizePair = { narrow: 10.5, wide: 11.5 };   // 密码说明/恢复描述 ×2（sweep 未列 11.5 档，补枚防误挂 F_MODAL_DESC）
export const F_MODAL_BTN: HmosSizePair = { narrow: 11, wide: 12 };       // ↧ 导出行字形 ×1（r12 fix-aitab-6：设置取消迁 F_SET_BTN 12/500）
export const F_PWD_SUB: HmosSizePair = { narrow: 9.5, wide: 10.5 };      // 口令项目名
export const F_PWD_TRIES: HmosSizePair = { narrow: 9, wide: 9.5 };       // 口令次数行
export const F_SET_CLOSE: HmosSizePair = { narrow: 20, wide: 22 };       // 设置 ✕（r12 fix-aitab-6：桌面 i:455 .icon-close 22px——wide=22 桌面值、narrow=20 断点降档，旧 14/13 退役）
export const F_SET_HEAD: HmosSizePair = { narrow: 12, wide: 13 };        // 设置分区题 ×6（r12 fix-aitab-1：AI tab 三题「AI 服务商/思考等级/步数上限」退出本档——桌面无 12px 深色分区题，降格 11px 字段标签 F_SET_LABEL；仅外观 tab 消费）
export const F_SET_VAL: HmosSizePair = { narrow: 10, wide: 11 };         // 主题 chip/引擎/DDP 行值 ×3（r12：provider 值→F_SET_SELECT、获取模型→F_SET_LABEL）
export const F_SET_MINI: HmosSizePair = { narrow: 9.5, wide: 10.5 };     // 深浅 chips ×1（r12 fix-aitab-1：AI tab 顶部说明行升 11px F_SET_LABEL；小艺档说明迁 F_SET_SEC）
// —— r12 AI tab 桌面单值档（fix-aitab-1~5：桌面 i:454-472/1133-1186 无窄/宽断点，
//      全部两态同值；10.5/11/11.5/12/12.5 五档与桌面 CSS 逐条对齐）——
export const F_SET_SEC: HmosSizePair = { narrow: 10.5, wide: 10.5 };     // 分区小题/hint 档（i:469 .settings-sec 10.5px/700/tx3 字距 .07em；#agent-model-hint 10.5/tx3 i:463、思考 hint :1175）
export const F_SET_LABEL: HmosSizePair = { narrow: 11, wide: 11 };       // 11px 档：字段标签/说明段/框下注行/获取模型钮（i:466 label 11px/tx2、i:455 note 11px、i:1161 获取模型 inline font-size:11px/500）
export const F_SET_MONO_URL: HmosSizePair = { narrow: 11.5, wide: 11.5 };// Base URL/Model ID 输入+模型触发值（i:466 #agent-base-url,#agent-model 11.5px ui-monospace）
export const F_SET_MONO_VAL: HmosSizePair = { narrow: 12, wide: 12 };    // API Token 输入/思考/步数触发值（i:466 .settings-grid input,select 基准 font 12px ui-monospace）
export const F_SET_SELECT: HmosSizePair = { narrow: 12.5, wide: 12.5 };  // 服务商预设 select 行（i:114 .settings-select font-size:12.5px）
export const F_SET_BTN: HmosSizePair = { narrow: 12, wide: 12 };         // 设置动作钮 取消/保存设置（i:75 .tbtn font-size:12px/weight 500）
export const F_SET_TAG: HmosSizePair = { narrow: 8, wide: 9 };           // coreTag
export const F_SET_KBD: HmosSizePair = { narrow: 9, wide: 10 };          // 快捷键两列 ×2
export const F_STAB: HmosSizePair = { narrow: 11, wide: 12 };            // 设置 sheet tab
// —— r12 退役登记（fix-aitab-1/2/5/6，旧两档 token 消费点已迁移；照 r11 先例显性
//      登记打破零漂移不变量）：
//   F_SET_INPUT {10.5,11.5} → F_SET_MONO_URL（URL/Model 11.5 mono）/ F_SET_MONO_VAL（Token/思考/步数 12 mono）
//   F_SET_NOTE {9,10} → F_SET_LABEL（11px 框下注行）/ F_SET_SEC（10.5px hint/小艺条件注行）
//   F_SET_DONE {11,12} / F_SET_DONE_L {12,13} → 底部「⚡完成」钮删除（fix-aitab-6，桌面无此钮）
//   H_SET_INPUT {30,34} → H_SET_FIELD {32,32}（fix-aitab-2 桌面 h32 单值）
//   H_SET_CTRL {27,30} → H_SET_BTN {28,28}（fix-aitab-6 .tbtn h28）
//   H_SET_PILL {21,24} → provider 右置药丸退役，改全宽 select 行（fix-aitab-3）
//   G_SET_ROWS {9,11} / G_SET_SECT {10,12} → G_SET_FIELD {5,5} / G_SET_BLOCK {12,12}
//     （fix-aitab-5 标签块 5/块间 12 节奏，桌面相邻框节距 15+5+32+12=64px）

// —— 高度族（batch-6 r10 §四 A 组；r12 fix-aitab-2/3/5/6：设置 AI 面板字段框/动作钮迁
//      桌面单值档，旧 H_SET_INPUT/H_SET_CTRL/H_SET_PILL/G_SET_ROWS/G_SET_SECT 退役，
//      迁移去向见上方字体族退役注）——
export const H_EXPORT_OPT: HmosSizePair = { narrow: 28, wide: 32 };      // 导出选项钮高
export const H_PWD_INPUT: HmosSizePair = { narrow: 32, wide: 36 };       // 口令输入高 ×2（与 F_MODAL_OPT 同行联动）
export const H_DLG_BTN: HmosSizePair = { narrow: 30, wide: 34 };         // 弹层主按钮高 ×6（r12 fix-aitab-6：设置「完成」钮删除）
export const H_SET_FIELD: HmosSizePair = { narrow: 32, wide: 32 };       // 设置字段框/select/触发行高（i:466 .settings-grid input,select h32；.settings-select h≈32 取 32）
export const H_SET_BTN: HmosSizePair = { narrow: 28, wide: 28 };         // 获取模型/取消/保存设置钮高（i:75 .tbtn h28）
export const G_SET_FIELD: HmosSizePair = { narrow: 5, wide: 5 };         // 字段块内 标签↔框 距（i:466 label gap 5）
export const G_SET_BLOCK: HmosSizePair = { narrow: 12, wide: 12 };       // 字段块间/分区间距（i:466 .settings-grid gap 12；sec→note 2+10、note→grid 16 由容器 12±margin 承担）
export const H_STAB: HmosSizePair = { narrow: 27, wide: 30 };            // 设置 sheet tab 高
