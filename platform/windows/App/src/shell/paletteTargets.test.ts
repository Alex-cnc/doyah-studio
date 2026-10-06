// 面板里的可检索对象 —— 行为判据（alpha 2.9）
//
// 守的三件事：
//   ① **id 能反解**（选中后只按 id 分派，不回查清单）；
//   ② 条数**封顶**（文件命中可能上千条，面板只给几十条，其余靠工作区检索看）；
//   ③ 相对路径整体当关键词（打路径片段也能搜到，不只靠文件名）。

import { describe, expect, it } from 'vitest'
import {
  FILE_PREFIX,
  fileToItem,
  MAX_OPENABLE_ITEMS,
  mergeItems,
  OBJECT_PREFIX,
  objectToItem,
  targetOf,
  type Target,
} from './paletteTargets'

describe('文件与对象转成面板条目', () => {
  it('文件：标题取文件名、相对路径当关键词', () => {
    const item = fileToItem('src/inner/agent-notes.md', false)
    expect(item.id).toBe(`${FILE_PREFIX}src/inner/agent-notes.md`)
    expect(item.title).toBe('agent-notes.md')
    expect(item.keywords).toContain('src/inner/agent-notes.md')
    expect(item.group).toBe('文件')
  })

  it('对象：带 schema 限定名与种类', () => {
    const item = objectToItem('app', 'orders', 'table')
    expect(item.id).toBe(`${OBJECT_PREFIX}app.orders`)
    expect(item.title).toBe('orders')
    expect(item.keywords).toContain('app.orders')
    expect(item.group).toContain('table')
  })
})

describe('id 反解（分派只看这里）', () => {
  it('三种目标都能反解出来', () => {
    const cases: [string, Target][] = [
      [`${FILE_PREFIX}src/a.rs`, { kind: 'file', relativePath: 'src/a.rs' }],
      [`${OBJECT_PREFIX}public.orders`, { kind: 'object', schema: 'public', name: 'orders' }],
      ['workspace.newFile', { kind: 'command', id: 'workspace.newFile' }],
    ]
    for (const [id, expected] of cases) {
      expect(targetOf(id)).toEqual(expected)
    }
  })

  it('边界：没有 schema 的对象、名字里带点的表名取**最后**一个点', () => {
    expect(targetOf(`${OBJECT_PREFIX}orders`)).toEqual({ kind: 'object', schema: '', name: 'orders' })
    // `app.my.table` ⇒ schema=app.my、name=table（最后一个点才是 schema 与名字的分界）
    expect(targetOf(`${OBJECT_PREFIX}app.my.table`)).toEqual({
      kind: 'object',
      schema: 'app.my',
      name: 'table',
    })
  })

  it('以 file: 开头的相对路径也能安全反解（不误判成对象或命令）', () => {
    expect(targetOf(`${FILE_PREFIX}a/b/c.txt`)).toEqual({ kind: 'file', relativePath: 'a/b/c.txt' })
    // 空相对路径也照实给（界面上不该出现，但反解不许抛）
    expect(targetOf(FILE_PREFIX)).toEqual({ kind: 'file', relativePath: '' })
  })
})

describe('合并清单', () => {
  it('命令在前，对象封顶', () => {
    const commands = [{ id: 'c1', title: '命令', keywords: [], group: '组' }]
    const many = Array.from({ length: MAX_OPENABLE_ITEMS + 50 }, (_, i) => fileToItem(`f${i}.txt`, false))
    const merged = mergeItems(commands, many)
    expect(merged[0].id).toBe('c1')
    expect(merged.length).toBe(1 + MAX_OPENABLE_ITEMS)
    // 封顶后仍在的那条要能反解
    expect(targetOf(merged[merged.length - 1].id).kind).toBe('file')
  })

  it('没有可打开对象时只剩命令（不硬凑）', () => {
    const commands = [{ id: 'c1', title: '命令', keywords: [], group: '组' }]
    expect(mergeItems(commands, []).map((i) => i.id)).toEqual(['c1'])
  })
})
