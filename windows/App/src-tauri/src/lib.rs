//! Doyah Studio · Windows 侧表示层外壳（Tauri 2）—— 命令层
//!
//! 分工：**命令只做转发**，逻辑全在 `query.rs`（那样才 `cargo test` 判得了；窗口在无人值守里起不来）。
//! 前端命令名与这里的注册项的一致性由 `tests/ipc_contract.rs` 双向判（前端 `invoke` 一个没注册的
//! 名字是**运行时静默失败**，靠人记不住）。

pub mod connections;
pub mod fs;
pub mod postgres;
pub mod search;
mod query;

pub use connections::{config_from_form, ConnectionStore};
pub use postgres::{
    ConnectParams, ConnectReport, DbFailure, PgSession, ProbeReport, QueryResult, ServerInfo,
    StartupOutcome, StatementOutcome, TableNode, MAX_QUERY_ROWS,
};
pub use query::{DatasetSummary, GridWindowPayload, ViewCache, MAX_WINDOW_ROWS};

use std::sync::{Arc, Mutex};
use tauri::State;
use tokio::sync::Mutex as AsyncMutex;

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
fn dataset_summary(state: State<'_, ShellState>, rows: usize, cols: usize, seed: u64) -> DatasetSummary {
    // 锁中毒（某个命令 panic）时不让整个界面挂掉：恢复内层继续用，并如实记一笔。
    let mut cache = state.cache.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
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
    let mut cache = state.cache.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    cache.window(&query::ViewRequest { rows, cols, seed, order_desc, start, len })
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
    state
        .read_only
        .store(read_only.unwrap_or(false), std::sync::atomic::Ordering::Relaxed);
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
#[tauri::command]
async fn db_schemas(state: State<'_, ShellState>) -> Result<Vec<String>, DbFailure> {
    let session = current_session(&state).await?;
    session.schemas().await
}

/// 第二层：某个 schema 下的对象（**展开时才问**，不在连接时一次拉光）。
#[tauri::command]
async fn db_relations(
    state: State<'_, ShellState>,
    schema: String,
) -> Result<Vec<doyah_studio_db::tree::ObjectNode>, DbFailure> {
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
fn connections_list(state: State<'_, ShellState>) -> Result<Vec<doyah_studio_db::config::ConnectionConfig>, DbFailure> {
    state.connections.load()
}

/// 记下当前连接（`remember_password` 为真时把口令写进系统凭据管理器；**口令绝不进配置文件**）。
#[tauri::command]
fn connection_save(
    state: State<'_, ShellState>,
    id: String,
    name: String,
    host: String,
    port: u16,
    database: String,
    user: String,
    ssl_mode: Option<String>,
    is_read_only: bool,
    password: Option<String>,
    remember_password: bool,
) -> Result<Vec<doyah_studio_db::config::ConnectionConfig>, DbFailure> {
    let config = config_from_form(
        &id,
        &name,
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
    if remember_password {
        if let Some(secret) = password.as_deref().filter(|p| !p.is_empty()) {
            connections::remember_password(&id, &user, secret)?;
        }
    }
    state.connections.upsert(config)
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
        hint: format!("（判定标识：{}）改好条件再试 —— 这里只接受单条表达式。", e.identifier()),
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
                hint: "要用写功能请新建一条不带只读标记的连接（只读是本机保护，不替代数据库权限）。"
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
async fn db_foreign_keys(state: State<'_, ShellState>) -> Result<Vec<doyah_studio_db::foreign_key::Edge>, DbFailure> {
    let session = current_session(&state).await?;
    let sql = "SELECT c.conname, c.contype::text, pg_get_constraintdef(c.oid), \
               t.relname, n.nspname \
               FROM pg_constraint c \
               JOIN pg_class t ON t.oid = c.conrelid \
               JOIN pg_namespace n ON n.oid = t.relnamespace \
               WHERE c.contype = 'f' AND n.nspname NOT IN ('pg_catalog', 'information_schema') \
               ORDER BY n.nspname, t.relname, c.conname";
    let result = session.client().simple_query(sql).await.map_err(|e| DbFailure {
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
                constraint,
                kind,
                definition,
                table,
                schema,
                schema,
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
    fs::list_directory(&workspace_root, relative_path.as_deref().unwrap_or(""), show_hidden.unwrap_or(false))
}

#[tauri::command]
fn workspace_read_file(workspace_root: String, relative_path: String) -> Result<fs::FileContent, DbFailure> {
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
fn workspace_open_tabs(workspace_root: String, paths: Vec<String>) -> Result<serde_json::Value, DbFailure> {
    let (history, _) = fs::read_history();
    let next = history.opened_workspace(&workspace_root, "").recording_open_tabs(&paths);
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
fn workspace_rename(workspace_root: String, relative_path: String, new_name: String) -> Result<fs::CreatedEntry, DbFailure> {
    fs::rename_entry(&workspace_root, &relative_path, &new_name)
}

#[tauri::command]
fn workspace_move(workspace_root: String, relative_path: String, into_relative_path: String) -> Result<fs::CreatedEntry, DbFailure> {
    fs::move_entry(&workspace_root, &relative_path, &into_relative_path)
}

/// 「将删几项」：**先给读数让人确认**，再真删（删非空文件夹要二次确认）。
#[tauri::command]
fn workspace_deletion_summary(workspace_root: String, relative_path: String) -> Result<doyah_studio_db::DeletionSummary, DbFailure> {
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
fn workspace_read_lines(workspace_root: String, relative_path: String) -> Result<fs::FileLines, DbFailure> {
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
fn workspace_file_snapshot(workspace_root: String, relative_path: String) -> Result<doyah_studio_db::LoadedFile, DbFailure> {
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
    let anchor = doyah_studio_db::remember(&file.content, &doyah_studio_db::Cursor::new(line, column));
    let (history, _) = fs::read_history();
    let next = history.opened_workspace(&workspace_root, "").recording_cursor(&relative_path, anchor);
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
fn workspace_clamp_line(workspace_root: String, relative_path: String, line: usize) -> Result<usize, DbFailure> {
    search::clamp_line(&workspace_root, &relative_path, line)
}

/// 解析 Markdown 成**块级模型**（预览用）。
///
/// 解析在领域层（`markdown::parse`，纯函数 + 7 例单测）；本命令只负责把文件读出来喂给它。
/// **一份解析、两个消费者**：将来笔记侧也走同一个 parse，不另写第二套。
#[tauri::command]
fn workspace_markdown(workspace_root: String, relative_path: String) -> Result<doyah_studio_db::MarkdownDocument, DbFailure> {
    let file = fs::read_text_file(&workspace_root, &relative_path)?;
    Ok(doyah_studio_db::parse_markdown(&file.content))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
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
            browse_sql,
            inspect_row,
            db_foreign_keys,
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
            workspace_markdown
        ])
        .run(tauri::generate_context!())
        .expect("启动 Doyah Studio Windows 外壳失败");
}
