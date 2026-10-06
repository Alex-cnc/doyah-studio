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
use doyah_studio_db::ddl::ColumnDef;
use doyah_studio_db::tree::{assemble_columns, ColumnRow, ObjectKind, ObjectNode, TableColumns};
use tokio_postgres::{Client, NoTls, SimpleQueryMessage};

/// 一次查询最多实体化多少行（超过就如实报截断）。
pub const MAX_QUERY_ROWS: usize = 5000;

/// 结果集：列名 + 行（每格是文本或 NULL）+ 数值形态 + 截断标记 + 影响行数。
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QueryResult {
    pub columns: Vec<String>,
    pub rows: Vec<Vec<Option<String>>>,
    /// 每行的**数值形态**（该列解析得出数字才有值）：排序 / 筛选**按值比**，
    /// 不拿显示字符串比（`"9" > "10"` 这种字典序错排是客户端表格的经典缺陷）。
    pub num_rows: Vec<Vec<Option<f64>>>,
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

/// 一条索引（1.5 段表设计器的输入之一）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IndexInfo {
    pub name: String,
    pub is_unique: bool,
    pub is_primary: bool,
    pub columns: Vec<String>,
}

/// 一条约束（主键 / 外键 / 唯一 / 检查；定义原文）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConstraintInfo {
    pub name: String,
    /// `primary` / `foreign` / `unique` / `check` / 服务端的原字母
    pub kind: String,
    pub definition: String,
}

/// 一张表的**结构**（列 / 索引 / 约束）—— 表设计器一打开就要这三样。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TableShape {
    pub schema: String,
    pub table: String,
    pub columns: Vec<ColumnDef>,
    pub indexes: Vec<IndexInfo>,
    pub constraints: Vec<ConstraintInfo>,
}

/// 一个库的读数（1.7 管理面）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DatabaseInfo {
    pub name: String,
    pub owner: String,
    pub encoding: String,
    pub size_bytes: i64,
    pub connections: i64,
    pub allow_connections: bool,
}

/// 一张表的读数（1.7 管理面）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TableStats {
    pub table: String,
    /// **估算**行数（`pg_class.reltuples`，不是精确 count）
    pub estimated_rows: i64,
    pub total_bytes: i64,
    pub table_bytes: i64,
    pub index_size_pretty: String,
    pub last_vacuum: String,
    pub last_analyze: String,
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
    /// 连到哪台主机（**本进程记的**，不是服务端自述；取消请求要用它再开一条连接）
    #[serde(default)]
    pub host: String,
    /// 连到哪个端口（同上）
    #[serde(default)]
    pub port: u16,
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

