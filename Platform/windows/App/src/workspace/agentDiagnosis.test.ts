// `workspace/agentDiagnosis.ts` 的行为判据（FR-AI-03）。
//
// 每条都钉一条口径：证据三态**不许混**、资料块**可复跑**、回复解析**按引用放行或拒绝**。
import { describe, expect, it } from 'vitest'
import {
  LOCK_SQL,
  buildBrief,
  evidenceFromPlan,
  evidenceFromRows,
  evidenceFromSlowReport,
  evidencePlan,
  evidenceUnavailable,
  parseAdvice,
  slowEvidenceSql,
  type EvidenceItem,
} from './agentDiagnosis'
import type { SlowQueryReport } from '../ipc'

const titles: Record<string, string> = {
  'diag.evidence.plan': '执行计划',
  'diag.evidence.locks': '锁阻塞',
  'diag.evidence.slow': '慢查询统计',
  'diag.evidence.stats': '表访问统计',
}
const titleOf = (spec: { titleKey: string }): string => titles[spec.titleKey] ?? spec.titleKey

function item(id: string, overrides: Partial<EvidenceItem> = {}): EvidenceItem {
  return {
    id,
    kind: 'locks',
    titleKey: 'diag.evidence.locks',
    sql: 'select 1',
    status: 'rows',
    columns: ['a'],
    rows: [['1']],
    truncated: false,
    reason: '',
    ...overrides,
  }
}

describe('证据规划（FR-AI-03 硬约束：不许把语句真跑一遍）', () => {
  it('四份证据按 e1~e4 编号，执行计划那条是 EXPLAIN 而不是 EXPLAIN ANALYZE', () => {
    const plan = evidencePlan('  select * from orders  ')
    expect(plan.map((spec) => spec.id)).toEqual(['e1', 'e2', 'e3', 'e4'])
    expect(plan[0].sql).toBe('EXPLAIN select * from orders')
    expect(plan[0].sql.toUpperCase()).not.toContain('ANALYZE')
  })

  it('锁阻塞那条是真能复跑的 SQL（不是占位串）', () => {
    const locks = evidencePlan('select 1')[1]
    expect(locks.sql).toBe(LOCK_SQL)
    expect(locks.sql).toContain('pg_locks')
    expect(locks.sql).toContain('granted')
  })

  it('慢查询那条的取证 SQL 跟着服务端版本换列名', () => {
    expect(slowEvidenceSql('total_time', 'mean_time')).toContain('ORDER BY total_time')
    expect(slowEvidenceSql('total_exec_time', 'mean_exec_time')).toContain('ORDER BY total_exec_time')
  })
})

describe('证据三态：有行 / 零行 / 没取到（三者不许混成一句）', () => {
  it('有行 → rows，NULL 单元格显示成 NULL（不跟空串混）', () => {
    const evidence = evidenceFromRows(evidencePlan('select 1')[1], ['a', 'b'], [['1', null]])
    expect(evidence.status).toBe('rows')
    expect(evidence.rows).toEqual([['1', 'NULL']])
  })

  it('查到了但没有行 → empty（不是错误、也不是没取到）', () => {
    const evidence = evidenceFromRows(evidencePlan('select 1')[1], ['a'], [])
    expect(evidence.status).toBe('empty')
    expect(evidence.reason).toBe('')
  })

  it('没取到 → unavailable 且必须带原因', () => {
    const evidence = evidenceUnavailable(evidencePlan('select 1')[2], '服务端没有 pg_stat_statements')
    expect(evidence.status).toBe('unavailable')
    expect(evidence.reason).toContain('pg_stat_statements')
    expect(evidence.rows).toEqual([])
  })

  it('执行计划按行切成单列，空行不算行（**行首缩进保留**：计划树靠它表达层级）', () => {
    const evidence = evidenceFromPlan(evidencePlan('select 1')[0], 'Seq Scan on orders\n\n  cost=0.0\n')
    expect(evidence.status).toBe('rows')
    expect(evidence.rows).toEqual([['Seq Scan on orders'], ['  cost=0.0']])
  })

  it('慢查询排行不可用 ⇒ 未取到 + 三步指引（不是空列表冒充「没有慢查询」）', () => {
    const report: SlowQueryReport = {
      available: false,
      installed: false,
      availableExtension: false,
      preloaded: false,
      reason: '服务端没有这份扩展',
      steps: ['① 预加载', '② 重启', '③ 建扩展'],
      totalColumn: '',
      meanColumn: '',
      rowsOut: [],
    }
    const evidence = evidenceFromSlowReport(evidencePlan('select 1')[2], report)
    expect(evidence.status).toBe('unavailable')
    expect(evidence.reason).toContain('服务端没有这份扩展')
    expect(evidence.reason).toContain('② 重启')
  })

  it('慢查询排行可用 ⇒ 按总耗时列出可断言的行', () => {
    const report: SlowQueryReport = {
      available: true,
      installed: true,
      availableExtension: true,
      preloaded: true,
      reason: null,
      steps: [],
      totalColumn: 'total_exec_time',
      meanColumn: 'mean_exec_time',
      rowsOut: [{ query: 'select 1', calls: 7, totalMs: 120.5, meanMs: 17.2, rows: 1, truncated: false }],
    }
    const evidence = evidenceFromSlowReport(evidencePlan('select 1')[2], report)
    expect(evidence.status).toBe('rows')
    expect(evidence.rows[0][1]).toBe('7')
    expect(evidence.columns).toEqual(['query', 'calls', 'total', 'mean'])
  })
})

