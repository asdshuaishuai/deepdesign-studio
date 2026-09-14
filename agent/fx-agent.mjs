#!/usr/bin/env node
// deepDesign Studio × fx Agent SDK (libfx) bridge.
//
// stdin : { mode:'run'|'selftest'|'models', instruction, mbt_b64, api_key, model, base_url,
//           thinking_level:'auto'|'off'|'on'|'low'|'medium'|'high' (MiniMax M3), engine_dir }
// stdout: { ok, mbt_b64, render, ops[], log[], error? }
//
// Contract: fx proposes operations via tools; every mutation executes through
// MoonViz CLI (AgentGate) and returns canonical `.mbt.md`. fx never edits MBT text.

import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import http from 'node:http';

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
function b64decode(b64) { return Buffer.from(b64, 'base64').toString('utf8'); }

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

function makeExecutor(engineDir) {
  let mbt = null;          // canonical MBT text
  let lastRender = null;   // latest engine render_json
  const ops = [];
  const log = [];

  return {
    setMbt(text) { mbt = text; },
    mbt: () => mbt,
    ops: () => ops,
    log: () => log,
    render: () => lastRender,

    async listComponents() {
      const rs = await runMoonCli(engineDir, ['list-components']);
      const arr = rs.find(r => Array.isArray(r));
      return { ok: true, components: arr ?? [] };
    },

    async readMbt() {
      if (!mbt) return { ok: false, error: 'no_mbt_loaded' };
      return { ok: true, mbt };
    },

    async moonvizOp(op) {
      if (typeof op !== 'string' || !op.trim()) return { ok: false, error: 'op_invalid' };
      if (/[\n\r]/.test(op)) return { ok: false, error: 'op_newline_forbidden' };
      // 空项目起步：template/create 命令可在无 MBT 时直接引导出新文档
      if (!mbt && /^(template|create) /.test(op.trim())) {
        const rs0 = await runMoonCli(engineDir, [op.trim(), 'export-mbt-human']);
        const boot = rs0.find(r => r && typeof r === 'object' && typeof r.mbt === 'string');
        if (!boot || boot.ok !== true) {
          const err = rs0.find(r => r && r.error);
          return { ok: false, error: (err && err.error) || 'boot_failed' };
        }
        mbt = boot.mbt;
        lastRender = boot;
        ops.push(op);
        log.push({ op, ok: true, revision: boot.revision ?? 0 });
        return {
          ok: true, op, revision: boot.revision ?? 0,
          artboards: (boot.artboards || []).map(a => ({ id: a.id, name: a.name })),
        };
      }
      if (!mbt) return { ok: false, error: 'no_mbt_loaded' };
      const rs = await runMoonCli(engineDir, [
        `apply-agent-mbt-op-b64 ${b64encode(mbt)} ${b64encode(op)}`,
      ]);
      const result = rs.find(r => r && typeof r === 'object' && r.mbt !== undefined);
      if (!result || result.ok !== true) {
        const err = rs.find(r => r && r.error);
        log.push({ op, ok: false, error: (err && err.error) || 'agent_op_failed' });
        return { ok: false, error: (err && err.error) || 'agent_op_failed' };
      }
      mbt = result.mbt;
      lastRender = result;
      ops.push(op);
      log.push({ op, ok: true, debt: result.debt ?? 0, revision: result.revision });
      return {
        ok: true,
        op,
        debt: result.debt ?? 0,
        revision: result.revision,
        artboards: (result.artboards || []).map(a => ({ id: a.id, name: a.name })),
      };
    },
  };
}

// 内置模板清单（与引擎 list-templates 同源；由 bridge 注入到指令）
const ENGINE_TEMPLATES = `login(登录页 390x844) | signup(注册页 390x844) | dashboard(仪表盘 390x844)
profile(个人主页 390x844) | settings(设置页 390x844) | list_detail(列表-详情 390x844)
onboarding(引导页 390x844) | empty_state(空状态页 390x844) | web_landing(Web落地页 1280x800)
web_login(Web登录 1280x800) | web_dashboard(Web仪表盘 1280x800) | pc_app(PC桌面应用 1440x900)
adaptive_landing(自适应落地页 1280x800) | login_v2(登录页v2 390x844)`;

