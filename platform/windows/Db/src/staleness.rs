//! **外部改动**的判定（FR-EDIT-43 / 计划 2.3 那条「外部改动要如实说」）
//!
//! 由头：文件在别处被改了（另一个编辑器、一个脚本、一次 `git checkout`），而我们的页签还拿着
//! **载入时的那份内容**。这时候最伤人的不是"内容旧了"，而是**界面不说** —— 用户以为看的就是盘上的。
//!
//! 所以这一层只回答一个问题：**这个页签拿的内容，与盘上现在那份，还是同一份吗？**
//! 四种结果各对应界面上一句不同的话（**没有"也许"这一档**：判不出来就说判不出来）。
//!
//! 判定顺序（**先看内容指纹**）：指纹一样 ⇒ 未变（时间戳变了也不算 —— 可能是"另存了一遍同样的内容"；
//! 只按时间戳报"被改过"会天天误报）。指纹不同或没有指纹 ⇒ 再看大小与修改时间。
//!
//! 三条取舍：
//!   ① **时间戳按秒比**：Windows 上文件时间的有效精度常见 1~2 秒，按更细的粒度比会误报；
//!   ② **盘上没有了 ⇒ 说"已删除"**，不是"已改动"（两件事用户要做的事不一样）；
//!   ③ **指纹不一样但大小与时间都没变 ⇒ 说"已替换"**（内容变了、元数据没变：脚本改写、
//!      从别处拷回来一份同样是新文件）—— 这一档最容易漏，单独报出来。

/// 载入页签那一刻记下的磁盘状态。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoadedFile {
    pub relative_path: String,
    /// 载入时的字节数
    pub byte_count: u64,
    /// 载入时的修改时间（Unix 秒；`None` = 拿不到 —— 那就只按指纹与大小判）
    pub modified_unix: Option<i64>,
    /// 内容的短指纹（**判定的第一依据**）
    pub content_hash: u64,
}

/// 这一刻盘上的状态。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DiskFile {
    pub byte_count: u64,
    pub modified_unix: Option<i64>,
    pub content_hash: u64,
}

/// 页签内容与盘上现在那份的关系。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Staleness {
    /// 还是同一份（指纹一致）—— **不打扰用户**
    Unchanged,
    /// 盘上被改过（指纹或大小/时间对不上）
    Modified,
    /// 盘上没有了（被删或被移走）
    Deleted,
    /// 内容变了但元数据没变（脚本改写 / 从别处拷回同样的新文件）
    Replaced,
}

impl Staleness {
    /// 供界面取文案的**稳定键**（句子在语言表里）。
    pub const fn key(self) -> &'static str {
        match self {
            Staleness::Unchanged => "editorStale.unchanged",
            Staleness::Modified => "editorStale.modified",
            Staleness::Deleted => "editorStale.deleted",
            Staleness::Replaced => "editorStale.replaced",
        }
    }

    /// 要不要让用户看见（只有"还是同一份"才安静）。
    pub const fn needs_attention(self) -> bool {
        !matches!(self, Staleness::Unchanged)
    }
}

