#!/usr/bin/env node
// 模型元数据快照同步：从 models.dev 拉取 api.json，裁剪出本项目预设涉及的提供商，
// 生成 src-tauri/models.json（vendored 快照，随版本库提交）。
//
// 为什么 vendor 而不是运行时拉取：桌面应用需离线可用；4.7MB 全量无意义——
// 本项目 11 个预设只覆盖 ~11 个提供商，裁剪后几十 KB。
//
// 数据性质（见 docs/research/models-dev-ai-sdk.md）：models.dev 记**能力轴**
// （toggle/effort 档位），**不含线上字段方言**。它是发现与对账信号，不是权威；
// agent.rs 的 thinking_extra_body 方言表保持以官方文档为准，本快照由
// cargo test 的 presets_match_snapshot 契约测试锁定漂移。
//
// 用法：node scripts/sync-models.mjs   （更新后 cargo test 必须仍然绿；
// 若 presets_match_snapshot 红，按报告第三节裁决：改预设 or 加 KNOWN_DIVERGENCES）
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url))); // deepDesign/
const SOURCE = 'https://models.dev/api.json';

// frontend/index.html 的 PROVIDERS 键 → models.dev 提供商 id
// 必须与 src-tauri/src/models.rs 的 PRESET_PROVIDER_MAP 完全一致（presets_match_snapshot 锚定后者，本表是第三份副本——加预设三处一起改）
const PROVIDER_MAP = {
  deepseek: 'deepseek',
  glm: 'zhipuai',
  'glm-coding': 'zhipuai-coding-plan',
  zai: 'zai',
  'zai-coding': 'zai-coding-plan',
  kimi: 'moonshotai-cn',
  'kimi-plan': 'kimi-code-plan-cn',  // models.dev 把原 kimi-for-coding 拆成 global/cn 两条
  minimax: 'minimax-cn',
  'minimax-intl': 'minimax',
  'minimax-anthropic': 'minimax-cn',
  'minimax-anthropic-intl': 'minimax',
  stepfun: 'stepfun',
  'stepfun-plan': 'stepfun-step-plan',
};

function fail(msg) {
  console.error(`[sync-models] ${msg}`);
  process.exit(1);
}

console.log(`[sync-models] fetching ${SOURCE} ...`);
const resp = await fetch(SOURCE);
if (!resp.ok) fail(`拉取失败 HTTP ${resp.status}`);
const api = await resp.json();
if (!api || typeof api !== 'object' || Array.isArray(api)) fail('api.json 不是对象');

const keep = [...new Set(Object.values(PROVIDER_MAP))];
const providers = {};
for (const pid of keep) {
  const p = api[pid];
  if (!p) fail(`api.json 缺提供商 ${pid}——上游改名了？同步更新 PROVIDER_MAP`);
  // 温和 schema 漂移照写会让坏快照静默入库、拖到 cargo test 才红——这里直接拒
  if (typeof p.name !== 'string') fail(`提供商 ${pid} 的 name 不是字符串`);
  if (typeof p.api !== 'string' || !/^https:\/\//.test(p.api)) fail(`提供商 ${pid} 的 api 端点异常：${String(p.api)}`);
  if (p.models && typeof p.models !== 'object') fail(`提供商 ${pid} 的 models 不是对象`);
  const models = {};
  for (const [mid, m] of Object.entries(p.models || {})) {
    models[mid] = {
      name: m.name ?? mid,
      reasoning: m.reasoning ?? false,
      // 能力轴：toggle / effort(values) / budget_tokens——方言表的档位对账信号
      ...(m.reasoning_options ? { reasoning_options: m.reasoning_options } : {}),
      tool_call: m.tool_call ?? false,
      structured_output: m.structured_output ?? false,
      ...(m.limit ? { limit: m.limit } : {}),
      ...(m.cost ? { cost: m.cost } : {}),
    };
  }
  providers[pid] = {
    id: pid,
    name: p.name ?? pid,
    api: p.api,
    npm: p.npm, // @ai-sdk/* —— 协议族信号（anthropic vs openai-compatible）
    model_count: Object.keys(models).length,
    models,
  };
}

const snapshot = {
  source: SOURCE,
  license: 'MIT (models.dev, sst/anomaly)',
  fetched_at: new Date().toISOString().slice(0, 10),
  note:
    'vendored snapshot for deepDesign Studio provider presets; capability axes only, ' +
    'wire dialects live in agent.rs::thinking_extra_body; drift is locked by ' +
    'cargo test presets_match_snapshot / minimax_static_models_in_snapshot',
  providers,
};

const out = join(root, 'src-tauri', 'models.json');
writeFileSync(out, JSON.stringify(snapshot, null, 2) + '\n');
const count = keep.reduce((n, k) => n + providers[k].model_count, 0);
console.log(
  `[sync-models] ${keep.length} providers / ${count} models -> ${out}\n` +
    keep.map((k) => `  ${k}: ${providers[k].api} (${providers[k].model_count} models)`).join('\n')
);
