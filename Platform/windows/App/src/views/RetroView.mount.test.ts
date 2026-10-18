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
  openCalls: string[]
  openFailures: Record<string, { message: string; hint: string }>
  pickedFolder: string | null
  pickCalls: number
  importResult: { period: string; state: string; message: string; path: string }
  importFailure: { message: string; hint: string } | null
  importCalls: string[]
  batchResult: {
    source: string
    items: Array<{ period: string; state: string; message: string; path: string }>
    scanned: number
    skipped: number
  } | null
  batchFailure: { message: string; hint: string } | null
  batchCalls: string[]
  revealCalls: string[]
  revealFailure: { message: string; hint: string } | null
} = {
  snapshot: { root: 'C:\\Users\\Alex\\AppData\\Roaming\\DoyahStudio\\retro\\packages', cards: [], problems: [] },
  snapshotFailure: null,
  reports: {},
  reportMedia: {},
  assetFailures: [],
  assetCalls: [],
  reportFailures: {},
  reportCalls: [],
  openCalls: [],
  openFailures: {},
  pickedFolder: null,
  pickCalls: 0,
  importResult: { period: '2026-W43', state: 'imported', message: '已导入到 C:\\...\\2026-W43', path: 'C:\\...\\2026-W43' },
  importFailure: null,
  importCalls: [],
  batchResult: null,
  batchFailure: null,
  batchCalls: [],
  revealCalls: [],
  revealFailure: null,
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
  openExternal: vi.fn(async (url: string) => {
    state.openCalls.push(url)
    const failure = state.openFailures[url]
    if (failure) throw failure
    return { program: 'rundll32.exe', args: ['url.dll,FileProtocolHandler', url], scheme: url.startsWith('https') ? 'https' : 'http' }
  }),
  retroImport: vi.fn(async (source: string) => {
    state.importCalls.push(source)
    if (state.importFailure) throw state.importFailure
    return state.importResult
  }),
  retroImportBatch: vi.fn(async (source: string) => {
    state.batchCalls.push(source)
    if (state.batchFailure) throw state.batchFailure
    if (!state.batchResult) throw { message: '没有预置整批结果', hint: '' }
    return state.batchResult
  }),
  retroReveal: vi.fn(async (period: string) => {
    state.revealCalls.push(period)
    if (state.revealFailure) throw state.revealFailure
    return {
      program: 'explorer.exe',
      args: [`C:\\Users\\Alex\\AppData\\Roaming\\DoyahStudio\\retro\\packages\\${period}`],
      workingDirectory: null,
      used: 'explorer',
    }
  }),
}))

