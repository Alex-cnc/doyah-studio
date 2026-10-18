<script setup lang="ts">
// 数据库视图（Windows 侧）—— alpha 1.0 的**读数据竖切**第一版
//
// 口径：模型与解析在领域层（`platform/windows/Db`），驱动在 Rust 外壳（`src-tauri/src/postgres.rs`），
// 本组件只做显示与转交 —— 三类状态各归其位：
//   · 失败：**服务端原话**与提示**两段都显示**（不合并成"失败了"）；
//   · 截断：`truncated` 为真时**如实说**（不静默少给行）；
//   · 未连接：按钮可用但一按就给可读原因（不做"灰着但不说为什么"）。

import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import ActionIcon from './ActionIcon.vue'
import {
  LAB_CONNECTION,
  connectionDelete,
  connectionImportUrl,
  connectionSave,
  connectionTypeDefaults,
  connectionValidate,
  connectionsList,
  savedQueriesList,
  savedQueryDelete,
  savedQuerySave,
  dbConnect,
  dbDisconnect,
  dbQuery,
  dbRunBatch,
  dbCancel,
  explainStatement,
  highlightSql,
  diagnoseSql,
  formatSql,
  scanSqlParameters,
  bindSqlParameters,
  type ParameterScan,
  dbWriteBatch,
  dbPrimaryKey,
  editsToDml,
  statementRisk,
  dbReadOnly,
  dbSchemas,
  dbRelations,
  dbColumns,
  searchObjects,
  browseSql,
  inspectRow,
  dbTables,
  dbTableShape,
  generateDdl,
  dbRunDdl,
  exportToFile,
  previewImport,
  runImport,
  // 库与服务器管理面（1.7）：这些名字此前**在模板/脚本里被调用、却没有 import** ——
  // `tsc --noEmit` 不校验 .vue，所以编译期无声；一点「管理面板」就在 try 里抛
  // ReferenceError，用户看到的是「ipcAdminDatabases is not defined」。本片补上。
  adminDatabases as ipcAdminDatabases,
  adminSessions as ipcAdminSessions,
  adminTableStats as ipcAdminTableStats,
  maintenanceSql as ipcMaintenanceSql,
  terminateSql as ipcTerminateSql,
  slowQueries as ipcSlowQueries,
  type SlowQueryReport,
  type SlowQuerySortKey,
  type ConnectParams,
  type DbFailure,
  type FieldProblem,
  type QueryResult,
  type SavedConnection,
  type SavedQuery,
  type ServerInfo,
  type RowField,
  type StartupOutcome,
  type StatementOutcome,
  type TableNode,
  type ObjectNode,
  type ColumnNode,
  type SearchHit,
  type SqlToken,
  type SqlDiagnostic,
  type CellEdit,
  type DmlStatement,
  type ColumnDef,
  type TableShape,
  type DdlStatement,
  type ImportPreview,
  type AgentTableBrief,
} from '../ipc'
import { frozenColumnStylesMeasured, pageOf, visibleOrder, DEFAULT_PAGE_SIZE } from '../grid/view'
import { EXPORT_FORMAT_LABELS, exportRows, type ExportFormat } from '../grid/export'
import { t as translate, toggleLanguage, type UiLanguage } from '../i18n'
import {
  readCollapsedGroups,
  toggleCollapsedGroup,
  writeCollapsedGroups,
  type KeyValueStore,
} from '../shell/connectionDisplay'
import ConnectionLabel from '../shell/ConnectionLabel.vue'
import ConnectionDialog from '../shell/ConnectionDialog.vue'
import BackupDialog from '../shell/BackupDialog.vue'
import AgentGenerateDialog from '../shell/AgentGenerateDialog.vue'
import type { ConnectionDialogMode } from '../shell/connectionDialog'
import NodeIcon from './NodeIcon.vue'
import SchemaDiffPanel from './SchemaDiffPanel.vue'
import {
  savedQuerySourceLabel,
  savedQuerySqlPreview,
  savedQueryTimeLabel,
  suggestQueryName,
} from './savedQueries'
import { serverMenuActions, type ServerMenuAction } from './serverMenu'
import {
  PARAM_KINDS,
  bindingLines,
  canSubmit,
  initialRows,
  missingNames,
  toValues,
  unusedHint,
  type ParamRow,
} from './queryParams'
import {
  columnLabel,
  groupByKind,
  loadColumns,
  mergeColumns,
  tableKey,
  treeNodeCount,
  userSchemas,
  type ColumnsByTable,
} from './objectTree'
import {executionTarget,
  applyCompletionItem,
  filterCompletions,
  highlightPieces,
  keywordCompletions,
  objectCompletions,
  outcomeSummary,
  pickDisplayedOutcome,
  snippetCompletions,
  stepCompletionIndex,
  wordBeforeCaret,
  type CompletionItem,
} from '../sql/editor'
// 编辑键（B1 接线）：纯逻辑在 `workspace/editing.ts`（11 个已单测函数，本片接前 6 条）。
// 口径照旧 —— 规则算在纯函数里、组件只把按键与选区喂进去再把结果落回 textarea，
// **不在这里重写一遍规则**（两处判必然分叉）。
import {
  autoIndentForNewline,
  autoPair,
  detectIndentStyle,
  indentSelection,
  indentUnitOf,
  matchBracket,
  moveOrDuplicateLines,
  toggleLineComment,
  type EditResult,
  type Selection as EditorSelection,
} from '../workspace/editing'
// 跳行列（B1 第二批）：解析与夹界在 `workspace/navigation.ts`（有行为单测），组件只做摆光标。
import { offsetOfJump, parseJumpInput } from '../workspace/navigation'
// 查找 / 替换（FR-EDIT-18）：字面量匹配、非重叠、替换串里的 `$&` 当字面量 —— 规则与 19 条单测同在一处。
import {
  findMatches,
  matchIndexAt,
  readout,
  replaceAll,
  replaceOne,
  stepMatch,
} from '../workspace/findReplace'
// 诊断上屏（B1 第三批 · FR-EDIT-56）：规则在领域层 `Db/src/lint.rs`，这里只把区间叠到高亮片段上。
import { decoratePieces } from '../workspace/diagnostics'
// 分隔条（FR-EDIT-13）：夹紧与步进是纯算术，摆在 `splitPane.ts`；组件只做测量、指针与 inline 高度。
import { SPLIT_MIN_PANE, SPLIT_STEP, clampSplitHeight, stepSplitHeight } from './splitPane'
// 撤销 / 重做（FR-EDIT-60）：栈与三档结论在 `workspace/undoStack.ts`。
// 合并规则**复用** `editing.ts` 的 `shouldCoalesce`（一处判，不在这里再写一份）。
import {
  newUndoState,
  pushUndo,
  redoDepth,
  redoOnce,
  stepForTextChange,
  undoDepth,
  undoOnce,
  type UndoSnapshot,
  type UndoState,
} from '../workspace/undoStack'

// **界面语言（1.8 双语）**：与标题栏同一套取值（zh-Hans / en）
// 口径：语言表只覆盖**界面外壳**；正文说明与服务端提示仍是中文（已在版本计划里登记未落）。
// 视图往底部面板打输出（图里的「输出 / 问题」两格就是收这个）
const emit = defineEmits<{
  (event: 'push-panel', entry: { text: string; level: 'info' | 'warn' | 'error'; source?: string }): void
  /** 结果集变了：把「几行几列 / 本片取了行」报给外壳（状态栏那两段读数就用它）。 */
  (event: 'result-stats', payload: { rows: number; cols: number; loaded: number; total: number }): void
}>()

/**
 * 外壳（命令面板 / 菜单）递进来的「开连接弹层」请求。
 *
 * 为什么要一个请求对象而不是布尔量：同一档连点两次（`seq` 变了）也要**重开一次**，
 * 布尔量在"已经开着"时是静默的。
 */
const props = defineProps<{
  dialogRequest?: { mode: ConnectionDialogMode; seq: number } | null
  /** 备份弹层的「开一次」请求序号（FR-IO-04）—— 与连接弹层同一套口径 */
  backupRequest?: number | null
}>()

/** 连接弹层的开合与档位 —— **状态归本视图**（弹层件只画与上报，不持有连接状态）。 */
const dialogOpen = ref(false)
const dialogMode = ref<ConnectionDialogMode>('current')
const connectionDialog = ref<InstanceType<typeof ConnectionDialog> | null>(null)

/**
 * 开弹层：置档位 + 按档位做该做的事。
 *
 * - `new`     —— 起一张新表单（`startNewConnectionForm`）；
 * - `edit`    —— 表单不动，把光标送到连接名那一格（原「编辑连接…」的落点，逐条照搬）；
 * - `current` —— 表单不动、也不抢焦点（「连接数据库」只管把表单摆出来）。
 */
function openConnectionDialog(mode: ConnectionDialogMode): void {
  if (mode === 'new') startNewConnectionForm()
  dialogMode.value = mode
  dialogOpen.value = true
  if (mode === 'edit') void nextTick(() => connectionDialog.value?.focusName())
}

/** 「新建连接」= 起一张**新表单**：换 id、名字 / 口令 / URL 导入清空、字段回默认（口径不变）。 */
function startNewConnectionForm(): void {
  formId.value = crypto.randomUUID()
  name.value = ''
  password.value = ''
  urlImport.value = ''
  urlImportNote.value = ''
  remember.value = true
  form.value = { ...LAB_CONNECTION }
  clearFailure()
  void refreshValidation()
}

const language = ref<UiLanguage>('zh-Hans')
function t(key: Parameters<typeof translate>[0], vars?: Record<string, string | number>): string {
  return translate(key, language.value, vars)
}

const form = ref<ConnectParams>({ ...LAB_CONNECTION })
const password = ref('')
const remember = ref(true)
/** 连接名（FR-CONN-02 的表单字段之一）；留空时按「库@主机」派生（沿用旧口径）。 */
const name = ref('')
/** 引擎（FR-CONN-02）：换引擎时端口 / SSL / 默认 schema **跟着类型走**（默认值在领域层，表单不另写一份）。 */
const dbType = ref('postgresql')
/** 从连接 URL 导入（FR-CONN-19）的输入与回执。 */
const urlImport = ref('')
const urlImportNote = ref('')
/** 表单逐项校验的读数（FR-CONN-06）：**规则只有一份**（领域层 `config::validate_form`），这里只显示它说的话。 */
const fieldProblems = ref<FieldProblem[]>([])

/** 这一条连接实际用的名字（留空 ⇒ 派生），校验与保存都走它。 */
const effectiveName = computed(() => name.value.trim() || `${form.value.database}@${form.value.host}`)
const problemOf = computed<Record<string, string>>(() => {
  const out: Record<string, string> = {}
  for (const problem of fieldProblems.value) out[problem.field] = problem.message
  return out
})
const formReady = computed(() => fieldProblems.value.length === 0)
const problemSummary = computed(() =>
  t('db.validation.summary', {
    n: fieldProblems.value.length,
    fields: fieldProblems.value.map((problem) => problem.message).join('、'),
  }),
)

/**
 * 跑一次逐项校验。端口**按文本**交上去（`0` / `65536` / 非数字由领域层当场拒）——
 * 界面不自己解析端口，否则就是"两套规则漂移"的来路。
 */
async function refreshValidation() {
  try {
    fieldProblems.value = await connectionValidate(
      effectiveName.value,
      form.value.host,
      String(form.value.port ?? ''),
      form.value.user,
    )
  } catch {
    // 校验通路本身坏了不该把表单锁死（保存时命令层还会再判一次）
    fieldProblems.value = []
  }
}

/** 换引擎：端口 / SSL / 默认 schema 照类型的默认值填（改的是"与类型相关"的那几格）。 */
async function switchDbType(kind: string) {
  dbType.value = kind
  try {
    const defaults = await connectionTypeDefaults(kind)
    dbType.value = defaults.dbType
    form.value = { ...form.value, port: defaults.port, sslMode: defaults.sslMode }
  } catch (e) {
    failure.value = describeError(e)
  }
  await refreshValidation()
}

/** 从连接 URL 导入：各字段填进表单；**认不出的参数如实列出**（不静默丢）。 */
async function importUrl() {
  const text = urlImport.value.trim()
  if (!text) return
  clearFailure()
  try {
    const parsed = await connectionImportUrl(text, formId.value, name.value.trim() || undefined)
    dbType.value = parsed.dbType
    name.value = parsed.name
    form.value = {
      host: parsed.host,
      port: parsed.port,
      database: parsed.database,
      user: parsed.user,
      sslMode: parsed.sslMode,
    }
    // URL 里带了口令 ⇒ 填进口令框（**只在这一次会话里**；保存时才落凭据存储，绝不进配置）
    if (parsed.password) password.value = parsed.password
    urlImportNote.value = parsed.ignoredParameters.length
      ? t('db.urlImport.ignored', { list: parsed.ignoredParameters.join('、') })
      : ''
    await refreshValidation()
  } catch (e) {
    urlImportNote.value = ''
    failure.value = describeError(e)
  }
}

// ── 「上次选中的连接」（FR-CONN-11）──────────────────────────────────────────────
//
// 口径与领域层 `config::ConnectionSelection::restore` **同一套**：只记 id；记住的那条
// 重启后还在就选它，不在了**回退列表首条**（不硬记一条已经不存在的）。
// 落点用 localStorage（WebView2 按应用持久化）—— 选中态是界面偏好，不塞进连接配置文件。
const SELECTION_KEY = 'doyah.connection.selectedId'

function rememberSelected(id: string) {
  try {
    window.localStorage.setItem(SELECTION_KEY, id)
  } catch {
    // 存不下不该挡住"选中"这件事本身
  }
}

/** 冷启动恢复：返回该选中的 id（记住的还在 ⇒ 它；否则首条；一条都没有 ⇒ null）。 */
function restoredSelection(available: string[]): string | null {
  let remembered: string | null = null
  try {
    remembered = window.localStorage.getItem(SELECTION_KEY)
  } catch {
    remembered = null
  }
  if (remembered && available.includes(remembered)) return remembered
  return available[0] ?? null
}
/** 启动 SQL（FR-CONN-17）：连接后自动执行；**逐条发、逐条报错**（一条失败不吞掉后面的） */
const startupSql = ref('')
const startup = ref<StartupOutcome[]>([])
// 服务端条件浏览（FR-DATA-02）：只生成 SQL 供预览，执行仍走 dbQuery（同一份输入只解析一次）
const browse = ref<{ table: string; schema: string } | null>(null)
const browseWhere = ref('')
const browseOrder = ref('')
const browseError = ref('')

function openBrowse(schema: string, table: string) {
  browse.value = { schema, table }
  browseWhere.value = ''
  browseOrder.value = ''
  browseError.value = ''
}

// ── 表设计器（1.5）：读结构 → 改列 → 变更集预览 → 只执行非破坏性那些 ──────────────────────
//
// 口径（与领域层 `ddl` 一致，界面这层要配合好）：
// ① **删除类只生成、不自动执行**：生成物按 `class` 分级，只有 `additive` / `altering` 会被
//    送进执行通路；`destructive` 只显示、供复制；
// ② **改类型是四步**（建临时列 / 搬值 / 删旧列 / 改名）—— 界面如实把四步都列出来，
//    其中"删旧列"标破坏性，所以**整段改类型不会被自动执行**（要用户自己复制去跑）；
// ③ 打不开结构（无可读原因）就如实报，不显示一个空面板让人以为表是空的。

const designer = ref<{ schema: string; table: string } | null>(null)
const shape = ref<TableShape | null>(null)
/** 编辑缓冲：列的下标 → 改动（只记改过的格子，不改的不进 DDL）。 */
const draftColumns = ref<ColumnDef[]>([])
const ddlPlan = ref<DdlStatement[]>([])

async function openDesigner(schema: string, table: string) {
  designer.value = { schema, table }
  shape.value = null
  ddlPlan.value = []
  draftColumns.value = []
  clearFailure()
  try {
    const loaded = await dbTableShape(schema, table)
    shape.value = loaded
    // 复制一份进编辑缓冲：**原始结构留着**（生成 DDL 要靠它算差异）
    draftColumns.value = loaded.columns.map((c) => ({ ...c }))
  } catch (e) {
    failure.value = describeError(e)
    designer.value = null
  }
}

function addDraftColumn() {
  draftColumns.value.push({ name: '', dataType: 'text', isNullable: true, defaultExpr: null })
  ddlPlan.value = []
}

function removeDraftColumn(index: number) {
  draftColumns.value.splice(index, 1)
  ddlPlan.value = []
}

/** 生成变更集预览（**只生成**）。 */
async function previewDdl() {
  if (!shape.value || !designer.value) return
  clearFailure()
  try {
    ddlPlan.value = await generateDdl({
      op: 'alter_columns',
      schema: designer.value.schema,
      table: designer.value.table,
      originalColumns: shape.value.columns,
      editedColumns: draftColumns.value,
    })
  } catch (e) {
    ddlPlan.value = []
    failure.value = describeError(e)
  }
}

/** 这批里哪些能自动执行（`additive` / `altering`）；破坏性的只给复制。 */
const runnableDdl = computed(() => ddlPlan.value.filter((s) => s.class !== 'destructive'))
const blockedDdl = computed(() => ddlPlan.value.filter((s) => s.class === 'destructive'))

/** 执行**非破坏性**那些；返回结果里逐句报成败。 */
async function applyDdl() {
  if (runnableDdl.value.length === 0) {
    failure.value = {
      message: '没有可自动执行的语句（破坏性语句只能复制出去自己跑）。',
      hint: '先点「生成变更集」看清将执行什么；含删除的变更请在生成面板里复制语句。',
    }
    return
  }
  busy.value = '执行 DDL…'
  clearFailure()
  try {
    outcomes.value = await dbRunDdl(runnableDdl.value.map((s) => s.bare))
    const failed = outcomes.value.find((o) => !o.ok)
    failure.value = failed?.failure ?? null
    if (!failed && designer.value) {
      // 执行成功就重读结构：界面显示"库里现在是什么"，而不是"我以为改成了什么"
      await openDesigner(designer.value.schema, designer.value.table)
      copied.value = `已执行 ${outcomes.value.length} 句`
      setTimeout(() => (copied.value = ''), 3000)
    }
  } catch (e) {
    failure.value = describeError(e)
  } finally {
    busy.value = ''
  }
}

/** 复制整份生成的语句（破坏性的那些靠这条路拿出去自己执行）。 */
async function copyDdl() {
  const text = ddlPlan.value.map((s) => s.sql).join('\n\n')
  try {
    await navigator.clipboard.writeText(text)
    copied.value = `已复制 ${ddlPlan.value.length} 句`
  } catch {
    copied.value = '复制失败：外壳不给剪贴板权限（可手动选中生成物复制）'
  }
  setTimeout(() => (copied.value = ''), 2500)
}

/** 生成预览（失败就把「为什么不行」如实显示，不静默给一句空 SQL） */
async function previewBrowse() {
  if (!browse.value) return
  browseError.value = ''
  try {
    const sql = await browseSql({
      table: browse.value.table,
      schema: browse.value.schema,
      whereClause: browseWhere.value,
      orderBy: browseOrder.value,
    })
    sqlText.value = sql
  } catch (e) {
    browseError.value = describeError(e).message
  }
}

/** 预览之后执行（**先看 SQL 再执行**：这是"生成 / 预览 / 执行同一份输入"的用法） */
async function runBrowse() {
  await previewBrowse()
  if (!browseError.value && sqlText.value) {
    sql.value = sqlText.value
    await run()
  }
}

// 结果网格的**显示态**：筛选词 + 排序列/方向（真正的比较逻辑在 `grid/view.ts`，那里有单测）
const filter = ref('')
const sortColumn = ref<number | null>(null)
const sortDesc = ref(false)
const copied = ref('')

/** 看得见的那一屏：先筛后排（序号是 `result.rows` 的下标） */
const visible = computed<number[]>(() =>
  result.value
    ? visibleOrder(result.value, filter.value, sortColumn.value === null ? null : { column: sortColumn.value, desc: sortDesc.value })
    : [],
)

/** 点表头：同一列再点就翻方向；换列则从升序开始 */
function toggleSort(column: number) {
  if (sortColumn.value === column) {
    sortDesc.value = !sortDesc.value
  } else {
    sortColumn.value = column
    sortDesc.value = false
  }
  // 排序 / 筛选变了就回第一页：留在第 5 页看新排序的结果没有意义
  page.value = 1
}

// 冻结列（FR-RES-05）：只冻最左边连续若干列。
// **宽度优先用实测值**（界面把每列的 offsetWidth 报上来），没量到才退回按表头估算 ——
// 估算是按表头字符数算的，而表头往往比内容短，结果就是"冻住了但表头被盖一半"。
const frozenCount = ref(0)
const measuredWidths = ref<Record<number, number>>({})
const frozenStyles = computed<Record<number, { left: string; zIndex: number }>>(() =>
  result.value
    ? frozenColumnStylesMeasured(result.value.columns, frozenCount.value, measuredWidths.value)
    : {},
)

/** 量一次表头的真实列宽（只在结果变化后量；量不到就让纯函数退回估算）。 */
async function measureColumns() {
  await nextTick()
  const heads = document.querySelectorAll<HTMLTableCellElement>('table.db__grid thead th')
  const observed: Record<number, number> = {}
  heads.forEach((head, index) => {
    const width = head.getBoundingClientRect().width
    if (Number.isFinite(width) && width > 0) observed[index] = Math.round(width)
  })
  measuredWidths.value = observed
}

// 分页（1.3）：**对当前可见序列再切分**，不是服务端分页（服务端分页走「按条件浏览」）
const page = ref(1)
const pageSize = ref(DEFAULT_PAGE_SIZE)
const paged = computed(() => pageOf(visible.value, page.value, pageSize.value))
/** 网格里真正画出来的那些行（导出也用这一份 —— 导出必须与眼前一致）。 */
const shownRows = computed(() => paged.value.rows)

/** 点表头：同一列再点就翻方向；换列则从升序开始 */
function cellStyle(index: number): Record<string, string> {
  const style = frozenStyles.value[index]
  if (!style) return {}
  return { position: 'sticky', left: style.left, zIndex: String(style.zIndex) }
}

/** 复制格式（1.3）：五种 —— 各格式的转义规则在 `grid/export.ts`（有单测）。 */
const copyFormat = ref<ExportFormat>('tsv')

/**
 * 复制**当前这一页**（与眼前一致 —— 不是偷偷导出全部）。
 *
 * 口径：导出/复制的范围 = 网格里真正画出来的那些行；要全量请在「按条件浏览」里用
 * LIMIT/OFFSET 从服务端取（那才是大结果集的正确姿势）。
 */
async function copyVisible() {
  if (!result.value) return
  const text = exportRows(result.value, shownRows.value, copyFormat.value, resultSource.value?.table)
  try {
    await navigator.clipboard.writeText(text)
    copied.value = `已复制 ${shownRows.value.length} 行（${EXPORT_FORMAT_LABELS[copyFormat.value]}）`
  } catch {
    copied.value = '复制失败：浏览器/外壳不给剪贴板权限（可手动选中表格复制）'
  }
  setTimeout(() => (copied.value = ''), 2500)
}

// ── 导入导出面板（1.6）：导出走"原子落盘"，导入走"预览 → 一个事务写入" ──────────────────
//
// 口径：**先预览再写库** —— 导入是"一次写很多行"的操作，用户必须先看见
// 「读了几行、丢了几行、为什么、列怎么对的」再决定写不写；预览不碰数据库，所以可以随便点。

const ioOpen = ref(false)
const exportPath = ref('')
const exportFormat = ref<'csv' | 'json'>('csv')
const exportNote = ref('')
const importPath = ref('')
const importTable = ref('')
const importHasHeader = ref(true)
const importPreview = ref<ImportPreview | null>(null)
const importNote = ref('')

/** 导出**当前 SQL 的结果**到文件（原子落盘：失败不留半截文件）。 */
async function runExport() {
  if (!exportPath.value.trim()) {
    exportNote.value = '先填目标文件路径'
    return
  }
  busy.value = '导出中…'
  clearFailure()
  try {
    const report = await exportToFile(sql.value, exportPath.value.trim(), exportFormat.value)
    exportNote.value = `已写 ${report.rows} 行 × ${report.columns} 列（${report.bytes} 字节）到 ${report.path}${
      report.truncated ? ' —— **已截断**：服务端还有更多行没取回来' : ''
    }`
  } catch (e) {
    exportNote.value = ''
    failure.value = describeError(e)
  } finally {
    busy.value = ''
  }
}

/** 预览导入：解析文件并与目标表列对账（**不碰数据库**）。 */
async function runPreviewImport() {
  if (!importPath.value.trim() || !importTable.value.trim()) {
    importNote.value = '先填文件路径与目标表'
    return
  }
  clearFailure()
  try {
    // 目标列从当前结果来源拿（同一张表）；没来源就让用户先点开那张表
    const columns = result.value?.columns ?? []
    importPreview.value = await previewImport(importPath.value.trim(), importHasHeader.value, columns)
    importNote.value = ''
  } catch (e) {
    importPreview.value = null
    failure.value = describeError(e)
  }
}

/** 执行导入（**一个事务**；中途失败整批回滚）。 */
async function runImportNow() {
  if (!importPreview.value) {
    importNote.value = '先「预览」看清会写入什么'
    return
  }
  busy.value = '导入中…'
  clearFailure()
  try {
    const report = await runImport({
      path: importPath.value.trim(),
      schema: resultSource.value?.schema,
      table: importTable.value.trim(),
      hasHeader: importHasHeader.value,
      targetColumns: result.value?.columns ?? [],
    })
    importNote.value = `已写入 ${report.inserted} 行（列：${report.columns.join(', ')}）；丢行 ${report.skipped.length}`
  } catch (e) {
    importNote.value = ''
    failure.value = describeError(e)
  } finally {
    busy.value = ''
  }
}

// ── 库与服务器管理面（1.7）：**读数只读**；危险操作只给语句、不代为执行 ────────────────────
//
// 口径（与领域层 `admin` 一致）：
// ① 维护命令与杀会话**只生成文本**——面板里没有"执行"按钮，只有"复制"；
// ② 会话列表按**危害**排（等锁优先），与领域层排序一致；
// ③ 删库确认要**逐字打库名**，判定在领域层（这里只把结果显示出来）。

// Schema 对比与同步（FR-DDL-04）：面板自己持两侧快照，本页只负责开关与「脚本进编辑器」
const schemaDiffOpen = ref(false)

/** 把同步脚本放进编辑器（**只放不执行**：执行仍走编辑器 + 危险分级那套动线）。 */
function openSchemaScript(text: string): void {
  sql.value = text
  tabNote.value = t('schema.openedNote')
}

const adminOpen = ref(false)
const adminDatabases = ref<DatabaseInfo[]>([])
const adminSessions = ref<SessionRow[]>([])
const adminStats = ref<TableStats[]>([])
const adminNote = ref('')
/** 维护 / 杀会话命令（只生成，不执行）。 */
const adminCommands = ref<MaintenanceCommand[]>([])
const adminCommandNote = ref('')

