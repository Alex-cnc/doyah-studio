//! **智能体配置**（`FR-AI-01` 的配置面）—— 落盘模型 + 输入合法性 + 把闸门裁决摊成一条可显示的清单。
//!
//! 契约等价物：macOS 侧 `Core/AgentConfiguration.swift`。
//!
//! ## 这一层管什么、不管什么
//!
//! - **不管裁决**：能不能外发只由 [`crate::agent::Gate`] 判（总开关 → 缺端点 / 缺模型 / 远端缺密钥）。
//!   本文件**不写第二份闸门** —— 那是最容易分叉的一类重复（改一处忘一处，界面说一套、实发另一套）。
//!   本文件把裁决**转成可显示的清单**，并在闸门放行之后**再补一道输入合法性**（端点必须是 `http(s)://`
//!   且有主机名、超时 1~600 秒、每小时上限 1~100000）。为什么补这一道：闸门只判「空不空」，
//!   而填了 `ftp://…` 或 `api.x.com/v1` 的配置闸门会放行，真发请求时才炸 —— 那时错误离用户已经很远。
//! - **不管密钥**：配置结构里**结构上没有密钥字段**（密钥由外壳写进系统凭据存储）。这条不靠「记得别写」，
//!   靠类型上没有那个字段 + 一条序列化白名单单测钉住。
//!
//! ## 口径
//!
//! - 落盘键名与取值都是契约（`enabled` / `endpoint` / `model` / `timeoutSecs` / `hourlyLimit` / `preset`）；
//! - 未知字段**不报错**（手改过的文件、版本降级读新值，都不该让设置面板起不来）；
//! - 缺失字段取默认值，**默认 = 关**（新装用户不会被静默打开外发）。

use serde::{Deserialize, Serialize};

use crate::agent::{Endpoint, Gate, GateProblem, GateVerdict};

/// 智能体配置（**结构上没有密钥字段**）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentConfiguration {
    /// 总开关。**默认关**：没配置过 = 不外发。
    #[serde(default)]
    pub enabled: bool,
    /// OpenAI 兼容端点（如 `https://api.deepseek.com/v1`）。
    #[serde(default)]
    pub endpoint: String,
    /// 模型名（如 `deepseek-chat`）。
    #[serde(default)]
    pub model: String,
    /// 单次请求超时（秒）。
    #[serde(default = "default_timeout")]
    pub timeout_secs: u32,
    /// 每小时请求上限（配额的第一道闸）。
    #[serde(default = "default_hourly_limit")]
    pub hourly_limit: u32,
    /// 选中的内置预设标签（`custom` = 自填）。**只作界面回显**，不参与裁决。
    #[serde(default = "default_preset")]
    pub preset: String,
}

fn default_timeout() -> u32 {
    60
}

fn default_hourly_limit() -> u32 {
    60
}

fn default_preset() -> String {
    "custom".to_string()
}

impl Default for AgentConfiguration {
    fn default() -> Self {
        Self {
            enabled: false,
            endpoint: String::new(),
            model: String::new(),
            timeout_secs: default_timeout(),
            hourly_limit: default_hourly_limit(),
            preset: default_preset(),
        }
    }
}

/// 端点的作用域 —— 决定「缺不缺密钥」。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum EndpointScope {
    /// 本机服务（Ollama / vLLM / 本地网关）：**不收 Authorization**，不算缺密钥。
    Local,
    /// 远端服务：缺密钥 ⇒ 不放行。
    Remote,
}

/// 闸门的三种状态（界面按它分三段文案）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum GateState {
    /// 总开关关着：**不会向任何模型服务发送数据**。
    Disabled,
    /// 有缺项 / 填错了：逐条点名。
    Missing,
    /// 放行。
    Ready,
}

