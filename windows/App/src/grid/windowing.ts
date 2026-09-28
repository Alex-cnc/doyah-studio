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

export interface PoolSlot {
  /** 行节点在文档里的**固定槽位**（0..len-1）——它就是 `v-for` 的 key：**永不变化**。 */
  slot: number
  /** 该槽位当前显示的**绝对行号**。 */
  row: number
}

/**
 * 行池槽位分配（纯函数，可单测）。
 *
 * 由头（2026-09-29 第 30 轮实测）：旧写法的 key 是**绝对行号**（`plan.start + index`）⇒ 窗口一动，
 * key 集合整体平移，Vue 只能靠**移动**节点来复用 —— 实测每帧 623 个节点被建 / 删、612 次属性写入，
 * 真机帧耗时 p50 79 ms（8.5 fps），而消融档把成本钉在「写 DOM + 重排版 / 重绘」上。
 *
 * 本函数把「槽位」与「行号」解耦：槽位固定、按**行号对池长取模**轮转分配 ⇒ 窗口平移一行时
 * **只有一个槽位换内容**（其余槽位内容原样不动，节点不移动、不重建）。性质由单测钉住：
 * ① 覆盖 [start, start+len-1] 每行恰好一次；② `start → start+1` 时恰好 1 个槽位变化。
 */
export function poolSlots(start: number, len: number): PoolSlot[] {
  if (len <= 0) return []
  // 起点为负时轮转会把某个槽位映射到「行号 -1」这种不存在的行（实测：`poolSlots(-1, 4)` 的末槽是 -1）
  // ——窗口起点由 `windowForScroll` 保证非负，这里直接拒，别让它静默渲染半行 / 空行。
  if (start < 0) throw new Error('poolSlots 的 start 不能为负（窗口起点由 windowForScroll 保证非负）')
  const off = ((start % len) + len) % len
  const out: PoolSlot[] = []
  for (let k = 0; k < len; k += 1) {
    out.push({ slot: k, row: start + (((k - off) % len) + len) % len })
  }
  return out
}
