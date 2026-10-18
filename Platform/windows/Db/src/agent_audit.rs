//! **外发审计**（`FR-AI-09` 的审计半 · `NFR-AI-03` 的 Windows 落点）—— 每一次「外发尝试」留一条痕。
//!
//! 契约等价物：macOS 侧 `Core/AgentAudit.swift` 的 `AgentActionRecord`（模型调用那一档）。
//!
//! ## 为什么与生成历史（`agent_history`）分成两份
//!
//! - **历史**回答「我以前问过什么、模型给了什么」，只记**成功**的那一次；
//! - **审计**回答「系统到底往外发过什么、有没有一次是被挡住的」——**成功与失败都要记**，
//!   被闸门 / 配额挡住的那一次也要留（「为什么没发出去」和「发了什么」一样是要交代的事）。
//!
//! 两份口径不同 ⇒ 两个模块、两个文件（`agent-history.json` / `agent-audit.json`）。合成一份会让
//! 「只记成功」这条历史口径被审计的「全记」污染。
//!
//! ## 四条口径（每条都有对应形状）
//!
//! ① **先抹再存**：问句 / 失败原因 / 端点里形似凭据的片段，在**写入这一层**就按 `agent::redact` 抹掉 ——
//!    审计文件是要给人看、给导出带走的，不能指望每个调用点都记得抹。
//! ② **键集合是白名单**：结构上**没有**承载结果集行数据的字段（同 `NFR-AI-01`）。有单测钉住键集合。
//! ③ **有界**：最多 [`MAX_ENTRIES`] 条、摘要 [`MAX_SUMMARY_CHARS`] 字、原因 [`MAX_DETAIL_CHARS`] 字；
//!    超限淘汰最老的那条（审计不是无底账本，界面也要一屏扫完）。
//! ④ **坏账不锁人**：文件坏了 / 字段缺了 ⇒ 当空账（丢的只是「查看」，不影响生成功能）；时间由调用方传入。

use serde::{Deserialize, Serialize};

use crate::agent::redact;

/// 最多留多少条（超出淘汰最老的）。
pub const MAX_ENTRIES: usize = 200;

/// 问句摘要最多多少字（按**字符**数，不是字节）。
pub const MAX_SUMMARY_CHARS: usize = 300;

/// 失败原因 / 决策理由最多多少字。
pub const MAX_DETAIL_CHARS: usize = 400;

/// 一次外发尝试的结局。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum AuditVerdict {
    /// 真的发出去了，并且拿到了可解析的回包。
    #[default]
    Ok,
    /// 发了但失败（连不上 / 超时 / HTTP 非 2xx / 回包解析失败）。
    Failed,
    /// **一条请求都没发**：外发闸门不放行（总开关关 / 配置不全）。
    Blocked,
    /// **一条请求都没发**：本小时配额已满。
    Throttled,
}

impl AuditVerdict {
    /// 这一次到底有没有出网（界面据此分色；也是「零外发」这条承诺的机械读数）。
    pub fn left_the_machine(self) -> bool {
        matches!(self, Self::Ok | Self::Failed)
    }
}

/// 一条审计记录。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AuditRecord {
    /// 时刻（epoch 秒；0 = 不知道）。
    #[serde(default)]
    pub at_secs: u64,
    /// 结局。
    pub verdict: AuditVerdict,
    /// 这一次用的模型名（被挡住时是「本来会用」的那个）。
    #[serde(default)]
    pub model: String,
    /// 目标端点（**已脱敏**：`https://user:pw@host` 的口令段会被抹掉）。
    #[serde(default)]
    pub endpoint: String,
    /// 问句摘要（**已脱敏**、超长截断）。
    #[serde(default)]
    pub summary: String,
    /// 失败原因 / 决策理由（**已脱敏**）。
    #[serde(default)]
    pub detail: String,
    /// 往返耗时（毫秒；没发出去的那几次是 0）。
    #[serde(default)]
    pub duration_ms: u64,
    /// 随请求外发的表数（用户可据此判断「我到底发了多少东西出去」）。
    #[serde(default)]
    pub table_count: usize,
}

impl AuditRecord {
    /// 造一条记录：**在这里一次性抹凭据 + 截断**，别让调用点各抹一遍（总有地方会忘）。
    pub fn record(
        verdict: AuditVerdict,
        model: &str,
        endpoint: &str,
        question: &str,
        detail: &str,
        duration_ms: u64,
        table_count: usize,
        at_secs: u64,
    ) -> Self {
        Self {
            at_secs,
            verdict,
            model: clip(&redact(model.trim()), MAX_DETAIL_CHARS),
            endpoint: clip(&redact(endpoint.trim()), MAX_DETAIL_CHARS),
            summary: clip(&redact(question.trim()), MAX_SUMMARY_CHARS),
            detail: clip(&redact(detail.trim()), MAX_DETAIL_CHARS),
            duration_ms,
            table_count,
        }
    }

    /// 这条记录有没有内容（摘要与原因都空 ⇒ 垃圾行，读盘时丢掉）。
    pub fn is_meaningful(&self) -> bool {
        !self.summary.is_empty() || !self.detail.is_empty()
    }
}

/// 审计台账（落盘的那份）。`entries` **按时间升序**（最老在前），呈现时用 [`Self::all_recent`] 倒过来。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AuditLedger {
    /// 记录（升序，最老在前）。
    #[serde(default)]
    pub entries: Vec<AuditRecord>,
}

