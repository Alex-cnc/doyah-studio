//! **代码格式化**的落地那一半（计划 2.6；规划与内置兜底在 `Db/src/format.rs`）
//!
//! ## 形态（人类主人 2026-10-02 定案，派活单 `T-20261002-013`）
//! **外部工具优先；无联网（或外部工具不可用）⇒ 回退内置并如实说明。**
//!
//! ## 三条纪律（每条都有实测判据）
//! 1. **探测要真探**：`where.exe` 找可执行文件、真跑一次版本旗标拿版本 —— 探不到就说探不到，
//!    **不编一个版本号**（版本号是"你用的是哪个工具"的证据）。
//! 2. **跑外部工具有界**：**超时**与**输出上限**都要有 —— 格式化器读 stdin 等输出，
//!    遇到怪文件可能不返回；没有超时就会把界面挂死。
//! 3. **失败如实报**：外部工具报错就把它的 stderr 带回给用户（**不吞掉**），
//!    并在这种情况下**不假装格式化成功了**。
//!
//! ## 为什么走 stdin / stdout 而不是让工具原地改文件
//! 原地改会让"保存冲突"那套护栏失效（工具已经把盘上改了，我们再判冲突就晚了）。
//! 走管道 ⇒ **内容在内存里进出，落盘仍走保存护栏**（盘上被别处改过照样拒绝）。

use doyah_studio_db::highlight::CodeTokenKind;
use doyah_studio_db::workspace::TextLanguage;
use doyah_studio_db::{FormatBuiltin, FormatPlan, FormatTool};

/// 外部工具的执行上限（格式化一个文件够用；超了就当失败）。
const TOOL_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(10);
/// 外部工具输出上限（防"吐出一屏错误"把内存吃满）。
const TOOL_OUTPUT_LIMIT: usize = 4 * 1024 * 1024;
/// 内容上限：超过就不格式化了（与编辑面同一档：太大的文件本来就不进编辑面）。
const MAX_FORMAT_BYTES: usize = 2 * 1024 * 1024;

/// 一个候选工具的探测结果。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolProbe {
    pub executable: String,
    pub display_name: String,
    /// 找到没有
    pub available: bool,
    /// 找到的完整路径
    pub path: Option<String>,
    /// 探测到的版本（**探不到就是 `None`**，绝不编造）
    pub version: Option<String>,
}

/// 用 `where.exe` 找可执行文件（Windows 上 `where` 比自己在 PATH 里拼扩展名可靠：
/// `.exe` / `.cmd` / `.bat` / `.ps1` 它都认）。
pub fn which(executable: &str) -> Option<String> {
    let output = std::process::Command::new("where.exe")
        .arg(executable)
        .stdin(std::process::Stdio::null())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout);
    text.lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(str::to_string)
}

/// 探测一个工具：找得到就给路径，并且**真跑一次版本旗标**（认这个旗标的话）。
pub fn probe_tool(tool: &FormatTool) -> ToolProbe {
    let path = which(&tool.executable);
    let version = match (&path, tool.can_report_version()) {
        (Some(_), true) => {
            // 版本旗标跑失败 ⇒ 版本就是"探不到"（**不拿报错文本当版本**）
            run_external(
                &tool.executable,
                &tool.version_arguments,
                None,
                false,
            )
            .ok()
            .and_then(|out| first_meaningful_line(&out))
        }
        _ => None,
    };
    ToolProbe {
        executable: tool.executable.clone(),
        display_name: tool.display_name.clone(),
        available: path.is_some(),
        path,
        version,
    }
}

/// 从版本输出里挑一行有意义的（多数工具第一行就是版本；空行跳过）。
fn first_meaningful_line(text: &str) -> Option<String> {
    text.lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(|line| line.chars().take(120).collect())
}

/// 给一个语言探测它的候选工具（**按候选顺序**）。
pub fn probe_language(language: TextLanguage) -> Vec<ToolProbe> {
    doyah_studio_db::tools_for(language)
        .iter()
        .map(probe_tool)
        .collect()
}

