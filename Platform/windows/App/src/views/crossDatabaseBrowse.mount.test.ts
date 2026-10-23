// @vitest-environment happy-dom
// FR-META-10「跨数据库浏览」的**界面判据**（第 58 轮）。
//
// 这一条钉的是三件**只有挂载才判得出来**的事（`tsc --noEmit` 不校验 .vue，模板里引用了不存在
// 的名字一律绿）：
// ① **不预连 / 不预取**：连上服务器只取库清单，**非当前库一次取数都没有**（展开才取）；
// ② **一个库一份状态**：展开别的库、再切回来，两个库各自的 schema 都还在，且切回来**不重取**；
// ③ **失败只影响那一个库**：取不到的库**不展开**、原话摆出来，当前库照旧能用。
// 外加两条接线：展开库后点 schema，请求里**带着那个库名**（不带就等于又连回当前库）；
// 关掉某个库的会话后，它的行标记消失、缓存作废（再点会重新连一次）。
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'

/** 取数记录（mock 工厂会被提升，所以状态必须 `vi.hoisted`）。 */
const state = vi.hoisted(() => ({
  schemasCalls: [] as (string | undefined)[],
  relationsCalls: [] as { schema: string; database?: string }[],
  closedCalls: [] as string[],
  /** 外壳那边「已建独立会话的库」—— mock 里在展开成功后自己记一笔（真外壳也是这样） */
  sessions: [] as string[],
}))

const dbRow = (name: string) => ({
  name,
  owner: 'alex',
  encoding: 'UTF8',
  sizeBytes: 1024,
  connections: 1,
  allowConnections: true,
})

vi.mock('../ipc', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../ipc')>()
  return {
    ...actual,
    dbConnect: vi.fn(async () => ({
      info: {
        version: 'PostgreSQL 18.0',
        database: 'shop',
        user: 'alex',
        serverEncoding: 'UTF8',
        currentSchema: 'public',
      },
      startup: [],
    })),
    adminDatabases: vi.fn(async () => [dbRow('shop'), dbRow('warehouse'), dbRow('broken')]),
    dbSchemas: vi.fn(async (database?: string) => {
      state.schemasCalls.push(database)
      if (database === 'shop') {
        // 顺带放一个系统 schema：**当前库也照样走一遍过滤**（过滤规则只有一处）
        return { rows: ['public', 'pg_catalog'], truncated: false, limit: 10000 }
      }
      if (database === 'warehouse') {
        state.sessions = [...state.sessions, 'warehouse']
        return { rows: ['sales'], truncated: false, limit: 10000 }
      }
      // 失败的那一个：错误形状与外壳的 `DbFailure` 一致（原话 + 提示）
      throw { message: '连不上 broken：服务端拒绝连接', hint: '核对这个库的权限' }
    }),
    dbRelations: vi.fn(async (schema: string, database?: string) => {
      state.relationsCalls.push({ schema, database })
      return { rows: [], truncated: false, limit: 10000 }
    }),
    dbBrowseSessions: vi.fn(async () => [...state.sessions]),
    dbSessionClose: vi.fn(async (name: string) => {
      state.closedCalls.push(name)
      const had = state.sessions.includes(name)
      state.sessions = state.sessions.filter((entry) => entry !== name)
      return had
    }),
  }
})

import DatabaseView from './DatabaseView.vue'

/** 挂载 → 走一遍「连接」（真点弹层里的连接按钮，不是直接塞 info）。 */
async function mountConnected() {
  const wrapper = mount(DatabaseView)
  await flushPromises()
  await wrapper.setProps({ dialogRequest: { mode: 'current', seq: 1 } })
  await flushPromises()
  const form = wrapper.find('form.db__bar')
  expect(form.exists()).toBe(true)
  await form.trigger('submit')
  await flushPromises()
  return wrapper
}

async function click(wrapper: ReturnType<typeof mount>, testid: string) {
  const target = wrapper.find(`[data-testid="${testid}"]`)
  expect(target.exists(), `没找到 ${testid}`).toBe(true)
  await target.trigger('click')
  await flushPromises()
}

/** 树上**展开开关那几行**里有没有这一项（只看树，不看别处出现的同名文字）。 */
function treeHas(wrapper: ReturnType<typeof mount>, label: string): boolean {
  return wrapper
    .findAll('.db__schema-toggle')
    .some((node) => node.text().includes(label))
}

beforeEach(() => {
  state.schemasCalls.length = 0
  state.relationsCalls.length = 0
  state.closedCalls.length = 0
  state.sessions.length = 0
})

