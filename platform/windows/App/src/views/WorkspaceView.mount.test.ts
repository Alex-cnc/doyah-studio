// @vitest-environment happy-dom
// WorkspaceView 挂载冒烟 —— 2026-10-07「工作区视图 setup 期 TDZ ⇒ 主区整屏空白」的回归判据。
//
// 为什么必须有这一条：既有两道网都漏 —— `tsc --noEmit` **不校验** setup 顶层语句里的 TDZ
// （把「同步根给外壳」的那句 watch 写在 `root` 的 ref 声明之前，就是同文件内的未初始化访问），
// 既有 vitest 用例是**纯逻辑**（不挂载组件）⇒ setup 期抛错没人发现，只有真挂一次才炸。
import { describe, expect, it, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import WorkspaceView from './WorkspaceView.vue'

describe('WorkspaceView 挂载冒烟（浏览器旁路 mock）', () => {
  it('挂得上并渲染出工具条与空态：无 console.error、根节点非空、文件夹输入框在、空态文案在', async () => {
    const errors: string[] = []
    const spy = vi.spyOn(console, 'error').mockImplementation((...args: unknown[]) => {
      errors.push(args.map((a) => (a instanceof Error ? a.message : String(a))).join(' '))
    })

    const wrapper = mount(WorkspaceView, { props: { version: '0.0.0-test' } })
    await new Promise((resolve) => setTimeout(resolve, 0)) // 让 setup 里的 mock 取数异步收尾

    // ① 挂载期不许有 console.error（setup 抛 TDZ 时 Vue 会把错误记到 console.error）
    expect(errors).toEqual([])
    // ② 根节点非空（改前 Vue 用空注释占位 ⇒ 整屏什么都没有）
    expect(wrapper.element).toBeTruthy()
    expect(wrapper.html().length).toBeGreaterThan(0)
    // ③ 工具条「文件夹」输入框在
    expect(wrapper.text()).toContain('文件夹')
    expect(wrapper.find('.ws__field input').exists()).toBe(true)
    // ④ 空态文案在（还没打开工作区）
    expect(wrapper.find('.ws__empty').text()).toContain('未打开工作区')

    spy.mockRestore()
    wrapper.unmount()
  })
})
