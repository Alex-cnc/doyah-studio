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

    fn temp_root(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("doyah-fs-{tag}-{}", std::process::id()));
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

    fn write_root(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("doyah-write-{tag}-{}", std::process::id()));
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
    fn write_root(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("doyah-reveal-{tag}-{}", std::process::id()));
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

    fn root(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("doyah-lines-{tag}-{}", std::process::id()));
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