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

use doyah_studio_db::agent_advisor;
use doyah_studio_db::agent_audit::{AuditRecord, AuditVerdict};
use doyah_studio_db::agent_config::{evaluate, AgentConfiguration, AgentGateReport, GateState};
use doyah_studio_db::agent_history::HistoryEntry;
use doyah_studio_db::agent_nl2sql::{build_request, parse_reply, Outgoing, TableBrief};
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
    /// 生成历史（**新的在前**，最多 `Db::agent_history::MAX_ENTRIES` 条）。
    /// 为什么跟着预览一起回：界面要「一打开就能看到以前问过什么」，不该为再开一条 IPC。
    pub history: Vec<HistoryEntry>,
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
    /// 记完这一条之后的历史（**新的在前**；界面用它直接换掉列表，不自己往前插一份 ——
    /// 两处各插一次迟早会不一致）。
    pub history: Vec<HistoryEntry>,
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
    // 历史：一打开弹层就能看到以前问过什么（新的在前）。
    let history = store.load_history().all_recent();
    match build_request(&config, question, tables) {
        Ok(outgoing) => Ok(GeneratePreview {
            gate,
            url: outgoing.url,
            human: outgoing.human,
            table_count: tables.len().min(doyah_studio_db::agent_nl2sql::MAX_TABLES),
            dropped: tables.len().saturating_sub(doyah_studio_db::agent_nl2sql::MAX_TABLES),
            quota,
            history,
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
    if let Some(gate) = gate_refusal(store, &config, question)? {
        return Ok(GenerateReply::Blocked { gate });
    }
    let outgoing = build_request(&config, question, tables).map_err(|err| DbFailure {
        message: err.to_string(),
        hint: "先写一句要查什么（比如「最近 7 天每天的订单数」）。".to_string(),
    })?;

    // 配额：**装配之后再记**（问题为空这类参数错误不该白占一次额度），**建客户端之前**记
    // （记不上就不发 —— 否则每小时上限形同不存在）。
    let quota = match quota_admission(store, &config, question)? {
        Ok(quota) => quota,
        Err(quota) => return Ok(GenerateReply::Throttled { quota }),
    };

    let started = Instant::now();
    let raw = send_once(
        store,
        &config,
        &outgoing,
        question,
        tables.len().min(doyah_studio_db::agent_nl2sql::MAX_TABLES),
    )?;
    let answer = match parse_reply(&raw, tables) {
        Ok(answer) => answer,
        Err(err) => {
            let failure = DbFailure {
                message: err.to_string(),
                hint: "换一个模型（有些模型不爱按代码块回话）或重试一次。".to_string(),
            };
            let note = record_audit(
                store,
                AuditVerdict::Failed,
                &outgoing.model,
                &outgoing.url,
                question,
                &failure.message,
                started.elapsed().as_millis() as u64,
                tables.len().min(doyah_studio_db::agent_nl2sql::MAX_TABLES),
            );
            return Err(with_audit_note(failure, note));
        }
    };

    // 记一条历史（**只在成功后**：被挡住 / 报错 / 解析失败的那一次不是「可回看的结果」）。
    // 落盘失败**不阻断**（与配额台账相反：历史写不上只是回看不到，配额写不上是上限失效），
    // 但必须在结果里如实说一句 —— 静默丢记录同样是骗人。
    let mut limitations: Vec<String> = LIMITATIONS.iter().map(|line| line.to_string()).collect();
    let mut ledger = store.load_history();
    ledger.append(HistoryEntry::record(
        question,
        &answer.sql,
        &answer.explanation,
        answer.tables_used.clone(),
        &outgoing.model,
        now_secs(),
    ));
    if let Err(err) = store.save_history(&ledger) {
        limitations.push(format!(
            "这一次的问句没能记进生成历史（{}）—— 结果仍然可用，只是关掉这个弹层后回看不到它。",
            err.message
        ));
    }

    let elapsed_ms = started.elapsed().as_millis() as u64;

    // 审计：**成功也要记**（这一次确实发出去了、用的哪个模型、发出去多少张表）。
    // 写不进去要如实说 —— 审计是事后交代，静默丢一条等于「说不清」。
    if let Some(note) = record_audit(
        store,
        AuditVerdict::Ok,
        &outgoing.model,
        &outgoing.url,
        question,
        "",
        elapsed_ms,
        tables.len().min(doyah_studio_db::agent_nl2sql::MAX_TABLES),
    ) {
        limitations.push(format!(
            "这一次没能记进审计记录（{note}）—— 结果仍然可用，但「刚才发过什么」这条事后查不到。"
        ));
    }

    Ok(GenerateReply::Generated(GenerateOutcome {
        sql: answer.sql,
        explanation: answer.explanation,
        tables_used: answer.tables_used,
        model: outgoing.model,
        elapsed_ms,
        table_count: tables.len().min(doyah_studio_db::agent_nl2sql::MAX_TABLES),
        quota,
        limitations,
        history: ledger.all_recent(),
    }))
}

/// 一次「问模型」的结局（诊断面 `FR-AI-03` 第二片）：**三种，全都在这里** ——
/// 与生成面同构（挡住 / 满额 / 真发出去），但回的是**正文原文**，不是 SQL。
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "status", rename_all = "camelCase")]
pub enum AskReply {
    /// 没放行：**一条请求都没发**。
    Blocked {
        /// 逐条理由（界面按短码查语言表）。
        gate: AgentGateReport,
    },
    /// 本小时配额已满：**一条请求都没发**。
    Throttled {
        /// 满额时的读数。
        quota: QuotaStatus,
    },
    /// 放行并完成：正文原样交回（**没有被解读、也没有被执行**）。
    Answered {
        /// 模型正文（解读在界面侧 `workspace/agentDiagnosis.ts`）。
        text: String,
        /// 实际使用的模型名。
        model: String,
        /// 往返耗时（毫秒）。
        elapsed_ms: u64,
        /// 发完这一次之后的配额读数。
        quota: QuotaStatus,
        /// 已知缺口（如实显示）。
        limitations: Vec<String>,
    },
}

