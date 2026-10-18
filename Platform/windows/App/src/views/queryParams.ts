// 填值面板的**纯逻辑**（FR-EXEC-17）：行状态、缺值判定、回执文案。
//
// 为什么单独一份而不是写在 `DatabaseView.vue` 里：组件里的条件（「哪个算填了」「缺哪个」）
// 一旦和模板混在一起就只能靠挂载测试间接验；这几条恰恰是「缺值不许执行」这条规矩的判据所在，
// 抽出来就能用纯函数逐条测。
//
// 两条口径：
// 1. **NULL 不需要填值**（值本来就被忽略），其余类型必须**用户碰过**才算填了 ——
//    空串对文本是**合法值**（空串与 NULL 是两件事），所以「填过再从输入框删空」必须算填了，
//    否则用户想绑一个空串会被面板卡住。
// 2. **默认类型是文本**：猜类型的代价是整条语句失败（`text = integer`），不猜。

import type { BoundParameter, ParamKind, ParamSite, ParamValue, ParameterBindOutcome } from '../ipc'

/** 面板上的一行（一个参数）。 */
export interface ParamRow {
  name: string
  occurrences: number
  positional: boolean
  kind: ParamKind
  value: string
  /** 用户是否碰过这个输入框（碰过之后删空 = 想要空串，不是「没填」） */
  touched: boolean
}

/** 可选的类型（顺序 = 面板上的下拉顺序）。 */
export const PARAM_KINDS: ParamKind[] = ['text', 'number', 'boolean', 'null']

/** 默认类型：文本（最不会出错的那个）。 */
export const DEFAULT_PARAM_KIND: ParamKind = 'text'

/** 按扫描结果生成初始行（全部未碰过、类型为文本）。 */
export function initialRows(sites: ParamSite[]): ParamRow[] {
  return sites.map((site) => ({
    name: site.name,
    occurrences: site.occurrences,
    positional: site.positional,
    kind: DEFAULT_PARAM_KIND,
    value: '',
    touched: false,
  }))
}

/** 这一行算不算填好了（NULL 不需要值；其余要用户碰过输入框）。 */
export function isFilled(row: ParamRow): boolean {
  if (row.kind === 'null') return true
  return row.touched || row.value !== ''
}

/** 还缺哪些参数（**一次报全**，与领域层同一个口径）。 */
export function missingNames(rows: ParamRow[]): string[] {
  return rows.filter((row) => !isFilled(row)).map((row) => row.name)
}

/** 能不能提交（缺一个就不许执行 —— 不把半成品丢给服务端）。 */
export function canSubmit(rows: ParamRow[]): boolean {
  return rows.length > 0 && missingNames(rows).length === 0
}

/** 转成命令参数（顺序与面板一致；NULL 的值留空串，领域层会忽略它）。 */
export function toValues(rows: ParamRow[]): ParamValue[] {
  return rows.map((row) => ({ name: row.name, value: row.value, kind: row.kind }))
}

/** 一行回执（每个参数变成了什么类型、写成了什么样）。 */
export interface BindingLine {
  name: string
  kind: ParamKind
  occurrences: number
  literal: string
}

/** 回执数据（组件按当前语言拼句子；纯逻辑不碰文案）。 */
export function bindingLines(outcome: ParameterBindOutcome): BindingLine[] {
  return outcome.params.map((param: BoundParameter) => ({
    name: param.name,
    kind: param.kind,
    occurrences: param.occurrences,
    literal: param.literal,
  }))
}

/**
 * 给了值、但 SQL 里没有这些参数的提示（多半是拼错）。
 * 空表 = 没有多余值（**不**输出「一切正常」这种话）。
 */
export function unusedHint(outcome: ParameterBindOutcome): string {
  return outcome.unused.join('、')
}
