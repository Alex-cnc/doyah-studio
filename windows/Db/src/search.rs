//! 工作区**检索**（FR-EDIT-32 / 44；契约等价物：macOS 侧 `Core/WorkspaceSearch.swift`）
//!
//! 按文件名找与按内容找**共用同一个匹配谓词** —— 这是这份契约里最要紧的一条：
//! 界面侧不许另写一套 `contains`，否则"同一个词在文件名里搜得到、在内容里搜不到"这类分歧
//! 迟早出现，而且是**静默**的。
//!
//! 匹配口径：**大小写不敏感 + 变音符号不敏感的子串匹配**（用户不该因为记不住大小写或打不出
//! 重音符号就搜不到）。
//!
//! 有界体现在三处（都可配，单测里调小）：
//!   ① 忽略名单（复用 `workspace::DEFAULT_IGNORED`）；
//!   ② **深度上限**（防止有人把工作区选到盘根或家目录后界面卡死）；
//!   ③ **结果上限**（命中太多就停下并**如实告知"已达上限"**，不悄悄截断）。
//!
//! 另外两条：**不跟随符号链接**（跟出去就跑到工作区外面了）、**跳过要报数**
//! （二进制 / 超大 / 读不了各记一笔 —— 跳过 ≠ 通过）。

use crate::code_lines::lines;

/// 默认深度上限（防止把盘根当工作区）。
pub const DEFAULT_MAX_DEPTH: usize = 12;
/// 默认结果条数上限。
pub const DEFAULT_RESULT_LIMIT: usize = 200;
/// 单个文件最多记多少条命中（免得一个文件把整份结果吃光）。
pub const DEFAULT_PER_FILE_LIMIT: usize = 20;
/// 单文件大小上限（超过就**跳过并报数**，不假装搜过）。
pub const DEFAULT_MAX_FILE_SIZE: u64 = 2 * 1024 * 1024;
/// 摘要长度上限（超出截断加省略号 —— **原文一个字不改**）。
pub const DEFAULT_SNIPPET_LIMIT: usize = 200;
/// 判二进制时探多少字节（含 NUL 即当二进制）。
pub const BINARY_PROBE_BYTES: usize = 8192;

/// 把查询词归一成比较用的形状（**与 `matches` 同源，只此一处**）。
///
/// 做法：小写化 + 去掉常见变音符号。**不引 Unicode 归一化库**：本侧只需要"用户打得出、
/// 搜得到"，覆盖拉丁字母的常见重音足够；好处是这一层没有额外依赖、行为完全可测。
pub fn normalize(query: &str) -> String {
    query.trim().to_lowercase().chars().map(fold_diacritic).collect()
}

/// 一个字符的变音折叠（`é → e`；没有对应关系的原样返回）。
fn fold_diacritic(ch: char) -> char {
    match ch {
        'á' | 'à' | 'â' | 'ä' | 'ã' | 'å' | 'ā' | 'ă' | 'ą' => 'a',
        'ç' | 'ć' | 'č' => 'c',
        'ď' | 'đ' => 'd',
        'é' | 'è' | 'ê' | 'ë' | 'ě' | 'ē' | 'ė' | 'ę' => 'e',
        'ğ' | 'ĝ' | 'ģ' => 'g',
        'í' | 'ì' | 'î' | 'ï' | 'ī' | 'į' | 'ı' => 'i',
        'ł' | 'ĺ' | 'ľ' => 'l',
        'ñ' | 'ń' | 'ň' => 'n',
        'ó' | 'ò' | 'ô' | 'ö' | 'õ' | 'ø' | 'ō' | 'ő' => 'o',
        'ř' | 'ŕ' => 'r',
        'ś' | 'š' | 'ş' | 'ș' => 's',
        'ť' | 'ţ' | 'ț' => 't',
        'ú' | 'ù' | 'û' | 'ü' | 'ū' | 'ů' | 'ű' | 'ų' => 'u',
        'ý' | 'ÿ' => 'y',
        'ź' | 'ż' | 'ž' => 'z',
        other => other,
    }
}

/// **唯一匹配谓词**：文件名搜索与内容搜索都走它。
///
/// `needle` 应当是**已经 `normalize` 过的**查询词（避免每次都归一一遍）；
/// 传空串一律不匹配（空查询不该命中一切）。
pub fn matches(text: &str, normalized_needle: &str) -> bool {
    if normalized_needle.is_empty() {
        return false;
    }
    normalize(text).contains(normalized_needle)
}

/// 一条内容命中 = **某个文件的某一行**。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContentHit {
    pub relative_path: String,
    /// 行号，**1 起**（与编辑器行号列**同一套数法**：复用 `code_lines::lines`）
    pub line: usize,
    /// 该行原文裁剪后的摘要 —— **不改写原文**（不替换、不美化）
    pub snippet: String,
}

/// 一个文件里的命中组（界面按文件分组渲染）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContentGroup {
    pub relative_path: String,
    pub hits: Vec<ContentHit>,
}

