//! 导入导出的**纯逻辑**（1.6 段）：CSV 解析 / 列映射 / 行报告 / 导出格式化 / 落盘原子性。
//!
//! 六条口径（导入导出是"会毁数据、也会留下垃圾文件"的功能，条条都要说清）：
//! ① **导入先报数再写库**：`parse_csv` 只解析、不碰数据库；解析报告里如实给出
//!    「读了几行、丢了几行、为什么」——**跳过不许静默**（静默跳过等于悄悄少导了数据）。
//! ② **列映射按表头名**（不按位置）：CSV 的列序与表的列序不必一致；表头对不上的列
//!    **不猜**，列进 `unmatched` 让调用方决定。
//! ③ **引号按 RFC 4180**：字段含分隔符 / 引号 / 换行时用引号包起来，内部引号翻倍；
//!    允许字段里有换行（多行字段是 CSV 最容易写错的地方）。
//! ④ **导出走"临时文件 + 改名"**：中途失败**不留半截文件**（版本计划原文要求）；
//!    改名在同目录内做（跨盘改名不是原子操作）。
//! ⑤ **取消/失败要能清干净**：`atomic_write` 失败时删掉临时文件，返回可读原因。
//! ⑥ **分隔符嗅探有边界**：只在 `,` `;` `\t` `|` 里选，且以"表头一行切出来的列数最多"为准；
//!    选不出来（都只有一列）就用逗号 —— 不瞎猜。

use serde::{Deserialize, Serialize};

/// 支持的分隔符（嗅探只在这几个里选）。
pub const DELIMITERS: [char; 4] = [',', ';', '\t', '|'];

/// 解析报告：**读了几行、丢了几行、为什么**（跳过不许静默）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParseReport {
    /// 表头（第一行；没有表头时为空）
    pub header: Vec<String>,
    /// 成功解析的数据行
    pub rows: Vec<Vec<String>>,
    /// 总的数据行数（含被丢的）
    pub total_data_rows: usize,
    /// 被丢掉的行：行号（1 基，含表头那行）+ 原因
    pub skipped: Vec<SkippedRow>,
    /// 实际用的分隔符
    pub delimiter: char,
    /// 有没有表头（由调用方声明；本层只如实回填）
    pub has_header: bool,
}

/// 被丢掉的一行（**必须带原因**，否则用户不知道丢的是什么）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SkippedRow {
    /// 原文里的行号（1 基，从文件第一行算）
    pub line: usize,
    pub reason: String,
    /// 该行的前若干字符（给用户认这是哪一行）
    pub preview: String,
}

impl ParseReport {
    /// 表头与目标列的对账：`(匹配上的列, CSV 里多出来的, 表里缺的)`。
    ///
    /// 口径：**按名字匹配、大小写不敏感、忽略首尾空白**；不做任何"看起来像"的猜测。
    pub fn match_columns(&self, target: &[String]) -> ColumnMatch {
        let mut matched: Vec<(String, usize)> = Vec::new();
        let mut unmatched_csv: Vec<String> = Vec::new();
        for (index, name) in self.header.iter().enumerate() {
            let key = normalize_name(name);
            match target.iter().position(|t| normalize_name(t) == key) {
                Some(at) => matched.push((target[at].clone(), index)),
                None => unmatched_csv.push(name.clone()),
            }
        }
        let missing: Vec<String> = target
            .iter()
            .filter(|t| {
                !self
                    .header
                    .iter()
                    .any(|h| normalize_name(h) == normalize_name(t))
            })
            .cloned()
            .collect();
        ColumnMatch { matched, unmatched_csv, missing }
    }
}

/// 列对账结果。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ColumnMatch {
    /// `(目标表里的列名, CSV 里的列下标)`
    pub matched: Vec<(String, usize)>,
    /// CSV 里有、目标表里没有的列
    pub unmatched_csv: Vec<String>,
    /// 目标表里有、CSV 里没有的列
    pub missing: Vec<String>,
}

/// 归一化列名（比对用：去首尾空白、小写、把连续空白压成一个下划线）。
pub fn normalize_name(name: &str) -> String {
    let mut out = String::new();
    let mut last_was_space = false;
    for ch in name.trim().chars() {
        if ch.is_whitespace() {
            if !last_was_space {
                out.push('_');
                last_was_space = true;
            }
        } else {
            out.push(ch.to_ascii_lowercase());
            last_was_space = false;
        }
    }
    out
}

