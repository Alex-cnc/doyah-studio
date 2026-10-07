<script setup lang="ts">
// 连接弹层（Windows 侧）—— 对齐 macOS `App/Views/ConnectionSettingsSheet.swift` 的**呈现形态**：
// 连接设置走**弹层**，不在主区里内联铺开（派活单 T-20261007-009 §一 W-B）。
//
// 三条口径：
//   ① **逐条照搬**：表单字段（名称 / 引擎 / 主机 / 端口 / 库 / 用户 / 口令 / SSL / 记住口令）、
//      按钮（连接 · 断开 · 列出对象 · 保存到连接列表）与连接列表（分组 / 折叠 / 高亮 / 删除）
//      都是从 `views/DatabaseView.vue` 的主区**搬**过来的，字段集合与行为一字未改；
//   ② **状态不搬家**：IPC、表单状态、连接列表状态仍由 DatabaseView 持有（它是这一路数据的
//      唯一出处）—— 本件只**画**与**上报**（`v-model:*` 与事件），自己不发一条 IPC；
//   ③ **文案只走语言表**：界面里的中文文案一律 `t(...)`（漏译棘轮守着）。
//
// 弹层由**命令清单**驱动：`database.connect` / `database.newConnection` / `database.editConnection`
// 的 id → 档位映射在 `shell/connectionDialog.ts`（那份映射与命令清单对账，不另造一套）。

import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import ConnectionLabel from './ConnectionLabel.vue'
import { groupConnections } from './connectionDisplay'
import { connectionDialogTitleKey, looseNumber, type ConnectionDialogMode } from './connectionDialog'
import { t as translate, type UiLanguage } from '../i18n'
import type { ConnectParams, ServerInfo, SavedConnection } from '../ipc'

const props = defineProps<{
  /** 开没开（由 DatabaseView 按命令/右键菜单决定）。 */
  open: boolean
  /** 开哪一档（只影响标题；重置与聚焦由持有状态的 DatabaseView 做）。 */
  mode: ConnectionDialogMode
  language: UiLanguage
  /** 正在跑的动作（连接中… / 保存中…）；空串 = 没在跑。 */
  busy: string
  /** 名称留空时的派生名（占位符），口径与 DatabaseView 的 `effectiveName` 同一处。 */
  effectiveName: string
  /** 逐项校验的读数（FR-CONN-06）：**规则在领域层**，这里只显示。 */
  problems: Readonly<Record<string, string>>
  ready: boolean
  summary: string
  /** 保存过的连接（列表的唯一数据面）。 */
  connections: readonly SavedConnection[]
  /** 当前连着的服务端（高亮与「已连：」都要它）。 */
  info: ServerInfo | null
  /** 当前连着的那些保存连接 id（高亮口径与 DatabaseView 的 `isConnected` 同源）。 */
  connectedIds: readonly string[]
  /** 名称留空时的占位文案（本地化由调用方给，本件不写死中文）。 */
  untitled: string
  /** 从连接 URL 导入的回执（认不出的参数如实列出；文案由 DatabaseView 算好）。 */
  urlImportNote: string
  /** 已折叠的分组名（折叠状态由 DatabaseView 落 localStorage，本件只读）。 */
  collapsedGroups: readonly string[]
}>()

const emit = defineEmits<{
  (event: 'close'): void
  (event: 'connect'): void
  (event: 'disconnect'): void
  (event: 'load-objects'): void
  (event: 'save'): void
  (event: 'remove', connection: SavedConnection): void
  (event: 'select', connection: SavedConnection): void
  (event: 'import-url'): void
  (event: 'switch-type', kind: string): void
  (event: 'toggle-group', group: string | null): void
}>()

// ── 表单（**两向绑定给持有状态的 DatabaseView**；本件不改它的口径）──────────────
const form = defineModel<ConnectParams>('form', { required: true })
const name = defineModel<string>('name', { required: true })
const dbType = defineModel<string>('dbType', { required: true })
const password = defineModel<string>('password', { required: true })
const remember = defineModel<boolean>('remember', { required: true })
const urlImport = defineModel<string>('urlImport', { required: true })

/** 表单里除了 `ConnectParams` 的定点几格以外都走这里（**整体替换**，不是就地改对象）。 */
function patchForm(part: Record<string, unknown>): void {
  form.value = { ...form.value, ...part } as ConnectParams
}

