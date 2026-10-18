//! 已保存查询的**落盘**（Windows 侧表示层）
//!
//! 口径（与 `connections.rs` 同一分层）：
//! ① 模型与「同名覆盖」判定在领域层 `doyah_studio_db::saved_query`，本文件只管「放哪儿、怎么取」；
//! ② **文件不存在 = 空列表**（首次使用不是错误）；文件坏了 = 可读失败（不静默当「没有」）；
//! ③ 写是**整份覆盖**：列表就是唯一事实源，不做增量合并（半截写入比旧数据更糟）。
//!
//! 为什么和连接列表分开一个文件：连接配置里带主机 / 用户，是有安全面的；已保存查询只是
//! 名字 + SQL，混进 `connections.json` 会让「导出连接配置」连带把用户的 SQL 带出去。

use std::path::{Path, PathBuf};

use doyah_studio_db::saved_query::{SavedQuery, SavedQueryBundle};

use crate::postgres::DbFailure;

/// 已保存查询的存储。
pub struct SavedQueryStore {
    /// 文件路径（`saved-queries.json`）。
    pub path: PathBuf,
}

impl SavedQueryStore {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self { path: path.into() }
    }

    /// 默认落点：`%APPDATA%\DoyahStudio\saved-queries.json`（与 `connections.json` 同目录）。
    /// 取不到 `APPDATA` 就退到当前目录 —— **不静默丢数据**，调用方看得到路径。
    pub fn default_path() -> PathBuf {
        match std::env::var("APPDATA") {
            Ok(base) if !base.trim().is_empty() => Path::new(&base)
                .join("DoyahStudio")
                .join("saved-queries.json"),
            _ => PathBuf::from("saved-queries.json"),
        }
    }

    /// 读列表。文件不存在 ⇒ 空列表；文件坏了 ⇒ 可读失败（点名文件与出路）。
    pub fn load(&self) -> Result<Vec<SavedQuery>, DbFailure> {
        if !self.path.exists() {
            return Ok(Vec::new());
        }
        let text = std::fs::read_to_string(&self.path).map_err(|e| DbFailure {
            message: format!("读已保存查询失败：{e}（{}）", self.path.display()),
            hint: "确认该文件可读；若内容坏了，先备份再删掉它（只会清掉已保存的查询，不动数据库里的数据）。"
                .to_string(),
        })?;
        if text.trim().is_empty() {
            return Ok(Vec::new());
        }
        match SavedQueryBundle::decode(&text) {
            Ok(bundle) => Ok(bundle.queries),
            Err(err) => Err(DbFailure {
                message: format!("已保存查询读不出来：{err}"),
                hint: "文件可能来自更新版本的客户端或已损坏；先备份再删掉它即可从空列表重建。"
                    .to_string(),
            }),
        }
    }

    /// 写列表（整份覆盖）。
    pub fn save(&self, queries: &[SavedQuery], saved_at: &str) -> Result<(), DbFailure> {
        if let Some(parent) = self.path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| DbFailure {
                message: format!("建目录失败：{e}（{}）", parent.display()),
                hint: "确认该目录可写。".to_string(),
            })?;
        }
        let bundle = SavedQueryBundle::new(saved_at, queries.to_vec());
        let text = bundle.encoded().map_err(|e| DbFailure {
            message: format!("已保存查询序列化失败：{e}"),
            hint: "这属实现缺陷：请保留现场并报告。".to_string(),
        })?;
        std::fs::write(&self.path, text).map_err(|e| DbFailure {
            message: format!("写已保存查询失败：{e}（{}）", self.path.display()),
            hint: "确认该文件可写（可能被杀毒软件 / 权限限制）。".to_string(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use doyah_studio_db::saved_query::SavedQuery;

    // 夹具根：与 `connections.rs` 同一处（系统临时区在本机沙箱里拒写，用仓外固定目录）。
    fn fixture_root() -> PathBuf {
        match std::env::var("DOYAH_TEST_ROOT") {
            Ok(value) if !value.trim().is_empty() => PathBuf::from(value),
            _ => PathBuf::from("D:/AIProjects/_tmp_face2/fish-fixtures"),
        }
    }

    fn tmp_store(tag: &str) -> SavedQueryStore {
        let dir = fixture_root().join(format!("doyah-saved-{tag}-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        SavedQueryStore::new(dir.join("saved-queries.json"))
    }

    #[test]
    fn a_missing_file_is_an_empty_list_not_an_error() {
        let store = tmp_store("missing");
        let _ = std::fs::remove_file(&store.path);
        assert!(store.load().unwrap().is_empty());
    }

    #[test]
    fn a_broken_file_fails_with_a_readable_reason() {
        let store = tmp_store("broken");
        std::fs::write(&store.path, "{ 这不是 JSON").unwrap();
        let err = store.load().unwrap_err();
        assert!(err.message.contains("读不出来"), "{}", err.message);
        assert!(!err.hint.is_empty());
    }

    #[test]
    fn saved_queries_round_trip_through_the_file() {
        let store = tmp_store("round-trip");
        let _ = std::fs::remove_file(&store.path);

        let mut one = SavedQuery::new("id-1", " 月度对账 ", "select *\n  from t");
        one.connection_name = Some("实验库".into());
        one.database = Some("doyah_lab".into());
        one.saved_at = "2026-10-18T10:00:00Z".into();
        let two = SavedQuery::new("id-2", "慢查询排查", "select pid from pg_stat_activity");

        store
            .save(&[one.clone(), two.clone()], "2026-10-18T10:00:00Z")
            .unwrap();
        let back = store.load().unwrap();
        assert_eq!(back.len(), 2);
        assert_eq!(back[0], one.sanitized());
        assert_eq!(back[1], two);
    }
}
