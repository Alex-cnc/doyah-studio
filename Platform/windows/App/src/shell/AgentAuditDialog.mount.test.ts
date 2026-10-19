// @vitest-environment happy-dom
// 智能体审计记录弹层（`FR-AI-09` 的审计半）的**挂载判据**。
//
// 为什么必须挂一次（不是只看 tsc）：`.vue` 不在 `tsc --noEmit` 的程序里 —— 模板引用了没 import 的名字
// 照样编译得过，点开才 ReferenceError（本仓踩过）。这里钉四件事：
//   ① 四档结局各说各的话，且「过网 / 没过网」分开说（被挡住的那几次确实一条都没发）；
//   ② 失败原因与服务端原话照实显示（不是只显示「失败」两个字）；
//   ③ 空态与「读不出来」是**两种**界面（读不出来时不许显示「还没有任何外发尝试」）；
//   ④ 每次打开都重新取一份（弹层一直开着时不许显示陈的读数）。
import { describe, expect, it, vi, beforeEach } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import type { AgentAuditRecord } from '../ipc'

const state: {
  records: AgentAuditRecord[]
  failure: { message: string; hint: string } | null
  loads: number
  exports: string[]
  exportFailure: { message: string; hint: string } | null
} = { records: [], failure: null, loads: 0, exports: [], exportFailure: null }

vi.mock('../ipc', () => ({
  agentAuditList: vi.fn(async () => {
    state.loads += 1
    if (state.failure) throw state.failure
    return state.records
  }),
  agentAuditExport: vi.fn(async (format: 'json' | 'csv') => {
    state.exports.push(format)
    if (state.exportFailure) throw state.exportFailure
    return {
      path: `C:/Users/Alex/AppData/Roaming/doyah/agent-audit-export-1.${format}`,
      bytes: 512,
      entries: state.records.length,
      format,
    }
  }),
}))

import AgentAuditDialog from './AgentAuditDialog.vue'

function record(over: Partial<AgentAuditRecord> = {}): AgentAuditRecord {
  return {
    atSecs: 1792331964,
    verdict: 'ok',
    model: 'fake-model',
    endpoint: 'http://127.0.0.1:1/v1',
    summary: '每天的订单数',
    detail: '',
    durationMs: 42,
    tableCount: 1,
    inputTokens: 0,
    outputTokens: 0,
    ...over,
  }
}

function mountDialog(open = true) {
  return mount(AgentAuditDialog, { props: { open, language: 'zh-Hans' as const } })
}

beforeEach(() => {
  state.records = []
  state.failure = null
  state.loads = 0
  state.exports = []
  state.exportFailure = null
})

