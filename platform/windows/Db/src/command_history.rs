//! **命令使用历史**（2.9 的"工作区历史"那一半）
//!
//! 面板里"最近用过"比"全部命令"更有用：用户反复做的那几件事，应当一打开就在眼前。
//!
//! ## 口径（三条，都有单测）
//! 1. **记的是次数与时刻，不是"最近 N 条"** —— 只留最近 N 条的话，"每天用 20 次的那条"会被
//!    偶尔用一次的命令挤掉；而用户真正想要的是**常用的**。
//! 2. **排序按"常用优先、同等常用看谁更近"**：次数差一档就压过时间差；
//!    这样"天天用的"总在前面，而"刚用过的"在同等常用里靠前。
//! 3. **只留用得上的那么多**（上限），且**从末尾淘汰**（用最少的先走）——
//!    淘汰要按同一把尺子，否则"谁走了"看着随机。

use std::collections::BTreeMap;

/// 最多记多少条命令。
pub const HISTORY_LIMIT: usize = 50;

/// 一条命令的使用记录。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Entry {
    /// 用了几次
    pub count: u32,
    /// 最后一次用的时刻（Unix 秒）
    pub last_used: i64,
}

/// 命令使用历史。
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct History {
    /// 命令 id → 记录（`BTreeMap` 保证序列化顺序稳定，便于 diff 与判据）
    #[serde(default)]
    pub entries: BTreeMap<String, Entry>,
}

impl History {
    /// 记一次"用了这条命令"。
    pub fn record(mut self, command_id: &str, at: i64) -> Self {
        let trimmed = command_id.trim();
        if trimmed.is_empty() {
            return self;
        }
        let entry = self
            .entries
            .entry(trimmed.to_string())
            .or_insert(Entry {
                count: 0,
                last_used: at,
            });
        entry.count = entry.count.saturating_add(1);
        // 时刻取**较大者**：乱序到达（时钟回拨 / 并发写）时不要让"最后用过"倒退
        entry.last_used = entry.last_used.max(at);
        // **这里刻意不淘汰**（这是本轮抓到的一个真缺陷）：如果在"记一次"里淘汰，
        // 新命令刚记第一次（count=1）就会因为"最少用"被立刻淘汰 ⇒ **它永远长不起来**，
        // 表现是"常用命令总也进不了榜、留下的都是长尾"。
        // 淘汰是**批量动作**：由调用方在合适的边界（收尾 / 下次启动）显式调 `prune`。
        self
    }

    /// 淘汰：超过上限就按"用得最少、且最久没用"从末尾去掉。
    ///
    /// **批量动作**：由调用方在边界处显式调用（收尾 / 下次启动），**不要在 record 里调** ——
    /// 那样新命令刚记第一次就会被淘汰掉。
    pub fn prune(&mut self) {
        if self.entries.len() <= HISTORY_LIMIT {
            return;
        }
        let mut ranked: Vec<(String, Entry)> = self
            .entries
            .iter()
            .map(|(id, entry)| (id.clone(), entry.clone()))
            .collect();
        // 排序尺子与 `ranked` **同一把**（`compare` 本身就是"常用优先"的口径）。
        // 我第一版写成 `compare(b, a)`（把参数反了）⇒ 变成升序 ⇒ **留下的全是"最少用"的那些**
        // （表现：条数确实截到上限了，但留下的都是长尾 —— 不打印次数根本看不出来）。
        ranked.sort_by(compare);
        self.entries = ranked
            .into_iter()
            .take(HISTORY_LIMIT)
            .collect();
    }

    /// 按"常用优先、同等常用看谁更近"排出命令 id（供面板显示"最近使用"分组）。
    pub fn ranked(&self, limit: usize) -> Vec<String> {
        let mut all: Vec<(String, Entry)> = self
            .entries
            .iter()
            .map(|(id, entry)| (id.clone(), entry.clone()))
            .collect();
        all.sort_by(compare);
        all.into_iter().take(limit).map(|(id, _)| id).collect()
    }

    /// 某条命令用了几次（0 = 没用过）。
    pub fn count_of(&self, command_id: &str) -> u32 {
        self.entries.get(command_id).map(|entry| entry.count).unwrap_or(0)
    }

    /// 清空（界面上的"清掉使用记录"）。
    pub fn clear(self) -> Self {
        Self::default()
    }
}

