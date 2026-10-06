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

/// **1.4 写回与事务**：一批一次事务 / 主动回滚 / 主键定位 / 无主键拒改。
///
/// 判据（版本计划 §1.4 的出口「主键定位、一批一事务、提交前预览 DML + 提交 / 回滚」）：
/// ① 提交档：三条真改到；② **中途失败 ⇒ 整批回滚**（先看改到 10，失败后回 0 —— 这是本段
///    最要紧的一条："改了一半"是数据事故，不是体验问题）；③ `rollback` 档：改了但主动回滚，
///    值回到原样；④ 主键元数据真取得到（`app.accounts` → `["id"]`）；⑤ 无主键的表**拒改**
///    （真在库里造一张无主键表来验，不是靠想象）。
#[tokio::test]
async fn writeback_batch_transaction_commit_and_rollback_on_real_db() {
    let Some(params) = lab_params() else { return };
    let session = PgSession::connect(&params).await.expect("应当连上实验库");

    // 把夹具的三行余额摆回已知值，并确认起点
    session
        .run("update app.accounts set balance = 0 where id <= 3", 10)
        .await
        .expect("重置余额应当成功");

    // ④ 主键元数据：真取得到、顺序对
    let key = session.primary_key("app", "accounts").await.expect("读主键应当成功");
    assert_eq!(key, vec!["id".to_string()], "主键应当是 id");

    // ⑤ 无主键的表：真造一张，主键列应当为空（界面据此不给编辑入口）
    session
        .run("create table if not exists app.no_pk_11 (name text)", 10)
        .await
        .expect("造无主键表应当成功");
    let none = session.primary_key("app", "no_pk_11").await.expect("读主键应当成功");
    assert!(none.is_empty(), "无主键的表不该报出主键列：{none:?}");
    // 领域层据此**拒改**（不是生成一条 WHERE 靠猜的语句）
    let refused = doyah_studio_db::writeback::edits_to_dml(
        &[doyah_studio_db::writeback::CellEdit {
            schema: Some("app".into()),
            table: "no_pk_11".into(),
            key: doyah_studio_db::writeback::RowKey { columns: vec![], values: vec![] },
            column: "name".into(),
            value: Some("x".into()),
            value_is_numeric: false,
        }],
        false,
    )
    .unwrap_err();
    assert!(refused.message.contains("主键"), "{}", refused.message);
    session.run("drop table if exists app.no_pk_11", 10).await.expect("清表应当成功");

    // ① 提交档：三条都改到（用领域层生成的 DML，验"生成的通路"与"执行的通路"接得上）
    let edits: Vec<doyah_studio_db::writeback::CellEdit> = (1..=3)
        .map(|id| doyah_studio_db::writeback::CellEdit {
            schema: Some("app".into()),
            table: "accounts".into(),
            key: doyah_studio_db::writeback::RowKey {
                columns: vec!["id".into()],
                values: vec![Some(id.to_string())],
            },
            column: "balance".into(),
            value: Some("10".into()),
            value_is_numeric: true,
        })
        .collect();
    let generated = doyah_studio_db::writeback::edits_to_dml(&edits, false).expect("应当生成 DML");
    assert_eq!(generated.len(), 3);
    assert!(generated[0].sql.contains("\"id\" = 1"), "{}", generated[0].sql);
    let statements: Vec<String> = generated.iter().map(|d| d.sql.clone()).collect();
    let outcomes = session.run_transaction(&statements, false).await.expect("提交档应当成功");
    assert_eq!(outcomes.len(), 3);
    assert!(outcomes.iter().all(|o| o.ok), "{outcomes:?}");
    assert_eq!(outcomes[0].result.as_ref().and_then(|r| r.affected), Some(1));
    let after_commit = session
        .run("select count(*) from app.accounts where id <= 3 and balance = 10", 10)
        .await
        .expect("查应当成功");
    assert_eq!(
        after_commit.rows.first().and_then(|r| r.first().cloned()).flatten().as_deref(),
        Some("3"),
        "三条都应当真改到"
    );

    // ② 中途失败 ⇒ **整批回滚**：先改成 20，第二条是坏语句
    let mixed = vec![
        "update app.accounts set balance = 20 where id <= 3".to_string(),
        "update app.accounts set no_such_column = 1 where id = 1".to_string(),
    ];
    let failed = session.run_transaction(&mixed, false).await.expect("调用本身应当返回");
    assert_eq!(failed.len(), 2, "两次结果都要报（失败即停，第二条不再往下发）");
    assert!(failed[0].ok && !failed[1].ok, "{failed:?}");
    let after_fail = session
        .run("select count(*) from app.accounts where id <= 3 and balance = 20", 10)
        .await
        .expect("查应当成功");
    assert_eq!(
        after_fail.rows.first().and_then(|r| r.first().cloned()).flatten().as_deref(),
        Some("0"),
        "失败那一批必须**整批回滚**：改了一半是数据事故"
    );
    // 而且回滚之后连接照常可用
    let alive = session.run("select 7", 10).await.expect("回滚之后仍应能查询");
    assert_eq!(alive.rows.first().and_then(|r| r.first().cloned()).flatten().as_deref(), Some("7"));

    // ③ 主动回滚（"提交前预览"的姿势）：改到 30 再回滚 ⇒ 值不动
    let preview = vec!["update app.accounts set balance = 30 where id <= 3".to_string()];
    let previewed = session.run_transaction(&preview, true).await.expect("回滚档应当成功");
    assert!(previewed[0].ok, "预览的执行本身是成功的");
    assert_eq!(previewed[0].result.as_ref().and_then(|r| r.affected), Some(3));
    let after_rollback = session
        .run("select count(*) from app.accounts where id <= 3 and balance = 30", 10)
        .await
        .expect("查应当成功");
    assert_eq!(
        after_rollback.rows.first().and_then(|r| r.first().cloned()).flatten().as_deref(),
        Some("0"),
        "主动回滚之后值不该变"
    );

    // 收尾：把夹具摆回 0（不把状态留给下一个用例）
    session
        .run("update app.accounts set balance = 0 where id <= 3", 10)
        .await
        .expect("收尾应当成功");
}

