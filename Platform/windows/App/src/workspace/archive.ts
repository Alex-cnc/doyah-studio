// 查询自动归档（FR-EDIT-31）—— 行为判据
//
// 口径：
//   · 归档路径 = `queries/<YYYY-MM-DD>.sql`（按天一个文件），日期取**本地时区**的 `YYYY-MM-DD`；
//   · 追加时用 `-- <HH:MM:SS> <页签标题>` 做分隔注释，SQL 原样保留（不重新格式化、不吞分号）；
//   · 重复执行同一条 SQL 也照记（归档是流水账，不是去重表）；
//   · 单文件超过上限时不静默丢，而是**如实返回 false**（调用方据此提示）。

export const ARCHIVE_DIR = 'queries'

/** 日期部分（本地时区）：`2026-09-27` */
export function archiveDate(epochMs: number): string {
  const date = new Date(epochMs)
  const pad = (value: number): string => String(value).padStart(2, '0')
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

/** 时刻部分（本地时区）：`09:05:07` */
export function archiveTime(epochMs: number): string {
  const date = new Date(epochMs)
  const pad = (value: number): string => String(value).padStart(2, '0')
  return `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`
}

/** 归档文件相对路径：`queries/2026-09-27.sql` */
export function archivePath(epochMs: number): string {
  return `${ARCHIVE_DIR}/${archiveDate(epochMs)}.sql`
}

/** 追加后的一整段（含分隔注释）；`title` 为空时只写时刻 */
export function archiveEntry(sql: string, title: string, epochMs: number): string {
  const header = `-- ${archiveTime(epochMs)}${title.trim() ? ` ${title.trim()}` : ''}`
  return `${header}\n${sql.replace(/\s+$/, '')}\n`
}

/** 单文件上限（字符）；超了不静默丢，返回 false 让调用方提示 */
export const ARCHIVE_MAX_CHARS = 512 * 1024

/** 把一条 SQL 追加进归档内容；超过上限 ⇒ `null`（调用方如实提示「今天这份满了」） */
export function appendArchive(existing: string, sql: string, title: string, epochMs: number): string | null {
  const entry = archiveEntry(sql, title, epochMs)
  const next = existing.endsWith('\n') || existing.length === 0 ? existing + entry : `${existing}\n${entry}`
  if (next.length > ARCHIVE_MAX_CHARS) return null
  return next
}
