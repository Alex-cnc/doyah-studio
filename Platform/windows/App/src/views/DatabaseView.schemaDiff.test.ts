// @vitest-environment happy-dom
// FR-DDL-04 的**入口判据**：Schema 对比面板必须真的能从界面点开（否则功能等于不存在）。
//
// 为什么单独一条：第 12 轮的教训是「面板里五个名字从没 import，一点就抛 ReferenceError，
// 而 tsc 全程绿」—— .vue 的类型门不查模板，**只有挂载 + 点一下**才判得出来。
// 这里顺带验一条：浏览器旁路没有真库时，点「抓当前结构」要**说出原因**，不能用空快照冒充空库。
import { describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'

vi.mock('../ipc', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../ipc')>()
  return {
    ...actual,
    // 结果区工具条上才有入口 ⇒ 先让一条查询回来
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

async function mountWithResult() {
  const wrapper = mount(DatabaseView)
  await flushPromises()
  await wrapper.find('textarea[aria-label="SQL"]').setValue('select 1')
  await wrapper.find('form.db__sql').trigger('submit')
  await flushPromises()
  return wrapper
}

describe('FR-DDL-04 · 界面入口', () => {
  it('工具条上有「结构对比」入口，点一下就把面板挂出来，再点关闭就收回去', async () => {
    const wrapper = await mountWithResult()

    const entry = wrapper.find('[data-testid="schema-open-panel"]')
    expect(entry.exists()).toBe(true)
    expect(wrapper.find('[data-testid="schema-diff"]').exists()).toBe(false)

    await entry.trigger('click')
    await flushPromises()
    const panel = wrapper.find('[data-testid="schema-diff"]')
    expect(panel.exists()).toBe(true)
    // 面板本体：两侧槽位 + 对比按钮都在（不是一个空壳）
    expect(panel.find('[data-testid="schema-slot-base"]').exists()).toBe(true)
    expect(panel.find('[data-testid="schema-slot-target"]').exists()).toBe(true)
    expect(panel.find('[data-testid="schema-compare"]').exists()).toBe(true)

    await panel.find('[data-testid="schema-close"]').trigger('click')
    await flushPromises()
    expect(wrapper.find('[data-testid="schema-diff"]').exists()).toBe(false)

    wrapper.unmount()
  })

  it('浏览器旁路点「抓当前结构」会说出原因（不静默给一个空快照）', async () => {
    const wrapper = await mountWithResult()
    await wrapper.find('[data-testid="schema-open-panel"]').trigger('click')
    await flushPromises()

    await wrapper.find('[data-testid="schema-capture-base"]').trigger('click')
    await flushPromises()

    const error = wrapper.find('[data-testid="schema-error"]')
    expect(error.exists()).toBe(true)
    expect(error.text()).toContain('浏览器旁路没有真库')
    // 没有快照 ⇒ 仍显示「还没抓」（不伪造 0 张表的快照）
    expect(wrapper.find('[data-testid="schema-base-state"]').text()).toBe('还没抓')

    wrapper.unmount()
  })
})