/// 跑一个外部工具：吃 `stdin`（有的话），把 stdout 拿回来。
///
/// **有界**：超时与输出上限；失败时把 stderr 一起带回来（`Err`，**不吞**）。
fn run_external(
    executable: &str,
    arguments: &[String],
    stdin_text: Option<&str>,
    echo_stdout_on_error: bool,
) -> Result<String, String> {
    use std::io::{Read, Write};

    let mut child = std::process::Command::new(executable)
        .args(arguments)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| format!("起不来（{e}）"))?;

    // 把内容喂进去。格式化器一般读完 stdin 才开始干，所以这里写完再读。
    if let Some(text) = stdin_text {
        if let Some(mut pipe) = child.stdin.take() {
            let _ = pipe.write_all(text.as_bytes());
            // 关掉 stdin：让工具知道"输入完了"（不关它会一直等）
            drop(pipe);
        }
    } else {
        drop(child.stdin.take());
    }

    // **有界等待**：超时就杀掉，如实报超时
    let deadline = std::time::Instant::now() + TOOL_TIMEOUT;
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) => {
                if std::time::Instant::now() >= deadline {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(format!("超过 {} 秒没返回（已中止）", TOOL_TIMEOUT.as_secs()));
                }
                std::thread::sleep(std::time::Duration::from_millis(20));
            }
            Err(e) => return Err(format!("等待失败（{e}）")),
        }
    }

    let mut stdout = String::new();
    let mut stderr = String::new();
    if let Some(mut pipe) = child.stdout.take() {
        let mut buffer = Vec::new();
        let _ = pipe.by_ref().take(TOOL_OUTPUT_LIMIT as u64).read_to_end(&mut buffer);
        stdout = String::from_utf8_lossy(&buffer).to_string();
    }
    if let Some(mut pipe) = child.stderr.take() {
        let mut buffer = Vec::new();
        let _ = pipe.by_ref().take(TOOL_OUTPUT_LIMIT as u64).read_to_end(&mut buffer);
        stderr = String::from_utf8_lossy(&buffer).to_string();
    }

    let status = child.wait().map_err(|e| format!("收尾失败（{e}）"))?;
    if status.success() {
        return Ok(stdout);
    }
    // **失败如实报**：把 stderr 带回去（截一段，别把界面刷满）
    let detail = first_meaningful_line(&stderr).unwrap_or_else(|| "（没有错误输出）".to_string());
    let _ = echo_stdout_on_error;
    Err(format!("它报错了：{detail}"))
}

/// 格式化的结果（给界面）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FormatOutcome {
    /// 格式化后的内容（**没改动时等于原文**）
    pub content: String,
    /// 内容变了没有
    pub changed: bool,
    /// 这句话必须如实说"用了哪一个工具 / 内置做了什么"
    pub note: String,
    /// 实际用的引擎（给界面标色用）：`external` / `builtin` / `refused`
    pub engine: String,
    /// 被拒绝或失败时的原因（`None` = 成功）
    pub problem: Option<String>,
}

