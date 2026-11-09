# Doyah产品详细设计说明书 · Windows

> **版本** v1.0.7（2026-11-09 三书合一同步（冻结段 v1.3）：能力书并入需求书，全产品三书一单；本册仍按 macOS 基准逐节同步）｜ v1.0.6（2026-11-08 按 macOS 基准 v1.2 同步：§0.2 处置 30 → 40 行、新增 §3.8 十节契约（3.31–3.40），契约逐条照抄基准、只标本端落点与「未测」；用途 = 本端暂不开发但详设跟得上，将来接任意一节照单实现）｜ v1.0.5（2026-11-05 正文重写：§2 分层按 136 条命令 / 53 模块 / 801 测试实读重写，§3 由 4 节扩到 14 节七段契约，§4–§11 全量重写）｜ v1.0.4（2026-11-05 加 §0.2 差异登记 30 行 + 头部「派生自 macOS 详设 v1.0.22」）｜ v1.0.3（（2026-10-26 编号改为「冻结段 + 流水」三段式：`v1.0.NNN`，NNN 上限 999，满了冻结为 v1.1）；承接历史流水 v1.2；原条目：2026-10-21 扫差补齐：补 Retro 章（本端有真实现 `plugins/retro/*` + `retro_library.rs`），矩阵补 §15/§16 两行）｜ v1.1（2026-10-21 订正：Windows 与 macOS / Linux 同为 **PC 全量端**（Studio + Notes + Retro）；上游契约 = `Docs/Doyah产品概要设计说明书.md` v0.6）

> **派生自**：`Docs/Doyah产品详细设计说明书-macOS.md` v1.2.0（对应冻结件 `Docs/frozen/Doyah产品详细设计说明书-macOS-v1.2-20261108.md`） —— 主人 2026-11-05 定法：平台详设以 macOS 为基准派生、按平台差异调整。
> 差异登记见 §0.2（macOS §3 逐节表态）；判据 = `Scripts/check-platform-derivation.py`。

## 0. 文档元信息与追溯关系

- 项目/功能名称：Doyah · Windows 端（**PC 全量端**：Studio 工作区与数据库 + Notes + Retro + Agent 在 Studio 内的表现 + 授权）
- 文档版本：v1.0.6（正文改动同步本节与 §12）
- 实现范围：`Platform/windows/`（Rust workspace：`Core` `Db` `App/src-tauri` `Cli` + Vue 前端）
- 上游依据：
  - 概要设计说明书：`Docs/Doyah产品概要设计说明书.md` v0.6
  - 需求规格书：`Docs/Doyah产品需求规格说明书.md`（Studio 线 `FR-STD-*` 227 条 / 27 族 + 笔记 `FR-NTS-*` 14 族）
  - 平台口径：需求书 §1.8.1 —— macOS（基线）、Windows、Linux、iOS 同为一等目标端
  - 能力规划书：`Docs/Doyah产品能力规划说明书.md` v1.247
  - 平台对齐件：`Docs/平台对齐-Studio-Windows对macOS.md`（逐条派生索引，勿手改）
- 本文件性质：**概要设计的实现级展开**（Windows 端怎么实现、怎么证明）。
- 优先级：需求规格书 > 概要设计 > 本详细设计 > 现有代码。
- 冲突处理：与概设冲突 ⇒ 以概设「禁止」为准，输出 `DESIGN_CONFLICT`，不自行裁决。
- 禁止行为：不得跨端复制 macOS 的类型名当契约；不得改 `Platform/macOS/**`、`Platform/linux/**`；不得放宽 `Tools/*.ps1` 判据。

### 0.2 与 macOS 基准的差异登记（逐节表态）

| macOS 节 | 处置 | 依据 / 本端落点 |
|---|---|---|
| `§3.1` | 沿用 | 同源 Rust 连接层（`Db`）就在本端，Windows 是它的宿主 |
| `§3.2` | 差异 | 凭据落 Windows 凭据管理器（`CredRead`，见 `connections.rs`），不是文件 / 钥匙串；连接清单同源 `connections.json` |
| `§3.3` | 沿用 | 执行走同源 `Db` + 外壳命令 |
| `§3.4` | 沿用 | 取消语义同源 |
| `§3.5` | 沿用 | 执行安全判定同源，本端不改口径 |
| `§3.6` | 差异 | macOS 是 Swift 侧 `AgentApprovalGate`；本端用同源 `agent::Approval` |
| `§3.7` | 沿用 | 元数据加载同源 |
| `§3.8` | 沿用 | 行浏览查询同源 |
| `§3.9` | 差异 | macOS 由 `AppState` 持有编辑状态；本端状态在同源 `ShellState` |
| `§3.10` | 沿用 | 结构脚本执行同源 |
| `§3.11` | 沿用 | 导出格式渲染同源（流式写文件） |
| `§3.12` | 沿用 | 导入计划同源 |
| `§3.13` | 沿用 | 会话监控同源；终止前二次确认由界面负责 |
| `§3.14` | 差异 | 上下文装配在 `agent_generate::build_chat_request_with_context` |
| `§3.15` | 差异 | 工具只有 `read_file` / `write_file`；调度入口 `chat_tool_resume` |
| `§3.16` | 不适用 | 同源无 `Plan Rows` 解析（本端检索命中 0） |
| `§3.17` | 不适用 | 同源 `is_known_chat_tool` 不认 `run_command` |
| `§3.18` | 不适用 | 同源无代码执行器 |
| `§3.19` | 不适用 | 同源无工具目录检索 |
| `§3.20` | 不适用 | 同源无并行编排 |
| `§3.21` | 不适用 | 同源无压缩准入 |
| `§3.22` | 不适用 | 同源无工具注册表 |
| `§3.23` | 不适用 | 同源无会话生命周期钩子 |
| `§3.24` | 不适用 | 记忆账本两侧均未建；界面不出现记忆页 |
| `§3.25` | 不适用 | IM 通道只在 macOS 侧；本端无扫码桥 |
| `§3.26` | 差异 | 只允许工作区内相对路径，不提供「授权一次」入口 |
| `§3.27` | 不适用 | 同源无联网工具 |
| `§3.28` | 不适用 | `Platform/windows` 内检索 DAP 命中 0，本端不做调试会话 |
| `§3.29` | 差异 | 对话区就是本端前端（`Platform/windows/App/src/`），步数口径与详单上限尚未接 |
| `§3.30` | 不适用 | 无委派能力 |
| `§3.31` | 不适用 | 同源命令层无 `rg` 随包与三级回落（`src-tauri` 检索命中 0） |
| `§3.32` | 不适用 | 同源无多词 / 缓存 / 预算实现 |
| `§3.33` | 差异 | 对话区就是本端前端（`App/src/`），结论/过程折叠口径尚未接 |
| `§3.34` | 不适用 | 前端无吸顶条（组件检索命中 0） |
| `§3.35` | 不适用 | 前端无 ↑↓ 历史回填（`composerHistory` 命中 0） |
| `§3.36` | 差异 | 审批走同源 `agent::Approval`；三档账本未建 |
| `§3.37` | 不适用 | 前端无过程区折展与高度自适应 |
| `§3.38` | 差异 | 工作区根参数在同源命令层；落 Windows 数据目录，不写死 `~/.doyah` |
| `§3.39` | 不适用 | 前端无「回到消息底部」入口（`jumpToBottom` 命中 0） |
| `§3.40` | 不适用 | 同源只有单组端点/模型，无档清单与每档密钥条目 |

