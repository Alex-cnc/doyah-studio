// 对象树**节点类型 → 图标**（FR-META-06）—— **这张映射表的唯一出处**
//
// 需求点名的是「库 / 模式 / 表 / 视图 / 列 / 函数」六类（对侧验收要点 = `DatabaseObject.symbolName`）；
// 本侧的树**还能renders出**更多类型（物化视图 / 外部表 / 序列 / 系统目录 / 服务器节点），所以
// 这张表按**树上真能出现的节点**穷举 —— 少一类就会让那一类悄悄退化成"别的图标"。
//
// 两条口径：
// ① **每类一个专属图标**，不许两类共用一个（共用就把"类型区分"这件需求本身做没了）；
// ② **认不出的类型给兜底图标**（`unknown`），不抛错、也不悄悄当成"表" ——
//    服务端将来多出一种 relkind 时，界面照常能画出来，只是图标是兜底那个。
//
// 为什么是"语义名"而不是 SVG 路径：映射（哪类节点配哪个图标）与画法（路径长什么样）是两件事。
// 画法在 `NodeIcon.vue` 一处；这张表只决定"用哪个"。判据因此能逐类对账，不必解析 SVG。

/** 树上一个节点画什么图标（**语义名**，不是字体名 / SF Symbol 名）。 */
export type NodeGlyph =
  | 'server'
  | 'database'
  | 'schema'
  | 'table'
  | 'view'
  | 'materializedView'
  | 'foreignTable'
  | 'sequence'
  | 'system'
  | 'function'
  | 'column'
  | 'other'
  | 'unknown'

/** 认不出的类型兜底用哪个图标（FR-META-06 的"未知类型兜底"）。 */
export const NODE_GLYPH_FALLBACK: NodeGlyph = 'unknown'

/**
 * 节点类型名 → 图标（**穷举**）。
 *
 * 键取的是契约里的类型名（对象节点用领域层 `ObjectKind` 的 snake_case 序列化名；树的行类型
 * 另加 `server` / `schema` / `column`）。**没有** `default` 分支以外的兜底：认不出就是 `unknown`。
 */
const NODE_GLYPHS: Record<string, NodeGlyph> = {
  // 服务器节点（FR-META-11 第一期那个）：整棵树/整个连接列表的根
  server: 'server',
  // 库 / 模式 / 表 / 视图 / 列 / 函数 —— 需求点名的那六类
  database: 'database',
  schema: 'schema',
  table: 'table',
  view: 'view',
  column: 'column',
  function: 'function',
  // 本侧树上还会出现的其余对象类型（各给各的图标，不合并）
  materialized_view: 'materializedView',
  foreign_table: 'foreignTable',
  sequence: 'sequence',
  system: 'system',
  other: 'other',
}

/** 节点类型 → 图标语义名（认不出给兜底，**绝不抛错**）。 */
export function nodeGlyph(kind: string): NodeGlyph {
  const key = kind.trim().toLowerCase()
  return NODE_GLYPHS[key] ?? NODE_GLYPH_FALLBACK
}

/** 这张表覆盖到的类型名（判据用它做"穷举"对账 —— 缺哪类当场看得见）。 */
export function knownNodeKinds(): string[] {
  return Object.keys(NODE_GLYPHS)
}
