// 前端 ↔ Rust（Tauri 2）的唯一出入口（platform/windows/App/src/ipc.ts）
//
// 三条口径：
//   1. **命令名只有一份**：`COMMANDS` 里的字符串必须与 `src-tauri/src/lib.rs` 里
//      `#[tauri::command]` 的函数名、以及 `generate_handler![]` 的注册项一致；
//   2. **浏览器旁路**：不在 Tauri 里跑时（`npm run dev` 直接开浏览器、vitest）走确定性 mock ——
//      只为开发与自测，**不是产品形态**（真形态 = WebView2 承载）；
//   3. 窗口取数**不带整份数据**：一次只取 `len` 行（Rust 侧切片，见 `grid/windowing.ts`）。

import { tNow } from './i18n'

/**
 * 浏览器旁路的统一说法（**19 处原本各写一遍中文**）。
 *
 * 为什么集中：这些提示只出现在"没在外壳里跑"的开发场景，但**也要双语** ——
 * 切英文时留着一句中文，用户看到的就还是不一致。`action` 走语言表（`ipc.action.*`）。
 */
function bypassDb(action: string) {
  return {
    message: tNow('ipc.bypass.db'),
    hint: tNow('ipc.bypass.hint', { action: tNow(action as never) }),
  }
}

/** 工作区侧的同一件事。 */
function bypassWorkspace(action: string) {
  return {
    message: tNow('ipc.bypass.workspace'),
    hint: tNow('ipc.bypass.hint', { action: tNow(action as never) }),
  }
}

import { invoke } from '@tauri-apps/api/core'

export const COMMANDS = {
  appInfo: 'app_info',
  // 插件清单（唯一出处 = 领域层 `Db/src/plugins.rs`；契约依据 = 概设 §3.52 / §8.5.8）
  pluginsManifest: 'plugins_manifest',
  datasetSummary: 'dataset_summary',
  gridWindow: 'grid_window',
  // 数据库域（真库链路）—— 与 src-tauri/src/lib.rs 的 generate_handler![] 双向一致
  dbConnect: 'db_connect',
  dbDisconnect: 'db_disconnect',
  dbTables: 'db_tables',
  // 对象树（1.1：展开一层取一层 + 对象搜索）
  dbSchemas: 'db_schemas',
  dbRelations: 'db_relations',
  dbColumns: 'db_columns',
  searchObjects: 'search_objects',
  dbQuery: 'db_query',
  // SQL 编辑面（1.2：多段执行 / 取消 / EXPLAIN / 高亮分词）
  dbRunBatch: 'db_run_batch',
  dbCancel: 'db_cancel',
  explainStatement: 'explain_statement',
  highlightSql: 'highlight_sql',
  // 编辑面静态检查（FR-EDIT-03 / FR-EDIT-56）：规则只在领域层 `Db/src/lint.rs` 判一遍
  diagnoseSql: 'diagnose_sql',
  // 格式化 SQL（FR-EDIT-22）：查询编辑面没有文件 ⇒ 单独一条命令（语言固定 SQL、无路径检查）
  sqlFormat: 'sql_format',
  // 查询参数（FR-EXEC-17）：扫描占位符 / 绑定值 —— 两条都是纯函数，不碰连接
  sqlParameters: 'sql_parameters',
  sqlBindParameters: 'sql_bind_parameters',
  // 写回与事务（1.4：一批一次事务 / 主键定位 / 只读拦截 / 危险语句判定）
  dbWriteBatch: 'db_write_batch',
  dbPrimaryKey: 'db_primary_key',
  editsToDml: 'edits_to_dml',
  statementRisk: 'statement_risk',
  dbReadOnly: 'db_read_only',
  // 表结构与 DDL（1.5）
  dbTableShape: 'db_table_shape',
  generateDdl: 'generate_ddl',
  dbRunDdl: 'db_run_ddl',
  // Schema 对比与同步（FR-DDL-04）：快照对快照 —— 两个库不在同一次会话里也能比
  schemaSnapshot: 'schema_snapshot',
  schemaDiffPlan: 'schema_diff_plan',
  // 导入导出（1.6：CSV / JSON / Excel；原子落盘、一个事务写入）
  exportToFile: 'export_to_file',
  // 备份（FR-IO-04：封装本机 pg_dump —— 先摊命令行，再真跑）
  backupPlan: 'backup_plan',
  backupRun: 'backup_run',
  backupCancel: 'backup_cancel',
  // 备份**跑着的读数**（FR-IO-04）：界面每 500ms 问一次，跑完就返回 null
  backupProgress: 'backup_progress',
  previewImport: 'preview_import',
  runImport: 'run_import',
  xlsxToCsv: 'xlsx_to_csv',
  // 库与服务器管理面（1.7：读数只读；危险操作只生成语句）
  adminDatabases: 'admin_databases',
  adminSessions: 'admin_sessions',
  adminTableStats: 'admin_table_stats',
  slowQueries: 'slow_queries',
  maintenanceSql: 'maintenance_sql',
  terminateSql: 'terminate_sql',
  grantPreview: 'grant_preview',
  confirmDropDatabase: 'confirm_drop_database',
  dbProbe: 'db_probe',
  // 连接列表（配置落盘 + 口令进系统凭据管理器）
  connectionsList: 'connections_list',
  connectionSave: 'connection_save',
  connectionDelete: 'connection_delete',
  // 已保存查询（FR-EDIT-14：落盘 + 重名覆盖）
  savedQueriesList: 'saved_queries_list',
  savedQuerySave: 'saved_query_save',
  savedQueryDelete: 'saved_query_delete',
  // 查询自动归档（FR-EDIT-31：执行过的 SQL 按天落盘；格式与合并规则在 `workspace/archive.ts`）
  archiveRead: 'archive_read',
  archiveWrite: 'archive_write',
  archiveDays: 'archive_days',
  // Retro 周报包（FR-R-12-01 / -02）：只读扫目录 + 读一期正文
  retroPackages: 'retro_packages',
  retroReport: 'retro_report',
  // 媒体字节（FR-R-12-03）：回 ArrayBuffer，界面建 blob URL（不开 asset 协议）
  retroAsset: 'retro_asset',
  // 智能体设置（FR-AI-01：总开关 / 端点 / 模型 / 配额；密钥单独存，永不回显）
  agentSettingsGet: 'agent_settings_get',
  agentSettingsSave: 'agent_settings_save',
  agentKeySave: 'agent_key_save',
  agentKeyClear: 'agent_key_clear',
  // 自然语言 → SQL（FR-AI-02：先看要发什么 → 再真发一次；结果只进编辑器，不执行）
  agentGeneratePreview: 'agent_generate_preview',
  agentGenerateSql: 'agent_generate_sql',
  // 问诊断一次（FR-AI-03 第二片）：把面板上那份资料块原样发出去，只回正文
  agentDiagnosisAsk: 'agent_diagnosis_ask',
  agentHistoryList: 'agent_history_list',
  agentAuditList: 'agent_audit_list',
  // 连接配置面收口（S-1a）：逐项校验 / 换引擎联动默认值 / 从 URL 导入
  connectionValidate: 'connection_validate',
  connectionTypeDefaults: 'connection_type_defaults',
  connectionImportUrl: 'connection_import_url',
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
  // 内置终端（W-C 底部终端 · 2.7 · S-9a）：起会话 / 写入 / 读输出 / 关闭。
  // 命令名的单一出处仍在这里 —— 与 lib.rs 的 generate_handler![] 双向一致，
  // 界面的接线（谁调用、怎么显示）归 S-9b，本片只登记这四条名字。
  terminalOpen: 'terminal_open',
  terminalWrite: 'terminal_write',
  terminalRead: 'terminal_read',
  terminalClose: 'terminal_close',
} as const

export interface AppInfo {
  name: string
  version: string
  platform: string
  backend: 'tauri' | 'browser'
  /** 构建标识 · 提交短号（`tauri` 侧由 `build.rs` 注入；浏览器旁路给非真值 `browser`）。 */
  buildHead: string
  /** 构建标识 · 构建时刻 `MM-dd HH:mm`（浏览器旁路给空串）。 */
  buildTime: string
}

