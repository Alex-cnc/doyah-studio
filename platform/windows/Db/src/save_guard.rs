//! **保存冲突**的判定（FR-EDIT-36 / 计划 2.3「保存冲突要如实说」）
//!
//! 场景：页签里改着，盘上这份**被别人改过**（另一个编辑器 / 脚本 / `git checkout`）。
//! 这时候保存有两种做法：
//! - **直接覆盖** —— 把别人的改动静默抹掉（最伤人的那种"数据丢失"，而且不可撤销）；
//! - **拒绝保存 + 如实说** —— 让用户先看清盘上是什么，再决定（本模块选这条）。
//!
//! 为什么不能只比时间戳：`staleness` 那一层已经论证过 —— **内容指纹才是权威判据**，
//! "另存了一遍同样的内容"很常见，只按时间戳会天天误报"冲突"。
//!
//! ## 三种结果的差别（都要能在界面上说清）
//! - **可保存**：盘上还是我载入时那份（或盘上已经没有了 —— 那是"新建回去"，不算冲突）；
//! - **冲突**：盘上变了 ⇒ **拒绝**，并把"盘上是哪一份"的信息给界面；
//! - **无变化**：内容与已保存的一模一样 ⇒ **不写盘**（省一次无谓的写，也免得把时间戳搅动）。

use crate::staleness::{classify, LoadedFile, Staleness};

/// 保存的判定结果。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind")]
pub enum SaveDecision {
    /// 可以写盘
    Write {
        /// 盘上这份已经**不存在**了（页签还开着）—— 写回去是"重新建一份"，要如实告诉用户
        recreated: bool,
    },
    /// **不写**：内容与已保存的一模一样（没什么可存的）
    NothingToDo,
    /// **拒绝**：盘上被改过（或已被替换）—— 不能让这次保存把别人的改动抹掉
    Conflict { staleness: Staleness },
}

/// 判定"这次保存能不能写"。
///
/// `current` = 页签里现在的内容；`saved` = 上次保存时的内容；`loaded` = 载入时的磁盘快照；
/// `now_on_disk` = 盘上此刻的状态（盘上没有了传 `None`）。
pub fn decide_save(
    current: &str,
    saved: &str,
    loaded: &LoadedFile,
    now_on_disk: Option<&crate::staleness::DiskFile>,
) -> SaveDecision {
    // ① 什么都没改 ⇒ 不写盘（**不搅动时间戳**，也省一次 IO）
    if current == saved {
        return SaveDecision::NothingToDo;
    }
    // ② 盘上变了 ⇒ **拒绝**（这是本模块存在的理由）
    match classify(loaded, now_on_disk) {
        Staleness::Unchanged => SaveDecision::Write { recreated: false },
        // 盘上没有了：页签里还有内容 ⇒ 写回去是"重新建一份"。**不算冲突** ——
        // 冲突的含义是"会覆盖别人的改动"，而这里盘上没有别人的改动可覆盖。
        Staleness::Deleted => SaveDecision::Write { recreated: true },
        // 被改过 / 被替换：**拒绝**，让用户先看清
        other => SaveDecision::Conflict { staleness: other },
    }
}

/// 用户**明确选择覆盖**时的判定（界面上是"用我的版本覆盖"那一档）。
///
/// 与 `decide_save` 的差别只有一处：**冲突不再拦**。但"什么都没改"仍然不写盘。
pub fn decide_overwrite(current: &str, saved: &str, staleness: Staleness) -> SaveDecision {
    if current == saved {
        return SaveDecision::NothingToDo;
    }
    SaveDecision::Write {
        recreated: staleness == Staleness::Deleted,
    }
}

