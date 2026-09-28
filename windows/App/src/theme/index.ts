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
