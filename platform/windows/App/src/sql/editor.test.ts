import { describe, expect, it } from 'vitest'
import {
  executionTarget,
  filterCompletions,
  highlightPieces,
  keywordCompletions,
  objectCompletions,
  outcomeSummary,
  pickDisplayedOutcome,
  wordBeforeCaret,
  type CompletionItem,
} from './editor'
import type { SqlToken } from '../ipc'

const item = (text: string, kind: CompletionItem['kind'] = 'keyword'): CompletionItem => ({
  text,
  kind,
  detail: '',
})

describe('sql/editor', () => {
  it('光标前的词只取连续的标识符字符（点号与空白都算边界）', () => {
    expect(wordBeforeCaret('select ord', 10)).toBe('ord')
    expect(wordBeforeCaret('select app.ord', 14)).toBe('ord')
    expect(wordBeforeCaret('select ', 7)).toBe('')
    expect(wordBeforeCaret('', 0)).toBe('')
    expect(wordBeforeCaret('中文列', 3)).toBe('中文列')
  })

  it('补全过滤：前缀命中排在包含命中之前，且不区分大小写', () => {
    // 只有真含 `ere` 的才该进结果（`OWNER` 里没有 `ere`，写进去就是错的期望）
    const items = [item('WHERE'), item('ELSEWHERE'), item('REFERENCES'), item('select')]
    const out = filterCompletions(items, 'ere')
    expect(out.map((i) => i.text)).toEqual(['WHERE', 'ELSEWHERE', 'REFERENCES'])
  })

  it('补全过滤：空词给全部候选（界面自己决定什么时候弹）', () => {
    const items = [item('a'), item('b')]
    expect(filterCompletions(items, '', 10).map((i) => i.text)).toEqual(['a', 'b'])
  })

  it('补全过滤：同一个插入文本只留一条（大小写不同的重复项会变鬼影）', () => {
    const items = [item('orders'), item('ORDERS'), item('orders')]
    expect(filterCompletions(items, 'ord').map((i) => i.text)).toEqual(['orders'])
  })

  it('补全过滤：limit 生效且顺序稳定', () => {
    const items = [item('aa1'), item('aa2'), item('aa3')]
    const first = filterCompletions(items, 'aa', 2).map((i) => i.text)
    const again = filterCompletions(items, 'aa', 2).map((i) => i.text)
    expect(first).toEqual(['aa1', 'aa2'])
    expect(again).toEqual(first)
  })

  it('对象候选同时给对象名与限定名（两种打法都要能打出来）', () => {
    const items = objectCompletions([{ schema: 'app', name: 'orders' }])
    expect(items.map((i) => i.text)).toEqual(['orders', 'app.orders'])
    expect(items.every((i) => i.kind === 'object')).toBe(true)
  })

  it('关键字候选来自同一份名单且不重复', () => {
    const items = keywordCompletions()
    expect(items.length).toBeGreaterThan(30)
    expect(new Set(items.map((i) => i.text)).size).toBe(items.length)
    expect(items.some((i) => i.text === 'SELECT')).toBe(true)
  })

  it('高亮片段：拼回来逐字等于原文', () => {
    const sql = "select id, 'a;b' -- c\nfrom app.accounts"
    const tokens: SqlToken[] = [
      { kind: 'keyword', start: 0, end: 6 },
      { kind: 'punctuation', start: 6, end: 7 },
      { kind: 'ident', start: 7, end: 9 },
      { kind: 'punctuation', start: 9, end: 11 },
      { kind: 'string', start: 11, end: 16 },
      { kind: 'punctuation', start: 16, end: 17 },
      { kind: 'line_comment', start: 17, end: 22 },
    ]
    const pieces = highlightPieces(sql, tokens)
    expect(pieces.map((p) => p.text).join('')).toBe(sql)
    expect(pieces[0]).toEqual({ text: 'select', kind: 'keyword' })
  })

  it('高亮片段：单元越界或乱序时不崩，剩下的按普通文本渲染', () => {
    const sql = 'select 1'
    const bad: SqlToken[] = [
      { kind: 'keyword', start: 0, end: 6 },
      { kind: 'number', start: 999, end: 1000 }, // 越界
      { kind: 'number', start: 2, end: 3 }, // 乱序（回到已渲染位置之前）
    ]
    const pieces = highlightPieces(sql, bad)
    expect(pieces.map((p) => p.text).join('')).toBe(sql)
  })

  it('高亮片段：空输入给空结果', () => {
    expect(highlightPieces('', [])).toEqual([])
  })

  it('挑选要显示的那一段：优先第一条失败的', () => {
    const outcomes = [
      { ok: true, result: { rows: [1] } },
      { ok: false, result: null },
      { ok: true, result: { rows: [2] } },
    ]
    expect(pickDisplayedOutcome(outcomes)).toBe(1)
  })

  it('挑选要显示的那一段：没有失败时取最后一条有结果的', () => {
    const outcomes = [
      { ok: true, result: { rows: [1] } },
      { ok: true, result: null },
      { ok: true, result: { rows: [2] } },
    ]
    expect(pickDisplayedOutcome(outcomes)).toBe(2)
    expect(pickDisplayedOutcome([])).toBeNull()
  })

  it('结果摘要：写语句报影响行数、查询报行数、失败就说失败', () => {
    expect(outcomeSummary({ ok: false, result: null })).toBe('失败')
    expect(outcomeSummary({ ok: true, result: { columns: [], rows: [], affected: 3 } })).toBe('影响 3 行')
    expect(outcomeSummary({ ok: true, result: { columns: ['a'], rows: [1, 2], affected: null } })).toBe('2 行')
    expect(outcomeSummary({ ok: true, result: null })).toBe('完成')
  })
})

// ── FR-EXEC-14：执行目标判定 ───────────────────────────────────────────────────
//
// 守四条：选区优先 / 空白选区不算 / 整篇不 trim / 来源标注如实。

describe('FR-EXEC-14 执行目标判定', () => {
  it('有选区 ⇒ 只跑选区', () => {
    const r = executionTarget('SELECT 1;\nSELECT 2;', 'SELECT 2;')
    expect(r.source).toBe('selection')
    expect(r.sql).toBe('SELECT 2;')
  })

  it('没有选区 ⇒ 跑整篇', () => {
    const r = executionTarget('SELECT 1;\nSELECT 2;', null)
    expect(r.source).toBe('whole')
    expect(r.sql).toBe('SELECT 1;\nSELECT 2;')
  })

  it('选区只有空白 ⇒ 不算选区，按整篇走（不能因为框了空格就什么都不跑）', () => {
    for (const blank of ['', '   ', '\n\t ']) {
      const r = executionTarget('SELECT 1;', blank)
      expect(r.source, `选区=${JSON.stringify(blank)}`).toBe('whole')
      expect(r.sql).toBe('SELECT 1;')
    }
  })

  it('整篇原样返回（不 trim —— trim 会让行号与错误定位错位）', () => {
    const whole = '  SELECT 1;\n\n'
    const r = executionTarget(whole, '')
    expect(r.sql).toBe(whole)
  })

  it('选区原样返回（含前导空白也要原样带出去）', () => {
    const withIndent = '    SELECT 1;'
    const r = executionTarget('x', withIndent)
    expect(r.sql).toBe(withIndent)
  })
})
