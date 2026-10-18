// 编辑面诊断的**绘制层**（FR-EDIT-56）
//
// 分工必须说清：**规则在领域层判**（`Db/src/lint.rs::diagnose`，经 IPC `diagnose_sql` 下来），
// 本文件只做一件纯逻辑的事 —— 把「已经算好的诊断区间」叠到高亮片段上，切成可直接渲染的片段序列。
// 这里**不许**再判一次「字符串在哪结束 / 括号配不配平」（两套判定必然分叉，需求规范书明令禁止）。
//
// 三条不变量（用例守）：
//   ① 切完之后**拼接逐字等于原片段序列**（加下划线不许丢字符、不许加字符）；
//   ② 诊断区间一律夹进全文；空区间（`end <= start`）忽略 —— 画不出东西；
//   ③ 同一段落在多条诊断里 ⇒ 取**最严重**的那条（error > warning > info）。

import type { SqlToken } from '../ipc'
import type { HighlightPiece } from '../sql/editor'

export type Severity = 'error' | 'warning' | 'info'

/** 一条诊断（与领域层 `db::lint::Diagnostic` 同形状；偏移是**字符下标**）。 */
export interface Diagnostic {
  start: number
  end: number
  severity: Severity
  message: string
}

/** 带诊断标记的高亮片段：`severity` 为空 = 这段没问题。 */
export interface DecoratedPiece {
  text: string
  kind: SqlToken['kind']
  severity?: Severity
}

const WEIGHT: Record<Severity, number> = { error: 0, warning: 1, info: 2 }

/** 一组严重度里最严重的那个（空数组给 `undefined`）。 */
export function worstSeverity(list: Severity[]): Severity | undefined {
  let worst: Severity | undefined
  for (const severity of list) {
    if (worst === undefined || WEIGHT[severity] < WEIGHT[worst]) worst = severity
  }
  return worst
}

/**
 * 把诊断区间叠到高亮片段上。
 *
 * @param pieces      高亮片段（拼接 = 编辑器全文）
 * @param diagnostics 领域层给的诊断（已夹过界的也会再夹一次 —— 界面不能因为一条越界诊断白屏）
 */
export function decoratePieces(pieces: HighlightPiece[], diagnostics: Diagnostic[]): DecoratedPiece[] {
  const total = pieces.reduce((sum, piece) => sum + piece.text.length, 0)
  const clamp = (value: number): number => Math.max(0, Math.min(value, total))
  const ranges = diagnostics
    .map((item) => ({
      start: clamp(Math.min(item.start, item.end)),
      end: clamp(Math.max(item.start, item.end)),
      severity: item.severity,
    }))
    .filter((item) => item.end > item.start)

  if (ranges.length === 0) return pieces.map((piece) => ({ text: piece.text, kind: piece.kind }))

  const out: DecoratedPiece[] = []
  let offset = 0
  for (const piece of pieces) {
    const pieceStart = offset
    const pieceEnd = offset + piece.text.length
    // 切点 = 片段两端 + 落在片段内部的诊断端点
    const bounds = new Set<number>([pieceStart, pieceEnd])
    for (const range of ranges) {
      if (range.start > pieceStart && range.start < pieceEnd) bounds.add(range.start)
      if (range.end > pieceStart && range.end < pieceEnd) bounds.add(range.end)
    }
    const sorted = [...bounds].sort((a, b) => a - b)
    for (let index = 0; index + 1 < sorted.length; index += 1) {
      const from = sorted[index]
      const to = sorted[index + 1]
      const hits = ranges.filter((range) => range.start < to && range.end > from).map((range) => range.severity)
      const severity = worstSeverity(hits)
      out.push({
        text: piece.text.slice(from - pieceStart, to - pieceStart),
        kind: piece.kind,
        ...(severity ? { severity } : {}),
      })
    }
    offset = pieceEnd
  }
  return out
}
