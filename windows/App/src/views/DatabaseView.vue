<script setup lang="ts">
// 数据库视图（Windows 侧）—— alpha 1.0 的**读数据竖切**第一版
//
// 口径：模型与解析在领域层（`windows/Db`），驱动在 Rust 外壳（`src-tauri/src/postgres.rs`），
// 本组件只做显示与转交 —— 三类状态各归其位：
//   · 失败：**服务端原话**与提示**两段都显示**（不合并成"失败了"）；
//   · 截断：`truncated` 为真时**如实说**（不静默少给行）；
//   · 未连接：按钮可用但一按就给可读原因（不做"灰着但不说为什么"）。

import { computed, onMounted, ref } from 'vue'
import {
  LAB_CONNECTION,
  connectionDelete,
  connectionSave,
  connectionsList,
  dbConnect,
  dbDisconnect,
  dbQuery,
  dbSchemas,
  dbRelations,
  searchObjects,
  browseSql,
  inspectRow,
  dbTables,
  type ConnectParams,
  type DbFailure,
  type QueryResult,
  type SavedConnection,
  type ServerInfo,
  type RowField,
  type StartupOutcome,
  type TableNode,
  type ObjectNode,
  type SearchHit,
} from '../ipc'
import { frozenColumnStyles, toTsv, visibleOrder } from '../grid/view'

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
}

// 冻结列（FR-RES-05）：只冻最左边连续若干列；偏移用估算宽度（纯函数，已单测）
const frozenCount = ref(0)
const frozenStyles = computed<Record<number, { left: string; zIndex: number }>>(() =>
  result.value ? frozenColumnStyles(result.value.columns, frozenCount.value) : {},
)

/** 表头 / 单元格的内联样式：冻的列给 sticky + left，不冻的列给空 */
function cellStyle(index: number): Record<string, string> {
  const style = frozenStyles.value[index]
  if (!style) return {}
  return { position: 'sticky', left: style.left, zIndex: String(style.zIndex) }
}

/** 复制**看得见的**那一屏（TSV，贴 Excel 直接分列；NULL 是空单元格） */
async function copyVisible() {
  if (!result.value) return
  const text = toTsv(result.value, visible.value)
  try {
    await navigator.clipboard.writeText(text)
    copied.value = `已复制 ${visible.value.length} 行`
  } catch (e) {
    copied.value = '复制失败：浏览器/外壳不给剪贴板权限（可手动选中表格复制）'
  }
  setTimeout(() => (copied.value = ''), 2500)
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
      <!-- 连接列表（保存过的连接；口令不在其中，在系统凭据管理器里） -->
      <aside class="db__tree db__tree--connections">
        <p class="db__tree-title">连接（{{ saved.length }}）</p>
        <p v-if="saved.length === 0" class="db__tree-empty">
          还没有保存过连接。填好上面的表单按「保存到连接列表」，口令（若勾了记住）进系统凭据管理器。
        </p>
        <div v-for="c in saved" :key="c.id" class="db__conn">
          <button
            class="db__table"
            type="button"
            :title="`${c.username}@${c.host}:${c.port}/${c.database}（口令不在配置文件里）`"
            @click="useSaved(c)"
          >
            {{ c.name }}<span class="db__kind">{{ c.isReadOnly ? '只读' : '' }}</span>
          </button>
          <button class="db__conn-del" type="button" title="删除这条连接（并清掉它的凭据）" @click="removeSaved(c)">
            ✕
          </button>
        </div>
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
          <template v-else>
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
        <li><button class="db__menu-item" type="button" @click="menuCopyName">复制名</button></li>
      </ul>

        <!-- 服务端条件浏览面板（FR-DATA-02）：先看 SQL，再执行 -->
        <div v-if="browse" class="db__browse-panel">
          <p class="db__browse-title">
            按条件浏览：<code>{{ browse.schema }}.{{ browse.table }}</code>
            <button class="db__btn" type="button" @click="browse = null">收起</button>
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
            <button class="db__btn db__btn--primary" type="button" @click="runBrowse">执行</button>
          </div>
          <p v-if="browseError" class="db__failure-msg">{{ browseError }}</p>
          <pre v-if="sqlText" class="db__sql-preview">{{ sqlText }}</pre>
        </div>

      <!-- SQL 与结果 -->
      <div class="db__main">
        <form class="db__sql" @submit.prevent="run">
          <textarea v-model="sql" spellcheck="false" rows="3" aria-label="SQL" />
          <div class="db__sql-actions">
            <button class="db__btn db__btn--primary" type="submit" :disabled="!!busy">执行</button>
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


        <!-- 结果区：左表格（可排序 / 筛选 / 复制 / 点行看详情）+ 右详情（竖排值检查） -->
        <div class="db__result-row">
          <template v-if="result && result.columns.length">
            <div class="db__grid-wrap">
              <div class="db__grid-tools">
                <input v-model="filter" type="search" placeholder="筛选（当前结果内，不分大小写）" aria-label="筛选结果" />
                <span class="db__note">显示 {{ visible.length }} / {{ result.rows.length }} 行</span>
                <label class="db__freeze">
                  冻结前
                  <input v-model.number="frozenCount" type="number" min="0" :max="result.columns.length" />
                  列
                </label>
                <button class="db__btn" type="button" @click="copyVisible">复制（TSV）</button>
                <span v-if="copied" class="db__note">{{ copied }}</span>
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
                    v-for="i in visible"
                    :key="i"
                    class="db__row"
                    title="点这一行看详情（值检查：NULL 与空串分开、长 JSON 格式化）"
                    @click="openDetail(i)"
                  >
                    <td v-for="(cell, j) in result.rows[i]" :key="j" :style="cellStyle(j)" :class="{ 'db__null': cell === null, 'db__frozen': !!frozenStyles[j] }">
                      {{ cell === null ? 'NULL' : cell }}
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
</style>