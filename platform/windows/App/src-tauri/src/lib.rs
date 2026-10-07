//! Doyah Studio · Windows 侧表示层外壳（Tauri 2）—— 命令层
//!
//! 分工：**命令只做转发**，逻辑全在 `query.rs`（那样才 `cargo test` 判得了；窗口在无人值守里起不来）。
//! 前端命令名与这里的注册项的一致性由 `tests/ipc_contract.rs` 双向判（前端 `invoke` 一个没注册的
//! 名字是**运行时静默失败**，靠人记不住）。

pub mod connections;
pub mod format_tool;
pub mod fs;
pub mod postgres;

mod query;
pub mod search;

pub use connections::{config_from_form, ConnectionStore};
pub use postgres::{
    ConnectParams, ConnectReport, DatabaseInfo, DbFailure, PgSession, ProbeReport, QueryResult,
    ServerInfo, StartupOutcome, StatementOutcome, TableNode, TableShape, TableStats,
    MAX_QUERY_ROWS,
};
pub use query::{DatasetSummary, GridWindowPayload, ViewCache, MAX_WINDOW_ROWS};

use std::sync::{Arc, Mutex};
use tauri::State;
use tokio::sync::Mutex as AsyncMutex;

use doyah_studio_db::db_type::DatabaseType;

/// 外壳状态：视图缓存（数据集 + 排序置换）+ 当前数据库会话。tauri 里跨命令共享的可变状态。
///
/// 数据库槽用 **tokio 的异步互斥锁**（异步命令要跨 await 持锁 ⇒ 标准库那把锁的守卫不是 `Send`）；
/// 命令拿到 `Arc<PgSession>` 后**先放锁再 await**，所以一条慢查询不会把别的命令一起堵住。
pub struct ShellState {
    pub cache: Mutex<ViewCache>,
    /// 当前连接（一次一个；多连接管理是后续段的事）。
    pub db: AsyncMutex<Option<Arc<PgSession>>>,
    /// 连接列表的落盘位置与凭据读写（口令走系统凭据管理器，不进配置文件）。
    pub connections: ConnectionStore,
    /// **当前连接是不是只读**（FR-CONN-17）：写回与危险判定都要看它。
    ///
    /// 为什么用原子布尔而不是塞进会话：只读是**连接级配置**的一部分，而"当前连接"这个槽
    /// 在换连接 / 断开时会变 —— 把它与会话绑在一起容易出现"会话还在、标记没了"的错位。
    pub read_only: std::sync::atomic::AtomicBool,
}

/// 取当前会话；没连上就是一句可读的失败（不 panic、不静默）。
async fn current_session(state: &State<'_, ShellState>) -> Result<Arc<PgSession>, DbFailure> {
    let guard = state.db.lock().await;
    guard.clone().ok_or_else(|| DbFailure {
        message: "尚未连接数据库".to_string(),
        hint: "先连接（连接面板），再执行这一步。".to_string(),
    })
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppInfo {
    pub name: String,
    /// **版本号只有一处真源** = 本 crate 的 `Cargo.toml`（`CARGO_PKG_VERSION`），
    /// 与 `tauri.conf.json` 的 `version` 必须一致（打包产物带的是后者）。
    pub version: String,
    pub platform: String,
    /// `tauri` = 真外壳（Rust 领域层经 IPC 供数）；`browser` = 浏览器旁路（前端 mock）。
    pub backend: &'static str,
}

#[tauri::command]
fn app_info() -> AppInfo {
    AppInfo {
        name: "Doyah Studio".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        platform: std::env::consts::OS.to_string(),
        backend: "tauri",
    }
}

#[tauri::command]
fn dataset_summary(
    state: State<'_, ShellState>,
    rows: usize,
    cols: usize,
    seed: u64,
) -> DatasetSummary {
    // 锁中毒（某个命令 panic）时不让整个界面挂掉：恢复内层继续用，并如实记一笔。
    let mut cache = state
        .cache
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    cache.summary(rows, cols, seed)
}

#[tauri::command]
fn grid_window(
    state: State<'_, ShellState>,
    rows: usize,
    cols: usize,
    seed: u64,
    order_desc: bool,
    start: usize,
    len: usize,
) -> GridWindowPayload {
    let mut cache = state
        .cache
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    cache.window(&query::ViewRequest {
        rows,
        cols,
        seed,
        order_desc,
        start,
        len,
    })
}

// ── 数据库命令（真库链路；模型来自领域层 Db，驱动只在本层）─────────────────────────────

/// 连接（**一次一个**：多连接管理是后续段的事）。成功后把会话留在状态里。
///
/// `startup_sql` = 连接后自动执行的语句（FR-CONN-17，**已由领域层逐条切好**）。
/// 某条失败**不阻断连接** —— 逐条结果在返回值里如实摆出来（见 `ConnectReport` 的口径说明）。
#[tauri::command]
async fn db_connect(
    state: State<'_, ShellState>,
    params: ConnectParams,
    startup_sql: Option<Vec<String>>,
    read_only: Option<bool>,
) -> Result<ConnectReport, DbFailure> {
    // 先把旧会话放掉（换连接 = 断旧连新），**先放锁再 await**，别把锁带过 await
    {
        let mut slot = state.db.lock().await;
        *slot = None;
    }
    // 只读标记随连接一起设：换连接时**不保留上一条的标记**（否则"上一条只读"会意外管住新连接）
    state.read_only.store(
        read_only.unwrap_or(false),
        std::sync::atomic::Ordering::Relaxed,
    );
    let statements = startup_sql.unwrap_or_default();
    let (session, report) = PgSession::connect_with_startup(&params, &statements).await?;
    let mut slot = state.db.lock().await;
    *slot = Some(Arc::new(session));
    Ok(report)
}

/// 断开（把会话丢掉；驱动任务随之结束）。
#[tauri::command]
async fn db_disconnect(state: State<'_, ShellState>) -> Result<bool, DbFailure> {
    let mut slot = state.db.lock().await;
    *slot = None;
    Ok(true)
}

/// 列对象树（表 / 视图）。
#[tauri::command]
async fn db_tables(state: State<'_, ShellState>) -> Result<Vec<TableNode>, DbFailure> {
    let session = current_session(&state).await?;
    session.tables().await
}

// ── 对象树（1.1：展开一层取一层；搜索是纯函数在领域层）────────────────────────────────

/// 树的第一层：能看到的 schema。
///
/// 返回 [`doyah_studio_db::tree::CappedRows`]（行 + 截断标记 + 上限）—— 元数据查询
/// 一律走行数上限保护（FR-META-07：10,000 行）；到顶时界面如实说"可能不完整"。
#[tauri::command]
async fn db_schemas(
    state: State<'_, ShellState>,
) -> Result<doyah_studio_db::tree::CappedRows<String>, DbFailure> {
    let session = current_session(&state).await?;
    session.schemas().await
}

/// 第二层：某个 schema 下的对象（**展开时才问**，不在连接时一次拉光）。
///
/// 同样带上限保护（FR-META-07）：一个 schema 下几万张表是可能的。
#[tauri::command]
async fn db_relations(
    state: State<'_, ShellState>,
    schema: String,
) -> Result<doyah_studio_db::tree::CappedRows<doyah_studio_db::tree::ObjectNode>, DbFailure> {
    let session = current_session(&state).await?;
    session.relations(&schema).await
}

/// 对象搜索：**纯函数**在领域层（`tree::search`），本命令只把已加载的那一层递过去。
///
/// 为什么搜索在这一层做而不是下发 SQL：搜索的对象是**界面上已经看见的那些**，
/// 与树里显示的东西必然一致；下发 `LIKE` 查询会引入"搜到了树里却没有"的错位。
#[tauri::command]
fn search_objects(
    items: Vec<doyah_studio_db::tree::ObjectNode>,
    query: String,
) -> Vec<doyah_studio_db::tree::SearchHit> {
    doyah_studio_db::tree::search(&items, &query)
}

/// 第三层：一个 schema 下**一批表 / 视图的列**（含数据类型原文）。
///
/// 为什么收成「一批表」而不是「一张表」：一层里的展开动作一次问齐 —— 一张表一次是
/// 最省事的写法，但界面上「全部展开」就成了 N+1；接口形状先钉住，调用方想 N+1 也难。
#[tauri::command]
async fn db_columns(
    state: State<'_, ShellState>,
    schema: String,
    tables: Vec<String>,
) -> Result<Vec<doyah_studio_db::tree::TableColumns>, DbFailure> {
    let session = current_session(&state).await?;
    session.columns(&schema, &tables).await
}

/// 跑一条 SQL。
#[tauri::command]
async fn db_query(state: State<'_, ShellState>, sql: String) -> Result<QueryResult, DbFailure> {
    let session = current_session(&state).await?;
    session.run(&sql, MAX_QUERY_ROWS).await
}

/// 自检读数（连上、能问出一行、能列出表）。
#[tauri::command]
async fn db_probe(state: State<'_, ShellState>) -> Result<ProbeReport, DbFailure> {
    let session = current_session(&state).await?;
    session.probe().await
}

// ── 连接列表命令（配置落盘 + 口令进系统凭据管理器；口令不进配置文件）────────────────────

/// 保存的连接列表（首次使用返回空表，不是错误）。
#[tauri::command]
fn connections_list(
    state: State<'_, ShellState>,
) -> Result<Vec<doyah_studio_db::config::ConnectionConfig>, DbFailure> {
    state.connections.load()
}

/// 记下当前连接（`remember_password` 为真时把口令写进系统凭据管理器；**口令绝不进配置文件**）。
///
/// 口令框的三档语义在 `connections::password_edit`（FR-CONN-08）：**留空 = 保持原口令不变**，
/// 显式空串 = 清空，非空 = 写入。命令层只是照它执行，不自己再判一遍。
#[tauri::command]
fn connection_save(
    state: State<'_, ShellState>,
    id: String,
    name: String,
    db_type: Option<String>,
    host: String,
    port: u16,
    database: String,
    user: String,
    ssl_mode: Option<String>,
    is_read_only: bool,
    password: Option<String>,
    remember_password: bool,
) -> Result<Vec<doyah_studio_db::config::ConnectionConfig>, DbFailure> {
    // 认不出的引擎走 Postgres 回退（表单给的是登记过的字面量；回退值写在**这一处**）
    let kind = db_type
        .as_deref()
        .and_then(DatabaseType::from_raw)
        .unwrap_or(DatabaseType::Postgresql);
    let config = config_from_form(
        &id,
        &name,
        kind,
        &host,
        port,
        &database,
        &user,
        ssl_mode.as_deref(),
        is_read_only,
    );
    if !config.is_valid() {
        return Err(DbFailure {
            message: "连接信息不完整：名字 / 主机 / 用户名不能为空，端口要在 1~65535".to_string(),
            hint: "补齐后再保存。".to_string(),
        });
    }
    match connections::password_edit(password.as_deref()) {
        connections::PasswordEdit::Set(secret) => {
            if remember_password {
                connections::remember_password(&id, &user, &secret)?;
            }
        }
        // 显式清空：把凭据也清掉（留一条孤儿口令是隐患）
        connections::PasswordEdit::Clear => {
            let _ = connections::forget_password(&id);
        }
        // 留空：一字不动（FR-CONN-08）
        connections::PasswordEdit::Keep => {}
    }
    state.connections.upsert(config)
}

/// **表单逐项校验**（FR-CONN-06）：规则只有一份（领域层 `config::validate_form`），
/// 本命令只把"哪一项不合法、为什么"递回界面 —— 界面据此禁用「连接 / 保存」并逐项提示。
///
/// 端口按**文本**校验（`0` / `65536` / 非数字都当场拒）：这是需求原文点名的那一步
/// 「端口先单独解析再按 1–65535 校验，防止默认端口把非法输入洗白」。
#[tauri::command]
fn connection_validate(
    name: String,
    host: String,
    port: String,
    username: String,
) -> Vec<doyah_studio_db::config::FieldProblem> {
    doyah_studio_db::config::validate_form(&name, &host, &port, &username)
}

/// **换引擎时的那几项默认值**（FR-CONN-02 的类型联动）：端口 / SSL / 默认 schema。
///
/// 为什么要有这条命令：默认值**挂在类型上**（领域层 `db_type`），表单不许自己再写一份
/// （两处各写一份 = 迟早一个改了另一个没改）。
#[tauri::command]
fn connection_type_defaults(db_type: String) -> ConnectionTypeDefaults {
    let kind = DatabaseType::from_raw(&db_type).unwrap_or(DatabaseType::Postgresql);
    ConnectionTypeDefaults {
        db_type: kind.raw_value().to_string(),
        port: kind.default_port(),
        ssl_mode: kind.default_ssl_mode().raw_value().to_string(),
        schema: kind.default_schema().map(|value| value.to_string()),
    }
}

/// 类型联动的答案（界面直接照着填那三格）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectionTypeDefaults {
    pub db_type: String,
    pub port: u16,
    pub ssl_mode: String,
    pub schema: Option<String>,
}

