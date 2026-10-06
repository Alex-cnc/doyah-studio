<script setup lang="ts">
// 连接名 + 环境标签 + 色条 —— **侧边栏连接行与查询上下文栏共用同一个组件**（FR-CONN-14 / -16）。
//
// 为什么必须是同一个组件而不是「两处各画一遍」：需求要的就是**两处一致**。
// 各自画一遍必然出现「侧栏标了生产、上下文栏没标」，而那条路径正好会让人连错库。
// 「显示什么、用什么颜色」全部来自 `connectionDisplay.ts` 的 `connectionPresentation`
// （本组件只把它的结论画出来，自己不做任何判断、不挑任何颜色）。
//
// 颜色只引用 `--ds-*` 令牌（角色 → 令牌的映射在本文件样式里，色值一个都没有）：
// 由 `tools/token-ratchet.mjs` 的裸值棘轮守着。

import { computed } from 'vue'
import {
  connectionPresentation,
  type ConnectionAppearanceSource,
  type ConnectionEnvironment,
} from './connectionDisplay'
import { t as translate, type DictKey, type UiLanguage } from '../i18n'

const props = defineProps<{
  connection: ConnectionAppearanceSource
  /** 名称为空时的占位文案（本地化文案由调用方给）。 */
  untitled: string
  language?: UiLanguage
  /**
   * 认证态：**显示名已由调用方算好**时直接给（保证「唯一函数」仍是同一个）。
   * 不给则本组件按同一函数算 —— 两条路都通到 `connectionDisplayTitle`。
   */
  title?: string
}>()

function tr(key: DictKey, vars?: Record<string, string | number>): string {
  return translate(key, props.language ?? 'zh-Hans', vars)
}

const presentation = computed(() =>
  connectionPresentation(props.connection, props.untitled, props.title),
)

/** 色条 / 徽标的样式修饰名（角色名 → 类名；类名 → 令牌在 <style> 里）。 */
const accentClass = computed(() => {
  const accent = presentation.value.accent
  if (!accent) return ''
  return accent.kind === 'environment' ? `conn__bar--env-${accent.tone}` : `conn__bar--tone-${accent.tone}`
})

const badge = computed(() => presentation.value.badge)

const badgeText = computed(() => {
  const plan = badge.value
  if (!plan) return ''
  if (plan.labelKey) return tr(plan.labelKey)
  return plan.labelRaw ?? ''
})

/** 认不出的标签：**原样显示**，并在悬停里说明这是没认出来的标签（不静默当没标）。 */
const badgeTitle = computed(() => {
  const plan = badge.value
  if (!plan) return ''
  if (plan.known) return badgeText.value
  return tr('db.env.unknownTip', { name: plan.labelRaw ?? '' })
})
</script>

<template>
  <span class="conn">
    <span v-if="presentation.accent" class="conn__bar" :class="accentClass" aria-hidden="true" />
    <span class="conn__name">{{ presentation.title }}</span>
    <span
      v-if="badge"
      class="conn__badge"
      :class="`conn__badge--${badge.tone}`"
      :title="badgeTitle"
    >
      {{ badgeText }}
    </span>
  </span>
</template>

<style scoped>
.conn {
  display: inline-flex;
  align-items: center;
  gap: var(--ds-spacing-hair);
  min-width: 0;
}

/* 色条：一行里那唯一一个颜色信号 */
.conn__bar {
  flex: none;
  width: var(--ds-metric-hairline);
  align-self: stretch;
  min-height: var(--ds-font-body-size);
  border-radius: var(--ds-radius-hairline);
  background: var(--ds-color-text-tertiary);
}

/* 环境标签的语义色：生产 = 危险色（整屏唯一一个红点）。 */
.conn__bar--env-danger {
  background: var(--ds-color-status-danger);
}

.conn__bar--env-warning {
  background: var(--ds-color-status-warning);
}

.conn__bar--env-success {
  background: var(--ds-color-status-success);
}

/* 自选色（不承担安全含义；只在「没标环境」时出现）。 */
.conn__bar--tone-amber {
  background: var(--ds-color-categorical-amber);
}

.conn__bar--tone-blue {
  background: var(--ds-color-categorical-blue);
}

.conn__bar--tone-magenta {
  background: var(--ds-color-categorical-magenta);
}

.conn__bar--tone-teal {
  background: var(--ds-color-categorical-teal);
}

.conn__name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* 环境徽标：小字 + 描边，随环境走语义色 */
.conn__badge {
  flex: none;
  padding: 0 var(--ds-spacing-hair);
  border: var(--ds-metric-hairline) solid currentColor;
  border-radius: var(--ds-radius-badge);
  font-size: var(--ds-font-caption-size);
  line-height: 1.4;
}

.conn__badge--danger {
  color: var(--ds-color-status-danger);
}

.conn__badge--warning {
  color: var(--ds-color-status-warning);
}

.conn__badge--success {
  color: var(--ds-color-status-success);
}

/* 认不出的标签走中性色 —— 不冒充任何安全色 */
.conn__badge--neutral {
  color: var(--ds-color-text-secondary);
}
</style>
