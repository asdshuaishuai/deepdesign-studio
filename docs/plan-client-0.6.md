# 客户端 v0.6 路线（下一版本方向）

> 状态：**规划（2026-11-04 定稿，待施工）**。下一次迭代按这份走。
> 边界：客户端是**壳**——只做桌面体验与编排，不重复实现设计逻辑；一切视觉语义、
> 规范裁决、生成与校验以引擎（MoonViz wasm）为准。引擎路线见引擎仓库 `ROADMAP.md`，
> 不在本文范围。

## 背景：v0.5.0-fix 之后的真实缺口

0.5.0-fix 把「规范驱动生成、交互/内容 QA、空文档零种子、可读性硬标准」接进了产品，
但客户端仍有四类确定性缺口（按「收益 ÷ 前置依赖」排序）：

1. 设计规范只能靠 Agent 隐式书写，用户无法可视化编辑/预览（引擎 0.2 会扩
   Style Profile，客户端没有承载面）；
2. 原型只能本机看，没有免安装的只读分享通道（`export_html` 已就绪，纯壳层可做）；
3. 分发与密钥安全不达标（ad-hoc 签名导致 Gatekeeper「已损坏」、TCC 授权失效；
   API Key 明文存 localStorage）；
4. 引擎能力（组件注册表持久化 / animation / prototest / collab / history）就绪后，
   客户端没有对应面板——需要按引擎节奏分批接入。

## P0（先做：收益最高、依赖已就绪）

### 1. 设计规范工作台（DESIGN.md + Style Profile）

- **依赖**：引擎 0.2 视觉语言线（tokens surface tint / elevation / accent 角色、
  `style: calm | vivid | editorial | playful` 进 design spec）。
- **内容**：
  - DESIGN.md 面板支持 `palette / typography / spacing / radius / rules` 的可视化编辑
    与预览；新增 Style Profile 选择器（calm / vivid / editorial / playful）。
  - 生成时把 profile + palette 作为 `spec=` 传入（现有链路已支持），
    `spec_violations` 在 Agent 轨迹里逐条呈现（可点击定位到节点）。
  - 规范缺失时展示引擎 `design_spec_draft`，一键落盘为 DESIGN.md（Agent 仍可改写）。
- **验收**：同一 intent 切换 profile 出稿，留白率/彩积比/elevation 分布可量化区分；
  改 spec 后下一次 `generate` 立即生效；旧项目无 spec 时行为与现在一致（calm 缺省）。

### 2. 内网只读分享（LAN share）

- **依赖**：`export_html` 已就绪（纯壳层）。
- **内容**：导出单文件 HTML + 内嵌只读 HTTP 服务；`serve-fresh-per-GET`（每次 GET
  重渲染，杜绝缓存污染）；访问口令；防目录穿越 / CSRF / 速率限制；分享链接 + 二维码；
  服务生命周期（手动启停 + 超时自动关闭）。
- **验收**：手机同网扫码即看；改文档后刷新即新；安全清单逐条锚定
  （见 `docs/plan-lan-share.md` 的既有设计）。

### 3. 安全与分发

- **内容**：API Key 从 localStorage 迁移 OS keychain（macOS Keychain / Windows
  Credential Manager / libsecret）；macOS **Developer ID 签名 + 公证**（解决
  Gatekeeper「已损坏」与每次重建后 TCC 授权失效）；Windows 代码签名。
- **验收**：全新机器双击即开、无「已损坏」弹窗、无 TCC 重复授权；密钥不出现在
  前端存储与日志。

## P1（等引擎能力就绪后按序接入）

| 方向 | 内容 | 前置（引擎侧） |
| --- | --- | --- |
| 用户组件库持久化 | 画板沉淀为组件、MCF 导入导出闭环；我的组件分组/搜索/拖放；用户组件纳入规范与门校验 | 组件注册表持久化模型定案 |
| 动效预览 | 演示模式实时播放引擎动画（时间线/缓动），与设计稿同源 | `animation` wasm 会话面 |
| 原型测试面板 | 断言式验证导航/输入/渲染/违规，可视化运行与失败定位 | `prototest` wasm 会话面 |
| 多窗口冲突检测 | 同项目多窗口：文件锁 + revision 比对 + 冲突提示（不静默覆盖）；collab 落地后接 OT 冲突的显式呈现 | `collab` wasm 会话面 |
| 全局撤销 | 跨画板线性撤销栈（当前按画板分栈）；打开项目/Agent 终态作为边界 | `history` 持久化方向明确 |

## P2（跟随引擎与生态）

- **DDP v2 多段容器兼容**：旧 DDP1 打开、新容器导出，`.mbt.md` 单源不变
  （跟随引擎 P1–P5 规划）。
- **可访问性与键盘全链路**：Tab 焦点序、对话框语义、快捷键帮助面板。
- **性能基线进客户端 CI**：画布渲染/预览帧/大文档打开的基准回归。

## 明确不做（本轮）

- **A2UI / AUI 协议接入**：已放弃（2026-11-04 决策）。GenUI 为自研协议，
  跨端能力以引擎 wasm 契约为准。
- **客户端重复实现设计逻辑**：genUI / norms / QA / token 一律归引擎；
  客户端不得在前端或 Rust 里解释视觉语义（架构硬边界，见 AGENTS.md）。

## 施工纪律

- 每项开工前先确认**前置依赖是否真的可用**（引擎会话面/导出面以契约为准，不靠推测）。
- 触碰 `frontend/index.html` 的改动必须过 `node test_studio.cjs`（40 项契约检查）；
  Rust 侧改动过 `cargo test`；引擎产物变化先跑 `node scripts/sync-engine.mjs` 探针。
- 版本号只改 `VERSION` 后跑 `node scripts/sync-version.mjs`。
