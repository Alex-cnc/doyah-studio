<script setup lang="ts">
// 数据库视图（Windows 侧）—— alpha 1.0 的**读数据竖切**第一版
//
// 口径：模型与解析在领域层（`windows/Db`），驱动在 Rust 外壳（`src-tauri/src/postgres.rs`），
// 本组件只做显示与转交 —— 三类状态各归其位：
//   · 失败：**服务端原话**与提示**两段都显示**（不合并成"失败了"）；
//   · 截断：`truncated` 为真时**如实说**（不静默少给行）；
//   · 未连接：按钮可用但一按就给可读原因（不做"灰着但不说为什么"）。

import { computed, nextTick, onMounted, ref, watch } from 'vue'
import {
  LAB_CONNECTION,
  connectionDelete,
  connectionSave,
  connectionsList,
  dbConnect,
  dbDisconnect,
  dbQuery,
  dbRunBatch,
  dbCancel,
  explainStatement,
  highlightSql,
  dbWriteBatch,
  dbPrimaryKey,
  editsToDml,
  statementRisk,
  dbReadOnly,
  dbSchemas,
  dbRelations,
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
  type ConnectParams,
  type DbFailure,
  type QueryResult,
  type SavedConnection,
  type ServerInfo,
  type RowField,
  type StartupOutcome,
  type StatementOutcome,
  type TableNode,
  type ObjectNode,
  type SearchHit,
  type SqlToken,
  type CellEdit,
  type DmlStatement,
  type ColumnDef,
  type TableShape,
  type DdlStatement,
  type ImportPreview,
} from '../ipc'
import { frozenColumnStylesMeasured, pageOf, visibleOrder, DEFAULT_PAGE_SIZE } from '../grid/view'
import { EXPORT_FORMAT_LABELS, exportRows, type ExportFormat } from '../grid/export'
import { t as translate, toggleLanguage, type UiLanguage } from '../i18n'
import {
  filterCompletions,
  highlightPieces,
  keywordCompletions,
  objectCompletions,
  outcomeSummary,
  pickDisplayedOutcome,
  wordBeforeCaret,
  type CompletionItem,
} from '../sql/editor'

// **界面语言（1.8 双语）**：与标题栏同一套取值（zh-Hans / en）
// 口径：语言表只覆盖**界面外壳**；正文说明与服务端提示仍是中文（已在版本计划里登记未落）。
// 视图往底部面板打输出（图里的「输出 / 问题」两格就是收这个）
const emit = defineEmits<{
  (event: 'push-panel', entry: { text: string; level: 'info' | 'warn' | 'error'; source?: string }): void
}>()

const language = ref<UiLanguage>('zh-Hans')
function t(key: Parameters<typeof translate>[0], vars?: Record<string, string | number>): string {
  return translate(key, language.value, vars)
}

const form = ref<ConnectParams>({ ...LAB_CONNECTION })
const password = ref('')
const remember = ref(true)
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
/**
 * 连接列表分组（布局对齐 macOS 封面图）：图里左栏是「连接列表」下有分组标题（示例：未分组）。
 *
 * 两条口径：
 * 1. **没分组的归到「未分组」，且这一档永远排最后**（其余按名字排 —— 顺序稳定，用户才记得住位置）；
 * 2. **当前连着的那个高亮**：拿 `info` 里的主机/端口/库与每条比对，**不另存一份"选中 id"**
 *    （两处状态迟早会不一致）。
 */
const connectionGroups = computed(() => {
  const byGroup = new Map<string, SavedConnection[]>()
  for (const connection of saved.value) {
    const key = (connection.group ?? '').trim() || '未分组'
    const list = byGroup.get(key) ?? []
    list.push(connection)
    byGroup.set(key, list)
  }
  return [...byGroup.entries()]
    .map(([name, items]) => ({ name, items }))
    .sort((a, b) => {
      if (a.name === '未分组') return 1
      if (b.name === '未分组') return -1
      return a.name.localeCompare(b.name)
    })
})

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

/** 小字：`主机 · 库名`（图里就是这个形状）。 */
function connectionSubtitle(connection: SavedConnection): string {
  return `${connection.host} · ${connection.database}`
}

