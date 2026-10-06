//! **代码格式化**（FR-EDIT-39 / 计划 2.6）
//!
//! ## 形态（人类主人 2026-10-02 最后一次拍板，派活单 `T-20261002-013`）
//! **外部工具优先；无联网（或外部工具不可用）⇒ 回退内置并如实说明。**
//! 三书 `FR-EDIT-39` 那行已注 `contract-change`（口径由「③ 混合」收紧为这一条）。
//!
//! ## 三条出口（都要能在界面上说清）
//! 1. **认不出这个语言** ⇒ 拒绝（`unknownLanguage`）—— **不装作用纯文本格式化器"格式化"了一遍**；
//! 2. **有外部工具**（按候选顺序，第一个装了的就用它）⇒ 用它，并**说出是哪一个、什么版本**；
//! 3. **没有外部工具但这条路能兜底** ⇒ 内置，并**说清内置只做了什么**（不夸大）。
//!
//! ## 内置兜底为什么**只对有词法规则的语言开放**
//! 内置只做"整理空白"这类**能证明安全**的事。证明靠词法：一段行尾空白**在字符串里**就是内容，
//! 删掉就改了别人的数据。没有词法规则（纯文本 / Markdown）就**证明不了** ⇒ 不做，如实拒绝，
//! **不猜着改**。这条口径与对侧 `Core/CodeFormatting.swift` 的 `plan` 一致。

use crate::highlight::{syntax_of, tokenize, CodeTokenKind};
use crate::workspace::TextLanguage;

/// 一个外部格式化器的登记（**名字不许空**：说了用外部工具就得说得清是哪一个）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Tool {
    /// 可执行文件名（探测 PATH 用）
    pub executable: String,
    /// 界面上如实说明用的名字（`Prettier` / `gofmt` …）
    pub display_name: String,
    /// 有些工具靠**文件名**判语言（Prettier 就是）⇒ 要把真实文件名传给它
    pub needs_file_name: bool,
    /// 取版本用的参数（不认 `--version` 的工具登记空数组 —— `gofmt` 就是）
    pub version_arguments: Vec<String>,
}

impl Tool {
    fn new(executable: &str, display_name: &str, needs_file_name: bool, version_arguments: &[&str]) -> Self {
        Self {
            executable: executable.to_string(),
            display_name: display_name.to_string(),
            needs_file_name,
            version_arguments: version_arguments.iter().map(|s| s.to_string()).collect(),
        }
    }

    /// 这个工具认不认 `--version`（不认就不去探测版本，免得把它的报错当版本）。
    pub fn can_report_version(&self) -> bool {
        !self.version_arguments.is_empty()
    }
}

/// 内置兜底能做到的程度。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Builtin {
    /// 什么都不做（这条路不存在）
    None,
    /// 整理空白：去掉**行尾空白**（字符串/注释里的行尾空白**不动**）
    Whitespace,
    /// 按花括号层级重排缩进
    BraceIndent,
    /// SQL 关键字大小写与分行
    Sql,
}

impl Builtin {
    pub const fn is_available(self) -> bool {
        !matches!(self, Builtin::None)
    }

    /// 界面上要说清它到底做了什么（**不夸大**）。
    pub const fn description(self) -> &'static str {
        match self {
            Builtin::None => "不做任何事",
            Builtin::Whitespace => "只去掉行尾空白（字符串与注释里的空白一个字都不动）",
            Builtin::BraceIndent => "按花括号层级重排缩进",
            Builtin::Sql => "SQL 关键字大小写与分行",
        }
    }
}

/// 一个语言的格式化能力。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Capability {
    pub tools: Vec<Tool>,
    pub builtin: Builtin,
}

/// 这个语言能用哪些外部工具（**按候选顺序**：第一个装了的就用它）。
///
/// **只覆盖本侧语言表里真有的语言**（Windows 侧按常见语言前 10：Rust / TypeScript / JavaScript /
/// Json / Toml / Yaml / Sql / Shell / Html / Css / Markdown / 纯文本）。
/// 表里没有的语言**不编造工具**：没有就走到"如实拒绝"那条路。
pub fn tools_for(language: TextLanguage) -> Vec<Tool> {
    match language {
        TextLanguage::Rust => vec![Tool::new("rustfmt", "rustfmt", false, &["--version"])],
        TextLanguage::TypeScript | TextLanguage::JavaScript | TextLanguage::Json | TextLanguage::Css => {
            vec![
                Tool::new("prettier", "Prettier", true, &["--version"]),
                Tool::new("deno", "deno fmt", true, &["--version"]),
            ]
        }
        TextLanguage::Shell => vec![Tool::new("shfmt", "shfmt", false, &["--version"])],
        TextLanguage::Sql => vec![Tool::new("sqlformat", "sqlformat", false, &["--version"])],
        TextLanguage::Html => vec![Tool::new("prettier", "Prettier", true, &["--version"])],
        // Toml / Yaml / Markdown / 纯文本：没有登记外部工具
        _ => Vec::new(),
    }
}

