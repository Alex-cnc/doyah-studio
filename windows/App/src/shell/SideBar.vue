<script setup lang="ts">
// 活动栏（窄条）—— **只负责显示与点击**；顺序、文案、图标语义全部来自 `activityBar.ts`
// （视图里不许再排一次顺序，也不许各存一份文案）。

import type { ActivityBarItemId } from './activityBar'

export interface ActivityBarSection {
  readonly id: ActivityBarItemId
  readonly label: string
  /** 图标语义名（不是 SF Symbol 名）；窄条上图标就是全部信息量，故与 tooltip 同源 */
  readonly glyph: string
  readonly ready: boolean
}

defineProps<{ sections: readonly ActivityBarSection[]; active: ActivityBarItemId }>()
const emit = defineEmits<{ select: [id: ActivityBarItemId] }>()
</script>

<template>
  <nav class="sidebar" role="tablist" aria-label="视图">
    <button
      v-for="section in sections"
      :key="section.id"
      class="sidebar__item"
      :class="{ 'sidebar__item--active': section.id === active, 'sidebar__item--pending': !section.ready }"
      type="button"
      role="tab"
      :aria-selected="section.id === active"
      :aria-label="section.ready ? section.label : `${section.label}（未开工）`"
      :title="section.ready ? section.label : `${section.label}（未开工）`"
      :data-glyph="section.glyph"
      @click="emit('select', section.id)"
    >
      <span class="sidebar__label">{{ section.label }}</span>
      <span v-if="!section.ready" class="sidebar__mark" aria-hidden="true">⬜</span>
    </button>
  </nav>
</template>

<style scoped>
.sidebar {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-hair);
  width: var(--ds-metric-sidebar-width);
  padding: var(--ds-spacing-s);
  background: var(--ds-color-surface-sidebar);
  border-right: var(--ds-metric-hairline) solid var(--ds-hairline);
}

.sidebar__item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  min-height: var(--ds-metric-control-height);
  padding: 0 var(--ds-spacing-s);
  background: transparent;
  color: var(--ds-color-text-primary);
  border: 1px solid transparent;
  border-radius: var(--ds-radius-control);
  font-size: var(--ds-font-body-size);
  text-align: left;
  cursor: pointer;
}

.sidebar__item:hover {
  background: var(--ds-color-surface-panel);
}

.sidebar__item--active {
  background: var(--ds-color-surface-raised);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
}

.sidebar__item--pending {
  color: var(--ds-color-text-tertiary);
}

.sidebar__mark {
  font-size: var(--ds-font-caption-size);
}
</style>
