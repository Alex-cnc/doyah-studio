<script setup lang="ts">
// 结果网格（表示层首片）
//
// **这一片刻意走「Rust 侧切片喂前端」**（§8.5.6-3 三候选之一）：前端只按可视窗口向 Rust 侧要
// `len` 行，**不持有整份结果集**。三候选的取舍结论仍以基准读数为准（见 §8.5.6-3 与
// `windows/Bench/grid/README.md`），本片不替它下结论。
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { DEFAULT_GRID_SEED, datasetSummary, gridWindow } from '../ipc'
import { windowForScroll } from '../grid/windowing'

const props = defineProps<{
  rows: number
  cols: number
  orderDesc: boolean
}>()

const emit = defineEmits<{
  'update:rows': [value: number]
  'update:cols': [value: number]
  'update:orderDesc': [value: boolean]
  stats: [payload: { loaded: number; total: number; bytes: number; colNames: string[] }]
}>()

// 行高**不在前端写死**：它读生成物里的 `--ds-metric-row-height`（令牌取值的单一来源）。
// 读不到就保持初值并如实标出来 —— 让「令牌没生效」可见，而不是静默当成 26。
const rowHeight = ref(26)
const rowHeightSource = ref<'token' | 'fallback'>('fallback')
const OVERSCAN = 6

const scrollTop = ref(0)
const viewportHeight = ref(480)
const cells = ref<string[][]>([])
const loaded = ref(0)
const total = ref(0)
const bytes = ref(0)
const colNames = ref<string[]>([])
const lastMs = ref(0)
const scroller = ref<HTMLElement | null>(null)
let requestSeq = 0

const plan = computed(() => windowForScroll(scrollTop.value, viewportHeight.value, rowHeight.value, total.value, OVERSCAN))

async function loadSummary(): Promise<void> {
  const summary = await datasetSummary(props.rows, props.cols, DEFAULT_GRID_SEED)
  total.value = summary.rows
  bytes.value = summary.bytes
  colNames.value = summary.colNames
  emit('stats', { loaded: loaded.value, total: total.value, bytes: bytes.value, colNames: colNames.value })
  await loadWindow()
}

async function loadWindow(): Promise<void> {
  if (plan.value.len === 0) {
    cells.value = []
    loaded.value = 0
    return
  }
  const seq = (requestSeq += 1)
  const started = performance.now()
  const window = await gridWindow({
    rows: props.rows,
    cols: props.cols,
    seed: DEFAULT_GRID_SEED,
    orderDesc: props.orderDesc,
    start: plan.value.start,
    len: plan.value.len,
  })
  if (seq !== requestSeq) return // 迟到的响应丢掉：窗口已经又变了
  cells.value = window.cells
  loaded.value = window.cells.length
  lastMs.value = Math.round(performance.now() - started)
  total.value = window.total
  emit('stats', { loaded: loaded.value, total: total.value, bytes: bytes.value, colNames: colNames.value })
}

function onScroll(event: Event): void {
  const target = event.target as HTMLElement
  scrollTop.value = target.scrollTop
  viewportHeight.value = target.clientHeight
}

let resizeObserver: ResizeObserver | null = null

onMounted(async () => {
  const fromCss = getComputedStyle(document.documentElement).getPropertyValue('--ds-metric-row-height').trim()
  const parsed = Number.parseFloat(fromCss)
  if (Number.isFinite(parsed) && parsed > 0) {
    rowHeight.value = parsed
    rowHeightSource.value = 'token'
  }
  if (scroller.value) {
    viewportHeight.value = scroller.value.clientHeight
    resizeObserver = new ResizeObserver(() => {
      if (scroller.value) viewportHeight.value = scroller.value.clientHeight
    })
    resizeObserver.observe(scroller.value)
  }
  await loadSummary()
})

onUnmounted(() => {
  resizeObserver?.disconnect()
})

watch(plan, loadWindow)
watch(
  () => [props.rows, props.cols, props.orderDesc],
  loadSummary,
)
</script>

<template>
  <section class="results">
    <header class="results__toolbar">
      <label class="results__field">
        行
        <input :value="rows" type="number" min="1" @input="emit('update:rows', Number(($event.target as HTMLInputElement).value) || 1)" />
      </label>
      <label class="results__field">
        列
        <input :value="cols" type="number" min="1" max="60" @input="emit('update:cols', Number(($event.target as HTMLInputElement).value) || 1)" />
      </label>
      <button class="results__button" type="button" @click="emit('update:orderDesc', !orderDesc)">
        排序：{{ orderDesc ? '降序' : '升序' }}
      </button>
      <span class="results__meta">
        本片 {{ loaded }} 行 / 窗口 {{ plan.start }}–{{ plan.start + plan.len }} · {{ lastMs }} ms ·
        估算 {{ (bytes / 1048576).toFixed(1) }} MB（字节估算，不含 WebView2 侧持有量）
        · 行高 {{ rowHeight }}px（{{ rowHeightSource === 'token' ? '取自令牌' : '取不到令牌，用了回退值' }}）
      </span>
    </header>

    <div ref="scroller" class="results__scroller" @scroll.passive="onScroll">
      <div class="results__head">
        <span v-for="(name, index) in colNames" :key="name" class="results__cell results__cell--head">
          {{ index === 0 ? '#' : name }}
        </span>
      </div>
      <div class="results__viewport" :style="{ height: `${total * rowHeight}px` }">
        <div class="results__row" v-for="(row, index) in cells" :key="plan.start + index" :style="{ top: `${(plan.start + index) * rowHeight}px` }">
          <span v-for="(value, col) in row" :key="col" class="results__cell" :title="value">{{ value }}</span>
        </div>
      </div>
      <p v-if="total === 0" class="results__empty">没有数据行（空态：主内容区一行都没有）。</p>
    </div>
  </section>
</template>

<style scoped>
.results {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
}

.results__toolbar {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-m);
  padding: var(--ds-spacing-s);
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
}

.results__field {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.results__field input {
  width: var(--ds-metric-toolbar-button-width);
  height: var(--ds-metric-control-height);
  background: var(--ds-color-surface-panel);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack-mono);
  font-size: var(--ds-font-data-size);
}

.results__button {
  height: var(--ds-metric-control-height);
  padding: 0 var(--ds-spacing-s);
  background: var(--ds-color-surface-panel);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-size: var(--ds-font-caption-size);
  cursor: pointer;
}

.results__meta {
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
}

.results__scroller {
  position: relative;
  flex: 1;
  min-height: 0;
  overflow: auto;
  background: var(--ds-color-surface-content);
}

.results__head {
  position: sticky;
  top: 0;
  z-index: 1;
  display: flex;
  height: var(--ds-metric-tab-height);
  background: var(--ds-color-surface-panel);
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
}

.results__viewport {
  position: relative;
}

.results__row {
  position: absolute;
  left: 0;
  right: 0;
  display: flex;
  height: var(--ds-metric-row-height);
  line-height: var(--ds-metric-row-height);
}

.results__row:nth-child(even) {
  background: color-mix(in srgb, var(--ds-color-text-primary) 2%, transparent);
}

.results__cell {
  flex: 0 0 var(--ds-metric-min-column-width);
  min-width: 0;
  padding: 0 var(--ds-spacing-s);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--ds-color-text-primary);
  font-size: var(--ds-font-data-size);
}

.results__cell--head {
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
  line-height: var(--ds-metric-tab-height);
}

.results__empty {
  padding: var(--ds-spacing-l);
  color: var(--ds-color-text-secondary);
}
</style>
