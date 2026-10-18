// 代码折叠（FR-EDIT-55）—— 行为判据
//
// 口径：
//   · 折叠区 = 「行尾是 `{` `(` `[` `:`」或「行尾是 `{` 之外的开括号 + 后续更深缩进的块」，
//     块的范围按**缩进**推（下一行缩进 <= 本行缩进 ⇒ 块结束）；
//   · 少于 `minLines` 行的块不产生折叠（单行 if 折叠没意义）；
//   · 围栏代码块（```）整段可折叠，且**不**参与缩进推块（围栏内的 `{` 不算块开头）；
//   · 空白行与注释行不影响推块（只看缩进比较，缩进 = 行首空白宽度，tab 记 1 档）。

export interface FoldRange {
  /** 折叠区首行（0 基，可见的那一行） */
  startLine: number
  /** 折叠区末行（含） */
  endLine: number
  /** 折叠后显示的一行文字用的占位（`{ … }` 之类由界面决定，这里只给行数） */
  hiddenLines: number
}

const OPEN_TAIL = /[{([]$/
const indentWidth = (line: string): number => {
  const match = /^[ \t]*/.exec(line)
  if (!match) return 0
  return match[0].replace(/\t/g, ' ').length
}

/**
 * 按缩进 + 围栏推折叠区。返回按 `startLine` 升序的区间；`minLines` 默认 2。
 */
export function foldRanges(text: string, minLines = 2): FoldRange[] {
  const lines = text.split('\n')
  const ranges: FoldRange[] = []
  let fence: { start: number } | null = null
  const inFence = new Set<number>()

  for (let index = 0; index < lines.length; index += 1) {
    if (/^\s*```/.test(lines[index])) {
      if (fence) {
        inFence.add(index)
        ranges.push({ startLine: fence.start, endLine: index, hiddenLines: index - fence.start - 1 })
        fence = null
      } else {
        fence = { start: index }
      }
      continue
    }
    if (fence) inFence.add(index)
  }

  for (let index = 0; index < lines.length; index += 1) {
    if (inFence.has(index)) continue
    const line = lines[index]
    if (!OPEN_TAIL.test(line.trimEnd())) continue
    const base = indentWidth(line)
    let end = index
    for (let cursor = index + 1; cursor < lines.length; cursor += 1) {
      if (lines[cursor].trim().length === 0) {
        end = cursor
        continue
      }
      if (indentWidth(lines[cursor]) <= base) {
        // 收尾行（`}` / `)` / `]` 打头）算进折叠区：折起来要能看见那个闭合符
        if (/^\s*[})\]]/.test(lines[cursor])) end = cursor
        break
      }
      end = cursor
    }
    // 折叠后至少要藏住 `minLines` 行才有意义（一行 if 块折起来只是把 `}` 藏了，纯噪声）
    if (end - index >= minLines) {
      if (!ranges.some((range) => range.startLine === index)) {
        ranges.push({ startLine: index, endLine: end, hiddenLines: end - index })
      }
    }
  }

  return ranges.sort((a, b) => a.startLine - b.startLine)
}

/**
 * 给定折叠状态（哪些 `startLine` 被折起），算出**实际可见**的行号集合（0 基）。
 * 折叠区内部的行全部不可见；折叠区的首行仍可见。
 */
export function visibleLines(text: string, ranges: FoldRange[], collapsed: Set<number>): number[] {
  const total = text.split('\n').length
  const hidden = new Set<number>()
  for (const range of ranges) {
    if (!collapsed.has(range.startLine)) continue
    for (let line = range.startLine + 1; line <= range.endLine; line += 1) hidden.add(line)
  }
  const out: number[] = []
  for (let line = 0; line < total; line += 1) if (!hidden.has(line)) out.push(line)
  return out
}
