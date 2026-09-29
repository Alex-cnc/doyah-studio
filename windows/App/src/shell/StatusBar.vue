<script setup lang="ts">
import { computed } from 'vue'
import type { AppInfo } from '../ipc'
import { applyTheme, readStoredTheme, storeTheme, type ThemeMode } from '../theme'
import {
  applyScheme,
  readStoredScheme,
  storeScheme,
  THEME_SCHEMES,
  THEME_SCHEME_LABELS,
  type ThemeSchemeId,
} from '../theme'

const props = defineProps<{
  info: AppInfo | null
  rows: number
  cols: number
  loaded: number
  total: number
}>()

const emit = defineEmits<{ 'update:theme': [mode: ThemeMode]; 'update:scheme': [scheme: ThemeSchemeId] }>()

const mode = computed<ThemeMode>(() => readStoredTheme(window.localStorage))
const scheme = computed<string>(() => readStoredScheme(window.localStorage))

const backendLabel = computed(() => (props.info ? (props.info.backend === 'tauri' ? 'Rust 领域层（Tauri IPC）' : '浏览器旁路（mock）') : '连接中…'))

function setMode(next: ThemeMode): void {
  storeTheme(window.localStorage, next)
  applyTheme(document.documentElement, next)
  emit('update:theme', next)
}

function setScheme(next: string): void {
  storeScheme(window.localStorage, next)
  applyScheme(document.documentElement, next)
  emit('update:scheme', next as ThemeSchemeId)
}
</script>

<template>
  <footer class="statusbar">
    <span>{{ backendLabel }}</span>
    <span>结果集 {{ rows.toLocaleString() }} 行 × {{ cols }} 列</span>
    <span>本片已取 {{ loaded }} 行 / 逻辑 {{ total.toLocaleString() }} 行</span>
    <span class="statusbar__spacer" />
    <!-- 主题（配色方案）：候选来自生成物（macOS 侧 Core/DesignTheme.swift），与 macOS 侧同名同值;
         「推导草案」标记也跟着生成物走（对侧值到位后这里自动不标）。 -->
    <select
      class="statusbar__scheme"
      :value="scheme"
      aria-label="主题（配色方案）"
      @change="setScheme(($event.target as HTMLSelectElement).value)"
    >
      <option v-for="candidate in THEME_SCHEMES" :key="candidate.id" :value="candidate.id">
        {{ THEME_SCHEME_LABELS[candidate.id] ?? candidate.id }}{{ candidate.derivedDraft ? '（推导草案）' : '' }}
      </option>
    </select>
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

.statusbar__scheme {
  padding: 0 var(--ds-spacing-xs);
  background: transparent;
  color: var(--ds-color-text-secondary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-badge);
  font-size: var(--ds-font-caption-size);
  font-family: inherit;
  cursor: pointer;
}

.statusbar__theme--active {
  background: var(--ds-color-surface-raised);
  color: var(--ds-color-text-primary);
}
</style>