const nameInput = ref<HTMLInputElement | null>(null)

/** 「编辑连接…」的落点：把光标送到连接名那一格（搬自 DatabaseView 原来的 `querySelector`）。 */
function focusName(): void {
  nameInput.value?.focus()
}

defineExpose({ focusName })

function tr(key: Parameters<typeof translate>[0], vars?: Record<string, string | number>): string {
  return translate(key, props.language, vars)
}

const title = computed(() => tr(connectionDialogTitleKey(props.mode)))

const groups = computed(() => groupConnections(props.connections))

function isCollapsed(group: string | null): boolean {
  return group !== null && props.collapsedGroups.includes(group)
}

/** 分组标题文案（未分组段用语言表里的文案，不在模板里写死中文）。 */
function groupTitle(group: string | null): string {
  return group ?? tr('db.connections.ungrouped')
}

/** 连接行的悬停提示（地址 + 一句「口令不在配置文件里」）。 */
function connectionTooltip(connection: SavedConnection): string {
  return tr('db.connections.rowTip', {
    user: connection.username,
    host: connection.host,
    port: connection.port,
    database: connection.database,
  })
}

/** 小字：`主机 · 库名`（图里就是这个形状）。 */
function connectionSubtitle(connection: SavedConnection): string {
  return `${connection.host} · ${connection.database}`
}

/** 当前连着的库名（折叠标题上显示一行「已连：xxx」）。 */
const connectedName = computed<string>(() => {
  if (!props.info) return ''
  const hit = props.connections.find((c) => props.connectedIds.includes(c.id))
  return hit ? hit.name : props.info.database
})

/** 是不是当前连着的（**id 由 DatabaseView 算好**：高亮口径只有一处，不在弹层里再判一次）。 */
function isConnectedRow(connection: SavedConnection): boolean {
  return props.connectedIds.includes(connection.id)
}

/** Esc 关弹层（只在开着时听；关掉的那一份不该抢别处的按键）。 */
function onKeydown(event: KeyboardEvent): void {
  if (props.open && event.key === 'Escape') emit('close')
}

onMounted(() => window.addEventListener('keydown', onKeydown))
onBeforeUnmount(() => window.removeEventListener('keydown', onKeydown))
</script>

