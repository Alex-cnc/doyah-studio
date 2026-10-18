// 左栏归组 / 过滤的**纯函数判据**（`FR-R-13-08` 判据①的折叠与过滤）。
//
// 挂载测只能证明「画出来了」；归组键的退化情形（没日期 / 没月份 / 期号也不像年份）
// 在这里逐条钉住，否则界面只是「看起来分了组」。
import { describe, expect, it } from 'vitest'
// 同 `cardMeta.test.ts`：测试住 `views/`、被测函数住插件目录 —— 插件边界判据（不许 import vitest）不变。
import type { RetroCard } from '../ipc'
import { filterCards, groupCards, periodKey } from '../plugins/retro/periodIndex'

function card(period: string, extra: Partial<RetroCard> = {}): RetroCard {
  return {
    period,
    title: `第 ${period} 期`,
    dateStart: '2026-10-12',
    dateEnd: '2026-10-18',
    tags: ['周报'],
    cover: null,
    generatedAt: '2026-10-18T09:30:00+08:00',
    published: '',
    ...extra,
  }
}

describe('periodKey 归组键', () => {
  it('date_start_wins_and_gives_year_and_month', () => {
    expect(periodKey(card('2026-W42', { dateStart: '2026-03-02', dateEnd: '2026-03-08' }))).toEqual({
      year: '2026',
      month: '03',
    })
  })

  it('a_missing_start_falls_back_to_the_end_date', () => {
    expect(periodKey(card('2026-W41', { dateStart: '', dateEnd: '2025-12-28' }))).toEqual({
      year: '2025',
      month: '12',
    })
  })

  it('with_no_dates_at_all_only_the_year_comes_from_the_period_name', () => {
    // 只有年没有月 ⇒ 月记空串，界面画「月份未标注」，不编一个 01
    expect(periodKey(card('2024-W07', { dateStart: '', dateEnd: '' }))).toEqual({ year: '2024', month: '' })
  })

  it('a_period_name_that_is_not_year_shaped_says_unknown_rather_than_guessing', () => {
    expect(periodKey(card('试做-第3期', { dateStart: '', dateEnd: '' }))).toEqual({ year: '', month: '' })
  })

  it('a_broken_date_is_ignored_instead_of_being_read_as_a_year', () => {
    expect(periodKey(card('2026-W42', { dateStart: '2026/10/12', dateEnd: '' }))).toEqual({
      year: '2026',
      month: '',
    })
  })
})

describe('groupCards 分组', () => {
  it('groups_keep_the_incoming_order_and_the_cards_inside_keep_theirs', () => {
    const groups = groupCards([
      card('2026-W42', { dateStart: '2026-10-12' }),
      card('2026-W41', { dateStart: '2026-10-05' }),
      card('2026-W39', { dateStart: '2026-09-21' }),
      card('2025-W50', { dateStart: '2025-12-08' }),
    ])

    expect(groups.map((group) => group.year)).toEqual(['2026', '2025'])
    expect(groups[0].count).toBe(3)
    expect(groups[0].months.map((month) => month.month)).toEqual(['10', '09'])
    // 组内顺序 = 传入顺序（上游已是最新在前，这里不重排）
    expect(groups[0].months[0].cards.map((entry) => entry.period)).toEqual(['2026-W42', '2026-W41'])
    expect(groups[1].months[0].cards.map((entry) => entry.period)).toEqual(['2025-W50'])
  })

  it('the_same_month_seen_twice_lands_in_one_bucket_not_two_headers', () => {
    const groups = groupCards([
      card('2026-W42', { dateStart: '2026-10-12' }),
      card('2025-W50', { dateStart: '2025-12-08' }),
      card('2026-W39', { dateStart: '2026-10-01' }),
    ])

    expect(groups.map((group) => group.year)).toEqual(['2026', '2025'])
    expect(groups[0].months).toHaveLength(1)
    expect(groups[0].months[0].cards).toHaveLength(2)
    expect(groups[0].count).toBe(2)
  })

  it('cards_with_no_year_shaped_anything_still_form_one_group', () => {
    const groups = groupCards([
      card('试做-第3期', { dateStart: '', dateEnd: '' }),
      card('试做-第2期', { dateStart: '', dateEnd: '' }),
    ])

    expect(groups).toHaveLength(1)
    expect(groups[0].year).toBe('')
    expect(groups[0].months).toHaveLength(1)
    expect(groups[0].months[0].month).toBe('')
    expect(groups[0].count).toBe(2)
  })

  it('an_empty_input_is_an_empty_list_not_a_phantom_group', () => {
    expect(groupCards([])).toEqual([])
  })
})

describe('filterCards 关键词过滤', () => {
  const cards = [
    card('2026-W42', { title: '芯片与半导体 · 第 42 周', tags: ['周报', '半导体'] }),
    card('2026-W41', { title: '新能源车 · 第 41 周', tags: ['周报', '汽车'] }),
    card('2025-W50', { title: '年度回顾', tags: ['总结'], dateStart: '2025-12-08', dateEnd: '2025-12-14' }),
  ]

  it('an_empty_query_returns_everything_untouched', () => {
    expect(filterCards(cards, '')).toBe(cards)
    expect(filterCards(cards, '   ')).toBe(cards)
  })

  it('a_query_matches_the_title_case_insensitively', () => {
    expect(filterCards(cards, '半导体').map((entry) => entry.period)).toEqual(['2026-W42'])
  })

  it('a_query_matches_the_period_name', () => {
    expect(filterCards(cards, 'w41').map((entry) => entry.period)).toEqual(['2026-W41'])
  })

  it('a_query_matches_a_tag', () => {
    expect(filterCards(cards, '总结').map((entry) => entry.period)).toEqual(['2025-W50'])
  })

  it('a_query_matches_a_date_range', () => {
    expect(filterCards(cards, '2025-12').map((entry) => entry.period)).toEqual(['2025-W50'])
  })

  it('several_words_are_all_required_not_any', () => {
    // 「半导体」命中第 42 期，「2025」只命中年度回顾 ⇒ AND 之后空
    expect(filterCards(cards, '半导体 2025')).toEqual([])
    expect(filterCards(cards, '半导体 周报').map((entry) => entry.period)).toEqual(['2026-W42'])
  })

  it('a_query_matching_nothing_gives_an_empty_list_not_the_whole_set', () => {
    expect(filterCards(cards, '量子计算')).toEqual([])
  })
})
