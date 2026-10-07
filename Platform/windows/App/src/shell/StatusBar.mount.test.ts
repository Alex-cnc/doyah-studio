// @vitest-environment happy-dom
// StatusBar 挂载冒烟 —— 2026-10-07「状态栏渲染期 TypeError ⇒ 整条状态栏不渲染」的回归判据。
//
// 守的口径：`rows` / `cols` 是**可缺省**的（没传时必须按 0 兜底），
// 而不是把模板里的读数删掉 —— 删掉读数只是把错藏起来（状态栏少两段信息）。
import { describe, expect, it, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import StatusBar from './StatusBar.vue'

describe('StatusBar 挂载冒烟', () => {
  it('不传 rows / cols 也能渲染出来、不抛（缺省兜底 0）', () => {
    const errors: string[] = []
    const spy = vi.spyOn(console, 'error').mockImplementation((...args: unknown[]) => {
      errors.push(args.map((a) => (a instanceof Error ? a.message : String(a))).join(' '))
    })

    const wrapper = mount(StatusBar, { props: { info: null, loaded: 0, total: 0 } })

    expect(errors).toEqual([])
    expect(wrapper.find('.statusbar').exists()).toBe(true)
    // 读数仍在（没有被"删掉了事"）：结果集 0 行 × 0 列
    expect(wrapper.text()).toContain('0 行')
    expect(wrapper.text()).toContain('0 列')

    spy.mockRestore()
    wrapper.unmount()
  })

  it('传了 rows / cols 时如实显示（不写死 0）', () => {
    const wrapper = mount(StatusBar, { props: { info: null, rows: 200000, cols: 20, loaded: 38, total: 200000 } })
    expect(wrapper.text()).toContain('200,000 行')
    expect(wrapper.text()).toContain('20 列')
    wrapper.unmount()
  })
})
