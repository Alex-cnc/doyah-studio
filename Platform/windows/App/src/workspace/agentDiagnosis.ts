// 对话式诊断（`FR-AI-03`）的**纯函数**
//
// 口径（照需求原文两条硬约束落地，不靠提示词里的一句请求）：
//   ① **结论必须引用真实证据**：证据有自己的编号（`e1`…）、**可复跑的取证 SQL**、行数据，
//      以及三种**必须分得开**的状态 —— 取到了有行 / 取到了零行 / **根本没取到**（带原因）。
//      模型回复按我们自己声明的行格式解析；没有依据的结论**整条拒绝**，引用不存在的编号、
//      引用「没取到」的证据同样拒绝，认不出来的行**原样留着**（静默丢弃会让人以为模型没说）。
//   ② **建议只产出 SQL 文本**：能不能执行由既有 `statementRisk` 判（本模块不判、也不执行），
//      界面侧只允许「放进编辑器」。
//
// 为什么要单独一个文件：取哪几种证据、资料块怎么拼、回复怎么解析，全是**可单测的纯逻辑**；
// 塞进 .vue 里就只能靠人眼看（而 `tsc --noEmit` 根本不校验 .vue）。

import type { DictKey } from '../i18n'
import type { SlowQueryReport } from '../ipc'

/** 证据种类。`plan` 走 `explain_statement`，`slow` 走 `slow_queries`，其余走通用查询。 */
export type EvidenceKind = 'plan' | 'locks' | 'slow' | 'stats'

/** 证据的三态 —— **「零行」不是「没取到」**，界面要给两句话。 */
export type EvidenceStatus = 'rows' | 'empty' | 'unavailable'

/** 一条证据的取数说明（做完以后带上状态就是 `EvidenceItem`）。 */
export interface EvidenceSpec {
  /** 编号（`e1`…）：模型回复里的 `[依据: e1,e2]` 就是引它。 */
  id: string
  kind: EvidenceKind
  /** 标题的语言键（界面翻译；本模块不拼中文）。 */
  titleKey: DictKey
  /** **可复跑的取证 SQL**（`plan` 那条 = `EXPLAIN <原语句>`，绝不 `EXPLAIN ANALYZE`）。 */
  sql: string
}

/** 取回来的证据（状态 / 行 / 原因）。 */
export interface EvidenceItem extends EvidenceSpec {
  status: EvidenceStatus
  columns: string[]
  rows: string[][]
  /** 服务端 / 外壳是否截断过这份行数据（截断要如实说）。 */
  truncated: boolean
  /** `status = unavailable` 时的**可读原因**（服务端原话优先）；有行时为空串。 */
  reason: string
}

/** 锁阻塞取证 SQL：等待中的会话 ⇄ 持锁的会话（只读，`pg_stat_activity` + `pg_locks`）。 */
export const LOCK_SQL = [
  'SELECT waiting.pid::text AS waiting_pid,',
  '       holder.pid::text AS blocking_pid,',
  '       waiting.wait_event_type, waiting.wait_event,',
  '       left(waiting.query, 200) AS waiting_query',
  '  FROM pg_locks blocked',
  '  JOIN pg_locks granted',
  '    ON granted.locktype = blocked.locktype',
  '   AND granted.database IS NOT DISTINCT FROM blocked.database',
  '   AND granted.relation IS NOT DISTINCT FROM blocked.relation',
  '   AND granted.page IS NOT DISTINCT FROM blocked.page',
  '   AND granted.tuple IS NOT DISTINCT FROM blocked.tuple',
  '   AND granted.transactionid IS NOT DISTINCT FROM blocked.transactionid',
  '   AND granted.classid IS NOT DISTINCT FROM blocked.classid',
  '   AND granted.objid IS NOT DISTINCT FROM blocked.objid',
  '   AND granted.objsubid IS NOT DISTINCT FROM blocked.objsubid',
  '   AND granted.granted',
  '   AND NOT blocked.granted',
  '  JOIN pg_stat_activity waiting ON waiting.pid = blocked.pid',
  '  JOIN pg_stat_activity holder ON holder.pid = granted.pid',
  ' WHERE waiting.datname = current_database()',
  ' ORDER BY waiting.pid',
  ' LIMIT 20',
].join('\n')

