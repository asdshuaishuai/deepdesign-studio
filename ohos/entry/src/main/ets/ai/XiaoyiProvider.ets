// 端侧 AI Provider —— 鸿蒙原生接入（小艺/AgentFramework/mindSporeLite）
//
// deepDesign Agent 循环的"第 14 个服务商"：设备端模型。相比云端的差异化价值：
//   - 离线可用（无网环境/敏感项目）
//   - 低延迟首 token
//   - 与小艺生态（IntentsKit 意图、系统级智能体）互操作
// 路线：
//   首选 @hms.ai.AgentFramework（智能体编排，系统级调度端侧模型）
//   备选 @ohos.ai.mindSporeLite（加载自托管 .ms 模型，完全离线）
// 本文件为 M1 骨架：接口形状与 Agent 循环流式协议对齐；真机实现分 P2 推进。

export interface ChatMessage {
  role: string;
  content: string;
}

export interface ChatChunk {
  delta: string;
  done: boolean;
}

export type AIBackend = 'agent-framework' | 'mindspore-lite' | 'unavailable';

export interface ProbeResult {
  available: boolean;
  backend: AIBackend;
  detail?: string;
}

type StreamCallback = (chunk: ChatChunk) => void;

class XiaoyiProvider {
  private backend: AIBackend = 'unavailable';
  private probed = false;

  async probe(): Promise<ProbeResult> {
    if (this.probed) {
      return { available: this.backend !== 'unavailable', backend: this.backend };
    }
    this.probed = true;
    // TODO(P2 真机)：AgentFramework.canIUse / mindSporeLite.init 运行时探测。
    // 模拟器（x86_64 镜像）无 HMS 端侧模型；真机（Kirin 9010+）按系统版本开放。
    this.backend = 'unavailable';
    return { available: false, backend: this.backend,
      detail: 'skeleton: probe on real device pending' };
  }

  async chatStream(messages: ChatMessage[], cb: StreamCallback): Promise<void> {
    const probe = await this.probe();
    if (!probe.available) {
      cb({ delta: '', done: true });
      return;
    }
    // TODO(P2 真机)：分派 AgentFramework（系统调度端侧大模型）或
    // mindSporeLite（本地 .ms 模型推理），流式回调 cb({delta, done:false})。
    cb({ delta: '', done: true });
  }
}

export const xiaoyiAI = new XiaoyiProvider();
