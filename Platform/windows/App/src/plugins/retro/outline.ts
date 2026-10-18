// 周报正文的**目录锚点**（`FR-R-13-08` ①「显示设定：目录锚点」的纯函数那一半）。
//
// 为什么单独一个文件、且是纯函数：
// ① 大纲 = 「正文里的标题」的**派生**，不是第二套解析 —— 块模型只有 `Db/src/markdown.rs` 一份，
//    这里只做「挑出 heading 块 + 拼行内文字 + 给一个稳定的锚点 id」；
// ② 抽取规则要能单跑（`environment: node`）：层级怎么夹、空标题怎么办、重行怎么去重，
//    全在下面这几行里，不靠挂载测去猜。
//
// 三条口径：
// 1. **层级按源文**（1~6），越界值夹到 1~6 —— 不改写原文档的层级；
// 2. **同一行只出一条**（正文里一行出现两个 heading 块理论上不该有，但去重比让用户点两次更省事）；
// 3. 文字 = 行内 span 的**文字**拼接（粗体 / 代码这些样式不进大纲），`trim` 后可能为空 ——
//    **空标题仍然出现在大纲里**（它是正文的一节），由界面替一句「（无标题）」而不是凭空吞掉一节。

import type { MdBlock, MdDocument } from '../../ipc'

/** 大纲的一条（= 正文里的一个标题块）。 */
export interface OutlineEntry {
  /** DOM 锚点 id：正文那个标题块上写的是同一个值（见 `BlockDocument.vue`）。 */
  id: string
  /** 层级 1~6（已夹过界）。 */
  level: number
  /** 标题文字（样式已去掉；可能为空串 = 源文里就是个空标题）。 */
  text: string
  /** 起始行（1 起）：判据用它证明「点到的是这一条」。 */
  line: number
}

/** 标题块的 DOM id（正文与大纲必须用同一个函数拼，别各写一份）。 */
export function headingAnchor(line: number): string {
  return `retro-h-${line}`
}

/** 层级夹到 1~6（UA 只认这六档；0 或 9 这种坏值不该把大纲排歪）。 */
export function clampHeadingLevel(level: number): number {
  if (!Number.isFinite(level)) return 1
  const rounded = Math.trunc(level)
  if (rounded < 1) return 1
  if (rounded > 6) return 6
  return rounded
}

/** 一个标题块的文字（行内样式不进大纲）。 */
export function headingText(block: MdBlock): string {
  if (block.kind.type !== 'heading') return ''
  return block.kind.spans
    .map((span) => span.text)
    .join('')
    .trim()
}

/**
 * 抽大纲。
 *
 * `null` / 空文档 ⇒ 空数组（界面据此**不画**空面板 —— 一个「0 条」的面板只会占地方）。
 */
export function outlineOf(document: MdDocument | null | undefined): OutlineEntry[] {
  if (!document || !Array.isArray(document.blocks)) return []
  const entries: OutlineEntry[] = []
  const seen = new Set<number>()
  for (const block of document.blocks) {
    if (!block || block.kind.type !== 'heading') continue
    if (seen.has(block.line)) continue
    seen.add(block.line)
    entries.push({
      id: headingAnchor(block.line),
      level: clampHeadingLevel(block.kind.level),
      text: headingText(block),
      line: block.line,
    })
  }
  return entries
}
