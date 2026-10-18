// @vitest-environment happy-dom
// 状态栏 + 跳行列接线判据（B1 第二批）—— 2026-10-18
//
// 为什么必须有这一条：`workspace/editing.ts::matchBracket`（FR-EDIT-50）与
// `workspace/navigation.ts::parseJumpInput`/`offsetOfJump`（FR-EDIT-19）此前**零导入** ——
// 纯函数单测只能证明「规则算得对」，证明不了「界面上真的把那三格显示出来、真的把光标挪过去」。
// 所以这里真挂 DatabaseView、真派发 keydown/keyup、真提交表单，断言 DOM 文案与 textarea 光标。
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

function editorOf({ wrapper }: Mounted): HTMLTextAreaElement {
  return wrapper.find('.db__editor textarea').element as HTMLTextAreaElement
}

/** 放一段文字、摆好光标，并**真派发** input + keyup（等同用户打字 / 移动光标）。 */
async function setText(mounted: Mounted, text: string, caret: number, end?: number) {
  const area = editorOf(mounted)
  area.value = text
  area.setSelectionRange(caret, end ?? caret)
  area.dispatchEvent(new Event('input', { bubbles: true }))
  area.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }))
  await nextTick()
  area.setSelectionRange(caret, end ?? caret)
  area.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }))
  await nextTick()
  await nextTick()
  return area
}

/** 只挪光标（等同用户按方向键 / 点一下）。 */
async function moveCaret(mounted: Mounted, caret: number) {
  const area = editorOf(mounted)
  area.setSelectionRange(caret, caret)
  area.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }))
  await nextTick()
  await nextTick()
}

function press(area: HTMLElement, init: KeyboardEventInit): boolean {
  return area.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ...init }))
}

function text(mounted: Mounted, testid: string): string {
  const node = mounted.wrapper.find(`[data-testid="${testid}"]`)
  return node.exists() ? node.text() : '⟪缺件⟫'
}

async function settle() {
  await nextTick()
  await nextTick()
  await new Promise((resolve) => setTimeout(resolve, 0))
}

