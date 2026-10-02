//! PostgreSQL 驱动层（Windows 侧表示层）—— **驱动只在这一层**，领域层保持零驱动
//!
//! 归属（§8.5.1 / §8.5.2-4）：本文件属表示层外壳，是唯一引数据库驱动的地方；
//! 模型（连接配置 / 连接串）来自领域层 `doyah-studio-db`，本层不重写一份。
//!
//! 四条口径：
//! ① **失败给可读原因**：驱动错误把服务端的原话端出来（带 SQLSTATE，不翻译、不归类）；
//! ② **值按服务端文本拿**：本轮统一走**简单查询协议**（服务端把每格按文本给）⇒
//!    不引数值 / 时间类型的解码依赖，第一版就能真跑通。**如实登记的代价**：这一档下
//!    NULL 与空串在协议层**分不开**（都可能是空文本），明细留待下一段换扩展协议时逐型解码；
//! ③ **不拼字符串做参数**：本轮只执行用户自己写的 SQL；参数化查询下一段接（`$1` 走驱动原生）；
//! ④ **超过上限如实报截断**，不静默少给行。

use doyah_studio_db::config::ConnectionConfig;
use tokio_postgres::{Client, NoTls, SimpleQueryMessage};

/// 一次查询最多实体化多少行（超过就如实报截断）。
pub const MAX_QUERY_ROWS: usize = 5000;

/// 结果集：列名 + 行（每格是文本或 NULL）+ 截断标记 + 影响行数。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QueryResult {
    pub columns: Vec<String>,
    pub rows: Vec<Vec<Option<String>>>,
    /// 服务端一共回来多少行；`rows.len() < returned` = 被上限截断
    pub returned: usize,
    pub truncated: bool,
    /// 非查询语句的影响行数（后端 command tag；拿不到就是 `None`）
    pub affected: Option<u64>,
}

/// 对象树节点（本轮到「表 / 视图」这一层）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TableNode {
    pub schema: String,
    pub name: String,
    /// `table` / `view` / `materialized view` / `foreign table`
    pub kind: String,
}

/// 服务端自述（连上后第一件事：把"连到了哪儿"如实告诉用户）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerInfo {
    pub version: String,
    pub database: String,
    pub user: String,
    pub server_encoding: String,
    pub current_schema: Option<String>,
}

/// 连接参数（IPC 入参）。口令**不常驻**：前端从凭据来源取来后即用即弃。
#[derive(Debug, Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectParams {
    pub host: String,
    pub port: u16,
    pub database: String,
    pub user: String,
    #[serde(default)]
    pub password: Option<String>,
    /// `disable` = 明确不走 TLS；其余取值本轮**也按不走处理并如实登记**（TLS 接线下一段）。
    #[serde(default)]
    pub ssl_mode: Option<String>,
}

/// 失败时的**可读原因**：服务端原话 + 一句"该往哪儿看"。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DbFailure {
    /// 服务端原话（一字不改）；没有原话时是驱动的话
    pub message: String,
    pub hint: String,
}

impl DbFailure {
    pub fn from_driver_text(text: &str) -> Self {
        let lower = text.to_lowercase();
        let hint = if lower.contains("password") || lower.contains("口令") {
            "口令不对或该用户没有登录权限：核对用户名与口令（口令不进配置文件）。"
        } else if lower.contains("does not exist") && lower.contains("database") {
            "库名不存在：先确认库名（服务端可列出可用库）。"
        } else if lower.contains("refused") || lower.contains("拒绝") {
            "端口上没有服务在听：确认服务已启动、端口正确。"
        } else if lower.contains("timed out") || lower.contains("timeout") || lower.contains("超时") {
            "连接超时：确认主机可达、防火墙放行、超时值够用。"
        } else if lower.contains("authentication") || lower.contains("认证") {
            "认证方式不匹配：核对服务端 pg_hba.conf 对本机的要求。"
        } else if lower.contains("syntax") || lower.contains("语法") {
            "服务端说这条语句语法不对：看原话里指出的位置与记号。"
        } else if lower.contains("permission denied") || lower.contains("权限") {
            "服务端说权限不够：核对当前用户对目标对象的权限。"
        } else {
            "把服务端原话与主机 / 端口 / 库名 / 用户名一起核对；必要时看服务端日志同一时刻的记录。"
        };
        Self {
            message: text.to_string(),
            hint: hint.to_string(),
        }
    }
}

