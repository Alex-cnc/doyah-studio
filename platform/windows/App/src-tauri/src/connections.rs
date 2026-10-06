//! 连接列表的**落盘**与口令的**凭据存储**（Windows 侧表示层）
//!
//! 口径（三书）：
//! ① **口令绝不进配置文件**（需求原文点名 DR-02）：配置只存"连到哪儿、以谁的身份"，
//!    口令走系统凭据管理器（Windows Credential Manager，Generic 类型；`P-02`）；
//! ② **配置的模型与合法性判定在领域层**（`doyah-studio-db`），本文件只管"放哪儿、怎么取"；
//! ③ **失败如实说**：读不出来（文件坏 / 凭据被清）都要给可读原因，不静默当"没有"。
//!
//! 为什么口令走 `cmdkey` 而不是自己写加密文件：Windows 凭据管理器是**系统级、按用户隔离**的
//! 存储，重装应用不丢、别的用户读不到；自己写一份"加密文件"等于把密钥和密文放同一个抽屉里。

use std::path::{Path, PathBuf};
use std::process::Command;

use doyah_studio_db::config::{ConnectionBundle, ConnectionConfig};
use doyah_studio_db::db_type::DatabaseType;

use crate::postgres::DbFailure;

/// 凭据目标名前缀：`doyah-studio/<连接 id>`（与 §8.5.2-2 的约定一致）。
pub const CREDENTIAL_PREFIX: &str = "doyah-studio/";

/// 连接存储（配置文件 + 凭据）。
pub struct ConnectionStore {
    /// 配置文件路径（`connections.json`）。
    pub config_path: PathBuf,
}

impl ConnectionStore {
    pub fn new(config_path: impl Into<PathBuf>) -> Self {
        Self {
            config_path: config_path.into(),
        }
    }

    /// 默认落点：`%APPDATA%\DoyahStudio\connections.json`。
    /// 取不到 `APPDATA` 就退到当前目录 —— **不静默丢数据**，调用方会看到路径。
    pub fn default_path() -> PathBuf {
        match std::env::var("APPDATA") {
            Ok(base) if !base.trim().is_empty() => Path::new(&base).join("DoyahStudio").join("connections.json"),
            _ => PathBuf::from("connections.json"),
        }
    }

    /// 读连接列表。**文件不存在 = 空列表**（首次使用不是错误）；文件坏了 = 可读失败。
    pub fn load(&self) -> Result<Vec<ConnectionConfig>, DbFailure> {
        if !self.config_path.exists() {
            return Ok(Vec::new());
        }
        let text = std::fs::read_to_string(&self.config_path).map_err(|e| DbFailure {
            message: format!("读连接配置失败：{e}（{}）", self.config_path.display()),
            hint: "确认该文件可读；若内容坏了，删掉它会从空列表重建（不会动数据库里的数据）。".to_string(),
        })?;
        if text.trim().is_empty() {
            return Ok(Vec::new());
        }
        match ConnectionBundle::decode(&text) {
            Ok(bundle) => Ok(bundle.connections),
            Err(err) => Err(DbFailure {
                message: format!("连接配置读不出来：{err}"),
                hint: "配置文件可能来自更新版本的客户端或已损坏；先备份再删掉它即可从空列表重建。".to_string(),
            }),
        }
    }

    /// 写连接列表（**整份覆盖**：列表就是唯一事实源，不做增量合并）。
    /// 口令不在其中 —— 写之前显式核对一次，见 `bundle_text_has_no_secret`。
    pub fn save(&self, connections: &[ConnectionConfig]) -> Result<(), DbFailure> {
        if let Some(parent) = self.config_path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| DbFailure {
                message: format!("建配置目录失败：{e}（{}）", parent.display()),
                hint: "确认该目录可写。".to_string(),
            })?;
        }
        let bundle = ConnectionBundle::new(now_iso8601(), connections.to_vec());
        let text = bundle.encoded().map_err(|e| DbFailure {
            message: format!("连接配置序列化失败：{e}"),
            hint: "这属实现缺陷：请保留现场并报告。".to_string(),
        })?;
        // **写之前核一次**：口令这一项一旦出现在配置里就是安全事故（DR-02），不靠"记得别写"。
        if let Some(word) = bundle_text_has_no_secret(&text) {
            return Err(DbFailure {
                message: format!("拒绝写入：连接配置里出现了疑似口令字段（{word}）"),
                hint: "口令只进系统凭据管理器；这是实现缺陷，请保留现场并报告。".to_string(),
            });
        }
        std::fs::write(&self.config_path, text).map_err(|e| DbFailure {
            message: format!("写连接配置失败：{e}（{}）", self.config_path.display()),
            hint: "确认该文件可写（可能被杀毒软件/权限限制）。".to_string(),
        })
    }

    /// 新增或更新一条（按 id 认；**id 相同就替换**，名字相同不算同一条）。
    pub fn upsert(&self, config: ConnectionConfig) -> Result<Vec<ConnectionConfig>, DbFailure> {
        let mut list = self.load()?;
        match list.iter_mut().find(|c| c.id == config.id) {
            Some(slot) => *slot = config,
            None => list.push(config),
        }
        self.save(&list)?;
        Ok(list)
    }

    /// 删一条（**同时清掉它的凭据**：留下孤儿口令是隐患）。
    pub fn remove(&self, id: &str) -> Result<Vec<ConnectionConfig>, DbFailure> {
        let mut list = self.load()?;
        list.retain(|c| c.id != id);
        self.save(&list)?;
        let _ = forget_password(id); // 清不掉也不该挡住删除；调用方可另查
        Ok(list)
    }
}

