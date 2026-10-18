// 编辑面智能辅助纯逻辑（FR-EDIT-57 补全 / 59 片段 / 56 诊断上屏）—— 行为判据
//
// 口径：
//   · 词法级判断只做**标识符边界**（字母 / 数字 / 下划线 / `.` 前缀），不猜语法；
//   · 候选排序要**稳定可断言**（同类按名字、跨类按「关键字 > 函数 > 片段」），否则同一输入两次排序不同；
//   · 诊断落点一律**夹进全文**并按行归并（同一行多条 ⇒ 取最严重那条当行标记）；
//   · 片段展开只认 `$0`（最终光标）与 `${n:默认值}`（占位），未知记号原样保留（不吞字符）。

/** 补全候选类别（排序权重按此顺序：关键字 > 函数 > 片段） */
export type CompletionKind = 'keyword' | 'function' | 'snippet'

export interface CompletionItem {
  /** 展示值 = 插入值（本层不做富文本 label） */
  text: string
  kind: CompletionKind
  /** 可选的说明（悬停 / 右侧提示用） */
  detail?: string
}

export interface CompletionContext {
  /** 光标前的标识符前缀（可能为空；**不含**点号） */
  prefix: string
  /** 前缀在全文中的起点（替换范围 = [prefixStart, caret)） */
  prefixStart: number
  /** 点号前的限定符（`t.sel` ⇒ `t`；无点号则为空串）—— 限定符本身**不参与替换** */
  qualifier: string
  /** 过滤排序后的候选（最多 `limit` 条） */
  items: CompletionItem[]
}

const KIND_WEIGHT: Record<CompletionKind, number> = { keyword: 0, function: 1, snippet: 2 }

const isWordChar = (ch: string): boolean => /[A-Za-z0-9_]/.test(ch)

/**
 * FR-EDIT-57 取当前光标处的补全上下文。
 *
 *   · 前缀为空 ⇒ 候选为空（不在每次按键后弹整表）；
 *   · 前缀不区分大小写匹配候选的**前缀**；
 *   · 排序：先按「前缀完全相等」> 「前缀匹配」，再按类别权重，再按名字升序 —— 同样的输入两次排序一致。
 */
export function completionContext(
  text: string,
  caret: number,
  catalog: CompletionItem[],
  limit = 12,
): CompletionContext {
  const at = Math.min(Math.max(caret, 0), text.length)
  let start = at
  while (start > 0 && isWordChar(text[start - 1])) start -= 1
  // `t.sel` 这种：点号**不进前缀**（替换只动标识符），但限定符要交出去供调用方路由（成员补全）
  let qualifier = ''
  if (start > 0 && text[start - 1] === '.') {
    let qualifierStart = start - 1
    while (qualifierStart > 0 && isWordChar(text[qualifierStart - 1])) qualifierStart -= 1
    qualifier = text.slice(qualifierStart, start - 1)
  }
  const prefix = text.slice(start, at)
  if (prefix.length === 0) return { prefix, prefixStart: start, qualifier, items: [] }

  const lowered = prefix.toLowerCase()
  const matches = catalog.filter((item) => item.text.toLowerCase().startsWith(lowered))
  const ranked = matches
    .map((item) => ({ item, exact: item.text.toLowerCase() === lowered ? 1 : 0 }))
    .sort((a, b) => {
      if (a.exact !== b.exact) return b.exact - a.exact
      const weight = KIND_WEIGHT[a.item.kind] - KIND_WEIGHT[b.item.kind]
      if (weight !== 0) return weight
      if (a.item.text.length !== b.item.text.length) return a.item.text.length - b.item.text.length
      return a.item.text < b.item.text ? -1 : a.item.text > b.item.text ? 1 : 0
    })
    .map((entry) => entry.item)
  return { prefix, prefixStart: start, qualifier, items: ranked.slice(0, Math.max(limit, 0)) }
}

/** 接受一个候选：替换 `[prefixStart, caret)`，光标落在插入值之后 */
export function applyCompletion(
  text: string,
  caret: number,
  context: CompletionContext,
  item: CompletionItem,
): { text: string; caret: number } {
  const at = Math.min(Math.max(caret, 0), text.length)
  const next = text.slice(0, context.prefixStart) + item.text + text.slice(at)
  return { text: next, caret: context.prefixStart + item.text.length }
}

/** FR-EDIT-59 片段：`$0` = 最终光标，`${n:默认值}` = 占位（展开后取默认值），未知记号原样保留 */
export interface ExpandedSnippet {
  text: string
  /** 相对展开起点的光标位置（`text` 内下标） */
  caret: number
}

export function expandSnippet(snippet: string): ExpandedSnippet {
  const out: string[] = []
  let caret = -1
  let index = 0
  while (index < snippet.length) {
    const rest = snippet.slice(index)
    const placeholder = /^\$\{(\d+):([^}]*)\}/.exec(rest)
    if (placeholder) {
      out.push(placeholder[2])
      index += placeholder[0].length
      continue
    }
    const cursor = /^\$(\d+)/.exec(rest)
    if (cursor) {
      if (cursor[1] === '0') caret = out.join('').length
      else out.push(cursor[0])
      index += cursor[0].length
      continue
    }
    out.push(snippet[index])
    index += 1
  }
  const text = out.join('')
  return { text, caret: caret < 0 ? text.length : caret }
}

/** 触发词 → 片段（大小写不敏感；取第一个命中的） */
export function snippetFor(trigger: string, snippets: Record<string, string>): string | null {
  const lowered = trigger.toLowerCase()
  for (const key of Object.keys(snippets)) {
    if (key.toLowerCase() === lowered) return snippets[key]
  }
  return null
}

/** FR-EDIT-56 诊断上屏：诊断（字符偏移）→ 行级标记 */
export type Severity = 'error' | 'warning' | 'info'

export interface Diagnostic {
  /** 字符偏移（开区间终点） */
  start: number
  end: number
  severity: Severity
  message: string
}

export interface DiagnosticMark {
  /** 0 基行号 */
  line: number
  severity: Severity
  /** 同一行多条时取最严重那条的文案 */
  message: string
  /** 同一行命中的条数（界面显示「+N」用） */
  count: number
}

const SEVERITY_WEIGHT: Record<Severity, number> = { error: 0, warning: 1, info: 2 }

/**
 * 诊断 → 行级标记：偏移夹进全文、按行归并（同一行取最严重的一条），按行号升序。
 */
export function diagnosticsToMarks(diagnostics: Diagnostic[], text: string): DiagnosticMark[] {
  const byLine = new Map<number, DiagnosticMark>()
  const clamped = (value: number): number => Math.min(Math.max(value, 0), text.length)
  for (const item of diagnostics) {
    const start = clamped(Math.min(item.start, item.end))
    const line = text.slice(0, start).split('\n').length - 1
    const existing = byLine.get(line)
    if (!existing) {
      byLine.set(line, { line, severity: item.severity, message: item.message, count: 1 })
      continue
    }
    existing.count += 1
    if (SEVERITY_WEIGHT[item.severity] < SEVERITY_WEIGHT[existing.severity]) {
      existing.severity = item.severity
      existing.message = item.message
    }
  }
  return [...byLine.values()].sort((a, b) => a.line - b.line)
}
