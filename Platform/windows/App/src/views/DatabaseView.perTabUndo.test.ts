// @vitest-environment happy-dom
// **每页签一份撤销栈**的接线判据（第 26 轮 · FR-EDIT-60 的页签条款）
//
// 为什么必须真挂载：规则（存 / 取 / 丢 / 对齐）在 `workspace/undoStack.test.ts` 已有单测，
// 但它证明不了「切页签真的把栈换了过去」「Ctrl+Z 撤的是**这张页签自己的**上一步」
// 「菜单可用态与页签徽标跟着当前页签走」。断了的地方永远是接线。
//
// 否定面与正例同权：新页签**不许**继承上一张的历史；在空页签按撤销要给「没得撤」而不是
// 「历史已重置」；A 的历史**绝不**能把文本撤到 B 里。
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { nextTick } from 'vue'
import { mount } from '@vue/test-utils'

// 格式化走外壳，浏览器里没有 —— 换成可控桩（与 `DatabaseView.undo.test.ts` 同一套口径）。
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

async function settle() {
  await nextTick()
  await nextTick()
  await new Promise((resolve) => setTimeout(resolve, 0))
  await nextTick()
}

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

async function openEditMenu(mounted: Mounted): Promise<void> {
  if (mounted.wrapper.find('[data-testid="edit-menu"]').exists()) return
  await mounted.wrapper.find('[data-testid="edit-menu-toggle"]').trigger('click')
  await settle()
}

/** 页签条上第 n 张（从 0 数）的名字按钮。 */
function tabName(mounted: Mounted, n: number) {
  return mounted.wrapper.findAll('.db__qtab-name')[n]
}

async function openNewTab(mounted: Mounted): Promise<void> {
  await mounted.wrapper.find('.db__qtab-add').trigger('click')
  await settle()
}

async function switchToTab(mounted: Mounted, n: number): Promise<void> {
  await tabName(mounted, n).trigger('click')
  await settle()
}

async function undo(mounted: Mounted): Promise<void> {
  press(editorOf(mounted), { key: 'z', ctrlKey: true })
  await settle()
}

describe('每页签一份撤销栈（第 26 轮）', () => {
  beforeEach(() => {
    formatControl.next = null
  })

  it('在查询 1 改过 → 新建查询 2 → 切回查询 1：Ctrl+Z 撤的是查询 1 自己的上一步', async () => {
    const mounted = await mountView()
    const initial = editorOf(mounted).value
    await typeInto(mounted, 'select 1', 8)
    expect(editorOf(mounted).value).toBe('select 1')

    await openNewTab(mounted)
    expect(editorOf(mounted).value).toBe('') // 新页签是空的

    await switchToTab(mounted, 0)
    expect(editorOf(mounted).value).toBe('select 1')

    await undo(mounted)
    // 切页签之前这条只能得到「历史已重置」；现在撤的是查询 1 自己打的那一步
    expect(editorOf(mounted).value).toBe(initial)
    const note = mounted.wrapper.find('[data-testid="undo-note"]')
    expect(note.exists()).toBe(false)

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('在空页签按 Ctrl+Z ⇒ 「已经撤到最早一步了」而不是「已重置」，且别的页签一字不动', async () => {
    const mounted = await mountView()
    await typeInto(mounted, 'select 1', 8)
    await openNewTab(mounted)
    await typeInto(mounted, '', 0)

    await undo(mounted)
    const note = mounted.wrapper.find('[data-testid="undo-note"]')
    expect(note.exists()).toBe(true)
    expect(note.text()).toContain('已经撤到最早一步了')
    expect(note.text()).not.toContain('重置')

    await switchToTab(mounted, 0)
    expect(editorOf(mounted).value).toBe('select 1')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('撤销 / 重做菜单的可用态跟着当前页签走（切到有历史的页签就亮起来）', async () => {
    const mounted = await mountView()
    await typeInto(mounted, 'select 1', 8)
    await openNewTab(mounted)

    await openEditMenu(mounted)
    // 新页签是空栈：撤销灰
    expect(mounted.wrapper.find('[data-testid="edit-menu-undo"]').attributes('disabled')).toBeDefined()

    press(editorOf(mounted), { key: 'Escape' })
    await settle()
    await switchToTab(mounted, 0)
    await openEditMenu(mounted)
    expect(mounted.wrapper.find('[data-testid="edit-menu-undo"]').attributes('disabled')).toBeUndefined()

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('页签徽标如实报「还能撤几步」：切到别的页签时它仍挂在原来那张上', async () => {
    const mounted = await mountView()
    await typeInto(mounted, 'select 1', 8)

    let badges = mounted.wrapper.findAll('[data-testid="qtab-undo-depth"]')
    expect(badges).toHaveLength(1)
    expect(badges[0].text()).toContain('1')
    expect(badges[0].attributes('title')).toContain('还能撤 1 步')

    await openNewTab(mounted)
    // 新页签没有历史 ⇒ 不挂徽标；查询 1 那张的徽标还在（这就是「切走历史还在」的可见面）
    badges = mounted.wrapper.findAll('[data-testid="qtab-undo-depth"]')
    expect(badges).toHaveLength(1)
    expect(badges[0].text()).toContain('1')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('关掉页签后它的历史随之消失：落到的那张页签撤的是自己的上一步', async () => {
    const mounted = await mountView()
    await typeInto(mounted, 'tab-one', 7)
    await openNewTab(mounted)
    await typeInto(mounted, 'tab-two', 7)

    // 关掉当前（第二张）页签 ⇒ 落到第一张
    await mounted.wrapper.findAll('[data-testid="qtab-close"]')[1].trigger('click')
    await settle()
    expect(editorOf(mounted).value).toBe('tab-one')

    await undo(mounted)
    // 撤的是第一张自己的那一步（回到初始 SQL），绝不是把 tab-two 的内容拉进来
    expect(editorOf(mounted).value).not.toBe('tab-two')
    expect(editorOf(mounted).value).toContain('app.accounts')

    mounted.restore()
    mounted.wrapper.unmount()
  })
})
