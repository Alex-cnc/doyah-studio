//! 库与服务器管理面的**纯逻辑**（1.7 段）：危险操作确认、维护命令生成、读数格式化。
//!
//! 五条口径（这一段全是"能搞坏服务器"的操作，条条都要说清）：
//! ① **删库要手输库名**（版本计划原文）：`confirm_drop` 要求用户逐字打出库名才放行 ——
//!    这是**唯一**一种"点了确认就执行"的操作里还额外要打字的一档，因为删库不可回退。
//! ② **维护任务只生成命令、不自动执行**（原文）：`maintenance_commands` 只返回命令文本，
//!    本层**没有任何执行入口**；命令里带注释说明它干什么、代价是什么。
//! ③ **杀会话只登记不执行**（原文）：`terminate_command` 生成 `pg_terminate_backend(...)`，
//!    同样只给文本。
//! ④ **读数如实**：`format_bytes` / `format_duration` 把服务端给的原始数字转成人读文本，
//!    **不四舍五入到失真**（1023 字节不许说成 "1.0 kB"）；单位不够精确时宁可给原始数。
//! ⑤ **权限预览是"将要说什么"**：`grant_sql` 只生成 `GRANT` / `REVOKE` 语句供预览，
//!    执行与否由调用方决定（与 DDL 那条路同一姿势）。

use serde::{Deserialize, Serialize};

use crate::writeback::quote_ident;

/// 危险操作的确认结果。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Confirmation {
    pub ok: bool,
    /// 不通过时的**可读原因**（说清要打什么、差在哪儿）
    pub reason: Option<String>,
}

/// **删库确认**：用户必须逐字打出库名（大小写敏感 —— 库名在 PostgreSQL 里就是大小写敏感的，
/// 这里若放宽，用户打错一个字母也照样删掉了）。
pub fn confirm_drop(typed: &str, database: &str) -> Confirmation {
    let expected = database.trim();
    if expected.is_empty() {
        return Confirmation {
            ok: false,
            reason: Some("库名是空的：不知道要删哪个库".to_string()),
        };
    }
    if typed != expected {
        return Confirmation {
            ok: false,
            reason: Some(format!("请逐字输入库名「{expected}」才能执行（大小写要一致）")),
        };
    }
    Confirmation { ok: true, reason: None }
}

/// 一条维护命令（**只生成、不执行**）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MaintenanceCommand {
    /// 带注释头的完整文本（给人读）
    pub sql: String,
    /// 裸语句（要真执行时用它）
    pub bare: String,
    /// 它干什么
    pub purpose: String,
    /// **代价 / 风险**（不许空 —— 维护命令都有代价，说清才叫"如实"）
    pub cost: String,
}

fn command(purpose: &str, bare: String, cost: &str) -> MaintenanceCommand {
    MaintenanceCommand {
        sql: format!("-- {purpose}\n-- 代价：{cost}\n{bare}"),
        bare,
        purpose: purpose.to_string(),
        cost: cost.to_string(),
    }
}

/// 生成**一组维护命令**（只生成、不执行；调用方按需复制）。
///
/// 为什么把它们放在一起而不是一条条单独给：这一组是"库里变慢了 / 胀了 / 统计旧了"时的常用动作，
/// 一起列出来用户能一次看全；但**每一句都各自带代价说明**，不会让人以为"一键全跑就对了"。
pub fn maintenance_commands(schema: Option<&str>, table: &str) -> Vec<MaintenanceCommand> {
    let qualified = crate::writeback::qualified(schema, table);
    vec![
        command(
            &format!("更新 {table} 的统计信息（优化器据此选计划）"),
            format!("ANALYZE {qualified};"),
            "会读一遍表采样；大表上要几十秒到几分钟，期间有额外 IO",
        ),
        command(
            &format!("回收 {table} 的空间（普通 VACUUM）"),
            format!("VACUUM {qualified};"),
            "不锁写、可与业务并行；只把死元组空间标记为可复用，**不还给操作系统**",
        ),
        command(
            &format!("回收 {table} 的空间并更新统计（VACUUM ANALYZE）"),
            format!("VACUUM ANALYZE {qualified};"),
            "等同上面两条一起跑；同样不还空间给操作系统",
        ),
        command(
            &format!("全量重建 {table}（会**长时间持排他锁**）"),
            format!("VACUUM FULL {qualified};"),
            "**持排他锁、期间这张表读写都被挡住**；会真正把空间还给操作系统 —— 生产库上要挑窗口",
        ),
        command(
            &format!("重写 {table} 消除膨胀（不长时间锁表，需先装 pg_repack）"),
            // 这条是**外部工具**的用法：本侧只把命令行写出来，**不代为执行**
            match schema {
                Some(s) => format!("-- pg_repack -t {table} -n {s}"),
                None => format!("-- pg_repack -t {table}"),
            },
            "需要另装 pg_repack；比 VACUUM FULL 温和但仍要额外磁盘空间",
        ),
    ]
}