const INSTRUCTIONS = `You are the embedded fx agent of deepDesign Studio, a visual prototyping editor.
The project's single source of truth is one MoonBit literate .mbt.md document held by the host.
You can build COMPLETE interactive prototypes: multiple artboards connected by tap-navigation flows.

## Workflow for building a prototype from a natural-language request (e.g. "make a WeChat-style social app"):
1. If the document has no artboards yet, call moonviz_op with "template <template_id> <name> <w> <h>" for EACH screen the app needs. Available templates:
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
- Discover available UI components with list_components before placing new ones.
- When the user goal is reached, stop calling tools and summarize briefly.`;

// OpenAI 兼容端点的本地转发：libfx 只允许 Gateway 或 loopback HTTP 作为
// gatewayChatUrl，远程厂商端点（DeepSeek/Kimi/GLM/MiniMax 等均为 OpenAI chat
// 格式）经此转发，鉴权头由厂商 baseURL 的 token 承担。
const PROVIDER_PRESETS = {
  deepseek:     'https://api.deepseek.com',
  kimi:         'https://api.moonshot.cn/v1',
  glm:          'https://open.bigmodel.cn/api/paas/v4',
  minimax:      'https://api.minimax.cn/v1',     // 国内站（OpenAI 兼容）
  'minimax-intl': 'https://api.minimax.chat/v1', // 国际站
};

// MiniMax 思考控制：thinking_level → chat/completions body 注入。
// M3 三态 + 努力等级（M2.x 恒开，字段被接受并忽略）：
//   off / auto / on(强制) — thinking.type = disabled | adaptive | enabled
//   low / medium / high   — thinking.type = adaptive + 顶层 reasoning_effort
//     （effort 为 OpenAI 兼容字段：官方 Responses API 与 vLLM/第三方托管
//       均识别；官方 chat 端点当前不调深度，字段被安全忽略）
// reasoning_split:true 让 thinking 走 reasoning_content，避免混入 content。
function minimaxRequestBodyPatch(level) {
  const t = (type) => (obj) => {
    obj.thinking = { type };
    obj.reasoning_split = true;
  };
  if (!level || level === 'auto' || level === 'adaptive') return t('adaptive');
  if (level === 'off' || level === 'disabled') return t('disabled');
  if (level === 'on' || level === 'enabled') return t('enabled');
  if (level === 'low' || level === 'medium' || level === 'high') {
    return (obj) => {
      obj.thinking = { type: 'adaptive' };
      obj.reasoning_effort = level;
      obj.reasoning_split = true;
    };
  }
  return null;
}

async function startOpenAIForwarder(baseURL, bodyPatcher = null) {
  const server = http.createServer(async (req, res) => {
    try {
      const chunks = [];
      for await (const c of req) chunks.push(c);
      let body = Buffer.concat(chunks);
      if (bodyPatcher && body.length && (req.headers['content-type'] || '').includes('json')) {
        try {
          const obj = JSON.parse(body.toString('utf8'));
          bodyPatcher(obj);
          body = Buffer.from(JSON.stringify(obj), 'utf8');
        } catch { /* body 不是 JSON 则原样转发 */ }
      }
      const target = baseURL.replace(/\/$/, '') + req.url;
      const headers = { ...req.headers };
      delete headers.host; delete headers.connection;
      delete headers['content-length'];
      headers['content-length'] = body.length;
      const upstream = await fetch(target, {
        method: req.method, headers, body: body.length ? body : undefined,
      });
      res.writeHead(upstream.status, Object.fromEntries(upstream.headers));
      if (upstream.body) {
        const buf = Buffer.from(await upstream.arrayBuffer());
        res.end(buf);
      } else res.end();
    } catch (e) {
      res.writeHead(502, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: { message: String(e && e.message) } }));
    }
  });
  await new Promise((resolve, reject) => {
    server.listen(0, '127.0.0.1', () => resolve());
    server.on('error', reject);
  });
  const port = server.address().port;
  // fx 要求 chat 端点形式；转发到厂商的 /chat/completions 由 fx 请求路径决定
  return { server, gatewayChatUrl: `http://127.0.0.1:${port}/chat/completions` };
}

