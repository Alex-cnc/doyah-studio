// 对象树（1.1）第三层与两档视图 —— 正例 + **负例**
//
// 负例是这一族的重点：每一条都在证「判据真的抓得到它声称抓的东西」——
// 不过滤系统 schema、大小写混写的漏网、逐表各问一次（N+1）、列层丢表、切换丢节点。
import { describe, it, expect } from 'vitest'

import type { ObjectNode, TableColumns } from '../ipc'
import {
  SYSTEM_SCHEMA_EXACT,
  columnLabel,
  groupByKind,
  isSystemSchema,
  loadColumns,
  mergeColumns,
  tableKey,
  treeNodeCount,
  userSchemas,
  type ColumnsByTable,
  type ColumnsFetcher,
} from './objectTree'

function obj(schema: string, name: string, kind: ObjectNode['kind']): ObjectNode {
  return { schema, name, kind }
}

/** 一张 3 张表 / 2 个 schema 的图。 */
function sampleObjects(): ObjectNode[] {
  return [
    obj('app', 'orders', 'table'),
    obj('app', 'accounts', 'table'),
    obj('app', 'v_totals', 'view'),
    obj('public', 'orders_archive', 'table'),
    obj('public', 'seq_ids', 'sequence'),
  ]
}

describe('系统 schema 过滤（FR-META-04）', () => {
  it('四个系统族都认得出来，用户 schema 一个都不误伤', () => {
    expect(isSystemSchema('pg_catalog')).toBe(true)
    expect(isSystemSchema('information_schema')).toBe(true)
    expect(isSystemSchema('pg_toast')).toBe(true)
    expect(isSystemSchema('pg_toast_temp_3')).toBe(true)
    expect(isSystemSchema('pg_temp_1')).toBe(true)
    expect(isSystemSchema('app')).toBe(false)
    expect(isSystemSchema('public')).toBe(false)
    expect(isSystemSchema('my_pg_like')).toBe(false)
  })

  it('过滤保持输入顺序，且结果里一个系统 schema 都没有', () => {
    const kept = userSchemas([
      'app',
      'pg_catalog',
      'information_schema',
      'pg_toast_temp_3',
      'public',
    ])
    expect(kept).toEqual(['app', 'public'])
    expect(kept.every((name) => !isSystemSchema(name))).toBe(true)
  })

  it('负例：不过滤的写法必须被「不许出现系统 schema」抓到', () => {
    // 故意原样返回 = 漏了过滤 ⇒ 断言当场判红
    const unfiltered = ['app', 'pg_catalog', 'information_schema']
    expect(unfiltered.some((name) => isSystemSchema(name))).toBe(true)
  })

  it('负例：按精确小写匹配的朴素写法会漏掉大小写混写的系统名', () => {
    const mixed = ['PG_Catalog', 'pg_ToAst_all', 'Public']
    // 我们的实现把它们摘干净
    expect(isSystemSchema('PG_Catalog')).toBe(true)
    expect(isSystemSchema('pg_ToAst_all')).toBe(true)
    expect(userSchemas(mixed)).toEqual(['Public'])
    // 朴素写法（只比 `SYSTEM_SCHEMA_EXACT` 的精确小写）确实会漏 —— 说明上面那条断言不是白写的
    const naive = (name: string) => !(SYSTEM_SCHEMA_EXACT as readonly string[]).includes(name)
    expect(mixed.some(naive)).toBe(true)
  })
})

describe('列节点（FR-META-01 / -05）', () => {
  it('列名与类型原文一起显示，类型不缩写', () => {
    expect(columnLabel({ name: 'name', dataType: 'character varying(50)' })).toBe(
      'name · character varying(50)',
    )
    expect(columnLabel({ name: 'total', dataType: 'numeric(12,2)' })).toBe('total · numeric(12,2)')
  })

  it('类型缺失就不留那个分隔号（不显示 `id · `）', () => {
    expect(columnLabel({ name: 'id', dataType: '' })).toBe('id')
  })

  it('列层按 `schema.表名` 归位，并进已有层时不动别的层', () => {
    const groups: TableColumns[] = [
      { schema: 'app', table: 'orders', columns: [{ name: 'id', dataType: 'integer' }] },
    ]
    const merged = mergeColumns({ [tableKey('app', 'accounts')]: [] }, groups)
    expect(Object.keys(merged).sort()).toEqual(['app.accounts', 'app.orders'])
    expect(merged[tableKey('app', 'orders')]).toHaveLength(1)
  })
})

