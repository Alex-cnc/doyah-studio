// SQL 编辑面的**纯函数**（Windows 侧表示层；1.2 段）
//
// 为什么单独放一个文件：补全候选的挑法与高亮片段的重建都是**可单测的纯逻辑**，
// 塞进 .vue 里就只能靠人眼看。这里只放"给什么输入、出什么结果"，不碰 DOM、不调 IPC。

import type { SqlToken } from '../ipc'
import { expandSnippet } from '../workspace/assist'

/** 补全候选项。 */
export interface CompletionItem {
  /** 插入文本（片段候选时 = 触发词，真正插入的是 `snippet` 展开结果） */
  text: string
  /** 分类（界面用来分组 / 显示依据：关键字 / 对象 / 列 / 片段） */
  kind: 'keyword' | 'object' | 'column' | 'schema' | 'snippet'
  /** 显示用的说明（例如对象来自哪个 schema） */
  detail: string
  /**
   * FR-EDIT-59 片段模板（只有 `kind === 'snippet'` 才有）。
   * 语法与 `workspace/assist.ts::expandSnippet` 同源：`${n:默认值}` 占位、`$0` 最终光标。
   */
  snippet?: string
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

// ── FR-EDIT-59 片段（结构补全）：触发词短、骨架长 ────────────────────────────────────
//
// 口径：① 触发词是**小写短词**（`sel` / `ins` / `upd` / `del`），因为它要在候选里跟关键字一起被前缀过滤命中；
// ② 模板里的占位一律给**可读默认值**（`${1:table}`），展开后用户能直接改，而不是看到一堆 `$1`；
// ③ `$0` 只有一个（最终光标），没有就落在插入文本末尾 —— 这条由 `assist.expandSnippet` 保证。
//
// 为什么四个而不是几十个：片段表是**用户要背的东西**，多了等于没有（主人明确「没用过的功能别照搬」）。
export const COMPLETION_SNIPPETS: { trigger: string; body: string; detail: string }[] = [
  { trigger: 'sel', body: 'SELECT ${1:*}\nFROM ${2:table}\nWHERE ${3:cond}$0', detail: '片段 · 查询骨架' },
  { trigger: 'ins', body: 'INSERT INTO ${1:table} (${2:col})\nVALUES (${3:value})$0', detail: '片段 · 插入' },
  { trigger: 'upd', body: 'UPDATE ${1:table}\nSET ${2:col} = ${3:value}\nWHERE ${4:cond}$0', detail: '片段 · 更新' },
  { trigger: 'del', body: 'DELETE FROM ${1:table}\nWHERE ${2:cond}$0', detail: '片段 · 删除' },
]

/** 片段候选（插入时展开模板）。 */
export function snippetCompletions(): CompletionItem[] {
  return COMPLETION_SNIPPETS.map((entry) => ({
    text: entry.trigger,
    kind: 'snippet' as const,
    detail: entry.detail,
    snippet: entry.body,
  }))
}

/**
 * 接受一个候选：把光标前那个词换成候选内容，光标落在该落的地方。
 *
 * 两种候选走同一条落笔逻辑，只是「插什么、光标放哪」不同：
 * · 普通候选 ⇒ 插 `text`，光标在插入文本之后；
 * · 片段候选 ⇒ 先 `expandSnippet` 展开（`${n:默认}` 取默认值、`$0` 决定光标），再插。
 *
 * 单独抽成纯函数的原因：落笔逻辑（替换哪个区间、光标摆哪）是**最容易在 .vue 里写错**的一段，
 * 而它完全可以单测 —— 片段插进去后光标差一格，用户每次都要手动挪，这种错不该靠肉眼发现。
 */
export function applyCompletionItem(
  text: string,
  caret: number,
  item: CompletionItem,
): { text: string; caret: number } {
  const at = Math.min(Math.max(caret, 0), text.length)
  const word = wordBeforeCaret(text, at)
  const start = at - word.length
  const inserted = item.snippet
    ? expandSnippet(item.snippet)
    : { text: item.text, caret: item.text.length }
  return { text: text.slice(0, start) + inserted.text + text.slice(at), caret: start + inserted.caret }
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
 *
 * 偏移口径：`tokens[].start/end` 是 **JS 字符串下标（UTF-16 码元）** —— 领域层
 * `sql::tokenize` 给字节偏移，IPC 边界（`highlight_sql`）已按 `Db/src/text_index.rs` 换算过。
 * 别在这里再折算一次：汉字 3 字节 / 1 码元，重复折算会把中文 SQL 切碎。
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

// ── FR-EXEC-14：执行目标判定（有选区只跑选中的那段，没有选区跑整篇）────────────────
//
// 契约原文：「**有选区只跑选中的那段，没有选区跑整篇** —— 自动判定，不需要用户先设『运行范围』」。
//
// 三条口径（都是"用户会怎么想"）：
//   ① **选区非空（去掉空白后）就以选区为准** —— 用户框出来就是要跑那一段；
//   ② 选区是**空白**（手抖拖了几个空格）⇒ **不算选区**，按整篇走（不能因为框了空格就什么都不跑）；
//   ③ 结果**原样返回文本**（不 trim）—— 行号映射、错误定位都要靠原始偏移，trim 掉就错位了。
//
// 为什么做成纯函数：判定规则（什么时候用选区）与取文本（怎么切）是两件事，
// 后者可单测；而且界面里那段 DOM 取值逻辑不该再判一遍"算不算选区"（两处判必然分叉）。

/** 执行目标的取值来源（界面拿去显示"这次跑的是选区还是整篇"）。 */
export type ExecutionSource = 'selection' | 'whole'

/** 执行目标判定结果。 */
export interface ExecutionTarget {
  /** 真正要执行的 SQL 文本（**原样**，不 trim）。 */
  sql: string
  /** 这次跑的是选区还是整篇。 */
  source: ExecutionSource
}

/**
 * 判定这一跑要执行什么。
 *
 * @param whole     整篇文本（编辑器当前内容）
 * @param selection 选区文本；没有选区传 `null` 或空串
 */
export function executionTarget(whole: string, selection: string | null | undefined): ExecutionTarget {
  const picked = selection ?? ''
  // 口径②：只含空白 ⇒ 不算选区
  if (picked.trim().length > 0) {
    return { sql: picked, source: 'selection' }
  }
  return { sql: whole, source: 'whole' }
}

