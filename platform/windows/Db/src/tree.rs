//! 对象树的对象清单与**对象搜索**（FR-CONN-15 / 1.1 段）
//!
//! 契约口径（与对侧行为同源，实现按本侧栈重写）：
//! ① **展开一层取一层**：树不在连接时把整库元数据一次拉光 —— 每层只问该层的孩子，
//!    所以本文件只做「一层之内」的**模型与判定**，取数在表示层（驱动只在那里）。
//! ② **搜索是纯函数**：对象搜索的匹配规则（大小写、限定名、schema 内点号、排序）只此一处，
//!    界面不另写一套（那是漂移的经典来源）。
//! ③ **名字里带点号/引号也要能搜**：`app."my.table"` 这类限定名照样能命中 ——
//!    匹配的是「schema 名 + 点 + 对象名」，不是先把限定名切开再拼。
//! ④ **空查询 = 空结果**（不是"全部"）：搜索框空着时界面显示的是**树的原貌**，
//!    不是把整库列成一张平表 —— 这条由调用方按 `query.is_empty()` 处理，这里如实返回空。

use serde::{Deserialize, Serialize};

/// 对象种类（树与搜索结果共用的分类；**不带显示文案** —— 文案在界面层）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ObjectKind {
    Table,
    View,
    MaterializedView,
    ForeignTable,
    Sequence,
    /// 系统目录（`pg_catalog` / `information_schema`）里的对象
    System,
    /// 认不出来的（不猜、不丢：如实归到这一档）
    Other,
}

impl ObjectKind {
    /// 服务端 `information_schema.table_type` / `pg_class.relkind` 的取值 → 本侧分类。
    ///
    /// 两套词表都要认（表 / 视图来自 information_schema，序列 / 物化视图来自 pg_class）。
    pub fn from_server(text: &str) -> Self {
        match text.trim().to_ascii_uppercase().as_str() {
            "BASE TABLE" | "TABLE" | "R" | "P" => ObjectKind::Table,
            "VIEW" | "V" => ObjectKind::View,
            "MATERIALIZED VIEW" | "M" => ObjectKind::MaterializedView,
            "FOREIGN" | "FOREIGN TABLE" | "F" => ObjectKind::ForeignTable,
            "SEQUENCE" | "S" => ObjectKind::Sequence,
            "SYSTEM TABLE" | "SYSTEM VIEW" => ObjectKind::System,
            _ => ObjectKind::Other,
        }
    }

    /// 这个种类的对象**能不能打开数据**（表 / 视图 / 物化视图能；序列不能）。
    /// 界面按它决定右键菜单里「浏览数据」给不给 —— **没目标就别给入口**。
    pub fn can_browse(self) -> bool {
        matches!(
            self,
            ObjectKind::Table | ObjectKind::View | ObjectKind::MaterializedView | ObjectKind::ForeignTable
        )
    }

    /// 树上的排序权重：同类扎堆，先表后视图，最后别的。
    pub fn order(self) -> u8 {
        match self {
            ObjectKind::Table => 0,
            ObjectKind::View => 1,
            ObjectKind::MaterializedView => 2,
            ObjectKind::ForeignTable => 3,
            ObjectKind::Sequence => 4,
            ObjectKind::System => 5,
            ObjectKind::Other => 6,
        }
    }
}

/// 树上的一个对象（一层之内的一员）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ObjectNode {
    pub schema: String,
    pub name: String,
    pub kind: ObjectKind,
}

impl ObjectNode {
    pub fn new(schema: impl Into<String>, name: impl Into<String>, kind: ObjectKind) -> Self {
        Self { schema: schema.into(), name: name.into(), kind }
    }

    /// 限定名（`schema.name`）。**原样拼**：不转义、不加引号 —— 这是给人看 / 复制的名字，
    /// 要下发到服务端的 SQL 由 `browse::qualified_name` 负责加引号（两者用途不同，别混）。
    pub fn qualified(&self) -> String {
        format!("{}.{}", self.schema, self.name)
    }

    /// 搜索用的小写键（`schema.name`）。
    fn search_key(&self) -> String {
        self.qualified().to_lowercase()
    }
}

