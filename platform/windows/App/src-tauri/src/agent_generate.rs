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

use std::io::Read;
use std::time::{Duration, Instant};

use doyah_studio_db::agent_advisor;
use doyah_studio_db::agent_audit::{parse_usage, parse_usage_text, AuditUsage, AuditRecord, AuditVerdict};
use doyah_studio_db::agent_config::{evaluate, AgentConfiguration, AgentGateReport, GateState};
use doyah_studio_db::agent_history::HistoryEntry;
use doyah_studio_db::agent_nl2sql::{
    build_chat_request_with_context, build_request, parse_reply, parse_tool_calls, read_file_path,
    write_file_arguments, CarriedFile, ChatMessage, ChatToolCall, Outgoing, TableBrief,
    CHAT_READ_FILE_TOOL, CHAT_WRITE_FILE_TOOL,
};
use doyah_studio_db::agent_quota::{now_secs, QuotaStatus};
use doyah_studio_db::agent_retry::{
    classify_status, classify_transport, AttemptNote, RetryClass, RetryPolicy,
};
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
    /// 这一发的**尝试账**（`FR-AI-30` ①）：成功也带 —— 用户能看到「第 1 次 429、退避 400ms，第 2 次成功」。
    pub attempts: Vec<AttemptNote>,
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
    let sent = send_with_retry(
        store,
        &config,
        &outgoing,
        question,
        tables.len().min(doyah_studio_db::agent_nl2sql::MAX_TABLES),
    )
    .map_err(|err| err.failure)?;
    let usage = sent.usage;
    let attempts = sent.attempts;
    let raw = sent.raw;
    let answer = match parse_reply(&raw, tables) {
        Ok(answer) => answer,
        Err(err) => {
            let failure = DbFailure {
                message: err.to_string(),
                hint: "换一个模型（有些模型不爱按代码块回话）或重试一次。".to_string(),
            };
            let note = record_audit_with_usage(
                store,
                AuditVerdict::Failed,
                &outgoing.model,
                &outgoing.url,
                question,
                &failure.message,
                started.elapsed().as_millis() as u64,
                tables.len().min(doyah_studio_db::agent_nl2sql::MAX_TABLES),
                usage,
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

    // 审计：**成功也要记**（这一次确实发出去了、用的哪个模型、发出去多少张表、花了多少 token）。
    // 写不进去要如实说 —— 审计是事后交代，静默丢一条等于「说不清」。
    if let Some(note) = record_audit_with_usage(
        store,
        AuditVerdict::Ok,
        &outgoing.model,
        &outgoing.url,
        question,
        "",
        elapsed_ms,
        tables.len().min(doyah_studio_db::agent_nl2sql::MAX_TABLES),
        usage,
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
        attempts,
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
        /// 这一发的**尝试账**（`FR-AI-30` ①；成功也带）。
        attempts: Vec<AttemptNote>,
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

/// 一次外发的**结局**（成功带正文，失败带可读原因）—— 两条都带**这一发的尝试账**。
struct SendOutcome {
    raw: String,
    attempts: Vec<AttemptNote>,
    /// 这一次真拿到的 token 用量（`FR-AI-24`；服务端不回 `usage` ⇒ 全 0）。
    usage: AuditUsage,
}

/// 失败载荷：`DbFailure` + 尝试账（调用方要把它带进回包文案里）。
struct SendFailure {
    failure: DbFailure,
}

/// 建 HTTP 客户端（不跟随重定向：端点被改写会把密钥带到别的主机上）。
fn build_client(config: &AgentConfiguration) -> Result<reqwest::blocking::Client, DbFailure> {
    reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(config.timeout_secs as u64))
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(|err| DbFailure {
            message: format!("建 HTTP 客户端失败：{err}"),
            hint: "这属实现缺陷：请保留现场并报告。".to_string(),
        })
}

/// 服务端的 `Retry-After`（只认秒数形态；HTTP 日期形态不猜，回落到我们自己的退避序列）。
fn retry_after_secs(response: &reqwest::blocking::Response) -> Option<u64> {
    response
        .headers()
        .get("retry-after")
        .and_then(|value| value.to_str().ok())
        .and_then(|text| text.trim().parse::<u64>().ok())
}

/// 这一跳失败后要不要再试、等多久（`None` = 停）。
fn next_delay(
    policy: &RetryPolicy,
    failed_attempt: u32,
    class: RetryClass,
    retry_after: Option<u64>,
) -> Option<u64> {
    if !class.is_retryable() || !policy.has_next(failed_attempt) {
        return None;
    }
    Some(policy.honour_retry_after(failed_attempt, retry_after))
}

/// 收尾文案：把「为什么停」补成一句人话（**不许静默吞掉**，也不许让用户以为程序卡住）。
fn stop_note(failure: DbFailure, attempts: &[AttemptNote], class: RetryClass) -> DbFailure {
    let tail = if attempts.len() <= 1 && class == RetryClass::Fatal {
        "（这类错误重试没有意义 —— 密钥 / 路径 / 请求体不对时，再发一百次也是同一个结果，所以只发了 1 次。）"
    } else if attempts.len() <= 1 {
        "（设置里「失败后重试」为 0 次，所以只发了 1 次；把它调大可以让这类抖动自动等一会儿再试。）"
    } else {
        return DbFailure {
            message: format!(
                "{}（已尝试 {} 次全部失败：每次重试都真出网、各占一次本小时配额。）",
                failure.message,
                attempts.len()
            ),
            hint: format!(
                "{} 等一会儿再点，或把「失败后重试」与「退避上限」调大；端点若是本机服务，先确认它是否在跑。",
                failure.hint
            ),
        };
    };
    DbFailure {
        message: format!("{}{}", failure.message, tail),
        hint: failure.hint,
    }
}

/// 一次真实外发（建客户端 → 按策略重试 → 读正文 → 非 2xx 分级后决定再试还是停）。**每次失败各记一条审计**。
///
/// 三处失败各自判、不统一兜：它们的判定来源不同（连接层 / 读包 / HTTP 状态），
/// 混在一起就只能写一句「失败了」，用户看不出该改端点、改超时还是换密钥。
///
/// **重试同样真出网** ⇒ 第 2 次起每次尝试都再过一遍配额（第一次由调用方记过账）。
fn send_with_retry(
    store: &AgentSettingsStore,
    config: &AgentConfiguration,
    outgoing: &Outgoing,
    summary: &str,
    table_count: usize,
) -> Result<SendOutcome, SendFailure> {
    let client = match build_client(config) {
        Ok(client) => client,
        Err(failure) => return Err(SendFailure { failure }),
    };
    let policy = RetryPolicy::from_config(config);
    let mut attempts: Vec<AttemptNote> = Vec::new();
    let mut attempt_no: u32 = 1;
    loop {
        if attempt_no > 1 {
            match quota_admission(store, config, summary) {
                Ok(Ok(_)) => {}
                Ok(Err(quota)) => {
                    let failure = DbFailure {
                        message: format!(
                            "还想再试一次，但本小时配额已满（上限 {} 次，已用 {} 次）：这一发没有发出去。前面已尝试 {} 次。",
                            quota.limit,
                            quota.used,
                            attempt_no - 1
                        ),
                        hint: format!(
                            "约 {} 分钟后才有空位；也可以把「每小时上限」调大。",
                            (quota.retry_after_secs + 59) / 60
                        ),
                    };
                    return Err(SendFailure { failure });
                }
                Err(err) => return Err(SendFailure { failure: err }),
            }
        }

        let started = Instant::now();
        let mut request = client
            .post(&outgoing.url)
            .header(reqwest::header::CONTENT_TYPE, "application/json")
            .body(outgoing.body.clone());
        // 本地端点免密钥：**重试时同样不带** Authorization（这条路只有一处，重试不该绕开它）。
        if let Some(secret) = store.key_secret() {
            request = request.header(reqwest::header::AUTHORIZATION, format!("Bearer {secret}"));
        }

        let response = match request.send() {
            Ok(response) => response,
            Err(err) => {
                let timed_out = err.is_timeout();
                let class = classify_transport(timed_out, err.is_connect());
                let failure = DbFailure {
                    message: if timed_out {
                        format!(
                            "请求超时（{} 秒）：模型服务没有在时限内回话。",
                            config.timeout_secs
                        )
                    } else {
                        format!("请求发不出去：{err}")
                    },
                    hint: if timed_out {
                        "把「单次请求超时」调大，或换一个更近的端点。".to_string()
                    } else {
                        "确认端点地址与网络（远端还需代理 / 防火墙放行）；本地端点的服务是否在跑。"
                            .to_string()
                    },
                };
                let detail = failure.message.clone();
                // 这一次**真的出网了**（连接已发起）⇒ 记 Failed。
                let note = record_audit(
                    store,
                    AuditVerdict::Failed,
                    &outgoing.model,
                    &outgoing.url,
                    summary,
                    &detail,
                    started.elapsed().as_millis() as u64,
                    table_count,
                );
                let failure = with_audit_note(failure, note);
                match next_delay(&policy, attempt_no, class, None) {
                    Some(delay) => {
                        attempts.push(AttemptNote::failed(attempt_no, class, None, detail, delay));
                        std::thread::sleep(Duration::from_millis(delay));
                        attempt_no += 1;
                        continue;
                    }
                    None => {
                        attempts.push(AttemptNote::failed(attempt_no, class, None, detail, 0));
                        let failure = stop_note(failure, &attempts, class);
                        return Err(SendFailure { failure });
                    }
                }
            }
        };

        let status = response.status();
        let retry_after = retry_after_secs(&response);
        let raw = match response.text() {
            Ok(raw) => raw,
            Err(err) => {
                let class = classify_transport(false, false);
                let failure = DbFailure {
                    message: format!("回包读不出来：{err}"),
                    hint: "重试一次；仍然不行就换端点。".to_string(),
                };
                let detail = failure.message.clone();
                let note = record_audit(
                    store,
                    AuditVerdict::Failed,
                    &outgoing.model,
                    &outgoing.url,
                    summary,
                    &detail,
                    started.elapsed().as_millis() as u64,
                    table_count,
                );
                let failure = with_audit_note(failure, note);
                match next_delay(&policy, attempt_no, class, None) {
                    Some(delay) => {
                        attempts.push(AttemptNote::failed(attempt_no, class, None, detail, delay));
                        std::thread::sleep(Duration::from_millis(delay));
                        attempt_no += 1;
                        continue;
                    }
                    None => {
                        attempts.push(AttemptNote::failed(attempt_no, class, None, detail, 0));
                        let failure = stop_note(failure, &attempts, class);
                        return Err(SendFailure { failure });
                    }
                }
            }
        };
        if !status.is_success() {
            let class = classify_status(status.as_u16());
            let failure = DbFailure {
                message: format!("模型服务返回 HTTP {}：{}", status.as_u16(), excerpt(&raw, 300)),
                hint: "401 / 403 多为密钥不对或没有权限；404 多为端点路径不对（要的是 OpenAI 兼容的 /v1）；429 是配额或限流（这类会自动等一会儿再试）。"
                    .to_string(),
            };
            let detail = failure.message.clone();
            let note = record_audit(
                store,
                AuditVerdict::Failed,
                &outgoing.model,
                &outgoing.url,
                summary,
                &detail,
                started.elapsed().as_millis() as u64,
                table_count,
            );
            let failure = with_audit_note(failure, note);
            match next_delay(&policy, attempt_no, class, retry_after) {
                Some(delay) => {
                    attempts.push(AttemptNote::failed(
                        attempt_no,
                        class,
                        Some(status.as_u16()),
                        detail,
                        delay,
                    ));
                    std::thread::sleep(Duration::from_millis(delay));
                    attempt_no += 1;
                    continue;
                }
                None => {
                    attempts.push(AttemptNote::failed(
                        attempt_no,
                        class,
                        Some(status.as_u16()),
                        detail,
                        0,
                    ));
                    let failure = stop_note(failure, &attempts, class);
                    return Err(SendFailure { failure });
                }
            }
        }
        attempts.push(AttemptNote::ok(attempt_no, Some(status.as_u16())));
        let usage = parse_usage_text(&raw);
        return Ok(SendOutcome {
            raw,
            attempts,
            usage,
        });
    }
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
    let sent = send_with_retry(store, &config, &outgoing, brief, 0).map_err(|err| err.failure)?;
    let usage = sent.usage;
    let attempts = sent.attempts;
    let raw = sent.raw;
    let text = match agent_advisor::parse_reply(&raw) {
        Ok(text) => text,
        Err(err) => {
            let failure = DbFailure {
                message: err.to_string(),
                hint: "换一个模型（有些模型把正文放在别的字段里），或直接把回复粘进下面的框手动解读。"
                    .to_string(),
            };
            let note = record_audit_with_usage(
                store,
                AuditVerdict::Failed,
                &outgoing.model,
                &outgoing.url,
                brief,
                &failure.message,
                started.elapsed().as_millis() as u64,
                0,
                usage,
            );
            return Err(with_audit_note(failure, note));
        }
    };
    let elapsed_ms = started.elapsed().as_millis() as u64;

    let mut limitations: Vec<String> = ASK_LIMITATIONS.iter().map(|line| line.to_string()).collect();
    if let Some(note) = record_audit_with_usage(
        store,
        AuditVerdict::Ok,
        &outgoing.model,
        &outgoing.url,
        brief,
        "",
        elapsed_ms,
        0,
        usage,
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
        attempts,
    })
}

/// 对话一次发送的结局（`FR-AI-25` 对话页签；与 [`AskReply`] 同构 —— 挡住 / 满额 / 真发出去）。
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "status", rename_all = "camelCase")]
pub enum ChatReply {
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
        /// 模型正文。
        text: String,
        /// 实际使用的模型名。
        model: String,
        /// 往返耗时（毫秒）。
        elapsed_ms: u64,
        /// 发完这一次之后的配额读数。
        quota: QuotaStatus,
        /// 已知缺口（如实显示）。
        limitations: Vec<String>,
        /// 这一发的**尝试账**（成功也带）。
        attempts: Vec<AttemptNote>,
        /// 这一段对话一共几条消息（含这一问；界面拿来显示轮次）。
        turns: usize,
        /// **真收到几段**（`FR-AI-16` ①：0 = 服务端无视 `stream`、整段回来；≥1 = 逐段到的）。
        deltas: usize,
    },
    /// 模型点了工具（`FR-AI-18`）：**还没执行**，等用户在卡片上逐件点允许 / 拒绝。
    ///
    /// `calls` 是**这一条回答里的全部调用**（可能多件）：一件都不许丢 —— 只认第一件、其余静默，
    /// 用户会以为模型只想读一个文件，而它其实还点了别的。
    /// 这一跳**真出过一次网**（配额与审计都记了），所以这三个读数一并交回 ——
    /// 用户看到的不是「什么都没发生」，而是「发了一次、模型要读文件、等你点」。
    ToolPending {
        /// 模型点的全部工具（名字 + 参数原文；界面只画路径，不猜）。空表不会出现。
        calls: Vec<ChatToolCall>,
        /// 这一跳模型同时说的正文（有的模型边说边点；空串表示没有）。
        text: String,
        /// 实际使用的模型名。
        model: String,
        /// 往返耗时（毫秒）。
        elapsed_ms: u64,
        /// 发完这一次之后的配额读数。
        quota: QuotaStatus,
        /// 这一发的尝试账。
        attempts: Vec<AttemptNote>,
        /// 这一段对话几条消息（含这一问）。
        turns: usize,
        /// 这一跳真收到几段正文。
        deltas: usize,
    },
}