/// **从连接 URL 导入**（FR-CONN-19）：解析一行连接串，把各字段回给界面填表。
///
/// 两条纪律（照契约）：
/// ① URL 里带的**口令只回给这一次调用**（界面把它填进口令框，保存时才落凭据存储）——
///    它**不进配置、不进导出件**；
/// ② 认不出的查询参数**逐条列出来**（不静默丢：静默会让人以为"设置生效了"）。
#[tauri::command]
fn connection_import_url(
    url: String,
    name: Option<String>,
    id: String,
) -> Result<ImportedUrl, DbFailure> {
    doyah_studio_db::url::parse(&url, name.as_deref(), &id)
        .map(|imported| ImportedUrl {
            db_type: imported.configuration.db_type.raw_value().to_string(),
            host: imported.configuration.host.clone(),
            port: imported.configuration.port,
            database: imported.configuration.database.clone(),
            user: imported.configuration.username.clone(),
            ssl_mode: imported.configuration.ssl_mode.raw_value().to_string(),
            name: imported.configuration.name.clone(),
            password: imported.password,
            ignored_parameters: imported.ignored_parameters,
        })
        .map_err(|error| DbFailure {
            message: error.to_string(),
            hint:
                "支持的写法：postgres://user@host:port/db?sslmode=…（口令可带，但不会写进配置）。"
                    .to_string(),
        })
}

/// URL 导入的答案（口令**只在这一条回执里**，不进任何落盘面）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportedUrl {
    pub db_type: String,
    pub host: String,
    pub port: u16,
    pub database: String,
    pub user: String,
    pub ssl_mode: String,
    pub name: String,
    pub password: Option<String>,
    pub ignored_parameters: Vec<String>,
}

/// 删一条连接（**同时清掉它的凭据**）。
#[tauri::command]
fn connection_delete(
    state: State<'_, ShellState>,
    id: String,
) -> Result<Vec<doyah_studio_db::config::ConnectionConfig>, DbFailure> {
    state.connections.remove(&id)
}

