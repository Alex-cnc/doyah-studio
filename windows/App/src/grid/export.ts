// 结果集导出的**多种格式**（Windows 侧表示层；1.3 段）
//
// 为什么单独一个文件、又为什么全是纯函数：导出是"看着简单、一粘就错"的典型地方
// （引号、逗号、换行、NULL 各格式的处理都不一样），必须能单测。
//
// 五种口径（写清楚，免得下一轮漂）：
//   ① **NULL 在各格式里各有正确写法**：CSV/TSV 是**空字段**（贴进表格就是空单元格），
//      JSON 是 `null`，Markdown 是空，SQL 是 `NULL` 关键字。糊成一样必错。
//   ② **CSV 按 RFC 4180**：字段含逗号 / 引号 / 换行时整个字段加引号，字段内的引号**翻倍**。
//   ③ **TSV 不能加引号**（Excel 不认），所以制表符与换行**替换成空格** —— 宁可丢格式，不能串列。
//   ④ **JSON 保留类型**：能取到数值形态的按数字写、NULL 按 null 写、其余按字符串 ——
//      全写成字符串会让下游还得再解析一次（而那是我们已经有 `numRows` 的信息）。
//   ⑤ **Markdown 转义竖线与换行**：表格里一个裸 `|` 会把列数撑坏。

import type { QueryResult } from '../ipc'

/** 导出的目标格式。 */
export type ExportFormat = 'tsv' | 'csv' | 'json' | 'markdown' | 'sqlInsert'

/** 一行在结果里的显示文本（NULL → 空串）。 */
function textOf(cell: string | null): string {
  return cell === null ? '' : cell
}

/** 取某格的数值形态（取不到 ⇒ `null`）。 */
function numOf(result: QueryResult, rowIndex: number, column: number): number | null {
  const value = result.numRows?.[rowIndex]?.[column]
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

/** CSV 单元格（RFC 4180）。 */
export function csvCell(cell: string | null): string {
  const text = textOf(cell)
  if (/[",\r\n]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`
  }
  return text
}

/** TSV 单元格：制表符与换行替换成空格（Excel 不认引号，只能这么办）。 */
export function tsvCell(cell: string | null): string {
  return textOf(cell).replace(/[\t\r\n]+/g, ' ')
}

/** Markdown 单元格：竖线转义、换行变空格。 */
export function markdownCell(cell: string | null): string {
  return textOf(cell).replace(/\|/g, '\\|').replace(/[\r\n]+/g, ' ')
}

/** SQL 字面量（只用于生成 INSERT 预览文本；**不是**执行通路的一部分）。 */
export function sqlLiteral(cell: string | null, numeric: number | null): string {
  if (cell === null) return 'NULL'
  if (numeric !== null) return String(numeric)
  return `'${cell.replace(/'/g, "''")}'`
}

/** 标识符加引号（表名 / 列名）。 */
function quoteIdent(name: string): string {
  return `"${name.replace(/"/g, '""')}"`
}

/**
 * 按格式导出**当前可见的那些行**。
 *
 * `order` 是行下标序列（与网格里看到的顺序一致 —— 导出必须与眼前一致，不能偷偷导出全部）。
 * `tableName` 只有 `sqlInsert` 用得上；没给时用 `results` 作表名并在返回文本里如实写出来。
 */
export function exportRows(
  result: QueryResult,
  order: number[],
  format: ExportFormat,
  tableName?: string,
): string {
  switch (format) {
    case 'tsv': {
      const head = result.columns.map((c) => tsvCell(c)).join('\t')
      const body = order.map((i) => (result.rows[i] ?? []).map((c) => tsvCell(c)).join('\t'))
      return [head, ...body].join('\n')
    }
    case 'csv': {
      const head = result.columns.map((c) => csvCell(c)).join(',')
      const body = order.map((i) => (result.rows[i] ?? []).map((c) => csvCell(c)).join(','))
      return [head, ...body].join('\r\n')
    }
    case 'json': {
      const items = order.map((i) => {
        const row = result.rows[i] ?? []
        const item: Record<string, string | number | null> = {}
        result.columns.forEach((column, j) => {
          const cell = row[j] ?? null
          if (cell === null) {
            item[column] = null
          } else {
            const numeric = numOf(result, i, j)
            item[column] = numeric === null ? cell : numeric
          }
        })
        return item
      })
      return JSON.stringify(items, null, 2)
    }
    case 'markdown': {
      const head = `| ${result.columns.map((c) => markdownCell(c)).join(' | ')} |`
      const rule = `| ${result.columns.map(() => '---').join(' | ')} |`
      const body = order.map((i) => `| ${(result.rows[i] ?? []).map((c) => markdownCell(c)).join(' | ')} |`)
      return [head, rule, ...body].join('\n')
    }
    case 'sqlInsert': {
      const table = tableName && tableName.trim() ? tableName.trim() : 'results'
      const columns = result.columns.map(quoteIdent).join(', ')
      const lines = order.map((i) => {
        const row = result.rows[i] ?? []
        const values = result.columns
          .map((_, j) => sqlLiteral(row[j] ?? null, numOf(result, i, j)))
          .join(', ')
        return `INSERT INTO ${table} (${columns}) VALUES (${values});`
      })
      return lines.join('\n')
    }
  }
}

/** 各格式在界面上的名字（与导出实现同一个文件，避免"加了格式忘了加名字"）。 */
export const EXPORT_FORMAT_LABELS: Record<ExportFormat, string> = {
  tsv: 'TSV（贴 Excel）',
  csv: 'CSV',
  json: 'JSON',
  markdown: 'Markdown 表格',
  sqlInsert: 'INSERT 语句',
}
