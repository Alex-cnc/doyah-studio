//! **对话式诊断的模型调用面**（`FR-AI-03` 第二片的纯逻辑半）—— 资料块装配 + 回包取文本。
//!
//! 契约等价物：macOS 侧 `Core/AgentDiagnosis.swift` 的「问模型」那条路（同一份需求、各自的实现）。
//!
//! ## 为什么不是复用 `agent_nl2sql`
//!
//! `agent_nl2sql` 的系统提示词写死「只输出一段 SQL」，且 [`crate::agent_nl2sql::parse_reply`] 对
//! **没有 SQL 代码块**的正文直接判 `NoSql` —— 而诊断要的恰恰是「带依据编号的结论」，不是 SQL。
//! 把两条需求塞进同一份提示词，只会让两边都变形（生成时模型爱写散文、诊断时模型被逼着编 SQL）。
//! ⇒ 装配与解析**各一份**；**闸门 / 配额 / 审计不外分**（仍只在外壳那一处，本模块只装请求与取文本）。
//!
//! ## 这一层管什么、不管什么
//!
//! - **管**：把面板上那份资料块（与用户屏幕所见**同一份文本**）装成一次 OpenAI 兼容 chat 请求；
//!   从回包里取出 `choices[0].message.content` 的正文。
//! - **不管**：不外发（网络在外壳 `agent_generate.rs::ask`）、不裁决（闸门在 `agent_config::evaluate`）、
//!   不解读回复（「结论必须有依据」的逐条采纳/拒绝在界面侧 `workspace/agentDiagnosis.ts`）、**不执行**。
//!
//! ## 口径
//!
//! - 外发正文 = 用户看到的资料块 + 三条输出纪律（结论须带 `[依据: eN]`、证据里没有的不许说、建议写成一条语句）；
//! - 系统消息固定、**不含任何用户数据**；
//! - 回包解析**宽容但如实**：正文为空 ⇒ 判失败（不把空白当「模型说没事」）。

use serde::Serialize;

use crate::agent_config::AgentConfiguration;
use crate::agent_nl2sql::{chat_url, Outgoing};

/// 资料块的字符上限（防手滑把整个结果集贴进去）。界面 `buildBrief` 默认只给 4000，
/// 这里是**安全网**：真超过就砍并**如实写出砍了多少**，不静默截断。
pub const MAX_BRIEF_CHARS: usize = 8000;

/// 系统消息（固定文案：不含用户数据，所以可以整份外发）。
pub const SYSTEM_PROMPT: &str = "你是 Doyah Studio 的数据库诊断助手。用户会给你一段「诊断资料块」：里面有编号的证据（e1 执行计划、e2 锁与阻塞、e3 慢查询统计、e4 表访问统计）、\n每条证据的复跑 SQL，以及用户要诊断的那句 SQL。\n你的输出必须遵守三条纪律：\n1. 每条结论后面用 `[依据: e1,e2]` 的形式注明它来自哪几条证据；只许引用资料块里真有的编号。\n2. 资料块里没有的东西不要说。某份证据写着「未取到」时，不要假装看过它；需要它就先说明缺什么。\n3. 需要用户动手的建议写成一行 `建议: <一条只读 SQL>`（例如查 pg_stat_activity 或建索引前先看体积），\n   一次只给一条，不要给破坏性语句（DROP / TRUNCATE / DELETE / UPDATE 一律不给）。\n你的输出不会被执行，只会显示给人看；不要声称你执行过任何语句。";

/// 这一层可能的失败（逐条对应一种用户能看懂的处境）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AdvisorError {
    /// 资料块为空（**在装配请求之前就拒绝**，不白花一次外发）。
    EmptyBrief,
    /// 回包不是合法的 chat 回包（JSON 坏了 / 没有 `choices` / 服务端报错）。
    ReplyShape(String),
    /// 回包能读，但正文是空的（**不把空白当「没问题」**）。
    EmptyReply(String),
}

impl AdvisorError {
    /// 机器短码（界面查语言表用）。
    pub const fn code(&self) -> &'static str {
        match self {
            Self::EmptyBrief => "emptyBrief",
            Self::ReplyShape(_) => "replyShape",
            Self::EmptyReply(_) => "emptyReply",
        }
    }

    /// 具体原文（没有就是空串）。
    pub fn detail(&self) -> &str {
        match self {
            Self::EmptyBrief => "",
            Self::ReplyShape(detail) | Self::EmptyReply(detail) => detail,
        }
    }
}

impl std::fmt::Display for AdvisorError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::EmptyBrief => write!(f, "还没有诊断资料块：先把证据取回来（面板会自动取）。"),
            Self::ReplyShape(detail) => write!(f, "模型回包读不出来：{detail}"),
            Self::EmptyReply(detail) => write!(f, "模型回了个空正文：{detail}"),
        }
    }
}

impl std::error::Error for AdvisorError {}

/// 把资料块裁到上限内：超了从尾部砍，并**在正文里如实写出砍了多少字符**。
fn clip_brief(brief: &str) -> String {
    let total = brief.chars().count();
    if total <= MAX_BRIEF_CHARS {
        return brief.to_string();
    }
    let kept: String = brief.chars().take(MAX_BRIEF_CHARS).collect();
    format!(
        "{kept}\n（资料块过长：已从尾部砍掉 {} 字符，原文共 {total} 字符）",
        total - MAX_BRIEF_CHARS
    )
}

