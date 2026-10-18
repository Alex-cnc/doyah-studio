//! 慢查询排行（FR-DIAG-03）的**纯逻辑**：排行 SQL 按服务端版本生成、三种排序、过滤扩展自身的查询、
//! 查询文本按字符截断、扩展不可用时给可读的三步指引。
//!
//! 五条口径（全部是 macOS 侧实测踩过 / 三书点名要求的）：
//! ① **列名按服务端版本生成**：PostgreSQL 13 把 `total_time` / `mean_time` 改名为
//!    `total_exec_time` / `mean_exec_time` —— 一套 SQL 打天下会在某一侧直接报「列不存在」，
//!    而那条报错离真因（版本）很远，用户只会以为「这个功能坏了」。
//! ② **`pg_stat_statements` 缺失是可读指引，不是报错**：给三步（预加载 → **重启** → `CREATE EXTENSION`）。
//!    只做第三步会得到「装了但查不到数据」的困惑状态 —— 那一点必须写在指引里。
//! ③ **过滤扩展自身的查询**：`pg_stat_statements` 自己也会记账，不过滤就会把固定几条内部查询顶在榜首，
//!    真业务查询被挤下去 ⇒ 用户看到的「最慢的语句」是工具自己。
//! ④ **查询文本按字符截断**：按字节切会把中文切半个（UTF-8 边界）⇒ 界面上出现乱码似的尾巴。
//! ⑤ **顺序是确定的**：排序键并列时按调用次数兜底 —— 同一次刷新两次读数顺序不同，用户会以为列表在跳。

use serde::{Deserialize, Serialize};

use crate::admin::format_duration;

/// 排行口径（三书原文：总耗时 / 平均耗时 / 调用次数）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SlowQuerySort {
    TotalTime,
    MeanTime,
    Calls,
}

impl SlowQuerySort {
    /// 界面传进来的字符串 → 口径（认不出的**返回 `None`**，由调用方给可读原因，不静默取默认值）。
    pub fn parse(text: &str) -> Option<Self> {
        match text.trim().to_ascii_lowercase().as_str() {
            "total" | "totaltime" | "total_time" | "总耗时" => Some(Self::TotalTime),
            "mean" | "meantime" | "mean_time" | "平均耗时" => Some(Self::MeanTime),
            "calls" | "count" | "调用次数" => Some(Self::Calls),
            _ => None,
        }
    }

    /// 排序与显示用的列名（**按服务端主版本** —— 见文件头口径①）。
    pub fn column(self, version_major: u32) -> &'static str {
        match (self, version_major >= 13) {
            (Self::TotalTime, true) => "total_exec_time",
            (Self::TotalTime, false) => "total_time",
            (Self::MeanTime, true) => "mean_exec_time",
            (Self::MeanTime, false) => "mean_time",
            (Self::Calls, _) => "calls",
        }
    }
}

/// 默认排行条数（面板一次显示 20 条足够看出问题）。
pub const DEFAULT_LIMIT: usize = 20;
/// 上限（再多也没人看，而且每行都带一段 SQL 文本）。
pub const MAX_LIMIT: usize = 200;

/// 条数夹取：0 或超上限都不许原样送到服务端（`LIMIT 0` 会让界面看着像「没有慢查询」）。
pub fn clamp_limit(limit: usize) -> usize {
    if limit == 0 {
        DEFAULT_LIMIT
    } else {
        limit.min(MAX_LIMIT)
    }
}

/// 服务端版本串 → 主版本号。`18.6` / `13.4 (Debian 13.4-1)` / `PostgreSQL 12.9 on ...` 都认；
/// 认不出返回 **0**（= 按老口径出 SQL，并且 `version_known()` 会告诉调用方「这一档不确定」）。
pub fn version_major(version: &str) -> u32 {
    let text = version.trim();
    // 先看开头；开头不是数字就往里找第一段数字（`PostgreSQL 13.4 ...` 这种形状）
    let candidate = if text.chars().next().map(|c| c.is_ascii_digit()).unwrap_or(false) {
        text
    } else {
        match text.split_whitespace().find(|w| w.chars().next().map(|c| c.is_ascii_digit()).unwrap_or(false)) {
            Some(word) => word,
            None => return 0,
        }
    };
    let head: String = candidate.chars().take_while(|c| c.is_ascii_digit()).collect();
    head.parse().unwrap_or(0)
}

