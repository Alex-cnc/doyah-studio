//! 外键引用导航（FR-DATA-06；契约等价物：macOS 侧 `Core/ForeignKeyNavigation.swift`）
//!
//! 需求点名的验收是「**存在外键元数据时才呈现入口；无可跳转目标时不显示**」——
//! 所以这一层的核心不是"能不能拼 SQL"，而是**"有没有目标"这个判定要准**：
//! 给一个点了没反应的入口，比不给更糟。
//!
//! 两个方向都要有（缺一个就会让人困惑"为什么这边能跳、那边不能"）：
//! - **正向**：本表某列引用别人 → 跳到被引用表，按被引用列取值；
//! - **反向**：别人引用我 → 跳到引用方，按外键列取值（"这张订单被哪些明细引用"）。

use crate::browse::qualified_name;

/// 跳转方向。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Direction {
    Forward,
    Reverse,
}

impl Direction {
    /// 菜单项里的动作词（文案在界面层也能取用；这里给一份默认中文，与对侧 `displayName` 同口径）。
    pub const fn display_name(self) -> &'static str {
        match self {
            Direction::Forward => "跳到被引用表",
            Direction::Reverse => "跳到引用本表的行",
        }
    }
}

/// 一条外键边（从约束定义解析而来）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Edge {
    pub constraint_name: Option<String>,
    pub from_table: String,
    pub from_schema: Option<String>,
    pub columns: Vec<String>,
    pub to_table: String,
    pub to_schema: Option<String>,
    pub referenced_columns: Vec<String>,
}

/// 一个可跳转的目标。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Option_ {
    pub direction: Direction,
    pub local_column: String,
    pub target_table: String,
    pub target_schema: Option<String>,
    pub target_column: String,
    pub constraint_name: Option<String>,
}

impl Option_ {
    /// 菜单项文案：`跳到被引用表：public.orders（id）`。
    pub fn title(&self) -> String {
        let target = match &self.target_schema {
            Some(schema) => format!("{schema}.{}", self.target_table),
            None => self.target_table.clone(),
        };
        format!(
            "{}：{}（{}）",
            self.direction.display_name(),
            target,
            self.target_column
        )
    }
}

/// 从约束行解析外键。`kind` 以 `f` 开头的才是外键（PG 的 `contype`）。
///
/// 解析失败**返回 `None` 而不是猜**：把一条 CHECK 当外键会生成"跳到不存在的列"的语句。
pub fn parse_edge(
    constraint_name: Option<&str>,
    kind: &str,
    definition: &str,
    table: &str,
    schema: Option<&str>,
    default_schema: Option<&str>,
) -> Option<Edge> {
    if !kind.to_lowercase().starts_with('f') {
        return None;
    }
    let text = definition.replace('\n', " ");
    let upper = text.to_uppercase();
    let foreign_at = upper.find("FOREIGN KEY")?;
    let references_at = upper.find("REFERENCES")?;
    if foreign_at >= references_at {
        return None;
    }
    // 取原串里的同样位置（大写化不改变字节长度：都是 ASCII 关键字）
    let local_part = &text[foreign_at + "FOREIGN KEY".len()..references_at];
    let target_part = &text[references_at + "REFERENCES".len()..];

    let local_columns = parenthesized(local_part)?;
    if local_columns.is_empty() {
        return None;
    }
    let (target_schema, target_table, target_columns) = parse_target(target_part)?;
    if target_columns.len() != local_columns.len() {
        return None;
    }
    Some(Edge {
        constraint_name: constraint_name.map(str::to_string),
        from_table: table.to_string(),
        from_schema: schema.map(str::to_string),
        columns: local_columns,
        to_table: target_table,
        to_schema: target_schema.or_else(|| default_schema.map(str::to_string)),
        referenced_columns: target_columns,
    })
}

