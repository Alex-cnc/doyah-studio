//! 连接串的导入 / 导出（FR-CONN-19；契约等价物：macOS 侧 `Core/ConnectionURL.swift`）
//!
//! 两条纪律（照抄契约）：
//! 1. **口令不进配置包**（需求原文点名 DR-02）：导出的 URL **不含口令**；导入时 URL 里若带了口令，
//!    只交给调用方**本次**用，由它放进凭据存储，**不写进配置** —— 但会如实告知"这里有一个口令"。
//! 2. **解析失败要说清哪里不对**，不返回一个字段半空的配置：半个配置比没有配置更难查。

use crate::config::ConnectionConfig;
use crate::db_type::{DatabaseType, SslMode};

/// 解析错误（每一档都能直接变成给用户看的一句话）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UrlParseError {
    /// 空串。
    Empty,
    /// 协议不认识。
    UnsupportedScheme(String),
    /// 缺主机名。
    MissingHost,
    /// 缺库名（URL 的路径部分）。
    MissingDatabase,
    /// 端口不是数字。
    InvalidPort(String),
    /// 百分号编码不合法。
    InvalidPercentEncoding(String),
    /// 裸 IPv6（`::1`）—— URL 里必须加方括号。
    InvalidIpv6Host(String),
}

impl std::fmt::Display for UrlParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            UrlParseError::Empty => write!(f, "URL 是空的"),
            UrlParseError::UnsupportedScheme(s) => {
                write!(f, "不支持的协议：{s}（支持 postgres / postgresql，以及 gbase）")
            }
            UrlParseError::MissingHost => write!(f, "缺少主机名"),
            UrlParseError::MissingDatabase => write!(f, "缺少数据库名（URL 里的路径部分）"),
            UrlParseError::InvalidPort(t) => write!(f, "端口不是数字：{t}"),
            UrlParseError::InvalidPercentEncoding(t) => write!(f, "百分号编码不合法：{t}"),
            UrlParseError::InvalidIpv6Host(t) => write!(f, "IPv6 主机要加方括号：[{t}]"),
        }
    }
}

impl std::error::Error for UrlParseError {}

/// 解析结果：一份配置 + **可选的口令**（口令不进配置）+ 不认识的查询参数（如实列出）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImportedConnection {
    pub configuration: ConnectionConfig,
    /// URL 里带的口令（若有）。调用方负责放进凭据存储。
    pub password: Option<String>,
    /// 原始 URL 里出现过但本侧不认的查询参数（**不静默丢**）。
    pub ignored_parameters: Vec<String>,
}

/// 「从 URL 导入」并进用户已经填了一半的表单时的两条合并规则（FR-CONN-19）。
///
/// 为什么抽成纯函数：这两条恰恰是"做错了也没人立刻发现"的地方 —— 覆盖掉用户手写的连接名、
/// 把"URL 里没写口令"当成"把口令清空"，都属于"导入一下，我填的东西没了"。
pub struct FormMerge;

impl FormMerge {
    /// 连接名：用户写了就**保留用户写的**；空着才采用 URL 推断出的名字。
    pub fn resolved_name(current: &str, imported: &str) -> String {
        if current.trim().is_empty() {
            imported.to_string()
        } else {
            current.to_string()
        }
    }

    /// 口令：URL 里带了才覆盖；没带就保持用户已输入的（**不静默清空**）。
    pub fn resolved_password(current: &str, imported: Option<&str>) -> String {
        match imported {
            Some(v) => v.to_string(),
            None => current.to_string(),
        }
    }
}

