// @vitest-environment happy-dom
// FR-DIAG-03（慢查询排行）的**界面判据**（挂载真组件）：
//   · 可用时列出排行行，切排序会按新口径重取；
//   · 扩展不可用时出现「原因 + 三步指引」，**且没有排行表**（空列表冒充「没有慢查询」= 假绿）；
//   · 读取失败时给可读原因，不是静默空表。
//
// 为什么必须挂载：这三条的真值都在**模板**上（哪一段渲染、有没有那张表）——
// `tsc --noEmit` 不校验 .vue，纯逻辑测也看不到 DOM。
import { describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'

const slowReply = vi.hoisted(() => {
  return {
    current: null as unknown,
    calls: [] as string[],
  }
})

vi.mock('../ipc', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../ipc')>()
  return {
    ...actual,
    slowQueries: vi.fn(async (sort: string) => {
      slowReply.calls.push(sort)
      const reply = slowReply.current
      if (reply instanceof Error) throw reply
      return reply
    }),
    // 管理面板的入口挂在**结果区工具条**上（有结果才渲染）⇒ 先让一条查询回来
    // （提交走的是多段执行：`dbRunBatch` 回一条带 result 的段结果）
    dbRunBatch: vi.fn(async (text: string) => [
      {
        sql: text,
        ok: true,
        result: { columns: ['one'], rows: [['1']], rowCount: 1, truncated: false, elapsedMs: 1 },
        failure: null,
        elapsedMs: 1,
      },
    ]),
  }
})

import DatabaseView from './DatabaseView.vue'

async function mountView() {
  slowReply.calls = []
  const wrapper = mount(DatabaseView)
  await flushPromises()
  // 管理面板的入口在**结果区工具条**上（有结果才渲染）⇒ 先跑一条查询把结果区撑出来
  await wrapper.find('textarea[aria-label="SQL"]').setValue('select 1')
  await wrapper.find('form.db__sql').trigger('submit')
  await flushPromises()
  await wrapper.find('[title="管理面板"]').trigger('click')
  await flushPromises()
  return wrapper
}

const available = {
  available: true,
  installed: true,
  availableExtension: true,
  preloaded: true,
  reason: null,
  steps: [],
  totalColumn: 'total_exec_time',
  meanColumn: 'mean_exec_time',
  rowsOut: [
    {
      query: 'select * from orders where buyer_id = $1',
      calls: 42,
      totalMs: 1500,
      meanMs: 35.7,
      rows: 900,
      truncated: false,
    },
    { query: 'select count(*) from items', calls: 7, totalMs: 900, meanMs: 128.5, rows: 1, truncated: true },
  ],
}

const unavailable = {
  available: false,
  installed: false,
  availableExtension: true,
  preloaded: false,
  reason: '扩展文件在，但没被预加载（shared_preload_libraries 里没有它）',
  steps: [
    "① 预加载：shared_preload_libraries = 'pg_stat_statements'",
    '② 重启服务端',
    '③ 建扩展：CREATE EXTENSION IF NOT EXISTS pg_stat_statements',
  ],
  totalColumn: '',
  meanColumn: '',
  rowsOut: [],
}

describe('FR-DIAG-03 · 慢查询排行面板', () => {
  it('可用时列出排行行、并显示本次用的时间列', async () => {
    slowReply.current = available
    const wrapper = await mountView()

    const rows = wrapper.find('[data-testid="slow-rows"]')
    expect(rows.exists()).toBe(true)
    expect(rows.findAll('li').length).toBe(2)
    expect(rows.text()).toContain('select * from orders')
    // 时间列名要露出来（PG12 与 13+ 列名不同，用户要能对上）
    expect(wrapper.find('[data-testid="slow-columns"]').text()).toContain('total_exec_time')
    // 被截断的那条要如实标
    expect(rows.text()).toContain('文本已截断')
    // 不可用那一段不该出现
    expect(wrapper.find('[data-testid="slow-unavailable"]').exists()).toBe(false)

    wrapper.unmount()
  })

  it('切排序会按新口径重取（口径字符串与领域层一致）', async () => {
    slowReply.current = available
    const wrapper = await mountView()
    expect(slowReply.calls).toEqual(['total'])

    await wrapper.find('[data-testid="slow-sort"]').setValue('calls')
    await flushPromises()

    expect(slowReply.calls).toEqual(['total', 'calls'])
    wrapper.unmount()
  })

  it('扩展不可用：给原因 + 三步指引，且没有排行表（不用空列表冒充「没有慢查询」）', async () => {
    slowReply.current = unavailable
    const wrapper = await mountView()

    expect(wrapper.find('[data-testid="slow-unavailable"]').text()).toContain('shared_preload_libraries')
    const steps = wrapper.find('[data-testid="slow-steps"]')
    expect(steps.exists()).toBe(true)
    expect(steps.findAll('li').length).toBe(3)
    expect(steps.text()).toContain('CREATE EXTENSION')
    // 关键否定面：没有排行表、也没有「0 条」那句（那两句都会被读成「库里没有慢查询」）
    expect(wrapper.find('[data-testid="slow-rows"]').exists()).toBe(false)
    expect(wrapper.find('[data-testid="slow-empty"]').exists()).toBe(false)

    wrapper.unmount()
  })

  it('读取失败：给可读原因，不是静默空表', async () => {
    slowReply.current = new Error('服务端拒绝了这条查询：permission denied')
    const wrapper = await mountView()

    const note = wrapper.find('[data-testid="slow-note"]')
    expect(note.exists()).toBe(true)
    expect(note.text()).toContain('permission denied')
    expect(wrapper.find('[data-testid="slow-rows"]').exists()).toBe(false)

    wrapper.unmount()
  })
})
