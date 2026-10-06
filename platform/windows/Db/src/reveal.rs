//! 「在资源管理器 / 终端打开」的**纯逻辑**（FR-EDIT-42 / 计划 2.1 那条）
//!
//! 本模块**不启动任何进程**：只给出"该用哪个程序、带什么参数、指向哪个路径"。
//! 真正的启动在表示层 —— 这样"选哪个程序""文件要定位而不是打开目录"这些判定可单测。
//!
//! 三条口径：
//!   ① **文件用定位**（资源管理器把文件选中），目录才直接打开 —— 对文件"打开所在目录"是错的行为；
//!   ② **终端按可用性挑**：Windows Terminal → Windows PowerShell → 命令提示符，
//!      挑不到就**如实说挑不到**（不是"尽力而为地乱起一个"）；
//!   ③ **路径只许在工作区内**（与其它文件操作同一条安全线；本层只做字符串校验，
//!      解链接那一遍在表示层）。

/// 终端种类（也是"用哪个程序"）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TerminalKind {
    /// 资源管理器
    Explorer,
    /// Windows Terminal
    WindowsTerminal,
    /// Windows PowerShell
    PowerShell,
    /// 命令提示符（最后的兜底）
    CommandPrompt,
}

impl TerminalKind {
    /// 可执行文件（交给系统 PATH 解析）。
    pub const fn program(self) -> &'static str {
        match self {
            TerminalKind::Explorer => "explorer.exe",
            TerminalKind::WindowsTerminal => "wt.exe",
            TerminalKind::PowerShell => "powershell.exe",
            TerminalKind::CommandPrompt => "cmd.exe",
        }
    }
}

/// 用哪个程序、带什么参数、指向哪里。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RevealPlan {
    /// 可执行程序名（交给系统 PATH 解析）。
    pub program: String,
    pub args: Vec<String>,
    /// 工作目录（终端用；资源管理器不需要就为 `None`）。
    pub working_directory: Option<String>,
    /// 挑到的那个程序（界面据此说"用 xx 打开的"；程序名是技术串，不进语言表）。
    pub used: TerminalKind,
}

/// 终端的**优先顺序**（Windows Terminal 体验最好，命令提示符最保底）。
pub const TERMINAL_PREFERENCE: [TerminalKind; 3] = [
    TerminalKind::WindowsTerminal,
    TerminalKind::PowerShell,
    TerminalKind::CommandPrompt,
];

/// 从"哪些程序可用"里挑一个终端。`available` = 程序名（不区分大小写）是否在 PATH 上。
///
/// 一个都没有 ⇒ `None`（**如实说挑不到**，由调用方给一句人话，不硬起一个不存在的程序）。
pub fn pick_terminal(available: impl Fn(&str) -> bool) -> Option<TerminalKind> {
    TERMINAL_PREFERENCE
        .into_iter()
        .find(|kind| available(kind.program()))
}

/// 「在资源管理器里定位」的计划。
///
/// - **文件** ⇒ `explorer.exe /select,<完整路径>`（把文件选中）
/// - **目录** ⇒ `explorer.exe <完整路径>`（直接进去）
/// - **符号链接** ⇒ 与文件同办（我们**不跟随**链接，能在资源管理器里看到它本身就行）
pub fn explorer_plan(is_directory: bool, full_path: &str) -> RevealPlan {
    let args: Vec<String> = if is_directory {
        vec![full_path.to_string()]
    } else {
        // `/select,` 与路径**必须在同一个参数里**（分开写 explorer 会当成两个东西）
        vec![format!("/select,{full_path}")]
    };
    RevealPlan {
        program: TerminalKind::Explorer.program().to_string(),
        args,
        working_directory: None,
        used: TerminalKind::Explorer,
    }
}

/// 「在终端打开」的计划：终端**起始目录**设成那个目录（文件则用它的父目录）。
///
/// 挑不到任何终端 ⇒ `Err(试过的程序清单)`，调用方据此给一句"这台机器上没找到终端程序"。
pub fn terminal_plan(
    is_directory: bool,
    full_path: &str,
    parent_directory: &str,
    available: impl Fn(&str) -> bool,
) -> Result<RevealPlan, Vec<&'static str>> {
    let kind = match pick_terminal(available) {
        Some(kind) => kind,
        None => {
            return Err(TERMINAL_PREFERENCE.iter().map(|k| k.program()).collect());
        }
    };
    let directory = if is_directory {
        full_path.to_string()
    } else {
        parent_directory.to_string()
    };
    let args: Vec<String> = match kind {
        // Windows Terminal 的 `-d` = 起始目录
        TerminalKind::WindowsTerminal => vec!["-d".to_string(), directory.clone()],
        // PowerShell 起在目标目录（`-NoExit` 让人能看到窗口）
        TerminalKind::PowerShell => vec![
            "-NoExit".to_string(),
            "-Command".to_string(),
            format!("Set-Location -LiteralPath '{}'", directory.replace('\'', "''")),
        ],
        // 命令提示符：`/k` 保持窗口
        _ => vec!["/k".to_string(), format!("cd /d \"{directory}\"")],
    };
    let program = kind.program().to_string();
    Ok(RevealPlan {
        program,
        args,
        working_directory: Some(directory),
        used: kind,
    })
}

