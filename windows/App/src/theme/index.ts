// 设计令牌的 TS 侧入口（windows/App/src/theme/index.ts）
//
// 取值本身**不在这里**：它在 `tokens.generated.css`（由 `tools/gen-tokens.mjs` 从 macOS 侧
// `Core/DesignTokens.swift` 生成 —— 令牌取值的单一来源）。这个文件只做两件事：
//   1. 把「变量名怎么拼」收成一个函数（免得各处手写字符串拼错）；
//   2. 主题档位的读写（system / light / dark）。
//
// 变量名规则与生成器 `numberVar` / `colorVar` 必须一致 —— 由 `src/theme/theme.test.ts`
// 读生成物逐名断言（拼法变了就判红，不会静默变成「样式没生效」）。

export type ThemeMode = 'system' | 'light' | 'dark'

export const THEME_STORAGE_KEY = 'doyah-studio.windows.theme'

/** camelCase → kebab-case（生成器对数值类令牌用的同一套拼法）。 */
export function kebab(name: string): string {
  return name.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)
}

/** 数值 / 尺寸类令牌：`cssVar('spacing', 'xs')` → `var(--ds-spacing-xs)`。 */
export function cssVar(group: string, name: string): string {
  return `var(--ds-${group}-${kebab(name)})`
}

/** 颜色令牌：`colorVar('surface', 'content')` → `var(--ds-color-surface-content)`。 */
export function colorVar(group: string, name: string): string {
  return `var(--ds-color-${group}-${name})`
}

export function normalizeTheme(value: string | null | undefined): ThemeMode {
  return value === 'light' || value === 'dark' || value === 'system' ? value : 'system'
}

export function readStoredTheme(storage: { getItem(key: string): string | null }): ThemeMode {
  return normalizeTheme(storage.getItem(THEME_STORAGE_KEY))
}

export function storeTheme(storage: { setItem(key: string, value: string): void }, mode: ThemeMode): void {
  storage.setItem(THEME_STORAGE_KEY, mode)
}

/** 只需要这两个方法 —— 这样单测里传个桩就行，不必把 jsdom 拖进来。 */
export interface ThemeRoot {
  setAttribute(name: string, value: string): void
  removeAttribute(name: string): void
}

/**
 * 把档位落到根元素：
 * - `system` → **摘掉** `data-theme`（交给 CSS 的 `@media (prefers-color-scheme: dark)`，
 *   系统跟随由生成物那条 `:root:not([data-theme])` 规则兜住）；
 * - `light` / `dark` → 显式写死（显式选择优先于系统，口径与 macOS 侧一致）。
 */
export function applyTheme(root: ThemeRoot, mode: ThemeMode): void {
  if (mode === 'system') root.removeAttribute('data-theme')
  else root.setAttribute('data-theme', mode)
}

// ── 配色方案（主题集；§9.2 / §9.4「候选同名同值」）───────────────────────────
//
// 主题集的 **id / 默认主题 / 是否「推导草案」** 全部来自生成物 `themes.generated.ts`
// （由 `tools/gen-tokens.mjs` 从 macOS 侧 `Core/DesignTheme.swift` 解析 —— 本侧不手抄，
// 对侧改名 / 增删主题 / 判定式换写法 / 值到位后不再是推导草案，这边 `--check` 就判红、
// 跑一次生成即跟上）。
// 这里只补两样生成物给不出的东西：**属性名**与**中文显示名**（显示名与 macOS 侧同口径：
// 科技蓝 / 星空紫 / 豆芽绿 / 玫瑰金；新增主题没配显示名 ⇒ `theme.test.ts` 判红，不会静默显示成 id）。

import { THEME_SCHEMES, type ThemeSchemeId } from './themes.generated'

export { THEME_SCHEMES, type ThemeSchemeId }
export const SCHEME_ATTRIBUTE = 'data-theme-scheme'
export const THEME_SCHEME_STORAGE_KEY = 'doyah-studio.windows.theme-scheme'

/** 主题 id → 显示名（与 macOS 文案同名；`theme.test.ts` 保证「生成物里每个主题都有名字」）。 */
export const THEME_SCHEME_LABELS: Record<string, string> = {
  'tech-blue': '科技蓝',
  'bean-green': '豆芽绿',
  'rose-gold': '玫瑰金',
  stardust: '星空紫',
}

/**
 * 非法 / 未知取值归一到默认主题（与 macOS 侧「未知 id 一律回退、不报错」同口径）：
 * 配置文件被手改、或将来删掉某个主题时，界面都必须照常起来。
 */
export function normalizeScheme(value: string | null | undefined): string {
  return THEME_SCHEMES.some((scheme) => scheme.id === value) ? (value as string) : DEFAULT_SCHEME
}

export function readStoredScheme(storage: { getItem(key: string): string | null }): string {
  return normalizeScheme(storage.getItem(THEME_SCHEME_STORAGE_KEY))
}

export function storeScheme(storage: { setItem(key: string, value: string): void }, scheme: string): void {
  storage.setItem(THEME_SCHEME_STORAGE_KEY, normalizeScheme(scheme))
}

/** 把主题落到根元素：`data-theme-scheme` 的取值必须是 `rawValue`（生成物里的 id，不是 Swift case 名）。 */
export function applyScheme(root: ThemeRoot, scheme: string): void {
  root.setAttribute(SCHEME_ATTRIBUTE, normalizeScheme(scheme))
}

/** 默认主题：生成物标着 `fallback: true` 的那一个（找不到就退第一个，保证一定有值）。 */
export const DEFAULT_SCHEME: string = (THEME_SCHEMES.find((scheme) => scheme.fallback) ?? THEME_SCHEMES[0]).id
