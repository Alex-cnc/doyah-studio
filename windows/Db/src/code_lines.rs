//! 代码编辑面的**行结构与换行符**（FR-EDIT-36；契约等价物：macOS 侧 `Core/CodeLines.swift`）
//!
//! 为什么放在领域层而不是界面里：行号看着是"画出来的东西"，但**哪一行算第几行**是纯逻辑 ——
//! 行终止符有好几种写法（`\n` / `\r\n` / `\r`，还有 `U+2028` / `U+2029` / `U+0085`），
//! 末尾换行算不算多一行、混排时按什么单位数，一旦错了界面上的表现是"行号跟内容对不上"，
//! 既难查也没法测。放这里就能逐条钉住。
//!
//! 两条口径（照对侧拍定的，不是顺手写的）：
//!
//! **①「行」的终止符集合 = 六种**：`\n`(LF) / `\r\n`(CRLF) / `\r`(CR) / `U+2028`(LS) /
//! `U+2029`(PS) / `U+0085`(NEL)。**`\r\n` 算一个**（不能拆成两次换行，否则每行都多出一个空行）。
//!
//! **② 末尾是行终止符 ⇒ 多一个空行**（`"a\n"` 是 **2** 行，不是 1 行）。
//! 理由 = 光标真的能停在那一行上：编辑器会为末尾终止符生成 extra line fragment，
//! 用户点在那个空行里是有反应的。少给一个号，就会出现"光标在那一行、左边却没有行号"的错位。

/// 行终止符种类（保存时按**主换行符**写回，不把文件悄悄改成另一种）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum LineEnding {
    /// `\n`
    Lf,
    /// `\r\n`
    Crlf,
    /// `\r`
    Cr,
    /// `U+2028`（行分隔符）
    Ls,
    /// `U+2029`（段分隔符）
    Ps,
    /// `U+0085`（下一行）
    Nel,
}

impl LineEnding {
    /// 这个终止符的字面写法（保存时用它拼回去）。
    pub const fn text(self) -> &'static str {
        match self {
            LineEnding::Lf => "\n",
            LineEnding::Crlf => "\r\n",
            LineEnding::Cr => "\r",
            LineEnding::Ls => "\u{2028}",
            LineEnding::Ps => "\u{2029}",
            LineEnding::Nel => "\u{0085}",
        }
    }
}

/// 一行：内容 + 它后面那个终止符（最后一行可能没有，为 `None`）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Line {
    /// 内容（**不含**终止符）
    pub text: String,
    /// 这一行后面的终止符；最后一行若没有终止符则为 `None`
    pub ending: Option<LineEnding>,
    /// 本行在**原文字节**里的起点（前端要按原文切片时用得上）
    pub byte_start: usize,
}

/// 认一个位置上的行终止符：返回 `(种类, 吃掉几个字节)`。
fn ending_at(bytes: &[u8], index: usize) -> Option<(LineEnding, usize)> {
    match bytes.get(index)? {
        b'\n' => Some((LineEnding::Lf, 1)),
        b'\r' => {
            // `\r\n` 算**一个**终止符
            if bytes.get(index + 1) == Some(&b'\n') {
                Some((LineEnding::Crlf, 2))
            } else {
                Some((LineEnding::Cr, 1))
            }
        }
        _ => {
            // 三个多字节终止符：U+2028 / U+2029 / U+0085（都在 3 字节区间里）
            let rest = &bytes[index..];
            if rest.starts_with("\u{2028}".as_bytes()) {
                Some((LineEnding::Ls, 3))
            } else if rest.starts_with("\u{2029}".as_bytes()) {
                Some((LineEnding::Ps, 3))
            } else if rest.starts_with("\u{0085}".as_bytes()) {
                Some((LineEnding::Nel, 2))
            } else {
                None
            }
        }
    }
}

