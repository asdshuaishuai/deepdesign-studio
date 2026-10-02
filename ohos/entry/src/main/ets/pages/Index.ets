// deepDesign Studio —— 鸿蒙原生交互层（纯 ArkUI）
// 布局与视觉 1:1 复刻通用版 frontend/index.html：
//   topbar 46 / left 252 / right 360 / statusbar 27，
//   设计 token（色值/字号/圆角/阴影/间距）逐条对应原版 CSS。
// Agent 默认执行者 = 端侧小艺（AgentService → localChatModel）。

import { coreVersion, ddpEncrypt, ddpDecrypt } from '../core/CoreBridge';
import { appStore, Board, LayerNode, TlEntry, TplDef, TPLS, TplSize, TPL_FEATURED, TPL_GROUPS } from '../model/AppStore';
import { agentService } from '../ai/AgentService';

// ===== 设计 token（对应原版 :root 与组件 CSS）=====
const BASE = '#f2f3f7';
const PANEL_S = 'rgba(255,255,255,0.92)';     // 侧栏半透明
const PANEL_T = 'rgba(255,255,255,0.85)';     // 顶栏毛玻璃底
const TX = '#1c1c1e';
const TX2 = '#636366';
const TX3 = '#686873';
const ACC = '#007aff';
const ACCTX = '#0066d6';
const PURPLE = '#9d4edd';
const OK = '#28a745';
const BD = 'rgba(0,0,0,0.08)';
const SHSM = 'rgba(0,0,0,0.05)';

