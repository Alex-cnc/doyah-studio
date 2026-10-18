// @vitest-environment happy-dom
// 补全清单的键盘导航判据（B1 收尾 · 2026-10-18）
//
// 为什么要有这一条：纯函数测「下标算得对」证明不了「按 ↓ 屏幕上的高亮真的动了」——
// 断了的地方永远是接线（keydown 没接 / 接在 keyup 之后被重算打回第一条 / 高亮在屏幕外），
// 那些只有真挂载才红。否定面同样重要：清单关着时回车必须还是换行，不能被吞。
import { describe, expect, it, vi } from 'vitest'
import { nextTick } from 'vue'
import { mount } from '@vue/test-utils'
import DatabaseView from './DatabaseView.vue'

async function mountView() {
  const errors: string[] = []
  const errSpy = vi.spyOn(console, 'error').mockImplementation((...args: unknown[]) => {
    errors.push(args.map((a) => (a instanceof Error ? a.message : String(a))).join(' '))
  })
  const wrapper = mount(DatabaseView)
  await new Promise((resolve) => setTimeout(resolve, 0))
  return { wrapper, errors, restore: () => errSpy.mockRestore() }
}

type Mounted = Awaited<ReturnType<typeof mountView>>

function editorOf(mounted: Mounted): HTMLTextAreaElement {
  return mounted.wrapper.find('.db__editor textarea').element as HTMLTextAreaElement
}

async function settle() {
  await nextTick()
  await nextTick()
  await new Promise((resolve) => setTimeout(resolve, 0))
}

/** 往编辑器里打字（走真实 input 事件 ⇒ 触发补全刷新）。 */
async function type(mounted: Mounted, text: string): Promise<HTMLTextAreaElement> {
  const area = editorOf(mounted)
  area.value = text
  area.setSelectionRange(text.length, text.length)
  area.dispatchEvent(new Event('input', { bubbles: true }))
  await settle()
  return editorOf(mounted)
}

/** 一次完整的按键（keydown + keyup，像真的敲了一下）。返回 keydown 是否被拦下。 */
async function press(area: HTMLTextAreaElement, init: KeyboardEventInit): Promise<boolean> {
  const notCancelled = area.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ...init }))
  await settle()
  area.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, cancelable: true, ...init }))
  await settle()
  return notCancelled
}

type Row = { text: string; detail: string }

/** 清单里所有候选（按钮），以及当前高亮那一条。 */
function rows(mounted: Mounted): Row[] {
  return mounted.wrapper.findAll('.db__completion').map((b) => ({
    text: b.find('.db__completion-text').text(),
    detail: b.find('.db__kind').text(),
  }))
}

function activeRow(mounted: Mounted): Row | null {
  const active = mounted.wrapper.find('.db__completion--active')
  if (!active.exists()) return null
  return { text: active.find('.db__completion-text').text(), detail: active.find('.db__kind').text() }
}

const EXPANDED_SELECT = 'SELECT *\nFROM table\nWHERE cond'

describe('补全清单的键盘导航（B1 收尾）', () => {
  it('↓ 把高亮移到下一条、再按一次回卷到第一条（循环而不是卡死在两端）', async () => {
    const mounted = await mountView()
    const area = await type(mounted, 'sel')
    const all = rows(mounted)
    expect(all.length).toBeGreaterThanOrEqual(2)
    expect(activeRow(mounted)).toEqual(all[0])

    await press(area, { key: 'ArrowDown' })
    expect(activeRow(mounted)).toEqual(all[1])

    await press(editorOf(mounted), { key: 'ArrowDown' })
    expect(activeRow(mounted)).toEqual(all[0])

    mounted.restore()
    expect(mounted.errors).toEqual([])
  })

  it('↑ 从第一条回卷到末条（不是卡在顶上不动）', async () => {
    const mounted = await mountView()
    const area = await type(mounted, 'sel')
    const all = rows(mounted)
    await press(area, { key: 'ArrowUp' })
    expect(activeRow(mounted)).toEqual(all[all.length - 1])
    mounted.restore()
    expect(mounted.errors).toEqual([])
  })

  it('回车插入**当前高亮**那条：高亮走到片段那条时得到展开后的骨架', async () => {
    const mounted = await mountView()
    const area = await type(mounted, 'sel')
    const all = rows(mounted)
    const snippetAt = all.findIndex((r) => r.detail.includes('片段'))
    expect(snippetAt).toBeGreaterThanOrEqual(0)

    let current = area
    for (let i = 0; i < snippetAt; i += 1) {
      await press(current, { key: 'ArrowDown' })
      current = editorOf(mounted)
    }
    expect(activeRow(mounted)?.detail).toContain('片段')

    await press(current, { key: 'Enter' })
    const editor = editorOf(mounted)
    expect(editor.value).toBe(EXPANDED_SELECT)
    expect(editor.selectionStart).toBe(EXPANDED_SELECT.length)
    // 清单接受后关掉（不然插入完还糊在屏幕上）
    expect(mounted.wrapper.findAll('.db__completion').length).toBe(0)
    mounted.restore()
    expect(mounted.errors).toEqual([])
  })

  it('清单关着时回车照旧换行（否定面：不被补全吞掉）', async () => {
    const mounted = await mountView()
    const area = await type(mounted, '')
    expect(rows(mounted).length).toBe(0)
    await press(area, { key: 'Enter' })
    expect(editorOf(mounted).value).toBe('\n')
    mounted.restore()
    expect(mounted.errors).toEqual([])
  })

  it('清单关着时 ↓ 不被拦下（否定面：光标还能正常移动）', async () => {
    const mounted = await mountView()
    const area = await type(mounted, '')
    expect(rows(mounted).length).toBe(0)
    const notCancelled = await press(area, { key: 'ArrowDown' })
    expect(notCancelled).toBe(true)
    mounted.restore()
    expect(mounted.errors).toEqual([])
  })

  it('清单开着时给出按键提示（↑↓ / 回车 这件事写在脸上）', async () => {
    const mounted = await mountView()
    await type(mounted, 'sel')
    const hint = mounted.wrapper.find('[data-testid="completion-keys"]')
    expect(hint.exists()).toBe(true)
    expect(hint.text()).toContain('回车')
    mounted.restore()
    expect(mounted.errors).toEqual([])
  })
})
