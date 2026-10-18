//! Doyah Studio · Windows 侧表示层外壳（Tauri 2）—— 命令层
//!
//! 分工：**命令只做转发**，逻辑全在 `query.rs`（那样才 `cargo test` 判得了；窗口在无人值守里起不来）。
//! 前端命令名与这里的注册项的一致性由 `tests/ipc_contract.rs` 双向判（前端 `invoke` 一个没注册的
//! 名字是**运行时静默失败**，靠人记不住）。

pub mod connections;
/// 智能体设置的落盘（FR-AI-01）：配置在 `%APPDATA%\DoyahStudio\agent.json`、
/// 密钥单独一份 DPAPI 密文（`agent-key.bin`）—— **配置结构里没有密钥字段**。
pub mod agent_settings;
/// 自然语言 → SQL 的外发面（FR-AI-02）：请求装配与回包解析在领域层
/// `doyah_studio_db::agent_nl2sql`；本模块只管「判放行 → 真发一次 → 回文本」，
/// **不持有任何数据库连接**（「永不自动执行」在形状上成立）。
pub mod agent_generate;
/// 对话会话的落盘（`FR-AI-17`）：一个工作区一份 `chat-<哈希>.json`，
/// 形状与归属校验在领域层 `doyah_studio_db::agent_chat_session`，本模块只管「放哪儿、怎么取」。
pub mod agent_chat_sessions;
pub mod format_tool;
pub mod fs;
pub mod postgres;
/// 内置终端的 PTY 层（W-C 底部终端 · S-9a）。**PTY 全部代码只在这个模块里**；
/// 本文件与其它文件只许经 `pty::` 接口调用，不许直接依赖 PTY crate（判据见
/// `Tools/check-platform-parity.ps1` 第五道「PTY 隔离」）。
pub mod pty;
/// 备份（`FR-IO-04` 的 Windows 侧）：封装本机 `pg_dump` —— 命令行先摊出来、口令只进环境变量。
pub mod backup;
/// 恢复（`FR-IO-05` 的 Windows 侧后一片）：封装本机 `pg_restore` —— 与备份同一套口令与日志口径。
pub mod restore;
/// 已保存查询的落盘（FR-EDIT-14）：模型与「同名覆盖」判定在领域层
/// `doyah_studio_db::saved_query`，本模块只管「放哪儿、怎么取」。
pub mod saved_queries;
/// 查询自动归档的落盘（FR-EDIT-31）：**条目格式与「同一条 SQL 累计次数」在领域口径**
/// `App/src/workspace/archive.ts`；本模块只管 `queries/<YYYY-MM-DD>.sql` 的读写与日期键校验。
pub mod archive;
/// Retro 周报包读盘（FR-R-12-01 / -02 · FR-R-13-08 的 M0 只读面）：
/// 扫 `%APPDATA%\DoyahStudio\retro\packages\<期号>\`，判定全在领域层
/// `doyah_studio_db::retro_package`，正文交给既有 `markdown::parse`。
pub mod retro_library;
/// 底部终端「端到端接线」层（W-C 底部终端 · S-9c）：把 `pty::` 的真字节喂进领域层
/// 屏幕模型 / 按键编码 / 页签会话，令 `Db/src/terminal*.rs` 那 29 例**由真字节流驱动**。
/// 只经 `pty::` 接口调用，本模块**不许出现 PTY crate 名**（判据同第五道「PTY 隔离」）。
pub mod terminal_bridge;

mod query;
pub mod search;

pub use connections::{config_from_form, ConnectionStore};
#[allow(unused_imports)]
pub use agent_settings::{AgentSettingsSnapshot, AgentSettingsStore};
#[allow(unused_imports)]
pub use saved_queries::SavedQueryStore;
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
use doyah_studio_db::sql_params;

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
    /// 已保存查询的落盘位置（FR-EDIT-14；与连接配置分两个文件，见 `saved_queries.rs` 头注）。
    pub saved_queries: SavedQueryStore,
    /// 查询自动归档的落盘根（FR-EDIT-31；`queries/<YYYY-MM-DD>.sql`，见 `archive.rs` 头注）。
    pub archive: archive::ArchiveStore,
    /// Retro 周报包目录（`FR-R-12`；`retro/packages/<期号>/`，见 `retro_library.rs` 头注）。
    pub retro: retro_library::RetroStore,
    /// 智能体配置与密钥的落盘位置（FR-AI-01；配置与密钥**分两份文件**，见 `agent_settings.rs` 头注）。
    pub agent_settings: AgentSettingsStore,
    /// 对话会话的落盘位置（FR-AI-17；**按工作区一份**，见 `agent_chat_sessions.rs` 头注）。
    pub agent_chat_sessions: agent_chat_sessions::ChatSessionStore,
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

// ── 插件清单（契约依据 = 概要设计 §3.52；本侧落法 = §8.5.8）────────────────────
//
// **单一出处**：清单本体在领域层 `doyah_studio_db::plugins::PLUGINS`（纯逻辑、可单测）。
// 本命令只做一件事：把那份清单**原样**递给界面，并**附带一次自检结果**。
//
// 为什么把自检结果也递过去：契约④要求「插件不在 ⇒ 其挂点整体消失且**不报错**」——
// 界面据此判"这份清单能不能信"；清单自相矛盾时界面应当**如实报**，而不是静默少画一个入口。

/// 插件清单里的一条（给界面看的形状；字段与领域层一一对应）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PluginEntry {
    /// 稳定标识（进视图 id / 挂点键）。
    pub id: String,
    /// 展示名（对账用的规范名；界面文案走 `App/src/i18n`）。
    pub name: String,
    /// 插件版本。
    pub version: String,
    /// 入口 target（界面目录名 = `App/src/plugins/<entry>/`）。
    pub entry: String,
    /// 能力位（`workspaces` / `database` / `notes`）。
    pub capabilities: Vec<String>,
    /// 需要的宿主挂点（七类之一）。
    pub mounts: Vec<String>,
    /// 存储归属（`bundled` = 自带 / `host` = 宿主代管）。
    pub storage: String,
    /// **功能本体是否已实现**。骨架阶段为 `false` ⇒ 界面**如实显示"未开工"**。
    pub implemented: bool,
}

/// 插件清单 + 自检（界面只消费这一份）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PluginsManifest {
    /// 全部插件声明（顺序 = 活动栏展示顺序）。
    pub plugins: Vec<PluginEntry>,
    /// 领域层自检发现的问题（空 = 清单自洽）。
    pub findings: Vec<PluginFinding>,
}

/// 自检发现的一条问题（`code` 稳定、不本地化；判据按它点名）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PluginFinding {
    pub plugin: String,
    pub code: String,
    pub detail: String,
}

/// **插件清单（唯一出处）** —— 界面与构建只消费它（契约②）。
#[tauri::command]
fn plugins_manifest() -> PluginsManifest {
    use doyah_studio_db::plugins as domain;

    PluginsManifest {
        plugins: domain::PLUGINS
            .iter()
            .map(|decl| PluginEntry {
                id: decl.id.to_string(),
                name: decl.name.to_string(),
                version: decl.version.to_string(),
                entry: decl.entry.to_string(),
                capabilities: decl.capabilities.iter().map(|c| c.id().to_string()).collect(),
                mounts: decl.mounts.iter().map(|m| m.id().to_string()).collect(),
                storage: decl.storage.id().to_string(),
                implemented: decl.implemented,
            })
            .collect(),
        findings: domain::audit()
            .into_iter()
            .map(|f| PluginFinding {
                plugin: f.plugin,
                code: f.code.to_string(),
                detail: f.detail,
            })
            .collect(),
    }
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
    /// 构建标识 · 第一段：构建时工作树所在提交的短号（`build.rs` 经 `cargo:rustc-env` 注入）。
    pub build_head: String,
    /// 构建标识 · 第二段：构建时刻（`MM-dd HH:mm`，本机本地时间；同样由 `build.rs` 注入）。
    pub build_time: String,
}

