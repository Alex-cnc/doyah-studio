// 工作区 Markdown 手感（FR-EDIT-47 列表续行 / FR-EDIT-48 任务框勾选 ⌘L）—— 行为判据
//
// 口径：
//   · 只认行首的**块级标记**（无序 `- * +`、有序 `1.` / `1)`、任务框 `- [ ]` / `- [x]`），
//     引号 / 代码块围栏里的一律不管（判断只看行本身，不猜上下文 —— 上下文层属编辑器状态机）。
//   · 续行**保持缩进**：缩进 + 新标记；空条目（只有标记没有内容）⇒ 返回 `null`（调用方去掉标记 = 退出列表）。
//   · 任务框勾选只翻转 `[ ]` ⇄ `[x]`，**不动**缩进、项目符号与 `[x]` 之后的文字。

export interface ListMarker {
  /** 行首缩进（原样保留） */
  indent: string
  /** 项目符号：`-` / `*` / `+` / `1.` / `1)`（有序号时带序号） */
  bullet: string
  /** 序号（仅有序列表；无序为 `null`） */
  ordinal: number | null
  /** 标记之后到正文之间的空白（通常是 ' '） */
  gap: string
  /** 正文（标记之后的部分） */
  content: string
  /** 是否任务框条目；`checked` 只在任务框时有意义 */
  task: boolean
  checked: boolean
}

const LIST_RE = /^(\s*)([-*+]|\d+[.)])(\s+)(\[[ xX]\]\s+)?(.*)$/

/** 解析一行是否为列表条目；不是 ⇒ `null` */
export function parseListMarker(line: string): ListMarker | null {
  const match = LIST_RE.exec(line)
  if (!match) return null
  const [, indent, bullet, gap, checkbox, content] = match
  const ordinal = /^\d+/.test(bullet) ? Number.parseInt(bullet, 10) : null
  const task = Boolean(checkbox)
  const checked = task ? /\[[xX]\]/.test(checkbox as string) : false
  return { indent, bullet, ordinal, gap, content, task, checked }
}

/**
 * FR-EDIT-47 回车续行：返回**下一行要写在行首的内容**（调用方把它接在 `\n` 之后）。
 *
 *   · 有序列表 ⇒ 序号 +1，且**保持**调用方给的分隔符（`.` 或 `)`）；
 *   · 无序 / 任务框 ⇒ 同一个项目符号（任务框回到未勾选）；
 *   · 空条目（`- ` 后面没字，或任务框只有 `[ ]`）⇒ `null`（调用方去掉标记 = 退出列表）。
 */
export function nextListPrefix(line: string): string | null {
  const marker = parseListMarker(line)
  if (!marker) return null
  if (marker.content.trim().length === 0) return null
  const bullet = marker.ordinal === null
    ? marker.bullet
    : `${marker.ordinal + 1}${marker.bullet.endsWith(')') ? ')' : '.'}`
  const checkbox = marker.task ? '[ ] ' : ''
  return `${marker.indent}${bullet}${marker.gap}${checkbox}`
}

/**
 * FR-EDIT-48 任务框勾选翻转（⌘L）。
 *
 *   · 任务框条目 ⇒ `[ ]` ⇄ `[x]`；其余一字不动；
 *   · 不是列表条目 ⇒ 原样返回（不硬塞一个任务框 —— 那是另一条需求）。
 */
export function toggleTaskCheckbox(line: string): string {
  const marker = parseListMarker(line)
  if (!marker || !marker.task) return line
  const head = `${marker.indent}${marker.bullet}${marker.gap}`
  const box = marker.checked ? '[ ] ' : '[x] '
  return `${head}${box}${marker.content}`
}