/// 会话：一个已建立的连接 + 它自述的信息（含**连到哪儿** —— 取消请求要往同一地址再开一条连接）。
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
        let mut info = read_server_info(&client).await?;
        // 记下"连到哪儿"：取消请求要往同一地址再开一条连接（见 `cancel`）
        info.host = params.host.clone();
        info.port = params.port;
        Ok(Self { client, info })
    }

    /// **请求服务端取消当前查询**（1.2 段）。
    ///
    /// 实现：走 PostgreSQL 协议的 `CancelRequest` —— 拿**驱动自己给的** `CancelRequest`
    /// （内含服务端后端 PID 与该连接的取消密钥），向**同一条地址再开一个 TCP 连接**把它发过去。
    /// 为什么不用 `tokio-postgres` 的 `cancel_token()`：那个方法在当前版本要 `postgres` /
    /// `postgres-openssl` 特性，而本机 cargo 缓存里没有对应依赖 ⇒ 为一个取消功能再引一次联网取包
    /// 不划算；协议层的 CancelRequest 是同一件事，且只在本文件（连接层）出现。
    ///
    /// 口径要说清（不是"万事大吉"）：
    /// ① 取消是**请求**，不是保证 —— 服务端可能已经在返回路上（那时它不回取消、查询照常成功）；
    /// ② 取消的是**服务端当前正在跑的那条**；本进程不再等待的那个 future 由调用方丢弃；
    /// ③ 取消之后**连接仍然可用**（协议上是 QueryCanceled 错误，连接本身不坏）—— 这是本段
    ///    出口判据点名的那条，真库用例里真取消一次再接着查询来验。
    pub async fn cancel(&self) -> Result<(), DbFailure> {
        let request = self.client.cancel_token();
        let mut stream = tokio::net::TcpStream::connect((self.info.host.as_str(), self.info.port))
            .await
            .map_err(|e| DbFailure {
                message: format!("打开取消连接失败：{e}"),
                hint: "服务端可能已断开；重连后再试。".to_string(),
            })?;
        request
            .cancel_query_raw(&mut stream, NoTls)
            .await
            .map_err(|e| DbFailure {
                message: format!("发送取消请求失败：{e}"),
                hint: "服务端可能已断开；重连后再试。取消是请求，不是保证。".to_string(),
            })?;
        Ok(())
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

    /// 对象树第一层：**这台服务器上能看到的 schema**（1.1 段「展开一层取一层」的第一层）。
    ///
    /// 为什么不在连接时把整库元数据一次拉光：大库上那是几百毫秒的固定开销、还没展开就先付了；
    /// 而且树的第一层本来就只显示 schema。`pg_catalog` / `information_schema` 与 `pg_*`
    /// 临时 schema 都排掉（它们是实现细节，不是用户的库）。
    pub async fn schemas(&self) -> Result<Vec<String>, DbFailure> {
        let sql = "SELECT schema_name FROM information_schema.schemata \
                   WHERE schema_name NOT IN ('pg_catalog', 'information_schema') \
                     AND schema_name NOT LIKE 'pg\\_%' \
                   ORDER BY schema_name";
        let messages = self
            .client
            .simple_query(sql)
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;
        let mut out = Vec::new();
        for m in messages {
            if let SimpleQueryMessage::Row(r) = m {
                if let Some(name) = r.get(0) {
                    out.push(name.to_string());
                }
            }
        }
        Ok(out)
    }

    /// 对象树第二层：**某个 schema 下的对象**（按需展开时才问）。
    ///
    /// 取的是 `pg_class` 而不是 `information_schema.tables`：序列、物化视图、分区表都在那里，
    /// 而 `information_schema.tables` 看不到序列。用 `relkind` 单字母词表交给领域层分类
    /// （分类规则只此一处，见 `doyah_studio_db::tree::ObjectKind::from_server`）。
    pub async fn relations(&self, schema: &str) -> Result<Vec<ObjectNode>, DbFailure> {
        let sql = "SELECT c.relname, c.relkind::text \
                   FROM pg_class c \
                   JOIN pg_namespace n ON n.oid = c.relnamespace \
                   WHERE n.nspname = $1 AND c.relkind IN ('r','p','v','m','f','S') \
                   ORDER BY c.relkind, c.relname";
        let rows = self
            .client
            .query(sql, &[&schema])
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;
        let mut out = Vec::new();
        for row in rows {
            let name: String = row.get(0);
            let kind: String = row.get(1);
            out.push(ObjectNode::new(schema, name, ObjectKind::from_server(&kind)));
        }
        doyah_studio_db::tree::sort_objects(&mut out);
        Ok(out)
    }

    /// 对象树第三层：**一批表的列**（FR-META-01 的「表 → 列」、FR-META-05 的数据类型）。
    ///
    /// **一层一次取数**（不许 N+1）：几张表一条 SQL 问齐（`relname = ANY($2)`），
    /// 不是「for 表 in 表们 { 查一次 }」。组装走领域层的 `tree::assemble_columns` ——
    /// 生产路径与判据自测（`tree.rs` 里那个计数替身）用的是**同一个**组装口。
    ///
    /// 为什么用 `pg_attribute` + `format_type` 而不是 `information_schema.columns`：
    /// 后者对**物化视图 / 外部表**的列覆盖面不稳，且类型串是自己拼的；`format_type`
    /// 直接给服务端原文（`character varying(50)` / `numeric(12,2)`），与表设计器取的
    /// 那份原文同源。
    pub async fn columns(
        &self,
        schema: &str,
        tables: &[String],
    ) -> Result<Vec<TableColumns>, DbFailure> {
        if tables.is_empty() {
            return Ok(Vec::new());
        }
        let sql = "SELECT c.relname, a.attname, \
                          pg_catalog.format_type(a.atttypid, a.atttypmod) AS col_type \
                   FROM pg_catalog.pg_attribute a \
                   JOIN pg_catalog.pg_class c ON c.oid = a.attrelid \
                   JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace \
                   WHERE n.nspname = $1 AND c.relname = ANY($2) \
                     AND a.attnum > 0 AND NOT a.attisdropped \
                   ORDER BY c.relname, a.attnum";
        let rows = self
            .client
            .query(sql, &[&schema, &tables])
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;
        let mut cells: Vec<ColumnRow> = Vec::with_capacity(rows.len());
        for row in rows {
            cells.push((row.get(0), row.get(1), row.get(2)));
        }
        Ok(assemble_columns(schema, tables, &cells))
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
            num_rows: Vec::new(),
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
            num_rows: numeric_view(&rows),
            returned: rows.len(),
            rows,
            truncated: capped,
            affected: None,
        })
    }

    /// **一批写回，一次事务**（1.4 段）。
    ///
    /// 口径（写回是"能改坏数据"的功能，条条都要说清）：
    /// ① **默认一批一次事务**：中途某条失败 ⇒ **整批回滚**（不让用户面对"改了一半"的库存）；
    /// ② `rollback` 为真 ⇒ 跑完**主动回滚**（这是"提交前预览"的正确姿势：先跑一遍看影响行数，
    ///    再决定提交还是回滚 —— 但要说清：在 PostgreSQL 里这仍是**真执行过**，
    ///    触发器会被触发、序列会被消耗，"回滚了就什么都没发生"是错的）；
    /// ③ 服务端错误**逐条收集**（哪条、服务端说了什么），不在第一条失败处丢掉上下文；
    /// ④ 只读连接在**命令层**就被拦住（这里再兜一次：真收到 `forbidden` 就整批不发）。
    pub async fn run_transaction(
        &self,
        statements: &[String],
        rollback: bool,
    ) -> Result<Vec<StatementOutcome>, DbFailure> {
        let plan = doyah_studio_db::writeback::TransactionPlan::explicit();
        let mut out: Vec<StatementOutcome> = Vec::with_capacity(statements.len() + 2);
        // 事务语句字面量取自领域层的语句表（**顺序与字面量只此一处**），这里只按序下发。
        // 为什么不用驱动的 `transaction()`：它要 `&mut Client`，而本层拿的是共享引用；
        // 手工下发还多一个好处 —— `BEGIN` / `COMMIT` / `ROLLBACK` 各自的结果也能逐条报出来。
        if let Some(begin) = &plan.begin {
            self.execute_simple(begin).await?;
        }
        let mut failed = false;
        for sql in statements {
            let started = std::time::Instant::now();
            match self.execute_simple(sql).await {
                Ok(affected) => out.push(StatementOutcome {
                    sql: sql.clone(),
                    ok: true,
                    result: Some(QueryResult {
                        columns: Vec::new(),
                        rows: Vec::new(),
                        num_rows: Vec::new(),
                        returned: 0,
                        truncated: false,
                        affected: Some(affected),
                    }),
                    failure: None,
                    elapsed_ms: started.elapsed().as_millis() as u64,
                }),
                Err(failure) => {
                    failed = true;
                    out.push(StatementOutcome {
                        sql: sql.clone(),
                        ok: false,
                        result: None,
                        failure: Some(failure),
                        elapsed_ms: started.elapsed().as_millis() as u64,
                    });
                    // 一条失败 ⇒ 不再往下发（后面的语句可能依赖前面那句），直接回滚
                    break;
                }
            }
        }
        if failed || rollback {
            if let Some(rb) = &plan.rollback {
                self.execute_simple(rb).await?;
            }
        } else if let Some(commit) = &plan.commit {
            self.execute_simple(commit).await?;
        }
        Ok(out)
    }

    /// 下发一条**不带结果集**的语句，取回影响行数（事务语句与写语句都用它）。
    async fn execute_simple(&self, sql: &str) -> Result<u64, DbFailure> {
        let statement = self
            .client
            .prepare(sql)
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;
        self.client
            .execute(&statement, &[])
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))
    }

    /// 一张表的**主键列名**（按主键定义顺序）。没有主键 ⇒ 空表。
    ///
    /// 为什么必须有它：写回要靠主键定位"是哪一行"（见领域层 `writeback` 的口径 ①）；
    /// 无主键的表**不给改入口**，而不是生成一条 `WHERE` 靠猜的 UPDATE。
    pub async fn primary_key(&self, schema: &str, table: &str) -> Result<Vec<String>, DbFailure> {
        let sql = "SELECT a.attname \
                   FROM pg_index i \
                   JOIN pg_class c ON c.oid = i.indrelid \
                   JOIN pg_namespace n ON n.oid = c.relnamespace \
                   JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY(i.indkey) \
                   WHERE i.indisprimary AND n.nspname = $1 AND c.relname = $2 \
                   ORDER BY array_position(i.indkey, a.attnum)";
        let rows = self
            .client
            .query(sql, &[&schema, &table])
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;
        Ok(rows.into_iter().map(|row| row.get::<_, String>(0)).collect())
    }

    /// 读一张表的**结构元数据**（1.5 段：表设计器的输入）。
    ///
    /// 三样一起取（列 / 索引 / 约束）而不是分三次问：表设计器一打开就要这三样，
    /// 分三次会让"打开"变成三次往返，且中间状态可能不一致。
    pub async fn table_shape(&self, schema: &str, table: &str) -> Result<TableShape, DbFailure> {
        // 列：类型 / 可空 / 默认值都取**原文**（不自己翻译类型名）
        let columns_sql = "SELECT column_name, \
                                  COALESCE(domain_name, data_type) || \
                                    CASE WHEN character_maximum_length IS NOT NULL \
                                         THEN '(' || character_maximum_length || ')' \
                                         WHEN numeric_precision IS NOT NULL AND numeric_scale IS NOT NULL \
                                         THEN '(' || numeric_precision || ',' || numeric_scale || ')' \
                                         ELSE '' END AS full_type, \
                                  is_nullable, column_default \
                           FROM information_schema.columns \
                           WHERE table_schema = $1 AND table_name = $2 \
                           ORDER BY ordinal_position";
        let mut columns = Vec::new();
        for row in self
            .client
            .query(columns_sql, &[&schema, &table])
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?
        {
            columns.push(ColumnDef {
                name: row.get(0),
                data_type: row.get(1),
                is_nullable: row.get::<_, String>(2) == "YES",
                default_expr: row.get(3),
            });
        }

        // 索引：按索引名聚合列（`array_agg` 保住列顺序）
        let indexes_sql = "SELECT i.relname AS index_name, \
                                  ix.indisunique AS is_unique, \
                                  ix.indisprimary AS is_primary, \
                                  array_agg(a.attname ORDER BY k.ord) AS cols \
                           FROM pg_index ix \
                           JOIN pg_class i ON i.oid = ix.indexrelid \
                           JOIN pg_class t ON t.oid = ix.indrelid \
                           JOIN pg_namespace n ON n.oid = t.relnamespace \
                           JOIN LATERAL unnest(ix.indkey) WITH ORDINALITY AS k(attnum, ord) ON TRUE \
                           JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum \
                           WHERE n.nspname = $1 AND t.relname = $2 \
                           GROUP BY i.relname, ix.indisunique, ix.indisprimary \
                           ORDER BY i.relname";
        let mut indexes = Vec::new();
        for row in self
            .client
            .query(indexes_sql, &[&schema, &table])
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?
        {
            let cols: Vec<String> = row.get(3);
            indexes.push(IndexInfo {
                name: row.get(0),
                is_unique: row.get(1),
                is_primary: row.get(2),
                columns: cols,
            });
        }

        // 约束：主键 / 外键 / 唯一 / 检查，定义原文直接取（`pg_get_constraintdef`）
        let constraints_sql = "SELECT c.conname, c.contype::text, pg_get_constraintdef(c.oid) \
                               FROM pg_constraint c \
                               JOIN pg_class t ON t.oid = c.conrelid \
                               JOIN pg_namespace n ON n.oid = t.relnamespace \
                               WHERE n.nspname = $1 AND t.relname = $2 \
                               ORDER BY c.conname";
        let mut constraints = Vec::new();
        for row in self
            .client
            .query(constraints_sql, &[&schema, &table])
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?
        {
            let kind: String = row.get(1);
            constraints.push(ConstraintInfo {
                name: row.get(0),
                kind: match kind.as_str() {
                    "p" => "primary".to_string(),
                    "f" => "foreign".to_string(),
                    "u" => "unique".to_string(),
                    "c" => "check".to_string(),
                    other => other.to_string(),
                },
                definition: row.get(2),
            });
        }

        Ok(TableShape { schema: schema.to_string(), table: table.to_string(), columns, indexes, constraints })
    }

    /// **按序执行一批 DDL**（1.5 段）。逐句报告（哪句成、哪句败、各耗时），与多段执行同一形状。
    ///
    /// 口径：**调用方（界面）只把非破坏性的那些递进来** —— 破坏性语句在界面层只给"复制语句"，
    /// 本函数不替它做判断（判定在领域层 `ddl::executable_subset`，一处）。
    pub async fn run_ddl(&self, statements: &[String]) -> Result<Vec<StatementOutcome>, DbFailure> {
        let mut out = Vec::with_capacity(statements.len());
        for sql in statements {
            let started = std::time::Instant::now();
            match self.execute_simple(sql).await {
                Ok(affected) => out.push(StatementOutcome {
                    sql: sql.clone(),
                    ok: true,
                    result: Some(QueryResult {
                        columns: Vec::new(),
                        rows: Vec::new(),
                        num_rows: Vec::new(),
                        returned: 0,
                        truncated: false,
                        affected: Some(affected),
                    }),
                    failure: None,
                    elapsed_ms: started.elapsed().as_millis() as u64,
                }),
                Err(failure) => {
                    out.push(StatementOutcome {
                        sql: sql.clone(),
                        ok: false,
                        result: None,
                        failure: Some(failure),
                        elapsed_ms: started.elapsed().as_millis() as u64,
                    });
                    // DDL 一句失败就停：后面的多半依赖前面那句（建了列才能改它的默认值）
                    break;
                }
            }
        }
        Ok(out)
    }

    /// **导出取数**（1.6 段）：把一张表（或一条查询）按**流式**取回，收够上限即停。
    ///
    /// 口径：导出与界面取数走**同一条** `run`（同一条上限语义、同一份"如实标截断"），
    /// 不另写一条"导出专用查询" —— 两条路必然漂移，而"导出比界面多/少几行"是最难查的那类缺陷。
    pub async fn export_rows(
        &self,
        sql: &str,
        limit: usize,
    ) -> Result<(Vec<String>, Vec<Vec<String>>, bool), DbFailure> {
        let result = self.run(sql, limit).await?;
        let rows: Vec<Vec<String>> = result
            .rows
            .iter()
            .map(|row| row.iter().map(|c| c.clone().unwrap_or_default()).collect())
            .collect();
        Ok((result.columns, rows, result.truncated))
    }

    /// **导入**（1.6 段）：一页数据 + 列映射 ⇒ 一个事务里的多条 INSERT。
    ///
    /// 口径：① **整个导入是一个事务**（中途失败整批回滚，不留"导了一半"的表）；
    /// ② 值用**参数化**下发（`$1..$n`），不拼字符串 —— 导入的数据来自外部文件，
    /// 拼字符串就是把注入面直接开给一个不可信来源；③ 空串与 NULL 的区分由调用方在 `Option` 里表达，
    /// 本层不猜（CSV 的空白字段到底是空串还是 NULL，只有用户知道）。
    pub async fn import_rows(
        &self,
        schema: Option<&str>,
        table: &str,
        columns: &[String],
        rows: &[Vec<Option<String>>],
    ) -> Result<usize, DbFailure> {
        if columns.is_empty() {
            return Err(DbFailure {
                message: "没有可写入的列：先做列映射".to_string(),
                hint: "CSV 的表头要与目标表的列对上（按名字匹配，不按位置）。".to_string(),
            });
        }
        let target = doyah_studio_db::writeback::qualified(schema, table);
        let quoted: Vec<String> = columns
            .iter()
            .map(|c| doyah_studio_db::writeback::quote_ident(c))
            .collect();
        // **按目标列的真实类型**显式转换：类型从服务端元数据取（`information_schema.columns`），
        // 不在客户端猜。为什么不靠"让服务端自己解析"：
        // 实测 `$n::text[]` 与 `$n::unknown[]` 两条路都被判成 text 表达式 ⇒
        // 插入 integer 列直接报 SQLSTATE 42804（"表达式的类型为 text"）。显式 cast 一次说清。
        let column_types = self.column_types(schema, table, columns).await?;
        let select_cols = column_types
            .iter()
            .enumerate()
            .map(|(i, ty)| format!("c{i}::text::{}", Self::cast_target(ty)))
            .collect::<Vec<_>>()
            .join(", ");
        // 一次插入**一批**：用 `unnest($n::text[])` 把"一列一个数组"摊成行集合。
        // 为什么不是逐行 INSERT：大文件上逐行往返会把导入拖成"按行计费"，
        // 而本段点名的正是"边读边写"。
        let array_params: Vec<String> = (1..=columns.len())
            .map(|i| format!("${i}::text[]"))
            .collect();
        // **`ROWS FROM (...)` 而不是并列写几个 `unnest`**：后者在 FROM 里是**交叉连接**
        // （实测：4 行 × 4 行 = 16 行，导入直接把数据翻倍）。`ROWS FROM` 按位置把多个集合函数
        // 并成一行行 —— 这正是"一列一个数组摊成行"要的语义。
        let unnests = array_params
            .iter()
            .map(|p| format!("unnest({p})"))
            .collect::<Vec<_>>()
            .join(", ");
        let aliases = (0..columns.len())
            .map(|i| format!("c{i}"))
            .collect::<Vec<_>>()
            .join(", ");
        let from_clause = format!("ROWS FROM ({unnests}) AS t({aliases})");
        let sql = format!(
            "INSERT INTO {target} ({}) SELECT {select_cols} FROM {from_clause}",
            quoted.join(", ")
        );
        let statement = self
            .client
            .prepare(&sql)
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;

        // 每批的行数：留足参数预算（一行一个数组参数，PostgreSQL 的参数上限是 65535）
        const BATCH_ROWS: usize = 500;
        // 事务：一句失败 ⇒ 整批回滚（与写回同一口径）
        let plan = doyah_studio_db::writeback::TransactionPlan::explicit();
        if let Some(begin) = &plan.begin {
            self.execute_simple(begin).await?;
        }
        let mut inserted = 0usize;
        for chunk in rows.chunks(BATCH_ROWS) {
            // 列式转置：每个参数是一个"该列在这一批里的值"的数组
            let mut owned_columns: Vec<Vec<Option<String>>> = Vec::with_capacity(columns.len());
            for (col, _) in columns.iter().enumerate() {
                owned_columns.push(chunk.iter().map(|row| row.get(col).cloned().flatten()).collect());
            }
            let params: Vec<&(dyn tokio_postgres::types::ToSql + Sync)> = owned_columns
                .iter()
                .map(|col| col as &(dyn tokio_postgres::types::ToSql + Sync))
                .collect();
            if let Err(e) = self.client.execute(&statement, &params[..]).await {
                let text = server_error_text(&e);
                if let Some(rb) = &plan.rollback {
                    self.execute_simple(rb).await.ok();
                }
                return Err(DbFailure {
                    message: format!(
                        "第 {} 行起的那一批写库失败（整批已回滚）：{text}",
                        inserted + 1
                    ),
                    hint: "看服务端原话里指出的列与值；改好数据后整批重导。".to_string(),
                });
            }
            inserted += chunk.len();
        }
        if let Some(commit) = &plan.commit {
            self.execute_simple(commit).await?;
        }
        Ok(inserted)
    }

    /// 取**指定若干列**在目标表里的类型原文（导入时要按它做显式转换）。
    ///
    /// 返回顺序与 `columns` 一致；某列在元数据里找不到 ⇒ 报错（**不猜类型**）。
    pub async fn column_types(
        &self,
        schema: Option<&str>,
        table: &str,
        columns: &[String],
    ) -> Result<Vec<String>, DbFailure> {
        let sql = "SELECT column_name, \
                          COALESCE(domain_name, data_type) || \
                            CASE WHEN character_maximum_length IS NOT NULL \
                                 THEN '(' || character_maximum_length || ')' \
                                 WHEN numeric_precision IS NOT NULL AND numeric_scale IS NOT NULL \
                                 THEN '(' || numeric_precision || ',' || numeric_scale || ')' \
                                 ELSE '' END \
                   FROM information_schema.columns \
                   WHERE table_name = $1 AND ($2::text IS NULL OR table_schema = $2)";
        // 不限定 schema 时可能出现同名表：这时**宁可报错也不猜**（见下）
        let schema_param: Option<&str> = schema;
        let rows = self
            .client
            .query(sql, &[&table, &schema_param])
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;
        let found: Vec<(String, String)> = rows
            .into_iter()
            .map(|row| (row.get::<_, String>(0), row.get::<_, String>(1)))
            .collect();
        let mut out = Vec::with_capacity(columns.len());
        for column in columns {
            match found.iter().find(|(name, _)| name == column) {
                Some((_, ty)) => out.push(ty.clone()),
                None => {
                    return Err(DbFailure {
                        message: format!("目标表里找不到列 {column}（或同名表不止一张）"),
                        hint: "确认列名与 schema；导入按列名匹配，找不到就不猜类型。".to_string(),
                    })
                }
            }
        }
        Ok(out)
    }

    /// 把**显示类型**裁成可当 cast 目标的名字。
