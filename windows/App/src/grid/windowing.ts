// 结果网格的**窗口取数**（纯函数，可单测）
//
// 口径（§8.5.6-3 的三候选之一 = 「Rust 侧切片喂前端」）：
// 前端**不持有整份结果集**，只按可视窗口向 Rust 侧要一小片。这里只算「要哪一片 + 上下留多少占位」，
// 真正的取值走 `ipc.ts` → Rust `grid_window`。

export interface WindowPlan {
  /** 要取的第一行（0 基）。 */
  start: number
  /** 要取多少行（含 overscan）。 */
  len: number
  /** 上方占位高度（px）——撑住滚动条，让虚拟列表的高度等于全量。 */
  topSpacer: number
  /** 下方占位高度（px）。 */
  bottomSpacer: number
  /** 本片之后是否还有数据（用于「到底了」提示与再取一页的判断）。 */
  hasMore: boolean
}

export function windowForScroll(
  scrollTop: number,
  viewportHeight: number,
  rowHeight: number,
  total: number,
  overscan = 4,
): WindowPlan {
  if (rowHeight <= 0) throw new Error('rowHeight 必须为正数（行高为 0 会让窗口永远取同一片）')
  if (total <= 0) return { start: 0, len: 0, topSpacer: 0, bottomSpacer: 0, hasMore: false }

  const firstVisible = Math.floor(Math.max(0, scrollTop) / rowHeight)
  const visibleCount = Math.max(1, Math.ceil(Math.max(0, viewportHeight) / rowHeight))
  const start = Math.max(0, firstVisible - overscan)
  const end = Math.min(total, firstVisible + visibleCount + overscan)
  const len = Math.max(0, end - start)

  return {
    start,
    len,
    topSpacer: start * rowHeight,
    bottomSpacer: Math.max(0, (total - (start + len)) * rowHeight),
    hasMore: start + len < total,
  }
}
