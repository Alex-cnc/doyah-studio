//! **光标位置**（FR-EDIT-36 会话恢复那一半 / 计划 2.3：重启后光标回来）
//!
//! 存什么、为什么这么存：
//!   ① 存**行号 + 行内字符偏移**，不存"整份文件的字节偏移" —— 后者只要文件开头多了一行就全错；
//!   ② **行号也存一个锚**（那一行开头的若干字符）：恢复时先按行号定位，行内容对不上就按锚找 ——
//!      文件被改过之后，纯行号常常还指得对，但"对不上"这件事必须能被发现，**不能默默指错地方**；
//!   ③ **不存行内偏移的锚**：行内偏移只用于同一次会话内（那时内容没变），跨会话恢复只要有行就够；
//!   ④ 恢复时**行号越界就夹到最后一行**（文件短了），并在结果里如实说明是"夹过的"还是"锚命中"的。
//!
//! 一句纪律：**恢复出来的位置必须说清它是怎么来的**（`Exact` / `ByAnchor` / `Clamped`），
//! 界面才可能在"位置可能不准"时提醒用户。

use crate::code_lines::lines;

/// 光标位置（行号从 1 起；`column` 是行内**字符**偏移，从 0 起）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Cursor {
    pub line: usize,
    pub column: usize,
}

impl Cursor {
    pub fn new(line: usize, column: usize) -> Self {
        Self {
            line: line.max(1),
            column,
        }
    }
}

/// 恢复用的**锚**：行号 + 该行开头的若干字符（用于"行号还准不准"的校验与再定位）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CursorAnchor {
    pub line: usize,
    pub column: usize,
    /// 那一行开头的片段（去掉首尾空白的更稳；最多取 [ANCHOR_CHARS] 个字符）
    pub line_prefix: String,
}

/// 锚取多少个字符（多了更准但更脆：一行改动就会让长锚对不上；少了容易撞）。
pub const ANCHOR_CHARS: usize = 32;

/// 从文本里取某个位置所在行的**锚前缀**（行不存在就给空串）。
pub fn anchor_prefix(text: &str, line: usize) -> String {
    let all = lines(text);
    let Some(target) = all.get(line.saturating_sub(1)) else {
        return String::new();
    };
    target.text.trim_start().chars().take(ANCHOR_CHARS).collect()
}

/// 记下当前光标（含锚）。
pub fn remember(text: &str, cursor: &Cursor) -> CursorAnchor {
    let line = cursor.line.max(1);
    CursorAnchor {
        line,
        column: cursor.column,
        line_prefix: anchor_prefix(text, line),
    }
}

/// 恢复的结果：怎么来的，加上位置本身。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RestoredCursor {
    pub cursor: Cursor,
    /// `exact` = 行号与锚都对上 / `byAnchor` = 行号对不上但按锚找到了 /
    /// `clamped` = 行号越界，夹到最后一行（文件短了）
    pub how: RestoreHow,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RestoreHow {
    Exact,
    ByAnchor,
    Clamped,
}

impl RestoreHow {
    /// 供界面取文案的稳定键。
    pub const fn key(self) -> &'static str {
        match self {
            RestoreHow::Exact => "cursorRestore.exact",
            RestoreHow::ByAnchor => "cursorRestore.byAnchor",
            RestoreHow::Clamped => "cursorRestore.clamped",
        }
    }

    /// 位置是否**可能不准**（界面据此决定要不要轻声提醒）。
    pub const fn is_uncertain(self) -> bool {
        matches!(self, RestoreHow::ByAnchor | RestoreHow::Clamped)
    }
}

/// 在一份（可能已经被改过的）文本里恢复位置。
pub fn restore(text: &str, anchor: &CursorAnchor) -> RestoredCursor {
    let all = lines(text);
    let line_count = all.len();
    let want = anchor.line.max(1);

    // ① 行号在范围内、且锚前缀对得上 ⇒ 精确命中
    if want <= line_count {
        let candidate = all[want - 1].text.trim_start().chars().take(ANCHOR_CHARS).collect::<String>();
        if anchor.line_prefix.is_empty() || candidate == anchor.line_prefix {
            return RestoredCursor {
                cursor: Cursor::new(want, clamp_column(&all[want - 1].text, anchor.column)),
                how: RestoreHow::Exact,
            };
        }
    }

    // ② 行号对不上 ⇒ 按锚前缀找（找最靠前的那一处；锚为空则跳过这一步）
    if !anchor.line_prefix.is_empty() {
        if let Some(index) = all.iter().position(|line| {
            line.text.trim_start().chars().take(ANCHOR_CHARS).collect::<String>() == anchor.line_prefix
        }) {
            return RestoredCursor {
                cursor: Cursor::new(index + 1, clamp_column(&all[index].text, anchor.column)),
                how: RestoreHow::ByAnchor,
            };
        }
    }

    // ③ 都找不到 ⇒ 夹到最后一行（文件短了 / 内容面目全非）
    let last = line_count.max(1);
    RestoredCursor {
        cursor: Cursor::new(last, 0),
        how: RestoreHow::Clamped,
    }
}

