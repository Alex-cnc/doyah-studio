//! **智能体设置的落盘面**（`FR-AI-01` · Windows 侧表示层）
//!
//! 分层与 `connections.rs` / `saved_queries.rs` 一致：
//! ① 配置模型、输入合法性、闸门裁决全在领域层（`doyah_studio_db::agent_config`），本文件只管
//!    「放哪儿、怎么取」；
//! ② **密钥与配置分两份文件**（`agent-key.bin` / `agent.json`）—— 需求原文「API Key 不落配置文件」，
//!    这条靠**两份文件**保证，而不是靠「记得别写进去」；
//! ③ 密钥密文用 **DPAPI** 加密（与当前 Windows 用户绑定：文件被拷到别的账户 / 机器上解不开）。
//!    加密是**失败即拒绝**：`CryptProtectData` 返回失败时**不落盘明文**，把可读原因交给界面。
//!
//! 为什么密钥不直接放进配置 JSON 里再加一层「加密字段」：那样一次重构 / 一次「导出配置」就会把它带出去。
//! 分成两个文件后，配置文件的序列化白名单（见领域层单测）永远看不到密钥。

use std::path::{Path, PathBuf};

use doyah_studio_db::agent_config::{evaluate, AgentConfiguration, AgentGateReport};
use doyah_studio_db::agent_audit::AuditLedger;
use doyah_studio_db::agent_history::HistoryLedger;
use doyah_studio_db::agent_quota::{now_secs, QuotaLedger, QuotaStatus};
use serde::Serialize;

use crate::postgres::DbFailure;

/// 配置与密钥的存储（两条路径都可由调用方指定 —— 单测与探针用它把文件挪到临时目录）。
///
/// `Clone`：异步命令要把存储挪进阻塞线程（流式对话不能堵住主线程），两个字段都是路径，复制没有副作用。
#[derive(Clone)]
pub struct AgentSettingsStore {
    /// 配置文件（`agent.json`）：**没有密钥字段**。
    pub config_path: PathBuf,
    /// 密钥文件（`agent-key.bin`）：DPAPI 密文，不是明文、也不是 base64 过的明文。
    pub key_path: PathBuf,
}

/// 界面上要的一份快照（配置 + 裁决 + 密钥在不在 + 两个路径）。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentSettingsSnapshot {
    /// 当前配置。
    pub config: AgentConfiguration,
    /// 闸门裁决（**唯一出处 = 领域层**；界面只显示，不自己算一遍）。
    pub gate: AgentGateReport,
    /// 密钥**在不在**（只给布尔，永不回显内容）。
    pub key_present: bool,
    /// 密钥存放方式（`dpapi` / `unavailable`）—— 界面照实写出，不假装安全。
    pub key_storage: String,
    /// 密钥存储的异常（读不出来 / 加密不可用），如实显示；正常时为 `null`。
    pub key_note: Option<String>,
    /// 配置文件路径（让用户知道去哪儿看）。
    pub config_path: String,
    /// 本小时的配额读数（**与生成面的拦面读同一本滑窗台账**；界面只显示，不自己算 ——
    /// 自己算就会出现「设置里说还剩 5 次、点生成却被拦住」这种最难查的分叉）。
    pub quota: QuotaStatus,
}

impl AgentSettingsStore {
    /// 指定两条路径。
    pub fn new(config_path: impl Into<PathBuf>, key_path: impl Into<PathBuf>) -> Self {
        Self {
            config_path: config_path.into(),
            key_path: key_path.into(),
        }
    }

    /// 默认落点：`%APPDATA%\DoyahStudio\{agent.json,agent-key.bin}`（与连接 / 已保存查询同目录）。
    /// 取不到 `APPDATA` 就退到当前目录 —— **不静默丢数据**，调用方看得到路径。
    pub fn default_store() -> Self {
        let base = match std::env::var("APPDATA") {
            Ok(value) if !value.trim().is_empty() => PathBuf::from(value),
            _ => PathBuf::from("."),
        };
        let dir = base.join("DoyahStudio");
        Self::new(dir.join("agent.json"), dir.join("agent-key.bin"))
    }

