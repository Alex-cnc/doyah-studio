//! 工作区里的**文件操作**（FR-EDIT-41 / 队列 L-114；契约等价物：macOS 侧
//! `Core/WorkspaceFileOperations.swift`）
//!
//! 四条纪律（形态由人类主人 2026-09-30 定，2026-10-02 追加「这几个问题都是 alpha2 版本冻结的，
//! 必须在 alpha2 中有」）：
//!   ① **只许工作区内** —— 目标路径与「重命名后的路径」都要过包含判定；
//!   ② **失败如实报** —— 名字非法 / 撞名 / 越界 / 系统错误四类给**结构化原因**，界面照它说话，不静默；
//!   ③ **删除走回收站** —— 「可撤销」这一条唯一的真保障，不做"直接抹掉"；
//!   ④ **展示文案不进本层** —— 默认名（中文「未命名」/ 英文 `Untitled`）由调用方从语言表给，
//!      这里只管「取一个不撞名的」。
//!
//! 本模块**不碰文件系统**：所有"存在吗""是目录吗"都走调用方给的谓词 ⇒ 纯逻辑可单测
//! （真正的 IO 在表示层 `src-tauri/src/fs.rs`，那里才调用这里给的判定）。

use std::collections::HashSet;

/// 失败的原因。每一条都对应界面上**不同的一句话**（这里只给结构，句子在界面语言表里）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind")]
pub enum Failure {
    /// 越界：不在工作区内（含符号链接指到工作区外）。
    NotContained,
    /// 名字是空的（或只有空白）。
    EmptyName,
    /// 名字非法：含分隔符 / 是 `.` / `..` / 首尾带空白（**不替用户猜要不要去掉**）。
    IllegalName { name: String },
    /// 已经有一个同名的东西了。
    AlreadyExists { name: String },
    /// 要往里建东西的那个路径不是目录。
    NotADirectory { name: String },
    /// 工作区根自己不能删（结构上挡一层）。
    RootNotDeletable,
    /// 系统给的真实原因（权限 / 文件系统 / 只读卷…）。
    System { message: String },
}

impl Failure {
    /// 供界面拼提示用的**稳定键**（文案在语言表里，这里不给句子）。
    pub const fn key(&self) -> &'static str {
        match self {
            Failure::NotContained => "fileOp.notContained",
            Failure::EmptyName => "fileOp.emptyName",
            Failure::IllegalName { .. } => "fileOp.illegalName",
            Failure::AlreadyExists { .. } => "fileOp.alreadyExists",
            Failure::NotADirectory { .. } => "fileOp.notADirectory",
            Failure::RootNotDeletable => "fileOp.rootNotDeletable",
            Failure::System { .. } => "fileOp.system",
        }
    }
}

/// 名字校验（纯函数，判据钉它）。
///
/// Windows 上的额外一条（对侧在 macOS 上遇不到）：**`\` 也是分隔符** ⇒ 一并拒掉；
/// 另外把 Windows 明令非法的那几个字符（`<>:"|?*`）以及**保留设备名**（`CON` / `PRN` / `AUX` /
/// `NUL` / `COM1..9` / `LPT1..9`）也拒掉 —— 这些名字在 macOS 上能建，在 Windows 上建不出来或
/// 建出来打不开，**提前拒掉比"建完才发现"好**。
pub fn validate_name(raw: &str) -> Option<Failure> {
    if raw.trim().is_empty() {
        return Some(Failure::EmptyName);
    }
    if raw == "." || raw == ".." {
        return Some(Failure::IllegalName { name: raw.to_string() });
    }
    if raw.starts_with(' ') || raw.ends_with(' ') || raw.starts_with('\t') || raw.ends_with('\t') {
        return Some(Failure::IllegalName { name: raw.to_string() });
    }
    if raw.chars().any(|c| matches!(c, '/' | '\\' | ':' | '<' | '>' | '"' | '|' | '?' | '*')) {
        return Some(Failure::IllegalName { name: raw.to_string() });
    }
    // 控制字符（含换行、制表）在文件名里是灾难：拒掉
    if raw.chars().any(|c| c.is_control()) {
        return Some(Failure::IllegalName { name: raw.to_string() });
    }
    let stem = raw.split('.').next().unwrap_or(raw).to_ascii_uppercase();
    let reserved = matches!(stem.as_str(), "CON" | "PRN" | "AUX" | "NUL")
        || (stem.len() == 4
            && (stem.starts_with("COM") || stem.starts_with("LPT"))
            && stem.as_bytes()[3].is_ascii_digit()
            && stem.as_bytes()[3] != b'0');
    if reserved {
        return Some(Failure::IllegalName { name: raw.to_string() });
    }
    None
}

