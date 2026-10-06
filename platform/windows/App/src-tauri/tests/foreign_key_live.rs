//! 真库端到端：**外键元数据与跳转**（FR-DATA-06）
//!
//! 口径：① 从服务端读回的外键定义**真能解析**成边（实验库 orders.account_id → accounts.id）；
//! ② 两个方向都有目标；③ 生成的跳转 SQL **真能跑**并取回预期的行；
//! ④ 无关列**没有目标**（需求原文的验收点：没目标就不给入口）。

use doyah_studio_shell::postgres::{ConnectParams, PgSession};

fn lab_params() -> Option<ConnectParams> {
    if std::env::var("DOYAH_LAB").ok().as_deref() != Some("1") {
        eprintln!("跳过：未设 DOYAH_LAB=1（本用例连本机专用实验集群 127.0.0.1:5433 / trust）");
        return None;
    }
    Some(ConnectParams {
        host: std::env::var("DOYAH_LAB_HOST").unwrap_or_else(|_| "127.0.0.1".into()),
        port: std::env::var("DOYAH_LAB_PORT").ok().and_then(|p| p.parse().ok()).unwrap_or(5433),
        database: std::env::var("DOYAH_LAB_DB").unwrap_or_else(|_| "doyah_lab".into()),
        user: std::env::var("DOYAH_LAB_USER").unwrap_or_else(|_| "doyah".into()),
        password: None,
        ssl_mode: Some("disable".into()),
    })
}

#[tokio::test]
async fn foreign_key_edges_parse_and_navigate_on_the_lab() {
    let Some(params) = lab_params() else { return };
    let session = PgSession::connect(&params).await.expect("应当连上实验库");

    // ① 读外键元数据（与命令层同一条 SQL）
    let sql = "SELECT c.conname, c.contype::text, pg_get_constraintdef(c.oid), \
               t.relname, n.nspname \
               FROM pg_constraint c \
               JOIN pg_class t ON t.oid = c.conrelid \
               JOIN pg_namespace n ON n.oid = t.relnamespace \
               WHERE c.contype = 'f' AND n.nspname NOT IN ('pg_catalog', 'information_schema') \
               ORDER BY n.nspname, t.relname, c.conname";
    let raw = session.run(sql, 1000).await.expect("读外键元数据应当成功");
    assert!(!raw.rows.is_empty(), "实验库里应当至少有一条外键：{sql}");

    let mut edges = Vec::new();
    for row in &raw.rows {
        let constraint = row[0].clone();
        let kind = row[1].clone().unwrap_or_default();
        let definition = row[2].clone().unwrap_or_default();
        let table = row[3].clone().unwrap_or_default();
        let schema = row[4].clone();
        if let Some(edge) = doyah_studio_db::foreign_key::parse_edge(
            constraint.as_deref(),
            &kind,
            &definition,
            &table,
            schema.as_deref(),
            schema.as_deref(),
        ) {
            edges.push(edge);
        }
    }
    assert!(
        edges.iter().any(|e| e.from_table == "orders" && e.to_table == "accounts"),
        "应当解析出 orders → accounts 这条：{edges:?}"
    );

    // ② 正向：orders.account_id → accounts.id
    let forward = doyah_studio_db::foreign_key::options("orders", "account_id", &edges, Some("app"));
    assert_eq!(forward.len(), 1, "{forward:?}");
    assert_eq!(forward[0].target_table, "accounts");

    // ③ 生成的跳转 SQL 真跑：拿第 1 条订单的 account_id，跳过去应当恰好 1 行、id 对得上
    let one = session
        .run("SELECT account_id FROM app.orders ORDER BY id LIMIT 1", 10)
        .await
        .expect("取一行订单应当成功");
    let account_id = one.rows[0][0].clone().unwrap_or_default();
    let jump = doyah_studio_db::foreign_key::query(&forward[0], &account_id, "int4", 200);
    let jumped = session.run(&jump, 100).await.expect("跳转查询应当能跑");
    assert_eq!(jumped.rows.len(), 1, "按主键跳到被引用表应当恰好 1 行：{jump}");
    assert_eq!(
        jumped.rows[0][0].clone().unwrap_or_default(),
        account_id,
        "跳过去的那一行 id 应当等于订单里的 account_id"
    );

    // ④ 反向：accounts.id ← orders.account_id
    let reverse = doyah_studio_db::foreign_key::options("accounts", "id", &edges, Some("app"));
    assert_eq!(reverse.len(), 1, "{reverse:?}");
    let back = doyah_studio_db::foreign_key::query(&reverse[0], &account_id, "int4", 200);
    let back_rows = session.run(&back, 100).await.expect("反向查询应当能跑");
    assert!(!back_rows.rows.is_empty(), "被引用的账号应当有订单：{back}");
    // 每一行的 account_id 都等于它
    assert!(
        back_rows
            .rows
            .iter()
            .all(|r| r[1].clone().unwrap_or_default() == account_id),
        "反向取回的行都该指向同一账号"
    );

    // ⑤ 无关列**没有目标**（没目标就不给入口）
    assert!(doyah_studio_db::foreign_key::options("orders", "sku", &edges, Some("app")).is_empty());
}
