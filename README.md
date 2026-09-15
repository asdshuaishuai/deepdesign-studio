# deepDesign Studio

AI 原生原型设计工具的桌面客户端（Tauri 2）。基于 [MoonViz](https://github.com/asdshuaishuai/moonviz) 纯 MoonBit 引擎：唯一事实源是 `.mbt.md` 文档，人类画布操作与 Agent 修改都必须经引擎校验（HumanGate / AgentGate）后回写同一文档。

## 架构

```
前端 (frontend/index.html, 纯静态)
  ├─ 多画板画布 / 组件库 / decl 源码视图 / 演示模式
  └─ 全部经 Tauri invoke（无 HTTP 层）
Rust 后端 (src-tauri)
  ├─ exec_cli — 引擎管道（用户组件库 restore/snapshot 写回）
  ├─ agent   — 进程内 Agent 循环（OpenAI chat-completions 工具调用）
  └─ save_ddp/open_ddp — DDP 加密容器读写
引擎 (engine/moonviz-cli.exe, 随包分发)
  └─ MoonViz CLI 独立二进制，stdin/stdout JSON 行协议
```

Agent 基座为 Rust 进程内实现（`src-tauri/src/agent.rs`）——无 JS 运行时、无子进程桥。
LLM 走任意 OpenAI 兼容端点，内置 11 个服务商预设（DeepSeek / GLM bigmodel+z.ai 双平台 /
Kimi API+订阅双线 / MiniMax 国内+国际 / StepFun 按量+订阅），思考等级按各家官方方言
（`reasoning_effort` / `thinking.type`）模型感知降级。

## 开发

```bash
./dev.sh            # debug 编译并启动（引擎二进制缺失时自动构建）
```

前置：Rust + Tauri CLI + Node（仅构建期脚本）+ 兄弟目录 MoonViz 仓库（引擎源码）。

```bash
# 打包（引擎二进制自动 staging 进 resources）
tauri build
```

## 测试

后端先行：`cargo test` 含 mock-LLM × 真实引擎二进制的端到端循环（bootstrap、中途失败
保留工作、只读会话 render 兜底）。前端状态机冒烟：`node test_studio.cjs`。

## 打包产物

- macOS：`.app` / `.dmg`（含内嵌引擎二进制，用户无需 MoonBit 工具链）
- Windows：NSIS 安装包（GitHub Actions，`.github/workflows/windows-build.yml`）

更多：[docs/menus.md](docs/menus.md)（菜单文案与动作映射）。