/// 内容是否合法（不含分隔符：那是"路径"不是"名字"）。用于"重命名后用不用再判一次"。
pub fn is_valid_name(raw: &str) -> bool {
    validate_name(raw).is_none()
}

/// 「取一个不撞名的」：`base` / `base 2` / `base 3` …（带扩展名时 = `base.txt` / `base 2.txt`）。
///
/// `exists` 由调用方给（"这个名字在目标目录里存在吗"）—— **本层不碰文件系统**。
pub fn unique_name(base: &str, file_extension: Option<&str>, exists: impl Fn(&str) -> bool) -> String {
    fn composed(base: &str, index: usize, extension: Option<&str>) -> String {
        let stem = if index <= 1 { base.to_string() } else { format!("{base} {index}") };
        match extension {
            Some(ext) if !ext.is_empty() => format!("{stem}.{ext}"),
            _ => stem,
        }
    }
    let mut index = 1usize;
    while index <= 10_000 {
        let candidate = composed(base, index, file_extension);
        if !exists(&candidate) {
            return candidate;
        }
        index += 1;
    }
    composed(base, index, file_extension)
}

/// 删除前那句「将删几项」的读数。
///
/// `truncated = true` 表示**数到上限就停了** —— 界面照实写「N 项以上」，
/// 而不是为了说一句话去把十万条目录递归读完。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeletionSummary {
    pub items: usize,
    pub truncated: bool,
}

/// 数到多少就停（含目录自身）。
pub const DELETION_COUNT_LIMIT: usize = 500;

/// 由"目录自身 + 它的子项计数"算出读数（**纯逻辑**：真正的递归在表示层）。
///
/// `descendant_count` 是调用方**最多数到 `DELETION_COUNT_LIMIT`** 的结果。
pub fn deletion_summary(is_directory: bool, descendant_count: usize) -> DeletionSummary {
    if !is_directory {
        return DeletionSummary { items: 1, truncated: false };
    }
    let total = 1 + descendant_count;
    DeletionSummary {
        items: total.min(DELETION_COUNT_LIMIT),
        truncated: total >= DELETION_COUNT_LIMIT,
    }
}

/// 重命名的判定结果：**同名不改**（返回 `Same`，不算失败）—— 那是"点开改名又什么都没改"的正常结局。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RenameDecision {
    /// 新名字与原名一样（标准化之后）：什么都不做。
    Same,
    /// 可以改，目标名就是它。
    Rename(String),
    /// 不能改，原因照 `Failure`。
    Refused(Failure),
}

/// 重命名的**纯判定**：先判新名字合法、再判目标是否已存在、再判是不是"没改"。
///
/// `exists` 语义 = "**除了自己以外**，这个名字在父目录里还有别的东西吗"。
pub fn decide_rename(
    old_name: &str,
    new_name: &str,
    exists_other: impl Fn(&str) -> bool,
) -> RenameDecision {
    if let Some(failure) = validate_name(new_name) {
        return RenameDecision::Refused(failure);
    }
    if old_name == new_name {
        return RenameDecision::Same;
    }
    if exists_other(new_name) {
        return RenameDecision::Refused(Failure::AlreadyExists {
            name: new_name.to_string(),
        });
    }
    RenameDecision::Rename(new_name.to_string())
}

