<script setup lang="ts">
// 工作区视图（alpha 2.0 骨架）—— 打开文件夹 → 左侧 Explorer → 页签 → 只读编辑面 → Home 页
//
// 分工（别把规则写两遍）：
//   · **Rust 侧**（`Db/src/workspace.rs` + `src-tauri/src/fs.rs`）管领域规则：脏标记怎么算、
//     路径安不安全、忽略名单、排序；本组件**不自己判路径安全**（那会让"安全关"有两份实现）。
//   · **纯逻辑层**（`workspace/logic.ts`）管显示串与树的展开/键盘走位（有 13 例单测）。
//   · 本组件只管状态与排版。

import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
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
  workspaceCheckStaleness,
  workspaceFileSnapshot,
  workspaceReadFile,
  workspaceReadLines,
  workspaceClampLine,
  workspaceDecideOpen,
  workspaceMarkdown,
  workspaceReadImage,
  workspaceReplaceApply,
  workspaceFormatContent,
  workspaceFormatTools,
  workspaceReplacePreview,
  workspaceSave,
  workspaceRecordCursor,
  workspaceSearch,
  workspaceReadSpans,
  workspaceReveal,
  workspaceRename,
  type CodeSpan,
  type DbFailure,
  type FileContent,
  type FileLines,
  type FsEntry,
  type CursorAnchor,
  type LoadedFile,
  type MdBlock,
  type MdDocument,
  type MdSpan,
  type OpenDecision,
  type FormatToolProbe,
  type ReplacePreview,
  type SaveReport,
  type SearchOutcome,
  type WorkspaceHistory,
  connectionsList,
  type SavedConnection,
} from '../ipc'
import { entryGlyph, flattenTree, indentPx, neighbouringRow, tabLabel, toggleExpanded, workspaceDisplayName } from '../workspace/logic'
import { dominantEndingLabel, lineNumberText, segmentsForLine, sliceSegments } from '../workspace/editor'
import { highlightPieces } from '../workspace/highlights'
import MarkdownPreview from './MarkdownPreview.vue'
import WorkspaceHome from './WorkspaceHome.vue'
import {
  charWidthFrom,
  codeWidthByDisplayColumns,
  gutterWidth,
  type FontMetrics,
} from '../workspace/metrics'

/** 编辑面数据（2.2）：行结构 + 高亮分词，按相对路径缓存 */
const editorData = ref(new Map<string, { structure: FileLines; spans: CodeSpan[] }>())

/** 一行要画的片段（按同一份原文的字节偏移归位到行内） */
function lineSegments(lineIndex: number) {
  const data = activeEditor.value
  const line = data?.structure.lines[lineIndex]
  if (!data || !line) return []
  // **命中高亮优先**：从检索跳过来时，这一行的命中片段直接标出来（比语法色更该看见）。
  // 口径与检索同源（`workspace/highlights.ts` 复刻了 Rust 侧那套归一规则）。
  const hit = activeHit.value
  if (hit) {
    const pieces = highlightPieces(line.text, hit.query)
    if (pieces.some((piece) => piece.hit)) {
      return pieces.map((piece) => ({ text: piece.text, kind: piece.hit ? 'hit' : 'plain' }))
    }
  }
  // 本行的字节终点 = 下一行的起点（最后一行就是整份原文的末尾）
  const nextStart =
    data.structure.lines[lineIndex + 1]?.byteStart ?? line.byteStart + new TextEncoder().encode(line.text).length
  return sliceSegments(line.text, segmentsForLine(line.text, line.byteStart, nextStart, data.spans))
}

// 外部改动（2.3）：每个页签存一份**载入快照**；比对结果按页签记，**只有变了才说话**
const snapshots = ref(new Map<string, LoadedFile>())
const staleNotes = ref(new Map<string, { staleness: string; note: string }>())

/** 载入（或重载）一个页签时记快照 */
async function rememberSnapshot(relativePath: string) {
  try {
    const loaded = await workspaceFileSnapshot(root.value, relativePath)
    const next = new Map(snapshots.value)
    next.set(relativePath, loaded)
    snapshots.value = next
    // 快照更新 ⇒ 这一页签的「变了」标记清掉（重载之后就是最新的了）
    const notes = new Map(staleNotes.value)
    notes.delete(relativePath)
    staleNotes.value = notes
  } catch {
    // 拿不到快照就不跟踪（**不假装**在跟踪）
  }
}

/** 比对所有开着的页签：**在别处被改了就要说出来** */
async function checkExternalChanges() {
  if (!root.value) return
  const notes = new Map(staleNotes.value)
  for (const tab of tabs.value) {
    const path = tab.relativePath
    if (!path) continue
    const loaded = snapshots.value.get(path)
    if (!loaded) continue
    try {
      const report = await workspaceCheckStaleness(root.value, loaded)
      if (report.staleness !== 'unchanged' && report.note) {
        notes.set(path, { staleness: report.staleness, note: report.note })
      } else {
        notes.delete(path)
      }
    } catch {
      // 查不动就保持原样（不编一个状态）
    }
  }
  staleNotes.value = notes
}

/** 当前页签的「变了」提示（没有就是没变） */
const staleNotice = computed(() => {
  const path = activeTab.value?.relativePath
  return path ? staleNotes.value.get(path) : undefined
})

