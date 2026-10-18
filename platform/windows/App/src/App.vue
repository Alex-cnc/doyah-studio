<script setup lang="ts">
// 表示层外壳（Windows 侧）—— 本轮把「活动栏 + 窗口标题」按三书落到单点状态上
//
// 契约来源：`Docs/概要设计.md` §8.5.4「一样」清单 + macOS 侧 `Core/ActivityBar.swift`。
// 四模块位与对侧的语义一一对应；**未开工的视图如实标 ⬜**（不半建、不假装能点）。

import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch} from 'vue'
import { appInfo, type AppInfo } from './ipc'
import CommandPalette from './shell/CommandPalette.vue'
import TitleBar from './shell/TitleBar.vue'
import { commandById, type Command } from './shell/commands'
import { pickFolder } from './shell/dialogs'
import { connectionDialogModeForCommand, type ConnectionDialogMode } from './shell/connectionDialog'
import BottomPanel from './shell/BottomPanel.vue'
import AgentSettingsDialog from './shell/AgentSettingsDialog.vue'
import { setLanguage, t as translate, type UiLanguage } from './i18n'
import SideBar from './shell/SideBar.vue'
import StatusBar from './shell/StatusBar.vue'
import {
  DEFAULT_APPEARANCE_DOM,
  appearanceGet,
  appearanceSet,
  commandHistoryClear,
  commandHistoryGet,
  commandHistoryRecord,
  dbPaletteObjects,
  type Appearance as AppearancePref,
  type DomAppearance,
} from './ipc'
import {
  applyAppearance,
  applyEditorFontVars,
  FONT_CHOICES,
  FONT_SIZE_CHOICES,
  MODE_LABELS,
  SCHEME_LABELS,
  systemIsDark,
} from './shell/appearance'
import { detectFontStatus, type FontStatus } from './shell/editorFont'
// **视图一律查表，不直连 import**（契约 §3.52-③ 宿主挂点 / §8.5.8）：
// 核心视图（工作区 / 数据库）与插件视图（笔记 / 回放）登记在**同一张表**里，
// 这里只按 id 取组件 —— 插件被拔掉时"查不到"，界面**什么都不画、不报错**。
import { registerCoreSlots } from './views/coreSlots'
import { installPlugins } from './plugins/registry'
import { loadPlugins, pluginById } from './shell/plugins'
import { resolveView } from './shell/pluginRegistry'
import { itemGlyph, itemTitle, type ActivityBarItemId } from './shell/activityBar'
// 活动栏项**由清单派生**（核心项 + 插件项）——不再写死一份"已开工清单"（契约 §3.52-②）。
import { CORE_ACTIVITY_ITEMS, derivedActivityItems } from './shell/activityItems'
import { activeItem, setActive } from './shell/activityBarStore'

const info = ref<AppInfo | null>(null)

// ── 当前视图：**查表取组件 + 按视图传参**（契约 §3.52-③④ / §8.5.8）──────────────
//
// 为什么核心视图与插件视图走同一处：两套机制迟早分叉（加一个视图忘改一处）。
// 核心视图有各自的入参（工作区的打开信号、数据库的对话框请求），插件视图只需要语言与版本；
// 这里**按 id 分派**，越界的 id 不硬套参数（宁可少传，也不给别的视图乱塞）。
const viewComponent = computed(() => resolveView(activeItem.value))

const viewProps = computed<Record<string, unknown>>(() => {
  const id = activeItem.value
  if (id === 'workspace') {
    return {
      openFileSignal: openFileSignal.value,
      openFolderSignal: openFolderSignal.value,
      version: info.value?.version ?? '',
      language: uiLanguage.value,
    }
  }
  if (id === 'database') {
    return { dialogRequest: connectionDialogRequest.value, language: uiLanguage.value }
  }
  // 插件视图：只给"语言 + 版本"（版本从清单取，避免插件目录再写一遍）。
  return { language: uiLanguage.value, version: pluginById(id)?.version ?? '' }
})



// 命令使用历史（2.9）：**常用优先**的顺序由 Rust 领域层给（这里只存与传）
const rankedCommands = ref<string[]>([])

