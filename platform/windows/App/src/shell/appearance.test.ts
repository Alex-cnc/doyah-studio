// 外观应用层 —— 行为判据（alpha 2.8 / FR-EDIT-26 字体面）
//
// 守的三件事：
//   ① 跟随系统时**移除** `data-theme` 属性（而不是设成空串）—— 令牌层的"系统跟随"选择器
//      是 `:not([data-theme='light']):not([data-theme='dark'])`，属性存在但没值会让选择器产生歧义；
//   ② 星云皮肤只由**一个属性**控制（`data-nebula`），贴/揭都只有一处；
//   ③ 字体面只贴**两个自定义属性**，值是领域层算好的整条 CSS —— 前端一旦自己拼字符串，
//      迟早就出现"界面拼的栈"与"Rust 算的栈"两套（中文族名、引号、回落顺序先分叉）。

import { describe, expect, it } from 'vitest'
import type { DomAppearance } from '../ipc'
import {
  applyAppearance,
  applyEditorFontVars,
  FONT_CHOICES,
  FONT_SIZE_CHOICES,
  MODE_LABELS,
  SCHEME_LABELS,
  systemIsDark,
} from './appearance'

/** 假根元素：**不用真 DOM**（本仓的 vitest 环境是 node，没有 document）。 */
function fakeRoot(): HTMLElement {
  return { dataset: {} as DOMStringMap } as unknown as HTMLElement
}

/** 带 `style.setProperty` 的假根元素（字体面要看它贴了什么）。 */
function fakeRootWithStyle(): { root: HTMLElement; vars: Record<string, string> } {
  const vars: Record<string, string> = {}
  const root = {
    dataset: {} as DOMStringMap,
    style: {
      setProperty: (name: string, value: string) => {
        vars[name] = value
      },
    },
  } as unknown as HTMLElement
  return { root, vars }
}

/** 一份完整的 DOM 回包（字体面用缺省，用例按需覆盖）。 */
function domPayload(patch: Partial<DomAppearance> = {}): DomAppearance {
  return {
    dataTheme: null,
    dataScheme: 'stardust',
    nebula: false,
    isDark: false,
    editorFamilyCss: 'var(--ds-font-stack-mono)',
    editorSizeCss: '13px',
    ...patch,
  }
}

describe('把外观贴到根元素', () => {
  it('总是深色 ⇒ 设 data-theme=dark', () => {
    const root = fakeRoot()
    applyAppearance(domPayload({ dataTheme: 'dark', dataScheme: 'stardust', nebula: true, isDark: true }), root)
    expect(root.dataset.theme).toBe('dark')
    expect(root.dataset.themeScheme).toBe('stardust')
    expect(root.dataset.nebula).toBe('on')
    expect(root.dataset.themeDark).toBe('true')
  })

  it('跟随系统 ⇒ **移除** data-theme（不是设空串）', () => {
    const root = fakeRoot()
    applyAppearance(domPayload({ dataTheme: 'light', dataScheme: 'techBlue' }), root)
    expect(root.dataset.theme).toBe('light')
    // 切回跟随系统
    applyAppearance(domPayload({ dataTheme: null, dataScheme: 'techBlue', isDark: true }), root)
    expect('theme' in root.dataset).toBe(false)
    expect(root.dataset.themeScheme).toBe('techBlue')
    // 皮肤关掉 ⇒ 属性被移除（不是留一个 off）
    expect('nebula' in root.dataset).toBe(false)
  })

  it('皮肤开关与深浅是两件事（各自独立贴）', () => {
    const root = fakeRoot()
    // 深色但皮肤关
    applyAppearance(domPayload({ dataTheme: 'dark', dataScheme: 'stardust', nebula: false, isDark: true }), root)
    expect(root.dataset.theme).toBe('dark')
    expect('nebula' in root.dataset).toBe(false)
    // 浅色但皮肤开（理论上领域层不会给这种组合，这里只验贴法互不影响）
    applyAppearance(domPayload({ dataTheme: 'light', dataScheme: 'stardust', nebula: true }), root)
    expect(root.dataset.theme).toBe('light')
    expect(root.dataset.nebula).toBe('on')
  })

  it('字体面贴成两个自定义属性（值就是领域层给的那一条，不在此处拼接）', () => {
    const { root, vars } = fakeRootWithStyle()
    applyAppearance(
      domPayload({
        editorFamilyCss: '"JetBrains Mono", var(--ds-font-stack-mono)',
        editorSizeCss: '15px',
      }),
      root,
    )
    expect(vars['--ds-editor-font-family']).toBe('"JetBrains Mono", var(--ds-font-stack-mono)')
    expect(vars['--ds-editor-font-size']).toBe('15px')
  })

  it('只改字体（不重算主题）也走同一条贴法', () => {
    const { root, vars } = fakeRootWithStyle()
    applyEditorFontVars({ editorFamilyCss: 'var(--ds-font-stack-mono)', editorSizeCss: '9px' }, root)
    expect(vars['--ds-editor-font-size']).toBe('9px')
    expect(vars['--ds-editor-font-family']).toBe('var(--ds-font-stack-mono)')
  })

  it('根元素没有 style 时静默跳过（不为了一个 DOM 细节让外观整体失败）', () => {
    const root = fakeRoot()
    expect(() => applyAppearance(domPayload({ isDark: true }), root)).not.toThrow()
    expect(root.dataset.themeDark).toBe('true')
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

  it('字号档位与领域层的夹取范围同口径（9~20，共 12 档）', () => {
    expect(FONT_SIZE_CHOICES[0]).toBe(9)
    expect(FONT_SIZE_CHOICES[FONT_SIZE_CHOICES.length - 1]).toBe(20)
    expect(FONT_SIZE_CHOICES).toHaveLength(12)
    expect(FONT_SIZE_CHOICES).toContain(13)
  })

  it('候选族名都是等宽族（含一个中文字族，别只给拉丁看）', () => {
    expect(FONT_CHOICES).toContain('Cascadia Mono')
    expect(FONT_CHOICES).toContain('Consolas')
    expect(FONT_CHOICES.some((f) => /[\u4e00-\u9fa5]/.test(f))).toBe(true)
  })

  it('拿不到 matchMedia 时按浅色处理（不抛错）', () => {
    // jsdom 里可能没有 matchMedia；这条只要求"不炸、给布尔"
    expect(typeof systemIsDark()).toBe('boolean')
  })
})
