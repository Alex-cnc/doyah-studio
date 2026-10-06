// 标题栏搜索栏的**宽度策略**（队列 L-141 / 内测清单 甲1）—— 纯逻辑，可单测。
//
// 由头（人类主人 2026-09-30 内测原话）：
//   「**不是全屏时搜索框没有同步缩小，遮住了 `Doyah Studio - Workspace` 标题**」。
// 一句原话里两个事实：搜索栏是**居中**的（FR-EDIT-37 原话「标题后面居中可以放一个长长的搜索栏」），
// 而窗口变窄时它**不收敛** —— 宽度交给系统给的是一个**与窗口宽度无关**的值 ⇒ 窗口一窄就打架。
//
// 几何模型（**口径的唯一出处**，界面照着摆）：
//   搜索栏居中，标题占它左边那一段（标题栏左端还有窗口按钮 —— `leadingInset`）。
//   居中意味着**两侧对称让位**：给左边让出多少，右边也就让出同样多。于是「不长到标题带上」的条件是
//
//     搜索栏宽度 ≤ 窗口宽度 − 2 ×（leadingInset + 标题宽度 + titleGap）
//
//   取的是**居中标题**这一档（最保守的一档）。
//
// 两条不变量（判据就是它们）：
//   ① **标题永远完整可见**（任何窗口宽度下搜索栏都不侵入标题带）；
//   ② **不挤成一条缝** —— 可用宽度连 `minimumWidth` 都不到时，搜索栏**收成 0**（这一档不显示），
//      不做"宽 40px 的搜索框"这种既不显示标题、也不能用的东西。

/** 搜索栏的**理想**宽度：够放一句检索词，也不至于霸占标题左侧那一块。 */
export const IDEAL_SEARCH_WIDTH = 360
/** 能让搜索栏**真的可用**的最小宽度；低于它就不该挤在那里（不变量 ②）。 */
export const MINIMUM_SEARCH_WIDTH = 180
/** 搜索栏与标题之间**必须留出的空档**。 */
export const TITLE_GAP = 24
/** 标题左端之外还要占掉的固定 chrome（窗口按钮 + 标题栏左内边距）。 */
export const LEADING_INSET = 90

/** 这一档**留给搜索栏**的宽度（小于 0 按 0 计 —— 不猜、不取绝对值）。 */
export function availableWidth(windowWidth: number, titleWidth: number): number {
  if (!Number.isFinite(windowWidth) || !Number.isFinite(titleWidth)) return 0
  const band = LEADING_INSET + Math.max(titleWidth, 0) + TITLE_GAP
  return Math.max(0, windowWidth - 2 * band)
}

/** 搜索栏宽度：`0` = 这一档放不下、整条不显示（此时只剩标题与 ⌘K）。 */
export function searchFieldWidth(windowWidth: number, titleWidth: number): number {
  const available = availableWidth(windowWidth, titleWidth)
  if (available < MINIMUM_SEARCH_WIDTH) return 0
  return Math.min(IDEAL_SEARCH_WIDTH, available)
}

/**
 * 给定一个宽度摆上去，会不会**压到标题带**（不变量 ① 的机械形式）。
 *
 * 它同时是判据"能判红"的那一半：写死宽度的旧口径在窄窗口上必须给 `false`，
 * 否则这条不变量等于没写。
 */
export function fitsWithoutCoveringTitle(
  windowWidth: number,
  titleWidth: number,
  fieldWidth: number,
): boolean {
  if (!Number.isFinite(fieldWidth)) return false
  return Math.max(fieldWidth, 0) <= availableWidth(windowWidth, titleWidth)
}

/**
 * 标题宽度的**估算**（前端不测 DOM：这里只要"窄窗时让位"，估宽足够）。
 * 中文按 2 个单位、其余按 1 个；字号由令牌给，这里只给比例。
 */
export const TITLE_CHAR_UNIT_PX = 9

export function estimateTitleWidth(title: string): number {
  let units = 0
  for (const ch of title) {
    units += /[\u3000-\u9fff\uff00-\uffef]/.test(ch) ? 2 : 1
  }
  return units * TITLE_CHAR_UNIT_PX
}
