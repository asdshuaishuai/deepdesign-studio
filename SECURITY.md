# 安全政策（Security Policy）

## 支持版本

安全修复只针对**最新发布版本**提供。请先确认问题在最新版本
（[Releases](https://github.com/asdshuaishuai/deepdesign-studio/releases/latest)）上仍可复现。

| 版本 | 支持 |
|---|---|
| 最新 release（当前 v0.4.2-fix） | ✅ |
| 更早版本 | ❌ |

## 报告漏洞

**请不要用公开 issue 报告安全漏洞。**

请通过 [GitHub Security Advisories](https://github.com/asdshuaishuai/deepdesign-studio/security/advisories/new)
私下报告，或发邮件至维护者（见 GitHub 主页联系方式），标题注明 `[SECURITY]`。

报告中请包含：

- 漏洞类型与影响面（例如：凭据泄露 / 任意文件读写 / 注入）
- 复现步骤或 PoC（最小化）
- 受影响版本与平台
- 如已知，修复建议

**响应承诺**：48 小时内确认收到；7 天内给出初步评估（确认/拒绝/需要更多信息）；
确认后协调披露时间（默认修复发布后公开致谢，除非你要求匿名）。

## 已知的安全设计边界（非漏洞）

以下为本项目的**有意设计**，请勿作为漏洞报告：

- **API Key 存于本地 localStorage**：桌面单用户场景的常见做法，与操作系统用户账户
  隔离同一安全级。计划迁移 OS keychain，见 AGENTS.md「已知缺口」。
- **DDP 加密容器**：DDP1 为 Argon2id + XChaCha20-Poly1305（密码强度决定安全级）；
  **DDP2 为免密容器（zstd + CRC32），不提供机密性**——只做完整性校验，不要用它传递机密。
- **Agent 发往 LLM 端点的内容**：使用第三方模型服务时，指令与文档内容会发送给该服务商，
  这是功能的必要组成。请自行评估服务商的数据政策。
- **`safe_base_url` SSRF 防护**：仅放行 https 与 localhost/私有网段 http。如需连接
  自建推理服务，请使用 https 或本地地址。
- **不跟随 HTTP 重定向**：API 端点返回 3xx 时直接报错（防止凭据跟随重定向外泄），
  这是有意行为。

## 供应链与依赖

- Rust 依赖全部为宽松许可（MIT / Apache-2.0 / BSD / ISC / Unicode / Zlib；
  MPL-2.0 与 GPL 类均为 `OR` 双许可，可选宽松分支）——无强 copyleft 传染。
- 前端**零 npm 依赖**（单文件静态页），无第三方 JS 供应链面。
- 引擎为预编译 wasm 产物，经 sha512 校验 + 真机契约探针后入库。
- 三平台安装包由 GitHub Actions 从 tag 构建，构建流程公开可审计
  （`.github/workflows/release-all.yml`）。
