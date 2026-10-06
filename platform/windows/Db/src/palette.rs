//! 命令面板的**匹配与排序**（FR-EDIT-25 / 计划 2.9；契约等价物：macOS 侧 `Core/CommandPalette.swift`）
//!
//! 面板好不好用几乎全在这一层：
//! - 输入 `fmt` 要能命中「格式化 SQL」（**首字母缩写**），输入 `格式` 也要命中（**子串**）；
//! - 结果顺序要**稳定**：同样相关的命令，每次打开都该在同一个位置 ——
//!   否则用户记不住"按两下 ↓ 再回车"这条最省事的路径。
//!
//! 排序规则放这里是因为**它能单测**，而"看起来差不多"的排序差异只有测试能钉住。
//!
//! ## 分值档位（**分档而不是任意分值**：档位之间的关系一目了然，也便于断言）
//! 完全相同 1000 > 前缀 800 > 词首 700 > 子串 600 > 首字母缩写 500 > 子序列 300；
//! 命中关键词加 50（但**档位优先**：关键词加成不会让低档越过高档）。
//!
//! ## 稳定排序的三级判据
//! 分值 → 标题 → id。**不能只按分值**：同分命令的顺序会取决于数组顺序（那是"实现细节"，
//! 用户看到的是"每次不一样"）。

/// 参与匹配的一条命令。标题与关键词由界面层提供（**本层不做本地化**）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Item {
    /// 稳定标识（执行时用它分派）。
    pub id: String,
    pub title: String,
    /// 额外关键词（英文名、拼音首字母之类）：**参与匹配但不展示**。
    #[serde(default)]
    pub keywords: Vec<String>,
    /// 分组标题（如「查询」「连接」「智能体」），仅用于展示排序。
    #[serde(default)]
    pub group: Option<String>,
}

impl Item {
    pub fn new(id: impl Into<String>, title: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            title: title.into(),
            keywords: Vec::new(),
            group: None,
        }
    }

    pub fn with_keywords(mut self, keywords: &[&str]) -> Self {
        self.keywords = keywords.iter().map(|k| k.to_string()).collect();
        self
    }

    pub fn with_group(mut self, group: impl Into<String>) -> Self {
        self.group = Some(group.into());
        self
    }
}

/// 命中结果。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Match {
    pub item: Item,
    pub score: u32,
    /// 标题里命中字符的**字符位置**（界面用来高亮；子串命中时是连续区间）。
    pub highlighted: Vec<usize>,
    /// 命中的是哪一种（便于调试与"为什么这条排前面"的解释）。
    pub tier: Tier,
}

/// 命中的档位（**分值就是它**，不另给任意分）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Tier {
    Exact,
    Prefix,
    WordPrefix,
    Substring,
    Acronym,
    Subsequence,
    KeywordOnly,
}

impl Tier {
    pub const fn score(self) -> u32 {
        match self {
            Tier::Exact => 1000,
            Tier::Prefix => 800,
            Tier::WordPrefix => 700,
            Tier::Substring => 600,
            Tier::Acronym => 500,
            Tier::Subsequence => 300,
            Tier::KeywordOnly => 200,
        }
    }
}

/// 命中关键词的加成（**档位优先**：它加到本档之上，不会让低档越过高档）。
pub const KEYWORD_BONUS: u32 = 50;

/// 搜索。**空查询返回全部**（面板刚打开时要能一屏看到有什么可用），按原顺序。
pub fn search(query: &str, items: &[Item], limit: usize) -> Vec<Match> {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return items
            .iter()
            .take(limit)
            .map(|item| Match {
                item: item.clone(),
                score: 0,
                highlighted: Vec::new(),
                tier: Tier::Exact,
            })
            .collect();
    }
    let mut matches: Vec<Match> = items.iter().filter_map(|item| match_item(trimmed, item)).collect();
    // 稳定排序：分值 → 标题 → id
    matches.sort_by(|a, b| {
        b.score
            .cmp(&a.score)
            .then_with(|| a.item.title.cmp(&b.item.title))
            .then_with(|| a.item.id.cmp(&b.item.id))
    });
    matches.truncate(limit);
    matches
}

