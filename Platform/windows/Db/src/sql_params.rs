//! **查询参数**（`FR-EXEC-17`）：SQL 里的 `:name` / `$1` 占位符的**扫描**与**类型化绑定**。
//!
//! ## 为什么要它
//! 手工拼串是注入的唯一来路（`'... where name = ''' || v || ''' ...'`）。占位符 + 绑定把「值」
//! 与「语句」分开：值**永远**只作为字面量的一部分写进语句，没有「原样插入」的通道。
//!
//! ## 三条口径
//! 1. **词法复用 `sql::tokenize`** —— 高亮、分号切分、参数扫描用同一套；再写一份词法，
//!    三处迟早对同一条 SQL 给出不同答案（字符串里的 `:name` 被一处认、另一处不认）。
//! 2. **类型由用户选**（文本 / 数字 / 布尔 / NULL），**默认文本**。不猜：`WHERE name = :name`
//!    填 `2` 猜成数字会得到 `text = integer`，整条语句失败；猜成文本则永远成立。
//! 3. **文本一律加单引号、内部单引号双写**（`standard_conforming_strings = on` 下反斜杠是字面量，
//!    不再额外转义 —— PostgreSQL 默认即如此）。数字先**校验**再不加引号书写。
//!
//! ## 界面这边的配套（本模块不做的事）
//! - 绑定结果**只用于本次执行**：编辑器里那行占位符原样留着（它是可复用的模板，
//!   被一次取值覆盖就找不回来了）—— 与对侧 `QueryParameterSheet` 同口径。
//! - 缺值 / 填错一次报全（不是抛出第一个就完）。

use serde::{Deserialize, Serialize};

use crate::sql::{tokenize, TokenKind};

/// 一个参数站点（去重后的声明，供填值面板列出来）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParamSite {
    /// 界面上的样子：`:name` 或 `$1`（位置参数按 `$n` 原样显示 —— 不替它改名）
    pub name: String,
    /// 在 SQL 里出现几次（界面显示「×2」，用户能判断是不是同一个意思）
    pub occurrences: usize,
    /// 是不是位置参数（`$1`）；命名参数为 `false`
    pub positional: bool,
}

/// 扫描结果。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScanOutcome {
    pub sites: Vec<ParamSite>,
    /// 有没有占位符（界面据此决定「弹不弹填值面板」—— 没参数就别打断日常执行）
    pub has_parameters: bool,
}

/// 参数值的书写类型（**用户选**，不猜）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ParamKind {
    /// 文本：加单引号，内部单引号双写
    Text,
    /// 数字：先校验，**不加引号**书写（加了会让索引失效、还会把比较变成字符串比较）
    Number,
    /// 布尔：写 `TRUE` / `FALSE`
    Boolean,
    /// NULL：值被忽略，写 `NULL`（空串与 NULL 是两件事，界面上不许混）
    Null,
}

impl ParamKind {
    /// 界面上的默认值：**文本**（最不会出错的那个）。
    pub fn default_kind() -> Self {
        ParamKind::Text
    }
}

/// 用户填的一个参数值。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParamValue {
    pub name: String,
    pub value: String,
    pub kind: ParamKind,
}

/// 绑定结果里的一个参数（回执要能说清「每个参数变成了什么」）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoundParam {
    pub name: String,
    pub occurrences: usize,
    pub kind: ParamKind,
    /// 实际写进语句的那段文本（`'abc'` / `42` / `TRUE` / `NULL`）
    pub literal: String,
}

/// 绑定结果。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BindOutcome {
    /// 绑定后的语句（**只用于本次执行**，不回写编辑器）
    pub sql: String,
    pub params: Vec<BoundParam>,
    /// 给了值、但 SQL 里没有这个参数的名字（多半是拼错 —— 如实提示，不静默丢）
    pub unused: Vec<String>,
}

/// 绑定失败的两类（**缺值一次报全**，不抛第一个就走）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BindError {
    /// 这些参数没有给值
    Missing(Vec<String>),
    /// 某个值的书写格式不对（数字 / 布尔）
    BadValue { name: String, reason: String },
}

