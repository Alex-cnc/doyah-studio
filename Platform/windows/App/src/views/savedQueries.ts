// 已保存查询的**纯显示口径**（FR-EDIT-14 · 2026-10-18 · 第 7 轮）
//
// 为什么单独一个文件：这三件事都在「显示」这一层，但都会被单测判 ——
// 放进 `.vue` 里就只能靠真挂载顺带验，验不清边界（首行是空行 / 首行是注释 / 超长截断）。
// **重名与合法性判定不在这里**：那是领域层 `Db/src/saved_query.rs` 的唯一出处，
// 界面不许另写一套比较（两套比较的下场是「看着同名、存成了两条」）。

import type { SavedQuery } from '../ipc'

/** 默认名字的最大长度（字符）。超了用省略号 —— 列表里放得下、且看得出是哪一条。 */
export const SUGGESTED_NAME_MAX = 48

/**
 * 从 SQL 里挑一句默认名字：**第一行有内容的**（跳空行与整行注释），去掉行尾分号，
 * 折掉多余空白，超长截断。都没有就退回页签标题。
 *
 * 为什么要跳过注释行：SQL 文件/笔记里最常见的第一行就是 `-- 月度对账` 这类说明，
 * 拿它当名字并不坏，但更常见的是一大段 `-- ==` 分隔线，拿它当名字等于没名字。
 */
export function suggestQueryName(sql: string, fallback: string): string {
  for (const raw of sql.split(/\r?\n/)) {
    const trimmed = raw.trim()
    if (!trimmed) continue
    if (trimmed.startsWith('--') || trimmed.startsWith('//')) continue
    const line = trimmed.replace(/\s+/g, ' ').replace(/;\s*$/, '').trim()
    if (!line) continue
    return line.length > SUGGESTED_NAME_MAX
      ? `${line.slice(0, SUGGESTED_NAME_MAX - 1)}…`
      : line
  }
  return fallback.trim()
}

/** 保存时刻的**可读**形式（`2026-10-18T10:00:00Z` → `2026-10-18 10:00`）。认不出就给空串。 */
export function savedQueryTimeLabel(savedAt: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(savedAt ?? '')
  if (!match) return ''
  return `${match[1]}-${match[2]}-${match[3]} ${match[4]}:${match[5]}`
}

/**
 * 列表里那行副标题：连接名 · 库名 · 保存时间（**缺的段跳过**，不写「—」占位）。
 * 三段都没有就返回空串（界面据此不显示副标题）。
 */
export function savedQuerySourceLabel(query: SavedQuery): string {
  const parts = [
    query.connectionName ?? '',
    query.database ?? '',
    savedQueryTimeLabel(query.savedAt),
  ]
    .map((part) => part.trim())
    .filter((part) => part.length > 0)
  return parts.join(' · ')
}

/** SQL 的一行摘要（列表里给个眼熟的线索；换行折成空格、超长截断）。
 *
 * 泛型而不是只认 `SavedQuery`：归档条目与已保存查询**都要这一份压平口径**，
 * 两处各写一遍截断逻辑迟早长短不一（文案面就会「同一段 SQL 两个样子」）。
 */
export function savedQuerySqlPreview<T extends { sql: string }>(query: T, limit = 80): string {
  const flat = (query.sql ?? '').replace(/\s+/g, ' ').trim()
  if (!flat) return ''
  return flat.length > limit ? `${flat.slice(0, limit - 1)}…` : flat
}
