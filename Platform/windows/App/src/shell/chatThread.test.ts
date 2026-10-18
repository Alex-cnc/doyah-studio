// 对话页签的纯逻辑判据（`FR-AI-25` 第一片）。
//
// 三条口径各一条判据：历史原样上行 / 超预算**如实拒绝并报数**（不静默丢历史）/ 回包只在成功时入历史。
import { describe, expect, it } from 'vitest'
import { CHAT_MAX_CHARS, CHAT_MAX_TURNS, budgetOf, outgoingTurns, questionCount, withReply } from './chatThread'
import type { AgentChatTurn } from '../ipc'

const history: AgentChatTurn[] = [
  { role: 'user', content: '第一问' },
  { role: 'assistant', content: '第一答' },
]

describe('对话页签的纯逻辑', () => {
  it('空草稿不发：这一问必须是真写了字', () => {
    const result = outgoingTurns(history, '   ')
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.problem).toContain('要问什么')
  })

  it('历史原样上行：只追加这一问，不改写既有消息', () => {
    const result = outgoingTurns(history, '  第二问  ')
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.turns).toHaveLength(3)
    expect(result.turns[0]).toBe(history[0])
    expect(result.turns[1]).toBe(history[1])
    expect(result.turns[2]).toEqual({ role: 'user', content: '第二问' })
  })

  it('超条数上限：如实报实际数与上限，且不产出可发的整段（不静默丢最早几轮）', () => {
    const long: AgentChatTurn[] = []
    for (let index = 0; index < CHAT_MAX_TURNS; index += 1) {
      long.push({ role: index % 2 === 0 ? 'user' : 'assistant', content: `第 ${index} 条` })
    }
    const result = outgoingTurns(long, '再来一问')
    expect(result.ok).toBe(false)
    if (result.ok) return
    expect(result.problem).toContain(String(CHAT_MAX_TURNS))
    expect(result.problem).toContain(String(CHAT_MAX_TURNS + 1))
  })

  it('超字符上限：同样如实报数（用例说明函数真在算长度，不是只看条数）', () => {
    const big: AgentChatTurn[] = [{ role: 'user', content: 'x'.repeat(CHAT_MAX_CHARS) }]
    const result = outgoingTurns(big, '再问一句')
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.problem).toContain(String(CHAT_MAX_CHARS))
  })

  it('回包接在历史后面：角色是 assistant，历史一条不少', () => {
    const next = withReply(history, '第二答')
    expect(next).toHaveLength(3)
    expect(next[2]).toEqual({ role: 'assistant', content: '第二答' })
    expect(questionCount(next)).toBe(1)
  })

  it('用量读数只算不改：budgetOf 不改动传进来的历史', () => {
    const before = JSON.stringify(history)
    const budget = budgetOf(history, '再问')
    expect(JSON.stringify(history)).toBe(before)
    expect(budget.turns).toBe(3)
    expect(budget.chars).toBe('第一问第一答再问'.length)
    expect(budget.over).toBe(false)
  })
})