async function loadAdmin() {
  busy.value = '读管理面…'
  clearFailure()
  try {
    adminDatabases.value = await ipcAdminDatabases()
    adminSessions.value = await ipcAdminSessions()
    if (resultSource.value) {
      adminStats.value = await ipcAdminTableStats(resultSource.value.schema)
    }
    adminNote.value = ''
    // 慢查询排行与前三块一起取（面板一打开就有读数；扩展不可用时同样给指引）
    await loadSlowQueries()
  } catch (e) {
    failure.value = describeError(e)
  } finally {
    busy.value = ''
  }
}

/** 生成维护命令（**只生成、不执行**）。 */
async function loadMaintenance() {
  const table = resultSource.value?.table
  if (!table) {
    adminCommandNote.value = '先从对象树点开一张表（维护命令是按表给的）'
    return
  }
  try {
    adminCommands.value = await ipcMaintenanceSql(resultSource.value?.schema, table)
    adminCommandNote.value = '以下是**文本**：本侧不代为执行维护命令'
  } catch (e) {
    failure.value = describeError(e)
  }
}

/** 生成杀会话命令（只生成；先给 cancel，要 terminate 由用户自己选那句话）。 */
async function generateKill(pid: number, force: boolean) {
  try {
    const cmd = await ipcTerminateSql(pid, force)
    adminCommands.value = [cmd]
    adminCommandNote.value = `已生成 ${force ? 'terminate' : 'cancel'} 语句：本侧**不代为执行**`
  } catch (e) {
    failure.value = describeError(e)
  }
}

/** 复制管理命令（这是把破坏性语句拿出去的唯一通路 —— 面板里没有执行按钮）。 */
async function copyAdminCommands() {
  const text = adminCommands.value.map((c) => c.sql).join('\n\n')
  try {
    await navigator.clipboard.writeText(text)
    copied.value = `已复制 ${adminCommands.value.length} 条命令`
  } catch {
    copied.value = '复制失败：外壳不给剪贴板权限（可手动选中复制）'
  }
  setTimeout(() => (copied.value = ''), 2500)
}

// ── 慢查询排行（FR-DIAG-03）────────────────────────────────────────────────────────────
//
// 三条口径：
// ① **扩展不可用不是错误**：面板要显示「为什么 + 三步怎么办」，绝不能用空列表冒充
//    「没有慢查询」（那是假绿：用户会以为库很健康）；
// ② 排序口径三种（总耗时 / 平均耗时 / 调用次数），切换即重取 —— 口径字符串与领域层
//    `SlowQuerySort::parse` 一一对应，**不在前端另编一套**；
// ③ 失败给可读原因（原话 + 提示），不是静默空表。
const slowSort = ref<SlowQuerySortKey>('total')
const slowReport = ref<SlowQueryReport | null>(null)
const slowNote = ref('')

async function loadSlowQueries() {
  try {
    slowReport.value = await ipcSlowQueries(slowSort.value)
    slowNote.value = ''
  } catch (e) {
    // 读不到就说清读不到：清掉旧回包，免得把上一次的行当成这一次的
    slowReport.value = null
    slowNote.value = describeError(e)
  }
}

/** 排序文案（只在界面上用；口径键 = 领域层认的那三个字符串）。 */
const SLOW_SORT_LABELS: { key: SlowQuerySortKey; label: string }[] = [
  { key: 'total', label: '总耗时' },
  { key: 'mean', label: '平均耗时' },
  { key: 'calls', label: '调用次数' },
]

/**
 * 连接列表分组（布局对齐 macOS 封面图）：图里左栏是「连接列表」下有分组标题（示例：未分组）。
 *
 * 两条口径：
 * 1. **没分组的归到「未分组」，且这一档永远排最后**（其余按名字排 —— 顺序稳定，用户才记得住位置）；
 * 2. **当前连着的那个高亮**：拿 `info` 里的主机/端口/库与每条比对，**不另存一份"选中 id"**
 *    （两处状态迟早会不一致）。
 */
/**
 * 连接列表分组（布局对齐 macOS 封面图）：图里左栏是「连接列表」下有分组标题（示例：未分组）。
 *
 * 两条口径：
 * 1. **没分组的归到「未分组」，且这一档永远排最后**（其余按名字排 —— 顺序稳定，用户才记得住位置）；
 * 2. **当前连着的那个高亮**：拿 `info` 里的主机/端口/库与每条比对，**不另存一份"选中 id"**
 *    （两处状态迟早会不一致）。
 *
 * 分组与顺序本身在 `shell/connectionDisplay.ts`（与折叠状态同源），这里只取值。
 */
/** localStorage 的最小面；**取不到存储就当没有**（隐私模式 / 权限策略下访问本身就抛）。 */
function connectionStore(): KeyValueStore | null {
  try {
    return window.localStorage
  } catch {
    return null
  }
}

/**
 * 分组折叠状态（FR-CONN-15）：**落在 localStorage、冷启动读回**。
 *
 * 为什么不让它留在组件里：折叠态要是活不过一次视图重建，用户看到的是
 * 「我收起来的东西自己又出来了」—— 那正是 macOS 侧实测挂过、开了队列 L-59 的那条。
 * 落点口径与「上次选中的连接」（FR-CONN-11）一致：界面偏好，不塞进连接配置文件。
 */
const collapsedGroups = ref<Set<string>>(readCollapsedGroups(connectionStore()))

function toggleGroupSection(group: string | null): void {
  if (group === null) return
  collapsedGroups.value = toggleCollapsedGroup(collapsedGroups.value, group)
  writeCollapsedGroups(connectionStore(), collapsedGroups.value)
}

/** 名称为空时的占位文案（FR-CONN-14）。 */
const untitledConnection = computed(() => t('db.connections.untitled'))

/** 当前连着的**那条保存连接**（上下文栏与列表共用同一个显示件时要用它）。 */
const connectedConnection = computed<SavedConnection | null>(
  () => saved.value.find((c) => isConnected(c)) ?? null,
)

/** 这一条是不是当前连着的（拿 `info` 比对）。 */
function isConnected(connection: SavedConnection): boolean {
  const current = info.value
  if (!current) return false
  return (
    current.host === connection.host &&
    current.port === connection.port &&
    current.database === connection.database
  )
}

/**
 * 当前连着的那些**保存连接**的 id（弹层的列表高亮用）。
 *
 * 为什么给 id 而不是给个判断函数：高亮口径**只有一处**（就是上面的 `isConnected`），
 * 弹层里不再判一次 —— 拿 `info` 比对的两处迟早会不一致。
 * 注意是"所有命中的"（两条保存连接指同一个库时都会亮）。
 */
const connectedIds = computed<string[]>(() => saved.value.filter((c) => isConnected(c)).map((c) => c.id))

/** 已折叠的分组名（折叠状态落在 localStorage，这里只把它摊成可传的数组）。 */
const collapsedGroupNames = computed<string[]>(() => [...collapsedGroups.value])

/**
 * 对象树两种视图（图里那组切换：**层级视图 / 按类型分组**）。
 *
 * 一条口径（与"按需展开"不冲突）：按类型分组**只能在已经加载的对象里分** ——
 * 本侧不在连接时把整库元数据拉光。所以那一档会**如实说**"只含已加载的"。
 */
const objectView = ref<'hierarchy' | 'byKind'>('hierarchy')

/** 按类型分组的树：类型名 → 对象（只含已加载）。分组规则在 `objectTree.groupByKind`。 */
const kindGroups = computed<{ kind: string; items: ObjectNode[] }[]>(() =>
  groupByKind(loadedObjects.value),
)

/** 已加载的对象数（按类型分组那一档要用）。 */
const loadedObjectCount = computed(() => loadedObjects.value.length)

/** 树的数据行数（对象 + 已加载的列）—— 两档视图**必须相等**（切换不许丢节点）。 */
const layerNodeCount = computed(() => treeNodeCount(loadedObjects.value, columnsOf.value))

/**
 * 树的**扁平行**（两档视图共用一个渲染口 —— 各写一份模板必然慢慢漂成两种行为）。
 *
 * `header` 行是分组标题（schema 名 / 类型名），不可展开、不挂右键菜单；
 * `object` 行可点（生成查询）、可右键；`column` 行是第三层（只读，带数据类型）。
 */
type TreeRow =
  | { id: string; kind: 'server' }
  | { id: string; kind: 'schema'; label: string; expanded: boolean; loading: boolean; count: number }
  | { id: string; kind: 'type'; label: string; count: number }
  | { id: string; kind: 'object'; object: ObjectNode }
  | { id: string; kind: 'column'; owner: ObjectNode; column: ColumnNode }
  | { id: string; kind: 'empty'; owner: ObjectNode }

function objectRows(object: ObjectNode): TreeRow[] {
  const rows: TreeRow[] = [{ id: `obj:${tableKey(object.schema, object.name)}`, kind: 'object', object }]
  const key = tableKey(object.schema, object.name)
  if (expandedTables.value[key]) {
    const columns = columnsFor(object)
    if (columns.length === 0) {
      // 展开过、但一列都没取回来：**如实说**（不装作展开成功了）
      rows.push({ id: `empty:${key}`, kind: 'empty', owner: object })
    } else {
      rows.push(
        ...columns.map((column) => ({
          id: `col:${key}:${column.name}`,
          kind: 'column' as const,
          owner: object,
          column,
        })),
      )
    }
  }
  return rows
}

const treeRows = computed<TreeRow[]>(() => {
  const rows: TreeRow[] = []
  if (objectView.value === 'byKind') {
    // 「服务器」也在这一档的最前（两档视图只是同一批数据的两种排法 —— 服务器节点不属于
    // 任何一"类"，它是根；少了它，按类型分组这一档就没有可右键的地方）
    rows.push({ id: 'server:root', kind: 'server' })
    for (const group of kindGroups.value) {
      rows.push({
        id: `type:${group.kind}`,
        kind: 'type',
        label: group.kind,
        count: group.items.length,
      })
      for (const object of group.items) rows.push(...objectRows(object))
    }
    return rows
  }
  // 层级视图：**第一个节点是「服务器」**（FR-META-11 第一期 —— 三个动作挂在这一行上）；
  // schema 行**永远在**（它是展开开关）；展开过才有对象行，对象展开过才有列行。
  rows.push({ id: 'server:root', kind: 'server' })
  for (const schema of schemas.value) {
    const items = layerOf.value[schema]
    const isExpanded = !!expanded.value[schema]
    rows.push({
      id: `schema:${schema}`,
      kind: 'schema',
      label: schema,
      expanded: isExpanded,
      loading: loadingSchema.value === schema,
      count: items ? items.length : 0,
    })
    if (!isExpanded || !items) continue
    for (const object of items) rows.push(...objectRows(object))
  }
  return rows
})


/** 刷新：重取 schema 列表并丢掉已加载的层（重新按需展开） */
async function refreshObjects() {
  layerOf.value = {}
  expanded.value = {}
  columnsOf.value = {}
  expandedTables.value = {}
  objectQuery.value = ''
  objectHits.value = []
  await loadSchemas()
}

// ── SQL 工具条上的「库」下拉（布局对齐 macOS 封面图那条）──────────────────────────
//
// **说清它是什么**：本侧**没有"列出服务端所有库"的命令**，所以这个下拉给的是
// **「已保存连接里、同主机同用户的那些库」** —— 选一个就是**重连到那个库**
// （复用已有的连接流程，不新造一条通路）。
//
// 为什么不做成"从服务端列库"：那要新加一条命令与一次查询，而且列库需要权限；
// 现有的"保存过的连接"已经覆盖了日常切换的场景。**做不到的那一半如实写在提示里。**
const databaseOptions = computed(() => {
  const current = info.value
  if (!current) return [] as string[]
  const names = new Set<string>([current.database])
  for (const connection of saved.value) {
    if (connection.host === form.value.host && connection.user === form.value.user) {
      names.add(connection.database)
    }
  }
  return [...names]
})

/** 切库 = 重连到那个库（复用已保存连接；找不到就改表单里的库名再连）。 */
async function switchDatabase(name: string) {
  if (!name || name === info.value?.database) return
  const match = saved.value.find(
    (c) => c.database === name && c.host === form.value.host && c.user === form.value.user,
  )
  if (match) {
    await useSaved(match)
    return
  }
  // 没有对应的保存连接：改表单里的库名，让用户自己按「连接」（**不偷偷连**）
  form.value = { ...form.value, database: name }
}

/** 清空 SQL（**先问一句**）。 */
function clearSql() {
  if (sql.value.trim() && !window.confirm('清空编辑器里的 SQL？（这一步不能撤销）')) return
  sql.value = ''
  outcomes.value = []
  refreshHighlight()
}

const saved = ref<SavedConnection[]>([])
const info = ref<ServerInfo | null>(null)
const tables = ref<TableNode[]>([])
// ── 查询页签（SQL 工具条上方那条「查询 1 ×」+ 加号；图里点名的界面件）────────────────
//
// 之前模板引用了 `queryTabs` / `activeQueryTab` / `selectQueryTab` / `closeQueryTab` /
// `newQueryTab` / `stashActiveQuery`，**脚本区一个都没声明** —— 页签条整段渲染成空，
// 且渲染期读 `queryTabs.length` 就是读 `undefined.length`（一旦分支被走进就是 TypeError）。
// 本片以 macOS `AppState`（`tabs` / `selectedTabID` / `newQueryTab` / `closeTab`）为准补齐：
//   · **权威副本在页签里**（`queryTabs[i].sql`）—— 编辑器里的 `sql` 是**实时缓冲**，
//     由提交点 `stashActiveQuery()` 把缓冲写回当前页签；切 / 关 / 新建页签前先提交，
//     否则「页签内容」会在切换这一刻丢掉最后一段编辑（与 macOS `commitEditorDraft` 同口径）。
//   · **编号不复用**：关掉「查询 2」再新建仍是「查询 3」（与 macOS `TabNumberGenerator` 同口径）。
interface QueryTab {
  id: string
  title: string
  sql: string
  /**
   * 这张页签是不是**正在执行**（`FR-EXEC-07`：执行中的页签不可关闭）。
   *
   * 为什么放在页签上而不是用一个全局标记：执行虽然是全局单条，但「哪张页签在跑」
   * 是有归属的 —— 关错页签会把正在跑的那条结果与它的上下文一起丢掉。
   * 成功 / 失败 / 取消三条路都在 `finally` 里清掉，不漏一个出口。
   */
  running: boolean
}

/** 页签编号生成器（**只增不减**，编号不复用）。 */
function makeTabNumberGenerator(): () => number {
  let next = 1
  return () => next++
}
const nextQueryTabNumber = makeTabNumberGenerator()
/** 页签标题走语言表（与 macOS `workspaceTabTitle` =「查询 %d」/「Query %d」同一句）。 */
function queryTabTitle(n: number): string {
  return t('db.queryTab', { n })
}

/** 编辑器初始 SQL（第一张页签用它起头 —— 与改前单页签时的默认值一致）。 */
const DEFAULT_QUERY_SQL = 'select id, name, balance from app.accounts order by id limit 20'
/** 查询页签（至少一张：关到最后一张时按钮是灰的，见模板 `queryTabs.length <= 1`）。 */
const queryTabs = ref<QueryTab[]>([
  {
    id: crypto.randomUUID(),
    title: queryTabTitle(nextQueryTabNumber()),
    sql: DEFAULT_QUERY_SQL,
    running: false,
  },
])
/** 当前选中的页签 id（模板里 `tab.id === activeQueryTab` 用它判高亮）。 */
const activeQueryTab = ref(queryTabs.value[0].id)

/** 编辑器里的实时文本（**缓冲**，不是权威副本）；初始 = 第一张页签的 SQL。 */
const sql = ref(queryTabs.value[0].sql)

const activeQueryTabRecord = computed<QueryTab | undefined>(
  () =>
    queryTabs.value.find((tab) => tab.id === activeQueryTab.value) ??
    queryTabs.value[queryTabs.value.length - 1],
)

/** **提交点**：把编辑器缓冲写回当前页签的权威副本。读 `tab.sql` 的入口都要先调它。 */
function stashActiveQuery(): void {
  const tab = activeQueryTabRecord.value
  if (tab) tab.sql = sql.value
}

// 编辑器每落一笔就回写 —— 免得在各处赋值点（执行 / 清空 / 跳转 / EXPLAIN…）逐个补，漏一处就丢内容。
watch(sql, stashActiveQuery)

/** 换页签后要重做的那几件显示面的事（高亮 / 补全），与结果面解耦。 */
function afterQueryTabSwitch(): void {
  outcomes.value = []
  detail.value = null
  void refreshHighlight()
  void refreshCompletions()
}

/** 切到某张页签：**先提交当前页签**，再换选中的页签并把它的 SQL 装进编辑器。 */
function selectQueryTab(id: string): void {
  if (id === activeQueryTab.value) return
  stashActiveQuery()
  const target = queryTabs.value.find((tab) => tab.id === id)
  if (!target) return
  activeQueryTab.value = id
  sql.value = target.sql
  afterQueryTabSwitch()
}

/** 新建一张空页签并选中（编号不复用）。 */
function newQueryTab(): void {
  stashActiveQuery()
  const tab: QueryTab = {
    id: crypto.randomUUID(),
    title: queryTabTitle(nextQueryTabNumber()),
    sql: '',
    running: false,
  }
  queryTabs.value.push(tab)
  activeQueryTab.value = tab.id
  sql.value = ''
  afterQueryTabSwitch()
}

/**
 * 给某张页签打「正在执行」的标（`FR-EXEC-07`）。
 *
 * 唯一的写入口：执行函数在 `try` 前置真、在 `finally` 置假 —— 成功 / 失败 / 取消 / 提前 return
 * 都走同一个出口，这样才不会有「跑完了但页签永远关不掉」这种反向 bug。
 */
function markTabRunning(id: string, running: boolean): void {
  const tab = queryTabs.value.find((item) => item.id === id)
  if (tab) tab.running = running
}

/** 页签条上的一句回执（被拦下的操作要**说出为什么**，不能只是没反应）。 */
const tabNote = ref('')

/** 关一张页签：最后一张不许关；**执行中的页签也不许关**（`FR-EXEC-07`）。 */
function closeQueryTab(id: string): void {
  if (queryTabs.value.length <= 1) return
  const target = queryTabs.value.find((tab) => tab.id === id)
  // 执行中：按钮已置灰，这里是**同一口径的兜底**（键盘 / 程序化调用也拦得住），并给出可见原因
  if (target?.running) {
    tabNote.value = t('sql.tabRunningBlocked', { title: target.title })
    return
  }
  const index = queryTabs.value.findIndex((tab) => tab.id === id)
  if (index < 0) return
  tabNote.value = ''
  const wasActive = activeQueryTab.value === id
  queryTabs.value.splice(index, 1)
  if (!wasActive) return
  // 关掉的是当前页签 ⇒ 落到剩下最后一张（与 macOS `closeTab` 一致）
  const next = queryTabs.value[queryTabs.value.length - 1]
  activeQueryTab.value = next.id
  sql.value = next.sql
  afterQueryTabSwitch()
}

// ── 保存查询（FR-EDIT-14）：落在 `%APPDATA%\DoyahStudio\saved-queries.json` ──────────────
//
// 三条口径（都在判据里锁着）：
// ① 保存 / 已保存两个按钮在**执行按钮之前**（需求原文点名「在执行按钮之前」）；
// ② **同名 = 覆盖**，但未确认覆盖前**服务端不写盘**（回 `saved:false` + `conflict`）——
//    所以「提示覆盖保存」不是一句提示，而是真的没存进去，用户点「覆盖保存」才替换；
// ③ 回填两条路：当前页签（替换编辑器内容）与**新页签**（当前页签一字不动）。
//
// 名字的合规与「同名」判定全在领域层（`Db/src/saved_query.rs`），这里只做显示与转交。
const savedQueries = ref<SavedQuery[]>([])
const saveQueryPanelOpen = ref(false)
const saveQueryName = ref('')
const saveQueryError = ref('')
const savedQueryMenuOpen = ref(false)
/** 冲突时摆出来的**既有那条**（非空 ⇒ 面板上的按钮变成「覆盖保存」）。 */
const pendingOverwrite = ref<SavedQuery | null>(null)
/** 一次操作的结果话（保存成功 / 已回填），显示在按钮旁。 */
const savedQueryNote = ref('')
const savedQueryBusy = ref(false)
/**
 * **这一次要存的那段 SQL**（来源可以不是编辑器）。
 *
 * 为什么要一个变量而不是直接读 `sql.value`：保存面板现在有两个入口 —— 工具栏（存编辑器当前内容）
 * 与「AI 生成」结果区（存**生成的那段**，编辑器内容不动）。两处必须走**同一份**面板与同一套
 * 判重/覆盖规则，所以差异只落在「这段 SQL 从哪里来」这一格上。
 */
const saveQueryTargetSql = ref('')
/** 这次的面板是不是从「AI 生成」过来的（是 ⇒ 面板上明写「要存的是生成的那段，编辑器不动」）。 */
const saveQueryFromGenerator = ref(false)

/** 读列表：失败**如实说**，不当成「没有已保存查询」。 */
async function loadSavedQueries(): Promise<void> {
  try {
    savedQueries.value = await savedQueriesList()
  } catch (error) {
    saveQueryError.value = t('saveQuery.failed', { reason: describeError(error).message })
  }
}

/**
 * 打开保存面板。`sourceSql` 不传 ⇒ 存编辑器当前内容（工具栏那条路，行为与之前一字不差）；
 * 传了 ⇒ 存**那段文本**（「AI 生成」结果区那条路：生成结果不必先进编辑器就能存下来）。
 *
 * ⚠️ 模板里必须写成 `openSaveQueryPanel()`：写 `@click="openSaveQueryPanel"` 会把 MouseEvent
 * 当成 `sourceSql` 传进来 —— 那会存下一段 `[object Object]`，而且看着像「保存成功了」。
 */
function openSaveQueryPanel(sourceSql?: string): void {
  stashActiveQuery()
  const fromGenerator = typeof sourceSql === 'string'
  saveQueryTargetSql.value = fromGenerator ? sourceSql : sql.value
  saveQueryFromGenerator.value = fromGenerator
  saveQueryName.value = suggestQueryName(saveQueryTargetSql.value, activeQueryTabRecord.value?.title ?? '')
  saveQueryError.value = ''
  pendingOverwrite.value = null
  saveQueryPanelOpen.value = true
}

function closeSaveQueryPanel(): void {
  saveQueryPanelOpen.value = false
  pendingOverwrite.value = null
  saveQueryError.value = ''
  saveQueryFromGenerator.value = false
}

/**
 * 提交保存。`overwrite` 只在用户点了「覆盖保存」时为真 —— 界面**不自己判**同名，
 * 服务端说冲突就摆出既有那条（两处各判一遍的下场：界面以为不同名、服务端覆盖了）。
 */
async function submitSaveQuery(overwrite = false): Promise<void> {
  const name = saveQueryName.value.trim()
  if (!name) {
    saveQueryError.value = t('saveQuery.nameRequired')
    return
  }
  // 校验与写盘都认 `saveQueryTargetSql`（这一格才是「本次要存的东西」；读 `sql.value` 会把
  // 「AI 生成 → 存」这条路上编辑器里的旧内容存进去）。
  const target = saveQueryTargetSql.value
  if (!target.trim()) {
    saveQueryError.value = t('saveQuery.sqlRequired')
    return
  }
  savedQueryBusy.value = true
  saveQueryError.value = ''
  try {
    const report = await savedQuerySave({
      id: crypto.randomUUID(),
      name,
      sql: target,
      connectionId: connectedConnection.value?.id ?? null,
      connectionName: connectedConnection.value?.name ?? null,
      database: info.value?.database ?? null,
      overwrite,
    })
    savedQueries.value = report.queries
    if (!report.saved) {
      // 冲突：**没有写盘**。把既有那条摆出来，按钮换成「覆盖保存」。
      pendingOverwrite.value = report.conflict ?? null
      return
    }
    pendingOverwrite.value = null
    saveQueryPanelOpen.value = false
    saveQueryFromGenerator.value = false
    savedQueryNote.value = t('saveQuery.saved', { name })
  } catch (error) {
    saveQueryError.value = t('saveQuery.failed', { reason: describeError(error).message })
  } finally {
    savedQueryBusy.value = false
  }
}

/** 回填一条已保存查询（当前页签 / 新页签）。 */
function refillSavedQuery(query: SavedQuery, intoNewTab: boolean): void {
  savedQueryMenuOpen.value = false
  closeSaveQueryPanel()
  if (intoNewTab) {
    stashActiveQuery()
    const tab: QueryTab = { id: crypto.randomUUID(), title: query.name, sql: query.sql, running: false }
    queryTabs.value.push(tab)
    activeQueryTab.value = tab.id
    sql.value = query.sql
    afterQueryTabSwitch()
  } else {
    sql.value = query.sql
    stashActiveQuery()
    void refreshHighlight()
    void refreshCompletions()
  }
  savedQueryNote.value = t('saveQuery.refilled', { name: query.name })
}

/** 删一条（**只删这份登记**，不动数据库里的任何数据）。 */
async function deleteSavedQuery(id: string): Promise<void> {
  try {
    savedQueries.value = await savedQueryDelete(id)
    if (pendingOverwrite.value?.id === id) pendingOverwrite.value = null
  } catch (error) {
    saveQueryError.value = t('saveQuery.failed', { reason: describeError(error).message })
  }
}

/** 展开 / 收起已保存清单（展开时重读一遍：文件是唯一事实源，可能被同一台机器的另一个窗口改过）。 */
function toggleSavedQueryMenu(): void {
  savedQueryMenuOpen.value = !savedQueryMenuOpen.value
  if (savedQueryMenuOpen.value) void loadSavedQueries()
}

const sqlText = ref('')
// 单行详情（FR-DATA-05）：宽表竖排看、长 JSON 格式化看 —— **纯计算**，值检查在领域层
const detail = ref<{ index: number; fields: RowField[] } | null>(null)

/** 点某一行：调领域层的值检查，把这一行的每个字段竖排列出来 */
async function openDetail(index: number) {
  if (!result.value) return
  const fields = await inspectRow(result.value.columns, result.value.rows[index] ?? [])
  detail.value = { index, fields }
}
const result = ref<QueryResult | null>(null)

// 结果换了就：回第一页、重新量列宽。
// 为什么用 watch 而不是在每个赋值点手写：`result` 有好几条赋值路径（执行 / 逐段挑选 / 外键跳转 /
// 条件浏览），漏一处就会出现"换了结果还停在第 5 页"或"冻的列宽还是上一份结果的"。
watch(result, () => {
  page.value = 1
  void measureColumns()
  // 状态栏读数（结果集几行几列 / 本片取了行）：**同一处出口**，免得各赋值点漏报一处。
  // 没有结果时一律 0（不编造数字）。
  emit('result-stats', {
    rows: result.value ? result.value.rows.length : 0,
    cols: result.value ? result.value.columns.length : 0,
    loaded: result.value ? result.value.rows.length : 0,
    total: result.value ? result.value.returned : 0,
  })
})
const failure = ref<DbFailure | null>(null)
const busy = ref('')

