<script setup lang="ts">
// 标题栏 —— 窗口标题由**活动栏项派生**（FR-EDIT-37；契约层口径见 `Core/ActivityBar.swift` 的 `WindowTitle`）：
// 品牌段不翻译、视图段走语言表，拼装只有一处（`windowTitle()`）。

import type { AppInfo } from '../ipc'
import { windowTitle, type ActivityBarItemId } from './activityBar'

defineProps<{ info: AppInfo | null; item: ActivityBarItemId }>()
</script>

<template>
  <header class="titlebar">
    <span class="titlebar__product">{{ windowTitle(item) }}</span>
    <span class="titlebar__hint">Windows 侧（Tauri 2 外壳 · Vue 3 · Rust 领域层）</span>
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
  font-size: var(--ds-font-title-size);
  font-weight: 600;
}

.titlebar__hint {
  flex: 1;
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
}

.titlebar__version {
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}
</style>
