// 端侧 AI 就绪探测（动态 import 隔离：系统无 DataAugmentationKit 时不影响页面加载）
import { probeReady } from './LocalChatBridge';

export async function probeLocalAi(): Promise<boolean> {
  try {
    return await probeReady();
  } catch (e) {
    return false;
  }
}
