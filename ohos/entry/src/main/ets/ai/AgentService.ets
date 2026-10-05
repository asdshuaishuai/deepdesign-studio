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
import { agentFeedOnWorker } from '../core/AgentFeedTask';

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
  finishReason?: string;              // M3.6.8：length=截断——工具调用没发全，续跑而非收报告
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

  /** 会话 canonical 回灌回调（M3.6.7）：loop 每轮把推进后的 canonical b64 交还
   * Index（merge+SVG 刷新+sync 全在 Index 侧——appStore 归 UI 层所有）。 */
  private docFlush: ((docB64: string) => void) | null = null;
  attachDocFlush(fn: (docB64: string) => void): void {
    this.docFlush = fn;
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
    onStep?: (ev: AgentStep) => void, opts?: RunTuning, docB64?: string): Promise<AgentOutcome> {
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
          return await this.maybeReview(outcome, instruction, applyTemplate, applyText, applyColor, onStep);
        }
      } catch (e) { /* 端侧不可用 → 本地兜底 */ }
      step('tool_end', '小艺不可用', '本地解析兜底', false);
    } else if (conf.apiKey.trim() !== '' && this.dispatch !== null) {
      // 2) 选定执行者：云端 OpenAI 兼容（M3.6.7 真 agent loop——桌面 agent.rs 同构：
      // loop 状态机/工具执行/引擎调用全在 Rust（rust-core agent.rs，op 于 TaskPool
      // 工作线程过引擎人类门），ArkTS 仅 HTTP 传输泵 + 轨迹渲染）。失败诚实降级。
      if (opts) {
        step('plan', `调优 思考=${opts.thinkingLevel} · 步数=${opts.maxSteps}`, '', true);
      }
      try {
        const st = await this.dispatch.dispatch('agent_start', {
          'instruction': instruction, 'docB64': docB64 ?? ''
        } as Record<string, Object>);
        let sess = JSON.parse(String((st as Record<string, Object>)['json'] ?? '{}')) as Record<string, Object>;
        let guard = 0;
        for (;;) {
          if (++guard > 64) throw new Error('pump guard');
          const action = String(sess['action'] ?? '');
          if (action === 'error') throw new Error(String(sess['error'] ?? 'agent error'));
          if (action === 'done') {
            const oc = (sess['outcome'] ?? {}) as Record<string, Object>;
            const ok = oc['ok'] === true;
            const reply = String(oc['reply'] ?? '');
            const executed = oc['executed'] === true;
            const ops = Number(oc['ops'] ?? 0);
            if (!ok) {
              step('failed', '失败', reply.slice(0, 50), false);
              return { ok: false, reply: reply, executed: false, ops: 0 };
            }
            if (!executed) {
              // 0 op（澄清之外的空报告）：ArkTS 意图链兜底一次
              const r = this.reviewExec(reply, applyTemplate, applyText, applyColor);
              if (r.executed) {
                step('tool_end', '意图落地', r.reply, true);
                return { ok: true, reply: reply, executed: true, ops: r.ops };
              }
            }
            return { ok: ok, reply: reply, executed: executed, ops: ops };
          }
          // action === 'llm'：先渲染上一 feed 的事件（工具执行轨迹），再发起本轮 HTTP
          const evs = (sess['events'] ?? []) as Array<Record<string, Object>>;
          for (const e2 of evs) {
            step(String(e2['kind'] ?? 'tool_end'), String(e2['label'] ?? ''), String(e2['detail'] ?? ''), e2['ok'] === true);
          }
          step('tool_start', `云端请求 ${conf.model}`, conf.baseUrl, true);
          const lvl = (opts ?? { thinkingLevel: 'auto' }).thinkingLevel;
          const fx = await this.loopChat((sess['messages'] ?? []) as Object[],
            (sess['tools'] ?? []) as Object[], conf, lvl);
          if (typeof fx.error === 'string' && fx.error !== '') throw new Error(fx.error);
          const feedJson: string = await agentFeedOnWorker(JSON.stringify({ 'message': fx.message ?? {}, 'finish_reason': fx.finishReason ?? '' }));
          sess = JSON.parse(feedJson) as Record<string, Object>;
          // 活进度：会话 canonical 每轮回灌 Index（merge+SVG 刷新+sync 在 Index 侧；
          // 撤销栈由 run 起点单次快照承担——整个 run 一个撤销边界）
          const docB64Out = String(sess['doc_b64'] ?? '');
          if (docB64Out !== '' && this.docFlush !== null) {
            this.docFlush(docB64Out);
          }
        }
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

  /** 思考方言表（M3.6.6，桌面 agent.rs::thinking_extra_body OpenAI 半区移植——稳定性
   * 支柱：恒思考模型如 StepFun 把 token 预算耗在思考上，maxTokens 不足即返回空消息
   * 断轮；batch-3「仅透传留痕」的欠账就此清偿）。按模型名分部：GLM-5.3 强制思考仅
   * low/high/max；Kimi k3 恒开 off→none；Kimi k2.x/Moonshot/MiniMax/GLM/DeepSeek-off/
   * 未知模型 off→thinking disabled；StepFun 三档无开关；Qwen 仅 vLLM off 方言；
   * auto 不注入。 */
  private thinkingExtraBody(model: string, level: string): Record<string, Object> | null {
    let lv = level;
    if (lv === 'on') lv = 'high';
    const m = model.toLowerCase();
    if (lv === 'auto') return null;
    const thinkDisabled: Record<string, Object> = { 'type': 'disabled' };
    const thinkOff: Record<string, Object> = { 'thinking': thinkDisabled };
    if (m.includes('glm-5.3')) {
      const effort = (lv === 'off' || lv === 'low') ? 'low' : (lv === 'medium' || lv === 'high') ? 'high' : 'max';
      const r: Record<string, Object> = { 'reasoning_effort': effort };
      return r;
    }
    if (m.includes('k3') || m.includes('kimi-for-coding')) {
      const effort = lv === 'off' ? 'none' : (lv === 'medium' ? 'high' : lv);
      const r: Record<string, Object> = { 'reasoning_effort': effort };
      return r;
    }
    if (m.includes('kimi') || m.includes('moonshot')) {
      return lv === 'off' ? thinkOff : null;
    }
    if (m.includes('glm')) {
      if (lv === 'off') return thinkOff;
      const r: Record<string, Object> = { 'reasoning_effort': lv };
      return r;
    }
    if (m.includes('minimax')) {
      return lv === 'off' ? thinkOff : null;
    }
    if (m.includes('step')) {
      const effort = (lv === 'off' || lv === 'low') ? 'low' : (lv === 'max' ? 'high' : lv);
      const r: Record<string, Object> = { 'reasoning_effort': effort };
      return r;
    }
    if (m.includes('deepseek')) {
      if (lv === 'off') return thinkOff;
      const r: Record<string, Object> = { 'reasoning_effort': lv };
      return r;
    }
    if (m.includes('qwen')) {
      if (lv === 'off') {
        const kw: Record<string, Object> = { 'enable_thinking': false };
        const r: Record<string, Object> = { 'chat_template_kwargs': kw };
        return r;
      }
      return null;
    }
    return lv === 'off' ? thinkOff : null;
  }

  /** loop 专用 chat（messages/tools 直传 Dispatch invoke_fx_sdk；错误以 error 字段带回）。 */
  private async loopChat(messages: Object[], tools: Object[],
    conf: AiConf, thinkingLevel: string): Promise<FxOutcome> {
    if (this.dispatch === null) return { error: 'dispatch 未注入' };
    // M3.6.8 发送前消毒：空 content 的 assistant 消息剔除（StepFun 400
    // "Empty chat message" 实证）、剥 reasoning_content 等非标准回显字段
    const wire: Array<Record<string, Object>> = [];
    for (const m0 of messages) {
      const m = m0 as Record<string, Object>;   // Object[] 参数收窄（索引访问须 Record）
      const role = String(m['role'] ?? 'user');
      const c = String(m['content'] ?? '');
      const tcs = m['tool_calls'] as Array<Object> | undefined;
      if (role === 'assistant') {
        if (c === '' && (tcs === undefined || tcs === null)) continue;
        const clean: Record<string, Object> = { 'role': 'assistant', 'content': c };
        if (tcs !== undefined && tcs !== null) clean['tool_calls'] = tcs;
        wire.push(clean);
      } else {
        const clean: Record<string, Object> = { 'role': role, 'content': c };
        if (m['tool_call_id'] !== undefined) clean['tool_call_id'] = m['tool_call_id'];
        wire.push(clean);
      }
    }
    const wireDump = wire.map((m: Record<string, Object>): string =>
      `${String(m['role'])}:${String(m['content'] ?? '').length}${m['tool_calls'] !== undefined ? '+tc' : ''}${m['tool_call_id'] !== undefined ? '+id' : ''}`).join(' | ');
    hilog.info(0x0000, 'ddAgent', 'wire: %{public}s', wireDump);
    const payload: Record<string, Object> = {
      'mode': 'chat',
      'baseUrl': conf.baseUrl,
      'model': conf.model,
      'messages': wire as Object,
      'maxTokens': 16384,   // M3.6.6：2048→8192→16384——推理思考+批量工具调用双耗 token，8192 批量下仍会截断
      'tools': tools as Object,
      'toolChoice': 'auto'
    };
    const extra = this.thinkingExtraBody(conf.model, thinkingLevel);
    if (extra !== null) {
      const keys = Object.keys(extra);
      for (const k of keys) {
        payload[k] = extra[k];
      }
    }
    const args: Record<string, Object> = { 'apiKey': conf.apiKey, 'payload': JSON.stringify(payload) };
    const v: Object | null = await this.dispatch.dispatch('invoke_fx_sdk', args);
    if (v === null) {
      hilog.error(0x0000, 'ddAgent', 'loopChat: dispatch null');
      return { error: 'dispatch 返回空' };
    }
    const o = v as FxOutcome;
    hilog.info(0x0000, 'ddAgent', 'loopChat: err=%{public}s contentLen=%{public}d finish=%{public}s hasMsg=%{public}s',
      String(o.error ?? ''), (o.content ?? '').length, String(o.finishReason ?? ''), String(o.message !== undefined));
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

// 收尾审查注入提示（桌面 review_prompt 三段语义同构）

export const agentService: AgentService = new AgentService();
