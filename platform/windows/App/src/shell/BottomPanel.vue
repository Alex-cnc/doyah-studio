<!--
  底部面板（布局对齐 macOS 封面图）

  图里有四个页签：**问题 / 输出 / 终端 / 调试控制台**。本版的处理：
  - **输出** 与 **问题**：真能收东西 —— 由外层（数据库视图 / 工作区视图）通过 `entries` 喂进来；
    每条带级别（普通 / 警告 / 出错）与时刻。
  - **终端**：**如实标注"未开工"**（那件卡的活还没通），点进去看到的是一句说明，
    **不假装能用、不放一个假提示符**。
  - **调试控制台**：同上，本版没有调试器，如实标注。

  为什么把"未开工"也留在面板里：图的骨架里这个面板是常驻的，**留格子比留空白更诚实** ——
  用户点一下就知道了，而不是猜"这里为什么空着"。
-->
<script setup lang="ts">
import { computed, ref } from 'vue'
import { t as translate, type UiLanguage } from '../i18n'

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
  /** 问题页签的内容（比输出更少、更"要处理"的那些） */
  problems?: readonly PanelEntry[]
}>()

const emit = defineEmits<{ (event: 'collapse'): void }>()

/** 本组件的文案帮手（语言由外壳给；不给就按中文）。 */
function tr(key: Parameters<typeof translate>[0], vars?: Record<string, string | number>): string {
  return translate(key, props.language ?? 'zh-Hans', vars)
}

type TabId = 'problems' | 'output' | 'terminal' | 'debug'

/** 各页签的标号（问题数实时跟着走）。 */
const problems = computed(() => props.problems ?? [])

const tabs = computed(() => [
  { id: 'problems' as TabId, label: tr('panel.problems'), count: problems.value.length, ready: true },
  { id: 'output' as TabId, label: tr('panel.output'), count: props.entries.length, ready: true },
  { id: 'terminal' as TabId, label: tr('panel.terminal'), count: 0, ready: false },
  { id: 'debug' as TabId, label: tr('panel.debug'), count: 0, ready: false },
])

const active = ref<TabId>('output')

/** 时刻显示（只给"时:分:秒"，日期对这个面板没意义）。 */
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
        @click="active = tab.id"
      >
        {{ tab.label }}
        <span v-if="tab.count > 0" class="panel__tab-count">{{ tab.count }}</span>
      </button>
      <span class="panel__spacer" />
      <button class="panel__act" type="button" :title="tr('panel.collapse')" @click="emit('collapse')">⌄</button>
    </div>

    <div class="panel__body">
      <!-- 未开工的两个页签：如实说，不放假界面 -->
      <p v-if="active === 'terminal' || active === 'debug'" class="panel__note">
        {{
          active === 'terminal' ? tr('panel.terminal.note') : tr('panel.debug.note')
        }}
      </p>
      <!-- 空的"真"页签：说清"这里会出现什么"，而不是干留白 -->
      <p v-else-if="activeEntries.length === 0" class="panel__note">
        {{
          active === 'problems' ? tr('panel.problems.empty') : tr('panel.output.empty')
        }}
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
</style>
