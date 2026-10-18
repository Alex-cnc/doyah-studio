// 编辑面纯逻辑 · 第二批（FR-EDIT-51 / 52 / 53 / 54）—— 行为判据
//
// 口径（照 `Docs/需求规范书.md` §3.2 与 macOS 侧同名实现）：
//   · 函数只吃「全文 + 选区（**字符下标**，不是字节）」与「注释符 / 缩进单位」这类**纯参数**，
//     返回「新全文 + 新选区」；不碰 UI、不读语言服务、不猜语法树。
//   · 选区越界一律**夹进全文**（宁可少改一行，也不许抛异常或改到不存在的行）。
//   · 注释符 / 缩进单位由调用方按语言给（语言表是唯一登记处），本文件不内置语言清单 ——
//     否则第二份语言清单迟早与登记处分叉。
//   · 行结构统一走 `toLines` / `fromLines`（**行尾是否补换行**单独记一位），
//     搬行 / 复制行就不会因为「末行没有 \n」把行粘在一起。
//
// 四条需求各自的「错了很难查」点：
//   FR-EDIT-51 注释切换：**只动行首**、保持缩进；全注释 ⇒ 取消；有一行没注释 ⇒ 全加（不是逐行取反）。
//   FR-EDIT-52 移行 / 复制行：整行搬动，末行无 `\n` 也不会与上一行粘连；到边界是 no-op（不报错）。
//   FR-EDIT-53 自动缩进：回车**继承当前行缩进**；`{ ( [` 之后多一级；下一字符是 `} ) ]` ⇒ 回退一级。
//   FR-EDIT-54 缩进检测：按**内容**判软 / 硬 tab 与宽度（不靠扩展名）；内容不足回退默认口径。

/** 选区（字符下标；`start <= end`，`end` 为开区间） */
export interface Selection {
  start: number
  end: number
}

/** 一次编辑的结果：新全文 + 新选区 */
export interface EditResult {
  text: string
  selection: Selection
}

/** 缩进口径（FR-EDIT-54） */
export interface IndentStyle {
  kind: 'space' | 'tab'
  /** 软 tab 的宽度；硬 tab 口径下为 1（一个制表符 = 一档） */
  width: number
}

const clamp = (value: number, min: number, max: number): number =>
  Math.min(Math.max(value, min), max)

/** 把选区夹进 `[0, text.length]`，并保证 `start <= end` */
export function clampSelection(text: string, selection: Selection): Selection {
  const start = clamp(Math.min(selection.start, selection.end), 0, text.length)
  const end = clamp(Math.max(selection.start, selection.end), 0, text.length)
  return { start, end }
}

interface LineView {
  lines: string[]
  trailingNewline: boolean
}

/** 全文 → 行数组（不含行尾；末尾是否补 `\n` 单独记） */
function toLines(text: string): LineView {
  if (text === '') return { lines: [''], trailingNewline: false }
  const trailingNewline = text.endsWith('\n')
  const lines = text.split('\n')
  if (trailingNewline) lines.pop()
  return { lines, trailingNewline }
}

/** 行数组 → 全文（只在原本以 `\n` 结尾时补回那一个） */
function fromLines(view: LineView): string {
  if (view.lines.length === 0) return ''
  return view.lines.join('\n') + (view.trailingNewline ? '\n' : '')
}

/** 选区覆盖的行号区间（0 基，闭区间）；终点落在行首时**不含**下一行 */
export function affectedLineRange(text: string, selection: Selection): [number, number] {
  const { start, end } = clampSelection(text, selection)
  const startLine = text.slice(0, start).split('\n').length - 1
  const probe = end > start ? end - 1 : end
  const endLine = text.slice(0, probe).split('\n').length - 1
  return [startLine, Math.max(startLine, endLine)]
}

/** 行号区间 → 选区（行首 → 末行行尾，不含末行换行） */
function selectionOfLines(view: LineView, from: number, to: number): Selection {
  const last = Math.min(to, view.lines.length - 1)
  let start = 0
  for (let index = 0; index < from; index += 1) start += view.lines[index].length + 1
  let end = start
  for (let index = from; index <= last; index += 1) {
    end += view.lines[index].length
    if (index < last) end += 1
  }
  return { start, end }
}

