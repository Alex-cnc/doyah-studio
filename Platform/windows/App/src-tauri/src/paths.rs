//! 数据落点：**一个应用一个家**（`DoyahStudio/`），Windows 与 Linux 各按本平台惯例取根。
//!
//! 为什么单拎出来：这套命令层现在被**两个外壳**共用（Windows 的 `%APPDATA%`、
//! Linux 的 `$XDG_DATA_HOME`）。原先每处各自 `std::env::var("APPDATA")`，取不到就退到
//! **当前目录** —— Windows 上退到 `.` 只是难看，Linux 上 `APPDATA` 根本不存在，
//! 于是所有配置 / 会话 / 归档都会写进「启动时的工作目录」，换个目录打开就全不见。
//!
//! 口径（与概设 §9.3.1「后端同源」一条配套）：
//!   - Windows：`%APPDATA%\DoyahStudio`（沿用既有位置，不迁数据）；
//!   - 其它（Linux / macOS 开发机）：`$XDG_DATA_HOME/doyah-studio`，无该变量时
//!     `$HOME/.local/share/doyah-studio`（XDG 基础目录规范），无 `HOME` 才退当前目录。
//!
//! **目录名带连字符**（`doyah-studio`）是 XDG 的惯例（小写、连字符）；Windows 侧保留
//! 历史拼法 `DoyahStudio`，两边各按本平台习惯，不做「统一成同一个字符串」的假整齐。

use std::path::PathBuf;

/// 应用数据根目录（存在与否不保证；调用方写文件前自己 `create_dir_all`）。
pub fn app_home() -> PathBuf {
    #[cfg(windows)]
    {
        // 取不到 `APPDATA` 才退当前目录 —— **不静默丢数据**，路径会回到界面上。
        if let Ok(base) = std::env::var("APPDATA") {
            if !base.trim().is_empty() {
                return PathBuf::from(base).join("DoyahStudio");
            }
        }
        PathBuf::from(".")
    }
    #[cfg(not(windows))]
    {
        if let Ok(base) = std::env::var("XDG_DATA_HOME") {
            if !base.trim().is_empty() {
                return PathBuf::from(base).join("doyah-studio");
            }
        }
        if let Ok(home) = std::env::var("HOME") {
            if !home.trim().is_empty() {
                return PathBuf::from(home).join(".local").join("share").join("doyah-studio");
            }
        }
        PathBuf::from(".")
    }
}

/// 应用数据根下的一个相对落点（`app_home().join(rel)`）。
pub fn app_path(rel: &str) -> PathBuf {
    app_home().join(rel)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 根目录必须是**绝对路径或明确的当前目录**，且以本平台的目录名结尾。
    #[test]
    fn app_home_has_a_platform_shaped_tail() {
        let home = app_home();
        let tail = home.file_name().and_then(|name| name.to_str()).unwrap_or("");
        #[cfg(windows)]
        assert_eq!(tail, "DoyahStudio");
        #[cfg(not(windows))]
        assert_eq!(tail, "doyah-studio");
    }

    /// `HOME` 有值时不得落到当前目录（这条就是原来那个 bug 的判据）。
    #[test]
    fn home_is_used_when_xdg_is_absent() {
        #[cfg(not(windows))]
        {
            let saved_xdg = std::env::var("XDG_DATA_HOME").ok();
            let saved_home = std::env::var("HOME").ok();
            std::env::set_var("XDG_DATA_HOME", "");
            std::env::set_var("HOME", "/tmp/doyah-home-probe");
            let got = app_home();
            assert_eq!(got, PathBuf::from("/tmp/doyah-home-probe/.local/share/doyah-studio"));
            match saved_xdg {
                Some(value) => std::env::set_var("XDG_DATA_HOME", value),
                None => std::env::remove_var("XDG_DATA_HOME"),
            }
            match saved_home {
                Some(value) => std::env::set_var("HOME", value),
                None => std::env::remove_var("HOME"),
            }
        }
    }
}