describe('FR-META-10 · 跨数据库浏览', () => {
  it('连上后只取当前库的 schema：服务器下的库都列出来，但非当前库一次都没取（不预连）', async () => {
    const wrapper = await mountConnected()

    // 库这一层真的画出来了（三个库）
    for (const name of ['shop', 'warehouse', 'broken']) {
      expect(wrapper.find(`[data-testid="db-node-${name}"]`).exists()).toBe(true)
    }
    // 当前库默认展开（schema 行在），系统 schema 被摘掉
    expect(wrapper.text()).toContain('public')
    expect(wrapper.text()).not.toContain('pg_catalog')

    // 关键否定面：**只问过当前这一个库**
    expect(state.schemasCalls).toEqual(['shop'])
    // 也**没有**为别的库建会话
    expect(wrapper.find('[data-testid="db-session-flag"]').exists()).toBe(false)

    wrapper.unmount()
  })

  it('展开别的库才取它的 schema；两个库各自的层都在，切回来不重取', async () => {
    const wrapper = await mountConnected()

    await click(wrapper, 'db-node-warehouse')
    // 取数点名了那个库
    expect(state.schemasCalls).toEqual(['shop', 'warehouse'])
    expect(treeHas(wrapper, 'sales')).toBe(true)
    // 同一时刻只展开一个库：当前库的 schema 行让位（不是两个库的层混在一起）
    expect(treeHas(wrapper, 'public')).toBe(false)

    await click(wrapper, 'db-node-shop')
    expect(treeHas(wrapper, 'public')).toBe(true)
    expect(treeHas(wrapper, 'sales')).toBe(false)
    // **切回来不重取**：仍然只是那两次
    expect(state.schemasCalls).toEqual(['shop', 'warehouse'])

    wrapper.unmount()
  })

  it('展开库后点它下面的 schema，请求里带着那个库名（不带就又连回当前库了）', async () => {
    const wrapper = await mountConnected()
    await click(wrapper, 'db-node-warehouse')

    const schemaRow = wrapper
      .findAll('.db__schema-toggle')
      .find((node) => node.text().includes('sales'))
    expect(schemaRow).toBeTruthy()
    await schemaRow!.trigger('click')
    await flushPromises()

    expect(state.relationsCalls).toEqual([{ schema: 'sales', database: 'warehouse' }])
    wrapper.unmount()
  })

  it('取不到的那个库：不展开、原话与提示都摆出来，当前库照旧能用', async () => {
    const wrapper = await mountConnected()

    await click(wrapper, 'db-node-broken')

    const alert = wrapper.find('.db__failure')
    expect(alert.exists()).toBe(true)
    expect(alert.text()).toContain('连不上 broken：服务端拒绝连接')
    expect(alert.text()).toContain('核对这个库的权限')
    // 没有「假装展开」：broken 那一行仍然收着，也没有把空树当成"这个库是空的"
    expect(wrapper.find('[data-testid="db-node-broken"]').attributes('aria-expanded')).toBe('false')
    // 需求原文点名「失败库标 ⚠️」：标记挂在那一个库的行上，原文进 title
    const flag = wrapper.find('[data-testid="db-failed-flag"]')
    expect(flag.exists()).toBe(true)
    expect(flag.attributes('title')).toContain('服务端拒绝连接')

    // 当前库不受影响：**它一直开着**（失败的库不会把它挤掉，也不会让树变成空的）
    expect(treeHas(wrapper, 'public')).toBe(true)
    wrapper.unmount()
  })

  it('关掉某个库的独立会话：标记消失、缓存作废（再点会重新取一次）', async () => {
    const wrapper = await mountConnected()
    await click(wrapper, 'db-node-warehouse')

    // 建过会话的库在行上标「独立会话」，并给一个「关掉」的入口
    expect(wrapper.find('[data-testid="db-session-flag"]').exists()).toBe(true)
    await click(wrapper, 'db-close-warehouse')

    expect(state.closedCalls).toEqual(['warehouse'])
    expect(wrapper.find('[data-testid="db-session-flag"]').exists()).toBe(false)
    // 会话没了 ⇒ 那个库已加载的层一起作废：窗口里只剩库清单
    expect(wrapper.text()).not.toContain('sales')

    await click(wrapper, 'db-node-warehouse')
    expect(state.schemasCalls).toEqual(['shop', 'warehouse', 'warehouse'])
    wrapper.unmount()
  })
})