/** **重新打开**当前页签：从盘上重读内容 + 行结构 + 高亮，并更新快照 */
async function reloadActiveTab() {
  const tab = activeTab.value
  if (!tab?.relativePath || !root.value) return
  busy.value = '重读中…'
  try {
    const file = await workspaceReadFile(root.value, tab.relativePath)
    tabs.value = tabs.value.map((t) => (t.id === tab.id ? { ...t, content: file.content, saved: file.content } : t))
    await loadEditorData(tab.relativePath)
    await rememberSnapshot(tab.relativePath)
  } catch (e) {
    failure.value = describeError(e)
  } finally {
    busy.value = ''
  }
}

// 列宽**按当前等宽字体实量**（2.2）：量一个字符宽，宽度都按"字符数 × 字符宽"算。
// 为什么不能写死：等宽字体在不同机器上字宽不同（默认字体 / DPI 缩放 / 用户字号），
// 写死会在高 DPI 上偏窄、小字号上偏宽，横向滚动条出现得莫名其妙。
const fontMetrics = ref<FontMetrics>({ charWidth: 8, measured: false })

/** 可视区宽度（代码列要不要给宽度靠它判断）；跟随缩放变化 */
const windowWidth = ref(typeof window === 'undefined' ? 0 : window.innerWidth)
function onResize() {
  windowWidth.value = window.innerWidth
}

/** 用 canvas 量一个字符的宽度（**真正碰 canvas 的只有这几行**，其余是纯函数） */
function measureCharWidth(): FontMetrics {
  try {
    const canvas = document.createElement('canvas')
    const context = canvas.getContext('2d')
    if (!context) return charWidthFrom(() => Number.NaN)
    const styles = getComputedStyle(document.documentElement)
    const family = styles.getPropertyValue('--ds-font-stack').trim() || 'monospace'
    const size = styles.getPropertyValue('--ds-font-caption-size').trim() || '12px'
    context.font = `${size} ${family}`
    return charWidthFrom((sample) => context.measureText(sample).width)
  } catch {
    // 量不出来就退回保守默认值（**并如实标注没量到**）
    return charWidthFrom(() => Number.NaN)
  }
}

onMounted(() => {
  fontMetrics.value = measureCharWidth()
  window.addEventListener('resize', onResize)
})
onBeforeUnmount(() => window.removeEventListener('resize', onResize))

/** 行号列宽度（按最大行号的位数算，夹在上下限之间） */
const gutterStyle = computed(() => {
  const digits = activeEditor.value?.structure.gutterDigits ?? 1
  return { width: `${gutterWidth(digits, fontMetrics.value)}px` }
})

/** 代码列宽度：只有**内容比可视区宽**时才给（否则会出一条永远拉不动的横向滚动条） */
const codeStyle = computed(() => {
  const data = activeEditor.value
  if (!data) return {}
  const available = Math.max(0, windowWidth.value - 320)
  const width = codeWidthByDisplayColumns(
    data.structure.lines.map((line) => line.text),
    fontMetrics.value,
    { availableWidth: available, maxWidth: 20_000 },
  )
  return width === null ? {} : { width: `${width}px` }
})
// 检索（2.4）：按文件名 / 按内容 —— **两者共用 Rust 侧同一个匹配谓词**，前端不另写一套 contains
const searchQuery = ref('')
const searchByContent = ref(false)
const searchResult = ref<SearchOutcome | null>(null)
const searching = ref(false)

async function runSearch() {
  if (!root.value || !searchQuery.value.trim()) return
  searching.value = true
  failure.value = null
  try {
    searchResult.value = await workspaceSearch(root.value, searchQuery.value, {
      byContent: searchByContent.value,
      showHidden: showHidden.value,
    })
  } catch (e) {
    failure.value = describeError(e)
    searchResult.value = null
  } finally {
    searching.value = false
  }
}

/** 命中条数（文件名与内容两种模式各算各的） */
const searchHitCount = computed(() => {
  const result = searchResult.value
  if (!result) return 0
  return searchByContent.value ? result.groups.reduce((sum, g) => sum + g.hits.length, 0) : result.files.length
})

/** 点一条命中：打开那个文件**并跳到命中行**（行号先夹进真实行数） */
async function openHit(relativePath: string, line?: number) {
  // **先记下命中信息**（行内高亮要用它；打开之后才记会晚一拍）
  if (line !== undefined) rememberHit(relativePath, searchQuery.value, line)
  // 文件可能还没在树里展开过 —— 直接按路径打开（走的是同一条安全关）
  await openFile({ name: relativePath.split('/').pop() ?? relativePath, relativePath, kind: 'file', isExpandable: false })
  const tab = tabs.value.find((t) => t.relativePath === relativePath)
  if (!tab) return
  if (line !== undefined) {
    const clamped = await workspaceClampLine(root.value, relativePath, line)
    tabs.value = tabs.value.map((t) => (t.id === tab.id ? { ...t, cursorLine: clamped, cursorHow: 'exact' } : t))
    // **滚到那一行**：行号列那一格有 `data-line`，用它在容器里滚过去
    await nextTick()
    const target = document.querySelector(`[data-hit-line="${clamped}"]`)
    target?.scrollIntoView({ block: 'center' })
  }
}
// Markdown 预览（2.5）：模型由 Rust 侧一处解析产出，这里**只画**（只读，没有可编辑控件）
const preview = ref<MdDocument | null>(null)
const showPreview = ref(false)

