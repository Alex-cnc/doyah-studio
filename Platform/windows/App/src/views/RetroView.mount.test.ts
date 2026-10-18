// @vitest-environment happy-dom
// 回放插件的周报阅读面（`FR-R-12-01` / `FR-R-12-02`）**挂载判据**。
//
// 为什么必须挂一次：`.vue` 不在 `tsc --noEmit` 的程序里 —— 组件里调一个没 import 的名字、
// 模板引用一个没定义的属性，类型门一律 rc=0，点开才炸。这里钉六件事：
//   ① 空库 ⇒ 画「还没有周报」，**并把放包目录显示出来**（用户得知道包该放哪儿）；
//   ② 有包 ⇒ 一期一张卡，标题 / 期号 / 日期范围都画出来；
//   ③ 点一张卡 ⇒ 右区按 `report.md` 的解析结果渲染，且**请求的正是那一期**；
//   ④ 坏包 ⇒ 逐条列出（不静默消失，也不拖垮好包）；
//   ⑤ 读目录失败 ⇒ 把服务端原话 + 提示两段都摆出来（不是灰着不说）；
//   ⑥ 切到打不开的一期 ⇒ 上一期的正文**不许残留**（否则用户以为看的是这一期）。
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import type { MdDocument, RetroCard, RetroProblem, RetroSnapshot } from '../ipc'

const state: {
  snapshot: RetroSnapshot
  snapshotFailure: { message: string; hint: string } | null
  reports: Record<string, MdDocument>
  reportFailures: Record<string, { message: string; hint: string }>
  reportCalls: string[]
} = {
  snapshot: { root: 'C:\\Users\\Alex\\AppData\\Roaming\\DoyahStudio\\retro\\packages', cards: [], problems: [] },
  snapshotFailure: null,
  reports: {},
  reportFailures: {},
  reportCalls: [],
}

vi.mock('../ipc', () => ({
  retroPackages: vi.fn(async () => {
    if (state.snapshotFailure) throw state.snapshotFailure
    return state.snapshot
  }),
  retroReport: vi.fn(async (period: string) => {
    state.reportCalls.push(period)
    const failure = state.reportFailures[period]
    if (failure) throw failure
    const document = state.reports[period]
    if (!document) throw { message: `找不到这一期：${period}`, hint: '' }
    return { period, path: `${period}/report.md`, bytes: 42, document }
  }),
}))

import RetroView from '../plugins/retro/RetroView.vue'

function heading(text: string): MdDocument {
  return {
    version: 1,
    blocks: [{ line: 1, kind: { type: 'heading', level: 1, spans: [{ text, bold: true, italic: false, code: false, target: null }] } }],
  }
}

function card(period: string, title: string, extra: Partial<RetroCard> = {}): RetroCard {
  return {
    period,
    title,
    dateStart: '2026-10-12',
    dateEnd: '2026-10-18',
    tags: ['周报'],
    cover: null,
    generatedAt: '2026-10-18T09:30:00+08:00',
    ...extra,
  }
}

function problem(period: string, message: string): RetroProblem {
  return { period, message }
}

beforeEach(() => {
  state.snapshot = { root: 'C:\\Users\\Alex\\AppData\\Roaming\\DoyahStudio\\retro\\packages', cards: [], problems: [] }
  state.snapshotFailure = null
  state.reports = {}
  state.reportFailures = {}
  state.reportCalls = []
})

describe('RetroView 周报阅读面', () => {
  it('an_empty_library_says_so_and_shows_where_packages_go', async () => {
    const wrapper = mount(RetroView)
    await flushPromises()
    const empty = wrapper.get('[data-role="retro-empty"]')
    expect(empty.text()).toContain('还没有周报')
    // 空态必须给出目录：只说「没有」等于让用户自己找地方
    expect(empty.text()).toContain('DoyahStudio')
    expect(empty.text()).toContain('packages')
  })

  it('every_package_on_disk_becomes_one_card_with_title_period_and_range', async () => {
    state.snapshot.cards = [card('2026-W42', '芯片与半导体 · 第 42 周'), card('2026-W41', '上周', { dateStart: '', dateEnd: '' })]
    const wrapper = mount(RetroView)
    await flushPromises()
    const cards = wrapper.findAll('.retro__card')
    expect(cards).toHaveLength(2)
    expect(cards[0].text()).toContain('芯片与半导体 · 第 42 周')
    expect(cards[0].text()).toContain('2026-W42')
    expect(cards[0].text()).toContain('2026-10-12')
    // 没有日期就如实写「日期未标注」，不编一个
    expect(cards[1].text()).toContain('日期未标注')
    expect(wrapper.text()).toContain('共 2 期')
  })

  it('clicking_a_card_renders_that_periods_report', async () => {
    state.snapshot.cards = [card('2026-W42', '本期')]
    state.reports['2026-W42'] = heading('芯片周报正文')
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('.retro__card').trigger('click')
    await flushPromises()
    expect(state.reportCalls).toEqual(['2026-W42'])
    const document = wrapper.get('[data-role="retro-document"]')
    expect(document.text()).toContain('芯片周报正文')
    // 没选之前右区是「左侧选一期」，选了之后这句要让位
    expect(wrapper.find('[data-role="retro-pick"]').exists()).toBe(false)
  })

  it('a_broken_package_is_listed_one_by_one_without_hiding_the_good_ones', async () => {
    state.snapshot.cards = [card('2026-W42', '好的一期')]
    state.snapshot.problems = [
      problem('2026-W41', '缺 index.json：这个目录不算一个周报包'),
      problem('2026-W40', 'report.md 不是 UTF-8（第 3 字节处断开）'),
    ]
    const wrapper = mount(RetroView)
    await flushPromises()
    expect(wrapper.findAll('.retro__card')).toHaveLength(1)
    const problems = wrapper.get('[data-role="retro-problems"]')
    expect(problems.text()).toContain('有 2 处读不出来')
    expect(problems.text()).toContain('2026-W41')
    expect(problems.text()).toContain('缺 index.json')
    expect(problems.text()).toContain('不是 UTF-8')
  })

  it('a_failing_scan_shows_the_message_and_the_hint', async () => {
    state.snapshotFailure = { message: '读 Retro 包目录失败：拒绝访问', hint: '确认该目录存在且可读' }
    const wrapper = mount(RetroView)
    await flushPromises()
    const failure = wrapper.get('[data-role="retro-load-failure"]')
    expect(failure.text()).toContain('读 Retro 包目录失败：拒绝访问')
    expect(failure.text()).toContain('确认该目录存在且可读')
  })

  it('switching_to_a_broken_period_clears_the_previous_body', async () => {
    state.snapshot.cards = [card('2026-W42', '能读的'), card('2026-W43', '读不了的')]
    state.reports['2026-W42'] = heading('上一期的正文')
    state.reportFailures['2026-W43'] = { message: '2026-W43：report.md 是空文件', hint: '把正文另存为 UTF-8' }
    const wrapper = mount(RetroView)
    await flushPromises()

    await wrapper.findAll('.retro__card')[0].trigger('click')
    await flushPromises()
    expect(wrapper.get('[data-role="retro-document"]').text()).toContain('上一期的正文')

    await wrapper.findAll('.retro__card')[1].trigger('click')
    await flushPromises()
    // 打不开就说打不开，且旧正文必须消失（否则用户以为看的是这一期）
    expect(wrapper.find('[data-role="retro-document"]').exists()).toBe(false)
    const failure = wrapper.get('[data-role="retro-report-failure"]')
    expect(failure.text()).toContain('这一期的正文打不开')
    expect(failure.text()).toContain('report.md 是空文件')
  })
})
