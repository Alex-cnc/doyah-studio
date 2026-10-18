// @vitest-environment happy-dom
// 自然语言 → SQL 弹层（FR-AI-02）的**挂载判据**。
//
// 为什么必须挂一次（不是只看 tsc）：`.vue` 不在 `tsc --noEmit` 的程序里，模板里叫到没 import
// 的名字也编译得过去 —— 本仓踩过「五个 ipc 名字从未 import、点面板就 ReferenceError」那次。
// 这里钉住四件事：
//   ① **两段式**：「先看要发什么」只调预览、**一次都不调生成**（外发必须先摊给人看）；
//   ② 预览正文**逐字显示**（用户看到什么，就是将要发出去什么）；
//   ③ 闸门没放行时「发送并生成」是灰的，且逐条点名缺什么；
//   ④ 结果只回文本 —— 点「写入编辑器」只 `emit('insert')`，**没有任何执行类调用**。
import { describe, expect, it, vi, beforeEach } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import type {
  AgentGenerateReply,
  AgentGeneratePreview,
  AgentHistoryEntry,
  AgentTableBrief,
} from '../ipc'

const state: {
  preview: AgentGeneratePreview | null
  reply: AgentGenerateReply | null
  history: AgentHistoryEntry[]
  failure: { message: string; hint: string } | null
  previewCalls: number
  generateCalls: number
  historyCalls: number
} = {
  preview: null,
  reply: null,
  history: [],
  failure: null,
  previewCalls: 0,
  generateCalls: 0,
  historyCalls: 0,
}

vi.mock('../ipc', () => ({
  agentGeneratePreview: vi.fn(async () => {
    state.previewCalls += 1
    if (state.failure) throw state.failure
    return state.preview
  }),
  agentGenerateSql: vi.fn(async () => {
    state.generateCalls += 1
    if (state.failure) throw state.failure
    return state.reply
  }),
  // 一打开弹层就拉一次历史（只读，不触发外发）。
  agentHistoryList: vi.fn(async () => {
    state.historyCalls += 1
    return state.history
  }),
}))

import AgentGenerateDialog from './AgentGenerateDialog.vue'

const TABLES: AgentTableBrief[] = [
  { schema: 'public', name: 'orders', columns: [{ name: 'id', dataType: 'bigint' }] },
]

const READY_QUOTA = {
  limit: 60,
  used: 3,
  remaining: 57,
  windowSecs: 3600,
  retryAfterSecs: 0,
}

const READY_PREVIEW: AgentGeneratePreview = {
  gate: { state: 'ready', scope: 'remote', model: 'deepseek-chat', issues: [] },
  url: 'https://api.example.com/v1/chat/completions',
  human: '数据库 schema（只有表名、列名与类型；没有行数据）：\n- public.orders(id bigint)\n\n请只输出一段 SQL…',
  tableCount: 1,
  dropped: 0,
  quota: READY_QUOTA,
  history: [],
}

/** 一条历史记录（形状 = `Db/src/agent_history.rs` 的 `HistoryEntry`）。 */
function historyEntry(overrides: Partial<AgentHistoryEntry> = {}): AgentHistoryEntry {
  return {
    question: '上周每天的订单数',
    sql: 'SELECT date_trunc(\'day\', created_at) FROM public.orders;',
    explanation: '按天分组。',
    tablesUsed: ['public.orders'],
    model: 'deepseek-chat',
    atSecs: 1_760_000_000,
    questionTruncated: false,
    sqlTruncated: false,
    ...overrides,
  }
}

function mountDialog() {
  return mount(AgentGenerateDialog, {
    props: { open: true, tables: TABLES, language: 'zh-Hans' as const },
  })
}

async function askAndPreview(wrapper: ReturnType<typeof mountDialog>) {
  await wrapper.find('[data-testid="generate-question"]').setValue('最近 7 天的订单数')
  await wrapper.find('[data-testid="generate-preview"]').trigger('click')
  await flushPromises()
}

beforeEach(() => {
  state.preview = READY_PREVIEW
  state.reply = {
    status: 'generated',
    sql: 'SELECT count(*) FROM public.orders;',
    explanation: '用到了 orders 表，按创建时间筛选。',
    tablesUsed: ['public.orders'],
    model: 'deepseek-chat',
    elapsedMs: 321,
    tableCount: 1,
    quota: { limit: 60, used: 4, remaining: 56, windowSecs: 3600, retryAfterSecs: 0 },
    limitations: [
      '每小时上限按「真发出去的请求」计（含超时 / 报错的那一次）：防的是重试风暴，不是给云端对账单。',
    ],
    attempts: [{ attempt: 1, outcome: 'ok', status: 200, delayMs: 0, detail: '' }],
    history: [],
  }
  state.history = []
  state.failure = null
  state.previewCalls = 0
  state.generateCalls = 0
  state.historyCalls = 0
})

