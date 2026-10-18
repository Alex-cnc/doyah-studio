// 编辑面智能辅助 —— 行为判据（FR-EDIT-57 / 59 / 56）
//
// 每条用例名就是需求里那句行为。

import { describe, expect, it } from 'vitest'
import {
  applyCompletion,
  completionContext,
  diagnosticsToMarks,
  expandSnippet,
  snippetFor,
  type CompletionItem,
} from './assist'

const CATALOG: CompletionItem[] = [
  { text: 'select', kind: 'keyword' },
  { text: 'se', kind: 'keyword' },
  { text: 'session_id', kind: 'function' },
  { text: 'setval', kind: 'function' },
  { text: 'select-join', kind: 'snippet' },
]

describe('FR-EDIT-57 补全候选', () => {
  it('前缀为空 ⇒ 不弹表（不在每次按键后弹整张表）', () => {
    expect(completionContext('select ', 7, CATALOG).items).toEqual([])
  })

  it('按前缀过滤（大小写不敏感）', () => {
    const context = completionContext('SEL', 3, CATALOG)
    expect(context.prefix).toBe('SEL')
    expect(context.items.map((item) => item.text)).toContain('select')
  })

  it('前缀完全相等排在前面', () => {
    const context = completionContext('se', 2, CATALOG)
    expect(context.items[0].text).toBe('se')
  })

  it('排序稳定：同前缀两次调用结果一致，且按 关键字 > 函数 > 片段', () => {
    const first = completionContext('s', 1, CATALOG).items.map((item) => item.text)
    const second = completionContext('s', 1, CATALOG).items.map((item) => item.text)
    expect(first).toEqual(second)
    const kinds = completionContext('s', 1, CATALOG).items.map((item) => item.kind)
    const weight = { keyword: 0, function: 1, snippet: 2 } as const
    const weights = kinds.map((kind) => weight[kind])
    expect(weights).toEqual([...weights].sort((a, b) => a - b))
  })

  it('带点号的限定：点号不进前缀，限定符单独交出（替换只动标识符）', () => {
    const context = completionContext('t.sel', 5, CATALOG)
    expect(context.prefixStart).toBe(2)
    expect(context.prefix).toBe('sel')
    expect(context.qualifier).toBe('t')
    const applied = applyCompletion('t.sel', 5, context, { text: 'select', kind: 'keyword' })
    expect(applied.text).toBe('t.select')
  })

  it('limit 限定候选条数', () => {
    expect(completionContext('s', 1, CATALOG, 1).items).toHaveLength(1)
  })

  it('接受候选：替换前缀并把光标放到插入值之后', () => {
    const text = 'select ses'
    const context = completionContext(text, text.length, CATALOG)
    const applied = applyCompletion(text, text.length, context, { text: 'session_id', kind: 'function' })
    expect(applied.text).toBe('select session_id')
    expect(applied.caret).toBe(applied.text.length)
  })

  it('光标越界时夹进全文（不抛异常）', () => {
    expect(() => completionContext('abc', 99, CATALOG)).not.toThrow()
    expect(completionContext('abc', 99, CATALOG).prefix).toBe('abc')
  })
})

describe('FR-EDIT-59 片段', () => {
  it('占位取默认值、`$0` 决定最终光标', () => {
    const expanded = expandSnippet('select ${1:*} from ${2:table} where $0;')
    expect(expanded.text).toBe('select * from table where ;')
    expect(expanded.caret).toBe(expanded.text.length - 1)
  })

  it('没有 `$0` ⇒ 光标落在末尾', () => {
    expect(expandSnippet('begin\n\nend')).toEqual({ text: 'begin\n\nend', caret: 10 })
  })

  it('未知的 `$n` 原样保留（不吞字符）', () => {
    expect(expandSnippet('a $9 b').text).toBe('a $9 b')
  })

  it('触发词匹配大小写不敏感，命不中返回 null', () => {
    const snippets = { sel: 'select $0' }
    expect(snippetFor('SEL', snippets)).toBe('select $0')
    expect(snippetFor('nope', snippets)).toBeNull()
  })
})

describe('FR-EDIT-56 诊断上屏', () => {
  const text = 'select 1\nfrom t\nbad('

  it('字符偏移落到正确行', () => {
    const marks = diagnosticsToMarks([{ start: 10, end: 12, severity: 'error', message: '未知列' }], text)
    expect(marks).toEqual([{ line: 1, severity: 'error', message: '未知列', count: 1 }])
  })

  it('同一行多条 ⇒ 归并成一条，取最严重的文案并计数', () => {
    const marks = diagnosticsToMarks(
      [
        { start: 10, end: 11, severity: 'info', message: '提示' },
        { start: 12, end: 13, severity: 'error', message: '括号未闭合' },
        { start: 14, end: 15, severity: 'warning', message: '警告' },
      ],
      text,
    )
    expect(marks).toEqual([{ line: 1, severity: 'error', message: '括号未闭合', count: 3 }])
  })

  it('按行号升序输出（与输入顺序无关）', () => {
    const marks = diagnosticsToMarks(
      [
        { start: 18, end: 19, severity: 'error', message: 'c' },
        { start: 0, end: 1, severity: 'error', message: 'a' },
      ],
      text,
    )
    expect(marks.map((mark) => mark.line)).toEqual([0, 2])
  })

  it('偏移越界夹进全文（不抛异常）', () => {
    const marks = diagnosticsToMarks([{ start: 999, end: 999, severity: 'info', message: 'x' }], text)
    expect(marks[0].line).toBe(2)
  })
})
