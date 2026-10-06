//! 数据库类型与 SSL 模式 —— 与服务端无关的**纯分类**（契约等价物：macOS 侧 `Core/DatabaseType.swift`）
//!
//! 三条口径（照抄契约，改一条即两端分叉）：
//! ① `rawValue` = 持久化与跨端交换用的字面量（不许改，改了老配置就读不出来）；
//! ② 默认端口 / 默认 SSL 模式**挂在类型上**，不在表单里各写一份；
//! ③ `displayName` **不是**给界面直接用的文案 —— 界面文案走语言表，这里只给**键**。

use std::fmt;

use serde::{Deserialize, Serialize};

/// 数据库类型。`raw_value()` 即持久化字面量。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DatabaseType {
    Postgresql,
    Mysql,
    #[serde(rename = "gbase8a")]
    Gbase8a,
}

impl DatabaseType {
    /// 持久化 / 交换用字面量（与对侧 `String` 枚举逐字相同）。
    pub const fn raw_value(self) -> &'static str {
        match self {
            DatabaseType::Postgresql => "postgresql",
            DatabaseType::Mysql => "mysql",
            DatabaseType::Gbase8a => "gbase8a",
        }
    }

    /// 由字面量解析。**认不出就返回 `None`**（调用方自己决定是回退还是报错，不在这里静默兜底）。
    pub fn from_raw(value: &str) -> Option<Self> {
        match value.to_ascii_lowercase().as_str() {
            "postgresql" | "postgres" => Some(DatabaseType::Postgresql),
            "mysql" => Some(DatabaseType::Mysql),
            "gbase8a" | "gbase" => Some(DatabaseType::Gbase8a),
            _ => None,
        }
    }

    /// 界面显示名的**语言键**（不是文案本身：文案在表示层的语言表里）。
    pub const fn display_key(self) -> &'static str {
        match self {
            DatabaseType::Postgresql => "db.postgresql",
            DatabaseType::Mysql => "db.mysql",
            DatabaseType::Gbase8a => "db.gbase8a",
        }
    }

    /// 默认端口（挂在类型上：表单不许自己写一份默认值）。
    pub const fn default_port(self) -> u16 {
        match self {
            DatabaseType::Postgresql => 5432,
            DatabaseType::Mysql => 3306,
            DatabaseType::Gbase8a => 5258,
        }
    }

    /// 默认 SSL 模式。
    pub const fn default_ssl_mode(self) -> SslMode {
        match self {
            DatabaseType::Postgresql => SslMode::Prefer,
            DatabaseType::Mysql => SslMode::Prefer,
            DatabaseType::Gbase8a => SslMode::Prefer,
        }
    }

    /// **默认 schema**（FR-CONN-02 的类型联动第三项）。
    ///
    /// `None` = 这个方言**没有 schema 层**（MySQL 里 database 与 schema 是同一个东西；
    /// GBase 同族）—— 树形结构与空态文案都按这同一个事实判，不各写一处。
    ///
    /// 一处**如实登记的对侧差异**：macOS 侧 `Core/DatabaseType.swift` 的 `defaultSSLMode` 对 GBase 8a
    /// 给的是 `.disable`，本侧当前是 `.prefer`。属"GBase 方言面按已放下闸"的既有读数，
    /// **本片不改行为**（改了要连 URL 解析默认值一起动），只把它登记出来。
    pub const fn default_schema(self) -> Option<&'static str> {
        match self {
            DatabaseType::Postgresql => Some("public"),
            DatabaseType::Mysql => None,
            DatabaseType::Gbase8a => None,
        }
    }

    /// 连接串协议名（导出 URL 用）。
    pub const fn url_scheme(self) -> &'static str {
        match self {
            DatabaseType::Gbase8a => "gbase",
            _ => "postgres",
        }
    }
}

impl fmt::Display for DatabaseType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.raw_value())
    }
}

/// SSL 模式。`raw_value()` 与对侧逐字相同（含 `verify-ca` / `verify-full` 的连字符写法）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SslMode {
    Disable,
    Allow,
    Prefer,
    Require,
    #[serde(rename = "verify-ca")]
    VerifyCa,
    #[serde(rename = "verify-full")]
    VerifyFull,
}

