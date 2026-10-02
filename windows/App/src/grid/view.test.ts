// 结果网格显示态（排序 / 筛选 / 复制）—— 行为判据
//
// 守的是三条最容易被写错的：**按值不按串**（9 vs 10）、**NULL 位置有规矩**（一律最后）、
// **稳定**（同值不抖动）。再守复制文本：NULL 是空单元格、制表符不串列。

import { describe, expect, it } from 'vitest'
import type { QueryResult } from '../ipc'
import { columnIsNumeric, sortedOrder, filteredOrder, visibleOrder, toTsv, rowText } from './view'

/** 造一个结果集：列 = id(num) / name(text) / score(num, 带 NULL)。 */
function sample(): QueryResult {
  return {
    columns: ['id', 'name', 'score'],
    rows: [
      ['10', 'bob', '9'],
      ['9', 'alice', null],
      ['100', 'carol', '10'],
      ['2', 'dave', '9'],
    ],
    numRows: [
      [10, null, 9],
      [9, null, null],
      [100, null, 10],
      [2, null, 9],
    ],
    returned: 4,
    truncated: false,
    affected: null,
  }
}

describe('列是不是数值列', () => {
  it('整列都能解析成数 ⇒ 数值列', () => {
    expect(columnIsNumeric(sample(), 0)).toBe(true)
  })

  it('文本列 ⇒ 不是；带 NULL 的数值列仍然算数值列（NULL 不参与判定）', () => {
    const r = sample()
    expect(columnIsNumeric(r, 1)).toBe(false)
    expect(columnIsNumeric(r, 2)).toBe(true)
  })

  it('空结果集 ⇒ 不是数值列（不猜）', () => {
    const empty: QueryResult = { columns: ['a'], rows: [], numRows: [], returned: 0, truncated: false, affected: null }
    expect(columnIsNumeric(empty, 0)).toBe(false)
  })
})

describe('排序：按值、不按串', () => {
  it('数值列按**数值**升序 —— 这正是 "9 > 10" 那种字典序错排要挡住的', () => {
    const order = sortedOrder(sample(), { column: 0, desc: false })
    expect(order).toEqual([3, 1, 0, 2]) // 2, 9, 10, 100
  })

  it('降序是升序的逆（没有 NULL 的列）', () => {
    const asc = sortedOrder(sample(), { column: 0, desc: false })
    const desc = sortedOrder(sample(), { column: 0, desc: true })
    expect(desc).toEqual([...asc].reverse())
  })

  it('文本列按显示文本排（locale 比较）', () => {
    const order = sortedOrder(sample(), { column: 1, desc: false })
    expect(order).toEqual([1, 0, 2, 3]) // alice, bob, carol, dave
  })

  it('NULL **一律最后**（升序降序都一样）—— 不随方向在两端跳', () => {
    const asc = sortedOrder(sample(), { column: 2, desc: false })
    const desc = sortedOrder(sample(), { column: 2, desc: true })
    expect(asc[asc.length - 1]).toBe(1) // score 为 NULL 的那行
    expect(desc[desc.length - 1]).toBe(1)
    // 前三个是真实值：升序 9,9,10；降序 10,9,9
    expect(asc.slice(0, 3).map((i) => sample().rows[i][2])).toEqual(['9', '9', '10'])
    expect(desc.slice(0, 3).map((i) => sample().rows[i][2])).toEqual(['10', '9', '9'])
  })

  it('同值**稳定**（按原本次序，不抖动）', () => {
    const order = sortedOrder(sample(), { column: 2, desc: false })
    // 两个 9 分：id 10（原序在前）应当排在 id 2 之前
    expect(order.slice(0, 2)).toEqual([0, 3])
  })

  it('不给排序态 ⇒ 原序', () => {
    expect(sortedOrder(sample(), null)).toEqual([0, 1, 2, 3])
  })
})

describe('筛选：纯包含、不分大小写', () => {
  it('空词 = 不过滤；命中按显示文本', () => {
    const r = sample()
    expect(filteredOrder(r, '')).toEqual([0, 1, 2, 3])
    expect(filteredOrder(r, '  ')).toEqual([0, 1, 2, 3])
    // alice / carol / dave 三行都含 a（我第一版漏了 dave —— 断言写错，不是实现错）
    expect(filteredOrder(r, 'A')).toEqual([1, 2, 3])
    expect(filteredOrder(r, 'carol')).toEqual([2])
  })

  it('命中为空就真的是空（不假装还有数据）', () => {
    expect(filteredOrder(sample(), 'zzz')).toEqual([])
  })

  it('NULL 单元格不参与匹配（显示为空串，不会命中任何词）', () => {
    const r = sample()
    expect(filteredOrder(r, 'null')).toEqual([])
  })
})

describe('筛选 + 排序串起来', () => {
  it('先筛后排：结果既命中筛选、又是排序序', () => {
    const r = sample()
    // 筛 "9"（命中 id=9 的 alice 与 score=9 的两行）—— 再按 id 升序
    const order = visibleOrder(r, '9', { column: 0, desc: false })
    const ids = order.map((i) => r.rows[i][0])
    // 命中三行：id 9（自己）、id 10（score 9）、id 2（score 9）—— 排序后按 id 升序
    expect(ids).toEqual(['2', '9', '10'])
  })

  it('不排序时只筛（保原序）', () => {
    expect(visibleOrder(sample(), 'a', null)).toEqual([1, 2, 3])
  })
})

describe('复制成 TSV', () => {
  it('首行是列名、NULL 是空单元格（不写 NULL 字样）', () => {
    const r = sample()
    const text = toTsv(r, [0, 1, 2, 3])
    const lines = text.split('\n')
    expect(lines[0]).toBe('id\tname\tscore')
    expect(lines[2]).toBe('9\talice\t') // 第 2 行（0 基 1）的 score 是 NULL ⇒ 空
    expect(lines).toHaveLength(5)
  })

  it('按给定顺序复制（复制的是**看得见的**那一屏顺序）', () => {
    const r = sample()
    const text = toTsv(r, sortedOrder(r, { column: 0, desc: false }))
    expect(text.split('\n')[1]).toBe('2\tdave\t9')
  })

  it('单元格里的制表符 / 换行被换成空格（否则贴过去串列）', () => {
    const r: QueryResult = {
      columns: ['x'],
      rows: [['a\tb'], ['c\nd']],
      numRows: [[null], [null]],
      returned: 2,
      truncated: false,
      affected: null,
    }
    const lines = toTsv(r, [0, 1]).split('\n')
    expect(lines[1]).toBe('a b')
    expect(lines[2]).toBe('c d')
  })
})

describe('显示文本', () => {
  it('NULL 显示为空串', () => {
    expect(rowText(['a', null, 'b'])).toEqual(['a', '', 'b'])
  })
})
