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
}