impl std::fmt::Display for BindError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BindError::Missing(names) => {
                write!(f, "这些参数还没有填值：{}", names.join("、"))
            }
            BindError::BadValue { name, reason } => write!(f, "参数 {name} 的值不能用：{reason}"),
        }
    }
}

impl std::error::Error for BindError {}

/// 扫描 SQL 里的占位符（去重、按首次出现排序）。
pub fn scan(sql: &str) -> ScanOutcome {
    let sites = sites(sql);
    let mut merged: Vec<ParamSite> = Vec::new();
    for site in sites {
        match merged.iter_mut().find(|existing| existing.name == site.name) {
            Some(existing) => existing.occurrences += 1,
            None => merged.push(ParamSite {
                name: site.name,
                occurrences: 1,
                positional: site.positional,
            }),
        }
    }
    ScanOutcome {
        has_parameters: !merged.is_empty(),
        sites: merged,
    }
}

/// 绑定：把每个占位符换成**字面量**（值永远被当数据）。
pub fn bind(sql: &str, values: &[ParamValue]) -> Result<BindOutcome, BindError> {
    let sites = sites(sql);
    if sites.is_empty() {
        return Ok(BindOutcome {
            sql: sql.to_string(),
            params: Vec::new(),
            unused: values.iter().map(|v| v.name.clone()).collect(),
        });
    }

    // ① 先查缺值（**一次报全**）：同名的多个站点只算一次缺
    let mut missing: Vec<String> = Vec::new();
    for site in &sites {
        if missing.contains(&site.name) {
            continue;
        }
        if !values.iter().any(|value| value.name == site.name) {
            missing.push(site.name.clone());
        }
    }
    if !missing.is_empty() {
        return Err(BindError::Missing(missing));
    }

    // ② 再逐个渲染字面量（数字 / 布尔先校验 —— 填错就在执行前拦下，不让服务端替我们报语法错）
    let mut literals: Vec<(String, ParamKind, String)> = Vec::new();
    for site in &sites {
        if literals.iter().any(|(name, _, _)| name == &site.name) {
            continue;
        }
        let value = values
            .iter()
            .find(|value| value.name == site.name)
            .expect("缺值已在上面拦掉");
        let literal = render(value).map_err(|reason| BindError::BadValue {
            name: site.name.clone(),
            reason,
        })?;
        literals.push((site.name.clone(), value.kind, literal));
    }

    // ③ 重建语句：只替换占位符那些字节区间，其余**逐字节原样**（注释 / 空白 / 大小写都不动）
    let mut out = String::with_capacity(sql.len());
    let mut cursor = 0usize;
    for site in &sites {
        let (_, kind, literal) = literals
            .iter()
            .find(|(name, _, _)| name == &site.name)
            .expect("每个站点都有字面量");
        out.push_str(&sql[cursor..site.start]);
        out.push_str(literal);
        cursor = site.end;
        let _ = kind;
    }
    out.push_str(&sql[cursor..]);

    let mut params: Vec<BoundParam> = Vec::new();
    for (name, kind, literal) in literals {
        let occurrences = sites.iter().filter(|site| site.name == name).count();
        params.push(BoundParam {
            name,
            occurrences,
            kind,
            literal,
        });
    }
    let unused = values
        .iter()
        .filter(|value| !sites.iter().any(|site| site.name == value.name))
        .map(|value| value.name.clone())
        .collect();

    Ok(BindOutcome {
        sql: out,
        params,
        unused,
    })
}

/// 一个**带位置**的站点（内部用；对外只给去重后的 `ParamSite`）。
#[derive(Debug, Clone)]
struct Site {
    name: String,
    /// 占位符在原文里的起始字节（`:` 或 `$` 本身）
    start: usize,
    /// 结束字节（不含）
    end: usize,
    positional: bool,
}

