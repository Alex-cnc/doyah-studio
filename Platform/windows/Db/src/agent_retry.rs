//! **模型调用的失败分级与退避**（`FR-AI-30` ① 的领域层半）
//!
//! ## 这一层管什么、不管什么
//!
//! - **管**三件纯判定：① 这次失败**该不该再试一次**（分级）；② 该等多久（退避序列，含服务端 `Retry-After` 的夹取）；
//!   ③ 每一跳留一条**可显示的形状**（[`AttemptNote`]），界面照它说话。
//! - **不管**发请求、睡觉、记审计、扣配额 —— 那些都在外壳（`App/src-tauri/src/agent_generate.rs`）。
//!   所以本模块**没有 `std::thread::sleep`、没有 HTTP 客户端**，单测一秒内跑完。
//!
//! ## 三条口径（每条都有对应形状）
//!
//! ① **不是所有失败都值得再试**：`429` / `408` / `5xx` 与「超时 / 连不上」是**环境抖动**，等一会儿可能就好；
//!    `401` / `403` / `404` / `400` 是**填错了**（密钥、路径、请求体），再试一百次也只是把同一件事再撞一遍 ——
//!    这类必须**当场停**并把原因说清楚，不许拿重试掩盖。
//! ② **退避必须封顶且可配**：起点 [`RETRY_BASE_MS`]，每失败一次翻倍，封顶由用户配（`retryMaxMs`）——
//!    没有封顶的重试在离线端点上会变成「时钟被占满」，用户却以为程序卡死。
//! ③ **服务端的 `Retry-After` 优先，但仍夹在配的上限内**：它比我们拍的数更懂自己什么时候有空，
//!    但不能让它把界面挂在那儿几分钟（上限还是用户说了算）。
//!
//! 为什么不在这里决定「重试几次」：那是用户配的（`retryMax`），本层只按给定策略算间隔。

use serde::{Deserialize, Serialize};

/// 退避起点（毫秒）。第一次失败后等这么久，之后翻倍。
pub const RETRY_BASE_MS: u64 = 400;

/// 默认重试次数（**不含**第一次尝试）：一共最多 3 次请求。
pub const DEFAULT_RETRY_MAX: u32 = 2;

/// 默认退避上限（毫秒）。
pub const DEFAULT_RETRY_MAX_MS: u64 = 4_000;

/// 重试次数的允许上限（再多就是替用户烧额度了）。
pub const RETRY_MAX_CEILING: u32 = 3;

/// 退避上限的允许区间（毫秒）。
pub const RETRY_MAX_MS_FLOOR: u64 = 500;
/// 退避上限的允许区间（毫秒）。
pub const RETRY_MAX_MS_CEILING: u64 = 60_000;

/// 一次失败的**分级**。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RetryClass {
    /// 环境抖动：等一会儿再试有意义。
    Retryable,
    /// 填错了 / 协议不认：再试也不会有别的结果。
    Fatal,
}

impl RetryClass {
    /// 是否值得再试一次。
    pub fn is_retryable(self) -> bool {
        matches!(self, RetryClass::Retryable)
    }
}

/// 按 HTTP 状态码分级。
///
/// `408`（服务端等请求超时）/ `425`（太早）/ `429`（限流）/ `5xx`（服务端故障）⇒ 可重试；
/// 其余 4xx 与 3xx ⇒ 不可重试（3xx 我们不跟随重定向，见外壳的 `redirect(Policy::none())`：
/// 那说明端点地址写成了另一个地方，重试只会把密钥再递一次）。
pub fn classify_status(status: u16) -> RetryClass {
    match status {
        408 | 425 | 429 | 500..=599 => RetryClass::Retryable,
        _ => RetryClass::Fatal,
    }
}

/// 按**传输层**失败分级。
///
/// - 超时 ⇒ 可重试（这正是生产环境里最常见、也最该重试的一类）；
/// - 连不上（连接被拒 / DNS 暂时解析不出 / 连接被掐）⇒ 可重试：本机服务重启的那几秒正是它；
/// - 其余（TLS 握手、回包解不出、请求体本身有问题）⇒ 不可重试：那是配置或代码的事，等多久都不会变。
pub fn classify_transport(timed_out: bool, connect: bool) -> RetryClass {
    if timed_out || connect {
        RetryClass::Retryable
    } else {
        RetryClass::Fatal
    }
}

