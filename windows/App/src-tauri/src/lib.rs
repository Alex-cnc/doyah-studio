//! Doyah Studio · Windows 侧表示层外壳（Tauri 2）—— 命令层
//!
//! 分工：**命令只做转发**，逻辑全在 `query.rs`（那样才 `cargo test` 判得了；窗口在无人值守里起不来）。
//! 前端命令名与这里的注册项的一致性由 `tests/ipc_contract.rs` 双向判（前端 `invoke` 一个没注册的
//! 名字是**运行时静默失败**，靠人记不住）。

mod query;

pub use query::{DatasetSummary, GridWindowPayload, ViewCache, MAX_WINDOW_ROWS};

use std::sync::Mutex;
use tauri::State;

/// 外壳状态：视图缓存（数据集 + 排序置换）。tauri 里跨命令共享的唯一可变状态。
pub struct ShellState(pub Mutex<ViewCache>);

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
    let mut cache = state.0.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
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
    let mut cache = state.0.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    cache.window(&query::ViewRequest { rows, cols, seed, order_desc, start, len })
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(ShellState(Mutex::new(ViewCache::new())))
        .invoke_handler(tauri::generate_handler![app_info, dataset_summary, grid_window])
        .run(tauri::generate_context!())
        .expect("启动 Doyah Studio Windows 外壳失败");
}
