// @vitest-environment happy-dom
// Schema 对比与同步面板（FR-DDL-04）的**挂载判据**。
//
// 为什么必须有这一条：`tsc --noEmit` 不校验 .vue（模板里引用了没 import 的名字也编译不出错），
// 纯逻辑测又碰不到模板 —— 只有真挂一次才看得见「按钮点了有没有反应、三态有没有如实显示」。
import { describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import type { SchemaDiffReport, SchemaSnapshot } from '../ipc'

const state: {
  snapshot: SchemaSnapshot
  report: SchemaDiffReport
  failure: { message: string; hint: string } | null
  calls: { snapshots: number; diffs: number; allowDrop: boolean[] }
} = {
  snapshot: { label: '侧', schema: 'public', takenAt: 0, tables: [] },
  report: {
    baseLabel: '基准（左）',
    targetLabel: '目标（右）',
    baseTableCount: 2,
    targetTableCount: 1,
    tableDiffs: [],
    statements: [],
    skipped: [],
    allowDrop: false,
    destructiveCount: 0,
    createdTables: 0,
    alteredTables: 0,
    droppedTables: 0,
  },
  failure: null,
  calls: { snapshots: 0, diffs: 0, allowDrop: [] },
}

vi.mock('../ipc', () => ({
  schemaSnapshot: vi.fn(async (_schema: string, label: string) => {
    state.calls.snapshots += 1
    if (state.failure) throw state.failure
    const snap = state.snapshot
    return { ...snap, label, schema: _schema }
  }),
  schemaDiffPlan: vi.fn(async (_base: SchemaSnapshot, _target: SchemaSnapshot, allowDrop: boolean) => {
    state.calls.diffs += 1
    state.calls.allowDrop.push(allowDrop)
    return { ...state.report, allowDrop }
  }),
}))

import SchemaDiffPanel from './SchemaDiffPanel.vue'

function reset(): void {
  state.failure = null
  state.calls = { snapshots: 0, diffs: 0, allowDrop: [] }
  state.report = {
    baseLabel: '基准（左）',
    targetLabel: '目标（右）',
    baseTableCount: 2,
    targetTableCount: 1,
    tableDiffs: [],
    statements: [],
    skipped: [],
    allowDrop: false,
    destructiveCount: 0,
    createdTables: 0,
    alteredTables: 0,
    droppedTables: 0,
  }
}

function mountPanel() {
  return mount(SchemaDiffPanel, { props: { language: 'zh-Hans' as const } })
}

async function captureBoth(wrapper: ReturnType<typeof mountPanel>): Promise<void> {
  await wrapper.find('[data-testid="schema-capture-base"]').trigger('click')
  await flushPromises()
  await wrapper.find('[data-testid="schema-capture-target"]').trigger('click')
  await flushPromises()
}

describe('FR-DDL-04 · Schema 对比面板', () => {
  it('初始态：两侧都说「还没抓」，对比按钮不可点（不能让用户点了没反应）', () => {
    reset()
    const wrapper = mountPanel()
    expect(wrapper.find('[data-testid="schema-base-state"]').text()).toBe('还没抓')
    expect(wrapper.find('[data-testid="schema-target-state"]').text()).toBe('还没抓')
    expect(wrapper.find('[data-testid="schema-compare"]').attributes('disabled')).toBeDefined()
    expect(wrapper.find('[data-testid="schema-script"]').exists()).toBe(false)
    wrapper.unmount()
  })

  it('两侧都抓到就自动对比一次，并把差异逐张列出来', async () => {
    reset()
    state.report = {
      ...state.report,
      createdTables: 1,
      tableDiffs: [
        {
          table: 'orders',
          status: 'create',
          addedColumns: ['id', 'memo'],
          removedColumns: [],
          alteredColumns: [],
          primaryKeyDiffers: false,
        },
        {
          table: 'legacy',
          status: 'alter',
          addedColumns: [],
          removedColumns: ['old_note'],
          alteredColumns: [],
          primaryKeyDiffers: true,
        },
      ],
    }
    const wrapper = mountPanel()
    await captureBoth(wrapper)

    expect(state.calls.snapshots).toBe(2)
    expect(state.calls.diffs).toBe(1)
    const diffs = wrapper.find('[data-testid="schema-diffs"]')
    expect(diffs.exists()).toBe(true)
    expect(diffs.text()).toContain('orders')
    expect(diffs.text()).toContain('建表')
    expect(wrapper.find('[data-testid="schema-diff-legacy"]').text()).toContain('主键不同')
    wrapper.unmount()
  })

  it('跳过的差异如实显示（关着删除时：不生成语句，但必须说清跳过了什么）', async () => {
    reset()
    state.report = {
      ...state.report,
      skipped: [{ table: 'legacy', what: '删除表（目标库多出来的表，3 列）', reason: '删除默认不生成' }],
    }
    const wrapper = mountPanel()
    await captureBoth(wrapper)

    const skipped = wrapper.find('[data-testid="schema-skipped"]')
    expect(skipped.exists()).toBe(true)
    expect(skipped.text()).toContain('legacy')
    expect(skipped.text()).toContain('删除默认不生成')
    expect(wrapper.find('[data-testid="schema-script"]').exists()).toBe(false)
    wrapper.unmount()
  })

  it('两侧一致时说「一致」，而不是给一块空白面板', async () => {
    reset()
    const wrapper = mountPanel()
    await captureBoth(wrapper)
    expect(wrapper.find('[data-testid="schema-in-sync"]').exists()).toBe(true)
    wrapper.unmount()
  })

  it('勾「允许删除」会把开关当真传给后端（不是界面自说自话）', async () => {
    reset()
    const wrapper = mountPanel()
    await captureBoth(wrapper)
    await wrapper.find('[data-testid="schema-allow-drop"]').setValue(true)
    await flushPromises()
    expect(state.calls.allowDrop.at(-1)).toBe(true)
    wrapper.unmount()
  })

  it('生成脚本后能复制 / 送去编辑器（脚本是唯一出口，面板里没有执行按钮）', async () => {
    reset()
    state.report = {
      ...state.report,
      statements: [
        {
          sql: '-- 建表 orders\nCREATE TABLE "public"."orders" ("id" integer);',
          bare: 'CREATE TABLE "public"."orders" ("id" integer);',
          class: 'additive',
          purpose: '建表',
        },
      ],
    }
    const wrapper = mountPanel()
    await captureBoth(wrapper)

    const script = wrapper.find('[data-testid="schema-script"]')
    expect(script.text()).toContain('CREATE TABLE')
    await wrapper.find('[data-testid="schema-open"]').trigger('click')
    const emitted = wrapper.emitted('open-sql')
    expect(emitted).toBeTruthy()
    expect(String(emitted?.[0]?.[0])).toContain('CREATE TABLE')
    // 面板里不许出现「执行」按钮
    expect(wrapper.findAll('button').every((b) => !b.text().includes('执行'))).toBe(true)
    wrapper.unmount()
  })

  it('抓取失败给服务端原话（不静默留一个空面板）', async () => {
    reset()
    state.failure = { message: '没有连接', hint: '先在连接面板连上服务端' }
    const wrapper = mountPanel()
    await wrapper.find('[data-testid="schema-capture-base"]').trigger('click')
    await flushPromises()

    const error = wrapper.find('[data-testid="schema-error"]')
    expect(error.exists()).toBe(true)
    expect(error.text()).toContain('没有连接')
    expect(error.text()).toContain('先在连接面板连上服务端')
    expect(wrapper.find('[data-testid="schema-base-state"]').text()).toBe('还没抓')
    wrapper.unmount()
  })
})
