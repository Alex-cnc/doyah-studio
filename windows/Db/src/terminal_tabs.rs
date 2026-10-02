//! 终端**页签与会话**（不在 PTY 那一半）（FR-EDIT-29 / 计划 2.7；契约等价物：macOS 侧
//! `Core/TerminalTabs.swift`）
//!
//! 刻意只放「界面要展示、逻辑要判断」的字段：屏幕缓冲、PTY 句柄、环境都在表示层 ——
//! 这样这个类型能在单测里穷举（真开 shell 的路径无法在闭环里每条都跑）。
//!
//! 三条口径（都有单测）：
//! 1. **标题取前台进程名**，不是「终端 1 / 终端 2」—— 用户开多个页签是为了让它们干**不同的活**
//!    （`psql` / `npm` / `pwsh`），编号对他没有信息量。
//! 2. **认不出就没有标题**（`None`），兜底词由界面从语言表取 ——
//!    不拿路径或空串硬凑一个看着像名字的东西（领域层不出用户可见文案）。
//! 3. **清洗只做一次**：标题要画进单行窄条，所以换行 / 制表 / 连续空白一律收成一个空格、
//!    控制字符丢掉、超长截断 —— 否则页签头会被撑破或出现竖排。
//!
//! 还有一条最要紧的：**页签 id 单调递增，关掉中间的页签也不重号** ——
//! 重号会让「切到第 3 个」指到另一个会话，而用户看到的是「我明明切的是它」。

/// 标题长度上限（页签头是窄条：超出部分对用户没价值，还会把别的页签挤掉）。
pub const TITLE_LIMIT: usize = 24;
/// 超长时补的省略号。
pub const TITLE_ELLIPSIS: &str = "…";

/// 标题清洗：空白收成一个空格、丢掉控制字符、去首尾空白、超长截断；
/// 洗不出东西来返回 `None`（**不拿空串硬凑**）。
pub fn sanitize_title(raw: &str) -> Option<String> {
    let mut cleaned = String::new();
    let mut last_was_space = false;
    for ch in raw.chars() {
        // **空白（含换行 / 制表）统一收成一个空格**：先判空白，再判其它控制字符。
        // 反过来写的话换行会先被"控制字符"那条吞掉 ⇒ `行1\n行2` 会粘成 `行1行2`
        // （我第一版就是这样，被用例抓出来了）。
        if ch.is_whitespace() {
            if !last_was_space {
                cleaned.push(' ');
                last_was_space = true;
            }
            continue;
        }
        if ch.is_control() {
            continue;
        }
        cleaned.push(ch);
        last_was_space = false;
    }
    let trimmed = cleaned.trim();
    if trimmed.is_empty() {
        return None;
    }
    let chars: Vec<char> = trimmed.chars().collect();
    if chars.len() > TITLE_LIMIT {
        let head: String = chars[..TITLE_LIMIT].iter().collect();
        return Some(format!("{head}{TITLE_ELLIPSIS}"));
    }
    Some(trimmed.to_string())
}

/// 从可执行文件路径推标题：`C:\...\pwsh.exe` → `pwsh`；`-zsh`（login shell）→ `zsh`。
///
/// 拿不到可用名字（空串 / 只有分隔符）时返回 `None`。
pub fn derive_title(executable_path: Option<&str>) -> Option<String> {
    let path = executable_path?;
    // 路径**以分隔符结尾**说明"这里没有文件名"（`C:\\` / `/`）⇒ 直接 None，
    // 否则 `rsplit` 会把盘符 `C:` 当成进程名（我第一版就踩了）。
    if path.ends_with('/') || path.ends_with('\\') {
        return None;
    }
    let name = path
        .rsplit(['/', '\\'])
        .find(|part| !part.is_empty())?;
    // 去掉常见可执行后缀（Windows）与前导的 `-`（login shell 的写法）
    let name = name
        .strip_suffix(".exe")
        .or_else(|| name.strip_suffix(".cmd"))
        .or_else(|| name.strip_suffix(".bat"))
        .unwrap_or(name);
    let name = name.trim_start_matches('-');
    sanitize_title(name)
}

