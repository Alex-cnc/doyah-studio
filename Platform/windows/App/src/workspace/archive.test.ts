// 查询自动归档 —— 行为判据（FR-EDIT-31）
//
// 这一组判据锁的是**文件里那份内容**（渲染 ↔ 解析互为逆），因为界面显示的清单就是它：
// 只要这两头对得上，「执行过的 SQL 在哪儿能看到」就不依赖任何别的东西。
import { describe, expect, it } from 'vitest'
import {
  ARCHIVE_MAX_CHARS,
  archiveDate,
  archiveDayChoices,
  archivePath,
  archiveTime,
  incomingEntry,
  mergeArchiveEntry,
  parseArchive,
  renderArchive,
  type ArchiveEntry,
} from './archive'

// 用本地时间构造，避免测试随时区飘
const AT = new Date(2026, 8, 27, 9, 5, 7).getTime()
const LATER = new Date(2026, 8, 27, 9, 12, 30).getTime()

function entry(sql: string, overrides: Partial<ArchiveEntry> = {}): ArchiveEntry {
  return {
    ...incomingEntry(sql, '查询 1', 'local', 'doyah_lab', AT, 12, 5),
    ...overrides,
  }
}

describe('FR-EDIT-31 查询自动归档', () => {
  it('按天一个文件：queries/YYYY-MM-DD.sql', () => {
    expect(archiveDate(AT)).toBe('2026-09-27')
    expect(archivePath(AT)).toBe('queries/2026-09-27.sql')
  })

  it('时刻补零到 HH:MM:SS', () => {
    expect(archiveTime(AT)).toBe('09:05:07')
  })

  it('渲染与解析互为逆：中文 / 多行 SQL / 行尾注释都逐字回得来', () => {
    const original: ArchiveEntry[] = [
      entry('SELECT 订单号, 金额\n  FROM 订单 -- 只看今天的\n  WHERE 金额 > 0;'),
      entry('select 1;', { title: '', connectionName: null, database: null, elapsedMs: null, rows: null, runs: 3 }),
    ]
    const back = parseArchive(renderArchive(original))
    expect(back).toEqual(original)
  })

  it('SQL 里普通的 -- 注释不会被当成条目头（头要带 runs/first/last 的 JSON）', () => {
    const text = renderArchive([entry('-- 09:05:07 这只是注释\nselect 1;')])
    const back = parseArchive(text)
    expect(back).toHaveLength(1)
    expect(back[0].sql).toBe('-- 09:05:07 这只是注释\nselect 1;')
  })

  it('同一条 SQL 再执行一次：只累计次数，首次时间不动、最近时间换新，文件里仍只有一段', () => {
    const first = mergeArchiveEntry('', entry('select 1;'))
    expect(first).not.toBeNull()
    expect(first!.runs).toBe(1)

    const second = mergeArchiveEntry(
      first!.content,
      entry('select 1;', { lastAt: archiveTime(LATER), elapsedMs: 40, rows: 9 }),
    )
    expect(second).not.toBeNull()
    expect(second!.runs).toBe(2)

    const back = parseArchive(second!.content)
    expect(back).toHaveLength(1)
    expect(back[0].runs).toBe(2)
    expect(back[0].firstAt).toBe('09:05:07')
    expect(back[0].lastAt).toBe('09:12:30')
    expect(back[0].elapsedMs).toBe(40)
    expect(back[0].rows).toBe(9)
    // 否定面：不是「两段一样的内容」—— 文件里只出现一次 SQL
    expect(second!.content.split('select 1;').length - 1).toBe(1)
  })

  it('首尾空白不同算同一条（去空白后全文相等）；大小写不同算两条（不擅自折成一条）', () => {
    const first = mergeArchiveEntry('', entry('select 1;'))!
    const padded = mergeArchiveEntry(first.content, entry('\n  select 1;  \n'))!
    expect(padded.runs).toBe(2)

    const cased = mergeArchiveEntry(padded.content, entry('SELECT 1;'))!
    expect(cased.runs).toBe(1)
    expect(parseArchive(cased.content)).toHaveLength(2)
  })

  it('元数据（连接 / 库 / 耗时 / 行数）跟着这一次执行走，解析后读得回来', () => {
    const merged = mergeArchiveEntry('', entry('update t set a = 1;', { elapsedMs: 7, rows: 3 }))!
    const [saved] = parseArchive(merged.content)
    expect(saved.connectionName).toBe('local')
    expect(saved.database).toBe('doyah_lab')
    expect(saved.elapsedMs).toBe(7)
    expect(saved.rows).toBe(3)
  })

  it('超过单文件上限 ⇒ null（不静默丢，交调用方提示）', () => {
    const huge = 'x'.repeat(ARCHIVE_MAX_CHARS - 5)
    expect(mergeArchiveEntry('', entry(huge))).toBeNull()
  })

  it('空内容解析成空清单（第一次使用的样子）', () => {
    expect(parseArchive('')).toEqual([])
    expect(parseArchive('\n\n  \n')).toEqual([])
  })
})

// 日期切换的口径（面板顶部那排按钮画哪些日子）
describe('归档日期切换的可选日（archiveDayChoices）', () => {
  it('今天必须在里面（当天还没执行过语句时盘上还没有这份文件）', () => {
    expect(archiveDayChoices([], '2026-10-19')).toEqual(['2026-10-19'])
  })

  it('盘上的日子并进来、新的在前、去重（今天重复出现也只一格）', () => {
    expect(archiveDayChoices(['2026-10-17', '2026-10-19', '2026-10-18'], '2026-10-19')).toEqual([
      '2026-10-19',
      '2026-10-18',
      '2026-10-17',
    ])
  })

  it('非法日期键不出现（手放的 / 别的工具写的文件不该给一个点了就读不出来的按钮）', () => {
    expect(
      archiveDayChoices(['2026-13-01', '2026-10-32', '20261018', '2026-10-1', 'notes', ''], '2026-10-19'),
    ).toEqual(['2026-10-19'])
  })
})
