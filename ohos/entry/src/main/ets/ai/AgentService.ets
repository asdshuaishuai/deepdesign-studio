// Agent 执行链 —— 端侧小艺（localChatModel）为默认执行者
//
// 分层：小艺产出指令文本 → 意图解析（模板/改文字/改色/移动）→ AppStore 执行。
// 小艺不可用（模拟器无模型管理服务/未就绪）时本地解析兜底，保证指令条可用。

import { chatOnce } from './LocalChatBridge';

export interface AgentOutcome {
  ok: boolean;
  reply: string;            // 给用户看的话术（小艺回复或本地结果）
  executed: boolean;        // 是否已落到画布
}

export class AgentService {
  private xiaoyiTried: boolean = false;
  private xiaoyiOk: boolean = false;

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
   * 执行用户指令：先小艺（生成结构化意图），失败本地解析。
   * 本地解析规则与桌面版无 LLM 兜底行为一致（模板关键词→建板）。
   */
  async run(instruction: string, mbtSummary: string, applyTemplate: (tid: string) => boolean,
    applyText: (text: string) => boolean, applyColor: (color: string) => boolean): Promise<AgentOutcome> {
    // 1) 端侧小艺
    try {
      const reply = await chatOnce(instruction, mbtSummary);
      if (reply !== null && reply.trim().length > 0) {
        const t = reply.trim();
        // 小艺输出若含模板指令关键词，按指令建板
        const tid = this.matchTpl(t);
        if (tid && applyTemplate(tid)) {
          return { ok: true, reply: '小艺：' + this.tplName(tid) + ' 已生成', executed: true };
        }
        if (applyText(t)) {
          return { ok: true, reply: '小艺：已更新文案', executed: true };
        }
        // 无法结构化执行：把小艺的回答作为澄清展示（对齐桌面 agent_no_mbt 语义）
        return { ok: true, reply: '小艺：' + t.slice(0, 120), executed: false };
      }
    } catch (e) { /* 小艺不可用 → 本地兜底 */ }

    // 2) 本地解析（与桌面版兜底一致）
    const tid = this.matchTpl(instruction);
    if (tid && applyTemplate(tid)) {
      return { ok: true, reply: '已通过模板提交（端侧小艺不可用，本地解析兜底）', executed: true };
    }
    const color = this.matchColor(instruction);
    if (color && applyColor(color)) {
      return { ok: true, reply: '已应用颜色 ' + color + '（本地解析）', executed: true };
    }
    if (applyText(instruction)) {
      return { ok: true, reply: '已更新文案（本地解析）', executed: true };
    }
    return { ok: false, reply: '试试更具体的指令：生成手机登录页 / 生成注册页 / 把标题改成蓝色', executed: false };
  }

  private matchTpl(s: string): string {
    const map: Record<string, string> = {
      '登录页 v2': 'login_v2', '注册': 'signup', '登录': 'login', '仪表盘': 'dashboard',
      '个人主页': 'profile', '设置页': 'settings_page', '列表': 'list_detail',
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
    const hit = ['登录页', '注册页', '仪表盘', '个人主页', '设置页', '列表-详情', '引导页', '空状态页',
      'Web 落地页', 'Web 登录', 'Web 仪表盘', 'PC 桌面应用', '自适应落地页', '登录页 v2'];
    void hit;
    return tid;
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

export const agentService: AgentService = new AgentService();
