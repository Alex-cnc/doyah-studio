//! Doyah Studio · Windows 侧**数据库域**（领域层，零第三方依赖）
//!
//! 归属与边界（`Docs/概要设计.md` §8.5.1 / §8.5.3）：
//! - 本 crate 属**领域层**：纯逻辑、可 `cargo test`、**不许引 GUI / 平台专有 API / 驱动**；
//! - 驱动接线与 IPC 在表示层（`App/src-tauri`），本层只给**模型与判定**；
//! - 契约来源 = 三书 + macOS 侧 `Core/` 的**行为**（`ConnectionConfig` / `ConnectionURL` /
//!   `DatabaseType`）—— 本侧按同一行为重建，不照抄其实现细节（语言 / 库 / 目录形状）。
//!
//! 本文件先落几片：**连接配置模型**（`config`）· **连接串解析 / 导出**（`url`）·
//! **服务端条件浏览**（`browse`，FR-DATA-02）。对象树、SQL 执行面按 `windows/版本计划.md` 继续。

pub mod browse;
pub mod config;
pub mod db_type;
pub mod file_ops;
pub mod foreign_key;
pub mod inspect;
pub mod reveal;
pub mod sql;
pub mod tree;
pub mod url;
pub mod workspace;
pub mod writeback;

pub use browse::{browse, count, qualified_name, split, BrowseError, BrowseFilter};
pub use reveal::{ensure_inside, explorer_plan, pick_terminal, terminal_plan, RevealPlan, TerminalKind};
pub use sql::{explain, spans, tokenize, StatementSpan, Token, TokenKind};
pub use writeback::{edits_to_dml, statement_risk, CellEdit, DmlStatement, Risk, RowKey, TransactionPlan};
pub use tree::{group_by_schema, search, sort_objects, ObjectKind, ObjectNode, SearchHit};
pub use config::{ConnectionBundle, BundleError, ConnectionConfig, SshTunnelConfig};
pub use db_type::{DatabaseType, SslMode};
pub use foreign_key::{parse_edge, query as fk_query, Direction, Edge, Option_};
pub use file_ops::{
    can_move_into, decide_rename, deletion_summary, unique_name, validate_name, DeletionSummary,
    Failure as FileOpFailure, RenameDecision, DELETION_COUNT_LIMIT,
};
pub use inspect::{CellValue, Field, Shape, SummaryLanguage};
pub use url::{FormMerge, ImportedConnection, UrlParseError};
pub use workspace::{EntryKind, History, Tab, TextLanguage};
