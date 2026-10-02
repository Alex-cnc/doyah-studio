<script setup lang="ts">
// 工作区视图（alpha 2.0 骨架）—— 打开文件夹 → 左侧 Explorer → 页签 → 只读编辑面 → Home 页
//
// 分工（别把规则写两遍）：
//   · **Rust 侧**（`Db/src/workspace.rs` + `src-tauri/src/fs.rs`）管领域规则：脏标记怎么算、
//     路径安不安全、忽略名单、排序；本组件**不自己判路径安全**（那会让"安全关"有两份实现）。
//   · **纯逻辑层**（`workspace/logic.ts`）管显示串与树的展开/键盘走位（有 13 例单测）。
//   · 本组件只管状态与排版。

import { computed, onMounted, ref } from 'vue'
import {
  workspaceClosed,
  workspaceHistory,
  workspaceListDirectory,
  workspaceOpened,
  workspaceReadFile,
  type DbFailure,
  type FileContent,
  type FsEntry,
  type WorkspaceHistory,
} from '../ipc'
import { entryGlyph, flattenTree, indentPx, neighbouringRow, tabLabel, toggleExpanded, workspaceDisplayName } from '../workspace/logic'

/** 本版只读：编辑面显示内容，改与存归 2.1 / 2.2 段（不假装能改）。 */
interface OpenTab {
  id: string
  title: string
  relativePath: string | null
  content: string
  languageKey: string
  saved: string
}

const HOME_ID = 'home'

const root = ref('')
const rootDraft = ref('')
const showHidden = ref(false)
const children = ref<Map<string, FsEntry[]>>(new Map())
const expanded = ref<Set<string>>(new Set())
const tabs = ref<OpenTab[]>([])
const selected = ref<string | null>(null)
const selectedTabId = ref<string>(HOME_ID)
const failure = ref<DbFailure | null>(null)
const busy = ref('')

// 会话恢复（2.0）：上次打开的根 + 最近打开两份清单。
// **不自动打开**上次那个文件夹：路径可能已被移动 / 删除，自动打开会每次启动弹一次错；
// 改成"预填 + 一句话告诉你是上次那个"，由人点一下「打开」（想打开哪个由人定）。
const history = ref<WorkspaceHistory | null>(null)
const historyWarning = ref('')

onMounted(async () => {
  try {
    const payload = await workspaceHistory()
    history.value = payload.history
    historyWarning.value = payload.warning ?? ''
    if (payload.history.currentRoot) {
      rootDraft.value = payload.history.currentRoot
    }
  } catch (e) {
    failure.value = describeError(e)
  }
})

/** 最近打开的工作区（点一下填进输入框）。 */
const recentWorkspaces = computed(() => history.value?.workspaces ?? [])

function useRecent(path: string) {
  rootDraft.value = path
}

const rootEntries = computed(() => children.value.get('') ?? [])

const rows = computed(() =>
  flattenTree(rootEntries.value, expanded.value, (path) => children.value.get(path)),
)

const activeTab = computed<OpenTab | null>(
  () => tabs.value.find((t) => t.id === selectedTabId.value) ?? null,
)

/** 层标题：`工作区 · <名字>`；没打开就写"未打开工作区" */
const headerText = computed(() => (root.value ? `工作区 · ${workspaceDisplayName(root.value)}` : '未打开工作区（贴一个文件夹路径，按「打开」）'))

function describeError(e: unknown): DbFailure {
  if (e && typeof e === 'object' && 'message' in e && 'hint' in e) return e as DbFailure
  return { message: e instanceof Error ? e.message : String(e), hint: '把这条原话与路径一起核对。' }
}

function homeTab(): OpenTab {
  return { id: HOME_ID, title: '首页', relativePath: null, content: '', languageKey: 'lang.plainText', saved: '' }
}

async function loadLevel(relativePath: string) {
  const entries = await workspaceListDirectory(root.value, relativePath || undefined, showHidden.value)
  const next = new Map(children.value)
  next.set(relativePath, entries)
  children.value = next
}

