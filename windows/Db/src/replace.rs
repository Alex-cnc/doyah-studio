//! **跨文件替换**的判定（FR-EDIT-42 那一半 / 计划 2.4）
//!
//! 由头：检索能"找到"，替换是"改掉"。改掉比找到危险得多 —— 一次误操作可能改掉几十个文件，
//! 而且**不可撤销**。所以这一层只管两件事，且都要能被单测钉住：
//!
//! 1. **改哪些位置**：与检索引擎**同一套归一规则**（大小写 + 变音符号不敏感），
//!    但**替换只改命中的那些字符**，其余一个字节不动（不做全行重写）；
//! 2. **改完长什么样**：给出一份"替换前的行 → 替换后的行"的**预览**，让用户先看清再落盘。
//!
//! 三条纪律：
//! - **空查询一律拒绝**（否则"把每一行的每一处都换掉"，那是灾难）；
//! - **同一位置不重复替换**（相邻命中不重叠，与高亮同一口径）；
//! - **归一可能改变长度** ⇒ 必须逐字记录"归一后的字符来自原文哪一个字符"，
//!   否则改的位置会错位（这一点与 `App/src/workspace/highlights.ts` 是同一个坑）。

use crate::save_guard::{decide_save, SaveDecision};
use crate::staleness::{DiskFile, LoadedFile};

/// 替换失败的原因（都对应界面上一句不同的话）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ReplaceError {
    /// 查询词是空的（**灾难的入口**，一律拒）
    EmptyQuery,
    /// 与查询词完全一样（换了等于没换）
    SameText,
}

/// 一处替换（**原文的字符区间** + 换成什么）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Replacement {
    pub start: usize,
    pub end: usize,
    pub with: String,
}

/// 一行的替换预览（给用户先看清）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LineChange {
    /// 行号（1 起，**与编辑器行号列同口径**）
    pub line: usize,
    /// 改之前那一行（原文）
    pub before: String,
    /// 改之后那一行
    pub after: String,
    /// 这一行改了几处
    pub count: usize,
}

/// 一份文件的替换计划。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FileChange {
    pub relative_path: String,
    pub changes: Vec<LineChange>,
    /// 这份文件里一共改了几处
    pub count: usize,
    /// 替换后的**完整内容**（落盘要用它 —— 与预览出自同一次计算，不会不一致）
    pub replaced: String,
}

impl FileChange {
    /// 应用之后要不要保留（零改动的文件不进计划）。
    pub fn is_empty(&self) -> bool {
        self.count == 0
    }
}

