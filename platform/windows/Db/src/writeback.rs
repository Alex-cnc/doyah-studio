//! 写回与事务的**纯逻辑**（1.4 段）：编辑集 → DML、危险语句判定、只读拦截、事务语句表。
//!
//! 四条口径（写清楚，写回是"能改坏数据"的功能，含糊不得）：
//! ① **没有主键就不给改**：定位不到"是哪一行"，UPDATE 就会误伤同名行 —— 这不是"体验问题"，
//!    是**数据正确性**问题；宁可不给入口，也不生成一条 `WHERE` 靠猜的语句。
//! ② **只读连接一律拒写**（FR-CONN-17）—— 这是**本机保护**，不替代数据库权限：它拦的是
//!    "我在这台机器上点错了"。拦截发生在**生成阶段**，连语句都不产生。
//! ③ **危险语句要能单独认出来**（`risk`）：无 WHERE 的 UPDATE / DELETE、`DROP` / `TRUNCATE`、
//!    以及**多段事务里的写语句**都要在执行前要一次确认；判定是纯函数，界面只负责弹框。
//! ④ **事务语句表只此一处**：`BEGIN` / `COMMIT` / `ROLLBACK` 的字面量与顺序都在这里，
//!    驱动层只按序下发（免得"某处漏了 COMMIT，连接一直挂在事务里"这种难查的毛病）。

use serde::{Deserialize, Serialize};

use crate::db_type::DatabaseType;

/// 标识符加引号（表 / 列 / schema 名）。内部引号翻倍。
pub fn quote_ident(name: &str) -> String {
    format!("\"{}\"", name.replace('"', "\"\""))
}

/// 限定名（schema + 表）加引号；schema 为空就只给表名。
pub fn qualified(schema: Option<&str>, table: &str) -> String {
    match schema.map(str::trim).filter(|s| !s.is_empty()) {
        Some(schema) => format!("{}.{}", quote_ident(schema), quote_ident(table)),
        None => quote_ident(table),
    }
}

/// 一行的**主键定位信息**（来自结果集 + 元数据）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RowKey {
    /// 主键列名（复合主键按顺序给全）
    pub columns: Vec<String>,
    /// 对应的值（与 `columns` 一一对应；`None` = NULL）
    pub values: Vec<Option<String>>,
}

/// 处编辑：某一行的某一列被改成什么。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CellEdit {
    pub schema: Option<String>,
    pub table: String,
    /// 这一行怎么定位（**必须有**，见口径 ①）
    pub key: RowKey,
    pub column: String,
    /// 新值（`None` = 置 NULL）
    pub value: Option<String>,
    /// 新值是不是数值（决定生成时加不加引号；界面从原列类型推断）
    #[serde(default)]
    pub value_is_numeric: bool,
}

/// 生成的 DML 与它的风险判定。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DmlStatement {
    pub sql: String,
    /// 这条语句影响哪一行（给人看的定位摘要）
    pub target: String,
    pub risk: Risk,
}

/// 风险档：`safe` 可直接执行；`confirm` 要过一次确认；`forbidden` 直接拒（只读连接）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Risk {
    Safe,
    Confirm,
    Forbidden,
}

/// 生成失败的原因（**可读**，且说清该怎么办）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DmlError {
    pub message: String,
    pub hint: String,
}

/// 值 → SQL 字面量。数值形态不加引号，其余按字符串转义（`'` 翻倍）。
pub fn literal(value: &Option<String>, is_numeric: bool) -> String {
    match value {
        None => "NULL".to_string(),
        Some(text) => {
            if is_numeric && text.trim().parse::<f64>().is_ok() {
                text.trim().to_string()
            } else {
                format!("'{}'", text.replace('\'', "''"))
            }
        }
    }
}

/// 主键条件（`"a" = 1 AND "b" = 'x'`）。**一个主键列都不能少** —— 少了就可能命中多行。
fn key_condition(key: &RowKey) -> Result<String, DmlError> {
    if key.columns.is_empty() {
        return Err(DmlError {
            message: "这张表没有主键：定位不到「是哪一行」，不给改".to_string(),
            hint: "无主键的表请用 SQL 直接写（那样你自己负责 WHERE 条件）；客户端不替你猜条件。"
                .to_string(),
        });
    }
    if key.columns.len() != key.values.len() {
        return Err(DmlError {
            message: "主键定位信息不完整（列与值个数不一致）".to_string(),
            hint: "重跑一次查询再编辑；这是本侧的内部不一致，值得报一下。".to_string(),
        });
    }
    let mut parts = Vec::with_capacity(key.columns.len());
    for (column, value) in key.columns.iter().zip(key.values.iter()) {
        // 主键里的 NULL 不能写 `= NULL`（SQL 里那是"未知"，永远不成立）⇒ 用 IS NULL
        parts.push(match value {
            None => format!("{} IS NULL", quote_ident(column)),
            // 主键列的值按文本给：能解析成数就不加引号（避免 `"id" = '1'` 这种跨类型比较）
            Some(_) => format!("{} = {}", quote_ident(column), literal(value, is_numberish(value))),
        });
    }
    Ok(parts.join(" AND "))
}