#[tauri::command]
fn app_info() -> AppInfo {
    AppInfo {
        name: "Doyah Studio".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        platform: std::env::consts::OS.to_string(),
        backend: "tauri",
        build_head: env!("DOYAH_BUILD_HEAD").to_string(),
        build_time: env!("DOYAH_BUILD_TIME").to_string(),
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

// ── 已保存查询（FR-EDIT-14 / DR-04）───────────────────────────────────────────────────────

/// 已保存查询的列表（首次使用返回空表，不是错误）。
#[tauri::command]
fn saved_queries_list(
    state: State<'_, ShellState>,
) -> Result<Vec<doyah_studio_db::saved_query::SavedQuery>, DbFailure> {
    state.saved_queries.load()
}

/// 保存一条查询的结果。
///
/// **同名冲突不是错误**（`saved: false` + `conflict`）：需求原文要的是「重名提示覆盖保存」，
/// 若走错误通道，界面只能靠匹配错误文案去分支 —— 那种分支是最脆的一种。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SavedQuerySaveReport {
    /// 这次是否真的写盘（冲突且用户没确认覆盖 ⇒ false）。
    pub saved: bool,
    /// 冲突时给出**既有那条**（界面据此提示「覆盖保存」）。
    pub conflict: Option<doyah_studio_db::saved_query::SavedQuery>,
    /// 写盘后的完整列表（`saved=false` 时是原样）。
    pub queries: Vec<doyah_studio_db::saved_query::SavedQuery>,
}

/// 保存一条查询（**同名 = 覆盖，但要先经用户确认**）。
///
/// 时间戳在这里给（领域层不读时钟，单测才能确定）；名字去空白、空名 / 空 SQL 当场拒。
#[tauri::command]
fn saved_query_save(
    state: State<'_, ShellState>,
    id: String,
    name: String,
    sql: String,
    connection_id: Option<String>,
    connection_name: Option<String>,
    database: Option<String>,
    overwrite: bool,
) -> Result<SavedQuerySaveReport, DbFailure> {
    let mut query = doyah_studio_db::saved_query::SavedQuery::new(id, name, sql).sanitized();
    query.connection_id = connection_id.filter(|v| !v.trim().is_empty());
    query.connection_name = connection_name.filter(|v| !v.trim().is_empty());
    query.database = database.filter(|v| !v.trim().is_empty());
    query.saved_at = connections::now_iso8601();

    if let Some(field) = query.problems().first() {
        let (message, hint) = match field {
            doyah_studio_db::saved_query::SavedQueryField::Name => (
                "查询名不能为空，且不能超过 120 个字符".to_string(),
                "给它起一个便于在列表里认出来的名字（例如「月度对账」）。".to_string(),
            ),
            doyah_studio_db::saved_query::SavedQueryField::Sql => (
                "编辑器里没有可保存的 SQL".to_string(),
                "先写一条 SQL 再保存。".to_string(),
            ),
        };
        return Err(DbFailure { message, hint });
    }

    let mut list = state.saved_queries.load()?;
    match doyah_studio_db::saved_query::save_into(&mut list, query.clone(), overwrite) {
        doyah_studio_db::saved_query::SaveVerdict::Conflict(existing) => {
            Ok(SavedQuerySaveReport {
                saved: false,
                conflict: Some(existing),
                queries: list,
            })
        }
        _ => {
            state.saved_queries.save(&list, &query.saved_at)?;
            Ok(SavedQuerySaveReport {
                saved: true,
                conflict: None,
                queries: list,
            })
        }
    }
}

/// 删一条已保存查询（按 id）。返回删完的列表。
#[tauri::command]
fn saved_query_delete(
    state: State<'_, ShellState>,
    id: String,
) -> Result<Vec<doyah_studio_db::saved_query::SavedQuery>, DbFailure> {
    let mut list = state.saved_queries.load()?;
    if doyah_studio_db::saved_query::remove_by_id(&mut list, &id).is_none() {
        // 本来就没有 ⇒ 不算失败（幂等），但**如实**把现状回给界面
        return Ok(list);
    }
    state.saved_queries.save(&list, &connections::now_iso8601())?;
    Ok(list)
}

// ── 查询自动归档（FR-EDIT-31）──────────────────────────────────────────────────────────
//
// 两条命令都很薄：**条目格式与「同一条 SQL 累计次数」在领域口径**
// （`App/src/workspace/archive.ts` 的纯函数 + 单测），本层只管「哪一天、放哪儿」。
// 为什么方向是这样：界面要显示归档内容，格式就得是界面那一层能读的同一份 —— 若两边各写一遍
// 渲染，改一处必漏一处（家族里这种「两处格式」最后都变成读不出来的旧文件）。

/// 读一天（`YYYY-MM-DD`）的归档；文件不在 = 空内容。
#[tauri::command]
fn archive_read(state: State<'_, ShellState>, date_key: String) -> Result<archive::ArchiveFile, DbFailure> {
    state.archive.read(&date_key)
}

/// 写一天（`YYYY-MM-DD`）的归档（整份覆盖），回写入后的身份（路径 + 字节数）。
#[tauri::command]
fn archive_write(
    state: State<'_, ShellState>,
    date_key: String,
    content: String,
) -> Result<archive::ArchiveFile, DbFailure> {
    state.archive.write(&date_key, &content)
}

/// 盘上真的有归档的日子（新的在前）—— 面板的日期切换按这份清单画。
#[tauri::command]
fn archive_days(state: State<'_, ShellState>) -> Result<Vec<archive::ArchiveDay>, DbFailure> {
    state.archive.days()
}

// ── Retro 周报包（FR-R-12-01 / -02 · FR-R-13-08 的 M0 只读面）──────────────────────────
//
// 两条命令都很薄：**什么算一张卡 / 什么算一处问题 / 路径合不合法**全在领域层
// `doyah_studio_db::retro_package`；本层只决定「扫哪儿、读哪些字节」。
// 只读：这两条命令**没有任何写路径**（`FR-R-13-08` ③：视图里不产生写回包的动作）。

/// 扫包目录（根路径 + 能画出来的期 + 读不出来的地方，逐条）。
#[tauri::command]
fn retro_packages(state: State<'_, ShellState>) -> Result<retro_library::RetroSnapshot, DbFailure> {
    state.retro.snapshot()
}

/// 读一期的正文并解析成渲染模型（`period` 只认扫出来的目录名）。
#[tauri::command]
fn retro_report(
    state: State<'_, ShellState>,
    period: String,
) -> Result<retro_library::RetroReport, DbFailure> {
    state.retro.report(&period)
}

/// 读一处媒体的字节（`FR-R-12-03`）。前端拿 ArrayBuffer 建 blob URL —— **不走 asset 协议**：
/// CSP 的「出网只走 IPC」口径不变，路径校验仍在 `retro_library::RetroStore::asset` 里。
#[tauri::command]
fn retro_asset(
    state: State<'_, ShellState>,
    period: String,
    target: String,
) -> Result<tauri::ipc::Response, DbFailure> {
    state.retro.asset(&period, &target).map(tauri::ipc::Response::new)
}

/// 把正文里的一处外链交给**系统默认处理**（`FR-R-13-09` ②：视图内不嵌 iframe、也不自己出网）。
///
/// 判定在领域层 `doyah_studio_db::external_plan`（只认 http / https）；本层只做两件事：
/// 把拒绝翻成人话、真启动（**不等进程** —— 浏览器 / 播放器会立刻返回）。
#[tauri::command]
fn open_external(url: String) -> Result<doyah_studio_db::ExternalPlan, DbFailure> {
    retro_library::open_external(&url)
}

/// 导入一个周报包（`FR-R-12-04` ① 幂等 / ③ 逐条报错不写半截）。
///
/// 源目录由**系统选择器**选（前端 `shell/dialogs.ts` 唯一调用点），本命令只收一个绝对路径。
/// 判定全在 `retro_library::RetroStore::import`：先判包合不合法 → 已有同名期比字节 →
/// 拷进临时目录再改名；界面拿回的 `state` 就是唯一裁决（`imported` / `already` / `conflict` /
/// `rejected` / `failed`），前端不再自己判第二遍。
#[tauri::command]
fn retro_import(state: State<'_, ShellState>, source: String) -> Result<retro_library::RetroImport, DbFailure> {
    state.retro.import(&source)
}

/// 整批导入（`FR-R-12-04` 的批量形态）：`source` = 装着若干期包的**上一层目录**（或单期包目录）。
///
/// 每个子目录仍走 `RetroStore::import` 同一套判定；这里只把多份结果并起来。
/// 不是包的子目录只计数（`skipped`），不逐条刷屏 —— 用户选了一整个下载目录时也不会被红字淹掉。
#[tauri::command]
fn retro_import_batch(
    state: State<'_, ShellState>,
    source: String,
) -> Result<retro_library::RetroBatchImport, DbFailure> {
    state.retro.import_batch(&source)
}

/// 在资源管理器里打开**这一期**的包目录（本机存储的可见面）。
///
/// 只收期号、**不收路径**：目录由库根 + 期号在 Rust 侧拼出来（`reveal_plan` 走
/// `validate_period`），前端给不了任意路径。启动不等进程（explorer 立刻返回）。
#[tauri::command]
fn retro_reveal(
    state: State<'_, ShellState>,
    period: String,
) -> Result<doyah_studio_db::RevealPlan, DbFailure> {
    state.retro.reveal(&period)
}

/// 导出某一期到用户选的目录（`FR-R-13-08` 显示设定第三项：导出）。
///
/// 两个参数都由**系统选择器 / 左侧列表**来（`period` 只认库里的期，`target` 必须是已存在的目录），
/// 判定全在 `retro_library::RetroStore::export`：源包只读、同名永不覆盖、不留半截。
#[tauri::command]
fn retro_export(
    state: State<'_, ShellState>,
    period: String,
    target: String,
) -> Result<retro_library::RetroExport, DbFailure> {
    state.retro.export(&period, &target)
}

/// 在资源管理器里打开**导出目录**（路径 = 目标目录 + 期号在 Rust 侧再拼一次，不收任意路径）。
#[tauri::command]
fn retro_export_reveal(
    state: State<'_, ShellState>,
    period: String,
    target: String,
) -> Result<doyah_studio_db::RevealPlan, DbFailure> {
    state.retro.export_reveal(&period, &target)
}

// ── 智能体设置（FR-AI-01）──────────────────────────────────────────────────────────────
//
// 四条命令都很薄：**判定在领域层**（`doyah_studio_db::agent_config::evaluate`），本层只做
// 「读盘 → 存盘 → 回一份快照」。界面拿到的 `gate` 就是唯一裁决，不在前端再算一遍。

/// 读设置快照（配置 + 闸门裁决 + 密钥在不在）。
#[tauri::command]
fn agent_settings_get(state: State<'_, ShellState>) -> Result<AgentSettingsSnapshot, DbFailure> {
    state.agent_settings.snapshot()
}

/// 存配置（整份覆盖），回一份新快照 —— 界面据此刷新「现在能不能外发」。
#[tauri::command]
fn agent_settings_save(
    state: State<'_, ShellState>,
    config: doyah_studio_db::agent_config::AgentConfiguration,
) -> Result<AgentSettingsSnapshot, DbFailure> {
    state.agent_settings.save(&config)?;
    state.agent_settings.snapshot()
}

/// 存密钥（DPAPI 加密后单独落盘）。**空串拒绝**，加密失败**不降级成明文**。
#[tauri::command]
fn agent_key_save(
    state: State<'_, ShellState>,
    key: String,
) -> Result<AgentSettingsSnapshot, DbFailure> {
    state.agent_settings.save_key(&key)?;
    state.agent_settings.snapshot()
}

/// 清除密钥（本就不在也算成功）。
#[tauri::command]
fn agent_key_clear(state: State<'_, ShellState>) -> Result<AgentSettingsSnapshot, DbFailure> {
    state.agent_settings.clear_key()?;
    state.agent_settings.snapshot()
}

// ── 自然语言 → SQL（FR-AI-02）──────────────────────────────────────────────────────────
//
// 两条命令：**先看要发什么**（不发）与**真发一次**（只回文本）。
// 界面必须先给用户看第一份正文、再让他点第二次才外发；而「关掉总开关零外发」由
// `agent_generate::generate` 第一段裁决保证（不是靠界面藏按钮）。

/// 装配「将要外发」的正文并给出闸门裁决（**不发请求**）。
#[tauri::command]
fn agent_generate_preview(
    state: State<'_, ShellState>,
    question: String,
    tables: Vec<doyah_studio_db::agent_nl2sql::TableBrief>,
) -> Result<agent_generate::GeneratePreview, DbFailure> {
    agent_generate::preview(&state.agent_settings, &question, &tables)
}

/// 真发一次：放行才发，结果**只回文本**、不执行；成功的那一次会留一条生成历史。
#[tauri::command]
fn agent_generate_sql(
    state: State<'_, ShellState>,
    question: String,
    tables: Vec<doyah_studio_db::agent_nl2sql::TableBrief>,
) -> Result<agent_generate::GenerateReply, DbFailure> {
    agent_generate::generate(&state.agent_settings, &question, &tables)
}

/// **问诊断一次**（`FR-AI-03`）：把面板上那份资料块原样发出去，只回正文。
///
/// 与 `agent_generate_sql` 共用同一条外发通道（闸门 / 配额 / 审计都在 `agent_generate` 里）——
/// 关掉总开关，这里同样一条请求都发不出去；回来的正文由界面按「结论必须有依据」逐条解读，
/// 本命令**不执行**任何语句。
#[tauri::command]
fn agent_diagnosis_ask(
    state: State<'_, ShellState>,
    brief: String,
) -> Result<agent_generate::AskReply, DbFailure> {
    agent_generate::ask(&state.agent_settings, &brief)
}

/// **对话一次**（`FR-AI-25` 对话页签第一片 · `FR-AI-16` ① 流式）：把整段历史原样发出去，只回正文。
///
/// 与生成 / 诊断共用同一条外发通道（闸门 / 配额 / 审计 / 重试都在 `agent_generate` 里）——
/// 关掉总开关，这里同样一条请求都发不出去。本命令**不执行**任何语句。
///
/// **异步 + 阻塞线程**：同步命令跑在主线程上，整段等回包的期间界面是冻的 ——
/// 那样「逐段画出来」就永远看不见。片段经 `onDelta` 立刻送到前端，
/// **最终正文仍以返回值为准**（流只是显示，不是第二份真值）。
#[tauri::command]
async fn agent_chat_send(
    state: State<'_, ShellState>,
    turns: Vec<doyah_studio_db::agent_nl2sql::ChatMessage>,
    carry: Vec<doyah_studio_db::agent_nl2sql::CarriedFile>,
    on_delta: tauri::ipc::Channel<String>,
) -> Result<agent_generate::ChatReply, DbFailure> {
    let store = state.agent_settings.clone();
    tauri::async_runtime::spawn_blocking(move || {
        agent_generate::chat_stream_with_carry(&store, &turns, &[], &carry, &mut |chunk| {
            // 页签已经关掉时这一发送不到：不算失败（正文照样在返回值里）。
            let _ = on_delta.send(chunk.to_string());
        })
    })
    .await
    .map_err(|err| DbFailure {
        message: format!("对话线程没能跑起来：{err}"),
        hint: "重试一次；一直不行就重启应用。".to_string(),
    })?
}

/// **用户逐件点完允许 / 拒绝之后**（`FR-AI-18`）：执行那批只读工具，把**全部**结果一次回灌给模型再要一次回答。
///
/// 与前一条同样走 `spawn_blocking`（等回包期间界面不能冻住，逐段正文才画得出来）。
/// 执行只发生在 Rust 侧：前端传进来的只是「哪几件工具 + 每件点的允许还是拒绝」。
/// `approvals` 与 `calls` 条数对不上 ⇒ 直接拒发（不替用户补一个默认决定）。
#[tauri::command]
async fn agent_chat_tool_resume(
    state: State<'_, ShellState>,
    workspace: String,
    turns: Vec<doyah_studio_db::agent_nl2sql::ChatMessage>,
    calls: Vec<doyah_studio_db::agent_nl2sql::ChatToolCall>,
    approvals: Vec<bool>,
    carry: Vec<doyah_studio_db::agent_nl2sql::CarriedFile>,
    on_delta: tauri::ipc::Channel<String>,
) -> Result<agent_generate::ToolResume, DbFailure> {
    let store = state.agent_settings.clone();
    tauri::async_runtime::spawn_blocking(move || {
        agent_generate::chat_tool_resume(
            &store,
            &workspace,
            &turns,
            &calls,
            &approvals,
            &carry,
            &mut |chunk| {
                let _ = on_delta.send(chunk.to_string());
            },
        )
    })
    .await
    .map_err(|err| DbFailure {
        message: format!("工具调用线程没能跑起来：{err}"),
        hint: "重试一次；一直不行就重启应用。".to_string(),
    })?
}

/// **读这个工作区的对话**（`FR-AI-17`）：打开对话页签 / 换工作区 / 切段时调一次。
///
/// 只读一条命令：**不触发任何外发**、也不改盘上的东西（写只发生在 [`agent_chat_save`]）。
/// `id` 省略 ⇒ 读「当前那段」（指针 → 最新 → 默认段）。
/// 文件不存在 = 第一次打开 = 空对话；文件坏了 / 属于别的工作区 ⇒ 空对话 + `notes` 里说清原因。
#[tauri::command]
fn agent_chat_load(
    state: State<'_, ShellState>,
    workspace: String,
    id: Option<String>,
) -> agent_chat_sessions::ChatSessionReport {
    match id {
        Some(id) if !id.trim().is_empty() => state.agent_chat_sessions.load_id(&workspace, &id),
        _ => state.agent_chat_sessions.load(&workspace),
    }
}

/// **这个工作区的对话列表**（`FR-AI-17` ⑤）：界面下拉用 —— 每段一行（标题 / 问数 / 时刻），
/// 读不出来的那段**单列并计数**，其余段照常可用。
///
/// 只读一条命令：**不触发任何外发**、也不改盘上的东西。
#[tauri::command]
fn agent_chat_list(
    state: State<'_, ShellState>,
    workspace: String,
) -> agent_chat_sessions::ChatSessionList {
    state.agent_chat_sessions.list(&workspace)
}

/// **开一段新对话**（`FR-AI-17`）：换话题不必「清空」（清空等于把上一段扔了）。
///
/// 当前段本来就是空的 ⇒ 原样返回它（连点两次不会造出两个空段）。
/// 这一条**会落一份空会话**：新建的段立刻出现在列表里，重开也不会消失。
#[tauri::command]
fn agent_chat_new(
    state: State<'_, ShellState>,
    workspace: String,
) -> Result<agent_chat_sessions::ChatSessionReport, DbFailure> {
    let at = doyah_studio_db::agent_quota::now_secs();
    state.agent_chat_sessions.new_session(&workspace, at)
}

/// **把这个工作区的对话落盘**（`FR-AI-17`）：每成功一问之后调一次。
///
/// `id` 省略 ⇒ 写默认段（升级前那一段的兼容路径）。归属工作区为空 ⇒ 可读失败
/// （没有「按工作区一份」可言，界面据此说「这次不会存」）。
/// 超上限 / 超长会被裁到上限**并回报条数**（`dropped` / `clipped` / `invalid`），不静默丢。
#[tauri::command]
fn agent_chat_save(
    state: State<'_, ShellState>,
    workspace: String,
    id: Option<String>,
    turns: Vec<doyah_studio_db::agent_nl2sql::ChatMessage>,
) -> Result<agent_chat_sessions::ChatSessionSaved, DbFailure> {
    let at = doyah_studio_db::agent_quota::now_secs();
    match id {
        Some(id) if !id.trim().is_empty() => state
            .agent_chat_sessions
            .save_id(&workspace, &id, &turns, at),
        _ => state.agent_chat_sessions.save(&workspace, &turns, at),
    }
}

/// 生成历史（`FR-AI-02` 的回看面）：一打开弹层就能看到以前问过什么。
///
/// 只读一条命令：**不触发任何外发**，也不改盘上的东西（写历史只发生在生成成功那一刻）。
/// 读盘失败按空历史回（口径见 `Db::agent_history` 模块头）—— 回看面坏掉不该让生成功能不可用。
#[tauri::command]
fn agent_history_list(
    state: State<'_, ShellState>,
) -> Vec<doyah_studio_db::agent_history::HistoryEntry> {
    state.agent_settings.load_history().all_recent()
}

/// **外发审计**（`FR-AI-09` 的审计半）：每一次外发尝试留的那一条痕（新的在前）。
///
/// 只读一条命令：**不触发任何外发**、也不改盘上的东西（写审计只发生在生成那一刻）。
/// 读盘失败按空账回（口径见 `Db::agent_audit` 模块头）—— 审计面坏掉不该让生成功能不可用，
/// 但界面上「一条都没有」与「读不出来」必须分得开（`AgentAuditDialog` 会先取快照再取这份清单）。
#[tauri::command]
fn agent_audit_list(state: State<'_, ShellState>) -> Vec<doyah_studio_db::agent_audit::AuditRecord> {
    state.agent_settings.load_audit().all_recent()
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
///
/// **偏移在边界换成 JS 下标**（UTF-16 码元）：领域层 `sql::tokenize` 给的是字节偏移，前端
/// `slice` 按码元切 —— 纯 ASCII 时两者相等，所以这个错长期没露头；SQL 里一有中文注释 /
/// 中文字符串，字节口径就比前端多算（汉字 3 字节 / 1 码元），整段颜色错位。
/// 换算法见 `Db/src/text_index.rs`，前端不再自带换算逻辑。
#[tauri::command]
fn highlight_sql(sql: String) -> Vec<doyah_studio_db::sql::Token> {
    let mut tokens = doyah_studio_db::sql::tokenize(&sql);
    let map = doyah_studio_db::text_index::byte_to_utf16_map(&sql);
    for token in &mut tokens {
        token.start = doyah_studio_db::text_index::byte_to_utf16(&map, token.start);
        token.end = doyah_studio_db::text_index::byte_to_utf16(&map, token.end);
    }
    tokens
}

/// FR-EDIT-03 / FR-EDIT-56 静态检查：诊断只在领域层判一遍（`Db/src/lint.rs`），界面只负责画。
/// 偏移同样是**可直接 `slice` 的 JS 下标** —— 检查器内部按码点算，这里换成 UTF-16 码元，
/// 于是「表情 + 中文」的 SQL 里下划线也不会偏一格。
#[tauri::command]
fn diagnose_sql(sql: String) -> Vec<doyah_studio_db::lint::Diagnostic> {
    let mut diagnostics = doyah_studio_db::lint::diagnose(&sql);
    let map = doyah_studio_db::text_index::char_to_utf16_map(&sql);
    for diagnostic in &mut diagnostics {
        diagnostic.start = doyah_studio_db::text_index::char_to_utf16(&map, diagnostic.start);
        diagnostic.end = doyah_studio_db::text_index::char_to_utf16(&map, diagnostic.end);
    }
    diagnostics
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

// ── 备份（FR-IO-04 · 封装本机 pg_dump）────────────────────────────────────────────
//
// 与导出的分工（两者常被混成一件事，这里钉清楚）：
//   · 导出（`export_to_file`）= 把**一条查询的结果**写成 CSV/JSON，用户自己挑列挑行；
//   · 备份（本段）= 把**整个数据库**做成一份能整库还原的归档，一致性由 `pg_dump` 的快照保证。
// 所以备份不经过驱动、不经过领域层：它是一条**子进程**，本层负责「命令怎么拼、口令怎么给、
// 日志怎么带回」。

/// 备份请求（界面 → 外壳）。**口令不在里面**：按 `connectionId` 从系统凭据里取。
#[derive(Debug, Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupRequest {
    /// 当前连接的 id（口令按它取；取不到就当这条连接没有口令）
    pub connection_id: String,
    /// 备份写到哪儿（文件或目录的完整路径）
    pub path: String,
    /// 三档格式
    pub format: backup::BackupFormat,
    /// 备份哪个库（留空 = 当前连接的库）—— 同服务器上换一个库备份不必重连
    #[serde(default)]
    pub database: Option<String>,
    /// 手动指定 `pg_dump` 路径（留空 = 自动找：PATH → 各盘 PostgreSQL 安装目录）
    #[serde(default)]
    pub program: Option<String>,
}

/// 计划回执：**只算不跑** —— 界面先把它摊给用户看（需求原文「展示实际命令行」）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupPlanReport {
    /// 找到的程序（`null` ⇒ 界面显示「程序找不到」那一档）
    pub program: Option<String>,
    /// 可复制的命令行（口令位置写 `PGPASSWORD=***`）
    pub display: String,
    pub database: String,
    pub target: String,
    pub format: backup::BackupFormat,
    /// 现在就跑会立刻失败的原因（程序找不到 / 目标已存在 / 路径空）—— **计划照样摊出来**，
    /// 用户能看着命令行自己判断哪儿不对，而不是只收到一句「失败」。
    pub problem: Option<DbFailure>,
}

/// 备份的「连哪儿、备份哪个库」+ 已 trim 的目标路径。
async fn backup_inputs(
    state: &State<'_, ShellState>,
    request: &BackupRequest,
) -> Result<(backup::BackupTarget, String), DbFailure> {
    let session = current_session(state).await?;
    let info = session.info().clone();
    let database = request
        .database
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(&info.database)
        .to_string();
    let target = backup::BackupTarget {
        host: info.host.clone(),
        port: info.port,
        user: info.user.clone(),
        database,
    };
    Ok((target, request.path.trim().to_string()))
}

/// **备份的取消槽**（同一刻只许一次备份）：`(运行序号, 取消旗)`。
///
/// 为什么是全局单槽而不是「每条命令带自己的句柄」：界面一次只开一个备份弹层，而 `pg_dump`
/// 两次同时跑会互相抢同一个目标路径 —— 与其让它们撞，不如**第二次直接拒掉**并说清是谁在跑。
static BACKUP_CANCEL_SLOT: std::sync::Mutex<Option<(u64, backup::CancelFlag)>> =
    std::sync::Mutex::new(None);
/// 运行序号（只用于「释放时确认槽里还是我这一面旗」，防止 A 跑完把 B 的旗清掉）。
static BACKUP_RUN_SEQ: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// 占住取消槽并拿到自己这面旗（已有备份在跑 ⇒ 拒绝，不排队）。
fn install_backup_cancel() -> Result<(u64, backup::CancelFlag), DbFailure> {
    let mut slot = BACKUP_CANCEL_SLOT
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    if let Some((seq, _)) = slot.as_ref() {
        return Err(DbFailure {
            message: format!("已经有一次备份在跑（第 {seq} 次），先等它结束或取消它"),
            hint: "同时跑两个 pg_dump 会互相抢同一个目标文件，所以这里不排队。".to_string(),
        });
    }
    let seq = BACKUP_RUN_SEQ.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1;
    let flag = backup::CancelFlag::new();
    *slot = Some((seq, flag.clone()));
    Ok((seq, flag))
}

/// 跑完释放槽（只在槽里还是**我这一次**时才清，别把别人的旗抹掉）。
fn release_backup_cancel(seq: u64) {
    let mut slot = BACKUP_CANCEL_SLOT
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    if matches!(slot.as_ref(), Some((current, _)) if *current == seq) {
        *slot = None;
    }
}

/// **备份的进度槽**（同一刻唯一，与取消槽同一份运行序号）。
///
/// 为什么是「轮询一个槽」而不是「往外抛事件」：本仓的 IPC 全是**一问答**形状
/// （前端 `invoke` 一次拿一个回执），没有事件通道 —— 为一次进度读数新拉一条事件管线，
/// 会把「谁在监听、监听没清掉会怎样」这类问题一起引进来。这里界面每 500ms 问一次，
/// 跑完立刻拿不到（槽被清），不会显示上一轮的陈旧读数。
static BACKUP_PROGRESS_SLOT: std::sync::Mutex<Option<(u64, backup::ProgressSink)>> =
    std::sync::Mutex::new(None);

/// 占进度槽（返回的读数槽交给跑备份的那个线程去更新）。
fn install_backup_progress(seq: u64) -> backup::ProgressSink {
    let sink = backup::ProgressSink::new();
    let mut slot = BACKUP_PROGRESS_SLOT
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    *slot = Some((seq, sink.clone()));
    sink
}

/// 跑完清进度槽（同样只看「还是不是我这一次」）。
fn release_backup_progress(seq: u64) {
    let mut slot = BACKUP_PROGRESS_SLOT
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    if matches!(slot.as_ref(), Some((current, _)) if *current == seq) {
        *slot = None;
    }
}

/// **备份计划**：找到程序、拼好参数、把命令行摊出来（**不起任何进程**）。
#[tauri::command]
async fn backup_plan(
    state: State<'_, ShellState>,
    request: BackupRequest,
) -> Result<BackupPlanReport, DbFailure> {
    let (target, path) = backup_inputs(&state, &request).await?;
    let (program, mut problem) = match backup::find_program(request.program.as_deref()) {
        Ok(found) => (Some(found), None),
        Err(failure) => (None, Some(failure)),
    };
    // 程序缺失与目标问题**各说一次**；两个都有时先报程序（没有程序，路径怎么写都跑不了）。
    if problem.is_none() {
        if let Err(failure) = backup::check_target(&path, request.format) {
            problem = Some(failure);
        }
    }
    let plan = backup::BackupPlan {
        program: program.clone(),
        args: backup::plan_args(&target, &path, request.format),
        target: std::path::PathBuf::from(&path),
        format: request.format,
        database: target.database.clone(),
    };
    Ok(BackupPlanReport {
        program: program.map(|path| path.display().to_string()),
        display: plan.display(),
        database: plan.database.clone(),
        target: path,
        format: request.format,
        problem,
    })
}

/// **真跑备份**：口令进 `PGPASSWORD`、`sslmode` 进 `PGSSLMODE`，日志尾部原样带回。
#[tauri::command]
async fn backup_run(
    state: State<'_, ShellState>,
    request: BackupRequest,
) -> Result<backup::BackupReport, DbFailure> {
    let (target, path) = backup_inputs(&state, &request).await?;
    let program = backup::find_program(request.program.as_deref())?;
    let target_path = backup::check_target(&path, request.format)?;
    // 口令：取不到就是取不到（trust / 证书认证的库本来就没有口令），不编一个空串
    let password = connections::recall_password(&request.connection_id)
        .ok()
        .flatten();
    let sslmode = state
        .connections
        .load()
        .ok()
        .and_then(|list| {
            list.into_iter()
                .find(|config| config.id == request.connection_id)
        })
        .map(|config| config.ssl_mode.raw_value().to_string());
    let plan = backup::BackupPlan {
        program: Some(program),
        args: backup::plan_args(&target, &path, request.format),
        target: target_path,
        format: request.format,
        database: target.database.clone(),
    };
    // 子进程是**阻塞**的（大库要跑几分钟）：挪到阻塞线程池，别把 async 运行时占住。
    // 取消旗先占槽再进线程 —— 界面在跑的时候按下「取消」才能摸到同一面旗。
    let (seq, cancel) = install_backup_cancel()?;
    // 进度槽同批占住：界面在跑的时候轮询它，跑完（这里）立刻清掉
    let progress = install_backup_progress(seq);
    let running_flag = cancel.clone();
    let running_sink = progress.clone();
    let outcome = tauri::async_runtime::spawn_blocking(move || {
        backup::run_cancellable_with_progress(
            &plan,
            password.as_deref(),
            sslmode.as_deref(),
            &running_flag,
            &running_sink,
        )
    })
    .await
    .map_err(|error| DbFailure {
        message: format!("备份线程没能起起来：{error}"),
        hint: "这属实现缺陷：请保留现场并报告。".to_string(),
    });
    release_backup_cancel(seq);
    release_backup_progress(seq);
    outcome?
}

/// **读一次进度**（界面在跑的时候轮询它）：`None` = 现在没有备份在跑。
///
/// 三个读数全是实测的（已写字节 / 已跑毫秒 / 子进程最近一行），**没有百分比** —
/// `pg_dump` 不告诉我们总量，编一个进度条等于骗人。
#[tauri::command]
async fn backup_progress() -> Result<Option<backup::BackupProgress>, DbFailure> {
    let slot = BACKUP_PROGRESS_SLOT
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    Ok(slot.as_ref().map(|(_, sink)| sink.snapshot()))
}

/// **取消正在跑的备份**：置位取消旗 ⇒ 子进程被终止 ⇒ **这次留下的半截产物被删掉**
/// （`pg_dump -F c` 先建文件再连服务器，强杀后不清就会剩一个 0 字节的「看起来有备份」）。
///
/// 返回值 `true` = 确实有一次备份收到了取消请求（它会在几十毫秒内以「备份已取消」结束）；
/// `false` = 当时没有备份在跑（界面上的键本该是灰的，这里如实说没有可取消的东西）。
#[tauri::command]
async fn backup_cancel() -> Result<bool, DbFailure> {
    let slot = BACKUP_CANCEL_SLOT
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    match slot.as_ref() {
        Some((_, flag)) => {
            flag.cancel();
            Ok(true)
        }
        None => Ok(false),
    }
}

/// **恢复请求**（界面 → 外壳）。**口令不在里面**：按 `connectionId` 从系统凭据里取。
#[derive(Debug, Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RestoreRequest {
    /// 当前连接的 id（口令按它取；取不到就当这条连接没有口令）
    pub connection_id: String,
    /// 从哪份备份恢复（文件或目录归档的完整路径）
    pub source: String,
    /// 先删后建（外壳会自动带上 `--if-exists`，见 `restore::plan_args`）
    #[serde(default)]
    pub clean: bool,
    /// 恢复哪一段
    #[serde(default)]
    pub section: restore::RestoreSection,
    /// 并行度（只有目录归档生效；文件归档一律串行）
    #[serde(default)]
    pub jobs: u32,
    /// 恢复到哪个库（留空 = 当前连接的库）
    #[serde(default)]
    pub database: Option<String>,
    /// 手动指定 `pg_restore` 路径（留空 = 自动找）
    #[serde(default)]
    pub program: Option<String>,
    /// **逐段恢复**（结构 → 数据 → 索引/约束，每段一条 `pg_restore --exit-on-error`，失败即停）
    #[serde(default)]
    pub sections: bool,
    /// 从哪一段起（`None` = 从第一段；失败续跑时传失败那一段）
    #[serde(default)]
    pub from: Option<restore::RestoreSection>,
}

