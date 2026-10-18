//! **对话会话的落盘形状**（`FR-AI-17`）—— 一个工作区一段对话，关掉页签 / 重开应用还能接着问。
//!
//! 契约等价物：macOS 侧 `Core/AgentChatSession.swift`（同类意图：按工作区一份、可继续发送）。
//!
//! ## 这一层管什么、不管什么
//!
//! - **管**：会话文件的**形状**（版本 / 归属工作区 / 时刻 / 消息序列）、**归属校验**、
//!   **上限与对齐**、坏文件的**空账兜底**、以及序列化往返。
//! - **不管**落盘位置（在外壳 `App/src-tauri/src/agent_chat_sessions.rs`），也**不管**「该不该发」
//!   （那是 `agent::Gate` / `agent_config::evaluate` 的事）。
//!
//! ## 五条口径（每条都有对应判据）
//!
//! ① **按工作区隔离**：文件名由工作区路径**派生**（哈希，不拼字符串）⇒ 路径里的 `..` / 分隔符 /
//!   冒号**进不了文件名**；文件内部再存一份归属工作区，读的时候**对不上就不认**（不同工作区的
//!   对话绝不混在一段里 —— 那会让模型看见别的项目的表名）。
//! ② **读完还要能继续发**：段尾若不是用户消息 ⇒ 这一发没有「这一问」；开头若是模型消息 ⇒
//!   历史从半句开始。所以写盘时按 [`MAX_MESSAGES`] 只留**最新的**那几条，并把开头的模型消息对齐掉，
//!   **丢了几条要报数**（`dropped`），不静默。
//! ③ **坏文件不锁人**：JSON 坏了 / 版本不认识 / 归属对不上 ⇒ 当空会话打开并**说清为什么**；
//!   读的时候**不改写**原文件（下一次保存才会覆盖）—— 用户还有机会手工救回来。
//! ④ **逐条容错**：角色不认识 / 正文空白 / 超长的条目在读与写两侧都按同一条规则处理，
//!   **跳过与截断都计数**（`skipped` / `clipped`），界面照实说「这段对话不是完整原文」。
//! ⑤ **时间由调用方传入**（`updated_secs`）：本层不读系统时钟，单测才能钉住顺序。

use serde::{Deserialize, Serialize};

use crate::agent_nl2sql::{ChatMessage, CHAT_MAX_TURNS};

/// 会话文件的格式版本。读到**更高**版本 ⇒ 不猜、不写坏，按空会话打开并说明。
pub const VERSION: u32 = 1;

/// 一段会话最多留几条消息。**与一次请求的上限同一口径**（`CHAT_MAX_TURNS`）——
/// 留得比它多，读回来就发不出去，用户看到的是「有历史但点发送就被拒」。
pub const MAX_MESSAGES: usize = CHAT_MAX_TURNS;

/// 单条正文最多留多少字符（防一条粘贴进来的长文把整份文件撑爆；截断会打标记并计数）。
pub const MAX_CONTENT_CHARS: usize = 12_000;

/// 一份会话文件。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatSession {
    /// 格式版本（[`VERSION`]）。
    #[serde(default)]
    pub version: u32,
    /// 这段对话属于哪个工作区（原样存调用方给的那份路径；比对时按 [`workspace_key`] 归一）。
    #[serde(default)]
    pub workspace: String,
    /// 最后一次写入的时刻（epoch 秒；0 = 不知道）。
    #[serde(default)]
    pub updated_secs: u64,
    /// 消息序列（升序：最早的在前）。
    #[serde(default)]
    pub messages: Vec<ChatMessage>,
}

impl ChatSession {
    /// 空会话（归属工作区已填好）。
    pub fn empty(workspace: &str) -> Self {
        Self {
            version: VERSION,
            workspace: workspace.trim().to_string(),
            updated_secs: 0,
            messages: Vec::new(),
        }
    }

    /// 有没有内容。
    pub fn is_empty(&self) -> bool {
        self.messages.is_empty()
    }

    /// 这一段里问了几句（界面「第 N 问」用；只数用户消息）。
    pub fn questions(&self) -> usize {
        self.messages
            .iter()
            .filter(|message| message.role == "user")
            .count()
    }

