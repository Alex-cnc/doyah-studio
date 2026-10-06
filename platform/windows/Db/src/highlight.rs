//! 编辑面的**高亮分词**（FR-EDIT-36 / 计划 2.2；契约等价物：macOS 侧 `Core/CodeLexer.swift` 的行为）
//!
//! 本层只做**一条一趟的词法扫描**，不做语法分析：认出注释 / 字符串 / 数字 / 关键字四类，
//! 其余原样当普通文本。**够用且可测**是这里的目标 —— 一门语言的全量词法是一辈子的事，
//! 而"注释里的关键字被上了色""字符串没闭合把后面整段吞掉"这两个错才是用户一眼能看出来的。
//!
//! 三条口径：
//!   ① **偏移都是字节偏移**（前端拿同一份原文切片即可；不做"行列"换算，那是另一件事）；
//!   ② **未闭合的字符串 / 块注释 ⇒ 一直吃到文末**（不是吃掉一行就算完 —— 那会让后面的代码
//!      全部错色，比"整段都当字符串"更难懂）；
//!   ③ **认不出语言 ⇒ 空表**（无高亮，而不是"随便上一套色"）。

use crate::workspace::TextLanguage;

/// 分词结果的类别（前端按它取颜色令牌）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum CodeTokenKind {
    Comment,
    Str,
    Number,
    Keyword,
}

/// 一段带位置的分词（`start` / `end` 都是**字节偏移**，`[start, end)`）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CodeSpan {
    pub start: usize,
    pub end: usize,
    pub kind: CodeTokenKind,
}

/// 一门语言的词法面貌。
#[derive(Debug, Clone, Copy)]
pub struct CodeSyntax {
    pub line_comment: &'static [&'static str],
    pub block_comment: Option<(&'static str, &'static str)>,
    /// 字符串定界符（单字符的；三引号之类的暂不处理 —— 本侧只做常见前 10 门语言）
    pub string_delims: &'static [char],
    /// 字符串里的转义符（`None` = 这门语言里反斜杠不是转义，如 SQL）
    pub escape: Option<char>,
    pub keywords: &'static [&'static str],
    /// 语言**大小写不敏感**（SQL）
    pub case_insensitive_keywords: bool,
}

const RUST_KEYWORDS: &[&str] = &[
    "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern",
    "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub",
    "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type",
    "unsafe", "use", "where", "while",
];
const JS_KEYWORDS: &[&str] = &[
    "async", "await", "break", "case", "catch", "class", "const", "continue", "default", "delete",
    "do", "else", "export", "extends", "false", "finally", "for", "from", "function", "if",
    "import", "in", "instanceof", "let", "new", "null", "of", "return", "static", "super",
    "switch", "this", "throw", "true", "try", "typeof", "undefined", "var", "void", "while",
    "yield",
];
const SQL_KEYWORDS: &[&str] = &[
    "add", "all", "alter", "and", "as", "asc", "begin", "between", "by", "case", "cast", "check",
    "column", "commit", "constraint", "create", "cross", "default", "delete", "desc", "distinct",
    "drop", "else", "end", "exists", "false", "foreign", "from", "full", "group", "having", "in",
    "index", "inner", "insert", "into", "is", "join", "key", "left", "like", "limit", "not",
    "null", "offset", "on", "or", "order", "outer", "primary", "references", "right", "rollback",
    "select", "set", "table", "then", "true", "union", "unique", "update", "values", "when",
    "where", "with",
];
const TOML_KEYWORDS: &[&str] = &["true", "false"];
const SHELL_KEYWORDS: &[&str] = &[
    "case", "do", "done", "elif", "else", "esac", "fi", "for", "function", "if", "in", "then",
    "until", "while", "export", "local", "readonly", "return", "set", "shift", "unset",
];

