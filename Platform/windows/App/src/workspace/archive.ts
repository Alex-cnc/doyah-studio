// 查询自动归档（FR-EDIT-31）—— 领域口径（格式 / 解析 / 合并规则**只有这一份**）
//
// 需求条文（《需求规范书》FR-EDIT-31）：执行过的 SQL 自动保存成 `.sql` 文件，**按天一个文件**
// （`queries/2026-09-23.sql`）；**同一条 SQL 重复执行只累计「执行次数」，不重复抄写**；
// 条目带连接 / 库 / 首次与最近执行时间 / 耗时 / 影响行数。
//
// 由此定下四条口径（每条都有判据）：
//   · 路径 = `queries/<YYYY-MM-DD>.sql`，日期取**本地时区**（归档是给人看的，日子要跟用户看到的一致）；
//   · 条目 = 一行注释头 + 原样 SQL：`-- HH:MM:SS {"title":"…","runs":3,…}` ——
//     元数据用 JSON 夹在注释里，标题 / 库名带空格或竖线都不会切错格；
//   · SQL **原样保留**（不重新格式化、不吞分号、不吞行尾注释）；
//   · 单文件超过上限 ⇒ **如实返回 null**（调用方提示「今天这份满了」），绝不静默丢。
//
// 为什么「渲染」与「解析」必须互为逆：界面显示的清单就是文件里那份内容 —— 两处各写一遍格式，
// 改一处必漏一处，最后留下的旧文件谁都读不出来。

export const ARCHIVE_DIR = 'queries'

/** 单文件上限（字符）；超了不静默丢，返回 null 让调用方提示 */
export const ARCHIVE_MAX_CHARS = 512 * 1024

/** 一条归档条目（一天一份文件里的一条）。 */
export interface ArchiveEntry {
  /** 原样 SQL（渲染时原样写回，解析时原样读回）。 */
  sql: string
  /** 页签标题（可为空 —— 空就只显示时刻）。 */
  title: string
  /** 执行时的连接名（无连接上下文时为空）。 */
  connectionName: string | null
  /** 执行时的库名。 */
  database: string | null
  /** 累计执行次数（同一条 SQL 每执行一次 +1）。 */
  runs: number
  /** 首次执行时刻 `HH:MM:SS`（同一天内，所以只存时刻）。 */
  firstAt: string
  /** 最近一次执行时刻 `HH:MM:SS`。 */
  lastAt: string
  /** 最近一次的耗时（毫秒）；拿不到就是 null（**不编数**）。 */
  elapsedMs: number | null
  /** 最近一次的影响行数（写语句）或返回行数（查询）；拿不到就是 null。 */
  rows: number | null
}

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

/** 条目头：`-- 09:05:07 {"title":"查询 1","runs":1,…}`（单行；JSON 里不会有换行）。 */
const HEADER = /^-- (\d{2}:\d{2}:\d{2}) (\{.*\})\s*$/

/** 渲染一条（**唯一的写入格式**）。 */
export function renderArchiveEntry(entry: ArchiveEntry): string {
  const meta: Record<string, unknown> = {
    title: entry.title.trim(),
    runs: Math.max(1, Math.trunc(entry.runs)),
    first: entry.firstAt,
    last: entry.lastAt,
  }
  if (entry.connectionName) meta.conn = entry.connectionName
  if (entry.database) meta.db = entry.database
  if (entry.elapsedMs !== null) meta.ms = Math.max(0, Math.trunc(entry.elapsedMs))
  if (entry.rows !== null) meta.rows = Math.trunc(entry.rows)
  const sql = entry.sql.replace(/\s+$/, '')
  return `-- ${entry.lastAt} ${JSON.stringify(meta)}\n${sql}\n\n`
}

/** 渲染整天（条目之间空一行；末条也留一个换行，追加时不用猜前一条结尾）。 */
export function renderArchive(entries: ArchiveEntry[]): string {
  return entries.map(renderArchiveEntry).join('')
}