/// 启动 SQL 的**逐条**执行结果（FR-CONN-17）。
///
/// 口径（照抄领域层 `startup_statements` 的设计意图）：**逐条发、逐条报错** ——
/// 一条失败不该把后面的一起吞掉（`search_path` 没设上，后面所有查询都可能找错表），
/// 所以这里**不返回一个布尔**，而是每一句各自的结果、各自的失败原话。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StartupOutcome {
    /// 语句原文（已 trim；注释与空段在领域层就被丢掉了）
    pub sql: String,
    pub ok: bool,
    /// 失败时的可读原因（服务端原话 + 提示）；成功为 `None`
    pub failure: Option<DbFailure>,
}

/// 连接结果：服务端自述 + 启动 SQL 的逐条结果。
///
/// **为什么启动 SQL 失败不阻断连接**：语句本身合法与否是用户的事（例如给一个没权限的库设
/// `search_path`）；把它做成"连不上"会让用户连界面都进不去，反而查不了为什么。⇒ 连上照常返回，
/// 失败**如实摆在界面上**（哪一条、服务端说了什么）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectReport {
    pub info: ServerInfo,
    pub startup: Vec<StartupOutcome>,
}

/// 拼驱动要的连接串。**口令单独传**（`password()`），绝不进连接串（会进日志与进程列表）。
pub fn connection_string(params: &ConnectParams) -> String {
    format!(
        "host={} port={} dbname={} user={} application_name=doyah-studio connect_timeout=5",
        params.host, params.port, params.database, params.user
    )
}

/// 领域层配置 → IPC 入参（同一份事实只存一处：配置在领域层，驱动参数由它派生）。
///
/// 现在只被单测用；**连接配置面板**（把已保存的配置填进表单再连）接上来时它就是那条通路，
/// 故先留着并显式标注 —— 不留一个"没人知道为什么在"的死代码。
#[allow(dead_code)]
pub fn params_from_config(config: &ConnectionConfig) -> ConnectParams {
    ConnectParams {
        host: config.host.clone(),
        port: config.port,
        database: config.database.clone(),
        user: config.username.clone(),
        password: None,
        ssl_mode: Some(config.ssl_mode.raw_value().to_string()),
    }
}

/// 这一档 sslmode 要不要真的走 TLS。
///
/// **如实登记**：本轮 `Prefer`（默认档）也走明文 —— 本机回环与自用场景够用；
/// 真 TLS 接线（`require` / `verify-ca` / `verify-full` 的语义差别）是下一段的事。
pub fn wants_tls(ssl_mode: Option<&str>) -> bool {
    matches!(
        ssl_mode.unwrap_or("prefer").to_ascii_lowercase().as_str(),
        "require" | "verify-ca" | "verify-full"
    )
}

/// 会话：一个已建立的连接 + 它自述的信息。
pub struct PgSession {
    client: Client,
    info: ServerInfo,
}

impl PgSession {
    pub fn info(&self) -> &ServerInfo {
        &self.info
    }

    /// 驱动客户端（**只在表示层内部用**：lib.rs 的命令层与本文件的启动 SQL 下发）。
    /// 公开它是因为 lib.rs 要拿会话去跑查询 —— 领域层永远看不到它（那边零驱动）。
    pub fn client(&self) -> &Client {
        &self.client
    }

