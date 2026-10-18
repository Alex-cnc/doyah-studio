// 查找 / 替换（FR-EDIT-18）—— 纯逻辑，界面只收集输入与显示结论。
//
// 三条口径（都是踩过才会想到的）：
// ① **字面量，不认正则**：用户查 `count(*)` 不该被判成语法错，替换串里的 `$&` / `$1` 也**当普通字符**
//    （用 `String.prototype.replace` 那个语义会让 `$&` 悄悄变成"匹配到的原文"，用户完全看不出来）；
// ② **位置是 UTF-16 码元下标**（JS 字符串原生口径）—— textarea 的 `selectionStart` 与 `String.slice`
//    都是这个口径，中文 / 表情上不会错位；
// ③ **非重叠**：`aaa` 里查 `aa` 命中 1 处（下标 0），不是 2 处 —— 与所有编辑器的「查找」一致，
//    重叠匹配还会让"替换全部"把同一段改两遍。
//
// 区分大小写两档：不确定时**按切片比较**而不是先整体 `toLowerCase()` 再找下标 ——
// 有些字符小写化会改长度（`İ` → `i̇`），整体小写会让下标整体漂掉，于是"替换"改到隔壁字符上。

/** 查找选项：目前只有一档（区分大小写），负数面另测。 */
export interface FindOptions {
  /** 区分大小写（缺省 = 不区分：SQL 里大小写随手打是常态） */
  caseSensitive?: boolean
}

/** 一段命中：只给起点，长度永远等于查询串长度（字面量匹配）。 */
export type MatchStart = number

/**
 * 找出全部命中的起点（升序、非重叠）。
 *
 * 空查询 / 纯空白 **不出匹配**（查空串命中"每一处"是数学上对、用起来全是噪音）。
 */
export function findMatches(text: string, query: string, options: FindOptions = {}): MatchStart[] {
  if (!query) return []
  const haystack = text
  const needle = options.caseSensitive ? query : query.toLowerCase()
  const out: MatchStart[] = []
  const step = query.length
  let i = 0
  while (i + step <= haystack.length) {
    const slice = haystack.slice(i, i + step)
    const probe = options.caseSensitive ? slice : slice.toLowerCase()
    if (probe === needle) {
      out.push(i)
      i += step // 非重叠
    } else {
      i += 1
    }
  }
  return out
}

/**
 * 从光标处挑"当前该看的那一处"：第一条起点 ≥ 光标的命中；都过了就回到第一处（绕回）。
 * 没有命中返回 -1。
 */
export function matchIndexAt(matches: MatchStart[], caret: number): number {
  if (!matches.length) return -1
  const at = matches.findIndex((start) => start >= caret)
  return at === -1 ? 0 : at
}

/** 上一处 / 下一处（环绕）。`current < 0` 时按方向落到首 / 末；一条都没有返回 -1。 */
export function stepMatch(count: number, current: number, direction: 1 | -1): number {
  if (count <= 0) return -1
  if (current < 0) return direction === 1 ? 0 : count - 1
  return (current + direction + count) % count
}

/** 一次替换的结果：新全文 + 新光标（落在替换串之后）+ 替了几处。 */
export interface ReplaceResult {
  text: string
  /** 替换后光标应落在哪（替换串末尾）；没替成时等于调用方给的 `start` */
  caret: number
  /** 实际替了几处（0 = 什么都没动） */
  count: number
}

/**
 * 替换**某一处**（`start` 必须是调用方上一次 `findMatches` 给的起点）。
 *
 * 起点处已经不是那段文字（文本在两次调用之间被改过）⇒ **一个字都不改**、`count: 0`。
 * 这条比"尽力猜个最近的位置改一下"重要：猜错就是静默改坏别人的 SQL。
 */
export function replaceOne(
  text: string,
  query: string,
  replacement: string,
  start: number,
  options: FindOptions = {},
): ReplaceResult {
  if (!query || start < 0 || start + query.length > text.length) {
    return { text, caret: Math.max(start, 0), count: 0 }
  }
  const slice = text.slice(start, start + query.length)
  const probe = options.caseSensitive ? slice : slice.toLowerCase()
  const needle = options.caseSensitive ? query : query.toLowerCase()
  if (probe !== needle) return { text, caret: Math.max(start, 0), count: 0 }
  const next = text.slice(0, start) + replacement + text.slice(start + query.length)
  return { text: next, caret: start + replacement.length, count: 1 }
}

/**
 * 替换全部。
 *
 * 替换串是**字面量**（见文件头 ①）：`$&` 在这里就是一个美元符号加和号。
 * 替换串里含查询串也没关系 —— 从原文一次扫描拼出新串，不在结果上再扫一遍（不会自己喂自己）。
 */
export function replaceAll(
  text: string,
  query: string,
  replacement: string,
  options: FindOptions = {},
): ReplaceResult {
  const starts = findMatches(text, query, options)
  if (!starts.length) return { text, caret: 0, count: 0 }
  let out = ''
  let cursor = 0
  for (const start of starts) {
    out += text.slice(cursor, start) + replacement
    cursor = start + query.length
  }
  out += text.slice(cursor)
  return { text: out, caret: out.length, count: starts.length }
}

/** 匹配读数：给界面一句能直接显示的话（0 处时也必须说清，不许留空白）。 */
export interface MatchReadout {
  /** 0 = 没有匹配 */
  total: number
  /** 1 基的"第几处"；没有匹配时是 0 */
  position: number
  /** `current < 0`（查询串还没填 / 没匹配） */
  empty: boolean
}

export function readout(matches: MatchStart[], current: number): MatchReadout {
  const total = matches.length
  if (!total) return { total: 0, position: 0, empty: true }
  const at = current < 0 ? 0 : Math.min(current, total - 1)
  return { total, position: at + 1, empty: false }
}
