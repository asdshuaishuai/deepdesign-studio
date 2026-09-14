#!/usr/bin/env node
// deepDesign Studio × @open-agent-loops/core bridge.
//
// stdin : { mode:'run'|'selftest'|'models', instruction, mbt_b64, api_key, model,
//           base_url, thinking_level, engine_dir }
// stdout: { ok, mbt_b64, render, ops[], log[], error? }
//
// Agent 基座：@open-agent-loops/core（开源、极简、原生 OpenAI 兼容）
// LLM 完全自主决策——看到工具结果决定下一步，判断何时停止。
// 所有变更经 MoonViz AgentGate 校验后写入 canonical .mbt.md。

import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { runAgent, defineTool, SessionMemoryStore } from '@open-agent-loops/core';
import { OpenAICompatibleModel } from '@open-agent-loops/core/providers/openai';
import { z } from 'zod';

const here = dirname(fileURLToPath(import.meta.url));
const DEFAULT_ENGINE = join(here, '..', '..', 'moonviz');

function readStdin() {
  return new Promise((resolve, reject) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', c => (data += c));
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', reject);
  });
}

function b64encode(text) { return Buffer.from(text, 'utf8').toString('base64'); }

function runMoonCli(engineDir, commands) {
  return new Promise((resolve) => {
    const child = spawn('moon', ['run', '--target', 'native', 'cli'], {
      cwd: engineDir,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    let out = '', err = '';
    child.stdout.on('data', c => (out += c));
    child.stderr.on('data', c => (err += c));
    child.on('error', e => resolve([{ ok: false, error: 'moon_unavailable:' + e.message }]));
    child.on('close', () => {
      const results = [];
      for (const line of out.split('\n')) {
        const t = line.trim();
        if (t.startsWith('{') || t.startsWith('[')) {
          try { results.push(JSON.parse(t)); } catch { /* not json */ }
        }
      }
      resolve(results.length ? results : [{ ok: false, error: 'engine_no_output:' + err.slice(0, 300) }]);
    });
    for (const cmd of commands) child.stdin.write(cmd + '\n');
    child.stdin.write('exit\n');
    child.stdin.end();
  });
}

/// 引擎模板清单（与 MoonViz list-templates 同步）
const ENGINE_TEMPLATES = `login(登录页 390x844) | signup(注册页 390x844) | dashboard(仪表盘 390x844)
profile(个人主页 390x844) | settings(设置页 390x844) | list_detail(列表-详情 390x844)
onboarding(引导页 390x844) | empty_state(空状态页 390x844) | web_landing(Web落地页 1280x800)
web_login(Web登录 1280x800) | web_dashboard(Web仪表盘 1280x800) | pc_app(PC桌面应用 1440x900)
adaptive_landing(自适应落地页 1280x800) | login_v2(登录页v2 390x844)`;

const INSTRUCTIONS = `You are the embedded agent of deepDesign Studio, a visual prototyping editor.
The project's single source of truth is one MoonBit literate .mbt.md document held by the host.
You can build COMPLETE interactive prototypes: multiple artboards connected by tap-navigation flows.

## Workflow for building a prototype from a natural-language request (e.g. "make a WeChat-style social app"):
1. If the document has no artboards yet, call moonviz_op with "template <template_id> <name> <w> <h>" for EACH screen. Available templates:
${ENGINE_TEMPLATES}
2. Customize each artboard with ops like "update <artboard> <node> text=... fill=...".
3. Connect screens with flows: "flow <from_artboard> <to_artboard> <trigger_node_id>".
4. Run "fix <artboard>" if any op is rejected for layout violations.

## Rules:
- Mutate the design ONLY by calling the moonviz_op tool, one operation string per call.
- Operation grammar (CLI-style):
  template <template_id> <name> <w> <h> | create <name> <w> <h>
  | move <artboard> <node> <x> <y> | update <artboard> <node> k=v [k=v ...]
  | delete <artboard> <node> | copy <artboard> <node> <new_id> [dx] [dy]
  | reorder <artboard> <node> front|back|up|down | flip <artboard> <node> h|v|both|none
  | place <artboard> <component> <instance_id> - <x> <y>
  | flow <from_artboard> <to_artboard> <node> | theme <name> | fix <artboard>
- Node ids and artboard ids are shared identifiers: never rename or guess them; call read_mbt first when unsure.
- update keys: w h text fill text_color stroke radius opacity font_size weight shadow rotate blur blend line tracking constraint.
- If an op is rejected, read the error, adjust the op, and retry with corrected values; do not repeat an identical failing op.
- When the user goal is reached, stop calling tools and summarize briefly.`;

function makeExecutor(engineDir) {
  let mbt = null;
  let lastRender = null;
  const ops = [];

  return {
    setMbt(text) { mbt = text; },
    mbt: () => mbt,
    ops: () => ops,
    render: () => lastRender,

    async moonvizOp(op) {
      if (typeof op !== 'string' || !op.trim()) return { ok: false, error: 'op_invalid' };
      if (/[\n\r]/.test(op)) return { ok: false, error: 'op_newline_forbidden' };

      // 空项目起步：template/create 可直接引导
      if (!mbt && /^(template|create) /.test(op.trim())) {
        const rs = await runMoonCli(engineDir, [op.trim(), 'export-mbt-human']);
        const boot = rs.find(r => r && typeof r === 'object' && typeof r.mbt === 'string');
        if (boot && boot.ok) {
          mbt = boot.mbt;
          lastRender = boot;
          ops.push(op);
          return { ok: true, op, revision: boot.revision ?? 0 };
        }
        const err = rs.find(r => r && r.error);
        return { ok: false, error: (err && err.error) || 'boot_failed' };
      }

      if (!mbt) return { ok: false, error: 'no_mbt_loaded' };
      const rs = await runMoonCli(engineDir, [
        `apply-agent-mbt-op-b64 ${b64encode(mbt)} ${b64encode(op)}`,
      ]);
      const result = rs.find(r => r && typeof r === 'object' && r.mbt !== undefined);
      if (!result || result.ok !== true) {
        const err = rs.find(r => r && r.error);
        return { ok: false, error: (err && err.error) || 'agent_op_failed' };
      }
      mbt = result.mbt;
      lastRender = result;
      ops.push(op);
      return {
        ok: true, op,
        debt: result.debt ?? 0,
        revision: result.revision,
        artboards: (result.artboards || []).map(a => ({ id: a.id, name: a.name })),
      };
    },

    async readMbt() {
      if (!mbt) return { ok: false, error: 'no_mbt_loaded' };
      return { ok: true, mbt };
    },

    async listComponents() {
      const rs = await runMoonCli(engineDir, ['list-components']);
      const arr = rs.find(r => Array.isArray(r));
      return { ok: true, components: arr ?? [] };
    },
  };
}

// ============================================================
// Agent 工具定义（@open-agent-loops/core defineTool）
// ============================================================
function makeTools(ex) {
  return [
    defineTool({
      name: 'moonviz_op',
      description: 'Execute one MoonViz design operation. Each call is validated by the engine (AgentGate) and committed to the canonical .mbt.md.',
      parameters: z.object({
        op: z.string().describe('One operation string, e.g. "update login title fill=#28a745"'),
      }),
      execute: async ({ op }) => ex.moonvizOp(op),
    }),
    defineTool({
      name: 'read_mbt',
      description: 'Read the current canonical .mbt.md source of truth.',
      parameters: z.object({}),
      execute: async () => ex.readMbt(),
    }),
    defineTool({
      name: 'list_components',
      description: 'List all engine UI component presets (id, category, variants).',
      parameters: z.object({}),
      execute: async () => ex.listComponents(),
    }),
  ];
}

// ============================================================
// Agent 运行（@open-agent-loops/core runAgent）
// ============================================================
async function runWithAgent({ instruction, mbt_b64, api_key, model, base_url, thinking_level, engine_dir }) {
  const apiKey = api_key || process.env.AI_GATEWAY_API_KEY;
  if (!apiKey) return { ok: false, error: 'api_key_missing' };

  const engineDir = engine_dir || DEFAULT_ENGINE;
  if (!existsSync(join(engineDir, 'cli'))) return { ok: false, error: 'engine_dir_invalid' };

  const ex = makeExecutor(engineDir);
  if (mbt_b64) {
    ex.setMbt(Buffer.from(mbt_b64, 'base64').toString('utf8'));
  }

  // Model：@open-agent-loops/core 的 OpenAICompatibleModel（原生 OpenAI 格式）
  const agentModel = new OpenAICompatibleModel({
    apiKey,
    baseURL: base_url || 'https://api.deepseek.com',
    model: model || 'deepseek-chat',
    thinking: thinking_level === 'off' ? 'off' : 'on',
  });

  const tools = makeTools(ex);
  const memory = new SessionMemoryStore();

  const result = await runAgent({
    model: agentModel,
    memory,
    sessionId: 'studio_' + Date.now().toString(36),
    prompt: instruction,
    tools,
    // 事件回调可选——不传则 runAgent 内部 drain
  });

  return {
    ok: ex.mbt() !== null,
    mbt_b64: ex.mbt() ? b64encode(ex.mbt()) : null,
    render: ex.render(),
    ops: ex.ops(),
    stopReason: result?.stopReason || 'done',
    text: result?.text || '',
  };
}

// ============================================================
// Selftest（无 API key，验证 executor 链路）
// ============================================================
async function selftest({ mbt_b64, engine_dir }) {
  const engineDir = engine_dir || DEFAULT_ENGINE;
  if (!existsSync(join(engineDir, 'cli'))) return { ok: false, error: 'engine_dir_invalid' };
  const ex = makeExecutor(engineDir);

  const probe = await runMoonCli(engineDir, [`load-mbt-b64 ${mbt_b64}`]);
  const entry = probe.find(r => r && r.ok)?.entry;
  if (!entry) return { ok: false, error: 'selftest_no_target' };
  ex.setMbt(Buffer.from(mbt_b64, 'base64').toString('utf8'));

  const q = await runMoonCli(engineDir, [`load-mbt-b64 ${mbt_b64}`, `query ${entry}`]);
  const nodes = q.find(r => Array.isArray(r));
  const node = nodes?.[0]?.id;
  if (!node) return { ok: false, error: 'selftest_no_target' };

  const ok1 = await ex.moonvizOp(`update ${entry} ${node} fill=#28a745`);
  const bad = await ex.moonvizOp(`move ${entry} nonexistent_node_xyz 99999 0`);
  const ok2 = await ex.moonvizOp(`move ${entry} ${node} 20 30`);
  return {
    ok: ok1.ok && !bad.ok && ok2.ok,
    validEditApplied: ok1.ok,
    structuralViolationRejected: !bad.ok,
    ops: ex.ops(),
  };
}

// ============================================================
// Models list（GET /models）
// ============================================================
async function listModels({ base_url, api_key }) {
  const apiKey = api_key || process.env.AI_GATEWAY_API_KEY;
  if (!apiKey) return { ok: false, error: 'api_key_missing' };
  if (!base_url) return { ok: false, error: 'base_url_required' };
  try {
    const res = await fetch(base_url.replace(/\/$/, '') + '/models', {
      headers: { Authorization: `Bearer ${apiKey}` },
    });
    const data = await res.json();
    if (!res.ok) return { ok: false, error: 'models_http_' + res.status };
    const arr = Array.isArray(data.data) ? data.data : (Array.isArray(data.models) ? data.models : []);
    return { ok: true, models: arr.map(m => ({ id: m.id })).filter(m => m.id) };
  } catch (e) {
    return { ok: false, error: 'models_fetch_failed', detail: String(e.message).slice(0, 200) };
  }
}

// ============================================================
// stdin/stdout 协议
// ============================================================
const input = JSON.parse(await readStdin());
try {
  const out = input.mode === 'selftest' ? await selftest(input)
    : input.mode === 'models' ? await listModels(input)
    : await runWithAgent(input);
  process.stdout.write(JSON.stringify(out));
} catch (e) {
  process.stdout.write(JSON.stringify({ ok: false, error: 'bridge_failed', detail: String(e && e.message).slice(0, 300) }));
}
