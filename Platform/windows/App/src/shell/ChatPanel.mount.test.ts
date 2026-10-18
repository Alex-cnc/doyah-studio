// @vitest-environment happy-dom
// 对话页签挂载判据（`FR-AI-25` 第一片）—— 判「用户点得着、看得见什么」，不看实现细节。
//
// 五条：① 一问一答真出现在消息流里 ② 被挡住 ⇒ 一条请求都没发且说清 ③ 满额 ⇒ 说清没发出去
// ④ 失败 ⇒ 把这句问题留在流里（只按一次重发，不用重敲） ⑤ 超长 ⇒ **一次外发都不发起**
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'

const chatMocks = vi.hoisted(() => ({
  agentChatSend: vi.fn(),
  agentChatLoad: vi.fn(),
  agentChatSave: vi.fn(),
}))

vi.mock('../ipc', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../ipc')>()
  return {
    ...actual,
    agentChatSend: chatMocks.agentChatSend,
    agentChatLoad: chatMocks.agentChatLoad,
    agentChatSave: chatMocks.agentChatSave,
  }
})

import ChatPanel from './ChatPanel.vue'
import { CHAT_MAX_TURNS } from './chatThread'

const quota = { limit: 60, used: 1, remaining: 59, windowSecs: 3600, retryAfterSecs: 0 }