/// 恢复计划回执：**只算不跑** —— 命令行先摊出来（恢复会改库，比备份更需要这一眼）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RestorePlanReport {
    /// 找到的程序（`null` ⇒ 界面显示「程序找不到」那一档）
    pub program: Option<String>,
    /// 可复制的命令行（口令位置写 `PGPASSWORD=***`）
    pub display: String,
    pub database: String,
    pub source: String,
    /// 源是文件还是目录归档（界面按它决定 `--jobs` 能不能填）
    pub kind: String,
    pub section: restore::RestoreSection,
    /// **实际会用上的并行度**（0 = 串行）
    pub jobs: u32,
    /// 现在就跑会立刻失败的原因（程序找不到 / 源不存在 / 纯 SQL 备份）
    pub problem: Option<DbFailure>,
}

/// 恢复的「连哪儿、恢复到哪个库」+ 已 trim 的源路径。
async fn restore_inputs(
    state: &State<'_, ShellState>,
    request: &RestoreRequest,
) -> Result<(restore::RestoreTarget, String), DbFailure> {
    let session = current_session(state).await?;
    let info = session.info().clone();
    let database = request
        .database
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(&info.database)
        .to_string();
    let target = restore::RestoreTarget {
        host: info.host.clone(),
        port: info.port,
        user: info.user.clone(),
        database,
    };
    Ok((target, request.source.trim().to_string()))
}

