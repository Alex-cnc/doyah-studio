<!--
  底部面板（布局对齐 macOS 封面图）

  图里有四个页签：**问题 / 输出 / 终端 / 调试控制台**。本版的处理：
  - **输出** 与 **问题**：真能收东西 —— 由外层（数据库视图 / 工作区视图）通过 `entries` 喂进来；
    每条带级别（普通 / 警告 / 出错）与时刻。
  - **终端**（2.7 段 · 第二片 S-9b；第四片 S-9d 薄壳化）：**接真会话** —— 进入页签按需起一个会话，键入走
    `terminalWrite`、输出靠 `terminalRead` 循环取回、页签关 / 组件卸载走 `terminalClose`。
    **会话页签条**支持新建 / 切换 / 关闭，**每个页签一条独立会话**。渲染源 = Rust 桥接层给的
    `chunk.screen`（领域层屏幕模型投影）；**设备查询（`ESC[6n`）回话已归 Rust 桥接层单点**，
    前端不再扫查询、不再回话（纯逻辑在 `./terminal.ts`，本组件只做接线）。
    本片 `terminalWrite` 只余**键盘输入**一处调用。
  - **调试控制台**：本版没有调试器，如实标注「未开工」（点进去看到的是一句说明，不放假界面）。

  为什么早前把「未开工」也留在面板里：图的骨架里这个面板是常驻的，**留格子比留空白更诚实**；
  现在终端那格已经通了，格子就该换成真东西，而不是继续挂着一句「未开工」。
-->
<script setup lang="ts">
import { computed, onBeforeUnmount, ref } from 'vue'
import { t as translate, type UiLanguage } from '../i18n'
import { terminalClose, terminalOpen, terminalRead, terminalWrite, type TerminalChunk } from '../ipc'
import { createSessionState, feed, keyToBytes, neighborAfterClose, type TerminalSessionState } from './terminal'

/** 面板里的一条输出（级别决定颜色）。 */
export interface PanelEntry {
  /** 内容 */
  text: string
  /** `info`（普通）/ `warn`（警告）/ `error`（出错） */
  level: 'info' | 'warn' | 'error'
  /** 来源（哪个视图 / 哪一步），便于分辨 */
  source?: string
  /** 时刻（Unix 毫秒；不传就不显示时间） */
  at?: number
}

const props = defineProps<{
  /** 界面语言（由外壳传下来；本组件的文案都走语言表） */
  language?: UiLanguage
  /** 输出页签的内容 */
  entries: readonly PanelEntry[]
  /** 问题页签的内容（比输出更少、更\"要处理\"的那些） */
  problems?: readonly PanelEntry[]
}>()

const emit = defineEmits<{ (event: 'collapse'): void }>()

/** 本组件的文案帮手（语言由外壳给；不给就按中文）。 */
function tr(key: Parameters<typeof translate>[0], vars?: Record<string, string | number>): string {
  return translate(key, props.language ?? 'zh-Hans', vars)
}

type TabId = 'problems' | 'output' | 'terminal' | 'debug'

/** 各页签的标号（问题数、终端会话数实时跟着走）。 */
const problems = computed(() => props.problems ?? [])

/** 一个界面侧会话：Rust 给的会话 id + 我们自己编的序号（标题用，关闭不回收）+ 纯逻辑状态。 */
interface LiveSession {
  id: number
  /** 会话在页签条里的显示序号（从 1 起，只增不减 —— 关掉 1 号后新开的不叫「1 号」）。 */
  ordinal: number
  state: TerminalSessionState
}

/** 起会话的默认几何（与 Rust 侧缺省一致：80×24）。 */
const DEFAULT_COLS = 80
const DEFAULT_ROWS = 24
/** 读循环两趟之间的间隔（没有输出时别空转）。 */
const READ_GAP_MS = 40

const sessions = ref<LiveSession[]>([])
const activeSession = ref<number | null>(null)
/** 最近一次终端操作的失败（**如实显示**，不静默吞掉）。 */
const lastError = ref<string | null>(null)
let nextOrdinal = 0