///
    /// 为什么需要它：`information_schema` 给的是显示类型（`character varying(50)` / `numeric(12,2)`），
    /// 而 `::numeric(12,2)` 这种写法在「表达式 :: 类型名」的位置**是语法错误**（实测 42601）。
    /// cast 只认类型名本身 ⇒ 砍掉括号里的长度 / 精度。
///
    /// **如实登记的简化**：只砍括号。`character varying` 这类 SQL 标准名 PostgreSQL 认，
    /// 所以够用；认不出的名字会让服务端报语法错并原话回给用户，**不会被静默吞掉**。
    fn cast_target(data_type: &str) -> String {
        match data_type.find('(') {
            Some(at) => data_type[..at].trim().to_string(),
            None => data_type.trim().to_string(),
    }
}

    /// **库列表 + 大小 + 连接数**（1.7 管理面）。只读；普通用户也能看到自己有权连的库。
    pub async fn databases(&self) -> Result<Vec<DatabaseInfo>, DbFailure> {
        let sql = "SELECT d.datname, \
                          pg_catalog.pg_get_userbyid(d.datdba) AS owner, \
                          pg_catalog.pg_encoding_to_char(d.encoding) AS encoding, \
                          pg_catalog.pg_database_size(d.datname)::text, \
                          (SELECT count(*) FROM pg_stat_activity a WHERE a.datname = d.datname)::text, \
                          d.datallowconn \
                   FROM pg_database d \
                   WHERE d.datistemplate = false \
                   ORDER BY pg_catalog.pg_database_size(d.datname) DESC, d.datname";
        let rows = self
            .client
            .query(sql, &[])
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;
        Ok(rows
            .into_iter()
            .map(|row| DatabaseInfo {
                name: row.get(0),
                owner: row.get(1),
                encoding: row.get(2),
                size_bytes: row.get::<_, String>(3).parse().unwrap_or(0),
                connections: row.get::<_, String>(4).parse().unwrap_or(0),
                allow_connections: row.get(5),
            })
            .collect())
    }

    /// **会话与锁**（1.7 管理面）：谁在跑什么、跑了多久、有没有在等锁。
    ///
    /// 口径：① `query` 只在 **active** 时给（idle 会话的 `query` 是上一条语句，给了会误导）；
    /// ② 时长按 `now() - query_start` 算；③ `waiting` 看 `wait_event_type = 'Lock'`
    /// —— 那才是"正在挡别人 / 被别人挡"的信号。
    pub async fn sessions(&self) -> Result<Vec<doyah_studio_db::admin::SessionRow>, DbFailure> {
        let sql = "SELECT pid::text, COALESCE(usename, ''), COALESCE(datname, ''), \
                          COALESCE(state, ''), \
                          CASE WHEN state = 'active' THEN query ELSE NULL END, \
                          COALESCE(EXTRACT(MILLISECONDS FROM (now() - query_start))::bigint, 0)::text, \
                          COALESCE(wait_event_type, '') \
                   FROM pg_stat_activity \
                   WHERE pid <> pg_backend_pid() \
                   ORDER BY query_start NULLS LAST";
        let rows = self
            .client
            .query(sql, &[])
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;
        let mut out: Vec<doyah_studio_db::admin::SessionRow> = rows
            .into_iter()
            .map(|row| doyah_studio_db::admin::SessionRow {
                pid: row.get::<_, String>(0).parse().unwrap_or(0),
                user: row.get(1),
                database: row.get(2),
                state: row.get(3),
                query: row.get(4),
                duration_ms: row.get::<_, String>(5).parse().unwrap_or(0),
                waiting: row.get::<_, String>(6) == "Lock",
            })
            .collect();
        // 排序口径在领域层（等锁优先、其次按时长）—— 界面直接按这个顺序显示
        doyah_studio_db::admin::sort_sessions(&mut out);
        Ok(out)
    }

    /// **表统计**（1.7 管理面）：行数**估算**、表与索引体积、上次 vacuum / analyze。
    ///
    /// 口径：行数取 `pg_class.reltuples`（**估算**）—— 精确 `count(*)` 在大表上要全扫；
    /// 字段名写明是估算，不假装精确。
    pub async fn table_stats(&self, schema: &str) -> Result<Vec<TableStats>, DbFailure> {
        let sql = "SELECT c.relname, \
                          c.reltuples::bigint::text, \
                          pg_total_relation_size(c.oid)::text, \
                          pg_relation_size(c.oid)::text, \
                          COALESCE(pg_size_pretty(pg_total_relation_size(c.oid) - pg_relation_size(c.oid)), '0'), \
                          COALESCE(to_char(GREATEST(s.last_vacuum, s.last_autovacuum), 'YYYY-MM-DD HH24:MI'), '从未'), \
                          COALESCE(to_char(GREATEST(s.last_analyze, s.last_autoanalyze), 'YYYY-MM-DD HH24:MI'), '从未') \
                   FROM pg_class c \
                   JOIN pg_namespace n ON n.oid = c.relnamespace \
                   LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid \
                   WHERE n.nspname = $1 AND c.relkind IN ('r','p','m') \
                   ORDER BY pg_total_relation_size(c.oid) DESC";
        let rows = self
            .client
            .query(sql, &[&schema])
            .await
            .map_err(|e| DbFailure::from_driver_text(&server_error_text(&e)))?;
        Ok(rows
            .into_iter()
            .map(|row| TableStats {
                table: row.get(0),
                estimated_rows: row.get::<_, String>(1).parse().unwrap_or(0),
                total_bytes: row.get::<_, String>(2).parse().unwrap_or(0),
                table_bytes: row.get::<_, String>(3).parse().unwrap_or(0),
                index_size_pretty: row.get(4),
                last_vacuum: row.get(5),
                last_analyze: row.get(6),
            })
            .collect())
    }