    /// **连接 + 下发启动 SQL**（FR-CONN-17）。
    ///
    /// 连接失败 ⇒ `Err`（连不上就是连不上）；连上之后**启动 SQL 逐条发**，某条失败
    /// **不阻断**，结果逐条摆在 `ConnectReport::startup` 里（见该类型的口径说明）。
    pub async fn connect_with_startup(
        params: &ConnectParams,
        startup_sql: &[String],
    ) -> Result<(Self, ConnectReport), DbFailure> {
        let session = Self::connect(params).await?;
        let mut startup = Vec::with_capacity(startup_sql.len());
        for sql in startup_sql {
            // 用 `execute`（不带结果集、也不留行）：启动 SQL 一般是 `SET` / `SELECT set_config`，
            // 走 `run` 会把可能的结果集实体化一份却没处放 —— 这里只要"成没成"与服务端原话。
            let outcome = match session.client().prepare(sql).await {
                Ok(statement) => match session.client().execute(&statement, &[]).await {
                    Ok(_) => StartupOutcome { sql: sql.clone(), ok: true, failure: None },
                    Err(e) => StartupOutcome {
                        sql: sql.clone(),
                        ok: false,
                        failure: Some(DbFailure::from_driver_text(&server_error_text(&e))),
                    },
                },
                Err(e) => StartupOutcome {
                    sql: sql.clone(),
                    ok: false,
                    failure: Some(DbFailure::from_driver_text(&server_error_text(&e))),
                },
            };
            startup.push(outcome);
        }
        let info_for_report = session.info().clone();
        Ok((session, ConnectReport {
            info: info_for_report,
            startup,
        }))
    }

    /// **连接**：失败时给服务端原话 + 提示。TLS 档本轮按明文并如实告知调用方。
    pub async fn connect(params: &ConnectParams) -> Result<Self, DbFailure> {
        let conn_str = connection_string(params);
        // 本轮：只有 require / verify-* 才尝试 TLS；但**驱动侧尚未接 TLS 实现** ⇒ 明确报"未接"，
        // 而不是静默降级成明文（静默降级是安全类缺陷里最难发现的一种）。
        if wants_tls(params.ssl_mode.as_deref()) {
            return Err(DbFailure {
                message: format!("sslmode={} 本轮尚未接线（驱动侧 TLS 未接）", params.ssl_mode.clone().unwrap_or_default()),
                hint: "改用 sslmode=disable 显式走明文，或等 TLS 接线（下一段）。不静默降级。".to_string(),
            });
        }
        let (client, connection) = tokio_postgres::connect(&conn_str, NoTls)
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;
        // 连接任务：驱动要求有人在后台驱动 IO（本会话存活期间一直跑）
        tokio::spawn(async move {
            if let Err(e) = connection.await {
                eprintln!("[doyah] 与数据库的连接断了：{e}");
            }
        });
        let info = read_server_info(&client).await?;
        Ok(Self { client, info })
    }

    /// 对象树：表 / 视图（按 schema、名字排序）。
    pub async fn tables(&self) -> Result<Vec<TableNode>, DbFailure> {
        let sql = "SELECT table_schema, table_name, table_type \
                   FROM information_schema.tables \
                   WHERE table_schema NOT IN ('pg_catalog', 'information_schema') \
                   ORDER BY table_schema, table_name";
        let messages = self
            .client
            .simple_query(sql)
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;
        let mut out = Vec::new();
        for m in messages {
            if let SimpleQueryMessage::Row(r) = m {
                out.push(TableNode {
                    schema: r.get(0).unwrap_or_default().to_string(),
                    name: r.get(1).unwrap_or_default().to_string(),
                    kind: match r.get(2).unwrap_or_default() {
                        "VIEW" => "view".to_string(),
                        "MATERIALIZED VIEW" => "materialized view".to_string(),
                        "FOREIGN" | "FOREIGN TABLE" => "foreign table".to_string(),
                        _ => "table".to_string(),
                    },
                });
            }
        }
        Ok(out)
    }

