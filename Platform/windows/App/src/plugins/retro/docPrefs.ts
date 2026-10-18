// 周报正文的**字号三档**（`FR-R-13-08` ①「显示设定：字号」的偏好那一半）。
//
// 三条口径：
// 1. 三档就三档（小 / 标准 / 大）—— 不是连续滑杆：读周报要的是「记得住的两个方向」，
//    连续值会让「上次调的那一档」变成一个谁也说不清的数；
// 2. **存不下 / 读不出 / 坏值一律回标准档**（读不清就用默认，不能因为一段坏记录把正文缩成看不清）；
// 3. 持久化只走 `localStorage` 的最小面（取成接口 —— 测试不必真有 window，隐私模式下访问都可能抛）。

/** 三档（顺序即从小到大：界面上的上一档 / 下一档靠它）。 */
export type DocFontSize = 'sm' | 'md' | 'lg'

/** 档位顺序（只此一份；界面加减档与测试都用它）。 */
export const DOC_FONT_SIZES: readonly DocFontSize[] = ['sm', 'md', 'lg'] as const

/** 默认档 = 标准（既有观感不变）。 */
export const DEFAULT_DOC_FONT_SIZE: DocFontSize = 'md'

/** 落点键（WebView2 按应用持久化；这是界面偏好，不塞进周报包 —— 包内容一个字节都不动）。 */
export const DOC_FONT_KEY = 'doyah.retro.docFont'

/** `localStorage` 的最小面（测试里给内存替身）。 */
export interface KeyValueStore {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
}

/** 是不是一个合法档位（外部进来的字符串都要过这一关）。 */
export function isDocFontSize(value: unknown): value is DocFontSize {
  return value === 'sm' || value === 'md' || value === 'lg'
}

/** 读回上次选的档（读不出 / 坏值 / 空 ⇒ 标准档）。 */
export function readDocFontSize(store: KeyValueStore | null | undefined): DocFontSize {
  if (!store) return DEFAULT_DOC_FONT_SIZE
  let raw: string | null = null
  try {
    raw = store.getItem(DOC_FONT_KEY)
  } catch {
    return DEFAULT_DOC_FONT_SIZE
  }
  const trimmed = (raw ?? '').trim()
  return isDocFontSize(trimmed) ? trimmed : DEFAULT_DOC_FONT_SIZE
}

/** 记住这一档（存不下就**算了**：偏好丢了不影响读正文，绝不能为此弹错）。 */
export function storeDocFontSize(store: KeyValueStore | null | undefined, size: DocFontSize): void {
  if (!store || !isDocFontSize(size)) return
  try {
    store.setItem(DOC_FONT_KEY, size)
  } catch {
    // 有意静默：写不进去只丢偏好
  }
}

/** 加一档 / 减一档（**到头就停在头上**，不绕回去 —— 绕回去会让人以为点错了）。 */
export function stepDocFontSize(current: DocFontSize, direction: -1 | 1): DocFontSize {
  const index = DOC_FONT_SIZES.indexOf(current)
  const base = index < 0 ? DOC_FONT_SIZES.indexOf(DEFAULT_DOC_FONT_SIZE) : index
  const next = base + (direction > 0 ? 1 : -1)
  if (next < 0) return DOC_FONT_SIZES[0]
  if (next >= DOC_FONT_SIZES.length) return DOC_FONT_SIZES[DOC_FONT_SIZES.length - 1]
  return DOC_FONT_SIZES[next]
}

/** 这一档的界面 class（正文容器的 class 由它派生；CSS 只认这三个名字）。 */
export function docFontClass(size: DocFontSize): string {
  return `retro__document--${isDocFontSize(size) ? size : DEFAULT_DOC_FONT_SIZE}`
}
