// @vitest-environment happy-dom
// 查询自动归档的**接线**判据（FR-EDIT-31 · 2026-10-18 · 第 27 轮）
//
// 为什么必须真挂载：`workspace/archive.ts` 的纯函数单测只能证明「格式与合并规则算得对」，
// 证明不了「执行完之后真的调了落盘」「面板里那条真是盘上那份」「点回填真的进了编辑器」——
// 断掉的地方永远是接线（本仓踩过：判定函数存在、调用点为零）。
// 这里把两个归档 IPC 包装换成内存桩（真落盘在 Rust 侧），其余包装保持原样。
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'

const control = vi.hoisted(() => ({
  files: new Map<string, string>(),
  writes: [] as { dateKey: string; content: string }[],
  /** 非空 ⇒ 下一次写盘就抛这个原因 */
  failWrite: '',
}))

vi.mock('../ipc', async (importOriginal) => {
  const actual = await importOriginal<Record<string, unknown>>()
  return {
    ...actual,
    dbQuery: vi.fn(async () => ({
      columns: ['total'],
      rows: [['1']],
      numRows: [[1]],
      returned: 1,
      truncated: false,
      affected: null,
    })),
    // 表单提交走的是**多段执行**那条路（`form.db__sql` → `runBatch`）：一次一段，成功。
    dbRunBatch: vi.fn(async (sql: string) => [
      {
        sql,
        ok: true,
        result: { columns: ['total'], rows: [['1']], numRows: [[1]], returned: 1, truncated: false, affected: null },
        failure: null,
        elapsedMs: 5,
      },
    ]),
    archiveRead: vi.fn(async (dateKey: string) => {
      const content = control.files.get(dateKey) ?? ''
      return { dateKey, path: `queries/${dateKey}.sql`, content, bytes: content.length }
    }),
    archiveWrite: vi.fn(async (dateKey: string, content: string) => {
      if (control.failWrite) throw { message: control.failWrite, hint: '' }
      control.writes.push({ dateKey, content })
      control.files.set(dateKey, content)
      return { dateKey, path: `queries/${dateKey}.sql`, content, bytes: content.length }
    }),
  }
})

import DatabaseView from './DatabaseView.vue'

async function mountView() {
  const errors: string[] = []
  const errSpy = vi.spyOn(console, 'error').mockImplementation((...args: unknown[]) => {
    errors.push(args.map((a) => (a instanceof Error ? a.message : String(a))).join(' '))
  })
  const wrapper = mount(DatabaseView)
  await flushPromises()
  return { wrapper, errors, restore: () => errSpy.mockRestore() }
}

/** 在编辑器里写一段 SQL 并点执行（与用户按的那一下同一条路）。 */
async function runSql(wrapper: Awaited<ReturnType<typeof mountView>>['wrapper'], sql: string) {
  await wrapper.find('textarea[aria-label="SQL"]').setValue(sql)
  await wrapper.find('form.db__sql').trigger('submit')
  await flushPromises()
  await flushPromises()
}

function textAt(wrapper: Awaited<ReturnType<typeof mountView>>['wrapper'], testid: string): string {
  const node = wrapper.find(`[data-testid="${testid}"]`)
  return node.exists() ? node.text() : '⟪缺件⟫'
}

describe('FR-EDIT-31 查询自动归档（接线）', () => {
  beforeEach(() => {
    control.files.clear()
    control.writes.length = 0
    control.failWrite = ''
  })

  it('执行成功后真的落盘一条：内容含这条 SQL，面板列出它并摊出文件路径与字节数', async () => {
    const mounted = await mountView()
    await runSql(mounted.wrapper, 'select 1 as total;')

    expect(control.writes).toHaveLength(1)
    expect(control.writes[0].content).toContain('select 1 as total;')
    // 日期键必须是 YYYY-MM-DD（拼进路径，格式错就写不出文件）
    expect(control.writes[0].dateKey).toMatch(/^\d{4}-\d{2}-\d{2}$/)

    await mounted.wrapper.find('[data-testid="archive-toggle"]').trigger('click')
    await flushPromises()

    expect(mounted.wrapper.findAll('[data-testid="archive-item"]')).toHaveLength(1)
    expect(textAt(mounted.wrapper, 'archive-facts')).toContain('1')
    expect(textAt(mounted.wrapper, 'archive-file')).toContain('queries/')
    expect(textAt(mounted.wrapper, 'archive-file')).toContain(String(control.writes[0].content.length))

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('同一条 SQL 再执行一次：只累计次数，文件里仍只有一段', async () => {
    const mounted = await mountView()
    await runSql(mounted.wrapper, 'select 1 as total;')
    await runSql(mounted.wrapper, 'select 1 as total;')

    expect(control.writes.length).toBeGreaterThanOrEqual(1)
    const last = control.files.get(control.writes[0].dateKey) ?? ''
    expect(last.split('select 1 as total;').length - 1).toBe(1)
    expect(last).toContain('"runs":2')

    await mounted.wrapper.find('[data-testid="archive-toggle"]').trigger('click')
    await flushPromises()
    expect(mounted.wrapper.findAll('[data-testid="archive-item"]')).toHaveLength(1)

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('还没跑过任何语句：面板如实说「还没有归档」，不编一条空条目', async () => {
    const mounted = await mountView()
    await mounted.wrapper.find('[data-testid="archive-toggle"]').trigger('click')
    await flushPromises()

    expect(textAt(mounted.wrapper, 'archive-empty')).toContain('还没有归档')
    expect(mounted.wrapper.findAll('[data-testid="archive-item"]')).toHaveLength(0)

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('点「回填」把归档里那条 SQL 放回编辑器（文件是事实源，不是内存里那份）', async () => {
    const mounted = await mountView()
    await runSql(mounted.wrapper, 'select 2 as total;')
    await mounted.wrapper.find('[data-testid="archive-toggle"]').trigger('click')
    await flushPromises()

    const editor = mounted.wrapper.find('textarea[aria-label="SQL"]')
    await editor.setValue('别的文字')
    await mounted.wrapper.find('[data-testid="archive-refill"]').trigger('click')
    await flushPromises()

    expect((mounted.wrapper.find('textarea[aria-label="SQL"]').element as HTMLTextAreaElement).value).toBe(
      'select 2 as total;',
    )

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('写盘失败：如实说「归档失败」，但查询结果照旧算成功（两件事不混成一件）', async () => {
    control.failWrite = '磁盘满了'
    const mounted = await mountView()
    await runSql(mounted.wrapper, 'select 3 as total;')

    const note = textAt(mounted.wrapper, 'archive-note')
    expect(note).toContain('归档失败')
    expect(note).toContain('磁盘满了')
    // 结果区还在（执行本身是成功的）
    expect(mounted.wrapper.text()).toContain('total')

    mounted.restore()
    mounted.wrapper.unmount()
  })
})
