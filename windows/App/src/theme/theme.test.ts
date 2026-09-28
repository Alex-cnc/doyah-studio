import { describe, expect, it } from 'vitest'
import { applyTheme, colorVar, cssVar, kebab, normalizeTheme, readStoredTheme, storeTheme, THEME_STORAGE_KEY } from './index'

function fakeRoot() {
  const attributes = new Map<string, string>()
  return {
    attributes,
    setAttribute(name: string, value: string) {
      attributes.set(name, value)
    },
    removeAttribute(name: string) {
      attributes.delete(name)
    },
  }
}

describe('theme/令牌接线', () => {
  it('变量名拼法（与生成器的 numberVar / colorVar 同一套；产物级核对在 tests/tools.test.mjs）', () => {
    expect(kebab('rowHeight')).toBe('row-height')
    expect(cssVar('spacing', 'xs')).toBe('var(--ds-spacing-xs)')
    expect(cssVar('metric', 'rowHeight')).toBe('var(--ds-metric-row-height)')
    expect(colorVar('surface', 'content')).toBe('var(--ds-color-surface-content)')
  })

  it('档位：system 摘掉 data-theme（交给系统跟随），light/dark 显式写死', () => {
    const root = fakeRoot()
    applyTheme(root, 'dark')
    expect(root.attributes.get('data-theme')).toBe('dark')
    applyTheme(root, 'light')
    expect(root.attributes.get('data-theme')).toBe('light')
    applyTheme(root, 'system')
    expect(root.attributes.has('data-theme')).toBe(false)
  })

  it('非法取值归一到 system（不把脏值写进属性）', () => {
    expect(normalizeTheme('DARK')).toBe('system')
    expect(normalizeTheme(null)).toBe('system')
    expect(normalizeTheme('dark')).toBe('dark')
  })

  it('读写走同一个键', () => {
    const store = new Map<string, string>()
    const storage = {
      getItem: (key: string) => store.get(key) ?? null,
      setItem: (key: string, value: string) => void store.set(key, value),
    }
    expect(readStoredTheme(storage)).toBe('system')
    storeTheme(storage, 'light')
    expect(store.get(THEME_STORAGE_KEY)).toBe('light')
    expect(readStoredTheme(storage)).toBe('light')
  })
})
