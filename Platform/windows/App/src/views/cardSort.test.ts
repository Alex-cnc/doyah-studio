// 左栏排序（`FR-R-12-01` 判据②「期号可排序」）的**纯函数判据**。
//
// 为什么测试放在 `views/`：插件目录（`src/plugins/**`）里的 `.ts` 不许 import `vitest`
// （`App/tools/check-plugins.mjs` 的 import 白名单），所以插件内的纯函数一律在这里钉。
//
// 钉五件事：
//   ① 默认档**原样返回同一个数组**（沿用上游顺序，前端不产生第二套默认排序真值）；
//   ② 期号 Z→A / A→Z 各一套口径；
//   ③ 重排**不动传入的数组**（调用方可能还拿着上游那份）；
//   ④ 同期号撞车时保持上游相对次序（稳定排序）；
//   ⑤ 界面下拉里给的档位就是这三个（别让模板多一个纯函数不认的值）。
import { describe, expect, it } from 'vitest'
import type { RetroCard } from '../ipc'
import { CARD_SORTS, sortCards } from '../plugins/retro/cardSort'

function card(period: string, title = period): RetroCard {
  return {
    period,
    title,
    dateStart: '2026-10-12',
    dateEnd: '2026-10-18',
    tags: ['周报'],
    cover: null,
    generatedAt: '2026-10-18T09:30:00+08:00',
    published: '2026-10-18',
  }
}

/** 上游（Rust）给的样子：新的在前。 */
function upstream(): RetroCard[] {
  return [card('2026-W42', '第 42 周'), card('2026-W41', '第 41 周'), card('2026-W01', '第 1 周')]
}

describe('sortCards 左栏排序口径', () => {
  it('the_default_tier_hands_back_the_upstream_array_untouched', () => {
    const cards = upstream()
    expect(sortCards(cards, 'default')).toBe(cards)
  })

  it('period_desc_puts_the_largest_period_first', () => {
    const order = sortCards(upstream(), 'period-desc').map((entry) => entry.period)
    expect(order).toEqual(['2026-W42', '2026-W41', '2026-W01'])
  })

  it('period_asc_puts_the_smallest_period_first', () => {
    const order = sortCards(upstream(), 'period-asc').map((entry) => entry.period)
    expect(order).toEqual(['2026-W01', '2026-W41', '2026-W42'])
  })

  it('reordering_never_touches_the_array_it_was_given', () => {
    const cards = upstream()
    const sorted = sortCards(cards, 'period-asc')
    expect(sorted).not.toBe(cards)
    expect(cards.map((entry) => entry.period)).toEqual(['2026-W42', '2026-W41', '2026-W01'])
  })

  it('two_cards_with_the_same_period_keep_their_upstream_relative_order', () => {
    // 坏包 / 手改目录名理论上不会重号，但真撞上时次序不能因切档而跳来跳去
    const first = card('2026-W40', '先到的同号')
    const second = card('2026-W40', '后到的同号')
    const sorted = sortCards([first, second], 'period-asc')
    expect(sorted.map((entry) => entry.title)).toEqual(['先到的同号', '后到的同号'])
    expect(sortCards([second, first], 'period-asc').map((entry) => entry.title)).toEqual([
      '后到的同号',
      '先到的同号',
    ])
  })

  it('the_tiers_offered_in_the_dropdown_are_exactly_the_ones_the_function_understands', () => {
    expect([...CARD_SORTS]).toEqual(['default', 'period-desc', 'period-asc'])
  })
})