async function loadCommandHistory() {
  try {
    const payload = await commandHistoryGet()
    rankedCommands.value = payload.ranked
  } catch {
    // 读不到就没有"常用"排序（面板按清单顺序显示），**不弹错**
    rankedCommands.value = []
  }
}

/** 记一次"用了这条命令"（**记完落盘**；失败不打断使用） */
async function rememberCommand(commandId: string) {
  try {
    const payload = await commandHistoryRecord(commandId, Math.floor(Date.now() / 1000))
    rankedCommands.value = payload.ranked
  } catch {
    // 记不住只是下次排序退化，不打断当前动作
  }
}

// 面板里可搜的数据库对象与最近打开（**打开面板时才拉对象**：连不上就是空，不打扰）
const paletteObjects = ref<{ schema: string; name: string; kind: string }[]>([])
const recentFiles = ref<string[]>([])

/** 记一个"刚打开过的文件"（最近的在前，去重，最多 10 条） */
function rememberRecentFile(relativePath: string) {
  recentFiles.value = [relativePath, ...recentFiles.value.filter((p) => p !== relativePath)].slice(0, 10)
}

async function loadPaletteObjects() {
  try {
    paletteObjects.value = await dbPaletteObjects()
  } catch {
    // 没连库 / 读不到 ⇒ 面板里只是少一类可搜项（**不弹错**）
    paletteObjects.value = []
  }
}
// 工作区根（面板里搜文件要用它；由 WorkspaceView 在打开/关闭工作区时同步上来）
const workspaceRoot = ref('')

/** 给 WorkspaceView 的"请打开这个文件"信号（**先声明后使用**） */
const openFileSignal = ref<string | null>(null)

/** 给 WorkspaceView 的"请打开这个目录"信号（命令面板「打开工作区文件夹」用；**先声明后使用**） */
const openFolderSignal = ref<string | null>(null)

/**
 * 面板里选中一个**文件**：切到工作区视图并打开它。
 *
 * 为什么要切视图：面板是全局的，而"打开文件"是工作区的事 —— 不切过去就会"点了没反应"。
 * `openFileSignal` 是给 WorkspaceView 的信号（它才是真正能打开文件的那一层）。
 */
async function openFromPalette(target: { relativePath: string }) {
  setActive('workspace')
  rememberRecentFile(target.relativePath)
  openFileSignal.value = target.relativePath
  // 让监听方处理完就清掉（避免重复触发）
  await nextTick()
  openFileSignal.value = null
}
// 命令面板（2.9）：Ctrl+K 打开；清单来自 `shell/commands.ts`，匹配排序在 Rust 侧
const paletteOpen = ref(false)
/** 从标题栏搜索带进面板的词（空串 = 面板自己从零开始） */
const paletteSeed = ref('')

/** 标题栏搜索框回车/点一下：开面板并把词带进去（复用面板已有的三合一搜索） */
function openPaletteWithSearch(query: string) {
  paletteSeed.value = query
  paletteOpen.value = true
}

/** 连接弹层的「开一次」请求（**序号**保证同档连点两次也会重开；布尔量在"开着"时是静默的）。 */
const connectionDialogRequest = ref<{ mode: ConnectionDialogMode; seq: number } | null>(null)
let connectionDialogSeq = 0

/** 智能体设置弹层（FR-AI-01）：只有一个开关位 —— 配置与裁决都在弹层自己那一侧。 */
const agentSettingsOpen = ref(false)

/** 命令点中了连接面：切到数据库视图（弹层在那一侧）并递一次开弹层请求。 */
function requestConnectionDialog(mode: ConnectionDialogMode) {
  setActive('database')
  connectionDialogSeq += 1
  connectionDialogRequest.value = { mode, seq: connectionDialogSeq }
}

function onGlobalKeydown(event: KeyboardEvent) {
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
    event.preventDefault()
    paletteOpen.value = !paletteOpen.value
    if (paletteOpen.value) {
      void loadPaletteObjects()
      void loadCommandHistory()
    }
  }
}