/// 单字符折叠（与 `search::normalize` 同一张表的等价实现）。
fn fold(ch: char) -> char {
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

/// 找出**一行的所有替换位置**（原文的字符下标）。
pub fn replacements_in_line(line: &str, query: &str) -> Vec<Replacement> {
    // 	o_lowercase() 返回的是迭代器（可能展开成多个字符）⇒ 先收成 String 再逐字折叠
    let lowered = query.trim().to_lowercase();
    let needle: Vec<char> = lowered.chars().map(fold).collect();
    if needle.is_empty() || line.is_empty() {
        return Vec::new();
    }
    // 逐字归一，并记住来源（**归一可能改变长度**，必须带来源）
    let original: Vec<char> = line.chars().collect();
    let mut folded: Vec<char> = Vec::new();
    let mut source: Vec<usize> = Vec::new();
    for (index, ch) in original.iter().enumerate() {
        // 同样：`to_lowercase()` 是迭代器 ⇒ 先收成 String（它可能展开成多个字符）
        for piece in ch.to_lowercase().collect::<String>().chars().map(fold) {
            folded.push(piece);
            source.push(index);
        }
    }
    if folded.len() < needle.len() {
        return Vec::new();
    }

    let mut found: Vec<Replacement> = Vec::new();
    let mut cursor = 0usize;
    while cursor + needle.len() <= folded.len() {
        let hit = (cursor..=folded.len() - needle.len())
            .find(|start| folded[*start..*start + needle.len()] == needle[..]);
        let Some(start) = hit else { break };
        let start_char = source[start];
        let end_char = source[start + needle.len() - 1] + 1;
        // 相邻命中**不重叠**（与高亮同一口径）
        match found.last() {
            Some(last) if start_char < last.end => {}
            _ => found.push(Replacement {
                start: start_char,
                end: end_char,
                with: String::new(),
            }),
        }
        cursor = start + needle.len();
    }
    found
}

/// 把一行的替换**应用**掉（按区间从后往前改，避免下标位移）。
pub fn apply_to_line(line: &str, query: &str, replacement: &str) -> (String, usize) {
    let mut hits = replacements_in_line(line, query);
    if hits.is_empty() {
        return (line.to_string(), 0);
    }
    let count = hits.len();
    let chars: Vec<char> = line.chars().collect();
    hits.sort_by(|a, b| b.start.cmp(&a.start));
    let mut out = chars;
    for hit in hits {
        out.splice(hit.start..hit.end, replacement.chars());
    }
    (out.into_iter().collect(), count)
}

/// 给一份文件算出替换计划（`None` = 这个文件没有命中）。
pub fn plan_file(relative_path: &str, text: &str, query: &str, replacement: &str) -> Option<FileChange> {
    // **空查询 / 与查询同词 ⇒ 拒绝**（前者是灾难入口，后者是白做功）
    if query.trim().is_empty() {
        return None;
    }
    if query == replacement {
        return None;
    }
    let mut changes: Vec<LineChange> = Vec::new();
    let mut count = 0usize;
    // 逐行处理（**行号与编辑器同口径**：复用 code_lines）
    let lines = crate::code_lines::lines(text);
    for (index, line) in lines.iter().enumerate() {
        let (after, hits) = apply_to_line(&line.text, query, replacement);
        if hits == 0 {
            continue;
        }
        count += hits;
        changes.push(LineChange {
            line: index + 1,
            before: line.text.clone(),
            after,
            count: hits,
        });
    }
    if count == 0 {
        return None;
    }
    Some(FileChange {
        relative_path: relative_path.to_string(),
        changes,
        count,
        replaced: apply_to_text(text, query, replacement),
    })
}

/// 替换整份文本（**保持原来的行终止符**：逐行改完再按各行的终止符拼回去）。
pub fn apply_to_text(text: &str, query: &str, replacement: &str) -> String {
    let lines = crate::code_lines::lines(text);
    let mut out = String::with_capacity(text.len());
    for line in &lines {
        let (after, _) = apply_to_line(&line.text, query, replacement);
        out.push_str(&after);
        // 终止符**原样保留**（不把 CRLF 改成 LF）
        if let Some(ending) = line.ending {
            out.push_str(ending.text());
        }
    }
    out
}

/// 整个替换计划的判定：能不能落盘（复用保存护栏的**同一条**冲突判据）。
pub fn decide_apply(
    current: &str,
    saved: &str,
    loaded: &LoadedFile,
    now_on_disk: Option<&DiskFile>,
) -> SaveDecision {
    decide_save(current, saved, loaded, now_on_disk)
}

/// 把计划汇总成一句人能读的话（**说清影响面，再让人确认**）。
pub fn summarise(changes: &[FileChange]) -> String {
    if changes.is_empty() {
        return "没有要改的地方。".to_string();
    }
    let files = changes.len();
    let hits: usize = changes.iter().map(|change| change.count).sum();
    format!("将改 **{files} 个文件**、共 **{hits} 处**。")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_query_is_refused_and_same_text_is_pointless() {
        // 空查询是**灾难的入口**（会把每行每处都换掉）
        assert!(plan_file("a.txt", "abc abc", "", "X").is_none());
        assert!(plan_file("a.txt", "abc abc", "   ", "X").is_none());
        // 换成同一个词 ⇒ 白做功
        assert!(plan_file("a.txt", "abc", "abc", "abc").is_none());
        assert_eq!(replacements_in_line("abc", ""), Vec::new());
    }

    #[test]
    fn replacements_are_found_with_the_search_engine_rules() {
        // 大小写不敏感
        let hits = replacements_in_line("agent AGENT", "agent");
        assert_eq!(hits.len(), 2);
        assert_eq!((hits[0].start, hits[0].end), (0, 5));
        assert_eq!((hits[1].start, hits[1].end), (6, 11));
        // 变音不敏感
        assert_eq!(replacements_in_line("café", "cafe").len(), 1);
        // 相邻命中不重叠
        let overlapping = replacements_in_line("aaaa", "aa");
        assert_eq!(overlapping.len(), 2, "非重叠地标两段");
        // 找不到
        assert!(replacements_in_line("abc", "zzz").is_empty());
    }

    #[test]
    fn applying_changes_only_the_matched_characters() {
        // 只改命中处，其余一字不动
        let (out, count) = apply_to_line("let agent = 1; // agent", "agent", "runner");
        assert_eq!(out, "let runner = 1; // runner");
        assert_eq!(count, 2);
        // 没命中 ⇒ 原样返回，count 0
        let (same, none) = apply_to_line("unchanged", "zzz", "X");
        assert_eq!(same, "unchanged");
        assert_eq!(none, 0);
        // 中文（一字一字符）
        let (zh, hits) = apply_to_line("格式化 SQL 与 格式化", "格式化", "美化");
        assert_eq!(zh, "美化 SQL 与 美化");
        assert_eq!(hits, 2);
        // 删除（换成空串）
        let (removed, _) = apply_to_line("a-b-c", "-", "");
        assert_eq!(removed, "abc");
        // **归一改变长度时位置不错位**
        let (turkish, hits) = apply_to_line("İstanbul", "stanbul", "X");
        assert_eq!(hits, 1);
        assert!(turkish.ends_with('X'));
        assert!(turkish.starts_with('İ'), "前半段不该被改到：{turkish}");
    }

    #[test]
    fn the_plan_carries_line_numbers_and_preview() {
        let text = "one\nTARGET here\ntwo\nTARGET again\n";
        let plan = plan_file("a.txt", text, "target", "done").unwrap();
        assert_eq!(plan.count, 2);
        assert_eq!(plan.changes.len(), 2);
        assert_eq!(plan.changes[0].line, 2, "行号与编辑器同口径");
        assert_eq!(plan.changes[0].before, "TARGET here");
        assert_eq!(plan.changes[0].after, "done here");
        assert_eq!(plan.changes[1].line, 4);
        // 替换后的完整内容与预览出自同一次计算
        assert_eq!(plan.replaced, "one\ndone here\ntwo\ndone again\n");
        // 没有命中的文件不进计划
        assert!(plan_file("b.txt", "nothing", "target", "done").is_none());
    }

    #[test]
    fn line_endings_are_preserved_verbatim() {
        // CRLF 不该被改成 LF（改完拼回去要按各行的终止符）
        let text = "TARGET\r\nsecond\r\n";
        let plan = plan_file("a.txt", text, "target", "done").unwrap();
        assert!(plan.replaced.contains("\r\n"), "CRLF 要保留：{:?}", plan.replaced);
        assert!(!plan.replaced.contains("\n\n"), "不该多出空行");
        assert_eq!(plan.replaced, "done\r\nsecond\r\n");
        // 混排也能逐行保留
        let mixed = "TARGET\nsecond\r\nthird";
        let mixed_plan = plan_file("b.txt", mixed, "target", "done").unwrap();
        assert_eq!(mixed_plan.replaced, "done\nsecond\r\nthird");
        // U+2028 这类少见终止符同样保留
        let ls = "TARGET\u{2028}x";
        let ls_plan = plan_file("c.txt", ls, "target", "done").unwrap();
        assert!(ls_plan.replaced.contains('\u{2028}'));
    }

    #[test]
    fn applying_reuses_the_same_conflict_guard_as_saving() {
        use crate::staleness::content_hash;
        let loaded = LoadedFile {
            relative_path: "a.txt".into(),
            byte_count: 6,
            modified_unix: Some(100),
            content_hash: content_hash(b"TARGET"),
        };
        let same = DiskFile {
            byte_count: 6,
            modified_unix: Some(100),
            content_hash: content_hash(b"TARGET"),
        };
        // 盘上没变 ⇒ 放行
        assert!(matches!(
            decide_apply("done", "TARGET", &loaded, Some(&same)),
            SaveDecision::Write { .. }
        ));
        // 盘上被改过 ⇒ **同一条护栏拒绝**（替换不能绕过保存冲突）
        let changed = DiskFile {
            byte_count: 4,
            modified_unix: Some(200),
            content_hash: content_hash(b"ELSE"),
        };
        assert!(matches!(
            decide_apply("done", "TARGET", &loaded, Some(&changed)),
            SaveDecision::Conflict { .. }
        ));
    }

    #[test]
    fn summary_says_how_much_will_change() {
        assert_eq!(summarise(&[]), "没有要改的地方。");
        let plan = plan_file("a.txt", "x x x", "x", "y").unwrap();
        let text = summarise(&[plan]);
        assert!(text.contains("1 个文件") && text.contains("3 处"), "{text}");
    }
}
