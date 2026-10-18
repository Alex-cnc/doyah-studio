// 代码折叠 —— 行为判据（FR-EDIT-55）
import { describe, expect, it } from 'vitest'
import { foldRanges, visibleLines } from './folding'

describe('FR-EDIT-55 折叠区推导', () => {
  it('缩进块：从开括号行折到块末', () => {
    const text = ['func f() {', '    a', '    b', '}', 'x'].join('\n')
    expect(foldRanges(text)).toEqual([{ startLine: 0, endLine: 3, hiddenLines: 3 }])
  })

  it('藏不住 minLines 行的块不折叠（单行 if 折了只是藏个 }）', () => {
    expect(foldRanges('if (x) {\n}')).toEqual([])
  })

  it('围栏代码块整段可折，且围栏内的 { 不参与推块', () => {
    const text = ['```', 'if (x) {', '  a', '```'].join('\n')
    const ranges = foldRanges(text)
    expect(ranges).toEqual([{ startLine: 0, endLine: 3, hiddenLines: 2 }])
  })

  it('多个块按行号升序', () => {
    const text = ['a {', '  b', '  c', '}', 'd {', '  e', '  f', '}'].join('\n')
    expect(foldRanges(text).map((range) => range.startLine)).toEqual([0, 4])
  })

  it('tab 缩进按 1 档比较（不把 tab 当 0 宽）', () => {
    const text = ['func {', '\ta', '\tb', '}'].join('\n')
    expect(foldRanges(text)).toEqual([{ startLine: 0, endLine: 3, hiddenLines: 3 }])
  })
})

describe('折叠状态 → 可见行', () => {
  it('折起某个区 ⇒ 内部行不可见，首行仍可见', () => {
    const text = ['func f() {', '    a', '    b', '}', 'x'].join('\n')
    const ranges = foldRanges(text)
    expect(visibleLines(text, ranges, new Set([0]))).toEqual([0, 4])
  })

  it('没折 ⇒ 全部可见', () => {
    const text = ['func f() {', '    a', '    b', '}', 'x'].join('\n')
    expect(visibleLines(text, foldRanges(text), new Set())).toEqual([0, 1, 2, 3, 4])
  })
})
