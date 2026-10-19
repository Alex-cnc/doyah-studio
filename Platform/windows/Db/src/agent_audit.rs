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

/// 一次调用的 **token 用量**（`FR-AI-24` 的成本字段：输入 / 输出）。
///
/// **0 就是 0**：服务端没回 `usage` 时两个数都是 0，界面据此画「没记到」，
/// 不许按字数估一个数出来（编出来的成本比不报更糟）。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AuditUsage {
    /// 输入（提示词）token 数。
    #[serde(default)]
    pub input: u32,
    /// 输出（生成）token 数。
    #[serde(default)]
    pub output: u32,
}

impl AuditUsage {
    /// 造一份用量。
    pub fn new(input: u32, output: u32) -> Self {
        Self { input, output }
    }

    /// 有没有记到用量（两个都 0 ⇒ 服务端没给，界面照实说「没记到」）。
    pub fn is_known(self) -> bool {
        self.input > 0 || self.output > 0
    }

    /// 合计（只用于显示与汇总；不要拿它当「计费真值」——价格表不在本仓）。
    pub fn total(self) -> u32 {
        self.input.saturating_add(self.output)
    }
}

/// 从一段 OpenAI 兼容回包里取用量（`FR-AI-24` ②）。
///
/// 两套字段名都认：`prompt_tokens` / `completion_tokens`（OpenAI 经典）与
/// `input_tokens` / `output_tokens`（部分网关）。**认不出就回全 0**（不猜）。
pub fn parse_usage(value: &serde_json::Value) -> AuditUsage {
    let Some(usage) = value.get("usage") else {
        return AuditUsage::default();
    };
    let pick = |names: [&str; 2]| -> u32 {
        for name in names {
            if let Some(number) = usage.get(name) {
                if let Some(found) = number.as_u64() {
                    return u32::try_from(found).unwrap_or(u32::MAX);
                }
            }
        }
        0
    };
    AuditUsage::new(
        pick(["prompt_tokens", "input_tokens"]),
        pick(["completion_tokens", "output_tokens"]),
    )
}