/// 嗅探分隔符：候选里"表头一行切出来的列数最多"的那个；并列时按 `DELIMITERS` 的顺序取先者。
///
/// 只切**第一行**（表头）——数据行里的分隔符可能被引号包着，拿数据行判会误判。
pub fn sniff_delimiter(text: &str, candidates: &[char]) -> char {
    let first_line = text.lines().next().unwrap_or("");
    let mut best = candidates.first().copied().unwrap_or(',');
    let mut best_count = 0usize;
    for &candidate in candidates {
        let count = split_line(first_line, candidate).len();
        if count > best_count {
            best_count = count;
            best = candidate;
        }
    }
    best
}

/// 按分隔符切一行（**引号规则见口径 ③**）。
fn split_line(line: &str, delimiter: char) -> Vec<String> {
    let mut out = Vec::new();
    let mut field = String::new();
    let mut in_quotes = false;
    let mut chars = line.chars().peekable();
    while let Some(ch) = chars.next() {
        if in_quotes {
            if ch == '"' {
                if chars.peek() == Some(&'"') {
                    field.push('"');
                    chars.next();
                } else {
                    in_quotes = false;
                }
            } else {
                field.push(ch);
            }
            continue;
        }
        if ch == '"' && field.is_empty() {
            in_quotes = true;
            continue;
        }
        if ch == delimiter {
            out.push(std::mem::take(&mut field));
            continue;
        }
        field.push(ch);
    }
    out.push(field);
    out
}

/// 解析 CSV 文本（**不碰数据库、不猜列**）。
///
/// `has_header` 为真时第一行当表头；为假时表头为空、第一行也算数据。
/// 空行被跳过（**记在 `skipped` 里**，让调用方看得见）；列数与表头不一致的行也跳过并记原因。
pub fn parse_csv(text: &str, has_header: bool) -> ParseReport {
    let delimiter = sniff_delimiter(text, &DELIMITERS);
    let logical_lines = logical_rows(text, delimiter);
    let mut header: Vec<String> = Vec::new();
    let mut rows: Vec<Vec<String>> = Vec::new();
    let mut skipped: Vec<SkippedRow> = Vec::new();
    let mut total_data_rows = 0usize;

    for (line_number, fields) in logical_lines {
        let all_empty = fields.iter().all(|f| f.trim().is_empty());
        if all_empty {
            skipped.push(SkippedRow {
                line: line_number,
                reason: "空行".to_string(),
                preview: fields.join(&delimiter.to_string()).chars().take(40).collect(),
            });
            continue;
        }
        if has_header && header.is_empty() {
            header = fields;
            continue;
        }
        total_data_rows += 1;
        if !header.is_empty() && fields.len() != header.len() {
            skipped.push(SkippedRow {
                line: line_number,
                reason: format!("列数不一致（表头 {} 列，这行 {} 列）", header.len(), fields.len()),
                preview: fields.join(&delimiter.to_string()).chars().take(40).collect(),
            });
            continue;
        }
        rows.push(fields);
    }

    ParseReport { header, rows, total_data_rows, skipped, delimiter, has_header }
}

