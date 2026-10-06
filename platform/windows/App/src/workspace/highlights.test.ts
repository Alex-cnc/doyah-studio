// 命中高亮 —— 行为判据（2.4 那一半：跳到命中行，并把命中内容标出来）
//
// 守的三件事：
//   ① **口径与检索同源**（大小写 + 变音符号不敏感）—— 否则会出现"搜得到但不高亮"；
//   ② 高亮区间落到**原文**上不错位（归一可能改变长度，映射必须带来源）；
//   ③ 一行里**所有**出现都标，且相邻命中不重复标。

import { describe, expect, it } from 'vitest'
import { foldChar, highlightPieces, matchRanges, normalizeQuery } from './highlights'

describe('归一化与检索同口径', () => {
  it('小写 + 去首尾空白 + 变音折叠', () => {
    expect(normalizeQuery('  AGENT  ')).toBe('agent')
    expect(normalizeQuery('CAFÉ')).toBe('cafe')
    expect(normalizeQuery('Ünïcödé')).toBe('unicode')
    expect(foldChar('é')).toBe('e')
    expect(foldChar('中')).toBe('中')
  })
})

describe('行内命中区间', () => {
  it('大小写不敏感，且所有出现都标出来', () => {
    const ranges = matchRanges('agent AGENT Agent', 'agent')
    expect(ranges).toEqual([
      { start: 0, end: 5 },
      { start: 6, end: 11 },
      { start: 12, end: 17 },
    ])
  })

  it('变音符号不敏感（打不出重音也标得出来）', () => {
    const ranges = matchRanges('café CAFE', 'cafe')
    expect(ranges).toEqual([
      { start: 0, end: 4 },
      { start: 5, end: 9 },
    ])
  })

  it('**中文**（一字一字符）与重叠的边界', () => {
    // 「格式化 SQL」里找 `格式`
    expect(matchRanges('格式化 SQL', '格式')).toEqual([{ start: 0, end: 2 }])
    // 找 `化 S`（跨中文与英文）：`格(0) 式(1) 化(2) 空格(3) S(4)` ⇒ 区间 [2,5)
    // （我第一版写 1..4，**又**把下标数错一位 —— 实现是对的，是用例错）
    expect(matchRanges('格式化 SQL', '化 S')).toEqual([{ start: 2, end: 5 }])
    // 找不到 / 空查询 ⇒ 不乱标
    expect(matchRanges('abc', 'zzz')).toEqual([])
    expect(matchRanges('abc', '   ')).toEqual([])
    expect(matchRanges('', 'a')).toEqual([])
  })

  it('相邻命中不重复标（**同一段不标两次**）', () => {
    // `aa` 在 `aaaa` 里：非重叠地标两段，而不是三段重叠的
    const ranges = matchRanges('aaaa', 'aa')
    expect(ranges).toEqual([
      { start: 0, end: 2 },
      { start: 2, end: 4 },
    ])
  })

  it('归一改变长度时映射仍落到原文（不错位）', () => {
    // `İ`（带点大写 I）小写是两码点，折叠后来源要正确
    const line = 'İstanbul'
    const ranges = matchRanges(line, 'stanbul')
    expect(ranges.length).toBe(1)
    // 区间必须落在原文的合法字符范围内，且切出来的原文包含 `stanbul`
    const chars = [...line]
    const slice = chars.slice(ranges[0].start, ranges[0].end).join('')
    expect(slice).toContain('stanbul')
    expect(ranges[0].end).toBeLessThanOrEqual(chars.length)
  })
})

describe('切片段（界面直接画）', () => {
  it('首尾相接覆盖整行，亮的部分就是命中', () => {
    const pieces = highlightPieces('let agent = 1', 'agent')
    expect(pieces.map((p) => p.text).join('')).toBe('let agent = 1')
    const hit = pieces.filter((p) => p.hit)
    expect(hit).toHaveLength(1)
    expect(hit[0].text).toBe('agent')
  })

  it('没有命中时整行一段不亮；空行给空数组', () => {
    expect(highlightPieces('nothing', 'zzz')).toEqual([{ text: 'nothing', hit: false }])
    expect(highlightPieces('', 'a')).toEqual([])
  })

  it('多处命中按顺序给出（顺序即阅读顺序）', () => {
    const pieces = highlightPieces('a X b X c', 'x')
    expect(pieces.filter((p) => p.hit).map((p) => p.text)).toEqual(['X', 'X'])
    expect(pieces.map((p) => p.text).join('')).toBe('a X b X c')
  })
})
