// 填值面板纯逻辑的判据（FR-EXEC-17）。
//
// 这几条是「缺值不许执行」那条规矩的落点：面板的按钮是不是灰的、缺哪个参数、
// 转给领域层的是什么 —— 全在这里判，而不是靠挂载一张界面去间接看。
import { describe, expect, it } from 'vitest'
import type { ParameterBindOutcome, ParamSite } from '../ipc'
import {
  DEFAULT_PARAM_KIND,
  PARAM_KINDS,
  bindingLines,
  canSubmit,
  initialRows,
  isFilled,
  missingNames,
  toValues,
  unusedHint,
} from './queryParams'

const sites: ParamSite[] = [
  { name: ':name', occurrences: 2, positional: false },
  { name: '$1', occurrences: 1, positional: true },
]

describe('查询参数 · 填值面板纯逻辑', () => {
  it('初始行：每个站点一行、默认文本、都没碰过', () => {
    const rows = initialRows(sites)
    expect(rows).toHaveLength(2)
    expect(rows.map((row) => row.name)).toEqual([':name', '$1'])
    expect(rows[0].occurrences).toBe(2)
    expect(rows[1].positional).toBe(true)
    for (const row of rows) {
      expect(row.kind).toBe(DEFAULT_PARAM_KIND)
      expect(row.touched).toBe(false)
      expect(row.value).toBe('')
    }
  })

  it('缺值判定：没碰过就是没填；碰过之后删空算填了（空串是合法值）', () => {
    const rows = initialRows(sites)
    expect(missingNames(rows)).toEqual([':name', '$1'])
    expect(isFilled(rows[0])).toBe(false)

    // 用户敲了一下再删空 ⇒ 想要的是空串，不是「没填」
    rows[0].touched = true
    expect(isFilled(rows[0])).toBe(true)
    expect(missingNames(rows)).toEqual(['$1'])
  })

  it('NULL 不需要填值（值本来就被忽略）', () => {
    const rows = initialRows([{ name: ':x', occurrences: 1, positional: false }])
    rows[0].kind = 'null'
    expect(isFilled(rows[0])).toBe(true)
    expect(canSubmit(rows)).toBe(true)
  })

  it('缺一个就不许执行（按钮的判据与领域层同一个口径）', () => {
    const rows = initialRows(sites)
    expect(canSubmit(rows)).toBe(false)
    rows[0].touched = true
    expect(canSubmit(rows)).toBe(false)
    rows[1].touched = true
    expect(canSubmit(rows)).toBe(true)
  })

  it('空行不算可提交（没有参数就不该有面板）', () => {
    expect(canSubmit([])).toBe(false)
  })

  it('转给领域层的顺序与面板一致，类型原样带过去', () => {
    const rows = initialRows(sites)
    rows[0].value = '张三'
    rows[0].touched = true
    rows[1].kind = 'number'
    rows[1].value = '42'
    rows[1].touched = true
    expect(toValues(rows)).toEqual([
      { name: ':name', value: '张三', kind: 'text' },
      { name: '$1', value: '42', kind: 'number' },
    ])
  })

  it('回执逐条给出名字 / 类型 / 次数 / 实际写法', () => {
    const outcome: ParameterBindOutcome = {
      sql: "select * from t where name = 'x' and id = 1",
      params: [
        { name: ':name', occurrences: 2, kind: 'text', literal: "'x'" },
        { name: '$1', occurrences: 1, kind: 'number', literal: '1' },
      ],
      unused: [],
    }
    expect(bindingLines(outcome)).toEqual([
      { name: ':name', kind: 'text', occurrences: 2, literal: "'x'" },
      { name: '$1', kind: 'number', occurrences: 1, literal: '1' },
    ])
  })

  it('多余的值有提示、没有多余值就**不**输出任何话', () => {
    const withUnused: ParameterBindOutcome = {
      sql: 'select 1',
      params: [],
      unused: [':typo', ':nam'],
    }
    expect(unusedHint(withUnused)).toBe(':typo、:nam')
    expect(unusedHint({ sql: 'select 1', params: [], unused: [] })).toBe('')
  })

  it('类型清单覆盖四种写法（文本 / 数字 / 布尔 / NULL）', () => {
    expect(PARAM_KINDS).toEqual(['text', 'number', 'boolean', 'null'])
  })
})
