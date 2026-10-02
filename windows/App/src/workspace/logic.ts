// 工作区（alpha 2.0）的**纯逻辑层** —— 页签与文件树的判定/格式化
//
// 分工：Rust 侧（`windows/Db/src/workspace.rs`）管**领域规则**（脏标记怎么算、路径安不安全、
// 排序键、忽略名单）；本文件管**表示层自己的事**：显示串怎么拼、树展开状态怎么维护。
// 两边都不重复对方的规则 —— 前端不自己判断路径安全性（那会让"安全关"有两份实现）。
//
// 三条口径：
//   ① **显示串在这里拼**（`显示名 (3) ●`），但**领域不变量在 Rust**（脏 = 内容比出来）；
//   ② 树是**按需展开**的：`expanded` 只记"哪些目录被展开过"，子项从缓存里取；
//   ③ 目录与文件**都进可见序列**（键盘上下要走它们），展开状态决定要不要往下走一层。

import type { FsEntry } from '../ipc'

/** 一条可见的树行（扁平化之后）。 */
export interface TreeRow {
  entry: FsEntry
  /** 缩进层级（根的直接子项 = 0） */
  depth: number
  /** 目录已展开（符号链接永远 false：不跟随） */
  expanded: boolean
}

/** 页签栏上要显示的信息（把领域里的"脏"翻成给人看的串）。 */
export function tabLabel(title: string, isDirty: boolean): string {
  return isDirty ? `${title} ●` : title
}

/** 标题栏上的工作区名（取最后一段；没有就显示占位，不编一个假路径）。 */
export function workspaceDisplayName(root: string | null): string {
  if (!root) return ''
  const trimmed = root.replace(/[\\/]+$/, '')
  const parts = trimmed.split(/[\\/]/)
  return parts[parts.length - 1] || trimmed
}

/**
 * 树行扁平化：**只展开已展开的目录**（按需展开 —— 打开大工程不会卡）。
 *
 * `childrenOf(relativePath)` 由调用方给（缓存里取）；取不到就当空数组（**不假装有内容**）。
 */
export function flattenTree(
  roots: readonly FsEntry[],
  expanded: ReadonlySet<string>,
  childrenOf: (relativePath: string) => readonly FsEntry[] | undefined,
  depth = 0,
): TreeRow[] {
  const rows: TreeRow[] = []
  for (const entry of roots) {
    const isExpanded = entry.isExpandable && expanded.has(entry.relativePath)
    rows.push({ entry, depth, expanded: isExpanded })
    if (isExpanded) {
      rows.push(...flattenTree(childrenOf(entry.relativePath) ?? [], expanded, childrenOf, depth + 1))
    }
  }
  return rows
}

/**
 * 选中项的**下一个**位置（键盘 ↓ / ↑）。
 *
 * - `delta = +1` 往下、`-1` 往上；
 * - 到边界就**停住**（不循环 —— 循环会让"按了几次到底"变得不可数）；
 * - 当前没选中：往下从第一条开始、往上从最后一条开始。
 */
export function neighbouringRow(
  rows: readonly TreeRow[],
  selected: string | null,
  delta: number,
): string | null {
  if (rows.length === 0) return null
  if (delta === 0) return selected
  if (selected === null) {
    return delta > 0 ? rows[0].entry.relativePath : rows[rows.length - 1].entry.relativePath
  }
  const index = rows.findIndex((row) => row.entry.relativePath === selected)
  if (index < 0) {
    return delta > 0 ? rows[0].entry.relativePath : rows[rows.length - 1].entry.relativePath
  }
  const next = index + (delta > 0 ? 1 : -1)
  if (next < 0 || next >= rows.length) return selected
  return rows[next].entry.relativePath
}

/**
 * 展开 / 收起一个目录（返回**新的**集合）。
 *
 * 符号链接**永远不展开**（哪怕它指向目录）—— 跟随会带来环与"读到了工作区外面"两个问题，
 * 所以这里直接不响应，而不是"展开后再说"。
 */
export function toggleExpanded(
  expanded: ReadonlySet<string>,
  entry: FsEntry,
): Set<string> {
  const next = new Set(expanded)
  if (!entry.isExpandable) return next
  if (next.has(entry.relativePath)) {
    next.delete(entry.relativePath)
  } else {
    next.add(entry.relativePath)
  }
  return next
}

/** 层次缩进（像素）。根的直接子项不缩进，每深一层加一档。 */
export const INDENT_STEP_PX = 12

export function indentPx(depth: number): number {
  return Math.max(0, Math.trunc(depth)) * INDENT_STEP_PX
}

/** 条目类型 → 图标字形（语义名，不是字体图标库的键）。 */
export function entryGlyph(entry: FsEntry): string {
  if (entry.kind === 'directory') return entry.isExpandable ? '▸' : '·'
  if (entry.kind === 'symlink') return '↩'
  return '·'
}
