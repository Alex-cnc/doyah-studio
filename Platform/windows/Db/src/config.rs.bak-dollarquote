//! 连接配置模型（契约等价物：macOS 侧 `Core/ConnectionConfig.swift`）
//!
//! **本文件只放模型与判定，不碰存储 / 密钥 / 网络**：
//! 口令走凭据存储（§8.5.2-2，落 `Platform/Windows/`），本层连"口令"这个词都不该出现。
//!
//! 三条口径（照抄契约）：
//! ① `schema_version` 落进配置本身 —— 老配置读得出来才不会把字段悄悄丢掉；
//! ② `is_valid()` 是**唯一**的合法性判据（表单与模型不许各写一套，那是漂移的经典来源）；
//! ③ 环境标签 `environment` 缺省是 `None`（没标就是没标）—— 不硬塞"生产"，否则每个连接都变红。

use serde::{Deserialize, Serialize};

use crate::db_type::{DatabaseType, SslMode};

/// 配置自身的模式版本（升版 = 加字段且需要迁移时）。
pub const CURRENT_SCHEMA_VERSION: u32 = 1;

/// SSH 隧道（FR-CONN-18）。`None` = 直连 —— **默认直连**，不给已有连接凭空加一层跳板。
///
/// **口令 / 私钥口令不在这里**（走凭据存储，键由隧道标识派生）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SshTunnelConfig {
    pub host: String,
    #[serde(default)]
    pub port: u16,
    pub user: String,
    /// 私钥路径（`None` = 用口令认证）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub private_key_path: Option<String>,
    /// 隧道是否启用（**允许保存但不启用**：表单里关了开关不该丢掉已填的信息）。
    #[serde(default)]
    pub is_enabled: bool,
}

impl SshTunnelConfig {
    /// 隧道参数是否成立。**没启用时调用方不该拿它挡保存**（见 `ConnectionConfig::is_valid`）。
    pub fn is_valid(&self) -> bool {
        !self.host.trim().is_empty() && !self.user.trim().is_empty()
    }
}

/// 一条连接配置。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectionConfig {
    /// 稳定标识（连接串导入时由调用方给，落盘后不再变）。
    pub id: String,
    pub name: String,
    pub db_type: DatabaseType,
    pub host: String,
    pub port: u16,
    #[serde(default)]
    pub database: String,
    #[serde(default)]
    pub username: String,
    pub ssl_mode: SslMode,
    /// 连接超时（秒）。
    #[serde(default = "default_timeout")]
    pub timeout: u32,
    /// 配置自身的模式版本。
    ///
    /// **缺字段按 v0 解码**（`#[serde(default = "default_schema_version")]`）：老文件里没有这一项时
    /// 直接反序列化会整份读不出来 —— 那正是「预留迁移能力」要避免的事（用户升了应用，连接列表打不开）。
    #[serde(default = "default_schema_version")]
    pub schema_version: u32,
    /// 环境标签（生产 / 预发 / 测试…）。`None` = 没标。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub environment: Option<String>,
    /// 用户自选颜色（分类色名）。环境标签的语义色优先于它。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub color_tag: Option<String>,
    /// 只读连接（FR-CONN-17）：客户端**拒绝执行写语句**。
    ///
    /// 口径必须说清：这是**本机保护**，不替代数据库权限 —— 它拦的是"我在这台机器上点错了"。
    #[serde(default)]
    pub is_read_only: bool,
    /// 连接建立后自动执行的 SQL（FR-CONN-17），例如 `SET search_path`。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub startup_sql: Option<String>,
    /// 自定义分组（FR-CONN-15）：空 / 纯空白视为**未分组**（否则会出现名字是空格的诡异分组）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub group: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ssh_tunnel: Option<SshTunnelConfig>,
}

fn default_timeout() -> u32 {
    5
}

/// 老文件缺 `schemaVersion` 时按 **v0** 解码（FR-CONN-10 / DR-03 的迁移路径起点）。
pub const LEGACY_SCHEMA_VERSION: u32 = 0;

fn default_schema_version() -> u32 {
    LEGACY_SCHEMA_VERSION
}

/// 表单字段（**点名是哪一项**，不是一个笼统的"不合法"）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ConnectionField {
    Name,
    Host,
    Port,
    Username,
}

