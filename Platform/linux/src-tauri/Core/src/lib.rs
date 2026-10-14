//! Doyah Studio · Linux 端领域层（骨架片）
//!
//! 三条口径（**判据** = `Platform/linux/Tools/check-linux-skeleton.py` 的 B / C 两条）：
//! - **零第三方依赖**（标准库之外一律不引）；
//! - **零 UI 依赖**（GUI / 平台 crate 不得出现 —— 判据按名判红并点名 `文件:行号`）；
//! - **零平台能力**（`std::os::unix` 一类平台专有 std 与 FFI 形状一律判红；平台能力只在 `Platform/Linux/`）。
//!
//! 本片落的两个模块：
//! - [`artifact`] —— 交付物身份四项（§8.6.3 的机械形态：目录 / 标签 / `sha256` / 构建时刻）；
//! - [`capability`] —— 平台能力表的**取值**解析（§8.6.1「前端不得按平台分支」的落点：差异只经取值表达）。

pub mod artifact;
pub mod capability;

/// 本端工程形态的版本口径（与 `Platform/linux/src-tauri/Cargo.toml` 的 `version` 同源）。
///
/// 发布产物的「一个值三处一致」口径（Windows 侧同形）由构建入口与判据守，本常量只给 CLI / 测试引用。
pub const PRODUCT_VERSION: &str = env!("CARGO_PKG_VERSION");
