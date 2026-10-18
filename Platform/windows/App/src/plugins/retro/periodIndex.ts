// 左栏的「按年·月归组 + 关键词过滤」（`FR-R-13-08` 判据① 的折叠与过滤两项）。
//
// 为什么单独成一个纯函数模块：
//   ① 挂载测只能证明「画出来了」，归组键的退化情形（没日期 / 没月份 / 期号也不像年份）
//      要在纯函数上逐条钉住，否则界面上只是「看起来分了组」；
//   ② 卡片顺序的**默认**真值在 Rust（`retro_package::collect`：新在前、同期号字典序）——
//      这里**只做保序切分，不再排一次**；用户显式切档「按期号」时的那一次重排
//      在 `cardSort.ts`（单一口径，见其文件头），本模块仍只负责保序切分。
//
// 归组键的口径（顺序即优先级）：
//   ① `dateStart` 的 `YYYY-MM`；② `dateEnd` 的 `YYYY-MM`；
//   ③ 期号前缀 `^(\d{4})`（只到年，月份记「未标注」）；④ 都没有 ⇒ 年、月都记「未标注」。
//   **不按 `generatedAt` 归组**：那是机器生成时刻，补跑一次包就换一组，日期范围才是内容事实。

import type { RetroCard } from '../../ipc'

/** 一个月里的一批卡片（组内顺序 = 传入顺序）。 */
export interface MonthGroup {
  /** `01`~`12`；`''` = 未标注。 */
  month: string
  cards: RetroCard[]
}

/** 一年里的一批月份组。 */
export interface YearGroup {
  /** `2026` 这类四位年；`''` = 未标注。 */
  year: string
  months: MonthGroup[]
  /** 该年下卡片总数（表头右侧的计数）。 */
  count: number
}

const DATE_PREFIX = /^(\d{4})-(\d{2})/
const YEAR_PREFIX = /^(\d{4})/

/** 从一段 `YYYY-MM-DD` 里取年月；不是这个形状就返回 `null`（不猜）。 */
function monthOfDate(text: string): { year: string; month: string } | null {
  const hit = DATE_PREFIX.exec(text.trim())
  if (!hit) return null
  return { year: hit[1], month: hit[2] }
}

/**
 * 一张卡归到哪一年哪一月。
 *
 * 依次看 `dateStart` → `dateEnd` → 期号前缀；全都不成立时返回两个空串（界面画「未标注」）。
 */
export function periodKey(card: RetroCard): { year: string; month: string } {
  const fromStart = monthOfDate(card.dateStart)
  if (fromStart) return fromStart
  const fromEnd = monthOfDate(card.dateEnd)
  if (fromEnd) return fromEnd
  const fromPeriod = YEAR_PREFIX.exec(card.period.trim())
  if (fromPeriod) return { year: fromPeriod[1], month: '' }
  return { year: '', month: '' }
}

/**
 * 按年 → 月把卡片切组。
 *
 * 两条纪律：① **保序**：组按首次出现顺序排（上游已是最新在前），组内顺序不动；
 * ② **合并同名组**：万一上游顺序不是严格连续的（同一年被别的年份夹开），并进同一组而不是画两次。
 */
export function groupCards(cards: RetroCard[]): YearGroup[] {
  const years: YearGroup[] = []
  const yearIndex = new Map<string, YearGroup>()

  for (const card of cards) {
    const { year, month } = periodKey(card)
    let group = yearIndex.get(year)
    if (!group) {
      group = { year, months: [], count: 0 }
      yearIndex.set(year, group)
      years.push(group)
    }
    group.count += 1
    let bucket = group.months.find((entry) => entry.month === month)
    if (!bucket) {
      bucket = { month, cards: [] }
      group.months.push(bucket)
    }
    bucket.cards.push(card)
  }

  return years
}

/**
 * 关键词过滤。
 *
 * 口径：空白分隔的多个词是 **AND**（每个词都要命中）；每个词对
 * 期号 / 标题 / 标签 / 日期起止 做**大小写不敏感**子串匹配。
 * 空查询（或全是空白）⇒ 原样返回全量（同一个数组引用，调用方可以据此判「没在筛」）。
 */
export function filterCards(cards: RetroCard[], query: string): RetroCard[] {
  const terms = query
    .toLowerCase()
    .split(/\s+/)
    .filter((term) => term.length > 0)
  if (!terms.length) return cards

  return cards.filter((card) => {
    const haystack = [card.period, card.title, ...card.tags, card.dateStart, card.dateEnd]
      .join('\n')
      .toLowerCase()
    return terms.every((term) => haystack.includes(term))
  })
}