/// 生成**杀会话**命令（只生成、不执行；版本计划点名"只登记不执行"）。
pub fn terminate_command(pid: i32, force: bool) -> MaintenanceCommand {
    let func = if force { "pg_terminate_backend" } else { "pg_cancel_backend" };
    let purpose = if force {
        format!("强制断开后端 {pid}（连接会被直接掐掉，客户端会看到连接错误）")
    } else {
        format!("取消后端 {pid} 上正在跑的查询（连接保留）")
    };
    let cost = if force {
        "**会掐断该连接**：对方若正在事务中，事务回滚；先试 cancel 再考虑 terminate"
    } else {
        "只取消当前语句；若它在长事务里，事务本身还在（之后可能又跑起来）—— 先试 cancel，不行再 terminate"
    };
    command(&purpose, format!("SELECT {func}({pid});"), cost)
}

/// 生成**授权预览**语句（只生成、不执行）。
///
/// `privileges` 是 `SELECT` / `INSERT` 这类；`object` 是表 / schema 名。
/// `revoke` 为真时生成回收语句（**同样只生成**）。
pub fn grant_sql(
    privileges: &[String],
    object_kind: &str,
    schema: Option<&str>,
    object: &str,
    role: &str,
    revoke: bool,
) -> Result<String, String> {
    if privileges.is_empty() {
        return Err("没有选任何权限：不知道要授什么".to_string());
    }
    if object.trim().is_empty() {
        return Err("对象名是空的".to_string());
    }
    if role.trim().is_empty() {
        return Err("角色名是空的".to_string());
    }
    let kind = match object_kind.trim().to_ascii_lowercase().as_str() {
        "table" | "table " => "TABLE",
        "schema" => "SCHEMA",
        "sequence" => "SEQUENCE",
        "database" => "DATABASE",
        other => {
            return Err(format!(
                "认不出的对象种类「{other}」（可用：table / schema / sequence / database）"
            ))
        }
    };
    // schema 只对 table / sequence 有意义；给 SCHEMA / DATABASE 时不拼限定名
    let target = if kind == "SCHEMA" || kind == "DATABASE" {
        quote_ident(object)
    } else {
        crate::writeback::qualified(schema, object)
    };
    let verb = if revoke { "REVOKE" } else { "GRANT" };
    Ok(format!(
        "{verb} {} ON {kind} {target} {} {};",
        privileges.join(", "),
        if revoke { "FROM" } else { "TO" },
        quote_ident(role)
    ))
}

/// 字节数 → 人读文本。
///
/// 口径（**不许失真**）：用 1024 进制、保留一位小数，但**只在能表示出来时才进位** ——
/// 1023 字节必须显示 `1023 B`（不是 `1.0 kB`）；1024 才显示 `1.0 kB`。
pub fn format_bytes(bytes: i64) -> String {
    const UNITS: [&str; 5] = ["B", "kB", "MB", "GB", "TB"];
    if bytes < 0 {
        return format!("{bytes} B");
    }
    let mut value = bytes as f64;
    let mut unit = 0usize;
    while value >= 1024.0 && unit + 1 < UNITS.len() {
        value /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{bytes} B")
    } else {
        format!("{value:.1} {}", UNITS[unit])
    }
}