/// 页签的会话状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind", content = "code")]
pub enum SessionState {
    /// 会话在跑
    Running,
    /// shell 已退出（界面标「已退出」并给重启入口）；拿不到退出码时是 `Exited(None)`
    Exited(Option<i32>),
}

/// 一个终端页签（**与 PTY 无关的那一半**）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Tab {
    /// **单调递增**的标识（关掉中间的页签也不重号）
    pub id: u64,
    /// 这个页签启动的 shell（兜底标题 + 判断"前台的到底是不是 shell 自己"）
    pub shell_path: String,
    /// 用户重命名（`None` = 用前台进程名）
    pub custom_title: Option<String>,
    /// 前台进程的可执行文件路径（拿不到就是 `None`）
    pub foreground_process: Option<String>,
    pub state: SessionState,
}

impl Tab {
    /// 界面要显示的标题：**用户重命名 > 前台进程名 > `None`**（兜底词由界面出）。
    pub fn title(&self) -> Option<String> {
        if let Some(custom) = &self.custom_title {
            return sanitize_title(custom);
        }
        derive_title(self.foreground_process.as_deref())
    }

    /// 前台进程是不是 shell 自己（是的话标题就用 shell 名）。
    pub fn running_shell_only(&self) -> bool {
        match (&self.foreground_process, &self.shell_path) {
            (Some(foreground), shell) => foreground.eq_ignore_ascii_case(shell),
            (None, _) => true,
        }
    }

    pub const fn is_running(&self) -> bool {
        matches!(self.state, SessionState::Running)
    }
}

/// 页签集合。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Tabs {
    pub tabs: Vec<Tab>,
    pub selected: Option<u64>,
    /// 下一个要分配的 id（**只增不减**）
    next_id: u64,
    /// 默认 shell（新建页签时用）
    pub default_shell: String,
}

impl Tabs {
    /// 建一个集合（**开机就有一个页签** —— 空终端窗口是没意义的）。
    pub fn new(shell_path: &str) -> Self {
        let mut tabs = Self {
            tabs: Vec::new(),
            selected: None,
            next_id: 1,
            default_shell: shell_path.to_string(),
        };
        tabs.new_tab(None);
        tabs
    }

    /// 新建页签并选中；返回新页签的 id。
    pub fn new_tab(&mut self, shell_path: Option<&str>) -> u64 {
        let id = self.next_id;
        self.next_id += 1;
        let shell = shell_path.unwrap_or(&self.default_shell).to_string();
        self.tabs.push(Tab {
            id,
            shell_path: shell,
            custom_title: None,
            foreground_process: None,
            state: SessionState::Running,
        });
        self.selected = Some(id);
        id
    }

    /// 关闭页签：**关掉最后一个就返回 false**（终端没有"零个页签"这一态 ——
    /// 界面应当改成"关掉整个面板"，而不是留一个空壳）。
    pub fn close(&mut self, id: u64) -> bool {
        let Some(index) = self.tabs.iter().position(|tab| tab.id == id) else {
            return false;
        };
        if self.tabs.len() <= 1 {
            return false;
        }
        self.tabs.remove(index);
        if self.selected == Some(id) {
            // 选中项落到**右边那个**；没有就左边（与工作区页签同一口径）
            let fallback = index.min(self.tabs.len() - 1);
            self.selected = Some(self.tabs[fallback].id);
        }
        true
    }

    pub fn select(&mut self, id: u64) -> bool {
        if self.tabs.iter().any(|tab| tab.id == id) {
            self.selected = Some(id);
            return true;
        }
        false
    }