/// 语言的词法面貌（**认不出 ⇒ `None`**，调用方给空表）。
pub fn syntax_of(language: TextLanguage) -> Option<CodeSyntax> {
    Some(match language {
        TextLanguage::Rust => CodeSyntax {
            line_comment: &["//"],
            block_comment: Some(("/*", "*/")),
            string_delims: &['"'],
            escape: Some('\\'),
            keywords: RUST_KEYWORDS,
            case_insensitive_keywords: false,
        },
        TextLanguage::TypeScript | TextLanguage::JavaScript | TextLanguage::Json | TextLanguage::Css => CodeSyntax {
            line_comment: if language == TextLanguage::Json { &[] } else { &["//"] },
            block_comment: Some(("/*", "*/")),
            string_delims: &['"', '\''],
            escape: Some('\\'),
            keywords: if language == TextLanguage::TypeScript || language == TextLanguage::JavaScript {
                JS_KEYWORDS
            } else {
                &[]
            },
            case_insensitive_keywords: false,
        },
        TextLanguage::Sql => CodeSyntax {
            // SQL 的注释有两种（`--` 行注释、`/* */` 块注释）
            line_comment: &["--"],
            block_comment: Some(("/*", "*/")),
            string_delims: &['\'', '"'],
            escape: None, // SQL 里单引号靠"两个单引号"转义，反斜杠不是转义符
            keywords: SQL_KEYWORDS,
            case_insensitive_keywords: true,
        },
        TextLanguage::Shell => CodeSyntax {
            line_comment: &["#"],
            block_comment: None,
            string_delims: &['"', '\''],
            escape: Some('\\'),
            keywords: SHELL_KEYWORDS,
            case_insensitive_keywords: false,
        },
        TextLanguage::Toml | TextLanguage::Yaml => CodeSyntax {
            line_comment: &["#"],
            block_comment: None,
            string_delims: &['"', '\''],
            escape: Some('\\'),
            keywords: TOML_KEYWORDS,
            case_insensitive_keywords: false,
        },
        TextLanguage::Html => CodeSyntax {
            line_comment: &[],
            block_comment: Some(("<!--", "-->")),
            string_delims: &['"', '\''],
            escape: None,
            keywords: &[],
            case_insensitive_keywords: false,
        },
        // Markdown 与纯文本**不上色**（Markdown 的"高亮"是另一件事：要解析结构）
        TextLanguage::Markdown | TextLanguage::PlainText => return None,
    })
}

fn is_word_char(ch: char) -> bool {
    ch.is_alphanumeric() || ch == '_' || ch == '$'
}

/// 扫描：返回按起点升序、互不重叠的分词表。
pub fn tokenize(text: &str, language: TextLanguage) -> Vec<CodeSpan> {
    let Some(syntax) = syntax_of(language) else {
        return Vec::new();
    };
    let bytes = text.as_bytes();
    let mut spans: Vec<CodeSpan> = Vec::new();
    let mut index = 0usize;

    while index < bytes.len() {
        // ① 行注释
        if let Some(marker) = syntax
            .line_comment
            .iter()
            .find(|marker| bytes[index..].starts_with(marker.as_bytes()))
        {
            let start = index;
            index += marker.len();
            while index < bytes.len() && !is_line_break_at(bytes, index) {
                index += char_len_at(text, index);
            }
            spans.push(CodeSpan { start, end: index, kind: CodeTokenKind::Comment });
            continue;
        }

        // ② 块注释（未闭合 ⇒ 吃到文末，口径 ②）
        if let Some((open, close)) = syntax.block_comment {
            if bytes[index..].starts_with(open.as_bytes()) {
                let start = index;
                index += open.len();
                match text[index..].find(close) {
                    Some(offset) => index += offset + close.len(),
                    None => index = bytes.len(),
                }
                spans.push(CodeSpan { start, end: index, kind: CodeTokenKind::Comment });
                continue;
            }
        }

        // ③ 字符串（未闭合 ⇒ 吃到文末，口径 ②）
        let ch = text[index..].chars().next().expect("index 在字符边界上");
        if syntax.string_delims.contains(&ch) {
            let start = index;
            index += ch.len_utf8();
            while index < bytes.len() {
                let current = text[index..].chars().next().expect("index 在字符边界上");
                if Some(current) == syntax.escape {
                    index += current.len_utf8();
                    if index < bytes.len() {
                        index += char_len_at(text, index);
                    }
                    continue;
                }
                index += current.len_utf8();
                if current == ch {
                    break;
                }
                if is_line_break_at(bytes, index - current.len_utf8()) {
                    // **不按行停**：未闭合的字符串一直吃到文末（口径 ②）。
                    // 这里原先写的是"到行尾就收"，与口径 ② 矛盾 —— 半截字符串会让后面的行
                    // 全留在字符串外面、逐行错色；是用例把我这条不一致抓出来的（保留注释备案）。
                    continue;
                }
            }
            spans.push(CodeSpan { start, end: index, kind: CodeTokenKind::Str });
            continue;
        }

        // ④ 数字
        if ch.is_ascii_digit() {
            let start = index;
            while index < bytes.len() {
                let current = text[index..].chars().next().expect("index 在字符边界上");
                if current.is_ascii_alphanumeric() || current == '.' || current == '_' {
                    index += current.len_utf8();
                } else {
                    break;
                }
            }
            spans.push(CodeSpan { start, end: index, kind: CodeTokenKind::Number });
            continue;
        }

        // ⑤ 词（可能是关键字）
        if is_word_char(ch) {
            let start = index;
            while index < bytes.len() {
                let current = text[index..].chars().next().expect("index 在字符边界上");
                if is_word_char(current) {
                    index += current.len_utf8();
                } else {
                    break;
                }
            }
            let word = &text[start..index];
            let hit = if syntax.case_insensitive_keywords {
                syntax.keywords.iter().any(|k| k.eq_ignore_ascii_case(word))
            } else {
                syntax.keywords.contains(&word)
            };
            if hit {
                spans.push(CodeSpan { start, end: index, kind: CodeTokenKind::Keyword });
            }
            continue;
        }

        // 其余：普通文本，继续往前
        index += ch.len_utf8();
    }
    spans
}

