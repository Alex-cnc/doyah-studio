<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { appInfo, type AppInfo } from './ipc'
import TitleBar from './shell/TitleBar.vue'
import SideBar from './shell/SideBar.vue'
import StatusBar from './shell/StatusBar.vue'
import ResultsView from './views/ResultsView.vue'

const SECTIONS = [
  { id: 'results', label: '结果网格', ready: true },
  { id: 'connections', label: '连接', ready: false },
  { id: 'notes', label: '笔记', ready: false },
  { id: 'settings', label: '设置', ready: false },
] as const

const active = ref<string>('results')
const info = ref<AppInfo | null>(null)
const rows = ref(200000)
const cols = ref(20)
const orderDesc = ref(false)
const loaded = ref(0)
const total = ref(0)

onMounted(async () => {
  info.value = await appInfo()
})
</script>

<template>
  <div class="shell">
    <TitleBar :info="info" />
    <div class="shell__body">
      <SideBar :sections="SECTIONS" :active="active" @select="active = $event" />
      <main class="shell__main">
        <ResultsView
          v-if="active === 'results'"
          v-model:rows="rows"
          v-model:cols="cols"
          v-model:order-desc="orderDesc"
          @stats="(payload) => ((loaded = payload.loaded), (total = payload.total))"
        />
        <p v-else class="shell__placeholder">该分区尚未开工（⬜ 不半建）。</p>
      </main>
    </div>
    <StatusBar :info="info" :rows="rows" :cols="cols" :loaded="loaded" :total="total" />
  </div>
</template>

<style scoped>
.shell {
  display: flex;
  flex-direction: column;
  height: 100vh;
  background: var(--ds-color-surface-window);
  color: var(--ds-color-text-primary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-body-size);
}

.shell__body {
  display: flex;
  flex: 1;
  min-height: 0;
}

.shell__main {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  background: var(--ds-color-surface-content);
}

.shell__placeholder {
  padding: var(--ds-spacing-l);
  color: var(--ds-color-text-secondary);
}
</style>
