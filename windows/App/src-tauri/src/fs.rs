//! 工作区的**文件系统面**（Windows 侧表示层）：列目录与读文件。
//!
//! 为什么放在表示层：真正的 IO 属平台能力（领域层保持零平台依赖、可单测）。
//! 领域层只给**判定**（`doyah_studio_db::workspace`：忽略名单 / 排序键 / 路径包含 / 相对路径解析），
//! 本文件只做"按判定去读盘"。
//!
//! 三条纪律：
//! ① **路径先过安全关**（`resolve` + `is_contained`）再读盘：相对路径可能来自缓存 / 书签 / 模型输出，
//!    **不能信**；
//! ② **符号链接只显示、不跟随**（跟随会带来环与"实际读到了工作区外面"两个问题）；
//! ③ 失败**给人话**（路径不存在 / 不是目录 / 文件太大，各给各的）。

use std::path::{Path, PathBuf};

use doyah_studio_db::workspace::{
    entry_kind, relative_path, resolve, should_list, sort_key, EntryKind, DEFAULT_IGNORED,
};

use crate::postgres::DbFailure;

/// 单个文件最多读多少字节（超过就不读全文，**如实说**，不悄悄截断）。
pub const MAX_TEXT_FILE_BYTES: u64 = 8 * 1024 * 1024;

/// 目录里的一个条目（IPC 面）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FsEntry {
    pub name: String,
    /// 相对工作区根的路径，**一律 `/` 分隔**（跨平台一致，也当 id 用）。
    pub relative_path: String,
    /// `directory` / `file` / `symlink`
    pub kind: &'static str,
    pub is_expandable: bool,
}

fn kind_name(kind: EntryKind) -> &'static str {
    match kind {
        EntryKind::Directory => "directory",
        EntryKind::File => "file",
        EntryKind::Symlink => "symlink",
    }
}

fn failure(message: String, hint: &str) -> DbFailure {
    DbFailure {
        message,
        hint: hint.to_string(),
    }
}

/// 列一层目录（**不递归**：展开才读下一层，避免打开大工程时卡住界面）。
///
/// 排序 = 目录在前、文件在后，同类按名称不区分大小写（与访达 / VS Code 一致）。
pub fn list_directory(
    workspace_root: &str,
    relative: &str,
    show_hidden: bool,
) -> Result<Vec<FsEntry>, DbFailure> {
    // 相对路径为空 = 工作区根本身（不是"非法输入"）
    let directory: PathBuf = if relative.trim().is_empty() {
        PathBuf::from(workspace_root)
    } else {
        resolve(relative, workspace_root).ok_or_else(|| {
            failure(
                format!("拒绝越界路径：{relative}"),
                "该路径不在当前工作区内（`..` 逃逸或指向别处）。",
            )
        })?
        .into()
    };

    if !directory.exists() {
        return Err(failure(
            format!("目录不存在：{}", directory.display()),
            "确认工作区是否还在原处（可能被移动或删除）。",
        ));
    }
    if !directory.is_dir() {
        return Err(failure(
            format!("不是目录：{}", directory.display()),
            "这一层要列的是目录；文件请用「打开文件」。",
        ));
    }

    let read_dir = std::fs::read_dir(&directory).map_err(|e| {
        failure(
            format!("列目录失败：{e}（{}）", directory.display()),
            "确认当前用户对该目录有读取权限。",
        )
    })?;

    let mut entries: Vec<FsEntry> = Vec::new();
    for item in read_dir.flatten() {
        let name = item.file_name().to_string_lossy().to_string();
        if !should_list(&name, show_hidden, DEFAULT_IGNORED) {
            continue;
        }
        let path = item.path();
        // `symlink_metadata` 不跟随链接 ⇒ 符号链接能认出来（`metadata` 会跟过去）
        let Ok(meta) = std::fs::symlink_metadata(&path) else { continue };
        let is_symlink = meta.file_type().is_symlink();
        let is_dir = if is_symlink {
            false // 链接的"是不是目录"我们不用（反正不展开）
        } else {
            meta.is_dir()
        };
        let kind = entry_kind(is_symlink, is_dir);
        let relative_path = relative_path(&path.to_string_lossy(), workspace_root)
            .unwrap_or_else(|| name.clone());
        entries.push(FsEntry {
            name,
            relative_path,
            kind: kind_name(kind),
            is_expandable: kind.is_expandable(),
        });
    }

    entries.sort_by_key(|entry| {
        let kind = match entry.kind {
            "directory" => EntryKind::Directory,
            "symlink" => EntryKind::Symlink,
            _ => EntryKind::File,
        };
        sort_key(&entry.name, kind)
    });
    Ok(entries)
}

/// 读一个文本文件（**先过安全关**；超过上限如实报，不悄悄截断）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FileContent {
    pub relative_path: String,
    pub content: String,
    pub bytes: u64,
    /// 语言键（界面按语言表取文案）
    pub language_key: &'static str,
}

