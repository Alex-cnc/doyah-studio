//! Doyah Studio · Windows 侧表示层外壳（Tauri 2）—— 命令层
//!
//! 分工：**命令只做转发**，逻辑全在 `query.rs`（那样才 `cargo test` 判得了；窗口在无人值守里起不来）。
//! 前端命令名与这里的注册项的一致性由 `tests/ipc_contract.rs` 双向判（前端 `invoke` 一个没注册的
//! 名字是**运行时静默失败**，靠人记不住）。

pub mod connections;
pub mod postgres;
mod query;

pub use connections::{config_from_form, ConnectionStore};
pub use postgres::{
    ConnectParams, ConnectReport, DbFailure, PgSession, ProbeReport, QueryResult, ServerInfo,
    StartupOutcome, TableNode, MAX_QUERY_ROWS,
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
) -> Result<ConnectReport, DbFailure> {
    // 先把旧会话放掉（换连接 = 断旧连新），**先放锁再 await**，别把锁带过 await
    {
        let mut slot = state.db.lock().await;
        *slot = None;
    }
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

/// 单行详情的**值检查**（FR-DATA-05）：宽表竖排看、长 JSON 格式化看。
///
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(ShellState {
            cache: Mutex::new(ViewCache::new()),
            db: AsyncMutex::new(None),
            connections: ConnectionStore::new(ConnectionStore::default_path()),
        })
        .invoke_handler(tauri::generate_handler![
            app_info,
            dataset_summary,
            grid_window,
            db_connect,
            db_disconnect,
            db_tables,
            db_query,
            db_probe,
            connections_list,
            connection_save,
            connection_delete,
            browse_sql,
            inspect_row,
            db_foreign_keys
        ])
        .run(tauri::generate_context!())
        .expect("启动 Doyah Studio Windows 外壳失败");
}
