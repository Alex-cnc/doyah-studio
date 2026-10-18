// @vitest-environment happy-dom
// 格式化 SQL 的**接线判据**（FR-EDIT-22 · 2026-10-18 · 第 10 轮）
//
// 为什么必须真挂载：格式化规则在外壳（`format_tool::format_content`：外部工具优先 → 内置兜底 → 如实拒绝）
// 且已有单测，但它证明不了「菜单里真有这一项」「点了真把当前文本发出去」「结果真落回 textarea」
// 「拒绝时文本一个字都不动、回执还看得出来是拒绝」。断了的地方永远是接线。
//
// 这里把 `formatSql` 换成可控桩（真格式化在 Rust 外壳，浏览器里没有它），其余包装保持原样。
// 否定面与正例同权：没改动 / 被拒绝 / 空编辑器三种情况都必须**说得出话**且不改文本。
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { nextTick } from 'vue'
import { mount } from '@vue/test-utils'

type Outcome = {
  content: string
  changed: boolean
  note: string
  engine: string
  problem: string | null
}

const control = vi.hoisted(() => ({
  calls: [] as { sql: string; preferBuiltin: boolean }[],
  /** 桩的下一次返回（缺省 = 原样、没改动） */
  next: null as null | ((sql: string) => Outcome),
  failWith: null as Error | null,
}))

vi.mock('../ipc', async (importOriginal) => {
  const actual = await importOriginal<Record<string, unknown>>()
  return {
    ...actual,
    formatSql: (sql: string, preferBuiltin = false) => {
      control.calls.push({ sql, preferBuiltin })
      if (control.failWith) return Promise.reject(control.failWith)
      const outcome = control.next
        ? control.next(sql)
        : { content: sql, changed: false, note: '检查过了，没有需要改的地方。', engine: 'builtin', problem: null }
      return Promise.resolve(outcome)
    },
  }
})

import DatabaseView from './DatabaseView.vue'

async function mountView() {
  const errors: string[] = []
  const errSpy = vi.spyOn(console, 'error').mockImplementation((...args: unknown[]) => {
    errors.push(args.map((a) => (a instanceof Error ? a.message : String(a))).join(' '))
  })
  const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {})
  // attachTo：选区 / activeElement 这类判据要求节点真的在文档里
  const host = document.createElement('div')
  document.body.appendChild(host)
  const wrapper = mount(DatabaseView, { attachTo: host })
  await settle()
  return {
    wrapper,
    errors,
    restore: () => {
      errSpy.mockRestore()
      warnSpy.mockRestore()
      host.remove()
    },
  }
}

type Mounted = Awaited<ReturnType<typeof mountView>>

function editorOf({ wrapper }: Mounted): HTMLTextAreaElement {
  return wrapper.find('.db__editor textarea').element as HTMLTextAreaElement
}

async function settle() {
  await nextTick()
  await nextTick()
  await new Promise((resolve) => setTimeout(resolve, 0))
  await nextTick()
}

/** 往编辑器里放一段文字并摆好选区（走真实 input 事件，等同用户粘贴 / 框选）。 */
async function setText(mounted: Mounted, text: string, start = 0, end = 0) {
  const area = editorOf(mounted)
  area.value = text
  area.setSelectionRange(start, end)
  area.dispatchEvent(new Event('input', { bubbles: true }))
  await settle()
  area.setSelectionRange(start, end)
  return area
}

/** 开编辑菜单并点其中一项。 */
async function clickMenuItem(mounted: Mounted, testId: string) {
  await mounted.wrapper.find('[data-testid="edit-menu-toggle"]').trigger('click')
  await settle()
  const item = mounted.wrapper.find(`[data-testid="${testId}"]`)
  expect(item.exists(), `菜单里应当有 ${testId}`).toBe(true)
  await item.trigger('click')
  await settle()
}

function noteText(mounted: Mounted): string {
  const note = mounted.wrapper.find('[data-testid="format-note"]')
  return note.exists() ? note.text() : ''
}

function press(mounted: Mounted, init: KeyboardEventInit) {
  const area = editorOf(mounted)
  return area.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ...init }))
}

beforeEach(() => {
  control.calls = []
  control.next = null
  control.failWith = null
})

