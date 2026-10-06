// 节点类型 → 图标（FR-META-06）—— 穷举 + **未知类型兜底**
//
// 重点：这条需求最容易被"看着做了、其实没做"（几个类型共用一个图标，或未知类型直接当表）。
// 所以判据里既有"每类一个专属图标"的正例，也有"认不出给兜底"的那一例。
import { describe, it, expect } from 'vitest'

import { NODE_GLYPH_FALLBACK, knownNodeKinds, nodeGlyph } from './nodeIcon'

describe('节点类型 → 图标（FR-META-06）', () => {
  it('需求点名的六类各有一个专属图标：库 / 模式 / 表 / 视图 / 列 / 函数', () => {
    expect(nodeGlyph('database')).toBe('database')
    expect(nodeGlyph('schema')).toBe('schema')
    expect(nodeGlyph('table')).toBe('table')
    expect(nodeGlyph('view')).toBe('view')
    expect(nodeGlyph('column')).toBe('column')
    expect(nodeGlyph('function')).toBe('function')
  })

  it('树上还会出现的其余类型也各有各的图标（不并成同一类）', () => {
    const kinds = knownNodeKinds()
    expect(kinds).toEqual(
      expect.arrayContaining([
        'server',
        'materialized_view',
        'foreign_table',
        'sequence',
        'system',
        'other',
      ]),
    )
    expect(nodeGlyph('materialized_view')).toBe('materializedView')
    expect(nodeGlyph('foreign_table')).toBe('foreignTable')
    expect(nodeGlyph('sequence')).toBe('sequence')
    expect(nodeGlyph('system')).toBe('system')
    expect(nodeGlyph('server')).toBe('server')
  })

  it('穷举：每类一个图标，且**两两不同**（两类共用一个就等于"类型区分"没做）', () => {
    const glyphs = knownNodeKinds().map((kind) => nodeGlyph(kind))
    expect(new Set(glyphs).size).toBe(glyphs.length)
    // 与兜底图标也不能撞（否则"未知"和某一类看起来一样）
    expect(glyphs).not.toContain(NODE_GLYPH_FALLBACK)
  })

  it('未知类型兜底：认不出的都给同一个兜底图标，不抛错、也不冒充成表', () => {
    expect(nodeGlyph('composite_type')).toBe(NODE_GLYPH_FALLBACK)
    expect(nodeGlyph('')).toBe(NODE_GLYPH_FALLBACK)
    expect(nodeGlyph('   ')).toBe(NODE_GLYPH_FALLBACK)
    // 将来服务端多出来的 relkind：兜底，而不是"表"
    expect(nodeGlyph('partitioned_index')).toBe(NODE_GLYPH_FALLBACK)
    expect(nodeGlyph('partitioned_index')).not.toBe(nodeGlyph('table'))
  })

  it('负例：把未知类型当成表（或共用一个"其它"图标）会被上面那条穷举抓红', () => {
    const naive = (kind: string) => (kind === 'view' ? 'view' : 'table')
    // 朴素写法对未知类型也给 'table' —— 与兜底图标不同 ⇒ 判据抓得到
    expect(naive('composite_type')).toBe('table')
    expect(nodeGlyph('composite_type')).not.toBe(naive('composite_type'))
  })

  it('大小写与空白不敏感（服务端 / 手写的拼法都要认）', () => {
    expect(nodeGlyph(' TABLE ')).toBe('table')
    expect(nodeGlyph('Materialized_View')).toBe('materializedView')
  })
})