// 外键跳转（FR-DATA-06）：元数据读回来缓存一次；**入口只在有目标时出现**
const fkEdges = ref<FkEdge[]>([])
const resultSource = ref<{ schema: string; table: string } | null>(null)

/** 连上之后读一次外键元数据（读不到就保持空 —— 那就没有入口，符合「没目标不显示」） */
async function loadForeignKeys() {
  try {
    fkEdges.value = await dbForeignKeys()
  } catch {
    fkEdges.value = []
  }
}

/** 某一格有没有可跳转目标（两个方向都算；**没有就不给入口**，这是需求点名的验收点） */
function cellFkTargets(columnName: string): { schema: string | null; table: string; column: string }[] {
  if (!resultSource.value || fkEdges.value.length === 0) return []
  const wantTable = resultSource.value.table.toLowerCase()
  const wantSchema = resultSource.value.schema.toLowerCase()
  const out: { schema: string | null; table: string; column: string }[] = []
  for (const edge of fkEdges.value) {
    const fromMatches =
      edge.fromTable.toLowerCase() === wantTable &&
      (!edge.fromSchema || edge.fromSchema.toLowerCase() === wantSchema)
    if (fromMatches) {
      edge.columns.forEach((local, i) => {
        if (local.toLowerCase() === columnName.toLowerCase() && i < edge.referencedColumns.length) {
          out.push({ schema: edge.toSchema, table: edge.toTable, column: edge.referencedColumns[i] })
        }
      })
    }
    const toMatches =
      edge.toTable.toLowerCase() === wantTable &&
      (!edge.toSchema || edge.toSchema.toLowerCase() === wantSchema)
    if (toMatches) {
      edge.referencedColumns.forEach((referenced, i) => {
        if (referenced.toLowerCase() === columnName.toLowerCase() && i < edge.columns.length) {
          out.push({ schema: edge.fromSchema, table: edge.fromTable, column: edge.columns[i] })
        }
      })
    }
  }
  return out
}