    /// 序列化（字段顺序稳定 ⇒ 同一份内容写出来的字节一致，判据才能逐字节比）。
    pub fn to_json(&self) -> String {
        serde_json::to_string_pretty(self).unwrap_or_else(|_| "{}".to_string())
    }
}

/// 写盘前的规整结果（**丢了几条、截了几条都要报出去**，不许静默）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionWrite {
    /// 规整后的会话（可以直接落盘）。
    pub session: ChatSession,
    /// 因为超上限 / 开头对齐而**移出文件**的最早几条。
    pub dropped: usize,
    /// 正文超长被截断的条数。
    pub clipped: usize,
    /// 角色不认识 / 正文空白而丢弃的条数。
    pub invalid: usize,
}

/// 读回来的结果（会话 + 如实交代读的时候发生了什么）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionLoad {
    /// 可用的那段对话（归属对不上 / 文件坏了 ⇒ 空）。
    pub session: ChatSession,
    /// 读的时候丢掉的条数（角色不认识 / 正文空白）。
    pub skipped: usize,
    /// 读的时候截断过的条数。
    pub clipped: usize,
    /// 给界面照实说的话（坏文件 / 版本不认识 / 属于别的工作区 / 有跳过）；正常时为空。
    pub notes: Vec<String>,
}

/// 工作区归一：去空白、反斜杠转正斜杠、去尾部斜杠、**统一小写**（Windows 路径大小写不敏感，
/// 同一个目录用两种大小写打开不该变成两段对话）。
pub fn workspace_key(workspace: &str) -> String {
    let mut key = workspace.trim().replace('\\', "/");
    while key.len() > 1 && key.ends_with('/') {
        key.pop();
    }
    key.to_lowercase()
}

/// 这段工作区值不值得落盘（空串 / 只有空白 ⇒ 没有「按工作区」可言）。
pub fn is_usable_workspace(workspace: &str) -> bool {
    !workspace_key(workspace).is_empty()
}

/// 会话文件名：由工作区**派生**（FNV-1a 64，纯 stdlib、无随机、跨次运行稳定）。
///
/// 为什么哈希而不是把路径拼进文件名：工作区路径里可能有 `..`、`:`、空格、盘符、中文 ——
/// 任何一种拼进文件名都会变成「路径穿越」或「在别的目录建文件」的入口。哈希之后文件名只含
/// `[a-z0-9-]`，**归属信息放在文件内部**（读的时候校验）。
pub fn file_name_for(workspace: &str) -> String {
    file_name_for_id(workspace, DEFAULT_ID)
}

/// 老段（升级前那一段）的段号。**保留 `1`** ⇒ 升级后老文件 `chat-<哈希>.json` 逐字节照旧读得到，
/// 不需要迁移、不搬家。
pub const DEFAULT_ID: &str = "1";

/// 文件名的公共前缀（段号、指针文件都长在它后面）。
pub fn file_stem_for(workspace: &str) -> String {
    format!("chat-{:016x}", fnv1a64(&workspace_key(workspace)))
}

/// 段号归一：**只认 ASCII 数字**。段号来自磁盘文件名与界面，两者都不可信 ——
/// 归一不了就是空串（调用方当默认段处理），于是 `..` / 分隔符 / 盘符同样进不了文件名。
pub fn normalize_id(id: &str) -> String {
    let trimmed = id.trim();
    if trimmed.is_empty() || !trimmed.chars().all(|c| c.is_ascii_digit()) {
        return String::new();
    }
    let digits = trimmed.trim_start_matches('0');
    if digits.is_empty() {
        "0".to_string()
    } else {
        digits.to_string()
    }
}

/// 某个工作区里**第 N 段**对话的文件名：默认段用老名字（逐字节兼容），其余段加后缀。
pub fn file_name_for_id(workspace: &str, id: &str) -> String {
    let stem = file_stem_for(workspace);
    let id = normalize_id(id);
    if id.is_empty() || id == DEFAULT_ID {
        format!("{stem}.json")
    } else {
        format!("{stem}-{id}.json")
    }
}

