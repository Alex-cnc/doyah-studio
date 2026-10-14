//! 平台能力表的**取值**解析（§8.6.1「前端不得按平台分支」的机械落点）。
//!
//! 口径：平台差异只能通过**取值**表达 —— 前端拿到的是 [`Availability`] 三档之一，
//! 组件里**不许**写「若 linux 则…」；差异也因此可以逐条登记（§10.9 / §10.10）。
//!
//! 语言无关：本模块只有三档与两张表（能力名 / 取值串），不含任何用户可见文案
//! （文案在语言表里，归前端面 —— 领域层不许硬编码展示文案）。

/// 一项平台能力的可用度。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Availability {
    /// 在（探到了）
    Present,
    /// 不在（探过，确实缺）
    Missing,
    /// 问不出来（未探 / 探不动 / 取值认不出）—— **最小假设档**，不是「不在」
    Unknown,
}

impl Availability {
    /// 解析取值串（大小写不敏感、两端空白裁掉）。
    ///
    /// **认不出 ⇒ [`Availability::Unknown`]**：与「缺」区分开 —— 这一档既不许被读成「有」，
    /// 也不许被读成「没有」（后者会把「没探到」说成「系统不支持」，是假结论）。
    pub fn parse(raw: &str) -> Self {
        match raw.trim().to_ascii_lowercase().as_str() {
            "present" => Availability::Present,
            "missing" => Availability::Missing,
            _ => Availability::Unknown,
        }
    }

    /// 回写成取值串（写出去的与读进来的同一张表，不许各自拼一份）。
    pub fn as_str(self) -> &'static str {
        match self {
            Availability::Present => "present",
            Availability::Missing => "missing",
            Availability::Unknown => "unknown",
        }
    }
}

/// 本端能力名表（**唯一出处**：CLI 的 `capabilities` 输出与判据都读它）。
///
/// 与 §8.6.4 的桌面集成各面一一对应：WebView 承载 / 密钥环 / 终端 PTY / 通知 / 剪贴板 / 托盘。
pub const CAPABILITY_NAMES: [&str; 6] = [
    "webview",
    "secret-service",
    "pty",
    "notifications",
    "clipboard",
    "tray",
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_three_known_values_case_insensitively() {
        assert_eq!(Availability::parse("present"), Availability::Present);
        assert_eq!(Availability::parse("  MISSING "), Availability::Missing);
        assert_eq!(Availability::parse("Unknown"), Availability::Unknown);
    }

    #[test]
    fn unrecognized_value_falls_back_to_unknown_not_missing() {
        // 认不出 ⇒ 最小假设档：不许被读成「缺」（那会把「没探到」说成「不支持」）
        assert_eq!(Availability::parse(""), Availability::Unknown);
        assert_eq!(Availability::parse("yes"), Availability::Unknown);
    }

    #[test]
    fn round_trips_through_as_str() {
        for value in [Availability::Present, Availability::Missing, Availability::Unknown] {
            assert_eq!(Availability::parse(value.as_str()), value);
        }
    }

    #[test]
    fn capability_table_covers_desktop_integration_faces() {
        assert_eq!(CAPABILITY_NAMES.len(), 6);
        assert_eq!(CAPABILITY_NAMES[0], "webview", "承载面排第一（缺它整端起不来）");
    }
}
