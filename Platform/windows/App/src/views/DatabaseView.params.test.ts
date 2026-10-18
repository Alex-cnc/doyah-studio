// @vitest-environment happy-dom
// 两条需求的**界面判据**（挂载真组件）：
//   · FR-EXEC-17：有占位符才弹填值面板、缺值不许执行、绑定结果只用于本次执行；
//   · FR-EXEC-07：执行中的页签关闭按钮**置灰并写明原因**，跑完恢复可关。
//
// 为什么要挂载而不是只测纯逻辑：这两条的真值都在**模板上**（按钮 disabled、面板出不出现）——
// `tsc` 不校验模板，纯逻辑测也看不到 DOM，只有真挂一次才判得着。
import { describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'

/** 让某一次执行卡住不返回（用来观察「执行中」那一刻的界面）。 */
const gate = vi.hoisted(() => {
  let release: (() => void) | null = null
  return {
    hold(): Promise<void> {
      return new Promise<void>((resolve) => {
        release = resolve
      })
    },
    open(): void {
      release?.()
      release = null
    },
  }
})

vi.mock('../ipc', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../ipc')>()
  return {
    ...actual,
    // 扫描：只认 `:name`（测试里够用，且能证明「没占位符就不弹面板」）
    scanSqlParameters: vi.fn(async (sql: string) =>
      sql.includes(':name')
        ? { sites: [{ name: ':name', occurrences: 1, positional: false }], hasParameters: true }
        : { sites: [], hasParameters: false },
    ),
    // 绑定：如实把值写成一个字面量（真绑定在 Rust 侧，这里只验「界面把值送到了哪」）
    bindSqlParameters: vi.fn(async (_sql: string, values: { name: string; value: string; kind: string }[]) => ({
      sql: `select * from t where name = '${values[0]?.value ?? ''}'`,
      params: [{ name: ':name', occurrences: 1, kind: 'text', literal: `'${values[0]?.value ?? ''}'` }],
      unused: [],
    })),
    dbRunBatch: vi.fn(async () => {
      await gate.hold()
      return []
    }),
    dbQuery: vi.fn(async () => {
      await gate.hold()
      return { columns: [], rows: [], rowCount: 0, truncated: false, elapsedMs: 0 } as never
    }),
  }
})

import * as ipc from '../ipc'
import DatabaseView from './DatabaseView.vue'

async function mountView() {
  const wrapper = mount(DatabaseView)
  await flushPromises()
  return wrapper
}

describe('FR-EXEC-17 · 查询参数填值面板', () => {
  it('有占位符 ⇒ 点执行先弹面板（不把 :name 原样发给服务端）', async () => {
    const wrapper = await mountView()
    await wrapper.find('textarea[aria-label="SQL"]').setValue('select * from t where name = :name')
    await wrapper.find('form.db__sql').trigger('submit')
    await flushPromises()

    expect(wrapper.find('[data-testid="param-panel"]').exists()).toBe(true)
    expect(wrapper.find('[data-testid="param-name-0"]').text()).toBe(':name')
    // 缺值 ⇒ 执行按钮是灰的
    expect(wrapper.find('[data-testid="param-run"]').attributes('disabled')).toBeDefined()
    // 一条语句都还没发出去
    expect(vi.mocked(ipc.dbRunBatch)).not.toHaveBeenCalled()
    wrapper.unmount()
  })

  it('填好之后执行：绑定值被送到执行，编辑器里的占位符原样留着', async () => {
    const wrapper = await mountView()
    await wrapper.find('textarea[aria-label="SQL"]').setValue('select * from t where name = :name')
    await wrapper.find('form.db__sql').trigger('submit')
    await flushPromises()

    await wrapper.find('[data-testid="param-value-0"]').setValue('x\'; DROP TABLE t; --')
    await flushPromises()
    expect(wrapper.find('[data-testid="param-run"]').attributes('disabled')).toBeUndefined()

    await wrapper.find('[data-testid="param-panel"]').trigger('submit')
    await flushPromises()

    // 绑定收到的是用户那股原样的值（转义在领域层做，界面不许自己拼串）
    expect(vi.mocked(ipc.bindSqlParameters)).toHaveBeenCalledWith('select * from t where name = :name', [
      { name: ':name', value: "x'; DROP TABLE t; --", kind: 'text' },
    ])
    // 执行的是**绑定后**的语句
    expect(vi.mocked(ipc.dbRunBatch)).toHaveBeenCalledWith("select * from t where name = 'x'; DROP TABLE t; --'")
    // 面板收掉，回执说出绑定结果
    expect(wrapper.find('[data-testid="param-panel"]').exists()).toBe(false)
    expect(wrapper.find('[data-testid="param-note"]').text()).toContain('参数已绑定')
    // 编辑器里的占位符**一个字都没动**（绑定只用于这一次执行）
    expect((wrapper.find('textarea[aria-label="SQL"]').element as HTMLTextAreaElement).value).toContain(':name')

    gate.open()
    await flushPromises()
    wrapper.unmount()
  })

  it('取消 ⇒ 一句「没有执行」，且真的没发语句', async () => {
    const wrapper = await mountView()
    await wrapper.find('textarea[aria-label="SQL"]').setValue('select * from t where name = :name')
    await wrapper.find('form.db__sql').trigger('submit')
    await flushPromises()
    await wrapper.find('[data-testid="param-cancel"]').trigger('click')
    await flushPromises()

    expect(wrapper.find('[data-testid="param-panel"]').exists()).toBe(false)
    expect(wrapper.find('[data-testid="param-note"]').text()).toContain('没有执行')
    expect(vi.mocked(ipc.dbRunBatch)).not.toHaveBeenCalled()
    wrapper.unmount()
  })

  it('没有占位符 ⇒ 不弹面板，直接执行（不打断日常查询）', async () => {
    const wrapper = await mountView()
    await wrapper.find('textarea[aria-label="SQL"]').setValue('select 1')
    await wrapper.find('form.db__sql').trigger('submit')
    await flushPromises()

    expect(wrapper.find('[data-testid="param-panel"]').exists()).toBe(false)
    expect(vi.mocked(ipc.dbRunBatch)).toHaveBeenCalledWith('select 1')
    gate.open()
    await flushPromises()
    wrapper.unmount()
  })
})

describe('FR-EXEC-07 · 执行中的页签不可关闭', () => {
  it('执行中：关闭按钮置灰且 title 说明原因；跑完恢复可关', async () => {
    const wrapper = await mountView()
    // 先有第二张页签（最后一张本来就不许关，会把结论混掉）
    await wrapper.find('.db__qtab-add').trigger('click')
    await flushPromises()

    await wrapper.find('textarea[aria-label="SQL"]').setValue('select 1')
    await wrapper.find('form.db__sql').trigger('submit')
    await flushPromises()

    const closeBefore = wrapper.findAll('[data-testid="qtab-close"]')
    expect(closeBefore.length).toBe(2)
    const runningTabClose = closeBefore[closeBefore.length - 1]
    expect(runningTabClose.attributes('disabled')).toBeDefined()
    expect(runningTabClose.attributes('title')).toContain('正在执行查询')

    gate.open()
    await flushPromises()

    const closeAfter = wrapper.findAll('[data-testid="qtab-close"]')
    expect(closeAfter[closeAfter.length - 1].attributes('disabled')).toBeUndefined()
    wrapper.unmount()
  })
})
