//! 表结构与 DDL 的**纯逻辑**（1.5 段）：列集差异 → `ALTER TABLE`、索引 / 约束语句、危险分级。
//!
//! 五条口径（DDL 是"改了不好回退"的操作，条条都要说清）：
//! ① **删除类只生成语句**：`DROP COLUMN` / `DROP TABLE` / `DROP INDEX` 一律标 `destructive`，
//!    调用方据它**只预览、不自动执行**（版本计划的原文要求）；加列 / 改列标 `additive`。
//! ② **改列一律走"改名式"重建**（PostgreSQL 的 `ALTER COLUMN TYPE` 在变更类型时会失败，
//!    且不是所有类型都能直接转换）⇒ 生成的是一串可读语句（`ADD` 新列 → `UPDATE` 搬值 →
//!    `DROP` 旧列 → `RENAME`），**让用户看见每一步**，而不是一句黑箱 `ALTER`。
//! ③ **每一句都带注释头**：生成物是给人读的，注释里写清"这一句干什么、为什么"。
//! ④ **不猜类型**：用户改了类型就按用户给的写，本层不做"看起来像什么"的推断。
//! ⑤ **空变更 = 空语句表**（不是生成一堆无意义的 `ALTER`）。

use serde::{Deserialize, Serialize};

use crate::writeback::quote_ident;

/// 一列的当前定义（从元数据读回来）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ColumnDef {
    pub name: String,
    /// 数据类型的**原文**（如 `character varying(50)` / `numeric(12,2)` / `timestamptz`）
    pub data_type: String,
    pub is_nullable: bool,
    /// 默认值表达式原文（`None` = 没有默认值）
    pub default_expr: Option<String>,
}

/// 用户对一列的改动意图。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ColumnChange {
    /// 现有列名（新加列为 `None`）
    pub from: Option<ColumnDef>,
    /// 改后的定义（删除列为 `None`）
    pub to: Option<ColumnDef>,
}

impl ColumnChange {
    /// 这是不是一次**删除列**。
    pub fn is_drop(&self) -> bool {
        self.from.is_some() && self.to.is_none()
    }

    /// 这是不是一次**新加列**。
    pub fn is_add(&self) -> bool {
        self.from.is_none() && self.to.is_some()
    }

    /// 这是不是一次**改名**（列身份不变、只有名字变）。
    pub fn is_rename(&self) -> bool {
        match (&self.from, &self.to) {
            (Some(from), Some(to)) => from.name != to.name && from.data_type == to.data_type
                && from.is_nullable == to.is_nullable && from.default_expr == to.default_expr,
            _ => false,
        }
    }

    /// 这是不是一次**实质性改动**（类型 / 可空 / 默认值任一变了）。
    pub fn is_alter(&self) -> bool {
        match (&self.from, &self.to) {
            (Some(from), Some(to)) => {
                from.data_type != to.data_type
                    || from.is_nullable != to.is_nullable
                    || from.default_expr != to.default_expr
            }
            _ => false,
        }
    }
}

/// 生成语句的**危险分级**。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StatementClass {
    /// 只加东西（加列 / 加索引 / 加约束）：可直接执行
    Additive,
    /// 改东西（改类型 / 改可空 / 改名）：要预览后确认
    Altering,
    /// **删东西**（删列 / 删索引 / 删约束 / 删表）：**只生成、不自动执行**
    Destructive,
    /// 会丢数据的搬运（改类型时新增临时列、搬值、删旧列）
    DataMoving,
}

/// 一句生成的 DDL。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DdlStatement {
    /// 带注释头的完整语句（给人读的生成物）
    pub sql: String,
    /// 裸语句（不含注释 —— 要真执行时用它；界面展示用上面的 `sql`）
    pub bare: String,
    pub class: StatementClass,
    /// 这句在干什么（界面按它分组显示）
    pub purpose: String,
}

/// 生成失败的**可读原因**。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DdlError {
    pub message: String,
    pub hint: String,
}

/// 拼一句带注释头的语句。
fn with_comment(comment: &str, bare: String, class: StatementClass, purpose: &str) -> DdlStatement {
    DdlStatement {
        sql: format!("-- {comment}\n{bare}"),
        bare,
        class,
        purpose: purpose.to_string(),
    }
}