    /// 读配置。文件不存在 ⇒ 默认值（**默认 = 总开关关**，不是错误）；文件坏了 ⇒ 可读失败。
    pub fn load(&self) -> Result<AgentConfiguration, DbFailure> {
        if !self.config_path.exists() {
            return Ok(AgentConfiguration::default());
        }
        let text = std::fs::read_to_string(&self.config_path).map_err(|e| DbFailure {
            message: format!("读智能体配置失败：{e}（{}）", self.config_path.display()),
            hint: "确认该文件可读；若内容坏了，先备份再删掉它（只会清掉智能体的设置，不动数据库里的数据）。"
                .to_string(),
        })?;
        if text.trim().is_empty() {
            return Ok(AgentConfiguration::default());
        }
        serde_json::from_str(&text).map_err(|e| DbFailure {
            message: format!("智能体配置读不出来：{e}"),
            hint: "文件可能来自更新版本的客户端或已损坏；先备份再删掉它即可从默认设置重建。".to_string(),
        })
    }

    /// 写配置（整份覆盖：配置就是唯一事实源，不做增量合并）。
    pub fn save(&self, config: &AgentConfiguration) -> Result<(), DbFailure> {
        if let Some(parent) = self.config_path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| DbFailure {
                message: format!("建目录失败：{e}（{}）", parent.display()),
                hint: "确认该目录可写。".to_string(),
            })?;
        }
        let text = serde_json::to_string_pretty(config).map_err(|e| DbFailure {
            message: format!("智能体配置序列化失败：{e}"),
            hint: "这属实现缺陷：请保留现场并报告。".to_string(),
        })?;
        std::fs::write(&self.config_path, text).map_err(|e| DbFailure {
            message: format!("写智能体配置失败：{e}（{}）", self.config_path.display()),
            hint: "确认该文件可写（可能被杀毒软件 / 权限限制）。".to_string(),
        })
    }

    /// 配额台账的落点：与配置同目录的 `agent-quota.json`（**不是**配置文件的一部分 ——
    /// 配置由用户手填、台账由程序写，两份混在一起会让「导出配置」把计数带走，也会让手改配置的人
    /// 一不留神把台账写坏）。
    pub fn quota_path(&self) -> PathBuf {
        self.config_path.with_file_name("agent-quota.json")
    }

    /// 读配额台账。文件不存在 / 读不出来 / 内容是坏 JSON ⇒ **空账**（口径见 `Db::agent_quota` 模块头：
    /// 一本坏账不许把人锁死一小时）。这里**不报错**，因为配额读不出来不该让生成功能整个不可用。
    pub fn load_quota(&self) -> QuotaLedger {
        let path = self.quota_path();
        match std::fs::read_to_string(&path) {
            Ok(text) => QuotaLedger::from_json(&text),
            Err(_) => QuotaLedger::default(),
        }
    }

    /// 写配额台账。**写不进去要报错**（调用方据此拒绝发送）：静默失败的后果是「每小时上限」形同不存在。
    pub fn save_quota(&self, ledger: &QuotaLedger) -> Result<(), DbFailure> {
        let path = self.quota_path();
        if let Some(parent) = path.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent).map_err(|e| DbFailure {
                    message: format!("建配额台账目录失败：{e}（{}）", parent.display()),
                    hint: "确认该目录可写。".to_string(),
                })?;
            }
        }
        std::fs::write(&path, ledger.to_json()).map_err(|e| DbFailure {
            message: format!("写配额台账失败：{e}（{}）", path.display()),
            hint: "确认该文件可写（可能被杀毒软件 / 权限限制）。".to_string(),
        })
    }

    /// 历史台账的落点：与配置同目录的 `agent-history.json`（**与配额台账分两份**：
    /// 配额是「安全上限」的计数，坏了就得拒发；历史是「回看」的记录，坏了只是少看几条 ——
    /// 两者的失败语义完全不同，混成一个文件会让其中一条拖垮另一条）。
    pub fn history_path(&self) -> PathBuf {
        self.config_path.with_file_name("agent-history.json")
    }

    /// 读历史。文件不存在 / 读不出来 / 内容是坏 JSON ⇒ **空历史**（口径见 `Db::agent_history` 模块头）。
    pub fn load_history(&self) -> HistoryLedger {
        let path = self.history_path();
        match std::fs::read_to_string(&path) {
            Ok(text) => HistoryLedger::from_json(&text),
            Err(_) => HistoryLedger::default(),
        }
    }

    /// 写历史。**写不进去要报错**（调用方据此在结果里如实说「这次没能记进历史」），但**不阻断发送** ——
    /// 与配额台账相反：配额写不上是上限失效（安全问题），历史写不上只是少一条记录（体验问题）。
    pub fn save_history(&self, ledger: &HistoryLedger) -> Result<(), DbFailure> {
        let path = self.history_path();
        if let Some(parent) = path.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent).map_err(|e| DbFailure {
                    message: format!("建历史目录失败：{e}（{}）", parent.display()),
                    hint: "确认该目录可写。".to_string(),
                })?;
            }
        }
        std::fs::write(&path, ledger.to_json()).map_err(|e| DbFailure {
            message: format!("写生成历史失败：{e}（{}）", path.display()),
            hint: "确认该文件可写（可能被杀毒软件 / 权限限制）。".to_string(),
        })
    }

    /// 审计台账的落点：与配置同目录的 `agent-audit.json`（**第三份文件**，理由同历史：
    /// 配额是安全上限（坏了拒发）、历史是回看（坏了少看）、审计是「发过什么」的交代（坏了按空账，
    /// 但**写不进去要说**）—— 三种失败语义，三个文件）。
    pub fn audit_path(&self) -> PathBuf {
        self.config_path.with_file_name("agent-audit.json")
    }

    /// 读审计台账。文件不存在 / 读不出来 / 坏 JSON ⇒ **空账**（口径见 `Db::agent_audit` 模块头）。
    pub fn load_audit(&self) -> AuditLedger {
        let path = self.audit_path();
        match std::fs::read_to_string(&path) {
            Ok(text) => AuditLedger::from_json(&text),
            Err(_) => AuditLedger::default(),
        }
    }

    /// 写审计台账。**写不进去要报错**（调用方据此在结果里如实说「这一次没能记进审计记录」），
    /// 但**不阻断发送**：审计写不上是「事后说不清」，而拒发是「现在办不成事」—— 前者更该被说出来，
    /// 后者不该被它连坐。
    pub fn save_audit(&self, ledger: &AuditLedger) -> Result<(), DbFailure> {
        let path = self.audit_path();
        if let Some(parent) = path.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent).map_err(|e| DbFailure {
                    message: format!("建审计目录失败：{e}（{}）", parent.display()),
                    hint: "确认该目录可写。".to_string(),
                })?;
            }
        }
        std::fs::write(&path, ledger.to_json()).map_err(|e| DbFailure {
            message: format!("写审计记录失败：{e}（{}）", path.display()),
            hint: "确认该文件可写（可能被杀毒软件 / 权限限制）。".to_string(),
        })
    }

    /// 把一份导出文本落到**审计文件同目录**（`FR-AI-24` ③）。
    ///
    /// 文件名 = `agent-audit-export-<epoch>.<ext>`；同一秒里连点两次不覆盖（补 `-2` / `-3`）——
    /// 导出是给用户带走的，静默覆盖上一次就等于弄丢他刚导的那份。
    pub fn save_audit_export(&self, extension: &str, text: &str) -> Result<PathBuf, DbFailure> {
        let dir = self
            .audit_path()
            .parent()
            .map(Path::to_path_buf)
            .unwrap_or_default();
        if !dir.as_os_str().is_empty() {
            std::fs::create_dir_all(&dir).map_err(|e| DbFailure {
                message: format!("建导出目录失败：{e}（{}）", dir.display()),
                hint: "确认该目录可写。".to_string(),
            })?;
        }
        let secs = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|elapsed| elapsed.as_secs())
            .unwrap_or(0);
        let mut path = dir.join(format!("agent-audit-export-{secs}.{extension}"));
        let mut attempt = 2;
        while path.exists() {
            path = dir.join(format!("agent-audit-export-{secs}-{attempt}.{extension}"));
            attempt += 1;
        }
        std::fs::write(&path, text).map_err(|e| DbFailure {
            message: format!("写导出文件失败：{e}（{}）", path.display()),
            hint: "确认该目录可写（可能被杀毒软件 / 权限限制）。".to_string(),
        })?;
        Ok(path)
    }

    /// 密钥在不在（只回答布尔；读不出来按「不在」处理，并把原因带给界面）。
    pub fn key_present(&self) -> bool {
        self.key_blob().is_some()
    }

    /// 密钥存储出问题时的可读原因（正常 = `None`）。
    pub fn key_note(&self) -> Option<String> {
        if !self.key_path.exists() {
            return None;
        }
        match self.key_blob() {
            Some(_) => None,
            None => Some(format!(
                "密钥文件读不出来（{}）：可能是别的 Windows 用户写的，或文件已损坏。请重新填写一次密钥。",
                self.key_path.display()
            )),
        }
    }

    /// 存密钥（DPAPI 加密后落盘；**空串 / 全空白直接拒绝**，不让「清空输入框再点保存」变成一次无意义的写）。
    pub fn save_key(&self, secret: &str) -> Result<(), DbFailure> {
        let trimmed = secret.trim();
        if trimmed.is_empty() {
            return Err(DbFailure {
                message: "密钥是空的，没有保存。".to_string(),
                hint: "要么填一个密钥，要么用「清除密钥」把已存的删掉。".to_string(),
            });
        }
        let blob = dpapi::protect(trimmed.as_bytes()).map_err(|reason| DbFailure {
            message: format!("密钥加密失败，未保存：{reason}"),
            hint: "这是本机的凭据加密不可用。密钥没有落盘（不会退化成明文保存）。".to_string(),
        })?;
        if let Some(parent) = self.key_path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| DbFailure {
                message: format!("建目录失败：{e}（{}）", parent.display()),
                hint: "确认该目录可写。".to_string(),
            })?;
        }
        std::fs::write(&self.key_path, blob).map_err(|e| DbFailure {
            message: format!("写密钥失败：{e}（{}）", self.key_path.display()),
            hint: "确认该文件可写（可能被杀毒软件 / 权限限制）。".to_string(),
        })
    }

    /// 取回密钥明文（**只给真正要发请求的那一层用**；界面永远不拿它）。
    pub fn key_secret(&self) -> Option<String> {
        let blob = self.key_blob()?;
        let plain = dpapi::unprotect(&blob).ok()?;
        String::from_utf8(plain).ok()
    }

    /// 清除密钥（文件不存在也算成功 —— 「已经不在了」与「刚删掉」对用户是同一件事）。
    pub fn clear_key(&self) -> Result<(), DbFailure> {
        if !self.key_path.exists() {
            return Ok(());
        }
        std::fs::remove_file(&self.key_path).map_err(|e| DbFailure {
            message: format!("删除密钥文件失败：{e}（{}）", self.key_path.display()),
            hint: "确认该文件可删（可能被杀毒软件占用）。".to_string(),
        })
    }

    /// 当前快照（配置 + 裁决 + 密钥状态 + 本小时配额读数）。
    pub fn snapshot(&self) -> Result<AgentSettingsSnapshot, DbFailure> {
        let config = self.load()?;
        let key_present = self.key_present();
        // 配额读数与 `agent_generate` 的拦面同源（同一本账 + 同一处算）：上限用**盘上那份配置**的
        // `hourly_limit`（不是界面草稿里的值 —— 没保存的上限不该让读数看起来已经生效）。
        let quota = self.load_quota().status(now_secs(), config.hourly_limit);
        Ok(AgentSettingsSnapshot {
            gate: evaluate(&config, key_present),
            config,
            key_present,
            key_storage: dpapi::STORAGE.to_string(),
            key_note: self.key_note(),
            config_path: self.config_path.display().to_string(),
            quota,
        })
    }

    fn key_blob(&self) -> Option<Vec<u8>> {
        if !self.key_path.exists() {
            return None;
        }
        let blob = std::fs::read(&self.key_path).ok()?;
        if blob.is_empty() {
            return None;
        }
        // 能解开才算真的在（坏文件不冒充「已配置」—— 否则用户会以为密钥还好着）。
        dpapi::unprotect(&blob).ok().map(|_| blob)
    }
}

