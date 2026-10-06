//! SQL 编辑面需要的纯逻辑：**带位置的切分 / EXPLAIN 生成 / 高亮分词**（1.2 段）
//!
//! 与 `config::split_statements` 的分工（别重写第二份解析）：
//! - 那边是**执行用**的切分：丢注释、只还语句文本 —— 启动 SQL 下发用它；
//! - 这边是**编辑面用**的切分：**保留注释、带位置**（高亮要按字符区间上色、报错要能指到行列），
//!   并且额外做两件编辑面专有的事：① 判定"这段输入能不能加 `EXPLAIN`"（多段不能）；
//!   ② 高亮分词。
//! 两边的"分号切分"规则必须一致（字符串 / 引号标识符 / 注释里不分号），故这边**逐字符状态机**
//! 与那边同一套状态集，并由用例把两边的**语句条数**对起来（口径漂移会被判红）。
//!
//! 三条口径：
//! ① 位置是**字节偏移**（Rust 的 `&str` 下标即字节），前端按同一份原文切片即可；
//! ② 高亮只做**词法**（关键字 / 字符串 / 注释 / 数字 / 标点）—— 不做语法分析、不猜语义，
//!    这样它永远快、永远不失败（识别不了的按普通标识符上色）；
//! ③ `EXPLAIN` 只对**单条**语句生成：多段输入让用户自己选一段，**不替他挑**。

use serde::{Deserialize, Serialize};

/// 一段语句在原文里的位置（高亮与报错都要能指回去）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StatementSpan {
    /// 语句文本（**已 trim**；但 `start` / `end` 指向原文里那段未 trim 的区间）
    pub text: String,
    /// 原文里的起始字节偏移（含前导空白）
    pub start: usize,
    /// 原文里的结束字节偏移（不含分号）
    pub end: usize,
    /// 1 基行号（按 `\n` 数，供界面显示"第几段"）
    pub line: usize,
}

/// 按分号切分**并保留注释**，返回每段的文本与位置。
///
/// 与 `config::split_statements` 的关系：同一套状态机（单引号里的 `''` 转义、双引号标识符、
/// `--` 行注释、`/* */` 块注释里都不当分号）；差别只有两点 —— **注释不被丢掉**（要上色），
/// 以及**带位置**。空段（只有空白 / 只有注释）不算语句，但仍会出现在分词结果里。
pub fn spans(sql: &str) -> Vec<StatementSpan> {
    let mut out = Vec::new();
    let bytes = sql.as_bytes();
    let mut start = 0usize;
    let mut i = 0usize;
    let mut in_single = false;
    let mut in_double = false;
    let mut in_line_comment = false;
    let mut in_block_comment = false;
    // 段的**第一处真代码**位置（注释不算内容）：段首注释要留在原文里给高亮用，
    // 但不能算进这条语句的文本 —— 否则 `select 1; -- 说明\nselect 2` 会把注释和下一句并成一段
    // （第一次写的实现就是这么错的：行注释被当成了"内容"）。
    let mut code_start: Option<usize> = None;
    // 正在读的字面量起点（进入单/双引号时记下 —— 字面量本身也算"第一处真代码"）
    let mut start_of_literal = 0usize;
    // 行首表：第 n 个元素 = 第 n 行的起始字节偏移（1 基行号由二分得到）。
    // 为什么预扫一遍：行号要**按段起点**精确给，而扫描中途的 `line` 只在换行处推进，
    // 遇到"段起点在注释之后"这类情况就容易错位；预扫一次再二分是精确的，也不受状态影响。
    let mut line_starts: Vec<usize> = vec![0];
    for (idx, b) in bytes.iter().enumerate() {
        if *b == b'\n' {
            line_starts.push(idx + 1);
        }
    }

    while i < bytes.len() {
        let c = bytes[i] as char;
        if in_line_comment {
            if c == '\n' {
                in_line_comment = false;
            }
            i += 1;
            continue;
        }
        if in_block_comment {
            if c == '*' && i + 1 < bytes.len() && bytes[i + 1] == b'/' {
                in_block_comment = false;
                i += 2;
                continue;
            }
            i += 1;
            continue;
        }
        if in_single {
            if code_start.is_none() {
                code_start = Some(start_of_literal);
            }
            if c == '\'' {
                // 连写两个单引号 = 转义，不算结束
                if i + 1 < bytes.len() && bytes[i + 1] == b'\'' {
                    i += 2;
                    continue;
                }
                in_single = false;
            }
            i += 1;
            continue;
        }
        if in_double {
            if code_start.is_none() {
                code_start = Some(start_of_literal);
            }
            if c == '"' {
                in_double = false;
            }
            i += 1;
            continue;
        }
        match c {
            '\'' => {
                in_single = true;
                start_of_literal = i;
                if code_start.is_none() {
                    code_start = Some(i);
                }
                i += 1;
            }
            '"' => {
                in_double = true;
                start_of_literal = i;
                if code_start.is_none() {
                    code_start = Some(i);
                }
                i += 1;
            }
            '-' if i + 1 < bytes.len() && bytes[i + 1] == b'-' => {
                in_line_comment = true;
                i += 2;
            }
            '/' if i + 1 < bytes.len() && bytes[i + 1] == b'*' => {
                in_block_comment = true;
                i += 2;
            }
            ';' => {
                if let Some(begin) = code_start {
                    push_span(&mut out, sql, begin, i, line_of(&line_starts, begin));
                }
                i += 1;
                start = i;
                code_start = None;
            }
            '\n' => {
                i += 1;
            }
            other => {
                if !other.is_whitespace() && code_start.is_none() {
                    code_start = Some(i);
                }
                i += 1;
            }
        }
    }
    if let Some(begin) = code_start {
        push_span(&mut out, sql, begin, bytes.len(), line_of(&line_starts, begin));
    }
    // `start` 只用于把原文区间交给高亮之外的地方；这里显式吞掉未用告警
    let _ = start;
    out
}