### 0.1 概设—详设追溯矩阵（Studio 线，Windows 落点）

| 概设章节 | 条款摘要 | 详设落点 | 实现单元 | 测试 |
|---|---|---|---|---|
| §3 组件契约 | 四层单向；禁越层 | 2.1 | `Core`（领域）+ `App/src-tauri`（外壳） | `T-2.1-01` |
| §4.1 连接建立 | 四类行为；凭据不入请求体 | 3.1 | `App/src-tauri/src/connections.rs` | `T-3.1-01` |
| §4.2 连接删除 | 连带清凭据 | 3.2 | 同上 + 凭据存储 | `T-3.2-01` |
| §4.3 语句执行 | 选区判定、逐条上报 | 3.3 | `Db` crate 执行面 | `T-3.3-01` |
| §4.4 执行取消 | 服务端真取消 | 3.4 | `Db` 取消路径 | `T-3.4-01` |
| §4.5 元数据列举 | 层级按类型 | 3.2 | `Db` 元数据查询 | `T-3.5-01` |
| §4.6 行编辑 | 主键保护、原值条件、冲突不覆盖 | 3.5 | `edits_to_dml` / `db_write_batch` | `T-3.5-01`、`T-3.5-02` |
| §4.7 结构变更 | 预览闸、危险动作确认 | 3.6 | `generate_ddl` / `db_run_ddl` | `T-3.6-01`、`T-3.6-02` |
| §4.8 导入导出 | 流式写、计划先行 | 3.7 | `export_to_file` / `preview_import` | `T-3.7-01`、`T-3.7-02` |
| §15 笔记域（14 节） | 捕获/附件/检索/私密/回收站/待办 | 3.13 | Notes 端实现（契约同 §15） | `T-9.1-01` |
| §16 复盘域（18 节） | 行情/特征/回测/复盘稿/周报 | 3.13 | `App/src/plugins/retro/*` + `App/src-tauri/src/retro_library.rs` | `T-16.1-01` |
| §5 数据契约 | 连接配置/记录/任务/审批 | 4.1 | `Core`（`dataset.rs` / `result_set.rs`） | `T-4.1-01` |
| §6 状态机 | 连接/执行/审批/页签闭集 | 4.2 | `Core` 状态类型 | `T-4.4-01` |
| §7 关键流程 | 查询全链 | 3.2、3.5 | 外壳编排 | `T-3.3-02` |
| §8 界面契约 | 六态/导航/动作映射 | 5.1–5.4 | `App/src`（Vue：`App.vue` `grid/` `sql/`） | `UI-5.3-01` |
| §9 错误（21 码） | 逐码落点 | 6.1 | 外壳错误映射 + 前端呈现 | `T-6.1-01` |
| §10 被拒方案（12） | 不得引入 | 1.1 | — | 静态检查 |
| §11 非功能 | 并发/权限/网络出口 | 7、8 | Rust 并发 + Tauri 权限 | `T-7.1-01` |

## 1. 基线与禁止项

| 项 | 取值 | 说明 |
|---|---|---|
| 语言 | Rust（2021 edition）+ TypeScript/Vue | workspace 成员：`Core` `Db` `App/src-tauri` `Cli` |
| 外壳 | Tauri | `App/src-tauri/src/main.rs`、`lib.rs`；前端 `App/src/main.ts` |
| 前端 | Vue + 虚拟表格 | `App/src/App.vue`、`App/src/grid/`、`App/src/sql/`、`App/src/i18n/` |
| 构建 | `Tools/build.ps1` | 干净克隆可出包 |
| 判据 | `Tools/*.ps1`（`check-core-boundary` / `check-platform-neutrality` / `check-platform-parity` / `check-design-tokens` / `check-doc-tables` / `check-exclusive-sections` / `check-path-ownership` / `check-grid-bench`） | 全绿才落档 |

概设 §10 的 12 条被拒方案在本端的禁止项：