/// 列的完整定义片段（`"name" type NOT NULL DEFAULT ...`）。
fn column_spec(column: &ColumnDef) -> String {
    let mut out = format!("{} {}", quote_ident(&column.name), column.data_type.trim());
    if !column.is_nullable {
        out.push_str(" NOT NULL");
    }
    if let Some(default) = column.default_expr.as_deref().map(str::trim).filter(|d| !d.is_empty()) {
        out.push_str(&format!(" DEFAULT {default}"));
    }
    out
}

/// 把所有列改动变成**有序**的 DDL 语句表。
///
/// 顺序为什么不许乱（照 PostgreSQL 的实际约束排）：
/// ① 先加列（后面的搬运才有目标）；
/// ② 再改类型 / 可空 / 默认值（用重建式，见口径 ②）；
/// ③ 再改名（改名放最后，避免前面的语句还在用旧名）；
/// ④ **删除列放最后**（前面可能还在读它）——并且标 `Destructive`。
pub fn alter_table(
    schema: Option<&str>,
    table: &str,
    changes: &[ColumnChange],
) -> Result<Vec<DdlStatement>, DdlError> {
    if table.trim().is_empty() {
        return Err(DdlError {
            message: "表名是空的：不知道要改哪张表".to_string(),
            hint: "先选中一张表再进表设计器。".to_string(),
        });
    }
    let target = crate::writeback::qualified(schema, table);
    let mut out = Vec::new();

    // ① 加列
    for change in changes.iter().filter(|c| c.is_add()) {
        let column = change.to.as_ref().expect("is_add 保证 to 存在");
        if column.name.trim().is_empty() {
            return Err(DdlError {
                message: "有一列没写名字".to_string(),
                hint: "新列必须有名字。".to_string(),
            });
        }
        let bare = format!("ALTER TABLE {target} ADD COLUMN {};", column_spec(column));
        out.push(with_comment(
            &format!("新增列 {}（只加东西，可直接执行）", column.name),
            bare,
            StatementClass::Additive,
            "新增列",
        ));
    }

    // ② 改类型 / 可空 / 默认值 —— 重建式四步
    for change in changes.iter().filter(|c| c.is_alter()) {
        let from = change.from.as_ref().expect("is_alter 保证 from 存在");
        let to = change.to.as_ref().expect("is_alter 保证 to 存在");
        // 类型变了才需要重建；只改可空 / 默认值时用普通 ALTER（不动数据）
        if from.data_type != to.data_type {
            let temp = format!("{}__new", to.name);
            out.push(with_comment(
                &format!(
                    "第 1/4 步：为 {} 建一个临时新列 {}（类型 {} → {}）—— 先不动旧列，值搬完再删",
                    to.name, temp, from.data_type, to.data_type
                ),
                format!(
                    "ALTER TABLE {target} ADD COLUMN {} {};",
                    quote_ident(&temp),
                    to.data_type.trim()
                ),
                StatementClass::DataMoving,
                "改类型（建临时列）",
            ));
            out.push(with_comment(
                &format!("第 2/4 步：把 {} 的值搬到 {} —— 类型不兼容时这一步会报错，先看它", to.name, temp),
                format!(
                    "UPDATE {target} SET {} = {}::{};",
                    quote_ident(&temp),
                    quote_ident(&to.name),
                    to.data_type.trim()
                ),
                StatementClass::DataMoving,
                "改类型（搬值）",
            ));
            out.push(with_comment(
                &format!("第 3/4 步：删掉旧列 {} —— **这一步丢数据**，确认第 2 步跑通了再执行", to.name),
                format!("ALTER TABLE {target} DROP COLUMN {};", quote_ident(&to.name)),
                StatementClass::Destructive,
                "改类型（删旧列）",
            ));
            out.push(with_comment(
                &format!("第 4/4 步：把临时列改名成 {}", to.name),
                format!(
                    "ALTER TABLE {target} RENAME COLUMN {} TO {};",
                    quote_ident(&temp),
                    quote_ident(&to.name)
                ),
                StatementClass::Altering,
                "改类型（改名收尾）",
            ));
            // 可空 / 默认值在新列上补齐
            if !to.is_nullable {
                out.push(with_comment(
                    &format!("补齐 {} 的 NOT NULL", to.name),
                    format!("ALTER TABLE {target} ALTER COLUMN {} SET NOT NULL;", quote_ident(&to.name)),
                    StatementClass::Altering,
                    "改可空",
                ));
            }
            if let Some(default) = to.default_expr.as_deref().map(str::trim).filter(|d| !d.is_empty()) {
                out.push(with_comment(
                    &format!("补齐 {} 的默认值", to.name),
                    format!(
                        "ALTER TABLE {target} ALTER COLUMN {} SET DEFAULT {default};",
                        quote_ident(&to.name)
                    ),
                    StatementClass::Altering,
                    "改默认值",
                ));
            }
            continue;
        }
        if from.is_nullable != to.is_nullable {
            let bare = if to.is_nullable {
                format!("ALTER TABLE {target} ALTER COLUMN {} DROP NOT NULL;", quote_ident(&to.name))
            } else {
                format!("ALTER TABLE {target} ALTER COLUMN {} SET NOT NULL;", quote_ident(&to.name))
            };
            out.push(with_comment(
                &format!("改 {} 的可空性（{} → {}）", to.name, if from.is_nullable { "可空" } else { "非空" }, if to.is_nullable { "可空" } else { "非空" }),
                bare,
                StatementClass::Altering,
                "改可空",
            ));
        }
        if from.default_expr != to.default_expr {
            let bare = match to.default_expr.as_deref().map(str::trim).filter(|d| !d.is_empty()) {
                Some(default) => format!(
                    "ALTER TABLE {target} ALTER COLUMN {} SET DEFAULT {default};",
                    quote_ident(&to.name)
                ),
                None => format!(
                    "ALTER TABLE {target} ALTER COLUMN {} DROP DEFAULT;",
                    quote_ident(&to.name)
                ),
            };
            out.push(with_comment(
                &format!("改 {} 的默认值", to.name),
                bare,
                StatementClass::Altering,
                "改默认值",
            ));
        }
    }

    // ③ 改名
    for change in changes.iter().filter(|c| c.is_rename()) {
        let from = change.from.as_ref().expect("is_rename 保证 from 存在");
        let to = change.to.as_ref().expect("is_rename 保证 to 存在");
        out.push(with_comment(
            &format!("把列 {} 改名为 {}（改名不动数据，但引用它的视图 / 代码要跟着改）", from.name, to.name),
            format!(
                "ALTER TABLE {target} RENAME COLUMN {} TO {};",
                quote_ident(&from.name),
                quote_ident(&to.name)
            ),
            StatementClass::Altering,
            "改列名",
        ));
    }

    // ④ 删除列（最后，且标破坏性）
    for change in changes.iter().filter(|c| c.is_drop()) {
        let from = change.from.as_ref().expect("is_drop 保证 from 存在");
        out.push(with_comment(
            &format!(
                "删除列 {} —— **丢数据且不可回退**：本侧只生成这一句，**不自动执行**",
                from.name
            ),
            format!("ALTER TABLE {target} DROP COLUMN {};", quote_ident(&from.name)),
            StatementClass::Destructive,
            "删除列",
        ));
    }

    Ok(out)
}

