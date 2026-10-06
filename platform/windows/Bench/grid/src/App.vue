<script setup lang="ts">
import { computed, onMounted, ref, shallowRef } from 'vue'
import { useVirtualizer } from '@tanstack/vue-virtual'
import { GridData } from './gridData'
import { heapMB, nextFrame, runScrollBench, timeSecondRun, type BenchResult } from './bench'

const ROW_H = 24
const OVERSCAN = 10
const COL_W = 140

const grid = shallowRef<GridData | null>(null)
const viewport = ref<HTMLElement | null>(null)
const status = ref('载入数据…')
const order = shallowRef<Uint32Array | null>(null)
const sortCol = ref(-1)
const sortDesc = ref(false)
const filterNeedle = ref('')
const lastAction = ref('')

const rowCount = computed(() => (order.value ? order.value.length : grid.value?.rows ?? 0))
const columns = computed(() => grid.value?.meta.colNames ?? [])
const gridWidth = computed(() => columns.value.length * COL_W)

const virtualizer = useVirtualizer(
  computed(() => ({
    count: rowCount.value,
    getScrollElement: () => viewport.value,
    estimateSize: () => ROW_H,
    overscan: OVERSCAN,
  })),
)
const items = computed(() => virtualizer.value.getVirtualItems())
const totalHeight = computed(() => virtualizer.value.getTotalSize())

function rowAt(index: number): string[] {
  const g = grid.value
  if (!g) return []
  const real = order.value ? order.value[index] : index
  return g.window(real, 1)[0] ?? []
}

function resetView(): void {
  order.value = null
  sortCol.value = -1
  sortDesc.value = false
  filterNeedle.value = ''
  if (viewport.value) viewport.value.scrollTop = 0
}

function doSort(col: number): void {
  const g = grid.value
  if (!g) return
  const desc = sortCol.value === col ? !sortDesc.value : false
  sortCol.value = col
  sortDesc.value = desc
  const t = timeSecondRun(() => g.sortOrder(col, desc))
  order.value = t.value
  lastAction.value = `排序 col=${col} desc=${desc} → ${t.ms} ms（前端排序）`
  if (viewport.value) viewport.value.scrollTop = 0
}

function doFilter(): void {
  const g = grid.value
  if (!g) return
  const textCol = g.meta.kinds.indexOf('text')
  if (textCol < 0) return
  const needle = filterNeedle.value || g.cell(7, textCol)
  filterNeedle.value = needle
  const t = timeSecondRun(() => g.filterText(textCol, needle))
  order.value = t.value
  sortCol.value = -1
  lastAction.value = `筛选 ${g.meta.colNames[textCol]} = ${needle} → 命中 ${t.value.length} 行 / ${t.ms} ms（前端筛选）`
  if (viewport.value) viewport.value.scrollTop = 0
}

async function runBench(opts: { frames?: number } = {}): Promise<BenchResult | null> {
  const g = grid.value
  const vp = viewport.value
  if (!g || !vp) return null
  status.value = '基准进行中…'
  const notes: string[] = [
    '帧耗时为无头 Chromium（软件光栅）读数，不含 GPU 合成 ⇒ 只用于同机方案对比与回归',
    '数据窗口由同一块 ArrayBuffer 直接切出（Rust 侧窗口 API 的等价语义），未含 Tauri IPC 开销',
  ]

  // 1) 滚动
  const scroll = await runScrollBench(vp, { frames: opts.frames ?? 240, stepPx: ROW_H * 12, warmup: 30 })

  // 2) 排序 / 筛选 / 窗口取数（前端侧对照项）
  const sort = timeSecondRun(() => g.sortOrder(1, true))
  const textCol = g.meta.kinds.indexOf('text')
  const sample = textCol >= 0 ? g.cell(7, textCol) : ''
  const filter = textCol >= 0 ? timeSecondRun(() => g.filterText(textCol, sample)) : { value: new Uint32Array(), ms: 0 }
  const windowx = timeSecondRun(() => {
    let cells = 0
    for (let i = 0; i < 200; i++) {
      const start = (i * 1973) % Math.max(1, g.rows - 64)
      cells += g.window(start, 64).length
    }
    return cells
  })

  const h = heapMB()
  const result: BenchResult = {
    rows: g.rows,
    cols: g.cols,
    scroll,
    sortMs: sort.ms,
    filterMs: filter.ms,
    windowMs: windowx.ms,
    heapUsedMB: h.used,
    heapTotalMB: h.total,
    mountMs: mountMs.value,
    ua: navigator.userAgent,
    notes,
  }
  benchResult.value = result
  status.value = '基准完成'
  ;(window as unknown as Record<string, unknown>).__DOYAH_GRID_BENCH__ = result
  return result
}

