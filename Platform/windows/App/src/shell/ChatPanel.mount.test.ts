// @vitest-environment happy-dom
// 对话页签挂载判据（`FR-AI-25` 第一片）—— 判「用户点得着、看得见什么」，不看实现细节。
//
// 五条：① 一问一答真出现在消息流里 ② 被挡住 ⇒ 一条请求都没发且说清 ③ 满额 ⇒ 说清没发出去
// ④ 失败 ⇒ 把这句问题留在流里（只按一次重发，不用重敲） ⑤ 超长 ⇒ **一次外发都不发起**
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'

const chatMocks = vi.hoisted(() => ({
  agentChatStream: vi.fn(),
  agentChatLoad: vi.fn(),
  agentChatList: vi.fn(),
  agentChatNew: vi.fn(),
  agentChatSave: vi.fn(),
  agentChatToolResume: vi.fn(),
}))

vi.mock('../ipc', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../ipc')>()
  return {
    ...actual,
    agentChatStream: chatMocks.agentChatStream,
    agentChatLoad: chatMocks.agentChatLoad,
    agentChatList: chatMocks.agentChatList,
    agentChatNew: chatMocks.agentChatNew,
    agentChatSave: chatMocks.agentChatSave,
    agentChatToolResume: chatMocks.agentChatToolResume,
  }
})

import ChatPanel from './ChatPanel.vue'
import { CHAT_MAX_TURNS } from './chatThread'

const quota = { limit: 60, used: 1, remaining: 59, windowSecs: 3600, retryAfterSecs: 0 }