describe('智能体审计记录弹层', () => {
  it('四档结局各说各的话，且「有没有出网」分开说', async () => {
    state.records = [
      record({ verdict: 'ok' }),
      record({ verdict: 'failed', detail: '模型服务返回 HTTP 500：boom', model: 'm', tableCount: 0 }),
      record({ verdict: 'blocked', detail: '外发闸门不放行：总开关关闭', model: '', tableCount: 0, durationMs: 0 }),
      record({ verdict: 'throttled', detail: '本小时已满额（上限 5 次，已用 5 次）', model: 'm', tableCount: 0 }),
    ]
    const wrapper = mountDialog()
    await flushPromises()

    const rows = wrapper.findAll('[data-testid="audit-row"]')
    expect(rows).toHaveLength(4)
    expect(rows[0].text()).toContain('成功')
    expect(rows[1].text()).toContain('失败')
    expect(rows[2].text()).toContain('被闸门挡住')
    expect(rows[3].text()).toContain('被每小时上限挡住')

    // 过网 / 没过网：前两条真的发出去过，后两条一条字节都没发。
    const egress = wrapper.findAll('[data-testid="audit-egress"]')
    expect(egress[0].text()).toContain('已出网')
    expect(egress[1].text()).toContain('已出网')
    expect(egress[2].text()).toContain('未出网')
    expect(egress[3].text()).toContain('未出网')

    // 失败原因照实显示（只写「失败」等于什么都没说）。
    expect(rows[1].text()).toContain('HTTP 500')
    expect(rows[2].text()).toContain('总开关')
    // 元信息：模型 / 表数 / 耗时都要露出来（用户据此判断「发了多少东西出去」）。
    expect(rows[0].text()).toContain('fake-model')
    expect(rows[0].text()).toContain('1 张表')
    expect(rows[0].text()).toContain('42')
  })

  it('一条都没有时说「还没有任何外发尝试」，而不是一片空白', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    expect(wrapper.find('[data-testid="audit-empty"]').exists()).toBe(true)
    expect(wrapper.find('[data-testid="audit-list"]').exists()).toBe(false)
  })

  it('读不出来时显示原因，绝不显示成「还没有任何外发尝试」', async () => {
    state.failure = { message: '读审计记录失败：拒绝访问', hint: '确认该文件可写。' }
    const wrapper = mountDialog()
    await flushPromises()
    const error = wrapper.find('[data-testid="audit-error"]')
    expect(error.exists()).toBe(true)
    expect(error.text()).toContain('拒绝访问')
    expect(error.text()).toContain('确认该文件可写')
    // 否定面：故障被空态掩盖，就等于骗人。
    expect(wrapper.find('[data-testid="audit-empty"]').exists()).toBe(false)
  })

  it('每次重新打开都再取一份（开着时发过生成，回来要看到新的那几条）', async () => {
    const wrapper = mountDialog(true)
    await flushPromises()
    expect(state.loads).toBe(1)

    state.records = [record({ verdict: 'blocked', detail: '外发闸门不放行：总开关关闭' })]
    await wrapper.setProps({ open: false })
    await wrapper.setProps({ open: true })
    await flushPromises()
    expect(state.loads).toBe(2)
    expect(wrapper.find('[data-testid="audit-row"]').text()).toContain('被闸门挡住')
  })

  // ---- `FR-AI-24`：成本字段 / 汇总 / 可导出 ----

  it('每条显示入出 token，底部一条汇总 = 明细之和', async () => {
    state.records = [
      record({ inputTokens: 120, outputTokens: 34 }),
      record({ verdict: 'failed', inputTokens: 9, outputTokens: 1, detail: 'HTTP 500' }),
    ]
    const wrapper = mountDialog()
    await flushPromises()

    const tokens = wrapper.findAll('[data-testid="audit-tokens"]')
    expect(tokens).toHaveLength(2)
    expect(tokens[0].text()).toContain('入 120 · 出 34 tokens')
    expect(tokens[1].text()).toContain('入 9 · 出 1 tokens')

    const totals = wrapper.find('[data-testid="audit-totals"]')
    expect(totals.exists()).toBe(true)
    expect(totals.text()).toContain('共 2 条')
    expect(totals.text()).toContain('出网 2 次')
    expect(totals.text()).toContain('入 129')
    expect(totals.text()).toContain('出 35')
  })

  it('没记到用量时写「没记到」，不画 0 个 token', async () => {
    // 否定面：0 / 0 的语义是「服务端没回 usage」，画成 `入 0 · 出 0` 等于告诉用户「这次免费」。
    state.records = [record({ inputTokens: 0, outputTokens: 0 })]
    const wrapper = mountDialog()
    await flushPromises()

    const tokens = wrapper.find('[data-testid="audit-tokens"]')
    expect(tokens.text()).toContain('没记到用量')
    expect(tokens.text()).not.toContain('入 0')
    const totals = wrapper.find('[data-testid="audit-totals"]')
    expect(totals.text()).toContain('用量没记到')
    expect(totals.text()).not.toContain('入 0')
  })

  it('点导出真的调命令，并把落点与字节数画出来', async () => {
    state.records = [record({ inputTokens: 1, outputTokens: 2 })]
    const wrapper = mountDialog()
    await flushPromises()

    await wrapper.find('[data-testid="audit-export-csv"]').trigger('click')
    await flushPromises()
    expect(state.exports).toEqual(['csv'])
    const note = wrapper.find('[data-testid="audit-exported"]')
    expect(note.exists()).toBe(true)
    expect(note.text()).toContain('已导出 1 条到')
    expect(note.text()).toContain('agent-audit-export-1.csv')
    expect(note.text()).toContain('512 字节')

    await wrapper.find('[data-testid="audit-export-json"]').trigger('click')
    await flushPromises()
    expect(state.exports).toEqual(['csv', 'json'])
    expect(wrapper.find('[data-testid="audit-exported"]').text()).toContain('.json')
  })

  it('导出失败时显示原因，不装作导出成功', async () => {
    state.records = [record()]
    state.exportFailure = { message: '写导出文件失败：拒绝访问', hint: '确认该目录可写。' }
    const wrapper = mountDialog()
    await flushPromises()

    await wrapper.find('[data-testid="audit-export-csv"]').trigger('click')
    await flushPromises()
    const error = wrapper.find('[data-testid="audit-export-error"]')
    expect(error.exists()).toBe(true)
    expect(error.text()).toContain('拒绝访问')
    // 否定面：失败时不许同时显示「已导出」。
    expect(wrapper.find('[data-testid="audit-exported"]').exists()).toBe(false)
  })

  it('一条记录都没有时导出按钮是灰的（导出一本空账没有意义）', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    expect(wrapper.find('[data-testid="audit-export-csv"]').attributes('disabled')).toBeDefined()
    expect(wrapper.find('[data-testid="audit-totals"]').exists()).toBe(false)
  })
})
