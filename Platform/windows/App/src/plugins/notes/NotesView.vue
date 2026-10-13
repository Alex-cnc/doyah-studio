<script setup lang="ts">
// 笔记插件 · 视图壳（**本轮 = 骨架，功能本体未做**）
//
// 口径（人类主人 2026-10-13 令「先做插件骨架 + 空模块」）：
// 这里**只证明"插件能被装配、能被拔掉"**，在功能本体落地前**如实显示"未开工"** ——
// 与本侧既有纪律一致：**不给假界面**（不画空的列表、不假装有编辑器）。
//
// 功能本体的出处 = `Docs/产品能力规划说明书.md`（笔记能力）；本壳不猜它长什么样。

import { t as translate, type UiLanguage } from '../../i18n'

const props = defineProps<{
  /** 界面语言（由外壳传下来；不给就按中文）。 */
  language?: UiLanguage
  /** 插件版本（由外壳从清单里取，避免这里再写一遍）。 */
  version?: string
}>()

/** 本组件的文案帮手。 */
function tr(key: Parameters<typeof translate>[0]): string {
  return translate(key, props.language ?? 'zh-Hans')
}
</script>

<template>
  <section class="plugin-view" data-plugin="notes">
    <header class="plugin-view__head">
      <h2 class="plugin-view__title">{{ tr('plugin.notes.title') }}</h2>
      <span v-if="props.version" class="plugin-view__version">v{{ props.version }}</span>
    </header>
    <p class="plugin-view__hint">{{ tr('plugin.notImplemented') }}</p>
  </section>
</template>

<style scoped>
/* 只用设计令牌（本侧铁律：不写裸值，令牌棘轮会判红）。 */
.plugin-view {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-s);
  padding: var(--ds-spacing-m);
  height: 100%;
  color: var(--ds-color-text-primary);
}
.plugin-view__head {
  display: flex;
  align-items: baseline;
  gap: var(--ds-spacing-s);
}
.plugin-view__title {
  font-size: var(--ds-font-title-size);
  font-weight: 600;
}
.plugin-view__version {
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
}
.plugin-view__hint {
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-body-size);
}
</style>
