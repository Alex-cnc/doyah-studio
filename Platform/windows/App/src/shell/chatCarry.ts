// 「读过的文件带进后续请求」的**纯逻辑**（`FR-AI-18` 收口）。
//
// 为什么要单独一个模块：面板上要能离线断言「哪几份进了上下文、共多少字符、谁没带上」，
// 而挂载测只能看到「请求里带了什么、画出来长什么样」。两条判据分开写，改一边不会静默带走另一边。
//
// 五条口径（每条都有对应判据）：
// ① **只有真读到的进上下文**（`ok` 且正文非空；拒绝 / 越界 / 读不到时外壳把 `ok` 置 false 且
//    正文留空）—— 把「模型没看到的东西」当成它看过，比不带给模型更糟。
//    **判据只留一处真值**：`ok` 与「正文非空」两条各管一个失败面（外壳标错 / 正文丢了），
//    不再另判 `approved` —— 那一条与 `ok` 同义，写两遍会让注入打在空处还假绿；
// ② **同一份按路径小写去重，以最后一次读到的为准**（Windows 卷不区分大小写）：
//    重读一次不该在上下文里出现两份、算两遍；
// ③ **有上限**（[`CHAT_CARRY_MAX_FILES`] 份 / [`CHAT_CARRY_MAX_CHARS`] 字符，与领域层同值）；
// ④ **放不下的必须列出来并写明原因** —— 静默丢会让用户以为模型看着整份上下文在回答；
// ⑤ **最近读到的优先**：预算不够时先保刚读到的（那多半正是当前这一问指着的东西）。

import type { AgentToolRun } from '../ipc'

/** 与领域层 `Db/src/agent_nl2sql.rs` 的 `CHAT_CARRY_MAX_FILES` 同一口径。 */
export const CHAT_CARRY_MAX_FILES = 6

/**
 * 与领域层 `CHAT_CARRY_MAX_CHARS` 同一口径。
 *
 * 计数用 JS 的 `length`（UTF-16 码元），领域层按 `chars()`（码点）算 —— 中文两者相同，
 * 表情等代理对会让这里**多算**，于是界面更早停手。方向是安全的：宁可少带，不会越过领域层的上限。
 */
export const CHAT_CARRY_MAX_CHARS = 24_000

/** 要带进后续请求的一份文件（形状与 `ipc.ts` 的 `AgentCarriedFile` 一致）。 */
export interface CarriedFile {
  path: string
  content: string
}

/** 没带上的原因：份数到顶 / 这一份就超出字符预算。 */
export type CarryDropReason = 'tooMany' | 'tooBig'

/** 没收进上下文的一份（要说出来，不许静默丢）。 */
export interface DroppedFile {
  path: string
  chars: number
  reason: CarryDropReason
}

/** 这一次请求会带上的上下文。 */
export interface CarrySummary {
  /** 真带上的（最近读到的在前）。 */
  files: CarriedFile[]
  /** 带上的正文合计字符数。 */
  chars: number
  /** 没带上的（按最近到最旧；同份只出现一次）。 */
  dropped: DroppedFile[]
}

/**
 * 把「逐件的执行账」收成「这一发要带上的上下文」。
 *
 * 从**最后一条**往前扫：先遇到的同一份就是「最后一次读到的」，后面的旧账直接跳过
 * （这正是口径 ②）；预算按扫到的顺序扣，扣不下的进 `dropped`（口径 ③④⑤）。
 */
export function carryOf(runs: readonly AgentToolRun[]): CarrySummary {
  const files: CarriedFile[] = []
  const dropped: DroppedFile[] = []
  const seen = new Set<string>()
  let chars = 0

  for (let index = runs.length - 1; index >= 0; index -= 1) {
    const run = runs[index]
    const path = run.path.trim()
    // 没有路径的（模型点了别的工具）没有「一份文件」可谈：它上一轮已经单列在「没读到」里。
    if (!path) continue
    const key = path.toLowerCase()
    if (seen.has(key)) continue
    seen.add(key)
    // 口径 ①：没真读到的（拒绝 / 越界 / 读不到）一律不带 —— 外壳在这几种情形下 `ok = false`。
    if (!run.ok) continue
    // 第二条腿：标了「读到了」却没有正文（旧外壳 / 回包丢了字段）⇒ 也没有东西可带。
    const content = run.content
    if (!content) continue
    const size = content.length
    if (files.length >= CHAT_CARRY_MAX_FILES) {
      dropped.push({ path, chars: size, reason: 'tooMany' })
      continue
    }
    if (chars + size > CHAT_CARRY_MAX_CHARS) {
      dropped.push({ path, chars: size, reason: 'tooBig' })
      continue
    }
    files.push({ path, content })
    chars += size
  }

  return { files, chars, dropped }
}