/** 插件清单里的一条（**形状跟领域层 `PluginDecl` 与命令层 `PluginEntry` 一一对应**）。 */
export interface PluginEntry {
  /** 稳定标识（进视图 id / 挂点键）。 */
  id: string
  /** 对账用的规范名；界面文案走 `i18n`。 */
  name: string
  version: string
  /** 界面目录名 = `App/src/plugins/<entry>/`。 */
  entry: string
  /** 能力位：`workspaces` / `database` / `notes`。 */
  capabilities: string[]
  /** 需要的宿主挂点（七类之一）。 */
  mounts: string[]
  /** 存储归属：`bundled` = 自带 / `host` = 宿主代管。 */
  storage: string
  /** **功能本体是否已实现**。骨架阶段为 `false` ⇒ 界面**如实显示"未开工"**。 */
  implemented: boolean
}

/** 清单自检发现的一条问题（`code` 稳定、不本地化）。 */
export interface PluginFinding {
  plugin: string
  code: string
  detail: string
}

/** 插件清单 + 自检（界面只消费这一份）。 */
export interface PluginsManifest {
  plugins: PluginEntry[]
  findings: PluginFinding[]
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
/**
 * 取插件清单（**唯一出处**在领域层；这里只做转发 + 浏览器旁路的空清单）。
 *
 * 浏览器旁路给**空清单**而不是编一份假清单：界面据此如实显示"没有插件"，
 * 与"清单为空 ⇒ 其挂点整体消失且不报错"（契约④）是同一套语义。
 */
export async function pluginsManifest(): Promise<PluginsManifest> {
  return call(COMMANDS.pluginsManifest, {}, () => ({ plugins: [], findings: [] }))
}

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
    buildHead: 'browser',
    buildTime: '',
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
// 契约来源：领域层 `platform/windows/Db`（连接配置 / 连接串解析）+ 概要设计 §8.5.2-4（驱动映射）。

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

/** 树第三层的一员：列名 + **数据类型原文**（FR-META-05；不缩写、不翻译）。 */
export interface ColumnNode {
  name: string
  dataType: string
}

/** 一个表 / 视图的列（第三层取数的返回形状）。 */
export interface TableColumns {
  schema: string
  table: string
  columns: ColumnNode[]
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
    throw bypassDb('ipc.action.connect') as DbFailure
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
    throw bypassDb('ipc.action.run') as DbFailure
  })
}

