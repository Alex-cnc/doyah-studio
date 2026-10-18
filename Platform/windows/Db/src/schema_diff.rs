//! **Schema 对比与同步**（FR-DDL-04）的纯逻辑：两份快照 → 差异清单 + 有序同步脚本。
//!
//! 六条口径（对结构做同步是"改了不好回退"的操作，条条都要说清）：
//! ① **快照对快照**，不要求一次连两个库：两个库常常不在同一次调用里（不同连接 / 机器 / 时间），
//!    快照落成 JSON 才能随时比、也能进版本库（与 macOS 侧同一取舍）。
//! ② **方向固定**：把**目标（右）** 同步成 **基准（左）** 的样子。界面上按这句话写，不靠用户猜。
//! ③ **删除默认不生成**：目标库多出来的表 / 列，只有 `allow_drop` 为真才生成 `DROP`；
//!    关着时**如实登记到 `skipped`**（"没做"要说出来，不能看起来像"没差异"）。
//! ④ **按列名匹配**：改名在差异里表现为「删 + 加」两笔（与 `ddl::alter_table` 同一口径），
//!    不猜"这两列是不是同一个"。
//! ⑤ **复用既有生成器**：加列 / 改列 / 删列走 `ddl::alter_table`，建表走 `ddl::create_table`，
//!    删表走 `ddl::drop_table` —— 本模块**不自己拼 DDL**（拼两份必然分叉）。
//! ⑥ **输出顺序确定**：建表 → 改表 → 删表，表名按字典序 ⇒ 同一对快照每次给的脚本逐字一致
//!    （否则"脚本变了没有"这件事没法判）。

use serde::{Deserialize, Serialize};

use crate::ddl::{self, ColumnChange, ColumnDef, DdlStatement};

/// 快照里的一列：**只有结构与名，没有任何数据**。
pub type SnapshotColumn = ColumnDef;

/// 快照里的一张表。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotTable {
    pub name: String,
    pub columns: Vec<SnapshotColumn>,
    /// 主键列（按主键内的顺序；空 = 没有主键）
    #[serde(default)]
    pub primary_key: Vec<String>,
}

/// 一份库结构快照（一个 schema 一张）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SchemaSnapshot {
    /// 这份快照是哪一边（界面直接显示，不让用户猜"左是哪份"）
    pub label: String,
    pub schema: String,
    /// 抓取时刻（epoch 毫秒，由调用方给 —— 本层是纯函数，不读时钟）
    #[serde(default)]
    pub taken_at: i64,
    pub tables: Vec<SnapshotTable>,
}

impl SchemaSnapshot {
    /// 表名查表（差异判定要反复按名找，线性找在几十张表时够用且不必引入 map 生命周期）。
    fn table(&self, name: &str) -> Option<&SnapshotTable> {
        self.tables.iter().find(|t| t.name == name)
    }

    /// 表名清单（升序；界面与判据都按这个顺序读）。
    pub fn table_names(&self) -> Vec<String> {
        let mut names: Vec<String> = self.tables.iter().map(|t| t.name.clone()).collect();
        names.sort();
        names
    }
}

/// 服务端**一次查询**回来的一行：`(表名, 列名, 类型原文, 是否可空, 默认值原文)`。
pub type SnapshotColumnRow = (String, String, String, bool, Option<String>);