/// 一条「不放行的理由」（短码给界面查语言表，`detail` 给具体越界值）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", tag = "code", content = "detail")]
pub enum AgentIssue {
    /// 端点为空。
    EndpointMissing,
    /// 模型名为空。
    ModelMissing,
    /// 远端端点缺密钥。
    KeyMissing,
    /// 端点不是 `http://` / `https://`（detail = 原值）。
    EndpointScheme(String),
    /// 端点解析不出主机名。
    EndpointHost,
    /// 超时越界（detail = 原值秒数）。
    TimeoutOutOfRange(u32),
    /// 每小时上限越界（detail = 原值）。
    HourlyLimitOutOfRange(u32),
}

impl AgentIssue {
    /// 稳定短码（**键名即契约**：界面按它查语言表，领域层不写死文案）。
    pub const fn code(&self) -> &'static str {
        match self {
            AgentIssue::EndpointMissing => "endpointMissing",
            AgentIssue::ModelMissing => "modelMissing",
            AgentIssue::KeyMissing => "keyMissing",
            AgentIssue::EndpointScheme(_) => "endpointScheme",
            AgentIssue::EndpointHost => "endpointHost",
            AgentIssue::TimeoutOutOfRange(_) => "timeoutOutOfRange",
            AgentIssue::HourlyLimitOutOfRange(_) => "hourlyLimitOutOfRange",
        }
    }
}

impl From<GateProblem> for AgentIssue {
    fn from(problem: GateProblem) -> Self {
        match problem {
            GateProblem::EndpointMissing => AgentIssue::EndpointMissing,
            GateProblem::ModelMissing => AgentIssue::ModelMissing,
            GateProblem::KeyMissing => AgentIssue::KeyMissing,
        }
    }
}

/// 闸门裁决的**可显示形态**（外壳原样回给界面；界面不自己算一遍）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentGateReport {
    /// 三段状态。
    pub state: GateState,
    /// 端点作用域（端点不合法时按远端算 —— 宁可多要一道密钥，也不少要）。
    pub scope: EndpointScope,
    /// 放行时会用到的模型名（未放行时为空串，不编造）。
    pub model: String,
    /// 不放行的理由（**顺序稳定**：闸门那几条在前，输入合法性在后）。
    pub issues: Vec<AgentIssue>,
}

/// 输入合法性（闸门不管的那几条）。
pub fn field_issues(config: &AgentConfiguration) -> Vec<AgentIssue> {
    let mut issues = Vec::new();
    let endpoint = config.endpoint.trim();
    if !endpoint.is_empty() && !(endpoint.starts_with("http://") || endpoint.starts_with("https://")) {
        // 不给「自动补 https://」的假回退：填错的东西要当场说，不能猜用户想连哪儿。
        issues.push(AgentIssue::EndpointScheme(endpoint.to_string()));
    } else if !endpoint.is_empty() && host_of(endpoint).is_none() {
        issues.push(AgentIssue::EndpointHost);
    }
    if config.timeout_secs == 0 || config.timeout_secs > 600 {
        issues.push(AgentIssue::TimeoutOutOfRange(config.timeout_secs));
    }
    if config.hourly_limit == 0 || config.hourly_limit > 100_000 {
        issues.push(AgentIssue::HourlyLimitOutOfRange(config.hourly_limit));
    }
    issues
}

/// 拼一个闸门（**唯一裁决的入口**：`crate::agent::Gate`）。
pub fn gate_of(config: &AgentConfiguration, key_present: bool) -> Gate {
    let endpoint = match endpoint_scope(&config.endpoint) {
        Some(EndpointScope::Local) => Endpoint::Local,
        _ => Endpoint::Remote,
    };
    Gate {
        enabled: config.enabled,
        endpoint,
        base_url: config.endpoint.trim().to_string(),
        model: config.model.trim().to_string(),
        has_key: key_present,
    }
}