async function openWorkspace() {
  const candidate = rootDraft.value.trim()
  if (!candidate) return
  busy.value = '打开中…'
  failure.value = null
  try {
    root.value = candidate
    children.value = new Map()
    expanded.value = new Set()
    tabs.value = [homeTab()]
    selectedTabId.value = HOME_ID
    selected.value = null
    await loadLevel('')
    // 记一次「打开了这个工作区」：既进「最近打开」，也记为当前根（下次启动预填它）
    const stamp = new Date().toISOString()
    const recorded = await workspaceOpened(candidate, stamp)
    history.value = recorded.history
  } catch (e) {
    failure.value = describeError(e)
    root.value = ''
    children.value = new Map()
  } finally {
    busy.value = ''
  }
}

async function onRowClick(entry: FsEntry) {
  selected.value = entry.relativePath
  failure.value = null
  try {
    if (entry.isExpandable) {
      const willExpand = !expanded.value.has(entry.relativePath)
      expanded.value = toggleExpanded(expanded.value, entry)
      // **按需展开**：第一次展开才去读盘（打开大工程不会卡）
      if (willExpand && !children.value.has(entry.relativePath)) {
        await loadLevel(entry.relativePath)
      }
    } else if (entry.kind === 'file') {
      await openFile(entry)
    }
  } catch (e) {
    failure.value = describeError(e)
  }
}

async function openFile(entry: FsEntry) {
  // **同一路径只开一个页签**（领域规则）：已开着就切过去，不重复开
  const existing = tabs.value.find((t) => t.relativePath === entry.relativePath)
  if (existing) {
    selectedTabId.value = existing.id
    return
  }
  busy.value = '读取中…'
  try {
    const file: FileContent = await workspaceReadFile(root.value, entry.relativePath)
    const tab: OpenTab = {
      id: `tab-${tabs.value.length}-${file.relativePath}`,
      title: entry.name,
      relativePath: file.relativePath,
      content: file.content,
      languageKey: file.languageKey,
      saved: file.content,
    }
    tabs.value = [...tabs.value, tab]
    selectedTabId.value = tab.id
  } finally {
    busy.value = ''
  }
}

function closeTab(id: string) {
  const index = tabs.value.findIndex((t) => t.id === id)
  if (index < 0) return
  const isHome = tabs.value[index].relativePath === null
  if (isHome) return // Home 关不掉（领域规则）
  const remaining = tabs.value.filter((t) => t.id !== id)
  tabs.value = remaining
  if (selectedTabId.value === id) {
    // 选中项关闭后**优先落到右边**那个（与 Rust 侧 selection_after_closing 同口径）
    const fallback = remaining[Math.min(index, remaining.length - 1)] ?? remaining[remaining.length - 1]
    selectedTabId.value = fallback ? fallback.id : HOME_ID
  }
}

/** 键盘上下在树里走位（**到边界停住**，不循环 —— 见 logic.test.ts） */
/** 关掉当前工作区：清当前根，**保留**最近打开里的记录（这条区分是领域层定的） */
async function closeWorkspace() {
  try {
    const recorded = await workspaceClosed()
    history.value = recorded.history
  } catch (e) {
    failure.value = describeError(e)
  }
  root.value = ''
  children.value = new Map()
  expanded.value = new Set()
  tabs.value = [homeTab()]
  selectedTabId.value = HOME_ID
  selected.value = null
}

function onTreeKeydown(event: KeyboardEvent) {
  if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') return
  event.preventDefault()
  const next = neighbouringRow(rows.value, selected.value, event.key === 'ArrowDown' ? 1 : -1)
  selected.value = next
}
</script>