/// 生成**服务端条件浏览**的 SQL（FR-DATA-02；**只生成、不执行**）。
///
/// 契约要点（与对侧 `Core/RowBrowsing.swift` 同一口径）：
/// ① 片段**原样下发**（用户在自己库上写 SQL，本层不做"聪明"改写）；
/// ② 出现分号（像不止一条语句）⇒ **拒绝并说清**，不会因为点了个"浏览"就把后面的语句执行掉；
/// ③ 排序写两处 ⇒ 报冲突（无法判断以哪个为准）。
/// 返回 SQL 供界面**预览**再执行 —— 预览与执行同一份输入、只解析一次。
#[tauri::command]
fn browse_sql(
    table: String,
    schema: Option<String>,
    where_clause: Option<String>,
    order_by: Option<String>,
    limit: Option<i64>,
    offset: Option<i64>,
    count_only: Option<bool>,
) -> Result<String, DbFailure> {
    let filter = doyah_studio_db::browse::BrowseFilter {
        where_clause: where_clause.unwrap_or_default(),
        order_by: order_by.unwrap_or_default(),
        limit: limit.unwrap_or(200),
        offset: offset.unwrap_or(0),
    };
    let built = if count_only.unwrap_or(false) {
        doyah_studio_db::browse::count(&table, schema.as_deref(), &filter)
    } else {
        doyah_studio_db::browse::browse(&table, schema.as_deref(), &filter)
    };
    built.map_err(|e: doyah_studio_db::browse::BrowseError| DbFailure {
        message: e.message().to_string(),
        hint: format!(
            "（判定标识：{}）改好条件再试 —— 这里只接受单条表达式。",
            e.identifier()
        ),
    })
}

// ── SQL 编辑面（1.2：多段执行 / 执行中可取消 / EXPLAIN）──────────────────────────────────

/// **多段执行**：一次提交多条，**逐段执行、逐段报告**（哪句成、哪句败、各耗时多少）。
#[tauri::command]
async fn db_run_batch(
    state: State<'_, ShellState>,
    sql: String,
    stop_on_error: Option<bool>,
) -> Result<Vec<StatementOutcome>, DbFailure> {
    let session = current_session(&state).await?;
    session
        .run_batch(&sql, MAX_QUERY_ROWS, stop_on_error.unwrap_or(true))
        .await
}

/// **取消当前查询**（1.2 段「执行中可取消」）。
///
/// 口径：这是**往服务端发的取消请求**，不是本地"不等了"。本地丢弃 future 不会让服务端停下。
/// 取消之后连接仍可用（协议上是 QueryCanceled），出口判据点名的就是这条。
#[tauri::command]
async fn db_cancel(state: State<'_, ShellState>) -> Result<bool, DbFailure> {
    let session = current_session(&state).await?;
    session.cancel().await?;
    Ok(true)
}

/// 生成 `EXPLAIN` 语句（**只对单条**；多段输入拒绝并说清为什么，不替用户挑一段）。
///
/// 只生成、不执行 —— 与「服务端条件浏览」同一姿势：用户先看见将要执行什么。
/// `analyze` 为真时带 `ANALYZE, BUFFERS`（**会真的执行语句**，写语句要先确认由界面负责）。
#[tauri::command]
fn explain_statement(sql: String, analyze: Option<bool>) -> Result<String, DbFailure> {
    doyah_studio_db::sql::explain(&sql, analyze.unwrap_or(false)).map_err(|message| DbFailure {
        message,
        hint: "EXPLAIN 一次只解释一条语句：选中要解释的那条，或把其它的删掉。".to_string(),
    })
}

/// 高亮分词（1.2 段）：**只做词法**，纯计算、不碰数据库。
///
/// 为什么分词在 Rust 侧：高亮的"什么算字符串 / 什么算注释"必须与执行时切分**同一套规则**，
/// 两边各写一套必然漂移（前端字符串里一个 `--` 就能让高亮与执行对不上）。
#[tauri::command]
fn highlight_sql(sql: String) -> Vec<doyah_studio_db::sql::Token> {
    doyah_studio_db::sql::tokenize(&sql)
}

// ── 写回与事务（1.4：一批一次事务 / 主键定位 / 只读拦截 / 危险语句确认）──────────────────

/// **一批写回，一次事务**：跑完提交，或（`rollback` 为真 / 中途失败）整批回滚。
///
/// **只读连接在这里就被拦住**：命令层先按当前连接配置的 `isReadOnly` 过一遍危险判定，
/// 命中 `Forbidden` 就整批不发（连服务端都不碰）。
#[tauri::command]
async fn db_write_batch(
    state: State<'_, ShellState>,
    statements: Vec<String>,
    rollback: Option<bool>,
) -> Result<Vec<StatementOutcome>, DbFailure> {
    let session = current_session(&state).await?;
    let read_only = state.read_only.load(std::sync::atomic::Ordering::Relaxed);
    if read_only {
        // 如实说是哪一条被拦下的：只说"只读"用户不知道自己去点哪儿
        if let Some(first) = statements.first() {
            return Err(DbFailure {
                message: format!("这条连接标了只读，写语句不发送：{first}"),
                hint:
                    "要用写功能请新建一条不带只读标记的连接（只读是本机保护，不替代数据库权限）。"
                        .to_string(),
            });
        }
    }
    session
        .run_transaction(&statements, rollback.unwrap_or(false))
        .await
}

/// 一张表的**主键列名**（写回要靠它定位"是哪一行"；无主键 ⇒ 空表，界面据此不给编辑入口）。
#[tauri::command]
async fn db_primary_key(
    state: State<'_, ShellState>,
    schema: String,
    table: String,
) -> Result<Vec<String>, DbFailure> {
    let session = current_session(&state).await?;
    session.primary_key(&schema, &table).await
}

/// 编辑集 → **要执行的 DML**（**只生成、不执行**：先让用户看清将执行什么）。
///
/// 领域层负责：完整主键条件、NULL 用 `IS NULL`、无主键拒改、只读连接标 `forbidden`。
#[tauri::command]
fn edits_to_dml(
    state: State<'_, ShellState>,
    edits: Vec<doyah_studio_db::writeback::CellEdit>,
) -> Result<Vec<doyah_studio_db::writeback::DmlStatement>, DbFailure> {
    let read_only = state.read_only.load(std::sync::atomic::Ordering::Relaxed);
    doyah_studio_db::writeback::edits_to_dml(&edits, read_only).map_err(|e| DbFailure {
        message: e.message,
        hint: e.hint,
    })
}

/// 单条 SQL 的**危险判定**（界面据此决定要不要弹确认框）。
#[tauri::command]
fn statement_risk(state: State<'_, ShellState>, sql: String) -> String {
    let read_only = state.read_only.load(std::sync::atomic::Ordering::Relaxed);
    match doyah_studio_db::writeback::statement_risk(&sql, read_only) {
        doyah_studio_db::writeback::Risk::Safe => "safe".to_string(),
        doyah_studio_db::writeback::Risk::Confirm => "confirm".to_string(),
        doyah_studio_db::writeback::Risk::Forbidden => "forbidden".to_string(),
    }
}

/// **只读标记**（FR-CONN-17）：连接时按保存的配置设定，界面也能读回来。
#[tauri::command]
fn db_read_only(state: State<'_, ShellState>) -> bool {
    state.read_only.load(std::sync::atomic::Ordering::Relaxed)
}

// ── 导入导出（1.6：CSV / JSON / Excel；边读边写、中途失败不留半截文件）──────────────────

/// **导出到文件**：跑查询 → 按格式编码 → **原子落盘**（临时文件 + 同目录改名）。
///
/// 口径：① 落盘走领域层 `io_csv::atomic_write` —— 中途失败**不留半截文件**（版本计划原文）；
/// ② **截断要如实带在返回值里**（导出也不是"想要多少有多少"，上限之外的行没进去）；
/// ③ 不静默改路径：写不进去就把服务端/系统原话端出来。
#[tauri::command]
async fn export_to_file(
    state: State<'_, ShellState>,
    sql: String,
    path: String,
    format: String,
    max_rows: Option<usize>,
) -> Result<ExportReport, DbFailure> {
    let session = current_session(&state).await?;
    let limit = max_rows.unwrap_or(100_000);
    let (columns, rows, truncated) = session.export_rows(&sql, limit).await?;
    let target = std::path::PathBuf::from(&path);
    let content = match format.as_str() {
        "json" => {
            let items: Vec<serde_json::Value> = rows
                .iter()
                .map(|row| {
                    let mut map = serde_json::Map::new();
                    for (i, column) in columns.iter().enumerate() {
                        let value = row.get(i).cloned().unwrap_or_default();
                        map.insert(column.clone(), serde_json::Value::String(value));
                    }
                    serde_json::Value::Object(map)
                })
                .collect();
            serde_json::to_string_pretty(&items).map_err(|e| DbFailure {
                message: format!("JSON 编码失败：{e}"),
                hint: "这属实现缺陷：请保留现场并报告。".to_string(),
            })?
        }
        // 默认 CSV（分隔符用逗号；嗅探只在导入时做）
        _ => doyah_studio_db::io_csv::to_csv(&columns, &rows, ','),
    };
    doyah_studio_db::io_csv::atomic_write(&target, &content).map_err(|message| DbFailure {
        message,
        hint: "确认目标目录存在且可写；换一个路径再试。".to_string(),
    })?;
    Ok(ExportReport {
        path,
        rows: rows.len(),
        columns: columns.len(),
        truncated,
        bytes: content.len(),
    })
}

