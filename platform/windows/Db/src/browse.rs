//! 服务端条件浏览（FR-DATA-02；契约等价物：macOS 侧 `Core/RowBrowsing.swift`）
//!
//! 与「客户端筛选」（`App/src/grid/view.ts` 那一层）的区别必须一句话讲清：
//! **这里的条件是在服务端执行的** —— 用户填 `WHERE` / `ORDER BY`，我们把它拼进 `SELECT` 发给数据库。
//!
//! 因此三条纪律（照抄对侧，一条都不许松）：
//! ① **片段原样下发**（这是使用者在自己的库上写 SQL，本层不做"聪明"的改写）；
//! ② **拒绝多语句**：`WHERE a = 1; DROP TABLE t` 这种输入不能因为点了个"浏览"就被执行 ——
//!    一个 `;` 就足以说明对方放错了地方，**拒绝并说清**比"尽力执行"安全得多；
//! ③ **两种错误要分开**：多语句 / ORDER BY 冲突（`WHERE` 框里既写了又另填）—— 各报各的。
//!
//! 生成顺序固定 = **WHERE → ORDER BY → 分页**：分页必须在最后，否则 `LIMIT` 之后的条件会被语法拒绝。

/// 浏览条件。`where_clause` / `order_by` 是**用户写的 SQL 片段**（可带也可不带关键字）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BrowseFilter {
    pub where_clause: String,
    pub order_by: String,
    pub limit: i64,
    pub offset: i64,
}

impl Default for BrowseFilter {
    fn default() -> Self {
        Self {
            where_clause: String::new(),
            order_by: String::new(),
            // 默认页大小：与对侧 `ObjectTreeActions.defaultBrowseLimit` 同量级（200 行够看一屏多）
            limit: 200,
            offset: 0,
        }
    }
}

/// 生成失败的原因（文案由界面层映射；本层不硬编码语言）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowseError {
    /// 片段里有多条语句（含分号）—— 拒绝执行，要求把条件写成单条表达式。
    MultipleStatements,
    /// `WHERE` 框里既写了 `ORDER BY`、又在 `ORDER BY` 框里写了一份：无法判断以哪个为准。
    AmbiguousOrderBy,
}

impl BrowseError {
    /// 给界面用的技术标识（本地化在界面层）。
    pub const fn identifier(self) -> &'static str {
        match self {
            BrowseError::MultipleStatements => "multipleStatements",
            BrowseError::AmbiguousOrderBy => "ambiguousOrderBy",
        }
    }

    /// 给用户看的一句话（含"该怎么做"）。
    pub const fn message(self) -> &'static str {
        match self {
            BrowseError::MultipleStatements => {
                "条件里出现了分号（像是不止一条语句）—— 这里只接受**单条表达式**，请把分号后面的内容去掉"
            }
            BrowseError::AmbiguousOrderBy => {
                "排序写了两处（条件框里一处、排序框里一处）—— 请只保留一处，否则无法判断以哪个为准"
            }
        }
    }
}

/// 把表名（与可选 schema）拼成**带引号**的限定名：`"app"."accounts"`。
///
/// 一律加双引号并转义内部双引号：这样大小写敏感的表名、带空格 / 关键字的表名都不会被拆坏。
pub fn qualified_name(table: &str, schema: Option<&str>) -> String {
    let quote = |part: &str| format!("\"{}\"", part.replace('"', "\"\""));
    match schema.filter(|s| !s.trim().is_empty()) {
        Some(schema) => format!("{}.{}", quote(schema), quote(table)),
        None => quote(table),
    }
}

/// PostgreSQL 的取数子句（本侧当前只支持 PostgreSQL；GBase 的 `LIMIT offset, count` 等
/// 等真接上那一端时再按方言出参 —— **不提前造一个用不上的方言参数**）。
pub fn limit_clause(offset: i64, count: i64) -> String {
    format!("LIMIT {} OFFSET {}", count.max(0), offset.max(0))
}

/// 生成浏览语句：`SELECT * FROM <表> [WHERE …] [ORDER BY …] LIMIT … OFFSET …;`
pub fn browse(table: &str, schema: Option<&str>, filter: &BrowseFilter) -> Result<String, BrowseError> {
    let (where_sql, order_sql) = split(&filter.where_clause, &filter.order_by)?;
    let mut sql = String::from("SELECT * FROM ");
    sql.push_str(&qualified_name(table, schema));
    if !where_sql.is_empty() {
        sql.push_str(" WHERE ");
        sql.push_str(&where_sql);
    }
    if !order_sql.is_empty() {
        sql.push_str(" ORDER BY ");
        sql.push_str(&order_sql);
    }
    sql.push(' ');
    sql.push_str(&limit_clause(filter.offset, filter.limit));
    sql.push(';');
    Ok(sql)
}

