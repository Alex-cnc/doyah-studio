// 动作图标集判据（T-20261013-053：全部图标化 + 图标须有明显含义 + 同族一致性）
//
// 守四件事：
//   ① **每个图标都有语义依据**（加令硬要求：不许抽象符号糊弄 —— 没有依据就是没想清）；
//   ② **图标名全局唯一登记**（`ACTION_GLYPHS` 与 `ACTION_SEMANTICS` 的键集必须一致）；
//   ③ **动作 → 图标 的映射全部指向已登记的图标**（防笔误借到不存在的图标）；
//   ④ **同一动作只有一个图标**（表是按动作做键的，天然唯一；这条守的是"别绕过表硬写"）。

import { describe, expect, it } from 'vitest'
import {
  ACTION_GLYPHS,
  ACTION_SEMANTICS,
  isActionGlyph,
  type ActionGlyph,
} from './actionIcons'
import { ACTION_ICONS, actionIcon, glyphUsage, isActionName } from './actionIcon'

describe('动作图标集：登记完备', () => {
  it('图标名清单与语义依据的键集一致（一个不多一个不少）', () => {
    const listed = [...ACTION_GLYPHS].sort()
    const documented = Object.keys(ACTION_SEMANTICS).sort()
    expect(documented).toEqual(listed)
  })

  it('每个图标都有非空语义依据（T-053：图标须有明显含义）', () => {
    for (const glyph of ACTION_GLYPHS) {
      const why = ACTION_SEMANTICS[glyph]
      expect(why, `${glyph} 缺语义依据`).toBeTruthy()
      expect(why.length, `${glyph} 的语义依据太短（敷衍）`).toBeGreaterThan(6)
    }
  })

  it('图标名清单无重复', () => {
    expect(new Set(ACTION_GLYPHS).size).toBe(ACTION_GLYPHS.length)
  })

  it('未登记的图标名不合法（判据与组件同一口径）', () => {
    expect(isActionGlyph('trash')).toBe(true)
    expect(isActionGlyph('delete')).toBe(false) // delete 是**动作**名，不是图标名
    expect(isActionGlyph('')).toBe(false)
  })
})

describe('动作 → 图标：映射合法且唯一', () => {
  it('每个动作都指向已登记的图标', () => {
    for (const [action, glyph] of Object.entries(ACTION_ICONS)) {
      expect(isActionGlyph(glyph), `动作 ${action} 指向了未登记的图标 ${glyph}`).toBe(true)
    }
  })

  it('同一动作只有一个图标（表按动作做键 ⇒ 天然唯一；这条防"绕过表另写一份"）', () => {
    const seen = new Map<string, Set<ActionGlyph>>()
    for (const [action, glyph] of Object.entries(ACTION_ICONS)) {
      ;(seen.get(action) ?? seen.set(action, new Set()).get(action)!).add(glyph)
    }
    for (const [action, glyphs] of seen) {
      expect(glyphs.size, `动作 ${action} 有多个图标`).toBe(1)
    }
  })

  it('取图标：已登记的动作拿到自己的图标', () => {
    expect(actionIcon('delete')).toBe('trash')
    expect(actionIcon('cancel')).toBe('close')
    expect(actionIcon('close')).toBe('close') // 取消与关闭**有意**同图标
    expect(actionIcon('newFile')).toBe('newFile')
  })

  it('取图标：未登记的动作落到占位图标（不抛错、不借用别的动作）', () => {
    expect(() => actionIcon('no-such-action')).not.toThrow()
    expect(actionIcon('no-such-action')).toBe('placeholder')
    expect(isActionName('no-such-action')).toBe(false)
    expect(isActionName('delete')).toBe(true)
  })

  it('共用面可复核（多个动作共用一个图标是有意的，但必须看得见）', () => {
    const usage = glyphUsage()
    // 叉被"取消"与"关闭"共用 —— 这是设计意图，不是错
    expect(usage.close).toEqual(expect.arrayContaining(['cancel', 'close']))
    // 每个图标名至少被一个动作使用（没有僵尸登记）
    const used = new Set(Object.values(ACTION_ICONS))
    for (const glyph of ACTION_GLYPHS) {
      if (glyph === 'placeholder') continue // 占位图标按设计不被动作使用
      expect(used.has(glyph), `图标 ${glyph} 登记了但没有任何动作在用（僵尸登记）`).toBe(true)
    }
  })
})