/// 单条匹配（对外暴露便于测试与调试）。
pub fn match_item(query: &str, item: &Item) -> Option<Match> {
    let lowered_query = query.to_lowercase();
    let lowered_title = item.title.to_lowercase();
    let chars: Vec<char> = item.title.chars().collect();
    let lowered_chars: Vec<char> = lowered_title.chars().collect();
    let query_chars: Vec<char> = lowered_query.chars().collect();

    // 关键词命中（不展示、只加成分）
    let keyword_hit = item.keywords.iter().any(|keyword| {
        let lowered = keyword.to_lowercase();
        lowered == lowered_query || lowered.starts_with(&lowered_query) || lowered.contains(&lowered_query)
    });

    // ① 完全相同
    if lowered_title == lowered_query {
        return Some(build(item, Tier::Exact, keyword_hit, (0..chars.len()).collect()));
    }
    // ② 前缀
    if lowered_title.starts_with(&lowered_query) {
        return Some(build(item, Tier::Prefix, keyword_hit, (0..query_chars.len()).collect()));
    }
    // ③ 词首（空格 / 标点分隔后的每个词的前缀）
    if let Some(start) = word_prefix_start(&lowered_chars, &query_chars) {
        return Some(build(
            item,
            Tier::WordPrefix,
            keyword_hit,
            (start..start + query_chars.len()).collect(),
        ));
    }
    // ④ 子串（中文标题几乎都走这条：`格式` 命中「格式化 SQL」）
    if let Some(start) = find_subsequence_slice(&lowered_chars, &query_chars) {
        return Some(build(
            item,
            Tier::Substring,
            keyword_hit,
            (start..start + query_chars.len()).collect(),
        ));
    }
    // ⑤ 首字母缩写（`fmt` → 「Format SQL」/「格式化 SQL」的英文关键词）
    if let Some(positions) = acronym_positions(&query_chars, &chars) {
        if !positions.is_empty() {
            return Some(build(item, Tier::Acronym, keyword_hit, positions));
        }
    }
    // ⑥ 关键词命中但不命中标题
    if keyword_hit {
        return Some(build(item, Tier::KeywordOnly, true, Vec::new()));
    }
    // ⑦ 子序列（查询字符按顺序出现在标题里，不要求连续）
    if let Some(positions) = subsequence_positions(&query_chars, &lowered_chars) {
        return Some(build(item, Tier::Subsequence, false, positions));
    }
    None
}

fn build(item: &Item, tier: Tier, keyword_hit: bool, highlighted: Vec<usize>) -> Match {
    Match {
        item: item.clone(),
        score: tier.score() + if keyword_hit { KEYWORD_BONUS } else { 0 },
        highlighted,
        tier,
    }
}

/// 一个字符算不算"词的分隔"。
fn is_word_break(ch: char) -> bool {
    ch.is_whitespace() || matches!(ch, '-' | '_' | '/' | '.' | ':' | '(' | ')' | '[' | ']' | '，' | '。' | '、')
}

/// 词首匹配：查询是某个词的前缀 ⇒ 返回那个词的起点。
fn word_prefix_start(title: &[char], query: &[char]) -> Option<usize> {
    if query.is_empty() || query.len() > title.len() {
        return None;
    }
    let mut index = 0usize;
    let mut at_word_start = true;
    while index + query.len() <= title.len() {
        if at_word_start && title[index..index + query.len()] == *query {
            return Some(index);
        }
        at_word_start = is_word_break(title[index]);
        index += 1;
    }
    None
}

