/**
 * Data Augmentation Kit（localChatModel 端侧问答模型）类型声明。
 * 该 kit 属 HarmonyOS NEXT（API 20+），OpenHarmony SDK 不自带——
 * 真机/仿真镜像有系统实现时运行时可加载；无则动态 import 失败，调用方降级。
 * API 签名依据 developer.huawei.com dataaugmentation-localchatmodel-api。
 */
declare module '@kit.DataAugmentationKit' {
  export namespace localChatModel {
    interface Config {
      isStream: boolean;
    }
    interface QuestionInfo {
      questionId: number;
      content: string;
    }
    interface Answer {
      questionId: number;
      content: string;
      isFinished: boolean;
    }
    function init(): Promise<boolean>;
    function chat(info: QuestionInfo, config: Config,
      callback: (err: Error | null, data: Answer) => void): Promise<void>;
  }
}