/** 跳过去：按目标表 + 目标列，用**这一格的值**生成查询（字面量转义在领域层，前端不自己拼） */
async function jumpTo(target: { schema: string | null; table: string; column: string }, value: string | null) {
  if (value === null) return
  try {
    const literal = /^-?\d+(\.\d+)?$/.test(value.trim())
      ? value.trim()
      : "'" + value.replace(/'/g, "''") + "'"
    const generated = await browseSql({
      table: target.table,
      schema: target.schema ?? undefined,
      whereClause: '"' + target.column.replace(/"/g, '""') + '" = ' + literal,
      limit: 200,
    })
    sql.value = generated
    await run()
    resultSource.value = { schema: target.schema ?? '', table: target.table }
  } catch (e) {
    failure.value = describeError(e)
  }
}

onMounted(async () => {
  try {
    saved.value = await connectionsList()
    // FR-CONN-11：冷启动恢复上次选中的那条（不在了就回退首条）
    const remembered = restoredSelection(saved.value.map((c) => c.id))
    const chosen = saved.value.find((c) => c.id === remembered)
    if (chosen) useSaved(chosen)
  } catch (e) {
    failure.value = describeError(e)
  }
  // 已保存查询（FR-EDIT-14）：一进来就读一遍，工具栏上的计数才是真的
  await loadSavedQueries()
  // 编辑器一进来就上一次高亮（纯计算，失败了也只是退回纯文本）
  await refreshHighlight()
  // 表单逐项校验：一进来先跑一次（"保存 / 连接"按钮的可用性以它为准）
  await refreshValidation()
})

// 表单改了 ⇒ 重算逐项校验（规则在领域层，这里只是"把改后的值递过去问一次"）
watch(
  [form, name, dbType],
  () => {
    void refreshValidation()
  },
  { deep: true },
)

/** 这套表单当前对应的连接 id（点列表里的连接 = 换成它的 id；新表单 = 新 id）。 */
const formId = ref(crypto.randomUUID())

// 外壳递进来的「开连接弹层」请求（命令面板的「连接数据库 / 新建连接 / 编辑连接」走这里）：
// 同一档连点两次 `seq` 也变，所以每次都**重开一次**（不像布尔量那样"开着就静默"）。
watch(
  () => props.dialogRequest,
  (request) => {
    if (!request) return
    openConnectionDialog(request.mode)
  },
)

/** 备份弹层（FR-IO-04）：状态归本视图（它要当前连接与当前库）。序号变化即开一次。 */
const backupOpen = ref(false)
watch(
  () => props.backupRequest,
  (seq) => {
    if (!seq) return
    backupOpen.value = true
  },
)

/** 点一条保存过的连接：把它填进表单（**口令不在这里**：口令在系统凭据管理器里）。 */
function useSaved(c: SavedConnection) {
  formId.value = c.id
  dbType.value = c.dbType
  name.value = c.name
  form.value = {
    host: c.host,
    port: c.port,
    database: c.database,
    user: c.username,
    sslMode: c.sslMode,
  }
  password.value = ''
  failure.value = null
  // FR-CONN-11：选中即记（重启后读回来）
  rememberSelected(c.id)
  void refreshValidation()
}

async function saveCurrent() {
  busy.value = '保存中…'
  clearFailure()
  try {
    if (!formReady.value) {
      failure.value = { message: problemSummary.value, hint: '把点名的那几项补齐再保存。' }
      return
    }
    saved.value = await connectionSave({
      id: formId.value,
      name: effectiveName.value,
      dbType: dbType.value,
      host: form.value.host,
      port: form.value.port,
      database: form.value.database,
      user: form.value.user,
      sslMode: form.value.sslMode,
      isReadOnly: false,
      password: password.value || undefined,
      rememberPassword: remember.value && !!password.value,
    })
    rememberSelected(formId.value)
  } catch (e) {
    failure.value = describeError(e)
  } finally {
    busy.value = ''
  }
}

async function removeSaved(c: SavedConnection) {
  busy.value = '删除中…'
  clearFailure()
  try {
    saved.value = await connectionDelete(c.id)
    if (formId.value === c.id) {
      formId.value = crypto.randomUUID()
    }
  } catch (e) {
    failure.value = describeError(e)
  } finally {
    busy.value = ''
  }
}

/** 服务端版本太长（PostgreSQL 18.6 on x86_64-windows…）⇒ 只显示前两段，完整值放 tooltip。 */
const versionShort = computed(() => {
  const v = info.value?.version ?? ''
  const first = v.split(',')[0] ?? v
  return first.length > 48 ? `${first.slice(0, 48)}…` : first
})

// ── 对象树（1.1）：展开一层取一层 + 对象搜索 + 右键菜单 ────────────────────────────────
//
// 口径：**不在连接时把整库元数据拉光** —— 第一层只问 schema，展开某个 schema 才问它下面的对象。
// 已展开的那一层缓存在 `layerOf`，搜索只搜**已经看见的那些**（与树里显示的必然一致）。

/** 已加载的层：schema 名 → 它下面的对象（`''` 这个键是「全部已加载对象的并集」，供搜索用）。 */
const layerOf = ref<Record<string, ObjectNode[]>>({})
/** 正在加载的 schema（展开时显示"加载中"，不假装已经有内容）。 */
const loadingSchema = ref('')
/** 展开的 schema 集合。 */
const expanded = ref<Record<string, boolean>>({})
/** 第三层：已加载的列（`schema.表名` → 列）。 */
const columnsOf = ref<ColumnsByTable>({})
/** 已展开的表（`schema.表名` 集合）。 */
const expandedTables = ref<Record<string, boolean>>({})
/** 正在取列的表（`schema.表名`；那一行显示"加载中"，不假装已经有内容）。 */
const loadingTable = ref('')
/** 对象搜索词与命中（`matchedOn` 要显示出来，不能只说"匹配"）。 */
const objectQuery = ref('')
const objectHits = ref<SearchHit[]>([])
/** 右键菜单：位置 + 目标对象；`null` = 没打开。 */
const contextMenu = ref<{ x: number; y: number; object: ObjectNode } | null>(null)
/**
 * 服务器节点右键菜单（FR-META-11 第一期）：**只挂在「服务器」那一行上**。
 *
 * 与对象菜单分开两处状态而不是合成一个：两者作用对象不同（一个是节点、一个是对象），
 * 合成一个就得在里面塞一个 `target: 'server' | 'object'` 的判别式 —— 那正是"两套菜单慢慢
 * 长成一个 if 堆"的来路。分开之后各自的呈现条件是"自己的状态非空"，互不干扰。
 */
const serverMenu = ref<{ x: number; y: number } | null>(null)

/**
 * 服务器节点三动作的可用性（**规则在 `views/serverMenu.ts`，只有一处**）。
 *
 * 已连接 ⇒ 连接置灰；未连接 ⇒ 断开置灰；有动作在路上 ⇒ 三个全置灰。
 * 置灰**不隐藏**：菜单里少一项，用户会以为功能不存在，而不是"现在不能用"。
 */
const serverActions = computed<ServerMenuAction[]>(() =>
  serverMenuActions({ connected: !!info.value, busy: !!busy.value }),
)

/** 菜单项文案（走语言表）。 */
function serverActionLabel(action: ServerMenuAction): string {
  return t(action.labelKey)
}

/** 置灰时的悬停提示：说清"为什么现在不能用"（不做灰着但不说为什么）。 */
function serverActionTip(action: ServerMenuAction): string {
  if (action.enabled) return serverActionLabel(action)
  const reason = action.reasonKey ? t(action.reasonKey) : ''
  return t('db.server.menu.disabledTip', { name: `${serverActionLabel(action)} `, reason })
}

function openServerMenu(event: MouseEvent) {
  contextMenu.value = null
  serverMenu.value = { x: event.clientX, y: event.clientY }
}

function closeServerMenu() {
  serverMenu.value = null
}

/** 两处菜单一起关（点树里的空白处时用）。 */
function closeMenus() {
  closeContextMenu()
  closeServerMenu()
}

/**
 * 执行服务器节点的一个动作。
 *
 * 口径：**置灰的动作点了也不做事**（菜单照常关掉，但不会偷偷发一次连接）——
 * 否则"灰着能点"就成了比"不给入口"更糟的假象。
 * 编辑连接**复用连接表单**（改的是上面那份表单，不新造一条通路）。
 */
async function runServerAction(action: ServerMenuAction) {
  closeServerMenu()
  if (!action.enabled) return
  if (action.id === 'connect') {
    await connect()
    return
  }
  if (action.id === 'disconnect') {
    await disconnect()
    return
  }
  const current = connectedConnection.value
  if (current) useSaved(current)
  // 编辑连接 → 开弹层（表单里的光标位置由弹层自己落到连接名那一格）
  openConnectionDialog('edit')
}

/** 已加载的全部对象（搜索的输入面）。 */
const loadedObjects = computed<ObjectNode[]>(() =>
  Object.values(layerOf.value).flat(),
)

/** 树：按 schema 排好的 (schema, 对象列表)；**只含已加载的层**（未展开的不占位、不假装）。 */
const tree = computed<{ schema: string; items: ObjectNode[] }[]>(() =>
  Object.entries(layerOf.value)
    .filter(([schema]) => schema !== '')
    .map(([schema, items]) => ({ schema, items }))
    .sort((a, b) => a.schema.localeCompare(b.schema)),
)

/** 第一层：schema 列表（连接后取一次）。**系统 schema 在这里就摘掉**（FR-META-04，
 * 过滤规则只有 `objectTree.isSystemSchema` 一处）。 */
const schemas = ref<string[]>([])
/** 元数据被行数上限截断时的读数（`0` = 没截断）—— 界面要如实说"可能不完整"（FR-META-07）。 */
const metadataTruncated = ref(0)

async function loadSchemas() {
  try {
    const report = await dbSchemas()
    schemas.value = userSchemas(report.rows)
    metadataTruncated.value = report.truncated ? report.limit : 0
    layerOf.value = {}
    expanded.value = {}
    columnsOf.value = {}
    expandedTables.value = {}
    clearFailure()
  } catch (e) {
    failure.value = describeError(e)
  }
}

/** 展开 / 收起一个 schema：**第一次展开才去问服务端**（有缓存就不重复问）。 */
async function toggleSchema(schema: string) {
  if (expanded.value[schema]) {
    expanded.value = { ...expanded.value, [schema]: false }
    return
  }
  expanded.value = { ...expanded.value, [schema]: true }
  if (layerOf.value[schema]) return
  loadingSchema.value = schema
  try {
    const report = await dbRelations(schema)
    layerOf.value = { ...layerOf.value, [schema]: report.rows }
    metadataTruncated.value = report.truncated ? report.limit : 0
    clearFailure()
  } catch (e) {
    failure.value = describeError(e)
    // 取不到就**如实收起**：不把一个空列表当成"这个 schema 是空的"
    expanded.value = { ...expanded.value, [schema]: false }
  } finally {
    loadingSchema.value = ''
  }
}

/** 能展开列的对象（表 / 视图 / 物化视图 / 外部表；序列没有列这一层）。 */
function canExpandColumns(object: ObjectNode): boolean {
  return (
    object.kind === 'table' ||
    object.kind === 'view' ||
    object.kind === 'materialized_view' ||
    object.kind === 'foreign_table'
  )
}

/**
 * 展开 / 收起一张表（**第三层**：表 → 列 + 数据类型）。
 *
 * 取数走 `loadColumns`（**一层一次**，不是逐表各问一次）—— 现在一次只展开一张表，
 * 但形状先钉住：将来「全部展开」也不会变成 N+1（判据按调用计数钉，见 `objectTree.test.ts`）。
 */
async function toggleTable(object: ObjectNode) {
  if (!canExpandColumns(object)) return
  const key = tableKey(object.schema, object.name)
  if (expandedTables.value[key]) {
    expandedTables.value = { ...expandedTables.value, [key]: false }
    return
  }
  expandedTables.value = { ...expandedTables.value, [key]: true }
  if (columnsOf.value[key]) return
  loadingTable.value = key
  try {
    const groups = await loadColumns(dbColumns, object.schema, [object.name])
    columnsOf.value = mergeColumns(columnsOf.value, groups)
    clearFailure()
  } catch (e) {
    failure.value = describeError(e)
    // 取不到就**如实收起**：不把一个空列表当成"这张表没有列"
    expandedTables.value = { ...expandedTables.value, [key]: false }
  } finally {
    loadingTable.value = ''
  }
}

/** 某张表已加载的列（没加载过就是空数组 —— 不是"没有列"）。 */
function columnsFor(object: ObjectNode): ColumnNode[] {
  return columnsOf.value[tableKey(object.schema, object.name)] ?? []
}

// ── 自然语言 → SQL（FR-AI-02）────────────────────────────────────────────────
//
// 视图这一侧只做两件交接：把「已加载的表」交给弹层（外发正文由 Rust 装配），
// 以及把用户点过「写入编辑器」的 SQL 放进编辑器缓冲 —— **不执行**。
// 弹层自己去问「先看要发什么」与「真发一次」，视图不拼提示词、不碰网络。

const generateOpen = ref(false)

/** 随请求外发的表摘要：**只含已加载过的那部分**（列没展开过就只给表名，不编列）。 */
const generateTables = computed<AgentTableBrief[]>(() =>
  loadedObjects.value
    .filter((object) => canExpandColumns(object))
    .map((object) => ({
      schema: object.schema,
      name: object.name,
      columns: columnsFor(object).map((column) => ({ name: column.name, dataType: column.dataType })),
    })),
)

/**
 * 打开生成弹层。一张表都没加载过时**先去取一层对象**（与对象树同一个口 `dbRelations`），
 * 否则外发正文里连表名都没有 —— 模型只能瞎编表名，那不是「生成 SQL」而是「猜」。
 */
async function openGenerate(): Promise<void> {
  if (!loadedObjects.value.length && schemas.value.length) {
    const target = schemas.value.includes('public') ? 'public' : schemas.value[0]
    loadingSchema.value = target
    try {
      const report = await dbRelations(target)
      layerOf.value = { ...layerOf.value, [target]: report.rows }
      expanded.value = { ...expanded.value, [target]: true }
      metadataTruncated.value = report.truncated ? report.limit : 0
    } catch (e) {
      // 取不到不拦着开弹层：弹层会如实说「一张表都没加载到」，仍可凭问题里的表名生成。
      failure.value = describeError(e)
    } finally {
      loadingSchema.value = ''
    }
  }
  generateOpen.value = true
}

/** 把用户确认过的 SQL 写进编辑器缓冲（watch(sql) 会回写当前页签）；**不执行**。 */
function applyGeneratedSql(text: string): void {
  if (!text.trim()) return
  sql.value = text
  generateOpen.value = false
  void refreshHighlight()
  void refreshCompletions()
  void nextTick(() => sqlArea.value?.focus())
}

/**
 * 「AI 生成」结果区点「存成已保存查询」：关弹层，走**同一条保存面板**，只是这次要存的是生成的那段。
 *
 * 三条都不做：不写编辑器（用户没点「写入编辑器」）、不执行、不跳过面板（面板里还能改名；
 * 同名仍由服务端先报冲突、用户确认才覆盖）。
 */
function saveGeneratedSql(text: string): void {
  if (!text.trim()) return
  generateOpen.value = false
  openSaveQueryPanel(text)
}

/** 类型分组标题的文案（种类名走语言表；认不出的种类如实归到「其他」）。 */
function kindLabel(kind: string): string {
  switch (kind) {
    case 'table':
      return t('db.kind.table')
    case 'view':
      return t('db.kind.view')
    case 'materialized_view':
      return t('db.kind.materializedView')
    case 'foreign_table':
      return t('db.kind.foreignTable')
    case 'sequence':
      return t('db.kind.sequence')
    case 'system':
      return t('db.kind.system')
    default:
      return t('db.kind.other')
  }
}

/** 搜索：空词 = 回到树的原貌（不把整库摊成平表）。 */
async function runObjectSearch() {
  if (!objectQuery.value.trim()) {
    objectHits.value = []
    return
  }
  try {
    objectHits.value = await searchObjects(loadedObjects.value, objectQuery.value)
  } catch (e) {
    failure.value = describeError(e)
  }
}

function openContextMenu(event: MouseEvent, object: ObjectNode) {
  contextMenu.value = { x: event.clientX, y: event.clientY, object }
}

function closeContextMenu() {
  contextMenu.value = null
}

/** 右键：浏览数据（只有表 / 视图这类**能取数**的对象才给这一项）。 */
function menuBrowse() {
  const target = contextMenu.value?.object
  closeContextMenu()
  if (!target) return
  openBrowse(target.schema, target.name)
}

/** 右键：生成查询（把对象塞进 SQL 编辑面，不自动执行 —— 生成与执行分开）。 */
function menuGenerateQuery() {
  const target = contextMenu.value?.object
  closeContextMenu()
  if (!target) return
  useTable({ schema: target.schema, name: target.name, kind: target.kind })
}

/** 右键：打开表设计器（1.5）—— 只有表 / 视图这类**有结构**的对象才有意义。 */
function menuDesignTable() {
  const target = contextMenu.value?.object
  closeContextMenu()
  if (!target) return
  void openDesigner(target.schema, target.name)
}

/** 右键：复制名（**限定名原样**：给人看 / 贴回来用。下发 SQL 的引号由服务端侧生成器负责）。 */
async function menuCopyName() {
  const target = contextMenu.value?.object
  closeContextMenu()
  if (!target) return
  const text = `${target.schema}.${target.name}`
  try {
    await navigator.clipboard.writeText(text)
    copied.value = `已复制 ${text}`
  } catch {
    copied.value = `复制失败：外壳不给剪贴板权限。名字是 ${text}`
  }
  setTimeout(() => (copied.value = ''), 2500)
}

function clearFailure() {
  failure.value = null
}

function describeError(e: unknown): DbFailure {
  if (e && typeof e === 'object' && 'message' in e && 'hint' in e) return e as DbFailure
  const text = e instanceof Error ? e.message : String(e)
  return { message: text, hint: '把这条原话与主机 / 端口 / 库名 / 用户名一起核对。' }
}

async function connect() {
  busy.value = '连接中…'
  clearFailure()
  try {
    // 启动 SQL 的切分在领域层做（注释丢掉、空段不算、字符串里的分号不切）。
    // ⚠️ 如实登记**这一处简化**：前端先按「分号 + 行尾」粗切一遍再交上去，
    // 所以字符串里带分号的启动 SQL（罕见）在前端就会被切错 —— 正解是让 Rust 收整段原文、
    // 由 `doyah_studio_db::config::split_statements` 切（下一段改接口时一并做）。
    const statements = startupSql.value.trim()
      ? startupSql.value
          .split(/;\s*(?:\r?\n|$)/)
          .map((s) => s.trim())
          .filter((s) => s.length > 0 && !s.startsWith('--'))
      : []
    const report = await dbConnect({ ...form.value, password: password.value || undefined }, statements)
    info.value = report.info
    startup.value = report.startup
    result.value = null
    await loadTables()
    await loadForeignKeys()
  } catch (e) {
    info.value = null
    tables.value = []
    startup.value = []
    fkEdges.value = []
    failure.value = describeError(e)
  } finally {
    busy.value = ''
  }
}

async function disconnect() {
  busy.value = '断开中…'
  try {
    await dbDisconnect()
    info.value = null
    tables.value = []
    result.value = null
    clearFailure()
  } catch (e) {
    failure.value = describeError(e)
  } finally {
    busy.value = ''
  }
}

async function loadTables() {
  // 1.1 起对象树按需展开：这个入口只剩「重新取第一层」（schema 列表）。
  // 保留命令名 `db_tables` 的那条通路见 `dbProbe`（自检仍要能列一次表）。
  await loadSchemas()
}

// ── 查询参数填值面板（FR-EXEC-17）──────────────────────────────────────────────────────
//
// 口径（都在判据里）：
// ① **有占位符才弹**：没参数的一条普通查询不该被面板打断；
// ② **缺值不许执行**：缺哪个一次说全（与领域层 `BindError::Missing` 同一个口径）；
// ③ **绑定结果只用于本次执行**：编辑器里的 `:name` / `$1` 原样留着 —— 它是可复用的模板；
// ④ 类型**用户选**、默认文本（猜类型的代价是整条语句失败）。

/** 面板开着没。 */
const paramOpen = ref(false)
/** 待执行的原文（占位符还在），绑定基于它。 */
const paramText = ref('')
/** 这一次执行走哪条路（单条 / 批量 / EXPLAIN ANALYZE）。 */
const paramMode = ref<'run' | 'batch' | 'analyze'>('run')
/** 面板上的参数行。 */
const paramRows = ref<ParamRow[]>([])
const paramError = ref('')
const paramBusy = ref(false)
/** 绑定回执（说清每个参数变成了什么）。 */
const paramNote = ref('')
const paramNoteBad = ref(false)

function openParameterPanel(text: string, scan: ParameterScan, mode: 'run' | 'batch' | 'analyze'): void {
  paramText.value = text
  paramMode.value = mode
  paramRows.value = initialRows(scan.sites)
  paramError.value = ''
  paramNote.value = ''
  paramNoteBad.value = false
  paramOpen.value = true
}

function closeParameterPanel(): void {
  paramOpen.value = false
  paramRows.value = []
  paramError.value = ''
}

/** 取消 = 这条语句**没有执行**（说出来，别让人以为已经跑过了）。 */
function cancelParameters(): void {
  closeParameterPanel()
  paramNote.value = t('sql.params.cancelled')
  paramNoteBad.value = false
}

/** 提交：绑定 → 执行（绑定失败就停在面板里，不去打扰服务端）。 */
async function submitParameters(): Promise<void> {
  const missing = missingNames(paramRows.value)
  if (missing.length) {
    paramError.value = t('sql.params.missing', { names: missing.join('、') })
    return
  }
  paramBusy.value = true
  paramError.value = ''
  try {
    const bound = await bindSqlParameters(paramText.value, toValues(paramRows.value))
    const list = bindingLines(bound)
      .map((line) => t('sql.params.boundLine', { name: line.name, kind: t(kindLabelKey(line.kind)), literal: line.literal }))
      .join('；')
    paramNote.value = t('sql.params.bound', { list })
    const unused = unusedHint(bound)
    if (unused) {
      // 多半是拼错：**说**出来，但不拦执行（SQL 里没有那个参数，执行本身是安全的）
      paramNote.value = `${paramNote.value} ${t('sql.params.unused', { names: unused })}`
      paramNoteBad.value = true
    } else {
      paramNoteBad.value = false
    }
    const text = bound.sql
    closeParameterPanel()
    await executeText(text, paramMode.value)
  } catch (e) {
    paramError.value = t('sql.params.failed', { reason: describeError(e).message })
  } finally {
    paramBusy.value = false
  }
}

/** 类型下拉的文案键（面板与回执共用一处）。 */
function kindLabelKey(kind: ParamRow['kind']): 'sql.params.kind.text' | 'sql.params.kind.number' | 'sql.params.kind.boolean' | 'sql.params.kind.null' {
  switch (kind) {
    case 'number':
      return 'sql.params.kind.number'
    case 'boolean':
      return 'sql.params.kind.boolean'
    case 'null':
      return 'sql.params.kind.null'
    default:
      return 'sql.params.kind.text'
  }
}

/** 面板能不能点「执行」（缺一个就不许 —— 模板与兜底同一个判据）。 */
const paramReady = computed(() => canSubmit(paramRows.value))

/**
 * **执行入口的闸**：先扫占位符 —— 有就弹面板，没有就直接执行。
 *
 * 扫描失败（IPC 异常）时**不拦执行**也不装作没事：记一句失败，然后照常执行
 * （此时占位符会由服务端报语法错，用户至少看得到真实原因）。
 */
async function beginExecution(text: string, mode: 'run' | 'batch' | 'analyze'): Promise<void> {
  try {
    const scan = await scanSqlParameters(text)
    if (scan.sites.length > 0) {
      openParameterPanel(text, scan, mode)
      return
    }
  } catch (e) {
    failure.value = describeError(e)
  }
  await executeText(text, mode)
}

/** 按路子执行（绑定后的语句 / 无参数语句都走这里）。 */
async function executeText(text: string, mode: 'run' | 'batch' | 'analyze'): Promise<void> {
  if (mode === 'run') {
    await runText(text)
  } else {
    await runBatchText(text, mode === 'analyze')
  }
}

async function run() {
  // FR-EXEC-14 同一口径（单条执行也认选区）；FR-EXEC-17 先在 `beginExecution` 里看有没有参数
  await beginExecution(currentExecutionSql(), 'run')
}

/** 单条执行（**已定文本**）：页签的「执行中」标在 `finally` 里清，三个出口都不漏。 */
async function runText(text: string): Promise<void> {
  const tabId = activeQueryTab.value
  markTabRunning(tabId, true)
  busy.value = '执行中…'
  clearFailure()
  try {
    result.value = await dbQuery(text)
  } catch (e) {
    result.value = null
    failure.value = describeError(e)
  } finally {
    markTabRunning(tabId, false)
    busy.value = ''
  }
}

// ── SQL 编辑面（1.2）：高亮 / 补全 / 多段执行 / 执行中可取消 / EXPLAIN ─────────────────

/** 高亮片段（词法在领域层 —— 与执行切分同一套规则）。 */
const pieces = ref<{ text: string; kind: SqlToken['kind'] }[]>([])
/** 逐段执行结果（多段时显示"哪句成、哪句败、各耗时"）。 */
const outcomes = ref<StatementOutcome[]>([])
/** 正在编辑的这一段要被查看的下标（默认按"先看失败、否则看最后一句"挑）。 */
const shownOutcome = ref<number | null>(null)
/** 补全：候选清单与当前高亮的候选下标。 */
const completions = ref<CompletionItem[]>([])
const completionIndex = ref(0)
/**
 * 清单一次露几条。
 *
 * 口径：**露出来的就是可选的** —— 显示与导航用同一个切片（`visibleCompletions`），
 * 否则会出现「高亮在第 9 条、屏幕上只有 8 条」这种按回车插错东西的形状。
 */
const VISIBLE_COMPLETION_ROWS = 8
const visibleCompletions = computed(() => completions.value.slice(0, VISIBLE_COMPLETION_ROWS))
/** 真高亮下标（越界先夹紧：候选被过滤变短时旧下标可能比新长度大）。 */
const activeCompletionIndex = computed(() =>
  stepCompletionIndex(completionIndex.value, 0, visibleCompletions.value.length),
)
const sqlArea = ref<HTMLTextAreaElement | null>(null)

// ── 分隔条（FR-EDIT-13 · 编辑区 ↔ 结果区）─────────────────────────────────
// 三条口径：① **自动高度是默认态**（`editorHeight === null` ⇒ 不写 inline 高度，观感与接线前一致）；
// ② 拖动只改编辑区高度，而容器是 flex 列、结果区 `flex: 1` ⇒ 两区高度**必然守恒**（不会总高溢出）；
// ③ 上下各 ≥120px（`SPLIT_MIN_PANE`），拖动与键盘走同一个夹紧函数。
const mainPane = ref<HTMLElement | null>(null)
const editorHeight = ref<number | null>(null)
const splitDragging = ref(false)
let dragStartY = 0
let dragStartHeight = 0

/** 量当前容器与编辑区高度；量不到给 0（夹紧函数据此只保下限，不会算出负数）。 */
function paneMetrics(): { container: number; editor: number } {
  const container = mainPane.value?.getBoundingClientRect().height ?? 0
  const editor = editorHeight.value ?? sqlArea.value?.getBoundingClientRect().height ?? 0
  return { container, editor }
}

/** 编辑区 inline 高度：自动态不产出 style（否则会把默认观感改成固定值）。 */
const editorStyle = computed(() =>
  editorHeight.value === null ? {} : { height: `${editorHeight.value}px` },
)

function detachSplitListeners() {
  window.removeEventListener('pointermove', onSplitMove)
  window.removeEventListener('pointerup', onSplitEnd)
  window.removeEventListener('pointercancel', onSplitEnd)
}

/** 按下分隔条：先把手上的自动高度**落成一个数**（否则第一次移动没有基准），再开始跟指针。 */
function onSplitDown(event: PointerEvent) {
  if (event.button !== 0) return
  event.preventDefault()
  const { container, editor } = paneMetrics()
  if (editorHeight.value === null && editor > 0) {
    editorHeight.value = clampSplitHeight(editor, container)
  }
  dragStartY = event.clientY
  dragStartHeight = editorHeight.value ?? editor
  splitDragging.value = true
  // 监听挂在 window 上：指针跑出这条细条（几乎必然）时拖动仍要继续。
  window.addEventListener('pointermove', onSplitMove)
  window.addEventListener('pointerup', onSplitEnd)
  window.addEventListener('pointercancel', onSplitEnd)
}

function onSplitMove(event: PointerEvent) {
  if (!splitDragging.value) return
  const { container } = paneMetrics()
  editorHeight.value = clampSplitHeight(dragStartHeight + (event.clientY - dragStartY), container)
}

function onSplitEnd() {
  splitDragging.value = false
  detachSplitListeners()
}

/** 键盘：↑ / ↓ 步进 16px（焦点在分隔条上时）。其他键不接管。 */
function onSplitKey(event: KeyboardEvent) {
  const delta = event.key === 'ArrowUp' ? -SPLIT_STEP : event.key === 'ArrowDown' ? SPLIT_STEP : 0
  if (!delta) return
  event.preventDefault()
  const { container, editor } = paneMetrics()
  editorHeight.value = stepSplitHeight(editorHeight.value ?? editor, delta, container)
}

/** 双击：回到自动高度（不是「回到某个魔法数字」——窗口多大就多高）。 */
function resetSplit() {
  editorHeight.value = null
}

onBeforeUnmount(detachSplitListeners)

async function refreshHighlight() {
  try {
    pieces.value = highlightPieces(sql.value, await highlightSql(sql.value))
  } catch {
    // 高亮失败不该挡住写 SQL：退回纯文本（不弹错、不清空编辑器）
    pieces.value = [{ text: sql.value, kind: 'punctuation' }]
  }
}

/** 光标移动 ⇒ 重算补全候选（只在有词时弹，避免一进编辑器糊一屏）。 */
async function refreshCompletions() {
  const area = sqlArea.value
  if (!area) {
    completions.value = []
    return
  }
  const word = wordBeforeCaret(sql.value, area.selectionStart ?? 0)
  if (!word) {
    completions.value = []
    return
  }
  const items = [
    ...keywordCompletions(),
    ...snippetCompletions(),
    ...objectCompletions(loadedObjects.value),
  ]
  completions.value = filterCompletions(items, word)
  completionIndex.value = 0
}

/**
 * Tab / 回车接受当前候选：把光标前那个词换成候选内容。
 *
 * 片段候选（`sel` / `ins` / `upd` / `del`）插入的是**展开后的模板**，光标落在模板里的 `$0`
 * —— 落笔逻辑在纯函数 `applyCompletionItem`（那里有行为单测），这里只负责摆光标与刷新。
 */
function acceptCompletion(item?: CompletionItem) {
  const chosen = item ?? visibleCompletions.value[activeCompletionIndex.value]
  const area = sqlArea.value
  if (!chosen || !area) return
  const caret = area.selectionStart ?? sql.value.length
  const result = applyCompletionItem(sql.value, caret, chosen)
  completions.value = []
  void applyEdit({ text: result.text, selection: { start: result.caret, end: result.caret } })
}

/**
 * 编辑器 keyup（补全刷新 / 光标同步）。
 *
 * ↑↓ 在有候选时**不重算候选**：`refreshCompletions` 会把高亮打回第一条，
 * 于是「按一下 ↓ 高亮跳回开头」—— 导航看起来像坏了，而根因在 keyup 这一侧。
 */
function onEditorKeyup(event: KeyboardEvent): void {
  if (completions.value.length > 0 && (event.key === 'ArrowUp' || event.key === 'ArrowDown')) {
    syncCaret()
    return
  }
  void refreshCompletions()
  syncCaret()
}

// ── 编辑键（B1 接线 · 第一批 6 条）：注释切换 / 移行 / 复制行 / 回车缩进 / Tab 缩进 / 自动配对 ──
//
// 只做「把按键喂给纯函数、再把结果落回 textarea」这一层：规则全在 `workspace/editing.ts`
// （那里有行为单测），这里不重写一遍。落回时**先把新全文写进 `sql`，再在 nextTick 之后摆光标** ——
// v-model 重渲染会把光标推到末尾，顺序反了每次按键光标都会跳到文章末尾。
const SQL_COMMENT_PREFIX = '--'

/** 编辑器当前的选区（字符下标；取不到就说「在末尾」）。 */
function editorSelection(area: HTMLTextAreaElement): EditorSelection {
  return { start: area.selectionStart ?? 0, end: area.selectionEnd ?? 0 }
}

/** 把一版文本与新选区落到编辑器上（**不记账**）：新全文 + 新选区 + 重算高亮与页签草稿。 */
async function writeEditor(snapshot: UndoSnapshot): Promise<void> {
  sql.value = snapshot.text
  await refreshHighlight()
  await nextTick()
  const area = sqlArea.value
  if (area) {
    area.selectionStart = snapshot.selection.start
    area.selectionEnd = snapshot.selection.end
  }
  caretOffset.value = snapshot.selection.end
  stashActiveQuery()
  void refreshCompletions()
}

/** 把一次编辑结果落到编辑器上：先记一步撤销，再写全文 + 摆光标 + 重算高亮与页签草稿。 */
async function applyEdit(result: EditResult): Promise<void> {
  if (result.text === sql.value) {
    // 内容没变（例如移行到边界是 no-op）：只摆光标，不重算高亮，也不记一步空的撤销
    const area = sqlArea.value
    if (area) {
      area.selectionStart = result.selection.start
      area.selectionEnd = result.selection.end
    }
    return
  }
  recordLineEdit(result.text, result.selection)
  await writeEditor({ text: result.text, selection: result.selection })
}

// ── 撤销 / 重做（FR-EDIT-60）──
//
// 为什么要自己记账：编辑器是 `<textarea>`，**原生撤销只认它自己的输入流**。本编辑器有大量
// 程序化写入（格式化 / 缩进 / 注释切换 / 片段插入 / 替换）—— 走过这些路径，那条流就断了：
// 之后按 Ctrl+Z 要么什么都不发生、要么把整段 SQL 退回到很早以前。现象就是「格式化之后一撤销 SQL 没了」。
//
// 口径：连续输入合并一步、行级编辑各一步（判断在 `undoStack.ts`，合并规则复用 `shouldCoalesce`）。
let undoState: UndoState = newUndoState({ text: sql.value, selection: { start: 0, end: 0 } })
const undoSteps = ref(0)
const redoSteps = ref(0)
/** 撤销面的一句回执（没得撤 / 栈被重建）：**不沉默** —— 按了没反应和「本来就没得撤」必须分得开。 */
const undoNote = ref('')

function publishUndo(): void {
  undoSteps.value = undoDepth(undoState)
  redoSteps.value = redoDepth(undoState)
}

/** 行级编辑记一步（移行 / 注释 / 缩进 / 格式化 / 替换 / 片段）：各算一步，永不与前一步合并。 */
function recordLineEdit(text: string, selection: EditorSelection): void {
  undoState = pushUndo(
    undoState,
    { text, selection },
    { kind: 'line', at: selection.start, atEnd: selection.end, atMs: Date.now() },
  )
  publishUndo()
  undoNote.value = ''
}

/** 打字记一步：位置由 `stepForTextChange` 从前后两版文本推出来（与光标追踪无关）。 */
function recordTyping(before: string, after: string, caretAfter: number): void {
  const step = stepForTextChange(before, after, Date.now())
  if (!step) return
  undoState = pushUndo(undoState, { text: after, selection: { start: caretAfter, end: caretAfter } }, step)
  publishUndo()
  undoNote.value = ''
}

/**
 * 撤销 / 重做。三档结论各说各的话：
 * 撤了（把那一版连同选区写回编辑器）/ 没得撤（如实说）/ 栈对不上屏幕（**重建栈并直说**）。
 */
async function applyUndoOrRedo(direction: 'undo' | 'redo'): Promise<void> {
  const outcome = direction === 'undo' ? undoOnce(undoState, sql.value) : redoOnce(undoState, sql.value)
  if (outcome.kind === 'applied') {
    undoState = outcome.state
    publishUndo()
    undoNote.value = ''
    await writeEditor(outcome.snapshot)
    return
  }
  if (outcome.kind === 'drifted') {
    // 文本被整篇换掉（切页签 / 回填已保存查询 / 打开文件）：旧栈记的是**另一份**文本，
    // 拿它去撤就是「把 A 页签的 SQL 撤到 B 页签里」—— 宁可重建栈并说清，也不猜。
    undoState = newUndoState({
      text: sql.value,
      selection: { start: caretOffset.value, end: caretOffset.value },
    })
    publishUndo()
    undoNote.value = t('sql.undo.rebuilt')
    return
  }
  undoNote.value = direction === 'undo' ? t('sql.undo.exhausted') : t('sql.redo.exhausted')
}

function menuUndo(): void {
  closeEditMenu()
  void applyUndoOrRedo('undo')
}

function menuRedo(): void {
  closeEditMenu()
  void applyUndoOrRedo('redo')
}

/** 打字入口：**先记账再刷新**（记账要用「打字前」的光标，syncCaret 会把它盖掉）。 */
function onEditorInput(event: Event): void {
  const area = event.target as HTMLTextAreaElement
  const before = sql.value
  const after = area.value
  recordTyping(before, after, area.selectionStart ?? after.length)
  sql.value = after
  void refreshHighlight()
  void refreshCompletions()
  syncCaret()
  stashActiveQuery()
}

/**
 * 编辑器按键总入口。
 *
 * 口径：**只接管它自己那几种组合**，其余一律放行 —— 打字、方向键、Ctrl+C/V、Shift+Enter 都走浏览器默认，
 * 不拦不是因为懒，是因为拦错了就会吃掉输入（否定面有测试）。
 */
function onEditorKeydown(event: KeyboardEvent): void {
  const area = sqlArea.value
  if (!area) return
  const selection = editorSelection(area)
  const mod = event.ctrlKey || event.metaKey

  // ⓪'''' 撤销 / 重做（FR-EDIT-60）：Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y。**必须自己接管**——
  // textarea 的原生撤销只认它自己的输入流，程序化写入（格式化 / 缩进 / 片段）之后按下去
  // 要么没反应、要么把整段内容退回到很早以前；接管后一律 preventDefault，不让两套栈打架。
  if (mod && !event.altKey && (event.key === 'z' || event.key === 'Z')) {
    event.preventDefault()
    void applyUndoOrRedo(event.shiftKey ? 'redo' : 'undo')
    return
  }
  if (mod && !event.shiftKey && !event.altKey && (event.key === 'y' || event.key === 'Y')) {
    event.preventDefault()
    void applyUndoOrRedo('redo')
    return
  }

  // ⓪ Ctrl+G 跳行列（FR-EDIT-19）：只开面板，**不改文本**
  if (mod && (event.key === 'g' || event.key === 'G')) {
    event.preventDefault()
    openGoto()
    return
  }

  // ⓪'' Ctrl+Shift+F 格式化 SQL（FR-EDIT-22）—— **必须排在 Ctrl+F 之前**：
  // 否则带 shift 的这一档会先被查找条吃掉（同一个 key，分享同一条分支）。
  if (mod && event.shiftKey && !event.altKey && (event.key === 'f' || event.key === 'F')) {
    event.preventDefault()
    void formatQuery()
    return
  }

  // ⓪' Ctrl+F 查找 / Ctrl+H 替换（FR-EDIT-18）：只开浮层，**不改文本**。
  // 必须 preventDefault —— 否则 WebView2 自己会弹一个浏览器查找条，两个查找条同时出现。
  if (mod && !event.shiftKey && !event.altKey && (event.key === 'f' || event.key === 'F')) {
    event.preventDefault()
    openFind('find')
    return
  }
  if (mod && !event.altKey && (event.key === 'h' || event.key === 'H')) {
    event.preventDefault()
    openFind('replace')
    return
  }

  // ① Ctrl+/ 注释切换（`--`；只动行首、保持缩进）
  if (mod && event.key === '/') {
    event.preventDefault()
    void applyEdit(toggleLineComment(sql.value, selection, SQL_COMMENT_PREFIX))
    return
  }

  // ② Alt+↑/↓ 移行；③ Alt+Shift+↓ 复制行
  if (event.altKey && (event.key === 'ArrowUp' || event.key === 'ArrowDown')) {
    event.preventDefault()
    const direction = event.shiftKey ? 'duplicate' : event.key === 'ArrowUp' ? 'up' : 'down'
    void applyEdit(moveOrDuplicateLines(sql.value, selection, direction))
    return
  }

  // ③.5 补全清单导航（B1 收尾）：↑↓ 在**可见候选**里循环移动，回车插入当前高亮。
  // 只在清单开着且不带修饰键时接管 —— 清单关着时 ↑↓ 照旧移光标、回车照旧自动缩进（否定面有测试）。
  if (completions.value.length > 0 && !mod && !event.altKey && !event.shiftKey) {
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault()
      completionIndex.value = stepCompletionIndex(
        activeCompletionIndex.value,
        event.key === 'ArrowDown' ? 1 : -1,
        visibleCompletions.value.length,
      )
      return
    }
    if (event.key === 'Enter') {
      event.preventDefault()
      acceptCompletion()
      return
    }
  }

  // ④ Tab / Shift+Tab 缩进 —— **有候选时仍归补全清单**（旧行为不夺走）
  if (event.key === 'Tab' && !mod && !event.altKey) {
    event.preventDefault()
    if (completions.value.length > 0) {
      acceptCompletion()
      return
    }
    const unit = indentUnitOf(detectIndentStyle(sql.value))
    void applyEdit(indentSelection(sql.value, selection, event.shiftKey ? -1 : 1, unit))
    return
  }

  // ⑤ Enter 自动缩进（继承当前行缩进；`{ ( [` 之后多一级；下一个字符是闭合符则回退一级）
  if (event.key === 'Enter' && !mod && !event.altKey && !event.shiftKey) {
    event.preventDefault()
    const caret = selection.end
    const lineStart = sql.value.lastIndexOf('\n', caret - 1) + 1
    const currentLine = sql.value.slice(lineStart, caret)
    const nextNonSpaceChar = /^\s*(\S)/.exec(sql.value.slice(caret))?.[1] ?? ''
    const unit = indentUnitOf(detectIndentStyle(sql.value))
    const indent = autoIndentForNewline(currentLine, nextNonSpaceChar, unit)
    const text = sql.value.slice(0, selection.start) + '\n' + indent + sql.value.slice(selection.end)
    const at = selection.start + 1 + indent.length
    void applyEdit({ text, selection: { start: at, end: at } })
    return
  }

  // ⑥ 自动配对：打出左半符 / 引号补右半；闭合符正好在光标处则跳过；有选区则包裹
  if (!mod && !event.altKey && !event.shiftKey && event.key.length === 1) {
    const outcome = autoPair(sql.value, selection, event.key)
    if (outcome) {
      event.preventDefault()
      void applyEdit({ text: outcome.text, selection: outcome.selection })
    }
  }
}

// ── 编辑面状态栏（B1 接线 · 第二批）：光标 行:列 / 缩进口径 / 括号配对 ─────────────────
//
// 三格全部照既有纯函数算（`editing.matchBracket` = FR-EDIT-50 · `detectIndentStyle` +
// `indentUnitOf` = FR-EDIT-54），组件只把光标位置喂进去，**不在这里重判一遍**（两处判必然分叉）。
// 光标位置单独存一份：textarea 的 selectionStart 不是响应式的，不记一份就不会重算。
const caretOffset = ref(0)

/** textarea 的**真**光标位置（取不到就保留上一次的值）。 */
function syncCaret(): void {
  const area = sqlArea.value
  if (area) caretOffset.value = area.selectionStart ?? 0
}

/** 字符偏移 ⇒ 1 基的行 / 列（状态栏口径：行、列都是 1 基，列是字符列不是字节列）。 */
function lineColumnAt(text: string, offset: number): { line: number; column: number } {
  const head = text.slice(0, Math.max(0, Math.min(offset, text.length)))
  const lines = head.split('\n')
  return { line: lines.length, column: (lines[lines.length - 1] ?? '').length + 1 }
}

/** 第一格：光标在哪（`行 N · 列 M`）。 */
const caretLabel = computed(() => {
  const at = lineColumnAt(sql.value, caretOffset.value)
  return t('sql.caret', { line: at.line, column: at.column })
})

/** 第二格：这份文本的缩进口径（多数口径，纯函数判；无缩进时是默认 4 空格）。 */
const indentLabel = computed(() => {
  const style = detectIndentStyle(sql.value)
  return style.kind === 'tab' ? t('sql.indentTab') : t('sql.indentSpaces', { n: style.width })
})

/** 第三格：括号配对（无括号 ⇒ 一个破折号；不配平 ⇒ 告警位，并说明是哪个括号）。 */
const bracketState = computed<{ kind: 'none' | 'matched' | 'unmatched'; text: string }>(() => {
  const match = matchBracket(sql.value, caretOffset.value)
  if (!match) return { kind: 'none', text: t('sql.bracketNone') }
  if (match.partner === null) {
    const here = lineColumnAt(sql.value, match.at)
    return {
      kind: 'unmatched',
      text: t('sql.bracketUnmatched', {
        char: sql.value[match.at] ?? '',
        line: here.line,
        column: here.column,
      }),
    }
  }
  const here = lineColumnAt(sql.value, match.at)
  const there = lineColumnAt(sql.value, match.partner)
  const [from, to] = match.at <= match.partner ? [here, there] : [there, here]
  return {
    kind: 'matched',
    text: t('sql.bracketMatched', {
      from: `${from.line}:${from.column}`,
      to: `${to.line}:${to.column}`,
    }),
  }
})

// ── 跳行列（FR-EDIT-19）：`Ctrl+G` 开一条小输入条，认「行」/「行:列」──────────────────
// 解析与超界夹取全在 `navigation.parseJumpInput` / `offsetOfJump`（有行为单测）；
// 这里只做三件事：开面板、把输入喂进去、把光标摆到算出来的偏移。
const gotoOpen = ref(false)
const gotoInput = ref('')
const gotoError = ref('')
const gotoBox = ref<HTMLInputElement | null>(null)

function openGoto(): void {
  gotoOpen.value = true
  gotoError.value = ''
  // 先填当前行号（多数时候是「跳去附近那一行」），并整段选中 —— 直接打就覆盖掉
  gotoInput.value = String(lineColumnAt(sql.value, caretOffset.value).line)
  void nextTick(() => {
    gotoBox.value?.focus()
    gotoBox.value?.select()
  })
}

function closeGoto(): void {
  gotoOpen.value = false
  gotoError.value = ''
  sqlArea.value?.focus()
}

/** 执行跳转：非法输入**不关面板、如实给原因**；超界由纯函数夹进全文（不算错）。 */
function applyGoto(): void {
  const parsed = parseJumpInput(gotoInput.value, sql.value)
  if (!parsed.ok) {
    gotoError.value = parsed.reason
    return
  }
  const at = offsetOfJump(sql.value, parsed.target)
  const area = sqlArea.value
  if (area) {
    area.focus()
    area.setSelectionRange(at, at)
  }
  caretOffset.value = at
  gotoOpen.value = false
  gotoError.value = ''
  void refreshCompletions()
}

// ── 编辑菜单（FR-EDIT-17）+ 查找 / 替换（FR-EDIT-18）──────────────────────────
//
// 现状对齐（写清为什么这一片现在才做）：
//   · 跳行列（FR-EDIT-19）、缩进 / 反缩进（FR-EDIT-20）、清除查询（FR-EDIT-21）**早就有各自的路**
//     （`Ctrl+G` + 状态栏按钮、`Tab` / `Shift+Tab`、工具条「清空」）—— 缺的是「一个入口能看见它们」；
//   · **查找 / 替换（FR-EDIT-18）此前全仓零实现**（连一个 find 函数都没有），这一片是新增能力；
//   · 格式化 SQL（FR-EDIT-22）下一轮才落领域层格式化器 ⇒ **本轮菜单里不放这一项**：
//     点了没反应的入口比没有入口更糟（用户会以为功能坏了）。
//
// 规则全在 `workspace/findReplace.ts`（19 条行为单测）；这里只做三件事：开合、把选区摆到命中上、把替换结果落回编辑器。
const editMenuOpen = ref(false)

function toggleEditMenu(): void {
  editMenuOpen.value = !editMenuOpen.value
  if (editMenuOpen.value) {
    // 同时只开一个浮层：另一处菜单（对象右键 / 服务器菜单 / 已保存清单）跟着收
    closeMenus()
    savedQueryMenuOpen.value = false
  }
}

function closeEditMenu(): void {
  editMenuOpen.value = false
}

const findOpen = ref(false)
const findTerm = ref('')
const findReplacement = ref('')
const findCaseSensitive = ref(false)
/** 当前停在第几处命中（0 基；-1 = 还没定位 / 没有命中） */
const findCurrent = ref(-1)
/** 替换回执与"没有匹配"这类结论 —— **必须有话说**，安静不是结论 */
const findNote = ref('')
const findBox = ref<HTMLInputElement | null>(null)
const replaceBox = ref<HTMLInputElement | null>(null)

const findHits = computed(() =>
  findMatches(sql.value, findTerm.value, { caseSensitive: findCaseSensitive.value }),
)
const findReadout = computed(() => readout(findHits.value, findCurrent.value))

/** 打开查找条：有选区就把选区当查询串（与主流编辑器同口径），否则沿用上一次查的词。 */
function openFind(mode: 'find' | 'replace' = 'find'): void {
  findOpen.value = true
  findNote.value = ''
  const area = sqlArea.value
  if (area && area.selectionEnd > area.selectionStart) {
    const picked = sql.value.slice(area.selectionStart, area.selectionEnd)
    if (picked && !picked.includes('\n') && picked.length <= 200) findTerm.value = picked
  }
  findCurrent.value = matchIndexAt(findHits.value, caretOffset.value)
  void nextTick(() => {
    const target = mode === 'replace' ? replaceBox.value ?? findBox.value : findBox.value
    target?.focus()
    target?.select()
  })
}

function closeFind(): void {
  findOpen.value = false
  findNote.value = ''
  // 焦点**等浮层真的被摘掉之后**再还给编辑器：同步抢焦点会被随后的移除动作打回 body
  void nextTick(() => sqlArea.value?.focus())
}

/**
 * 把编辑器选区摆到第 `index` 处命中上。
 *
 * `focus = false`（边打字边预览）时**不许抢焦点** —— 否则在输入框里每打一个字，焦点都被编辑器夺走，
 * 查找框连一个字都打不进去（这是这种浮层最经典的坏法）。
 */
function syncFindSelection(index: number = findCurrent.value, focus = true): void {
  const matches = findHits.value
  const area = sqlArea.value
  if (index < 0 || index >= matches.length) {
    findCurrent.value = -1
    return
  }
  if (!area) return
  const start = matches[index]
  if (focus) area.focus()
  area.setSelectionRange(start, start + findTerm.value.length)
  if (focus) caretOffset.value = start + findTerm.value.length
  findCurrent.value = index
}

function stepFind(direction: 1 | -1): void {
  const matches = findHits.value
  if (!matches.length) {
    findCurrent.value = -1
    return
  }
  findNote.value = ''
  syncFindSelection(stepMatch(matches.length, findCurrent.value, direction))
}

/** 替换结果落回编辑器（与编辑键同一条路：先写全文，nextTick 后摆光标）。 */
async function commitFoundText(text: string, caret: number): Promise<void> {
  recordLineEdit(text, { start: caret, end: caret })
  sql.value = text
  await refreshHighlight()
  await nextTick()
  const area = sqlArea.value
  if (area) area.setSelectionRange(caret, caret)
  caretOffset.value = caret
  stashActiveQuery()
  void refreshCompletions()
  // 文本变了 ⇒ 命中列表重算，光标处那一处成为"当前"
  findCurrent.value = matchIndexAt(findHits.value, caret)
}

function replaceCurrent(): void {
  if (!findTerm.value) {
    findNote.value = t('sql.find.emptyQuery')
    return
  }
  const matches = findHits.value
  if (!matches.length || findCurrent.value < 0) {
    findNote.value = t('sql.find.none')
    return
  }
  const result = replaceOne(sql.value, findTerm.value, findReplacement.value, matches[findCurrent.value], {
    caseSensitive: findCaseSensitive.value,
  })
  if (!result.count) {
    // 起点处已经不是那段文字（文本在此期间被改过）：**一个字都不改**，并如实说
    findNote.value = t('sql.find.none')
    findCurrent.value = matchIndexAt(findHits.value, caretOffset.value)
    return
  }
  void commitFoundText(result.text, result.caret)
  findNote.value = t('sql.find.note', { n: 1 })
}

function replaceAllFound(): void {
  if (!findTerm.value) {
    findNote.value = t('sql.find.emptyQuery')
    return
  }
  const result = replaceAll(sql.value, findTerm.value, findReplacement.value, {
    caseSensitive: findCaseSensitive.value,
  })
  if (!result.count) {
    findNote.value = t('sql.find.none')
    return
  }
  void commitFoundText(result.text, result.caret)
  findNote.value = t('sql.find.note', { n: result.count })
}

// 边打字边预览：查询串 / 大小写档变了就重算并**不抢焦点**地高亮第一处
watch([findTerm, findCaseSensitive], () => {
  findNote.value = ''
  if (!findOpen.value) return
  findCurrent.value = matchIndexAt(findHits.value, caretOffset.value)
  if (findCurrent.value >= 0) syncFindSelection(findCurrent.value, false)
})

// 菜单里的四项：都是既有动作，只是多了一个能看见的入口
function menuFind(): void {
  closeEditMenu()
  openFind('replace')
}

function menuGoto(): void {
  closeEditMenu()
  openGoto()
}

function menuIndent(delta: 1 | -1): void {
  closeEditMenu()
  const area = sqlArea.value
  const selection = area ? editorSelection(area) : { start: caretOffset.value, end: caretOffset.value }
  const unit = indentUnitOf(detectIndentStyle(sql.value))
  void applyEdit(indentSelection(sql.value, selection, delta, unit))
}

function menuClear(): void {
  closeEditMenu()
  clearSql()
}

// ── 格式化 SQL（FR-EDIT-22）────────────────────────────────────────────────────────────
//
// 规则**不在这一层**：外壳 `format_tool::format_content` 按「外部工具优先 → 内置兜底 → 如实拒绝」
// 判一遍（与按文件格式化同一套，不在这里另写一份 —— 同一规则两处实现必然分叉）。
// 组件只做三件事：取目标文本、把结果落回编辑器、把回执如实说出来。
//
// 三条口径：
//   ① **有选区只格式化选中段** —— 整篇格式化会把用户没在看的部分一起改掉，一次按键改全身不值当；
//   ② **没改动就一个字都不动**（连高亮都不重算），并说「检查过了，没有需要改的地方」；
//   ③ **拒绝要说清为什么** —— `engine === 'refused'`（浏览器旁路 / 认不出语言）时回执用告警色，
//      不许把「没格式化」说成「已格式化」（安静不是结论）。
const formatNote = ref('')
/** 回执是「没跑成」那一类（拒绝 / 出错）⇒ 用告警色，别和「已格式化」长一个样 */
const formatNoteBad = ref(false)
const formatBusy = ref(false)

async function formatQuery(preferBuiltin = false): Promise<void> {
  if (formatBusy.value) return
  const area = sqlArea.value
  const selection = area ? editorSelection(area) : { start: caretOffset.value, end: caretOffset.value }
  const hasSelection = selection.end > selection.start
  const target = hasSelection ? sql.value.slice(selection.start, selection.end) : sql.value
  if (!target.trim()) {
    formatNote.value = t('sql.format.empty')
    formatNoteBad.value = true
    return
  }
  formatBusy.value = true
  try {
    const outcome = await formatSql(target, preferBuiltin)
    formatNote.value = outcome.note
    formatNoteBad.value = outcome.engine === 'refused'
    // ② 没改动 ⇒ 编辑器一个字都不动（也不重算高亮：文本没变，重算只是白花时间）
    if (!outcome.changed) return
    const next = hasSelection
      ? sql.value.slice(0, selection.start) + outcome.content + sql.value.slice(selection.end)
      : outcome.content
    // 光标：有选区 ⇒ 选中「格式化后的那一段」（用户看得出改了哪儿）；整篇 ⇒ 原光标位置夹到新长度内
    const caret = hasSelection
      ? selection.start + outcome.content.length
      : Math.min(caretOffset.value, outcome.content.length)
    await applyEdit({ text: next, selection: { start: caret, end: caret } })
  } catch (e) {
    formatNote.value = t('sql.format.failed', { reason: describeError(e).message })
    formatNoteBad.value = true
  } finally {
    formatBusy.value = false
  }
}

function menuFormat(): void {
  closeEditMenu()
  void formatQuery()
}

// ── 编辑面静态检查上屏（FR-EDIT-03 检查器 → FR-EDIT-56 画出来）────────────────────────
//
// 规则在领域层 `Db/src/lint.rs`（15 条行为单测），这里只做三件界面的事：
//   ① 每次文本变化问一次诊断（与高亮同一节奏，不另设防抖计时器 —— 两套节奏必然不同步）；
//   ② 把诊断区间叠到高亮片段上（`workspace/diagnostics.decoratePieces`，只切不改文字）；
//   ③ 在编辑器下方列成可点的问题条（点一条 ⇒ 光标跳到那一处）。
// 浏览器旁路没有检查器 ⇒ `diagnoseSql` 回空表，于是既不下划线也不列问题 ——
// **不假装「已检查、没问题」**：检查器缺席时界面只是安静，不是绿的。
const diagnostics = ref<SqlDiagnostic[]>([])
/** 只认最后一次请求的结果：连着打字时先发的慢请求回来晚了，不能把新结果顶掉。 */
let diagnoseSeq = 0

async function refreshDiagnostics(): Promise<void> {
  const seq = (diagnoseSeq += 1)
  try {
    const list = await diagnoseSql(sql.value)
    if (seq === diagnoseSeq) diagnostics.value = list
  } catch {
    // 检查器失败不该挡住写 SQL：清掉标记，不弹错、不清空编辑器
    if (seq === diagnoseSeq) diagnostics.value = []
  }
}

watch(
  sql,
  () => {
    void refreshDiagnostics()
  },
  { immediate: true },
)

/** 高亮片段 + 诊断下划线（绘制层只切分，不重判规则）。 */
const decoratedPieces = computed(() => decoratePieces(pieces.value, diagnostics.value))

/** 问题条的一行：位置 + 一句说明（位置 1 基行列，与状态栏同一口径）。 */
const problemRows = computed(() =>
  diagnostics.value.map((item) => {
    const at = lineColumnAt(sql.value, item.start)
    return { ...item, line: at.line, column: at.column }
  }),
)

/** 点问题条：把光标搬到那一处（顺手收起跳转面板与补全清单，免得抢焦点）。 */
async function jumpToProblem(offset: number): Promise<void> {
  gotoOpen.value = false
  completions.value = []
  const area = sqlArea.value
  if (!area) return
  area.focus()
  area.setSelectionRange(offset, offset)
  caretOffset.value = offset
  await nextTick()
  syncCaret()
}

/** 当前编辑器里的**选区文本**（没有选区 / 不是 textarea ⇒ 空串）。 */
function selectedSql(): string {
  const area = sqlArea.value
  const begin = area.selectionStart ?? 0
  const end = area.selectionEnd ?? 0
  if (end <= begin) return ''
  return area.value.slice(begin, end)
}

/**
 * **执行目标**（FR-EXEC-14）：有选区只跑选中的那段，没有选区跑整篇 —— 自动判定。
 *
 * 判定规则全在 `sql/editor.ts::executionTarget`（纯函数、有判据）；
 * 这里只负责把选区从 DOM 取出来喂给它，**不在这里重判一遍**（两处判必然分叉）。
 */
function currentExecutionSql(): string {
  return executionTarget(sql.value, selectedSql()).sql
}

/** **多段执行**：一次提交多条，逐段报告；显示"先看失败、否则看最后一句"。 */
async function runBatch(analyze: boolean) {
  // FR-EXEC-17：有占位符先填值（EXPLAIN 那条路也一样 —— 占位符原样发给服务端只会报语法错）
  await beginExecution(currentExecutionSql(), analyze ? 'analyze' : 'batch')
}

/** 多段执行（**已定文本**）：与 `runText` 同一口径 —— 执行中标在 `finally` 里清。 */
async function runBatchText(text: string, analyze: boolean) {
  const tabId = activeQueryTab.value
  markTabRunning(tabId, true)
  busy.value = analyze ? '生成并执行计划…' : '执行中…'
  clearFailure()
  try {
    // FR-EXEC-14：有选区只跑选中的那段（用户框出来就是要跑那段）。
    let pending = text
    if (analyze) {
      // EXPLAIN 只对单条：多段会被拒（并说明为什么），这里如实把拒绝端出来
      pending = await explainStatement(pending, true)
    } else {
      // **危险语句先要确认**（1.4）：无 WHERE 的 UPDATE/DELETE、DROP、TRUNCATE。
      // 判定在领域层（只认能确凿认出来的），界面只负责弹框；只读连接会被判 forbidden、直接拒。
      const risk = await statementRisk(pending)
      if (risk === 'forbidden') {
        failure.value = {
          message: '这条连接标了只读：写语句不发送。',
          hint: '要用写功能请新建一条不带只读标记的连接（只读是本机保护，不替代数据库权限）。',
        }
        return
      }
      if (risk === 'confirm') {
        const ok = window.confirm(
          '这条语句被判定为破坏性操作（无 WHERE 的写语句，或 DROP / TRUNCATE）。\n\n确认要执行吗？',
        )
        if (!ok) {
          return
        }
      }
    }
    outcomes.value = await dbRunBatch(pending)
    const pick = pickDisplayedOutcome(outcomes.value)
    shownOutcome.value = pick
    if (pick !== null) {
      const chosen = outcomes.value[pick]
      result.value = chosen.result
      if (!chosen.ok) failure.value = chosen.failure
    } else {
      result.value = null
    }
  } catch (e) {
    outcomes.value = []
    failure.value = describeError(e)
  } finally {
    markTabRunning(tabId, false)
    busy.value = ''
  }
}

/** 只生成计划（不执行）—— 与「条件浏览」同一姿势：先看将要执行什么。 */
async function showPlan() {
  clearFailure()
  try {
    sql.value = await explainStatement(sql.value, false)
    await refreshHighlight()
    await runBatch(false)
  } catch (e) {
    failure.value = describeError(e)
  }
}

/** **取消当前查询**：往服务端发取消请求，不是本地"不等了"。 */
async function cancelRunning() {
  try {
    await dbCancel()
    busy.value = '已发取消请求（服务端可能已在返回路上）'
    setTimeout(() => {
      if (busy.value.startsWith('已发取消')) busy.value = ''
    }, 2500)
  } catch (e) {
    failure.value = describeError(e)
  }
}

/** 点某一段的结果：网格换成那一段。 */
function selectOutcome(index: number) {
  shownOutcome.value = index
  const chosen = outcomes.value[index]
  result.value = chosen?.result ?? null
  failure.value = chosen && !chosen.ok ? chosen.failure : null
}

// ── 写回与事务（1.4）：内联编辑 → 生成 DML → 一次事务提交 ─────────────────────────────
//
// 口径（照领域层 `writeback` 那三条，界面这层要配合好）：
// ① **无主键不给编辑入口**：定位不到"是哪一行"就不许改（这不是体验问题，是数据正确性）；
// ② **只读连接只给预览、不给提交**：语句照样生成给用户看，但提交按钮不可用；
// ③ **提交前必须先看 DML**：不提供"直接提交"的捷径 —— 那正是"改错了才发现"的来路。

/** 当前结果来源表的**主键列**（空 = 无主键 ⇒ 不给编辑）。 */
const primaryKey = ref<string[]>([])
/** 只读标记（连接时设定）。 */
const readOnly = ref(false)
/** 编辑缓冲：`行下标:列下标` → 新值。 */
const cellEdits = ref<Record<string, string>>({})
/** 正在编辑的那一格（`行:列`）。 */
const editingCell = ref('')
/** 生成出来的 DML（提交前必须先有它）。 */
const pendingDml = ref<DmlStatement[]>([])

const canEditCells = computed(() => !readOnly.value && primaryKey.value.length > 0)
const editCount = computed(() => Object.keys(cellEdits.value).length)

function cellKey(row: number, column: number): string {
  return `${row}:${column}`
}

/** 这一格当前显示的文本（有编辑缓冲就用缓冲值）。 */
function cellText(row: number, column: number, cell: string | null): string {
  const edited = cellEdits.value[cellKey(row, column)]
  if (edited !== undefined) return edited
  return cell === null ? '' : cell
}

/** 双击进入编辑（只读 / 无主键时不给进）。 */
function beginEdit(row: number, column: number) {
  if (!canEditCells.value) return
  editingCell.value = cellKey(row, column)
}

function commitEdit(row: number, column: number, value: string) {
  const key = cellKey(row, column)
  cellEdits.value = { ...cellEdits.value, [key]: value }
  editingCell.value = ''
  pendingDml.value = []
}

/** 把一行按主键值拼成 `RowKey`（值取自**当前显示的那一行**）。 */
function rowKeyOf(rowIndex: number): { columns: string[]; values: (string | null)[] } | null {
  if (!result.value || primaryKey.value.length === 0) return null
  const keys: (string | null)[] = []
  for (const column of primaryKey.value) {
    const at = result.value.columns.indexOf(column)
    if (at < 0) return null
    const cell = result.value.rows[rowIndex]?.[at] ?? null
    keys.push(cell)
  }
  return { columns: [...primaryKey.value], values: keys }
}

/** 编辑缓冲 → 领域层的编辑集（**值列是数值时按数值写**，避免 `"id" = '1'` 这种跨类型比较）。 */
function cellEditSet(): CellEdit[] {
  if (!result.value || !resultSource.value) return []
  const out: CellEdit[] = []
  for (const [key, value] of Object.entries(cellEdits.value)) {
    const [rowText, columnText] = key.split(':')
    const row = Number(rowText)
    const column = Number(columnText)
    const rowKey = rowKeyOf(row)
    const columnName = result.value.columns[column]
    if (!rowKey || !columnName) continue
    const numeric = result.value.numRows?.[row]?.[column]
    out.push({
      schema: resultSource.value.schema,
      table: resultSource.value.table,
      key: rowKey,
      column: columnName,
      value,
      valueIsNumeric: typeof numeric === 'number',
    })
  }
  return out
}

/** 生成 DML（**只生成**）：先让用户看清将执行什么。 */
async function previewDml() {
  clearFailure()
  try {
    pendingDml.value = await editsToDml(cellEditSet())
    copied.value = `将执行 ${pendingDml.value.length} 条`
    setTimeout(() => (copied.value = ''), 2500)
  } catch (e) {
    pendingDml.value = []
    failure.value = describeError(e)
  }
}

/** 提交（一批一次事务）；`rollback` 为真时跑完回滚 —— 也就是"先真跑一遍再撤回"。 */
async function submitWriteback(rollback: boolean) {
  if (pendingDml.value.length === 0) {
    failure.value = {
      message: '还没有要执行的语句：先点「生成 SQL」看清将执行什么。',
      hint: '本侧不提供"跳过预览直接提交"的捷径 —— 那正是改错了才发现的来路。',
    }
    return
  }
  busy.value = rollback ? '试跑（跑完回滚）…' : '提交中…'
  clearFailure()
  try {
    const statements = pendingDml.value.map((d) => d.sql)
    outcomes.value = await dbWriteBatch(statements, rollback)
    const failed = outcomes.value.find((o) => !o.ok)
    if (failed) {
      failure.value = failed.failure
    } else {
      copied.value = rollback
        ? `试跑完成：${outcomes.value.length} 条都改到，已回滚（值未变）`
        : `已提交：${outcomes.value.length} 条`
      setTimeout(() => (copied.value = ''), 4000)
      if (!rollback) {
        cellEdits.value = {}
        pendingDml.value = []
        await run() // 重新取一次真值，界面不显示"我改成了什么"而是"库里现在是什么"
      }
    }
  } catch (e) {
    failure.value = describeError(e)
  } finally {
    busy.value = ''
  }
}

/** 结果来源变了 / 结果换了 ⇒ 重新读主键与只读标记（编辑入口的依据）。 */
watch(resultSource, async () => {
  pendingDml.value = []
  cellEdits.value = {}
  if (!resultSource.value) {
    primaryKey.value = []
    return
  }
  try {
    primaryKey.value = await dbPrimaryKey(resultSource.value.schema, resultSource.value.table)
  } catch {
    primaryKey.value = []
  }
})

onMounted(async () => {
  try {
    readOnly.value = await dbReadOnly()
  } catch {
    readOnly.value = false
  }
})

function useTable(t: ObjectNode) {
  // 记住"这一屏是从哪张表来的"——外键入口只对**那张表**的列才有意义
  resultSource.value = { schema: t.schema, table: t.name }
  sql.value = `select * from ${t.schema}.${t.name} limit 50`
}

async function probe() {
  busy.value = '自检中…'
  clearFailure()
  try {
    await loadTables()
    result.value = await dbQuery('select 1 as one')
    await dbQuery(sql.value)
    result.value = await dbQuery(sql.value)
  } catch (e) {
    failure.value = describeError(e)
  } finally {
    busy.value = ''
  }
}
</script>

<template>
  <section class="db">
    <!-- 连接弹层（对齐 macOS ConnectionSettingsSheet 的呈现形态）：
         表单字段 / 连接列表 / 按钮行为都是从下面主区**搬**过去的（逐条照搬，不是重写）。 -->
    <ConnectionDialog
      ref="connectionDialog"
      v-model:form="form"
      v-model:name="name"
      v-model:db-type="dbType"
      v-model:password="password"
      v-model:remember="remember"
      v-model:url-import="urlImport"
      :open="dialogOpen"
      :mode="dialogMode"
      :language="language"
      :busy="busy"
      :effective-name="effectiveName"
      :problems="problemOf"
      :ready="formReady"
      :summary="problemSummary"
      :connections="saved"
      :info="info"
      :connected-ids="connectedIds"
      :untitled="untitledConnection"
      :url-import-note="urlImportNote"
      :collapsed-groups="collapsedGroupNames"
      @close="dialogOpen = false"
      @connect="connect"
      @disconnect="disconnect"
      @load-objects="loadTables"
      @save="saveCurrent"
      @remove="removeSaved"
      @select="useSaved"
      @import-url="importUrl"
      @switch-type="switchDbType"
      @toggle-group="toggleGroupSection"
    />
    <!-- 连接面（表单 / 校验回执 / URL 导入）已**搬进弹层**：`shell/ConnectionDialog.vue`。
         主区不再内联铺开 —— 入口是菜单命令「新建连接 / 编辑连接…」与服务器节点右键菜单
         （对齐 macOS `App/Views/ConnectionSettingsSheet.swift` 的呈现形态）。 -->
    <!-- 查询上下文栏：当前这条连接的**同一个显示件**（显示名 / 环境标签 / 色条）——
         与侧边栏连接行共用 ConnectionLabel，两处不可能出现「一处标了、一处没标」（FR-CONN-14 / -16）。 -->
    <p v-if="connectedConnection" class="db__context">
      <ConnectionLabel
        :connection="connectedConnection"
        :untitled="untitledConnection"
        :language="language"
      />
    </p>

    <!-- 连上了：显示"连到了哪儿" -->
    <p v-if="info" class="db__info">
      <strong>{{ info.database }}</strong> · {{ t('db.connected', { database: info.database, user: info.user }) }}
      {{ info.serverEncoding }} · schema {{ info.currentSchema ?? '—' }}） ·
      <span :title="info.version">{{ versionShort }}</span>
    </p>

    <!-- 启动 SQL（FR-CONN-17）：连接后自动执行；逐条发、逐条报 -->
    <details class="db__startup">
      <summary>
        {{ t('db.startup.title') }}
        <span v-if="startup.length" class="db__note">
          {{ t('db.startup.last', { ok: startup.filter((s) => s.ok).length, fail: startup.filter((s) => !s.ok).length }) }}
        </span>
      </summary>
      <textarea
        v-model="startupSql"
        spellcheck="false"
        rows="2"
        :aria-label="t('db.startup.aria')"
        :placeholder="t('db.startup.placeholder')"
      />
      <ul v-if="startup.length" class="db__startup-list">
        <li v-for="(item, i) in startup" :key="i" :class="{ 'db__startup-bad': !item.ok }">
          <span class="db__startup-mark">{{ item.ok ? '✅' : '❌' }}</span>
          <code>{{ item.sql }}</code>
          <div v-if="item.failure" class="db__startup-fail">
            <p class="db__failure-msg">{{ item.failure.message }}</p>
            <p class="db__failure-hint">{{ item.failure.hint }}</p>
          </div>
        </li>
      </ul>
    </details>

    <!-- 失败：原话 + 提示，两段都显示 -->
    <div v-if="failure" class="db__failure" role="alert">
      <p class="db__failure-msg">{{ failure.message }}</p>
      <p class="db__failure-hint">{{ failure.hint }}</p>
    </div>

    <div class="db__body">
      <!-- 数据库页的左栏（**一列，不是两列**）：
           连接列表收成顶部可折叠的一段，对象树占满整列 ——
           之前把"连接列表"与"对象树"并排成两栏，导航被挤成两条窄缝，已改。 -->
      <aside class="db__tree db__tree--navigator" @click="closeMenus">
        <!-- 连接列表也搬进了弹层（与连接表单同一个件）：
             左栏只剩对象树与它的视图切换（FR-CONN-15 的分组折叠仍由弹层读同一份 localStorage）。 -->

        <!-- 对象树（1.1）：展开一层取一层；右键给「浏览数据 / 生成查询 / 复制名」 -->
        <p class="db__tree-title">
          {{ t('db.objects.summary', { loaded: loadedObjects.length, schemas: schemas.length }) }}
        </p>
        <p v-if="!info" class="db__tree-empty">{{ t('db.tree.notConnected') }}</p>
        <template v-else>
          <!-- 元数据查询到顶（FR-META-07）：**如实说"可能不完整"**，不假装这就是全部 -->
          <p v-if="metadataTruncated > 0" class="db__tree-empty" role="status">
            {{ t('db.meta.truncated', { limit: metadataTruncated }) }}
          </p>
          <!-- 两档视图（FR-META-15）：层级视图 / 按类型分组 —— 切换只重新聚合已加载的层，不重查 -->
          <div class="db__tree-modes" role="tablist" :aria-label="t('db.view.aria')">
            <button
              class="db__tree-mode"
              :class="{ 'db__tree-mode--on': objectView === 'hierarchy' }"
              type="button"
              role="tab"
              :aria-selected="objectView === 'hierarchy' ? 'true' : 'false'"
              @click="objectView = 'hierarchy'"
            >
              {{ t('db.view.hierarchy') }}
            </button>
            <button
              class="db__tree-mode"
              :class="{ 'db__tree-mode--on': objectView === 'byKind' }"
              type="button"
              role="tab"
              :aria-selected="objectView === 'byKind' ? 'true' : 'false'"
              @click="objectView = 'byKind'"
            >
              {{ t('db.view.byKind') }}
            </button>
          </div>
          <p class="db__tree-empty">{{ t('db.tree.nodeCount', { nodes: layerNodeCount }) }}</p>
          <input
            v-model="objectQuery"
            class="db__tree-search"
            type="search"
            :placeholder="t('db.search.placeholder')"
            :aria-label="t('db.search.placeholder')"
            @input="runObjectSearch"
          />
          <p v-if="objectQuery.trim()" class="db__tree-empty">
            {{ t('db.search.hits', { hit: objectHits.length, loaded: loadedObjects.length }) }}
          </p>
          <ul v-if="objectQuery.trim()" class="db__hits">
            <li v-for="hit in objectHits" :key="`${hit.object.schema}.${hit.object.name}`">
              <button
                class="db__table"
                type="button"
                :title="t('db.search.hitTip', {
                  schema: hit.object.schema,
                  name: hit.object.name,
                  basis: hit.matchedOn === 'qualified'
                    ? t('db.search.basis.qualified')
                    : hit.matchedOn === 'name'
                      ? t('db.search.basis.name')
                      : t('db.search.basis.schema'),
                })"
                @click="useTable({ schema: hit.object.schema, name: hit.object.name, kind: hit.object.kind })"
                @contextmenu.prevent="openContextMenu($event, hit.object)"
              >
                <span class="db__icon" :title="t('db.icon.tip', { kind: hit.object.kind })">
                  <NodeIcon :kind="hit.object.kind" />
                </span>
                {{ hit.object.name }}<span class="db__kind">{{ hit.object.schema }} · {{ hit.object.kind }}</span>
              </button>
            </li>
          </ul>
          <template v-else>
            <p v-if="schemas.length === 0" class="db__tree-empty">{{ t('db.tree.noSchema') }}</p>
            <template v-for="row in treeRows" :key="row.id">
              <!-- 服务器节点（FR-META-11 第一期）：右键给「连接 / 断开 / 编辑连接…」 -->
              <button
                v-if="row.kind === 'server'"
                class="db__schema-toggle db__server"
                type="button"
                :title="t('db.server.menu.aria')"
                @contextmenu.prevent="openServerMenu($event)"
              >
                <span class="db__icon"><NodeIcon kind="server" /></span>
                {{ t('db.server') }}
                <span v-if="info" class="db__kind">
                  {{ t('db.server.menu.connected', { database: info.database, user: info.user }) }}
                </span>
              </button>
              <button
                v-else-if="row.kind === 'schema'"
                class="db__schema-toggle"
                type="button"
                :aria-expanded="row.expanded ? 'true' : 'false'"
                @click="toggleSchema(row.label)"
              >
                <span class="db__chevron">{{ row.expanded ? '▾' : '▸' }}</span>
                <span class="db__icon" :title="t('db.icon.tip', { kind: 'schema' })">
                  <NodeIcon kind="schema" />
                </span>
                {{ row.label }}
                <span v-if="row.loading" class="db__kind">{{ t('db.tree.loading') }}</span>
                <span v-else class="db__kind">{{ row.count }}</span>
              </button>
              <p v-else-if="row.kind === 'type'" class="db__tree-group">
                <span class="db__icon" :title="t('db.icon.tip', { kind: row.label })">
                  <NodeIcon :kind="row.label" />
                </span>
                {{ kindLabel(row.label) }}<span class="db__kind">{{ row.count }}</span>
              </p>
              <button
                v-else-if="row.kind === 'object'"
                class="db__table"
                type="button"
                :title="t('db.tree.objectTip', { kind: row.object.kind })"
                @click="useTable({ schema: row.object.schema, name: row.object.name, kind: row.object.kind })"
                @contextmenu.prevent="openContextMenu($event, row.object)"
              >
                <span
                  v-if="canExpandColumns(row.object)"
                  class="db__chevron db__chevron--inline"
                  :title="t('db.columns.toggle')"
                  @click.stop="toggleTable(row.object)"
                >{{ expandedTables[tableKey(row.object.schema, row.object.name)] ? '▾' : '▸' }}</span>
                <span class="db__icon" :title="t('db.icon.tip', { kind: row.object.kind })">
                  <NodeIcon :kind="row.object.kind" />
                </span>
                {{ row.object.name }}<span class="db__kind">{{ row.object.kind === 'table' ? '' : row.object.kind }}</span>
                <span
                  v-if="loadingTable === tableKey(row.object.schema, row.object.name)"
                  class="db__kind"
                >{{ t('db.tree.loading') }}</span>
              </button>
              <p v-else-if="row.kind === 'column'" class="db__column">
                <span class="db__icon" :title="t('db.icon.tip', { kind: 'column' })">
                  <NodeIcon kind="column" />
                </span>
                {{ columnLabel(row.column) }}
              </p>
              <p v-else class="db__tree-empty">{{ t('db.columns.empty') }}</p>
            </template>
          </template>
        </template>
      </aside>

      <!-- 服务器节点右键菜单（FR-META-11 第一期）：三动作**永远都在**，不可用时置灰并说明原因 -->
      <ul
        v-if="serverMenu"
        class="db__menu"
        :style="{ left: `${serverMenu.x}px`, top: `${serverMenu.y}px` }"
        :aria-label="t('db.server.menu.aria')"
        @click.stop
      >
        <li class="db__menu-head">{{ t('db.server') }}</li>
        <li v-for="action in serverActions" :key="action.id">
          <button
            class="db__menu-item"
            type="button"
            :disabled="!action.enabled"
            :title="serverActionTip(action)"
            @click="runServerAction(action)"
          >
            {{ serverActionLabel(action) }}
          </button>
        </li>
      </ul>

      <!-- 对象右键菜单：**没目标就不给入口** —— 序列之类取不了数的对象不出现「浏览数据」 -->
      <ul
        v-if="contextMenu"
        class="db__menu"
        :style="{ left: `${contextMenu.x}px`, top: `${contextMenu.y}px` }"
        @click.stop
      >
        <li class="db__menu-head">{{ contextMenu.object.schema }}.{{ contextMenu.object.name }}</li>
        <li>
          <button
            v-if="contextMenu.object.kind === 'table' || contextMenu.object.kind === 'view' || contextMenu.object.kind === 'materialized_view' || contextMenu.object.kind === 'foreign_table'"
            class="db__menu-item"
            type="button"
            @click="menuBrowse"
          >
            {{ t('db.menu.browse') }}
          </button>
        </li>
        <li><button class="db__menu-item" type="button" @click="menuGenerateQuery">{{ t('db.menu.generateQuery') }}</button></li>
        <li><button class="db__menu-item" type="button" @click="menuDesignTable">{{ t('db.menu.design') }}</button></li>
        <li><button class="db__menu-item" type="button" @click="menuCopyName">{{ t('db.menu.copyName') }}</button></li>
      </ul>

        <!-- 表设计器（1.5）：改列 → 生成变更集 → **只执行非破坏性那些** -->
        <div v-if="designer && shape" class="db__designer">
          <p class="db__browse-title">
            表结构：<code>{{ designer.schema }}.{{ designer.table }}</code>
            <button class="db__btn" type="button" @click="designer = null; ddlPlan = []">{{ t('designer.collapse') }}</button>
          </p>

          <table class="db__grid db__designer-grid">
            <thead>
              <tr>
                <th class="db__grid-head">列名</th>
                <th class="db__grid-head">类型（原文）</th>
                <th class="db__grid-head">可空</th>
                <th class="db__grid-head">默认值</th>
                <th class="db__grid-head">操作</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(c, i) in draftColumns" :key="i">
                <td><input v-model="c.name" class="db__cell-input" spellcheck="false" @change="ddlPlan = []" /></td>
                <td><input v-model="c.dataType" class="db__cell-input" spellcheck="false" @change="ddlPlan = []" /></td>
                <td><input v-model="c.isNullable" type="checkbox" @change="ddlPlan = []" /></td>
                <td>
                  <input
                    :value="c.defaultExpr ?? ''"
                    class="db__cell-input"
                    spellcheck="false"
                    placeholder="（无）"
                    @change="c.defaultExpr = ($event.target as HTMLInputElement).value || null; ddlPlan = []"
                  />
                </td>
                <td><button class="db__btn" type="button" @click="removeDraftColumn(i)">{{ t('designer.dropColumn') }}</button></td>
              </tr>
            </tbody>
          </table>

          <div class="db__writeback">
            <button class="db__btn db__btn--icon" type="button" @click="addDraftColumn" :title="t('designer.addColumn')"><ActionIcon name="plus" /></button>
            <button class="db__btn db__btn--icon db__btn--primary" type="button" @click="previewDdl" :title="t('designer.generate')"><ActionIcon name="wand" /></button>
            <button
                class="db__btn db__btn--icon"
                type="button"
                :disabled="runnableDdl.length === 0"
                :title="`执行非破坏性（${runnableDdl.length} 句）`"
                @click="applyDdl"
              >
                <ActionIcon name="play" />
              </button>
            <button class="db__btn db__btn--icon" type="button" :disabled="ddlPlan.length === 0" title="复制全部语句" @click="copyDdl"><ActionIcon name="copy" /></button>
            <span v-if="blockedDdl.length" class="db__note">
              其中 {{ blockedDdl.length }} 句是**破坏性**的：只生成、不自动执行，请复制出去自己确认后跑
            </span>
          </div>

          <div v-if="ddlPlan.length" class="db__dml">
            <p class="db__dml-title">变更集（{{ ddlPlan.length }} 句）</p>
            <ul class="db__dml-list">
              <li v-for="(s, i) in ddlPlan" :key="i">
                <span class="db__kind">{{ s.purpose }} · {{ s.class }}</span>
                <pre class="db__sql-preview">{{ s.sql }}</pre>
              </li>
            </ul>
          </div>

          <details class="db__startup">
            <summary>索引与约束（{{ shape.indexes.length }} 个索引 / {{ shape.constraints.length }} 个约束）</summary>
            <ul class="db__startup-list">
              <li v-for="ix in shape.indexes" :key="ix.name">
                <code>{{ ix.name }}</code>
                <span class="db__kind">{{ ix.isPrimary ? '主键' : ix.isUnique ? '唯一' : '普通' }} · {{ ix.columns.join(', ') }}</span>
              </li>
              <li v-for="c in shape.constraints" :key="c.name">
                <code>{{ c.name }}</code>
                <span class="db__kind">{{ c.kind }} · {{ c.definition }}</span>
              </li>
            </ul>
          </details>
        </div>

        <!-- 服务端条件浏览面板（FR-DATA-02）：先看 SQL，再执行 -->
        <div v-if="browse" class="db__browse-panel">
          <p class="db__browse-title">
            按条件浏览：<code>{{ browse.schema }}.{{ browse.table }}</code>
            <button class="db__btn" type="button" @click="browse = null">{{ t('designer.collapse') }}</button>
          </p>
          <div class="db__browse-fields">
            <label class="db__field">
              <span>WHERE（单条表达式；写分号会被拒）</span>
              <input v-model="browseWhere" type="text" spellcheck="false" placeholder="例如 balance &gt; 100" />
            </label>
            <label class="db__field">
              <span>ORDER BY（只写列与方向）</span>
              <input v-model="browseOrder" type="text" spellcheck="false" placeholder="例如 id DESC" />
            </label>
            <button class="db__btn db__btn--icon" type="button" @click="previewBrowse" title="生成 SQL"><ActionIcon name="wand" /></button>
            <button class="db__btn db__btn--icon db__btn--primary" type="button" @click="runBrowse" :title="t('sql.run')"><ActionIcon name="play" /></button>
          </div>
          <p v-if="browseError" class="db__failure-msg">{{ browseError }}</p>
          <pre v-if="sqlText" class="db__sql-preview">{{ sqlText }}</pre>
        </div>

      <!-- SQL 与结果 -->
      <div class="db__main" ref="mainPane">
        <!-- 查询页签（图里的「查询 1 ×」+ 加号）；每个页签各自一份 SQL -->
        <div class="db__qtabs" role="tablist" aria-label="查询页签">
          <div
            v-for="tab in queryTabs"
            :key="tab.id"
            class="db__qtab"
            :class="{ 'db__qtab--active': tab.id === activeQueryTab }"
          >
            <button
              class="db__qtab-name"
              type="button"
              role="tab"
              :aria-selected="tab.id === activeQueryTab"
              :title="`切换到 ${tab.title}`"
              @click="selectQueryTab(tab.id)"
            >
              {{ tab.title }}
            </button>
            <button
              class="db__qtab-close"
              type="button"
              data-testid="qtab-close"
              :disabled="queryTabs.length <= 1 || tab.running"
              :title="
                tab.running
                  ? t('sql.tabRunningTip', { title: tab.title })
                  : queryTabs.length <= 1
                    ? '最后一个页签不能关（要收起来请切到别的视图）'
                    : '关闭这个查询页签'
              "
              @click="closeQueryTab(tab.id)"
            >
              ✕
            </button>
          </div>
          <button class="db__qtab-add" type="button" title="新建查询页签" @click="newQueryTab">
                  <ActionIcon name="plus" />
                </button>
          <!-- 被拦下的操作要**说出原因**（`FR-EXEC-07`）：只把按钮置灰而不解释，用户只会以为界面坏了 -->
          <span v-if="tabNote" class="db__qtab-note" role="alert" data-testid="qtab-note">{{ tabNote }}</span>
        </div>
        <!-- 查询参数填值面板（FR-EXEC-17）：**有占位符才出现**；缺值不许执行；
             绑定结果只用于本次执行（编辑器里的 `:name` / `$1` 原样留着）。 -->
        <form v-if="paramOpen" class="db__params" data-testid="param-panel" @submit.prevent="submitParameters">
          <div class="db__params-head">
            <span class="db__params-title">{{ t('sql.params.title', { n: paramRows.length }) }}</span>
            <span class="db__params-tip">{{ t('sql.params.tip') }}</span>
          </div>
          <div v-for="(row, i) in paramRows" :key="row.name" class="db__params-row" :data-testid="`param-row-${i}`">
            <code class="db__params-name" :data-testid="`param-name-${i}`">{{ row.name }}</code>
            <span v-if="row.occurrences > 1" class="db__params-count">{{
              t('sql.params.occurrences', { n: row.occurrences })
            }}</span>
            <select
              v-model="row.kind"
              class="db__params-kind"
              :data-testid="`param-kind-${i}`"
              :aria-label="t('sql.params.kind')"
            >
              <option v-for="kind in PARAM_KINDS" :key="kind" :value="kind">{{ t(kindLabelKey(kind)) }}</option>
            </select>
            <input
              v-model="row.value"
              class="db__params-value"
              :data-testid="`param-value-${i}`"
              spellcheck="false"
              :disabled="row.kind === 'null'"
              :placeholder="row.kind === 'null' ? t('sql.params.nullHint') : t('sql.params.value')"
              @input="row.touched = true"
            />
          </div>
          <p v-if="paramError" class="db__params-error" role="alert" data-testid="param-error">{{ paramError }}</p>
          <div class="db__params-actions">
            <button
              class="db__btn db__btn--primary"
              type="submit"
              :disabled="!paramReady || paramBusy"
              data-testid="param-run"
            >
              {{ t('sql.params.submit') }}
            </button>
            <button class="db__btn" type="button" data-testid="param-cancel" @click="cancelParameters">
              {{ t('sql.params.cancel') }}
            </button>
          </div>
        </form>
        <p v-if="paramNote" class="db__params-note" :class="{ 'db__params-note--bad': paramNoteBad }" role="status" data-testid="param-note">{{
          paramNote
        }}</p>
        <form class="db__sql" @submit.prevent="runBatch(false)">
          <!-- 编辑面：**高亮层在下面（透明文字）+ 真 textarea 在上面**。
               两层共用同一份字体与内边距（否则光标与字会错位，这是这种做法的经典坑）。 -->
          <div class="db__editor">
            <pre class="db__editor-highlight" aria-hidden="true"><span
              v-for="(piece, i) in decoratedPieces"
              :key="i"
              :class="[`db__tok db__tok--${piece.kind}`, piece.severity ? `db__tok--${piece.severity}` : '']"
            >{{ piece.text }}</span></pre>
            <textarea
              ref="sqlArea"
              :value="sql"
              :style="editorStyle"
              spellcheck="false"
              rows="3"
              aria-label="SQL"
              @input="onEditorInput"
              @keyup="onEditorKeyup"
              @click="refreshCompletions(); syncCaret()"
              @select="syncCaret()"
              @keydown="onEditorKeydown"
              @keydown.esc="completions = []"
            />
          </div>
          <!-- 状态栏（B1 第二批）：光标 行:列 / 缩进口径 / 括号配对。三格都由纯函数算，这里只显示。 -->
          <div class="db__editor-status">
            <span class="db__status-caret" data-testid="editor-caret">{{ caretLabel }}</span>
            <span class="db__status-dot" aria-hidden="true">·</span>
            <span class="db__status-indent" data-testid="editor-indent">{{ indentLabel }}</span>
            <span class="db__status-dot" aria-hidden="true">·</span>
            <span
              class="db__status-bracket"
              :class="`db__status-bracket--${bracketState.kind}`"
              data-testid="editor-bracket"
            >{{ bracketState.text }}</span>
            <button class="db__status-goto" type="button" :title="t('sql.gotoTip')" @click="openGoto">
              {{ t('sql.gotoOpen') }}
            </button>
          </div>
          <!-- 问题条（FR-EDIT-56）：静态检查的结果**画出来** —— 编辑器里那几处加虚下划线，
               这里列成可点的行（点一条就把光标搬到那一处）。检查器在领域层，这里只显示。 -->
          <div v-if="problemRows.length" class="db__problems" data-testid="editor-problems">
            <span class="db__problems-count" data-testid="editor-problem-count">{{
              t('sql.problems', { n: problemRows.length })
            }}</span>
            <ul class="db__problems-list">
              <li v-for="(row, i) in problemRows" :key="`${row.start}:${i}`">
                <button
                  class="db__problem"
                  :class="`db__problem--${row.severity}`"
                  type="button"
                  :title="row.message"
                  @click="jumpToProblem(row.start)"
                >
                  <span class="db__problem-at">{{ t('sql.caret', { line: row.line, column: row.column }) }}</span>
                  <span class="db__problem-msg">{{ row.message }}</span>
                </button>
              </li>
            </ul>
          </div>
          <!-- 跳行列（FR-EDIT-19）：Ctrl+G 或点状态栏那颗按钮开；非法输入不关面板、如实给原因。 -->
          <form v-if="gotoOpen" class="db__goto" @submit.prevent="applyGoto">
            <label class="db__goto-label">
              <span>{{ t('sql.gotoLabel') }}</span>
              <input
                ref="gotoBox"
                v-model="gotoInput"
                class="db__goto-input"
                data-testid="goto-input"
                spellcheck="false"
                @keydown.esc.stop.prevent="closeGoto"
              />
            </label>
            <button class="db__btn" type="submit">{{ t('sql.gotoGo') }}</button>
            <span v-if="gotoError" class="db__goto-error" data-testid="goto-error">{{ gotoError }}</span>
          </form>
          <!-- 查找 / 替换（FR-EDIT-18）：Ctrl+F / Ctrl+H 或编辑菜单开。读数与"没有匹配"都写在脸上 ——
               安静不是结论（这是本仓反复踩过的那条：没有可观测面时用户只能猜）。 -->
          <div v-if="findOpen" class="db__find" data-testid="find-bar" role="search">
            <label class="db__find-field">
              <span>{{ t('sql.find.label') }}</span>
              <input
                ref="findBox"
                v-model="findTerm"
                class="db__find-input"
                data-testid="find-term"
                spellcheck="false"
                :placeholder="t('sql.find.placeholder')"
                @keydown.enter.prevent="stepFind($event.shiftKey ? -1 : 1)"
                @keydown.esc.stop.prevent="closeFind"
              />
            </label>
            <label class="db__find-field">
              <span>{{ t('sql.find.replaceLabel') }}</span>
              <input
                ref="replaceBox"
                v-model="findReplacement"
                class="db__find-input"
                data-testid="find-replacement"
                spellcheck="false"
                :placeholder="t('sql.find.replacePlaceholder')"
                @keydown.enter.prevent="replaceCurrent"
                @keydown.esc.stop.prevent="closeFind"
              />
            </label>
            <label class="db__find-case" :title="t('sql.find.caseTip')">
              <input v-model="findCaseSensitive" type="checkbox" data-testid="find-case" />
              <span>{{ t('sql.find.case') }}</span>
            </label>
            <span
              class="db__find-readout"
              :class="{ 'db__find-readout--empty': !findReadout.total }"
              data-testid="find-readout"
            >{{
              findReadout.total
                ? t('sql.find.readout', { position: findReadout.position, total: findReadout.total })
                : findTerm
                  ? t('sql.find.none')
                  : t('sql.find.emptyQuery')
            }}</span>
            <button class="db__btn" type="button" data-testid="find-prev" :disabled="!findReadout.total" @click="stepFind(-1)">
              {{ t('sql.find.prev') }}
            </button>
            <button class="db__btn" type="button" data-testid="find-next" :disabled="!findReadout.total" @click="stepFind(1)">
              {{ t('sql.find.next') }}
            </button>
            <button class="db__btn" type="button" data-testid="find-replace" :disabled="!findReadout.total" @click="replaceCurrent">
              {{ t('sql.find.one') }}
            </button>
            <button class="db__btn" type="button" data-testid="find-replace-all" :disabled="!findReadout.total" @click="replaceAllFound">
              {{ t('sql.find.all') }}
            </button>
            <button class="db__btn" type="button" data-testid="find-close" @click="closeFind">
              {{ t('sql.find.close') }}
            </button>
            <span v-if="findNote" class="db__find-note" data-testid="find-note" role="status">{{ findNote }}</span>
          </div>
          <!-- 格式化 SQL 的回执（FR-EDIT-22）：说清用了哪个引擎 / 没改动 / 为什么拒绝。
               拒绝那一类用告警色 —— 不许和「已格式化」长一个样（安静不是结论）。 -->
          <p
            v-if="formatNote"
            class="db__format-note"
            :class="{ 'db__format-note--bad': formatNoteBad }"
            data-testid="format-note"
            role="status"
          >
            <span>{{ formatNote }}</span>
            <button class="db__btn" type="button" data-testid="format-note-dismiss" @click="formatNote = ''">
              {{ t('sql.format.dismiss') }}
            </button>
          </p>
          <!-- 撤销面的回执（FR-EDIT-60）：没得撤 / 栈被重建这两类**必须说出来** ——
               「按了没反应」和「本来就没得撤」分不开，就会变成用户反复按 Ctrl+Z 猜。 -->
          <p v-if="undoNote" class="db__format-note" data-testid="undo-note" role="status">
            <span>{{ undoNote }}</span>
            <button class="db__btn" type="button" data-testid="undo-note-dismiss" @click="undoNote = ''">
              {{ t('sql.format.dismiss') }}
            </button>
          </p>
          <p class="db__editor-keys">{{ t('sql.keys') }}</p>
          <ul v-if="completions.length" class="db__completions">
            <li v-for="(c, i) in visibleCompletions" :key="`${c.kind}:${c.text}`">
              <button
                class="db__completion"
                :class="{ 'db__completion--active': i === activeCompletionIndex }"
                type="button"
                @click="acceptCompletion(c)"
              >
                <span class="db__completion-text">{{ c.text }}</span>
                <span class="db__kind">{{ c.detail }}</span>
              </button>
            </li>
            <!-- 键盘提示（B1 收尾）：清单开着时把「↑↓ / 回车」写在脸上 -->
            <li class="db__completion-hint" data-testid="completion-keys">{{ t('sql.completionKeys') }}</li>
          </ul>
          <div class="db__sql-actions">
            <!-- 工具条第一格（图里那条）：当前库 —— 选项来自**已保存连接**里同主机同用户的那些库 -->
            <label v-if="info" class="db__bar-field db__bar-field--inline">
              <span>{{ t('db.database') }}</span>
              <select
                :value="info.database"
                :disabled="!!busy"
                :title="t('db.switchDatabase')"
                @change="switchDatabase(($event.target as HTMLSelectElement).value)"
              >
                <option v-for="name in databaseOptions" :key="name" :value="name">{{ name }}</option>
              </select>
            </label>
            <span v-if="info" class="db__bar-sep" />
            <!-- 编辑菜单（FR-EDIT-17）：一个入口管五件事，五件全接上了真动作
                 （查找替换 / 格式化 SQL / 跳行列 / 缩进 / 清除）—— 不放点了没反应的项。 -->
            <div class="db__edit-menu">
              <button
                class="db__btn"
                type="button"
                data-testid="edit-menu-toggle"
                :title="t('sql.editMenu.tip')"
                :aria-expanded="editMenuOpen ? 'true' : 'false'"
                @click.stop="toggleEditMenu"
              >
                {{ t('sql.editMenu') }}
              </button>
              <template v-if="editMenuOpen">
                <div class="db__menu-backdrop" data-testid="edit-menu-backdrop" @click.stop="closeEditMenu" />
                <ul class="db__menu db__menu--dropdown" role="menu" data-testid="edit-menu">
                  <li>
                    <button
                      class="db__menu-item"
                      type="button"
                      role="menuitem"
                      data-testid="edit-menu-undo"
                      :disabled="undoSteps === 0"
                      :title="t('sql.edit.undoTip')"
                      @click="menuUndo"
                    >
                      {{ t('sql.edit.undo') }}
                    </button>
                  </li>
                  <li>
                    <button
                      class="db__menu-item"
                      type="button"
                      role="menuitem"
                      data-testid="edit-menu-redo"
                      :disabled="redoSteps === 0"
                      :title="t('sql.edit.redoTip')"
                      @click="menuRedo"
                    >
                      {{ t('sql.edit.redo') }}
                    </button>
                  </li>
                  <li>
                    <button class="db__menu-item" type="button" role="menuitem" data-testid="edit-menu-find" @click="menuFind">
                      {{ t('sql.edit.find') }}
                    </button>
                  </li>
                  <li>
                    <button
                      class="db__menu-item"
                      type="button"
                      role="menuitem"
                      data-testid="edit-menu-format"
                      :disabled="!sql.trim()"
                      :title="t('sql.edit.format')"
                      @click="menuFormat"
                    >
                      {{ t('sql.edit.format') }}
                    </button>
                  </li>
                  <li>
                    <button class="db__menu-item" type="button" role="menuitem" data-testid="edit-menu-goto" @click="menuGoto">
                      {{ t('sql.edit.goto') }}
                    </button>
                  </li>
                  <li>
                    <button class="db__menu-item" type="button" role="menuitem" data-testid="edit-menu-indent" @click="menuIndent(1)">
                      {{ t('sql.edit.indent') }}
                    </button>
                  </li>
                  <li>
                    <button class="db__menu-item" type="button" role="menuitem" data-testid="edit-menu-outdent" @click="menuIndent(-1)">
                      {{ t('sql.edit.outdent') }}
                    </button>
                  </li>
                  <li>
                    <button
                      class="db__menu-item"
                      type="button"
                      role="menuitem"
                      data-testid="edit-menu-clear"
                      :disabled="!sql.trim()"
                      @click="menuClear"
                    >
                      {{ t('sql.edit.clear') }}
                    </button>
                  </li>
                </ul>
              </template>
            </div>
            <!-- 保存查询（FR-EDIT-14）：**在执行按钮之前**（需求原文点名的位置）。
                 两个入口：存当前页签 / 打开已保存清单（回填到当前或新页签）。 -->
            <button
              class="db__btn"
              type="button"
              :disabled="!sql.trim()"
              :title="t('saveQuery.saveTip')"
              data-testid="save-query-open"
              @click="openSaveQueryPanel()"
            >
              {{ t('saveQuery.save') }}
            </button>
            <button
              class="db__btn"
              type="button"
              :title="t('saveQuery.listTip')"
              :aria-expanded="savedQueryMenuOpen ? 'true' : 'false'"
              data-testid="saved-query-toggle"
              @click="toggleSavedQueryMenu"
            >
              {{ t('saveQuery.list') }} ({{ savedQueries.length }})
            </button>
            <span v-if="savedQueryNote" class="db__note" data-testid="saved-query-note">{{ savedQueryNote }}</span>
            <button class="db__btn db__btn--icon db__btn--primary" type="submit" :disabled="!!busy" :title="t('sql.run')"><ActionIcon name="play" /></button>
            <button class="db__btn db__btn--icon" type="button" :disabled="!busy" @click="cancelRunning" :title="t('sql.cancel')"><ActionIcon name="stop" /></button>
            <button class="db__btn db__btn--icon" type="button" :disabled="!!busy" @click="showPlan" :title="t('sql.planOnly')"><ActionIcon name="code" /></button>
            <button class="db__btn db__btn--icon" type="button" :disabled="!!busy" @click="runBatch(true)" :title="t('sql.runWithPlan')"><ActionIcon name="flask" /></button>
          <button
            class="db__btn"
            type="button"
            :disabled="!sql.trim()"
            :title="t('db.clear.tip')"
            @click="clearSql"
          >
            清空
          </button>
            <!-- 自然语言 → SQL（FR-AI-02）：两段式，先摊外发正文再看结果；
                 生成的 SQL **只写进编辑器**，不执行（运行仍要用户按「执行」）。 -->
            <button
              class="db__btn"
              type="button"
              data-testid="ai-generate"
              :title="t('agent.generate.entryTip')"
              @click="openGenerate"
            >
              {{ t('agent.generate.entry') }}
            </button>
            <span v-if="result && !result.columns.length" class="db__note">
              影响 {{ result.affected ?? '未知' }} 行（无结果集）
            </span>
            <span v-else-if="result" class="db__note">
              {{ result.rows.length }} 行<template v-if="result.truncated">
                （服务端回来 {{ result.returned }} 行，**已截断**，只显示前 {{ result.rows.length }} 行）</template
              >
            </span>
          </div>
        </form>

        <!-- 保存查询面板（FR-EDIT-14）：名字预填、空名当场拒、**同名先问覆盖**（未确认前服务端没写盘） -->
        <div v-if="saveQueryPanelOpen" class="db__save-query" data-testid="save-query-panel">
          <!-- 来源是「AI 生成」时明写这一句：不然用户会以为存的是编辑器里的内容 -->
          <p v-if="saveQueryFromGenerator" class="db__save-query-source" data-testid="save-query-source">
            {{ t('saveQuery.sourceGenerated') }}
          </p>
          <label class="db__save-query-label">
            <span>{{ t('saveQuery.nameLabel') }}</span>
            <input
              v-model="saveQueryName"
              class="db__save-query-input"
              data-testid="save-query-name"
              spellcheck="false"
              :placeholder="t('saveQuery.namePlaceholder')"
              @keydown.enter.prevent="submitSaveQuery(!!pendingOverwrite)"
              @keydown.esc.prevent="closeSaveQueryPanel"
            />
          </label>
          <button
            class="db__btn db__btn--primary"
            type="button"
            :disabled="savedQueryBusy"
            data-testid="save-query-submit"
            @click="submitSaveQuery(!!pendingOverwrite)"
          >
            {{ pendingOverwrite ? t('saveQuery.overwrite') : t('saveQuery.submit') }}
          </button>
          <button class="db__btn" type="button" data-testid="save-query-cancel" @click="closeSaveQueryPanel">
            {{ t('saveQuery.cancel') }}
          </button>
          <p v-if="pendingOverwrite" class="db__save-query-warn" data-testid="save-query-conflict" role="alert">
            {{
              t('saveQuery.conflict', {
                name: pendingOverwrite.name,
                time: savedQueryTimeLabel(pendingOverwrite.savedAt) || '—',
              })
            }}
          </p>
          <p v-if="saveQueryError" class="db__save-query-error" data-testid="save-query-error" role="alert">
            {{ saveQueryError }}
          </p>
        </div>

        <!-- 已保存清单（FR-EDIT-14）：每条两路回填 + 删除；空表如实说「还没有」 -->
        <div v-if="savedQueryMenuOpen" class="db__saved-queries" data-testid="saved-query-list">
          <p v-if="!savedQueries.length" class="db__saved-empty" data-testid="saved-query-empty">
            {{ t('saveQuery.empty') }}
          </p>
          <ul v-else class="db__saved-list">
            <li v-for="q in savedQueries" :key="q.id" class="db__saved-item">
              <div class="db__saved-head">
                <span class="db__saved-name">{{ q.name }}</span>
                <span v-if="savedQuerySourceLabel(q)" class="db__saved-source">{{ savedQuerySourceLabel(q) }}</span>
              </div>
              <p class="db__saved-sql">{{ savedQuerySqlPreview(q) }}</p>
              <div class="db__saved-actions">
                <button class="db__btn" type="button" :title="t('saveQuery.refillTip')" @click="refillSavedQuery(q, false)">
                  {{ t('saveQuery.refill') }}
                </button>
                <button class="db__btn" type="button" :title="t('saveQuery.refillNewTip')" @click="refillSavedQuery(q, true)">
                  {{ t('saveQuery.refillNew') }}
                </button>
                <button
                  class="db__btn db__btn--icon"
                  type="button"
                  :title="t('saveQuery.deleteTip')"
                  @click="deleteSavedQuery(q.id)"
                >
                  <ActionIcon name="trash" />
                </button>
              </div>
            </li>
          </ul>
        </div>

        <!-- 分隔条（FR-EDIT-13）：编辑区与结果区之间那条**能拖**的线。
             口径：两区各 ≥120px；↑↓ 步进、双击复位；焦点可落在条上（键盘用户也能调）。 -->
        <div
          class="db__split"
          :class="{ 'db__split--active': splitDragging }"
          role="separator"
          aria-orientation="horizontal"
          :aria-label="t('db.split.aria')"
          :aria-valuemin="SPLIT_MIN_PANE"
          :aria-valuenow="editorHeight === null ? undefined : editorHeight"
          tabindex="0"
          :title="t('db.split.tip')"
          data-testid="db-split"
          @pointerdown="onSplitDown"
          @keydown="onSplitKey"
          @dblclick="resetSplit"
        >
          <span class="db__split-grip" aria-hidden="true" />
        </div>

        <!-- 逐段结果（1.2）：多段提交时"哪句成、哪句败、各耗时多少"一眼可见 -->
        <div v-if="outcomes.length > 1" class="db__outcomes">
          <p class="db__outcomes-title">
            这次提交了 {{ outcomes.length }} 段（点某一段把它显示到下面的网格里）
          </p>
          <ol class="db__outcomes-list">
            <li v-for="(o, i) in outcomes" :key="i">
              <button
                class="db__outcome"
                :class="{ 'db__outcome--bad': !o.ok, 'db__outcome--active': i === shownOutcome }"
                type="button"
                :title="o.sql"
                @click="selectOutcome(i)"
              >
                <span class="db__outcome-mark">{{ o.ok ? '✅' : '❌' }}</span>
                <span class="db__outcome-summary">{{ outcomeSummary(o) }}</span>
                <span class="db__kind">{{ o.elapsedMs }} ms</span>
                <span class="db__outcome-sql">{{ o.sql }}</span>
              </button>
            </li>
          </ol>
        </div>


        <!-- 结果区：左表格（可排序 / 筛选 / 复制 / 点行看详情）+ 右详情（竖排值检查） -->
        <div class="db__result-row">
          <template v-if="result && result.columns.length">
            <div class="db__grid-wrap">
              <div class="db__grid-tools">
                <input
                  v-model="filter"
                  type="search"
                  placeholder="{{ t('grid.filter.placeholder') }}"
                  aria-label="筛选结果"
                  @input="page = 1"
                />
                <span class="db__note">
                  命中 {{ visible.length }} / 共 {{ result.rows.length }} 行 ·
                  第 {{ paged.page }} / {{ paged.pageCount }} 页（本页 {{ shownRows.length }} 行）
                </span>
                <button class="db__btn db__btn--icon" type="button" :disabled="paged.page <= 1" title="上一页" @click="page = paged.page - 1"><ActionIcon name="chevronLeft" /></button>
                <button
                    class="db__btn db__btn--icon"
                    type="button"
                    :disabled="paged.page >= paged.pageCount"
                    title="下一页"
                    @click="page = paged.page + 1"
                  >
                    <ActionIcon name="chevronRight" />
                  </button>
                <label class="db__freeze">
                  每页
                  <input v-model.number="pageSize" type="number" min="1" @change="page = 1" />
                  行
                </label>
                <label class="db__freeze">
                  冻结前
                  <input v-model.number="frozenCount" type="number" min="0" :max="result.columns.length" />
                  列
                </label>
                <label class="db__freeze">
                  复制为
                  <select v-model="copyFormat" class="db__select">
                    <option v-for="(label, fmt) in EXPORT_FORMAT_LABELS" :key="fmt" :value="fmt">{{ label }}</option>
                  </select>
                </label>
                <button class="db__btn" type="button" @click="copyVisible">{{ t('grid.copy') }}</button>
                <button
                  class="db__btn"
                  type="button"
                  :title="language === 'zh-Hans' ? 'Switch UI language' : '切换界面语言'"
                  @click="language = toggleLanguage(language)"
                >
                  {{ language === 'zh-Hans' ? 'EN' : '中文' }}
                </button>
                <button class="db__btn" type="button" @click="ioOpen = !ioOpen">{{ t('grid.io') }}</button>
                <button
                    class="db__btn db__btn--icon"
                    type="button"
                    :title="t('schema.open')"
                    data-testid="schema-open-panel"
                    @click="schemaDiffOpen = !schemaDiffOpen"
                  >
                    <ActionIcon name="diff" />
                  </button>
                <button
                    class="db__btn db__btn--icon"
                    type="button"
                    title="管理面板"
                    @click="adminOpen = !adminOpen; if (adminOpen) loadAdmin()"
                  >
                    <ActionIcon name="sliders" />
                  </button>
                <!-- 备份（FR-IO-04）：入口就摆在这一排工具里 —— 命令面板的同名命令也走它 -->
                <button
                    class="db__btn"
                    type="button"
                    data-testid="backup-open"
                    :title="t('cmd.database.backup')"
                    @click="backupOpen = true"
                  >
                    {{ t('cmd.database.backup') }}
                  </button>
                <span v-if="copied" class="db__note">{{ copied }}</span>
              </div>

              <!-- Schema 对比与同步（FR-DDL-04）：两侧各自抓快照 → 差异 → 同步脚本（只生成、不执行） -->
              <SchemaDiffPanel
                v-if="schemaDiffOpen"
                :language="language"
                @close="schemaDiffOpen = false"
                @open-sql="openSchemaScript"
              />

              <!-- 管理面（1.7）：读数只读；维护 / 杀会话**只生成语句**，面板里没有执行按钮 -->
              <div v-if="adminOpen" class="db__io">
                <p class="db__browse-title">
                  库（{{ adminDatabases.length }}）· 会话（{{ adminSessions.length }}）
                  <button class="db__btn db__btn--icon" type="button" :title="t('admin.refresh')" @click="loadAdmin"><ActionIcon name="refresh" /></button>
                  <button class="db__btn db__btn--icon" type="button" :title="t('admin.maintenance')" @click="loadMaintenance"><ActionIcon name="sliders" /></button>
                  <button
                    class="db__btn"
                    type="button"
                    :disabled="adminCommands.length === 0"
                    @click="copyAdminCommands"
                  >
                    复制命令（唯一出口）
                  </button>
                </p>
                <p v-if="adminNote" class="db__note">{{ adminNote }}</p>

                <details open>
                  <summary class="db__note">库列表（大小按服务端读数；**不四舍五入到失真**）</summary>
                  <ul class="db__dml-list">
                    <li v-for="d in adminDatabases" :key="d.name">
                      <code>{{ d.name }}</code>
                      <span class="db__kind">
                        {{ d.sizeBytes }} 字节 · {{ d.connections }} 连接 · 属主 {{ d.owner }} ·
                        {{ d.allowConnections ? '允许连接' : '**不允许连接**' }}
                      </span>
                    </li>
                  </ul>
                </details>

                <details>
                  <summary class="db__note">会话与锁（**等锁的排最前** —— 按危害排，不按数字大小排）</summary>
                  <ul class="db__dml-list">
                    <li v-for="s in adminSessions" :key="s.pid">
                      <code>pid {{ s.pid }}</code>
                      <span class="db__kind">
                        {{ s.user }}@{{ s.database }} · {{ s.state }} · {{ s.durationMs }} ms
                        <template v-if="s.waiting">· **在等锁**</template>
                      </span>
                      <button class="db__btn" type="button" @click="generateKill(s.pid, false)">{{ t('admin.genCancel') }}</button>
                      <button class="db__btn" type="button" @click="generateKill(s.pid, true)">{{ t('admin.genTerminate') }}</button>
                    </li>
                  </ul>
                </details>

                <details v-if="adminStats.length">
                  <summary class="db__note">表统计（行数是**估算**，不是精确 count）</summary>
                  <ul class="db__dml-list">
                    <li v-for="t in adminStats" :key="t.table">
                      <code>{{ t.table }}</code>
                      <span class="db__kind">
                        ≈{{ t.estimatedRows }} 行 · 共 {{ t.totalBytes }} 字节（索引 {{ t.indexSizePretty }}）·
                        vacuum {{ t.lastVacuum }} · analyze {{ t.lastAnalyze }}
                      </span>
                    </li>
                  </ul>
                </details>

                <!-- 慢查询排行（FR-DIAG-03）：扩展不可用给原因 + 三步，**不用空列表冒充「没有慢查询」** -->
                <details open data-testid="slow-queries">
                  <summary class="db__note">慢查询排行（pg_stat_statements；时间列按服务端版本取）</summary>
                  <div class="db__writeback">
                    <label class="db__freeze">
                      排序
                      <select v-model="slowSort" class="db__select" data-testid="slow-sort" @change="loadSlowQueries">
                        <option v-for="s in SLOW_SORT_LABELS" :key="s.key" :value="s.key">{{ s.label }}</option>
                      </select>
                    </label>
                    <button class="db__btn" type="button" data-testid="slow-refresh" @click="loadSlowQueries">
                      刷新排行
                    </button>
                    <span v-if="slowReport && slowReport.available" class="db__note" data-testid="slow-columns">
                      时间列 {{ slowReport.totalColumn }} / {{ slowReport.meanColumn }}
                    </span>
                  </div>

                  <p v-if="slowNote" class="db__note" data-testid="slow-note">{{ slowNote }}</p>

                  <template v-if="slowReport && !slowReport.available">
                    <p class="db__note" data-testid="slow-unavailable">{{ slowReport.reason }}</p>
                    <ol class="db__dml-list" data-testid="slow-steps">
                      <li v-for="(step, index) in slowReport.steps" :key="index">{{ step }}</li>
                    </ol>
                  </template>

                  <template v-else-if="slowReport && slowReport.available">
                    <p v-if="slowReport.rowsOut.length === 0" class="db__note" data-testid="slow-empty">
                      排行读回来了 0 条：扩展在，但这台服务端还没有语句被记账（或当前用户只看得见自己的查询）
                    </p>
                    <ol v-else class="db__dml-list" data-testid="slow-rows">
                      <li v-for="(row, index) in slowReport.rowsOut" :key="index">
                        <span class="db__kind">
                          {{ row.calls }} 次 · 共 {{ row.totalMs }} ms · 平均 {{ row.meanMs }} ms ·
                          影响 {{ row.rows }} 行
                          <template v-if="row.truncated">· 文本已截断</template>
                        </span>
                        <pre class="db__sql-preview">{{ row.query }}</pre>
                      </li>
                    </ol>
                  </template>
                </details>

                <div v-if="adminCommands.length" class="db__dml">
                  <p class="db__dml-title">{{ adminCommandNote }}</p>
                  <ul class="db__dml-list">
                    <li v-for="(c, i) in adminCommands" :key="i">
                      <span class="db__kind">{{ c.purpose }} · 代价：{{ c.cost }}</span>
                      <pre class="db__sql-preview">{{ c.sql }}</pre>
                    </li>
                  </ul>
                </div>
              </div>

              <!-- 导入导出（1.6）：导出走原子落盘；导入先预览、再一个事务写入 -->
              <div v-if="ioOpen" class="db__io">
                <p class="db__browse-title">导出当前 SQL 的结果</p>
                <div class="db__writeback">
                  <label class="db__freeze">
                    格式
                    <select v-model="exportFormat" class="db__select">
                      <option value="csv">CSV</option>
                      <option value="json">JSON</option>
                    </select>
                  </label>
                  <input
                    v-model="exportPath"
                    class="db__cell-input db__io-path"
                    spellcheck="false"
                    placeholder="目标文件路径，例如 D:\\tmp\\export.csv"
                    aria-label="导出目标路径"
                  />
                  <button class="db__btn db__btn--icon db__btn--primary" type="button" :disabled="!!busy" title="导出到文件" @click="runExport"><ActionIcon name="download" /></button>
                  <span v-if="exportNote" class="db__note">{{ exportNote }}</span>
                </div>

                <p class="db__browse-title">从文件导入（说明：空白字段按 NULL 写入）</p>
                <div class="db__writeback">
                  <input
                    v-model="importPath"
                    class="db__cell-input db__io-path"
                    spellcheck="false"
                    placeholder="CSV 或 .xlsx?? 目前 CSV 直接读；.xlsx 走 Python 桥"
                    aria-label="导入文件路径"
                  />
                  <input
                    v-model="importTable"
                    class="db__cell-input"
                    spellcheck="false"
                    placeholder="目标表名"
                    aria-label="目标表名"
                  />
                  <label class="db__freeze">
                    <input v-model="importHasHeader" type="checkbox" />
                    首行是表头
                  </label>
                  <button class="db__btn" type="button" @click="runPreviewImport">{{ t('io.preview') }}</button>
                  <button
                      class="db__btn db__btn--icon db__btn--primary"
                      type="button"
                      :disabled="!importPreview || !!busy"
                      title="导入（一个事务）"
                      @click="runImportNow"
                    >
                      <ActionIcon name="upload" />
                    </button>
                </div>

                <div v-if="importPreview" class="db__dml">
                  <p class="db__dml-title">
                    预览：分隔符「{{ importPreview.delimiter }}」· 解析 {{ importPreview.parsedRows }} 行 /
                    共 {{ importPreview.totalDataRows }} 行 · 丢弃 {{ importPreview.skipped.length }} 行
                  </p>
                  <p class="db__note">
                    对上的列：{{ importPreview.matched.map((m) => m[0]).join('、') || '（没有一列对上）' }}
                    <template v-if="importPreview.unmatchedCsv.length">
                      · CSV 多出来的列：{{ importPreview.unmatchedCsv.join('、') }}
                    </template>
                    <template v-if="importPreview.missing.length">
                      · 表里没给的列：{{ importPreview.missing.join('、') }}
                    </template>
                  </p>
                  <ul v-if="importPreview.skipped.length" class="db__dml-list">
                    <li v-for="(s, i) in importPreview.skipped.slice(0, 10)" :key="i">
                      第 {{ s.line }} 行：{{ s.reason }}（{{ s.preview }}）
                    </li>
                  </ul>
                  <p v-if="importNote" class="db__note">{{ importNote }}</p>
                </div>
              </div>

              <!-- 写回（1.4）：双击单元格改值 → 生成 SQL → 试跑 / 提交。
                   没主键或只读连接时**说清为什么不能改**，不做"灰着但不说为什么"。 -->
              <div class="db__writeback">
                <span v-if="readOnly" class="db__note">
                  这条连接标了只读：可以预览将执行的语句，但**不会发送**（本机保护，不替代数据库权限）
                </span>
                <span v-else-if="primaryKey.length === 0" class="db__note">
                  这张表没有主键：定位不到「是哪一行」，所以不给单元格编辑（请用 SQL 自己写 WHERE）
                </span>
                <span v-else class="db__note">
                  双击单元格改值（主键：{{ primaryKey.join(' + ') }}）· 已改 {{ editCount }} 处
                </span>
                <button
                    class="db__btn db__btn--icon"
                    type="button"
                    :disabled="editCount === 0"
                    title="生成 SQL（先看清）"
                    @click="previewDml"
                  >
                    <ActionIcon name="wand" />
                  </button>
                <button
                    class="db__btn db__btn--icon"
                    type="button"
                    :disabled="!readOnly && pendingDml.length === 0"
                    title="试跑（跑完回滚）"
                    @click="submitWriteback(true)"
                  >
                    <ActionIcon name="flask" />
                  </button>
                <button
                    class="db__btn db__btn--icon db__btn--primary"
                    type="button"
                    :disabled="readOnly || pendingDml.length === 0"
                    title="提交（一次事务）"
                    @click="submitWriteback(false)"
                  >
                    <ActionIcon name="check" />
                  </button>
                <button v-if="editCount > 0" class="db__btn db__btn--icon" type="button" title="放弃改动" @click="cellEdits = {}; pendingDml = []"><ActionIcon name="undo" /></button>
              </div>

              <!-- 将执行的语句（**提交前必须先有它**） -->
              <div v-if="pendingDml.length" class="db__dml">
                <p class="db__dml-title">将执行 {{ pendingDml.length }} 条（一次事务）</p>
                <ul class="db__dml-list">
                  <li v-for="(d, i) in pendingDml" :key="i">
                    <code>{{ d.sql }}</code>
                    <span class="db__kind">{{ d.target }}</span>
                    <span v-if="d.risk === 'forbidden'" class="db__outcome-summary">（只读：不会发送）</span>
                  </li>
                </ul>
              </div>
              <table class="db__grid">
                <thead>
                  <tr>
                    <th
                      v-for="(c, j) in result.columns"
                      :key="c"
                      class="db__grid-head"
                      :style="cellStyle(j)"
                      :title="`点一下按 ${c} 排序（再点翻方向）`"
                      @click="toggleSort(j)"
                    >
                      {{ c }}
                      <span v-if="sortColumn === j" class="db__sort-mark">{{ sortDesc ? '▼' : '▲' }}</span>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="i in shownRows"
                    :key="i"
                    class="db__row"
                    title="点这一行看详情（值检查：NULL 与空串分开、长 JSON 格式化）"
                    @click="openDetail(i)"
                  >
                    <td
                      v-for="(cell, j) in result.rows[i]"
                      :key="j"
                      :style="cellStyle(j)"
                      :class="{
                        'db__null': cell === null,
                        'db__frozen': !!frozenStyles[j],
                        'db__cell--edited': cellEdits[cellKey(i, j)] !== undefined,
                      }"
                      @dblclick.stop="beginEdit(i, j)"
                    >
                      <!-- 编辑态：就地输入（回车提交、Esc 取消）；非编辑态显示显示值 -->
                      <input
                        v-if="editingCell === cellKey(i, j)"
                        class="db__cell-input"
                        :value="cellText(i, j, cell)"
                        autofocus
                        @keydown.enter="commitEdit(i, j, ($event.target as HTMLInputElement).value)"
                        @keydown.esc="editingCell = ''"
                        @blur="commitEdit(i, j, ($event.target as HTMLInputElement).value)"
                      />
                      <template v-else>
                        {{ cellText(i, j, cell) || (cell === null ? 'NULL' : '') }}
                      </template>
                      <!-- 外键入口：**只在有目标时出现**（没目标不显示，点了没反应比不给更糟） -->
                      <template v-for="(t, k) in cellFkTargets(result.columns[j])" :key="k">
                        <button
                          class="db__fk"
                          type="button"
                          :title="`跳到 ${t.schema ? t.schema + '.' : ''}${t.table} 里 ${t.column} = 这一格值 的行`"
                          @click.stop="jumpTo(t, cell)"
                        >
                          ↪
                        </button>
                      </template>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <!-- 单行详情（FR-DATA-05）：竖排看宽表 —— 形态摘要 + 展示文本（长 JSON 已美化） -->
            <aside v-if="detail" class="db__detail">
              <p class="db__detail-title">
                第 {{ detail.index + 1 }} 行 · {{ detail.fields.length }} 个字段
                <button class="db__btn db__btn--icon" type="button" title="关闭" @click="detail = null"><ActionIcon name="close" /></button>
              </p>
              <dl class="db__detail-list">
                <template v-for="f in detail.fields" :key="f.columnName">
                  <dt>
                    {{ f.columnName }}<span v-if="f.typeName" class="db__kind">{{ f.typeName }}</span>
                  </dt>
                  <dd>
                    <p class="db__detail-meta">
                      {{ f.value.shape.kind }} · {{ f.value.originalCharacterCount }} 字符
                      <template v-if="f.value.lineCount > 1">· {{ f.value.lineCount }} 行</template>
                      <template v-if="f.value.isTruncated">· 已截断（下面不是全部）</template>
                    </p>
                    <pre class="db__detail-value" :class="{ 'db__null': f.value.shape.kind === 'null' }">{{ f.value.shape.kind === 'null' ? 'NULL' : f.value.shape.kind === 'empty' ? '（空串）' : f.value.display }}</pre>
                    <!-- 详情面板里也给外键入口（带目标名，比表格里的箭头更好认） -->
                    <div v-if="cellFkTargets(f.columnName).length" class="db__detail-fk">
                      <button
                        v-for="(t, k) in cellFkTargets(f.columnName)"
                        :key="k"
                        class="db__btn"
                        type="button"
                        :disabled="f.value.shape.kind === 'null'"
                        :title="f.value.shape.kind === 'null' ? 'NULL 没有可跳转的值' : '跳到该行'"
                        @click="jumpTo(t, f.value.shape.kind === 'null' ? null : f.value.display)"
                      >
                        ↪ {{ t.schema ? t.schema + '.' : '' }}{{ t.table }}（{{ t.column }}）
                      </button>
                    </div>
                  </dd>
                </template>
              </dl>
            </aside>
          </template>
          <p v-else-if="info && !failure" class="db__hint">
            从左侧点一张表生成查询，或直接写 SQL 后按「执行」。
          </p>
        </div>
      </div>
    </div>
  </section>

  <!-- 自然语言 → SQL（FR-AI-02）：弹层自己管两段式流程；视图只给它「已加载的表」并把
       用户确认后的 SQL 写进编辑器缓冲（**不执行** —— 这一点在弹层文案里也写明）。 -->
  <AgentGenerateDialog
    :open="generateOpen"
    :tables="generateTables"
    :language="language"
    @close="generateOpen = false"
    @insert="applyGeneratedSql"
    @save-as="saveGeneratedSql"
  />

  <!-- 备份（FR-IO-04）：外观与「导出结果」不是一件事 —— 这里备份的是**整个库** -->
  <BackupDialog
    :open="backupOpen"
    :language="language"
    :connection-id="connectedConnection?.id ?? null"
    database=""
    @close="backupOpen = false"
  />