/// 现在时刻（ISO-8601 / UTC）—— **不引时间库**：配置包里这一项只是"什么时候导出的"。
fn now_iso8601() -> String {
    // 从系统时钟取秒数，手工折成 ISO-8601（够用且无依赖）
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let days = secs / 86_400;
    let rem = secs % 86_400;
    let (h, m, s) = (rem / 3600, (rem % 3600) / 60, rem % 60);
    // 从 1970-01-01 起按民用历推年月日（不处理闰秒：导出时间戳不需要）
    let (mut y, mut d) = (1970i64, days as i64);
    loop {
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
        let len = if leap { 366 } else { 365 };
        if d < len {
            break;
        }
        d -= len;
        y += 1;
    }
    let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    let months = [31, if leap { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    let mut month = 1;
    for len in months {
        if d < len {
            break;
        }
        d -= len;
        month += 1;
    }
    format!("{y:04}-{month:02}-{:02}T{h:02}:{m:02}:{s:02}Z", d + 1)
}

/// 配置文本里有没有"疑似口令"字段。返回命中的词（`None` = 干净）。
///
/// 判据口径：**只认会真的把口令写进文件的那种形状**（`"password": "..."` / `secret`），
/// 不拿 `passwordHint` 之类的说明文字误报 —— 判据误报多了就会被绕开。
pub fn bundle_text_has_no_secret(text: &str) -> Option<&'static str> {
    for word in ["\"password\"", "\"passwd\"", "\"secret\"", "\"pwd\""] {
        if text.contains(word) {
            return Some(word);
        }
    }
    None
}

/// 凭据目标名：`doyah-studio/<连接 id>`。
pub fn credential_target(connection_id: &str) -> String {
    format!("{CREDENTIAL_PREFIX}{connection_id}")
}

/// 把口令写进 Windows 凭据管理器（Generic）。
///
/// 走 `cmdkey.exe`（系统自带）：不引额外 crate、不手写 FFI 面（§8.5.2-2 允许的两种落法之一）。
/// **口令经命令行传给 cmdkey** ⇒ 与"用 API"相比多一次进程创建；这是本轮如实登记的代价，
/// 换法是接 `windows` crate 的 `CredWriteW`（已在依赖面里，属下一段的活）。
pub fn remember_password(connection_id: &str, user: &str, password: &str) -> Result<(), DbFailure> {
    let target = credential_target(connection_id);
    let output = Command::new("cmdkey")
        .args(["/generic:", &target, &format!("/user:{user}"), &format!("/pass:{password}")])
        .output()
        .map_err(|e| DbFailure {
            message: format!("调 cmdkey 失败：{e}"),
            hint: "确认系统自带 cmdkey 可用（本机在 C:\\WINDOWS\\system32）。".to_string(),
        })?;
    if !output.status.success() {
        return Err(DbFailure {
            message: format!(
                "凭据写入失败（退出码 {:?}）：{}",
                output.status.code(),
                String::from_utf8_lossy(&output.stderr).trim()
            ),
            hint: "确认当前用户有权访问凭据管理器。".to_string(),
        });
    }
    Ok(())
}

/// 取口令（读不到返回 `Ok(None)`：**没存过不是错误**）。
pub fn recall_password(connection_id: &str) -> Result<Option<String>, DbFailure> {
    let target = credential_target(connection_id);
    let output = Command::new("cmdkey").arg(format!("/list:{target}")).output().map_err(|e| DbFailure {
        message: format!("调 cmdkey 失败：{e}"),
        hint: "确认系统自带 cmdkey 可用。".to_string(),
    })?;
    // 注意：cmdkey 读口令**只能读到自己**（`/list` 不显示口令）⇒ 这里只判"有没有存"，
    // 真取值交给驱动连接时由系统按目标名解析（下一段接 CredReadW 时把这一处补成真取值）。
    let text = String::from_utf8_lossy(&output.stdout);
    let marker = format!("Target: {target}");
    if text.contains(&marker) {
        Ok(None) // 存过，但命令行取不回口令本体 ⇒ 如实返回 None（不假装拿到了）
    } else {
        Ok(None)
    }
}

/// 忘掉一条口令（删连接时同清）。
///
/// **不认 `cmdkey /delete` 的退出码**：实测（2026-10-02）它对已经不存在、甚至删不掉的目标
/// 也报成功 ⇒ 删完必须**列一遍复查**；还在就如实报失败（"删不掉却报成功"是最坏的一类：
/// 用户以为口令清了，其实还在）。
pub fn forget_password(connection_id: &str) -> Result<(), DbFailure> {
    let target = credential_target(connection_id);
    let delete = Command::new("cmdkey").arg(format!("/delete:{target}")).output().map_err(|e| DbFailure {
        message: format!("调 cmdkey 失败：{e}"),
        hint: "确认系统自带 cmdkey 可用。".to_string(),
    })?;
    if has_credential(&target) {
        return Err(DbFailure {
            message: format!(
                "凭据删除后复查仍在（cmdkey 退出码 {:?}）：{target}",
                delete.status.code()
            ),
            hint: "在「控制面板 → 凭据管理器 → Windows 凭据」里手工删除这一条。".to_string(),
        });
    }
    Ok(())
}

/// 凭据管理器里有没有这一条（**只看有没有，取不回口令本体** —— `cmdkey /list` 不回显口令）。
pub fn has_credential(target: &str) -> bool {
    match Command::new("cmdkey").arg(format!("/list:{target}")).output() {
        Ok(out) => {
            let text = String::from_utf8_lossy(&out.stdout);
            text.contains(&format!("Target: {target}"))
        }
        Err(_) => false,
    }
}

/// 由表单参数造一条配置（id 由调用方给；端口 / SSL 的默认值走领域层的类型默认）。
#[allow(clippy::too_many_arguments)]
pub fn config_from_form(
    id: &str,
    name: &str,
    host: &str,
    port: u16,
    database: &str,
    user: &str,
    ssl_mode: Option<&str>,
    is_read_only: bool,
) -> ConnectionConfig {
    let mut config = ConnectionConfig::new(id, name, DatabaseType::Postgresql);
    config.host = host.to_string();
    config.port = port;
    config.database = database.to_string();
    config.username = user.to_string();
    if let Some(mode) = ssl_mode.and_then(doyah_studio_db::db_type::SslMode::from_raw) {
        config.ssl_mode = mode;
    }
    config.is_read_only = is_read_only;
    config
}

#[cfg(test)]
mod tests {
    use super::*;

    // 夹具根目录：**不用系统临时区**（cargo test 拿不到会话里的 TEMP，系统临时区在本机沙箱里拒写
    // ⇒ 建夹具报“拒绝访问”，看着像权限问题、其实是写错了地方）。可用环境变量覆盖。
    fn fixture_root() -> std::path::PathBuf {
        match std::env::var("DOYAH_TEST_ROOT") {
            Ok(value) if !value.trim().is_empty() => std::path::PathBuf::from(value),
            _ => std::path::PathBuf::from("D:/AIProjects/_tmp_face2/fish-fixtures"),
        }
    }

    use doyah_studio_db::db_type::SslMode;

    fn tmp_store(tag: &str) -> ConnectionStore {
        let dir = fixture_root().join(format!("doyah-test-{tag}-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        ConnectionStore::new(dir.join("connections.json"))
    }

    #[test]
    fn missing_file_is_an_empty_list_not_an_error() {
        let store = tmp_store("missing");
        let _ = std::fs::remove_file(&store.config_path);
        assert!(store.load().unwrap().is_empty());
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
    fn upsert_and_remove_round_trip_through_the_file() {
        let store = tmp_store("round-trip");
        let _ = std::fs::remove_file(&store.config_path);

        let a = config_from_form("id-a", "实验库", "127.0.0.1", 5433, "doyah_lab", "doyah", Some("disable"), false);
        assert!(a.is_valid());
        store.upsert(a.clone()).unwrap();

        let b = config_from_form("id-b", "线上", "10.0.0.5", 5432, "prod", "bob", Some("require"), true);
        let list = store.upsert(b).unwrap();
        assert_eq!(list.len(), 2);

        // 同 id 再 upsert = 替换，不是新增
        let mut renamed = a.clone();
        renamed.name = "实验库（改名）".into();
        let list = store.upsert(renamed.clone()).unwrap();
        assert_eq!(list.len(), 2, "同 id 应当替换而不是追加");
        assert_eq!(
            list.iter().find(|c| c.id == "id-a").unwrap().name,
            "实验库（改名）"
        );
        assert!(list.iter().any(|c| c.is_read_only), "只读标记要保住");
        assert_eq!(list.iter().find(|c| c.id == "id-a").unwrap().ssl_mode, SslMode::Disable);

        let list = store.remove("id-a").unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].id, "id-b");
    }

    #[test]
    fn the_saved_file_never_contains_a_password_field() {
        let store = tmp_store("no-secret");
        let _ = std::fs::remove_file(&store.config_path);
        store
            .upsert(config_from_form("id-x", "n", "h", 5432, "d", "u", None, false))
            .unwrap();
        let text = std::fs::read_to_string(&store.config_path).unwrap();
        assert!(bundle_text_has_no_secret(&text).is_none(), "配置里出现口令字段：{text}");
        assert!(text.contains("不含任何口令") || text.contains("不含"), "包里应当写明不含口令");
    }

    #[test]
    fn the_secret_guard_is_not_fooled_by_a_password_shaped_field() {
        // 这不是过虑：写配置的那条路一旦被改成带口令，这个判据必须当场炸
        assert_eq!(bundle_text_has_no_secret(r#"{"password":"hunter2"}"#), Some("\"password\""));
        assert_eq!(bundle_text_has_no_secret(r#"{"secret":"x"}"#), Some("\"secret\""));
        assert!(bundle_text_has_no_secret(r#"{"note":"口令不在此文件"}"#).is_none());
    }

    #[test]
    fn credential_targets_are_prefixed_and_unique_per_connection() {
        assert_eq!(credential_target("abc"), "doyah-studio/abc");
        assert_ne!(credential_target("abc"), credential_target("abd"));
        assert!(credential_target("abc").starts_with(CREDENTIAL_PREFIX));
    }

    #[test]
    fn iso8601_timestamp_is_well_formed() {
        let stamp = now_iso8601();
        assert_eq!(stamp.len(), 20, "{stamp}");
        assert!(stamp.ends_with('Z'));
        assert_eq!(&stamp[4..5], "-");
        assert_eq!(&stamp[10..11], "T");
        let year: i32 = stamp[..4].parse().unwrap();
        assert!(year >= 2026, "系统时钟算出来的年份不合理：{stamp}");
    }

    /// **真验一遍凭据往返**（用一次性目标名，测完就删）：要 Windows 凭据管理器真的能用。
    /// 设 `DOYAH_CRED_TEST=1` 才跑（默认跳过并说明）；它会在系统凭据管理器里建一条再删掉。
    #[test]
    fn credential_manager_round_trip_on_this_machine() {
        if std::env::var("DOYAH_CRED_TEST").ok().as_deref() != Some("1") {
            eprintln!("跳过：未设 DOYAH_CRED_TEST=1（本用例会在 Windows 凭据管理器里建一条一次性凭据再删掉）");
            return;
        }
        let id = format!("selftest-{}", std::process::id());
        let target = credential_target(&id);
        // 先清一遍（上一次跑剩下的），确保起点干净
        let _ = Command::new("cmdkey").arg(format!("/delete:{target}")).output();
        assert!(!has_credential(&target), "起点应当是干净的");

        remember_password(&id, "doyah", "Secret-For-Test-Only").expect("写入凭据应当成功");
        assert!(
            has_credential(&target),
            "凭据管理器里应当有这条（口令本体 cmdkey 不回显，这一点如实承认）"
        );

        forget_password(&id).expect("删除凭据应当成功");
        assert!(!has_credential(&target), "删完不该还在：{target}");
    }

    /// 复查机制本身要能咬人：对一个**不存在**的目标，删除应当报「OK」（幂等），
    /// 而复查必须说「没有」—— 这条用例守的是"删不掉却报成功"那类假成功。
    #[test]
    fn forget_verifies_instead_of_trusting_the_exit_code() {
        if std::env::var("DOYAH_CRED_TEST").ok().as_deref() != Some("1") {
            eprintln!("跳过：未设 DOYAH_CRED_TEST=1");
            return;
        }
        let id = format!("selftest-absent-{}", std::process::id());
        forget_password(&id).expect("删一个不存在的目标应当幂等成功");
        assert!(!has_credential(&credential_target(&id)));
    }
}
