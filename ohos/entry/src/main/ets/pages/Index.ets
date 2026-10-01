// deepDesign Studio —— 鸿蒙原生交互层（ArkUI）
// 后端 = Rust（NAPI，见 core/CoreBridge）；UI = ArkUI 原生组件。
// 布局对标桌面版：顶栏 / 左侧面板 / 中央画布 / 右侧属性 / 底部 Agent 指令条。

import { coreVersion, corePing } from '../core/CoreBridge';
import { xiaoyiAI } from '../ai/XiaoyiProvider';
import { appStore, Board } from '../model/AppStore';

interface Tpl {
  title: string;
  kind: string;
  sub: string;
  width: number;
  height: number;
}

type ProbeResultAlias = import('../ai/XiaoyiProvider').ProbeResult;

const BG = '#f2f3f7';
const TX = '#1c1c1e';
const TX2 = '#636366';
const PANEL = '#ffffff';
const ACC = '#007aff';

@Entry
@Component
struct Index {
  @State coreVersion: string = '...';
  @State corePong: string = '';
  @State selectedTab: number = 0;
  @State promptText: string = '';
  @State aiBackend: string = '探测中…';
  @State boards: Board[] = appStore.boards;
  @State showSettings: boolean = false;
  @State themeDark: boolean = false;
  @State selectedBoard: Board | null = null;
  tpls: Tpl[] = [
    { title: '登录页', kind: 'mobile', sub: 'mobile · 390 × 844', width: 390, height: 844 },
    { title: 'Web 登录', kind: 'web', sub: 'web · 1280 × 800', width: 1280, height: 800 },
    { title: '自适应落地页', kind: 'adaptive', sub: 'adaptive · 1280 × 800', width: 1280, height: 800 }
  ];

  aboutToAppear(): void {
    try {
      this.coreVersion = coreVersion();
      this.corePong = corePing('handshake');
    } catch (e) {
      this.coreVersion = 'NAPI 未加载（签名后启用）';
    }
    xiaoyiAI.probe().then((r: ProbeResultAlias) => {
      this.aiBackend = r.available ? r.backend : '不可用（云端回退）';
    });
  }

  addTpl(t: Tpl): void {
    appStore.addBoard(t.title, t.kind, t.width, t.height);
    this.boards = appStore.boards.slice();
  }

