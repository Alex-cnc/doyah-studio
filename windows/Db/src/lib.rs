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

pub mod appearance;
pub mod browse;
pub mod code_lines;
pub mod command_history;
pub mod config;
pub mod cursor;
pub mod db_type;
pub mod ddl;
pub mod file_ops;
pub mod foreign_key;
pub mod format;
pub mod highlight;
pub mod inspect;
pub mod markdown;
pub mod open_as;
pub mod palette;
pub mod replace;
pub mod reveal;
pub mod save_guard;
pub mod search;
pub mod sql;
pub mod staleness;
pub mod tree;
pub mod terminal;
pub mod terminal_input;
pub mod terminal_tabs;
pub mod url;
pub mod workspace;
pub mod writeback;

pub use appearance::{
    Appearance, AppearanceMode, ColorScheme, DomAppearance,
};
pub use browse::{browse, count, qualified_name, split, BrowseError, BrowseFilter};
pub use markdown::{
    parse as parse_markdown, parse_inline, Block, BlockKind, ColumnAlignment, Document as MarkdownDocument,
    Span as MarkdownSpan, MARKDOWN_FORMAT_VERSION,
};
pub use open_as::{
    decide as decide_open_as, explain as explain_open_as, image_format, looks_binary, ImageFormat, OpenAs,
    MAX_EDITABLE_BYTES, PROBE_BYTES,
};
pub use palette::{
    match_item, search as palette_search, Item as PaletteItem, Match as PaletteMatch, Tier as PaletteTier,
    KEYWORD_BONUS,
};
pub use replace::{
    apply_to_line, apply_to_text, decide_apply, plan_file, replacements_in_line, summarise,
    FileChange, LineChange, ReplaceError, Replacement,
};
pub use reveal::{ensure_inside, explorer_plan, pick_terminal, terminal_plan, RevealPlan, TerminalKind};
pub use save_guard::{
    decide_overwrite, decide_save, explain_conflict, SaveDecision,
};
pub use search::{
    assemble, decode_text, hits_in_text, matches, normalize, snippet, ContentGroup, ContentHit,
    ContentResult, SkipReport, BINARY_PROBE_BYTES, DEFAULT_MAX_DEPTH, DEFAULT_MAX_FILE_SIZE,
    DEFAULT_PER_FILE_LIMIT, DEFAULT_RESULT_LIMIT, DEFAULT_SNIPPET_LIMIT,
};
pub use sql::{explain, spans, tokenize, StatementSpan, Token, TokenKind};
pub use ddl::{
    add_foreign_key, alter_table, create_index, drop_constraint, drop_index, drop_table,
    executable_subset, has_destructive, ColumnChange, ColumnDef as DdlColumnDef, DdlError,
    DdlStatement, StatementClass,
};
pub use staleness::{classify, content_hash, note as staleness_note, DiskFile, LoadedFile, Staleness};
pub use writeback::{edits_to_dml, statement_risk, CellEdit, DmlStatement, Risk, RowKey, TransactionPlan};
pub use tree::{group_by_schema, search, sort_objects, ObjectKind, ObjectNode, SearchHit};
pub use cursor::{anchor_prefix, remember, restore, Cursor, CursorAnchor, RestoreHow, RestoredCursor};
pub use code_lines::{
    digits_of, dominant_ending, gutter_digits, is_mixed, join_with, line_count, lines, Line, LineEnding,
};
pub use command_history::{Entry as CommandHistoryEntry, History as CommandHistory, HISTORY_LIMIT as COMMAND_HISTORY_LIMIT};
pub use config::{ConnectionBundle, BundleError, ConnectionConfig, SshTunnelConfig};
pub use db_type::{DatabaseType, SslMode};
pub use format::{
    builtin_for, describe as describe_format_plan, format_whitespace, plan_format as plan_format, tools_for,
    Builtin as FormatBuiltin, Capability as FormatCapability, Plan as FormatPlan, Refusal as FormatRefusal,
    Tool as FormatTool, WhitespaceReport,
};
pub use foreign_key::{parse_edge, query as fk_query, Direction, Edge, Option_};
pub use file_ops::{
    can_move_into, decide_rename, deletion_summary, unique_name, validate_name, DeletionSummary,
    Failure as FileOpFailure, RenameDecision, DELETION_COUNT_LIMIT,
};
// 注：	okenize / TokenKind 已被 sql 模块占用（那边是 SQL 编辑面的分词）⇒ 这里加 code 前缀
pub use highlight::{
    syntax_of, tokenize as tokenize_code, CodeSpan, CodeSyntax, CodeTokenKind,
};
pub use inspect::{CellValue, Field, Shape, SummaryLanguage};
pub use terminal_tabs::{
    derive_title, perform as perform_tab_command, sanitize_title, SessionState, Tab as TerminalTab,
    TabCommand, Tabs as TerminalTabs, TITLE_LIMIT,
};
pub use terminal_input::{
    control_key, cursor_key, cursor_key_with_modifiers, function_key, key_char, mouse_report, paste as paste_bytes,
    CursorKey as TermCursorKey, Modifiers as TermModifiers, MouseAction, MouseButton, MouseEvent,
    PASTE_END, PASTE_START,
};
pub use terminal::{is_wide, Cell as TerminalCell, Color as TerminalColor, Pen as TerminalPen, Screen as TerminalScreen, SCROLLBACK_LIMIT};
pub use url::{FormMerge, ImportedConnection, UrlParseError};
pub use workspace::{EntryKind, History, Tab, TextLanguage};
