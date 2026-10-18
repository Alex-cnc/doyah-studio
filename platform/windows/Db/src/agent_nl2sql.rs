//! **自然语言 → SQL**（`FR-AI-02` 的纯逻辑面）—— 请求装配 + 回包解析 + 「用到哪些表」的机械判定。
//!
//! 契约等价物：macOS 侧 `Core/AgentSqlGeneration.swift`。
//!
//! ## 这一层管什么、不管什么
//!
//! - **管**：把「用户问题 + 当前连接的表/列摘要」装成一次 OpenAI 兼容的 chat 请求；把回包里的
//!   代码块切成 SQL 与解释；用**真实 schema** 核出「这次生成用到了哪些表」（不采信模型自述）。
//! - **不管**：不外发（网络在外壳 `agent_generate.rs`）、不执行（本模块**结构上没有连接、没有执行器**，
//!   拿不到库就执行不了 —— 需求原文「生成结果永不自动执行」靠这条形状成立，不靠纪律）。
//! - **不管裁决**：能不能外发只由 [`crate::agent::Gate`] / [`crate::agent_config::evaluate`] 判；本文件不写第二份闸门。
//!
//! ## 口径
//!
//! - 外发内容 = **表名 + 列名 + 类型 + 用户问题**（不含行数据；上限 [`MAX_TABLES`] 张表，超出**如实报数**）；
//! - 提示词里明确要求「只给一个代码块、不要解释之外的客套、结果不会被自动执行」；
//! - 回包解析**宽容但如实**：围栏没有语言标记也认；一句 SQL 都不像就报可读失败，**不猜**；
//! - 「用到哪些表」只认当前 schema 里真有的表（大小写不敏感、按 `schema.name` 去重）。

use serde::{Deserialize, Serialize};

use crate::agent_config::AgentConfiguration;

/// 随请求一起外发的表数上限（再多就不只是贵，而是把 schema 淹掉、模型反而乱写）。
pub const MAX_TABLES: usize = 40;

/// 一列（只带名字与类型：**行数据不外发**）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ColumnBrief {
    /// 列名。
    pub name: String,
    /// 类型（`numeric(12,2)` 这种原文；空串表示没取到 —— 不编一个）。
    #[serde(default)]
    pub data_type: String,
}

/// 一张表（或视图）的摘要。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TableBrief {
    /// schema 名（可为空串：有些连接面给不出）。
    #[serde(default)]
    pub schema: String,
    /// 表名。
    pub name: String,
    /// 已加载的列（空数组 = 还没展开过，**不是「没有列」**）。
    #[serde(default)]
    pub columns: Vec<ColumnBrief>,
}

/// schema 摘要拼出来的结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TablesBriefing {
    /// 拼好的文本（逐行 `schema.table(col type, …)`）。
    pub text: String,
    /// 真正写进去的表数。
    pub included: usize,
    /// 因上限被丢掉的表数（**界面要如实说**）。
    pub dropped: usize,
}

/// 一次外发请求（`human` 是**摊给用户看的那份正文**，与 `body` 同源）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Outgoing {
    /// 完整 URL（端点 + `/chat/completions`，端点已带就不重复拼）。
    pub url: String,
    /// HTTP 正文（JSON 字符串）。
    pub body: String,
    /// 给人看的正文（= 用户消息原文；界面「先看要发什么」显示它）。
    pub human: String,
    /// 用到的模型名（回显用）。
    pub model: String,
}

/// 解析出来的一条答案。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Answer {
    /// 生成的 SQL（**只给文本，永不自动执行**）。
    pub sql: String,
    /// 模型给的解释（代码块之外的文字；没有就是空串）。
    pub explanation: String,
    /// 本次 SQL 里点到、且**当前 schema 真有**的表（`schema.name` 形态，去重、稳定序）。
    pub tables_used: Vec<String>,
}

/// 这一层可能的失败（可读原因，逐条对应一种「用户能看懂」的处境）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Nl2SqlError {
    /// 问题为空（**在装配请求之前就拒绝**，不白花一次外发）。
    EmptyQuestion,
    /// 回包不是合法的 chat 回包（JSON 坏了 / 没有 `choices`）。
    ReplyShape(String),
    /// 回包能读，但里面没有 SQL 代码块。
    NoSql(String),
}