// 目录选择器（`FR-R-12-04`）：插件经**挂点契约的宿主能力** `pickFolder` 拿选择器
// （实现仍在 `shell/dialogs.ts`，插件边界判据不许插件直接 import shell 内部模块）。
// 打桩这一处即断言「点按钮 ⇒ 选择器真的被调」，不用假装系统对话框存在。
vi.mock('../shell/pluginRegistry', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../shell/pluginRegistry')>()),
  pickFolder: vi.fn(async () => {
    state.pickCalls += 1
    return state.pickedFolder
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
    published: '',
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
  state.openCalls = []
  state.openFailures = {}
  state.pickedFolder = null
  state.pickCalls = 0
  state.importResult = { period: '2026-W43', state: 'imported', message: '已导入到 C:\\...\\2026-W43', path: 'C:\\...\\2026-W43' }
  state.importFailure = null
  state.importCalls = []
  state.batchResult = null
  state.batchFailure = null
  state.batchCalls = []
  state.revealCalls = []
  state.revealFailure = null
  // 显示设定（字号档）落在 localStorage：逐条测之间清干净，免得上一档带进来
  globalThis.localStorage?.clear?.()
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

  // ── 外链交给系统默认处理 + 媒体汇总（FR-R-13-09 ②③④）─────────────────────────

  it('an_external_media_offers_a_click_that_hands_it_to_the_system_instead_of_loading_it', async () => {
    const url = 'https://example.com/clip.mp4'
    state.snapshot.cards = [card('2026-W42', '外链视频')]
    state.reports['2026-W42'] = mediaDocument('video', '外部录屏', url)
    state.reportMedia['2026-W42'] = [mediaSlot(url, 'external', { reason: '外链：视图内不加载（防出网），需要时自己用浏览器打开' })]
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('.retro__card').trigger('click')
    await flushPromises()

    // 视图内不加载：没有 video、也没有去取字节
    expect(wrapper.find('[data-role="retro-media-video"]').exists()).toBe(false)
    expect(state.assetCalls).toEqual([])
    // 但要有可点的入口（判据②：不许留白）
    const button = wrapper.get('[data-role="retro-media-open"]')
    expect(button.text()).toBe('用系统默认打开')
    await button.trigger('click')
    await flushPromises()
    expect(state.openCalls).toEqual([url])
  })

  it('a_link_the_system_refuses_says_why_in_place_and_the_placeholder_stays', async () => {
    const url = 'https://example.com/blocked.mp4'
    state.snapshot.cards = [card('2026-W42', '被拒的外链')]
    state.reports['2026-W42'] = mediaDocument('video', '外部录屏', url)
    state.reportMedia['2026-W42'] = [mediaSlot(url, 'external')]
    state.openFailures[url] = { message: '这个链接不能打开：只支持 http / https 外链：file:///C:/Windows/win.ini', hint: '' }
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('.retro__card').trigger('click')
    await flushPromises()

    expect(wrapper.find('[data-role="retro-media-open-failure"]').exists()).toBe(false)
    await wrapper.get('[data-role="retro-media-open"]').trigger('click')
    await flushPromises()

    // 失败要说原因（服务端原话），占位不许消失、也不许假装成功
    expect(wrapper.get('[data-role="retro-media-open-failure"]').text()).toContain('这个链接不能打开')
    expect(wrapper.get('[data-role="retro-media-note"]').text()).toContain('外链')
    expect(wrapper.find('[data-role="retro-media-video"]').exists()).toBe(false)
  })

  it('media_that_cannot_be_shown_inline_is_summarised_in_one_line_with_a_breakdown', async () => {
    state.snapshot.cards = [card('2026-W42', '三种问题')]
    state.reports['2026-W42'] = {
      version: 1,
      blocks: [
        { line: 1, kind: { type: 'media', media: 'image', alt: '缺的', target: 'assets/gone.png' } },
        { line: 3, kind: { type: 'media', media: 'video', alt: '外链', target: 'https://example.com/a.mp4' } },
        { line: 5, kind: { type: 'media', media: 'video', alt: '老格式', target: 'assets/old.avi' } },
      ],
    }
    state.reportMedia['2026-W42'] = [
      mediaSlot('assets/gone.png', 'missing', { reason: '包里没有 assets/gone.png' }),
      mediaSlot('https://example.com/a.mp4', 'external', { reason: '外链：视图内不加载' }),
      mediaSlot('assets/old.avi', 'unsupported', { reason: '格式不在白名单（avi）：只认图片与 mp4 / m4v' }),
    ]
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('.retro__card').trigger('click')
    await flushPromises()

    const summary = wrapper.get('[data-role="retro-media-summary"]')
    expect(summary.text()).toContain('3 处')
    expect(summary.text()).toContain('缺失 1')
    expect(summary.text()).toContain('外链 1')
    expect(summary.text()).toContain('格式不支持 1')
    // 分项是照判定数出来的：三处各一个占位，没有一个变成图 / 视频
    expect(wrapper.findAll('[data-role="retro-media-note"]')).toHaveLength(3)
    expect(wrapper.find('[data-role="retro-media-image"]').exists()).toBe(false)
    expect(wrapper.find('[data-role="retro-media-video"]').exists()).toBe(false)
  })

  it('a_report_whose_media_all_render_has_no_summary_strip', async () => {
    state.snapshot.cards = [card('2026-W42', '都正常')]
    state.reports['2026-W42'] = mediaDocument('image', '图', 'assets/curve.png')
    state.reportMedia['2026-W42'] = [mediaSlot('assets/curve.png')]
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('.retro__card').trigger('click')
    await flushPromises()

    // 否定面：全好了就不许再挂一条「0 处」的横幅（那是噪声，也是假报告）
    expect(wrapper.find('[data-role="retro-media-summary"]').exists()).toBe(false)
    expect(wrapper.find('[data-role="retro-media-image"]').exists()).toBe(true)
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

  it('a_contract_package_shows_its_published_date_and_not_as_a_generated_time', async () => {
    // 契约包（`IR-05` 不变量 4）：只有 `published`，没有 `generatedAt` ——
    // 早先解析器不认 `published`，这种包在卡片上一个时间都不显示。
    state.snapshot.cards = [
      card('2026-W40', '契约包', {
        published: '2026-10-05',
        generatedAt: '',
        dateStart: '2026-09-28',
        dateEnd: '2026-10-04',
      }),
      card('2026-W41', '老包没发布日', { published: '' }),
    ]
    const wrapper = mount(RetroView)
    await flushPromises()

    const published = wrapper.findAll('[data-role="retro-published"]')
    expect(published).toHaveLength(1)
    expect(published[0].text()).toContain('发布 2026-10-05')
    // 发布日**不冒充**生成时间：那一格仍如实说「未标注」
    const stamps = wrapper.findAll('[data-role="retro-generated"]').map((node) => node.text())
    expect(stamps[0]).toContain('生成时间未标注')
    // 范围照包的（Rust 已按期号推好），界面不再自己算
    expect(wrapper.text()).toContain('2026-09-28')
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

  // ── 包导入（`FR-R-12-04` ①③）──────────────────────────────────────────────────
  // 四件事：点按钮真弹选择器 · 取消不报错 · 导进来立刻在列表里 · 拒收/失败把原因原话摆出来。

  it('clicking_import_opens_the_folder_picker_and_puts_the_new_period_in_the_list', async () => {
    state.pickedFolder = 'D:\\inbox\\2026-W43'
    state.importResult = {
      period: '2026-W43',
      state: 'imported',
      message: '已导入到 C:\\...\\packages\\2026-W43',
      path: 'C:\\...\\packages\\2026-W43',
    }
    const wrapper = mount(RetroView)
    await flushPromises()
    // 导入成功后重扫会多出这一期（外壳侧真把包复制进来了）
    state.snapshot.cards = [card('2026-W43', '芯片周报 · 第 43 周')]
    await wrapper.get('[data-role="retro-import"]').trigger('click')
    await flushPromises()

    expect(state.pickCalls).toBe(1)
    expect(state.importCalls).toEqual(['D:\\inbox\\2026-W43'])
    expect(wrapper.get('[data-role="retro-import-result"]').text()).toContain('已导入到')
    // 「导进来」必须真的出现在左列表（否则等于没导入）
    expect(wrapper.text()).toContain('芯片周报 · 第 43 周')
  })

  it('cancelling_the_picker_imports_nothing_and_says_nothing', async () => {
    state.pickedFolder = null
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('[data-role="retro-import"]').trigger('click')
    await flushPromises()

    expect(state.pickCalls).toBe(1)
    expect(state.importCalls).toEqual([])
    expect(wrapper.find('[data-role="retro-import-result"]').exists()).toBe(false)
    expect(wrapper.find('[data-role="retro-import-failure"]').exists()).toBe(false)
  })

  it('a_refused_package_shows_the_reason_verbatim_instead_of_staying_silent', async () => {
    state.pickedFolder = 'D:\\inbox\\2026-W44'
    state.importResult = {
      period: '2026-W44',
      state: 'rejected',
      message: '包里没有 report.md（正文是契约三件之一）',
      path: 'D:\\inbox\\2026-W44',
    }
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('[data-role="retro-import"]').trigger('click')
    await flushPromises()

    const line = wrapper.get('[data-role="retro-import-result"]')
    expect(line.attributes('data-state')).toBe('rejected')
    expect(line.text()).toContain('report.md')
  })

  it('an_import_that_fails_outright_shows_the_message_and_the_hint', async () => {
    state.pickedFolder = 'D:\\not-a-folder'
    state.importFailure = { message: '这不是一个目录：D:\\not-a-folder', hint: '选目录，不要选文件。' }
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('[data-role="retro-import"]').trigger('click')
    await flushPromises()

    const line = wrapper.get('[data-role="retro-import-failure"]')
    expect(line.text()).toContain('不是一个目录')
    expect(line.text()).toContain('选目录，不要选文件。')
  })

  // ── 整批导入（`FR-R-12-04` 批量形态）─────────────────────────────────────────────

  it('importing_a_folder_of_packages_reports_each_one_and_puts_them_in_the_list', async () => {
    state.pickedFolder = 'D:\\inbox'
    state.batchResult = {
      source: 'D:\\inbox',
      items: [
        { period: '2026-W43', state: 'imported', message: '已导入到 C:\\...\\2026-W43', path: 'C:\\...\\2026-W43' },
        { period: '2026-W44', state: 'already', message: '已导入（与库里那份逐字节相同，未覆盖）', path: 'C:\\...\\2026-W44' },
      ],
      scanned: 4,
      skipped: 2,
    }
    const wrapper = mount(RetroView)
    await flushPromises()
    // 整批导完会重扫：两期都该出现在左列表
    state.snapshot.cards = [card('2026-W43', '第 43 周'), card('2026-W44', '第 44 周')]
    await wrapper.get('[data-role="retro-import-batch"]').trigger('click')
    await flushPromises()

    expect(state.pickCalls).toBe(1)
    expect(state.batchCalls).toEqual(['D:\\inbox'])
    const summary = wrapper.get('[data-role="retro-import-batch-result"]')
    expect(summary.text()).toContain('新增 1')
    expect(summary.text()).toContain('已存在 1')
    // 不是包的条目只计数，不逐条刷屏
    expect(wrapper.get('[data-role="retro-import-batch-skipped"]').text()).toContain('2')
    // 逐条明细：两行、态与原因都在
    const items = wrapper.get('[data-role="retro-import-batch-items"]').findAll('li')
    expect(items).toHaveLength(2)
    expect(items.map((item) => item.attributes('data-state'))).toEqual(['imported', 'already'])
    expect(items[1].text()).toContain('逐字节相同')
    // 「导进来」必须真的出现在左列表（否则等于没导入）
    expect(wrapper.text()).toContain('第 43 周')
    expect(wrapper.text()).toContain('第 44 周')
  })

  it('a_folder_without_any_package_says_so_instead_of_reporting_a_fake_success', async () => {
    state.pickedFolder = 'D:\\downloads'
    state.batchResult = { source: 'D:\\downloads', items: [], scanned: 3, skipped: 3 }
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('[data-role="retro-import-batch"]').trigger('click')
    await flushPromises()

    const line = wrapper.get('[data-role="retro-import-batch-result"]')
    expect(line.attributes('data-state')).toBe('empty')
    expect(line.text()).toContain('没有找到周报包')
    // 说清下一步该选哪一层（不是只报「0 条」）
    expect(line.text()).toContain('index.json')
    // 一条明细都不该编
    expect(wrapper.find('[data-role="retro-import-batch-items"]').exists()).toBe(false)
  })

  it('cancelling_the_batch_picker_imports_nothing_and_says_nothing', async () => {
    state.pickedFolder = null
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('[data-role="retro-import-batch"]').trigger('click')
    await flushPromises()

    expect(state.pickCalls).toBe(1)
    expect(state.batchCalls).toEqual([])
    expect(wrapper.find('[data-role="retro-import-batch-result"]').exists()).toBe(false)
    expect(wrapper.find('[data-role="retro-import-failure"]').exists()).toBe(false)
  })

  // ── 打开所在文件夹（本机存储的可见面）──────────────────────────────────────────

  it('reveal_opens_the_selected_periods_folder_and_reports_a_failure_verbatim', async () => {
    state.snapshot.cards = [card('2026-W43', '芯片周报 · 第 43 周')]
    state.reports['2026-W43'] = heading('正文')
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('[data-period="2026-W43"]').trigger('click')
    await flushPromises()

    await wrapper.get('[data-role="retro-reveal"]').trigger('click')
    await flushPromises()
    // 只传期号（路径由 Rust 侧拼，界面给不了任意路径）
    expect(state.revealCalls).toEqual(['2026-W43'])
    expect(wrapper.find('[data-role="retro-reveal-failure"]').exists()).toBe(false)

    // 打不开时：原话 + 提示两段都要在（不静默）
    state.revealFailure = {
      message: '库里没有这一期：2026-W43',
      hint: '点「刷新」看看它还在不在（包可能被移到别处了）。',
    }
    await wrapper.get('[data-role="retro-reveal"]').trigger('click')
    await flushPromises()
    const failure = wrapper.get('[data-role="retro-reveal-failure"]')
    expect(failure.text()).toContain('库里没有这一期')
    expect(failure.text()).toContain('刷新')
  })

  // ── 显示设定：目录锚点 + 字号三档（`FR-R-13-08` ①；只改怎么看，不动包）────────────

  it('the_outline_lists_every_heading_with_its_level_and_text', async () => {
    state.snapshot.cards = [card('2026-W43', '本期')]
    state.reports['2026-W43'] = headings()
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('[data-period="2026-W43"]').trigger('click')
    await flushPromises()

    // 面板默认收起：有标题才有这个入口，条数写在按钮上
    const toggle = wrapper.get('[data-role="retro-outline-toggle"]')
    expect(toggle.text()).toContain('大纲 · 3 节')
    expect(wrapper.find('[data-role="retro-outline"]').exists()).toBe(false)
    await toggle.trigger('click')

    const items = wrapper.findAll('[data-role="retro-outline-item"]')
    expect(items).toHaveLength(3)
    expect(items.map((item) => item.text())).toEqual(['本周速览', '进展', '安卓'])
    // 层级按源文（1 / 2 / 3），不是一律拉平
    expect(items.map((item) => item.attributes('data-level'))).toEqual(['1', '2', '3'])
    // 段落不进大纲（只查大纲面板，不查正文 —— 正文里当然有那段）
    expect(wrapper.get('[data-role="retro-outline"]').text()).not.toContain('正文段落')
  })

  it('clicking_an_outline_entry_marks_only_that_heading', async () => {
    state.snapshot.cards = [card('2026-W43', '本期')]
    state.reports['2026-W43'] = headings()
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('[data-period="2026-W43"]').trigger('click')
    await flushPromises()
    await wrapper.get('[data-role="retro-outline-toggle"]').trigger('click')

    // 还没点时：正文里没有任何一节被标成当前
    expect(wrapper.findAll('.retro-md__heading--active')).toHaveLength(0)

    await wrapper.findAll('[data-role="retro-outline-item"]')[1].trigger('click')
    const active = wrapper.findAll('.retro-md__heading--active')
    expect(active).toHaveLength(1)
    // 标的是「进展」那一节（行 5），且锚点 id 与大纲条目同一个拼法
    expect(active[0].text()).toBe('进展')
    expect(active[0].attributes('id')).toBe('retro-h-5')
    expect(wrapper.findAll('[data-role="retro-outline-item"]')[1].attributes('aria-current')).toBe('location')
    expect(wrapper.findAll('[data-role="retro-outline-item"]')[0].attributes('aria-current')).toBeUndefined()

    // 再点另一条：只留一个当前项（不是越点越多）
    await wrapper.findAll('[data-role="retro-outline-item"]')[2].trigger('click')
    const after = wrapper.findAll('.retro-md__heading--active')
    expect(after).toHaveLength(1)
    expect(after[0].text()).toBe('安卓')
    // 只读：点大纲不重读正文、不触发任何导入 / 打开目录
    expect(state.reportCalls).toEqual(['2026-W43'])
    expect(state.importCalls).toEqual([])
    expect(state.revealCalls).toEqual([])
  })

  it('a_report_without_headings_offers_no_outline_at_all', async () => {
    state.snapshot.cards = [card('2026-W43', '本期')]
    state.reports['2026-W43'] = heading('只有一节')
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('[data-period="2026-W43"]').trigger('click')
    await flushPromises()
    // 一个标题也算大纲（能跳），但没有标题时不该出现一个「0 条」的空入口
    expect(wrapper.find('[data-role="retro-outline-toggle"]').exists()).toBe(true)

    state.reports['2026-W43'] = { version: 1, blocks: [{ line: 1, kind: { type: 'paragraph', spans: [{ text: '纯正文', bold: false, italic: false, code: false, target: null }] } }] }
    state.snapshot.cards = [card('2026-W43', '本期'), card('2026-W44', '下一期')]
    state.reports['2026-W44'] = state.reports['2026-W43']
    const second = mount(RetroView)
    await flushPromises()
    await second.get('[data-period="2026-W44"]').trigger('click')
    await flushPromises()
    expect(second.find('[data-role="retro-outline-toggle"]').exists()).toBe(false)
    expect(second.find('[data-role="retro-outline"]').exists()).toBe(false)
  })

  it('the_font_tier_changes_the_container_class_without_reloading_the_report', async () => {
    state.snapshot.cards = [card('2026-W43', '本期')]
    state.reports['2026-W43'] = headings()
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('[data-period="2026-W43"]').trigger('click')
    await flushPromises()

    const document_ = () => wrapper.get('[data-role="retro-document"]')
    expect(document_().classes()).toContain('retro__document--md')
    expect(wrapper.get('[data-role="retro-font-current"]').text()).toBe('标准')

    await wrapper.get('[data-role="retro-font-up"]').trigger('click')
    expect(document_().classes()).toContain('retro__document--lg')
    expect(wrapper.get('[data-role="retro-font-current"]').text()).toBe('大')
    // 偏好落进 localStorage（下次开应用还是这一档）
    expect(globalThis.localStorage.getItem('doyah.retro.docFont')).toBe('lg')
    // 到顶就停：大档时「更大」是灰的
    expect(wrapper.get('[data-role="retro-font-up"]').attributes('disabled')).toBeDefined()

    await wrapper.get('[data-role="retro-font-down"]').trigger('click')
    await wrapper.get('[data-role="retro-font-down"]').trigger('click')
    expect(document_().classes()).toContain('retro__document--sm')
    expect(globalThis.localStorage.getItem('doyah.retro.docFont')).toBe('sm')
    expect(wrapper.get('[data-role="retro-font-down"]').attributes('disabled')).toBeDefined()

    // 只改观感：正文没被重读（`FR-R-13-08` ①「显示设定不得改变包内容」）
    expect(state.reportCalls).toEqual(['2026-W43'])
    expect(state.importCalls).toEqual([])
    expect(state.batchCalls).toEqual([])
  })

  it('switching_period_clears_the_outline_selection', async () => {
    state.snapshot.cards = [card('2026-W43', '本期'), card('2026-W42', '上一期')]
    state.reports['2026-W43'] = headings()
    state.reports['2026-W42'] = heading('上一期正文')
    const wrapper = mount(RetroView)
    await flushPromises()
    await wrapper.get('[data-period="2026-W43"]').trigger('click')
    await flushPromises()
    await wrapper.get('[data-role="retro-outline-toggle"]').trigger('click')
    await wrapper.findAll('[data-role="retro-outline-item"]')[1].trigger('click')
    expect(wrapper.findAll('.retro-md__heading--active')).toHaveLength(1)

    // 换一期：上一期的「当前节」不许跟着过来（否则用户以为看的是这一节）
    await wrapper.get('[data-period="2026-W42"]').trigger('click')
    await flushPromises()
    expect(wrapper.findAll('.retro-md__heading--active')).toHaveLength(0)
    // 新一期只有一个标题 ⇒ 大纲按钮的条数跟着变
    expect(wrapper.get('[data-role="retro-outline-toggle"]').text()).toContain('大纲 · 1 节')
  })
})

/** 三个标题 + 一段正文（大纲判据的夹具：层级 1 / 2 / 3，行号 1 / 5 / 9）。 */
function headings(): MdDocument {
  const span = (text: string) => ({ text, bold: false, italic: false, code: false, target: null })
  return {
    version: 1,
    blocks: [
      { line: 1, kind: { type: 'heading', level: 1, spans: [span('本周速览')] } },
      { line: 2, kind: { type: 'paragraph', spans: [span('正文段落')] } },
      { line: 5, kind: { type: 'heading', level: 2, spans: [span('进展')] } },
      { line: 9, kind: { type: 'heading', level: 3, spans: [span('安卓')] } },
    ],
  }
}