/// 子串查找（按字符，不是按字节）⇒ 返回起点。
fn find_subsequence_slice(title: &[char], query: &[char]) -> Option<usize> {
    if query.is_empty() || query.len() > title.len() {
        return None;
    }
    (0..=title.len() - query.len()).find(|&start| title[start..start + query.len()] == *query)
}

/// 首字母缩写：查询的每个字符依次匹配标题里各词的**首字符**。
fn acronym_positions(query: &[char], title: &[char]) -> Option<Vec<usize>> {
    if query.is_empty() {
        return None;
    }
    // 标题里各词的起点
    let mut starts: Vec<usize> = Vec::new();
    let mut at_word_start = true;
    for (index, ch) in title.iter().enumerate() {
        if at_word_start && !is_word_break(*ch) {
            starts.push(index);
        }
        at_word_start = is_word_break(*ch);
    }
    if starts.len() < query.len() {
        return None;
    }
    // 查询字符要**依次**命中某些词的首字符
    let mut positions: Vec<usize> = Vec::new();
    let mut cursor = 0usize;
    for wanted in query {
        let mut found = None;
        for (offset, start) in starts.iter().enumerate().skip(cursor) {
            let candidate = title[*start].to_lowercase().next().unwrap_or(' ');
            if candidate == *wanted {
                found = Some((offset, *start));
                break;
            }
        }
        match found {
            Some((offset, start)) => {
                positions.push(start);
                cursor = offset + 1;
            }
            None => return None,
        }
    }
    Some(positions)
}