/** 表访问统计：顺序扫描占比高的表（`pg_stat_user_tables`，只读）。 */
export const STATS_SQL = [
  'SELECT relname,',
  '       n_live_tup::text AS live_rows,',
  '       seq_scan::text, idx_scan::text,',
  '       round(100.0 * seq_scan / GREATEST(seq_scan + idx_scan, 1), 1)::text AS seq_scan_pct',
  '  FROM pg_stat_user_tables',
  ' ORDER BY seq_scan DESC',
  ' LIMIT 10',
].join('\n')

/**
 * 本次要取哪几种证据（**顺序即资料块里的顺序**）。
 *
 * `plan` 用的是**用户那句原话**（`EXPLAIN` 之前不 `ANALYZE`）：诊断不能自己把语句跑一遍 ——
 * 那会在生产库上真的改数据（需求原文「建议可转成 SQL 但须走审批」同理：本功能不执行任何东西）。
 */
export function evidencePlan(statement: string): EvidenceSpec[] {
  const trimmed = statement.trim()
  return [
    { id: 'e1', kind: 'plan', titleKey: 'diag.evidence.plan', sql: `EXPLAIN ${trimmed}` },
    { id: 'e2', kind: 'locks', titleKey: 'diag.evidence.locks', sql: LOCK_SQL },
    { id: 'e3', kind: 'slow', titleKey: 'diag.evidence.slow', sql: slowEvidenceSql('total_exec_time', 'mean_exec_time') },
    { id: 'e4', kind: 'stats', titleKey: 'diag.evidence.stats', sql: STATS_SQL },
  ]
}

/**
 * 慢查询取证的**可复跑 SQL**（列名随服务端版本变 —— PG12 是 `total_time`，13 起是 `total_exec_time`，
 * 由外壳的 `slow_queries` 判定后给回来；界面不自己猜版本）。
 */
export function slowEvidenceSql(totalColumn: string, meanColumn: string): string {
  return [
    `SELECT left(query, 160) AS query, calls::text,`,
    `       round(${totalColumn}::numeric, 1)::text AS total_ms,`,
    `       round(${meanColumn}::numeric, 1)::text AS mean_ms`,
    '  FROM public.pg_stat_statements',
    " WHERE query NOT ILIKE '%pg_stat_statements%'",
    ` ORDER BY ${totalColumn} DESC`,
    ' LIMIT 10',
  ].join('\n')
}

/** 有行的证据（`null` 单元格按 `NULL` 显示 —— 资料块是给人读的，空串与 NULL 不该混）。 */
export function evidenceFromRows(
  spec: EvidenceSpec,
  columns: string[],
  rows: (string | null)[][],
  truncated = false,
): EvidenceItem {
  const text = rows.map((row) => row.map((cell) => (cell === null ? 'NULL' : cell)))
  return {
    ...spec,
    status: text.length > 0 ? 'rows' : 'empty',
    columns,
    rows: text,
    truncated,
    reason: '',
  }
}

/** **没取到**的证据：必须带原因（「没取到」与「零行」是两件事，界面不许混成一句）。 */
export function evidenceUnavailable(spec: EvidenceSpec, reason: string): EvidenceItem {
  return { ...spec, status: 'unavailable', columns: [], rows: [], truncated: false, reason }
}

/** 执行计划是一条长文本（不是表格）⇒ 按行切成单列，状态照「有行 / 零行」判。 */
export function evidenceFromPlan(spec: EvidenceSpec, plan: string): EvidenceItem {
  const lines = plan.split('\n').filter((line) => line.trim().length > 0)
  return {
    ...spec,
    status: lines.length > 0 ? 'rows' : 'empty',
    columns: [],
    rows: lines.map((line) => [line.trimEnd()]),
    truncated: false,
    reason: '',
  }
}

