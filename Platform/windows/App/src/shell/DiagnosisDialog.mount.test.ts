// @vitest-environment happy-dom
// 诊断面板的**界面判据**（挂载真组件）：
//   · 四份证据按 e1~e4 渲染，**「没取到」的单列原因**（红字），不跟「零行」混；
//   · 资料块里带着取证 SQL 与编号（用户能复制去问模型）；
//   · 粘回来的回复里：有依据的结论采纳、没依据的拒绝、建议带风险判定且「放进编辑器」只发事件。
//
// 为什么必须挂载：这几条的真值都在**模板**上（哪一段渲染、点了发什么事件）——
// `tsc --noEmit` 不校验 .vue，纯逻辑测也看不到 DOM。
import { describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'

const replies = vi.hoisted(() => {
  return {
    plan: 'Seq Scan on orders  (cost=0.00..1.00 rows=1)',
    locks: { columns: ['waiting_pid'], rows: [] as (string | null)[][], truncated: false },
    slowError: null as Error | null,
    risk: 'confirm' as string,
    riskCalls: [] as string[],
  }
})

vi.mock('../ipc', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../ipc')>()
  return {
    ...actual,
    explainStatement: vi.fn(async () => replies.plan),
    dbQuery: vi.fn(async (sql: string) => {
      if (sql.includes('pg_locks')) return { ...replies.locks, rows: [], numRows: [], returned: 0, affected: null }
      throw new Error('relation "pg_stat_user_tables" 读不到（测试里故意）')
    }),
    slowQueries: vi.fn(async () => {
      if (replies.slowError) throw replies.slowError
      return {
        available: false,
        installed: false,
        availableExtension: false,
        preloaded: false,
        reason: '服务端没有 pg_stat_statements',
        steps: ['① 预加载', '② 重启', '③ 建扩展'],
        totalColumn: '',
        meanColumn: '',
        rowsOut: [],
      }
    }),
    statementRisk: vi.fn(async (sql: string) => {
      replies.riskCalls.push(sql)
      return replies.risk
    }),
  }
})

import DiagnosisDialog from './DiagnosisDialog.vue'

async function mountDialog(sql = 'select * from orders where buyer_id = 1') {
  replies.riskCalls = []
  const wrapper = mount(DiagnosisDialog, { props: { open: true, language: 'zh-Hans', sql } })
  await flushPromises()
  return wrapper
}

describe('诊断面板', () => {
  it('四份证据都渲染，编号是 e1~e4', async () => {
    const wrapper = await mountDialog()
    const ids = wrapper.findAll('.diag__item-id').map((node) => node.text())
    expect(ids).toEqual(['e1', 'e2', 'e3', 'e4'])
  })

  it('「没取到」单列原因，且与「查到了但没有行」分得开', async () => {
    const wrapper = await mountDialog()
    // e2 锁阻塞：查到了零行
    expect(wrapper.find('[data-status="empty"]').exists()).toBe(true)
    // e3 慢查询 + e4 表统计：没取到，各带原因
    const reasons = wrapper.findAll('[data-reason]').map((node) => node.text())
    expect(reasons.join('\n')).toContain('服务端没有 pg_stat_statements')
    expect(reasons.join('\n')).toContain('读不到')
    expect(wrapper.findAll('[data-status="unavailable"]').length).toBeGreaterThanOrEqual(2)
  })

  it('资料块里带编号与可复跑的取证 SQL（e1 那条 = EXPLAIN 原语句）', async () => {
    const wrapper = await mountDialog()
    const brief = (wrapper.find('[data-testid="diagnosis-brief"]').element as HTMLTextAreaElement).value
    expect(brief).toContain('【证据 e1】执行计划')
    expect(brief).toContain('EXPLAIN select * from orders where buyer_id = 1')
    expect(brief).toContain('未取到 —— 服务端没有 pg_stat_statements')
  })

  it('有依据的结论采纳、没依据的拒绝；建议带风险判定并只发 insert 事件（不执行）', async () => {
    const wrapper = await mountDialog()
    await wrapper.find('[data-testid="diagnosis-reply"]').setValue(
      ['结论: 这条查询在做全表扫描 [依据: e1]', '结论: 我觉得该加索引', '建议: create index on orders(buyer_id)'].join('\n'),
    )
    await wrapper.find('[data-testid="diagnosis-parse"]').trigger('click')
    await flushPromises()

    expect(wrapper.find('[data-testid="diagnosis-accepted-count"]').text()).toContain('2')
    expect(wrapper.find('[data-testid="diagnosis-rejected-count"]').text()).toContain('1')
    expect(wrapper.find('[data-reason="no_citation"]').exists()).toBe(true)
    // 风险判定问的是既有的 statementRisk（不在这里重判一遍）
    expect(replies.riskCalls).toEqual(['create index on orders(buyer_id)'])
    expect(wrapper.text()).toContain('会改数据')

    await wrapper.find('[data-testid="diagnosis-insert"]').trigger('click')
    expect(wrapper.emitted('insert')?.[0]).toEqual(['create index on orders(buyer_id)'])
  })

  it('引用没取到的证据也被拒（它支撑不了任何结论）', async () => {
    const wrapper = await mountDialog()
    await wrapper.find('[data-testid="diagnosis-reply"]').setValue('结论: 慢查询榜第一名很明显 [依据: e3]')
    await wrapper.find('[data-testid="diagnosis-parse"]').trigger('click')
    await flushPromises()
    expect(wrapper.find('[data-reason="unavailable_evidence"]').exists()).toBe(true)
  })

  it('关掉时整块不渲染（否定面：不许挂在界面上挡操作）', async () => {
    const wrapper = mount(DiagnosisDialog, { props: { open: false, language: 'zh-Hans', sql: 'select 1' } })
    await flushPromises()
    expect(wrapper.find('[data-testid="diagnosis-panel"]').exists()).toBe(false)
  })
})
