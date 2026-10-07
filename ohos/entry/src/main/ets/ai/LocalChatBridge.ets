// 系统级端侧 AI 桥（localChatModel / Data Augmentation Kit）
//
// 独立模块 + Dispatch 侧动态 import：设备无该系统模块时加载失败被 catch，
// 调用方优雅降级到云端链路——静态 import 会让整个页面模块加载失败。
// 端侧模型上下文上限 4500 字节（官方建议），超出须截断。

import { localChatModel } from '@kit.DataAugmentationKit';

const PROMPT_MAX_BYTES = 4400;   // 预留 id/包装开销
const MBT_MAX_BYTES = 3000;      // 文档上下文配额

let qid = 0;

const INIT_TIMEOUT_MS = 10000;
const CHAT_TIMEOUT_MS = 30000;

function withTimeout<T>(p: Promise<T>, ms: number): Promise<T | null> {
  return new Promise<T | null>((resolve) => {
    let done = false;
    const timer = setTimeout((): void => {
      if (!done) { done = true; resolve(null); }
    }, ms);
    p.then((v: T): void => {
      if (!done) { done = true; clearTimeout(timer); resolve(v); }
    }).catch((): void => {
      if (!done) { done = true; clearTimeout(timer); resolve(null); }
    });
  });
}

function utf8Len(s: string): number {
  let n = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    n += c < 0x80 ? 1 : (c < 0x800 ? 2 : 3);
  }
  return n;
}

function truncateUtf8(s: string, maxBytes: number): string {
  let n = 0;
  let end = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    n += c < 0x80 ? 1 : (c < 0x800 ? 2 : 3);
    if (n > maxBytes) break;
    end = i + 1;
  }
  return s.slice(0, end);
}

function buildPrompt(instruction: string, mbt: string): string {
  const doc = truncateUtf8(mbt, MBT_MAX_BYTES);
  const head =
    '你是 MoonViz UI 设计画布的端侧设计助手。根据用户指令，对当前设计文档输出变更命令流。\n' +
    '命令语法（每行一条，动词开头）：\n' +
    'template <模板名> <画板id> <宽> <高>   例如: template login p1 390 844\n' +
    'create <画板id> <宽> <高>\n' +
    'text <画板id> <元素id> "文案"   设置/新增文字元素\n' +
    'set <画板id> <元素id> <属性> <值>   属性如 fill color x y fontSize\n' +
    'move <画板id> <元素id> <dx> <dy>   相对位移\n' +
    'delete <画板id> <元素id>\n' +
    'delete-artboard <画板id>\n' +
    'flow <源画板id> <源元素id> <目标画板id>\n' +
    'list / lint <画板id>   检视类\n' +
    '规则：只输出命令行，不要解释、不要 markdown；需要澄清时用一句话提问。\n';
  const tail = `\n当前文档（.mbt.md）：\n${doc}\n\n用户指令：${instruction}\n命令流：`;
  let q = head + tail;
  if (utf8Len(q) > PROMPT_MAX_BYTES) {
    q = truncateUtf8(head, 1200) + truncateUtf8(tail, PROMPT_MAX_BYTES - 1200);
  }
  return q;
}

/**
 * 端侧问答单轮：返回模型文本；null = 端侧模型不可用（未初始化/调用失败）。
 */
export async function chatOnce(instruction: string, mbt: string): Promise<string | null> {
  const ready = await withTimeout<boolean>(localChatModel.init(), INIT_TIMEOUT_MS);
  if (ready !== true) return null;
  const question = buildPrompt(instruction, mbt);
  return new Promise<string | null>((resolve) => {
    const info: localChatModel.QuestionInfo = { questionId: ++qid, content: question };
    const cfg: localChatModel.Config = { isStream: false };
    let settled = false;
    localChatModel.chat(info, cfg, (err: Error | null, ans: localChatModel.Answer | undefined): void => {
      if (settled) return;
      if (err || !ans || !ans.content) { settled = true; clearTimeout(timer); resolve(null); return; }
      if (ans.isFinished) { settled = true; clearTimeout(timer); resolve(ans.content); return; }
      // 增量返回：累积内容
      acc += ans.content;
    });
    let acc = '';
    const timer = setTimeout((): void => {
      if (!settled) { settled = true; resolve(acc || null); }
    }, CHAT_TIMEOUT_MS);
  });
}

/** 端侧模型就绪探测（设置页/顶栏状态显示用）。 */
export async function probeReady(): Promise<boolean> {
  const r = await withTimeout<boolean>(localChatModel.init(), INIT_TIMEOUT_MS);
  return r === true;
}