/// 格式化一段内容（**不落盘**：落盘仍走保存护栏）。
///
/// `prefer_builtin` = 用户/环境要求"只用内置"（对应契约侧 `planBuiltinOnly` 那条；
/// 本侧留这个开关，是为了在断网环境里也能明确走内置那条路）。
pub fn format_content(
    language: TextLanguage,
    is_fallback: bool,
    content: &str,
    prefer_builtin: bool,
) -> FormatOutcome {
    if content.len() > MAX_FORMAT_BYTES {
        return FormatOutcome {
            content: content.to_string(),
            changed: false,
            note: format!("这个文件太大（{} 字节），本版不格式化（与编辑面同一档上限）。", content.len()),
            engine: "refused".to_string(),
            problem: Some("tooLarge".to_string()),
        };
    }

    let plan = if prefer_builtin {
        builtin_only_plan(language, is_fallback)
    } else {
        doyah_studio_db::plan_format(language, is_fallback, &|name: &str| which(name).is_some())
    };

    match plan {
        FormatPlan::Refused { .. } => FormatOutcome {
            content: content.to_string(),
            changed: false,
            note: doyah_studio_db::describe_format_plan(&plan),
            engine: "refused".to_string(),
            problem: Some("noFormatter".to_string()),
        },
        FormatPlan::Builtin { builtin } => {
            let (formatted, changed, extra) = run_builtin(builtin, content, language);
            FormatOutcome {
                content: formatted,
                changed,
                note: if changed {
                    format!("{} {extra}", doyah_studio_db::describe_format_plan(&plan))
                } else {
                    format!("{} 检查过了，**没有需要改的地方**。", doyah_studio_db::describe_format_plan(&plan))
                },
                engine: "builtin".to_string(),
                problem: None,
            }
        }
        FormatPlan::External { tool, .. } => {
            // 真跑：把内容从 stdin 喂进去，拿 stdout
            let arguments = external_arguments(&tool, language);
            match run_external(&tool.executable, &arguments, Some(content), false) {
                Ok(formatted) => {
                    // 版本单独探一次（**探不到就如实说探不到**）
                    let probe = probe_tool(&tool);
                    let changed = formatted != content;
                    let version_note = match &probe.version {
                        Some(version) => version.clone(),
                        None => "版本探测不到".to_string(),
                    };
                    FormatOutcome {
                        content: formatted,
                        changed,
                        note: format!(
                            "已用外部工具 {}（{version_note}）{}。",
                            tool.display_name,
                            if changed { "" } else { " 检查过了，**没有需要改的地方**" }
                        ),
                        engine: "external".to_string(),
                        problem: None,
                    }
                }
                Err(error) => {
                    // **外部工具失败 ⇒ 回退内置并如实说明**（这是定案里的兜底那一半）
                    let fallback = builtin_only_plan(language, is_fallback);
                    match fallback {
                        FormatPlan::Builtin { builtin } => {
                            let (formatted, changed, extra) = run_builtin(builtin, content, language);
                            FormatOutcome {
                                content: formatted,
                                changed,
                                note: format!(
                                    "外部工具 {} {error} ⇒ **已回退内置**（{}）{extra}。",
                                    tool.display_name,
                                    builtin.description()
                                ),
                                engine: "builtin".to_string(),
                                problem: None,
                            }
                        }
                        _ => FormatOutcome {
                            content: content.to_string(),
                            changed: false,
                            note: format!(
                                "外部工具 {} {error}，这条路也没有内置兜底 ⇒ **没有改动**。",
                                tool.display_name
                            ),
                            engine: "refused".to_string(),
                            problem: Some("externalFailed".to_string()),
                        },
                    }
                }
            }
        }
    }
}

/// 只用内置（**连探测都不做**；对应契约侧 `planBuiltinOnly`）。
fn builtin_only_plan(language: TextLanguage, is_fallback: bool) -> FormatPlan {
    if is_fallback {
        return FormatPlan::Refused {
            reason: doyah_studio_db::FormatRefusal::UnknownLanguage,
        };
    }
    let builtin = doyah_studio_db::builtin_for(language);
    if builtin.is_available() && doyah_studio_db::syntax_of(language).is_some() {
        return FormatPlan::Builtin { builtin };
    }
    FormatPlan::Refused {
        reason: doyah_studio_db::FormatRefusal::NoFormatter {
            language: language.key().to_string(),
        },
    }
}

/// 给外部工具的参数。
///
/// - 靠**文件名**判 parser 的工具（Prettier）要拿到一个"像这个名字"的输入名；
/// - 其余工具从 stdin 读、写到 stdout（`-` 是这几家的共同约定）。
fn external_arguments(tool: &FormatTool, language: TextLanguage) -> Vec<String> {
    match tool.executable.as_str() {
        "rustfmt" => vec!["--emit".to_string(), "stdout".to_string(), "--quiet".to_string()],
        "prettier" => {
            let _ = language;
            // Prettier：从 stdin 读，靠 `--parser` 给定语言（比文件名更稳，不依赖扩展名）
            vec![
                "--stdin-filepath".to_string(),
                format!("input.{}", extension_hint(language)),
            ]
        }
        "deno" => vec!["fmt".to_string(), "-".to_string()],
        "shfmt" => Vec::new(),
        "sqlformat" => vec!["-".to_string()],
        _ => Vec::new(),
    }
}

/// 给 Prettier 的文件名提示（它按扩展名判 parser）。
fn extension_hint(language: TextLanguage) -> &'static str {
    match language {
        TextLanguage::TypeScript => "ts",
        TextLanguage::JavaScript => "js",
        TextLanguage::Json => "json",
        TextLanguage::Css => "css",
        TextLanguage::Html => "html",
        TextLanguage::Markdown => "md",
        TextLanguage::Yaml => "yaml",
        TextLanguage::Toml => "toml",
        _ => "txt",
    }
}