/// 这个值能不能当数值写（能解析成数才算）。
fn is_numberish(value: &Option<String>) -> bool {
    matches!(value, Some(text) if text.trim().parse::<f64>().is_ok())
}

/// 定位摘要（给人看："主键 id=3"）。
fn target_text(key: &RowKey) -> String {
    key.columns
        .iter()
        .zip(key.values.iter())
        .map(|(c, v)| format!("{c}={}", v.clone().unwrap_or_else(|| "NULL".into())))
        .collect::<Vec<_>>()
        .join(", ")
}

/// 把一批格子编辑变成 DML（**一批 = 多条 UPDATE，一次事务**）。
///
/// 口径：① 每条都带**完整主键条件**；② `is_read_only` 为真 ⇒ 全部 `Risk::Forbidden`
/// （连语句都不给执行，但**仍然生成** —— 让用户看见"本来会执行什么"，比一句"只读"更有用）。
pub fn edits_to_dml(edits: &[CellEdit], is_read_only: bool) -> Result<Vec<DmlStatement>, DmlError> {
    let mut out = Vec::with_capacity(edits.len());
    for edit in edits {
        let condition = key_condition(&edit.key)?;
        let sql = format!(
            "UPDATE {} SET {} = {} WHERE {};",
            qualified(edit.schema.as_deref(), &edit.table),
            quote_ident(&edit.column),
            literal(&edit.value, edit.value_is_numeric),
            condition
        );
        out.push(DmlStatement {
            sql,
            target: format!("{}（{}）", edit.table, target_text(&edit.key)),
            risk: if is_read_only { Risk::Forbidden } else { Risk::Safe },
        });
    }
    Ok(out)
}

/// 单条 SQL 的**危险判定**（在执行前用）。
///
/// 判定档（只认能确凿认出来的，不猜）：
/// - 只读连接 ⇒ `Forbidden`（一律）；
/// - `DROP` / `TRUNCATE` / 无 `WHERE` 的 `UPDATE` / 无 `WHERE` 的 `DELETE` ⇒ `Confirm`；
/// - 其余 ⇒ `Safe`。
///
/// 为什么不用"包含 DELETE 就危险"这种粗口径：那会把 `DELETE ... WHERE id = 1` 也拦下来，
/// 拦多了用户就会习惯性点确认 —— 确认框一旦变成橡皮图章，它就等于不存在。
pub fn statement_risk(sql: &str, is_read_only: bool) -> Risk {
    if is_read_only {
        return Risk::Forbidden;
    }
    let text = strip_comments(sql).to_lowercase();
    let trimmed = text.trim();
    if trimmed.starts_with("drop") || trimmed.starts_with("truncate") {
        return Risk::Confirm;
    }
    let destructive = trimmed.starts_with("update") || trimmed.starts_with("delete");
    if destructive && !trimmed.contains(" where ") {
        return Risk::Confirm;
    }
    Risk::Safe
}

/// 去掉注释（判定前用：`-- delete from t` 这种注释不该被判成危险语句）。
fn strip_comments(sql: &str) -> String {
    let mut out = String::with_capacity(sql.len());
    let bytes = sql.as_bytes();
    let mut i = 0usize;
    let mut in_single = false;
    while i < bytes.len() {
        let c = bytes[i] as char;
        if in_single {
            out.push(c);
            if c == '\'' {
                if i + 1 < bytes.len() && bytes[i + 1] == b'\'' {
                    out.push('\'');
                    i += 2;
                    continue;
                }
                in_single = false;
            }
            i += 1;
            continue;
        }
        if c == '\'' {
            in_single = true;
            out.push(c);
            i += 1;
            continue;
        }
        if c == '-' && i + 1 < bytes.len() && bytes[i + 1] == b'-' {
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
            out.push(' ');
            continue;
        }
        if c == '/' && i + 1 < bytes.len() && bytes[i + 1] == b'*' {
            i += 2;
            while i < bytes.len() {
                if bytes[i] == b'*' && i + 1 < bytes.len() && bytes[i + 1] == b'/' {
                    i += 2;
                    break;
                }
                i += 1;
            }
            out.push(' ');
            continue;
        }
        out.push(c);
        i += 1;
    }
    out
}

