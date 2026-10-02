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
  // 对象树（1.1：展开一层取一层 + 对象搜索）
  dbSchemas: 'db_schemas',
  dbRelations: 'db_relations',
  searchObjects: 'search_objects',
  dbQuery: 'db_query',
  // SQL 编辑面（1.2：多段执行 / 取消 / EXPLAIN / 高亮分词）
  dbRunBatch: 'db_run_batch',
  dbCancel: 'db_cancel',
  explainStatement: 'explain_statement',
  highlightSql: 'highlight_sql',
  // 写回与事务（1.4：一批一次事务 / 主键定位 / 只读拦截 / 危险语句判定）
  dbWriteBatch: 'db_write_batch',
  dbPrimaryKey: 'db_primary_key',
  editsToDml: 'edits_to_dml',
  statementRisk: 'statement_risk',
  dbReadOnly: 'db_read_only',
  dbProbe: 'db_probe',
  // 连接列表（配置落盘 + 口令进系统凭据管理器）
  connectionsList: 'connections_list',
  connectionSave: 'connection_save',
  connectionDelete: 'connection_delete',
  // 服务端条件浏览（只生成 SQL，执行仍走 dbQuery）
  browseSql: 'browse_sql',
  // 单行详情的值检查（纯计算，不碰数据库）
  inspectRow: 'inspect_row',
  // 外键元数据（FR-DATA-06：两个方向的跳转都靠它）
  dbForeignKeys: 'db_foreign_keys',
  // 工作区（alpha 2.0：列目录 / 读文本文件；写面归 2.1 段）
  workspaceListDirectory: 'workspace_list_directory',
  workspaceReadFile: 'workspace_read_file',
  // 工作区历史与会话恢复（2.0：上次打开的根 / 最近打开两份清单）
  workspaceHistory: 'workspace_history',
  workspaceOpened: 'workspace_opened',
  workspaceClosed: 'workspace_closed',
  workspaceOpenTabs: 'workspace_open_tabs',
  // 工作区写面（2.1：新建 / 重命名 / 移动 / 删除走回收站）
  workspaceCreate: 'workspace_create',
  workspaceRename: 'workspace_rename',
  workspaceMove: 'workspace_move',
  workspaceDeletionSummary: 'workspace_deletion_summary',
  workspaceDelete: 'workspace_delete',
  // 在资源管理器 / 终端打开（2.1）
  workspaceReveal: 'workspace_reveal',
  // 编辑面（2.2：行结构 / 高亮分词）
  workspaceReadLines: 'workspace_read_lines',
  workspaceReadSpans: 'workspace_read_spans',
  // 外部改动（2.3：载入快照 / 比对）
  workspaceFileSnapshot: 'workspace_file_snapshot',
  workspaceCheckStaleness: 'workspace_check_staleness',
  workspaceRecordCursor: 'workspace_record_cursor',
  // 检索（2.4：按文件名 / 按内容，共用同一个匹配谓词）
  workspaceSearch: 'workspace_search',
  workspaceClampLine: 'workspace_clamp_line',
  // Markdown 预览（2.5：一份解析，界面只画模型）
  workspaceMarkdown: 'workspace_markdown',
  // 外观（2.8：深浅轴 / 配色轴 / 星云皮肤）
  appearanceGet: 'appearance_get',
  appearanceSet: 'appearance_set',
  // 命令面板（2.9：匹配与排序在 Rust 领域层）
  paletteSearch: 'palette_search',
  // 面板用的对象清单（一条 SQL 取回全部表/视图）
  dbPaletteObjects: 'db_palette_objects',
  // 命令使用历史（2.9：面板里「常用的」排前面）
  commandHistoryGet: 'command_history_get',
  commandHistoryRecord: 'command_history_record',
  commandHistoryClear: 'command_history_clear',
  // 按类型打开（2.3：文本 / 图片 / 二进制 / 太大）
  workspaceDecideOpen: 'workspace_decide_open',
  workspaceReadImage: 'workspace_read_image',
  // 保存（2.3：先判冲突再写）
  workspaceSave: 'workspace_save',
  // 跨文件替换（2.4：先预览，再逐个走保存护栏落盘）
  workspaceReplacePreview: 'workspace_replace_preview',
  workspaceReplaceApply: 'workspace_replace_apply',
  // 代码格式化（2.6：外部优先，没有则内置并如实说明）
  workspaceFormatTools: 'workspace_format_tools',
  workspaceFormatContent: 'workspace_format_content',
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

/** 对象种类（与领域层 `tree::ObjectKind` 的序列化名一致：snake_case）。 */
export type ObjectKindName =
  | 'table'
  | 'view'
  | 'materialized_view'
  | 'foreign_table'
  | 'sequence'
  | 'system'
  | 'other'

/** 树上的一个对象（1.1：在某个 schema 这一层里的一员）。 */
export interface ObjectNode {
  schema: string
  name: string
  kind: ObjectKindName
}

/** 一条搜索命中：对象 + **为什么命中**（界面要显示依据，不能只说"匹配"）。 */
export interface SearchHit {
  object: ObjectNode
  /** `qualified` = 命中限定名；`name` = 只命中对象名；`schema` = 只命中 schema 名 */
  matchedOn: 'qualified' | 'name' | 'schema'
}

