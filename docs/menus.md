# deepDesign Studio 中文菜单文案清单

所有菜单动作最终经 WebView 内的 wasm 引擎落到唯一事实源 `.mbt.md`；菜单本身只是壳的具现化入口（无 CLI、无子进程）。

## 1. 原生菜单栏（macOS 全局菜单）

由 Tauri 2 原生菜单构建（`src-tauri/src/lib.rs::build_native_menus`）。菜单项点击后 `lib.rs::on_menu_event` 经 `win.eval("nativeMenuAction(id)")` **直调**前端全局函数（`event.listen` 曾因 Tauri ACL 未放行而弃用），由它映射到既有函数执行。

### deepDesign Studio（应用菜单）
| 菜单项 | 说明 |
|--------|------|
| 关于 deepDesign Studio | 系统关于面板（版本 0.3.0） |
| 服务 | macOS 系统服务 |
| 隐藏 / 隐藏其它 / 显示全部 | 系统窗口管理 |
| 退出 deepDesign | `quit-app`（⌘Q）→ `quitApp()`：有未保存更改先弹原生确认，放弃后 `app_exit` 退出（预置 quit 走 terminate: 不触发关窗拦截，故自定义） |

### 文件
| 菜单项 | 快捷键 | 动作 id → 前端函数 |
|--------|--------|--------------------|
| 新建项目… | ⌘N | `new-project` → `newProject()`（有未保存更改时先弹原生确认） |
| 打开 DDP… | ⌘O | `open-ddp` → `openProject()`（先输密码（免密留空）再选文件 → 解密 → MBT 重载） |
| 打开最近的项目… | — | `open-recent` → `openRecentMenu()`（前端文件菜单展开并渲染最近项目区；注册表存 localStorage `dd-recent-projects`，经 `list_ddp_projects` 磁盘对账；点击行免对话框切换 `openProject(path)`——先试会话口令/空口令，失败再问） |
| 保存 | ⌘S | `save` → `saveProject()`（已有路径原地回写并复用会话口令；否则回落导出对话框） |
| 导出 DDP… | ⇧⌘E | `export-ddp` → `exportDdp()`（加密/免密选择，总弹保存对话框） |
| 导出 HTML 原型… | ⇧⌘H | `export-html` → `exportHtmlProto()`（引擎 `export_html`：自包含可交互 HTML） |
| 导出 SVG（当前画板）… | — | `export-svg` → `exportSvg()`（当前活动画板的 SVG） |

### 编辑（撤销/重做为自定义项，作用于当前画板；剪切/复制/粘贴为系统预置项）
撤销 ⌘Z（`edit-undo` → `undoMbt()`，当前画板历史会话；焦点在输入框时回退文本撤销）/ 重做 ⇧⌘Z（`edit-redo` → `redoMbt()`）/ 剪切 ⌘X / 复制 ⌘C / 粘贴 ⌘V / 全选 ⌘A

### 视图
| 菜单项 | 快捷键 | 动作 id → 前端函数 |
|--------|--------|--------------------|
| 线框图 | ⌘1 | `view-wireframe` → `setMode('wireframe')` |
| 高保真 | ⌘2 | `view-hifi` → `setMode('hifi')` |
| MBT 源码 | ⌘3 | `view-decl` → `setMode('decl')` |
| 演示模式 | ⌘4 | `view-play` → `setMode('play')` |
| 适配窗口 | ⌘0 | `view-fit` → `zoomReset()` |

### 画板
| 菜单项 | 快捷键 | 动作 id → 前端函数 |
|--------|--------|--------------------|
| 新建画板 | ⇧⌘N | `board-new` → `createBlank()` |
| 复制当前画板 | ⇧⌘D | `board-dup` → `duplicateActiveBoard()`（引擎 `duplicate` 操作） |
| 自动修复（引擎还债） | ⇧⌘F | `autofix` → `runAutoFix()`（违规严格减少即提交） |
| 校验并渲染 | — | `validate` → `setMode('decl') + validateMbt()` |

### 帮助
| 菜单项 | 动作 id |
|--------|---------|
| 快捷键与菜单说明 | `shortcuts` → `openShortcuts()` 弹窗 |

## 2. 右键菜单（前端动态构建 `showMenu()`）

### 2.1 画布元素（右键节点 → 自动选中 + 节点菜单）
| 菜单项 | 说明 |
|--------|------|
| ✏️ 编辑文字（双击） | 打开内联文本编辑（`update … text=` 回写 MBT） |
| ⧉ 复制元素 | 引擎 `copy` 操作（+24px 偏移副本） |
| ⬆ 置顶 / ⬇ 置底 | 引擎 `reorder` 操作 |
| ↔ 水平居中 / ↕ 垂直居中 | 引擎 `move` 操作（画板中心对齐） |
| ⇋ 水平翻转 / ⇵ 垂直翻转 | 引擎 `flip` 操作 |
| 🔗 从这里链接交互… | 进入连接模式（点目标画板 → `flow` 写入 MBT） |
| 🗑 删除元素（⌫） | 引擎 `delete` 操作 |

