# 贡献指南（Contributing to deepDesign Studio）

感谢你对 deepDesign Studio 的关注！本文档说明参与贡献的方式与必须遵守的工程纪律。

## 目录

- [开始之前](#开始之前)
- [开发环境](#开发环境)
- [分支纪律](#分支纪律)
- [提交信息规范](#提交信息规范)
- [测试要求](#测试要求)
- [Pull Request 流程](#pull-request-流程)
- [架构边界（改代码前必读）](#架构边界改代码前必读)
- [报告问题](#报告问题)

---

## 开始之前

deepDesign Studio 是 [MoonViz 引擎](https://github.com/asdshuaishuai/moonviz)的桌面工作台。
两个仓库均为 MIT 开源、独立演进：

- **本仓库**（deepdesign-studio）：Tauri 2 + Rust 桌面客户端，前端单文件静态页。
- **引擎仓库**（moonviz）：纯 MoonBit 引擎，以**预编译 wasm 产物**集成到本仓库。

引擎的 bug 或能力缺口请提到[引擎仓库 issue](https://github.com/asdshuaishuai/moonviz/issues)，
附带真机证据（最小复现探针 + 引擎返回 JSON 原文）。本仓库不硬扛引擎缺陷。

## 开发环境

前置依赖：**Rust**（Windows 需 MSVC 工具链）· **Node**（构建脚本与测试宿主）。
仓库自包含——引擎是预编译产物、DDP codec 已 vendored，**不需要 MoonBit 工具链**。

```bash
git clone https://github.com/asdshuaishuai/deepdesign-studio.git
cd deepdesign-studio

node scripts/sync-engine.mjs      # 1. 拉取引擎 wasm 产物（sha512 校验 + 契约探针）
cd src-tauri && cargo build       # 2. 构建（实测冷编译约 60s）
cargo test                        # 3. 测试（47 个测试，全绿是基线）
cd .. && node test_studio.cjs     # 4. 前端契约测试

./dev.sh --fresh                  # 开发运行（macOS/Linux；Windows 用 dev.bat）
```

## 分支纪律

| 分支 | 用途 |
|---|---|
| **`dev`** | **开发分支**——所有日常开发提交都落在这里。拉取代码、改动、测试都在 dev 上做 |
| **`main`** | **发布分支**——只接受从 dev 合并的发布内容，用于打 tag 与构建正式产物。不要在 main 上直接开发 |

发布流程：`dev` 改完并验证 → 合并 `dev` 进 `main` → main 上打 tag `v*` →
GitHub Actions 自动构建三平台产物并附到 Release。

从 `dev` 建特性分支开发，完成后 PR 回 `dev`。

## 提交信息规范

使用 [Conventional Commits](https://www.conventionalcommits.org/) + **英文 subject**：

```
feat(agent): add streaming tool-call preview
fix(studio): restore sess binding in attachPlayHotZones
chore: bump engine artifact to 0.1.9
docs: record rebase design decisions
```

常用 scope：`agent` / `studio` / `ui` / `engine` / `bundle`。

正文说明**为什么**（what/why），不是 what 的逐行复述。涉及行为变更时写明验证方式。

## 测试要求

**所有改动必须通过现有测试；行为变更必须附带新测试。**

```bash
cd src-tauri && cargo test    # Rust：单元 + 契约 + 端到端（含 mock-LLM × 真 wasm）
node test_studio.cjs          # 前端：静态断言 + 状态机动态切片
```

测试纪律（本项目的重要工程约定）：

1. **测试必须真的能红**。新增防线若声称守护某性质，必须做**变异验证**——
   故意注入缺陷确认测试变红，再还原。
2. **合法跳过 vs 静默失败**：wasm 产物缺失 → 合法跳过（打印提示）；产物在场但
   宿主/编解码损坏 → 必须失败。绝不把损坏伪装成绿灯。
3. **字符串锚定测试写位置断言**，不只写存在性断言——「挪了位置」的变异必须能被抓住。

## Pull Request 流程

1. Fork 或直接在仓库建分支（成员），分支从 `dev` 切出。
2. 完成改动 + 测试，确保 `cargo test` 与 `node test_studio.cjs` 全绿。
3. 开 PR 到 `dev`，填写 PR 模板（变更说明 / 测试方式 / 关联 issue）。
4. 维护者审查。审查关注：**架构边界**（见下节）、测试有效性、是否引入重复实现。
5. Squash 合并，保持提交历史整洁。

## 架构边界（改代码前必读）

违反这些边界的 PR 不会被合并——它们是本项目「AI 生成的设计可信可控」的根基：

1. **唯一事实源**：人类画布操作与 Agent 修改都必须经引擎门（HumanGate / AgentGate）
   校验后回写同一份 `.mbt.md` 文档。**不要在前端本地改数据结构了事**。
2. **Rust 不解释视觉语义**：Rust 层只做三件事——b64 搬运、wasmtime 宿主、DDP 加解密。
   任何「顺手在 Rust 里改一下布局/属性」的做法都越界了——变更必须回到引擎。
3. **前端无 HTTP 层**：前端只能经 `window.__TAURI__.core.invoke` 调 Tauri 命令。
   不要引入 fetch/axios。
4. **双门语义分离**：人类路径与 Agent 路径走不同引擎入口，语义差异由门实现，
   不要绕过门直接改数据。
5. **引擎能力对账**：引擎更新后，`frontend/index.html` 与 `agent.rs` 的硬编码能力面
   要回来对账（契约测试会锚定模板清单/组件快照/导出面）。

完整架构说明与历史事故登记见 [`AGENTS.md`](AGENTS.md)（仓库最高指令源，改代码前必读）。

## 报告问题

- **Bug**：用 issue 模板提交，附最小复现步骤、环境（OS / 版本号）、
  预期与实际行为。崩溃/异常请附日志（agent 运行日志在
  `~/Library/Application Support/com.deepcode.deepdesign/logs/`）。
- **引擎问题**：提到 [moonviz 仓库](https://github.com/asdshuaishuai/moonviz/issues)，
  附真机探针证据。
- **安全漏洞**：不要开公开 issue，见 [`SECURITY.md`](SECURITY.md)。

## 开源协议

本项目以 MIT 协议开源。提交贡献即表示你同意你的贡献以同一协议授权
（inbound = outbound）。请勿提交带有不兼容许可（GPL 等强 copyleft）的代码。
