// 「这一轮模型读到了哪几份文件」的纯函数判据（`FR-AI-18` 收口）。
//
// 判的是**口径**，不是排版：同一份只算一份、字符取最后一次、被拒绝 / 没读到的不算进上下文
// 但必须列出来（用户要知道模型不知道什么）、以最后一次决定为准。
import { describe, expect, it } from 'vitest'

import type { AgentToolRun } from '../ipc'
import { contextOf } from './chatContext'

function run(path: string, over: Partial<AgentToolRun> = {}): AgentToolRun {
  return {
    name: 'read_file',
    path,
    approved: true,
    ok: true,
    chars: 10,
    truncated: false,
    problem: '',
    content: '',
    kind: 'read',
    bytes: 0,
    added: 0,
    removed: 0,
    undo: '',
    ...over,
  }
}

describe('对话「已读文件」读数', () => {
  it('什么都没读 ⇒ 空读数（面板不出现，也不编一行 0）', () => {
    const summary = contextOf([])
    expect(summary.files).toEqual([])
    expect(summary.misses).toEqual([])
    expect(summary.chars).toBe(0)
  })

  it('写过的文件不冒充「读到了」：写那件不进这一栏（也不占一行 0 字符）', () => {
    const summary = contextOf([
      run('src/a.ts', { name: 'write_file', kind: 'write', chars: 0, content: '', bytes: 20, added: 2, removed: 0, undo: 't-1' }),
      run('src/b.ts', { chars: 66 }),
    ])
    expect(summary.files.map((file) => file.path)).toEqual(['src/b.ts'])
    expect(summary.chars).toBe(66)
    expect(summary.misses).toEqual([])
  })

  it('同一份文件读两次 ⇒ 只一行、字符取最后一次、读了几次单独记', () => {
    const summary = contextOf([
      run('src/a.ts', { chars: 40 }),
      run('src/a.ts', { chars: 120 }),
    ])
    expect(summary.files.length).toBe(1)
    expect(summary.files[0].path).toBe('src/a.ts')
    // 上下文里留的是最后那份：累加会把同一段正文算两遍（240 是错的）
    expect(summary.files[0].chars).toBe(120)
    expect(summary.files[0].reads).toBe(2)
    expect(summary.chars).toBe(120)
  })

  it('被拒绝的文件不算进上下文，但必须列出来（用户要知道模型没看到它）', () => {
    const summary = contextOf([
      run('src/a.ts', { chars: 40 }),
      run('src/b.ts', { approved: false, ok: false, chars: 0 }),
    ])
    expect(summary.files.map((file) => file.path)).toEqual(['src/a.ts'])
    expect(summary.misses.length).toBe(1)
    expect(summary.misses[0]).toMatchObject({ path: 'src/b.ts', reason: 'denied', problem: '' })
    // 拒绝那件一个字符都没给模型
    expect(summary.chars).toBe(40)
  })

  it('读失败要带原因，且同样不算进上下文', () => {
    const summary = contextOf([run('src/ghost.ts', { ok: false, chars: 0, problem: '找不到这个文件' })])
    expect(summary.files).toEqual([])
    expect(summary.misses[0]).toMatchObject({ path: 'src/ghost.ts', reason: 'failed', problem: '找不到这个文件' })
    expect(summary.chars).toBe(0)
  })

  it('以最后一次决定为准：先拒绝后允许 ⇒ 在上下文里；先允许后拒绝 ⇒ 不在', () => {
    const allowedLater = contextOf([
      run('src/a.ts', { approved: false, ok: false, chars: 0 }),
      run('src/a.ts', { chars: 88 }),
    ])
    expect(allowedLater.files.map((file) => file.path)).toEqual(['src/a.ts'])
    expect(allowedLater.misses).toEqual([])
    expect(allowedLater.chars).toBe(88)

    const deniedLater = contextOf([
      run('src/a.ts', { chars: 88 }),
      run('src/a.ts', { approved: false, ok: false, chars: 0 }),
    ])
    expect(deniedLater.files).toEqual([])
    expect(deniedLater.misses.map((miss) => miss.reason)).toEqual(['denied'])
    expect(deniedLater.chars).toBe(0)
  })

  it('同一份文件换个大小写写法 ⇒ 仍是同一份（Windows 卷不区分大小写）', () => {
    const summary = contextOf([run('src/App.ts', { chars: 30 }), run('src/app.ts', { chars: 50 })])
    expect(summary.files.length).toBe(1)
    expect(summary.files[0].chars).toBe(50)
    expect(summary.files[0].reads).toBe(2)
    expect(summary.chars).toBe(50)
  })

  it('模型没给路径 ⇒ 用工具名当身份，不画一行空路径', () => {
    const summary = contextOf([run('', { name: 'list_dir', chars: 7 })])
    expect(summary.files.length).toBe(1)
    expect(summary.files[0].path).toBe('')
    expect(summary.files[0].name).toBe('list_dir')
    expect(summary.files[0].key).toBe('tool:list_dir')
  })

  it('多份文件的总字符 = 各份最后一次之和（顺序按第一次出现）', () => {
    const summary = contextOf([
      run('src/b.ts', { chars: 100 }),
      run('src/a.ts', { chars: 5 }),
      run('src/b.ts', { chars: 200 }),
    ])
    expect(summary.files.map((file) => file.path)).toEqual(['src/b.ts', 'src/a.ts'])
    expect(summary.chars).toBe(205)
  })
})
