// @vitest-environment happy-dom
// 分隔条接线判据（FR-EDIT-13 · 2026-10-18 · 第 6 轮）
//
// 为什么必须真挂载：`splitPane.ts` 的夹紧再正确，也证明不了「拖这条线真的会改编辑区高度」——
// 断的地方永远是接线（模板上没绑 style / 事件没挂 window / 每次 keyup 把高度打回自动）。
// happy-dom 不做布局，所以**尺寸由本文件喂**（容器 600、编辑区 200），断言的是
// 「组件拿这些尺寸算出了什么、写回了什么」，而不是浏览器排版结果。
import { describe, expect, it, vi } from 'vitest'
import { nextTick } from 'vue'
import { mount } from '@vue/test-utils'
import DatabaseView from './DatabaseView.vue'

type Rect = { height: number }

/** 给一个元素装上固定高度（只实现被测代码用到的那个字段）。 */
function stubHeight(el: HTMLElement, height: number) {
  Object.defineProperty(el, 'getBoundingClientRect', {
    configurable: true,
    value: (): Partial<DOMRect> => ({ height, width: 800, top: 0, bottom: height, left: 0, right: 800, x: 0, y: 0 }),
  })
}

async function settle() {
  await nextTick()
  await nextTick()
  await new Promise((resolve) => setTimeout(resolve, 0))
}

async function mountView() {
  const errors: string[] = []
  const errSpy = vi.spyOn(console, 'error').mockImplementation((...args: unknown[]) => {
    errors.push(args.map((a) => (a instanceof Error ? a.message : String(a))).join(' '))
  })
  const wrapper = mount(DatabaseView, { attachTo: document.body })
  await settle()
  const container = wrapper.find('.db__main').element as HTMLElement
  const area = wrapper.find('.db__editor textarea').element as HTMLTextAreaElement
  const split = wrapper.find('[data-testid="db-split"]').element as HTMLElement
  stubHeight(container, 600)
  stubHeight(area, 200)
  return {
    wrapper,
    container,
    area,
    split,
    errors,
    reset: () => errSpy.mockRestore(),
  }
}

type Mounted = Awaited<ReturnType<typeof mountView>>

async function pointerDown(m: Mounted, clientY: number, button = 0) {
  m.split.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true, cancelable: true, button, clientY }))
  await settle()
}

async function pointerMove(clientY: number) {
  window.dispatchEvent(new MouseEvent('pointermove', { bubbles: true, clientY }))
  await settle()
}

async function pointerUp(clientY: number) {
  window.dispatchEvent(new MouseEvent('pointerup', { bubbles: true, clientY }))
  await settle()
}

async function pressKey(m: Mounted, key: string) {
  m.split.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }))
  await settle()
}

describe('分隔条（FR-EDIT-13：编辑区 ↔ 结果区）', () => {
  it('初始态是自动高度：编辑区不写 inline 高度（不改现有默认观感），条上给出可读提示', async () => {
    const m = await mountView()

    // 否定面：没拖过就不许有 inline 高度 —— 否则「接线前后观感一致」这条承诺就是假的
    expect(m.area.style.height).toBe('')
    expect(m.split.getAttribute('role')).toBe('separator')
    expect(m.split.getAttribute('aria-orientation')).toBe('horizontal')
    expect(m.split.getAttribute('aria-valuemin')).toBe('120')
    // 自动态不给 aria-valuenow（没有「当前值」这回事）
    expect(m.split.getAttribute('aria-valuenow')).toBeNull()
    // 提示里三件事都写着：拖动 / ↑↓ / 双击复位
    expect(m.split.getAttribute('title')).toContain('拖动')
    expect(m.split.getAttribute('title')).toContain('↑↓')
    expect(m.split.getAttribute('title')).toContain('双击')

    m.reset()
    m.wrapper.unmount()
  })

  it('拖动实时改编辑区高度（下拖 40px ⇒ 200 → 240），并且拖完不再跟指针', async () => {
    const m = await mountView()

    await pointerDown(m, 300)
    await pointerMove(340)
    expect(m.area.style.height).toBe('240px')
    expect(m.split.getAttribute('aria-valuenow')).toBe('240')

    await pointerUp(340)
    // 抬手后再动鼠标不该继续改（否则光标一动编辑器就自己长）
    await pointerMove(500)
    expect(m.area.style.height).toBe('240px')

    m.reset()
    m.wrapper.unmount()
  })

  it('上下限夹紧：拖到屏幕外 ⇒ 120 / 480（结果区始终留 120）', async () => {
    const m = await mountView()

    await pointerDown(m, 300)
    await pointerMove(-2000) // 往上拖过头
    expect(m.area.style.height).toBe('120px')

    await pointerUp(-2000)
    await pointerDown(m, 300)
    await pointerMove(5000) // 往下拖过头（上限 = 600 - 120 = 480）
    expect(m.area.style.height).toBe('480px')

    m.reset()
    m.wrapper.unmount()
  })

  it('键盘 ↑↓ 步进 16px（焦点在条上时；并遵守同一夹紧）', async () => {
    const m = await mountView()

    await pointerDown(m, 300)
    await pointerMove(340) // 停在 240
    await pointerUp(340)

    await pressKey(m, 'ArrowDown')
    expect(m.area.style.height).toBe('256px')
    await pressKey(m, 'ArrowUp')
    expect(m.area.style.height).toBe('240px')

    // 到顶后再按 ↓ 不回卷（夹紧而不是环绕）
    await pointerDown(m, 400)
    await pointerMove(5000)
    await pointerUp(5000)
    expect(m.area.style.height).toBe('480px')
    await pressKey(m, 'ArrowDown')
    expect(m.area.style.height).toBe('480px')

    m.reset()
    m.wrapper.unmount()
  })

  it('双击复位：回到自动高度（inline style 被清掉）', async () => {
    const m = await mountView()

    await pointerDown(m, 300)
    await pointerMove(360)
    expect(m.area.style.height).toBe('260px')

    await pointerUp(360)
    m.split.dispatchEvent(new MouseEvent('dblclick', { bubbles: true, cancelable: true }))
    await settle()
    expect(m.area.style.height).toBe('')

    // 复位后键盘仍可用：从量到的自动高度（200）再步进
    await pressKey(m, 'ArrowDown')
    expect(m.area.style.height).toBe('216px')

    m.reset()
    m.wrapper.unmount()
  })

  it('右鍵按下不开始拖动（不许用右键/中键把编辑区拽走）', async () => {
    const m = await mountView()

    await pointerDown(m, 300, 2)
    await pointerMove(400)
    expect(m.area.style.height).toBe('')

    m.reset()
    m.wrapper.unmount()
  })
})
