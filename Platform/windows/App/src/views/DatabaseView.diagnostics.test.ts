// @vitest-environment happy-dom
// 诊断上屏接线判据（B1 第三批 · FR-EDIT-03 检查器 → FR-EDIT-56 画出来）—— 2026-10-18
//
// 为什么必须有这一条：`Db/src/lint.rs::diagnose` 有 15 条行为单测、`workspace/diagnostics.ts`
// 有 6 条切片不变量 —— 两边都能证明"算得对"，但**证明不了界面上真的画出来、真的点得动**。
// 所以这里真挂 DatabaseView、真喂 SQL、真点问题条，只把 IPC 的 `diagnoseSql` 换成**可控桩**
// （检查器本身在 Rust，浏览器里没有它；桩只替换"取诊断"这一步，其余包装保持原样）。
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { nextTick } from 'vue'
import { mount } from '@vue/test-utils'

type Stub = ((sql: string) => Promise<unknown[]>) | null

const control = vi.hoisted(() => ({
  stub: null as Stub,
  calls: [] as string[],
}))

vi.mock('../ipc', async (importOriginal) => {
  const actual = await importOriginal<Record<string, unknown>>()
  return {
    ...actual,
    diagnoseSql: (sql: string) => {
      control.calls.push(sql)
      return control.stub ? control.stub(sql) : Promise.resolve([])
    },
  }
})

import DatabaseView from './DatabaseView.vue'

async function mountView() {
  const errors: string[] = []
  const errSpy = vi.spyOn(console, 'error').mockImplementation((...args: unknown[]) => {
    errors.push(args.map((a) => (a instanceof Error ? a.message : String(a))).join(' '))
  })
  const wrapper = mount(DatabaseView)
  await settle()
  return { wrapper, errors, restore: () => errSpy.mockRestore() }
}

type Mounted = Awaited<ReturnType<typeof mountView>>

function editorOf({ wrapper }: Mounted): HTMLTextAreaElement {
  return wrapper.find('.db__editor textarea').element as HTMLTextAreaElement
}

async function settle() {
  for (let i = 0; i < 4; i += 1) {
    await nextTick()
    await new Promise((resolve) => setTimeout(resolve, 0))
  }
}

/** 真打字：写值 + 派发 input（等同用户敲键盘），再等诊断那一跳回来。 */
async function type(mounted: Mounted, text: string, caret?: number) {
  const area = editorOf(mounted)
  area.value = text
  area.setSelectionRange(caret ?? text.length, caret ?? text.length)
  area.dispatchEvent(new Event('input', { bubbles: true }))
  await settle()
  return area
}

describe('编辑面诊断上屏（FR-EDIT-56）', () => {
  beforeEach(() => {
    control.stub = null
    control.calls.length = 0
  })

  it('有问题时：编辑器里那一段带 error 标记，下方给出「问题 N」与可读说明', async () => {
    control.stub = async () => [
      { start: 7, end: 11, severity: 'error', message: "字符串没闭合：这个单引号到文末也没找到收尾" },
    ]
    const mounted = await mountView()
    await type(mounted, "select 'abc")

    // ① 下划线：高亮层里确实出现带 error 类的片段，且那段的文字就是问题范围
    const marked = mounted.wrapper.findAll('.db__tok--error')
    expect(marked.length).toBeGreaterThan(0)
    expect(marked.map((node) => node.text()).join('')).toBe("'abc")

    // ② 问题条：计数 + 位置（1 基行:列）+ 说明
    expect(mounted.wrapper.find('[data-testid="editor-problems"]').exists()).toBe(true)
    expect(mounted.wrapper.find('[data-testid="editor-problem-count"]').text()).toContain('1')
    const row = mounted.wrapper.find('.db__problem')
    expect(row.exists()).toBe(true)
    expect(row.text()).toContain('行 1')
    expect(row.text()).toContain('列 8')
    expect(row.text()).toContain('字符串没闭合')

    // ③ 真的问了检查器（不是界面自己瞎标）
    expect(control.calls[control.calls.length - 1]).toBe("select 'abc")

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('点问题条 ⇒ 光标跳到那一处（行列读数跟着变）', async () => {
    control.stub = async () => [
      { start: 17, end: 18, severity: 'error', message: '多余的右括号 )：它前面没有与之配对的左括号' },
    ]
    const mounted = await mountView()
    const area = await type(mounted, 'select 1\nselect 2)', 0)
    expect(area.selectionStart).toBe(0)

    await mounted.wrapper.find('.db__problem').trigger('click')
    await settle()

    expect(editorOf(mounted).selectionStart).toBe(17)
    const caret = mounted.wrapper.find('[data-testid="editor-caret"]').text()
    expect(caret).toContain('行 2')
    expect(caret).toContain('列 9')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('改好之后：问题条与下划线一起消失（不留上一轮的残影）', async () => {
    control.stub = async () => [{ start: 7, end: 11, severity: 'error', message: '字符串没闭合' }]
    const mounted = await mountView()
    await type(mounted, "select 'abc")
    expect(mounted.wrapper.find('[data-testid="editor-problems"]').exists()).toBe(true)

    control.stub = async () => []
    await type(mounted, "select 'abc'")

    expect(mounted.wrapper.find('[data-testid="editor-problems"]').exists()).toBe(false)
    expect(mounted.wrapper.findAll('.db__tok--error').length).toBe(0)
    // 文本本身还在（高亮层不许因为诊断消失而丢字）
    expect(mounted.wrapper.find('.db__editor-highlight').text()).toBe("select 'abc'")

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('检查器失败时不崩、也不假装没问题：不列问题、编辑器照常显示原文', async () => {
    control.stub = async () => {
      throw new Error('检查器挂了')
    }
    const mounted = await mountView()
    const area = await type(mounted, 'select 1)')

    expect(mounted.wrapper.find('[data-testid="editor-problems"]').exists()).toBe(false)
    expect(mounted.wrapper.find('.db__editor-highlight').text()).toBe('select 1)')
    // 输入没被吞（写 SQL 不受检查器影响）
    expect(area.value).toBe('select 1)')

    mounted.restore()
    mounted.wrapper.unmount()
  })

  it('多条问题按位置从上到下列出（不是只有第一条）', async () => {
    control.stub = async () => [
      { start: 8, end: 9, severity: 'error', message: '多余的右括号 )' },
      { start: 12, end: 20, severity: 'error', message: '块注释没闭合' },
    ]
    const mounted = await mountView()
    await type(mounted, 'select 1)\n/* open')

    const rows = mounted.wrapper.findAll('.db__problem')
    expect(rows.length).toBe(2)
    expect(rows[0].text()).toContain('行 1')
    expect(rows[1].text()).toContain('行 2')

    mounted.restore()
    mounted.wrapper.unmount()
  })
})