| 概设 §10 被拒绝方案 | Windows 禁止项 | 检查方式 |
|---|---|---|
| 只读连接给「仍然执行」 | 禁止绕过只读判定的前端入口 | `check-core-boundary.ps1` + 用例 |
| `EXPLAIN ANALYZE` 估行数 | 仅 `EXPLAIN (FORMAT JSON)` | 代码检索 |
| 行数用总数或猜测 | 取不到如实说 | 用例 |
| 写语句自动重试 | 禁止 | 代码检索 |
| 界面层缓存服务对象 | 服务按「连接 + 库」唯一（外壳持） | 评审 |
| 整表读内存导出 | 流式写 | 代码检索 |
| 多语句并发 | 按文本顺序逐条 | 用例 |
| 未授权入口灰色 | 不出现 | 用例 |
| 到期锁死数据 | 降级可导出 | 用例 |
| 行数据默认投助理 | 显式确认 + 留痕 | 用例 |
| 读数写进契约 | 只进台账 | 评审 |
| 日志面板冒充终端 | 真 PTY | 用例 |

## 2. 分层与模块

### 2.1 四层与真实规模

| 层 | 落点 | 规模 | 职责 | 禁止 |
|---|---|---|---|---|
| 表示层（前端） | `App/src/**`（Vue 3 + TS） | 87 个 `*.test.ts`（含 mount 用例） | 视图、六态、动作映射、i18n | 不直连驱动、不写业务规则、不做日期/金额算术 |
| 外壳层（IPC） | `App/src-tauri/src/*.rs`（19 个模块） | **136 条 `#[tauri::command]`** | 命令边界、状态持有（`ShellState`）、子进程（PTY / 备份）、路径校验 | 不复制 `Db` 的判定；不绕过凭据入口 |
| 能力层 | `Db/src/*.rs`（53 个模块） | **801 个 `#[test]`**（`agent_generate.rs` 44 · `retro_library.rs` 36 · `tree.rs` 30 · `fs.rs` 28 · `config.rs` 27 · `agent_nl2sql.rs` 27 · `retro_package.rs` 25 · `workspace.rs` 21 …） | SQL 方言、数据集、元数据、导入导出、Agent 纯逻辑、复盘包 | 不碰 UI、不读环境变量以外的宿主状态 |
| 领域层 | `Core` | 数据集 / 结果集 / 状态类型 | 跨端同源的纯类型与算法 | 零平台依赖 |

- 本端**同时是 PC 族基准的「实现宿主」**：Linux 的外壳直接依赖 `App/src-tauri`（`doyah-studio-shell`），
  所以这一端的命令边界一旦松动，Linux 会跟着松。改动命令签名 = 跨端变更，必须两侧同批。
- 判据：`T-2.1-01`（四层边界静态检查）、`T-2.1-02`（命令总数与登记表一致）。

### 2.2 命令族（136 条，按族归并）

| 族 | 条数 | 代表命令 | 对应契约 |
|---|---:|---|---|
| `workspace_*` | 27 | `workspace_read_file` · `workspace_save` · `workspace_check_staleness` · `workspace_replace_preview/apply` · `workspace_search` | §3.9 |
| `db_*` | 19 | `db_connect` · `db_query` · `db_run_batch` · `db_cancel` · `db_browse_sessions` · `db_write_batch` · `db_run_ddl` | §3.2–§3.6 |
| `agent_*` | 18 | `agent_chat_send` · `agent_chat_tool_resume` · `agent_write_preview/undo` · `agent_key_save/clear` · `agent_audit_list/export` | §3.10–§3.12 |
| `retro_*` | 8 | `retro_packages` · `retro_report` · `retro_import_batch` · `retro_export` | §3.14 |
| `connection_*` | 5 | `connection_save` · `connection_delete` · `connection_validate` · `connection_import_url` | §3.1 |
| `restore_*` | 5 | `restore_plan` · `restore_run` · `restore_cancel` · `restore_plan_sections` | §3.7 |
| `backup_*` | 4 | `backup_plan` · `backup_run` · `backup_cancel` · `backup_progress` | §3.7 |
| `terminal_*` | 4 | `terminal_open` · `terminal_write` · `terminal_read` · `terminal_close` | §3.8 |
| `sql_*` / `saved_*` / `archive_*` / `export_*` / `admin_*` / `command_*` | 3+3+3+3+3+3 | `sql_format` · `saved_query_save` · `archive_write` · `export_to_file` · `admin_sessions` · `command_history_record` | §3.3–§3.6、§3.13 |
| `schema_*` / `appearance_*` | 2+2 | `schema_snapshot` · `schema_diff_plan` · `appearance_set` | §3.6 |
| 单条（24 族） | 24 | `app_info` · `plugins_manifest` · `dataset_summary` · `grid_window` · `explain_statement` · `statement_risk` · `edits_to_dml` · `preview_import` · `run_import` · `xlsx_to_csv` · `terminate_sql` … | 各自契约节 |

- 判据：`T-2.2-01`（`generate_handler!` 清单与本节族表逐条对账；新增命令必须同时改本节）。

### 2.3 注入点与可替换依赖

| 注入点 | 生产实现 | 替身（测试用） | 不许注入什么 |
|---|---|---|---|
| 数据库驱动 | `Db` 内的方言实现 | 内存替身（`Db` 单测） | 不许在命令层注入第二套驱动 |
| 凭据 | Windows 凭据管理器（`CredRead` / `CredWrite`） | 内存替身 | 不许注入明文文件后端 |
| 时钟 / ID | 系统 | 固定值 | 不许在界面层取当前时间做业务判定 |
| 子进程（PTY / 备份 / 恢复） | 真进程 | 假进程脚本 | 不许在测试里真调 `pg_dump` |

- 判据：`T-2.3-01`（替身全部生效且不改生产代码）。

### 2.4 目录与命名约束

- `App/src-tauri/src/lib.rs` 只放**命令注册与薄适配**；业务逻辑进 `Db`。`lib.rs` 已 3200+ 行 —— 新增命令必须带 `#[tauri::command]` 与登记行，否则 `T-2.2-01` 判红。
- 前端：视图在 `App/src/views/*.vue`，插件在 `App/src/plugins/{notes,retro}`；**不许**在视图里写方言关键字。
- 数据家：一律 `paths::app_path(...)`，不许手拼 `%APPDATA%`。

## 3. 关键契约

