// 终端会话与显示的**纯逻辑**（W-C 底部终端 · 2.7 · 第二片 S-9b）
//
// 为什么单独一个文件：组件（`BottomPanel.vue`）只做接线 —— 起会话 / 写 / 读循环 / 关；
// 这里放的是**不碰 DOM、不碰 ipc** 的纯函数，单测判得了。
//
// ## 一条硬约束（来自上一片 S-9a 的实测交接，不许绕）
//
// Windows 伪控制台（ConPTY）在会话起来后会先发一条**光标位置查询** `ESC[6n`，并**等终端回话**
// `ESC[<行>;<列>R`；不回话，它一个字节都不往外吐（S-9a 集成测试里由测试自己扮终端回一次）。
// 回话是**终端仿真器**的职责 —— 本模块负责回话；同时 `terminal_read` 读到的字节一律
// **原样留在缓冲里**，其余控制序列**不吞**（我们没有真网格，就如实把原文显示出来）。

/** 光标位置查询（ConPTY 起会话后发的第一条）。 */
export const CURSOR_QUERY = '\u001b[6n'

/** 默认回话坐标（我们没有真网格，按 1;1 回 —— 与 S-9a 集成测试同一姿势）。 */
export const DEFAULT_CURSOR_ROW = 1
export const DEFAULT_CURSOR_COL = 1

/** 拼一条光标位置报告（终端应回给 pty 的字节）：`ESC[<行>;<列>R`。 */
export function cursorReport(row: number = DEFAULT_CURSOR_ROW, col: number = DEFAULT_CURSOR_COL): string {
  return `\u001b[${row};${col}R`
}

/** 一次读取的入参形态（与 Rust 侧 `pty::PtyChunk` 同形；这里只取要用的三样）。 */
export interface TerminalChunkLike {
  data: string
  eof: boolean
  exitCode: number | null
}

/** 一个会话在界面侧的全部状态（纯数据）。 */
export interface TerminalSessionState {
  /** 已收到的**可显示文本**：字节原样进，控制序列不吞。 */
  buffer: string
  /** 已回话过的查询扫描游标（同一条查询只回一次）。 */
  scanned: number
  /** 读端是否已到尽头（子进程结束 / 会话关闭）。 */
  eof: boolean
  /** 子进程退出码（拿到才有）。 */
  exitCode: number | null
}

/** 新建一个空会话状态。 */
export function createSessionState(): TerminalSessionState {
  return { buffer: '', scanned: 0, eof: false, exitCode: null }
}

/** 一次读入的结果：新状态 + 需要**写回 pty** 的回话字节（没有则 `null`）。 */
export interface FeedResult {
  state: TerminalSessionState
  reply: string | null
}

/**
 * 把一次 `terminal_read` 的字节喂进来（**纯函数**：不改入参，返回新状态）：
 *   · 字节**原样**追加进 `buffer`（其余控制序列不被吞）；
 *   · 扫出 `ESC[6n` 并生成回话（同一条只回一次；跨 chunk 的分片也能拼上）；
 *   · `eof` / `exitCode` 记进状态。
 */
export function feed(state: TerminalSessionState, chunk: TerminalChunkLike): FeedResult {
  const buffer = state.buffer + chunk.data
  // 从上次扫过的地方继续找查询，避免同一条重复回话。
  let cursor = state.scanned
  let replies = ''
  let found = buffer.indexOf(CURSOR_QUERY, cursor)
  while (found >= 0) {
    replies += cursorReport()
    cursor = found + CURSOR_QUERY.length
    found = buffer.indexOf(CURSOR_QUERY, cursor)
  }
  return {
    state: {
      buffer,
      scanned: cursor,
      eof: state.eof || chunk.eof,
      exitCode: chunk.exitCode ?? state.exitCode,
    },
    reply: replies.length > 0 ? replies : null,
  }
}

/**
 * 关掉某个会话后应该激活谁：优先**右邻**，没有右邻取左邻；一个都不剩 = `null`。
 * 纯函数（单测判得了），不碰界面状态。
 */
export function neighborAfterClose(ids: readonly number[], removed: number): number | null {
  const index = ids.indexOf(removed)
  if (index < 0) return ids.length > 0 ? ids[0] : null
  if (index + 1 < ids.length) return ids[index + 1]
  if (index - 1 >= 0) return ids[index - 1]
  return null
}

/** 键盘事件的修饰键（只取要用的两样）。 */
export interface KeyModifiers {
  ctrl?: boolean
  alt?: boolean
}

/**
 * 键盘事件 → 要写进 pty 的字节（**纯映射**；认不出的键返回 `null`，交回浏览器）。
 *
 * 说明：我们没有真终端仿真器，先把**常用键**映射对（回车 / 退格 / 方向键 / 控制组合）；
 * 单个可打印字符原样送。认不出的（F 键、组合键等）返回 `null`，不猜。
 */
export function keyToBytes(key: string, modifiers: KeyModifiers = {}): string | null {
  const named: Record<string, string> = {
    Enter: '\r',
    Backspace: '\u007f',
    Tab: '\t',
    Escape: '\u001b',
    ArrowUp: '\u001b[A',
    ArrowDown: '\u001b[B',
    ArrowRight: '\u001b[C',
    ArrowLeft: '\u001b[D',
    Home: '\u001b[H',
    End: '\u001b[F',
    Delete: '\u001b[3~',
    PageUp: '\u001b[5~',
    PageDown: '\u001b[6~',
    ' ': ' ',
  }
  const direct = named[key]
  if (direct) return direct
  if (modifiers.ctrl && key.length === 1) {
    const lower = key.toLowerCase()
    const code = lower.charCodeAt(0)
    if (code >= 97 && code <= 122) return String.fromCharCode(code - 96)
  }
  if (!modifiers.ctrl && !modifiers.alt && key.length === 1) return key
  return null
}
