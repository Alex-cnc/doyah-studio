// 撤销 / 重做栈的行为单测（FR-EDIT-60）
//
// 这一层是**纯逻辑**，所以判据也全在这里：合并、分步、分支截断、上限、三档结论。
// 挂载测（`views/DatabaseView.undo.test.ts`）只证明「这些函数真的被键盘与菜单接到」，
// 规则本身不靠它来判 —— 两处都判必然分叉。
//
// 否定面与正例同权：判「不该合并」的用例和判「该合并」的一样多。
import { describe, expect, it } from 'vitest'
import {
  UNDO_LIMIT,
  alignedUndoState,
  dropUndoStack,
  newUndoState,
  putUndoStack,
  pushUndo,
  redoDepth,
  redoOnce,
  stepForTextChange,
  takeUndoStack,
  undoDepth,
  undoOnce,
  type UndoStacks,
  type UndoState,
} from './undoStack'

const at = (start: number, end = start) => ({ start, end })

/** 记一步打字（复用组件里那条路径：位置由 `stepForTextChange` 从前后两版文本推出来）。 */
function type(state: UndoState, before: string, after: string, caretAfter: number, atMs: number): UndoState {
  const step = stepForTextChange(before, after, atMs)
  if (!step) return state
  return pushUndo(state, { text: after, selection: at(caretAfter) }, step)
}

/** 记一步行级编辑（各算一步）。 */
function lineEdit(state: UndoState, after: string, caret: number, atMs: number): UndoState {
  return pushUndo(state, { text: after, selection: at(caret) }, { kind: 'line', at: caret, atEnd: caret, atMs })
}

describe('新栈', () => {
  it('一开始没有可撤也没有可重做的步骤', () => {
    const state = newUndoState({ text: 'select 1', selection: at(8) })
    expect(undoDepth(state)).toBe(0)
    expect(redoDepth(state)).toBe(0)
    expect(state.states).toHaveLength(1)
  })

  it('刚建栈就撤销：还是最早那一版，结论说「没得撤了」而不是假装撤了一步', () => {
    const state = newUndoState({ text: 'select 1', selection: at(8) })
    expect(undoOnce(state, 'select 1').kind).toBe('exhausted')
    expect(redoOnce(state, 'select 1').kind).toBe('exhausted')
  })
})

describe('连续输入合并成一次撤销', () => {
  it('连打三个字符（间隔在合并窗口内）只占一步，一次撤销回到空', () => {
    let state = newUndoState({ text: '', selection: at(0) })
    state = type(state, '', 's', 1, 1000)
    state = type(state, 's', 'se', 2, 1200)
    state = type(state, 'se', 'sel', 3, 1400)
    expect(undoDepth(state)).toBe(1)
    const back = undoOnce(state, 'sel')
    expect(back.kind).toBe('applied')
    if (back.kind === 'applied') expect(back.snapshot.text).toBe('')
  })

  it('间隔超过合并窗口 ⇒ 分成两步（隔一会儿再打字是新的意图）', () => {
    let state = newUndoState({ text: '', selection: at(0) })
    state = type(state, '', 'a', 1, 1000)
    state = type(state, 'a', 'ab', 2, 1000 + 801)
    expect(undoDepth(state)).toBe(2)
  })

  it('连续退格也合并成一步（变化区间记在旧版坐标里，两次退格首尾相接）', () => {
    let state = newUndoState({ text: 'select', selection: at(6) })
    state = type(state, 'select', 'selec', 5, 1000)
    state = type(state, 'selec', 'sele', 4, 1100)
    state = type(state, 'sele', 'sel', 3, 1200)
    expect(undoDepth(state)).toBe(1)
    const back = undoOnce(state, 'sel')
    if (back.kind === 'applied') expect(back.snapshot.text).toBe('select')
  })

  it('插入与删除交替 ⇒ 不合并（撤销时不该把「打字 + 退格」揉成一步）', () => {
    let state = newUndoState({ text: '', selection: at(0) })
    state = type(state, '', 'a', 1, 1000)
    state = type(state, 'a', '', 0, 1100)
    expect(undoDepth(state)).toBe(2)
  })

  it('光标跳到别处再打字 ⇒ 不合并（两处不相接）', () => {
    let state = newUndoState({ text: 'abc', selection: at(3) })
    state = type(state, 'abc', 'abcX', 4, 1000)
    state = type(state, 'abcX', 'YabcX', 1, 1100)
    expect(undoDepth(state)).toBe(2)
  })

  it('等长替换记成行级一步：不与前面打的字合并', () => {
    expect(stepForTextChange('a', 'b', 1000)?.kind).toBe('line')
    let state = newUndoState({ text: 'a', selection: at(1) })
    state = type(state, 'a', 'b', 1, 1000)
    state = type(state, 'b', 'bc', 2, 1050)
    expect(undoDepth(state)).toBe(2)
  })

  it('前后两版一样 ⇒ 不产生步骤（空操作不该占一格撤销）', () => {
    expect(stepForTextChange('same', 'same', 1000)).toBeNull()
  })
})

