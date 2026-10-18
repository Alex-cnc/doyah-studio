// 对话页签的**纯逻辑**（`FR-AI-25` 第一片）：消息追加与预算。
//
// 为什么单独一个模块：界面里「这一问合不合法、要不要发」必须能离线断言，
// 而挂载测只能看到「点一下按钮之后长什么样」。两条判据分开写，改一边不会静默带走另一边。
//
// 三条口径（每一条都有对应判据）：
// ① **界面不裁剪历史**：超预算就**如实拒绝并报数**（`problem` 里带实际数与上限），
//    不静默丢掉最早的几轮 —— 悄悄丢会让模型答得莫名其妙，而用户看不出发生了什么；
// ② **历史原样上行**：`outgoingTurns` 只追加这一问，不改写任何既有消息；
// ③ **回包只在成功时入历史**：失败 / 被挡住 / 满额都不往历史里塞一条空的模型回复。

import type { AgentChatTurn } from '../ipc'

/** 与领域层 `Db/src/agent_nl2sql.rs` 的 `CHAT_MAX_TURNS` 同一口径（超了由那边也再挡一次）。 */
export const CHAT_MAX_TURNS = 40

/** 与领域层 `CHAT_MAX_CHARS` 同一口径。 */
export const CHAT_MAX_CHARS = 60_000

/** 一段对话的用量读数。 */
export interface TurnBudget {
  /** 已用条数（现有历史 + 这一问）。 */
  turns: number
  /** 已用字符数（现有历史 + 这一问）。 */
  chars: number
  limitTurns: number
  limitChars: number
  /** 是否超预算。 */
  over: boolean
}

/** 一段对话 + 待发的一句，算用量（**只算、不改**）。 */
export function budgetOf(turns: readonly AgentChatTurn[], draft = ''): TurnBudget {
  const draftChars = draft.trim().length
  const turns_ = turns.length + (draftChars > 0 ? 1 : 0)
  const chars = turns.reduce((total, turn) => total + turn.content.length, 0) + draftChars
  return {
    turns: turns_,
    chars,
    limitTurns: CHAT_MAX_TURNS,
    limitChars: CHAT_MAX_CHARS,
    over: turns_ > CHAT_MAX_TURNS || chars > CHAT_MAX_CHARS,
  }
}

/** 这一问能不能发：能 ⇒ `{ turns }`（历史 + 这一问，原样）；不能 ⇒ `{ problem }`（带实际数与上限）。 */
export type OutgoingTurns = { ok: true; turns: AgentChatTurn[] } | { ok: false; problem: string }

/** 组装**这一次要发出去的整段**（历史原样 + 这一问）。 */
export function outgoingTurns(
  turns: readonly AgentChatTurn[],
  draft: string,
  describe?: (budget: TurnBudget) => string,
): OutgoingTurns {
  const question = draft.trim()
  if (!question) {
    return { ok: false, problem: '先写一句要问什么。' }
  }
  const budget = budgetOf(turns, question)
  if (budget.over) {
    return {
      ok: false,
      problem: describe
        ? describe(budget)
        : `这一段对话太长了（${budget.turns} 条 / ${budget.chars} 字符，上限 ${budget.limitTurns} 条 / ${budget.limitChars} 字符）：先清空对话再问。`,
    }
  }
  return { ok: true, turns: [...turns, { role: 'user', content: question }] }
}

/** 把模型的回复接在历史后面（**只在成功时调用**）。 */
export function withReply(turns: readonly AgentChatTurn[], text: string): AgentChatTurn[] {
  return [...turns, { role: 'assistant', content: text }]
}

/** 这一段历史里问了几句（界面上「第 N 问」用；只数用户消息）。 */
export function questionCount(turns: readonly AgentChatTurn[]): number {
  return turns.filter((turn) => turn.role === 'user').length
}