    /// 跑一条 SQL。**扩展协议 + 原生取行上限**：`query_raw` 的流收够 `limit` 行就停，
    /// 剩下的由驱动丢弃 —— 这样"上限"是真的（真库用例当场抓到过：先前两版都是
    /// "先把整个结果收进内存再截"，要 2 行却拿到 50 行、大表还会顶爆内存）。
    pub async fn run(&self, sql: &str, limit: usize) -> Result<QueryResult, DbFailure> {
        use futures_util::StreamExt;
        let statement = self
            .client
            .prepare(sql)
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;

        // **没有结果列的语句**（INSERT / UPDATE / DELETE / DDL / SET …）走 `execute`：
        // 只有它回影响行数（`query_raw` 不回 command tag ⇒ 上一版把影响行数丢了，真库用例抓到）。
        if statement.columns().is_empty() {
            let affected = self
                .client
                .execute(&statement, &[])
                .await
                .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;
            return Ok(QueryResult {
                columns: Vec::new(),
                rows: Vec::new(),
                returned: 0,
                truncated: false,
                affected: Some(affected),
            });
        }

        let empty: [&(dyn tokio_postgres::types::ToSql + Sync); 0] = [];
        let stream = self
            .client
            .query_raw(&statement, empty)
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;
        futures_util::pin_mut!(stream);

        let mut columns: Vec<String> = Vec::new();
        let mut rows: Vec<Vec<Option<String>>> = Vec::new();
        let mut capped = false;
        while let Some(item) = stream.next().await {
            let row = item.map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;
            if columns.is_empty() {
                columns = row.columns().iter().map(|c| c.name().to_string()).collect();
            }
            if rows.len() >= limit {
                capped = true;
                break;
            }
            rows.push(
                (0..row.columns().len())
                    .map(|i| decode_cell(&row, i).as_option())
                    .collect(),
            );
        }
        Ok(QueryResult {
            columns,
            returned: rows.len(),
            rows,
            truncated: capped,
            affected: None,
        })
    }

    /// 快速自检（`--probe` 用）：连上、能问出一行、能列出表。
    pub async fn probe(&self) -> Result<ProbeReport, DbFailure> {
        let tables = self.tables().await?;
        let one = self.run("SELECT 1 AS one", 10).await?;
        Ok(ProbeReport {
            info: self.info.clone(),
            table_count: tables.len(),
            schemas: {
                let mut names: Vec<String> = tables.iter().map(|t| t.schema.clone()).collect();
                names.sort();
                names.dedup();
                names
            },
            select_one: one.rows.first().and_then(|r| r.first().cloned()).flatten(),
        })
    }
}

/// 自检读数。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProbeReport {
    pub info: ServerInfo,
    pub table_count: usize,
    pub schemas: Vec<String>,
    pub select_one: Option<String>,
}

async fn read_server_info(client: &Client) -> Result<ServerInfo, DbFailure> {
    let sql = "SELECT version(), current_database(), current_user, \
               current_setting('server_encoding'), current_schema()";
    let messages = client
        .simple_query(sql)
        .await
        .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;
    for m in messages {
        if let SimpleQueryMessage::Row(r) = m {
            let get = |i: usize| r.get(i).map(|s| s.to_string());
            return Ok(ServerInfo {
                version: get(0).unwrap_or_default(),
                database: get(1).unwrap_or_default(),
                user: get(2).unwrap_or_default(),
                server_encoding: get(3).unwrap_or_default(),
                current_schema: get(4),
            });
        }
    }
    Err(DbFailure {
        message: "服务端没有返回版本行".to_string(),
        hint: "重试；若稳定复现，请在服务端日志里查同一时刻的记录。".to_string(),
    })
}

/// 一格的值（**认不出要如实说**：给类型名与字节数，不倒驱动内部表示）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum Cell {
    Null,
    Text { value: String },
    Unknown {
        type_name: String,
        bytes: usize,
        preview: String,
    },
}

