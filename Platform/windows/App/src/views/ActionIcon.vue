<script setup lang="ts">
// 动作图标组件（T-20261013-053）—— **动作图标的画法只在这一处**
//
// 与 `NodeIcon.vue` 同一分层口径：语义名（`actionIcons.ts`）与画法（本文件）分开，
// 判据对账的是"动作 → 图标名"，不必解析 SVG；换一套画法只动本文件。
//
// 零依赖：内联 SVG（不引图标字体 / CDN）。颜色随主题走 `currentColor`。
// **可访问性**：纯图标按钮必须带 tooltip / aria-label —— 由调用方给，本组件只 `aria-hidden`
// （图标本身对读屏无意义，动作由按钮的 label 表达）。

import { computed } from 'vue'

import { isActionGlyph, type ActionGlyph } from '../shell/actionIcons'

const props = defineProps<{
  /** 图标语义名（未登记的名字会**如实落到占位图标**，不抛错、也不悄悄画别的动作） */
  name: string
  /** 视觉尺寸（px）；缺省 14 */
  size?: number
}>()

/** 每类图标一组路径（`viewBox` 固定 0 0 16 16，描边画法见模板）。 */
const PATHS: Record<ActionGlyph, string[]> = {
  // ── 文件与工作区 ──
  // 文件夹张口
  openFolder: ['M2 5.5A1.5 1.5 0 0 1 3.5 4h2.6l1.2 1.5H12a1.5 1.5 0 0 1 1.5 1.5v4A1.5 1.5 0 0 1 12 12.5H3.5A1.5 1.5 0 0 1 2 11z', 'M2 8.5h11.5'],
  // 文件夹 + 减号
  closeFolder: ['M2 5.5A1.5 1.5 0 0 1 3.5 4h2.6l1.2 1.5H12a1.5 1.5 0 0 1 1.5 1.5v4A1.5 1.5 0 0 1 12 12.5H3.5A1.5 1.5 0 0 1 2 11z', 'M5.8 9.2h4.4'],
  // 纸页 + 加号
  newFile: ['M9 2.5H5A1.5 1.5 0 0 0 3.5 4v8A1.5 1.5 0 0 0 5 13.5h6A1.5 1.5 0 0 0 12.5 12V6z', 'M9 2.5V6h3.5', 'M8 8.5v3', 'M6.5 10h3'],
  // 文件夹 + 加号
  newFolder: ['M2 5.5A1.5 1.5 0 0 1 3.5 4h2.6l1.2 1.5H12a1.5 1.5 0 0 1 1.5 1.5v4A1.5 1.5 0 0 1 12 12.5H3.5A1.5 1.5 0 0 1 2 11z', 'M8 8v3', 'M6.5 9.5h3'],
  // 软盘
  save: ['M3.5 3.5h7L13 6v6.5A1 1 0 0 1 12 13.5H4A1 1 0 0 1 3 12.5V4.5A1 1 0 0 1 3.5 3.5z', 'M5.5 3.5v3h4v-3', 'M5.5 13.5v-3.5h5v3.5'],
  // 对向箭头（差异）
  diff: ['M4 5h7', 'M9 3.2 11 5 9 6.8', 'M12 11H5', 'M7 9.2 5 11l2 1.8'],
  // 垃圾桶
  trash: ['M3.5 5h9', 'M6.5 5V3.8A.8.8 0 0 1 7.3 3h1.4a.8.8 0 0 1 .8.8V5', 'M4.8 5l.6 8a1 1 0 0 0 1 .9h3.2a1 1 0 0 0 1-.9L11.2 5', 'M6.8 7.5v4', 'M9.2 7.5v4'],
  // ── 检索与替换 ──
  search: ['M7.2 12.2a5 5 0 1 0 0-10 5 5 0 0 0 0 10z', 'M11 11l2.5 2.5'],
  replace: ['M3 5.5h6.5', 'M7.6 3.6 9.6 5.5 7.6 7.4', 'M13 10.5H6.5', 'M8.4 8.6 6.4 10.5l2 1.9'],
  preview: ['M1.8 8S4.2 4 8 4s6.2 4 6.2 4-2.4 4-6.2 4S1.8 8 1.8 8z', 'M8 9.8a1.8 1.8 0 1 0 0-3.6 1.8 1.8 0 0 0 0 3.6z'],
  // 对话气泡（尾巴朝左下）＝与模型对话
  chatBubble: ['M2.5 4.2A1.7 1.7 0 0 1 4.2 2.5h7.6a1.7 1.7 0 0 1 1.7 1.7v5.2a1.7 1.7 0 0 1-1.7 1.7H7.4L4.6 13.3v-2.2H4.2a1.7 1.7 0 0 1-1.7-1.7z'],
  // ── 通用动作 ──
  plus: ['M8 3.5v9', 'M3.5 8h9'],
  close: ['M4 4l8 8', 'M12 4l-8 8'],
  check: ['M3.5 8.5l3 3 6-7'],
  pencil: ['M11.2 2.8l2 2-8 8-2.7.7.7-2.7z', 'M10 4l2 2'],
  copy: ['M5.5 5.5h7.5v8H5.5z', 'M3 10.5V3h7.5'],
  play: ['M5.5 3.5l7 4.5-7 4.5z'],
  stop: ['M4.5 4.5h7v7h-7z'],
  eraser: ['M6.5 13.5h6.5', 'M3.2 10.6 8.6 5.2a1.2 1.2 0 0 1 1.7 0l2.5 2.5a1.2 1.2 0 0 1 0 1.7l-3.6 3.6H5.6z'],
  download: ['M8 2.8v7.4', 'M5 7.4 8 10.4l3-3', 'M3.5 12.8h9'],
  upload: ['M8 13.2V5.8', 'M5 8.6 8 5.6l3 3', 'M3.5 3.2h9'],
  flask: ['M6.5 2.8v4L3.6 12a1 1 0 0 0 .9 1.5h7a1 1 0 0 0 .9-1.5L9.5 6.8v-4', 'M5.8 2.8h4.4', 'M5.2 10h5.6'],
  wand: ['M3 13l7.5-7.5', 'M11.2 2.6l.5 1.4 1.4.5-1.4.5-.5 1.4-.5-1.4-1.4-.5 1.4-.5z', 'M13 8.6l.3.8.8.3-.8.3-.3.8-.3-.8-.8-.3.8-.3z'],
  code: ['M6 4.5 2.5 8 6 11.5', 'M10 4.5 13.5 8 10 11.5'],
  sliders: ['M3 5.5h10', 'M3 10.5h10', 'M6 3.8v3.4', 'M10 8.8v3.4'],
  lock: ['M4.5 7.5h7V13h-7z', 'M6.2 7.5V5.6a1.8 1.8 0 0 1 3.6 0v1.9'],
  sortAsc: ['M8 12.5V4', 'M5 7l3-3 3 3', 'M3 13.5h10'],
  sortDesc: ['M8 3.5V12', 'M5 9l3 3 3-3', 'M3 13.5h10'],
  chevronLeft: ['M10 3.5 5.5 8l4.5 4.5'],
  chevronRight: ['M6 3.5 10.5 8 6 12.5'],
  chevronDown: ['M3.5 6 8 10.5 12.5 6'],
  chevronUp: ['M3.5 10 8 5.5 12.5 10'],
  arrowRight: ['M3 8h9.5', 'M9.5 5 12.5 8l-3 3'],
  undo: ['M4 8.5h5.5a3 3 0 0 1 0 6H8', 'M6 6 3.5 8.5 6 11'],
  refresh: ['M12.5 8a4.5 4.5 0 1 1-1.6-3.4', 'M12.6 3.2v2.4h-2.4'],
  placeholder: ['M3.5 3.5h9v9h-9z'],
}

const glyph = computed<ActionGlyph>(() =>
  isActionGlyph(props.name) ? props.name : 'placeholder',
)
const paths = computed<string[]>(() => PATHS[glyph.value])
const px = computed<number>(() => props.size ?? 14)
</script>

<template>
  <svg
    class="actionicon"
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
.actionicon {
  flex: 0 0 auto;
  display: block;
  vertical-align: -1px;
}
</style>