const mountMs = ref<number | null>(null)
const benchResult = shallowRef<BenchResult | null>(null)

onMounted(async () => {
  const t0 = performance.now()
  try {
    grid.value = await GridData.load('/data')
    await nextFrame()
    mountMs.value = +(performance.now() - t0).toFixed(1)
    status.value = `已载入 ${grid.value.rows} 行 × ${grid.value.cols} 列`
  } catch (e) {
    status.value = `载入失败：${(e as Error).message}（先跑 Rust 侧 grid-bench 生成 public/data）`
    return
  }
  ;(window as unknown as Record<string, unknown>).__DOYAH_GRID = grid.value
  ;(window as unknown as Record<string, unknown>).__doyahRunBench = runBench
  if (location.search.includes('bench')) {
    await nextFrame()
    await runBench()
  }
})
</script>

<template>
  <div class="wrap">
    <header>
      <strong>Doyah Studio · 结果网格压力基准</strong>
      <span class="status">{{ status }}</span>
      <span class="ctl">
        <button data-test="sort" @click="doSort(1)">排序（列 1）</button>
        <button data-test="filter" @click="doFilter()">筛选（首个文本列）</button>
        <button data-test="reset" @click="resetView()">复位</button>
        <button data-test="bench" @click="runBench()">跑基准</button>
      </span>
      <span class="act">{{ lastAction }}</span>
    </header>

    <div class="head-row" :style="{ width: gridWidth + 'px' }">
      <div v-for="(c, i) in columns" :key="c" class="cell head" :style="{ width: COL_W + 'px' }" @click="doSort(i)">
        {{ c }}
      </div>
    </div>

    <div ref="viewport" class="viewport">
      <div :style="{ height: totalHeight + 'px', width: gridWidth + 'px', position: 'relative' }">
        <div
          v-for="it in items"
          :key="it.key"
          class="row"
          :style="{ transform: `translateY(${it.start}px)`, height: ROW_H + 'px' }"
        >
          <div v-for="(c, ci) in rowAt(it.index)" :key="ci" class="cell" :style="{ width: COL_W + 'px' }">{{ c }}</div>
        </div>
      </div>
    </div>

    <pre v-if="benchResult" class="result" data-test="result">{{ JSON.stringify(benchResult, null, 2) }}</pre>
  </div>
</template>

<style>
body { margin: 0; font: 12px/1.4 "Segoe UI", system-ui, sans-serif; color: #e6e8ea; background: #14171a; }
.wrap { display: flex; flex-direction: column; height: 100vh; }
header { display: flex; gap: 12px; align-items: center; padding: 8px 12px; background: #1c2126; }
.status { color: #9aa4ad; }
.act { color: #7fd1a0; }
.head-row { display: flex; background: #22282e; position: sticky; top: 0; }
.viewport { flex: 1; overflow: auto; }
.row { display: flex; position: absolute; left: 0; top: 0; }
.cell { padding: 4px 8px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; box-sizing: border-box; }
.head { font-weight: 600; cursor: pointer; }
.result { max-height: 30vh; overflow: auto; margin: 0; padding: 8px 12px; background: #101316; color: #b6f0c8; }
</style>