  build() {
    Column() {
      // ---- 顶栏 ----
      Row() {
        Text('deepDesign').fontWeight(700).fontSize(15)
        Text('STUDIO').fontSize(9).fontWeight(600).letterSpacing(1.2)
          .fontColor(TX2).margin({ left: 5 })
        Text('v0.4.0-β · harmonyos').fontSize(10).fontColor(TX2).margin({ left: 10 })
        Blank()
        Text(`core: ${this.coreVersion}`).fontSize(10).fontColor(TX2)
          .maxLines(2).textAlign(TextAlign.End)
        Button('设置')
          .fontSize(12).backgroundColor(PANEL).fontColor(TX)
          .border({ width: 1, color: BG }).borderRadius(6).height(28)
          .margin({ left: 10 })
          .onClick(() => { this.showSettings = true })
      }
      .width('100%').height(46).padding({ left: 14, right: 14 })
      .backgroundColor(PANEL).alignItems(VerticalAlign.Center)

      // ---- 主体三栏 ----
      Row() {
        Column() {
          Text(appStore.projectName).fontSize(13).fontWeight(600).fontColor(TX)
            .margin({ bottom: 8 })
          Row() {
            Text('+ 新建').fontSize(12).fontColor(ACC)
              .onClick(() => { this.addTpl(this.tpls[0]) })
            Blank()
            Text('打开…').fontSize(12).fontColor(TX2)
          }.width('100%')

          Row({ space: 12 }) {
            Text('图层').fontSize(12).fontWeight(this.selectedTab === 0 ? 700 : 400)
              .fontColor(this.selectedTab === 0 ? ACC : TX2)
              .onClick(() => { this.selectedTab = 0 })
            Text('AI 组件').fontSize(12).fontWeight(this.selectedTab === 1 ? 700 : 400)
              .fontColor(this.selectedTab === 1 ? ACC : TX2)
              .onClick(() => { this.selectedTab = 1 })
            Text('流程').fontSize(12).fontWeight(this.selectedTab === 2 ? 700 : 400)
              .fontColor(this.selectedTab === 2 ? ACC : TX2)
              .onClick(() => { this.selectedTab = 2 })
          }.margin({ top: 12, bottom: 6 })

          if (this.selectedTab === 0) {
            List({ space: 4 }) {
              ForEach(this.boards, (b: Board) => {
                ListItem() {
                  Column() {
                    Row() {
                      Text(b.name).fontSize(11).fontColor(TX)
                      Blank()
                      Text(`${this.boards.length}`).fontSize(11).fontColor(TX2)
                    }.width('100%')
                    Text(`${b.kind} · ${b.width} × ${b.height}`)
                      .fontSize(10).fontColor(TX2).margin({ top: 2 })
                  }.width('100%').padding(6)
                }
              }, (b: Board) => b.id)
            }
            .width('100%').height(160)
            if (this.boards.length === 0) {
              Text('无画板 — 点下方模板卡或 Prompt 生成').fontSize(11).fontColor(TX2)
                .margin({ top: 10 })
            }
          } else if (this.selectedTab === 1) {
            Text('AI 组件库（拖入画布复用）').fontSize(11).fontColor(TX2).margin({ top: 10 })
          } else {
            Text('交互流绑定').fontSize(11).fontColor(TX2).margin({ top: 10 })
          }
          Blank()
        }
        .width(220).height('100%').padding(12)
        .backgroundColor(PANEL).border({ width: { right: 1 }, color: BG })
        .alignItems(HorizontalAlign.Start)

        // 中央画布
        Column() {
          if (this.boards.length > 0) {
            Scroll() {
              Column({ space: 12 }) {
                ForEach(this.boards, (b: Board) => {
                  Column() {
                    Row() {
                      Text(b.name).fontSize(13).fontWeight(600).fontColor(TX)
                      Blank()
                      Text(`${b.kind} · ${b.width} × ${b.height}`).fontSize(10).fontColor(TX2)
                    }.width('100%')
                    // 画板缩略占位（按声明比例的迷你预览）
                    Column() {
                      Text(b.name).fontSize(10).fontColor(TX2)
                    }
                    .width(b.width > b.height ? 160 : 100)
                    .height(b.width > b.height ? 100 : 160)
                    .backgroundColor(PANEL).borderRadius(6)
                    .border({ width: 1, color: BG })
                  }
                  .width('100%').padding(12).backgroundColor(PANEL).borderRadius(10)
                  .shadow({ radius: 6, color: 'rgba(0,0,0,0.08)' })
                  .onClick(() => { this.selectedBoard = b })
                }, (b: Board) => b.id)
              }.width('100%').padding(12)
            }
            .layoutWeight(1).scrollBar(BarState.Auto)
          } else {
            Column() {
              Text('未打开画板').fontSize(12).fontColor(TX2)
              Column() {
                Text('从 deepDesign 开始').fontSize(18).fontWeight(700).fontColor(TX)
                Text('选择模板即刻开始，或按 Ctrl+K 直接对 Agent 下令').fontSize(12)
                  .fontColor(TX2).margin({ top: 8 })
                Row({ space: 12 }) {
                  ForEach(this.tpls, (t: Tpl) => {
                    Column() {
                      Text(t.title).fontSize(12).fontWeight(600).fontColor(TX)
                      Text(t.sub).fontSize(10).fontColor(TX2).margin({ top: 4 })
                    }
                    .width(120).height(80).justifyContent(FlexAlign.Center)
                    .backgroundColor(PANEL).borderRadius(8)
                    .shadow({ radius: 6, color: 'rgba(0,0,0,0.08)' })
                    .onClick(() => { this.addTpl(t) })
                  }, (t: Tpl) => t.title)
                }.margin({ top: 24 })
              }
              .justifyContent(FlexAlign.Center)
              .width('100%').height('100%')
            }
          }
        }
        .layoutWeight(1).height('100%').backgroundColor(BG)
        .alignItems(HorizontalAlign.Center)

        // 右侧属性面板
        Column() {
          Row() {
            Text('属性').fontSize(13).fontWeight(600)
            Blank()
            Text('Agent 追踪').fontSize(12).fontColor(TX2)
          }.width('100%')
          Divider().margin({ top: 8 })
          Column() {
            Text('未选中元素').fontSize(14).fontWeight(600).fontColor(TX)
            Text('在画布中点选任意元素\n属性与交互将在此显示').fontSize(12).fontColor(TX2)
              .margin({ top: 10 }).textAlign(TextAlign.Center)
          }.margin({ top: 60 })
          Blank()
          Column() {
            Text('端侧 AI').fontSize(11).fontWeight(600).fontColor(TX2)
            Text(this.aiBackend).fontSize(11).fontColor(TX2).margin({ top: 4 })
            Text(`core: ${this.coreVersion}`).fontSize(10).fontColor(TX2).margin({ top: 8 })
          }.alignItems(HorizontalAlign.Start).margin({ bottom: 12 })
        }
        .width(240).height('100%').padding(12)
        .backgroundColor(PANEL).border({ width: { left: 1 }, color: BG })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)

      // ---- 底部 Agent 指令条 ----
      Row() {
        Text('READY').fontSize(10).fontWeight(700).fontColor('#28a745')
          .border({ width: 1, color: '#28a745', radius: 4 }).padding(3)
        Text('三条输入汇入同一命令流：人类拖拽 · Agent 指令 · 模板')
          .fontSize(10).fontColor(TX2).margin({ left: 8 })
        Blank()
        TextInput({ placeholder: '描述意图（如：生成 Web 登录页 / 一键修复）…', text: this.promptText })
          .onChange((v: string) => { this.promptText = v })
          .width(420).height(30).fontSize(12).borderRadius(6)
        Button('生成')
          .fontSize(12).fontColor('#fff').backgroundColor(ACC)
          .borderRadius(6).height(30).margin({ left: 8 })
      }
      .width('100%').height(40).padding({ left: 14, right: 14 })
      .backgroundColor(PANEL).alignItems(VerticalAlign.Center)
    }
    .width('100%').height('100%').backgroundColor(BG)
  }
}