impl Nl2SqlError {
    /// 机器短码（界面查语言表用）。
    pub const fn code(&self) -> &'static str {
        match self {
            Self::EmptyQuestion => "emptyQuestion",
            Self::ReplyShape(_) => "replyShape",
            Self::NoSql(_) => "noSql",
        }
    }

    /// 具体越界值 / 原文（没有就是空串）。
    pub fn detail(&self) -> &str {
        match self {
            Self::EmptyQuestion => "",
            Self::ReplyShape(detail) | Self::NoSql(detail) => detail,
        }
    }
}

impl std::fmt::Display for Nl2SqlError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::EmptyQuestion => write!(f, "问题还是空的：先写一句要查什么（比如「最近 7 天每天的订单数」）。"),
            Self::ReplyShape(detail) => write!(f, "模型回包读不出来：{detail}"),
            Self::NoSql(detail) => write!(f, "模型没有按约定给出 SQL 代码块：{detail}"),
        }
    }
}

impl std::error::Error for Nl2SqlError {}

/// 拼 schema 摘要（逐行 `schema.table(col type, …)`；超过 [`MAX_TABLES`] 截断并报数）。
pub fn brief_schema(tables: &[TableBrief]) -> TablesBriefing {
    let included = tables.len().min(MAX_TABLES);
    let mut lines: Vec<String> = Vec::with_capacity(included);
    for table in tables.iter().take(included) {
        let qualified = qualified_name(table);
        if table.columns.is_empty() {
            // 没展开过列就只给表名 —— 不写 `()` 冒充「这张表没有列」。
            lines.push(format!("- {qualified}"));
            continue;
        }
        let columns: Vec<String> = table
            .columns
            .iter()
            .map(|column| {
                let kind = column.data_type.trim();
                if kind.is_empty() {
                    column.name.clone()
                } else {
                    format!("{} {}", column.name, kind)
                }
            })
            .collect();
        lines.push(format!("- {qualified}({})", columns.join(", ")));
    }
    TablesBriefing {
        text: lines.join("\n"),
        included,
        dropped: tables.len().saturating_sub(included),
    }
}

fn qualified_name(table: &TableBrief) -> String {
    let schema = table.schema.trim();
    let name = table.name.trim();
    if schema.is_empty() {
        name.to_string()
    } else {
        format!("{schema}.{name}")
    }
}

/// 拼「用户消息」正文 = schema 摘要 + 问题 + 纪律三条。
///
/// 这份正文就是 [`Outgoing::human`]：用户点「先看要发什么」看到的就是它，
/// **看到什么就发什么**（同一个函数产出，不另写一份预览）。
pub fn user_message(briefing: &TablesBriefing, question: &str, dropped: usize) -> String {
    let mut out = String::new();
    out.push_str("数据库 schema（只有表名、列名与类型；没有行数据）：\n");
    if briefing.included == 0 {
        out.push_str("（本次没有加载到任何表：请在问题里直接写出表名）\n");
    } else {
        out.push_str(&briefing.text);
        out.push('\n');
    }
    if dropped > 0 {
        out.push_str(&format!("（另有 {dropped} 张表因上限未列出）\n"));
    }
    out.push_str("\n请只输出一段 SQL，满足下面这条需求：\n");
    out.push_str(question.trim());
    out.push_str("\n\n纪律：\n1. SQL 放在一个 ```sql 代码块里，代码块之外用一两句话说明用到哪些表、按什么条件筛选。\n2. 只写一条语句，不要分号外的额外语句，不要写 DDL 之外的破坏性语句。\n3. 生成的语句不会被自动执行，会交给人在编辑器里过一遍。\n");
    out
}

/// 系统消息（固定文案：**不含用户数据**，所以可以整份外发）。
pub const SYSTEM_PROMPT: &str = "你是 Doyah Studio 的 SQL 助手。用户会给你数据库的表与列，以及一句自然语言需求。\
你只输出一段 SQL（```sql 代码块）和一两句解释：用到了哪些表、按什么条件筛选。\
不要编造 schema 里没有的表或列；做不到就直说做不到，不要硬编。";