/// 对话这一次的已知缺口（随结果一起回，界面照实说）。
/// 注：**会话落盘**（`FR-AI-17`）与**逐段流式**（`FR-AI-16` ①）都已从这份清单里摘掉 ——
/// 两条现在都是真接上的（`agent_chat_sessions.rs` + `ChatPanel`；`chat_stream` + 同一条 SSE 读法），
/// 留着旧话就成了假缺口。
pub const CHAT_LIMITATIONS: [&str; 3] = [
    "流是逐段到的：中途断掉时已经画出来的那部分会留着，但不会自动补全 —— 重发一次即可。",
    "模型给的语句只落在对话正文里，本应用**不执行**它 —— 要用就自己复制到编辑器里跑。",
    "工具只有一件只读的「读取工作区里的文件」：模型一条回答里可能连着点几件，每件都要你单独点允许或拒绝；不写文件、不执行语句。",
];

/// **对话这一次**（`FR-AI-25` 对话页签第一片）：把整段历史发出去，只回正文。
///
/// 与 `generate` / `ask` 共用同一套闸门 / 配额 / 审计 / 重试 —— 对话不是「第三条外发通道」，
/// 它只是**换了一份提示词与多轮历史**的同一条通道（关掉总开关，这里同样一条请求都发不出去）。
///
/// 实现上 = [`chat_stream`] 配一个「什么都不画」的 sink：**只有一条路**，
/// 否则「整段回来」与「逐段回来」会各自长出一套配额 / 审计写法。
pub fn chat(store: &AgentSettingsStore, turns: &[ChatMessage]) -> Result<ChatReply, DbFailure> {
    chat_stream(store, turns, &mut |_| {})
}

/// 对话这一次的**流式**版（`FR-AI-16` ①）：每收到一段正文就交给 `sink`，最终仍整段交回。
///
/// 四条口径（每条都有对应的代码形状）：
/// ① 闸门 / 配额 / 审计 / 重试**与整段版完全同一条**：这里不放行，就一条请求都不发；
/// ② **按行缓冲字节**再解 UTF-8 —— 按字节切字符串会把多字节字符切成烂字（`String::from_utf8_lossy`
///    遇到半截字符会给出替换符，且**不会报错**）；
/// ③ 服务端无视 `stream`（回一整段 JSON）⇒ 当「整段回来」解析，**不假装流式**（`deltas = 0`）；
/// ④ **已经画出去的东西不重试**：重试会把同一段再发一遍（用户看到重复文字）⇒ 只在还没吐出
///    任何片段时按策略重试；中途断了就把已收到的正文交回并如实说「可能被截断」。
pub fn chat_stream(
    store: &AgentSettingsStore,
    turns: &[ChatMessage],
    sink: &mut dyn FnMut(&str),
) -> Result<ChatReply, DbFailure> {
    chat_stream_with_carry(store, turns, &[], &[], sink)
}

/// **带工具状态**的对话（`FR-AI-18`）：与 [`chat_stream`] 完全同一条通道，
/// 只是这次请求里带着工具清单，可能带回「模型点了某件工具」。
///
/// `pending` = 上一跳模型点的**全部**工具 + 用户点完之后拿到的结果（空表 = 这一问的第一跳）。
/// **工具结果只从参数进来**：本层不执行任何工具（执行在 [`chat_tool_resume`] 那一侧），
/// 所以「模型想读什么」与「真读到了什么」是两条分开的路，谁也替不了谁。
pub fn chat_stream_with(
    store: &AgentSettingsStore,
    turns: &[ChatMessage],
    pending: &[(&ChatToolCall, &str)],
    sink: &mut dyn FnMut(&str),
) -> Result<ChatReply, DbFailure> {
    chat_stream_with_carry(store, turns, pending, &[], sink)
}

/// **带文件上下文**的那一条（`FR-AI-18` 收口）：`carry` = 用户批准读过、要带进这一发的文件正文。
///
/// 上下文只影响**装配**（拼进那一条 system 消息），闸门 / 配额 / 审计 / 重试一个字都没变 ——
/// 带上文件不等于多一条外发通道。超上限由领域层拒绝并报数（这里不吞、不改写那句话）。
pub fn chat_stream_with_carry(
    store: &AgentSettingsStore,
    turns: &[ChatMessage],
    pending: &[(&ChatToolCall, &str)],
    carry: &[CarriedFile],
    sink: &mut dyn FnMut(&str),
) -> Result<ChatReply, DbFailure> {
    let config = store.load()?;
    let question = turns
        .last()
        .map(|turn| turn.content.clone())
        .unwrap_or_default();
    if let Some(gate) = gate_refusal(store, &config, &question)? {
        return Ok(ChatReply::Blocked { gate });
    }
    let outgoing = build_chat_request_with_context(&config, turns, pending, carry).map_err(|err| DbFailure {
        message: err.to_string(),
        hint: "改一下这段对话（空消息 / 太长 / 结尾是模型的话）再发。".to_string(),
    })?;

    // 配额：与生成面 / 诊断面同一条台账（对话一样烧钱）。
    let quota = match quota_admission(store, &config, &question)? {
        Ok(quota) => quota,
        Err(quota) => return Ok(ChatReply::Throttled { quota }),
    };

    let started = Instant::now();
    let client = build_client(&config)?;
    let policy = RetryPolicy::from_config(&config);
    let mut attempts: Vec<AttemptNote> = Vec::new();
    let mut attempt_no: u32 = 1;
    let mut text = String::new();
    let mut deltas = 0usize;
    // 这一跳的 token 用量（`FR-AI-24`）：流里报了就取报的，没报就看整段回包；两处都没有 ⇒ 全 0。
    let mut usage = AuditUsage::default();
    // 这一跳模型点到的工具（流里逐段拼出来；`FR-AI-18`）。
    let mut calls: Vec<ChatToolCall>;
    // 只在成功读到回包时赋值（循环里那两处 `return` 不会走到下面）。
    let finished: bool;

    loop {
        // 重试同样真出网 ⇒ 第 2 次起每次尝试都再过一遍配额（第一次由上面记过账）。
        if attempt_no > 1 {
            match quota_admission(store, &config, &question) {
                Ok(Ok(_)) => {}
                Ok(Err(quota)) => {
                    return Err(DbFailure {
                        message: format!(
                            "还想再试一次，但本小时配额已满（上限 {} 次，已用 {} 次）：这一发没有发出去。前面已尝试 {} 次。",
                            quota.limit,
                            quota.used,
                            attempt_no - 1
                        ),
                        hint: format!(
                            "约 {} 分钟后才有空位；也可以把「每小时上限」调大。",
                            (quota.retry_after_secs + 59) / 60
                        ),
                    });
                }
                Err(err) => return Err(err),
            }
        }

        let attempt_started = Instant::now();
        let mut request = client
            .post(&outgoing.url)
            .header(reqwest::header::CONTENT_TYPE, "application/json")
            .body(outgoing.body.clone());
        // 本地端点免密钥：**重试时同样不带** Authorization（这条路只有一处）。
        if let Some(secret) = store.key_secret() {
            request = request.header(reqwest::header::AUTHORIZATION, format!("Bearer {secret}"));
        }

        let response = match request.send() {
            Ok(response) => response,
            Err(err) => {
                let timed_out = err.is_timeout();
                let class = classify_transport(timed_out, err.is_connect());
                let failure = DbFailure {
                    message: if timed_out {
                        format!(
                            "请求超时（{} 秒）：模型服务没有在时限内回话。",
                            config.timeout_secs
                        )
                    } else {
                        format!("请求发不出去：{err}")
                    },
                    hint: if timed_out {
                        "把「单次请求超时」调大，或换一个更近的端点。".to_string()
                    } else {
                        "确认端点地址与网络（远端还需代理 / 防火墙放行）；本地端点的服务是否在跑。"
                            .to_string()
                    },
                };
                attempt_no = match retry_or_fail(
                    store,
                    &outgoing,
                    &question,
                    failure,
                    attempt_started,
                    attempt_no,
                    class,
                    None,
                    None,
                    &policy,
                    &mut attempts,
                ) {
                    Ok(next) => next,
                    Err(stop) => return Err(stop),
                };
                continue;
            }
        };

        let status = response.status();
        if !status.is_success() {
            let retry_after = retry_after_secs(&response);
            let raw = response.text().unwrap_or_default();
            let class = classify_status(status.as_u16());
            let failure = DbFailure {
                message: format!("模型服务返回 HTTP {}：{}", status.as_u16(), excerpt(&raw, 300)),
                hint: "401 / 403 多为密钥不对或没有权限；404 多为端点路径不对（要的是 OpenAI 兼容的 /v1）；429 是配额或限流（这类会自动等一会儿再试）。"
                    .to_string(),
            };
            attempt_no = match retry_or_fail(
                store,
                &outgoing,
                &question,
                failure,
                attempt_started,
                attempt_no,
                class,
                Some(status.as_u16()),
                retry_after,
                &policy,
                &mut attempts,
            ) {
                Ok(next) => next,
                Err(stop) => return Err(stop),
            };
            continue;
        }

        match read_sse_stream(response, sink) {
            Ok(read) => {
                text = read.text;
                deltas += read.deltas;
                finished = read.finished;
                calls = read.calls;
                usage = if read.usage.is_known() {
                    read.usage
                } else {
                    parse_usage_text(&read.raw)
                };
                if text.is_empty() && calls.is_empty() {
                    // 服务端无视 `stream`（或回的是一整段 JSON）：先看有没有工具调用，再整段解析正文。
                    calls = parse_tool_calls(&read.raw);
                }
                if text.is_empty() && calls.is_empty() {
                    match agent_advisor::parse_reply(&read.raw) {
                        Ok(whole) => text = whole,
                        Err(err) => {
                            let failure = DbFailure {
                                message: err.to_string(),
                                hint: "换一个模型（有些模型把正文放在别的字段里），或改用「生成 SQL」那条路。"
                                    .to_string(),
                            };
                            let note = record_audit_with_usage(
                                store,
                                AuditVerdict::Failed,
                                &outgoing.model,
                                &outgoing.url,
                                &question,
                                &failure.message,
                                started.elapsed().as_millis() as u64,
                                0,
                                usage,
                            );
                            return Err(with_audit_note(failure, note));
                        }
                    }
                }
                attempts.push(AttemptNote::ok(attempt_no, Some(status.as_u16())));
                break;
            }
            Err(reason) => {
                let class = classify_transport(false, false);
                // 已经画出去的片段不能再重试（会把同一段再发一遍）⇒ 直接如实停在这里。
                if deltas > 0 || !text.is_empty() {
                    let failure = DbFailure {
                        message: format!("回包读到一半断了：{reason}"),
                        hint: "已经收到的部分留在对话里；重发一次就能补全。".to_string(),
                    };
                    let note = record_audit_with_usage(
                        store,
                        AuditVerdict::Failed,
                        &outgoing.model,
                        &outgoing.url,
                        &question,
                        &failure.message,
                        started.elapsed().as_millis() as u64,
                        0,
                        usage,
                    );
                    return Err(with_audit_note(failure, note));
                }
                let failure = DbFailure {
                    message: format!("回包读不出来：{reason}"),
                    hint: "重试一次；仍然不行就换端点。".to_string(),
                };
                attempt_no = match retry_or_fail(
                    store,
                    &outgoing,
                    &question,
                    failure,
                    attempt_started,
                    attempt_no,
                    class,
                    None,
                    None,
                    &policy,
                    &mut attempts,
                ) {
                    Ok(next) => next,
                    Err(stop) => return Err(stop),
                };
                continue;
            }
        }
    }

    let elapsed_ms = started.elapsed().as_millis() as u64;

    // 模型点了工具（`FR-AI-18`）：这一跳**真出过网**（配额、审计照记），然后**停下来等人逐件点** ——
    // 不自己执行、不替用户点。**全部**调用一起交回（只认第一件会让用户漏看别的）。
    // 执行与回灌在 `chat_tool_resume` 那一侧。
    if !calls.is_empty() {
        let mut limitations: Vec<String> = Vec::new();
        let names: Vec<&str> = calls.iter().map(|call| call.name.as_str()).collect();
        if let Some(note) = record_audit_with_usage(
            store,
            AuditVerdict::Ok,
            &outgoing.model,
            &outgoing.url,
            &question,
            &format!("工具调用 {} 件：{}（等用户逐件批准）", calls.len(), names.join(", ")),
            elapsed_ms,
            0,
            usage,
        ) {
            limitations.push(format!("这一次没能记进审计记录（{note}）—— 工具调用仍然可以继续。"));
        }
        return Ok(ChatReply::ToolPending {
            calls,
            text,
            model: outgoing.model,
            elapsed_ms,
            quota,
            attempts,
            turns: turns.len(),
            deltas,
        });
    }

    let mut limitations: Vec<String> = CHAT_LIMITATIONS.iter().map(|line| line.to_string()).collect();
    if deltas > 0 && !finished {
        // 流里没有收尾标记（`[DONE]` / `finish_reason`）⇒ 可能是中途被截断。正文照给，但要说清。
        limitations.push(
            "这一段回包没有收尾标记（没有 [DONE] / finish_reason）：可能是中途被截断的，重发一次可补全。"
                .to_string(),
        );
    }
    if let Some(note) = record_audit_with_usage(
        store,
        AuditVerdict::Ok,
        &outgoing.model,
        &outgoing.url,
        &question,
        "",
        elapsed_ms,
        0,
        usage,
    ) {
        limitations.push(format!(
            "这一次没能记进审计记录（{note}）—— 结果仍然可用，但「刚才发过什么」这条事后查不到。"
        ));
    }

    Ok(ChatReply::Answered {
        text,
        model: outgoing.model,
        elapsed_ms,
        quota,
        limitations,
        attempts,
        turns: turns.len(),
        deltas,
    })
}