/// 问诊断这一次的已知缺口（随结果一起回，界面照实说）。
pub const ASK_LIMITATIONS: [&str; 2] = [
    "这一次的问答只进审计（每次外发一条），不进「生成历史」—— 那里是「一条 SQL」的清单，混进来会让回填串味。",
    "模型给的建议只按 `statementRisk` 判风险并放进编辑器，**本应用不执行它**。",
];

/// 闸门裁决：不放行就回 `Some(报告)`（**并记一条 blocked 审计**），放行回 `None`。
///
/// 为什么抽出来：生成面与诊断面**必须用同一个闸门**。各写一份的话，某天改了一边，
/// 另一边就会在「总开关关着」时照样把资料块发出去 —— 而那种缺失不会有任何判据变红。
fn gate_refusal(
    store: &AgentSettingsStore,
    config: &AgentConfiguration,
    summary: &str,
) -> Result<Option<AgentGateReport>, DbFailure> {
    let gate = evaluate(config, store.key_present());
    if gate.state == GateState::Ready {
        return Ok(None);
    }
    // 闸门不放行 ⇒ 零外发（连客户端都不建）。**但这一次要留痕**：
    // 「为什么没发出去」和「发了什么」一样要能事后查（FR-AI-09）。
    let detail = if gate.issues.is_empty() {
        "外发闸门不放行：总开关关闭".to_string()
    } else {
        format!(
            "外发闸门不放行：{}",
            gate.issues
                .iter()
                .map(|issue| issue.code())
                .collect::<Vec<_>>()
                .join("、")
        )
    };
    let _ = record_audit(
        store,
        AuditVerdict::Blocked,
        &config.model,
        &config.endpoint,
        summary,
        &detail,
        0,
        0,
    );
    Ok(Some(gate))
}