/// 这个语言的内置兜底能力。
///
/// **只给有词法规则的语言开"整理空白"**：没有词法就证明不了"那段行尾空白不在字符串里"
/// ⇒ 不做（纯文本 / Markdown / YAML 的空白本来就可能是内容）。
pub fn builtin_for(language: TextLanguage) -> Builtin {
    match language {
        TextLanguage::Sql => Builtin::Sql,
        TextLanguage::Rust
        | TextLanguage::TypeScript
        | TextLanguage::JavaScript
        | TextLanguage::Json
        | TextLanguage::Css
        | TextLanguage::Shell
        | TextLanguage::Html
        | TextLanguage::Toml => Builtin::Whitespace,
        // 没有词法规则 ⇒ 不开放兜底
        TextLanguage::Markdown | TextLanguage::Yaml | TextLanguage::PlainText => Builtin::None,
    }
}

/// 规划的结果（三条出口）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase", tag = "kind")]
pub enum Plan {
    /// 用外部工具（**说出是哪一个**；版本探测不到就是 `None`）
    External { tool: Tool, version: Option<String> },
    /// 用内置兜底
    Builtin { builtin: Builtin },
    /// **如实拒绝**
    Refused { reason: Refusal },
}

/// 拒绝的原因。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase", tag = "kind")]
pub enum Refusal {
    /// 认不出这个语言（回落值）—— **不装作用纯文本格式化器格式化了一遍**
    UnknownLanguage,
    /// 认得、但没有可用的格式化器
    NoFormatter { language: String },
}

/// 规划：**外部优先 → 内置兜底（只对有词法规则的语言）→ 如实拒绝**。
///
/// `is_executable` 由调用方给（本层不碰文件系统 ⇒ 单测能把三条分支都跑到）。
/// `is_fallback` = 这个语言是不是"认不出来"的回落值。
pub fn plan_format(
    language: TextLanguage,
    is_fallback: bool,
    is_executable: &dyn Fn(&str) -> bool,
) -> Plan {
    // ① 认不出 ⇒ 拒绝
    if is_fallback {
        return Plan::Refused {
            reason: Refusal::UnknownLanguage,
        };
    }
    // ② 外部优先（候选顺序，第一个装了的就用）
    if let Some(tool) = tools_for(language).into_iter().find(|tool| is_executable(&tool.executable)) {
        return Plan::External { tool, version: None };
    }
    // ③ 内置兜底：**只对有词法规则的语言开放**（没有词法就证明不了"那段空白不在字符串里"）
    let builtin = builtin_for(language);
    if builtin.is_available() && syntax_of(language).is_some() {
        return Plan::Builtin { builtin };
    }
    // ④ 都不行：如实拒绝，并说清是哪个语言
    Plan::Refused {
        reason: Refusal::NoFormatter {
            language: language.key().to_string(),
        },
    }
}

/// 界面上的一句话（**说出来的是哪一个、什么版本 / 或者内置只做了什么**）。
pub fn describe(plan: &Plan) -> String {
    match plan {
        Plan::External { tool, version } => match version {
            Some(version) => format!("已用外部工具 {} {}。", tool.display_name, version),
            // **版本探测不到就如实说探测不到**，不编一个
            None => format!("已用外部工具 {}（版本探测不到，未编造）。", tool.display_name),
        },
        Plan::Builtin { builtin } => format!(
            "**没找到可用的外部格式化器**，已用内置兜底：{}。",
            builtin.description()
        ),
        Plan::Refused { reason } => match reason {
            Refusal::UnknownLanguage => {
                "认不出这个文件是什么语言，**没有格式化**（不拿纯文本规则去改代码）。".to_string()
            }
            Refusal::NoFormatter { language } => format!(
                "{language} 没有可用的格式化器（外部工具没装、这条路也没有内置兜底），**没有改动**。"
            ),
        },
    }
}

