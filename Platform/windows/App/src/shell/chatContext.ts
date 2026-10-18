// 「这一轮模型读到了哪几份文件」的**纯逻辑**（`FR-AI-18` 收口）。
//
// 为什么单独一个模块：界面上必须能离线断言「哪几份进了模型的眼睛、各多少字符、谁没进去」，
// 而挂载测只能看到「画出来长什么样」。两条判据分开写，改一边不会静默带走另一边。
//
// 四条口径（每条都有对应判据）：
// ① **同一份文件按最后一次读到的算**：上下文里留的是最后那一份，把每次读到的字符数累加
//    会把同一段正文算两遍 ⇒ 报大的数比不报更糟；
// ② **读了几次单独记**：用户能看出「模型在同一个文件上来回读」；
// ③ **被拒绝 / 没读到的文件不进上下文**，单独列出来并写明原因 —— 用户才知道模型**不知道**什么，
//    而不是以为它读过；
// ④ **以最后一次决定为准**：先拒绝后允许 ⇒ 在上下文里；先允许后拒绝 ⇒ 不在。历史决定不进这一栏。

import type { AgentToolRun } from '../ipc'

/** 一份现在在模型手里的文件。 */
export interface ContextFile {
  /** 去重键（路径小写；没给路径时退化成工具名）。 */
  key: string
  /** 展示用路径（模型没给路径时为空串，组件退回工具名）。 */
  path: string
  /** 工具名（没给路径时它是唯一能写在界面上的身份）。 */
  name: string
  /** 最近一次读到的字符数（= 现在真正给到模型的那一份）。 */
  chars: number
  /** 同一个文件被读了几次。 */
  reads: number
  /** 最近那一份是否被截断。 */
  truncated: boolean
}

/** 没进上下文的（被拒绝 / 没读到）。 */
export interface ContextMiss {
  key: string
  path: string
  name: string
  /** `denied` = 用户拒绝；`failed` = 读了但没读到。 */
  reason: 'denied' | 'failed'
  /** 没读到的原因（`denied` 时为空串）。 */
  problem: string
}

/** 一个页签的「已读文件」读数。 */
export interface ContextSummary {
  /** 现在在上下文里的文件（按第一次出现的顺序）。 */
  files: ContextFile[]
  /** 没进上下文的（按第一次出现的顺序）。 */
  misses: ContextMiss[]
  /** 上下文里的字符总数（= 各文件最后一次读到的字符数之和）。 */
  chars: number
}

/**
 * 去重键：路径小写。
 *
 * 本面是 Windows（卷不区分大小写），`src/A.ts` 与 `src/a.ts` 是同一份 ⇒ 不归一就会在面板上
 * 出现两行、字符数也算两遍。没给路径的（模型点了没登记的工具）退化成工具名。
 */
function keyOf(run: AgentToolRun): string {
  const path = run.path.trim()
  return path ? `path:${path.toLowerCase()}` : `tool:${run.name}`
}

/** 把「逐件的执行账」收成一栏「模型这一轮读了什么」。 */
export function contextOf(runs: readonly AgentToolRun[]): ContextSummary {
  const seen = new Map<string, number>()
  for (const run of runs) {
    const key = keyOf(run)
    seen.set(key, (seen.get(key) ?? 0) + 1)
  }

  const order: string[] = []
  const last = new Map<string, AgentToolRun>()
  for (const run of runs) {
    const key = keyOf(run)
    if (!last.has(key)) order.push(key)
    last.set(key, run)
  }

  const files: ContextFile[] = []
  const misses: ContextMiss[] = []
  for (const key of order) {
    const run = last.get(key) as AgentToolRun
    const path = run.path.trim()
    const name = run.name
    if (!run.approved) {
      misses.push({ key, path, name, reason: 'denied', problem: '' })
      continue
    }
    if (!run.ok) {
      misses.push({ key, path, name, reason: 'failed', problem: run.problem.trim() })
      continue
    }
    files.push({
      key,
      path,
      name,
      chars: Math.max(0, run.chars),
      reads: seen.get(key) ?? 1,
      truncated: run.truncated,
    })
  }

  return { files, misses, chars: files.reduce((total, file) => total + file.chars, 0) }
}