/// **跳过报告** —— 跳过 ≠ 通过：二进制 / 超大 / 读不了各记一笔，界面要看得见。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SkipReport {
    pub binary: usize,
    pub too_large: usize,
    pub unreadable: usize,
}

impl SkipReport {
    pub fn total(&self) -> usize {
        self.binary + self.too_large + self.unreadable
    }

    pub fn is_empty(&self) -> bool {
        self.total() == 0
    }
}

/// 内容检索结果。
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContentResult {
    pub groups: Vec<ContentGroup>,
    pub skips: SkipReport,
    /// 真正读了内容的文件数（含读了但没命中的）
    pub scanned_files: usize,
    /// 命中总数到达上限而提前停止（界面应如实提示）
    pub truncated: bool,
}

impl ContentResult {
    pub fn hit_count(&self) -> usize {
        self.groups.iter().map(|group| group.hits.len()).sum()
    }
}

/// 上下文摘要：去掉首尾空白，超长截断加 `…`（**原文一个字不改**）。
pub fn snippet(line: &str, limit: usize) -> String {
    let trimmed = line.trim();
    let chars: Vec<char> = trimmed.chars().collect();
    if chars.len() <= limit {
        return trimmed.to_string();
    }
    let head: String = chars[..limit].iter().collect();
    format!("{head}…")
}

/// 在一份**已经读出来的文本**里按行找命中（**纯函数**：IO 在表示层）。
///
/// 返回这一份文本里的命中（按行号升序），以及是否因为 `per_file_limit` 提前停下。
pub fn hits_in_text(
    relative_path: &str,
    text: &str,
    normalized_needle: &str,
    per_file_limit: usize,
    snippet_limit: usize,
) -> (Vec<ContentHit>, bool) {
    let mut hits: Vec<ContentHit> = Vec::new();
    if normalized_needle.is_empty() || per_file_limit == 0 {
        return (hits, false);
    }
    // **行号数与编辑器同源**：复用 code_lines::lines（同一套终止符与末尾空行口径）
    for (index, line) in lines(text).iter().enumerate() {
        if matches(&line.text, normalized_needle) {
            hits.push(ContentHit {
                relative_path: relative_path.to_string(),
                line: index + 1,
                snippet: snippet(&line.text, snippet_limit),
            });
            if hits.len() >= per_file_limit {
                return (hits, true);
            }
        }
    }
    (hits, false)
}

/// 判断一段字节是不是"二进制"（前 8 KiB 含 NUL 即算），并尝试解成 UTF-8 文本。
///
/// 解不出来 = 二进制（**不假装搜过**）。
pub fn decode_text(bytes: &[u8]) -> Option<String> {
    let probe = &bytes[..bytes.len().min(BINARY_PROBE_BYTES)];
    if probe.contains(&0) {
        return None;
    }
    String::from_utf8(bytes.to_vec()).ok()
}