/// 行内偏移夹进行长（文件被改短了也不越界）。
fn clamp_column(line_text: &str, column: usize) -> usize {
    column.min(line_text.chars().count())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn anchor_prefix_takes_the_start_of_the_line_without_leading_space() {
        let text = "  let a = 1;\nfn main() {}";
        assert_eq!(anchor_prefix(text, 1), "let a = 1;");
        assert_eq!(anchor_prefix(text, 2), "fn main() {}");
        // 行号越界 ⇒ 空串（不编一行）
        assert_eq!(anchor_prefix(text, 99), "");
        // 超长行截断到上限
        let long = "x".repeat(ANCHOR_CHARS + 50);
        assert_eq!(anchor_prefix(&long, 1).chars().count(), ANCHOR_CHARS);
    }

    #[test]
    fn restoring_in_an_unchanged_file_is_exact() {
        let text = "line one\nline two\nline three";
        let anchor = remember(text, &Cursor::new(2, 4));
        let restored = restore(text, &anchor);
        assert_eq!(restored.how, RestoreHow::Exact);
        assert_eq!(restored.cursor, Cursor::new(2, 4));
        assert!(!restored.how.is_uncertain(), "精确命中不该提示不确定");
    }

    #[test]
    fn when_lines_were_inserted_above_the_anchor_finds_the_place() {
        // 上面插了两行 ⇒ 行号（2）指向别处，但锚能找到原来那一行（现在是第 4 行）
        let before = "a\nline two\nb";
        let anchor = remember(before, &Cursor::new(2, 3));
        let after = "x\ny\na\nline two\nb";
        let restored = restore(after, &anchor);
        assert_eq!(restored.how, RestoreHow::ByAnchor);
        assert_eq!(restored.cursor.line, 4);
        assert!(restored.how.is_uncertain(), "按锚找到的要如实说可能不准");
    }

    #[test]
    fn a_shorter_file_clamps_to_the_last_line_and_says_so() {
        let before = "one\ntwo\nthree\nfour\nfive";
        let anchor = remember(before, &Cursor::new(5, 1));
        let after = "one\ntwo";
        let restored = restore(after, &anchor);
        assert_eq!(restored.how, RestoreHow::Clamped);
        assert_eq!(restored.cursor.line, 2, "夹到最后一行");
        assert_eq!(restored.cursor.column, 0);
        assert!(restored.how.is_uncertain());
        // 空文件也要给一个能落的位置（第 1 行）
        let empty = restore("", &anchor);
        assert_eq!(empty.cursor.line, 1);
    }

    #[test]
    fn an_edited_line_falls_back_to_the_anchor_search_or_clamps() {
        // 原来那一行被改了前缀 ⇒ 锚找不到 ⇒ 夹到最后一行（**不猜一个位置**）
        let before = "keep this\nTARGET LINE\ntail";
        let anchor = remember(before, &Cursor::new(2, 0));
        let after = "keep this\nCHANGED ENTIRELY\ntail";
        let restored = restore(after, &anchor);
        assert_eq!(restored.how, RestoreHow::Clamped);
        assert!(restored.how.is_uncertain());
    }

    #[test]
    fn column_is_clamped_when_the_line_got_shorter() {
        let before = "short\nthis is a much longer line";
        let anchor = remember(before, &Cursor::new(2, 20));
        let after = "short\nthis is a much longer line"; // 内容不变
        assert_eq!(restore(after, &anchor).cursor.column, 20);
        // 行被改短了 ⇒ 夹到行尾（不越界）
        let shorter = "short\ny";
        let restored = restore(shorter, &anchor);
        assert!(restored.cursor.column <= 1);
    }

    #[test]
    fn keys_and_serialisation_are_stable() {
        for (how, key) in [
            (RestoreHow::Exact, "cursorRestore.exact"),
            (RestoreHow::ByAnchor, "cursorRestore.byAnchor"),
            (RestoreHow::Clamped, "cursorRestore.clamped"),
        ] {
            assert_eq!(how.key(), key);
        }
        let anchor = CursorAnchor {
            line: 3,
            column: 5,
            line_prefix: "abc".to_string(),
        };
        let text = serde_json::to_string(&anchor).unwrap();
        assert!(text.contains("\"linePrefix\""), "{text}");
        let back: CursorAnchor = serde_json::from_str(&text).unwrap();
        assert_eq!(back, anchor);
        // 行号 0 或负数一律当第 1 行（不出现"第 0 行"）
        assert_eq!(Cursor::new(0, 0).line, 1);
    }
}