/// 一次工具执行的**可见账**（界面卡片上如实显示「允许了没有、读到 / 写了多少」）。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolRun {
    /// 工具名（`read_file` / `write_file`）。
    pub name: String,
    /// 模型要的相对路径（原样回显，便于用户核对）。
    pub path: String,
    /// 用户点了允许还是拒绝。
    pub approved: bool,
    /// 真读到了 / 真写进去了（拒绝 / 越界 / 读不到都是 `false`）。
    pub ok: bool,
    /// 交给模型的字符数（读那件有意义；拒绝时为 0）。
    pub chars: usize,
    /// 是不是因为太长被截断了。
    pub truncated: bool,
    /// 读不到 / 越界 / 写不进去时的可读原因（空串 = 没问题）。
    pub problem: String,
    /// **当次真交给模型的那段正文**（拒绝 / 没读到时为空串）。
    ///
    /// 界面靠它把「读过的文件」带进后续请求（`FR-AI-18` 收口）：正文只在这一处产出，
    /// 界面不必再拼一遍 —— 拼两处就会有两份「模型看到的是什么」。
    pub content: String,
    /// 这一件是读还是写（`read` / `write`）—— 界面按它决定画「读到多少」还是「加了几行 / 减了几行」。
    pub kind: String,
    /// 真写到盘上的字节数（读那件恒为 0）。
    pub bytes: usize,
    /// 相比写入前多了几行（写那件有意义）。
    pub added: usize,
    /// 相比写入前少了几行（写那件有意义）。
    pub removed: usize,
    /// **撤销凭据**（写成功才有；空串 = 没有可撤销的）。
    ///
    /// 界面拿它调 `agent_write_undo` 把文件恢复到写之前 —— 前提是盘上还是我们写的那份。
    pub undo: String,
}

/// 用户逐件点完之后的结果：**每一件**的执行账 + 模型拿到结果后的最终回答。
///
/// `runs` 与当初的 `calls` 一一对应、顺序一致 —— 界面靠这个把「哪一行账」对回「哪一件工具」。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolResume {
    /// 这一批工具的执行账（每件一条，顺序同调用顺序）。
    pub runs: Vec<ToolRun>,
    /// 回灌之后模型的回答（与普通对话同一个 [`ChatReply`]；也可能再次点工具）。
    pub reply: ChatReply,
}

/// 交回模型的那段「被拒绝」正文：**让它别编**。
pub const TOOL_DENIED_NOTE: &str =
    "用户拒绝了这次读取。不要编造该文件的内容；请基于已有信息回答，并说明你需要哪部分内容、为什么。";

/// 写那件被拒绝时交回模型的正文（同样**让它别声称改过了**）。
pub const TOOL_WRITE_DENIED_NOTE: &str =
    "用户拒绝了这次写入，文件一个字都没改。不要声称已经修改或已经保存；请说明你打算改成什么、为什么，等用户下一次批准。";

/// 交给模型的单次工具正文上限（字符）。超了如实标注截断 —— 悄悄砍掉会让模型以为文件只有这么长。
pub const TOOL_RESULT_MAX_CHARS: usize = 8_000;

/// 用户逐件点完之后：执行（或记下拒绝）**全部**结果，**一次请求**回灌给模型（`FR-AI-18`）。
///
/// 三条口径：
/// ① **执行只在这一条路上**，且只认 [`CHAT_READ_FILE_TOOL`]：别的名字连读都不读；
/// ② `approvals` 与 `calls` 必须**逐件对齐**（条数不等 ⇒ 直接拒发，不默认成允许 / 拒绝）——
///    静默补一个 `false` 会让「少点了一件」看起来像「用户拒绝了」；
/// ③ 全部结果**一次回灌**：逐件各发一发 = 同一回答被拆成 N 次出网（N 次配额 / N 次审计），
///    而且模型看到的上下文是残缺的。
pub fn chat_tool_resume(
    store: &AgentSettingsStore,
    workspace: &str,
    turns: &[ChatMessage],
    calls: &[ChatToolCall],
    approvals: &[bool],
    carry: &[CarriedFile],
    sink: &mut dyn FnMut(&str),
) -> Result<ToolResume, DbFailure> {
    if calls.is_empty() {
        return Err(DbFailure {
            message: "没有待批的工具调用：这次一个字都没发。".to_string(),
            hint: "重新问一次；模型再点工具时会重新出卡片。".to_string(),
        });
    }
    if approvals.len() != calls.len() {
        return Err(DbFailure {
            message: format!(
                "批准结果与工具数量对不上（{} 件工具 / {} 个决定）：这次没有发出去。",
                calls.len(),
                approvals.len()
            ),
            hint: "每一件工具都要单独点允许或拒绝；全部点完才会一起交给模型。".to_string(),
        });
    }
    let mut runs: Vec<ToolRun> = Vec::with_capacity(calls.len());
    // 结果与调用一一对应（顺序一致）：回灌时 `tool_call_id` 逐件对齐。
    let mut results: Vec<(ChatToolCall, String)> = Vec::with_capacity(calls.len());
    let undo_dir = agent_undo_dir();
    for (call, approved) in calls.iter().zip(approvals.iter()) {
        // 写那件：只有批准了才动盘；拒绝 / 参数不全 / 越界都如实说，**不写半截**。
        if call.name.trim() == CHAT_WRITE_FILE_TOOL {
            let (path, content) = write_file_arguments(&call.arguments).unwrap_or_default();
            let write = if !approved {
                ToolWrite::refused(TOOL_WRITE_DENIED_NOTE, &path)
            } else if path.trim().is_empty() {
                ToolWrite::refused("模型没给路径（path 为空），文件一个字都没改", "")
            } else {
                write_workspace_file(workspace, &path, &content, &undo_dir)
            };
            runs.push(ToolRun {
                name: call.name.clone(),
                path: write.path.clone(),
                approved: *approved,
                ok: write.ok,
                chars: 0,
                truncated: false,
                problem: write.problem.clone(),
                content: String::new(),
                kind: "write".to_string(),
                bytes: write.bytes,
                added: write.added,
                removed: write.removed,
                undo: write.undo.clone(),
            });
            results.push((call.clone(), write.content));
            continue;
        }
        let path = read_file_path(&call.arguments).unwrap_or_default();
        let read = if !approved {
            ToolRead {
                content: TOOL_DENIED_NOTE.to_string(),
                chars: 0,
                truncated: false,
                ok: false,
                problem: String::new(),
            }
        } else if call.name.trim() != CHAT_READ_FILE_TOOL {
            ToolRead {
                content: format!(
                    "没有执行：工具「{}」不在白名单里（只允许 {CHAT_READ_FILE_TOOL} / {CHAT_WRITE_FILE_TOOL}）。",
                    call.name
                ),
                chars: 0,
                truncated: false,
                ok: false,
                problem: "不在白名单".to_string(),
            }
        } else {
            read_workspace_file(workspace, &path)
        };
        runs.push(ToolRun {
            name: call.name.clone(),
            path,
            approved: *approved,
            ok: read.ok,
            chars: read.chars,
            truncated: read.truncated,
            problem: read.problem.clone(),
            // 只有真读到了才把正文交回界面（拒绝 / 越界时那段是「没读到」的说明，不是文件内容）。
            content: if read.ok { read.content.clone() } else { String::new() },
            kind: "read".to_string(),
            bytes: 0,
            added: 0,
            removed: 0,
            undo: String::new(),
        });
        results.push((call.clone(), read.content));
    }
    let pending: Vec<(&ChatToolCall, &str)> = results
        .iter()
        .map(|(call, result)| (call, result.as_str()))
        .collect();
    let reply = chat_stream_with_carry(store, turns, &pending, carry, sink)?;
    Ok(ToolResume { runs, reply })
}

/// 读一次工作区里的文本文件（**只读、只认相对路径、不许跳出工作区**）。
struct ToolRead {
    content: String,
    chars: usize,
    truncated: bool,
    ok: bool,
    problem: String,
}

fn tool_read_refused(reason: &str) -> ToolRead {
    ToolRead {
        content: format!("没有读到：{reason}"),
        chars: 0,
        truncated: false,
        ok: false,
        problem: reason.to_string(),
    }
}

fn read_workspace_file(workspace: &str, path: &str) -> ToolRead {
    let root = workspace.trim();
    if root.is_empty() {
        return tool_read_refused("没有打开工作区，读不了文件");
    }
    if path.trim().is_empty() {
        return tool_read_refused("模型没给路径（path 为空）");
    }
    let relative = std::path::Path::new(path);
    if relative.is_absolute() {
        return tool_read_refused("只允许工作区里的相对路径，绝对路径一律不读");
    }
    if relative
        .components()
        .any(|part| matches!(part, std::path::Component::ParentDir | std::path::Component::RootDir | std::path::Component::Prefix(_)))
    {
        return tool_read_refused("路径里有 .. / 前缀：只允许工作区内部的路径");
    }
    let root_path = std::path::Path::new(root);
    let Ok(root_real) = root_path.canonicalize() else {
        return tool_read_refused("工作区路径读不到");
    };
    let joined = root_path.join(relative);
    let Ok(target) = joined.canonicalize() else {
        return tool_read_refused(&format!("工作区里没有这个文件：{path}"));
    };
    if !target.starts_with(&root_real) {
        return tool_read_refused("这个路径落在工作区外面，不读");
    }
    if !target.is_file() {
        return tool_read_refused("这不是一个文件（目录不读）");
    }
    let Ok(bytes) = std::fs::read(&target) else {
        return tool_read_refused("文件读不出来（没有权限或已被占用）");
    };
    if bytes.iter().any(|byte| *byte == 0) {
        return tool_read_refused("这不是文本文件（含二进制内容），没有读取");
    }
    // 文件名出现在给模型的正文里：让它知道读的是哪一份（路径已经校验过在工作区内）。
    let shown = path.trim().replace('\\', "/");
    let text = String::from_utf8_lossy(&bytes).to_string();
    let total = text.chars().count();
    let (body, truncated) = if total > TOOL_RESULT_MAX_CHARS {
        let cut: String = text.chars().take(TOOL_RESULT_MAX_CHARS).collect();
        (cut, true)
    } else {
        (text, false)
    };
    let mut content = format!("文件 {shown}（共 {total} 字符）：\n{body}");
    if truncated {
        content.push_str(&format!(
            "\n\n（已截断：只给了前 {TOOL_RESULT_MAX_CHARS} 字符，共 {total} 字符。需要更多就分段问。）"
        ));
    }
    ToolRead {
        chars: body.chars().count(),
        content,
        truncated,
        ok: true,
        problem: String::new(),
    }
}

// ── 写文件（`FR-AI-20` / `FR-AI-25`：差异预览 → 批准 → 落盘 → 撤销）──────────────────
//
// 四条口径：
// ① **批准前先看差异**：预览与落盘走**同一个**路径校验（`resolve_write_target`），预览说能写、
//    落盘就一定还是那个目标 —— 两条各写一份校验，就会出现「卡片上说没问题、点下去越界」；
// ② **差异 = 裁掉公共前缀 / 后缀剩下的改动段**：不做 LCS，但单点修改就是精确的；
//    多处修改会并成一段「整段被替换」—— 如实报行数，不假装是逐行最小差异；
// ③ **撤销要有前提**：落盘前把旧正文与「写完之后的样子」（长度 + 校验和）一起存下来，
//    撤销时先核盘上还是我们写的那份，对不上就拒绝（否则会吃掉用户手工改的内容）；
// ④ 写盘是本地动作：**不产生外发**，不新增审计条目、不动配额。

/// 单文件写盘上限（字节）。超了就拒 —— 对话里一次改一份几十 MB 的文件不是本片想干的事。
pub const TOOL_WRITE_MAX_BYTES: usize = 1_048_576;

/// 预览里旧 / 新各最多画多少行（再长就如实说「还有 N 行没逐行列出」）。
pub const TOOL_DIFF_PREVIEW_LINES: usize = 20;

/// 逐行差异的行数读数。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
struct LineDiff {
    old_lines: usize,
    new_lines: usize,
    added: usize,
    removed: usize,
}

/// 按行切（末尾换行不算多一行；`\r\n` 的 `\r` 去掉，否则 Windows 上每行都会被算成「改了」）。
fn split_lines(text: &str) -> Vec<&str> {
    let mut lines: Vec<&str> = text
        .split('\n')
        .map(|line| line.strip_suffix('\r').unwrap_or(line))
        .collect();
    if lines.last().map(|line| line.is_empty()).unwrap_or(false) {
        lines.pop();
    }
    lines
}

