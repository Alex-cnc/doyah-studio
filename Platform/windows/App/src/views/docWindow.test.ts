// 长文分段渲染的纯函数判据（`FR-R-12-02` ②「1 万字级不卡」能机械验证的那一半）。
//
// 钉七件事：短文档**原样交回同一份数组**（没切片、没复制）· 阈值边界 · 切片不改原数组 ·
// 续窗只增不减且夹取 · 行号→块下标（精确 / 落在两块之间 / 在开头之前 / 越界）· 近底判定的边界 ·
// 字数统计（含代码块 / 表格 / 嵌套；空白与媒体说明不算）。
import { describe, expect, it } from 'vitest'
import type { MdBlock, MdDocument } from '../ipc'
import {
  DOC_NEAR_BOTTOM_PX,
  DOC_WINDOW_FIRST,
  DOC_WINDOW_LIMIT,
  DOC_WINDOW_STEP,
  blocksFor,
  docStats,
  firstWindow,
  indexForLine,
  nearBottom,
  nextWindow,
  windowForLine,
  windowOf,
} from '../plugins/retro/docWindow'

function span(text: string) {
  return { text, bold: false, italic: false, code: false, target: null }
}

/** 一块一段，行号 = 序号 + 1（正文里最小的形状，够判窗口）。 */
function paragraphs(count: number): MdBlock[] {
  const blocks: MdBlock[] = []
  for (let index = 0; index < count; index += 1) {
    blocks.push({ line: index + 1, kind: { type: 'paragraph', spans: [span(`第 ${index + 1} 段`)] } })
  }
  return blocks
}

function doc(blocks: MdBlock[]): MdDocument {
  return { version: 1, blocks }
}