/// `(a, b)` → `["a", "b"]`（去引号、去空白；没有括号返回 `None`）。
pub fn parenthesized(text: &str) -> Option<Vec<String>> {
    let open = text.find('(')?;
    let close = text.rfind(')')?;
    if open >= close {
        return None;
    }
    let inner = &text[open + 1..close];
    let items: Vec<String> = inner
        .split(',')
        .map(|part| part.trim().trim_matches('"').to_string())
        .filter(|s| !s.is_empty())
        .collect();
    Some(items)
}

/// `public.orders(id)` / `orders (id)` / `"My Schema"."T"(id)` → 目标表与列。
pub fn parse_target(text: &str) -> Option<(Option<String>, String, Vec<String>)> {
    let open = text.find('(')?;
    let name_part = &text[..open];
    let columns = parenthesized(&text[open..])?;
    if columns.is_empty() {
        return None;
    }
    let components: Vec<String> = name_part
        .split('.')
        .map(|part| part.trim().trim_matches('"').to_string())
        .filter(|s| !s.is_empty())
        .collect();
    let table = components.last()?.clone();
    let schema = if components.len() >= 2 {
        Some(components[components.len() - 2].clone())
    } else {
        None
    };
    Some((schema, table, columns))
}

/// 某表某列的所有可跳转目标（正向 + 反向）。**顺序确定**：正向在前，各自按标题排序。
pub fn options(table: &str, column: &str, edges: &[Edge], schema: Option<&str>) -> Vec<Option_> {
    let matches = |a: &str, b: &str| a.eq_ignore_ascii_case(b);
    let schema_ok = |edge_schema: Option<&str>| match (schema, edge_schema) {
        (None, _) | (_, None) => true,
        (Some(want), Some(have)) => matches(want, have),
    };

    let mut forward: Vec<Option_> = Vec::new();
    let mut reverse: Vec<Option_> = Vec::new();

    for edge in edges {
        if matches(&edge.from_table, table) && schema_ok(edge.from_schema.as_deref()) {
            for (position, local_column) in edge.columns.iter().enumerate() {
                if matches(local_column, column) && position < edge.referenced_columns.len() {
                    forward.push(Option_ {
                        direction: Direction::Forward,
                        local_column: local_column.clone(),
                        target_table: edge.to_table.clone(),
                        target_schema: edge.to_schema.clone(),
                        target_column: edge.referenced_columns[position].clone(),
                        constraint_name: edge.constraint_name.clone(),
                    });
                }
            }
        }
        if matches(&edge.to_table, table) && schema_ok(edge.to_schema.as_deref()) {
            for (position, referenced) in edge.referenced_columns.iter().enumerate() {
                if matches(referenced, column) && position < edge.columns.len() {
                    reverse.push(Option_ {
                        direction: Direction::Reverse,
                        local_column: column.to_string(),
                        target_table: edge.from_table.clone(),
                        target_schema: edge.from_schema.clone(),
                        target_column: edge.columns[position].clone(),
                        constraint_name: edge.constraint_name.clone(),
                    });
                }
            }
        }
    }

    forward.sort_by(|a, b| a.title().cmp(&b.title()));
    reverse.sort_by(|a, b| a.title().cmp(&b.title()));
    forward.extend(reverse);
    forward
}

/// 需求原文的验收点：**没有可跳转目标时不给入口**。
pub fn has_option(table: &str, column: &str, edges: &[Edge], schema: Option<&str>) -> bool {
    !options(table, column, edges, schema).is_empty()
}

/// 按列类型把值写成 SQL 字面量。
///
/// **所有值一律当字符串处理并转义**：这里没有"类型推断"，也没有字符串拼接的余地 ——
/// 单引号翻倍是 SQL 字面量的标准写法，比"我猜这是个数字所以直接拼"安全得多。
/// 数字类型**只在能解析成数**时才不加引号（那样可读性好一点，且解析失败就退回带引号）。
pub fn literal(value: &str, type_name: &str) -> String {
    let numeric = matches!(
        type_name.to_lowercase().as_str(),
        "int2" | "int4" | "int8" | "smallint" | "integer" | "bigint" | "numeric" | "float4" | "float8"
            | "real" | "double precision" | "decimal"
    );
    if numeric && value.trim().parse::<f64>().is_ok() {
        return value.trim().to_string();
    }
    format!("'{}'", value.replace('\'', "''"))
}

