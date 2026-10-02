//! 工作区页签与「最近打开」（FR-EDIT-35 / 36；契约等价物：macOS 侧
//! `Core/WorkspaceTab.swift` + `Core/WorkspaceHistory.swift`）
//!
//! 三条口径（照抄对侧，一条都不许松）：
//! ① **页签另起类型，不复用查询页签**：查询页签背的是 SQL 执行语义（连接 / 结果 / 事务态），
//!    把"打开一个 JS 文件"塞进去，等于给一个已承担执行语义的结构再加一套无关状态；
//! ② **`is_dirty` 由内容比出来**，不另维护一个布尔 —— 布尔迟早与内容不一致；
//! ③ **同一路径只开一个页签**：开成两个、改一边存另一边，是这类编辑器最经典的丢改动方式。

use std::path::Path;

/// 语言标识（**只给键，不给文案**：文案在界面层的语言表里）。
///
/// 本侧现在只需要"认得出是什么语言"，识别规则照对侧 `TextLanguage.detect(path:)` 的**行为**
/// 重建（后缀 → 语言），但**只覆盖 Windows 侧 2.2 段要用的那几种**；其余一律 `PlainText`，
/// 宁可当纯文本，也不猜错（猜错会按错的语法上色，比不上色更误导）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TextLanguage {
    PlainText,
    Markdown,
    Rust,
    TypeScript,
    JavaScript,
    Json,
    Toml,
    Yaml,
    Sql,
    Shell,
    Html,
    Css,
}

impl TextLanguage {
    /// 语言键（界面文案由调用方按语言表取）。
    pub const fn key(self) -> &'static str {
        match self {
            TextLanguage::PlainText => "lang.plainText",
            TextLanguage::Markdown => "lang.markdown",
            TextLanguage::Rust => "lang.rust",
            TextLanguage::TypeScript => "lang.typescript",
            TextLanguage::JavaScript => "lang.javascript",
            TextLanguage::Json => "lang.json",
            TextLanguage::Toml => "lang.toml",
            TextLanguage::Yaml => "lang.yaml",
            TextLanguage::Sql => "lang.sql",
            TextLanguage::Shell => "lang.shell",
            TextLanguage::Html => "lang.html",
            TextLanguage::Css => "lang.css",
        }
    }

    /// 由路径推断语言（大小写不敏感；认不出就是 `PlainText`）。
    pub fn detect(path: &str) -> Self {
        let name = file_name(path).to_ascii_lowercase();
        // 特例：先看整名（`Cargo.toml` 之类靠后缀也能中，但 `Dockerfile` 之类没有后缀）
        if name == "dockerfile" || name == "makefile" {
            return TextLanguage::Shell;
        }
        let ext = name.rsplit_once('.').map(|(_, ext)| ext).unwrap_or("");
        match ext {
            "md" | "markdown" => TextLanguage::Markdown,
            "rs" => TextLanguage::Rust,
            "ts" | "tsx" | "mts" | "cts" => TextLanguage::TypeScript,
            "js" | "jsx" | "mjs" | "cjs" => TextLanguage::JavaScript,
            "json" | "jsonc" => TextLanguage::Json,
            "toml" => TextLanguage::Toml,
            "yaml" | "yml" => TextLanguage::Yaml,
            "sql" => TextLanguage::Sql,
            "sh" | "bash" | "zsh" | "ps1" | "bat" | "cmd" => TextLanguage::Shell,
            "html" | "htm" | "vue" | "svelte" => TextLanguage::Html,
            "css" | "scss" | "less" => TextLanguage::Css,
            _ => TextLanguage::PlainText,
        }
    }
}

/// 路径最后一段（`/` 与 `\` 都认：本侧要处理两种写法）。
///
/// 为什么不用 `Path::file_name()`：它按**平台**解析分隔符，Windows 上遇到 `/` 也能认，
/// 但我们的输入里两种都可能出现（用户粘贴的路径、POSIX 风格的相对路径）⇒ 显式两种都切更稳。
pub fn file_name(path: &str) -> String {
    let trimmed = path.trim_end_matches(['/', '\\']);
    match trimmed.rsplit(['/', '\\']).next() {
        Some(name) if !name.is_empty() => name.to_string(),
        _ => trimmed.to_string(),
    }
}

/// 一个工作区页签。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Tab {
    pub id: String,
    /// 页签标题（文件页 = 文件名；**Home 页由调用方从语言表取文案** —— 本层不写死任何文案）。
    pub title: String,
    /// 文件路径；`None` = **Home 欢迎页**（工作区的默认页签）。
    pub path: Option<String>,
    pub language: TextLanguage,
    pub content: String,
    /// 上次读盘 / 存盘时的内容 —— **脏标记由它比出来**，不另存布尔。
    pub saved_content: String,
}

