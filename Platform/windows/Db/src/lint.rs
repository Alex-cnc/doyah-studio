//! FR-EDIT-03 / FR-EDIT-56 客户端静态检查（编辑面用）—— **诊断的唯一出处**
//!
//! 为什么在领域层而不是前端：需求规范书写明「**检查器与界面同源，不许两套判定**」。执行与高亮
//! 用的词法已经在 `sql::tokenize`（同一套引号 / 注释规则），本模块**只消费它**、再补两条它不管的
//! 规则（dollar-quote、括号配对），不另写一个扫描器去判「字符串在哪结束」。
//!
//! 四条规则（与 FR-EDIT-03 逐条对应）：
//!   ① 未闭合单引号字符串；② 未闭合块注释；③ 未闭合 dollar-quote（`$$` / `$tag$`）；
//!   ④ 括号不配平（多余右括号 / 左括号没闭合 / 配对种类不一致）。
//!
//! 三条口径：
//!   · **偏移是字符下标（0 基）**，不是字节 —— 前端 `String.prototype.slice` 按 UTF-16 单元切；
//!     本仓既有的 `highlight_sql` 用的是字节口径，含中文注释后会错位（那条隐患不在本模块复制，
//!     已登记在运行日志里）。用例 `a_chinese_comment_before_the_problem_does_not_shift_the_mark` 守这条。
//!   · 范围 `[start, end)`；`end == start` 的空区间不产出（没有可画的位置）。
//!   · 消息是**给人看的一句中文**（正文说明不跟界面语言走，与既有服务端提示同口径）。

use serde::{Deserialize, Serialize};

use crate::sql::{tokenize, TokenKind};

/// 严重度（界面按它选颜色：error 红虚下划线 / warning 告警色 / info 中性）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Severity {
    Error,
    Warning,
    Info,
}

/// 一条诊断：原文里的字符区间 + 一句可读说明。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Diagnostic {
    /// 起始字符下标（0 基，含）
    pub start: usize,
    /// 结束字符下标（0 基，不含）
    pub end: usize,
    pub severity: Severity,
    pub message: String,
}

impl Diagnostic {
    fn error(start: usize, end: usize, message: String) -> Self {
        Diagnostic { start, end, severity: Severity::Error, message }
    }
}

/// 字节偏移 → 字符下标（只对**字符边界**的偏移有意义；token 的 start / end 都是）。
fn char_index_map(sql: &str) -> Vec<usize> {
    let mut map = vec![0usize; sql.len() + 1];
    let mut ci = 0usize;
    let mut bi = 0usize;
    for ch in sql.chars() {
        map[bi] = ci;
        bi += ch.len_utf8();
        ci += 1;
    }
    map[sql.len()] = ci;
    map
}

/// 字面量（`'…'` / `"…"`）是否真的收尾：**`''` 是转义，不算收尾**。
///
/// 为什么不能只看「最后一个是引号」：`'a''` 的最后两个字符是转义对，字符串其实没闭合
/// （`tokenize` 会一路吃到文末）；直接把「末字符是引号」当收尾会把这种漏掉。
fn literal_closed(text: &str, quote: u8) -> bool {
    let bytes = text.as_bytes();
    if bytes.len() < 2 || bytes[0] != quote {
        return false;
    }
    let mut i = 1usize;
    while i < bytes.len() {
        if bytes[i] == quote {
            if i + 1 < bytes.len() && bytes[i + 1] == quote {
                i += 2;
                continue;
            }
            return true;
        }
        i += 1;
    }
    false
}

fn opens_with(ch: char) -> bool {
    matches!(ch, '(' | '[' | '{')
}

fn closes_with(ch: char) -> bool {
    matches!(ch, ')' | ']' | '}')
}

fn partner(open: char) -> char {
    match open {
        '(' => ')',
        '[' => ']',
        _ => '}',
    }
}