</template>

<style scoped>
.db {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
}

.db__field {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
  font-size: var(--ds-font-caption-size);
  color: var(--ds-color-text-secondary);
}

.db__field--narrow {
  width: 84px;
}

.db__field--check {
  flex-direction: row;
  align-items: center;
  gap: var(--ds-spacing-xs);
  padding-bottom: var(--ds-spacing-xs);
}

.db__tree--connections {
  width: 240px;
}

.db__startup {
  padding: 0 var(--ds-spacing-m) var(--ds-spacing-s);
}

.db__startup summary {
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
  cursor: pointer;
}

.db__startup textarea {
  width: 100%;
  margin-top: var(--ds-spacing-xs);
  padding: var(--ds-spacing-xs);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  resize: vertical;
}

.db__startup-list {
  margin: var(--ds-spacing-xs) 0 0;
  padding-left: var(--ds-spacing-m);
  font-size: var(--ds-font-caption-size);
}

.db__startup-list code {
  font-family: var(--ds-font-stack);
}

.db__startup-bad {
  color: var(--ds-color-status-danger);
}

.db__startup-mark {
  margin-right: var(--ds-spacing-xs);
}

.db__startup-fail {
  margin: var(--ds-spacing-xs) 0;
}

.db__field input {
  height: var(--ds-metric-control-height);
  padding: 0 var(--ds-spacing-s);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
}

