<script setup lang="ts">
// 周报正文的块级渲染（插件内自持）。
//
// **为什么插件里另有一份，而不是复用 `views/MarkdownPreview.vue`**：插件边界由判据
// `App/tools/check-plugins.mjs` ④ 守着 —— 插件目录只许依赖 `shell/pluginRegistry` / `i18n` / `ipc` / `vue`，
// 不许 import `views/**`（那条边界的用途是「插件不碰宿主内部模型」）。
// 所以这里**只消费 `ipc` 里的公开模型 `MdDocument`**，不 import 宿主视图；
// 两处渲染的分工：工作区文件走 `views/MarkdownPreview`，周报正文走本组件。
// **两者映射的是同一份块模型**（解析只有 Rust 一份，`Db/src/markdown.rs`）。
//
// 纪律：只读 —— 本组件不产生任何编辑控件（模型里也没有，结构上挡住）。

import type { MdBlock, MdDocument, MdSpan } from '../../ipc'

const props = defineProps<{ document: MdDocument }>()

/** 行内三态：粗体 / 斜体 / 行内代码。 */
function inlineClass(span: MdSpan): string[] {
  const classes: string[] = []
  if (span.bold) classes.push('retro-md__bold')
  if (span.italic) classes.push('retro-md__italic')
  if (span.code) classes.push('retro-md__code')
  return classes
}

/** 列表嵌套缩进（一层一档）。 */
function indent(level: number): string {
  return `${Math.max(0, level) * 18}px`
}

function keyOf(block: MdBlock, index: number): string {
  return `${block.line}-${index}`
}

function childDocument(blocks: MdBlock[]): MdDocument {
  return { version: props.document.version, blocks }
}
</script>

<template>
  <div class="retro-md">
    <template v-for="(block, index) in document.blocks" :key="keyOf(block, index)">
      <!-- 标题：层级按源文给（1~6），不改写 -->
      <component
        :is="`h${Math.min(6, Math.max(1, block.kind.type === 'heading' ? block.kind.level : 1))}`"
        v-if="block.kind.type === 'heading'"
        class="retro-md__heading"
        :data-line="block.line"
      >
        <span v-for="(span, i) in block.kind.spans" :key="i" :class="inlineClass(span)">{{ span.text }}</span>
      </component>

      <!-- 段落（软换行原样保留） -->
      <p v-else-if="block.kind.type === 'paragraph'" class="retro-md__p" :data-line="block.line">
        <span v-for="(span, i) in block.kind.spans" :key="i" :class="inlineClass(span)">{{ span.text }}</span>
      </p>

      <!-- 围栏代码块（内容原样） -->
      <pre v-else-if="block.kind.type === 'codeFence'" class="retro-md__pre" :data-line="block.line"><code>{{
        block.kind.text
      }}</code></pre>

      <!-- 引用（递归） -->
      <blockquote v-else-if="block.kind.type === 'quote'" class="retro-md__quote" :data-line="block.line">
        <BlockDocument :document="childDocument(block.kind.children)" />
      </blockquote>

      <!-- 分隔线 -->
      <hr v-else-if="block.kind.type === 'rule'" class="retro-md__rule" :data-line="block.line" />

      <!-- 表格 -->
      <table v-else-if="block.kind.type === 'table'" class="retro-md__table" :data-line="block.line">
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
      <div
        v-else-if="block.kind.type === 'listItem'"
        class="retro-md__item"
        :data-line="block.line"
        :style="{ paddingLeft: indent(0) }"
      >
        <span class="retro-md__bullet">
          <template v-if="block.kind.checked !== null">
            <input type="checkbox" :checked="block.kind.checked === true" disabled />
          </template>
          <template v-else-if="block.kind.number !== null">{{ block.kind.number }}.</template>
          <template v-else>•</template>
        </span>
        <span class="retro-md__item-body">
          <span v-for="(span, i) in block.kind.spans" :key="i" :class="inlineClass(span)">{{ span.text }}</span>
          <BlockDocument v-if="block.kind.children.length" :document="childDocument(block.kind.children)" />
        </span>
      </div>
    </template>
  </div>
</template>

<script lang="ts">
// 递归组件要显式给名字（`<script setup>` 默认按文件名推导，这里显式声明更稳）。
export default { name: 'BlockDocument' }
</script>

<style scoped>
/* 只用设计令牌（裸值棘轮会判红）。 */
.retro-md {
  font-size: var(--ds-font-body-size);
  line-height: var(--ds-metric-list-row-height);
}
.retro-md__heading {
  margin: var(--ds-spacing-s) 0 var(--ds-spacing-xs);
}
.retro-md__p {
  margin: 0 0 var(--ds-spacing-s);
  white-space: pre-wrap;
}
.retro-md__pre {
  margin: 0 0 var(--ds-spacing-s);
  padding: var(--ds-spacing-s);
  background: var(--ds-color-surface-content);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack-mono);
  font-size: var(--ds-font-mono-size);
  overflow: auto;
}
.retro-md__quote {
  margin: 0 0 var(--ds-spacing-s);
  padding-left: var(--ds-spacing-s);
  border-left: var(--ds-metric-hairline) solid var(--ds-color-accent-accent);
  color: var(--ds-color-text-secondary);
}
.retro-md__rule {
  margin: var(--ds-spacing-s) 0;
  border: 0;
  border-top: var(--ds-metric-hairline) solid var(--ds-hairline);
}
.retro-md__table {
  margin: 0 0 var(--ds-spacing-s);
  border-collapse: collapse;
}
.retro-md__table th,
.retro-md__table td {
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
}
.retro-md__item {
  display: flex;
  gap: var(--ds-spacing-xs);
  margin-bottom: var(--ds-spacing-xs);
}
.retro-md__bullet {
  color: var(--ds-color-text-tertiary);
  font-variant-numeric: tabular-nums;
}
.retro-md__item-body {
  flex: 1;
}
.retro-md__bold {
  font-weight: 600;
}
.retro-md__italic {
  font-style: italic;
}
.retro-md__code {
  padding: 0 var(--ds-spacing-hair);
  border-radius: var(--ds-radius-hairline);
  background: var(--ds-color-surface-content);
  font-family: var(--ds-font-stack-mono);
  font-size: var(--ds-font-mono-small-size);
}
</style>