/** 执行一条命令：**能做的就做，做不到就如实说**（不假装执行过） */
async function runCommand(command: Command) {
  // 先记一笔（**常用优先**排序靠它；记不进也不影响执行）
  void rememberCommand(command.id)
  // 连接面（表单 + 连接列表）只在弹层里：这三条命令把弹层**开起来**
  // （开哪一档由 `shell/connectionDialog.ts` 的 id → 档位映射决定；不在这里再写一份）。
  const dialogMode = connectionDialogModeForCommand(command.id)
  if (dialogMode) {
    requestConnectionDialog(dialogMode)
    return
  }
  switch (command.id) {
    case 'workspace.openFolder': {
      // **真的调起系统文件夹选择器**（本条命令原先走默认分支、只回一句「请在视图里用界面按钮执行」
      // = 入口死路；前门单 `T-20261007-015` 一 认定为真缺陷）。选中的目录递给 WorkspaceView，
      // 由它走**既有** `openWorkspace()` —— 打开栈只有那一处。
      const selected = await pickFolder(tr('cmd.workspace.openFolder'))
      if (!selected) return
      setActive('workspace')
      openFolderSignal.value = selected
      // 让监听方处理完就清掉（避免重复触发）——与 `openFromPalette` 同一套
      await nextTick()
      openFolderSignal.value = null
      return
    }
    case 'history.clear': {
      // 清掉使用记录：清完把"常用优先"的顺序也清空（面板回到清单顺序）
      try {
        const payload = await commandHistoryClear()
        rankedCommands.value = payload.ranked
      } catch {
        commandNote.value = '命令使用记录没清掉（文件可能不可写）'
        setTimeout(() => (commandNote.value = ''), 4000)
      }
      return
    }
    case 'appearance.followSystem':
      await changeAppearance({ mode: 'followSystem' })
      return
    case 'appearance.alwaysDark':
      await changeAppearance({ mode: 'alwaysDark' })
      return
    case 'appearance.alwaysLight':
      await changeAppearance({ mode: 'alwaysLight' })
      return
    case 'agent.settings': {
      // 智能体设置（FR-AI-01）：弹层自己取快照（配置 + 裁决 + 密钥在不在），
      // 外壳不持有那一路状态 —— 它只有一个开关位。
      agentSettingsOpen.value = true
      return
    }
    default:
      // 其余命令要在对应视图里用界面按钮做（那才是**实际执行路径**）；
      // 这里如实说明，而不是"静默什么都不做"。
      commandNote.value = `「${command.title}」请在「${command.view ?? ''}」视图里用界面按钮执行（面板只做发现与分派）`
      setTimeout(() => (commandNote.value = ''), 4000)
  }
}

/** 命令执行的回执（做不到时要说清） */
// 底部面板（布局对齐 macOS 封面图）
//
// 输出流水由视图通过 `push-panel` 事件喂进来；有上限（超出丢最老的）——
// 一个跑一整天的应用不能把输出全留在内存里。
/** 界面语言：**外壳持有、往下传**（原来是数据库视图自己持有一份 ⇒ 两处会不一致）。
 * 详情面板与外壳文案都取它；切换入口仍在数据库视图那一侧（它才是用户看得见的地方）。 */
const uiLanguage = ref<UiLanguage>('zh-Hans')

// 语言一变就同步给 i18n 的"当前值"（ipc 等底层模块读它）——**单一出处**，不是各存一份
watch(uiLanguage, (value) => setLanguage(value), { immediate: true })

/** 外壳文案帮手（语言由外壳自己持有）。 */
function tr(key: Parameters<typeof translate>[0], vars?: Record<string, string | number>): string {
  return translate(key, uiLanguage.value, vars)
}

const panelOpen = ref(true)
const panelEntries = ref<PanelEntry[]>([])
const PANEL_ENTRY_LIMIT = 500

/** 某个视图往面板里打一条。 */
function pushPanel(entry: PanelEntry) {
  const next = [...panelEntries.value, { at: Date.now(), ...entry }]
  panelEntries.value = next.length > PANEL_ENTRY_LIMIT ? next.slice(next.length - PANEL_ENTRY_LIMIT) : next
}

/** 只有警告与出错进「问题」页签（要处理的那些）。 */
const panelProblems = computed(() => panelEntries.value.filter((entry) => entry.level !== 'info'))

