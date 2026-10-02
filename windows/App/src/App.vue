<script setup lang="ts">
// 表示层外壳（Windows 侧）—— 本轮把「活动栏 + 窗口标题」按三书落到单点状态上
//
// 契约来源：`Docs/概要设计.md` §8.5.4「一样」清单 + macOS 侧 `Core/ActivityBar.swift`。
// 四模块位与对侧的语义一一对应；**未开工的视图如实标 ⬜**（不半建、不假装能点）。

import { nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import { appInfo, type AppInfo } from './ipc'
import CommandPalette from './shell/CommandPalette.vue'
import TitleBar from './shell/TitleBar.vue'
import { commandById, type Command } from './shell/commands'
import SideBar from './shell/SideBar.vue'
import StatusBar from './shell/StatusBar.vue'
import {
  appearanceGet,
  appearanceSet,
  dbPaletteObjects,
  type Appearance as AppearancePref,
  type DomAppearance,
} from './ipc'
import { applyAppearance, MODE_LABELS, SCHEME_LABELS, systemIsDark } from './shell/appearance'
import DatabaseView from './views/DatabaseView.vue'
import WorkspaceView from './views/WorkspaceView.vue'
import {
  BUILT_ITEMS,
  ITEMS,
  itemGlyph,
  itemTitle,
  type ActivityBarItemId,
} from './shell/activityBar'
import { activeItem, setActive } from './shell/activityBarStore'

const info = ref<AppInfo | null>(null)
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

function onGlobalKeydown(event: KeyboardEvent) {
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
    event.preventDefault()
    paletteOpen.value = !paletteOpen.value
    if (paletteOpen.value) void loadPaletteObjects()
  }
}

/** 执行一条命令：**能做的就做，做不到就如实说**（不假装执行过） */
async function runCommand(command: Command) {
  switch (command.id) {
    case 'appearance.followSystem':
      await changeAppearance({ mode: 'followSystem' })
      return
    case 'appearance.alwaysDark':
      await changeAppearance({ mode: 'alwaysDark' })
      return
    case 'appearance.alwaysLight':
      await changeAppearance({ mode: 'alwaysLight' })
      return
    default:
      // 其余命令要在对应视图里用界面按钮做（那才是**实际执行路径**）；
      // 这里如实说明，而不是"静默什么都不做"。
      commandNote.value = `「${command.title}」请在「${command.view ?? ''}」视图里用界面按钮执行（面板只做发现与分派）`
      setTimeout(() => (commandNote.value = ''), 4000)
  }
}

/** 命令执行的回执（做不到时要说清） */
const commandNote = ref('')
const loaded = ref(0)
const total = ref(0)

// 外观（2.8）：规则在 Rust 侧（`Db/src/appearance.rs`），这里只管"读回来 → 贴到根元素 → 改了就存回去"
const appearance = ref<AppearancePref | null>(null)
const appearanceWarning = ref('')

/** 系统当前深浅（只在"跟随系统"那一档影响结果；监听它才能在系统切换时即时跟随） */
const darkQuery =
  typeof window !== 'undefined' && window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null
const systemDark = ref(systemIsDark())

/** 改了任一项：写回并重贴（**部分更新**，只传改动的那项） */
async function changeAppearance(patch: Partial<Pick<AppearancePref, 'mode' | 'scheme' | 'nebulaSkin'>>) {
  if (!appearance.value) return
  try {
    const payload = await appearanceSet(patch, systemDark.value)
    appearance.value = payload.appearance
    applyAppearance(payload.dom)
  } catch {
    // 存不下去就**不假装配上了**：界面先不动，下次启动会回到上次存下的那份
  }
}

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

/** 活动栏的显示面：顺序、文案、图标语义都从 `activityBar.ts` 派生（视图里不再排一次）。 */
const sections = ITEMS.map((id) => ({
  id,
  label: itemTitle(id),
  glyph: itemGlyph(id),
  ready: BUILT_ITEMS.includes(id),
}))

onMounted(async () => {
  info.value = await appInfo()
  // 外观：读一次偏好并贴上（**读不到就按缺省贴** —— 外观读失败不该挡住界面）
  try {
    const payload = await appearanceGet(systemDark.value)
    appearance.value = payload.appearance
    appearanceWarning.value = payload.warning ?? ''
    applyAppearance(payload.dom)
  } catch {
    applyAppearance({
      dataTheme: null,
      dataScheme: 'stardust',
      nebula: systemDark.value,
      isDark: systemDark.value,
    })
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
    <TitleBar :info="info" :item="activeItem" />
    <!-- 星云皮肤（2.8）：只在「星空紫 + 深色 + 开关开」时由 data-nebula 显形；纯装饰、不吃点击 -->
    <div class="nebula" aria-hidden="true"></div>
    <!-- 命令面板（2.9）：Ctrl+K 开关；清单在 shell/commands.ts，匹配排序在 Rust 侧 -->
    <CommandPalette
      :open="paletteOpen"
      :view="activeItem === 'workspace' ? 'workspace' : 'database'"
      :workspace-root="workspaceRoot"
      @close="paletteOpen = false"
      @run="runCommand"
:objects="paletteObjects"
      :recent-files="recentFiles"
      @open="openFromPalette"
    />
    <p v-if="commandNote" class="shell__command-note">{{ commandNote }}</p>
    <p v-else class="shell__command-hint">Ctrl+K 打开命令面板</p>
    <!-- 外观控件：深浅轴 × 配色轴 + 皮肤开关（规则全在 Rust 侧，这里只改值） -->
    <div v-if="appearance" class="appearance">
      <label class="appearance__field">
        <span>外观</span>
        <select
          :value="appearance.mode"
          @change="changeAppearance({ mode: ($event.target as HTMLSelectElement).value as AppearancePref['mode'] })"
        >
          <option v-for="m in MODE_LABELS" :key="m.value" :value="m.value">{{ m.label }}</option>
        </select>
      </label>
      <label class="appearance__field">
        <span>配色</span>
        <select
          :value="appearance.scheme"
          @change="changeAppearance({ scheme: ($event.target as HTMLSelectElement).value as AppearancePref['scheme'] })"
        >
          <option v-for="s in SCHEME_LABELS" :key="s.value" :value="s.value">{{ s.label }}</option>
        </select>
      </label>
      <label class="appearance__check" title="只在「星空紫 + 深色」时看得出来">
        <input
          type="checkbox"
          :checked="appearance.nebulaSkin"
          @change="changeAppearance({ nebulaSkin: ($event.target as HTMLInputElement).checked })"
        />
        星云皮肤
      </label>
      <span v-if="appearanceWarning" class="appearance__warn" :title="appearanceWarning">
        外观偏好读不出来（按缺省走）
      </span>
    </div>
    <div class="shell__body">
      <SideBar :sections="sections" :active="activeItem" @select="onSelect" />
      <main class="shell__main">
        <!-- 数据库：**真库链路**（连库 → 对象树 → SQL → 结果），驱动在 Rust 外壳 -->
        <DatabaseView v-if="activeItem === 'database'" />
        <WorkspaceView
          v-else-if="activeItem === 'workspace'"
          :open-file-signal="openFileSignal"
          @root-changed="workspaceRoot = $event"
        />
        <p v-else class="shell__placeholder">
          {{ itemTitle(activeItem) }}视图尚未开工（⬜ 不半建）。
        </p>
      </main>
    </div>
    <StatusBar :info="info" :loaded="loaded" :total="total" />
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