/// **恢复的取消槽**（与备份各一把：两件事互不排队，但同时只会各跑一个）。
static RESTORE_CANCEL_SLOT: std::sync::Mutex<Option<(u64, backup::CancelFlag)>> =
    std::sync::Mutex::new(None);
static RESTORE_RUN_SEQ: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

fn install_restore_cancel() -> Result<(u64, backup::CancelFlag), DbFailure> {
    let mut slot = RESTORE_CANCEL_SLOT
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    if let Some((seq, _)) = slot.as_ref() {
        return Err(DbFailure {
            message: format!("已经有一次恢复在跑（第 {seq} 次），先等它结束或取消它"),
            hint: "同时跑两个 pg_restore 会往同一个库里抢着写对象，所以这里不排队。".to_string(),
        });
    }
    let seq = RESTORE_RUN_SEQ.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1;
    let flag = backup::CancelFlag::new();
    *slot = Some((seq, flag.clone()));
    Ok((seq, flag))
}

fn release_restore_cancel(seq: u64) {
    let mut slot = RESTORE_CANCEL_SLOT
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    if matches!(slot.as_ref(), Some((current, _)) if *current == seq) {
        *slot = None;
    }
}

/// **恢复计划**：找到程序、校验源、拼好参数（**不起任何进程**）。
#[tauri::command]
async fn restore_plan(
    state: State<'_, ShellState>,
    request: RestoreRequest,
) -> Result<RestorePlanReport, DbFailure> {
    let (target, source) = restore_inputs(&state, &request).await?;
    let (program, mut problem) = match restore::find_program(request.program.as_deref()) {
        Ok(found) => (Some(found), None),
        Err(failure) => (None, Some(failure)),
    };
    let options = restore::RestoreOptions {
        clean: request.clean,
        section: request.section,
        jobs: request.jobs,
        // 单段模式保持既有行为：不加 --exit-on-error（一次性恢复由 pg_restore 自己决定何时停）
        fail_fast: false,
    };
    // 源的问题与程序缺失各说一次；两个都有时先报程序（没有程序，源对不对都跑不了）
    let mut kind = "file".to_string();
    let mut jobs = restore::effective_jobs(restore::SourceKind::File, options.jobs);
    if let Ok((path, resolved)) = restore::check_source(&source) {
        kind = if resolved.is_directory() {
            "directory".to_string()
        } else {
            "file".to_string()
        };
        jobs = restore::effective_jobs(resolved, options.jobs);
        let plan = restore::RestorePlan {
            program: program.clone(),
            args: restore::plan_args(&target, &path, resolved, &options),
            source: path,
            kind: resolved,
            database: target.database.clone(),
            section: options.section,
            jobs,
        };
        return Ok(RestorePlanReport {
            program: program.map(|found| found.display().to_string()),
            display: plan.display(),
            database: plan.database.clone(),
            source: plan.source.display().to_string(),
            kind,
            section: plan.section,
            jobs: plan.jobs,
            problem,
        });
    } else if problem.is_none() {
        if let Err(failure) = restore::check_source(&source) {
            problem = Some(failure);
        }
    }
    // 源不合法：计划照样摊出来（用户能看着命令行自己判断哪儿不对），只是标成「跑不了」
    let plan = restore::RestorePlan {
        program,
        args: Vec::new(),
        source: std::path::PathBuf::from(&source),
        kind: restore::SourceKind::File,
        database: target.database.clone(),
        section: options.section,
        jobs,
    };
    Ok(RestorePlanReport {
        program: plan.program.as_ref().map(|found| found.display().to_string()),
        display: plan.display(),
        database: plan.database.clone(),
        source,
        kind,
        section: plan.section,
        jobs: plan.jobs,
        problem,
    })
}