/// 一次写回要下发的事务语句表（**顺序与字面量只此一处**）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TransactionPlan {
    /// 是否显式开事务（`false` = 每条各自自动提交）
    pub in_transaction: bool,
    pub begin: Option<String>,
    pub commit: Option<String>,
    pub rollback: Option<String>,
}

impl TransactionPlan {
    /// 显式事务档（写回默认走这个：一批一次事务）。
    pub fn explicit() -> Self {
        Self {
            in_transaction: true,
            begin: Some("BEGIN".to_string()),
            commit: Some("COMMIT".to_string()),
            rollback: Some("ROLLBACK".to_string()),
        }
    }

    /// 自动提交档（每条各自提交；只读或"本来就没有批"时用）。
    pub fn auto_commit() -> Self {
        Self { in_transaction: false, begin: None, commit: None, rollback: None }
    }

    /// 把语句表按顺序拼成要下发的一串（开事务 → 语句 → 提交/回滚）。
    pub fn script(&self, statements: &[String], rollback: bool) -> Vec<String> {
        let mut out = Vec::new();
        if let Some(begin) = &self.begin {
            out.push(begin.clone());
        }
        out.extend(statements.iter().cloned());
        if rollback {
            if let Some(rb) = &self.rollback {
                out.push(rb.clone());
            }
        } else if let Some(commit) = &self.commit {
            out.push(commit.clone());
        }
        out
    }
}

