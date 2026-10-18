//! **对话会话的落盘面**（`FR-AI-17` · Windows 侧表示层）
//!
//! 分层与 `agent_settings.rs` / `saved_queries.rs` 一致：形状、归属校验、上限、坏文件兜底全在领域层
//! （`doyah_studio_db::agent_chat_session`），本模块只管「放哪儿、怎么取」。
//!
//! 为什么一个工作区一份文件（而不是全塞进 `agent-history.json`）：
//! ① 生成历史是「问过什么 SQL」的回看清单，一次外发一条；对话是**长文本、多轮、按项目分**的东西，
//!   两个工作区的对话混在一份文件里，模型下回就会看见别的项目的表名；
//! ② 一份对话文件坏掉，只该影响那一个工作区的回看 —— 不该把别的项目的对话一起拖下水。
//!
//! 落点：`%APPDATA%\DoyahStudio\chat\chat-<工作区哈希>.json`（文件名由领域层派生，见
//! `file_name_for`：路径里的 `..` / 分隔符进不了文件名）。

use std::path::{Path, PathBuf};

use doyah_studio_db::agent_chat_session::{
    bounded, file_name_for, is_usable_workspace, load_json, ChatSession,
};
use doyah_studio_db::agent_nl2sql::ChatMessage;
use serde::Serialize;

use crate::postgres::DbFailure;

/// 对话会话的存储（目录可由调用方指定 —— 单测与探针用它把文件挪到临时目录）。
pub struct ChatSessionStore {
    /// 会话文件所在目录（每个工作区一份文件）。
    pub dir: PathBuf,
}

/// 读回来的会话（给界面的一份完整交代：消息 + 路径 + 读的时候发生了什么）。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatSessionReport {
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

impl ChatSessionStore {
    /// 指定目录。
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        Self { dir: dir.into() }
    }

    /// 默认落点：`%APPDATA%\DoyahStudio\chat`（与配置 / 历史 / 审计同根目录、另一个子目录 ——
    /// 会话是长文本，单独一层便于用户整批备份或清掉）。
    /// 取不到 `APPDATA` 就退到当前目录 —— **不静默丢数据**，界面拿得到路径。
    pub fn default_store() -> Self {
        let base = match std::env::var("APPDATA") {
            Ok(value) if !value.trim().is_empty() => PathBuf::from(value),
            _ => PathBuf::from("."),
        };
        Self::new(base.join("DoyahStudio").join("chat"))
    }

    /// 某个工作区的会话文件路径（文件名由领域层派生 ⇒ 调用方给什么路径都安全）。
    pub fn path_for(&self, workspace: &str) -> PathBuf {
        self.dir.join(file_name_for(workspace))
    }

    /// 读这个工作区的对话。**文件不存在 = 第一次打开 = 空对话**（不是错误，也不写盘）；
    /// 文件坏了 / 属于别的工作区 ⇒ 空对话 + 说清（口径见领域层模块头）。
    ///
    /// 没打开工作区（空串）⇒ 空对话且 `path` 为空：没有「按工作区」可言，界面据此如实说「这次不会存」。
    pub fn load(&self, workspace: &str) -> ChatSessionReport {
        if !is_usable_workspace(workspace) {
            return ChatSessionReport {
                workspace: workspace.to_string(),
                path: String::new(),
                messages: Vec::new(),
                skipped: 0,
                clipped: 0,
                notes: Vec::new(),
                questions: 0,
            };
        }
        let path = self.path_for(workspace);
        let text = match std::fs::read_to_string(&path) {
            Ok(text) => text,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => String::new(),
            Err(err) => {
                // 读不出来（权限 / 编码）：当空对话，但**说清是哪个文件读不了** ——
                // 静默当空会让人以为「对话被吞了」。
                let load = load_json(workspace, "");
                let mut notes = load.notes;
                notes.push(format!(
                    "这份对话记录读不出来（{err}）：{}",
                    path.display()
                ));
                return ChatSessionReport {
                    workspace: workspace.to_string(),
                    path: path.display().to_string(),
                    messages: Vec::new(),
                    skipped: 0,
                    clipped: 0,
                    notes,
                    questions: 0,
                };
            }
        };
        let load = load_json(workspace, &text);
        ChatSessionReport {
            workspace: workspace.to_string(),
            path: path.display().to_string(),
            messages: load.session.messages.clone(),
            skipped: load.skipped,
            clipped: load.clipped,
            notes: load.notes,
            questions: load.session.questions(),
        }
    }

    /// 写这个工作区的对话（整份覆盖：会话文件就是唯一事实源，不做增量合并）。
    ///
    /// **写不进去要报错**：这一次对话没留下痕迹是用户该知道的事（关掉页签就真没了），
    /// 但**不阻断发送** —— 发送面在 `agent_generate`，那里已经发完了。
    pub fn save(
        &self,
        workspace: &str,
        messages: &[ChatMessage],
        at_secs: u64,
    ) -> Result<ChatSessionSaved, DbFailure> {
        if !is_usable_workspace(workspace) {
            return Err(DbFailure {
                message: "没有打开工作区，这次对话没处以落盘。".to_string(),
                hint: "先打开一个文件夹（Home「打开文件夹」），对话会按工作区各存一份。".to_string(),
            });
        }
        let path = self.path_for(workspace);
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
        Ok(ChatSessionSaved {
            path: path.display().to_string(),
            messages: session.messages.len(),
            dropped: write.dropped,
            clipped: write.clipped,
            invalid: write.invalid,
            updated_secs: at_secs,
        })
    }
}

/// 这个工作区的会话文件在不在（界面「已存 / 未存」的判据用；不读内容）。
pub fn session_file_exists(dir: &Path, workspace: &str) -> bool {
    dir.join(file_name_for(workspace)).exists()
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
        assert!(std::path::Path::new(&saved.path).exists());

        // 「重启」= 换一个 store 实例再读。
        let reopened = ChatSessionStore::new(&dir).load("D:/work/demo");
        assert_eq!(reopened.messages, messages, "重启后要原样读回来");
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
        // 没存过的第三个工作区：空对话 + 没有异常话（第一次打开就该是这样）。
        let fresh = store.load("D:/work/gamma");
        assert!(fresh.messages.is_empty());
        assert!(fresh.notes.is_empty());
        assert!(fresh.path.ends_with(".json"), "路径仍要给出来");
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
        assert_eq!(
            store.load("D:/work/demo").messages[0].content,
            "新的一段"
        );
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
    }
}
