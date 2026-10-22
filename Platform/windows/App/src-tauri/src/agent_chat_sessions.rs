//! **对话会话的落盘面**（`FR-AI-17` · Windows 侧表示层）
//!
//! 分层与 `agent_settings.rs` / `saved_queries.rs` 一致：形状、归属校验、上限、坏文件兜底、段号与标题
//! 全在领域层（`doyah_studio_db::agent_chat_session`），本模块只管「放哪儿、怎么取」。
//!
//! 为什么一个工作区**可以有多段**、每段一份文件（而不是全塞进一份）：
//! ① 生成历史是「问过什么 SQL」的回看清单，一次外发一条；对话是**长文本、多轮、按项目分**的东西，
//!   两个工作区的对话混在一份文件里，模型下回就会看见别的项目的表名；
//! ② 一份对话文件坏掉，只该影响那一段的回看 —— 不该把别的项目 / 别的段的对话一起拖下水；
//! ③ 换话题不必「清空」（清空等于把上一段扔了）：新建一段即可，上一段原样留在盘上。
//!
//! 落点：`%APPDATA%\DoyahStudio\chat\chat-<工作区哈希>[-段号].json`（文件名由领域层派生，见
//! `file_name_for_id`：路径里的 `..` / 分隔符进不了文件名）。段 `1` = 升级前的老文件（逐字节兼容，
//! 不迁移）；「当前是哪一段」记在同目录的 `chat-<哈希>.active`（纯文本段号，只认数字）。

use std::path::{Path, PathBuf};

use doyah_studio_db::agent_chat_session::{
    active_from_text, bounded, file_name_for_id, file_stem_for, is_usable_workspace, load_json,
    newest_first, next_session_id, normalize_id, parse_session_id, summarize, ChatSession,
    SessionSummary, DEFAULT_ID,
};
use doyah_studio_db::agent_nl2sql::ChatMessage;
use serde::Serialize;

use crate::postgres::DbFailure;

/// 对话会话的存储（目录可由调用方指定 —— 单测与探针用它把文件挪到临时目录）。
pub struct ChatSessionStore {
    /// 会话文件所在目录（每个工作区的每一段一份文件）。
    pub dir: PathBuf,
}

/// 读回来的会话（给界面的一份完整交代：是哪一段 + 消息 + 路径 + 读的时候发生了什么）。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatSessionReport {
    /// 段号（界面「当前是哪一段」用；空工作区为空串）。
    pub id: String,
    /// 这段对话属于哪个工作区（原样回给界面，便于界面显示它绑的是谁）。
    pub workspace: String,
    /// 会话文件路径（让用户知道去哪儿看；没打开工作区时为空）。
    pub path: String,
    /// 消息序列（最早的在前）。
    pub messages: Vec<ChatMessage>,
    /// 读的时候跳过的条数。
    pub skipped: usize,
    /// 读的时候截断过的条数。
    pub clipped: usize,
    /// 照实要说的话（坏文件 / 属于别的工作区 / 有跳过）；正常时为空数组。
    pub notes: Vec<String>,
    /// 这一段里问了几句（界面「第 N 问」用）。
    pub questions: usize,
}

/// 写盘的结果（**丢了几条、截了几条都要回给界面**，不许静默）。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatSessionSaved {
    /// 写到哪一段。
    pub id: String,
    /// 写到哪个文件。
    pub path: String,
    /// 落盘后实际几条消息。
    pub messages: usize,
    /// 因超上限 / 开头对齐被移出文件的最早几条。
    pub dropped: usize,
    /// 正文超长被截断的条数。
    pub clipped: usize,
    /// 角色不认识 / 正文空白而丢弃的条数。
    pub invalid: usize,
    /// 写入时刻（epoch 秒）。
    pub updated_secs: u64,
}

/// 列表里的一段对话（标题由第一句提问派生，落盘形状不动 ⇒ 升级前的旧文件照样有标题）。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatSessionEntry {
    /// 段号。
    pub id: String,
    /// 标题（没有提问 ⇒ 空串，界面自己说「新对话」）。
    pub title: String,
    /// 这段里问了几句。
    pub questions: usize,
    /// 留存的消息条数。
    pub messages: usize,
    /// 最后一次写入的时刻（epoch 秒）。
    pub updated_secs: u64,
    /// 这一段读不出来 / 属于别的工作区 / 版本不认识 ⇒ 原因（**这一段跳过**，其余段照常可用）。
    pub problem: Option<String>,
}

