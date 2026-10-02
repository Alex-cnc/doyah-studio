// 命令面板里的**可检索对象**（2.9：面板全文检索"文件 / 对象 / 笔记"）
//
// 口径：面板里除了命令，还能直接搜到**工作区里的文件**与**数据库对象** —— 选中即打开/跳过去。
// 这样"面板"与"工作区检索"**共用同一套搜索引擎**（都在 Rust 侧 `Db/src/search.rs`），
// 不再长第二套匹配。
//
// 三条纪律：
//   ① **对象与命令在同一张榜上排序**：都交给领域层 `palette` 统一打分排序
//      （否则会出现"命令永远排在文件前面"这种看不出理由的顺序）；
//   ② **id 要能反解**：`file:<相对路径>` / `object:<schema>.<表名>` —— 选中后据此分派，
//      不用再回查一遍清单；
//   ③ **条数要封顶**：文件命中可能上千条，面板里最多给几十条（**其余靠工作区检索去看**，
//      那里有分组与跳过报告）。

import type { PaletteItem } from '../ipc'

/** 对象种类前缀（**id 前缀就是分派依据**，别在别处再写一次判断）。 */
export const FILE_PREFIX = 'file:'
export const OBJECT_PREFIX = 'object:'

/** 面板里最多显示多少个可打开对象（命令不限）。 */
export const MAX_OPENABLE_ITEMS = 30

/** 把一个工作区文件转成面板条目。 */
export function fileToItem(relativePath: string, showHidden: boolean): PaletteItem {
  const name = relativePath.split('/').pop() ?? relativePath
  return {
    id: `${FILE_PREFIX}${relativePath}`,
    title: name,
    // 相对路径整体当关键词 ⇒ 打路径片段也能搜到（不只靠文件名）
    keywords: [relativePath, showHidden ? 'hidden' : ''],
    group: '文件',
  }
}

/** 把一个数据库对象转成面板条目。 */
export function objectToItem(schema: string, name: string, kind: string): PaletteItem {
  return {
    id: `${OBJECT_PREFIX}${schema}.${name}`,
    title: name,
    keywords: [`${schema}.${name}`, kind],
    group: `对象 · ${kind}`,
  }
}

/** 从面板条目的 id 反解出"这是个什么"（**分派只看这里**）。 */
export type Target =
  | { kind: 'file'; relativePath: string }
  | { kind: 'object'; schema: string; name: string }
  | { kind: 'command'; id: string }

export function targetOf(id: string): Target {
  if (id.startsWith(FILE_PREFIX)) {
    return { kind: 'file', relativePath: id.slice(FILE_PREFIX.length) }
  }
  if (id.startsWith(OBJECT_PREFIX)) {
    const rest = id.slice(OBJECT_PREFIX.length)
    const dot = rest.lastIndexOf('.')
    if (dot > 0) {
      return { kind: 'object', schema: rest.slice(0, dot), name: rest.slice(dot + 1) }
    }
    return { kind: 'object', schema: '', name: rest }
  }
  return { kind: 'command', id }
}

/** 合并命令清单与可打开对象（**命令在前**，但排序交给领域层统一做）。 */
export function mergeItems(commands: readonly PaletteItem[], openables: readonly PaletteItem[]): PaletteItem[] {
  return [...commands, ...openables.slice(0, MAX_OPENABLE_ITEMS)]
}
