//! 已保存查询（FR-EDIT-14 / DR-04 的 Windows 等价物）
//!
//! **本文件只放模型与判定，不碰磁盘、不读时钟**（与 `config.rs` 同一分层口径）：
//! 落盘在表示层 `App/src-tauri/src/saved_queries.rs`，时间戳由调用方给。
//!
//! 四条口径：
//! ① 只存「SQL + 它从哪儿来（连接 id / 连接名 / 库名）+ 什么时候存的」—— **不存口令、不存结果集**；
//! ② 名字的合法性与「重名」判定**只在 `name_key` 这一处**：界面不许自己另写一套比较
//!    （两套比较的下场是一条叫「Orders」、一条叫「orders 」，用户以为存丢了一条）；
//! ③ **同名 = 覆盖**（id 不变、内容与时间替换），不是新增第二条；
//! ④ 名字去掉首尾空白后才落盘 —— 名字是给列表看的，首尾空格只会让两条看起来一样。
//!
//! 口径 ③ 为什么要一个显式的 `overwrite`：覆盖是**会丢旧内容**的动作，必须由用户在界面上
//! 确认一次（需求原文点名「重名提示覆盖保存」），所以 `save_into` 在未确认时返回
//! `Conflict` 而**不改表**。这条是判据（`a_conflicting_name_is_refused_until_overwritten`）锁住的。

use serde::{Deserialize, Serialize};

/// 一条已保存查询自身的模式版本（升版 = 加字段且需要迁移时）。
pub const CURRENT_SCHEMA_VERSION: u32 = 1;

/// 名字的最大长度（字符数）。给列表与按钮留出可读宽度；超了当场判不合法而不是静默截断
/// （静默截断会让两个不同的长名字变成同一个，正好撞上「同名 = 覆盖」）。
pub const MAX_NAME_CHARS: usize = 120;

/// 一条已保存查询。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SavedQuery {
    /// 稳定标识（新建时由调用方给；覆盖保存时**沿用既有那条的 id**）。
    pub id: String,
    /// 展示名（已去首尾空白）。
    pub name: String,
    /// SQL 正文（**逐字保留**：用户排的版不该被这里悄悄改）。
    pub sql: String,
    /// 来源连接 id（`None` = 没绑定连接，例如从文件打开写的 SQL）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub connection_id: Option<String>,
    /// 来源连接名（连接改名后这里是存的那一刻的名字 —— 只作显示线索，不做关联依据）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub connection_name: Option<String>,
    /// 来源库名。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub database: Option<String>,
    /// 保存时刻（ISO-8601 UTC，由调用方给 —— 领域层不读时钟，单测才能确定）。
    #[serde(default)]
    pub saved_at: String,
    /// 本条自身的模式版本。
    #[serde(default = "default_schema_version")]
    pub schema_version: u32,
}

fn default_schema_version() -> u32 {
    CURRENT_SCHEMA_VERSION
}

/// 出问题的那一项（**点名**，不是一个笼统的「不合法」）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SavedQueryField {
    Name,
    Sql,
}

impl SavedQueryField {
    /// 稳定的字段键（界面据此定位到那一格）。
    pub const fn key(self) -> &'static str {
        match self {
            SavedQueryField::Name => "name",
            SavedQueryField::Sql => "sql",
        }
    }
}

impl SavedQuery {
    pub fn new(id: impl Into<String>, name: impl Into<String>, sql: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            sql: sql.into(),
            connection_id: None,
            connection_name: None,
            database: None,
            saved_at: String::new(),
            schema_version: CURRENT_SCHEMA_VERSION,
        }
    }

    /// 规范化：**名字去首尾空白**（SQL 一字不动）。
    pub fn sanitized(mut self) -> Self {
        self.name = self.name.trim().to_string();
        self.schema_version = CURRENT_SCHEMA_VERSION;
        self
    }

    /// 哪几项不成立（空 = 成立）。
    pub fn problems(&self) -> Vec<SavedQueryField> {
        let mut out = Vec::new();
        let name = self.name.trim();
        if name.is_empty() || name.chars().count() > MAX_NAME_CHARS {
            out.push(SavedQueryField::Name);
        }
        if self.sql.trim().is_empty() {
            out.push(SavedQueryField::Sql);
        }
        out
    }

    pub fn is_valid(&self) -> bool {
        self.problems().is_empty()
    }
}

/// 名字的比较键：**去首尾空白 + 忽略大小写**（唯一的「同名」判据）。
pub fn name_key(name: &str) -> String {
    name.trim().to_lowercase()
}

/// 按名字找（返回第一条命中的下标）。
pub fn index_of_name(list: &[SavedQuery], name: &str) -> Option<usize> {
    let key = name_key(name);
    list.iter().position(|q| name_key(&q.name) == key)
}

/// 存一条进去的结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SaveVerdict {
    /// 新名字：追加。
    Created,
    /// 同名且用户确认了覆盖：**替换既有那条的内容**（id 沿用既有的）。
    Replaced,
    /// 同名但用户没确认覆盖：**表一字不动**，把既有那条交给界面去提示。
    Conflict(SavedQuery),
}