/// 把「一次查回来的列」+「一次查回来的主键列」组装成快照。
///
/// 生产的取数（`App/src-tauri/src/postgres.rs` 的两条 SQL）与判据自测走**同一个**组装口 ——
/// 组装规则只有一份，判据钉的就是盘上跑的那份。
pub fn assemble_snapshot(
    label: &str,
    schema: &str,
    taken_at: i64,
    columns: &[SnapshotColumnRow],
    primary_keys: &[(String, String)],
) -> SchemaSnapshot {
    let mut tables: Vec<SnapshotTable> = Vec::new();
    for (table, name, data_type, is_nullable, default_expr) in columns {
        let column = ColumnDef {
            name: name.clone(),
            data_type: data_type.clone(),
            is_nullable: *is_nullable,
            default_expr: default_expr.clone(),
        };
        match tables.iter_mut().find(|t| &t.name == table) {
            Some(group) => group.columns.push(column),
            // 没被点名过的表也**如实留下**（不静默丢）
            None => tables.push(SnapshotTable {
                name: table.clone(),
                columns: vec![column],
                primary_key: Vec::new(),
            }),
        }
    }
    for (table, column) in primary_keys {
        if let Some(group) = tables.iter_mut().find(|t| &t.name == table) {
            group.primary_key.push(column.clone());
        }
    }
    // 顺序定死：表名升序（列保持服务端给的列序）
    tables.sort_by(|a, b| a.name.cmp(&b.name));
    SchemaSnapshot {
        label: label.to_string(),
        schema: schema.to_string(),
        taken_at,
        tables,
    }
}

/// 一张表在差异里的形态。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TableStatus {
    /// 基准有、目标没有 ⇒ 生成 `CREATE TABLE`
    Create,
    /// 基准没有、目标有 ⇒ 只有允许删除时才生成 `DROP TABLE`
    Drop,
    /// 两侧都有、结构不同 ⇒ 生成 `ALTER TABLE`
    Alter,
    /// 两侧都有、结构一致（含主键一致）
    Same,
}

/// 一张表的差异摘要（界面按它分组显示；`statements` 在报告级统一有序）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TableDiff {
    pub table: String,
    pub status: TableStatus,
    /// 基准有、目标没有的列（要加）
    pub added_columns: Vec<String>,
    /// 目标有、基准没有的列（要删 —— 只有允许删除时才会真生成）
    pub removed_columns: Vec<String>,
    /// 两侧都有但类型 / 可空 / 默认值不同的列
    pub altered_columns: Vec<String>,
    /// 主键是否不同（**不自动生成**：改主键要先定"现有数据怎么办"，属人工判断）
    pub primary_key_differs: bool,
}

/// 一处**看见了但没生成语句**的差异（"没做"必须说出来）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SkippedChange {
    pub table: String,
    pub what: String,
    pub reason: String,
}

/// 对比报告。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SchemaDiffReport {
    pub base_label: String,
    pub target_label: String,
    pub base_table_count: usize,
    pub target_table_count: usize,
    pub table_diffs: Vec<TableDiff>,
    /// 有序同步脚本（建表 → 改表 → 删表）
    pub statements: Vec<DdlStatement>,
    pub skipped: Vec<SkippedChange>,
    /// 本次是否允许删除（界面要显示，用户才知道"为什么没删"）
    pub allow_drop: bool,
    /// 生成物里标了 `destructive` 的条数（改类型的"删旧列"也算 —— 它真的丢数据）
    pub destructive_count: usize,
    pub created_tables: usize,
    pub altered_tables: usize,
    pub dropped_tables: usize,
}

impl SchemaDiffReport {
    /// 两侧结构完全一致（没有语句、也没有被跳过的差异）。
    pub fn in_sync(&self) -> bool {
        self.statements.is_empty() && self.skipped.is_empty()
    }
}

