// deepDesign core NAPI 类型声明（rust-core/deepdesign_core 的 #[napi] 导出）
// 注意：napi-ohos 默认按 camelCase 导出（core_version -> coreVersion）
export const coreVersion: () => string;
export const corePing: (payload: string) => string;
// DDP 认证加密容器（与桌面版 .ddp 互通；空密码 = DDP2 无密码模式）
export const ddpEncrypt: (mbt: string, password: string) => string;
export const ddpDecrypt: (ddpB64: string, password: string) => string;