impl Cell {
    /// IPC 只给字符串；`None` = NULL（界面自己显示成灰的 NULL）。
    pub fn as_option(&self) -> Option<String> {
        match self {
            Cell::Null => None,
            Cell::Text { value } => Some(value.clone()),
            Cell::Unknown {
                type_name,
                bytes,
                preview,
            } => Some(format!("[认不出的类型 {type_name} · {bytes} 字节 · {preview}]")),
        }
    }
}

/// 逐型解码一格：**先试文本**（`text` / `varchar` / 数值 / JSON 这些驱动都能给文本），
/// 再试常见标量；都不行就**如实报"认不出"**（点名类型 + 字节数 + 十六进制预览）。
pub fn decode_cell(row: &tokio_postgres::Row, index: usize) -> Cell {
    use tokio_postgres::types::Type;
    if row.try_get::<_, Option<String>>(index).is_ok() {
        return opt_text(row.try_get::<_, Option<String>>(index).ok().flatten());
    }
    let col_type = row.columns()[index].type_().clone();
    let decoded: Result<Option<String>, _> = match col_type {
        Type::BOOL => row.try_get::<_, Option<bool>>(index).map(|v| v.map(|b| b.to_string())),
        Type::INT2 => row.try_get::<_, Option<i16>>(index).map(|v| v.map(|n| n.to_string())),
        Type::INT4 => row.try_get::<_, Option<i32>>(index).map(|v| v.map(|n| n.to_string())),
        Type::INT8 => row.try_get::<_, Option<i64>>(index).map(|v| v.map(|n| n.to_string())),
        Type::FLOAT4 => row.try_get::<_, Option<f32>>(index).map(|v| v.map(|n| n.to_string())),
        Type::FLOAT8 => row.try_get::<_, Option<f64>>(index).map(|v| v.map(|n| n.to_string())),
        _ => return unknown(row, index, &col_type),
    };
    match decoded {
        Ok(v) => opt_text(v),
        Err(_) => unknown(row, index, &col_type),
    }
}

fn opt_text(value: Option<String>) -> Cell {
    match value {
        Some(v) => Cell::Text { value: v },
        None => Cell::Null,
    }
}

/// 认不出时：**点名类型**、给字节数与十六进制预览（不让用户看见驱动的内部枚举名而无从下手）。
fn unknown(row: &tokio_postgres::Row, index: usize, col_type: &tokio_postgres::types::Type) -> Cell {
    // 原始字节：驱动在二进制形态下能拿到；拿不到就说明它连"认不出"都只能点到为止
    let raw: Option<Vec<u8>> = row.try_get::<_, Option<Vec<u8>>>(index).ok().flatten();
    let (bytes, preview) = match raw {
        Some(b) => (
            b.len(),
            b.iter().take(8).map(|x| format!("{x:02x}")).collect::<Vec<_>>().join(" "),
        ),
        None => (0, String::new()),
    };
    Cell::Unknown {
        type_name: col_type.name().to_string(),
        bytes,
        preview,
    }
}

/// 简单协议的消息 → 结果集（**这一处**做解码，界面只拿字符串）。
pub fn result_from_messages(messages: &[SimpleQueryMessage], limit: usize) -> QueryResult {
    let mut acc = QueryAccumulator::new(limit);
    for m in messages {
        acc.push(m);
    }
    acc.finish()
}

/// 逐条累积结果：**上限一到就停止收**，并把"服务端其实还有行"如实记成截断。
pub struct QueryAccumulator {
    limit: usize,
    columns: Vec<String>,
    rows: Vec<Vec<Option<String>>>,
    returned: usize,
    affected: Option<u64>,
    overflow: bool,
}

impl QueryAccumulator {
    pub fn new(limit: usize) -> Self {
        Self {
            limit,
            columns: Vec::new(),
            rows: Vec::new(),
            returned: 0,
            affected: None,
            overflow: false,
        }
    }