/// **真跑恢复**：口令进 `PGPASSWORD`、`sslmode` 进 `PGSSLMODE`，日志尾部原样带回。
#[tauri::command]
async fn restore_run(
    state: State<'_, ShellState>,
    request: RestoreRequest,
) -> Result<restore::RestoreReport, DbFailure> {
    let (target, source) = restore_inputs(&state, &request).await?;
    let program = restore::find_program(request.program.as_deref())?;
    let (path, kind) = restore::check_source(&source)?;
    let options = restore::RestoreOptions {
        clean: request.clean,
        section: request.section,
        jobs: request.jobs,
        fail_fast: false,
    };
    let password = connections::recall_password(&request.connection_id)
        .ok()
        .flatten();
    let sslmode = state
        .connections
        .load()
        .ok()
        .and_then(|list| {
            list.into_iter()
                .find(|config| config.id == request.connection_id)
        })
        .map(|config| config.ssl_mode.raw_value().to_string());
    let plan = restore::RestorePlan {
        program: Some(program),
        args: restore::plan_args(&target, &path, kind, &options),
        source: path,
        kind,
        database: target.database.clone(),
        section: options.section,
        jobs: restore::effective_jobs(kind, options.jobs),
    };
    // 子进程是阻塞的（大库恢复要几分钟）：挪到阻塞线程池，别把 async 运行时占住。
    let (seq, cancel) = install_restore_cancel()?;
    let running_flag = cancel.clone();
    let outcome = tauri::async_runtime::spawn_blocking(move || {
        restore::run_cancellable(&plan, password.as_deref(), sslmode.as_deref(), &running_flag)
    })
    .await
    .map_err(|error| DbFailure {
        message: format!("恢复线程没能起起来：{error}"),
        hint: "这属实现缺陷：请保留现场并报告。".to_string(),
    });
    release_restore_cancel(seq);
    outcome?
}

