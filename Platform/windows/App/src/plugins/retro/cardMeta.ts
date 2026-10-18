// 卡片上的两条元信息：**生成时间**与**封面的 MIME**（`FR-R-13-08` 判据① 的最后两个字段）。
//
// 为什么单独成模块（而不是写在组件里）：
//   ① 时间规范化有一串退化形状（带偏移 / 带毫秒 / 只有日期 / 空格分隔 / 空 / 形状不认识），
//      这些要在纯函数上逐条钉住，挂载测只能证明「画出来了」；
//   ② 封面的 MIME 由后缀派生 —— 判定「这个后缀合不合法」在 Rust（`retro_package::normalize_asset_path`），
//      这一侧只负责把合法后缀翻译成 `Blob` 要的 type，**不重做一遍白名单**。
//
// 时间口径（写死，别再改）：
//   · **不换算时区**：包里写的是带偏移的 ISO（`2026-10-18T09:30:00+08:00`）⇒ 显示包里那个**墙上时间**。
//     生成时间描述的是「生成侧那一刻」，按读的人所在时区再转一次会让同一份包在两台机器上显示不同数字；
//   · 能匹配 `YYYY-MM-DD[ T]HH:mm` 才规范化（去掉秒、毫秒与时区尾巴），只有日期就只显示日期；
//   · **非空但形状不认识 ⇒ 原样显示**（如实转述，不猜、不编）；
//   · 空串 ⇒ 空串（调用方翻成「未标注」）。

const DATE_TIME = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})/
const DATE_ONLY = /^(\d{4})-(\d{2})-(\d{2})$/

/** 包里写的生成时间 → 卡片上要显示的那一行；空串表示「包里没写」。 */
export function formatGeneratedAt(raw: string): string {
  const text = raw.trim()
  if (!text) return ''
  const full = DATE_TIME.exec(text)
  if (full) return `${full[1]}-${full[2]}-${full[3]} ${full[4]}:${full[5]}`
  const day = DATE_ONLY.exec(text)
  if (day) return `${day[1]}-${day[2]}-${day[3]}`
  return text
}

/** 后缀 → MIME（只覆盖 Rust 白名单里那几种；其余给通用二进制）。 */
const MIME_BY_EXTENSION: Record<string, string> = {
  png: 'image/png',
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  webp: 'image/webp',
  gif: 'image/gif',
  mp4: 'video/mp4',
  m4v: 'video/mp4',
}

/**
 * 封面的 `Blob` MIME。
 *
 * 后缀**大小写不敏感**（Rust 侧按 `to_ascii_lowercase` 判过）；没后缀 / 不认识 ⇒ `application/octet-stream`
 * —— 浏览器仍按内容解码图片，这里不为了好看把类型猜成 `image/png`。
 */
export function coverMime(target: string): string {
  const base = target.split(/[\\/]/).pop() ?? ''
  const dot = base.lastIndexOf('.')
  if (dot < 0 || dot === base.length - 1) return 'application/octet-stream'
  return MIME_BY_EXTENSION[base.slice(dot + 1).toLowerCase()] ?? 'application/octet-stream'
}
