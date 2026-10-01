// deepDesign 本地数据模型 —— 与桌面版状态语义对齐
// （后续 Rust core NAPI 接入后，持久化与引擎校验下沉到 core；
//  当前 ArkUI 层持有内存态，接口形状与桌面 invoke 对齐）

export interface Board {
  id: string;
  name: string;
  kind: string;         // mobile | web | adaptive
  width: number;
  height: number;
}

export interface LayerNode {
  id: string;
  name: string;
  type: string;         // frame | text | rect | image
}

export class AppStore {
  private seq: number = 0;
  boards: Board[] = [];
  projectName: string = '未命名项目';
  dirty: boolean = false;

  addBoard(name: string, kind: string, width: number, height: number): Board {
    this.seq++;
    const b: Board = {
      id: `board-${this.seq}`,
      name: name,
      kind: kind,
      width: width,
      height: height
    };
    this.boards.push(b);
    return b;
  }

  removeBoard(id: string): void {
    this.boards = this.boards.filter((b) => b.id !== id);
  }

  boardCount(): number {
    return this.boards.length;
  }
}

export const appStore = new AppStore();