/// 扫一遍占位符（**带位置**）。字符串 / 引号标识符 / 注释 / dollar-quote 体里的一律不算。
fn sites(sql: &str) -> Vec<Site> {
    let tokens = tokenize(sql);
    let bytes = sql.as_bytes();
    let mut out: Vec<Site> = Vec::new();
    let mut index = 0usize;
    while index < tokens.len() {
        let token = &tokens[index];
        match token.kind {
            // 只从**标点**里认占位符。字符串 / 引号标识符 / 注释各自是**一个整 token**
            // （`'...'` 不会被拆开），所以它们的**内容**根本走不到这里 —— 这一条性质由词法保证，
            // 不靠本函数再判一次（写一行「跳过 String」在这里是装饰：它永远不会命中）。
            TokenKind::Punctuation => {
                let ch = &sql[token.start..token.end];
                if ch == "$" {
                    // dollar-quote（`$$…$$` / `$tag$…$tag$`）整体跳过：体里可以有任意字符
                    if let Some(next) = skip_dollar_quote(sql, &tokens, index) {
                        index = next;
                        continue;
                    }
                    // 位置参数 `$n`：`$` 紧跟一个纯数字
                    if let Some(next) = tokens.get(index + 1) {
                        if next.start == token.end && next.kind == TokenKind::Number {
                            let digits = &sql[next.start..next.end];
                            if !digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit()) {
                                out.push(Site {
                                    name: format!("${digits}"),
                                    start: token.start,
                                    end: next.end,
                                    positional: true,
                                });
                                index += 2;
                                continue;
                            }
                        }
                    }
                    index += 1;
                } else if ch == ":" {
                    // `::` 是类型转换，不是参数（前一个非空白字符是 `:` 就让开）
                    let prev_is_colon = previous_non_space(bytes, token.start) == Some(b':');
                    if prev_is_colon {
                        index += 1;
                        continue;
                    }
                    if let Some(next) = tokens.get(index + 1) {
                        // 名字必须**紧贴**在冒号后面，且是标识符（关键字也认：`:limit` 这种名字合法）
                        let is_word =
                            matches!(next.kind, TokenKind::Ident | TokenKind::Keyword);
                        if is_word && next.start == token.end {
                            out.push(Site {
                                name: format!(":{}", &sql[next.start..next.end]),
                                start: token.start,
                                end: next.end,
                                positional: false,
                            });
                            index += 2;
                            continue;
                        }
                    }
                    index += 1;
                } else {
                    index += 1;
                }
            }
            _ => index += 1,
        }
    }
    out
}

/// 如果 `$` 开了一个 dollar-quote，返回**它结束之后**的第一个 token 下标。
fn skip_dollar_quote(sql: &str, tokens: &[crate::sql::Token], index: usize) -> Option<usize> {
    let start = tokens[index].start;
    let bytes = sql.as_bytes();
    if start >= bytes.len() || bytes[start] != b'$' {
        return None;
    }
    // 标签：`$$`（空）或 `$tag$`（tag = 字母 / 下划线开头，后可跟字母数字下划线）
    let mut cursor = start + 1;
    while cursor < bytes.len() && (bytes[cursor].is_ascii_alphanumeric() || bytes[cursor] == b'_') {
        cursor += 1;
    }
    // 标签不许以数字开头（`$1` 是位置参数，不是 dollar-quote）
    if cursor == start + 1 {
        // 空标签：必须是紧挨着的 `$$`
        if cursor < bytes.len() && bytes[cursor] == b'$' {
            let open_end = cursor + 1;
            return close_of(sql, tokens, open_end, "$$");
        }
        return None;
    }
    if !bytes[start + 1].is_ascii_alphabetic() && bytes[start + 1] != b'_' {
        return None;
    }
    if cursor < bytes.len() && bytes[cursor] == b'$' {
        let open_end = cursor + 1;
        let tag = &sql[start..open_end];
        return close_of(sql, tokens, open_end, tag);
    }
    None
}

/// 找 `tag` 作为结束标记的位置，返回其后第一个 token 的下标。
fn close_of(sql: &str, tokens: &[crate::sql::Token], from: usize, tag: &str) -> Option<usize> {
    let close = sql[from..].find(tag)? + from + tag.len();
    // 结束标记之后的第一个 token（中间的 token 全在 dollar-quote 体里，跳过）
    let next = tokens
        .iter()
        .position(|token| token.start >= close)
        .unwrap_or(tokens.len());
    Some(next)
}

/// 某个字节位置之前**第一个非空白字节**（`::` 的判定用）。
fn previous_non_space(bytes: &[u8], at: usize) -> Option<u8> {
    let mut cursor = at;
    while cursor > 0 {
        cursor -= 1;
        let byte = bytes[cursor];
        if !byte.is_ascii_whitespace() {
            return Some(byte);
        }
    }
    None
}