const commandNote = ref('')
// 状态栏的四个读数：**来源 = 当前结果集**（由 DatabaseView 在结果变化时上报，见 `onResultStats`）。
// 没有结果（未连库 / 没跑查询）时一律 0 —— 不编造数字。
const rows = ref(0)
const cols = ref(0)
const loaded = ref(0)
const total = ref(0)

/** 结果集换了：把「结果集几行几列 / 本片取了行」同步给状态栏。 */
function onResultStats(payload: { rows: number; cols: number; loaded: number; total: number }) {
  rows.value = payload.rows
  cols.value = payload.cols
  loaded.value = payload.loaded
  total.value = payload.total
}

// 外观（2.8）：规则在 Rust 侧（`Db/src/appearance.rs`），这里只管"读回来 → 贴到根元素 → 改了就存回去"
const appearance = ref<AppearancePref | null>(null)
const appearanceWarning = ref('')

/** 系统当前深浅（只在"跟随系统"那一档影响结果；监听它才能在系统切换时即时跟随） */
const darkQuery =
  typeof window !== 'undefined' && window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null
const systemDark = ref(systemIsDark())

/** 改了任一项：写回并重贴（**部分更新**，只传改动的那项） */
async function changeAppearance(
  patch: Partial<Pick<AppearancePref, 'mode' | 'scheme' | 'nebulaSkin' | 'editorSizePt'>> & {
    /** 空串 = 回到系统等宽（清掉挑的族）；不传 = 不改 */
    editorFamily?: string
  },
) {
  if (!appearance.value) return
  try {
    const payload = await appearanceSet(patch, systemDark.value)
    appearance.value = payload.appearance
    applyAppearance(payload.dom)
  } catch {
    // 存不下去就**不假装配上了**：界面先不动，下次启动会回到上次存下的那份
  }
}

// ── 编辑器字体（FR-EDIT-26 的字体面）──────────────────────────────────────────────
// 分工：族名清洗 / 等宽回落 / 字号夹取在 Rust（`Db/src/editor_font.rs`）；
// 「这台机器上到底有没有这个族」只能在前端量（`shell/editorFont.ts`）；
// 这里只做三件事：收集用户输入、调命令、把**当前实际在用的**那句说出来。
const fontDraft = ref('')

/** 未选 = 系统等宽；选了且量到 = 命中；选了没量到 = 没装（如实提示，不静默装作成功）。 */
const fontStatusValue = computed<FontStatus>(() => detectFontStatus(appearance.value?.editorFamily ?? null))

const fontStatusText = computed(() => {
  const current = appearance.value
  if (!current) return ''
  const size = current.editorSizePt
  if (fontStatusValue.value === 'system') return tr('appearance.font.system', { n: size })
  const family = current.editorFamily ?? ''
  return fontStatusValue.value === 'resolved'
    ? tr('appearance.font.resolved', { family, n: size })
    : tr('appearance.font.missing', { family })
})

/** 点「应用」才落盘：一个字一个字落盘会把偏好文件写成半截族名（还会反复重排编辑器）。 */
async function applyFontFamily() {
  await changeAppearance({ editorFamily: fontDraft.value.trim() })
}

/** 偏好回来了就把输入框对齐（换语言 / 换机器后显示的是**盘上那份**，不是上次的草稿）。 */
watch(appearance, (next) => {
  if (next) fontDraft.value = next.editorFamily ?? ''
})

/** 系统深浅变了：重算一次（不改偏好，只重贴） */
async function refreshAppearance() {
  try {
    const payload = await appearanceGet(systemDark.value)
    appearance.value = payload.appearance
    applyAppearance(payload.dom)
  } catch {
    // 读不到就不动（不把外观失败放大成界面故障）
  }
}

/**
 * 活动栏的显示面：**顺序与组成由清单派生**（核心项 + 插件项），文案与图标语义仍取自
 * `activityBar.ts`（那两样是"视图自己的事"，不归清单）。
 *
 * `ready` 的口径：
 *   · 核心项 ⇒ 由 `CORE_ACTIVITY_ITEMS` 定（它们是宿主自带的）；
 *   · 插件项 ⇒ **取自清单的 `implemented`** —— 本轮两个插件都是 `false`，
 *     所以点进去**如实显示"未开工"**（不假装能点、也不藏起来）。
 */