/// 内容短指纹（FNV-1a）。
///
/// 为什么自己写而不是引依赖：**只需要"两个内容一样不一样"**，不需要抗碰撞的密码学性质；
/// 为这点用途拉一个哈希库进领域层不划算（本模块到现在只有 serde 一个依赖，保持它）。
/// 万一碰撞，后果是"漏报一次外部改动"（还有大小与时间戳两道在旁边），不是安全问题。
pub fn content_hash(bytes: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in bytes {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
}

/// 判定一个页签的内容与盘上现在那份是否还是同一份。
pub fn classify(loaded: &LoadedFile, now_on_disk: Option<&DiskFile>) -> Staleness {
    let Some(disk) = now_on_disk else {
        return Staleness::Deleted;
    };

    // ① **指纹是权威判据**：一样就是没变（时间戳变了也不算 —— "另存了一遍同样的内容"很常见）
    if disk.content_hash == loaded.content_hash {
        return Staleness::Unchanged;
    }

    // ② 大小或时间变了 ⇒ 被改过
    if disk.byte_count != loaded.byte_count {
        return Staleness::Modified;
    }
    match (disk.modified_unix, loaded.modified_unix) {
        (Some(now), Some(then)) => {
            // **按秒比**（Windows 上文件时间精度常见 1~2 秒，比得更细会误报）
            if now / 1 != then / 1 {
                return Staleness::Modified;
            }
            Staleness::Replaced
        }
        // 时间戳拿不到（两侧有一侧是 None）：指纹已经不同、大小却一样 ⇒ 只能是"已替换"
        _ => Staleness::Replaced,
    }
}

/// 一句**人话**（中文；英文由界面语言表出 —— 这里给的是命令层兜底句）。
///
/// 刻意说出**下一步能做什么**：只说"文件变了"等于把问题丢回给用户。
pub fn note(staleness: Staleness) -> Option<String> {
    match staleness {
        Staleness::Unchanged => None,
        Staleness::Modified => Some(
            "盘上这份文件在别处被改过了；这里显示的还是打开时那份。要看最新的，请重新打开它（本版只读，不会覆盖你的改动）。"
                .to_string(),
        ),
        Staleness::Deleted => Some("盘上这份文件已经不在了（被删除或移走）。".to_string()),
        Staleness::Replaced => Some(
            "盘上这份文件的内容变了，但大小与时间戳没变（像是被脚本改写或从别处拷回一份）。请重新打开它。"
                .to_string(),
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn loaded(hash: u64, bytes: u64, modified: Option<i64>) -> LoadedFile {
        LoadedFile {
            relative_path: "a.txt".to_string(),
            byte_count: bytes,
            modified_unix: modified,
            content_hash: hash,
        }
    }

    fn disk(hash: u64, bytes: u64, modified: Option<i64>) -> DiskFile {
        DiskFile {
            byte_count: bytes,
            modified_unix: modified,
            content_hash: hash,
        }
    }

    #[test]
    fn same_fingerprint_means_unchanged_even_if_the_timestamp_moved() {
        // "另存了一遍同样的内容"很常见：只按时间戳报"被改过"会天天误报
        let loaded = loaded(0xAAAA, 10, Some(1000));
        assert_eq!(classify(&loaded, Some(&disk(0xAAAA, 10, Some(2000)))), Staleness::Unchanged);
        // 完全相同当然也是未变
        assert_eq!(classify(&loaded, Some(&disk(0xAAAA, 10, Some(1000)))), Staleness::Unchanged);
        // 未变时**不打扰**用户
        assert!(!Staleness::Unchanged.needs_attention());
        assert!(note(Staleness::Unchanged).is_none());
    }

    #[test]
    fn a_different_fingerprint_with_a_different_size_is_a_modification() {
        let loaded = loaded(0xAAAA, 10, Some(1000));
        let result = classify(&loaded, Some(&disk(0xBBBB, 12, Some(1005))));
        assert_eq!(result, Staleness::Modified);
        assert!(result.needs_attention());
        assert!(note(result).unwrap().contains("重新打开"));
    }

    #[test]
    fn a_moved_timestamp_with_the_same_size_is_also_a_modification() {
        // 大小没变但时间变了（改了内容又改回同样长度）
        let loaded = loaded(0xAAAA, 10, Some(1000));
        assert_eq!(classify(&loaded, Some(&disk(0xBBBB, 10, Some(1001)))), Staleness::Modified);
    }

    #[test]
    fn same_size_and_same_second_but_a_different_fingerprint_is_a_replacement() {
        // 这一档最容易漏：内容变了、元数据没变（脚本改写 / 从别处拷回一份）
        let file = loaded(0xAAAA, 10, Some(1000));
        let result = classify(&file, Some(&disk(0xBBBB, 10, Some(1000))));
        assert_eq!(result, Staleness::Replaced);
        assert!(note(result).unwrap().contains("脚本改写"));
        // 时间戳拿不到时同理
        assert_eq!(classify(&file, Some(&disk(0xBBBB, 10, None))), Staleness::Replaced);
        let without_timestamp = loaded(0xAAAA, 10, None);
        assert_eq!(
            classify(&without_timestamp, Some(&disk(0xBBBB, 10, None))),
            Staleness::Replaced
        );
    }

    #[test]
    fn a_missing_file_is_reported_as_deleted_not_as_modified() {
        let loaded = loaded(0xAAAA, 10, Some(1000));
        let result = classify(&loaded, None);
        assert_eq!(result, Staleness::Deleted, "两件事用户要做的不一样，不能混成一句");
        assert!(note(result).unwrap().contains("已经不在了"));
    }

    #[test]
    fn timestamps_are_compared_by_the_second_only() {
        // 同一秒内的细微差别不该报"被改过"（Windows 上文件时间精度常见 1~2 秒）
        let loaded = loaded(0xAAAA, 10, Some(1000));
        assert_eq!(classify(&loaded, Some(&disk(0xBBBB, 10, Some(1000)))), Staleness::Replaced);
        // 差一秒就是改动
        assert_eq!(classify(&loaded, Some(&disk(0xBBBB, 10, Some(1001)))), Staleness::Modified);
    }

    #[test]
    fn content_hash_is_stable_and_detects_changes() {
        assert_eq!(content_hash(b""), content_hash(b""));
        assert_eq!(content_hash(b"abc"), content_hash(b"abc"));
        assert_ne!(content_hash(b"abc"), content_hash(b"abd"));
        // 顺序也算（不是集合比较）
        assert_ne!(content_hash(b"ab"), content_hash(b"ba"));
        // 已知值：锁住实现，避免以后换算法却没意识到会影响"判定同一份文件"
        assert_eq!(content_hash(b"abc"), 0xe71f_a219_0541_574b);
        // 中文内容按字节算（UTF-8）
        assert_ne!(content_hash("中文".as_bytes()), content_hash("中".as_bytes()));
    }

    #[test]
    fn keys_are_distinct_and_serialisation_is_camel_case() {
        let all = [
            Staleness::Unchanged,
            Staleness::Modified,
            Staleness::Deleted,
            Staleness::Replaced,
        ];
        let keys: std::collections::HashSet<&str> = all.iter().map(|s| s.key()).collect();
        assert_eq!(keys.len(), all.len(), "每一档都要有自己的提示键");
        let text = serde_json::to_string(&Staleness::Replaced).unwrap();
        assert_eq!(text, "\"replaced\"");
        // 状态结构往返
        let file = loaded(0xAAAA, 10, Some(1000));
        let back: LoadedFile = serde_json::from_str(&serde_json::to_string(&file).unwrap()).unwrap();
        assert_eq!(back, file);
    }
}
