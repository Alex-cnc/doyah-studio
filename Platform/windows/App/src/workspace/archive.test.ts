// 查询自动归档 —— 行为判据（FR-EDIT-31）
import { describe, expect, it } from 'vitest'
import {
  ARCHIVE_MAX_CHARS,
  appendArchive,
  archiveDate,
  archiveEntry,
  archivePath,
  archiveTime,
} from './archive'

// 用本地时间构造，避免测试随时区飘
const AT = new Date(2026, 8, 27, 9, 5, 7).getTime()

describe('FR-EDIT-31 查询自动归档', () => {
  it('按天一个文件：queries/YYYY-MM-DD.sql', () => {
    expect(archiveDate(AT)).toBe('2026-09-27')
    expect(archivePath(AT)).toBe('queries/2026-09-27.sql')
  })

  it('时刻补零到 HH:MM:SS', () => {
    expect(archiveTime(AT)).toBe('09:05:07')
  })

  it('条目带分隔注释（时刻 + 页签标题），SQL 原样保留', () => {
    expect(archiveEntry('select 1;', '查询 1', AT)).toBe('-- 09:05:07 查询 1\nselect 1;\n')
  })

  it('标题为空时只写时刻', () => {
    expect(archiveEntry('select 1', '  ', AT)).toBe('-- 09:05:07\nselect 1\n')
  })

  it('追加不吞上一条，也不需要上一条以换行结尾', () => {
    const next = appendArchive('-- 09:00:00 a\nselect 1', 'select 2', 'b', AT)
    expect(next).toBe('-- 09:00:00 a\nselect 1\n-- 09:05:07 b\nselect 2\n')
  })

  it('超过单文件上限 ⇒ null（不静默丢，交调用方提示）', () => {
    const huge = 'x'.repeat(ARCHIVE_MAX_CHARS - 5)
    expect(appendArchive(huge, 'select 1', 'a', AT)).toBeNull()
  })
})
