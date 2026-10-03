<script setup lang="ts">
// 活动栏（窄条）—— **只负责显示与点击**；顺序、文案、图标语义全部来自 `activityBar.ts`
// （视图里不许再排一次顺序，也不许各存一份文案）。

import type { ActivityBarItemId } from './activityBar'
import { t as translate, type UiLanguage } from '../i18n'

export interface ActivityBarSection {
  readonly id: ActivityBarItemId
  readonly label: string
  /** 图标语义名（不是 SF Symbol 名）；窄条上图标就是全部信息量，故与 tooltip 同源 */
  readonly glyph: string
  readonly ready: boolean
}

const props = defineProps<{
  sections: readonly ActivityBarSection[]
  active: ActivityBarItemId
  /** 界面语言（由外壳传下来；不给就按中文） */
  language?: UiLanguage
}>()

/** 本组件的文案帮手（语言由外壳给）。 */
function tr(key: Parameters<typeof translate>[0], vars?: Record<string, string | number>): string {
  return translate(key, props.language ?? 'zh-Hans', vars)
}
const emit = defineEmits<{ select: [id: ActivityBarItemId] }>()

/**
 * 活动栏的**短标签**：46px 的窄条放不下四字标签，只放两个字。
 *
 * 为什么短标签集中在这里：文案的**语义**来自 `activityBar.ts`（那里是唯一出处），
 * 这里只是"窄条上的缩略显示"。两处各写一份的话，改一处就会对不上。
 */
function shortLabel(label: string): string {
  const map: Record<string, string> = {
    工作区: '工作',
    数据库: '数据',
    笔记: '笔记',
    复盘: '复盘',
  }
  return map[label] ?? label.slice(0, 2)
}
</script>

<template>
  <nav class="sidebar" role="tablist" :aria-label="tr('sidebar.aria')">
    <button
      v-for="section in sections"
      :key="section.id"
      class="sidebar__item"
      :class="{ 'sidebar__item--active': section.id === active, 'sidebar__item--pending': !section.ready }"
      type="button"
      role="tab"
      :aria-selected="section.id === active"
      :aria-label="section.ready ? section.label : tr('sidebar.notReady', { name: section.label })"
      :title="section.ready ? section.label : tr('sidebar.notReady', { name: section.label })"
      :data-glyph="section.glyph"
      @click="emit('select', section.id)"
    >
      <!-- 契约：**活动栏 46px**（`Docs/概要设计.md` L218「活动栏 46、侧栏 248」）。
           之前误用了 `--ds-metric-sidebar-width`（248px，那是给侧栏面板的），
           于是活动栏看起来像一块导航板 —— 这是本侧的实现错误，不是契约问题。 -->
      <span class="sidebar__glyph" aria-hidden="true">{{ section.glyph }}</span>
      <span class="sidebar__short">{{ shortLabel(section.label) }}</span>
      <span v-if="!section.ready" class="sidebar__mark" aria-hidden="true">⬜</span>
    </button>
  </nav>
</template>

<style scoped>
.sidebar {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-hair);
  /* **活动栏宽度走活动栏令牌**（46px），不是侧栏令牌（248px） */
  width: var(--ds-metric-activity-bar-width);
  flex: 0 0 auto;
  padding: var(--ds-spacing-xs) 0;
  background: var(--ds-color-surface-sidebar);
  border-right: var(--ds-metric-hairline) solid var(--ds-hairline);
}

.sidebar__item {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: var(--ds-spacing-hair);
  width: 100%;
  min-height: calc(var(--ds-metric-control-height) * 2);
  padding: var(--ds-spacing-xs) 0;
  background: transparent;
  color: var(--ds-color-text-secondary);
  border: 0;
  border-left: 2px solid transparent;
  font-size: var(--ds-font-caption-size);
  text-align: center;
  cursor: pointer;
}

.sidebar__glyph {
  font-size: var(--ds-metric-activity-icon-size);
  line-height: 1;
}

.sidebar__short {
  font-size: var(--ds-font-caption-size);
  line-height: 1;
}

.sidebar__item:hover {
  background: var(--ds-color-surface-panel);
  color: var(--ds-color-text-primary);
}

.sidebar__item--active {
  background: var(--ds-color-surface-raised);
  border-left-color: var(--ds-color-accent-accent);
  color: var(--ds-color-text-primary);
}

.sidebar__item--pending {
  color: var(--ds-color-text-tertiary);
}

.sidebar__mark {
  font-size: var(--ds-font-caption-size);
  line-height: 1;
}
</style>