describe('行级编辑各算一步', () => {
  it('两次行级编辑就是两步，不会被合并', () => {
    let state = newUndoState({ text: 'select 1', selection: at(0) })
    state = lineEdit(state, '-- select 1', 0, 1000)
    state = lineEdit(state, '-- -- select 1', 0, 1010)
    expect(undoDepth(state)).toBe(2)
  })

  it('一次行级编辑打断连续输入：前面那串字与它各自一步', () => {
    let state = newUndoState({ text: '', selection: at(0) })
    state = type(state, '', 'a', 1, 1000)
    state = type(state, 'a', 'ab', 2, 1050)
    state = lineEdit(state, '-- ab', 0, 1100)
    expect(undoDepth(state)).toBe(2)
  })
})

describe('撤销 / 重做', () => {
  it('撤销之后能重做回同一份文本，选区一起回来', () => {
    let state = newUndoState({ text: 'aaa', selection: at(3) })
    state = lineEdit(state, 'bbb', 1, 1000)
    const back = undoOnce(state, 'bbb')
    expect(back.kind).toBe('applied')
    if (back.kind !== 'applied') return
    expect(back.snapshot.text).toBe('aaa')
    expect(back.snapshot.selection).toEqual(at(3))
    const again = redoOnce(back.state, 'aaa')
    expect(again.kind).toBe('applied')
    if (again.kind !== 'applied') return
    expect(again.snapshot.text).toBe('bbb')
    expect(again.snapshot.selection).toEqual(at(1))
  })

  it('撤销之后打字 ⇒ redo 分支被丢掉（那之后没有「未来」了）', () => {
    let state = newUndoState({ text: 'a', selection: at(1) })
    state = lineEdit(state, 'b', 1, 1000)
    const back = undoOnce(state, 'b')
    if (back.kind !== 'applied') throw new Error('应当能撤销')
    expect(redoDepth(back.state)).toBe(1)
    const edited = lineEdit(back.state, 'c', 1, 2000)
    expect(redoDepth(edited)).toBe(0)
    expect(redoOnce(edited, 'c').kind).toBe('exhausted')
  })

  it('撤销完再打字必然是新的一步（不会跟上一次撤销前的输入合并）', () => {
    let state = newUndoState({ text: '', selection: at(0) })
    state = type(state, '', 'a', 1, 1000)
    const back = undoOnce(state, 'a')
    if (back.kind !== 'applied') throw new Error('应当能撤销')
    const edited = type(back.state, '', 'a', 1, 1001)
    expect(undoDepth(edited)).toBe(1)
    expect(undoOnce(edited, 'a').kind).toBe('applied')
  })
})

describe('上限与漂移', () => {
  it('超过上限的老步被丢掉，栈深停在上限，丢掉的步数如实记着', () => {
    let state = newUndoState({ text: '0', selection: at(0) })
    for (let i = 1; i <= UNDO_LIMIT + 20; i += 1) state = lineEdit(state, String(i), 0, i)
    expect(undoDepth(state)).toBe(UNDO_LIMIT)
    expect(state.states.length).toBe(UNDO_LIMIT + 1)
    expect(state.dropped).toBe(20)
  })

  it('屏幕上的文本不是栈里那份 ⇒ 结论是 drifted（切页签 / 外部替换），不许硬撤', () => {
    let state = newUndoState({ text: 'a', selection: at(1) })
    state = lineEdit(state, 'b', 1, 1000)
    expect(undoOnce(state, '别的页签里的 SQL').kind).toBe('drifted')
    expect(redoOnce(state, '别的页签里的 SQL').kind).toBe('drifted')
  })
})