/// 把文本切成**逻辑行**（引号里的换行不算换行）——多行字段是 CSV 最容易写错的地方。
///
/// 返回 `(行号, 字段)`；行号是**物理首行**的 1 基编号（多行字段占的那些行算它的）。
fn logical_rows(text: &str, delimiter: char) -> Vec<(usize, Vec<String>)> {
    let mut out = Vec::new();
    let mut field = String::new();
    let mut fields: Vec<String> = Vec::new();
    let mut in_quotes = false;
    let mut line_number = 1usize;
    let mut row_start_line = 1usize;
    let mut chars = text.chars().peekable();
    let mut started = false;

    while let Some(ch) = chars.next() {
        if ch == '\r' {
            // CRLF 只当一次换行
            if chars.peek() == Some(&'\n') {
                continue;
            }
            // 单独的 \r 也是换行
            if in_quotes {
                field.push('\n');
            } else {
                fields.push(std::mem::take(&mut field));
                out.push((row_start_line, std::mem::take(&mut fields)));
                line_number += 1;
                row_start_line = line_number;
                started = false;
            }
            continue;
        }
        if ch == '\n' && !in_quotes {
            fields.push(std::mem::take(&mut field));
            out.push((row_start_line, std::mem::take(&mut fields)));
            line_number += 1;
            row_start_line = line_number;
            started = false;
            continue;
        }
        if ch == '\n' {
            // 引号里的换行：留在字段里，但行号要推进
            field.push('\n');
            line_number += 1;
            continue;
        }
        if ch == '"' {
            if in_quotes {
                if chars.peek() == Some(&'"') {
                    field.push('"');
                    chars.next();
                } else {
                    in_quotes = false;
                }
            } else if field.is_empty() {
                in_quotes = true;
            } else {
                field.push('"');
            }
            started = true;
            continue;
        }
        if ch == delimiter && !in_quotes {
            fields.push(std::mem::take(&mut field));
            started = true;
            continue;
        }
        field.push(ch);
        started = true;
    }
    if started || !field.is_empty() || !fields.is_empty() {
        fields.push(field);
        out.push((row_start_line, fields));
    }
    out
}

/// 导出格式（1.6 段：CSV / JSON；Excel 走 Python，见表示层）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ExportKind {
    Csv,
    Json,
    /// 只导出表头与行数的探针（给"边读边写"用：先看有多少行）
    None,
}

/// 把一个字段编码成 CSV 字段（RFC 4180：必要时加引号、内部引号翻倍）。
pub fn csv_field(value: &str, delimiter: char) -> String {
    let needs_quote = value.contains(delimiter)
        || value.contains('"')
        || value.contains('\n')
        || value.contains('\r');
    if needs_quote {
        format!("\"{}\"", value.replace('"', "\"\""))
    } else {
        value.to_string()
    }
}

/// 把表头 + 行编码成 CSV 文本（`\r\n` 行尾，与 RFC 4180 一致）。
pub fn to_csv(header: &[String], rows: &[Vec<String>], delimiter: char) -> String {
    let mut out = String::new();
    out.push_str(
        &header
            .iter()
            .map(|h| csv_field(h, delimiter))
            .collect::<Vec<_>>()
            .join(&delimiter.to_string()),
    );
    for row in rows {
        out.push_str("\r\n");
        out.push_str(
            &row.iter()
                .map(|v| csv_field(v, delimiter))
                .collect::<Vec<_>>()
                .join(&delimiter.to_string()),
        );
    }
    out
}