impl ConnectionField {
    /// 稳定的字段键（界面据此定位到那一格、写校验提示）。
    pub const fn key(self) -> &'static str {
        match self {
            ConnectionField::Name => "name",
            ConnectionField::Host => "host",
            ConnectionField::Port => "port",
            ConnectionField::Username => "username",
        }
    }
}

/// 一项不合法的**字段 + 原因**。
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FieldProblem {
    pub field: ConnectionField,
    pub message: String,
}

/// 端口文本 → 端口号。**表单层那个"先单独解析端口"的一步**（FR-CONN-06 的原文口径）：
/// 非数字 / `0` / `>65535` 一律拒，**不让类型默认端口把非法输入洗白**。
pub fn port_from_text(text: &str) -> Result<u16, String> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return Err("端口不能为空".to_string());
    }
    let value: u32 = trimmed
        .parse()
        .map_err(|_| format!("端口必须是数字：{trimmed}"))?;
    if !(1..=65535).contains(&value) {
        return Err(format!("端口要在 1~65535：{value}"));
    }
    Ok(value as u16)
}

/// **逐项校验**（FR-CONN-06）：名称 / 主机 / 端口（1~65535）/ 用户名非空。
///
/// 为什么它和 `ConnectionConfig::is_valid` 不是"两套规则"：`is_valid` 是这台配置的**判定**，
/// 本函数是同一套规则的**逐项说明**（同一份口径的两种出口）；一致性由单测钉住
/// （`form_validation_agrees_with_the_model`）。
pub fn validate_form(name: &str, host: &str, port_text: &str, username: &str) -> Vec<FieldProblem> {
    let mut problems = Vec::new();
    if name.trim().is_empty() {
        problems.push(FieldProblem {
            field: ConnectionField::Name,
            message: "名称不能为空".to_string(),
        });
    }
    if host.trim().is_empty() {
        problems.push(FieldProblem {
            field: ConnectionField::Host,
            message: "主机不能为空".to_string(),
        });
    }
    if let Err(reason) = port_from_text(port_text) {
        problems.push(FieldProblem {
            field: ConnectionField::Port,
            message: reason,
        });
    }
    if username.trim().is_empty() {
        problems.push(FieldProblem {
            field: ConnectionField::Username,
            message: "用户名不能为空".to_string(),
        });
    }
    problems
}

impl ConnectionConfig {
    /// 用**类型默认值**兜住的构造（端口 / SSL / 超时都不在调用点各写一份）。
    pub fn new(id: impl Into<String>, name: impl Into<String>, db_type: DatabaseType) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            db_type,
            host: "127.0.0.1".to_string(),
            port: db_type.default_port(),
            database: String::new(),
            username: String::new(),
            ssl_mode: db_type.default_ssl_mode(),
            timeout: default_timeout(),
            schema_version: CURRENT_SCHEMA_VERSION,
            environment: None,
            color_tag: None,
            is_read_only: false,
            startup_sql: None,
            group: None,
            ssh_tunnel: None,
        }
    }

    /// 归一化后的组名：空 / 纯空白 → `None`（未分组）。
    pub fn normalized_group(&self) -> Option<&str> {
        self.group
            .as_deref()
            .map(str::trim)
            .filter(|g| !g.is_empty())
    }

    /// 启动 SQL 拆成**逐条**语句（**注释被丢掉**、空段不算）。
    ///
    /// 为什么要逐条：连上之后要一条条发、一条条报错 —— 一条失败不该把后面的一起吞掉
    /// （`search_path` 没设上，后面所有查询都可能找错表）。
    pub fn startup_statements(&self) -> Vec<String> {
        let Some(sql) = self.startup_sql.as_deref() else {
            return Vec::new();
        };
        if sql.trim().is_empty() {
            return Vec::new();
        }
        // 切分器已经把注释丢掉、空段滤掉了；这里再 trim 一遍是防御性的（改了切分器也不至于漏）。
        split_statements(sql)
            .into_iter()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect()
    }

    /// 地址（显示用，**不含账号口令**）。
    pub fn endpoint_description(&self) -> String {
        format!("{}:{}", self.host, self.port)
    }

    /// **唯一**的合法性判据。表单允许保存而模型判非法（或反过来）是两套规则漂移的经典来源。
    ///
    /// 隧道参数的合法性**并进同一条规则**：没配隧道、或隧道被关掉时，这一项恒真 —— 直连行为不变。
    pub fn is_valid(&self) -> bool {
        let tunnel_ok = match &self.ssh_tunnel {
            None => true,
            Some(t) => !t.is_enabled || t.is_valid(),
        };
        !self.name.trim().is_empty()
            && !self.host.trim().is_empty()
            && self.port > 0
            && !self.username.trim().is_empty()
            && tunnel_ok
    }

    /// 这份配置要不要迁移（FR-CONN-10）：版本比当前**低**才算要迁。
    /// **更高的版本一律不动**（逐字节保住读不懂的字段，不迁移、不降级）。
    pub fn needs_migration(&self) -> bool {
        self.schema_version < CURRENT_SCHEMA_VERSION
    }

    /// v0 → v1：**只做能确定的正常化**。
    ///
    /// 明文写清做了什么、不做什么：端口 `0`（老档里越界 / 缺失的落点）落回**该类型的默认端口**、
    /// 超时 `0` 落回 5；**不猜**主机名 / 用户名 / 库名（猜这些只会把错误藏起来）。
    /// 版本已经 >= 当前的：原样返回（含"更新版本"）。
    pub fn migrated(self) -> Self {
        if !self.needs_migration() {
            return self;
        }
        let mut next = self;
        if next.port == 0 {
            next.port = next.db_type.default_port();
        }
        if next.timeout == 0 {
            next.timeout = default_timeout();
        }
        next.schema_version = CURRENT_SCHEMA_VERSION;
        next
    }

    /// **切换数据库类型**（FR-CONN-02 的类型联动）：默认端口 / 默认 SSL / 默认 schema 跟着新类型走。
    ///
    /// 明确不做的事：**不改**名称 / 主机 / 库名 / 用户名 / 只读标记 —— 那些与"是哪一种库"无关，
    /// 换类型时把它们一起改掉就是"我改了个类型，连的东西全变了"。
    pub fn switch_type(&mut self, to: DatabaseType) {
        self.db_type = to;
        self.port = to.default_port();
        self.ssl_mode = to.default_ssl_mode();
    }
}

