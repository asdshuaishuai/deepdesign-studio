// deepDesign core 桥 —— ArkTS ↔ Rust NAPI
//
// libdeepdesign_core.so 由 rust-core（napi-ohos）产出，随 HAP 的 libs/ 分发，
// OHOS 运行时按 ABI 自动加载。import 路径即库名（OHOS NAPI 约定）。
// 注意：napi-ohos 的 #[napi] 导出默认转 camelCase（core_version -> coreVersion），
// 新增导出时 d.ts（cpp/types/libdeepdesign_core/index.d.ts）须同步。
// DDP 编解码与桌面版共用 vendor/moonviz-ddp——同一 .ddp 两端互通。

import core from 'libdeepdesign_core.so';

export interface CoreInfo {
  version: string;
}

export function coreVersion(): string {
  return core.coreVersion();
}

export function corePing(payload: string): string {
  return core.corePing(payload);
}

/** MBT 源（标准 base64）→ DDP 容器（base64）。空密码 = DDP2 无密码模式。 */
export function ddpEncrypt(mbtB64: string, password: string): string {
  return core.ddpEncrypt(mbtB64, password);
}

/** DDP 容器（base64）→ MBT 源。口令不符/损坏抛错（消息即 codec 错误码）。 */
export function ddpDecrypt(ddpB64: string, password: string): string {
  return core.ddpDecrypt(ddpB64, password);
}