// 读循环的停止令牌：每个会话一个号，关会话 / 卸载时把号作废，循环下一跳自己退出。
let disposed = false
let tokenSeq = 0
const runTokens = new Map<number, number>()

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms)
  })
}

/** 把 ipc 抛出来的东西（字符串或结构化失败）拼成一句可读的话。 */
function describeError(error: unknown): string {
  if (typeof error === 'string') return error
  if (error && typeof error === 'object') {
    const shape = error as { message?: unknown; hint?: unknown }
    if (typeof shape.message === 'string') {
      return typeof shape.hint === 'string' ? `${shape.message} ${shape.hint}` : shape.message
    }
  }
  return String(error)
}

const tabs = computed(() => [
  { id: 'problems' as TabId, label: tr('panel.problems'), count: problems.value.length, ready: true },
  { id: 'output' as TabId, label: tr('panel.output'), count: props.entries.length, ready: true },
  { id: 'terminal' as TabId, label: tr('panel.terminal'), count: sessions.value.length, ready: true },
  { id: 'debug' as TabId, label: tr('panel.debug'), count: 0, ready: false },
])

const active = ref<TabId>('output')

const sessionIds = computed(() => sessions.value.map((session) => session.id))
const activeState = computed(
  () => sessions.value.find((session) => session.id === activeSession.value)?.state ?? null,
)

function sessionOf(id: number): LiveSession | undefined {
  return sessions.value.find((session) => session.id === id)
}

/** 起一个会话并接上读循环（失败如实显示，不拿假会话冒充成功）。 */
async function openSession(): Promise<void> {
  try {
    const id = await terminalOpen({ cols: DEFAULT_COLS, rows: DEFAULT_ROWS })
    nextOrdinal += 1
    sessions.value = [...sessions.value, { id, ordinal: nextOrdinal, state: createSessionState() }]
    activeSession.value = id
    lastError.value = null
    void pump(id)
  } catch (error) {
    lastError.value = describeError(error)
  }
}

/** 读循环：一轮一轮把字节取回来喂给纯逻辑（**只存投影**）。回话归 Rust 桥接层单点，这里不写回。 */
async function pump(id: number): Promise<void> {
  tokenSeq += 1
  const token = tokenSeq
  runTokens.set(id, token)
  while (!disposed && runTokens.get(id) === token) {
    const session = sessionOf(id)
    if (!session || session.state.eof) return
    let chunk: TerminalChunk
    try {
      chunk = await terminalRead(id, 50)
    } catch (error) {
      // 读不回来就停这一路，并把原因**显示出来**（不是吞掉当没事）。
      lastError.value = describeError(error)
      return
    }
    if (disposed || runTokens.get(id) !== token) return
    const current = sessionOf(id)
    if (!current) return
    // 纯逻辑只存领域层投影（渲染源）；`ESC[6n` 回话已归 Rust 桥接层单点，这里**不再写回**。
    current.state = feed(current.state, chunk)
    if (chunk.eof) return
    await delay(READ_GAP_MS)
  }
}

/** 关闭一个会话：先停它的读循环，再从页签条摘掉，最后真关（失败如实显示）。 */
async function closeSession(id: number): Promise<void> {
  runTokens.delete(id)
  const ids = sessionIds.value
  sessions.value = sessions.value.filter((session) => session.id !== id)
  if (activeSession.value === id) activeSession.value = neighborAfterClose(ids, id)
  try {
    await terminalClose(id)
  } catch (error) {
    // 会话可能已自行结束；关不掉**如实显示**，不静默吞掉。
    lastError.value = describeError(error)
  }
}

function activate(id: number): void {
  activeSession.value = id
}

/** 切入某个页签；终端页签**按需**起会话（一条都没有时才起）。 */
function selectTab(id: TabId): void {
  active.value = id
  if (id === 'terminal' && sessions.value.length === 0) void openSession()
}