/// 把文本切成行（`lines`）。
///
/// - 空文档 ⇒ **一行**（空内容、无终止符）：「什么都没有」仍然是第 1 行，光标可以落上去；
/// - `"a\n"` ⇒ **两行**（第二行空内容、无终止符）—— 见口径 ②；
/// - `"a"` ⇒ 一行。
pub fn lines(text: &str) -> Vec<Line> {
    let bytes = text.as_bytes();
    let mut result: Vec<Line> = Vec::new();
    let mut line_start = 0usize;
    let mut cursor = 0usize;

    while cursor < bytes.len() {
        match ending_at(bytes, cursor) {
            Some((ending, width)) => {
                result.push(Line {
                    text: text[line_start..cursor].to_string(),
                    ending: Some(ending),
                    byte_start: line_start,
                });
                cursor += width;
                line_start = cursor;
            }
            None => {
                // 走到下一个字符的边界（多字节字符不能按字节步进）
                let ch = text[cursor..].chars().next().expect("cursor 在字符边界上");
                cursor += ch.len_utf8();
            }
        }
    }
    // 收尾：还有内容 ⇒ 最后一行；否则（末尾正好是终止符）⇒ 补一个**空行**
    if line_start < bytes.len() || result.is_empty() || text.is_empty() {
        result.push(Line {
            text: text[line_start..].to_string(),
            ending: None,
            byte_start: line_start,
        });
    } else {
        result.push(Line {
            text: String::new(),
            ending: None,
            byte_start: line_start,
        });
    }
    result
}

/// 行数（空文档 = 1）。**口径 ②**：末尾终止符算多一行。
pub fn line_count(text: &str) -> usize {
    lines(text).len()
}

/// 行号列要留几位数（`9 → 1` / `10 → 2` / `10000 → 5`）。
///
/// 宽度不能用固定值：99 行与 10000 行的列宽不一样，写死就会在第 100 行处把数字挤掉。
pub fn gutter_digits(text: &str) -> usize {
    digits_of(line_count(text))
}

/// 由行数算列宽（供界面与单测共用同一口径）。
pub fn digits_of(line_count: usize) -> usize {
    let count = line_count.max(1).to_string();
    count.len()
}

/// 主换行符：出现**次数最多**的那一种；一次都没有 ⇒ `None`（纯单行文件，无从判断）。
///
/// 平手时按"先出现的那种"定（读文件时人看到的第一种通常就是它）。
pub fn dominant_ending(text: &str) -> Option<LineEnding> {
    let mut tally: Vec<(LineEnding, usize, usize)> = Vec::new(); // (种类, 次数, 首次位置)
    for (index, line) in lines(text).iter().enumerate() {
        if let Some(ending) = line.ending {
            match tally.iter_mut().find(|(kind, _, _)| *kind == ending) {
                Some(entry) => entry.1 += 1,
                None => tally.push((ending, 1, index)),
            }
        }
    }
    tally
        .into_iter()
        .max_by(|a, b| a.1.cmp(&b.1).then(b.2.cmp(&a.2)))
        .map(|(kind, _, _)| kind)
}

/// 混排检测：文件里是否**同时**有不止一种行终止符（要如实告诉用户，别偷偷统一）。
pub fn is_mixed(text: &str) -> bool {
    let mut seen: Vec<LineEnding> = Vec::new();
    for line in lines(text) {
        if let Some(ending) = line.ending {
            if !seen.contains(&ending) {
                seen.push(ending);
                if seen.len() > 1 {
                    return true;
                }
            }
        }
    }
    false
}

