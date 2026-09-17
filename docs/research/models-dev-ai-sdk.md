# 调研报告:models.dev + AI SDK 作为模型集成核心的可行性

> 调研日期 2026-09-17。所有数据均为当日实测:api.json 已拉取本地核对(221 提供商 / 4.7MB),
> 端点比对基于本仓库 `frontend/index.html` 的 `PROVIDERS` 预设与 `agent.rs::thinking_extra_body` 方言表。
>
> **落地状态:P1 已实现**——`scripts/sync-models.mjs` + vendored 快照 `src-tauri/models.json`
> (11 提供商/86 模型/~48KB) + `src-tauri/src/models.rs` 的四个契约测试。
> 实施中发现两处新的真实分歧并显性登记:MiniMax 双预设端点漂移(官方已推荐 Anthropic 兼容,
> 切换需请求体改造,暂留 `KNOWN_DIVERGENCES`)、UI 静态模型 `MiniMax-M2.1-highspeed` 官方存在
> 但 models.dev 快照滞后(`KNOWN_UI_EXTRAS`,快照补齐即红逼清理)。

## TL;DR

| 角色 | 结论 |
|---|---|
| **models.dev** | ✅ **采纳,作为数据层**:提供商预设、模型清单、能力元数据的事实源候选。MIT 许可,可 vendor。但它记的是**能力轴**(toggle/effort 档位),**不含线上字段方言**(`thinking`/`reasoning_effort`/`chat_template_kwargs` 全库零命中),所以不能替代方言表,只能喂养和校验它 |
| **AI SDK** | ❌ **不采纳为运行时**(纯 TS/Node≥22/ESM-only/Zod,与 Rust 进程内 Agent、无 JS 运行时的架构决策正面冲突);✅ **采纳为思想库**:它的 `reasoning` 六档归一化、provider 吸收层、providerOptions 优先规则,与本仓库方言表几乎同构,可对齐语义 |
| **`thinking_extra_body` 方言表** | 🔒 **保留为本仓库的权威**——它是"能力 → 线上字节"的编译器,这正是 models.dev 不做的部分。但要用 models.dev 做对账信号(已实测抓到 2 处漂移) |

一句话:**这两个站本来就同源**——models.dev 就是 AI SDK 的模型注册表数据层(每个提供商带 `npm: @ai-sdk/*` 字段,Model ID 即 AI SDK 标识符,SST/Anomaly 团队同时维护 opencode)。选它们等于选了一个生态的两层。适合本仓库的切法是:取其数据层,不取其运行时。

---

## 一、models.dev 调研事实

- **是什么**:开源 AI 模型规格库,仓库 `sst/models.dev`(已迁 `anomalyco/models.dev`),MIT 许可(代码+数据),4.8k stars,SST/Anomaly 团队维护(opencode 的内部数据源)。
- **数据面**:TOML 按提供商/模型组织,社区 PR + 每小时自动同步 + GitHub Action schema 校验。三个 JSON 端点:
  - `/api.json` 提供商视角(端点、env、每模型规格)——实测 221 提供商、4.7MB
  - `/models.json` 模型本体元数据(与提供商无关)
  - `/catalog.json` 合并;另有 `/logos/{provider}.svg` 与类型化 SDK `@opencode-ai/models`
- **模型字段**(实测全集):`reasoning` / `reasoning_options`(抽象能力轴:`[{type:"toggle"}]`、`[{type:"effort",values:[...]}]`、`budget_tokens`)、`tool_call`、`structured_output`、`limit.context/output`、`cost`、`modalities`、`open_weights`、`knowledge`、`release_date/last_updated`。
- **关键限制(实测确认)**:全库 **不含任何线上方言字段**——`"thinking"`/`"reasoning_effort"`/`"chat_template_kwargs"`/`"enable_thinking"` 零命中。它回答"这家模型支持什么档位",不回答"请求体里怎么写"。
- **对本仓库关心的提供商覆盖极好**:deepseek、zhipuai(+`zhipuai-coding-plan`)、moonshotai(-cn)、kimi-for-coding、minimax(+cn/+coding-plan)、stepfun(+step-plan)、zai(+coding-plan)、alibaba 全部在册。