### 2.2 画布空白区
| 菜单项 | 说明 |
|--------|------|
| ✚ 新建画板（⇧⌘N） | `createBlank()` |
| ⧉ 复制当前画板（⇧⌘D） | 引擎 `duplicate` |
| ◻ 切换到线框图 / 🎨 切换到高保真 | 按当前模式互切 |
| ‹/› 查看 MBT 源码（⌘3） | 切到源码视图 |
| ✓ 校验并渲染 | `validateMbt()` |
| ▶ 演示模式（⌘4） | 进入播放 |
| ⛶ 适配窗口（⌘0） | `zoomReset()` |

### 2.3 画板卡片（右键画板标题栏）
| 菜单项 | 说明 |
|--------|------|
| → 切换到此画板 | `switchSession(id)` |
| ⧉ 复制此画板 | 引擎 `duplicate` |
| ▶ 从此画板演示 | 切换后进入演示模式 |
| 🗑 删除此画板 | 引擎 `delete-artboard`（至少保留一个画板；引用它的交互流自动清理） |

### 2.4 MBT 源码编辑器
| 菜单项 | 说明 |
|--------|------|
| ⌿ 全选（⌘A） | 选中文本域全部源码 |
| ⧉ 复制源码 | 复制完整 `.mbt.md` 到剪贴板 |
| ✓ 校验并渲染 | `validateMbt()` |
| 🗑 清空编辑器 | 清空草稿（危险项，红色） |

### 2.5 交互逻辑标注（编辑视图常显）

- **流连线**：画板间蓝色虚线箭头，标签为白底药丸「点击「按钮文字」 → 目标画板」（无文字时回退 `tap:id`），带引线与小圆端点。
- **触发按钮**：带交互流的按钮在编辑视图常显绿色虚线描边（`data-flow-trigger`），一眼可见「哪个按钮触发哪条跳转」。
- 连线坐标使用布局 offset（不依赖 `getBoundingClientRect`），规避 WKWebView 渲染错位。

## 3. 演示模式（工作区内）

演示不再是独立全屏页：进入后**同一工作区禁用编辑、只保留演示**。
控制区为**底部操作栏**（2026-09 起，替代原顶部胶囊）：`◀ 返回`（playStack 回退，起始页时禁用）·
画板路径面包屑 · `绿框 = 可点击交互 · Esc 返回上一页` 提示 · `退出演示 ✕`（随当前主题配色）。

| 项目 | 行为 |
|------|------|
| 进入 | 工具栏「演示」按钮 / ⌘4 / 画板右键「从此画板演示」 |
| 隐藏 | 左侧栏 · 右侧检查器 · 画布工具条 · 缩放控件 · 底部 Prompt 条 · 流连线 · 非当前画板 |
| 保留 | 当前画板居中放大 · 底部演示操作栏（◀ 返回 / 面包屑 / 退出）· 状态栏 |
| 交互 | 绿色虚线热区 = 可点击（HTML div 命中可靠）。点击按引擎 tap 解析顺序回退：先 flow 边跳转，未命中再查 interact 标记（`navigate_to:` 跳转 / `back` 返回 / `show_toast:` 弹示 / `set_text:`·`set_state:` 真执行）；非 tap 触发器不响应（进入演示时计数提示） |
| 返回 | 底部「◀ 返回」或 Esc = playStack 回退上一页；起始页再按/Esc 退出演示 |
| 撤销/重做 | 演示中禁用（⌘Z/⇧⌘Z 不响应） |
| Esc | 返回上一页；回到起点后再按退出，恢复编辑模式 |
| 禁用 | 选择/拖拽/双击改字/右键菜单/方向键移动/删除（编辑能力全部冻结） |

## 4. 画布键盘操作（帮助弹窗同步收录）

| 按键 | 行为 |
|------|------|
| ⌘K | 聚焦 Agent 指令输入 |
| ⌘S | 保存（已有路径原地回写；否则另存） |
| ⌘Z / ⇧⌘Z | 撤销 / 重做（当前画板；输入框内为文本撤销） |
| ⇧⌘E | 导出 DDP（加密/免密选择） |
| ⇧⌘H | 导出 HTML 原型（自包含可交互） |
| 方向键 / ⇧+方向键 | 移动选中元素 1px / 10px |
| V / T | 选择工具 / 文本工具（单击等价） |
| ⌫ | 删除选中元素 |
| 双击 | 编辑元素文字 |
| Esc（演示模式） | 返回上一层 / 退出演示 |
| Esc（快捷键弹窗） | 关闭弹窗 |

## 5. 实现边界

- 菜单不持有任何状态：每个动作都调用既有前端函数，最终走 `runOp` → `engApply`（WebView 内 wasm `apply_human_op` 直调）→ canonical `.mbt.md` 回写 → 重新渲染。
- 引擎 `duplicate` 操作已加入 MBT 操作表（`cli/main.mbt::apply_mbt_operation`），与直接命令 `duplicate <src> <new_name>` 同源。
- 右键菜单容器 `#ctxmenu` 动态构建；点击任意处 / 窗口失焦自动关闭。