/// 拖拽移动的**纯判定**：不许把目录移进它自己（或它的子孙）里 —— 那是经典的自吞操作。
///
/// `relative` 用 `/` 分隔；`moving` 是源相对路径，`into` 是目标目录相对路径。
pub fn can_move_into(moving: &str, into: &str, moving_is_directory: bool) -> Result<(), Failure> {
    if !moving_is_directory {
        return Ok(());
    }
    // 移进自己的子孙（含"移进自己"）⇒ 拒绝
    if into == moving || into.starts_with(&format!("{moving}/")) {
        return Err(Failure::IllegalName { name: into.to_string() });
    }
    Ok(())
}

/// 一批名字里挑出**不重名**的那个（新建多个时用；纯函数便于单测）。
pub fn first_free_name(base: &str, taken: &HashSet<String>) -> String {
    unique_name(base, None, |candidate| taken.contains(candidate))
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── 名字校验 ──────────────────────────────────────────────────────────

    #[test]
    fn empty_and_whitespace_names_are_refused() {
        assert_eq!(validate_name(""), Some(Failure::EmptyName));
        assert_eq!(validate_name("   "), Some(Failure::EmptyName));
        assert_eq!(validate_name("\t\n"), Some(Failure::EmptyName));
        assert_eq!(Failure::EmptyName.key(), "fileOp.emptyName");
    }

    #[test]
    fn dot_and_separators_and_windows_illegal_chars_are_refused() {
        assert!(matches!(validate_name("."), Some(Failure::IllegalName { .. })));
        assert!(matches!(validate_name(".."), Some(Failure::IllegalName { .. })));
        // 两种分隔符都拒（Windows 上 `\` 也是分隔符）
        assert!(validate_name("a/b").is_some());
        assert!(validate_name("a\\b").is_some());
        assert!(validate_name("a:b").is_some());
        // Windows 明令非法的那几个
        for bad in ["a<b", "a>b", "a\"b", "a|b", "a?b", "a*b"] {
            assert!(validate_name(bad).is_some(), "{bad} 应当被拒");
        }
    }

    #[test]
    fn leading_trailing_space_and_control_chars_are_refused() {
        assert!(validate_name(" leading").is_some());
        assert!(validate_name("trailing ").is_some());
        assert!(validate_name("\ttab").is_some());
        assert!(validate_name("with\nnewline").is_some());
        // 名字**中间**有空格是正常的
        assert!(validate_name("my file.txt").is_none());
    }

    #[test]
    fn windows_reserved_device_names_are_refused_early() {
        // 这些在 macOS 上能建、在 Windows 上建不出来或打不开 ⇒ 提前拒掉更省事
        for bad in ["CON", "con", "PRN", "AUX", "NUL", "COM1", "LPT9", "nul.txt", "con.md"] {
            assert!(validate_name(bad).is_some(), "{bad} 应当被拒（Windows 保留名）");
        }
        // COM0 不是保留名；COM10 也不是（只有 1..9）
        assert!(validate_name("COM0").is_none());
        assert!(validate_name("COM10").is_none());
        // 不相关的名字不受影响
        assert!(validate_name("console.log").is_none(), "console 不是 con");
        assert!(validate_name("readme.md").is_none());
    }

    #[test]
    fn normal_names_pass() {
        for good in ["a.txt", "未命名", "my-file_v2.rs", "café.md", ".gitignore"] {
            assert!(is_valid_name(good), "{good} 应当合法");
        }
    }

    // ── 唯一名 ────────────────────────────────────────────────────────────

    #[test]
    fn unique_name_appends_a_counter_and_keeps_the_extension() {
        let taken: HashSet<String> = ["a.txt".to_string(), "a 2.txt".to_string()].into_iter().collect();
        let name = unique_name("a", Some("txt"), |candidate| taken.contains(candidate));
        assert_eq!(name, "a 3.txt");
        // 不撞名时就是 base 本身
        let free = unique_name("b", Some("txt"), |_| false);
        assert_eq!(free, "b.txt");
        // 没有扩展名
        let dir = unique_name("新建文件夹", None, |candidate| candidate == "新建文件夹");
        assert_eq!(dir, "新建文件夹 2");
    }

    #[test]
    fn unique_name_gives_up_gracefully_after_the_cap() {
        // 上限之后不再无限找：给一个（可能撞的）名字，而不是死循环
        let name = unique_name("x", None, |_| true);
        assert_eq!(name, "x 10001");
    }

    // ── 删除读数 ──────────────────────────────────────────────────────────

    #[test]
    fn deletion_summary_counts_and_truncates() {
        // 文件：就是 1
        assert_eq!(deletion_summary(false, 999), DeletionSummary { items: 1, truncated: false });
        // 目录：自身 + 内容
        assert_eq!(deletion_summary(true, 3), DeletionSummary { items: 4, truncated: false });
        // 数到上限 ⇒ 截断（界面写「N 项以上」）
        let big = deletion_summary(true, DELETION_COUNT_LIMIT);
        assert_eq!(big.items, DELETION_COUNT_LIMIT);
        assert!(big.truncated);
        // 正好差一项不算截断
        let just_under = deletion_summary(true, DELETION_COUNT_LIMIT - 2);
        assert_eq!(just_under.items, DELETION_COUNT_LIMIT - 1);
        assert!(!just_under.truncated);
    }

    // ── 重命名 ────────────────────────────────────────────────────────────

    #[test]
    fn rename_same_name_is_a_no_op_not_a_failure() {
        assert_eq!(decide_rename("a.txt", "a.txt", |_| false), RenameDecision::Same);
        // 即使磁盘上有一个同名（就是它自己），也不该报"已存在"
        assert_eq!(decide_rename("a.txt", "a.txt", |_| true), RenameDecision::Same);
    }

    #[test]
    fn rename_refuses_illegal_names_and_collisions() {
        assert!(matches!(
            decide_rename("a.txt", "b/c.txt", |_| false),
            RenameDecision::Refused(Failure::IllegalName { .. })
        ));
        assert!(matches!(
            decide_rename("a.txt", "  ", |_| false),
            RenameDecision::Refused(Failure::EmptyName)
        ));
        assert!(matches!(
            decide_rename("a.txt", "b.txt", |candidate| candidate == "b.txt"),
            RenameDecision::Refused(Failure::AlreadyExists { .. })
        ));
        assert_eq!(
            decide_rename("a.txt", "b.txt", |_| false),
            RenameDecision::Rename("b.txt".to_string())
        );
    }

    // ── 拖拽移动 ──────────────────────────────────────────────────────────

    #[test]
    fn moving_a_directory_into_itself_or_a_descendant_is_refused() {
        // 移进自己
        assert!(can_move_into("src", "src", true).is_err());
        // 移进自己的子孙
        assert!(can_move_into("src", "src/sub", true).is_err());
        // 移进别处没问题
        assert!(can_move_into("src", "other", true).is_ok());
        assert!(can_move_into("src", "", true).is_ok());
        // **文件**没有"自吞"问题（它不可能包含目录）
        assert!(can_move_into("a.txt", "a.txt", false).is_ok());
        // 前缀相似但不是子孙（`src2` 不是 `src` 的子孙）
        assert!(can_move_into("src", "src2", true).is_ok());
    }

    #[test]
    fn first_free_name_skips_taken_ones() {
        let taken: HashSet<String> = ["未命名".to_string(), "未命名 2".to_string()].into_iter().collect();
        assert_eq!(first_free_name("未命名", &taken), "未命名 3");
        assert_eq!(first_free_name("别的", &taken), "别的");
    }

    #[test]
    fn failure_keys_are_stable_and_unique() {
        let all = [
            Failure::NotContained,
            Failure::EmptyName,
            Failure::IllegalName { name: "x".into() },
            Failure::AlreadyExists { name: "x".into() },
            Failure::NotADirectory { name: "x".into() },
            Failure::RootNotDeletable,
            Failure::System { message: "x".into() },
        ];
        let keys: HashSet<&str> = all.iter().map(Failure::key).collect();
        assert_eq!(keys.len(), all.len(), "每条失败的提示键必须各不相同");
        // 序列化成 camelCase + tag，界面按 kind 分支说话
        let text = serde_json::to_string(&Failure::AlreadyExists { name: "a.txt".into() }).unwrap();
        assert!(text.contains("\"kind\":\"alreadyExists\""), "{text}");
    }
}