/// 配额：满了回 `Err(读数)`（**已记一条 throttled 审计**），放行回 `Ok(放行后的读数)`。
///
/// 「记不上就不发」留在这里（不是留在调用方）：台账写不进去时上限等于不存在，
/// 那比少发一次糟得多。
fn quota_admission(
    store: &AgentSettingsStore,
    config: &AgentConfiguration,
    summary: &str,
) -> Result<Result<QuotaStatus, QuotaStatus>, DbFailure> {
    let mut ledger = store.load_quota();
    let (admitted, quota) = ledger.admit(now_secs(), config.hourly_limit);
    if !admitted {
        // 满了：一条请求都不发 —— **同样留痕**（满额也是「说清楚为什么」的一次）。
        let detail = format!(
            "本小时已满额（上限 {} 次，已用 {} 次）：约 {} 分钟后才有空位",
            quota.limit,
            quota.used,
            (quota.retry_after_secs + 59) / 60
        );
        let _ = record_audit(
            store,
            AuditVerdict::Throttled,
            &config.model,
            &config.endpoint,
            summary,
            &detail,
            0,
            0,
        );
        return Ok(Err(quota));
    }
    store.save_quota(&ledger).map_err(|err| DbFailure {
        message: format!(
            "{} 这次没有发送：记不了账就不发，否则「每小时上限」等于没有。",
            err.message
        ),
        hint: err.hint,
    })?;
    Ok(Ok(quota))
}

/// 一次真实外发（建客户端 → POST → 读正文 → 非 2xx 转可读失败）。**失败一律记一条审计**。
///
/// 三处失败各自记一次、不统一兜：它们的判定来源不同（连接层 / 读包 / HTTP 状态），
/// 混在一起就只能写一句「失败了」，用户看不出该改端点、改超时还是换密钥。
fn send_once(
    store: &AgentSettingsStore,
    config: &AgentConfiguration,
    outgoing: &Outgoing,
    summary: &str,
    table_count: usize,
) -> Result<String, DbFailure> {
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
    let response = match request.send() {
        Ok(response) => response,
        Err(err) => {
            let timeout = err.is_timeout();
            let failure = DbFailure {
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
                    "确认端点地址与网络（远端还需代理 / 防火墙放行）；本地端点的服务是否在跑。"
                        .to_string()
                },
            };
            // 这一次**真的出网了**（连接已发起）⇒ 记 Failed。
            let note = record_audit(
                store,
                AuditVerdict::Failed,
                &outgoing.model,
                &outgoing.url,
                summary,
                &failure.message,
                started.elapsed().as_millis() as u64,
                table_count,
            );
            return Err(with_audit_note(failure, note));
        }
    };

    let status = response.status();
    let raw = match response.text() {
        Ok(raw) => raw,
        Err(err) => {
            let failure = DbFailure {
                message: format!("回包读不出来：{err}"),
                hint: "重试一次；仍然不行就换端点。".to_string(),
            };
            let note = record_audit(
                store,
                AuditVerdict::Failed,
                &outgoing.model,
                &outgoing.url,
                summary,
                &failure.message,
                started.elapsed().as_millis() as u64,
                table_count,
            );
            return Err(with_audit_note(failure, note));
        }
    };
    if !status.is_success() {
        let failure = DbFailure {
            message: format!("模型服务返回 HTTP {}：{}", status.as_u16(), excerpt(&raw, 300)),
            hint: "401 / 403 多为密钥不对或没有权限；404 多为端点路径不对（要的是 OpenAI 兼容的 /v1）；429 是配额或限流。"
                .to_string(),
        };
        let note = record_audit(
            store,
            AuditVerdict::Failed,
            &outgoing.model,
            &outgoing.url,
            summary,
            &failure.message,
            started.elapsed().as_millis() as u64,
            table_count,
        );
        return Err(with_audit_note(failure, note));
    }
    Ok(raw)
}

