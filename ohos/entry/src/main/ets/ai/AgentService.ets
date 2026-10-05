// Agent 执行链（batch-9 平级化重写）——选定执行者优先，不是兜底：
//   provider=xiaoyi → 端侧小艺（失败诚实降级本地解析兜底）；
//   其余 provider → 云端 OpenAI 兼容（无 key 不发起 dispatch，直接本地兜底并如实标注——
//   复审 finding-1 后门收口，Dispatch 侧隐性改道已删）。
//
// 分层：模型/命令行/兜底产出 → 澄清门（isClarify，修订 1：先于 applyText）→ 意图解析
// （模板/改色/改文字）→ AppStore 执行。onStep 逐步推进实时轨迹（gap-right-4）。

import { chatOnce } from './LocalChatBridge';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CommandDispatch, extractOps } from '../invoke/Dispatch';
import { aiConfig, AiConf } from '../model/AiConfig';

export interface AgentOutcome {
  ok: boolean;
  reply: string;            // 给用户看的话术（澄清时=提问全文，不截断）
  executed: boolean;        // 是否已落到画布
  ops: number;              // 本次 run 实际执行 op 数（batch-9 替换 interim ≤1 口径：命令行
                            // 路径=成功执行的命令行条数；意图路径=模板/改色/改文字各计 1、
                            // 失败/澄清计 0——绿胶囊计数与实际执行一一同面）
}

/** 命令行执行回包（batch-9 cur-5）：Index 注入的执行器逐行回执。 */
export interface LineExecOutcome {
  ok: boolean;              // 是否实际执行（检视类/未支持动词=false 诚实计数）
  note: string;             // 执行/跳过说明（轨迹与回复引用）
}

/** 命令行执行器（Index 注入）：单条命令行 → AppStore 支持子集执行。 */
export type LineExecutor = (line: string) => LineExecOutcome;

/** 实时轨迹事件（gap-right-4）。kind: plan | tool_start | tool_end | done | failed */
export interface AgentStep {
  kind: string;
  label: string;
  detail: string;
  ms: number;
  ok: boolean;
}

/** invoke_fx_sdk chat 返回的具名形状（Dispatch 内部接口未导出，按字段对齐）。 */
interface FxOutcome {
  content?: string;
  error?: string;
  message?: Record<string, Object>;   // M3.6.4：原始 assistant 消息（含 tool_calls）
}

/** run 调优透传（batch-3，audit-modal-6）：设置卡思考等级/步数上限原样带入。
 * 方言注入（reasoning_effort/chat_template_kwargs 等）归 gap-global-3——本批仅透传+轨迹留痕。 */
export interface RunTuning {
  thinkingLevel: string;   // off|auto|low|medium|high|max
  maxSteps: number;        // 200|500|1000|2000
}

export class AgentService {
  private xiaoyiTried: boolean = false;
  private xiaoyiOk: boolean = false;
  private dispatch: CommandDispatch | null = null;
  private lineExec: LineExecutor | null = null;

  /** Index 持有带 context 的 dispatch 实例（云端通道与模型快照回落共用）。 */
  attachDispatch(d: CommandDispatch): void {
    this.dispatch = d;
  }

  /** 命令行执行器注入（batch-9 cur-5）：Index 提供 AppStore 支持子集的逐行执行。 */
  attachLineExec(fn: LineExecutor): void {
    this.lineExec = fn;
  }

  /** 端侧小艺可用性（设置面板/顶栏状态显示）。带超时（init 挂起保护）。 */
  async probe(): Promise<boolean> {
    if (this.xiaoyiTried) return this.xiaoyiOk;
    this.xiaoyiTried = true;
    try {
      const r = await chatOnce('ping', '');
      this.xiaoyiOk = r !== null && r.length > 0;
    } catch (e) {
      this.xiaoyiOk = false;
    }
    return this.xiaoyiOk;
  }

