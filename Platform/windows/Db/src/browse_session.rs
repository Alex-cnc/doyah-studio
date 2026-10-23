//! **跨库浏览的目标判定**（FR-META-10）——「这次取数该走哪条连接」只此一处。
//!
//! 为什么要把这条判定抽成纯函数：跨库浏览真正的错只有三种，且都是**静默**的：
//! ① 连上就把服务器上几十个库**全预连**（服务端立刻多出几十个后端，用户毫无感觉）；
//! ② 展开非当前库时**复用当前库那条连接**（子树里列出的是**当前库**的表 —— 有东西出来，
//!    但那是错的，比空树更难发现）；
//! ③ 库名比较不严谨（大小写归一 / 去掉空白）⇒ 请求 `Shop` 时静默落到 `shop` 上。
//!
//! 所以这里只做一件事：给「当前库 + 用户要看的库 + 已建会话的库」判出
//! **用当前连接 / 复用已有会话 / 新建一条**。取数与连接建立都在表示层（驱动只在那里），
//! 本层零依赖、可单测（家族「判据先行」：先把这条规则钉住，再接）。
//!
//! 三条铁口径（单测逐条钉）：
//! - **请求的就是当前库 ⇒ 用当前连接**（哪怕缓存里正好有同名条目，也不为它另开第二条）；
//! - **没指定 / 空白 ⇒ 用当前连接**（`None` 不是「列全部」的意思）；
//! - **库名大小写敏感**：PostgreSQL 的库名就是敏感的，`Shop` 与 `shop` 是两个库，
//!   这里绝不做大小写归一（归一会让请求静默落到另一个库上）。

use serde::{Deserialize, Serialize};

/// 这次取数该怎么拿会话。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BrowseAction {
    /// 用当前连接（请求的是当前库，或没指定库）
    UsePrimary,
    /// 复用该库**已经建好**的独立会话（不新建连接）
    UseCached,
    /// 给该库**新建**一条独立会话（按需建连，只在用户真展开它时发生）
    Connect,
}

/// 判定结果：动作 + 目标库（`UsePrimary` 时目标库 = 当前库 —— 界面可以直接显示「正在看哪个库」）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BrowsePlan {
    pub action: BrowseAction,
    /// 这次取数**真正要打到的库**（永远非空：`UsePrimary` 时是当前库名）
    pub database: String,
}

impl BrowsePlan {
    /// 要不要新建一条连接（判据里最常问的一句）。
    pub fn opens_connection(&self) -> bool {
        self.action == BrowseAction::Connect
    }
}

/// 判定：`current` = 当前连接的库名；`requested` = 界面要展开的库（`None` = 没指定）；
/// `cached` = 已建独立会话的库名清单。
///
/// **不做任何归一**：库名逐字比较（`trim` 只用于削掉界面送来的人手空白，
/// 削完仍逐字比 —— 削空白不等于改大小写）。
pub fn plan(current: &str, requested: Option<&str>, cached: &[String]) -> BrowsePlan {
    let current = current.trim().to_string();
    let requested = requested.map(str::trim).filter(|name| !name.is_empty());

    match requested {
        // ① 没指定库 ⇒ 当前连接（`None` 不代表「全部库」）
        None => BrowsePlan { action: BrowseAction::UsePrimary, database: current },
        // ② 请求的就是当前库 ⇒ 当前连接（不为它另开一条）
        Some(name) if name == current => BrowsePlan { action: BrowseAction::UsePrimary, database: current },
        // ③ 该库已有独立会话 ⇒ 复用（重展开不许再建一条）
        Some(name) if cached.iter().any(|cached_name| cached_name == name) => BrowsePlan {
            action: BrowseAction::UseCached,
            database: name.to_string(),
        },
        // ④ 别的库、且还没有会话 ⇒ 按需建一条（**只建这一个库**，不是整台服务器）
        Some(name) => BrowsePlan { action: BrowseAction::Connect, database: name.to_string() },
    }
}

/// 独立会话的**归属说明**（界面上一行小字 + 出问题时的提示用）。
///
/// 为什么要把「这条连接是给哪个库开的」说清楚：同一个服务器上两条会话长得一模一样，
/// 出错时（比如权限不够）只说「连接失败」用户没法判断是哪一步。
pub fn session_label(database: &str) -> String {
    format!("独立会话 · {database}")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cached(names: &[&str]) -> Vec<String> {
        names.iter().map(|name| name.to_string()).collect()
    }

    #[test]
    fn no_request_uses_the_primary_session_and_reports_the_current_database() {
        // `None` ≠ 「列出所有库」：没指定就老老实实用当前连接
        let plan = plan("shop", None, &cached(&["warehouse"]));
        assert_eq!(plan.action, BrowseAction::UsePrimary);
        assert_eq!(plan.database, "shop");
        assert!(!plan.opens_connection());
    }

    #[test]
    fn a_blank_request_is_treated_as_no_request() {
        // 界面上「空串 / 一串空格」与没选是同一件事
        for blank in ["", "   ", "\t"] {
            let plan = plan("shop", Some(blank), &[]);
            assert_eq!(plan.action, BrowseAction::UsePrimary, "空白请求：{blank:?}");
            assert_eq!(plan.database, "shop");
        }
    }

    #[test]
    fn requesting_the_current_database_never_opens_a_second_connection() {
        // 即使缓存里正好有同名条目（比如上一轮遗留），也不为它另开一条
        let plan = plan("shop", Some("shop"), &cached(&["shop"]));
        assert_eq!(plan.action, BrowseAction::UsePrimary);
        assert!(!plan.opens_connection());
    }

    #[test]
    fn another_database_with_a_cached_session_is_reused_instead_of_reconnecting() {
        // 「重展开仍 1 条后端」靠这条：第二次展开必须是 UseCached
        let plan = plan("shop", Some("warehouse"), &cached(&["warehouse"]));
        assert_eq!(plan.action, BrowseAction::UseCached);
        assert_eq!(plan.database, "warehouse");
        assert!(!plan.opens_connection());
    }

    #[test]
    fn another_database_without_a_session_is_connected_on_demand_only_for_that_one() {
        // 关键否定面：`Connect` 只点名**一个**库（一次只建一条，不是整台服务器）
        let plan = plan("shop", Some("warehouse"), &[]);
        assert_eq!(plan.action, BrowseAction::Connect);
        assert_eq!(plan.database, "warehouse");
        assert!(plan.opens_connection());
    }

    #[test]
    fn database_names_are_case_sensitive_so_a_different_case_is_a_different_database() {
        // PostgreSQL 的库名大小写敏感：`Shop` 不许被当成 `shop`
        let upper = plan("shop", Some("Shop"), &[]);
        assert_eq!(upper.action, BrowseAction::Connect);
        assert_eq!(upper.database, "Shop");

        // 反过来也一样：当前库是 `Shop`，请求 `shop` 也不是它
        let lower = plan("Shop", Some("shop"), &[]);
        assert_eq!(lower.action, BrowseAction::Connect);
    }

    #[test]
    fn surrounding_whitespace_is_trimmed_but_the_name_itself_is_kept_verbatim() {
        let plan = plan("shop", Some("  warehouse \n"), &[]);
        assert_eq!(plan.action, BrowseAction::Connect);
        assert_eq!(plan.database, "warehouse");
    }

    #[test]
    fn the_label_says_which_database_the_extra_session_belongs_to() {
        // 同一个服务器上两条会话长得一样，标签必须点名库
        assert!(session_label("warehouse").contains("warehouse"));
    }
}