impl Tab {
    /// 打开一个文件页签。
    pub fn file(id: impl Into<String>, path: impl Into<String>, content: impl Into<String>) -> Self {
        let path = path.into();
        let content = content.into();
        Self {
            id: id.into(),
            title: tab_title(&path),
            language: TextLanguage::detect(&path),
            path: Some(path),
            saved_content: content.clone(),
            content,
        }
    }

    /// Home 页签（**标题由调用方传入**：Core 里不出现展示文案）。
    pub fn home(id: impl Into<String>, title: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            title: title.into(),
            path: None,
            language: TextLanguage::PlainText,
            content: String::new(),
            saved_content: String::new(),
        }
    }

    pub fn is_home(&self) -> bool {
        self.path.is_none()
    }

    /// 有未保存改动（**比出来的**，不是另一个字段）。
    pub fn is_dirty(&self) -> bool {
        self.content != self.saved_content
    }

    /// 存盘成功：把"已保存内容"对齐到当前内容。
    pub fn mark_saved(&mut self) {
        self.saved_content = self.content.clone();
    }
}

/// 页签栏上显示的名字 = 路径最后一段（空就退回整条路径）。
pub fn tab_title(path: &str) -> String {
    let name = file_name(path);
    if name.is_empty() {
        path.to_string()
    } else {
        name
    }
}

/// 打开一个文件：已开着就**复用**（返回它的 id），没开过就追加到末尾。
///
/// 返回 `(tabs, selected_id)`。
pub fn opening(tabs: Vec<Tab>, id: impl Into<String>, path: &str, content: &str) -> (Vec<Tab>, String) {
    // 先取出 id（借用结束），再决定要不要 move `tabs`
    let existing = tabs.iter().find(|t| t.path.as_deref() == Some(path)).map(|t| t.id.clone());
    if let Some(existing_id) = existing {
        return (tabs, existing_id);
    }
    let tab = Tab::file(id, path, content);
    let id = tab.id.clone();
    (tabs.into_iter().chain(std::iter::once(tab)).collect(), id)
}

/// 关闭一个页签：**Home 关不掉**（它是工作区的落脚点，关了就没有默认页了）。
pub fn closing(tabs: &[Tab], id: &str) -> Vec<Tab> {
    tabs.iter().filter(|t| t.id != id || t.is_home()).cloned().collect()
}

/// 选中项在关闭之后落到谁身上：**优先右边那个**，没有就左边，都没有就 `None`。
///
/// 若当前选中项不是被关的那个、且它还在 ⇒ 保持不动。
pub fn selection_after_closing(tabs: &[Tab], closing_id: &str, selected: Option<&str>) -> Option<String> {
    let Some(index) = tabs.iter().position(|t| t.id == closing_id) else {
        return selected.map(str::to_string);
    };
    let remaining = closing(tabs, closing_id);
    if let Some(selected) = selected {
        if remaining.iter().any(|t| t.id == selected) {
            return Some(selected.to_string());
        }
    }
    if remaining.is_empty() {
        return None;
    }
    let fallback = index.min(remaining.len() - 1);
    Some(remaining[fallback].id.clone())
}

// ── 「最近打开」两份清单（Home 欢迎页要用）──────────────────────────────────────────

/// 一条"最近打开"记录。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryEntry {
    pub path: String,
    /// 时刻（ISO-8601 字符串：跨端可读优先于类型精确，与连接配置同一取舍）。
    pub opened_at: String,
}

impl HistoryEntry {
    /// 显示名 = 最后一段（Home 上不展示整条长路径）。
    pub fn display_name(&self) -> String {
        file_name(&self.path)
    }
}

/// 文件清单上限（欢迎页是"回到上次"，不是历史博物馆）。
pub const FILE_HISTORY_LIMIT: usize = 20;
/// 工作区清单上限。
pub const WORKSPACE_HISTORY_LIMIT: usize = 10;

/// Home 页的两份清单：**文件**与**工作区目录**。
///
/// 规则刻意简单且可单测：同一路径只留一条（重复打开只是**置顶**）、最近的在前、各有限额。
/// **不存内容**：只记路径与时间 —— 存内容会让这个文件变成代码库的副本。
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct History {
    #[serde(default)]
    pub files: Vec<HistoryEntry>,
    #[serde(default)]
    pub workspaces: Vec<HistoryEntry>,
    /// **上次打开的工作区根**（会话恢复用）。
    ///
    /// 为什么单列一项而不是"取 `workspaces[0]`"：两者语义不同 —— 关掉当前工作区**不该**
    /// 等于删掉"最近打开"里的那条记录。混成一个字段，"关掉"就变成了"删记录"。
    #[serde(default)]
    pub current_root: Option<String>,
    /// **上次开着的页签**（只记路径，按顺序）—— 会话恢复用。
    ///
    /// **不记内容**：内容以盘上的为准（记内容是"代码库副本"的老问题：体积、陈旧、
    /// 以及"我到底在编辑哪一份"）。恢复时**按路径重新读盘**；盘上没有的路径**跳过并报出来**。
    #[serde(default)]
    pub open_tabs: Vec<String>,
    /// **每个页签的光标位置**（相对路径 → 锚）—— 2.3「重启后光标回来」。
    ///
    /// 存的是**行号 + 行内偏移 + 那一行开头的锚**（不是整份文件的字节偏移：文件开头多一行就全错）。
    /// 键与 `open_tabs` 的路径一致；页签关掉时对应项**一并清掉**（不留孤儿）。
    #[serde(default)]
    pub cursors: std::collections::BTreeMap<String, crate::cursor::CursorAnchor>,
}