// ── DPAPI（Windows 凭据加密）────────────────────────────────────────────────────

#[cfg(windows)]
mod dpapi {
    use windows_sys::Win32::Foundation::LocalFree;
    use windows_sys::Win32::Security::Cryptography::{
        CryptProtectData, CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
    };

    /// 存放方式（界面照实写出）。
    pub const STORAGE: &str = "dpapi";

    fn entropy() -> Vec<u8> {
        // 固定的应用级熵：不是机密（算法公开），作用是把本应用的密文与同账户下别的程序的密文区分开。
        b"DoyahStudio/agent-key/v1".to_vec()
    }

    fn blob_of(bytes: &mut [u8]) -> CRYPT_INTEGER_BLOB {
        CRYPT_INTEGER_BLOB {
            cbData: bytes.len() as u32,
            pbData: bytes.as_mut_ptr(),
        }
    }

    /// 加密（失败 ⇒ `Err(可读原因)`；**绝不返回明文当「降级」**）。
    pub fn protect(plain: &[u8]) -> Result<Vec<u8>, String> {
        if plain.is_empty() {
            return Err("要加密的内容是空的".to_string());
        }
        let mut input = plain.to_vec();
        let mut entropy = entropy();
        let mut input_blob = blob_of(&mut input);
        let mut entropy_blob = blob_of(&mut entropy);
        let mut out = CRYPT_INTEGER_BLOB {
            cbData: 0,
            pbData: std::ptr::null_mut(),
        };
        // SAFETY：两个输入 blob 指向本函数内有效的 Vec，`out` 由系统分配、下面用 LocalFree 归还。
        let ok = unsafe {
            CryptProtectData(
                &mut input_blob,
                std::ptr::null(),
                &mut entropy_blob,
                std::ptr::null(),
                std::ptr::null(),
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut out,
            )
        };
        if ok == 0 {
            return Err(format!("CryptProtectData 失败（GetLastError={}）", unsafe {
                windows_sys::Win32::Foundation::GetLastError()
            }));
        }
        // SAFETY：`out` 由系统分配、长度由系统填写；拷出后立刻归还。
        let bytes = unsafe { std::slice::from_raw_parts(out.pbData, out.cbData as usize).to_vec() };
        unsafe {
            LocalFree(out.pbData as *mut core::ffi::c_void);
        }
        Ok(bytes)
    }

