// @vitest-environment happy-dom
// 保存查询接线判据（FR-EDIT-14 · 2026-10-18 · 第 7 轮）
//
// 为什么必须真挂载：领域层的「同名覆盖」判定与落盘层都能单测，但它们**证明不了**
// 「工具栏上真有这颗按钮、点了真调 IPC、列表真能回填到编辑器」—— 断了的地方永远是接线。
// 这里只把三个 IPC 包装换成可控桩（真落盘在 Rust，浏览器里没有它），其余包装保持原样。
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { nextTick } from 'vue'
import { mount } from '@vue/test-utils'

type Row = {
  id: string
  name: string
  sql: string
  connectionName?: string | null
  database?: string | null
  savedAt: string
  schemaVersion: number
}

const control = vi.hoisted(() => ({
  queries: [] as Row[],
  saves: [] as Record<string, unknown>[],
  deletes: [] as string[],
  /** 非空 ⇒ 下一次不带 overwrite 的保存回「冲突」 */
  conflictOn: null as Row | null,
}))

vi.mock('../ipc', async (importOriginal) => {
  const actual = await importOriginal<Record<string, unknown>>()
  return {
    ...actual,
    savedQueriesList: () => Promise.resolve(control.queries.map((q) => ({ ...q }))),
    savedQuerySave: (request: Record<string, unknown>) => {
      control.saves.push(request)
      if (control.conflictOn && !request.overwrite) {
        return Promise.resolve({
          saved: false,
          conflict: { ...control.conflictOn },
          queries: control.queries.map((q) => ({ ...q })),
        })
      }
      const record: Row = {
        id: String(request.id),
        name: String(request.name),
        sql: String(request.sql),
        connectionName: (request.connectionName as string | null) ?? null,
        database: (request.database as string | null) ?? null,
        savedAt: '2026-10-18T10:00:00Z',
        schemaVersion: 1,
      }
      control.queries = [...control.queries.filter((q) => q.id !== record.id), record]
      return Promise.resolve({ saved: true, conflict: null, queries: control.queries.map((q) => ({ ...q })) })
    },
    savedQueryDelete: (id: string) => {
      control.deletes.push(id)
      control.queries = control.queries.filter((q) => q.id !== id)
      return Promise.resolve(control.queries.map((q) => ({ ...q })))
    },
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

type Mounted = Awaited<ReturnType<typeof mountView>>

function editorOf({ wrapper }: Mounted): HTMLTextAreaElement {
  return wrapper.find('.db__editor textarea').element as HTMLTextAreaElement
}

async function type(mounted: Mounted, text: string) {
  const area = editorOf(mounted)
  area.value = text
  area.dispatchEvent(new Event('input', { bubbles: true }))
  await settle()
}

beforeEach(() => {
  control.queries = []
  control.saves = []
  control.deletes = []
  control.conflictOn = null
})

describe('保存查询（FR-EDIT-14）', () => {
  it('工具条上「保存查询」在「执行」之前，且编辑器空时不可点', async () => {
    const m = await mountView()

    const save = m.wrapper.find('[data-testid="save-query-open"]')
    const run = m.wrapper.find('.db__sql-actions button[type="submit"]')
    expect(save.exists()).toBe(true)
    expect(run.exists()).toBe(true)
    // DOM 顺序：保存按钮出现在执行按钮**之前**（需求原文点名的位置）
    expect(save.element.compareDocumentPosition(run.element) & 4).toBeTruthy()

    // 否定面：把编辑器清空 ⇒ 保存按钮不可点（没东西可存）
    await type(m, '   ')
    expect((m.wrapper.find('[data-testid="save-query-open"]').element as HTMLButtonElement).disabled).toBe(true)

    m.restore()
    expect(m.errors).toEqual([])
    m.wrapper.unmount()
  })

  it('点保存 → 面板出现且名字预填 SQL 首行；提交后 IPC 收到 sql + 名字 + 来源库', async () => {
    const m = await mountView()
    await type(m, 'select 42 as answer')

    await m.wrapper.find('[data-testid="save-query-open"]').trigger('click')
    await settle()
    const panel = m.wrapper.find('[data-testid="save-query-panel"]')
    expect(panel.exists()).toBe(true)
    const nameInput = m.wrapper.find('[data-testid="save-query-name"]').element as HTMLInputElement
    expect(nameInput.value).toBe('select 42 as answer')

    nameInput.value = '月度对账'
    nameInput.dispatchEvent(new Event('input', { bubbles: true }))
    await settle()
    await m.wrapper.find('[data-testid="save-query-submit"]').trigger('click')
    await settle()

    expect(control.saves).toHaveLength(1)
    expect(control.saves[0]).toMatchObject({ name: '月度对账', sql: 'select 42 as answer', overwrite: false })
    // 面板收起来、工具栏计数变 1、给一句结果话
    expect(m.wrapper.find('[data-testid="save-query-panel"]').exists()).toBe(false)
    expect(m.wrapper.find('[data-testid="saved-query-toggle"]').text()).toContain('1')
    expect(m.wrapper.find('[data-testid="saved-query-note"]').text()).toContain('月度对账')

    m.restore()
    m.wrapper.unmount()
  })

  it('重名：先摆出既有那条并换成「覆盖保存」，点了才带 overwrite 再发一次', async () => {
    control.conflictOn = {
      id: 'old-1',
      name: '月度对账',
      sql: 'select old',
      savedAt: '2026-10-18T09:00:00Z',
      schemaVersion: 1,
    }
    const m = await mountView()
    await type(m, 'select new')

    await m.wrapper.find('[data-testid="save-query-open"]').trigger('click')
    await settle()
    const nameInput = m.wrapper.find('[data-testid="save-query-name"]').element as HTMLInputElement
    nameInput.value = '月度对账'
    nameInput.dispatchEvent(new Event('input', { bubbles: true }))
    await settle()

    await m.wrapper.find('[data-testid="save-query-submit"]').trigger('click')
    await settle()

    // 第一次：没有覆盖授权 ⇒ 服务端没写盘，界面把既有那条摆出来
    expect(control.saves[0].overwrite).toBe(false)
    const warn = m.wrapper.find('[data-testid="save-query-conflict"]')
    expect(warn.exists()).toBe(true)
    expect(warn.text()).toContain('月度对账')
    expect(m.wrapper.find('[data-testid="save-query-submit"]').text()).toContain('覆盖保存')

    await m.wrapper.find('[data-testid="save-query-submit"]').trigger('click')
    await settle()

    expect(control.saves).toHaveLength(2)
    expect(control.saves[1].overwrite).toBe(true)
    expect(m.wrapper.find('[data-testid="save-query-panel"]').exists()).toBe(false)

    m.restore()
    m.wrapper.unmount()
  })

  it('已保存清单：回填当前页签 = 编辑器换成那条 SQL', async () => {
    control.queries = [
      { id: 'q1', name: '慢查询', sql: 'select * from pg_stat_activity', savedAt: '2026-10-18T09:30:00Z', schemaVersion: 1 },
    ]
    const m = await mountView()

    await m.wrapper.find('[data-testid="saved-query-toggle"]').trigger('click')
    await settle()
    const list = m.wrapper.find('[data-testid="saved-query-list"]')
    expect(list.exists()).toBe(true)
    expect(list.text()).toContain('慢查询')
    expect(list.text()).toContain('2026-10-18 09:30')

    const refill = m.wrapper.findAll('.db__saved-actions button')[0]
    expect(refill.text()).toContain('回填')
    await refill.trigger('click')
    await settle()

    expect(editorOf(m).value).toBe('select * from pg_stat_activity')
    expect(m.wrapper.find('[data-testid="saved-query-list"]').exists()).toBe(false)

    m.restore()
    m.wrapper.unmount()
  })

  it('已保存清单：新页签打开 = 多一张页签且标题是查询名，当前页签内容不动', async () => {
    control.queries = [
      { id: 'q2', name: '对账', sql: 'select 1', savedAt: '2026-10-18T09:30:00Z', schemaVersion: 1 },
    ]
    const m = await mountView()
    await type(m, 'select keep_me')
    const before = m.wrapper.findAll('.db__qtab').length

    await m.wrapper.find('[data-testid="saved-query-toggle"]').trigger('click')
    await settle()
    const newTabButton = m.wrapper.findAll('.db__saved-actions button')[1]
    expect(newTabButton.text()).toContain('新页签')
    await newTabButton.trigger('click')
    await settle()

    const tabs = m.wrapper.findAll('.db__qtab')
    expect(tabs.length).toBe(before + 1)
    expect(tabs[tabs.length - 1].text()).toContain('对账')
    expect(editorOf(m).value).toBe('select 1')

    // 回到原来那张页签：内容一字未动（新页签不是「覆盖当前页签」）
    await tabs[0].find('.db__qtab-name').trigger('click')
    await settle()
    expect(editorOf(m).value).toBe('select keep_me')

    m.restore()
    m.wrapper.unmount()
  })

  it('否定面：名字留空 ⇒ 不发 IPC，并给一句可读的话', async () => {
    const m = await mountView()
    await type(m, 'select 1')

    await m.wrapper.find('[data-testid="save-query-open"]').trigger('click')
    await settle()
    const nameInput = m.wrapper.find('[data-testid="save-query-name"]').element as HTMLInputElement
    nameInput.value = '   '
    nameInput.dispatchEvent(new Event('input', { bubbles: true }))
    await settle()

    await m.wrapper.find('[data-testid="save-query-submit"]').trigger('click')
    await settle()

    expect(control.saves).toHaveLength(0)
    const error = m.wrapper.find('[data-testid="save-query-error"]')
    expect(error.exists()).toBe(true)
    expect(error.text()).toContain('名字')

    m.restore()
    m.wrapper.unmount()
  })
})