/// 内置"整理空白"的结果。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WhitespaceReport {
    pub formatted: String,
    /// 去掉了行尾空白的行数
    pub trimmed_lines: usize,
    /// **因为行尾空白在字符串/注释里而放过的行数**（放过的要让人知道，不能悄悄跳过）
    pub skipped_lines: usize,
}

/// 内置兜底：**只去掉行尾空白**，而且**字符串与注释里的行尾空白一个字都不动**。
///
/// 判据来自词法：把每行按行内偏移切出 token 片段，若行尾那段空白落在 token 里（即它属于
/// 字符串或注释）⇒ **放过这一行**并把数字记下来（`skipped_lines`）。
pub fn format_whitespace(code: &str, language: TextLanguage) -> WhitespaceReport {
    let mut formatted = String::with_capacity(code.len());
    let mut trimmed_lines = 0usize;
    let mut skipped_lines = 0usize;

    for line in crate::code_lines::lines(code) {
        let text = line.text.as_str();
        let trimmed = text.trim_end();
        if trimmed.len() == text.len() {
            // 没有行尾空白，原样
            formatted.push_str(text);
        } else {
            // 行尾空白落在 token 里 ⇒ **放过**（那可能是字符串内容）
            // token 偏移是**字节** ⇒ 这里也用字节长度（用字符数会错位）
            let trailing_start = trimmed.len();
            // 判定：行尾空白所在处是否被某个 **字符串 / 注释** 片段覆盖
            let covered = tokenize(text, language).iter().any(|span| {
                matches!(span.kind, CodeTokenKind::Str | CodeTokenKind::Comment)
                    && span.start <= trailing_start
                    && span.end > trailing_start
            });
            if covered {
                skipped_lines += 1;
                formatted.push_str(text);
            } else {
                trimmed_lines += 1;
                formatted.push_str(trimmed);
            }
        }
        if let Some(ending) = line.ending {
            formatted.push_str(ending.text());
        }
    }
    WhitespaceReport {
        formatted,
        trimmed_lines,
        skipped_lines,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn none_installed(_: &str) -> bool {
        false
    }

    fn all_installed(_: &str) -> bool {
        true
    }

    fn only(name: &'static str) -> impl Fn(&str) -> bool {
        move |candidate: &str| candidate == name
    }

    #[test]
    fn an_unrecognised_language_is_refused_not_pretended() {
        // 认不出 ⇒ 拒绝。**不拿纯文本规则去"格式化"代码**
        let plan = plan_format(TextLanguage::PlainText, true, &all_installed);
        assert_eq!(
            plan,
            Plan::Refused {
                reason: Refusal::UnknownLanguage
            }
        );
        assert!(describe(&plan).contains("认不出"));
    }

    #[test]
    fn an_external_tool_wins_over_the_builtin() {
        // 装了 rustfmt ⇒ 用它（外部优先），且说得出是哪一个
        let plan = plan_format(TextLanguage::Rust, false, &only("rustfmt"));
        match &plan {
            Plan::External { tool, .. } => assert_eq!(tool.display_name, "rustfmt"),
            other => panic!("应当用外部工具，实际 {other:?}"),
        }
        assert!(describe(&plan).contains("rustfmt"));
        // 版本探测得到就说版本；探测不到**如实说探测不到**
        let with_version = Plan::External {
            tool: tools_for(TextLanguage::Rust)[0].clone(),
            version: Some("1.7.0".to_string()),
        };
        assert!(describe(&with_version).contains("1.7.0"));
        let without = Plan::External {
            tool: tools_for(TextLanguage::Rust)[0].clone(),
            version: None,
        };
        assert!(describe(&without).contains("探测不到"));
    }

    #[test]
    fn the_candidate_order_decides_which_tool_is_used() {
        // TypeScript 的候选顺序是 Prettier → deno fmt；两个都装了要用 Prettier
        let plan = plan_format(TextLanguage::TypeScript, false, &all_installed);
        match plan {
            Plan::External { tool, .. } => assert_eq!(tool.display_name, "Prettier"),
            other => panic!("{other:?}"),
        }
        // 只装了 deno ⇒ 用 deno fmt（**退而求其次也要说得出名字**）
        let second = plan_format(TextLanguage::TypeScript, false, &only("deno"));
        match second {
            Plan::External { tool, .. } => assert_eq!(tool.display_name, "deno fmt"),
            other => panic!("{other:?}"),
        }
        // Prettier 靠**文件名**判 parser ⇒ 登记里要标出来
        assert!(tools_for(TextLanguage::TypeScript)[0].needs_file_name);
        // **不认版本旗标的工具不去探测版本**（本侧登记的几种都认 `--version`，
        // 所以这条用构造的工具验口径本身；将来加了 gofmt 这类工具，登记时把参数留空即可）
        let no_version_flag = Tool::new("gofmt", "gofmt", false, &[]);
        assert!(!no_version_flag.can_report_version());
        assert!(tools_for(TextLanguage::Rust)[0].can_report_version());
    }

    #[test]
    fn without_an_external_tool_the_builtin_covers_only_languages_with_lexical_rules() {
        // 有词法规则（Rust）⇒ 内置兜底
        let plan = plan_format(TextLanguage::Rust, false, &none_installed);
        assert_eq!(
            plan,
            Plan::Builtin {
                builtin: Builtin::Whitespace
            }
        );
        let text = describe(&plan);
        assert!(text.contains("没找到") && text.contains("行尾空白"), "{text}");
        // 没有词法规则（Markdown / YAML / 纯文本）⇒ **不开放兜底**，如实拒绝
        for language in [TextLanguage::Markdown, TextLanguage::Yaml, TextLanguage::PlainText] {
            let plan = plan_format(language, false, &none_installed);
            match plan {
                Plan::Refused {
                    reason: Refusal::NoFormatter { .. },
                } => {}
                other => panic!("{language:?} 应当如实拒绝，实际 {other:?}"),
            }
        }
        // SQL 有词法也有内置（登记的是 Sql）
        assert_eq!(builtin_for(TextLanguage::Sql), Builtin::Sql);
    }

    #[test]
    fn whitespace_formatting_leaves_string_contents_alone() {
        // 普通行：去掉行尾空白
        let report = format_whitespace("let a = 1;   \nlet b = 2;\t\n", TextLanguage::Rust);
        assert_eq!(report.formatted, "let a = 1;\nlet b = 2;\n");
        assert_eq!(report.trimmed_lines, 2);
        assert_eq!(report.skipped_lines, 0);

        // **字符串里的行尾空白一个字都不动**（那是内容）
        let inside = format_whitespace("let s = \"trailing   \n", TextLanguage::Rust);
        assert_eq!(inside.skipped_lines, 1, "字符串里的行尾空白要放过");
        assert!(inside.formatted.contains("trailing   "), "{:?}", inside.formatted);

        // 注释里的行尾空白也放过
        let comment = format_whitespace("// note   \nlet a = 1;   \n", TextLanguage::Rust);
        assert_eq!(comment.skipped_lines, 1);
        assert_eq!(comment.trimmed_lines, 1);
        assert!(comment.formatted.starts_with("// note   \n"), "{:?}", comment.formatted);

        // 行终止符原样保留（CRLF 不被改成 LF）
        let crlf = format_whitespace("let a = 1;   \r\nlet b = 2;\r\n", TextLanguage::Rust);
        assert_eq!(crlf.formatted, "let a = 1;\r\nlet b = 2;\r\n");

        // 没有行尾空白 ⇒ 一个字都不改（也不该"顺手重排"）
        let clean = format_whitespace("let a = 1;\n", TextLanguage::Rust);
        assert_eq!(clean.formatted, "let a = 1;\n");
        assert_eq!(clean.trimmed_lines + clean.skipped_lines, 0);
    }

    #[test]
    fn plan_and_refusal_serialise_with_a_kind_tag() {
        let external = serde_json::to_string(&Plan::External {
            tool: tools_for(TextLanguage::Rust)[0].clone(),
            version: Some("1.7.0".into()),
        })
        .unwrap();
        assert!(external.contains("\"kind\":\"external\""), "{external}");
        assert!(external.contains("\"displayName\":\"rustfmt\""), "{external}");
        let refused = serde_json::to_string(&Plan::Refused {
            reason: Refusal::UnknownLanguage,
        })
        .unwrap();
        assert!(refused.contains("\"kind\":\"unknownLanguage\""), "{refused}");
        let builtin = serde_json::to_string(&Plan::Builtin {
            builtin: Builtin::Whitespace,
        })
        .unwrap();
        assert!(builtin.contains("\"whitespace\""), "{builtin}");
        let back: Plan = serde_json::from_str(&external).unwrap();
        assert!(matches!(back, Plan::External { .. }));
    }
}