/// 这个数据库类型支不支持事务里的写回。
///
/// 现状（按 `db_type::DatabaseType` 的**实际变体**写，不写想象出来的名字）：`Postgresql` /
/// `Mysql` / `Gbase8a` 三档都支持事务，于是本函数对当前所有变体都返回真。
/// **保留这个函数**是为了让"写回要开事务"这件事有一个可判定的入口：将来若加入不支持事务的
/// 目标（或某档只读），判定改在这里一处，而不是散在调用点。
pub fn supports_transaction(db_type: DatabaseType) -> bool {
    match db_type {
        DatabaseType::Postgresql | DatabaseType::Mysql | DatabaseType::Gbase8a => true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key(cols: &[&str], vals: &[Option<&str>]) -> RowKey {
        RowKey {
            columns: cols.iter().map(|c| c.to_string()).collect(),
            values: vals.iter().map(|v| v.map(|s| s.to_string())).collect(),
        }
    }

    fn edit(column: &str, value: Option<&str>, numeric: bool, k: RowKey) -> CellEdit {
        CellEdit {
            schema: Some("app".into()),
            table: "accounts".into(),
            key: k,
            column: column.into(),
            value: value.map(|s| s.to_string()),
            value_is_numeric: numeric,
        }
    }

    #[test]
    fn identifiers_and_qualified_names_are_quoted_with_escapes() {
        assert_eq!(quote_ident("name"), "\"name\"");
        assert_eq!(quote_ident("we\"ird"), "\"we\"\"ird\"");
        assert_eq!(qualified(Some("app"), "orders"), "\"app\".\"orders\"");
        assert_eq!(qualified(None, "orders"), "\"orders\"");
        assert_eq!(qualified(Some("   "), "orders"), "\"orders\"");
    }

    #[test]
    fn literals_numeric_unquoted_and_strings_escaped() {
        assert_eq!(literal(&None, false), "NULL");
        assert_eq!(literal(&Some("42".into()), true), "42");
        assert_eq!(literal(&Some("42".into()), false), "'42'");
        assert_eq!(literal(&Some("it's".into()), false), "'it''s'");
        // 标了数值但解析不出数 ⇒ 当字符串处理（不生成一条注定语法错的语句）
        assert_eq!(literal(&Some("4x".into()), true), "'4x'");
    }

    #[test]
    fn a_cell_edit_becomes_one_update_with_the_full_key_condition() {
        let dml = edits_to_dml(&[edit("balance", Some("9.5"), true, key(&["id"], &[Some("3")]))], false)
            .unwrap();
        assert_eq!(dml.len(), 1);
        assert_eq!(
            dml[0].sql,
            "UPDATE \"app\".\"accounts\" SET \"balance\" = 9.5 WHERE \"id\" = 3;"
        );
        assert_eq!(dml[0].risk, Risk::Safe);
        assert!(dml[0].target.contains("id=3"), "{}", dml[0].target);
    }

    #[test]
    fn a_composite_key_produces_an_and_condition() {
        let dml = edits_to_dml(
            &[edit("note", Some("x"), false, key(&["a", "b"], &[Some("1"), Some("k")]))],
            false,
        )
        .unwrap();
        assert_eq!(
            dml[0].sql,
            "UPDATE \"app\".\"accounts\" SET \"note\" = 'x' WHERE \"a\" = 1 AND \"b\" = 'k';"
        );
    }

    #[test]
    fn a_null_key_part_uses_is_null_not_equals() {
        // `= NULL` 在 SQL 里永远不成立 ⇒ 必须写 IS NULL，否则这条更新一行都改不到
        let dml = edits_to_dml(&[edit("note", Some("x"), false, key(&["id"], &[None]))], false).unwrap();
        assert!(dml[0].sql.contains("\"id\" IS NULL"), "{}", dml[0].sql);
    }

    #[test]
    fn editing_a_nullable_column_to_null_writes_the_null_keyword() {
        let dml = edits_to_dml(&[edit("note", None, false, key(&["id"], &[Some("7")]))], false).unwrap();
        assert!(dml[0].sql.contains("SET \"note\" = NULL"));
    }

    #[test]
    fn a_table_without_a_primary_key_is_refused_not_guessed() {
        let err = edits_to_dml(&[edit("note", Some("x"), false, key(&[], &[]))], false).unwrap_err();
        assert!(err.message.contains("主键"), "{}", err.message);
        assert!(err.hint.contains("SQL"), "{}", err.hint);
    }

    #[test]
    fn mismatched_key_columns_and_values_is_refused() {
        let err = edits_to_dml(&[edit("note", Some("x"), false, key(&["a", "b"], &[Some("1")]))], false)
            .unwrap_err();
        assert!(err.message.contains("不完整"), "{}", err.message);
    }

    #[test]
    fn a_read_only_connection_still_shows_what_would_have_run_but_forbids_it() {
        let dml = edits_to_dml(&[edit("balance", Some("1"), true, key(&["id"], &[Some("1")]))], true)
            .unwrap();
        // 语句照样生成（让用户看见"本来会执行什么"），但风险档是禁行
        assert!(dml[0].sql.starts_with("UPDATE"));
        assert_eq!(dml[0].risk, Risk::Forbidden);
    }

    #[test]
    fn risk_only_confirms_what_it_can_prove_is_destructive() {
        // 有 WHERE 的 UPDATE/DELETE 不拦（拦多了确认框就成橡皮图章）
        assert_eq!(statement_risk("update t set a = 1 where id = 2", false), Risk::Safe);
        assert_eq!(statement_risk("delete from t where id = 2", false), Risk::Safe);
        assert_eq!(statement_risk("select * from t", false), Risk::Safe);
        // 无 WHERE 的写语句要确认
        assert_eq!(statement_risk("update t set a = 1", false), Risk::Confirm);
        assert_eq!(statement_risk("delete from t", false), Risk::Confirm);
        assert_eq!(statement_risk("  DELETE   FROM t  ", false), Risk::Confirm);
        // DDL 破坏性语句要确认
        assert_eq!(statement_risk("drop table t", false), Risk::Confirm);
        assert_eq!(statement_risk("truncate t", false), Risk::Confirm);
        // 只读连接一律禁行
        assert_eq!(statement_risk("select 1", true), Risk::Forbidden);
    }

    #[test]
    fn risk_ignores_comments_and_literals() {
        // 注释里的 delete 不该让一条 SELECT 变成危险语句
        assert_eq!(statement_risk("select 1 -- delete from t", false), Risk::Safe);
        assert_eq!(statement_risk("/* drop table t */ select 1", false), Risk::Safe);
        // 字符串里的 where 不算真 WHERE：`delete ... 'where'` 仍应判危险
        assert_eq!(statement_risk("delete from t where note = 'x'", false), Risk::Safe);
        assert_eq!(statement_risk("delete from t -- where\n", false), Risk::Confirm);
    }

    #[test]
    fn transaction_plan_is_the_single_source_of_the_statement_order() {
        let plan = TransactionPlan::explicit();
        let script = plan.script(&["UPDATE a SET x = 1;".into(), "UPDATE b SET y = 2;".into()], false);
        assert_eq!(
            script,
            vec!["BEGIN", "UPDATE a SET x = 1;", "UPDATE b SET y = 2;", "COMMIT"]
        );
        let rolled = plan.script(&["UPDATE a SET x = 1;".into()], true);
        assert_eq!(rolled, vec!["BEGIN", "UPDATE a SET x = 1;", "ROLLBACK"]);
        let auto = TransactionPlan::auto_commit();
        assert_eq!(auto.script(&["delete from t where id = 1;".into()], false), vec!["delete from t where id = 1;"]);
    }

    #[test]
    fn transactions_are_supported_for_every_shipped_type() {
        // 按枚举的**实际变体**逐个写（漏一个变体时这个用例会编译不过 —— 那正是要的效果）
        assert!(supports_transaction(DatabaseType::Postgresql));
        assert!(supports_transaction(DatabaseType::Mysql));
        assert!(supports_transaction(DatabaseType::Gbase8a));
    }
}