/**
 * 对象树两种视图（图里那组切换：**层级视图 / 按类型分组**）。
 *
 * 一条口径（与"按需展开"不冲突）：按类型分组**只能在已经加载的对象里分** ——
 * 本侧不在连接时把整库元数据拉光。所以那一档会**如实说**"只含已加载的"。
 */
const objectView = ref<'hierarchy' | 'byKind'>('hierarchy')

/** 按类型分组的树：类型名 → 对象（只含已加载）。 */
const kindGroups = computed<{ kind: string; items: ObjectNode[] }[]>(() => {
  const byKind = new Map<string, ObjectNode[]>()
  for (const object of Object.values(layerOf.value).flat()) {
    const key = object.kind?.trim() || '其他'
    const list = byKind.get(key) ?? []
    list.push(object)
    byKind.set(key, list)
  }
  return [...byKind.entries()]
    .map(([kind, items]) => ({ kind, items }))
    .sort((a, b) => a.kind.localeCompare(b.kind))
    .map((group) => ({
      kind: group.kind,
      items: [...group.items].sort((a, b) =>
        `${a.schema}.${a.name}`.localeCompare(`${b.schema}.${b.name}`),
      ),
    }))
})

/** 已加载的对象数（按类型分组那一档要用）。 */
const loadedObjectCount = computed(() => Object.values(layerOf.value).flat().length)

/** 刷新：重取 schema 列表并丢掉已加载的层（重新按需展开） */
async function refreshObjects() {
  layerOf.value = {}
  expanded.value = {}
  objectQuery.value = ''
  objectHits.value = []
  await loadSchemas()
}

const saved = ref<SavedConnection[]>([])
const info = ref<ServerInfo | null>(null)
const tables = ref<TableNode[]>([])
const sql = ref('select id, name, balance from app.accounts order by id limit 20')
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
  } catch (e) {
    failure.value = describeError(e)
  }
  // 编辑器一进来就上一次高亮（纯计算，失败了也只是退回纯文本）
  await refreshHighlight()
})

/** 这套表单当前对应的连接 id（点列表里的连接 = 换成它的 id；新表单 = 新 id）。 */
const formId = ref(crypto.randomUUID())

/** 点一条保存过的连接：把它填进表单（**口令不在这里**：口令在系统凭据管理器里）。 */
function useSaved(c: SavedConnection) {
  formId.value = c.id
  form.value = {
    host: c.host,
    port: c.port,
    database: c.database,
    user: c.username,
    sslMode: c.sslMode,
  }
  password.value = ''
  failure.value = null
}

