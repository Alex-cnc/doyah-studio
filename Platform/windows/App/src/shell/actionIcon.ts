// **动作 → 图标**映射（T-20261013-053 硬要求：同族一致性 —— 同一动作全仓只用一个图标）
//
// ## 这份表存在的理由
//
// 加令原文要求「**同一个动作在不同界面用同一个图标**」，并建议「**同一动作的图标全仓唯一（可机械断言）**」。
// 光把图标塞进各按钮，没人能断言"取消是否三处都用了叉"——所以把**动作**抽出来做键：
// 界面写 `actionIcon('cancel')`，判据就能机械核对"每个动作只有一个图标名"。
//
// ## 一条纪律
//
// **能说话的动作才进这张表**。表里的键是**动作语义**（cancel / delete / save…），
// 不是按钮位置（leftPanelButton2 那种）。位置变了不该改图标；动作变了才该改。

import type { ActionGlyph } from './actionIcons'

/**
 * 动作 → 图标（**唯一出处**）。
 *
 * 键的取名口径：动词优先（`open` / `close` / `new` / `delete`…），必要时加宾语
 * （`newFile` / `newFolder`）—— 因为"新建"与"新建文件夹"在图标上是两个形，必须分开认。
 */
export const ACTION_ICONS = {
  // 工作区
  openWorkspace: 'openFolder',      // 打开工作区 = 打开文件夹
  closeWorkspace: 'closeFolder',    // 关闭工作区（不是删除 ⇒ 不用垃圾桶）
  newFile: 'newFile',
  newFolder: 'newFolder',
  save: 'save',
  compare: 'diff',
  delete: 'trash',                  // 删除 / 移入回收站
  reopen: 'undo',                   // 重新打开（回到之前状态）
  refresh: 'refresh',
  // 检索与替换
  search: 'search',
  replace: 'replace',
  previewReplace: 'preview',
  applyReplace: 'check',            // 执行替换 = 正向终态动作
  // 通用
  create: 'plus',                   // 新建 / 新增（不带宾语时）
  cancel: 'close',                  // 取消 = 叉（**全仓唯一**）
  close: 'close',                   // 关闭 = 叉（与取消同图标：同一"收起"语义）
  confirm: 'check',                 // 确认 / 提交
  edit: 'pencil',                   // 编辑 / 重命名
  copy: 'copy',
  run: 'play',                      // 执行 / 运行
  stop: 'stop',
  clear: 'eraser',                  // 清空（不动数据 ⇒ 与删除分开）
  exportFile: 'download',
  importFile: 'upload',
  dryRun: 'flask',                  // 试跑（跑完回滚）
  generate: 'wand',                 // 生成 SQL / 语句
  chat: 'chatBubble',               // 与模型对话（"说话"≠"生成"：两个动作不共形）
  admin: 'sliders',                 // 管理面板
  readOnly: 'lock',
  // 排序与翻页
  sortAsc: 'sortAsc',
  sortDesc: 'sortDesc',
  prevPage: 'chevronLeft',
  nextPage: 'chevronRight',
  expand: 'chevronDown',
  collapse: 'chevronUp',
  goTo: 'arrowRight',               // 跳转 / 进入（≠ 下一页）
  format: 'code',                   // 代码格式化
} as const satisfies Record<string, ActionGlyph>

/** 动作名（判据与界面共用）。 */
export type ActionName = keyof typeof ACTION_ICONS

/** 取动作的图标名（**未登记的动作如实落到占位图标**，不抛错、也不悄悄借用别的动作的图标）。 */
export function actionIcon(action: string): ActionGlyph {
  return (ACTION_ICONS as Record<string, ActionGlyph>)[action] ?? 'placeholder'
}

/** 动作名是否已登记（判据用）。 */
export function isActionName(value: string): value is ActionName {
  return Object.prototype.hasOwnProperty.call(ACTION_ICONS, value)
}

/**
 * **反向核对**：同一图标名被几个动作用了。
 *
 * 用来落"同族一致性"判据的正向半：多个动作共用一个图标**未必错**
 * （`cancel` 与 `close` 共用叉是**有意**的），所以判据只报"**同一动作查出多个图标**"，
 * 不报"多个动作共用一个图标"。这个函数供人工复核时看清共用面。
 */
export function glyphUsage(): Record<string, string[]> {
  const out: Record<string, string[]> = {}
  for (const [action, glyph] of Object.entries(ACTION_ICONS)) {
    ;(out[glyph] ??= []).push(action)
  }
  return out
}
