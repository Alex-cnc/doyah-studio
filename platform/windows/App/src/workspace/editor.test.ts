// 编辑面纯逻辑 —— 行为判据（alpha 2.2）
//
// 守的三件"错了很难查"的事：
//   ① **字节偏移 ≠ 字符下标**：含中文 / emoji 的行按字节当字符用会整体错开；
//   ② 片段必须**首尾相接覆盖整行**（否则视图要自己猜空隙，迟早漏字）；
//   ③ 越界的 span **夹进行内**（宁可少画色，也不许画到行外）。

import { describe, expect, it } from 'vitest'
import {
  byteToCharIndex,
  dominantEndingLabel,
  endingLabel,
  lineNumberText,
  segmentsForLine,
  sliceSegments,
} from './editor'

describe('字节偏移 → 行内字符下标', () => {
  it('纯 ASCII 时两者一致', () => {
    expect(byteToCharIndex('abcdef', 0)).toBe(0)
    expect(byteToCharIndex('abcdef', 3)).toBe(3)
    expect(byteToCharIndex('abcdef', 6)).toBe(6)
  })

  it('**中文与 emoji 会差开**（这正是要显式换算的原因）', () => {
    // "中" 3 字节、"文" 3 字节、emoji 4 字节；但字符数各是 1
    expect(byteToCharIndex('中abc', 3)).toBe(1)
    expect(byteToCharIndex('中文abc', 6)).toBe(2)
    expect(byteToCharIndex('😀abc', 4)).toBe(1)
  })

  it('边界都给安全答案（负偏移 / 超长）', () => {
    expect(byteToCharIndex('abc', -5)).toBe(0)
    expect(byteToCharIndex('abc', 999)).toBe(3)
    expect(byteToCharIndex('', 10)).toBe(0)
  })
})

describe('每行的片段：首尾相接覆盖整行', () => {
  it('高亮片段之间补上普通文本，且不多不少盖满整行', () => {
    // 行内容：`let x = 1;`（10 字符）；高亮 `let`（0..3）与 `1`（8..9）
    const line = 'let x = 1;'
    const segments = segmentsForLine(line, 0, line.length, [
      { start: 0, end: 3, kind: 'keyword' },
      { start: 8, end: 9, kind: 'number' },
    ])
    expect(segments[0]).toEqual({ start: 0, end: 3, kind: 'keyword' })
    expect(segments[segments.length - 1].end).toBe(line.length)
    // 相邻片段必须接上（不重叠、不留缝）
    for (let i = 1; i < segments.length; i += 1) {
      expect(segments[i].start).toBe(segments[i - 1].end)
    }
    expect(segments.some((s) => s.kind === 'plain')).toBe(true)
  })

  it('切出来的文本拼回去等于整行（一个字符都不丢）', () => {
    const line = 'const 名 = "值"; // 注'
    const segments = segmentsForLine(line, 0, 40, [
      { start: 0, end: 5, kind: 'keyword' },
      { start: 11, end: 17, kind: 'str' },
    ])
    const pieces = sliceSegments(line, segments)
    expect(pieces.map((p) => p.text).join('')).toBe(line)
    // 有中文时也要一字不差
    const withChinese = 'let s = "中文😀";'
    const segs = segmentsForLine(withChinese, 0, 40, [{ start: 8, end: 20, kind: 'str' }])
    expect(sliceSegments(withChinese, segs).map((p) => p.text).join('')).toBe(withChinese)
  })

  it('span 跨行时只取相交部分（行内偏移正确）', () => {
    // 一份原文里第 2 行从字节 7 开始（"abc\r\n" = 5 字节，第二行 "defgh" 起于 5）
    const line = 'defgh'
    const segments = segmentsForLine(line, 5, 10, [{ start: 0, end: 8, kind: 'comment' }])
    // 落到本行的部分是字节 5..8 ⇒ 行内字符 0..3
    const highlighted = segments.filter((s) => s.kind === 'comment')
    expect(highlighted).toEqual([{ start: 0, end: 3, kind: 'comment' }])
    expect(segments[segments.length - 1].end).toBe(5)
  })

  it('越界的 span 被夹进行内（不画到行外）', () => {
    const line = 'abc'
    const segments = segmentsForLine(line, 0, 3, [
      { start: 0, end: 999, kind: 'str' },
      { start: 100, end: 200, kind: 'comment' },
    ])
    for (const segment of segments) {
      expect(segment.start).toBeGreaterThanOrEqual(0)
      expect(segment.end).toBeLessThanOrEqual(line.length)
    }
    // 完全在行外的那个 span 不产生片段
    expect(segments.filter((s) => s.kind === 'comment')).toHaveLength(0)
  })

  it('空行 / 没有 span 都安全', () => {
    expect(segmentsForLine('', 0, 0, [])).toEqual([])
    const plain = segmentsForLine('abc', 0, 3, [])
    expect(plain).toEqual([{ start: 0, end: 3, kind: 'plain' }])
  })
})

describe('换行符与行号的人话名', () => {
  it('六种终止符都有名字，最后一行如实说"无"', () => {
    expect(endingLabel('\n')).toBe('LF')
    expect(endingLabel('\r\n')).toBe('CRLF')
    expect(endingLabel('\r')).toBe('CR')
    expect(endingLabel('\u2028')).toBe('LS')
    expect(endingLabel('\u2029')).toBe('PS')
    expect(endingLabel('\u0085')).toBe('NEL')
    expect(endingLabel(null)).toContain('无')
  })

  it('主换行符键映射完整，未知键不编一个假名字', () => {
    expect(dominantEndingLabel('lf')).toBe('LF')
    expect(dominantEndingLabel('crlf')).toBe('CRLF')
    expect(dominantEndingLabel(null)).toContain('未定')
    expect(dominantEndingLabel('weird')).toContain('未定')
  })

  it('行号按列宽右对齐（第 100 行不会把数字挤掉）', () => {
    expect(lineNumberText(0, 1)).toBe('1')
    expect(lineNumberText(9, 2)).toBe('10')
    expect(lineNumberText(99, 3)).toBe('100')
    // 补齐用空格，长度等于列宽
    expect(lineNumberText(0, 3)).toHaveLength(3)
    expect(lineNumberText(4, 1)).toHaveLength(1)
  })
})
