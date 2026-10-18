// 左栏「排序口径」（`FR-R-12-01` 判据② 的「期号可排序」那半）。
//
// 三条纪律：
//   ① **默认不排**：`default` 原样返回**同一个数组**（Rust `retro_package::collect` 已按
//      生成时间 / 发布日倒序、同期号字典序排好）—— 前端不产生第二套**默认**排序真值；
//   ② 用户显式切档（`period-desc` / `period-asc`）时才排一次，且**每一档都只有一个口径**；
//      排出来的是展示次序，不回写任何数据、不影响上游的卡片顺序；
//   ③ 期号用**字典序**（UTF-16 码元比较，不用「数字感知」）：
//      期号形态允许 `2026-W42` / `20261005` / 任意目录名混存；把三种形态混在一起做
//      「数字感知」序**排出来并不是日期序**（`2026-W42` 会排到 `20261005` 后面），
//      那是伪精度。字典序是确定性的，同一命名制下（全是 `YYYY-Www` 或全是 `YYYYMMDD`）
//      恰好就是时间序 —— 界面则如实写「期号 Z→A / A→Z」，不承诺日期语义。
//
// 稳定性：`Array.prototype.sort` 自 ES2019 起是稳定的，同号（理论上去重后期号唯一，
// 但坏包 / 手改目录名可能撞）保持上游给的相对次序，不会因切档而随机换位。

import type { RetroCard } from '../../ipc'

/** 左栏排序档位（`default` = 沿用上游顺序，不排）。 */
export type CardSort = 'default' | 'period-desc' | 'period-asc'

/** 界面上给用户的三个选项（顺序 = 下拉框里的顺序）。 */
export const CARD_SORTS: readonly CardSort[] = ['default', 'period-desc', 'period-asc']

/**
 * 按档位给出**展示次序**。
 *
 * - `default` ⇒ 同一个数组引用（调用方可以据此判「没在重排」）；
 * - `period-desc` / `period-asc` ⇒ 新数组（传入的数组一个元素都不动）。
 */
export function sortCards(cards: RetroCard[], mode: CardSort): RetroCard[] {
  if (mode === 'default') return cards
  const direction = mode === 'period-asc' ? 1 : -1
  return cards.slice().sort((left, right) => {
    if (left.period === right.period) return 0
    return (left.period < right.period ? -1 : 1) * direction
  })
}