describe('格式化 SQL（FR-EDIT-22）', () => {
  it('编辑菜单第五项真把当前文本发出去，并把结果落回编辑器', async () => {
    const mounted = await mountView()
    try {
      control.next = (sql) => ({
        content: sql.replace('select', 'SELECT').replace('from', 'FROM'),
        changed: true,
        note: '**没找到可用的外部格式化器**，已用内置兜底：只把 SQL 关键字转成大写。',
        engine: 'builtin',
        problem: null,
      })
      const before = editorOf(mounted).value
      await clickMenuItem(mounted, 'edit-menu-format')

      expect(control.calls).toHaveLength(1)
      expect(control.calls[0].sql).toBe(before)
      expect(editorOf(mounted).value).toBe(before.replace('select', 'SELECT').replace('from', 'FROM'))
      // 回执必须说清「用了什么」—— 安静不是结论
      expect(noteText(mounted)).toContain('内置')
    } finally {
      mounted.restore()
    }
  })

  it('有选区只格式化选中段，其余一个字都不动', async () => {
    const mounted = await mountView()
    try {
      const text = 'select a from t;\nselect b from t;\n'
      const second = text.indexOf('select b')
      await setText(mounted, text, second, text.length - 1)
      control.next = (sql) => ({ content: sql.toUpperCase(), changed: true, note: '已用内置兜底。', engine: 'builtin', problem: null })

      await clickMenuItem(mounted, 'edit-menu-format')

      // 发出去的只是选中那段
      expect(control.calls[0].sql).toBe('select b from t;')
      // 落回去时只换选中那段，前半段原样
      expect(editorOf(mounted).value).toBe('select a from t;\nSELECT B FROM T;\n')
    } finally {
      mounted.restore()
    }
  })

  it('没有需要改的地方：文本一个字都不动，回执照实说', async () => {
    const mounted = await mountView()
    try {
      const before = editorOf(mounted).value
      control.next = (sql) => ({ content: sql, changed: false, note: '检查过了，**没有需要改的地方**。', engine: 'builtin', problem: null })
      await clickMenuItem(mounted, 'edit-menu-format')

      expect(control.calls).toHaveLength(1)
      expect(editorOf(mounted).value).toBe(before)
      expect(noteText(mounted)).toContain('没有需要改的地方')
      // 这不是「没跑成」⇒ 不许用告警色
      expect(mounted.wrapper.find('[data-testid="format-note"]').classes()).not.toContain('db__format-note--bad')
    } finally {
      mounted.restore()
    }
  })

  it('被拒绝时：文本原样，回执用告警色并说清为什么（不假装格式化过）', async () => {
    const mounted = await mountView()
    try {
      const before = editorOf(mounted).value
      control.next = (sql) => ({
        content: sql,
        changed: false,
        note: 'sql 没有可用的格式化器（外部工具没装、这条路也没有内置兜底），**没有改动**。',
        engine: 'refused',
        problem: 'noFormatter',
      })
      await clickMenuItem(mounted, 'edit-menu-format')

      expect(editorOf(mounted).value).toBe(before)
      const note = mounted.wrapper.find('[data-testid="format-note"]')
      expect(note.classes()).toContain('db__format-note--bad')
      expect(note.text()).toContain('没有改动')
    } finally {
      mounted.restore()
    }
  })

  it('Ctrl+Shift+F 走格式化，Ctrl+F 仍然只开查找条（同一个 key 的两档不许互相吃）', async () => {
    const mounted = await mountView()
    try {
      control.next = (sql) => ({ content: sql.toUpperCase(), changed: true, note: '已用内置兜底。', engine: 'builtin', problem: null })
      const handled = press(mounted, { key: 'F', ctrlKey: true, shiftKey: true })
      await settle()
      expect(handled).toBe(false) // preventDefault 过了 ⇒ 浏览器不另弹查找
      expect(control.calls).toHaveLength(1)
      expect(mounted.wrapper.find('[data-testid="find-bar"]').exists()).toBe(false)

      press(mounted, { key: 'f', ctrlKey: true })
      await settle()
      expect(mounted.wrapper.find('[data-testid="find-bar"]').exists()).toBe(true)
      // 查找那一档**不许**顺手再格式化一次
      expect(control.calls).toHaveLength(1)
    } finally {
      mounted.restore()
    }
  })

  it('编辑器空着时菜单项置灰，强行触发也会说清「没有可格式化的东西」', async () => {
    const mounted = await mountView()
    try {
      await setText(mounted, '', 0, 0)
      await mounted.wrapper.find('[data-testid="edit-menu-toggle"]').trigger('click')
      await settle()
      const item = mounted.wrapper.find('[data-testid="edit-menu-format"]')
      expect(item.attributes('disabled')).toBeDefined()

      // 菜单项置灰点不动 ⇒ 从快捷键这一路进来，同样不许静默
      press(mounted, { key: 'F', ctrlKey: true, shiftKey: true })
      await settle()
      expect(control.calls).toHaveLength(0)
      expect(noteText(mounted)).toContain('没有 SQL 可格式化')
    } finally {
      mounted.restore()
    }
  })

  it('格式化链路自己出错时，回执说清原因（不吞异常、不动文本）', async () => {
    const mounted = await mountView()
    try {
      const before = editorOf(mounted).value
      control.failWith = new Error('外壳没起')
      await clickMenuItem(mounted, 'edit-menu-format')
      expect(editorOf(mounted).value).toBe(before)
      expect(noteText(mounted)).toContain('外壳没起')
      expect(mounted.wrapper.find('[data-testid="format-note"]').classes()).toContain('db__format-note--bad')
    } finally {
      mounted.restore()
    }
  })
})
