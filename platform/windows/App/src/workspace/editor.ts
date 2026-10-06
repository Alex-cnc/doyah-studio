// 编辑面（2.2）的**纯逻辑**：把领域层给的行结构与高亮分词，翻成"每行要画的片段"
//
// 为什么需要这一层：Rust 给的是**字节偏移**，而界面上的字符串下标是**UTF-16**（中文与 emoji
// 会让两者差开）。直接把字节偏移当字符下标用，含中文的行会从中间错开 —— 看起来像"上色偏了半个字"，
// 极难查。所以这里做一次**显式换算**，并且**只按行内区间**交给视图。
//
// 两条口径：
//   ① 片段必须**首尾相接、覆盖整行**（普通文本要在高亮片段之间补上，否则视图要自己猜空隙）；
//   ② 越界的 span 一律**夹进行内**（宁可少画一点色，也不许画到行外去）。

import type { CodeTokenKind } from '../ipc'

/** 一行里要画的一段：字符区间 + 类别（`plain` = 无高亮）。 */
export interface Segment {
  start: number
  end: number
  kind: CodeTokenKind | 'plain'
}

/** 一行的结构（由 Rust 侧给，这里只加"行内片段"）。 */
export interface LineInput {
  text: string
  ending: string | null
  byteStart: number
}

/** 字节偏移 → 行内**字符**下标（超出范围就夹到两端）。 */
export function byteToCharIndex(line: string, byteOffset: number): number {
  if (byteOffset <= 0) return 0
  const encoder = new TextEncoder()
  let bytes = 0
  let chars = 0
  for (const ch of line) {
    if (bytes >= byteOffset) return chars
    bytes += encoder.encode(ch).length
    chars += 1
  }
  return chars
}

/**
 * 把一行的高亮 span 归位（span 的字节偏移是**相对整份原文**的）。
 *
 * `lineByteStart` / `lineByteEnd` 由调用方从行结构里给（后端已算好每行起点）。
 */
export function segmentsForLine(
  line: string,
  lineByteStart: number,
  lineByteEnd: number,
  spans: readonly { start: number; end: number; kind: CodeTokenKind }[],
): Segment[] {
  const lineLength = [...line].length
  if (lineLength === 0) return []

  // 只取与本行相交的部分，并按行内字符区间归位
  const inside: Segment[] = []
  for (const span of spans) {
    if (span.end <= lineByteStart || span.start >= lineByteEnd) continue
    const start = byteToCharIndex(line, Math.max(span.start, lineByteStart) - lineByteStart)
    const end = byteToCharIndex(line, Math.min(span.end, lineByteEnd) - lineByteStart)
    if (end > start) inside.push({ start, end, kind: span.kind })
  }
  inside.sort((a, b) => a.start - b.start)

  // **首尾相接**：高亮片段之间补普通文本（口径 ①）
  const result: Segment[] = []
  let cursor = 0
  for (const segment of inside) {
    const start = Math.max(segment.start, cursor)
    if (start > cursor) result.push({ start: cursor, end: start, kind: 'plain' })
    const end = Math.max(segment.end, start)
    if (end > start) result.push({ start, end, kind: segment.kind })
    cursor = Math.max(cursor, end)
  }
  if (cursor < lineLength) result.push({ start: cursor, end: lineLength, kind: 'plain' })
  return result
}

/** 把一行按片段切成人能读的字符串数组（视图直接 `v-for` 画，不必自己切片）。 */
export function sliceSegments(line: string, segments: readonly Segment[]): { text: string; kind: Segment['kind'] }[] {
  const chars = [...line]
  return segments.map((segment) => ({
    text: chars.slice(segment.start, segment.end).join(''),
    kind: segment.kind,
  }))
}

/** 换行符的**人话名**（界面显示用；技术键不进语言表）。 */
export function endingLabel(ending: string | null): string {
  switch (ending) {
    case '\n':
      return 'LF'
    case '\r\n':
      return 'CRLF'
    case '\r':
      return 'CR'
    case '\u2028':
      return 'LS'
    case '\u2029':
      return 'PS'
    case '\u0085':
      return 'NEL'
    default:
      return '无（最后一行）'
  }
}

/** 主换行符的人话名（后端给的是键名）。 */
export function dominantEndingLabel(key: string | null): string {
  switch (key) {
    case 'lf':
      return 'LF'
    case 'crlf':
      return 'CRLF'
    case 'cr':
      return 'CR'
    case 'ls':
      return 'LS'
    case 'ps':
      return 'PS'
    case 'nel':
      return 'NEL'
    default:
      return '未定（单行文件）'
  }
}

/** 行号文本（右对齐由 CSS 管，这里只管数字）。 */
export function lineNumberText(index: number, gutterDigits: number): string {
  return String(index + 1).padStart(Math.max(1, gutterDigits), ' ')
}