/// 拼「用户消息」正文 = 资料块 + 输出纪律三条。
///
/// 这份正文就是 [`Outgoing::human`]：**面板上给用户看的那份资料块就是发出去的那份**，
/// 除此之外只多一段固定纪律（不含任何用户数据）。
pub fn user_message(brief: &str) -> String {
    let mut out = String::new();
    out.push_str("下面是诊断资料块（证据编号 + 复跑 SQL + 要诊断的语句）：\n\n");
    out.push_str(&clip_brief(brief.trim()));
    out.push_str("\n\n请按三条纪律回答：结论带 `[依据: eN]`；资料块里没有的不说；建议写成一行 `建议: <只读 SQL>`。");
    out
}

/// 装配一次请求（**不发**：网络在外壳那层）。
pub fn build_request(config: &AgentConfiguration, brief: &str) -> Result<Outgoing, AdvisorError> {
    let brief = brief.trim();
    if brief.is_empty() {
        return Err(AdvisorError::EmptyBrief);
    }
    let human = user_message(brief);
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

/// 解析 chat 回包：只取 `choices[0].message.content` 的正文（**不解读**，解读在界面侧）。
pub fn parse_reply(raw: &str) -> Result<String, AdvisorError> {
    let value: serde_json::Value = serde_json::from_str(raw).map_err(|e| {
        AdvisorError::ReplyShape(format!("不是 JSON（{e}）：{}", first_chars(raw, 160)))
    })?;
    if let Some(message) = value
        .get("error")
        .and_then(|error| error.get("message"))
        .and_then(|message| message.as_str())
    {
        return Err(AdvisorError::ReplyShape(format!(
            "服务端返回错误：{message}"
        )));
    }
    let content = value
        .get("choices")
        .and_then(|choices| choices.get(0))
        .and_then(|choice| choice.get("message"))
        .and_then(|message| message.get("content"))
        .and_then(|content| content.as_str())
        .ok_or_else(|| {
            AdvisorError::ReplyShape(format!(
                "没有 choices[0].message.content：{}",
                first_chars(raw, 160)
            ))
        })?;
    let text = content.trim();
    if text.is_empty() {
        return Err(AdvisorError::EmptyReply(format!(
            "回包正文：{}",
            first_chars(raw, 200)
        )));
    }
    Ok(text.to_string())
}

/// 一段原文的前 `limit` 个字符（带省略号）—— 报错时给可读的值，不给整个回包。
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
        let mut config = AgentConfiguration::default();
        config.endpoint = "http://127.0.0.1:9/v1".to_string();
        config.model = "local-test".to_string();
        config
    }

    fn reply_with(content: &str) -> String {
        serde_json::json!({
            "choices": [{ "message": { "role": "assistant", "content": content } }]
        })
        .to_string()
    }

    #[test]
    fn an_empty_brief_is_refused_before_anything_is_built() {
        assert_eq!(
            build_request(&config(), "   \n ").unwrap_err(),
            AdvisorError::EmptyBrief
        );
    }

    #[test]
    fn the_human_text_is_the_brief_plus_the_three_rules() {
        let outgoing = build_request(&config(), "e1 执行计划\nSeq Scan on orders").unwrap();
        assert!(outgoing.human.contains("e1 执行计划"));
        assert!(outgoing.human.contains("[依据: eN]"));
        // 端点已带 /v1 ⇒ 拼成 chat/completions
        assert_eq!(outgoing.url, "http://127.0.0.1:9/v1/chat/completions");
    }

    #[test]
    fn the_body_carries_the_same_human_text_it_shows() {
        let outgoing = build_request(&config(), "e2 锁阻塞：3 条").unwrap();
        let body: serde_json::Value = serde_json::from_str(&outgoing.body).unwrap();
        let messages = body.get("messages").unwrap().as_array().unwrap();
        assert_eq!(messages[0]["role"], "system");
        assert_eq!(messages[0]["content"].as_str().unwrap(), SYSTEM_PROMPT);
        assert_eq!(messages[1]["content"].as_str().unwrap(), outgoing.human);
        assert_eq!(body["model"].as_str().unwrap(), "local-test");
    }

    #[test]
    fn an_over_long_brief_is_cut_and_the_cut_is_reported() {
        let brief = "x".repeat(MAX_BRIEF_CHARS + 25);
        let outgoing = build_request(&config(), &brief).unwrap();
        assert!(outgoing.human.contains("已从尾部砍掉 25 字符"));
        assert!(outgoing.human.len() < brief.len() + 400);
    }

    #[test]
    fn a_reply_with_choices_yields_its_text_trimmed() {
        assert_eq!(
            parse_reply(&reply_with("  结论: 全表扫描 [依据: e1]\n")).unwrap(),
            "结论: 全表扫描 [依据: e1]"
        );
    }

    #[test]
    fn a_reply_without_choices_names_what_was_missing() {
        let err = parse_reply("{\"id\":\"x\"}").unwrap_err();
        assert_eq!(err.code(), "replyShape");
        assert!(err.to_string().contains("choices"));
    }

    #[test]
    fn a_server_error_message_is_carried_out_verbatim() {
        let raw = serde_json::json!({ "error": { "message": "invalid api key" } }).to_string();
        let err = parse_reply(&raw).unwrap_err();
        assert!(err.to_string().contains("invalid api key"));
    }

    #[test]
    fn an_empty_reply_body_is_refused_instead_of_shown_as_blank() {
        let err = parse_reply(&reply_with("   ")).unwrap_err();
        assert_eq!(err.code(), "emptyReply");
    }
}