/** 慢查询排行（`slow_queries` 回包）→ 证据。**`available: false` 不是空列表**，是「没取到 + 原因」。 */
export function evidenceFromSlowReport(spec: EvidenceSpec, report: SlowQueryReport): EvidenceItem {
  if (!report.available) {
    const steps = report.steps.length > 0 ? ` ${report.steps.join(' ')}` : ''
    return evidenceUnavailable(spec, `${report.reason ?? '慢查询统计不可用'}${steps}`)
  }
  const rows = report.rowsOut.map((row) => [
    row.query,
    String(row.calls),
    `${row.totalMs} ms`,
    `${row.meanMs} ms`,
  ])
  return {
    ...spec,
    status: rows.length > 0 ? 'rows' : 'empty',
    columns: ['query', 'calls', 'total', 'mean'],
    rows,
    truncated: report.rowsOut.some((row) => row.truncated),
    reason: '',
  }
}

/** 资料块里每份证据最多带几行（多了没用，还挤掉后面的证据）。 */
const BRIEF_ROWS = 8

/**
 * 组装**给人复制去问模型**的资料块。
 *
 * 三条纪律：① 每份证据都带**可复跑的取证 SQL**（用户能自己核）；② 「没取到」的单独点名并把
 * 原因写进去；③ 整块超过 `limitChars` 时**从尾部砍并如实报砍了多少字符**（不静默截断）。
 */
export function buildBrief(
  items: EvidenceItem[],
  titleOf: (spec: EvidenceSpec) => string,
  limitChars = 4000,
): { text: string; droppedChars: number } {
  const blocks: string[] = [
    '以下是本机对这条查询取到的证据（编号供你引用）。请只依据这些证据下结论，'
      + '没有证据支撑的结论不要写；引用格式写在结论行末：[依据: e1,e2]。',
  ]
  for (const item of items) {
    const head = `【证据 ${item.id}】${titleOf(item)}`
    const lines: string[] = [head, `取证 SQL: ${item.sql.replace(/\n\s*/g, ' ')}`]
    if (item.status === 'unavailable') {
      lines.push(`状态: 未取到 —— ${item.reason}`)
    } else if (item.status === 'empty') {
      lines.push('状态: 查到了，但没有行（这本身也是一种证据）')
    } else {
      const shown = item.rows.slice(0, BRIEF_ROWS)
      lines.push(`状态: ${item.rows.length} 行${item.rows.length > BRIEF_ROWS ? `（只列前 ${BRIEF_ROWS} 行）` : ''}`)
      if (item.columns.length > 0) lines.push(`列: ${item.columns.join(' | ')}`)
      for (const row of shown) lines.push(`  ${row.join(' | ')}`)
      if (item.truncated) lines.push('  （行数据被服务端 / 外壳截断过，完整数据请复跑上面的 SQL）')
    }
    blocks.push(lines.join('\n'))
  }
  const full = blocks.join('\n\n')
  if (full.length <= limitChars) return { text: full, droppedChars: 0 }
  const kept = full.slice(0, limitChars)
  const dropped = full.length - kept.length
  return { text: `${kept}\n…（资料块超长，尾部 ${dropped} 个字符没有带上；请逐条复跑上面的 SQL 补齐）`, droppedChars: dropped }
}

/** 回复里的建议归属。 */
export interface AcceptedAdvice {
  kind: 'conclusion' | 'suggestion'
  /** 结论正文 / 建议的 SQL 原文。 */
  text: string
  /** 被引用的证据编号（建议行不要求引用，继承最近那条已采纳结论的引用）。 */
  citations: string[]
  /** 建议归属的结论序号（1 基；结论行为 `null`）。 */
  forConclusion: number | null
}

/** 被拒的原因（**逐条可读**：不能只说「没看懂」）。 */
export type RejectReason =
  | 'no_citation'
  | 'unknown_evidence'
  | 'unavailable_evidence'
  | 'empty_suggestion'
  | 'orphan_suggestion'