/// 存一条（唯一出口：命令层照它落盘）。
///
/// 三档语义：
/// ① 名字未被占用 ⇒ 追加（`Created`）；
/// ② 名字被**另一条**占用且 `overwrite` ⇒ 替换那一条（`Replaced`，id 保持既有）；
/// ③ 名字被占用而用户没确认 ⇒ `Conflict`，**不改表**。
///
/// id 相同的同一条再存 = 就地更新（不算冲突：那是「编辑同一条」的路径）。
pub fn save_into(list: &mut Vec<SavedQuery>, query: SavedQuery, overwrite: bool) -> SaveVerdict {
    let query = query.sanitized();
    // ① 同 id ⇒ 就地更新
    if let Some(slot) = list.iter_mut().find(|q| q.id == query.id) {
        *slot = query;
        return SaveVerdict::Replaced;
    }
    // ② / ③ 同名判定
    match index_of_name(list, &query.name) {
        Some(index) => {
            if overwrite {
                let kept_id = list[index].id.clone();
                list[index] = SavedQuery { id: kept_id, ..query };
                SaveVerdict::Replaced
            } else {
                SaveVerdict::Conflict(list[index].clone())
            }
        }
        None => {
            list.push(query);
            SaveVerdict::Created
        }
    }
}

/// 删一条（按 id）。返回被删掉的那条（`None` = 本来就没有）。
pub fn remove_by_id(list: &mut Vec<SavedQuery>, id: &str) -> Option<SavedQuery> {
    let index = list.iter().position(|q| q.id == id)?;
    Some(list.remove(index))
}

// ── 落盘包的编解码（与 `config::ConnectionBundle` 同形：格式版本 + 说明 + 列表）──────────────

/// 已保存查询文件的格式版本。
pub const CURRENT_BUNDLE_FORMAT_VERSION: u32 = 1;

/// 包解析的失败（**按域一个枚举**，同 `BundleError` 的口径）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SavedQueryError {
    /// 文本不是合法 JSON，或字段形状不对。
    Malformed(String),
    /// 文件来自更新版本的客户端 ⇒ 拒绝（不静默丢字段）。
    TooNew(u32),
}

impl std::fmt::Display for SavedQueryError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SavedQueryError::Malformed(detail) => write!(f, "已保存查询文件读不出来：{detail}"),
            SavedQueryError::TooNew(version) => write!(
                f,
                "已保存查询文件来自更新版本的客户端（格式 v{version}，本版只认 v{CURRENT_BUNDLE_FORMAT_VERSION}）"
            ),
        }
    }
}

impl std::error::Error for SavedQueryError {}

/// 已保存查询文件（`saved-queries.json`）的形状。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SavedQueryBundle {
    pub format_version: u32,
    /// 最后一次写入时刻（ISO-8601，由调用方给）。
    pub saved_at: String,
    pub queries: Vec<SavedQuery>,
    /// 包里故意不含什么的说明（写给打开文件的人看）。
    pub note: String,
}

impl SavedQueryBundle {
    pub const DEFAULT_NOTE: &'static str =
        "本文件只含查询的名字与 SQL 正文（以及它来自哪个连接 / 库），不含口令、不含查询结果。";

    pub fn new(saved_at: impl Into<String>, queries: Vec<SavedQuery>) -> Self {
        Self {
            format_version: CURRENT_BUNDLE_FORMAT_VERSION,
            saved_at: saved_at.into(),
            queries,
            note: Self::DEFAULT_NOTE.to_string(),
        }
    }

    pub fn encoded(&self) -> Result<String, SavedQueryError> {
        serde_json::to_string_pretty(self)
            .map_err(|e| SavedQueryError::Malformed(e.to_string()))
    }