<template>
  <div v-if="open" class="dlg" role="dialog" aria-modal="true" :aria-label="title">
    <!-- 底板：点空白 = 关（与 macOS 的 sheet 同姿势） -->
    <div class="dlg__backdrop" @click="emit('close')"></div>
    <div class="dlg__panel">
      <header class="dlg__head">
        <h2 class="dlg__title">{{ title }}</h2>
        <button class="dlg__close" type="button" :title="tr('db.connectionDialog.close')" @click="emit('close')">
          ✕
        </button>
      </header>

      <!-- 连接表单：字段与行为逐条照搬自 DatabaseView 主区（原 `form.db__bar`） -->
      <form class="db__bar" @submit.prevent="emit('connect')">
        <label class="db__field">
          <span>{{ tr('db.name') }}</span>
          <input v-model="name" ref="nameInput" type="text" spellcheck="false" :placeholder="effectiveName" />
        </label>
        <label class="db__field db__field--narrow" :title="tr('db.type.defaults')">
          <span>{{ tr('db.type') }}</span>
          <select
            :value="dbType"
            class="db__select"
            :disabled="!!busy"
            @change="emit('switch-type', ($event.target as HTMLSelectElement).value)"
          >
            <option value="postgresql">PostgreSQL</option>
            <option value="mysql">MySQL</option>
            <option value="gbase8a">GBase 8a</option>
          </select>
        </label>
        <label class="db__field">
          <span>{{ tr('db.host') }}</span>
          <input
            :value="form.host"
            type="text"
            spellcheck="false"
            @input="patchForm({ host: ($event.target as HTMLInputElement).value })"
          />
        </label>
        <label class="db__field db__field--narrow">
          <span>{{ tr('db.port') }}</span>
          <input
            :value="form.port"
            type="number"
            min="1"
            max="65535"
            @input="patchForm({ port: looseNumber(($event.target as HTMLInputElement).value) })"
          />
        </label>
        <label class="db__field">
          <span>{{ tr('db.database') }}</span>
          <input
            :value="form.database"
            type="text"
            spellcheck="false"
            @input="patchForm({ database: ($event.target as HTMLInputElement).value })"
          />
        </label>
        <label class="db__field">
          <span>{{ tr('db.user') }}</span>
          <input
            :value="form.user"
            type="text"
            spellcheck="false"
            @input="patchForm({ user: ($event.target as HTMLInputElement).value })"
          />
        </label>
        <label class="db__field">
          <span>{{ tr('db.password') }}</span>
          <input v-model="password" type="password" autocomplete="off" :placeholder="tr('db.password.placeholder')" />
        </label>
        <label class="db__field db__field--narrow">
          <span>{{ tr('db.ssl') }}</span>
          <select
            :value="form.sslMode"
            class="db__select"
            :disabled="!!busy"
            @change="patchForm({ sslMode: ($event.target as HTMLSelectElement).value })"
          >
            <option value="disable">disable</option>
            <option value="allow">allow</option>
            <option value="prefer">prefer</option>
            <option value="require">require</option>
            <option value="verify-ca">verify-ca</option>
            <option value="verify-full">verify-full</option>
          </select>
        </label>
        <label class="db__field db__field--check" :title="tr('db.remember.tip')">
          <span>{{ tr('db.remember') }}</span>
          <input v-model="remember" type="checkbox" />
        </label>
        <button class="db__btn db__btn--primary" type="submit" :disabled="!!busy || !ready">
          {{ info ? tr('db.reconnect') : tr('db.connect') }}
        </button>
        <button v-if="info" class="db__btn" type="button" :disabled="!!busy" @click="emit('disconnect')">
          {{ tr('db.disconnect') }}
        </button>
        <button class="db__btn" type="button" :disabled="!!busy" @click="emit('load-objects')">
          {{ tr('db.loadObjects') }}
        </button>
        <button class="db__btn" type="button" :disabled="!!busy || !ready" @click="emit('save')">
          {{ tr('db.saveToConnections') }}
        </button>
        <span v-if="busy" class="db__busy">{{ busy }}</span>
      </form>

      <!-- 逐项校验（FR-CONN-06）：**哪一项不合法由领域层说了算**，界面只显示、并按它禁用按钮 -->
      <p v-if="!ready" class="db__failure-hint">{{ summary }}</p>

      <!-- 从连接 URL 导入（FR-CONN-19）：口令可带，但只填进口令框、绝不进配置 -->
      <div class="db__writeback">
        <label class="db__field">
          <span>{{ tr('db.urlImport') }}</span>
          <input
            v-model="urlImport"
            class="db__cell-input db__io-path"
            type="text"
            spellcheck="false"
            :placeholder="tr('db.urlImport.placeholder')"
            :aria-label="tr('db.urlImport')"
          />
        </label>
        <button class="db__btn" type="button" @click="emit('import-url')">{{ tr('db.urlImport.button') }}</button>
        <span v-if="urlImportNote" class="db__note">{{ urlImportNote }}</span>
      </div>

      <!-- 连接列表（FR-CONN-12 / -15）：分组 + 折叠 + 高亮当前，**搬自主区左栏** -->
      <details class="db__conn-fold" open>
        <summary class="db__tree-title">
          {{ tr('db.connections') }}（{{ connections.length }}）<span class="db__kind">{{ tr('db.connectedAs') }}{{ connectedName || tr('db.none') }}</span>
        </summary>
        <p v-if="connections.length === 0" class="db__tree-empty">
          {{ tr('db.connections.empty') }}
        </p>
        <template v-else>
          <div v-for="group in groups" :key="group.group ?? '::ungrouped'" class="db__conn-group">
            <button
              v-if="group.group !== null"
              class="db__group-toggle"
              type="button"
              :aria-expanded="isCollapsed(group.group) ? 'false' : 'true'"
              :title="tr('db.connections.groupToggle', { name: group.group })"
              @click="emit('toggle-group', group.group)"
            >
              <span class="db__chevron">{{ isCollapsed(group.group) ? '▸' : '▾' }}</span>
              {{ groupTitle(group.group) }}
            </button>
            <p v-else class="db__group-title">{{ groupTitle(group.group) }}</p>
            <template v-if="!isCollapsed(group.group)">
              <div
                v-for="c in group.items"
                :key="c.id"
                class="db__conn"
                :class="{ 'db__conn--active': isConnectedRow(c) }"
              >
                <button
                  class="db__conn-main"
                  type="button"
                  :title="connectionTooltip(c)"
                  @click="emit('select', c)"
                >
                  <span class="db__conn-name">
                    <!-- 显示名 + 环境标签 + 色条：**与查询上下文栏同一个共用件**（FR-CONN-14 / -16） -->
                    <ConnectionLabel
                      :connection="c"
                      :untitled="untitled"
                      :language="language"
                    />
                    <span v-if="c.isReadOnly" class="db__kind">只读</span>
                  </span>
                  <span class="db__conn-sub">{{ connectionSubtitle(c) }}</span>
                </button>
                <button
                  class="db__conn-del"
                  type="button"
                  title="删除这条连接（并清掉它的凭据）"
                  @click="emit('remove', c)"
                >
                  ✕
                </button>
              </div>
            </template>
          </div>
        </template>
      </details>
    </div>
  </div>
