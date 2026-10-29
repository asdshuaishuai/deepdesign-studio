## 变更说明

<!-- 这个 PR 做了什么、为什么。关联 issue：Fixes #... -->

## 变更类型

- [ ] 缺陷修复（fix）
- [ ] 新功能（feat）
- [ ] 重构（refactor）
- [ ] 文档（docs）
- [ ] 构建 / 依赖（chore）

## 测试

<!-- 必填：说明你如何验证。行为变更必须附带测试 -->

- [ ] `cd src-tauri && cargo test` 全绿
- [ ] `node test_studio.cjs` 全绿
- [ ] 新增/修改的防线做过**变异验证**（故意注入缺陷确认变红后还原）——如有
- [ ] 涉及前端 UI 的改动已在 `./dev.sh --fresh` 下人工冒烟

## 架构边界自查

- [ ] 未绕过引擎门直接改数据结构（人类 op 走 HumanGate、Agent op 走 AgentGate）
- [ ] Rust 层未引入视觉语义解释（只做 b64 搬运 / wasmtime 宿主 / DDP 加解密）
- [ ] 前端未引入 HTTP 层（只用 Tauri invoke）
- [ ] 引擎能力面硬编码（模板清单/组件快照/导出面）如有变化，已同步契约测试与 `AGENTS.md`

## 文档

- [ ] 行为/架构变化已在 `AGENTS.md` 或 `docs/` 相应登记
- [ ] 如涉及版本号：改的是仓库根 `VERSION` 并经 `node scripts/sync-version.mjs` 同步（未手改下游面）