impl AuditLedger {
    /// 从落盘文本读一份账。**任何读不懂的东西都当空账**（口径 ④）。
    pub fn from_json(text: &str) -> Self {
        let mut ledger: AuditLedger = match serde_json::from_str(text) {
            Ok(value) => value,
            Err(_) => return Self::default(),
        };
        ledger.entries.retain(AuditRecord::is_meaningful);
        ledger.trim_to_cap();
        ledger
    }

    /// 落盘文本（字段名是契约：`atSecs` / `verdict` / `durationMs` / `tableCount` …）。
    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| "{\"entries\":[]}".to_string())
    }

    /// 追加一条（超限时淘汰最老的那条）。
    pub fn append(&mut self, record: AuditRecord) {
        if !record.is_meaningful() {
            return;
        }
        self.entries.push(record);
        self.trim_to_cap();
    }

    /// 最近 `n` 条，**新的在前**（界面直接照这个顺序渲染）。
    pub fn recent(&self, n: usize) -> Vec<AuditRecord> {
        self.entries.iter().rev().take(n).cloned().collect()
    }

    /// 全部记录（新的在前）。
    pub fn all_recent(&self) -> Vec<AuditRecord> {
        self.recent(self.entries.len())
    }

    /// 条数。
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// 空不空。
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    fn trim_to_cap(&mut self) {
        if self.entries.len() > MAX_ENTRIES {
            let drop = self.entries.len() - MAX_ENTRIES;
            self.entries.drain(0..drop);
        }
    }
}

/// 按**字符**截断；截断时补一个 `…`，让「这里不是全文」肉眼可见。
fn clip(text: &str, limit: usize) -> String {
    if text.chars().count() <= limit {
        return text.to_string();
    }
    let mut out: String = text.chars().take(limit).collect();
    out.push('…');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ok_record(question: &str, at: u64) -> AuditRecord {
        AuditRecord::record(
            AuditVerdict::Ok,
            "fake-model",
            "http://127.0.0.1:1/v1",
            question,
            "",
            42,
            1,
            at,
        )
    }

    #[test]
    fn the_field_set_is_a_whitelist_with_no_room_for_row_data() {
        // 口径 ②：**结构上**没有承载结果集行数据 / 密钥的字段。键集合就是那份白名单。
        let record = ok_record("每天的订单数", 100);
        let value = serde_json::to_value(&record).unwrap();
        let mut keys: Vec<&str> = value
            .as_object()
            .unwrap()
            .keys()
            .map(|key| key.as_str())
            .collect();
        keys.sort_unstable();
        assert_eq!(
            keys,
            vec![
                "atSecs",
                "detail",
                "durationMs",
                "endpoint",
                "model",
                "summary",
                "tableCount",
                "verdict",
            ],
            "键集合变了就是契约变了：先确认没有把行数据 / 密钥塞进来"
        );
    }

    #[test]
    fn a_password_in_the_question_is_redacted_before_it_is_written() {
        // 口径 ①：抹凭据在**写入这一层**做，调用点忘了也抹掉。
        let record = ok_record("SELECT * FROM users WHERE password = 'hunter2'", 1);
        assert!(
            !record.summary.contains("hunter2"),
            "口令被原样写进了审计：{}",
            record.summary
        );
        assert!(record.summary.contains("SELECT"), "抹凭据不该抹掉整句");
    }

    #[test]
    fn a_password_inside_the_endpoint_is_redacted() {
        let record = AuditRecord::record(
            AuditVerdict::Failed,
            "m",
            "https://alice:s3cret@llm.example.com/v1",
            "问",
            "",
            0,
            0,
            1,
        );
        assert!(
            !record.endpoint.contains("s3cret"),
            "端点里的口令被原样落盘：{}",
            record.endpoint
        );
        assert!(record.endpoint.contains("llm.example.com"));
    }

    #[test]
    fn the_cap_drops_the_oldest_and_never_grows_past_it() {
        let mut ledger = AuditLedger::default();
        for i in 0..(MAX_ENTRIES as u64 + 5) {
            ledger.append(ok_record(&format!("问 {i}"), i));
        }
        assert_eq!(ledger.len(), MAX_ENTRIES);
        assert_eq!(ledger.all_recent()[0].summary, format!("问 {}", MAX_ENTRIES + 4));
        assert!(!ledger.entries.iter().any(|e| e.summary == "问 0" || e.summary == "问 4"));
        assert!(ledger.entries.iter().any(|e| e.summary == "问 5"));
    }

    #[test]
    fn a_broken_file_reads_as_empty_instead_of_breaking_generation() {
        assert!(AuditLedger::from_json("{ 这不是 JSON").is_empty());
        assert!(AuditLedger::from_json("").is_empty());
        // 空账本身也是合法的（第一次运行就是空）。
        assert!(AuditLedger::from_json("{\"entries\":[]}").is_empty());
    }

    #[test]
    fn only_the_two_real_attempts_count_as_leaving_the_machine() {
        assert!(AuditVerdict::Ok.left_the_machine());
        assert!(AuditVerdict::Failed.left_the_machine());
        assert!(!AuditVerdict::Blocked.left_the_machine());
        assert!(!AuditVerdict::Throttled.left_the_machine());
    }
}
