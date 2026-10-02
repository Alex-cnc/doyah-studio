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
  // 数据库域（真库链路）—— 与 src-tauri/src/lib.rs 的 generate_handler![] 双向一致
  dbConnect: 'db_connect',
  dbDisconnect: 'db_disconnect',
  dbTables: 'db_tables',
  dbQuery: 'db_query',
  dbProbe: 'db_probe',
  // 连接列表（配置落盘 + 口令进系统凭据管理器）
  connectionsList: 'connections_list',
  connectionSave: 'connection_save',
  connectionDelete: 'connection_delete',
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

// ── 数据库域（真库链路）──────────────────────────────────────────────────────────────
//
// 契约来源：领域层 `windows/Db`（连接配置 / 连接串解析）+ 概要设计 §8.5.2-4（驱动映射）。

/** 连接入参。口令**即用即弃**：只经 IPC 传给驱动，不落配置、不进连接串、不进日志。 */
export interface ConnectParams {
  host: string
  port: number
  database: string
  user: string
  password?: string
  sslMode?: string
}

/** 服务端自述（连上后第一件事：把"连到了哪儿"如实显示出来）。 */
export interface ServerInfo {
  version: string
  database: string
  user: string
  serverEncoding: string
  currentSchema: string | null
}

/** 对象树节点（本轮到「表 / 视图」这一层）。 */
export interface TableNode {
  schema: string
  name: string
  kind: string
}

/** 一次查询的结果：列名 + 行（每格文本或 null）+ 截断与影响行数。 */
export interface QueryResult {
  columns: string[]
  rows: (string | null)[][]
  returned: number
  truncated: boolean
  affected: number | null
}

/** 失败：**服务端原话** + 一句"该往哪儿看"（两段都显示，不合并成一句"失败了"）。 */
export interface DbFailure {
  message: string
  hint: string
}

export interface ProbeReport {
  info: ServerInfo
  tableCount: number
  schemas: string[]
  selectOne: string | null
}

/** 本机**专用实验库**（自己起的测试集群：端口 5433、trust 认证；不动本机现有那台）。
 *  写在这里只为减少手输 —— 它**不是**产品默认值（产品默认值在领域层的 `DatabaseType` 上）。 */
export const LAB_CONNECTION: ConnectParams = {
  host: '127.0.0.1',
  port: 5433,
  database: 'doyah_lab',
  user: 'doyah',
  sslMode: 'disable',
}

export function dbConnect(params: ConnectParams): Promise<ServerInfo> {
  return call(COMMANDS.dbConnect, { params }, () => {
    throw { message: '浏览器旁路没有真库', hint: '请在 Tauri 外壳里连库（npm run tauri dev）。' } as DbFailure
  })
}

export function dbDisconnect(): Promise<boolean> {
  return call(COMMANDS.dbDisconnect, {}, () => false)
}

export function dbTables(): Promise<TableNode[]> {
  return call(COMMANDS.dbTables, {}, () => [] as TableNode[])
}

export function dbQuery(sql: string): Promise<QueryResult> {
  return call(COMMANDS.dbQuery, { sql }, () => {
    throw { message: '浏览器旁路没有真库', hint: '请在 Tauri 外壳里执行（npm run tauri dev）。' } as DbFailure
  })
}

export function dbProbe(): Promise<ProbeReport> {
  return call(COMMANDS.dbProbe, {}, () => {
    throw { message: '浏览器旁路没有真库', hint: '请在 Tauri 外壳里自检（npm run tauri dev）。' } as DbFailure
  })
}

// ── 连接列表（配置落盘 + 口令进系统凭据管理器）─────────────────────────────────────────

/** 保存过的一条连接。**没有口令字段** —— 口令只在系统凭据管理器里。 */
export interface SavedConnection {
  id: string
  name: string
  dbType: string
  host: string
  port: number
  database: string
  username: string
  sslMode: string
  timeout: number
  schemaVersion: number
  environment?: string | null
  colorTag?: string | null
  isReadOnly: boolean
  startupSql?: string | null
  group?: string | null
}

export interface ConnectionSaveRequest {
  id: string
  name: string
  host: string
  port: number
  database: string
  user: string
  sslMode?: string
  isReadOnly: boolean
  /** 只用于本次写入系统凭据管理器；**绝不进配置文件**。 */
  password?: string
  rememberPassword: boolean
}

export function connectionsList(): Promise<SavedConnection[]> {
  return call(COMMANDS.connectionsList, {}, () => [] as SavedConnection[])
}

export function connectionSave(request: ConnectionSaveRequest): Promise<SavedConnection[]> {
  return call(COMMANDS.connectionSave, { ...request }, () => [] as SavedConnection[])
}

export function connectionDelete(id: string): Promise<SavedConnection[]> {
  return call(COMMANDS.connectionDelete, { id }, () => [] as SavedConnection[])
}
