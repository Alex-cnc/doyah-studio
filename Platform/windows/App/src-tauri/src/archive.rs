//! 查询自动归档的**落盘**（`FR-EDIT-31` · Windows 侧表示层）
//!
//! 口径（与 `saved_queries.rs` 同一分层）：
//! ① **格式与合并规则不在这里** —— 条目长什么样、同一条 SQL 怎么累计次数，全在领域口径
//!    `App/src/workspace/archive.ts`（纯函数 + 单测）；本文件只管「放哪儿、怎么取」。
//!    这样「一次渲染 / 一次解析」只有一处，界面拿文件里的内容就能显示，不会出现两份格式。
//! ② **按天一个文件**：`queries/<YYYY-MM-DD>.sql`，日期由界面按**本地时区**算好传进来
//!    （服务端不猜时区 —— 归档是给人看的，日子要跟用户看到的一致）；
//! ③ **日期键严格校验**：只许 `YYYY-MM-DD` 且月 / 日在合法区间 —— 它拼进路径，
//!    不做校验就等于把「写任意文件」交给前端；
//! ④ **文件不存在 = 空内容**（第一次使用不是错误）；读不出来 / 写不进去要**点名路径**。

use std::path::{Path, PathBuf};

use crate::postgres::DbFailure;

/// 一天一份归档文件的内容与身份（界面拿 `path` 显示「这份在哪儿」）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ArchiveFile {
    /// 日期键（`YYYY-MM-DD`）。
    pub date_key: String,
    /// 绝对路径（界面上要能照着去找）。
    pub path: String,
    /// 文件内容（不存在时为空串）。
    pub content: String,
    /// 内容字节数（UTF-8；界面的「多大」读数）。
    pub bytes: usize,
}

/// 归档目录 + 按天取文件。
pub struct ArchiveStore {
    /// 归档根目录（`...\DoyahStudio\queries`）。
    pub root: PathBuf,
}

impl ArchiveStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    /// 默认落点：`%APPDATA%\DoyahStudio\queries`（与 `saved-queries.json` 同父目录）。
    /// 取不到 `APPDATA` 就退到当前目录下的 `queries` —— **不静默丢数据**，路径会回到界面上。
    pub fn default_root() -> PathBuf {
        match std::env::var("APPDATA") {
            Ok(base) if !base.trim().is_empty() => Path::new(&base).join("DoyahStudio").join("queries"),
            _ => PathBuf::from("queries"),
        }
    }

    /// 日期键 → 文件路径（**校验失败即拒**）。
    fn path_for(&self, date_key: &str) -> Result<PathBuf, DbFailure> {
        if !is_date_key(date_key) {
            return Err(DbFailure {
                message: format!("归档日期不合法：「{date_key}」"),
                hint: "日期只接受 YYYY-MM-DD（例如 2026-10-18）。".to_string(),
            });
        }
        Ok(self.root.join(format!("{date_key}.sql")))
    }

    /// 读一天的内容。文件不存在 ⇒ 空内容；读不出来 ⇒ 可读失败（**不当成「今天没有」**）。
    pub fn read(&self, date_key: &str) -> Result<ArchiveFile, DbFailure> {
        let path = self.path_for(date_key)?;
        if !path.exists() {
            return Ok(ArchiveFile {
                date_key: date_key.to_string(),
                path: path.display().to_string(),
                content: String::new(),
                bytes: 0,
            });
        }
        let content = std::fs::read_to_string(&path).map_err(|e| DbFailure {
            message: format!("读归档失败：{e}（{}）", path.display()),
            hint: "确认该文件可读；它不是数据库，删掉只丢这一天的归档记录。".to_string(),
        })?;
        Ok(ArchiveFile {
            date_key: date_key.to_string(),
            path: path.display().to_string(),
            bytes: content.len(),
            content,
        })
    }

    /// 写一天的内容（**整份覆盖**：文件就是唯一事实源，不做增量追加）。
    pub fn write(&self, date_key: &str, content: &str) -> Result<ArchiveFile, DbFailure> {
        let path = self.path_for(date_key)?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| DbFailure {
                message: format!("建归档目录失败：{e}（{}）", parent.display()),
                hint: "确认该目录可写。".to_string(),
            })?;
        }
        std::fs::write(&path, content).map_err(|e| DbFailure {
            message: format!("写归档失败：{e}（{}）", path.display()),
            hint: "确认该文件可写（可能被杀毒软件 / 权限限制）。".to_string(),
        })?;
        Ok(ArchiveFile {
            date_key: date_key.to_string(),
            path: path.display().to_string(),
            bytes: content.len(),
            content: content.to_string(),
        })
    }
}

