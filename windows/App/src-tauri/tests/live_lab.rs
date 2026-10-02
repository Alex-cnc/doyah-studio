//! **真库链路**的端到端判据（Windows 侧）
//!
//! 口径（§8.5.3 的等价物 + 本侧版本计划的"出口"第 1 条）：
//! **主链要在真库上真的跑一遍** —— 不拿合成数据冒充"已跑通"。
//!
//! 跑法：设 `DOYAH_LAB=1` 时启用（连本机专用实验集群：端口 5433 / trust 认证）；
//! 没设就**跳过并说明为什么**（跳过不是通过 —— 与闸门协议一致）。
//! 实验库不属于产品：它是我自己起的测试集群，不动用户现有那台 PostgreSQL。

use doyah_studio_db::tree::ObjectKind;
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
async fn startup_sql_is_sent_one_by_one_and_reported_per_statement() {
    let Some(params) = lab_params() else { return };
    // 三句：一句设 5s、一句设成坏值、一句也是好的 —— 坏的那句**不许吞掉**后面那句
    let statements = vec![
        "SET statement_timeout = '5s'".to_string(),
        "SET statement_timeout = 'not-a-duration'".to_string(),
        "SET search_path = app, public".to_string(),
    ];
    let (session, report) = PgSession::connect_with_startup(&params, &statements)
        .await
        .expect("连接本身应当成功（启动 SQL 失败不阻断连接）");

    // ① 逐条结果：好 / 坏 / 好，顺序与条数都要对
    assert_eq!(report.startup.len(), 3, "{:?}", report.startup);
    assert!(report.startup[0].ok, "第 1 句应当成功");
    assert!(!report.startup[1].ok, "第 2 句是坏值，必须判失败");
    assert!(report.startup[2].ok, "第 3 句不该被第 2 句连累（逐条发、逐条报）");
    let failure = report.startup[1].failure.as_ref().expect("失败必须带原因");
    assert!(!failure.message.is_empty() && !failure.hint.is_empty());

    // ② 生效要不要真？要真：第 1 句的 5s 应当真的设在会话上
    let shown = session
        .run("SHOW statement_timeout", 10)
        .await
        .expect("查会话参数应当成功");
    assert_eq!(
        shown.rows.first().and_then(|r| r.first().cloned()).flatten().as_deref(),
        Some("5s"),
        "第 1 句应当真的生效（{shown:?}）"
    );

    // ③ 第 3 句也真的生效了（坏语句之后的语句照样执行到）
    let path = session.run("SHOW search_path", 10).await.expect("查 search_path 应当成功");
    let text = path.rows.first().and_then(|r| r.first().cloned()).flatten().unwrap_or_default();
    assert!(text.contains("app"), "第 3 句应当真的生效：{text}");

    // ④ 报告里的服务端自述与连接自述一致（同一条连接，不是连了两次）
    assert_eq!(report.info.database, session.info().database);
    assert_eq!(report.info.user, session.info().user);
}