/// 导出结果（**行数与截断如实报**）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportReport {
    pub path: String,
    pub rows: usize,
    pub columns: usize,
    /// 服务端还有更多行没取回来（超过上限）
    pub truncated: bool,
    pub bytes: usize,
}

/// **预览导入**：读文件 → 解析 → 与目标表列对账（**不碰数据库**）。
///
/// 为什么分两步（预览 / 执行）：导入是"一次写很多行"的操作，用户必须先看见
/// 「读了几行、丢了几行、为什么、列怎么对的」再决定写不写。预览不写库，所以可以随便点。
#[tauri::command]
fn preview_import(
    path: String,
    has_header: bool,
    target_columns: Vec<String>,
) -> Result<ImportPreview, DbFailure> {
    let text = std::fs::read_to_string(&path).map_err(|e| DbFailure {
        message: format!("读文件失败：{e}（{path}）"),
        hint: "确认路径与编码（本侧按 UTF-8 读）。".to_string(),
    })?;
    let report = doyah_studio_db::io_csv::parse_csv(&text, has_header);
    let matched = report.match_columns(&target_columns);
    Ok(ImportPreview {
        header: report.header.clone(),
        delimiter: report.delimiter.to_string(),
        parsed_rows: report.rows.len(),
        total_data_rows: report.total_data_rows,
        skipped: report.skipped.clone(),
        matched: matched.matched.clone(),
        unmatched_csv: matched.unmatched_csv.clone(),
        missing: matched.missing.clone(),
        // 前若干行做样子（给用户认数据长什么样）
        sample: report.rows.iter().take(5).cloned().collect(),
    })
}

/// 导入预览（**丢了多少、为什么，都要能看见**）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportPreview {
    pub header: Vec<String>,
    pub delimiter: String,
    pub parsed_rows: usize,
    pub total_data_rows: usize,
    pub skipped: Vec<doyah_studio_db::io_csv::SkippedRow>,
    pub matched: Vec<(String, usize)>,
    pub unmatched_csv: Vec<String>,
    pub missing: Vec<String>,
    pub sample: Vec<Vec<String>>,
}

/// **执行导入**：重新解析文件 → 按映射取列 → **一个事务**里写库。
///
/// 为什么重新解析而不是把预览的行传回来：文件可能在预览与执行之间被改过
/// （或用户换了文件）；重新解析保证"写进去的就是文件现在的内容"，且不必把整份数据
/// 在前端绕一圈（大文件那样会顶爆内存）。
#[tauri::command]
async fn run_import(
    state: State<'_, ShellState>,
    path: String,
    schema: Option<String>,
    table: String,
    has_header: bool,
    target_columns: Vec<String>,
) -> Result<ImportReport, DbFailure> {
    let session = current_session(&state).await?;
    let text = std::fs::read_to_string(&path).map_err(|e| DbFailure {
        message: format!("读文件失败：{e}（{path}）"),
        hint: "确认路径与编码（本侧按 UTF-8 读）。".to_string(),
    })?;
    let report = doyah_studio_db::io_csv::parse_csv(&text, has_header);
    let matched = report.match_columns(&target_columns);
    if matched.matched.is_empty() {
        return Err(DbFailure {
            message: "CSV 的表头与目标表没有一列对得上".to_string(),
            hint: format!(
                "CSV 表头：{:?}；目标表列：{:?}（按名字匹配，大小写与首尾空白不敏感）",
                report.header, target_columns
            ),
        });
    }
    let columns: Vec<String> = matched
        .matched
        .iter()
        .map(|(name, _)| name.clone())
        .collect();
    let indexes: Vec<usize> = matched.matched.iter().map(|(_, at)| *at).collect();
    // 空字段 → NULL 还是空串？本侧**按 NULL**（导入空白通常意思是"没有值"），
    // 这一点写在返回值里让用户看得见（要空串请用引号包一个空字段 `""`）。
    let rows: Vec<Vec<Option<String>>> = report
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
        .import_rows(schema.as_deref(), &table, &columns, &rows)
        .await?;
    Ok(ImportReport {
        inserted,
        skipped: report.skipped.clone(),
        columns,
    })
}

/// 导入结果。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportReport {
    pub inserted: usize,
    pub skipped: Vec<doyah_studio_db::io_csv::SkippedRow>,
    pub columns: Vec<String>,
}