## 二、AI SDK 调研事实

- **是什么**:Vercel 的统一 TS SDK(Apache-2.0,26.9k stars,18.3M 周下载)。Core(文本/工具调用/结构化/agent)+ UI(hooks)。**运行时硬约束:Node ≥22、ESM-only、Zod peer 依赖**;Python 版刚 beta。无 Rust 绑定。
- **方言处理**(值得借鉴的部分):顶层可移植 `reasoning` 参数,六档 `none/minimal/low/medium/high/xhigh`;**差异由各 provider 包吸收**("Each provider translates the value to its native reasoning API");原生档位少时做强制映射并**发警告**;token 预算型换算为最大输出的百分比;`providerOptions` 里写了原生推理选项则**完全优先、不与顶层合并**。
- **与 models.dev 的关系**:models.dev 的 Model ID 就是 AI SDK 标识符,提供商 TOML 的 `npm` 字段直接指向 `@ai-sdk/*` 包(含 `@ai-sdk/openai-compatible` 兜底 + base URL)。

## 三、交叉验证(本仓库 11 预设 × models.dev)

### 端点比对

| 本仓库预设 | 我们的端点 | models.dev | 协议族 | 结果 |
|---|---|---|---|---|
| deepseek | api.deepseek.com | 同 | openai-compatible | ✅ |
| glm(bigmodel) | open.bigmodel.cn/api/paas/v4 | 同 | openai-compatible | ✅ |
| zai | api.z.ai/api/paas/v4 | 同 | openai-compatible | ✅ |
| kimi | api.moonshot.cn/v1 | 同 | openai-compatible | ✅ |
| kimi-plan | api.kimi.com/coding/v1 | 同 | **@ai-sdk/anthropic** | ⚠️ 端点同,但它标 Anthropic 协议族 |
| minimax | api.minimax.cn/v1 | **api.minimaxi.com/anthropic/v1** | **@ai-sdk/anthropic** | ⚠️ 漂移(域名疑为社区笔误,协议族变化值得核实) |
| minimax-intl | api.minimax.io/v1 | **api.minimax.io/anthropic/v1** | **@ai-sdk/anthropic** | ⚠️ 漂移:MiniMax 或已主推 Anthropic 兼容端点 |
| stepfun | api.stepfun.com/v1 | 同 | openai-compatible | ✅ |
| stepfun-plan | …/step_plan/v1 | 同 | openai-compatible | ✅ |

7/9 端点一致;**2 处 MiniMax 漂移双向都有信息量**——若 MiniMax 确已主推 `/anthropic/v1`,我们的手写表正在腐烂(models.dev 能抓到);若 `minimaxi.com` 是笔误,则证明社区数据需要本地权威兜底。**两个方向都指向同一架构**。

### 方言档位比对(抽样)

| 模型 | 我们方言表(对照官方文档核实) | models.dev `reasoning_options` | 判定 |
|---|---|---|---|
| GLM-5.3-flash | 强制思考,仅 low/high/max | effort [low,high,max] | ✅ 档位完全一致 |
| step-3.7-flash | 三档 effort(off→low, max→high) | effort [low,medium,high] | ✅ 档位一致(off 映射是我们的方言知识) |
| kimi-k2.6 | 仅开关 | [toggle] | ✅ |
| deepseek-v4-flash | 开关 + effort 全档(medium 服务端映射) | [toggle, effort(low,high,max)] | 🔶 接近,档位枚举略异 |
| glm-5.2 | 开关 + 全档 effort | effort [high,max],无 toggle | ❌ 不一致(待查官方) |
| qwen3.7-max | 仅 vLLM 自部署 off 方言 | [toggle, budget_tokens](DashScope) | ❌ 不一致(端点语境不同) |
| MiniMax-M2.x | 仅开关(thinking.type) | opts=None(仅 reasoning:true) | 🔶 信息量低于我们的表 |

