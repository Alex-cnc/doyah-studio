import { describe, expect, it } from 'vitest'
import { mockCells, mockColumnNames, COMMANDS, DEFAULT_GRID_SEED, datasetSummary, gridWindow, inTauri } from './ipc'

describe('ipc', () => {
  it('浏览器旁路返回确定性数据（同入参同输出）', () => {
    const first = mockCells(10, 3, 2, 2)
    const again = mockCells(10, 3, 2, 2)
    expect(first).toEqual(again)
    expect(first).toHaveLength(2)
    expect(first[0]).toHaveLength(3)
    expect(first[0][0]).toContain('3') // 第 2 行（0 基）→ 显示行号 3
  })

  it('列名规则与 Rust 领域层一致：每 5 列的第 5 列是文本列', () => {
    expect(mockColumnNames(6)).toEqual(['metric_0', 'metric_1', 'metric_2', 'metric_3', 'label_4', 'metric_5'])
  })

  it('不在 Tauri 里时走 mock，且如实自报 backend', async () => {
    expect(inTauri()).toBe(false)
    const summary = await datasetSummary(100, 5, DEFAULT_GRID_SEED)
    expect(summary.rows).toBe(100)
    expect(summary.colNames).toHaveLength(5)
    const window = await gridWindow({ rows: 100, cols: 5, seed: DEFAULT_GRID_SEED, orderDesc: false, start: 10, len: 3 })
    expect(window.start).toBe(10)
    expect(window.total).toBe(100)
    expect(window.cells).toHaveLength(3)
  })

  it('命令名与 Rust 侧的注册项同名（真正的双向判在 src-tauri/tests/ipc_contract.rs）', () => {
    expect(Object.values(COMMANDS)).toEqual(['app_info', 'dataset_summary', 'grid_window'])
  })
})
