import { describe, expect, it } from 'vitest'
import { poolSlots, windowForScroll } from './windowing'

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

describe('grid/poolSlots（行池槽位：槽位固定、行号轮转）', () => {
  it('槽位号恒为 0..len-1（v-for 的 key 永不变化）', () => {
    expect(poolSlots(0, 4).map((s) => s.slot)).toEqual([0, 1, 2, 3])
    expect(poolSlots(97, 4).map((s) => s.slot)).toEqual([0, 1, 2, 3])
    expect(poolSlots(1, 0)).toEqual([])
  })

  it('每个槽位恰好覆盖 [start, start+len-1] 里的一个行号，不重不漏', () => {
    for (const start of [0, 1, 5, 11, 38, 77, 399989]) {
      const slots = poolSlots(start, 38)
      const rows = slots.map((s) => s.row).sort((a, b) => a - b)
      const want = Array.from({ length: 38 }, (_, i) => start + i)
      expect(rows).toEqual(want)
    }
  })

  it('窗口平移一行只换一个槽位的内容（这是「不重建、不移动节点」的全部依据）', () => {
    for (const start of [0, 1, 37, 38, 39, 100, 1031]) {
      const a = poolSlots(start, 38)
      const b = poolSlots(start + 1, 38)
      const changed = a.filter((s, i) => s.row !== b[i].row).length
      expect(changed).toBe(1)
    }
  })

  it('滚动一整圈（len 行）后回到同一分配（轮转周期 = len）', () => {
    const a = poolSlots(1234, 38)
    const b = poolSlots(1234 + 38, 38)
    expect(b.map((s) => s.row - 38)).toEqual(a.map((s) => s.row))
  })

  it('负 start 直接抛错（轮转会把某槽映射到不存在的行 -1；窗口起点由 windowForScroll 保证非负）', () => {
    expect(() => poolSlots(-1, 4)).toThrow()
  })
})
