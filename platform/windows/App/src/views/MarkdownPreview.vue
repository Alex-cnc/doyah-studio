<script setup lang="ts">
// Markdown 只读预览：**只画模型**（模型由 Rust 侧一处解析产出，见 `Db/src/markdown.rs`）
//
// 三条纪律：
//   ① **只读**：预览里不出现任何可编辑控件（模型里也没有 —— 这是结构上挡住的）；
//   ② **不自动打开外部链接**：链接只显示成带下划线的文字 + 目标提示，点了不跳（自用口径）；
//   ③ 本组件**不做任何 Markdown 解析**（有第二套解析就等于有两处口径）。

import type { MdBlock, MdDocument, MdSpan } from '../ipc'

defineProps<{ document: MdDocument }>()

function inlineClass(span: MdSpan): string[] {
  const classes: string[] = []
  if (span.bold) classes.push('md__bold')
  if (span.italic) classes.push('md__italic')
  if (span.code) classes.push('md__code')
  return classes
}

/** 列表缩进：嵌套层各加一档（模板里用 style 给 padding） */
function indent(level: number): string {
  return `${Math.max(0, level) * 18}px`
}

function keyOf(block: MdBlock, index: number): string {
  return `${block.line}-${index}`
}
</script>

<template>
  <div class="md">
    <template v-for="(block, index) in document.blocks" :key="keyOf(block, index)">
      <!-- 标题 -->
      <component
        :is="`h${Math.min(6, Math.max(1, block.kind.type === 'heading' ? block.kind.level : 1))}`"
        v-if="block.kind.type === 'heading'"
        class="md__heading"
        :data-line="block.line"
      >
        <span v-for="(span, i) in block.kind.spans" :key="i" :class="inlineClass(span)">{{ span.text }}</span>
      </component>

      <!-- 段落（软换行原样保留：`white-space: pre-wrap`） -->
      <p v-else-if="block.kind.type === 'paragraph'" class="md__p" :data-line="block.line">
        <span v-for="(span, i) in block.kind.spans" :key="i" :class="inlineClass(span)">{{ span.text }}</span>
      </p>

      <!-- 围栏代码块（内容原样） -->
      <pre v-else-if="block.kind.type === 'codeFence'" class="md__pre" :data-line="block.line"><code>{{
        block.kind.text
      }}</code></pre>

      <!-- 引用（递归） -->
      <blockquote v-else-if="block.kind.type === 'quote'" class="md__quote" :data-line="block.line">
        <MarkdownPreview :document="{ version: document.version, blocks: block.kind.children }" />
      </blockquote>

      <!-- 分隔线 -->
      <hr v-else-if="block.kind.type === 'rule'" class="md__rule" :data-line="block.line" />

      <!-- 表格 -->
      <table v-else-if="block.kind.type === 'table'" class="md__table" :data-line="block.line">
        <thead>
          <tr>
            <th
              v-for="(cell, c) in block.kind.header"
              :key="c"
              :style="{ textAlign: block.kind.alignments[c] === 'none' ? 'left' : block.kind.alignments[c] }"
            >
              <span v-for="(span, i) in cell" :key="i" :class="inlineClass(span)">{{ span.text }}</span>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(row, r) in block.kind.rows" :key="r">
            <td
              v-for="(cell, c) in row"
              :key="c"
              :style="{ textAlign: block.kind.alignments[c] === 'none' ? 'left' : block.kind.alignments[c] }"
            >
              <span v-for="(span, i) in cell" :key="i" :class="inlineClass(span)">{{ span.text }}</span>
            </td>
          </tr>
        </tbody>
      </table>

      <!-- 列表条目（嵌套走 children 递归） -->
      <div v-else-if="block.kind.type === 'listItem'" class="md__item" :data-line="block.line" :style="{ paddingLeft: indent(0) }">
        <span class="md__bullet">
          <template v-if="block.kind.checked !== null">
            <input type="checkbox" :checked="block.kind.checked === true" disabled />
          </template>
          <template v-else-if="block.kind.number !== null">{{ block.kind.number }}.</template>
          <template v-else>•</template>
        </span>
        <span class="md__item-body">
          <span v-for="(span, i) in block.kind.spans" :key="i" :class="inlineClass(span)">{{ span.text }}</span>
          <MarkdownPreview
            v-if="block.kind.children.length"
            :document="{ version: document.version, blocks: block.kind.children }"
          />
        </span>
      </div>
    </template>
  </div>
</template>

<script lang="ts">
// 递归组件要显式给名字（Vue 3 的 <script setup> 默认按文件名推导，这里显式声明更稳）
export default { name: 'MarkdownPreview' }
</script>

<style scoped>
.md {
  font-size: var(--ds-font-body-size);
  line-height: var(--ds-metric-list-row-height);
}

.md__heading {
  margin: var(--ds-spacing-s) 0 var(--ds-spacing-xs);
}

.md__p {
  margin: 0 0 var(--ds-spacing-s);
  /* 软换行**原样保留**（解析层把 `\n` 留着，怎么显示由这里决定） */
  white-space: pre-wrap;
}

.md__pre {
  margin: 0 0 var(--ds-spacing-s);
  padding: var(--ds-spacing-s);
  background: var(--ds-color-surface-content);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
  overflow: auto;
}

.md__quote {
  margin: 0 0 var(--ds-spacing-s);
  padding-left: var(--ds-spacing-s);
  border-left: var(--ds-metric-hairline) solid var(--ds-color-accent-accent);
  color: var(--ds-color-text-secondary);
}

.md__rule {
  margin: var(--ds-spacing-s) 0;
  border: 0;
  border-top: var(--ds-metric-hairline) solid var(--ds-hairline);
}

.md__table {
  margin: 0 0 var(--ds-spacing-s);
  border-collapse: collapse;
}

.md__table th,
.md__table td {
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
}

.md__item {
  display: flex;
  gap: var(--ds-spacing-xs);
  margin-bottom: var(--ds-spacing-xs);
}

.md__bullet {
  color: var(--ds-color-text-secondary);
  min-width: 18px;
}

.md__item-body {
  flex: 1;
}

.md__bold {
  font-weight: 600;
}

.md__italic {
  font-style: italic;
}

.md__code {
  padding: 0 var(--ds-spacing-xs);
  background: var(--ds-color-surface-content);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack);
}
</style>
