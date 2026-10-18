// 「读过的文件带进后续请求」的纯逻辑判据（`FR-AI-18` 收口）。
//
// 六条：① 批准且读到的进 ② 被拒绝 / 没读到的不进 ③ 同份按路径小写去重、取最后一次
//       ④ 份数上限（超出的是**最旧的**） ⑤ 字符上限（放不下的单列，不静默丢） ⑥ 最近读到的在前
import { describe, expect, it } from 'vitest'
import {
  CHAT_CARRY_MAX_CHARS,
  CHAT_CARRY_MAX_FILES,
  carryOf,
  type CarriedFile,
} from './chatCarry'
import type { AgentToolRun } from '../ipc'

function run(path: string, over: Partial<AgentToolRun> = {}): AgentToolRun {
  const content = over.content ?? `内容:${path}`
  return {
    name: 'read_file',
    path,
    approved: true,
    ok: true,
    chars: content.length,
    truncated: false,
    problem: '',
    content,
    ...over,
  }
}

describe('carryOf', () => {
  it('批准的带进上下文，被拒绝 / 没读到的一个都不带', () => {
    const summary = carryOf([
      run('src/a.ts', { content: 'AAA' }),
      run('src/b.ts', { approved: false, ok: false, chars: 0, content: '', problem: '你拒绝了' }),
      run('src/c.ts', { ok: false, chars: 0, content: '', problem: '读不到' }),
    ])
    expect(summary.files.map((file) => file.path)).toEqual(['src/a.ts'])
    expect(summary.chars).toBe(3)
    // 没读到的不进「没带上」清单：它们已经在「这一轮读到了什么」那栏单列过原因了。
    expect(summary.dropped).toEqual([])
  })

  it('没读到的即便带着正文也不带（`ok = false` 是唯一真值）', () => {
    // 形状上不该出现（外壳在拒绝 / 越界时会把正文留空），但万一哪天外壳标错，
    // 这一条必须拦得住 —— 否则「模型没看到的东西」会被当成它看过。
    const summary = carryOf([run('src/a.ts', { ok: false, content: '本该没读到' })])
    expect(summary.files).toEqual([])
  })

  it('标了读到却没有正文 ⇒ 没有东西可带（也不编一份空的）', () => {
    const summary = carryOf([run('src/a.ts', { ok: true, content: '' })])
    expect(summary.files).toEqual([])
    expect(summary.chars).toBe(0)
  })

  it('同一份（大小写不同）只带一次，正文取最后一次读到的', () => {
    const summary = carryOf([
      run('src/App.ts', { content: '第一版' }),
      run('src/app.ts', { content: '第二版，更长一些' }),
    ])
    expect(summary.files).toHaveLength(1)
    expect(summary.files[0].path).toBe('src/app.ts')
    expect(summary.files[0].content).toBe('第二版，更长一些')
    expect(summary.chars).toBe('第二版，更长一些'.length)
  })

  it('份数到顶 ⇒ 只带最近的 N 份，最旧的列进「没带上」并写明原因', () => {
    const runs: AgentToolRun[] = []
    for (let index = 0; index <= CHAT_CARRY_MAX_FILES; index += 1) {
      runs.push(run(`src/f${index}.ts`, { content: 'x' }))
    }
    const summary = carryOf(runs)
    expect(summary.files).toHaveLength(CHAT_CARRY_MAX_FILES)
    // 最近读到的在前：最后补进来的那份在第一位，最旧的（f0）被淘汰。
    expect(summary.files[0].path).toBe(`src/f${CHAT_CARRY_MAX_FILES}.ts`)
    expect(summary.files.map((file) => file.path)).not.toContain('src/f0.ts')
    expect(summary.dropped).toEqual([{ path: 'src/f0.ts', chars: 1, reason: 'tooMany' }])
  })

  it('字符到顶 ⇒ 放不下的单列成 tooBig，已收下的字符总数不超上限', () => {
    const big = 'y'.repeat(10_000)
    const summary = carryOf([
      run('src/old.ts', { content: big }),
      run('src/mid.ts', { content: big }),
      run('src/new.ts', { content: big }),
    ])
    expect(summary.files.map((file) => file.path)).toEqual(['src/new.ts', 'src/mid.ts'])
    expect(summary.chars).toBeLessThanOrEqual(CHAT_CARRY_MAX_CHARS)
    expect(summary.dropped).toEqual([
      { path: 'src/old.ts', chars: big.length, reason: 'tooBig' },
    ])
  })

  it('一条账都没有时是空上下文（不清空、不报错）', () => {
    const summary = carryOf([])
    expect(summary.files).toEqual([])
    expect(summary.dropped).toEqual([])
    expect(summary.chars).toBe(0)
  })

  it('没给路径的账不进上下文（没有「一份文件」可谈）', () => {
    const summary = carryOf([run('', { content: '某个工具的输出' })])
    expect(summary.files).toEqual([])
    expect(summary.dropped).toEqual([])
  })
})

describe('carryOf 的类型面', () => {
  it('带出去的就是 { path, content } 两件（不多塞字段）', () => {
    const sample: CarriedFile = carryOf([run('src/a.ts')]).files[0]
    expect(Object.keys(sample).sort()).toEqual(['content', 'path'])
  })
})