fn is_line_break_at(bytes: &[u8], index: usize) -> bool {
    matches!(bytes.get(index), Some(b'\n') | Some(b'\r'))
}

fn char_len_at(text: &str, index: usize) -> usize {
    text[index..].chars().next().map(char::len_utf8).unwrap_or(1)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kinds(text: &str, language: TextLanguage) -> Vec<(CodeTokenKind, String)> {
        tokenize(text, language)
            .into_iter()
            .map(|span| (span.kind, text[span.start..span.end].to_string()))
            .collect()
    }

    #[test]
    fn spans_are_ordered_non_overlapping_and_on_char_boundaries() {
        let text = "fn main() { let s = \"中文😀\"; /* 块 */ } // 尾注";
        let spans = tokenize(text, TextLanguage::Rust);
        assert!(!spans.is_empty());
        let mut previous_end = 0;
        for span in &spans {
            assert!(span.start >= previous_end, "分词必须升序且不重叠");
            assert!(span.start < span.end);
            assert!(text.is_char_boundary(span.start) && text.is_char_boundary(span.end), "必须在字符边界上");
            previous_end = span.end;
        }
    }

    #[test]
    fn comments_strings_numbers_and_keywords_are_recognised() {
        let text = "let n = 42; // 注释里的 let 不该上色";
        let found = kinds(text, TextLanguage::Rust);
        assert!(found.contains(&(CodeTokenKind::Keyword, "let".to_string())));
        assert!(found.contains(&(CodeTokenKind::Number, "42".to_string())));
        let comment = found.iter().find(|(kind, _)| *kind == CodeTokenKind::Comment).unwrap();
        assert_eq!(comment.1, "// 注释里的 let 不该上色");
        // 注释里的 let 只有一处关键字（就是语句开头那个）
        assert_eq!(found.iter().filter(|(k, v)| *k == CodeTokenKind::Keyword && v == "let").count(), 1);

        let with_string = kinds("let s = \"let\";", TextLanguage::Rust);
        assert!(with_string.contains(&(CodeTokenKind::Str, "\"let\"".to_string())));
        // 字符串里的 let 也不算关键字
        assert_eq!(with_string.iter().filter(|(k, _)| *k == CodeTokenKind::Keyword).count(), 1);
    }

    #[test]
    fn unterminated_string_or_block_comment_eats_to_the_end_of_file() {
        // 口径 ②：不是"吃到行尾就算完"（那会让后面的代码全部错色）
        let text = "let a = 1;\nlet b = \"没闭合\nlet c = 2;";
        let found = kinds(text, TextLanguage::Rust);
        let string = found.iter().find(|(k, _)| *k == CodeTokenKind::Str).unwrap();
        assert!(string.1.ends_with("let c = 2;"), "未闭合字符串一直吃到文末：{}", string.1);
        // 关键字只剩第一行那个 `let`（第二行那个 `let` 在引号**之前**，所以是 2 个）——
        // 关键是**字符串之后**的代码没有被当成代码
        let keywords: Vec<&str> = found
            .iter()
            .filter(|(k, _)| *k == CodeTokenKind::Keyword)
            .map(|(_, v)| v.as_str())
            .collect();
        assert_eq!(keywords, vec!["let", "let"], "字符串之前的两个 let 仍然是关键字");
        assert!(!found.iter().any(|(k, v)| *k == CodeTokenKind::Number && v == "2"), "字符串里的 2 不该被当数字");

        let block = "/* 没闭合\nfn main() {}";
        let found = kinds(block, TextLanguage::Rust);
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].1, block);
    }

    #[test]
    fn sql_is_case_insensitive_and_has_two_comment_styles() {
        let found = kinds("SELECT id FROM t -- 取注释\nWHERE x = 1 /* 块注释 */", TextLanguage::Sql);
        let keywords: Vec<&str> = found.iter().filter(|(k, _)| *k == CodeTokenKind::Keyword).map(|(_, v)| v.as_str()).collect();
        assert!(keywords.contains(&"SELECT") && keywords.contains(&"FROM") && keywords.contains(&"WHERE"));
        assert_eq!(found.iter().filter(|(k, _)| *k == CodeTokenKind::Comment).count(), 2, "两种注释都要认出来");
        // SQL 里反斜杠不是转义符 ⇒ 字符串里的 `\` 不吞下一个引号
        let backslash = kinds("select 'a\\' from t", TextLanguage::Sql);
        let string = backslash.iter().find(|(k, _)| *k == CodeTokenKind::Str).unwrap();
        assert_eq!(string.1, "'a\\'");
    }

    #[test]
    fn language_specific_markers_differ() {
        // `#` 在 shell 是注释，在 rust 不是
        assert!(kinds("# comment", TextLanguage::Shell).iter().any(|(k, _)| *k == CodeTokenKind::Comment));
        assert!(kinds("# not a comment", TextLanguage::Rust).is_empty());
        // HTML 的块注释是 `<!-- -->`
        let html = kinds("<!-- 注释 --><p>hi</p>", TextLanguage::Html);
        assert!(html.iter().any(|(k, v)| *k == CodeTokenKind::Comment && v == "<!-- 注释 -->"));
        // YAML 用 `#`
        assert!(kinds("# key", TextLanguage::Yaml).iter().any(|(k, _)| *k == CodeTokenKind::Comment));
    }

    #[test]
    fn json_has_no_keywords_and_no_line_comments() {
        let found = kinds("{\"a\": 1} // 不是注释", TextLanguage::Json);
        // 字符串认出来了
        assert!(found.iter().any(|(k, v)| *k == CodeTokenKind::Str && v == "\"a\""));
        // 数字认出来了
        assert!(found.iter().any(|(k, v)| *k == CodeTokenKind::Number && v == "1"));
        // JSON 没有行注释：`// 不是注释` 不该被当注释
        assert!(!found.iter().any(|(k, _)| *k == CodeTokenKind::Comment));
    }

    #[test]
    fn plain_text_and_markdown_get_no_highlighting_at_all() {
        assert!(tokenize("let x = 1;", TextLanguage::PlainText).is_empty());
        assert!(tokenize("# 标题\n**粗体**", TextLanguage::Markdown).is_empty());
        assert!(syntax_of(TextLanguage::PlainText).is_none());
    }

    #[test]
    fn escaped_quotes_do_not_end_a_string() {
        let found = kinds(r#"let s = "a\"b"; let t = 2;"#, TextLanguage::Rust);
        let string = found.iter().find(|(k, _)| *k == CodeTokenKind::Str).unwrap();
        assert_eq!(string.1, r#""a\"b""#);
        // 后面的代码照常识别（没被字符串吞掉）
        assert!(found.iter().any(|(k, v)| *k == CodeTokenKind::Number && v == "2"));
    }
}
