// 编辑面纯逻辑 · 第二批 —— 行为判据（FR-EDIT-51 / 52 / 53 / 54）
//
// 每条用例名就是需求里那句行为，读用例清单 = 读需求清单。

import { describe, expect, it } from 'vitest'
import {
  affectedLineRange,
  autoIndentForNewline,
  clampSelection,
  detectIndentStyle,
  indentUnitOf,
  moveOrDuplicateLines,
  toggleLineComment,
} from './editing'

describe('FR-EDIT-51 注释切换（注释符插在缩进之后）', () => {
  it('未注释 ⇒ 加注释且保持缩进', () => {
    const result = toggleLineComment('  select 1', { start: 0, end: 0 }, '--')
    expect(result.text).toBe('  --select 1')
  })

  it('已注释 ⇒ 取消注释且缩进不动', () => {
    const result = toggleLineComment('  --select 1', { start: 0, end: 0 }, '--')
    expect(result.text).toBe('  select 1')
  })

  it('连按两次回到原文（不是单向加注释）', () => {
    const once = toggleLineComment('x', { start: 0, end: 0 }, '//')
    const twice = toggleLineComment(once.text, once.selection, '//')
    expect(twice.text).toBe('x')
  })

  it('多行里有一行没注释 ⇒ 全部加（不做逐行取反）', () => {
    const text = '--a\nb\n--c'
    const result = toggleLineComment(text, { start: 0, end: text.length }, '--')
    expect(result.text).toBe('----a\n--b\n----c')
  })

  it('全部已注释的多行 ⇒ 全部取消', () => {
    const text = '--a\n--b'
    const result = toggleLineComment(text, { start: 0, end: text.length }, '--')
    expect(result.text).toBe('a\nb')
  })

  it('空行不参与判定也不加注释符', () => {
    const text = '--a\n\n--b'
    const result = toggleLineComment(text, { start: 0, end: text.length }, '--')
    expect(result.text).toBe('a\n\nb')
  })

  it('选区终点落在下一行行首时不含那一行', () => {
    expect(affectedLineRange('a\nb\nc', { start: 0, end: 2 })).toEqual([0, 0])
  })

  it('选区越界被夹进全文（不抛异常）', () => {
    expect(clampSelection('abc', { start: -5, end: 99 })).toEqual({ start: 0, end: 3 })
  })

  it('光标停在换行处只动本行（换行不属于下一行）', () => {
    const result = toggleLineComment('a\nb', { start: 1, end: 1 }, '--')
    expect(result.text).toBe('--a\nb')
  })

  it('切换后选区覆盖被改的整行（便于连按）', () => {
    const result = toggleLineComment('a\nb', { start: 0, end: 3 }, '--')
    expect(result.text).toBe('--a\n--b')
    expect(result.text.slice(result.selection.start, result.selection.end)).toBe('--a\n--b')
  })
})

describe('FR-EDIT-52 移行 / 复制行（到边界是 no-op）', () => {
  it('上移把整行搬到上一行之前', () => {
    const result = moveOrDuplicateLines('a\nb\nc', { start: 2, end: 2 }, 'up')
    expect(result.text).toBe('b\na\nc')
  })

  it('首行上移是 no-op', () => {
    const text = 'a\nb'
    expect(moveOrDuplicateLines(text, { start: 0, end: 0 }, 'up').text).toBe(text)
  })

  it('下移把整行搬到下一行之后（末行无换行也不粘连）', () => {
    const result = moveOrDuplicateLines('a\nb\nc', { start: 2, end: 2 }, 'down')
    expect(result.text).toBe('a\nc\nb')
  })

  it('末行下移是 no-op', () => {
    const text = 'a\nb'
    expect(moveOrDuplicateLines(text, { start: 2, end: 2 }, 'down').text).toBe(text)
  })

  it('末行没有结尾换行时上移也不粘连', () => {
    const result = moveOrDuplicateLines('a\nb', { start: 2, end: 2 }, 'up')
    expect(result.text).toBe('b\na')
  })

  it('原本以换行结尾 ⇒ 搬完仍以换行结尾', () => {
    const result = moveOrDuplicateLines('a\nb\n', { start: 0, end: 0 }, 'down')
    expect(result.text).toBe('b\na\n')
  })

  it('复制整行插在下方，选区落在副本上', () => {
    const result = moveOrDuplicateLines('a\nb', { start: 0, end: 0 }, 'duplicate')
    expect(result.text).toBe('a\na\nb')
    expect(result.text.slice(result.selection.start, result.selection.end)).toBe('a')
  })

  it('复制末行（无结尾换行）不会把副本与上一行粘连', () => {
    const result = moveOrDuplicateLines('a\nb', { start: 2, end: 2 }, 'duplicate')
    expect(result.text).toBe('a\nb\nb')
  })
})

describe('FR-EDIT-53 自动缩进（回车继承当前缩进）', () => {
  it('继承当前行的行首缩进', () => {
    expect(autoIndentForNewline('    select 1', '', '  ')).toBe('    ')
  })

  it('以 { 结尾 ⇒ 多一级', () => {
    expect(autoIndentForNewline('  if (x) {', '', '  ')).toBe('    ')
  })

  it('以 [ 结尾且行尾有空白 ⇒ 仍算开括号', () => {
    expect(autoIndentForNewline('[', ' ', '\t')).toBe('\t')
  })

  it('下一字符是 } ⇒ 回退一级', () => {
    expect(autoIndentForNewline('    x', '}', '  ')).toBe('  ')
  })

  it('回退不会低到负数（缩进不足一级时保持原样）', () => {
    expect(autoIndentForNewline('x', '}', '  ')).toBe('')
  })
})

describe('FR-EDIT-54 缩进检测（按内容判，不靠扩展名）', () => {
  it('两空格缩进的内容 ⇒ 软 tab 宽度 2', () => {
    expect(detectIndentStyle('if x:\n  a\n    b\n  c')).toEqual({ kind: 'space', width: 2 })
  })

  it('四空格缩进的内容 ⇒ 宽度 4', () => {
    expect(detectIndentStyle('if (x) {\n    a();\n        b();\n}')).toEqual({ kind: 'space', width: 4 })
  })

  it('制表符缩进的内容 ⇒ 硬 tab', () => {
    expect(detectIndentStyle('a\n\tb\n\tc')).toEqual({ kind: 'tab', width: 1 })
  })

  it('没有缩进的内容 ⇒ 回退默认口径', () => {
    expect(detectIndentStyle('a\nb')).toEqual({ kind: 'space', width: 4 })
    expect(detectIndentStyle('a\nb', { kind: 'tab', width: 1 })).toEqual({ kind: 'tab', width: 1 })
  })

  it('口径 → 插入串：软 tab 按宽度铺空格，硬 tab 一个制表符', () => {
    expect(indentUnitOf({ kind: 'space', width: 3 })).toBe('   ')
    expect(indentUnitOf({ kind: 'tab', width: 1 })).toBe('\t')
  })
})