pub fn read_text_file(workspace_root: &str, relative: &str) -> Result<FileContent, DbFailure> {
    let full = resolve(relative, workspace_root).ok_or_else(|| {
        failure(
            format!("拒绝越界路径：{relative}"),
            "该路径不在当前工作区内（`..` 逃逸或指向别处）。",
        )
    })?;
    let path = Path::new(&full);
    let meta = std::fs::metadata(path).map_err(|e| {
        failure(
            format!("读文件失败：{e}（{full}）"),
            "确认文件还在、且当前用户有读取权限。",
        )
    })?;
    if meta.is_dir() {
        return Err(failure(
            format!("这是一个目录：{full}"),
            "目录不能当文件打开；请展开它再选里面的文件。",
        ));
    }
    if meta.len() > MAX_TEXT_FILE_BYTES {
        return Err(failure(
            format!(
                "文件太大，本版不读：{} 字节（上限 {} 字节）",
                meta.len(),
                MAX_TEXT_FILE_BYTES
            ),
            "本版只读文本文件；超大文件请用别的工具处理（**不悄悄截断**）。",
        ));
    }
    let content = std::fs::read_to_string(path).map_err(|e| {
        failure(
            format!("按文本读失败：{e}（{full}）"),
            "文件可能不是 UTF-8 文本（本版不做编码识别，不猜）。",
        )
    })?;
    let language = doyah_studio_db::workspace::TextLanguage::detect(&full);
    Ok(FileContent {
        relative_path: relative.replace('\\', "/"),
        bytes: meta.len(),
        content,
        language_key: language.key(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    // 夹具根目录：**不用系统临时区**（cargo test 拿不到会话里的 TEMP，系统临时区在本机沙箱里
// 拒写 ⇒ 建夹具报“拒绝访问”，看着像权限问题、其实是写错了地方）。可用环境变量覆盖。
fn fixture_root() -> std::path::PathBuf {
    match std::env::var("DOYAH_TEST_ROOT") {
        Ok(value) if !value.trim().is_empty() => std::path::PathBuf::from(value),
        _ => std::path::PathBuf::from("D:/AIProjects/_tmp_face2/fish-fixtures"),
    }
}

    fn temp_root(tag: &str) -> PathBuf {
        let dir = fixture_root().join(format!("doyah-fs-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("sub")).unwrap();
        std::fs::write(dir.join("a.txt"), "hello").unwrap();
        std::fs::write(dir.join("sub/b.rs"), "fn main() {}").unwrap();
        std::fs::write(dir.join(".hidden"), "h").unwrap();
        std::fs::create_dir_all(dir.join("node_modules")).unwrap();
        dir
    }

    #[test]
    fn lists_a_directory_with_ignores_and_directories_first() {
        let root = temp_root("list");
        let root_text = root.to_string_lossy().to_string();
        let entries = list_directory(&root_text, "", false).unwrap();
        let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
        assert!(names.contains(&"a.txt"));
        assert!(names.contains(&"sub"));
        assert!(!names.contains(&"node_modules"), "忽略名单里的目录不列");
        assert!(!names.contains(&".hidden"), "隐藏项默认不列");
        // 目录在前
        assert_eq!(entries[0].name, "sub");
        assert!(entries[0].is_expandable);
        // 相对路径是相对**工作区根**算的（不是相对被列出的那一层）
        let sub = entries.iter().find(|e| e.name == "sub").unwrap();
        assert_eq!(sub.relative_path, "sub");
        let a = entries.iter().find(|e| e.name == "a.txt").unwrap();
        assert_eq!(a.relative_path, "a.txt");
        // 开隐藏后能看到 .hidden
        let entries = list_directory(&root_text, "", true).unwrap();
        assert!(entries.iter().any(|e| e.name == ".hidden"));
        // 子目录里的相对路径带前缀
        let sub_entries = list_directory(&root_text, "sub", false).unwrap();
        assert_eq!(sub_entries[0].relative_path, "sub/b.rs");
    }

    #[test]
    fn reads_a_text_file_and_reports_language() {
        let root = temp_root("read");
        let root_text = root.to_string_lossy().to_string();
        let file = read_text_file(&root_text, "sub/b.rs").unwrap();
        assert_eq!(file.content, "fn main() {}");
        assert_eq!(file.relative_path, "sub/b.rs");
        assert!(file.language_key.contains("rust"), "{}", file.language_key);
        assert_eq!(file.bytes, 12);
        // 反斜杠写法也认
        let back = read_text_file(&root_text, "sub\\b.rs").unwrap();
        assert_eq!(back.content, file.content);
    }

    #[test]
    fn refuses_escapes_and_says_why() {
        let root = temp_root("escape");
        let root_text = root.to_string_lossy().to_string();
        let err = read_text_file(&root_text, "../../etc/passwd").unwrap_err();
        assert!(err.message.contains("拒绝越界"), "{}", err.message);
        assert!(!err.hint.is_empty());
        let err = list_directory(&root_text, "../..", false).unwrap_err();
        assert!(err.message.contains("拒绝越界"), "{}", err.message);
    }

    #[test]
    fn directory_read_as_file_and_missing_paths_give_human_reasons() {
        let root = temp_root("errors");
        let root_text = root.to_string_lossy().to_string();
        let err = read_text_file(&root_text, "sub").unwrap_err();
        assert!(err.message.contains("是一个目录"), "{}", err.message);
        let err = read_text_file(&root_text, "nope.txt").unwrap_err();
        assert!(err.message.contains("读文件失败"), "{}", err.message);
        let err = list_directory(&root_text, "nope", false).unwrap_err();
        assert!(err.message.contains("目录不存在"), "{}", err.message);
        let err = list_directory(&root_text, "a.txt", false).unwrap_err();
        assert!(err.message.contains("不是目录"), "{}", err.message);
    }
}

// ── 「最近打开」与会话恢复的落盘（FR-EDIT-35 的 Home 页数据 + 2.0 会话恢复）──────────────
//
// 与工程里其它偏好文件同一套路（对侧 `WorkspaceHistoryStore` 同口径）：**一个 JSON、按需读写、
// 坏了不致命** —— 读失败返回**空历史**而不是抛错（一份"最近打开"坏掉，不该让工作区打不开），
// 但要把"为什么空"**说出来**，不静默吞掉。

/// 历史文件的默认落点：`%APPDATA%\DoyahStudio\workspace-history.json`。
pub fn history_path() -> std::path::PathBuf {
    let base = std::env::var("APPDATA").unwrap_or_else(|_| ".".to_string());
    std::path::Path::new(&base).join("DoyahStudio").join("workspace-history.json")
}

/// 读历史：**文件不存在 = 空历史**；文件坏了 = 空历史 + 一句可读的原因（不抛）。
///
/// 返回 `(history, warning)`：`warning` 非空表示"这次是空的，因为读不出来"。
pub fn read_history() -> (doyah_studio_db::workspace::History, Option<String>) {
    let path = history_path();
    if !path.exists() {
        return (doyah_studio_db::workspace::History::default(), None);
    }
    match std::fs::read_to_string(&path) {
        Ok(text) if text.trim().is_empty() => (doyah_studio_db::workspace::History::default(), None),
        Ok(text) => match serde_json::from_str::<doyah_studio_db::workspace::History>(&text) {
            Ok(history) => (history, None),
            Err(e) => (
                doyah_studio_db::workspace::History::default(),
                Some(format!("最近打开记录读不出来（{e}）—— 已按空记录继续，原文件未改动：{}", path.display())),
            ),
        },
        Err(e) => (
            doyah_studio_db::workspace::History::default(),
            Some(format!("最近打开记录打不开（{e}）：{}", path.display())),
        ),
    }
}

/// 写历史（**整份覆盖**：这份记录就是唯一事实源，不做增量合并）。
pub fn write_history(history: &doyah_studio_db::workspace::History) -> Result<(), DbFailure> {
    let path = history_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| {
            failure(format!("建配置目录失败：{e}（{}）", parent.display()), "确认该目录可写。")
        })?;
    }
    let text = serde_json::to_string_pretty(history).map_err(|e| {
        failure(format!("历史序列化失败：{e}"), "这属实现缺陷：请保留现场并报告。")
    })?;
    std::fs::write(&path, text).map_err(|e| {
        failure(
            format!("写最近打开记录失败：{e}（{}）", path.display()),
            "确认该文件可写（可能被杀毒软件 / 权限限制）。",
        )
    })
}

// ── 写面（alpha 2.1）：新建 / 重命名 / 删除（**走回收站**）/ 拖拽移动 ─────────────────────
//
// 纪律（与领域层 `file_ops` 的分工）：**判定**在领域层（名字校验 / 唯一名 / 同名不改 / 自吞拦截），
// **IO** 在这里；越界判定**两遍都过** —— 字符串路径（挡 `..`）与**解开符号链接后的真实路径**
// （挡"链接指到工作区外"那一步字符串判定拦不住的情况）。

/// 把路径规范化成本侧内部形态，并**剥掉 Windows 的 `\\?\` 前缀**（`canonicalize` 会加上它，
/// 留着会让后续的包含判定把同一处在字面上当成两条不同路径）。
fn canonical(path: &Path) -> Option<String> {
    let resolved = std::fs::canonicalize(path).ok()?;
    let text = resolved.to_string_lossy().to_string();
    Some(match text.strip_prefix(r"\\?\") {
        Some(rest) => rest.to_string(),
        None => text,
    })
}

/// 越界判定：**两遍都要过**（字符串路径 + 解开符号链接后的真实路径）。
fn require_contained(candidate: &Path, workspace_root: &str) -> Result<(), DbFailure> {
    let raw = candidate.to_string_lossy().to_string();
    if !doyah_studio_db::workspace::is_contained(&raw, workspace_root) {
        return Err(not_contained(&raw));
    }
    // 已经存在的东西：解链接之后再判一次（不存在就没法解，跳过第二遍）
    if candidate.exists() {
        if let Some(resolved) = canonical(candidate) {
            if !doyah_studio_db::workspace::is_contained(&resolved, workspace_root) {
                return Err(failure(
                    format!("拒绝越界：{raw} 通过符号链接指到了工作区外（{resolved}）"),
                    "工作区内的链接不能把操作带到工作区外面去。",
                ));
            }
        }
    }
    Ok(())
}

fn not_contained(path: &str) -> DbFailure {
    failure(
        format!("拒绝越界路径：{path}"),
        "该路径不在当前工作区内（`..` 逃逸、链接指向别处、或换了盘符）。",
    )
}

fn file_op_failure(op: &doyah_studio_db::FileOpFailure) -> DbFailure {
    // 提示文案按**稳定键**给一句人话（界面另有语言表；这里给的是命令层兜底句）
    let hint = match op {
        doyah_studio_db::FileOpFailure::NotContained => "只能在当前工作区内操作。",
        doyah_studio_db::FileOpFailure::EmptyName => "名字不能是空的。",
        doyah_studio_db::FileOpFailure::IllegalName { .. } => {
            "名字里不能有 / \\ : < > \" | ? *，也不能是 . / .. / Windows 保留名（CON / NUL / COM1…），首尾不能是空白。"
        }
        doyah_studio_db::FileOpFailure::AlreadyExists { .. } => "同名已经存在，换个名字。",
        doyah_studio_db::FileOpFailure::NotADirectory { .. } => "要往里放东西的那个位置不是文件夹。",
        doyah_studio_db::FileOpFailure::RootNotDeletable => "工作区根不能删。",
        doyah_studio_db::FileOpFailure::System { .. } => "系统给的错误原话见上；确认权限与磁盘状态。",
    };
    failure(format!("{:?}", op), hint)
}

/// 解析一个相对路径，**并确认落在工作区内**。
fn resolve_in(workspace_root: &str, relative: &str) -> Result<PathBuf, DbFailure> {
    let full = doyah_studio_db::workspace::resolve(relative, workspace_root)
        .ok_or_else(|| not_contained(relative))?;
    let path = PathBuf::from(&full);
    require_contained(&path, workspace_root)?;
    Ok(path)
}

/// 新建文件 / 文件夹（名字由领域层取**不撞名的**那个）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CreatedEntry {
    pub relative_path: String,
    pub name: String,
    pub kind: &'static str,
}

pub fn create_entry(
    workspace_root: &str,
    parent_relative: &str,
    base_name: &str,
    extension: Option<&str>,
    directory: bool,
) -> Result<CreatedEntry, DbFailure> {
    let parent = if parent_relative.trim().is_empty() {
        let root = PathBuf::from(workspace_root);
        require_contained(&root, workspace_root)?;
        root
    } else {
        resolve_in(workspace_root, parent_relative)?
    };
    if !parent.is_dir() {
        return Err(file_op_failure(&doyah_studio_db::FileOpFailure::NotADirectory {
            name: parent_relative.to_string(),
        }));
    }
    let name = doyah_studio_db::unique_name(base_name, extension, |candidate| {
        parent.join(candidate).exists()
    });
    if let Some(bad) = doyah_studio_db::validate_name(&name) {
        return Err(file_op_failure(&bad));
    }
    let target = parent.join(&name);
    require_contained(&target, workspace_root)?;
    let created = if directory {
        std::fs::create_dir(&target)
    } else {
        std::fs::OpenOptions::new()
            .write(true)
            .create_new(true) // **不覆盖**同名（唯一名之后再兜一层）
            .open(&target)
            .map(|_| ())
    };
    created.map_err(|e| {
        failure(
            format!("新建失败：{e}（{}）", target.display()),
            "确认目标目录可写、且磁盘没满。",
        )
    })?;
    Ok(CreatedEntry {
        relative_path: relative_path(&target.to_string_lossy(), workspace_root).unwrap_or(name.clone()),
        name,
        kind: if directory { "directory" } else { "file" },
    })
}

/// 重命名（**同名不改**，不算失败）。
pub fn rename_entry(workspace_root: &str, relative: &str, new_name: &str) -> Result<CreatedEntry, DbFailure> {
    let source = resolve_in(workspace_root, relative)?;
    require_contained(&source, workspace_root)?;
    let old_name = source
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();
    let parent = source.parent().map(Path::to_path_buf).unwrap_or_else(|| PathBuf::from(workspace_root));

    let decision = doyah_studio_db::decide_rename(&old_name, new_name, |candidate| {
        let candidate_path = parent.join(candidate);
        candidate_path.exists() && candidate != old_name
    });
    match decision {
        doyah_studio_db::RenameDecision::Same => Ok(CreatedEntry {
            relative_path: relative.replace('\\', "/"),
            name: old_name,
            kind: if source.is_dir() { "directory" } else { "file" },
        }),
        doyah_studio_db::RenameDecision::Refused(reason) => Err(file_op_failure(&reason)),
        doyah_studio_db::RenameDecision::Rename(name) => {
            let target = parent.join(&name);
            require_contained(&target, workspace_root)?;
            std::fs::rename(&source, &target).map_err(|e| {
                failure(
                    format!("重命名失败：{e}（{} → {}）", source.display(), target.display()),
                    "确认源还在、目标没被占用（可能有程序正打开它）。",
                )
            })?;
            Ok(CreatedEntry {
                relative_path: relative_path(&target.to_string_lossy(), workspace_root)
                    .unwrap_or(name.clone()),
                name,
                kind: if target.is_dir() { "directory" } else { "file" },
            })
        }
    }
}

/// 拖拽移动：把 `relative` 移进目录 `into_relative`（同级同处 = 什么都不做）。
pub fn move_entry(
    workspace_root: &str,
    relative: &str,
    into_relative: &str,
) -> Result<CreatedEntry, DbFailure> {
    let source = resolve_in(workspace_root, relative)?;
    let into = if into_relative.trim().is_empty() {
        PathBuf::from(workspace_root)
    } else {
        resolve_in(workspace_root, into_relative)?
    };
    if !into.is_dir() {
        return Err(file_op_failure(&doyah_studio_db::FileOpFailure::NotADirectory {
            name: into_relative.to_string(),
        }));
    }
    // **不许把目录移进它自己或它的子孙**（经典的自吞操作）
    let file_name = source
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();
    doyah_studio_db::can_move_into(relative, into_relative, source.is_dir()).map_err(|e| file_op_failure(&e))?;

    let target = into.join(&file_name);
    require_contained(&target, workspace_root)?;
    if target == source {
        return Ok(CreatedEntry {
            relative_path: relative.replace('\\', "/"),
            name: file_name,
            kind: if source.is_dir() { "directory" } else { "file" },
        });
    }
    if target.exists() {
        return Err(file_op_failure(&doyah_studio_db::FileOpFailure::AlreadyExists {
            name: file_name,
        }));
    }
    std::fs::rename(&source, &target).map_err(|e| {
        failure(
            format!("移动失败：{e}（{} → {}）", source.display(), target.display()),
            "跨盘符移动不受支持（先复制再删）；确认目标可写。",
        )
    })?;
    Ok(CreatedEntry {
        relative_path: relative_path(&target.to_string_lossy(), workspace_root)
            .unwrap_or(file_name.clone()),
        name: file_name,
        kind: if target.is_dir() { "directory" } else { "file" },
    })
}

/// 「将删几项」：目录 = 自身 + 递归内容（**数到上限就停并标截断**）；文件 = 1。
pub fn deletion_summary(workspace_root: &str, relative: &str) -> Result<doyah_studio_db::DeletionSummary, DbFailure> {
    let path = resolve_in(workspace_root, relative)?;
    if !path.is_dir() {
        return Ok(doyah_studio_db::deletion_summary(false, 0));
    }
    // 广度优先数，数到上限就停 —— 不为了一句提示去把十万条目录读完
    let limit = doyah_studio_db::DELETION_COUNT_LIMIT;
    let mut count = 0usize;
    let mut queue = vec![path.clone()];
    while let Some(current) = queue.pop() {
        let Ok(read) = std::fs::read_dir(&current) else { continue };
        for item in read.flatten() {
            count += 1;
            if count >= limit {
                return Ok(doyah_studio_db::deletion_summary(true, count));
            }
            if item.path().is_dir() {
                queue.push(item.path());
            }
        }
    }
    Ok(doyah_studio_db::deletion_summary(true, count))
}

/// 删除：**走回收站**（可撤销是唯一的真保障）。
///
/// 做法 = 调 Windows 自带的 `Microsoft.VisualBasic.FileIO.FileSystem`（它的 `RecycleBin` 档
/// 就是这个语义）—— 比自己写 Shell API 的 P/Invoke 更不容易出错，且**不需要为删一个文件引入依赖**。
/// 删完**回读确认**：文件还在就如实报失败，不谎报成功。
pub fn delete_entry(workspace_root: &str, relative: &str) -> Result<String, DbFailure> {
    let path = resolve_in(workspace_root, relative)?;
    let root = canonical(Path::new(workspace_root));
    if let Some(root) = root {
        if let Some(target) = canonical(&path) {
            if target.eq_ignore_ascii_case(&root) {
                return Err(file_op_failure(&doyah_studio_db::FileOpFailure::RootNotDeletable));
            }
        }
    }
    if !path.exists() {
        return Err(failure(
            format!("要删的东西不在了：{}", path.display()),
            "可能已经被别的程序删掉；刷新一下树。",
        ));
    }

    let is_dir = path.is_dir();
    let literal = path.to_string_lossy().replace('\'', "''");
    let script = if is_dir {
        format!(
            "Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory('{literal}', 'OnlyErrorDialogs', 'SendToRecycleBin')"
        )
    } else {
        format!(
            "Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('{literal}', 'OnlyErrorDialogs', 'SendToRecycleBin')"
        )
    };

    let mut command = std::process::Command::new("powershell");
    command
        .arg("-NoProfile")
        .arg("-NonInteractive")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-Command")
        .arg(&script);
    // 让子进程的编码与父进程对得上（GBK 输出会让错误原话变成乱码）
    command.env("PYTHONUTF8", "1");
    let output = command.output().map_err(|e| {
        failure(
            format!("调系统回收站失败：{e}"),
            "确认 PowerShell 可用（系统自带的那个）。",
        )
    })?;

    if path.exists() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(failure(
            format!(
                "删除没有生效（文件还在）：{}{}",
                path.display(),
                if stderr.is_empty() { String::new() } else { format!("；系统原话：{stderr}") }
            ),
            "**没有**改成永久删除 —— 宁可报失败也不悄悄抹掉；确认文件没被占用、回收站可用。",
        ));
    }
    Ok(if is_dir { "directory" } else { "file" }.to_string())
}

#[cfg(test)]
mod write_tests {
    use super::*;

    // ── 写面（alpha 2.1）：真建 / 真改 / 真移动 / 真删（回收站）──────────────────────────

    // 夹具根目录：**不用系统临时区**（cargo test 拿不到会话里的 TEMP，系统临时区在本机沙箱里
// 拒写 ⇒ 建夹具报“拒绝访问”，看着像权限问题、其实是写错了地方）。可用环境变量覆盖。
fn fixture_root() -> std::path::PathBuf {
    match std::env::var("DOYAH_TEST_ROOT") {
        Ok(value) if !value.trim().is_empty() => std::path::PathBuf::from(value),
        _ => std::path::PathBuf::from("D:/AIProjects/_tmp_face2/fish-fixtures"),
    }
}

    fn write_root(tag: &str) -> PathBuf {
        let dir = fixture_root().join(format!("doyah-write-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("sub")).unwrap();
        dir
    }

    #[test]
    fn creates_files_and_directories_with_a_free_name() {
        let root = write_root("create");
        let root_text = root.to_string_lossy().to_string();
        let created = create_entry(&root_text, "", "未命名", None, false).unwrap();
        assert_eq!(created.name, "未命名");
        assert_eq!(created.kind, "file");
        assert!(root.join("未命名").exists());
        // 再来一个 ⇒ 同名之后自动取「未命名 2」（**不覆盖**）
        let second = create_entry(&root_text, "", "未命名", None, false).unwrap();
        assert_eq!(second.name, "未命名 2");
        assert!(root.join("未命名").exists() && root.join("未命名 2").exists());
        // 带扩展名 + 在子目录里建
        let in_sub = create_entry(&root_text, "sub", "new", Some("rs"), false).unwrap();
        assert_eq!(in_sub.name, "new.rs");
        assert_eq!(in_sub.relative_path, "sub/new.rs");
        // 建文件夹
        let dir = create_entry(&root_text, "", "新文件夹", None, true).unwrap();
        assert_eq!(dir.kind, "directory");
        assert!(root.join("新文件夹").is_dir());
        // 父路径不是目录 ⇒ 给人话
        let err = create_entry(&root_text, "未命名", "x", None, false).unwrap_err();
        assert!(err.message.contains("NotADirectory"), "{}", err.message);
    }

    #[test]
    fn rename_refuses_collisions_and_treats_same_name_as_noop() {
        let root = write_root("rename");
        let root_text = root.to_string_lossy().to_string();
        std::fs::write(root.join("a.txt"), "a").unwrap();
        std::fs::write(root.join("b.txt"), "b").unwrap();

        // 同名 ⇒ 不算失败、不报"已存在"
        let same = rename_entry(&root_text, "a.txt", "a.txt").unwrap();
        assert_eq!(same.name, "a.txt");
        assert!(root.join("a.txt").exists());

        // 撞名 ⇒ 明确拒绝，且**原文件没被动**
        let err = rename_entry(&root_text, "a.txt", "b.txt").unwrap_err();
        assert!(err.message.contains("AlreadyExists"), "{}", err.message);
        assert_eq!(std::fs::read_to_string(root.join("a.txt")).unwrap(), "a");

        // 非法名字 ⇒ 拒绝
        let err = rename_entry(&root_text, "a.txt", "x/y.txt").unwrap_err();
        assert!(err.message.contains("IllegalName"), "{}", err.message);

        // 正常改名
        let done = rename_entry(&root_text, "a.txt", "c.txt").unwrap();
        assert_eq!(done.name, "c.txt");
        assert!(!root.join("a.txt").exists() && root.join("c.txt").exists());
    }

    #[test]
    fn move_refuses_swallowing_a_directory_into_itself() {
        let root = write_root("move");
        let root_text = root.to_string_lossy().to_string();
        std::fs::create_dir_all(root.join("sub/deep")).unwrap();
        std::fs::write(root.join("sub/deep/x.txt"), "x").unwrap();

        // 移进自己 / 移进自己的子孙 ⇒ 拒绝（经典自吞）
        assert!(move_entry(&root_text, "sub", "sub").is_err());
        assert!(move_entry(&root_text, "sub", "sub/deep").is_err());
        assert!(root.join("sub/deep/x.txt").exists(), "拒绝之后一个字节都不该动");

        // 正常移动：把 deep 移到 sub 下（已经在，等同不动）→ 目标不存在时才真移
        std::fs::create_dir_all(root.join("other")).unwrap();
        let moved = move_entry(&root_text, "sub/deep", "other").unwrap();
        assert_eq!(moved.relative_path, "other/deep");
        assert!(root.join("other/deep/x.txt").exists());
        assert!(!root.join("sub/deep").exists());
        // 移进不存在的位置 ⇒ 给人话
        assert!(move_entry(&root_text, "other/deep", "nope").is_err());
    }

    #[test]
    fn deletion_summary_counts_children_and_reports_truncation() {
        let root = write_root("summary");
        let root_text = root.to_string_lossy().to_string();
        std::fs::write(root.join("one.txt"), "1").unwrap();
        // 文件 = 1 项
        assert_eq!(deletion_summary(&root_text, "one.txt").unwrap().items, 1);
        // 目录 = 自身 + 内容
        std::fs::create_dir_all(root.join("pack/inner")).unwrap();
        std::fs::write(root.join("pack/a.txt"), "a").unwrap();
        std::fs::write(root.join("pack/inner/b.txt"), "b").unwrap();
        let summary = deletion_summary(&root_text, "pack").unwrap();
        assert_eq!(summary.items, 4, "pack + inner + a.txt + b.txt");
        assert!(!summary.truncated);
    }

    #[test]
    fn delete_moves_to_the_recycle_bin_and_refuses_the_root() {
        let root = write_root("delete");
        let root_text = root.to_string_lossy().to_string();
        std::fs::write(root.join("bye.txt"), "bye").unwrap();

        // **工作区根不能删**
        let err = delete_entry(&root_text, "").unwrap_err();
        assert!(!err.message.is_empty());

        // 真删：文件不见（进回收站 —— 本用例只能证"不在原地"，回收站位置由系统管）
        delete_entry(&root_text, "bye.txt").unwrap();
        assert!(!root.join("bye.txt").exists(), "删完不该还在原地");

        // 目录也能删（走同一个回收站口径）
        std::fs::create_dir_all(root.join("tmpdir")).unwrap();
        std::fs::write(root.join("tmpdir/inside.txt"), "x").unwrap();
        delete_entry(&root_text, "tmpdir").unwrap();
        assert!(!root.join("tmpdir").exists());

        // 已经不在了 ⇒ 如实报，不谎报成功
        let err = delete_entry(&root_text, "bye.txt").unwrap_err();
        assert!(err.message.contains("不在了"), "{}", err.message);
    }

    #[test]
    fn write_side_refuses_escapes() {
        let root = write_root("write-escape");
        let root_text = root.to_string_lossy().to_string();
        assert!(create_entry(&root_text, "../..", "x", None, false).is_err());
        assert!(rename_entry(&root_text, "../outside.txt", "y.txt").is_err());
        assert!(delete_entry(&root_text, "../outside.txt").is_err());
        assert!(move_entry(&root_text, "../outside.txt", "").is_err());
    }
}

// ── 在资源管理器 / 终端打开（2.1）──────────────────────────────────────────────────
//
// 判定在领域层 `reveal`（选哪个程序 / 文件要定位 / 路径必须在内），本层只负责**真启动**。
// 启动**不等进程**（explorer 会把已有窗口提到前面然后立刻返回，等它反而会卡住界面）。

/// 某个程序在不在 PATH 上（用系统自带的 `where.exe`，退出码 0 = 在）。
fn program_available(program: &str) -> bool {
    std::process::Command::new("where.exe")
        .arg(program)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

/// 在资源管理器里定位（文件选中 / 目录进入）；`terminal = true` 则改为在终端打开。
pub fn reveal_entry(workspace_root: &str, relative: &str, terminal: bool) -> Result<doyah_studio_db::RevealPlan, DbFailure> {
    let path = resolve_in(workspace_root, relative)?;
    // 链接不跟随：用 `symlink_metadata` 判类型（`is_dir` 会跟过去）
    let meta = std::fs::symlink_metadata(&path).map_err(|e| {
        failure(
            format!("看不到这个条目：{e}（{}）", path.display()),
            "它可能被移动或删除了；刷新一下树。",
        )
    })?;
    let is_directory = meta.is_dir() && !meta.file_type().is_symlink();
    let full = path.to_string_lossy().to_string();
    let parent = path
        .parent()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|| workspace_root.to_string());

    let plan = if terminal {
        doyah_studio_db::terminal_plan(is_directory, &full, &parent, program_available).map_err(|tried| {
            failure(
                format!("这台机器上没找到终端程序（试过：{}）", tried.join(" / ")),
                "装了 Windows Terminal / PowerShell 之后再来（**不硬起一个不存在的程序**）。",
            )
        })?
    } else {
        doyah_studio_db::explorer_plan(is_directory, &full)
    };

    let mut command = std::process::Command::new(&plan.program);
    command.args(&plan.args);
    if let Some(directory) = &plan.working_directory {
        command.current_dir(directory);
    }
    command
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());
    command.spawn().map_err(|e| {
        failure(
            format!("启动失败：{e}（{}）", plan.program),
            "确认该程序可用（PATH 里能找到）。",
        )
    })?;
    Ok(plan)
}

#[cfg(test)]
mod reveal_tests {
    use super::*;

    /// 本模块自备临时根（跨模块共享私有测试助手不值当：两处各六行，比"公开一个只为测试存在的
    /// 函数"更干净）。
    // 夹具根目录：**不用系统临时区**（cargo test 拿不到会话里的 TEMP，系统临时区在本机沙箱里
// 拒写 ⇒ 建夹具报“拒绝访问”，看着像权限问题、其实是写错了地方）。可用环境变量覆盖。
fn fixture_root() -> std::path::PathBuf {
    match std::env::var("DOYAH_TEST_ROOT") {
        Ok(value) if !value.trim().is_empty() => std::path::PathBuf::from(value),
        _ => std::path::PathBuf::from("D:/AIProjects/_tmp_face2/fish-fixtures"),
    }
}

    fn write_root(tag: &str) -> PathBuf {
        let dir = fixture_root().join(format!("doyah-reveal-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn reveal_refuses_escapes_before_touching_anything() {
        let root = write_root("reveal");
        let root_text = root.to_string_lossy().to_string();
        std::fs::write(root.join("a.txt"), "a").unwrap();
        assert!(reveal_entry(&root_text, "../outside.txt", false).is_err());
        assert!(reveal_entry(&root_text, "nope.txt", false).is_err(), "不存在的条目要给人话");
    }

    #[test]
    fn reveal_plan_for_a_file_locates_it_and_for_a_directory_opens_it() {
        let root = write_root("reveal-plan");
        let root_text = root.to_string_lossy().to_string();
        std::fs::write(root.join("a.txt"), "a").unwrap();
        // 这里**只验计划**（真启动会弹窗口，不做）—— 用领域层的纯函数按同一入参算一遍
        let file_plan = doyah_studio_db::explorer_plan(false, &format!("{root_text}/a.txt"));
        assert!(file_plan.args[0].starts_with("/select,"), "文件要定位");
        let dir_plan = doyah_studio_db::explorer_plan(true, &root_text);
        assert!(!dir_plan.args[0].starts_with("/select,"), "目录直接进去");
        // 终端：这台机器上至少要有一个（Windows 自带 PowerShell 与 cmd）
        let found = doyah_studio_db::pick_terminal(program_available);
        assert!(found.is_some(), "Windows 上应当至少能找到 PowerShell 或 cmd");
    }
}

// ── 编辑面：行结构 + 高亮（2.2）──────────────────────────────────────────────────
//
// 读一个文件的**行结构**：行内容 / 每行的终止符 / 行号列宽 / 主换行符 / 是否混排。
// 判定全在领域层（`code_lines`）—— 这里只把文件读出来喂给它。

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FileLines {
    pub relative_path: String,
    pub lines: Vec<doyah_studio_db::Line>,
    /// 行号列要留几位（`99 → 2` / `10000 → 5`；写死宽度会在第 100 行处挤掉数字）
    pub gutter_digits: usize,
    /// 主换行符（`None` = 单行文件，无从判断）
    pub dominant_ending: Option<doyah_studio_db::LineEnding>,
    /// **混排**（同时有两种以上终止符）⇒ 界面要如实说，别偷偷统一
    pub mixed_endings: bool,
    /// 语言键（高亮按它取语法）
    pub language_key: &'static str,
}

pub fn read_lines(workspace_root: &str, relative: &str) -> Result<FileLines, DbFailure> {
    let file = read_text_file(workspace_root, relative)?;
    let text = &file.content;
    Ok(FileLines {
        relative_path: file.relative_path,
        lines: doyah_studio_db::lines(text),
        gutter_digits: doyah_studio_db::gutter_digits(text),
        dominant_ending: doyah_studio_db::dominant_ending(text),
        mixed_endings: doyah_studio_db::is_mixed(text),
        language_key: file.language_key,
    })
}

/// 高亮分词：`(相对路径, 分词表, 原文长度)` —— 前端**按同一份原文切片**上色。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FileSpans {
    pub relative_path: String,
    pub spans: Vec<doyah_studio_db::CodeSpan>,
    /// 原文**字节**长度（前端可据此校验两边看到的是同一份文本）
    pub byte_len: usize,
}

pub fn read_spans(workspace_root: &str, relative: &str, language_key: Option<&str>) -> Result<FileSpans, DbFailure> {
    let file = read_text_file(workspace_root, relative)?;
    let language = match language_key {
        Some(key) => language_from_key(key),
        None => doyah_studio_db::TextLanguage::detect(&file.relative_path),
    };
    Ok(FileSpans {
        relative_path: file.relative_path,
        spans: doyah_studio_db::tokenize_code(&file.content, language),
        byte_len: file.content.len(),
    })
}

/// 语言键 → 语言（**认不出一律纯文本**：猜错会按错的语法上色，比不上色更误导）。
fn language_from_key(key: &str) -> doyah_studio_db::TextLanguage {
    use doyah_studio_db::TextLanguage as L;
    match key {
        "lang.markdown" => L::Markdown,
        "lang.rust" => L::Rust,
        "lang.typescript" => L::TypeScript,
        "lang.javascript" => L::JavaScript,
        "lang.json" => L::Json,
        "lang.toml" => L::Toml,
        "lang.yaml" => L::Yaml,
        "lang.sql" => L::Sql,
        "lang.shell" => L::Shell,
        "lang.html" => L::Html,
        "lang.css" => L::Css,
        _ => L::PlainText,
    }
}

#[cfg(test)]
mod lines_tests {
    use super::*;

    // 夹具根目录：**不用系统临时区**（cargo test 拿不到会话里的 TEMP，系统临时区在本机沙箱里拒写
    // ⇒ 建夹具报"拒绝访问"，看着像权限问题、其实是写错了地方）。可用环境变量覆盖。
    fn fixture_root() -> std::path::PathBuf {
        match std::env::var("DOYAH_TEST_ROOT") {
            Ok(value) if !value.trim().is_empty() => std::path::PathBuf::from(value),
            _ => std::path::PathBuf::from("D:/AIProjects/_tmp_face2/fish-fixtures"),
        }
    }

    fn root(tag: &str) -> PathBuf {
        let dir = fixture_root().join(format!("doyah-lines-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn reads_line_structure_with_gutter_width_and_endings() {
        let dir = root("read");
        let root_text = dir.to_string_lossy().to_string();
        // 三种换行符各来一次 + 一个混排文件
        std::fs::write(dir.join("lf.rs"), "fn a() {}\nfn b() {}\n").unwrap();
        std::fs::write(dir.join("crlf.rs"), "fn a() {}\r\nfn b() {}\r\n").unwrap();
        std::fs::write(dir.join("cr.rs"), "fn a() {}\rfn b() {}\r").unwrap();
        std::fs::write(dir.join("mixed.txt"), "a\r\nb\nc").unwrap();

        let lf = read_lines(&root_text, "lf.rs").unwrap();
        assert_eq!(lf.lines.len(), 3, "末尾终止符算多一行");
        assert_eq!(lf.dominant_ending, Some(doyah_studio_db::LineEnding::Lf));
        assert!(!lf.mixed_endings);
        assert_eq!(lf.gutter_digits, 1);

        let crlf = read_lines(&root_text, "crlf.rs").unwrap();
        assert_eq!(crlf.dominant_ending, Some(doyah_studio_db::LineEnding::Crlf));
        assert_eq!(crlf.lines.len(), 3, "CRLF 算一个终止符，不是两个");

        let cr = read_lines(&root_text, "cr.rs").unwrap();
        assert_eq!(cr.dominant_ending, Some(doyah_studio_db::LineEnding::Cr));
        assert_eq!(cr.lines.len(), 3);

        let mixed = read_lines(&root_text, "mixed.txt").unwrap();
        assert!(mixed.mixed_endings, "混排要如实报");
        assert_eq!(mixed.lines.len(), 3);

        // 行号列宽：造一个 12 行的文件 ⇒ 2 位
        let twelve: String = (1..=12).map(|i| format!("line {i}\n")).collect();
        std::fs::write(dir.join("twelve.txt"), &twelve).unwrap();
        assert_eq!(read_lines(&root_text, "twelve.txt").unwrap().gutter_digits, 2);
    }

    #[test]
    fn spans_cover_the_content_and_identify_the_language() {
        let dir = root("spans");
        let root_text = dir.to_string_lossy().to_string();
        let source = "fn main() {\n    let s = \"hi\"; // 注释\n}\n";
        std::fs::write(dir.join("main.rs"), source).unwrap();

        let spans = read_spans(&root_text, "main.rs", None).unwrap();
        assert_eq!(spans.byte_len, source.len(), "前端据此校验两边看的是同一份文本");
        assert!(!spans.spans.is_empty());
        // 关键字 / 字符串 / 注释都认出来了
        let kinds: Vec<doyah_studio_db::CodeTokenKind> = spans.spans.iter().map(|s| s.kind).collect();
        assert!(kinds.contains(&doyah_studio_db::CodeTokenKind::Keyword));
        assert!(kinds.contains(&doyah_studio_db::CodeTokenKind::Str));
        assert!(kinds.contains(&doyah_studio_db::CodeTokenKind::Comment));
        // 每个 span 都能安全切片
        for span in &spans.spans {
            assert!(source.is_char_boundary(span.start) && source.is_char_boundary(span.end));
        }
        // 明确给语言键时按它算（给 markdown ⇒ 空表）
        let plain = read_spans(&root_text, "main.rs", Some("lang.markdown")).unwrap();
        assert!(plain.spans.is_empty(), "Markdown 不上色");
        // 认不出的键 ⇒ 纯文本
        assert!(read_spans(&root_text, "main.rs", Some("lang.nope")).unwrap().spans.is_empty());
    }
}

// ── 外部改动（2.3）：载入快照与实际状态对比 ──────────────────────────────────────────
//
// 判定全在领域层 `staleness`：**先看内容指纹**（指纹一样就是没变，时间戳动了也不算 ——
// "另存了一遍同样的内容"很常见），再看大小与修改时间；盘上没有了 ⇒ "已删除"（不是"已改动"）。

/// 载入一个文件时记下的快照（页签拿它做对比）。
pub fn file_snapshot(workspace_root: &str, relative: &str) -> Result<doyah_studio_db::LoadedFile, DbFailure> {
    let path = resolve_in(workspace_root, relative)?;
    let meta = std::fs::metadata(&path).map_err(|e| {
        failure(
            format!("看不到这个文件：{e}（{}）", path.display()),
            "它可能被移动或删除了；刷新一下树。",
        )
    })?;
    let bytes = std::fs::read(&path).map_err(|e| {
        failure(
            format!("读文件失败：{e}（{}）", path.display()),
            "确认权限与文件状态。",
        )
    })?;
    Ok(doyah_studio_db::LoadedFile {
        relative_path: relative.replace('\\', "/"),
        byte_count: meta.len(),
        modified_unix: modified_unix(&meta),
        content_hash: doyah_studio_db::content_hash(&bytes),
    })
}

/// 修改时间（Unix 秒）；拿不到就是 `None`（**不编一个 0** —— 那会与真实时间戳混起来骗判定）。
fn modified_unix(meta: &std::fs::Metadata) -> Option<i64> {
    meta.modified()
        .ok()
        .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|delta| delta.as_secs() as i64)
}

/// 检查一个页签的快照与盘上现在那份是否还是同一份。
///
/// 返回 `(状态, 人话)`：**状态**给界面做分支，**人话**给界面直接显示（都 `None` 表示没变）。
pub fn check_staleness(
    workspace_root: &str,
    loaded: &doyah_studio_db::LoadedFile,
) -> Result<(doyah_studio_db::Staleness, Option<String>), DbFailure> {
    let path = resolve_in(workspace_root, &loaded.relative_path)?;
    let now = if path.exists() {
        let meta = std::fs::metadata(&path).map_err(|e| {
            failure(
                format!("看不到这个文件：{e}（{}）", path.display()),
                "确认权限与文件状态。",
            )
        })?;
        let bytes = std::fs::read(&path).map_err(|e| {
            failure(
                format!("读文件失败：{e}（{}）", path.display()),
                "确认权限与文件状态。",
            )
        })?;
        Some(doyah_studio_db::DiskFile {
            byte_count: meta.len(),
            modified_unix: modified_unix(&meta),
            content_hash: doyah_studio_db::content_hash(&bytes),
        })
    } else {
        None // 盘上没有了 ⇒ 交给领域层判成"已删除"
    };
    let staleness = doyah_studio_db::classify(loaded, now.as_ref());
    Ok((staleness, doyah_studio_db::staleness_note(staleness)))
}

#[cfg(test)]
mod staleness_tests {
    use super::*;

    // 夹具根目录：**不用系统临时区**（cargo test 拿不到会话里的 TEMP，系统临时区在本机沙箱里拒写
    // ⇒ 建夹具报“拒绝访问”，看着像权限问题、其实是写错了地方）。可用环境变量覆盖。
    fn fixture_root() -> std::path::PathBuf {
        match std::env::var("DOYAH_TEST_ROOT") {
            Ok(value) if !value.trim().is_empty() => std::path::PathBuf::from(value),
            _ => std::path::PathBuf::from("D:/AIProjects/_tmp_face2/fish-fixtures"),
        }
    }

    fn root(tag: &str) -> PathBuf {
        let dir = fixture_root().join(format!("doyah-stale-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn unchanged_then_modified_then_deleted_are_all_reported_truthfully() {
        let dir = root("check");
        let root_text = dir.to_string_lossy().to_string();
        std::fs::write(dir.join("a.txt"), "hello").unwrap();

        let snapshot = file_snapshot(&root_text, "a.txt").unwrap();
        // ① 没动过 ⇒ 未变，而且**不给提示**（不打扰）
        let (state, note) = check_staleness(&root_text, &snapshot).unwrap();
        assert_eq!(state, doyah_studio_db::Staleness::Unchanged);
        assert!(note.is_none());

        // ② 别处改了内容 ⇒ "被改过" + 一句能照做的人话
        std::fs::write(dir.join("a.txt"), "hello, world").unwrap();
        let (state, note) = check_staleness(&root_text, &snapshot).unwrap();
        assert_eq!(state, doyah_studio_db::Staleness::Modified);
        assert!(note.unwrap().contains("重新打开"));

        // ③ 内容一样、只是又写了一遍 ⇒ **还是未变**（这条防的是"天天误报"）
        let snapshot2 = file_snapshot(&root_text, "a.txt").unwrap();
        std::fs::write(dir.join("a.txt"), "hello, world").unwrap();
        let (state, _) = check_staleness(&root_text, &snapshot2).unwrap();
        assert_eq!(state, doyah_studio_db::Staleness::Unchanged, "内容没变就不该报");

        // ④ 盘上删掉 ⇒ "已删除"（与"被改过"分开报）
        std::fs::remove_file(dir.join("a.txt")).unwrap();
        let (state, note) = check_staleness(&root_text, &snapshot2).unwrap();
        assert_eq!(state, doyah_studio_db::Staleness::Deleted);
        assert!(note.unwrap().contains("已经不在了"));
    }

    #[test]
    fn same_size_rewrite_is_reported_as_replaced() {
        let dir = root("replace");
        let root_text = dir.to_string_lossy().to_string();
        std::fs::write(dir.join("b.txt"), "AAAA").unwrap();
        let snapshot = file_snapshot(&root_text, "b.txt").unwrap();
        // 同长度改写（大小不变、时间戳可能不变）⇒ 靠指纹抓出来
        std::fs::write(dir.join("b.txt"), "BBBB").unwrap();
        let (state, note) = check_staleness(&root_text, &snapshot).unwrap();
        assert!(state.needs_attention(), "同长度改写必须报出来");
        assert!(note.is_some());
    }

    #[test]
    fn snapshot_refuses_escapes_and_missing_files() {
        let dir = root("snapshot");
        let root_text = dir.to_string_lossy().to_string();
        assert!(file_snapshot(&root_text, "../outside.txt").is_err());
        assert!(file_snapshot(&root_text, "nope.txt").is_err());
    }
}

// ── 外观偏好的落盘（2.8）──────────────────────────────────────────────────────────
//
// 与其它偏好文件同一套路：**一个 JSON、按需读写、坏了不致命**（读不出来就按缺省走，
// 缺省是"跟随系统 + 星空紫 + 皮肤开"）。**键名与取值是契约**（见 Db/src/appearance.rs 的 keys）。

/// 外观偏好文件：`%APPDATA%\DoyahStudio\appearance.json`。
pub fn appearance_path() -> std::path::PathBuf {
    let base = std::env::var("APPDATA").unwrap_or_else(|_| ".".to_string());
    std::path::Path::new(&base).join("DoyahStudio").join("appearance.json")
}

/// 读外观偏好：文件不在 / 读不出来 / 结构不认识 ⇒ **按缺省**（不抛错，界面照常起）。
pub fn read_appearance() -> (doyah_studio_db::Appearance, Option<String>) {
    let path = appearance_path();
    if !path.exists() {
        return (doyah_studio_db::Appearance::default(), None);
    }
    match std::fs::read_to_string(&path) {
        Ok(text) if text.trim().is_empty() => (doyah_studio_db::Appearance::default(), None),
        Ok(text) => match serde_json::from_str::<serde_json::Value>(&text) {
            Ok(value) => {
                // 逐项解析：**缺项用缺省、未知值按规则回落**（不整体失败）
                let mode = value.get("mode").and_then(|v| v.as_str()).map(str::to_string);
                let scheme = value.get("scheme").and_then(|v| v.as_str()).map(str::to_string);
                let nebula = value.get("nebulaSkin").and_then(|v| v.as_bool());
                (
                    doyah_studio_db::Appearance::resolve(
                        mode.as_deref(),
                        scheme.as_deref(),
                        nebula,
                    ),
                    None,
                )
            }
            Err(e) => (
                doyah_studio_db::Appearance::default(),
                Some(format!("外观偏好读不出来（{e}）—— 已按缺省继续：{}", path.display())),
            ),
        },
        Err(e) => (
            doyah_studio_db::Appearance::default(),
            Some(format!("外观偏好打不开（{e}）：{}", path.display())),
        ),
    }
}

/// 写外观偏好（整份覆盖）。
pub fn write_appearance(appearance: &doyah_studio_db::Appearance) -> Result<(), DbFailure> {
    let path = appearance_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| {
            failure(format!("建配置目录失败：{e}（{}）", parent.display()), "确认该目录可写。")
        })?;
    }
    // 落盘用**契约键名**（mode / scheme / nebulaSkin），与读回来时一一对应
    let payload = serde_json::json!({
        "mode": appearance.mode.raw(),
        "scheme": appearance.scheme.raw(),
        "nebulaSkin": appearance.nebula_skin,
    });
    let text = serde_json::to_string_pretty(&payload).map_err(|e| {
        failure(format!("外观偏好序列化失败：{e}"), "这属实现缺陷：请保留现场并报告。")
    })?;
    std::fs::write(&path, text).map_err(|e| {
        failure(
            format!("写外观偏好失败：{e}（{}）", path.display()),
            "确认该文件可写（可能被杀毒软件 / 权限限制）。",
        )
    })
}

#[cfg(test)]
mod appearance_tests {
    use super::*;

    #[test]
    fn appearance_round_trips_and_unknown_values_fall_back() {
        // 直接用领域层的解析规则验一遍"缺项 / 未知值"两条（文件 IO 由上面的读写函数承担）
        let fresh = doyah_studio_db::Appearance::resolve(None, None, None);
        assert!(fresh.nebula_skin, "缺省皮肤开");
        assert_eq!(fresh.scheme, doyah_studio_db::ColorScheme::Stardust);
        let unknown = doyah_studio_db::Appearance::resolve(Some("nope"), Some("nope"), Some(false));
        assert_eq!(unknown.mode, doyah_studio_db::AppearanceMode::FollowSystem);
        assert_eq!(unknown.scheme, doyah_studio_db::ColorScheme::Stardust);
        assert!(!unknown.nebula_skin);
        // 落盘形态：键名是契约
        let payload = serde_json::json!({
            "mode": fresh.mode.raw(),
            "scheme": fresh.scheme.raw(),
            "nebulaSkin": fresh.nebula_skin,
        });
        let text = serde_json::to_string(&payload).unwrap();
        assert!(text.contains("\"mode\":\"followSystem\""), "{text}");
        assert!(text.contains("\"scheme\":\"stardust\""), "{text}");
        assert!(text.contains("\"nebulaSkin\":true"), "{text}");
    }
}

// ── 命令使用历史的落盘（2.9）──────────────────────────────────────────────────────
//
// 与其它偏好文件同一套路（一个 JSON、按需读写、坏了不致命）。
// **淘汰（prune）只在写盘前做一次** —— 绝不在"记一次"里做（那会让新命令永远长不起来，
// 见 `Db/src/command_history.rs` 的注释）。

/// 命令历史文件：`%APPDATA%\DoyahStudio\command-history.json`。
pub fn command_history_path() -> std::path::PathBuf {
    let base = std::env::var("APPDATA").unwrap_or_else(|_| ".".to_string());
    std::path::Path::new(&base).join("DoyahStudio").join("command-history.json")
}

/// 读命令历史：文件不在 / 读不出来 ⇒ **空历史**（面板只是没有"最近使用"分组，不打扰用户）。
pub fn read_command_history() -> doyah_studio_db::CommandHistory {
    let path = command_history_path();
    let Ok(text) = std::fs::read_to_string(&path) else {
        return doyah_studio_db::CommandHistory::default();
    };
    if text.trim().is_empty() {
        return doyah_studio_db::CommandHistory::default();
    }
    serde_json::from_str(&text).unwrap_or_default()
}

/// 写命令历史（**写前淘汰一次**）。
pub fn write_command_history(history: &doyah_studio_db::CommandHistory) -> Result<(), DbFailure> {
    let path = command_history_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| {
            failure(format!("建配置目录失败：{e}（{}）", parent.display()), "确认该目录可写。")
        })?;
    }
    let text = serde_json::to_string_pretty(history).map_err(|e| {
        failure(format!("命令历史序列化失败：{e}"), "这属实现缺陷：请保留现场并报告。")
    })?;
    std::fs::write(&path, text).map_err(|e| {
        failure(
            format!("写命令历史失败：{e}（{}）", path.display()),
            "确认该文件可写（可能被杀毒软件 / 权限限制）。",
        )
    })
}

#[cfg(test)]
mod command_history_tests {
    use super::*;

    #[test]
    fn history_prunes_only_on_write_boundary_not_per_record() {
        // **这条是"真缺陷"的回归判据**：记 60 条之后、淘汰之前，条数应当是 60
        // （如果谁把淘汰放回 record 里，这条会立刻红）。
        let mut history = doyah_studio_db::CommandHistory::default();
        for index in 0..60u32 {
            let id = format!("cmd.{index:02}");
            // **内层循环是必须的**：cmd.i 要记 i+1 次（我第一版漏了内层，每条只记 1 次
            // ⇒ 断言 60 次必然红 —— 又是用例写错，不是实现错）
            for _ in 0..=index {
                history = history.record(&id, 1000 + index as i64);
            }
        }
        assert_eq!(history.entries.len(), 60, "记的过程不该淘汰");
        history.prune();
        assert_eq!(history.entries.len(), doyah_studio_db::COMMAND_HISTORY_LIMIT);
        assert_eq!(history.count_of("cmd.59"), 60, "用得最多的必须留着");
        // 空文件 / 坏文件都按空历史走（不抛）
        let empty = doyah_studio_db::CommandHistory::default();
        assert!(empty.ranked(10).is_empty());
    }
}
// ── 按类型打开（2.3 遗留项）：判定 + 图片字节 ────────────────────────────────────────
//
// 判定在领域层 `open_as`（5 例单测：图片按内容认 / 二进制 / 太大不截断 / 说明给下一步）。
// 本层只负责"读头部让领域层判、需要时把图片字节取出来"。

/// 打开判定的结果（给界面 + 一句说明）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenDecision {
    pub relative_path: String,
    pub open_as: doyah_studio_db::OpenAs,
    /// 界面直接显示的一句说明（`None` = 正常文本，不打扰）
    pub note: Option<String>,
    /// 图片的 MIME（`None` = 不是图片；界面用 `data:` 显示）
    pub image_mime: Option<String>,
}

/// 判一个文件该怎么打开（**只读头部**：大文件不整个读进来）。
pub fn decide_open(workspace_root: &str, relative: &str) -> Result<OpenDecision, DbFailure> {
    let path = resolve_in(workspace_root, relative)?;
    let meta = std::fs::metadata(&path).map_err(|e| {
        failure(
            format!("看不到这个文件：{e}（{}）", path.display()),
            "它可能被移动或删除了；刷新一下树。",
        )
    })?;
    let whole_size = meta.len();

    // 只读前 PROBE_BYTES（够判魔数与 NUL）
    let head = {
        use std::io::Read;
        let mut file = std::fs::File::open(&path).map_err(|e| {
            failure(format!("打不开这个文件：{e}（{}）", path.display()), "确认权限。")
        })?;
        let mut buffer = vec![0u8; doyah_studio_db::PROBE_BYTES];
        let read = file.read(&mut buffer).unwrap_or(0);
        buffer.truncate(read);
        buffer
    };

    let language = doyah_studio_db::TextLanguage::detect(relative);
    let open_as = doyah_studio_db::decide_open_as(&head, whole_size, language.key());
    let note = doyah_studio_db::explain_open_as(&open_as);
    let image_mime = match &open_as {
        doyah_studio_db::OpenAs::Image { format } => Some(format.mime().to_string()),
        _ => None,
    };
    Ok(OpenDecision {
        relative_path: relative.replace('\\', "/"),
        open_as,
        note,
        image_mime,
    })
}

/// 读图片字节（base64）供界面用 `data:` 显示。
///
/// **只允许读判定为图片的文件**（免得把任意大文件塞进前端）；太大也要拒（图片也有上限）。
pub fn read_image_base64(workspace_root: &str, relative: &str) -> Result<String, DbFailure> {
    let decision = decide_open(workspace_root, relative)?;
    if decision.image_mime.is_none() {
        return Err(failure(
            format!("这不是图片：{relative}"),
            "只有按图片打开的文件才走这条路（其余走编辑面）。",
        ));
    }
    let path = resolve_in(workspace_root, relative)?;
    let bytes = std::fs::read(&path).map_err(|e| {
        failure(format!("读图片失败：{e}（{}）", path.display()), "确认权限与文件状态。")
    })?;
    // 图片上限比文本宽（图片本来就不小），但仍要有个头
    const IMAGE_LIMIT: usize = 32 * 1024 * 1024;
    if bytes.len() > IMAGE_LIMIT {
        return Err(failure(
            format!("图片太大（{} 字节，上限 {IMAGE_LIMIT}）", bytes.len()),
            "本版不做图片降采样；用系统看图工具打开更大。",
        ));
    }
    Ok(base64_encode(&bytes))
}

/// 标准 base64 编码（**自写不引依赖**：只需编码，几行就够）。
fn base64_encode(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity((bytes.len() + 2) / 3 * 4);
    for chunk in bytes.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = *chunk.get(1).unwrap_or(&0) as u32;
        let b2 = *chunk.get(2).unwrap_or(&0) as u32;
        let triple = (b0 << 16) | (b1 << 8) | b2;
        out.push(TABLE[(triple >> 18) as usize & 0x3f] as char);
        out.push(TABLE[(triple >> 12) as usize & 0x3f] as char);
        out.push(if chunk.len() > 1 {
            TABLE[(triple >> 6) as usize & 0x3f] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            TABLE[triple as usize & 0x3f] as char
        } else {
            '='
        });
    }
    out
}

