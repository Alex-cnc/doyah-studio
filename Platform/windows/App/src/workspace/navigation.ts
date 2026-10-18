// 跳转与符号定位（FR-EDIT-19 跳到指定行列 / FR-EDIT-58 悬停文档与跳定义）—— 行为判据
//
// 口径：
//   · 跳转输入只认 `行` / `行:列` 两种写法（列可省；1 基，与状态栏一致），非法输入**如实拒绝**并给原因；
//   · 跳转目标一律**夹进全文**（行号超界 ⇒ 落到末行；列超界 ⇒ 落到行尾），不抛异常；
//   · 符号定位只做**词法级**（标识符 + 定义候选行），不建 AST —— 局限就地登记，升级留给后续片。

export interface JumpTarget {
  /** 0 基行号 */
  line: number
  /** 0 基列号（字符下标） */
  column: number
}

export type JumpParse = { ok: true; target: JumpTarget } | { ok: false; reason: string }

/** FR-EDIT-19 解析「跳到指定行或列」的输入（1 基），并夹进全文 */
export function parseJumpInput(input: string, text: string): JumpParse {
  const trimmed = input.trim()
  if (trimmed.length === 0) return { ok: false, reason: '没有输入行号' }
  const match = /^(\d+)(?:\s*[:,]\s*(\d+))?$/.exec(trimmed)
  if (!match) return { ok: false, reason: '只认「行」或「行:列」两种写法' }
  const line = Number.parseInt(match[1], 10)
  const column = match[2] ? Number.parseInt(match[2], 10) : 1
  if (line < 1) return { ok: false, reason: '行号从 1 开始' }
  const lines = text.split('\n')
  const targetLine = Math.min(line, lines.length) - 1
  const lineText = lines[targetLine] ?? ''
  const targetColumn = Math.min(Math.max(column, 1), lineText.length + 1) - 1
  return { ok: true, target: { line: targetLine, column: targetColumn } }
}

/** 跳转目标 → 全文字符偏移（供光标定位） */
export function offsetOfJump(text: string, target: JumpTarget): number {
  const lines = text.split('\n')
  const line = Math.min(Math.max(target.line, 0), lines.length - 1)
  let offset = 0
  for (let index = 0; index < line; index += 1) offset += lines[index].length + 1
  const column = Math.min(Math.max(target.column, 0), lines[line].length)
  return offset + column
}

export interface SymbolHit {
  /** 全文里的字符偏移 */
  offset: number
  line: number
  column: number
}

const IDENT_CHAR = /[A-Za-z0-9_]/

/** 光标处的标识符（找不到 ⇒ null） */
export function identifierAt(text: string, caret: number): { name: string; start: number } | null {
  const at = Math.min(Math.max(caret, 0), text.length)
  let start = at
  while (start > 0 && IDENT_CHAR.test(text[start - 1])) start -= 1
  let end = at
  while (end < text.length && IDENT_CHAR.test(text[end])) end += 1
  if (end <= start) return null
  return { name: text.slice(start, end), start }
}

/**
 * FR-EDIT-58 定义候选（词法级）：同文件里以该标识符**开头一行的声明形状**（`func|fn|def|let|const|var|type|class|interface`）。
 * 找不到 ⇒ 空数组（界面据此显示「本文件没有定义」而不是静默）。
 */
export function definitionSites(text: string, name: string): SymbolHit[] {
  const declare = new RegExp(`^\\s*(?:export\\s+)?(?:pub\\s+)?(?:func|fn|def|let|const|var|type|class|interface|struct|enum)\\s+${name}\\b`)
  const hits: SymbolHit[] = []
  text.split('\n').forEach((line, index) => {
    if (!declare.test(line)) return
    const column = line.indexOf(name)
    if (column < 0) return
    hits.push({ offset: 0, line: index, column })
  })
  // 偏移按行号回算，避免两处各算一遍
  return hits.map((hit) => ({ ...hit, offset: offsetOfJump(text, { line: hit.line, column: hit.column }) }))
}