/// 把各组拼成最终结果，并**在总数超上限时停下并标记截断**。
///
/// 分成两半是为了让"走目录树"那一半（表示层）与"算结果"这一半（本层，可单测）分开。
pub fn assemble(groups: Vec<ContentGroup>, skips: SkipReport, scanned_files: usize, limit: usize) -> ContentResult {
    let mut kept: Vec<ContentGroup> = Vec::new();
    let mut total = 0usize;
    let mut truncated = false;
    for group in groups {
        if total >= limit {
            truncated = true;
            break;
        }
        let room = limit - total;
        if group.hits.len() > room {
            truncated = true;
            let mut partial = group.clone();
            partial.hits.truncate(room);
            total += partial.hits.len();
            kept.push(partial);
            break;
        }
        total += group.hits.len();
        kept.push(group);
    }
    ContentResult {
        groups: kept,
        skips,
        scanned_files,
        truncated,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matching_is_case_and_diacritic_insensitive() {
        // 大小写不敏感
        assert!(matches("AgentRunner.swift", &normalize("agentrunner")));
        assert!(matches("agentrunner", &normalize("AGENTRUNNER")));
        // 变音符号不敏感（打不出重音也能搜到）
        assert!(matches("café.md", &normalize("cafe")));
        assert!(matches("Zürich.txt", &normalize("zurich")));
        assert!(matches("naïve", &normalize("naive")));
        // 归一化本身
        assert_eq!(normalize("  CAFÉ  "), "cafe");
        assert_eq!(normalize("Ünïcödé"), "unicode");
        // 空查询**不命中一切**
        assert!(!matches("anything", ""));
        assert!(!matches("anything", &normalize("   ")));
        // 子串匹配（不是整词）
        assert!(matches("my-agent-runner", &normalize("agent")));
        assert!(!matches("my-agent-runner", &normalize("zzz")));
    }

    #[test]
    fn one_predicate_is_shared_by_name_and_content_search() {
        // 这条用例是"唯一出处"的机械形式：同一对（文本, 查询）在两处必须给同一答案。
        // 文件名搜索在表示层也只是调 matches；内容搜索在 hits_in_text 里调同一个。
        let text = "let café = 1;";
        let needle = normalize("CAFE");
        assert!(matches(text, &needle), "文件名谓词必须认它");
        let (hits, _) = hits_in_text("a.rs", text, &needle, 10, 200);
        assert_eq!(hits.len(), 1, "内容搜索必须给同一答案 —— 否则同一词两边搜不到一起");
    }

    #[test]
    fn line_numbers_share_the_editor_counting() {
        // 末尾终止符算多一个空行（与编辑器行号列同源）—— 这条错了会"静默跳到相邻行"
        let text = "one\nTARGET\ntail\n";
        let (hits, _) = hits_in_text("a.txt", text, &normalize("target"), 10, 200);
        assert_eq!(hits[0].line, 2);
        assert_eq!(hits[0].snippet, "TARGET");
        // CRLF 与单独 CR 也认（同一套 code_lines 口径）
        let (crlf, _) = hits_in_text("a.txt", "one\r\nTARGET\r\n", &normalize("target"), 10, 200);
        assert_eq!(crlf[0].line, 2);
        let (cr, _) = hits_in_text("a.txt", "one\rTARGET\r", &normalize("target"), 10, 200);
        assert_eq!(cr[0].line, 2);
        // U+2028 分隔的行号也要对（不同源的话这里就会差）
        let (ls, _) = hits_in_text("a.txt", "one\u{2028}TARGET", &normalize("target"), 10, 200);
        assert_eq!(ls[0].line, 2);
    }

    #[test]
    fn per_file_limit_stops_and_says_so() {
        let text = (1..=10).map(|i| format!("hit line {i}\n")).collect::<String>();
        let (hits, truncated) = hits_in_text("a.txt", &text, &normalize("hit"), 3, 200);
        assert_eq!(hits.len(), 3);
        assert!(truncated, "一个文件吃光了上限要如实说");
        // 上限为 0 ⇒ 不找（也不拖时间）
        let (none, _) = hits_in_text("a.txt", &text, &normalize("hit"), 0, 200);
        assert!(none.is_empty());
    }

    #[test]
    fn snippets_trim_and_truncate_without_rewriting_the_line() {
        assert_eq!(snippet("   spaced   ", 200), "spaced");
        let long = "x".repeat(300);
        let cut = snippet(&long, 200);
        assert_eq!(cut.chars().count(), 201, "200 个字符 + 省略号");
        assert!(cut.ends_with('…'));
        // 原文里的内容一个字不改（只去首尾空白）
        assert_eq!(snippet("  const a = 1;  ", 200), "const a = 1;");
    }

    #[test]
    fn binary_detection_and_text_decoding() {
        assert_eq!(decode_text(b"plain text"), Some("plain text".to_string()));
        assert_eq!(decode_text("中文".as_bytes()), Some("中文".to_string()));
        // 含 NUL ⇒ 二进制
        assert_eq!(decode_text(b"a\0b"), None);
        // 不是合法 UTF-8 ⇒ 也当二进制（**不假装搜过**）
        assert_eq!(decode_text(&[0xff, 0xfe, 0xfd]), None);
        // 空文件是可读文本（没命中而已，不算"跳过"）
        assert_eq!(decode_text(b""), Some(String::new()));
    }

    #[test]
    fn assembling_stops_at_the_result_limit_and_marks_truncation() {
        let group = |path: &str, count: usize| ContentGroup {
            relative_path: path.to_string(),
            hits: (1..=count)
                .map(|i| ContentHit {
                    relative_path: path.to_string(),
                    line: i,
                    snippet: format!("h{i}"),
                })
                .collect(),
        };
        // 上限 5：第一组 3 条全要，第二组只留 2 条，并标记截断
        let result = assemble(vec![group("a", 3), group("b", 4)], SkipReport::default(), 2, 5);
        assert_eq!(result.hit_count(), 5);
        assert!(result.truncated);
        assert_eq!(result.groups[1].hits.len(), 2);
        assert_eq!(result.scanned_files, 2);
        // 没到上限 ⇒ 不标截断
        let whole = assemble(vec![group("a", 2)], SkipReport::default(), 1, 200);
        assert!(!whole.truncated);
        assert_eq!(whole.hit_count(), 2);
        // 上限为 0 ⇒ 什么都不留且标截断
        let none = assemble(vec![group("a", 1)], SkipReport::default(), 1, 0);
        assert_eq!(none.hit_count(), 0);
        assert!(none.truncated);
    }

    #[test]
    fn skip_report_counts_each_path_separately() {
        let report = SkipReport {
            binary: 3,
            too_large: 1,
            unreadable: 2,
        };
        assert_eq!(report.total(), 6);
        assert!(!report.is_empty());
        assert!(SkipReport::default().is_empty());
        let text = serde_json::to_string(&report).unwrap();
        assert!(text.contains("\"tooLarge\""), "{text}");
    }
}
