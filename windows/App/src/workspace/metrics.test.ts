// 列宽实量 —— 行为判据（alpha 2.2）
//
// 守的两件事：
//   ① **量不出来要如实标注**（`measured: false` + 保守默认值），不假装量过；
//   ② **中文按两格算**（全角字符在等宽字体里占两个字符宽）—— 只数字符数会让一整列中文
//      少算一半宽度，内容被切掉比"宽一点"难看得多。

import { describe, expect, it } from 'vitest'
import {
  charWidthFrom,
  codeWidth,
  codeWidthByDisplayColumns,
  displayColumns,
  FALLBACK_CHAR_WIDTH,
  GUTTER_MAX_WIDTH,
  GUTTER_PADDING,
  GUTTER_MIN_WIDTH,
  gutterWidth,
} from './metrics'

describe('字符宽实量', () => {
  it('量到了就如实说量到了', () => {
    // 量 16 个字符给 128px ⇒ 每个 8px
    const metrics = charWidthFrom(() => 128)
    expect(metrics.charWidth).toBe(8)
    expect(metrics.measured).toBe(true)
  })

  it('**量不出来退回保守默认值并标注**（不假装配了字体）', () => {
    // 抛异常
    expect(charWidthFrom(() => { throw new Error('no canvas') })).toEqual({
      charWidth: FALLBACK_CHAR_WIDTH,
      measured: false,
    })
    // 返回 0 / 负数 / NaN 都不算量到了
    expect(charWidthFrom(() => 0).measured).toBe(false)
    expect(charWidthFrom(() => -5).measured).toBe(false)
    expect(charWidthFrom(() => Number.NaN).measured).toBe(false)
    expect(charWidthFrom(() => Number.POSITIVE_INFINITY).measured).toBe(false)
  })
})

describe('行号列宽度', () => {
  const metrics = { charWidth: 8, measured: true }

  it('按位数算，并夹在上下限之间', () => {
    // 1 位：8 + 16 = 24 ⇒ 触到下限 32
    expect(gutterWidth(1, metrics)).toBe(GUTTER_MIN_WIDTH)
    // 5 位：40 + 16 = 56
    expect(gutterWidth(5, metrics)).toBe(56)
    // 位数极大 ⇒ 触到上限（不许占掉半屏）
    expect(gutterWidth(100, metrics)).toBe(GUTTER_MAX_WIDTH)
  })

  it('位数非法也给安全答案', () => {
    expect(gutterWidth(0, metrics)).toBe(GUTTER_MIN_WIDTH)
    expect(gutterWidth(-3, metrics)).toBe(GUTTER_MIN_WIDTH)
    expect(gutterWidth(2.7, metrics)).toBe(gutterWidth(2, metrics))
  })

  it('不同字体宽度会给不同结果（这就是"实量"的意义）', () => {
    const wide = { charWidth: 12, measured: true }
    expect(gutterWidth(5, wide)).toBeGreaterThan(gutterWidth(5, metrics))
  })
})

describe('代码列宽度', () => {
  const metrics = { charWidth: 8, measured: true }

  it('按最长行算', () => {
    const lines = ['short', 'a much longer line here', 'mid line']
    // 23 列 × 8 + 16 = 200
    expect(codeWidthByDisplayColumns(lines, metrics)).toBe(23 * 8 + 16)
  })

  it('**中文按两格**（只数字符数会少算一半）', () => {
    expect(displayColumns('中文')).toBe(4)
    expect(displayColumns('abc')).toBe(3)
    expect(displayColumns('中a')).toBe(3)
    // 一整列中文：按字符数是 4、按显示列是 8 ⇒ 宽度翻倍
    const chinese = ['中文内容']
    const byChars = codeWidth(chinese, metrics)!
    const byColumns = codeWidthByDisplayColumns(chinese, metrics)!
    expect(byColumns).toBeGreaterThan(byChars)
    expect(byColumns - GUTTER_PADDING).toBe(8 * 8)
  })

  it('比可视区窄就**不给宽度**（避免永远拉不动的横向滚动条）', () => {
    const lines = ['short']
    expect(codeWidthByDisplayColumns(lines, metrics, { availableWidth: 500 })).toBeNull()
    // 超出可视区才给
    const long = ['x'.repeat(200)]
    expect(codeWidthByDisplayColumns(long, metrics, { availableWidth: 500 })).not.toBeNull()
  })

  it('上限能夹住超长行（不然一行就把界面拉飞）', () => {
    const long = ['x'.repeat(10_000)]
    const width = codeWidthByDisplayColumns(long, metrics, { maxWidth: 2000 })
    expect(width).toBe(2000)
  })

  it('空内容与空行都给安全答案', () => {
    expect(codeWidth([], metrics)).toBeNull()
    expect(codeWidthByDisplayColumns([], metrics)).toBeNull()
    // 全是空行 ⇒ 只有空档那么宽，但不为 0
    expect(codeWidthByDisplayColumns(['', ''], metrics)).toBeGreaterThan(0)
  })
})