impl History {
    /// 记一次"打开了这个工作区"：既进"最近打开"清单，也记为**当前根**（会话恢复用）。
    pub fn opened_workspace(mut self, path: &str, at: &str) -> Self {
        self = self.recording_workspace(path, at);
        let trimmed = path.trim();
        if !trimmed.is_empty() {
            self.current_root = Some(trimmed.to_string());
        }
        self
    }

    /// **关掉**当前工作区：只清"当前根"，**保留**"最近打开"清单里的记录。
    ///
    /// 页签也一并清掉（工作区都关了，还记着它的页签没意义）。
    pub fn closed_workspace(mut self) -> Self {
        self.current_root = None;
        self.open_tabs.clear();
        self.cursors.clear();
        self
    }

    /// 记下"当前开着的页签"（只记路径，去重、保持顺序）。
    pub fn recording_open_tabs(mut self, paths: &[String]) -> Self {
        let mut seen: Vec<String> = Vec::new();
        for path in paths {
            let trimmed = path.trim();
            if trimmed.is_empty() {
                continue;
            }
            if !seen.iter().any(|p| p == trimmed) {
                seen.push(trimmed.to_string());
            }
        }
        self.open_tabs = seen;
        self
    }

    /// 记一次"打开了文件"。
    pub fn recording_file(mut self, path: &str, at: &str) -> Self {
        self.files = update(&self.files, path, at, FILE_HISTORY_LIMIT);
        self
    }

    /// 记一次"切换了工作区"。
    pub fn recording_workspace(mut self, path: &str, at: &str) -> Self {
        self.workspaces = update(&self.workspaces, path, at, WORKSPACE_HISTORY_LIMIT);
        self
    }

    pub fn removing_file(mut self, path: &str) -> Self {
        self.files.retain(|e| e.path != path);
        self
    }

    pub fn removing_workspace(mut self, path: &str) -> Self {
        self.workspaces.retain(|e| e.path != path);
        self
    }
}

fn update(entries: &[HistoryEntry], path: &str, at: &str, limit: usize) -> Vec<HistoryEntry> {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return entries.to_vec();
    }
    let mut result: Vec<HistoryEntry> = entries.iter().filter(|e| e.path != trimmed).cloned().collect();
    result.insert(
        0,
        HistoryEntry {
            path: trimmed.to_string(),
            opened_at: at.to_string(),
        },
    );
    result.truncate(limit);
    result
}

/// 路径分隔符归一：`\` → `/`（本侧内部**一律用 `/`**：跨平台一致，也便于当 id 用）。
pub fn normalize_separators(path: &str) -> String {
    path.replace('\\', "/")
}

/// 规范化"用户 / 缓存里拿到的相对路径"：去掉 `.` 与空段、吃掉 `..`。
///
/// 返回 `None` 表示**不安全**（`..` 逃逸到工作区外），调用方应当**拒绝**而不是"尽力而为"。
pub fn normalized_relative_path(raw: &str) -> Option<String> {
    let mut components: Vec<&str> = Vec::new();
    // 先落成局部变量：`normalize_separators(raw).split('/')` 的临时 String 会在本语句结束就释放，
    // 而 components 借用它到后面（E0716）。
    let normalized = normalize_separators(raw);
    for component in normalized.split('/') {
        match component {
            "" | "." => continue,
            ".." => {
                if components.pop().is_none() {
                    return None;
                }
            }
            other => components.push(other),
        }
    }
    if components.is_empty() {
        None
    } else {
        Some(components.join("/"))
    }
}

