<script setup lang="ts">
// 数据库视图（Windows 侧）—— alpha 1.0 的**读数据竖切**第一版
//
// 口径：模型与解析在领域层（`windows/Db`），驱动在 Rust 外壳（`src-tauri/src/postgres.rs`），
// 本组件只做显示与转交 —— 三类状态各归其位：
//   · 失败：**服务端原话**与提示**两段都显示**（不合并成"失败了"）；
//   · 截断：`truncated` 为真时**如实说**（不静默少给行）；
//   · 未连接：按钮可用但一按就给可读原因（不做"灰着但不说为什么"）。

import { computed, ref } from 'vue'
import {
  LAB_CONNECTION,
  dbConnect,
  dbDisconnect,
  dbQuery,
  dbTables,
  type ConnectParams,
  type DbFailure,
  type QueryResult,
  type ServerInfo,
  type TableNode,
} from '../ipc'

const form = ref<ConnectParams>({ ...LAB_CONNECTION })
const password = ref('')
const info = ref<ServerInfo | null>(null)
const tables = ref<TableNode[]>([])
const sql = ref('select id, name, balance from app.accounts order by id limit 20')
const result = ref<QueryResult | null>(null)
const failure = ref<DbFailure | null>(null)
const busy = ref('')

/** 服务端版本太长（PostgreSQL 18.6 on x86_64-windows…）⇒ 只显示前两段，完整值放 tooltip。 */
const versionShort = computed(() => {
  const v = info.value?.version ?? ''
  const first = v.split(',')[0] ?? v
  return first.length > 48 ? `${first.slice(0, 48)}…` : first
})

/** 表按 schema 分组（对象树的雏形；逐层钻取是 1.1 段的事）。 */
const grouped = computed(() => {
  const map = new Map<string, TableNode[]>()
  for (const t of tables.value) {
    const list = map.get(t.schema) ?? []
    list.push(t)
    map.set(t.schema, list)
  }
  return [...map.entries()].map(([schema, items]) => ({ schema, items }))
})

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
    info.value = await dbConnect({ ...form.value, password: password.value || undefined })
    result.value = null
    await loadTables()
  } catch (e) {
    info.value = null
    tables.value = []
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
  try {
    tables.value = await dbTables()
    clearFailure()
  } catch (e) {
    failure.value = describeError(e)
  }
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

function useTable(t: TableNode) {
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
      <button class="db__btn db__btn--primary" type="submit" :disabled="!!busy">
        {{ info ? '重新连接' : '连接' }}
      </button>
      <button v-if="info" class="db__btn" type="button" :disabled="!!busy" @click="disconnect">断开</button>
      <button class="db__btn" type="button" :disabled="!!busy" @click="loadTables">列出对象</button>
      <span v-if="busy" class="db__busy">{{ busy }}</span>
    </form>

    <!-- 连上了：显示"连到了哪儿" -->
    <p v-if="info" class="db__info">
      已连接 <strong>{{ info.database }}</strong> （用户 {{ info.user }} ·
      {{ info.serverEncoding }} · schema {{ info.currentSchema ?? '—' }}） ·
      <span :title="info.version">{{ versionShort }}</span>
    </p>

    <!-- 失败：原话 + 提示，两段都显示 -->
    <div v-if="failure" class="db__failure" role="alert">
      <p class="db__failure-msg">{{ failure.message }}</p>
      <p class="db__failure-hint">{{ failure.hint }}</p>
    </div>

    <div class="db__body">
      <!-- 对象树（本轮到表 / 视图） -->
      <aside class="db__tree">
        <p class="db__tree-title">对象（{{ tables.length }}）</p>
        <p v-if="!info" class="db__tree-empty">未连接</p>
        <p v-else-if="tables.length === 0" class="db__tree-empty">没有表 / 视图</p>
        <div v-for="group in grouped" :key="group.schema" class="db__schema">
          <p class="db__schema-name">{{ group.schema }}</p>
          <button
            v-for="t in group.items"
            :key="`${t.schema}.${t.name}`"
            class="db__table"
            type="button"
            :title="`${t.kind} · 点一下生成查询`"
            @click="useTable(t)"
          >
            {{ t.name }}<span class="db__kind">{{ t.kind === 'table' ? '' : t.kind }}</span>
          </button>
        </div>
      </aside>

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

        <div v-if="result && result.columns.length" class="db__grid-wrap">
          <table class="db__grid">
            <thead>
              <tr>
                <th v-for="c in result.columns" :key="c">{{ c }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(row, i) in result.rows" :key="i">
                <td v-for="(cell, j) in row" :key="j" :class="{ 'db__null': cell === null }">
                  {{ cell === null ? 'NULL' : cell }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-else-if="info && !failure" class="db__hint">
          从左侧点一张表生成查询，或直接写 SQL 后按「执行」。
        </p>
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

.db__grid th {
  position: sticky;
  top: 0;
  background: var(--ds-color-surface-raised);
}

.db__null {
  color: var(--ds-color-text-tertiary);
}
</style>