/// 排序：先按种类权重、再按 schema、最后按名字（都按小写比，避免大小写造成的忽上忽下）。
pub fn sort_objects(items: &mut [ObjectNode]) {
    items.sort_by(|a, b| {
        a.kind
            .order()
            .cmp(&b.kind.order())
            .then_with(|| a.schema.to_lowercase().cmp(&b.schema.to_lowercase()))
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
}

/// 一条搜索命中：对象本身 + 它为什么命中（界面要显示依据，不能只说"匹配"）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchHit {
    pub object: ObjectNode,
    /// `qualified` = 命中限定名；`name` = 只命中对象名；`schema` = 只命中 schema 名
    pub matched_on: String,
}

/// 对象搜索：在**已加载的这一层**里按名字找。
///
/// 规则（只有一处实现）：
/// ① 大小写不敏感；
/// ② 查询里含点号 ⇒ 按**限定名**整串找（`app.ord` 命中 `app.orders`；`my.table` 也能命中
///    名字里带点号的对象，因为比较的是拼好的 `schema.name`）；
/// ③ 不含点号 ⇒ 对象名与 schema 名**都算命中**（搜 `app` 能找出 app 下所有对象）；
/// ④ 查询首尾空白不算内容；**空查询返回空**（见模块头 ④）；
/// ⑤ 命中按种类 / schema / 名字排序，同一次搜索的顺序稳定。
pub fn search(items: &[ObjectNode], query: &str) -> Vec<SearchHit> {
    let needle = query.trim().to_lowercase();
    if needle.is_empty() {
        return Vec::new();
    }
    let qualified_mode = needle.contains('.');
    let mut hits = Vec::new();
    for item in items {
        let name = item.name.to_lowercase();
        let schema = item.schema.to_lowercase();
        let matched_on = if qualified_mode {
            if item.search_key().contains(&needle) {
                "qualified"
            } else {
                continue;
            }
        } else if name.contains(&needle) {
            "name"
        } else if schema.contains(&needle) {
            "schema"
        } else {
            continue;
        };
        hits.push(SearchHit { object: item.clone(), matched_on: matched_on.to_string() });
    }
    hits.sort_by(|a, b| {
        a.object
            .kind
            .order()
            .cmp(&b.object.kind.order())
            .then_with(|| a.object.schema.to_lowercase().cmp(&b.object.schema.to_lowercase()))
            .then_with(|| a.object.name.to_lowercase().cmp(&b.object.name.to_lowercase()))
    });
    hits
}

/// 按 schema 把一层对象分组（树的一层里再分一层；顺序：schema 名升序）。
///
/// ⚠️ 实现坑（实测抓到）：`sort_objects` 是**按种类优先**排的，直接拿它排完再分组，
/// 同一个 schema 会被别的 schema 的同种类对象插开（`app 表 / public 表 / app 视图 …`）
/// ⇒ 分组结果里同一个 schema 出现好几段。**分组前必须先按 schema 聚拢**，组内再按种类排。
pub fn group_by_schema(items: &[ObjectNode]) -> Vec<(String, Vec<ObjectNode>)> {
    let mut sorted = items.to_vec();
    sorted.sort_by(|a, b| {
        a.schema
            .to_lowercase()
            .cmp(&b.schema.to_lowercase())
            .then_with(|| a.kind.order().cmp(&b.kind.order()))
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    let mut out: Vec<(String, Vec<ObjectNode>)> = Vec::new();
    for item in sorted {
        match out.last_mut() {
            Some((schema, list)) if *schema == item.schema => list.push(item),
            _ => out.push((item.schema.clone(), vec![item])),
        }
    }
    out
}

// ── 第三层：表 / 视图 → 列（FR-META-01 的最后一格、FR-META-05 的数据类型）──────────────
//
// 口径（与对侧行为同源，实现按本侧栈重写）：
// ① **列节点带数据类型**：类型是**服务端原文**（`character varying(50)` / `numeric(12,2)`），
//    不翻译、不缩写 ——「显示什么」是界面的事，模型只如实带；
// ② **一层一次取数**：要展开的那几张表**一次**交给取数实现（`expand_layer`），
//    不许「for 表 in 表们 { 问一次 }」—— 那是 N+1。判据按**取数调用计数**钉死（见本模块测试）；
// ③ **要了没给的表不丢**：`tables` 里点名要、服务端一行都没回的表，如实给一个**空列组** ——
//    「这张表没有列」与「我没问这张表」必须能分开（后者会让界面永远转圈）。

/// 系统 schema 的**字面名单**（FR-META-04）。
pub const SYSTEM_SCHEMA_EXACT: &[&str] = &["pg_catalog", "information_schema"];
/// 系统 schema 的**前缀名单**（`pg_toast*` / `pg_temp*`，`pg_toast_temp_*` 之类也归这里）。
pub const SYSTEM_SCHEMA_PREFIXES: &[&str] = &["pg_toast", "pg_temp"];

/// 这个 schema 是不是系统目录。**过滤规则只此一处** —— 查询层（SQL 的 WHERE）与界面层
/// （展开前先把系统 schema 摘掉）都走它，免得两处各写一份、慢慢漂成两种口径。
///
/// 大小写不敏感：服务端把标识符折成小写，但界面 / 测试里手写的 `PG_Catalog` 也得认出来，
/// 否则「按名字精确匹配」的写法会漏掉它（见本模块负例）。
pub fn is_system_schema(name: &str) -> bool {
    let lower = name.trim().to_lowercase();
    SYSTEM_SCHEMA_EXACT.contains(&lower.as_str())
        || SYSTEM_SCHEMA_PREFIXES.iter().any(|p| lower.starts_with(p))
}

/// 把系统 schema 摘掉（**保持输入顺序**，不改别的、不排序 —— 排序是各调用方自己的事）。
pub fn filter_system_schemas(names: &[String]) -> Vec<String> {
    names
        .iter()
        .filter(|n| !is_system_schema(n))
        .cloned()
        .collect()
}

/// 树第三层的一员：列名 + 数据类型原文（FR-META-05）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ColumnNode {
    pub name: String,
    /// 数据类型**原文**（`character varying(50)` / `numeric(12,2)` / `timestamptz`）。
    pub data_type: String,
}

impl ColumnNode {
    pub fn new(name: impl Into<String>, data_type: impl Into<String>) -> Self {
        Self { name: name.into(), data_type: data_type.into() }
    }
}

/// 一个表 / 视图的列（第三层取数的返回形状；`schema` / `table` 是它的坐标）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TableColumns {
    pub schema: String,
    pub table: String,
    pub columns: Vec<ColumnNode>,
}

/// 服务端**一次查询**回来的一行：`(表名, 列名, 数据类型原文)`。
pub type ColumnRow = (String, String, String);

/// 把一次查询回来的行**组装**成每表一组。生产的取数（`postgres.rs` 的一条 SQL）与判据自测
/// 走的是**同一个**组装口 —— 这样「组装规则」只有一份，判据钉的就是盘上跑的那份。
pub fn assemble_columns(schema: &str, tables: &[String], rows: &[ColumnRow]) -> Vec<TableColumns> {
    let mut out: Vec<TableColumns> = tables
        .iter()
        .map(|t| TableColumns {
            schema: schema.to_string(),
            table: t.clone(),
            columns: Vec::new(),
        })
        .collect();
    for (table, name, data_type) in rows {
        match out.iter_mut().find(|g| &g.table == table) {
            Some(group) => group.columns.push(ColumnNode::new(name.clone(), data_type.clone())),
            // 没点名的表也**如实留下**（不静默丢 —— 丢了就会「问过却没显示」）
            None => out.push(TableColumns {
                schema: schema.to_string(),
                table: table.clone(),
                columns: vec![ColumnNode::new(name.clone(), data_type.clone())],
            }),
        }
    }
    out
}

/// 一层取数的**唯一入口**：把要展开的表一次交出去。
///
/// 生产实现是 `postgres.rs` 的一条 `... WHERE relname = ANY($2)`；判据自测实现是个**计数器**
/// —— 两者都从 `expand_layer` 走，于是「调用计数」这条断言钉的是真实取数形状。
pub trait ColumnFetch {
    type Error;
    /// **一次**取回这些表的列；不许在实现里再逐表发查询。
    fn fetch_columns(&mut self, schema: &str, tables: &[String])
        -> Result<Vec<TableColumns>, Self::Error>;
}

/// **一层一次**：空表清单一次都不问（不无谓往返）；否则恰调用取数一次。
///
/// 负例（判据自测）：逐表循环 `fetch.fetch_columns(schema, &[t])` 的写法会让调用计数
/// = 表的张数 ⇒ 本函数那句「计数 == 1」当场判红。
pub fn expand_layer<F: ColumnFetch + ?Sized>(
    fetch: &mut F,
    schema: &str,
    tables: &[String],
) -> Result<Vec<TableColumns>, F::Error> {
    if tables.is_empty() {
        return Ok(Vec::new());
    }
    fetch.fetch_columns(schema, tables)
}

/// 按**类型**分组（FR-META-15 的「按类型分组」那一档）。
///
/// 组序 = 种类权重（表 → 视图 → 物化视图 → 外部表 → 序列 → 系统 → 其他），
/// **组内保持入参顺序**（不重排：界面已经排过一遍，这里再排一次会让两种视图的顺序凭空不同）。
pub fn group_by_kind(items: &[ObjectNode]) -> Vec<(ObjectKind, Vec<ObjectNode>)> {
    let mut kinds: Vec<ObjectKind> = Vec::new();
    let mut buckets: Vec<Vec<ObjectNode>> = Vec::new();
    for item in items {
        match kinds.iter().position(|k| *k == item.kind) {
            Some(i) => buckets[i].push(item.clone()),
            None => {
                kinds.push(item.kind);
                buckets.push(vec![item.clone()]);
            }
        }
    }
    let mut pairs: Vec<(ObjectKind, Vec<ObjectNode>)> =
        kinds.into_iter().zip(buckets.into_iter()).collect();
    pairs.sort_by_key(|(kind, _)| kind.order());
    pairs
}

// ── 元数据查询的行数上限保护（FR-META-07：10,000 行）───────────────────────────────
//
// 口径（与对侧 `QueryOptions(maxRows: 10_000)` 同源，实现按本侧栈重写）：
// ① **上限是保护，不是"分页"**：元数据本来可以无限长（一个 schema 下几万张表是可能的），
//    把它整份收进内存是"还没展开就先顶爆内存"的来路 —— 收够上限就不再收；
// ② **截断要如实报**（`truncated`）：到顶时界面必须能说"只显示了前 N 条，可能不完整"。
//    静默少给会让用户以为"库里就这么多表" —— 那是最难查的一类缺陷；
// ③ **恰好装满不算截断**：正好 10,000 行是**完整**的一层；把它说成截断会让每一层
//    都挂一句"可能不完整"（提示一多就等于没有提示）。

/// 元数据查询的**行数上限**（FR-META-07）。
pub const METADATA_ROW_LIMIT: usize = 10_000;

/// 上限保护的结果：留下的行 + 有没有被截掉的行 + 生效的上限（界面要写"前 N 条"）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CappedRows<T> {
    pub rows: Vec<T>,
    /// 服务端还回得更多、被上限截掉了（**如实报**，不静默少给）
    pub truncated: bool,
    /// 本次生效的上限（截断提示里要写它）
    pub limit: usize,
}