/// 路径校验：**只许工作区内**（字符串层；解链接那一遍在表示层）。
pub fn ensure_inside(workspace_root: &str, candidate: &str) -> Result<(), String> {
    if crate::workspace::is_contained(candidate, workspace_root) {
        Ok(())
    } else {
        Err(format!("拒绝越界路径：{candidate}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn files_are_located_not_opened_as_directories() {
        let plan = explorer_plan(false, r"D:\ws\a.txt");
        assert_eq!(plan.program, "explorer.exe");
        // `/select,` 与路径必须在同一个参数里
        assert_eq!(plan.args, vec![r"/select,D:\ws\a.txt".to_string()]);
        assert_eq!(plan.used, TerminalKind::Explorer);
        assert!(plan.working_directory.is_none());
        // 目录则直接打开
        let dir = explorer_plan(true, r"D:\ws\src");
        assert_eq!(dir.args, vec![r"D:\ws\src".to_string()]);
        // 符号链接（不跟随）按文件处理：能在资源管理器里看到它本身
        let link = explorer_plan(false, r"D:\ws\link");
        assert!(link.args[0].starts_with("/select,"));
    }

    #[test]
    fn terminal_is_picked_by_preference_and_reports_which_one() {
        // 三个都在 ⇒ 挑 Windows Terminal
        let all = |_: &str| true;
        let plan = terminal_plan(true, r"D:\ws", r"D:\ws", all).unwrap();
        assert_eq!(plan.used, TerminalKind::WindowsTerminal);
        assert_eq!(plan.program, "wt.exe");
        assert_eq!(plan.args, vec!["-d".to_string(), r"D:\ws".to_string()]);

        // 只有 PowerShell ⇒ 挑它，并起在目标目录
        let only_ps = |name: &str| name == "powershell.exe";
        let plan = terminal_plan(true, r"D:\ws", r"D:\ws", only_ps).unwrap();
        assert_eq!(plan.used, TerminalKind::PowerShell);
        assert!(plan.args.iter().any(|a| a.contains(r"D:\ws")));

        // 只有 cmd ⇒ 兜底
        let only_cmd = |name: &str| name == "cmd.exe";
        let plan = terminal_plan(true, r"D:\ws", r"D:\ws", only_cmd).unwrap();
        assert_eq!(plan.used, TerminalKind::CommandPrompt);
    }

    #[test]
    fn no_terminal_at_all_is_refused_with_the_list_of_tried_programs() {
        let none = |_: &str| false;
        let err = terminal_plan(true, r"D:\ws", r"D:\ws", none).unwrap_err();
        assert_eq!(err, vec!["wt.exe", "powershell.exe", "cmd.exe"]);
        assert!(pick_terminal(none).is_none());
    }

    #[test]
    fn terminal_for_a_file_uses_its_parent_directory() {
        let all = |_: &str| true;
        let plan = terminal_plan(false, r"D:\ws\sub\a.txt", r"D:\ws\sub", all).unwrap();
        assert_eq!(plan.working_directory.as_deref(), Some(r"D:\ws\sub"));
        assert!(plan.args.contains(&r"D:\ws\sub".to_string()), "终端的起始目录应当是父目录");
    }

    #[test]
    fn path_must_be_inside_the_workspace() {
        assert!(ensure_inside(r"D:\ws", r"D:\ws\sub\a.txt").is_ok());
        // 经典坑：字符串前缀会把 ws-evil 当成 ws 的子路径 ⇒ 由分量判定挡住
        assert!(ensure_inside(r"D:\ws", r"D:\ws-evil\a.txt").is_err());
        assert!(ensure_inside(r"D:\ws", r"D:\other\a.txt").is_err());
        assert!(ensure_inside(r"D:\ws", r"D:\ws\..\evil.txt").is_err());
        // 盘符大小写不敏感
        assert!(ensure_inside(r"D:\ws", r"d:\WS\a.txt").is_ok());
    }

    #[test]
    fn plan_serialises_with_expected_shape() {
        let plan = explorer_plan(false, r"D:\ws\a.txt");
        let text = serde_json::to_string(&plan).unwrap();
        assert!(text.contains("\"used\":\"explorer\""), "{text}");
        assert!(text.contains("\"workingDirectory\":null"), "{text}");
        let back: RevealPlan = serde_json::from_str(&text).unwrap();
        assert_eq!(back, plan);
    }
}