/** 当前页签是不是 Markdown（按语言键判断，不靠文件名猜） */
const activeIsMarkdown = computed(() => activeTab.value?.languageKey === 'lang.markdown')

async function togglePreview() {
  if (!activeTab.value?.relativePath) return
  showPreview.value = !showPreview.value
  if (!showPreview.value) return
  try {
    preview.value = await workspaceMarkdown(root.value, activeTab.value.relativePath)
  } catch (e) {
    failure.value = describeError(e)
    showPreview.value = false
  }
}

/** 行内 span 的样式类（加粗/斜体/代码可以有交集） */
function inlineClass(span: MdSpan): string[] {
  const classes: string[] = []
  if (span.bold) classes.push('md__bold')
  if (span.italic) classes.push('md__italic')
  if (span.code) classes.push('md__code')
  return classes
}

/** 把一段行内 span 拼成纯文字（表格/列表里要纯文字时用） */
function plainOf(spans: MdSpan[]): string {
  return spans.map((s) => s.text).join('')
}

/** 列表条目的缩进（嵌套层级由 children 递归渲染，这里只是排一下） */
function isMdBlock(block: MdBlock): boolean {
  return typeof block.kind === 'object' && block.kind !== null
}
const props = defineProps<{
  /** 命令面板选中的文件（由外壳递进来）；`null` = 没有待打开的文件 */
  openFileSignal?: string | null
  /** 版本号（Home 页那行"版本 x.y.z"；外壳给的，本视图不自己编） */
  version?: string
}>()

const emit = defineEmits<{
  (event: 'root-changed', root: string): void

  (event: 'push-panel', entry: { text: string; level: 'info' | 'warn' | 'error'; source?: string }): void}>()

/** 工作区根变化时同步给外壳（面板里搜文件要用它） */
watch(root, (value) => emit('root-changed', value), { immediate: true })

/** 面板递进来的"请打开这个文件"：真正打开它（**只有这一层会开文件**） */
watch(
  () => props.openFileSignal,
  async (path) => {
    if (!path || !root.value) return
    await openFile({ name: path.split('/').pop() ?? path, relativePath: path, kind: 'file', isExpandable: false })
  },
)
// 从检索跳过来时的命中信息（2.4）：**查询词**用来在行内标出命中，**行号**用来滚到那里
const hitInfo = ref<Map<string, { query: string; line: number }>>(new Map())

/** 记一次"这一跳带着检索词"（打开命中时调） */
function rememberHit(relativePath: string, query: string, line: number) {
  const next = new Map(hitInfo.value)
  next.set(relativePath, { query, line })
  hitInfo.value = next
}

/** 当前页签的命中信息（没有就是普通打开） */
const activeHit = computed(() => {
  const path = activeTab.value?.relativePath
  return path ? hitInfo.value.get(path) : undefined
})

// 保存（2.3）：编辑面的内容 + 冲突处置
const editorDraft = ref('')
const saveReport = ref<SaveReport | null>(null)

/** 当前页签有未保存改动 */
const isDirty = computed(() => {
  const tab = activeTab.value
  return !!tab && tab.relativePath !== null && editorDraft.value !== tab.saved
})

/** 把草稿对齐到当前页签（切页签 / 打开文件时调） */
watch(
  () => [activeTab.value?.id, activeTab.value?.content] as const,
  () => {
    editorDraft.value = activeTab.value?.content ?? ''
    saveReport.value = null
  },
  { immediate: true },
)

/**
 * 保存当前页签：**必须先有载入快照**（基线），否则不保存 ——
 * 没有基线就无法判断"盘上有没有被别人改过"，盲目写就是拿别人的改动去赌。
 */
async function saveActiveTab(force = false) {
  const tab = activeTab.value
  if (!tab?.relativePath || !root.value) return
  const loaded = snapshots.value.get(tab.relativePath)
  if (!loaded) {
    failure.value = {
      message: '这个页签没有载入快照，无法安全保存',
      hint: '重新打开它一次（快照是"盘上有没有被改过"的判据，缺了就不能保证不覆盖别人的改动）。',
    }
    return
  }
  busy.value = '保存中…'
  try {
    const report = await workspaceSave(root.value, tab.relativePath, editorDraft.value, tab.saved, loaded, force)
    saveReport.value = report
    if (report.decision.kind === 'write' && report.snapshot) {
      // 写成功：内容成为"已保存"，并更新快照（否则下次保存会误报冲突）
      tabs.value = tabs.value.map((t) =>
        t.id === tab.id ? { ...t, content: editorDraft.value, saved: editorDraft.value } : t,
      )
      await rememberSnapshot(tab.relativePath)
      await loadEditorData(tab.relativePath)
    }
  } catch (e) {
    failure.value = describeError(e)
  } finally {
    busy.value = ''
  }
}

// 跨文件替换（2.4）：**先预览、再落盘** —— 一次误操作可能改掉几十个文件，且不可撤销
const replaceText = ref('')
const replacePreview = ref<ReplacePreview | null>(null)
const replaceResult = ref<string>('')