beforeEach(() => {
  chatMocks.agentChatSend.mockReset()
  chatMocks.agentChatLoad.mockReset()
  chatMocks.agentChatSave.mockReset()
  // 缺省：这份工作区没有旧会话；落盘成功但只是记账（每条用例自己覆盖）
  chatMocks.agentChatLoad.mockResolvedValue({
    workspace: 'D:/work/demo',
    path: 'C:/Users/x/AppData/Roaming/DoyahStudio/chat/chat-0123456789abcdef.json',
    messages: [],
    skipped: 0,
    clipped: 0,
    notes: [],
    questions: 0,
  })
  chatMocks.agentChatSave.mockResolvedValue({
    path: 'C:/Users/x/AppData/Roaming/DoyahStudio/chat/chat-0123456789abcdef.json',
    messages: 2,
    dropped: 0,
    clipped: 0,
    invalid: 0,
    updatedSecs: 1,
  })
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

// 会话按工作区落盘（`FR-AI-17`）：判「关掉页签 / 重开还能读回来」与「没存上要说出原因」。
describe('对话会话按工作区落盘', () => {
  const answered = (text: string, turns: number) => ({
    status: 'answered' as const,
    text,
    model: 'm',
    elapsedMs: 3,
    quota,
    limitations: [],
    attempts: [{ attempt: 1, outcome: 'ok' as const, status: 200, delayMs: 0, detail: '' }],
    turns,
  })

  it('打开页签 ⇒ 读回上次的对话，并说清存在哪个文件', async () => {
    chatMocks.agentChatLoad.mockResolvedValue({
      workspace: 'D:/work/demo',
      path: 'C:/Users/x/AppData/Roaming/DoyahStudio/chat/chat-0123456789abcdef.json',
      messages: [
        { role: 'user', content: '上次问：这个库有哪些表' },
        { role: 'assistant', content: '上次答：三张表' },
      ],
      skipped: 0,
      clipped: 0,
      notes: [],
      questions: 1,
    })
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans', workspace: 'D:/work/demo' } })
    await flushPromises()

    expect(chatMocks.agentChatLoad).toHaveBeenCalledWith('D:/work/demo')
    const thread = wrapper.find('[data-testid="chat-thread"]').text()
    expect(thread).toContain('上次问：这个库有哪些表')
    expect(thread).toContain('上次答：三张表')
    expect(wrapper.find('[data-testid="chat-restored"]').text()).toContain('2')
    expect(wrapper.find('[data-testid="chat-session"]').text()).toContain('chat-0123456789abcdef.json')
    // 读回不等于发出去：一条请求都没发。
    expect(chatMocks.agentChatSend).not.toHaveBeenCalled()
  })

  it('成功一问之后落盘的是**整段历史**；被挡住的那一问不落盘', async () => {
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans', workspace: 'D:/work/demo' } })
    await flushPromises()

    chatMocks.agentChatSend.mockResolvedValueOnce(answered('三张表', 1))
    await ask(wrapper, '有哪些表')
    expect(chatMocks.agentChatSave).toHaveBeenCalledTimes(1)
    expect(chatMocks.agentChatSave.mock.calls[0][0]).toBe('D:/work/demo')
    expect(chatMocks.agentChatSave.mock.calls[0][1]).toEqual([
      { role: 'user', content: '有哪些表' },
      { role: 'assistant', content: '三张表' },
    ])

    // 第二问：整段历史（不再只有这一问）也要一起存
    chatMocks.agentChatSend.mockResolvedValueOnce(answered('大约 40 万行', 3))
    await ask(wrapper, 'orders 多少行')
    expect(chatMocks.agentChatSave.mock.calls[1][1]).toEqual([
      { role: 'user', content: '有哪些表' },
      { role: 'assistant', content: '三张表' },
      { role: 'user', content: 'orders 多少行' },
      { role: 'assistant', content: '大约 40 万行' },
    ])

    // 第三问被闸门挡住 ⇒ 一个字都不该写盘（否则重开时是一段假历史）
    chatMocks.agentChatSend.mockResolvedValueOnce({
      status: 'blocked',
      gate: { state: 'missing', scope: 'remote', model: '', issues: [{ code: 'keyMissing' }] },
    })
    await ask(wrapper, '再问一句')
    expect(chatMocks.agentChatSave).toHaveBeenCalledTimes(2)
  })

  it('没打开工作区 ⇒ 不读不写，并如实说「这次不会存」', async () => {
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans', workspace: '   ' } })
    await flushPromises()
    expect(chatMocks.agentChatLoad).not.toHaveBeenCalled()
    expect(wrapper.find('[data-testid="chat-session-off"]').text()).toContain('不会存')

    chatMocks.agentChatSend.mockResolvedValueOnce(answered('答一句', 1))
    await ask(wrapper, '问一句')
    expect(chatMocks.agentChatSave).not.toHaveBeenCalled()
  })

  it('落盘失败 ⇒ 原因留在界面上（不静默当作存好了）', async () => {
    chatMocks.agentChatSave.mockRejectedValue({
      message: '写对话记录失败：拒绝访问',
      hint: '确认该文件可写',
    })
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans', workspace: 'D:/work/demo' } })
    await flushPromises()
    chatMocks.agentChatSend.mockResolvedValueOnce(answered('答一句', 1))
    await ask(wrapper, '问一句')

    const failed = wrapper.find('[data-testid="chat-save-failed"]').text()
    expect(failed).toContain('没能存盘')
    expect(failed).toContain('拒绝访问')
    // 模型的话照样在流里（存不上不影响这一次的结果）
    expect(wrapper.find('[data-testid="chat-thread"]').text()).toContain('答一句')
  })

  it('读的时候跳过 / 裁掉过东西 ⇒ 如实显示那几句话', async () => {
    chatMocks.agentChatLoad.mockResolvedValue({
      workspace: 'D:/work/demo',
      path: 'C:/x/chat-aa.json',
      messages: [{ role: 'user', content: '只剩这一条' }],
      skipped: 3,
      clipped: 1,
      notes: ['读的时候跳过了 3 条（角色不认识 / 正文为空 / 超出上限 / 开头是模型消息）—— 这段对话不是完整原文。'],
      questions: 1,
    })
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans', workspace: 'D:/work/demo' } })
    await flushPromises()
    const notes = wrapper.find('[data-testid="chat-session-notes"]').text()
    expect(notes).toContain('跳过了 3 条')
  })

  it('换工作区 ⇒ 立刻换成那个工作区的对话，绝不把上一段的正文写进新的那份', async () => {
    chatMocks.agentChatLoad.mockResolvedValueOnce({
      workspace: 'D:/work/alpha',
      path: 'C:/x/chat-alpha.json',
      messages: [
        { role: 'user', content: 'alpha 的表' },
        { role: 'assistant', content: 'alpha 有三张' },
      ],
      skipped: 0,
      clipped: 0,
      notes: [],
      questions: 1,
    })
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans', workspace: 'D:/work/alpha' } })
    await flushPromises()
    expect(wrapper.find('[data-testid="chat-thread"]').text()).toContain('alpha 的表')

    // 换成 beta：读的是 beta 那一份（缺省桩 = 空对话）
    await wrapper.setProps({ workspace: 'D:/work/beta' })
    await flushPromises()
    expect(chatMocks.agentChatLoad).toHaveBeenLastCalledWith('D:/work/beta')
    expect(wrapper.find('[data-testid="chat-thread"]').text()).not.toContain('alpha 的表')

    chatMocks.agentChatSend.mockResolvedValueOnce(answered('beta 的回答', 1))
    await ask(wrapper, 'beta 的问题')
    const saved = chatMocks.agentChatSave.mock.calls.at(-1)!
    expect(saved[0]).toBe('D:/work/beta')
    expect(JSON.stringify(saved[1])).not.toContain('alpha')
  })

  it('清空对话 ⇒ 连盘上那份也清掉（否则重开页签又会读回来）', async () => {
    chatMocks.agentChatLoad.mockResolvedValue({
      workspace: 'D:/work/demo',
      path: 'C:/x/chat-aa.json',
      messages: [
        { role: 'user', content: '旧问题' },
        { role: 'assistant', content: '旧回答' },
      ],
      skipped: 0,
      clipped: 0,
      notes: [],
      questions: 1,
    })
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans', workspace: 'D:/work/demo' } })
    await flushPromises()
    chatMocks.agentChatSave.mockClear()
    await wrapper.find('[data-testid="chat-clear"]').trigger('click')
    await flushPromises()
    expect(chatMocks.agentChatSave).toHaveBeenCalledWith('D:/work/demo', [])
    expect(wrapper.find('[data-testid="chat-thread"]').text()).toContain('还没有对话')
  })
})