export function dbProbe(): Promise<ProbeReport> {
  return call(COMMANDS.dbProbe, {}, () => {
    throw bypassDb('ipc.action.selfCheck') as DbFailure
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
  /** 引擎（FR-CONN-02）；缺省走 Postgres 回退（回退值在命令层一处）。 */
  dbType?: string
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

/** 表单某一项不合法（**点名是哪一项**）。 */
export interface FieldProblem {
  field: 'name' | 'host' | 'port' | 'username'
  message: string
}

/** 换引擎时的那几项默认值（默认值挂在类型上，界面不自己写一份）。 */
export interface ConnectionTypeDefaults {
  dbType: string
  port: number
  sslMode: string
  schema: string | null
}

/** 从连接 URL 导入的结果。口令**只在这一条回执里**（不进配置、不进导出件）。 */
export interface ImportedUrl {
  dbType: string
  host: string
  port: number
  database: string
  user: string
  sslMode: string
  name: string
  password: string | null
  ignoredParameters: string[]
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

// ── 已保存查询（FR-EDIT-14）──────────────────────────────────────────────────────────────
//
// 形状与领域层 `Db/src/saved_query.rs` 一一对应（`rename_all = "camelCase"`）。
// 口径：**同名 = 覆盖**，但**未确认覆盖时服务端不写盘**（回 `saved: false` + `conflict`）——
// 冲突不走错误通道，界面才不用去匹配错误文案。

/** 一条已保存查询。 */
export interface SavedQuery {
  id: string
  name: string
  sql: string
  connectionId?: string | null
  connectionName?: string | null
  database?: string | null
  /** 保存时刻（ISO-8601 UTC，服务端给）。 */
  savedAt: string
  schemaVersion: number
}

export interface SavedQuerySaveRequest {
  id: string
  name: string
  sql: string
  connectionId?: string | null
  connectionName?: string | null
  database?: string | null
  /** 同名时是否覆盖（`false` ⇒ 回冲突、不写盘）。 */
  overwrite: boolean
}

export interface SavedQuerySaveReport {
  /** 这次是否真的写盘。 */
  saved: boolean
  /** 冲突时给出既有那条（界面据此提示「覆盖保存」）。 */
  conflict?: SavedQuery | null
  /** 写盘后的完整列表。 */
  queries: SavedQuery[]
}

/** 浏览器旁路的内存表（**只服务开发自测**：刷新即丢；真形态在 Tauri 外壳里落盘）。 */
let bypassSavedQueries: SavedQuery[] = []

function bypassSaveQuery(request: SavedQuerySaveRequest): SavedQuerySaveReport {
  const name = request.name.trim()
  const key = name.toLowerCase()
  const sameName = bypassSavedQueries.find((q) => q.name.trim().toLowerCase() === key)
  const sameId = bypassSavedQueries.find((q) => q.id === request.id)
  if (sameName && sameName.id !== request.id && !request.overwrite) {
    return { saved: false, conflict: sameName, queries: [...bypassSavedQueries] }
  }
  const record: SavedQuery = {
    id: sameId?.id ?? sameName?.id ?? request.id,
    name,
    sql: request.sql,
    connectionId: request.connectionId ?? null,
    connectionName: request.connectionName ?? null,
    database: request.database ?? null,
    savedAt: new Date().toISOString(),
    schemaVersion: 1,
  }
  const target = sameId ?? sameName
  bypassSavedQueries = target
    ? bypassSavedQueries.map((q) => (q.id === target.id ? record : q))
    : [...bypassSavedQueries, record]
  return { saved: true, conflict: null, queries: [...bypassSavedQueries] }
}

export function savedQueriesList(): Promise<SavedQuery[]> {
  return call(COMMANDS.savedQueriesList, {}, () => [...bypassSavedQueries])
}

export function savedQuerySave(request: SavedQuerySaveRequest): Promise<SavedQuerySaveReport> {
  return call(COMMANDS.savedQuerySave, { ...request }, () => bypassSaveQuery(request))
}

export function savedQueryDelete(id: string): Promise<SavedQuery[]> {
  return call(
    COMMANDS.savedQueryDelete,
    { id },
    () => {
      bypassSavedQueries = bypassSavedQueries.filter((q) => q.id !== id)
      return [...bypassSavedQueries]
    },
  )
}

// ── 查询自动归档（FR-EDIT-31）──────────────────────────────────────────────────────────
//
// 外壳只管「哪一天、放哪儿」（`App/src-tauri/src/archive.rs`）：**一天一份文件**，
// 内容是什么形状由 `workspace/archive.ts` 决定 —— 界面读回来的就是它自己写进去的那份。

/** 一天归档文件的内容与身份。 */
export interface ArchiveFile {
  /** 日期键 `YYYY-MM-DD`。 */
  dateKey: string
  /** 实际路径（界面要能照着去找）。 */
  path: string
  /** 文件内容（不存在时为空串）。 */
  content: string
  /** 内容字节数（UTF-8）。 */
  bytes: number
}

/** 浏览器旁路的归档（内存里存，刷新即丢 —— 旁路本来就不落盘）。 */
const bypassArchive = new Map<string, string>()

function bypassArchiveFile(dateKey: string, content: string): ArchiveFile {
  return {
    dateKey,
    path: `queries/${dateKey}.sql`,
    content,
    bytes: new TextEncoder().encode(content).length,
  }
}

export function archiveRead(dateKey: string): Promise<ArchiveFile> {
  return call(COMMANDS.archiveRead, { dateKey }, () => bypassArchiveFile(dateKey, bypassArchive.get(dateKey) ?? ''))
}

export function archiveWrite(dateKey: string, content: string): Promise<ArchiveFile> {
  return call(COMMANDS.archiveWrite, { dateKey, content }, () => {
    bypassArchive.set(dateKey, content)
    return bypassArchiveFile(dateKey, content)
  })
}

/** 盘上一天归档的读数（日期切换用）。 */
export interface ArchiveDay {
  /** 日期键 `YYYY-MM-DD`。 */
  dateKey: string
  /** 文件字节数（UTF-8）。 */
  bytes: number
}

/** 盘上真的有归档的日子（新的在前）；目录还不存在时是空清单。 */
export function archiveDays(): Promise<ArchiveDay[]> {
  return call(COMMANDS.archiveDays, {}, () =>
    [...bypassArchive.entries()]
      .map(([dateKey, content]) => ({ dateKey, bytes: new TextEncoder().encode(content).length }))
      .sort((left, right) => (left.dateKey < right.dateKey ? 1 : left.dateKey > right.dateKey ? -1 : 0)),
  )
}

// ── Retro 周报包（FR-R-12-01 / -02 · FR-R-13-08 的 M0 只读面）────────────────────────────
//
// 形状与领域层 `Db/src/retro_package.rs` 一一对应（`rename_all = "camelCase"`）。
// **判定不在这一层**：什么算一张卡、封面路径合不合法由 Rust 判完再给 ——
// 前端照着画，出错只显示「哪里读不出来」。

/** 一张周报卡片（左侧列表的一项）。 */
export interface RetroCard {
  /** 期号（= 包目录名；排序键与「打开哪一期」的键）。 */
  period: string
  /** 标题。 */
  title: string
  /** 日期范围起点（`YYYY-MM-DD`；包里没写就是空串）。 */
  dateStart: string
  /** 日期范围终点。 */
  dateEnd: string
  /** 标签（已去重）。 */
  tags: string[]
  /** 封面（包内相对路径；没有 / 不合法时为 null）。 */
  cover: string | null
  /** 生成时间（包里没写就是空串）。 */
  generatedAt: string
}

/** 一处「读不出来」（逐条显示，不让整批失败）。 */
export interface RetroProblem {
  /** 出问题的期号（目录名）。 */
  period: string
  /** 可读原因。 */
  message: string
}

/** 一处媒体的判定结果（**Rust 判完**：界面不再自己拼路径 / 判后缀 / 判文件在不在）。 */
export type RetroMediaState = 'ok' | 'missing' | 'rejected' | 'external' | 'unsupported'

export interface RetroMedia {
  /** 正文里写的原文（占位与取字节都用它）。 */
  target: string
  state: RetroMediaState
  /** `ok` 时是绝对落点（排错用）。 */
  path: string | null
  /** 外链 / 缺文件 / 越界 / 后缀不在白名单时给出的可读原因。 */
  reason: string | null
  /** `ok` 时的 MIME（建 blob 用）。 */
  mime: string | null
}

/** 一次扫描的结果。 */
export interface RetroSnapshot {
  /** 扫描根（空态要把这个路径显示给用户）。 */
  root: string
  cards: RetroCard[]
  problems: RetroProblem[]
}

/** 一期的正文（已解析成渲染模型）。 */
export interface RetroReport {
  period: string
  /** 正文文件路径。 */
  path: string
  /** 正文字节数。 */
  bytes: number
  /** 渲染模型（解析在 Rust 领域层 `markdown::parse`）。 */
  document: MdDocument
  /** 正文里每一处媒体在盘上的判定（能读的显示、读不了的占位 + 原因）。 */
  media: RetroMedia[]
}

/** 扫包目录（浏览器旁路：空库 + 一句说明用的根路径）。 */
export function retroPackages(): Promise<RetroSnapshot> {
  return call(COMMANDS.retroPackages, {}, () => ({
    root: '',
    cards: [],
    problems: [],
  }))
}

/** 读一期的正文；`period` 只认扫出来的目录名（Rust 侧会再校验一次）。 */
export function retroReport(period: string): Promise<RetroReport> {
  return call(COMMANDS.retroReport, { period }, () => {
    throw bypassWorkspace('ipc.action.retro') as unknown as RetroReport
  })
}

/**
 * 读一处媒体的字节（`FR-R-12-03`）。回的是 `ArrayBuffer`，界面自己建 `blob:` URL。
 *
 * **为什么不走 asset 协议**：那要开 `protocol-asset` 并给 CSP 放一个文件协议源；
 * 而本仓的 CSP 口径是「出网只走 IPC」，媒体字节走命令回来更窄（路径校验也还在 Rust 里）。
 */
export function retroAsset(period: string, target: string): Promise<ArrayBuffer> {
  if (!inTauri()) throw bypassWorkspace('ipc.action.retro')
  return invoke<ArrayBuffer>(COMMANDS.retroAsset, { period, target })
}

// ── 智能体设置（FR-AI-01）──────────────────────────────────────────────────────────────
//
// 形状与领域层 `Db/src/agent_config.rs` 一一对应（`rename_all = "camelCase"`）。
// **界面拿到的 `gate` 就是唯一裁决**（在 Rust 里由 `agent::Gate` 算），前端不再算第二遍 ——
// 两处判定迟早分叉，用户看到「可以外发」而实际被拦是最糟的一种不一致。

/** 智能体配置（**没有密钥字段**：密钥单独存，只回「在不在」）。 */
export interface AgentConfiguration {
  /** 总开关。默认关：没配置过 = 不外发。 */
  enabled: boolean
  /** OpenAI 兼容端点。 */
  endpoint: string
  /** 模型名。 */
  model: string
  /** 单次请求超时（秒，1~600）。 */
  timeoutSecs: number
  /** 每小时请求上限（1~100000）。 */
  hourlyLimit: number
  /** 选中的内置预设标签（`custom` = 自填）。 */
  preset: string
}

/** 端点作用域。 */
export type AgentEndpointScope = 'local' | 'remote'

/** 闸门三段状态。 */
export type AgentGateState = 'disabled' | 'missing' | 'ready'

/**
 * 一条「不放行的理由」。
 *
 * 领域层把短码与具体值分成两格（`{ code, detail }`），界面据此查语言表；
 * `detail` 只对「填错了」那几条有值。
 */
export interface AgentIssue {
  code:
    | 'endpointMissing'
    | 'modelMissing'
    | 'keyMissing'
    | 'endpointScheme'
    | 'endpointHost'
    | 'timeoutOutOfRange'
    | 'hourlyLimitOutOfRange'
  detail?: string | number
}

/** 闸门裁决（**Rust 一处算**；界面只显示）。 */
export interface AgentGateReport {
  state: AgentGateState
  scope: AgentEndpointScope
  /** 放行时会用到的模型（未放行时为空串）。 */
  model: string
  issues: AgentIssue[]
}

// ── 自然语言 → SQL（FR-AI-02）────────────────────────────────────────────────
//
// 两段式：**先看要发什么**（`agentGeneratePreview`，不发请求）→ 用户点第二次才
// `agentGenerateSql`。外发正文由 Rust 那侧装配一次（预览与实发**同一份文本**），
// 界面不许自己拼提示词（否则预览看到的与实际发出去的不是一件事）。

/** 一列（只带名字与类型；**行数据不外发**）。 */
export interface AgentColumnBrief {
  name: string
  dataType: string
}

/** 一张表（或视图）的摘要（列没展开过时 `columns` 为空数组，**不是「没有列」**）。 */
export interface AgentTableBrief {
  schema: string
  name: string
  columns: AgentColumnBrief[]
}

/**
 * 本小时的配额读数（`FR-AI-01` 的「每小时上限」在 `FR-AI-02` 的拦面上）。
 *
 * 口径由领域层（`Db/src/agent_quota.rs`）给：`used` 按上限截断、`retryAfterSecs` 在没满时是 0。
 * 界面**不自己算**这些数（自己算就会与真闸门分叉）。
 */
export interface AgentQuotaStatus {
  limit: number
  used: number
  remaining: number
  windowSecs: number
  /** 满了的话还要等多少秒；没满 = 0。 */
  retryAfterSecs: number
}

export interface AgentGeneratePreview {
  gate: AgentGateReport
  /** 将要请求的完整地址。 */
  url: string
  /** 将要发送的正文（表名 / 列名 / 类型 / 问题）。 */
  human: string
  tableCount: number
  /** 因上限没列出去的表数（界面要如实说）。 */
  dropped: number
  /** 发之前就能看到的配额读数。 */
  quota: AgentQuotaStatus
  /** 生成历史（**新的在前**；由 Rust 侧读盘给出，界面不自己攒）。 */
  history: AgentHistoryEntry[]
}

/**
 * 一条生成记录（`Db/src/agent_history.rs` 的 `HistoryEntry`）。
 *
 * 只在**生成成功**时记；被挡住 / 报错 / 解析失败那一次不记（历史是结果清单，不是请求日志）。
 * `questionTruncated` / `sqlTruncated` = 原文太长被截断过，界面要如实说「这里不是全文」。
 */
export interface AgentHistoryEntry {
  question: string
  sql: string
  explanation: string
  tablesUsed: string[]
  model: string
  /** 记下来的时刻（epoch 秒；0 = 不知道）。 */
  atSecs: number
  questionTruncated: boolean
  sqlTruncated: boolean
}

/** 一次生成的结果（**只有文本，没有被执行**）。 */
export interface AgentGenerateOutcome {
  sql: string
  explanation: string
  tablesUsed: string[]
  model: string
  elapsedMs: number
  tableCount: number
  /** 发完这一次之后的配额读数（`used` 已含本次）。 */
  quota: AgentQuotaStatus
  /** 本片的已知缺口（配额尚未计数等），界面必须显示。 */
  limitations: string[]
  /** 记完这一条之后的历史（新的在前）—— 界面用它直接换掉列表。 */
  history: AgentHistoryEntry[]
}

/** 生成的三种结局：被闸门挡住（零外发）、被配额挡住（零外发）、或真的发了。 */
export type AgentGenerateReply =
  | { status: 'blocked'; gate: AgentGateReport }
  | { status: 'throttled'; quota: AgentQuotaStatus }
  | ({ status: 'generated' } & AgentGenerateOutcome)

/**
 * 一次「问诊断」的结局（`FR-AI-03` 第二片）—— 与生成面同构，但回的是**正文原文**。
 *
 * 三种结局都要界面上说得清：挡住（连请求都没发）/ 满额（本小时没额度了）/ 真发出去拿到正文。
 */
export type AgentAskReply =
  | { status: 'blocked'; gate: AgentGateReport }
  | { status: 'throttled'; quota: AgentQuotaStatus }
  | {
      status: 'answered'
      /** 模型正文（**不解读、不执行**；解读在 `workspace/agentDiagnosis.ts`）。 */
      text: string
      model: string
      elapsedMs: number
      quota: AgentQuotaStatus
      limitations: string[]
    }

/** 设置快照：配置 + 裁决 + 密钥在不在 + 两个路径。 */
export interface AgentSettingsSnapshot {
  config: AgentConfiguration
  gate: AgentGateReport
  /** 密钥**在不在**（永不回显内容）。 */
  keyPresent: boolean
  /** 存放方式（`dpapi` / `unavailable`）—— 界面照实写出，不假装安全。 */
  keyStorage: string
  /** 密钥读不出来的原因；正常为 null。 */
  keyNote: string | null
  /** 配置文件路径（让用户知道去哪儿看）。 */
  configPath: string
  /** 本小时的配额读数（与生成面的拦面同源；界面只显示，不自己算）。 */
  quota: AgentQuotaStatus
}

/** 浏览器旁路的状态（**只服务开发自测**：刷新即丢；真形态在 Tauri 外壳里落盘 + DPAPI）。 */
let bypassAgent: { config: AgentConfiguration; keyPresent: boolean } = {
  config: {
    enabled: false,
    endpoint: '',
    model: '',
    timeoutSecs: 60,
    hourlyLimit: 60,
    preset: 'custom',
  },
  keyPresent: false,
}

/**
 * 旁路下的裁决 —— **只镜像「分段」这一步**，不复制领域层那套规则以外的东西。
 *
 * 为什么旁路也要给一个像样的判定：浏览器里点一圈设置面板是开发时的主要验面，
 * 全返回「disabled」就验不出三态。判据仍以 Rust 侧单测为准（旁路不是产品形态）。
 */
function bypassAgentGate(): AgentGateReport {
  const { config, keyPresent } = bypassAgent
  const endpoint = config.endpoint.trim()
  const local = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0)/i.test(endpoint)
  const scope: AgentEndpointScope = local ? 'local' : 'remote'
  if (!config.enabled) return { state: 'disabled', scope, model: '', issues: [] }
  const issues: AgentIssue[] = []
  if (!endpoint) issues.push({ code: 'endpointMissing' })
  else if (!/^https?:\/\//i.test(endpoint)) issues.push({ code: 'endpointScheme', detail: endpoint })
  if (!config.model.trim()) issues.push({ code: 'modelMissing' })
  if (scope === 'remote' && !keyPresent) issues.push({ code: 'keyMissing' })
  if (config.timeoutSecs < 1 || config.timeoutSecs > 600) {
    issues.push({ code: 'timeoutOutOfRange', detail: config.timeoutSecs })
  }
  if (config.hourlyLimit < 1 || config.hourlyLimit > 100000) {
    issues.push({ code: 'hourlyLimitOutOfRange', detail: config.hourlyLimit })
  }
  return issues.length
    ? { state: 'missing', scope, model: '', issues }
    : { state: 'ready', scope, model: config.model.trim(), issues }
}

function bypassAgentSnapshot(): AgentSettingsSnapshot {
  return {
    config: { ...bypassAgent.config },
    gate: bypassAgentGate(),
    keyPresent: bypassAgent.keyPresent,
    keyStorage: 'unavailable',
    keyNote: null,
    configPath: '(浏览器旁路：没有落盘)',
    // 旁路不记配额账（刷新即丢的环境里记账没有意义）：读数照实给 0，并让上限跟配置走。
    quota: {
      limit: bypassAgent.config.hourlyLimit,
      used: 0,
      remaining: bypassAgent.config.hourlyLimit,
      windowSecs: 3600,
      retryAfterSecs: 0,
    },
  }
}

export function agentSettingsGet(): Promise<AgentSettingsSnapshot> {
  return call(COMMANDS.agentSettingsGet, {}, () => bypassAgentSnapshot())
}

export function agentSettingsSave(config: AgentConfiguration): Promise<AgentSettingsSnapshot> {
  return call(COMMANDS.agentSettingsSave, { config }, () => {
    bypassAgent = { ...bypassAgent, config: { ...config } }
    return bypassAgentSnapshot()
  })
}

export function agentKeySave(key: string): Promise<AgentSettingsSnapshot> {
  return call(COMMANDS.agentKeySave, { key }, () => {
    const trimmed = key.trim()
    if (!trimmed) {
      // 与外壳同形：**原话 + 出路**两段，且走语言表（漏译棘轮守着）
      throw {
        message: tNow('agent.key.empty'),
        hint: tNow('agent.key.emptyHint'),
      }
    }
    bypassAgent = { ...bypassAgent, keyPresent: true }
    return bypassAgentSnapshot()
  })
}

export function agentKeyClear(): Promise<AgentSettingsSnapshot> {
  return call(COMMANDS.agentKeyClear, {}, () => {
    bypassAgent = { ...bypassAgent, keyPresent: false }
    return bypassAgentSnapshot()
  })
}

/**
 * 「先看要发什么」（`FR-AI-02`）：**不发请求**，只把将要外发的正文与放行状态摊出来。
 *
 * 浏览器旁路里**不给一份自己拼的正文** —— 预览与实发必须是同一份文本，
 * 而那份文本只在 Rust 那侧装配一次（见 `Db/src/agent_nl2sql.rs` 的单测
 * 「the_human_preview_is_the_same_text_that_gets_sent」）。
 */
export function agentGeneratePreview(
  question: string,
  tables: AgentTableBrief[],
): Promise<AgentGeneratePreview> {
  return call(COMMANDS.agentGeneratePreview, { question, tables }, () => {
    throw { message: tNow('agent.generate.desktopOnly'), hint: tNow('agent.generate.desktopOnlyHint') }
  })
}

/** 真发一次（放行才发；结果**只回文本**，不执行；成功的那一次会留一条生成历史）。 */
export function agentGenerateSql(
  question: string,
  tables: AgentTableBrief[],
): Promise<AgentGenerateReply> {
  return call(COMMANDS.agentGenerateSql, { question, tables }, () => {
    throw { message: tNow('agent.generate.desktopOnly'), hint: tNow('agent.generate.desktopOnlyHint') }
  })
}

/**
 * **问诊断一次**（`FR-AI-03` 第二片）：把面板上那份资料块**原样**发出去，只回正文。
 *
 * 外发正文由 Rust 那侧装配（与面板上显示的是同一份文本 + 一段固定输出纪律），界面不自己拼提示词。
 * 与生成面共用同一条通道：总开关关着 / 满额都会在这里被挡住，**一条请求都不发**。
 */
export function agentDiagnosisAsk(brief: string): Promise<AgentAskReply> {
  return call(COMMANDS.agentDiagnosisAsk, { brief }, () => {
    throw { message: tNow('agent.generate.desktopOnly'), hint: tNow('agent.generate.desktopOnlyHint') }
  })
}

/**
 * 生成历史（新的在前）。**只读**：不触发外发、不改盘上的东西。
 *
 * 为什么单独一条命令（而不是从预览里取）：预览要一句非空的问题才装得出来，
 * 而「一打开弹层就看到以前问过什么」不该逼用户先敲字。
 */
export function agentHistoryList(): Promise<AgentHistoryEntry[]> {
  return call(COMMANDS.agentHistoryList, {}, () => [] as AgentHistoryEntry[])
}

/**
 * 一条审计记录（`Db/src/agent_audit.rs` 的 `AuditRecord`）。
 *
 * 与生成历史**分开的两件事**：历史只记成功的那一次（「可回看的结果」）；
 * 审计记**每一次外发尝试**，含被闸门 / 配额挡住、根本没过网的那几次（「为什么没发出去」也要能查）。
 * 键集合是白名单：**结构上没有承载结果集行数据的字段**（`NFR-AI-01`）。
 */
export interface AgentAuditRecord {
  /** 时刻（epoch 秒；0 = 不知道）。 */
  atSecs: number
  /** 结局：成功 / 失败（过网了） / 被闸门挡住 / 被每小时上限挡住（都没过网）。 */
  verdict: 'ok' | 'failed' | 'blocked' | 'throttled'
  model: string
  /** 目标端点（**已脱敏**：`https://user:pw@host` 的口令段被抹掉）。 */
  endpoint: string
  /** 问句摘要（已脱敏、超长截断）。 */
  summary: string
  /** 失败原因 / 决策理由（已脱敏）。 */
  detail: string
  /** 往返耗时（毫秒；没过网的那几次是 0）。 */
  durationMs: number
  /** 随请求外发的表数。 */
  tableCount: number
}

/** 外发审计清单（**新的在前**；只读，不触发任何外发）。 */
export function agentAuditList(): Promise<AgentAuditRecord[]> {
  return call(COMMANDS.agentAuditList, {}, () => [] as AgentAuditRecord[])
}

/** 表单逐项校验（FR-CONN-06）：端口按**文本**校验，`0` / `65536` / 非数字都当场拒。 */
export function connectionValidate(
  name: string,
  host: string,
  port: string,
  username: string,
): Promise<FieldProblem[]> {
  return call(COMMANDS.connectionValidate, { name, host, port, username }, () => [] as FieldProblem[])
}

/** 换引擎联动（FR-CONN-02）：端口 / SSL / 默认 schema 跟着新类型走。 */
export function connectionTypeDefaults(dbType: string): Promise<ConnectionTypeDefaults> {
  return call(COMMANDS.connectionTypeDefaults, { dbType }, () => ({
    dbType,
    port: 5432,
    sslMode: 'prefer',
    schema: null,
  }))
}

/** 从连接 URL 导入（FR-CONN-19）：解析失败给具体原因（不是半个配置）。 */
export function connectionImportUrl(
  url: string,
  id: string,
  name?: string,
): Promise<ImportedUrl> {
  return call(COMMANDS.connectionImportUrl, { url, id, name }, () => {
    throw bypassDb('ipc.action.connect') as DbFailure
  })
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
    throw bypassDb('ipc.action.generate') as DbFailure
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
//
// **元数据行数上限（FR-META-07）**：两层元数据查询都返回 `CappedRows<T>`（行 + 截断标记 + 上限）
// —— 收够 10,000 行就停，到顶时 `truncated` 为真，界面据此如实说"可能不完整"（不静默少给）。

/** 带上限保护的元数据结果（与领域层 `tree::CappedRows` 同形）。 */
export interface CappedRows<T> {
  rows: T[]
  /** 服务端还回得更多、被上限截掉了（界面要如实说） */
  truncated: boolean
  /** 本次生效的上限（"只显示了前 N 条"里的 N） */
  limit: number
}

/** 树的第一层：这台服务器上能看到的 schema（带上限保护，FR-META-07）。 */
export function dbSchemas(): Promise<CappedRows<string>> {
  return call(COMMANDS.dbSchemas, {}, () => ({ rows: [] as string[], truncated: false, limit: 0 }))
}

/** 第二层：某个 schema 下的对象（**展开时才问**；带上限保护，FR-META-07）。 */
export function dbRelations(schema: string): Promise<CappedRows<ObjectNode>> {
  return call(COMMANDS.dbRelations, { schema }, () => ({
    rows: [] as ObjectNode[],
    truncated: false,
    limit: 0,
  }))
}

/**
 * 第三层：一个 schema 下**一批表 / 视图的列**（含数据类型原文）。
 *
 * 接口收成「一批表」而不是「一张表」：一张表一次是最省事的写法，但「全部展开」就成 N+1
 * —— 形状先钉住，调用方想 N+1 也难（判据按**调用计数**钉，见 `views/objectTree.ts`）。
 */
export function dbColumns(schema: string, tables: string[]): Promise<TableColumns[]> {
  return call(COMMANDS.dbColumns, { schema, tables }, () => [] as TableColumns[])
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
    throw bypassDb('ipc.action.run') as DbFailure
  })
}

/** **取消当前查询**：往服务端发取消请求（不是本地"不等了"）。取消后连接仍可用。 */
export function dbCancel(): Promise<boolean> {
  return call(COMMANDS.dbCancel, {}, () => false)
}

/** 生成 `EXPLAIN` 语句（只生成、不执行；**只对单条**，多段输入会被拒并说明原因）。 */
export function explainStatement(sql: string, analyze = false): Promise<string> {
  return call(COMMANDS.explainStatement, { sql, analyze }, () => {
    throw bypassDb('ipc.action.generate') as DbFailure
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

// ── 编辑面静态检查（FR-EDIT-03 检查器 / FR-EDIT-56 上屏）──────────────────────────────

/** 一条诊断（**偏移是字符下标**，前端可直接 `slice` 原文；`end` 不含）。 */
export interface SqlDiagnostic {
  start: number
  end: number
  severity: 'error' | 'warning' | 'info'
  message: string
}

/**
 * 跑一遍静态检查（未闭合字符串 / 块注释 / dollar-quote / 括号不配平）。
 *
 * 口径：**规则只判一遍**（领域层 `Db/src/lint.rs`），这个函数只把原文递过去。
 * 浏览器旁路（不在 Tauri 里跑）没有检查器 ⇒ 返回空表（不编造问题）；
 * 界面据此不给下划线，而不是假装「已检查、无问题」。
 */
export function diagnoseSql(sql: string): Promise<SqlDiagnostic[]> {
  return call(COMMANDS.diagnoseSql, { sql }, () => [] as SqlDiagnostic[])
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
    throw bypassDb('ipc.action.preview') as DbFailure
  })
}

/** 一批写回，一次事务：`rollback` 为真时跑完主动回滚（"提交前预览"的姿势）。 */
export function dbWriteBatch(statements: string[], rollback = false): Promise<StatementOutcome[]> {
  return call(COMMANDS.dbWriteBatch, { statements, rollback }, () => {
    throw bypassDb('ipc.action.writeBack') as DbFailure
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

// ── 表结构与 DDL（1.5：表设计器 / 变更集预览 / 索引约束 / 删除类只生成不执行）──────────────

/** 一列的定义（与领域层 `ddl::ColumnDef` 同形）。 */
export interface ColumnDef {
  name: string
  dataType: string
  isNullable: boolean
  defaultExpr: string | null
}

export interface IndexInfo {
  name: string
  isUnique: boolean
  isPrimary: boolean
  columns: string[]
}

export interface ConstraintInfo {
  name: string
  /** `primary` / `foreign` / `unique` / `check` / 服务端原字母 */
  kind: string
  definition: string
}

/** 一张表的**结构**（列 / 索引 / 约束）—— 表设计器一打开就要这三样。 */
export interface TableShape {
  schema: string
  table: string
  columns: ColumnDef[]
  indexes: IndexInfo[]
  constraints: ConstraintInfo[]
}

/** 生成的 DDL 与它的分级（`destructive` = **只生成、不自动执行**）。 */
export interface DdlStatement {
  sql: string
  bare: string
  class: 'additive' | 'altering' | 'destructive' | 'data_moving'
  purpose: string
}

/** 读一张表的结构。 */
export function dbTableShape(schema: string, table: string): Promise<TableShape> {
  return call(COMMANDS.dbTableShape, { schema, table }, () => {
    throw {
      message: tNow('ipc.bypass.db'),
      hint: tNow('ipc.bypass.hint', { action: tNow('ipc.action.designer' as never) }),
    } as DbFailure
  })
}

/** **生成 DDL**（只生成、不执行）：按 `op` 分派，返回带注释头的可读语句表。 */
export function generateDdl(request: {
  op: 'alter_columns' | 'create_index' | 'drop_index' | 'add_foreign_key' | 'drop_constraint' | 'drop_table'
  schema?: string
  table?: string
  originalColumns?: ColumnDef[]
  editedColumns?: ColumnDef[]
  columns?: string[]
  unique?: boolean
  indexName?: string
  refSchema?: string
  refTable?: string
  refColumns?: string[]
  constraintName?: string
}): Promise<DdlStatement[]> {
  return call(COMMANDS.generateDdl, { ...request }, () => {
    throw bypassDb('ipc.action.generate') as DbFailure
  })
}

/** **执行非破坏性 DDL**（加列 / 改列 / 加索引 / 加约束）；破坏性语句会被命令层拒收。 */
export function dbRunDdl(statements: string[]): Promise<StatementOutcome[]> {
  return call(COMMANDS.dbRunDdl, { statements }, () => {
    throw bypassDb('ipc.action.run') as DbFailure
  })
}

// ── Schema 对比与同步（FR-DDL-04）────────────────────────────────────────────────────

/** 快照里的一列：**只有结构与名，没有数据**。 */
export interface SnapshotColumn {
  name: string
  dataType: string
  isNullable: boolean
  defaultExpr: string | null
}

/** 快照里的一张表。 */
export interface SnapshotTable {
  name: string
  columns: SnapshotColumn[]
  primaryKey: string[]
}

/** 一份库结构快照（一个 schema 一张）。 */
export interface SchemaSnapshot {
  label: string
  schema: string
  takenAt: number
  tables: SnapshotTable[]
}

export type TableDiffStatus = 'create' | 'drop' | 'alter' | 'same'

/** 一张表的差异摘要。 */
export interface TableDiff {
  table: string
  status: TableDiffStatus
  addedColumns: string[]
  removedColumns: string[]
  alteredColumns: string[]
  primaryKeyDiffers: boolean
}

/** 看见了但**没生成语句**的差异（"没做"必须说出来）。 */
export interface SkippedChange {
  table: string
  what: string
  reason: string
}

/** 对比报告（脚本有序：建表 → 改表 → 删表）。 */
export interface SchemaDiffReport {
  baseLabel: string
  targetLabel: string
  baseTableCount: number
  targetTableCount: number
  tableDiffs: TableDiff[]
  statements: DdlStatement[]
  skipped: SkippedChange[]
  allowDrop: boolean
  destructiveCount: number
  createdTables: number
  alteredTables: number
  droppedTables: number
}

/**
 * **抓一份结构快照**（`FR-DDL-04`）：对比的两侧都从这条命令拿。
 *
 * 浏览器旁路没有真库 ⇒ 抛带原因的错误（面板据它显示「这里没有真库」，不用空快照冒充「空库」）。
 */
export function schemaSnapshot(schema: string, label: string): Promise<SchemaSnapshot> {
  return call(
    COMMANDS.schemaSnapshot,
    { schema, label, takenAt: Date.now() },
    () => {
      throw bypassDb('ipc.action.schemaSnapshot') as DbFailure
    },
  )
}

/** **两份快照 → 差异 + 同步脚本**（纯函数，不连库；`allowDrop` 默认关）。 */
export function schemaDiffPlan(
  base: SchemaSnapshot,
  target: SchemaSnapshot,
  allowDrop = false,
): Promise<SchemaDiffReport> {
  return call(COMMANDS.schemaDiffPlan, { base, target, allowDrop }, () => {
    throw bypassDb('ipc.action.schemaDiff') as DbFailure
  })
}

// ── 导入导出（1.6）────────────────────────────────────────────────────────────────────

/** 导出结果：**行数与截断如实报**。 */
export interface ExportReport {
  path: string
  rows: number
  columns: number
  /** 服务端还有更多行没取回来（超过上限） */
  truncated: boolean
  bytes: number
}

/** 被丢掉的一行（**必须带原因**，否则用户不知道丢的是什么）。 */
export interface SkippedRow {
  line: number
  reason: string
  preview: string
}

/** 导入预览：读了几行 / 丢了几行 / 列怎么对的（**不碰数据库**）。 */
export interface ImportPreview {
  header: string[]
  delimiter: string
  parsedRows: number
  totalDataRows: number
  skipped: SkippedRow[]
  matched: [string, number][]
  unmatchedCsv: string[]
  missing: string[]
  sample: string[][]
}

export interface ImportReport {
  inserted: number
  skipped: SkippedRow[]
  columns: string[]
}

/** **导出到文件**（原子落盘：临时文件 + 同目录改名，失败不留半截文件）。 */
export function exportToFile(
  sql: string,
  path: string,
  format: 'csv' | 'json' = 'csv',
  maxRows?: number,
): Promise<ExportReport> {
  return call(COMMANDS.exportToFile, { sql, path, format, maxRows }, () => {
    throw bypassDb('ipc.action.export') as DbFailure
  })
}

// ── 备份（FR-IO-04：封装本机 pg_dump）────────────────────────────────────────────────
//
// 两段式：`backupPlan` 只算不跑（把**命令行**摊出来给用户看），`backupRun` 才真起子进程。
// 口令不进这两个参数里的任何一个 —— 外壳按 `connectionId` 从系统凭据里取，只进环境变量。

/** 备份格式（与 `pg_dump -F` 一一对应）。 */
export type BackupFormat = 'plain' | 'custom' | 'directory'

/** 备份计划回执（**不含口令**；`problem` = 现在就跑会立刻失败的原因）。 */
export interface BackupPlanReport {
  /** 找到的 `pg_dump`（`null` ⇒ 本机没有 / 指定的不对） */
  program: string | null
  /** 可复制的命令行（口令位置写 `PGPASSWORD=***`） */
  display: string
  database: string
  target: string
  format: BackupFormat
  problem: DbFailure | null
}

/** 备份结局（**成功失败都带日志尾部与退出码**）。 */
export interface BackupReport {
  display: string
  exitCode: number | null
  log: string
  /** 前面还有多少字符没带回来（没截断就是 0） */
  logTrimmedChars: number
  bytes: number
  elapsedMs: number
  target: string
  format: BackupFormat
}

export interface BackupRequest {
  connectionId: string
  path: string
  format: BackupFormat
  /** 备份哪个库（留空 = 当前连接的库） */
  database?: string
  /** 手动指定 `pg_dump` 路径（留空 = 自动找） */
  program?: string
}

/**
 * **跑着的读数**（`FR-IO-04`）：三个数全是实测的，**没有百分比** ——
 * `pg_dump` 不告诉我们总量，编一个进度条等于骗人。
 */
export interface BackupProgress {
  /** 这次跑了多少毫秒 */
  elapsedMs: number
  /** 目标现在多大（目录形式为各文件之和） */
  bytes: number
  /** 子进程已经吐了多少行（`--verbose` 下一张表一行） */
  lines: number
  /** 最近一行原话；还没吐过就是 null */
  lastLine: string | null
}

/** **备份计划**：只算命令行，不起任何进程。 */
export function backupPlan(request: BackupRequest): Promise<BackupPlanReport> {
  return call(COMMANDS.backupPlan, { request }, () => {
    throw bypassDb('ipc.action.backup') as DbFailure
  })
}

/** **真跑备份**：子进程起 `pg_dump`，回执带退出码与日志尾部。 */
export function backupRun(request: BackupRequest): Promise<BackupReport> {
  return call(COMMANDS.backupRun, { request }, () => {
    throw bypassDb('ipc.action.backup') as DbFailure
  })
}

/**
 * **取消正在跑的备份**（`true` = 确实有一次在跑、已收到取消请求）。
 *
 * 不是「本地不等了」：外壳会终止 `pg_dump` 进程，并把这次留下的半截产物删掉 ——
 * 于是「取消」不会给盘上留一个看起来有备份的 0 字节文件。
 */
export function backupCancel(): Promise<boolean> {
  return call(COMMANDS.backupCancel, {}, () => {
    throw bypassDb('ipc.action.backup') as DbFailure
  })
}

/**
 * **读一次备份进度**（跑着的时候轮询）：`null` = 现在没有备份在跑。
 *
 * 读数只用于显示，**不参与判定**：路径 / 程序 / 成败全在外壳判。
 */
export function backupProgress(): Promise<BackupProgress | null> {
  return call(COMMANDS.backupProgress, {}, () => null)
}

/** **预览导入**（不碰数据库）：解析文件并与目标表列对账。 */
export function previewImport(
  path: string,
  hasHeader: boolean,
  targetColumns: string[],
): Promise<ImportPreview> {
  return call(COMMANDS.previewImport, { path, hasHeader, targetColumns }, () => {
    throw bypassDb('ipc.action.previewImport') as DbFailure
  })
}

/** **执行导入**：重新解析文件 → **一个事务**写入（中途失败整批回滚）。 */
export function runImport(request: {
  path: string
  schema?: string
  table: string
  hasHeader: boolean
  targetColumns: string[]
}): Promise<ImportReport> {
  return call(COMMANDS.runImport, { ...request }, () => {
    throw bypassDb('ipc.action.import') as DbFailure
  })
}

/** **Excel（.xlsx）→ CSV 文本**（借本机 DSH 运行时的 Python + openpyxl，不引 Rust 侧 Excel 依赖）。 */
export function xlsxToCsv(path: string, sheet?: string): Promise<string> {
  return call(COMMANDS.xlsxToCsv, { path, sheet }, () => {
    throw {
      message: '浏览器旁路没有真库',
      hint: 'Excel 通路要在 Tauri 外壳里跑（npm run tauri dev）。',
    } as DbFailure
  })
}

// ── 库与服务器管理面（1.7）────────────────────────────────────────────────────────────

export interface DatabaseInfo {
  name: string
  owner: string
  encoding: string
  sizeBytes: number
  connections: number
  allowConnections: boolean
}

/** 会话与锁的一行（排序口径在领域层：等锁优先，其次按时长）。 */
export interface SessionRow {
  pid: number
  user: string
  database: string
  state: string
  /** 只在 active 时有值（idle 会话的 query 是上一条语句，给了会误导） */
  query: string | null
  durationMs: number
  /** 它是不是**等锁**的那个 */
  waiting: boolean
}

export interface TableStats {
  table: string
  /** **估算**行数（`pg_class.reltuples`，不是精确 count） */
  estimatedRows: number
  totalBytes: number
  tableBytes: number
  indexSizePretty: string
  lastVacuum: string
  lastAnalyze: string
}

/** 慢查询排行的一行（文本已按字符截断；`truncated` 为真时界面要如实说「已截断」）。 */
export interface SlowQueryRow {
  query: string
  calls: number
  totalMs: number
  meanMs: number
  /** 该语句累计影响 / 返回的行数（服务端口径） */
  rows: number
  truncated: boolean
}

/**
 * 慢查询排行回包（FR-DIAG-03）。
 *
 * **`available: false` 不是错误**：它带一句可读原因 + 三步安装指引 ——
 * 界面上绝不能用「空列表」冒充「没有慢查询」（那是假绿）。
 */
export interface SlowQueryReport {
  available: boolean
  installed: boolean
  availableExtension: boolean
  preloaded: boolean
  reason: string | null
  steps: string[]
  /** 本次用的时间列名（PG12 是 `total_time`，13 起是 `total_exec_time`） */
  totalColumn: string
  meanColumn: string
  rowsOut: SlowQueryRow[]
}

/** 一条维护命令（**只生成、不执行**；每条都带代价说明）。 */
export interface MaintenanceCommand {
  sql: string
  bare: string
  purpose: string
  cost: string
}

/** 危险操作的确认结果。 */
export interface Confirmation {
  ok: boolean
  reason: string | null
}

export function adminDatabases(): Promise<DatabaseInfo[]> {
  return call(COMMANDS.adminDatabases, {}, () => [] as DatabaseInfo[])
}

export function adminSessions(): Promise<SessionRow[]> {
  return call(COMMANDS.adminSessions, {}, () => [] as SessionRow[])
}

export function adminTableStats(schema: string): Promise<TableStats[]> {
  return call(COMMANDS.adminTableStats, { schema }, () => [] as TableStats[])
}

/**
 * **慢查询排行**（FR-DIAG-03）：`sort` 只能是 `total` / `mean` / `calls`。
 *
 * 浏览器旁路没有真库 ⇒ 回一个 `available: false` + 原因（不是抛错 —— 面板要能说清「这里没有真库」）。
 */
export function slowQueries(sort: SlowQuerySortKey, limit = 20): Promise<SlowQueryReport> {
  return call(COMMANDS.slowQueries, { sort, limit }, () => ({
    available: false,
    installed: false,
    availableExtension: false,
    preloaded: false,
    reason: '浏览器旁路没有真库：慢查询排行要在 Tauri 外壳里连上服务端才读得到。',
    steps: [],
    totalColumn: '',
    meanColumn: '',
    rowsOut: [],
  }) as SlowQueryReport)
}

/** 排行口径（与领域层 `SlowQuerySort::parse` 认的字符串一一对应）。 */
export type SlowQuerySortKey = 'total' | 'mean' | 'calls'

/** **维护命令**（只生成、不执行）。 */
export function maintenanceSql(schema: string | undefined, table: string): Promise<MaintenanceCommand[]> {
  return call(COMMANDS.maintenanceSql, { schema, table }, () => [] as MaintenanceCommand[])
}

/** **杀会话命令**（只生成、不执行；`force` 为真给 terminate，否则 cancel）。 */
export function terminateSql(pid: number, force = false): Promise<MaintenanceCommand> {
  return call(COMMANDS.terminateSql, { pid, force }, () => {
    throw bypassDb('ipc.action.generate') as DbFailure
  })
}

/** **授权预览**（只生成 GRANT / REVOKE 语句）。 */
export function grantPreview(request: {
  privileges: string[]
  objectKind: string
  schema?: string
  object: string
  role: string
  revoke?: boolean
}): Promise<string> {
  return call(COMMANDS.grantPreview, { ...request }, () => {
    throw bypassDb('ipc.action.generate') as DbFailure
  })
}

/** **删库确认**：逐字打出库名才放行（判定在领域层）。 */
export function confirmDropDatabase(typed: string, database: string): Promise<Confirmation> {
  return call(COMMANDS.confirmDropDatabase, { typed, database }, () => ({ ok: false, reason: '浏览器旁路' }))
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
    throw bypassWorkspace('ipc.action.openWorkspace') as DbFailure
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

/** 媒体引用的种类（与领域层 `markdown::MediaKind` 同形）。 */
export type MdMediaKind = 'image' | 'video' | 'external' | 'unsupported'

/** 块级模型的成员（**没有可编辑控件**：预览是只读的，这条是结构上挡住的）。 */
export type MdBlockKind =
  | { type: 'heading'; level: number; spans: MdSpan[] }
  | { type: 'paragraph'; spans: MdSpan[] }
  /** 独占一行的媒体引用（`![说明](assets/x.png)`）—— 图片 / 视频就地渲染。 */
  | { type: 'media'; media: MdMediaKind; alt: string; target: string }
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
  /** 编辑器等宽字体族；`null` = **系统等宽**（`editor.fontFamily`） */
  editorFamily: string | null
  /** 编辑器字号（pt，9~20，已由领域层夹取；`editor.fontSize`） */
  editorSizePt: number
}

/** Rust 算好的 DOM 取值（`dataTheme` 为 `null` = 不设那个属性）。 */
export interface DomAppearance {
  dataTheme: 'dark' | 'light' | null
  dataScheme: string
  nebula: boolean
  isDark: boolean
  /** 落到 `--ds-editor-font-family` 的整条 CSS（Rust 拼好，前端不拼） */
  editorFamilyCss: string
  /** 落到 `--ds-editor-font-size` 的值（如 `13px`） */
  editorSizeCss: string
}

export interface AppearancePayload {
  appearance: Appearance
  dom: DomAppearance
  warning?: string | null
}

/** 缺省外观（浏览器旁路与「读失败」两条路共用的**一份**缺省值）。 */
export const DEFAULT_APPEARANCE: Appearance = {
  mode: 'followSystem',
  scheme: 'stardust',
  nebulaSkin: true,
  editorFamily: null,
  editorSizePt: 13,
}

/** 缺省字体面落 DOM 的取值（与 Rust 侧 `EditorFont::default()` 逐字一致）。 */
export const DEFAULT_APPEARANCE_DOM: DomAppearance = {
  dataTheme: null,
  dataScheme: 'stardust',
  nebula: false,
  isDark: false,
  editorFamilyCss: 'var(--ds-font-stack-mono)',
  editorSizeCss: '13px',
}

/** 读外观偏好（`systemIsDark` 由前端给 —— 本命令只算"最终该长什么样"）。 */
export function appearanceGet(systemIsDark: boolean): Promise<AppearancePayload> {
  return call(COMMANDS.appearanceGet, { systemIsDark }, () => ({
    appearance: { ...DEFAULT_APPEARANCE },
    dom: { ...DEFAULT_APPEARANCE_DOM, nebula: systemIsDark, isDark: systemIsDark },
    warning: null,
  }))
}

/** 改外观偏好（**部分更新**：只传要改的那几项）。 */
export function appearanceSet(
  patch: {
    mode?: Appearance['mode']
    scheme?: Appearance['scheme']
    nebulaSkin?: boolean
    /** 传空串 = **回到系统等宽**（清掉用户挑的族）；不传 = 不改 */
    editorFamily?: string
    editorSizePt?: number
  },
  systemIsDark: boolean,
): Promise<{ appearance: Appearance; dom: DomAppearance }> {
  return call(
    COMMANDS.appearanceSet,
    {
      mode: patch.mode,
      scheme: patch.scheme,
      nebulaSkin: patch.nebulaSkin,
      editorFamily: patch.editorFamily,
      editorSizePt: patch.editorSizePt,
      systemIsDark,
    },
    () => {
      // 浏览器旁路：够界面自测（**不落盘**，刷新即回缺省）
      const family =
        patch.editorFamily === undefined
          ? DEFAULT_APPEARANCE.editorFamily
          : patch.editorFamily.trim() === ''
            ? null
            : patch.editorFamily
      const sizePt = Math.min(20, Math.max(9, patch.editorSizePt ?? DEFAULT_APPEARANCE.editorSizePt))
      return {
        appearance: {
          mode: patch.mode ?? DEFAULT_APPEARANCE.mode,
          scheme: patch.scheme ?? DEFAULT_APPEARANCE.scheme,
          nebulaSkin: patch.nebulaSkin ?? DEFAULT_APPEARANCE.nebulaSkin,
          editorFamily: family,
          editorSizePt: sizePt,
        },
        dom: {
          dataTheme: null,
          dataScheme: patch.scheme ?? DEFAULT_APPEARANCE.scheme,
          nebula: systemIsDark,
          isDark: systemIsDark,
          editorFamilyCss: family
            ? `"${family}", var(--ds-font-stack-mono)`
            : 'var(--ds-font-stack-mono)',
          editorSizeCss: `${sizePt}px`,
        },
      }
    },
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

/**
 * 格式化**编辑面里的一段 SQL**（FR-EDIT-22）—— 查询还没有文件，所以不走 `workspaceFormatContent`
 * （那条要工作区根 + 相对路径，为的是语言探测与路径安全，这里两样都不需要）。
 *
 * 浏览器旁路**如实拒绝**（不发一个假的「已格式化」）：真格式化由外壳按
 * 「外部工具优先 → 内置兜底 → 如实拒绝」那条定案判定。
 */
export function formatSql(sql: string, preferBuiltin = false): Promise<FormatOutcome> {
  return call(COMMANDS.sqlFormat, { sql, preferBuiltin }, () => ({
    content: sql,
    changed: false,
    note: tNow('ipc.bypass.sqlFormat'),
    engine: 'refused',
    problem: 'browser',
  }))
}

// ── 查询参数（FR-EXEC-17）───────────────────────────────────────────────────────────────
//
// 两条命令都是**纯函数**（扫描 / 绑定），不碰连接：界面在执行前先扫一次决定「弹不弹填值面板」，
// 用户填完再绑定，绑定结果**只用于本次执行**（编辑器里的占位符原样留着 —— 它是可复用的模板）。
//
// 为什么类型要用户选而不是界面猜：`where name = :name` 填 `2`，猜成数字会得到 `text = integer`，
// 整条语句失败；猜成文本则永远成立。所以默认文本，数字 / 布尔 / NULL 都要用户明确选。

/** 参数值写进语句时的类型（**用户选**，不猜）。 */
export type ParamKind = 'text' | 'number' | 'boolean' | 'null'

/** 一个参数站点（去重后）。 */
export interface ParamSite {
  name: string
  occurrences: number
  positional: boolean
}

export interface ParameterScan {
  sites: ParamSite[]
  hasParameters: boolean
}

export interface ParamValue {
  name: string
  value: string
  kind: ParamKind
}

export interface BoundParameter {
  name: string
  occurrences: number
  kind: ParamKind
  literal: string
}

export interface ParameterBindOutcome {
  sql: string
  params: BoundParameter[]
  unused: string[]
}

/** 扫一遍 SQL 里的 `:name` / `$1`（字符串 / 注释 / dollar-quote 里的一律不算）。 */
export function scanSqlParameters(sql: string): Promise<ParameterScan> {
  return call(COMMANDS.sqlParameters, { sql }, () => ({ sites: [], hasParameters: false }))
}

/** 绑定参数（缺值 / 数字格式不对时**抛错**，错误话直接可显示）。 */
export function bindSqlParameters(sql: string, values: ParamValue[]): Promise<ParameterBindOutcome> {
  return call(COMMANDS.sqlBindParameters, { sql, values }, () => ({ sql, params: [], unused: [] }))
}

// ── 内置终端（W-C 底部终端 · 2.7 · S-9b）：界面侧的四个包装 ───────────────────────────────
//
// 命令名的单一出处仍是 `COMMANDS`（`terminalOpen` / `terminalWrite` / `terminalRead` /
// `terminalClose` 四条）。S-9a 只登记了名字，本片补**可调用包装**；界面侧只经这四个函数
// 调用终端，不许自己 `invoke('terminal_*')`。
//
// **浏览器旁路**：不在 Tauri 里跑时没有真终端（真形态是 WebView2 里跑真 PTY）—— `terminalOpen`
// 与 `dbConnect` 同款：给一句「浏览器旁路没有真终端」的结构化失败，不拿假会话冒充成功。

/** 浏览器旁路的终端提示（与 `bypassDb` / `bypassWorkspace` 同一姿势）。 */
function bypassTerminal(action: string) {
  return {
    message: tNow('ipc.bypass.terminal'),
    hint: tNow('ipc.bypass.hint', { action: tNow(action as never) }),
  }
}

/** 领域层屏幕模型投影的线上形态（与 Rust 侧 `terminal_bridge::ScreenProjection` 同形）。 */
export interface TerminalScreenProjection {
  /** 网格每行的可显示文本。 */
  rows: string[]
  /** 整屏文本（各行以 `\n` 相连）—— S-9d 起为前端**渲染源**。 */
  text: string
  cursor: { row: number; col: number }
  cursorVisible: boolean
  /** 本轮消费（已写回 PTY）的设备查询应答；消费后清空，故同一条至多出现一次。 */
  pendingResponses: string[]
  eof: boolean
  exitCode: number | null
}

/** 一次读取的返回（与 Rust 侧 `terminal_bridge::TerminalChunk` 同形；`exitCode` 拿到才有）。 */
export interface TerminalChunk {
  /** PTY 原始字节（前端不再显示它；保留字段以与线上形态同形）。 */
  data: string
  eof: boolean
  exitCode: number | null
  /** 领域层屏幕投影（S-9c 起新增字段；S-9d 起为前端渲染源）。浏览器旁路没有真终端 ⇒ `null`。 */
  screen: TerminalScreenProjection | null
}

/** 起会话的入参（都可缺省：不给就是系统 shell、80×24）。 */
export interface TerminalOpenOptions {
  program?: string
  args?: string[]
  cwd?: string
  cols?: number
  rows?: number
}

/** 起一个真交互式终端会话，返回会话 id（Rust 侧从 1 起的自增号）。 */
export function terminalOpen(options: TerminalOpenOptions = {}): Promise<number> {
  return call(COMMANDS.terminalOpen, { ...options }, () => {
    throw bypassTerminal('ipc.action.terminal') as unknown as number
  })
}

/** 往终端会话写（用户按键 / 粘贴）。 */
export function terminalWrite(id: number, data: string): Promise<void> {
  return call(COMMANDS.terminalWrite, { id, data }, () => undefined)
}

/** 读终端输出（最多等 `timeoutMs`，缺省 50ms），带领域层屏幕投影与「是否已结束」与退出码。 */
export function terminalRead(id: number, timeoutMs = 50): Promise<TerminalChunk> {
  return call(COMMANDS.terminalRead, { id, timeoutMs }, () => ({
    data: '',
    eof: true,
    exitCode: null,
    screen: null,
  }))
}

/** 关闭终端会话（子进程 / pty / 两条线程一并收工）。 */
export function terminalClose(id: number): Promise<void> {
  return call(COMMANDS.terminalClose, { id }, () => undefined)
}
