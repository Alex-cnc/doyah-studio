<script setup lang="ts">
// 结果网格（表示层首片）
//
// **这一片刻意走「Rust 侧切片喂前端」**（§8.5.6-3 三候选之一）：前端只按可视窗口向 Rust 侧要
// `len` 行，**不持有整份结果集**。三候选的取舍结论仍以基准读数为准（见 §8.5.6-3 与
// `windows/Bench/grid/README.md`），本片不替它下结论。
import { computed, onMounted, onUnmounted, ref, shallowRef, watch } from 'vue'
import { DEFAULT_GRID_SEED, datasetSummary, gridWindow } from '../ipc'
import { poolSlots, windowForScroll } from '../grid/windowing'

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
/** 取数时在池子两端各多取 LOOKAHEAD 行。
 *  由头（2026-09-29 第 30 轮实测）：只取「池子那几行」时，池子一平移，**新进入的行当帧还没有数据**
 *  ⇒ 先渲染一帧空白、下一帧再填真值 ⇒ 实测每帧被写入的单元格 ~815 个（≈ 全部 38 行 × 21 列），
 *  而真正变化的只有进入的 ~11 行（~231 个）。多取一段前置行之后，「进入的行」当帧就有值，写一次就够。 */
const LOOKAHEAD = 12

const scrollTop = ref(0)
const viewportHeight = ref(480)
/** 已取到的窗口（**起点与内容绑成一对**）：渲染只看它，不看「正在请求的那一片」，
 *  否则每帧会多出一次「先空白、后填值」的渲染。 */
const windowRows = shallowRef<{ start: number; cells: string[][] }>({ start: -1, cells: [] })
const loaded = ref(0)
const total = ref(0)
const bytes = ref(0)
const colNames = ref<string[]>([])
const lastMs = ref(0)
const scroller = ref<HTMLElement | null>(null)
let requestSeq = 0

const plan = computed(() => windowForScroll(scrollTop.value, viewportHeight.value, rowHeight.value, total.value, OVERSCAN))

// 行池：槽位固定（key = `slot`，永不变化），行号按池长轮转分配 ⇒ 窗口平移一行只换一个槽位的内容。
// 旧写法 key 用绝对行号（`plan.start + index`）⇒ 每帧几百个节点被建 / 删 + 几百次属性写入（第 30 轮实测）。
const pool = computed(() => poolSlots(plan.value.start, plan.value.len))

/** 槽位要显示的单元格：行号 → 已取到窗口里的下标。取不到就回空（越界不渲染半行）。 */
const EMPTY_ROW: string[] = []

function rowCells(row: number): string[] {
  const w = windowRows.value
  const idx = row - w.start
  return idx >= 0 && idx < w.cells.length ? w.cells[idx] : EMPTY_ROW
}

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
    windowRows.value = { start: -1, cells: [] }
    loaded.value = 0
    return
  }
  const seq = (requestSeq += 1)
  const started = performance.now()
  // 取数范围 = 池子（plan）+ 两端各 LOOKAHEAD 行（见常量处的由头说明）
  const from = Math.max(0, plan.value.start - LOOKAHEAD)
  const to = Math.min(total.value, plan.value.start + plan.value.len + LOOKAHEAD)
  const len = Math.max(0, to - from)
  const window = await gridWindow({
    rows: props.rows,
    cols: props.cols,
    seed: DEFAULT_GRID_SEED,
    orderDesc: props.orderDesc,
    start: from,
    len,
  })
  if (seq !== requestSeq) return // 迟到的响应丢掉：窗口已经又变了
  windowRows.value = { start: from, cells: window.cells }
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
        <div
          class="results__row"
          :class="{ 'is-even': item.row % 2 === 0 }"
          v-for="item in pool"
          :key="item.slot"
          :style="{ top: `${item.row * rowHeight}px` }"
        >
          <span v-for="(value, col) in rowCells(item.row)" :key="col" class="results__cell" :title="value">{{ value }}</span>
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
  /* 行内布局 / 绘制自成一体（第 30 轮实测：只加这一条**当时**没效果 —— 那时的成本在「每帧重建 + 移动
     整片行节点」上；行池落地后它才有意义：把「换了内容的那些行」的失效范围限制在该行内）。 */
  contain: layout paint;
}

.results__row.is-even {
  background: color-mix(in srgb, var(--ds-color-text-primary) 2%, transparent);
}

.results__cell {
  flex: 0 0 var(--ds-metric-min-column-width);
  min-width: 0;
  padding: 0 var(--ds-spacing-s);
  overflow: hidden;
  /* 数据格用 clip 不用 ellipsis：列宽只有 40px，省略号本身要走**全文排版**才能定裁剪点
     （第 30 轮消融实测：仅把 ellipsis 换成 clip，帧耗时 79.3 → 66 ms、布局 6.38 → 4.77 s）。
     完整取值由 `title` 悬浮提示给出，故不丢信息。 */
  text-overflow: clip;
  white-space: nowrap;
  color: var(--ds-color-text-primary);
  font-size: var(--ds-font-data-size);
}

.results__cell--head {
  text-overflow: ellipsis;
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
  line-height: var(--ds-metric-tab-height);
}

.results__empty {
  padding: var(--ds-spacing-l);
  color: var(--ds-color-text-secondary);
}
</style>