/// 裁决并摊成可显示清单。
pub fn evaluate(config: &AgentConfiguration, key_present: bool) -> AgentGateReport {
    let scope = endpoint_scope(&config.endpoint).unwrap_or(EndpointScope::Remote);
    match gate_of(config, key_present).check() {
        GateVerdict::ClosedBySwitch => AgentGateReport {
            state: GateState::Disabled,
            scope,
            model: String::new(),
            issues: Vec::new(),
        },
        GateVerdict::ClosedByConfig { problems } => {
            let mut issues: Vec<AgentIssue> = problems.into_iter().map(AgentIssue::from).collect();
            issues.extend(field_issues(config));
            AgentGateReport {
                state: GateState::Missing,
                scope,
                model: String::new(),
                issues,
            }
        }
        GateVerdict::Open => {
            let issues = field_issues(config);
            if issues.is_empty() {
                AgentGateReport {
                    state: GateState::Ready,
                    scope,
                    model: config.model.trim().to_string(),
                    issues,
                }
            } else {
                AgentGateReport {
                    state: GateState::Missing,
                    scope,
                    model: String::new(),
                    issues,
                }
            }
        }
    }
}

/// 端点作用域；端点不合法 ⇒ `None`（不猜）。
pub fn endpoint_scope(endpoint: &str) -> Option<EndpointScope> {
    let host = host_of(endpoint.trim())?;
    let host = host.to_ascii_lowercase();
    let local = host == "localhost"
        || host == "127.0.0.1"
        || host == "::1"
        || host == "0.0.0.0"
        || host.ends_with(".local");
    Some(if local {
        EndpointScope::Local
    } else {
        EndpointScope::Remote
    })
}