/// **路径必须落在工作区内**（FR-EDIT-32 的安全约束）。
///
/// 刻意按**路径分量**比较而不是字符串前缀：后者会把 `D:/ws-evil` 误判成 `D:/ws` 的子路径 ——
/// 这是路径校验里最经典的一个坑。
///
/// Windows 上的额外两条（对侧在 macOS 上遇不到，本侧必须处理）：
/// ① **盘符大小写不敏感**（`d:/ws` 与 `D:/WS` 是同一处）⇒ 分量比较时 ASCII 不分大小写；
/// ② **两种分隔符混用**（`D:\ws/sub`）⇒ 先归一。
pub fn is_contained(candidate_path: &str, workspace_path: &str) -> bool {
    let candidate = path_components(candidate_path);
    let workspace = path_components(workspace_path);
    if candidate.len() < workspace.len() {
        return false;
    }
    let candidate_prefix: Vec<String> = candidate[..workspace.len()].iter().map(|s| s.to_lowercase()).collect();
    let workspace_lower: Vec<String> = workspace.iter().map(|s| s.to_lowercase()).collect();
    candidate_prefix == workspace_lower
}

/// 在给定工作区根下解析一个相对路径（`None` = 不安全或越界）。
///
/// 这是"打开文件 / 交给智能体读写"之前**必须**过的一道关：相对路径可能来自缓存、
/// 书签或模型输出，**不能信**。
pub fn resolve(relative_path: &str, workspace_path: &str) -> Option<String> {
    let normalized = normalized_relative_path(relative_path)?;
    let base = normalize_separators(workspace_path);
    let base = base.trim_end_matches('/');
    let candidate = format!("{base}/{normalized}");
    if is_contained(&candidate, workspace_path) {
        Some(candidate)
    } else {
        None
    }
}

/// 拆成路径分量（去掉 `.`、吃掉 `..`、丢了末尾分隔符；盘符保留原样）。
fn path_components(path: &str) -> Vec<String> {
    let normalized = normalize_separators(path);
    let mut out: Vec<String> = Vec::new();
    for component in normalized.split('/') {
        match component {
            "" | "." => continue,
            ".." => {
                out.pop();
            }
            other => out.push(other.to_string()),
        }
    }
    out
}

// ── 目录列举的**纯判定**（真正的 IO 在表示层）────────────────────────────────────────

/// 默认忽略名单：构建产物、依赖、版本库元数据、虚拟环境…
///
/// 这些目录动辄几万条，列进来既慢又没用；用户真要看得细可以关掉忽略
/// （`show_hidden` 只管点开头的隐藏文件 —— 两者是不同维度，故分开两个参数）。
pub const DEFAULT_IGNORED: &[&str] = &[
    ".build", ".build-cache", "DerivedData", "node_modules", ".git", ".svn", ".hg", ".DS_Store",
    "__pycache__", ".venv", "venv", ".tox", "target", "dist", ".next", ".nuxt", ".swiftpm",
    ".idea", ".vscode-test", "Pods", "Carthage",
];

/// 这一条要不要列出来（**纯判定**，不碰磁盘 ⇒ 可单测）。
pub fn should_list(name: &str, show_hidden: bool, ignored: &[&str]) -> bool {
    if ignored.iter().any(|i| *i == name) {
        return false;
    }
    if !show_hidden && name.starts_with('.') {
        return false;
    }
    true
}

/// 排序键：**目录在前、文件在后，同类按名称不区分大小写**（与访达 / VS Code 一致）。
/// 返回 `(是不是目录, 名称小写)` —— 调用方拿它 `sort_by_key` 即可。
pub fn sort_key(name: &str, kind: EntryKind) -> (u8, String) {
    let group = if kind == EntryKind::Directory { 0u8 } else { 1u8 };
    (group, name.to_lowercase())
}

/// 工作区里的一个条目。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum EntryKind {
    Directory,
    File,
    /// 符号链接：**只显示、不跟随** —— 跟随会带来环与"实际读到了工作区外面"两个问题。
    Symlink,
}

impl EntryKind {
    /// 可展开 = 目录（**符号链接即使指向目录也不展开**）。
    pub const fn is_expandable(self) -> bool {
        matches!(self, EntryKind::Directory)
    }
}

/// 由文件系统元数据判定条目类型（目录判定优先于"是不是链接"？不 —— 与对侧同序：
/// **先看是不是符号链接**，因为链接指向目录时我们仍不展开）。
pub fn entry_kind(is_symlink: bool, is_dir: bool) -> EntryKind {
    if is_symlink {
        EntryKind::Symlink
    } else if is_dir {
        EntryKind::Directory
    } else {
        EntryKind::File
    }
}

/// 相对路径（`None` = 不在该目录下）。两个入参都先归一分隔符 + 吃 `..`。
pub fn relative_path(target: &str, root: &str) -> Option<String> {
    let target_components = path_components(target);
    let root_components = path_components(root);
    if target_components.len() < root_components.len() {
        return None;
    }
    // 先把候选前缀小写化**存下来**再比：直接 `.iter().map(|s| s.to_lowercase())` 会在
    // 语句结束时把临时 String 丢掉，而比较还要借它（经典临时值坑）。
    let candidate_prefix: Vec<String> = target_components[..root_components.len()]
        .iter()
        .map(|s| s.to_lowercase())
        .collect();
    let root_lower: Vec<String> = root_components.iter().map(|s| s.to_lowercase()).collect();
    if candidate_prefix != root_lower {
        return None;
    }
    let rest = target_components[root_components.len()..].join("/");
    if rest.is_empty() {
        None
    } else {
        Some(rest)
    }
}