  /**
   * 执行用户指令（batch-9 选定执行者优先链）：provider=xiaoyi 走小艺、其余走云端（无 key
   * 不发起请求），任一渠道失败诚实降级本地解析兜底。三渠道共用澄清门、命令行解析与意图执行。
   * 修订 1：isClarify 门先于 applyText——问句特征或无可执行意图动词一律判澄清，
   * 返回 {ok:true, executed:false, reply:原文完整}（不截断，澄清面板需全文）。
   */
  async run(instruction: string, mbtSummary: string, applyTemplate: (tid: string) => boolean,
    applyText: (text: string) => boolean, applyColor: (color: string) => boolean,
    onStep?: (ev: AgentStep) => void, opts?: RunTuning, mbtNow?: () => string,
    readMbt?: () => string, engineApply?: (op: string) => Promise<LineExecOutcome>): Promise<AgentOutcome> {
    const t0 = Date.now();
    const step = (kind: string, label: string, detail: string, ok: boolean): void => {
      if (onStep) onStep({ kind: kind, label: label, detail: detail, ms: Date.now() - t0, ok: ok });
    };
    step('plan', '计划', instruction, true);
    const conf = aiConfig.load();

    // 命令行解析执行（batch-9 cur-5，三渠道统一：小艺/云端回复与本地兜底原始指令同面）：
    // extractOps 提取动词行 → Index 注入执行器逐行执行支持子集；检视类/未支持动词诚实
    // 计数不执行；绿胶囊 ops=实际执行条数。无命令行返回 null 落回意图链。
    const execCommandFlow = (t: string, source: string): AgentOutcome | null => {
      const lines = extractOps(t);
      if (lines.length === 0) return null;
      let done = 0;
      const notes: string[] = [];
      const skipped: string[] = [];
      for (const line of lines) {
        const r = this.lineExec !== null ? this.lineExec(line) : null;
        if (r !== null && r.ok) {
          done++;
          notes.push(r.note);
        } else {
          skipped.push(r !== null ? r.note : '执行器未注入');
        }
      }
      const tail = skipped.length > 0 ? `（跳过 ${skipped.length}：${skipped.join('、').slice(0, 60)}）` : '';
      step('tool_end', `命令流 ${done}/${lines.length}`, notes.join(' · ').slice(0, 80), done > 0);
      if (done > 0) {
        return { ok: true, reply: `${source}：已执行 ${done}/${lines.length} 条命令${tail}`,
          executed: true, ops: done };
      }
      // 全部未执行（检视类/未支持动词）：诚实计数进回复，不算失败也不进澄清
      return { ok: true, reply: `${source}：识别到 ${lines.length} 条命令，暂无可执行项${tail}`,
        executed: false, ops: 0 };
    };

    // 意图执行（三渠道共用）：命令行 → 模板 → 改色 → 澄清门 → 改文字
    const executeReply = (t: string, source: string): AgentOutcome => {
      const flow = execCommandFlow(t, source);
      if (flow !== null) return flow;
      const tid = this.matchTpl(t);
      if (tid && applyTemplate(tid)) {
        step('tool_end', `模板 ${this.tplName(tid)}`, source, true);
        return { ok: true, reply: `${source}：${this.tplName(tid)} 已生成`, executed: true, ops: 1 };
      }
      const color = this.matchColor(t);
      if (color && applyColor(color)) {
        step('tool_end', `改色 ${color}`, source, true);
        return { ok: true, reply: `${source}：已应用颜色 ${color}`, executed: true, ops: 1 };
      }
      if (this.isClarify(t)) {
        step('tool_end', '澄清', '模型请求补充信息', true);
        return { ok: true, reply: t, executed: false, ops: 0 };
      }
      if (applyText(t)) {
        step('tool_end', '改文字', source, true);
        return { ok: true, reply: `${source}：已更新文案`, executed: true, ops: 1 };
      }
      step('tool_end', '未识别可执行意图', '按澄清展示', false);
      return { ok: true, reply: t, executed: false, ops: 0 };
    };

    // 1) 选定执行者：provider=xiaoyi → 端侧小艺（batch-9 平级化；不注入 RunTuning 透传留痕——免适配）
    if (conf.provider === 'xiaoyi') {
      step('tool_start', '小艺调用', '', true);
      try {
        const reply = await chatOnce(instruction, mbtSummary);
        if (reply !== null && reply.trim().length > 0) {
          step('tool_end', '小艺回复', reply.trim().slice(0, 80), true);
          const outcome = executeReply(reply.trim(), '小艺');
          return await this.maybeReview(outcome, instruction, applyTemplate, applyText, applyColor, onStep, mbtNow);
        }
      } catch (e) { /* 端侧不可用 → 本地兜底 */ }
      step('tool_end', '小艺不可用', '本地解析兜底', false);
    } else if (conf.apiKey.trim() !== '' && this.dispatch !== null) {
      // 2) 选定执行者：云端 OpenAI 兼容（有 key 且 dispatch 已挂）——M3.6.4 起【真 agent
      // loop】：多轮 tool-calling（moonviz_op/read_mbt），模型自规划 op 序列、看结果迭代，
      // 收尾审查注入轮内（桌面 agent.rs 同构）；工具面不可用/网络失败诚实降级单轮意图链。
      try {
        return await this.agentLoop(instruction, conf, opts ?? null, onStep, readMbt,
          engineApply, applyTemplate, applyText, applyColor);
      } catch (e) {
        step('tool_end', '工具循环不可用，降级单轮意图解析', (e as Error).message.slice(0, 60), false);
      }
    } else {
      // 复审 finding-1 收口：无 key 不发起 dispatch（Dispatch 隐性改道已删），轨迹如实标注
      step('tool_end', '云端未配置 Key', '本地解析兜底', false);
    }

    // 3) 本地解析兜底（与桌面版兜底一致；共用澄清门与命令行解析）
    step('tool_start', '本地解析', instruction.slice(0, 60), true);
    const flow = execCommandFlow(instruction, '本地');
    if (flow !== null) {
      return flow;
    }
    const tid = this.matchTpl(instruction);
    if (tid && applyTemplate(tid)) {
      step('tool_end', `模板 ${this.tplName(tid)}`, '本地', true);
      return { ok: true, reply: '已通过模板提交（本地解析兜底）', executed: true, ops: 1 };
    }
    const color = this.matchColor(instruction);
    if (color && applyColor(color)) {
      step('tool_end', `改色 ${color}`, '本地', true);
      return { ok: true, reply: `已应用颜色 ${color}（本地解析）`, executed: true, ops: 1 };
    }
    if (this.isClarify(instruction)) {
      const q = this.localClarifyQuestion(instruction);
      step('tool_end', '澄清', '需要补充信息', true);
      return { ok: true, reply: q, executed: false, ops: 0 };
    }
    if (applyText(instruction)) {
      step('tool_end', '改文字', '本地', true);
      return { ok: true, reply: '已更新文案（本地解析）', executed: true, ops: 1 };
    }
    step('failed', '失败', '无可执行意图', false);
    return { ok: false, reply: '试试更具体的指令：生成手机登录页 / 生成注册页 / 把标题改成蓝色，或输入命令行（如 template web_login b1 1280 800）', executed: false, ops: 0 };
  }