impl SslMode {
    pub const fn raw_value(self) -> &'static str {
        match self {
            SslMode::Disable => "disable",
            SslMode::Allow => "allow",
            SslMode::Prefer => "prefer",
            SslMode::Require => "require",
            SslMode::VerifyCa => "verify-ca",
            SslMode::VerifyFull => "verify-full",
        }
    }

    /// 由字面量解析（**不分大小写**：URL 里 `sslmode=REQUIRE` 是合法的）。
    pub fn from_raw(value: &str) -> Option<Self> {
        match value.to_ascii_lowercase().as_str() {
            "disable" => Some(SslMode::Disable),
            "allow" => Some(SslMode::Allow),
            "prefer" => Some(SslMode::Prefer),
            "require" => Some(SslMode::Require),
            "verify-ca" => Some(SslMode::VerifyCa),
            "verify-full" => Some(SslMode::VerifyFull),
            _ => None,
        }
    }

    pub const fn display_key(self) -> &'static str {
        match self {
            SslMode::Disable => "ssl.disable",
            SslMode::Allow => "ssl.allow",
            SslMode::Prefer => "ssl.prefer",
            SslMode::Require => "ssl.require",
            SslMode::VerifyCa => "ssl.verifyCA",
            SslMode::VerifyFull => "ssl.verifyFull",
        }
    }
}

impl fmt::Display for SslMode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.raw_value())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn raw_values_are_the_persisted_literals() {
        // 这些字面量进了配置文件与跨端交换面 ⇒ 改动等于破坏兼容，用例就是它的锁
        assert_eq!(DatabaseType::Postgresql.raw_value(), "postgresql");
        assert_eq!(DatabaseType::Mysql.raw_value(), "mysql");
        assert_eq!(DatabaseType::Gbase8a.raw_value(), "gbase8a");
        assert_eq!(SslMode::VerifyCa.raw_value(), "verify-ca");
        assert_eq!(SslMode::VerifyFull.raw_value(), "verify-full");
    }

    #[test]
    fn parsing_accepts_aliases_and_is_case_insensitive() {
        assert_eq!(
            DatabaseType::from_raw("postgres"),
            Some(DatabaseType::Postgresql)
        );
        assert_eq!(
            DatabaseType::from_raw("PostgreSQL"),
            Some(DatabaseType::Postgresql)
        );
        assert_eq!(DatabaseType::from_raw("gbase"), Some(DatabaseType::Gbase8a));
        assert_eq!(DatabaseType::from_raw("oracle"), None);

        assert_eq!(SslMode::from_raw("REQUIRE"), Some(SslMode::Require));
        assert_eq!(SslMode::from_raw("verify-full"), Some(SslMode::VerifyFull));
        assert_eq!(SslMode::from_raw("verify_full"), None);
        assert_eq!(SslMode::from_raw("maybe"), None);
    }

    #[test]
    fn defaults_live_on_the_type_not_in_the_form() {
        assert_eq!(DatabaseType::Postgresql.default_port(), 5432);
        assert_eq!(DatabaseType::Mysql.default_port(), 3306);
        assert_eq!(DatabaseType::Gbase8a.default_port(), 5258);
        for t in [
            DatabaseType::Postgresql,
            DatabaseType::Mysql,
            DatabaseType::Gbase8a,
        ] {
            assert_eq!(t.default_ssl_mode(), SslMode::Prefer);
            assert!(!t.display_key().is_empty());
        }
        assert_eq!(DatabaseType::Gbase8a.url_scheme(), "gbase");
        assert_eq!(DatabaseType::Mysql.url_scheme(), "postgres");
        // 类型联动的第三项：默认 schema（`None` = 这个方言没有 schema 层）
        assert_eq!(DatabaseType::Postgresql.default_schema(), Some("public"));
        assert_eq!(DatabaseType::Mysql.default_schema(), None);
        assert_eq!(DatabaseType::Gbase8a.default_schema(), None);
    }

    #[test]
    fn every_ssl_mode_round_trips() {
        for mode in [
            SslMode::Disable,
            SslMode::Allow,
            SslMode::Prefer,
            SslMode::Require,
            SslMode::VerifyCa,
            SslMode::VerifyFull,
        ] {
            assert_eq!(SslMode::from_raw(mode.raw_value()), Some(mode));
            assert!(!mode.display_key().is_empty());
        }
    }
}
