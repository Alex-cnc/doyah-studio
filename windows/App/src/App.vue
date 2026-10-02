<script setup lang="ts">
// 表示层外壳（Windows 侧）—— 本轮把「活动栏 + 窗口标题」按三书落到单点状态上
//
// 契约来源：`Docs/概要设计.md` §8.5.4「一样」清单 + macOS 侧 `Core/ActivityBar.swift`。
// 四模块位与对侧的语义一一对应；**未开工的视图如实标 ⬜**（不半建、不假装能点）。

import { onMounted, ref } from 'vue'
import { appInfo, type AppInfo } from './ipc'
import TitleBar from './shell/TitleBar.vue'
import SideBar from './shell/SideBar.vue'
import StatusBar from './shell/StatusBar.vue'
import ResultsView from './views/ResultsView.vue'
import {
  BUILT_ITEMS,
  ITEMS,
  itemGlyph,
  itemTitle,
  type ActivityBarItemId,
} from './shell/activityBar'
import { activeItem, setActive } from './shell/activityBarStore'

const info = ref<AppInfo | null>(null)
const rows = ref(200000)
const cols = ref(20)
const orderDesc = ref(false)
const loaded = ref(0)
const total = ref(0)

/** 活动栏的显示面：顺序、文案、图标语义都从 `activityBar.ts` 派生（视图里不再排一次）。 */
const sections = ITEMS.map((id) => ({
  id,
  label: itemTitle(id),
  glyph: itemGlyph(id),
  ready: BUILT_ITEMS.includes(id),
}))

onMounted(async () => {
  info.value = await appInfo()
})

function onSelect(id: ActivityBarItemId) {
  setActive(id)
}
</script>

<template>
  <div class="shell">
    <TitleBar :info="info" :item="activeItem" />
    <div class="shell__body">
      <SideBar :sections="sections" :active="activeItem" @select="onSelect" />
      <main class="shell__main">
        <!-- 数据库：本轮只到「外壳 + 合成数据结果网格」；真库链路按 windows/版本计划.md 1.0 段推进 -->
        <section v-if="activeItem === 'database'" class="shell__stack">
          <p class="shell__notice">
            数据库模块：当前是<strong>外壳 + 合成数据结果网格</strong>（窗口取数已跑通）。
            真库连接 / 对象树 / SQL 执行按 <code>windows/版本计划.md</code> 的 1.0 段推进。
          </p>
          <ResultsView
            v-model:rows="rows"
            v-model:cols="cols"
            v-model:order-desc="orderDesc"
            @stats="(payload) => ((loaded = payload.loaded), (total = payload.total))"
          />
        </section>
        <p v-else class="shell__placeholder">
          {{ itemTitle(activeItem) }}视图尚未开工（⬜ 不半建）。
        </p>
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

.shell__stack {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
}

.shell__notice {
  margin: 0;
  padding: var(--ds-spacing-s) var(--ds-spacing-m);
  color: var(--ds-color-text-secondary);
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
  font-size: var(--ds-font-caption-size);
}

.shell__placeholder {
  padding: var(--ds-spacing-l);
  color: var(--ds-color-text-secondary);
}
</style>
