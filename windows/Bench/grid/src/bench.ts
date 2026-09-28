/**
 * 基准台测量：滚动帧耗时 / 内存 / 排序筛选延迟。
 *
 * 口径（不写进报告的实话写在代码里）：
 * - 帧耗时用 `requestAnimationFrame` 间隔测量，**不含 GPU 合成**：无头 Chromium 下是软件光栅，
 *   与真机（WebView2 + GPU）不可直接比 —— 读数用于**同一台机器上的方案对比与回归**。
 * - 内存取 `performance.memory.usedJSHeapSize`（Chromium 专有）；拿不到就如实返回 null。
 * - 排序 / 筛选取 `performance.now()` 差值，含 JIT 预热的影响 ⇒ 每项跑两遍取第二遍，如实标注。
 */

export interface FrameStats {
  frames: number
  avgMs: number
  p50Ms: number
  p95Ms: number
  maxMs: number
  fps: number
  over16ms: number
  over33ms: number
}

export interface BenchResult {
  rows: number
  cols: number
  scroll: FrameStats
  sortMs: number | null
  filterMs: number | null
  windowMs: number | null
  heapUsedMB: number | null
  heapTotalMB: number | null
  mountMs: number | null
  ua: string
  notes: string[]
}

export function percentile(sorted: number[], p: number): number {
  if (sorted.length === 0) return 0
  const i = Math.min(sorted.length - 1, Math.max(0, Math.round((p / 100) * (sorted.length - 1))))
  return sorted[i]
}

export function frameStats(deltas: number[]): FrameStats {
  const sorted = [...deltas].sort((a, b) => a - b)
  const sum = deltas.reduce((a, b) => a + b, 0)
  const avg = deltas.length ? sum / deltas.length : 0
  return {
    frames: deltas.length,
    avgMs: +avg.toFixed(3),
    p50Ms: +percentile(sorted, 50).toFixed(3),
    p95Ms: +percentile(sorted, 95).toFixed(3),
    maxMs: +(sorted.length ? sorted[sorted.length - 1] : 0).toFixed(3),
    fps: +(avg > 0 ? 1000 / avg : 0).toFixed(1),
    over16ms: deltas.filter((d) => d > 16.7).length,
    over33ms: deltas.filter((d) => d > 33.4).length,
  }
}

export function nextFrame(): Promise<number> {
  return new Promise((resolve) => {
    const t0 = performance.now()
    requestAnimationFrame(() => resolve(performance.now() - t0))
  })
}

/** 程序化滚动：每帧把 viewport 往下推 `stepPx`，逐帧记录间隔 */
export async function runScrollBench(
  viewport: HTMLElement,
  opts: { frames?: number; stepPx?: number; warmup?: number } = {},
): Promise<FrameStats> {
  const frames = opts.frames ?? 240
  const stepPx = opts.stepPx ?? 24 * 12
  const warmup = opts.warmup ?? 30
  const maxScroll = Math.max(0, viewport.scrollHeight - viewport.clientHeight)

  for (let i = 0; i < warmup; i++) {
    viewport.scrollTop = Math.min(maxScroll, viewport.scrollTop + stepPx)
    await nextFrame()
  }
  viewport.scrollTop = 0
  await nextFrame()

  const deltas: number[] = []
  let prev = performance.now()
  for (let i = 0; i < frames; i++) {
    viewport.scrollTop = Math.min(maxScroll, (i + 1) * stepPx)
    await nextFrame()
    const now = performance.now()
    deltas.push(now - prev)
    prev = now
  }
  return frameStats(deltas)
}

export function heapMB(): { used: number | null; total: number | null } {
  const m = (performance as unknown as { memory?: { usedJSHeapSize: number; totalJSHeapSize: number } }).memory
  if (!m) return { used: null, total: null }
  return { used: +(m.usedJSHeapSize / 1048576).toFixed(1), total: +(m.totalJSHeapSize / 1048576).toFixed(1) }
}

/** 两遍取第二遍（避开 JIT 与首次分页），差值为 0 也如实返回 0 */
export function timeSecondRun<T>(f: () => T): { value: T; ms: number } {
  f()
  const t0 = performance.now()
  const value = f()
  return { value, ms: +(performance.now() - t0).toFixed(1) }
}