    /// 收一条消息。**超过上限后仍继续计数**（这样"截断"才有依据），但不再留内容。
    pub fn push(&mut self, message: &SimpleQueryMessage) {
        match message {
            SimpleQueryMessage::RowDescription(cols) => {
                if self.columns.is_empty() {
                    self.columns = cols.iter().map(|c| c.name().to_string()).collect();
                }
            }
            SimpleQueryMessage::Row(r) => {
                self.returned += 1;
                if self.rows.len() < self.limit {
                    self.rows.push((0..r.len()).map(|i| r.get(i).map(|s| s.to_string())).collect());
                } else {
                    self.overflow = true;
                }
            }
            SimpleQueryMessage::CommandComplete(n) => self.affected = Some(*n),
            _ => {}
        }
    }

    /// 内容已经收满（调用方可以停止再取）。
    pub fn is_full(&self) -> bool {
        self.limit > 0 && self.rows.len() >= self.limit
    }

    pub fn finish(self) -> QueryResult {
        QueryResult {
            columns: self.columns,
            rows: self.rows,
            returned: self.returned,
            truncated: self.overflow || self.returned > self.limit,
            affected: self.affected,
        }
    }
}

/// 驱动错误 → 服务端原话（**带 SQLSTATE**，不翻译、不归类、不丢服务端说过的话）。
pub fn server_error_text(err: &tokio_postgres::Error) -> String {
    if let Some(db) = err.as_db_error() {
        let mut text = db.message().to_string();
        text.push_str(&format!("（SQLSTATE {}）", db.code().code()));
        if let Some(detail) = db.detail() {
            text.push_str(&format!(" 细节：{detail}"));
        }
        if let Some(hint) = db.hint() {
            text.push_str(&format!(" 服务端建议：{hint}"));
        }
        text
    } else {
        err.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn params() -> ConnectParams {
        ConnectParams {
            host: "127.0.0.1".into(),
            port: 5433,
            database: "doyah_lab".into(),
            user: "doyah".into(),
            password: None,
            ssl_mode: Some("disable".into()),
        }
    }

    #[test]
    fn connection_string_never_carries_the_password() {
        let mut p = params();
        p.password = Some("secret-should-not-appear".into());
        let text = connection_string(&p);
        assert!(!text.contains("secret-should-not-appear"), "{text}");
        assert!(text.contains("host=127.0.0.1"));
        assert!(text.contains("port=5433"));
        assert!(text.contains("dbname=doyah_lab"));
        assert!(text.contains("connect_timeout=5"));
    }

    #[test]
    fn tls_modes_are_not_silently_downgraded() {
        assert!(!wants_tls(Some("disable")));
        assert!(!wants_tls(Some("prefer")));
        assert!(wants_tls(Some("require")));
        assert!(wants_tls(Some("verify-full")));
        // 缺省 = prefer（与领域层的默认档一致）
        assert!(!wants_tls(None));
    }

    #[test]
    fn failure_hints_point_somewhere_useful() {
        let f = DbFailure::from_driver_text("password authentication failed for user \"bob\"");
        assert!(f.hint.contains("口令"));
        let f = DbFailure::from_driver_text("connection refused");
        assert!(f.hint.contains("服务"));
        let f = DbFailure::from_driver_text("something nobody has seen before");
        assert!(f.hint.contains("服务端原话"));
        // 原话一字不改
        assert_eq!(f.message, "something nobody has seen before");
    }

    #[test]
    fn config_maps_to_ipc_params_without_inventing_values() {
        use doyah_studio_db::config::ConnectionConfig;
        use doyah_studio_db::db_type::DatabaseType;
        let mut config = ConnectionConfig::new("id-1", "本地实验库", DatabaseType::Postgresql);
        config.host = "127.0.0.1".into();
        config.port = 5433;
        config.database = "doyah_lab".into();
        config.username = "doyah".into();
        let p = params_from_config(&config);
        assert_eq!(p.port, 5433);
        assert_eq!(p.database, "doyah_lab");
        assert_eq!(p.user, "doyah");
        assert!(p.password.is_none(), "配置里没有口令这一项");
    }
}
