// @vitest-environment happy-dom
// 「AI 生成 → 存成已保存查询」的**挂载判据**（FR-AI-02 第二片 · 2026-10-18 · 第 16 轮）
//
// 为什么必须挂载真视图：这条路上有两个组件（生成弹层 → 视图的保存面板）与两条 IPC
// （`agent_generate_sql` / `saved_query_save`），断的地方永远是**接线**：
//   · 弹层只 `emit('save-as')`，视图如果没接那个事件，按钮点了什么也不会发生；
//   · 保存面板如果读 `sql.value`（编辑器）而不是「这次要存的那段」，就会把**编辑器里的旧内容**存进去 ——
//     界面一切正常、列表里多出一条错的，这是最糟的一种。
// 所以这里同时断言肯定面（IPC 收到生成的那段）与否定面（编辑器内容一字未动、也没被存）。
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { nextTick } from 'vue'
import { mount } from '@vue/test-utils'

const GENERATED = 'SELECT count(*) FROM public.orders;'
const EDITOR_CONTENT = 'select keep_me'

const control = vi.hoisted(() => ({
  saves: [] as Record<string, unknown>[],
  queries: [] as Record<string, unknown>[],
  generateCalls: 0,
}))

vi.mock('../ipc', async (importOriginal) => {
  const actual = await importOriginal<Record<string, unknown>>()
  return {
    ...actual,
    agentGeneratePreview: () =>
      Promise.resolve({
        gate: { state: 'ready', scope: 'remote', model: 'm', issues: [] },
        url: 'https://api.example.com/v1/chat/completions',
        human: '表：public.orders(id bigint)',
        tableCount: 1,
        dropped: 0,
        quota: { limit: 60, used: 0, remaining: 60, windowSecs: 3600, retryAfterSecs: 0 },
      }),
    agentGenerateSql: () => {
      control.generateCalls += 1
      return Promise.resolve({
        status: 'generated',
        sql: GENERATED,
        explanation: '用到了 orders。',
        tablesUsed: ['public.orders'],
        model: 'm',
        elapsedMs: 12,
        tableCount: 1,
        quota: { limit: 60, used: 1, remaining: 59, windowSecs: 3600, retryAfterSecs: 0 },
        limitations: ['生成结果不会自动执行。'],
        attempts: [{ attempt: 1, outcome: 'ok', status: 200, delayMs: 0, detail: '' }],
      })
    },
    savedQueriesList: () => Promise.resolve(control.queries.map((q) => ({ ...q }))),
    savedQuerySave: (request: Record<string, unknown>) => {
      control.saves.push(request)
      const record = { savedAt: '2026-10-18T10:00:00Z', schemaVersion: 1, ...request }
      control.queries = [...control.queries, record]
      return Promise.resolve({ saved: true, conflict: null, queries: control.queries.map((q) => ({ ...q })) })
    },
    savedQueryDelete: () => Promise.resolve(control.queries.map((q) => ({ ...q }))),
  }
})

import DatabaseView from './DatabaseView.vue'

async function settle() {
  for (let i = 0; i < 4; i += 1) {
    await nextTick()
    await new Promise((resolve) => setTimeout(resolve, 0))
  }
}

async function mountView() {
  const errors: string[] = []
  const errSpy = vi.spyOn(console, 'error').mockImplementation((...args: unknown[]) => {
    errors.push(args.map((a) => (a instanceof Error ? a.message : String(a))).join(' '))
  })
  const wrapper = mount(DatabaseView)
  await settle()
  return { wrapper, errors, restore: () => errSpy.mockRestore() }
}

beforeEach(() => {
  control.saves = []
  control.queries = []
  control.generateCalls = 0
})

describe('AI 生成结果 → 已保存查询（FR-AI-02 第二片）', () => {
  it('存的是生成的那段 SQL；编辑器里的内容一字未动、也没被存进去', async () => {
    const m = await mountView()
    const area = m.wrapper.find('.db__editor textarea').element as HTMLTextAreaElement
    area.value = EDITOR_CONTENT
    area.dispatchEvent(new Event('input', { bubbles: true }))
    await settle()

    // ① 打开生成弹层 → 先看要发什么 → 发送并生成
    await m.wrapper.find('[data-testid="ai-generate"]').trigger('click')
    await settle()
    const dialog = m.wrapper.find('[data-testid="agent-generate"]')
    expect(dialog.exists()).toBe(true)
    await m.wrapper.find('[data-testid="generate-question"]').setValue('订单总数')
    await m.wrapper.find('[data-testid="generate-preview"]').trigger('click')
    await settle()
    await m.wrapper.find('[data-testid="generate-send"]').trigger('click')
    await settle()
    expect(m.wrapper.find('[data-testid="generate-sql"]').text()).toContain('count(*)')

    // ② 点「存成已保存查询」⇒ 弹层收起、保存面板出现，且明写来源
    await m.wrapper.find('[data-testid="generate-save-as-query"]').trigger('click')
    await settle()
    expect(m.wrapper.find('[data-testid="agent-generate"]').exists()).toBe(false)
    const panel = m.wrapper.find('[data-testid="save-query-panel"]')
    expect(panel.exists()).toBe(true)
    expect(m.wrapper.find('[data-testid="save-query-source"]').text()).toContain('AI 生成')
    // 名字预填的是**生成的那段**的第一行，不是编辑器内容
    const nameInput = m.wrapper.find('[data-testid="save-query-name"]').element as HTMLInputElement
    expect(nameInput.value).toBe('SELECT count(*) FROM public.orders')

    // ③ 提交 ⇒ 落盘的是生成的那段，编辑器仍是自己的内容
    await m.wrapper.find('[data-testid="save-query-submit"]').trigger('click')
    await settle()
    expect(control.saves).toHaveLength(1)
    expect(control.saves[0]).toMatchObject({ sql: GENERATED, overwrite: false })
    expect(control.saves[0].sql).not.toBe(EDITOR_CONTENT)
    expect(area.value).toBe(EDITOR_CONTENT)
    // 列表计数刷新（工具栏那颗「已保存 (N)」）
    expect(m.wrapper.find('[data-testid="saved-query-toggle"]').text()).toContain('1')
    // 只发了一次生成：保存不该顺手再问模型一次
    expect(control.generateCalls).toBe(1)

    m.restore()
    expect(m.errors).toEqual([])
    m.wrapper.unmount()
  })

  it('否定面：工具栏那条保存入口仍存编辑器内容（来源标记不出现）', async () => {
    const m = await mountView()
    const area = m.wrapper.find('.db__editor textarea').element as HTMLTextAreaElement
    area.value = 'select 42'
    area.dispatchEvent(new Event('input', { bubbles: true }))
    await settle()

    await m.wrapper.find('[data-testid="save-query-open"]').trigger('click')
    await settle()
    expect(m.wrapper.find('[data-testid="save-query-source"]').exists()).toBe(false)
    await m.wrapper.find('[data-testid="save-query-submit"]').trigger('click')
    await settle()
    expect(control.saves[0]).toMatchObject({ sql: 'select 42' })

    m.restore()
    m.wrapper.unmount()
  })
})
