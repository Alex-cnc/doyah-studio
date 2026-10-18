// @vitest-environment happy-dom
// 智能体设置弹层（FR-AI-01）的**挂载判据**。
//
// 为什么必须挂一次（不是只看 tsc）：`.vue` 不在 `tsc --noEmit` 的程序里，模板引用到没 import 的
// 名字也编译得过去 —— 本仓踩过「五个 ipc 名字从未 import、点面板就 ReferenceError」那次。
// 这里钉住四件事：三态裁决各说各的话、保存把真值传给后端、密钥保存后输入框清空且**永不回显**、
// 没密钥时「清除」是灰的（点了也没用）。
import { describe, expect, it, vi, beforeEach } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import type { AgentConfiguration, AgentSettingsSnapshot } from '../ipc'

const state: {
  snapshot: AgentSettingsSnapshot
  failure: { message: string; hint: string } | null
  saved: AgentConfiguration[]
  keys: string[]
  cleared: number
} = {
  snapshot: {
    config: { enabled: false, endpoint: '', model: '', timeoutSecs: 60, hourlyLimit: 60, preset: 'custom', retryMax: 2, retryMaxMs: 4000 },
    gate: { state: 'disabled', scope: 'remote', model: '', issues: [] },
    keyPresent: false,
    keyStorage: 'dpapi',
    keyNote: null,
    configPath: 'C:/Users/x/AppData/Roaming/DoyahStudio/agent.json',
    quota: { limit: 60, used: 0, remaining: 60, windowSecs: 3600, retryAfterSecs: 0 },
  },
  failure: null,
  saved: [],
  keys: [],
  cleared: 0,
}

vi.mock('../ipc', () => ({
  agentSettingsGet: vi.fn(async () => {
    if (state.failure) throw state.failure
    return state.snapshot
  }),
  agentSettingsSave: vi.fn(async (config: AgentConfiguration) => {
    state.saved.push(config)
    state.snapshot = { ...state.snapshot, config }
    return state.snapshot
  }),
  agentKeySave: vi.fn(async (key: string) => {
    state.keys.push(key)
    state.snapshot = { ...state.snapshot, keyPresent: true }
    return state.snapshot
  }),
  agentKeyClear: vi.fn(async () => {
    state.cleared += 1
    state.snapshot = { ...state.snapshot, keyPresent: false }
    return state.snapshot
  }),
}))

import AgentSettingsDialog from './AgentSettingsDialog.vue'

function mountDialog(open = true) {
  return mount(AgentSettingsDialog, { props: { open, language: 'zh-Hans' as const } })
}

beforeEach(() => {
  state.failure = null
  state.saved = []
  state.keys = []
  state.cleared = 0
  state.snapshot = {
    config: { enabled: false, endpoint: '', model: '', timeoutSecs: 60, hourlyLimit: 60, preset: 'custom', retryMax: 2, retryMaxMs: 4000 },
    gate: { state: 'disabled', scope: 'remote', model: '', issues: [] },
    keyPresent: false,
    keyStorage: 'dpapi',
    keyNote: null,
    configPath: 'C:/Users/x/AppData/Roaming/DoyahStudio/agent.json',
    quota: { limit: 60, used: 0, remaining: 60, windowSecs: 3600, retryAfterSecs: 0 },
  }
})

