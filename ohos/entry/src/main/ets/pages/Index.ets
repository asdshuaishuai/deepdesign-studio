// deepDesign Studio —— 鸿蒙原生交互层（ArkUI）
//
// 架构：后端 = Rust（wasmtime 引擎宿主 + Agent 循环，经 NAPI 暴露）；
//       前端 = ArkUI 原生组件（本文件），替代 ArkWeb/HTML 方案。
// 布局对标桌面版：顶栏 / 左侧面板（图层·AI组件·流程）/ 中央画布 / 右侧属性 / 底部 Agent 指令条。
// 状态管理：@State 本地态；核心数据后续由 Rust core 经 NAPI 推送。

import { coreVersion, corePing } from '../core/CoreBridge';
import { xiaoyiAI } from '../ai/XiaoyiProvider';

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
  @State selectedTab: number = 0;       // 0 图层 1 AI组件 2 流程
  @State promptText: string = '';
  @State aiBackend: string = '探测中…';
  @State boards: number = 0;

  aboutToAppear(): void {
    // NAPI 链路自检：Rust core 经 .so 直达 ArkTS
    try {
      this.coreVersion = coreVersion();
      this.corePong = corePing('handshake');
    } catch (e) {
      this.coreVersion = `NAPI load failed: ${(e as Error).message}`;
    }
    xiaoyiAI.probe().then((r: ProbeResultAlias) => {
      this.aiBackend = r.available ? r.backend : '不可用（云端回退）';
    });
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
        Text(`core: ${this.corePong === '' ? this.coreVersion : this.corePong}`)
          .fontSize(10).fontColor(TX2).maxLines(1)
      }
      .width('100%').height(46).padding({ left: 14, right: 14 })
      .backgroundColor(PANEL).alignItems(VerticalAlign.Center)

      // ---- 主体三栏 ----
      Row() {
        // 左侧面板
        Column() {
          Text('未命名项目').fontSize(13).fontWeight(600).fontColor(TX)
            .margin({ bottom: 8 })
          Row() {
            Text('+ 新建').fontSize(12).fontColor(ACC)
            Blank()
            Text('打开…').fontSize(12).fontColor(TX2)
          }.width('100%')

          Row({ space: 12 }) {
            this.tabBtn('图层', 0)
            this.tabBtn('AI 组件', 1)
            this.tabBtn('流程', 2)
          }.margin({ top: 12, bottom: 6 })

          if (this.selectedTab === 0) {
            Row() {
              Text('画布页面').fontSize(11).fontColor(TX2)
              Blank()
              Text(`${this.boards}`).fontSize(11).fontColor(TX2)
            }.width('100%').margin({ top: 8 })
            Text('无画板 — 点下方模板卡或 Prompt 生成').fontSize(11).fontColor(TX2)
              .margin({ top: 10 })
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
          Text('未打开画板').fontSize(12).fontColor(TX2)
          Column() {
            Text('从 deepDesign 开始').fontSize(18).fontWeight(700).fontColor(TX)
            Text('选择模板即刻开始，或按 Ctrl+K 直接对 Agent 下令').fontSize(12)
              .fontColor(TX2).margin({ top: 8 })
            Row({ space: 12 }) {
              this.tplCard('登录页', 'mobile · 390 × 844')
              this.tplCard('Web 登录', 'web · 1280 × 800')
              this.tplCard('自适应落地页', 'adaptive · 1280 × 800')
            }.margin({ top: 24 })
          }
          .justifyContent(FlexAlign.Center)
          .width('100%').height('100%')
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

  @Builder
  tabBtn(label: string, idx: number) {
    Text(label)
      .fontSize(12).fontWeight(this.selectedTab === idx ? 700 : 400)
      .fontColor(this.selectedTab === idx ? ACC : TX2)
      .onClick(() => { this.selectedTab = idx })
  }

  @Builder
  tplCard(title: string, sub: string) {
    Column() {
      Text(title).fontSize(12).fontWeight(600).fontColor(TX)
      Text(sub).fontSize(10).fontColor(TX2).margin({ top: 4 })
    }
    .width(120).height(80).justifyContent(FlexAlign.Center)
    .backgroundColor(PANEL).borderRadius(8)
    .shadow({ radius: 6, color: 'rgba(0,0,0,0.08)' })
  }
}

type ProbeResultAlias = import('../ai/XiaoyiProvider').ProbeResult;
