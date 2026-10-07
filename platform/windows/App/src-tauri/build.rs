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
//! 纪律（卡面原文）：**取不到就写 `unknown`，绝不让构建失败** ——
//! 构建标识是辅助信息，不该因为环境里没有 git / 取不到本地时刻就把整份包卡死。

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

/// 提交短号（取不到 ⇒ `unknown`）。
///
/// 用 `--short HEAD` 而不是带上 `--dirty` 之类的花活：口径就是卡面写的那一句，
/// 判据脚本对账时用的也是同一条命令。
fn build_head() -> String {
    run_quiet("git", &["rev-parse", "--short", "HEAD"]).unwrap_or_else(|| "unknown".to_string())
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

/// 构建时刻（本地时间，取不到 ⇒ `unknown`）。
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
    let head = build_head();
    let time = build_time().unwrap_or_else(|| "unknown".to_string());

    println!("cargo:rustc-env=DOYAH_BUILD_HEAD={head}");
    println!("cargo:rustc-env=DOYAH_BUILD_TIME={time}");

    // 源码一动就重跑本脚本 ⇒ 窗口标题里的构建标识（尤其时刻）跟着这次构建刷新，
    // 不会拿上一次构建的旧值糊在新包上。
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=src");

    tauri_build::build()
}