async function runWithFx({ instruction, mbt_b64, api_key, model, base_url, thinking_level, engine_dir }) {
  let libfx;
  try {
    libfx = await import('libfx');
  } catch {
    return { ok: false, error: 'fxsdk_not_installed', detail: 'cd agent && npm install libfx' };
  }
  const apiKey = api_key || process.env.AI_GATEWAY_API_KEY;
  if (!apiKey) return { ok: false, error: 'fxsdk_api_key_missing' };

  // baseURL（OpenAI 兼容）→ 本地 loopback 转发 + gatewayChatUrl
  let forwarder = null;
  const options = { apiKey, model: model || undefined, instructions: INSTRUCTIONS, tools: null };
  if (base_url) {
    const key = String(base_url).trim().toLowerCase();
    const target = PROVIDER_PRESETS[key] || String(base_url).trim();
    // 思考等级仅对 MiniMax 系端点注入（其他 OpenAI 兼容厂商不识别该字段）
    const patcher = /minimax/i.test(target) ? minimaxRequestBodyPatch(thinking_level) : null;
    forwarder = await startOpenAIForwarder(target, patcher);
    options.gatewayChatUrl = forwarder.gatewayChatUrl;
  }

  const engineDir = engine_dir || DEFAULT_ENGINE;
  if (!existsSync(join(engineDir, 'cli'))) return { ok: false, error: 'engine_dir_invalid' };

  const ex = makeExecutor(engineDir);
  if (mbt_b64) {
    let mbtText;
    try { mbtText = b64decode(mbt_b64); } catch { return { ok: false, error: 'mbt_b64_invalid' }; }
    // Engine pre-validation: fx never starts from an invalid source of truth.
    const pre = await runMoonCli(engineDir, [`render-mbt-b64 ${b64encode(mbtText)}`]);
    const preOk = pre.find(r => r && typeof r === 'object' && r.ok === true && Array.isArray(r.artboards));
    if (!preOk) {
      const err = pre.find(r => r && r.error);
      return { ok: false, error: 'mbt_invalid', detail: (err && err.error) || 'render_failed' };
    }
    ex.setMbt(mbtText);
  }

  const tools = [
    {
      name: 'moonviz_op',
      description: 'Execute one MoonViz design operation. Each call is validated by the engine (AgentGate) and committed to the canonical .mbt.md.',
      inputSchema: {
        type: 'object',
        properties: { op: { type: 'string', description: 'One operation string, e.g. "update login title fill=#28a745"' } },
        required: ['op'],
      },
      execute: async (input) => ex.moonvizOp(input.op),
    },
    {
      name: 'read_mbt',
      description: 'Read the current canonical .mbt.md source of truth.',
      inputSchema: { type: 'object', properties: {} },
      execute: async () => ex.readMbt(),
    },
    {
      name: 'list_components',
      description: 'List all engine UI component presets (id, category, variants).',
      inputSchema: { type: 'object', properties: {} },
      execute: async () => ex.listComponents(),
    },
  ];

  options.tools = tools;
  const agent = await libfx.createFxAgent(options);
  try {
    const turn = agent.prompt(instruction);
    for await (const ev of turn) {
      if (ev.type === 'tool_start') ex.log().push({ op: `tool:${ev.name}`, ok: true });
    }
    const result = await turn.result;
    if (result?.stopReason === 'refused') {
      return { ok: false, error: 'fx_auth_refused', detail: 'AI Gateway 拒绝了请求：请检查 API Key/额度（fx login / fx setup）' };
    }
    if (!ex.mbt()) return { ok: false, error: 'fx_no_mbt', stopReason: result?.stopReason };
    return {
      ok: true,
      mbt_b64: b64encode(ex.mbt()),
      render: ex.render(),
      ops: ex.ops(),
      log: ex.log(),
      stopReason: result?.stopReason,
    };
  } catch (e) {
    return { ok: false, error: 'fx_run_failed', detail: String(e && e.message).slice(0, 300) };
  } finally {
    await agent.close().catch(() => {});
    if (forwarder) forwarder.server.close();
  }
}