#[cfg(test)]
mod open_decision_tests {
    use super::*;

    // 夹具根目录：**不用系统临时区**（cargo test 拿不到会话里的 TEMP，系统临时区在本机沙箱里拒写
    // ⇒ 建夹具报"拒绝访问"）。可用环境变量覆盖。
    fn fixture_root() -> std::path::PathBuf {
        match std::env::var("DOYAH_TEST_ROOT") {
            Ok(value) if !value.trim().is_empty() => std::path::PathBuf::from(value),
            _ => std::path::PathBuf::from("D:/AIProjects/_tmp_face2/fish-fixtures"),
        }
    }

    fn root(tag: &str) -> PathBuf {
        static COUNTER: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let unique = COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        // 与其它测试模块同一口径：**不用系统临时区**（cargo test 拿不到会话里的 TEMP，
        // 系统临时区在本机沙箱里拒写 ⇒ 建夹具报"拒绝访问"）。
        let dir = fixture_root().join(format!("doyah-open-{tag}-{}-{unique}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn decides_text_image_binary_and_too_large() {
        let dir = root("decide");
        let root_text = dir.to_string_lossy().to_string();

        std::fs::write(dir.join("a.rs"), "fn main() {}").unwrap();
        std::fs::write(dir.join("blob.bin"), [0u8, 1, 2, 3]).unwrap();
        // 一张最小的 PNG（只需魔数够判）
        let png: Vec<u8> = vec![0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0];
        std::fs::write(dir.join("pic.txt"), &png).unwrap(); // **扩展名故意骗人**
        // 超大文本
        let big = "x".repeat((doyah_studio_db::MAX_EDITABLE_BYTES + 10) as usize);
        std::fs::write(dir.join("big.txt"), &big).unwrap();

        let text = decide_open(&root_text, "a.rs").unwrap();
        assert!(matches!(text.open_as, doyah_studio_db::OpenAs::Text { .. }));
        assert!(text.note.is_none(), "正常文本不打扰");

        let binary = decide_open(&root_text, "blob.bin").unwrap();
        assert_eq!(binary.open_as, doyah_studio_db::OpenAs::Binary);
        assert!(binary.note.unwrap().contains("终端"), "要给出下一步");

        let image = decide_open(&root_text, "pic.txt").unwrap();
        assert_eq!(image.image_mime.as_deref(), Some("image/png"), "按内容认，不看扩展名");
        assert!(image.note.unwrap().contains("PNG"));

        let large = decide_open(&root_text, "big.txt").unwrap();
        match large.open_as {
            doyah_studio_db::OpenAs::TooLarge { bytes, limit } => {
                assert!(bytes > limit);
            }
            other => panic!("应当是 TooLarge，实际 {other:?}"),
        }
        // 越界与不存在都要挡
        assert!(decide_open(&root_text, "../outside.txt").is_err());
        assert!(decide_open(&root_text, "nope.txt").is_err());
    }

    #[test]
    fn image_bytes_are_returned_only_for_images() {
        let dir = root("image");
        let root_text = dir.to_string_lossy().to_string();
        let png: Vec<u8> = vec![0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3];
        std::fs::write(dir.join("pic.png"), &png).unwrap();
        std::fs::write(dir.join("a.txt"), "hello").unwrap();

        let encoded = read_image_base64(&root_text, "pic.png").unwrap();
        assert!(encoded.starts_with("iVBORw0KGgo"), "PNG 的 base64 前缀固定：{encoded}");
        // 非图片 ⇒ 拒绝（不把任意文件塞给前端）
        assert!(read_image_base64(&root_text, "a.txt").is_err());
        assert!(read_image_base64(&root_text, "../x.png").is_err());
    }

    #[test]
    fn base64_matches_known_values() {
        // RFC 4648 的样例（含补位）
        assert_eq!(base64_encode(b""), "");
        assert_eq!(base64_encode(b"f"), "Zg==");
        assert_eq!(base64_encode(b"fo"), "Zm8=");
        assert_eq!(base64_encode(b"foo"), "Zm9v");
        assert_eq!(base64_encode(b"foob"), "Zm9vYg==");
        assert_eq!(base64_encode(b"fooba"), "Zm9vYmE=");
        assert_eq!(base64_encode(b"foobar"), "Zm9vYmFy");
    }
}

// ── 保存（2.3 遗留项）：写盘 + 冲突拦截 ─────────────────────────────────────────────
//
// 判定在领域层 `save_guard`（6 例单测）。本层的顺序**必须是**：
// **先判 → 冲突就拒（一个字节都不写）→ 通过了才写盘**。
// 反过来（先写再报错）就等于"已经覆盖了别人的改动"，那是不可撤销的伤害。
//
// **载入快照由界面带进来**（`loaded`）：页签打开时记的那一份才是基线；
// 在这里现读盘会把基线换成"盘上现在这份"，冲突判定当场失真 —— 这是本函数第一条纪律。

/// 保存的判定结果（给界面）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveReport {
    pub relative_path: String,
    pub decision: doyah_studio_db::SaveDecision,
    /// 拒绝时的一句说明（**说清盘上是什么、下一步能选什么**）
    pub note: Option<String>,
    /// 写成功后的**新快照**（界面要更新它，否则下次保存会误报冲突）
    pub snapshot: Option<doyah_studio_db::LoadedFile>,
}

/// 保存一个文件：**先判再写**。
///
/// `loaded` = 页签打开时记的快照（**基线，不能现读**）；`force` = 用户明确选择"用我的版本覆盖"。
pub fn save_file(
    workspace_root: &str,
    relative: &str,
    content: &str,
    saved_content: &str,
    loaded: &doyah_studio_db::LoadedFile,
    force: bool,
) -> Result<SaveReport, DbFailure> {
    let now = disk_state(workspace_root, relative)?;

    // ① 判定（**读盘之后、写盘之前**）
    let staleness = doyah_studio_db::classify(loaded, now.as_ref());
    let decision = if force {
        doyah_studio_db::decide_overwrite(content, saved_content, staleness)
    } else {
        doyah_studio_db::decide_save(content, saved_content, loaded, now.as_ref())
    };

    match decision {
        doyah_studio_db::SaveDecision::NothingToDo => Ok(SaveReport {
            relative_path: relative.replace('\\', "/"),
            decision: doyah_studio_db::SaveDecision::NothingToDo,
            note: Some("内容没有变化，已跳过写入。".to_string()),
            snapshot: None,
        }),
        doyah_studio_db::SaveDecision::Conflict { staleness } => Ok(SaveReport {
            relative_path: relative.replace('\\', "/"),
            decision: doyah_studio_db::SaveDecision::Conflict { staleness },
            // **拒绝保存**：这里一个字节都没写
            note: Some(doyah_studio_db::explain_conflict(staleness)),
            snapshot: None,
        }),
        doyah_studio_db::SaveDecision::Write { recreated } => {
            let target = resolve_in(workspace_root, relative)?;
            std::fs::write(&target, content.as_bytes()).map_err(|e| {
                failure(
                    format!("写文件失败：{e}（{}）", target.display()),
                    "确认文件可写（可能被别的程序占用 / 只读）。",
                )
            })?;
            let snapshot = file_snapshot(workspace_root, relative)?;
            Ok(SaveReport {
                relative_path: relative.replace('\\', "/"),
                decision: doyah_studio_db::SaveDecision::Write { recreated },
                note: if recreated {
                    Some("盘上这份原本不在了 —— 已**重新建一份**。".to_string())
                } else {
                    None
                },
                snapshot: Some(snapshot),
            })
        }
    }
}

/// 盘上此刻的状态（**不写任何东西**）。
fn disk_state(
    workspace_root: &str,
    relative: &str,
) -> Result<Option<doyah_studio_db::DiskFile>, DbFailure> {
    let path = resolve_in(workspace_root, relative)?;
    if !path.exists() {
        return Ok(None);
    }
    let meta = std::fs::metadata(&path).map_err(|e| {
        failure(format!("看不到这个文件：{e}（{}）", path.display()), "确认权限。")
    })?;
    let bytes = std::fs::read(&path).map_err(|e| {
        failure(format!("读文件失败：{e}（{}）", path.display()), "确认权限。")
    })?;
    Ok(Some(doyah_studio_db::DiskFile {
        byte_count: meta.len(),
        modified_unix: modified_unix(&meta),
        content_hash: doyah_studio_db::content_hash(&bytes),
    }))
}

#[cfg(test)]
mod save_tests {
    use super::*;

