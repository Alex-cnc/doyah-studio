// @vitest-environment happy-dom
// 外壳挂载冒烟 —— 外观面板的**字体面**（FR-EDIT-26）
//
// 为什么需要这一条：`tsc --noEmit` **不校验模板**（模板里引用了一个 setup 里不存在的名字，
// 编译期无声、运行时整段不渲染 —— 第 1 轮 queryTabs 就是这样漏过去的）。字体面这一片加的
// 正是模板（输入框 / 字号下拉 / 当前使用那句 / 预览行），只有真挂一次才能证明它接上了。
import { describe, expect, it, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import App from './App.vue'

async function mountShell() {
  const errors: string[] = []
  const warnings: string[] = []
  const errSpy = vi.spyOn(console, 'error').mockImplementation((...args: unknown[]) => {
    errors.push(args.map((a) => (a instanceof Error ? a.message : String(a))).join(' '))
  })
  const warnSpy = vi.spyOn(console, 'warn').mockImplementation((...args: unknown[]) => {
    warnings.push(args.map((a) => (a instanceof Error ? a.message : String(a))).join(' '))
  })
  const wrapper = mount(App, { attachTo: document.body })
  // 让 onMounted 里的取数（appInfo / 外观偏好 / 插件清单）异步收尾
  await new Promise((resolve) => setTimeout(resolve, 0))
  await wrapper.vm.$nextTick()
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

describe('外壳外观面板 · 字体面', () => {
  it('挂载后字体输入框 / 字号下拉 / 当前使用那句 / 预览行都在，且挂载期无 console.error', async () => {
    const { wrapper, errors, warnings, restore } = await mountShell()
    try {
      const input = wrapper.find('[data-testid="font-family-input"]')
      expect(input.exists()).toBe(true)
      expect(input.attributes('list')).toBe('ds-font-choices')
      // 候选族名通过 datalist 提供（用户不必记得族名怎么写）
      expect(wrapper.findAll('#ds-font-choices option').length).toBeGreaterThan(3)

      const size = wrapper.find('[data-testid="font-size"]')
      expect(size.exists()).toBe(true)
      // 12 档 9~20，且当前值落在里面（不然下拉显示为空白）
      expect(wrapper.findAll('[data-testid="font-size"] option')).toHaveLength(12)
      expect(Number((size.element as HTMLSelectElement).value)).toBeGreaterThanOrEqual(9)

      // 「当前使用」那句必须有内容 —— 它正是"到底生效了没有"的唯一人眼出口
      const status = wrapper.find('[data-testid="font-status"]')
      expect(status.exists()).toBe(true)
      expect(status.text().length).toBeGreaterThan(0)

      expect(wrapper.find('.appearance__font-preview').exists()).toBe(true)
      expect(errors).toEqual([])
      // 模板引用了未定义的名字会走 console.warn —— 那正是要抓的那种漏
      expect(warnings.filter((w) => /is not defined|was accessed during render/.test(w))).toEqual([])
    } finally {
      restore()
      wrapper.unmount()
    }
  })

  it('输入族名后点「应用」⇒ 走一次外观写回（空串 = 回到系统等宽）', async () => {
    const { wrapper, restore } = await mountShell()
    try {
      const input = wrapper.find('[data-testid="font-family-input"]')
      await input.setValue('Consolas')
      await wrapper.find('[data-testid="font-apply"]').trigger('click')
      await new Promise((resolve) => setTimeout(resolve, 0))
      await wrapper.vm.$nextTick()
      // 写回成功后输入框里仍是用户输入的那一份（浏览器旁路不落盘，但界面口径要对）
      expect((wrapper.find('[data-testid="font-family-input"]').element as HTMLInputElement).value).toBe(
        'Consolas',
      )
      // 清空后再应用 ⇒ 回到系统等宽（输入框空、状态行说「系统等宽」）
      await wrapper.find('[data-testid="font-family-input"]').setValue('')
      await wrapper.find('[data-testid="font-apply"]').trigger('click')
      await new Promise((resolve) => setTimeout(resolve, 0))
      await wrapper.vm.$nextTick()
      expect((wrapper.find('[data-testid="font-family-input"]').element as HTMLInputElement).value).toBe('')
    } finally {
      restore()
      wrapper.unmount()
    }
  })
})
