// 目录锚点抽取的纯函数判据（`FR-R-13-08` ①：大纲 = 正文标题的派生，不是第二套解析）。
//
// 钉五件事：层级与文字取自源文 · 越界层级夹到 1~6 · 同一行只出一条 · 空标题不被吞掉 · 无标题 ⇒ 空大纲。
import { describe, expect, it } from 'vitest'
import type { MdBlock, MdDocument } from '../ipc'
import { clampHeadingLevel, headingAnchor, headingText, outlineOf } from '../plugins/retro/outline'

function span(text: string, extra: Partial<{ bold: boolean; italic: boolean; code: boolean }> = {}) {
  return { text, bold: false, italic: false, code: false, target: null, ...extra }
}

function headingBlock(line: number, level: number, spans: ReturnType<typeof span>[]): MdBlock {
  return { line, kind: { type: 'heading', level, spans } }
}

function doc(blocks: MdBlock[]): MdDocument {
  return { version: 1, blocks }
}

describe('周报正文目录锚点', () => {
  it('lists_the_headings_in_source_order_with_their_levels_and_text', () => {
    const outline = outlineOf(
      doc([
        headingBlock(1, 1, [span('本周速览')]),
        { line: 3, kind: { type: 'paragraph', spans: [span('正文')] } },
        headingBlock(5, 2, [span('进展')]),
        headingBlock(9, 3, [span('安卓')]),
      ]),
    )
    expect(outline).toEqual([
      { id: 'retro-h-1', level: 1, text: '本周速览', line: 1 },
      { id: 'retro-h-5', level: 2, text: '进展', line: 5 },
      { id: 'retro-h-9', level: 3, text: '安卓', line: 9 },
    ])
    // 段落不进大纲
    expect(outline.some((entry) => entry.line === 3)).toBe(false)
  })

  it('joins_inline_spans_and_drops_the_styling', () => {
    const outline = outlineOf(
      doc([headingBlock(2, 2, [span('第 '), span('38', { bold: true }), span(' 轮')])]),
    )
    expect(outline[0]?.text).toBe('第 38 轮')
  })

  it('clamps_a_broken_level_instead_of_letting_it_rank_the_outline', () => {
    expect(clampHeadingLevel(0)).toBe(1)
    expect(clampHeadingLevel(-3)).toBe(1)
    expect(clampHeadingLevel(9)).toBe(6)
    expect(clampHeadingLevel(Number.NaN)).toBe(1)
    expect(clampHeadingLevel(2.7)).toBe(2)
    const outline = outlineOf(doc([headingBlock(1, 0, [span('a')]), headingBlock(2, 12, [span('b')])]))
    expect(outline.map((entry) => entry.level)).toEqual([1, 6])
  })

  it('a_document_without_headings_has_no_outline_at_all', () => {
    expect(outlineOf(doc([{ line: 1, kind: { type: 'paragraph', spans: [span('只有正文')] } }]))).toEqual([])
    expect(outlineOf(doc([]))).toEqual([])
    expect(outlineOf(null)).toEqual([])
  })

  it('an_empty_heading_still_shows_up_because_it_is_still_a_section', () => {
    const outline = outlineOf(doc([headingBlock(4, 2, [span('   ')])]))
    expect(outline).toHaveLength(1)
    expect(outline[0]?.text).toBe('')
  })

  it('two_headings_on_one_line_produce_one_entry_so_a_click_never_needs_a_tie_break', () => {
    const outline = outlineOf(doc([headingBlock(7, 2, [span('甲')]), headingBlock(7, 2, [span('乙')])]))
    expect(outline).toHaveLength(1)
    expect(outline[0]?.text).toBe('甲')
  })

  it('the_anchor_helper_and_the_renderer_agree_on_the_id_shape', () => {
    expect(headingAnchor(12)).toBe('retro-h-12')
    expect(outlineOf(doc([headingBlock(12, 1, [span('x')])]))[0]?.id).toBe(headingAnchor(12))
  })

  it('heading_text_is_empty_for_a_non_heading_block', () => {
    expect(headingText({ line: 1, kind: { type: 'paragraph', spans: [span('正文')] } })).toBe('')
  })
})
