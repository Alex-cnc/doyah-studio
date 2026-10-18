// 外观的**应用层**（2.8）：把 Rust 算好的 `data-*` 落到根元素，并管星云皮肤的开关
//
// 分工（**规则只有一份**）：
//   · 规则（三态怎么解、未知值怎么回落、皮肤三个条件）全在 Rust 领域层 `Db/src/appearance.rs`
//     （7 例单测）；本文件**不重写任何规则**，只负责"把结果贴到 DOM 上"。
//   · 为什么贴 DOM 而不是给每个组件传参：令牌层是**属性选择器**驱动的
//     （`:root[data-theme='dark']` / `:root[data-theme-scheme='…']`），
//     贴一次属性，全树自动换色 —— 这也保证"编辑面底色与字色**只走主题令牌**"。

// 类型**只有一份**，在 IPC 面（`src/ipc.ts`）：这里原来抄了一份同形声明，加了字体字段之后
// 立刻分叉（tsc 当场报「DomAppearance 缺 editorFamilyCss」）—— 抄写型重复迟早漂，改成再导出。
export type { Appearance, AppearancePayload, DomAppearance } from '../ipc'

import type { Appearance, DomAppearance } from '../ipc'

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
  // 字体面（FR-EDIT-26）：编辑器那两层（高亮层 + textarea）读的就是这两个自定义属性，
  // **整条 CSS 由领域层算好**（族名清洗、等宽回落栈都在 Rust 侧），这里只负责贴上去。
  // 贴到根元素而不是组件上：高亮层与 textarea 是**两个**节点，贴一次两边同时变，
  // 不会出现"换了字号、字与光标错位"那种经典坑。
  applyEditorFontVars(dom, target)
}

/**
 * 贴字体自定义属性（单独一个函数：`applyAppearance` 与「只改字体不重算主题」两条路都用它）。
 *
 * `target` 上没有 `style`（本仓 vitest 的假根元素）时**静默跳过** —— 不让判据为了一个
 * DOM 细节去假造一整个 `style` 对象；真浏览器里 `style` 一定在。
 */
export function applyEditorFontVars(
  dom: Pick<DomAppearance, 'editorFamilyCss' | 'editorSizeCss'>,
  target: HTMLElement | null = null,
): void {
  const node = target ?? (typeof document === 'undefined' ? null : document.documentElement)
  const style = node?.style
  if (!style || typeof style.setProperty !== 'function') return
  style.setProperty('--ds-editor-font-family', dom.editorFamilyCss)
  style.setProperty('--ds-editor-font-size', dom.editorSizeCss)
}

/**
 * 常见的**等宽**族（下拉候选；用户也能手输）。
 *
 * 放候选里不是"我们认为这些一定装了" —— 「装没装」由 `editorFont.ts` 实测字宽判，
 * 判出没装就如实提示并回落。这里只解决"用户不知道该输什么名字"。
 */
export const FONT_CHOICES: string[] = [
  'Cascadia Code',
  'Cascadia Mono',
  'Consolas',
  'Courier New',
  'JetBrains Mono',
  'Fira Code',
  'Source Code Pro',
  '更纱黑体 SC',
  'Noto Sans Mono CJK SC',
]

/** 字号档位（与领域层 9~20 的夹取范围同一口径）。 */
export const FONT_SIZE_CHOICES: number[] = Array.from({ length: 12 }, (_, i) => 9 + i)

/** 配色轴的中文名（界面下拉用；技术取值不进语言表，这里只是显示名）。 */
/**
 * 四个配色。
 *
 * **`value` 是稳定标识**（进令牌选择器与落盘偏好），**`key` 才是给用户看的文案** ——
 * 原来这里直接写中文，切英文时下拉里仍是中文（扫描器第三面就是为这类"数据型文案"补的）。
 */
export const SCHEME_LABELS: { value: Appearance['scheme']; key: string }[] = [
  { value: 'techBlue', key: 'appearance.scheme.techBlue' },
  { value: 'beanGreen', key: 'appearance.scheme.beanGreen' },
  { value: 'roseGold', key: 'appearance.scheme.roseGold' },
  { value: 'stardust', key: 'appearance.scheme.stardust' },
]

/** 深浅轴的中文名。 */
/** 三档深浅（`value` 稳定标识，`key` 是文案 —— 与配色同一口径）。 */
export const MODE_LABELS: { value: Appearance['mode']; key: string }[] = [
  { value: 'followSystem', key: 'appearance.mode.followSystem' },
  { value: 'alwaysDark', key: 'appearance.mode.alwaysDark' },
  { value: 'alwaysLight', key: 'appearance.mode.alwaysLight' },
]
