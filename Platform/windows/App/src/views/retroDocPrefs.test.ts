// 字号三档偏好的纯函数判据（`FR-R-13-08` ①：显示设定只改「怎么看」，不动包内容）。
//
// 钉六件事：默认档 = 标准 · 坏值 / 空值 / 读不出都回标准 · 存不下不抛 · 加减档到头停住 · class 名字只三种 · 读写往返一致。
import { describe, expect, it } from 'vitest'
import {
  DEFAULT_DOC_FONT_SIZE,
  DOC_FONT_KEY,
  docFontClass,
  isDocFontSize,
  readDocFontSize,
  stepDocFontSize,
  storeDocFontSize,
  type KeyValueStore,
} from '../plugins/retro/docPrefs'

function memoryStore(initial: Record<string, string> = {}): KeyValueStore & { data: Record<string, string> } {
  const data = { ...initial }
  return {
    data,
    getItem: (key) => (key in data ? data[key] : null),
    setItem: (key, value) => {
      data[key] = value
    },
  }
}

describe('周报字号三档', () => {
  it('nothing_stored_means_the_standard_tier', () => {
    expect(readDocFontSize(memoryStore())).toBe('md')
    expect(DEFAULT_DOC_FONT_SIZE).toBe('md')
    expect(readDocFontSize(null)).toBe('md')
    expect(readDocFontSize(undefined)).toBe('md')
  })

  it('a_stored_tier_comes_back_and_survives_a_round_trip', () => {
    const store = memoryStore()
    storeDocFontSize(store, 'lg')
    expect(store.data[DOC_FONT_KEY]).toBe('lg')
    expect(readDocFontSize(store)).toBe('lg')
  })

  it('a_broken_or_unknown_value_falls_back_instead_of_breaking_the_report', () => {
    expect(readDocFontSize(memoryStore({ [DOC_FONT_KEY]: 'huge' }))).toBe('md')
    expect(readDocFontSize(memoryStore({ [DOC_FONT_KEY]: '' }))).toBe('md')
    expect(readDocFontSize(memoryStore({ [DOC_FONT_KEY]: '  ' }))).toBe('md')
    // 前后空白不影响认档（手工改过 localStorage 也能认）
    expect(readDocFontSize(memoryStore({ [DOC_FONT_KEY]: ' sm ' }))).toBe('sm')
  })

  it('storage_that_throws_is_treated_as_no_preference', () => {
    const throwing: KeyValueStore = {
      getItem: () => {
        throw new Error('blocked')
      },
      setItem: () => {
        throw new Error('blocked')
      },
    }
    expect(readDocFontSize(throwing)).toBe('md')
    // 存不下只丢偏好，不许抛出去（读正文不该被一段存储失败打断）
    expect(() => storeDocFontSize(throwing, 'lg')).not.toThrow()
    expect(() => storeDocFontSize(null, 'lg')).not.toThrow()
  })

  it('stepping_stops_at_both_ends_instead_of_wrapping_around', () => {
    expect(stepDocFontSize('md', 1)).toBe('lg')
    expect(stepDocFontSize('md', -1)).toBe('sm')
    expect(stepDocFontSize('lg', 1)).toBe('lg')
    expect(stepDocFontSize('sm', -1)).toBe('sm')
    // 坏档当作标准档再加减（界面不该因为这个按钮变成死键）
    expect(stepDocFontSize('huge' as never, 1)).toBe('lg')
    expect(stepDocFontSize('huge' as never, -1)).toBe('sm')
  })

  it('the_container_class_is_one_of_exactly_three_names', () => {
    expect(docFontClass('sm')).toBe('retro__document--sm')
    expect(docFontClass('md')).toBe('retro__document--md')
    expect(docFontClass('lg')).toBe('retro__document--lg')
    expect(docFontClass('nope' as never)).toBe('retro__document--md')
    expect(isDocFontSize('lg')).toBe(true)
    expect(isDocFontSize('LG')).toBe(false)
  })
})
