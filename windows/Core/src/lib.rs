//! Doyah Studio · Windows 侧领域层（Rust）
//!
//! 约束（照 §8.5.1 / §8.5.3）：
//! - **零第三方依赖**（标准库之外一律不引 —— 判据 `check-core-boundary` 会扫）；
//! - **零 UI / 平台依赖**（无 `tauri`、无 `windows`、无 `winit` 之类）；
//! - 只做纯逻辑：本次落地 = 结果集（合成数据集 + 排序 / 筛选 / 窗口取数），
//!   它是 §8.5.6-3「结果网格压力基准」的被测对象。

pub mod dataset;
pub mod result_set;

pub use dataset::{generate, Column, Dataset, XorShift64};
pub use result_set::Window;
