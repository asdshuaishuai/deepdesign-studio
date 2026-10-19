---
name: 引擎问题
about: MoonViz 引擎的行为缺陷或能力缺口（渲染 / 布局 / 规范 / 交互语义 / 门校验）
title: "[Engine] "
labels: engine
---

> **注意**：若确认是引擎层问题（而非工作台层），请优先提到引擎仓库：
> https://github.com/asdshuaishuai/moonviz/issues
> 本模板用于「不确定归属」或「需要工作台侧配合」的情况。

## 问题描述

## 真机证据（必须）

引擎问题必须有**真机证据**，不接受推测性报告：

- 最小复现的 op 序列（或 `.mbt.md` 文档片段）：
- 引擎返回的 JSON 原文（经 `frontend/vendor/moonviz.wasm` 直跑；可用
  `node scripts/engine-host.mjs` 行协议复现）：

```json
（粘贴引擎返回原文）
```

## 对照路径

<!-- 人类门（apply_human_op）与代理门（apply_agent_op）表现是否不同？
     单 op 与整篇提交（apply_agent_mbt）表现是否不同？ -->

- 人类门：
- 代理门：

## 环境

- 引擎版本（`engine-manifest.json`）：
- deepDesign 版本：
