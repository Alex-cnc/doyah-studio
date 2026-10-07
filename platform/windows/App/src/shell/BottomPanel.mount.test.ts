// @vitest-environment happy-dom
// BottomPanel 终端页签挂载冒烟（S-9b；S-9d 薄壳化跟版）—— 守的口径：
//   ① 终端页签挂载后**不再是「未开工」**（进得去、有真会话区域 / 入口）；
//   ② **新建 / 关闭 / 切换**各 ≥1 例；进入页签按需起会话、不重复起；
//   ③ **（S-9d）渲染源 = `chunk.screen` 投影**、**读循环不再把回话写回**（`terminalWrite` 只由键盘触发）。
// 用 `vi.mock` 把 `../ipc` 的四个包装换成可控桩：不依赖真 Tauri 外壳，也不让读循环空转。
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'

const { openMock, writeMock, readMock, closeMock } = vi.hoisted(() => ({
  openMock: vi.fn(),
  writeMock: vi.fn(),
  readMock: vi.fn(),
  closeMock: vi.fn(),
}))

vi.mock('../ipc', () => ({
  terminalOpen: openMock,
  terminalWrite: writeMock,
  terminalRead: readMock,
  terminalClose: closeMock,
}))

import BottomPanel from './BottomPanel.vue'

/** 造一个屏幕投影（只填用得上的字段）。 */
function projection(text: string, over: Record<string, unknown> = {}) {
  return {
    rows: text.split('\n'),
    text,
    cursor: { row: 0, col: 0 },
    cursorVisible: true,
    pendingResponses: [] as string[],
    eof: false,
    exitCode: null,
    ...over,
  }
}

/** 在一堆节点里按可见文案找（界面是中文），点它。 */
function clickByText(wrapper: ReturnType<typeof mount>, selector: string, text: string): Promise<void> {
  const target = wrapper.findAll(selector).find((node) => node.text().includes(text))
  if (!target) throw new Error(`找不到文案「${text}」的节点（${selector}）`)
  return target.trigger('click')
}

/** 切到终端页签并等会话起来。 */
async function enterTerminal(wrapper: ReturnType<typeof mount>): Promise<void> {
  await clickByText(wrapper, '.panel__tab', '终端')
  await flushPromises()
}

describe('BottomPanel 终端页签挂载冒烟', () => {
  let seq = 0
  beforeEach(() => {
    seq = 0
    openMock.mockReset()
    writeMock.mockReset()
    readMock.mockReset()
    closeMock.mockReset()
    openMock.mockImplementation(async () => {
      seq += 1
      return seq
    })
    writeMock.mockImplementation(async () => undefined)
    // 读端一次就报结束：挂载测试只关心会话页签的增删切换，不让读循环空转。
    readMock.mockImplementation(async () => ({ data: '', eof: true, exitCode: 0, screen: projection('') }))
    closeMock.mockImplementation(async () => undefined)
  })

  it('进入终端页签后有真会话区域（不再是「未开工」）', async () => {
    const wrapper = mount(BottomPanel, { props: { entries: [] } })
    await enterTerminal(wrapper)

    expect(openMock).toHaveBeenCalledTimes(1)
    expect(wrapper.find('.panel__terminal').exists()).toBe(true)
    // 「未开工」的说明与标题后缀都不该再出现
    expect(wrapper.text()).not.toContain('未开工')
    wrapper.unmount()
  })

  it('新建 ≥1 例：点「新建」多起一条会话', async () => {
    const wrapper = mount(BottomPanel, { props: { entries: [] } })
    await enterTerminal(wrapper)
    expect(wrapper.findAll('.panel__session')).toHaveLength(1)

    await wrapper.find('.panel__session-new').trigger('click')
    await flushPromises()

    expect(openMock).toHaveBeenCalledTimes(2)
    expect(wrapper.findAll('.panel__session')).toHaveLength(2)
    wrapper.unmount()
  })

  it('切换 ≥1 例：点会话页签能换激活的那条', async () => {
    const wrapper = mount(BottomPanel, { props: { entries: [] } })
    await enterTerminal(wrapper)
    await wrapper.find('.panel__session-new').trigger('click')
    await flushPromises()

    expect(wrapper.findAll('.panel__session')).toHaveLength(2)
    expect(wrapper.findAll('.panel__session')[1].classes()).toContain('panel__session--active')

    await wrapper.findAll('.panel__session')[0].trigger('click')
    expect(wrapper.findAll('.panel__session')[0].classes()).toContain('panel__session--active')
    expect(wrapper.findAll('.panel__session')[1].classes()).not.toContain('panel__session--active')
    wrapper.unmount()
  })

  it('关闭 ≥1 例：关掉一条会话会调 terminalClose 并摘掉页签', async () => {
    const wrapper = mount(BottomPanel, { props: { entries: [] } })
    await enterTerminal(wrapper)
    expect(wrapper.findAll('.panel__session')).toHaveLength(1)

    await wrapper.find('.panel__session-close').trigger('click')
    await flushPromises()

    expect(wrapper.findAll('.panel__session')).toHaveLength(0)
    expect(closeMock).toHaveBeenCalledTimes(1)
    expect(openMock).toHaveBeenCalledTimes(1)
    wrapper.unmount()
  })

  it('进入页签按需起会话：已有会话就不再起', async () => {
    const wrapper = mount(BottomPanel, { props: { entries: [] } })
    await enterTerminal(wrapper)
    await clickByText(wrapper, '.panel__tab', '输出')
    await clickByText(wrapper, '.panel__tab', '终端')
    await flushPromises()

    expect(openMock).toHaveBeenCalledTimes(1)
    wrapper.unmount()
  })

  // 新语义 ③-a：渲染源 = chunk.screen 投影（输出区显示投影文本，而不是原始字节）
  it('渲染源是 chunk.screen：输出区显示领域层投影文本', async () => {
    const wrapper = mount(BottomPanel, { props: { entries: [] } })
    readMock.mockImplementation(async () => ({
      data: 'RAW-BYTES-SHOULD-NOT-RENDER',
      eof: true,
      exitCode: 0,
      screen: projection('PROJ-MARK'),
    }))
    await enterTerminal(wrapper)
    await flushPromises()

    const shown = wrapper.find('.panel__term-out').text()
    expect(shown).toContain('PROJ-MARK')
    expect(shown).not.toContain('RAW-BYTES-SHOULD-NOT-RENDER')
    wrapper.unmount()
  })

  // 新语义 ③-b：读循环不再把回话写回（即便投影里带着设备查询应答，也**不由前端写回** —— 回话归 Rust 单点）
  it('不双回话：读循环不再把设备查询应答写回（terminalWrite 只由键盘触发）', async () => {
    const wrapper = mount(BottomPanel, { props: { entries: [] } })
    readMock.mockImplementation(async () => ({
      data: '',
      eof: true,
      exitCode: 0,
      // 投影里带着一条光标报告应答（消费后清空的那批）—— 前端**不许**把它写回
      screen: projection('', { pendingResponses: ['\u001b[1;1R'] }),
    }))
    await enterTerminal(wrapper)
    await flushPromises()

    expect(writeMock).not.toHaveBeenCalled()
    wrapper.unmount()
  })
})