/// 连接配置包（换机迁移用）：**只有配置，没有口令**。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectionBundle {
    pub format_version: u32,
    /// 导出时间（ISO-8601 字符串：跨端可读优先于类型精确）。
    pub exported_at: String,
    pub connections: Vec<ConnectionConfig>,
    /// 包里**故意不含**口令的说明（写给打开文件的人看）。
    pub note: String,
}

/// 配置包的格式版本。
pub const CURRENT_BUNDLE_FORMAT_VERSION: u32 = 1;

impl ConnectionBundle {
    pub const DEFAULT_NOTE: &'static str =
        "本文件只含连接配置，不含任何口令；口令请在新机器上重新输入。";

    pub fn new(exported_at: impl Into<String>, connections: Vec<ConnectionConfig>) -> Self {
        Self {
            format_version: CURRENT_BUNDLE_FORMAT_VERSION,
            exported_at: exported_at.into(),
            connections,
            note: Self::DEFAULT_NOTE.to_string(),
        }
    }

    pub fn encoded(&self) -> Result<String, BundleError> {
        serde_json::to_string_pretty(self).map_err(|e| BundleError::Malformed(e.to_string()))
    }

    /// **导出**（FR-CONN-19 的"导出件不含口令"）：编码之后**再逐字扫一遍**，
    /// 命中疑似口令字段就**拒绝给出导出件**（不是"提醒一下"）。
    ///
    /// 为什么要多这一道：`ConnectionConfig` 现在没有口令字段，所以"导出不含口令"看起来是构造上必然的；
    /// 但**将来某次改动**加一个字段、或调用方塞进来一份别处来的 JSON，就可能在没人察觉的情况下写出去。
    /// 这一道让那种改动**当场失败**，而不是等用户把带口令的文件发给别人。
    pub fn export_text(&self) -> Result<String, BundleError> {
        let text = self.encoded()?;
        if let Some(word) = secret_field(&text) {
            return Err(BundleError::Malformed(format!(
                "导出件里出现了疑似口令字段（{word}）—— 已拒绝导出"
            )));
        }
        Ok(text)
    }

