// 周报正文的**分段渲染窗口**（`FR-R-12-02` ②「长文滚动不卡（1 万字级）」的纯函数那一半）。
//
// 为什么单独一个文件、且是纯函数：
// ① 「渲染多少块」是一件事，只该有一条口径 —— 首屏几块、一次续几块、阈值多少、什么算「快到底了」，
//    全在这里；组件只负责把算出来的数字画出来（改边界不必挂一次组件）；
// ② 短周报要**一个像素都不变**：总块数不超过阈值时把**同一份数组引用**交回去（判据用 `toBe` 钉住），
//    既不切片也不复制 —— 绝大多数周报走的就是这条老路，观感与既有页面查找（Ctrl+F）都不受影响；
// ③ 长文的分段必须是**可逆的显示设定**：页脚永远写着「已渲染 X / Y 段」并给「显示全部」，
//    所以「分段」不会变成「有些内容用户看不到」。
//
// 三条硬口径：
// 1. **只切顶层块**（嵌套列表 / 引用跟着父块一起进来）—— 切到子块里会把一个列表劈成两半，比慢更糟；
// 2. **窗口只增不减**（续窗 / 跳转 / 显示全部都是「往上扩」），否则读着读着已经看过的段落会消失；
// 3. 窗口状态**不落盘**：它是显示态，不是包内容（包一个字节都不动）。

import type { MdBlock, MdDocument, MdSpan } from '../../ipc'

/** 超过这个块数才分段（1 万字级周报约两百多块；十几段的短周报永远走全量）。 */
export const DOC_WINDOW_LIMIT = 120

/** 首屏渲染块数（分段时）。 */
export const DOC_WINDOW_FIRST = 60

/** 每次续渲染的块数。 */
export const DOC_WINDOW_STEP = 60

/** 距底多少像素算「快到底了」（续窗触发）；给滚动留出预渲染的余量。 */
export const DOC_NEAR_BOTTOM_PX = 400

/** 这一份文档要不要分段。 */
export function needsWindow(total: number): boolean {
  return Number.isFinite(total) && total > DOC_WINDOW_LIMIT
}

/** 首屏该渲染几块：短文档 = 全量；长文档 = 前 `DOC_WINDOW_FIRST` 块。 */
export function firstWindow(total: number): number {
  if (!Number.isFinite(total) || total <= 0) return 0
  if (!needsWindow(total)) return Math.trunc(total)
  return Math.min(Math.trunc(total), DOC_WINDOW_FIRST)
}

/**
 * 取这一屏要画的块。
 *
 * **短文档交回同一个数组引用**（`document.value.blocks`）—— 判据用 `toBe` 钉住「没切片」；
 * 长文档才切片，且 `shown` 越界一律夹到 `[0, total]`（坏值不许把正文画成空白）。
 */
export function blocksFor(document: MdDocument | null | undefined, shown: number): MdBlock[] {
  if (!document || !Array.isArray(document.blocks)) return []
  const blocks = document.blocks
  if (!needsWindow(blocks.length)) return blocks
  const limit = clampShown(shown, blocks.length)
  return blocks.slice(0, limit)
}

/** 把 `shown` 夹进 `[0, total]`（非数字 / 负数 / 超界都归一）。 */
export function clampShown(shown: number, total: number): number {
  if (!Number.isFinite(total) || total <= 0) return 0
  if (!Number.isFinite(shown) || shown <= 0) return 0
  return Math.min(Math.trunc(shown), Math.trunc(total))
}

/** 窗口读数（页脚那一行就画它）。 */
export interface DocWindow {
  /** 已经渲染的块数。 */
  shown: number
  /** 总块数。 */
  total: number
  /** 还没渲染的块数。 */
  remaining: number
  /** 是否处于分段态（短文档 = `false`，页脚不画）。 */
  limited: boolean
}

/** 当前窗口读数。 */
export function windowOf(document: MdDocument | null | undefined, shown: number): DocWindow {
  const total = document && Array.isArray(document.blocks) ? document.blocks.length : 0
  const effective = needsWindow(total) ? clampShown(shown, total) : total
  return {
    shown: effective,
    total,
    remaining: Math.max(0, total - effective),
    limited: needsWindow(total),
  }
}

/** 续一窗（**只增不减**；已到底就原样返回）。 */
export function nextWindow(shown: number, total: number): number {
  const current = clampShown(shown, total)
  if (!needsWindow(total)) return clampShown(total, total)
  if (current >= total) return current
  return Math.min(total, current + DOC_WINDOW_STEP)
}