/// 快速自检（`--probe` 用）：连上、能问出一行、能列出表。
    pub async fn probe(&self) -> Result<ProbeReport, DbFailure> {        let tables = self.tables().await?;
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

    /// **多段执行**（1.2 段）：把输入按分号切成多段，**逐段执行、逐段报告**。
    ///
    /// 三条口径：
    /// ① 切分用领域层 `config::split_statements`（与启动 SQL 同一套：丢注释、字符串里的分号不切）
    ///    —— 编辑面的位置切分在 `sql::spans`，两者条数由领域层用例对住，这里不另写一套；
    /// ② **一段失败就停**（`stop_on_error`）：这是数据库客户端的常规语义 —— 后面的语句可能
    ///    依赖前面那句（建表 → 插数），硬跑下去只会制造一堆连带错误；停在哪一条、服务端说了
    ///    什么，都如实摆在 `statements` 里；
    /// ③ **取消之后不再往下跑**：调用方（命令层）在每一段之间检查取消标志 —— 取消是"停在这段"，
    ///    不是"把后面的也发出去"。
    pub async fn run_batch(
        &self,
        sql: &str,
        limit: usize,
        stop_on_error: bool,
    ) -> Result<Vec<StatementOutcome>, DbFailure> {
        let statements = doyah_studio_db::config::split_statements(sql);
        let mut out = Vec::with_capacity(statements.len());
        for text in statements {
            let started = std::time::Instant::now();
            match self.run(&text, limit).await {
                Ok(result) => out.push(StatementOutcome {
                    sql: text,
                    ok: true,
                    result: Some(result),
                    failure: None,
                    elapsed_ms: started.elapsed().as_millis() as u64,
                }),
                Err(failure) => {
                    out.push(StatementOutcome {
                        sql: text,
                        ok: false,
                        result: None,
                        failure: Some(failure),
                        elapsed_ms: started.elapsed().as_millis() as u64,
                    });
                    if stop_on_error {
                        break;
                    }
                }
            }
        }
        Ok(out)
    }
}

