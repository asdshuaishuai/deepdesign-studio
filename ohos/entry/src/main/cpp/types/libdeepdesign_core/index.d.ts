// deepDesign core NAPI 类型声明（rust-core/deepdesign_core 的 #[napi] 导出）
// 注意：napi-ohos 默认按 camelCase 导出（core_version -> coreVersion）
export const coreVersion: () => string;
export const corePing: (payload: string) => string;