<template>
  <section class="ws">
    <!-- 打开工作区 -->
    <form class="ws__bar" @submit.prevent="openWorkspace">
      <label class="ws__field">
        <span>文件夹</span>
        <input v-model="rootDraft" type="text" spellcheck="false" placeholder="例如 D:\AIProjects\DoyahStudio" />
      </label>
      <label class="ws__check" title="只管点开头的隐藏项；忽略名单（node_modules / target / .git …）是另一回事">
        <input v-model="showHidden" type="checkbox" @change="root && loadLevel('')" />
        显示隐藏项
      </label>
      <button class="ws__btn ws__btn--primary" type="submit" :disabled="!!busy">打开</button>
      <button v-if="root" class="ws__btn" type="button" :disabled="!!busy" @click="closeWorkspace">关闭工作区</button>
      <span v-if="busy" class="ws__note">{{ busy }}</span>
      <span class="ws__note">{{ headerText }}</span>
    </form>

    <p v-if="historyWarning" class="ws__note ws__note--warn">{{ historyWarning }}</p>

    <div v-if="failure" class="ws__failure" role="alert">
      <p class="ws__failure-msg">{{ failure.message }}</p>
      <p class="ws__failure-hint">{{ failure.hint }}</p>
    </div>

    <div class="ws__body">
      <!-- Explorer：按需展开的树 -->
      <aside class="ws__tree" tabindex="0" @keydown="onTreeKeydown">
        <p class="ws__tree-title">资源管理器（{{ rows.length }}）</p>
        <p v-if="!root" class="ws__empty">未打开工作区</p>
        <p v-else-if="rows.length === 0" class="ws__empty">这一层没有可列出的条目</p>
        <button
          v-for="row in rows"
          :key="row.entry.relativePath"
          class="ws__row"
          :class="{ 'ws__row--active': selected === row.entry.relativePath }"
          type="button"
          :style="{ paddingLeft: `${indentPx(row.depth) + 4}px` }"
          :title="`${row.entry.kind} · ${row.entry.relativePath}`"
          @click="onRowClick(row.entry)"
        >
          <span class="ws__glyph">{{ row.entry.kind === 'directory' ? (row.expanded ? '▾' : entryGlyph(row.entry)) : entryGlyph(row.entry) }}</span>
          {{ row.entry.name }}
          <span v-if="row.entry.kind === 'symlink'" class="ws__tag">链接（不跟随）</span>
        </button>
      </aside>

      <!-- 页签 + 编辑面 -->
      <div class="ws__main">
        <div class="ws__tabs" role="tablist">
          <div v-for="tab in tabs" :key="tab.id" class="ws__tab" :class="{ 'ws__tab--active': tab.id === selectedTabId }">
            <button class="ws__tab-name" type="button" role="tab" :aria-selected="tab.id === selectedTabId" @click="selectedTabId = tab.id">
              {{ tabLabel(tab.title, tab.content !== tab.saved) }}
            </button>
            <button v-if="tab.relativePath !== null" class="ws__tab-close" type="button" title="关闭页签" @click="closeTab(tab.id)">✕</button>
          </div>
        </div>

        <div class="ws__editor">
          <template v-if="activeTab && activeTab.relativePath === null">
            <h2 class="ws__home-title">工作区</h2>
            <p class="ws__home-line">左侧「资源管理器」里点一个**文件**即可在这里只读打开；点**目录**展开一层。</p>
            <p class="ws__home-line">键盘 ↑ / ↓ 可在树里走位（到边界停住，不循环）。</p>
            <p class="ws__home-line">本版**只读**：编辑与保存归 2.1 / 2.2 段（不假装能改）。</p>
            <template v-if="recentWorkspaces.length">
              <p class="ws__home-line">最近打开的工作区（点一下填进上面的输入框）：</p>
              <div class="ws__recent">
                <button
                  v-for="entry in recentWorkspaces"
                  :key="entry.path"
                  class="ws__btn"
                  type="button"
                  :title="entry.path"
                  @click="useRecent(entry.path)"
                >
                  {{ entry.path }}
                </button>
              </div>
            </template>
          </template>
          <template v-else-if="activeTab">
            <p class="ws__editor-meta">
              {{ activeTab.relativePath }} · {{ activeTab.languageKey }}
              <span class="ws__tag">只读（本版）</span>
            </p>
            <pre class="ws__code">{{ activeTab.content }}</pre>
          </template>
          <p v-else class="ws__empty">没有打开的页签</p>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.ws {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
}

.ws__bar {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  gap: var(--ds-spacing-s);
  padding: var(--ds-spacing-s) var(--ds-spacing-m);
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
  background: var(--ds-color-surface-panel);
}

