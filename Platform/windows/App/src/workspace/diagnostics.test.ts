// 诊断绘制层的判据（FR-EDIT-56）：只守**切片不变量**，不在这里验 lint 规则
// （规则在 Rust `Db/src/lint.rs`，那边有 15 条行为单测；这里验的是「叠标记不会改坏文本」）。
import { describe, expect, it } from 'vitest'
import { decoratePieces, worstSeverity, type Diagnostic } from './diagnostics'
import type { HighlightPiece } from '../sql/editor'

const pieces: HighlightPiece[] = [
  { text: 'select ', kind: 'keyword' },
  { text: "'abc", kind: 'string' },
  { text: ' from t', kind: 'ident' },
]

const join = (list: { text: string }[]): string => list.map((piece) => piece.text).join('')

describe('诊断绘制层（把已算好的区间叠到高亮片段上）', () => {
  it('没有诊断时逐段照原（一个字符都不许动）', () => {
    const out = decoratePieces(pieces, [])
    expect(join(out)).toBe("select 'abc from t")
    expect(out.every((piece) => piece.severity === undefined)).toBe(true)
    expect(out.map((piece) => piece.kind)).toEqual(['keyword', 'string', 'ident'])
  })

  it('诊断跨片段时切成多段，拼接仍逐字等于原文', () => {
    const diagnostics: Diagnostic[] = [{ start: 3, end: 13, severity: 'error', message: '字符串没闭合' }]
    const out = decoratePieces(pieces, diagnostics)
    expect(join(out)).toBe("select 'abc from t")
    // 落在区间里的片段带 severity，区间外的不带
    const marked = out.filter((piece) => piece.severity === 'error').map((piece) => piece.text).join('')
    expect(marked).toBe("ect 'abc f")
    expect(out[0].text).toBe('sel')
    expect(out[0].severity).toBeUndefined()
  })

  it('越界与反向的区间被夹住，空区间直接忽略', () => {
    const diagnostics: Diagnostic[] = [
      { start: -5, end: 999, severity: 'warning', message: '全段' },
      { start: 4, end: 4, severity: 'error', message: '空区间' },
      { start: 9, end: 2, severity: 'info', message: '反着给的' },
    ]
    const out = decoratePieces(pieces, diagnostics)
    expect(join(out)).toBe("select 'abc from t")
    // 全段 warning 生效；空区间不产出；反向区间按夹正后的 [2,9) 算
    expect(out.every((piece) => piece.severity === 'warning')).toBe(true)
  })

  it('同一段落在多条诊断里取最严重的那个', () => {
    const diagnostics: Diagnostic[] = [
      { start: 0, end: 6, severity: 'info', message: '提醒' },
      { start: 0, end: 6, severity: 'error', message: '错' },
      { start: 0, end: 6, severity: 'warning', message: '警' },
    ]
    const out = decoratePieces(pieces, diagnostics)
    expect(out[0].text).toBe('select')
    expect(out[0].severity).toBe('error')
  })

  it('严重度比较：error 比 warning 重、warning 比 info 重', () => {
    expect(worstSeverity(['info', 'warning'])).toBe('warning')
    expect(worstSeverity(['warning', 'error'])).toBe('error')
    expect(worstSeverity([])).toBeUndefined()
  })

  it('诊断区间正好落在片段边界上时不多切出空段', () => {
    const diagnostics: Diagnostic[] = [{ start: 7, end: 11, severity: 'error', message: '引号没闭合' }]
    const out = decoratePieces(pieces, diagnostics)
    expect(join(out)).toBe("select 'abc from t")
    expect(out.every((piece) => piece.text.length > 0)).toBe(true)
    expect(out.find((piece) => piece.severity === 'error')?.text).toBe("'abc")
  })
})
