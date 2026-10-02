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
    // 这份清单是**快照**：加命令时这里与 ipc.ts / lib.rs 的 generate_handler![] 一起改，
    // 三方不一致由 Rust 侧那条双向判据与这条快照各抓一半（漏改哪一半都红）。
    expect(Object.values(COMMANDS)).toEqual([
      'app_info',
      'dataset_summary',
      'grid_window',
      'db_connect',
      'db_disconnect',
      'db_tables',
      'db_schemas',
      'db_relations',
      'search_objects',
      'db_query',
      'db_run_batch',
      'db_cancel',
      'explain_statement',
      'highlight_sql',
      'db_write_batch',
      'db_primary_key',
      'edits_to_dml',
      'statement_risk',
      'db_read_only',
      'db_probe',
      'connections_list',
      'connection_save',
      'connection_delete',
      'browse_sql',
      'inspect_row',
      'db_foreign_keys',
      'workspace_list_directory',
      'workspace_read_file',
      'workspace_history',
      'workspace_opened',
      'workspace_closed',
      'workspace_open_tabs',
      'workspace_create',
      'workspace_rename',
      'workspace_move',
      'workspace_deletion_summary',
      'workspace_delete',
      'workspace_reveal',
      'workspace_read_lines',
      'workspace_read_spans',
      'workspace_file_snapshot',
      'workspace_check_staleness',
      'workspace_record_cursor',
      'workspace_search',
      'workspace_clamp_line',
      'workspace_markdown',
      'appearance_get',
      'appearance_set',
      'palette_search',
      'db_palette_objects',
      'command_history_get',
      'command_history_record',
      'command_history_clear',
      'workspace_decide_open',
      'workspace_read_image',
      'workspace_save',
      'workspace_replace_preview',
      'workspace_replace_apply',
      'workspace_format_tools',
      'workspace_format_content',
    ])
  })

  it('实验库默认连接参数指向本机专用测试集群，且**不带口令**', async () => {
    const { LAB_CONNECTION } = await import('./ipc')
    expect(LAB_CONNECTION.port).toBe(5433)
    expect(LAB_CONNECTION.database).toBe('doyah_lab')
    expect(LAB_CONNECTION.sslMode).toBe('disable')
    expect(LAB_CONNECTION.password).toBeUndefined()
  })
})