  /**
   * 真 agent loop（M3.6.4，桌面 agent.rs run() 的鸿蒙同构）：多轮 OpenAI 兼容
   * tool-calling——messages 累积，assistant(tool_calls) 原样回填、逐 op 经 lineExec
   * （引擎人类门优先）执行并以 role:'tool' 回填结果；无 tool_calls 时按桌面语义
   * 先注入收尾审查轮（reviewDone 单次）再收报告；澄清=纯文本回复（无工具调用）。
   * 轮次预算 24（登记偏离：桌面 maxSteps 200-2000 为 Rust 循环步、每步引擎直调；
   * 鸿蒙每步一次 HTTP 往返——故 moonviz_op 支持多行批量、一轮落一批 op（M3.6.5），
   * 24 轮 × 批量即覆盖完整需求构建；RunTuning.maxSteps 暂不直接消费）。
   * 任何一轮 HTTP/协议失败抛错 → run() 诚实降级单轮意图链。
   */
  private async agentLoop(instruction: string, conf: AiConf, opts: RunTuning | null,
    onStep?: (ev: AgentStep) => void, readMbt?: () => string,
    engineApply?: (op: string) => Promise<LineExecOutcome>,
    applyTemplate?: (tid: string) => boolean, applyText?: (text: string) => boolean,
    applyColor?: (color: string) => boolean): Promise<AgentOutcome> {
    return this.agentLoopInner(instruction, conf, opts, onStep, readMbt, engineApply,
      applyTemplate, applyText, applyColor);
  }