/** 滚动容器的三件读数（只取算得着的，便于纯函数里断言）。 */
export interface ScrollMetrics {
  scrollTop: number
  clientHeight: number
  scrollHeight: number
}

/**
 * 是不是快到容器底部了。
 *
 * 读不到尺寸（`0` / 非数字）一律判**否** —— 宁可不续，也别在未知尺寸上乱续一屏；
 * `scrollHeight` 不超过可视高度时（内容本来就没撑出滚动条）也判否。
 */
export function nearBottom(metrics: ScrollMetrics, margin = DOC_NEAR_BOTTOM_PX): boolean {
  const { scrollTop, clientHeight, scrollHeight } = metrics
  for (const value of [scrollTop, clientHeight, scrollHeight]) {
    if (!Number.isFinite(value) || value < 0) return false
  }
  if (scrollHeight <= clientHeight) return false
  const remaining = scrollHeight - clientHeight - scrollTop
  return remaining <= margin
}

/**
 * 行号 → 顶层块下标（找不到就返回最接近的那一块）。
 *
 * 口径：取**最后一个 `block.line <= line`** 的块 —— 大纲里的行号就是标题块自己的行号，
 * 精确命中时正是那一块；若某个包的行号落在两块之间（解析器改过行号口径），退到「包含这一行的那一块」。
 * 空文档 ⇒ `-1`；行号在第一块之前 ⇒ `0`（往前退到开头，而不是不画）。
 */
export function indexForLine(document: MdDocument | null | undefined, line: number): number {
  const blocks = document?.blocks ?? []
  if (blocks.length === 0) return -1
  if (!Number.isFinite(line)) return blocks.length - 1
  let found = -1
  for (let index = 0; index < blocks.length; index += 1) {
    const blockLine = blocks[index]?.line
    if (!Number.isFinite(blockLine)) continue
    if (blockLine <= line) found = index
    else break
  }
  return found < 0 ? 0 : found
}

/**
 * 跳到大纲某一条之前，窗口至少要铺到哪一块（`index + 1`）。
 *
 * **只扩不缩**：目标在已渲染范围内就原样返回当前窗口（不会因为跳转把后面的段落收回去）。
 */
export function windowForLine(document: MdDocument | null | undefined, line: number, shown: number): number {
  const total = document?.blocks?.length ?? 0
  const index = indexForLine(document, line)
  if (index < 0) return clampShown(shown, total)
  return Math.max(clampShown(shown, total), index + 1)
}

/** 正文读数：块数 + 字数（页头那一行）。 */
export interface DocStats {
  blocks: number
  /** 正文字数（**不含空白**；代码块与表格里的文字算，媒体说明不算）。 */
  chars: number
}

/** 数一份文档的块数与字数（含代码块 / 表格 / 嵌套；不额外读盘）。 */
export function docStats(document: MdDocument | null | undefined): DocStats {
  const blocks = document?.blocks ?? []
  let chars = 0
  for (const block of blocks) chars += blockChars(block)
  return { blocks: blocks.length, chars }
}

function spanChars(spans: MdSpan[] | undefined): number {
  let count = 0
  for (const span of spans ?? []) count += textChars(span?.text)
  return count
}

function textChars(text: string | null | undefined): number {
  if (!text) return 0
  // 空白不算「字」：换行 / 缩进 / 段间空行不是用户读到的内容
  return text.replace(/\s+/gu, '').length
}

function blockChars(block: MdBlock | null | undefined): number {
  const kind = block?.kind
  if (!kind) return 0
  switch (kind.type) {
    case 'heading':
    case 'paragraph':
      return spanChars(kind.spans)
    case 'codeFence':
      return textChars(kind.text)
    case 'table': {
      let count = 0
      for (const cell of kind.header ?? []) count += spanChars(cell)
      for (const row of kind.rows ?? []) for (const cell of row) count += spanChars(cell)
      return count
    }
    case 'listItem':
      return spanChars(kind.spans) + (kind.children ?? []).reduce((sum, child) => sum + blockChars(child), 0)
    case 'quote':
      return (kind.children ?? []).reduce((sum, child) => sum + blockChars(child), 0)
    default:
      // 媒体 / 分隔线没有正文（媒体说明是说明，不是正文）
      return 0
  }
}