/// 从磁盘上的文件名反解出段号（只认**本工作区**的名字）。
///
/// 为什么按定长前缀切：哈希是定长 16 位十六进制，`chat-<别的哈希>.json` 与
/// `chat-<本哈希>-2.json` 形状不同 ⇒ 别的工作区的文件永远不会被当成本工作区的一段。
pub fn parse_session_id(workspace: &str, file_name: &str) -> Option<String> {
    let stem = file_stem_for(workspace);
    if file_name == format!("{stem}.json") {
        return Some(DEFAULT_ID.to_string());
    }
    let rest = file_name.strip_prefix(&format!("{stem}-"))?;
    let digits = rest.strip_suffix(".json")?;
    let id = normalize_id(digits);
    if id.is_empty() {
        None
    } else {
        Some(id)
    }
}

/// 下一段的段号 = 现有最大段号 + 1（空表 ⇒ `1`，已有 `1` ⇒ `2`…）。
/// 认不出的段号不算数（它们是磁盘上的垃圾名字，不该把号推到天上去）。
pub fn next_session_id(existing: &[String]) -> String {
    let mut max = 0u64;
    for id in existing {
        if let Ok(value) = normalize_id(id).parse::<u64>() {
            max = max.max(value);
        }
    }
    (max + 1).to_string()
}

/// 列表里一段对话的**摘要**（标题由第一句提问派生 —— 落盘形状不动，升级前的旧文件照样有标题）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionSummary {
    /// 段号。
    pub id: String,
    /// 标题（第一句提问，单行，[`MAX_TITLE_CHARS`] 字符截断；没有提问 ⇒ 空串）。
    pub title: String,
    /// 这段里问了几句。
    pub questions: usize,
    /// 留存的消息条数。
    pub messages: usize,
    /// 最后一次写入的时刻（epoch 秒）。
    pub updated_secs: u64,
    /// 读不出来 / 属于别的工作区 / 版本不认识 ⇒ 写清原因（这一段**跳过**，其余段照常可用）。
    pub problem: Option<String>,
}

/// 标题最多多少字符。
pub const MAX_TITLE_CHARS: usize = 40;

/// 标题 = 第一句**用户**消息压成一行（换行 / 多空白折成一个空格），超 [`MAX_TITLE_CHARS`] 补 `…`。
pub fn title_of(messages: &[ChatMessage]) -> String {
    let Some(first) = messages
        .iter()
        .find(|message| message.role.trim() == "user" && !message.content.trim().is_empty())
    else {
        return String::new();
    };
    let flat = first
        .content
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    let mut title: String = flat.chars().take(MAX_TITLE_CHARS).collect();
    if flat.chars().count() > MAX_TITLE_CHARS {
        title.push('…');
    }
    title
}

/// 把「读回来的会话 + 读的时候说的话」压成列表里的一行。
pub fn summarize(id: &str, session: &ChatSession, notes: &[String]) -> SessionSummary {
    // 「空会话 + 有话要说」= 这一份用不了（坏文件 / 别的工作区 / 版本更新）⇒ 跳过并计数。
    // 合法的空对话（清空后那段）同样空，但一句话都没有 ⇒ 不算坏。
    let problem = if session.is_empty() && !notes.is_empty() {
        Some(notes.join(" "))
    } else {
        None
    };
    SessionSummary {
        id: normalize_id(id),
        title: title_of(&session.messages),
        questions: session.questions(),
        messages: session.messages.len(),
        updated_secs: session.updated_secs,
        problem,
    }
}

/// 新的在前；同一时刻按段号**数值**排（`10` 排在 `2` 后面，不按字符串比）。
pub fn newest_first(mut entries: Vec<SessionSummary>) -> Vec<SessionSummary> {
    entries.sort_by(|a, b| {
        b.updated_secs.cmp(&a.updated_secs).then_with(|| {
            let left = a.id.parse::<u64>().unwrap_or(0);
            let right = b.id.parse::<u64>().unwrap_or(0);
            left.cmp(&right)
        })
    });
    entries
}

/// 指针文件（`.active`）里的内容 ⇒ 段号。**只认数字**，认不出 = 没有指针（调用方退回默认段）。
pub fn active_from_text(text: Option<&str>) -> Option<String> {
    let id = normalize_id(text?);
    if id.is_empty() {
        None
    } else {
        Some(id)
    }
}

fn fnv1a64(text: &str) -> u64 {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in text.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
}