    /// 解析配置包。**版本比当前新时拒绝** —— 避免把读不懂的字段悄悄丢掉。
    ///
    /// **逐条走迁移**（FR-CONN-10）：老档（缺 `schemaVersion`，读作 v0）在这里被正常化到当前版本，
    /// 于是"用户升了应用连接列表打不开"这件事不会发生。更高的版本逐字节保住、不迁移。
    pub fn decode(text: &str) -> Result<Self, BundleError> {
        let mut bundle: Self =
            serde_json::from_str(text).map_err(|e| BundleError::Malformed(e.to_string()))?;
        if bundle.format_version > CURRENT_BUNDLE_FORMAT_VERSION {
            return Err(BundleError::TooNew(bundle.format_version));
        }
        for connection in &mut bundle.connections {
            *connection = connection.clone().migrated();
        }
        Ok(bundle)
    }
}

/// 文本里有没有"疑似口令"字段，返回命中的词（`None` = 干净）。
///
/// 判据口径（与表示层 `connections::bundle_text_has_no_secret` 同一套，**同一份词表**）：
/// 只认**会真的把口令写进文件**的那种形状（`"password": …`），不拿说明文字误报 ——
/// 判据误报多了就会被绕开。
pub fn secret_field(text: &str) -> Option<&'static str> {
    for word in [r#""password""#, r#""passwd""#, r#""secret""#, r#""pwd""#] {
        if text.contains(word) {
            return Some(word);
        }
    }
    None
}

/// 「上次选中的连接」（FR-CONN-11）：**只存 id**（名字 / 地址会变，id 落盘后不再变）。
///
/// 单独一份小文件（不是塞进连接列表里）：选中态是**界面偏好**，连接列表是**配置**；
/// 混在一起会出现"只想记住选了哪条，结果把整份配置重写了一遍"。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ConnectionSelection {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub selected_id: Option<String>,
}

impl ConnectionSelection {
    pub fn new(id: impl Into<String>) -> Self {
        Self {
            selected_id: Some(id.into()),
        }
    }

    /// 冷启动恢复：记住的那条**还在**就选它；不在了**回退列表首条**（不硬记一条已经不存在的）。
    /// 一条都没有 ⇒ `None`（界面据此显示"未选中"）。
    pub fn restore<'a>(&self, available: &'a [String]) -> Option<&'a str> {
        if let Some(remembered) = self.selected_id.as_deref() {
            if let Some(hit) = available.iter().find(|id| id.as_str() == remembered) {
                return Some(hit.as_str());
            }
        }
        available.first().map(|id| id.as_str())
    }

    pub fn encoded(&self) -> Result<String, BundleError> {
        serde_json::to_string_pretty(self).map_err(|e| BundleError::Malformed(e.to_string()))
    }

    pub fn decode(text: &str) -> Result<Self, BundleError> {
        serde_json::from_str(text).map_err(|e| BundleError::Malformed(e.to_string()))
    }
}

/// 配置包的错误（**说清是哪一种**，不合并成一句"解析失败"）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BundleError {
    /// 版本比本客户端支持的更新。
    TooNew(u32),
    /// 内容本身读不出来（JSON 坏了 / 字段类型不对）。
    Malformed(String),
}

impl std::fmt::Display for BundleError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BundleError::TooNew(v) => write!(
                f,
                "配置包版本 {v} 比本客户端支持的 {CURRENT_BUNDLE_FORMAT_VERSION} 更新，请升级客户端"
            ),
            BundleError::Malformed(msg) => write!(f, "配置包内容读不出来：{msg}"),
        }
    }
}

impl std::error::Error for BundleError {}

