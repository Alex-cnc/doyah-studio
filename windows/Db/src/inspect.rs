//! 单元格 / 单行的**值检查**（FR-DATA-05；契约等价物：macOS 侧 `Core/CellInspector.swift`）
//!
//! 为什么单独做一层：这三件事都有"看着对、其实错"的坑 ——
//! ① JSON 识别**太宽**会把 `123`、`{不是 JSON}` 也当 JSON（然后显示一句解析错误）；
//!    **太严**又会让 `[...]` 这种数组漏掉；
//! ② 截断如果不把**原始长度**一起说出来，用户会以为拿到的就是全部；
//! ③ NULL 与空串必须继续分开（与结果面同一条纪律）。
//!
//! 所以这里只做**纯计算**：判定形态、给出展示文本与元信息；界面只负责排版。

use serde::{Deserialize, Serialize};
use serde_json::Value as Json;

/// 默认展示上限。长 JSON 常见几千字符，超过就截断 —— 但**必须**同时告诉用户原始长度。
pub const DEFAULT_DISPLAY_LIMIT: usize = 4000;

/// 值的形态。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind")]
pub enum Shape {
    Null,
    Empty,
    JsonObject,
    JsonArray,
    /// 二进制（`bytea` 的十六进制文本形态：`\x48656c6c6f`）。
    Binary { byte_count: usize },
    /// 能解析的标量 JSON（数字 / 字符串 / true / false / null）。
    ScalarJson,
    Text,
}

/// 一个值的完整描述。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CellValue {
    pub shape: Shape,
    /// 展示用文本（JSON 已美化、二进制已摘要）。
    pub display: String,
    /// 原始文本长度（**字符数**：用户看到的是字符，不是字节）。
    pub original_character_count: usize,
    /// 原始文本的 UTF-8 字节数。
    pub original_byte_count: usize,
    /// 展示文本被截断了吗。
    pub is_truncated: bool,
    /// 原始文本的行数（1 起）。
    pub line_count: usize,
}

impl CellValue {
    /// 一句话摘要，供列表 / 状态栏用：`JSON 对象 · 42 字符 · 6 行`。
    ///
    /// **文案在这里**（本层是纯逻辑，但摘要要能直接用）—— 语言由调用方要哪种就给哪种，
    /// 不硬编码一种（与对侧 `summary(language:)` 同一考虑）。
    pub fn summary(&self, language: SummaryLanguage) -> String {
        let t = |zh: &'static str, en: &'static str| match language {
            SummaryLanguage::ZhHans => zh,
            SummaryLanguage::En => en,
        };
        let mut parts: Vec<String> = Vec::new();
        match self.shape {
            Shape::Null => parts.push("NULL".to_string()),
            Shape::Empty => parts.push(t("空串", "empty").to_string()),
            Shape::JsonObject => parts.push(t("JSON 对象", "JSON object").to_string()),
            Shape::JsonArray => parts.push(t("JSON 数组", "JSON array").to_string()),
            Shape::Binary { byte_count } => parts.push(match language {
                SummaryLanguage::ZhHans => format!("二进制 {byte_count} 字节"),
                SummaryLanguage::En => format!("binary {byte_count} bytes"),
            }),
            Shape::ScalarJson => parts.push(t("标量 JSON", "scalar JSON").to_string()),
            Shape::Text => parts.push(t("文本", "text").to_string()),
        }
        if !matches!(self.shape, Shape::Null | Shape::Empty) {
            parts.push(match language {
                SummaryLanguage::ZhHans => format!("{} 字符", self.original_character_count),
                SummaryLanguage::En => format!("{} chars", self.original_character_count),
            });
            if self.line_count > 1 {
                parts.push(match language {
                    SummaryLanguage::ZhHans => format!("{} 行", self.line_count),
                    SummaryLanguage::En => format!("{} lines", self.line_count),
                });
            }
        }
        if self.is_truncated {
            parts.push(t("已截断", "truncated").to_string());
        }
        parts.join(" · ")
    }
}

/// 摘要用哪种语言。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SummaryLanguage {
    ZhHans,
    En,
}