/// 毫秒 → 人读时长（同样是"不许失真"：不足 1 秒就说毫秒，不写成 `0.0 s`）。
pub fn format_duration(ms: i64) -> String {
    if ms < 0 {
        return format!("{ms} ms");
    }
    if ms < 1000 {
        return format!("{ms} ms");
    }
    let seconds = ms as f64 / 1000.0;
    if seconds < 60.0 {
        return format!("{seconds:.1} s");
    }
    let minutes = seconds / 60.0;
    if minutes < 60.0 {
        return format!("{:.1} min", minutes);
    }
    format!("{:.1} h", minutes / 60.0)
}

/// 会话与锁的一行（驱动读回来后由界面显示；本层只管**排序与分组口径**）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionRow {
    pub pid: i32,
    pub user: String,
    pub database: String,
    /// `active` / `idle` / `idle in transaction` / …
    pub state: String,
    /// 正在跑的语句（`None` = 没在跑）
    pub query: Option<String>,
    /// 这条会话跑了多久（毫秒）
    pub duration_ms: i64,
    /// 它是不是**等锁**的那个（`wait_event_type = 'Lock'`）
    pub waiting: bool,
}

/// 排序：**等锁的排最前**（它们才是"现在就有事"的），然后按跑了多久从长到短。
///
/// 为什么等锁优先而不是按时长：一条 idle 三天不动的连接没有危害，
/// 而一条等了 5 秒锁的会话正在挡着别人 —— 按危害排，不按数字大小排。
pub fn sort_sessions(rows: &mut [SessionRow]) {
    rows.sort_by(|a, b| {
        b.waiting
            .cmp(&a.waiting)
            .then_with(|| b.duration_ms.cmp(&a.duration_ms))
            .then_with(|| a.pid.cmp(&b.pid))
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dropping_a_database_requires_the_exact_name() {
        assert!(confirm_drop("doyah_lab", "doyah_lab").ok);
        // 大小写不一致也不算（PostgreSQL 的库名大小写敏感，放宽就等于"打错也能删"）
        assert!(!confirm_drop("DOYAH_LAB", "doyah_lab").ok);
        assert!(!confirm_drop("doyah_la", "doyah_lab").ok);
        assert!(!confirm_drop("", "doyah_lab").ok);
        let refusal = confirm_drop("wrong", "doyah_lab");
        assert!(refusal.reason.unwrap().contains("doyah_lab"));
    }

    #[test]
    fn dropping_with_an_empty_database_name_is_refused_with_a_reason() {
        let r = confirm_drop("anything", "   ");
        assert!(!r.ok);
        assert!(r.reason.unwrap().contains("空的"));
    }

    #[test]
    fn maintenance_commands_never_execute_and_always_state_their_cost() {
        let cmds = maintenance_commands(Some("app"), "orders");
        assert!(cmds.len() >= 4);
        for c in &cmds {
            // 每一条都必须写清代价（"如实"的最低要求）
            assert!(!c.cost.trim().is_empty(), "{} 没写代价", c.purpose);
            assert!(c.sql.contains("-- 代价："), "{}", c.sql);
            assert!(!c.bare.is_empty());
        }
        // 危险的那条必须点名锁表
        let full = cmds.iter().find(|c| c.bare.contains("VACUUM FULL")).expect("应当有 VACUUM FULL");
        assert!(full.cost.contains("锁"), "{}", full.cost);
    }

    #[test]
    fn maintenance_sql_uses_the_qualified_quoted_name() {
        let cmds = maintenance_commands(Some("app"), "orders");
        let analyze = cmds.iter().find(|c| c.bare.starts_with("ANALYZE")).unwrap();
        assert_eq!(analyze.bare, "ANALYZE \"app\".\"orders\";");
        // 不带 schema 时只给表名
        let no_schema = maintenance_commands(None, "orders");
        assert_eq!(no_schema[0].bare, "ANALYZE \"orders\";");
    }

    #[test]
    fn terminating_a_session_only_produces_text_and_warns_about_the_cost() {
        let cancel = terminate_command(1234, false);
        assert_eq!(cancel.bare, "SELECT pg_cancel_backend(1234);");
        assert!(cancel.cost.contains("事务"), "{}", cancel.cost);
        let force = terminate_command(1234, true);
        assert_eq!(force.bare, "SELECT pg_terminate_backend(1234);");
        assert!(force.cost.contains("掐断"), "{}", force.cost);
        // 先温和后强硬：cancel 的说法里要提"先试 cancel 再考虑 terminate"这条阶梯
        assert!(cancel.cost.contains("先试 cancel"), "{}", cancel.cost);
    }

    #[test]
    fn grant_preview_builds_grant_and_revoke_for_tables() {
        let sql = grant_sql(
            &["SELECT".into(), "INSERT".into()],
            "table",
            Some("app"),
            "orders",
            "reporting",
            false,
        )
        .unwrap();
        assert_eq!(
            sql,
            "GRANT SELECT, INSERT ON TABLE \"app\".\"orders\" TO \"reporting\";"
        );
        let revoked = grant_sql(&["UPDATE".into()], "table", None, "orders", "r", true).unwrap();
        assert_eq!(revoked, "REVOKE UPDATE ON TABLE \"orders\" FROM \"r\";");
    }

    #[test]
    fn grant_preview_refuses_incomplete_input() {
        assert!(grant_sql(&[], "table", None, "t", "r", false).is_err());
        assert!(grant_sql(&["SELECT".into()], "table", None, "  ", "r", false).is_err());
        assert!(grant_sql(&["SELECT".into()], "table", None, "t", "  ", false).is_err());
        let bad_kind = grant_sql(&["SELECT".into()], "banana", None, "t", "r", false).unwrap_err();
        assert!(bad_kind.contains("banana"), "{bad_kind}");
    }

    #[test]
    fn schema_and_database_grants_are_not_schema_qualified() {
        let s = grant_sql(&["USAGE".into()], "schema", Some("app"), "app", "r", false).unwrap();
        assert_eq!(s, "GRANT USAGE ON SCHEMA \"app\" TO \"r\";");
        let d = grant_sql(&["CONNECT".into()], "database", None, "doyah_lab", "r", false).unwrap();
        assert_eq!(d, "GRANT CONNECT ON DATABASE \"doyah_lab\" TO \"r\";");
    }

    #[test]
    fn byte_formatting_never_distorts_small_values() {
        // 1023 字节不许说成 1.0 kB（这是"如实报数"的最低线）
        assert_eq!(format_bytes(1023), "1023 B");
        assert_eq!(format_bytes(1024), "1.0 kB");
        assert_eq!(format_bytes(0), "0 B");
        assert_eq!(format_bytes(1536), "1.5 kB");
        assert_eq!(format_bytes(1024 * 1024), "1.0 MB");
        assert_eq!(format_bytes(-5), "-5 B");
    }

    #[test]
    fn duration_formatting_never_distorts_sub_second_values() {
        assert_eq!(format_duration(999), "999 ms");
        assert_eq!(format_duration(0), "0 ms");
        assert_eq!(format_duration(1000), "1.0 s");
        assert_eq!(format_duration(1500), "1.5 s");
        assert_eq!(format_duration(90_000), "1.5 min");
        assert_eq!(format_duration(3_600_000), "1.0 h");
    }

    fn session(pid: i32, waiting: bool, duration_ms: i64) -> SessionRow {
        SessionRow {
            pid,
            user: "u".into(),
            database: "d".into(),
            state: "active".into(),
            query: None,
            duration_ms,
            waiting,
        }
    }

    #[test]
    fn sessions_waiting_on_locks_come_first_then_longest_running() {
        let mut rows = vec![
            session(1, false, 999_999),
            session(2, true, 10),
            session(3, false, 5),
            session(4, true, 100),
        ];
        sort_sessions(&mut rows);
        let order: Vec<i32> = rows.iter().map(|r| r.pid).collect();
        // 等锁的两个在前（其中跑得久的先），其余按时长降序
        assert_eq!(order, vec![4, 2, 1, 3]);
    }

    #[test]
    fn sorting_is_stable_for_identical_keys() {
        let mut a = vec![session(7, false, 100), session(3, false, 100)];
        let mut b = a.clone();
        sort_sessions(&mut a);
        sort_sessions(&mut b);
        assert_eq!(a, b);
        // 同键时按 pid 升序（确定顺序，不抖动）
        assert_eq!(a[0].pid, 3);
    }
}