const sections = computed(() =>
  derivedActivityItems().map((id) => {
    const plugin = pluginById(id)
    return {
      id,
      label: itemTitle(id),
      glyph: itemGlyph(id),
      ready: CORE_ACTIVITY_ITEMS.includes(id) ? true : (plugin?.implemented ?? false),
    }
  }),
)

onMounted(async () => {
// 视图装配：**先核心、后插件**（插件装配要读清单，所以先起装载、装上时再登记）。
// `loadPlugins()` 不 await：界面先起来，清单到位后自动补上插件入口（避免白屏风险）。
registerCoreSlots()
void loadPlugins().then(() => installPlugins())

  info.value = await appInfo()
  // 外观：读一次偏好并贴上（**读不到就按缺省贴** —— 外观读失败不该挡住界面）
  try {
    const payload = await appearanceGet(systemDark.value)
    appearance.value = payload.appearance
    appearanceWarning.value = payload.warning ?? ''
    applyAppearance(payload.dom)
  } catch {
    applyAppearance({ ...DEFAULT_APPEARANCE_DOM, nebula: systemDark.value, isDark: systemDark.value })
  }
  darkQuery?.addEventListener('change', onSystemChange)
  window.addEventListener('keydown', onGlobalKeydown)
})

function onSystemChange(event: MediaQueryListEvent) {
  systemDark.value = event.matches
  void refreshAppearance()
}

onBeforeUnmount(() => {
  darkQuery?.removeEventListener('change', onSystemChange)
  window.removeEventListener('keydown', onGlobalKeydown)
})

function onSelect(id: ActivityBarItemId) {
  setActive(id)
}
</script>

<template>
  <div class="shell">
    <TitleBar
      :info="info"
      :item="activeItem"
      :language="uiLanguage"
      @search-submit="openPaletteWithSearch"
    />
    <!-- 星云皮肤（2.8）：只在「星空紫 + 深色 + 开关开」时由 data-nebula 显形；纯装饰、不吃点击 -->
    <div class="nebula" aria-hidden="true"></div>
    <!-- 命令面板（2.9）：Ctrl+K 开关；清单在 shell/commands.ts，匹配排序在 Rust 侧 -->
    <CommandPalette
      :open="paletteOpen"
      :language="uiLanguage"
      :view="activeItem === 'workspace' ? 'workspace' : 'database'"
      :workspace-root="workspaceRoot"
      @close="paletteOpen = false"
      @run="runCommand"