/// 竖排视图里的一行（列名 → 值）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Field {
    pub column_name: String,
    /// 列类型名（来自服务端；没有就给空串，**不编一个**）
    pub type_name: String,
    pub value: CellValue,
}

/// 单行详情：按**列顺序**给出每个字段（竖排看宽表）。
pub fn row(
    columns: &[(String, String)],
    row: &[Option<String>],
    display_limit: usize,
) -> Vec<Field> {
    columns
        .iter()
        .enumerate()
        .map(|(index, (name, type_name))| Field {
            column_name: name.clone(),
            type_name: type_name.clone(),
            value: inspect(row.get(index).cloned().flatten(), display_limit),
        })
        .collect()
}

/// 检查一个单元格值。
pub fn inspect(raw: Option<String>, display_limit: usize) -> CellValue {
    let Some(raw) = raw else {
        return CellValue {
            shape: Shape::Null,
            display: "NULL".to_string(),
            original_character_count: 0,
            original_byte_count: 0,
            is_truncated: false,
            line_count: 0,
        };
    };
    if raw.is_empty() {
        return CellValue {
            shape: Shape::Empty,
            display: String::new(),
            original_character_count: 0,
            original_byte_count: 0,
            is_truncated: false,
            line_count: 1,
        };
    }

    let characters = raw.chars().count();
    let bytes = raw.len();
    let lines = raw.lines().count().max(1);

    // 二进制：PostgreSQL 的 `bytea` 文本形态 = `\x` + 偶数个十六进制字符。
    if let Some(byte_count) = binary_byte_count(&raw) {
        let preview: String = raw.chars().take(32).collect();
        let truncated = characters > 32;
        let display = if truncated { format!("{preview}…") } else { preview };
        return CellValue {
            shape: Shape::Binary { byte_count },
            display,
            original_character_count: characters,
            original_byte_count: bytes,
            is_truncated: truncated,
            line_count: lines,
        };
    }

    // JSON：先看**首字符**再交给解析器 —— 不靠"包含花括号"这种宽判据
    if let Some(shape) = json_shape(&raw) {
        if let Some(pretty) = pretty_json(&raw) {
            let truncated = pretty.chars().count() > display_limit;
            let display = if truncated {
                format!("{}…", pretty.chars().take(display_limit).collect::<String>())
            } else {
                pretty
            };
            return CellValue {
                shape,
                display,
                original_character_count: characters,
                original_byte_count: bytes,
                is_truncated: truncated,
                line_count: lines,
            };
        }
    }

    // 普通文本：超长也截断，并如实标注
    let truncated = characters > display_limit;
    let display = if truncated {
        format!("{}…", raw.chars().take(display_limit).collect::<String>())
    } else {
        raw
    };
    CellValue {
        shape: Shape::Text,
        display,
        original_character_count: characters,
        original_byte_count: bytes,
        is_truncated: truncated,
        line_count: lines,
    }
}

/// `\x48656c6c6f` → 5 字节；不是这种形态返回 `None`。
pub fn binary_byte_count(text: &str) -> Option<usize> {
    let hex = text.strip_prefix("\\x")?;
    if hex.is_empty() || hex.len() % 2 != 0 || !hex.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    Some(hex.len() / 2)
}

/// JSON 形态判定：**只认「首字符像 JSON 且真能被解析」的值**。
///
/// 为什么不能只看首字符：`{不是 JSON}`、`[未闭合` 在真实数据里很常见（尤其是半截日志），
/// 把它们当 JSON 只会显示一句解析错误，还不如按文本原样显示。
pub fn json_shape(text: &str) -> Option<Shape> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return None;
    }
    let first = trimmed.chars().next()?;
    let looks_like = match first {
        '{' | '[' | '"' => true,
        't' | 'f' | 'n' => matches!(trimmed, "true" | "false" | "null"),
        c => c.is_ascii_digit() || c == '-',
    };
    if !looks_like {
        return None;
    }
    // **必须真能解析**才认（`123` 与 `"abc"` 这类标量也算：对侧 `.fragmentsAllowed` 同口径）。
    // 本侧的等价做法 = 把裸标量包一层数组再解 —— serde_json 默认不吃顶层标量。
    parse_json_lenient(trimmed)?;
    Some(match first {
        '{' => Shape::JsonObject,
        '[' => Shape::JsonArray,
        _ => Shape::ScalarJson,
    })
}