impl<T> CappedRows<T> {
    /// 由**流式取数**构造：`rows` 已按上限收好，`more` = "服务端还有一行没读"。
    ///
    /// 与 [`cap_metadata_rows`] 的分工：流式那条路在**读的时候**就知道有没有更多
    /// （所以截断标记由调用方给）；这条纯函数那条路是在**整批已在手上**时截。
    /// 两条路的最终形状与语义完全一致，界面只认这一个形状。
    pub fn from_stream(rows: Vec<T>, limit: usize, more: bool) -> Self {
        Self { rows, truncated: more, limit }
    }
}

/// 按上限收行（**纯函数、唯一入口** —— 生产取数的落点与判据自测都走它）。
///
/// 语义：`rows.len() <= limit` 时原样返回且 `truncated = false`（**恰好装满也算完整**）；
/// 超出时留下**前 `limit` 行**（顺序就是树的顺序，不是后 N 行）并置 `truncated = true`。
///
/// 负例（本模块测试）：`rows.truncate(0)` 那种"丢光"、以及"原样整份返回"的写法都会让
/// 「行数不许超过上限」或「截了要有标记」这两句当场判红。
pub fn cap_metadata_rows<T>(rows: Vec<T>, limit: usize) -> CappedRows<T> {
    let mut rows = rows;
    let truncated = rows.len() > limit;
    if truncated {
        rows.truncate(limit);
    }
    CappedRows { rows, truncated, limit }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Vec<ObjectNode> {
        vec![
            ObjectNode::new("app", "orders", ObjectKind::Table),
            ObjectNode::new("app", "accounts", ObjectKind::Table),
            ObjectNode::new("app", "v_totals", ObjectKind::View),
            ObjectNode::new("public", "orders_archive", ObjectKind::Table),
            ObjectNode::new("app", "my.table", ObjectKind::Table),
            ObjectNode::new("public", "seq_ids", ObjectKind::Sequence),
        ]
    }

    #[test]
    fn server_words_map_to_our_kinds_both_vocabularies() {
        assert_eq!(ObjectKind::from_server("BASE TABLE"), ObjectKind::Table);
        assert_eq!(ObjectKind::from_server("VIEW"), ObjectKind::View);
        assert_eq!(ObjectKind::from_server("MATERIALIZED VIEW"), ObjectKind::MaterializedView);
        assert_eq!(ObjectKind::from_server("FOREIGN TABLE"), ObjectKind::ForeignTable);
        assert_eq!(ObjectKind::from_server("SEQUENCE"), ObjectKind::Sequence);
        // pg_class 的单字母词表
        assert_eq!(ObjectKind::from_server("r"), ObjectKind::Table);
        assert_eq!(ObjectKind::from_server("m"), ObjectKind::MaterializedView);
        assert_eq!(ObjectKind::from_server("S"), ObjectKind::Sequence);
        // 认不出来不猜
        assert_eq!(ObjectKind::from_server("composite type"), ObjectKind::Other);
    }

    #[test]
    fn sequences_cannot_be_browsed_tables_and_views_can() {
        assert!(ObjectKind::Table.can_browse());
        assert!(ObjectKind::View.can_browse());
        assert!(ObjectKind::MaterializedView.can_browse());
        assert!(!ObjectKind::Sequence.can_browse());
        assert!(!ObjectKind::Other.can_browse());
    }

    #[test]
    fn qualified_name_is_verbatim_not_quoted() {
        // 给人看 / 复制的名字：原样，不加引号（加引号是下发 SQL 那一路的事）
        assert_eq!(ObjectNode::new("app", "orders", ObjectKind::Table).qualified(), "app.orders");
        assert_eq!(ObjectNode::new("my schema", "o", ObjectKind::Table).qualified(), "my schema.o");
    }

    #[test]
    fn empty_query_returns_nothing_not_everything() {
        // 空查询 = 空结果：界面此时显示树的原貌，不是把整库摊成平表
        assert!(search(&sample(), "").is_empty());
        assert!(search(&sample(), "   ").is_empty());
    }

    #[test]
    fn search_is_case_insensitive_on_both_name_and_schema() {
        let hits = search(&sample(), "ORD");
        assert_eq!(hits.len(), 2, "app.orders 与 public.orders_archive 都该命中：{hits:?}");
        assert!(hits.iter().all(|h| h.matched_on == "name"));

        let by_schema = search(&sample(), "APP");
        assert_eq!(by_schema.len(), 4, "app 下 4 个对象：{by_schema:?}");
        assert!(by_schema.iter().all(|h| h.matched_on == "schema"));
    }

    #[test]
    fn a_dotted_query_matches_the_qualified_name() {
        let hits = search(&sample(), "app.ord");
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].object.name, "orders");
        assert_eq!(hits[0].matched_on, "qualified");
    }

    #[test]
    fn a_dotted_query_can_find_an_object_whose_name_contains_a_dot() {
        // 名字里本来就有点号：限定名整串比较照样命中（不先切开再拼）
        let hits = search(&sample(), "my.table");
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].object.name, "my.table");
        assert_eq!(hits[0].matched_on, "qualified");
    }

    #[test]
    fn dotted_query_does_not_fall_back_to_bare_name_match() {
        // 带点号 = 只按限定名找：`app.nope` 不该因为"名字里有 nope"而命中任何东西
        assert!(search(&sample(), "app.nope").is_empty());
        // 反过来：`zzz.orders` 也不该命中 app.orders（限定名整串不匹配）
        assert!(search(&sample(), "zzz.orders").is_empty());
    }

    #[test]
    fn results_are_ordered_by_kind_then_schema_then_name() {
        let hits = search(&sample(), "o");
        let names: Vec<String> = hits.iter().map(|h| h.object.qualified()).collect();
        // 名字或 schema 里带 `o` 的：accounts / orders / orders_archive / v_totals。
        // `public.seq_ids` **不在内**（既没有 schema 命中也没有名字命中）—— 期望按事实写。
        // 表在前、视图其次；同种类内 app 在 public 前。
        assert_eq!(
            names,
            vec!["app.accounts", "app.orders", "public.orders_archive", "app.v_totals"]
        );
    }

    #[test]
    fn a_hit_must_match_name_or_schema_not_merely_exist() {
        // 反例守栏：一个既不含查询词、schema 也不含的对象，不许因为"排序靠前"混进结果
        assert!(search(&sample(), "o").iter().all(|h| h.object.name != "seq_ids"));
    }

    #[test]
    fn search_order_is_stable_for_equal_keys() {
        let a = search(&sample(), "orders");
        let b = search(&sample(), "orders");
        assert_eq!(a, b);
    }

    #[test]
    fn grouping_keeps_schemas_sorted_and_objects_inside_grouped_by_kind() {
        let groups = group_by_schema(&sample());
        let schemas: Vec<&str> = groups.iter().map(|(s, _)| s.as_str()).collect();
        assert_eq!(schemas, vec!["app", "public"]);
        let app: Vec<&str> = groups[0].1.iter().map(|o| o.name.as_str()).collect();
        // 表（accounts / my.table / orders 按名字）→ 视图
        assert_eq!(app, vec!["accounts", "my.table", "orders", "v_totals"]);
        let public: Vec<&str> = groups[1].1.iter().map(|o| o.name.as_str()).collect();
        assert_eq!(public, vec!["orders_archive", "seq_ids"]);
    }

    #[test]
    fn grouping_an_empty_layer_gives_no_groups() {
        assert!(group_by_schema(&[]).is_empty());
    }

    // ── 第三层：系统 schema 过滤（FR-META-04）─────────────────────────────────────────

    fn schema_list() -> Vec<String> {
        vec![
            "app".to_string(),
            "pg_catalog".to_string(),
            "information_schema".to_string(),
            "pg_toast".to_string(),
            "pg_toast_temp_3".to_string(),
            "pg_temp_1".to_string(),
            "public".to_string(),
        ]
    }

    #[test]
    fn system_schema_families_are_recognised_by_name_and_prefix() {
        assert!(is_system_schema("pg_catalog"));
        assert!(is_system_schema("information_schema"));
        assert!(is_system_schema("pg_toast"));
        assert!(is_system_schema("pg_toast_temp_3"));
        assert!(is_system_schema("pg_temp_1"));
        // 用户 schema 一个都不许中
        assert!(!is_system_schema("app"));
        assert!(!is_system_schema("public"));
        assert!(!is_system_schema("my_pg_like")); // 前缀里有 pg_ 但不是系统族
    }

    #[test]
    fn filtering_keeps_user_schemas_in_input_order() {
        let kept = filter_system_schemas(&schema_list());
        assert_eq!(kept, vec!["app".to_string(), "public".to_string()]);
        assert!(kept.iter().all(|s| !is_system_schema(s)));
    }

    #[test]
    fn negative_a_no_filter_list_is_caught() {
        // 负例：证明「过滤」这条断言真的抓得到东西 —— 「不过滤」的结果里系统 schema 还在，
        // 于是「不许出现系统 schema」这句判红（判据写的不是空话）。
        let unfiltered = schema_list(); // 故意原样返回 = 漏了过滤
        assert!(
            unfiltered.iter().any(|s| is_system_schema(s)),
            "不过滤的写法必须被「不许出现系统 schema」抓到"
        );
    }

    #[test]
    fn negative_case_insensitive_spelling_must_not_leak() {
        // 负例：按**精确小写**匹配的朴素写法会漏掉大小写混写的那几个 —— 这些也必须被摘掉。
        let mixed = vec![
            "PG_Catalog".to_string(),
            "pg_ToAst_all".to_string(),
            "Public".to_string(),
        ];
        assert!(is_system_schema("PG_Catalog"));
        assert!(is_system_schema("pg_ToAst_all"));
        let kept = filter_system_schemas(&mixed);
        assert_eq!(kept, vec!["Public".to_string()], "系统族要摘干净，用户 schema 原样保留：{kept:?}");
        // 而朴素的精确匹配写法会把这几个漏过去 —— 说明这条断言不是白写的
        let naive = |n: &String| !SYSTEM_SCHEMA_EXACT.contains(&n.as_str());
        assert!(
            mixed.iter().any(naive),
            "精确匹配的朴素写法确实会漏（所以判据必须判它红）"
        );
    }

    // ── 第三层：列节点与组装（FR-META-01 / -05）──────────────────────────────────────

    fn table_names() -> Vec<String> {
        vec!["customers".to_string(), "orders".to_string(), "no_pk_table".to_string()]
    }

    fn column_rows() -> Vec<ColumnRow> {
        vec![
            ("customers".to_string(), "id".to_string(), "integer".to_string()),
            (
                "customers".to_string(),
                "name".to_string(),
                "character varying(50)".to_string(),
            ),
            (
                "orders".to_string(),
                "total".to_string(),
                "numeric(12,2)".to_string(),
            ),
        ]
    }

    #[test]
    fn columns_are_grouped_per_table_in_the_requested_order_with_types() {
        let groups = assemble_columns("public", &table_names(), &column_rows());
        let names: Vec<&str> = groups.iter().map(|g| g.table.as_str()).collect();
        assert_eq!(names, vec!["customers", "orders", "no_pk_table"]);
        assert_eq!(groups[0].columns.len(), 2);
        let cols: Vec<&str> = groups[0].columns.iter().map(|c| c.name.as_str()).collect();
        assert_eq!(cols, vec!["id", "name"]);
        // FR-META-05：类型**原文**照带（不缩写、不翻译）
        assert_eq!(groups[0].columns[1].data_type, "character varying(50)");
        assert_eq!(groups[1].columns[0].data_type, "numeric(12,2)");
        assert_eq!(groups[0].schema, "public");
    }

    #[test]
    fn negative_a_requested_table_with_no_rows_must_not_be_dropped() {
        // 负例：只把 rows 里出现过的表吐出来的写法会**丢掉** `no_pk_table`
        // （界面于是永远等不到它 ⇒ 那一行永远转圈）。我们要求它是**空列组**。
        let groups = assemble_columns("public", &table_names(), &column_rows());
        let asked = groups.iter().find(|g| g.table == "no_pk_table");
        assert!(
            asked.is_some(),
            "点名要过的表必须回一个空列组，不是不回"
        );
        assert!(asked.unwrap().columns.is_empty());
        // 朴素的「只吐 rows 里有的表」写法会少一张 —— 判据抓的就是它
        let rows = column_rows();
        let naive_count = {
            let mut seen: Vec<&str> = Vec::new();
            for (t, _, _) in &rows {
                if !seen.iter().any(|s| s == t) {
                    seen.push(t);
                }
            }
            seen.len()
        };
        assert!(
            naive_count < table_names().len(),
            "朴素写法只吐 {naive_count} 张，按需的表有 {} 张 ⇒ 必须判红",
            table_names().len()
        );
    }

    #[test]
    fn negative_a_table_not_asked_for_is_kept_rather_than_silently_dropped() {
        // 负例：服务端回了没点名的表 —— 不许静默吞掉（吞掉就是「查到了却没显示」）。
        let rows = vec![("surprise".to_string(), "x".to_string(), "text".to_string())];
        let groups = assemble_columns("public", &table_names(), &rows);
        assert_eq!(groups.len(), 4);
        assert_eq!(groups[3].table, "surprise");
    }

    // ── 一层一次取数（不许 N+1）────────────────────────────────────────────────────

    /// 计数替身：只数「被问了几次」，不真连库。
    struct CountingFetch {
        calls: usize,
    }

    #[derive(Debug, PartialEq, Eq)]
    struct NeverError;

    impl ColumnFetch for CountingFetch {
        type Error = NeverError;
        fn fetch_columns(
            &mut self,
            schema: &str,
            tables: &[String],
        ) -> Result<Vec<TableColumns>, NeverError> {
            self.calls += 1;
            // 生产实现是一条 SQL；这里就按 SQL 的形状组装
            let rows: Vec<ColumnRow> = tables
                .iter()
                .map(|t| (t.clone(), "id".to_string(), "integer".to_string()))
                .collect();
            Ok(assemble_columns(schema, tables, &rows))
        }
    }

    #[test]
    fn expanding_a_layer_asks_the_server_exactly_once() {
        let mut fetch = CountingFetch { calls: 0 };
        let out = expand_layer(&mut fetch, "public", &table_names()).expect("自测取数不会失败");
        assert_eq!(fetch.calls, 1, "一层里的三张表只能问一次（N+1 = 判红）");
        assert_eq!(out.len(), 3);
        let mut none = CountingFetch { calls: 0 };
        assert!(expand_layer(&mut none, "public", &[]).unwrap().is_empty());
        assert_eq!(none.calls, 0, "没表要展开就一次都不该问");
    }

    #[test]
    fn negative_one_query_per_table_is_caught_by_the_count() {
        // 负例：N+1 写法（逐表各问一次）—— 计数 != 1，于是上面那句断言当场判红。
        let mut fetch = CountingFetch { calls: 0 };
        for table in table_names() {
            fetch.fetch_columns("public", &[table]).expect("自测取数不会失败");
        }
        assert_ne!(
            fetch.calls, 1,
            "逐表循环的写法会让计数 = 表数（{}），判据必须判它红",
            table_names().len()
        );
        assert_eq!(fetch.calls, table_names().len());
    }

    // ── 按类型分组（FR-META-15）───────────────────────────────────────────────────

    #[test]
    fn grouping_by_kind_orders_groups_by_kind_weight_and_keeps_inner_order() {
        let groups = group_by_kind(&sample());
        let kinds: Vec<ObjectKind> = groups.iter().map(|(k, _)| *k).collect();
        assert_eq!(
            kinds,
            vec![ObjectKind::Table, ObjectKind::View, ObjectKind::Sequence],
            "组序 = 表 → 视图 → 序列"
        );
        let tables: Vec<&str> = groups[0].1.iter().map(|o| o.name.as_str()).collect();
        // 组内保持入参顺序（app.orders, app.accounts, public.orders_archive, app.my.table）
        assert_eq!(tables, vec!["orders", "accounts", "orders_archive", "my.table"]);
        // 一个对象都不许丢、也不许重复
        let total: usize = groups.iter().map(|(_, v)| v.len()).sum();
        assert_eq!(total, sample().len());
    }

    #[test]
    fn negative_can_browse_boolean_must_not_be_used_as_the_grouping_key() {
        // 负例：拿 `can_browse()` 当分组键会把 表 / 视图 / 物化视图 / 外部表 挤进同一桶
        // （「按类型分组」直接失真）。判据要求它们各自成组。
        let groups = group_by_kind(&sample());
        let table_group = groups.iter().find(|(k, _)| *k == ObjectKind::Table).unwrap();
        assert!(
            table_group.1.iter().all(|o| o.kind == ObjectKind::Table),
            "表这一组里不许混进别的种类"
        );
        let naive_buckets = {
            let items = sample();
            let mut browsable: Vec<&ObjectNode> = Vec::new();
            let mut rest: Vec<&ObjectNode> = Vec::new();
            for o in &items {
                if o.kind.can_browse() {
                    browsable.push(o)
                } else {
                    rest.push(o)
                }
            }
            (browsable.len(), rest.len())
        };
        assert_eq!(
            naive_buckets,
            (5, 1),
            "按 can_browse 分只有两桶（5 / 1）⇒ 与「按类型」不是一回事"
        );
        assert!(groups.len() > 2, "按类型分组要出 3 组以上");
    }

    // ── 元数据查询行数上限（FR-META-07：10,000 行）─────────────────────────────────

    #[test]
    fn metadata_rows_over_the_limit_are_cut_and_truncation_is_reported() {
        let rows: Vec<usize> = (0..METADATA_ROW_LIMIT + 3).collect();
        let capped = cap_metadata_rows(rows, METADATA_ROW_LIMIT);
        assert_eq!(capped.rows.len(), METADATA_ROW_LIMIT, "留下的不许超过上限");
        assert!(capped.truncated, "截了就必须如实报");
        assert_eq!(capped.limit, METADATA_ROW_LIMIT);
        // 留下的是**前** limit 行（顺序就是树的顺序）——不是后 limit 行
        assert_eq!(capped.rows.first(), Some(&0));
        assert_eq!(capped.rows.last(), Some(&(METADATA_ROW_LIMIT - 1)));
    }

    #[test]
    fn exactly_at_the_limit_is_a_complete_layer_not_a_truncation() {
        let rows: Vec<usize> = (0..METADATA_ROW_LIMIT).collect();
        let capped = cap_metadata_rows(rows, METADATA_ROW_LIMIT);
        assert_eq!(capped.rows.len(), METADATA_ROW_LIMIT);
        assert!(!capped.truncated, "正好装满 = 完整的一层，不许说成截断");
    }

    #[test]
    fn under_the_limit_passes_through_untouched_and_empty_stays_empty() {
        let small = cap_metadata_rows(vec![1, 2, 3], METADATA_ROW_LIMIT);
        assert_eq!(small.rows, vec![1, 2, 3]);
        assert!(!small.truncated);
        let empty = cap_metadata_rows(Vec::<usize>::new(), METADATA_ROW_LIMIT);
        assert!(empty.rows.is_empty() && !empty.truncated);
    }

    #[test]
    fn negative_a_pass_through_without_capping_is_caught() {
        // 负例：不加保护的写法把整份返回 ⇒ 「行数不许超过上限」这句当场判红。
        let rows: Vec<usize> = (0..METADATA_ROW_LIMIT + 1).collect();
        let naive = rows.clone(); // 原样返回 = 没有上限保护
        assert!(naive.len() > METADATA_ROW_LIMIT, "无保护的写法确实会超上限");
        let capped = cap_metadata_rows(rows, METADATA_ROW_LIMIT);
        assert!(capped.rows.len() <= METADATA_ROW_LIMIT);
    }

    #[test]
    fn negative_silent_truncation_without_the_flag_is_caught() {
        // 负例：截了却不说（`truncate` 完直接返回一个 Vec）—— 界面于是把"前 10000 张表"
        // 当成"这个 schema 下就这么多表"。留下的行一样，但必须多出「截断了」这个事实。
        let rows: Vec<usize> = (0..METADATA_ROW_LIMIT + 5).collect();
        let mut silent = rows.clone();
        silent.truncate(METADATA_ROW_LIMIT);
        let capped = cap_metadata_rows(rows, METADATA_ROW_LIMIT);
        assert_eq!(capped.rows, silent, "留下的行与朴素截断一致");
        assert!(capped.truncated, "但「截断了」这个事实必须能被界面读到");
    }

    #[test]
    fn streaming_construction_carries_the_same_shape_as_the_pure_cap() {
        // 两条入口（流式 / 整批）产出同一个形状：界面只认一个。
        let streamed = CappedRows::from_stream(vec![1, 2, 3], METADATA_ROW_LIMIT, true);
        assert_eq!(streamed.rows, vec![1, 2, 3]);
        assert!(streamed.truncated);
        assert_eq!(streamed.limit, METADATA_ROW_LIMIT);
        let pure = cap_metadata_rows(vec![1, 2, 3], 3);
        assert_eq!(pure.rows, streamed.rows);
        assert_eq!(pure.limit, 3);
    }
}