> 体例：每节 = 落点 / 用途 / 前置 / 后置 / 错误契约 / 禁止行为 / 并发·幂等 / 日志 / 测试 ID。
> 与 macOS 同语义的节只写**本端差异**并注明基准节，不把 macOS 的正文抄一遍（抄一遍就一定会漂）。

### 3.1 连接与凭据：`connection_save` · `connection_delete` · `connection_validate` · `db_connect` · `db_disconnect`

- 落点：`App/src-tauri/src/connections.rs`（IPC）+ Windows 凭据管理器（`CredRead` / `CredWrite`）｜ 基准：macOS §3.1 / §3.2
- 用途：保存连接（凭据进凭据管理器、配置进 `connections.json`）、连接 / 断开、校验可达性。
- 前置：连接标识稳定；类型 ∈ 支持的方言闭集；未保存的连接不许被 `db_connect` 直接使用。
- 后置：
  - 口令**只进凭据管理器**，`connections.json` 里只有引用；保存成功后重开应用仍能连（凭据可恢复）
  - 删除连接**先清凭据再删配置**；清凭据失败 ⇒ 报 `CRED_PURGE_FAILED` 并明说残留位置（不许只删列表项）
  - `db_disconnect` 幂等：未连接时返回成功，不报错
  - `connection_validate` 只做可达性与认证判定，不建长连接、不缓存结果
- 错误契约

| 场景 | 错误码 | 可重试 | 禁止行为 |
|---|---|---|---|
| 主机解析不了 / 端口不通 | `CONN_UNREACHABLE` | 是（改配置后） | 禁止把「解析失败」当成「口令错」 |
| 认证失败 | `CONN_AUTH_FAILED` | 是（改口令） | 禁止回显口令 |
| 凭据管理器不可用 | `CONN_NO_CREDENTIAL` | 是（修系统后） | 禁止回落明文文件 |
| 无此连接 | `CONN_NOT_FOUND` | 否 | 禁止静默新建一条同名连接 |
| 删除时清凭据失败 | `CRED_PURGE_FAILED` | 是（重试删除） | 禁止先删配置再清凭据（反了会留下孤儿凭据） |

- 禁止：把口令写进 `connections.json`、日志、IPC 返回值；用「测试连接成功」当保存成功的替代。
- 并发·幂等：保存与删除串行（同一连接）；`db_connect` 同一连接重复调用返回同一服务对象。
- 日志：`connection_id`、`dialect`、`duration_ms`、`result`；禁记口令与连接串原文。
- 测试 ID：`T-3.1-01`（存→重启→可连）、`T-3.1-02`（删连接先清凭据，失败即报残留）、`T-3.1-03`（配置里无口令）

### 3.2 语句执行：`db_query` · `db_run_batch` · `statement_risk` · `db_read_only`

- 落点：`App/src-tauri/src/query.rs` + `Db` 执行面 ｜ 基准：macOS §3.3
- 用途：执行一段 SQL（可能多语句），逐条上报结果；执行前给风险判定。
- 前置：连接已建立；SQL 去空白后非空；只读连接上的写语句在执行前就被拒。
- 后置：
  - **按文本顺序逐条执行**，多结果集按序返回；单条失败即停并上报已执行条数（不续跑后续）
  - 只读连接的判定结果与 `db_read_only` 一致（同一处口径，不许界面自判）
  - `statement_risk` 给四类（读 / 写 / DDL / 未知）+ 风险点；**未知一律按需确认**处理
  - 结果集超 `grid_window` 上限时按窗口取，界面滚动再取，不整表进内存
- 错误契约

| 场景 | 错误码 | 可重试 | 禁止行为 |
|---|---|---|---|
| 空语句 | `EXEC_EMPTY_SQL` | 否 | 禁止当成功 |
| 只读连接写操作 | `EXEC_READONLY_DENIED` | 否 | 禁止提供「仍然执行」 |
| 需二次确认 | `EXEC_CONFIRM_REQUIRED` | 等确认 | 禁止白名单静默放行 |
| 连接中途断开 | `EXEC_CONNECTION_LOST` | 是（重连后重跑） | 禁止自动重跑写语句 |
| 服务端报错 | `EXEC_SERVER_ERROR` | 依错误码 | 禁止改写服务端原文当自造错误 |

- 禁止：对写语句自动重试；把多语句拆到多个线程并发；在界面层拼 SQL。
- 并发·幂等：一个连接上执行串行；读语句可重复，写语句非幂等。
- 日志：`connection_id`、`statements`、`rows`、`duration_ms`、`outcome`；禁记 SQL 原文（原文进 `queries/<date>.sql` 归档）。
- 测试 ID：`T-3.2-01`（三条语句按序、第二条失败即停）、`T-3.2-02`（只读连接拒写）、`T-3.2-03`（窗口取数不整表）

### 3.3 取消：`db_cancel`

- 落点：`Db` 取消路径（服务端取消请求）｜ 基准：macOS §3.4
- 用途：真取消正在跑的服务端语句，而不是只把界面转圈停掉。
- 前置：有正在执行的语句且拿到了其后端进程标识（连接级）。
- 后置：服务端语句被取消；界面收到取消结局；**执行中的客户端连接不被关闭**（可继续跑下一条）。
- 错误契约

| 场景 | 错误码 | 可重试 | 禁止行为 |
|---|---|---|---|
| 没有在跑的语句 | `EXEC_CANCEL_ILLEGAL` | 否 | 禁止把「没得取消」当取消成功 |
| 取消请求发不出去 | `EXEC_CANCEL_FAILED` | 是（再点一次） | 禁止悄悄关连接当取消 |
| 语句已结束 | 成功（无副作用） | — | 禁止报错打断用户 |

- 禁止：用「关闭连接」实现取消；取消后把已取到的部分结果当完整结果。
- 并发·幂等：同一语句重复取消幂等；取消与执行同连接串行进入驱动。
- 日志：`connection_id`、`cancel_requested_at`、`outcome`。
- 测试 ID：`T-3.3-01`