    /// 解密（失败 ⇒ `Err(可读原因)`：换用户 / 换机器 / 文件坏了都会走到这里）。
    pub fn unprotect(blob: &[u8]) -> Result<Vec<u8>, String> {
        if blob.is_empty() {
            return Err("密文是空的".to_string());
        }
        let mut input = blob.to_vec();
        let mut entropy = entropy();
        let mut input_blob = blob_of(&mut input);
        let mut entropy_blob = blob_of(&mut entropy);
        let mut out = CRYPT_INTEGER_BLOB {
            cbData: 0,
            pbData: std::ptr::null_mut(),
        };
        // SAFETY：同 `protect`；描述串传 null（不落额外元数据）。
        let ok = unsafe {
            CryptUnprotectData(
                &mut input_blob,
                std::ptr::null_mut(),
                &mut entropy_blob,
                std::ptr::null(),
                std::ptr::null(),
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut out,
            )
        };
        if ok == 0 {
            return Err("CryptUnprotectData 失败（换 Windows 用户或换机器都会解不开）".to_string());
        }
        // SAFETY：同 `protect`。
        let bytes = unsafe { std::slice::from_raw_parts(out.pbData, out.cbData as usize).to_vec() };
        unsafe {
            LocalFree(out.pbData as *mut core::ffi::c_void);
        }
        Ok(bytes)
    }
}