describe('长文分段渲染窗口', () => {
  it('a_short_report_gets_back_the_very_same_block_array_so_nothing_changes_for_it', () => {
    const document = doc(paragraphs(DOC_WINDOW_LIMIT))
    expect(blocksFor(document, 0)).toBe(document.blocks)
    expect(firstWindow(document.blocks.length)).toBe(DOC_WINDOW_LIMIT)
    expect(windowOf(document, 0)).toEqual({
      shown: DOC_WINDOW_LIMIT,
      total: DOC_WINDOW_LIMIT,
      remaining: 0,
      limited: false,
    })
  })

  it('one_block_over_the_limit_switches_to_the_first_window_and_says_what_is_left', () => {
    const document = doc(paragraphs(DOC_WINDOW_LIMIT + 1))
    const visible = blocksFor(document, firstWindow(document.blocks.length))
    expect(visible).toHaveLength(DOC_WINDOW_FIRST)
    // 切片是**新数组**（原数组一个成员都没动）
    expect(visible).not.toBe(document.blocks)
    expect(document.blocks).toHaveLength(DOC_WINDOW_LIMIT + 1)
    expect(windowOf(document, DOC_WINDOW_FIRST)).toEqual({
      shown: DOC_WINDOW_FIRST,
      total: DOC_WINDOW_LIMIT + 1,
      remaining: DOC_WINDOW_LIMIT + 1 - DOC_WINDOW_FIRST,
      limited: true,
    })
  })

  it('a_broken_window_number_is_clamped_instead_of_blanking_the_body', () => {
    const document = doc(paragraphs(200))
    expect(blocksFor(document, -5)).toHaveLength(0)
    expect(blocksFor(document, Number.NaN)).toHaveLength(0)
    expect(blocksFor(document, 9_999)).toHaveLength(200)
    expect(blocksFor(null, 10)).toEqual([])
  })

  it('the_window_only_grows_and_stops_at_the_end', () => {
    expect(nextWindow(DOC_WINDOW_FIRST, 200)).toBe(DOC_WINDOW_FIRST + DOC_WINDOW_STEP)
    expect(nextWindow(180, 200)).toBe(200)
    expect(nextWindow(200, 200)).toBe(200)
    // 短文档：一窗到底
    expect(nextWindow(0, DOC_WINDOW_LIMIT)).toBe(DOC_WINDOW_LIMIT)
  })

  it('a_heading_line_maps_to_the_block_that_holds_it', () => {
    const blocks: MdBlock[] = [
      { line: 1, kind: { type: 'heading', level: 1, spans: [span('标题')] } },
      { line: 4, kind: { type: 'paragraph', spans: [span('正文')] } },
      { line: 9, kind: { type: 'heading', level: 2, spans: [span('第二节')] } },
    ]
    const document = doc(blocks)
    expect(indexForLine(document, 1)).toBe(0)
    expect(indexForLine(document, 9)).toBe(2)
    // 落在两块之间 ⇒ 退到「包含这一行」的那一块（解析器改过行号口径时不至于跳空）
    expect(indexForLine(document, 6)).toBe(1)
    // 在第一块之前 ⇒ 从头开始；超出最后一块 ⇒ 最后一块
    expect(indexForLine(document, 0)).toBe(0)
    expect(indexForLine(document, 999)).toBe(2)
    expect(indexForLine(doc([]), 3)).toBe(-1)
  })

  it('jumping_from_the_outline_extends_the_window_but_never_shrinks_it', () => {
    const document = doc(paragraphs(200))
    // 目标在第 150 块 ⇒ 至少铺到 150 块
    expect(windowForLine(document, 150, DOC_WINDOW_FIRST)).toBe(150)
    // 已经铺得比目标更多 ⇒ 原样（不会把读过的段落收回去）
    expect(windowForLine(document, 2, 180)).toBe(180)
    // 空文档 ⇒ 不动
    expect(windowForLine(doc([]), 3, 5)).toBe(0)
  })

  it('near_bottom_needs_known_metrics_and_a_real_scroll_range', () => {
    const base = { clientHeight: 600, scrollHeight: 2000 }
    expect(nearBottom({ ...base, scrollTop: 2000 - 600 - DOC_NEAR_BOTTOM_PX })).toBe(true)
    expect(nearBottom({ ...base, scrollTop: 2000 - 600 - DOC_NEAR_BOTTOM_PX - 1 })).toBe(false)
    // 内容没撑出滚动条 ⇒ 不续（否则每次滚动都白加一窗）
    expect(nearBottom({ scrollTop: 0, clientHeight: 600, scrollHeight: 600 })).toBe(false)
    // 尺寸读不到 ⇒ 判否（宁可不续，也不在未知尺寸上乱续）
    expect(nearBottom({ scrollTop: 0, clientHeight: Number.NaN, scrollHeight: 2000 })).toBe(false)
    expect(nearBottom({ scrollTop: -1, clientHeight: 600, scrollHeight: 2000 })).toBe(false)
  })

  it('the_word_count_includes_nested_prose_and_skips_whitespace_and_media_captions', () => {
    const document = doc([
      { line: 1, kind: { type: 'heading', level: 1, spans: [span('本周 速览')] } },
      { line: 2, kind: { type: 'paragraph', spans: [span('芯片'), span('走强')] } },
      { line: 3, kind: { type: 'codeFence', language: 'sql', text: 'select 1;\nselect 2;' } },
      {
        line: 4,
        kind: {
          type: 'table',
          alignments: ['none', 'none'],
          header: [[span('列一')], [span('列二')]],
          rows: [[[span('甲')], [span('乙')]]],
        },
      },
      {
        line: 5,
        kind: { type: 'listItem', number: null, checked: null, spans: [span('一条')], children: [{ line: 6, kind: { type: 'paragraph', spans: [span('嵌套')] } }] },
      },
      { line: 7, kind: { type: 'quote', children: [{ line: 7, kind: { type: 'paragraph', spans: [span('引用')] } }] } },
      { line: 8, kind: { type: 'media', media: 'image', alt: '说明不算正文', target: 'assets/a.png' } },
    ])
    const stats = docStats(document)
    expect(stats.blocks).toBe(7)
    // 本周速览(4) + 芯片(2) + 走强(2) + code 16 + 表 6 + 一条(2) + 嵌套(2) + 引用(2) = 36
    expect(stats.chars).toBe(36)
    expect(docStats(null)).toEqual({ blocks: 0, chars: 0 })
  })
})
