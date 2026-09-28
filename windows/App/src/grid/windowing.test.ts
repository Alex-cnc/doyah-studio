import { describe, expect, it } from 'vitest'
import { windowForScroll } from './windowing'

describe('grid/windowing', () => {
  it('窗口盖住可视区并带 overscan', () => {
    // 26px 行高、可视 300px、滚到第 100 行处
    const plan = windowForScroll(100 * 26, 300, 26, 1000, 4)
    expect(plan.start).toBe(96)
    expect(plan.len).toBe(Math.ceil(300 / 26) + 8)
    expect(plan.topSpacer).toBe(96 * 26)
    expect(plan.hasMore).toBe(true)
  })

  it('滚动到顶部时不留上方占位、start 不为负', () => {
    const plan = windowForScroll(0, 260, 26, 1000, 4)
    expect(plan.start).toBe(0)
    expect(plan.topSpacer).toBe(0)
  })

  it('末尾截断：不越过总行数，且报「到底了」', () => {
    const plan = windowForScroll(999 * 26, 260, 26, 1000, 4)
    expect(plan.start + plan.len).toBe(1000)
    expect(plan.hasMore).toBe(false)
    expect(plan.bottomSpacer).toBe(0)
  })

  it('总行数为 0 时给出空片（空态由调用方渲染，不是这里编数据）', () => {
    const plan = windowForScroll(0, 260, 26, 0, 4)
    expect(plan).toEqual({ start: 0, len: 0, topSpacer: 0, bottomSpacer: 0, hasMore: false })
  })

  it('行高为 0 直接抛错（会静默永远取同一片的坑）', () => {
    expect(() => windowForScroll(0, 260, 0, 10)).toThrow()
  })

  it('负滚动位置按 0 处理（弹性滚动会给出负值）', () => {
    expect(windowForScroll(-40, 260, 26, 100, 4).start).toBe(0)
  })
})