  private async agentLoopInner(instruction: string, conf: AiConf, opts: RunTuning | null,
    onStep?: (ev: AgentStep) => void, readMbt?: () => string,
    engineApply?: (op: string) => Promise<LineExecOutcome>,
    applyTemplate?: (tid: string) => boolean, applyText?: (text: string) => boolean,
    applyColor?: (color: string) => boolean): Promise<AgentOutcome> {
    const t0 = Date.now();
    const step = (kind: string, label: string, detail: string, ok: boolean): void => {
      if (onStep) onStep({ kind: kind, label: label, detail: detail, ms: Date.now() - t0, ok: ok });
    };
    step('plan', '计划', instruction, true);
    if (opts !== null) {
      step('plan', `调优 思考=${opts.thinkingLevel} · 步数=${opts.maxSteps}`, '', true);
    }
    // ArkTS：对象字面量必须逐层显式 Record 标注（arkts-no-untyped-obj-literals）
    const opProp: Record<string, Object> = {
      'type': 'string', 'description': 'One operation string, e.g. "set login title color=#007aff"'
    };
    const opProps: Record<string, Object> = { 'op': opProp };
    const mvRequired: Array<string> = ['op'];
    const mvParams: Record<string, Object> = { 'type': 'object', 'properties': opProps, 'required': mvRequired };
    const mvFn: Record<string, Object> = {
      'name': 'moonviz_op',
      'description': 'Execute MoonViz design operations (validated by the engine gates, committed to the canonical document). ' +
        'BATCHING: you MAY put multiple operations in one call — separate them with newlines, one op per line, executed in order. ' +
        'Batch aggressively (e.g. build a whole screen in one call) to minimize round trips. ' +
        'Ops: "template <tid>" create an artboard from a preset; "create <id> <w> <h>" blank artboard; ' +
        '"text <board> <node> <text>" set or add text; "set <board> <node> <key>=<value>" style keys color/fontSize/bold/opacity/radius; ' +
        '"move <board> <node> <dx> <dy>"; "delete <board> <node>"; "delete-artboard <board>"; "flow <fromBoard>.<node> <toBoard>" wire interaction.',
      'parameters': mvParams
    };
    const mvTool: Record<string, Object> = { 'type': 'function', 'function': mvFn };
    const noProps: Record<string, Object> = {};
    const noRequired: Array<string> = [];
    const rmParams: Record<string, Object> = { 'type': 'object', 'properties': noProps, 'required': noRequired };
    const rmFn: Record<string, Object> = {
      'name': 'read_mbt',
      'description': 'Read the current canonical document source (artboards, node ids, flows) — call when unsure about ids.',
      'parameters': rmParams
    };
    const rmTool: Record<string, Object> = { 'type': 'function', 'function': rmFn };
    const tools: Array<Object> = [mvTool, rmTool];
    const messages: Array<Record<string, Object>> = [
      { 'role': 'system', 'content': LOOP_SYS },
      { 'role': 'user', 'content': instruction }
    ];
    const ROUNDS = 24;   // M3.6.5：12→24，配合批量 op（一轮可落整屏）覆盖完整需求构建
    let ops = 0;
    let reviewDone = false;
    for (let round = 0; round < ROUNDS; round++) {
      step('tool_start', `云端请求 ${conf.model} · 第 ${round + 1}/${ROUNDS} 轮`, conf.baseUrl, true);
      const v = await this.loopChat(messages, tools, conf);
      if (typeof v.error === 'string' && v.error !== '') {
        hilog.error(0x0000, 'ddAgent', 'round %{public}d failed: %{public}s', round + 1, v.error.slice(0, 120));
        throw new Error(v.error);
      }
      const msg = (v.message ?? {}) as Record<string, Object>;
      const tcs = (msg['tool_calls'] ?? []) as Array<Record<string, Object>>;
      const content = typeof msg['content'] === 'string' ? msg['content'] as string : '';
      if (tcs.length === 0) {
        // 无工具调用：审查注入点（桌面 review 语义，单次）或收报告
        if (!reviewDone && ops > 0) {
          reviewDone = true;
          step('review', '🔎 收尾审查', '需求完整度 · 连线完整度 · 综合修复', true);
          if (content.trim() !== '') {
            const am: Record<string, Object> = { 'role': 'assistant', 'content': content };
          messages.push(am);
          }
          const rm: Record<string, Object> = { 'role': 'user', 'content': REVIEW_PROMPT(instruction) };
          messages.push(rm);
          continue;
        }
        if (content.trim() === '') break;
        step('tool_end', '云端回复', content.trim().slice(0, 80), true);
        if (ops === 0 && this.isClarify(content)) {
          step('tool_end', '澄清', '模型请求补充信息', true);
          return { ok: true, reply: content, executed: false, ops: 0 };
        }
        if (ops > 0) {
          return { ok: true, reply: content.trim(), executed: true, ops: ops };
        }
        // 0 op 且非澄清：模型只回文本没干活 → 兜底意图链（模板/改色/改文字）
        if (applyTemplate !== undefined && applyText !== undefined && applyColor !== undefined) {
          const r = this.reviewExec(content, applyTemplate, applyText, applyColor);
          if (r.executed) {
            step('tool_end', '意图落地', r.reply, true);
            return { ok: true, reply: content.trim(), executed: true, ops: r.ops };
          }
        }
        return { ok: true, reply: content.trim(), executed: false, ops: 0 };
      }
      // assistant(tool_calls) 原样回填（wire 契约：后续 role:'tool' 需与其 id 配对）
      messages.push(msg);
      for (const tc of tcs) {
        const fn = tc['function'] as Record<string, string> | undefined;
        const name = String(fn?.['name'] ?? '');
        const tcId = String(tc['id'] ?? `call_${round}`);
        if (name === 'read_mbt') {
          const doc = readMbt !== undefined ? readMbt() : '';
          // M3.6.6：结构大纲代替全文——板/节点(id+component+text)/flows 全量 id 在场，
          // 但体积从 ~18KB 降到 ~4KB（全文回灌撑爆上下文、轮次时延爆炸的实证根因）
          const outline = doc.split('\n')
            .filter((l: string): boolean => l.startsWith('## ') || l.includes('id="') ||
              l.includes('component="') || l.startsWith('flow '))
            .map((l: string): string => l.trim())
            .join('\n').slice(0, 4000);
          step('tool_end', 'read_mbt', `${outline.length} 字节（大纲）`, true);
          const tm: Record<string, Object> = { 'role': 'tool', 'tool_call_id': tcId, 'content': outline };
          messages.push(tm);
          continue;
        }
        let op = '';
        try {
          const argv = JSON.parse(String(fn?.['arguments'] ?? '{}')) as Record<string, string>;
          op = String(argv['op'] ?? '');
        } catch (e) { op = ''; }
        if (op === '') {
          const em: Record<string, Object> = { 'role': 'tool', 'tool_call_id': tcId, 'content': '{"ok":false,"error":"empty op"}' };
          messages.push(em);
          continue;
        }
        // M3.6.5 批量执行：op 可含多行（一行一命令），顺序执行、聚合一笔回填——
        // 一轮 HTTP 落一批 op（每步一次往返的管道开销摊薄 10 倍+，12 轮不够的根因即此）
        const lines = op.split(/\r?\n/).map((x: string): string => x.trim()).filter((x: string): boolean => x !== '');
        let done = 0;
        const notes: string[] = [];
        for (const one of lines) {
          // M3.6.6：engineApply 优先——完整引擎 op 词表直连人类门（桌面同面：place/update
          // 全键/interact/state/align/constrain/fix...）；lineExec 仅无引擎闭包时的兜底
          const r = engineApply !== undefined ? await engineApply(one) :
            (this.lineExec !== null ? this.lineExec(one) : null);
          const ok = r !== null && r.ok;
          if (ok) { ops++; done++; }
          notes.push(`${ok ? '✓' : '✗'} ${one.slice(0, 40)}${r !== null ? ' :: ' + r.note : ' :: executor missing'}`);
          step('tool_end', `${ok ? '✓' : '✗'} ${one.slice(0, 44)}`, r !== null ? r.note : '执行器未注入', ok);
        }
        const noteJson = notes.map((x: string): string => x.replace(/"/g, "'")).join('\\n').slice(0, 1800);
        const tr: Record<string, Object> = { 'role': 'tool', 'tool_call_id': tcId,
          'content': `{"ok":${done > 0 ? 'true' : 'false'},"executed":${done},"total":${lines.length},"detail":"${noteJson}"}` };
        messages.push(tr);
      }
    }
    if (ops > 0) {
      return { ok: true, reply: `已完成 ${ops} 项操作（轮次预算用尽）`, executed: true, ops: ops };
    }
    step('failed', '失败', '轮次预算内无可执行操作', false);
    return { ok: false, reply: '模型未给出可执行操作', executed: false, ops: 0 };
  }

  /** loop 专用 chat（messages/tools 直传 Dispatch invoke_fx_sdk；错误以 error 字段带回）。 */
  private async loopChat(messages: Array<Record<string, Object>>, tools: Array<Object>,
    conf: AiConf): Promise<FxOutcome> {
    if (this.dispatch === null) return { error: 'dispatch 未注入' };
    const payload: Record<string, Object> = {
      'mode': 'chat',
      'baseUrl': conf.baseUrl,
      'model': conf.model,
      'messages': messages as Object,
      'maxTokens': 2048,
      'tools': tools as Object,
      'toolChoice': 'auto'
    };
    const args: Record<string, Object> = { 'apiKey': conf.apiKey, 'payload': JSON.stringify(payload) };
    const v: Object | null = await this.dispatch.dispatch('invoke_fx_sdk', args);
    if (v === null) {
      hilog.error(0x0000, 'ddAgent', 'loopChat: dispatch null');
      return { error: 'dispatch 返回空' };
    }
    const o = v as FxOutcome;
    hilog.info(0x0000, 'ddAgent', 'loopChat: err=%{public}s contentLen=%{public}d hasMsg=%{public}s',
      String(o.error ?? ''), (o.content ?? '').length, String(o.message !== undefined));
    return o;
  }

  /**
   * 收尾审查轮（M3.6.4，对齐桌面 agent.rs 收尾审查层/moonviz#20 三段语义：需求完整度/
   * 操作逻辑连线/综合修复）：主轮执行成功（executed 且 ops>0）才发起；同通道单轮、
   * 指令明令「不得提问」，澄清形回复一律吞为「审查通过」；审查回复复用命令流/模板/
   * 改色/改文字执行链（修复 op 直接落画布并计入 ops）。本地兜底轮不审查（无 LLM 可用，
   * 登记偏离：桌面为 LLM 循环内注入层，鸿蒙为单轮附加、不消耗 RunTuning.maxSteps）。
   * 审查失败不改变主轮结果（诚实降级为「审查跳过」）。
   */
  private async maybeReview(outcome: AgentOutcome, instruction: string,
    applyTemplate: (tid: string) => boolean, applyText: (text: string) => boolean,
    applyColor: (color: string) => boolean, onStep?: (ev: AgentStep) => void,
    mbtNow?: () => string): Promise<AgentOutcome> {
    if (!outcome.executed || outcome.ops <= 0) return outcome;
    const conf = aiConfig.load();
    const xiaoyi = conf.provider === 'xiaoyi';
    const cloudReady = !xiaoyi && conf.apiKey.trim() !== '' && this.dispatch !== null;
    if (!xiaoyi && !cloudReady) return outcome;
    const t0 = Date.now();
    const step = (kind: string, label: string, detail: string, ok: boolean): void => {
      if (onStep) onStep({ kind: kind, label: label, detail: detail, ms: Date.now() - t0, ok: ok });
    };
    const canvas = mbtNow !== undefined ? mbtNow() : '';
    const reviewInstr = '[收尾审查] 设计实现已完成。执行强制收尾审查——不得提问，直接给出修复：\n' +
      `1) 需求完整度：目标「${instruction}」是否全部落实；\n` +
      '2) 操作逻辑连线：可交互元素是否补齐交互流；\n' +
      '3) 综合修复：布局重叠、对齐、配色问题。\n' +
      '无需修复时只回复「审查通过」。需要修复时直接给命令行（如 set b1 title color #007aff）。' +
      (canvas !== '' ? `当前画布：${canvas}` : '');
    step('review', '🔎 收尾审查', '需求完整度 · 连线完整度 · 综合修复', true);
    try {
      let reply: string | null = '';
      if (xiaoyi) {
        reply = await chatOnce(reviewInstr, '');
      } else {
        reply = await this.cloudChat(reviewInstr, canvas, conf);
      }
      if (reply === null || reply.trim() === '' || this.isClarify(reply)) {
        step('review', '审查通过', '无修复项', true);
        return outcome;
      }
      const ro = this.reviewExec(reply, applyTemplate, applyText, applyColor);
      if (ro.executed) {
        step('review', `审查修复落地 +${ro.ops}`, ro.reply.slice(0, 60), true);
        return { ok: true, reply: `${outcome.reply}；审查修复 ${ro.ops} 项`,
          executed: true, ops: outcome.ops + ro.ops };
      }
      step('review', '审查通过', reply.trim().slice(0, 60), true);
      return outcome;
    } catch (e) {
      step('review', '审查跳过', (e as Error).message.slice(0, 40), false);
      return outcome;
    }
  }

  /** 审查轮执行链（executeReply 的审查变体）：无澄清分支（上游已吞）、review 通道专用——
   * 命令流 → 模板 → 改色 → 改文字，执行计数同主轮口径。 */
  private reviewExec(t: string, applyTemplate: (tid: string) => boolean,
    applyText: (text: string) => boolean, applyColor: (color: string) => boolean): AgentOutcome {
    const lines = extractOps(t);
    let done = 0;
    for (const line of lines) {
      const r = this.lineExec !== null ? this.lineExec(line) : null;
      if (r !== null && r.ok) done++;
    }
    if (done > 0) {
      return { ok: true, reply: `命令流 ${done}/${lines.length}`, executed: true, ops: done };
    }
    const tid = this.matchTpl(t);
    if (tid && applyTemplate(tid)) {
      return { ok: true, reply: `模板 ${this.tplName(tid)}`, executed: true, ops: 1 };
    }
    const color = this.matchColor(t);
    if (color && applyColor(color)) {
      return { ok: true, reply: `改色 ${color}`, executed: true, ops: 1 };
    }
    if (applyText(t)) {
      return { ok: true, reply: '文案已修', executed: true, ops: 1 };
    }
    return { ok: false, reply: '', executed: false, ops: 0 };
  }

  /**
   * 修订 1 澄清门：问句特征（？/? 结尾、征询词）或无可执行意图动词
   * （无模板关键词、非明确改字/改色句式）即判澄清。
   * 续跑合并指令（含【回答】标记）不再判澄清，直接尝试执行。
   */
  private isClarify(s: string): boolean {
    if (s.includes('【回答】')) return false;
    if (/[？?]\s*$/.test(s)) return true;
    if (/(需要|是否|想要|偏好|可以告诉我|还是|哪一|哪种|多少)/.test(s)) return true;
    if (this.matchTpl(s) !== '') return false;
    if (this.matchColor(s) !== '') return false;
    if (/(改成|改为|设为|设置为|换成|写作|文案|标题|文字)/.test(s)) return false;
    return true;
  }

  /** 本地兜底的澄清提问（小艺不可用为模拟器常态，验收 4 即走此路径）。 */
  private localClarifyQuestion(instruction: string): string {
    return `收到你的需求：「${instruction}」。\n` +
      '为了直接生成而不是猜测，请补充：\n' +
      '1) 目标形态：手机 / Web / 桌面？\n' +
      '2) 页面构成：需要哪几个核心页面？\n' +
      '3) 风格偏好：配色或参考产品？';
  }

  /** 云端 OpenAI 兼容 chat（Dispatch invoke_fx_sdk 直连，messages 由上下文构造）。 */
  private async cloudChat(instruction: string, mbtSummary: string, conf: AiConf): Promise<string> {
    if (this.dispatch === null) return '';
    const sys = '你是原型设计工具 deepDesign 的执行器。若指令足以执行，直接简短确认要点；' +
      '若信息不足，用中文提出 1-3 个具体问题（以？结尾）。' +
      '可用模板关键词：登录页/注册页/仪表盘/个人主页/设置页/列表/引导/空状态/落地页/桌面应用/Web 登录/Web 落地。' +
      `当前画布：${mbtSummary}`;
    const sysMsg: Record<string, string> = { 'role': 'system', 'content': sys };
    const usrMsg: Record<string, string> = { 'role': 'user', 'content': instruction };
    const messages: Array<Record<string, string>> = [sysMsg, usrMsg];
    const payload: Record<string, Object> = {
      'mode': 'chat',
      'baseUrl': conf.baseUrl,
      'model': conf.model,
      'messages': messages,
      'maxTokens': 1024
    };
    const args: Record<string, Object> = { 'apiKey': conf.apiKey, 'payload': JSON.stringify(payload) };
    const v: Object | null = await this.dispatch.dispatch('invoke_fx_sdk', args);
    if (v === null) return '';
    const r = v as FxOutcome;
    if (typeof r.error === 'string' && r.error !== '') {
      throw new Error(r.error);
    }
    return typeof r.content === 'string' ? r.content : '';
  }

  private matchTpl(s: string): string {
    const map: Record<string, string> = {
      '登录页 v2': 'login_v2', '注册': 'signup', '登录': 'login', '仪表盘': 'dashboard',
      '个人主页': 'profile', '设置页': 'settings', '列表': 'list_detail',   // iss-3：映射值对齐引擎注册 id（原 settings_page）
      '引导': 'onboarding', '空状态': 'empty_state', '落地页': 'adaptive_landing',
      '桌面应用': 'pc_app', 'Web 登录': 'web_login', 'Web 落地': 'web_landing'
    };
    if (s.includes('登录页 v2')) return 'login_v2';
    if (/Web\s*登录/i.test(s)) return 'web_login';
    if (/Web\s*落地/i.test(s)) return 'web_landing';
    for (const k of ['注册', '登录', '仪表盘', '个人主页', '设置页', '列表', '引导', '空状态', '落地页', '桌面应用']) {
      if (s.includes(k)) return map[k] ?? 'login';
    }
    return '';
  }

  private tplName(tid: string): string {
    const names: Record<string, string> = {
      'login': '登录页', 'signup': '注册页', 'dashboard': '仪表盘', 'profile': '个人主页',
      'settings': '设置页', 'list_detail': '列表-详情', 'onboarding': '引导页',   // iss-3：表键随 tid 对齐（原 settings_page；显示名保留）
      'empty_state': '空状态页', 'web_landing': 'Web 落地页', 'web_login': 'Web 登录',
      'web_dashboard': 'Web 仪表盘', 'pc_app': 'PC 桌面应用', 'adaptive_landing': '自适应落地页',
      'login_v2': '登录页 v2'
    };
    return names[tid] ?? tid;
  }

  private matchColor(s: string): string {
    if (/蓝/.test(s)) return '#007aff';
    if (/红/.test(s)) return '#e5484d';
    if (/绿/.test(s)) return '#28a745';
    if (/紫/.test(s)) return '#9d4edd';
    if (/橙|黄/.test(s)) return '#e6a700';
    if (/深色|黑/.test(s)) return '#1c1c1e';
    if (/灰/.test(s)) return '#8e8e93';
    return '';
  }
}

// agent loop 系统提示（M3.6.6：桌面 INSTRUCTIONS 逐段移植——完整引擎 op 语法/
// 构建循环/ground-truth 规则；差异登记：ohos 引擎面无检视类 op 导出，read_mbt 为
// 唯一检视工具、组件发现走模板板 canonical 源的 component="..." 字段；批量 op 为
// 鸿蒙扩展——一轮多行摊薄 HTTP 往返）
const LOOP_SYS: string = `You are the embedded design agent of deepDesign Studio (HarmonyOS), a visual prototyping editor.
You operate as a product designer, not a command executor: interpret what the user wants to
ACHIEVE, decide which screens the experience needs, build them, connect them, and verify the result.
The single source of truth is one MoonBit literate .mbt.md document; every operation you issue is
validated by the engine (AgentGate) and committed immediately, so the user watches progress live.

## Mindset
- Derive intent: "a WeChat-style app" means an experience (login, feed, chat, profile, settings),
  not one artboard. Before the first tool call, state a one-line plan: the screen list and how they connect.
- CLARIFY-FIRST TASKS: when the user explicitly asks you to confirm questions before building,
  reply with those questions as plain text — do NOT call tools and do NOT build yet.
- Think in flows: a prototype is screens + navigation. An unconnected screen is unfinished.
- Write real product copy (realistic labels, names, numbers), never lorem ipsum.
- Full-bleed backgrounds are fine: place a background rect and grow it with
  width_mode=fill & height_mode=fill. Nodes with EXPLICIT sizes must never intersect any
  sibling rect (no_sibling_overlap rejects them): before each place, reserve a
  non-intersecting slot; when you know a node's final size, pass [w] [h] inline.
- Tiny precision nodes (battery/status icons, switches) occupy small rects
  inside bars — place them FIRST, then place larger siblings around them.
- Two modes: BUILD requests get the full loop below; TWEAK requests ("make the button green")
  get read_mbt, one targeted op, done.

## Build loop (from empty document)
1. PLAN: choose screens; map each to a template. Available (template <tid> <name> [w] [h]):
   login, login_v2, signup, dashboard, profile, settings, list_detail, onboarding,
   empty_state, web_login, web_landing, web_dashboard, pc_app, adaptive_landing.
   Artboard names become ids after sanitization — ASCII snake_case only (e.g. chat_list);
   Chinese copy belongs in node text values, never in ids.
2. CREATE: one "template <tid> <name> [w] [h]" per screen, then IMMEDIATELY read_mbt —
   node ids are only discoverable there. Artboard id = sanitized name.
3. CUSTOMIZE: "update <artboard> <node> k=v ..." per screen; finish one before the next.
   "place <artboard> <component> <instance_id> [variant|-] [x] [y] [w] [h]" adds engine
   components — component ids appear as component="..." in read_mbt output of template
   boards (badge/heading/body_text/text_input/button/divider at minimum). ALWAYS pass
   the final [w] [h] when you know them — the gate evaluates the FINAL bbox.
4. CONNECT: "flow <from> <to> <node>" for every primary CTA (login button, card tap, tab, back).
5. VERIFY: read_mbt and check flows cover every screen; every primary CTA wired.
   Run "fix <artboard>" if violations accumulated.
6. REPORT: stop calling tools and reply in Chinese: screens built and the flow map.

## Tweak loop (document already loaded)
0. read_mbt FIRST — always ground ids and flows before any op.
1. Make the minimal ops. 2. Report what changed.

## Operation grammar (multiple ops per moonviz_op call ALLOWED on this face: one per line,
executed in order — batch a whole screen per call to minimize round trips)
  template <template_id> <name> [w] [h] | create <name> [w] [h]
  | duplicate <artboard> <new_name> | delete-artboard <artboard>
  | place <artboard> <component> <instance_id> [variant|-] [x] [y] [w] [h]
  | move <artboard> <node> <x> <y> | update <artboard> <node> k=v [k=v ...]
  | delete <artboard> <node> | copy <artboard> <node> <new_id> [dx] [dy]
  | reorder <artboard> <node> front|back|up|down | flip <artboard> <node> h|v|both|none
  | align <artboard> left|right|top|bottom|hcenter|vcenter <n1> <n2> ...
  | resize-canvas <artboard> <w> <h>
  | interact <artboard> <node> <trigger> <action>  | uninteract <artboard> <node>
  | state <artboard> <node> <state_name> k=v ...   | set-state <node> <state_name> [toggle]
  | flow <from_artboard> <to_artboard> <node> | unflow <from_artboard> <to_artboard> <node>
  | theme <name> (light|dark|high_contrast|sepia|nord|sunset) | fix <artboard>
- update keys: w h text fill text_color stroke stroke_width radius opacity font_size weight
  shadow rotate blur blend line tracking constraint align italic dash visible layout gap
  justify padding width_mode height_mode x_mode y_mode name.
  Quote values with spaces: text="Sign in". Unquoted words after a space are silently dropped.
- interact triggers: tap long_press swipe_left swipe_right swipe_up swipe_down scroll_end
  key_enter focus blur. interact actions: back | navigate_to:<board> | show_toast:<msg> | haptic.

## Ground truth and errors
- NEVER guess node/component/template ids: templates are listed above; everything else:
  read_mbt. Ids are shared with the human canvas: never rename; new ids = snake_case.
- Errors: unknown_artboard/unknown_node/unknown_template → read_mbt then retry with real ids.
  Predicate violations (overflow, overlap) reject the op with predicate + node_id → adjust values;
  if stuck run fix <artboard>. Never repeat an identical failing op.
- On this engine face read-only inspection ops (list/lint/query/list-components/...) are NOT
  available — read_mbt is your only introspection tool. Use it liberally.

## HarmonyOS batching note
You are running with a per-round HTTP budget: BATCH AGGRESSIVELY. Build one complete screen
per moonviz_op call (template line, then all place/update lines, then all flow lines). Aim to
finish the whole request in 3-6 calls.`;

// 收尾审查注入提示（桌面 review_prompt 三段语义同构）
const REVIEW_PROMPT: (goal: string) => string = (goal: string): string =>
  '[收尾审查] 设计实现已完成。执行强制收尾审查——不得提问，直接用工具修复：\n' +
  `1) 需求完整度：目标「${goal}」是否全部落实，缺项直接补建；\n` +
  '2) 操作逻辑连线：可交互元素（按钮/链接）是否已用 flow 建立交互流，缺则补齐；\n' +
  '3) 综合修复：布局重叠、明显对齐与配色问题。\n' +
  '修复完成后给出简短中文报告；若无任何问题，只回复「审查通过」。';

export const agentService: AgentService = new AgentService();