/// `YYYY-MM-DD` 且月 01~12、日 01~31（不查闰年：差一天不可能拼出别的路径）。
pub fn is_date_key(value: &str) -> bool {
    let bytes = value.as_bytes();
    if bytes.len() != 10 {
        return false;
    }
    for (index, byte) in bytes.iter().enumerate() {
        match index {
            4 | 7 => {
                if *byte != b'-' {
                    return false;
                }
            }
            _ => {
                if !byte.is_ascii_digit() {
                    return false;
                }
            }
        }
    }
    let month: u32 = value[5..7].parse().unwrap_or(0);
    let day: u32 = value[8..10].parse().unwrap_or(0);
    (1..=12).contains(&month) && (1..=31).contains(&day)
}

#[cfg(test)]
mod tests {
    use super::*;

    // 夹具根：与 `saved_queries.rs` 同一处（系统临时区在本机沙箱里拒写，用仓外固定目录）。
    fn fixture_root() -> PathBuf {
        match std::env::var("DOYAH_TEST_ROOT") {
            Ok(value) if !value.trim().is_empty() => PathBuf::from(value),
            _ => PathBuf::from("D:/AIProjects/_tmp_face2/fish-fixtures"),
        }
    }

    fn tmp_store(tag: &str) -> ArchiveStore {
        let dir = fixture_root().join(format!("doyah-archive-{tag}-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let store = ArchiveStore::new(dir.join("queries"));
        let _ = std::fs::remove_dir_all(&store.root);
        store
    }

    #[test]
    fn a_missing_day_file_is_empty_content_not_an_error() {
        let store = tmp_store("missing");
        let file = store.read("2026-10-18").unwrap();
        assert!(file.content.is_empty());
        assert_eq!(file.bytes, 0);
        assert!(file.path.ends_with("2026-10-18.sql"), "{}", file.path);
    }

    #[test]
    fn content_round_trips_byte_exactly_including_chinese() {
        let store = tmp_store("round-trip");
        let content = "-- 09:05:07 {\"title\":\"月度对账\",\"runs\":2}\nSELECT count(*) FROM 订单;\n";
        store.write("2026-10-18", content).unwrap();
        let back = store.read("2026-10-18").unwrap();
        assert_eq!(back.content, content);
        assert_eq!(back.bytes, content.len());
    }

    #[test]
    fn two_days_do_not_touch_each_other() {
        let store = tmp_store("two-days");
        store.write("2026-10-17", "旧的一天\n").unwrap();
        store.write("2026-10-18", "新的一天\n").unwrap();
        assert_eq!(store.read("2026-10-17").unwrap().content, "旧的一天\n");
        assert_eq!(store.read("2026-10-18").unwrap().content, "新的一天\n");
    }

    #[test]
    fn a_path_like_or_impossible_date_is_refused_before_any_write() {
        let store = tmp_store("bad-key");
        for bad in ["../../evil", "2026-13-01", "2026-10-32", "20261018", "2026-1-1", ""] {
            let err = store.read(bad).unwrap_err();
            assert!(err.message.contains("不合法"), "{bad}: {}", err.message);
            assert!(store.write(bad, "x").is_err(), "{bad} 竟然写进去了");
        }
        assert!(!store.root.exists(), "被拒的键不该建出目录");
    }
}