async function selftest({ mbt_b64, engine_dir }) {
  // Exercises the same executor/tool path as fx without needing an API key:
  // two ops, one valid edit + one structural violation that must be rejected.
  const engineDir = engine_dir || DEFAULT_ENGINE;
  if (!existsSync(join(engineDir, 'cli'))) return { ok: false, error: 'engine_dir_invalid' };
  const ex = makeExecutor(engineDir);
  // 引擎自查第一个画板 id，避免硬编码（MBT 是外部输入）
  // load-mbt 使引擎可查询（query 作用于当前会话 Project）；probe 出首画板与首节点
  const probe = await runMoonCli(engineDir, [`load-mbt-b64 ${mbt_b64}`]);
  const q = await runMoonCli(engineDir, [`load-mbt-b64 ${mbt_b64}`, 'query ' + (probe.find(r => r && r.ok)?.entry || '')]);
  const nodesList = q.find(r => Array.isArray(r));
  const board = probe.find(r => r && r.ok)?.entry;
  const node = nodesList?.[0]?.id;
  if (!board || !node) return { ok: false, error: 'selftest_no_target' };
  ex.setMbt(b64decode(mbt_b64));
  const ok1 = await ex.moonvizOp(`update ${board} ${node} fill=#28a745`);
  const bad = await ex.moonvizOp(`move ${board} nonexistent_node_xyz 99999 0`);
  const ok2 = await ex.moonvizOp(`move ${board} ${node} 20 30`);
  return {
    ok: ok1.ok && !bad.ok && ok2.ok,
    validEditApplied: ok1.ok,
    structuralViolationRejected: !bad.ok,
    violationError: bad.error,
    finalRevision: ok2.revision,
    ops: ex.ops(),
    log: ex.log(),
    mbt_b64: ex.mbt() ? b64encode(ex.mbt()) : null,
  };
}

// 模型列表：GET {resolved_base}/models（OpenAI 标准）。
// 返回 { ok, models:[{id}] }；端点不支持时由调用方回退静态清单。
async function listModels({ api_key, base_url }) {
  const apiKey = api_key || process.env.AI_GATEWAY_API_KEY;
  if (!apiKey) return { ok: false, error: 'fxsdk_api_key_missing' };
  const target = PROVIDER_PRESETS[String(base_url || '').trim().toLowerCase()] || String(base_url || '').trim();
  if (!target) return { ok: false, error: 'models_base_url_required' };
  try {
    const res = await fetch(target.replace(/\/$/, '') + '/models', {
      headers: { Authorization: `Bearer ${apiKey}` },
    });
    const text = await res.text();
    let json;
    try { json = JSON.parse(text); } catch { return { ok: false, error: 'models_response_invalid', detail: text.slice(0, 200) }; }
    if (!res.ok) {
      return { ok: false, error: 'models_http_' + res.status, detail: (json.error && json.error.message) || text.slice(0, 200) };
    }
    const arr = Array.isArray(json.data) ? json.data : (Array.isArray(json.models) ? json.models : []);
    const models = arr.map(m => ({ id: m.id || m.model || String(m) })).filter(m => m.id);
    return { ok: true, base: target, models };
  } catch (e) {
    return { ok: false, error: 'models_fetch_failed', detail: String(e && e.message).slice(0, 200) };
  }
}

const input = JSON.parse(await readStdin());
try {
  const out = input.mode === 'selftest' ? await selftest(input)
    : input.mode === 'models' ? await listModels(input)
    : await runWithFx(input);
  process.stdout.write(JSON.stringify(out));
} catch (e) {
  process.stdout.write(JSON.stringify({ ok: false, error: 'bridge_failed', detail: String(e && e.message).slice(0, 300) }));
}
