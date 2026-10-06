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
 * 活动栏图标：**内联 SVG**（零依赖、不发网络请求、随主题走 `currentColor`）。
 *
 * 键取自契约里的**语义名**（`activityBar.ts` 的 `itemGlyph`：folder / cylinder / note / chart），
 * 所以"哪个视图配什么语义"仍然只有那一处出处；这里只负责把语义画出来。
 *
 * 为什么不用图标字体 / 外部图标包：那要引字体文件或 CDN —— 本侧要求零第三方依赖，
 * 外链还把界面的一部分挂在网上（断网就缺图标）。
 */
const ICON_PATHS: Record<string, string> = {
  // 工作区：文件夹
  folder: 'M3 6.5A1.5 1.5 0 0 1 4.5 5h3.2l1.3 1.6h6.5A1.5 1.5 0 0 1 17 8.1v6.4A1.5 1.5 0 0 1 15.5 16h-11A1.5 1.5 0 0 1 3 14.5z',
  // 数据库：圆柱（上椭圆 + 两条竖边 + 下椭圆）
  cylinder:
    'M10 3c3.3 0 6 .9 6 2s-2.7 2-6 2-6-.9-6-2 2.7-2 6-2zM4 5v10c0 1.1 2.7 2 6 2s6-.9 6-2V5M4 10c0 1.1 2.7 2 6 2s6-.9 6-2',
  // 笔记：一页带折角与两条横线
  note: 'M6 3h5l4 4v10H6zM11 3v4h4M8.5 11h5M8.5 13.5h5',
  // 复盘：柱状图
  chart: 'M4 16V9M9 16V5M14 16v-4M3 16.5h14',
}
function iconPath(glyph: string): string {
  return ICON_PATHS[glyph] ?? ICON_PATHS.folder
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
           老板明确：**栏面只要图标、不要标题文字** —— 视图名靠 `title` 与 `aria-label` 给
           （悬停有提示、读屏有名字），栏面不再被文字占宽。 -->
      <svg
        class="sidebar__glyph"
        viewBox="0 0 20 20"
        fill="none"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
      >
        <path :d="iconPath(section.glyph)" />
      </svg>
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
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  /* 没有文字了 ⇒ 高度 = 图标 + 上下各一份小内边距（不再需要两倍控件高） */
  min-height: calc(var(--ds-metric-activity-icon-size) + var(--ds-spacing-s));
  padding: 0;
  background: transparent;
  color: var(--ds-color-text-secondary);
  border: 0;
  border-left: 2px solid transparent;
  cursor: pointer;
}

.sidebar__glyph {
  display: block;
  width: var(--ds-metric-activity-icon-size);
  height: var(--ds-metric-activity-icon-size);
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

/* 未开工标记做成**角标**：不占栏面宽度、也不再撑高 */
.sidebar__mark {
  position: absolute;
  right: 1px;
  bottom: 0;
  font-size: var(--ds-font-caption-size);
  line-height: 1;
}
</style>