/// 宽松解析：顶层标量（数字 / 字符串 / true / false / null）也认。
///
/// 做法 = 先直接解；失败就把原文包成 `[原文]` 再解（这就是"允许片段"的等价实现）。
fn parse_json_lenient(trimmed: &str) -> Option<Json> {
    if let Ok(value) = serde_json::from_str::<Json>(trimmed) {
        return Some(value);
    }
    let wrapped = format!("[{trimmed}]");
    let mut array = serde_json::from_str::<Json>(&wrapped).ok()?;
    if let Json::Array(items) = &mut array {
        if items.len() == 1 {
            return items.pop();
        }
    }
    None
}

/// 美化 JSON。**键按字典序**（`serde_json` 的 `BTreeMap` 顺序天然如此）——
/// 与其让每次显示的顺序不稳定，不如固定成排序后的（对阅读也更友好）。
///
/// 标量原样返回（本来也没什么可"美化"的）；解析不出来就原样返回，**不编**。
pub fn pretty_json(text: &str) -> Option<String> {
    let trimmed = text.trim();
    match parse_json_lenient(trimmed)? {
        Json::Number(_) | Json::String(_) | Json::Bool(_) | Json::Null => Some(trimmed.to_string()),
        other => serde_json::to_string_pretty(&other).ok(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn inspect_raw(raw: &str) -> CellValue {
        inspect(Some(raw.to_string()), DEFAULT_DISPLAY_LIMIT)
    }

    #[test]
    fn null_and_empty_stay_distinct() {
        let null = inspect(None, DEFAULT_DISPLAY_LIMIT);
        assert_eq!(null.shape, Shape::Null);
        assert_eq!(null.display, "NULL");
        assert_eq!(null.summary(SummaryLanguage::ZhHans), "NULL");

        let empty = inspect(Some(String::new()), DEFAULT_DISPLAY_LIMIT);
        assert_eq!(empty.shape, Shape::Empty);
        assert_eq!(empty.display, "");
        assert_eq!(empty.line_count, 1);
        assert_eq!(empty.summary(SummaryLanguage::ZhHans), "空串");
        // 两者不是一回事
        assert_ne!(null.shape, empty.shape);
    }

    #[test]
    fn json_objects_and_arrays_are_pretty_printed_with_sorted_keys() {
        let v = inspect_raw(r#"{"b":1,"a":2}"#);
        assert_eq!(v.shape, Shape::JsonObject);
        // 键按字典序 ⇒ a 在 b 前
        let a = v.display.find("\"a\"").unwrap();
        let b = v.display.find("\"b\"").unwrap();
        assert!(a < b, "键应当按字典序：{}", v.display);
        assert!(v.display.contains('\n'), "美化后应当多行：{}", v.display);

        let arr = inspect_raw("[1,2,3]");
        assert_eq!(arr.shape, Shape::JsonArray);
        assert!(arr.display.contains('\n'));
    }

    #[test]
    fn json_lookalikes_are_text_not_json() {
        // 半截日志在真实数据里很常见：当成 JSON 只会甩一句解析错误
        assert_eq!(inspect_raw("{不是 JSON}").shape, Shape::Text);
        assert_eq!(inspect_raw("[未闭合").shape, Shape::Text);
        assert_eq!(inspect_raw(r#"{"a":}"#).shape, Shape::Text);
        // 只是"包含花括号"不算 JSON
        assert_eq!(inspect_raw("say {hello} now").shape, Shape::Text);
    }

    #[test]
    fn scalars_count_as_json_when_they_really_parse() {
        assert_eq!(inspect_raw("123").shape, Shape::ScalarJson);
        assert_eq!(inspect_raw("-1.5e3").shape, Shape::ScalarJson);
        assert_eq!(inspect_raw("true").shape, Shape::ScalarJson);
        assert_eq!(inspect_raw("null").shape, Shape::ScalarJson);
        assert_eq!(inspect_raw(r#""quoted""#).shape, Shape::ScalarJson);
        // 标量原样显示（不"美化"，也没什么可美化的）
        assert_eq!(inspect_raw("123").display, "123");
        // 不像 JSON 的自然不是
        assert_eq!(inspect_raw("truex").shape, Shape::Text);
        assert_eq!(inspect_raw("nope").shape, Shape::Text);
    }

    #[test]
    fn binary_hex_is_recognised_and_summarised_with_byte_count() {
        let v = inspect_raw("\\x48656c6c6f");
        assert_eq!(v.shape, Shape::Binary { byte_count: 5 });
        assert_eq!(v.display, "\\x48656c6c6f");
        assert!(v.summary(SummaryLangZh()).contains("二进制 5 字节"));
        // 奇数位 / 非十六进制 / 空 ⇒ 不是二进制
        assert_eq!(binary_byte_count("\\x486"), None);
        assert_eq!(binary_byte_count("\\xzz"), None);
        assert_eq!(binary_byte_count("\\x"), None);
        assert_eq!(binary_byte_count("48656c"), None);
    }

    // 小助手：让上面的断言读起来短一点（测试专用）
    #[allow(non_snake_case)]
    fn SummaryLangZh() -> SummaryLanguage {
        SummaryLanguage::ZhHans
    }

    #[test]
    fn long_values_are_truncated_and_say_how_long_they_were() {
        let long = "x".repeat(DEFAULT_DISPLAY_LIMIT + 50);
        let v = inspect_raw(&long);
        assert_eq!(v.shape, Shape::Text);
        assert!(v.is_truncated);
        assert_eq!(v.original_character_count, DEFAULT_DISPLAY_LIMIT + 50);
        assert!(v.display.ends_with('…'));
        let summary = v.summary(SummaryLanguage::ZhHans);
        assert!(summary.contains("字符") && summary.contains("已截断"), "{summary}");

        // 长 JSON 同理（截断的是**美化后**的文本）
        let long_json = format!(r#"{{"k":"{}"}}"#, "y".repeat(10));
        let small = inspect(Some(long_json.clone()), 20);
        assert!(small.is_truncated);
        assert_eq!(small.original_character_count, long_json.chars().count());
    }

    #[test]
    fn summaries_are_bilingual_and_count_lines() {
        let v = inspect_raw("line1\nline2\nline3");
        assert_eq!(v.shape, Shape::Text);
        assert_eq!(v.line_count, 3);
        let zh = v.summary(SummaryLanguage::ZhHans);
        let en = v.summary(SummaryLanguage::En);
        assert!(zh.contains("文本") && zh.contains("3 行"), "{zh}");
        assert!(en.contains("text") && en.contains("3 lines"), "{en}");
        // 单行就不提行数（少一句废话）
        let one = inspect_raw("just one line");
        assert!(!one.summary(SummaryLanguage::ZhHans).contains("行"));
    }

    #[test]
    fn char_and_byte_counts_differ_for_multibyte_text() {
        let v = inspect_raw("中文");
        assert_eq!(v.original_character_count, 2);
        assert_eq!(v.original_byte_count, 6);
    }

    #[test]
    fn row_is_built_in_column_order_and_tolerates_short_rows() {
        let columns = vec![
            ("id".to_string(), "int4".to_string()),
            ("note".to_string(), "text".to_string()),
            ("extra".to_string(), "text".to_string()),
        ];
        let fields = row(&columns, &[Some("1".into()), None], DEFAULT_DISPLAY_LIMIT);
        assert_eq!(fields.len(), 3);
        assert_eq!(fields[0].column_name, "id");
        assert_eq!(fields[0].value.shape, Shape::ScalarJson); // "1" 是真能解析的标量
        assert_eq!(fields[1].value.shape, Shape::Null);
        // 行比列短 ⇒ 缺的那格当 NULL（不 panic、也不编值）
        assert_eq!(fields[2].value.shape, Shape::Null);
        assert_eq!(fields[2].type_name, "text");
    }
}