</template>

<style scoped>
/* 弹层底板（对齐 macOS sheet 的呈现：面板居中、背景压暗、点空白关闭） */
.dlg {
  position: fixed;
  inset: 0;
  z-index: 40;
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding: var(--ds-spacing-l);
}

.dlg__backdrop {
  position: absolute;
  inset: 0;
  background: var(--ds-color-surface-window);
  opacity: 0.6;
}

.dlg__panel {
  position: relative;
  z-index: 1;
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-s);
  width: min(720px, 100%);
  max-height: 100%;
  overflow: auto;
  padding: var(--ds-spacing-m);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-body-size);
}

.dlg__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--ds-spacing-s);
}

.dlg__title {
  margin: 0;
  font-size: var(--ds-font-title-size);
  color: var(--ds-color-text-primary);
}

.dlg__close {
  background: transparent;
  color: var(--ds-color-text-tertiary);
  border: 0;
  cursor: pointer;
}

.dlg__close:hover {
  color: var(--ds-color-text-primary);
}

/* ── 连接面（表单 / 校验回执 / URL 导入 / 连接列表）──────────────────────────────
   这一整段是从 `views/DatabaseView.vue` 的同类规则**逐条搬**过来的（同一套令牌、
   同一套取值）：弹层的 scoped 样式不继承主区的 data-v 属性，所以规则必须随件走。 */

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

.db__failure-hint {
  margin: var(--ds-spacing-xs) 0 0;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.db__writeback {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--ds-spacing-s);
  margin-bottom: var(--ds-spacing-xs);
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

.db__conn-fold {
  flex: 0 0 auto;
}

.db__conn-fold > summary {
  cursor: pointer;
}

.db__tree-title {
  margin: 0 0 var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.db__tree-empty {
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
}

.db__kind {
  margin-left: var(--ds-spacing-xs);
  color: var(--ds-color-text-tertiary);
}

.db__group-title {
  margin: var(--ds-spacing-s) 0 var(--ds-spacing-hair);
  padding: 0 var(--ds-spacing-xs);
  color: var(--ds-color-text-tertiary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
}

/* 可折叠的分组标题（命名分组；未分组那一段仍是上面那个静态标题） */
.db__group-toggle {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-hair);
  width: 100%;
  margin: var(--ds-spacing-s) 0 var(--ds-spacing-hair);
  padding: 0 var(--ds-spacing-xs);
  border: 0;
  background: transparent;
  color: var(--ds-color-text-tertiary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  text-align: left;
  cursor: pointer;
}

.db__group-toggle:hover {
  color: var(--ds-color-text-primary);
}

.db__conn {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-xs);
}

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
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-xs);
  min-width: 0;
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
  background: transparent;
  color: var(--ds-color-text-tertiary);
  border: 0;
  cursor: pointer;
  opacity: 0;
  flex: none;
}

.db__conn-del:hover {
  color: var(--ds-color-status-danger);
}

.db__conn:hover .db__conn-del {
  opacity: 1;
}

.db__chevron {
  width: 1em;
  flex: 0 0 auto;
  color: var(--ds-color-text-tertiary);
}

/* 连接 URL 输入框（原样式在 DatabaseView 的 `.db__cell-input` / `.db__io-path`） */
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

.db__io-path {
  min-width: 320px;
}
</style>