async function saveCurrent() {
  busy.value = '保存中…'
  clearFailure()
  try {
    saved.value = await connectionSave({
      id: formId.value,
      name: `${form.value.database}@${form.value.host}`,
      host: form.value.host,
      port: form.value.port,
      database: form.value.database,
      user: form.value.user,
      sslMode: form.value.sslMode,
      isReadOnly: false,
      password: password.value || undefined,
      rememberPassword: remember.value && !!password.value,
    })
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
/** 对象搜索词与命中（`matchedOn` 要显示出来，不能只说"匹配"）。 */
const objectQuery = ref('')
const objectHits = ref<SearchHit[]>([])
/** 右键菜单：位置 + 目标对象；`null` = 没打开。 */
const contextMenu = ref<{ x: number; y: number; object: ObjectNode } | null>(null)

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

/** 第一层：schema 列表（连接后取一次）。 */
const schemas = ref<string[]>([])

async function loadSchemas() {
  try {
    schemas.value = await dbSchemas()
    layerOf.value = {}
    expanded.value = {}
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
    const items = await dbRelations(schema)
    layerOf.value = { ...layerOf.value, [schema]: items }
    clearFailure()
  } catch (e) {
    failure.value = describeError(e)
    // 取不到就**如实收起**：不把一个空列表当成"这个 schema 是空的"
    expanded.value = { ...expanded.value, [schema]: false }
  } finally {
    loadingSchema.value = ''
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

async function run() {
  busy.value = '执行中…'
  clearFailure()
  try {
    result.value = await dbQuery(sql.value)
  } catch (e) {
    result.value = null
    failure.value = describeError(e)
  } finally {
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
const sqlArea = ref<HTMLTextAreaElement | null>(null)

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
  const items = [...keywordCompletions(), ...objectCompletions(loadedObjects.value)]
  completions.value = filterCompletions(items, word)
  completionIndex.value = 0
}

/** Tab / 回车接受当前候选：把光标前那个词换成候选文本。 */
function acceptCompletion(item?: CompletionItem) {
  const chosen = item ?? completions.value[completionIndex.value]
  const area = sqlArea.value
  if (!chosen || !area) return
  const caret = area.selectionStart ?? sql.value.length
  const word = wordBeforeCaret(sql.value, caret)
  sql.value = sql.value.slice(0, caret - word.length) + chosen.text + sql.value.slice(caret)
  completions.value = []
  void refreshHighlight()
}

/** **多段执行**：一次提交多条，逐段报告；显示"先看失败、否则看最后一句"。 */
async function runBatch(analyze: boolean) {
  busy.value = analyze ? '生成并执行计划…' : '执行中…'
  clearFailure()
  try {
    let text = sql.value
    if (analyze) {
      // EXPLAIN 只对单条：多段会被拒（并说明为什么），这里如实把拒绝端出来
      text = await explainStatement(sql.value, true)
    } else {
      // **危险语句先要确认**（1.4）：无 WHERE 的 UPDATE/DELETE、DROP、TRUNCATE。
      // 判定在领域层（只认能确凿认出来的），界面只负责弹框；只读连接会被判 forbidden、直接拒。
      const risk = await statementRisk(text)
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
          busy.value = ''
          return
        }
      }
    }
    outcomes.value = await dbRunBatch(text)
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
    <!-- 连接条 -->
    <form class="db__bar" @submit.prevent="connect">
      <label class="db__field">
        <span>主机</span>
        <input v-model="form.host" type="text" spellcheck="false" />
      </label>
      <label class="db__field db__field--narrow">
        <span>端口</span>
        <input v-model.number="form.port" type="number" min="1" max="65535" />
      </label>
      <label class="db__field">
        <span>库</span>
        <input v-model="form.database" type="text" spellcheck="false" />
      </label>
      <label class="db__field">
        <span>用户</span>
        <input v-model="form.user" type="text" spellcheck="false" />
      </label>
      <label class="db__field">
        <span>口令</span>
        <input v-model="password" type="password" autocomplete="off" placeholder="不落盘、不显示" />
      </label>
      <label class="db__field db__field--check" title="口令进 Windows 凭据管理器（本用户可见），配置文件里没有口令">
        <span>记住口令</span>
        <input v-model="remember" type="checkbox" />
      </label>
      <button class="db__btn db__btn--primary" type="submit" :disabled="!!busy">
        {{ info ? '重新连接' : '连接' }}
      </button>
      <button v-if="info" class="db__btn" type="button" :disabled="!!busy" @click="disconnect">断开</button>
      <button class="db__btn" type="button" :disabled="!!busy" @click="loadTables">列出对象</button>
      <button class="db__btn" type="button" :disabled="!!busy" @click="saveCurrent">保存到连接列表</button>
      <span v-if="busy" class="db__busy">{{ busy }}</span>
    </form>

    <!-- 连上了：显示"连到了哪儿" -->
    <p v-if="info" class="db__info">
      已连接 <strong>{{ info.database }}</strong> （用户 {{ info.user }} ·
      {{ info.serverEncoding }} · schema {{ info.currentSchema ?? '—' }}） ·
      <span :title="info.version">{{ versionShort }}</span>
    </p>

    <!-- 启动 SQL（FR-CONN-17）：连接后自动执行；逐条发、逐条报 -->
    <details class="db__startup">
      <summary>
        启动 SQL（连接后自动执行，逐条发、逐条报错）
        <span v-if="startup.length" class="db__note">
          —— 上次：{{ startup.filter((s) => s.ok).length }} 成 / {{ startup.filter((s) => !s.ok).length }} 败
        </span>
      </summary>
      <textarea
        v-model="startupSql"
        spellcheck="false"
        rows="2"
        aria-label="启动 SQL"
        placeholder="例如 SET search_path = app, public;  或  SET statement_timeout = '5s'"
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
        <!-- 连接列表（图里的左栏上半）：分组 + 每条两行小字 + 当前那条高亮 -->
        <aside class="db__tree db__tree--connections">
          <p class="db__tree-title">连接列表</p>
          <p v-if="saved.length === 0" class="db__tree-empty">
            还没有保存过连接。填好上面的表单按「保存到连接列表」，口令（若勾了记住）进系统凭据管理器。
          </p>
          <template v-else>
            <div v-for="group in connectionGroups" :key="group.name" class="db__conn-group">
              <p class="db__group-title">{{ group.name }}</p>
              <div
                v-for="c in group.items"
                :key="c.id"
                class="db__conn"
                :class="{ 'db__conn--active': isConnected(c) }"
              >
                <button
                  class="db__conn-main"
                  type="button"
                  :title="`${c.username}@${c.host}:${c.port}/${c.database}（口令不在配置文件里）`"
                  @click="useSaved(c)"
                >
                  <span class="db__conn-name">
                    {{ c.name }}
                    <span v-if="c.isReadOnly" class="db__kind">只读</span>
                  </span>
                  <span class="db__conn-sub">{{ connectionSubtitle(c) }}</span>
                </button>
                <button
                  class="db__conn-del"
                  type="button"
                  title="删除这条连接（并清掉它的凭据）"
                  @click="removeSaved(c)"
                >
                  ✕
                </button>
              </div>
            </div>
          </template>
        </aside>

      <!-- 对象树（1.1）：展开一层取一层；右键给「浏览数据 / 生成查询 / 复制名」 -->
      <aside class="db__tree" @click="closeContextMenu">
        <p class="db__tree-title">
          对象（{{ loadedObjects.length }} 个已加载 · {{ schemas.length }} 个 schema）
        </p>
        <p v-if="!info" class="db__tree-empty">未连接</p>
        <template v-else>
          <input
            v-model="objectQuery"
            class="db__tree-search"
            type="search"
            placeholder="搜索对象（名字或 schema）"
            aria-label="搜索数据库对象"
            @input="runObjectSearch"
          />
          <p v-if="objectQuery.trim()" class="db__tree-empty">
            命中 {{ objectHits.length }} 个（只在已加载的 {{ loadedObjects.length }} 个对象里找）
          </p>
          <ul v-if="objectQuery.trim()" class="db__hits">
            <li v-for="hit in objectHits" :key="`${hit.object.schema}.${hit.object.name}`">
              <button
                class="db__table"
                type="button"
                :title="`${hit.object.schema}.${hit.object.name}（命中依据：${hit.matchedOn === 'qualified' ? '限定名' : hit.matchedOn === 'name' ? '对象名' : 'schema 名'}）`"
                @click="useTable({ schema: hit.object.schema, name: hit.object.name, kind: hit.object.kind })"
                @contextmenu.prevent="openContextMenu($event, hit.object)"
              >
                {{ hit.object.name }}<span class="db__kind">{{ hit.object.schema }} · {{ hit.object.kind }}</span>
              </button>
            </li>
          </ul>
          <template v-else-if="!objectQuery.trim() && objectView === 'hierarchy'">
            <p v-if="schemas.length === 0" class="db__tree-empty">没有可展开的 schema</p>
            <div v-for="schema in schemas" :key="schema" class="db__schema">
              <button
                class="db__schema-toggle"
                type="button"
                :aria-expanded="expanded[schema] ? 'true' : 'false'"
                @click="toggleSchema(schema)"
              >
                <span class="db__chevron">{{ expanded[schema] ? '▾' : '▸' }}</span>
                {{ schema }}
                <span v-if="loadingSchema === schema" class="db__kind">加载中…</span>
              </button>
              <template v-if="expanded[schema] && layerOf[schema]">
                <p v-if="layerOf[schema].length === 0" class="db__tree-empty">这个 schema 下没有对象</p>
                <button
                  v-for="t in layerOf[schema]"
                  :key="`${t.schema}.${t.name}`"
                  class="db__table"
                  type="button"
                  :title="`${t.kind} · 点一下生成查询；右键有更多`"
                  @click="useTable({ schema: t.schema, name: t.name, kind: t.kind })"
                  @contextmenu.prevent="openContextMenu($event, t)"
                >
                  {{ t.name }}<span class="db__kind">{{ t.kind === 'table' ? '' : t.kind }}</span>
                </button>
              </template>
            </div>
          </template>
        </template>
      </aside>

      <!-- 右键菜单：**没目标就不给入口** —— 序列之类取不了数的对象不出现「浏览数据」 -->
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
            浏览数据…
          </button>
        </li>
        <li><button class="db__menu-item" type="button" @click="menuGenerateQuery">生成查询</button></li>
        <li><button class="db__menu-item" type="button" @click="menuDesignTable">表结构设计…</button></li>
        <li><button class="db__menu-item" type="button" @click="menuCopyName">复制名</button></li>
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
            <button class="db__btn" type="button" @click="addDraftColumn">{{ t('designer.addColumn') }}</button>
            <button class="db__btn db__btn--primary" type="button" @click="previewDdl">{{ t('designer.generate') }}</button>
            <button
              class="db__btn"
              type="button"
              :disabled="runnableDdl.length === 0"
              @click="applyDdl"
            >
              执行非破坏性（{{ runnableDdl.length }} 句）
            </button>
            <button class="db__btn" type="button" :disabled="ddlPlan.length === 0" @click="copyDdl">
              复制全部语句
            </button>
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
            <button class="db__btn" type="button" @click="previewBrowse">生成 SQL</button>
            <button class="db__btn db__btn--primary" type="button" @click="runBrowse">{{ t('sql.run') }}</button>
          </div>
          <p v-if="browseError" class="db__failure-msg">{{ browseError }}</p>
          <pre v-if="sqlText" class="db__sql-preview">{{ sqlText }}</pre>
        </div>

      <!-- SQL 与结果 -->
      <div class="db__main">
        <form class="db__sql" @submit.prevent="runBatch(false)">
          <!-- 编辑面：**高亮层在下面（透明文字）+ 真 textarea 在上面**。
               两层共用同一份字体与内边距（否则光标与字会错位，这是这种做法的经典坑）。 -->
          <div class="db__editor">
            <pre class="db__editor-highlight" aria-hidden="true"><span
              v-for="(piece, i) in pieces"
              :key="i"
              :class="`db__tok db__tok--${piece.kind}`"
            >{{ piece.text }}</span></pre>
            <textarea
              ref="sqlArea"
              v-model="sql"
              spellcheck="false"
              rows="3"
              aria-label="SQL"
              @input="refreshHighlight(); refreshCompletions()"
              @keyup="refreshCompletions()"
              @click="refreshCompletions()"
              @keydown.tab.prevent="acceptCompletion()"
              @keydown.esc="completions = []"
            />
          </div>
          <ul v-if="completions.length" class="db__completions">
            <li v-for="(c, i) in completions.slice(0, 8)" :key="`${c.kind}:${c.text}`">
              <button
                class="db__completion"
                :class="{ 'db__completion--active': i === completionIndex }"
                type="button"
                @click="acceptCompletion(c)"
              >
                <span class="db__completion-text">{{ c.text }}</span>
                <span class="db__kind">{{ c.detail }}</span>
              </button>
            </li>
          </ul>
          <div class="db__sql-actions">
            <button class="db__btn db__btn--primary" type="submit" :disabled="!!busy">{{ t('sql.run') }}</button>
            <button class="db__btn" type="button" :disabled="!busy" @click="cancelRunning">{{ t('sql.cancel') }}</button>
            <button class="db__btn" type="button" :disabled="!!busy" @click="showPlan">{{ t('sql.planOnly') }}</button>
            <button class="db__btn" type="button" :disabled="!!busy" @click="runBatch(true)">{{ t('sql.runWithPlan') }}</button>
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
                <button class="db__btn" type="button" :disabled="paged.page <= 1" @click="page = paged.page - 1">
                  上一页
                </button>
                <button
                  class="db__btn"
                  type="button"
                  :disabled="paged.page >= paged.pageCount"
                  @click="page = paged.page + 1"
                >
                  下一页
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
                  class="db__btn"
                  type="button"
                  @click="adminOpen = !adminOpen; if (adminOpen) loadAdmin()"
                >
                  管理面板…
                </button>
                <span v-if="copied" class="db__note">{{ copied }}</span>
              </div>

              <!-- 管理面（1.7）：读数只读；维护 / 杀会话**只生成语句**，面板里没有执行按钮 -->
              <div v-if="adminOpen" class="db__io">
                <p class="db__browse-title">
                  库（{{ adminDatabases.length }}）· 会话（{{ adminSessions.length }}）
                  <button class="db__btn" type="button" @click="loadAdmin">{{ t('admin.refresh') }}</button>
                  <button class="db__btn" type="button" @click="loadMaintenance">{{ t('admin.maintenance') }}</button>
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
                  <button class="db__btn db__btn--primary" type="button" :disabled="!!busy" @click="runExport">
                    导出到文件
                  </button>
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
                    class="db__btn db__btn--primary"
                    type="button"
                    :disabled="!importPreview || !!busy"
                    @click="runImportNow"
                  >
                    导入（一个事务）
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
                  class="db__btn"
                  type="button"
                  :disabled="editCount === 0"
                  @click="previewDml"
                >
                  生成 SQL（先看清）
                </button>
                <button
                  class="db__btn"
                  type="button"
                  :disabled="!readOnly && pendingDml.length === 0"
                  @click="submitWriteback(true)"
                >
                  试跑（跑完回滚）
                </button>
                <button
                  class="db__btn db__btn--primary"
                  type="button"
                  :disabled="readOnly || pendingDml.length === 0"
                  @click="submitWriteback(false)"
                >
                  提交（一次事务）
                </button>
                <button v-if="editCount > 0" class="db__btn" type="button" @click="cellEdits = {}; pendingDml = []">
                  放弃改动
                </button>
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
                <button class="db__btn" type="button" @click="detail = null">关闭</button>
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
</template>

<style scoped>
.db {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
}

.db__bar {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  gap: var(--ds-spacing-s);
  padding: var(--ds-spacing-s) var(--ds-spacing-m);
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
  background: var(--ds-color-surface-panel);
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

.db__conn {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-xs);
}

.db__conn-del {
  background: transparent;
  color: var(--ds-color-text-tertiary);
  border: 0;
  cursor: pointer;
}

.db__conn-del:hover {
  color: var(--ds-color-status-danger);
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

.db__tree {
  width: 220px;
  overflow: auto;
  padding: var(--ds-spacing-s);
  border-right: var(--ds-metric-hairline) solid var(--ds-hairline);
  background: var(--ds-color-surface-sidebar);
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
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
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
  resize: vertical;
}

.db__editor textarea::selection {
  background: var(--ds-color-accent-accent);
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
.db__group-title {
  margin: var(--ds-spacing-s) 0 var(--ds-spacing-hair);
  padding: 0 var(--ds-spacing-xs);
  color: var(--ds-color-text-tertiary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
}

/* 连接条目：两行（名字 + 主机·库名 小字），当前连着的那个高亮 */
.db__conn-main {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-hair);
  flex: 1;
  min-width: 0;
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: none;
  border-radius: var(--ds-radius-control);
  background: transparent;
  text-align: left;
  cursor: pointer;
}

.db__conn--active .db__conn-main {
  background: var(--ds-color-surface-raised);
}

.db__conn-name {
  color: var(--ds-color-text-primary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-body-size);
}

.db__conn-sub {
  color: var(--ds-color-text-tertiary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
}

/* 删除入口：悬停才出现（图里没画，但功能不能丢） */
.db__conn-del {
  opacity: 0;
  flex: none;
}

.db__conn:hover .db__conn-del {
  opacity: 1;
}

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

.db__menu-item:hover {
  background: var(--ds-color-accent-accent);
  color: var(--ds-color-surface-content);
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