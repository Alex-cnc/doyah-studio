// 结果网格的**显示态**计算（排序 / 筛选 / 复制文本）—— 纯函数，便于单测
//
// 两条口径（都要写出来，否则下一轮就会漂）：
//   ① **按值比、不按显示串比**：后端给了 `numRows`（每格的数值形态），能取到数就按数比 ——
//      否则 `"9" > "10"` 这种字典序错排就会出现（客户端表格的经典缺陷）。取不到数再退回字符串比。
//   ② **NULL 的位置有规矩**：排序时 NULL **一律排在最后**（升序、降序都一样）——
//      让"没有值"不参与大小之争，也不随方向在两端跳。
//   ③ **筛选是纯包含**（不分大小写、按显示文本），命中为空就是空 —— **不假装还有数据**。

import type { QueryResult } from '../ipc'

/** 排序态：列下标 + 方向。`null` = 原序（后端给的顺序）。 */
export interface SortState {
  column: number
  desc: boolean
}

/** 一行的显示文本（NULL 显示为空串）。 */
export function rowText(row: (string | null)[]): string[] {
  return row.map((cell) => (cell === null ? '' : cell))
}

/** 取某列的数值（取不到 ⇒ `null`）。 */
function numAt(result: QueryResult, rowIndex: number, column: number): number | null {
  const row = result.numRows?.[rowIndex]
  const value = row?.[column]
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

/** 某列是否**整列都是数值**（决定排序用值还是用串）。 */
export function columnIsNumeric(result: QueryResult, column: number): boolean {
  if (!result.numRows || result.numRows.length === 0) return false
  let numeric = 0
  let nonNull = 0
  for (let i = 0; i < result.numRows.length; i += 1) {
    const cell = result.rows[i]?.[column]
    if (cell === null || cell === undefined) continue
    nonNull += 1
    if (numAt(result, i, column) !== null) numeric += 1
  }
  return nonNull > 0 && numeric === nonNull
}

/**
 * 排序后的**行下标序列**（不复制行数据）：`order` 是 `result.rows` 的下标排列。
 * 不给排序态 ⇒ 原序。
 */
export function sortedOrder(result: QueryResult, sort: SortState | null): number[] {
  const count = result.rows.length
  const order = Array.from({ length: count }, (_, i) => i)
  if (!sort) return order
  const { column, desc } = sort
  const useNumbers = columnIsNumeric(result, column)

  order.sort((a, b) => {
    // NULL 一律最后（不看方向）
    const aNull = result.rows[a]?.[column] === null || result.rows[a]?.[column] === undefined
    const bNull = result.rows[b]?.[column] === null || result.rows[b]?.[column] === undefined
    if (aNull && bNull) return a - b
    if (aNull) return 1
    if (bNull) return -1

    let cmp: number
    if (useNumbers) {
      cmp = (numAt(result, a, column) ?? 0) - (numAt(result, b, column) ?? 0)
    } else {
      const left = (result.rows[a]?.[column] ?? '').toString()
      const right = (result.rows[b]?.[column] ?? '').toString()
      cmp = left.localeCompare(right, 'zh-Hans-CN')
    }
    // 稳定排序：值相同就按原本次序（不抖动）
    if (cmp === 0) return a - b
    return desc ? -cmp : cmp
  })
  return order
}

/** 筛选：**纯包含**（不分大小写、按显示文本），空词 = 不过滤。 */
export function filteredOrder(result: QueryResult, filter: string): number[] {
  const needle = filter.trim().toLowerCase()
  const all = Array.from({ length: result.rows.length }, (_, i) => i)
  if (!needle) return all
  return all.filter((i) => rowText(result.rows[i] ?? []).some((cell) => cell.toLowerCase().includes(needle)))
}

/** 把「筛选 → 排序」串起来：返回**显示用**的行下标序列。 */
export function visibleOrder(result: QueryResult, filter: string, sort: SortState | null): number[] {
  const hits = filteredOrder(result, filter)
  if (!sort) return hits
  const sorted = sortedOrder(result, sort)
  const rank = new Map<number, number>()
  sorted.forEach((rowIndex, position) => rank.set(rowIndex, position))
  return hits.slice().sort((a, b) => (rank.get(a) ?? 0) - (rank.get(b) ?? 0))
}

/**
 * 复制成 **TSV**（贴 Excel 直接分列）。
 *
 * 口径：**NULL 用空串**（不写 `NULL` 字样 —— 那是显示层的事，粘进表格里应当是空单元格）；
 * 单元格里的制表符 / 换行替换成空格（否则贴过去会串列）。
 */
export function toTsv(result: QueryResult, order: number[]): string {
  const escape = (text: string) => text.replace(/[\t\r\n]+/g, ' ')
  const head = result.columns.map(escape).join('\t')
  const body = order.map((i) => rowText(result.rows[i] ?? []).map(escape).join('\t'))
  return [head, ...body].join('\n')
}

// ── 冻结列（FR-RES-05）──────────────────────────────────────────────────────────────
//
// 口径（为什么这么算，写清楚免得下一轮"优化"掉）：
//   ① 冻结的是**最左边的连续若干列**（冻结第 3 列而第 2 列不冻，中间会露出滚动内容）；
//   ② 每列的 `left` = 它左边那些**也被冻结**的列的宽度之和（不冻的列不占位）；
//   ③ 宽度用估算值（按该列**表头**的字符数），**不测 DOM** —— 纯函数才能单测，
//      而且估算错一点只是"表头被盖住一点"，不会算错语义。

/** 冻结列宽度估算：中文字符按 2 个宽度单位算。 */
export const COLUMN_WIDTH_UNIT_PX = 9
/** 每列的基础内边距（与 CSS 的 padding 对齐，估宽时一并加上）。 */
export const COLUMN_PADDING_PX = 16
/** 单列宽度上限（避免一格超长表头把后面全挤飞）。 */
export const COLUMN_MAX_WIDTH_PX = 240

/** 估算一列的宽度（按列名算；不读 DOM）。 */
export function estimateColumnWidth(columnName: string): number {
  let units = 0
  for (const ch of columnName) {
    units += /[\u3000-\u9fff\uff00-\uffef]/.test(ch) ? 2 : 1
  }
  const estimated = units * COLUMN_WIDTH_UNIT_PX + COLUMN_PADDING_PX
  return Math.min(COLUMN_MAX_WIDTH_PX, Math.max(COLUMN_WIDTH_UNIT_PX * 4, estimated))
}

/**
 * 冻结列的样式表：列下标 → `{ left, zIndex }`。
 *
 * - 只对**前 `frozenCount` 列**给值（其余列不冻、不占位）；
 * - `frozenCount` 夹到 `[0, columns.length]`（调用方给超了也不许越界）；
 * - `zIndex` 比普通表头高一层，否则滚动时会被后面的单元格盖住。
 */
export function frozenColumnStyles(
  columns: readonly string[],
  frozenCount: number,
): Record<number, { left: string; zIndex: number }> {
  const count = Math.max(0, Math.min(frozenCount, columns.length))
  const styles: Record<number, { left: string; zIndex: number }> = {}
  let offset = 0
  for (let i = 0; i < count; i += 1) {
    styles[i] = { left: `${offset}px`, zIndex: 3 }
    offset += estimateColumnWidth(columns[i] ?? '')
  }
  return styles
}

/** 冻结列数是否有效（0 = 不冻；超过列数 = 全冻）。 */
export function normalizeFrozenCount(columns: readonly string[], frozenCount: number): number {
  if (!Number.isFinite(frozenCount)) return 0
  return Math.max(0, Math.min(Math.trunc(frozenCount), columns.length))
}

// ── 分页（1.3 段）──────────────────────────────────────────────────────────────────
//
// 口径：分页是**客户端对当前可见序列的再切分**（服务端分页走"按条件浏览"的 LIMIT/OFFSET）。
// 为什么要分页：一屏 5000 行 DOM 没必要全建，而"我在第几页、一共几页"是看数据时的基本方位感。

/** 一页多少行（缺省；界面可改）。 */
export const DEFAULT_PAGE_SIZE = 200

/**
 * 把可见序列切成某一页：`{ rows, page, pageCount, total }`。
 *
 * 三条口径（用例守）：
 * ① **夹紧页码**：页码给负数 / 超界都夹到合法范围（不返回空白页，让人以为"没数据"）；
 * ② **空结果 = 1 页 0 行**（不是 0 页 —— "第 0 页 / 共 0 页"读起来像出了错）；
 * ③ 页大小非正或非整数时退回 `DEFAULT_PAGE_SIZE`（不抛异常，界面不该因为一个输入框崩）。
 */
export function pageOf(
  order: number[],
  page: number,
  pageSize: number,
): { rows: number[]; page: number; pageCount: number; total: number } {
  const size = Number.isFinite(pageSize) && pageSize >= 1 ? Math.trunc(pageSize) : DEFAULT_PAGE_SIZE
  const total = order.length
  const pageCount = Math.max(1, Math.ceil(total / size))
  const wanted = Number.isFinite(page) ? Math.trunc(page) : 1
  const clamped = Math.max(1, Math.min(wanted, pageCount))
  const start = (clamped - 1) * size
  return { rows: order.slice(start, start + size), page: clamped, pageCount, total }
}

/**
 * 冻结列样式：**优先用实测宽度**（界面把每列量到的宽度报上来），没量到才退回估算。
 *
 * 为什么要有实测这一档：估算是按**表头字符数**算的，而表头往往比内容短得多 ——
 * 结果就是"冻是冻住了，但表头被盖住一半"。实测宽度只有界面能给（纯函数不读 DOM），
 * 所以这里同时接受两种来源，并**逐列回退**（某列没量到不影响其它列）。
 */
export function frozenColumnStylesMeasured(
  columns: readonly string[],
  frozenCount: number,
  measured: Record<number, number>,
): Record<number, { left: string; zIndex: number }> {
  const count = normalizeFrozenCount(columns, frozenCount)
  const styles: Record<number, { left: string; zIndex: number }> = {}
  let offset = 0
  for (let i = 0; i < count; i += 1) {
    styles[i] = { left: `${offset}px`, zIndex: 3 }
    const observed = measured[i]
    const width =
      typeof observed === 'number' && Number.isFinite(observed) && observed > 0
        ? observed
        : estimateColumnWidth(columns[i] ?? '')
    offset += width
  }
  return styles
}