/** 头里的元数据 → 条目（缺字段 / 形状不对 ⇒ 不当成条目头，那一行按 SQL 正文处理）。 */
function parseMeta(raw: string): Omit<ArchiveEntry, 'sql'> | null {
  let value: unknown
  try {
    value = JSON.parse(raw)
  } catch {
    return null
  }
  if (!value || typeof value !== 'object') return null
  const record = value as Record<string, unknown>
  const runs = typeof record.runs === 'number' ? Math.trunc(record.runs) : 0
  const first = typeof record.first === 'string' ? record.first : ''
  const last = typeof record.last === 'string' ? record.last : ''
  if (runs < 1 || !/^\d{2}:\d{2}:\d{2}$/.test(first) || !/^\d{2}:\d{2}:\d{2}$/.test(last)) return null
  return {
    title: typeof record.title === 'string' ? record.title : '',
    connectionName: typeof record.conn === 'string' && record.conn ? record.conn : null,
    database: typeof record.db === 'string' && record.db ? record.db : null,
    runs,
    firstAt: first,
    lastAt: last,
    elapsedMs: typeof record.ms === 'number' ? Math.trunc(record.ms) : null,
    rows: typeof record.rows === 'number' ? Math.trunc(record.rows) : null,
  }
}

/**
 * 解析一整天（**与 `renderArchive` 互为逆**：`parseArchive(renderArchive(x))` 逐条相等）。
 *
 * SQL 正文里出现 `-- ` 注释不会被误认成条目头：头必须同时满足「时刻 + 一整个 JSON 对象 +
 * runs / first / last 齐全」，普通注释命中不了。
 */
export function parseArchive(content: string): ArchiveEntry[] {
  const entries: ArchiveEntry[] = []
  let current: { meta: Omit<ArchiveEntry, 'sql'>; lines: string[] } | null = null
  const flush = (): void => {
    if (!current) return
    const sql = current.lines.join('\n').replace(/\s+$/, '')
    if (sql.trim()) entries.push({ ...current.meta, sql })
    current = null
  }
  for (const line of content.split('\n')) {
    const header = HEADER.exec(line)
    if (header) {
      const meta = parseMeta(header[2])
      if (meta) {
        flush()
        current = { meta, lines: [] }
        continue
      }
    }
    if (current) current.lines.push(line)
  }
  flush()
  return entries
}

/** SQL 的相等口径：**去首尾空白后的全文**（不改大小写、不折空白 —— 归档是给人读的）。 */
export function sameArchivedSql(left: string, right: string): boolean {
  return left.trim() === right.trim()
}

/** 一条新执行（界面把这一次的上下文摊进来；`runs` 由合并函数决定）。 */
export function incomingEntry(
  sql: string,
  title: string,
  connectionName: string | null,
  database: string | null,
  epochMs: number,
  elapsedMs: number | null,
  rows: number | null,
): ArchiveEntry {
  const at = archiveTime(epochMs)
  return {
    sql,
    title,
    connectionName,
    database,
    runs: 1,
    firstAt: at,
    lastAt: at,
    elapsedMs,
    rows,
  }
}

/**
 * 把一条执行并进当天内容：**同一条 SQL 只累计次数**（首次时间不动、最近时间与耗时换成这一次）。
 *
 * 返回 `null` = 这一条会让文件超过上限（调用方如实提示，不写半份）。
 */
export function mergeArchiveEntry(
  content: string,
  incoming: ArchiveEntry,
): { content: string; runs: number } | null {
  const entries = parseArchive(content)
  const existing = entries.find((entry) => sameArchivedSql(entry.sql, incoming.sql))
  if (existing) {
    existing.runs += Math.max(1, Math.trunc(incoming.runs))
    existing.lastAt = incoming.lastAt
    if (incoming.title.trim()) existing.title = incoming.title
    if (incoming.connectionName) existing.connectionName = incoming.connectionName
    if (incoming.database) existing.database = incoming.database
    if (incoming.elapsedMs !== null) existing.elapsedMs = incoming.elapsedMs
    if (incoming.rows !== null) existing.rows = incoming.rows
  } else {
    entries.push({ ...incoming, runs: Math.max(1, Math.trunc(incoming.runs)), firstAt: incoming.lastAt })
  }
  const next = renderArchive(entries)
  if (next.length > ARCHIVE_MAX_CHARS) return null
  const saved = entries.find((entry) => sameArchivedSql(entry.sql, incoming.sql))
  return { content: next, runs: saved?.runs ?? 1 }
}
