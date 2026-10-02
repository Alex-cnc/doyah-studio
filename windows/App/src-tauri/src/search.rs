//! 工作区检索的**表示层**（真走目录树）—— 判定与匹配全在领域层 `search`
//!
//! 为什么走树这一半必须在表示层：它要碰磁盘（目录、大小、读文本），而领域层保持零平台依赖。
//! 这一层的纪律与领域层一致：**有界递归 / 不跟随符号链接 / 尊重忽略名单 / 跳过要报数**。

use std::path::{Path, PathBuf};

use doyah_studio_db::search as engine;
use doyah_studio_db::workspace::{should_list, EntryKind, DEFAULT_IGNORED};

use crate::fs;
use crate::postgres::DbFailure;

/// 一次检索的结果（文件名与内容共用，未用的那半边为空）。
#[derive(Debug, Clone, Default, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchOutcome {
    /// 按文件名找到的条目（相对路径，`/` 分隔）
    pub files: Vec<String>,
    /// 按内容找到的分组
    pub groups: Vec<engine::ContentGroup>,
    /// **跳过报告**（二进制 / 超大 / 读不了）—— 跳过 ≠ 通过
    pub skips: engine::SkipReport,
    /// 真正读了内容的文件数
    pub scanned_files: usize,
    /// 命中总数到达上限而提前停止（界面要如实提示）
    pub truncated: bool,
    /// 本次真正用的上限（界面照它说话，不写死）
    pub limit: usize,
}

/// 走一遍目录树，把"要看的文件"列出来（**不递归进符号链接**）。
///
/// 返回 `(相对路径, 绝对路径)`；忽略名单与隐藏项口径复用领域层的 `should_list`。
fn walk(root: &Path, max_depth: usize, show_hidden: bool, limit: usize) -> (Vec<(String, PathBuf)>, bool) {
    let mut found: Vec<(String, PathBuf)> = Vec::new();
    let mut truncated = false;
    // 广度优先 + 深度记账（**不递归**：深度太深时不会把调用栈也压进去）
    let mut queue: Vec<(PathBuf, usize)> = vec![(root.to_path_buf(), 0)];
    while let Some((directory, depth)) = queue.pop() {
        if depth > max_depth {
            continue;
        }
        let Ok(read) = std::fs::read_dir(&directory) else { continue };
        for item in read.flatten() {
            let name = item.file_name().to_string_lossy().to_string();
            if !should_list(&name, show_hidden, DEFAULT_IGNORED) {
                continue;
            }
            let path = item.path();
            // `symlink_metadata` 不跟随链接 ⇒ 符号链接既不进去、也不当文件读
            let Ok(meta) = std::fs::symlink_metadata(&path) else { continue };
            if meta.file_type().is_symlink() {
                continue;
            }
            if meta.is_dir() {
                queue.push((path, depth + 1));
                continue;
            }
            let relative = doyah_studio_db::workspace::relative_path(&path.to_string_lossy(), &root.to_string_lossy())
                .unwrap_or_else(|| name.clone());
            found.push((relative, path));
            if found.len() >= limit {
                truncated = true;
                return (found, truncated);
            }
        }
    }
    (found, truncated)
}