/// 装配一次请求（**不发**：网络在外壳那层）。
pub fn build_request(
    config: &AgentConfiguration,
    question: &str,
    tables: &[TableBrief],
) -> Result<Outgoing, Nl2SqlError> {
    let question = question.trim();
    if question.is_empty() {
        return Err(Nl2SqlError::EmptyQuestion);
    }
    let briefing = brief_schema(tables);
    let human = user_message(&briefing, question, briefing.dropped);
    let body = serde_json::json!({
        "model": config.model.trim(),
        "temperature": 0,
        "stream": false,
        "messages": [
            { "role": "system", "content": SYSTEM_PROMPT },
            { "role": "user", "content": human },
        ],
    })
    .to_string();
    Ok(Outgoing {
        url: chat_url(&config.endpoint),
        body,
        human,
        model: config.model.trim().to_string(),
    })
}

/// 端点 → `…/chat/completions`（已经带了就不再拼一层）。
pub fn chat_url(endpoint: &str) -> String {
    let base = endpoint.trim().trim_end_matches('/');
    if base.ends_with("/chat/completions") {
        base.to_string()
    } else {
        format!("{base}/chat/completions")
    }
}

/// 解析 chat 回包：取 `choices[0].message.content`，切成 SQL + 解释，再用 schema 核「用到哪些表」。
pub fn parse_reply(raw: &str, tables: &[TableBrief]) -> Result<Answer, Nl2SqlError> {
    let value: serde_json::Value = serde_json::from_str(raw).map_err(|e| {
        Nl2SqlError::ReplyShape(format!("不是 JSON（{e}）：{}", first_chars(raw, 160)))
    })?;
    // 服务端把错误放在 `error.message` 里时，把那句原话带出来（别只说「形状不对」）。
    if let Some(message) = value
        .get("error")
        .and_then(|error| error.get("message"))
        .and_then(|message| message.as_str())
    {
        return Err(Nl2SqlError::ReplyShape(format!("服务端返回错误：{message}")));
    }
    let content = value
        .get("choices")
        .and_then(|choices| choices.get(0))
        .and_then(|choice| choice.get("message"))
        .and_then(|message| message.get("content"))
        .and_then(|content| content.as_str())
        .ok_or_else(|| {
            Nl2SqlError::ReplyShape(format!(
                "没有 choices[0].message.content：{}",
                first_chars(raw, 160)
            ))
        })?;
    let (sql, explanation) = split_sql_and_explanation(content).ok_or_else(|| {
        Nl2SqlError::NoSql(format!("回包正文：{}", first_chars(content, 200)))
    })?;
    Ok(Answer {
        tables_used: tables_used(&sql, tables),
        sql,
        explanation,
    })
}

/// 把模型正文切成（SQL, 解释）：优先认 ``` 围栏（语言标记可有可无），否则认「整段以 SQL 关键字开头」。
pub fn split_sql_and_explanation(content: &str) -> Option<(String, String)> {
    let mut outside: Vec<&str> = Vec::new();
    let mut fenced: Option<Vec<&str>> = None;
    let mut current: Option<Vec<&str>> = None;
    for line in content.lines() {
        let trimmed = line.trim_start();
        if trimmed.starts_with("```") {
            match current.take() {
                Some(block) => {
                    if fenced.is_none() {
                        fenced = Some(block);
                    }
                }
                None => current = Some(Vec::new()),
            }
            continue;
        }
        match current.as_mut() {
            Some(block) => block.push(line),
            None => outside.push(line),
        }
    }
    // 围栏没闭合时，把已收的那段也当候选（模型偶尔会漏掉收尾的 ```）。
    let block = fenced.or(current);
    let explanation = outside.join("\n").trim().to_string();
    if let Some(block) = block {
        let sql = block.join("\n").trim().to_string();
        if !sql.is_empty() {
            return Some((sql, explanation));
        }
    }
    let bare = content.trim();
    if starts_with_sql_keyword(bare) {
        return Some((bare.to_string(), String::new()));
    }
    None
}

fn starts_with_sql_keyword(text: &str) -> bool {
    const KEYWORDS: [&str; 9] = [
        "SELECT", "WITH", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP", "EXPLAIN",
    ];
    let head = text.trim_start().to_ascii_uppercase();
    KEYWORDS
        .iter()
        .any(|keyword| head.starts_with(keyword) && head.as_bytes().get(keyword.len()).map_or(true, |b| !b.is_ascii_alphanumeric() && *b != b'_'))
}