/// 一个工作区的对话列表（界面下拉用）。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatSessionList {
    /// 会话目录（界面「去哪儿找这些文件」）。
    pub dir: String,
    /// 各段摘要（新的在前）。
    pub entries: Vec<ChatSessionEntry>,
    /// 有几段读不出来（**跳过并计数**，不静默丢，也不让整个列表不可用）。
    pub broken: usize,
    /// 当前是哪一段（指针文件；没有指针 = 最新那段）。
    pub active: String,
}

impl ChatSessionStore {
    /// 指定目录。
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        Self { dir: dir.into() }
    }

    /// 默认落点：`%APPDATA%\DoyahStudio\chat`（与配置 / 历史 / 审计同根目录、另一个子目录 ——
    /// 会话是长文本，单独一层便于用户整批备份或清掉）。
    /// 取不到 `APPDATA` 就退到当前目录 —— **不静默丢数据**，界面拿得到路径。
    pub fn default_store() -> Self {
        Self::new(crate::paths::app_path("chat"))
    }

    /// 某个工作区默认段的会话文件路径（文件名由领域层派生 ⇒ 调用方给什么路径都安全）。
    pub fn path_for(&self, workspace: &str) -> PathBuf {
        self.path_for_id(workspace, DEFAULT_ID)
    }

    /// 某个工作区第 N 段的会话文件路径。
    pub fn path_for_id(&self, workspace: &str, id: &str) -> PathBuf {
        self.dir.join(file_name_for_id(workspace, id))
    }

    /// 「当前是哪一段」的指针文件（纯文本段号；与对话文件同一个目录）。
    fn active_path(&self, workspace: &str) -> PathBuf {
        self.dir.join(format!("{}.active", file_stem_for(workspace)))
    }

    fn read_active(&self, workspace: &str) -> Option<String> {
        let text = std::fs::read_to_string(self.active_path(workspace)).ok()?;
        active_from_text(Some(&text))
    }

    /// 记下「当前是哪一段」。**尽力而为**：文件才是真相，指针写不进去不该让一次成功的落盘变成失败。
    fn write_active(&self, workspace: &str, id: &str) -> bool {
        let path = self.active_path(workspace);
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        std::fs::write(&path, id.as_bytes()).is_ok()
    }

    /// 这个工作区盘上现有的各段（只读；坏文件单列 `problem`，不抛错）。
    fn entries(&self, workspace: &str) -> Vec<SessionSummary> {
        if !is_usable_workspace(workspace) {
            return Vec::new();
        }
        let mut found: Vec<SessionSummary> = Vec::new();
        let Ok(read) = std::fs::read_dir(&self.dir) else {
            // 目录还不存在 = 一段都没存过（不是错误）。
            return found;
        };
        for item in read.flatten() {
            let name = item.file_name().to_string_lossy().to_string();
            // 只认**本工作区**的名字（另一工作区的哈希不同 ⇒ 不会串；`.active` / `.tmp` 也不算）。
            let Some(id) = parse_session_id(workspace, &name) else {
                continue;
            };
            let text = match std::fs::read_to_string(item.path()) {
                Ok(text) => text,
                Err(err) => {
                    found.push(SessionSummary {
                        id,
                        title: String::new(),
                        questions: 0,
                        messages: 0,
                        updated_secs: 0,
                        problem: Some(format!("读不出来：{err}")),
                    });
                    continue;
                }
            };
            let load = load_json(workspace, &text);
            found.push(summarize(&id, &load.session, &load.notes));
        }
        newest_first(found)
    }

    /// 当前段号：指针文件优先；指针指向的那段已经不在了 / 没有指针 ⇒ 最新那段；一段都没有 ⇒ 默认段。
    fn active_id(&self, workspace: &str, entries: &[SessionSummary]) -> String {
        if let Some(id) = self.read_active(workspace) {
            if entries.iter().any(|entry| entry.id == id) {
                return id;
            }
        }
        match entries.first() {
            Some(entry) => entry.id.clone(),
            None => DEFAULT_ID.to_string(),
        }
    }

    /// 这个工作区的对话列表（界面下拉 + 坏文件计数）。
    pub fn list(&self, workspace: &str) -> ChatSessionList {
        let entries = self.entries(workspace);
        let broken = entries.iter().filter(|entry| entry.problem.is_some()).count();
        let active = if is_usable_workspace(workspace) {
            self.active_id(workspace, &entries)
        } else {
            String::new()
        };
        ChatSessionList {
            dir: self.dir.display().to_string(),
            entries: entries
                .into_iter()
                .map(|entry| ChatSessionEntry {
                    id: entry.id,
                    title: entry.title,
                    questions: entry.questions,
                    messages: entry.messages,
                    updated_secs: entry.updated_secs,
                    problem: entry.problem,
                })
                .collect(),
            broken,
            active,
        }
    }

    /// 读**当前段**的对话（指针 → 最新 → 默认段）。
    ///
    /// 文件不存在 = 第一次打开 = 空对话（不是错误，也不写盘）；文件坏了 / 属于别的工作区
    /// ⇒ 空对话 + 说清（口径见领域层模块头）。没打开工作区 ⇒ 空对话且 `path` 为空。
    pub fn load(&self, workspace: &str) -> ChatSessionReport {
        if !is_usable_workspace(workspace) {
            return self.empty_report(workspace, "", "");
        }
        let entries = self.entries(workspace);
        let id = self.active_id(workspace, &entries);
        self.load_id(workspace, &id)
    }

    /// 读**指定段**的对话。
    pub fn load_id(&self, workspace: &str, id: &str) -> ChatSessionReport {
        let id = normalize_id(id);
        let id = if id.is_empty() {
            DEFAULT_ID.to_string()
        } else {
            id
        };
        if !is_usable_workspace(workspace) {
            return self.empty_report(workspace, "", "");
        }
        let path = self.path_for_id(workspace, &id);
        let text = match std::fs::read_to_string(&path) {
            Ok(text) => text,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => String::new(),
            Err(err) => {
                // 读不出来（权限 / 编码）：当空对话，但**说清是哪个文件读不了** ——
                // 静默当空会让人以为「对话被吞了」。
                let mut report = self.empty_report(workspace, &id, &path.display().to_string());
                report.notes.push(format!(
                    "这份对话记录读不出来（{err}）：{}",
                    path.display()
                ));
                return report;
            }
        };
        let load = load_json(workspace, &text);
        ChatSessionReport {
            id,
            workspace: workspace.to_string(),
            path: path.display().to_string(),
            messages: load.session.messages.clone(),
            skipped: load.skipped,
            clipped: load.clipped,
            notes: load.notes,
            questions: load.session.questions(),
        }
    }

    fn empty_report(&self, workspace: &str, id: &str, path: &str) -> ChatSessionReport {
        ChatSessionReport {
            id: id.to_string(),
            workspace: workspace.to_string(),
            path: path.to_string(),
            messages: Vec::new(),
            skipped: 0,
            clipped: 0,
            notes: Vec::new(),
            questions: 0,
        }
    }

    /// 写**默认段**（升级前那一段的兼容入口）。
    pub fn save(
        &self,
        workspace: &str,
        messages: &[ChatMessage],
        at_secs: u64,
    ) -> Result<ChatSessionSaved, DbFailure> {
        self.save_id(workspace, DEFAULT_ID, messages, at_secs)
    }

    /// 写**指定段**的对话（整份覆盖：会话文件就是唯一事实源，不做增量合并）。
    ///
    /// 写完把「当前段」指针指到这一段的段号（落盘哪段就是哪段 ⇒ 重开应用回到刚才在聊的那段）。
    /// **写不进去要报错**：这一次对话没留下痕迹是用户该知道的事，但**不阻断发送**。
    pub fn save_id(
        &self,
        workspace: &str,
        id: &str,
        messages: &[ChatMessage],
        at_secs: u64,
    ) -> Result<ChatSessionSaved, DbFailure> {
        if !is_usable_workspace(workspace) {
            return Err(DbFailure {
                message: "没有打开工作区，这次对话没处以落盘。".to_string(),
                hint: "先打开一个文件夹（Home「打开文件夹」），对话会按工作区各存一份。".to_string(),
            });
        }
        let id = normalize_id(id);
        let id = if id.is_empty() {
            DEFAULT_ID.to_string()
        } else {
            id
        };
        let path = self.path_for_id(workspace, &id);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| DbFailure {
                message: format!("建对话目录失败：{e}（{}）", parent.display()),
                hint: "确认该目录可写（可能被杀毒软件 / 权限限制）。".to_string(),
            })?;
        }
        let write = bounded(workspace, messages, at_secs);
        let session: ChatSession = write.session;
        let text = session.to_json();
        // 先写临时文件再改名：写到一半崩掉不会留下一份「半个 JSON」。
        let temp = path.with_extension("json.tmp");
        std::fs::write(&temp, text.as_bytes()).map_err(|e| DbFailure {
            message: format!("写对话记录失败：{e}（{}）", temp.display()),
            hint: "确认该文件可写（可能被杀毒软件 / 权限限制）。".to_string(),
        })?;
        std::fs::rename(&temp, &path).map_err(|e| DbFailure {
            message: format!("落盘对话记录失败：{e}（{}）", path.display()),
            hint: "确认该文件可写（可能被杀毒软件 / 权限限制）。".to_string(),
        })?;
        self.write_active(workspace, &id);
        Ok(ChatSessionSaved {
            id,
            path: path.display().to_string(),
            messages: session.messages.len(),
            dropped: write.dropped,
            clipped: write.clipped,
            invalid: write.invalid,
            updated_secs: at_secs,
        })
    }

    /// **开一段新对话**：段号 = 现有最大 + 1，并落一份空会话（这样列表里立刻看得见它）。
    ///
    /// 当前段本来就是空对话 ⇒ **原样返回它**（连点两次「新建」不该造出两个空段）。
    pub fn new_session(
        &self,
        workspace: &str,
        at_secs: u64,
    ) -> Result<ChatSessionReport, DbFailure> {
        if !is_usable_workspace(workspace) {
            return Err(DbFailure {
                message: "没有打开工作区，新建的对话没处以落盘。".to_string(),
                hint: "先打开一个文件夹（Home「打开文件夹」），对话会按工作区各存一份。".to_string(),
            });
        }
        let entries = self.entries(workspace);
        let active = self.active_id(workspace, &entries);
        if let Some(current) = entries.iter().find(|entry| entry.id == active) {
            if current.problem.is_none() && current.messages == 0 {
                return Ok(self.load_id(workspace, &current.id));
            }
        }
        let ids: Vec<String> = entries.iter().map(|entry| entry.id.clone()).collect();
        let id = next_session_id(&ids);
        self.save_id(workspace, &id, &[], at_secs)?;
        Ok(self.load_id(workspace, &id))
    }
}