const leadingIndent = (line: string): string => line.slice(0, line.length - line.trimStart().length)

/**
 * FR-EDIT-51 注释切换（⌘/）。
 *
 * · 受影响的每一行都**已**被注释（行首空白之后即注释符）⇒ 全部取消；
 * · 否则 ⇒ 全部加上（有一行没注释就是「加」，不是逐行取反）；
 * · 空行（去空白后为空）不参与判定、也不加注释符；
 * · 加注释保持原缩进（注释符插在缩进之后）。
 */
export function toggleLineComment(
  text: string,
  selection: Selection,
  commentPrefix: string,
): EditResult {
  const [from, to] = affectedLineRange(text, selection)
  const view = toLines(text)
  if (from >= view.lines.length) return { text, selection: clampSelection(text, selection) }

  const targets: number[] = []
  for (let index = from; index <= to && index < view.lines.length; index += 1) {
    if (view.lines[index].trim().length > 0) targets.push(index)
  }
  if (targets.length === 0) return { text, selection: clampSelection(text, selection) }

  const allCommented = targets.every((index) => {
    const line = view.lines[index]
    return line.slice(leadingIndent(line).length).startsWith(commentPrefix)
  })

  for (const index of targets) {
    const line = view.lines[index]
    const indent = leadingIndent(line)
    const rest = line.slice(indent.length)
    view.lines[index] = allCommented ? indent + rest.slice(commentPrefix.length) : indent + commentPrefix + rest
  }

  return { text: fromLines(view), selection: selectionOfLines(view, from, to) }
}

/**
 * FR-EDIT-52 移行 / 复制行。
 *
 * `up` / `down` 整行搬动（光标与选区跟着搬）；`duplicate` 向下复制整行，
 * 选区落在**副本**上。到边界（首行上移 / 末行下移）⇒ 原样返回（no-op）。
 */
export function moveOrDuplicateLines(
  text: string,
  selection: Selection,
  direction: 'up' | 'down' | 'duplicate',
): EditResult {
  const [from, to] = affectedLineRange(text, selection)
  const view = toLines(text)
  const last = Math.min(to, view.lines.length - 1)
  if (from >= view.lines.length) return { text, selection: clampSelection(text, selection) }

  if (direction === 'up') {
    if (from === 0) return { text, selection: clampSelection(text, selection) }
    const block = view.lines.splice(from, last - from + 1)
    view.lines.splice(from - 1, 0, ...block)
    return { text: fromLines(view), selection: selectionOfLines(view, from - 1, last - 1) }
  }

  if (direction === 'down') {
    if (last >= view.lines.length - 1) return { text, selection: clampSelection(text, selection) }
    const block = view.lines.splice(from, last - from + 1)
    view.lines.splice(from + 1, 0, ...block)
    return { text: fromLines(view), selection: selectionOfLines(view, from + 1, last + 1) }
  }

  const block = view.lines.slice(from, last + 1)
  view.lines.splice(last + 1, 0, ...block)
  return { text: fromLines(view), selection: selectionOfLines(view, last + 1, last + block.length) }
}

/**
 * FR-EDIT-53 自动缩进（回车时）。
 *
 * 返回**回车之后**应插入的缩进串（调用方先落 `\n`，再接这段）：
 *   · 默认继承当前行的行首缩进；
 *   · 当前行以 `{` `(` `[` 结尾（忽略尾随空白）⇒ 多一级；
 *   · 光标下一个非空白字符是 `}` `)` `]` ⇒ 回退一级（不低到负数）。
 */