/// 多段执行里**一段**的结果（1.2 段）。
///
/// 为什么要逐段报告而不是合成一个总结果：一次提交五句、第三句错了，用户必须知道
/// **是哪一句**错了、前两句有没有生效、后两句跑没跑 —— 合成一个布尔等于把这些信息全丢掉。
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StatementOutcome {
    pub sql: String,
    pub ok: bool,
    /// 成功时的结果集（没有结果列的语句给空列 + 影响行数）
    pub result: Option<QueryResult>,
    /// 失败时的可读原因（服务端原话 + 提示）
    pub failure: Option<DbFailure>,
    /// 这一段耗时（毫秒）—— 计划与慢查询排查都要看它
    pub elapsed_ms: u64,
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
                // 这两项是**本进程记的**（"连到哪儿"），由 `connect` 随后填上 —— 取消请求要用它
                host: String::new(),
                port: 0,
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

/// 显示文本 → **数值形态**（解析不出就是 `None`）。
///
/// 口径：只认"看起来就是数"的串（可带正负号、小数、科学计数、前后空白）；
/// **千分位逗号不算**（`1,234` 在有的区域设置里是数字、有的不是 —— 判不准就不判，
/// 宁可让那一列按文本排，也不猜）。
pub fn numeric_view(rows: &[Vec<Option<String>>]) -> Vec<Vec<Option<f64>>> {
    rows.iter()
        .map(|row| {
            row.iter()
                .map(|cell| cell.as_deref().and_then(|s| s.trim().parse::<f64>().ok()))
                .collect()
        })
        .collect()
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
            num_rows: Vec::new(),
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