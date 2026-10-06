// 标题栏搜索栏宽度策略 —— 行为判据（内测 甲1：「不是全屏时搜索框遮住标题」）
//
// 守的是两条不变量（契约层 `Core/TitleBarSearchLayout.swift` 同口径）：
//   ① 标题永远完整可见（任何窗口宽度下搜索栏都不侵入标题带）；
//   ② 不挤成一条缝（可用宽度不够就**收成 0**，不做"宽 40px 的搜索框"）。

import { describe, expect, it } from 'vitest'
import {
  availableWidth,
  estimateTitleWidth,
  fitsWithoutCoveringTitle,
  IDEAL_SEARCH_WIDTH,
  LEADING_INSET,
  MINIMUM_SEARCH_WIDTH,
  searchFieldWidth,
  TITLE_GAP,
  TITLE_CHAR_UNIT_PX,
} from './titleBarSearch'

const TITLE = 'Doyah Studio - 工作区'
const titleWidth = estimateTitleWidth(TITLE)

describe('标题栏搜索栏宽度', () => {
  it('宽窗口：给理想宽度（不是无限宽）', () => {
    expect(searchFieldWidth(2400, titleWidth)).toBe(IDEAL_SEARCH_WIDTH)
  })

  it('窄窗口：按可用宽度收缩，绝不超过可用宽度', () => {
    const width = 900
    const available = availableWidth(width, titleWidth)
    const field = searchFieldWidth(width, titleWidth)
    expect(field).toBeLessThan(IDEAL_SEARCH_WIDTH)
    expect(field).toBeLessThanOrEqual(available)
    expect(field).toBeGreaterThan(0)
  })

  it('**放不下就收成 0**（不做既不显示标题、也不能用的窄缝）', () => {
    // 可用宽度**明确不够**最小宽度（构造时留出余量，避免正好落在 180 的边界上）
    const band = LEADING_INSET + titleWidth + TITLE_GAP
    const width = 2 * band + MINIMUM_SEARCH_WIDTH - 40
    expect(availableWidth(width, titleWidth)).toBe(MINIMUM_SEARCH_WIDTH - 40)
    expect(searchFieldWidth(width, titleWidth)).toBe(0)
    // 刚好够最小宽度 ⇒ 给最小宽度（不缩到更窄，也不跳成理想宽度）
    const exact = 2 * band + MINIMUM_SEARCH_WIDTH
    expect(searchFieldWidth(exact, titleWidth)).toBe(MINIMUM_SEARCH_WIDTH)
    // 极窄窗口当然也是 0
    expect(searchFieldWidth(200, titleWidth)).toBe(0)
    expect(searchFieldWidth(0, titleWidth)).toBe(0)
  })

  it('不变量 ①：任何宽度下给的宽度都不压标题带（机械形式）', () => {
    for (let width = 0; width <= 3000; width += 17) {
      const field = searchFieldWidth(width, titleWidth)
      expect(fitsWithoutCoveringTitle(width, titleWidth, field)).toBe(true)
    }
  })

  it('判据能判红：写死 320 的旧口径在窄窗口上必须不合格', () => {
    // 这正是内测那条问题的机械化 —— 旧口径不看窗口宽度
    expect(fitsWithoutCoveringTitle(700, titleWidth, 320)).toBe(false)
    // 宽窗口上它倒是没问题（所以只看宽窗口测不出来）
    expect(fitsWithoutCoveringTitle(2400, titleWidth, 320)).toBe(true)
  })

  it('非有限值 / 负标题宽都给安全答案（不猜、不取绝对值）', () => {
    expect(availableWidth(Number.NaN, titleWidth)).toBe(0)
    expect(availableWidth(1000, Number.NaN)).toBe(0)
    expect(availableWidth(1000, -50)).toBe(availableWidth(1000, 0))
    expect(fitsWithoutCoveringTitle(1000, titleWidth, Number.NaN)).toBe(false)
    expect(fitsWithoutCoveringTitle(1000, titleWidth, -5)).toBe(true)
  })

  it('标题越宽、留给搜索栏的越少（两者不会同时变大）', () => {
    const narrowTitle = estimateTitleWidth('Doyah Studio')
    expect(narrowTitle).toBeLessThan(titleWidth)
    expect(availableWidth(1200, titleWidth)).toBeLessThan(availableWidth(1200, narrowTitle))
  })

  it('标题宽度估算：中文按两倍宽、英文按一倍', () => {
    expect(estimateTitleWidth('工作区')).toBeGreaterThan(estimateTitleWidth('abc'))
    expect(estimateTitleWidth('')).toBe(0)
  })
})


// ── 与领域层同一套算法（收口审计点出的"同一件事两处实现"）──────────────────────────
//
// 背景：本文件（界面侧）与 `Db/src/title_bar_search.rs`（领域层）**各有一份**同一算法。
// 界面侧必须留一份 —— resize 时要**同步**算，不能每次去问 Rust。所以做法不是"删掉一份"，
// 而是**让两份互相钉住**：下面这例把两组常量与几何模型对齐；Rust 侧另有 9 例
// （含**逐宽度扫描**的两条不变量）守着同一套口径。
//
// 谁把两处改成不一样的数，这里就红。
describe('与领域层 title_bar_search.rs 的口径对齐', () => {
  it('两组常量必须同值（改一处就红）', () => {
    // 领域层：IDEAL_WIDTH / MIN_WIDTH / TITLE_GAP / LEADING_INSET / TITLE_CHAR_UNIT_PX
    // 界面侧：IDEAL_SEARCH_WIDTH / MINIMUM_SEARCH_WIDTH / TITLE_GAP / LEADING_INSET / TITLE_CHAR_UNIT_PX
    expect(IDEAL_SEARCH_WIDTH).toBe(360)
    expect(MINIMUM_SEARCH_WIDTH).toBe(180)
    expect(TITLE_GAP).toBe(24)
    expect(LEADING_INSET).toBe(90)
    expect(TITLE_CHAR_UNIT_PX).toBe(9)
  })

  it('几何模型同一条：可用宽 = 窗口宽 − 2 ×（左端固定 + 标题宽 + 空档）', () => {
    // 手算一遍与函数比（这就是两侧共用的那条式子）
    const windowWidth = 1200
    const titleWidth = 200
    const expected = windowWidth - 2 * (LEADING_INSET + titleWidth + TITLE_GAP)
    expect(availableWidth(windowWidth, titleWidth)).toBe(expected)
    // 窄到放不下 ⇒ 收成 0（不变量 ②）
    expect(searchFieldWidth(2 * (LEADING_INSET + titleWidth + TITLE_GAP) + 179, titleWidth)).toBe(0)
    // 宽到有余 ⇒ 给理想宽
    expect(searchFieldWidth(4000, titleWidth)).toBe(IDEAL_SEARCH_WIDTH)
  })

  it('标题估宽与领域层同口径（中文按两单位）', () => {
    expect(estimateTitleWidth('abc')).toBe(3 * TITLE_CHAR_UNIT_PX)
    expect(estimateTitleWidth('工作区')).toBe(3 * 2 * TITLE_CHAR_UNIT_PX)
  })
})
