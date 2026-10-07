// 端侧 AI Provider 骨架（HarmonyOS Intelligence 接入点）
//
// 设计（deepDesign Agent 循环的"第 14 个服务商"——离线端侧模型）：
//   设备侧 AgentFramework / mindSporeLite 提供 LLM 推理；本 provider 把它包装为
//   与云端服务商同构的 chat 接口，供 Agent 循环路由（按服务商预设选择端侧/云端）。
//   可用性探测：无端侧模型授权/低配设备时 probe 返回 unavailable，Agent 循环
//   自动回退云端服务商——deepDesign 多服务商架构天然支持此回退。
//
// SDK 盘点（26.0.0.851）：
//   @hms.ai.AgentFramework —— 智能体编排（AgentController/FunctionController）
//   @hms.ai.insightIntent  —— 意图框架
//   @ohos.ai.mindSporeLite —— 端侧推理（可加载自托管模型）
//   注意：端侧基础大模型（FoundationModels）的开放接口随设备/系统版本差异较大，
//   probe 采用运行时特性探测而非硬编码 import（import 失败的备选实现放
//   mindSporeLite 路线）。

export interface ChatMessage {
  role: string;       // 'system' | 'user' | 'assistant'
  content: string;
}

export interface ChatChunk {
  delta: string;
  done: boolean;
}

type StreamCallback = (chunk: ChatChunk) => void;

type AIBackend = 'agent-framework' | 'mindspore-lite' | 'unavailable';

export interface ProbeResult {
  available: boolean;
  backend: AIBackend;
  detail?: string;
}

class OnDeviceAIProvider {
  private backend: AIBackend = 'unavailable';
  private probed = false;

  /**
   * 运行时探测端侧 AI 能力。设备不支持/未授权时返回 unavailable。
   * 真机验证点：AgentFramework 的可用性随HarmonyOS 版本与设备芯片差异较大。
   */
  async probe(): Promise<ProbeResult> {
    if (this.probed) {
      return { available: this.backend !== 'unavailable', backend: this.backend };
    }
    this.probed = true;
    // TODO(P2 真机)：AgentFramework.canIUse / mindSporeLite 探测实现。
    // 骨架阶段保守返回 unavailable——Agent 循环回退云端服务商，不阻塞桌面/真机主流程。
    this.backend = 'unavailable';
    return { available: false, backend: this.backend,
      detail: 'skeleton: device probe pending (needs real device)' };
  }

  /**
   * 端侧流式 chat。available=false 时回调一个 done chunk 即返回。
   * 接口形状与 Agent 循环的流式协议对齐（delta 累积语义）。
   */
  async chatStream(messages: ChatMessage[], cb: StreamCallback): Promise<void> {
    const probe = await this.probe();
    if (!probe.available) {
      cb({ delta: '', done: true });
      return;
    }
    // TODO(P2 真机)：按 probe.backend 分派 AgentFramework/mindSporeLite 实现。
    cb({ delta: '', done: true });
  }
}

export const onDeviceAI = new OnDeviceAIProvider();