describe('AgentGenerateDialog（FR-AI-02）', () => {
  it('预览一步不调生成：外发必须先摊给人看', async () => {
    const wrapper = mountDialog()
    await askAndPreview(wrapper)
    expect(state.previewCalls).toBe(1)
    expect(state.generateCalls).toBe(0)
    const text = wrapper.find('[data-testid="generate-preview-text"]').text()
    expect(text).toContain('public.orders(id bigint)')
    expect(wrapper.find('[data-testid="generate-url"]').text()).toContain('/chat/completions')
  })

  it('问题还空着时两颗按钮都点不动（不白花一次外发）', async () => {
    const wrapper = mountDialog()
    expect(wrapper.find('[data-testid="generate-preview"]').attributes('disabled')).toBeDefined()
    expect(wrapper.find('[data-testid="generate-send"]').attributes('disabled')).toBeDefined()
  })

  it('总开关关着时不能发送，并逐条点名缺什么', async () => {
    state.preview = {
      gate: { state: 'disabled', scope: 'remote', model: '', issues: [] },
      url: 'https://api.example.com/v1/chat/completions',
      human: '…',
      tableCount: 1,
      dropped: 0,
      quota: READY_QUOTA,
      history: [],
    }
    const wrapper = mountDialog()
    await askAndPreview(wrapper)
    expect(wrapper.find('[data-testid="generate-gate"]').text()).toContain('不会向任何模型服务发送数据')
    expect(wrapper.find('[data-testid="generate-send"]').attributes('disabled')).toBeDefined()
    expect(state.generateCalls).toBe(0)
  })

  it('缺项时把那几条逐条列出来（不是只说「不能发」）', async () => {
    state.preview = {
      gate: {
        state: 'missing',
        scope: 'remote',
        model: '',
        issues: [{ code: 'modelMissing' }, { code: 'keyMissing' }],
      },
      url: 'https://api.example.com/v1/chat/completions',
      human: '…',
      tableCount: 1,
      dropped: 0,
      quota: READY_QUOTA,
      history: [],
    }
    const wrapper = mountDialog()
    await askAndPreview(wrapper)
    const issues = wrapper.find('[data-testid="generate-issues"]').text()
    expect(issues).toContain('模型名')
    expect(issues).toContain('API Key')
    expect(wrapper.find('[data-testid="generate-send"]').attributes('disabled')).toBeDefined()
  })

  it('生成后只显示文本；点「写入编辑器」只发出 insert，不做别的', async () => {
    const wrapper = mountDialog()
    await askAndPreview(wrapper)
    await wrapper.find('[data-testid="generate-send"]').trigger('click')
    await flushPromises()
    expect(state.generateCalls).toBe(1)
    expect(wrapper.find('[data-testid="generate-sql"]').text()).toContain('SELECT count(*)')
    expect(wrapper.find('[data-testid="generate-tables"]').text()).toContain('public.orders')
    // 已知缺口必须显示（配额口径 —— 不许让用户以为「按账单算」）
    expect(wrapper.find('[data-testid="generate-limits"]').text()).toContain('每小时上限')
    expect(wrapper.find('[data-testid="generate-insert"]').exists()).toBe(true)
    await wrapper.find('[data-testid="generate-insert"]').trigger('click')
    const emitted = wrapper.emitted('insert')
    expect(emitted).toHaveLength(1)
    expect(emitted?.[0]).toEqual(['SELECT count(*) FROM public.orders;'])
    // 弹层不自己关（关与不关由视图决定），也不多调一次生成。
    expect(state.generateCalls).toBe(1)
  })

  it('生成后点「存成已保存查询」：只把这段 SQL 交出去，不发第二次生成、也不写编辑器', async () => {
    const wrapper = mountDialog()
    await askAndPreview(wrapper)
    await wrapper.find('[data-testid="generate-send"]').trigger('click')
    await flushPromises()

    const saveAs = wrapper.find('[data-testid="generate-save-as-query"]')
    expect(saveAs.exists()).toBe(true)
    await saveAs.trigger('click')

    expect(wrapper.emitted('save-as')).toEqual([['SELECT count(*) FROM public.orders;']])
    // 否定面：保存不是「写入编辑器」，也不是再发一次请求
    expect(wrapper.emitted('insert')).toBeUndefined()
    expect(state.generateCalls).toBe(1)
  })

  it('闸门在发送那一刻才被挡住时，如实显示裁决而不是假装成功', async () => {
    state.reply = {
      status: 'blocked',
      gate: { state: 'missing', scope: 'remote', model: '', issues: [{ code: 'keyMissing' }] },
    }
    const wrapper = mountDialog()
    await askAndPreview(wrapper)
    await wrapper.find('[data-testid="generate-send"]').trigger('click')
    await flushPromises()
    expect(wrapper.find('[data-testid="generate-issues"]').text()).toContain('API Key')
    expect(wrapper.find('[data-testid="generate-sql"]').exists()).toBe(false)
  })

  it('失败要两段都说（原话 + 出路），不许只显示一句「失败了」', async () => {
    state.failure = { message: '请求超时（60 秒）：模型服务没有在时限内回话。', hint: '把超时调大。' }
    const wrapper = mountDialog()
    await askAndPreview(wrapper)
    const error = wrapper.find('[data-testid="generate-error"]').text()
    expect(error).toContain('请求超时')
    expect(error).toContain('把超时调大')
  })

  // ── 每小时配额（FR-AI-02 第三片）──────────────────────────────────────────
  it('预览这一步就显示本小时还剩几次，发完立刻 +1（读数来自回包，界面不自己算）', async () => {
    const wrapper = mountDialog()
    await askAndPreview(wrapper)
    const before = wrapper.find('[data-testid="generate-quota"]').text()
    expect(before).toContain('3/60')
    expect(before).toContain('还剩 57 次')

    await wrapper.find('[data-testid="generate-send"]').trigger('click')
    await flushPromises()
    const after = wrapper.find('[data-testid="generate-quota"]').text()
    expect(after).toContain('4/60')
    expect(after).toContain('还剩 56 次')
  })

  it('配额满了时发送键是灰的，并点名还要等多久（灰按钮不解释 = 用户不知道能干什么）', async () => {
    state.preview = {
      ...READY_PREVIEW,
      quota: { limit: 60, used: 60, remaining: 0, windowSecs: 3600, retryAfterSecs: 125 },
    }
    const wrapper = mountDialog()
    await askAndPreview(wrapper)
    expect(wrapper.find('[data-testid="generate-send"]').attributes('disabled')).toBeDefined()
    const quota = wrapper.find('[data-testid="generate-quota"]').text()
    expect(quota).toContain('额度已用完')
    expect(quota).toContain('2 分 5 秒')
  })

  it('真发被配额拦下时说清「一条都没发」，且不显示结果区、不发出 insert / save-as', async () => {
    state.reply = {
      status: 'throttled',
      quota: { limit: 1, used: 1, remaining: 0, windowSecs: 3600, retryAfterSecs: 90 },
    }
    const wrapper = mountDialog()
    await askAndPreview(wrapper)
    await wrapper.find('[data-testid="generate-send"]').trigger('click')
    await flushPromises()

    const throttled = wrapper.find('[data-testid="generate-throttled"]').text()
    expect(throttled).toContain('一条请求都没有发出去')
    expect(throttled).toContain('1 分 30 秒')
    // 否定面：没有结果区，也没有任何交出去的文本
    expect(wrapper.find('[data-testid="generate-sql"]').exists()).toBe(false)
    expect(wrapper.find('[data-testid="generate-insert"]').exists()).toBe(false)
    expect(wrapper.emitted('insert')).toBeUndefined()
    expect(wrapper.emitted('save-as')).toBeUndefined()
    // 发送键随后变灰（读数显示已满）
    expect(wrapper.find('[data-testid="generate-send"]').attributes('disabled')).toBeDefined()
    expect(wrapper.find('[data-testid="generate-quota"]').text()).toContain('额度已用完')
  })

  // ── 生成历史（FR-AI-02 第四片）──────────────────────────────────────────────
  it('一打开就拉一次历史；没有记录时说清「还没有成功的生成」，而不是空一块', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    expect(state.historyCalls).toBe(1)
    expect(state.previewCalls).toBe(0)
    expect(state.generateCalls).toBe(0)
    expect(wrapper.find('[data-testid="generate-history-empty"]').text()).toContain('还没有成功的生成记录')
    expect(wrapper.find('[data-testid="generate-history-row"]').exists()).toBe(false)
  })

  it('历史读得出来：逐条显示问句与时间；点一条把问句填回输入框并摊出那次的 SQL', async () => {
    state.history = [
      historyEntry({ question: '上周每天的订单数', atSecs: 1_760_000_000 }),
      historyEntry({ question: '库存为 0 的商品', sql: 'SELECT * FROM public.stock WHERE qty = 0;', atSecs: 1_759_000_000 }),
    ]
    const wrapper = mountDialog()
    await flushPromises()

    const rows = wrapper.findAll('[data-testid="generate-history-row"]')
    expect(rows).toHaveLength(2)
    expect(rows[0].text()).toContain('上周每天的订单数')
    expect(wrapper.find('[data-testid="generate-history-count"]').text()).toContain('共 2 条')

    // 点第二条 ⇒ 问句回到输入框、SQL 摊在「历史里那一次」那块里
    await rows[1].trigger('click')
    expect((wrapper.find('[data-testid="generate-question"]').element as HTMLTextAreaElement).value).toBe(
      '库存为 0 的商品',
    )
    const reopened = wrapper.find('[data-testid="generate-history-reopened"]').text()
    expect(reopened).toContain('历史里那一次的 SQL')
    expect(wrapper.find('[data-testid="generate-history-sql"]').text()).toContain('qty = 0')
    // 否定面：回看不触发任何外发，也不冒充「这一次的结果」
    expect(state.previewCalls).toBe(0)
    expect(state.generateCalls).toBe(0)
    expect(wrapper.find('[data-testid="generate-sql"]').exists()).toBe(false)
  })

  it('点开历史的「写入编辑器」只把那次 SQL 交出去（不执行、不发请求）', async () => {
    state.history = [historyEntry({ sql: 'SELECT 42;' })]
    const wrapper = mountDialog()
    await flushPromises()
    await wrapper.find('[data-testid="generate-history-row"]').trigger('click')
    await wrapper.find('[data-testid="generate-history-insert"]').trigger('click')
    expect(wrapper.emitted('insert')).toEqual([['SELECT 42;']])
    expect(wrapper.emitted('save-as')).toBeUndefined()
    expect(state.generateCalls).toBe(0)
  })

  it('生成成功后列表换成回包里那份历史（界面不自己攒），截断过的旧 SQL 如实说', async () => {
    state.reply = {
      status: 'generated',
      sql: 'SELECT 1;',
      explanation: '',
      tablesUsed: [],
      model: 'deepseek-chat',
      elapsedMs: 10,
      tableCount: 1,
      quota: { limit: 60, used: 4, remaining: 56, windowSecs: 3600, retryAfterSecs: 0 },
      limitations: [],
      attempts: [{ attempt: 1, outcome: 'ok', status: 200, delayMs: 0, detail: '' }],
      history: [historyEntry({ question: '刚刚这一问', sql: 'SELECT 1;', sqlTruncated: true })],
    }
    const wrapper = mountDialog()
    await flushPromises()
    expect(wrapper.find('[data-testid="generate-history-empty"]').exists()).toBe(true)

    await askAndPreview(wrapper)
    await wrapper.find('[data-testid="generate-send"]').trigger('click')
    await flushPromises()

    const rows = wrapper.findAll('[data-testid="generate-history-row"]')
    expect(rows).toHaveLength(1)
    expect(rows[0].text()).toContain('刚刚这一问')

    await rows[0].trigger('click')
    expect(wrapper.find('[data-testid="generate-history-truncated"]').text()).toContain('截断')
  })

  // 尝试账（FR-AI-30 ①）：一次成功**不打扰**，真重试过才画一行且读数照回包说。
  it('重试过才画「共尝试 N 次」，一次成功不画', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    await askAndPreview(wrapper)
    await wrapper.find('[data-testid="generate-send"]').trigger('click')
    await flushPromises()
    expect(wrapper.find('[data-testid="generate-attempts"]').exists()).toBe(false)

    state.reply = {
      status: 'generated',
      sql: 'SELECT 1;',
      explanation: '',
      tablesUsed: [],
      model: 'deepseek-chat',
      elapsedMs: 900,
      tableCount: 1,
      quota: { limit: 60, used: 5, remaining: 55, windowSecs: 3600, retryAfterSecs: 0 },
      limitations: [],
      attempts: [
        { attempt: 1, outcome: 'retryable', status: 429, delayMs: 400, detail: 'HTTP 429' },
        { attempt: 2, outcome: 'ok', status: 200, delayMs: 0, detail: '' },
      ],
      history: [],
    }
    await wrapper.find('[data-testid="generate-send"]').trigger('click')
    await flushPromises()
    const line = wrapper.get('[data-testid="generate-attempts"]').text()
    expect(line).toContain('共尝试 2 次')
    expect(line).toContain('HTTP 429')
    expect(line).toContain('400')
  })
})