    // 夹具根目录：**不用系统临时区**（cargo test 拿不到会话里的 TEMP，系统临时区在本机沙箱里拒写
    // ⇒ 建夹具报"拒绝访问"）。可用环境变量覆盖。
    fn fixture_root() -> std::path::PathBuf {
        match std::env::var("DOYAH_TEST_ROOT") {
            Ok(value) if !value.trim().is_empty() => std::path::PathBuf::from(value),
            _ => std::path::PathBuf::from("D:/AIProjects/_tmp_face2/fish-fixtures"),
        }
    }

    fn root(tag: &str) -> PathBuf {
        static COUNTER: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let unique = COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let dir = fixture_root().join(format!("doyah-save-{tag}-{}-{unique}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn a_normal_save_writes_and_returns_a_fresh_snapshot() {
        let dir = root("normal");
        let root_text = dir.to_string_lossy().to_string();
        std::fs::write(dir.join("a.txt"), "hello").unwrap();
        let loaded = file_snapshot(&root_text, "a.txt").unwrap();

        let report = save_file(&root_text, "a.txt", "hello world", "hello", &loaded, false).unwrap();
        assert!(matches!(
            report.decision,
            doyah_studio_db::SaveDecision::Write { .. }
        ));
        assert_eq!(std::fs::read_to_string(dir.join("a.txt")).unwrap(), "hello world");
        // **新快照要回来**（界面更新它，否则下次保存会误报冲突）
        assert!(report.snapshot.is_some());
        let fresh = report.snapshot.unwrap();
        assert_eq!(fresh.content_hash, doyah_studio_db::content_hash(b"hello world"));

        // 用新快照再存一次（内容又改了）⇒ 不冲突
        let second = save_file(&root_text, "a.txt", "hello world 2", "hello world", &fresh, false).unwrap();
        assert!(matches!(
            second.decision,
            doyah_studio_db::SaveDecision::Write { .. }
        ));
    }

    #[test]
    fn an_external_change_is_refused_and_the_file_is_left_untouched() {
        let dir = root("conflict");
        let root_text = dir.to_string_lossy().to_string();
        std::fs::write(dir.join("a.txt"), "hello").unwrap();
        let loaded = file_snapshot(&root_text, "a.txt").unwrap();
        // 别处改了它
        std::fs::write(dir.join("a.txt"), "SOMEONE ELSE").unwrap();

        let report = save_file(&root_text, "a.txt", "my version", "hello", &loaded, false).unwrap();
        assert!(matches!(
            report.decision,
            doyah_studio_db::SaveDecision::Conflict { .. }
        ));
        assert!(report.note.unwrap().contains("没有保存"));
        // **一个字节都没写**（这是本函数最要紧的一条）
        assert_eq!(std::fs::read_to_string(dir.join("a.txt")).unwrap(), "SOMEONE ELSE");
        assert!(report.snapshot.is_none());

        // 用户明确选"覆盖" ⇒ 放行，并且内容确实被覆盖
        let forced = save_file(&root_text, "a.txt", "my version", "hello", &loaded, true).unwrap();
        assert!(matches!(
            forced.decision,
            doyah_studio_db::SaveDecision::Write { .. }
        ));
        assert_eq!(std::fs::read_to_string(dir.join("a.txt")).unwrap(), "my version");
    }

    #[test]
    fn nothing_to_do_skips_the_write_entirely() {
        let dir = root("none");
        let root_text = dir.to_string_lossy().to_string();
        std::fs::write(dir.join("a.txt"), "same").unwrap();
        let loaded = file_snapshot(&root_text, "a.txt").unwrap();
        let before = std::fs::metadata(dir.join("a.txt")).unwrap().modified().unwrap();
        std::thread::sleep(std::time::Duration::from_millis(20));
        let report = save_file(&root_text, "a.txt", "same", "same", &loaded, false).unwrap();
        assert!(matches!(
            report.decision,
            doyah_studio_db::SaveDecision::NothingToDo
        ));
        // 时间戳**没被搅动**（说明真的没写）
        let after = std::fs::metadata(dir.join("a.txt")).unwrap().modified().unwrap();
        assert_eq!(before, after, "没变化就不该写盘");
    }

    #[test]
    fn a_file_deleted_on_disk_is_recreated_and_says_so() {
        let dir = root("recreate");
        let root_text = dir.to_string_lossy().to_string();
        std::fs::write(dir.join("a.txt"), "hello").unwrap();
        let loaded = file_snapshot(&root_text, "a.txt").unwrap();
        std::fs::remove_file(dir.join("a.txt")).unwrap();

        let report = save_file(&root_text, "a.txt", "new content", "hello", &loaded, false).unwrap();
        match report.decision {
            doyah_studio_db::SaveDecision::Write { recreated } => assert!(recreated),
            other => panic!("应当是 Write {{ recreated: true }}，实际 {other:?}"),
        }
        assert!(report.note.unwrap().contains("重新建一份"));
        assert_eq!(std::fs::read_to_string(dir.join("a.txt")).unwrap(), "new content");
    }

    #[test]
    fn saving_refuses_escapes() {
        let dir = root("escape");
        let root_text = dir.to_string_lossy().to_string();
        let loaded = doyah_studio_db::LoadedFile {
            relative_path: "a.txt".to_string(),
            byte_count: 5,
            modified_unix: Some(1),
            content_hash: doyah_studio_db::content_hash(b"hello"),
        };
        assert!(save_file(&root_text, "../outside.txt", "x", "y", &loaded, false).is_err());
    }
}

// ── 跨文件替换（2.4）：预览 + 落盘 ───────────────────────────────────────────────
//
// 判定与内容计算都在领域层 `replace`（7 例单测）。本层的两条纪律：
// 1. **预览与落盘用同一份计划**（`preview` 算完交给界面，`apply` 时按同一规则重算一次并核对
//    盘上快照）—— 不让"看到的是 A、写下去的是 B"。
// 2. **落盘走保存护栏**：盘上被别处改过就**拒绝**（替换不能绕过冲突判定）。

/// 一份文件的替换预览（**不带**替换后全文，界面不需要；落盘时再算）。**
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReplacePreviewFile {
    pub relative_path: String,
    pub count: usize,
    pub changes: Vec<doyah_studio_db::LineChange>,
}

/// 替换预览的总览。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReplacePreview {
    pub query: String,
    pub replacement: String,
    pub files: Vec<ReplacePreviewFile>,
    /// 一起改了几处
    pub total: usize,
    /// 跳过（二进制 / 超大 / 读不了）——**跳过 ≠ 没命中**
    pub skips: doyah_studio_db::SkipReport,
    /// 人读的一句话（**说清影响面，再让人确认**）
    pub summary: String,
}

/// 扫一遍工作区，算出"将改哪些文件、各改几处"（**不写盘**）。
pub fn replace_preview(
    workspace_root: &str,
    query: &str,
    replacement: &str,
    show_hidden: bool,
) -> Result<ReplacePreview, DbFailure> {
    if query.trim().is_empty() {
        return Err(failure("查询词是空的".to_string(), "空查询会把每行每处都换掉，不能这么做。"));
    }
    // 复用检索那套有界遍历（忽略名单 / 深度 / 不跟随链接）
    let outcome = crate::search::search_workspace(
        workspace_root,
        query,
        true,
        show_hidden,
        Some(usize::MAX),
        None,
    )?;
    let mut files: Vec<ReplacePreviewFile> = Vec::new();
    let mut plans: Vec<doyah_studio_db::FileChange> = Vec::new();
    for group in &outcome.groups {
        let Ok(file) = read_text_file(workspace_root, &group.relative_path) else {
            continue;
        };
        if let Some(plan) = doyah_studio_db::plan_file(&group.relative_path, &file.content, query, replacement)
        {
            files.push(ReplacePreviewFile {
                relative_path: plan.relative_path.clone(),
                count: plan.count,
                changes: plan.changes.clone(),
            });
            plans.push(plan);
        }
    }
    let total: usize = plans.iter().map(|plan| plan.count).sum();
    Ok(ReplacePreview {
        query: query.to_string(),
        replacement: replacement.to_string(),
        files,
        total,
        skips: outcome.skips,
        summary: doyah_studio_db::summarise(&plans),
    })
}

/// 落盘结果（逐文件）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReplaceResult {
    pub relative_path: String,
    pub count: usize,
    /// `written` / `conflict` / `skipped`（界面按它分类说话）
    pub outcome: String,
    /// 冲突时的一句说明
    pub note: Option<String>,
}

/// 落盘总览。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReplaceApplied {
    pub results: Vec<ReplaceResult>,
    pub written: usize,
    pub conflicts: usize,
    pub total_changes: usize,
}

