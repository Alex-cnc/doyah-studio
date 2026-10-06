<script setup lang="ts">
// 节点图标（FR-META-06）—— **画法只在这一处**；"哪类节点配哪个图标"在 `nodeIcon.ts`。
//
// 为什么拆成两层：映射（语义）与画法（路径）是两件事。判据要对账的是映射，不必解析 SVG；
// 换一套图标只动这个文件，不会碰到任何规则。
//
// 零依赖：内联 SVG（不引图标字体 / CDN —— 断网就缺图标，而且本侧要求零第三方依赖）。
// 颜色随主题走 `currentColor`。

import { computed } from 'vue'

import { nodeGlyph, type NodeGlyph } from './nodeIcon'

const props = defineProps<{
  /** 节点类型名（`table` / `view` / `column` / `schema` / …；认不出给兜底图标） */
  kind: string
  /** 视觉尺寸（px）；缺省 14 */
  size?: number
}>()

/** 每类图标一组路径（`viewBox` 固定 0 0 16 16，描边画法见模板）。 */
const PATHS: Record<NodeGlyph, string[]> = {
  // 服务器：两台叠着的机架
  server: ['M2.5 3.5h11v3.5h-11z', 'M2.5 9h11v3.5h-11z', 'M5 5.25h.01', 'M5 10.75h.01'],
  // 库：圆柱
  database: [
    'M8 3c2.8 0 5 .7 5 1.5S10.8 6 8 6 3 5.3 3 4.5 5.2 3 8 3z',
    'M3 4.5v7c0 .8 2.2 1.5 5 1.5s5-.7 5-1.5v-7',
    'M3 8c0 .8 2.2 1.5 5 1.5S13 8.8 13 8',
  ],
  // 模式：文件夹
  schema: ['M2.5 5.5A1.5 1.5 0 0 1 4 4h2.4l1 1.3H12a1.5 1.5 0 0 1 1.5 1.5v4.2A1.5 1.5 0 0 1 12 12.5H4a1.5 1.5 0 0 1-1.5-1.5z'],
  // 表：带行列的网格
  table: ['M2.5 3.5h11v9h-11z', 'M2.5 6.5h11', 'M2.5 9.5h11', 'M6.5 3.5v9', 'M10 3.5v9'],
  // 列：一根竖条（列是表里的"一格"）
  column: ['M6 2.5h4v11H6z', 'M6 6h4', 'M6 10h4'],
  // 视图：框里一只眼睛
  view: ['M2.5 3.5h11v9h-11z', 'M4.8 8s1.3-2 3.2-2 3.2 2 3.2 2-1.3 2-3.2 2S4.8 8 4.8 8z', 'M8 7.3a.7.7 0 1 0 0 1.4.7.7 0 0 0 0-1.4z'],
  // 物化视图：框里一个勾（有实体）
  materializedView: ['M2.5 3.5h11v9h-11z', 'M5 8.2l2 2 4-4.4'],
  // 外部表：框 + 指向框外的箭头
  foreignTable: ['M2.5 3.5h6.5v7h-6.5z', 'M9.5 8h4', 'M11.5 6l2 2-2 2'],
  // 序列：# 号
  sequence: ['M6.2 3.5 5.2 12.5', 'M10.8 3.5 9.8 12.5', 'M3.5 6.3h9', 'M3.2 9.7h9'],
  // 系统目录：齿轮
  system: [
    'M8 6a2 2 0 1 0 0 4 2 2 0 0 0 0-4z',
    'M8 2.5v1.8M8 11.7v1.8M2.5 8h1.8M11.7 8h1.8',
    'M4.1 4.1l1.3 1.3M10.6 10.6l1.3 1.3M11.9 4.1l-1.3 1.3M5.4 10.6l-1.3 1.3',
  ],
  // 函数：斜体 f
  function: ['M10.6 3.6c-1.7-.5-2.8.4-3.1 2.1L7 9.6c-.3 1.7-1.4 2.6-3.1 2.1', 'M4.6 7.6h5'],
  // 其他：圆 + 一个点
  other: ['M8 3.5a4.5 4.5 0 1 0 0 9 4.5 4.5 0 0 0 0-9z', 'M8 7v3', 'M8 5.4h.01'],
  // 未知类型兜底：圆 + 问号
  unknown: [
    'M8 3.5a4.5 4.5 0 1 0 0 9 4.5 4.5 0 0 0 0-9z',
    'M6.4 6.6a1.6 1.6 0 1 1 2.3 1.5c-.5.2-.7.5-.7 1',
    'M8 11h.01',
  ],
}

const glyph = computed<NodeGlyph>(() => nodeGlyph(props.kind))
const paths = computed<string[]>(() => PATHS[glyph.value])
const px = computed<number>(() => props.size ?? 14)
</script>

<template>
  <svg
    class="nodeicon"
    :width="px"
    :height="px"
    viewBox="0 0 16 16"
    fill="none"
    stroke="currentColor"
    stroke-width="1.2"
    stroke-linecap="round"
    stroke-linejoin="round"
    :data-glyph="glyph"
    aria-hidden="true"
  >
    <path v-for="(d, i) in paths" :key="i" :d="d" />
  </svg>
</template>

<style scoped>
.nodeicon {
  flex: 0 0 auto;
  display: block;
  vertical-align: -1px;
}
</style>
