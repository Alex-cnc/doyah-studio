// 撤销 / 重做栈（FR-EDIT-60）· **纯逻辑**：合并判断、分支截断、上限、三档结论。
//
// 为什么要前端自带一套（不是在 textarea 上白拿原生撤销）：
// 原生撤销只认它自己那条输入流。本编辑器有大量**程序化写入** —— 格式化、缩进 / 反缩进、
// 注释切换、片段插入、查找替换 —— 一旦走过这些路径，那条流就断了：之后按 Ctrl+Z
// 要么什么都不发生，要么把整段内容退回到很早以前（还常把光标甩到末尾）。
// 用户看得见的现象是「格式化之后一按撤销，SQL 没了」。要修只能自己记账。
//
// 口径（照需求原文 FR-EDIT-60）：
//   · 一段**连续输入**合并成**一次**撤销 —— 判断复用 `editing.ts` 的 `shouldCoalesce`（一处判，不另写一份）；
//   · **行级编辑**（移行 / 注释切换 / 补全 / 格式化 / 替换）各算**一步**；
//   · 栈里存**全文快照**：JS 字符串是共享引用，100 步的额外成本是 100 个指针，不是 100 份副本。
//
// **游标漂移的处置**（这条最容易被写成静默错）：切页签 / 回填已保存查询 / 打开文件时，
// 文本是被整篇换掉的，而栈还记着上一份。此时**不许**把 A 页签的文本撤到 B 页签 ——
// 撤销前先核「栈顶那份文本 == 屏幕上那份」，不等就返回 `drifted`，由调用方**重建栈并如实说**。
import { shouldCoalesce, type EditKind, type EditStep, type Selection } from './editing'

/** 栈里的一版：全文 + 那时的选区（撤销之后要把光标放回去）。 */
export interface UndoSnapshot {
  text: string
  selection: Selection
}

export interface UndoState {
  /** `states[0]` = 仍保留的最早一版；`states[index]` = **屏幕上那一版**。 */
  states: UndoSnapshot[]
  index: number
  /** 上一次记录的那一步（合并判断用）；undo / redo 之后置空 —— 撤销完再打字必然是**新的一步**。 */
  last: EditStep | null
  /** 因超上限被丢掉的老步数（如实给读数，别假装栈是无限深）。 */
  dropped: number
}

/** 最多保留多少步。100 步足够覆盖「改错一段 SQL」的手感，再深就是白占内存。 */
export const UNDO_LIMIT = 100

export function newUndoState(initial: UndoSnapshot): UndoState {
  return { states: [{ text: initial.text, selection: { ...initial.selection } }], index: 0, last: null, dropped: 0 }
}

/**
 * 记一步。返回**新状态**（不改入参）：组件把它存进 `shallowRef`，菜单的可用态就能跟着变。
 *
 * 两种收法：① 与上一步可合并（同一段连续输入）⇒ 把**当前那一步的结果**换成新的全文，栈深度不变；
 * ② 否则压入新的一版，并**丢掉 redo 分支**（撤到中间又改了东西，原来的「未来」就不存在了）。
 */
export function pushUndo(state: UndoState, next: UndoSnapshot, step: EditStep): UndoState {
  const snapshot: UndoSnapshot = { text: next.text, selection: { ...next.selection } }
  const states = state.states.slice(0, state.index + 1)
  if (state.last !== null && states.length > 1 && shouldCoalesce(state.last, step)) {
    states[states.length - 1] = snapshot
    return { states, index: states.length - 1, last: step, dropped: state.dropped }
  }
  states.push(snapshot)
  let index = states.length - 1
  let dropped = state.dropped
  while (states.length > UNDO_LIMIT + 1) {
    states.shift()
    index -= 1
    dropped += 1
  }
  return { states, index, last: step, dropped }
}

export type UndoOutcome =
  | { kind: 'applied'; state: UndoState; snapshot: UndoSnapshot }
  /** 已经在最早 / 最晚那一版（没得撤了）。 */
  | { kind: 'exhausted' }
  /** 屏幕上的文本不是这一栈记的那份（切页签 / 外部替换）⇒ 调用方应重建栈，**不许**硬撤。 */
  | { kind: 'drifted' }

/** 撤销一步。`currentText` 是**屏幕上此刻**的全文（漂移判据靠它）。 */
export function undoOnce(state: UndoState, currentText: string): UndoOutcome {
  const top = state.states[state.index]
  if (!top || top.text !== currentText) return { kind: 'drifted' }
  if (state.index === 0) return { kind: 'exhausted' }
  const index = state.index - 1
  return {
    kind: 'applied',
    state: { ...state, states: state.states.slice(), index, last: null },
    snapshot: state.states[index],
  }
}

/** 重做一步（与 `undoOnce` 对称：`last` 同样置空）。 */
export function redoOnce(state: UndoState, currentText: string): UndoOutcome {
  const top = state.states[state.index]
  if (!top || top.text !== currentText) return { kind: 'drifted' }
  if (state.index >= state.states.length - 1) return { kind: 'exhausted' }
  const index = state.index + 1
  return {
    kind: 'applied',
    state: { ...state, states: state.states.slice(), index, last: null },
    snapshot: state.states[index],
  }
}

/** 还能撤几步。 */
export function undoDepth(state: UndoState): number {
  return state.index
}

/** 还能重做几步。 */
export function redoDepth(state: UndoState): number {
  return Math.max(0, state.states.length - 1 - state.index)
}

/**
 * 把一次文本变化量成一步：**位置要从「哪一段变了」推出来，不能靠光标**。
 *
 * 由头（本轮实测）：按光标落点记时，**连续退格一步都合并不上**，而且连插入也合并不上 ——
 * `caretOffset` 在 `@input` 触发前就被别的刷新链改成了新位置，量出来的 `at` 永远等于新光标，
 * 与上一步的 `atEnd` 差一格。改成从前后两版文本求**公共前后缀**，位置就与光标追踪无关：
 *   · 纯插入 ⇒ 变化区间在**新版**坐标里（连续两次插入首尾相接）；
 *   · 纯删除 ⇒ 变化区间在**旧版**坐标里（连续退格同样首尾相接，`shouldCoalesce` 才判得出来）；
 *   · 既插又删（等长替换 / 选中一段再输入）⇒ 记成 `line`，**不与前面合并**（它不是一段连续输入）。
 */
export function stepForTextChange(before: string, after: string, atMs: number): EditStep | null {
  if (before === after) return null
  const min = Math.min(before.length, after.length)
  let prefix = 0
  while (prefix < min && before[prefix] === after[prefix]) prefix += 1
  let suffix = 0
  while (suffix < min - prefix && before[before.length - 1 - suffix] === after[after.length - 1 - suffix]) suffix += 1
  const removed = before.length - prefix - suffix
  const added = after.length - prefix - suffix
  const kind: EditKind = removed === 0 ? 'insert' : added === 0 ? 'delete' : 'line'
  const atEnd = kind === 'delete' ? prefix + removed : prefix + added
  return { kind, at: prefix, atEnd, atMs }
}