/// 排行 SQL（**生成而不是手写常量** —— 版本与排序都是变量）。
pub fn ranking_sql(sort: SlowQuerySort, server_version: &str, limit: usize) -> String {
    let major = version_major(server_version);
    let order = sort.column(major);
    let total = SlowQuerySort::TotalTime.column(major);
    let mean = SlowQuerySort::MeanTime.column(major);
    format!(
        "SELECT query, \
                calls::text, \
                {total}::text, \
                {mean}::text, \
                rows::text \
         FROM public.pg_stat_statements \
         WHERE query NOT ILIKE '%pg_stat_statements%' \
         ORDER BY {order} DESC, calls DESC \
         LIMIT {}",
        clamp_limit(limit)
    )
}

/// 可用性探测 SQL（**一次问全三件事**，免得界面上出现「装了 / 没装 / 没预加载」三种半截说法）：
/// `installed` = 视图存在；`available` = 服务端有这份扩展文件；`preloaded` = 已写进 `shared_preload_libraries`。
pub fn availability_sql() -> &'static str {
    "SELECT to_regclass('public.pg_stat_statements') IS NOT NULL, \
            EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_stat_statements'), \
            COALESCE(current_setting('shared_preload_libraries', true), '') ILIKE '%pg_stat_statements%'"
}

/// 可用性读数（驱动读回来交给本层）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Availability {
    pub installed: bool,
    pub available: bool,
    pub preloaded: bool,
}

impl Availability {
    /// 能不能查排行 = 视图在（其余两种情形都要给指引）。
    pub fn usable(&self) -> bool {
        self.installed
    }
}

/// 排行的一行（驱动读回来、界面直接显示）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SlowQueryRow {
    /// 查询文本（**已按字符截断**；`truncated` 为真时界面要如实说「已截断」）
    pub query: String,
    pub calls: i64,
    pub total_ms: f64,
    pub mean_ms: f64,
    /// 该语句累计影响 / 返回的行数（服务端口径，`pg_stat_statements.rows`）
    pub rows: i64,
    pub truncated: bool,
}

/// 排行回包：可用就给行，不可用就给**指引**（`rows` 必为空 —— 绝不用「空列表」冒充「没有慢查询」）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SlowQueryReport {
    pub available: bool,
    pub installed: bool,
    pub available_extension: bool,
    pub preloaded: bool,
    /// 不可用时的**可读原因**（可用时为 `None`）
    pub reason: Option<String>,
    /// 不可用时的**三步安装指引**（可用时为空）
    pub steps: Vec<String>,
    /// 本次用的时间列名（可用时才有值；界面显示出来，让「为什么这一版列的比法不同」有据可查）
    pub total_column: String,
    pub mean_column: String,
    pub rows_out: Vec<SlowQueryRow>,
}

impl SlowQueryReport {
    /// 不可用（带三步指引）。
    pub fn unavailable(state: Availability) -> Self {
        Self {
            available: false,
            installed: state.installed,
            available_extension: state.available,
            preloaded: state.preloaded,
            reason: Some(unavailable_reason(state)),
            steps: guidance(state),
            total_column: String::new(),
            mean_column: String::new(),
            rows_out: Vec::new(),
        }
    }
}

/// 不可用的**一句原因**：把「装不了 / 没预加载 / 可装未装」三种情形分开说 ——
/// 三种的下一步动作完全不同，合成一句「不可用」等于让用户自己猜。
pub fn unavailable_reason(state: Availability) -> String {
    if state.installed {
        // 视图在却查不了：这一档由驱动在跑排行时报错兜住，本函数不该被叫到
        return "扩展视图存在，但查询没跑通（看服务端原话）".to_string();
    }
    if !state.available {
        return "服务端没有 pg_stat_statements 这份扩展（这是精简构建 / 未装扩展包的发行版）：排行读不到数据。"
            .to_string();
    }
    if !state.preloaded {
        return "扩展文件在，但没被预加载（shared_preload_libraries 里没有它）：此时即使 CREATE EXTENSION 成功，查询也会报 must be loaded via shared_preload_libraries。"
            .to_string();
    }
    "扩展已预加载、但当前库里还没创建这个扩展：跑一次 CREATE EXTENSION 即可。".to_string()
}

