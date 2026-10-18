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
import type { MdDocument, MdSpan, RetroCard, RetroMedia, RetroProblem, RetroSnapshot } from '../ipc'

const state: {
  snapshot: RetroSnapshot
  snapshotFailure: { message: string; hint: string } | null
  reports: Record<string, MdDocument>
  reportMedia: Record<string, RetroMedia[]>
  assetFailures: string[]
  assetCalls: Array<[string, string]>
  reportFailures: Record<string, { message: string; hint: string }>
  reportCalls: string[]
} = {
  snapshot: { root: 'C:\\Users\\Alex\\AppData\\Roaming\\DoyahStudio\\retro\\packages', cards: [], problems: [] },
  snapshotFailure: null,
  reports: {},
  reportMedia: {},
  assetFailures: [],
  assetCalls: [],
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
    return { period, path: `${period}/report.md`, bytes: 42, document, media: state.reportMedia[period] ?? [] }
  }),
  retroAsset: vi.fn(async (period: string, target: string) => {
    state.assetCalls.push([period, target])
    if (state.assetFailures.includes(target)) throw { message: `包里没有这个媒体：${target}`, hint: '' }
    return new ArrayBuffer(8)
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

/** 一个媒体块（正文里独占一行的那种）。 */
function mediaDocument(media: 'image' | 'video', alt: string, target: string): MdDocument {
  return { version: 1, blocks: [{ line: 3, kind: { type: 'media', media, alt, target } }] }
}

function mediaSlot(target: string, state_: RetroMedia['state'] = 'ok', extra: Partial<RetroMedia> = {}): RetroMedia {
  return {
    target,
    state: state_,
    path: state_ === 'ok' ? `C:\\Users\\Alex\\AppData\\Roaming\\DoyahStudio\\retro\\packages\\2026-W42\\${target}` : null,
    reason: null,
    mime: target.endsWith('.mp4') ? 'video/mp4' : 'image/png',
    ...extra,
  }
}

beforeEach(() => {
  state.snapshot = { root: 'C:\\Users\\Alex\\AppData\\Roaming\\DoyahStudio\\retro\\packages', cards: [], problems: [] }
  state.snapshotFailure = null
  state.reports = {}
  state.reportMedia = {}
  state.assetFailures = []
  state.assetCalls = []
  state.reportFailures = {}
  state.reportCalls = []
  // happy-dom 没实现 blob URL：给一个确定性的替身（判据只关心「挂上了没有」）
  let counter = 0
  Object.assign(URL, {
    createObjectURL: vi.fn(() => `blob:mock-${++counter}`),
    revokeObjectURL: vi.fn(),
  })
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

  // ── 正文媒体（FR-R-12-03：图片 / 视频就地渲染）──────────────────────────────────

  it('an_addressable_image_is_rendered_inline_from_its_bytes', async () => {
    state.snapshot.cards = [card('2026-W42', '带图的')]
    state.reports['2026-W42'] = mediaDocument('image', '净值曲线', 'assets/curve.png')
    state.reportMedia['2026-W42'] = [mediaSlot('assets/curve.png')]
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('.retro__card').trigger('click')
    await flushPromises()

    // 只对「判定 ok」的目标取字节（缺的 / 外链的不该发请求）
    expect(state.assetCalls).toEqual([['2026-W42', 'assets/curve.png']])
    const image = wrapper.get('[data-role="retro-media-image"]')
    expect(image.attributes('src')).toBe('blob:mock-1')
    expect(image.attributes('alt')).toBe('净值曲线')
    // 媒体出现在正文位置（不是堆到文末）：它与文档容器的直接子节点就是同一个块
    expect(wrapper.get('[data-role="retro-document"]').find('[data-role="retro-media-image"]').exists()).toBe(true)
  })

  it('a_video_is_rendered_with_native_controls', async () => {
    state.snapshot.cards = [card('2026-W42', '带录屏的')]
    state.reports['2026-W42'] = mediaDocument('video', '复盘录屏', 'assets/clip.mp4')
    state.reportMedia['2026-W42'] = [mediaSlot('assets/clip.mp4')]
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('.retro__card').trigger('click')
    await flushPromises()

    const video = wrapper.get('[data-role="retro-media-video"]')
    expect(video.attributes('src')).toBe('blob:mock-1')
    // 进度 / 音量 / 全屏都交给原生控件（不自造一套播放器）
    expect(video.attributes('controls')).toBeDefined()
  })

  it('a_missing_or_external_media_becomes_a_placeholder_with_the_file_name', async () => {
    state.snapshot.cards = [card('2026-W42', '缺图的')]
    state.reports['2026-W42'] = mediaDocument('image', '缺的图', 'assets/gone.png')
    state.reportMedia['2026-W42'] = [mediaSlot('assets/gone.png', 'missing', { reason: '包里没有 assets/gone.png' })]
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('.retro__card').trigger('click')
    await flushPromises()

    // 缺文件 ⇒ 不发请求、画占位（文件名 + 原因都要在，不然用户不知道少了什么）
    expect(state.assetCalls).toEqual([])
    expect(wrapper.find('[data-role="retro-media-image"]').exists()).toBe(false)
    const note = wrapper.get('[data-role="retro-media-note"]')
    expect(note.text()).toContain('包里没有这个文件')
    expect(note.text()).toContain('gone.png')
    expect(note.text()).toContain('包里没有 assets/gone.png')
    expect(wrapper.get('[data-media="image"]').attributes('data-state')).toBe('missing')
  })

  it('a_media_whose_bytes_fail_to_load_says_so_instead_of_staying_blank', async () => {
    state.snapshot.cards = [card('2026-W42', '读不出的')]
    state.reports['2026-W42'] = mediaDocument('image', '图', 'assets/broken.png')
    state.reportMedia['2026-W42'] = [mediaSlot('assets/broken.png')]
    state.assetFailures = ['assets/broken.png']
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('.retro__card').trigger('click')
    await flushPromises()

    // 判定说 ok、字节却没读到 ⇒ 就地改成占位 + 原因（不许白屏）
    expect(wrapper.find('[data-role="retro-media-image"]').exists()).toBe(false)
    expect(wrapper.get('[data-role="retro-media-note"]').text()).toContain('这个媒体读不出来')
  })

  it('clicking_an_image_opens_the_zoom_layer', async () => {
    state.snapshot.cards = [card('2026-W42', '点图放大')]
    state.reports['2026-W42'] = mediaDocument('image', '净值曲线', 'assets/curve.png')
    state.reportMedia['2026-W42'] = [mediaSlot('assets/curve.png')]
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('.retro__card').trigger('click')
    await flushPromises()

    expect(wrapper.find('[data-role="retro-zoom"]').exists()).toBe(false)
    await wrapper.get('[data-role="retro-media-image"]').trigger('click')
    const zoom = wrapper.get('[data-role="retro-zoom"]')
    expect(zoom.get('[data-role="retro-zoom-image"]').attributes('src')).toBe('blob:mock-1')
    expect(zoom.text()).toContain('净值曲线')
    // 关掉
    await wrapper.get('.retro__zoom-close').trigger('click')
    expect(wrapper.find('[data-role="retro-zoom"]').exists()).toBe(false)
  })

  // ── 左栏按年·月折叠 + 关键词过滤（FR-R-13-08 判据①）────────────────────────────

  it('cards_are_grouped_by_year_then_month_with_counts_on_the_headers', async () => {
    state.snapshot.cards = [
      card('2026-W42', '十月中', { dateStart: '2026-10-12', dateEnd: '2026-10-18' }),
      card('2026-W39', '九月末', { dateStart: '2026-09-21', dateEnd: '2026-09-27' }),
      card('2025-W50', '去年末', { dateStart: '2025-12-08', dateEnd: '2025-12-14' }),
    ]
    const wrapper = mount(RetroView)
    await flushPromises()

    const years = wrapper.findAll('.retro__year')
    expect(years).toHaveLength(2)
    // 年表头：文字 + 该年卡片数（3 期里 2 期在 2026）
    expect(wrapper.get('[data-role="retro-year-2026"]').text()).toContain('2026 年')
    expect(wrapper.get('[data-role="retro-year-2026"]').text()).toContain('2')
    expect(wrapper.get('[data-role="retro-year-2025"]').text()).toContain('1')
    // 月表头：10 月 / 9 月
    expect(wrapper.get('[data-role="retro-month-2026-10"]').text()).toContain('10 月')
    expect(wrapper.get('[data-role="retro-month-2026-09"]').text()).toContain('9 月')
    // 卡片顺序保持上游给的「新在前」
    expect(wrapper.findAll('.retro__card').map((node) => node.attributes('data-period'))).toEqual([
      '2026-W42',
      '2026-W39',
      '2025-W50',
    ])
  })

  it('a_card_without_dates_or_a_year_shaped_name_lands_in_an_explicit_unknown_group', async () => {
    state.snapshot.cards = [card('试做-第3期', '没日期的', { dateStart: '', dateEnd: '' })]
    const wrapper = mount(RetroView)
    await flushPromises()

    // 不编年份：如实写「年份未标注 / 月份未标注」
    const year = wrapper.get('[data-role="retro-year-unknown"]')
    expect(year.text()).toContain('年份未标注')
    expect(wrapper.get('[data-role="retro-month-unknown-unknown"]').text()).toContain('月份未标注')
    expect(wrapper.findAll('.retro__card')).toHaveLength(1)
  })

  it('folding_a_year_hides_its_cards_and_unfolding_brings_them_back', async () => {
    state.snapshot.cards = [
      card('2026-W42', '今年的'),
      card('2025-W50', '去年的', { dateStart: '2025-12-08', dateEnd: '2025-12-14' }),
    ]
    const wrapper = mount(RetroView)
    await flushPromises()
    expect(wrapper.findAll('.retro__card')).toHaveLength(2)

    const head = wrapper.get('[data-role="retro-year-2026"]')
    expect(head.attributes('aria-expanded')).toBe('true')
    await head.trigger('click')
    expect(head.attributes('aria-expanded')).toBe('false')
    // 只收起这一年：另一年的卡片还在（收起不是「清空」）
    expect(wrapper.findAll('.retro__card').map((node) => node.attributes('data-period'))).toEqual(['2025-W50'])

    await head.trigger('click')
    expect(head.attributes('aria-expanded')).toBe('true')
    expect(wrapper.findAll('.retro__card')).toHaveLength(2)
  })

  it('folding_a_month_leaves_the_other_month_of_the_same_year_open', async () => {
    state.snapshot.cards = [
      card('2026-W42', '十月', { dateStart: '2026-10-12' }),
      card('2026-W39', '九月', { dateStart: '2026-09-21' }),
    ]
    const wrapper = mount(RetroView)
    await flushPromises()

    await wrapper.get('[data-role="retro-month-2026-10"]').trigger('click')
    expect(wrapper.findAll('.retro__card').map((node) => node.attributes('data-period'))).toEqual(['2026-W39'])
    // 年表头还在（收起月份不该连带收起整年）
    expect(wrapper.get('[data-role="retro-year-2026"]').attributes('aria-expanded')).toBe('true')
  })

  it('typing_a_keyword_narrows_the_list_and_shows_how_many_match', async () => {
    state.snapshot.cards = [
      card('2026-W42', '芯片与半导体 · 第 42 周', { tags: ['周报', '半导体'] }),
      card('2026-W41', '新能源车 · 第 41 周', { tags: ['周报'] }),
    ]
    const wrapper = mount(RetroView)
    await flushPromises()

    await wrapper.get('[data-role="retro-filter"]').setValue('半导体')
    await flushPromises()

    expect(wrapper.findAll('.retro__card').map((node) => node.attributes('data-period'))).toEqual(['2026-W42'])
    expect(wrapper.get('[data-role="retro-count"]').text()).toContain('1 / 2 期匹配')
    // 清空按钮出现（键鼠都关掉筛选，不必删字）
    await wrapper.get('[data-role="retro-filter-clear"]').trigger('click')
    await flushPromises()
    expect(wrapper.findAll('.retro__card')).toHaveLength(2)
    expect(wrapper.get('[data-role="retro-count"]').text()).toContain('共 2 期')
  })

  it('a_filter_expands_a_folded_group_so_the_hit_is_never_hidden', async () => {
    state.snapshot.cards = [
      card('2026-W42', '芯片与半导体 · 第 42 周', { tags: ['半导体'] }),
      card('2025-W50', '去年的', { dateStart: '2025-12-08', dateEnd: '2025-12-14' }),
    ]
    const wrapper = mount(RetroView)
    await flushPromises()

    // 先收起 2026，再筛「半导体」——命中项必须可见，不能藏在折叠组里
    await wrapper.get('[data-role="retro-year-2026"]').trigger('click')
    expect(wrapper.findAll('.retro__card').map((node) => node.attributes('data-period'))).toEqual(['2025-W50'])

    await wrapper.get('[data-role="retro-filter"]').setValue('半导体')
    await flushPromises()
    expect(wrapper.findAll('.retro__card').map((node) => node.attributes('data-period'))).toEqual(['2026-W42'])
  })

  it('clearing_the_filter_restores_the_fold_state_the_user_left', async () => {
    state.snapshot.cards = [
      card('2026-W42', '芯片与半导体 · 第 42 周', { tags: ['半导体'] }),
      card('2025-W50', '去年的', { dateStart: '2025-12-08', dateEnd: '2025-12-14' }),
    ]
    const wrapper = mount(RetroView)
    await flushPromises()

    await wrapper.get('[data-role="retro-year-2026"]').trigger('click')
    await wrapper.get('[data-role="retro-filter"]').setValue('半导体')
    await flushPromises()
    await wrapper.get('[data-role="retro-filter-clear"]').trigger('click')
    await flushPromises()

    // 筛选期间强制展开，但清空后回到用户原来收着的样子（不是被悄悄改成全展开）
    expect(wrapper.get('[data-role="retro-year-2026"]').attributes('aria-expanded')).toBe('false')
    expect(wrapper.findAll('.retro__card').map((node) => node.attributes('data-period'))).toEqual(['2025-W50'])
  })

  it('a_keyword_that_matches_nothing_says_so_with_the_keyword_instead_of_a_blank_list', async () => {
    state.snapshot.cards = [card('2026-W42', '芯片与半导体 · 第 42 周')]
    const wrapper = mount(RetroView)
    await flushPromises()

    await wrapper.get('[data-role="retro-filter"]').setValue('量子计算')
    await flushPromises()

    expect(wrapper.findAll('.retro__card')).toHaveLength(0)
    const note = wrapper.get('[data-role="retro-no-match"]')
    expect(note.text()).toContain('没有匹配')
    expect(note.text()).toContain('量子计算')
    // 空态那句「还没有周报」不许冒充「筛不到」（包是在的）
    expect(wrapper.find('[data-role="retro-empty"]').exists()).toBe(false)
  })

  // ── 卡片封面与生成时间（FR-R-13-08 判据① 的最后两个字段）──────────────────────────

  it('a_cover_is_fetched_through_the_asset_command_and_drawn_as_a_thumbnail', async () => {
    state.snapshot.cards = [card('2026-W42', '带封面的', { cover: 'assets/cover.png' })]
    const wrapper = mount(RetroView)
    await flushPromises()

    // 走的正是 Rust 判过的那条包内相对路径（不自己拼绝对路径）
    expect(state.assetCalls).toEqual([['2026-W42', 'assets/cover.png']])
    const image = wrapper.get('[data-role="retro-cover-image"]')
    expect(image.attributes('src')).toBe('blob:mock-1')
    expect(image.attributes('alt')).toContain('带封面的')
  })

  it('a_card_without_a_cover_says_no_cover_and_asks_for_nothing', async () => {
    state.snapshot.cards = [card('2026-W42', '没封面的')]
    const wrapper = mount(RetroView)
    await flushPromises()

    // 没有封面就不该发请求（省一次 IPC，也不会误读别的文件）
    expect(state.assetCalls).toEqual([])
    expect(wrapper.get('[data-role="retro-cover-empty"]').text()).toContain('无封面')
    expect(wrapper.find('[data-role="retro-cover-image"]').exists()).toBe(false)
  })

  it('a_cover_whose_bytes_fail_says_so_instead_of_showing_a_blank_block', async () => {
    state.snapshot.cards = [card('2026-W42', '封面读不出的', { cover: 'assets/gone.png' })]
    state.assetFailures = ['assets/gone.png']
    const wrapper = mount(RetroView)
    await flushPromises()

    expect(wrapper.find('[data-role="retro-cover-image"]').exists()).toBe(false)
    expect(wrapper.get('[data-role="retro-cover-failed"]').text()).toContain('封面读不出来')
  })

  it('the_generated_time_is_shown_as_written_and_a_missing_one_says_not_stated', async () => {
    state.snapshot.cards = [
      card('2026-W42', '写了时间', { generatedAt: '2026-10-18T09:30:00+08:00' }),
      card('2026-W41', '没写时间', { generatedAt: '' }),
    ]
    const wrapper = mount(RetroView)
    await flushPromises()

    const stamps = wrapper.findAll('[data-role="retro-generated"]').map((node) => node.text())
    // 墙上时间照抄（不按时区再转一次），缺了就如实写「未标注」
    expect(stamps[0]).toContain('2026-10-18 09:30')
    expect(stamps[1]).toContain('生成时间未标注')
  })

  // ── 正文块级渲染（`FR-R-13-08` 判据②：标题层级 / 表格 / 引用 / 列表与源文一致）──────────
  //
  // 这一组钉的是「解析结果 → 界面」的最后一段：块模型只有 Rust 一份实现（`Db/src/markdown.rs`），
  // 这里按同一份形状喂进来，断言 DOM 与源文逐项对上。`tsc` 从不校验模板，只有挂载能证明接线对。

  const span = (value: string): MdSpan => ({ text: value, bold: false, italic: false, code: false, target: null })

  /** 一份含标题三层 / 表格 / 引用 / 两级列表 / 分隔线的正文（与 Rust 侧那条端到端测试同形）。 */
  function structureDocument(): MdDocument {
    return {
      version: 1,
      blocks: [
        { line: 1, kind: { type: 'heading', level: 1, spans: [span('芯片周报')] } },
        { line: 3, kind: { type: 'heading', level: 2, spans: [span('一、本周行情')] } },
        { line: 5, kind: { type: 'heading', level: 3, spans: [span('1.1 存储器')] } },
        {
          line: 7,
          kind: {
            type: 'table',
            alignments: ['left', 'center', 'right'],
            header: [[span('品类')], [span('涨幅')], [span('备注')]],
            rows: [
              [[span('DRAM')], [span('+3.2%')], [span('现货')]],
              [[span('NAND')], [span('-1.1%')], [span('合约')]],
            ],
          },
        },
        { line: 14, kind: { type: 'rule' } },
        {
          line: 16,
          kind: {
            type: 'quote',
            children: [{ line: 16, kind: { type: 'paragraph', spans: [span('行情只做记录，不构成建议。')] } }],
          },
        },
        {
          line: 18,
          kind: {
            type: 'listItem',
            number: null,
            checked: null,
            spans: [span('供给端')],
            children: [
              { line: 19, kind: { type: 'listItem', number: null, checked: null, spans: [span('三大厂减产')], children: [] } },
            ],
          },
        },
        { line: 21, kind: { type: 'listItem', number: 1, checked: null, spans: [span('需求端回升')], children: [] } },
      ],
    }
  }

  /** 打开哪一期就把这份正文挂上去（判据只看渲染，不看取数）。 */
  async function mountStructure(): Promise<ReturnType<typeof mount>> {
    state.snapshot.cards = [card('2026-W42', '芯片与半导体 · 第 42 周')]
    state.reports['2026-W42'] = structureDocument()
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('.retro__card').trigger('click')
    await flushPromises()
    return wrapper
  }

  it('heading_levels_keep_their_level_text_and_size_tier', async () => {
    const wrapper = await mountStructure()
    const headings = wrapper.findAll('.retro-md__heading')
    // 层级按源文：h1 / h2 / h3，不塌成同一个标签
    expect(headings.map((node) => node.element.tagName)).toEqual(['H1', 'H2', 'H3'])
    expect(headings.map((node) => node.text())).toEqual(['芯片周报', '一、本周行情', '1.1 存储器'])
    // 字号分档走 data-level（样式按档取令牌；UA 缺省的 h5/h6 会小过正文）
    expect(headings.map((node) => node.attributes('data-level'))).toEqual(['1', '2', '3'])
  })

  it('a_table_keeps_its_columns_cells_and_alignment_and_scrolls_when_wide', async () => {
    const wrapper = await mountStructure()
    // 宽了横向滚动，不把右区撑破
    const scroller = wrapper.get('[data-role="retro-table-scroll"]')
    const table = scroller.get('.retro-md__table')

    const headers = table.findAll('th')
    expect(headers.map((cell) => cell.text())).toEqual(['品类', '涨幅', '备注'])
    const cells = table.findAll('td')
    expect(cells.map((cell) => cell.text())).toEqual(['DRAM', '+3.2%', '现货', 'NAND', '-1.1%', '合约'])
    // 对齐按源文的 :--: 落（列序不能错位）
    expect((headers[0].element as HTMLElement).style.textAlign).toBe('left')
    expect((headers[1].element as HTMLElement).style.textAlign).toBe('center')
    expect((headers[2].element as HTMLElement).style.textAlign).toBe('right')
    expect((cells[1].element as HTMLElement).style.textAlign).toBe('center')
    // 两行数据（不是把行并成一行，也不是只画表头）
    expect(table.findAll('tbody tr')).toHaveLength(2)
  })

  it('a_quote_renders_its_nested_paragraph_in_place', async () => {
    const wrapper = await mountStructure()
    const quote = wrapper.get('blockquote')
    expect(quote.text()).toContain('行情只做记录，不构成建议。')
    // 引用里是真的段落块（不是把整段当纯文本塞进来）
    expect(quote.find('.retro-md__p').exists()).toBe(true)
    // 位置也按源文序：引用排在表格之后、列表之前
    const order = wrapper.findAll('[data-line]').map((node) => node.attributes('data-line'))
    expect(order.indexOf('16')).toBeGreaterThan(order.indexOf('7'))
    expect(order.indexOf('16')).toBeLessThan(order.indexOf('18'))
  })

  it('lists_keep_their_markers_and_nest_one_indent_per_level', async () => {
    const wrapper = await mountStructure()
    const items = wrapper.findAll('.retro-md__item')
    // 两条顶层 + 一条嵌套
    expect(items).toHaveLength(3)
    expect(items[0].text()).toContain('供给端')
    expect(items[2].text()).toContain('需求端回升')
    // 记号按源文：无序是圆点、有序是序号
    expect(items[0].get('.retro-md__bullet').text()).toBe('•')
    expect(items[2].get('.retro-md__bullet').text()).toBe('1.')
    // 嵌套层级缩进递增（父 0px / 子 18px），并且层级数一路带下去
    const parent = items.find((node) => node.attributes('data-level') === '0' && node.text().includes('供给端'))!
    const child = items.find((node) => node.attributes('data-level') === '1')!
    expect((parent.element as HTMLElement).style.paddingLeft).toBe('0px')
    expect((child.element as HTMLElement).style.paddingLeft).toBe('18px')
    expect(child.attributes('data-level')).toBe('1')
  })

  it('a_rule_and_the_block_order_match_the_source', async () => {
    const wrapper = await mountStructure()
    expect(wrapper.findAll('hr.retro-md__rule')).toHaveLength(1)
  })
})
