// @vitest-environment happy-dom
// 对话页签挂载判据（`FR-AI-25` 第一片）—— 判「用户点得着、看得见什么」，不看实现细节。
//
// 五条：① 一问一答真出现在消息流里 ② 被挡住 ⇒ 一条请求都没发且说清 ③ 满额 ⇒ 说清没发出去
// ④ 失败 ⇒ 把这句问题留在流里（只按一次重发，不用重敲） ⑤ 超长 ⇒ **一次外发都不发起**
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'

const chatMocks = vi.hoisted(() => ({ agentChatSend: vi.fn() }))

vi.mock('../ipc', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../ipc')>()
  return { ...actual, agentChatSend: chatMocks.agentChatSend }
})

import ChatPanel from './ChatPanel.vue'
import { CHAT_MAX_TURNS } from './chatThread'

const quota = { limit: 60, used: 1, remaining: 59, windowSecs: 3600, retryAfterSecs: 0 }

beforeEach(() => {
  chatMocks.agentChatSend.mockReset()
})

async function ask(wrapper: ReturnType<typeof mount>, text: string) {
  await wrapper.find('[data-testid="chat-draft"]').setValue(text)
  await wrapper.find('[data-testid="chat-send"]').trigger('click')
  await flushPromises()
}

describe('对话页签', () => {
  it('一问一答真的出现在消息流里，并给出模型 / 耗时读数', async () => {
    chatMocks.agentChatSend.mockResolvedValue({
      status: 'answered',
      text: '这个库有三张表。',
      model: 'm',
      elapsedMs: 12,
      quota,
      limitations: ['限制一'],
      attempts: [{ attempt: 1, outcome: 'ok', status: 200, delayMs: 0, detail: '' }],
      turns: 1,
    })
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans' } })
    await ask(wrapper, '这个库有哪些表')

    const thread = wrapper.find('[data-testid="chat-thread"]').text()
    expect(thread).toContain('这个库有哪些表')
    expect(thread).toContain('这个库有三张表。')
    // 发出去的就是「历史 + 这一问」
    expect(chatMocks.agentChatSend.mock.calls[0][0]).toEqual([{ role: 'user', content: '这个库有哪些表' }])
    expect(wrapper.find('[data-testid="chat-info"]').text()).toContain('m')
    expect(wrapper.find('[data-testid="chat-limits"]').text()).toContain('限制一')
  })

  it('被闸门挡住 ⇒ 说清「一条请求都没发」，并把缺的项逐条列出', async () => {
    chatMocks.agentChatSend.mockResolvedValue({
      status: 'blocked',
      gate: {
        state: 'missing',
        scope: 'remote',
        model: '',
        issues: [{ code: 'keyMissing' }],
      },
    })
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans' } })
    await ask(wrapper, '问一句')
    const blocked = wrapper.find('[data-testid="chat-blocked"]').text()
    expect(blocked).toContain('一条请求都没发')
    expect(blocked).toContain('API Key')
    // 这一问留在流里（用户不用重敲）
    expect(wrapper.find('[data-testid="chat-thread"]').text()).toContain('问一句')
  })

  it('本小时满额 ⇒ 说清已用 / 上限，且不假装成功', async () => {
    chatMocks.agentChatSend.mockResolvedValue({
      status: 'throttled',
      quota: { ...quota, used: 60, remaining: 0, retryAfterSecs: 125 },
    })
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans' } })
    await ask(wrapper, '问一句')
    const text = wrapper.find('[data-testid="chat-throttled"]').text()
    expect(text).toContain('60')
    expect(text).toContain('3')
    expect(wrapper.find('[data-testid="chat-thread"]').text()).not.toContain('模型')
  })

  it('请求失败 ⇒ 给出服务端原话，并把这一问留在流里（重发只按一次）', async () => {
    chatMocks.agentChatSend.mockRejectedValue({ message: '请求超时（60 秒）', hint: '把超时调大' })
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans' } })
    await ask(wrapper, '问一句')
    const failure = wrapper.find('[data-testid="chat-failure"]').text()
    expect(failure).toContain('请求超时')
    expect(failure).toContain('把超时调大')
    expect(wrapper.find('[data-testid="chat-thread"]').text()).toContain('问一句')
  })

  it('超长 ⇒ 本地就拒绝：**一次外发都不发起**，也不静默丢掉最早的几轮', async () => {
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans' } })
    // 先把一段长历史堆出来：每问都成功，直到底层预算吃满
    for (let index = 0; index < CHAT_MAX_TURNS; index += 1) {
      chatMocks.agentChatSend.mockResolvedValueOnce({
        status: 'answered',
        text: `答 ${index}`,
        model: 'm',
        elapsedMs: 1,
        quota,
        limitations: [],
        attempts: [{ attempt: 1, outcome: 'ok', status: 200, delayMs: 0, detail: '' }],
        turns: index + 1,
      })
      await ask(wrapper, `问 ${index}`)
    }
    chatMocks.agentChatSend.mockClear()
    await ask(wrapper, '再来一问')
    expect(chatMocks.agentChatSend).not.toHaveBeenCalled()
    expect(wrapper.find('[data-testid="chat-failure"]').text()).toContain(String(CHAT_MAX_TURNS))
  })
})