/** 一次查询的结果：列名 + 行（每格文本或 null）+ 数值形态 + 截断与影响行数。 */
export interface QueryResult {
  columns: string[]
  rows: (string | null)[][]
  /** 每行的**数值形态**（该列解析得出数字才有值）：排序 / 筛选**按值比**，不拿显示串比 */
  numRows: (number | null)[][]
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

/** 启动 SQL 的逐条结果（FR-CONN-17）：**逐条发、逐条报** —— 一条失败不吞掉后面的。 */
export interface StartupOutcome {
  sql: string
  ok: boolean
  /** 失败时的可读原因（服务端原话 + 提示）；成功为 null */
  failure: DbFailure | null
}

/** 连接结果：服务端自述 + 启动 SQL 逐条结果。 */
export interface ConnectReport {
  info: ServerInfo
  startup: StartupOutcome[]
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

export function dbConnect(params: ConnectParams, startupSql?: string[]): Promise<ConnectReport> {
  return call(COMMANDS.dbConnect, { params, startupSql }, () => {
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

/** 生成**服务端条件浏览**的 SQL（FR-DATA-02；只生成，不执行）。
 *  契约：片段原样下发；出现分号（像多条语句）**拒绝**；排序写两处报冲突。 */
export function browseSql(request: {
  table: string
  schema?: string
  whereClause?: string
  orderBy?: string
  limit?: number
  offset?: number
  countOnly?: boolean
}): Promise<string> {
  return call(COMMANDS.browseSql, { ...request }, () => {
    throw { message: '浏览器旁路没有真库', hint: '请在 Tauri 外壳里生成（npm run tauri dev）。' } as DbFailure
  })
}
/** 值的形态（与领域层 `inspect::Shape` 同名同义；`binary` 带字节数）。 */
export type CellShape =
  | { kind: 'null' }
  | { kind: 'empty' }
  | { kind: 'jsonObject' }
  | { kind: 'jsonArray' }
  | { kind: 'binary'; byteCount: number }
  | { kind: 'scalarJson' }
  | { kind: 'text' }

export interface CellValue {
  shape: CellShape
  /** 展示文本（JSON 已美化、二进制已摘要） */
  display: string
  originalCharacterCount: number
  originalByteCount: number
  isTruncated: boolean
  lineCount: number
}

export interface RowField {
  columnName: string
  typeName: string
  value: CellValue
}

/** 单行详情的**值检查**（FR-DATA-05）：纯计算 —— 输入就是界面上那一行。 */
export function inspectRow(
  columns: string[],
  row: (string | null)[],
  typeNames?: string[],
): Promise<RowField[]> {
  return call(COMMANDS.inspectRow, { columns, typeNames, row }, () => [] as RowField[])
}
/** 外键的一条边（与领域层 `foreign_key::Edge` 同形）。 */
export interface FkEdge {
  constraintName: string | null
  fromTable: string
  fromSchema: string | null
  columns: string[]
  toTable: string
  toSchema: string | null
  referencedColumns: string[]
}

/** 读外键元数据（从 pg_constraint 取定义原文，解析规则在领域层 —— 只有一处实现）。 */
export function dbForeignKeys(): Promise<FkEdge[]> {
  return call(COMMANDS.dbForeignKeys, {}, () => [] as FkEdge[])
}

// ── 对象树（1.1：展开一层取一层 + 对象搜索）────────────────────────────────────────────
//
// 口径：**不在连接时把整库元数据拉光** —— 树的第一层只问 schema，展开某个 schema 才问它下面的
// 对象。搜索是纯函数（领域层 `tree::search`），只搜「界面上已经看见的那些」，与树里显示的必然一致。

/** 树的第一层：这台服务器上能看到的 schema。 */
export function dbSchemas(): Promise<string[]> {
  return call(COMMANDS.dbSchemas, {}, () => [] as string[])
}

/** 第二层：某个 schema 下的对象（**展开时才问**）。 */
export function dbRelations(schema: string): Promise<ObjectNode[]> {
  return call(COMMANDS.dbRelations, { schema }, () => [] as ObjectNode[])
}

/** 对象搜索：**纯函数在领域层**，本函数只把已加载的那一层递过去。 */
export function searchObjects(items: ObjectNode[], query: string): Promise<SearchHit[]> {
  return call(COMMANDS.searchObjects, { items, query }, () => [] as SearchHit[])
}

// ── SQL 编辑面（1.2：多段执行 / 取消 / EXPLAIN / 高亮）──────────────────────────────────

/** 多段执行里**一段**的结果（与表示层 `StatementOutcome` 同形）。 */
export interface StatementOutcome {
  sql: string
  ok: boolean
  result: QueryResult | null
  failure: DbFailure | null
  /** 这一段耗时（毫秒） */
  elapsedMs: number
}

/** **多段执行**：一次提交多条，逐段执行、逐段报告。`stopOnError` 缺省为真（一段失败就停）。 */
export function dbRunBatch(sql: string, stopOnError = true): Promise<StatementOutcome[]> {
  return call(COMMANDS.dbRunBatch, { sql, stopOnError }, () => {
    throw { message: '浏览器旁路没有真库', hint: '请在 Tauri 外壳里执行（npm run tauri dev）。' } as DbFailure
  })
}

/** **取消当前查询**：往服务端发取消请求（不是本地"不等了"）。取消后连接仍可用。 */
export function dbCancel(): Promise<boolean> {
  return call(COMMANDS.dbCancel, {}, () => false)
}

/** 生成 `EXPLAIN` 语句（只生成、不执行；**只对单条**，多段输入会被拒并说明原因）。 */
export function explainStatement(sql: string, analyze = false): Promise<string> {
  return call(COMMANDS.explainStatement, { sql, analyze }, () => {
    throw { message: '浏览器旁路没有真库', hint: '请在 Tauri 外壳里生成（npm run tauri dev）。' } as DbFailure
  })
}

/** 高亮用的词法单元种类（与领域层 `sql::TokenKind` 同名）。 */
export type SqlTokenKind =
  | 'keyword'
  | 'string'
  | 'number'
  | 'line_comment'
  | 'block_comment'
  | 'quoted_ident'
  | 'punctuation'
  | 'ident'

export interface SqlToken {
  kind: SqlTokenKind
  start: number
  end: number
}

/** 高亮分词：**词法在领域层**（与执行切分同一套规则），本函数只把原文递过去。 */
export function highlightSql(sql: string): Promise<SqlToken[]> {
  return call(COMMANDS.highlightSql, { sql }, () => [] as SqlToken[])
}

// ── 写回与事务（1.4）──────────────────────────────────────────────────────────────────

/** 一行的主键定位信息（写回靠它找"是哪一行"；无主键就不给编辑入口）。 */
export interface RowKey {
  columns: string[]
  values: (string | null)[]
}

/** 一处单元格编辑。 */
export interface CellEdit {
  schema: string | null
  table: string
  key: RowKey
  column: string
  value: string | null
  valueIsNumeric: boolean
}

/** 生成出来的 DML 与它的风险档。 */
export interface DmlStatement {
  sql: string
  target: string
  risk: 'safe' | 'confirm' | 'forbidden'
}

/** 编辑集 → 要执行的 DML（**只生成、不执行**：先看清将执行什么）。 */
export function editsToDml(edits: CellEdit[]): Promise<DmlStatement[]> {
  return call(COMMANDS.editsToDml, { edits }, () => {
    throw { message: '浏览器旁路没有真库', hint: '请在 Tauri 外壳里预览（npm run tauri dev）。' } as DbFailure
  })
}

/** 一批写回，一次事务：`rollback` 为真时跑完主动回滚（"提交前预览"的姿势）。 */
export function dbWriteBatch(statements: string[], rollback = false): Promise<StatementOutcome[]> {
  return call(COMMANDS.dbWriteBatch, { statements, rollback }, () => {
    throw { message: '浏览器旁路没有真库', hint: '请在 Tauri 外壳里写回（npm run tauri dev）。' } as DbFailure
  })
}

/** 一张表的主键列名（空 = 无主键 ⇒ 界面不给编辑入口）。 */
export function dbPrimaryKey(schema: string, table: string): Promise<string[]> {
  return call(COMMANDS.dbPrimaryKey, { schema, table }, () => [] as string[])
}

/** 单条 SQL 的危险判定：`safe` / `confirm` / `forbidden`。 */
export function statementRisk(sql: string): Promise<string> {
  return call(COMMANDS.statementRisk, { sql }, () => 'safe')
}

/** 当前连接是不是只读。 */
export function dbReadOnly(): Promise<boolean> {
  return call(COMMANDS.dbReadOnly, {}, () => false)
}
// ── 工作区（alpha 2.0）───────────────────────────────────────────────────────────────
//
// 只读面：列一层目录、读一个文本文件。**路径安全由 Rust 侧把关**（领域层 `workspace::resolve`
// + `is_contained`）—— 前端不自己拼路径判断，避免造第二份判据。

/** 目录里的一个条目。 */
export interface FsEntry {
  name: string
  /** 相对工作区根，**一律 `/` 分隔**（跨平台一致，也当 id 用） */
  relativePath: string
  /** `directory` / `file` / `symlink` */
  kind: 'directory' | 'file' | 'symlink'
  /** 可展开 = 目录（**符号链接即使指向目录也不展开**） */
  isExpandable: boolean
}

export interface FileContent {
  relativePath: string
  content: string
  bytes: number
  /** 语言键（文案在语言表里） */
  languageKey: string
}

/** 列一层目录（不递归：展开才读下一层）。`relativePath` 省略 = 工作区根。 */
export function workspaceListDirectory(
  workspaceRoot: string,
  relativePath?: string,
  showHidden?: boolean,
): Promise<FsEntry[]> {
  return call(COMMANDS.workspaceListDirectory, { workspaceRoot, relativePath, showHidden }, () => [] as FsEntry[])
}

/** 读一个文本文件（先过安全关；超上限如实报，不悄悄截断）。 */
export function workspaceReadFile(workspaceRoot: string, relativePath: string): Promise<FileContent> {
  return call(COMMANDS.workspaceReadFile, { workspaceRoot, relativePath }, () => {
    throw { message: '浏览器旁路没有工作区', hint: '请在 Tauri 外壳里打开工作区（npm run tauri dev）。' } as DbFailure
  })
}
/** 「最近打开」的一条记录。 */
export interface HistoryEntry {
  path: string
  openedAt: string
}

/** 工作区历史：两份清单 + **上次打开的根**（会话恢复用）。 */
export interface WorkspaceHistory {
  files: HistoryEntry[]
  workspaces: HistoryEntry[]
  currentRoot: string | null
  /** **上次开着的页签**（只记路径，按顺序）—— 恢复时按路径重读，盘上没有的跳过 */
  openTabs: string[]
  /** 每个页签的**光标锚**（相对路径 → 行号 + 行内偏移 + 那一行开头的锚） */
  cursors?: Record<string, CursorAnchor>
}

/** 恢复光标用的锚（**行号 + 行内偏移 + 那一行开头的片段**） */
export interface CursorAnchor {
  line: number
  column: number
  linePrefix: string
}

/** 读历史。读不出来时给**空历史 + 一句原因**（不抛：记录坏掉不该让工作区打不开）。 */
export function workspaceHistory(): Promise<{ history: WorkspaceHistory; warning: string | null }> {
  return call(COMMANDS.workspaceHistory, {}, () => ({
    history: { files: [], workspaces: [], currentRoot: null, openTabs: [] },
    warning: null,
  }))
}

/** 记一次「打开了这个工作区」：进「最近打开」+ 记为当前根。 */
export function workspaceOpened(workspaceRoot: string, at: string): Promise<{ history: WorkspaceHistory }> {
  return call(COMMANDS.workspaceOpened, { workspaceRoot, at }, () => ({
    history: { files: [], workspaces: [], currentRoot: null, openTabs: [] },
  }))
}

/** 关掉当前工作区：只清当前根，**保留**最近打开里的记录。 */
export function workspaceClosed(): Promise<{ history: WorkspaceHistory }> {
  return call(COMMANDS.workspaceClosed, {}, () => ({
    history: { files: [], workspaces: [], currentRoot: null, openTabs: [] },
  }))
}
/** 记下当前开着的页签（只记路径；内容以盘上为准）。 */
export function workspaceOpenTabs(workspaceRoot: string, paths: string[]): Promise<{ history: WorkspaceHistory }> {
  return call(COMMANDS.workspaceOpenTabs, { workspaceRoot, paths }, () => ({
    history: { files: [], workspaces: [], currentRoot: null, openTabs: [] },
  }))
}
// ── 工作区写面（alpha 2.1）──────────────────────────────────────────────────────────
//
// 判定在 Rust 领域层（名字校验 / 唯一名 / 同名不改 / 自吞拦截），**前端不自己拼路径或判安全**。

/** 新建 / 改名 / 移动的共同返回：落在哪、叫什么、是文件还是文件夹。 */
export interface CreatedEntry {
  relativePath: string
  name: string
  kind: 'directory' | 'file'
}

/** 删除前的读数（`truncated` = 数到上限就停了，界面照实写「N 项以上」）。 */
export interface DeletionSummary {
  items: number
  truncated: boolean
}

/** 失败的结构化原因（`kind` 决定界面说哪句话）。 */
export interface FileOpFailure {
  kind:
    | 'notContained'
    | 'emptyName'
    | 'illegalName'
    | 'alreadyExists'
    | 'notADirectory'
    | 'rootNotDeletable'
    | 'system'
  name?: string
  message?: string
}

/** 新建文件或文件夹（同名自动取「名字 2」；**不覆盖**）。 */
export function workspaceCreate(
  workspaceRoot: string,
  parentRelativePath: string,
  baseName: string,
  options: { extension?: string; directory?: boolean } = {},
): Promise<CreatedEntry> {
  return call(COMMANDS.workspaceCreate, {
    workspaceRoot,
    parentRelativePath,
    baseName,
    extension: options.extension,
    directory: options.directory ?? false,
  }, () => ({ relativePath: baseName, name: baseName, kind: (options.directory ? 'directory' : 'file') as 'directory' | 'file' }))
}

/** 重命名（**同名不算失败**，什么都不做）。 */
export function workspaceRename(workspaceRoot: string, relativePath: string, newName: string): Promise<CreatedEntry> {
  return call(COMMANDS.workspaceRename, { workspaceRoot, relativePath, newName }, () => ({ relativePath, name: newName, kind: 'file' as const }))
}

/** 拖拽移动（**不许把目录移进它自己或子孙**）。 */
export function workspaceMove(workspaceRoot: string, relativePath: string, intoRelativePath: string): Promise<CreatedEntry> {
  return call(COMMANDS.workspaceMove, { workspaceRoot, relativePath, intoRelativePath }, () => ({ relativePath, name: relativePath, kind: 'file' as const }))
}

/** 删除前的读数（先给读数让人确认，再真删）。 */
export function workspaceDeletionSummary(workspaceRoot: string, relativePath: string): Promise<DeletionSummary> {
  return call(COMMANDS.workspaceDeletionSummary, { workspaceRoot, relativePath }, () => ({ items: 1, truncated: false }))
}

/** 删除：**走回收站**（可撤销）；删不掉就报失败，不悄悄抹掉。 */
export function workspaceDelete(workspaceRoot: string, relativePath: string): Promise<string> {
  return call(COMMANDS.workspaceDelete, { workspaceRoot, relativePath }, () => 'file')
}
/** 打开计划：用哪个程序、带什么参数（判定在 Rust 领域层）。 */
export interface RevealPlan {
  program: string
  args: string[]
  workingDirectory: string | null
  used: 'explorer' | 'windowsTerminal' | 'powerShell' | 'commandPrompt'
}

/** 在资源管理器里定位（文件选中 / 目录进入）；`terminal = true` 则改为在终端打开。 */
export function workspaceReveal(
  workspaceRoot: string,
  relativePath: string,
  terminal = false,
): Promise<RevealPlan> {
  return call(
    COMMANDS.workspaceReveal,
    { workspaceRoot, relativePath, terminal },
    () => ({ program: 'explorer.exe', args: [], workingDirectory: null, used: 'explorer' as const }),
  )
}
// ── 编辑面（alpha 2.2）──────────────────────────────────────────────────────────────

export type CodeTokenKind = 'comment' | 'str' | 'number' | 'keyword'

/** 一段带位置的高亮分词（`start` / `end` 是**字节偏移**，相对整份原文）。 */
export interface CodeSpan {
  start: number
  end: number
  kind: CodeTokenKind
}

/** 一行：内容 + 它后面那个终止符（`null` = 最后一行没有终止符）+ 原文字节起点。 */
export interface CodeLine {
  text: string
  ending: string | null
  byteStart: number
}

export interface FileLines {
  relativePath: string
  lines: CodeLine[]
  /** 行号列要留几位（写死宽度会在第 100 行处挤掉数字） */
  gutterDigits: number
  dominantEnding: 'lf' | 'crlf' | 'cr' | 'ls' | 'ps' | 'nel' | null
  /** **混排**（同时有两种以上终止符）⇒ 界面要如实说 */
  mixedEndings: boolean
  languageKey: string
}

export interface FileSpans {
  relativePath: string
  spans: CodeSpan[]
  /** 原文**字节**长度（前端据此校验两边看的是同一份文本） */
  byteLen: number
}

/** 读一个文件的行结构（行号列宽 / 主换行符 / 是否混排）。 */
export function workspaceReadLines(workspaceRoot: string, relativePath: string): Promise<FileLines> {
  return call(COMMANDS.workspaceReadLines, { workspaceRoot, relativePath }, () => ({
    relativePath,
    lines: [],
    gutterDigits: 1,
    dominantEnding: null,
    mixedEndings: false,
    languageKey: 'lang.plainText',
  }))
}

/** 读一个文件的高亮分词（字节偏移）。 */
export function workspaceReadSpans(
  workspaceRoot: string,
  relativePath: string,
  languageKey?: string,
): Promise<FileSpans> {
  return call(
    COMMANDS.workspaceReadSpans,
    { workspaceRoot, relativePath, languageKey },
    () => ({ relativePath, spans: [], byteLen: 0 }),
  )
}
// ── 外部改动（alpha 2.3）────────────────────────────────────────────────────────────

/** 载入页签那一刻记下的磁盘状态（比对用）。 */
export interface LoadedFile {
  relativePath: string
  byteCount: number
  modifiedUnix: number | null
  contentHash: number
}

/** 页签内容与盘上现在那份的关系（**只有 unchanged 才安静**）。 */
export type Staleness = 'unchanged' | 'modified' | 'deleted' | 'replaced'

export interface StalenessReport {
  staleness: Staleness
  /** 人话（**说出下一步能做什么**）；`null` = 没变、不打扰 */
  note: string | null
}

/** 载入文件时取快照。 */
export function workspaceFileSnapshot(workspaceRoot: string, relativePath: string): Promise<LoadedFile> {
  return call(COMMANDS.workspaceFileSnapshot, { workspaceRoot, relativePath }, () => ({
    relativePath,
    byteCount: 0,
    modifiedUnix: null,
    contentHash: 0,
  }))
}

/** 比对快照与盘上现在那份（外部改动要如实说）。 */
export function workspaceCheckStaleness(workspaceRoot: string, loaded: LoadedFile): Promise<StalenessReport> {
  return call(COMMANDS.workspaceCheckStaleness, { workspaceRoot, loaded }, () => ({
    staleness: 'unchanged' as const,
    note: null,
  }))
}
/** 记下某个页签的光标位置（行号 + 行内偏移；锚由 Rust 侧从内容里取）。 */
export function workspaceRecordCursor(
  workspaceRoot: string,
  relativePath: string,
  line: number,
  column: number,
): Promise<{ history: WorkspaceHistory }> {
  return call(
    COMMANDS.workspaceRecordCursor,
    { workspaceRoot, relativePath, line, column },
    () => ({ history: { files: [], workspaces: [], currentRoot: null, openTabs: [] } }),
  )
}
// ── 检索（alpha 2.4）────────────────────────────────────────────────────────────────

export interface ContentHit {
  relativePath: string
  line: number
  snippet: string
}

export interface ContentGroup {
  relativePath: string
  hits: ContentHit[]
}

/** **跳过报告**：跳过 ≠ 通过（二进制 / 超大 / 读不了各记一笔，界面要看得见）。 */
export interface SkipReport {
  binary: number
  tooLarge: number
  unreadable: number
}

export interface SearchOutcome {
  /** 按文件名找到的（相对路径） */
  files: string[]
  groups: ContentGroup[]
  skips: SkipReport
  scannedFiles: number
  /** 命中总数到达上限而提前停止（界面要如实提示） */
  truncated: boolean
  /** 本次真正用的上限（界面照它说话，不写死） */
  limit: number
}

/** 工作区检索：`byContent = false` 只看名字（快），`true` 逐个读内容并按行命中。 */
export function workspaceSearch(
  workspaceRoot: string,
  query: string,
  options: { byContent?: boolean; showHidden?: boolean; limit?: number; maxDepth?: number } = {},
): Promise<SearchOutcome> {
  return call(
    COMMANDS.workspaceSearch,
    {
      workspaceRoot,
      query,
      byContent: options.byContent ?? false,
      showHidden: options.showHidden ?? false,
      limit: options.limit,
      maxDepth: options.maxDepth,
    },
    () => ({ files: [], groups: [], skips: { binary: 0, tooLarge: 0, unreadable: 0 }, scannedFiles: 0, truncated: false, limit: 200 }),
  )
}

/** 跳到命中行前把行号**夹进真实行数**（文件可能在检索之后被改短了）。 */
export function workspaceClampLine(workspaceRoot: string, relativePath: string, line: number): Promise<number> {
  return call(COMMANDS.workspaceClampLine, { workspaceRoot, relativePath, line }, () => line)
}
// ── Markdown 预览（alpha 2.5）──────────────────────────────────────────────────────

/** 行内 span（一段文字 + 是否加粗/斜体/代码 + 链接目标）。 */
export interface MdSpan {
  text: string
  bold: boolean
  italic: boolean
  code: boolean
  target: string | null
}

export type MdColumnAlignment = 'none' | 'left' | 'center' | 'right'

/** 块级模型的成员（**没有可编辑控件**：预览是只读的，这条是结构上挡住的）。 */
export type MdBlockKind =
  | { type: 'heading'; level: number; spans: MdSpan[] }
  | { type: 'paragraph'; spans: MdSpan[] }
  | { type: 'codeFence'; language: string | null; text: string }
  | {
      type: 'listItem'
      number: number | null
      /** 任务项勾选态；`null` = 不是任务项（复选框已从正文里摘出） */
      checked: boolean | null
      spans: MdSpan[]
      children: MdBlock[]
    }
  | { type: 'table'; alignments: MdColumnAlignment[]; header: MdSpan[][]; rows: MdSpan[][][] }
  | { type: 'quote'; children: MdBlock[] }
  | { type: 'rule' }

export interface MdBlock {
  /** 起始行（1 起）—— 跟随滚动时把行映射到预览锚点要用 */
  line: number
  kind: MdBlockKind
}

export interface MdDocument {
  version: number
  blocks: MdBlock[]
}

/** 解析 Markdown 成块级模型（解析在 Rust 领域层，一份实现两处消费）。 */
export function workspaceMarkdown(workspaceRoot: string, relativePath: string): Promise<MdDocument> {
  return call(COMMANDS.workspaceMarkdown, { workspaceRoot, relativePath }, () => ({ version: 1, blocks: [] }))
}
// ── 外观（alpha 2.8）────────────────────────────────────────────────────────────────

/** 落盘偏好（与 Rust 侧 `Appearance` 同形）。 */
export interface Appearance {
  mode: 'followSystem' | 'alwaysDark' | 'alwaysLight'
  scheme: 'techBlue' | 'beanGreen' | 'roseGold' | 'stardust'
  /** 星云皮肤开关；**缺省开** */
  nebulaSkin: boolean
}

/** Rust 算好的 DOM 取值（`dataTheme` 为 `null` = 不设那个属性）。 */
export interface DomAppearance {
  dataTheme: 'dark' | 'light' | null
  dataScheme: string
  nebula: boolean
  isDark: boolean
}

export interface AppearancePayload {
  appearance: Appearance
  dom: DomAppearance
  warning?: string | null
}

/** 读外观偏好（`systemIsDark` 由前端给 —— 本命令只算"最终该长什么样"）。 */
export function appearanceGet(systemIsDark: boolean): Promise<AppearancePayload> {
  return call(COMMANDS.appearanceGet, { systemIsDark }, () => ({
    appearance: { mode: 'followSystem', scheme: 'stardust', nebulaSkin: true },
    dom: { dataTheme: null, dataScheme: 'stardust', nebula: systemIsDark, isDark: systemIsDark },
    warning: null,
  }))
}

/** 改外观偏好（**部分更新**：只传要改的那几项）。 */
export function appearanceSet(
  patch: { mode?: Appearance['mode']; scheme?: Appearance['scheme']; nebulaSkin?: boolean },
  systemIsDark: boolean,
): Promise<{ appearance: Appearance; dom: DomAppearance }> {
  return call(
    COMMANDS.appearanceSet,
    { mode: patch.mode, scheme: patch.scheme, nebulaSkin: patch.nebulaSkin, systemIsDark },
    () => ({
      appearance: { mode: patch.mode ?? 'followSystem', scheme: patch.scheme ?? 'stardust', nebulaSkin: patch.nebulaSkin ?? true },
      dom: { dataTheme: null, dataScheme: patch.scheme ?? 'stardust', nebula: systemIsDark, isDark: systemIsDark },
    }),
  )
}
// ── 命令面板（alpha 2.9）────────────────────────────────────────────────────────────

export interface PaletteItem {
  id: string
  title: string
  keywords: string[]
  group: string | null
}

export interface PaletteMatch {
  item: PaletteItem
  score: number
  /** 标题里命中字符的**字符位置**（界面用来高亮） */
  highlighted: number[]
  tier: 'exact' | 'prefix' | 'wordPrefix' | 'substring' | 'acronym' | 'subsequence' | 'keywordOnly'
}

/** 命令面板的匹配与排序（**匹配只有一处实现**，在 Rust 领域层）。 */
export function paletteSearch(query: string, items: PaletteItem[], limit = 50): Promise<PaletteMatch[]> {
  return call(COMMANDS.paletteSearch, { query, items, limit }, () =>
    items
      .filter((item) => item.title.toLowerCase().includes(query.trim().toLowerCase()))
      .slice(0, limit)
      .map((item) => ({ item, score: 0, highlighted: [], tier: 'substring' as const })),
  )
}
/** 面板里可搜的数据库对象（schema + 名 + 种类）。 */
export interface PaletteObject {
  schema: string
  name: string
  kind: string
}

/** 面板用的对象清单：**一条 SQL 取回全部表 / 视图**（不逐个 schema 问）。连不上就给空。 */
export function dbPaletteObjects(): Promise<PaletteObject[]> {
  return call(COMMANDS.dbPaletteObjects, {}, () => [] as PaletteObject[])
}

// ── 命令使用历史（alpha 2.9）────────────────────────────────────────────────────────

export interface CommandHistoryPayload {
  history: { entries: Record<string, { count: number; lastUsed: number }> }
  /** 已排好序的命令 id（**常用优先、同等常用看谁更近**；排序在 Rust 领域层） */
  ranked: string[]
}

/** 读命令使用历史（面板用它把常用的排在前面）。 */
export function commandHistoryGet(): Promise<CommandHistoryPayload> {
  return call(COMMANDS.commandHistoryGet, {}, () => ({ history: { entries: {} }, ranked: [] }))
}

/** 记一次「用了这条命令」：**记完就落盘**（淘汰只在写盘前做一次）。 */
export function commandHistoryRecord(commandId: string, at: number): Promise<CommandHistoryPayload> {
  return call(COMMANDS.commandHistoryRecord, { commandId, at }, () => ({ history: { entries: {} }, ranked: [] }))
}

/** 清掉命令使用历史。 */
export function commandHistoryClear(): Promise<CommandHistoryPayload> {
  return call(COMMANDS.commandHistoryClear, {}, () => ({ history: { entries: {} }, ranked: [] }))
}


// ── 按类型打开（alpha 2.3 遗留项）────────────────────────────────────────────────────

/** 该怎么打开这个文件（判定在 Rust 领域层 `open_as`）。 */
export type OpenAs =
  | { kind: 'text'; languageKey: string }
  | { kind: 'image'; format: 'png' | 'jpeg' | 'gif' | 'webp' | 'bmp' }
  | { kind: 'binary' }
  | { kind: 'tooLarge'; bytes: number; limit: number }

export interface OpenDecision {
  relativePath: string
  openAs: OpenAs
  /** 界面直接显示的一句说明（`null` = 正常文本，不打扰） */
  note: string | null
  /** 图片的 MIME（`null` = 不是图片） */
  imageMime: string | null
}

/** 判一个文件该怎么打开（**只读头部**：大文件不整个读进来）。 */
export function workspaceDecideOpen(workspaceRoot: string, relativePath: string): Promise<OpenDecision> {
  return call(COMMANDS.workspaceDecideOpen, { workspaceRoot, relativePath }, () => ({
    relativePath,
    openAs: { kind: 'text' as const, languageKey: 'lang.plainText' },
    note: null,
    imageMime: null,
  }))
}

/** 读图片字节（base64）供 `data:` 显示。 */
export function workspaceReadImage(workspaceRoot: string, relativePath: string): Promise<string> {
  return call(COMMANDS.workspaceReadImage, { workspaceRoot, relativePath }, () => '')
}


// ── 保存（alpha 2.3 遗留项）────────────────────────────────────────────────────────

/** 保存的判定（与 Rust 侧 `SaveDecision` 同形）。 */
export type SaveDecision =
  | { kind: 'write'; recreated: boolean }
  | { kind: 'nothingToDo' }
  | { kind: 'conflict'; staleness: 'modified' | 'deleted' | 'replaced' | 'unchanged' }

export interface SaveReport {
  relativePath: string
  decision: SaveDecision
  /** 拒绝时的一句说明（**说清盘上是什么、下一步能选什么**） */
  note: string | null
  /** 写成功后的**新快照**（界面要更新它，否则下次保存会误报冲突） */
  snapshot: LoadedFile | null
}

/**
 * 保存一个文件（**先判冲突再写**）。
 *
 * `loaded` 必须是**页签打开时记的那份快照**（基线）——在这里现读盘会把基线换成"盘上现在这份"，
 * 冲突判定当场失真。
 */
export function workspaceSave(
  workspaceRoot: string,
  relativePath: string,
  content: string,
  savedContent: string,
  loaded: LoadedFile,
  force = false,
): Promise<SaveReport> {
  return call(
    COMMANDS.workspaceSave,
    { workspaceRoot, relativePath, content, savedContent, loaded, force },
    () => ({ relativePath, decision: { kind: 'nothingToDo' as const }, note: null, snapshot: null }),
  )
}


// ── 跨文件替换（alpha 2.4）──────────────────────────────────────────────────────────

export interface ReplacePreviewFile {
  relativePath: string
  count: number
  changes: { line: number; before: string; after: string; count: number }[]
}

export interface ReplacePreview {
  query: string
  replacement: string
  files: ReplacePreviewFile[]
  /** 一起改了几处 */
  total: number
  /** 跳过（二进制 / 超大 / 读不了）—— **跳过 ≠ 没命中** */
  skips: SkipReport
  /** 人读的一句话（**说清影响面，再让人确认**） */
  summary: string
}

export interface ReplaceResult {
  relativePath: string
  count: number
  /** `written` / `conflict` / `skipped` */
  outcome: string
  note: string | null
}

export interface ReplaceApplied {
  results: ReplaceResult[]
  written: number
  conflicts: number
  totalChanges: number
}

/** 跨文件替换的**预览**（**不写盘**）。 */
export function workspaceReplacePreview(
  workspaceRoot: string,
  query: string,
  replacement: string,
  showHidden = false,
): Promise<ReplacePreview> {
  return call(
    COMMANDS.workspaceReplacePreview,
    { workspaceRoot, query, replacement, showHidden },
    () => ({
      query,
      replacement,
      files: [],
      total: 0,
      skips: { binary: 0, tooLarge: 0, unreadable: 0 },
      summary: '（浏览器旁路没有工作区）',
    }),
  )
}

/**
 * 跨文件替换的**落盘**：逐个文件走保存护栏（盘上被改过就拒，不写）。
 *
 * `snapshots` = 每份文件的**载入快照**（基线）；**缺基线的文件会被跳过并说明** ——
 * 没有基线就无法判断盘上有没有被别处改过。
 */
export function workspaceReplaceApply(
  workspaceRoot: string,
  query: string,
  replacement: string,
  snapshots: Record<string, LoadedFile>,
  options: { showHidden?: boolean; force?: boolean } = {},
): Promise<ReplaceApplied> {
  return call(
    COMMANDS.workspaceReplaceApply,
    {
      workspaceRoot,
      query,
      replacement,
      snapshots,
      showHidden: options.showHidden ?? false,
      force: options.force ?? false,
    },
    () => ({ results: [], written: 0, conflicts: 0, totalChanges: 0 }),
  )
}


// ── 代码格式化（alpha 2.6）──────────────────────────────────────────────────────────

export interface FormatToolProbe {
  executable: string
  displayName: string
  available: boolean
  path: string | null
  /** 探测到的版本（**探不到就是 null**，绝不编造） */
  version: string | null
}

export interface FormatToolsPayload {
  languageKey: string
  tools: FormatToolProbe[]
}

export interface FormatOutcome {
  /** 格式化后的内容（没改动时等于原文） */
  content: string
  changed: boolean
  /** 这句话如实说「用了哪一个工具 / 内置做了什么」 */
  note: string
  /** `external` / `builtin` / `refused` */
  engine: string
  problem: string | null
}

/** 探一个文件的候选格式化工具（真探：找路径 + 真跑版本旗标）。 */
export function workspaceFormatTools(workspaceRoot: string, relativePath: string): Promise<FormatToolsPayload> {
  return call(COMMANDS.workspaceFormatTools, { workspaceRoot, relativePath }, () => ({
    languageKey: 'lang.plainText',
    tools: [],
  }))
}

/** 格式化一段内容（**不落盘**：落盘仍走 workspaceSave 的冲突护栏）。 */
export function workspaceFormatContent(
  workspaceRoot: string,
  relativePath: string,
  content: string,
  preferBuiltin = false,
): Promise<FormatOutcome> {
  return call(
    COMMANDS.workspaceFormatContent,
    { workspaceRoot, relativePath, content, preferBuiltin },
    () => ({ content, changed: false, note: '（浏览器旁路没有工作区）', engine: 'refused', problem: null }),
  )
}