.db__btn {
  height: var(--ds-metric-control-height);
  padding: 0 var(--ds-spacing-m);
  background: var(--ds-color-surface-raised);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  cursor: pointer;
}

/* 纯图标按钮（T-20261013-053）：方形命中区，图形居中；文字不进 DOM。 */
.db__btn--icon {
  width: var(--ds-metric-control-height);
  padding: 0;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.db__btn--primary {
  background: var(--ds-color-accent-accent);
  color: var(--ds-color-surface-content);
  border-color: transparent;
}

.db__btn:disabled {
  color: var(--ds-color-text-disabled);
  cursor: default;
}

.db__busy,
.db__note,
.db__hint {
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.db__info {
  margin: 0;
  padding: var(--ds-spacing-xs) var(--ds-spacing-m);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.db__failure {
  margin: var(--ds-spacing-s) var(--ds-spacing-m) 0;
  padding: var(--ds-spacing-s);
  border: var(--ds-metric-hairline) solid var(--ds-color-status-danger);
  border-radius: var(--ds-radius-control);
}

.db__failure-msg {
  margin: 0;
  color: var(--ds-color-status-danger);
  font-family: var(--ds-font-stack);
}

.db__failure-hint {
  margin: var(--ds-spacing-xs) 0 0;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.db__body {
  display: flex;
  flex: 1;
  min-height: 0;
}

/* 数据库页的左栏 = **一列**（连接列表折叠在顶部 + 对象树占满）。
   之前这里是两个并排的 `aside`，把导航挤成两条窄缝 —— 已改成一列。 */
.db__tree {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-s);
  /* 一列的宽度：导航要能看清 schema 与对象名，不能是窄缝 */
  width: var(--ds-metric-sidebar-width);
  flex: 0 0 auto;
  overflow: auto;
  padding: var(--ds-spacing-s);
  border-right: var(--ds-metric-hairline) solid var(--ds-hairline);
  background: var(--ds-color-surface-sidebar);
}

/* 连接列表的可折叠段：默认收起，要用时展开 —— 不占常驻宽度 */
/* 对象树占满剩下的一列 */
.db__tree--navigator {
  overflow: hidden;
}

.db__tree--navigator > :last-child {
  flex: 1;
  min-height: 0;
  overflow: auto;
}

.db__tree-title,
.db__schema-name {
  margin: 0 0 var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.db__tree-empty {
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
}

.db__schema {
  margin-bottom: var(--ds-spacing-s);
}

.db__table {
  display: block;
  width: 100%;
  padding: var(--ds-spacing-xs) var(--ds-spacing-xs);
  background: transparent;
  color: var(--ds-color-text-primary);
  border: 0;
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  text-align: left;
  cursor: pointer;
}

.db__table:hover {
  background: var(--ds-color-surface-panel);
}

/* 对象树两档视图切换（FR-META-15） */
.db__tree-modes {
  display: flex;
  gap: var(--ds-spacing-xs);
  margin-bottom: var(--ds-spacing-xs);
}

.db__tree-mode {
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  background: transparent;
  color: var(--ds-color-text-secondary);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  cursor: pointer;
}

.db__tree-mode--on {
  color: var(--ds-color-text-primary);
  background: var(--ds-color-surface-panel);
}

/* 按类型分组的分组标题（虚拟行：不可展开、不挂右键菜单） */
.db__tree-group {
  margin: var(--ds-spacing-xs) 0 0;
  color: var(--ds-color-text-primary);
  font-size: var(--ds-font-caption-size);
  font-weight: 600;
}

/* 第三层：列 + 数据类型 */
.db__column {
  margin: 0;
  padding: 0 0 0 var(--ds-spacing-l);
  color: var(--ds-color-text-secondary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
}

.db__chevron--inline {
  display: inline-block;
  width: 1em;
}

.db__result-row {
  display: flex;
  flex: 1;
  min-height: 0;
}

.db__row {
  cursor: pointer;
}

/* 外键入口：贴着单元格右侧的小箭头（**只在有目标时渲染**） */
.db__fk {
  margin-left: var(--ds-spacing-xs);
  padding: 0 var(--ds-spacing-xs);
  background: transparent;
  color: var(--ds-color-accent-accent);
  border: 0;
  cursor: pointer;
}

.db__detail-fk {
  margin-top: var(--ds-spacing-xs);
}

.db__row:hover td {
  background: var(--ds-color-surface-panel);
}

.db__detail {
  width: 380px;
  overflow: auto;
  padding: var(--ds-spacing-s) var(--ds-spacing-m);
  border-left: var(--ds-metric-hairline) solid var(--ds-hairline);
  background: var(--ds-color-surface-sidebar);
}

.db__detail-title {
  margin: 0 0 var(--ds-spacing-s);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.db__detail-list {
  margin: 0;
}

.db__detail-list dt {
  margin-top: var(--ds-spacing-s);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.db__detail-meta {
  margin: 0 0 var(--ds-spacing-xs);
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
}

.db__detail-value {
  margin: 0;
  padding: var(--ds-spacing-xs);
  background: var(--ds-color-surface-content);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  white-space: pre-wrap;
  word-break: break-all;
}
.db__browse {
  display: block;
  width: 100%;
  padding: 0 var(--ds-spacing-xs);
  background: transparent;
  color: var(--ds-color-text-tertiary);
  border: 0;
  font-size: var(--ds-font-caption-size);
  text-align: left;
  cursor: pointer;
}

.db__browse-panel {
  padding: var(--ds-spacing-s) var(--ds-spacing-m);
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
  background: var(--ds-color-surface-panel);
}

.db__browse-title {
  margin: 0 0 var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.db__browse-fields {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  gap: var(--ds-spacing-s);
}

.db__browse-fields .db__field input {
  min-width: 220px;
}

.db__sql-preview {
  margin: var(--ds-spacing-xs) 0 0;
  padding: var(--ds-spacing-xs);
  background: var(--ds-color-surface-content);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  white-space: pre-wrap;
}
.db__kind {
  margin-left: var(--ds-spacing-xs);
  color: var(--ds-color-text-tertiary);
}

.db__main {
  display: flex;
  flex: 1;
  min-width: 0;
  flex-direction: column;
}

.db__sql {
  padding: var(--ds-spacing-s) var(--ds-spacing-m);
}

.db__sql textarea {
  width: 100%;
  padding: var(--ds-spacing-s);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  resize: vertical;
}

.db__sql-actions {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-s);
  margin-top: var(--ds-spacing-xs);
}

/* ── 保存查询（FR-EDIT-14）：面板 = 一条输入 + 两个按钮；清单 = 每条两路回填 ───────────── */

.db__save-query,
.db__saved-queries {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--ds-spacing-s);
  margin-top: var(--ds-spacing-xs);
  padding: var(--ds-spacing-s);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-raised);
}

.db__saved-queries {
  flex-direction: column;
  align-items: stretch;
}

.db__save-query-label {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-s);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.db__save-query-input {
  min-width: 22rem;
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  font: inherit;
}

.db__save-query-input:focus-visible {
  outline: var(--ds-metric-hairline) solid var(--ds-color-accent-accent);
  outline-offset: 1px;
}

/* 冲突与失败都是**要人读**的话：占一整行，不与按钮挤在一起 */
.db__save-query-warn,
.db__save-query-error,
.db__save-query-source {
  flex-basis: 100%;
  margin: 0;
  font-size: var(--ds-font-caption-size);
}

/* 「要存的是 AI 生成的那段」：提示色而不是警告色（它不是问题，是要紧的口径） */
.db__save-query-source {
  color: var(--ds-color-text-secondary);
}

.db__save-query-warn {
  color: var(--ds-color-status-warning);
}

.db__save-query-error {
  color: var(--ds-color-status-danger);
}

.db__saved-empty {
  margin: 0;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.db__saved-list {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
  margin: 0;
  padding: 0;
  list-style: none;
  max-height: 16rem;
  overflow: auto;
}

.db__saved-item {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-hair);
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border-radius: var(--ds-radius-control);
}

.db__saved-head {
  display: flex;
  align-items: baseline;
  gap: var(--ds-spacing-s);
}

.db__saved-name {
  color: var(--ds-color-text-primary);
}

.db__saved-source,
.db__saved-sql {
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
  margin: 0;
}

/* SQL 摘要与编辑器同一套字体：看到的就是那一份文本 */
.db__saved-sql {
  font-family: var(--ds-font-stack);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.db__saved-actions {
  display: flex;
  gap: var(--ds-spacing-xs);
}

/* ── SQL 编辑面（1.2）：高亮层 + 真 textarea 叠放 / 补全清单 / 逐段结果 ─────────────── */

.db__editor {
  position: relative;
}

/* 高亮层与 textarea **必须共用**同一份字体、字号、行高、内边距与换行规则：
   任何一处不同，光标与字就会错位（这是这种叠放做法的经典坑）。 */
.db__editor-highlight,
.db__editor textarea {
  margin: 0;
  padding: var(--ds-spacing-s);
  /* 字体族与字号**只认这两个自定义属性**（FR-EDIT-26）：由外壳把偏好贴到根元素上，
     两层一起变。缺省值 = 令牌层的等宽栈 + 13px（与 Rust 侧 `EditorFont::default()` 一致）。 */
  font-family: var(--ds-editor-font-family, var(--ds-font-stack-mono));
  font-size: var(--ds-editor-font-size, 13px);
  line-height: 1.5;
  white-space: pre-wrap;
  word-break: break-word;
  border: var(--ds-metric-hairline) solid transparent;
  border-radius: var(--ds-radius-control);
}

.db__editor-highlight {
  position: absolute;
  inset: 0;
  overflow: hidden;
  color: var(--ds-color-text-primary);
  pointer-events: none;
}

.db__editor textarea {
  position: relative;
  width: 100%;
  background: var(--ds-color-surface-content);
  /* 字色透明：看到的是下面那层的上色文字；光标色仍用主题色（否则看不见光标） */
  color: transparent;
  caret-color: var(--ds-color-text-primary);
  border-color: var(--ds-hairline);
  /* 高度改由分隔条（FR-EDIT-13）统一管：留 `vertical` 会出现两套拖拽互相打架，
     用户拖出来的高度也会与分隔条记住的那个数不一致。 */
  resize: none;
}

/* 分隔条（FR-EDIT-13）：8px 细条 + 居中握把。命中区比视觉粗（hover 时高亮），
   否则一条 1px 的线鼠标追不住。 */
.db__split {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 8px;
  flex: none;
  cursor: row-resize;
  border-top: var(--ds-metric-hairline) solid var(--ds-hairline);
  background: transparent;
  touch-action: none;
}

.db__split-grip {
  width: 40px;
  height: 2px;
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-text-secondary);
  opacity: 0.35;
}

.db__split:hover .db__split-grip,
.db__split:focus-visible .db__split-grip,
.db__split--active .db__split-grip {
  opacity: 1;
  background: var(--ds-color-accent-accent);
}

.db__split:focus-visible {
  /* 键盘焦点要看得见（无障碍）：用强调色描边，且收在条内不推动布局。 */
  outline: 2px solid var(--ds-color-accent-accent);
  outline-offset: -2px;
}

.db__editor textarea::selection {
  background: var(--ds-color-accent-accent);
}

/* 按键提示（B1 接线）：一行小字、低对比，只为让这几组键**看得见**，不抢编辑面。 */
.db__editor-keys {
  margin: 0 0 var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}
/* 状态栏（B1 第二批）：三格读数 + 一颗「跳行列」按钮。数字用 tabular-nums，宽度不跳。 */
.db__editor-status {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-s);
  margin: 0 0 var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}
.db__status-caret,
.db__status-indent {
  font-variant-numeric: tabular-nums;
}
.db__status-dot {
  color: var(--ds-color-text-tertiary);
}
.db__status-bracket--matched {
  color: var(--ds-color-status-success);
}
.db__status-bracket--unmatched {
  color: var(--ds-color-status-danger);
}
.db__status-bracket--none {
  color: var(--ds-color-text-tertiary);
}
.db__status-goto {
  margin-left: auto;
  padding: 0 var(--ds-spacing-s);
  background: transparent;
  color: var(--ds-color-text-secondary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  cursor: pointer;
}
.db__status-goto:hover {
  color: var(--ds-color-accent-accent);
}
/* 跳行列输入条（Ctrl+G）：一行、窄输入、错误就地显示 */
.db__goto {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-s);
  margin: 0 0 var(--ds-spacing-xs);
  font-size: var(--ds-font-caption-size);
}
.db__goto-label {
  display: inline-flex;
  align-items: center;
  gap: var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
}
.db__goto-input {
  width: 8ch;
  padding: 0 var(--ds-spacing-xs);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  font-variant-numeric: tabular-nums;
}
.db__goto-error {
  color: var(--ds-color-status-danger);
}

/* 编辑菜单（FR-EDIT-17）：按钮 + 锚在它下面的下拉。锚点靠 relative 容器，菜单本身 fixed 会跑到窗口角落。 */
.db__edit-menu {
  position: relative;
  display: inline-flex;
}
/* 点空白处收菜单用的透明挡板（比在 document 上挂监听更省：不会漏摘） */
.db__menu-backdrop {
  position: fixed;
  inset: 0;
  z-index: 39;
}
.db__menu--dropdown {
  position: absolute;
  top: calc(100% + var(--ds-spacing-xs));
  left: 0;
  z-index: 41;
}

/* 查找 / 替换条（FR-EDIT-18）：与跳行列同一条视觉带；读数用等宽数字，换匹配时宽度不跳 */
.db__find {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--ds-spacing-s);
  margin: 0 0 var(--ds-spacing-xs);
  font-size: var(--ds-font-caption-size);
}
.db__find-field {
  display: inline-flex;
  align-items: center;
  gap: var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
}
.db__find-input {
  width: 18ch;
  padding: 0 var(--ds-spacing-xs);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
}
.db__find-case {
  display: inline-flex;
  align-items: center;
  gap: var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
  white-space: nowrap;
}
.db__find-readout {
  color: var(--ds-color-text-secondary);
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
/* 没有匹配 / 还没填：用告警色说清，不留一个空白格让人以为"还在算" */
.db__find-readout--empty {
  color: var(--ds-color-status-warning);
}
.db__find-note {
  color: var(--ds-color-text-secondary);
}

/* 格式化 SQL 的回执（FR-EDIT-22）：与查找条同一条视觉带；拒绝/出错走告警色，
   并且**和成功态长得不一样**（同一句话两种结果的差别要在颜色上看得出来）。 */
.db__format-note {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-s);
  margin: 0 0 var(--ds-spacing-xs);
  font-size: var(--ds-font-caption-size);
  color: var(--ds-color-text-secondary);
}
.db__format-note--bad {
  color: var(--ds-color-status-warning);
}

/* 诊断下划线（FR-EDIT-56）：出问题的范围在字下加虚下划线 —— 只做"哪一段有问题"，
   颜色走状态令牌（与问题条同一套），不在样式里写死颜色。 */
.db__tok--error {
  text-decoration: underline dashed;
  text-decoration-color: var(--ds-color-status-danger);
  text-decoration-thickness: 1px;
  text-underline-offset: 2px;
}
.db__tok--warning {
  text-decoration: underline dashed;
  text-decoration-color: var(--ds-color-status-warning);
  text-decoration-thickness: 1px;
  text-underline-offset: 2px;
}
.db__tok--info {
  text-decoration: underline dotted;
  text-decoration-color: var(--ds-color-text-tertiary);
  text-underline-offset: 2px;
}
/* 问题条（FR-EDIT-56）：一行计数 + 逐条可点的行（点一条把光标搬过去） */
.db__problems {
  display: flex;
  align-items: flex-start;
  gap: var(--ds-spacing-s);
  margin: 0 0 var(--ds-spacing-xs);
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  background: var(--ds-color-surface-content);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-size: var(--ds-font-caption-size);
}
.db__problems-count {
  color: var(--ds-color-status-danger);
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.db__problems-list {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-hair);
  margin: 0;
  padding: 0;
  list-style: none;
}
.db__problem {
  display: flex;
  gap: var(--ds-spacing-xs);
  align-items: baseline;
  padding: 0;
  background: transparent;
  color: var(--ds-color-text-secondary);
  border: 0;
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  text-align: left;
  cursor: pointer;
}
.db__problem:hover .db__problem-msg {
  color: var(--ds-color-text-primary);
}
.db__problem-at {
  color: var(--ds-color-text-tertiary);
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.db__problem--error .db__problem-at {
  color: var(--ds-color-status-danger);
}
.db__problem--warning .db__problem-at {
  color: var(--ds-color-status-warning);
}

.db__tok--keyword {
  color: var(--ds-color-accent-accent);
}

.db__tok--string {
  color: var(--ds-color-status-success);
}

.db__tok--number {
  color: var(--ds-color-status-warning);
}

.db__tok--line_comment,
.db__tok--block_comment {
  color: var(--ds-color-text-tertiary);
}

.db__tok--quoted_ident {
  color: var(--ds-color-status-warning);
}

.db__completions {
  max-height: 220px;
  margin: var(--ds-spacing-xs) 0 0;
  padding: var(--ds-spacing-xs) 0;
  overflow: auto;
  background: var(--ds-color-surface-raised);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  list-style: none;
}

.db__completion {
  display: flex;
  justify-content: space-between;
  gap: var(--ds-spacing-s);
  width: 100%;
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  background: transparent;
  color: var(--ds-color-text-primary);
  border: 0;
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  text-align: left;
  cursor: pointer;
}

.db__completion--active,
.db__completion:hover {
  background: var(--ds-color-surface-panel);
}

.db__completion-text {
  font-family: var(--ds-font-stack);
}

/* 清单底部的按键提示（B1 收尾）：低对比、贴边、不吃点击 */
.db__completion-hint {
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
  font-variant-numeric: tabular-nums;
  border-top: var(--ds-metric-hairline) solid var(--ds-hairline);
}

.db__outcomes {
  padding: 0 var(--ds-spacing-m) var(--ds-spacing-s);
}

.db__outcomes-title {
  margin: 0 0 var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.db__outcomes-list {
  margin: 0;
  padding: 0;
  list-style: none;
}

.db__outcome {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-s);
  width: 100%;
  padding: var(--ds-spacing-xs);
  background: transparent;
  color: var(--ds-color-text-primary);
  border: 0;
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  text-align: left;
  cursor: pointer;
}

.db__outcome:hover {
  background: var(--ds-color-surface-panel);
}

.db__outcome--active {
  background: var(--ds-color-surface-panel);
}

.db__outcome--bad {
  color: var(--ds-color-status-danger);
}

.db__outcome-summary {
  flex: 0 0 auto;
}

.db__outcome-sql {
  overflow: hidden;
  color: var(--ds-color-text-tertiary);
  white-space: nowrap;
  text-overflow: ellipsis;
}

/* ── 写回（1.4）：工具栏 / 待执行语句 / 就地编辑的单元格 ───────────────────────────── */

.db__writeback {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--ds-spacing-s);
  margin-bottom: var(--ds-spacing-xs);
}

.db__dml {
  margin-bottom: var(--ds-spacing-xs);
  padding: var(--ds-spacing-s);
  background: var(--ds-color-surface-panel);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
}

.db__dml-title {
  margin: 0 0 var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.db__dml-list {
  margin: 0;
  padding-left: var(--ds-spacing-m);
  font-size: var(--ds-font-caption-size);
}

.db__dml-list code {
  font-family: var(--ds-font-stack);
}

/* 改过但还没提交的格子：一眼能看出"哪些是我改的"（提交后会被真值覆盖） */
.db__cell--edited {
  background: var(--ds-color-surface-raised);
  outline: var(--ds-metric-hairline) solid var(--ds-color-accent-accent);
}

.db__cell-input {
  width: 100%;
  min-width: 60px;
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-color-accent-accent);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
}

.db__grid-wrap {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: 0 var(--ds-spacing-m) var(--ds-spacing-m);
}

.db__grid {
  border-collapse: collapse;
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
}

.db__grid th,
.db__grid td {
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  text-align: left;
  white-space: nowrap;
}

.db__freeze {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.db__freeze input {
  width: 56px;
  height: var(--ds-metric-control-height);
  padding: 0 var(--ds-spacing-xs);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
}

/* 冻结列要有自己的底色，否则滚动时下面的内容会透出来 */
.db__frozen {
  background: var(--ds-color-surface-content);
}

.db__grid-head.db__frozen,
th.db__grid-head[style] {
  background: var(--ds-color-surface-raised);
}
.db__grid-tools {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-s);
  margin-bottom: var(--ds-spacing-xs);
}

.db__grid-tools input {
  height: var(--ds-metric-control-height);
  padding: 0 var(--ds-spacing-s);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
}

.db__select {
  height: var(--ds-metric-control-height);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
}

.db__grid-head {
  cursor: pointer;
}

.db__sort-mark {
  margin-left: var(--ds-spacing-xs);
  color: var(--ds-color-accent-accent);
}
.db__grid th {
  position: sticky;
  top: 0;
  background: var(--ds-color-surface-raised);
}

.db__null {
  color: var(--ds-color-text-tertiary);
}

/* ── 对象树（1.1）：搜索框 / 可展开的 schema / 命中清单 / 右键菜单 ───────────────────── */

/* 连接列表与对象树（图里的左栏两块）：分组标题 / 两行条目 / 视图切换 / 工具条 */
/* 工具条里的内联字段（库下拉）与分隔线 */
.db__bar-field--inline {
  flex-direction: row;
  align-items: center;
  gap: var(--ds-spacing-hair);
}

.db__bar-sep {
  width: var(--ds-metric-hairline);
  align-self: stretch;
  background: var(--ds-hairline);
  margin: 0 var(--ds-spacing-hair);
}

/* 查询页签（图里的「查询 1 ×」+ 加号） */
.db__qtabs {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-hair);
  height: var(--ds-metric-tab-height);
  padding: 0 var(--ds-spacing-xs);
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
}

.db__qtab {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-hair);
  height: 100%;
  padding: 0 var(--ds-spacing-xs) 0 var(--ds-spacing-s);
  border-bottom: var(--ds-metric-hairline) solid transparent;
}

.db__qtab--active {
  border-bottom-color: var(--ds-color-accent-accent);
  background: var(--ds-color-surface-raised);
}

.db__qtab-name {
  border: none;
  background: transparent;
  color: var(--ds-color-text-secondary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  cursor: pointer;
}

.db__qtab--active .db__qtab-name {
  color: var(--ds-color-text-bright);
}

.db__qtab-close {
  border: none;
  background: transparent;
  color: var(--ds-color-text-tertiary);
  cursor: pointer;
  font-size: var(--ds-font-caption-size);
}

.db__qtab-close:disabled {
  opacity: 0;
  cursor: default;
}

.db__qtab:hover .db__qtab-close:not(:disabled) {
  color: var(--ds-color-text-primary);
}

.db__qtab-add {
  border: none;
  background: transparent;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-body-size);
  cursor: pointer;
  padding: 0 var(--ds-spacing-xs);
}

.db__qtab-add:hover {
  color: var(--ds-color-accent-accent);
}

/* 页签条上的拦截回执（FR-EXEC-07）：置灰的按钮旁边必须有一句话说明为什么 */
.db__qtab-note {
  margin-left: var(--ds-spacing-s);
  color: var(--ds-color-status-warning);
  font-size: var(--ds-font-caption-size);
}

/* 查询参数填值面板（FR-EXEC-17）：行 = 名字 + 次数 + 类型 + 值 */
.db__params {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
  margin: 0 0 var(--ds-spacing-xs);
  padding: var(--ds-spacing-s);
  background: var(--ds-color-surface-content);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-size: var(--ds-font-caption-size);
}

.db__params-head {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: var(--ds-spacing-s);
}

.db__params-title {
  color: var(--ds-color-text-primary);
  font-weight: 600;
}

.db__params-tip {
  color: var(--ds-color-text-secondary);
}

.db__params-row {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-s);
}