describe('资料块（给人复制去问模型）', () => {
  const items = [
    evidenceFromPlan(evidencePlan('select 1')[0], 'Seq Scan on orders  (cost=0.00..1.00 rows=1)'),
    evidenceUnavailable(evidencePlan('select 1')[2], '服务端没有 pg_stat_statements'),
    evidenceFromRows(evidencePlan('select 1')[1], ['waiting_pid'], []),
  ]

  it('每份证据都带编号与可复跑的取证 SQL，没取到的把原因写进去', () => {
    const brief = buildBrief(items, titleOf)
    expect(brief.text).toContain('【证据 e1】执行计划')
    expect(brief.text).toContain('取证 SQL: EXPLAIN select 1')
    expect(brief.text).toContain('未取到 —— 服务端没有 pg_stat_statements')
    expect(brief.text).toContain('查到了，但没有行')
    expect(brief.droppedChars).toBe(0)
  })

  it('超长时从尾部砍并如实报砍了多少字符（不静默截断）', () => {
    const long = [evidenceFromPlan(evidencePlan('select 1')[0], 'x'.repeat(500))]
    const brief = buildBrief(long, titleOf, 120)
    expect(brief.droppedChars).toBeGreaterThan(0)
    expect(brief.text).toContain('没有带上')
  })
})

describe('回复解析（没有依据的结论整条拒绝）', () => {
  const evidence = [item('e1'), item('e2'), item('e3', { status: 'unavailable', rows: [], reason: '没装扩展' })]

  it('有依据的结论被采纳，依据编号原样带出来', () => {
    const parsed = parseAdvice('结论: 这条查询在做全表扫描 [依据: e1]', evidence)
    expect(parsed.accepted).toHaveLength(1)
    expect(parsed.accepted[0]).toMatchObject({ kind: 'conclusion', citations: ['e1'], forConclusion: null })
    expect(parsed.rejected).toEqual([])
  })

  it('没有 [依据: …] 的结论整条拒绝（不许靠语气过关）', () => {
    const parsed = parseAdvice('结论: 我猜是索引没建好', evidence)
    expect(parsed.accepted).toEqual([])
    expect(parsed.rejected[0].reason).toBe('no_citation')
  })

  it('引用不存在的编号 ⇒ 拒绝并点名那个编号', () => {
    const parsed = parseAdvice('结论: 锁太多 [依据: e9]', evidence)
    expect(parsed.rejected[0].reason).toBe('unknown_evidence')
    expect(parsed.rejected[0].detail).toContain('e9')
  })

  it('引用「没取到」的证据也拒绝（它本来就支撑不了任何结论）', () => {
    const parsed = parseAdvice('结论: 慢查询榜第一名很明显 [依据: e3]', evidence)
    expect(parsed.rejected[0].reason).toBe('unavailable_evidence')
  })

  it('建议归属最近的已采纳结论；前面没有结论的建议被拒', () => {
    const parsed = parseAdvice(
      ['建议: create index on orders(buyer_id)', '结论: 缺索引 [依据：e1、e2]', '建议: create index on orders(buyer_id)'].join('\n'),
      evidence,
    )
    expect(parsed.rejected.map((row) => row.reason)).toEqual(['orphan_suggestion'])
    const suggestions = parsed.accepted.filter((row) => row.kind === 'suggestion')
    expect(suggestions).toHaveLength(1)
    expect(suggestions[0].forConclusion).toBe(1)
    expect(suggestions[0].citations).toEqual(['e1', 'e2'])
  })

  it('空建议被拒，认不出的行原样留着（不静默丢）', () => {
    const parsed = parseAdvice(['结论: 缺索引 [依据: e1]', '建议:', '另外我觉得可以加个分区'].join('\n'), evidence)
    expect(parsed.rejected.map((row) => row.reason)).toEqual(['empty_suggestion'])
    expect(parsed.unrecognized).toEqual(['另外我觉得可以加个分区'])
  })

  it('行首的列表符号剥掉不影响识别', () => {
    const parsed = parseAdvice('- 结论: 缺索引 [依据: e1]', evidence)
    expect(parsed.accepted).toHaveLength(1)
    expect(parsed.accepted[0].text).toBe('缺索引')
  })
})