/// 这个工作区默认段的会话文件在不在（界面「已存 / 未存」的判据用；不读内容）。
pub fn session_file_exists(dir: &Path, workspace: &str) -> bool {
    dir.join(file_name_for_id(workspace, DEFAULT_ID)).exists()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("doyah-chat-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn turn(role: &str, content: &str) -> ChatMessage {
        ChatMessage {
            role: role.to_string(),
            content: content.to_string(),
        }
    }

    #[test]
    fn a_conversation_survives_a_restart_because_it_is_its_own_file() {
        let dir = temp_dir("restart");
        let store = ChatSessionStore::new(&dir);
        let messages = vec![
            turn("user", "这个库有哪些表"),
            turn("assistant", "orders / users / events"),
        ];
        let saved = store.save("D:/work/demo", &messages, 1_700_000_000).unwrap();
        assert_eq!(saved.messages, 2);
        assert_eq!(saved.dropped, 0);
        assert_eq!(saved.id, DEFAULT_ID, "老入口写的就是默认段");
        assert!(std::path::Path::new(&saved.path).exists());

        // 「重启」= 换一个 store 实例再读。
        let reopened = ChatSessionStore::new(&dir).load("D:/work/demo");
        assert_eq!(reopened.messages, messages, "重启后要原样读回来");
        assert_eq!(reopened.id, DEFAULT_ID);
        assert_eq!(reopened.questions, 1);
        assert!(reopened.notes.is_empty(), "{:?}", reopened.notes);
        assert!(reopened.path.ends_with(".json"));
    }

    #[test]
    fn two_workspaces_never_see_each_other_s_conversation() {
        let dir = temp_dir("isolate");
        let store = ChatSessionStore::new(&dir);
        store
            .save("D:/work/alpha", &[turn("user", "alpha 的表")], 1)
            .unwrap();
        store
            .save("D:/work/beta", &[turn("user", "beta 的表")], 2)
            .unwrap();
        assert_eq!(store.load("D:/work/alpha").messages[0].content, "alpha 的表");
        assert_eq!(store.load("D:/work/beta").messages[0].content, "beta 的表");
        // 列表也互不可见（另一工作区的文件不该出现在本工作区的列表里）。
        let alpha = store.list("D:/work/alpha");
        assert_eq!(alpha.entries.len(), 1);
        assert_eq!(alpha.entries[0].title, "alpha 的表");
        // 没存过的第三个工作区：空对话 + 没有异常话（第一次打开就该是这样）。
        let fresh = store.load("D:/work/gamma");
        assert!(fresh.messages.is_empty());
        assert!(fresh.notes.is_empty());
        assert!(fresh.path.ends_with(".json"), "路径仍要给出来");
        assert!(store.list("D:/work/gamma").entries.is_empty());
    }

    #[test]
    fn a_broken_file_reads_as_empty_and_is_left_untouched_until_the_next_save() {
        let dir = temp_dir("broken");
        let store = ChatSessionStore::new(&dir);
        let path = store.path_for("D:/work/demo");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, "{ 这不是 JSON").unwrap();

        let load = store.load("D:/work/demo");
        assert!(load.messages.is_empty());
        assert_eq!(load.notes.len(), 1);
        assert!(load.notes[0].contains("读不出来"), "{:?}", load.notes);
        // 读不许改写原文件（用户还有机会手工救回来）。
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "{ 这不是 JSON");

        // 下一次保存才覆盖。
        store.save("D:/work/demo", &[turn("user", "新的一段")], 3).unwrap();
        assert_eq!(store.load("D:/work/demo").messages[0].content, "新的一段");
    }

    #[test]
    fn saving_without_an_open_workspace_is_refused_with_a_readable_reason() {
        let dir = temp_dir("noworkspace");
        let store = ChatSessionStore::new(&dir);
        let failure = store.save("   ", &[turn("user", "x")], 1).unwrap_err();
        assert!(failure.message.contains("没有打开工作区"), "{}", failure.message);
        assert!(failure.hint.contains("打开一个文件夹"), "{}", failure.hint);
        // 读也一样：空工作区不产生文件、也不报错（界面据此说「这次不会存」）。
        let load = store.load("");
        assert!(load.messages.is_empty());
        assert!(load.path.is_empty());
        assert!(!session_file_exists(&dir, ""));
        // 新建也一样：没有工作区就没有「按工作区一段」可言。
        assert!(store.new_session("  ", 1).is_err());
        assert_eq!(store.list("").active, "");
    }

    #[test]
    fn a_second_conversation_starts_empty_and_the_first_one_stays_put() {
        let dir = temp_dir("segments");
        let store = ChatSessionStore::new(&dir);
        store
            .save_id("D:/work/demo", DEFAULT_ID, &[turn("user", "第一段的问题")], 10)
            .unwrap();

        let fresh = store.new_session("D:/work/demo", 20).unwrap();
        assert_eq!(fresh.id, "2", "已有第 1 段 ⇒ 新建的是第 2 段");
        assert!(fresh.messages.is_empty());
        assert!(fresh.path.ends_with("-2.json"), "{}", fresh.path);

        // 两段各写各的，互不影响。
        store
            .save_id("D:/work/demo", "2", &[turn("user", "第二段的问题")], 30)
            .unwrap();
        assert_eq!(store.load_id("D:/work/demo", "1").messages[0].content, "第一段的问题");
        assert_eq!(store.load_id("D:/work/demo", "2").messages[0].content, "第二段的问题");
        // 落盘哪段就是哪段：重开（换实例）读到的是第 2 段。
        let reopened = ChatSessionStore::new(&dir);
        let active = reopened.load("D:/work/demo");
        assert_eq!(active.id, "2");
        assert_eq!(active.messages[0].content, "第二段的问题");

        let list = reopened.list("D:/work/demo");
        assert_eq!(list.entries.len(), 2);
        assert_eq!(list.active, "2");
        assert_eq!(list.broken, 0);
        assert_eq!(list.entries[0].id, "2", "新的在前：第 2 段最后写入得最晚");
        assert_eq!(list.entries[0].title, "第二段的问题");
        assert_eq!(list.entries[1].title, "第一段的问题");
    }

    #[test]
    fn starting_a_new_conversation_twice_does_not_leave_two_empty_ones() {
        let dir = temp_dir("emptynew");
        let store = ChatSessionStore::new(&dir);
        let first = store.new_session("D:/work/demo", 10).unwrap();
        assert_eq!(first.id, "1", "一段都没有 ⇒ 从默认段开始");
        let again = store.new_session("D:/work/demo", 11).unwrap();
        assert_eq!(again.id, "1", "当前段本来就是空的 ⇒ 原样返回，不再造一段");
        assert_eq!(store.list("D:/work/demo").entries.len(), 1);

        // 有内容之后才真的开新段。
        store
            .save_id("D:/work/demo", "1", &[turn("user", "问了点什么")], 12)
            .unwrap();
        let next = store.new_session("D:/work/demo", 13).unwrap();
        assert_eq!(next.id, "2");
        assert_eq!(store.list("D:/work/demo").entries.len(), 2);
        // 老段原样还在（新建不该动它）。
        assert_eq!(store.load_id("D:/work/demo", "1").messages[0].content, "问了点什么");
    }

    #[test]
    fn a_broken_segment_is_counted_and_the_good_ones_still_list() {
        let dir = temp_dir("brokenlist");
        let store = ChatSessionStore::new(&dir);
        store
            .save_id("D:/work/demo", "1", &[turn("user", "好的一段")], 10)
            .unwrap();
        let broken = store.path_for_id("D:/work/demo", "2");
        std::fs::create_dir_all(broken.parent().unwrap()).unwrap();
        std::fs::write(&broken, "{ 半个 JSON").unwrap();

        let list = store.list("D:/work/demo");
        assert_eq!(list.entries.len(), 2, "坏的那段也要列出来（用户要知道它存在）");
        assert_eq!(list.broken, 1, "读不出来的要计数");
        let bad = list
            .entries
            .iter()
            .find(|entry| entry.id == "2")
            .expect("坏的那段在列表里");
        assert!(bad.problem.is_some(), "坏段要带原因");
        let good = list
            .entries
            .iter()
            .find(|entry| entry.id == "1")
            .expect("好的一段仍在列表里");
        assert!(good.problem.is_none());
        assert_eq!(good.title, "好的一段", "坏文件不该让好的那段也没有标题");
        // 当前段指针没被坏文件带跑。
        assert_eq!(list.active, "1");
    }

    #[test]
    fn a_pointer_to_a_missing_segment_falls_back_to_the_newest() {
        let dir = temp_dir("pointer");
        let store = ChatSessionStore::new(&dir);
        store
            .save_id("D:/work/demo", "1", &[turn("user", "老的那段")], 10)
            .unwrap();
        store
            .save_id("D:/work/demo", "2", &[turn("user", "新的那段")], 20)
            .unwrap();
        // 用户手工删了第 2 段（指针还指着它）⇒ 退回最新可用那段，不空着不说。
        std::fs::remove_file(store.path_for_id("D:/work/demo", "2")).unwrap();
        let load = store.load("D:/work/demo");
        assert_eq!(load.id, "1");
        assert_eq!(load.messages[0].content, "老的那段");
        // 指针文件里塞垃圾 ⇒ 同样退回最新那段，不当成段号。
        std::fs::write(store.active_path("D:/work/demo"), "../../evil").unwrap();
        assert_eq!(store.load("D:/work/demo").id, "1");
    }
}