/// 生成跳转用的查询：带 `LIMIT`（跳过去看的是"这一行的引用对象"，不是整表导出）。
pub fn query(option: &Option_, value: &str, type_name: &str, limit: i64) -> String {
    let target = qualified_name(&option.target_table, option.target_schema.as_deref());
    let quoted_column = format!("\"{}\"", option.target_column.replace('"', "\"\""));
    format!(
        "SELECT * FROM {} WHERE {} = {} LIMIT {};",
        target,
        quoted_column,
        literal(value, type_name),
        limit.max(1)
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn orders_edge() -> Edge {
        Edge {
            constraint_name: Some("orders_account_id_fkey".to_string()),
            from_table: "orders".to_string(),
            from_schema: Some("app".to_string()),
            columns: vec!["account_id".to_string()],
            to_table: "accounts".to_string(),
            to_schema: Some("app".to_string()),
            referenced_columns: vec!["id".to_string()],
        }
    }

    #[test]
    fn parses_a_postgres_foreign_key_definition() {
        let definition = "FOREIGN KEY (account_id) REFERENCES app.accounts(id)";
        let edge = parse_edge(Some("fk1"), "f", definition, "orders", Some("app"), None).unwrap();
        assert_eq!(edge.columns, vec!["account_id"]);
        assert_eq!(edge.to_table, "accounts");
        assert_eq!(edge.to_schema.as_deref(), Some("app"));
        assert_eq!(edge.referenced_columns, vec!["id"]);
        assert_eq!(edge.constraint_name.as_deref(), Some("fk1"));
    }

    #[test]
    fn composite_keys_and_quoting_and_schema_fallback() {
        let definition = "FOREIGN KEY (a, b) REFERENCES \"My Schema\".\"T\"(\"x\", y)";
        let edge = parse_edge(None, "f", definition, "child", None, Some("public")).unwrap();
        assert_eq!(edge.columns, vec!["a", "b"]);
        assert_eq!(edge.to_schema.as_deref(), Some("My Schema"));
        assert_eq!(edge.to_table, "T");
        assert_eq!(edge.referenced_columns, vec!["x", "y"]);
        // 定义里没写 schema ⇒ 用默认 schema（不是留空）
        let no_schema = parse_edge(None, "f", "FOREIGN KEY (a) REFERENCES t(x)", "c", None, Some("public")).unwrap();
        assert_eq!(no_schema.to_schema.as_deref(), Some("public"));
        // 连默认都没有 ⇒ 确实没有
        let none = parse_edge(None, "f", "FOREIGN KEY (a) REFERENCES t(x)", "c", None, None).unwrap();
        assert!(none.to_schema.is_none());
    }

    #[test]
    fn non_foreign_key_definitions_are_refused_not_guessed() {
        // CHECK 约束被当成外键 ⇒ 会生成"跳到不存在的列"的语句
        assert!(parse_edge(None, "c", "CHECK ((a > 0))", "t", None, None).is_none());
        assert!(parse_edge(None, "p", "PRIMARY KEY (id)", "t", None, None).is_none());
        // kind 像 f 但定义里没有关键字
        assert!(parse_edge(None, "f", "SOMETHING ELSE", "t", None, None).is_none());
        // 关键字顺序反了（REFERENCES 在前）
        assert!(parse_edge(None, "f", "REFERENCES t(id) FOREIGN KEY (a)", "t", None, None).is_none());
        // 列数不匹配 ⇒ 拒绝（宁可不给入口）
        assert!(parse_edge(None, "f", "FOREIGN KEY (a, b) REFERENCES t(x)", "t", None, None).is_none());
        // 空括号
        assert!(parse_edge(None, "f", "FOREIGN KEY () REFERENCES t()", "t", None, None).is_none());
    }

    #[test]
    fn options_cover_forward_and_reverse_in_a_stable_order() {
        let edges = vec![orders_edge()];
        // 正向：orders.account_id → accounts.id
        let forward = options("orders", "account_id", &edges, Some("app"));
        assert_eq!(forward.len(), 1);
        assert_eq!(forward[0].direction, Direction::Forward);
        assert_eq!(forward[0].target_table, "accounts");
        assert_eq!(forward[0].target_column, "id");
        assert!(forward[0].title().contains("跳到被引用表"));
        assert!(forward[0].title().contains("app.accounts"));

        // 反向：accounts.id ← orders.account_id
        let reverse = options("accounts", "id", &edges, Some("app"));
        assert_eq!(reverse.len(), 1);
        assert_eq!(reverse[0].direction, Direction::Reverse);
        assert_eq!(reverse[0].target_table, "orders");
        assert_eq!(reverse[0].target_column, "account_id");
        assert!(reverse[0].title().contains("跳到引用本表的行"));

        // 不相关的列 / 表：**没有目标**（入口不该出现）
        assert!(options("orders", "sku", &edges, Some("app")).is_empty());
        assert!(options("other", "id", &edges, Some("app")).is_empty());
        assert!(!has_option("orders", "sku", &edges, Some("app")));
        assert!(has_option("orders", "account_id", &edges, Some("app")));
    }

    #[test]
    fn schema_filtering_keeps_same_named_tables_apart() {
        let mut other = orders_edge();
        other.from_schema = Some("other".to_string());
        let edges = vec![orders_edge(), other];
        // 只看 app 的那条
        let app = options("orders", "account_id", &edges, Some("app"));
        assert_eq!(app.len(), 1);
        // 不给 schema ⇒ 两条都算
        let any = options("orders", "account_id", &edges, None);
        assert_eq!(any.len(), 2);
        // 大小写不敏感
        let upper = options("ORDERS", "ACCOUNT_ID", &edges, Some("APP"));
        assert_eq!(upper.len(), 1);
    }

    #[test]
    fn generated_query_quotes_and_escapes_values() {
        let edges = vec![orders_edge()];
        let option = options("accounts", "id", &edges, Some("app")).remove(0);
        // 文本值：单引号翻倍（这是 SQL 字面量的标准写法）
        let q = query(&option, "O'Brien", "text", 200);
        assert_eq!(
            q,
            "SELECT * FROM \"app\".\"orders\" WHERE \"account_id\" = 'O''Brien' LIMIT 200;"
        );
        // 数字类型且真能解析成数 ⇒ 不带引号（可读性好一点）
        let n = query(&option, "42", "int4", 50);
        assert!(n.ends_with("= 42 LIMIT 50;"), "{n}");
        // 数字类型但值不是数 ⇒ 退回带引号（不猜）
        let odd = query(&option, "abc", "int4", 50);
        assert!(odd.contains("= 'abc'"), "{odd}");
        // LIMIT 夹到至少 1
        assert!(query(&option, "1", "text", 0).ends_with("LIMIT 1;"));
        // 列名里的双引号被转义
        let mut weird = option.clone();
        weird.target_column = "we\"ird".to_string();
        assert!(query(&weird, "1", "text", 10).contains("\"we\"\"ird\""));
    }

    #[test]
    fn parenthesized_and_target_parsing_edge_cases() {
        assert_eq!(parenthesized("(a, b)"), Some(vec!["a".to_string(), "b".to_string()]));
        assert_eq!(parenthesized("no parens"), None);
        assert_eq!(parenthesized(")("), None);
        let (schema, table, cols) = parse_target(" s . t ( id ) ").unwrap();
        assert_eq!(schema.as_deref(), Some("s"));
        assert_eq!(table, "t");
        assert_eq!(cols, vec!["id"]);
        // 没有 schema
        let (schema, table, _) = parse_target("t(id)").unwrap();
        assert!(schema.is_none() && table == "t");
        // 没有括号 ⇒ None
        assert!(parse_target("t").is_none());
    }
}
