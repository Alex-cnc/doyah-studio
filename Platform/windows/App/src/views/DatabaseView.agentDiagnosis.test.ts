// @vitest-environment happy-dom
// 诊断入口在**数据库视图**上的判据（挂载真组件）：
//   · 编辑器状态栏那枚「诊断…」真能打开面板，且面板拿到的是**编辑器里那句 SQL**；
//   · 面板采纳的建议只**追加**进编辑器（原有 SQL 一个字节不动），**不执行**。
//
// 为什么必须挂载：入口在不在、点了传下去的是哪份文本，这两条都在模板与组件边界上。
import { describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'

const calls = vi.hoisted(() => {
  return { explain: [] as string[], batch: [] as string[] }
})

vi.mock('../ipc', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../ipc')>()
  return {
    ...actual,
    explainStatement: vi.fn(async (sql: string) => {
      calls.explain.push(sql)
      return 'Seq Scan on orders  (cost=0.00..1.00 rows=1)'
    }),
    dbQuery: vi.fn(async () => ({ columns: ['pid'], rows: [], numRows: [], returned: 0, truncated: false, affected: null })),
    slowQueries: vi.fn(async () => ({
      available: false,
      installed: false,
      availableExtension: false,
      preloaded: false,
      reason: '服务端没有 pg_stat_statements',
      steps: [],
      totalColumn: '',
      meanColumn: '',
      rowsOut: [],
    })),
    statementRisk: vi.fn(async () => 'safe'),
    // 执行通道：只记调用。诊断面板**一次都不许**走这里（本轮的否定面）。
    dbRunBatch: vi.fn(async (text: string) => {
      calls.batch.push(text)
      return []
    }),
  }
})

import DatabaseView from './DatabaseView.vue'

async function openDiagnosisPanel() {
  calls.explain = []
  calls.batch = []
  const wrapper = mount(DatabaseView)
  await flushPromises()
  await wrapper.find('textarea[aria-label="SQL"]').setValue('select * from orders where buyer_id = 1')
  await wrapper.find('[data-testid="editor-diagnose"]').trigger('click')
  await flushPromises()
  return wrapper
}

describe('数据库视图 · 诊断入口', () => {
  it('状态栏那枚按钮打开面板，面板拿着编辑器里的 SQL 去取执行计划', async () => {
    const wrapper = await openDiagnosisPanel()
    expect(wrapper.find('[data-testid="diagnosis-panel"]').exists()).toBe(true)
    expect(calls.explain).toEqual(['select * from orders where buyer_id = 1'])
    const brief = (wrapper.find('[data-testid="diagnosis-brief"]').element as HTMLTextAreaElement).value
    expect(brief).toContain('EXPLAIN select * from orders where buyer_id = 1')
  })

  it('采纳的建议追加进编辑器（原有 SQL 不动），且一次都没执行', async () => {
    const wrapper = await openDiagnosisPanel()
    await wrapper.find('[data-testid="diagnosis-reply"]').setValue('结论: 缺索引 [依据: e1]\n建议: create index on orders(buyer_id)')
    await wrapper.find('[data-testid="diagnosis-parse"]').trigger('click')
    await flushPromises()
    await wrapper.find('[data-testid="diagnosis-insert"]').trigger('click')
    await flushPromises()

    const area = wrapper.find('textarea[aria-label="SQL"]').element as HTMLTextAreaElement
    expect(area.value).toContain('select * from orders where buyer_id = 1')
    expect(area.value).toContain('create index on orders(buyer_id)')
    // 否定面：诊断面板不许替用户执行任何东西
    expect(calls.batch).toEqual([])
  })

  it('关掉面板后整块消失', async () => {
    const wrapper = await openDiagnosisPanel()
    await wrapper.find('[data-testid="diagnosis-close"]').trigger('click')
    await flushPromises()
    expect(wrapper.find('[data-testid="diagnosis-panel"]').exists()).toBe(false)
  })
})
