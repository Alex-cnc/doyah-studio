import { describe, expect, it } from 'vitest'
import { GridData, type GridMeta } from './gridData'

/** 小夹具：3 行 × 3 列（2 数值 + 1 文本字典列），与 Rust 侧 grid-bench 写出的格式同形 */
function fixture(): GridData {
  const meta: GridMeta = {
    rows: 3,
    cols: 3,
    colNames: ['metric_0', 'metric_1', 'label_2'],
    kinds: ['num', 'num', 'text'],
    dict: ['x-0', 'y-1', 'z-2'],
  }
  const cells = Float64Array.from([1, 2, 0, 3, 4, 1, 5, 6, 2])
  return new GridData(meta, cells)
}

describe('GridData（取数层）', () => {
  it('数值列按 4 位小数渲染，文本列查字典', () => {
    const g = fixture()
    expect(g.cell(0, 0)).toBe('1.0000')
    expect(g.cell(1, 2)).toBe('y-1')
    expect(g.cell(2, 2)).toBe('z-2')
  })

  it('长度不符必须抛错（不许静默截断）', () => {
    const meta: GridMeta = { rows: 2, cols: 2, colNames: ['a', 'b'], kinds: ['num', 'num'], dict: [] }
    expect(() => new GridData(meta, Float64Array.from([1, 2, 3]))).toThrow()
  })

  it('window 越界自动截断、且内容与 cell 一致', () => {
    const g = fixture()
    const w = g.window(2, 10)
    expect(w.length).toBe(1)
    expect(w[0][2]).toBe(g.cell(2, 2))
    expect(g.window(5, 3).length).toBe(0)
  })

  it('升序 / 降序都是 0..rows 的置换且真有序', () => {
    const g = fixture()
    const asc = Array.from(g.sortOrder(1, false))
    const desc = Array.from(g.sortOrder(1, true))
    expect([...asc].sort((a, b) => a - b)).toEqual([0, 1, 2])
    const vals = (idxs: number[]) => idxs.map((i) => Number(g.cell(i, 1)))
    expect(vals(asc)).toEqual([...vals(asc)].sort((a, b) => a - b))
    expect(vals(desc)).toEqual([...vals(desc)].sort((a, b) => b - a))
  })

  it('文本列筛选命中全部且不漏', () => {
    const g = fixture()
    expect(Array.from(g.filterText(2, 'y-1'))).toEqual([1])
    expect(g.filterText(2, '不存在')).toHaveLength(0)
  })
})
