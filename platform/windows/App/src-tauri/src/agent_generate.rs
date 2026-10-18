//! **自然语言 → SQL 的外发面**（`FR-AI-02` · Windows 侧表示层）
//!
//! 分层：请求装配 / 回包解析 / 「用到哪些表」全在领域层（`doyah_studio_db::agent_nl2sql`）；
//! 本文件只管三件事 —— **判放行、真发一次、把结果原样交回去**。
//!
//! 四条口径（每条都在下面有对应的代码形状）：
//! ① **关掉总开关就一条请求都发不出去**：`generate` 第一步取闸门裁决，非 `ready` 直接回
//!    [`GenerateReply::Blocked`] —— 连 HTTP 客户端都不建；
//! ② **密钥只进请求头**（`Authorization: Bearer …`），正文里没有它，错误信息里也不会带出来；
//! ③ **生成结果只回文本**：本文件**不调用任何执行入口**（`Db` 连接不在这里出现）——
//!    「永不自动执行」在形状上成立，不靠界面自觉；
//! ④ **每小时上限是真闸门**：放行后、建客户端前先记一次账（`Db::agent_quota` 的滑窗台账），
//!    满了就回 [`GenerateReply::Throttled`] —— **一条请求都不发**；台账写不进去也**不发**
//!    （否则上限会静默失效）。计的是「真发出去的请求」，含超时 / 报错的那一次。
//!
//! 契约等价物：macOS 侧 `App/Agent/AgentSqlGenerationService.swift`。

use std::time::{Duration, Instant};

use doyah_studio_db::agent_config::{evaluate, AgentGateReport, GateState};
use doyah_studio_db::agent_nl2sql::{build_request, parse_reply, TableBrief};
use doyah_studio_db::agent_quota::{now_secs, QuotaStatus};
use serde::Serialize;

use crate::agent_settings::AgentSettingsStore;
use crate::postgres::DbFailure;

/// 「先看要发什么」的结果：**不发请求**，只把将要外发的正文与放行状态摊出来。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GeneratePreview {
    /// 闸门裁决（唯一出处 = 领域层）。
    pub gate: AgentGateReport,
    /// 将要请求的完整地址（放行时才有意义；未放行也照实给出拼法，便于排查）。
    pub url: String,
    /// 将要发送的正文（= 用户消息原文；表名 / 列名 / 类型 / 问题，不含行数据、不含密钥）。
    pub human: String,
    /// 摘要里**真正列进去**的表数。
    pub table_count: usize,
    /// 因上限没列出去的表数（界面要如实说）。
    pub dropped: usize,
    /// 本小时的配额读数（**发之前**就能看到还剩几次 —— 否则用户只会在点下去之后撞墙）。
    pub quota: QuotaStatus,
}

/// 一次生成的结果（**只有文本**）。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GenerateOutcome {
    /// 生成的 SQL。
    pub sql: String,
    /// 模型的解释（代码块之外的文字）。
    pub explanation: String,
    /// 本次 SQL 里点到、且当前 schema 真有的表。
    pub tables_used: Vec<String>,
    /// 实际使用的模型名。
    pub model: String,
    /// 往返耗时（毫秒）。
    pub elapsed_ms: u64,
    /// 随请求外发的表数（用户可据此判断「我到底发了多少东西出去」）。
    pub table_count: usize,
    /// 发完这一次之后的配额读数（`used` 已含本次）。
    pub quota: QuotaStatus,
    /// 本片的已知缺口（**如实显示**，不让用户以为配额已经生效）。
    pub limitations: Vec<String>,
}

/// 生成请求的三种结局：被闸门挡住（零外发）、被配额挡住（零外发）、或者真的发了并解析成功。
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "status", rename_all = "camelCase")]
pub enum GenerateReply {
    /// 没放行：**一条请求都没发**。
    Blocked {
        /// 逐条理由（界面按短码查语言表）。
        gate: AgentGateReport,
    },
    /// 本小时配额已满：**一条请求都没发**（`retryAfterSecs` 告诉界面还要等多久）。
    Throttled {
        /// 满额时的读数（`limit` / `used` / `retry_after_secs`）。
        quota: QuotaStatus,
    },
    /// 放行并完成：结果只在这里，**没有被执行**。
    Generated(GenerateOutcome),
}