### 3.4 会话与终止：`db_browse_sessions` · `db_session_close` · `admin_sessions` · `terminate_sql`

- 落点：`Db` 会话监控 + `lib.rs` 命令 ｜ 基准：macOS §3.13
- 用途：看当前库上的活动会话；终止某个后端进程（危险动作，二次确认）。
- 前置：连接可执行查询；终止需用户确认（`confirm` 类命令）。
- 后置：会话列表含 `pid` / 用户 / 状态 / 起始时间 / 当前语句摘要；**终止只影响目标 pid**；终止后列表刷新一次。
- 错误契约

| 场景 | 错误码 | 可重试 | 禁止行为 |
|---|---|---|---|
| 未确认就终止 | `SESS_KILL_REQUIRED_CONFIRM` | 等确认 | 禁止默认勾选确认 |
| 无权限终止 | `SESS_KILL_DENIED` | 否 | 禁止改写为「已终止」 |
| 目标已结束 | `SESS_NOT_FOUND` | 否 | 禁止当成功 |

- 禁止：批量终止不带确认；把其他用户的会话信息当自己的数据展示（只展示有权限读的字段）。
- 并发·幂等：终止请求幂等（对已结束 pid 报 `SESS_NOT_FOUND`）。
- 日志：`pid`、`target_user`、`confirmed`、`outcome`。
- 测试 ID：`T-3.4-01`

### 3.5 行编辑：`edits_to_dml` · `db_write_batch` · `db_primary_key` · `db_table_shape` · `inspect_row`

- 落点：`Db`（DML 生成与批量写）+ `lib.rs` ｜ 基准：macOS §3.9
- 用途：把界面上的单元格编辑换算成 DML，按批提交；没有主键的表拒写。
- 前置：目标表有主键（`db_primary_key` 非空）；编辑前记录了原值（乐观锁）。
- 后置：
  - 一批编辑 → 一批 DML；**逐条带原值条件**（`WHERE pk = ? AND 原值`），影响行数 0 ⇒ 判冲突
  - 冲突时不静默覆盖：返回冲突行清单，界面标红
  - 写入不触发结构变更；不改主键
- 错误契约

| 场景 | 错误码 | 可重试 | 禁止行为 |
|---|---|---|---|
| 无主键 | `DATA_NO_PK` | 否 | 禁止用「全部列当主键」凑一个 |
| 行被他人改过 | `DATA_WRITE_CONFLICT` | 是（刷新后再改） | 禁止强写 |
| 写入失败 | `DATA_WRITE_FAILED` | 依原因 | 禁止部分成功后报全成功 |
| 类型不兼容 | `DATA_WRITE_FAILED` + 字段明细 | 是（改值） | 禁止隐式转换后写入 |

- 禁止：整表替换式写；把「影响 0 行」当成功；在界面里拼 DML。
- 并发·幂等：一批一个事务；同一行并发编辑以原值条件串行化。
- 日志：`table`、`rows`、`conflicts`、`duration_ms`；禁记单元格原值。
- 测试 ID：`T-3.5-01`（无主键拒写）、`T-3.5-02`（并发改同一行 ⇒ 冲突不覆盖）

### 3.6 结构与差异：`generate_ddl` · `db_run_ddl` · `schema_snapshot` · `schema_diff_plan` · `confirm_drop_database`

- 落点：`Db` 结构面 + `lib.rs` ｜ 基准：macOS §3.10
- 用途：生成 DDL、预览差异、执行结构变更；删库这类动作必须二次确认。
- 前置：DDL 执行前必须走「预览 → 确认」；`confirm_drop_database` 需要用户输入库名确认。
- 后置：
  - 预览与实际执行**用同一份 DDL 文本**（预览过的和跑的是同一串，不许重新生成）
  - 差异计划列出新增 / 修改 / 删除三档，删除项单独标出
  - 执行结果逐语句上报；失败即停
- 错误契约

| 场景 | 错误码 | 可重试 | 禁止行为 |
|---|---|---|---|
| 未预览直接执行 | `DDL_PREVIEW_REQUIRED` | 否 | 禁止「先跑了再补预览」 |
| 危险 DDL 未确认 | `DDL_CONFIRM_REQUIRED` | 等确认 | 禁止默认确认 |
| 执行失败 | `DDL_FAILED` | 依原因 | 禁止回滚后报「已撤销」（服务端可能已部分生效） |

- 禁止：把 `DROP DATABASE` 放进批量脚本静默执行；用差异计划直接改库（差异是给人看的）。
- 并发·幂等：结构变更串行；同一 DDL 重跑由服务端报错决定（本端不加幂等包装）。
- 日志：`object`、`kind`、`statements`、`outcome`。
- 测试 ID：`T-3.6-01`（未预览执行被拒）、`T-3.6-02`（删库需输名确认）

### 3.7 导出与导入：`export_to_file` · `export_table_copy` · `export_schema_copy` · `preview_import` · `run_import` · `xlsx_to_csv`

- 落点：`Db` 导入导出 + `lib.rs` ｜ 基准：macOS §3.11 / §3.12
- 用途：把结果 / 整表 / 整库流式导出成文件；把文件导入表（先出计划再执行）。
- 前置：导出目录可写；导入前目标表结构已取到。
- 后置：
  - **流式写**：不整表进内存；中断留下的是半份文件，且明确告知「未完成」
  - 导入前给计划：行数估算（取不到写「未接」，不写 0）、列映射、冲突策略
  - `xlsx_to_csv` 只做格式转换，不改内容
- 错误契约

| 场景 | 错误码 | 可重试 | 禁止行为 |
|---|---|---|---|
| 目标文件已存在 | `IO_TARGET_EXISTS` | 是（换名/覆盖确认） | 禁止静默覆盖 |
| 半途失败 | `IO_PARTIAL` | 是 | 禁止报成功 |
| 格式不支持 | `IO_FORMAT_UNSUPPORTED` | 否 | 禁止「尽力而为」写坏文件 |