/// 裁掉公共前缀 / 后缀，返回（行数读数, 被删的旧行, 新增的新行）。
///
/// **不做 LCS**：单点修改就是精确的最小差异；多处修改会并成一段「中间被整段替换」——
/// 这对「批准前看一眼」够用，且不会为了好看而把两处改动拆错。
fn line_diff<'a>(old: &'a str, new: &'a str) -> (LineDiff, Vec<&'a str>, Vec<&'a str>) {
    let old_lines = split_lines(old);
    let new_lines = split_lines(new);
    let mut prefix = 0usize;
    while prefix < old_lines.len() && prefix < new_lines.len() && old_lines[prefix] == new_lines[prefix] {
        prefix += 1;
    }
    let mut suffix = 0usize;
    while suffix < old_lines.len() - prefix
        && suffix < new_lines.len() - prefix
        && old_lines[old_lines.len() - 1 - suffix] == new_lines[new_lines.len() - 1 - suffix]
    {
        suffix += 1;
    }
    let removed: Vec<&str> = old_lines[prefix..old_lines.len() - suffix].to_vec();
    let added: Vec<&str> = new_lines[prefix..new_lines.len() - suffix].to_vec();
    (
        LineDiff {
            old_lines: old_lines.len(),
            new_lines: new_lines.len(),
            added: added.len(),
            removed: removed.len(),
        },
        removed,
        added,
    )
}

/// 预览里画出来的差异正文（`- 旧行` / `+ 新行`；超长的部分如实说没画）。
fn render_diff(removed: &[&str], added: &[&str]) -> String {
    let mut out = String::new();
    for line in removed.iter().take(TOOL_DIFF_PREVIEW_LINES) {
        out.push_str("- ");
        out.push_str(line);
        out.push('\n');
    }
    if removed.len() > TOOL_DIFF_PREVIEW_LINES {
        out.push_str(&format!(
            "- …（还有 {} 行被删掉，未逐行列出）\n",
            removed.len() - TOOL_DIFF_PREVIEW_LINES
        ));
    }
    for line in added.iter().take(TOOL_DIFF_PREVIEW_LINES) {
        out.push_str("+ ");
        out.push_str(line);
        out.push('\n');
    }
    if added.len() > TOOL_DIFF_PREVIEW_LINES {
        out.push_str(&format!(
            "+ …（还有 {} 行是新增的，未逐行列出）\n",
            added.len() - TOOL_DIFF_PREVIEW_LINES
        ));
    }
    out
}

/// 批准前给用户看的差异（`FR-AI-20`「写盘前先出差异」）。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WritePreview {
    /// 模型要写的相对路径（原样回显）。
    pub path: String,
    /// 盘上原本有没有这个文件（`false` = 新建）。
    pub existed: bool,
    /// 相比现在多了几行。
    pub added: usize,
    /// 相比现在少了几行。
    pub removed: usize,
    /// 现在几行。
    pub old_lines: usize,
    /// 写完之后几行。
    pub new_lines: usize,
    /// 逐行差异预览（空串 = 没有差异：内容相同 / 新建空文件）。
    pub diff: String,
    /// 写不进去的原因（空 = 没问题）。**预览阶段就把不可能写的情况说清**，别等点了允许才拒。
    pub problem: String,
}

/// 算一份「如果现在写，会变成什么样」（**不落盘**）。
pub fn write_preview(workspace: &str, path: &str, content: &str) -> WritePreview {
    let shown = path.trim().replace('\\', "/");
    match resolve_write_target(workspace, path) {
        Err(problem) => WritePreview {
            path: shown,
            existed: false,
            added: 0,
            removed: 0,
            old_lines: 0,
            new_lines: 0,
            diff: String::new(),
            problem,
        },
        Ok((_target, existing)) => {
            let old = existing.unwrap_or_default();
            let (stat, removed, added) = line_diff(&old, content);
            WritePreview {
                path: shown,
                existed: stat.old_lines > 0 || !old.is_empty(),
                added: stat.added,
                removed: stat.removed,
                old_lines: stat.old_lines,
                new_lines: stat.new_lines,
                diff: render_diff(&removed, &added),
                problem: String::new(),
            }
        }
    }
}

/// 解析一次写入的目标：**预览与落盘共用这一份校验**（各写一份就会两处不一致）。
///
/// 返回（落盘用的绝对路径, 盘上现有正文）。现有正文是 `None` = 新建。
fn resolve_write_target(workspace: &str, path: &str) -> Result<(std::path::PathBuf, Option<String>), String> {
    let root = workspace.trim();
    if root.is_empty() {
        return Err("没有打开工作区，写不了文件".to_string());
    }
    let relative = std::path::Path::new(path.trim());
    if path.trim().is_empty() {
        return Err("模型没给路径（path 为空）".to_string());
    }
    if relative.is_absolute() {
        return Err("只允许工作区里的相对路径，绝对路径一律不写".to_string());
    }
    if relative.components().any(|part| {
        matches!(
            part,
            std::path::Component::ParentDir
                | std::path::Component::RootDir
                | std::path::Component::Prefix(_)
        )
    }) {
        return Err("路径里有 .. / 前缀：只允许工作区内部的路径".to_string());
    }
    let root_path = std::path::Path::new(root);
    let root_real = root_path
        .canonicalize()
        .map_err(|_| "工作区路径读不到".to_string())?;
    let joined = root_path.join(relative);
    let Some(name) = joined.file_name() else {
        return Err("路径没有文件名（不能写到一个目录上）".to_string());
    };
    let Some(parent) = joined.parent() else {
        return Err("路径没有父目录".to_string());
    };
    // 父目录必须已存在（本片不顺手建目录：建了目录撤销就删不干净）。
    let parent_real = parent
        .canonicalize()
        .map_err(|_| format!("目标目录不存在：{}（本片不自动建目录）", parent.display()))?;
    if !parent_real.starts_with(&root_real) {
        return Err("这个路径落在工作区外面，不写".to_string());
    }
    let target = parent_real.join(name);
    if target.is_dir() {
        return Err("那是一个目录，不写".to_string());
    }
    if !target.exists() {
        return Ok((target, None));
    }
    let bytes = std::fs::read(&target).map_err(|_| "目标文件读不出来（没有权限或已被占用）".to_string())?;
    if bytes.iter().any(|byte| *byte == 0) {
        return Err("目标不是文本文件（含二进制内容），没有覆盖".to_string());
    }
    if bytes.len() > TOOL_WRITE_MAX_BYTES {
        return Err(format!(
            "目标文件 {} 字节，超过单次写入上限 {TOOL_WRITE_MAX_BYTES} 字节，没有覆盖",
            bytes.len()
        ));
    }
    let text = String::from_utf8(bytes).map_err(|_| "目标不是 UTF-8 文本，没有覆盖".to_string())?;
    Ok((target, Some(text)))
}

/// 一次写盘的结果（交给模型 / 交给界面的两份说法都在这里产出，别处不再拼）。
struct ToolWrite {
    /// 回显给界面的路径（模型原话，斜杠统一）。
    path: String,
    /// 回灌给模型的说明（成功 / 失败都是完整一句话）。
    content: String,
    ok: bool,
    problem: String,
    bytes: usize,
    added: usize,
    removed: usize,
    /// 撤销凭据（空 = 不能撤销）。
    undo: String,
}

impl ToolWrite {
    fn refused(note: &str, path: &str) -> Self {
        let shown = path.trim().replace('\\', "/");
        let reason = if path.trim().is_empty() {
            "没给路径".to_string()
        } else {
            shown.clone()
        };
        ToolWrite {
            path: shown,
            content: format!("没有写入：{note}"),
            ok: false,
            problem: if note.is_empty() {
                format!("没有写入：{reason}")
            } else {
                note.to_string()
            },
            bytes: 0,
            added: 0,
            removed: 0,
            undo: String::new(),
        }
    }
}

/// 撤销记录（存在 `%APPDATA%\DoyahStudio\agent-undo\<token>.json`）。
///
/// `after_sum` 是**非加密校验和**（FNV-1a 64）：只用来回答「盘上还是不是我们写的那份」，
/// 不当完整性证明用。
#[derive(Debug, Clone, Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct UndoRecord {
    token: String,
    workspace: String,
    path: String,
    /// 写之前有没有这个文件（没有 ⇒ 撤销 = 删掉它）。
    existed: bool,
    /// 写之前的正文（`existed = false` 时为空串）。
    before: String,
    /// 写完之后盘上的字节数。
    after_len: usize,
    /// 写完之后盘上的校验和（十六进制）。
    after_sum: String,
}

/// 撤销记录目录（与对话会话同一层：`%APPDATA%\DoyahStudio\...`）。
pub fn agent_undo_dir() -> std::path::PathBuf {
    let base = match std::env::var("APPDATA") {
        Ok(value) if !value.trim().is_empty() => std::path::PathBuf::from(value),
        _ => std::path::PathBuf::from("."),
    };
    base.join("DoyahStudio").join("agent-undo")
}

/// FNV-1a 64（只用于「文件有没有被改过」这个判断）。
fn fnv1a(bytes: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in bytes {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
}

/// 撤销凭据 = 毫秒时间戳 + 进程内自增（同毫秒两次写入也不会撞）。
fn next_undo_token() -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let millis = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    format!("{millis}-{}", COUNTER.fetch_add(1, Ordering::Relaxed))
}

/// 写一次工作区里的文本文件（**沙箱与预览同源**：`resolve_write_target`）。
fn write_workspace_file(
    workspace: &str,
    path: &str,
    content: &str,
    undo_dir: &std::path::Path,
) -> ToolWrite {
    let shown = path.trim().replace('\\', "/");
    let (target, existing) = match resolve_write_target(workspace, path) {
        Ok(found) => found,
        Err(problem) => {
            return ToolWrite {
                path: shown.clone(),
                content: format!("没有写入 {shown}：{problem}"),
                ok: false,
                problem,
                bytes: 0,
                added: 0,
                removed: 0,
                undo: String::new(),
            }
        }
    };
    if content.len() > TOOL_WRITE_MAX_BYTES {
        let problem = format!(
            "要写的内容 {} 字节，超过单次写入上限 {TOOL_WRITE_MAX_BYTES} 字节，没有写",
            content.len()
        );
        return ToolWrite {
            path: shown.clone(),
            content: format!("没有写入 {shown}：{problem}"),
            ok: false,
            problem,
            bytes: 0,
            added: 0,
            removed: 0,
            undo: String::new(),
        };
    }
    let before = existing.clone().unwrap_or_default();
    let (stat, _removed, _added) = line_diff(&before, content);
    if let Err(error) = std::fs::write(&target, content.as_bytes()) {
        let problem = format!("写不进去（{error}）");
        return ToolWrite {
            path: shown.clone(),
            content: format!("没有写入 {shown}：{problem}"),
            ok: false,
            problem,
            bytes: 0,
            added: 0,
            removed: 0,
            undo: String::new(),
        };
    }
    // 写完再记撤销凭据：记不下来也**不改口说没写** —— 如实说「写了但撤不回」。
    let record = UndoRecord {
        token: next_undo_token(),
        workspace: workspace.trim().to_string(),
        path: shown.clone(),
        existed: existing.is_some(),
        before,
        after_len: content.len(),
        after_sum: format!("{:016x}", fnv1a(content.as_bytes())),
    };
    let undo = match store_undo_record(undo_dir, &record) {
        Ok(token) => token,
        Err(error) => {
            return ToolWrite {
                path: shown.clone(),
                content: format!(
                    "已写入 {shown}（旧 {} 行 → 新 {} 行，+{} / -{}），但撤销记录没落下（{error}）：这一次改不回去。",
                    stat.old_lines, stat.new_lines, stat.added, stat.removed
                ),
                ok: true,
                problem: format!("已写入，但撤销记录没落下（{error}）"),
                bytes: content.len(),
                added: stat.added,
                removed: stat.removed,
                undo: String::new(),
            }
        }
    };
    ToolWrite {
        path: shown.clone(),
        content: format!(
            "已写入文件 {shown}（旧 {} 行 → 新 {} 行，+{} / -{}，{} 字节）。用户可以在界面上撤销这一次写入。",
            stat.old_lines,
            stat.new_lines,
            stat.added,
            stat.removed,
            content.len()
        ),
        ok: true,
        problem: String::new(),
        bytes: content.len(),
        added: stat.added,
        removed: stat.removed,
        undo,
    }
}

fn store_undo_record(dir: &std::path::Path, record: &UndoRecord) -> Result<String, String> {
    std::fs::create_dir_all(dir).map_err(|error| format!("建不了记录目录（{error}）"))?;
    let text = serde_json::to_string(record).map_err(|error| format!("记录写不成 JSON（{error}）"))?;
    let path = dir.join(format!("{}.json", record.token));
    std::fs::write(&path, text).map_err(|error| format!("记录文件写不进去（{error}）"))?;
    Ok(record.token.clone())
}

/// 撤销一次写入的结果（界面照实显示：恢复成了什么 / 删掉了什么）。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UndoResult {
    /// 撤销的是哪个文件（相对路径）。
    pub path: String,
    /// 恢复成了写之前的正文。
    pub restored: bool,
    /// 写之前本来没有这个文件 ⇒ 撤销 = 把它删掉。
    pub removed: bool,
    /// 一句话交代（含行数），界面直接显示。
    pub note: String,
}

