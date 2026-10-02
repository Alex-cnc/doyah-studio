import { describe, expect, it } from 'vitest'
import { csvCell, exportRows, sqlLiteral, tsvCell, markdownCell, EXPORT_FORMAT_LABELS } from './export'
import { DEFAULT_PAGE_SIZE, frozenColumnStylesMeasured, pageOf } from './view'
import type { QueryResult } from '../ipc'

/** 造一份结果：两列三行，第二行有 NULL，第一列是数值。 */
function sample(): QueryResult {
  return {
    columns: ['id', 'name'],
    rows: [
      ['1', '阿甲'],
      ['2', null],
      ['3', 'has,comma'],
    ],
    numRows: [
      [1, null],
      [2, null],
      [3, null],
    ],
    returned: 3,
    truncated: false,
    affected: null,
  }
}

describe('grid/export', () => {
  it('CSV：含逗号 / 引号 / 换行的字段加引号，字段内引号翻倍', () => {
    expect(csvCell('plain')).toBe('plain')
    expect(csvCell('has,comma')).toBe('"has,comma"')
    expect(csvCell('say "hi"')).toBe('"say ""hi"""')
    expect(csvCell('two\nlines')).toBe('"two\nlines"')
    // NULL 在 CSV 里是空字段（贴进表格就是空单元格）
    expect(csvCell(null)).toBe('')
  })

  it('CSV：表头与行用 CRLF 连接（RFC 4180）', () => {
    const text = exportRows(sample(), [0, 1, 2], 'csv')
    expect(text.split('\r\n')).toHaveLength(4)
    expect(text).toContain('"has,comma"')
    expect(text.split('\r\n')[2]).toBe('2,')
  })

  it('TSV：制表符与换行换成空格（Excel 不认引号，宁可丢格式不能串列）', () => {
    expect(tsvCell('a\tb')).toBe('a b')
    expect(tsvCell('a\nb')).toBe('a b')
    expect(tsvCell(null)).toBe('')
    const text = exportRows(sample(), [0, 1, 2], 'tsv')
    expect(text.split('\n')).toHaveLength(4)
  })

  it('JSON：能取到数值的写数字、NULL 写 null、其余写字符串', () => {
    const parsed = JSON.parse(exportRows(sample(), [0, 1], 'json'))
    expect(parsed).toEqual([
      { id: 1, name: '阿甲' },
      { id: 2, name: null },
    ])
    // 类型不许被糊成字符串
    expect(typeof parsed[0].id).toBe('number')
  })

  it('Markdown：竖线转义、换行变空格、带分隔行', () => {
    expect(markdownCell('a|b')).toBe('a\\|b')
    expect(markdownCell('a\nb')).toBe('a b')
    const lines = exportRows(sample(), [0], 'markdown').split('\n')
    expect(lines[0]).toBe('| id | name |')
    expect(lines[1]).toBe('| --- | --- |')
    expect(lines[2]).toBe('| 1 | 阿甲 |')
  })

  it('SQL 字面量：NULL 关键字 / 数字不加引号 / 字符串单引号翻倍', () => {
    expect(sqlLiteral(null, null)).toBe('NULL')
    expect(sqlLiteral('42', 42)).toBe('42')
    expect(sqlLiteral("it's", null)).toBe("'it''s'")
  })

  it('INSERT 语句：列名加引号、未给表名时用 results 且如实写出来', () => {
    const text = exportRows(sample(), [0], 'sqlInsert', 'app.accounts')
    expect(text).toBe('INSERT INTO app.accounts ("id", "name") VALUES (1, \'阿甲\');')
    const fallback = exportRows(sample(), [1], 'sqlInsert')
    expect(fallback).toContain('INSERT INTO results')
    expect(fallback).toContain('NULL')
  })

  it('导出只覆盖**给的那几行**（导出必须与眼前一致）', () => {
    const onlyFirst = exportRows(sample(), [0], 'tsv')
    expect(onlyFirst.split('\n')).toHaveLength(2)
    const reversed = exportRows(sample(), [2, 0], 'tsv')
    const lines = reversed.split('\n')
    expect(lines[1]).toContain('has,comma')
    expect(lines[2]).toContain('阿甲')
  })

  it('每种格式都有界面名字（加了格式忘了加名字会在这里露出来）', () => {
    const formats = ['tsv', 'csv', 'json', 'markdown', 'sqlInsert'] as const
    for (const f of formats) {
      expect(EXPORT_FORMAT_LABELS[f]).toBeTruthy()
    }
  })
})

describe('grid/view 分页与实测列宽', () => {
  it('分页：页码夹到 1..pageCount，不返回空白页', () => {
    const order = Array.from({ length: 450 }, (_, i) => i)
    const first = pageOf(order, 1, 200)
    expect(first.page).toBe(1)
    expect(first.pageCount).toBe(3)
    expect(first.rows).toHaveLength(200)
    expect(first.total).toBe(450)
    // 超界夹到最后一页；负数夹到第一页
    expect(pageOf(order, 99, 200).page).toBe(3)
    expect(pageOf(order, -5, 200).page).toBe(1)
    expect(pageOf(order, 3, 200).rows).toHaveLength(50)
  })

  it('分页：空结果算 1 页 0 行（"第 0 页 / 共 0 页"读起来像出错）', () => {
    const page = pageOf([], 1, 200)
    expect(page.pageCount).toBe(1)
    expect(page.page).toBe(1)
    expect(page.rows).toEqual([])
  })

  it('分页：页大小非法时退回缺省值，不抛异常', () => {
    const order = [1, 2, 3, 4, 5]
    expect(pageOf(order, 1, 0).rows).toHaveLength(5)
    expect(pageOf(order, 1, -3).rows).toHaveLength(5)
    expect(pageOf(order, 1, Number.NaN).rows).toHaveLength(5)
    expect(DEFAULT_PAGE_SIZE).toBeGreaterThan(0)
    // 小数页大小按整数处理
    expect(pageOf(order, 1, 2.7).rows).toHaveLength(2)
  })

  it('冻结列：优先用实测宽度，缺的那列退回估算', () => {
    const columns = ['id', 'name', 'note']
    const measured = { 0: 50, 1: 120 }
    const styles = frozenColumnStylesMeasured(columns, 3, measured)
    expect(styles[0].left).toBe('0px')
    expect(styles[1].left).toBe('50px')
    // 第 3 列没量到 ⇒ left 仍按前两列累加（估算值只影响它自己之后的偏移）
    expect(styles[2].left).toBe('170px')
  })

  it('冻结列：实测宽度非法（0 / 负数 / NaN）时退回估算', () => {
    const columns = ['id', 'name']
    const styles = frozenColumnStylesMeasured(columns, 2, { 0: 0, 1: Number.NaN })
    expect(styles[0].left).toBe('0px')
    // 第 0 列退回估算 ⇒ 第 1 列的 left 等于那个估算值，而不是 0
    expect(styles[1].left).not.toBe('0px')
  })

  it('冻结列：frozenCount 超界 / 负数都夹紧', () => {
    expect(Object.keys(frozenColumnStylesMeasured(['a', 'b'], 9, {}))).toEqual(['0', '1'])
    expect(frozenColumnStylesMeasured(['a', 'b'], -2, {})).toEqual({})
  })
})