/// 生成计数语句：`SELECT count(*) FROM <表> [WHERE …];`
///
/// 计数**不带 ORDER BY**：它对结果没有影响，带上只会让数据库白排序一遍。
pub fn count(table: &str, schema: Option<&str>, filter: &BrowseFilter) -> Result<String, BrowseError> {
    let (where_sql, _) = split(&filter.where_clause, &filter.order_by)?;
    let mut sql = String::from("SELECT count(*) FROM ");
    sql.push_str(&qualified_name(table, schema));
    if !where_sql.is_empty() {
        sql.push_str(" WHERE ");
        sql.push_str(&where_sql);
    }
    sql.push(';');
    Ok(sql)
}

/// 条件片段的规范化与拆分（**同一份输入只解析一次**：预览与生成共用本函数）。
pub fn split(where_clause: &str, order_by: &str) -> Result<(String, String), BrowseError> {
    let raw_where = sanitize(where_clause).ok_or(BrowseError::MultipleStatements)?;
    let raw_order = sanitize(order_by).ok_or(BrowseError::MultipleStatements)?;

    let mut where_sql = raw_where;
    let mut order_sql = raw_order;

    // 用户在 WHERE 框里顺手写了 ORDER BY：条件框只有一个，就**拆开**（且只在他没另填时这么做）
    if let Some((start, end)) = find_top_level_order_by(&where_sql) {
        if !order_sql.is_empty() {
            return Err(BrowseError::AmbiguousOrderBy);
        }
        order_sql = where_sql[end..].trim().to_string();
        where_sql = where_sql[..start].trim().to_string();
    }

    Ok((
        strip_leading_keyword(&where_sql, "where").to_string(),
        strip_leading_keyword(&order_sql, "order by").to_string(),
    ))
}

/// 去掉首尾空白与**一个**结尾分号；若还剩分号（= 多条语句）返回 `None`。
fn sanitize(raw: &str) -> Option<String> {
    let mut text = raw.trim().to_string();
    if let Some(stripped) = text.strip_suffix(';') {
        text = stripped.trim().to_string();
    }
    if text.contains(';') {
        return None;
    }
    Some(text)
}

/// 去掉用户可能一起粘进来的关键字（`WHERE a = 1` 与 `a = 1` 都接受）。
///
/// 必须是**独立的**关键字（`wherever` 不能被当成 `where`）。
fn strip_leading_keyword<'a>(text: &'a str, keyword: &str) -> &'a str {
    let lowered = text.to_lowercase();
    if !lowered.starts_with(keyword) {
        return text;
    }
    let rest = &text[keyword.len()..];
    let standalone = rest.is_empty()
        || rest
            .chars()
            .next()
            .map(|c| c.is_whitespace() || c == '(')
            .unwrap_or(true);
    if !standalone {
        return text;
    }
    rest.trim()
}