.ws__field {
  display: flex;
  flex-direction: column;
  /* 最小档间距：走令牌（棘轮连注释里的字面量也计——这条注释原先写了具体像素值，被判红过一次） */
  gap: var(--ds-spacing-hair);
  font-size: var(--ds-font-caption-size);
  color: var(--ds-color-text-secondary);
}

.ws__field input {
  min-width: 360px;
  height: var(--ds-metric-control-height);
  padding: 0 var(--ds-spacing-s);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
}

.ws__check {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-xs);
  padding-bottom: var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.ws__btn {
  height: var(--ds-metric-control-height);
  padding: 0 var(--ds-spacing-m);
  background: var(--ds-color-surface-raised);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  cursor: pointer;
}

.ws__btn--primary {
  background: var(--ds-color-accent-accent);
  color: var(--ds-color-surface-content);
  border-color: transparent;
}

.ws__note,
.ws__empty {
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

/* 历史文件读不出来时的提示：**说得出来**，但不挡着开工作区 */
.ws__note--warn {
  margin: 0;
  padding: var(--ds-spacing-xs) var(--ds-spacing-m);
  color: var(--ds-color-status-warning);
}

.ws__recent {
  display: flex;
  flex-wrap: wrap;
  gap: var(--ds-spacing-xs);
  margin-top: var(--ds-spacing-xs);
}

.ws__failure {
  margin: var(--ds-spacing-s) var(--ds-spacing-m) 0;
  padding: var(--ds-spacing-s);
  border: var(--ds-metric-hairline) solid var(--ds-color-status-danger);
  border-radius: var(--ds-radius-control);
}

.ws__failure-msg {
  margin: 0;
  color: var(--ds-color-status-danger);
}

.ws__failure-hint {
  margin: var(--ds-spacing-xs) 0 0;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.ws__body {
  display: flex;
  flex: 1;
  min-height: 0;
}

.ws__tree {
  width: 300px;
  overflow: auto;
  padding: var(--ds-spacing-s);
  border-right: var(--ds-metric-hairline) solid var(--ds-hairline);
  background: var(--ds-color-surface-sidebar);
  outline: none;
}

.ws__tree-title {
  margin: 0 0 var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.ws__row {
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

.ws__row:hover,
.ws__row--active {
  background: var(--ds-color-surface-panel);
}

.ws__glyph {
  display: inline-block;
  width: 12px;
  color: var(--ds-color-text-tertiary);
}

.ws__tag {
  margin-left: var(--ds-spacing-xs);
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
}

.ws__main {
  display: flex;
  flex: 1;
  min-width: 0;
  flex-direction: column;
}

.ws__tabs {
  display: flex;
  gap: var(--ds-spacing-hair);
  padding: 0 var(--ds-spacing-s);
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
  background: var(--ds-color-surface-panel);
}

.ws__tab {
  display: flex;
  align-items: center;
  background: transparent;
  border: var(--ds-metric-hairline) solid transparent;
  border-bottom: 0;
  border-radius: var(--ds-radius-control) var(--ds-radius-control) 0 0;
}

.ws__tab--active {
  background: var(--ds-color-surface-content);
  border-color: var(--ds-hairline);
}

.ws__tab-name {
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  background: transparent;
  color: var(--ds-color-text-primary);
  border: 0;
  font-size: var(--ds-font-caption-size);
  cursor: pointer;
}

.ws__tab-close {
  padding: 0 var(--ds-spacing-xs);
  background: transparent;
  color: var(--ds-color-text-tertiary);
  border: 0;
  cursor: pointer;
}

.ws__tab-close:hover {
  color: var(--ds-color-status-danger);
}

.ws__editor {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: var(--ds-spacing-m);
}

.ws__editor-meta {
  margin: 0 0 var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.ws__code {
  margin: 0;
  padding: var(--ds-spacing-s);
  background: var(--ds-color-surface-content);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  white-space: pre-wrap;
}

.ws__home-title {
  margin: 0 0 var(--ds-spacing-s);
  font-size: var(--ds-font-title-size);
}

.ws__home-line {
  margin: 0 0 var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
}
</style>