/// 把一个值写成一个**字面量**（这里是全模块唯一产出 SQL 文本的地方）。
fn render(value: &ParamValue) -> Result<String, String> {
    match value.kind {
        ParamKind::Text => Ok(format!("'{}'", value.value.replace('\'', "''"))),
        ParamKind::Number => {
            let text = value.value.trim();
            if !is_number(text) {
                return Err(format!(
                    "「{}」不是数字（只认 123 / -4.5 / 1e3 这种写法）",
                    value.value
                ));
            }
            Ok(text.to_string())
        }
        ParamKind::Boolean => {
            let text = value.value.trim().to_ascii_lowercase();
            match text.as_str() {
                "true" => Ok("TRUE".to_string()),
                "false" => Ok("FALSE".to_string()),
                _ => Err(format!(
                    "「{}」不是布尔值（只认 true / false）",
                    value.value
                )),
            }
        }
        ParamKind::Null => Ok("NULL".to_string()),
    }
}

/// 严格的数字字面量判定（**不认** `NaN` / `inf` / 十六进制 —— 那些要用户写文本）。
fn is_number(text: &str) -> bool {
    if text.is_empty() {
        return false;
    }
    let mut chars = text.chars().peekable();
    if matches!(chars.peek(), Some('+') | Some('-')) {
        chars.next();
    }
    let mut digits = 0usize;
    let mut dots = 0usize;
    while let Some(ch) = chars.next() {
        if ch.is_ascii_digit() {
            digits += 1;
        } else if ch == '.' {
            dots += 1;
            if dots > 1 {
                return false;
            }
        } else if ch == 'e' || ch == 'E' {
            // 指数部分：可选符号 + 至少一位数字
            let rest: String = chars.collect();
            if rest.is_empty() {
                return false;
            }
            let rest = rest.strip_prefix(['+', '-']).unwrap_or(&rest);
            return digits > 0 && !rest.is_empty() && rest.bytes().all(|b| b.is_ascii_digit());
        } else {
            return false;
        }
    }
    digits > 0
}

#[cfg(test)]
mod tests {
    use super::*;

    fn value(name: &str, text: &str, kind: ParamKind) -> ParamValue {
        ParamValue {
            name: name.to_string(),
            value: text.to_string(),
            kind,
        }
    }

    fn names(outcome: &ScanOutcome) -> Vec<String> {
        outcome.sites.iter().map(|site| site.name.clone()).collect()
    }

    #[test]
    fn scan_finds_named_and_positional_placeholders() {
        let outcome = scan("select * from t where a = :first and b = $1");
        assert_eq!(names(&outcome), vec![":first", "$1"]);
        assert!(outcome.has_parameters);
        assert!(outcome.sites[1].positional);
        assert!(!outcome.sites[0].positional);
    }

    #[test]
    fn scan_ignores_placeholders_inside_strings_and_comments() {
        // 这三处都是**内容**：字符串里、行注释里、块注释里
        let sql = "select ':notaparam' as a, /* :nope */ 1 -- :alsonope\nfrom t where x = :real";
        let outcome = scan(sql);
        assert_eq!(names(&outcome), vec![":real"]);
    }

    #[test]
    fn scan_does_not_treat_type_casts_as_parameters() {
        let outcome = scan("select cast(:v as integer)::text, x::numeric from t");
        assert_eq!(names(&outcome), vec![":v"]);
    }

    #[test]
    fn scan_skips_dollar_quoted_bodies() {
        // dollar-quote 里的 `:x` 与 `$1` 都不是参数；体外的 `:after` 才是
        let sql = "select $tag$ :x $1 $$ $tag$ as body, :after from t";
        let outcome = scan(sql);
        assert_eq!(names(&outcome), vec![":after"]);
    }

    #[test]
    fn scan_merges_repeats_and_counts_them() {
        let outcome = scan("select :n where a = :n or b = :n");
        assert_eq!(outcome.sites.len(), 1);
        assert_eq!(outcome.sites[0].occurrences, 3);
    }

    #[test]
    fn scan_of_sql_without_placeholders_says_so() {
        let outcome = scan("select 1");
        assert!(!outcome.has_parameters);
        assert!(outcome.sites.is_empty());
    }

