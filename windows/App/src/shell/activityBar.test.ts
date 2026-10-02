// 活动栏 / 窗口标题（Windows 侧）—— 行为判据
//
// 这些用例守的是**跨端一致的那几条行为**（对侧 `Tests/…` 同口径）：
// 顺序只由声明决定、未知值回退、序号跟着栏上顺序、标题由项派生、未开工项不冒充已开工。

import { describe, expect, it } from 'vitest'
import {
  ACTIVITY_BAR_STORAGE_KEY,
  BRAND,
  BUILT_ITEMS,
  ITEMS,
  MAC_ITEMS,
  TITLE_SEPARATOR,
  isActivityBarItem,
  itemGlyph,
  itemMenuLabel,
  itemTitle,
  resolveActivityBarItem,
  shortcutIndex,
  visibleItems,
  windowTitle,
} from './activityBar'

describe('活动栏项', () => {
  it('栏上顺序 = 声明顺序，工作区在最上面（老板 2026-09-25 口径）', () => {
    expect(ITEMS).toEqual(['workspace', 'database', 'notes', 'retro'])
    expect(ITEMS[0]).toBe('workspace')
    // 唯一出处：栏上可显示的项就是声明数组本身（不是另排一份）
    expect(visibleItems()).toBe(ITEMS)
  })

  it('对侧三项是四项的前缀（本侧只多一个预留的 retro）', () => {
    expect(MAC_ITEMS).toEqual(ITEMS.slice(0, 3))
  })

  it('未开工项不冒充已开工：retro 在 BUILT_ITEMS 之外，其余三项都在', () => {
    expect(BUILT_ITEMS).toEqual(['workspace', 'database', 'notes'])
    expect(BUILT_ITEMS).not.toContain('retro')
    for (const item of BUILT_ITEMS) expect(ITEMS).toContain(item)
  })

  it('每一项都有中文 / 英文的标题与菜单文案，且没有空串', () => {
    for (const item of ITEMS) {
      for (const language of ['zh-Hans', 'en'] as const) {
        expect(itemTitle(item, language).length).toBeGreaterThan(0)
        expect(itemMenuLabel(item, language).length).toBeGreaterThan(0)
      }
      expect(itemGlyph(item).length).toBeGreaterThan(0)
    }
    // 品牌段不翻译，视图段翻译
    expect(itemTitle('database', 'zh-Hans')).toBe('数据库')
    expect(itemTitle('database', 'en')).toBe('Database')
  })

  it('id 解析只认声明过的项', () => {
    expect(isActivityBarItem('database')).toBe(true)
    expect(isActivityBarItem('Database')).toBe(false)
    expect(isActivityBarItem('')).toBe(false)
    expect(isActivityBarItem('settings')).toBe(false)
  })
})

describe('持久化解析（未知值不许让界面起不来）', () => {
  it('缺省 / 空串 / 未知值都回退到数据库视图', () => {
    expect(resolveActivityBarItem(undefined)).toBe('database')
    expect(resolveActivityBarItem(null)).toBe('database')
    expect(resolveActivityBarItem('')).toBe('database')
    expect(resolveActivityBarItem('settings')).toBe('database')
    expect(resolveActivityBarItem('数据库')).toBe('database')
  })

  it('认得的值原样返回', () => {
    for (const item of ITEMS) expect(resolveActivityBarItem(item)).toBe(item)
  })

  it('持久化里存了当前不可见的项 ⇒ 回退，不返回一个栏上不存在的视图', () => {
    // 许可证降级：只剩笔记可见，而持久化里存的是工作区
    expect(resolveActivityBarItem('workspace', ['notes'])).toBe('notes')
    // 存的就是可见项 ⇒ 保留
    expect(resolveActivityBarItem('notes', ['notes'])).toBe('notes')
    // 可见集里没有 database（默认项本身不可见）⇒ 取可见集第一项，且不抛错
    expect(resolveActivityBarItem('nope', ['notes', 'retro'])).toBe('notes')
  })

  it('存储键与对侧同一套 ui. 前缀、逐字相同', () => {
    expect(ACTIVITY_BAR_STORAGE_KEY).toBe('ui.activityBarItem')
    expect(ACTIVITY_BAR_STORAGE_KEY.startsWith('ui.')).toBe(true)
  })
})

describe('菜单快捷键序号（跟着栏上顺序，不写死在项上）', () => {
  it('栏上第一项就是 1 号', () => {
    expect(shortcutIndex('workspace')).toBe(1)
    expect(shortcutIndex('database')).toBe(2)
    expect(shortcutIndex('notes')).toBe(3)
    expect(shortcutIndex('retro')).toBe(4)
  })

  it('可见集变小 ⇒ 序号跟着变；不可见 = 没有序号', () => {
    expect(shortcutIndex('notes', ['notes'])).toBe(1)
    expect(shortcutIndex('workspace', ['notes'])).toBeNull()
    expect(shortcutIndex('retro', MAC_ITEMS)).toBeNull()
  })
})

describe('窗口标题由活动栏项派生（FR-EDIT-37）', () => {
  it('中文界面出中文视图名，英文界面出英文视图名', () => {
    expect(windowTitle('workspace', 'zh-Hans')).toBe('Doyah Studio - 工作区')
    expect(windowTitle('database', 'zh-Hans')).toBe('Doyah Studio - 数据库')
    expect(windowTitle('notes', 'en')).toBe('Doyah Studio - Notes')
  })

  it('品牌段用同一个常量拼、分隔符只有一处定义（两处各写一遍迟早会漂）', () => {
    for (const item of ITEMS) {
      expect(windowTitle(item)).toBe(`${BRAND}${TITLE_SEPARATOR}${itemTitle(item)}`)
    }
    expect(TITLE_SEPARATOR).toBe(' - ')
  })

  it('每一项都能拼出标题（含未开工的 retro —— 标题机制不因模块没开工而缺席）', () => {
    expect(windowTitle('retro', 'zh-Hans')).toBe('Doyah Studio - 复盘')
  })
})
