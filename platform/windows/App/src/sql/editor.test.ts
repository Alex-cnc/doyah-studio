import { describe, expect, it } from 'vitest'
import {
  applyCompletionItem,
  executionTarget,
  filterCompletions,
  highlightPieces,
  keywordCompletions,
  objectCompletions,
  outcomeSummary,
  pickDisplayedOutcome,
  snippetCompletions,
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

// ── 高亮偏移口径（2026-10-18 修的真实缺陷）：JS 下标是 UTF-16 码元，不是字节 ──────────────
describe('高亮偏移口径 = JS 字符串下标（UTF-16 码元）', () => {
  const sql = "select 1 -- 中文注释\nselect '😀' from t"
  /** JS 下标（`String.indexOf` / `length` 就是码元口径）。 */
  const jsTokens = (): SqlToken[] => {
    const comment = sql.indexOf('-- 中文注释')
    const emojiString = sql.indexOf("'😀'")
    const from = sql.indexOf('from')
    return [
      { kind: 'keyword', start: 0, end: 6 },
      { kind: 'number', start: 7, end: 8 },
      { kind: 'line_comment', start: comment, end: comment + '-- 中文注释'.length },
      { kind: 'string', start: emojiString, end: emojiString + "'😀'".length },
      { kind: 'keyword', start: from, end: from + 4 },
    ]
  }

  it('中文注释 + 表情之后的关键字仍被单独切出来（片段的文字就是原文那一段）', () => {
    const pieces = highlightPieces(sql, jsTokens())
    expect(pieces.map((p) => p.text).join('')).toBe(sql)
    expect(pieces).toContainEqual({ text: 'from', kind: 'keyword' })
    expect(pieces).toContainEqual({ text: '-- 中文注释', kind: 'line_comment' })
    expect(pieces).toContainEqual({ text: "'😀'", kind: 'string' })
  })

  it('给字节偏移会切歪（这就是被修掉的缺陷，不许回退）', () => {
    const encoder = new TextEncoder()
    const byteAt = (index: number): number => encoder.encode(sql.slice(0, index)).length
    const byteTokens = jsTokens().map((token) => ({
      ...token,
      start: byteAt(token.start),
      end: byteAt(token.end),
    }))
    const pieces = highlightPieces(sql, byteTokens)
    expect(pieces.some((p) => p.text === 'from' && p.kind === 'keyword')).toBe(false)
  })
})

// ── FR-EDIT-59 片段：补全清单里的一类候选，接受后展开模板 ──────────────────────────────
describe('片段补全（FR-EDIT-59）', () => {
  it('片段表有 4 个触发词，模板都带一个 $0（最终光标）', () => {
    const items = snippetCompletions()
    expect(items.map((i) => i.text)).toEqual(['sel', 'ins', 'upd', 'del'])
    for (const item of items) {
      expect(item.kind, item.text).toBe('snippet')
      expect(item.snippet, item.text).toContain('$0')
      // 说明要能让人看懂这是片段（界面直接显示 detail）
      expect(item.detail, item.text).toContain('片段')
    }
  })

  it('片段候选与关键字同列：前缀 se 既能命中 SELECT 也能命中 sel', () => {
    const items = filterCompletions([...keywordCompletions(), ...snippetCompletions()], 'se')
    expect(items.some((i) => i.text === 'SELECT' && i.kind === 'keyword')).toBe(true)
    expect(items.some((i) => i.text === 'sel' && i.kind === 'snippet')).toBe(true)
  })

  it('接受片段 ⇒ 插入展开后的骨架、占位换成默认值、光标落在 $0', () => {
    const sel = snippetCompletions().find((i) => i.text === 'sel')!
    const result = applyCompletionItem('sel', 3, sel)
    expect(result.text).toBe('SELECT *\nFROM table\nWHERE cond')
    expect(result.text).not.toContain('${')
    expect(result.caret).toBe(result.text.length)
  })

  it('$0 在中间时光标落在那里，不是文末', () => {
    const item: CompletionItem = { text: 'x', kind: 'snippet', detail: '片段 · 试', snippet: 'SELECT $0 FROM t' }
    const result = applyCompletionItem('x', 1, item)
    expect(result.text).toBe('SELECT  FROM t')
    expect(result.caret).toBe(7)
  })

  it('普通候选仍走老口径：替换光标前的词、光标在插入文本之后', () => {
    const item: CompletionItem = { text: 'SELECT', kind: 'keyword', detail: '关键字' }
    const result = applyCompletionItem('sel from', 3, item)
    expect(result.text).toBe('SELECT from')
    expect(result.caret).toBe(6)
  })

  it('词中间接受候选只替换光标前那个词，右边的文字不动', () => {
    const item: CompletionItem = { text: 'count', kind: 'keyword', detail: '关键字' }
    const result = applyCompletionItem('select cou(*) from t', 10, item)
    expect(result.text).toBe('select count(*) from t')
    expect(result.caret).toBe(12)
  })
})