:objects="paletteObjects"
      :recent-files="recentFiles"
      :ranked-commands="rankedCommands"
      :seed-query="paletteSeed"
      @open="openFromPalette"
    />
    <p v-if="commandNote" class="shell__command-note">{{ commandNote }}</p>
    <p v-else class="shell__command-hint">{{ tr('shell.commandHint') }}</p>
    <!-- 外观控件：深浅轴 × 配色轴 + 皮肤开关（规则全在 Rust 侧，这里只改值） -->
    <div v-if="appearance" class="appearance">
      <label class="appearance__field">
        <span>{{ tr('appearance.mode') }}</span>
        <select
          :value="appearance.mode"
          @change="changeAppearance({ mode: ($event.target as HTMLSelectElement).value as AppearancePref['mode'] })"
        >
          <option v-for="m in MODE_LABELS" :key="m.value" :value="m.value">{{ tr(m.key as never) }}</option>
        </select>
      </label>
      <label class="appearance__field">
        <span>{{ tr('appearance.scheme') }}</span>
        <select
          :value="appearance.scheme"
          @change="changeAppearance({ scheme: ($event.target as HTMLSelectElement).value as AppearancePref['scheme'] })"
        >
          <option v-for="s in SCHEME_LABELS" :key="s.value" :value="s.value">{{ tr(s.key as never) }}</option>
        </select>
      </label>
      <label class="appearance__check" :title="tr('appearance.nebula.tip')">
        <input
          type="checkbox"
          :checked="appearance.nebulaSkin"
          @change="changeAppearance({ nebulaSkin: ($event.target as HTMLInputElement).checked })"
        />
        {{ tr('appearance.nebula') }}
      </label>
      <span v-if="appearanceWarning" class="appearance__warn" :title="appearanceWarning">
        {{ tr('appearance.warning') }}
      </span>
      <!-- 编辑器字体（FR-EDIT-26 字体面）：族名可挑可手输、字号 9~20 一档一档来。
           挑完先**说清当前实际在用的是什么**（没装就如实说「已回落」），再给一行真字体预览 ——
           只写「已应用」而不显示实际字形，等于让用户自己猜。 -->
      <label class="appearance__field">
        <span>{{ tr('appearance.font.family') }}</span>
        <input
          v-model="fontDraft"
          class="appearance__input"
          list="ds-font-choices"
          data-testid="font-family-input"
          :placeholder="tr('appearance.font.placeholder')"
          @keydown.enter.prevent="applyFontFamily"
        />
        <datalist id="ds-font-choices">
          <option v-for="name in FONT_CHOICES" :key="name" :value="name" />
        </datalist>
        <button type="button" class="appearance__apply" data-testid="font-apply" @click="applyFontFamily">
          {{ tr('appearance.font.apply') }}
        </button>
      </label>
      <label class="appearance__field">
        <span>{{ tr('appearance.font.size') }}</span>
        <select
          :value="appearance.editorSizePt"
          data-testid="font-size"
          @change="changeAppearance({ editorSizePt: Number(($event.target as HTMLSelectElement).value) })"
        >
          <option v-for="n in FONT_SIZE_CHOICES" :key="n" :value="n">{{ n }}</option>
        </select>
      </label>
      <span
        class="appearance__hint"
        :class="{ 'appearance__hint--warn': fontStatusValue === 'missing' }"
        data-testid="font-status"
        >{{ fontStatusText }}</span
      >
      <div class="appearance__font-preview" aria-hidden="true">SELECT id, name FROM users WHERE id = 1;</div>
    </div>
    <div class="shell__body">
      <SideBar
        :sections="sections"
        :active="activeItem"
        :language="uiLanguage"
        @select="onSelect"
      />
      <main class="shell__main">
        <div class="shell__stack">
          <!-- 当前视图：**一律查表**（核心视图与插件视图同一张表）。
                 查不到 ⇒ 不画（插件未装 / 视图未登记），**不报错** —— 契约 §3.52-④。 -->
            <component
              :is="viewComponent"
              v-if="viewComponent"
              v-bind="viewProps"
              @push-panel="pushPanel"
              @result-stats="onResultStats"
              @root-changed="workspaceRoot = $event"
            />
            <p v-else class="shell__placeholder">
            {{ itemTitle(activeItem) }}视图尚未开工（⬜ 不半建）。
          </p>
        </div>
        <!-- 底部面板（图里的 问题 / 输出 / 终端 / 调试控制台；后两个如实标「未开工」） -->
        <BottomPanel
          v-if="panelOpen"
          :language="uiLanguage"
          :entries="panelEntries"
          :problems="panelProblems"
          @collapse="panelOpen = false"
        />
        <button
          v-else
          class="shell__panel-open"
          type="button"
          :title="tr('shell.panel.expand')"
          @click="panelOpen = true"
        >
          ⌃ {{ tr('shell.panel.toggle') }}
        </button>
      </main>
    </div>
    <StatusBar :info="info" :rows="rows" :cols="cols" :loaded="loaded" :total="total" :language="uiLanguage" />
    <!-- 智能体设置弹层（FR-AI-01）：入口 = 命令面板「智能体设置…」 -->
    <AgentSettingsDialog :open="agentSettingsOpen" :language="uiLanguage" @close="agentSettingsOpen = false" />
  </div>
</template>

<style scoped>
.shell {
  display: flex;
  flex-direction: column;
  height: 100vh;
  background: var(--ds-color-surface-window);
  color: var(--ds-color-text-primary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-body-size);
}

.shell__body {
  display: flex;
  flex: 1;
  min-height: 0;
}

.shell__main {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  background: var(--ds-color-surface-content);
}

.shell__stack {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
}

