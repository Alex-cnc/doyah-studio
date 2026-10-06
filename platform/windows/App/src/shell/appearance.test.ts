// 外观应用层 —— 行为判据（alpha 2.8）
//
// 守的两件事：
//   ① 跟随系统时**移除** `data-theme` 属性（而不是设成空串）—— 令牌层的"系统跟随"选择器
//      是 `:not([data-theme='light']):not([data-theme='dark'])`，属性存在但没值会让选择器产生歧义；
//   ② 星云皮肤只由**一个属性**控制（`data-nebula`），贴/揭都只有一处。

import { describe, expect, it } from 'vitest'
import { applyAppearance, MODE_LABELS, SCHEME_LABELS, systemIsDark } from './appearance'

/**
 * 假根元素：**不用真 DOM**（本仓的 vitest 环境是 node，没有 document）。
 * `applyAppearance` 只碰 `dataset`，所以给一个带 `dataset` 的普通对象就够 ——
 * 这也让这条判据跑得比 jsdom 快得多。
 */
function fakeRoot(): HTMLElement {
  return { dataset: {} as DOMStringMap } as unknown as HTMLElement
}

describe('把外观贴到根元素', () => {
  it('总是深色 ⇒ 设 data-theme=dark', () => {
    const root = fakeRoot()
    applyAppearance({ dataTheme: 'dark', dataScheme: 'stardust', nebula: true, isDark: true }, root)
    expect(root.dataset.theme).toBe('dark')
    expect(root.dataset.themeScheme).toBe('stardust')
    expect(root.dataset.nebula).toBe('on')
    expect(root.dataset.themeDark).toBe('true')
  })

  it('跟随系统 ⇒ **移除** data-theme（不是设空串）', () => {
    const root = fakeRoot()
    applyAppearance({ dataTheme: 'light', dataScheme: 'techBlue', nebula: false, isDark: false }, root)
    expect(root.dataset.theme).toBe('light')
    // 切回跟随系统
    applyAppearance({ dataTheme: null, dataScheme: 'techBlue', nebula: false, isDark: true }, root)
    expect('theme' in root.dataset).toBe(false)
    expect(root.dataset.themeScheme).toBe('techBlue')
    // 皮肤关掉 ⇒ 属性被移除（不是留一个 off）
    expect('nebula' in root.dataset).toBe(false)
  })

  it('皮肤开关与深浅是两件事（各自独立贴）', () => {
    const root = fakeRoot()
    // 深色但皮肤关
    applyAppearance({ dataTheme: 'dark', dataScheme: 'stardust', nebula: false, isDark: true }, root)
    expect(root.dataset.theme).toBe('dark')
    expect('nebula' in root.dataset).toBe(false)
    // 浅色但皮肤开（理论上领域层不会给这种组合，这里只验贴法互不影响）
    applyAppearance({ dataTheme: 'light', dataScheme: 'stardust', nebula: true, isDark: false }, root)
    expect(root.dataset.theme).toBe('light')
    expect(root.dataset.nebula).toBe('on')
  })
})

describe('界面下拉的取值与显示名', () => {
  it('四个配色都在，取值与令牌层一致', () => {
    expect(SCHEME_LABELS.map((s) => s.value)).toEqual(['techBlue', 'beanGreen', 'roseGold', 'stardust'])
    // 中文显示名（人类主人自己的叫法）
    expect(SCHEME_LABELS.find((s) => s.value === 'stardust')?.key).toBe('appearance.scheme.stardust')
    expect(SCHEME_LABELS.find((s) => s.value === 'techBlue')?.key).toBe('appearance.scheme.techBlue')
  })

  it('三档深浅都在（跟随系统在第一位）', () => {
    expect(MODE_LABELS.map((m) => m.value)).toEqual(['followSystem', 'alwaysDark', 'alwaysLight'])
    expect(MODE_LABELS[0].key).toBe('appearance.mode.followSystem')
  })

  it('拿不到 matchMedia 时按浅色处理（不抛错）', () => {
    // jsdom 里可能没有 matchMedia；这条只要求"不炸、给布尔"
    expect(typeof systemIsDark()).toBe('boolean')
  })
})