/// 按指定换行符写回（**保存时用**：不把文件悄悄改成另一种）。
///
/// 注意：这会**统一**所有行终止符 —— 调用方要么用 `dominant_ending` 给的那个（保持不变），
/// 要么**明确**选择统一（界面要如实说"这次保存把换行符统一成 X 了"）。
pub fn join_with(text: &str, ending: LineEnding) -> String {
    let mut out = String::with_capacity(text.len());
    for line in lines(text) {
        out.push_str(&line.text);
        // 最后一行没有终止符 ⇒ 不补（否则每次保存都会长出一行）
        if line.ending.is_some() {
            out.push_str(ending.text());
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_document_is_one_line() {
        let result = lines("");
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].text, "");
        assert!(result[0].ending.is_none());
        assert_eq!(line_count(""), 1);
    }

    #[test]
    fn trailing_terminator_gives_an_extra_empty_line() {
        // 口径 ②：`a\n` 是 **2** 行（光标能停在第二行）
        let result = lines("a\n");
        assert_eq!(result.len(), 2);
        assert_eq!(result[0].text, "a");
        assert_eq!(result[0].ending, Some(LineEnding::Lf));
        assert_eq!(result[1].text, "");
        assert!(result[1].ending.is_none());
        // 没有终止符 ⇒ 就是 1 行
        assert_eq!(line_count("a"), 1);
    }

    #[test]
    fn crlf_counts_as_one_terminator_not_two() {
        // 拆错的话每行都会多出一个空行
        let result = lines("a\r\nb\r\n");
        assert_eq!(result.len(), 3, "a / b / 末尾空行");
        assert_eq!(result[0].ending, Some(LineEnding::Crlf));
        assert_eq!(result[1].text, "b");
        assert_eq!(result[1].ending, Some(LineEnding::Crlf));
        // 单独一个 `\r`（老 Mac 写法）也算一种
        let cr = lines("a\rb");
        assert_eq!(cr.len(), 2);
        assert_eq!(cr[0].ending, Some(LineEnding::Cr));
    }

    #[test]
    fn unicode_line_separators_are_recognised() {
        // U+2028 / U+2029 / U+0085 都算行终止符（这三种在真实数据里少见但确实存在）
        for (ending, text) in [
            (LineEnding::Ls, "a\u{2028}b"),
            (LineEnding::Ps, "a\u{2029}b"),
            (LineEnding::Nel, "a\u{0085}b"),
        ] {
            let result = lines(text);
            assert_eq!(result.len(), 2, "{text:?} 应当是两行");
            assert_eq!(result[0].ending, Some(ending));
            assert_eq!(result[1].text, "b");
        }
    }

    #[test]
    fn multibyte_content_does_not_break_line_splitting() {
        // 中文与 emoji 都是多字节：按字节步进会把字符切断
        let text = "中文😀\n第二行\n";
        let result = lines(text);
        assert_eq!(result.len(), 3);
        assert_eq!(result[0].text, "中文😀");
        assert_eq!(result[1].text, "第二行");
        assert_eq!(result[2].text, "");
        // 字节起点也必须落在字符边界上（能安全切片）
        for line in &result {
            assert!(text.is_char_boundary(line.byte_start), "{} 不在字符边界", line.byte_start);
        }
    }

    #[test]
    fn gutter_digits_grows_with_the_line_count() {
        assert_eq!(digits_of(1), 1);
        assert_eq!(digits_of(9), 1);
        assert_eq!(digits_of(10), 2);
        assert_eq!(digits_of(99), 2);
        assert_eq!(digits_of(100), 3);
        assert_eq!(digits_of(10_000), 5);
        // 0 行（理论上不会有）也至少一位
        assert_eq!(digits_of(0), 1);
        // 从文本算：9 行 1 位、10 行 2 位
        let nine = "1\n2\n3\n4\n5\n6\n7\n8\n9";
        assert_eq!(gutter_digits(nine), 1);
        let ten = format!("{nine}\n10");
        assert_eq!(gutter_digits(&ten), 2);
    }

    #[test]
    fn dominant_ending_is_the_most_frequent_and_mixed_is_reported() {
        assert_eq!(dominant_ending("a\nb\nc"), Some(LineEnding::Lf));
        assert_eq!(dominant_ending("a\r\nb\r\nc"), Some(LineEnding::Crlf));
        // 一次都没有 ⇒ 无从判断
        assert_eq!(dominant_ending("single line"), None);
        // 混排：多数是 CRLF，少数 LF ⇒ 主换行符是 CRLF，且**如实报混排**
        let mixed = "a\r\nb\r\nc\nd";
        assert_eq!(dominant_ending(mixed), Some(LineEnding::Crlf));
        assert!(is_mixed(mixed));
        // 平手时先出现的算主
        assert_eq!(dominant_ending("a\r\nb\n"), Some(LineEnding::Crlf));
        assert!(!is_mixed("a\r\nb\r\n"));
    }

    #[test]
    fn join_with_round_trips_and_never_grows_a_line() {
        let original = "a\r\nb\r\n";
        // 用**主换行符**写回 ⇒ 逐字节相同（不把文件悄悄改成另一种）
        let ending = dominant_ending(original).unwrap();
        assert_eq!(join_with(original, ending), original);
        // 明确统一成 LF：内容行数不变、不额外长出一行
        let unified = join_with(original, LineEnding::Lf);
        assert_eq!(unified, "a\nb\n");
        assert_eq!(line_count(&unified), line_count(original));
        // 没有末尾终止符的文本写回后也不该多一行
        assert_eq!(join_with("a\nb", LineEnding::Lf), "a\nb");
        assert_eq!(line_count("a\nb"), 2);
    }
}