/* 折叠后的面板入口（贴在底边） */
.shell__panel-open {
  flex: none;
  height: var(--ds-metric-status-bar-height);
  border: none;
  border-top: var(--ds-metric-hairline) solid var(--ds-hairline);
  background: var(--ds-color-surface-panel);
  color: var(--ds-color-text-secondary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  cursor: pointer;
  text-align: left;
  padding: 0 var(--ds-spacing-s);
}

.shell__panel-open:hover {
  color: var(--ds-color-text-primary);
}

.shell__notice {
  margin: 0;
  padding: var(--ds-spacing-s) var(--ds-spacing-m);
  color: var(--ds-color-text-secondary);
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
  font-size: var(--ds-font-caption-size);
}

.shell__placeholder {
  padding: var(--ds-spacing-l);
  color: var(--ds-color-text-secondary);
}

/* ── 星云皮肤（2.8）───────────────────────────────────────────────────────────
   只在 `data-nebula='on'` 时显形（那个属性由领域层三个条件算出来：星空紫 + 深色 + 开关开）。
   **纯装饰**：`pointer-events: none` 不吃点击；用两层径向渐变 + 一层点状星空做"星云"。
   颜色只走令牌（棘轮守着）—— 不落系统色。 */
.nebula {
  position: fixed;
  inset: 0;
  z-index: 0;
  pointer-events: none;
  display: none;
}

:root[data-nebula='on'] .nebula {
  display: block;
  background:
    radial-gradient(ellipse at 18% 12%, var(--ds-color-accent-accentGlow) 0%, transparent 42%),
    radial-gradient(ellipse at 82% 78%, var(--ds-color-accent-accentGlow) 0%, transparent 46%),
    radial-gradient(circle at 62% 28%, var(--ds-color-text-bright) 0, transparent 2px),
    radial-gradient(circle at 28% 62%, var(--ds-color-text-bright) 0, transparent 1.5px),
    radial-gradient(circle at 74% 46%, var(--ds-color-text-bright) 0, transparent 1.5px),
    radial-gradient(circle at 42% 84%, var(--ds-color-text-bright) 0, transparent 1px);
  opacity: 0.55;
}

/* 外观控件：贴在内容之上，但只占标题栏那一行的高度 */
.appearance {
  position: relative;
  z-index: 2;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--ds-spacing-s);
  padding: var(--ds-spacing-xs) var(--ds-spacing-m);
  background: var(--ds-color-surface-panel);
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
  font-size: var(--ds-font-caption-size);
}

.appearance__field {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
}

.appearance__field select {
  height: var(--ds-metric-control-height);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
}

.appearance__check {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
}

.appearance__warn {
  color: var(--ds-color-status-warning);
}

/* 字体面（FR-EDIT-26）：输入框 / 应用键 / 一句「当前实际在使用」 / 一行真字体预览。
   预览**故意**吃 `--ds-editor-font-*` 两个自定义属性 —— 它显示的就是编辑器此刻的字形，
   换成静态的等宽样张就成了"假样张"（用户看不出自己挑的字体到底生效了没有）。 */
.appearance__input {
  width: 11rem;
  height: var(--ds-metric-control-height);
  padding: 0 var(--ds-spacing-xs);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: inherit;
}

.appearance__input:focus-visible,
.appearance__apply:focus-visible {
  outline: var(--ds-metric-hairline) solid var(--ds-color-accent-accent);
  outline-offset: 1px;
}

.appearance__apply {
  height: var(--ds-metric-control-height);
  padding: 0 var(--ds-spacing-s);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  cursor: pointer;
}

.appearance__apply:hover {
  border-color: var(--ds-color-accent-accent);
}

.appearance__hint {
  color: var(--ds-color-text-tertiary);
  font-variant-numeric: tabular-nums;
}

/* 「没装」那档要更重：它意味着用户挑的族**没生效**，与「已生效」不能长一个样 */
.appearance__hint--warn {
  color: var(--ds-color-status-warning);
}

.appearance__font-preview {
  flex: 1 1 100%;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  color: var(--ds-color-text-secondary);
  background: var(--ds-color-surface-content);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-editor-font-family, var(--ds-font-stack-mono));
  font-size: var(--ds-editor-font-size, 13px);
}

/* 命令面板的入口提示与回执（**做不到的事要说出来**，不静默） */
.shell__command-hint,
.shell__command-note {
  margin: 0;
  padding: var(--ds-spacing-xs) var(--ds-spacing-m);
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
}

.shell__command-note {
  color: var(--ds-color-status-warning);
}
</style>
