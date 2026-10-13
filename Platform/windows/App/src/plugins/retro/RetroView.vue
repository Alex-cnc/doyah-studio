<script setup lang="ts">
// 回放插件 · 视图壳（**本轮 = 骨架，功能本体未做**）
//
// 与笔记壳同一套口径：只证明"插件能装能拔"，功能本体未做就**如实显示"未开工"**。
// 功能本体的出处 = `Docs/产品能力规划说明书.md`（回放能力）；本壳不猜它长什么样。

import { t as translate, type UiLanguage } from '../../i18n'

const props = defineProps<{
  /** 界面语言（由外壳传下来；不给就按中文）。 */
  language?: UiLanguage
  /** 插件版本（由外壳从清单里取）。 */
  version?: string
}>()

/** 本组件的文案帮手。 */
function tr(key: Parameters<typeof translate>[0]): string {
  return translate(key, props.language ?? 'zh-Hans')
}
</script>

<template>
  <section class="plugin-view" data-plugin="retro">
    <header class="plugin-view__head">
      <h2 class="plugin-view__title">{{ tr('plugin.retro.title') }}</h2>
      <span v-if="props.version" class="plugin-view__version">v{{ props.version }}</span>
    </header>
    <p class="plugin-view__hint">{{ tr('plugin.notImplemented') }}</p>
  </section>
</template>

<style scoped>
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
