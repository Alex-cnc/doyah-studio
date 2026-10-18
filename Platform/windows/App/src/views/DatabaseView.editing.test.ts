// @vitest-environment happy-dom
// 编辑键接线判据（B1 第一批 6 条）—— 2026-10-18
//
// 为什么必须有这一条：`workspace/editing.ts` 的 11 个纯函数此前**全仓零导入**（逻辑已落地、未接线）。
// 光有纯函数单测只能证明「规则算得对」，证明不了「按这个键真的会改到编辑器里的字」——
// 接线断在模板（`@keydown` 没挂上）或断在「先写字后摆光标」的顺序上，纯函数测试一个都红不了。
// 所以这里**真挂 DatabaseView、真往 textarea 派发 KeyboardEvent**，断言 textarea 的值与光标。
import { describe, expect, it, vi } from 'vitest'
import { nextTick } from 'vue'
import { mount } from '@vue/test-utils'
import DatabaseView from './DatabaseView.vue'

/** 挂载（顺手收掉挂载期 console.error / warn，免得噪声混进断言）。 */
async function mountView() {
  const errors: string[] = []
  const errSpy = vi.spyOn(console, 'error').mockImplementation((...args: unknown[]) => {
    errors.push(args.map((a) => (a instanceof Error ? a.message : String(a))).join(' '))
  })
  const wrapper = mount(DatabaseView)
  await new Promise((resolve) => setTimeout(resolve, 0))
  return {
    wrapper,
    errors,
    restore: () => errSpy.mockRestore(),
  }
}

type Mounted = Awaited<ReturnType<typeof mountView>>

/** 往编辑器里放一段文字并把光标摆好（走真实 input 事件，等同用户粘贴/打字）。 */
async function setText({ wrapper }: Mounted, text: string, caret: number, end?: number) {
  const area = wrapper.find('.db__editor textarea').element as HTMLTextAreaElement
  area.value = text
  area.setSelectionRange(caret, end ?? caret)
  area.dispatchEvent(new Event('input', { bubbles: true }))
  await nextTick()
  area.setSelectionRange(caret, end ?? caret)
  return area
}

/** 真派发一次按键；返回 false = 被编辑键接管（preventDefault），true = 放行给浏览器。 */
function press(area: HTMLTextAreaElement, init: KeyboardEventInit): boolean {
  return area.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ...init }))
}

/** 编辑是异步落盘（先写全文、nextTick 后摆光标）—— 等它落完再断言。 */
async function settle() {
  await nextTick()
  await nextTick()
  await new Promise((resolve) => setTimeout(resolve, 0))
}

function editorOf({ wrapper }: Mounted): HTMLTextAreaElement {
  return wrapper.find('.db__editor textarea').element as HTMLTextAreaElement
}

