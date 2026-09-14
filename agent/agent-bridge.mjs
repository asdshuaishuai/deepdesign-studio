#!/usr/bin/env node
// deepDesign Studio × @open-agent-loops/core bridge.
//
// stdin : { mode:'run'|'selftest'|'models', instruction, mbt_b64, api_key, model,
//           base_url, thinking_level, engine_dir }
// stdout: { ok, mbt_b64, render, ops[], text, error? }
//
// Agent 基座：@open-agent-loops/core（开源、极简、原生 OpenAI 兼容）
// LLM 完全自主决策——系统提示词通过 runAgent({ system }) 传入。
// 所有变更经 MoonViz AgentGate 校验后写入 canonical .mbt.md。

import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { runAgent, defineTool, SessionMemoryStore } from '@open-agent-loops/core';
import { OpenAICompatibleModel } from '@open-agent-loops/core/providers/openai';
import { z } from 'zod';

const here = dirname(fileURLToPath(import.meta.url));
const DEFAULT_ENGINE = process.env.MOONVIZ_DIR || join(here, '..', '..', 'moonviz');
const CLI_TIMEOUT_MS = 30000;

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
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      resolve([{ ok: false, error: 'engine_timeout' }]);
    }, CLI_TIMEOUT_MS);
    child.stdout.on('data', c => (out += c));
    child.stderr.on('data', c => (err += c));
    // 引擎早退（如 moon 不存在 / 编译失败）时 stdin 写入会 EPIPE；
    // 不挂 error 监听会成为 uncaught exception，吞掉下面的错误返回。
    child.stdin.on('error', () => {});
    child.on('error', e => { clearTimeout(timer); resolve([{ ok: false, error: 'moon_unavailable:' + e.message }]); });
    child.on('close', () => {
      clearTimeout(timer);
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
const ENGINE_TEMPLATES = `login(登录页) | signup(注册页) | dashboard(仪表盘) | profile(个人主页)
settings(设置页) | list_detail(列表-详情，含两屏) | onboarding(引导页) | empty_state(空状态)
web_landing(Web落地页 1280x800) | web_login(Web登录) | web_dashboard(Web仪表盘) | pc_app(PC桌面 1440x900)
adaptive_landing(自适应落地页) | login_v2(登录页v2)`;

const INSTRUCTIONS = `You are the embedded design agent of deepDesign Studio, a visual prototyping editor.
You operate as a product designer, not a command executor: interpret what the user wants to
ACHIEVE, decide which screens the experience needs, build them, connect them, and verify the result.
The single source of truth is one MoonBit literate .mbt.md document; every operation you issue is
validated by the engine (AgentGate) and committed immediately, so the user watches progress live.

## Mindset
- Derive intent: "a WeChat-style app" means an experience (login, feed, chat, profile, settings),
  not one artboard. Before the first tool call, state a one-line plan: the screen list and how they connect.
- Think in flows: a prototype is screens + navigation. An unconnected screen is unfinished.
- Write real product copy (realistic labels, names, numbers), never lorem ipsum.
- Two modes: BUILD requests get the full loop below; TWEAK requests ("make the button green")
  get read_mbt, one targeted op, done.

## Build loop (from empty document)
1. PLAN: choose screens; map each to a template. Available: ${ENGINE_TEMPLATES}
   Notes: template/create size args are optional; list_detail yields ONE artboard
   (a list screen with a detail placeholder card — not two separate screens);
   adaptive templates pick structure by width.
   Artboard names become ids after sanitization — use ASCII snake_case names
   (e.g. chat_list); non-ASCII names collapse to "_" and collide. Chinese copy
   belongs in node text values, never in artboard/node ids.
2. CREATE: one "template <id> <name> [w] [h]" per screen, then IMMEDIATELY read_mbt —
   node ids are only discoverable there. Artboard id = sanitized name.
3. CUSTOMIZE: "update <artboard> <node> k=v ..." per screen; finish one before the next.
   "place <artboard> <component> <instance_id> [variant|-] [x] [y]" to add engine components
   (discover ids via list_components; "-" as variant means default).
4. CONNECT: "flow <from> <to> <node>" for every primary CTA (login button, card tap, tab, back).
5. VERIFY: read_mbt and check flows cover every screen; every primary CTA wired; no dangling refs.
   Run "fix <artboard>" if violations accumulated (fix commits when it strictly reduces them).
6. REPORT: stop calling tools and summarize: screens built and the flow map.

## Tweak loop (document already loaded)
0. read_mbt FIRST — always ground ids and flows before any op.
1. Make the minimal ops. 2. Report what changed.

## Operation grammar (one op per moonviz_op call, no newlines)
  template <template_id> <name> [w] [h] | create <name> [w] [h]
  | duplicate <artboard> <new_name> | delete-artboard <artboard>
  | place <artboard> <component> <instance_id> [variant|-] [x] [y]
  | move <artboard> <node> <x> <y> | update <artboard> <node> k=v [k=v ...]
  | delete <artboard> <node> | copy <artboard> <node> <new_id> [dx] [dy]
  | reorder <artboard> <node> front|back|up|down | flip <artboard> <node> h|v|both|none
  | flow <from_artboard> <to_artboard> <node>
  | theme <name>  (light|dark|high_contrast|sepia|nord|sunset)
  | fix <artboard>
- read-only inspection ops (no document change): lint <artboard>
  | critique <artboard> | query <artboard> | infer <artboard>
  | flows | tap <artboard> <x> <y>
- update keys: w h text fill text_color stroke radius opacity font_size weight shadow rotate
  blur blend line tracking constraint. Quote values with spaces: text="Sign in".
  Unquoted words after a space are silently dropped — always quote multi-word text.
- duplicate is the cheapest way to spawn "a similar screen" before diverging with update.

## Ground truth and errors
- NEVER guess node/component/template/theme ids. Templates: list above; components: list_components;
  everything else: read_mbt. Ids are shared with the human canvas: never rename; new ids = snake_case.
- Errors: unknown_artboard/unknown_node/unknown_component/unknown_template → read_mbt then retry with real ids.
  Predicate violations (overflow, overlap) reject the op with predicate + node_id + detail → adjust values;
  if stuck run fix <artboard>. Never repeat an identical failing op.
- debt = remaining tolerated violations; keep it 0. All changes go through moonviz_op only.`;

// 只读命令（走 load-mbt-b64 管道而非 apply-op 路径）。
// 注意：fix 不在此列——引擎在 apply-agent-mbt-op-b64 中为 fix 实现了
// 「违规严格下降才提交」的还债语义，走只读管道会丢弃变更。
// (\s|$) 允许无参命令（flows / list-templates / list-components）裸调用。
const READONLY_RE = /^(lint|critique|query|flows|tap|list-templates|list-components|infer)(\s|$)/;

function makeExecutor(engineDir) {
  let mbt = null;
  let lastRender = null;
  const ops = [];

  return {
    setMbt(text) { mbt = text; },
    setRender(r) { lastRender = r; },
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
          return { ok: true, op, revision: boot.revision ?? 0,
            artboards: (boot.artboards || []).map(a => ({ id: a.id, name: a.name })) };
        }
        const err = rs.find(r => r && r.error);
        return { ok: false, error: (err && err.error) || 'boot_failed' };
      }

      if (!mbt) return { ok: false, error: 'no_mbt_loaded' };

      // 只读命令（lint/critique/query/flows/tap/…）：走 load + 命令管线。
      // 引擎输出顺序：banner{moonviz} → load ack{ok,entry,revision} → 命令结果，
      // 因此取「最后一个非 banner 对象」——load ack 永远排在命令结果之前。
      if (READONLY_RE.test(op.trim())) {
        const rs = await runMoonCli(engineDir, [
          `load-mbt-b64 ${b64encode(mbt)}`, op.trim(),
        ]);
        const nonBanner = rs.filter(r => r && typeof r === 'object' && !r.moonviz);
        const result = nonBanner[nonBanner.length - 1];
        if (!result) return { ok: false, error: 'readonly_no_output' };
        if (result.error) return { ok: false, error: result.error };
        ops.push(op);
        return Array.isArray(result) ? { ok: true, result } : result;
      }

      // 变更操作：apply-agent-mbt-op-b64
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

function makeTools(ex) {
  return [
    defineTool({
      name: 'moonviz_op',
      description: 'Execute one MoonViz design operation (validated by AgentGate, committed to .mbt.md). Also supports read-only ops: lint, critique, query, flows, tap.',
      parameters: z.object({
        op: z.string().describe('One operation string, e.g. "update login title text=\\"Sign in\\""'),
      }),
      execute: async ({ op }) => { const r = await ex.moonvizOp(op); return { content: JSON.stringify(r) }; },
    }),
    defineTool({
      name: 'read_mbt',
      description: 'Read the current canonical .mbt.md source of truth (node ids, flows, all screens).',
      parameters: z.object({}),
      execute: async () => { const r = await ex.readMbt(); return { content: JSON.stringify(r) }; },
    }),
    defineTool({
      name: 'list_components',
      description: 'List all engine UI component presets (id, category, variants).',
      parameters: z.object({}),
      execute: async () => { const r = await ex.listComponents(); return { content: JSON.stringify(r) }; },
    }),
  ];
}

/// base_url 校验：https 任意主机；http 仅放行本机/内网（本地 LLM 如 Ollama/vLLM）。
function safeBaseUrl(u) {
  if (!u || !u.trim()) return 'https://api.deepseek.com';
  let parsed;
  try { parsed = new URL(u.trim()); } catch { return null; }
  if (parsed.protocol === 'https:') return parsed.toString();
  if (parsed.protocol === 'http:' &&
      /^(localhost|127\.0\.0\.1|\[::1\]|192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)/.test(parsed.hostname)) {
    return parsed.toString();
  }
  return null;
}

/// 框架 ThinkingMode 仅支持 on|off|auto；兼容前端历史保存的 low/medium/high（映射为 on）。
function mapThinking(level) {
  if (level === 'off') return 'off';
  if (level === 'on' || level === 'low' || level === 'medium' || level === 'high') return 'on';
  return 'auto';
}

async function runWithAgent({ instruction, mbt_b64, api_key, model, base_url, thinking_level, engine_dir }) {
  const apiKey = api_key || process.env.AI_GATEWAY_API_KEY;
  if (!apiKey) return { ok: false, error: 'api_key_missing' };

  const engineDir = engine_dir || DEFAULT_ENGINE;
  if (!existsSync(join(engineDir, 'cli'))) return { ok: false, error: 'engine_dir_invalid' };

  const baseUrl = safeBaseUrl(base_url);
  if (!baseUrl) return { ok: false, error: 'base_url_invalid_https_or_local' };

  const ex = makeExecutor(engineDir);
  if (mbt_b64) {
    ex.setMbt(Buffer.from(mbt_b64, 'base64').toString('utf8'));
  }

  const agentModel = new OpenAICompatibleModel({
    apiKey,
    baseURL: baseUrl,
    model: model || 'deepseek-chat',
    thinking: mapThinking(thinking_level),
  });

  const tools = makeTools(ex);
  const memory = new SessionMemoryStore();

  const result = await runAgent({
    model: agentModel,
    memory,
    system: INSTRUCTIONS,
    sessionId: 'studio_' + Date.now().toString(36),
    prompt: instruction,
    tools,
    maxSteps: 20,
    // moonviz_op 读写共享的 mbt 闭包状态，并发执行会互相覆盖丢失更新。
    toolExecution: 'sequential',
  });

  // 从 newMessages 提取 assistant 总结和错误信息
  const newMsgs = result?.newMessages || [];
  const lastAssistant = [...newMsgs].reverse().find(m => m.role === 'assistant');
  const hasError = newMsgs.some(m => m.role === 'assistant' && m.isError);
  const text = lastAssistant?.content || '';

  // mbt 为 null 且无 ops → agent 未执行任何操作
  if (!ex.mbt() && ex.ops().length === 0) {
    return {
      ok: false,
      error: hasError ? 'llm_stream_error' : 'agent_no_mbt',
      detail: hasError ? text.slice(0, 200) : 'LLM did not call any tools',
      ops: [], text,
    };
  }

  // 只读会话（如仅 lint/query）不会产生 apply 渲染——用 render-mbt-b64 兜底，
  // 保证前端始终拿到含 artboards/svg 的终态 render，而不是 null。
  if (ex.mbt() && !ex.render()) {
    const rs = await runMoonCli(engineDir, [`render-mbt-b64 ${b64encode(ex.mbt())}`]);
    const rendered = rs.find(r => r && typeof r === 'object' && typeof r.mbt === 'string');
    if (rendered) ex.setRender(rendered);
  }

  return {
    ok: ex.mbt() !== null,
    mbt_b64: ex.mbt() ? b64encode(ex.mbt()) : null,
    render: ex.render(),
    ops: ex.ops(),
    stopReason: result?.steps >= 20 ? 'max_turns' : 'done',
    text,
  };
}

async function selftest({ mbt_b64, engine_dir }) {
  const engineDir = engine_dir || DEFAULT_ENGINE;
  if (!existsSync(join(engineDir, 'cli'))) return { ok: false, error: 'engine_dir_invalid' };
  // 严格 base64 校验（与 server.py 同一正则，防换行注入）
  if (typeof mbt_b64 !== 'string' || !/^[A-Za-z0-9+/]+={0,2}$/.test(mbt_b64)) {
    return { ok: false, error: 'mbt_b64_invalid' };
  }
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

async function listModels({ base_url, api_key }) {
  const apiKey = api_key || process.env.AI_GATEWAY_API_KEY;
  if (!apiKey) return { ok: false, error: 'api_key_missing' };
  if (!base_url || !/^https:\/\//.test(base_url)) return { ok: false, error: 'base_url_must_be_https' };
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

try {
  const input = JSON.parse(await readStdin());
  const out = input.mode === 'selftest' ? await selftest(input)
    : input.mode === 'models' ? await listModels(input)
    : await runWithAgent(input);
  process.stdout.write(JSON.stringify(out));
} catch (e) {
  process.stdout.write(JSON.stringify({ ok: false, error: 'bridge_failed', detail: String(e && e.message).slice(0, 300) }));
}