/// 推入一段：位置指向**第一处真代码**到分号（或结尾），文本按该区间取。
fn push_span(out: &mut Vec<StatementSpan>, sql: &str, begin: usize, end: usize, line: usize) {
    let raw = &sql[begin..end];
    let text = raw.trim();
    if text.is_empty() {
        return;
    }
    let lead = raw.len() - raw.trim_start().len();
    let tail = raw.len() - raw.trim_end().len();
    out.push(StatementSpan {
        text: text.to_string(),
        start: begin + lead,
        end: begin + raw.len() - tail,
        line,
    });
}

/// 按行首表求某个字节偏移所在的行号（1 基）。
fn line_of(line_starts: &[usize], offset: usize) -> usize {
    match line_starts.binary_search(&offset) {
        Ok(idx) => idx + 1,
        // 落在两行首之间 ⇒ 属于前一行
        Err(idx) => idx,
    }
}

pub fn explain(sql: &str, analyze: bool) -> Result<String, String> {
    let parts = spans(sql);
    if parts.is_empty() {
        return Err("没有可解释的语句：输入是空的（或只有注释）。".to_string());
    }
    if parts.len() > 1 {
        return Err(format!(
            "输入里有 {} 条语句：EXPLAIN 一次只解释一条。选中要解释的那条，或把其它的删掉。",
            parts.len()
        ));
    }
    let body = parts[0].text.trim_end().trim_end_matches(';').trim();
    if body.is_empty() {
        return Err("没有可解释的语句。".to_string());
    }
    Ok(if analyze {
        format!("EXPLAIN (ANALYZE, BUFFERS) {body}")
    } else {
        format!("EXPLAIN {body}")
    })
}

/// 高亮用的词法单元。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TokenKind {
    Keyword,
    String,
    Number,
    LineComment,
    BlockComment,
    QuotedIdent,
    Punctuation,
    Ident,
}

/// 一个词法单元：种类 + 原文区间。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Token {
    pub kind: TokenKind,
    pub start: usize,
    pub end: usize,
}

