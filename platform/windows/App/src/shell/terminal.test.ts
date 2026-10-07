// 终端会话与显示的纯逻辑单测（S-9b；S-9d 薄壳化跟版）
//
// 守的口径（对卡面验收判据 2）：
//   · **渲染源 = 领域层屏幕投影**（Rust 侧 `terminal_bridge::ScreenProjection`），不再拿原始字节当渲染源；
//   · **前端不再回话**：`ESC[6n` 之类的应答已搬到 Rust 桥接层单点，`feed` 返回值里没有回话字节
//     （此前那批「回话形状」「同一条只回一次」的断言属于已删掉的 `cursorReport`，语义换成下面这批）；
//   · 会话状态（eof / 退出码）不被后续空读抹掉；
//   · 负例 ≥3：拿不到投影不清空画面 / eof 不被抹 / 空读不改状态。
import { describe, expect, it } from 'vitest'
import { createSessionState, feed, keyToBytes, neighborAfterClose, type ScreenProjection } from './terminal'

/** 造一个屏幕投影（只填用得上的字段，其余给默认）。 */
function projection(text: string, over: Partial<ScreenProjection> = {}): ScreenProjection {
  return {
    rows: text.split('\n'),
    text,
    cursor: { row: 0, col: 0 },
    cursorVisible: true,
    pendingResponses: [],
    eof: false,
    exitCode: null,
    ...over,
  }
}

describe('终端纯逻辑（S-9d：渲染源 = 领域层投影，前端不回话）', () => {
  it('渲染源是屏幕投影：feed 把 chunk.screen 存进状态', () => {
    const next = feed(createSessionState(), {
      data: 'raw-bytes-ignored',
      eof: false,
      exitCode: null,
      screen: projection('hello\nworld'),
    })
    expect(next.screen?.text).toBe('hello\nworld')
    expect(next.screen?.rows).toEqual(['hello', 'world'])
  })

  it('后续投影覆盖前一次（屏幕模型自己重排，前端只存最新）', () => {
    const first = feed(createSessionState(), { data: '', eof: false, exitCode: null, screen: projection('A') })
    const second = feed(first, { data: '', eof: false, exitCode: null, screen: projection('A\nB') })
    expect(second.screen?.text).toBe('A\nB')
  })

  // 新语义 ①：front 不再产出回话 —— 返回值只有 screen / eof / exitCode，且不因原文里有查询而合成任何东西
  it('前端不回话：feed 返回值没有回话字节，原文里的 ESC[6n 也不生成应答', () => {
    const next = feed(createSessionState(), {
      data: 'x\u001b[6n',
      eof: false,
      exitCode: null,
      screen: null,
    })
    expect(Object.keys(next).sort()).toEqual(['eof', 'exitCode', 'screen'])
    expect(next.screen).toBeNull()
  })

  // 负例 ①：拿不到投影（浏览器旁路 / 旧形态）⇒ 保留旧投影，**不清空已有画面**
  it('负例：拿不到投影时保留上一次投影（不清空画面）', () => {
    const shown = feed(createSessionState(), { data: '', eof: false, exitCode: null, screen: projection('keep') })
    const after = feed(shown, { data: '', eof: false, exitCode: null, screen: null })
    expect(after.screen?.text).toBe('keep')
  })

  // 负例 ②：eof / 退出码记进状态，且不被后续空读抹掉
  it('负例：eof / 退出码记进状态，不被后续空读抹掉', () => {
    const ended = feed(createSessionState(), { data: 'done', eof: true, exitCode: 7, screen: projection('done') })
    expect(ended.eof).toBe(true)
    expect(ended.exitCode).toBe(7)
    const after = feed(ended, { data: '', eof: false, exitCode: null })
    expect(after.eof).toBe(true)
    expect(after.exitCode).toBe(7)
    expect(after.screen?.text).toBe('done')
  })

  // 负例 ③：空读（没有投影、也没有字节）不改状态
  it('负例：空读不改状态（不把屏幕清空、也不动 eof/退出码）', () => {
    const base = feed(createSessionState(), { data: '', eof: false, exitCode: null, screen: projection('base') })
    const after = feed(base, { data: '', eof: false, exitCode: null })
    expect(after.screen).toEqual(base.screen)
    expect(after.eof).toBe(false)
    expect(after.exitCode).toBeNull()
  })

  it('关闭后该激活谁：优先右邻，其次左邻，都没有 = null', () => {
    expect(neighborAfterClose([1, 2, 3], 2)).toBe(3)
    expect(neighborAfterClose([1, 2, 3], 3)).toBe(2)
    expect(neighborAfterClose([1], 1)).toBeNull()
    expect(neighborAfterClose([1, 2], 9)).toBe(1)
  })

  it('键盘映射：常用键对得上，认不出的交回浏览器', () => {
    expect(keyToBytes('Enter')).toBe('\r')
    expect(keyToBytes('Backspace')).toBe('\u007f')
    expect(keyToBytes('ArrowUp')).toBe('\u001b[A')
    expect(keyToBytes('a')).toBe('a')
    expect(keyToBytes('c', { ctrl: true })).toBe('\u0003')
    expect(keyToBytes('F5')).toBeNull()
  })

  it('feed 是纯函数：不改入参', () => {
    const state = createSessionState()
    const snapshot = { ...state }
    feed(state, { data: 'x', eof: true, exitCode: 0, screen: projection('x') })
    expect(state).toEqual(snapshot)
  })

  it('原始字节不再进状态：状态里没有 buffer / scanned 这类渲染源残留', () => {
    const next = feed(createSessionState(), { data: 'raw', eof: false, exitCode: null, screen: null })
    expect('buffer' in next).toBe(false)
    expect('scanned' in next).toBe(false)
  })
})