/// 生成**新建索引**语句。
pub fn create_index(
    schema: Option<&str>,
    table: &str,
    columns: &[String],
    unique: bool,
    index_name: Option<&str>,
) -> Result<DdlStatement, DdlError> {
    if columns.is_empty() {
        return Err(DdlError {
            message: "索引至少要有一列".to_string(),
            hint: "选一列或多列再生成索引语句。".to_string(),
        });
    }
    let target = crate::writeback::qualified(schema, table);
    let name = index_name
        .map(str::trim)
        .filter(|n| !n.is_empty())
        .map(|n| n.to_string())
        .unwrap_or_else(|| format!("{}_idx", columns.join("_")));
    let bare = format!(
        "CREATE {}INDEX {} ON {target} ({});",
        if unique { "UNIQUE " } else { "" },
        quote_ident(&name),
        columns.iter().map(|c| quote_ident(c)).collect::<Vec<_>>().join(", ")
    );
    Ok(with_comment(
        &format!("新建{}索引 {}（只加东西，可直接执行）", if unique { "唯一" } else { "" }, name),
        bare,
        StatementClass::Additive,
        "新建索引",
    ))
}

/// 生成**删索引**语句（破坏性：只生成、不自动执行）。
pub fn drop_index(schema: Option<&str>, index_name: &str) -> DdlStatement {
    let qualified = match schema.map(str::trim).filter(|s| !s.is_empty()) {
        Some(schema) => format!("{}.{}", quote_ident(schema), quote_ident(index_name)),
        None => quote_ident(index_name),
    };
    with_comment(
        &format!("删除索引 {index_name} —— 本侧只生成这一句，**不自动执行**"),
        format!("DROP INDEX {qualified};"),
        StatementClass::Destructive,
        "删除索引",
    )
}