/// 排序尺子（**只有这一处**）：次数多的在前；次数相同则"更近的"在前；再相同按 id 升序（稳定）。
fn compare(a: &(String, Entry), b: &(String, Entry)) -> std::cmp::Ordering {
    b.1.count
        .cmp(&a.1.count)
        .then_with(|| b.1.last_used.cmp(&a.1.last_used))
        .then_with(|| a.0.cmp(&b.0))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recording_counts_and_keeps_the_latest_moment() {
        let history = History::default()
            .record("sql.run", 100)
            .record("sql.run", 200)
            .record("sql.run", 150); // 乱序（时钟回拨）不该让"最后用过"倒退
        assert_eq!(history.count_of("sql.run"), 3);
        assert_eq!(history.entries["sql.run"].last_used, 200);
        // 空 id 不入账
        let untouched = history.clone().record("   ", 300);
        assert_eq!(untouched, history);
        // 没用过的命令次数是 0
        assert_eq!(history.count_of("nope"), 0);
    }

    #[test]
    fn ranking_prefers_frequently_used_then_recent() {
        let history = History::default()
            .record("often", 100) // 用 2 次（下面再加一次）
            .record("often", 100)
            .record("rare", 999) // 用 1 次，但**最近**
            .record("middle", 500)
            .record("middle", 500);
        // "常用优先"：2 次的排在同一档，1 次的在后（哪怕它最新）
        let ranked = history.ranked(10);
        // `often` 与 `middle` **都是 2 次**，而 middle 更近（500 > 100）⇒ middle 在前。
        // 我第一版把"次数多的在前"当成 often 排第一，**没注意两者次数相同** —— 是用例写错，实现是对的。
        assert_eq!(ranked[0], "middle", "同为 2 次时更近的在前");
        assert_eq!(ranked[1], "often");
        // 1 次的排在最后，**哪怕它最近用过**（这条是"常用优先"的真正含义）
        assert_eq!(ranked[2], "rare", "次数少的在后，哪怕它最近用过");
    }

    #[test]
    fn same_count_and_same_moment_is_stable_by_id() {
        let history = History::default()
            .record("b.command", 100)
            .record("a.command", 100);
        // 同分 ⇒ 按 id 升序（**不能取决于插入顺序**，否则用户看到"每次不一样"）
        assert_eq!(history.ranked(10), vec!["a.command", "b.command"]);
        let reversed = History::default()
            .record("a.command", 100)
            .record("b.command", 100);
        assert_eq!(reversed.ranked(10), vec!["a.command", "b.command"]);
    }

    #[test]
    fn pruning_keeps_the_limit_and_drops_the_least_used() {
        // 记满 60 条（`cmd.i` 用 i+1 次）—— **记的过程不淘汰**，淘汰是之后显式做的
        let mut history = History::default();
        for index in 0..60usize {
            let id = format!("cmd.{i:02}", i = index);
            for _ in 0..=index {
                history = history.record(&id, 1000 + index as i64);
            }
        }
        assert_eq!(history.entries.len(), 60, "记的过程不该淘汰（这是本轮修掉的真缺陷）");
        assert_eq!(history.count_of("cmd.59"), 60);

        // 显式淘汰一次
        history.prune();
        assert_eq!(history.entries.len(), HISTORY_LIMIT, "上限要生效");
        // 用得最多的必须留下且次数完整
        assert_eq!(history.count_of("cmd.59"), 60, "用得最多的必须留着");
        // 淘汰的正好 10 条
        let dropped = (0..60)
            .map(|i| format!("cmd.{i:02}"))
            .filter(|id| history.count_of(id) == 0)
            .count();
        assert_eq!(dropped, 10, "60 条留 50 ⇒ 淘汰 10 条");
        // **留下的都不差于走的**（"按同一把尺子淘汰"的机械形式）
        let kept_min = history.entries.values().map(|e| e.count).min().unwrap_or(0);
        let dropped_max = (0..60)
            .map(|i| format!("cmd.{i:02}"))
            .filter(|id| history.count_of(id) == 0)
            .map(|id| id.split('.').nth(1).and_then(|n| n.parse::<u32>().ok()).map(|n| n + 1).unwrap_or(0))
            .max()
            .unwrap_or(0);
        assert!(
            kept_min >= dropped_max,
            "留下的最少次数（{kept_min}）不该低于被淘汰的最多次数（{dropped_max}）"
        );
        // 排序自洽
        assert_eq!(history.ranked(1), vec!["cmd.59".to_string()]);
    }

    #[test]
    fn limit_parameter_is_respected_and_clear_resets() {
        let history = History::default().record("a", 1).record("b", 2).record("c", 3);
        assert_eq!(history.ranked(2).len(), 2);
        assert_eq!(history.ranked(0).len(), 0);
        assert!(history.clone().clear().entries.is_empty());
    }

    #[test]
    fn serialisation_shape_is_stable_for_diffing() {
        let history = History::default().record("sql.run", 100).record("ws.open", 50);
        let json = serde_json::to_string(&history).unwrap();
        // 键名与形状固定（便于落盘后 diff 与判据）
        assert!(json.contains("\"lastUsed\""), "{json}");
        assert!(json.contains("\"count\""), "{json}");
        let back: History = serde_json::from_str(&json).unwrap();
        assert_eq!(back, history);
        // 旧文件（空对象）也要读得进来
        let old: History = serde_json::from_str("{}").unwrap();
        assert!(old.entries.is_empty());
    }
}