/// **取消正在跑的恢复**：置位取消旗 ⇒ 子进程被终止。
///
/// ⚠️ 与备份不同：强杀 `pg_restore` **不会撤销已经写进库里的对象** ⇒ 回执里必须说清
/// 「库里可能停在半途」（`restore::run_cancellable` 已按这条措辞返回）。
#[tauri::command]
async fn restore_cancel() -> Result<bool, DbFailure> {
    let slot = RESTORE_CANCEL_SLOT
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    match slot.as_ref() {
        Some((_, flag)) => {
            flag.cancel();
            Ok(true)
        }
        None => Ok(false),
    }
}

/// **逐段恢复的计划回执**：逐段模式的「先摊命令行」是**每段一条**（三行），不是一行。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SectionCommandReport {
    pub section: restore::RestoreSection,
    /// 这一段实际会跑的命令行（口令写 `PGPASSWORD=***`）
    pub display: String,
    /// 这一段实际会用上的并行度（0 = 串行）
    pub jobs: u32,
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RestoreSectionsPlanReport {
    pub program: Option<String>,
    /// 按依赖顺序排好的每段命令（续跑时只有失败段与它后面的段）
    pub commands: Vec<SectionCommandReport>,
    pub database: String,
    pub source: String,
    pub kind: String,
    pub jobs: u32,
    pub problem: Option<DbFailure>,
}