export interface RejectedAdvice {
  line: string
  reason: RejectReason
  /** 补一句人话（缺哪个编号 / 哪份证据没取到）。 */
  detail: string
}

export interface AdviceParseResult {
  accepted: AcceptedAdvice[]
  rejected: RejectedAdvice[]
  unrecognized: string[]
}

/** 行首的列表符号（`- ` / `* ` / `• ` / `1. `）先剥掉 —— 模型爱加，剥掉不损失语义。 */
const LIST_MARKER = /^\s*(?:[-*•]|\d+[.)])\s*/

/** `[依据: e1,e2]` / `【依据：e1、e2】` 两种括号与半全角冒 / 分隔符都认。 */
const CITATION = /[\[【]\s*依据\s*[:：]\s*([^\]】]*)[\]】]/

/** `结论: …` / `建议: …`（半角冒、全角冒都认）。 */
const ADVICE_LINE = /^(结论|建议)\s*[:：]\s*(.*)$/

/**
 * 解析模型回复。
 *
 * 拒绝面（**每种都有单独的理由**）：没有 `[依据: …]` 的结论、引用不存在的编号、引用「没取到」的证据、
 * 空建议、以及**前面没有任何已采纳结论**的建议（归属悬空）。认不出的行原样留在 `unrecognized`。
 */
export function parseAdvice(reply: string, items: EvidenceItem[]): AdviceParseResult {
  const known = new Map(items.map((item) => [item.id, item]))
  const accepted: AcceptedAdvice[] = []
  const rejected: RejectedAdvice[] = []
  const unrecognized: string[] = []
  let lastAccepted: AcceptedAdvice | null = null

  for (const raw of reply.split('\n')) {
    const stripped = raw.replace(LIST_MARKER, '').trim()
    if (stripped.length === 0) continue
    const matched = ADVICE_LINE.exec(stripped)
    if (!matched) {
      unrecognized.push(raw.trimEnd())
      continue
    }
    const head = matched[1]
    const body = matched[2].trim()
    if (head === '结论') {
      const cite = CITATION.exec(body)
      const text = body.replace(CITATION, '').trim()
      if (!cite) {
        rejected.push({ line: stripped, reason: 'no_citation', detail: '结论行没有引用任何证据' })
        continue
      }
      const ids = cite[1]
        .split(/[,，、\s]+/)
        .map((id) => id.trim())
        .filter((id) => id.length > 0)
      const unknown = ids.filter((id) => !known.has(id))
      if (unknown.length > 0) {
        rejected.push({
          line: stripped,
          reason: 'unknown_evidence',
          detail: `引用了不存在的证据编号：${unknown.join('、')}`,
        })
        continue
      }
      const missing = ids.filter((id) => known.get(id)?.status === 'unavailable')
      if (missing.length > 0) {
        rejected.push({
          line: stripped,
          reason: 'unavailable_evidence',
          detail: `引用了没取到的证据：${missing.join('、')}`,
        })
        continue
      }
      const entry: AcceptedAdvice = { kind: 'conclusion', text, citations: ids, forConclusion: null }
      accepted.push(entry)
      lastAccepted = entry
      continue
    }
    // 建议：不要求自己带引用（沿用最近那条已采纳结论），但**必须有归属**
    if (body.length === 0) {
      rejected.push({ line: stripped, reason: 'empty_suggestion', detail: '建议行里没有 SQL' })
      continue
    }
    if (!lastAccepted) {
      rejected.push({ line: stripped, reason: 'orphan_suggestion', detail: '这条建议前面没有已采纳的结论，无法归属' })
      continue
    }
    accepted.push({
      kind: 'suggestion',
      text: body,
      citations: lastAccepted.citations,
      forConclusion: accepted.filter((item) => item.kind === 'conclusion').length,
    })
  }
  return { accepted, rejected, unrecognized }
}