/// **1.1 对象树**：展开一层取一层 —— 第一层只问 schema，展开某个 schema 才问它下面的对象。
///
/// 判据（版本计划 §1.1 的出口「展开一层取一层、点表能出数」）：
/// ① `schemas()` 回得来且含夹具的 `app`；② `relations("app")` 回得来且含两张夹具表；
/// ③ 序列 / 物化视图这类**别的地方会漏**的对象也能在 `pg_class` 那条路上看见（真库造一个再删）；
/// ④ 搜索是纯函数：拿真元数据当输入，按名字与限定名各命中一次。
#[tokio::test]
async fn lazy_object_tree_layer_by_layer_on_real_db() {
    let Some(params) = lab_params() else { return };
    let session = PgSession::connect(&params).await.expect("应当连上实验库");

    // ① 第一层：schema
    let schemas = session.schemas().await.expect("列 schema 应当成功");
    assert!(schemas.contains(&"app".to_string()), "实际：{schemas:?}");
    assert!(
        !schemas.iter().any(|s| s == "pg_catalog" || s == "information_schema"),
        "系统 schema 不该出现在树的第一层：{schemas:?}"
    );

    // ③ 真库造一个序列：`pg_class` 那条路看得见它，`information_schema.tables` 看不见
    session
        .run("create sequence if not exists app.seq_probe_11", 10)
        .await
        .expect("建序列应当成功");
    let layer = session.relations("app").await.expect("列 schema 下的对象应当成功");
    let names: Vec<String> = layer.iter().map(|o| o.name.clone()).collect();
    assert!(names.contains(&"accounts".to_string()), "实际：{names:?}");
    assert!(names.contains(&"orders".to_string()), "实际：{names:?}");
    let seq = layer
        .iter()
        .find(|o| o.name == "seq_probe_11")
        .expect("序列必须能被列出来（改走 pg_class 的原因就是这个）");
    assert_eq!(seq.kind, ObjectKind::Sequence, "序列的种类要如实分类");
    assert!(!seq.kind.can_browse(), "序列取不了数 ⇒ 界面不给「浏览数据」入口");
    session
        .run("drop sequence if exists app.seq_probe_11", 10)
        .await
        .expect("清理序列应当成功");

    // ② 用**第一层的真实返回**当第二层的输入（界面就是这么用的：点开才问）
    let app_layer = session.relations("app").await.expect("再来一次也应当成功");
    assert!(app_layer.iter().all(|o| o.schema == "app"), "第二层只该含这个 schema 的对象");

    // ④ 搜索：真元数据当输入，名字命中与限定名命中各验一次
    //
    // ⚠️ 期望按**真库事实**写，不按想象写：`app` 里除了夹具两张表，还有建表时自动生成的
    // `orders_id_seq`（序列）—— 搜 `ORD` 本来就该命中「表 + 它的序列」两条。
    // 第一次跑这条用例时我按"只命中 orders"写，当场被真库判红（这正是真库判据的价值）。
    let by_name = doyah_studio_db::tree::search(&app_layer, "ORD");
    assert!(
        by_name.iter().any(|h| h.object.name == "orders" && h.matched_on == "name"),
        "orders 必须按对象名命中：{by_name:?}"
    );
    assert!(
        by_name.iter().all(|h| h.object.name.to_lowercase().contains("ord")),
        "命中项的名字里都必须真的含 ord（不许混进不匹配的）：{by_name:?}"
    );
    let by_qualified = doyah_studio_db::tree::search(&app_layer, "app.acc");
    assert!(
        by_qualified.iter().any(|h| h.object.name == "accounts" && h.matched_on == "qualified"),
        "accounts 必须按限定名命中：{by_qualified:?}"
    );
    assert!(
        by_qualified.iter().all(|h| h.matched_on == "qualified" && h.object.schema == "app"),
        "限定名模式下命中项都必须是 app 下的、且依据是限定名：{by_qualified:?}"
    );
    assert!(
        by_qualified.iter().all(|h| h.object.name.to_lowercase().starts_with("acc")
            || h.object.name.to_lowercase().contains("acc")),
        "命中项名字都真的含 acc：{by_qualified:?}"
    );
    // 空查询 = 空结果（界面此时显示树的原貌）
    assert!(doyah_studio_db::tree::search(&app_layer, "  ").is_empty());
}