/// 便捷：把操作系统给的路径转成我们内部的规范形态。
pub fn to_internal(path: &Path) -> String {
    normalize_separators(&path.to_string_lossy())
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── 页签 ──────────────────────────────────────────────────────────────

    #[test]
    fn tab_title_is_the_last_component_for_both_separators() {
        assert_eq!(tab_title("/a/b/c.rs"), "c.rs");
        assert_eq!(tab_title("D:\\proj\\src\\main.rs"), "main.rs");
        assert_eq!(tab_title("C:/proj/README.md"), "README.md");
        assert_eq!(tab_title("no-separator.txt"), "no-separator.txt");
        // 结尾有分隔符也不出错
        assert_eq!(tab_title("/a/b/"), "b");
    }

    #[test]
    fn language_detection_covers_what_we_claim_and_defaults_to_plain_text() {
        assert_eq!(TextLanguage::detect("a/b/main.rs"), TextLanguage::Rust);
        assert_eq!(TextLanguage::detect("x.TS"), TextLanguage::TypeScript);
        assert_eq!(TextLanguage::detect("D:\\p\\app.vue"), TextLanguage::Html);
        assert_eq!(TextLanguage::detect("notes.md"), TextLanguage::Markdown);
        assert_eq!(TextLanguage::detect("config.yaml"), TextLanguage::Yaml);
        assert_eq!(TextLanguage::detect("Dockerfile"), TextLanguage::Shell);
        // 认不出 ⇒ 纯文本（**不猜**：猜错会按错的语法上色，比不上色更误导）
        assert_eq!(TextLanguage::detect("weird.zzz"), TextLanguage::PlainText);
        assert_eq!(TextLanguage::detect("noext"), TextLanguage::PlainText);
    }

    #[test]
    fn dirty_is_computed_from_content_not_stored() {
        let mut tab = Tab::file("1", "/a/b.txt", "hello");
        assert!(!tab.is_dirty());
        tab.content.push('!');
        assert!(tab.is_dirty(), "改了内容就该脏");
        tab.content = "hello".to_string();
        assert!(!tab.is_dirty(), "改回原样就不该脏（布尔字段做不到这条）");
        tab.content = "bye".to_string();
        tab.mark_saved();
        assert!(!tab.is_dirty());
        assert_eq!(tab.saved_content, "bye");
    }

    #[test]
    fn opening_the_same_file_reuses_its_tab() {
        let tabs = vec![Tab::home("h", "首页")];
        let (tabs, first) = opening(tabs, "t1", "/a/x.rs", "fn main() {}");
        let (tabs, second) = opening(tabs, "t2", "/a/x.rs", "fn main() {} // 重复打开");
        assert_eq!(tabs.len(), 2, "同一路径不该开成两个页签");
        assert_eq!(first, second, "第二次打开应当选中已有那个");
        assert_eq!(tabs[1].id, "t1");
    }

    #[test]
    fn home_tab_cannot_be_closed() {
        let tabs = vec![Tab::home("h", "首页"), Tab::file("f", "/a/x.rs", "")];
        let after = closing(&tabs, "h");
        // Home 关不掉 ⇒ 列表**原样**（我第一版把这条断言写成 1，是断言错、实现对）
        assert_eq!(after.len(), 2, "Home 关不掉：列表应当原样");
        assert!(after.iter().any(|t| t.id == "h"), "Home 还在");
        assert!(after.iter().any(|t| t.id == "f"), "另一个页签也在");
        let after = closing(&tabs, "f");
        assert_eq!(after.len(), 1);
        assert_eq!(after[0].id, "h");
    }

    #[test]
    fn selection_after_closing_prefers_the_right_neighbour() {
        let tabs = vec![
            Tab::home("h", "首页"),
            Tab::file("a", "/a", ""),
            Tab::file("b", "/b", ""),
            Tab::file("c", "/c", ""),
        ];
        // 关中间那个（选中它）⇒ 落到右边那个
        assert_eq!(selection_after_closing(&tabs, "b", Some("b")).as_deref(), Some("c"));
        // 关最后一个 ⇒ 落到左边那个
        assert_eq!(selection_after_closing(&tabs, "c", Some("c")).as_deref(), Some("b"));
        // 关的不是选中的那个 ⇒ 选中项不动
        assert_eq!(selection_after_closing(&tabs, "a", Some("c")).as_deref(), Some("c"));
        // 关掉一个不存在的 id ⇒ 保持原选中
        assert_eq!(selection_after_closing(&tabs, "zz", Some("a")).as_deref(), Some("a"));
        // 全部关完（Home 关不掉，所以用只有文件的列表）
        let only = vec![Tab::file("x", "/x", "")];
        assert_eq!(selection_after_closing(&only, "x", Some("x")), None);
    }

    #[test]
    fn tab_serialises_with_camel_case_and_round_trips() {
        let tab = Tab::file("id-1", "/a/b.rs", "fn main() {}");
        let text = serde_json::to_string(&tab).unwrap();
        assert!(text.contains("\"savedContent\""), "{text}");
        assert!(text.contains("\"plainText\"") || text.contains("\"rust\""), "{text}");
        let back: Tab = serde_json::from_str(&text).unwrap();
        assert_eq!(back, tab);
    }

    // ── 最近打开 ──────────────────────────────────────────────────────────

    #[test]
    fn history_dedupes_moves_to_top_and_trims() {
        let h = History::default()
            .recording_file("/a/one.rs", "2026-10-02T10:00:00Z")
            .recording_file("/a/two.rs", "2026-10-02T10:01:00Z");
        assert_eq!(h.files.len(), 2);
        assert_eq!(h.files[0].path, "/a/two.rs", "最近的在前");
        // 再打开一次 one.rs ⇒ 只置顶，不新增
        let h = h.recording_file("/a/one.rs", "2026-10-02T10:02:00Z");
        assert_eq!(h.files.len(), 2);
        assert_eq!(h.files[0].path, "/a/one.rs");
        assert_eq!(h.files[0].opened_at, "2026-10-02T10:02:00Z");
        assert_eq!(h.files[0].display_name(), "one.rs");
        // 空白路径不入账
        let h = h.recording_file("   ", "2026-10-02T10:03:00Z");
        assert_eq!(h.files.len(), 2);
        // 移除
        let h = h.removing_file("/a/one.rs");
        assert_eq!(h.files.len(), 1);
        assert_eq!(h.files[0].path, "/a/two.rs");
    }

    #[test]
    fn history_limits_are_enforced() {
        let mut h = History::default();
        for i in 0..25 {
            h = h.recording_file(&format!("/a/f{i}.rs"), "2026-10-02T10:00:00Z");
        }
        assert_eq!(h.files.len(), FILE_HISTORY_LIMIT);
        assert_eq!(h.files[0].path, "/a/f24.rs", "最新的必须还在");
        assert!(!h.files.iter().any(|e| e.path == "/a/f0.rs"), "最旧的被挤出");

        let mut w = History::default();
        for i in 0..15 {
            w = w.recording_workspace(&format!("D:/ws{i}"), "2026-10-02T10:00:00Z");
        }
        assert_eq!(w.workspaces.len(), WORKSPACE_HISTORY_LIMIT);
        // 两份清单互不干扰
        assert!(w.files.is_empty());
        assert_eq!(h.workspaces.len(), 0);
    }

    // ── 路径安全（这几条是"很容易写错又很难在界面上发现"的）────────────────

    #[test]
    fn containment_compares_components_not_string_prefixes() {
        // 经典坑：字符串前缀会把 ws-evil 当成 ws 的子路径
        assert!(!is_contained("/Users/me/ws-evil/x", "/Users/me/ws"));
        assert!(is_contained("/Users/me/ws/x", "/Users/me/ws"));
        assert!(is_contained("/Users/me/ws", "/Users/me/ws"));
        // 工作区比候选长 ⇒ 不是子路径
        assert!(!is_contained("/Users/me", "/Users/me/ws"));
    }

    #[test]
    fn containment_handles_windows_drive_case_and_mixed_separators() {
        assert!(is_contained("d:/ws/sub/file.txt", "D:/ws"));
        assert!(is_contained("D:\\ws\\sub\\file.txt", "D:/ws"));
        assert!(is_contained("D:/ws/sub/../file.txt", "D:/ws"), "`..` 在分量里被吃掉，仍在内");
        // 越界的 `..` 会被吃掉一层，结果落在工作区外 ⇒ 不包含
        assert!(!is_contained("D:/ws/../evil.txt", "D:/ws"));
        // 另一个盘符当然不算
        assert!(!is_contained("E:/ws/file.txt", "D:/ws"));
        assert!(!is_contained("D:/wsx/file.txt", "D:/ws"));
    }

    #[test]
    fn relative_and_resolve_round_trip_and_refuse_escapes() {
        assert_eq!(relative_path("D:/ws/sub/a.rs", "D:/ws").as_deref(), Some("sub/a.rs"));
        assert_eq!(relative_path("D:\\ws\\sub\\a.rs", "d:/WS").as_deref(), Some("sub/a.rs"));
        assert_eq!(relative_path("D:/other/a.rs", "D:/ws"), None);
        assert_eq!(relative_path("D:/ws", "D:/ws"), None, "自己不算自己的相对路径");

        assert_eq!(resolve("sub/a.rs", "D:/ws").as_deref(), Some("D:/ws/sub/a.rs"));
        assert_eq!(resolve("./sub//a.rs", "D:/ws").as_deref(), Some("D:/ws/sub/a.rs"));
        assert_eq!(resolve("sub/../a.rs", "D:/ws").as_deref(), Some("D:/ws/a.rs"));
        // 逃逸：明确拒绝（不是"尽力而为"）
        assert_eq!(resolve("../evil.txt", "D:/ws"), None);
        assert_eq!(resolve("sub/../../evil.txt", "D:/ws"), None);
        assert_eq!(resolve("", "D:/ws"), None);
        assert_eq!(normalized_relative_path("."), None);
        assert_eq!(normalized_relative_path("a/./b"), Some("a/b".to_string()));
    }

    // ── 目录列举的纯判定 ─────────────────────────────────────────────────

    #[test]
    fn ignore_and_hidden_rules_are_two_different_dimensions() {
        // 忽略名单命中 ⇒ 不列（哪怕它不以点开头）
        assert!(!should_list("node_modules", true, DEFAULT_IGNORED));
        assert!(!should_list("target", true, DEFAULT_IGNORED));
        // 点开头的隐藏项：默认不列，开了 show_hidden 才列
        assert!(!should_list(".env", false, DEFAULT_IGNORED));
        assert!(should_list(".env", true, DEFAULT_IGNORED));
        // `.git` 既在忽略名单、又是隐藏项 ⇒ 即便开了隐藏也不列
        assert!(!should_list(".git", true, DEFAULT_IGNORED));
        // 普通文件照列
        assert!(should_list("main.rs", false, DEFAULT_IGNORED));
    }

    #[test]
    fn directories_come_first_then_case_insensitive_name() {
        let mut items = vec![
            ("zeta.rs", EntryKind::File),
            ("Alpha", EntryKind::Directory),
            ("beta.rs", EntryKind::File),
            ("alpha2", EntryKind::Directory),
            ("link", EntryKind::Symlink),
        ];
        items.sort_by_key(|(name, kind)| sort_key(name, *kind));
        let order: Vec<&str> = items.iter().map(|(n, _)| *n).collect();
        // 目录在前（Alpha / alpha2，按不区分大小写排），然后是文件（beta.rs / zeta.rs），符号链接归"非目录"一组
        assert_eq!(order[0], "Alpha");
        assert_eq!(order[1], "alpha2");
        assert_eq!(order[2], "beta.rs");
        assert_eq!(order[3], "link");
        assert_eq!(order[4], "zeta.rs");
    }

    #[test]
    fn symlink_is_never_expandable_even_when_it_points_at_a_directory() {
        assert_eq!(entry_kind(true, true), EntryKind::Symlink);
        assert!(!entry_kind(true, true).is_expandable(), "符号链接不跟随");
        assert_eq!(entry_kind(false, true), EntryKind::Directory);
        assert!(entry_kind(false, true).is_expandable());
        assert_eq!(entry_kind(false, false), EntryKind::File);
    }

    // ── 会话恢复（当前根）────────────────────────────────────────────────

    #[test]
    fn opening_a_workspace_sets_current_root_and_records_it() {
        let h = History::default().opened_workspace("D:/ws", "2026-10-02T20:00:00Z");
        assert_eq!(h.current_root.as_deref(), Some("D:/ws"));
        assert_eq!(h.workspaces.len(), 1, "同时进「最近打开」清单");
        assert_eq!(h.workspaces[0].path, "D:/ws");
        // 空白路径不该把当前根清掉（它是"没给路径"，不是"关掉工作区"）
        let h = h.opened_workspace("   ", "2026-10-02T20:01:00Z");
        assert_eq!(h.current_root.as_deref(), Some("D:/ws"));
    }

    #[test]
    fn closing_a_workspace_clears_the_root_but_keeps_the_history() {
        let h = History::default()
            .opened_workspace("D:/ws", "2026-10-02T20:00:00Z")
            .closed_workspace();
        assert!(h.current_root.is_none(), "关掉之后没有当前根");
        assert_eq!(h.workspaces.len(), 1, "**关掉 ≠ 删记录**：最近打开里还在");
    }

    #[test]
    fn open_tabs_are_recorded_by_path_deduped_and_cleared_when_closing() {
        let h = History::default()
            .opened_workspace("D:/ws", "2026-10-02T20:00:00Z")
            .recording_open_tabs(&[
                "src/main.rs".to_string(),
                "  README.md  ".to_string(),
                "src/main.rs".to_string(), // 重复：只留一条
                String::new(),             // 空：不记
            ]);
        // 顺序保持、去重、trim
        assert_eq!(h.open_tabs, vec!["src/main.rs".to_string(), "README.md".to_string()]);
        // **不记内容**：这个结构里根本没有 content 字段（内容以盘上为准）
        let text = serde_json::to_string(&h).unwrap();
        assert!(!text.contains("content"), "历史里不该出现内容：{text}");
        // 关掉工作区 ⇒ 页签一并清掉；但最近打开清单仍在
        let closed = h.closed_workspace();
        assert!(closed.open_tabs.is_empty());
        assert_eq!(closed.workspaces.len(), 1);
        // 旧文件（没有 openTabs）也要读得进来
        let old = "{\"files\":[],\"workspaces\":[],\"currentRoot\":\"D:/ws\"}";
        let parsed: History = serde_json::from_str(old).unwrap();
        assert!(parsed.open_tabs.is_empty());
    }

    #[test]
    fn history_json_round_trips_and_tolerates_an_older_file() {
        let h = History::default().opened_workspace("D:/ws", "2026-10-02T20:00:00Z");
        let text = serde_json::to_string(&h).unwrap();
        assert!(text.contains("\"currentRoot\"") && text.contains("\"openTabs\""), "{text}");
        let back: History = serde_json::from_str(&text).unwrap();
        assert_eq!(back, h);
        // 旧文件（没有 currentRoot 那一项）也要读得进来 —— 会话恢复不该让老用户开不了工作区
        let old = "{\"files\":[],\"workspaces\":[]}";
        let parsed: History = serde_json::from_str(old).unwrap();
        assert!(parsed.current_root.is_none());
        assert!(parsed.workspaces.is_empty());
    }
}