    /// 按**序号**（1 起）选中：`Ctrl+1` 之类。
    pub fn select_numbered(&mut self, number: u64) -> bool {
        if number == 0 {
            return false;
        }
        match self.tabs.get((number - 1) as usize) {
            Some(tab) => {
                self.selected = Some(tab.id);
                true
            }
            None => false,
        }
    }

    /// 选下一个（**到末尾停住，不绕回** —— 绕回会让"按几次到底"不可数）。
    pub fn select_next(&mut self) -> bool {
        let Some(current) = self.selected else { return false };
        let Some(index) = self.tabs.iter().position(|tab| tab.id == current) else {
            return false;
        };
        if index + 1 < self.tabs.len() {
            self.selected = Some(self.tabs[index + 1].id);
            return true;
        }
        false
    }

    /// 选上一个（同样不绕回）。
    pub fn select_previous(&mut self) -> bool {
        let Some(current) = self.selected else { return false };
        let Some(index) = self.tabs.iter().position(|tab| tab.id == current) else {
            return false;
        };
        if index > 0 {
            self.selected = Some(self.tabs[index - 1].id);
            return true;
        }
        false
    }

    /// 重命名（**空名字等于取消重命名**，回到前台进程名）。
    pub fn rename(&mut self, id: u64, raw: &str) -> bool {
        let Some(tab) = self.tabs.iter_mut().find(|tab| tab.id == id) else {
            return false;
        };
        tab.custom_title = sanitize_title(raw);
        true
    }

    /// 前台进程变了（终端每收到一次 shell 集成提示就调一次）。
    pub fn set_foreground_process(&mut self, id: u64, path: Option<&str>) -> bool {
        let Some(tab) = self.tabs.iter_mut().find(|tab| tab.id == id) else {
            return false;
        };
        tab.foreground_process = path.map(str::to_string);
        true
    }

    /// 会话退出（界面据此标「已退出」并给重启入口）。
    pub fn mark_exited(&mut self, id: u64, code: Option<i32>) -> bool {
        let Some(tab) = self.tabs.iter_mut().find(|tab| tab.id == id) else {
            return false;
        };
        tab.state = SessionState::Exited(code);
        true
    }

    pub fn selected_tab(&self) -> Option<&Tab> {
        let id = self.selected?;
        self.tabs.iter().find(|tab| tab.id == id)
    }

    /// 界面要显示的标题列表（`None` = 该页签用兜底词）—— **顺序与页签顺序一致**。
    pub fn titles(&self) -> Vec<Option<String>> {
        self.tabs.iter().map(Tab::title).collect()
    }
}

/// 快捷键动作（键位映射由界面做，**这里只管语义**）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TabCommand {
    New,
    Close,
    Next,
    Previous,
    /// `Ctrl+1..9`
    SelectNumbered(u64),
}