/// **逐段恢复计划**：拼出每段的命令行（**不起任何进程**）。
#[tauri::command]
async fn restore_plan_sections(
    state: State<'_, ShellState>,
    request: RestoreRequest,
) -> Result<RestoreSectionsPlanReport, DbFailure> {
    let (target, source) = restore_inputs(&state, &request).await?;
    let (program, mut problem) = match restore::find_program(request.program.as_deref()) {
        Ok(found) => (Some(found), None),
        Err(failure) => (None, Some(failure)),
    };
    let options = restore::RestoreOptions {
        clean: request.clean,
        section: restore::RestoreSection::All,
        jobs: request.jobs,
        fail_fast: true,
    };
    let mut commands: Vec<SectionCommandReport> = Vec::new();
    let mut kind = "file".to_string();
    let mut jobs = 0;
    match restore::check_source(&source) {
        Ok((path, resolved)) => {
            kind = if resolved.is_directory() {
                "directory".to_string()
            } else {
                "file".to_string()
            };
            for plan in restore::section_plans(
                program.clone(),
                &target,
                &path,
                resolved,
                options,
                request.from,
            ) {
                jobs = plan.jobs;
                commands.push(SectionCommandReport {
                    section: plan.section,
                    display: plan.display(),
                    jobs: plan.jobs,
                });
            }
        }
        Err(failure) => {
            // 程序缺失先报程序（没有程序，源对不对都跑不了）—— 与单段计划同一口径
            if problem.is_none() {
                problem = Some(failure);
            }
        }
    }
    Ok(RestoreSectionsPlanReport {
        program: program.map(|found| found.display().to_string()),
        commands,
        database: target.database.clone(),
        source,
        kind,
        jobs,
        problem,
    })
}