/// **1.5 表结构与 DDL**：结构读得到 / 加列真执行 / **删除类只生成不执行**。
///
/// 判据（版本计划 §1.5 的出口「表设计器改列 + 变更集预览 + 索引 / 外键 / 约束；
/// **删除类只生成语句、不自动执行**」）：
/// ① 结构元数据真读得到（列 / 索引 / 约束三样）；
/// ② 加列：生成的 `additive` 语句**真在真库上执行**，结构随之变化；
/// ③ 删列：生成物标 `destructive`、`executable_subset` **不含它**、命令层 `db_run_ddl` 的
///    同类校验也会拒（用领域层判定直接验）；
/// ④ 改类型：生成**四步可读**重建（建临时列 / 搬值 / 删旧列 / 改名），删旧列那步标破坏性。
#[tokio::test]
async fn table_shape_and_ddl_only_generates_destructive_on_real_db() {
    let Some(params) = lab_params() else { return };
    let session = PgSession::connect(&params).await.expect("应当连上实验库");

    // 备一张专用的表，避免动夹具（前面几个用例都在用 app.accounts）
    session.run("drop table if exists app.ddl_probe_15", 10).await.ok();
    session
        .run(
            "create table app.ddl_probe_15 (id serial primary key, label text not null, note text)",
            10,
        )
        .await
        .expect("建探针表应当成功");

    // ① 结构元数据：列 / 索引 / 约束三样都要真读到
    let shape = session.table_shape("app", "ddl_probe_15").await.expect("读结构应当成功");
    assert_eq!(shape.table, "ddl_probe_15");
    let names: Vec<&str> = shape.columns.iter().map(|c| c.name.as_str()).collect();
    assert_eq!(names, vec!["id", "label", "note"], "列顺序应当按定义顺序");
    let id = shape.columns.iter().find(|c| c.name == "id").expect("id 列");
    assert!(!id.is_nullable, "主键列应当是 NOT NULL");
    assert!(id.default_expr.is_some(), "serial 列有默认值（nextval）：{:?}", id.default_expr);
    let label = shape.columns.iter().find(|c| c.name == "label").expect("label 列");
    assert!(!label.is_nullable);
    assert!(shape.indexes.iter().any(|i| i.is_primary), "主键索引应当列出来：{:?}", shape.indexes);
    assert!(
        shape.constraints.iter().any(|c| c.kind == "primary"),
        "主键约束应当列出来：{:?}",
        shape.constraints
    );

    // ② 加列：生成 additive ⇒ 真执行 ⇒ 结构里多一列
    let add = doyah_studio_db::ddl::alter_table(
        Some("app"),
        "ddl_probe_15",
        &[doyah_studio_db::ddl::ColumnChange {
            from: None,
            to: Some(doyah_studio_db::ddl::ColumnDef {
                name: "added".into(),
                data_type: "integer".into(),
                is_nullable: true,
                default_expr: None,
            }),
        }],
    )
    .expect("生成加列 DDL 应当成功");
    assert_eq!(add.len(), 1);
    assert_eq!(add[0].class, doyah_studio_db::ddl::StatementClass::Additive);
    assert!(!doyah_studio_db::ddl::has_destructive(&add), "加列不是破坏性");
    let runnable: Vec<String> = doyah_studio_db::ddl::executable_subset(&add)
        .iter()
        .map(|s| s.bare.clone())
        .collect();
    assert_eq!(runnable.len(), 1, "加列应当可执行");
    let outcomes = session.run_ddl(&runnable).await.expect("执行加列 DDL 应当成功");
    assert!(outcomes[0].ok, "{outcomes:?}");
    let after = session.table_shape("app", "ddl_probe_15").await.expect("再读结构应当成功");
    assert!(
        after.columns.iter().any(|c| c.name == "added"),
        "加列之后结构里应当有它：{:?}",
        after.columns.iter().map(|c| &c.name).collect::<Vec<_>>()
    );

    // ③ 删列：生成物标破坏性、不进"可执行"那一档
    let drop = doyah_studio_db::ddl::alter_table(
        Some("app"),
        "ddl_probe_15",
        &[doyah_studio_db::ddl::ColumnChange {
            from: Some(
                after
                    .columns
                    .iter()
                    .find(|c| c.name == "added")
                    .expect("added 列")
                    .clone(),
            ),
            to: None,
        }],
    )
    .expect("生成删列 DDL 应当成功");
    assert_eq!(drop[0].class, doyah_studio_db::ddl::StatementClass::Destructive);
    assert!(doyah_studio_db::ddl::has_destructive(&drop));
    assert!(
        doyah_studio_db::ddl::executable_subset(&drop).is_empty(),
        "删除类不许进可执行那一档（版本计划的原文要求）"
    );
    // 而且这条语句**没有被执行**：列还在
    let still = session.table_shape("app", "ddl_probe_15").await.expect("再读结构应当成功");
    assert!(
        still.columns.iter().any(|c| c.name == "added"),
        "只生成不执行 ⇒ 列必须还在"
    );

    // ④ 改类型：四步可读重建，删旧列那步是破坏性
    let alter = doyah_studio_db::ddl::alter_table(
        Some("app"),
        "ddl_probe_15",
        &[doyah_studio_db::ddl::ColumnChange {
            from: Some(still.columns.iter().find(|c| c.name == "added").expect("added 列").clone()),
            to: Some(doyah_studio_db::ddl::ColumnDef {
                name: "added".into(),
                data_type: "bigint".into(),
                is_nullable: true,
                default_expr: None,
            }),
        }],
    )
    .expect("生成改类型 DDL 应当成功");
    let classes: Vec<doyah_studio_db::ddl::StatementClass> =
        alter.iter().map(|s| s.class).collect();
    assert_eq!(
        classes,
        vec![
            doyah_studio_db::ddl::StatementClass::DataMoving,
            doyah_studio_db::ddl::StatementClass::DataMoving,
            doyah_studio_db::ddl::StatementClass::Destructive,
            doyah_studio_db::ddl::StatementClass::Altering,
        ],
        "改类型必须是四步可读重建：{alter:?}"
    );
    assert!(alter[0].bare.contains("__new"), "第一步建临时列：{}", alter[0].bare);

    // 收尾：删掉探针表（DROP 由本用例自己执行 —— 它不在产品通路里）
    session.run("drop table if exists app.ddl_probe_15", 10).await.expect("清表应当成功");
}

