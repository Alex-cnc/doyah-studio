// @vitest-environment happy-dom
// 编辑菜单 + 查找 / 替换的**接线判据**（FR-EDIT-17 / FR-EDIT-18）—— 2026-10-18
//
// 为什么必须有这一条：纯逻辑（`workspace/findReplace.ts` 19 条）只能证明"规则算得对"，
// 证明不了「按 Ctrl+F 真的开得出来」「输入框里打一个字焦点会不会被编辑器夺走」「替换真的落到 textarea」。
// 所以这里**真挂 DatabaseView、真派发按键、真读 DOM 与 textarea 的值**。
// 反面用例（没有匹配时界面必须**说清**、菜单点空白处要收）与正例同权 —— 安静不是结论。
import { describe, expect, it, vi } from 'vitest'
import { nextTick } from 'vue'
import { mount } from '@vue/test-utils'
import DatabaseView from './DatabaseView.vue'

async function mountView() {
  const errors: string[] = []
  const errSpy = vi.spyOn(console, 'error').mockImplementation((...args: unknown[]) => {
    errors.push(args.map((a) => (a instanceof Error ? a.message : String(a))).join(' '))
  })
  const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {})
  // attachTo：焦点 / activeElement 这类判据要求节点真的在文档里（默认挂到游离 div 上，focus() 一律无效）
  const host = document.createElement('div')
  document.body.appendChild(host)
  const wrapper = mount(DatabaseView, { attachTo: host })
  await new Promise((resolve) => setTimeout(resolve, 0))
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