/// 工作区检索（`by_content = false` 按文件名、`true` 按内容）。**两者共用同一个匹配谓词。**
pub fn search_workspace(
    workspace_root: &str,
    query: &str,
    by_content: bool,
    show_hidden: bool,
    limit: Option<usize>,
    max_depth: Option<usize>,
) -> Result<SearchOutcome, DbFailure> {
    let needle = engine::normalize(query);
    if needle.is_empty() {
        return Err(DbFailure {
            message: "查询词是空的".to_string(),
            hint: "写一个词再搜（空查询不该命中一切）。".to_string(),
        });
    }
    let root = Path::new(workspace_root);
    if !root.is_dir() {
        return Err(DbFailure {
            message: format!("工作区不是一个目录：{workspace_root}"),
            hint: "先在上面打开一个文件夹。".to_string(),
        });
    }
    let limit = limit.unwrap_or(engine::DEFAULT_RESULT_LIMIT).max(1);
    let max_depth = max_depth.unwrap_or(engine::DEFAULT_MAX_DEPTH);

    // 文件名搜索：只看名字，不读内容（快）
    if !by_content {
        let (files, truncated) = walk(root, max_depth, show_hidden, usize::MAX);
        // 先把**全部命中**数出来，再截到上限 —— "截断"要按**命中总数**判，不能按取回来的条数判
        // （我第一版就是按后者：恰好等于上限时漏报，恰好多一条时又看不出来）。
        let mut matched: Vec<String> = files
            .into_iter()
            .filter(|(relative, _)| engine::matches(relative, &needle))
            .map(|(relative, _)| relative)
            .collect();
        let truncated = truncated || matched.len() > limit;
        matched.truncate(limit);
        return Ok(SearchOutcome {
            files: matched,
            groups: Vec::new(),
            skips: engine::SkipReport::default(),
            scanned_files: 0,
            truncated,
            limit,
        });
    }

    // 内容搜索：逐个读、逐个算（**跳过要分类计数**）
    let (files, walk_truncated) = walk(root, max_depth, show_hidden, usize::MAX);
    let mut groups: Vec<engine::ContentGroup> = Vec::new();
    let mut skips = engine::SkipReport::default();
    let mut scanned = 0usize;
    for (relative, path) in files {
        let Ok(meta) = std::fs::metadata(&path) else {
            skips.unreadable += 1;
            continue;
        };
        if meta.len() > engine::DEFAULT_MAX_FILE_SIZE {
            skips.too_large += 1;
            continue;
        }
        let Ok(bytes) = std::fs::read(&path) else {
            skips.unreadable += 1;
            continue;
        };
        let Some(text) = engine::decode_text(&bytes) else {
            skips.binary += 1;
            continue;
        };
        scanned += 1;
        let (hits, _per_file_truncated) = engine::hits_in_text(
            &relative,
            &text,
            &needle,
            engine::DEFAULT_PER_FILE_LIMIT,
            engine::DEFAULT_SNIPPET_LIMIT,
        );
        if !hits.is_empty() {
            groups.push(engine::ContentGroup {
                relative_path: relative,
                hits,
            });
        }
    }
    let mut result = engine::assemble(groups, skips, scanned, limit);
    result.truncated = result.truncated || walk_truncated;
    Ok(SearchOutcome {
        files: Vec::new(),
        groups: result.groups,
        skips: result.skips,
        scanned_files: result.scanned_files,
        truncated: result.truncated,
        limit,
    })
}

/// 跳到命中行要用的"带行号打开"：先过安全关，再把行号夹进行数。
///
/// 夹行号的理由：文件可能在检索之后被改短了 —— 那时**如实给一个存在的行**，
/// 而不是让界面跳到一个不存在的位置。
pub fn clamp_line(workspace_root: &str, relative: &str, line: usize) -> Result<usize, DbFailure> {
    let lines = fs::read_lines(workspace_root, relative)?;
    let count = lines.lines.len().max(1);
    Ok(line.clamp(1, count))
}
#[cfg(test)]
mod tests {
    use super::*;

    /// 夹具根目录：**不用系统临时区**。
    ///
    /// 由头（实测）：`cargo test` 起的测试进程拿不到会话里设的 `TEMP`，`std::env::temp_dir()`
    /// 于是指向 `C:\Users\...\AppData\Local\Temp`，而本机沙箱**拒写系统临时区** ⇒ 建夹具目录报
    /// “拒绝访问 (os error 5)”。看着像权限或杀软问题，实际是**写错了地方**。
    /// 改用工作区外的本侧临时区（一定可写），并留一个环境变量可覆盖。
    fn test_root() -> PathBuf {
        match std::env::var("DOYAH_TEST_ROOT") {
            Ok(value) if !value.trim().is_empty() => PathBuf::from(value),
            _ => PathBuf::from("D:/AIProjects/_tmp_face2/fish-fixtures"),
        }
    }

    fn root(tag: &str) -> PathBuf {
        // 目录名**全局唯一**：进程号 + 自增号 + tag + 纳秒时间戳。
        // 为什么要时间戳：Db 与 shell 是两个测试二进制，可能拿到同一个进程号、自增号也各自从 0 起
        // ⇒ 光靠前两者仍会撞在同一目录上（两个测试互相踩，表象同样是“拒绝访问”）。
        static COUNTER: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let unique = COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let dir = test_root().join(format!(
            "doyah-search-{tag}-{}-{unique}-{nanos}",
            std::process::id()
        ));
        std::fs::create_dir_all(&dir)
            .unwrap_or_else(|e| panic!("建夹具目录失败：{e}  路径={}", dir.display()));
        std::fs::create_dir_all(dir.join("src/inner")).unwrap();
        std::fs::create_dir_all(dir.join("node_modules")).unwrap();
        std::fs::write(dir.join("agent-runner.txt"), "nothing here\n").unwrap();
        std::fs::write(dir.join("src/cafe.md"), "unrelated\nhas Agent inside\n").unwrap();
        std::fs::write(dir.join("src/inner/deep.txt"), "agent deep\n").unwrap();
        // 第二个**文件名**含 agent 的夹具：这样 result-limit 才真的构成截断（只一个时不算截断）
        std::fs::write(dir.join("src/inner/agent-notes.md"), "unrelated\n").unwrap();
        std::fs::write(dir.join("node_modules/pkg.txt"), "agent in ignored dir\n").unwrap();
        // **点开头**才算隐藏项（我先写成 hidden.txt，那不是隐藏文件 —— 判据对、是夹具起错名了）
        std::fs::write(dir.join(".hidden.txt"), "agent hidden\n").unwrap();
        std::fs::write(dir.join("blob.bin"), [0u8, 1, 2, 3]).unwrap();
        dir
    }

