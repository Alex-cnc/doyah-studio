//! 客户端侧整表 / 整库导出（`FR-STD-DB-IO-002`；契约等价物：macOS 侧 CLI `export --table`）
//!
//! 与「导出当前 SQL 的结果」（`FR-STD-DB-IO-001`，`io_csv` + 外壳 `export_to_file`）的分工必须一句话讲清：
//! - **IO-001** = 把**已经取回内存的一页结果**编码落盘（受行数上限约束，超出如实标截断）；
//! - **本片 = IO-002** = 让服务端按 `COPY` 协议把**整张表**推向客户端，客户端**逐块写盘** ——
//!   全程没有一个「整表在内存里」的时刻，所以整表行数再多也不会把内存抬起来。
//!
//! 三条硬口径（每条都对应一个真会犯的错）：
//! 1. **语句里只许 `TO STDOUT`**：绝不生成 `TO '<服务端路径>'` 或 `PROGRAM '…'` —— 那是让**服务端**读写
//!    自己盘上的文件，与本需求「导出到我的机器」是两件事，而且把权限面开到了服务端。
//!    语句只由 [`copy_out_statement`] 这一处生成，并用 [`is_client_side`] 在单测里钉死。
//! 2. **记录数要引号感知地数**：CSV 的一个值可以自带换行（`"a\nb"`），直接数 `\n` 会把一行数成两行，
//!    于是「导出了多少行」这个读数当场是假的。用 [`RecordCounter`] 走状态机（还认 `""` 转义）。
//! 3. **每表文件名由表名派生，不许把表名当路径拼**：`/` `\` `:` `..` 与 Windows 保留名（`CON` / `NUL` …）
//!    都能穿出目标目录或写不出文件。派生只走 [`assign_file_names`]，它同时解决「两个表名只在大小写上有别」
//!    这个 Windows 专有撞名（大小写不敏感卷上 `Foo` / `foo` 会落成同一个文件 ⇒ 后一个静默盖掉前一个）。

/// 整表导出的文件扩展名（与 IO-001 / IO-005 的 CSV 口径一致；用户拿到的就是能双击打开的表）。
pub const EXPORT_EXTENSION: &str = "csv";

/// Windows 上**不能**用作文件名的设备名（写 `con.csv` 会直接失败，`nul.csv` 更糟：写进黑洞不报错）。
const RESERVED_DEVICE_NAMES: [&str; 22] = [
    "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8",
    "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
];

/// 生成语句时唯一可能的失败原因（表名为空 = 界面没把目标表带上来）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CopyExportError {
    /// 表名为空（或只有空白）
    EmptyTable,
    /// 名字里有 NUL：任何 SQL / 文件名都不接受，宁可报错也不猜
    EmbeddedNul,
}

impl CopyExportError {
    /// 给界面用的技术标识（本地化在界面层，与 `browse::BrowseError` 同一口径）。
    pub const fn identifier(self) -> &'static str {
        match self {
            CopyExportError::EmptyTable => "emptyTable",
            CopyExportError::EmbeddedNul => "embeddedNul",
        }
    }

    /// 给用户看的一句话（含「该怎么做」）。
    pub const fn message(self) -> &'static str {
        match self {
            CopyExportError::EmptyTable => "没指定表名 —— 先选一张表再导出（整库导出请给目录）",
            CopyExportError::EmbeddedNul => "表名里含不可见字符（NUL），无法安全拼进语句：请检查对象名",
        }
    }
}

/// 生成 `COPY <限定名> TO STDOUT`（**服务端只往客户端推流，不碰自己的文件系统**）。
///
/// - `header = true` ⇒ 第一行是列名（CSV 表头），行数读数要减掉它；
/// - 标识符一律经 `writeback::quote_ident` 加引号（含 `"` 的表名由它转义，本函数不另写一套）；
/// - `schema` 为空 ⇒ 只写表名（走 `search_path`，与界面「当前 schema」语义一致）。
pub fn copy_out_statement(
    schema: Option<&str>,
    table: &str,
    header: bool,
) -> Result<String, CopyExportError> {
    let name = table.trim();
    if name.is_empty() {
        return Err(CopyExportError::EmptyTable);
    }
    if name.contains('\0') || schema.map(|s| s.contains('\0')).unwrap_or(false) {
        return Err(CopyExportError::EmbeddedNul);
    }
    let schema = schema.map(str::trim).filter(|s| !s.is_empty());
    let target = crate::writeback::qualified(schema, name);
    let header = if header { "true" } else { "false" };
    Ok(format!(
        "COPY {target} TO STDOUT WITH (FORMAT csv, HEADER {header})"
    ))
}