/// 三步安装指引（三书原文的三步；**顺序不能换** —— 先建扩展再预加载会得到「装了但没数据」）。
pub fn guidance(state: Availability) -> Vec<String> {
    if state.installed {
        return Vec::new();
    }
    let mut steps = vec![
        if state.preloaded {
            "① 预加载：shared_preload_libraries 已包含 pg_stat_statements（这一条已满足，跳过）".to_string()
        } else {
            "① 预加载：在 postgresql.conf 里写 shared_preload_libraries = 'pg_stat_statements'（需要改服务端配置文件 + 重启权限）".to_string()
        },
        if state.preloaded {
            "② 重启服务端：预加载已生效，无需重启".to_string()
        } else {
            "② 重启服务端：预加载只在启动时读 —— 不重启就 CREATE EXTENSION 会得到一个「装了但查询报 must be loaded via shared_preload_libraries」的困惑状态".to_string()
        },
        "③ 建扩展：在当前库里执行 CREATE EXTENSION IF NOT EXISTS pg_stat_statements（需要超管或建扩展权限）".to_string(),
    ];
    if !state.available {
        steps.push(
            "④ 这一档还要先装扩展包：服务端没有这份扩展文件（Debian/Ubuntu 是 postgresql-contrib 包），装完再从 ① 走"
                .to_string(),
        );
    }
    steps.push(
        "权限：非超管要能看到别人的语句，需被授予 pg_read_all_stats；否则只能看到自己的查询（读数偏小不是缺陷）"
            .to_string(),
    );
    steps
}

/// 查询文本按**字符**截断（见文件头口径④）。返回（文本, 是否截断过）。
pub fn truncate_query(text: &str, max_chars: usize) -> (String, bool) {
    let limit = max_chars.max(1);
    let mut out = String::new();
    for (index, ch) in text.chars().enumerate() {
        if index >= limit {
            return (format!("{out}…"), true);
        }
        out.push(ch);
    }
    (out, false)
}

