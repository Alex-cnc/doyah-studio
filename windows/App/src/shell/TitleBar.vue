<script setup lang="ts">
// 标题栏 —— 窗口标题由**活动栏项派生**（FR-EDIT-37；契约层口径见 `Core/ActivityBar.swift` 的 `WindowTitle`）：
// 品牌段不翻译、视图段走语言表，拼装只有一处（`windowTitle()`）。
//
// 居中搜索栏（FR-EDIT-37 + 内测 甲1）：宽度**由纯函数给**（`shell/titleBarSearch.ts`，8 例单测），
// 界面只负责把算出来的宽度摆上去。**放不下就整条不显示**（不硬塞一条窄缝遮住标题）。

import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import type { AppInfo } from '../ipc'
import { windowTitle, type ActivityBarItemId } from './activityBar'
import { estimateTitleWidth, searchFieldWidth } from './titleBarSearch'

const props = defineProps<{ info: AppInfo | null; item: ActivityBarItemId }>()

// 标题栏搜索是**全局搜索**：把词抛给外壳去开命令面板（它已能搜 功能 / 文件 / 对象）
const emit = defineEmits<{ (event: 'search-submit', query: string): void }>()

/** 窗口宽度（跟随缩放变化）—— 唯一的输入，其余都从它算出来。 */
const windowWidth = ref(typeof window !== 'undefined' ? window.innerWidth : 0)

function measure() {
  windowWidth.value = window.innerWidth
}

onMounted(() => window.addEventListener('resize', measure))
onBeforeUnmount(() => window.removeEventListener('resize', measure))

const title = computed(() => windowTitle(props.item))
const titleWidth = computed(() => estimateTitleWidth(title.value))
/** `0` = 这一档放不下 ⇒ 整条不显示（回车入口仍在 ⌘K / 命令面板）。 */
const fieldWidth = computed(() => searchFieldWidth(windowWidth.value, titleWidth.value))
const query = ref('')
</script>

<template>
  <header class="titlebar">
    <span class="titlebar__product">{{ title }}</span>
    <input
      v-if="fieldWidth > 0"
      v-model="query"
      class="titlebar__search"
      type="search"
      :style="{ width: `${fieldWidth}px` }"
      :placeholder="`搜索（当前：${title}）`"
      aria-label="工作区搜索"
    />
    <!-- 放不下时不塞窄缝：如实告诉人这一档没有搜索栏，入口还在快捷键 -->
    <span v-else class="titlebar__search-hidden" title="窗口太窄：搜索栏让位给标题（用快捷键搜索）">
      搜索栏让位
    </span>
    <span class="titlebar__version">{{ info ? `v${info.version}` : '…' }}</span>
  </header>
</template>

<style scoped>
.titlebar {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-s);
  height: var(--ds-metric-toolbar-height);
  padding: 0 var(--ds-spacing-m);
  background: var(--ds-color-surface-window);
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
}

.titlebar__product {
  flex: 0 0 auto;
  font-size: var(--ds-font-title-size);
  font-weight: 600;
}

/* 居中：左右各一个弹性槽，宽度由纯函数给（不是 flex 自由伸缩） */
.titlebar__search {
  flex: 0 0 auto;
  margin: 0 auto;
  height: var(--ds-metric-control-height);
  padding: 0 var(--ds-spacing-s);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
}

.titlebar__search-hidden {
  flex: 1;
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
  text-align: center;
}

.titlebar__version {
  flex: 0 0 auto;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}
</style>
