//! **生成历史**（`FR-AI-02` 的回看面）—— 「刚才问了什么、模型给了什么、用了几次」留一份本地清单。
//!
//! 契约等价物：macOS 侧 `Core/AgentSqlHistory.swift`。
//!
//! ## 这一层管什么、不管什么
//!
//! - **管**：一条记录的**形状**（问句 / SQL / 解释 / 用到的表 / 模型 / 时刻）、**长度截断**、
//!   **条数上限淘汰**、坏文件的**空账兜底**、以及序列化往返。
//! - **不管**落盘位置（在外壳 `App/src-tauri/src/agent_settings.rs`，与配额台账同目录、分两份文件）。
//! - **不管**「该不该发」：能不能外发由 `agent::Gate` / `agent_config::evaluate` 判；本文件只在
//!   **已经成功拿到结果之后**记一条。
//!
//! ## 四条口径（每条都有对应形状）
//!
//! ① **只记成功的那一次**：被闸门挡住 / 被配额挡住 / HTTP 报错 / 解析失败 ⇒ 一条都不记。历史是
//!    「可回看的结果清单」，不是请求日志 —— 请求日志是审计面（`agent::AuditEntry`）的事，两份不混。
//! ② **坏账不锁人**：文件坏了 / 字段缺了 ⇒ 当空历史（与配额台账同口径），丢的只是「回看」，
//!    不影响生成功能本身。
//! ③ **有界**：最多 [`MAX_ENTRIES`] 条、问句 [`MAX_QUESTION_CHARS`] 字、SQL [`MAX_SQL_CHARS`] 字。
//!    截断时**打标记**（`questionTruncated` / `sqlTruncated`），让界面能如实说「这里看到的不是全文」——
//!    原文归档走「存成已保存查询」那条路，不靠历史兼职。
//! ④ **时间由调用方传入**（`at_secs`）：本层不读系统时钟，单测才能钉住顺序。

use serde::{Deserialize, Serialize};

/// 最多留多少条（超出淘汰最老的）。文件不能无限长，界面也要能一屏扫完。
pub const MAX_ENTRIES: usize = 20;

/// 问句最多留多少字（按**字符**数，不是字节 —— 否则中文会被切成半个字）。
pub const MAX_QUESTION_CHARS: usize = 500;

/// SQL 最多留多少字（理由同上；一段 SELECT 通常远小于这个数）。
pub const MAX_SQL_CHARS: usize = 4_000;

/// 解释文字最多留多少字。
pub const MAX_EXPLANATION_CHARS: usize = 1_000;

/// 一条生成记录。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryEntry {
    /// 用户问的那句话（可能被截断，见 `question_truncated`）。
    pub question: String,
    /// 生成的 SQL（可能被截断，见 `sql_truncated`）。
    pub sql: String,
    /// 模型的解释（代码块之外的文字；可为空）。
    #[serde(default)]
    pub explanation: String,
    /// 这条 SQL 里点到、且当时 schema 真有的表（`schema.table`）。
    #[serde(default)]
    pub tables_used: Vec<String>,
    /// 实际使用的模型名（端点换了模型名，回看时才分得清）。
    #[serde(default)]
    pub model: String,
    /// 记下来的时刻（epoch 秒；0 = 不知道）。
    #[serde(default)]
    pub at_secs: u64,
    /// 问句被截断过（界面要如实说）。
    #[serde(default)]
    pub question_truncated: bool,
    /// SQL 被截断过。
    #[serde(default)]
    pub sql_truncated: bool,
}

impl HistoryEntry {
    /// 造一条记录：**在这里一次性做截断与打标记**，别让调用点各截一遍。
    pub fn record(
        question: &str,
        sql: &str,
        explanation: &str,
        tables_used: Vec<String>,
        model: &str,
        at_secs: u64,
    ) -> Self {
        let (question, question_truncated) = clip(question.trim(), MAX_QUESTION_CHARS);
        let (sql, sql_truncated) = clip(sql.trim(), MAX_SQL_CHARS);
        let (explanation, _) = clip(explanation.trim(), MAX_EXPLANATION_CHARS);
        Self {
            question,
            sql,
            explanation,
            tables_used,
            model: model.to_string(),
            at_secs,
            question_truncated,
            sql_truncated,
        }
    }