beforeEach(() => {
  chatMocks.agentChatStream.mockReset()
  chatMocks.agentChatLoad.mockReset()
  chatMocks.agentChatList.mockReset()
  chatMocks.agentChatNew.mockReset()
  chatMocks.agentChatSave.mockReset()
  // 缺省：这份工作区没有旧会话；落盘成功但只是记账（每条用例自己覆盖）
  chatMocks.agentChatLoad.mockResolvedValue({
    id: '1',
    workspace: 'D:/work/demo',
    path: 'C:/Users/x/AppData/Roaming/DoyahStudio/chat/chat-0123456789abcdef.json',
    messages: [],
    skipped: 0,
    clipped: 0,
    notes: [],
    questions: 0,
  })
  // 缺省：盘上一段都没有（下拉不出现）—— 每条用例自己覆盖
  chatMocks.agentChatList.mockResolvedValue({
    dir: 'C:/Users/x/AppData/Roaming/DoyahStudio/chat',
    entries: [],
    broken: 0,
    active: '1',
  })
  chatMocks.agentChatNew.mockResolvedValue({
    id: '2',
    workspace: 'D:/work/demo',
    path: 'C:/Users/x/AppData/Roaming/DoyahStudio/chat/chat-0123456789abcdef-2.json',
    messages: [],
    skipped: 0,
    clipped: 0,
    notes: [],
    questions: 0,
  })
  chatMocks.agentChatSave.mockResolvedValue({
    id: '1',
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
    chatMocks.agentChatStream.mockResolvedValue({
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
    expect(chatMocks.agentChatStream.mock.calls[0][0]).toEqual([{ role: 'user', content: '这个库有哪些表' }])
    expect(wrapper.find('[data-testid="chat-info"]').text()).toContain('m')
    expect(wrapper.find('[data-testid="chat-limits"]').text()).toContain('限制一')
  })

  it('被闸门挡住 ⇒ 说清「一条请求都没发」，并把缺的项逐条列出', async () => {
    chatMocks.agentChatStream.mockResolvedValue({
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
    chatMocks.agentChatStream.mockResolvedValue({
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
    chatMocks.agentChatStream.mockRejectedValue({ message: '请求超时（60 秒）', hint: '把超时调大' })
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
      chatMocks.agentChatStream.mockResolvedValueOnce({
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
    chatMocks.agentChatStream.mockClear()
    await ask(wrapper, '再来一问')
    expect(chatMocks.agentChatStream).not.toHaveBeenCalled()
    expect(wrapper.find('[data-testid="chat-failure"]').text()).toContain(String(CHAT_MAX_TURNS))
  })
})

// 会话按工作区落盘（`FR-AI-17`）：判「关掉页签 / 重开还能读回来」与「没存上要说出原因」。
describe('对话会话按工作区落盘', () => {
  const answered = (text: string, turns: number, deltas = 0) => ({
    status: 'answered' as const,
    text,
    model: 'm',
    elapsedMs: 3,
    quota,
    limitations: [],
    attempts: [{ attempt: 1, outcome: 'ok' as const, status: 200, delayMs: 0, detail: '' }],
    turns,
    deltas,
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

    expect(chatMocks.agentChatLoad).toHaveBeenCalledWith('D:/work/demo', undefined)
    const thread = wrapper.find('[data-testid="chat-thread"]').text()
    expect(thread).toContain('上次问：这个库有哪些表')
    expect(thread).toContain('上次答：三张表')
    expect(wrapper.find('[data-testid="chat-restored"]').text()).toContain('2')
    expect(wrapper.find('[data-testid="chat-session"]').text()).toContain('chat-0123456789abcdef.json')
    // 读回不等于发出去：一条请求都没发。
    expect(chatMocks.agentChatStream).not.toHaveBeenCalled()
  })

  it('成功一问之后落盘的是**整段历史**；被挡住的那一问不落盘', async () => {
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans', workspace: 'D:/work/demo' } })
    await flushPromises()

    chatMocks.agentChatStream.mockResolvedValueOnce(answered('三张表', 1))
    await ask(wrapper, '有哪些表')
    expect(chatMocks.agentChatSave).toHaveBeenCalledTimes(1)
    expect(chatMocks.agentChatSave.mock.calls[0][0]).toBe('D:/work/demo')
    expect(chatMocks.agentChatSave.mock.calls[0][1]).toEqual([
      { role: 'user', content: '有哪些表' },
      { role: 'assistant', content: '三张表' },
    ])

    // 第二问：整段历史（不再只有这一问）也要一起存
    chatMocks.agentChatStream.mockResolvedValueOnce(answered('大约 40 万行', 3))
    await ask(wrapper, 'orders 多少行')
    expect(chatMocks.agentChatSave.mock.calls[1][1]).toEqual([
      { role: 'user', content: '有哪些表' },
      { role: 'assistant', content: '三张表' },
      { role: 'user', content: 'orders 多少行' },
      { role: 'assistant', content: '大约 40 万行' },
    ])

    // 第三问被闸门挡住 ⇒ 一个字都不该写盘（否则重开时是一段假历史）
    chatMocks.agentChatStream.mockResolvedValueOnce({
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

    chatMocks.agentChatStream.mockResolvedValueOnce(answered('答一句', 1))
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
    chatMocks.agentChatStream.mockResolvedValueOnce(answered('答一句', 1))
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
    expect(chatMocks.agentChatLoad).toHaveBeenLastCalledWith('D:/work/beta', undefined)
    expect(wrapper.find('[data-testid="chat-thread"]').text()).not.toContain('alpha 的表')

    chatMocks.agentChatStream.mockResolvedValueOnce(answered('beta 的回答', 1))
    await ask(wrapper, 'beta 的问题')
    const saved = chatMocks.agentChatSave.mock.calls.at(-1)!
    expect(saved[0]).toBe('D:/work/beta')
    expect(JSON.stringify(saved[1])).not.toContain('alpha')
  })

  it('清空对话 ⇒ 连盘上那份也清掉（否则重开页签又会读回来）', async () => {
    chatMocks.agentChatLoad.mockResolvedValue({
      id: '1',
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
    // 清的是**当前这一段**（段号一起带上：不许把别的段清掉）
    expect(chatMocks.agentChatSave).toHaveBeenCalledWith('D:/work/demo', [], '1')
    expect(wrapper.find('[data-testid="chat-thread"]').text()).toContain('还没有对话')
  })

  // 多段对话（`FR-AI-17` 续）：判「切段真的换历史 / 新建真的起一段空的 / 坏的那段单独计数」。
  it('同一个工作区两段 ⇒ 下拉里都看得见；切段换的是那一段的历史，落盘也写那一段', async () => {
    chatMocks.agentChatLoad.mockImplementation(async (_workspace: string, id?: string) => {
      const which = id ?? '1'
      return {
        id: which,
        workspace: 'D:/work/demo',
        path: `C:/x/chat-aa-${which}.json`,
        messages:
          which === '2'
            ? [{ role: 'user', content: '第二段的问题' }, { role: 'assistant', content: '第二段的回答' }]
            : [{ role: 'user', content: '第一段的问题' }, { role: 'assistant', content: '第一段的回答' }],
        skipped: 0,
        clipped: 0,
        notes: [],
        questions: 1,
      }
    })
    chatMocks.agentChatList.mockResolvedValue({
      dir: 'C:/x',
      entries: [
        { id: '2', title: '第二段的问题', questions: 1, messages: 2, updatedSecs: 30, problem: null },
        { id: '1', title: '第一段的问题', questions: 1, messages: 2, updatedSecs: 10, problem: null },
      ],
      broken: 0,
      active: '1',
    })
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans', workspace: 'D:/work/demo' } })
    await flushPromises()

    expect(wrapper.find('[data-testid="chat-thread"]').text()).toContain('第一段的问题')
    const options = wrapper.findAll('[data-testid="chat-session-select"] option')
    expect(options.length).toBe(2)
    // 下拉里写的是「标题 · 问数」（不是文件名 / 段号）
    expect(options[0].text()).toContain('第二段的问题')
    expect(options[0].text()).toContain('问 1 次')

    // 切到第 2 段 ⇒ 读的是那一段（带段号），消息流换成它
    const select = wrapper.find('[data-testid="chat-session-select"]')
    ;(select.element as HTMLSelectElement).value = '2'
    await select.trigger('change')
    await flushPromises()
    expect(chatMocks.agentChatLoad).toHaveBeenLastCalledWith('D:/work/demo', '2')
    const thread = wrapper.find('[data-testid="chat-thread"]').text()
    expect(thread).toContain('第二段的问题')
    expect(thread).not.toContain('第一段的问题')

    // 在这一段里提问 ⇒ 落盘带的是第 2 段的段号（不许写回第 1 段）
    chatMocks.agentChatStream.mockResolvedValueOnce(answered('接着答', 3))
    await ask(wrapper, '接着问')
    const saved = chatMocks.agentChatSave.mock.calls.at(-1)!
    expect(saved[0]).toBe('D:/work/demo')
    expect(saved[2]).toBe('2')
    expect(JSON.stringify(saved[1])).toContain('接着问')
  })

  it('新建对话 ⇒ 起一段新的（空流），下一次落盘写新段号；清空不再是换话题的唯一办法', async () => {
    // 没有段号 ⇒ 读到当前段（老话题）；带段号 ⇒ 那一段（新段是空的）
    chatMocks.agentChatLoad.mockImplementation(async (_workspace: string, id?: string) => ({
      id: id ?? '1',
      workspace: 'D:/work/other',
      path: `C:/x/chat-bb${id ? `-${id}` : ''}.json`,
      messages: id ? [] : [{ role: 'user', content: '老话题的问题' }],
      skipped: 0,
      clipped: 0,
      notes: [],
      questions: id ? 0 : 1,
    }))
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans', workspace: 'D:/work/other' } })
    await flushPromises()
    expect(wrapper.find('[data-testid="chat-thread"]').text()).toContain('老话题的问题')

    await wrapper.find('[data-testid="chat-new"]').trigger('click')
    await flushPromises()
    expect(chatMocks.agentChatNew).toHaveBeenCalledWith('D:/work/other')
    // 新段是空的（老那段的正文不许留在界面上）
    const thread = wrapper.find('[data-testid="chat-thread"]').text()
    expect(thread).toContain('还没有对话')
    expect(thread).not.toContain('老话题的问题')

    chatMocks.agentChatStream.mockResolvedValueOnce(answered('新话题的回答', 1))
    await ask(wrapper, '新话题的问题')
    const saved = chatMocks.agentChatSave.mock.calls.at(-1)!
    expect(saved[2]).toBe('2')
    expect(JSON.stringify(saved[1])).not.toContain('老话题')
  })

  it('有段读不出来 ⇒ 页头如实计数，其余段照常可选（不因为一段坏了整个列表不可用）', async () => {
    chatMocks.agentChatList.mockResolvedValue({
      dir: 'C:/x',
      entries: [
        { id: '1', title: '好的一段', questions: 2, messages: 4, updatedSecs: 20, problem: null },
        { id: '2', title: '', questions: 0, messages: 0, updatedSecs: 0, problem: '这份对话记录读不出来' },
      ],
      broken: 1,
      active: '1',
    })
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans', workspace: 'D:/work/demo' } })
    await flushPromises()

    const broken = wrapper.find('[data-testid="chat-broken"]').text()
    expect(broken).toContain('1')
    expect(broken).toContain('读不出来')
    // 好的那段照常在下拉里且可用
    const options = wrapper.findAll('[data-testid="chat-session-select"] option')
    expect(options.length).toBe(2)
    expect(options[0].text()).toContain('好的一段')
    expect(options[1].text()).toContain('读不出来')
  })
})

// 逐段渲染（`FR-AI-16` ①）：判「片段先出现、最终正文替换它、读数说清到底是不是流式」。
describe('对话逐段渲染', () => {
  const answered = (text: string, deltas: number) => ({
    status: 'answered' as const,
    text,
    model: 'm',
    elapsedMs: 5,
    quota,
    limitations: [],
    attempts: [{ attempt: 1, outcome: 'ok' as const, status: 200, delayMs: 0, detail: '' }],
    turns: 1,
    deltas,
  })

  it('片段先画出来，最终正文替换它，并给出「逐段 N 段」读数', async () => {
    let release!: (value: unknown) => void
    const finished = new Promise((resolve) => {
      release = resolve
    })
    chatMocks.agentChatStream.mockImplementation(
      (_turns: unknown, _carry: unknown, onDelta: (chunk: string) => void) => {
        onDelta('第一段')
        onDelta('，第二段')
        return finished
      },
    )
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans' } })
    await wrapper.find('[data-testid="chat-draft"]').setValue('问一句')
    await wrapper.find('[data-testid="chat-send"]').trigger('click')
    await flushPromises()

    // 还没回完：片段已经在流里了（不是干等一行「正在等模型回话」）
    const partial = wrapper.find('[data-testid="chat-partial"]')
    expect(partial.exists()).toBe(true)
    expect(partial.text()).toContain('第一段，第二段')
    expect(wrapper.find('[data-testid="chat-sending"]').text()).toContain('已到')

    release(answered('第一段，第二段', 2))
    await flushPromises()

    // 回完之后：临时气泡消失，正式那条在流里，读数说「逐段 2 段」
    expect(wrapper.find('[data-testid="chat-partial"]').exists()).toBe(false)
    expect(wrapper.find('[data-testid="chat-thread"]').text()).toContain('第一段，第二段')
    expect(wrapper.find('[data-testid="chat-streamed"]').text()).toContain('2')
  })

  it('该服务端整段返回（deltas = 0）⇒ 如实说「没有逐段流」，不假装滚出来了', async () => {
    chatMocks.agentChatStream.mockImplementation(async () => answered('整段回来的', 0))
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans' } })
    await ask(wrapper, '问一句')

    expect(wrapper.find('[data-testid="chat-thread"]').text()).toContain('整段回来的')
    expect(wrapper.find('[data-testid="chat-streamed"]').text()).toContain('整段返回')
  })
})

// 工具调用 + 内联审批（`FR-AI-18`）：判「卡片写明要读哪个文件 / 不点就不执行 /
// 全部点完才一次发出去 / 允许与拒绝都各有一条账」。
describe('对话工具调用', () => {
  const call = (id: string, path: string) => ({ id, name: 'read_file', arguments: JSON.stringify({ path }) })

  const pending = (calls: ReturnType<typeof call>[]) => ({
    status: 'toolPending' as const,
    calls,
    text: '',
    model: 'm',
    elapsedMs: 8,
    quota,
    attempts: [{ attempt: 1, outcome: 'ok' as const, status: 200, delayMs: 0, detail: '' }],
    turns: 1,
    deltas: 0,
  })

  const answered = (text: string) => ({
    status: 'answered' as const,
    text,
    model: 'm',
    elapsedMs: 9,
    quota,
    limitations: [],
    attempts: [{ attempt: 1, outcome: 'ok' as const, status: 200, delayMs: 0, detail: '' }],
    turns: 1,
    deltas: 1,
  })

  const run = (path: string, approved: boolean, content = approved ? `文件 ${path}：正文` : '') => ({
    name: 'read_file',
    path,
    approved,
    ok: approved,
    chars: approved ? 42 : 0,
    truncated: false,
    problem: '',
    content,
  })

  it('模型点工具 ⇒ 卡片写明路径，不点就一次都不执行；点允许后才真发并显示读数', async () => {
    chatMocks.agentChatStream.mockResolvedValue(pending([call('call_1', 'src/main.ts')]))
    chatMocks.agentChatToolResume.mockResolvedValue({
      runs: [run('src/main.ts', true)],
      reply: answered('这个文件导出了 start()。'),
    })
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans', workspace: 'D:/work/demo' } })
    await ask(wrapper, '看一下 src/main.ts')

    // 卡片出来了，且**什么都没执行**
    expect(wrapper.find('[data-testid="chat-tool-card"]').exists()).toBe(true)
    expect(wrapper.find('[data-testid="chat-tool-ask"]').text()).toContain('src/main.ts')
    expect(chatMocks.agentChatToolResume).not.toHaveBeenCalled()

    await wrapper.find('[data-testid="chat-tool-allow"]').trigger('click')
    await flushPromises()

    const [workspace, turns, calls, approvals] = chatMocks.agentChatToolResume.mock.calls[0]
    expect(workspace).toBe('D:/work/demo')
    expect(turns).toEqual([{ role: 'user', content: '看一下 src/main.ts' }])
    expect(calls).toEqual([call('call_1', 'src/main.ts')])
    expect(approvals).toEqual([true])
    // 最终回答进流里、执行账留着、卡片消失（同一件事不会追问第二次）
    expect(wrapper.find('[data-testid="chat-thread"]').text()).toContain('这个文件导出了 start()。')
    expect(wrapper.find('[data-testid="chat-tool-runs"]').text()).toContain('42')
    expect(wrapper.find('[data-testid="chat-tool-card"]').exists()).toBe(false)
  })

  it('点拒绝 ⇒ 带 [false] 再发一次，账上写清「你拒绝了」', async () => {
    chatMocks.agentChatStream.mockResolvedValue(pending([call('call_1', 'src/main.ts')]))
    chatMocks.agentChatToolResume.mockResolvedValue({
      runs: [run('src/main.ts', false)],
      reply: answered('没有读到文件，我只能按你贴的内容回答。'),
    })
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans', workspace: 'D:/work/demo' } })
    await ask(wrapper, '看一下 src/main.ts')

    await wrapper.find('[data-testid="chat-tool-deny"]').trigger('click')
    await flushPromises()

    expect(chatMocks.agentChatToolResume.mock.calls[0][3]).toEqual([false])
    expect(wrapper.find('[data-testid="chat-tool-runs"]').text()).toContain('拒绝')
    expect(wrapper.find('[data-testid="chat-thread"]').text()).toContain('没有读到文件')
  })

  it('一条回答里两件 ⇒ 逐件列出；只点一件仍零调用，两件都点完才一次交给模型', async () => {
    chatMocks.agentChatStream.mockResolvedValue(
      pending([call('call_1', 'src/a.ts'), call('call_2', 'src/b.ts')]),
    )
    chatMocks.agentChatToolResume.mockResolvedValue({
      runs: [run('src/a.ts', true), run('src/b.ts', false)],
      reply: answered('a.ts 里是 A，b.ts 我没读。'),
    })
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans', workspace: 'D:/work/demo' } })
    await ask(wrapper, '看一下 src/a.ts 和 src/b.ts')

    // 两件都在卡片上，且一件都还没点
    const rows = wrapper.findAll('[data-testid="chat-tool-ask"]')
    expect(rows.length).toBe(2)
    expect(rows[0].text()).toContain('src/a.ts')
    expect(rows[1].text()).toContain('src/b.ts')
    expect(wrapper.find('[data-testid="chat-tool-progress"]').text()).toContain('0 / 2')

    // 只点第一件 ⇒ **一次都不发**（不许拿半批决定去问模型）
    await wrapper.findAll('[data-testid="chat-tool-allow"]')[0].trigger('click')
    await flushPromises()
    expect(chatMocks.agentChatToolResume).not.toHaveBeenCalled()
    expect(wrapper.find('[data-testid="chat-tool-progress"]').text()).toContain('1 / 2')
    expect(wrapper.findAll('[data-testid="chat-tool-mark"]')[0].text()).toContain('已允许')

    // 第二件点拒绝 ⇒ 走一次，带着两件的决定与两件工具
    await wrapper.findAll('[data-testid="chat-tool-deny"]')[1].trigger('click')
    await flushPromises()
    expect(chatMocks.agentChatToolResume).toHaveBeenCalledTimes(1)
    const [, , calls, approvals] = chatMocks.agentChatToolResume.mock.calls[0]
    expect(calls).toEqual([call('call_1', 'src/a.ts'), call('call_2', 'src/b.ts')])
    expect(approvals).toEqual([true, false])

    // 两件各有一条账，最终回答进流里
    const runs = wrapper.find('[data-testid="chat-tool-runs"]').text()
    expect(runs).toContain('src/a.ts')
    expect(runs).toContain('src/b.ts')
    expect(wrapper.find('[data-testid="chat-thread"]').text()).toContain('a.ts 里是 A')
    expect(wrapper.find('[data-testid="chat-tool-card"]').exists()).toBe(false)
  })

  it('读到的文件进「这一轮读到了什么」：同份只一行、字符如实报，被拒绝的单列（清空后消失）', async () => {
    chatMocks.agentChatStream.mockResolvedValue(
      pending([call('call_1', 'src/a.ts'), call('call_2', 'src/b.ts')]),
    )
    chatMocks.agentChatToolResume.mockResolvedValue({
      runs: [
        { name: 'read_file', path: 'src/a.ts', approved: true, ok: true, chars: 128, truncated: true, problem: '', content: '文件 src/a.ts：aaa' },
        { name: 'read_file', path: 'src/b.ts', approved: false, ok: false, chars: 0, truncated: false, problem: '', content: '' },
      ],
      reply: answered('a.ts 我读了前 128 字符，b.ts 没看到。'),
    })
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans', workspace: 'D:/work/demo' } })
    await ask(wrapper, '看看 src/a.ts 和 src/b.ts')

    await wrapper.findAll('[data-testid="chat-tool-allow"]')[0].trigger('click')
    await flushPromises()
    await wrapper.findAll('[data-testid="chat-tool-deny"]')[1].trigger('click')
    await flushPromises()

    // 标题只报「真的进了上下文的那一份」与它的字符数（拒绝那件 0 字符，不能算进去）
    const title = wrapper.find('[data-testid="chat-context-title"]').text()
    expect(title).toContain('1')
    expect(title).toContain('128')

    const files = wrapper.findAll('[data-testid="chat-context-file"]')
    expect(files.length).toBe(1)
    expect(files[0].text()).toContain('src/a.ts')
    expect(files[0].text()).toContain('128')
    // 截断要如实说，不许让用户以为模型看到了全文
    expect(files[0].text()).toContain('截断')

    // 被拒绝那件单独一行：用户要知道模型**没**看到它
    const miss = wrapper.find('[data-testid="chat-context-miss"]')
    expect(miss.text()).toContain('src/b.ts')
    expect(miss.text()).toContain('拒绝')
    expect(wrapper.find('[data-testid="chat-context-note"]').text()).toContain('带进后续请求')

    // 清空对话 ⇒ 这一栏一起清掉（不留上一轮的读数冒充「模型现在知道」）
    await wrapper.find('[data-testid="chat-clear"]').trigger('click')
    await flushPromises()
    expect(wrapper.find('[data-testid="chat-context"]').exists()).toBe(false)
  })

  it('读到的正文带进下一问：请求里带着它，被拒绝的不带；清空后不再带', async () => {
    chatMocks.agentChatStream.mockResolvedValueOnce(
      pending([call('call_1', 'src/a.ts'), call('call_2', 'src/b.ts')]),
    )
    chatMocks.agentChatToolResume.mockResolvedValue({
      runs: [run('src/a.ts', true, '文件 src/a.ts：export const A = 1'), run('src/b.ts', false)],
      reply: answered('a.ts 里只有一个常量。'),
    })
    chatMocks.agentChatStream.mockResolvedValueOnce(answered('按 a.ts 的说法，它是个常量。'))
    const wrapper = mount(ChatPanel, { props: { language: 'zh-Hans', workspace: 'D:/work/demo' } })
    await ask(wrapper, '看看 src/a.ts 和 src/b.ts')

    await wrapper.findAll('[data-testid="chat-tool-allow"]')[0].trigger('click')
    await flushPromises()
    await wrapper.findAll('[data-testid="chat-tool-deny"]')[1].trigger('click')
    await flushPromises()

    // 面板如实说「带进了几份 / 多少字符」
    const carryLine = wrapper.find('[data-testid="chat-carry"]').text()
    expect(carryLine).toContain('1')
    expect(wrapper.find('[data-testid="chat-carry-dropped"]').exists()).toBe(false)

    // 下一问：请求里真带着 a.ts 的正文，且只有它一份（被拒绝的 b.ts 不许带）
    await ask(wrapper, '那它是什么类型')
    const carry = chatMocks.agentChatStream.mock.calls[1][1] as { path: string; content: string }[]
    expect(carry.map((file) => file.path)).toEqual(['src/a.ts'])
    expect(carry[0].content).toContain('export const A = 1')
    // 发出去的历史里**不许**混进这段正文（上下文是程序加的、由 Rust 拼进 system）
    expect((chatMocks.agentChatStream.mock.calls[1][0] as { content: string }[]).map((turn) => turn.content).join('\n')).not.toContain(
      'export const A = 1',
    )

    // 清空 ⇒ 上下文一起清（下一问不再带任何文件）
    await wrapper.find('[data-testid="chat-clear"]').trigger('click')
    await flushPromises()
    chatMocks.agentChatStream.mockResolvedValueOnce(answered('重新开始。'))
    await ask(wrapper, '从头来')
    expect(chatMocks.agentChatStream.mock.calls[2][1]).toEqual([])
  })
})