/// SQL 里点到、且当前 schema **真有**的表（大小写不敏感；按 `schema.name` 去重并稳定排序）。
///
/// 这是「用到哪些表」的机械答案：**不采信模型自述**（它常把表名写错或漏写）。
pub fn tables_used(sql: &str, tables: &[TableBrief]) -> Vec<String> {
    let haystack = strip_quotes(&sql.to_ascii_lowercase());
    let mut hits: Vec<String> = Vec::new();
    for table in tables {
        let name = table.name.trim().to_ascii_lowercase();
        if name.is_empty() {
            continue;
        }
        if contains_identifier(&haystack, &name) {
            let qualified = qualified_name(table);
            if !hits.iter().any(|hit| hit.eq_ignore_ascii_case(&qualified)) {
                hits.push(qualified);
            }
        }
    }
    hits.sort();
    hits
}

/// 去掉单 / 双引号里的内容（字符串字面量里的 `'orders'` 不算「用到了 orders 这张表」）。
fn strip_quotes(sql: &str) -> String {
    let mut out = String::with_capacity(sql.len());
    let mut quote: Option<char> = None;
    let mut chars = sql.chars();
    while let Some(ch) = chars.next() {
        match quote {
            Some(active) => {
                if ch == active {
                    quote = None;
                }
                if active == '"' {
                    // 双引号在 SQL 里是**标识符**引号：内容保留（"Orders" 仍是一张表）。
                    out.push(ch);
                } else {
                    out.push(' ');
                }
            }
            None => {
                if ch == '\'' || ch == '"' {
                    quote = Some(ch);
                    out.push(ch);
                } else {
                    out.push(ch);
                }
            }
        }
    }
    out
}

fn contains_identifier(haystack: &str, needle: &str) -> bool {
    let bytes = haystack.as_bytes();
    let mut start = 0;
    while let Some(offset) = haystack[start..].find(needle) {
        let at = start + offset;
        // 前面允许是 `.`（`public.orders` 里的表名要给算上），但不许是标识符字符。
        let before_ok = at == 0
            || !bytes[at - 1].is_ascii_alphanumeric() && bytes[at - 1] != b'_';
        let after = at + needle.len();
        let after_ok = after >= bytes.len()
            || !bytes[after].is_ascii_alphanumeric() && bytes[after] != b'_';
        if before_ok && after_ok {
            return true;
        }
        start = at + needle.len();
    }
    false
}