/// 本片的已知缺口（写进结果里，随界面显示）。
pub const LIMITATIONS: [&str; 2] = [
    "每小时上限按「真发出去的请求」计（含超时 / 报错的那一次）：防的是重试风暴，不是给云端对账单。",
    "生成结果不会自动执行；要留下就点结果区的「存成已保存查询」（存的是这段文本，编辑器内容不动）。",
];

/// 「先看要发什么」：装配正文 + 取裁决，**不建 HTTP 客户端、不发请求**。
pub fn preview(
    store: &AgentSettingsStore,
    question: &str,
    tables: &[TableBrief],
) -> Result<GeneratePreview, DbFailure> {
    let config = store.load()?;
    let gate = evaluate(&config, store.key_present());
    // 配额读数：预览就要能给「还剩几次」，否则用户只能点下去撞墙。
    let quota = store.load_quota().status(now_secs(), config.hourly_limit);
    match build_request(&config, question, tables) {
        Ok(outgoing) => Ok(GeneratePreview {
            gate,
            url: outgoing.url,
            human: outgoing.human,
            table_count: tables.len().min(doyah_studio_db::agent_nl2sql::MAX_TABLES),
            dropped: tables.len().saturating_sub(doyah_studio_db::agent_nl2sql::MAX_TABLES),
            quota,
        }),
        // 问题为空时也要能看「哪一步不让发」：给一份不带问题的正文，把原因交给 `gate` / 调用方。
        Err(err) => Err(DbFailure {
            message: err.to_string(),
            hint: "先写一句要查什么（比如「最近 7 天每天的订单数」）。".to_string(),
        }),
    }
}

/// 真发一次，只回文本。
pub fn generate(
    store: &AgentSettingsStore,
    question: &str,
    tables: &[TableBrief],
) -> Result<GenerateReply, DbFailure> {
    let config = store.load()?;
    let key_present = store.key_present();
    let gate = evaluate(&config, key_present);
    if gate.state != GateState::Ready {
        // 闸门不放行 ⇒ 零外发（连客户端都不建）。
        return Ok(GenerateReply::Blocked { gate });
    }
    let outgoing = build_request(&config, question, tables).map_err(|err| DbFailure {
        message: err.to_string(),
        hint: "先写一句要查什么（比如「最近 7 天每天的订单数」）。".to_string(),
    })?;

    // 配额：**装配之后再记**（问题为空这类参数错误不该白占一次额度），**建客户端之前**记
    // （记不上就不发 —— 否则每小时上限形同不存在）。
    let mut ledger = store.load_quota();
    let (admitted, quota) = ledger.admit(now_secs(), config.hourly_limit);
    if !admitted {
        // 满了：一条请求都不发。
        return Ok(GenerateReply::Throttled { quota });
    }
    store.save_quota(&ledger).map_err(|err| DbFailure {
        message: format!(
            "{} 这次没有发送：记不了账就不发，否则「每小时上限」等于没有。",
            err.message
        ),
        hint: err.hint,
    })?;

    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(config.timeout_secs as u64))
        // 不跟随重定向：端点被改写会把密钥带到别的主机上。
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(|err| DbFailure {
            message: format!("建 HTTP 客户端失败：{err}"),
            hint: "这属实现缺陷：请保留现场并报告。".to_string(),
        })?;

    let started = Instant::now();
    let mut request = client
        .post(&outgoing.url)
        .header(reqwest::header::CONTENT_TYPE, "application/json")
        .body(outgoing.body.clone());
    if let Some(secret) = store.key_secret() {
        request = request.header(reqwest::header::AUTHORIZATION, format!("Bearer {secret}"));
    }
    let response = request.send().map_err(|err| {
        let timeout = err.is_timeout();
        DbFailure {
            message: if timeout {
                format!(
                    "请求超时（{} 秒）：模型服务没有在时限内回话。",
                    config.timeout_secs
                )
            } else {
                format!("请求发不出去：{err}")
            },
            hint: if timeout {
                "把「单次请求超时」调大，或换一个更近的端点。".to_string()
            } else {
                "确认端点地址与网络（远端还需代理 / 防火墙放行）；本地端点的服务是否在跑。".to_string()
            },
        }
    })?;

    let status = response.status();
    let raw = response.text().map_err(|err| DbFailure {
        message: format!("回包读不出来：{err}"),
        hint: "重试一次；仍然不行就换端点。".to_string(),
    })?;
    if !status.is_success() {
        return Err(DbFailure {
            message: format!("模型服务返回 HTTP {}：{}", status.as_u16(), excerpt(&raw, 300)),
            hint: "401 / 403 多为密钥不对或没有权限；404 多为端点路径不对（要的是 OpenAI 兼容的 /v1）；429 是配额或限流。"
                .to_string(),
        });
    }
    let answer = parse_reply(&raw, tables).map_err(|err| DbFailure {
        message: err.to_string(),
        hint: "换一个模型（有些模型不爱按代码块回话）或重试一次。".to_string(),
    })?;
    Ok(GenerateReply::Generated(GenerateOutcome {
        sql: answer.sql,
        explanation: answer.explanation,
        tables_used: answer.tables_used,
        model: outgoing.model,
        elapsed_ms: started.elapsed().as_millis() as u64,
        table_count: tables.len().min(doyah_studio_db::agent_nl2sql::MAX_TABLES),
        quota,
        limitations: LIMITATIONS.iter().map(|line| line.to_string()).collect(),
    }))
}