/// 生成**加外键**语句。
pub fn add_foreign_key(
    schema: Option<&str>,
    table: &str,
    columns: &[String],
    ref_schema: Option<&str>,
    ref_table: &str,
    ref_columns: &[String],
    constraint_name: Option<&str>,
) -> Result<DdlStatement, DdlError> {
    if columns.is_empty() || columns.len() != ref_columns.len() {
        return Err(DdlError {
            message: format!(
                "外键两边的列数不一致（本表 {} 列，被引用表 {} 列）",
                columns.len(),
                ref_columns.len()
            ),
            hint: "外键要求逐列对应：改到两边列数一样再生成。".to_string(),
        });
    }
    let target = crate::writeback::qualified(schema, table);
    let referenced = crate::writeback::qualified(ref_schema, ref_table);
    let name = constraint_name
        .map(str::trim)
        .filter(|n| !n.is_empty())
        .map(|n| n.to_string())
        .unwrap_or_else(|| format!("{}_fkey", table));
    let bare = format!(
        "ALTER TABLE {target} ADD CONSTRAINT {} FOREIGN KEY ({}) REFERENCES {referenced} ({});",
        quote_ident(&name),
        columns.iter().map(|c| quote_ident(c)).collect::<Vec<_>>().join(", "),
        ref_columns.iter().map(|c| quote_ident(c)).collect::<Vec<_>>().join(", ")
    );
    Ok(with_comment(
        &format!("加外键 {name}（约束不满足时这条会失败 —— 先看报错再改数据）"),
        bare,
        StatementClass::Additive,
        "加外键",
    ))
}

/// 生成**删约束**语句（破坏性：只生成、不自动执行）。
pub fn drop_constraint(schema: Option<&str>, table: &str, constraint_name: &str) -> DdlStatement {
    let target = crate::writeback::qualified(schema, table);
    with_comment(
        &format!("删除约束 {constraint_name} —— 本侧只生成这一句，**不自动执行**"),
        format!("ALTER TABLE {target} DROP CONSTRAINT {};", quote_ident(constraint_name)),
        StatementClass::Destructive,
        "删除约束",
    )
}

/// 生成**删表**语句（破坏性：只生成、不自动执行）。
pub fn drop_table(schema: Option<&str>, table: &str) -> DdlStatement {
    let target = crate::writeback::qualified(schema, table);
    with_comment(
        &format!("删除表 {table} —— **丢全部数据且不可回退**：本侧只生成这一句，**不自动执行**"),
        format!("DROP TABLE {target};"),
        StatementClass::Destructive,
        "删除表",
    )
}

/// 生成语句表里有没有**破坏性**语句（界面据此禁用"直接执行"、只给"复制语句"）。
pub fn has_destructive(statements: &[DdlStatement]) -> bool {
    statements.iter().any(|s| s.class == StatementClass::Destructive)
}