/// 解析连接串。
///
/// - `name`：连接名；不给就用「主机/库」拼一个可读的默认名。
/// - `id`：配置标识（由调用方给，落盘后不再变）。
pub fn parse(
    raw: &str,
    name: Option<&str>,
    id: &str,
) -> Result<ImportedConnection, UrlParseError> {
    let text = raw.trim();
    if text.is_empty() {
        return Err(UrlParseError::Empty);
    }
    let Some(scheme_end) = text.find("://") else {
        return Err(UrlParseError::UnsupportedScheme(text.to_string()));
    };
    let scheme = text[..scheme_end].to_ascii_lowercase();
    let db_type = match scheme.as_str() {
        "postgres" | "postgresql" => DatabaseType::Postgresql,
        "gbase" | "gbase8a" => DatabaseType::Gbase8a,
        other => return Err(UrlParseError::UnsupportedScheme(other.to_string())),
    };

    let mut remainder = &text[scheme_end + 3..];

    // fragment 先摘（`#` 之后全丢），再摘查询串 —— 顺序不能反：
    // 先摘查询会把 fragment 留在 remainder 里，于是 `?a=b#frag` 会把 `a=b#frag` 整段又当参数解析一遍；
    // 那一步会把已经认出来的 `sslmode` **覆盖掉**（临时目录真跑抓到的缺陷，用例已锁住）。
    if let Some(h) = remainder.find('#') {
        remainder = &remainder[..h];
    }

    // 查询串摘掉（它不影响主机 / 库的解析）
    let mut ssl_from_query: Option<SslMode> = None;
    let mut ignored: Vec<String> = Vec::new();
    if let Some(q) = remainder.find('?') {
        let query = &remainder[q + 1..];
        remainder = &remainder[..q];
        for pair in query.split('&') {
            match pair.split_once('=') {
                Some((k, v)) if k.eq_ignore_ascii_case("sslmode") => {
                    if let Some(mode) = SslMode::from_raw(v) {
                        ssl_from_query = Some(mode);
                    } else {
                        // 认不出的取值**如实列出来**，不静默取默认
                        ignored.push(pair.to_string());
                    }
                }
                _ => ignored.push(pair.to_string()),
            }
        }
    }

    // 凭据段：**最后一个 `@`** 是分隔符（口令里可以出现 `@`）
    let mut user: Option<String> = None;
    let mut password: Option<String> = None;
    if let Some(at) = remainder.rfind('@') {
        let credentials = &remainder[..at];
        remainder = &remainder[at + 1..];
        let (raw_user, raw_password) = match credentials.split_once(':') {
            Some((u, p)) => (u, Some(p)),
            None => (credentials, None),
        };
        if !raw_user.is_empty() {
            user = Some(
                percent_decode(raw_user)
                    .ok_or_else(|| UrlParseError::InvalidPercentEncoding(raw_user.to_string()))?,
            );
        }
        if let Some(p) = raw_password {
            password = Some(
                percent_decode(p)
                    .ok_or_else(|| UrlParseError::InvalidPercentEncoding(p.to_string()))?,
            );
        }
    }

    // 主机 / 端口 / 库
    let (host_part, database_part) = match remainder.find('/') {
        Some(slash) => (&remainder[..slash], &remainder[slash + 1..]),
        None => (remainder, ""),
    };
    if host_part.is_empty() {
        return Err(UrlParseError::MissingHost);
    }
    if database_part.is_empty() {
        return Err(UrlParseError::MissingDatabase);
    }
    let database = percent_decode(database_part)
        .ok_or_else(|| UrlParseError::InvalidPercentEncoding(database_part.to_string()))?;

    let mut host = host_part;
    let mut port = db_type.default_port();
    if let Some(rest) = host_part.strip_prefix('[') {
        // IPv6：`[::1]:5432`
        let Some(close) = rest.find(']') else {
            return Err(UrlParseError::MissingHost);
        };
        host = &rest[..close];
        let tail = &rest[close + 1..];
        if let Some(port_text) = tail.strip_prefix(':') {
            port = port_text
                .parse::<u16>()
                .map_err(|_| UrlParseError::InvalidPort(port_text.to_string()))?;
        }
    } else if host_part.matches(':').count() > 1 {
        // 裸 IPv6 必须加方括号：按"最后一个冒号是端口"去切会把 `::1` 切成 host `:`（实测如此）
        return Err(UrlParseError::InvalidIpv6Host(host_part.to_string()));
    } else if let Some(colon) = host_part.rfind(':') {
        host = &host_part[..colon];
        let port_text = &host_part[colon + 1..];
        port = port_text
            .parse::<u16>()
            .map_err(|_| UrlParseError::InvalidPort(port_text.to_string()))?;
    }
    if host.is_empty() {
        return Err(UrlParseError::MissingHost);
    }

    let mut configuration = ConnectionConfig::new(id, name.unwrap_or(&format!("{host}/{database}")), db_type);
    configuration.host = host.to_string();
    configuration.port = port;
    configuration.database = database;
    configuration.username = user.unwrap_or_default();
    configuration.ssl_mode = ssl_from_query.unwrap_or_else(|| db_type.default_ssl_mode());

    ignored.sort();
    Ok(ImportedConnection {
        configuration,
        password,
        ignored_parameters: ignored,
    })
}