describe('第三层取数：一层一次（不许 N+1）', () => {
  /** 计数替身：只数「被问了几次」。 */
  function countingFetcher(): { fetch: ColumnsFetcher; calls: () => number } {
    let calls = 0
    const fetch: ColumnsFetcher = async (schema, tables) => {
      calls += 1
      return tables.map((table) => ({
        schema,
        table,
        columns: [{ name: 'id', dataType: 'integer' }],
      }))
    }
    return { fetch, calls: () => calls }
  }

  it('三张表只问一次，且每张表都回来了', async () => {
    const { fetch, calls } = countingFetcher()
    const out = await loadColumns(fetch, 'public', ['a', 'b', 'c'])
    expect(calls()).toBe(1)
    expect(out.map((g) => g.table)).toEqual(['a', 'b', 'c'])
  })

  it('没有表要展开就一次都不问', async () => {
    const { fetch, calls } = countingFetcher()
    expect(await loadColumns(fetch, 'public', [])).toEqual([])
    expect(calls()).toBe(0)
  })

  it('负例：逐表各问一次（N+1）的写法计数 = 表数，被「计数 == 1」抓红', async () => {
    const { fetch, calls } = countingFetcher()
    // 反面写法：for 表 → 问一次（就是不许出现的那种形状）
    for (const table of ['a', 'b', 'c']) {
      await fetch('public', [table])
    }
    expect(calls()).toBe(3)
    expect(calls()).not.toBe(1)
  })
})

describe('两档视图切换（FR-META-15）', () => {
  it('按类型分组的组序 = 表 → 视图 → 序列，组内保持入参顺序', () => {
    const groups = groupByKind(sampleObjects())
    expect(groups.map((g) => g.kind)).toEqual(['table', 'view', 'sequence'])
    expect(groups[0].items.map((o) => o.name)).toEqual(['orders', 'accounts', 'orders_archive'])
    expect(groups[1].items.map((o) => o.name)).toEqual(['v_totals'])
    expect(groups[2].items.map((o) => o.name)).toEqual(['seq_ids'])
  })

  it('切换后节点数不变（对象一个不丢、也不重复）', () => {
    const objects = sampleObjects()
    const columns: ColumnsByTable = {
      [tableKey('app', 'orders')]: [
        { name: 'id', dataType: 'integer' },
        { name: 'total', dataType: 'numeric(12,2)' },
      ],
    }
    const hierarchy = treeNodeCount(objects, columns)
    const byKind = treeNodeCount(
      groupByKind(objects).flatMap((g) => g.items),
      columns,
    )
    expect(hierarchy).toBe(2 + 5) // 2 列 + 5 个对象
    expect(byKind).toBe(hierarchy)
  })

  it('负例：拿 can_browse 当分组键会把四类可浏览对象挤成一桶（按类型分组失真）', () => {
    const groups = groupByKind([
      obj('app', 't', 'table'),
      obj('app', 'v', 'view'),
      obj('app', 'mv', 'materialized_view'),
      obj('app', 'ft', 'foreign_table'),
    ])
    expect(groups).toHaveLength(4)
    expect(groups.every((g) => g.items.length === 1)).toBe(true)
  })

  it('负例：切换时漏掉某一类对象 ⇒ 节点数不等，判据判红', () => {
    const objects = sampleObjects()
    const columns = {}
    const full = groupByKind(objects).flatMap((g) => g.items)
    // 反面写法：只留表，漏掉视图 / 序列
    const truncated = full.filter((o) => o.kind === 'table')
    expect(treeNodeCount(truncated, columns)).not.toBe(treeNodeCount(objects, columns))
  })
})