/// **问诊断这一次**（`FR-AI-03` 第二片）：把面板上那份资料块原样发出去，只回正文。
///
/// 与 `generate` 共用同一套闸门 / 配额 / 审计 / 外发助手 —— 诊断不是「另一条外发通道」，
/// 它只是**换了一份提示词**的同一条通道（关掉总开关，这里同样一条请求都发不出去）。
pub fn ask(store: &AgentSettingsStore, brief: &str) -> Result<AskReply, DbFailure> {
    let config = store.load()?;
    if let Some(gate) = gate_refusal(store, &config, brief)? {
        return Ok(AskReply::Blocked { gate });
    }
    let outgoing = agent_advisor::build_request(&config, brief).map_err(|err| DbFailure {
        message: err.to_string(),
        hint: "证据还没取回来时也能用：把证据区的内容自己贴进「回复」框直接点解读。".to_string(),
    })?;

    // 配额：与生成面同一条台账（问诊断也占一次额度 —— 它一样烧钱）。
    let quota = match quota_admission(store, &config, brief)? {
        Ok(quota) => quota,
        Err(quota) => return Ok(AskReply::Throttled { quota }),
    };

    let started = Instant::now();
    let raw = send_once(store, &config, &outgoing, brief, 0)?;
    let text = match agent_advisor::parse_reply(&raw) {
        Ok(text) => text,
        Err(err) => {
            let failure = DbFailure {
                message: err.to_string(),
                hint: "换一个模型（有些模型把正文放在别的字段里），或直接把回复粘进下面的框手动解读。"
                    .to_string(),
            };
            let note = record_audit(
                store,
                AuditVerdict::Failed,
                &outgoing.model,
                &outgoing.url,
                brief,
                &failure.message,
                started.elapsed().as_millis() as u64,
                0,
            );
            return Err(with_audit_note(failure, note));
        }
    };
    let elapsed_ms = started.elapsed().as_millis() as u64;

    let mut limitations: Vec<String> = ASK_LIMITATIONS.iter().map(|line| line.to_string()).collect();
    if let Some(note) = record_audit(
        store,
        AuditVerdict::Ok,
        &outgoing.model,
        &outgoing.url,
        brief,
        "",
        elapsed_ms,
        0,
    ) {
        limitations.push(format!(
            "这一次没能记进审计记录（{note}）—— 结果仍然可用，但「刚才发过什么」这条事后查不到。"
        ));
    }

    Ok(AskReply::Answered {
        text,
        model: outgoing.model,
        elapsed_ms,
        quota,
        limitations,
    })
}

/// 记一条审计（`FR-AI-09`）：**四种结局都记** —— 成功、失败、被闸门挡住、被配额挡住。
///
/// 返回 `Option<String>` = 写不进去时的可读原因（调用方必须**说出来**，别咽掉）；
/// 但没有理由因为它而拒发 / 改判：审计是事后交代，不是通行证。
#[allow(clippy::too_many_arguments)]
fn record_audit(
    store: &AgentSettingsStore,
    verdict: AuditVerdict,
    model: &str,
    endpoint: &str,
    question: &str,
    detail: &str,
    duration_ms: u64,
    table_count: usize,
) -> Option<String> {
    let mut ledger = store.load_audit();
    ledger.append(AuditRecord::record(
        verdict,
        model,
        endpoint,
        question,
        detail,
        duration_ms,
        table_count,
        now_secs(),
    ));
    store.save_audit(&ledger).err().map(|err| err.message)
}

