// @vitest-environment happy-dom
// DatabaseView 挂载冒烟 —— 2026-10-07「模板引用了未定义的 queryTabs ⇒ 查询页签条整段不渲染 +
// 渲染期读 undefined.length」的回归判据（W-A-1）。
//
// 为什么必须有这一条：既有两道网都漏 —— `tsc --noEmit` **不校验**模板（模板里引用的属性不在实例上，
// 编译期无声）；既有 vitest 用例是**纯逻辑**（不挂载组件）⇒ 渲染期的
// `Property "queryTabs" was accessed during render but is not defined on instance` 只有真挂一次才会现形。
// 沿用 W-A-0 的 happy-dom 姿态（`@vue/test-utils` + 浏览器旁路 mock）。
import { describe, expect, it, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import DatabaseView from './DatabaseView.vue'

/** 挂载并收全挂载期的 console.error / console.warn（改前 queryTabs 那条就走 console.warn）。 */
async function mountCapturing() {
  const errors: string[] = []
  const warnings: string[] = []
  const errSpy = vi.spyOn(console, 'error').mockImplementation((...args: unknown[]) => {
    errors.push(args.map((a) => (a instanceof Error ? a.message : String(a))).join(' '))
  })
  const warnSpy = vi.spyOn(console, 'warn').mockImplementation((...args: unknown[]) => {
    warnings.push(args.map((a) => (a instanceof Error ? a.message : String(a))).join(' '))
  })
  const wrapper = mount(DatabaseView)
  await new Promise((resolve) => setTimeout(resolve, 0)) // 让 setup 里的 mock 取数异步收尾
  return {
    wrapper,
    errors,
    warnings,
    restore: () => {
      errSpy.mockRestore()
      warnSpy.mockRestore()
    },
  }
}

describe('DatabaseView 挂载冒烟（查询页签条）', () => {
  it('挂载后无 console.error、无「queryTabs … is not defined」警告，页签条渲染出「查询 1」+ 加号', async () => {
    const { wrapper, errors, warnings, restore } = await mountCapturing()

    // ① 挂载期不许有 console.error
    expect(errors).toEqual([])
    // ② 不许有「属性未在实例上定义」这条渲染期 Warning（改前：queryTabs ×4）
    expect(warnings.filter((w) => w.includes('is not defined on instance'))).toEqual([])

    // ③ 页签条真渲染了：一张「查询 1」页签 + 加号按钮
    const tabs = wrapper.findAll('.db__qtab')
    expect(tabs.length).toBe(1)
    expect(tabs[0].text()).toContain('查询 1')
    expect(wrapper.find('.db__qtab-add').exists()).toBe(true)

    // ④ `queryTabs.length <= 1` 那句没抛：最后一张的关闭按钮被置灰、并给出「不许关」的 title
    const closeBtn = wrapper.find('.db__qtab-close')
    expect(closeBtn.exists()).toBe(true)
    expect(closeBtn.attributes('disabled')).toBeDefined()
    expect(closeBtn.attributes('title')).toContain('最后一个页签不能关')

    restore()
    wrapper.unmount()
  })

  it('加号能新建页签且编号不复用；两张时关闭按钮可用（走通 newQueryTab / closeQueryTab）', async () => {
    const { wrapper, errors, restore } = await mountCapturing()

    // 加号：新建「查询 2」并选中
    await wrapper.find('.db__qtab-add').trigger('click')
    let tabs = wrapper.findAll('.db__qtab')
    expect(tabs.length).toBe(2)
    expect(tabs[1].text()).toContain('查询 2')
    expect(tabs[1].classes()).toContain('db__qtab--active')
    // 两张页签后关闭按钮可用（queryTabs.length <= 1 为假，disabled 不渲染）
    expect(tabs[1].find('.db__qtab-close').attributes('disabled')).toBeUndefined()

    // 关掉「查询 2」→ 回到一张；再新建应是「查询 3」（编号不复用）
    await tabs[1].find('.db__qtab-close').trigger('click')
    expect(wrapper.findAll('.db__qtab').length).toBe(1)
    await wrapper.find('.db__qtab-add').trigger('click')
    tabs = wrapper.findAll('.db__qtab')
    expect(tabs.length).toBe(2)
    expect(tabs[1].text()).toContain('查询 3')

    // 这一串交互也不许把错/警告打进控制台
    expect(errors).toEqual([])
    restore()
    wrapper.unmount()
  })
})
