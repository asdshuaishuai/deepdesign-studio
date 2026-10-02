// deepDesign Studio —— 鸿蒙原生交互层（纯 ArkUI，复刻通用版布局与交互）
//
// 对齐原版 frontend/index.html 的结构：顶栏（logo/项目/模式/操作）+
// 左栏（画板页签 + 图层/AI组件/流程）+ 画布 stage（多画板/选中/拖拽/缩放）+
// 右栏（属性 inspector 全字段 / Agent 追踪时间线）+ 底部指令条（chips/一键生成）。
// Agent 默认执行者 = 端侧小艺（AgentService → localChatModel），本地解析兜底。

import { coreVersion, ddpEncrypt, ddpDecrypt } from '../core/CoreBridge';
import { appStore, Board, LayerNode, TlEntry, TplDef, TPLS, TplSize, TPL_FEATURED, TPL_GROUPS } from '../model/AppStore';
import { agentService } from '../ai/AgentService';

const BG = '#f2f3f7';
const TX = '#1c1c1e';
const TX2 = '#636366';
const PANEL = '#ffffff';
const LINE = 'rgba(0,0,0,0.08)';
const ACC = '#007aff';

@Entry
@Component
struct Index {
  @State coreTag: string = '...';
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
  private chips: string[] = ['+ Web 登录页', '+ 手机登录', '+ 仪表盘', '💬 微信社交', '⚡ 自动修复'];

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
    const def = TPLS.find((t) => t.tid === tid);
    if (!def) return;
    const b = appStore.addBoard(tid, def.name, def.kind, 'TEMPLATE');
    this.sync();
    this.selBoard = b.id;
    this.selLayer = '';
  }

  // ===== Agent 执行（端侧小艺默认）=====
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
        const l = b?.layers.find((x: LayerNode) => /title|welcome/.test(x.name));
        if (!b || !l) return false;
        appStore.setStyle(b.id, l.id, 'text', text.replace(/^小艺[:：]?\s*/, ''));
        this.sync();
        return true;
      },
      (color: string): boolean => {
        const b = this.curBoard();
        const l = b?.layers.find((x: LayerNode) => /title|welcome/.test(x.name));
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

  private undo(): void {
    appStore.undo();
    this.sync();
  }

  // ===== 画布元素渲染（按 style）=====
  @Builder
  elNode(b: Board, l: LayerNode) {
    Stack() {
      if (l.type === 'input') {
        Row() {
          Text(l.style.text).fontSize(l.style.fontSize * 0.9).fontColor(l.style.color).maxLines(1)
        }.width('100%').height('100%').padding({ left: 8 })
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
            .fontWeight(l.style.bold ? 700 : 400).maxLines(2)
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
    .opacity(l.style.visible ? l.style.opacity : 0.15)
    .border(this.selLayer === l.id ? { width: 1.5, color: ACC, radius: l.style.radius } : { width: 0 })
    .onClick(() => {
      if (this.selLayer === l.id) return;
      this.selLayer = l.id;
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
        }, (l: LayerNode) => l.id + '_' + Math.round(l.style.x) + '_' + Math.round(l.style.y) + '_' + l.style.text)
      }.width('100%').height('100%').clip(true)

      Text(`${b.name} · ${b.width} × ${b.height}`).fontSize(9).fontColor(TX2).margin({ top: 4 })
    }
    .width(b.width).height(b.height + 22)
    .onClick(() => { this.selBoard = b.id; })
  }

  // ===== 模板缩略（按 kind 差异化线框示意）=====
  @Builder
  tplThumb(kind: string) {
    Column({ space: 4 }) {
      if (kind === 'mobile') {
        Circle({ width: 12, height: 12 }).fill(LINE)
        Rect({ width: '66%', height: 6 }).radius(3).fill(LINE)
        Rect({ width: '46%', height: 5 }).radius(2).fill('#e8e8ec')
        Rect({ width: '76%', height: 12 }).radius(4).fill('#fff').stroke(LINE)
        Rect({ width: '76%', height: 12 }).radius(4).fill('#fff').stroke(LINE)
        Rect({ width: '76%', height: 13 }).radius(4).fill(ACC).opacity(0.85)
      } else {
        Row({ space: 3 }) {
          Rect({ width: 9, height: 5 }).radius(2).fill(LINE)
          Blank()
          Rect({ width: 13, height: 5 }).radius(2).fill(ACC).opacity(0.7)
        }.width('100%')
        Rect({ width: '52%', height: 7 }).radius(3).fill(LINE)
        Rect({ width: '38%', height: 5 }).radius(2).fill('#e8e8ec')
        Row({ space: 4 }) {
          Rect({ width: 24, height: 12 }).radius(4).fill(ACC).opacity(0.85)
          Rect({ width: 24, height: 12 }).radius(4).fill('#fff').stroke(LINE)
        }
      }
    }.width('100%').height('100%').padding(7)
    .backgroundColor('#fafafc').borderRadius(5).border({ width: 1, color: LINE })
    .alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
  }

  @Builder
  tplCardRow(tid: string, name: string, kind: string) {
    Column() {
      this.tplThumb(kind)
      Text(name).fontSize(10).fontWeight(600).fontColor(TX).margin({ top: 5 }).maxLines(1)
      Text(`${kind} · ${TplSize.of(kind)[0]} × ${TplSize.of(kind)[1]}`).fontSize(8).fontColor(TX2).margin({ top: 1 })
    }.padding(8)
    .constraintSize({ minWidth: 92 })
    .backgroundColor(PANEL).borderRadius(9).border({ width: 1, color: LINE })
    .shadow({ radius: 4, color: 'rgba(0,0,0,0.05)' })
    .onClick(() => this.addTpl(tid))
  }

  @Builder
  layerRow(l: LayerNode) {
    Row({ space: 5 }) {
      Text(l.type === 'text' ? 'T' : l.type === 'input' ? '▭' : l.type === 'btn' ? '⬒' : l.type === 'image' ? '◉' : '▢')
        .fontSize(9).fontColor(TX2).width(14)
      Text(l.name).fontSize(10.5)
        .fontColor(this.selLayer === l.id ? ACC : TX).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      if (this.selLayer === l.id) {
        Text('⋯').fontSize(11).fontColor(TX2)
          .onClick(() => {
            const b = this.curBoard();
            if (b) { appStore.deleteLayer(b.id, l.id); this.selLayer = ''; this.sync(); }
          })
      }
    }.width('100%').height(24).borderRadius(4).padding({ left: 4, right: 4 })
    .backgroundColor(this.selLayer === l.id ? 'rgba(0,122,255,0.08)' : Color.Transparent)
    .onClick(() => { this.selLayer = l.id; })
  }

  @Builder
  tlRow(e: TlEntry) {
    Row({ space: 5 }) {
      Text(e.src).fontSize(7.5).fontWeight(700)
        .fontColor(e.src === 'AGENT' ? '#9d4edd' : e.src === 'TEMPLATE' ? '#28a745' : ACC)
        .padding({ left: 3, right: 3, top: 1, bottom: 1 })
        .border({ width: 1, color: LINE, radius: 3 })
      Text(`${e.rev}`).fontSize(7.5).fontColor('#aeaeb2')
      Text(e.op).fontSize(8.5).fontColor(e.ok ? TX2 : '#e5484d').maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      Text(`${e.ms}ms`).fontSize(7.5).fontColor('#aeaeb2')
    }.width('100%')
  }

  // 属性字段行（标签 + 可编辑值）
  @Builder
  fieldRow(label: string, value: string, onSet: (v: string) => void, wide: boolean = false) {
    Column({ space: 2 }) {
      Text(label).fontSize(8.5).fontColor(TX2)
      TextInput({ text: value }).fontSize(10).height(26).borderRadius(5)
        .backgroundColor('#fff').border({ width: 1, color: LINE })
        .onChange((v: string) => onSet(v))
    }.width(wide ? '100%' : '47%')
  }

  build() {
    Column() {
      // ===== 顶栏 =====
      Row({ space: 7 }) {
        Text('deepDesign').fontSize(13.5).fontWeight(700).fontColor(TX)
        Text('STUDIO').fontSize(7.5).fontWeight(600).letterSpacing(1).fontColor(TX2).margin({ top: 2 })
        Row({ space: 3 }) {
          Text(this.projName).fontSize(9.5).fontColor(TX2).maxLines(1)
          Text('▾').fontSize(8).fontColor(TX2)
        }.padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .backgroundColor('rgba(0,0,0,0.04)').borderRadius(5)
        .constraintSize({ maxWidth: 96 })
        Text('v0.4.0-β').fontSize(8.5).fontColor(TX2).margin({ top: 2 })
        Blank()
        ForEach(this.modes, (m: string, i: number) => {
          Text(m).fontSize(10.5).fontWeight(this.modeIdx === i ? 600 : 400)
            .fontColor(this.modeIdx === i ? TX : TX2)
            .padding({ left: 7, right: 7, top: 3, bottom: 3 }).borderRadius(4)
            .backgroundColor(this.modeIdx === i ? 'rgba(0,122,255,0.10)' : Color.Transparent)
            .onClick(() => { this.modeIdx = i; })
        }, (m: string) => m)
        Row({ space: 10 }) {
          Text('新建').fontSize(10).fontColor(TX2).onClick(() => { this.projName = '未命名项目'; })
          Text('打开 DDP').fontSize(10).fontColor(TX2)
          Text('保存').fontSize(10).fontColor(this.dirty ? TX : TX2)
          Text('⚙').fontSize(11).fontColor(TX2).onClick(() => { this.showSettings = true; })
          Text(this.xiaoyiState).fontSize(8.5)
            .fontColor(this.xiaoyiState.includes('就绪') ? '#28a745' : TX2)
            .maxLines(1).constraintSize({ maxWidth: 110 })
          Text('导出 DDP').fontSize(10).fontColor(TX)
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .backgroundColor(PANEL).borderRadius(4).border({ width: 1, color: LINE })
        }.margin({ left: 6 })
      }
      .width('100%').height(38).padding({ left: 10, right: 10 })
      .backgroundColor(PANEL).alignItems(VerticalAlign.Center)

      // ===== 主区 =====
      Row() {
        // 左栏
        Column() {
          Row() {
            ForEach(this.tabs, (t: string, i: number) => {
              Text(t).fontSize(10.5).fontWeight(this.tabIdx === i ? 600 : 400)
                .fontColor(this.tabIdx === i ? TX : TX2)
                .padding({ left: 5, right: 5, bottom: 3 })
                .border({ width: { bottom: this.tabIdx === i ? 2 : 0 }, color: ACC })
                .onClick(() => { this.tabIdx = i; })
            }, (t: string) => t)
          }.width('100%').height(26).justifyContent(FlexAlign.SpaceEvenly)
          Divider().color(LINE)
          Scroll() {
            Column() {
              if (this.tabIdx === 0) {
                Row() {
                  Text('画布页面').fontSize(9).fontColor(TX2)
                  Blank()
                  Text(String(this.boards.length)).fontSize(9).fontColor(TX2)
                }.width('100%').padding(5)
                ForEach(this.boards, (b: Board) => {
                  Row({ space: 4 }) {
                    Text(b.id === this.selBoard ? '●' : '○').fontSize(8)
                      .fontColor(b.id === this.selBoard ? ACC : TX2)
                    Text(b.name).fontSize(10.5)
                      .fontColor(b.id === this.selBoard ? ACC : TX).maxLines(1)
                      .onClick(() => { this.selBoard = b.id; this.selLayer = ''; })
                    Blank()
                    Text(`rev ${b.rev}`).fontSize(7.5).fontColor(TX2)
                    Text('✕').fontSize(9).fontColor(TX2)
                      .onClick(() => { appStore.removeBoard(b.id); this.sync(); })
                  }.width('100%').height(24).borderRadius(4).padding({ left: 5, right: 5 })
                  .backgroundColor(b.id === this.selBoard ? 'rgba(0,122,255,0.06)' : Color.Transparent)
                  .onClick(() => { this.selBoard = b.id; })
                }, (b: Board) => b.id + b.rev)
                if (this.boards.length === 0) {
                  Text('无画板 — 点模板卡或 Prompt 生成').fontSize(8.5).fontColor(TX2)
                    .padding(6).textAlign(TextAlign.Center)
                }
                Divider().color(LINE).margin({ top: 5, bottom: 5 })
                Row() {
                  Text('图层').fontSize(9).fontColor(TX2)
                  Blank()
                  Text(String(this.curBoard()?.layers.length ?? 0)).fontSize(9).fontColor(TX2)
                }.width('100%').padding(5)
                ForEach(this.curBoard()?.layers ?? [], (l: LayerNode) => {
                  this.layerRow(l)
                }, (l: LayerNode) => l.id)
              } else if (this.tabIdx === 1) {
                Text('AI 组件（L1 引擎下沉后接入组件市场）').fontSize(9).fontColor(TX2).padding(10)
              } else {
                Text('流程视图（画板间交互流）').fontSize(9).fontColor(TX2).padding(10)
                if (this.boards.length > 1) {
                  ForEach(this.boards, (b: Board, i: number) => {
                    Row({ space: 4 }) {
                      Text(String(i + 1)).fontSize(9).fontColor(TX2)
                      Text(b.name).fontSize(10).fontColor(TX).maxLines(1)
                    }.width('100%').height(24).padding({ left: 6 })
                  }, (b: Board) => b.id)
                }
              }
            }.width('100%').padding({ left: 4, right: 4, top: 4, bottom: 8 })
          }.layoutWeight(1).scrollBar(BarState.Auto)
          // 左下角引擎状态（对齐原版 lfoot）
          Row({ space: 4 }) {
            Circle({ width: 5, height: 5 }).fill('#28a745')
            Text('deepDesign Engine').fontSize(8).fontColor(TX2).maxLines(1)
            Blank()
            Text('8ms').fontSize(8).fontColor(TX2)
          }.width('100%').height(22).padding({ left: 8, right: 8 })
          .backgroundColor('rgba(0,0,0,0.02)')
        }.width(196).height('100%').backgroundColor(PANEL)
        .border({ width: { right: 1 }, color: LINE }).alignItems(HorizontalAlign.Start)

        // 中央画布
        Column() {
          Row({ space: 10 }) {
            Text('↖ 选择').fontSize(10).fontColor(TX)
            Text('T 文本').fontSize(10).fontColor(TX2)
            Text('▭ 画板').fontSize(10).fontColor(TX2)
            Text('⇄ 连接').fontSize(10).fontColor(TX2)
            Text('⚡ 修复').fontSize(10).fontColor(TX2)
            Blank()
            Text('−').fontSize(13).fontColor(TX2)
              .onClick(() => { this.zoom = Math.max(25, this.zoom - 25); })
            Text(`${this.zoom}%`).fontSize(9.5).fontColor(TX).constraintSize({ minWidth: 34 })
            Text('＋').fontSize(13).fontColor(TX2)
              .onClick(() => { this.zoom = Math.min(200, this.zoom + 25); })
            Text('⤢ 适配').fontSize(10).fontColor(TX2)
          }.width('100%').height(28).padding({ left: 12, right: 12 })
          .backgroundColor(PANEL).alignItems(VerticalAlign.Center)
          Divider().color(LINE)

          Scroll() {
            Column() {
              if (this.boards.length > 0) {
                // stage：多画板横排（对齐原版 stage）
                Row({ space: 40 }) {
                  ForEach(this.boards, (b: Board) => {
                    this.boardFrame(b)
                  }, (b: Board) => b.id + b.rev + b.layers.length)
                }
                .scale({ x: this.zoom / 100, y: this.zoom / 100 })
                .padding(24)
              } else {
                Column() {
                  Text('从 deepDesign 开始').fontSize(19).fontWeight(700).fontColor(TX)
                  Text('选择模板即刻开始，或直接对 Agent 下命令').fontSize(10.5)
                    .fontColor(TX2).margin({ top: 7 })
                  // 精选 3 张（对齐 TPL_FEATURED）
                  Row({ space: 10 }) {
                    ForEach(TPLS.filter((t: TplDef) => TPL_FEATURED.includes(t.tid)), (t: TplDef) => {
                      Column() {
                        this.tplThumb(t.kind)
                        Text(t.name).fontSize(10).fontWeight(600).fontColor(TX).margin({ top: 5 })
                        Text(`${t.kind} · ${TplSize.of(t.kind)[0]} × ${TplSize.of(t.kind)[1]}`).fontSize(8).fontColor(TX2).margin({ top: 1 })
                      }.padding(8).backgroundColor(PANEL).borderRadius(9)
                      .border({ width: 1, color: LINE })
                      .shadow({ radius: 4, color: 'rgba(0,0,0,0.05)' })
                      .onClick(() => this.addTpl(t.tid))
                    }, (t: TplDef) => t.tid)
                  }.margin({ top: 24 })
                  // 全量模板（分组展开，对齐 renderTplRow/toggleAllTpl）
                  if (this.showAllTpl) {
                    Column({ space: 6 }) {
                      ForEach(TPL_GROUPS, (g: string[]) => {
                        Column() {
                          Text(`${g[1]} · ${TPLS.filter((t) => t.kind === g[0]).length}`)
                            .fontSize(8.5).fontColor(TX2).margin({ top: 6 })
                          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
                            ForEach(TPLS.filter((t: TplDef) => t.kind === g[0]), (t: TplDef) => {
                              this.tplCardRow(t.tid, t.name, t.kind)
                            }, (t: TplDef) => t.tid)
                          }.width('100%')
                        }.width('100%')
                      }, (g: string[]) => g[0])
                    }.width('58%').margin({ top: 16 })
                  }
                  Text(this.showAllTpl ? '收起 ▴' : `浏览全部模板（14）▾`)
                    .fontSize(9.5).fontColor(ACC).margin({ top: 14 })
                    .onClick(() => { this.showAllTpl = !this.showAllTpl; })
                }.justifyContent(FlexAlign.Center).width('100%').height('100%')
              }
            }.width('100%').padding(16).alignItems(HorizontalAlign.Center)
          }.layoutWeight(1).scrollBar(BarState.Auto).align(Alignment.Center)
        }.layoutWeight(1).height('100%').backgroundColor(BG)

        // 右栏：属性 / Agent 追踪
        Column() {
          Row() {
            Text('属性').fontSize(10.5).fontWeight(this.selLayer !== '' ? 600 : 400)
              .fontColor(this.selLayer !== '' ? TX : TX2)
              .border({ width: { bottom: this.selLayer !== '' ? 2 : 0 }, color: ACC })
              .padding({ bottom: 2 })
            Text('Agent 追踪').fontSize(10.5).fontWeight(this.timeline.length > 0 ? 600 : 400)
              .fontColor(this.timeline.length > 0 ? TX : TX2).margin({ left: 10 })
          }.width('100%').height(26).justifyContent(FlexAlign.Center)
          Divider().color(LINE)
          Scroll() {
            Column() {
              if (this.curLayer()) {
                Text(this.curLayer()!.name).fontSize(11).fontWeight(600).fontColor(TX)
                Text(`${this.curLayer()!.type} · rev ${this.curBoard()!.rev}`).fontSize(8).fontColor(TX2).margin({ top: 2 })
                // 属性字段（对齐原版 inspector：文本/填充/文字色/位置/尺寸/字号/对齐/可见）
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
                  this.fieldRow('文本', this.curLayer()!.style.text, (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'text', v); this.sync(); }
                  }, true)
                  this.fieldRow('填充', this.curLayer()!.style.fill, (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'fill', v); this.sync(); }
                  })
                  this.fieldRow('文字色', this.curLayer()!.style.color, (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'color', v); this.sync(); }
                  })
                  this.fieldRow('X', String(Math.round(this.curLayer()!.style.x)), (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'x', Number(v) || 0); this.sync(); }
                  })
                  this.fieldRow('Y', String(Math.round(this.curLayer()!.style.y)), (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'y', Number(v) || 0); this.sync(); }
                  })
                  this.fieldRow('宽', String(this.curLayer()!.style.w), (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'w', Number(v) || 1); this.sync(); }
                  })
                  this.fieldRow('高', String(this.curLayer()!.style.h), (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'h', Number(v) || 1); this.sync(); }
                  })
                  this.fieldRow('字号', String(this.curLayer()!.style.fontSize), (v: string): void => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.setStyle(b.id, l.id, 'fontSize', Number(v) || 12); this.sync(); }
                  })
                }.width('100%').padding({ top: 8 })
                Row() {
                  Text('对齐').fontSize(8.5).fontColor(TX2)
                  ForEach(['left', 'center', 'right'], (a: string) => {
                    Text(a === 'left' ? '⬅' : a === 'center' ? '↔' : '➡').fontSize(11)
                      .fontColor(this.curLayer()!.style.align === a ? ACC : TX2).margin({ left: 8 })
                      .onClick(() => {
                        const b = this.curBoard(); const l = this.curLayer();
                        if (b && l) { appStore.setStyle(b.id, l.id, 'align', a); this.sync(); }
                      })
                  }, (a: string) => a)
                  Blank()
                  Text(this.curLayer()!.style.visible ? '👁 可见' : '🚫 隐藏').fontSize(9).fontColor(TX2)
                    .onClick(() => {
                      const b = this.curBoard(); const l = this.curLayer();
                      if (b && l) { appStore.setStyle(b.id, l.id, 'visible', !l.style.visible); this.sync(); }
                    })
                }.width('100%').margin({ top: 8 })
                Text('删除元素 Del').fontSize(8.5).fontColor('#e5484d').margin({ top: 8 })
                  .onClick(() => {
                    const b = this.curBoard(); const l = this.curLayer();
                    if (b && l) { appStore.deleteLayer(b.id, l.id); this.selLayer = ''; this.sync(); }
                  })
              } else {
                Text('未选中元素').fontSize(11).fontWeight(600).fontColor(TX)
                Text('在画布中点选任意元素\n属性与交互将在此显示').fontSize(9).fontColor(TX2)
                  .margin({ top: 6 }).textAlign(TextAlign.Center)
                Text('删除元素 Del · 改文字 双击').fontSize(8.5).fontColor('#aeaeb2').margin({ top: 10 })
              }
              Divider().color(LINE).margin({ top: 10, bottom: 6 })
              // 时间线
              ForEach(this.timeline.slice(0, 14), (e: TlEntry) => {
                this.tlRow(e)
              }, (e: TlEntry) => e.op + e.rev)
            }.width('100%').padding(8).alignItems(HorizontalAlign.Start)
          }.layoutWeight(1)
        }.width(186).height('100%').backgroundColor(PANEL)
        .border({ width: { left: 1 }, color: LINE }).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1)

      // ===== 底部指令条 =====
      Column() {
        if (this.agentMsg !== '') {
          Text(this.agentMsg).fontSize(8.5).fontColor('#9d4edd').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%').padding({ left: 12, right: 12, top: 2 })
        }
        Row({ space: 7 }) {
          Text(this.busy ? 'RUN' : 'READY').fontSize(8.5).fontWeight(700)
            .fontColor(this.busy ? '#e6a700' : '#28a745')
            .border({ width: 1, color: this.busy ? '#e6a700' : '#28a745', radius: 3 })
            .padding({ left: 3, right: 3, top: 1, bottom: 1 })
          Text('⌘K').fontSize(8).fontColor('#aeaeb2')
          Row({ space: 5 }) {
            ForEach(this.chips.slice(0, 3), (c: string) => {
              Text(c).fontSize(8.5).fontColor(TX2)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor('rgba(0,0,0,0.04)').borderRadius(8)
                .onClick(() => {
                  if (c.includes('Web 登录')) this.addTpl('web_login');
                  else if (c.includes('手机')) this.addTpl('login');
                  else if (c.includes('仪表盘')) this.addTpl('dashboard');
                })
            }, (c: string) => c)
          }
          Blank()
          Text(this.dirty ? '未保存' : '已同步').fontSize(8).fontColor(this.dirty ? '#e6a700' : '#aeaeb2')
          TextInput({ placeholder: '描述意图（如：生成 Web 登录页 / 一键修复 / 深色主题）…', text: this.prompt })
            .onChange((v: string) => { this.prompt = v; })
            .onSubmit(() => this.runPrompt())
            .layoutWeight(1).height(28).fontSize(10.5).borderRadius(6)
            .backgroundColor('#fff').border({ width: 1, color: LINE })
          Text('↩ 撤销').fontSize(8.5).fontColor(TX2).onClick(() => this.undo())
          Button('一键生成').fontSize(10).fontColor('#fff').backgroundColor(ACC)
            .borderRadius(6).height(28)
            .onClick(() => this.runPrompt())
        }.width('100%').height(40).padding({ left: 10, right: 10 })
        .backgroundColor(PANEL).alignItems(VerticalAlign.Center)
      }.backgroundColor(PANEL)
    }.width('100%').height('100%').backgroundColor(BG)
    .bindSheet($$this.showSettings, this.settingsSheet(), { height: 440, dragBar: true })
  }

  @Builder
  settingsSheet() {
    Column({ space: 10 }) {
      Text('设置').fontSize(15).fontWeight(700).fontColor(TX)
      Divider().color(LINE)
      Column({ space: 9 }) {
        Row() {
          Text('Agent 执行者').fontSize(11.5).fontColor(TX)
          Blank()
          Text(this.xiaoyiState).fontSize(9.5)
            .fontColor(this.xiaoyiState.includes('就绪') ? '#28a745' : TX2)
        }.width('88%')
        Row() {
          Text('端侧小艺（localChatModel）').fontSize(10).fontColor(TX2)
          Blank()
          Text('系统级 · 数据不出设备').fontSize(9).fontColor(TX2)
        }.width('88%')
        Row() {
          Text('云端回退').fontSize(10).fontColor(TX2)
          Blank()
          Text('设置 API Key 后启用').fontSize(9).fontColor(TX2)
        }.width('88%')
        Divider().color(LINE).width('88%')
        Row() {
          Text('引擎').fontSize(11.5).fontColor(TX)
          Blank()
          Text('moonviz · wasmtime 宿主 L1 下沉中').fontSize(9.5).fontColor(TX2)
        }.width('88%')
        Row() {
          Text('DDP 加密').fontSize(11.5).fontColor(TX)
          Blank()
          Text('Argon2id + XChaCha20 · 已接通').fontSize(9.5).fontColor('#28a745')
        }.width('88%')
        Row() {
          Text('Rust core').fontSize(11.5).fontColor(TX)
          Blank()
          Text(this.coreTag).fontSize(8).fontColor(TX2).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 170 })
        }.width('88%')
      }.width('100%').alignItems(HorizontalAlign.Center)
      Button('完成').fontSize(11.5).fontColor('#fff').backgroundColor(ACC).borderRadius(8)
        .width(110).margin({ top: 6 })
        .onClick(() => { this.showSettings = false; })
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
  }
}
