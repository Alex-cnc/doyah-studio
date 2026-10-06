import { describe, expect, it } from 'vitest'
import {
  applyScheme,
  applyTheme,
  colorVar,
  cssVar,
  DEFAULT_SCHEME,
  kebab,
  normalizeScheme,
  normalizeTheme,
  readStoredScheme,
  readStoredTheme,
  SCHEME_ATTRIBUTE,
  storeScheme,
  storeTheme,
  THEME_SCHEMES,
  THEME_SCHEME_LABELS,
  THEME_SCHEME_STORAGE_KEY,
  THEME_STORAGE_KEY,
} from './index'

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

describe('theme/配色方案（主题集）', () => {
  it('候选来自生成物：id 唯一、非空，且恰好一个默认主题', () => {
    const ids = THEME_SCHEMES.map((scheme) => scheme.id)
    expect(ids.length).toBeGreaterThanOrEqual(2)
    expect(new Set(ids).size).toBe(ids.length)
    expect(ids.every((id) => /^[a-z0-9-]+$/.test(id))).toBe(true)
    expect(THEME_SCHEMES.filter((scheme) => scheme.fallback)).toHaveLength(1)
    expect(DEFAULT_SCHEME).toBe(THEME_SCHEMES.find((scheme) => scheme.fallback)?.id)
  })

  it('每个主题都有中文显示名（新增主题没配名字就判红，不静默显示成 id）', () => {
    for (const scheme of THEME_SCHEMES) {
      expect(THEME_SCHEME_LABELS[scheme.id], `主题 ${scheme.id} 缺显示名`).toBeTruthy()
    }
    for (const id of Object.keys(THEME_SCHEME_LABELS)) {
      expect(THEME_SCHEMES.map((scheme) => scheme.id)).toContain(id)
    }
  })

  it('落属性用 rawValue（不是 Swift case 名），未知取值回退默认主题', () => {
    const root = fakeRoot()
    applyScheme(root, 'bean-green')
    expect(root.attributes.get(SCHEME_ATTRIBUTE)).toBe('bean-green')
    applyScheme(root, 'techBlue') // Swift case 名不是合法 id ⇒ 回退（属性选择器匹配不上会静默不生效）
    expect(root.attributes.get(SCHEME_ATTRIBUTE)).toBe(DEFAULT_SCHEME)
    expect(normalizeScheme(null)).toBe(DEFAULT_SCHEME)
    expect(normalizeScheme('rose-gold')).toBe('rose-gold')
  })

  it('配色方案读写走同一个键', () => {
    const store = new Map<string, string>()
    const storage = {
      getItem: (key: string) => store.get(key) ?? null,
      setItem: (key: string, value: string) => void store.set(key, value),
    }
    expect(readStoredScheme(storage)).toBe(DEFAULT_SCHEME)
    storeScheme(storage, 'rose-gold')
    expect(store.get(THEME_SCHEME_STORAGE_KEY)).toBe('rose-gold')
    expect(readStoredScheme(storage)).toBe('rose-gold')
  })
})