/** 出预览（不写盘） */
async function previewReplace() {
  if (!root.value || !searchQuery.value.trim()) return
  failure.value = null
  try {
    replacePreview.value = await workspaceReplacePreview(
      root.value,
      searchQuery.value,
      replaceText.value,
      showHidden.value,
    )
    replaceResult.value = ''
  } catch (e) {
    failure.value = describeError(e)
    replacePreview.value = null
  }
}

/** 落盘（**逐个文件走保存护栏**：盘上被改过就拒） */
async function applyReplace(force = false) {
  if (!root.value || !replacePreview.value) return
  failure.value = null
  try {
    // **只带已打开页签的快照**（没打开过的文件没有基线 ⇒ 后端会**跳过并说明**，不盲目写）
    const snapshotPayload = Object.fromEntries(snapshots.value)
    const payload = await workspaceReplaceApply(
      root.value,
      searchQuery.value,
      replaceText.value,
      snapshotPayload,
      { showHidden: showHidden.value, force },
    )
    replaceResult.value =
      `已写 ${payload.written} 个文件（共改 ${payload.totalChanges} 处）` +
      (payload.conflicts > 0 ? `；**${payload.conflicts} 个文件因盘上被改过而拒绝**` : '')
    replacePreview.value = null
    // 落盘后把开着的页签重读一遍（否则界面还是旧的）
    for (const tab of tabs.value) {
      if (tab.relativePath) {
        await loadEditorData(tab.relativePath)
        await rememberSnapshot(tab.relativePath)
      }
    }
  } catch (e) {
    failure.value = describeError(e)
  }
}

// 代码格式化（2.6）：按定案口径 —— **外部工具优先，没有则内置并如实说明**
const formatTools = ref<FormatToolProbe[]>([])
const formatNote = ref('')

/** 探一次候选工具（打开文件 / 进入页签时调；**真探**，探不到就是没有） */
async function probeFormatTools() {
  const tab = activeTab.value
  if (!tab?.relativePath || !root.value) {
    formatTools.value = []
    return
  }
  try {
    const payload = await workspaceFormatTools(root.value, tab.relativePath)
    formatTools.value = payload.tools
  } catch {
    // 探不到只是没有外部工具（还有内置兜底），**不弹错**
    formatTools.value = []
  }
}

/** 格式化当前页签（**只改内存**；要落盘还得点保存，届时照样走冲突护栏） */
async function formatActiveTab(preferBuiltin = false) {
  const tab = activeTab.value
  if (!tab?.relativePath || !root.value) return
  busy.value = '格式化中…'
  try {
    const outcome = await workspaceFormatContent(root.value, tab.relativePath, editorDraft.value, preferBuiltin)
    editorDraft.value = outcome.content
    formatNote.value = outcome.note
    if (outcome.changed) {
      // 内容变成本地草稿（**未保存**）：靠 isDirty 提示，用户点保存才落盘
      tabs.value = tabs.value.map((t) => (t.id === tab.id ? { ...t, content: outcome.content } : t))
    }
  } catch (e) {
    failure.value = describeError(e)
  } finally {
    busy.value = ''
  }
}

