// 审计汇总的**纯函数判据**（`FR-AI-24` ①）：求和规则只有这一处。
//
// 挂载测负责「画得对不对」，这里负责「算得对不对」—— 两处分开，改一边不会把另一边带走。
import { describe, expect, it } from 'vitest'
import type { AgentAuditRecord } from '../ipc'
import { auditTotals, hasUsage } from './auditTotals'

function record(over: Partial<AgentAuditRecord> = {}): AgentAuditRecord {
  return {
    atSecs: 1,
    verdict: 'ok',
    model: 'm',
    endpoint: 'http://127.0.0.1:1/v1',
    summary: '问',
    detail: '',
    durationMs: 1,
    tableCount: 0,
    inputTokens: 0,
    outputTokens: 0,
    ...over,
  }
}

describe('auditTotals', () => {
  it('空账回全 0 且 withUsage=0（界面据此写「没记到」，不画 0 个 token）', () => {
    const totals = auditTotals([])
    expect(totals).toEqual({ records: 0, sent: 0, input: 0, output: 0, withUsage: 0 })
  })

  it('只合计记到用量的那几条，没记到的不算进 withUsage', () => {
    const totals = auditTotals([
      record({ inputTokens: 120, outputTokens: 34 }),
      record({ verdict: 'failed', inputTokens: 9, outputTokens: 1 }),
      record({ verdict: 'blocked', inputTokens: 0, outputTokens: 0 }),
    ])
    expect(totals.records).toBe(3)
    expect(totals.input).toBe(129)
    expect(totals.output).toBe(35)
    expect(totals.withUsage).toBe(2)
  })

  it('「出网」只数过网的两档（blocked / throttled 一条请求都没发）', () => {
    const totals = auditTotals([
      record({ verdict: 'ok' }),
      record({ verdict: 'failed' }),
      record({ verdict: 'blocked' }),
      record({ verdict: 'throttled' }),
    ])
    expect(totals.sent).toBe(2)
    expect(totals.records).toBe(4)
  })

  it('旧账（字段缺失）按 0 计，不猜', () => {
    const legacy = record()
    // 模拟字段上线前落盘的记录：键根本不存在。
    delete (legacy as Partial<AgentAuditRecord>).inputTokens
    delete (legacy as Partial<AgentAuditRecord>).outputTokens
    expect(auditTotals([legacy])).toEqual({
      records: 1,
      sent: 1,
      input: 0,
      output: 0,
      withUsage: 0,
    })
    expect(hasUsage(legacy)).toBe(false)
  })

  it('只有一边非零也算记到了（有的端点只回输出 token）', () => {
    expect(hasUsage(record({ inputTokens: 0, outputTokens: 7 }))).toBe(true)
    expect(hasUsage(record({ inputTokens: 7, outputTokens: 0 }))).toBe(true)
    expect(hasUsage(record({ inputTokens: 0, outputTokens: 0 }))).toBe(false)
  })
})
