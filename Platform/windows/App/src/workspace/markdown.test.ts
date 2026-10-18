// 工作区 Markdown 手感 —— 行为判据（FR-EDIT-47 / 48）
import { describe, expect, it } from 'vitest'
import { nextListPrefix, parseListMarker, toggleTaskCheckbox } from './markdown'

describe('FR-EDIT-47 回车续行', () => {
  it('无序列表 ⇒ 同一个项目符号', () => {
    expect(nextListPrefix('- 第一项')).toBe('- ')
  })

  it('有序列表 ⇒ 序号 +1（保持 . 或 ) 分隔符）', () => {
    expect(nextListPrefix('1. 一')).toBe('2. ')
    expect(nextListPrefix('9) 九')).toBe('10) ')
  })

  it('缩进原样保留', () => {
    expect(nextListPrefix('  - 子项')).toBe('  - ')
  })

  it('任务框 ⇒ 下一个回到未勾选', () => {
    expect(nextListPrefix('- [x] 做完的')).toBe('- [ ] ')
  })

  it('空条目 ⇒ null（调用方去掉标记 = 退出列表）', () => {
    expect(nextListPrefix('- ')).toBeNull()
    expect(nextListPrefix('- [ ] ')).toBeNull()
  })

  it('不是列表条目 ⇒ null（不替用户瞎续）', () => {
    expect(nextListPrefix('普通段落')).toBeNull()
  })
})

describe('FR-EDIT-48 任务框勾选翻转（⌘L）', () => {
  it('未勾选 ⇒ 勾上，缩进与文字不动', () => {
    expect(toggleTaskCheckbox('  - [ ] 买菜')).toBe('  - [x] 买菜')
  })

  it('已勾选 ⇒ 取消，缩进与文字不动', () => {
    expect(toggleTaskCheckbox('- [x] 买菜')).toBe('- [ ] 买菜')
  })

  it('有序列表的任务框同样支持', () => {
    expect(toggleTaskCheckbox('1. [ ] 第一步')).toBe('1. [x] 第一步')
  })

  it('普通条目原样返回（不硬塞任务框）', () => {
    expect(toggleTaskCheckbox('- 普通条目')).toBe('- 普通条目')
    expect(toggleTaskCheckbox('段落')).toBe('段落')
  })
})

describe('列表标记解析', () => {
  it('解析出缩进 / 符号 / 序号 / 任务框', () => {
    expect(parseListMarker('  2. [x] 有内容')).toEqual({
      indent: '  ', bullet: '2.', ordinal: 2, gap: ' ', content: '有内容', task: true, checked: true,
    })
  })
})