- 禁止：整表读进内存再写；把估算行数当真实行数展示。
- 并发·幂等：一个导出任务一个文件；同任务重复启动拒绝。
- 日志：`format`、`rows`、`bytes`、`partial`。
- 测试 ID：`T-3.7-01`（大表导出内存不涨）、`T-3.7-02`（中断留半份并如实报）

### 3.8 智能体对话面十节契约（与 macOS 基准 v1.2 逐条一致，本端多处未实现）

> **派生自** macOS 详设 v1.2 §3.31–§3.40（冻结件 20261108）。**写这节的用途**：本端虽然暂不开发，
> 契约必须与基准**逐条一致**；将来接任意一节时照单实现，不许各自发明口径。
> 本端现状依据 = 同源命令层 / 前端检索（`rg` / `jumpToBottom` / `composerHistory` / 档管理均命中 0），
> **不是逐条真机实测** —— 覆盖不全只报「未核」，不报「已核」。

1. **搜索工具引擎（基准 §3.31）**：三级顺序固定（随包 → PATH → 内置），前两级不可用必须**静默回落**，不许抛错、不许返回空集；语义差异（大小写 / 变音符号 / 截断子集）必须写死。**本端：不适用**（命令层无 `rg`）。
2. **搜索策略（§3.32）**：多词一次搜 + 同轮缓存（TTL 60 秒、写改即作废）+ 只读工具按**能力**记预算 + 截断如实报数。**本端：不适用**。
3. **展示优先级（§3.33）**：结论默认**整段**展开；断言台账 / 思考段 / 步骤详单一律「摘要行 + 限高 + 内部滚动」，高度只由常量定；未核断言必须在**折叠那一行**告警。**本端：差异**（前端在，口径未接）。
4. **当前轮提问吸顶（§3.34）**：只吸当前轮、只吸一行（20pt）、是滚动区上面的兄弟视图（不遮正文）、点击回到该消息顶边。**本端：不适用**。
5. **输入框历史（§3.35）**：只在首行行首 / 末行行末接管 ↑↓；草稿不丢、只回填不发送；提交成功才入史、上限 200、连续重复去重、落盘。**本端：不适用**。
6. **审批三档（§3.36）**：仅这一次 / 本会话内 / 总是允许；记账键 = 工具名 + 规范化作用域值（禁止只写工具名）；越界 / 删除 / 对外发送 / 凭据只留「仅这一次」，盘上有全局授权也不认；授权可逐条撤。**本端：差异**（走同源 `agent::Approval`，三档账本未建）。
7. **过程区高度（§3.37）**：展开高 = `min(抬头 + 发丝 + 内容实测高, 200)`、视口 = `min(实测, 178)`，实测高按整行向上取（不许逐 token 抖）；运行中→终态只许一次跳变。**本端：不适用**。
8. **工作区根两态（§3.38）**：只有「默认 / 用户打开」两态、来源可见、已显式选择后不回落、迁移换根给提示；Agent 读写搜索命令边界一律取这个根。**本端：差异**（根参数在，路径落 Windows 数据目录）。
9. **回到消息底部（§3.39）**：距底 > 40pt 且不贴底时出现，落在保留窄条里（高 22pt、不压正文），点击滚到内容底边并恢复跟随；不在滚动链上。**本端：不适用**。
10. **模型档位（§3.40）**：档 = 端点 + 模型名 + 超时 + 每档独立密钥条目；可增删切换、**最后一档不许删**、切档不改写历史会话、密钥不进配置文件。**本端：不适用**（同源只有单组端点/模型）。

**判据**：上述十条的判据编号同基准（`T-3.31-01` … `T-3.40-06`）；**本端未测** —— 基准读数不搬到本端。

## 4. 数据与状态

### 4.1 存储落点（唯一清单）

| 存储 | 路径（`paths::app_path` 之下） | 权限 | 写入方 | 崩溃后语义 |
|---|---|---|---|---|
| 连接清单 | `connections.json` | 用户目录 | 连接管理 | 损坏 ⇒ 读成空清单并**保留原文件** |
| 凭据 | Windows 凭据管理器（`CredRead` / `CredWrite`） | 系统托管 | `connection_save` / `agent_key_save` | 取不到 ⇒ 报缺凭据，不回落明文 |
| 查询归档 | `queries/<YYYY-MM-DD>.sql` | 用户目录 | 执行路径 | 只增不改 |
| 保存的查询 | `saved-queries.json` | 用户目录 | 保存 / 删除 | 原子替换 |
| 工作区历史 | `workspace-history.json` | 用户目录 | 打开 / 关闭 | 原子替换 |
| 外观 | `appearance.json` | 用户目录 | 设置面板 | 损坏 ⇒ 默认值 + 保留原文件 |
| 命令历史 | `command-history.json` | 用户目录 | 面板 | 有上限，超出丢最旧 |
| Agent 会话 | `chat/` | 用户目录 | `agent_chat_save` | 读坏 ⇒ 空会话 + 保留原文件 |
| Agent 撤销凭据 | `agent-undo/` | 用户目录 | 写盘 | 哈希不符 ⇒ 拒撤 |
| Agent 审计 | `agent-audit.json` | 用户目录 | 调用收口 | 读坏 ⇒ 空账 + 如实报 |
| 复盘包 | `retro/packages/` | 用户目录 | 导入 | 按包原子落盘 |

- 序列化契约：JSON 字段名 = 结构体字段名；时间一律 ISO8601；空值 `null`、空集合 `[]`；布尔显式 `true`/`false`。
- 禁止：手拼 `%APPDATA%`；把手写的临时路径写进任何配置文件；把口令/令牌放进上表任何一份 JSON。

### 4.2 状态机（四台，闭集）