/// **Excel（.xlsx）→ CSV**：借本机 DSH 运行时的 Python + openpyxl（**不引 Rust 侧 Excel 依赖**）。
///
/// 为什么走 Python 而不是加 Rust crate：`calamine` / `rust_xlsxwriter` 不在本机 cargo 缓存，
/// 加它们要联网取包；而本机运行时自带 Python 3.13 + openpyxl 3.1.5（实测），
/// 一条子进程就能把 .xlsx 读成 CSV，导入通路（解析 / 对账 / 事务写入）**完全复用**。
#[tauri::command]
fn xlsx_to_csv(path: String, sheet: Option<String>) -> Result<String, DbFailure> {
    let python = find_python().ok_or_else(|| DbFailure {
        message: "找不到可用的 Python（Excel 通路需要它）".to_string(),
        hint: "确认 DSH 运行时的 python 在位，或把 python 放进 PATH；CSV / JSON 通路不需要它。"
            .to_string(),
    })?;
    let script = r#"
import sys, csv, openpyxl
src, sheet_name = sys.argv[1], (sys.argv[2] or None)
wb = openpyxl.load_workbook(src, read_only=True, data_only=True)
ws = wb[sheet_name] if sheet_name else wb.active
w = csv.writer(sys.stdout, lineterminator="\n")
for row in ws.iter_rows(values_only=True):
    w.writerow(["" if c is None else str(c) for c in row])
"#;
    let mut cmd = std::process::Command::new(python);
    cmd.arg("-c").arg(script).arg(&path);
    cmd.arg(sheet.unwrap_or_default());
    let output = cmd.output().map_err(|e| DbFailure {
        message: format!("起 Python 失败：{e}"),
        hint: "确认 Python 可执行且 openpyxl 已装（本机 DSH 运行时自带）。".to_string(),
    })?;
    if !output.status.success() {
        return Err(DbFailure {
            message: format!(
                "读 .xlsx 失败：{}",
                String::from_utf8_lossy(&output.stderr).trim()
            ),
            hint: "确认这个文件真是 .xlsx（不是改了扩展名的 .xls / .csv），且没有密码保护。"
                .to_string(),
        });
    }
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

/// 找可用的 Python：先看本机 DSH 运行时的固定位置，再退回 PATH 上的 `python`。
fn find_python() -> Option<std::path::PathBuf> {
    let mut candidates: Vec<std::path::PathBuf> = Vec::new();
    if let Ok(home) = std::env::var("USERPROFILE") {
        candidates.push(
            std::path::PathBuf::from(home)
                .join(".dsh\\dsh-runtimes\\dsh-primary-runtime\\dependencies\\python\\python.exe"),
        );
    }
    candidates.push(std::path::PathBuf::from("python"));
    candidates.into_iter().find(|p| {
        std::process::Command::new(p)
            .arg("--version")
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
    })
}

// ── 库与服务器管理面（1.7：读数只读；危险操作只生成语句、不代为执行）────────────────────

/// 库列表 + 大小 + 连接数。
#[tauri::command]
async fn admin_databases(state: State<'_, ShellState>) -> Result<Vec<DatabaseInfo>, DbFailure> {
    let session = current_session(&state).await?;
    session.databases().await
}

/// 会话与锁（**排序口径在领域层**：等锁优先、其次按时长）。
#[tauri::command]
async fn admin_sessions(
    state: State<'_, ShellState>,
) -> Result<Vec<doyah_studio_db::admin::SessionRow>, DbFailure> {
    let session = current_session(&state).await?;
    session.sessions().await
}

/// 某个 schema 下的表统计（行数是**估算**，字段名已写明）。
#[tauri::command]
async fn admin_table_stats(
    state: State<'_, ShellState>,
    schema: String,
) -> Result<Vec<TableStats>, DbFailure> {
    let session = current_session(&state).await?;
    session.table_stats(&schema).await
}

/// **维护命令**（只生成、不执行 —— 版本计划原文要求）。
#[tauri::command]
fn maintenance_sql(
    schema: Option<String>,
    table: String,
) -> Vec<doyah_studio_db::admin::MaintenanceCommand> {
    doyah_studio_db::admin::maintenance_commands(schema.as_deref(), &table)
}

/// **杀会话命令**（只生成、不执行 ——"只登记不执行"）。
#[tauri::command]
fn terminate_sql(pid: i32, force: Option<bool>) -> doyah_studio_db::admin::MaintenanceCommand {
    doyah_studio_db::admin::terminate_command(pid, force.unwrap_or(false))
}

/// **授权预览**（只生成 GRANT / REVOKE 语句）。
#[tauri::command]
fn grant_preview(
    privileges: Vec<String>,
    object_kind: String,
    schema: Option<String>,
    object: String,
    role: String,
    revoke: Option<bool>,
) -> Result<String, DbFailure> {
    doyah_studio_db::admin::grant_sql(
        &privileges,
        &object_kind,
        schema.as_deref(),
        &object,
        &role,
        revoke.unwrap_or(false),
    )
    .map_err(|message| DbFailure {
        message,
        hint: "补齐权限 / 对象 / 角色再生成；本侧只生成语句、不代为执行。".to_string(),
    })
}

/// **删库确认**：用户逐字打出库名才放行（领域层判定，界面只显示结果）。
#[tauri::command]
fn confirm_drop_database(typed: String, database: String) -> doyah_studio_db::admin::Confirmation {
    doyah_studio_db::admin::confirm_drop(&typed, &database)
}

/// 读一张表的**结构**（列 / 索引 / 约束）—— 表设计器的输入。
#[tauri::command]
async fn db_table_shape(
    state: State<'_, ShellState>,
    schema: String,
    table: String,
) -> Result<TableShape, DbFailure> {
    let session = current_session(&state).await?;
    session.table_shape(&schema, &table).await
}

/// **生成 DDL**（只生成、不执行）：把表设计器的改动变成一串可读语句。
///
/// 一个命令按 `op` 分派，而不是拆成六个命令：六个命令会让"同一件事的判定散在六处"，
/// 而这几档的口径必须一致 —— 尤其"哪些算破坏性"（领域层 `ddl` 是唯一判定处）。
#[tauri::command]
fn generate_ddl(
    op: String,
    schema: Option<String>,
    table: Option<String>,
    original_columns: Option<Vec<doyah_studio_db::ddl::ColumnDef>>,
    edited_columns: Option<Vec<doyah_studio_db::ddl::ColumnDef>>,
    columns: Option<Vec<String>>,
    unique: Option<bool>,
    index_name: Option<String>,
    ref_schema: Option<String>,
    ref_table: Option<String>,
    ref_columns: Option<Vec<String>>,
    constraint_name: Option<String>,
) -> Result<Vec<doyah_studio_db::ddl::DdlStatement>, DbFailure> {
    use doyah_studio_db::ddl;
    let table_name = table.clone().unwrap_or_default();
    let schema_ref = schema.as_deref();
    let result = match op.as_str() {
        "alter_columns" => {
            let original = original_columns.unwrap_or_default();
            let edited = edited_columns.unwrap_or_default();
            let changes = column_changes(&original, &edited);
            ddl::alter_table(schema_ref, &table_name, &changes)
        }
        "create_index" => ddl::create_index(
            schema_ref,
            &table_name,
            &columns.unwrap_or_default(),
            unique.unwrap_or(false),
            index_name.as_deref(),
        )
        .map(|one| vec![one]),
        "drop_index" => {
            Ok(vec![ddl::drop_index(schema_ref, index_name.as_deref().unwrap_or_default())])
        }
        "add_foreign_key" => ddl::add_foreign_key(
            schema_ref,
            &table_name,
            &columns.unwrap_or_default(),
            ref_schema.as_deref(),
            ref_table.as_deref().unwrap_or_default(),
            &ref_columns.unwrap_or_default(),
            constraint_name.as_deref(),
        )
        .map(|one| vec![one]),
        "drop_constraint" => Ok(vec![ddl::drop_constraint(
            schema_ref,
            &table_name,
            constraint_name.as_deref().unwrap_or_default(),
        )]),
        "drop_table" => Ok(vec![ddl::drop_table(schema_ref, &table_name)]),
        other => Err(ddl::DdlError {
            message: format!("认不出的 DDL 操作：{other}"),
            hint: "可用：alter_columns / create_index / drop_index / add_foreign_key / drop_constraint / drop_table"
                .to_string(),
        }),
    };
    result.map_err(|e| DbFailure {
        message: e.message,
        hint: e.hint,
    })
}

/// 把「原列集」与「改后列集」比成领域层的列变更（**按列名配对**；新列 / 删列各归其位）。
///
/// 口径：**不猜改名** —— 改后找不到同名列就按"删除 + 新增"处理。改名要显式做，
/// 否则"把 a 改名成 b"会被误判成一删一加，用户以为只是改个名字、实际丢了数据。
fn column_changes(
    original: &[doyah_studio_db::ddl::ColumnDef],
    edited: &[doyah_studio_db::ddl::ColumnDef],
) -> Vec<doyah_studio_db::ddl::ColumnChange> {
    use doyah_studio_db::ddl::ColumnChange;
    let mut out = Vec::new();
    for from in original {
        match edited.iter().find(|to| to.name == from.name) {
            Some(to) => out.push(ColumnChange {
                from: Some(from.clone()),
                to: Some(to.clone()),
            }),
            None => out.push(ColumnChange {
                from: Some(from.clone()),
                to: None,
            }),
        }
    }
    for to in edited {
        if !original.iter().any(|from| from.name == to.name) {
            out.push(ColumnChange {
                from: None,
                to: Some(to.clone()),
            });
        }
    }
    out
}

/// **执行非破坏性 DDL**（加列 / 改列 / 加索引 / 加约束）。
///
/// **破坏性语句（删列 / 删索引 / 删约束 / 删表）不走这条命令**：界面只给"复制语句"，
/// 由用户自己拿到别处执行。命令层再兜一次 —— 万一递进来一句删类语句，直接拒绝并说明。
#[tauri::command]
async fn db_run_ddl(
    state: State<'_, ShellState>,
    statements: Vec<String>,
) -> Result<Vec<StatementOutcome>, DbFailure> {
    let session = current_session(&state).await?;
    for sql in &statements {
        if matches!(
            doyah_studio_db::writeback::statement_risk(sql, false),
            doyah_studio_db::writeback::Risk::Confirm
        ) {
            return Err(DbFailure {
                message: format!("这句被判为破坏性操作，本命令不执行：{sql}"),
                hint:
                    "破坏性语句请在生成面板里复制出去、自己确认后执行（本侧只生成、不自动执行）。"
                        .to_string(),
            });
        }
    }
    session.run_ddl(&statements).await
}

/// 单行详情的**值检查**（FR-DATA-05）：宽表竖排看、长 JSON 格式化看。///
/// 纯计算（判定形态 + 给展示文本与元信息），**不碰数据库** —— 输入就是界面上那一行。
/// 要点：NULL 与空串分开；JSON **必须真能解析**才当 JSON（半截日志按文本显示）；
/// 截断**必须**连原始字符数 / 行数一起报，否则用户会以为拿到的就是全部。
#[tauri::command]
fn inspect_row(
    columns: Vec<String>,
    type_names: Option<Vec<String>>,
    row: Vec<Option<String>>,
) -> Vec<doyah_studio_db::inspect::Field> {
    let types = type_names.unwrap_or_default();
    let cols: Vec<(String, String)> = columns
        .into_iter()
        .enumerate()
        .map(|(i, name)| (name, types.get(i).cloned().unwrap_or_default()))
        .collect();
    doyah_studio_db::inspect::row(&cols, &row, doyah_studio_db::inspect::DEFAULT_DISPLAY_LIMIT)
}

/// 读外键元数据（FR-DATA-06）：从 `pg_constraint` 把每条外键的**定义原文**取回来。
///
/// 为什么取定义原文而不是拆好的列：解析规则（`FOREIGN KEY (..) REFERENCES ..(..)`）
/// 在领域层 `foreign_key::parse_edge` 里，**只有一处**实现、可单测；
/// 命令层只负责"把服务端的话原样拿回来"。
#[tauri::command]
async fn db_foreign_keys(
    state: State<'_, ShellState>,
) -> Result<Vec<doyah_studio_db::foreign_key::Edge>, DbFailure> {
    let session = current_session(&state).await?;
    let sql = "SELECT c.conname, c.contype::text, pg_get_constraintdef(c.oid), \
               t.relname, n.nspname \
               FROM pg_constraint c \
               JOIN pg_class t ON t.oid = c.conrelid \
               JOIN pg_namespace n ON n.oid = t.relnamespace \
               WHERE c.contype = 'f' AND n.nspname NOT IN ('pg_catalog', 'information_schema') \
               ORDER BY n.nspname, t.relname, c.conname";
    let result = session
        .client()
        .simple_query(sql)
        .await
        .map_err(|e| DbFailure {
            message: postgres::server_error_text(&e),
            hint: "读外键元数据失败：确认当前用户能读 pg_catalog（一般都有）。".to_string(),
        })?;
    let mut edges = Vec::new();
    for message in result {
        if let tokio_postgres::SimpleQueryMessage::Row(row) = message {
            let constraint = row.get(0);
            let kind = row.get(1).unwrap_or_default();
            let definition = row.get(2).unwrap_or_default();
            let table = row.get(3).unwrap_or_default();
            let schema = row.get(4);
            if let Some(edge) = doyah_studio_db::foreign_key::parse_edge(
                constraint, kind, definition, table, schema, schema,
            ) {
                edges.push(edge);
            }
        }
    }
    Ok(edges)
}

// ── 工作区（alpha 2.0）命令：列目录 / 读文本文件 ────────────────────────────────────────
//
// 只读面（列目录、读文件）：**先过领域层的路径安全关**（`resolve` + `is_contained`）再读盘 ——
// 相对路径可能来自缓存 / 书签 / 模型输出，不能信。写面（新建 / 改名 / 删除）归 2.1 段。

#[tauri::command]
fn workspace_list_directory(
    workspace_root: String,
    relative_path: Option<String>,
    show_hidden: Option<bool>,
) -> Result<Vec<fs::FsEntry>, DbFailure> {
    fs::list_directory(
        &workspace_root,
        relative_path.as_deref().unwrap_or(""),
        show_hidden.unwrap_or(false),
    )
}

#[tauri::command]
fn workspace_read_file(
    workspace_root: String,
    relative_path: String,
) -> Result<fs::FileContent, DbFailure> {
    fs::read_text_file(&workspace_root, &relative_path)
}

/// 读工作区历史（**含"上次打开的根"**，会话恢复用）：读不出来就给空历史 + 一句原因，不抛。
#[tauri::command]
fn workspace_history() -> serde_json::Value {
    let (history, warning) = fs::read_history();
    serde_json::json!({ "history": history, "warning": warning })
}

/// 记一次"打开了工作区"：进"最近打开" + 记为当前根（会话恢复用）。
#[tauri::command]
fn workspace_opened(workspace_root: String, at: String) -> Result<serde_json::Value, DbFailure> {
    let (history, _) = fs::read_history();
    let next = history.opened_workspace(&workspace_root, &at);
    fs::write_history(&next)?;
    Ok(serde_json::json!({ "history": next }))
}

/// 关掉当前工作区：只清"当前根"，**保留**"最近打开"里的记录。
#[tauri::command]
fn workspace_closed() -> Result<serde_json::Value, DbFailure> {
    let (history, _) = fs::read_history();
    let next = history.closed_workspace();
    fs::write_history(&next)?;
    Ok(serde_json::json!({ "history": next }))
}

/// 记下"当前开着的页签"（只记路径 —— 内容以盘上为准，恢复时按路径重读）。
#[tauri::command]
fn workspace_open_tabs(
    workspace_root: String,
    paths: Vec<String>,
) -> Result<serde_json::Value, DbFailure> {
    let (history, _) = fs::read_history();
    let next = history
        .opened_workspace(&workspace_root, "")
        .recording_open_tabs(&paths);
    fs::write_history(&next)?;
    Ok(serde_json::json!({ "history": next }))
}

// ── 工作区写面（alpha 2.1）：新建 / 重命名 / 移动 / 删除（走回收站）────────────────────────
//
// 判定在领域层（`file_ops`：名字校验 / 唯一名 / 同名不改 / 自吞拦截），IO 在 `fs`；
// 越界判定**两遍都过**（字符串路径 + 解链接后的真实路径）。

#[tauri::command]
fn workspace_create(
    workspace_root: String,
    parent_relative_path: Option<String>,
    base_name: String,
    extension: Option<String>,
    directory: bool,
) -> Result<fs::CreatedEntry, DbFailure> {
    fs::create_entry(
        &workspace_root,
        parent_relative_path.as_deref().unwrap_or(""),
        &base_name,
        extension.as_deref(),
        directory,
    )
}

#[tauri::command]
fn workspace_rename(
    workspace_root: String,
    relative_path: String,
    new_name: String,
) -> Result<fs::CreatedEntry, DbFailure> {
    fs::rename_entry(&workspace_root, &relative_path, &new_name)
}

#[tauri::command]
fn workspace_move(
    workspace_root: String,
    relative_path: String,
    into_relative_path: String,
) -> Result<fs::CreatedEntry, DbFailure> {
    fs::move_entry(&workspace_root, &relative_path, &into_relative_path)
}

/// 「将删几项」：**先给读数让人确认**，再真删（删非空文件夹要二次确认）。
#[tauri::command]
fn workspace_deletion_summary(
    workspace_root: String,
    relative_path: String,
) -> Result<doyah_studio_db::DeletionSummary, DbFailure> {
    fs::deletion_summary(&workspace_root, &relative_path)
}

/// 删除：**走回收站**（可撤销是唯一的真保障）；删完回读确认，删不掉就如实报失败。
#[tauri::command]
fn workspace_delete(workspace_root: String, relative_path: String) -> Result<String, DbFailure> {
    fs::delete_entry(&workspace_root, &relative_path)
}

/// 在资源管理器里定位（文件选中 / 目录进入），或改为在终端打开。
#[tauri::command]
fn workspace_reveal(
    workspace_root: String,
    relative_path: String,
    terminal: Option<bool>,
) -> Result<doyah_studio_db::RevealPlan, DbFailure> {
    fs::reveal_entry(&workspace_root, &relative_path, terminal.unwrap_or(false))
}

/// 读一个文件的**行结构**（行号列宽 / 主换行符 / 是否混排）—— 判定在领域层 code_lines。
#[tauri::command]
fn workspace_read_lines(
    workspace_root: String,
    relative_path: String,
) -> Result<fs::FileLines, DbFailure> {
    fs::read_lines(&workspace_root, &relative_path)
}

/// 读一个文件的**高亮分词**（按同一份原文切片的字节偏移）。
#[tauri::command]
fn workspace_read_spans(
    workspace_root: String,
    relative_path: String,
    language_key: Option<String>,
) -> Result<fs::FileSpans, DbFailure> {
    fs::read_spans(&workspace_root, &relative_path, language_key.as_deref())
}

/// 载入一个文件时的**快照**（页签拿它做外部改动对比）。
#[tauri::command]
fn workspace_file_snapshot(
    workspace_root: String,
    relative_path: String,
) -> Result<doyah_studio_db::LoadedFile, DbFailure> {
    fs::file_snapshot(&workspace_root, &relative_path)
}

/// 检查一个页签的快照与盘上现在那份是否还是同一份（**外部改动要如实说**）。
#[tauri::command]
fn workspace_check_staleness(
    workspace_root: String,
    loaded: doyah_studio_db::LoadedFile,
) -> Result<serde_json::Value, DbFailure> {
    let (staleness, note) = fs::check_staleness(&workspace_root, &loaded)?;
    Ok(serde_json::json!({ "staleness": staleness, "note": note }))
}

/// 记下某个页签的**光标位置**（行号 + 行内偏移 + 那一行开头的锚）—— 2.3「重启后光标回来」。
///
/// 锚的作用：文件被改过之后，纯行号常常还指得对，但"对不上"这件事必须能被发现
/// （领域层 `cursor::restore` 会给 Exact / ByAnchor / Clamped 三种来源，界面据此决定要不要提醒）。
#[tauri::command]
fn workspace_record_cursor(
    workspace_root: String,
    relative_path: String,
    line: usize,
    column: usize,
) -> Result<serde_json::Value, DbFailure> {
    let file = fs::read_text_file(&workspace_root, &relative_path)?;
    let anchor =
        doyah_studio_db::remember(&file.content, &doyah_studio_db::Cursor::new(line, column));
    let (history, _) = fs::read_history();
    let next = history
        .opened_workspace(&workspace_root, "")
        .recording_cursor(&relative_path, anchor);
    fs::write_history(&next)?;
    Ok(serde_json::json!({ "history": next }))
}

/// 工作区检索：按**文件名**或按**内容**找（两者共用同一个匹配谓词）。
///
/// `byContent = false` 只看名字、不读内容（快）；`true` 逐个读内容并按行命中。
/// **跳过 ≠ 通过**：二进制 / 超大 / 读不了各记一笔，界面要看得见。
#[tauri::command]
fn workspace_search(
    workspace_root: String,
    query: String,
    by_content: Option<bool>,
    show_hidden: Option<bool>,
    limit: Option<usize>,
    max_depth: Option<usize>,
) -> Result<search::SearchOutcome, DbFailure> {
    search::search_workspace(
        &workspace_root,
        &query,
        by_content.unwrap_or(false),
        show_hidden.unwrap_or(false),
        limit,
        max_depth,
    )
}

/// 跳到命中行前把行号**夹进真实行数**（文件可能在检索之后被改短了）。
#[tauri::command]
fn workspace_clamp_line(
    workspace_root: String,
    relative_path: String,
    line: usize,
) -> Result<usize, DbFailure> {
    search::clamp_line(&workspace_root, &relative_path, line)
}

/// 解析 Markdown 成**块级模型**（预览用）。
///
/// 解析在领域层（`markdown::parse`，纯函数 + 7 例单测）；本命令只负责把文件读出来喂给它。
/// **一份解析、两个消费者**：将来笔记侧也走同一个 parse，不另写第二套。
#[tauri::command]
fn workspace_markdown(
    workspace_root: String,
    relative_path: String,
) -> Result<doyah_studio_db::MarkdownDocument, DbFailure> {
    let file = fs::read_text_file(&workspace_root, &relative_path)?;
    Ok(doyah_studio_db::parse_markdown(&file.content))
}

/// 读外观偏好（深浅轴 / 配色轴 / 星云皮肤开关）。
///
/// `systemIsDark` 由前端给（`matchMedia` 的当前值）—— 本命令只算"最终该长什么样"，
/// **不改任何东西**，界面照着设 `data-*` 即可。
#[tauri::command]
fn appearance_get(system_is_dark: Option<bool>) -> serde_json::Value {
    let (appearance, warning) = fs::read_appearance();
    serde_json::json!({
        "appearance": appearance,
        "dom": appearance.to_dom(system_is_dark.unwrap_or(false)),
        "warning": warning,
    })
}

/// 改外观偏好：**部分更新**（只传要改的那几项，其余保持）。
#[tauri::command]
fn appearance_set(
    mode: Option<String>,
    scheme: Option<String>,
    nebula_skin: Option<bool>,
    system_is_dark: Option<bool>,
) -> Result<serde_json::Value, DbFailure> {
    let (current, _) = fs::read_appearance();
    let next = doyah_studio_db::Appearance::resolve(
        Some(mode.as_deref().unwrap_or(current.mode.raw())),
        Some(scheme.as_deref().unwrap_or(current.scheme.raw())),
        Some(nebula_skin.unwrap_or(current.nebula_skin)),
    );
    fs::write_appearance(&next)?;
    Ok(serde_json::json!({
        "appearance": next,
        "dom": next.to_dom(system_is_dark.unwrap_or(false)),
    }))
}

/// 命令面板的**匹配与排序**（FR-EDIT-25）。
///
/// 命令清单由前端给（**清单只有一份**，在 `App/src/shell/commands.ts`）；
/// 匹配与排序在领域层（`palette`，7 例单测）—— 前端不另写一套匹配。
#[tauri::command]
fn palette_search(
    query: String,
    items: Vec<doyah_studio_db::PaletteItem>,
    limit: Option<usize>,
) -> Vec<doyah_studio_db::PaletteMatch> {
    doyah_studio_db::palette_search(&query, &items, limit.unwrap_or(50))
}

/// 面板用的**对象清单**：一条 SQL 取回全部表 / 视图（**不逐个 schema 问** —— 那在大库上很慢）。
///
/// 只在面板打开、且连上库时才拉；失败就返回空（面板里只是少一类可搜项，**不打扰用户**）。
#[tauri::command]
async fn db_palette_objects(
    state: State<'_, ShellState>,
) -> Result<Vec<serde_json::Value>, DbFailure> {
    let session = current_session(&state).await?;
    let sql = "SELECT n.nspname, c.relname, \
               CASE c.relkind WHEN 'r' THEN 'table' WHEN 'p' THEN 'table' \
                    WHEN 'v' THEN 'view' WHEN 'm' THEN 'view' WHEN 'f' THEN 'table' ELSE 'other' END \
               FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace \
               WHERE c.relkind IN ('r','p','v','m','f') \
                 AND n.nspname NOT IN ('pg_catalog','information_schema') \
                 AND n.nspname NOT LIKE 'pg\\_%' \
               ORDER BY n.nspname, c.relname";
    let result = session
        .client()
        .simple_query(sql)
        .await
        .map_err(|e| DbFailure {
            message: postgres::server_error_text(&e),
            hint: "读对象清单失败：确认当前用户能读 pg_catalog（一般都有）。".to_string(),
        })?;
    let mut out: Vec<serde_json::Value> = Vec::new();
    for message in result {
        if let tokio_postgres::SimpleQueryMessage::Row(row) = message {
            out.push(serde_json::json!({
                "schema": row.get(0).unwrap_or_default(),
                "name": row.get(1).unwrap_or_default(),
                "kind": row.get(2).unwrap_or_default(),
            }));
        }
    }
    Ok(out)
}

/// 读命令使用历史（面板用它把"常用的"排在前面）。
#[tauri::command]
fn command_history_get() -> serde_json::Value {
    let history = fs::read_command_history();
    serde_json::json!({ "history": history, "ranked": history.ranked(20) })
}

/// 记一次"用了这条命令"：**记完就落盘**（淘汰只在写盘前做一次）。
#[tauri::command]
fn command_history_record(command_id: String, at: i64) -> Result<serde_json::Value, DbFailure> {
    let mut history = fs::read_command_history().record(&command_id, at);
    history.prune();
    fs::write_command_history(&history)?;
    Ok(serde_json::json!({ "history": history, "ranked": history.ranked(20) }))
}

/// 清掉命令使用历史。
#[tauri::command]
fn command_history_clear() -> Result<serde_json::Value, DbFailure> {
    let history = doyah_studio_db::CommandHistory::default();
    fs::write_command_history(&history)?;
    Ok(serde_json::json!({ "history": history, "ranked": [] }))
}

/// 判一个文件**该怎么打开**（文本 / 图片 / 二进制 / 太大）—— 判定在领域层 open_as。
#[tauri::command]
fn workspace_decide_open(
    workspace_root: String,
    relative_path: String,
) -> Result<fs::OpenDecision, DbFailure> {
    fs::decide_open(&workspace_root, &relative_path)
}

/// 读图片字节（base64）供界面用 `data:` 显示；**只允许读判定为图片的文件**。
#[tauri::command]
fn workspace_read_image(
    workspace_root: String,
    relative_path: String,
) -> Result<String, DbFailure> {
    fs::read_image_base64(&workspace_root, &relative_path)
}

/// 保存一个文件（**先判冲突再写**）：盘上被别处改过就**拒绝**，一个字节都不写。
///
/// `loaded` = 页签打开时记的快照（**基线**，不能在这里现读）；`force` = 用户明确选"用我的版本覆盖"。
#[tauri::command]
fn workspace_save(
    workspace_root: String,
    relative_path: String,
    content: String,
    saved_content: String,
    loaded: doyah_studio_db::LoadedFile,
    force: Option<bool>,
) -> Result<fs::SaveReport, DbFailure> {
    fs::save_file(
        &workspace_root,
        &relative_path,
        &content,
        &saved_content,
        &loaded,
        force.unwrap_or(false),
    )
}

/// 跨文件替换的**预览**（**不写盘**）：将改哪些文件、各改几处。
#[tauri::command]
fn workspace_replace_preview(
    workspace_root: String,
    query: String,
    replacement: String,
    show_hidden: Option<bool>,
) -> Result<fs::ReplacePreview, DbFailure> {
    fs::replace_preview(
        &workspace_root,
        &query,
        &replacement,
        show_hidden.unwrap_or(false),
    )
}

/// 跨文件替换的**落盘**：逐个文件走保存护栏（盘上被改过就拒，不写）。
#[tauri::command]
fn workspace_replace_apply(
    workspace_root: String,
    query: String,
    replacement: String,
    snapshots: std::collections::HashMap<String, doyah_studio_db::LoadedFile>,
    show_hidden: Option<bool>,
    force: Option<bool>,
) -> Result<fs::ReplaceApplied, DbFailure> {
    fs::replace_apply(
        &workspace_root,
        &query,
        &replacement,
        &snapshots,
        show_hidden.unwrap_or(false),
        force.unwrap_or(false),
    )
}

// ── 代码格式化（2.6）：探测工具 / 格式化内容 ─────────────────────────────────────────
//
// 规划与内置兜底在领域层 `Db/src/format.rs`（6 例）；真探测与真跑在 `format_tool.rs`（6 例）。
// 本层只做命令的出入参。**格式化只改内存、不落盘** —— 落盘仍走 `workspace_save`
// （盘上被别处改过照样拒绝，格式化不能绕过那条护栏）。

/// 探一个文件对应语言的候选工具（**真探**：`where.exe` 找路径 + 真跑版本旗标）。
#[tauri::command]
fn workspace_format_tools(
    workspace_root: String,
    relative_path: String,
) -> Result<serde_json::Value, DbFailure> {
    // 路径仍要过安全关（免得拿相对路径去探别的目录 —— 虽然这里只用它推语言）
    fs::ensure_inside(&workspace_root, &relative_path)?;
    let language = doyah_studio_db::TextLanguage::detect(&relative_path);
    let probes = format_tool::probe_language(language);
    Ok(serde_json::json!({
        "languageKey": language.key(),
        "tools": probes,
    }))
}

/// 格式化一段内容（**不落盘**）。
///
/// `prefer_builtin` = 明确要求"只用内置"（断网环境 / 用户选择）；默认走定案口径（外部优先）。
#[tauri::command]
fn workspace_format_content(
    workspace_root: String,
    relative_path: String,
    content: String,
    prefer_builtin: Option<bool>,
) -> Result<format_tool::FormatOutcome, DbFailure> {
    fs::ensure_inside(&workspace_root, &relative_path)?;
    let language = doyah_studio_db::TextLanguage::detect(&relative_path);
    let is_fallback = language == doyah_studio_db::TextLanguage::PlainText;
    Ok(format_tool::format_content(
        language,
        is_fallback,
        &content,
        prefer_builtin.unwrap_or(false),
    ))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // 系统文件 / 文件夹选择器（W-A-1）：Home「打开文件…」与命令面板「打开工作区文件夹」
        // 两处入口靠它弹**真**选择器；权限最小面登记在 `capabilities/default.json`（只给 `dialog:allow-open`）。
        .plugin(tauri_plugin_dialog::init())
        .manage(ShellState {
            cache: Mutex::new(ViewCache::new()),
            db: AsyncMutex::new(None),
            connections: ConnectionStore::new(ConnectionStore::default_path()),
            read_only: std::sync::atomic::AtomicBool::new(false),
        })
        .invoke_handler(tauri::generate_handler![
            app_info,
            dataset_summary,
            grid_window,
            db_connect,
            db_disconnect,
            db_tables,
            db_schemas,
            db_relations,
            db_columns,
            search_objects,
            db_query,
            db_run_batch,
            db_cancel,
            explain_statement,
            highlight_sql,
            db_write_batch,
            db_primary_key,
            edits_to_dml,
            statement_risk,
            db_read_only,
            db_probe,
            connections_list,
            connection_save,
            connection_delete,
            connection_validate,
            connection_type_defaults,
            connection_import_url,
            browse_sql,
            inspect_row,
            db_foreign_keys,
            db_table_shape,
            generate_ddl,
            db_run_ddl,
            export_to_file,
            preview_import,
            run_import,
            xlsx_to_csv,
            admin_databases,
            admin_sessions,
            admin_table_stats,
            maintenance_sql,
            terminate_sql,
            grant_preview,
            confirm_drop_database,
            workspace_list_directory,
            workspace_read_file,
            workspace_history,
            workspace_opened,
            workspace_closed,
            workspace_open_tabs,
            workspace_create,
            workspace_rename,
            workspace_move,
            workspace_deletion_summary,
            workspace_delete,
            workspace_reveal,
            workspace_read_lines,
            workspace_read_spans,
            workspace_file_snapshot,
            workspace_check_staleness,
            workspace_record_cursor,
            workspace_search,
            workspace_clamp_line,
            workspace_markdown,
            appearance_get,
            appearance_set,
            palette_search,
            db_palette_objects,
            command_history_get,
            command_history_record,
            command_history_clear,
            workspace_decide_open,
            workspace_read_image,
            workspace_save,
            workspace_replace_preview,
            workspace_replace_apply,
            workspace_format_tools,
            workspace_format_content
        ])
        .run(tauri::generate_context!())
        .expect("启动 Doyah Studio Windows 外壳失败");
}