/// 导出成 URL。**不含口令**（需求原文 + DR-02）。
pub fn url_for(configuration: &ConnectionConfig) -> String {
    let mut text = format!("{}://", configuration.db_type.url_scheme());
    if !configuration.username.is_empty() {
        text.push_str(&percent_encode(&configuration.username));
        text.push('@');
    }
    if configuration.host.contains(':') {
        text.push('[');
        text.push_str(&configuration.host);
        text.push(']');
    } else {
        text.push_str(&configuration.host);
    }
    text.push_str(&format!(":{}", configuration.port));
    text.push('/');
    text.push_str(&percent_encode(&configuration.database));
    text.push_str(&format!("?sslmode={}", configuration.ssl_mode.raw_value()));
    text
}

/// 只对**会破坏 URL 结构**的字符编码（`@ : / ? # %` 与空白、控制字符）。
pub fn percent_encode(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for byte in text.as_bytes() {
        let c = *byte as char;
        let keep = c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | '~');
        if keep {
            out.push(c);
        } else {
            out.push_str(&format!("%{byte:02X}"));
        }
    }
    out
}

/// 百分号解码。**遇到不合法的编码返回 `None`**（不猜、不吞）。
pub fn percent_decode(text: &str) -> Option<String> {
    let bytes = text.as_bytes();
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            if i + 2 >= bytes.len() {
                return None;
            }
            let hi = (bytes[i + 1] as char).to_digit(16)?;
            let lo = (bytes[i + 2] as char).to_digit(16)?;
            out.push((hi * 16 + lo) as u8);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parsed(raw: &str) -> ImportedConnection {
        parse(raw, None, "id-1").expect("应当解析成功")
    }

    #[test]
    fn parses_a_plain_postgres_url() {
        let r = parsed("postgres://bob@10.0.0.5:6000/analytics");
        assert_eq!(r.configuration.db_type, DatabaseType::Postgresql);
        assert_eq!(r.configuration.host, "10.0.0.5");
        assert_eq!(r.configuration.port, 6000);
        assert_eq!(r.configuration.database, "analytics");
        assert_eq!(r.configuration.username, "bob");
        assert_eq!(r.password, None);
        assert!(r.ignored_parameters.is_empty());
        // 没给名字 ⇒ 用「主机/库」拼
        assert_eq!(r.configuration.name, "10.0.0.5/analytics");
    }

    #[test]
    fn postgresql_is_the_same_protocol_and_gbase_has_its_own() {
        assert_eq!(
            parsed("postgresql://bob@h/db").configuration.db_type,
            DatabaseType::Postgresql
        );
        let g = parsed("gbase://bob@h/db");
        assert_eq!(g.configuration.db_type, DatabaseType::Gbase8a);
        assert_eq!(g.configuration.port, 5258, "没写端口 ⇒ 用类型默认端口");
        assert_eq!(g.configuration.ssl_mode, SslMode::Prefer);
    }

    #[test]
    fn password_comes_back_to_the_caller_and_never_into_the_config() {
        let r = parsed("postgres://bob:ZXvmax_2017@h:5432/db");
        assert_eq!(r.password.as_deref(), Some("ZXvmax_2017"));
        // 配置里没有口令这一项 —— 导出的 URL 也不含它
        let exported = url_for(&r.configuration);
        assert!(!exported.contains("ZXvmax_2017"), "{exported}");
        assert_eq!(exported, "postgres://bob@h:5432/db?sslmode=prefer");
        assert_eq!(r.configuration.username, "bob");
    }

    #[test]
    fn an_at_sign_inside_the_password_does_not_break_the_split() {
        let r = parsed("postgres://bob:p%40ss@h/db");
        assert_eq!(r.password.as_deref(), Some("p@ss"));
        assert_eq!(r.configuration.username, "bob");
        assert_eq!(r.configuration.host, "h");
    }

    #[test]
    fn percent_encoded_credentials_and_database_names_round_trip() {
        let r = parsed("postgres://b%20ob:p%40ss@h/%E4%B8%AD%E6%96%87%E5%BA%93");
        assert_eq!(r.configuration.username, "b ob");
        assert_eq!(r.configuration.database, "中文库");
        assert_eq!(r.password.as_deref(), Some("p@ss"));
        let exported = url_for(&r.configuration);
        assert_eq!(exported, "postgres://b%20ob@h:5432/%E4%B8%AD%E6%96%87%E5%BA%93?sslmode=prefer");
        let again = parsed(&exported);
        assert_eq!(again.configuration.database, "中文库");
        assert_eq!(again.configuration.username, "b ob");
        assert_eq!(again.password, None, "导出不含口令 ⇒ 再导入也没有");
    }

    #[test]
    fn sslmode_is_read_case_insensitively_and_unknown_parameters_are_listed() {
        let r = parsed("postgres://bob@h/db?sslmode=VERIFY-FULL&application_name=x&sslmode2=y");
        assert_eq!(r.configuration.ssl_mode, SslMode::VerifyFull);
        assert_eq!(
            r.ignored_parameters,
            vec!["application_name=x".to_string(), "sslmode2=y".to_string()]
        );
        // 认不出的 sslmode 取值也要如实列出来，不静默取默认
        let bad = parsed("postgres://bob@h/db?sslmode=sortof");
        assert_eq!(bad.configuration.ssl_mode, SslMode::Prefer);
        assert_eq!(bad.ignored_parameters, vec!["sslmode=sortof".to_string()]);
    }

    #[test]
    fn fragment_is_ignored_and_cannot_overwrite_what_the_query_already_said() {
        let r = parsed("postgres://bob@h/db?sslmode=require#frag");
        assert_eq!(r.configuration.database, "db");
        assert_eq!(
            r.configuration.ssl_mode,
            SslMode::Require,
            "带 fragment 时 sslmode 被覆盖过（早期缺陷）"
        );
        assert!(r.ignored_parameters.is_empty(), "{:?}", r.ignored_parameters);

        // 两个 sslmode：后者胜出，且都算"认识"（不进忽略清单）
        let twice = parsed("postgres://bob@h/db?sslmode=require&sslmode=disable");
        assert_eq!(twice.configuration.ssl_mode, SslMode::Disable);
        assert!(twice.ignored_parameters.is_empty(), "{:?}", twice.ignored_parameters);

        let v6 = parsed("postgres://bob@[::1]:6000/db");
        assert_eq!(v6.configuration.host, "::1");
        assert_eq!(v6.configuration.port, 6000);
        assert_eq!(url_for(&v6.configuration), "postgres://bob@[::1]:6000/db?sslmode=prefer");

        // 裸 IPv6 明确拒绝（按"最后一个冒号是端口"切会把它切成 host `:`）
        assert_eq!(
            parse("postgres://bob@::1/db", None, "id").unwrap_err(),
            UrlParseError::InvalidIpv6Host("::1".to_string())
        );
    }

    #[test]
    fn every_failure_says_which_one_it_is() {
        assert_eq!(parse("   ", None, "id").unwrap_err(), UrlParseError::Empty);
        assert_eq!(
            parse("mysql://bob@h/db", None, "id").unwrap_err(),
            UrlParseError::UnsupportedScheme("mysql".to_string())
        );
        assert_eq!(
            parse("postgres://bob@/db", None, "id").unwrap_err(),
            UrlParseError::MissingHost
        );
        assert_eq!(
            parse("postgres://bob@h", None, "id").unwrap_err(),
            UrlParseError::MissingDatabase
        );
        assert_eq!(
            parse("postgres://bob@h:abc/db", None, "id").unwrap_err(),
            UrlParseError::InvalidPort("abc".to_string())
        );
        assert_eq!(
            parse("postgres://bo%2@h/db", None, "id").unwrap_err(),
            UrlParseError::InvalidPercentEncoding("bo%2".to_string())
        );
        // 连 :// 都没有 ⇒ 整串当协议名报出来（不猜）
        assert!(matches!(
            parse("not-a-url", None, "id").unwrap_err(),
            UrlParseError::UnsupportedScheme(_)
        ));
    }

    #[test]
    fn given_name_wins() {
        let r = parse("postgres://bob@h/db", Some("线上库"), "id").unwrap();
        assert_eq!(r.configuration.name, "线上库");
    }

    #[test]
    fn form_merge_never_clobbers_what_the_user_typed() {
        // 用户写了名字 ⇒ 保留用户的
        assert_eq!(FormMerge::resolved_name("我的库", "h/db"), "我的库");
        // 空着 ⇒ 采用导入的
        assert_eq!(FormMerge::resolved_name("   ", "h/db"), "h/db");
        // URL 没带口令 ⇒ 保留用户已输入的（不静默清空）
        assert_eq!(FormMerge::resolved_password("typed", None), "typed");
        // URL 带了 ⇒ 覆盖
        assert_eq!(FormMerge::resolved_password("typed", Some("from-url")), "from-url");
    }

    #[test]
    fn percent_helpers_reject_malformed_input() {
        assert_eq!(percent_decode("%E4%B8%AD"), Some("中".to_string()));
        assert_eq!(percent_decode("%4"), None);
        assert_eq!(percent_decode("%ZZ"), None);
        assert_eq!(percent_encode("a b"), "a%20b");
        assert_eq!(percent_encode("中文"), "%E4%B8%AD%E6%96%87");
    }
}
