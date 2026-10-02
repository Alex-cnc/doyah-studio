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
