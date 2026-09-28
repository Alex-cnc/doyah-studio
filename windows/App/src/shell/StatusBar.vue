<script setup lang="ts">
import { computed } from 'vue'
import type { AppInfo } from '../ipc'
import { applyTheme, readStoredTheme, storeTheme, type ThemeMode } from '../theme'

const props = defineProps<{
  info: AppInfo | null
  rows: number
  cols: number
  loaded: number
  total: number
}>()

const emit = defineEmits<{ 'update:theme': [mode: ThemeMode] }>()

const mode = computed<ThemeMode>(() => readStoredTheme(window.localStorage))

const backendLabel = computed(() => (props.info ? (props.info.backend === 'tauri' ? 'Rust 领域层（Tauri IPC）' : '浏览器旁路（mock）') : '连接中…'))

function setMode(next: ThemeMode): void {
  storeTheme(window.localStorage, next)
  applyTheme(document.documentElement, next)
  emit('update:theme', next)
}
</script>

<template>
  <footer class="statusbar">
    <span>{{ backendLabel }}</span>
    <span>结果集 {{ rows.toLocaleString() }} 行 × {{ cols }} 列</span>
    <span>本片已取 {{ loaded }} 行 / 逻辑 {{ total.toLocaleString() }} 行</span>
    <span class="statusbar__spacer" />
    <button
      v-for="candidate in (['system', 'light', 'dark'] as ThemeMode[])"
      :key="candidate"
      type="button"
      class="statusbar__theme"
      :class="{ 'statusbar__theme--active': candidate === mode }"
      @click="setMode(candidate)"
    >
      {{ candidate === 'system' ? '跟随系统' : candidate === 'light' ? '浅色' : '深色' }}
    </button>
  </footer>
</template>

<style scoped>
.statusbar {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-m);
  height: var(--ds-metric-status-bar-height);
  padding: 0 var(--ds-spacing-m);
  background: var(--ds-color-surface-window);
  border-top: var(--ds-metric-hairline) solid var(--ds-hairline);
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
}

.statusbar__spacer {
  flex: 1;
}

.statusbar__theme {
  padding: 0 var(--ds-spacing-s);
  background: transparent;
  color: var(--ds-color-text-secondary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-badge);
  font-size: var(--ds-font-caption-size);
  cursor: pointer;
}

.statusbar__theme--active {
  background: var(--ds-color-surface-raised);
  color: var(--ds-color-text-primary);
}
</style>