/// 撤销一次写入（`FR-AI-25`「差异应用 / 撤销」）。
///
/// **前提**：盘上还是我们写的那份（长度 + 校验和都对得上）。对不上就拒绝 ——
/// 用户中途手工改过，撤销会把那些改动一起吃掉。
pub fn undo_write(dir: &std::path::Path, token: &str) -> Result<UndoResult, DbFailure> {
    let clean = token.trim();
    if clean.is_empty() || clean.len() > 64 || !clean.chars().all(|ch| ch.is_ascii_alphanumeric() || ch == '-') {
        return Err(DbFailure {
            message: "撤销凭据不合法：没有动任何文件。".to_string(),
            hint: "重新让助手写一次，界面上会重新给出「撤销」按钮。".to_string(),
        });
    }
    let path = dir.join(format!("{clean}.json"));
    let raw = std::fs::read_to_string(&path).map_err(|_| DbFailure {
        message: "找不到这一次写入的撤销记录：没有动任何文件。".to_string(),
        hint: "撤销只在记录还在时可用（记录目录被清过就回不去了）。".to_string(),
    })?;
    let record: UndoRecord = serde_json::from_str(&raw).map_err(|error| DbFailure {
        message: format!("撤销记录读不出来（{error}）：没有动任何文件。"),
        hint: "记录文件损坏了；需要手动把文件改回去。".to_string(),
    })?;
    let (target, current) = resolve_write_target(&record.workspace, &record.path).map_err(|problem| DbFailure {
        message: format!("现在找不到那个文件了（{problem}）：没有动任何文件。"),
        hint: "文件被删掉 / 工作区换了之后，撤销需要手动处理。".to_string(),
    })?;
    let Some(current_text) = current else {
        return Err(DbFailure {
            message: "文件现在不在盘上：没有动任何文件。".to_string(),
            hint: "它可能是你手工删掉的；要恢复请自己新建一份。".to_string(),
        });
    };
    let same = current_text.len() == record.after_len
        && format!("{:016x}", fnv1a(current_text.as_bytes())) == record.after_sum;
    if !same {
        return Err(DbFailure {
            message: "文件在写入之后被改过（长度 / 校验和对不上）：没有撤销，以免覆盖你后来的修改。".to_string(),
            hint: "确认那些改动可以丢掉，再手工把内容改回去。".to_string(),
        });
    }
    let removed = !record.existed;
    if removed {
        std::fs::remove_file(&target).map_err(|error| DbFailure {
            message: format!("删不掉这个文件（{error}）：没有撤销。"),
            hint: "它可能正被别的程序占用；关掉之后重试。".to_string(),
        })?;
    } else {
        std::fs::write(&target, record.before.as_bytes()).map_err(|error| DbFailure {
            message: format!("写不回旧内容（{error}）：没有撤销。"),
            hint: "检查文件权限 / 是否被占用后重试。".to_string(),
        })?;
    }
    // 记录用完即删：同一个凭据撤两次会得到「找不到记录」，不会第二次乱动文件。
    let _ = std::fs::remove_file(&path);
    let note = if removed {
        format!("已撤销：{} 是这次新建的，已删除。", record.path)
    } else {
        format!(
            "已撤销：{} 已恢复成写入前的 {} 行。",
            record.path,
            split_lines(&record.before).len()
        )
    };
    Ok(UndoResult {
        path: record.path,
        restored: !removed,
        removed,
        note,
    })
}


/// 一次失败的**留痕 + 决定再试还是停**（流式与整段两条路共用，避免各写一份重试账）。
///
/// 成功时回**下一次的尝试号**；该停时回最终失败（已把「试了几次、为什么停」写进消息）。
#[allow(clippy::too_many_arguments)]
fn retry_or_fail(
    store: &AgentSettingsStore,
    outgoing: &Outgoing,
    summary: &str,
    failure: DbFailure,
    attempt_started: Instant,
    attempt_no: u32,
    class: RetryClass,
    status: Option<u16>,
    retry_after: Option<u64>,
    policy: &RetryPolicy,
    attempts: &mut Vec<AttemptNote>,
) -> Result<u32, DbFailure> {
    let detail = failure.message.clone();
    let note = record_audit(
        store,
        AuditVerdict::Failed,
        &outgoing.model,
        &outgoing.url,
        summary,
        &detail,
        attempt_started.elapsed().as_millis() as u64,
        0,
    );
    let failure = with_audit_note(failure, note);
    match next_delay(policy, attempt_no, class, retry_after) {
        Some(delay) => {
            attempts.push(AttemptNote::failed(attempt_no, class, status, detail, delay));
            std::thread::sleep(Duration::from_millis(delay));
            Ok(attempt_no + 1)
        }
        None => {
            attempts.push(AttemptNote::failed(attempt_no, class, status, detail, 0));
            Err(stop_note(failure, attempts, class))
        }
    }
}

/// SSE 里的一帧（只认 OpenAI 兼容的那几种）。
#[derive(Debug, Clone, PartialEq, Eq)]
enum SseEvent {
    /// 一段正文增量。
    Delta(String),
    /// `data: [DONE]`。
    Done,
    /// `finish_reason` 非空（有的服务端不发 `[DONE]`，只给这个）。
    Finished,
    /// 服务端把错误塞在流里。
    Error(String),
    /// 一段工具调用增量（`FR-AI-18`）：名字 / 参数都会**分几帧到**，按 `index` 拼。
    ToolCall {
        /// 第几件（同一条回包里可能并列多件）。
        index: usize,
        /// 调用 id（只有第一帧带）。
        id: Option<String>,
        /// 工具名（可能分帧拼）。
        name: Option<String>,
        /// 参数 JSON 的**片段**（必须原样拼接，不能逐帧解析）。
        arguments: String,
    },
    /// 服务端在这一帧里报了 token 用量（`FR-AI-24`；多数端点放在最后一帧，`choices` 为空）。
    Usage(AuditUsage),
}

/// 读一段流式回包的结果。
struct StreamRead {
    /// 整段原始字节解出来的文本（没有 SSE 帧时用它整段解析）。
    raw: String,
    /// 拼起来的正文。
    text: String,
    /// 真收到几段。
    deltas: usize,
    /// 有没有收尾标记。
    finished: bool,
    /// 拼出来的工具调用（`FR-AI-18`；空 = 这一跳没点工具）。
    calls: Vec<ChatToolCall>,
    /// 这一次的 token 用量（`FR-AI-24`；流里没报 ⇒ 全 0）。
    usage: AuditUsage,
}

/// 按行读 SSE：命中 `data:` 就交一段给 `sink`。
///
/// **按行缓冲字节**再解码：网络读到的块边界会落在多字节字符中间，先切字符串就会烂字
/// （`from_utf8_lossy` 悄悄替换成 U+FFFD，不报错）。行边界（`\n`）在 UTF-8 里不会落在字符内部
/// ⇒ 只有整行解码才是安全的。
fn read_sse_stream(
    mut response: reqwest::blocking::Response,
    sink: &mut dyn FnMut(&str),
) -> Result<StreamRead, String> {
    let mut raw_bytes: Vec<u8> = Vec::new();
    let mut line: Vec<u8> = Vec::new();
    let mut buf = [0u8; 4096];
    let mut text = String::new();
    let mut deltas = 0usize;
    let mut finished = false;
    let mut calls: Vec<ChatToolCall> = Vec::new();
    let mut usage = AuditUsage::default();
    loop {
        let read = response
            .read(&mut buf)
            .map_err(|err| format!("{err}"))?;
        if read == 0 {
            break;
        }
        raw_bytes.extend_from_slice(&buf[..read]);
        for &byte in &buf[..read] {
            if byte == b'\n' {
                let current = String::from_utf8_lossy(&line).to_string();
                line.clear();
                for event in parse_sse_line(&current) {
                    apply_sse_event(
                        event,
                        &mut text,
                        &mut deltas,
                        &mut finished,
                        &mut calls,
                        &mut usage,
                        sink,
                    )?;
                }
            } else {
                line.push(byte);
            }
        }
    }
    // 最后一行可能没有换行符收尾（服务端断开 / 省略末尾换行）。
    if !line.is_empty() {
        let current = String::from_utf8_lossy(&line).to_string();
        for event in parse_sse_line(&current) {
            apply_sse_event(
                event,
                &mut text,
                &mut deltas,
                &mut finished,
                &mut calls,
                &mut usage,
                sink,
            )?;
        }
    }
    Ok(StreamRead {
        raw: String::from_utf8_lossy(&raw_bytes).to_string(),
        text,
        deltas,
        finished,
        calls,
        usage,
    })
}

/// 把一帧落到正文 / 段数 / 收尾标记上，并交给 `sink`。
fn apply_sse_event(
    event: SseEvent,
    text: &mut String,
    deltas: &mut usize,
    finished: &mut bool,
    calls: &mut Vec<ChatToolCall>,
    usage: &mut AuditUsage,
    sink: &mut dyn FnMut(&str),
) -> Result<(), String> {
    match event {
        SseEvent::Delta(chunk) => {
            text.push_str(&chunk);
            *deltas += 1;
            sink(&chunk);
        }
        SseEvent::ToolCall {
            index,
            id,
            name,
            arguments,
        } => {
            // 按 index 拼：同一件的名字与参数会分几帧到，参数只能**原样拼接**（逐帧解析必然失败）。
            while calls.len() <= index {
                calls.push(ChatToolCall {
                    id: String::new(),
                    name: String::new(),
                    arguments: String::new(),
                });
            }
            let slot = &mut calls[index];
            if let Some(id) = id {
                if slot.id.is_empty() {
                    slot.id = id;
                }
            }
            if let Some(name) = name {
                slot.name.push_str(&name);
            }
            slot.arguments.push_str(&arguments);
        }
        SseEvent::Done | SseEvent::Finished => *finished = true,
        SseEvent::Usage(reported) => {
            // 只认**非零**的那一份：有的端点先发一帧 `{"usage":{"prompt_tokens":0,...}}` 占位，
            // 后一帧才给真数 —— 用零去覆盖真数等于把成本抹掉。
            if reported.is_known() {
                *usage = reported;
            }
        }
        SseEvent::Error(message) => {
            return Err(format!("模型服务在流里回了错误：{message}"));
        }
    }
    Ok(())
}

/// 解析一行 SSE（`FR-AI-18` 第二片：**一行可以出多帧事件**，所以回 `Vec`）。
///
/// 为什么不是 `Option`：`delta.tool_calls` 在协议里是**数组**，一帧里并列多件是合法的
/// （有的端点第一帧就把所有调用的 name 一起给出）。旧实现每行只取第一件、其余静默丢掉 ——
/// 用户看到「模型只想读一个文件」，其实它点了两个，第二个既没执行也没人知道。
///
/// **不是 `data:` 行就回空表**（`event:` / 注释 / 空行都不算错）。
fn parse_sse_line(line: &str) -> Vec<SseEvent> {
    let Some(payload) = line.trim_end_matches('\r').strip_prefix("data:") else {
        return Vec::new();
    };
    let payload = payload.trim();
    if payload.is_empty() {
        return Vec::new();
    }
    if payload == "[DONE]" {
        return vec![SseEvent::Done];
    }
    let Ok(value) = serde_json::from_str::<serde_json::Value>(payload) else {
        return Vec::new();
    };
    if let Some(message) = value
        .get("error")
        .and_then(|error| error.get("message"))
        .and_then(|message| message.as_str())
    {
        return vec![SseEvent::Error(message.to_string())];
    }
    let choice = value.get("choices").and_then(|choices| choices.get(0));
    let mut events: Vec<SseEvent> = Vec::new();
    // 工具调用增量（`FR-AI-18`）：位置在 `delta.tool_calls[i]`，名字与参数可能**分几帧**到。
    // 同一帧里并列的**每一件都要出**（`index` 决定它是第几件，交给 apply 侧按 index 拼）。
    if let Some(list) = choice
        .and_then(|choice| choice.get("delta"))
        .and_then(|delta| delta.get("tool_calls"))
        .and_then(|calls| calls.as_array())
    {
        for item in list {
            let index = item
                .get("index")
                .and_then(|index| index.as_u64())
                .unwrap_or(0) as usize;
            let id = item
                .get("id")
                .and_then(|id| id.as_str())
                .filter(|id| !id.is_empty())
                .map(|id| id.to_string());
            let function = item.get("function");
            let name = function
                .and_then(|function| function.get("name"))
                .and_then(|name| name.as_str())
                .filter(|name| !name.is_empty())
                .map(|name| name.to_string());
            let arguments = function
                .and_then(|function| function.get("arguments"))
                .and_then(|arguments| arguments.as_str())
                .unwrap_or("")
                .to_string();
            if id.is_some() || name.is_some() || !arguments.is_empty() {
                events.push(SseEvent::ToolCall {
                    index,
                    id,
                    name,
                    arguments,
                });
            }
        }
    }
    if let Some(chunk) = choice
        .and_then(|choice| choice.get("delta"))
        .and_then(|delta| delta.get("content"))
        .and_then(|content| content.as_str())
    {
        if !chunk.is_empty() {
            events.push(SseEvent::Delta(chunk.to_string()));
        }
    }
    // 收尾标记只在**这一帧没有别的内容**时补：有工具调用 / 正文的帧本来就不是收尾帧。
    if events.is_empty() {
        let reason = choice
            .and_then(|choice| choice.get("finish_reason"))
            .and_then(|reason| reason.as_str())
            .unwrap_or("");
        if !reason.is_empty() {
            events.push(SseEvent::Finished);
        }
    }
    // token 用量（`FR-AI-24`）：放在最后 —— 它是**附带读数**，不许影响「这一帧是不是收尾帧」的判断。
    let usage = parse_usage(&value);
    if usage.is_known() {
        events.push(SseEvent::Usage(usage));
    }
    events
}

/// 记一条审计（`FR-AI-09`）：**四种结局都记** —— 成功、失败、被闸门挡住、被配额挡住。
///
/// 返回 `Option<String>` = 写不进去时的可读原因（调用方必须**说出来**，别咽掉）；
/// 但没有理由因为它而拒发 / 改判：审计是事后交代，不是通行证。
///
/// 这一档 = **没拿到用量**的那几次（连不上 / HTTP 非 2xx / 被挡住）：真的没有 token 可记，
/// 按 0 落盘，界面画「没记到」。拿到回包的路径一律走 [`record_audit_with_usage`]。
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
    record_audit_with_usage(
        store,
        verdict,
        model,
        endpoint,
        question,
        detail,
        duration_ms,
        table_count,
        AuditUsage::default(),
    )
}

