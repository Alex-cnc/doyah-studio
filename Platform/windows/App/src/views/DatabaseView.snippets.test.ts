// @vitest-environment happy-dom
// 片段补全接线判据（FR-EDIT-59 · 2026-10-18）
//
// 为什么要有这一条：`workspace/assist.ts` 的 `expandSnippet` / `snippetFor` 此前**全仓零导入**
// （逻辑已落地、未接线）。纯函数测「展开得对」证明不了「打 sel 按 Tab 真的会插进编辑器」——
// 断了的地方永远是接线（候选没进清单 / 接受后没摆光标 / 弹出列表点不动），那些只有真挂载才红。
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

/** 往编辑器里打字（走真实 input 事件 ⇒ 触发补全刷新）。 */
async function type(mounted: Mounted, text: string): Promise<HTMLTextAreaElement> {
  const area = editorOf(mounted)
  area.value = text
  area.setSelectionRange(text.length, text.length)
  area.dispatchEvent(new Event('input', { bubbles: true }))
  await settle()
  return editorOf(mounted)
}

async function settle() {
  await nextTick()
  await nextTick()
  await new Promise((resolve) => setTimeout(resolve, 0))
}

function press(area: HTMLTextAreaElement, init: KeyboardEventInit): boolean {
  return area.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ...init }))
}

const EXPANDED_SELECT = 'SELECT *\nFROM table\nWHERE cond'

describe('片段补全（B1 剩余项：assist.expandSnippet 接线）', () => {
  it('打 sel 弹出候选，其中一条是片段（说明里写着「片段」）', async () => {
    const mounted = await mountView()
    await type(mounted, 'sel')
    const buttons = mounted.wrapper.findAll('.db__completion')
    expect(buttons.length).toBeGreaterThan(0)
    const texts = buttons.map((b) => b.text())
    expect(texts.some((t) => t.includes('片段'))).toBe(true)
    mounted.restore()
    expect(mounted.errors).toEqual([])
  })

  it('Tab 接受片段 ⇒ 插入展开后的骨架，光标落在 $0（文末）', async () => {
    const mounted = await mountView()
    await type(mounted, 'sel')
    const list = mounted.wrapper.findAll('.db__completion')
    // 片段一般排在关键字后面（前缀命中优先，同类内按长度）：直接点那一条更稳，也顺带验了点击入口
    const snippetButton = list.find((b) => b.text().includes('片段'))
    expect(snippetButton).toBeTruthy()
    await snippetButton!.trigger('click')
    await settle()

    const editor = editorOf(mounted)
    expect(editor.value).toBe(EXPANDED_SELECT)
    expect(editor.selectionStart).toBe(EXPANDED_SELECT.length)
    // 没有残留占位符（展开必须把 ${n:默认} 都换掉）
    expect(editor.value).not.toContain('${')
    mounted.restore()
    expect(mounted.errors).toEqual([])
  })

  it('键盘路径同样成立：sel 后按 Tab 展开（不是只有鼠标能点）', async () => {
    const mounted = await mountView()
    const area = await type(mounted, 'sel')
    press(area, { key: 'Tab' })
    await settle()
    const editor = editorOf(mounted)
    // 候选第一条不一定是最短的片段，所以只断言「Tab 真的接受了某条候选并改了全文」
    expect(editor.value).not.toBe('sel')
    expect(editor.value.length).toBeGreaterThan(3)
    mounted.restore()
    expect(mounted.errors).toEqual([])
  })

  it('否定面：不匹配触发词时不会冒出片段（fro 只有 FROM 关键字）', async () => {
    const mounted = await mountView()
    await type(mounted, 'fro')
    const texts = mounted.wrapper.findAll('.db__completion').map((b) => b.text())
    expect(texts.some((t) => t.includes('片段'))).toBe(false)
    mounted.restore()
    expect(mounted.errors).toEqual([])
  })

  it('否定面：片段不会因为光标前没词就弹出来（空词不弹整表）', async () => {
    const mounted = await mountView()
    await type(mounted, '')
    expect(mounted.wrapper.findAll('.db__completion').length).toBe(0)
    mounted.restore()
    expect(mounted.errors).toEqual([])
  })
})