/** 本版只读：编辑面显示内容，改与存归 2.1 / 2.2 段（不假装能改）。 */
interface OpenTab {
  id: string
  title: string
  relativePath: string | null
  content: string
  languageKey: string
  saved: string
  /** 上次离开时停在哪一行（1 起）；本版只读，这个"光标"就是那一行 */
  cursorLine: number
  /** 这个位置是**怎么恢复来的**（只有不确定时才提醒用户） */
  cursorHow: 'exact' | 'byAnchor' | 'clamped'
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

// 外部改动检查的时机：**窗口回到前台时**（切出去在别处改文件是主场景）+ 页签上的手动按钮。
// **不做定时轮询**：那是持续消耗，而"回到前台"已经覆盖了绝大多数场景。
function onWindowFocus() {
  void checkExternalChanges()
}
onMounted(() => window.addEventListener('focus', onWindowFocus))
onBeforeUnmount(() => window.removeEventListener('focus', onWindowFocus))

// 会话恢复（2.0）：上次打开的根 + 最近打开两份清单。
// **不自动打开**上次那个文件夹：路径可能已被移动 / 删除，自动打开会每次启动弹一次错；
// 改成"预填 + 一句话告诉你是上次那个"，由人点一下「打开」（想打开哪个由人定）。
// ── Home 页三栏（布局对齐 macOS 封面图）───────────────────────────────────────────
//
// 「连接」那一栏要的是**已保存的连接**（与数据库视图同一份数据，`connections_list`）。
// 没连过库就是空数组 ⇒ 那一栏**不画**（不留空栏位充数）。
const savedConnections = ref<SavedConnection[]>([])

async function loadSavedConnections() {
  try {
    savedConnections.value = await connectionsList()
  } catch {
    savedConnections.value = []
  }
}

/** Home 上点「打开文件…」：引导到资源管理器（工作区内的文件选择在那里） */
function homeOpenFile() {
  openHint.value = '在左侧「资源管理器」里点一个文件即可打开；Home 上「最近打开的文件」点一下也能打开。'
}

/** Home 上点某个最近文件：在**当前工作区**里按相对路径打开（不在工作区内就如实提示） */
async function homeOpenRecentFile(path: string) {
  const normalized = path.split('\\').join('/')
  const base = (root.value || '').split('\\').join('/').replace(/\/+$/, '')
  if (!base || !normalized.startsWith(base + '/')) {
    openHint.value = `这个文件不在当前工作区里：${path}（先打开它所在的工作区）`
    return
  }
  await openHit(normalized.slice(base.length + 1))
}

/** Home 上点某个连接：**如实说**它在数据库视图里用（本视图不连库） */
function homeOpenConnection(id: string) {
  const target = savedConnections.value.find((c) => c.id === id)
  openHint.value = target
    ? `已保存的连接「${target.name}」在「数据库」视图里使用（点左侧活动栏的数据库图标）。`
    : '这个连接找不到了（可能已被删除）。'
}

/** Home 上点某个最近工作区：**真的打开它**（不是只填进输入框） */
async function openRecentWorkspace(path: string) {
  rootDraft.value = path
  await openWorkspace()
}

const history = ref<WorkspaceHistory | null>(null)
const historyWarning = ref('')
const openHint = ref('')

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
  return {
    id: HOME_ID,
    title: '首页',
    relativePath: null,
    content: '',
    languageKey: 'lang.plainText',
    saved: '',
    cursorLine: 1,
    cursorHow: 'exact',
  }
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

async function openTextFile(entry: FsEntry) {
  // **同一路径只开一个页签**（领域规则）：已开着就切过去，不重复开
  const existing = tabs.value.find((t) => t.relativePath === entry.relativePath)
  if (existing) {
    selectedTabId.value = existing.id
    return
  }
  busy.value = '读取中…'
  try {
    const file: FileContent = await workspaceReadFile(root.value, entry.relativePath)
    // 先拉编辑面数据（行结构）—— 光标恢复要用它对齐；**拉不到不影响打开**
    await loadEditorData(file.relativePath)
    // 光标恢复（2.3）：把上次的锚与现在的行结构对一遍，落到原位（怎么来的要说清）
    const restored = restoreCursor(file.relativePath, history.value?.cursors?.[file.relativePath])
    const tab: OpenTab = {
      id: `tab-${tabs.value.length}-${file.relativePath}`,
      title: entry.name,
      relativePath: file.relativePath,
      content: file.content,
      languageKey: file.languageKey,
      saved: file.content,
      cursorLine: restored.line,
      cursorHow: restored.how,
    }
    tabs.value = [...tabs.value, tab]
    selectedTabId.value = tab.id
    await rememberSnapshot(tab.relativePath)
    await rememberOpenTabs()
  } finally {
    busy.value = ''
  }
}

/**
 * 光标恢复：行号命中且那一行开头对得上 ⇒ exact；否则按前缀找 ⇒ byAnchor；都找不到 ⇒ 夹到最后一行。
 *
 * 与 Rust 侧 cursor::restore 同一套判定（那边有 7 例单测）；这里按同一口径走一遍，
 * 因为打开文件时我们已经把行结构拉回来了，不必再多一次往返。
 */
function restoreCursor(
  relativePath: string,
  anchor: CursorAnchor | undefined,
): { line: number; how: 'exact' | 'byAnchor' | 'clamped' } {
  if (!anchor) return { line: 1, how: 'exact' }
  const structure = editorData.value.get(relativePath)?.structure
  if (!structure) return { line: Math.max(1, anchor.line), how: 'exact' }
  const prefixOf = (text: string) => [...text.trimStart()].slice(0, 32).join('')
  const want = Math.max(1, anchor.line)
  const line = structure.lines[want - 1]
  if (line && prefixOf(line.text) === anchor.linePrefix) return { line: want, how: 'exact' }
  const found = structure.lines.findIndex((l) => prefixOf(l.text) === anchor.linePrefix)
  if (found >= 0) return { line: found + 1, how: 'byAnchor' }
  return { line: Math.max(1, structure.lines.length), how: 'clamped' }
}

/** 切页签：**先把当前这个停在哪记下来**，再切过去 */
function switchTab(id: string) {
  void rememberCursor(activeTab.value)
  selectedTabId.value = id
}
/** 记下某个页签停在哪儿（切页签 / 关页签时调） */
async function rememberCursor(tab: OpenTab | null) {
  if (!tab?.relativePath || !root.value) return
  try {
    await workspaceRecordCursor(root.value, tab.relativePath, tab.cursorLine, 0)
  } catch {
    // 记不住不影响用（下次恢复不到原位而已），不打断当前操作
  }
}
// 按类型打开（2.3）：打开文件前先判"该怎么打开" —— 图片走图片预览，二进制 / 太大给说明
const openDecision = ref<OpenDecision | null>(null)
const imageDataUrl = ref('')

/**
 * 打开文件**之前**问一次"该怎么打开"。
 *
 * 为什么要问：工作区里不只放代码 —— 图片、二进制、超大日志都有。
 * 全塞进编辑面会得到"一屏乱码"或"打开就卡住"；判定在 Rust 领域层（`open_as`，5 例单测）。
 */
async function openFile(entry: FsEntry) {
  if (!root.value) return
  failure.value = null
  try {
    const decision = await workspaceDecideOpen(root.value, entry.relativePath)
    openDecision.value = decision
    if (decision.openAs.kind === 'image') {
      // 图片：取字节走图片预览（**不进编辑面**）
      imageDataUrl.value = `data:${decision.imageMime};base64,${await workspaceReadImage(root.value, entry.relativePath)}`
      preview.value = null
      showPreview.value = false
      return
    }
    imageDataUrl.value = ''
    if (decision.openAs.kind !== 'text') {
      // 二进制 / 太大：**如实说**，不硬塞进编辑面
      return
    }
  } catch (e) {
    failure.value = describeError(e)
    return
  }
  await openTextFile(entry)
}

/** 打开一个页签时拉一次编辑面数据（行号列宽 / 主换行符 / 混排 / 高亮分词） */
async function loadEditorData(relativePath: string | null) {
  if (!relativePath) return
  try {
    const [structure, highlight] = await Promise.all([
      workspaceReadLines(root.value, relativePath),
      workspaceReadSpans(root.value, relativePath),
    ])
    const next = new Map(editorData.value)
    next.set(relativePath, { structure, spans: highlight.spans })
    editorData.value = next
  } catch {
    // 读不到就不上色、不给行号（**不假装**有）
  }
}

/** 当前页签的编辑面数据（没有就是纯文本） */
const activeEditor = computed(() =>
  activeTab.value?.relativePath ? editorData.value.get(activeTab.value.relativePath) : undefined,
)

/** 换行符如实显示：混排要说出来，别偷偷统一 */
const endingNote = computed(() => {
  const data = activeEditor.value
  if (!data) return ''
  const parts = [`换行符 ${dominantEndingLabel(data.structure.dominantEnding)}`]
  if (data.structure.mixedEndings) parts.push('**混排**（保存时会统一成上面那种）')
  return parts.join(' · ')
})

function closeTab(id: string) {
  const index = tabs.value.findIndex((t) => t.id === id)
  if (index >= 0) void rememberCursor(tabs.value[index])
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

    <!-- 检索（2.4）：按文件名 / 按内容；点结果即打开并跳到命中行 -->
    <form v-if="root" class="ws__searchbar" @submit.prevent="runSearch">
      <input v-model="searchQuery" type="search" placeholder="在工作区里找…（回车搜索）" aria-label="工作区检索" />
      <label class="ws__check">
        <input v-model="searchByContent" type="checkbox" />
        搜内容（不勾=只搜文件名）
      </label>
      <label class="ws__field">
        <span>替换为</span>
        <input v-model="replaceText" type="text" spellcheck="false" placeholder="跨文件替换（先预览）" />
      </label>
      <button class="ws__btn" type="button" :disabled="searching || !searchQuery.trim()" @click="previewReplace">
        预览替换
      </button>
      <template v-if="replacePreview">
        <button class="ws__btn ws__btn--primary" type="button" @click="applyReplace(false)">执行替换</button>
        <button class="ws__btn" type="button" :disabled="!replacePreview" @click="replacePreview = null">取消</button>
      </template>
      <button class="ws__btn" type="submit" :disabled="searching">搜索</button>
      <span v-if="searchResult" class="ws__note">
        命中 {{ searchHitCount }} 条<template v-if="searchResult.truncated">（**已达上限 {{ searchResult.limit }}**，不是全部）</template>
        <template v-if="searchByContent">
          · 读了 {{ searchResult.scannedFiles }} 个文件
          <template v-if="searchResult.skips.binary + searchResult.skips.tooLarge + searchResult.skips.unreadable > 0">
            · 跳过 {{ searchResult.skips.binary }} 个二进制 / {{ searchResult.skips.tooLarge }} 个过大 /
            {{ searchResult.skips.unreadable }} 个读不了
          </template>
        </template>
      </span>
      <button v-if="searchResult" class="ws__act" type="button" title="清掉结果" @click="searchResult = null">✕</button>
    </form>
    <!-- 替换预览（2.4）：**先让人看清影响面**（几个文件、各几处）再落盘 -->
    <div v-if="replacePreview" class="ws__hits">
      <p class="ws__hit-file">{{ replacePreview.summary }}</p>
      <p class="ws__note">
        跳过 {{ replacePreview.skips.binary }} 个二进制 / {{ replacePreview.skips.tooLarge }} 个过大 /
        {{ replacePreview.skips.unreadable }} 个读不了（**跳过 ≠ 没命中**）
      </p>
      <div v-for="file in replacePreview.files" :key="file.relativePath" class="ws__hit-group">
        <p class="ws__hit-file">{{ file.relativePath }}（{{ file.count }} 处）</p>
        <p v-for="change in file.changes" :key="change.line" class="ws__hit">
          第 {{ change.line }} 行：{{ change.before }} → {{ change.after }}
        </p>
      </div>
      <p v-if="replacePreview.files.length === 0" class="ws__empty">没有要改的地方</p>
    </div>
    <p v-if="replaceResult" class="ws__note ws__note--warn">{{ replaceResult }}</p>
    <div v-if="searchResult" class="ws__hits">
      <template v-if="searchByContent">
        <div v-for="group in searchResult.groups" :key="group.relativePath" class="ws__hit-group">
          <p class="ws__hit-file">{{ group.relativePath }}（{{ group.hits.length }} 处）</p>
          <button
            v-for="hit in group.hits"
            :key="hit.line"
            class="ws__hit"
            type="button"
            :title="`打开并跳到第 ${hit.line} 行`"
            @click="openHit(hit.relativePath, hit.line)"
          >
            第 {{ hit.line }} 行：{{ hit.snippet }}
          </button>
        </div>
        <p v-if="searchResult.groups.length === 0" class="ws__empty">没有命中（跳过的那几个文件不算"没命中"）</p>
      </template>
      <template v-else>
        <button
          v-for="file in searchResult.files"
          :key="file"
          class="ws__hit"
          type="button"
          :title="`打开 ${file}`"
          @click="openHit(file)"
        >
          {{ file }}
        </button>
        <p v-if="searchResult.files.length === 0" class="ws__empty">没有名字匹配的文件</p>
      </template>
    </div>

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
            <button class="ws__tab-name" type="button" role="tab" :aria-selected="tab.id === selectedTabId" @click="switchTab(tab.id)">
              {{ tabLabel(tab.title, tab.content !== tab.saved) }}
            </button>
            <button v-if="tab.relativePath !== null" class="ws__tab-close" type="button" title="关闭页签" @click="closeTab(tab.id)">✕</button>
          </div>
        </div>

        <div class="ws__editor">
          <template v-if="activeTab && activeTab.relativePath === null">
              <WorkspaceHome
                :recent-files="history?.files ?? []"
                :recent-workspaces="recentWorkspaces"
                :current-root="history?.currentRoot ?? ''"
                :connections="savedConnections"
                :version="props.version?.trim() || '（版本未知）'"
                @open-file="homeOpenFile"
                @open-workspace="openRecentWorkspace"
                @open-connection="homeOpenConnection"
              />
              <p v-if="openHint" class="ws__home-line">{{ openHint }}</p>
            </template>
          <template v-else-if="activeTab">
            <p class="ws__editor-meta">
              {{ activeTab.relativePath }} · {{ activeTab.languageKey }}
              <span v-if="endingNote" class="ws__tag">{{ endingNote }}</span>
              <span class="ws__tag">只读（本版）</span>
              <span v-if="activeTab.cursorHow !== 'exact' && activeTab.cursorLine > 1" class="ws__tag" title="文件被改过，位置是按内容锚找回来的">
                位置可能不准（按内容找回来的）
              </span>
              <button v-if="activeIsMarkdown" class="ws__act" type="button" :title="showPreview ? '看源码' : '看预览（只读）'" @click="togglePreview">
                {{ showPreview ? '源码' : '预览' }}
              </button>
              <button
                class="ws__act"
                type="button"
                :title="
                  formatTools.some((t) => t.available)
                    ? '代码格式化（外部工具优先）'
                    : '代码格式化（没有外部工具 ⇒ 内置兜底，会如实说明）'
                "
                @click="formatActiveTab(false)"
              >
                ✨ 格式化
              </button>
              <button
                class="ws__act"
                type="button"
                :title="isDirty ? '保存到磁盘（盘上被别处改过时会拒绝）' : '没有改动'"
                :disabled="!isDirty"
                @click="saveActiveTab(false)"
              >
                💾 保存
              </button>
              <button class="ws__act" type="button" title="重新比对盘上有没有被别处改过" @click="checkExternalChanges">
                ⟳ 比对
              </button>
            </p>
            <!-- 格式化的回执（2.6）：**必须说清用了哪一个工具 / 内置做了什么** -->
            <div v-if="formatNote" class="ws__stale" role="status">
              <p class="ws__stale-msg">{{ formatNote }}</p>
              <button class="ws__btn" type="button" @click="formatNote = ''">知道了</button>
            </div>
            <!-- 保存冲突（2.3）：**拒绝保存**之后要给人一条出路（覆盖 / 先比对） -->
            <div v-if="saveReport && (saveReport.decision.kind === 'conflict' || saveReport.note)" class="ws__stale" role="alert">
              <p class="ws__stale-msg">{{ saveReport.note }}</p>
              <template v-if="saveReport.decision.kind === 'conflict'">
                <button class="ws__btn" type="button" @click="checkExternalChanges">先比对</button>
                <button class="ws__btn ws__btn--primary" type="button" @click="saveActiveTab(true)">
                  用我的版本覆盖
                </button>
              </template>
            </div>
            <!-- 外部改动（2.3）：**如实说**，并给出下一步（重新打开）—— 只说"变了"等于把问题丢回给人 -->
            <div v-if="staleNotice" class="ws__stale" role="alert">
              <p class="ws__stale-msg">{{ staleNotice.note }}</p>
              <button class="ws__btn ws__btn--primary" type="button" @click="reloadActiveTab">重新打开</button>
            </div>
            <!-- 图片预览（2.3 按类型打开）：按内容认出来的图片走这里 -->
            <div v-if="imageDataUrl" class="ws__image">
              <p class="ws__note">{{ openDecision?.note }}</p>
              <img :src="imageDataUrl" :alt="activeTab?.title ?? '图片'" class="ws__image-img" />
            </div>
            <!-- 二进制 / 太大：如实说，不硬塞进编辑面 -->
            <div v-else-if="openDecision && openDecision.openAs.kind !== 'text'" class="ws__notice">
              <p class="ws__failure-msg">{{ openDecision.note }}</p>
              <p class="ws__failure-hint">用「在终端打开」或系统工具看它（本版不假装能预览）。</p>
            </div>
            <!-- Markdown 只读预览（2.5）：模型由 Rust 侧一处解析产出，这里只画 -->
            <div v-if="showPreview && preview" class="ws__preview">
              <MarkdownPreview :document="preview" />
            </div>
            <!-- 编辑面：**行号列 + 高亮**（行号列宽随行数变 —— 写死会在第 100 行处挤掉数字） -->
            <div v-if="activeEditor && !showPreview" class="ws__gutter-wrap">
              <div class="ws__gutter" aria-hidden="true" :style="gutterStyle">
                <span
                  v-for="(line, i) in activeEditor.structure.lines"
                  :key="i"
                  class="ws__gutter-num"
                  :class="{ 'ws__gutter-num--cursor': activeTab.cursorLine === i + 1 }"
                  :data-hit-line="activeHit?.line === i + 1 ? i + 1 : undefined"
                  :title="activeTab.cursorLine === i + 1 ? '上次停在这一行' : undefined"
                >{{
                  lineNumberText(i, activeEditor.structure.gutterDigits)
                }}</span>
              </div>
              <pre class="ws__code ws__code--lined" :style="codeStyle"><span
                v-for="(line, i) in activeEditor.structure.lines"
                :key="i"
                class="ws__line"
              ><span
                v-for="(piece, j) in lineSegments(i)"
                :key="j"
                :class="piece.kind === 'plain' ? undefined : `ws__tok ws__tok--${piece.kind}`"
              >{{ piece.text }}</span>
</span></pre>
            </div>
            <pre v-else-if="!showPreview" class="ws__code">{{ activeTab.content }}</pre>
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
.ws__searchbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--ds-spacing-s);
  padding: var(--ds-spacing-xs) var(--ds-spacing-m);
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
  background: var(--ds-color-surface-panel);
}