/// 原子落盘：写临时文件 → 改名到目标。**失败不留半截文件**。
///
/// 为什么改名要在**同目录**：跨盘的 rename 不是原子操作（会退化成拷贝），
/// 于是"中途失败"又会留下半截文件 —— 正是本节要避免的。
pub fn atomic_write(target: &std::path::Path, content: &str) -> Result<(), String> {
    let parent = target
        .parent()
        .ok_or_else(|| format!("目标路径没有父目录：{}", target.display()))?;
    // 临时文件**与目标同目录**（原子改名要求同盘同目录），名字用 `<目标名>.part`。
    //
    // **不用点前缀**（原来写的是 `.<名字>.part`）：点开头的文件在本机沙箱里会被拒写
    // （实测 `写临时文件失败：拒绝访问 (os error 5)`），而那与"原子落盘"这件事无关 ——
    // 名字只是"别撞上目标"，用 `.part` 后缀已经够了。
    let tmp = parent.join(format!(
        "{}.part",
        target
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| "export".to_string())
    ));
    std::fs::write(&tmp, content).map_err(|e| format!("写临时文件失败：{e}（{}）", tmp.display()))?;
    std::fs::rename(&tmp, target).map_err(|e| {
        // 改名失败 ⇒ 把临时文件清掉（不留垃圾），并如实报原因
        let _ = std::fs::remove_file(&tmp);
        format!("改名失败：{e}（{} → {}）", tmp.display(), target.display())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_a_simple_csv_with_header() {
        let report = parse_csv("id,name\n1,alice\n2,bob\n", true);
        assert_eq!(report.header, vec!["id", "name"]);
        assert_eq!(report.rows.len(), 2);
        assert_eq!(report.total_data_rows, 2);
        assert!(report.skipped.is_empty(), "{:?}", report.skipped);
        assert_eq!(report.delimiter, ',');
    }

    #[test]
    fn quoted_fields_may_contain_delimiter_quotes_and_newlines() {
        let text = "id,note\n1,\"has,comma\"\n2,\"say \"\"hi\"\"\"\n3,\"two\nlines\"\n";
        let report = parse_csv(text, true);
        assert_eq!(report.rows.len(), 3, "{:?}", report.rows);
        assert_eq!(report.rows[0][1], "has,comma");
        assert_eq!(report.rows[1][1], "say \"hi\"");
        // 引号里的换行留在字段里（多行字段）
        assert_eq!(report.rows[2][1], "two\nlines");
        assert!(report.skipped.is_empty(), "多行字段不该被当成坏行：{:?}", report.skipped);
    }

    #[test]
    fn a_row_with_the_wrong_column_count_is_skipped_with_a_reason() {
        let report = parse_csv("id,name\n1,alice,extra\n2,bob\n", true);
        assert_eq!(report.rows.len(), 1, "{:?}", report.rows);
        assert_eq!(report.total_data_rows, 2, "总数含被丢的那行");
        assert_eq!(report.skipped.len(), 1);
        assert!(report.skipped[0].reason.contains("列数不一致"), "{:?}", report.skipped[0]);
        assert_eq!(report.skipped[0].line, 2, "行号指向原文第 2 行");
        assert!(!report.skipped[0].preview.is_empty(), "要能认出是哪一行");
    }

    #[test]
    fn blank_lines_are_reported_not_silently_dropped() {
        let report = parse_csv("id,name\n\n1,alice\n\n", true);
        assert_eq!(report.rows.len(), 1);
        assert!(report.skipped.iter().any(|s| s.reason.contains("空行")), "{:?}", report.skipped);
    }

    #[test]
    fn without_a_header_the_first_line_is_data() {
        let report = parse_csv("1,alice\n2,bob\n", false);
        assert!(report.header.is_empty());
        assert_eq!(report.rows.len(), 2);
        assert!(!report.has_header);
    }

    #[test]
    fn sniffs_the_delimiter_from_the_header_line() {
        assert_eq!(sniff_delimiter("a;b;c\n1;2;3", &DELIMITERS), ';');
        assert_eq!(sniff_delimiter("a\tb\tc\n1\t2\t3", &DELIMITERS), '\t');
        assert_eq!(sniff_delimiter("a|b\n1|2", &DELIMITERS), '|');
        // 只有一列 ⇒ 选不出更好的，按候选顺序取逗号
        assert_eq!(sniff_delimiter("single\nvalue", &DELIMITERS), ',');
        // 表头里有逗号但被引号包着 ⇒ 不该因此选中逗号
        assert_eq!(sniff_delimiter("\"a,b\";c\n1;2", &DELIMITERS), ';');
    }

    #[test]
    fn column_matching_is_by_name_case_insensitive() {
        let report = parse_csv("ID,Full Name\n1,alice\n", true);
        let target = vec!["id".to_string(), "full_name".to_string(), "extra".to_string()];
        let m = report.match_columns(&target);
        assert_eq!(m.matched, vec![("id".to_string(), 0), ("full_name".to_string(), 1)]);
        assert!(m.unmatched_csv.is_empty(), "{:?}", m.unmatched_csv);
        assert_eq!(m.missing, vec!["extra".to_string()]);
    }

    #[test]
    fn column_matching_reports_csv_columns_the_table_does_not_have() {
        let report = parse_csv("id,weird\n1,x\n", true);
        let m = report.match_columns(&["id".to_string()]);
        assert_eq!(m.unmatched_csv, vec!["weird".to_string()]);
        assert!(m.missing.is_empty());
    }

    #[test]
    fn name_normalisation_collapses_spaces_and_case() {
        assert_eq!(normalize_name("  Full   Name "), "full_name");
        assert_eq!(normalize_name("ID"), "id");
    }

    #[test]
    fn csv_field_quotes_only_when_needed_and_doubles_inner_quotes() {
        assert_eq!(csv_field("plain", ','), "plain");
        assert_eq!(csv_field("has,comma", ','), "\"has,comma\"");
        assert_eq!(csv_field("say \"hi\"", ','), "\"say \"\"hi\"\"\"");
        assert_eq!(csv_field("two\nlines", ','), "\"two\nlines\"");
    }

    #[test]
    fn csv_round_trips_through_parse() {
        let header = vec!["id".to_string(), "note".to_string()];
        let rows = vec![
            vec!["1".to_string(), "has,comma".to_string()],
            vec!["2".to_string(), "say \"hi\"".to_string()],
            vec!["3".to_string(), "two\nlines".to_string()],
        ];
        let text = to_csv(&header, &rows, ',');
        let back = parse_csv(&text, true);
        assert_eq!(back.header, header);
        assert_eq!(back.rows, rows, "导出的 CSV 必须能被自己解析回来");
        assert!(back.skipped.is_empty(), "{:?}", back.skipped);
    }

    /// 本测试自己的临时目录：**每次唯一**。
    ///
    /// 为什么要唯一：这两条原来用**固定名字**（`doyah_export_probe` / `doyah_export_ok.txt`）
    /// 放在系统临时区顶层 ⇒ 上一次运行的残留会互相干扰（本侧实测：一条一直红）。
    fn own_dir(tag: &str) -> std::path::PathBuf {
        use std::sync::atomic::{AtomicUsize, Ordering};
        static COUNTER: AtomicUsize = AtomicUsize::new(0);
        let unique = COUNTER.fetch_add(1, Ordering::Relaxed);
        // **夹具根落在工作区里**，不用系统临时区 ——
        // 本机（本会话沙箱）拒写系统临时区：实测 `写临时文件失败：拒绝访问 (os error 5)`。
        // 这是本仓既有约定（外壳侧各测试模块也这么取），这里照同一口径。
        let root = match std::env::var("DOYAH_TEST_ROOT") {
            Ok(value) if !value.trim().is_empty() => std::path::PathBuf::from(value),
            _ => std::path::PathBuf::from("D:/AIProjects/_tmp_face2/fish-fixtures"),
        };
        let dir = root.join(format!("doyah_io_csv_{tag}_{}_{unique}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        dir
    }

    #[test]
    fn atomic_write_leaves_no_partial_file_when_the_rename_fails() {
        // **按真实场景来**：目标是一个**已存在的目录**（`<dir>/occupied`），
        // 这样临时文件落在 `<dir>` 里（与目标同目录 —— 原子改名要求的就是这个），
        // 改名必然失败 ⇒ 临时文件必须被清掉。
        //
        // 原来这条把"目录"本身当目标，于是临时文件落在**临时区顶层**：
        // 既不像真实调用，又会与别的测试/残留互相踩（本侧实测它一直红）。
        let dir = own_dir("probe");
        let occupied = dir.join("occupied");
        std::fs::create_dir_all(&occupied).unwrap();

        let err = atomic_write(&occupied, "x").unwrap_err();
        assert!(err.contains("改名失败"), "{err}");

        // **只扫自己那个目录**（原来扫的是整个系统临时区 ⇒ 会被无关残留判红）
        let leftovers: Vec<String> = std::fs::read_dir(&dir)
            .unwrap()
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().to_string())
            .filter(|n| n.ends_with(".part"))
            .collect();
        assert!(leftovers.is_empty(), "失败后不许留下临时文件：{leftovers:?}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn atomic_write_succeeds_and_replaces_content() {
        // 同样用**自己那个目录**（固定文件名在并行/重复运行时会互相踩）
        let dir = own_dir("replace");
        let path = dir.join("export_ok.txt");
        atomic_write(&path, "first").expect("第一次写应当成功");
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "first");
        // 再写一次：内容被整体替换（不是追加）
        atomic_write(&path, "second").expect("第二次写应当成功");
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "second");
        // 成功后也不该留下临时文件
        let leftovers: Vec<String> = std::fs::read_dir(&dir)
            .unwrap()
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().to_string())
            .filter(|n| n.ends_with(".part"))
            .collect();
        assert!(leftovers.is_empty(), "写成功后不留临时文件：{leftovers:?}");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
