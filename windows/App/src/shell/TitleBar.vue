<script setup lang="ts">
import type { AppInfo } from '../ipc'

defineProps<{ info: AppInfo | null }>()
</script>

<template>
  <header class="titlebar">
    <span class="titlebar__product">Doyah Studio</span>
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