// ── 每页签一份栈（第 26 轮 · FR-EDIT-60 的页签条款）──────────────────────────
//
// 判据只判**存 / 取 / 丢**这三件的规则；「切页签之后 Ctrl+Z 真的撤对了」是接线，交给挂载测
// （`views/DatabaseView.perTabUndo.test.ts`）。否定面：不继承别人的历史、不许跨文档撤销。
describe('每页签一份栈', () => {
  it('没记过的页签 ⇒ 按它自己的文本起一个空栈（撤销报「没得撤」，不是 drifted）', () => {
    const state = takeUndoStack({}, 'tab-b', 'select 2', 8)
    expect(undoDepth(state)).toBe(0)
    expect(state.states).toHaveLength(1)
    expect(undoOnce(state, 'select 2').kind).toBe('exhausted')
  })

  it('存过再取回 ⇒ 逐字同一份（历史跨页签保留）', () => {
    let stacks: UndoStacks = {}
    const edited = lineEdit(newUndoState({ text: 'one', selection: at(3) }), 'one two', 3, 1000)
    stacks = putUndoStack(stacks, 'tab-a', edited)
    const back = takeUndoStack(stacks, 'tab-a', 'one two', 7)
    expect(back.states.map((s) => s.text)).toEqual(['one', 'one two'])
    expect(undoDepth(back)).toBe(1)
    const undone = undoOnce(back, 'one two')
    expect(undone.kind).toBe('applied')
    if (undone.kind === 'applied') expect(undone.snapshot.text).toBe('one')
  })

  it('栈顶与当前文本对不上（这个页签的文本被整篇换过）⇒ 起新栈，绝不把旧历史接上去', () => {
    let stacks: UndoStacks = {}
    const edited = lineEdit(newUndoState({ text: 'one', selection: at(3) }), 'one two', 3, 1000)
    stacks = putUndoStack(stacks, 'tab-a', edited)
    const fresh = takeUndoStack(stacks, 'tab-a', '完全换过的一段', 4)
    expect(undoDepth(fresh)).toBe(0)
    expect(fresh.states).toHaveLength(1)
    expect(fresh.states[0].text).toBe('完全换过的一段')
  })

  it('putUndoStack 不改入参；dropUndoStack 只删一个键，别的页签的栈原样留着', () => {
    const a = newUndoState({ text: 'a', selection: at(1) })
    const b = newUndoState({ text: 'b', selection: at(1) })
    const before = putUndoStack(putUndoStack({}, 'a', a), 'b', b)
    const frozen = JSON.stringify(before)
    const after = putUndoStack(before, 'a', newUndoState({ text: 'a2', selection: at(2) }))
    expect(JSON.stringify(before)).toBe(frozen)
    expect(after.a).not.toBe(a)
    const dropped = dropUndoStack(after, 'a')
    expect(Object.keys(dropped)).toEqual(['b'])
    expect(dropped.b).toBe(b)
    // 表里没有这个键 ⇒ 返回同一份表（不做无意义的复制）
    expect(dropUndoStack(dropped, 'nope')).toBe(dropped)
  })

  it('整篇替换之后先打字：那一笔压在新的一份上（不许跨文档撤销）', () => {
    const stale = lineEdit(newUndoState({ text: '旧文档', selection: at(3) }), '旧文档改', 3, 1000)
    const aligned = alignedUndoState(stale, '新文档', 3)
    const after = type(aligned, '新文档', '新文档x', 4, 2000)
    expect(undoDepth(after)).toBe(1)
    const back = undoOnce(after, '新文档x')
    expect(back.kind).toBe('applied')
    if (back.kind === 'applied') expect(back.snapshot.text).toBe('新文档')
  })

  it('栈顶与改动前文本一致时，对齐不动栈（不白扔历史）', () => {
    const state = lineEdit(newUndoState({ text: 'a', selection: at(1) }), 'ab', 2, 1000)
    expect(alignedUndoState(state, 'ab', 2)).toBe(state)
  })
})
