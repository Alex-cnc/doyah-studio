//! **每小时请求配额**（`FR-AI-01` 的 `hourlyLimit` 落到实处的记账面 / `FR-AI-02` 的拦面）
//!
//! 契约等价物：macOS 侧 `Core/AgentHourlyQuota.swift`。
//!
//! ## 这一层管什么、不管什么
//!
//! - **管**「这一发能不能发 + 已经发了几次 + 还要等多久」：滑窗台账（默认 3600 秒）是**纯函数 + 一份可落盘的账**，
//!   时间由调用方传入（`now`），所以「一小时前的记录滑出窗口」这种事能在单测里一秒内验完。
//! - **不管**落盘位置与文件格式：读写成对（[`QuotaLedger::from_json`] / [`QuotaLedger::to_json`]）在这里，
//!   路径与 IO 在外壳（`App/src-tauri/src/agent_settings.rs`）。
//! - **不管**用户怎么填上限：1~100000 的合法性由 [`crate::agent_config`] 判，这里只负责按给定上限执行。
//!
//! ## 三条口径（每条都有对应形状）
//!
//! ① **计的是「真发出去的请求」**（含超时 / 报错的那一次）—— 要防的是重试风暴，不是给云端对账单；
//! ② **一本坏账不许把人锁死**：文件坏了、字段缺了、读不出来 ⇒ 当空账（宁可多放行一次，也不让用户干等一小时，
//!    而且这时外发的每一次仍受总开关与端点闸门约束）；
//! ③ **时钟回拨不永锁**：台账里出现「未来时刻」时按当下算 —— 否则把系统时间往前调一次，配额就锁死到那个时刻为止。
//!
//! 为什么不把计数放在内存里：应用一重启计数就归零 = 上限等于没有（用户重开五次就发五轮）。

use serde::{Deserialize, Serialize};

/// 滑窗宽度：一小时（与设置面上的「每小时上限」同义）。
pub const WINDOW_SECS: u64 = 3_600;

/// 台账（落盘的那份）。
///
/// 字段只有一条：本窗口内**真发出去**的请求时刻（epoch 秒，升序）。刻意不加「模型 / 问题 / 表名」——
/// 台账只服务于计数，不顺手把用户问了什么记到盘上。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaLedger {
    /// 本窗口内的请求时刻（epoch 秒）。
    #[serde(default)]
    pub sent_at: Vec<u64>,
}

/// 界面要的配额读数（`used` / `remaining` / 还要等多久）。
///
/// `used` 按**上限截断**：上限从 60 调到 5 时，窗口里可能躺着 20 次旧记录 —— 显示「20/5」只会让人困惑，
/// 显示「5/5」才是用户要的信息（这条不掩盖事实：`remaining` 一定是 0）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaStatus {
    /// 每小时上限（来自配置）。
    pub limit: u32,
    /// 本窗口内已用（按上限截断）。
    pub used: u32,
    /// 还剩几次（0 = 满了）。
    pub remaining: u32,
    /// 滑窗宽度（秒），界面用它解释「一小时」。
    pub window_secs: u64,
    /// 现在满了的话，还要等多少秒才有空位；没满 = 0。
    pub retry_after_secs: u64,
}

impl QuotaStatus {
    /// 现在能不能发。
    pub fn allowed(&self) -> bool {
        self.remaining > 0
    }
}

impl QuotaLedger {
    /// 从落盘文本读一份账。
    ///
    /// **任何读不懂的东西都当空账**（口径 ②）：这里不返回 `Result`，因为「配额账读不出来」不该变成
    /// 「界面起不来」或「一条都发不出去」—— 该报的错在外壳（它会如实说台账写不进去）。
    pub fn from_json(text: &str) -> Self {
        let mut ledger: QuotaLedger = match serde_json::from_str(text) {
            Ok(value) => value,
            Err(_) => return Self::default(),
        };
        // 0 是「不知道什么时候」，留着只会永远占一个位置。
        ledger.sent_at.retain(|at| *at > 0);
        ledger.sent_at.sort_unstable();
        ledger
    }

    /// 落盘文本（字段名是契约：`sentAt`）。
    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| "{\"sentAt\":[]}".to_string())
    }

    /// 当前读数（会顺手把窗口外的记录清掉 —— 幂等，不改「还有几次」的语义）。
    pub fn status(&mut self, now_secs: u64, limit: u32) -> QuotaStatus {
        self.normalize(now_secs);
        self.measure(now_secs, limit)
    }

    /// 判「这一发放不放行」，放行就**记账**（返回账后的读数）。
    ///
    /// 返回 `(是否放行, 读数)`：放行 = 已经记进账里，调用方**必须**把账落盘（否则重启就白记）；
    /// 不放行 = 账**没有被改动**（只清了窗口外的旧记录）。
    pub fn admit(&mut self, now_secs: u64, limit: u32) -> (bool, QuotaStatus) {
        self.normalize(now_secs);
        if (self.sent_at.len() as u64) < u64::from(limit) {
            self.sent_at.push(now_secs);
            self.sent_at.sort_unstable();
            (true, self.measure(now_secs, limit))
        } else {
            (false, self.measure(now_secs, limit))
        }
    }

    /// 归一：未来时刻按当下算 + 清掉窗口外的记录 + 保持升序。
    fn normalize(&mut self, now_secs: u64) {
        for at in &mut self.sent_at {
            if *at > now_secs {
                *at = now_secs;
            }
        }
        self.sent_at
            .retain(|at| now_secs.saturating_sub(*at) < WINDOW_SECS);
        self.sent_at.sort_unstable();
    }

    fn measure(&self, now_secs: u64, limit: u32) -> QuotaStatus {
        let count = self.sent_at.len() as u32;
        let remaining = limit.saturating_sub(count);
        let retry_after_secs = if remaining > 0 {
            0
        } else {
            // 满额时「最老的那一次」滑出窗口才有空位。
            match self.sent_at.first() {
                Some(oldest) => WINDOW_SECS
                    .saturating_sub(now_secs.saturating_sub(*oldest))
                    .max(1),
                None => 0,
            }
        };
        QuotaStatus {
            limit,
            used: count.min(limit),
            remaining,
            window_secs: WINDOW_SECS,
            retry_after_secs,
        }
    }
}

