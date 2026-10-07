// 构建标识（标题栏版本格）—— 纯函数，**不 import 任何 `.vue`**。
//
// 为什么要它：对外交付的截图只含网页内容、**不含系统标题栏**（S-073b 实测：WebView2 CDP 的
// `Page.captureScreenshot` 不画标题栏）⇒「这是哪一份构建（短号 / 时刻）」必须同时落到**界面里**，
// 才在截图里看得见。
//
// 契约（S-073c）：
//   · 满值（`buildHead` 与 `buildTime` 皆非空）⇒ `v<version> · <buildHead> · <buildTime>`；
//   · 缺 `buildHead` / 缺 `buildTime` / 两者皆缺（含空串 / `null` 入参）⇒ **一律退化为** `v<version>`；
//   · 任何情况下输出里都不许出现 `undefined` / `null` / `unknown` 字样。

/** 本函数要的三段（结构化取用；`AppInfo` 满足它，测试可只给需要的段）。 */
export interface BuildStampSource {
  version?: string | null
  buildHead?: string | null
  buildTime?: string | null
}

/** 段间分隔符：与窗口标题同口径的 `·`（U+00B7）。 */
const STAMP_SEPARATOR = ' · '

/** 取一段可用文本：非字符串 / 空串 / 纯空白一律当「没有」。 */
function text(value: string | null | undefined): string {
  return typeof value === 'string' ? value.trim() : ''
}

/**
 * 把 `AppInfo`（或其子集）渲染成标题栏版本格的那一行。
 * 缺任一段即退化为 `v<version>`（绝不把 `undefined` / `null` 之类漏到界面上）。
 */
export function buildStamp(info: BuildStampSource | null | undefined): string {
  const version = text(info?.version)
  const head = text(info?.buildHead)
  const time = text(info?.buildTime)
  if (head !== '' && time !== '') {
    return `v${version}${STAMP_SEPARATOR}${head}${STAMP_SEPARATOR}${time}`
  }
  return `v${version}`
}
