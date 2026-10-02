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
  workspaceCreate,
  workspaceDelete,
  workspaceDeletionSummary,
  workspaceHistory,
  workspaceListDirectory,
  workspaceMove,
  workspaceOpened,
  workspaceOpenTabs,
  workspaceReadFile,
  workspaceReveal,
  workspaceRename,
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
    // 会话恢复：把上次开着的页签**按路径重读**（盘上没有的跳过并报出来）
    await restoreOpenTabs(recorded.history.openTabs ?? [])
    await rememberOpenTabs()
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
    await rememberOpenTabs()
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
  void rememberOpenTabs()
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

/** 把"当前开着的页签"记下来（只记路径；内容以盘上为准） */
async function rememberOpenTabs() {
  if (!root.value) return
  const paths = tabs.value.map((t) => t.relativePath).filter((p): p is string => p !== null)
  try {
    const recorded = await workspaceOpenTabs(root.value, paths)
    history.value = recorded.history
  } catch {
    // 记不住不影响用（下次少恢复几个页签而已），不打断当前操作
  }
}

/** 恢复上次开着的页签：**按路径重新读盘**；盘上没有的**跳过并报出来**（不假装还在） */
async function restoreOpenTabs(paths: readonly string[]) {
  const missing: string[] = []
  for (const path of paths) {
    try {
      const file = await workspaceReadFile(root.value, path)
      const tab: OpenTab = {
        id: `tab-restored-${path}`,
        title: path.split('/').pop() ?? path,
        relativePath: file.relativePath,
        content: file.content,
        languageKey: file.languageKey,
        saved: file.content,
      }
      tabs.value = [...tabs.value, tab]
    } catch {
      missing.push(path)
    }
  }
  if (missing.length) {
    failure.value = {
      message: `有 ${missing.length} 个上次开着的文件没恢复：${missing.join('、')}`,
      hint: '它们可能被移动或删除了；**没有假装还在**。修好后重新点开即可。',
    }
  }
}

/** 某个条目是不是正在改名 / 正在被确认删除（行内状态，不弹系统对话框） */
const renaming = ref<string | null>(null)
const renameDraft = ref('')
const confirming = ref<{ entry: FsEntry; items: number; truncated: boolean } | null>(null)
/** 拖动中的条目（拖拽移动用） */
const dragging = ref<FsEntry | null>(null)

/** 新建：文件 / 文件夹（名字由 Rust 侧取「不撞名」的那个） */
async function createIn(parentRelative: string, directory: boolean) {
  if (!root.value) return
  failure.value = null
  try {
    const created = await workspaceCreate(root.value, parentRelative, directory ? '新建文件夹' : '未命名', {
      directory,
    })
    // 建完刷新这一层（新建不一定在当前展开的那层：见调用点传的 parent）
    await loadLevel(parentRelative)
    if (parentRelative && !expanded.value.has(parentRelative)) {
      expanded.value = new Set([...expanded.value, parentRelative])
    }
    selected.value = created.relativePath
  } catch (e) {
    failure.value = describeError(e)
  }
}

/** 在资源管理器 / 终端打开（`used` 那一栏告诉人实际用的是哪个程序） */
async function reveal(entry: FsEntry, terminal: boolean) {
  if (!root.value) return
  failure.value = null
  try {
    const plan = await workspaceReveal(root.value, entry.relativePath, terminal)
    revealed.value = terminal ? `已在 ${plan.program} 打开` : `已在资源管理器里选中（${entry.name}）`
    setTimeout(() => (revealed.value = ''), 2500)
  } catch (e) {
    failure.value = describeError(e)
  }
}

/** 打开动作的回执（**说清用的是哪个程序**） */
const revealed = ref('')

/** 某个条目的父目录相对路径（新建同级用）。 */
function parentOf(relativePath: string): string {
  const slash = relativePath.lastIndexOf('/')
  return slash < 0 ? '' : relativePath.slice(0, slash)
}

function beginRename(entry: FsEntry) {
  renaming.value = entry.relativePath
  renameDraft.value = entry.name
}

async function commitRename(entry: FsEntry) {
  if (!root.value) return
  const next = renameDraft.value
  renaming.value = null
  // 名字没变就不打扰后端（同名不算失败这条规则在 Rust 侧也成立，这里只是省一次往返）
  if (next === entry.name) return
  failure.value = null
  try {
    await workspaceRename(root.value, entry.relativePath, next)
    await refreshAfterMutation(entry.relativePath)
  } catch (e) {
    failure.value = describeError(e)
    renaming.value = entry.relativePath
  }
}

/** 点「删除」：**先取读数再让人确认**（删非空文件夹必须二次确认） */
async function askDelete(entry: FsEntry) {
  if (!root.value) return
  failure.value = null
  try {
    const summary = await workspaceDeletionSummary(root.value, entry.relativePath)
    confirming.value = { entry, items: summary.items, truncated: summary.truncated }
  } catch (e) {
    failure.value = describeError(e)
  }
}

async function confirmDelete() {
  const pending = confirming.value
  confirming.value = null
  if (!pending || !root.value) return
  try {
    await workspaceDelete(root.value, pending.entry.relativePath)
    await refreshAfterMutation(pending.entry.relativePath)
  } catch (e) {
    failure.value = describeError(e)
  }
}