@Entry
@Component
struct Index {
  @State coreTag: string = '';
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
    this.sync();
    this.projName = appStore.projectName;
    agentService.probe().then((ok: boolean): void => {
      this.xiaoyiState = ok ? '小艺 · 就绪' : '小艺 · 不可用（本地兜底）';
    });
  }

  private sync(): void {
    this.boards = appStore.boards.slice();
    this.timeline = appStore.timeline.slice();
    this.dirty = appStore.dirty;
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
    const b = appStore.addBoard(tid, def.name, def.kind, 'TEMPLATE');
    this.sync();
    this.selBoard = b.id;
    this.selLayer = '';
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
    this.busy = true;
    this.agentMsg = '';
    const mbt = `画板 ${this.boards.length} 个；当前 ${this.curBoard()?.name ?? '无'}`;
    agentService.run(t, mbt,
      (tid: string): boolean => { this.addTpl(tid); return true; },
      (text: string): boolean => {
        const b = this.curBoard();
        const l = b?.layers.find((x: LayerNode): boolean => /title|welcome/.test(x.name));
        if (!b || !l) return false;
        appStore.setStyle(b.id, l.id, 'text', text.replace(/^小艺[:：]?\s*/, ''));
        this.sync();
        return true;
      },
      (color: string): boolean => {
        const b = this.curBoard();
        const l = b?.layers.find((x: LayerNode): boolean => /title|welcome/.test(x.name));
        if (!b || !l) return false;
        appStore.setStyle(b.id, l.id, 'color', color);
        this.sync();
        return true;
      }
    ).then((r) => {
      this.agentMsg = r.reply;
      this.sync();
      this.busy = false;
    });
    this.prompt = '';
  }

  // ===== 画布元素（按 style 精确渲染）=====
  @Builder
  elNode(b: Board, l: LayerNode) {
    Stack() {
      if (l.type === 'input') {
        Row() {
          Text(l.style.text).fontSize(l.style.fontSize * 0.92).fontColor(l.style.color).maxLines(1)
        }.width('100%').height('100%').padding({ left: 9 })
        .backgroundColor('#ffffff').borderRadius(l.style.radius)
        .border({ width: 1, color: 'rgba(0,0,0,0.14)' })
      } else if (l.type === 'btn') {
        Row() {
          Text(l.style.text).fontSize(l.style.fontSize).fontColor(l.style.color).maxLines(1)
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor(l.style.fill).borderRadius(l.style.radius)
      } else if (l.type === 'text') {
        Row() {
          Text(l.style.text).fontSize(l.style.fontSize).fontColor(l.style.color)
            .fontWeight(l.style.bold ? 700 : 400).maxLines(2).lineHeight(l.style.fontSize * 1.35)
        }.width('100%').justifyContent(l.style.align === 'center' ? FlexAlign.Center :
          l.style.align === 'right' ? FlexAlign.End : FlexAlign.Start)
      } else if (l.type === 'image') {
        Circle({ width: '100%', height: '100%' }).fill(l.style.fill)
      } else {
        Rect().width('100%').height('100%').radiusWidth(l.style.radius).radiusHeight(l.style.radius).fill(l.style.fill)
      }
    }
    .width(l.style.w).height(l.style.h)
    .position({ x: l.style.x, y: l.style.y })
    .opacity(l.style.visible ? l.style.opacity : 0.12)
    .border(this.selLayer === l.id ?
      { width: 1.5, color: ACC, radius: l.style.radius + 2 } :
      { width: 0 })
    .onClick(() => {
      if (this.selLayer !== l.id) { this.selLayer = l.id; }
    })
    .gesture(PanGesture({ fingers: 1, distance: 3 })
      .onActionEnd((e: GestureEvent) => {
        appStore.moveLayer(b.id, l.id, e.offsetX, e.offsetY);
        this.sync();
      }))
  }

  @Builder
  boardFrame(b: Board) {
    Column() {
      Stack() {
        ForEach(b.layers, (l: LayerNode) => {
          this.elNode(b, l)
        }, (l: LayerNode) => l.id + '_' + Math.round(l.style.x) + '_' + Math.round(l.style.y) + '_' + l.style.text + '_' + l.style.color)
      }.width('100%').height('100%').clip(true)

      Text(`${b.name} · ${b.width} × ${b.height}`)
        .fontSize(11.5).fontWeight(600).fontColor(TX).margin({ top: 9 })
    }
    .width(b.width).height(b.height + 30)
    .padding(0)
    .onClick(() => { this.selBoard = b.id; })
  }

  // ===== 模板缩略（对齐 .th：白底斜纹 + 线框示意）=====
  @Builder
  tplThumb(kind: string, compact: boolean) {
    Column({ space: compact ? 3 : 4 }) {
      if (kind === 'mobile') {
        Circle({ width: compact ? 10 : 13, height: compact ? 10 : 13 }).fill('rgba(0,0,0,0.12)')
        Rect({ width: '62%', height: compact ? 5 : 7 }).radius(2).fill('rgba(0,0,0,0.14)')
        Rect({ width: '44%', height: compact ? 4 : 5 }).radius(2).fill('rgba(0,0,0,0.08)')
        Rect({ width: '74%', height: compact ? 10 : 13 }).radius(3).fill('#fff').stroke('rgba(0,0,0,0.13)')
        Rect({ width: '74%', height: compact ? 10 : 13 }).radius(3).fill('#fff').stroke('rgba(0,0,0,0.13)')
        Rect({ width: '74%', height: compact ? 11 : 14 }).radius(3).fill(ACC).opacity(0.88)
      } else {
        Row({ space: 3 }) {
          Rect({ width: compact ? 8 : 10, height: 4 }).radius(1).fill('rgba(0,0,0,0.14)')
          Blank()
          Rect({ width: compact ? 11 : 14, height: 4 }).radius(1).fill(ACC).opacity(0.75)
        }.width('100%')
        Rect({ width: '50%', height: compact ? 5 : 7 }).radius(2).fill('rgba(0,0,0,0.14)')
        Rect({ width: '36%', height: compact ? 4 : 5 }).radius(2).fill('rgba(0,0,0,0.08)')
        Row({ space: 4 }) {
          Rect({ width: compact ? 20 : 26, height: compact ? 9 : 12 }).radius(3).fill(ACC).opacity(0.88)
          Rect({ width: compact ? 20 : 26, height: compact ? 9 : 12 }).radius(3).fill('#fff').stroke('rgba(0,0,0,0.13)')
        }
      }
    }.width('100%').height('100%').padding(6)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .border({ width: 1, color: 'rgba(0,0,0,0.07)' })
    .alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
  }

  @Builder
  tplCard(t: TplDef, compact: boolean) {
    Column() {
      Column() {
        this.tplThumb(t.kind, compact)
      }.width('100%').height(compact ? 56 : 74).margin({ bottom: compact ? 6 : 9 })

      Text(t.name).fontSize(11.5).fontWeight(600).fontColor(TX)
        .maxLines(1).alignSelf(ItemAlign.Start)
      Text(`${t.kind} · ${TplSize.of(t.kind)[0]} × ${TplSize.of(t.kind)[1]}`)
        .fontSize(9).fontColor(TX2).margin({ top: 1 }).alignSelf(ItemAlign.Start)
    }
    .width(compact ? 96 : 126).padding(compact ? 8 : 11)
    .backgroundColor('#ffffff')
    .borderRadius(12)
    .border({ width: 1, color: 'rgba(0,0,0,0.08)' })
    .shadow({ radius: 2, offsetX: 0, offsetY: 1, color: SHSM })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.addTpl(t.tid))
  }

  @Builder
  layerRow(l: LayerNode) {
    Row({ space: 6 }) {
      Text(l.type === 'text' ? 'T' : l.type === 'input' ? '▭' : l.type === 'btn' ? '⬒' : l.type === 'image' ? '◉' : '▢')
        .fontSize(10).fontColor(TX3).width(14)
      Text(l.name).fontSize(11.5)
        .fontColor(this.selLayer === l.id ? ACCTX : TX).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      if (this.selLayer === l.id) {
        Text('✕').fontSize(10).fontColor(TX3)
          .onClick(() => {
            const b = this.curBoard();
            if (b) { appStore.deleteLayer(b.id, l.id); this.selLayer = ''; this.sync(); }
          })
      }
    }.width('100%').height(27).borderRadius(6).padding({ left: 5, right: 5 })
    .backgroundColor(this.selLayer === l.id ? 'rgba(0,102,214,0.07)' : Color.Transparent)
    .onClick(() => { this.selLayer = l.id; })
  }

  @Builder
  tlCard(e: TlEntry) {
    Column() {
      Text(`${e.src === 'AGENT' ? 'AGENT' : e.src === 'TEMPLATE' ? 'TEMPLATE' : 'HUMAN'} · rev ${e.rev} · ${e.ms}ms`)
        .fontSize(11.5).fontWeight(700).fontColor(TX).margin({ bottom: 4 })
      Row({ space: 5 }) {
        Text(e.src === 'AGENT' ? '◆' : e.src === 'TEMPLATE' ? '◇' : '●')
          .fontSize(9).fontColor(e.src === 'AGENT' ? PURPLE : e.src === 'TEMPLATE' ? OK : ACC)
        Text(e.op).fontSize(10.5).fontColor(TX2).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      }.width('100%')
    }.width('100%').padding({ left: 11, right: 11, top: 9, bottom: 9 })
    .borderRadius(12).backgroundColor('#ffffff')
    .border({ width: 1, color: 'rgba(0,0,0,0.1)' })
    .margin({ bottom: 8 })
  }

  @Builder
  fieldRow(label: string, value: string, onSet: (v: string) => void, wide: boolean) {
    Column({ space: 3 }) {
      Text(label).fontSize(9.5).fontColor(TX2)
      TextInput({ text: value }).fontSize(11.5).height(27).borderRadius(6)
        .backgroundColor('#ffffff').border({ width: 1, color: 'rgba(0,0,0,0.1)' })
        .padding({ left: 7, right: 7 })
        .onChange((v: string) => onSet(v))
    }.width(wide ? '100%' : '48%')
  }

  build() {
    Column() {
      // ===== topbar（46px，token 对齐）=====
      Row({ space: 6 }) {
        // brand
        Row({ space: 8 }) {
          Column() {
            Text('dD').fontSize(9).fontWeight(800).fontColor('#fff')
          }.width(20).height(20).borderRadius(5).backgroundColor(TX)
          .shadow({ radius: 4, color: 'rgba(15,23,42,0.25)' })
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          Column({ space: 0 }) {
            Row({ space: 5 }) {
              Text('deepDesign').fontSize(13).fontWeight(700).fontColor(TX)
              Text('STUDIO').fontSize(9).fontColor(TX3).fontWeight(600)
                .letterSpacing(1.2).margin({ top: 1 })
            }
          }
        }
        // filechip（项目名）
        Row({ space: 4 }) {
          Text(this.projName).fontSize(10.5).fontColor(TX2).maxLines(1)
          Text('▾').fontSize(8).fontColor(TX2)
        }.height(22).padding({ left: 9, right: 9 }).borderRadius(99)
        .backgroundColor('rgba(0,0,0,0.05)')
        .constraintSize({ maxWidth: 180 })
        Text('v0.4.0-β').fontSize(10.5).fontColor(TX3).margin({ left: 2 })
        Blank()
        // mode-seg（三模式）
        Row({ space: 2 }) {
          ForEach(this.modes, (m: string, i: number) => {
            Text(m).fontSize(12.5).fontWeight(this.modeIdx === i ? 600 : 500)
              .fontColor(this.modeIdx === i ? TX : TX2)
              .height(28).padding({ left: 13, right: 13 }).borderRadius(8)
              .backgroundColor(this.modeIdx === i ? '#ffffff' : Color.Transparent)
              .shadow(this.modeIdx === i ? { radius: 3, offsetY: 1, color: 'rgba(0,0,0,0.1)' } :
                { radius: 0, color: 'rgba(0,0,0,0)' })
              .onClick(() => { this.modeIdx = i; })
          }, (m: string) => m)
        }.padding(2).borderRadius(9).backgroundColor('rgba(0,0,0,0.055)')
        .border({ width: 1, color: 'rgba(0,0,0,0.05)' })
        // 操作组
        Row({ space: 12 }) {
          Text(this.xiaoyiState).fontSize(9.5)
            .fontColor(this.xiaoyiState.includes('就绪') ? '#1d6b41' : TX3).maxLines(1)
          Text('新建').fontSize(12.5).fontWeight(500).fontColor(TX2)
          Text('打开 DDP…').fontSize(12.5).fontWeight(500).fontColor(TX2)
          Text(this.dirty ? '保存 •' : '保存').fontSize(12.5).fontWeight(500).fontColor(TX2)
          Text('⚙').fontSize(13).fontColor(TX2).onClick(() => { this.showSettings = true; })
          Row({ space: 5 }) {
            Text('↧').fontSize(12).fontColor('#fff')
            Text('导出 DDP').fontSize(12.5).fontWeight(600).fontColor('#fff')
          }.height(28).padding({ left: 12, right: 12 }).borderRadius(8)
          .backgroundColor(ACC)
        }.margin({ left: 10 })
      }
      .width('100%').height(46).padding({ left: 12, right: 14 })
      .backgroundColor(PANEL_T).border({ width: { bottom: 1 }, color: BD })
      .alignItems(VerticalAlign.Center)

      // ===== 主区 =====
      Row() {
        // ---- left 252px ----
        Column() {
          Row() {
            ForEach(this.tabs, (t: string, i: number) => {
              Text(t).fontSize(12).fontWeight(500)
                .fontColor(this.tabIdx === i ? TX : TX2)
                .layoutWeight(1).height(37)
                .textAlign(TextAlign.Center)
                .border({ width: { bottom: this.tabIdx === i ? 2 : 2 }, color: this.tabIdx === i ? ACC : 'rgba(0,0,0,0,0)' })
                .onClick(() => { this.tabIdx = i; })
            }, (t: string) => t)
          }.width('100%').backgroundColor('rgba(0,0,0,0.02)')
          .border({ width: { bottom: 1 }, color: BD })
          Scroll() {
            Column() {
              if (this.tabIdx === 0) {
                // 画板组
                Row() {
                  Text('画布页面').fontSize(11).fontWeight(600).fontColor(TX2)
                  Blank()
                  Text(String(this.boards.length)).fontSize(11).fontColor(TX3)
                }.width('100%').margin({ bottom: 6 })
                ForEach(this.boards, (b: Board) => {
                  Row({ space: 6 }) {
                    Circle({ width: 6, height: 6 })
                      .fill(b.id === this.selBoard ? ACC : 'rgba(0,0,0,0.18)')
                    Text(b.name).fontSize(12).fontWeight(b.id === this.selBoard ? 600 : 400)
                      .fontColor(b.id === this.selBoard ? ACCTX : TX).maxLines(1)
                      .layoutWeight(1)
                    Text(`rev ${b.rev}`).fontSize(10).fontColor(TX3)
                    Text('✕').fontSize(9).fontColor(TX3)
                      .onClick(() => { appStore.removeBoard(b.id); this.sync(); })
                  }.width('100%').height(28).borderRadius(6)
                  .padding({ left: 6, right: 6 }).margin({ bottom: 1 })
                  .backgroundColor(b.id === this.selBoard ? 'rgba(0,102,214,0.06)' : Color.Transparent)
                  .onClick(() => { this.selBoard = b.id; this.selLayer = ''; })
                }, (b: Board) => b.id + b.rev)
                if (this.boards.length === 0) {
                  Text('无画板 — 点下方模板卡或 Prompt 生成')
                    .fontSize(11).fontColor(TX3).padding({ top: 6, bottom: 10 }).width('100%')
                    .textAlign(TextAlign.Center)
                }
                Divider().color(BD).margin({ top: 10, bottom: 10 })
                // 图层组
                Row() {
                  Text('图层').fontSize(11).fontWeight(600).fontColor(TX2)
                  Blank()
                  Text(String(this.curBoard()?.layers.length ?? 0)).fontSize(11).fontColor(TX3)
                }.width('100%').margin({ bottom: 6 })
                ForEach(this.curBoard()?.layers ?? [], (l: LayerNode) => {
                  this.layerRow(l)
                }, (l: LayerNode) => l.id)
              } else if (this.tabIdx === 1) {
                Text('AI 组件（组件市场随 L1 引擎开放）')
                  .fontSize(11.5).fontColor(TX3).padding({ top: 10 })
              } else {
                Text('流程视图（画板间交互流）').fontSize(11.5).fontColor(TX3).padding({ top: 10 })
                if (this.boards.length > 1) {
                  ForEach(this.boards, (b: Board, i: number) => {
                    Row({ space: 6 }) {
                      Text(`${i + 1}`).fontSize(10).fontColor(TX3)
                      Text(b.name).fontSize(11.5).fontColor(TX).maxLines(1)
                    }.width('100%').height(28).padding({ left: 6 })
                  }, (b: Board) => b.id)
                }
              }
            }.width('100%').padding(10)
          }.layoutWeight(1).scrollBar(BarState.Auto)
          // lfoot（引擎状态，对齐原版）
          Row({ space: 5 }) {
            Circle({ width: 6, height: 6 }).fill(OK)
            Text('deepDesign Engine').fontSize(10).fontColor(TX2).maxLines(1)
            Blank()
            Text('8ms').fontSize(10).fontColor(TX2)
          }.width('100%').height(24).padding({ left: 11, right: 11 })
        }.width(252).height('100%').backgroundColor(PANEL_S)
        .border({ width: { right: 1 }, color: BD }).alignItems(HorizontalAlign.Start)

        // ---- 中央画布（Stack：画布 + czoom + dock）----
        Stack({ alignContent: Alignment.TopEnd }) {
          Scroll() {
            Column() {
              if (this.boards.length > 0) {
                Row({ space: 96 }) {
                  ForEach(this.boards, (b: Board) => {
                    this.boardFrame(b)
                  }, (b: Board) => b.id + b.rev + b.layers.length)
                }.padding({ top: 56, bottom: 130, left: 64, right: 64 })
              } else {
                Column() {
                  Text('从 deepDesign 开始').fontSize(21).fontWeight(700).fontColor(TX)
                  Text('选择模板即刻开始，或按 ⌘K 直接对 Agent 下命令')
                    .fontSize(12.5).fontColor(TX2).margin({ top: 8 })
                  Row({ space: 12 }) {
                    ForEach(TPLS.filter((t: TplDef): boolean => TPL_FEATURED.includes(t.tid)), (t: TplDef) => {
                      this.tplCard(t, false)
                    }, (t: TplDef) => t.tid)
                  }.margin({ top: 30 })
                  if (this.showAllTpl) {
                    Column() {
                      ForEach(TPL_GROUPS, (g: string[]) => {
                        Column() {
                          Text(`${g[1]} · ${TPLS.filter((t: TplDef): boolean => t.kind === g[0]).length}`)
                            .fontSize(10.5).fontWeight(600).fontColor(TX3)
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
                  Text(this.showAllTpl ? '收起 ▴' : '浏览全部模板（14）▾')
                    .fontSize(12).fontWeight(500).fontColor(ACCTX).margin({ top: 18 })
                    .onClick(() => { this.showAllTpl = !this.showAllTpl; })
                }.width('100%').height('100%').justifyContent(FlexAlign.Center)
              }
            }.width('100%')
          }.width('100%').height('100%').scrollBar(BarState.Auto).align(Alignment.Center)

          // czoom（右上悬浮，token 对齐）
          Row({ space: 8 }) {
            Text('−').fontSize(13).fontColor(TX2)
              .onClick(() => { this.zoom = Math.max(25, this.zoom - 25); })
            Text(`${this.zoom}%`).fontSize(11).fontWeight(600).fontColor(TX)
              .constraintSize({ minWidth: 40 }).textAlign(TextAlign.Center)
            Text('＋').fontSize(13).fontColor(TX2)
              .onClick(() => { this.zoom = Math.min(200, this.zoom + 25); })
            Divider().vertical(true).height(12).color(BD)
            Text('⤢ 适配窗口').fontSize(11).fontColor(TX2).onClick(() => { this.zoom = 100; })
          }.padding({ left: 10, right: 10, top: 5, bottom: 5 }).borderRadius(12)
          .backgroundColor('rgba(255,255,255,0.9)').border({ width: 1, color: 'rgba(0,0,0,0.07)' })
          .shadow({ radius: 12, color: 'rgba(0,0,0,0.13)' })
          .margin({ top: 12, right: 12 })

          // canvas-dock（底部居中悬浮：pchips + pmain，token 对齐）
          Column({ space: 6 }) {
            Flex({ wrap: FlexWrap.NoWrap, justifyContent: FlexAlign.Center }) {
              ForEach(this.pchips, (c: string) => {
                Text(c).fontSize(12).fontWeight(500).fontColor(TX)
                  .height(30).padding({ left: 13, right: 13 }).borderRadius(99)
                  .backgroundColor('rgba(0,0,0,0.05)')
                  .border({ width: 1, color: 'rgba(0,0,0,0.07)' })
                  .margin({ left: 3, right: 3 })
                  .onClick(() => {
                    if (c.includes('Web 登录')) this.usePrompt('生成 Web 登录页');
                    else if (c.includes('手机')) this.usePrompt('生成手机登录页');
                    else if (c.includes('仪表盘')) this.usePrompt('生成仪表盘页面');
                    else if (c.includes('微信')) this.usePrompt('做一个微信风格的社交应用原型：聊天列表、会话页、发现页、我的页面，相互可跳转');
                    else this.usePrompt('一键修复');
                  })
              }, (c: string) => c)
            }
            if (this.agentMsg !== '') {
              Text(this.agentMsg).fontSize(11).fontColor(PURPLE).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).padding({ left: 8, right: 8 })
            }
            // pmain（输入条）
            Row({ space: 8 }) {
              Text('✦').fontSize(14).fontColor(PURPLE)
              TextInput({ placeholder: '描述意图（如：生成 Web 登录页 / 一键修复 / 深色主题）…', text: this.prompt })
                .onChange((v: string) => { this.prompt = v; })
                .onSubmit(() => this.runPrompt())
                .fontSize(13).height(34).layoutWeight(1)
                .backgroundColor(Color.Transparent).border({ width: 0 })
                .placeholderColor(TX3)
                .constraintSize({ minWidth: 280 })
              Text('⌘K').fontSize(10).fontColor(TX3)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(5)
                .backgroundColor('rgba(0,0,0,0.05)').border({ width: 1, color: 'rgba(0,0,0,0.06)' })
              Row({ space: 6 }) {
                Text('⚡').fontSize(12).fontColor('#fff')
                Text('一键生成').fontSize(13).fontWeight(600).fontColor('#fff')
              }.height(34).padding({ left: 18, right: 18 }).borderRadius(9)
              .backgroundColor(ACC)
              .onClick(() => this.runPrompt())
            }.padding({ left: 13, right: 5, top: 5, bottom: 5 }).borderRadius(12)
            .backgroundColor('#ffffff')
            .border({ width: 1, color: 'rgba(0,0,0,0.1)' })
            .shadow({ radius: 2, offsetY: 1, color: SHSM })
            .constraintSize({ maxWidth: 640 })
          }.width('100%')
          .position({ x: '12%', y: '78%' })
        }.layoutWeight(1).height('100%').backgroundColor(BASE)

        // ---- right 360px ----
        Column() {
          Row() {
            Text('属性').fontSize(12.5).fontWeight(this.selLayer !== '' ? 600 : 500)
              .fontColor(this.selLayer !== '' ? TX : TX2)
              .height(37).padding({ left: 14, right: 14 })
              .border({ width: { bottom: this.selLayer !== '' ? 2 : 2 }, color: this.selLayer !== '' ? ACC : 'rgba(0,0,0,0,0)' })
            Text('Agent 追踪').fontSize(12.5).fontWeight(this.timeline.length > 0 && this.selLayer === '' ? 600 : 500)
              .fontColor(this.timeline.length > 0 ? TX : TX2)
              .height(37).padding({ left: 14, right: 14 })
              .border({ width: { bottom: this.selLayer === '' ? 2 : 2 }, color: this.selLayer === '' ? ACC : 'rgba(0,0,0,0,0)' })
          }.width('100%').backgroundColor('rgba(0,0,0,0.02)')
          .border({ width: { bottom: 1 }, color: BD })
          Scroll() {
            Column() {
              if (this.selLayer !== '' && this.curLayer()) {
                Text(this.curLayer()!.name).fontSize(13).fontWeight(600).fontColor(TX)
                Text(`${this.curLayer()!.type} · rev ${this.curBoard()!.rev}`)
                  .fontSize(10).fontColor(TX3).margin({ top: 2, bottom: 8 })
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
                  this.fieldRow('文本', this.curLayer()!.style.text, (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'text', v); this.sync(); }
                  }, true)
                  this.fieldRow('填充', this.curLayer()!.style.fill, (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'fill', v); this.sync(); }
                  }, false)
                  this.fieldRow('文字色', this.curLayer()!.style.color, (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'color', v); this.sync(); }
                  }, false)
                  this.fieldRow('X', String(Math.round(this.curLayer()!.style.x)), (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'x', Number(v) || 0); this.sync(); }
                  }, false)
                  this.fieldRow('Y', String(Math.round(this.curLayer()!.style.y)), (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'y', Number(v) || 0); this.sync(); }
                  }, false)
                  this.fieldRow('宽', String(this.curLayer()!.style.w), (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'w', Number(v) || 1); this.sync(); }
                  }, false)
                  this.fieldRow('高', String(this.curLayer()!.style.h), (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'h', Number(v) || 1); this.sync(); }
                  }, false)
                  this.fieldRow('字号', String(this.curLayer()!.style.fontSize), (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'fontSize', Number(v) || 12); this.sync(); }
                  }, false)
                  this.fieldRow('圆角', String(this.curLayer()!.style.radius), (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'radius', Number(v) || 0); this.sync(); }
                  }, false)
                }.width('100%')
                Row() {
                  Text('对齐').fontSize(9.5).fontColor(TX2)
                  ForEach(['左', '中', '右'], (a: string, i: number) => {
                    Text(a).fontSize(10).fontWeight(500)
                      .fontColor(this.curLayer()!.style.align === ['left', 'center', 'right'][i] ? ACCTX : TX2)
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 }).borderRadius(5)
                      .backgroundColor(this.curLayer()!.style.align === ['left', 'center', 'right'][i] ?
                        'rgba(0,102,214,0.08)' : Color.Transparent)
                      .margin({ left: 4 })
                      .onClick(() => {
                        const b = this.curBoard(); const l = this.curLayer();
                        if (b && l) { appStore.setStyle(b.id, l.id, 'align', ['left', 'center', 'right'][i]); this.sync(); }
                      })
                  }, (a: string) => a)
                  Blank()
                  Text(this.curLayer()!.style.visible ? '👁' : '◌').fontSize(11)
                    .fontColor(this.curLayer()!.style.visible ? TX : TX3)
                    .onClick(() => {
                      const b = this.curBoard(); const l = this.curLayer();
                      if (b && l) { appStore.setStyle(b.id, l.id, 'visible', !l.style.visible); this.sync(); }
                    })
                }.width('100%').margin({ top: 10 })
                Divider().color(BD).margin({ top: 10, bottom: 10 })
              } else {
                Text('未选中元素').fontSize(13).fontWeight(600).fontColor(TX)
                Text('在画布中点选任意元素\n属性与交互将在此显示')
                  .fontSize(11.5).fontColor(TX2).margin({ top: 6 }).textAlign(TextAlign.Center)
                Row({ space: 10 }) {
                  Text('删除元素').fontSize(10).fontColor(TX3)
                  Text('Del').fontSize(9.5).fontColor(TX3)
                    .padding({ left: 5, right: 5, top: 1, bottom: 1 }).borderRadius(4)
                    .backgroundColor('rgba(0,0,0,0.05)')
                    .fontFamily('monospace')
                  Text('改文字').fontSize(10).fontColor(TX3)
                  Text('双击').fontSize(9.5).fontColor(TX3)
                    .padding({ left: 5, right: 5, top: 1, bottom: 1 }).borderRadius(4)
                    .backgroundColor('rgba(0,0,0,0.05)')
                    .fontFamily('monospace')
                }.margin({ top: 12 })
              }
              // 时间线（tl-run 卡片，token 对齐）
              ForEach(this.timeline.slice(0, 12), (e: TlEntry) => {
                this.tlCard(e)
              }, (e: TlEntry) => e.op + e.rev)
            }.width('100%').padding(10).alignItems(HorizontalAlign.Start)
          }.layoutWeight(1).scrollBar(BarState.Auto)
        }.width(360).height('100%').backgroundColor(PANEL_S)
        .border({ width: { left: 1 }, color: BD }).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1)

      // ===== statusbar（27px，token 对齐）=====
      Row({ space: 10 }) {
        Text(this.busy ? 'RUN' : 'READY').fontSize(8.5).fontWeight(800)
          .fontColor('#1d6b41').letterSpacing(0.5)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 }).borderRadius(99)
          .backgroundColor('rgba(40,167,69,0.12)')
        Text('三条输入汇入同一命令流：人类拖拽 · Agent 指令 · 模板')
          .fontSize(10.5).fontColor(TX2).fontFamily('monospace').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        Text(this.coreTag).fontSize(10.5).fontColor(TX3).fontFamily('monospace')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').height(27).padding({ left: 12, right: 12 })
      .backgroundColor(PANEL_S).border({ width: { top: 1 }, color: BD })
      .alignItems(VerticalAlign.Center)
    }.width('100%').height('100%').backgroundColor(BASE)
    .bindSheet($$this.showSettings, this.settingsSheet(), { height: 440, dragBar: true })
  }

  @Builder
  settingsSheet() {
    Column({ space: 11 }) {
      Text('设置').fontSize(16).fontWeight(700).fontColor(TX)
      Divider().color(BD)
      Column({ space: 11 }) {
        Row() {
          Text('Agent 执行者').fontSize(13).fontColor(TX)
          Blank()
          Text(this.xiaoyiState).fontSize(11)
            .fontColor(this.xiaoyiState.includes('就绪') ? '#1d6b41' : TX2)
        }.width('86%')
        Row() {
          Text('端侧小艺（localChatModel）').fontSize(11.5).fontColor(TX2)
          Blank()
          Text('系统级 · 数据不出设备').fontSize(10.5).fontColor(TX3)
        }.width('86%')
        Row() {
          Text('云端回退').fontSize(11.5).fontColor(TX2)
          Blank()
          Text('配置 API Key 后启用').fontSize(10.5).fontColor(TX3)
        }.width('86%')
        Divider().color(BD).width('86%')
        Row() {
          Text('引擎').fontSize(13).fontColor(TX)
          Blank()
          Text('moonviz · wasmtime 宿主 L1 下沉中').fontSize(11).fontColor(TX2)
        }.width('86%')
        Row() {
          Text('DDP 加密').fontSize(13).fontColor(TX)
          Blank()
          Text('Argon2id + XChaCha20 · 已接通').fontSize(11).fontColor('#1d6b41')
        }.width('86%')
        Row() {
          Text('Rust core').fontSize(13).fontColor(TX)
          Blank()
          Text(this.coreTag).fontSize(9).fontColor(TX3).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 190 })
        }.width('86%')
      }.width('100%').alignItems(HorizontalAlign.Center)
      Row({ space: 6 }) {
        Text('⚡').fontSize(12).fontColor('#fff')
        Text('完成').fontSize(13).fontWeight(600).fontColor('#fff')
      }.height(34).padding({ left: 18, right: 18 }).borderRadius(9)
      .backgroundColor(ACC).margin({ top: 6 })
      .onClick(() => { this.showSettings = false; })
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
  }
}