    #[test]
    fn bind_writes_text_as_a_single_quoted_literal() {
        let out = bind(
            "select * from t where name = :name",
            &[value(":name", "张三", ParamKind::Text)],
        )
        .expect("应当能绑定");
        assert_eq!(out.sql, "select * from t where name = '张三'");
        assert_eq!(out.params[0].literal, "'张三'");
        assert_eq!(out.params[0].kind, ParamKind::Text);
    }

    #[test]
    fn bind_keeps_an_injection_attempt_as_data() {
        // 这条是 FR-EXEC-17 的验收面：值里的分号 / 引号 / DROP 全留在**一个字面量**里
        let hostile = "x'; DROP TABLE t; --";
        let out = bind(
            "select * from t where name = :name",
            &[value(":name", hostile, ParamKind::Text)],
        )
        .expect("应当能绑定");
        assert_eq!(
            out.sql,
            "select * from t where name = 'x''; DROP TABLE t; --'"
        );
        // 绑定后仍是**一条**语句：切分只有一段（`DROP` 在字面量里）
        assert_eq!(crate::config::split_statements(&out.sql).len(), 1);
    }

    #[test]
    fn bind_writes_numbers_and_booleans_without_quotes() {
        let out = bind(
            "select * from t where id = $1 and ok = :ok and v is not distinct from :n",
            &[
                value("$1", " 42 ", ParamKind::Number),
                value(":ok", "true", ParamKind::Boolean),
                value(":n", "", ParamKind::Null),
            ],
        )
        .expect("应当能绑定");
        assert_eq!(
            out.sql,
            "select * from t where id = 42 and ok = TRUE and v is not distinct from NULL"
        );
        assert_eq!(out.params.len(), 3);
    }

    #[test]
    fn bind_reports_all_missing_values_at_once() {
        let err = bind("select :a, :b, :c", &[value(":b", "1", ParamKind::Text)])
            .expect_err("缺值应当被拒");
        match err {
            BindError::Missing(missing) => assert_eq!(missing, vec![":a", ":c"]),
            other => panic!("应报缺值，实际 {other:?}"),
        }
    }

    #[test]
    fn bind_refuses_a_value_that_is_not_a_number() {
        let err = bind(
            "select :id",
            &[value(":id", "12abc", ParamKind::Number)],
        )
        .expect_err("非数字应当被拒");
        match err {
            BindError::BadValue { name, reason } => {
                assert_eq!(name, ":id");
                assert!(reason.contains("不是数字"), "{reason}");
            }
            other => panic!("应报值不合法，实际 {other:?}"),
        }
    }

    #[test]
    fn bind_leaves_placeholders_in_comments_untouched() {
        let out = bind(
            "select :real -- 说明：:notaparam 是例子\nfrom t",
            &[value(":real", "1", ParamKind::Text)],
        )
        .expect("应当能绑定");
        // 注释里的那个 `:notaparam` **逐字留着**（它本来就是说明文字）
        assert!(out.sql.contains("-- 说明：:notaparam 是例子"), "{}", out.sql);
        assert!(out.sql.starts_with("select '1' "), "{}", out.sql);
    }

    #[test]
    fn bind_reports_unused_values_as_a_typo_hint() {
        let out = bind("select :a", &[value(":a", "1", ParamKind::Text), value(":b", "2", ParamKind::Text)])
            .expect("多余值不算失败");
        assert_eq!(out.unused, vec![":b"]);
    }

    #[test]
    fn bind_of_sql_without_parameters_returns_it_unchanged() {
        let sql = "select 1 -- :x 只是说明";
        let out = bind(sql, &[]).expect("无参数不算失败");
        assert_eq!(out.sql, sql);
        assert!(out.params.is_empty());
        assert!(out.unused.is_empty());
    }

    #[test]
    fn number_check_accepts_only_plain_numbers() {
        for good in ["1", "-4.5", "+7", "1e3", "2.5E-2", "0"] {
            assert!(is_number(good), "{good} 应被认作数字");
        }
        for bad in ["", "1.2.3", "1e", "NaN", "inf", "0x10", "1,000", "1 2"] {
            assert!(!is_number(bad), "{bad} 不该被认作数字");
        }
    }
}