    #[test]
    fn filename_search_is_bounded_and_ignores_the_ignore_list() {
        let dir = root("names");
        let root_text = dir.to_string_lossy().to_string();
        // 按名字找 agent（大小写不敏感）
        let found = search_workspace(&root_text, "AGENT", false, false, None, None).unwrap();
        assert!(found.files.iter().any(|f| f.ends_with("agent-runner.txt")));
        assert!(found.files.iter().any(|f| f.ends_with("agent-notes.md")));
        assert_eq!(found.files.len(), 2, "名字含 agent 的应当有两条");
        // 忽略名单里的目录不搜
        assert!(
            !found.files.iter().any(|f| f.contains("node_modules")),
            "忽略名单里的目录不该被搜到：{:?}",
            found.files
        );
        // 文件名检索不读内容 ⇒ 不给分组
        assert!(found.groups.is_empty());
        // 结果上限：命中 2 条、上限 1 ⇒ 只给 1 条，并且**如实标记截断**
        let limited = search_workspace(&root_text, "agent", false, false, Some(1), None).unwrap();
        assert_eq!(limited.files.len(), 1);
        assert!(limited.truncated, "命中数超过上限时要如实说（按命中总数判，不是按取回来的条数）");
        // 上限够大 ⇒ 不标截断
        let roomy = search_workspace(&root_text, "agent", false, false, Some(50), None).unwrap();
        assert!(!roomy.truncated);
        // 空查询给结构化错误（不命中一切）
        assert!(search_workspace(&root_text, "   ", false, false, None, None).is_err());
    }

    #[test]
    fn content_search_groups_by_file_with_line_numbers() {
        let dir = root("content");
        let root_text = dir.to_string_lossy().to_string();
        let found = search_workspace(&root_text, "agent", true, false, None, None).unwrap();
        let paths: Vec<&str> = found.groups.iter().map(|g| g.relative_path.as_str()).collect();
        assert!(paths.iter().any(|p| p.ends_with("cafe.md")), "{paths:?}");
        assert!(paths.iter().any(|p| p.ends_with("deep.txt")), "{paths:?}");
        let md = found
            .groups
            .iter()
            .find(|g| g.relative_path.ends_with("cafe.md"))
            .unwrap();
        assert_eq!(md.hits[0].line, 2, "行号要与编辑器行号列同口径");
        assert_eq!(md.hits[0].snippet, "has Agent inside");
        // 大小写不敏感：按名字搜 CAFE 也能搜到 cafe.md
        let by_name = search_workspace(&root_text, "CAFE", false, false, None, None).unwrap();
        assert!(by_name.files.iter().any(|f| f.ends_with("cafe.md")));
        // 二进制文件被跳过并**报数**（不是静默略过）
        assert_eq!(found.skips.binary, 1, "{:?}", found.skips);
        assert!(found.scanned_files >= 3);
        // 忽略名单里的目录内容也不搜
        assert!(!paths.iter().any(|p| p.contains("node_modules")));
        // 隐藏文件默认不搜，开了才搜
        assert!(!paths.iter().any(|p| p.contains(".hidden.txt")));
        let with_hidden = search_workspace(&root_text, "agent", true, true, None, None).unwrap();
        assert!(with_hidden
            .groups
            .iter()
            .any(|g| g.relative_path.contains(".hidden.txt")));
    }

    #[test]
    fn depth_limit_and_clamp_line_keep_things_bounded() {
        let dir = root("depth");
        let root_text = dir.to_string_lossy().to_string();
        // 深度上限 0 ⇒ 只看根这一层（深层文件搜不到）
        let shallow = search_workspace(&root_text, "deep", true, false, Some(50), Some(0)).unwrap();
        assert!(shallow.groups.is_empty(), "深度 0 不该进子目录");
        // 深度够就能搜到
        let deep = search_workspace(&root_text, "deep", true, false, Some(50), Some(4)).unwrap();
        assert!(deep.groups.iter().any(|g| g.relative_path.contains("deep.txt")));

        // 跳行要夹：`agent-runner.txt` 的内容是 "nothing here\n" ⇒ **2 行**（末尾终止符多一个空行）——
        // 我第一版把这里写成 1，是用例写错，不是实现错
        assert_eq!(clamp_line(&root_text, "agent-runner.txt", 99).unwrap(), 2);
        assert_eq!(clamp_line(&root_text, "src/cafe.md", 2).unwrap(), 2);
        assert_eq!(clamp_line(&root_text, "src/cafe.md", 0).unwrap(), 1);
        // 越界与不存在的文件都要挡
        assert!(clamp_line(&root_text, "../outside.txt", 1).is_err());
        assert!(clamp_line(&root_text, "nope.txt", 1).is_err());
    }
}
