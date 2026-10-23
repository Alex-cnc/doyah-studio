// @vitest-environment happy-dom
// 整表 / 整库导出（`FR-STD-DB-IO-002`）的**挂载判据**。
//
// 为什么必须挂一次：`.vue` 不在 `tsc --noEmit` 的程序里（模板引用了没 import 的名字照样编译得过，
// 点开才 ReferenceError —— 本仓踩过）。这里钉四件事：
//   ① 面板里真有「导出整表 / 导出整库」两个入口，且**点下去真的调了命令**（名字 + 参数形状对齐）；
//   ② 完成回报要带**行数 · 字节 · 路径**（判据④），不是只说「成功」；
//   ③ 整库导出**逐表一行**，失败的表带原因照实画（「导出成功」不许盖住某张表挂了）；
//   ④ 没填路径就点 ⇒ 给出可读原因且**不发请求**（不许把空路径递到外壳里，让用户以为在跑）。
import { describe, expect, it, vi, beforeEach } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import type { CopyExportSummary, DbFailure, SchemaExportSummary } from '../ipc'
import DatabaseView from './DatabaseView.vue'

const state: {
  tableArgs: unknown[] | null
  schemaArgs: unknown[] | null
  tableReport: CopyExportSummary
  schemaReport: SchemaExportSummary
  tableFailure: DbFailure | null
  schemaFailure: DbFailure | null
} = {
  tableArgs: null,
  schemaArgs: null,
  tableReport: { statement: 'COPY "public"."orders" TO STDOUT WITH (FORMAT csv, HEADER true)', path: 'D:/tmp/orders.csv', rows: 3, bytes: 42 },
  schemaReport: {
    schema: 'public',
    dir: 'D:/tmp/export',
    tables: [
      { table: 'orders', fileName: 'orders.csv', path: 'D:/tmp/export/orders.csv', rows: 3, bytes: 42, failure: null },
      { table: 'users', fileName: 'users.csv', path: 'D:/tmp/export/users.csv', rows: 0, bytes: 0, failure: { message: 'permission denied for table users', hint: '换一个有权限的角色再导出' } },
    ],
    totalRows: 3,
    totalBytes: 42,
    failed: 1,
    skipped: 2,
  },
  tableFailure: null,
  schemaFailure: null,
}

vi.mock('../ipc', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../ipc')>()
  return {
    ...actual,
    exportTableCopy: vi.fn(async (table: string, path: string, schema?: string, header?: boolean) => {
      state.tableArgs = [table, path, schema, header]
      if (state.tableFailure) throw state.tableFailure
      return state.tableReport
    }),
    exportSchemaCopy: vi.fn(async (schema: string, dir: string, header?: boolean) => {
      state.schemaArgs = [schema, dir, header]
      if (state.schemaFailure) throw state.schemaFailure
      return state.schemaReport
    }),
  }
})

/** 打开「整表 / 整库导出」面板（入口在一直可见的 SQL 工具条上 ⇒ 不需要先跑查询）。 */
async function mountWithIoPanel() {
  const wrapper = mount(DatabaseView)
  await flushPromises()
  const toggle = wrapper.find('[data-testid="copy-export-open"]')
  expect(toggle.exists(), '页面上找不到「整表 / 整库导出」入口').toBe(true)
  await toggle!.trigger('click')
  await flushPromises()
  return wrapper
}

describe('整表 / 整库导出（FR-STD-DB-IO-002）', () => {
  beforeEach(() => {
    state.tableArgs = null
    state.schemaArgs = null
    state.tableFailure = null
    state.schemaFailure = null
  })

  it('整表导出：点了就调命令，完成回报带行数 / 字节 / 路径', async () => {
    const wrapper = await mountWithIoPanel()
    const inputs = wrapper.findAll('input')
    // 按 aria-label 定位（= 界面给读屏与自动化用的同一份语义）
    await wrapper.find('input[aria-label="整表导出的 schema"]').setValue('public')
    await wrapper.find('input[aria-label="整表导出的表名"]').setValue('orders')
    await wrapper.find('input[aria-label="整表导出目标文件"]').setValue('D:/tmp/orders.csv')
    expect(inputs.length).toBeGreaterThan(0)

    await wrapper.find('[data-testid="export-table-copy"]').trigger('click')
    await flushPromises()

    expect(state.tableArgs).toEqual(['orders', 'D:/tmp/orders.csv', 'public', true])
    const note = wrapper.find('[data-testid="copy-note"]')
    expect(note.exists()).toBe(true)
    expect(note.text()).toContain('3 行')
    expect(note.text()).toContain('42 字节')
    expect(note.text()).toContain('D:/tmp/orders.csv')
    wrapper.unmount()
  })

  it('整库导出：逐表一行，失败的表带服务端原话与提示，没导的关系数也说出来', async () => {
    const wrapper = await mountWithIoPanel()
    await wrapper.find('input[aria-label="整表导出的 schema"]').setValue('public')
    await wrapper.find('input[aria-label="整库导出目标目录"]').setValue('D:/tmp/export')

    await wrapper.find('[data-testid="export-schema-copy"]').trigger('click')
    await flushPromises()

    expect(state.schemaArgs).toEqual(['public', 'D:/tmp/export', true])
    const rows = wrapper.findAll('[data-testid="copy-schema-rows"] li')
    expect(rows).toHaveLength(2)
    expect(rows[0].text()).toContain('orders.csv')
    expect(rows[0].text()).toContain('3 行')
    // 失败那张：原因与提示都要在（不能只画一个 ⚠️ 什么都不说）
    expect(rows[1].text()).toContain('permission denied for table users')
    expect(rows[1].text()).toContain('换一个有权限的角色再导出')
    const note = wrapper.find('[data-testid="copy-note"]')
    expect(note.text()).toContain('1 / 2')
    const skipped = wrapper.find('[data-testid="copy-skipped"]')
    expect(skipped.text()).toContain('2 个')
    wrapper.unmount()
  })

  it('没填目标文件就点：给可读原因，且**不发请求**', async () => {
    const wrapper = await mountWithIoPanel()
    await wrapper.find('input[aria-label="整表导出的表名"]').setValue('orders')
    await wrapper.find('[data-testid="export-table-copy"]').trigger('click')
    await flushPromises()

    expect(state.tableArgs).toBeNull()
    expect(wrapper.find('[data-testid="copy-note"]').text()).toContain('目标文件路径')
    wrapper.unmount()
  })

  it('外壳报错时摆在失败条里（不是静默什么都不发生）', async () => {
    state.tableFailure = { message: 'permission denied for table orders', hint: '换一个有权限的角色再导出' }
    const wrapper = await mountWithIoPanel()
    await wrapper.find('input[aria-label="整表导出的表名"]').setValue('orders')
    await wrapper.find('input[aria-label="整表导出目标文件"]').setValue('D:/tmp/orders.csv')
    await wrapper.find('[data-testid="export-table-copy"]').trigger('click')
    await flushPromises()

    const html = wrapper.html()
    expect(html).toContain('permission denied for table orders')
    expect(html).toContain('换一个有权限的角色再导出')
    wrapper.unmount()
  })
})
