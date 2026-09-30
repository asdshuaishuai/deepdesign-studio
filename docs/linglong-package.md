# 玲珑包（如意玲珑 / Linyaps）适配方案

> 状态：**仅方案，未实施**。目标：deepDesign Studio 以玲珑包形态分发到
> deepin V23+ / UOS 1070+（x86_64 优先，arm64 可选），并上架玲珑应用商店。
> 事实核查日期：2026-09-29（来源见文末）。

## 1. 结论先行

技术阻力小：Tauri 2 在 Linux 的 deb 产物是现成起点，官方推荐的
`deb → ll-pica 转制（生成 linglong.yaml）→ ll-builder 构建导出` 链路能覆盖 90% 的工作。
真正要花心思的是两件事：

1. **webkit2gtk 依赖怎么进沙箱**——体积与兼容性的核心矛盾；
2. **沙箱内文件访问 / 中文输入法 / CJK 字体**的可用性。

## 2. 已核实的关键事实（2026-09-29 检索）

- Tauri 2 Linux 端依赖 **webkit2gtk-4.1**（v2 官方迁移说明）。
- 玲珑工具链齐备：`ll-builder`（构建/导出）、`ll-cli`（沙箱安装运行）、
  `ll-pica`（deb/appimage/flatpak → 玲珑，自动生成 linglong.yaml）、
  `ll-publisher`（推商店）。
- deepin 官方"玲珑 10 分钟快速构建指南"主推的正是 deb 转制路线。
- 社区 SIG 已做 **GTK4 + WebKit2GTK 共享运行时组件**，专门解决 Tauri 类应用玲珑包
  200MB+ 的体积问题（linyaps.org.cn 2025-09 报道）——依赖共享运行时层是控体积的关键。
- 玲珑跨发行版：deepin/UOS 之外，Ubuntu/Debian/Fedora/Arch 等可装运行时
  （2026-07 报道：7000+ 应用，商店已进多发行版）。
- 基础层现状有 `org.deepin.foundation/23`、`org.deepin.base/23` 等，社区对分层演进
  仍有讨论（重复/归并议题）——引用哪个层要跟社区对齐后钉死版本。

## 3. 路线：两步走

### 路线 A（推荐）：deb 转制

1. Linux CI 出 deb（`tauri.conf.json` 的 bundle targets 加 `"deb"`）；
2. `ll-pica` 转制生成 `linglong.yaml` 骨架；
3. 手工调优：`command`、运行时层引用、环境变量（输入法模块、渲染兜底）；
4. `ll-builder build` / `export` → `ll-cli install/run` 本机验证；
5. `ll-publisher` 推玲珑商店。

本文**不手写 linglong.yaml 全量示例**——字段与工具版本强相关，以 ll-pica 实际生成物
为准绳，避免文档漂移。包 id 用 `com.deepcode.deepdesign`（对齐 tauri identifier），
版本随 `tauri.conf.json`（当前 0.3.x）。

### 路线 B（备选）：源码直构

`linglong.yaml` 的 source/build 直接跑 cargo + tauri-cli。可控性最高，但构建机依赖重：
node + GitHub 拉 wasm（`beforeBuildCommand` 的网络依赖在玲珑构建机上同样存在，需预置
vendor 产物或走代理）。除非转制路线受阻，否则不选。

## 4. 技术要点与风险（按优先级）

1. **webkit2gtk 进沙箱（本方案最大的待验证点）**：二选一——
   - (a) 引用社区 GTK4+WebKit 共享运行时层：体积优，但版本跟社区走，且
     **webkit2gtk-4.1 与 GTK4 侧 webkitgtk-6.0 的 API/链接面差异需实测**；
   - (b) deb 自带依赖整包打入：简单可靠，代价是 200MB+。
   推荐先走 (a)，P0 第一件事就是拿社区层的包清单对版本、真机跑一晚定结论；
   不行再退 (b)，功能不受影响只是包大。
2. **沙箱文件访问**：DDP 保存/打开走文件选择器 + 用户授权目录；应用数据
   （localStorage 里的最近项目注册表 / apiKey 槽位、agent 日志）落沙箱持久目录。
   玲珑对 HOME 的授权模型要实测——最近项目按绝对路径对账（`list_ddp_projects`），
   沙箱路径映射的稳定性直接影响多项目体验。
3. **中文字体**：画布 SVG 文本渲染依赖 CJK 字体；沙箱内若无则需运行时层带
   Noto CJK 类字体，否则预览与 `export-svg` 产物字体漂移。
4. **输入法**：fcitx/ibus 透传（`GTK_IM_MODULE` 等环境变量），玲珑沙箱通常已处理，
   列入验收项而非开发项。
5. **GPU/渲染**：WebView 硬件加速走宿主 GPU，沙箱设备节点一般可用；异常时
   `WEBKIT_DISABLE_COMPOSITING_MODE=1` 兜底（性能降级，验收时标注）。
6. **CI**：现有 `windows-build.yml` 仅 tag/手动触发。加 ubuntu job：
   装 webkit2gtk-4.1-dev + rust(MSVC 无关，Linux 用默认 GNU 即可) + node →
   `tauri build --bundles deb` → ll-pica / ll-builder（建议容器化跑，工具链版本可复现）→
   产 lpkg 工件。**Linux 上先跑 `cargo test` + `node test_studio.cjs`**——引擎契约
   测试在 Linux 原生可跑，等于免费多一个平台对账。

## 5. 验收清单（真机 deepin V23 + UOS 1070 各一台）

- [ ] 安装/启动/卸载干净（`ll-cli run` 无残留报错，卸载无孤儿数据）
- [ ] 新建/打开/保存 DDP（含中文路径与中文口令）
- [ ] 完整 agent run：LLM 出网、轨迹时间线、preview 刷新、澄清式多轮
- [ ] 画布中文渲染 + `export-svg` 字体一致
- [ ] fcitx 中文输入（画布内联编辑 + 提示词栏）
- [ ] localStorage 持久（重启后最近项目 / API key 还在）
- [ ] 离线启动（无网时打开本地 DDP 正常）
- [ ] 键盘快捷键（Ctrl+Z 撤销、Ctrl+S 保存）

## 6. 事实来源

- deepin 官方"玲珑 10 分钟快速构建指南"（deb 转制 + ll-builder 链路）
- linyaps.org.cn 社区报道：2025-09（GTK4+WebKit2GTK 运行时组件 / Tauri 体积优化）、
  2026-07（跨发行版 7000+ 应用）
- v2.tauri.app：Linux 端 webkit2gtk-4.1 迁移说明
- 检索日期 2026-09-29；"Tauri 无官方玲珑支持"为当日结论，官方若出 Linux 沙箱指南可再对齐