/// 子序列匹配：查询字符按顺序出现在标题里（不要求连续）⇒ 返回它们的位置。
fn subsequence_positions(query: &[char], title: &[char]) -> Option<Vec<usize>> {
    if query.is_empty() {
        return None;
    }
    let mut positions: Vec<usize> = Vec::new();
    let mut cursor = 0usize;
    for wanted in query {
        let mut found = None;
        for index in cursor..title.len() {
            if title[index] == *wanted {
                found = Some(index);
                break;
            }
        }
        let index = found?;
        positions.push(index);
        cursor = index + 1;
    }
    Some(positions)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn commands() -> Vec<Item> {
        vec![
            Item::new("sql.format", "格式化 SQL").with_keywords(&["fmt", "format"]),
            Item::new("sql.run", "执行 SQL").with_keywords(&["run", "execute"]).with_group("查询"),
            Item::new("conn.new", "新建连接").with_keywords(&["new connection"]).with_group("连接"),
            Item::new("ws.open", "打开工作区").with_keywords(&["open workspace"]),
            Item::new("file.save", "保存文件").with_keywords(&["save"]),
        ]
    }

    #[test]
    fn empty_query_returns_everything_in_original_order() {
        // 面板刚打开时要能一屏看到有什么可用
        let found = search("", &commands(), 50);
        assert_eq!(found.len(), 5);
        assert_eq!(found[0].item.id, "sql.format", "保持原顺序");
        // 空白也算空查询
        assert_eq!(search("   ", &commands(), 50).len(), 5);
        // limit 生效
        assert_eq!(search("", &commands(), 2).len(), 2);
    }

    #[test]
    fn substring_matches_chinese_titles() {
        let found = search("格式", &commands(), 10);
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].item.id, "sql.format");
        assert_eq!(found[0].tier, Tier::Prefix, "`格式` 是「格式化 SQL」的前缀");
        // 中间的字走子串档
        let middle = search("化 S", &commands(), 10);
        assert_eq!(middle[0].tier, Tier::Substring);
        // 高亮位置是**字符**位置（中文一个字算一位）
        // 「格式化 SQL」里 `化 S` 起于第 3 个字符（字符位 2）—— 我第一版写成 [1,2,3] 是**算错了**，实现是对的`n        assert_eq!(middle[0].highlighted, vec![2, 3, 4]);
    }

    #[test]
    fn acronym_matches_and_keyword_bonus_never_beats_a_higher_tier() {
        // `fmt` 不在标题里，但在关键词里 ⇒ 走关键词档
        let by_keyword = search("fmt", &commands(), 10);
        assert_eq!(by_keyword[0].item.id, "sql.format");
        assert_eq!(by_keyword[0].tier, Tier::KeywordOnly);
        // 关键词加成**加到本档之上**，不会让低档越过高档
        assert_eq!(by_keyword[0].score, Tier::KeywordOnly.score() + KEYWORD_BONUS);
        assert!(by_keyword[0].score < Tier::Subsequence.score());
        // 首字母缩写：标题里的词首字母
        let acronym = search("dxsql", &commands(), 10);
        assert!(acronym.is_empty() || acronym[0].tier != Tier::Subsequence, "子序列不报错即可");
        let items = vec![Item::new("a", "Format SQL")];
        let hit = match_item("fs", &items[0]).unwrap();
        assert_eq!(hit.tier, Tier::Acronym);
        assert_eq!(hit.highlighted, vec![0, 7], "F 与 S 的位置");
    }

    #[test]
    fn exact_beats_prefix_beats_word_prefix() {
        let items = vec![
            Item::new("a", "fmt"),
            Item::new("b", "fmt something"),
            Item::new("c", "do fmt now"),
        ];
        let found = search("fmt", &items, 10);
        // 完全相同 > 前缀 > 词首
        assert_eq!(found[0].tier, Tier::Exact);
        assert_eq!(found[1].tier, Tier::Prefix);
        assert_eq!(found[2].tier, Tier::WordPrefix);
        assert_eq!(found[0].score, 1000);
        assert_eq!(found[1].score, 800);
        assert_eq!(found[2].score, 700);
    }

    #[test]
    fn ordering_is_stable_for_equal_scores() {
        // 同分 ⇒ 按标题、再按 id；**不能只按分值**（否则顺序取决于数组顺序）
        let items = vec![
            Item::new("z2", "同一个标题"),
            Item::new("a1", "同一个标题"),
            Item::new("m3", "同一个标题"),
        ];
        let first = search("同一个", &items, 10);
        let again = search("同一个", &items, 10);
        assert_eq!(first, again, "同样输入必须同样输出");
        assert_eq!(first[0].item.id, "a1", "同分按 id 升序");
        assert_eq!(first[1].item.id, "m3");
        assert_eq!(first[2].item.id, "z2");
        // 换个数组顺序 ⇒ 结果顺序不变
        let reversed: Vec<Item> = items.into_iter().rev().collect();
        assert_eq!(search("同一个", &reversed, 10)[0].item.id, "a1");
    }

    #[test]
    fn subsequence_matches_when_nothing_else_does() {
        let items = vec![Item::new("a", "abcdef")];
        let hit = match_item("ace", &items[0]).unwrap();
        assert_eq!(hit.tier, Tier::Subsequence);
        assert_eq!(hit.highlighted, vec![0, 2, 4]);
        assert_eq!(hit.score, Tier::Subsequence.score());
        // 顺序不对 ⇒ 不命中
        assert!(match_item("eca", &items[0]).is_none());
        // 没有的字符 ⇒ 不命中
        assert!(match_item("xyz", &items[0]).is_none());
    }

    #[test]
    fn limit_and_no_match_cases() {
        assert!(search("zzzz", &commands(), 10).is_empty());
        assert!(search("格式", &commands(), 0).is_empty(), "limit 0 ⇒ 什么都不给");
        // 大小写不敏感
        assert_eq!(search("SQL", &commands(), 10)[0].item.id, search("sql", &commands(), 10)[0].item.id);
        // 序列化形状（界面要用）
        let hit = &search("保存", &commands(), 1)[0];
        let json = serde_json::to_string(hit).unwrap();
        assert!(json.contains("\"tier\":\"prefix\""), "{json}");
        assert!(json.contains("\"highlighted\""), "{json}");
    }
}