/// 写盘前规整：丢掉不可用的条目、按字符截断超长正文、只留最新的 [`MAX_MESSAGES`] 条、
/// 并把开头的模型消息对齐掉（读回来就是一段「从用户提问开始」的历史）。
pub fn bounded(workspace: &str, messages: &[ChatMessage], updated_secs: u64) -> SessionWrite {
    let mut clipped = 0usize;
    let mut invalid = 0usize;
    let mut kept: Vec<ChatMessage> = Vec::with_capacity(messages.len());
    for message in messages {
        let role = message.role.trim();
        if role != "user" && role != "assistant" {
            invalid += 1;
            continue;
        }
        if message.content.trim().is_empty() {
            invalid += 1;
            continue;
        }
        let (content, was_clipped) = clip(&message.content, MAX_CONTENT_CHARS);
        if was_clipped {
            clipped += 1;
        }
        kept.push(ChatMessage {
            role: role.to_string(),
            content,
        });
    }

    let mut dropped = 0usize;
    if kept.len() > MAX_MESSAGES {
        dropped += kept.len() - MAX_MESSAGES;
        kept.drain(0..kept.len() - MAX_MESSAGES);
    }
    // 开头若是模型消息 ⇒ 从半句开始（模型不在场也能读到「它答什么」的上一问），对齐掉。
    while kept.first().map(|message| message.role.as_str()) == Some("assistant") {
        kept.remove(0);
        dropped += 1;
    }

    SessionWrite {
        session: ChatSession {
            version: VERSION,
            workspace: workspace.trim().to_string(),
            updated_secs,
            messages: kept,
        },
        dropped,
        clipped,
        invalid,
    }
}

/// 读一份会话文件：**归属对不上 / 版本不认识 / JSON 坏了 ⇒ 空会话 + 说清为什么**。
///
/// 读的时候**不改写**原文件（下一次保存才覆盖）：坏文件里也许还有用户能手工救回来的正文。
pub fn load_json(workspace: &str, text: &str) -> SessionLoad {
    let mut notes: Vec<String> = Vec::new();
    if text.trim().is_empty() {
        return SessionLoad {
            session: ChatSession::empty(workspace),
            skipped: 0,
            clipped: 0,
            notes,
        };
    }
    let parsed: ChatSession = match serde_json::from_str(text) {
        Ok(session) => session,
        Err(err) => {
            notes.push(format!(
                "这份对话记录读不出来（{err}）：本次从空对话开始；原文件在你下一次发送前不会被改写。"
            ));
            return SessionLoad {
                session: ChatSession::empty(workspace),
                skipped: 0,
                clipped: 0,
                notes,
            };
        }
    };
    if parsed.version > VERSION {
        notes.push(format!(
            "这份对话记录来自更新版本（v{}，本版本只认得 v{}）：为免写坏它，本次按空对话打开。",
            parsed.version, VERSION
        ));
        return SessionLoad {
            session: ChatSession::empty(workspace),
            skipped: 0,
            clipped: 0,
            notes,
        };
    }
    if workspace_key(&parsed.workspace) != workspace_key(workspace) {
        notes.push(format!(
            "这份对话记录属于另一个工作区（{}），已按空对话打开 —— 不同工作区的对话不混在一起。",
            if parsed.workspace.trim().is_empty() {
                "未标注".to_string()
            } else {
                parsed.workspace.trim().to_string()
            }
        ));
        return SessionLoad {
            session: ChatSession::empty(workspace),
            skipped: 0,
            clipped: 0,
            notes,
        };
    }

    let mut skipped = 0usize;
    let mut clipped = 0usize;
    let mut kept: Vec<ChatMessage> = Vec::with_capacity(parsed.messages.len());
    for message in parsed.messages {
        let role = message.role.trim();
        if role != "user" && role != "assistant" {
            skipped += 1;
            continue;
        }
        if message.content.trim().is_empty() {
            skipped += 1;
            continue;
        }
        let (content, was_clipped) = clip(&message.content, MAX_CONTENT_CHARS);
        if was_clipped {
            clipped += 1;
        }
        kept.push(ChatMessage {
            role: role.to_string(),
            content,
        });
    }
    if kept.len() > MAX_MESSAGES {
        let extra = kept.len() - MAX_MESSAGES;
        kept.drain(0..extra);
        skipped += extra;
    }
    while kept.first().map(|message| message.role.as_str()) == Some("assistant") {
        kept.remove(0);
        skipped += 1;
    }
    if skipped > 0 {
        notes.push(format!(
            "读的时候跳过了 {skipped} 条（角色不认识 / 正文为空 / 超出上限 / 开头是模型消息）—— 这段对话不是完整原文。"
        ));
    }
    if clipped > 0 {
        notes.push(format!("有 {clipped} 条正文过长，已按 {MAX_CONTENT_CHARS} 字符截断。"));
    }

    SessionLoad {
        session: ChatSession {
            version: if parsed.version == 0 { VERSION } else { parsed.version },
            workspace: parsed.workspace,
            updated_secs: parsed.updated_secs,
            messages: kept,
        },
        skipped,
        clipped,
        notes,
    }
}

