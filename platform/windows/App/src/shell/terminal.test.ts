// 终端会话与显示的纯逻辑单测（S-9b）
//
// 守的口径（对卡面验收判据 2）：
//   · `ESC[6n` **必须回话**（不回话 ConPTY 一个字节都不吐 —— S-9a 实测交接）；
//   · `terminal_read` 读到的字节**原样进缓冲**，其余控制序列**不吞**；
//   · 回话形状 = `ESC[<行>;<列>R`；
//   · 负例 ≥3：未回话不吐字节 / 控制序列被吞 / 回话形状不对。
import { describe, expect, it } from 'vitest'
import {
  CURSOR_QUERY,
  createSessionState,
  cursorReport,
  feed,
  keyToBytes,
  neighborAfterClose,
} from './terminal'

describe('终端纯逻辑', () => {
  it('读到 ESC[6n 就回话，且查询原样留在缓冲里（不吞）', () => {
    const result = feed(createSessionState(), { data: `hi${CURSOR_QUERY}`, eof: false, exitCode: null })
    expect(result.reply).toBe(cursorReport())
    expect(result.state.buffer).toContain(CURSOR_QUERY)
    expect(result.state.buffer).toContain('hi')
  })

  it('同一条查询只回一次（后续普通输出不再回话）', () => {
    const first = feed(createSessionState(), { data: `x${CURSOR_QUERY}`, eof: false, exitCode: null })
    expect(first.reply).toBe(cursorReport())
    const second = feed(first.state, { data: 'plain output', eof: false, exitCode: null })
    expect(second.reply).toBeNull()
  })

  it('跨 chunk 分片的查询也能拼上并回话', () => {
    const head = feed(createSessionState(), { data: 'x\u001b[6', eof: false, exitCode: null })
    expect(head.reply).toBeNull()
    const tail = feed(head.state, { data: 'n', eof: false, exitCode: null })
    expect(tail.reply).toBe(cursorReport())
  })

  // 负例 ①：未回话不吐字节 —— 没有查询就不许凭空回话；空读也不往缓冲里塞东西
  it('负例：没有查询就不回话；空读不进缓冲（未回话不吐字节）', () => {
    const blank = feed(createSessionState(), { data: '', eof: false, exitCode: null })
    expect(blank.reply).toBeNull()
    expect(blank.state.buffer).toBe('')
    expect(blank.state.scanned).toBe(0)

    const quiet = feed(createSessionState(), { data: 'no query here', eof: false, exitCode: null })
    expect(quiet.reply).toBeNull()
  })

  // 负例 ②：控制序列被吞 —— 非查询控制序列必须原样留在缓冲，不许被过滤掉
  it('负例：其它控制序列不被吞（原样留在缓冲）', () => {
    const result = feed(createSessionState(), {
      data: '\u001b[2J\u001b[?25l正文\u001b[0m',
      eof: false,
      exitCode: null,
    })
    expect(result.reply).toBeNull()
    expect(result.state.buffer).toContain('\u001b[2J')
    expect(result.state.buffer).toContain('\u001b[?25l')
    expect(result.state.buffer).toContain('\u001b[0m')
    expect(result.state.buffer).toContain('正文')
  })

  // 负例 ③：回话形状——必须是 ESC[<行>;<列>R，不是随便一个串
  it('负例：回话形状是 ESC[<行>;<列>R', () => {
    expect(cursorReport()).toBe('\u001b[1;1R')
    expect(cursorReport(12, 34)).toBe('\u001b[12;34R')
    expect(/^\u001b\[\d+;\d+R$/.test(cursorReport(5, 9))).toBe(true)
  })

  it('eof / 退出码记进状态，且不被后续空读抹掉', () => {
    const ended = feed(createSessionState(), { data: 'done', eof: true, exitCode: 7 })
    expect(ended.state.eof).toBe(true)
    expect(ended.state.exitCode).toBe(7)
    const after = feed(ended.state, { data: '', eof: false, exitCode: null })
    expect(after.state.eof).toBe(true)
    expect(after.state.exitCode).toBe(7)
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
    feed(state, { data: 'x', eof: true, exitCode: 0 })
    expect(state).toEqual(snapshot)
  })
})