/** 键盘 → 写进 pty；认不出的键交回浏览器（不拦）。 */
function onKey(event: KeyboardEvent): void {
  const id = activeSession.value
  if (id === null) return
  const bytes = keyToBytes(event.key, { ctrl: event.ctrlKey, alt: event.altKey })
  if (bytes === null) return
  event.preventDefault()
  void terminalWrite(id, bytes).catch((error: unknown) => {
    lastError.value = describeError(error)
  })
}

onBeforeUnmount(() => {
  disposed = true
  runTokens.clear()
  const ids = sessionIds.value
  sessions.value = []
  // 组件没了就无处显示错误；收尾**尽力**关掉每个会话（不留进程 / 线程在后面）。
  void Promise.allSettled(ids.map((id) => terminalClose(id)))
})

/** 时刻显示（只给\"时:分:秒\"，日期对这个面板没意义）。 */
function clock(at?: number): string {
  if (!at) return ''
  const date = new Date(at)
  const pad = (value: number) => String(value).padStart(2, '0')
  return `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`
}

const activeEntries = computed(() => (active.value === 'problems' ? problems.value : props.entries))
</script>

<template>
  <section class="panel" :aria-label="tr('panel.aria')">
    <div class="panel__tabs" role="tablist">
      <button
        v-for="tab in tabs"
        :key="tab.id"
        class="panel__tab"
        :class="{ 'panel__tab--active': active === tab.id, 'panel__tab--idle': !tab.ready }"
        type="button"
        role="tab"
        :aria-selected="active === tab.id"
        :title="tab.ready ? tab.label : tr('panel.notReady', { name: tab.label })"
        @click="selectTab(tab.id)"
      >
        {{ tab.label }}
        <span v-if="tab.count > 0" class="panel__tab-count">{{ tab.count }}</span>
      </button>
      <span class="panel__spacer" />
      <button class="panel__act" type="button" :title="tr('panel.collapse')" @click="emit('collapse')">⌄</button>
    </div>

    <div class="panel__body">
      <!-- 终端页签（2.7 · S-9b）：会话页签条 + 输出区 + 输入行 -->
      <div v-if="active === 'terminal'" class="panel__terminal">
        <div class="panel__sessions" role="tablist" :aria-label="tr('panel.terminal.aria')">
          <button
            v-for="session in sessions"
            :key="session.id"
            class="panel__session"
            :class="{ 'panel__session--active': session.id === activeSession }"
            type="button"
            role="tab"
            :aria-selected="session.id === activeSession"
            @click="activate(session.id)"
          >
            {{ tr('panel.terminal.session', { n: session.ordinal }) }}
            <span
              class="panel__session-close"
              role="button"
              :title="tr('panel.terminal.close')"
              @click.stop="closeSession(session.id)"
              >×</span
            >
          </button>
          <button
            class="panel__session-new"
            type="button"
            :title="tr('panel.terminal.new')"
            @click="openSession"
          >
            ＋
          </button>
        </div>
        <p v-if="lastError" class="panel__term-error">{{ lastError }}</p>
        <p v-if="sessions.length === 0 && !lastError" class="panel__note">
          {{ tr('panel.terminal.empty') }}
        </p>
        <template v-else-if="activeState">
          <pre class="panel__term-out">{{ activeState.screen?.text }}</pre>
          <p v-if="activeState.eof" class="panel__note">
            {{ tr('panel.terminal.ended', { code: activeState.exitCode ?? '—' }) }}
          </p>
        </template>
        <input
          v-if="activeState && !activeState.eof"
          class="panel__term-input"
          type="text"
          :aria-label="tr('panel.terminal.input')"
          :placeholder="tr('panel.terminal.input')"
          @keydown="onKey"
        />
      </div>

      <!-- 调试控制台：本版没有调试器，如实说，不放假界面 -->
      <p v-else-if="active === 'debug'" class="panel__note">{{ tr('panel.debug.note') }}</p>
      <!-- 空的"真"页签：说清"这里会出现什么"，而不是干留白 -->
      <p v-else-if="activeEntries.length === 0" class="panel__note">
        {{ active === 'problems' ? tr('panel.problems.empty') : tr('panel.output.empty') }}
      </p>
      <ol v-else class="panel__list">
        <li
          v-for="(entry, index) in activeEntries"
          :key="index"
          class="panel__line"
          :class="`panel__line--${entry.level}`"
        >
          <span v-if="entry.at" class="panel__time">{{ clock(entry.at) }}</span>
          <span v-if="entry.source" class="panel__source">{{ entry.source }}</span>
          <span class="panel__text">{{ entry.text }}</span>
        </li>
      </ol>
    </div>
  </section>