/// 把「审计没记上」这件事挂到错误消息后面：**不改变原错误**（它才是用户要处理的），
/// 但也不让「这一次没留下痕」被静默吞掉。
fn with_audit_note(mut failure: DbFailure, note: Option<String>) -> DbFailure {
    if let Some(note) = note {
        failure.message = format!(
            "{}（另外：这一次没能记进审计记录：{note}）",
            failure.message
        );
    }
    failure
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
        // 历史同理（留着上一轮的记录会让「只记了一条」这类断言直接失真）。
        let _ = std::fs::remove_file(store.history_path());
        // 审计同理：留着上一轮的痕，「这一次留了几条」就说不清。
        let _ = std::fs::remove_file(store.audit_path());
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

    // ── 审计（`FR-AI-09`）：**四种结局各留一条**，成功失败都要能事后说得清 ─────────────

    #[test]
    fn a_successful_generation_leaves_one_audit_record_saying_it_did_leave() {
        let body = serde_json::json!({
            "choices": [{ "message": { "content": "```sql\nSELECT count(*) FROM public.orders;\n```" } }]
        })
        .to_string();
        let leaked: &'static str = Box::leak(body.into_boxed_str());
        let (endpoint, _seen) = fake_endpoint("200 OK", leaked);
        let store = tmp_store("audit-ok");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "fake-model".to_string(),
                ..Default::default()
            })
            .unwrap();

        assert!(matches!(
            generate(&store, "订单总数", &[orders()]).unwrap(),
            GenerateReply::Generated(_)
        ));

        let records = store.load_audit().all_recent();
        assert_eq!(records.len(), 1, "一次成功只该留一条痕：{records:?}");
        assert_eq!(records[0].verdict, AuditVerdict::Ok);
        assert!(
            records[0].verdict.left_the_machine(),
            "成功的那次当然出网了"
        );
        assert_eq!(records[0].model, "fake-model");
        assert_eq!(records[0].table_count, 1, "发出去几张表要记下来");
        assert!(records[0].summary.contains("订单总数"), "{records:?}");
    }

    #[test]
    fn a_blocked_attempt_is_audited_even_though_nothing_left_the_machine() {
        // 否定面的另一半：**没发出去**也要留一条 —— 否则「我怎么什么都没查到」无法回答。
        let store = tmp_store("audit-blocked");
        assert!(matches!(
            generate(&store, "随便", &[]).unwrap(),
            GenerateReply::Blocked { .. }
        ));
        let records = store.load_audit().all_recent();
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].verdict, AuditVerdict::Blocked);
        assert!(!records[0].verdict.left_the_machine());
        assert!(
            records[0].detail.contains("总开关"),
            "挡住的原因要写清：{}",
            records[0].detail
        );
        assert_eq!(records[0].duration_ms, 0, "没发出去就没有往返耗时");
    }

    #[test]
    fn a_throttled_attempt_is_audited_next_to_the_one_that_got_through() {
        let body = serde_json::json!({
            "choices": [{ "message": { "content": "```sql\nSELECT 1;\n```" } }]
        })
        .to_string();
        let leaked: &'static str = Box::leak(body.into_boxed_str());
        let (endpoint, _seen) = fake_endpoint("200 OK", leaked);
        let store = tmp_store("audit-throttled");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                hourly_limit: 1,
                timeout_secs: 2,
                ..Default::default()
            })
            .unwrap();

        assert!(matches!(
            generate(&store, "第一发", &[orders()]).unwrap(),
            GenerateReply::Generated(_)
        ));
        assert!(matches!(
            generate(&store, "第二发", &[orders()]).unwrap(),
            GenerateReply::Throttled { .. }
        ));

        let records = store.load_audit().all_recent();
        assert_eq!(records.len(), 2, "成功一发 + 满额一发，各一条：{records:?}");
        assert_eq!(records[0].verdict, AuditVerdict::Throttled, "新的在前");
        assert!(!records[0].verdict.left_the_machine());
        assert!(records[0].detail.contains("满额"), "{}", records[0].detail);
        assert_eq!(records[1].verdict, AuditVerdict::Ok);
    }

    #[test]
    fn a_failed_request_is_audited_and_the_secret_in_the_server_text_is_scrubbed() {
        // 端点在回包里夹了一句形似口令的话：审计要**照实记这次失败**，但凭据不许跟着落盘。
        let body = "{\"error\":\"password = 'hunter2' 不对\"}".to_string();
        let leaked: &'static str = Box::leak(body.into_boxed_str());
        let (endpoint, _seen) = fake_endpoint("500 Internal Server Error", leaked);
        let store = tmp_store("audit-failed");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                ..Default::default()
            })
            .unwrap();

        assert!(
            generate(&store, "随便", &[]).is_err(),
            "500 不该被当成成功"
        );

        let records = store.load_audit().all_recent();
        assert_eq!(records.len(), 1, "失败也要留一条：{records:?}");
        assert_eq!(records[0].verdict, AuditVerdict::Failed);
        assert!(records[0].verdict.left_the_machine(), "连接已经发出去了");
        assert!(records[0].detail.contains("500"), "{}", records[0].detail);
        assert!(
            !records[0].detail.contains("hunter2"),
            "服务端原话里的口令被原样写进了审计：{}",
            records[0].detail
        );
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

    #[test]
    fn a_successful_generation_leaves_one_entry_behind_and_the_preview_shows_it() {
        let body = serde_json::json!({
            "choices": [{ "message": { "content": "按天分组。\n```sql\nSELECT date_trunc('day', created_at) FROM public.orders;\n```" } }]
        })
        .to_string();
        let leaked: &'static str = Box::leak(body.into_boxed_str());
        let (endpoint, _seen) = fake_endpoint("200 OK", leaked);
        let store = tmp_store("history-writes");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "fake-model".to_string(),
                ..Default::default()
            })
            .unwrap();

        // 发之前：历史是空的，预览也得照实回空。
        assert!(preview(&store, "每天的订单数", &[orders()]).unwrap().history.is_empty());

        match generate(&store, "每天的订单数", &[orders()]).unwrap() {
            GenerateReply::Generated(outcome) => {
                assert_eq!(outcome.history.len(), 1, "生成成功了却没记一条");
                assert_eq!(outcome.history[0].question, "每天的订单数");
                assert!(outcome.history[0].sql.contains("date_trunc"));
                assert_eq!(outcome.history[0].model, "fake-model");
                assert_eq!(outcome.history[0].tables_used, vec!["public.orders".to_string()]);
                // 这一条真的落盘了（重启后还在）。
                assert_eq!(store.load_history().len(), 1);
                // 预览也读得到（下次打开弹层就能看到）。
                assert_eq!(preview(&store, "再问一句", &[orders()]).unwrap().history.len(), 1);
            }
            other => panic!("假端点没有回包：{other:?}"),
        }
    }

    #[test]
    fn a_failed_generation_leaves_no_history_entry() {
        let (endpoint, _seen) = fake_endpoint("500 Internal Server Error", "{}");
        let store = tmp_store("history-no-write");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                ..Default::default()
            })
            .unwrap();
        assert!(generate(&store, "随便", &[orders()]).is_err(), "500 还被当成成功");
        assert!(
            store.load_history().is_empty(),
            "失败的那一次不该进历史（历史是结果清单，不是请求日志）"
        );
    }

    #[test]
    fn an_unwritable_history_file_still_returns_the_sql_and_says_so() {
        let body = serde_json::json!({
            "choices": [{ "message": { "content": "```sql\nSELECT 1;\n```" } }]
        })
        .to_string();
        let leaked: &'static str = Box::leak(body.into_boxed_str());
        let (endpoint, _seen) = fake_endpoint("200 OK", leaked);
        let store = tmp_store("history-unwritable");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                ..Default::default()
            })
            .unwrap();
        // 历史路径被一个**目录**占住 ⇒ 写必然失败。配额那条路仍可写（两份文件互不牵连）。
        std::fs::create_dir_all(store.history_path()).unwrap();
        match generate(&store, "随便", &[orders()]).unwrap() {
            GenerateReply::Generated(outcome) => {
                assert_eq!(outcome.sql, "SELECT 1;");
                assert!(
                    outcome
                        .limitations
                        .iter()
                        .any(|line| line.contains("没能记进生成历史")),
                    "记不上历史却没如实说：{:?}",
                    outcome.limitations
                );
            }
            other => panic!("记不上历史就把整次生成废了：{other:?}"),
        }
        let _ = std::fs::remove_dir_all(store.history_path());
    }

    // ── 问诊断（`FR-AI-03` 第二片）：与生成面**同一条外发通道** ─────────────────────

    fn advisor_body() -> &'static str {
        let body = serde_json::json!({
            "choices": [{ "message": {
                "role": "assistant",
                "content": "结论: e1 显示全表扫描，缺索引 [依据: e1]\n建议: SELECT count(*) FROM pg_stat_activity;"
            } }]
        })
        .to_string();
        Box::leak(body.into_boxed_str())
    }

    #[test]
    fn a_blocked_diagnosis_ask_sends_nothing_and_says_why() {
        // 否定面：总开关关着时，**资料块一个字节都不许出去**，但这一次要留痕。
        let store = tmp_store("ask-blocked");
        match ask(&store, "e1 执行计划：Seq Scan on orders").unwrap() {
            AskReply::Blocked { gate } => {
                assert_ne!(gate.state, GateState::Ready);
            }
            other => panic!("关着总开关还把资料块发了：{other:?}"),
        }
        let records = store.load_audit().all_recent();
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].verdict, AuditVerdict::Blocked);
        assert!(!records[0].verdict.left_the_machine());
        assert!(records[0].summary.contains("Seq Scan"), "{records:?}");
        // 挡住的那次不该占额度，也不该进生成历史。
        assert_eq!(store.load_quota().status(now_secs(), 60).used, 0);
        assert!(store.load_history().all_recent().is_empty());
    }

    #[test]
    fn a_diagnosis_ask_round_trip_sends_the_brief_verbatim_and_returns_only_text() {
        let (endpoint, seen) = fake_endpoint("200 OK", advisor_body());
        let store = tmp_store("ask-ok");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "fake-model".to_string(),
                ..Default::default()
            })
            .unwrap();
        let brief = "诊断资料块 e1 执行计划\nSeq Scan on public.orders  (cost=0.00..1.00)";
        match ask(&store, brief).unwrap() {
            AskReply::Answered { text, model, quota, limitations, .. } => {
                assert!(text.starts_with("结论:"), "{text}");
                assert!(text.contains("[依据: e1]"), "{text}");
                assert_eq!(model, "fake-model");
                assert_eq!(quota.used, 1, "问一次也占一次额度");
                assert!(
                    limitations.iter().any(|line| line.contains("审计")),
                    "{limitations:?}"
                );
            }
            other => panic!("假端点回了正常正文却没过：{other:?}"),
        }
        let request = seen.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(
            request.starts_with("POST /v1/chat/completions"),
            "{request}"
        );
        assert!(request.contains("Seq Scan on public.orders"), "{request}");
        assert!(request.contains("[依据: eN]"), "三条纪律要随正文发出去：{request}");
        // 诊断不进生成历史（那里是「一条 SQL」的清单）。
        assert!(store.load_history().all_recent().is_empty());
        let records = store.load_audit().all_recent();
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].verdict, AuditVerdict::Ok);
        assert_eq!(records[0].table_count, 0, "诊断不发表结构");
    }

    #[test]
    fn a_diagnosis_ask_over_the_hourly_limit_does_not_send() {
        let (endpoint, _seen) = fake_endpoint("200 OK", advisor_body());
        let store = tmp_store("ask-throttle");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                hourly_limit: 1,
                ..Default::default()
            })
            .unwrap();
        assert!(matches!(
            ask(&store, "e1 执行计划").unwrap(),
            AskReply::Answered { .. }
        ));
        match ask(&store, "e1 执行计划").unwrap() {
            AskReply::Throttled { quota } => {
                assert_eq!(quota.used, 1);
                assert_eq!(quota.limit, 1);
            }
            other => panic!("满额了还发：{other:?}"),
        }
    }
}