impl History {
    /// 记下某个文件的光标位置（**只在该页签还开着时**才有意义）。
    pub fn recording_cursor(mut self, path: &str, anchor: crate::cursor::CursorAnchor) -> Self {
        let trimmed = path.trim();
        if !trimmed.is_empty() {
            self.cursors.insert(trimmed.to_string(), anchor);
        }
        self
    }

    /// 取某个文件上次的光标位置。
    pub fn cursor_for(&self, path: &str) -> Option<&crate::cursor::CursorAnchor> {
        self.cursors.get(path)
    }

    /// 页签集合变了之后**清掉孤儿光标**（已关掉的页签不该留着位置）。
    pub fn prune_cursors(mut self) -> Self {
        let open: std::collections::HashSet<&str> = self.open_tabs.iter().map(String::as_str).collect();
        self.cursors.retain(|path, _| open.contains(path.as_str()));
        self
    }
}

#[cfg(test)]
mod cursor_tests {
    use super::*;

    #[test]
    fn cursors_round_trip_and_orphans_are_pruned() {
        use crate::cursor::{CursorAnchor, Cursor};
        let anchor = CursorAnchor { line: 12, column: 3, line_prefix: "let x".to_string() };
        let h = History::default()
            .opened_workspace("D:/ws", "2026-10-02T20:00:00Z")
            .recording_open_tabs(&["a.rs".to_string(), "b.rs".to_string()])
            .recording_cursor("a.rs", anchor.clone());
        // 记下来了
        assert_eq!(h.cursor_for("a.rs"), Some(&anchor));
        assert!(h.cursor_for("b.rs").is_none());
        // 序列化往返（camelCase）
        let text = serde_json::to_string(&h).unwrap();
        assert!(text.contains("\"cursors\""), "{text}");
        let back: History = serde_json::from_str(&text).unwrap();
        assert_eq!(back, h);

        // 页签集合变了 ⇒ **孤儿光标要清掉**（已关掉的页签不该留着位置）
        let pruned = h.clone().recording_open_tabs(&["b.rs".to_string()]).prune_cursors();
        assert!(pruned.cursor_for("a.rs").is_none(), "a.rs 已不在页签里，光标不该留着");
        assert!(pruned.cursor_for("b.rs").is_none());

        // 关掉工作区 ⇒ 页签与光标一并清（最近打开清单仍在）
        let closed = h.closed_workspace();
        assert!(closed.cursors.is_empty());
        assert_eq!(closed.workspaces.len(), 1);
        assert_eq!(Cursor::new(0, 0).line, 1);
    }

    #[test]
    fn an_old_history_file_without_cursors_still_loads() {
        let old = "{\"files\":[],\"workspaces\":[],\"currentRoot\":\"D:/ws\",\"openTabs\":[\"a.rs\"]}";
        let parsed: History = serde_json::from_str(old).unwrap();
        assert!(parsed.cursors.is_empty(), "旧文件没有 cursors 也要读得进来");
        assert_eq!(parsed.open_tabs.len(), 1);
    }
}