</template>

<style scoped>
.panel {
  display: flex;
  flex-direction: column;
  /* 面板高度按窗口比例给（窗口小时不至于把主区挤没） */
  height: 22vh;
  min-height: 96px;
  border-top: var(--ds-metric-hairline) solid var(--ds-hairline);
  background: var(--ds-color-surface-panel);
}

.panel__tabs {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-hair);
  height: var(--ds-metric-tab-height);
  padding: 0 var(--ds-spacing-xs);
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
}

.panel__tab {
  display: inline-flex;
  align-items: center;
  gap: var(--ds-spacing-hair);
  height: 100%;
  padding: 0 var(--ds-spacing-s);
  border: none;
  border-bottom: var(--ds-metric-hairline) solid transparent;
  background: transparent;
  color: var(--ds-color-text-secondary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  cursor: pointer;
}

.panel__tab:hover {
  color: var(--ds-color-text-primary);
}

.panel__tab--active {
  color: var(--ds-color-text-bright);
  border-bottom-color: var(--ds-color-accent-accent);
}

/* 未开工的页签：看着就知道不一样，但**仍然可点**（点了会告诉你为什么） */
.panel__tab--idle {
  color: var(--ds-color-text-tertiary);
  font-style: italic;
}

.panel__tab-count {
  color: var(--ds-color-text-tertiary);
}

.panel__spacer {
  flex: 1;
}

.panel__act {
  border: none;
  background: transparent;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-body-size);
  cursor: pointer;
}

.panel__body {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
}

.panel__note {
  margin: 0;
  color: var(--ds-color-text-tertiary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
}

.panel__list {
  margin: 0;
  padding: 0;
  list-style: none;
}

.panel__line {
  display: flex;
  gap: var(--ds-spacing-xs);
  padding: var(--ds-spacing-hair) 0;
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  color: var(--ds-color-text-primary);
}

.panel__line--warn {
  color: var(--ds-color-status-warning);
}

.panel__line--error {
  color: var(--ds-color-status-danger);
}

.panel__time,
.panel__source {
  flex: none;
  color: var(--ds-color-text-tertiary);
}

.panel__text {
  white-space: pre-wrap;
  word-break: break-word;
}

/* ── 终端页签 ─────────────────────────────────────────────────────────── */

.panel__terminal {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  gap: var(--ds-spacing-hair);
}

.panel__sessions {
  display: flex;
  align-items: center;
  flex: none;
  gap: var(--ds-spacing-hair);
}

.panel__session {
  display: inline-flex;
  align-items: center;
  gap: var(--ds-spacing-hair);
  padding: 0 var(--ds-spacing-s);
  border: none;
  border-bottom: var(--ds-metric-hairline) solid transparent;
  background: transparent;
  color: var(--ds-color-text-secondary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  cursor: pointer;
}

.panel__session--active {
  color: var(--ds-color-text-bright);
  border-bottom-color: var(--ds-color-accent-accent);
}

.panel__session-close {
  color: var(--ds-color-text-tertiary);
}

.panel__session-new {
  border: none;
  background: transparent;
  color: var(--ds-color-text-secondary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  cursor: pointer;
}

.panel__term-error {
  margin: 0;
  flex: none;
  color: var(--ds-color-status-danger);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
}

.panel__term-out {
  flex: 1;
  min-height: 0;
  margin: 0;
  overflow: auto;
  white-space: pre-wrap;
  word-break: break-word;
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  color: var(--ds-color-text-primary);
}

.panel__term-input {
  flex: none;
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  background: var(--ds-color-surface-panel);
  color: var(--ds-color-text-primary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  padding: 0 var(--ds-spacing-xs);
}
</style>
