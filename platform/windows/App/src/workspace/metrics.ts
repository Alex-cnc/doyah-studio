// 编辑面的**列宽实量**（计划 2.2：「列宽按当前等宽字体实量」）
//
// 为什么不能写死：等宽字体在不同机器上并不是同一个字宽（默认字体不同、DPI 缩放不同、
// 用户改了字号），写死一个像素值 ⇒ 在高 DPI 上偏窄、在小字号上偏宽，横向滚动条出现得莫名其妙。
// 正解 = **量一个字符宽**（用当前真正在渲染的那个字体），宽度都按"字符数 × 字符宽"算。
//
// 两条纪律：
//   ① 量不出来（没有 canvas / 字体没加载好）**退回一个保守默认值并如实标注** ——
//      不假装量过（`measured: false`），界面可以据此少说一句"已按字体实量"；
//   ② 宽度**有上下限**：太窄会挤掉内容、太宽会让行号列占掉半屏。

/** 一个字符的宽度量不出来时的保守默认值（等宽字体常见 7~9px 区间取中）。 */
export const FALLBACK_CHAR_WIDTH = 8

/** 行号列右侧与代码之间的空档。 */
export const GUTTER_PADDING = 16

/** 单列（行号列）的宽度下限与上限。 */
export const GUTTER_MIN_WIDTH = 32
export const GUTTER_MAX_WIDTH = 120

/** 量出来的字体度量结果。 */
export interface FontMetrics {
  /** 一个字符占多少像素 */
  charWidth: number
  /** 是否**真的量到了**（false = 用的保守默认值） */
  measured: boolean
}

/**
 * 量一个等宽字符的宽度。
 *
 * `measure` 由调用方注入（浏览器里用 canvas 的 `measureText`，测试里给一个确定值）——
 * 这样这一段是**纯函数**，可以单测；真正碰 canvas 的那几行放在视图里。
 */
export function charWidthFrom(
  measure: (sample: string) => number,
  sample = 'M',
): FontMetrics {
  try {
    const width = measure(sample.repeat(16)) / 16
    if (Number.isFinite(width) && width > 0) {
      return { charWidth: width, measured: true }
    }
  } catch {
    // 量不出来走下面的保守默认值（不抛给界面）
  }
  return { charWidth: FALLBACK_CHAR_WIDTH, measured: false }
}

/**
 * 行号列要多宽：按**最大行号的位数** + 空档算，并夹在上下限之间。
 *
 * 为什么按最大行号的位数而不是行数：`99 → 2 位` / `100 → 3 位`，
 * 位数才是真正要占的宽度（行数只决定位数）。
 */
export function gutterWidth(gutterDigits: number, metrics: FontMetrics): number {
  const digits = Math.max(1, Math.trunc(gutterDigits))
  const raw = digits * metrics.charWidth + GUTTER_PADDING
  return Math.min(GUTTER_MAX_WIDTH, Math.max(GUTTER_MIN_WIDTH, Math.round(raw)))
}

/**
 * 代码列的宽度：按**最长那一行**的字符数算。
 *
 * 返回 `null` 表示"不必给宽度"（内容比可视区窄，交给布局自然撑开 —— 硬给宽度反而会出现
 * 一条永远拉不动的横向滚动条）。
 */
export function codeWidth(
  lines: readonly string[],
  metrics: FontMetrics,
  options: { availableWidth?: number; maxWidth?: number } = {},
): number | null {
  if (lines.length === 0) return null
  let longest = 0
  for (const line of lines) {
    // 按**字符**数（不是 UTF-16 单元）：与视觉宽度一致（等宽字体里一个汉字占两格，
    // 这里保守按一个字符算 —— 结果是"够宽"，不会把内容切掉）
    const length = [...line].length
    if (length > longest) longest = length
  }
  const raw = Math.ceil(longest * metrics.charWidth) + GUTTER_PADDING
  const max = options.maxWidth ?? Number.POSITIVE_INFINITY
  const width = Math.min(raw, max)
  // 比可视区窄 ⇒ 不给宽度（避免横向滚动条）
  if (options.availableWidth !== undefined && width <= options.availableWidth) {
    return null
  }
  return Math.max(1, width)
}

/**
 * 汉字这类**全角**字符在等宽字体里占两个字符宽 —— 用它把"最长行"折算成字符单位。
 *
 * 为什么单独给这一条：`codeWidth` 按字符数算对纯英文够用，但一整列中文会让宽度少算一半，
 * 结果是内容被切掉一截（比"宽一点"难看得多）。
 */
export function displayColumns(text: string): number {
  let columns = 0
  for (const ch of text) {
    columns += /[\u1100-\u115f\u2e80-\ua4cf\ua960-\ua97f\uac00-\ud7a3\uf900-\ufaff\ufe10-\ufe19\ufe30-\ufe6f\uff00-\uff60\uffe0-\uffe6]/.test(ch) ? 2 : 1
  }
  return columns
}

/** 按全角折算后的列宽（推荐用这个 —— 它把中文也算对）。 */
export function codeWidthByDisplayColumns(
  lines: readonly string[],
  metrics: FontMetrics,
  options: { availableWidth?: number; maxWidth?: number } = {},
): number | null {
  if (lines.length === 0) return null
  let widest = 0
  for (const line of lines) {
    const columns = displayColumns(line)
    if (columns > widest) widest = columns
  }
  const raw = Math.ceil(widest * metrics.charWidth) + GUTTER_PADDING
  const max = options.maxWidth ?? Number.POSITIVE_INFINITY
  const width = Math.min(raw, max)
  if (options.availableWidth !== undefined && width <= options.availableWidth) {
    return null
  }
  return Math.max(1, width)
}
