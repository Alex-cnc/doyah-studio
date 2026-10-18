// 已保存查询的纯显示口径判据（FR-EDIT-14 · 2026-10-18 · 第 7 轮）
import { describe, expect, it } from 'vitest'
import {
  SUGGESTED_NAME_MAX,
  savedQuerySourceLabel,
  savedQuerySqlPreview,
  savedQueryTimeLabel,
  suggestQueryName,
} from './savedQueries'

describe('已保存查询 · 默认名字', () => {
  it('取第一行有内容的：跳空行、去行尾分号、折空白', () => {
    expect(suggestQueryName('\n\n  select   id, name\nfrom t;\n', '查询 1')).toBe('select id, name')
    expect(suggestQueryName('select 1;\nselect 2;', '查询 1')).toBe('select 1')
  })

  it('跳过注释行（分隔线当名字等于没名字）', () => {
    expect(suggestQueryName('-- ======\n-- 月度对账\nselect 1', '查询 1')).toBe('select 1')
    expect(suggestQueryName('// note\nselect 1', '查询 1')).toBe('select 1')
  })

  it('超长截断到上限（不是整行塞进按钮）', () => {
    const long = `select ${'a'.repeat(SUGGESTED_NAME_MAX * 2)}`
    const name = suggestQueryName(long, '查询 1')
    expect(name.length).toBe(SUGGESTED_NAME_MAX)
    expect(name.endsWith('…')).toBe(true)
  })

  it('否定面：只有空行 / 只有注释 ⇒ 退回页签标题（不返回空名字）', () => {
    expect(suggestQueryName('\n  \n-- 只有注释\n', '  查询 3  ')).toBe('查询 3')
    expect(suggestQueryName('', '查询 3')).toBe('查询 3')
  })
})

describe('已保存查询 · 列表副标题', () => {
  it('连接名 · 库 · 时间三段都写', () => {
    expect(
      savedQuerySourceLabel({
        id: 'a',
        name: 'n',
        sql: 'select 1',
        connectionName: '实验库',
        database: 'doyah_lab',
        savedAt: '2026-10-18T10:05:00Z',
        schemaVersion: 1,
      }),
    ).toBe('实验库 · doyah_lab · 2026-10-18 10:05')
  })

  it('缺的段跳过（不留「—」占位）', () => {
    expect(
      savedQuerySourceLabel({
        id: 'a',
        name: 'n',
        sql: 'select 1',
        savedAt: '',
        schemaVersion: 1,
      }),
    ).toBe('')
  })

  it('SQL 摘要折成一行并截断', () => {
    expect(savedQuerySqlPreview({ id: 'a', name: 'n', sql: 'select\n  1\nfrom t', savedAt: '', schemaVersion: 1 })).toBe(
      'select 1 from t',
    )
    const preview = savedQuerySqlPreview(
      { id: 'a', name: 'n', sql: 'x'.repeat(200), savedAt: '', schemaVersion: 1 },
      20,
    )
    expect(preview.length).toBe(20)
    expect(preview.endsWith('…')).toBe(true)
  })

  it('时间认不出就给空串（不编一个假时间出来）', () => {
    expect(savedQueryTimeLabel('')).toBe('')
    expect(savedQueryTimeLabel('昨天')).toBe('')
  })
})
