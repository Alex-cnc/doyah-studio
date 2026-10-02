// 编辑面（2.x）的**命中高亮**：在行内找出与检索词匹配的区间
//
// 为什么要单独一层：检索的匹配口径（**大小写 + 变音符号不敏感**）在 Rust 领域层
// （`Db/src/search.rs` 的 `normalize` / `matches`）。**高亮必须用同一套口径** ——
// 否则会出现"搜得到但不高亮"或"高亮了但搜不到"，而这类分歧在界面上看起来只是"偶尔不亮"，
// 极难查。所以这一层复刻同一套归一规则，并**每个字都带上它对应原文的哪个字符**
// （折叠会改变长度：`é` 折叠成 `e` 看似一对一，但 `ß` 之类不一定），
// 保证高亮区间落到**原文**上不会错位。
//
// 三条口径：
//   ① 高亮区间以**原文的字符下标**给出（不是归一后的下标）；
//   ② 一行里**所有**出现都标出来（不只第一个）；
//   ③ 空查询 / 找不到 ⇒ 空数组（**不乱标**）。

/** 变音折叠表（与 Rust 侧 `fold_diacritic` 同一张表；两边必须一致）。 */
const FOLD_MAP: Record<string, string> = {
  á: 'a', à: 'a', â: 'a', ä: 'a', ã: 'a', å: 'a', ā: 'a', ă: 'a', ą: 'a',
  ç: 'c', ć: 'c', č: 'c',
  ď: 'd', đ: 'd',
  é: 'e', è: 'e', ê: 'e', ë: 'e', ě: 'e', ē: 'e', ė: 'e', ę: 'e',
  ğ: 'g', ĝ: 'g', ģ: 'g',
  í: 'i', ì: 'i', î: 'i', ï: 'i', ī: 'i', į: 'i', ı: 'i',
  ł: 'l', ĺ: 'l', ľ: 'l',
  ñ: 'n', ń: 'n', ň: 'n',
  ó: 'o', ò: 'o', ô: 'o', ö: 'o', õ: 'o', ø: 'o', ō: 'o', ő: 'o',
  ř: 'r', ŕ: 'r',
  ś: 's', š: 's', ş: 's', ș: 's',
  ť: 't', ţ: 't', ț: 't',
  ú: 'u', ù: 'u', û: 'u', ü: 'u', ū: 'u', ů: 'u', ű: 'u', ų: 'u',
  ý: 'y', ÿ: 'y',
  ź: 'z', ż: 'z', ž: 'z',
}

/** 单字符折叠（与 Rust 侧同口径）。 */
export function foldChar(ch: string): string {
  return FOLD_MAP[ch] ?? ch
}

/**
 * 把查询词归一成比较用的形状（与 Rust 侧 `normalize` 同口径：trim + 小写 + 折叠）。
 */
export function normalizeQuery(query: string): string {
  return [...query.trim().toLowerCase()].map(foldChar).join('')
}

/** 一段命中的区间（**原文的字符下标**，`[start, end)`）。 */
export interface MatchRange {
  start: number
  end: number
}

/**
 * 在一行里找出**所有**命中区间。
 *
 * 做法：把整行按字符归一（同时记住每个归一后字符来自原文的第几个字符），
 * 在归一后的串上找 needle，再把下标映射回原文。
 */
export function matchRanges(line: string, query: string): MatchRange[] {
  const needle = normalizeQuery(query)
  if (needle.length === 0 || line.length === 0) return []

  const original = [...line]
  const foldedChars: string[] = []
  const sourceIndex: number[] = []
  original.forEach((ch, index) => {
    // 折叠后可能是多个字符（理论上），逐个记来源
    for (const piece of [...ch.toLowerCase()].map(foldChar)) {
      foldedChars.push(piece)
      sourceIndex.push(index)
    }
  })
  const folded = foldedChars.join('')
  if (folded.length < needle.length) return []

  const ranges: MatchRange[] = []
  let cursor = 0
  while (cursor <= folded.length - needle.length) {
    const at = folded.indexOf(needle, cursor)
    if (at < 0) break
    const start = sourceIndex[at]
    const end = sourceIndex[at + needle.length - 1] + 1
    // 相邻命中不重叠（**同一段不重复标**）
    const last = ranges[ranges.length - 1]
    if (!last || start >= last.end) {
      ranges.push({ start, end })
    }
    cursor = at + needle.length
  }
  return ranges
}

/**
 * 把一行按命中区间切成"亮 / 不亮"的片段（**首尾相接覆盖整行**）。
 *
 * 与 `matchRanges` 分开是为了界面能直接用：给它一行与查询词，拿到可以 `v-for` 画的片段。
 */
export function highlightPieces(
  line: string,
  query: string,
): { text: string; hit: boolean }[] {
  const ranges = matchRanges(line, query)
  if (ranges.length === 0) {
    return line.length === 0 ? [] : [{ text: line, hit: false }]
  }
  const chars = [...line]
  const pieces: { text: string; hit: boolean }[] = []
  let cursor = 0
  for (const range of ranges) {
    if (range.start > cursor) {
      pieces.push({ text: chars.slice(cursor, range.start).join(''), hit: false })
    }
    pieces.push({ text: chars.slice(range.start, range.end).join(''), hit: true })
    cursor = range.end
  }
  if (cursor < chars.length) {
    pieces.push({ text: chars.slice(cursor).join(''), hit: false })
  }
  return pieces
}