/// 找**顶层**的 `ORDER BY`（跳过单引号字符串、双引号标识符与括号内部），返回字符下标区间。
///
/// 只做够用的一件事：这个条件框里出现 `ORDER BY`，几乎都是"顺手把整段条件粘进来"了。
fn find_top_level_order_by(text: &str) -> Option<(usize, usize)> {
    let chars: Vec<char> = text.chars().collect();
    let mut i = 0usize;
    let mut depth = 0i32;

    while i < chars.len() {
        let c = chars[i];
        // 引号内的内容整段跳过（连同**连写两个引号**的转义）
        if c == '\'' || c == '"' {
            let quote = c;
            i += 1;
            while i < chars.len() {
                if chars[i] == quote {
                    if i + 1 < chars.len() && chars[i + 1] == quote {
                        i += 2;
                        continue;
                    }
                    i += 1;
                    break;
                }
                i += 1;
            }
            continue;
        }
        if c == '(' {
            depth += 1;
            i += 1;
            continue;
        }
        if c == ')' {
            depth = (depth - 1).max(0);
            i += 1;
            continue;
        }
        if depth == 0 && c.is_whitespace() {
            let start = i;
            let mut cursor = i;
            while cursor < chars.len() && chars[cursor].is_whitespace() {
                cursor += 1;
            }
            let tail: String = chars[cursor..].iter().collect::<String>().to_lowercase();
            if tail.starts_with("order by") {
                let after = cursor + "order by".chars().count();
                // 关键字后面必须是空白或行尾，避免匹配到 `order byx`（列名）
                if after >= chars.len() || chars[after].is_whitespace() {
                    return Some((start, after));
                }
            }
        }
        i += 1;
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn filter(where_clause: &str, order_by: &str) -> BrowseFilter {
        BrowseFilter {
            where_clause: where_clause.to_string(),
            order_by: order_by.to_string(),
            ..Default::default()
        }
    }

    #[test]
    fn builds_where_order_paging_in_that_order() {
        let sql = browse("accounts", Some("app"), &filter("balance > 100", "id DESC")).unwrap();
        assert_eq!(
            sql,
            "SELECT * FROM \"app\".\"accounts\" WHERE balance > 100 ORDER BY id DESC LIMIT 200 OFFSET 0;"
        );
    }

    #[test]
    fn keywords_are_optional_and_standalone_only() {
        // 带关键字与不带关键字等价
        let a = browse("t", None, &filter("WHERE a = 1", "ORDER BY a")).unwrap();
        let b = browse("t", None, &filter("a = 1", "a")).unwrap();
        assert_eq!(a, b);
        // `wherever` 不能被当成 `where`
        let c = browse("t", None, &filter("wherever = 1", "")).unwrap();
        assert!(c.contains("WHERE wherever = 1"), "{c}");
    }

    #[test]
    fn multiple_statements_are_refused_not_executed() {
        let err = browse("t", None, &filter("a = 1; DROP TABLE t", "")).unwrap_err();
        assert_eq!(err, BrowseError::MultipleStatements);
        assert_eq!(err.identifier(), "multipleStatements");
        assert!(err.message().contains("单条表达式"));
        // 结尾一个分号是允许的（顺手多打的分号不算多语句）
        let ok = browse("t", None, &filter("a = 1;", "")).unwrap();
        assert_eq!(ok, "SELECT * FROM \"t\" WHERE a = 1 LIMIT 200 OFFSET 0;");
        // ORDER BY 框里同样不许出现分号
        assert_eq!(
            browse("t", None, &filter("", "a; DELETE FROM t")).unwrap_err(),
            BrowseError::MultipleStatements
        );
    }

    #[test]
    fn order_by_pasted_into_the_where_box_is_split_out() {
        let (w, o) = split("a = 1 ORDER BY b DESC", "").unwrap();
        assert_eq!(w, "a = 1");
        assert_eq!(o, "b DESC");
    }

    #[test]
    fn two_order_by_sources_are_ambiguous_and_say_so() {
        let err = split("a = 1 ORDER BY b", "c").unwrap_err();
        assert_eq!(err, BrowseError::AmbiguousOrderBy);
        assert_eq!(err.identifier(), "ambiguousOrderBy");
        assert!(err.message().contains("两处"));
    }

    #[test]
    fn order_by_inside_literals_or_parens_is_not_top_level() {
        // 单引号字符串里的 order by 不算
        let (w, o) = split("note = 'order by x'", "").unwrap();
        assert_eq!(w, "note = 'order by x'");
        assert!(o.is_empty());
        // 括号里的 order by 不算（子查询）
        let (w, o) = split("id IN (SELECT id FROM t ORDER BY id)", "").unwrap();
        assert!(o.is_empty(), "{o}");
        assert!(w.contains("ORDER BY id"));
        // 双引号标识符里同理
        let (w, o) = split("\"order by\" = 1", "").unwrap();
        assert!(o.is_empty());
        assert_eq!(w, "\"order by\" = 1");
    }

    #[test]
    fn order_byx_is_not_the_keyword() {
        let (w, o) = split("order byx = 1", "").unwrap();
        assert_eq!(w, "order byx = 1");
        assert!(o.is_empty());
    }

    #[test]
    fn count_has_no_order_by_and_paging() {
        let sql = count("accounts", Some("app"), &filter("balance > 100", "id DESC")).unwrap();
        assert_eq!(sql, "SELECT count(*) FROM \"app\".\"accounts\" WHERE balance > 100;");
        // 计数也不该因为"没了排序"就丢掉 where
        let sql = count("t", None, &filter("", "")).unwrap();
        assert_eq!(sql, "SELECT count(*) FROM \"t\";");
    }

    #[test]
    fn names_are_quoted_and_escaped() {
        assert_eq!(qualified_name("my table", None), "\"my table\"");
        assert_eq!(qualified_name("we\"ird", Some("s")), "\"s\".\"we\"\"ird\"");
        // 空 schema 视同没给
        assert_eq!(qualified_name("t", Some("   ")), "\"t\"");
    }

    #[test]
    fn paging_is_clamped_and_never_negative() {
        let f = BrowseFilter {
            where_clause: String::new(),
            order_by: String::new(),
            limit: -5,
            offset: -9,
        };
        assert!(browse("t", None, &f).unwrap().ends_with("LIMIT 0 OFFSET 0;"));
        let f = BrowseFilter { limit: 50, offset: 100, ..Default::default() };
        assert!(browse("t", None, &f).unwrap().ends_with("LIMIT 50 OFFSET 100;"));
    }

    #[test]
    fn default_filter_is_a_sane_first_page() {
        let f = BrowseFilter::default();
        assert_eq!(f.limit, 200);
        assert_eq!(f.offset, 0);
        assert!(f.where_clause.is_empty() && f.order_by.is_empty());
    }
}