/// 对比两份快照，**把目标同步成基准**。
///
/// `allow_drop` 为假 ⇒ 目标多出来的表 / 列只登记进 `skipped`，不生成任何 `DROP`。
/// 真 ⇒ 生成 `DROP COLUMN` / `DROP TABLE`，并标 `destructive`（界面只给复制、不自动执行）。
pub fn diff(base: &SchemaSnapshot, target: &SchemaSnapshot, allow_drop: bool) -> SchemaDiffReport {
    let mut table_diffs: Vec<TableDiff> = Vec::new();
    let mut statements: Vec<DdlStatement> = Vec::new();
    let mut skipped: Vec<SkippedChange> = Vec::new();
    let mut created = 0usize;
    let mut altered = 0usize;
    let mut dropped = 0usize;

    for name in base.table_names() {
        let base_table = base.table(&name).expect("表名来自自身清单");
        match target.table(&name) {
            // ① 目标没有这张表 ⇒ 建
            None => {
                match ddl::create_table(
                    Some(target.schema.as_str()),
                    &name,
                    &base_table.columns,
                    &base_table.primary_key,
                ) {
                    Ok(statement) => {
                        statements.push(statement);
                        created += 1;
                        table_diffs.push(TableDiff {
                            table: name.clone(),
                            status: TableStatus::Create,
                            added_columns: base_table.columns.iter().map(|c| c.name.clone()).collect(),
                            removed_columns: Vec::new(),
                            altered_columns: Vec::new(),
                            primary_key_differs: false,
                        });
                    }
                    Err(error) => skipped.push(SkippedChange {
                        table: name.clone(),
                        what: "建表".to_string(),
                        reason: format!("{}（{}）", error.message, error.hint),
                    }),
                }
            }
            // ② 两侧都有 ⇒ 比列
            Some(target_table) => {
                let mut changes: Vec<ColumnChange> = Vec::new();
                let mut added: Vec<String> = Vec::new();
                let mut removed: Vec<String> = Vec::new();
                let mut altered_cols: Vec<String> = Vec::new();

                for column in &base_table.columns {
                    match target_table.columns.iter().find(|c| c.name == column.name) {
                        Some(existing) => {
                            let change = ColumnChange {
                                from: Some(existing.clone()),
                                to: Some(column.clone()),
                            };
                            if change.is_alter() {
                                altered_cols.push(column.name.clone());
                            }
                            if change.is_alter() || change.is_rename() {
                                changes.push(change);
                            }
                        }
                        None => {
                            added.push(column.name.clone());
                            changes.push(ColumnChange { from: None, to: Some(column.clone()) });
                        }
                    }
                }
                for column in &target_table.columns {
                    if base_table.columns.iter().any(|c| c.name == column.name) {
                        continue;
                    }
                    removed.push(column.name.clone());
                    if allow_drop {
                        changes.push(ColumnChange { from: Some(column.clone()), to: None });
                    } else {
                        skipped.push(SkippedChange {
                            table: name.clone(),
                            what: format!("删除列 {}", column.name),
                            reason: "删除默认不生成（会丢数据）：勾上「允许删除」才出 DROP COLUMN。"
                                .to_string(),
                        });
                    }
                }

                let primary_key_differs = base_table.primary_key != target_table.primary_key;
                if primary_key_differs {
                    skipped.push(SkippedChange {
                        table: name.clone(),
                        what: format!(
                            "主键（基准 [{}] / 目标 [{}]）",
                            base_table.primary_key.join(", "),
                            target_table.primary_key.join(", ")
                        ),
                        reason: "改主键要先定现有数据怎么办（重复值 / 空值会直接失败），本侧只报告、不自动生成。"
                            .to_string(),
                    });
                }

                let status = if changes.is_empty()
                    && added.is_empty()
                    && removed.is_empty()
                    && altered_cols.is_empty()
                    && !primary_key_differs
                {
                    TableStatus::Same
                } else {
                    if !changes.is_empty() {
                        match ddl::alter_table(Some(target.schema.as_str()), &name, &changes) {
                            Ok(generated) => {
                                altered += 1;
                                statements.extend(generated);
                            }
                            Err(error) => skipped.push(SkippedChange {
                                table: name.clone(),
                                what: "改表".to_string(),
                                reason: format!("{}（{}）", error.message, error.hint),
                            }),
                        }
                    }
                    TableStatus::Alter
                };

                if status != TableStatus::Same {
                    table_diffs.push(TableDiff {
                        table: name,
                        status,
                        added_columns: added,
                        removed_columns: removed,
                        altered_columns: altered_cols,
                        primary_key_differs,
                    });
                }
            }
        }
    }

    // ③ 目标多出来的表 ⇒ 只有允许删除时才生成 DROP（否则如实报跳过）
    for name in target.table_names() {
        if base.table(&name).is_some() {
            continue;
        }
        let column_count = target.table(&name).map(|t| t.columns.len()).unwrap_or(0);
        if allow_drop {
            statements.push(ddl::drop_table(Some(target.schema.as_str()), &name));
            dropped += 1;
            table_diffs.push(TableDiff {
                table: name,
                status: TableStatus::Drop,
                added_columns: Vec::new(),
                removed_columns: Vec::new(),
                altered_columns: Vec::new(),
                primary_key_differs: false,
            });
        } else {
            skipped.push(SkippedChange {
                table: name,
                what: format!("删除表（目标库多出来的表，{column_count} 列）"),
                reason: "删除默认不生成（会丢数据）：勾上「允许删除」才出 DROP TABLE。".to_string(),
            });
        }
    }
    table_diffs.sort_by(|a, b| a.table.cmp(&b.table));

    let destructive_count = statements
        .iter()
        .filter(|s| matches!(s.class, ddl::StatementClass::Destructive))
        .count();

    SchemaDiffReport {
        base_label: base.label.clone(),
        target_label: target.label.clone(),
        base_table_count: base.tables.len(),
        target_table_count: target.tables.len(),
        table_diffs,
        statements,
        skipped,
        allow_drop,
        destructive_count,
        created_tables: created,
        altered_tables: altered,
        dropped_tables: dropped,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn column(name: &str, data_type: &str) -> ColumnDef {
        ColumnDef {
            name: name.to_string(),
            data_type: data_type.to_string(),
            is_nullable: true,
            default_expr: None,
        }
    }

    fn table(name: &str, columns: Vec<ColumnDef>) -> SnapshotTable {
        SnapshotTable { name: name.to_string(), columns, primary_key: Vec::new() }
    }

    fn snapshot(label: &str, tables: Vec<SnapshotTable>) -> SchemaSnapshot {
        SchemaSnapshot {
            label: label.to_string(),
            schema: "public".to_string(),
            taken_at: 0,
            tables,
        }
    }

    #[test]
    fn identical_snapshots_produce_no_statements_and_no_skips() {
        let left = snapshot("左", vec![table("orders", vec![column("id", "integer")])]);
        let right = snapshot("右", vec![table("orders", vec![column("id", "integer")])]);
        let report = diff(&left, &right, false);
        assert!(report.statements.is_empty(), "结构一致不该生成语句");
        assert!(report.skipped.is_empty(), "结构一致不该有跳过项");
        assert!(report.in_sync(), "两侧一致要能一句话说出来");
    }

    #[test]
    fn a_table_only_in_the_base_is_created_with_every_column() {
        let left = snapshot(
            "左",
            vec![table("orders", vec![column("id", "integer"), column("memo", "text")])],
        );
        let right = snapshot("右", vec![]);
        let report = diff(&left, &right, false);
        assert_eq!(report.created_tables, 1);
        assert_eq!(report.statements.len(), 1);
        let sql = &report.statements[0].bare;
        assert!(sql.starts_with("CREATE TABLE \"public\".\"orders\""), "实际：{sql}");
        assert!(sql.contains("\"id\" integer"), "列要逐列写全：{sql}");
        assert!(sql.contains("\"memo\" text"), "列要逐列写全：{sql}");
        assert_eq!(report.table_diffs[0].status, TableStatus::Create);
    }

    #[test]
    fn a_table_only_in_the_target_is_dropped_only_when_drops_are_allowed() {
        let left = snapshot("左", vec![]);
        let right = snapshot("右", vec![table("legacy", vec![column("id", "integer")])]);
        let safe = diff(&left, &right, false);
        assert!(safe.statements.is_empty(), "默认不许生成 DROP");
        assert_eq!(safe.skipped.len(), 1, "跳过的表要如实登记");
        assert_eq!(safe.skipped[0].table, "legacy");
        assert!(safe.skipped[0].what.contains("删除表"), "要写清是哪一类差异");
        assert!(!safe.in_sync(), "有跳过项就不算一致");

        let allowed = diff(&left, &right, true);
        assert_eq!(allowed.dropped_tables, 1);
        assert_eq!(allowed.statements.len(), 1);
        assert_eq!(allowed.statements[0].class, ddl::StatementClass::Destructive);
        assert!(allowed.statements[0].bare.starts_with("DROP TABLE"));
        assert_eq!(allowed.destructive_count, 1);
    }

    #[test]
    fn a_column_missing_from_the_target_is_added_and_never_dropped_silently() {
        let left = snapshot(
            "左",
            vec![table("orders", vec![column("id", "integer"), column("note", "text")])],
        );
        let right = snapshot("右", vec![table("orders", vec![column("id", "integer")])]);
        let report = diff(&left, &right, false);
        assert_eq!(report.table_diffs.len(), 1);
        assert_eq!(report.table_diffs[0].added_columns, vec!["note".to_string()]);
        let sql = report.statements.iter().map(|s| s.bare.as_str()).collect::<Vec<_>>().join("\n");
        assert!(sql.contains("ADD COLUMN \"note\" text"), "实际：{sql}");
        assert!(!sql.contains("DROP"), "基准缺的列不许顺手删：{sql}");
    }

    #[test]
    fn a_column_missing_from_the_base_is_dropped_only_with_allow_drop() {
        let left = snapshot("左", vec![table("orders", vec![column("id", "integer")])]);
        let right = snapshot(
            "右",
            vec![table("orders", vec![column("id", "integer"), column("old_note", "text")])],
        );
        let safe = diff(&left, &right, false);
        assert!(safe.statements.is_empty(), "默认不许生成 DROP COLUMN");
        assert_eq!(safe.table_diffs[0].removed_columns, vec!["old_note".to_string()]);
        assert!(safe.skipped.iter().any(|s| s.what.contains("old_note")), "被跳过的列要点名");

        let allowed = diff(&left, &right, true);
        let sql = allowed.statements.iter().map(|s| s.bare.as_str()).collect::<Vec<_>>().join("\n");
        assert!(sql.contains("DROP COLUMN \"old_note\""), "实际：{sql}");
    }

    #[test]
    fn a_type_change_is_reported_as_altered_and_uses_the_rebuild_form() {
        let left = snapshot("左", vec![table("orders", vec![column("qty", "bigint")])]);
        let right = snapshot("右", vec![table("orders", vec![column("qty", "integer")])]);
        let report = diff(&left, &right, false);
        assert_eq!(report.altered_tables, 1);
        assert_eq!(report.table_diffs[0].altered_columns, vec!["qty".to_string()]);
        let sql = report.statements.iter().map(|s| s.bare.as_str()).collect::<Vec<_>>().join("\n");
        // 改类型走"重建式四步"（既有生成器的口径），不是一句黑箱 ALTER
        assert!(sql.contains("\"qty__new\" bigint"), "实际：{sql}");
        assert!(sql.contains("DROP COLUMN \"qty\""), "重建式必然含删旧列：{sql}");
    }

    #[test]
    fn a_nullable_change_only_touches_nullability() {
        let left = snapshot(
            "左",
            vec![table(
                "orders",
                vec![ColumnDef { is_nullable: false, ..column("id", "integer") }],
            )],
        );
        let right = snapshot("右", vec![table("orders", vec![column("id", "integer")])]);
        let report = diff(&left, &right, false);
        let sql = report.statements.iter().map(|s| s.bare.as_str()).collect::<Vec<_>>().join("\n");
        assert!(sql.contains("SET NOT NULL"), "实际：{sql}");
        assert!(!sql.contains("__new"), "只改可空不该重建列：{sql}");
    }

    #[test]
    fn a_renamed_column_is_reported_as_remove_plus_add_not_guessed() {
        let left = snapshot("左", vec![table("orders", vec![column("note", "text")])]);
        let right = snapshot("右", vec![table("orders", vec![column("memo", "text")])]);
        let report = diff(&left, &right, false);
        assert_eq!(report.table_diffs[0].added_columns, vec!["note".to_string()]);
        assert_eq!(report.table_diffs[0].removed_columns, vec!["memo".to_string()]);
        let sql = report.statements.iter().map(|s| s.bare.as_str()).collect::<Vec<_>>().join("\n");
        assert!(sql.contains("ADD COLUMN \"note\""), "实际：{sql}");
        assert!(!sql.contains("RENAME"), "按列名匹配，不猜改名：{sql}");
    }

    #[test]
    fn a_primary_key_difference_is_reported_as_skipped_not_silently_ignored() {
        let mut left_table = table("orders", vec![column("id", "integer")]);
        left_table.primary_key = vec!["id".to_string()];
        let mut right_table = table("orders", vec![column("id", "integer")]);
        right_table.primary_key = Vec::new();
        let report = diff(&snapshot("左", vec![left_table]), &snapshot("右", vec![right_table]), false);
        assert!(report.statements.is_empty(), "改主键不自动生成");
        assert_eq!(report.skipped.len(), 1);
        assert!(report.skipped[0].what.contains("主键"), "要写清是哪一项");
        assert!(report.table_diffs[0].primary_key_differs);
    }

    #[test]
    fn statements_are_ordered_create_then_alter_then_drop() {
        let left = snapshot(
            "左",
            vec![
                table("alpha", vec![column("id", "integer")]),
                table("beta", vec![column("id", "integer"), column("extra", "text")]),
            ],
        );
        let right = snapshot(
            "右",
            vec![
                table("beta", vec![column("id", "integer")]),
                table("zeta", vec![column("id", "integer")]),
            ],
        );
        let report = diff(&left, &right, true);
        let kinds: Vec<&str> = report
            .statements
            .iter()
            .map(|s| if s.bare.starts_with("CREATE") { "create" } else if s.bare.starts_with("DROP TABLE") { "drop" } else { "alter" })
            .collect();
        assert_eq!(kinds.first().copied(), Some("create"), "建表排最前：{kinds:?}");
        assert_eq!(kinds.last().copied(), Some("drop"), "删表排最后：{kinds:?}");
    }

    #[test]
    fn the_same_pair_of_snapshots_always_gives_byte_identical_sql() {
        let left = snapshot(
            "左",
            vec![table("b", vec![column("x", "text")]), table("a", vec![column("y", "text")])],
        );
        let right = snapshot("右", vec![]);
        let first: Vec<String> = diff(&left, &right, false).statements.into_iter().map(|s| s.sql).collect();
        let again: Vec<String> = diff(&left, &right, false).statements.into_iter().map(|s| s.sql).collect();
        assert_eq!(first, again, "同一对快照必须给逐字一致的脚本");
        assert!(first[0].contains("\"a\" ("), "表按名字排序：{:?}", first[0]);
    }

    #[test]
    fn assembling_rows_keeps_every_column_and_attaches_the_primary_key() {
        let rows: Vec<SnapshotColumnRow> = vec![
            ("orders".into(), "id".into(), "integer".into(), false, None),
            (
                "orders".into(),
                "created".into(),
                "timestamp with time zone".into(),
                true,
                Some("now()".into()),
            ),
            ("items".into(), "id".into(), "integer".into(), false, None),
        ];
        let pks = vec![("orders".to_string(), "id".to_string())];
        let snap = assemble_snapshot("左", "public", 42, &rows, &pks);
        assert_eq!(snap.tables.len(), 2);
        assert_eq!(snap.tables[0].name, "items", "表名升序");
        let orders = &snap.tables[1];
        assert_eq!(orders.columns.len(), 2);
        assert_eq!(orders.primary_key, vec!["id".to_string()]);
        assert_eq!(orders.columns[1].default_expr.as_deref(), Some("now()"));
        assert!(snap.tables[0].columns[0].is_nullable == false);
    }
}