/// 跑一遍静态检查。**纯函数、不失败**（再多问题也只返回清单，不返回 Err —— 编辑面不能因为
/// 一段没写完的 SQL 就报错）。
pub fn diagnose(sql: &str) -> Vec<Diagnostic> {
    if sql.trim().is_empty() {
        return Vec::new();
    }
    let chars: Vec<char> = sql.chars().collect();
    let map = char_index_map(sql);
    let tokens = tokenize(sql);
    let mut out: Vec<Diagnostic> = Vec::new();

    // ① 未闭合字面量 / 块注释 —— 直接问分词结果（同一套规则，不重写）
    //
    // 只取这三类：其余 token 的位置在**含多字节字符**时可能落在字符中间（`tokenize` 对非 ASCII
    // 逐字节出标点），按它切原文会 panic —— 那是既有分词的字节口径，本模块不跟着踩。
    for token in &tokens {
        if !matches!(
            token.kind,
            TokenKind::String | TokenKind::QuotedIdent | TokenKind::BlockComment
        ) {
            continue;
        }
        if !sql.is_char_boundary(token.start) || !sql.is_char_boundary(token.end) {
            continue;
        }
        let raw = &sql[token.start..token.end];
        let start = map[token.start];
        let end = map[token.end];
        match token.kind {
            TokenKind::String => {
                if !literal_closed(raw, b'\'') {
                    out.push(Diagnostic::error(
                        start,
                        end,
                        "字符串没闭合：这个单引号到文末也没找到收尾（连续两个 '' 是转义，不算收尾）"
                            .to_string(),
                    ));
                }
            }
            TokenKind::QuotedIdent => {
                if !literal_closed(raw, b'"') {
                    out.push(Diagnostic::error(
                        start,
                        end,
                        "引号标识符没闭合：这个双引号到文末也没找到收尾（连续两个 \"\" 是转义）"
                            .to_string(),
                    ));
                }
            }
            TokenKind::BlockComment => {
                // `/*/` 这种长度不足 4 的不能靠「末尾是 */」判（`/` 会与前一个 `*` 假配对）
                if !(raw.len() >= 4 && raw.ends_with("*/")) {
                    out.push(Diagnostic::error(
                        start,
                        end,
                        "块注释没闭合：`/*` 之后到文末也没找到 `*/`".to_string(),
                    ));
                }
            }
            _ => {}
        }
    }

    // ② 哪些字符属于字面量 / 注释（后面两条规则只扫**代码区**，不然字符串里的括号会被误判）
    let mut opaque = vec![false; chars.len()];
    for token in &tokens {
        if matches!(
            token.kind,
            TokenKind::String | TokenKind::QuotedIdent | TokenKind::LineComment | TokenKind::BlockComment
        ) && sql.is_char_boundary(token.start)
            && sql.is_char_boundary(token.end)
        {
            let start = map[token.start];
            let end = map[token.end];
            for slot in opaque.iter_mut().take(end).skip(start) {
                *slot = true;
            }
        }
    }

    // ③ dollar-quote：分词不认识它（`$` 只在标识符内允许），这里补一遍
    let mut i = 0usize;
    while i < chars.len() {
        if opaque[i] || chars[i] != '$' {
            i += 1;
            continue;
        }
        let mut j = i + 1;
        while j < chars.len() && (chars[j].is_ascii_alphanumeric() || chars[j] == '_') {
            j += 1;
        }
        // `$1` 这类位置占位符：`$` 后面没有第二个 `$` ⇒ 不是 dollar-quote
        if j >= chars.len() || chars[j] != '$' {
            i += 1;
            continue;
        }
        let delim: String = chars[i..=j].iter().collect();
        let body_start = j + 1;
        let mut closing: Option<usize> = None;
        let mut k = body_start;
        while k + delim.chars().count() <= chars.len() {
            if chars[k] == '$' {
                let candidate: String = chars[k..k + delim.chars().count()].iter().collect();
                if candidate == delim {
                    closing = Some(k);
                    break;
                }
            }
            k += 1;
        }
        match closing {
            None => {
                out.push(Diagnostic::error(
                    i,
                    j + 1,
                    format!("dollar-quote 没闭合：`{delim}` 之后没找到同一个收尾标记"),
                ));
                i = j + 1;
            }
            Some(close) => {
                // 已闭合：正文对后面的括号扫描是**不透明**的（里面的 `(` 不算代码）
                let end = close + delim.chars().count();
                for slot in opaque.iter_mut().take(end).skip(i) {
                    *slot = true;
                }
                i = end;
            }
        }
    }

    // ④ 括号配对：多余右括号 / 种类不一致 / 到文末还有没闭合的左括号
    let mut stack: Vec<(usize, char)> = Vec::new();
    for (index, ch) in chars.iter().enumerate() {
        if opaque[index] {
            continue;
        }
        if opens_with(*ch) {
            stack.push((index, *ch));
            continue;
        }
        if !closes_with(*ch) {
            continue;
        }
        match stack.pop() {
            None => out.push(Diagnostic::error(
                index,
                index + 1,
                format!("多余的右括号 {ch}：它前面没有与之配对的左括号"),
            )),
            Some((_, open)) => {
                if partner(open) != *ch {
                    out.push(Diagnostic::error(
                        index,
                        index + 1,
                        format!("括号配对不一致：前面开的是 {open}，这里却用 {ch} 收尾"),
                    ));
                }
            }
        }
    }
    for (index, open) in stack {
        out.push(Diagnostic::error(
            index,
            index + 1,
            format!("左括号 {open} 没闭合：到文末也没等到对应的 {}", partner(open)),
        ));
    }

    out.sort_by(|a, b| a.start.cmp(&b.start).then(a.end.cmp(&b.end)));
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn messages(list: &[Diagnostic]) -> Vec<String> {
        list.iter().map(|d| d.message.clone()).collect()
    }

    fn slice(sql: &str, d: &Diagnostic) -> String {
        sql.chars().skip(d.start).take(d.end - d.start).collect()
    }

    #[test]
    fn clean_sql_has_no_diagnostics() {
        assert!(diagnose("select id, name from app.accounts where id in (1, 2)").is_empty());
        assert!(diagnose("").is_empty());
        assert!(diagnose("   \n  ").is_empty());
    }

    #[test]
    fn an_unterminated_string_is_reported_at_its_opening_quote() {
        let sql = "select 'abc from t";
        let found = diagnose(sql);
        assert_eq!(found.len(), 1, "{found:?}");
        assert_eq!(found[0].severity, Severity::Error);
        assert_eq!(slice(sql, &found[0]), "'abc from t");
        assert!(found[0].message.contains("字符串没闭合"), "{found:?}");
    }

    #[test]
    fn an_escaped_quote_pair_does_not_close_the_string() {
        // `'a''` —— 最后两个引号是转义对，字符串其实没闭合（别只看末字符是引号）
        let sql = "select 'a''";
        let found = diagnose(sql);
        assert_eq!(found.len(), 1, "{found:?}");
        assert!(found[0].message.contains("字符串没闭合"), "{found:?}");
    }

    #[test]
    fn a_properly_closed_string_with_escapes_is_not_reported() {
        assert!(diagnose("select 'it''s fine' from t").is_empty());
        assert!(diagnose("select \"weird \"\"name\"\"\" from t").is_empty());
    }

    #[test]
    fn an_unterminated_block_comment_is_reported() {
        let sql = "select 1 /* 说明没写完";
        let found = diagnose(sql);
        assert_eq!(found.len(), 1, "{found:?}");
        assert!(found[0].message.contains("块注释没闭合"), "{found:?}");
        assert_eq!(slice(sql, &found[0]), "/* 说明没写完");
    }

    #[test]
    fn the_shortest_unterminated_block_comment_is_not_mistaken_for_a_closed_one() {
        // `/*/` 只有三个字符：末两字符看着像 `*/`，其实是同一个 `*`
        let found = diagnose("select 1 /*/ 2");
        assert_eq!(found.len(), 1, "{found:?}");
        assert!(found[0].message.contains("块注释没闭合"), "{found:?}");
        assert!(diagnose("select 1 /* ok */ 2").is_empty());
    }

    #[test]
    fn an_unterminated_dollar_quote_is_reported_with_its_tag() {
        let sql = "select $body$ 里面的括号不算代码";
        let found = diagnose(sql);
        assert_eq!(found.len(), 1, "{found:?}");
        assert!(found[0].message.contains("$body$"), "{found:?}");
        // 已闭合的正文里的 `$$` / 括号都不参与判定（正文是不透明的）
        assert!(diagnose("select $body$ a $$ b ( c $body$").is_empty(), "{:?}", diagnose("select $body$ a $$ b ( c $body$"));
        assert!(diagnose("select $$ plain $$").is_empty());
    }

    #[test]
    fn a_positional_placeholder_is_not_a_dollar_quote() {
        assert!(diagnose("select $1, $2 from t").is_empty());
    }

    #[test]
    fn a_closed_dollar_quote_body_is_not_scanned_for_brackets() {
        // 正文里的 `(` 不算代码：已闭合的 dollar-quote 里不能报括号不配平
        assert!(diagnose("select $$ unbalanced ( $$").is_empty());
    }

    #[test]
    fn an_extra_closing_bracket_is_reported() {
        let sql = "select 1)";
        let found = diagnose(sql);
        assert_eq!(found.len(), 1, "{found:?}");
        assert_eq!(found[0].start, 8);
        assert!(found[0].message.contains("多余的右括号"), "{found:?}");
    }

    #[test]
    fn an_unclosed_bracket_is_reported_at_the_opening() {
        let sql = "select count(id from t";
        let found = diagnose(sql);
        assert_eq!(found.len(), 1, "{found:?}");
        assert_eq!(slice(sql, &found[0]), "(");
        assert!(found[0].message.contains("没闭合"), "{found:?}");
    }

    #[test]
    fn mismatched_bracket_kinds_are_reported() {
        let found = diagnose("select (1]");
        assert_eq!(found.len(), 1, "{found:?}");
        assert!(found[0].message.contains("配对不一致"), "{found:?}");
    }

    #[test]
    fn brackets_inside_strings_and_comments_are_ignored() {
        assert!(diagnose("select ')' from t -- 这里有个 ( 不算").is_empty());
        assert!(diagnose("select 1 /* ( */").is_empty());
    }

    #[test]
    fn a_chinese_comment_before_the_problem_does_not_shift_the_mark() {
        // 偏移是**字符下标**：中文注释在问题之前时，用它切原文必须正好切到那个多余右括号
        let sql = "-- 中文注释：查一下\nselect 1)";
        let found = diagnose(sql);
        assert_eq!(found.len(), 1, "{found:?}");
        assert_eq!(slice(sql, &found[0]), ")");
    }

    #[test]
    fn every_problem_is_listed_not_just_the_first() {
        // 两处互不相干的问题：多余右括号 + 块注释没闭合
        let sql = "select 1)\n/* open";
        let found = diagnose(sql);
        let list = messages(&found);
        assert!(list.iter().any(|m| m.contains("多余的右括号")), "{list:?}");
        assert!(list.iter().any(|m| m.contains("块注释没闭合")), "{list:?}");
        // 乱序给出也要按位置排好（界面从上往下列问题）
        let mut sorted = found.clone();
        sorted.sort_by_key(|d| d.start);
        assert_eq!(found, sorted);
    }
}