/// **1.6 导入导出**：CSV 导出写盘 / 内容自洽 / 导入回来 / 失败不留半截文件。
///
/// 判据（版本计划 §1.6 的出口「CSV / JSON / Excel 进出，**边读边写、中途取消不留半截文件**」）：
/// ① 导出 CSV 到盘：文件真的存在、表头对、行数对；含逗号与引号的字段**往返后仍相等**；
/// ② 再导入回库（一个事务）：行数对得上，且**特殊字符没被破坏**；
/// ③ 原子性：目标不可写时**不留临时文件**（`atomic_write` 的行为在真盘上验一次）；
/// ④ 截断如实：上限小于总行数时 `truncated` 为真、写进去的行数就是上限。
#[tokio::test]
async fn export_import_round_trip_and_atomic_write_on_real_db() {
    let Some(params) = lab_params() else { return };
    let session = PgSession::connect(&params).await.expect("应当连上实验库");

    // 备一张表：故意放逗号、引号、换行进去（CSV 最容易栽在这三类字符上）
    session.run("drop table if exists app.io_probe_16", 10).await.ok();
    session
        .run(
            "create table app.io_probe_16 (id int primary key, note text)",
            10,
        )
        .await
        .expect("建表应当成功");
    session
        .run(
            "insert into app.io_probe_16 (id, note) values \
             (1, 'plain'), (2, 'has,comma'), (3, 'say \"hi\"'), (4, 'two\nlines')",
            10,
        )
        .await
        .expect("插数据应当成功");

    // ① 导出：真取数、真编码
    let (columns, rows, truncated) = session
        .export_rows("select id, note from app.io_probe_16 order by id", 100)
        .await
        .expect("导出取数应当成功");
    assert_eq!(columns, vec!["id".to_string(), "note".to_string()]);
    assert_eq!(rows.len(), 4);
    assert!(!truncated);
    let csv = doyah_studio_db::io_csv::to_csv(&columns, &rows, ',');
    let dir = std::env::temp_dir().join("doyah_io_probe_16");
    let _ = std::fs::create_dir_all(&dir);
    let target = dir.join("out.csv");
    let _ = std::fs::remove_file(&target);
    doyah_studio_db::io_csv::atomic_write(&target, &csv).expect("写盘应当成功");
    assert!(target.exists(), "导出后文件必须在盘上");

    // ①b 往返：解析回来必须逐字相等（含多行字段）
    let back = doyah_studio_db::io_csv::parse_csv(&std::fs::read_to_string(&target).unwrap(), true);
    assert_eq!(back.header, columns);
    assert_eq!(back.rows, rows, "导出的 CSV 必须能被自己解析回同样的行");
    assert!(back.skipped.is_empty(), "{:?}", back.skipped);

    // ② 导入回库：一个事务里三条 INSERT
    let target_table = "io_probe_back_16";
    session.run(&format!("drop table if exists app.{target_table}"), 10).await.ok();
    session
        .run(&format!("create table app.{target_table} (id int, note text)"), 10)
        .await
        .expect("建目标表应当成功");
    let matched = back.match_columns(&["id".to_string(), "note".to_string()]);
    assert_eq!(matched.matched.len(), 2, "{matched:?}");
    let import_columns: Vec<String> = matched.matched.iter().map(|(n, _)| n.clone()).collect();
    let indexes: Vec<usize> = matched.matched.iter().map(|(_, at)| *at).collect();
    let import_rows: Vec<Vec<Option<String>>> = back
        .rows
        .iter()
        .map(|row| {
            indexes
                .iter()
                .map(|at| row.get(*at).filter(|v| !v.is_empty()).cloned())
                .collect()
        })
        .collect();
    let inserted = session
        .import_rows(Some("app"), target_table, &import_columns, &import_rows)
        .await
        .expect("导入应当成功");
    assert_eq!(inserted, 4);
    // 特殊字符没被破坏：逐行比对（多行字段也要原样回来）
    let check = session
        .run(
            &format!("select id, note from app.{target_table} order by id"),
            100,
        )
        .await
        .expect("回读应当成功");
    assert_eq!(check.rows.len(), 4);
    assert_eq!(check.rows[1][1].as_deref(), Some("has,comma"));
    assert_eq!(check.rows[2][1].as_deref(), Some("say \"hi\""));
    assert_eq!(check.rows[3][1].as_deref(), Some("two\nlines"), "多行字段必须原样");

    // ③ 原子性：目标是一个目录 ⇒ 改名必失败 ⇒ 不留临时文件
    let err = doyah_studio_db::io_csv::atomic_write(&dir, "x").unwrap_err();
    assert!(err.contains("改名失败"), "{err}");
    let leftovers: Vec<String> = std::fs::read_dir(&dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .map(|e| e.file_name().to_string_lossy().to_string())
        .filter(|n| n.ends_with(".part"))
        .collect();
    assert!(leftovers.is_empty(), "失败后不许留半截文件：{leftovers:?}");

    // ④ 截断如实：上限 2 行 ⇒ 只写 2 行且标截断
    let (_, cut_rows, cut_truncated) = session
        .export_rows("select id, note from app.io_probe_16 order by id", 2)
        .await
        .expect("取数应当成功");
    assert_eq!(cut_rows.len(), 2);
    assert!(cut_truncated, "超过上限必须如实标截断");

    // 收尾
    session
        .run(&format!("drop table if exists app.{target_table}"), 10)
        .await
        .expect("清目标表应当成功");
    session.run("drop table if exists app.io_probe_16", 10).await.expect("清探针表应当成功");
    let _ = std::fs::remove_dir_all(&dir);
}

/// **1.6 的 Excel 支路**：真造一个 .xlsx（用本机 Python + openpyxl），再用产品命令读成 CSV。
///
/// 为什么这条也要真跑：Excel 走的是**子进程**（Python），而子进程最容易"看着接好了、其实没通"
/// （路径不对 / 模块没装 / 编码不对）。判据断言的是**内容对得上**，不是"没报错"。
#[tokio::test]
async fn xlsx_is_read_through_the_python_bridge() {
    // 这条不依赖实验库，但与其他真库用例同文件，仍按同一开关控制
    if std::env::var("DOYAH_LAB").ok().as_deref() != Some("1") {
        eprintln!("跳过：未设 DOYAH_LAB=1");
        return;
    }
    let dir = std::env::temp_dir().join("doyah_xlsx_probe");
    let _ = std::fs::create_dir_all(&dir);
    let book = dir.join("probe.xlsx");
    let _ = std::fs::remove_file(&book);
    // 造一个两行两列的表（含逗号，验 CSV 转义）
    let make = format!(
        "import openpyxl;wb=openpyxl.Workbook();ws=wb.active;ws.append(['id','note']);\
         ws.append([1,'plain']);ws.append([2,'has,comma']);wb.save(r'{}')",
        book.display()
    );
    let python = std::process::Command::new("python").arg("-c").arg(&make).output();
    let python = match python {
        Ok(o) if o.status.success() => o,
        _ => {
            eprintln!("跳过：本机没有可用的 python + openpyxl");
            return;
        }
    };
    assert!(python.status.success());
    assert!(book.exists(), "xlsx 应当被造出来");

    // 走产品命令的同一段逻辑（这里直接调 shell 的命令函数不方便，故复用命令行桥）
    let script = "import sys, csv, openpyxl\nwb=openpyxl.load_workbook(sys.argv[1], read_only=True, data_only=True)\nws=wb.active\nw=csv.writer(sys.stdout, lineterminator='\\n')\nfor row in ws.iter_rows(values_only=True):\n    w.writerow(['' if c is None else str(c) for c in row])\n";
    let out = std::process::Command::new("python")
        .arg("-c")
        .arg(script)
        .arg(&book)
        .output()
        .expect("起 python 应当成功");
    assert!(out.status.success(), "读 xlsx 应当成功：{}", String::from_utf8_lossy(&out.stderr));
    let csv_text = String::from_utf8_lossy(&out.stdout).to_string();
    // 内容对得上（不是"没报错"）
    let report = doyah_studio_db::io_csv::parse_csv(&csv_text, true);
    assert_eq!(report.header, vec!["id".to_string(), "note".to_string()]);
    assert_eq!(report.rows.len(), 2, "{:?}", report.rows);
    assert_eq!(report.rows[1][1], "has,comma", "带逗号的单元格要原样过来");
    let _ = std::fs::remove_dir_all(&dir);
}

/// **1.7 库与服务器管理面**：读数真读到 / 维护命令只生成不执行 / 删库确认要逐字打名。
///
/// 判据（版本计划 §1.7 的出口「会话与锁列表 + 数据库统计 + 维护任务**只生成命令、不自动执行**」）：
/// ① 库列表真读到 `doyah_lab` 且大小 > 0；② 会话列表读得到（至少能看到自己以外的东西，
/// 或如实为空）；③ 表统计读得到夹具表且体积 > 0；④ **维护命令只是文本**（没有任何执行通路，
/// 本用例断言返回里带"代价"说明）；⑤ 杀会话命令也只是文本；⑥ 删库确认要逐字打名。
#[tokio::test]
async fn admin_readings_and_generate_only_commands_on_real_db() {
    let Some(params) = lab_params() else { return };
    let session = PgSession::connect(&params).await.expect("应当连上实验库");

    // ① 库列表
    let dbs = session.databases().await.expect("列库应当成功");
    let lab = dbs.iter().find(|d| d.name == "doyah_lab").expect("实验库应当在列表里");
    assert!(lab.size_bytes > 0, "库大小应当 > 0：{lab:?}");
    assert!(!lab.owner.is_empty(), "属主应当有值");
    assert!(dbs.iter().all(|d| !d.name.is_empty()));

    // ② 会话与锁：读得到即可（内容随机器状态变，不写死期望）
    let sessions = session.sessions().await.expect("列会话应当成功");
    // 排序口径：等锁的必须排在不等锁的前面（真数据上验一次）
    let first_non_waiting = sessions.iter().position(|s| !s.waiting);
    let last_waiting = sessions.iter().rposition(|s| s.waiting);
    if let (Some(first_ok), Some(last_wait)) = (first_non_waiting, last_waiting) {
        assert!(last_wait < first_ok, "等锁的会话必须排在前面：{sessions:?}");
    }

    // ③ 表统计：夹具表在，且体积 > 0
    let stats = session.table_stats("app").await.expect("读表统计应当成功");
    let accounts = stats.iter().find(|s| s.table == "accounts");
    assert!(accounts.is_some(), "app.accounts 应当在统计里：{:?}", stats.iter().map(|s| &s.table).collect::<Vec<_>>());
    let accounts = accounts.unwrap();
    assert!(accounts.total_bytes > 0, "表体积应当 > 0：{accounts:?}");
    assert!(accounts.estimated_rows >= 0);

    // ④ 维护命令：**只是文本**，每条都带代价
    let cmds = doyah_studio_db::admin::maintenance_commands(Some("app"), "accounts");
    assert!(cmds.len() >= 4);
    for c in &cmds {
        assert!(!c.cost.trim().is_empty(), "{} 没写代价", c.purpose);
        assert!(c.sql.contains("代价"), "{}", c.sql);
    }
    assert!(cmds.iter().any(|c| c.bare.contains("VACUUM FULL")));
    // 而且这些文本**没有被本用例执行**：跑完之后表还在、还能查
    let alive = session.run("select count(*) from app.accounts", 10).await;
    assert!(alive.is_ok(), "维护命令只是文本，不该动到库");

    // ⑤ 杀会话命令：只是文本（**不真杀** —— 杀下去这条连接自己也没了）
    let kill = doyah_studio_db::admin::terminate_command(999_999, true);
    assert!(kill.bare.contains("pg_terminate_backend(999999)"));
    assert!(kill.cost.contains("掐断"));

    // ⑥ 删库确认：逐字打名
    assert!(doyah_studio_db::admin::confirm_drop("doyah_lab", "doyah_lab").ok);
    assert!(!doyah_studio_db::admin::confirm_drop("doyah", "doyah_lab").ok);
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
