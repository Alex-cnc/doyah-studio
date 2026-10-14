// SQL 编辑面的**纯函数**（Windows 侧表示层；1.2 段）
//
// 为什么单独放一个文件：补全候选的挑法与高亮片段的重建都是**可单测的纯逻辑**，
// 塞进 .vue 里就只能靠人眼看。这里只放"给什么输入、出什么结果"，不碰 DOM、不调 IPC。

import type { SqlToken } from '../ipc'

/** 补全候选项。 */
export interface CompletionItem {
  /** 插入文本 */
  text: string
  /** 分类（界面用来分组 / 显示依据：关键字 / 对象 / 列） */
  kind: 'keyword' | 'object' | 'column' | 'schema'
  /** 显示用的说明（例如对象来自哪个 schema） */
  detail: string
}

/** 光标处正在输入的"词"（用于补全过滤）：从光标往前取连续的标识符字符。 */
export function wordBeforeCaret(text: string, caret: number): string {
  let start = caret
  while (start > 0) {
    const ch = text[start - 1]
    if (/[A-Za-z0-9_$\u4e00-\u9fff]/.test(ch)) start -= 1
    else break
  }
  return text.slice(start, caret)
}

/**
 * 按已输入的词过滤候选：**前缀匹配优先、包含匹配其次**，都不区分大小写。
 *
 * 口径：① 空词 = 全部候选（但界面只在用户真开始打字时才弹，避免一进编辑器就糊一屏）；
 * ② 结果里**同一个插入文本只留一条**（大小写不同的重复项会让列表看起来有鬼影）；
 * ③ 排序稳定：前缀命中在前，其余保持传入顺序。
 */
export function filterCompletions(items: CompletionItem[], word: string, limit = 50): CompletionItem[] {
  const needle = word.trim().toLowerCase()
  const seen = new Set<string>()
  const prefix: CompletionItem[] = []
  const contains: CompletionItem[] = []
  for (const item of items) {
    const key = item.text.toLowerCase()
    if (seen.has(key)) continue
    const lower = key
    if (needle && !lower.includes(needle)) continue
    seen.add(key)
    if (needle && lower.startsWith(needle)) prefix.push(item)
    else contains.push(item)
  }
  return [...prefix, ...contains].slice(0, limit)
}

/** SQL 关键字候选（与领域层 `sql::KEYWORDS` 同一份名单的**显示用**大写形式）。 */
export const COMPLETION_KEYWORDS: string[] = [
  'SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE', 'CREATE',
  'ALTER', 'DROP', 'TABLE', 'VIEW', 'INDEX', 'JOIN', 'LEFT', 'RIGHT', 'INNER', 'OUTER', 'ON',
  'GROUP', 'BY', 'ORDER', 'HAVING', 'LIMIT', 'OFFSET', 'UNION', 'ALL', 'DISTINCT', 'AS', 'AND',
  'OR', 'NOT', 'NULL', 'IS', 'IN', 'EXISTS', 'BETWEEN', 'LIKE', 'CASE', 'WHEN', 'THEN', 'ELSE',
  'END', 'CAST', 'ASC', 'DESC', 'EXPLAIN', 'ANALYZE', 'BEGIN', 'COMMIT', 'ROLLBACK', 'RETURNING',
  'WITH', 'PRIMARY', 'KEY', 'REFERENCES', 'DEFAULT', 'COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'COALESCE',
]

/** 关键字候选（给补全用）。 */
export function keywordCompletions(): CompletionItem[] {
  return COMPLETION_KEYWORDS.map((text) => ({ text, kind: 'keyword' as const, detail: '关键字' }))
}

/**
 * 把已加载的对象变成候选。
 *
 * 口径：**同时给对象名与限定名两类候选** —— 只给对象名，用户就没法直接敲 `app.orders`；
 * 只给限定名，用户就得每次多打一段 schema。两类都给，前缀过滤自然各取所需。
 */
export function objectCompletions(
  objects: { schema: string; name: string }[],
): CompletionItem[] {
  const out: CompletionItem[] = []
  for (const o of objects) {
    out.push({ text: o.name, kind: 'object', detail: `对象 · ${o.schema}` })
    out.push({ text: `${o.schema}.${o.name}`, kind: 'object', detail: '限定名' })
  }
  return out
}

/** 一段高亮片段：文本 + 类别（界面按类别上色；类别名与领域层 `SqlTokenKind` 一致）。 */
export interface HighlightPiece {
  text: string
  kind: SqlToken['kind']
}

/**
 * 把「原文 + 词法单元」重建成可渲染的片段序列。
 *
 * 三条不变量（用例守）：
 * ① **拼接回来逐字等于原文**（高亮不许丢字符、不许加字符）；
 * ② 单元位置越界或乱序时**不崩**：按可信的部分渲染，剩下的当普通文本 —— 编辑器不能因为
 *    一次分词异常就白屏（我正在打字时尤其如此）；
 * ③ 空输入给空片段。
 */
export function highlightPieces(sql: string, tokens: SqlToken[]): HighlightPiece[] {
  const out: HighlightPiece[] = []
  let cursor = 0
  for (const token of tokens) {
    if (token.start < cursor || token.end > sql.length || token.end <= token.start) continue
    if (token.start > cursor) {
      out.push({ text: sql.slice(cursor, token.start), kind: 'punctuation' })
    }
    out.push({ text: sql.slice(token.start, token.end), kind: token.kind })
    cursor = token.end
  }
  if (cursor < sql.length) {
    out.push({ text: sql.slice(cursor), kind: 'punctuation' })
  }
  return out
}

/**
 * 从多段执行的逐段结果里挑出"当前要在网格里看的那一段"。
 *
 * 口径：优先**第一条失败的**（用户最需要看的是哪儿断了），否则**最后一条成功的**
 * （"跑完看最后一句的结果"是常见期望）。都没有就返回 `null`。
 */
export function pickDisplayedOutcome<T extends { ok: boolean; result: unknown }>(
  outcomes: T[],
): number | null {
  if (outcomes.length === 0) return null
  const firstFailure = outcomes.findIndex((o) => !o.ok)
  if (firstFailure >= 0) return firstFailure
  for (let i = outcomes.length - 1; i >= 0; i -= 1) {
    if (outcomes[i].ok && outcomes[i].result) return i
  }
  return outcomes.length - 1
}

/** 一段结果的摘要文案（界面与测试共用同一份口径）。 */
export function outcomeSummary(outcome: { ok: boolean; result: { rows?: unknown[]; columns?: unknown[]; affected?: number | null } | null }): string {
  if (!outcome.ok) return '失败'
  const result = outcome.result
  if (!result) return '完成'
  if ((result.columns?.length ?? 0) === 0) {
    return `影响 ${result.affected ?? '未知'} 行`
  }
  return `${result.rows?.length ?? 0} 行`
}
