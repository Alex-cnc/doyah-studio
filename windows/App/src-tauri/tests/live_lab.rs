//! **真库链路**的端到端判据（Windows 侧）
//!
//! 口径（§8.5.3 的等价物 + 本侧版本计划的"出口"第 1 条）：
//! **主链要在真库上真的跑一遍** —— 不拿合成数据冒充"已跑通"。
//!
//! 跑法：设 `DOYAH_LAB=1` 时启用（连本机专用实验集群：端口 5433 / trust 认证）；
//! 没设就**跳过并说明为什么**（跳过不是通过 —— 与闸门协议一致）。
//! 实验库不属于产品：它是我自己起的测试集群，不动用户现有那台 PostgreSQL。

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
async fn main_chain_connect_tables_query_on_real_db() {
    let Some(params) = lab_params() else { return };
    let session = PgSession::connect(&params).await.expect("应当连上实验库");

    // ① 服务端自述：把"连到了哪儿"如实报出来
    let info = session.info();
    assert_eq!(info.database, "doyah_lab");
    assert_eq!(info.user, "doyah");
    assert!(info.version.contains("PostgreSQL"), "版本串：{}", info.version);

    // ② 对象树：夹具里的两张表必须在
    let tables = session.tables().await.expect("列对象应当成功");
    let names: Vec<String> = tables
        .iter()
        .filter(|t| t.schema == "app")
        .map(|t| t.name.clone())
        .collect();
    assert!(names.contains(&"accounts".to_string()), "实际：{names:?}");
    assert!(names.contains(&"orders".to_string()), "实际：{names:?}");

    // ③ 查询：真数据出得来，列名与行数对得上
    let result = session
        .run("select id, name, balance from app.accounts order by id limit 5", 100)
        .await
        .expect("查询应当成功");
    assert_eq!(result.columns, vec!["id", "name", "balance"]);
    assert_eq!(result.rows.len(), 5);
    assert_eq!(result.rows[0][1].as_deref(), Some("user-1"));
    assert!(!result.truncated);

    // ④ 上限是**真上限**：收够就停止再取 ⇒ 行数如实、截断如实标
    let cut = session
        .run("select id from app.accounts order by id", 2)
        .await
        .expect("查询应当成功");
    assert_eq!(cut.rows.len(), 2);
    assert!(cut.truncated, "超过上限必须如实报截断");
    assert_eq!(cut.returned, 2, "收够上限即停 ⇒ 行数就是上限（不是服务端总行数）");

    // ⑤ 非查询语句：拿影响行数，没有结果集
    let dml = session
        .run("update app.orders set note = note where id <= 3", 100)
        .await
        .expect("写语句应当成功");
    assert!(dml.columns.is_empty());
    assert_eq!(dml.affected, Some(3));

    // ⑥ 服务端错误：原话要端出来，并带 SQLSTATE（不吞成"失败了"）
    let err = session.run("select * from app.no_such_table", 10).await.unwrap_err();
    assert!(
        err.message.contains("no_such_table"),
        "服务端原话应当被端出来：{}",
        err.message
    );
    assert!(err.message.contains("SQLSTATE 42P01"), "应当带 SQLSTATE：{}", err.message);
    assert!(!err.hint.is_empty(), "失败必须给一句可读的提示");

    // ⑦ 自检读数
    let probe = session.probe().await.expect("自检应当成功");
    assert_eq!(probe.select_one.as_deref(), Some("1"));
    assert!(probe.table_count >= 2);
    assert!(probe.schemas.contains(&"app".to_string()), "{:?}", probe.schemas);
}

#[tokio::test]
async fn unreachable_server_reports_readable_reason() {
    let mut params = lab_params().unwrap_or(ConnectParams {
        host: "127.0.0.1".into(),
        port: 5433,
        database: "doyah_lab".into(),
        user: "doyah".into(),
        password: None,
        ssl_mode: Some("disable".into()),
    });
    // 指到一个没人听的端口：失败必须带可读原因与提示（这条不依赖实验库在不在）
    params.port = 59999;
    let failure = PgSession::connect(&params).await.err().expect("应当失败");
    assert!(!failure.message.is_empty());
    assert!(!failure.hint.is_empty());
}