/// 从一段回包**文本**里取用量（整段 JSON 回包 / 非流式响应用这个入口）。
///
/// 流式回包（SSE）整段拿去 `serde_json::from_str` 会失败 ⇒ 回全 0，这是**对的**：
/// 流里的用量由逐帧解析负责（`SseEvent::Usage`），不该在这里猜。
pub fn parse_usage_text(text: &str) -> AuditUsage {
    match serde_json::from_str::<serde_json::Value>(text) {
        Ok(value) => parse_usage(&value),
        Err(_) => AuditUsage::default(),
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
    /// 输入 token（`FR-AI-24`；`#[serde(default)]` ⇒ 旧账照读、按 0 显示「没记到」）。
    #[serde(default)]
    pub input_tokens: u32,
    /// 输出 token（同上）。
    #[serde(default)]
    pub output_tokens: u32,
}

impl AuditRecord {
    /// 这条记录的用量（显示与汇总都走这一处，别再各拆一遍两个字段）。
    pub fn usage(&self) -> AuditUsage {
        AuditUsage::new(self.input_tokens, self.output_tokens)
    }

    /// 补上用量（构造成本字段的唯一入口；调用点只许在这里加一次）。
    pub fn with_usage(mut self, usage: AuditUsage) -> Self {
        self.input_tokens = usage.input;
        self.output_tokens = usage.output;
        self
    }

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
            // 用量由 [`Self::with_usage`] 补（构造成本字段的唯一入口；这里按「没记到」起步）。
            input_tokens: 0,
            output_tokens: 0,
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

    /// 导出 JSON（缩进版，给人看 / 给别的工具读）：与落盘那份**同一组键**，只是排版不同。
    ///
    /// 落盘用紧凑版（省盘、好逐行 grep），导出用缩进版（用户会直接打开看）—— 两份都从
    /// `AuditLedger` 序列化出来，键集合不可能分叉。
    pub fn to_json_export(&self) -> String {
        serde_json::to_string_pretty(self).unwrap_or_else(|_| "{\"entries\":[]}".to_string())
    }

    /// CSV 的列（**白名单**，`FR-AI-24` ③）：与 JSON 是同一组键，顺序固定。
    ///
    /// 导出是给人拿去表格里看的，所以列名用结构体的驼峰键 —— 两处对不上，用户就会
    /// 拿到两套「同一个东西的两个名字」。
    pub const CSV_COLUMNS: [&'static str; 10] = [
        "atSecs",
        "verdict",
        "model",
        "endpoint",
        "inputTokens",
        "outputTokens",
        "durationMs",
        "tableCount",
        "summary",
        "detail",
    ];

    /// 导出 CSV（RFC 4180：含逗号 / 引号 / 换行的字段加引号并把内部引号翻倍）。
    ///
    /// 行序 = 落盘顺序（升序，最老在前）—— 导出的是一本账，不是一屏列表。
    pub fn to_csv(&self) -> String {
        let mut out = String::new();
        out.push_str(&Self::CSV_COLUMNS.join(","));
        out.push_str("\r\n");
        for entry in &self.entries {
            let verdict = match entry.verdict {
                AuditVerdict::Ok => "ok",
                AuditVerdict::Failed => "failed",
                AuditVerdict::Blocked => "blocked",
                AuditVerdict::Throttled => "throttled",
            };
            let cells = [
                entry.at_secs.to_string(),
                verdict.to_string(),
                entry.model.clone(),
                entry.endpoint.clone(),
                entry.input_tokens.to_string(),
                entry.output_tokens.to_string(),
                entry.duration_ms.to_string(),
                entry.table_count.to_string(),
                entry.summary.clone(),
                entry.detail.clone(),
            ];
            let line: Vec<String> = cells.iter().map(|cell| csv_cell(cell)).collect();
            out.push_str(&line.join(","));
            out.push_str("\r\n");
        }
        out
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

/// CSV 单元格（RFC 4180）：**只有**含逗号 / 引号 / 换行时才加引号 —— 全都加引号也能过
/// 表格软件，但导出的账会被 Excel 当成文本列，用户反而不好排序。
fn csv_cell(text: &str) -> String {
    let needs_quotes = text.contains(',')
        || text.contains('"')
        || text.contains('\n')
        || text.contains('\r');
    if needs_quotes {
        format!("\"{}\"", text.replace('"', "\"\""))
    } else {
        text.to_string()
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
                "inputTokens",
                "model",
                "outputTokens",
                "summary",
                "tableCount",
                "verdict",
            ],
            "键集合变了就是契约变了：先确认没有把行数据 / 密钥塞进来"
        );
    }

    #[test]
    fn an_old_record_without_token_fields_still_reads_and_shows_nothing_known() {
        // `FR-AI-24` 之前落盘的账没有 token 两个键 ⇒ 照读，且**不当成 0 个 token**，
        // 而是「没记到」（`is_known()` 为假，界面据此画「没记到」）。
        let old = "{\"entries\":[{\"atSecs\":10,\"verdict\":\"ok\",\"model\":\"m\",\
                   \"endpoint\":\"http://127.0.0.1:1/v1\",\"summary\":\"旧账\",\"detail\":\"\",\
                   \"durationMs\":7,\"tableCount\":0}]}";
        let ledger = AuditLedger::from_json(old);
        assert_eq!(ledger.len(), 1);
        let record = &ledger.all_recent()[0];
        assert_eq!(record.summary, "旧账");
        assert!(!record.usage().is_known(), "旧账没有用量，不许被读成 0 个 token");
        assert_eq!(record.usage().total(), 0);
    }

    #[test]
    fn the_usage_parser_accepts_both_field_namings_and_never_guesses() {
        let openai: serde_json::Value = serde_json::from_str(
            "{\"usage\":{\"prompt_tokens\":120,\"completion_tokens\":34,\"total_tokens\":154}}",
        )
        .unwrap();
        assert_eq!(parse_usage(&openai), AuditUsage::new(120, 34));

        let gateway: serde_json::Value =
            serde_json::from_str("{\"usage\":{\"input_tokens\":9,\"output_tokens\":1}}").unwrap();
        assert_eq!(parse_usage(&gateway), AuditUsage::new(9, 1));

        // 回包里没有 usage（很多本地端点默认不回）⇒ 全 0，不按字数估。
        let bare: serde_json::Value = serde_json::from_str("{\"choices\":[]}").unwrap();
        assert_eq!(parse_usage(&bare), AuditUsage::default());
        assert!(!parse_usage(&bare).is_known());
    }

    #[test]
    fn the_csv_header_is_the_whitelist_and_the_rows_carry_the_numbers() {
        let ledger = AuditLedger::from_json("{\"entries\":[]}");
        let csv = ledger.to_csv();
        assert_eq!(
            csv.trim_end_matches("\r\n"),
            AuditLedger::CSV_COLUMNS.join(","),
            "空账也要一行表头，且表头与白名单逐字一致"
        );

        let mut ledger = AuditLedger::default();
        ledger.append(ok_record("问一句", 5).with_usage(AuditUsage::new(120, 34)));
        let csv = ledger.to_csv();
        let mut lines = csv.split("\r\n").filter(|line| !line.is_empty());
        assert_eq!(lines.next().unwrap(), AuditLedger::CSV_COLUMNS.join(","));
        let row = lines.next().expect("一条记录应该有一行");
        let cells: Vec<&str> = row.split(',').collect();
        assert_eq!(cells.len(), AuditLedger::CSV_COLUMNS.len());
        assert_eq!(cells[0], "5");
        assert_eq!(cells[1], "ok");
        assert_eq!(cells[4], "120");
        assert_eq!(cells[5], "34");
        assert_eq!(cells[8], "问一句");
        assert!(lines.next().is_none(), "行数 = 记录数（不许多出空行）");
    }

    #[test]
    fn a_summary_with_commas_quotes_and_newlines_is_escaped_not_split() {
        let mut ledger = AuditLedger::default();
        ledger.append(
            AuditRecord::record(
                AuditVerdict::Ok,
                "m",
                "http://127.0.0.1:1/v1",
                "删掉 a, b 里的 \"c\"\n再跑一次",
                "",
                1,
                0,
                1,
            )
            .with_usage(AuditUsage::new(3, 4)),
        );
        let csv = ledger.to_csv();
        // 三行：表头 + 一条记录（摘要里的换行被引号包住，不再多出一行）。
        let rows: Vec<&str> = csv.split("\r\n").filter(|line| !line.is_empty()).collect();
        assert_eq!(rows.len(), 2, "摘要里的换行不该把一条记录拆成两行：{csv}");
        assert!(
            rows[1].contains("\"删掉 a, b 里的 \"\"c\"\"\n再跑一次\""),
            "逗号 / 引号 / 换行都必须按 RFC 4180 转义：{}",
            rows[1]
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