/// 给界面的一句说明（**说清盘上是什么、以及下一步能选什么**）。
pub fn explain_conflict(staleness: Staleness) -> String {
    match staleness {
        Staleness::Modified => "盘上这份文件已经被别处改过了。为免覆盖别人的改动，这次**没有保存**。\
你可以先「比对」（看盘上是什么），再选「用我的版本覆盖」。"
            .to_string(),
        Staleness::Replaced => "盘上这份文件的内容变了（大小与时间戳没变：像是被脚本改写或从别处拷回一份）。\
这次**没有保存**，请先比对再决定。"
            .to_string(),
        Staleness::Deleted => "盘上这份文件已经不在了 —— 保存会**重新建一份**。".to_string(),
        Staleness::Unchanged => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::staleness::{content_hash, DiskFile};

    fn loaded(content: &str, bytes: u64, modified: i64) -> LoadedFile {
        LoadedFile {
            relative_path: "a.txt".to_string(),
            byte_count: bytes,
            modified_unix: Some(modified),
            content_hash: content_hash(content.as_bytes()),
        }
    }

    fn disk(content: &str, bytes: u64, modified: i64) -> DiskFile {
        DiskFile {
            byte_count: bytes,
            modified_unix: Some(modified),
            content_hash: content_hash(content.as_bytes()),
        }
    }

    #[test]
    fn unchanged_content_is_not_written_at_all() {
        // 页签里没改 ⇒ 不写盘（省 IO、也不把时间戳搅动）
        let snapshot = loaded("hello", 5, 100);
        assert_eq!(
            decide_save("hello", "hello", &snapshot, Some(&disk("hello", 5, 100))),
            SaveDecision::NothingToDo
        );
        // 明确覆盖也一样：没改就不写
        assert_eq!(
            decide_overwrite("hello", "hello", Staleness::Modified),
            SaveDecision::NothingToDo
        );
    }

    #[test]
    fn a_normal_save_writes_when_the_disk_still_matches_what_we_loaded() {
        let snapshot = loaded("hello", 5, 100);
        let decision = decide_save("hello world", "hello", &snapshot, Some(&disk("hello", 5, 999)));
        // 时间戳动了但内容一样 ⇒ **不算冲突**（"另存了一遍同样的内容"很常见）
        assert_eq!(decision, SaveDecision::Write { recreated: false });
    }

    #[test]
    fn external_changes_are_refused_rather_than_silently_overwritten() {
        let snapshot = loaded("hello", 5, 100);
        // 盘上被改过 ⇒ 拒绝
        let decision = decide_save("hello world", "hello", &snapshot, Some(&disk("HELLO", 5, 200)));
        assert_eq!(
            decision,
            SaveDecision::Conflict {
                staleness: Staleness::Modified
            }
        );
        // 内容变了但元数据没变（脚本改写）⇒ 也拒绝，而且报的档位不同
        let replaced = decide_save("hello world", "hello", &snapshot, Some(&disk("HELLO", 5, 100)));
        assert_eq!(
            replaced,
            SaveDecision::Conflict {
                staleness: Staleness::Replaced
            }
        );
        // 说明里要给出下一步（比对 / 覆盖）
        let text = explain_conflict(Staleness::Modified);
        assert!(text.contains("没有保存") && text.contains("覆盖"), "{text}");
        let replaced_text = explain_conflict(Staleness::Replaced);
        assert!(replaced_text.contains("大小与时间戳没变"), "{replaced_text}");
        // 未变时说明是空的（不打扰）
        assert!(explain_conflict(Staleness::Unchanged).is_empty());
    }

    #[test]
    fn a_file_deleted_on_disk_is_recreated_not_treated_as_a_conflict() {
        let snapshot = loaded("hello", 5, 100);
        let decision = decide_save("hello world", "hello", &snapshot, None);
        // 盘上没有了 ⇒ 写回去是"重新建一份"，**不算冲突**（没有别人的改动可覆盖）
        assert_eq!(decision, SaveDecision::Write { recreated: true });
        assert!(explain_conflict(Staleness::Deleted).contains("重新建一份"));
        // 明确覆盖时也标出"这是重建"
        assert_eq!(
            decide_overwrite("hello world", "hello", Staleness::Deleted),
            SaveDecision::Write { recreated: true }
        );
    }

    #[test]
    fn explicit_overwrite_bypasses_the_conflict_but_not_the_no_change_rule() {
        let snapshot = loaded("hello", 5, 100);
        // 冲突时用户选"覆盖" ⇒ 放行（这是用户的明确选择）
        assert_eq!(
            decide_overwrite("hello world", "hello", Staleness::Modified),
            SaveDecision::Write { recreated: false }
        );
        // 但那之前 `decide_save` 必须已经拦过一次（顺序不能反）
        assert!(matches!(
            decide_save("hello world", "hello", &snapshot, Some(&disk("HELLO", 5, 200))),
            SaveDecision::Conflict { .. }
        ));
    }

    #[test]
    fn decision_serialises_with_a_kind_tag() {
        let text = serde_json::to_string(&SaveDecision::Write { recreated: true }).unwrap();
        assert!(text.contains("\"kind\":\"write\""), "{text}");
        assert!(text.contains("\"recreated\":true"), "{text}");
        let conflict = serde_json::to_string(&SaveDecision::Conflict {
            staleness: Staleness::Modified,
        })
        .unwrap();
        assert!(conflict.contains("\"kind\":\"conflict\""), "{conflict}");
        assert!(conflict.contains("\"modified\""), "{conflict}");
        let back: SaveDecision = serde_json::from_str(&text).unwrap();
        assert_eq!(back, SaveDecision::Write { recreated: true });
    }
}
