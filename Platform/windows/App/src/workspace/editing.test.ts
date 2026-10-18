// 编辑面纯逻辑 · 第二批 —— 行为判据（FR-EDIT-51 / 52 / 53 / 54）
//
// 每条用例名就是需求里那句行为，读用例清单 = 读需求清单。

import { describe, expect, it } from 'vitest'
import {
  affectedLineRange,
  autoIndentForNewline,
  autoPair,
  clampSelection,
  detectIndentStyle,
  indentSelection,
  indentUnitOf,
  matchBracket,
  moveOrDuplicateLines,
  shouldCoalesce,
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

describe('FR-EDIT-20 缩进 / 反缩进选中文本', () => {
  it('多行选区逐行加一个缩进单位', () => {
    const result = indentSelection('a\nb', { start: 0, end: 3 }, 1, '  ')
    expect(result.text).toBe('  a\n  b')
  })

  it('反缩进优先去掉一个完整单位', () => {
    const result = indentSelection('    a\n    b', { start: 0, end: 9 }, -1, '  ')
    expect(result.text).toBe('  a\n  b')
  })

  it('反缩进时行首不足一个单位 ⇒ 能去多少去多少（不削内容）', () => {
    expect(indentSelection(' a', { start: 0, end: 2 }, -1, '    ').text).toBe('a')
  })

  it('空行不动', () => {
    expect(indentSelection('a\n\nb', { start: 0, end: 4 }, 1, '  ').text).toBe('  a\n\n  b')
  })

  it('选区保持覆盖同一批行', () => {
    const result = indentSelection('a\nb', { start: 0, end: 3 }, 1, '  ')
    expect(result.text.slice(result.selection.start, result.selection.end)).toBe('  a\n  b')
  })
})

describe('FR-EDIT-49 括号 / 引号自动配对', () => {
  it('打出左括号 ⇒ 补右半且光标留在中间', () => {
    const out = autoPair('', { start: 0, end: 0 }, '(')
    expect(out).toEqual({ kind: 'pair', text: '()', selection: { start: 1, end: 1 } })
  })

  it('打出引号同样成对（引号自己就是闭合符）', () => {
    const out = autoPair('ab', { start: 2, end: 2 }, '"')
    expect(out?.text).toBe('ab""')
    expect(out?.selection).toEqual({ start: 3, end: 3 })
  })

  it('光标处已是闭合符时再打闭合符 = 跳过（不重复输入）', () => {
    const out = autoPair('()', { start: 1, end: 1 }, ')')
    expect(out).toEqual({ kind: 'skip', text: '()', selection: { start: 2, end: 2 } })
  })

  it('有选区时打出配对符 ⇒ 包裹选区，选区落在原文上', () => {
    const out = autoPair('abc', { start: 1, end: 3 }, '[')
    expect(out?.text).toBe('a[bc]')
    expect(out?.selection).toEqual({ start: 2, end: 4 })
  })

  it('普通字符不接管（交回调用方按普通输入处理）', () => {
    expect(autoPair('a', { start: 1, end: 1 }, 'b')).toBeNull()
  })

  it('配对表可由调用方覆盖（语言特有符号）', () => {
    const out = autoPair('', { start: 0, end: 0 }, '<', { '<': '>' })
    expect(out?.text).toBe('<>')
  })
})

describe('FR-EDIT-50 括号匹配', () => {
  it('光标在左括号之后 ⇒ 配对到右括号', () => {
    expect(matchBracket('f(a)', 2)).toEqual({ at: 1, partner: 3 })
  })

  it('光标在右括号之后 ⇒ 反向配对到左括号', () => {
    expect(matchBracket('f(a)', 4)).toEqual({ at: 3, partner: 1 })
  })

  it('嵌套括号配对到**同层**的那个', () => {
    expect(matchBracket('((a))', 1)).toEqual({ at: 0, partner: 4 })
  })

  it('不配平时 partner 为 null（界面可据此告警）', () => {
    expect(matchBracket('(a', 1)).toEqual({ at: 0, partner: null })
  })

  it('光标旁边没有括号 ⇒ null', () => {
    expect(matchBracket('abc', 2)).toBeNull()
  })
})

describe('FR-EDIT-60 撤销粒度', () => {
  const step = (kind: 'insert' | 'delete' | 'line', at: number, atEnd: number, atMs: number) =>
    ({ kind, at, atEnd, atMs })

  it('连续打字合并成一步撤销', () => {
    expect(shouldCoalesce(step('insert', 3, 4, 1000), step('insert', 4, 5, 1100))).toBe(true)
  })

  it('间隔超过 800 ms ⇒ 分成两步', () => {
    expect(shouldCoalesce(step('insert', 3, 4, 1000), step('insert', 4, 5, 2500))).toBe(false)
  })

  it('插入与删除交替 ⇒ 各自独立', () => {
    expect(shouldCoalesce(step('insert', 3, 4, 1000), step('delete', 4, 3, 1050))).toBe(false)
  })

  it('行级编辑（移行 / 注释切换 / 补全）永远独立成一步', () => {
    expect(shouldCoalesce(step('line', 0, 10, 1000), step('line', 0, 10, 1010))).toBe(false)
    expect(shouldCoalesce(step('insert', 3, 4, 1000), step('line', 4, 4, 1010))).toBe(false)
  })

  it('位置不相接（中间有跳转）⇒ 不合并', () => {
    expect(shouldCoalesce(step('insert', 3, 4, 1000), step('insert', 40, 41, 1100))).toBe(false)
  })
})

