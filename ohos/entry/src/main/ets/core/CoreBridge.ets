// deepDesign core 桥 —— ArkTS ↔ Rust NAPI
//
// libdeepdesign_core.so 由 rust-core（napi-ohos）产出，随 HAP 的 libs/ 分发，
// OHOS 运行时按 ABI 自动加载。import 路径即库名（OHOS NAPI 约定）。
// 注意：napi-ohos 的 #[napi] 导出默认转 camelCase（core_version -> coreVersion），
// 新增导出时 d.ts（cpp/types/libdeepdesign_core/index.d.ts）须同步。
// 后端核心能力（引擎宿主/Agent 循环/DDP）将在此逐模块暴露。

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