#[cfg(not(windows))]
mod dpapi {
    /// 存放方式：**本机没有系统凭据加密** —— 界面照实写出，不假装。
    pub const STORAGE: &str = "unavailable";

    pub fn protect(_plain: &[u8]) -> Result<Vec<u8>, String> {
        Err("本机没有可用的系统凭据加密（本片只支持 Windows 的 DPAPI）".to_string())
    }

    pub fn unprotect(_blob: &[u8]) -> Result<Vec<u8>, String> {
        Err("本机没有可用的系统凭据加密（本片只支持 Windows 的 DPAPI）".to_string())
    }
}

/// 配置文件的父目录（探针 / 单测打印用）。
pub fn store_directory(path: &Path) -> Option<&Path> {
    path.parent()
}

#[cfg(test)]
mod tests {
    use super::*;
    use doyah_studio_db::agent_config::GateState;

    // 夹具根：与 `connections.rs` / `saved_queries.rs` 同一处（系统临时区在本机沙箱里拒写）。
    fn fixture_root() -> PathBuf {
        match std::env::var("DOYAH_TEST_ROOT") {
            Ok(value) if !value.trim().is_empty() => PathBuf::from(value),
            _ => PathBuf::from("D:/AIProjects/_tmp_face2/fish-fixtures"),
        }
    }