| 状态机 | 合法流转 | 触发 | 禁止 |
|---|---|---|---|
| 连接 | 未连接 → 连接中 → 已连接 / 失败 | `db_connect` | 跳过「连接中」直接置已连接 |
| 执行 | 空闲 → 执行中 → 完成 / 失败 / 已取消 | `db_query` / `db_cancel` | 已取消再置完成；把取消当失败上报给用户 |
| 审批 | 待确认 → 已确认 / 已拒绝 | 用户点 | 默认确认；拒绝后翻回确认 |
| 页签 | 打开 → 脏 → 保存 → 关闭 | 编辑 / 保存 | 脏页签直接关（必须先问） |

- 新增状态或新增流转 = 改概设并同批改本节；`match` 必须穷尽，`_ =>` 兜住枚举即判红。

### 4.3 事务与幂等边界

- 一次写动作（行编辑批 / DDL 脚本 / 导入）一个事务；**归档与审计属动作后置**，失败只报「记录未落盘」，不回滚已成功的业务。
- 删除连接：先清凭据、再删配置（顺序反了会留孤儿凭据）。
- 备份 / 恢复的子进程产物：取消后标记不完整，不参与「最近一份可用备份」的判定。

## 5. 界面

### 5.1 视图落点

| 面 | 落点 | 关键约束 |
|---|---|---|
| 主壳 | `App/src/App.vue` + `shell/` | 分栏与导航；不在组件里做业务判定 |
| 数据库面 | `views/DatabaseView.vue` + `grid/` | 结果网格窗口取数、编辑乐观锁、页签脏态 |
| 工作区面 | `workspace/` 视图族 | 文件树、编辑区、外部改动提示 |
| 终端面 | 终端视图 + `pty` 命令 | 真 PTY；宽字符与颜色由前端渲染 |
| 笔记 / 复盘 | `plugins/notes` · `plugins/retro` | 插件挂载；清单由 `plugins_manifest` 决定 |
| 设置与关于 | 设置视图 / 关于面板 | 版本读构建产物；功能清单按 `FR-STD-WS-HELP-003` 同口径 |

### 5.2 六态（每面必齐）

空态（说清「还没有」而不是空白）· 载入态（骨架或逐段，禁假进度）· 失败态（机器码 → 人话 + 可重试）· 只读态（禁用动作并说明原因）· 越权态（入口不出现，不是灰掉）· 满态（长列表虚拟滚动）。

- 判据：`UI-5.2-01`（六态齐）、`UI-5.2-02`（禁止渲染项：假进度、灰掉冒充越权、空容器）。

### 5.3 IPC 边界与 CSP

- 前端只能调 `generate_handler!` 里登记的命令；命令参数与返回值是**唯一的跨界契约**，改签名 = 跨端变更（Linux 复用本端外壳）。
- CSP 现为 `default-src 'self'; img-src 'self' data: blob:; media-src 'self' blob:; style-src 'self' 'unsafe-inline'; connect-src ipc: http://ipc.localhost` —— 新增外部域名必须同批改本节与 `tauri.conf.json`。
- 判据：`T-5.3-01`（前端 ipc 调用集合 ⊆ 命令清单）、`T-5.3-02`（CSP 与本节逐字一致）。

### 5.4 界面测试面

- 87 个 `*.test.ts`（含 mount 用例）：`DatabaseView.*` 20+ 个（编辑、撤销、诊断、导入导出、分屏、状态栏…）、`App.mount.test.ts`、`ipc.test.ts`。
- 判据：`npm test` 全绿；新增视图必须带 mount 用例（否则六态判据无依据）。

## 6. 错误映射

| 概设 21 码 | 本端落点 | 状态 |
|---|---|---|
| `CONN_INVALID_CONFIG` | 连接表单校验（`connection_validate` 前置） | 已实现 |
| `CONN_UNREACHABLE` / `CONN_AUTH_FAILED` | `connections.rs` 失败分类 | 已实现 |
| `CONN_NO_CREDENTIAL` | 凭据管理器取不到 | 已实现 |
| `CONN_NOT_FOUND` | 连接清单查找 | 已实现 |
| `CRED_PURGE_FAILED` | 删除连接时清凭据失败 | 已实现 |
| `EXEC_EMPTY_SQL` / `EXEC_NO_CONNECTION` / `EXEC_READONLY_DENIED` / `EXEC_CONFIRM_REQUIRED` | 执行前判定（`query.rs` + `Db`） | 已实现 |
| `EXEC_CANCEL_ILLEGAL` / `EXEC_CANCEL_FAILED` | `db_cancel` | 已实现 |
| `EXEC_CONNECTION_LOST` / `EXEC_SERVER_ERROR` | 驱动错误分类 | 已实现 |
| `DATA_NO_PK` / `DATA_WRITE_CONFLICT` / `DATA_WRITE_FAILED` | `edits_to_dml` / `db_write_batch` | 已实现 |
| `DDL_PREVIEW_REQUIRED` / `DDL_CONFIRM_REQUIRED` / `DDL_FAILED` | 结构面 | 已实现 |
| `IO_TARGET_EXISTS` / `IO_PARTIAL` / `IO_FORMAT_UNSUPPORTED` | 导出导入 | 已实现 |
| `SESS_KILL_REQUIRED_CONFIRM` / `SESS_KILL_DENIED` / `SESS_NOT_FOUND` | 会话终止 | 已实现 |
| `META_UNSUPPORTED` / `META_FAILED` | 元数据面 | 已实现 |
| `LIC_NO_CAPABILITY` | 授权降级（入口不出现） | 已实现 |

本端独有码（概设没有、只在这一端出现）：`TOOL_MISSING`（缺备份工具）、`PROCESS_FAILED`（子进程失败带退出码）、`SHELL_MISSING` / `TERM_NOT_FOUND`（终端）、`PATH_OUTSIDE_WORKSPACE` / `FILE_STALE` / `FILE_TOO_LARGE`（工作区）、`RETRO_PACKAGE_INVALID`（复盘包）。

- 禁止：把本端独有码写成界面文案（文案由语言表按码映射）；把服务端原文改写成自造错误。