/// 记一条审计并带上 token 用量（`FR-AI-24` ②）—— **写入口只有这一个函数**。
///
/// 两个函数不是两条路：上面那个是「用量未知」的转发口，落盘、抹凭据、截断、淘汰全在这里。
#[allow(clippy::too_many_arguments)]
fn record_audit_with_usage(
    store: &AgentSettingsStore,
    verdict: AuditVerdict,
    model: &str,
    endpoint: &str,
    question: &str,
    detail: &str,
    duration_ms: u64,
    table_count: usize,
    usage: AuditUsage,
) -> Option<String> {
    let mut ledger = store.load_audit();
    ledger.append(
        AuditRecord::record(
            verdict,
            model,
            endpoint,
            question,
            detail,
            duration_ms,
            table_count,
            now_secs(),
        )
        .with_usage(usage),
    );
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
        let (endpoint, _seen) = fake_endpoint_script(vec![
            ("500 Internal Server Error", leaked),
            ("500 Internal Server Error", leaked),
            ("500 Internal Server Error", leaked),
        ]);
        let store = tmp_store("audit-failed");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                retry_max: 2,
                retry_max_ms: 500,
                ..Default::default()
            })
            .unwrap();

        assert!(
            generate(&store, "随便", &[]).is_err(),
            "500 不该被当成成功"
        );

        // 重试也真出网 ⇒ **每次尝试各一条**（3 次全失败 = 3 条），一条都不能省。
        let records = store.load_audit().all_recent();
        assert_eq!(records.len(), 3, "每次尝试都要留一条：{records:?}");
        for record in &records {
            assert_eq!(record.verdict, AuditVerdict::Failed);
            assert!(record.verdict.left_the_machine(), "连接已经发出去了");
            assert!(record.detail.contains("500"), "{}", record.detail);
            assert!(
                !record.detail.contains("hunter2"),
                "服务端原话里的口令被原样写进了审计：{}",
                record.detail
            );
        }
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

    /// 假端点：按脚本**依次**回多段响应（一次一个连接），收到的请求原文逐条记下来。
    ///
    /// 重试要能被数出来 —— 用只能 accept 一次的 `fake_endpoint` 测重试，第二次会撞「连接被拒」，
    /// 于是断言分不清「真重试了」还是「重试撞空了」。
    fn fake_endpoint_script(
        script: Vec<(&'static str, &'static str)>,
    ) -> (String, mpsc::Receiver<String>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let (tx, rx) = mpsc::channel();
        std::thread::spawn(move || {
            for (status_line, body) in script {
                let (mut stream, _) = match listener.accept() {
                    Ok(pair) => pair,
                    Err(_) => return,
                };
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
                    if let Some(value) =
                        trimmed.to_ascii_lowercase().strip_prefix("content-length:")
                    {
                        length = value.trim().parse().unwrap_or(0);
                    }
                    head.push_str(&trimmed);
                    head.push('\n');
                }
                let mut payload = vec![0u8; length];
                let _ = reader.read_exact(&mut payload);
                let _ = tx.send(format!("{head}\n{}", String::from_utf8_lossy(&payload)));
                let response = format!(
                    "HTTP/1.1 {status_line}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
                let _ = stream.write_all(response.as_bytes());
                let _ = stream.flush();
            }
        });
        (format!("http://127.0.0.1:{port}/v1"), rx)
    }

    /// 一段能解析成 SQL 的 200 回包正文（泄漏成 `'static`，好喂给上面的脚本）。
    fn sql_body() -> &'static str {
        let body = serde_json::json!({
            "choices": [{ "message": { "content": "```sql\nSELECT count(*) FROM public.orders;\n```" } }]
        })
        .to_string();
        Box::leak(body.into_boxed_str())
    }

    #[test]
    fn a_throttled_answer_is_waited_out_and_the_retry_returns_the_sql() {
        let (endpoint, seen) = fake_endpoint_script(vec![
            ("429 Too Many Requests", "{\"error\":\"rate limited\"}"),
            ("200 OK", sql_body()),
        ]);
        let store = tmp_store("retry-throttled");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "fake-model".to_string(),
                retry_max: 2,
                retry_max_ms: 500,
                ..Default::default()
            })
            .unwrap();

        let started = Instant::now();
        match generate(&store, "订单总数", &[orders()]).unwrap() {
            GenerateReply::Generated(outcome) => {
                assert_eq!(outcome.sql, "SELECT count(*) FROM public.orders;");
                assert_eq!(outcome.attempts.len(), 2, "{:?}", outcome.attempts);
                assert_eq!(outcome.attempts[0].status, Some(429));
                assert_eq!(outcome.attempts[0].outcome, "retryable");
                assert!(
                    outcome.attempts[0].delay_ms >= 400,
                    "退避起点是 400ms：{:?}",
                    outcome.attempts[0]
                );
                assert_eq!(outcome.attempts[1].outcome, "ok");
                assert_eq!(outcome.attempts[1].delay_ms, 0);
            }
            other => panic!("429 之后的重试应当成功：{other:?}"),
        }
        assert!(
            started.elapsed() >= Duration::from_millis(400),
            "重试之前必须真等过那一段退避，不许立刻再撞"
        );
        // 两次请求都到了服务端 —— 重试不是「以为发了」。
        let first = seen.recv_timeout(Duration::from_secs(5)).unwrap();
        let second = seen.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(second.contains("订单总数"));
        assert!(!first.is_empty());
        // 重试同样真出网 ⇒ 配额记两次、审计两条。
        assert_eq!(store.load_quota().status(now_secs(), 60).used, 2);
        assert_eq!(store.load_audit().all_recent().len(), 2);
    }

    #[test]
    fn a_bad_key_is_not_retried_at_all() {
        let (endpoint, seen) =
            fake_endpoint_script(vec![("401 Unauthorized", "{\"error\":\"bad key\"}")]);
        let store = tmp_store("retry-fatal");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                retry_max: 2,
                retry_max_ms: 500,
                ..Default::default()
            })
            .unwrap();

        let failure = generate(&store, "随便", &[orders()]).unwrap_err();
        assert!(failure.message.contains("401"), "{}", failure.message);
        assert!(
            failure.message.contains("只发了 1 次"),
            "密钥错这类不该重试，文案要说清：{}",
            failure.message
        );
        // 第一次请求确实到了（否则下一条断言会把「根本没发」当「没重试」）。
        assert!(seen.recv_timeout(Duration::from_secs(5)).is_ok(), "401 那一次该到服务端");
        assert!(
            seen.recv_timeout(Duration::from_millis(300)).is_err(),
            "401 之后不该有第二次请求"
        );
        assert_eq!(store.load_quota().status(now_secs(), 60).used, 1);
    }

    #[test]
    fn retries_stop_at_the_budget_and_say_how_many_times() {
        let (endpoint, seen) = fake_endpoint_script(vec![
            ("500 Internal Server Error", "{\"error\":\"boom\"}"),
            ("503 Service Unavailable", "{\"error\":\"boom\"}"),
            ("500 Internal Server Error", "{\"error\":\"boom\"}"),
        ]);
        let store = tmp_store("retry-budget");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                retry_max: 2,
                retry_max_ms: 500,
                ..Default::default()
            })
            .unwrap();

        let failure = generate(&store, "随便", &[orders()]).unwrap_err();
        assert!(
            failure.message.contains("已尝试 3 次"),
            "上限触达要如实报数：{}",
            failure.message
        );
        for _ in 0..3 {
            assert!(
                seen.recv_timeout(Duration::from_secs(5)).is_ok(),
                "三次尝试都该真到服务端"
            );
        }
        assert_eq!(store.load_audit().all_recent().len(), 3);
        assert_eq!(store.load_quota().status(now_secs(), 60).used, 3);
    }

    #[test]
    fn a_retry_never_carries_an_authorization_header_when_no_key_is_saved() {
        let (endpoint, seen) = fake_endpoint_script(vec![
            ("500 Internal Server Error", "{\"error\":\"boom\"}"),
            ("200 OK", sql_body()),
        ]);
        let store = tmp_store("retry-no-key");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                retry_max: 2,
                retry_max_ms: 500,
                ..Default::default()
            })
            .unwrap();

        assert!(matches!(
            generate(&store, "订单总数", &[orders()]).unwrap(),
            GenerateReply::Generated(_)
        ));
        for _ in 0..2 {
            let request = seen.recv_timeout(Duration::from_secs(5)).unwrap();
            assert!(
                !request.to_ascii_lowercase().contains("authorization"),
                "本地端点没存密钥，重试那一次也不许带 Authorization：{request}"
            );
        }
    }

    #[test]
    fn a_retry_budget_of_zero_means_a_single_request() {
        let (endpoint, seen) =
            fake_endpoint_script(vec![("500 Internal Server Error", "{\"error\":\"boom\"}")]);
        let store = tmp_store("retry-off");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                retry_max: 0,
                retry_max_ms: 500,
                ..Default::default()
            })
            .unwrap();

        let failure = generate(&store, "随便", &[orders()]).unwrap_err();
        assert!(
            failure.message.contains("只发了 1 次"),
            "配 0 次重试要如实说：{}",
            failure.message
        );
        assert!(seen.recv_timeout(Duration::from_secs(5)).is_ok(), "那一次该到服务端");
        assert!(seen.recv_timeout(Duration::from_millis(300)).is_err());
        assert_eq!(store.load_quota().status(now_secs(), 60).used, 1);
    }

    #[test]
    fn a_diagnosis_ask_also_retries_and_reports_the_attempts() {
        let (endpoint, seen) = fake_endpoint_script(vec![
            ("502 Bad Gateway", "{\"error\":\"gateway\"}"),
            ("200 OK", advisor_body()),
        ]);
        let store = tmp_store("ask-retry");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                retry_max: 2,
                retry_max_ms: 500,
                ..Default::default()
            })
            .unwrap();
        match ask(&store, "e1 执行计划").unwrap() {
            AskReply::Answered { attempts, .. } => {
                assert_eq!(attempts.len(), 2, "{attempts:?}");
                assert_eq!(attempts[0].status, Some(502));
            }
            other => panic!("诊断问答也该走同一条重试通道：{other:?}"),
        }
        assert!(seen.recv_timeout(Duration::from_secs(5)).is_ok());
        assert!(seen.recv_timeout(Duration::from_secs(5)).is_ok());
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

    // ── 对话（`FR-AI-25` 对话页签第一片）──────────────────────────────────────────
    // 三条判据：真把历史发出去 / 关掉总开关零请求 / 走同一条配额台账。

    fn chat_turn(role: &str, content: &str) -> ChatMessage {
        ChatMessage {
            role: role.to_string(),
            content: content.to_string(),
        }
    }

    #[test]
    fn a_chat_send_puts_the_whole_history_in_the_request_body() {
        let (endpoint, seen) = fake_endpoint("200 OK", advisor_body());
        let store = tmp_store("chat-send");
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                ..Default::default()
            })
            .unwrap();
        let turns = vec![
            chat_turn("user", "第一问：orders 有几行"),
            chat_turn("assistant", "历史上模型这么答过"),
            chat_turn("user", "第二问：那按天分呢"),
        ];
        match chat(&store, &turns).unwrap() {
            ChatReply::Answered { turns: count, text, .. } => {
                assert_eq!(count, 3);
                assert!(!text.is_empty());
            }
            other => panic!("该真发一次：{other:?}"),
        }
        // 服务端侧核对：历史逐条在正文里（不是只发最后一句）。
        let request = seen.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(request.contains("第一问：orders 有几行"), "{request}");
        assert!(request.contains("历史上模型这么答过"), "{request}");
        assert!(request.contains("第二问：那按天分呢"), "{request}");
        // 审计记的问句是**这一问**，不是整段历史。
        let audit = store.load_audit();
        let last = audit.all_recent().first().cloned().unwrap();
        assert!(last.summary.contains("第二问"));
        // 配额真记了一次。
        assert_eq!(store.load_quota().status(now_secs(), 60).used, 1);
    }

    #[test]
    fn a_chat_send_with_the_switch_off_never_reaches_the_server() {
        let (endpoint, seen) = fake_endpoint("200 OK", advisor_body());
        let store = tmp_store("chat-blocked");
        store
            .save(&AgentConfiguration {
                enabled: false,
                endpoint,
                model: "m".to_string(),
                ..Default::default()
            })
            .unwrap();
        match chat(&store, &[chat_turn("user", "问一句")]).unwrap() {
            ChatReply::Blocked { gate } => assert_eq!(gate.state, GateState::Disabled),
            other => panic!("关着总开关还发了请求：{other:?}"),
        }
        assert!(
            seen.recv_timeout(Duration::from_millis(300)).is_err(),
            "一条请求都不该到服务端"
        );
    }

    #[test]
    fn a_chat_send_over_the_hourly_limit_does_not_send_and_says_so() {
        let (endpoint, _seen) = fake_endpoint("200 OK", advisor_body());
        let store = tmp_store("chat-throttle");
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
            chat(&store, &[chat_turn("user", "第一问")]).unwrap(),
            ChatReply::Answered { .. }
        ));
        match chat(&store, &[chat_turn("user", "第二问")]).unwrap() {
            ChatReply::Throttled { quota } => {
                assert_eq!(quota.used, 1);
                assert_eq!(quota.limit, 1);
            }
            other => panic!("满额了还发：{other:?}"),
        }
    }

    /// 三段式 SSE（OpenAI 兼容）+ 收尾标记。
    const SSE_THREE: &str = concat!(
        "data: {\"choices\":[{\"delta\":{\"content\":\"第一段\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"，第二段\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"收尾。\"}}]}\n\n",
        "data: [DONE]\n\n",
    );

    /// 同前，但**没有收尾标记**（模拟被中途截断的回包）。
    const SSE_NO_CLOSE: &str = concat!(
        "data: {\"choices\":[{\"delta\":{\"content\":\"前半\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"后半\"}}]}\n\n",
    );

    /// 假端点：回包**分两次写**（中间停 30 毫秒），切点由调用方指定。
    /// 用来钉「按行缓冲字节」这条口径 —— 切在多字节字符中间时，按字节切字符串会烂字。
    fn fake_endpoint_in_two_writes(body: &'static str, split_at: usize) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
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
            }
            let mut payload = vec![0u8; length];
            let _ = reader.read_exact(&mut payload);
            let head = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                body.len()
            );
            let _ = stream.write_all(head.as_bytes());
            let (first, rest) = body.as_bytes().split_at(split_at);
            let _ = stream.write_all(first);
            let _ = stream.flush();
            std::thread::sleep(Duration::from_millis(30));
            let _ = stream.write_all(rest);
            let _ = stream.flush();
        });
        format!("http://127.0.0.1:{port}/v1")
    }

    fn streaming_store(tag: &str, endpoint: String) -> AgentSettingsStore {
        let store = tmp_store(tag);
        store
            .save(&AgentConfiguration {
                enabled: true,
                endpoint,
                model: "m".to_string(),
                ..Default::default()
            })
            .unwrap();
        store
    }

    /// 带 token 用量的流式回包（`FR-AI-24`）：末帧 `choices` 为空、只带 `usage`。
    const SSE_WITH_USAGE: &str = concat!(
        "data: {\"choices\":[{\"delta\":{\"content\":\"答一句\"}}]}\n\n",
        "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":120,\"completion_tokens\":34}}\n\n",
        "data: [DONE]\n\n",
    );

    #[test]
    fn a_hit_that_reports_usage_lands_the_tokens_in_the_audit() {
        // `FR-AI-24` ②：服务端回了 usage ⇒ 审计里这一条必须带着两个数（模型 / 端点 / 耗时之外的成本字段）。
        let (endpoint, _seen) = fake_endpoint("200 OK", SSE_WITH_USAGE);
        let store = streaming_store("chat-usage", endpoint);
        let reply = chat(&store, &[chat_turn("user", "问一句")]).unwrap();
        assert!(matches!(reply, ChatReply::Answered { .. }));

        let records = store.load_audit().all_recent();
        assert_eq!(records.len(), 1, "一次调用一条痕");
        assert_eq!(records[0].input_tokens, 120);
        assert_eq!(records[0].output_tokens, 34);
        assert_eq!(records[0].usage().total(), 154);
    }

    #[test]
    fn a_hit_without_usage_is_recorded_as_nothing_known_instead_of_zero() {
        // 否定面：回包不问用量 ⇒ 两个数是 0，且 `is_known()` 为假（界面据此写「没记到」，不画 0 个 token）。
        let (endpoint, _seen) = fake_endpoint("200 OK", SSE_THREE);
        let store = streaming_store("chat-usage-none", endpoint);
        let _ = chat(&store, &[chat_turn("user", "问一句")]).unwrap();

        let records = store.load_audit().all_recent();
        assert_eq!(records.len(), 1);
        assert!(
            !records[0].usage().is_known(),
            "没回 usage 却被记成「用了 0 个 token」：{:?}",
            records[0].usage()
        );
    }

    #[test]
    fn a_server_that_ignores_stream_still_has_its_usage_recorded() {
        // 整段 JSON 回包（无视 stream）也带成本字段：走 `parse_usage_text` 那条路，
        // 不是只有 SSE 才有用量 —— 否则「换一个不回流的端点，成本就查不到」。
        let body = "{\"choices\":[{\"message\":{\"content\":\"答一句\"}}],\
                    \"usage\":{\"prompt_tokens\":9,\"completion_tokens\":1}}";
        let (endpoint, _seen) = fake_endpoint("200 OK", body);
        let store = streaming_store("chat-usage-whole", endpoint);
        let _ = chat(&store, &[chat_turn("user", "问一句")]).unwrap();

        let records = store.load_audit().all_recent();
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].usage().input, 9);
        assert_eq!(records[0].usage().output, 1);
    }

    #[test]
    fn a_streaming_reply_arrives_in_pieces_and_the_pieces_join_into_the_answer() {
        // `FR-AI-16` ①：用户看到的是「字一个个滚出来」⇒ sink 至少被叫两次、拼起来等于最终正文。
        let (endpoint, seen) = fake_endpoint("200 OK", SSE_THREE);
        let store = streaming_store("chat-stream", endpoint);
        let mut pieces: Vec<String> = Vec::new();
        let reply = chat_stream(&store, &[chat_turn("user", "问一句")], &mut |chunk| {
            pieces.push(chunk.to_string())
        })
        .unwrap();
        match reply {
            ChatReply::Answered {
                text,
                deltas,
                limitations,
                attempts,
                ..
            } => {
                assert_eq!(deltas, 3, "三段增量各算一段");
                assert_eq!(text, "第一段，第二段收尾。");
                assert_eq!(attempts.len(), 1, "一次就成，不该有重试");
                assert!(
                    !limitations.iter().any(|line| line.contains("没有收尾标记")),
                    "有 [DONE] 就不该说被截断：{limitations:?}"
                );
            }
            other => panic!("该真发一次：{other:?}"),
        }
        assert_eq!(pieces.len(), 3, "逐段渲染要真的分段：{pieces:?}");
        assert_eq!(pieces.concat(), "第一段，第二段收尾。");
        // 请求侧核对：这一发真带 `stream: true`（否则服务端会整段回，界面就看不到滚动）。
        let request = seen.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(request.contains("\"stream\":true"), "{request}");
        // 配额与审计与整段版同口径：一次出网 = 一次额度、一条成功审计。
        assert_eq!(store.load_quota().status(now_secs(), 60).used, 1);
        assert_eq!(store.load_audit().all_recent().len(), 1);
    }

    #[test]
    fn a_piece_split_inside_a_chinese_character_is_not_mangled() {
        // 切点故意落在多字节字符中间：先切字符串再解码会得到 U+FFFD（而且不会报错）。
        let split = (1..SSE_THREE.len())
            .find(|index| !SSE_THREE.is_char_boundary(*index))
            .expect("这段正文里必有中文");
        let endpoint = fake_endpoint_in_two_writes(SSE_THREE, split);
        let store = streaming_store("chat-stream-split", endpoint);
        let mut pieces: Vec<String> = Vec::new();
        let reply = chat_stream(&store, &[chat_turn("user", "问一句")], &mut |chunk| {
            pieces.push(chunk.to_string())
        })
        .unwrap();
        match reply {
            ChatReply::Answered { text, deltas, .. } => {
                assert_eq!(text, "第一段，第二段收尾。");
                assert!(!text.contains('\u{FFFD}'), "解出了替换符（烂字）：{text}");
                assert_eq!(deltas, 3);
            }
            other => panic!("该真发一次：{other:?}"),
        }
    }

    #[test]
    fn a_server_that_ignores_stream_still_returns_the_whole_answer() {
        // 有的服务端无视 `stream`、回一整段 JSON：这时不能假装流式，正文仍要完整交回。
        let (endpoint, _seen) = fake_endpoint("200 OK", advisor_body());
        let store = streaming_store("chat-stream-whole", endpoint);
        let mut pieces: Vec<String> = Vec::new();
        let reply = chat_stream(&store, &[chat_turn("user", "问一句")], &mut |chunk| {
            pieces.push(chunk.to_string())
        })
        .unwrap();
        match reply {
            ChatReply::Answered {
                text,
                deltas,
                limitations,
                ..
            } => {
                assert_eq!(deltas, 0, "整段回来的不算逐段");
                assert!(pieces.is_empty(), "整段回来的不该有片段：{pieces:?}");
                assert!(!text.is_empty(), "正文仍要完整交回");
                assert!(
                    !limitations.iter().any(|line| line.contains("没有收尾标记")),
                    "整段回来的不该被说成被截断：{limitations:?}"
                );
            }
            other => panic!("该真发一次：{other:?}"),
        }
    }

    #[test]
    fn a_stream_without_a_closing_marker_says_it_may_be_truncated() {
        let (endpoint, _seen) = fake_endpoint("200 OK", SSE_NO_CLOSE);
        let store = streaming_store("chat-stream-truncated", endpoint);
        let reply = chat_stream(&store, &[chat_turn("user", "问一句")], &mut |_| {}).unwrap();
        match reply {
            ChatReply::Answered {
                text,
                deltas,
                limitations,
                ..
            } => {
                assert_eq!(text, "前半后半");
                assert_eq!(deltas, 2);
                assert!(
                    limitations.iter().any(|line| line.contains("没有收尾标记")),
                    "没有收尾标记就要如实说可能被截断：{limitations:?}"
                );
            }
            other => panic!("该真发一次：{other:?}"),
        }
    }

    // ── 工具调用 + 内联审批（`FR-AI-18`）────────────────────────────────────────────
    // 四条判据：请求里真带工具清单 / 模型点工具就**停在等人点** / 允许后文件内容回灌 / 拒绝与越界都不读。

    /// 一段工具调用 SSE：**参数分两帧到**（真实服务端就是这样），拼起来才是合法 JSON。
    const SSE_TOOL_CALL: &str = concat!(
        "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",",
        "\"function\":{\"name\":\"read_file\",\"arguments\":\"{\\\"path\\\":\"}}]}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\"notes.txt\\\"}\"}}]}}]}\n\n",
        "data: [DONE]\n\n",
    );

    /// 一段普通正文 SSE（工具点完之后模型给的最终回答）。
    const SSE_ANSWER: &str = concat!(
        "data: {\"choices\":[{\"delta\":{\"content\":\"文件里写着重试三次\"}}]}\n\n",
        "data: [DONE]\n\n",
    );

    fn tool_workspace(tag: &str) -> PathBuf {
        let dir = fixture_root().join(format!("doyah-tool-ws-{tag}-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("notes.txt"), "重试三次。").unwrap();
        std::fs::write(dir.join("other.txt"), "另一份文件。").unwrap();
        std::fs::write(
            fixture_root().join(secret_name()),
            "不该被读到",
        )
        .unwrap();
        dir
    }

    /// 工作区**外面**那份文件的名字（越界判据用它 —— 名字必须真存在，否则「读不到」会顶替「越界」而假绿）。
    fn secret_name() -> String {
        format!("doyah-tool-secret-{}.txt", std::process::id())
    }

    #[test]
    fn a_tool_call_stops_for_approval_and_the_approved_file_goes_back_to_the_model() {
        let (endpoint, seen) = fake_endpoint_script(vec![
            ("200 OK", SSE_TOOL_CALL),
            ("200 OK", SSE_ANSWER),
        ]);
        let store = streaming_store("chat-tool-approve", endpoint);
        let workspace = tool_workspace("approve");
        let turns = vec![chat_turn("user", "看一下 notes.txt 里写了什么")];

        let call = match chat(&store, &turns).unwrap() {
            ChatReply::ToolPending { calls, .. } => calls.into_iter().next().expect("该有至少一件工具"),
            other => panic!("模型点了工具就该停下来等人点：{other:?}"),
        };
        assert_eq!(call.name, "read_file");
        assert_eq!(call.id, "call_1");
        assert_eq!(call.arguments, "{\"path\":\"notes.txt\"}", "分帧参数要原样拼回去");

        // 第一发请求里真带着工具清单（否则模型根本没机会点）。
        let first = seen.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(first.contains("\"tools\""), "{first}");
        assert!(first.contains("read_file"), "{first}");

        // 允许之后：文件内容要真出现在第二发请求里（role: tool + tool_call_id 成对）。
        let decision = chat_tool_resume(
            &store,
            workspace.to_str().unwrap(),
            &turns,
            &[call],
            &[true],
            &[],
            &mut |_| {},
        )
        .unwrap();
        let run = &decision.runs[0];
        assert!(run.approved);
        assert!(run.ok, "{:?}", run.problem);
        assert!(run.chars > 0);
        // 交回界面的正文 = 真给到模型的那一份（界面靠它把文件带进后续请求）。
        assert!(run.content.contains("重试三次"), "{}", run.content);
        let second = seen.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(second.contains("tool_call_id"), "{second}");
        assert!(second.contains("重试三次"), "读到的内容要回灌给模型：{second}");
        match decision.reply {
            ChatReply::Answered { text, deltas, .. } => {
                assert!(text.contains("重试三次"), "{text}");
                assert_eq!(deltas, 1);
            }
            other => panic!("回灌之后该给最终回答：{other:?}"),
        }
    }

    #[test]
    fn a_denied_tool_is_reported_to_the_model_and_the_file_stays_unread() {
        let (endpoint, seen) =
            fake_endpoint_script(vec![("200 OK", SSE_TOOL_CALL), ("200 OK", SSE_ANSWER)]);
        let store = streaming_store("chat-tool-deny", endpoint);
        let workspace = tool_workspace("deny");
        let turns = vec![chat_turn("user", "看一下 notes.txt 里写了什么")];
        let call = match chat(&store, &turns).unwrap() {
            ChatReply::ToolPending { calls, .. } => calls.into_iter().next().expect("该有至少一件工具"),
            other => panic!("该等到审批：{other:?}"),
        };
        // 先把第一发（带工具清单那一次）取走，下面取到的才是回灌那一次。
        let _first = seen.recv_timeout(Duration::from_secs(5)).unwrap();
        let decision = chat_tool_resume(
            &store,
            workspace.to_str().unwrap(),
            &turns,
            &[call],
            &[false],
            &[],
            &mut |_| {},
        )
        .unwrap();
        let run = &decision.runs[0];
        assert!(!run.approved);
        assert!(!run.ok);
        assert_eq!(run.chars, 0);
        // 没读到的没有正文可带（界面不该把「没读到」的说明当成文件内容带进下一发）。
        assert!(run.content.is_empty(), "{}", run.content);
        let second = seen.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(second.contains("用户拒绝了"), "被拒要如实告诉模型：{second}");
        assert!(
            !second.contains("重试三次"),
            "拒绝了就不许把文件内容发出去：{second}"
        );
    }

    /// 一条回答里**并列两件**工具调用：第一帧里两件的名字一起到，参数再分帧补齐。
    ///
    /// 这一帧正是旧实现的缺口：`parse_sse_line` 每行只返回第一件 ⇒ 第二件静默消失。
    const SSE_TWO_TOOL_CALLS: &str = concat!(
        "data: {\"choices\":[{\"delta\":{\"tool_calls\":[",
        "{\"index\":0,\"id\":\"call_1\",\"function\":{\"name\":\"read_file\",\"arguments\":\"{\\\"path\\\":\\\"note\"}},",
        "{\"index\":1,\"id\":\"call_2\",\"function\":{\"name\":\"read_file\",\"arguments\":\"{\\\"path\\\":\\\"oth\"}}",
        "]}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"tool_calls\":[",
        "{\"index\":0,\"function\":{\"arguments\":\"s.txt\\\"}\"}},",
        "{\"index\":1,\"function\":{\"arguments\":\"er.txt\\\"}\"}}",
        "]}}]}\n\n",
        "data: [DONE]\n\n",
    );

    #[test]
    fn two_tool_calls_in_one_answer_are_both_kept_and_go_back_in_one_request() {
        let (endpoint, seen) =
            fake_endpoint_script(vec![("200 OK", SSE_TWO_TOOL_CALLS), ("200 OK", SSE_ANSWER)]);
        let store = streaming_store("chat-tool-two", endpoint);
        let workspace = tool_workspace("two");
        let turns = vec![chat_turn("user", "看一下 notes.txt 和 other.txt")];

        let calls = match chat(&store, &turns).unwrap() {
            ChatReply::ToolPending { calls, .. } => calls,
            other => panic!("两件工具都该停下来等人点：{other:?}"),
        };
        assert_eq!(calls.len(), 2, "一条回答里两件，一件都不许丢：{calls:?}");
        assert_eq!(calls[0].id, "call_1");
        assert_eq!(calls[1].id, "call_2");
        assert_eq!(calls[0].arguments, "{\"path\":\"notes.txt\"}", "分帧参数要拼回整份");
        assert_eq!(calls[1].arguments, "{\"path\":\"other.txt\"}", "第二件也要拼回整份");

        let _first = seen.recv_timeout(Duration::from_secs(5)).unwrap();
        // 逐件决定：第一件允许、第二件拒绝 ⇒ **一次**请求把两份结果一起回灌。
        let decision =
            chat_tool_resume(&store, workspace.to_str().unwrap(), &turns, &calls, &[true, false], &[], &mut |_| {})
                .unwrap();
        assert_eq!(decision.runs.len(), 2, "每件都要有一条账");
        assert!(decision.runs[0].ok, "{:?}", decision.runs[0].problem);
        assert!(decision.runs[0].chars > 0);
        assert!(!decision.runs[1].approved);
        assert_eq!(decision.runs[1].path, "other.txt");

        let second = seen.recv_timeout(Duration::from_secs(5)).unwrap();
        assert_eq!(
            second.matches("\"tool_call_id\"").count(),
            2,
            "两件结果各一条 tool 消息：{second}"
        );
        assert!(second.contains("call_1") && second.contains("call_2"), "{second}");
        assert!(second.contains("重试三次"), "允许的那份要回灌：{second}");
        assert!(second.contains("用户拒绝了"), "拒绝的那份要如实告诉模型：{second}");
        assert!(
            !second.contains("另一份文件。"),
            "拒绝的就不许把内容发出去：{second}"
        );
    }

    #[test]
    fn a_decision_count_that_does_not_match_the_calls_sends_nothing() {
        let (endpoint, seen) =
            fake_endpoint_script(vec![("200 OK", SSE_TWO_TOOL_CALLS), ("200 OK", SSE_ANSWER)]);
        let store = streaming_store("chat-tool-mismatch", endpoint);
        let workspace = tool_workspace("mismatch");
        let turns = vec![chat_turn("user", "看一下 notes.txt 和 other.txt")];
        let calls = match chat(&store, &turns).unwrap() {
            ChatReply::ToolPending { calls, .. } => calls,
            other => panic!("该等到审批：{other:?}"),
        };
        let _first = seen.recv_timeout(Duration::from_secs(5)).unwrap();

        // 两件工具只给了一个决定 ⇒ **一条请求都不许发**（不许静默补一个「拒绝」）。
        let failure = chat_tool_resume(
            &store,
            workspace.to_str().unwrap(),
            &turns,
            &calls,
            &[true],
            &[],
            &mut |_| {},
        )
        .unwrap_err();
        assert!(failure.message.contains("对不上"), "{}", failure.message);
        assert!(seen.try_recv().is_err(), "对不上就不许再出网");
    }

    #[test]
    fn an_approved_file_is_carried_into_the_next_request_without_faking_a_turn() {
        let (endpoint, seen) = fake_endpoint_script(vec![("200 OK", SSE_ANSWER)]);
        let store = streaming_store("chat-carry", endpoint);
        let turns = vec![
            chat_turn("user", "看一下 notes.txt"),
            chat_turn("assistant", "它写着重试三次。"),
            chat_turn("user", "那按它说的做"),
        ];
        let carry = vec![CarriedFile {
            path: "notes.txt".to_string(),
            content: "文件 notes.txt（共 5 字符）：\n重试三次。".to_string(),
        }];
        let reply = chat_stream_with_carry(&store, &turns, &[], &carry, &mut |_| {}).unwrap();
        assert!(
            matches!(reply, ChatReply::Answered { .. }),
            "带上上下文照样该正常答：{reply:?}"
        );
        let body = seen.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(body.contains("【文件 notes.txt】"), "上下文要进请求：{body}");
        assert!(body.contains("重试三次"), "{body}");
        // 否定面：上下文只待在那一条 system 里 —— 不许伪造成用户 / 模型说过的话。
        assert_eq!(
            body.matches("\"role\":\"user\"").count(),
            2,
            "两问就是两条 user：{body}"
        );
        assert!(
            !body.contains("\"role\":\"assistant\",\"content\":\"【文件"),
            "上下文不许冒充满一轮：{body}"
        );
    }

    #[test]
    fn a_path_outside_the_workspace_is_refused_before_any_read() {
        let workspace = tool_workspace("escape");
        // 工作区外那份文件**真的存在**（否则「没有这个文件」会顶替「越界」而假绿）。
        let escape = format!("../{}", secret_name());
        assert!(fixture_root().join(secret_name()).exists());
        let read = read_workspace_file(workspace.to_str().unwrap(), &escape);
        assert!(!read.ok);
        // 钉住「越界这一条前置检查先拦下来」——只靠 canonicalize 兜底也算安全，
        // 但那样这里就分不出「前置检查在不在」（实测：删掉前置检查，这条断言才会红）。
        assert!(read.content.contains("路径里有"), "{}", read.content);
        assert!(!read.content.contains("不该被读到"));
        // 绝对路径同样不读。
        let absolute = read_workspace_file(workspace.to_str().unwrap(), "C:/Windows/win.ini");
        assert!(!absolute.ok);
        // 工作区里的正常文件照读。
        let inside = read_workspace_file(workspace.to_str().unwrap(), "notes.txt");
        assert!(inside.ok);
        assert!(inside.content.contains("重试三次"));
    }

    // ── 写文件：差异预览 / 沙箱 / 落盘 / 撤销（`FR-AI-20` · `FR-AI-25`）──────────────

    fn write_workspace(tag: &str) -> PathBuf {
        let dir = fixture_root().join(format!("doyah-write-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("src")).unwrap();
        std::fs::write(dir.join("src/a.ts"), "let a = 1;\nlet b = 2;\nlet c = 3;\n").unwrap();
        dir
    }

    #[test]
    fn the_preview_counts_only_the_changed_lines_and_shows_both_sides() {
        let workspace = write_workspace("preview");
        let old = "a\nb\nc\nd\n";
        let new = "a\nb\nC\nd\n";
        let (stat, removed, added) = line_diff(old, new);
        assert_eq!(stat.old_lines, 4);
        assert_eq!(stat.new_lines, 4);
        assert_eq!(stat.removed, 1);
        assert_eq!(stat.added, 1);
        assert_eq!(removed, vec!["c"]);
        assert_eq!(added, vec!["C"]);
        // 纯新增 / 纯删除 / CRLF 三种边界。
        let (only_added, removed, added) = line_diff("a\n", "a\nb\n");
        assert_eq!((only_added.added, only_added.removed), (1, 0));
        assert!(removed.is_empty());
        assert_eq!(added, vec!["b"]);
        let (crlf, _, _) = line_diff("a\r\nb\r\n", "a\nb\n");
        assert_eq!(
            (crlf.added, crlf.removed),
            (0, 0),
            "只是换行符不同不该算成「每行都改了」"
        );

        // 真读盘的那一份：改一行 ⇒ 卡片上看得到减 / 加两侧。
        let preview = write_preview(
            workspace.to_str().unwrap(),
            "src/a.ts",
            "let a = 1;\nlet b = 20;\nlet c = 3;\n",
        );
        assert!(preview.problem.is_empty(), "{}", preview.problem);
        assert!(preview.existed);
        assert_eq!((preview.added, preview.removed), (1, 1));
        assert!(preview.diff.contains("- let b = 2;"), "{}", preview.diff);
        assert!(preview.diff.contains("+ let b = 20;"), "{}", preview.diff);
        // 新建（盘上没有）：整份都是新增，且**不落盘**。
        let fresh = write_preview(workspace.to_str().unwrap(), "src/new.ts", "x\ny\n");
        assert!(!fresh.existed);
        assert_eq!(fresh.added, 2);
        assert!(!workspace.join("src/new.ts").exists());
    }

    #[test]
    fn the_write_sandbox_refuses_absolute_escapes_missing_dirs_and_binaries() {
        let workspace = write_workspace("sandbox");
        let root = workspace.to_str().unwrap();

        let absolute = write_preview(root, "C:/Windows/win.ini", "x");
        assert!(absolute.problem.contains("绝对路径"), "{}", absolute.problem);
        let escape = write_preview(root, "../escape.txt", "x");
        assert!(escape.problem.contains("路径里有"), "{}", escape.problem);
        let missing = write_preview(root, "nope/a.txt", "x");
        assert!(missing.problem.contains("目标目录不存在"), "{}", missing.problem);
        // 目录不能当文件写。
        let directory = write_preview(root, "src", "x");
        assert!(!directory.problem.is_empty(), "目录该被拒");
        // 二进制目标不覆盖（含 0 字节的文件）。
        std::fs::write(workspace.join("blob.bin"), [0u8, 1, 2, 3]).unwrap();
        let binary = write_preview(root, "blob.bin", "x");
        assert!(binary.problem.contains("二进制"), "{}", binary.problem);

        // 注入面：去掉 `..` 前置判之后，拒绝的理由会变成「落在工作区外面」（canonicalize 兜底），
        // 这条 message 断言当场红 —— 证明前置判真接在这条路上；而下面那句「越界文件绝不许落盘」
        // 守的是真正的安全网（两层都在，缺一层都不会静默放行）。
        let refused = write_workspace_file(root, "../escape.txt", "x", &workspace.join("undo"));
        assert!(!refused.ok);
        assert!(!fixture_root().join("escape.txt").exists(), "越界文件绝不许落盘");
    }

    #[test]
    fn a_write_lands_then_undo_restores_the_old_text_and_a_tampered_file_is_refused() {
        let workspace = write_workspace("undo");
        let root = workspace.to_str().unwrap();
        let undo_dir = workspace.join("undo");

        let written = write_workspace_file(root, "src/a.ts", "let a = 1;\nlet b = 2;\n", &undo_dir);
        assert!(written.ok, "{}", written.problem);
        assert_eq!(written.removed, 1);
        assert_eq!(written.bytes, "let a = 1;\nlet b = 2;\n".len());
        assert!(!written.undo.is_empty(), "写成功要给撤销凭据");
        assert_eq!(
            std::fs::read_to_string(workspace.join("src/a.ts")).unwrap(),
            "let a = 1;\nlet b = 2;\n"
        );

        // 中途被手工改过 ⇒ 撤销拒绝（否则会吃掉用户后来的修改）。
        std::fs::write(workspace.join("src/a.ts"), "let a = 1;\nlet b = 2;\nlet mine = 3;\n").unwrap();
        let tampered = undo_write(&undo_dir, &written.undo).unwrap_err();
        assert!(tampered.message.contains("被改过"), "{}", tampered.message);
        assert!(std::fs::read_to_string(workspace.join("src/a.ts"))
            .unwrap()
            .contains("mine"));

        // 改回去（恢复成我们写的那份）⇒ 撤销成功、正文回到写之前。
        std::fs::write(workspace.join("src/a.ts"), "let a = 1;\nlet b = 2;\n").unwrap();
        let undone = undo_write(&undo_dir, &written.undo).unwrap();
        assert!(undone.restored && !undone.removed);
        assert_eq!(
            std::fs::read_to_string(workspace.join("src/a.ts")).unwrap(),
            "let a = 1;\nlet b = 2;\nlet c = 3;\n"
        );
        // 记录用完即删：同一个凭据不能再撤第二次。
        assert!(undo_write(&undo_dir, &written.undo).is_err());
    }

    #[test]
    fn undoing_a_brand_new_file_deletes_it_and_a_bad_token_touches_nothing() {
        let workspace = write_workspace("undo-new");
        let root = workspace.to_str().unwrap();
        let undo_dir = workspace.join("undo");
        let written = write_workspace_file(root, "src/b.ts", "hello\n", &undo_dir);
        assert!(written.ok, "{}", written.problem);
        assert!(workspace.join("src/b.ts").exists());
        let undone = undo_write(&undo_dir, &written.undo).unwrap();
        assert!(undone.removed && !undone.restored);
        assert!(!workspace.join("src/b.ts").exists());
        // 凭据里带路径分隔符 ⇒ 一律不认（不许用它去读别的记录）。
        assert!(undo_write(&undo_dir, "..\\..\\etc").is_err());
        assert!(undo_write(&undo_dir, "").is_err());
    }
}
