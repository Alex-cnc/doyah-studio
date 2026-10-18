// Schema 对比与同步（FR-DDL-04）的展示逻辑判据：
// 脚本怎么拼、时间怎么显示、状态行怎么读 —— 这几条不该靠「装上包看一眼」才算验过。

import { describe, expect, it } from 'vitest'
import { t, type DictKey } from '../i18n'
import type { SchemaDiffReport, SchemaSnapshot, TableDiff } from '../ipc'
import { STATUS_KEYS, columnSummary, diffCounts, formatTakenAt, slotLine, statementScript } from './schemaDiff'

const zh = (key: DictKey, vars?: Record<string, string | number>): string => t(key, 'zh-Hans', vars)

function diff(overrides: Partial<TableDiff> = {}): TableDiff {
  return {
    table: 'orders',
    status: 'alter',
    addedColumns: [],
    removedColumns: [],
    alteredColumns: [],
    primaryKeyDiffers: false,
    ...overrides,
  }
}

function report(overrides: Partial<SchemaDiffReport> = {}): SchemaDiffReport {
  return {
    baseLabel: '基准（左）',
    targetLabel: '目标（右）',
    baseTableCount: 1,
    targetTableCount: 1,
    tableDiffs: [],
    statements: [],
    skipped: [],
    allowDrop: false,
    destructiveCount: 0,
    createdTables: 0,
    alteredTables: 0,
    droppedTables: 0,
    ...overrides,
  }
}

function snapshot(overrides: Partial<SchemaSnapshot> = {}): SchemaSnapshot {
  return { label: '基准（左）', schema: 'public', takenAt: 0, tables: [], ...overrides }
}

describe('schemaDiff 展示逻辑', () => {
  it('每张表的差异只列非零项（不出现「加 0 列」这种噪声）', () => {
    expect(columnSummary(diff(), zh)).toBe('')
    expect(columnSummary(diff({ addedColumns: ['a', 'b'] }), zh)).toBe('加 2 列')
    expect(columnSummary(diff({ addedColumns: ['a'], alteredColumns: ['c'] }), zh)).toBe('加 1 列 · 改 1 列')
    expect(columnSummary(diff({ primaryKeyDiffers: true }), zh)).toContain('主键不同')
  })

  it('三种差异状态各有自己的文案（不会都落到「一致」）', () => {
    const keys = new Set(Object.values(STATUS_KEYS))
    expect(keys.size).toBe(4)
    expect(zh(STATUS_KEYS.create)).toContain('建表')
    expect(zh(STATUS_KEYS.drop)).toContain('删表')
    expect(zh(STATUS_KEYS.alter)).toContain('改表')
  })

  it('同步脚本按下发顺序拼、空报告给空串（不产出「看起来像脚本」的空白）', () => {
    const statements = [
      { sql: '-- 建表 a\nCREATE TABLE "public"."a" ();', bare: '', class: 'additive' as const, purpose: '建表' },
      { sql: '-- 删表 b\nDROP TABLE "public"."b";', bare: '', class: 'destructive' as const, purpose: '删表' },
    ]
    expect(statementScript(report({ statements }))).toBe(
      '-- 建表 a\nCREATE TABLE "public"."a" ();\n\n-- 删表 b\nDROP TABLE "public"."b";',
    )
    expect(statementScript(report())).toBe('')
    expect(statementScript(null)).toBe('')
  })

  it('抓取时间按本地时区显示到分钟；没抓过的时刻显示占位而不是 1970', () => {
    const text = formatTakenAt(new Date(2026, 9, 18, 9, 5, 30).getTime())
    expect(text).toBe('2026-10-18 09:05')
    expect(formatTakenAt(0)).toBe('—')
    expect(formatTakenAt(Number.NaN)).toBe('—')
  })

  it('没抓快照的一侧明说「还没抓」（不用空表冒充一个空库）', () => {
    expect(slotLine(null, zh)).toBe('还没抓')
    const line = slotLine(snapshot({ tables: [{ name: 'a', columns: [], primaryKey: [] }], takenAt: new Date(2026, 9, 18, 9, 5).getTime() }), zh)
    expect(line).toContain('public')
    expect(line).toContain('1 张表')
    expect(line).toContain('2026-10-18 09:05')
  })

  it('报告计数取自报告本身（界面与判据同一份读数）', () => {
    const counts = diffCounts(report({ createdTables: 2, alteredTables: 1, droppedTables: 0, skipped: [{ table: 'x', what: 'w', reason: 'r' }] }))
    expect(counts).toEqual({ created: 2, altered: 1, dropped: 0, skipped: 1 })
    expect(diffCounts(null)).toEqual({ created: 0, altered: 0, dropped: 0, skipped: 0 })
  })
})