/// 执行一条页签命令；返回"是否真的做了"（**做不到就说做不到**，界面据此决定要不要提示）。
pub fn perform(tabs: &mut Tabs, command: TabCommand) -> bool {
    match command {
        TabCommand::New => {
            tabs.new_tab(None);
            true
        }
        TabCommand::Close => match tabs.selected {
            Some(id) => tabs.close(id),
            None => false,
        },
        TabCommand::Next => tabs.select_next(),
        TabCommand::Previous => tabs.select_previous(),
        TabCommand::SelectNumbered(number) => tabs.select_numbered(number),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn title_sanitising_collapses_whitespace_and_drops_control_chars() {
        assert_eq!(sanitize_title("  pwsh  "), Some("pwsh".to_string()));
        // 换行 / 制表 / 连续空白 ⇒ 一个空格（页签头是窄条，否则会被撑破）
        assert_eq!(sanitize_title("a\n\tb   c"), Some("a b c".to_string()));
        assert_eq!(sanitize_title("行1\n行2"), Some("行1 行2".to_string()));
        // 洗不出东西来 ⇒ None（**不拿空串硬凑**）
        assert_eq!(sanitize_title("   "), None);
        assert_eq!(sanitize_title("\n\t"), None);
        assert_eq!(sanitize_title(""), None);
        // 超长截断 + 省略号
        let long = "x".repeat(TITLE_LIMIT + 10);
        let cleaned = sanitize_title(&long).unwrap();
        assert_eq!(cleaned.chars().count(), TITLE_LIMIT + 1);
        assert!(cleaned.ends_with(TITLE_ELLIPSIS));
        // 控制字符丢掉但**不吞掉旁边的正常字符**
        assert_eq!(sanitize_title("a\u{7}b"), Some("ab".to_string()));
    }

    #[test]
    fn title_derives_from_executable_path_for_both_separators() {
        assert_eq!(derive_title(Some("C:\\Program Files\\PowerShell\\pwsh.exe")), Some("pwsh".to_string()));
        assert_eq!(derive_title(Some("/bin/zsh")), Some("zsh".to_string()));
        assert_eq!(derive_title(Some("-zsh")), Some("zsh".to_string()), "login shell 的前导 - 要去掉");
        assert_eq!(derive_title(Some("cmd.exe")), Some("cmd".to_string()));
        // 拿不到可用名字 ⇒ None
        assert_eq!(derive_title(None), None);
        assert_eq!(derive_title(Some("")), None);
        assert_eq!(derive_title(Some("/")), None);
        assert_eq!(derive_title(Some("C:\\")), None);
    }

    #[test]
    fn ids_are_monotonic_and_never_reused_after_closing() {
        // **这条最要紧**：重号会让"切到第 3 个"指到另一个会话，用户看到的是"我明明切的是它"
        let mut tabs = Tabs::new("pwsh.exe");
        let first = tabs.tabs[0].id;
        let second = tabs.new_tab(None);
        let third = tabs.new_tab(None);
        assert_eq!((first, second, third), (1, 2, 3));
        // 关掉中间的，再开一个 ⇒ id 是 4，**不是回填 2**
        assert!(tabs.close(second));
        let fourth = tabs.new_tab(None);
        assert_eq!(fourth, 4);
        assert!(!tabs.tabs.iter().any(|tab| tab.id == second), "关掉的 id 不该复活");
    }

    #[test]
    fn closing_the_last_tab_is_refused() {
        let mut tabs = Tabs::new("pwsh.exe");
        let only = tabs.tabs[0].id;
        assert!(!tabs.close(only), "终端没有零个页签这一态");
        assert_eq!(tabs.tabs.len(), 1);
        // 不存在的 id 也返回 false
        assert!(!tabs.close(999));
    }

    #[test]
    fn selection_falls_to_the_right_then_left() {
        let mut tabs = Tabs::new("pwsh.exe");
        let a = tabs.tabs[0].id;
        let b = tabs.new_tab(None);
        let c = tabs.new_tab(None);
        // 选中中间那个再关掉 ⇒ 落到右边那个
        assert!(tabs.select(b));
        assert!(tabs.close(b));
        assert_eq!(tabs.selected, Some(c));
        // 关掉最后一个（选中它）⇒ 落到左边
        assert!(tabs.close(c));
        assert_eq!(tabs.selected, Some(a));
        assert_eq!(tabs.tabs.len(), 1);
    }

    #[test]
    fn next_and_previous_stop_at_the_ends_instead_of_wrapping() {
        let mut tabs = Tabs::new("pwsh.exe");
        let a = tabs.tabs[0].id;
        let b = tabs.new_tab(None);
        assert_eq!(tabs.selected, Some(b));
        // 已经在末尾 ⇒ 再"下一个"返回 false（**不绕回**）
        assert!(!tabs.select_next());
        assert_eq!(tabs.selected, Some(b));
        // 上一个能走
        assert!(tabs.select_previous());
        assert_eq!(tabs.selected, Some(a));
        // 已经在开头 ⇒ 再"上一个"返回 false
        assert!(!tabs.select_previous());
    }

    #[test]
    fn numbered_selection_is_one_based_and_reports_failure() {
        let mut tabs = Tabs::new("pwsh.exe");
        let a = tabs.tabs[0].id;
        tabs.new_tab(None);
        assert!(tabs.select_numbered(1));
        assert_eq!(tabs.selected, Some(a));
        assert!(tabs.select_numbered(2));
        // 越界 / 0 ⇒ false
        assert!(!tabs.select_numbered(9));
        assert!(!tabs.select_numbered(0));
    }

    #[test]
    fn titles_prefer_custom_then_foreground_process() {
        let mut tabs = Tabs::new("C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe");
        let id = tabs.tabs[0].id;
        // 一开始没有前台进程信息 ⇒ 没有标题（界面用兜底词）
        assert_eq!(tabs.tabs[0].title(), None);
        // 前台进程来了 ⇒ 用它
        assert!(tabs.set_foreground_process(id, Some("C:\\Program Files\\PostgreSQL\\bin\\psql.exe")));
        assert_eq!(tabs.tabs[0].title(), Some("psql".to_string()));
        // 用户重命名优先
        assert!(tabs.rename(id, "数据库"));
        assert_eq!(tabs.tabs[0].title(), Some("数据库".to_string()));
        // 空名字 = 取消重命名 ⇒ 回到前台进程名
        assert!(tabs.rename(id, "   "));
        assert_eq!(tabs.tabs[0].title(), Some("psql".to_string()));
        // 重命名也要清洗（页签头是窄条）
        assert!(tabs.rename(id, "多行\n标题"));
        assert_eq!(tabs.tabs[0].title(), Some("多行 标题".to_string()));
    }

    #[test]
    fn exit_state_is_reported_with_or_without_a_code() {
        let mut tabs = Tabs::new("pwsh.exe");
        let id = tabs.tabs[0].id;
        assert!(tabs.tabs[0].is_running());
        assert!(tabs.mark_exited(id, Some(1)));
        assert_eq!(tabs.tabs[0].state, SessionState::Exited(Some(1)));
        assert!(!tabs.tabs[0].is_running());
        // 拿不到退出码也要能标"已退出"
        let second = tabs.new_tab(None);
        assert!(tabs.mark_exited(second, None));
        assert_eq!(tabs.tabs[1].state, SessionState::Exited(None));
        // 不存在的 id ⇒ false
        assert!(!tabs.mark_exited(999, Some(0)));
    }

    #[test]
    fn perform_reports_whether_it_actually_did_something() {
        let mut tabs = Tabs::new("pwsh.exe");
        assert!(perform(&mut tabs, TabCommand::New));
        assert_eq!(tabs.tabs.len(), 2);
        assert!(perform(&mut tabs, TabCommand::Previous));
        assert!(perform(&mut tabs, TabCommand::Next));
        assert!(perform(&mut tabs, TabCommand::SelectNumbered(1)));
        // 关到只剩一个 ⇒ 再关返回 false（界面据此改成"关掉整个面板"）
        assert!(perform(&mut tabs, TabCommand::Close));
        assert!(!perform(&mut tabs, TabCommand::Close));
        assert_eq!(tabs.tabs.len(), 1);
    }

    #[test]
    fn running_shell_only_detects_the_shell_itself() {
        let mut tabs = Tabs::new("pwsh.exe");
        let id = tabs.tabs[0].id;
        // 没有前台信息 ⇒ 当"只有 shell"
        assert!(tabs.tabs[0].running_shell_only());
        tabs.set_foreground_process(id, Some("pwsh.exe"));
        assert!(tabs.tabs[0].running_shell_only());
        tabs.set_foreground_process(id, Some("psql.exe"));
        assert!(!tabs.tabs[0].running_shell_only());
        // 标题列表：顺序与页签一致、没有标题的给 None
        let titles = tabs.titles();
        assert_eq!(titles.len(), 1);
        assert_eq!(titles[0], Some("psql".to_string()));
    }
}
