//! 真库端到端：**服务端条件浏览**（FR-DATA-02）—— 生成的 SQL 真跑 + 被拒的输入真没到服务端
//!
//! 口径：① 生成的浏览 SQL 直接可执行、LIMIT / ORDER BY 都真的生效；
//! ② 计数语句与对照查询一致；③ **多语句在生成阶段就被拒**（我们手里根本没有可执行的 SQL），
//! 并用"那张表还在"做反证 —— 拒绝不是嘴上说说。

use doyah_studio_shell::postgres::{ConnectParams, PgSession};

fn lab_params() -> Option<ConnectParams> {
    if std::env::var("DOYAH_LAB").ok().as_deref() != Some("1") {
        eprintln!("跳过：未设 DOYAH_LAB=1（本用例连本机专用实验集群 127.0.0.1:5433 / trust）");
        return None;
    }
    Some(ConnectParams {
        host: std::env::var("DOYAH_LAB_HOST").unwrap_or_else(|_| "127.0.0.1".into()),
        port: std::env::var("DOYAH_LAB_PORT")
            .ok()
            .and_then(|p| p.parse().ok())
            .unwrap_or(5433),
        database: std::env::var("DOYAH_LAB_DB").unwrap_or_else(|_| "doyah_lab".into()),
        user: std::env::var("DOYAH_LAB_USER").unwrap_or_else(|_| "doyah".into()),
        password: None,
        ssl_mode: Some("disable".into()),
    })
}

#[tokio::test]
async fn generated_browse_sql_runs_and_refused_input_never_reaches_the_server() {
    let Some(params) = lab_params() else { return };
    let session = PgSession::connect(&params).await.expect("应当连上实验库");

    // ① 生成的浏览 SQL 直接可执行，LIMIT / ORDER BY 真的生效
    let filter = doyah_studio_db::browse::BrowseFilter {
        where_clause: "balance > 10".to_string(),
        order_by: "id DESC".to_string(),
        limit: 3,
        offset: 1,
    };
    let sql = doyah_studio_db::browse::browse("accounts", Some("app"), &filter).expect("应当生成成功");
    assert!(sql.starts_with("SELECT * FROM \"app\".\"accounts\""), "{sql}");
    let result = session.run(&sql, 100).await.expect("生成的 SQL 应当能跑");
    assert_eq!(result.rows.len(), 3, "LIMIT 3 应当恰好回 3 行：{sql}");
    let ids: Vec<i64> = result
        .rows
        .iter()
        .map(|r| r.first().and_then(|c| c.clone()).unwrap_or_default().parse().unwrap_or(0))
        .collect();
    assert!(ids.windows(2).all(|w| w[0] > w[1]), "ORDER BY id DESC 没生效：{ids:?}");

    // ② 计数语句与对照查询一致
    let count_sql = doyah_studio_db::browse::count("accounts", Some("app"), &filter).expect("应当生成成功");
    let counted = session.run(&count_sql, 10).await.expect("计数应当能跑");
    let total: i64 = counted.rows[0][0].clone().unwrap_or_default().parse().unwrap_or(-1);
    let all = session
        .run("SELECT count(*) FROM \"app\".\"accounts\" WHERE balance > 10", 10)
        .await
        .expect("对照查询应当能跑");
    assert_eq!(
        total,
        all.rows[0][0].clone().unwrap_or_default().parse::<i64>().unwrap_or(-2),
        "计数语句与对照查询应当一致"
    );

    // ③ 多语句在**生成阶段**就被拒（手里没有可执行的 SQL），并用"表还在"做反证
    let evil = doyah_studio_db::browse::BrowseFilter {
        where_clause: "balance > 10; DROP TABLE app.orders".to_string(),
        ..Default::default()
    };
    match doyah_studio_db::browse::browse("accounts", Some("app"), &evil) {
        Err(e) => assert_eq!(e.identifier(), "multipleStatements"),
        Ok(sql) => panic!("多语句必须被拒，却生成了：{sql}"),
    }
    let alive = session
        .run("SELECT count(*) FROM app.orders", 10)
        .await
        .expect("orders 表应当还在");
    assert_eq!(
        alive.rows[0][0].clone().unwrap_or_default().parse::<i64>().unwrap_or(0),
        500,
        "被拒的语句不该有任何东西执行过"
    );
}