/// SQL 关键字（够用就行的常用集；**不追求完备** —— 认不出的按标识符上色，不会错、只是不上色）。
pub const KEYWORDS: &[&str] = &[
    "select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create",
    "alter", "drop", "table", "view", "index", "sequence", "schema", "database", "join", "left",
    "right", "inner", "outer", "full", "cross", "on", "using", "group", "by", "order", "having",
    "limit", "offset", "union", "all", "distinct", "as", "and", "or", "not", "null", "is", "in",
    "exists", "between", "like", "ilike", "case", "when", "then", "else", "end", "cast", "asc",
    "desc", "primary", "key", "foreign", "references", "unique", "check", "default", "constraint",
    "begin", "commit", "rollback", "savepoint", "explain", "analyze", "vacuum", "truncate",
    "returning", "with", "recursive", "if", "replace", "temporary", "temp", "grant", "revoke",
    "show", "true", "false", "coalesce", "count", "sum", "avg", "min", "max", "now", "interval",
];

/// 关键字判定（大小写不敏感）。
pub fn is_keyword(word: &str) -> bool {
    let lower = word.to_ascii_lowercase();
    KEYWORDS.contains(&lower.as_str())
}

/// 高亮分词：**只做词法**，从左到右扫一遍，覆盖整段文本（每个字符必属于某个单元）。
///
/// 不变量（用例守）：① 单元按 `start` 升序且**首尾相接、无缝无叠**；
/// ② 第一个单元从 0 开始、最后一个到 `sql.len()` 结束；③ 空输入给空表。
pub fn tokenize(sql: &str) -> Vec<Token> {
    let bytes = sql.as_bytes();
    let mut out: Vec<Token> = Vec::new();
    let mut i = 0usize;
    while i < bytes.len() {
        let c = bytes[i] as char;
        let start = i;
        // 行注释
        if c == '-' && i + 1 < bytes.len() && bytes[i + 1] == b'-' {
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
            out.push(Token { kind: TokenKind::LineComment, start, end: i });
            continue;
        }
        // 块注释（未闭合也吃到结尾 —— 半截注释照样上色，不报错）
        if c == '/' && i + 1 < bytes.len() && bytes[i + 1] == b'*' {
            i += 2;
            while i < bytes.len() {
                if bytes[i] == b'*' && i + 1 < bytes.len() && bytes[i + 1] == b'/' {
                    i += 2;
                    break;
                }
                i += 1;
            }
            out.push(Token { kind: TokenKind::BlockComment, start, end: i });
            continue;
        }
        // 单引号字符串（含 `''` 转义）
        if c == '\'' {
            i += 1;
            while i < bytes.len() {
                if bytes[i] == b'\'' {
                    if i + 1 < bytes.len() && bytes[i + 1] == b'\'' {
                        i += 2;
                        continue;
                    }
                    i += 1;
                    break;
                }
                i += 1;
            }
            out.push(Token { kind: TokenKind::String, start, end: i });
            continue;
        }
        // 双引号标识符（含 `""` 转义）
        if c == '"' {
            i += 1;
            while i < bytes.len() {
                if bytes[i] == b'"' {
                    if i + 1 < bytes.len() && bytes[i + 1] == b'"' {
                        i += 2;
                        continue;
                    }
                    i += 1;
                    break;
                }
                i += 1;
            }
            out.push(Token { kind: TokenKind::QuotedIdent, start, end: i });
            continue;
        }
        // 数字（含小数点）
        if c.is_ascii_digit() {
            while i < bytes.len() && (bytes[i].is_ascii_digit() || bytes[i] == b'.') {
                i += 1;
            }
            out.push(Token { kind: TokenKind::Number, start, end: i });
            continue;
        }
        // 标识符 / 关键字（下划线、字母、数字；不加 Unicode —— SQL 标识符本就不许非 ASCII 直接写）
        if c.is_ascii_alphabetic() || c == '_' {
            while i < bytes.len()
                && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_' || bytes[i] == b'$')
            {
                i += 1;
            }
            let word = &sql[start..i];
            let kind = if is_keyword(word) { TokenKind::Keyword } else { TokenKind::Ident };
            out.push(Token { kind, start, end: i });
            continue;
        }
        // 标点：单个字符一个单元（空白也在内 —— 保证"每个字符都属于某个单元"）
        i += 1;
        out.push(Token { kind: TokenKind::Punctuation, start, end: i });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 按位置把原文那一段取回来（用法例统一口径：**终点永远是 `end` 字段**）。
    fn slice_of<'a>(sql: &'a str, span: &StatementSpan) -> &'a str {
        &sql[span.start..span.end]
    }

    #[test]
    fn spans_treat_a_statement_trailing_line_comment_as_part_of_the_previous_segment() {
        // 回归：`-- 说明` 在分号之后、换行之前 —— 它是**上一段的尾巴**，不是下一段的开头。
        // 第一版实现把行注释当成"段的内容"，于是注释和下一句被并成一段（用例判红）。
        let sql = "select 1; -- 说明\nselect 2";
        let parts = spans(sql);
        assert_eq!(parts.len(), 2, "{parts:?}");
        assert_eq!(parts[0].text, "select 1");
        assert_eq!(parts[1].text, "select 2");
        assert_eq!(parts[1].line, 2);
    }

    #[test]
    fn spans_report_the_line_of_the_segment_start() {
        let sql = "select 1;\n\n-- 注释在前\nselect 2;\nselect 3";
        let parts = spans(sql);
        assert_eq!(parts.len(), 3, "{parts:?}");
        assert_eq!(parts[0].line, 1);
        // 第二段从第 4 行的 `select` 开始（注释不算段的起点内容）
        assert_eq!(parts[1].line, 4);
        assert_eq!(parts[2].line, 5);
    }

    #[test]
    fn spans_keep_comments_and_positions() {
        let sql = "select 1; -- 说明\nselect 2";
        let parts = spans(sql);
        assert_eq!(parts.len(), 2);
        assert_eq!(parts[0].text, "select 1");
        assert_eq!(slice_of(sql, &parts[0]), "select 1");
        assert_eq!(parts[1].text, "select 2");
        // 位置切片必须**逐字等于** text（前端的报错指位就靠这个）
        //
        // ⚠️ 别用 `start + text.len()` 当终点：`text` 是 trim 过的，第二段前面那个换行不在
        // `text` 里 —— 第一次就是这么算的，长度对不上、断言当场红。终点是 `end` 字段。
        assert_eq!(slice_of(sql, &parts[1]), "select 2");
        assert_eq!(parts[1].line, 2);
    }

    #[test]
    fn spans_never_cut_inside_literals_or_quoted_identifiers() {
        let parts = spans("insert into t values ('a;b'); select \"c;d\" from t");
        assert_eq!(parts.len(), 2, "{parts:?}");
        assert!(parts[0].text.contains("'a;b'"));
        assert!(parts[1].text.contains("\"c;d\""));
    }

    #[test]
    fn spans_ignore_comment_only_segments() {
        // 只有注释的那一段不算可执行语句（否则"执行全部"会多报一条失败）
        let parts = spans("-- 只有注释\n;select 1;/* 块注释 */;");
        assert_eq!(parts.len(), 1, "{parts:?}");
        assert_eq!(parts[0].text, "select 1");
    }

    #[test]
    fn spans_of_empty_or_blank_input_are_empty() {
        assert!(spans("").is_empty());
        assert!(spans("   \n\t ").is_empty());
        assert!(spans(";;;").is_empty());
    }

    #[test]
    fn span_count_matches_the_execution_splitter() {
        // 口径不许漂移：编辑面的段数必须与「执行用切分」的条数一致（注释段的处理除外）
        for sql in [
            "select 1; select 2",
            "insert into t values ('a;b'); select 2",
            "SET a = 1; SET b = 2;",
            "select \"x;y\" from t; select 2",
            "select 'it''s; fine'; select 3",
        ] {
            let mine = spans(sql).len();
            let exec = crate::config::split_statements(sql).len();
            assert_eq!(mine, exec, "段数不一致：{sql}");
        }
    }

    #[test]
    fn explain_refuses_multi_statement_instead_of_picking_one() {
        let err = explain("select 1; select 2", false).unwrap_err();
        assert!(err.contains("2 条"), "{err}");
        assert!(err.contains("EXPLAIN"), "{err}");
    }

    #[test]
    fn explain_wraps_a_single_statement_and_drops_the_semicolon() {
        assert_eq!(explain("select 1;", false).unwrap(), "EXPLAIN select 1");
        assert_eq!(
            explain("  select * from app.accounts  ", false).unwrap(),
            "EXPLAIN select * from app.accounts"
        );
        assert_eq!(
            explain("select 1", true).unwrap(),
            "EXPLAIN (ANALYZE, BUFFERS) select 1"
        );
    }

    #[test]
    fn explain_rejects_empty_and_comment_only_input() {
        assert!(explain("   ", false).is_err());
        assert!(explain("-- 只有注释", false).is_err());
    }

    #[test]
    fn explain_keeps_comments_inside_the_statement_body() {
        // 语句体里的注释要留着（用户可能靠它标注），只去掉结尾的分号
        let out = explain("select /* 谁 */ 1;", false).unwrap();
        assert!(out.contains("/* 谁 */"), "{out}");
        assert!(!out.ends_with(';'));
    }

    #[test]
    fn tokenize_covers_every_character_without_gaps_or_overlaps() {
        let sql = "select id, 'a;b' /* c */ -- d\nfrom app.accounts where n > 1.5 and x = \"Q\"";
        let tokens = tokenize(sql);
        assert!(!tokens.is_empty());
        assert_eq!(tokens[0].start, 0);
        assert_eq!(tokens.last().unwrap().end, sql.len());
        for pair in tokens.windows(2) {
            assert_eq!(pair[0].end, pair[1].start, "单元之间不许有缝或重叠：{pair:?}");
        }
        // 拼接回来必须**逐字节等于原文**（高亮不许丢字符）
        let rebuilt: String = tokens.iter().map(|t| &sql[t.start..t.end]).collect();
        assert_eq!(rebuilt, sql);
    }

    #[test]
    fn tokenize_classifies_keywords_strings_comments_numbers() {
        let sql = "SELECT 'x' -- c\nFROM t WHERE n = 12";
        let kinds: Vec<TokenKind> = tokenize(sql)
            .into_iter()
            .filter(|t| t.kind != TokenKind::Punctuation)
            .map(|t| t.kind)
            .collect();
        assert_eq!(kinds[0], TokenKind::Keyword); // SELECT
        assert!(kinds.contains(&TokenKind::String));
        assert!(kinds.contains(&TokenKind::LineComment));
        assert!(kinds.contains(&TokenKind::Number));
        assert!(kinds.contains(&TokenKind::Ident));
        // 关键字大小写不敏感
        assert!(is_keyword("select") && is_keyword("SELECT") && is_keyword("SeLeCt"));
        assert!(!is_keyword("selectx"));
    }

    #[test]
    fn tokenize_treats_literal_contents_as_literal() {
        let sql = "select 'select -- not a comment'";
        let tokens = tokenize(sql);
        let strings: Vec<&Token> = tokens.iter().filter(|t| t.kind == TokenKind::String).collect();
        assert_eq!(strings.len(), 1);
        let text = &sql[strings[0].start..strings[0].end];
        assert!(text.contains("-- not a comment"), "{text}");
        // 字符串里不许出现"关键字"单元
        assert!(!tokens.iter().any(|t| {
            t.kind == TokenKind::Keyword && sql[t.start..t.end].eq_ignore_ascii_case("not")
        }));
    }

    #[test]
    fn tokenize_handles_unterminated_literals_and_comments_without_failing() {
        // 半截输入是编辑面的常态：不许 panic、不许漏字符
        for sql in ["select 'abc", "select /* abc", "select \"abc"] {
            let tokens = tokenize(sql);
            let rebuilt: String = tokens.iter().map(|t| &sql[t.start..t.end]).collect();
            assert_eq!(rebuilt, sql, "{sql}");
        }
    }

    #[test]
    fn tokenize_of_empty_input_is_empty() {
        assert!(tokenize("").is_empty());
    }
}