/// 按**字符**截断（不是字节 —— 否则中文会被切成半个字）；截断时补一个 `…`，让「这里不是全文」看得见。
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

    fn turn(role: &str, content: &str) -> ChatMessage {
        ChatMessage {
            role: role.to_string(),
            content: content.to_string(),
        }
    }

    #[test]
    fn a_saved_session_reads_back_in_the_same_order() {
        let messages = vec![
            turn("user", "这个库有哪些表"),
            turn("assistant", "三张：orders / users / events"),
            turn("user", "orders 有多少行"),
            turn("assistant", "大约 40 万行"),
        ];
        let write = bounded("D:/work/demo", &messages, 1_700_000_000);
        assert_eq!(write.dropped, 0);
        assert_eq!(write.invalid, 0);
        let text = write.session.to_json();
        for key in [
            "\"version\"",
            "\"workspace\"",
            "\"updatedSecs\"",
            "\"messages\"",
            "\"role\"",
            "\"content\"",
        ] {
            assert!(text.contains(key), "落盘字段少了 {key}：{text}");
        }
        let load = load_json("D:/work/demo", &text);
        assert!(load.notes.is_empty(), "正常文件不该有话要说：{:?}", load.notes);
        assert_eq!(load.session.messages, messages, "顺序与正文必须原样");
        assert_eq!(load.session.questions(), 2);
    }

    #[test]
    fn the_file_name_is_derived_and_can_never_escape_its_directory() {
        let plain = file_name_for("D:/work/demo");
        assert_eq!(plain, file_name_for("d:\\work\\demo\\"), "同一目录的两种写法必须落到同一份");
        assert_ne!(plain, file_name_for("D:/work/other"), "不同工作区不能共用一份");
        assert!(plain.starts_with("chat-") && plain.ends_with(".json"));
        // 路径穿越 / 盘符 / 分隔符都进不了文件名。
        for hostile in ["../../evil", "C:\\Windows\\System32", "a/b", "", "   "] {
            let name = file_name_for(hostile);
            assert!(!name.contains(".."), "{hostile} ⇒ {name}");
            assert!(!name.contains('/') && !name.contains('\\'), "{hostile} ⇒ {name}");
            assert!(!name.contains(':'), "{hostile} ⇒ {name}");
            assert_eq!(name.chars().filter(|c| *c == '.').count(), 1, "{hostile} ⇒ {name}");
        }
        assert!(!is_usable_workspace("   "), "空工作区不值得落盘");
        assert!(is_usable_workspace("D:/work/demo"));
    }

    #[test]
    fn a_broken_file_reads_as_empty_and_says_why_without_touching_it() {
        let load = load_json("D:/work/demo", "{ 这不是 JSON");
        assert!(load.session.is_empty());
        assert_eq!(load.notes.len(), 1);
        assert!(load.notes[0].contains("读不出来"), "{:?}", load.notes);
        // 空文件就是空会话，不算异常（第一次打开就是这个样子）。
        let blank = load_json("D:/work/demo", "   ");
        assert!(blank.session.is_empty());
        assert!(blank.notes.is_empty());
    }

    #[test]
    fn a_session_from_another_workspace_is_not_shown() {
        let write = bounded("D:/work/other", &[turn("user", "别的项目的问题")], 1);
        let load = load_json("D:/work/demo", &write.session.to_json());
        assert!(load.session.is_empty(), "别的工作区的对话绝不能混进来");
        assert!(load.notes[0].contains("另一个工作区"), "{:?}", load.notes);
        // 未标注归属的旧文件同样不认（宁可空着，也不猜）。
        let anonymous = r#"{"version":1,"messages":[{"role":"user","content":"谁的？"}]}"#;
        assert!(load_json("D:/work/demo", anonymous).session.is_empty());
    }

    #[test]
    fn a_newer_file_version_is_refused_instead_of_being_written_over() {
        let text = r#"{"version":9,"workspace":"D:/work/demo","messages":[{"role":"user","content":"x"}]}"#;
        let load = load_json("D:/work/demo", text);
        assert!(load.session.is_empty());
        assert!(load.notes[0].contains("更新版本"), "{:?}", load.notes);
    }

    #[test]
    fn garbage_entries_are_skipped_and_counted_on_both_sides() {
        let text = serde_json::json!({
            "version": 1,
            "workspace": "D:/work/demo",
            "messages": [
                { "role": "system", "content": "偷偷塞进来的系统提示" },
                { "role": "user", "content": "   " },
                { "role": "user", "content": "真问题" },
                { "role": "assistant", "content": "真回答" }
            ]
        })
        .to_string();
        let load = load_json("D:/work/demo", &text);
        assert_eq!(load.skipped, 2, "角色不认识 + 空白 都要计上");
        assert_eq!(load.session.messages.len(), 2);
        assert_eq!(load.session.messages[0].content, "真问题");
        assert!(load.notes[0].contains("跳过了 2 条"), "{:?}", load.notes);

        // 写盘侧同一条规则（同一个函数），不各写一份。
        let write = bounded(
            "D:/work/demo",
            &[turn("system", "x"), turn("user", "真问题")],
            2,
        );
        assert_eq!(write.invalid, 1);
        assert_eq!(write.session.messages.len(), 1);
    }

    #[test]
    fn the_cap_keeps_the_newest_and_never_leaves_an_orphan_reply_at_the_top() {
        let mut messages: Vec<ChatMessage> = Vec::new();
        for index in 0..(MAX_MESSAGES + 6) {
            let role = if index % 2 == 0 { "user" } else { "assistant" };
            messages.push(turn(role, &format!("第 {index} 条")));
        }
        let write = bounded("D:/work/demo", &messages, 3);
        assert_eq!(write.session.messages.len(), MAX_MESSAGES);
        assert!(write.dropped >= 6, "丢了几条必须报数：{}", write.dropped);
        assert_eq!(
            write.session.messages[0].role, "user",
            "开头必须是用户消息（否则读回来历史从半句开始）"
        );
        assert_eq!(
            write.session.messages.last().unwrap().content,
            format!("第 {} 条", MAX_MESSAGES + 5),
            "上限压的是最老的，最新那条必须在"
        );
        // 读侧同样对齐（手改过的文件也不会让界面出现「模型先说话」）。
        let load = load_json("D:/work/demo", &write.session.to_json());
        assert_eq!(load.session.messages[0].role, "user");
    }

    #[test]
    fn a_very_long_message_is_clipped_by_characters_and_counted() {
        let long = "查".repeat(MAX_CONTENT_CHARS + 10);
        let write = bounded(
            "D:/work/demo",
            &[turn("user", &long), turn("assistant", "短答")],
            4,
        );
        assert_eq!(write.clipped, 1);
        let kept = &write.session.messages[0].content;
        assert_eq!(kept.chars().count(), MAX_CONTENT_CHARS + 1);
        assert!(kept.ends_with('…'));
        // 按字节切会把中文切成半个字（字节边界也不该破）。
        assert!(std::str::from_utf8(kept.as_bytes()).is_ok());
    }

    #[test]
    fn segments_of_one_workspace_never_collide_with_another_workspace() {
        // 段 1 用老名字 ⇒ 升级后老对话照旧读得到（逐字节兼容）。
        assert_eq!(file_name_for_id("D:/work/demo", DEFAULT_ID), file_name_for("D:/work/demo"));
        assert_eq!(file_name_for_id("D:/work/demo", "1"), file_name_for("D:/work/demo"));
        // 段 2 起加后缀，且解回来还是 2。
        let second = file_name_for_id("D:/work/demo", "2");
        assert_eq!(parse_session_id("D:/work/demo", &second), Some("2".to_string()));
        assert_eq!(
            parse_session_id("D:/work/demo", &file_name_for("D:/work/demo")),
            Some(DEFAULT_ID.to_string())
        );
        // 另一工作区的文件**绝不**被当成本工作区的一段（负例）。
        let other = file_name_for_id("D:/work/other", "2");
        assert_ne!(other, second);
        assert_eq!(parse_session_id("D:/work/demo", &other), None);
        assert_eq!(parse_session_id("D:/work/demo", &file_name_for("D:/work/other")), None);
        // 临时文件 / 乱七八糟的名字都不算一段。
        for junk in [
            format!("{}.json.tmp", file_stem_for("D:/work/demo")),
            format!("{}-2.json.tmp", file_stem_for("D:/work/demo")),
            format!("{}-.json", file_stem_for("D:/work/demo")),
            format!("{}-x.json", file_stem_for("D:/work/demo")),
            "chat-whatever.json".to_string(),
        ] {
            assert_eq!(parse_session_id("D:/work/demo", &junk), None, "{junk}");
        }
        // 段号来自界面 / 文件名，两者都不可信：路径穿越进不了文件名（负例）。
        for hostile in ["../../evil", "C:\\Windows", "a/2", "  "] {
            let name = file_name_for_id("D:/work/demo", hostile);
            assert!(!name.contains("..") && !name.contains('/') && !name.contains('\\'), "{hostile} ⇒ {name}");
            assert_eq!(name, file_name_for("D:/work/demo"), "{hostile} ⇒ 落回默认段");
        }
        // `01` 与 `1` 是同一段（否则同一段会有两个文件）。
        assert_eq!(file_name_for_id("D:/work/demo", "01"), file_name_for("D:/work/demo"));
    }

    #[test]
    fn the_next_segment_is_never_reused() {
        assert_eq!(next_session_id(&[]), "1", "空表 ⇒ 老段位置");
        assert_eq!(next_session_id(&["1".to_string()]), "2");
        assert_eq!(next_session_id(&["2".to_string()]), "3");
        assert_eq!(
            next_session_id(&["1".to_string(), "3".to_string()]),
            "4",
            "取最大 + 1，不填洞（填洞会让「最近那段」与段号顺序打架）"
        );
        assert_eq!(
            next_session_id(&["1".to_string(), "garbage".to_string()]),
            "2",
            "认不出的名字不该把号推上天"
        );
    }

    #[test]
    fn a_title_is_the_first_question_flattened_to_one_line() {
        let messages = vec![
            turn("assistant", "先说的话不该当标题"),
            turn("user", "这个库里\n有哪些表？"),
            turn("user", "第二个问题"),
        ];
        assert_eq!(title_of(&messages), "这个库里 有哪些表？");
        assert_eq!(title_of(&[turn("assistant", "只有模型在说")]), "", "没有提问就没有标题");
        let long = "问".repeat(MAX_TITLE_CHARS + 5);
        let title = title_of(&[turn("user", &long)]);
        assert_eq!(title.chars().count(), MAX_TITLE_CHARS + 1);
        assert!(title.ends_with('…'), "截断要看得出来：{title}");
    }

    #[test]
    fn the_list_puts_the_newest_first_and_says_which_segment_is_broken() {
        let older = summarize(
            "1",
            &bounded("D:/work/demo", &[turn("user", "老问题")], 10).session,
            &[],
        );
        let newer = summarize(
            "2",
            &bounded("D:/work/demo", &[turn("user", "新问题")], 30).session,
            &[],
        );
        // 坏文件：读出来是空会话 + 有话要说 ⇒ 单列 problem（跳过并计数），不影响别的段。
        let broken = summarize("3", &ChatSession::empty("D:/work/demo"), &["这份对话记录读不出来".to_string()]);
        assert!(broken.problem.is_some());
        assert_eq!(broken.messages, 0);
        // 合法的空对话（清空后那段）不算坏。
        let empty = summarize("4", &ChatSession::empty("D:/work/demo"), &[]);
        assert!(empty.problem.is_none());

        let sorted = newest_first(vec![older.clone(), newer.clone(), broken.clone(), empty]);
        assert_eq!(
            sorted.iter().map(|entry| entry.id.as_str()).collect::<Vec<_>>(),
            vec!["2", "1", "3", "4"],
            "按时刻新的在前；同一时刻（0）按段号数值排"
        );
        assert_eq!(sorted[0].title, "新问题");
        assert_eq!(active_from_text(Some(" 2\n")), Some("2".to_string()));
        assert_eq!(active_from_text(Some("../../evil")), None);
        assert_eq!(active_from_text(None), None);
    }
}