/// 退避策略（来自配置：`retryMax` / `retryMaxMs`）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RetryPolicy {
    /// 重试次数上限（不含第一次尝试）。
    pub max_retries: u32,
    /// 退避上限（毫秒）。
    pub max_ms: u64,
}

impl Default for RetryPolicy {
    fn default() -> Self {
        Self {
            max_retries: DEFAULT_RETRY_MAX,
            max_ms: DEFAULT_RETRY_MAX_MS,
        }
    }
}

impl RetryPolicy {
    /// 从配置取策略（越界的值在这里**夹回区间**：配置校验会点名，但重试这件事不该因为一格填错就退化成「一直重试」）。
    pub fn from_config(config: &crate::agent_config::AgentConfiguration) -> Self {
        Self {
            max_retries: config.retry_max.min(RETRY_MAX_CEILING),
            max_ms: config.retry_max_ms.clamp(RETRY_MAX_MS_FLOOR, RETRY_MAX_MS_CEILING),
        }
    }

    /// 还有没有下一次（`failed_attempt` = 刚刚失败的是第几次，从 1 起）。
    pub fn has_next(&self, failed_attempt: u32) -> bool {
        failed_attempt <= self.max_retries
    }

    /// 第 `failed_attempt` 次失败之后该等多久：起点 ×2 翻倍，封顶 `max_ms`。
    ///
    /// 例（起点 400 / 上限 1000）：第 1 次失败 ⇒ 400，第 2 次 ⇒ 800，第 3 次 ⇒ 1000（封顶）。
    pub fn delay_after(&self, failed_attempt: u32) -> u64 {
        let shift = failed_attempt.saturating_sub(1).min(20);
        let raw = RETRY_BASE_MS.saturating_mul(1u64 << shift);
        raw.min(self.max_ms).max(RETRY_BASE_MS.min(self.max_ms))
    }

    /// 有服务端 `Retry-After` 时以它为准（秒 → 毫秒），但**夹在配的上限内**。
    ///
    /// 夹取的两端：不短于起点（服务端说 0 秒时我们也不立刻重发，避免打断服务端刚腾出的一点空档），
    /// 不长于用户配的上限（否则界面会被挂住几分钟，用户以为卡死）。
    pub fn honour_retry_after(&self, failed_attempt: u32, retry_after_secs: Option<u64>) -> u64 {
        match retry_after_secs {
            Some(secs) => (secs.saturating_mul(1_000))
                .clamp(RETRY_BASE_MS.min(self.max_ms), self.max_ms),
            None => self.delay_after(failed_attempt),
        }
    }
}

/// 一跳的结局（**给界面看的形状**，不含任何正文 —— 正文里的服务端原文另走失败文案）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AttemptNote {
    /// 第几次尝试（从 1 起）。
    pub attempt: u32,
    /// 这一跳的结局：`ok` / `retryable` / `fatal`。
    pub outcome: String,
    /// HTTP 状态码（传输层失败时没有）。
    pub status: Option<u16>,
    /// 这一跳失败后**实际等了多久**（毫秒；成功或不再重试时 = 0）。
    pub delay_ms: u64,
    /// 一句给用户看的原因（不含密钥；失败文案已在外壳脱敏）。
    pub detail: String,
}

/// 结局短码（**键名即契约**：界面按它查语言表）。
pub const OUTCOME_OK: &str = "ok";
/// 结局短码：可重试的失败。
pub const OUTCOME_RETRYABLE: &str = "retryable";
/// 结局短码：不可重试的失败。
pub const OUTCOME_FATAL: &str = "fatal";

impl AttemptNote {
    /// 成功那一跳。
    pub fn ok(attempt: u32, status: Option<u16>) -> Self {
        Self {
            attempt,
            outcome: OUTCOME_OK.to_string(),
            status,
            delay_ms: 0,
            detail: String::new(),
        }
    }

