// 编辑器字体的**可用性判定**（FR-EDIT-26 的「如实说」那一半）
//
// 为什么需要这层：偏好里能存下任意族名（用户能手输），但**这台机器上有没有这个族**只有浏览器
// 量得出来。不量就会掉进两种都不对的形态：
//   · 假装成功：界面写「当前使用 JetBrains Mono」，实际回落到等宽栈 —— 用户以为自己选对了
//     （macOS 侧当年正是为此把判定分成「命中 / 没这个族 / 有但不是等宽」三档）；
//   · 一律报不可用：系统里明明装了，却提示「未安装」，用户会去反复重装。
//
// 量法 = **同一段探针文本、同一字号，量两次字宽**：带候选族量一次、只用兜底 `monospace` 量一次。
// 两次相同 ⇒ 候选族没有参与排版 ⇒ 没装。（已知局限：某个族的字宽恰好与兜底等宽逐字相同 ⇒
// 会被判成没装。等宽族之间这种巧合极少，且判错的后果只是多一句提示，不会改坏排版。）

/** 三档判定（与 macOS 侧 `MonospaceFontResolution` 同一口径）。 */
export type FontStatus = 'system' | 'resolved' | 'missing'

/** 探针文本：混宽窄字形，任何真参与排版的族都会与兜底拉开宽度差。 */
export const PROBE_TEXT = 'mmmmmmmmmmlli0O'

/** 字宽量法（注入式：判据里给一个假量法，真浏览器里给 canvas）。 */
export type Measure = (cssFont: string) => number

/**
 * 这个族参与排版了吗（= 装了吗）。
 *
 * `cssFont` 里候选族**带引号**：族名里有空格（`JetBrains Mono`）时不加引号会被当成字体列表的
 * 多个项，量出来永远是兜底的宽度 ⇒ 恒判「没装」。
 */
export function familyPresent(family: string, measure: Measure, sizePx = 16): boolean {
  const name = family.trim()
  if (name === '') return false
  const withFamily = measure(`${sizePx}px "${name}", monospace`)
  const fallbackOnly = measure(`${sizePx}px monospace`)
  return withFamily !== fallbackOnly
}

/** 三档判定：未选 = 系统等宽；选了且量到 = 命中；选了但没量到 = 没装（界面据此如实提示）。 */
export function fontStatus(family: string | null, present: (family: string) => boolean): FontStatus {
  const name = family?.trim() ?? ''
  if (name === '') return 'system'
  return present(name) ? 'resolved' : 'missing'
}

/** canvas 量法（浏览器侧）。取不到 2D 上下文时给 `null`，由调用方按「量不了」处理。 */
export function canvasMeasure(): Measure | null {
  if (typeof document === 'undefined' || typeof document.createElement !== 'function') return null
  const canvas = document.createElement('canvas')
  const ctx = typeof canvas.getContext === 'function' ? canvas.getContext('2d') : null
  if (!ctx || typeof ctx.measureText !== 'function') return null
  return (cssFont: string) => {
    ctx.font = cssFont
    return ctx.measureText(PROBE_TEXT).width
  }
}

/**
 * 真环境里的判定。
 *
 * **量不了时不报警**（返回 `resolved`）：没有测量能力就说「你这个族没装」是纯猜测，
 * 而错的提示会把用户推去重装一个本来就有的字体。
 */
export function detectFontStatus(family: string | null): FontStatus {
  const measure = canvasMeasure()
  if (measure === null) return fontStatus(family, () => true)
  return fontStatus(family, (name) => familyPresent(name, measure))
}