## 7. 并发与线程

| 场景 | 模型 | 禁止 |
|---|---|---|
| 命令调用 | Tauri 异步运行时；重活进 `spawn_blocking`（Agent 对话、备份、导入） | 在异步线程里做阻塞 IO |
| 一个连接上的语句 | 串行 | 同一连接并发执行 |
| 终端 | 一条会话一个读线程 + 写入队列 | 用事件循环轮询读 |
| 备份 / 恢复 | 独立子进程 + 进度通道 | 在 UI 线程 join 子进程 |
| 取消 | 信号传给驱动 / 子进程，等待真退出 | 「标记取消」后当已取消 |
| 文件保存 | 按路径串行 + 原子替换 | 并发写同一文件 |

- 判据：`T-7.1-01`（长任务期间 UI 心跳不中断）、`T-7.1-02`（取消后资源真释放）。

## 8. 安全

- 凭据：只经 Windows 凭据管理器；日志与 IPC 返回**永不**含口令；删除连接先清凭据。
- 路径：工作区外一律拒（绝对路径、`..`、符号链接逃逸）；Agent 写盘与用户编辑共用同一份校验。
- 进程：PTY / 备份子进程用参数数组启动，不经 shell 拼接；禁止把用户输入拼进命令行。
- 网络出口：只有 Agent 端点（受配置门约束）与数据库连接；无其他外部域名（CSP 白名单为零）。
- 日志脱敏：连接串、口令、令牌、文件正文一律不进日志。
- 判据：`T-8.1-01`（日志扫描无凭据）、`T-8.2-01`（子进程无 shell 注入面）。

## 9. 测试与判据

| 面 | 规模（2026-11-05 实读） | 命令 |
|---|---|---|
| Rust 单测 | **801** 个 `#[test]`（`agent_generate` 44 · `retro_library` 36 · `tree` 30 · `fs` 28 · `config` 27 · `agent_nl2sql` 27 · `retro_package` 25 · `workspace` 21 …） | `cargo test`（`App/src-tauri` + `Db`） |
| 前端测试 | **87** 个 `*.test.ts`（含 20+ 个 `DatabaseView.*` mount 用例） | `npm test` |
| 层边界 | `Tools/check-core-boundary.ps1` | PowerShell 脚本 |
| 命令对账 | `T-2.2-01`（`generate_handler!` ↔ §2.2 族表） | 静态检索 |

### 9.2 本轮新增契约的用例

| 用例 ID | 对应契约 | Given | When | Then |
|---|---|---|---|---|
| `T-3.1-03` | §3.1 后置 | 保存一条连接 | 读 `connections.json` | 文件里无口令，只有引用；重启后可连 |
| `T-3.2-03` | §3.2 后置 | 10 万行结果 | 打开网格 | 按窗口取数，内存不随行数线性上涨 |
| `T-3.5-02` | §3.5 错误表 | 同一行被两处同时编辑 | 后提交者保存 | 报 `DATA_WRITE_CONFLICT`，不覆盖先提交者 |
| `T-3.7-02` | §3.7 错误表 | 导出大表途中取消 | 查产物 | 报 `IO_PARTIAL`，留下半份且不标成功 |
| `T-3.8-03` | §3.8 错误表 | 未确认就执行恢复 | 调 `restore_run` | 被拒，目标库未变 |
| `T-3.9-03` | §3.9 后置 | 终端输出 10 MB | 读输出 | 按窗口返回并标 `truncated` |
| `T-3.10-01` | §3.10 错误表 | 文件被外部改过 | 在编辑器保存 | 报 `FILE_STALE`，不覆盖 |
| `T-5.3-01` | §5.3 | 前端 ipc 调用集合 | 与命令清单比对 | 差集为空 |
| `T-8.1-01` | §8 | 全量日志 | 扫描凭据模式 | 命中 0 |

- 负例：以上每条都必须有一条「故意违规就变红」的样本（例如把口令写进 JSON 时 `T-3.1-03` 必须红）。

## 10. 未实现位点（代码现状，不是文档缺口）

| 位点 | 现状 | 影响 |
|---|---|---|
| Agent 命令执行 / 代码执行 / 工具目录 / 编排 / 压缩 / 注册表 / 钩子 / 记忆 / 联网工具 | 同源 Rust 面**没有**（`is_known_chat_tool` 只认 `read_file` / `write_file`） | 对话里不出现这些工具；与 macOS 的差距在同源面 |
| DAP 调试 | `Platform/windows` 内检索 DAP 命中 0 | 不提供调试会话 |
| 计划行数预估 | 无 `Plan Rows` 解析 | 审批卡显示「未接」，不显示 0 |
| IM 通道 | 只在 macOS 侧实现 | 不出现通道设置 |
| 笔记 / 复盘业务判据 | 在 `notes` / `retro` 仓的测试里 | 本端只承接宿主装配（§3.13） |

## 11. 偏离处理

| 信号 | 触发 | 动作 |
|---|---|---|
| `DETAIL_GAP` | 本节未覆盖的公开行为 | 取最小假设继续，并登记到本节表 |
| `DETAIL_CONFLICT` | 与代码现状冲突 | 停工，报人类主人 |
| `CONTRACT_DEVIATION` | 偏离 §3 契约 | 等确认 |
| `PLATFORM_CHANGE` | 需要换基线（Tauri 2 / WebView2 / Rust editions） | 停工 |
| `DESIGN_CONFLICT` | 与概设冲突 | 以概设「禁止」为准，不自行裁决 |

## 12. 已知坑

1. `Tools/check-exclusive-sections.ps1` 要求对侧独占节不改 —— 改契约前先确认本节归属。
2. `App/` 含 132 MB 构建产物与 `target/`（834 MB）；判据与提交都要避开，禁止把它们纳入统计。
3. 前端 `ipc.ts` 是唯一 IPC 出口；新增命令必须同时登记命令目录，否则命令面板搜不到。