    /// 失败那一跳（`delay_ms` = 之后真等了多久；0 = 不再重试）。
    pub fn failed(
        attempt: u32,
        class: RetryClass,
        status: Option<u16>,
        detail: String,
        delay_ms: u64,
    ) -> Self {
        Self {
            attempt,
            outcome: if class.is_retryable() {
                OUTCOME_RETRYABLE.to_string()
            } else {
                OUTCOME_FATAL.to_string()
            },
            status,
            delay_ms,
            detail,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::agent_config::AgentConfiguration;

    #[test]
    fn a_throttled_or_broken_server_is_retryable_and_a_bad_key_is_not() {
        for status in [408u16, 425, 429, 500, 502, 503, 504] {
            assert_eq!(
                classify_status(status),
                RetryClass::Retryable,
                "{status} 该重试"
            );
        }
        for status in [301u16, 400, 401, 403, 404, 413, 422] {
            assert_eq!(classify_status(status), RetryClass::Fatal, "{status} 不该重试");
        }
    }

    #[test]
    fn a_timeout_or_a_refused_connection_is_retryable_but_a_broken_body_is_not() {
        assert!(classify_transport(true, false).is_retryable());
        assert!(classify_transport(false, true).is_retryable());
        assert_eq!(classify_transport(false, false), RetryClass::Fatal);
    }

    #[test]
    fn the_backoff_doubles_and_stops_at_the_configured_ceiling() {
        let policy = RetryPolicy {
            max_retries: 3,
            max_ms: 1_000,
        };
        assert_eq!(policy.delay_after(1), RETRY_BASE_MS); // 400
        assert_eq!(policy.delay_after(2), RETRY_BASE_MS * 2); // 800
        assert_eq!(policy.delay_after(3), 1_000); // 封顶
        assert_eq!(policy.delay_after(9), 1_000); // 再翻也不会超过封顶
    }

    #[test]
    fn the_ceiling_is_never_below_the_base_so_a_tiny_setting_still_waits_a_little() {
        let policy = RetryPolicy {
            max_retries: 2,
            max_ms: 100, // 远小于起点
        };
        assert_eq!(policy.delay_after(1), 100);
        assert_eq!(policy.honour_retry_after(1, Some(30)), 100);
    }

    #[test]
    fn the_servers_retry_after_wins_but_only_within_the_ceiling() {
        let policy = RetryPolicy {
            max_retries: 2,
            max_ms: 4_000,
        };
        assert_eq!(policy.honour_retry_after(1, Some(30)), 4_000, "30 秒要被夹到上限");
        assert_eq!(policy.honour_retry_after(1, Some(1)), 1_000);
        assert_eq!(policy.honour_retry_after(1, Some(0)), RETRY_BASE_MS, "0 秒也不立刻重发");
        assert_eq!(policy.honour_retry_after(2, None), RETRY_BASE_MS * 2);
    }

    #[test]
    fn a_retry_budget_of_zero_means_one_attempt_only() {
        let policy = RetryPolicy {
            max_retries: 0,
            max_ms: 4_000,
        };
        assert!(!policy.has_next(1), "配 0 次重试时第一次失败就该停");
    }

    #[test]
    fn the_policy_from_config_clamps_out_of_range_values() {
        let config = AgentConfiguration {
            retry_max: 99,
            retry_max_ms: 10,
            ..Default::default()
        };
        let policy = RetryPolicy::from_config(&config);
        assert_eq!(policy.max_retries, RETRY_MAX_CEILING);
        assert_eq!(policy.max_ms, RETRY_MAX_MS_FLOOR);
    }

    #[test]
    fn attempt_notes_carry_the_keys_the_ui_reads() {
        let note = AttemptNote::failed(1, RetryClass::Retryable, Some(429), "限流".to_string(), 400);
        let json = serde_json::to_string(&note).unwrap();
        for key in ["\"attempt\"", "\"outcome\"", "\"status\"", "\"delayMs\"", "\"detail\""] {
            assert!(json.contains(key), "{key} 不在 {json}");
        }
        assert!(json.contains("\"retryable\""));
        let ok = AttemptNote::ok(2, Some(200));
        assert_eq!(ok.delay_ms, 0);
        assert_eq!(ok.outcome, OUTCOME_OK);
    }
}
