// 前端 ↔ Rust（Tauri 2）的唯一出入口（windows/App/src/ipc.ts）
//
// 三条口径：
//   1. **命令名只有一份**：`COMMANDS` 里的字符串必须与 `src-tauri/src/lib.rs` 里
//      `#[tauri::command]` 的函数名、以及 `generate_handler![]` 的注册项一致；
//   2. **浏览器旁路**：不在 Tauri 里跑时（`npm run dev` 直接开浏览器、vitest）走确定性 mock ——
//      只为开发与自测，**不是产品形态**（真形态 = WebView2 承载）；
//   3. 窗口取数**不带整份数据**：一次只取 `len` 行（Rust 侧切片，见 `grid/windowing.ts`）。

import { invoke } from '@tauri-apps/api/core'

export const COMMANDS = {
  appInfo: 'app_info',
  datasetSummary: 'dataset_summary',
  gridWindow: 'grid_window',
} as const

export interface AppInfo {
  name: string
  version: string
  platform: string
  backend: 'tauri' | 'browser'
}

export interface DatasetSummary {
  rows: number
  cols: number
  bytes: number
  textCol: number
  colNames: string[]
}

export interface GridWindow {
  total: number
  start: number
  cells: string[][]
}

export interface GridWindowRequest {
  rows: number
  cols: number
  seed: number
  orderDesc: boolean
  start: number
  len: number
}

/** 合成数据集的列名规则（与 Rust `Core::dataset::generate` 逐条一致：每 5 列的第 5 列是短文本）。 */
export function mockColumnNames(cols: number): string[] {
  return Array.from({ length: cols }, (_, col) => (col % 5 === 4 ? `label_${col}` : `metric_${col}`))
}

/** 合成数据集的行窗口请求用的默认种子（与基准台同一颗：同 seed 同结果，任何人可复跑）。 */
export const DEFAULT_GRID_SEED = 20260928

export function inTauri(): boolean {
  return typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window
}

async function call<T>(command: string, args: Record<string, unknown>, fallback: () => T): Promise<T> {
  if (!inTauri()) return fallback()
  return (await invoke(command, args)) as T
}

export function appInfo(): Promise<AppInfo> {
  return call(COMMANDS.appInfo, {}, () => ({
    name: 'Doyah Studio',
    version: '0.2.0',
    platform: 'browser',
    backend: 'browser' as const,
  }))
}

export function datasetSummary(rows: number, cols: number, seed: number): Promise<DatasetSummary> {
  return call(COMMANDS.datasetSummary, { rows, cols, seed }, () => ({
    rows,
    cols,
    bytes: rows * cols * 8,
    textCol: 0,
    colNames: mockColumnNames(cols),
  }))
}

export function gridWindow(request: GridWindowRequest): Promise<GridWindow> {
  const { rows, cols, start, len } = request
  return call(COMMANDS.gridWindow, { ...request }, () => ({
    total: rows,
    start,
    cells: mockCells(rows, cols, start, len),
  }))
}

/** 确定性 mock（同样的入参给同样的输出）；只在浏览器旁路用。 */
export function mockCells(rows: number, cols: number, start: number, len: number): string[][] {
  const out: string[][] = []
  for (let row = start; row < Math.min(rows, start + len); row += 1) {
    const cells: string[] = []
    for (let col = 0; col < cols; col += 1) {
      cells.push(col === 0 ? `行 ${String(row + 1).padStart(6, '0')}` : `${(row * (col + 3)) % 100000}.${col}`)
    }
    out.push(cells)
  }
  return out
}