export function autoIndentForNewline(
  currentLine: string,
  nextNonSpaceChar: string,
  indentUnit: string,
): string {
  const indent = leadingIndent(currentLine)
  if (/[})\]]/.test(nextNonSpaceChar)) {
    return indent.endsWith(indentUnit) ? indent.slice(0, indent.length - indentUnit.length) : indent
  }
  return /[{([]$/.test(currentLine.trimEnd()) ? indent + indentUnit : indent
}

/**
 * FR-EDIT-54 缩进检测（按内容，不靠扩展名）。
 *
 * · 制表符开头的非空行 ≥2 且不少于空格开头的行 ⇒ `tab`；
 * · 否则按空格，宽度取「相邻缩进档位差」的最小正值（1~8），取不到 ⇒ `fallback`；
 * · 完全没有缩进内容 ⇒ `fallback`（调用方默认口径）。
 */
export function detectIndentStyle(
  text: string,
  fallback: IndentStyle = { kind: 'space', width: 4 },
): IndentStyle {
  const lines = text.split('\n').filter((line) => line.trim().length > 0)
  const tabLines = lines.filter((line) => line.startsWith('\t')).length
  const spaceLines = lines.filter((line) => /^ +/.test(line)).length
  if (tabLines >= 2 && tabLines >= spaceLines) return { kind: 'tab', width: 1 }

  const widths = new Set<number>()
  for (const line of lines) {
    const match = /^( +)/.exec(line)
    if (match) widths.add(match[1].length)
  }
  if (widths.size === 0) return fallback
  const sorted = [...widths].sort((a, b) => a - b)
  let step = 0
  for (let index = 1; index < sorted.length; index += 1) {
    const diff = sorted[index] - sorted[index - 1]
    if (diff > 0 && (step === 0 || diff < step)) step = diff
  }
  if (step === 0) step = sorted[0]
  if (step < 1 || step > 8) return fallback
  return { kind: 'space', width: step }
}

/**
 * FR-EDIT-20 缩进 / 反缩进选中文本（多行按行处理）。
 *
 * `delta = +1` 逐行加一个缩进单位（缩进单位可为单位串）；`-1` 逐行去掉**最多**一个单位
 * （行首不足一个单位 ⇒ 能去多少去多少，不把内容削掉）。空行不动。选区保持覆盖同一批行。
 */
export function indentSelection(
  text: string,
  selection: Selection,
  delta: 1 | -1,
  indentUnit: string,
): EditResult {
  const [from, to] = affectedLineRange(text, selection)
  const view = toLines(text)
  for (let index = from; index <= to && index < view.lines.length; index += 1) {
    const line = view.lines[index]
    if (line.trim().length === 0) continue
    if (delta === 1) {
      view.lines[index] = indentUnit + line
      continue
    }
    // 反缩进：优先去掉一个完整单位；去不掉就去掉行首空白里的一格
    if (line.startsWith(indentUnit)) view.lines[index] = line.slice(indentUnit.length)
    else {
      const indent = leadingIndent(line)
      if (indent.length > 0) view.lines[index] = indent.slice(1) + line.slice(indent.length)
    }
  }
  return { text: fromLines(view), selection: selectionOfLines(view, from, to) }
}

/** 缩进口径 → 实际插入串（`tab` 口径恒为一个制表符） */
export function indentUnitOf(style: IndentStyle): string {
  return style.kind === 'tab' ? '\t' : ' '.repeat(style.width)
}

// ── FR-EDIT-49 括号 / 引号自动配对（打出左半补右半、光标留中间；闭合符重复则跳过；有选区则包裹）──
/** 默认配对表（语言无关的那几种；语言特有的由调用方覆盖） */
export const DEFAULT_PAIRS: Record<string, string> = {
  '(': ')', '[': ']', '{': '}', '"': '"', "'": "'", '`': '`',
}

export type PairOutcome =
  | { kind: 'pair' | 'wrap' | 'skip'; text: string; selection: Selection }
  | null

/**
 * 决定「这一次按键要不要接管」：
 *   · 选区非空 + 打出配对符 ⇒ **包裹**选区（左 + 原选区 + 右），选区落在原文上；
 *   · 打出的闭合符正好等于光标处的字符 ⇒ **跳过**（不重复输入，光标 +1）；
 *   · 打出左半符 / 引号 ⇒ 补右半，光标夹在中间；
 *   · 其余 ⇒ `null`（调用方按普通输入处理）。
 */
export function autoPair(
  text: string,
  selection: Selection,
  typed: string,
  pairs: Record<string, string> = DEFAULT_PAIRS,
): PairOutcome {
  const { start, end } = clampSelection(text, selection)
  const open = pairs[typed]
  const closers = new Set(Object.values(pairs))

  if (start !== end && open) {
    const inner = text.slice(start, end)
    const next = text.slice(0, start) + typed + inner + open + text.slice(end)
    return { kind: 'wrap', text: next, selection: { start: start + 1, end: end + 1 } }
  }
  if (closers.has(typed) && text[start] === typed) {
    return { kind: 'skip', text, selection: { start: start + 1, end: start + 1 } }
  }
  if (open && start === end) {
    const next = text.slice(0, start) + typed + open + text.slice(start)
    return { kind: 'pair', text: next, selection: { start: start + 1, end: start + 1 } }
  }
  return null
}

// ── FR-EDIT-50 括号匹配高亮（光标紧邻括号 ⇒ 成对点亮；不配平 ⇒ 只点亮自己 + 告警位）──
export interface BracketMatch {
  /** 光标侧那个括号的位置 */
  at: number
  /** 配对的那个括号位置；`null` = 不配平 */
  partner: number | null
}

const OPENERS = '([{'
const CLOSERS = ')]}'
const PARTNER: Record<string, string> = { '(': ')', '[': ']', '{': '}', ')': '(', ']': '[', '}': '{' }

/**
 * 找光标紧邻括号的配对位置（**只看括号，不跳字符串 / 注释** —— 词法级匹配属 `FR-EDIT-03` 的检查面，
 * 这里先做视觉高亮所需的那一层，局限写在此处如实登记）。
 *
 * 光标优先看**光标前**那个字符（刚打完左括号的常态），再看光标处那个字符。
 */
export function matchBracket(text: string, caret: number): BracketMatch | null {
  const at = clamp(caret, 0, text.length)
  const candidates = [at - 1, at]
  for (const index of candidates) {
    if (index < 0 || index >= text.length) continue
    const ch = text[index]
    if (!(ch in PARTNER)) continue
    const partner = findPartner(text, index, ch)
    return { at: index, partner }
  }
  return null
}

function findPartner(text: string, index: number, ch: string): number | null {
  const mate = PARTNER[ch]
  const forward = OPENERS.includes(ch)
  const step = forward ? 1 : -1
  let depth = 0
  for (let cursor = index; cursor >= 0 && cursor < text.length; cursor += step) {
    const current = text[cursor]
    if (current === ch) depth += 1
    else if (current === mate) {
      depth -= 1
      if (depth === 0) return cursor
    }
  }
  return null
}

// ── FR-EDIT-60 撤销粒度（连续输入合并成一步；行级编辑各算一步）──
export type EditKind = 'insert' | 'delete' | 'line'

export interface EditStep {
  kind: EditKind
  /** 编辑发生处 */
  at: number
  /** 编辑结束处（插入/删除后的位置） */
  atEnd: number
  /** 发生时刻（毫秒，调用方给的单调时钟） */
  atMs: number
}

/** 两次连续输入合并成一次撤销的最大间隔（毫秒）—— 超过就当两段 */
export const COALESCE_WINDOW_MS = 800

/**
 * 相邻两步是否合并成一步撤销：
 *   · 行级编辑（移行 / 注释切换 / 补全）**永远独立**；
 *   · 同为插入或同为删除、位置首尾相接、间隔 ≤ 800 ms ⇒ 合并；
 *   · 插入与删除交替、或中间断档 ⇒ 独立。
 */
export function shouldCoalesce(previous: EditStep, next: EditStep): boolean {
  if (previous.kind === 'line' || next.kind === 'line') return false
  if (previous.kind !== next.kind) return false
  if (next.atMs - previous.atMs > COALESCE_WINDOW_MS) return false
  const contiguous = next.at === previous.atEnd || next.atEnd === previous.at
  return contiguous
}

