//! Doyah Studio · Windows 侧 · 构建脚本（`build.rs`）
//!
//! 除了 Tauri 的常规构建动作（`tauri_build::build()`），这里还把
//! **「这一份包是哪一次构建」注入二进制**（S-073a · 前门裁决 `T-20261007-085`）：
//!
//!   · `DOYAH_BUILD_HEAD` = 构建时工作树所在提交的短号（`git rev-parse --short HEAD`）；
//!   · `DOYAH_BUILD_TIME` = 构建时刻（本机本地时间，`MM-dd HH:mm`）。
//!
//! 用途：窗口标题里显示这段标识（见 `src/lib.rs` 的窗口 setup），
//! 让人**打开包就能看出「测的是哪一份」**——原先标题写死 `Doyah Studio`，
//! 一份 debug、一份 release、一周前的旧包长得一模一样。
//!
//! ## 刷新面（S-073e · 前门裁决 `T-20261008-016`）
//!
//! 由头（已复现）：只改 `App/tools/**` 并提交后**重建** ⇒ 界面徽标**滞留旧短号**
//! （`python App/tools/check-build-stamp.py` 判 `FAIL`）。根因 = 本脚本原先只声明
//! `rerun-if-changed=build.rs` 与 `=src` ⇒ 改 `App/tools/**` 时 build.rs 不重跑、
//! 徽标取旧值。两手都做：
//!
//!   ① **首选**：徽标值优先取**构建 / 出包脚本**（`App/tools/build-release.py`）在每次
//!      构建时写进环境的 `DOYAH_BUILD_HEAD` / `DOYAH_BUILD_TIME` —— 值由 cargo 之外的
//!      一方给定，构建脚本不现算也能刷新。
//!   ② **兜底**：`rerun-if-changed` 覆盖面**补齐**到凡「进产物」的输入（`App/src/**` ·
//!      `App/tools/**` · 工作区与包的 `Cargo.toml` · `Cargo.lock` · `tauri.conf.json` ·
//!      图标）——即便直接 `cargo build`（没经过出包脚本），输入一变就重跑本脚本刷新徽标。
//!
//! **不声明 `cargo:rerun-if-env-changed`**（有意为之）：出包脚本每次构建都会把当前时刻
//! 写进 `DOYAH_BUILD_TIME`，若让环境变量也触发重跑，则「什么都没改也重建」会把标题里的
//! 时刻一并刷掉（判据第 ③ 条要求此情形下 `TITLE=` 逐字不变）。徽标该在**输入变更**时刷新。
//!
//! 纪律（卡面原文）：**取不到就写 `unknown`，绝不让构建失败**。

use std::process::Command;

/// 跑一条命令：成功且 stdout 去空白后非空才回内容；任何一步不成就 `None`（不 panic、不打印噪音）。
fn run_quiet(program: &str, args: &[&str]) -> Option<String> {
    let output = Command::new(program).args(args).output().ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if text.is_empty() {
        None
    } else {
        Some(text)
    }
}

/// 取**构建 / 出包脚本写入**的环境变量（首选面）；形状不合就当没给
/// （宁可自己现算，也不把怪值写进窗口标题）。
fn from_env(name: &str, accept: fn(&str) -> bool) -> Option<String> {
    let value = std::env::var(name).ok()?;
    let value = value.trim().to_string();
    if value.is_empty() || !accept(&value) {
        None
    } else {
        Some(value)
    }
}

/// 提交短号的形状：7~40 位**小写**十六进制（`git --short` 的写法；
/// 判据脚本的正则是 `[0-9a-f]{7,}`，大写会被它判成不符 ⇒ 这里也按小写认）。
fn is_head(text: &str) -> bool {
    let bytes = text.as_bytes();
    (7..=40).contains(&bytes.len())
        && bytes
            .iter()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(b))
}

/// 严格校验 `MM-dd HH:mm` 的形状：只认这一种写法，别的字符串当取不到。
///
/// 为什么宁可当取不到也不原样写进去：判据按这个形状逐字对，写进一段「带区域差异的怪串」
/// 会让窗口标题看起来像坏了；退成 `unknown` 至少是**诚实的**。
fn is_stamp(text: &str) -> bool {
    let b = text.as_bytes();
    b.len() == 11
        && b[2] == b'-'
        && b[5] == b' '
        && b[8] == b':'
        && b[0].is_ascii_digit()
        && b[1].is_ascii_digit()
        && b[3].is_ascii_digit()
        && b[4].is_ascii_digit()
        && b[6].is_ascii_digit()
        && b[7].is_ascii_digit()
        && b[9].is_ascii_digit()
        && b[10].is_ascii_digit()
}

/// 提交短号（取不到 ⇒ `unknown`）。
///
/// 用 `--short HEAD` 而不是带上 `--dirty` 之类的花活：口径就是卡面写的那一句，
/// 判据脚本对账时用的也是同一条命令。
fn build_head() -> String {
    run_quiet("git", &["rev-parse", "--short", "HEAD"]).unwrap_or_else(|| "unknown".to_string())
}

/// 构建时刻（本地时间，取不到 ⇒ `None`）。
///
/// 走 PowerShell 的**固定格式串 + InvariantCulture**：格式串本身把时间分隔符钉成 `:`
/// （某些区域默认是 `.`，直接用 `%DATE%` / `%TIME%` 会被区域带偏）。
/// 只借标准库 `std::process`，**不加任何依赖**（卡面禁止引新 crate）。
fn build_time() -> Option<String> {
    const PS: &str = "(Get-Date).ToString('MM-dd HH:mm', \
                      [System.Globalization.CultureInfo]::InvariantCulture)";
    for program in ["powershell.exe", "pwsh.exe"] {
        if let Some(text) = run_quiet(program, &["-NoProfile", "-NonInteractive", "-Command", PS]) {
            if is_stamp(&text) {
                return Some(text);
            }
        }
    }
    None
}

fn main() {
    // ① 首选：构建 / 出包脚本写了就用它，没写（直接 `cargo build`）再自己现算。
    let head = from_env("DOYAH_BUILD_HEAD", is_head).unwrap_or_else(build_head);
    let time = from_env("DOYAH_BUILD_TIME", is_stamp)
        .or_else(build_time)
        .unwrap_or_else(|| "unknown".to_string());

    println!("cargo:rustc-env=DOYAH_BUILD_HEAD={head}");
    println!("cargo:rustc-env=DOYAH_BUILD_TIME={time}");

    // ② 兜底：`rerun-if-changed` 覆盖面补齐 —— 凡「进产物」的输入都要声明，
    //    否则增量构建就会复用旧徽标。路径相对本包 `Cargo.toml` 所在目录（`App/src-tauri`）。
    for path in [
        "build.rs",          // 本脚本
        "tauri.conf.json",   // 窗口 / 打包配置
        "icons",             // 打包图标
        "Cargo.toml",        // 本包清单
        "src",               // App/src-tauri/src（Rust 外壳本体）
        "../../src",         // App/src（前端源码；进产物的输入）
        "../../tools",       // App/tools（构建 / 出包脚本 —— S-073e 的由头就在这一行）
        "../../Core",        // 领域层（path 依赖，进产物）
        "../../Db",          // 领域层（path 依赖，进产物）
        "../../Cli",         // 工作区成员
        "../../Cargo.toml",  // 工作区清单
        "../../Cargo.lock",  // 工作区锁
    ] {
        println!("cargo:rerun-if-changed={path}");
    }

    tauri_build::build()
}
