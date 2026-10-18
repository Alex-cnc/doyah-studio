// @vitest-environment happy-dom
// 撤销 / 重做的**接线判据**（FR-EDIT-60 · 2026-10-18 · 第 24 轮）
//
// 为什么必须真挂载：栈的规则在 `workspace/undoStack.ts` 已有 15 条单测，
// 但它证明不了「Ctrl+Z 真的被接管 ⇒ 原生撤销不会来抢」「菜单里真有两项且空栈时是灰的」
// 「打字走的是 @input 那条路、位置量得对」。断了的地方永远是接线。
//
// 否定面与正例同权：空栈时的回执、撤销后 redo 分支被截断、以及「Ctrl+Z 必须 preventDefault」。
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { nextTick } from 'vue'
import { mount } from '@vue/test-utils'

// 格式化走外壳，浏览器里没有 —— 换成可控桩（与 `DatabaseView.formatSql.test.ts` 同一套口径）。
const formatControl = vi.hoisted(() => ({ next: null as null | ((sql: string) => Record<string, unknown>) }))

vi.mock('../ipc', async (importOriginal) => {
  const actual = await importOriginal<Record<string, unknown>>()
  return {
    ...actual,
    formatSql: (sql: string) => {
      const outcome = formatControl.next
        ? formatControl.next(sql)
        : { content: sql, changed: false, note: '没有需要改的地方。', engine: 'builtin', problem: null }
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

/** 走真实 input 事件往编辑器里写字（等同用户打字 / 粘贴）。 */
async function typeInto(mounted: Mounted, text: string, caret = text.length): Promise<HTMLTextAreaElement> {
  const area = editorOf(mounted)
  area.value = text
  area.setSelectionRange(caret, caret)
  area.dispatchEvent(new Event('input', { bubbles: true }))
  await settle()
  area.setSelectionRange(caret, caret)
  return area
}

/** 真派发一次按键；返回 false = 被接管（preventDefault），true = 放行给浏览器。 */
function press(area: HTMLTextAreaElement, init: KeyboardEventInit): boolean {
  return area.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ...init }))
}

async function settle() {
  await nextTick()
  await nextTick()
  await new Promise((resolve) => setTimeout(resolve, 0))
  await nextTick()
}

async function openEditMenu(mounted: Mounted): Promise<void> {
  // 幂等：菜单可能已经开着（点了撤销 / 重做会自己关，但打字不会）—— 无脑点 toggle 会把它关掉
  if (mounted.wrapper.find('[data-testid="edit-menu"]').exists()) return
  await mounted.wrapper.find('[data-testid="edit-menu-toggle"]').trigger('click')
  await settle()
}

describe('撤销 / 重做（FR-EDIT-60）', () => {
  beforeEach(() => {
    formatControl.next = null
  })

  it('Ctrl+/ 注释是一步：Ctrl+Z 撤回到注释前，Ctrl+Shift+Z 重做', async () => {
    const mounted = await mountView()
    const area = await typeInto(mounted, 'select 1', 0)

    expect(press(area, { key: '/', ctrlKey: true })).toBe(false)
    await settle()
    const commented = editorOf(mounted).value
    expect(commented).toContain('select 1')
    expect(commented.startsWith('--')).toBe(true)

    // 撤销：preventDefault（返回 false）—— 原生撤销绝不能同时来抢
    expect(press(editorOf(mounted), { key: 'z', ctrlKey: true })).toBe(false)
    await settle()
    expect(editorOf(mounted).value).toBe('select 1')

    expect(press(editorOf(mounted), { key: 'Z', ctrlKey: true, shiftKey: true })).toBe(false)
    await settle()
    expect(editorOf(mounted).value).toBe(commented)

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('一段连续输入算一步：连打两字符后一次撤销回到两个字之前', async () => {
    const mounted = await mountView()
    await typeInto(mounted, '', 0)
    await typeInto(mounted, 's', 1)
    await typeInto(mounted, 'se', 2)

    expect(editorOf(mounted).value).toBe('se')
    press(editorOf(mounted), { key: 'z', ctrlKey: true })
    await settle()
    // 合并成一步 ⇒ 两个字符一起退掉；逐字符记的话这里会剩 'se'（只有一处坏掉才看得见）
    expect(editorOf(mounted).value).toBe('')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('格式化之后按 Ctrl+Z 回到格式化前的原文（原生撤销在这里是断的）', async () => {
    const mounted = await mountView()
    await typeInto(mounted, 'select * from t', 15)
    formatControl.next = (sql) => ({
      content: sql.replace('select', 'SELECT'),
      changed: true,
      note: '已格式化。',
      engine: 'builtin',
      problem: null,
    })

    expect(press(editorOf(mounted), { key: 'f', ctrlKey: true, shiftKey: true })).toBe(false)
    await settle()
    expect(editorOf(mounted).value).toBe('SELECT * from t')

    press(editorOf(mounted), { key: 'z', ctrlKey: true })
    await settle()
    expect(editorOf(mounted).value).toBe('select * from t')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('「编辑」菜单里有撤销 / 重做：空栈时是灰的，编辑后撤销可用、撤销完重做可用', async () => {
    const mounted = await mountView()
    await openEditMenu(mounted)
    const undo = mounted.wrapper.find('[data-testid="edit-menu-undo"]')
    const redo = mounted.wrapper.find('[data-testid="edit-menu-redo"]')
    expect(undo.exists()).toBe(true)
    expect(redo.exists()).toBe(true)
    expect(undo.attributes('disabled')).toBeDefined()
    expect(redo.attributes('disabled')).toBeDefined()

    press(editorOf(mounted), { key: 'Escape' })
    await typeInto(mounted, 'select 1', 8)
    await openEditMenu(mounted)
    expect(mounted.wrapper.find('[data-testid="edit-menu-undo"]').attributes('disabled')).toBeUndefined()

    // 点菜单项就能撤（不是只有键盘能用）
    await mounted.wrapper.find('[data-testid="edit-menu-undo"]').trigger('click')
    await settle()
    expect(editorOf(mounted).value).not.toBe('select 1')

    await openEditMenu(mounted)
    expect(mounted.wrapper.find('[data-testid="edit-menu-redo"]').attributes('disabled')).toBeUndefined()

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('空栈时按 Ctrl+Z 不沉默：给一句「已经撤到最早一步了」', async () => {
    const mounted = await mountView()
    const initial = editorOf(mounted).value
    await typeInto(mounted, '', 0)

    press(editorOf(mounted), { key: 'z', ctrlKey: true })
    await settle()
    expect(editorOf(mounted).value).toBe(initial)
    press(editorOf(mounted), { key: 'z', ctrlKey: true })
    await settle()
    const note = mounted.wrapper.find('[data-testid="undo-note"]')
    expect(note.exists()).toBe(true)
    expect(note.text()).toContain('已经撤到最早一步了')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('撤销之后再打字 ⇒ 重做分支被丢掉（重做按钮回到灰）', async () => {
    const mounted = await mountView()
    const initial = editorOf(mounted).value
    await typeInto(mounted, 'abc', 3)
    press(editorOf(mounted), { key: 'z', ctrlKey: true })
    await settle()
    expect(editorOf(mounted).value).toBe(initial)

    await typeInto(mounted, 'x', 1)
    await openEditMenu(mounted)
    expect(mounted.wrapper.find('[data-testid="edit-menu-redo"]').attributes('disabled')).toBeDefined()

    mounted.restore()
    mounted.wrapper.unmount()
  })
})