describe('编辑器状态栏（B1 第二批：光标 行:列 / 缩进口径 / 括号配对）', () => {
  it('三格都挂在编辑器下方，光标在最前时是「行 1 · 列 1」', async () => {
    const mounted = await mountView()
    await setText(mounted, 'select 1', 0)

    expect(mounted.wrapper.find('.db__editor-status').exists()).toBe(true)
    expect(text(mounted, 'editor-caret')).toContain('行 1')
    expect(text(mounted, 'editor-caret')).toContain('列 1')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('光标移到第 2 行第 3 列（真 keyup 驱动），读数跟着走', async () => {
    const mounted = await mountView()
    await setText(mounted, 'select 1\nselect 2', 0)

    await moveCaret(mounted, 'select 1\nse'.length)
    expect(text(mounted, 'editor-caret')).toContain('行 2')
    expect(text(mounted, 'editor-caret')).toContain('列 3')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('括号配对：光标在 ( 之后 ⇒ 显示两个位置（1:8 ↔ 1:10）且不是告警态', async () => {
    const mounted = await mountView()
    await setText(mounted, 'select (1)', 8)

    const bracket = text(mounted, 'editor-bracket')
    expect(bracket).toContain('1:8')
    expect(bracket).toContain('1:10')
    const node = mounted.wrapper.find('[data-testid="editor-bracket"]')
    expect(node.classes()).toContain('db__status-bracket--matched')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('括号不配平 ⇒ 告警态并点名是哪个括号（不是静默）', async () => {
    const mounted = await mountView()
    await setText(mounted, 'select (1', 8)

    const bracket = text(mounted, 'editor-bracket')
    expect(bracket).toContain('不配对')
    expect(bracket).toContain('(')
    const node = mounted.wrapper.find('[data-testid="editor-bracket"]')
    expect(node.classes()).toContain('db__status-bracket--unmatched')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('否定面：光标不在括号旁 ⇒ 显示「无括号」，不误报配对也不告警', async () => {
    const mounted = await mountView()
    await setText(mounted, 'select (1)', 0)

    expect(text(mounted, 'editor-bracket')).toContain('无括号')
    const node = mounted.wrapper.find('[data-testid="editor-bracket"]')
    expect(node.classes()).toContain('db__status-bracket--none')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('缩进口径按内容判：两空格内容 ⇒ 空格 ×2；两行制表符 ⇒ Tab 缩进', async () => {
    const mounted = await mountView()

    await setText(mounted, 'select\n  a\n  b', 0)
    expect(text(mounted, 'editor-indent')).toContain('空格 ×2')

    await setText(mounted, 'select\n\ta\n\tb', 0)
    expect(text(mounted, 'editor-indent')).toContain('Tab')

    mounted.restore()
    mounted.wrapper.unmount()
  })
})

describe('跳行列（FR-EDIT-19：Ctrl+G / 状态栏按钮）', () => {
  it('Ctrl+G 开面板且**不改编辑器文本**；输入 3 回车 ⇒ 光标落到第 3 行首、面板关闭', async () => {
    const mounted = await mountView()
    const area = await setText(mounted, 'a\nb\nc', 0)

    expect(press(area, { key: 'g', ctrlKey: true })).toBe(false)
    await settle()
    expect(editorOf(mounted).value).toBe('a\nb\nc')
    const input = mounted.wrapper.find('[data-testid="goto-input"]')
    expect(input.exists()).toBe(true)
    // 默认填的是当前行号，整段选中（直接打就覆盖）
    expect((input.element as HTMLInputElement).value).toBe('1')

    ;(input.element as HTMLInputElement).value = '3'
    await input.trigger('input')
    await mounted.wrapper.find('.db__goto').trigger('submit')
    await settle()

    expect(mounted.wrapper.find('.db__goto').exists()).toBe(false)
    expect(editorOf(mounted).selectionStart).toBe('a\nb\nc'.indexOf('c'))
    expect(text(mounted, 'editor-caret')).toContain('行 3')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('认「行:列」写法：2:2 ⇒ 光标落在第 2 行第 2 列', async () => {
    const mounted = await mountView()
    await setText(mounted, 'select 1\nselect 2', 0)
    press(editorOf(mounted), { key: 'G', ctrlKey: true })
    await settle()

    const input = mounted.wrapper.find('[data-testid="goto-input"]')
    ;(input.element as HTMLInputElement).value = '2:2'
    await input.trigger('input')
    await mounted.wrapper.find('.db__goto').trigger('submit')
    await settle()

    expect(editorOf(mounted).selectionStart).toBe('select 1\ns'.length)
    expect(text(mounted, 'editor-caret')).toContain('行 2')
    expect(text(mounted, 'editor-caret')).toContain('列 2')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('否定面：非法输入 ⇒ 面板不关、如实给原因、光标与文本都不动', async () => {
    const mounted = await mountView()
    await setText(mounted, 'select 1\nselect 2', 3)
    press(editorOf(mounted), { key: 'g', ctrlKey: true })
    await settle()

    const input = mounted.wrapper.find('[data-testid="goto-input"]')
    ;(input.element as HTMLInputElement).value = 'abc'
    await input.trigger('input')
    await mounted.wrapper.find('.db__goto').trigger('submit')
    await settle()

    expect(mounted.wrapper.find('.db__goto').exists()).toBe(true)
    expect(text(mounted, 'goto-error')).toContain('只认')
    expect(editorOf(mounted).value).toBe('select 1\nselect 2')
    expect(editorOf(mounted).selectionStart).toBe(3)

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('行号超界 ⇒ 夹到末行（不报错、不越界）', async () => {
    const mounted = await mountView()
    await setText(mounted, 'a\nb\nc', 0)
    press(editorOf(mounted), { key: 'g', ctrlKey: true })
    await settle()

    const input = mounted.wrapper.find('[data-testid="goto-input"]')
    ;(input.element as HTMLInputElement).value = '99'
    await input.trigger('input')
    await mounted.wrapper.find('.db__goto').trigger('submit')
    await settle()

    expect(text(mounted, 'goto-error')).toBe('⟪缺件⟫')
    expect(text(mounted, 'editor-caret')).toContain('行 3')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('可见面：状态栏那颗「跳行列…」按钮能开面板，Esc 关掉', async () => {
    const mounted = await mountView()
    await setText(mounted, 'select 1', 0)

    await mounted.wrapper.find('.db__status-goto').trigger('click')
    await settle()
    expect(mounted.wrapper.find('.db__goto').exists()).toBe(true)

    const input = mounted.wrapper.find('[data-testid="goto-input"]')
    input.element.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }))
    await settle()
    expect(mounted.wrapper.find('.db__goto').exists()).toBe(false)

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('可见面：按键提示里写着 Ctrl+G（否则只有摸到的人知道这条键）', async () => {
    const mounted = await mountView()
    expect(mounted.wrapper.find('.db__editor-keys').text()).toContain('Ctrl+G')
    expect(mounted.errors).toEqual([])
    mounted.restore()
    mounted.wrapper.unmount()
  })
})