/// 判据本身：这条语句是不是**客户端侧**取数（`TO STDOUT` 且无 `PROGRAM`）。
///
/// 单测既断言「我们生成的语句通过」，也断言「手写的服务端写文件语句不通过」——
/// 只判前者的话，函数恒 `true` 也能绿。
pub fn is_client_side(statement: &str) -> bool {
    let upper = statement.to_uppercase();
    upper.contains("TO STDOUT") && !upper.contains("PROGRAM")
}

/// **引号感知**的 CSV 记录计数器：喂字节块，出记录数。
///
/// 为什么必须感知引号：`COPY … (FORMAT csv)` 会把带换行 / 逗号 / 引号的值整个包进 `"…"`，
/// 值内的换行是**数据**不是行界 —— 直接数 `\n` 会把「1 万行」数成「1.3 万行」。
/// `""` 是引号内的转义（一个字节的 `"`），状态机要能区分它和「字段结束」的那个 `"`。
#[derive(Debug, Default, Clone)]
pub struct RecordCounter {
    /// 已经数到的完整记录（以行为界，不含末尾没换行的残行）
    complete: usize,
    /// 当前是否在引号内
    in_quotes: bool,
    /// 在引号内遇到 `"`：还不能判定是转义还是收尾，等下一个字节说了算
    quote_pending: bool,
    /// 行界之后又来过渡字节 ⇒ 末尾有一条没换行收尾的记录
    tail_partial: bool,
}

impl RecordCounter {
    pub fn new() -> Self {
        Self::default()
    }

    /// 喂一块字节（**块边界可以落在任何位置**，包括某个中文字符中间或一串 `""` 中间）。
    pub fn push(&mut self, chunk: &[u8]) {
        for &byte in chunk {
            if self.in_quotes {
                if self.quote_pending {
                    // 上一个字节是引号内的 `"`：再来一个 `"` = 转义；否则那个 `"` 是收尾
                    self.quote_pending = false;
                    if byte == b'"' {
                        continue;
                    }
                    self.in_quotes = false;
                    // 落到下面按「引号外」处理这一个字节
                } else if byte == b'"' {
                    self.quote_pending = true;
                    continue;
                } else {
                    continue; // 引号内的换行 / 逗号都是数据
                }
            }
            match byte {
                b'"' => self.in_quotes = true,
                b'\n' => {
                    self.complete += 1;
                    self.tail_partial = false;
                }
                b'\r' => {} // CRLF 只按 \n 记一次
                _ => self.tail_partial = true,
            }
        }
    }

    /// 方便字符串来源（测试与短块用它）。
    pub fn push_str(&mut self, chunk: &str) {
        self.push(chunk.as_bytes());
    }

    /// 记录数（含末尾没有换行收尾的那一条）。
    pub fn records(&self) -> usize {
        self.complete + usize::from(self.tail_partial)
    }

    /// **数据行数**（导出完成后要报给用户的那个数）：`header = true` 时减掉表头。
    pub fn data_rows(&self, header: bool) -> usize {
        let records = self.records();
        if header {
            records.saturating_sub(1)
        } else {
            records
        }
    }
}

/// 把一个表名变成**安全的单段文件名**（不含目录分隔符、不是保留设备名、不以点结尾）。
fn sanitize_stem(table: &str) -> String {
    let mut out = String::with_capacity(table.len());
    for ch in table.chars() {
        match ch {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => out.push('_'),
            c if c.is_control() => out.push('_'),
            c => out.push(c),
        }
    }
    // Windows 会静默丢掉名字末尾的点和空格（写 `a.` 得到 `a`）⇒ 自己先收干净，别让落盘名与回报名不符
    let trimmed = out.trim().trim_end_matches(['.', ' ']).to_string();
    let trimmed = trimmed.trim_start_matches(' ').to_string();
    // 空名 / 纯点（`.`、`..`、`...`）：路径穿越的直接入口，一律换成一个中性名
    if trimmed.is_empty() || trimmed.chars().all(|c| c == '.') {
        return "table".to_string();
    }
    let stem = trimmed;
    // 保留设备名（大小写不敏感）：`CON` ⇒ `_CON`
    let upper = stem.to_uppercase();
    if RESERVED_DEVICE_NAMES.contains(&upper.as_str()) {
        return format!("_{stem}");
    }
    stem
}