.db__params-name {
  min-width: 12ch;
  color: var(--ds-color-accent-accent);
}

.db__params-count {
  color: var(--ds-color-text-secondary);
}

.db__params-kind,
.db__params-value {
  padding: 0 var(--ds-spacing-xs);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-size: var(--ds-font-caption-size);
}

.db__params-value {
  flex: 1;
  min-width: 16ch;
}

.db__params-error {
  margin: 0;
  color: var(--ds-color-status-danger);
}

.db__params-actions {
  display: flex;
  gap: var(--ds-spacing-s);
}

.db__params-note {
  margin: 0 0 var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.db__params-note--bad {
  color: var(--ds-color-status-warning);
}

.db__context {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-xs);
  margin: 0;
  padding: var(--ds-spacing-xs) var(--ds-spacing-m) 0;
  font-size: var(--ds-font-body-size);
}

/* 连接条目：两行（名字 + 主机·库名 小字），当前连着的那个高亮 */
/* 对象树头部的两个视图切换（图里的 层级视图 / 按类型分组） */
.db__view-switch {
  display: flex;
  gap: var(--ds-spacing-hair);
  margin: 0 var(--ds-spacing-xs) var(--ds-spacing-xs);
  padding: var(--ds-spacing-hair);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-raised);
}

.db__view {
  flex: 1;
  height: var(--ds-metric-toolbar-button-height);
  border: none;
  border-radius: var(--ds-radius-hairline);
  background: transparent;
  color: var(--ds-color-text-secondary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  cursor: pointer;
}

.db__view--active {
  background: var(--ds-color-accent-accent);
  color: var(--ds-color-surface-content);
}

.db__tree-tools {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-hair);
  margin: 0 var(--ds-spacing-xs) var(--ds-spacing-xs);
}

