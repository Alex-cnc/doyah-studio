// 对象树（1.1）：第三层（表 → 列）+ 系统 schema 过滤 + 两档视图 —— **这几条规则的唯一出处**
//
// 为什么从 `DatabaseView.vue` 里抽出来：树上这几条规则（哪些 schema 该藏、列怎么显示、
// 两档视图怎么分、**一层问几次**）如果散在组件里就没法在测试里数「一层问了几次」——
// 而 N+1（逐表各问一次）正是这一层最顺手的写法。
//
// 与领域层同源：系统 schema 名单 / 列节点形状 / 按类型分组的组序，对侧与 `Db/src/tree.rs`
// 各有一份实现，**规则口径一致**（本侧按 Tauri + TS 的栈重写，不是翻译）。

import type { ColumnNode, ObjectNode, TableColumns } from '../ipc'

/** 系统 schema 的**字面名单**（对齐领域层 `tree::SYSTEM_SCHEMA_EXACT`，FR-META-04）。 */
export const SYSTEM_SCHEMA_EXACT = ['pg_catalog', 'information_schema'] as const
/** 系统 schema 的**前缀名单**（`pg_toast*` / `pg_temp*`）。 */
export const SYSTEM_SCHEMA_PREFIXES = ['pg_toast', 'pg_temp'] as const

/**
 * 这个 schema 是不是系统目录（**过滤规则只此一处**）。
 *
 * 大小写不敏感：服务端把标识符折成小写，但界面 / 测试里手写的 `PG_Catalog` 也得认出来
 * —— 按名字精确匹配的朴素写法会把它漏进树里（见负例）。
 */
export function isSystemSchema(name: string): boolean {
  const lower = name.trim().toLowerCase()
  return (
    (SYSTEM_SCHEMA_EXACT as readonly string[]).includes(lower) ||
    SYSTEM_SCHEMA_PREFIXES.some((prefix) => lower.startsWith(prefix))
  )
}

/** 摘掉系统 schema（**保持输入顺序**，不排序 —— 排序是调用方自己的事）。 */
export function userSchemas(names: string[]): string[] {
  return names.filter((name) => !isSystemSchema(name))
}

/** 列节点的一行文案：`列名 · 类型原文`（类型空就不留那个分隔号）。 */
export function columnLabel(column: ColumnNode): string {
  const type = column.dataType?.trim()
  return type ? `${column.name} · ${type}` : column.name
}

/** 一层取数的形状（`ipc.dbColumns` 就是它）。 */
export type ColumnsFetcher = (schema: string, tables: string[]) => Promise<TableColumns[]>

/**
 * 第三层取数：**恰调用取数一次**（不管几张表）。
 *
 * 空清单一次都不问（不无谓往返）。判据按**调用计数**钉死：
 * 逐表循环的写法（`loadColumnsOneByOne` 那种形状）计数 = 表的张数 ⇒ 当场判红。
 */
export async function loadColumns(
  fetch: ColumnsFetcher,
  schema: string,
  tables: string[],
): Promise<TableColumns[]> {
  if (tables.length === 0) return []
  return fetch(schema, tables)
}

/** 已加载的列：`schema.name` → 列。 */
export type ColumnsByTable = Record<string, ColumnNode[]>

/** 表在列层里的键（与树节点的键同一形状，避免两处各拼一遍）。 */
export function tableKey(schema: string, name: string): string {
  return `${schema}.${name}`
}

/** 把取回来的列层并进已有的列层（**不覆盖已有层的顺序**，按取回顺序并）。 */
export function mergeColumns(
  current: ColumnsByTable,
  groups: TableColumns[],
): ColumnsByTable {
  const next: ColumnsByTable = { ...current }
  for (const group of groups) {
    next[tableKey(group.schema, group.table)] = group.columns
  }
  return next
}

/** 两档视图：层级视图 / 按类型分组（FR-META-15）。 */
export type TreeMode = 'hierarchy' | 'byKind'

/** 种类权重（与领域层 `ObjectKind::order` 同序：表 → 视图 → 物化 → 外部表 → 序列 → 系统 → 其他）。 */
const KIND_ORDER = [
  'table',
  'view',
  'materialized_view',
  'foreign_table',
  'sequence',
  'system',
  'other',
] as const

function kindWeight(kind: string): number {
  const at = (KIND_ORDER as readonly string[]).indexOf(kind)
  return at === -1 ? KIND_ORDER.length : at
}

/**
 * 按**类型**分组（「按类型分组」那一档）。
 *
 * 组序 = 种类权重；**组内保持入参顺序**（不重排 —— 界面已经排过一遍，这里再排一次
 * 会让两种视图的顺序凭空不同）。认不出的种类归到 `other`，但**不合并**已认出的种类。
 */
export function groupByKind(objects: ObjectNode[]): { kind: string; items: ObjectNode[] }[] {
  const buckets = new Map<string, ObjectNode[]>()
  for (const object of objects) {
    const kind = object.kind || 'other'
    const list = buckets.get(kind)
    if (list) list.push(object)
    else buckets.set(kind, [object])
  }
  return [...buckets.entries()]
    .map(([kind, items]) => ({ kind, items }))
    .sort((a, b) => kindWeight(a.kind) - kindWeight(b.kind))
}

/**
 * 树的**数据行数**（不含表头 / 分组标题）—— = 对象数 + 已加载的列数。
 *
 * 两档视图（层级 / 按类型分组）只是同一批数据的两种排法 ⇒ 这个数**必须相等**；
 * 切换后数不一样就是「切换时丢东西了」，判据当场判红。
 */
export function treeNodeCount(objects: ObjectNode[], columns: ColumnsByTable): number {
  const loaded = Object.values(columns).reduce((sum, list) => sum + list.length, 0)
  return objects.length + loaded
}