/** 拖拽落下：移进目标目录（**自吞会被 Rust 侧拒绝**，这里只如实显示结果） */
async function onDrop(entry: FsEntry) {
  const from = dragging.value
  dragging.value = null
  if (!from || !root.value || from.relativePath === entry.relativePath) return
  failure.value = null
  try {
    await workspaceMove(root.value, from.relativePath, entry.relativePath)
    await refreshAfterMutation(from.relativePath)
  } catch (e) {
    failure.value = describeError(e)
  }
}

/** 改完之后把受影响的那两层重新读一遍（不整树重扫：大工程会卡） */
async function refreshAfterMutation(movedRelative: string) {
  const parent = movedRelative.includes('/')
    ? movedRelative.slice(0, movedRelative.lastIndexOf('/'))
    : ''
  await loadLevel(parent)
  for (const path of [...expanded.value]) {
    if (children.value.has(path)) await loadLevel(path)
  }
  // 被改的那个页签内容不再可信：关掉它（重新点开就是盘上的最新内容）
  const affected = tabs.value.find((t) => t.relativePath === movedRelative)
  if (affected) closeTab(affected.id)
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
      <template v-if="root">
        <button class="ws__btn" type="button" @click="createIn('', false)">新建文件</button>
        <button class="ws__btn" type="button" @click="createIn('', true)">新建文件夹</button>
      </template>
      <span v-if="busy" class="ws__note">{{ busy }}</span>
      <span v-if="revealed" class="ws__note">{{ revealed }}</span>
      <span class="ws__note">{{ headerText }}</span>
    </form>

    <p v-if="historyWarning" class="ws__note ws__note--warn">{{ historyWarning }}</p>

    <div v-if="failure" class="ws__failure" role="alert">
      <p class="ws__failure-msg">{{ failure.message }}</p>
      <p class="ws__failure-hint">{{ failure.hint }}</p>
    </div>

    <!-- 删除确认：**先给读数**再动手（删非空文件夹必须二次确认） -->
    <div v-if="confirming" class="ws__confirm" role="alertdialog">
      <p class="ws__confirm-msg">
        删除「{{ confirming.entry.name }}」？<template v-if="confirming.entry.kind === 'directory'">
          这一项共 <strong>{{ confirming.items }}</strong
          ><template v-if="confirming.truncated"> 项以上</template> 项</template
        >。会**移到回收站**（可撤销）。
      </p>
      <button class="ws__btn ws__btn--primary" type="button" @click="confirmDelete">移到回收站</button>
      <button class="ws__btn" type="button" @click="confirming = null">取消</button>
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
          :draggable="row.entry.kind !== 'symlink'"
          @click="onRowClick(row.entry)"
          @dragstart="dragging = row.entry"
          @dragover.prevent
          @drop="row.entry.isExpandable && onDrop(row.entry)"
        >
          <span class="ws__glyph">{{ row.entry.kind === 'directory' ? (row.expanded ? '▾' : entryGlyph(row.entry)) : entryGlyph(row.entry) }}</span>
          <template v-if="renaming === row.entry.relativePath">
            <input
              v-model="renameDraft"
              class="ws__rename"
              type="text"
              @click.stop
              @keydown.enter.prevent="commitRename(row.entry)"
              @keydown.esc="renaming = null"
            />
          </template>
          <template v-else>
            {{ row.entry.name }}
            <span v-if="row.entry.kind === 'symlink'" class="ws__tag">链接（不跟随）</span>
          </template>
          <!-- 行内动作：图标必带提示（title），删非空文件夹要二次确认 -->
          <span class="ws__actions" @click.stop>
            <button
              v-if="row.entry.kind === 'file'"
              class="ws__act"
              type="button"
              title="重命名（回车确认 / Esc 取消）"
              @click="beginRename(row.entry)"
            >
              ✎
            </button>
            <button
              class="ws__act"
              type="button"
              title="新建同级文件夹"
              @click="createIn(parentOf(row.entry.relativePath), false)"
            >
              ＋
            </button>
            <button class="ws__act" type="button" title="在资源管理器里显示" @click="reveal(row.entry, false)">
              📁
            </button>
            <button class="ws__act" type="button" title="在终端打开（起始目录 = 所在文件夹）" @click="reveal(row.entry, true)">
              ▶
            </button>
            <button class="ws__act" type="button" title="删除（走回收站，可撤销）" @click="askDelete(row.entry)">
              🗑
            </button>
          </span>
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

/* 删除确认条：读数 + 两个按钮（不做系统对话框） */
.ws__confirm {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--ds-spacing-s);
  margin: var(--ds-spacing-s) var(--ds-spacing-m) 0;
  padding: var(--ds-spacing-s);
  background: var(--ds-color-surface-panel);
  border: var(--ds-metric-hairline) solid var(--ds-color-status-danger);
  border-radius: var(--ds-radius-control);
}

.ws__confirm-msg {
  margin: 0;
  color: var(--ds-color-text-primary);
  font-size: var(--ds-font-caption-size);
}

/* 行内动作：平时淡、悬停才显眼（图标必带提示） */
.ws__actions {
  float: right;
  display: none;
  gap: var(--ds-spacing-hair);
}

.ws__row:hover .ws__actions,
.ws__row--active .ws__actions {
  display: inline-flex;
}

.ws__act {
  padding: 0 var(--ds-spacing-xs);
  background: transparent;
  color: var(--ds-color-text-secondary);
  border: 0;
  cursor: pointer;
}

.ws__act:hover {
  color: var(--ds-color-accent-accent);
}

.ws__rename {
  width: 60%;
  height: var(--ds-metric-control-height);
  padding: 0 var(--ds-spacing-xs);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-color-accent-accent);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
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