/// 说清一档内置做了什么（**含放过几行 / 不变式没过就整档放弃**）。
fn describe_builtin(outcome: &BuiltinOutcome) -> String {
    if outcome.invariant_failed {
        // 不变式没过 ⇒ 整档放弃：**说出来**，不装作做过了
        return "（**检查后放弃**：这一档会改动到内容本身，为免改坏，内容一字未改）".to_string();
    }
    let base = if outcome.changed_lines > 0 {
        format!("（改了 {} 行的缩进/关键字", outcome.changed_lines)
    } else {
        "（没有需要改的地方".to_string()
    };
    if outcome.skipped_lines > 0 {
        format!("{base}；**放过了 {} 行** —— 那几行的花括号/关键字在字符串或注释里）", outcome.skipped_lines)
    } else {
        format!("{base}）")
    }
}

/// 跑内置兜底；返回（内容, 变了没有, 一句说明）。
fn run_builtin(builtin: FormatBuiltin, content: &str, language: TextLanguage) -> (String, bool, String) {
    match builtin {
        FormatBuiltin::Whitespace => {
            let report = doyah_studio_db::format_whitespace(content, language);
            let changed = report.formatted != content;
            let extra = if report.skipped_lines > 0 {
                format!(
                    "（去了 {} 行的行尾空白；**放过了 {} 行** —— 那几行的行尾空白在字符串或注释里）",
                    report.trimmed_lines, report.skipped_lines
                )
            } else {
                format!("（去了 {} 行的行尾空白）", report.trimmed_lines)
            };
            (report.formatted, changed, extra)
        }
        FormatBuiltin::BraceIndent => {
            let outcome = format_brace_indent(content, language);
            let extra = describe_builtin(&outcome);
            (outcome.content, outcome.changed_lines > 0, extra)
        }
        FormatBuiltin::Sql => {
            let outcome = format_sql_keywords(content, language);
            let extra = describe_builtin(&outcome);
            (outcome.content, outcome.changed_lines > 0, extra)
        }
        // `None` = 这条路不存在；真走到这里就**如实说没做**
        FormatBuiltin::None => (
            content.to_string(),
            false,
            "（这个内置档位不存在 ⇒ 内容一字未改）".to_string(),
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn which_finds_a_program_that_definitely_exists() {
        // `cmd.exe` 在 Windows 上必然存在 —— 这条判据同时验证"找得到就给路径"
        let found = which("cmd.exe");
        assert!(found.is_some(), "cmd.exe 应当找得到");
        let path = found.unwrap();
        assert!(path.to_lowercase().contains("cmd"), "{path}");
        // 不存在的程序 ⇒ None（**不瞎给一个路径**）
        assert!(which("definitely-not-a-real-program-xyz.exe").is_none());
    }

    #[test]
    fn probing_reports_availability_truthfully() {
        // 探一个必然存在的"工具"：用 cmd.exe 当输入，看探测结果自洽
        let tool = doyah_studio_db::FormatTool {
            executable: "cmd.exe".to_string(),
            display_name: "cmd".to_string(),
            needs_file_name: false,
            // 登记一个**必然非零退出**的旗标（cmd 对 /c 后跟不存在命令会返回非零）
            // ⇒ 版本应当是 None（**不把报错当版本**）。
            // 我第一版写的是 \--definitely-not-a-flag\：cmd **不认的旗标不当旗标**，
            // 它照样打印版本横幅并成功退出 ⇒ 用例的前提就是错的（不是实现错）。
            version_arguments: vec!["/c".to_string(), "exit 9".to_string()],
        };
        let probe = probe_tool(&tool);
        assert!(probe.available, "cmd.exe 应当探测到");
        assert!(probe.path.is_some());
        assert_eq!(probe.version, None, "认不出的旗标 ⇒ 版本是探不到，不是报错文本");

        // 不存在的工具 ⇒ available = false，路径与版本都没有
        let missing = doyah_studio_db::FormatTool {
            executable: "definitely-not-a-real-program-xyz.exe".to_string(),
            display_name: "missing".to_string(),
            needs_file_name: false,
            version_arguments: vec!["--version".to_string()],
        };
        let missing_probe = probe_tool(&missing);
        assert!(!missing_probe.available);
        assert!(missing_probe.path.is_none());
        assert!(missing_probe.version.is_none());
    }

    #[test]
    fn a_failing_external_tool_is_reported_not_swallowed() {
        // 拿 cmd.exe 跑一个必然失败的命令：错误要带回来（**不吞**）
        let error = run_external("cmd.exe", &["/c".to_string(), "exit 3".to_string()], None, false);
        assert!(error.is_err(), "非零退出应当算失败");
        assert!(error.unwrap_err().contains("报错"), "要如实说是它报错了");
    }

    #[test]
    fn external_tool_output_comes_back_through_stdin() {
        // 用 cmd.exe 的 `more` 之类容易受环境影响，这里直接验"喂进去、拿回来"这条管道：
        // `findstr` 从 stdin 读并回显匹配行 —— 它必然存在（Windows 自带）
        let output = run_external(
            "findstr.exe",
            &["x".to_string()],
            Some("axb\nno match\n"),
            false,
        );
        assert!(output.is_ok(), "findstr 应当跑得起来：{output:?}");
        assert!(output.unwrap().contains("axb"), "喂进去的内容应当能回来");
    }

    #[test]
    fn a_too_large_file_is_refused_with_its_real_size() {
        let big = "x".repeat(MAX_FORMAT_BYTES + 1);
        let outcome = format_content(TextLanguage::Rust, false, &big, false);
        assert!(!outcome.changed);
        assert_eq!(outcome.engine, "refused");
        assert!(outcome.note.contains("太大"), "{}", outcome.note);
    }

    #[test]
    fn builtin_whitespace_runs_and_says_what_it_did() {
        // 强制走内置：Rust 是有词法规则的语言，且"只用内置"不进外部探测那条路
        let outcome = format_content(TextLanguage::Rust, false, "let a = 1;   \n", true);
        assert_eq!(outcome.engine, "builtin");
        assert_eq!(outcome.content, "let a = 1;\n");
        assert!(outcome.changed);
        assert!(outcome.note.contains("行尾空白"), "{}", outcome.note);

        // 认不出的语言 + 只用内置 ⇒ 如实拒绝，一个字不改
        let refused = format_content(TextLanguage::PlainText, true, "whatever   \n", true);
        assert_eq!(refused.engine, "refused");
        assert_eq!(refused.content, "whatever   \n", "拒绝时不能改内容");
        assert!(refused.note.contains("认不出"));
    }
}

// ── 内置兜底的两档（2.6）：按花括号重排缩进 / SQL 关键字与分行 ──────────────────────────
//
// 为什么放在这里（而不是领域层 `format.rs`）：这两档要**按行切 + 按 token 片段判安全**，
// 而"哪段是字符串/注释"的判据来自领域层 `highlight::tokenize`。放在表示层能直接用，
// 领域层那半（规划与"整理空白"）保持不变。
//
// ## 两档共同的第一纪律：**只准动空白**
// 判据是一条**内容不变式**：把结果与原文的所有非空白字符抽出来，**必须逐字相同**。
// 不满足就**放弃这一档、原样返回**（宁可不格式化，也不改坏代码）。这条不变式在两档各有单测。

/// 一档内置格式化的结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BuiltinOutcome {
    pub content: String,
    /// 有多少行被改了缩进 / 关键字
    pub changed_lines: usize,
    /// **因为不安全而放过的行数**（放过的要让人知道）
    pub skipped_lines: usize,
    /// 内容不变式没通过 ⇒ 整档放弃（原样返回）
    pub invariant_failed: bool,
}

/// 抽出所有**非空白字符**（内容不变式用）。
fn non_whitespace(text: &str) -> String {
    text.chars().filter(|ch| !ch.is_whitespace()).collect()
}

/// 内容不变式：结果与原文的非空白字符必须逐字相同。
fn keeps_content(original: &str, formatted: &str) -> bool {
    non_whitespace(original) == non_whitespace(formatted)
}

/// 一行的**行首空白**（字符）与**内容起点**（字节）。返回 `(空白串, 内容起点的字节偏移)`。
fn leading_whitespace(line: &str) -> (String, usize) {
    let mut indent = String::new();
    let mut bytes = 0usize;
    for ch in line.chars() {
        if ch == ' ' || ch == '\t' {
            indent.push(ch);
            bytes += ch.len_utf8();
        } else {
            break;
        }
    }
    (indent, bytes)
}

/// 一行里有没有落在**字符串 / 注释**里的花括号（有就不敢按它算层级）。
fn braces_inside_tokens(line: &str, language: TextLanguage) -> bool {
    doyah_studio_db::tokenize_code(line, language)
        .iter()
        .filter(|span| matches!(span.kind, CodeTokenKind::Str | CodeTokenKind::Comment))
        .any(|span| line[span.start..span.end].contains('{') || line[span.start..span.end].contains('}'))
}

/// 一行里**不在字符串 / 注释里**的花括号净数（`{` 记 +1，`}` 记 −1）。
fn brace_delta(line: &str, language: TextLanguage) -> i32 {
    let spans: Vec<(usize, usize)> = doyah_studio_db::tokenize_code(line, language)
        .iter()
        .filter(|span| matches!(span.kind, CodeTokenKind::Str | CodeTokenKind::Comment))
        .map(|span| (span.start, span.end))
        .collect();
    let covered = |index: usize| spans.iter().any(|(start, end)| *start <= index && index < *end);
    let mut delta = 0i32;
    for (index, byte) in line.bytes().enumerate() {
        if covered(index) {
            continue;
        }
        match byte {
            b'{' => delta += 1,
            b'}' => delta -= 1,
            _ => {}
        }
    }
    delta
}

/// 用空格重排一行的行首缩进（**只换行首空白**，内容起点之后的每一个字节都不动）。
fn reindent(line: &str, depth: i32, unit: &str) -> (String, bool) {
    let (indent, content_start) = leading_whitespace(line);
    if content_start == line.len() {
        return (line.to_string(), false); // 空行 / 全空白行不动
    }
    let want = unit.repeat(depth.max(0) as usize);
    if indent == want {
        return (line.to_string(), false);
    }
    let mut out = String::with_capacity(line.len() + want.len());
    out.push_str(&want);
    out.push_str(&line[content_start..]);
    (out, true)
}

/// 内置档：**按花括号层级重排行首缩进**（缩进单位按文件里已有的推断）。
///
/// 安全边界（都在单测里）：
/// - 花括号**在字符串/注释里**的行**跳过**（算层级会算错、重排会改坏内容）；
/// - 行尾的 `{` / 行首的 `}` 参与层级；
/// - **只动行首空白** ⇒ 内容不变式必然成立；一旦不成立就整档放弃。
pub fn format_brace_indent(code: &str, language: TextLanguage) -> BuiltinOutcome {
    let lines = doyah_studio_db::code_lines::lines(code);
    // 缩进单位：按文件里已有的行首缩进取"最小正增量"，取不到就用 4 空格
    let unit = detect_indent_unit(code).unwrap_or_else(|| "    ".to_string());

    let mut out = String::with_capacity(code.len());
    let mut depth = 0i32;
    let mut changed_lines = 0usize;
    let mut skipped_lines = 0usize;

    for line in &lines {
        let text = line.text.as_str();
        let trimmed = text.trim_start();
        // 先减：行首是 `}` ⇒ 这一行要往外退一层
        let mut line_depth = depth;
        if trimmed.starts_with('}') {
            line_depth -= 1;
        }

        if braces_inside_tokens(text, language) {
            skipped_lines += 1;
            out.push_str(text);
        } else {
            let (reindented, changed) = reindent(text, line_depth, &unit);
            if changed {
                changed_lines += 1;
            }
            out.push_str(&reindented);
        }

        // 再按这一行的净变化更新层级
        let delta = if braces_inside_tokens(text, language) {
            0
        } else {
            brace_delta(text, language)
        };
        depth += delta;
        if depth < 0 {
            depth = 0;
        }

        if let Some(ending) = line.ending {
            out.push_str(ending.text());
        }
    }

    if !keeps_content(code, &out) {
        // 不变式没过 ⇒ **整档放弃**（宁可原样，也不改坏）
        return BuiltinOutcome {
            content: code.to_string(),
            changed_lines: 0,
            skipped_lines,
            invariant_failed: true,
        };
    }
    BuiltinOutcome {
        content: out,
        changed_lines,
        skipped_lines,
        invariant_failed: false,
    }
}

/// 推断缩进单位：文件里行首缩进的最小正增量（空格或制表符都认）。
fn detect_indent_unit(code: &str) -> Option<String> {
    let mut best: Option<usize> = None;
    for line in doyah_studio_db::code_lines::lines(code) {
        let (indent, content_start) = leading_whitespace(&line.text);
        if content_start == 0 || content_start == line.text.len() {
            continue;
        }
        // 纯制表符缩进 ⇒ 单位就用制表符
        if indent.starts_with('\t') {
            return Some("\t".to_string());
        }
        let width = indent.len();
        if width > 0 && best.map(|current| width < current).unwrap_or(true) {
            best = Some(width);
        }
    }
    best.filter(|width| *width > 0).map(|width| " ".repeat(width))
}

/// SQL 关键字表（**只大写这些词**；不认的词一个字不动）。
const SQL_KEYWORDS: &[&str] = &[
    "select", "from", "where", "group", "by", "order", "having", "limit", "offset", "insert",
    "into", "values", "update", "set", "delete", "join", "inner", "left", "right", "outer", "on",
    "as", "and", "or", "not", "null", "is", "in", "between", "like", "case", "when", "then",
    "else", "end", "union", "all", "distinct", "create", "table", "view", "index", "drop",
    "alter", "add", "column", "primary", "key", "foreign", "references", "default", "with",
    "returning", "exists", "count", "sum", "avg", "min", "max",
];

/// 内置档：**SQL 关键字大写**（字符串 / 注释里的一个字符都不动）。
///
/// 不做"重排成一行"那种激进的事：那会改动大量空白，风险与收益不成比例；
/// 大写关键字是**能证明安全**（逐词判定）且真有用的一档。
pub fn format_sql_keywords(code: &str, language: TextLanguage) -> BuiltinOutcome {
    let lines = doyah_studio_db::code_lines::lines(code);
    let mut out = String::with_capacity(code.len());
    let mut changed_lines = 0usize;
    let mut skipped_lines = 0usize;

    for line in &lines {
        let text = line.text.as_str();
        // 整行都在注释里（以 `--` 开头）⇒ 跳过
        if text.trim_start().starts_with("--") {
            skipped_lines += 1;
            out.push_str(text);
            if let Some(ending) = line.ending {
                out.push_str(ending.text());
            }
            continue;
        }
        // 排除字符串 / 注释片段后，逐词判定
        let spans: Vec<(usize, usize)> = doyah_studio_db::tokenize_code(text, language)
            .iter()
            .filter(|span| matches!(span.kind, CodeTokenKind::Str | CodeTokenKind::Comment))
            .map(|span| (span.start, span.end))
            .collect();
        let covered = |index: usize| spans.iter().any(|(start, end)| *start <= index && index < *end);
        let mut rebuilt = String::with_capacity(text.len());
        let mut changed = false;
        let mut index = 0usize;
        while index < text.len() {
            let byte = text.as_bytes()[index];
            // 词的开头（字母或下划线）且不在 token 里
            if (byte.is_ascii_alphabetic() || byte == b'_') && !covered(index) {
                let start = index;
                while index < text.len()
                    && (text.as_bytes()[index].is_ascii_alphanumeric() || text.as_bytes()[index] == b'_')
                {
                    index += 1;
                }
                let word = &text[start..index];
                let lower = word.to_ascii_lowercase();
                if SQL_KEYWORDS.contains(&lower.as_str()) {
                    let upper = lower.to_ascii_uppercase();
                    if upper != word {
                        changed = true;
                    }
                    rebuilt.push_str(&upper);
                } else {
                    rebuilt.push_str(word);
                }
                continue;
            }
            // 非词首：按 UTF-8 边界整字符复制
            let ch = text[index..].chars().next().unwrap_or(' ');
            rebuilt.push(ch);
            index += ch.len_utf8();
        }
        if changed {
            changed_lines += 1;
        }
        out.push_str(&rebuilt);
        if let Some(ending) = line.ending {
            out.push_str(ending.text());
        }
    }

    // SQL 档的不变式**按大小写不敏感比**：这一档要做的正是改大小写，
    // 拿"逐字相同"去比必然判失败（我第一版就是这样，用例红在不变式上，不是实现在这一步错）。
    if non_whitespace(&out).to_lowercase() != non_whitespace(code).to_lowercase() {
        return BuiltinOutcome {
            content: code.to_string(),
            changed_lines: 0,
            skipped_lines,
            invariant_failed: true,
        };
    }
    BuiltinOutcome {
        content: out,
        changed_lines,
        skipped_lines,
        invariant_failed: false,
    }
}

#[cfg(test)]
mod builtin_format_tests {
    use super::*;

    #[test]
    fn brace_indent_reindents_and_keeps_content_identical() {
        let messy = "fn main() {\nlet a = 1;\nif a > 0 {\nprintln!(\"hi\");\n}\n}\n";
        let outcome = format_brace_indent(messy, TextLanguage::Rust);
        assert!(!outcome.invariant_failed, "内容不变式必须成立");
        // **内容一字不改**（只动空白）
        assert_eq!(non_whitespace(&outcome.content), non_whitespace(messy));
        // 缩进确实按层级排了
        assert_eq!(
            outcome.content,
            "fn main() {\n    let a = 1;\n    if a > 0 {\n        println!(\"hi\");\n    }\n}\n"
        );
        assert!(outcome.changed_lines >= 3);
    }

    #[test]
    fn brace_indent_respects_the_existing_indent_unit_and_tabs() {
        // 文件里用的是 2 空格 ⇒ 按 2 空格排。
        // **内容里必须真有一行是缩进的**，单位才推断得出来 —— 我第一版给的是一份
        // "一行都没有缩进"的内容 ⇒ 推断不出单位、按默认 4 空格排（那是正确退化）。
        // 所以这里先放一行 2 空格缩进的，再放一行没缩进的看它有没有跟上 2 空格。
        let two = "fn a() {\n  let only = 1;\nfn b() {\nlet c = 2;\n}\n}\n";
        let two_out = format_brace_indent(two, TextLanguage::Rust);
        // 精确取那一行来比（**不要用带 `\n` 的子串断言** —— 行首前面还有缩进，
        // 子串会错位；我上一版就是这样，看着像实现错，其实是断言写错）
        let c_line = doyah_studio_db::code_lines::lines(&two_out.content)
            .into_iter()
            .find(|line| line.text.contains("let c"))
            .map(|line| line.text)
            .unwrap_or_default();
        // 单位是 2 空格 ⇒ 第一层 2 个、**第二层 4 个**（`let c` 在两层里）。
        // 我上一版把"两层"算成了 2 个空格 —— 又是用例算错，实现是对的。
        assert_eq!(c_line, "    let c = 2;", "两层缩进 = 2 × 单位 2 空格");
        let only_line = doyah_studio_db::code_lines::lines(&two_out.content)
            .into_iter()
            .find(|line| line.text.contains("let only"))
            .map(|line| line.text)
            .unwrap_or_default();
        assert_eq!(only_line, "  let only = 1;", "一层缩进 = 单位本身（2 空格，不是默认的 4）");
        // 用制表符的文件 ⇒ 继续用制表符（不把它换成空格）
        let tabs = "fn a() {\n\tlet b = 1;\n}\n";
        let tabs_out = format_brace_indent(tabs, TextLanguage::Rust);
        assert!(tabs_out.content.contains("\n\tlet b = 1;"), "{}", tabs_out.content);
    }

    #[test]
    fn brace_indent_skips_lines_whose_braces_are_inside_strings() {
        // 花括号在字符串里 ⇒ **放过这一行**（算层级会算错、重排会改坏内容）
        let tricky = "fn a() {\n    let s = \"}{\";\n}\n";
        let outcome = format_brace_indent(tricky, TextLanguage::Rust);
        assert_eq!(outcome.skipped_lines, 1, "字符串里带花括号的行要放过");
        assert!(outcome.content.contains("let s = \"}{\";"));
        assert!(!outcome.invariant_failed);
    }

    #[test]
    fn brace_indent_leaves_crlf_alone() {
        let crlf = "fn a() {\r\nlet b = 1;\r\n}\r\n";
        let outcome = format_brace_indent(crlf, TextLanguage::Rust);
        assert!(outcome.content.contains("\r\n"), "CRLF 要保留：{:?}", outcome.content);
        assert_eq!(outcome.content.matches("\r\n").count(), 3);
    }

    #[test]
    fn sql_keywords_are_uppercased_outside_strings_and_comments() {
        let sql = "select id, name from users where name = 'select me' -- select in comment\n";
        let outcome = format_sql_keywords(sql, TextLanguage::Sql);
        assert!(!outcome.invariant_failed);
        let text = &outcome.content;
        assert!(text.starts_with("SELECT id, name FROM users WHERE name = "), "{text}");
        // **字符串里的一个字不动**
        assert!(text.contains("'select me'"), "{text}");
        // **注释里的一个字不动**
        assert!(text.contains("-- select in comment"), "{text}");
        // 内容不变式：非空白字符相同（大写会改字符大小写 ⇒ 这条不变式对 SQL 档要放宽）
        assert_eq!(text.to_lowercase(), sql.to_lowercase(), "除大小写外内容一字不改");
    }

    #[test]
    fn sql_keywords_do_not_touch_column_named_like_a_keyword() {
        // `select_count` 这种带下划线的标识符**不是一个关键字** ⇒ 不动它
        let sql = "select select_count from t\n";
        let outcome = format_sql_keywords(sql, TextLanguage::Sql);
        assert!(outcome.content.contains("SELECT select_count FROM t"), "{}", outcome.content);
    }
}