    /// 这条记录有没有内容（问句与 SQL 都空 ⇒ 是垃圾行，读盘时丢掉）。
    pub fn is_meaningful(&self) -> bool {
        !self.question.is_empty() || !self.sql.is_empty()
    }
}

/// 历史台账（落盘的那份）。`entries` **按时间升序**（最老在前），呈现时用 [`Self::recent`] 倒过来。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryLedger {
    /// 记录（升序，最老在前）。
    #[serde(default)]
    pub entries: Vec<HistoryEntry>,
}

impl HistoryLedger {
    /// 从落盘文本读一份账。
    ///
    /// **任何读不懂的东西都当空账**（口径 ②）：历史读不出来不该让生成功能整个不可用；
    /// 该报的错在外壳（它会把「写不进去」如实说）。
    pub fn from_json(text: &str) -> Self {
        let mut ledger: HistoryLedger = match serde_json::from_str(text) {
            Ok(value) => value,
            Err(_) => return Self::default(),
        };
        ledger.entries.retain(HistoryEntry::is_meaningful);
        // 文件可能是手改的、也可能是旧版本写的：读进来就地压到上限（保最新）。
        ledger.trim_to_cap();
        ledger
    }

    /// 落盘文本（字段名是契约：`entries` / `atSecs` / `tablesUsed` / `questionTruncated` / `sqlTruncated`）。
    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| "{\"entries\":[]}".to_string())
    }

    /// 追加一条（最老的那条在超限时被淘汰）。
    pub fn append(&mut self, entry: HistoryEntry) {
        if !entry.is_meaningful() {
            return;
        }
        self.entries.push(entry);
        self.trim_to_cap();
    }

    /// 最近 `n` 条，**新的在前**（界面直接按这个顺序渲染，不再自己倒）。
    pub fn recent(&self, n: usize) -> Vec<HistoryEntry> {
        self.entries.iter().rev().take(n).cloned().collect()
    }

    /// 全部记录（新的在前）。
    pub fn all_recent(&self) -> Vec<HistoryEntry> {
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

/// 按**字符**截断；返回（文本, 是否截断过）。截断时补一个 `…`，让「这里不是全文」肉眼可见。
fn clip(text: &str, limit: usize) -> (String, bool) {
    if text.chars().count() <= limit {
        return (text.to_string(), false);
    }
    let mut out: String = text.chars().take(limit).collect();
    out.push('…');
    (out, true)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(question: &str, sql: &str, at: u64) -> HistoryEntry {
        HistoryEntry::record(question, sql, "", vec!["public.orders".to_string()], "m", at)
    }

    #[test]
    fn the_newest_entry_comes_first_when_read_by_the_ui() {
        let mut ledger = HistoryLedger::default();
        ledger.append(entry("第一问", "SELECT 1;", 100));
        ledger.append(entry("第二问", "SELECT 2;", 200));
        let recent = ledger.recent(10);
        assert_eq!(recent.len(), 2);
        assert_eq!(recent[0].question, "第二问", "界面拿到的第一条必须是最新的");
        assert_eq!(recent[1].question, "第一问");
        // 落盘顺序仍是升序（下一个读到这份文件的人不必猜方向）。
        assert_eq!(ledger.entries[0].question, "第一问");
    }

    #[test]
    fn the_cap_drops_the_oldest_and_never_grows_past_it() {
        let mut ledger = HistoryLedger::default();
        for i in 0..(MAX_ENTRIES as u64 + 5) {
            ledger.append(entry(&format!("问 {i}"), "SELECT 1;", i));
        }
        assert_eq!(ledger.len(), MAX_ENTRIES);
        assert_eq!(ledger.recent(1)[0].question, format!("问 {}", MAX_ENTRIES + 4));
        // 最老的五条真的没了。
        assert!(!ledger
            .entries
            .iter()
            .any(|e| e.question == "问 0" || e.question == "问 4"));
        assert!(ledger.entries.iter().any(|e| e.question == "问 5"));
    }

    #[test]
    fn a_hand_edited_file_that_is_too_long_is_trimmed_on_read() {
        let too_many: Vec<HistoryEntry> = (0..(MAX_ENTRIES as u64 + 3))
            .map(|i| entry(&format!("旧 {i}"), "SELECT 1;", i))
            .collect();
        let text = serde_json::to_string(&serde_json::json!({ "entries": too_many })).unwrap();
        let ledger = HistoryLedger::from_json(&text);
        assert_eq!(ledger.len(), MAX_ENTRIES, "读进来也要压到上限");
        assert_eq!(
            ledger.recent(1)[0].question,
            format!("旧 {}", MAX_ENTRIES + 2),
            "压上限必须保最新的那些"
        );
    }

    #[test]
    fn a_broken_or_empty_file_reads_as_empty_instead_of_breaking_generation() {
        assert!(HistoryLedger::from_json("这不是 JSON").is_empty());
        assert!(HistoryLedger::from_json("").is_empty());
        assert!(HistoryLedger::from_json("{\"entries\":\"x\"}").is_empty());
        assert!(HistoryLedger::from_json("{}").is_empty());
    }

    #[test]
    fn garbage_entries_with_neither_question_nor_sql_are_dropped() {
        let text = serde_json::json!({
            "entries": [
                { "question": "", "sql": "", "atSecs": 1 },
                { "question": "真问题", "sql": "SELECT 1;", "atSecs": 2 }
            ]
        })
        .to_string();
        let ledger = HistoryLedger::from_json(&text);
        assert_eq!(ledger.len(), 1);
        assert_eq!(ledger.entries[0].question, "真问题");
        // 追加口也守同一条。
        let mut ledger = HistoryLedger::default();
        ledger.append(entry("   ", "   ", 3));
        assert!(ledger.is_empty(), "空白记录不该占一格");
    }

    #[test]
    fn a_very_long_question_and_sql_are_clipped_by_characters_not_bytes() {
        let long_question: String = "查".repeat(MAX_QUESTION_CHARS + 10);
        let long_sql: String = "一".repeat(MAX_SQL_CHARS + 10);
        let record = HistoryEntry::record(&long_question, &long_sql, "", vec![], "m", 1);
        assert!(record.question_truncated, "问句超长却没打标记");
        assert!(record.sql_truncated, "SQL 超长却没打标记");
        // 字符数 = 上限 + 省略号；按字节切会把中文切成半个字（这里连字节边界都不该破）。
        assert_eq!(record.question.chars().count(), MAX_QUESTION_CHARS + 1);
        assert_eq!(record.sql.chars().count(), MAX_SQL_CHARS + 1);
        assert!(record.question.ends_with('…'));
        assert!(record.sql.ends_with('…'));
        // 正常长度的不该被打标记。
        let short = HistoryEntry::record("查订单", "SELECT 1;", "解释", vec![], "m", 2);
        assert!(!short.question_truncated);
        assert!(!short.sql_truncated);
    }

    #[test]
    fn the_ledger_survives_a_json_round_trip() {
        let mut ledger = HistoryLedger::default();
        ledger.append(HistoryEntry::record(
            "每天的订单数",
            "SELECT count(*) FROM public.orders;",
            "按天分组",
            vec!["public.orders".to_string()],
            "fake-model",
            1_700_000_000,
        ));
        let text = ledger.to_json();
        for key in [
            "\"entries\"",
            "\"question\"",
            "\"sql\"",
            "\"tablesUsed\"",
            "\"atSecs\"",
            "\"questionTruncated\"",
            "\"sqlTruncated\"",
        ] {
            assert!(text.contains(key), "落盘字段少了 {key}：{text}");
        }
        assert_eq!(HistoryLedger::from_json(&text), ledger);
    }
}