结论:**models.dev 档位数据大体准确但非权威**——7 条抽样 3 ✅ 3 🔶/❌。它适合做"对账信号 + 发现新模型",不适合直接驱动请求体生成。

## 四、与本仓库约束的适配

1. **Rust 进程内 Agent、无 JS 运行时**(提交 `39a59fd` 刻意移除):AI SDK 运行时不可用。且 AGENTS.md 已记录"类型化 chat 客户端(async-openai)评估否决"——理由(wire 字段需序列化后注入)对 AI SDK 同样成立且更重。
2. **依赖极简原则**:AI SDK 拉入 Zod/ESM/Node 运行时,直接违反。
3. **前端无 HTTP 层**:模型数据若进前端,只能经 Tauri invoke 或随包静态资产。
4. **离线桌面应用**:运行时拉 models.dev 不可靠;应 vendor 快照。4.7MB 全量不必——只需 ~12 个提供商的子集(数十 KB),MIT 允许。
5. **本仓库已有一套成熟模式**:引擎二进制 sync + vendored SKILL.md + 契约测试四方对账。模型元数据可以完全复用这套打法。

## 五、落地建议(分期)

### P1(建议做):models.dev 为数据源,方言表为编译器
- 新增 `scripts/sync-models.mjs`:拉 `api.json` → 裁剪出本仓库关心的 ~12 提供商 → 生成 `src-tauri/models.json`(vendored 快照,记录来源日期与 commit)。
- 前端 `PROVIDERS`(11 项手写)改为从快照生成/校验;`fetchFxModels` 的模型列表兜底、`MINIMAX_STATIC_MODELS` 手写清单改由快照派生。
- **新增契约测试**(镜像 `skill_dictionary_matches_engine_and_agent` 的打法):快照端点 ⇄ `PROVIDERS` 严格相等——上游端点/协议族漂移(如 MiniMax)会红;快照里 `reasoning_options.values` ⇄ `thinking_family_table` 档位断言——新增模型档位与方言表不匹配会红,提醒人工核官方文档后再扩方言表。
- 方言表继续手工维护、继续以官方文档为准;models.dev 只做哨兵,不做权威。

### P2(可选):UI 增强
- 设置面板的模型选择器用快照数据展示上下文窗口/价格/能力标签(tool_call、structured_output——后者对本仓库工具调用循环有直接意义:不支持 tool_call 的模型可在 UI 直接标灰)。

### AI SDK:不引入,但对齐两个语义
- 档位命名向它靠拢(我们 `off/auto/low/medium/high/max` vs 它 `none/minimal/…/xhigh`,保持现状亦可,但映射语义对齐后文档可互引);
- 借鉴 **providerOptions 优先于通用参数、不合并** 的规则——未来方言表若支持用户透传原生字段,应整体覆盖而非合并。

## 六、风险

| 风险 | 缓解 |
|---|---|
| 社区数据准确性(glm-5.2、qwen 已见不一致;minimaxi.com 疑笔误) | 方言表保持本地权威;快照仅作对账信号,分歧时人工核官方文档 |
| 数据滞后于厂商调价/改端点(小时级同步仍有延迟) | 契约测试红 → 人工裁决,不自动改写方言表 |
| 上游迁移(sst → anomalyco 已发生一次) | 快照记录来源 URL+日期;sync 脚本参数化 |
| vendor 体积 | 裁剪子集(全量 4.7MB → 预计 <100KB);MIT 保留署名 |

## 附:验证方法

```bash
curl -sL https://models.dev/api.json -o /tmp/models_dev_api.json   # 221 providers
# 端点比对见本报告第三节;方言档位:providers.{pk}.models.{id}.reasoning_options
# 全库方言字段检索:"thinking"/"reasoning_effort"/"chat_template_kwargs" 均 0 命中
```