/// 一个表名 ⇒ 一个文件名（`<安全名>.csv`）。单独用它只适合**一张表**；整库请走 [`assign_file_names`]。
pub fn table_file_name(table: &str, extension: &str) -> String {
    let ext: String = extension
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .collect();
    let ext = if ext.is_empty() {
        EXPORT_EXTENSION.to_string()
    } else {
        ext
    };
    format!("{}.{ext}", sanitize_stem(table))
}

/// 整库导出：给**全部表**各分配一个**互不相同**的文件名，并给出确定的行序。
///
/// 为什么需要它（不是在 shell 里 `format!("{table}.csv")` 就完了）：
/// - **撞名**：PostgreSQL 允许 `Foo` 与 `foo` 同时存在，而 Windows/APFS 不区分大小写 ⇒ 两张表落成同一个文件，
///   后一张静默盖掉前一张，界面上还报「导出成功」。这里按大小写不敏感去重，撞了补 `-2` / `-3`。
/// - **确定性**：按名字排序（先小写再原名做次键），同一批表两次导出得到同一份行序与同一份回报。
/// - **不丢表**：只去重文件名，不丢表 —— 撞名的两张表都导出，各一个文件（这是与「跳过重复项」的关键区别）。
pub fn assign_file_names(tables: &[String]) -> Vec<(String, String)> {
    let mut ordered: Vec<&String> = tables.iter().collect();
    ordered.sort_by(|a, b| {
        a.to_lowercase()
            .cmp(&b.to_lowercase())
            .then_with(|| a.cmp(b))
    });
    let mut used: Vec<String> = Vec::with_capacity(ordered.len());
    let mut out: Vec<(String, String)> = Vec::with_capacity(ordered.len());
    for table in ordered {
        let stem = sanitize_stem(table);
        let mut candidate = format!("{stem}.{EXPORT_EXTENSION}");
        let mut attempt = 2usize;
        while used.iter().any(|u| u.eq_ignore_ascii_case(&candidate)) {
            candidate = format!("{stem}-{attempt}.{EXPORT_EXTENSION}");
            attempt += 1;
        }
        used.push(candidate.clone());
        out.push((table.clone(), candidate));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── 判据②：语句必须是客户端侧取数 ───────────────────────────────────────────────

    #[test]
    fn the_generated_statement_streams_to_the_client_and_never_names_a_server_file() {
        let sql = copy_out_statement(Some("public"), "orders", true).expect("语句");
        assert_eq!(
            sql,
            "COPY \"public\".\"orders\" TO STDOUT WITH (FORMAT csv, HEADER true)"
        );
        assert!(is_client_side(&sql));
        // ②：既不许出现服务端文件写法，也不许出现 PROGRAM
        assert!(!sql.contains("TO '"));
        assert!(!sql.to_uppercase().contains("PROGRAM"));
    }

    #[test]
    fn the_guard_itself_rejects_server_side_forms() {
        // 只判「我们生成的语句通过」的话，恒 true 的实现也会绿 ⇒ 这里反向钉死
        assert!(!is_client_side("COPY t TO '/tmp/t.csv' WITH (FORMAT csv)"));
        assert!(!is_client_side(
            "COPY t TO PROGRAM 'cat > /tmp/t.csv' WITH (FORMAT csv)"
        ));
        assert!(is_client_side("COPY t TO STDOUT"));
    }

    #[test]
    fn a_schema_less_export_goes_through_search_path() {
        let sql = copy_out_statement(None, " orders ", false).expect("语句");
        assert_eq!(sql, "COPY \"orders\" TO STDOUT WITH (FORMAT csv, HEADER false)");
        // 只有空白 schema 与没有一样处理
        let same = copy_out_statement(Some("   "), "orders", false).expect("语句");
        assert_eq!(sql, same);
    }

    #[test]
    fn a_table_name_with_a_quote_is_quoted_not_interpolated() {
        let sql = copy_out_statement(Some("s"), "we\"ird", true).expect("语句");
        assert!(sql.contains("\"we\"\"ird\""), "实际：{sql}");
        assert!(is_client_side(&sql));
    }

    #[test]
    fn an_empty_table_is_refused_with_a_readable_reason() {
        assert_eq!(
            copy_out_statement(Some("s"), "   ", true),
            Err(CopyExportError::EmptyTable)
        );
        assert_eq!(
            CopyExportError::EmptyTable.identifier(),
            "emptyTable",
            "界面靠这个标识挑文案"
        );
        assert!(CopyExportError::EmbeddedNul.message().contains("NUL"));
    }

    // ── 判据③：行数读数要引号感知 ────────────────────────────────────────────────

    #[test]
    fn records_are_counted_by_quoting_rules_not_by_newline_bytes() {
        let mut counter = RecordCounter::new();
        counter.push_str("id,name\n1,alice\n2,\"a\nb\"\n");
        // 3 条记录：表头 + 2 条数据。若按 \n 数会得到 4。
        assert_eq!(counter.records(), 3);
        assert_eq!(counter.data_rows(true), 2);
        assert_eq!(counter.data_rows(false), 3);
    }

    #[test]
    fn escaped_quotes_do_not_end_the_field() {
        let mut counter = RecordCounter::new();
        // 一个字段 = `a"b,c\nd`（引号内转义 + 逗号 + 换行），后面还有第二行
        counter.push_str("h1,h2\n\"a\"\"b,c\nd\",2\n");
        assert_eq!(counter.records(), 2);
        assert_eq!(counter.data_rows(true), 1);
    }

    #[test]
    fn a_chunk_boundary_inside_a_quote_or_an_escape_changes_nothing() {
        let whole = "id,v\n1,\"x\ny\"\n2,\"p\"\"q\"\n";
        let mut one_shot = RecordCounter::new();
        one_shot.push_str(whole);
        for cut in 1..whole.len() {
            let mut split = RecordCounter::new();
            split.push(&whole.as_bytes()[..cut]);
            split.push(&whole.as_bytes()[cut..]);
            assert_eq!(split.records(), one_shot.records(), "切点 {cut}");
        }
        assert_eq!(one_shot.records(), 3);
    }

    #[test]
    fn a_last_record_without_a_trailing_newline_still_counts() {
        let mut counter = RecordCounter::new();
        counter.push_str("a,b\n1,2");
        assert_eq!(counter.records(), 2);
        assert_eq!(counter.data_rows(true), 1);
    }

    #[test]
    fn an_empty_stream_reports_zero_data_rows_rather_than_one() {
        let counter = RecordCounter::new();
        assert_eq!(counter.records(), 0);
        assert_eq!(counter.data_rows(true), 0);
        // 只有表头（表是空的）：数据行是 0，而不是 1
        let mut header_only = RecordCounter::new();
        header_only.push_str("id,name\n");
        assert_eq!(header_only.data_rows(true), 0);
    }

    #[test]
    fn crlf_terminated_rows_are_counted_once_each() {
        let mut counter = RecordCounter::new();
        counter.push_str("a,b\r\n1,2\r\n");
        assert_eq!(counter.records(), 2);
    }

    // ── 判据：文件名的路径穿越与撞名 ────────────────────────────────────────────────

    #[test]
    fn a_table_name_can_never_escape_the_target_directory() {
        assert_eq!(table_file_name("a/b", "csv"), "a_b.csv");
        assert_eq!(table_file_name("..", "csv"), "table.csv");
        assert_eq!(table_file_name("...", "csv"), "table.csv");
        assert_eq!(table_file_name("../evil", "csv"), ".._evil.csv");
        assert_eq!(table_file_name("C:\\x", "csv"), "C__x.csv");
        assert_eq!(table_file_name("nul", "csv"), "_nul.csv");
        assert_eq!(table_file_name("CON", "csv"), "_CON.csv");
        assert_eq!(table_file_name("trailing.", "csv"), "trailing.csv");
        assert_eq!(table_file_name("  ", "csv"), "table.csv");
        assert!(table_file_name("正常表", "csv").ends_with(".csv"));
    }

    #[test]
    fn two_tables_differing_only_in_case_get_two_files_not_one() {
        let names = assign_file_names(&["Foo".to_string(), "foo".to_string(), "bar".to_string()]);
        assert_eq!(names.len(), 3);
        let files: Vec<&String> = names.iter().map(|(_, f)| f).collect();
        assert_eq!(files, vec!["bar.csv", "Foo.csv", "foo-2.csv"]);
        // 两张表都在（不丢表），且落在不同文件上
        assert!(names.iter().any(|(t, _)| t == "Foo"));
        assert!(names.iter().any(|(t, _)| t == "foo"));
    }

    #[test]
    fn the_export_order_is_stable_for_the_same_set_of_tables() {
        let a = assign_file_names(&["zeta".to_string(), "Alpha".to_string(), "beta".to_string()]);
        let b = assign_file_names(&["beta".to_string(), "zeta".to_string(), "Alpha".to_string()]);
        assert_eq!(a, b);
        assert_eq!(
            a.iter().map(|(t, _)| t.as_str()).collect::<Vec<_>>(),
            vec!["Alpha", "beta", "zeta"]
        );
    }
}
