// 审计账的**汇总读数**（`FR-AI-24` ①：一屏就能看到「这一阵子发了多少次、花了多少 token」）。
//
// 为什么收成纯函数：弹层只负责画。求和规则一旦散在模板里（`records.reduce` 写两遍），
// 「明细之和 ≠ 汇总」这种自相矛盾就没有任何东西能判出来。

import type { AgentAuditRecord } from '../ipc'

/** 一屏审计的汇总。 */
export interface AuditTotals {
  /** 记录条数（含没过网的那几条）。 */
  records: number
  /** 真出网的条数（只有「成功 / 失败」过网）。 */
  sent: number
  /** 输入 token 合计（只合计记到的那几条）。 */
  input: number
  /** 输出 token 合计。 */
  output: number
  /** 记到用量的条数（0 ⇒ 整屏都没有用量，界面要说「没记到」而不是画两个 0）。 */
  withUsage: number
}

/**
 * 求和。
 *
 * - 空态回全 0（`withUsage = 0` ⇒ 界面画「没记到」，不画 `0 tokens`）；
 * - 旧账（`inputTokens` 字段上线前落盘的）没有这两个键 ⇒ 按 0 计，**不猜**。
 */
export function auditTotals(records: AgentAuditRecord[]): AuditTotals {
  let sent = 0
  let input = 0
  let output = 0
  let withUsage = 0
  for (const record of records) {
    if (record.verdict === 'ok' || record.verdict === 'failed') sent += 1
    const recordInput = record.inputTokens ?? 0
    const recordOutput = record.outputTokens ?? 0
    input += recordInput
    output += recordOutput
    if (recordInput > 0 || recordOutput > 0) withUsage += 1
  }
  return { records: records.length, sent, input, output, withUsage }
}

/** 一条记录有没有记到用量（0 / 0 = 没记到，不是「用了 0 个」）。 */
export function hasUsage(record: AgentAuditRecord): boolean {
  return (record.inputTokens ?? 0) > 0 || (record.outputTokens ?? 0) > 0
}