/// **逐段真跑**：每段一条 `pg_restore --section=… --exit-on-error`，**遇错即停**。
///
/// 回执里带每段的退出码与日志尾部，以及「接下来从哪一段起」（`resumeFrom` / `resumeCommand`）。
/// 取消沿用同一把槽：取消的是**当前这一段**，子进程被强杀后整条序列停下（不再往下跑）。
#[tauri::command]
async fn restore_run_sections(
    state: State<'_, ShellState>,
    request: RestoreRequest,
) -> Result<restore::SectionsReport, DbFailure> {
    let (target, source) = restore_inputs(&state, &request).await?;
    let program = restore::find_program(request.program.as_deref())?;
    let (path, kind) = restore::check_source(&source)?;
    let options = restore::RestoreOptions {
        clean: request.clean,
        section: restore::RestoreSection::All,
        jobs: request.jobs,
        fail_fast: true,
    };
    let plans = restore::section_plans(
        Some(program),
        &target,
        &path,
        kind,
        options,
        request.from,
    );
    let password = connections::recall_password(&request.connection_id)
        .ok()
        .flatten();
    let sslmode = state
        .connections
        .load()
        .ok()
        .and_then(|list| {
            list.into_iter()
                .find(|config| config.id == request.connection_id)
        })
        .map(|config| config.ssl_mode.raw_value().to_string());
    let (seq, cancel) = install_restore_cancel()?;
    let running_flag = cancel.clone();
    let outcome = tauri::async_runtime::spawn_blocking(move || {
        restore::run_sections(&plans, |plan| {
            restore::attempt(plan, password.as_deref(), sslmode.as_deref(), &running_flag)
        })
    })
    .await
    .map_err(|error| DbFailure {
        message: format!("逐段恢复的线程没能起起来：{error}"),
        hint: "这属实现缺陷：请保留现场并报告。".to_string(),
    });
    release_restore_cancel(seq);
    outcome?
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

/// **慢查询排行**（FR-DIAG-03）。扩展不可用**不是错误**：回包里 `available=false` +
/// 一句可读原因 + 三步安装指引 —— 界面上要读得出来「为什么不行、下一步做什么」。
#[tauri::command]
async fn slow_queries(
    state: State<'_, ShellState>,
    sort: String,
    limit: Option<u32>,
) -> Result<doyah_studio_db::slow_query::SlowQueryReport, DbFailure> {
    let parsed = doyah_studio_db::slow_query::SlowQuerySort::parse(&sort).ok_or_else(|| DbFailure {
        message: format!("认不出的排序口径：{sort}"),
        hint: "只能用 total（总耗时）/ mean（平均耗时）/ calls（调用次数）这三个之一。".to_string(),
    })?;
    let session = current_session(&state).await?;
    session
        .slow_queries(parsed, limit.map(|n| n as usize).unwrap_or(doyah_studio_db::slow_query::DEFAULT_LIMIT))
        .await
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

/// **抓一份库结构快照**（FR-DDL-04）：对比要的两侧都从这里拿。
///
/// `label` 是界面给这一侧起的名字（如「上周的库」），会原样进报告 —— 界面上显示的是它，
/// 不是本层猜的「基准 / 目标」。
#[tauri::command]
async fn schema_snapshot(
    state: State<'_, ShellState>,
    schema: String,
    label: Option<String>,
    taken_at: Option<i64>,
) -> Result<doyah_studio_db::schema_diff::SchemaSnapshot, DbFailure> {
    if schema.trim().is_empty() {
        return Err(DbFailure {
            message: "schema 是空的：不知道抓哪个 schema 的结构".to_string(),
            hint: "先选一个 schema（默认 public）再抓快照。".to_string(),
        });
    }
    let session = current_session(&state).await?;
    session
        .schema_snapshot(
            label.as_deref().map(str::trim).filter(|l| !l.is_empty()).unwrap_or("当前库"),
            schema.trim(),
            taken_at.unwrap_or(0),
        )
        .await
}

/// **两份快照 → 差异 + 有序同步脚本**（FR-DDL-04）。
///
/// **纯函数、不连库**：两侧都是快照，所以两个库不在同一次会话里也能比。
/// 生成失败（空表名 / 零列表）不进 Err，而是逐条落进报告里的 `skipped` —— 界面要能
/// 「一边报差异、一边说这条为什么不生成」，而不是整块报错什么都看不到。
#[tauri::command]
fn schema_diff_plan(
    base: doyah_studio_db::schema_diff::SchemaSnapshot,
    target: doyah_studio_db::schema_diff::SchemaSnapshot,
    allow_drop: Option<bool>,
) -> doyah_studio_db::schema_diff::SchemaDiffReport {
    doyah_studio_db::schema_diff::diff(&base, &target, allow_drop.unwrap_or(false))
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
///
/// 字体面也走同一条命令（同一份偏好文件、两条正交轴）：
/// * `editorFamily` **不传** = 不改；传空串 = **回到系统等宽**（清掉用户挑的族）；
/// * `editorSizePt` **不传** = 不改；传越界值 = 夹取到 9~20（不报错，与领域层同口径）。
#[tauri::command]
fn appearance_set(
    mode: Option<String>,
    scheme: Option<String>,
    nebula_skin: Option<bool>,
    editor_family: Option<String>,
    editor_size_pt: Option<u32>,
    system_is_dark: Option<bool>,
) -> Result<serde_json::Value, DbFailure> {
    let (current, _) = fs::read_appearance();
    let family = editor_family.or_else(|| current.editor_family.clone());
    let next = doyah_studio_db::Appearance::resolve(
        Some(mode.as_deref().unwrap_or(current.mode.raw())),
        Some(scheme.as_deref().unwrap_or(current.scheme.raw())),
        Some(nebula_skin.unwrap_or(current.nebula_skin)),
    )
    .with_editor_font(
        family.as_deref(),
        editor_size_pt.or(Some(current.editor_size_pt)),
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

/// 格式化**编辑面里的一段 SQL**（`FR-EDIT-22`）—— 与 `workspace_format_content` 同一套规则，
/// 只差一处：**查询还没有文件**（它是内存里的一段文本）⇒ 语言固定为 SQL，也不必过路径安全检查。
///
/// 规则仍只在 `format_tool::format_content` 里判一遍（外部工具优先 → 内置兜底 → 如实拒绝），
/// 本层不另写一份格式化器：同一个规则两处实现必然分叉。
#[tauri::command]
fn sql_format(sql: String, prefer_builtin: Option<bool>) -> format_tool::FormatOutcome {
    format_tool::format_content(
        doyah_studio_db::TextLanguage::Sql,
        false,
        &sql,
        prefer_builtin.unwrap_or(false),
    )
}

#[tauri::command]
fn sql_parameters(sql: String) -> sql_params::ScanOutcome {
    sql_params::scan(&sql)
}

/// 把参数值**绑定**进语句（`FR-EXEC-17`）。
///
/// 返回的是**只用于本次执行**的语句：编辑器里那行占位符原样留着（可复用模板）。
/// 缺值 / 填错在绑定前就拦下（`Missing` 一次报全，`BadValue` 点明是哪个参数）——
/// 不把半成品丢给服务端替我们报语法错。
#[tauri::command]
fn sql_bind_parameters(
    sql: String,
    values: Vec<sql_params::ParamValue>,
) -> Result<sql_params::BindOutcome, String> {
    sql_params::bind(&sql, &values).map_err(|error| error.to_string())
}

// ── 内置终端（W-C 底部终端 · S-9a 起 PTY，S-9c 起**经领域层**）：四条命令，本文件不碰 PTY 库 ──
//
// S-9c 起命令走 `terminal_bridge::`：真字节喂进领域层屏幕模型（`TerminalScreen`）、
// 会话 id ↔ `TerminalTabs`、退出态落 `mark_exited`。`data` 字段**原样保留**（前端仍靠它渲染），
// `screen` 是**新增的投影字段**（只增不减，前端 `TerminalChunk` 与既有 15 例不动）。

/// 起一个真交互式终端会话，返回会话 id。
///
/// `program` 缺省即系统 shell（`%COMSPEC%`）；`args` 为空 = 交互式，给了 = 跑一次性命令。
#[tauri::command]
fn terminal_open(
    program: Option<String>,
    args: Option<Vec<String>>,
    cwd: Option<String>,
    cols: Option<u16>,
    rows: Option<u16>,
) -> Result<u64, String> {
    let program = program.unwrap_or_else(pty::default_shell);
    let args = args.unwrap_or_default();
    terminal_bridge::open(
        &program,
        &args,
        cwd.as_deref(),
        cols.unwrap_or(80),
        rows.unwrap_or(24),
    )
}

/// 往终端会话写（用户按键 / 粘贴）。
#[tauri::command]
fn terminal_write(id: u64, data: String) -> Result<(), String> {
    terminal_bridge::write(id, &data)
}

/// 读终端输出（最多等 `timeout_ms`）：裸字节 + 领域层屏幕投影 + 是否结束 + 退出码。
#[tauri::command]
fn terminal_read(
    id: u64,
    timeout_ms: Option<u64>,
) -> Result<terminal_bridge::TerminalChunk, String> {
    terminal_bridge::read(id, timeout_ms.unwrap_or(50))
}

/// 关闭终端会话。
#[tauri::command]
fn terminal_close(id: u64) -> Result<(), String> {
    terminal_bridge::close(id)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // 系统文件 / 文件夹选择器（W-A-1）：Home「打开文件…」与命令面板「打开工作区文件夹」
        // 两处入口靠它弹**真**选择器；权限最小面登记在 `capabilities/default.json`（只给 `dialog:allow-open`）。
        .plugin(tauri_plugin_dialog::init())
        // **界面可见构建标识**（S-073a · 前门裁决 `T-20261007-085`）：主窗口标题写成
        // `Doyah Studio {版本} · {提交短号} · {构建时刻}`，打开包就能认出「这是哪一份构建」——
        // 原先标题写死 `Doyah Studio`，debug / release / 一周前的旧包长得一模一样。
        // 版本号仍只有一处真源 = 本 crate 的 `CARGO_PKG_VERSION`（见 `app_info`）；
        // 提交短号与构建时刻由 `build.rs` 经 `cargo:rustc-env` 在构建期注入（取不到即 `unknown`）。
        .setup(|app| {
            use tauri::Manager as _;
            if let Some(window) = app.get_webview_window("main") {
                let title = format!(
                    "Doyah Studio {} · {} · {}",
                    env!("CARGO_PKG_VERSION"),
                    env!("DOYAH_BUILD_HEAD"),
                    env!("DOYAH_BUILD_TIME"),
                );
                // 设不上标题不该让外壳起不来：照原样记一笔，其余照跑。
                if let Err(error) = window.set_title(&title) {
                    eprintln!("设置主窗口标题失败：{error}");
                }
            }
            Ok(())
        })
        .manage(ShellState {
            cache: Mutex::new(ViewCache::new()),
            db: AsyncMutex::new(None),
            connections: ConnectionStore::new(ConnectionStore::default_path()),
            saved_queries: SavedQueryStore::new(SavedQueryStore::default_path()),
            archive: archive::ArchiveStore::new(archive::ArchiveStore::default_root()),
            retro: retro_library::RetroStore::new(retro_library::RetroStore::default_root()),
            agent_settings: AgentSettingsStore::default_store(),
            agent_chat_sessions: agent_chat_sessions::ChatSessionStore::default_store(),
            read_only: std::sync::atomic::AtomicBool::new(false),
        })
        .invoke_handler(tauri::generate_handler![
            app_info,
            plugins_manifest,
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
            diagnose_sql,
            sql_format,
            sql_parameters,
            sql_bind_parameters,
            db_write_batch,
            db_primary_key,
            edits_to_dml,
            statement_risk,
            db_read_only,
            db_probe,
            connections_list,
            connection_save,
            connection_delete,
            saved_queries_list,
            saved_query_save,
            saved_query_delete,
            archive_read,
            archive_write,
            archive_days,
            retro_packages,
            retro_report,
            retro_asset,
            open_external,
            retro_import,
            retro_import_batch,
            retro_reveal,
            retro_export,
            retro_export_reveal,
            agent_settings_get,
            agent_settings_save,
            agent_key_save,
            agent_key_clear,
            agent_generate_preview,
            agent_generate_sql,
            agent_diagnosis_ask,
            agent_chat_send,
            agent_chat_tool_resume,
            agent_chat_load,
            agent_chat_list,
            agent_chat_new,
            agent_chat_save,
            agent_history_list,
            agent_audit_list,
            connection_validate,
            connection_type_defaults,
            connection_import_url,
            browse_sql,
            inspect_row,
            db_foreign_keys,
            db_table_shape,
            generate_ddl,
            db_run_ddl,
            schema_snapshot,
            schema_diff_plan,
            export_to_file,
            backup_plan,
            backup_run,
            backup_cancel,
            backup_progress,
            restore_plan,
            restore_run,
            restore_cancel,
            restore_plan_sections,
            restore_run_sections,
            preview_import,
            run_import,
            xlsx_to_csv,
            admin_databases,
            admin_sessions,
            admin_table_stats,
            slow_queries,
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
            workspace_format_content,
            terminal_open,
            terminal_write,
            terminal_read,
            terminal_close
        ])
        .run(tauri::generate_context!())
        .expect("启动 Doyah Studio Windows 外壳失败");
}
