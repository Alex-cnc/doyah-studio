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

import type { MdBlock, MdDocument, MdSpan, RetroMedia } from '../../ipc'
import { t as translate, type UiLanguage } from '../../i18n'

/** 媒体槽位：判定（Rust 给的）+ 界面拉回来的 blob URL（`null` = 还没到 / 读不出来）。 */
export type MediaSlot = RetroMedia & { url: string | null }

const props = defineProps<{
  document: MdDocument
  /** 正文里所有媒体的判定与 blob URL（由 `RetroView` 统一拉，组件只画）。 */
  media?: MediaSlot[]
  /** 界面语言（由外壳传下来；不给就按中文）。 */
  language?: UiLanguage
}>()

const emit = defineEmits<{
  /** 点图片放大（浮层由 `RetroView` 画 —— 插件里只发事件）。 */
  (event: 'zoom', payload: { url: string; alt: string }): void
}>()

function tr(key: Parameters<typeof translate>[0], vars?: Record<string, string | number>): string {
  return translate(key, props.language ?? 'zh-Hans', vars)
}

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

// ── 媒体（`FR-R-12-03`：图片 / 视频就地渲染；读不出来就地降级为占位）────────────────

/** 目标是「这一处媒体」的槽位（没有判定 = 理论上不该发生，按占位画）。 */
function slotOf(target: string): MediaSlot | null {
  return props.media?.find((slot) => slot.target === target) ?? null
}

/** 可读的文件名：`assets/curve.png` → `curve.png`（占位里要说清是哪个文件）。 */
function fileNameOf(target: string): string {
  const trimmed = target.trim()
  const last = trimmed.split('/').pop() ?? trimmed
  return last || trimmed
}

/** 图片的说明：`![这里]` 写着就用它，没写就用文件名（不画一个没有名字的框）。 */
function captionOf(alt: string, target: string): string {
  return alt.trim() || fileNameOf(target)
}

/** 状态标签（占位左上角那一句：缺文件 / 外链 / 格式不支持 / 路径不合法 / 正在读）。 */
function stateLabel(slot: MediaSlot | null): string {
  if (!slot) return tr('plugin.retro.mediaMissing')
  switch (slot.state) {
    case 'ok':
      return tr('plugin.retro.mediaLoading')
    case 'missing':
      return tr('plugin.retro.mediaMissing')
    case 'external':
      return tr('plugin.retro.mediaExternal')
    case 'unsupported':
      return tr('plugin.retro.mediaUnsupported')
    default:
      return tr('plugin.retro.mediaRejected')
  }
}

/** 能画吗：判定 ok **且**字节已经到（blob URL 有了）。 */
function playable(target: string): string | null {
  const slot = slotOf(target)
  return slot && slot.state === 'ok' && slot.url ? slot.url : null
}

/** 点图放大（原图在新窗口里看不了，改成同页浮层 —— 不出网、不加协议）。 */
function zoomIn(url: string, alt: string): void {
  emit('zoom', { url, alt })
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

      <!-- 媒体（`FR-R-12-03`）：能读的就地画，读不了的就地降级为占位 + 文件名 + 原因 -->
      <figure
        v-else-if="block.kind.type === 'media'"
        class="retro-md__media"
        :data-media="block.kind.media"
        :data-target="block.kind.target"
        :data-state="slotOf(block.kind.target)?.state ?? 'missing'"
        :data-line="block.line"
      >
        <template v-if="playable(block.kind.target)">
          <img
            v-if="block.kind.media === 'image'"
            class="retro-md__image"
            :src="playable(block.kind.target) ?? ''"
            :alt="captionOf(block.kind.alt, block.kind.target)"
            :title="tr('plugin.retro.mediaZoomHint')"
            data-role="retro-media-image"
            @click="zoomIn(playable(block.kind.target) ?? '', captionOf(block.kind.alt, block.kind.target))"
          />
          <video
            v-else
            class="retro-md__video"
            :src="playable(block.kind.target) ?? ''"
            controls
            preload="metadata"
            data-role="retro-media-video"
          ></video>
          <figcaption class="retro-md__media-caption">{{ captionOf(block.kind.alt, block.kind.target) }}</figcaption>
        </template>
        <span v-else class="retro-md__media-note" data-role="retro-media-note">
          <span class="retro-md__media-state">{{ stateLabel(slotOf(block.kind.target)) }}</span>
          <span class="retro-md__media-name">{{ fileNameOf(block.kind.target) }}</span>
          <span v-if="slotOf(block.kind.target)?.reason" class="retro-md__media-reason">
            {{ slotOf(block.kind.target)?.reason }}
          </span>
        </span>
      </figure>

      <!-- 引用（递归） -->
      <blockquote v-else-if="block.kind.type === 'quote'" class="retro-md__quote" :data-line="block.line">
        <BlockDocument
          :document="childDocument(block.kind.children)"
          :media="props.media"
          :language="props.language"
          @zoom="emit('zoom', $event)"
        />
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
          <BlockDocument
            v-if="block.kind.children.length"
            :document="childDocument(block.kind.children)"
            :media="props.media"
            :language="props.language"
            @zoom="emit('zoom', $event)"
          />
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
.retro-md__media {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
  margin: 0 0 var(--ds-spacing-m);
}
.retro-md__image,
.retro-md__video {
  max-width: 100%;
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-card);
  background: var(--ds-color-surface-content);
}
.retro-md__image {
  cursor: zoom-in;
}
.retro-md__media-caption {
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
}
.retro-md__media-note {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-hair);
  padding: var(--ds-spacing-s);
  border: var(--ds-metric-hairline) dashed var(--ds-color-status-warning);
  border-radius: var(--ds-radius-card);
  background: var(--ds-color-surface-content);
}
.retro-md__media-state {
  color: var(--ds-color-status-warning);
  font-size: var(--ds-font-caption-size);
}
.retro-md__media-name {
  font-family: var(--ds-font-stack-mono);
  font-size: var(--ds-font-mono-small-size);
}
.retro-md__media-reason {
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
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