describe('编辑器按键接线（B1：Ctrl+/ · Alt+↑↓ · Alt+Shift+↓ · Enter · Tab · 自动配对）', () => {
  it('Ctrl+/ 给当前行加 -- 注释，再按一次取消（只动行首、保持其余行不动）', async () => {
    const mounted = await mountView()
    const area = await setText(mounted, 'select 1\nselect 2', 0)

    expect(press(area, { key: '/', ctrlKey: true })).toBe(false)
    await settle()
    // 口径与纯函数一致：注释符紧贴缩进之后、**不额外插空格**（`editing.test.ts` 同一条）
    expect(editorOf(mounted).value).toBe('--select 1\nselect 2')

    press(editorOf(mounted), { key: '/', ctrlKey: true })
    await settle()
    expect(editorOf(mounted).value).toBe('select 1\nselect 2')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('Alt+↓ 把当前行往下搬一行，光标跟着搬（Alt+↑ 到首行是 no-op）', async () => {
    const mounted = await mountView()
    const area = await setText(mounted, 'first\nsecond', 0)

    expect(press(area, { key: 'ArrowDown', altKey: true })).toBe(false)
    await settle()
    expect(editorOf(mounted).value).toBe('second\nfirst')

    // 再往上搬回去；此时光标在第 1 行（原 first），Alt+↑ 到顶 ⇒ 内容不变
    const back = editorOf(mounted)
    back.setSelectionRange(0, 0)
    press(back, { key: 'ArrowUp', altKey: true })
    await settle()
    expect(editorOf(mounted).value).toBe('second\nfirst')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('Alt+Shift+↓ 复制当前行（副本在下面，选区落在副本上）', async () => {
    const mounted = await mountView()
    const area = await setText(mounted, 'select 1\nselect 2', 0)

    expect(press(area, { key: 'ArrowDown', altKey: true, shiftKey: true })).toBe(false)
    await settle()
    const editor = editorOf(mounted)
    expect(editor.value).toBe('select 1\nselect 1\nselect 2')
    // 选区落在副本上（第 2 行全程），不是原文第 1 行
    expect(editor.value.slice(editor.selectionStart, editor.selectionEnd)).toBe('select 1')
    expect(editor.selectionStart).toBe('select 1\n'.length)

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('回车继承当前行缩进、开括号后多一级（缩进宽度按内容判：两空格内容 ⇒ 回车后 4 空格）', async () => {
    const mounted = await mountView()
    const text = '  select ('
    const area = await setText(mounted, text, text.length)

    expect(press(area, { key: 'Enter' })).toBe(false)
    await settle()
    const editor = editorOf(mounted)
    expect(editor.value).toBe('  select (\n    ')
    expect(editor.selectionStart).toBe(editor.value.length)

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('回车缩进在没有缩进内容时回退默认口径（4 空格）', async () => {
    const mounted = await mountView()
    const text = 'select ('
    const area = await setText(mounted, text, text.length)

    expect(press(area, { key: 'Enter' })).toBe(false)
    await settle()
    expect(editorOf(mounted).value).toBe('select (\n    ')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('打出 ( 自动补 ) 且光标留在中间；闭合符已在光标处时跳过不再补', async () => {
    const mounted = await mountView()
    const area = await setText(mounted, '', 0)

    expect(press(area, { key: '(' })).toBe(false)
    await settle()
    let editor = editorOf(mounted)
    expect(editor.value).toBe('()')
    expect(editor.selectionStart).toBe(1)

    // 光标在 ( 与 ) 之间，打出 ) ⇒ 跳过：内容不变、光标右移一格
    press(editor, { key: ')' })
    await settle()
    editor = editorOf(mounted)
    expect(editor.value).toBe('()')
    expect(editor.selectionStart).toBe(2)

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('有选区时打出引号是**包裹**选区（不是插入两个引号）', async () => {
    const mounted = await mountView()
    const area = await setText(mounted, 'select name from t', 7, 11) // 选中 name

    expect(press(area, { key: "'" })).toBe(false)
    await settle()
    const editor = editorOf(mounted)
    expect(editor.value).toBe("select 'name' from t")
    // 选区仍罩着原来那四个字
    expect(editor.value.slice(editor.selectionStart, editor.selectionEnd)).toBe('name')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('Tab 在没有补全候选时缩进一个单位（光标不在词里 ⇒ 不夺走补全）', async () => {
    const mounted = await mountView()
    const area = await setText(mounted, 'select 1', 0)

    expect(press(area, { key: 'Tab' })).toBe(false)
    await settle()
    expect(editorOf(mounted).value).toBe('    select 1')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('否定面：Shift+Enter / Ctrl+A / 普通字母都**不被接管**，编辑器内容原样', async () => {
    const mounted = await mountView()
    const area = await setText(mounted, 'select 1', 3)

    expect(press(area, { key: 'Enter', shiftKey: true })).toBe(true)
    expect(press(area, { key: 'a', ctrlKey: true })).toBe(true)
    expect(press(area, { key: 'a' })).toBe(true)
    await settle()
    expect(editorOf(mounted).value).toBe('select 1')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('可见面：编辑器下有一条按键提示（用户不摸黑也能发现这几组键）', async () => {
    const mounted = await mountView()
    const hint = mounted.wrapper.find('.db__editor-keys')
    expect(hint.exists()).toBe(true)
    expect(hint.text()).toContain('Ctrl+/')
    expect(mounted.errors).toEqual([])
    mounted.restore()
    mounted.wrapper.unmount()
  })
})