/** 往编辑器里放一段文字并把光标摆好（走真实 input 事件，等同用户粘贴/打字）。 */
async function setText(mounted: Mounted, text: string, caret: number, end?: number) {
  const area = editorOf(mounted)
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

async function settle() {
  await nextTick()
  await nextTick()
  await new Promise((resolve) => setTimeout(resolve, 0))
}

/** 往一个输入框里打字（走真实 input 事件，v-model 才会动）。 */
async function typeInto({ wrapper }: Mounted, testid: string, value: string) {
  const input = wrapper.find(`[data-testid="${testid}"]`).element as HTMLInputElement
  input.value = value
  input.dispatchEvent(new Event('input', { bubbles: true }))
  await settle()
  return input
}

describe('FR-EDIT-17 编辑菜单：一个能看见的入口', () => {
  it('工具栏有「编辑」按钮；点开菜单，五项都在（查找替换 / 跳行列 / 缩进 / 反缩进 / 清除查询）', async () => {
    const mounted = await mountView()
    const toggle = mounted.wrapper.find('[data-testid="edit-menu-toggle"]')
    expect(toggle.exists()).toBe(true)
    expect(toggle.text()).toContain('编辑')

    expect(mounted.wrapper.find('[data-testid="edit-menu"]').exists()).toBe(false)
    await toggle.trigger('click')
    await settle()

    const menu = mounted.wrapper.find('[data-testid="edit-menu"]')
    expect(menu.exists()).toBe(true)
    const ids = [
      'edit-menu-find',
      'edit-menu-goto',
      'edit-menu-indent',
      'edit-menu-outdent',
      'edit-menu-clear',
    ]
    for (const id of ids) expect(mounted.wrapper.find(`[data-testid="${id}"]`).exists()).toBe(true)

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('点空白处（挡板）收菜单 —— 不许"开着收不掉"', async () => {
    const mounted = await mountView()
    await mounted.wrapper.find('[data-testid="edit-menu-toggle"]').trigger('click')
    await settle()
    expect(mounted.wrapper.find('[data-testid="edit-menu"]').exists()).toBe(true)

    await mounted.wrapper.find('[data-testid="edit-menu-backdrop"]').trigger('click')
    await settle()
    expect(mounted.wrapper.find('[data-testid="edit-menu"]').exists()).toBe(false)

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('菜单里的「缩进选中行」真按 4 空格缩进多行（走的是既有 indentSelection，规则不重写）', async () => {
    const mounted = await mountView()
    await setText(mounted, 'select 1\nselect 2', 0, 'select 1\nselect 2'.length)

    await mounted.wrapper.find('[data-testid="edit-menu-toggle"]').trigger('click')
    await settle()
    await mounted.wrapper.find('[data-testid="edit-menu-indent"]').trigger('click')
    await settle()

    expect(editorOf(mounted).value).toBe('    select 1\n    select 2')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('菜单里的「跳到行或列」打开既有跳转条（不另造第二套跳转）', async () => {
    const mounted = await mountView()
    await setText(mounted, 'select 1', 0)

    await mounted.wrapper.find('[data-testid="edit-menu-toggle"]').trigger('click')
    await settle()
    await mounted.wrapper.find('[data-testid="edit-menu-goto"]').trigger('click')
    await settle()

    expect(mounted.wrapper.find('[data-testid="goto-input"]').exists()).toBe(true)

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('菜单里的「清除查询」清空编辑器（确认框点"确定"后才清）', async () => {
    const mounted = await mountView()
    // happy-dom 没有 window.confirm（真实 WebView2 有）—— 这里补一个"点了确定"的同形替身
    const originalConfirm = window.confirm
    const confirmSpy = vi.fn(() => true)
    window.confirm = confirmSpy
    await setText(mounted, 'select 1', 0)

    await mounted.wrapper.find('[data-testid="edit-menu-toggle"]').trigger('click')
    await settle()
    await mounted.wrapper.find('[data-testid="edit-menu-clear"]').trigger('click')
    await settle()

    expect(confirmSpy).toHaveBeenCalled()
    expect(editorOf(mounted).value).toBe('')

    window.confirm = originalConfirm
    mounted.restore()
    mounted.wrapper.unmount()
  })
})

describe('FR-EDIT-18 查找 / 替换：Ctrl+F 开、读数与选区、替换落回编辑器', () => {
  it('Ctrl+F 被编辑器接管（不放给 WebView 的第二套查找条）并开出查找条', async () => {
    const mounted = await mountView()
    const area = await setText(mounted, 'select 1 from a', 0)

    expect(press(area, { key: 'f', ctrlKey: true })).toBe(false)
    await settle()
    expect(mounted.wrapper.find('[data-testid="find-bar"]').exists()).toBe(true)

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('输入查询词 ⇒ 读数说清「第几处 / 共几处」，点下一处把选区摆到第二处', async () => {
    const mounted = await mountView()
    await setText(mounted, 'select 1 from a where b from c', 0)
    press(editorOf(mounted), { key: 'f', ctrlKey: true })
    await settle()

    await typeInto(mounted, 'find-term', 'from')
    expect(mounted.wrapper.find('[data-testid="find-readout"]').text()).toContain('1 / 2')

    await mounted.wrapper.find('[data-testid="find-next"]').trigger('click')
    await settle()
    expect(mounted.wrapper.find('[data-testid="find-readout"]').text()).toContain('2 / 2')

    const area = editorOf(mounted)
    expect(area.value.slice(area.selectionStart, area.selectionEnd)).toBe('from')
    expect(area.selectionStart).toBe('select 1 from a where b '.length)

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('没有匹配时**如实说**没有匹配（不静默、也不假装在第 1 处）', async () => {
    const mounted = await mountView()
    await setText(mounted, 'select 1', 0)
    press(editorOf(mounted), { key: 'f', ctrlKey: true })
    await settle()

    await typeInto(mounted, 'find-term', 'zzz')
    const readout = mounted.wrapper.find('[data-testid="find-readout"]').text()
    expect(readout).toContain('没有匹配')
    expect(mounted.wrapper.find('[data-testid="find-next"]').attributes('disabled')).toBeDefined()

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('多行编辑器里已选的一段会被当作查询词预填（选中就查它）', async () => {
    const mounted = await mountView()
    await setText(mounted, 'select id from t', 7, 9) // 选中 "id"
    press(editorOf(mounted), { key: 'f', ctrlKey: true })
    await settle()

    const term = mounted.wrapper.find('[data-testid="find-term"]').element as HTMLInputElement
    expect(term.value).toBe('id')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('全部替换：两处都换掉、textarea 真变了、回执说替了几处', async () => {
    const mounted = await mountView()
    await setText(mounted, 'select 1 from a where b from c', 0)
    press(editorOf(mounted), { key: 'h', ctrlKey: true }) // Ctrl+H 直接开替换
    await settle()

    await typeInto(mounted, 'find-term', 'from')
    await typeInto(mounted, 'find-replacement', 'FROM')
    await mounted.wrapper.find('[data-testid="find-replace-all"]').trigger('click')
    await settle()

    expect(editorOf(mounted).value).toBe('select 1 FROM a where b FROM c')
    expect(mounted.wrapper.find('[data-testid="find-note"]').text()).toContain('替换了 2 处')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('替换一处只动当前那一处（其余原样）', async () => {
    const mounted = await mountView()
    await setText(mounted, 'from from', 0)
    press(editorOf(mounted), { key: 'h', ctrlKey: true })
    await settle()

    await typeInto(mounted, 'find-term', 'from')
    await typeInto(mounted, 'find-replacement', 'FROM')
    await mounted.wrapper.find('[data-testid="find-replace"]').trigger('click')
    await settle()

    expect(editorOf(mounted).value).toBe('FROM from')
    expect(mounted.wrapper.find('[data-testid="find-note"]').text()).toContain('替换了 1 处')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('关闭查找条后编辑器拿回焦点（Esc 不该把光标留在浮层里）', async () => {
    const mounted = await mountView()
    await setText(mounted, 'select 1', 0)
    press(editorOf(mounted), { key: 'f', ctrlKey: true })
    await settle()

    await mounted.wrapper.find('[data-testid="find-close"]').trigger('click')
    await settle()
    expect(mounted.wrapper.find('[data-testid="find-bar"]').exists()).toBe(false)
    expect(document.activeElement).toBe(editorOf(mounted))

    mounted.restore()
    mounted.wrapper.unmount()
  })
})

// ─────────────────────────────────────────────────────────────────────────────
// FR-EDIT-48 的等长替换条款：「等长替换 ⇒ 光标与选区都不动」
// 老行为两个毛病都在这两条判据上现形：全部替换把光标甩到文末、替换一处把选区塌成光标。
// ─────────────────────────────────────────────────────────────────────────────
describe('FR-EDIT-48 替换之后的落点：等长替换不许顶掉光标与选区', () => {
  it('全部替换（等长）后光标还在原处 —— 不再被甩到文末', async () => {
    const mounted = await mountView()
    const text = 'select 1 from a where b from c'
    await setText(mounted, text, 0)
    press(editorOf(mounted), { key: 'h', ctrlKey: true })
    await settle()
    await typeInto(mounted, 'find-term', 'from')
    await typeInto(mounted, 'find-replacement', 'FROM')
    // 打查询词时选区会被摆到第一处命中（既有行为）；这里把光标摆回第 20 个字符（'where' 之后）当基线
    const before = editorOf(mounted)
    before.setSelectionRange(20, 20)
    expect(before.selectionStart).toBe(20)

    await mounted.wrapper.find('[data-testid="find-replace-all"]').trigger('click')
    await settle()

    const area = editorOf(mounted)
    expect(area.value).toBe('select 1 FROM a where b FROM c')
    expect(area.selectionStart).toBe(20)
    expect(area.selectionEnd).toBe(20)

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('替换一处后选区落在下一处命中（看得见下一个要替的是谁），回执说清', async () => {
    const mounted = await mountView()
    await setText(mounted, 'from from', 0)
    press(editorOf(mounted), { key: 'h', ctrlKey: true })
    await settle()
    await typeInto(mounted, 'find-term', 'from')
    await typeInto(mounted, 'find-replacement', 'FROM')

    await mounted.wrapper.find('[data-testid="find-replace"]').trigger('click')
    await settle()

    const area = editorOf(mounted)
    expect(area.value).toBe('FROM from')
    expect(area.value.slice(area.selectionStart, area.selectionEnd)).toBe('from')
    expect(area.selectionStart).toBe(5)
    expect(mounted.wrapper.find('[data-testid="find-note"]').text()).toContain('下一处已选中')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('最后一处替完之后选区留在刚替换出来的那一段（不塌陷、不跳到别处）', async () => {
    const mounted = await mountView()
    await setText(mounted, 'select from', 0)
    press(editorOf(mounted), { key: 'h', ctrlKey: true })
    await settle()
    await typeInto(mounted, 'find-term', 'from')
    await typeInto(mounted, 'find-replacement', 'FROM')

    await mounted.wrapper.find('[data-testid="find-replace"]').trigger('click')
    await settle()

    const area = editorOf(mounted)
    expect(area.value).toBe('select FROM')
    expect(area.value.slice(area.selectionStart, area.selectionEnd)).toBe('FROM')
    expect(area.selectionStart).toBe(7)
    expect(mounted.wrapper.find('[data-testid="find-note"]').text()).toContain('已替完')

    mounted.restore()
    mounted.wrapper.unmount()
  })
})