describe('智能体设置弹层', () => {
  it('总开关关闭时说的是「不会向任何模型服务发送数据」', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    const gate = wrapper.get('[data-testid="agent-gate"]')
    expect(gate.text()).toContain('不会向任何模型服务发送数据')
    expect(wrapper.find('[data-testid="agent-issues"]').exists()).toBe(false)
  })

  it('缺项时逐条点名（远端缺密钥 + 缺端点 + 缺模型都列出来）', async () => {
    state.snapshot = {
      ...state.snapshot,
      config: { ...state.snapshot.config, enabled: true },
      gate: {
        state: 'missing',
        scope: 'remote',
        model: '',
        issues: [{ code: 'endpointMissing' }, { code: 'modelMissing' }, { code: 'keyMissing' }],
      },
    }
    const wrapper = mountDialog()
    await flushPromises()
    const items = wrapper.get('[data-testid="agent-issues"]').findAll('li')
    expect(items).toHaveLength(3)
    expect(items[2].text()).toContain('API Key')
  })

  it('放行时把模型名与端点类型一起说出来', async () => {
    state.snapshot = {
      ...state.snapshot,
      config: { ...state.snapshot.config, enabled: true, endpoint: 'http://localhost:11434/v1', model: 'llama3' },
      gate: { state: 'ready', scope: 'local', model: 'llama3', issues: [] },
      keyPresent: false,
    }
    const wrapper = mountDialog()
    await flushPromises()
    const text = wrapper.get('[data-testid="agent-gate"]').text()
    expect(text).toContain('llama3')
    expect(text).toContain('本机端点')
  })

  it('保存把界面上填的真值传给后端（含预设反推与去空白）', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    await wrapper.get('[data-testid="agent-endpoint"]').setValue('  https://api.deepseek.com/v1/  ')
    await wrapper.get('[data-testid="agent-model"]').setValue('  deepseek-chat  ')
    await wrapper.get('[data-testid="agent-save"]').trigger('click')
    await flushPromises()
    expect(state.saved).toHaveLength(1)
    // 只去前后空白；**不替用户改他填的端点**（尾斜杠照留 —— 悄悄改掉用户输入是另一种撒谎）。
    expect(state.saved[0].endpoint).toBe('https://api.deepseek.com/v1/')
    expect(state.saved[0].model).toBe('deepseek-chat')
    // 端点被手填 ⇒ 预设应被反推成 deepseek（下拉不能停在一个错的厂商上）
    expect(state.saved[0].preset).toBe('deepseek')
  })

  // 失败重试两格（FR-AI-30 ①）：**可配**是关键 —— 只读显示等于没配。
  it('「失败后重试」与「退避上限」两格随保存传给后端', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    expect((wrapper.get('[data-testid="agent-retry-max"]').element as HTMLInputElement).value).toBe('2')
    expect(
      (wrapper.get('[data-testid="agent-retry-max-ms"]').element as HTMLInputElement).value,
    ).toBe('4000')
    expect(wrapper.get('[data-testid="agent-retry-note"]').text()).toContain('429')

    await wrapper.get('[data-testid="agent-retry-max"]').setValue('1')
    await wrapper.get('[data-testid="agent-retry-max-ms"]').setValue('1200')
    await wrapper.get('[data-testid="agent-save"]').trigger('click')
    await flushPromises()

    expect(state.saved).toHaveLength(1)
    expect(state.saved[0].retryMax).toBe(1)
    expect(state.saved[0].retryMaxMs).toBe(1200)
  })

  it('密钥保存后输入框立刻清空（不回显），且状态改成「已配置」', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    await wrapper.get('[data-testid="agent-key-input"]').setValue('sk-round14-secret')
    await wrapper.get('[data-testid="agent-key-save"]').trigger('click')
    await flushPromises()
    expect(state.keys).toEqual(['sk-round14-secret'])
    expect((wrapper.get('[data-testid="agent-key-input"]').element as HTMLInputElement).value).toBe('')
    expect(wrapper.get('[data-testid="agent-key-state"]').text()).toContain('已配置')
  })

  it('没有密钥时「清除密钥」是灰的；有密钥时可点并真的清掉', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    const clearButton = wrapper.get('[data-testid="agent-key-clear"]')
    expect((clearButton.element as HTMLButtonElement).disabled).toBe(true)

    await wrapper.get('[data-testid="agent-key-input"]').setValue('sk-x')
    await wrapper.get('[data-testid="agent-key-save"]').trigger('click')
    await flushPromises()
    const enabledButton = wrapper.get('[data-testid="agent-key-clear"]')
    expect((enabledButton.element as HTMLButtonElement).disabled).toBe(false)
    await enabledButton.trigger('click')
    await flushPromises()
    expect(state.cleared).toBe(1)
    expect(wrapper.get('[data-testid="agent-key-state"]').text()).toContain('未配置')
  })

  it('密钥存放方式照实写出（DPAPI），并且配置文件路径也显示出来', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    expect(wrapper.get('[data-testid="agent-key-state"]').text()).toContain('DPAPI')
    expect(wrapper.get('[data-testid="agent-path"]').text()).toContain('agent.json')
  })

  it('读设置失败时给「原话 + 出路」两段，而不是一片空白', async () => {
    state.failure = { message: '智能体配置读不出来：坏 JSON', hint: '先备份再删掉它' }
    const wrapper = mountDialog()
    await flushPromises()
    const error = wrapper.get('[data-testid="agent-error"]').text()
    expect(error).toContain('坏 JSON')
    expect(error).toContain('先备份再删掉它')
  })

  it('设置面上就看得见「本小时已用 N/M（还剩 K 次）」', async () => {
    state.snapshot = {
      ...state.snapshot,
      quota: { limit: 60, used: 3, remaining: 57, windowSecs: 3600, retryAfterSecs: 0 },
    }
    const wrapper = mountDialog()
    await flushPromises()
    const text = wrapper.get('[data-testid="agent-quota-text"]').text()
    expect(text).toContain('3/60')
    expect(text).toContain('还剩 57 次')
  })

  it('满额时不写「还剩 0 次」了事，而是说清还要等几分钟', async () => {
    state.snapshot = {
      ...state.snapshot,
      config: { ...state.snapshot.config, hourlyLimit: 5 },
      quota: { limit: 5, used: 5, remaining: 0, windowSecs: 3600, retryAfterSecs: 600 },
    }
    const wrapper = mountDialog()
    await flushPromises()
    const text = wrapper.get('[data-testid="agent-quota-text"]').text()
    expect(text).toContain('满额')
    expect(text).toContain('10 分钟')
    // 满额态要能一眼看出来（走的是「暖色」那一档，不是同一片灰字）
    expect(wrapper.get('[data-testid="agent-quota-text"]').classes()).toContain('agent__quota-text--full')
  })

  it('「刷新读数」重取快照，但不把没保存的草稿清掉', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    expect(wrapper.get('[data-testid="agent-quota-text"]').text()).toContain('0/60')

    // 用户在弹层开着的时候在编辑器里发了几次生成 ⇒ 台账变了
    state.snapshot = {
      ...state.snapshot,
      quota: { limit: 60, used: 4, remaining: 56, windowSecs: 3600, retryAfterSecs: 0 },
    }
    await wrapper.get('[data-testid="agent-endpoint"]').setValue('http://localhost:11434/v1')
    await wrapper.get('[data-testid="agent-quota-refresh"]').trigger('click')
    await flushPromises()

    expect(wrapper.get('[data-testid="agent-quota-text"]').text()).toContain('4/60')
    // 刷新只换读数：草稿里没保存的端点还在（刷新把用户输入清掉是另一种数据丢失）
    expect((wrapper.get('[data-testid="agent-endpoint"]').element as HTMLInputElement).value).toBe(
      'http://localhost:11434/v1',
    )
  })
})