.db__icon-btn {
  flex: none;
  width: var(--ds-metric-toolbar-button-width);
  height: var(--ds-metric-toolbar-button-height);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: transparent;
  color: var(--ds-color-text-secondary);
  cursor: pointer;
}

.db__icon-btn:hover {
  color: var(--ds-color-text-primary);
  border-color: var(--ds-color-accent-accent);
}

.db__tree-search {
  width: 100%;
  height: var(--ds-metric-control-height);
  margin-bottom: var(--ds-spacing-xs);
  padding: 0 var(--ds-spacing-s);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
}

.db__schema-toggle {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-xs);
  width: 100%;
  padding: var(--ds-spacing-xs);
  background: transparent;
  color: var(--ds-color-text-secondary);
  border: 0;
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  text-align: left;
  cursor: pointer;
}

.db__schema-toggle:hover {
  background: var(--ds-color-surface-panel);
}

/* 三角形只在位置上占位：展开与否靠字形换，不靠加宽 —— 免得展开时整列跟着跳 */
.db__chevron {
  width: 1em;
  flex: 0 0 auto;
  color: var(--ds-color-text-tertiary);
}

.db__hits {
  margin: 0;
  padding: 0;
  list-style: none;
}

.db__menu {
  position: fixed;
  z-index: 40;
  min-width: 168px;
  margin: 0;
  padding: var(--ds-spacing-xs) 0;
  background: var(--ds-color-surface-raised);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  list-style: none;
  box-shadow: 0 6px 20px rgb(0 0 0 / 28%);
}

.db__menu-head {
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  color: var(--ds-color-text-tertiary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  white-space: nowrap;
}

.db__menu-item {
  display: block;
  width: 100%;
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  background: transparent;
  color: var(--ds-color-text-primary);
  border: 0;
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  text-align: left;
  cursor: pointer;
}

.db__menu-item:hover:not(:disabled) {
  background: var(--ds-color-accent-accent);
  color: var(--ds-color-surface-content);
}

/* 不可用的动作**置灰但不隐藏**（FR-META-11）：菜单里少一项，用户会以为功能不存在 */
.db__menu-item:disabled {
  color: var(--ds-color-text-tertiary);
  cursor: not-allowed;
}

/* 节点图标（FR-META-06）：占位固定，免得有图标 / 没图标的行文字对不齐 */
.db__icon {
  display: inline-flex;
  align-items: center;
  flex: 0 0 auto;
  margin-right: var(--ds-spacing-xs);
  color: var(--ds-color-text-tertiary);
}

.db__icon > svg {
  vertical-align: middle;
}

/* 服务器节点（FR-META-11 第一期）：树的第一行，比 schema 行更"根"一点 */
.db__server {
  color: var(--ds-color-text-primary);
}

/* ── 表设计器（1.5）：结构网格 + 变更集 ───────────────────────────────────────────── */

.db__designer {
  padding: var(--ds-spacing-s) var(--ds-spacing-m);
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
  background: var(--ds-color-surface-panel);
}

.db__designer-grid {
  margin-bottom: var(--ds-spacing-s);
}

.db__designer-grid .db__cell-input {
  min-width: 120px;
}

/* ── 导入导出面板（1.6）──────────────────────────────────────────────────────────── */

.db__io {
  margin-bottom: var(--ds-spacing-s);
  padding: var(--ds-spacing-s);
  background: var(--ds-color-surface-panel);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
}

.db__io-path {
  min-width: 320px;
}
</style>