    /// 解析：版本比当前新 ⇒ `TooNew`；老档逐条规范化（去名字空白 / 补 schemaVersion）。
    pub fn decode(text: &str) -> Result<Self, SavedQueryError> {
        let mut bundle: Self =
            serde_json::from_str(text).map_err(|e| SavedQueryError::Malformed(e.to_string()))?;
        if bundle.format_version > CURRENT_BUNDLE_FORMAT_VERSION {
            return Err(SavedQueryError::TooNew(bundle.format_version));
        }
        bundle.queries = bundle.queries.into_iter().map(SavedQuery::sanitized).collect();
        Ok(bundle)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn q(id: &str, name: &str, sql: &str) -> SavedQuery {
        SavedQuery::new(id, name, sql)
    }

    #[test]
    fn names_are_trimmed_before_storing() {
        let saved = q("a", "  月度对账  ", "select 1").sanitized();
        assert_eq!(saved.name, "月度对账");
        // SQL 逐字保留：连换行与缩进都不动
        let sql = "select 1\n  from t\n";
        assert_eq!(q("a", "x", sql).sanitized().sql, sql);
    }

    #[test]
    fn a_query_without_a_name_or_sql_is_refused() {
        assert_eq!(
            q("a", "   ", "select 1").problems(),
            vec![SavedQueryField::Name]
        );
        assert_eq!(
            q("a", "ok", "  \n\t ").problems(),
            vec![SavedQueryField::Sql]
        );
        assert!(q("a", "ok", "select 1").is_valid());
        // 名字过长当场判不合法，而不是静默截断（截断会把两条不同的名字合成一条）
        let long = "名".repeat(MAX_NAME_CHARS + 1);
        assert_eq!(
            q("a", &long, "select 1").problems(),
            vec![SavedQueryField::Name]
        );
    }

    #[test]
    fn the_same_name_is_one_key_regardless_of_case_or_padding() {
        assert_eq!(name_key("  Orders "), name_key("orders"));
        let list = vec![q("a", "Orders", "select 1")];
        assert_eq!(index_of_name(&list, "orders"), Some(0));
        assert_eq!(index_of_name(&list, "order"), None);
    }

    #[test]
    fn a_new_name_is_appended() {
        let mut list = vec![q("a", "一", "select 1")];
        assert_eq!(save_into(&mut list, q("b", "二", "select 2"), false), SaveVerdict::Created);
        assert_eq!(list.len(), 2);
        assert_eq!(list[1].name, "二");
    }

    #[test]
    fn a_conflicting_name_is_refused_until_overwritten() {
        let mut list = vec![q("a", "Orders", "select old")];
        let verdict = save_into(&mut list, q("b", "orders", "select new"), false);
        match verdict {
            SaveVerdict::Conflict(existing) => {
                assert_eq!(existing.id, "a");
                assert_eq!(existing.sql, "select old");
            }
            other => panic!("同名未确认时必须给冲突，实际：{other:?}"),
        }
        // 关键：拒绝时**表一字不动**（否则「提示覆盖」就成了一句空话）
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].sql, "select old");
    }

    #[test]
    fn an_overwrite_replaces_the_entry_and_keeps_its_id() {
        let mut list = vec![q("a", "Orders", "select old"), q("b", "Other", "select x")];
        let verdict = save_into(&mut list, q("new-id", "  orders ", "select new"), true);
        assert_eq!(verdict, SaveVerdict::Replaced);
        assert_eq!(list.len(), 2, "覆盖不是新增第三条");
        let hit = list.iter().find(|q| name_key(&q.name) == name_key("orders")).unwrap();
        assert_eq!(hit.id, "a", "覆盖要沿用既有 id（否则列表里会出现两条同名）");
        assert_eq!(hit.sql, "select new");
    }

    #[test]
    fn saving_the_same_id_again_updates_it_in_place() {
        let mut list = vec![q("a", "一", "select 1")];
        assert_eq!(
            save_into(&mut list, SavedQuery::new("a", "一（改名）", "select 2"), false),
            SaveVerdict::Replaced
        );
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].name, "一（改名）");
        assert_eq!(list[0].sql, "select 2");
    }

    #[test]
    fn removing_by_id_takes_exactly_one_out() {
        let mut list = vec![q("a", "一", "select 1"), q("b", "二", "select 2")];
        assert_eq!(remove_by_id(&mut list, "a").map(|q| q.name), Some("一".to_string()));
        assert_eq!(list.len(), 1);
        assert_eq!(remove_by_id(&mut list, "a"), None, "删过的再删是「本来就没有」");
    }

    #[test]
    fn the_bundle_round_trips_and_says_what_it_does_not_hold() {
        let mut one = q("a", "月度对账", "select * from t");
        one.connection_name = Some("实验库".into());
        one.database = Some("doyah_lab".into());
        one.saved_at = "2026-10-18T10:00:00Z".into();
        let bundle = SavedQueryBundle::new("2026-10-18T10:00:00Z", vec![one.clone()]);
        let text = bundle.encoded().unwrap();
        assert!(text.contains("不含口令"), "{text}");
        let back = SavedQueryBundle::decode(&text).unwrap();
        assert_eq!(back.queries, vec![one]);
        assert_eq!(back.format_version, CURRENT_BUNDLE_FORMAT_VERSION);
    }

    #[test]
    fn a_newer_bundle_is_refused_instead_of_silently_dropping_fields() {
        let mut bundle = SavedQueryBundle::new("2026-10-18T10:00:00Z", vec![]);
        bundle.format_version = CURRENT_BUNDLE_FORMAT_VERSION + 1;
        let text = bundle.encoded().unwrap();
        match SavedQueryBundle::decode(&text) {
            Err(SavedQueryError::TooNew(v)) => {
                assert_eq!(v, CURRENT_BUNDLE_FORMAT_VERSION + 1)
            }
            other => panic!("版本更新时必须拒绝，实际：{other:?}"),
        }
        assert!(matches!(
            SavedQueryBundle::decode("{ 这不是 JSON"),
            Err(SavedQueryError::Malformed(_))
        ));
    }
}
