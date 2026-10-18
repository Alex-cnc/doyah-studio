// 可拖拽分隔条（FR-EDIT-13）· **纯逻辑**：高度夹紧与步进。
//
// 为什么单拎出来：拖动这条链上有两个只有真挂载才看得见的地方（div 测量、inline 高度回写），
// 但「拖到顶会不会把编辑区压成 0」「容器比两倍下限还窄时会不会算出负数」这类是纯算术，
// 用纯函数钉住比在挂载测试里反复造 DOM 尺寸稳得多。
//
// 口径（与 macOS 侧 FR-EDIT-13 一致）：**上下两区各不小于 120px**；分隔条本身很薄、不计入夹紧。
// 单位是 CSS px（整数），避免半像素在 inline style 里来回抖。

/** 两区各自的最小高度（px）。取自需求：编辑区 / 结果区最小 120。 */
export const SPLIT_MIN_PANE = 120

/** 键盘步进一格（px）。40 行内的编辑器上下各挪半行左右，按住能快调但不失控。 */
export const SPLIT_STEP = 16

/**
 * 把「想要的高度」夹进合法区间。
 *
 * - `desired` 不是有限数（NaN / Infinity，多半来自没量到尺寸）⇒ 退回下限；
 * - 容器高度量不到（<=0，如首帧或隐藏态）⇒ 只保下限，不硬夹上限（否则会把编辑区压成 120 回不去）；
 * - 容器比 `2 × minPane` 还窄 ⇒ 上限就在下限之下，此时**保下限**（宁可让下方区溢出，也不给出 0 或负数）。
 */
export function clampSplitHeight(
  desired: number,
  containerHeight: number,
  minPane: number = SPLIT_MIN_PANE,
): number {
  const min = Math.max(0, Math.round(minPane))
  if (!Number.isFinite(desired)) return min
  const wanted = Math.round(desired)
  if (!Number.isFinite(containerHeight) || containerHeight <= 0) return Math.max(min, wanted)
  const upper = Math.max(min, Math.round(containerHeight) - min)
  return Math.min(Math.max(wanted, min), upper)
}

/** 键盘步进：在合法区间内 `current + delta`（越界即夹紧，不环绕 —— 拖到底再按 ↓ 不该跳回顶）。 */
export function stepSplitHeight(
  current: number,
  delta: number,
  containerHeight: number,
  minPane: number = SPLIT_MIN_PANE,
): number {
  const base = Number.isFinite(current) ? current : minPane
  const move = Number.isFinite(delta) ? delta : 0
  return clampSplitHeight(base + move, containerHeight, minPane)
}