/// 逐条切分 SQL：**只认分号，且跳过字符串字面量；注释被丢掉（不进食）**。
///
/// 为什么注释要**丢掉**而不是原样留着：留着的话，`SET a; -- 说明\nSET b;` 的中间那段会变成
/// 一条"以 `--` 开头"的独立语句，调用方只能靠"是否以 `--` 开头"去丢它 —— 而那样会把
/// **注释后面紧跟的真语句一起丢掉**（临时目录真跑抓到：`SET statement_timeout` 整条消失，
/// 用户设的超时静默没生效，这正是本函数存在的理由）。
pub fn split_statements(sql: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut current = String::new();
    let mut chars = sql.chars().peekable();
    let mut in_single = false;
    let mut in_double = false;
    let mut in_line_comment = false;
    let mut in_block_comment = false;

    while let Some(c) = chars.next() {
        if in_line_comment {
            if c == '\n' {
                in_line_comment = false;
            }
            continue;
        }
        if in_block_comment {
            if c == '*' && chars.peek() == Some(&'/') {
                chars.next();
                in_block_comment = false;
            }
            continue;
        }
        if in_single {
            current.push(c);
            if c == '\'' {
                // 连写两个单引号 = 转义，不算结束
                if chars.peek() == Some(&'\'') {
                    current.push(chars.next().unwrap());
                } else {
                    in_single = false;
                }
            }
            continue;
        }
        if in_double {
            current.push(c);
            if c == '"' {
                in_double = false;
            }
            continue;
        }
        match c {
            '\'' => {
                in_single = true;
                current.push(c);
            }
            '"' => {
                in_double = true;
                current.push(c);
            }
            // 注释只在"不在字符串里"时才成立（字面量里的 `--` / `/*` 是普通字符）
            '-' if chars.peek() == Some(&'-') => {
                chars.next();
                in_line_comment = true;
            }
            '/' if chars.peek() == Some(&'*') => {
                chars.next();
                in_block_comment = true;
            }
            ';' => {
                let statement = current.trim().to_string();
                if !statement.is_empty() {
                    out.push(statement);
                }
                current.clear();
            }
            _ => current.push(c),
        }
    }
    let statement = current.trim().to_string();
    if !statement.is_empty() {
        out.push(statement);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pg() -> ConnectionConfig {
        let mut c = ConnectionConfig::new(
            "33333333-3333-3333-3333-333333333333",
            "本地",
            DatabaseType::Postgresql,
        );
        c.host = "127.0.0.1".into();
        c.database = "postgres".into();
        c.username = "postgres".into();
        c
    }

    #[test]
    fn defaults_come_from_the_type() {
        let c = ConnectionConfig::new("id", "n", DatabaseType::Gbase8a);
        assert_eq!(c.port, 5258);
        assert_eq!(c.ssl_mode, SslMode::Prefer);
        assert_eq!(c.timeout, 5);
        assert_eq!(c.schema_version, CURRENT_SCHEMA_VERSION);
        assert!(!c.is_read_only);
        assert!(c.environment.is_none());
        assert!(c.ssh_tunnel.is_none());
    }

    #[test]
    fn validity_needs_name_host_username_and_a_port() {
        let mut c = pg();
        assert!(c.is_valid());
        c.name = "   ".into();
        assert!(!c.is_valid());
        c = pg();
        c.host = "".into();
        assert!(!c.is_valid());
        c = pg();
        c.username = " ".into();
        assert!(!c.is_valid());
        c = pg();
        c.port = 0;
        assert!(!c.is_valid());
    }

    #[test]
    fn a_disabled_or_absent_tunnel_never_blocks_saving() {
        let mut c = pg();
        // 没配隧道 ⇒ 直连，照旧合法
        assert!(c.is_valid());
        // 配了但关掉，哪怕字段空着 ⇒ 仍然合法（表单里关了开关不该丢掉已填的信息）
        c.ssh_tunnel = Some(SshTunnelConfig {
            host: String::new(),
            port: 0,
            user: String::new(),
            private_key_path: None,
            is_enabled: false,
        });
        assert!(c.is_valid());
        // 启用且空 ⇒ 才判非法
        c.ssh_tunnel.as_mut().unwrap().is_enabled = true;
        assert!(!c.is_valid());
        c.ssh_tunnel.as_mut().unwrap().host = "jump.example".into();
        c.ssh_tunnel.as_mut().unwrap().user = "bob".into();
        assert!(c.is_valid());
    }

    #[test]
    fn group_whitespace_is_no_group() {
        let mut c = pg();
        assert_eq!(c.normalized_group(), None);
        c.group = Some("   ".into());
        assert_eq!(c.normalized_group(), None);
        c.group = Some(" 项目 / 生产 ".into());
        assert_eq!(c.normalized_group(), Some("项目 / 生产"));
    }

    #[test]
    fn startup_sql_is_split_per_statement_and_comments_dropped() {
        let mut c = pg();
        assert!(c.startup_statements().is_empty());
        c.startup_sql = Some("   ".into());
        assert!(c.startup_statements().is_empty());
        c.startup_sql =
            Some("SET search_path = app; -- 说明\nSET statement_timeout = '5s';;".into());
        let s = c.startup_statements();
        assert_eq!(
            s.len(),
            2,
            "注释丢掉、空段不算，两条真语句都要在（实际：{s:?}）"
        );
        assert_eq!(s[0], "SET search_path = app");
        assert_eq!(s[1], "SET statement_timeout = '5s'");
        c.startup_sql = Some("-- 只有注释".into());
        assert!(c.startup_statements().is_empty());
        // 注释后面紧跟真语句（没有分号隔开）⇒ 真语句必须留下 —— 早期版本会把整条丢掉
        c.startup_sql = Some("  -- 说明\nSET search_path = app".into());
        let mixed = c.startup_statements();
        assert_eq!(
            mixed,
            vec!["SET search_path = app".to_string()],
            "{mixed:?}"
        );
        // 末尾没分号也算一条
        c.startup_sql = Some("SET a = 1".into());
        assert_eq!(c.startup_statements(), vec!["SET a = 1".to_string()]);
    }

    #[test]
    fn splitter_drops_comments_and_never_cuts_inside_literals() {
        // 注释（含它的换行）被丢掉，前后两条真语句分开
        let parts = split_statements("SET a = 1; -- 说明\nSET b = 2;");
        assert_eq!(
            parts,
            vec!["SET a = 1".to_string(), "SET b = 2".to_string()]
        );

        // 字面量里的分号不是分隔符；注释里的单引号不许把后面的语句吞掉
        let parts = split_statements("INSERT INTO t VALUES ('a;b'); -- it's fine\nSELECT 2");
        assert_eq!(parts.len(), 2, "{parts:?}");
        assert!(parts[0].contains("'a;b'"));
        assert_eq!(parts[1], "SELECT 2");

        // 块注释同样丢掉（**只丢注释本身**：注释两边的空白原样留着 ⇒ 可能出现双空格，
        // 这里断言用"去掉空白后相等"，不假装自己会重排 SQL）
        let parts = split_statements("SELECT /* ; */ 1; SELECT 2");
        assert_eq!(parts.len(), 2, "{parts:?}");
        assert_eq!(
            parts[0].split_whitespace().collect::<Vec<_>>(),
            vec!["SELECT", "1"]
        );
        assert_eq!(parts[1], "SELECT 2");

        // 字面量里的 `--` 不是注释
        let parts = split_statements("SELECT 'a--b'; SELECT 2");
        assert_eq!(parts.len(), 2, "{parts:?}");
        assert!(parts[0].contains("a--b"));

        // 双引号标识符里的分号不分隔
        let quoted_ident = split_statements("SELECT \"a;b\" FROM t");
        assert_eq!(quoted_ident.len(), 1);

        // 连写两个单引号是转义，不算结束
        let escaped = split_statements("SELECT 'it''s; fine'");
        assert_eq!(escaped.len(), 1);

        // 空段（连写分号）不算一条
        assert_eq!(split_statements(";; ;"), Vec::<String>::new());
        assert_eq!(split_statements("   "), Vec::<String>::new());
    }

    #[test]
    fn config_round_trips_through_json_with_camel_case_keys() {
        let mut c = pg();
        c.environment = Some("production".into());
        c.is_read_only = true;
        let text = serde_json::to_string(&c).unwrap();
        assert!(text.contains("\"dbType\":\"postgresql\""), "{text}");
        assert!(text.contains("\"sslMode\":\"prefer\""), "{text}");
        assert!(text.contains("\"isReadOnly\":true"), "{text}");
        assert!(!text.contains("password"), "配置里不许出现口令字段：{text}");
        let back: ConnectionConfig = serde_json::from_str(&text).unwrap();
        assert_eq!(back, c);
    }

    #[test]
    fn bundle_refuses_a_newer_format_version_and_says_which() {
        let mut bundle = ConnectionBundle::new("2026-10-02T00:00:00Z", vec![pg()]);
        let text = bundle.encoded().unwrap();
        assert!(text.contains("本文件只含连接配置"), "{text}");
        let back = ConnectionBundle::decode(&text).unwrap();
        assert_eq!(back.connections.len(), 1);
        assert_eq!(back.format_version, CURRENT_BUNDLE_FORMAT_VERSION);

        bundle.format_version = CURRENT_BUNDLE_FORMAT_VERSION + 1;
        let newer = bundle.encoded().unwrap();
        match ConnectionBundle::decode(&newer) {
            Err(BundleError::TooNew(v)) => assert_eq!(v, CURRENT_BUNDLE_FORMAT_VERSION + 1),
            other => panic!("版本更新时必须拒绝，实际：{other:?}"),
        }
        assert!(matches!(
            ConnectionBundle::decode("{ not json"),
            Err(BundleError::Malformed(_))
        ));
    }

    #[test]
    fn endpoint_description_has_no_credentials() {
        let c = pg();
        assert_eq!(c.endpoint_description(), "127.0.0.1:5432");
    }

    // ── S-1a：连接配置面收口（校验 / 持久化 / 导入导出 / 类型联动）────────────────────────

    /// 老档：**缺 `schemaVersion`**（读作 v0），且端口是越界的 `0`、超时是 `0`。
    fn legacy_bundle_json() -> String {
        r#"{
  "formatVersion": 1,
  "exportedAt": "2026-01-01T00:00:00Z",
  "note": "老档",
  "connections": [
    {
      "id": "old-1",
      "name": "老库",
      "dbType": "gbase8a",
      "host": "10.0.0.9",
      "port": 0,
      "database": "legacy",
      "username": "",
      "sslMode": "prefer",
      "timeout": 0
    }
  ]
}"#
        .to_string()
    }

    #[test]
    fn form_validation_passes_a_complete_form() {
        assert!(validate_form("本地库", "127.0.0.1", "5432", "postgres").is_empty());
    }

    #[test]
    fn form_validation_names_each_field_that_is_empty() {
        let problems = validate_form("   ", "", "5432", "  ");
        let fields: Vec<&str> = problems.iter().map(|p| p.field.key()).collect();
        assert_eq!(fields, vec!["name", "host", "username"], "{problems:?}");
    }

    #[test]
    fn form_validation_rejects_out_of_range_and_non_numeric_ports() {
        // 负例面：0 / 65536 / 非数字 / 空 / 负数 / 小数 —— 每一项都只报"端口"这一格
        for text in ["0", "65536", "abc", "", "-1", "5432.5"] {
            let problems = validate_form("n", "h", text, "u");
            assert_eq!(problems.len(), 1, "{text} 应当只报一项：{problems:?}");
            assert_eq!(problems[0].field, ConnectionField::Port, "{text}");
        }
        // 边界内的两端都要过
        assert!(validate_form("n", "h", "1", "u").is_empty());
        assert!(validate_form("n", "h", "65535", "u").is_empty());
    }

    #[test]
    fn port_text_parsing_keeps_every_rejection_specific() {
        assert_eq!(port_from_text(" 5432 "), Ok(5432));
        assert_eq!(port_from_text("0").unwrap_err(), "端口要在 1~65535：0");
        assert_eq!(
            port_from_text("65536").unwrap_err(),
            "端口要在 1~65535：65536"
        );
        assert_eq!(port_from_text("abc").unwrap_err(), "端口必须是数字：abc");
        assert_eq!(port_from_text("  ").unwrap_err(), "端口不能为空");
    }

    #[test]
    fn form_validation_agrees_with_the_model() {
        // 同一套规则的两个出口：表单逐项报空 ⟺ 模型判合法（谁改歪了这条就红）
        for (name, host, port, user, valid) in [
            ("n", "h", "5432", "u", true),
            ("", "h", "5432", "u", false),
            ("n", "", "5432", "u", false),
            ("n", "h", "0", "u", false),
            ("n", "h", "65536", "u", false),
            ("n", "h", "abc", "u", false),
            ("n", "h", "5432", " ", false),
        ] {
            let mut c = pg();
            c.name = name.to_string();
            c.host = host.to_string();
            c.username = user.to_string();
            c.port = port_from_text(port).unwrap_or(0);
            assert_eq!(
                validate_form(name, host, port, user).is_empty(),
                valid,
                "表单逐项：{name}/{host}/{port}/{user}"
            );
            assert_eq!(c.is_valid(), valid, "模型判定：{name}/{host}/{port}/{user}");
        }
    }

    #[test]
    fn an_old_document_without_schema_version_is_migrated_on_read() {
        let bundle = ConnectionBundle::decode(&legacy_bundle_json()).expect("老档要读得出来");
        let c = &bundle.connections[0];
        // 一用例：缺字段按 v0 解码 ⇒ **走迁移分支**；一断言：迁到当前版本且越界值落回类型默认
        assert_eq!(
            c.schema_version, CURRENT_SCHEMA_VERSION,
            "缺 schemaVersion 的老档必须被迁到当前版本"
        );
        assert_eq!(c.port, 5258, "越界端口 0 要落回该类型（gbase8a）默认端口");
        assert_eq!(c.timeout, 5, "超时 0 落回 5");
        // **不猜**的几项一字不动
        assert_eq!(c.host, "10.0.0.9");
        assert_eq!(c.database, "legacy");
        assert_eq!(c.username, "", "用户名不许被猜出来");
    }

    #[test]
    fn a_newer_schema_version_is_left_alone() {
        let mut c = pg();
        c.schema_version = CURRENT_SCHEMA_VERSION + 2;
        c.port = 0;
        assert!(!c.needs_migration());
        assert_eq!(
            c.clone().migrated(),
            c,
            "更新版本的配置必须原样保住（不迁移、不降级、不猜）"
        );
    }

    #[test]
    fn migration_is_idempotent() {
        let mut bundle = ConnectionBundle::decode(&legacy_bundle_json()).unwrap();
        let first = bundle.connections.remove(0);
        assert_eq!(
            first.clone().migrated(),
            first,
            "迁移过的再迁一次不许变（否则每次加载都在改文件）"
        );
    }

    #[test]
    fn switching_type_follows_that_types_defaults() {
        let mut c = pg();
        c.name = "我的库".into();
        c.host = "10.0.0.5".into();
        c.username = "bob".into();
        c.database = "prod".into();
        c.is_read_only = true;

        for (kind, port, ssl, schema) in [
            (
                DatabaseType::Postgresql,
                5432,
                SslMode::Prefer,
                Some("public"),
            ),
            (DatabaseType::Mysql, 3306, SslMode::Prefer, None),
            (DatabaseType::Gbase8a, 5258, SslMode::Prefer, None),
        ] {
            c.switch_type(kind);
            assert_eq!(c.db_type, kind);
            assert_eq!(c.port, port, "{kind:?} 的默认端口");
            assert_eq!(c.ssl_mode, ssl, "{kind:?} 的默认 SSL");
            assert_eq!(kind.default_schema(), schema, "{kind:?} 的默认 schema");
            // 与"是哪一种库"无关的字段一字不动
            assert_eq!(c.name, "我的库");
            assert_eq!(c.host, "10.0.0.5");
            assert_eq!(c.username, "bob");
            assert_eq!(c.database, "prod");
            assert!(c.is_read_only);
        }
    }

    #[test]
    fn the_selected_connection_survives_a_restart() {
        // 持久：选中态落成一份 JSON（**只存 id**）
        let text = ConnectionSelection::new("id-b").encoded().unwrap();
        assert!(text.contains("\"selectedId\": \"id-b\""), "{text}");
        // 冷启动读回：新进程把文件读出来，仍在的连接会被选回
        let restored = ConnectionSelection::decode(&text).unwrap();
        let available = vec!["id-a".to_string(), "id-b".to_string()];
        assert_eq!(restored.restore(&available), Some("id-b"));
    }

    #[test]
    fn a_remembered_connection_that_is_gone_falls_back_to_the_first() {
        let selection = ConnectionSelection::new("id-gone");
        let available = vec!["id-a".to_string(), "id-b".to_string()];
        assert_eq!(
            selection.restore(&available),
            Some("id-a"),
            "记住的那条已经不在列表里 ⇒ 回退首条（不硬记一条不存在的）"
        );
        assert_eq!(
            ConnectionSelection::default().restore(&available),
            Some("id-a")
        );
        assert_eq!(selection.restore(&[]), None, "一条都没有 ⇒ 未选中");
    }

    #[test]
    fn the_exported_bundle_never_carries_a_password_field() {
        let bundle = ConnectionBundle::new("2026-10-06T00:00:00Z", vec![pg()]);
        let text = bundle.export_text().unwrap();
        assert!(
            secret_field(&text).is_none(),
            "导出件里出现疑似口令字段：{text}"
        );
        assert!(text.contains("本文件只含连接配置"), "包里要写明不含口令");
    }

    #[test]
    fn the_export_guard_catches_a_password_written_into_the_bundle() {
        // 负例：**把口令写进导出件** ⇒ 判红并点名（这是那道护栏存在的唯一理由）
        let bundle = ConnectionBundle::new("2026-10-06T00:00:00Z", vec![pg()]);
        let tampered = bundle
            .encoded()
            .unwrap()
            .replace("\"note\"", "\"password\":\"hunter2\", \"note\"");
        assert_eq!(
            secret_field(&tampered),
            Some("\"password\""),
            "写进去的口令必须当场被抓到"
        );
        // 而且要说清：反序列化**不会**替我们挡住它（未知字段被静默丢掉）——
        // 所以这道"扫原文"的护栏不是多余的。
        assert!(ConnectionBundle::decode(&tampered).is_ok());
    }
}