.ws__searchbar input[type='search'] {
  min-width: 280px;
  height: var(--ds-metric-control-height);
  padding: 0 var(--ds-spacing-s);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
}

/* 命中列表：最多占半屏，避免把编辑面挤没 */
.ws__hits {
  max-height: 40vh;
  overflow: auto;
  padding: var(--ds-spacing-xs) var(--ds-spacing-m);
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
}

.ws__hit-file {
  margin: var(--ds-spacing-xs) 0;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.ws__hit {
  display: block;
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

.ws__hit:hover {
  background: var(--ds-color-surface-panel);
}
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

/* 行号列 + 代码（2.2）：两栏并排，行高必须一致（否则行号与内容会错开半行） */
/* 外部改动提示：**醒目但不挡路**（内容还在，只是可能不是盘上那份了） */
.ws__stale {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--ds-spacing-s);
  margin: 0 0 var(--ds-spacing-s);
  padding: var(--ds-spacing-s);
  background: var(--ds-color-surface-panel);
  border: var(--ds-metric-hairline) solid var(--ds-color-status-warning);
  border-radius: var(--ds-radius-control);
}

.ws__stale-msg {
  margin: 0;
  color: var(--ds-color-text-primary);
  font-size: var(--ds-font-caption-size);
}
/* Markdown 预览容器（只读：里面不出现任何可编辑控件） */
/* 图片预览（按类型打开）：给个上限，别把界面撑破 */
.ws__image {
  padding: var(--ds-spacing-s);
}

.ws__image-img {
  max-width: 100%;
  max-height: 60vh;
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
}

/* 二进制 / 太大的说明区（**不硬塞**） */
.ws__notice {
  padding: var(--ds-spacing-s);
  border: var(--ds-metric-hairline) solid var(--ds-color-status-warning);
  border-radius: var(--ds-radius-control);
}

.ws__preview {
  padding: var(--ds-spacing-s);
  background: var(--ds-color-surface-content);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  overflow: auto;
}
.ws__gutter-wrap {
  display: flex;
  align-items: stretch;
  background: var(--ds-color-surface-content);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  overflow: auto;
}

.ws__gutter {
  display: flex;
  flex-direction: column;
  padding: var(--ds-spacing-s) var(--ds-spacing-xs);
  border-right: var(--ds-metric-hairline) solid var(--ds-hairline);
  background: var(--ds-color-surface-sidebar);
  color: var(--ds-color-text-tertiary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  line-height: var(--ds-metric-list-row-height);
  text-align: right;
  user-select: none;
}

/* 上次停在的那一行：左侧给一条标记（本版只读，"光标"就是这一行） */
.ws__gutter-num--cursor {
  color: var(--ds-color-accent-accent);
  font-weight: 600;
}
.ws__gutter-num {
  display: block;
  white-space: pre;
}

.ws__code--lined {
  flex: 1;
  line-height: var(--ds-metric-list-row-height);
  border: 0;
  border-radius: 0;
  white-space: pre;
}

.ws__line {
  display: block;
  min-height: var(--ds-metric-list-row-height);
}

/* 高亮色只走令牌（棘轮守着） */
/* 命中高亮（2.4）：从检索跳过来的那一行，命中片段标出来 */
.ws__tok--hit {
  background: var(--ds-color-status-warning);
  color: var(--ds-color-surface-content);
  border-radius: var(--ds-radius-hairline);
}

.ws__tok--comment {
  color: var(--ds-color-text-tertiary);
}

.ws__tok--str {
  color: var(--ds-color-accent-accent);
}

.ws__tok--number {
  color: var(--ds-color-status-warning);
}

.ws__tok--keyword {
  color: var(--ds-color-text-primary);
  font-weight: 600;
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
