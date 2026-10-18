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
import type { AgentGenerateReply, AgentGeneratePreview, AgentTableBrief } from '../ipc'

const state: {
  preview: AgentGeneratePreview | null
  reply: AgentGenerateReply | null
  failure: { message: string; hint: string } | null
  previewCalls: number
  generateCalls: number
} = {
  preview: null,
  reply: null,
  failure: null,
  previewCalls: 0,
  generateCalls: 0,
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
}))

import AgentGenerateDialog from './AgentGenerateDialog.vue'

const TABLES: AgentTableBrief[] = [
  { schema: 'public', name: 'orders', columns: [{ name: 'id', dataType: 'bigint' }] },
]

const READY_PREVIEW: AgentGeneratePreview = {
  gate: { state: 'ready', scope: 'remote', model: 'deepseek-chat', issues: [] },
  url: 'https://api.example.com/v1/chat/completions',
  human: '数据库 schema（只有表名、列名与类型；没有行数据）：\n- public.orders(id bigint)\n\n请只输出一段 SQL…',
  tableCount: 1,
  dropped: 0,
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
    limitations: ['每小时上限（配额）在本片尚未计数：现在不会因为超量被拦。'],
  }
  state.failure = null
  state.previewCalls = 0
  state.generateCalls = 0
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
    // 已知缺口必须显示（配额还没计数 —— 不许让用户以为已经生效）
    expect(wrapper.find('[data-testid="generate-limits"]').text()).toContain('配额')
    expect(wrapper.find('[data-testid="generate-insert"]').exists()).toBe(true)
    await wrapper.find('[data-testid="generate-insert"]').trigger('click')
    const emitted = wrapper.emitted('insert')
    expect(emitted).toHaveLength(1)
    expect(emitted?.[0]).toEqual(['SELECT count(*) FROM public.orders;'])
    // 弹层不自己关（关与不关由视图决定），也不多调一次生成。
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
})