/// 真正落盘：**逐个文件走保存护栏**（盘上被改过就拒，不写）。
///
/// `snapshots` = 界面带来的"载入快照"（每份文件的基线）；缺基线的文件**直接跳过并说明**
/// —— 没有基线就无法判断盘上有没有被别处改过，盲目写就是拿别人的改动去赌。
pub fn replace_apply(
    workspace_root: &str,
    query: &str,
    replacement: &str,
    snapshots: &std::collections::HashMap<String, doyah_studio_db::LoadedFile>,
    show_hidden: bool,
    force: bool,
) -> Result<ReplaceApplied, DbFailure> {
    let preview = replace_preview(workspace_root, query, replacement, show_hidden)?;
    let mut results: Vec<ReplaceResult> = Vec::new();
    let mut written = 0usize;
    let mut conflicts = 0usize;
    let mut total_changes = 0usize;

    for file in &preview.files {
        let Ok(current) = read_text_file(workspace_root, &file.relative_path) else {
            results.push(ReplaceResult {
                relative_path: file.relative_path.clone(),
                count: 0,
                outcome: "skipped".to_string(),
                note: Some("读不出来了（文件可能在预览之后被删/改）".to_string()),
            });
            continue;
        };
        let Some(plan) = doyah_studio_db::plan_file(&file.relative_path, &current.content, query, replacement)
        else {
            results.push(ReplaceResult {
                relative_path: file.relative_path.clone(),
                count: 0,
                outcome: "skipped".to_string(),
                note: Some("预览之后这里已经不再匹配".to_string()),
            });
            continue;
        };
        let Some(loaded) = snapshots.get(&file.relative_path) else {
            results.push(ReplaceResult {
                relative_path: file.relative_path.clone(),
                count: plan.count,
                outcome: "skipped".to_string(),
                note: Some("没有载入快照（没打开过它）⇒ 无法确认盘上有没有被改过，**不敢写**".to_string()),
            });
            continue;
        };
        // **同一份计划**：`plan.replaced` 就是写下去的内容（与预览同源）
        let report = save_file(
            workspace_root,
            &file.relative_path,
            &plan.replaced,
            &current.content,
            loaded,
            force,
        )?;
        match report.decision {
            doyah_studio_db::SaveDecision::Write { .. } => {
                written += 1;
                total_changes += plan.count;
                results.push(ReplaceResult {
                    relative_path: file.relative_path.clone(),
                    count: plan.count,
                    outcome: "written".to_string(),
                    note: report.note,
                });
            }
            doyah_studio_db::SaveDecision::Conflict { staleness } => {
                conflicts += 1;
                results.push(ReplaceResult {
                    relative_path: file.relative_path.clone(),
                    count: plan.count,
                    outcome: "conflict".to_string(),
                    note: Some(doyah_studio_db::explain_conflict(staleness)),
                });
            }
            doyah_studio_db::SaveDecision::NothingToDo => {
                results.push(ReplaceResult {
                    relative_path: file.relative_path.clone(),
                    count: 0,
                    outcome: "skipped".to_string(),
                    note: Some("内容没有变化".to_string()),
                });
            }
        }
    }
    Ok(ReplaceApplied {
        results,
        written,
        conflicts,
        total_changes,
    })
}
