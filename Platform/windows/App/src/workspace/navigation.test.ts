// 跳转与符号定位 —— 行为判据（FR-EDIT-19 / 58）
import { describe, expect, it } from 'vitest'
import { definitionSites, identifierAt, offsetOfJump, parseJumpInput } from './navigation'

const TEXT = ['select 1', 'from t', 'where x = 1'].join('\n')

describe('FR-EDIT-19 跳到指定行或列', () => {
  it('只写行号 ⇒ 列取 1', () => {
    expect(parseJumpInput('2', TEXT)).toEqual({ ok: true, target: { line: 1, column: 0 } })
  })

  it('行:列 ⇒ 都按 1 基换算成 0 基', () => {
    expect(parseJumpInput('2:3', TEXT)).toEqual({ ok: true, target: { line: 1, column: 2 } })
  })

  it('行号超界 ⇒ 夹到末行（不报错）', () => {
    const parsed = parseJumpInput('99', TEXT)
    expect(parsed.ok && parsed.target.line).toBe(2)
  })

  it('列超界 ⇒ 夹到行尾', () => {
    const parsed = parseJumpInput('1:99', TEXT)
    expect(parsed.ok && parsed.target.column).toBe('select 1'.length)
  })

  it('空输入 / 非法写法 ⇒ 如实拒绝并给原因', () => {
    expect(parseJumpInput('  ', TEXT)).toEqual({ ok: false, reason: '没有输入行号' })
    const bad = parseJumpInput('abc', TEXT)
    expect(bad.ok).toBe(false)
  })

  it('0 或负数行号 ⇒ 拒绝（行号从 1 开始）', () => {
    expect(parseJumpInput('0', TEXT).ok).toBe(false)
  })

  it('跳转目标 → 全文字符偏移', () => {
    expect(offsetOfJump(TEXT, { line: 1, column: 0 })).toBe('select 1\n'.length)
    expect(offsetOfJump(TEXT, { line: 2, column: 6 })).toBe('select 1\nfrom t\n'.length + 6)
  })
})

describe('FR-EDIT-58 悬停文档与跳定义（词法级）', () => {
  it('取光标所在标识符', () => {
    const at = TEXT.indexOf('from')
    expect(identifierAt(TEXT, at + 2)).toEqual({ name: 'from', start: at })
  })

  it('光标在空白处 ⇒ null', () => {
    expect(identifierAt('a  b', 2)).toBeNull()
  })

  it('找同文件的声明行（func/fn/def/let/const/type/class…）', () => {
    const text = ['fn helper() {', '  let other = 1', '  helper()', '}'].join('\n')
    const hits = definitionSites(text, 'helper')
    expect(hits).toHaveLength(1)
    expect(hits[0].line).toBe(0)
    expect(text.slice(hits[0].offset, hits[0].offset + 6)).toBe('helper')
  })

  it('只有调用没有声明 ⇒ 空数组（界面显示「本文件没有定义」而不是静默）', () => {
    expect(definitionSites('call(helper)', 'helper')).toEqual([])
  })

  it('不把别的标识符当成命中（`helper2` 不算 `helper`）', () => {
    expect(definitionSites('fn helper2() {', 'helper')).toEqual([])
  })
})