    fn tmp_store(tag: &str) -> AgentSettingsStore {
        let dir = fixture_root().join(format!("doyah-agent-{tag}-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let store = AgentSettingsStore::new(dir.join("agent.json"), dir.join("agent-key.bin"));
        let _ = std::fs::remove_file(&store.config_path);
        let _ = std::fs::remove_file(&store.key_path);
        // 两份台账也要清：同一 tag 的目录若留着上一轮的账，会读成「已用过 / 已有历史」。
        let _ = std::fs::remove_file(store.quota_path());
        let _ = std::fs::remove_file(store.history_path());
        store
    }

    #[test]
    fn a_missing_file_is_the_default_config_and_the_switch_is_off() {
        let store = tmp_store("missing");
        let config = store.load().unwrap();
        assert_eq!(config, AgentConfiguration::default());
        assert!(!config.enabled);
        let snapshot = store.snapshot().unwrap();
        assert_eq!(snapshot.gate.state, GateState::Disabled);
        assert!(!snapshot.key_present);
    }

    #[test]
    fn a_broken_file_fails_with_a_readable_reason() {
        let store = tmp_store("broken");
        std::fs::write(&store.config_path, "{ 这不是 JSON").unwrap();
        let err = store.load().unwrap_err();
        assert!(err.message.contains("读不出来"), "{}", err.message);
        assert!(!err.hint.is_empty());
    }

    #[test]
    fn settings_round_trip_through_the_file() {
        let store = tmp_store("round-trip");
        let config = AgentConfiguration {
            enabled: true,
            endpoint: "http://localhost:11434/v1".to_string(),
            model: "llama3".to_string(),
            preset: "ollama".to_string(),
            ..Default::default()
        };
        store.save(&config).unwrap();
        assert_eq!(store.load().unwrap(), config);
        // 本地端点免密钥 ⇒ 已经放行；用户看得到的就是这个判定。
        assert_eq!(store.snapshot().unwrap().gate.state, GateState::Ready);
    }

    #[test]
    fn the_key_never_reaches_the_configuration_file() {
        let store = tmp_store("key-split");
        let secret = "sk-round14-do-not-leak";
        store.save_key(secret).unwrap();
        store.save(&AgentConfiguration::default()).unwrap();
        let config_text = std::fs::read_to_string(&store.config_path).unwrap();
        assert!(!config_text.contains(secret), "密钥不能进配置文件");
        assert!(!config_text.to_ascii_lowercase().contains("key\""), "配置里不该有密钥键");
        // 密钥文件里也不该有明文（DPAPI 密文）。
        let blob = std::fs::read(&store.key_path).unwrap();
        assert!(!blob.is_empty());
        let as_text = String::from_utf8_lossy(&blob);
        assert!(!as_text.contains(secret), "密钥文件里出现了明文");
    }

    #[cfg(windows)]
    #[test]
    fn a_saved_key_can_be_read_back_for_the_request_layer_only() {
        let store = tmp_store("key-roundtrip");
        store.save_key("sk-round14-abc").unwrap();
        assert!(store.key_present());
        assert_eq!(store.key_secret().as_deref(), Some("sk-round14-abc"));
        assert!(store.key_note().is_none());
    }

    #[cfg(windows)]
    #[test]
    fn a_corrupt_key_file_is_reported_as_not_configured_instead_of_pretending() {
        let store = tmp_store("key-corrupt");
        std::fs::write(&store.key_path, b"\x00\x01\x02 not dpapi").unwrap();
        assert!(!store.key_present());
        let note = store.key_note().expect("要说清为什么读不出来");
        assert!(note.contains("读不出来"), "{note}");
    }

    #[test]
    fn an_empty_key_is_refused_rather_than_written() {
        let store = tmp_store("key-empty");
        let err = store.save_key("   ").unwrap_err();
        assert!(err.message.contains("空的"), "{}", err.message);
        assert!(!store.key_path.exists());
    }

    #[test]
    fn clearing_a_key_twice_is_still_success() {
        let store = tmp_store("key-clear");
        store.save_key("sk-round14-clear").unwrap();
        store.clear_key().unwrap();
        store.clear_key().unwrap();
        assert!(!store.key_present());
    }

    #[test]
    fn a_history_entry_survives_a_restart_because_it_is_its_own_file() {
        use doyah_studio_db::agent_history::HistoryEntry;
        let store = tmp_store("history-roundtrip");
        assert!(store.load_history().is_empty(), "干净目录里不该有历史");
        let mut ledger = store.load_history();
        ledger.append(HistoryEntry::record(
            "每天的订单数",
            "SELECT count(*) FROM public.orders;",
            "",
            vec!["public.orders".to_string()],
            "m",
            1_700_000_000,
        ));
        store.save_history(&ledger).unwrap();
        // 换一份同路径的 store 读（模拟重启：只靠盘上的文件）。
        let reopened = AgentSettingsStore::new(&store.config_path, &store.key_path);
        let back = reopened.load_history();
        assert_eq!(back.len(), 1);
        assert_eq!(back.recent(1)[0].question, "每天的订单数");
        // 两份台账互不覆盖：写历史不该动配额那本，反之亦然。
        assert!(reopened.load_quota().sent_at.is_empty());
    }

    #[test]
    fn a_broken_history_file_reads_as_empty_instead_of_blocking_the_feature() {
        let store = tmp_store("history-broken");
        std::fs::write(store.history_path(), "{ 这不是 JSON").unwrap();
        assert!(store.load_history().is_empty());
    }

    #[test]
    fn the_settings_snapshot_carries_this_hour_s_quota_reading() {
        let store = tmp_store("quota-reading");
        store
            .save(&AgentConfiguration {
                hourly_limit: 5,
                ..Default::default()
            })
            .unwrap();
        let now = now_secs();
        let mut ledger = store.load_quota();
        assert!(ledger.admit(now, 5).0);
        assert!(ledger.admit(now, 5).0);
        store.save_quota(&ledger).unwrap();

        let snapshot = store.snapshot().unwrap();
        assert_eq!(snapshot.quota.limit, 5, "上限要取盘上那份配置");
        assert_eq!(snapshot.quota.used, 2);
        assert_eq!(snapshot.quota.remaining, 3);
        assert_eq!(snapshot.quota.retry_after_secs, 0, "没满却说要等");
    }

    #[test]
    fn a_full_window_reads_as_full_with_a_wait_instead_of_a_silent_zero() {
        let store = tmp_store("quota-full");
        store
            .save(&AgentConfiguration {
                hourly_limit: 1,
                ..Default::default()
            })
            .unwrap();
        let mut ledger = store.load_quota();
        assert!(ledger.admit(now_secs(), 1).0);
        store.save_quota(&ledger).unwrap();

        let snapshot = store.snapshot().unwrap();
        assert_eq!(snapshot.quota.used, 1);
        assert_eq!(snapshot.quota.remaining, 0);
        assert!(
            snapshot.quota.retry_after_secs > 0,
            "满额了却说不用等：{:?}",
            snapshot.quota
        );
    }
}
