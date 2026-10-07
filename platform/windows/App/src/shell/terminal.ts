// 终端会话与显示的**纯逻辑**（W-C 底部终端 · 2.7 · 第二片 S-9b；第四片 S-9d 薄壳化）
//
// 为什么单独一个文件：组件（`BottomPanel.vue`）只做接线 —— 起会话 / 写 / 读循环 / 关；
// 这里放的是**不碰 DOM、不碰 ipc** 的纯函数，单测判得了。
//
// ## S-9d 起的两条口径（承接 S-9c 裁决 Q3 / 组长 0 步 A）
//
// 1. **设备查询回话搬到 Rust 桥接层单点**：`ESC[6n` 之类的应答由 `terminal_bridge::read` 写回 PTY，
//    前端**不再扫查询、不再回话** —— 此前那份 `cursorReport` / `CURSOR_QUERY` / `scanned` 一并删掉
//    （不留死码，防再被接线造成**双回话**：两边同时回话，ConPTY 会把第二条应答当杂散输入）。
// 2. **渲染源切到领域层投影**：只存桥接层给的 `screen`（领域层屏幕模型投影），
//    **不再拿原始字节缓冲 `buffer` 当渲染源**。原始字节仍由 Rust 原样返回，但前端不显示它。

/** 领域层屏幕模型投影（与 Rust 侧 `terminal_bridge::ScreenProjection` 同形）。 */
export interface ScreenProjection {
  /** 网格每行的可显示文本。 */
  rows: string[]
  /** 整屏文本（各行以 `\n` 相连）—— **渲染源**。 */
  text: string
  cursor: { row: number; col: number }
  cursorVisible: boolean
  /** 本轮消费（已写回 PTY）的设备查询应答；消费后清空，故同一条至多出现一次。 */
  pendingResponses: string[]
  eof: boolean
  exitCode: number | null
}

/** 一次读取的入参形态（与 Rust 侧 `terminal_bridge::TerminalChunk` 同形；这里只取要用的几样）。 */
export interface TerminalChunkLike {
  /** PTY 原始字节（前端不再显示它；保留字段以与线上形态同形）。 */
  data: string
  eof: boolean
  exitCode: number | null
  /** 领域层屏幕投影；拿不到（浏览器旁路 / 旧形态）时为 `null`。 */
  screen?: ScreenProjection | null
}

/** 一个会话在界面侧的全部状态（纯数据）。 */
export interface TerminalSessionState {
  /** 领域层屏幕模型投影（**渲染源**）；还没拿到过投影时为 `null`。 */
  screen: ScreenProjection | null
  /** 读端是否已到尽头（子进程结束 / 会话关闭）。 */
  eof: boolean
  /** 子进程退出码（拿到才有）。 */
  exitCode: number | null
}

/** 新建一个空会话状态。 */
export function createSessionState(): TerminalSessionState {
  return { screen: null, eof: false, exitCode: null }
}

/**
 * 把一次 `terminal_read` 的结果喂进来（**纯函数**：不改入参，返回新状态）：
 *   · 有屏幕投影就**存下**（渲染源）；没有（旁路 / 拿不到）则保留上一次，**不清空已有画面**；
 *   · `eof` / `exitCode` 记进状态，不被后续空读抹掉。
 * **不回话**：设备查询应答归 Rust 桥接层单点（见文件头第 1 条）—— 返回值里**没有回话字节**。
 */
export function feed(state: TerminalSessionState, chunk: TerminalChunkLike): TerminalSessionState {
  return {
    screen: chunk.screen ?? state.screen,
    eof: state.eof || chunk.eof,
    exitCode: chunk.exitCode ?? state.exitCode,
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