fn first_chars(text: &str, limit: usize) -> String {
    let mut out: String = text.chars().take(limit).collect();
    if text.chars().count() > limit {
        out.push('…');
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config() -> AgentConfiguration {
        AgentConfiguration {
            enabled: true,
            endpoint: "https://api.example.com/v1".to_string(),
            model: "example-model".to_string(),
            ..Default::default()
        }
    }

    fn orders() -> TableBrief {
        TableBrief {
            schema: "public".to_string(),
            name: "orders".to_string(),
            columns: vec![
                ColumnBrief {
                    name: "id".to_string(),
                    data_type: "bigint".to_string(),
                },
                ColumnBrief {
                    name: "created_at".to_string(),
                    data_type: "timestamptz".to_string(),
                },
            ],
        }
    }

    fn reply_with(content: &str) -> String {
        serde_json::json!({
            "choices": [{ "message": { "role": "assistant", "content": content } }]
        })
        .to_string()
    }

    #[test]
    fn the_outgoing_body_carries_the_question_and_only_names_and_types() {
        let tables = vec![orders()];
        let outgoing = build_request(&config(), "最近 7 天每天的订单数", &tables).unwrap();
        assert_eq!(outgoing.url, "https://api.example.com/v1/chat/completions");
        assert_eq!(outgoing.model, "example-model");
        assert!(outgoing.body.contains("public.orders(id bigint, created_at timestamptz)"));
        assert!(outgoing.body.contains("最近 7 天每天的订单数"));
        // 正文里不出现任何密钥（密钥走请求头，由外壳那层加）。
        assert!(!outgoing.body.to_ascii_lowercase().contains("authorization"));
    }

    #[test]
    fn the_human_preview_is_the_same_text_that_gets_sent() {
        let tables = vec![orders()];
        let outgoing = build_request(&config(), "列一下订单", &tables).unwrap();
        let body: serde_json::Value = serde_json::from_str(&outgoing.body).unwrap();
        let sent = body["messages"][1]["content"].as_str().unwrap();
        assert_eq!(sent, outgoing.human, "预览与实发必须逐字同一份");
    }

    #[test]
    fn a_schema_larger_than_the_cap_is_truncated_and_the_dropped_count_is_reported() {
        let tables: Vec<TableBrief> = (0..MAX_TABLES + 5)
            .map(|i| TableBrief {
                schema: "public".to_string(),
                name: format!("t{i}"),
                columns: vec![],
            })
            .collect();
        let briefing = brief_schema(&tables);
        assert_eq!(briefing.included, MAX_TABLES);
        assert_eq!(briefing.dropped, 5);
        let outgoing = build_request(&config(), "随便", &tables).unwrap();
        assert!(outgoing.human.contains("另有 5 张表因上限未列出"), "{}", outgoing.human);
    }

    #[test]
    fn an_empty_question_is_refused_before_anything_is_built() {
        let err = build_request(&config(), "   ", &[]).unwrap_err();
        assert_eq!(err.code(), "emptyQuestion");
        assert!(err.to_string().contains("空的"));
    }

    #[test]
    fn a_fenced_reply_yields_the_sql_and_the_explanation() {
        let content = "用到了 orders 表。\n```sql\nSELECT count(*) FROM public.orders WHERE created_at > now() - interval '7 days';\n```\n按创建时间筛选。";
        let answer = parse_reply(&reply_with(content), &[orders()]).unwrap();
        assert!(answer.sql.starts_with("SELECT count(*)"));
        assert!(!answer.sql.contains("```"));
        assert!(answer.explanation.contains("用到了 orders 表"));
        assert_eq!(answer.tables_used, vec!["public.orders".to_string()]);
    }

    #[test]
    fn a_fence_without_a_language_tag_or_closing_marker_is_still_accepted() {
        let content = "```\nSELECT id FROM public.orders\n";
        let answer = parse_reply(&reply_with(content), &[orders()]).unwrap();
        assert_eq!(answer.sql, "SELECT id FROM public.orders");
    }

    #[test]
    fn a_bare_sql_reply_is_accepted() {
        let answer = parse_reply(&reply_with("SELECT id FROM public.orders;"), &[orders()]).unwrap();
        assert_eq!(answer.sql, "SELECT id FROM public.orders;");
        assert!(answer.explanation.is_empty());
        assert_eq!(answer.tables_used, vec!["public.orders".to_string()]);
    }

    #[test]
    fn prose_without_any_sql_is_refused_with_the_reply_quoted() {
        let err = parse_reply(&reply_with("这个库看起来没有订单表，做不了。"), &[orders()]).unwrap_err();
        assert_eq!(err.code(), "noSql");
        assert!(err.detail().contains("做不了"));
    }

    #[test]
    fn a_server_error_message_is_carried_out_verbatim() {
        let raw = serde_json::json!({ "error": { "message": "invalid api key" } }).to_string();
        let err = parse_reply(&raw, &[]).unwrap_err();
        assert_eq!(err.code(), "replyShape");
        assert!(err.detail().contains("invalid api key"), "{}", err.detail());
    }

    #[test]
    fn a_reply_without_choices_names_what_was_missing() {
        let err = parse_reply("{\"id\":\"x\"}", &[]).unwrap_err();
        assert_eq!(err.code(), "replyShape");
        assert!(err.detail().contains("choices"));
    }

    #[test]
    fn tables_used_ignores_string_literals_and_unknown_names() {
        let sql = "SELECT * FROM public.orders WHERE note = 'orders' AND id IN (SELECT order_id FROM public.missing_table)";
        let used = tables_used(sql, &[orders()]);
        assert_eq!(used, vec!["public.orders".to_string()]);
    }

    #[test]
    fn tables_used_is_case_insensitive_and_lists_each_table_once() {
        let sql = "select * from PUBLIC.ORDERS o join public.orders o2 on o.id = o2.id";
        let used = tables_used(sql, &[orders()]);
        assert_eq!(used, vec!["public.orders".to_string()]);
    }

    #[test]
    fn a_chat_url_that_already_ends_with_chat_completions_is_not_piled_up() {
        assert_eq!(
            chat_url("https://api.example.com/v1/chat/completions/"),
            "https://api.example.com/v1/chat/completions"
        );
        assert_eq!(chat_url("http://127.0.0.1:11434/v1"), "http://127.0.0.1:11434/v1/chat/completions");
    }
}