/// 现在（epoch 秒）。时间只在这一处取，别在调用点各写一遍。
pub fn now_secs() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_limit_of_one_admits_once_then_refuses_with_the_wait() {
        let mut ledger = QuotaLedger::default();
        let (admitted, status) = ledger.admit(10_000, 1);
        assert!(admitted);
        assert_eq!(status.used, 1);
        assert_eq!(status.remaining, 0);

        let (admitted, status) = ledger.admit(10_010, 1);
        assert!(!admitted, "上限 1 却放了第二发");
        assert_eq!(status.used, 1);
        assert_eq!(status.retry_after_secs, WINDOW_SECS - 10);
    }

    #[test]
    fn a_request_slides_out_of_the_window_after_an_hour() {
        let mut ledger = QuotaLedger {
            sent_at: vec![1_000],
        };
        let (admitted, _) = ledger.admit(1_000 + WINDOW_SECS - 1, 1);
        assert!(!admitted, "还没到一小时就放了第二发");
        let (admitted, status) = ledger.admit(1_000 + WINDOW_SECS, 1);
        assert!(admitted, "一小时前的记录没有滑出窗口");
        assert_eq!(status.used, 1);
        assert_eq!(status.remaining, 0);
    }

    #[test]
    fn the_reading_counts_every_admitted_request_inside_the_window() {
        let mut ledger = QuotaLedger::default();
        for now in [100u64, 200, 300] {
            assert!(ledger.admit(now, 60).0);
        }
        let status = ledger.status(400, 60);
        assert_eq!(status.used, 3);
        assert_eq!(status.remaining, 57);
        assert_eq!(status.retry_after_secs, 0);
        assert!(status.allowed());
    }

    #[test]
    fn lowering_the_limit_below_what_is_already_used_reads_as_full_not_as_a_weird_ratio() {
        let mut ledger = QuotaLedger {
            sent_at: vec![100, 200, 300, 400],
        };
        let status = ledger.status(500, 2);
        assert_eq!(status.used, 2, "读数要按上限截断，不显示 4/2");
        assert_eq!(status.remaining, 0);
        assert!(!status.allowed());
        assert!(status.retry_after_secs > 0);
    }

    #[test]
    fn a_clock_that_moves_backwards_does_not_lock_the_user_forever() {
        // 台账里有一个「未来」时刻（系统时间被往前调过）。
        let mut ledger = QuotaLedger {
            sent_at: vec![99_999],
        };
        let status = ledger.status(1_000, 1);
        assert_eq!(status.remaining, 0, "未来时刻仍算一次已用");
        // 一小时后（按当下算的 3600 秒）就该放行，而不是等到 99_999 + 3600。
        let (admitted, _) = ledger.admit(1_000 + WINDOW_SECS, 1);
        assert!(admitted, "时钟回拨把用户锁死了");
    }

    #[test]
    fn a_broken_ledger_file_reads_as_empty_instead_of_locking_the_user() {
        assert_eq!(QuotaLedger::from_json("这不是 JSON"), QuotaLedger::default());
        assert_eq!(QuotaLedger::from_json(""), QuotaLedger::default());
        assert_eq!(QuotaLedger::from_json("{\"sentAt\":\"x\"}"), QuotaLedger::default());
    }

    #[test]
    fn the_ledger_survives_a_json_round_trip() {
        let mut ledger = QuotaLedger::default();
        ledger.admit(1_700_000_000, 10);
        ledger.admit(1_700_000_100, 10);
        let text = ledger.to_json();
        assert!(text.contains("\"sentAt\""), "{text}");
        let mut back = QuotaLedger::from_json(&text);
        assert_eq!(back.sent_at, ledger.sent_at);
        assert_eq!(back.status(1_700_000_200, 10).used, 2);
    }

    #[test]
    fn zero_and_unknown_values_are_dropped_instead_of_holding_a_slot() {
        let ledger = QuotaLedger::from_json("{\"sentAt\":[0,1700000000,0]}");
        assert_eq!(ledger.sent_at, vec![1_700_000_000]);
    }

    #[test]
    fn a_zero_limit_admits_nothing() {
        let mut ledger = QuotaLedger::default();
        let (admitted, status) = ledger.admit(500, 0);
        assert!(!admitted);
        assert_eq!(status.remaining, 0);
        assert_eq!(status.used, 0);
    }
}
