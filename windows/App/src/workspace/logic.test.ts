// 工作区纯逻辑层 —— 行为判据（alpha 2.0 骨架）
//
// 守的是三件在界面上很难发现、但一错就误导人的事：
//   ① 页签的"脏"标记必须**真的等于**领域层算出来的脏（不是前端另算一份）；
//   ② 树**按需展开**：没展开的目录**不许**把子项算进可见序列（否则键盘上下会走到看不见的行）；
//   ③ 符号链接**永不展开**（跟随会带来环与越界读）。

import { describe, expect, it } from 'vitest'
import type { FsEntry } from '../ipc'
import {
  entryGlyph,
  flattenTree,
  indentPx,
  neighbouringRow,
  tabLabel,
  toggleExpanded,
  workspaceDisplayName,
} from './logic'

function dir(name: string): FsEntry {
  return { name, relativePath: name, kind: 'directory', isExpandable: true }
}
function file(name: string): FsEntry {
  return { name, relativePath: name, kind: 'file', isExpandable: false }
}
function symlink(name: string): FsEntry {
  return { name, relativePath: name, kind: 'symlink', isExpandable: false }
}

describe('页签与标题的显示串', () => {
  it('脏页签带圆点，干净的不带', () => {
    expect(tabLabel('main.rs', false)).toBe('main.rs')
    expect(tabLabel('main.rs', true)).toBe('main.rs ●')
    // Home 页也走同一条规则（它只是标题不同）
    expect(tabLabel('首页', true)).toBe('首页 ●')
  })

  it('工作区名取最后一段，两种分隔符都认；没有就是空串（不编假路径）', () => {
    expect(workspaceDisplayName('D:\\proj\\doyah-studio')).toBe('doyah-studio')
    expect(workspaceDisplayName('/home/me/proj')).toBe('proj')
    expect(workspaceDisplayName('D:\\proj\\')).toBe('proj')
    expect(workspaceDisplayName(null)).toBe('')
    expect(workspaceDisplayName('')).toBe('')
  })
})

describe('树扁平化：只展开已展开的目录', () => {
  const tree: FsEntry[] = [dir('src'), file('README.md'), symlink('link-to-src')]
  const children: Record<string, FsEntry[]> = {
    src: [file('src/main.rs'), dir('src/sub')],
    'src/sub': [file('src/sub/deep.rs')],
  }
  const childrenOf = (path: string) => children[path]

  it('没展开任何目录 ⇒ 只看到第一层', () => {
    const rows = flattenTree(tree, new Set(), childrenOf)
    expect(rows.map((r) => r.entry.relativePath)).toEqual(['src', 'README.md', 'link-to-src'])
    expect(rows.every((r) => r.depth === 0)).toBe(true)
    expect(rows[0].expanded).toBe(false)
  })

  it('展开一层 ⇒ 子项进来且缩进加一档；再展开一层 ⇒ 孙子进来', () => {
    const one = flattenTree(tree, new Set(['src']), childrenOf)
    expect(one.map((r) => r.entry.relativePath)).toEqual([
      'src',
      'src/main.rs',
      'src/sub',
      'README.md',
      'link-to-src',
    ])
    expect(one[0].expanded).toBe(true)
    expect(one[1].depth).toBe(1)
    expect(one[2].depth).toBe(1)

    const two = flattenTree(tree, new Set(['src', 'src/sub']), childrenOf)
    expect(two.map((r) => r.entry.relativePath)).toContain('src/sub/deep.rs')
    expect(two.find((r) => r.entry.relativePath === 'src/sub/deep.rs')?.depth).toBe(2)
  })

  it('缓存里没有子项 ⇒ 当空（不假装有内容）', () => {
    const rows = flattenTree(tree, new Set(['src']), () => undefined)
    expect(rows.map((r) => r.entry.relativePath)).toEqual(['src', 'README.md', 'link-to-src'])
  })

  it('符号链接即使被塞进展开集合，也不展开它的子项', () => {
    const rows = flattenTree(tree, new Set(['link-to-src', 'src']), childrenOf)
    // 链接自己那行还在，但它后面**没有**多出任何行（不跟随）
    const linkIndex = rows.findIndex((r) => r.entry.relativePath === 'link-to-src')
    expect(linkIndex).toBe(rows.length - 1)
    expect(rows[linkIndex].expanded).toBe(false)
  })
})

describe('键盘上下（不循环、边界停住）', () => {
  const rows = flattenTree(
    [dir('src'), file('a.rs'), file('b.rs')],
    new Set(['src']),
    () => [file('src/inner.rs')],
  )

  it('往下 / 往上按顺序走', () => {
    expect(neighbouringRow(rows, 'src', 1)).toBe('src/inner.rs')
    expect(neighbouringRow(rows, 'src/inner.rs', 1)).toBe('a.rs')
    expect(neighbouringRow(rows, 'a.rs', -1)).toBe('src/inner.rs')
  })

  it('**到边界就停住**（不循环：循环会让"按了几次到底"不可数）', () => {
    const last = rows[rows.length - 1].entry.relativePath
    expect(neighbouringRow(rows, last, 1)).toBe(last)
    expect(neighbouringRow(rows, 'src', -1)).toBe('src')
  })

  it('当前没选中 / 选中项不在表里 ⇒ 从头或从尾开始', () => {
    expect(neighbouringRow(rows, null, 1)).toBe('src')
    expect(neighbouringRow(rows, null, -1)).toBe(rows[rows.length - 1].entry.relativePath)
    expect(neighbouringRow(rows, '不存在', 1)).toBe('src')
    expect(neighbouringRow(rows, '不存在', -1)).toBe(rows[rows.length - 1].entry.relativePath)
  })

  it('空表 / delta=0 都给安全的答案', () => {
    expect(neighbouringRow([], 'x', 1)).toBeNull()
    expect(neighbouringRow(rows, 'a.rs', 0)).toBe('a.rs')
  })
})

describe('展开开关与缩进', () => {
  it('目录能开来回；符号链接**永不展开**', () => {
    let expanded = new Set<string>()
    expanded = toggleExpanded(expanded, dir('src'))
    expect(expanded.has('src')).toBe(true)
    expanded = toggleExpanded(expanded, dir('src'))
    expect(expanded.has('src')).toBe(false)

    const after = toggleExpanded(expanded, symlink('link'))
    expect(after.has('link')).toBe(false)
    // 原集合不被改（纯函数）
    expect(expanded.has('link')).toBe(false)
  })

  it('缩进按层级线性增长，负数当 0', () => {
    expect(indentPx(0)).toBe(0)
    expect(indentPx(1)).toBe(12)
    expect(indentPx(3)).toBe(36)
    expect(indentPx(-2)).toBe(0)
    expect(indentPx(1.7)).toBe(12)
  })

  it('字形按类型区分（目录 / 文件 / 链接各不相同）', () => {
    expect(entryGlyph(dir('d'))).not.toBe(entryGlyph(file('f')))
    expect(entryGlyph(symlink('l'))).not.toBe(entryGlyph(dir('d')))
  })
})
