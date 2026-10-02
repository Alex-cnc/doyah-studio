// 外观的**应用层**（2.8）：把 Rust 算好的 `data-*` 落到根元素，并管星云皮肤的开关
//
// 分工（**规则只有一份**）：
//   · 规则（三态怎么解、未知值怎么回落、皮肤三个条件）全在 Rust 领域层 `Db/src/appearance.rs`
//     （7 例单测）；本文件**不重写任何规则**，只负责"把结果贴到 DOM 上"。
//   · 为什么贴 DOM 而不是给每个组件传参：令牌层是**属性选择器**驱动的
//     （`:root[data-theme='dark']` / `:root[data-theme-scheme='…']`），
//     贴一次属性，全树自动换色 —— 这也保证"编辑面底色与字色**只走主题令牌**"。

/** 落盘偏好（与 Rust 侧 `Appearance` 同形）。 */
export interface Appearance {
  mode: 'followSystem' | 'alwaysDark' | 'alwaysLight'
  scheme: 'techBlue' | 'beanGreen' | 'roseGold' | 'stardust'
  /** 星云皮肤开关；**缺省开** */
  nebulaSkin: boolean
}

/** Rust 算好的 DOM 取值（`dataTheme` 为 `null` = **不设那个属性**）。 */
export interface DomAppearance {
  dataTheme: 'dark' | 'light' | null
  dataScheme: string
  nebula: boolean
  isDark: boolean
}

export interface AppearancePayload {
  appearance: Appearance
  dom: DomAppearance
  warning?: string | null
}

/** 系统当前是不是深色（跟随系统那一档要用）。 */
export function systemIsDark(): boolean {
  if (typeof window === 'undefined' || !window.matchMedia) return false
  return window.matchMedia('(prefers-color-scheme: dark)').matches
}

/**
 * 把外观贴到根元素上。
 *
 * `dataTheme` 为 `null` ⇒ **移除这个属性**（而不是设成空串）：令牌层里"跟随系统"那段是
 * `:root:not([data-theme='light']):not([data-theme='dark'])`，设成空串虽然也能命中，
 * 但"属性存在但没值"会让别的选择器（含将来新增的）产生歧义。
 */
export function applyAppearance(dom: DomAppearance, root: HTMLElement | null = null): void {
  const target = root ?? (typeof document === 'undefined' ? null : document.documentElement)
  if (!target) return
  const dataset = target.dataset
  if (dom.dataTheme === null) {
    delete dataset.theme
  } else {
    dataset.theme = dom.dataTheme
  }
  dataset.themeScheme = dom.dataScheme
  // 星云皮肤只用一个属性控制（样式里按它显示/隐藏背景层）
  if (dom.nebula) {
    dataset.nebula = 'on'
  } else {
    delete dataset.nebula
  }
  // 深浅也写成属性，方便组件按需取（**不用它换色** —— 换色一律走令牌）
  dataset.themeDark = dom.isDark ? 'true' : 'false'
}

/** 配色轴的中文名（界面下拉用；技术取值不进语言表，这里只是显示名）。 */
export const SCHEME_LABELS: { value: Appearance['scheme']; label: string }[] = [
  { value: 'techBlue', label: '科技蓝' },
  { value: 'beanGreen', label: '豆芽绿' },
  { value: 'roseGold', label: '玫瑰金' },
  { value: 'stardust', label: '星空紫' },
]

/** 深浅轴的中文名。 */
export const MODE_LABELS: { value: Appearance['mode']; label: string }[] = [
  { value: 'followSystem', label: '跟随系统' },
  { value: 'alwaysDark', label: '总是深色' },
  { value: 'alwaysLight', label: '总是浅色' },
]