/// 一行的**显示用**摘要（界面别自己拼：格式化口径只有一处）。
pub fn row_summary(row: &SlowQueryRow) -> String {
    format!(
        "{} 次 · 共 {} · 平均 {} · 影响 {} 行",
        row.calls,
        format_duration(row.total_ms.round() as i64),
        format_duration(row.mean_ms.round() as i64),
        row.rows
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_major_reads_the_leading_number() {
        assert_eq!(version_major("18.6"), 18);
        assert_eq!(version_major("13.4 (Debian 13.4-1)"), 13);
        assert_eq!(version_major("PostgreSQL 12.9 on x86_64"), 12);
        assert_eq!(version_major(""), 0);
        assert_eq!(version_major("unknown"), 0);
    }

    #[test]
    fn ranking_sql_uses_pre13_time_columns_on_old_servers() {
        let sql = ranking_sql(SlowQuerySort::TotalTime, "12.9", 20);
        assert!(sql.contains("total_time::text"), "PG12 该用 total_time：{sql}");
        assert!(sql.contains("mean_time::text"), "PG12 该用 mean_time：{sql}");
        assert!(!sql.contains("exec_time"), "PG12 不该出现 exec_time：{sql}");
    }

    #[test]
    fn ranking_sql_uses_exec_columns_on_pg13_and_later() {
        for version in ["13.0", "16.2", "18.6"] {
            let sql = ranking_sql(SlowQuerySort::TotalTime, version, 20);
            assert!(
                sql.contains("total_exec_time::text") && sql.contains("mean_exec_time::text"),
                "PG{version} 该用 *_exec_time：{sql}"
            );
            assert!(!sql.contains(" total_time"), "PG{version} 不该再出现老列名：{sql}");
        }
    }

    #[test]
    fn ranking_sql_orders_by_the_requested_measure() {
        let total = ranking_sql(SlowQuerySort::TotalTime, "18.6", 20);
        let mean = ranking_sql(SlowQuerySort::MeanTime, "18.6", 20);
        let calls = ranking_sql(SlowQuerySort::Calls, "18.6", 20);
        assert!(total.contains("ORDER BY total_exec_time DESC"));
        assert!(mean.contains("ORDER BY mean_exec_time DESC"));
        assert!(calls.contains("ORDER BY calls DESC"));
        // 并列兜底：三种都按 calls 再排一次（顺序确定）
        for sql in [&total, &mean, &calls] {
            assert!(sql.contains(", calls DESC"), "并列时要有确定顺序：{sql}");
        }
    }

    #[test]
    fn ranking_sql_filters_the_extension_own_queries() {
        let sql = ranking_sql(SlowQuerySort::Calls, "18.6", 20);
        assert!(
            sql.contains("NOT ILIKE '%pg_stat_statements%'"),
            "扩展自己的查询必须被过滤掉，否则它会把真业务查询挤下去：{sql}"
        );
    }

    #[test]
    fn ranking_sql_clamps_limit() {
        assert!(ranking_sql(SlowQuerySort::Calls, "18.6", 0).ends_with(&format!("LIMIT {DEFAULT_LIMIT}")));
        assert!(ranking_sql(SlowQuerySort::Calls, "18.6", 9999).ends_with(&format!("LIMIT {MAX_LIMIT}")));
        assert!(ranking_sql(SlowQuerySort::Calls, "18.6", 5).ends_with("LIMIT 5"));
    }

    #[test]
    fn sort_parses_from_text_and_rejects_unknown() {
        assert_eq!(SlowQuerySort::parse("total"), Some(SlowQuerySort::TotalTime));
        assert_eq!(SlowQuerySort::parse("MeanTime"), Some(SlowQuerySort::MeanTime));
        assert_eq!(SlowQuerySort::parse(" 调用次数 "), Some(SlowQuerySort::Calls));
        assert_eq!(SlowQuerySort::parse("slowest"), None);
    }

    #[test]
    fn truncate_query_counts_characters_not_bytes() {
        let text = "查询很慢的原因：没有走索引";
        let (out, cut) = truncate_query(text, 4);
        assert_eq!(out, "查询很慢…");
        assert!(cut);
        // 逐字符比：截断后不该出现 UTF-8 半截字符（能正常转成 &str 就说明没切坏）
        assert_eq!(out.chars().count(), 5);
        let (same, cut2) = truncate_query("select 1", 20);
        assert_eq!(same, "select 1");
        assert!(!cut2);
    }

    #[test]
    fn availability_sql_asks_all_three_questions_at_once() {
        let sql = availability_sql();
        assert!(sql.contains("to_regclass"));
        assert!(sql.contains("pg_available_extensions"));
        assert!(sql.contains("shared_preload_libraries"));
    }

    #[test]
    fn unavailable_reason_separates_the_three_states() {
        let missing = Availability { installed: false, available: false, preloaded: false };
        let not_preloaded = Availability { installed: false, available: true, preloaded: false };
        let not_created = Availability { installed: false, available: true, preloaded: true };
        let a = unavailable_reason(missing);
        let b = unavailable_reason(not_preloaded);
        let c = unavailable_reason(not_created);
        assert_ne!(a, b);
        assert_ne!(b, c);
        assert!(b.contains("shared_preload_libraries"));
        assert!(c.contains("CREATE EXTENSION"));
    }

    #[test]
    fn guidance_says_preload_then_restart_then_create() {
        let state = Availability { installed: false, available: true, preloaded: false };
        let steps = guidance(state);
        assert!(steps[0].contains("shared_preload_libraries"));
        assert!(steps[1].contains("重启"));
        assert!(steps[2].contains("CREATE EXTENSION"));
        // 没预加载时要说清「先建扩展会得到装了但没数据」这条
        assert!(steps[1].contains("must be loaded via shared_preload_libraries"));
        // 已预加载的档：前两步要标「已满足 / 无需重启」（别让用户去改已经对的配置）
        let ready = guidance(Availability { installed: false, available: true, preloaded: true });
        assert!(ready[0].contains("已满足"));
        assert!(ready[1].contains("无需重启"));
        // 装了以后不该再给指引
        assert!(guidance(Availability { installed: true, available: true, preloaded: true }).is_empty());
    }

    #[test]
    fn report_marks_rows_empty_when_unavailable() {
        let report = SlowQueryReport::unavailable(Availability {
            installed: false,
            available: true,
            preloaded: false,
        });
        assert!(!report.available);
        assert!(report.rows_out.is_empty());
        assert!(report.reason.is_some());
        assert!(!report.steps.is_empty());
    }
}