fn excerpt(text: &str, limit: usize) -> String {
    let mut out: String = text.chars().take(limit).collect();
    if text.chars().count() > limit {
        out.push('…');
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use doyah_studio_db::agent_config::AgentConfiguration;
    use doyah_studio_db::agent_nl2sql::ColumnBrief;
    use std::io::{BufRead, BufReader, Read, Write};
    use std::net::TcpListener;
    use std::path::PathBuf;
    use std::sync::mpsc;

    fn fixture_root() -> PathBuf {
        match std::env::var("DOYAH_TEST_ROOT") {
            Ok(value) if !value.trim().is_empty() => PathBuf::from(value),
            _ => PathBuf::from("D:/AIProjects/_tmp_face2/fish-fixtures"),
        }
    }

    fn tmp_store(tag: &str) -> AgentSettingsStore {
        let dir = fixture_root().join(format!("doyah-nl2sql-{tag}-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let store = AgentSettingsStore::new(dir.join("agent.json"), dir.join("agent-key.bin"));
        let _ = std::fs::remove_file(&store.config_path);
        let _ = std::fs::remove_file(&store.key_path);
        // 配额台账也要清：同一 tag 的目录若留着上一轮的账，会读成「已用过 N 次」。
        let _ = std::fs::remove_file(store.quota_path());
        store
    }

    fn orders() -> TableBrief {
        TableBrief {
            schema: "public".to_string(),
            name: "orders".to_string(),
            columns: vec![ColumnBrief {
                name: "id".to_string(),
                data_type: "bigint".to_string(),
            }],
        }
    }

    /// 假端点：收一条请求，记下原文，回一段固定的 chat 回包。
    fn fake_endpoint(status_line: &'static str, body: &'static str) -> (String, mpsc::Receiver<String>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let (tx, rx) = mpsc::channel();
        std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut head = String::new();
            let mut length = 0usize;
            loop {
                let mut line = String::new();
                if reader.read_line(&mut line).unwrap_or(0) == 0 {
                    break;
                }
                let trimmed = line.trim_end().to_string();
                if trimmed.is_empty() {
                    break;
                }
                if let Some(value) = trimmed.to_ascii_lowercase().strip_prefix("content-length:") {
                    length = value.trim().parse().unwrap_or(0);
                }
                head.push_str(&trimmed);
                head.push('\n');
            }
            let mut payload = vec![0u8; length];
            let _ = reader.read_exact(&mut payload);
            let request_text = format!("{head}\n{}", String::from_utf8_lossy(&payload));
            let _ = tx.send(request_text);
            let response = format!(
                "HTTP/1.1 {status_line}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            let _ = stream.write_all(response.as_bytes());
            let _ = stream.flush();
        });
        (format!("http://127.0.0.1:{port}/v1"), rx)
    }

    #[test]
    fn a_preview_never_opens_a_connection_and_shows_the_exact_text() {
        let store = tmp_store("preview");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint: "http://127.0.0.1:1/v1".to_string(),
                model: "m".to_string(),
                ..Default::default()
            })
            .unwrap();
        let preview = preview(&store, "每天的订单数", &[orders()]).unwrap();
        assert_eq!(preview.gate.state, GateState::Ready);
        assert!(preview.human.contains("每天的订单数"));
        assert!(preview.human.contains("public.orders(id bigint)"));
        assert_eq!(preview.table_count, 1);
        assert_eq!(preview.url, "http://127.0.0.1:1/v1/chat/completions");
    }

    #[test]
    fn the_switch_being_off_blocks_before_any_request_and_says_why() {
        let store = tmp_store("blocked");
        // 默认配置 = 总开关关。
        match generate(&store, "随便", &[orders()]).unwrap() {
            GenerateReply::Blocked { gate } => assert_eq!(gate.state, GateState::Disabled),
            other => panic!("关着总开关还发了请求：{other:?}"),
        }
    }

    #[test]
    fn a_missing_model_blocks_with_the_issue_named() {
        let store = tmp_store("missing-model");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint: "http://127.0.0.1:1/v1".to_string(),
                model: String::new(),
                ..Default::default()
            })
            .unwrap();
        match generate(&store, "随便", &[orders()]).unwrap() {
            GenerateReply::Blocked { gate } => {
                assert!(gate.issues.iter().any(|issue| issue.code() == "modelMissing"));
            }
            other => panic!("缺模型还发了请求：{other:?}"),
        }
    }

    #[test]
    fn a_real_round_trip_returns_the_sql_and_never_executes_it() {
        let body = serde_json::json!({
            "choices": [{ "message": { "content": "用到了 orders。\n```sql\nSELECT count(*) FROM public.orders;\n```" } }]
        })
        .to_string();
        let leaked: &'static str = Box::leak(body.into_boxed_str());
        let (endpoint, seen) = fake_endpoint("200 OK", leaked);
        let store = tmp_store("round-trip");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint: endpoint.clone(),
                model: "fake-model".to_string(),
                ..Default::default()
            })
            .unwrap();
        // 本地端点免密钥；给一个密钥也不该出现在正文里。
        store.save_key("sk-local-test").unwrap();
        match generate(&store, "订单总数", &[orders()]).unwrap() {
            GenerateReply::Generated(outcome) => {
                assert_eq!(outcome.sql, "SELECT count(*) FROM public.orders;");
                assert_eq!(outcome.tables_used, vec!["public.orders".to_string()]);
                assert_eq!(outcome.model, "fake-model");
                assert!(outcome
                    .limitations
                    .iter()
                    .any(|line| line.contains("每小时上限")));
                // 这一次是真发出去的 ⇒ 配额读数已经含它。
                assert_eq!(outcome.quota.used, 1);
                assert_eq!(outcome.quota.remaining, 59);
            }
            other => panic!("假端点没有回包：{other:?}"),
        }
        let request = seen.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(request.starts_with("POST /v1/chat/completions"), "{request}");
        assert!(request.to_ascii_lowercase().contains("authorization: bearer"), "{request}");
        assert!(request.contains("订单总数"), "{request}");
        assert!(request.contains("public.orders"), "{request}");
    }

    #[test]
    fn an_http_error_is_reported_with_its_status_and_body() {
        let (endpoint, _seen) = fake_endpoint("401 Unauthorized", "{\"error\":\"bad key\"}");
        let store = tmp_store("http-error");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                ..Default::default()
            })
            .unwrap();
        let err = match generate(&store, "随便", &[]) {
            Ok(reply) => panic!("401 还被当成成功：{reply:?}"),
            Err(err) => err,
        };
        assert!(err.message.contains("401"), "{}", err.message);
        assert!(err.message.contains("bad key"), "{}", err.message);
    }

    #[test]
    fn the_hourly_limit_stops_the_request_before_it_is_sent() {
        let body = serde_json::json!({
            "choices": [{ "message": { "content": "```sql\nSELECT 1;\n```" } }]
        })
        .to_string();
        let leaked: &'static str = Box::leak(body.into_boxed_str());
        let (endpoint, seen) = fake_endpoint("200 OK", leaked);
        let store = tmp_store("quota-blocks");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                hourly_limit: 1,
                // 假端点只接一次：真发第二发会等到超时 —— 让这条判据在机制失效时快速转红而不是挂住。
                timeout_secs: 2,
                ..Default::default()
            })
            .unwrap();

        match generate(&store, "第一发", &[orders()]).unwrap() {
            GenerateReply::Generated(outcome) => assert_eq!(outcome.quota.used, 1),
            other => panic!("第一发就被拦了：{other:?}"),
        }

        match generate(&store, "第二发", &[orders()]).unwrap() {
            GenerateReply::Throttled { quota } => {
                assert_eq!(quota.limit, 1);
                assert_eq!(quota.used, 1);
                assert_eq!(quota.remaining, 0);
                assert!(quota.retry_after_secs > 0, "满额了却说不用等：{quota:?}");
            }
            other => panic!("上限 1 却放了第二发：{other:?}"),
        }

        // 否定面：假端点只收到**一条**请求（第二发一条字节都没发出去）。
        let first = seen.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(first.contains("第一发"), "{first}");
        assert!(
            seen.try_recv().is_err(),
            "第二发真的发出去了：配额没有挡住外发"
        );
        // 台账落盘：重启后仍记得这一次（否则上限重启即归零）。
        assert_eq!(store.load_quota().sent_at.len(), 1);
    }

    #[test]
    fn a_preview_shows_how_many_requests_are_left_in_the_hour() {
        let body = serde_json::json!({
            "choices": [{ "message": { "content": "```sql\nSELECT 1;\n```" } }]
        })
        .to_string();
        let leaked: &'static str = Box::leak(body.into_boxed_str());
        let (endpoint, _seen) = fake_endpoint("200 OK", leaked);
        let store = tmp_store("quota-preview");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                ..Default::default()
            })
            .unwrap();

        let before = preview(&store, "订单总数", &[orders()]).unwrap();
        assert_eq!(before.quota.used, 0);
        assert_eq!(before.quota.remaining, before.quota.limit);

        assert!(matches!(
            generate(&store, "订单总数", &[orders()]).unwrap(),
            GenerateReply::Generated(_)
        ));

        let after = preview(&store, "订单总数", &[orders()]).unwrap();
        assert_eq!(after.quota.used, 1, "预览读数没跟上已经发出去的那一次");
        assert_eq!(after.quota.remaining, before.quota.limit - 1);
    }

    #[test]
    fn an_unwritable_quota_ledger_refuses_to_send_instead_of_silently_dropping_the_limit() {
        let (endpoint, seen) = fake_endpoint("200 OK", "{}");
        let store = tmp_store("quota-unwritable");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                ..Default::default()
            })
            .unwrap();
        // 台账路径被一个**目录**占住 ⇒ 写必然失败（Windows / Linux 都是）。
        std::fs::create_dir_all(store.quota_path()).unwrap();
        let err = match generate(&store, "随便", &[orders()]) {
            Ok(reply) => panic!("记不了账还发了请求：{reply:?}"),
            Err(err) => err,
        };
        assert!(err.message.contains("没有发送"), "{}", err.message);
        assert!(seen.try_recv().is_err(), "记不了账却真的外发了");
        let _ = std::fs::remove_dir_all(store.quota_path());
    }
}