/// 这批语句里**可以自动执行**的那些（其余要用户自己复制去跑）。
pub fn executable_subset(statements: &[DdlStatement]) -> Vec<&DdlStatement> {
    statements
        .iter()
        .filter(|s| matches!(s.class, StatementClass::Additive | StatementClass::Altering))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn col(name: &str, ty: &str, nullable: bool, default: Option<&str>) -> ColumnDef {
        ColumnDef {
            name: name.into(),
            data_type: ty.into(),
            is_nullable: nullable,
            default_expr: default.map(|d| d.into()),
        }
    }

    fn change(from: Option<ColumnDef>, to: Option<ColumnDef>) -> ColumnChange {
        ColumnChange { from, to }
    }

    #[test]
    fn adding_a_column_produces_one_additive_statement() {
        let out = alter_table(
            Some("app"),
            "accounts",
            &[change(None, Some(col("note", "text", true, None)))],
        )
        .unwrap();
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].class, StatementClass::Additive);
        assert_eq!(out[0].bare, "ALTER TABLE \"app\".\"accounts\" ADD COLUMN \"note\" text;");
        // 生成物是给人读的：带注释头
        assert!(out[0].sql.starts_with("-- "), "{}", out[0].sql);
    }

    #[test]
    fn new_column_keeps_nullability_and_default() {
        let out = alter_table(
            None,
            "t",
            &[change(None, Some(col("n", "integer", false, Some("0"))))],
        )
        .unwrap();
        assert_eq!(out[0].bare, "ALTER TABLE \"t\" ADD COLUMN \"n\" integer NOT NULL DEFAULT 0;");
    }

    #[test]
    fn changing_only_nullability_does_not_rebuild_the_column() {
        // 只改可空性不该走"建临时列"那套（那会白搬一遍数据）
        let out = alter_table(
            None,
            "t",
            &[change(Some(col("a", "text", true, None)), Some(col("a", "text", false, None)))],
        )
        .unwrap();
        assert_eq!(out.len(), 1);
        assert!(out[0].bare.contains("SET NOT NULL"), "{}", out[0].bare);
        assert!(!out.iter().any(|s| s.class == StatementClass::DataMoving));
    }

    #[test]
    fn dropping_not_null_and_setting_default_are_separate_statements() {
        let out = alter_table(
            None,
            "t",
            &[change(
                Some(col("a", "text", false, None)),
                Some(col("a", "text", true, Some("'x'"))),
            )],
        )
        .unwrap();
        assert_eq!(out.len(), 2, "{out:?}");
        assert!(out[0].bare.contains("DROP NOT NULL"));
        assert!(out[1].bare.contains("SET DEFAULT 'x'"));
    }

    #[test]
    fn a_type_change_is_rebuilt_in_four_visible_steps() {
        let out = alter_table(
            None,
            "t",
            &[change(Some(col("n", "text", true, None)), Some(col("n", "integer", true, None)))],
        )
        .unwrap();
        // 1 建临时列 / 2 搬值 / 3 删旧列（破坏性）/ 4 改名
        let kinds: Vec<StatementClass> = out.iter().map(|s| s.class).collect();
        assert_eq!(
            kinds,
            vec![
                StatementClass::DataMoving,
                StatementClass::DataMoving,
                StatementClass::Destructive,
                StatementClass::Altering
            ],
            "{out:?}"
        );
        assert!(out[0].bare.contains("ADD COLUMN \"n__new\" integer"));
        assert!(out[1].bare.contains("\"n__new\" = \"n\"::integer"));
        assert!(out[2].bare.contains("DROP COLUMN \"n\""));
        assert!(out[3].bare.contains("RENAME COLUMN \"n__new\" TO \"n\""));
    }

    #[test]
    fn renaming_a_column_keeps_its_data_and_comes_before_drops() {
        let out = alter_table(
            None,
            "t",
            &[
                change(Some(col("old", "text", true, None)), None),
                change(Some(col("a", "text", true, None)), Some(col("b", "text", true, None))),
            ],
        )
        .unwrap();
        // 改名在前、删除在后（删除永远最后）
        assert!(out[0].bare.contains("RENAME COLUMN \"a\" TO \"b\""), "{out:?}");
        assert_eq!(out.last().unwrap().class, StatementClass::Destructive);
        assert!(out.last().unwrap().bare.contains("DROP COLUMN \"old\""));
    }

    #[test]
    fn dropping_a_column_is_destructive_and_never_silently_executable() {
        let out = alter_table(None, "t", &[change(Some(col("a", "text", true, None)), None)]).unwrap();
        assert_eq!(out[0].class, StatementClass::Destructive);
        assert!(has_destructive(&out), "有删除列就必须被认出来");
        assert!(executable_subset(&out).is_empty(), "破坏性语句不许进'可自动执行'那一档");
        assert!(out[0].sql.contains("不自动执行"), "生成物里要写明这一点：{}", out[0].sql);
    }

    #[test]
    fn no_changes_means_no_statements() {
        assert!(alter_table(None, "t", &[]).unwrap().is_empty());
        // 一模一样的前后定义 = 没有变更（不该生成一堆无意义的 ALTER）
        let same = col("a", "text", true, None);
        assert!(alter_table(None, "t", &[change(Some(same.clone()), Some(same))]).unwrap().is_empty());
    }

    #[test]
    fn an_empty_table_name_is_refused() {
        let err = alter_table(None, "   ", &[]).unwrap_err();
        assert!(err.message.contains("表名"), "{}", err.message);
    }

    #[test]
    fn an_unnamed_new_column_is_refused() {
        let err = alter_table(None, "t", &[change(None, Some(col("  ", "text", true, None)))]).unwrap_err();
        assert!(err.message.contains("名字"), "{}", err.message);
    }

    #[test]
    fn index_creation_is_additive_and_names_itself_when_unnamed() {
        let one = create_index(Some("app"), "orders", &["account_id".into()], false, None).unwrap();
        assert_eq!(one.class, StatementClass::Additive);
        assert_eq!(one.bare, "CREATE INDEX \"account_id_idx\" ON \"app\".\"orders\" (\"account_id\");");
        let unique = create_index(None, "t", &["a".into(), "b".into()], true, Some("u_ab")).unwrap();
        assert!(unique.bare.contains("CREATE UNIQUE INDEX \"u_ab\""));
        assert!(unique.bare.contains("(\"a\", \"b\")"));
    }

    #[test]
    fn an_index_without_columns_is_refused() {
        let err = create_index(None, "t", &[], false, None).unwrap_err();
        assert!(err.message.contains("一列"), "{}", err.message);
    }

    #[test]
    fn dropping_an_index_is_destructive() {
        let out = drop_index(Some("app"), "account_id_idx");
        assert_eq!(out.class, StatementClass::Destructive);
        assert_eq!(out.bare, "DROP INDEX \"app\".\"account_id_idx\";");
    }

    #[test]
    fn a_foreign_key_requires_matching_column_counts() {
        let err = add_foreign_key(
            None,
            "orders",
            &["account_id".into()],
            Some("app"),
            "accounts",
            &["a".into(), "b".into()],
            None,
        )
        .unwrap_err();
        assert!(err.message.contains("列数不一致"), "{}", err.message);

        let ok = add_foreign_key(
            None,
            "orders",
            &["account_id".into()],
            Some("app"),
            "accounts",
            &["id".into()],
            Some("orders_account_fk"),
        )
        .unwrap();
        assert_eq!(ok.class, StatementClass::Additive);
        assert_eq!(
            ok.bare,
            "ALTER TABLE \"orders\" ADD CONSTRAINT \"orders_account_fk\" FOREIGN KEY (\"account_id\") REFERENCES \"app\".\"accounts\" (\"id\");"
        );
    }

    #[test]
    fn dropping_a_constraint_or_a_table_is_destructive() {
        let c = drop_constraint(Some("app"), "orders", "orders_account_fk");
        assert_eq!(c.class, StatementClass::Destructive);
        assert!(c.bare.contains("DROP CONSTRAINT \"orders_account_fk\""));
        let t = drop_table(Some("app"), "orders");
        assert_eq!(t.class, StatementClass::Destructive);
        assert!(t.bare.contains("DROP TABLE \"app\".\"orders\""));
        assert!(t.sql.contains("丢全部数据"));
    }

    #[test]
    fn executable_subset_keeps_only_additive_and_altering() {
        let out = alter_table(
            None,
            "t",
            &[
                change(None, Some(col("added", "text", true, None))),
                change(Some(col("gone", "text", true, None)), None),
            ],
        )
        .unwrap();
        let runnable = executable_subset(&out);
        assert_eq!(runnable.len(), 1);
        assert!(runnable[0].bare.contains("ADD COLUMN"));
    }
}