/// **1.2 SQL 编辑面**：多段执行逐段报告 + **执行中可取消**（取消后连接仍可用）+ EXPLAIN 生成。
///
/// 判据（版本计划 §1.2 的出口「多段语句一次提交、取消后连接仍可用」）：
/// ① 多段提交：三段里第二段坏 ⇒ 逐段结果三条、`ok` 依次 真/假/真（**不是停止后续**，因为默认
///    `stop_on_error` 关掉时要把后面的跑完；这里显式传 false 验"都跑"），各段耗时字段有值；
/// ② 取消：起一条长查询，取消它 ⇒ 该查询以错误收场，而**同一条会话接下来照样能查询**；
/// ③ EXPLAIN：单条能生成、多段被拒（拒绝理由要说清条数）。
#[tokio::test]
async fn sql_editor_batch_cancel_and_explain_on_real_db() {
    let Some(params) = lab_params() else { return };
    let session = PgSession::connect(&params).await.expect("应当连上实验库");

    // ① 多段执行：成 / 败 / 成，逐段报告（不合成一个总结果）
    let batch = session
        .run_batch(
            "select 1 as a; select * from app.no_such_table_12; select 2 as b",
            100,
            false, // 不因一段失败就停 —— 本用例要验"都跑到了"
        )
        .await
        .expect("多段执行本身应当返回结果（段内失败不算调用失败）");
    assert_eq!(batch.len(), 3, "三段都要有各自的报告：{batch:?}");
    assert!(batch[0].ok, "第 1 段应当成功");
    assert!(!batch[1].ok, "第 2 段是坏表名，必须判失败");
    assert!(batch[2].ok, "第 3 段不该被第 2 段连累（逐段执行、逐段报告）");
    assert!(batch[0].result.is_some(), "成功段要带结果集");
    assert!(batch[1].result.is_none(), "失败段不该有结果集");
    let failure = batch[1].failure.as_ref().expect("失败段必须带原因");
    assert!(failure.message.contains("no_such_table_12"), "{}", failure.message);
    assert!(!failure.hint.is_empty());

    // ①b 默认口径是**一段失败就停**：后面的段不该被发出去
    let stopped = session
        .run_batch("select 1; select * from app.no_such_table_13; select 3", 100, true)
        .await
        .expect("应当返回");
    assert_eq!(stopped.len(), 2, "失败即停 ⇒ 只报告到出错那一段：{stopped:?}");
    assert!(stopped[0].ok && !stopped[1].ok);

    // ② 取消：长查询 + 取消 ⇒ 查询失败，但**连接仍可用**
    //
    // 用 `Arc` 把同一条会话借给两个地方：**取消要发给同一条连接**（每条连接有自己的后端 PID
    // 与取消密钥），所以不能另开一条连接来"取消"，那样取消的是别人。
    let session = std::sync::Arc::new(session);
    let sleeper = std::sync::Arc::clone(&session);
    let long = tokio::spawn(async move { sleeper.run("select pg_sleep(30)", 10).await });
    tokio::time::sleep(std::time::Duration::from_millis(600)).await;
    session.cancel().await.expect("发送取消请求应当成功");
    let outcome = tokio::time::timeout(std::time::Duration::from_secs(15), long)
        .await
        .expect("取消后长查询应当很快结束（不是等满 30 秒）")
        .expect("任务本身不该 panic");
    assert!(outcome.is_err(), "被取消的查询应当以错误收场：{outcome:?}");
    // 取消之后连接照常：这条是出口判据点名的
    let after = session
        .run("select 41 + 1 as answer", 10)
        .await
        .expect("取消之后同一条会话仍应能查询");
    assert_eq!(
        after.rows.first().and_then(|r| r.first().cloned()).flatten().as_deref(),
        Some("42")
    );

    // ③ EXPLAIN 生成：单条能生成；多段被拒并说清条数
    let plan = doyah_studio_db::sql::explain("select count(*) from app.accounts", false)
        .expect("单条应当能生成计划");
    assert!(plan.starts_with("EXPLAIN "), "{plan}");
    let rejected = doyah_studio_db::sql::explain("select 1; select 2", false).unwrap_err();
    assert!(rejected.contains('2'), "拒绝理由要说清有几条：{rejected}");
    // 生成出来的计划语句**真能跑**（只生成不执行是界面的姿势；这里要证它本身合法）
    let explained = session.run(&plan, 100).await.expect("生成的计划语句应当能在真库上执行");
    assert!(!explained.rows.is_empty(), "EXPLAIN 应当至少回一行计划：{explained:?}");

    // ④ 高亮分词也在真库往返的路子里验一次（纯计算，但保证与本用例同一套输入没崩）
    let tokens = doyah_studio_db::sql::tokenize(&batch[0].sql);
    assert!(!tokens.is_empty());
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
