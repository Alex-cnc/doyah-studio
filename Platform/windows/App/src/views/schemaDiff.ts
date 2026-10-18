// Schema 对比与同步（FR-DDL-04）的**纯展示逻辑**：文案拼装 / 脚本导出 / 时间格式化。
//
// 为什么单独一份、不写在组件里：组件里的模板跑不进 node 测（本仓 vitest 环境是 `node`，
// 组件验证本来靠挂载测），而这几条规则（脚本怎么拼、时间怎么显示、缺项怎么数）**必须能单独判**。
// 这里只做字符串，不碰 ipc、不读全局状态。

import type { DictKey } from '../i18n'
import type { SchemaDiffReport, SchemaSnapshot, TableDiff } from '../ipc'

/** 差异状态 → 语言表 key（一处映射，组件不各写一份 if）。 */
export const STATUS_KEYS: Record<TableDiff['status'], DictKey> = {
  create: 'schema.status.create',
  drop: 'schema.status.drop',
  alter: 'schema.status.alter',
  same: 'schema.status.same',
}

type Translate = (key: DictKey, vars?: Record<string, string | number>) => string

/**
 * 一张表的差异摘要（`加 2 列 · 删 1 列 · 改 3 列 · 主键不同`）。
 *
 * 只列**非零**的项：全零时给空串（调用方据此不渲染），而不是写一排「加 0 列」。
 */
export function columnSummary(diff: TableDiff, t: Translate): string {
  const parts: string[] = []
  if (diff.addedColumns.length) parts.push(t('schema.addedCols', { n: diff.addedColumns.length }))
  if (diff.removedColumns.length) parts.push(t('schema.removedCols', { n: diff.removedColumns.length }))
  if (diff.alteredColumns.length) parts.push(t('schema.alteredCols', { n: diff.alteredColumns.length }))
  if (diff.primaryKeyDiffers) parts.push(t('schema.pkDiffers'))
  return parts.join(' · ')
}

/**
 * 同步脚本的**可复制文本**：逐条 `sql`（含注释头）之间空一行。
 *
 * 空报告给空串（不产出「看起来像脚本」的空白内容）。顺序照报告给的原序（建表 → 改表 → 删表），
 * 这里不重排 —— 重排会让界面看到的和被复制的不一致。
 */
export function statementScript(report: SchemaDiffReport | null): string {
  if (!report || report.statements.length === 0) return ''
  return report.statements.map((s) => s.sql).join('\n\n')
}

/** 抓快照的时间（`YYYY-MM-DD HH:mm`；本地时区，用户看的是自己机器的时间）。 */
export function formatTakenAt(epochMs: number): string {
  if (!Number.isFinite(epochMs) || epochMs <= 0) return '—'
  const at = new Date(epochMs)
  const pad = (n: number): string => String(n).padStart(2, '0')
  return `${at.getFullYear()}-${pad(at.getMonth() + 1)}-${pad(at.getDate())} ${pad(at.getHours())}:${pad(at.getMinutes())}`
}

/** 一侧快照的状态行；没抓过就明说「还没抓」（不用空白冒充一个空库）。 */
export function slotLine(snapshot: SchemaSnapshot | null, t: Translate): string {
  if (!snapshot) return t('schema.slotEmpty')
  return t('schema.slotFilled', {
    schema: snapshot.schema,
    tables: snapshot.tables.length,
    when: formatTakenAt(snapshot.takenAt),
  })
}

/** 报告里各类表各几张（界面标题与判据都按它读，别在模板里各数一遍）。 */
export function diffCounts(report: SchemaDiffReport | null): {
  created: number
  altered: number
  dropped: number
  skipped: number
} {
  if (!report) return { created: 0, altered: 0, dropped: 0, skipped: 0 }
  return {
    created: report.createdTables,
    altered: report.alteredTables,
    dropped: report.droppedTables,
    skipped: report.skipped.length,
  }
}