/// 从 `scheme://host[:port]/path` 里取主机名（不引 url crate：这里只要主机那一段）。
fn host_of(endpoint: &str) -> Option<&str> {
    let rest = endpoint
        .strip_prefix("http://")
        .or_else(|| endpoint.strip_prefix("https://"))?;
    let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let authority = &rest[..end];
    if authority.is_empty() {
        return None;
    }
    // 去掉 userinfo 与端口；IPv6 字面量按方括号切（`[::1]:8080` 里的冒号不是端口分隔符）。
    let after_userinfo = match authority.rfind('@') {
        Some(idx) => &authority[idx + 1..],
        None => authority,
    };
    let host = if let Some(stripped) = after_userinfo.strip_prefix('[') {
        match stripped.find(']') {
            Some(idx) => &stripped[..idx],
            None => return None,
        }
    } else {
        match after_userinfo.find(':') {
            Some(idx) => &after_userinfo[..idx],
            None => after_userinfo,
        }
    };
    if host.is_empty() {
        None
    } else {
        Some(host)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn filled() -> AgentConfiguration {
        AgentConfiguration {
            enabled: true,
            endpoint: "https://api.deepseek.com/v1".to_string(),
            model: "deepseek-chat".to_string(),
            ..Default::default()
        }
    }

    fn codes(report: &AgentGateReport) -> Vec<&'static str> {
        report.issues.iter().map(AgentIssue::code).collect()
    }

    #[test]
    fn a_fresh_install_is_disabled_and_sends_nothing() {
        let config = AgentConfiguration::default();
        assert!(!config.enabled);
        let report = evaluate(&config, false);
        assert_eq!(report.state, GateState::Disabled);
        assert!(report.issues.is_empty());
        assert_eq!(report.model, "");
    }

    #[test]
    fn the_switch_off_wins_even_when_everything_else_is_filled_in() {
        // 闸门顺序是安全属性：端点 / 模型 / 密钥齐也挡在总开关后面。
        let mut config = filled();
        config.enabled = false;
        assert_eq!(evaluate(&config, true).state, GateState::Disabled);
    }

    #[test]
    fn a_remote_endpoint_without_a_key_names_the_missing_key() {
        let report = evaluate(&filled(), false);
        assert_eq!(report.state, GateState::Missing);
        assert_eq!(codes(&report), vec!["keyMissing"]);
        assert_eq!(report.scope, EndpointScope::Remote);
    }

    #[test]
    fn a_local_endpoint_needs_no_key() {
        let mut config = filled();
        config.endpoint = "http://localhost:11434/v1".to_string();
        config.model = "llama3".to_string();
        let report = evaluate(&config, false);
        assert_eq!(report.state, GateState::Ready);
        assert_eq!(report.model, "llama3");
        assert_eq!(report.scope, EndpointScope::Local);
    }

    #[test]
    fn a_remote_endpoint_with_a_key_is_ready() {
        let report = evaluate(&filled(), true);
        assert_eq!(report.state, GateState::Ready);
        assert_eq!(report.model, "deepseek-chat");
    }

    #[test]
    fn an_endpoint_without_a_scheme_is_refused_instead_of_guessed() {
        let mut config = filled();
        config.endpoint = "api.deepseek.com/v1".to_string();
        let report = evaluate(&config, true);
        assert_eq!(report.state, GateState::Missing);
        assert_eq!(
            report.issues,
            vec![AgentIssue::EndpointScheme("api.deepseek.com/v1".to_string())]
        );
    }

    #[test]
    fn an_endpoint_with_no_host_is_refused() {
        let mut config = filled();
        config.endpoint = "https:///v1".to_string();
        let report = evaluate(&config, true);
        assert_eq!(report.issues, vec![AgentIssue::EndpointHost]);
    }

    #[test]
    fn empty_fields_and_out_of_range_numbers_are_each_named() {
        let config = AgentConfiguration {
            enabled: true,
            endpoint: String::new(),
            model: "  ".to_string(),
            timeout_secs: 0,
            hourly_limit: 100_001,
            ..Default::default()
        };
        let report = evaluate(&config, true);
        assert_eq!(
            codes(&report),
            vec![
                "endpointMissing",
                "modelMissing",
                "timeoutOutOfRange",
                "hourlyLimitOutOfRange"
            ]
        );
    }

    #[test]
    fn numbers_out_of_range_block_a_config_the_gate_would_have_passed() {
        // 闸门只看「空不空」：一个 0 秒超时的远端配置会被闸门放行 —— 这一道必须拦住它。
        let mut config = filled();
        config.timeout_secs = 0;
        let report = evaluate(&config, true);
        assert_eq!(report.state, GateState::Missing);
        assert_eq!(codes(&report), vec!["timeoutOutOfRange"]);
    }

    #[test]
    fn the_configuration_has_no_place_to_keep_a_key() {
        // 结构保证 + 序列化白名单：密钥一旦能有字段，它就会被写进配置文件。
        let json = serde_json::to_value(AgentConfiguration::default()).expect("serialize");
        let object = json.as_object().expect("object");
        let mut keys: Vec<&str> = object.keys().map(|k| k.as_str()).collect();
        keys.sort_unstable();
        assert_eq!(
            keys,
            vec![
                "enabled",
                "endpoint",
                "hourlyLimit",
                "model",
                "preset",
                "timeoutSecs"
            ]
        );
        let text = serde_json::to_string(&AgentConfiguration::default()).expect("text");
        for forbidden in ["key", "secret", "token", "password", "authorization"] {
            assert!(
                !text.to_ascii_lowercase().contains(forbidden),
                "配置文件里不该出现 {forbidden}：{text}"
            );
        }
    }

    #[test]
    fn a_hand_edited_file_with_unknown_fields_still_loads() {
        let text = r#"{"enabled":true,"endpoint":"http://localhost:11434/v1","model":"llama3",
                       "futureField":{"a":1},"preset":"ollama"}"#;
        let config: AgentConfiguration = serde_json::from_str(text).expect("decode");
        assert!(config.enabled);
        assert_eq!(config.preset, "ollama");
        assert_eq!(config.timeout_secs, default_timeout());
        assert_eq!(evaluate(&config, false).state, GateState::Ready);
    }

    #[test]
    fn scope_handles_ports_userinfo_and_ipv6_literals() {
        assert_eq!(
            endpoint_scope("http://user:pw@127.0.0.1:8080/v1"),
            Some(EndpointScope::Local)
        );
        assert_eq!(
            endpoint_scope("http://[::1]:11434/v1"),
            Some(EndpointScope::Local)
        );
        assert_eq!(
            endpoint_scope("https://example.com:443/v1"),
            Some(EndpointScope::Remote)
        );
        assert_eq!(endpoint_scope("nonsense"), None);
    }
}
