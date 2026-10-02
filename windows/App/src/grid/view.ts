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
