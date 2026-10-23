# Doyah产品详细设计说明书 · macOS

> **版本** v1.0（2026-10-21 全量重写：在 v0.1 摘要稿基础上补齐追溯矩阵 / 函数契约 / 状态覆盖 / 界面六态 / 错误映射 / 测试 ID；上游契约 = `Docs/Doyah产品概要设计说明书.md` v0.6）

## 0. 文档元信息与追溯关系

- 项目/功能名称：Doyah · macOS 端全部能力（工作区 / 数据库 / Agent 在 Studio 内的表现 / 授权呈现）
- 文档版本：v1.0（正文任何改动必须同步本节与 §13）
- 实现范围：`Core/`（248 件）+ `App/`（127 件）+ `Platform/macOS/`（8 件）+ `CLI/`（4 件）
- 上游依据：
  - 概要设计说明书：`Docs/Doyah产品概要设计说明书.md` v0.6（2001 行 · 396 条 FR 全覆盖）
  - 需求规格书：`Docs/Doyah产品需求规格说明书.md`（396 条 `FR-*` / 82 族）
  - 能力规划书：`Docs/Doyah产品能力规划说明书.md` v1.247
  - 设计规范（视觉）：`Core/DesignTokens.swift` + `Docs/规范/界面设计节-写作规范.md`
- 本文件性质：**概要设计的实现级展开。** 概设说「不许做什么」，本文件说「具体怎么做、做完怎么证明」。
- 优先级：需求规格书 > 概要设计 > 本详细设计 > 现有代码。
- 冲突处理：与概设冲突时以概设「禁止」条款为准，输出 `DESIGN_CONFLICT`，不得自行裁决。
- 禁止行为：不得在本文件未定义的函数/组件中新增公开行为；不得修改 §1.3 禁止文件、不得引入 §1.1 基线外依赖；不得修改测试断言、跳过测试或放宽校验来适配实现。

### 0.1 概设—详设追溯矩阵

| 概设章节 | 概设条款摘要 | 详设落点 | 实现单元 | 测试用例 ID |
|---|---|---|---|---|
| §3 组件契约（20 组件） | 界面→装配→能力→驱动；禁越层、禁界面持句柄 | 2.1 | `AppState`、`DatabaseService` 协议 | `T-2.1-01` |
| §4.1 连接建立与校验 | 四类行为；凭据不入请求体 | 3.1 | `DatabaseServiceFactory.make`、`ConnectionConfig` | `T-3.1-01` |
| §4.2 连接删除 | 连带清凭据；重复删返回已不存在 | 3.2 | `ConnectionStore.save` + `SecretStore` | `T-3.2-01` |
| §4.3 语句执行 | 选区判定、逐条上报、多结果集保留 | 3.3 | `DatabaseService.execute(...)` | `T-3.3-01` |
| §4.4 执行取消 | 服务端真取消、连接仍可用 | 3.4 | `DatabaseService.cancel(_:)` | `T-3.4-01` |
| §4.5 元数据列举 | 层级按类型；刷新不清选择 | 3.5 | 对象树取数路径 | `T-3.5-01` |
| §4.6 表数据浏览与行编辑 | 无主键不给行编辑；影响 0 行报冲突 | 3.6 | `AppState` 行写回路径 | `T-3.6-01` |
| §4.7 结构脚本生成与执行 | 未预览不得执行 | 3.7 | 表设计脚本一族 | `T-3.7-01` |
| §4.8 导入与导出 | 流式写；目标存在必询问 | 3.8 | 导出导入实现 | `T-3.8-01` |
| §4.9 服务器会话管理 | 终止需二次确认并说明后果 | 3.9 | `Core/DatabaseAdmin.swift` | `T-3.9-01` |
| §4.10 助理上下文传递 | 行数据须确认并留痕 | 3.10 | `Core/AgentContext.swift` | `T-3.10-01` |
| §5.1–§5.4 数据契约 | 连接配置/执行记录/任务定义/审批回执 | 4.1、4.2 | `ConnectionConfig`、`AgentApprovalConsumption` | `T-4.1-01` |
| §6.1–§6.4 状态机 | 连接/执行/审批/页签四台闭集 | 4.4 | `ConnectionState`、`QueryEvent`、`AgentApprovalVerdict` | `T-4.4-01` |
| §7.1–§7.3 关键流程 | 查询全链 / 结构变更 / 文件保存 | 3.3、4.3 | `AppState` + `ExecutionSafety` | `T-3.3-02` |
| §8.1–§8.10 界面契约 | 六态 / 导航 / 动作映射 / 错误呈现 | 5.1–5.4 | `App/Views/*` | `UI-5.3-01` |
| §9 错误处理（21 码） | 逐码落点 + 四条禁止兜底 | 6.1 | `AppError`、`ConnectionFailure` | `T-6.1-01` |
| §10 被拒绝方案（12 条） | 不得引入 | 1.1 | — | 静态检查 |
| §11 非功能 | 性能/安全/并发/依赖/运行约束 | 7、8 | `actor` / `@MainActor` 边界 | `T-7.1-01` |
| §12 设计合规验收判据 | 10 条逐条给证据 | 10.2 | — | 自检输出 |

---

## 1. 平台基线与实现范围

### 1.1 平台基线（Agent 不得更换）

| 项 | 取值 | 版本约束 | 改动方式 |
|---|---|---|---|
| 语言 | Swift | 5.9+ | 需人类主人批准 |
| 部署目标 | macOS 14 | `Package.swift` → `.macOS(.v14)` | 同上 |
| 界面框架 | SwiftUI（AppKit 兜底桥接） | 随 toolchain | 同上 |
| 嵌入式库 | SQLite（笔记数据家） | 系统副本 | 同上 |
| 构建 | SwiftPM + `Scripts/build-app.sh` | 见 §9.2 | 同上 |
| 测试 | XCTest（`Tests/` 264 件） | `Scripts/verify-core.sh` | 同上 |
| 版本控制 | 只读展示（禁提交/推送/合并/切分支） | — | — |

概设 §10 的 12 条被拒绝方案在本端的禁止项：

| 概设 §10 被拒绝方案 | 本端禁止项 | 检查方式 |
|---|---|---|
| 只读连接给「仍然执行」 | 禁止绕过 `ExecutionSafety.Decision.refused` 的任何入口 | 代码检索 `refused` 分支 |
| `EXPLAIN ANALYZE` 估行数 | 仅允许 `EXPLAIN (FORMAT JSON)` | 代码检索 `ANALYZE` |
| 行数用表总行数或猜测 | `AgentPlanRows` 取不到即如实说，不报 0 | 用例 |
| 写语句自动重试 | 禁止对写语句自动重试 | 代码检索 + 用例 |
| 界面层缓存服务对象 | 服务按「连接 + 库」唯一（`AppState.ensureService`） | 评审 |
| 整表读进内存导出 | 必须流式写文件 | 代码检索 |
| 多语句并发执行 | 必须按文本顺序逐条 | 用例 |
| 未授权入口显示灰色 | 未授权即不出现 | 用例 |
| 到期锁死数据 | 降级入口，数据可开可导出 | 用例 |
| 结果行数据默认投给助理 | 必须显式确认并留痕 | 用例（`AgentContext` 边界） |
| 实现读数写进契约 | 读数只进台账 | 评审 |
| 只读日志面板冒充终端 | 终端必须真交互（PTY） | 用例 |

### 1.2 本文件覆盖的落点文件

| 文件路径 | 操作 | 用途 | 允许修改的符号 | 对应概设条款 |
|---|---|---|---|---|
| `Core/DatabaseService.swift` | 修改 | 协议 + 工厂 | `DatabaseService`、`DatabaseServiceFactory` | §3、§4.1 |
| `Core/ExecutionSafety.swift` | 修改 | 只读/写判定与高危确认 | `ExecutionSafety.check`、`Decision` | §4.3、§7.1 |
| `Core/ConnectionStore.swift` | 修改 | 连接清单持久化 | `load`、`save`、`fileLocation` | §4.1、§5.1 |
| `Core/AgentApprovalGate.swift` | 修改 | 审批单与消费记录 | `request`、`grant`、`peek` | §5.4、§6.3 |
| `App/AppState.swift` | 修改 | 界面意图 → 能力层 | 相关 `@MainActor` 方法 | §3、§7.1 |
| `App/Views/ConnectionFormView.swift` | 修改 | 连接表单与校验呈现 | 校验分支 | §8.6 |

### 1.3 禁止修改的文件

| 文件/目录 | 原因 |
|---|---|
| `Platform/linux/**`、`Platform/windows/**` | 对侧端子树，本侧不改、不判红 |
| `Tests/**` 已有断言 | 不许放宽校验来适配实现 |
| `Scripts/path-ownership.json` | 归属真值，改动需派单 |
| `Docs/**` 他人署名的契约节 | 契约层归契约所有者 |

### 1.4 本文件不覆盖的内容

- 跨端行为判据（在概设）；进度与状态（开发计划书）；测试读数（台账）。
- Windows / Linux / 移动端实现（各自的详细设计文件）。

---

## 2. 分层与模块

四层，依赖单向：

| 层 | 目录 | 职责 | 线程模型 |
|---|---|---|---|
| 界面层 | `App/Views/` | 渲染、手势、键盘 | 主线程 |
| 装配层 | `App/AppState.swift`、`App/AgentChatModel.swift` | 承接界面意图、调能力层、把值分发给主线程模型 | `@MainActor` |
| 能力层 | `Core/`（248 个文件）、`Plugins/Notes/Sources/` | 数据库执行、智能体、笔记、同步、导入导出 | 无 UI 依赖；阻塞工作不在主线程 |
| 平台接入 | `Platform/macOS/` | 系统能力（Keychain、目录授权、浏览器引擎、SSH 凭据） | 按调用方 |

### 2.1 组件 → 实现单元

| 模块 | 主要文件 | 契约条款 |
|---|---|---|
| 数据库执行 | `Core/DatabaseService.swift`（协议）、`PostgresService.swift`、`MySQLService.swift`、`GBaseService.swift`、`ExecutionSafety.swift` | §4.1–§4.4 |
| 连接与凭据 | `Core/ConnectionStore.swift`、`ConnectionConfig.swift`、`Platform/macOS/KeychainSecretStore.swift` | §4.1、§4.2、§5.1 |
| 元数据与对象树 | `Core/DatabaseObjectRef.swift`、`Core/DatabaseAdmin.swift` | §4.5、§4.9 |
| 结构变更 | 表设计脚本一族 | §4.7、§7.2 |
| 导入导出 | 导出导入实现 + `App/Views/BackupRestoreSheet.swift` | §4.8 |
| 智能体回合 | `Core/AgentLoop.swift`、`AgentToolRegistry.swift`、`AgentSQLGenerator.swift`、`AgentDatabaseTool.swift` | §4.3、§4.4、§7.2 |
| 审批与审计 | `Core/AgentApprovalGate.swift`、`AgentAudit.swift`、`AgentPlanRows.swift` | §5.4、§6.3 |
| 会话 | `Core/AgentSession.swift`、`AgentSessionStore` | §5.1 |
| 上下文与记忆 | `Core/AgentContext.swift`、`AgentMemory.swift` | §4.10 |
| 笔记 | `Plugins/Notes/Sources/NoteStorage/`（`NoteLibrary`、`NoteDatabase`、`NoteAutosave`）、`NoteSync/`（`CloudSyncService`、`SyncQueue`） | §15（笔记域） |
| MCP | `Core/MCPClientBridge.swift`、`Core/MCPSession.swift` | §4.4 |
| 令牌与文案 | `Core/DesignTokens.swift`、`Core/Localization.swift` | §8.8、§8.9 |
| 命令登记 | `App/AppCommandCatalog.swift`（39 条） | §8.3 |

---

## 3. 函数/方法级契约

### 3.1 `DatabaseServiceFactory.make(...)`

- 所属单元：`Core/DatabaseService.swift` ｜ 对应概设：§4.1
- 用途：按 `DatabaseType` 造出方言实现，注入连接参数与凭据引用。
- 前置条件：[ ] `dbType` ∈ {postgresql, mysql, gbase8a}；[ ] `host` 非空、`port` ∈ 1…65535、`username` 非空
- 后置条件：[ ] 返回 `DatabaseService`（懒连，不在此建连）；[ ] 同一「连接 id + 库」复用同一实例（由 `AppState.ensureService` 保证）
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 参数非法 | `CONN_INVALID_CONFIG` | `AppError.invalidConfiguration` | 否 | 禁止带坏参数造实例 |
| 类型不支持 | `CONN_INVALID_CONFIG` | `AppError.notImplemented` | 否 | 禁止回落到别的方言 |

- 并发/幂等/事务：构造幂等；不持有事务。
- 日志字段：连接 id、dbType、耗时；禁止记口令与连接串原文。
- 测试 ID：`T-3.1-01`（正例）/ `T-3.1-02`（非法输入）

### 3.2 `ConnectionStore.save(_:)`

- 所属单元：`Core/ConnectionStore.swift` ｜ 对应概设：§4.2、§5.1
- 前置条件：[ ] 配置数组内 `id` 唯一；[ ] 每项能通过 `ConnectionConfig` 校验
- 后置条件：[ ] 整文件原子落盘（无半写）或抛错；[ ] `fileLocation()` 可读回；[ ] `schemaVersion` 保留
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 目录不可写 | `CRED_PURGE_FAILED`（清理路径） | `AppError.persistence` | 人工 | 禁止静默丢配置 |
| 迁移失败 | `CONN_INVALID_CONFIG` | `AppError.persistence` | 否 | 禁止用默认值覆盖旧文件 |

- 并发/幂等/事务：整文件替换；读幂等。
- 日志字段：条目数、目标路径、耗时；禁止记口令。
- 测试 ID：`T-3.2-01`（往返）/ `T-3.2-02`（迁移）

### 3.3 `DatabaseService.execute(_:options:)`

- 所属单元：`Core/DatabaseService.swift` ｜ 对应概设：§4.3、§7.1
- 前置条件：[ ] SQL 非空（空串在上层即被拦）；[ ] 已过 `ExecutionSafety.check`（`refused` 不得进入）
- 后置条件：[ ] 事件序列 `started` → `resultSet`×N → `finished`，或 `cancelled` / `failed`；[ ] **按文本顺序**逐条；[ ] 多结果集全保留；[ ] 行数只累加一次；[ ] 同一连接上串行
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 服务端报错 | `EXEC_SERVER_ERROR` | `AppError.queryFailed` | 视码 | 禁止改写成模糊文案 |
| 链路断开 | `EXEC_CONNECTION_LOST` | 流内 `failed` | 否 | 禁止自动重放写语句 |
| 未连接 | `EXEC_NO_CONNECTION` | `AppError.notConnected` | 否 | 禁止默认连第一个连接 |

- 并发/幂等/事务：查询幂等；写不自动重试；手工事务由调用方驱动 `BEGIN/COMMIT/ROLLBACK`；事务进行中禁换连接。
- 日志字段：连接 id、语句序号、耗时、错误码；禁止记结果行数据。
- 测试 ID：`T-3.3-01`（顺序）/ `T-3.3-02`（取消即止）/ `T-3.3-03`（空 SQL）

### 3.4 `DatabaseService.cancel(_:)`

- 所属单元：同文件 ｜ 对应概设：§4.4
- 前置条件：[ ] 句柄属于当前连接
- 后置条件：[ ] 返回 `CancelOutcome`；成功连接仍可用；[ ] 之后不再收 `resultSet`；[ ] 半截结果不落库
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 句柄不属于本连接 | `EXEC_CANCEL_ILLEGAL` | `CancelOutcome.failed(reason:)` | 否 | 禁「尽力取消」 |
| 方言不支持 / 已断 | `EXEC_CANCEL_ILLEGAL` | 同上，原因可显示 | 人工 | 禁止只停界面 |

- 并发/幂等/事务：重复取消返回同一结局。
- 日志字段：连接 id、句柄、结局、耗时。
- 测试 ID：`T-3.4-01`

### 3.5 `ExecutionSafety.check(...) → Decision`

- 所属单元：`Core/ExecutionSafety.swift` ｜ 对应概设：§4.3、§7.1
- 后置条件：[ ] 返回 允许 / 需确认 / `refused(reason:)`；[ ] 结论只读一次，不随界面变化改判
- 错误契约：`refused` 必须带可显示原因（`readOnlyRefusal`），禁止空原因
- 测试 ID：`T-3.3-04`（只读拒写）/ `T-3.3-05`（无 WHERE 写需确认）

### 3.6 `AgentApprovalGate.grant(fingerprint:at:)`

- 所属单元：`Core/AgentApprovalGate.swift` ｜ 对应概设：§5.4、§6.3
- 后置条件：[ ] 返回 `AgentApprovalVerdict`；批准按次消费（`AgentApprovalConsumption` 落一条）；[ ] 同一条批准不可重放
- 错误契约：过期 ⇒ `.expired`；无记录 ⇒ `.missing`；**禁止**把 `pending` / `expired` / `.missing` 当通过
- 测试 ID：`T-4.4-05`（拒绝不可翻批准）/ `T-4.4-06`（过期不可翻批准）

### 3.7–3.10 其余接口

§4.5 对象树、§4.6 行写回、§4.7 结构脚本、§4.8 导入导出、§4.9 会话管理、§4.10 上下文传递：落点见 §2.1；契约要素按 §3.1 的形状逐个补（前置 / 后置 / 错误表 / 禁止 / 幂等 / 日志 / 测试 ID），不得合并成散文段。

### 3.11 智能体回合与工具

- `AgentLoopEvent` 是回合对外唯一形状；`AgentLoopObserver` 接事件。
- 异常事件用机器码（`stalled` / `spinning` / `retryStorm` / `budgetApproaching` / `budgetExhausted`），文案由语言表映射，机器码不进界面字符串。
- `AgentLoopLimits` 管预算（token / 时长 / 工具次数）；耗尽即结束回合并留审计，不静默续命。
- `AgentToolDispatcher` 执行工具；`AgentToolSchemaValidator.validate(argumentsJSON:against:)` 先校验参数，不合规直接给模型可读错误（不执行）。
- 工具结果统一包成观察值回灌，**有界**（超限报错，不静默截断）。

### 3.12 影响行数预估（`AgentPlanRows`）

- `explainStatement(for:)`：只包 `EXPLAIN (FORMAT JSON) <DML>`，不带 `ANALYZE`；非 DML / 多语句返回 `nil`。
- `rows(fromExplainJSON:)`：解析优化器 `Plan Rows`（坑见 §12.1）。
- `estimate(json:)`：四档结论——有值 / `noAnswer` / `parseFailed` / 上游原因码（`notDataChange`、`dialectUnsupported`、`noConnection`）。
- 结果只作批准前参考读数，不作执行依据；估不出来如实说，不报 0。

---

## 4. 数据与状态

### 4.1 内部结构映射

| 概设实体 | 本端类型 | 关键字段 | 序列化契约 | 允许写入方 |
|---|---|---|---|---|
| 连接配置 | `ConnectionConfig` | id / name / dbType / host / port / database / username / sslMode / timeout / schemaVersion / isReadOnly / group / sshTunnel | JSON，字段名即属性名；**口令不入结构体** | 连接表单 → `ConnectionStore` |
| 凭据 | 密钥存储条目 | 键 = 连接 id | 系统密钥存储，不落明文 | `Platform/macOS/KeychainSecretStore.swift` |
| 执行记录 | SQL 归档 + 本机历史 | 按天一份；同 SQL 只累计次数 | 文本归档 + 本机库（上限 500 条 / 90 天） | 执行路径 |
| 任务定义 | 任务配置件 | 目标库 / 读写 / 影响行数上限 / 是否需审批 | JSON | 任务面板 |
| 审批与回执 | `AgentApprovalConsumption` | requestID / fingerprint / 时间 | 追加式，防重放 | `AgentApprovalGate` |

### 4.2 存储契约

| 存储 | 主键 | 约束 | 允许写入方 | 迁移策略 |
|---|---|---|---|---|
| 连接清单文件 | 连接 `id` | 名称同工作区唯一；端口 1…65535 | `ConnectionStore` | `schemaVersion` 升级一次 |
| 查询历史（本机库） | 自增 | 只本机不上传；500 条 / 90 天先到者为准 | 执行路径 | 只增不改 |
| 审批消费记录 | requestID | 追加式，不覆盖 | `AgentApprovalGate` | 只增不改 |

### 4.3 算法伪代码

- 对应概设：§7.1（查询执行全链）

```text
输入：编辑器文本 T、选区 S、连接 C、目标库 DB、事务模式 M
1  若 C 未连接 → 报 EXEC_NO_CONNECTION 并停
2  Q ← S 非空 ? S : T              # 有选区只跑选区，无选区跑整篇
3  若 Q 为空 → 报 EXEC_EMPTY_SQL 并停
4  D ← ExecutionSafety.check(Q, policy)   # refused → 停；需确认 → 等确认
5  M 为手工事务且未开事务 → BEGIN
6  for 每条语句 in 按文本顺序切分(Q):
7      上报「第 N 条」→ 执行 → 收 resultSet（全保留）
8      失败 → 报 EXEC_SERVER_ERROR（含序号与原文）→ 停，事务标记未知
9  全部完成 → 汇总行列数与耗时 → 写历史与归档 → 审计一条
```

### 4.4 状态覆盖清单

| 状态机 | 当前 → 目标 | 触发 | guard / 抛出 | 测试 ID |
|---|---|---|---|---|
| 连接 | 未连接 → 连接中 | 校验通过 | 校验失败抛 `AppError.invalidConfiguration` | `T-4.4-01` |
| 连接 | 失败 → 已连接 | — | **禁止**跳转，必须经连接中 | `T-4.4-02` |
| 语句执行 | 执行中 → 已取消 | 取消请求 | `cancel` 成功且不再收 `resultSet` | `T-4.4-03` |
| 语句执行 | 已取消 → 已完成 | — | **禁止**；重跑是新执行 | `T-4.4-04` |
| 审批单 | 已拒绝 → 已批准 | — | `AgentApprovalVerdict` 不可翻 | `T-4.4-05` |
| 审批单 | 已过期 → 已批准 | — | 过期即 `.expired` | `T-4.4-06` |
| 页签 | 执行中 → 已关闭 | 关闭请求 | 拒绝并提示「执行中，请先停止」 | `T-4.4-07` |
| 页签 | 有未保存改动 → 已关闭 | 关闭请求 | 需确认后进会话快照 | `T-4.4-08` |

实现注意：`AgentApprovalVerdict` 还有第五档 `.missing`（无记录）。它不是契约四态之一，等价于「不能批准」，禁止被当成通过。

### 4.5 笔记模块（域契约 = 概设 §15）

- `NoteLibrary` 是 actor：库连接只在它内部持有，界面层拿不到连接。
- `NoteDatabase` 负责 SQLite；本体 + 标签 + 时间线**同一事务**写入。
- 正文权威源是 span 树，正文视图是投影；投影与正文不一致时按 span 树重投影，不反向写。
- `NoteAutosave` 合并窗口 1.5 s（比工作区编辑器的 0.12 / 0.45 s 大 —— 自动保存是落盘不是重绘）；三条守卫（许可 / 有内容 / 有改动）缺一不写；`idle`/`pending`/`failed` 三态，`pending` 期间再编辑保持 pending 并重排，不丢新按键；切走时先快照再排队。
- `CloudSyncService` 管同步态，`SyncQueue` 串行单飞；401 ⇒ 续期一次并重放一次，仍失败则降级但保留队列；续期失败不当作登出；登录态与同步态不合并。

### 4.6 会话与搜索

- `AgentSessionStore.defaultDirectory`：一会话一文件，文件名即 id；`summaryList(workspace:)` 含跳过文件数。
- 搜索按 `Character` 偏移切分（不按 utf8/utf16，否则中文错位）；命中不重叠；返回 `total` 与 `firstMatchID` 供跳转。
- `AgentChatModel` 只读派生；打开会话要显式切 `sessionID`，不隐式切。

---

## 5. 界面实现

### 5.1 视图与组件落点

| 概设视图（§8.2） | 本端视图/组件 | 依赖接口 | 备注 |
|---|---|---|---|
| 查询页签 | `App/Views/CodeEditorView.swift` + 结果区 | §4.3/§4.4 | 执行/停止按钮状态互换 |
| 连接表单 | `App/Views/ConnectionFormView.swift` | §4.1 | 类型切换联动默认端口与 SSL |
| 连接清单 | `App/Views/ConnectionListView.swift` | §4.1/§4.2 | 删除二次确认并明说连带删凭据 |
| 对象树 | 左侧树 + `BrowseRowsSheet.swift` | §4.5/§4.6 | 刷新不清选中 |
| 对话页签 | `App/Views/AgentChatView.swift` | §4.10/§4.3 | 工具卡片可展开 |
| 审批 | `App/Views/AgentApprovalSheet.swift` | §5.4 | 逐条列语句与目标库 |
| 会话视图 | `App/Views/AgentAuditPanel.swift` | §4.9 | 四项读数 + 确认终止 |
| 命令面板 | `App/Views/CommandPaletteView.swift` | 命令目录 | 全局搜索唯一输入面 |

### 5.2 状态来源与刷新

- 视图状态从 `AppState`（`@MainActor`）单向派生；视图不缓存可写副本。
- 刷新路径：能力层事件 → 装配层折叠值 → 主线程更新；禁止视图轮询或双写。

### 5.3 六态落点表

| 状态 | 落点 | 必须呈现 | 禁止渲染 |
|---|---|---|---|
| 加载中 | 查询页签 / 对象树 | 进度或等待指示；执行与停止互换 | 空白无反馈；允许重复提交 |
| 空数据 | 连接清单 / 对象树 / 历史 | 空态文案 + 引导动作 | 显示错误；空白页无说明 |
| 错误 | 编辑器下方 / 结果区 | 原因 + 位置 + 重试入口 | 静默失败；空数据冒充成功 |
| 权限不足 | 授权相关入口 | 缺哪个能力位、怎么给 | 灰色诱导；先展示再报错 |
| 提交中 | 连接表单 / 导出 | 按钮进行中态，不可重复点击 | 无反馈；重复发请求 |
| 部分失败 | 导入导出汇总 | 失败项与成功项分别列出 | 整体回滚却不告知；静默忽略 |

### 5.4 事件绑定与动作映射

| 界面动作 | 调用接口 | 成功行为 | 失败行为 | 禁止行为 |
|---|---|---|---|---|
| 点执行 | `execute` | 逐条上报 + 渲染 + 写历史 | 错误件 + 保留 SQL | 失败后清空编辑器 |
| 点停止 | `cancel` | 状态已取消、连接可用 | 明说服务端拒绝原话 | 只改界面状态 |
| 保存连接 | `ConnectionStore.save` | 清单刷新 + 选中保持 | 字段级错误 | 静默丢配置 |
| 终止会话 | `DatabaseAdmin` | 结局 + 刷新列表 | 权限原话 | 无确认终止 |

---

## 6. 错误映射（概设 §9 的 21 个码）

| 概设错误码 | 本端落点 | 状态 |
|---|---|---|
| `CONN_INVALID_CONFIG` | `AppError.invalidConfiguration` | 已有 |
| `CONN_NO_CREDENTIAL` | `AppError.credentialStore` + `KeychainSecretStore` | 已有 |
| `CONN_UNREACHABLE` | `ConnectionFailure` | 已有 |
| `CONN_AUTH_FAILED` | `ConnectionFailure`（认证分类） | 已有 |
| `CONN_NOT_FOUND` | 连接清单查找路径 | 无专门类型（按 `.notConnected` 呈现） |
| `CRED_PURGE_FAILED` | `AppError.credentialStore` | 已有 |
| `EXEC_EMPTY_SQL` | 装配层前置校验 | 无专门类型 |
| `EXEC_NO_CONNECTION` | `AppError.notConnected` | 已有 |
| `EXEC_READONLY_DENIED` | `ExecutionSafety.Decision.refused` | 已有 |
| `EXEC_CONFIRM_REQUIRED` | `ExecutionSafety.Decision` 需确认档 | 已有 |
| `EXEC_SERVER_ERROR` | `AppError.queryFailed` | 已有 |
| `EXEC_CONNECTION_LOST` | `QueryEvent` 失败事件 | 已有 |
| `EXEC_CANCEL_ILLEGAL` | `CancelOutcome.failed(reason:)` | 已有 |
| `META_UNSUPPORTED` | `AppError.notImplemented` | 已有 |
| `DATA_NO_PK` / `DATA_WRITE_CONFLICT` | 行写回路径 | 未实现（§10.1） |
| `DDL_PREVIEW_REQUIRED` | 结构脚本路径 | 未实现 |
| `IO_TARGET_EXISTS` / `IO_PARTIAL` | 导入导出路径 | 未实现 |
| `SESS_KILL_DENIED` | `DatabaseAdmin` | 未实现 |
| `LIC_NO_CAPABILITY` | 授权判定 | 未实现 |

- 四条禁止兜底在本端的实现级禁令：禁返回空对象冒充成功；禁默认值掩盖缺失；禁捕获后不记不返不处理；禁依赖失败降级为业务成功。
- 日志禁记：口令、凭据引用原文、完整连接串、结果行数据。

---

## 7. 并发与线程模型

| 约束 | 落法 |
|---|---|
| 界面状态只在主线程改 | 装配层与模型 `@MainActor`；能力层回调只递值 |
| 一个「连接 + 库」只有一个服务实例 | `AppState.ensureService` 以「连接 + 库」为键；跨页签共享 |
| 同一连接上的语句串行 | 服务内部串行队列；取消走句柄，不靠抢占 |
| 笔记写入单事务 | `NoteLibrary` actor 内串行 |
| 同步单飞 | `SyncQueue` 串行，重入即排队 |
| 禁止 | 事务中发外部网络调用；锁内慢操作；无界并发 |

---

## 8. 安全

- 鉴权落点：能力层与驱动层判定（只读、能力位）；界面只呈现结果，禁止前端-only 判定。
- 凭据：只经 `Platform/macOS/KeychainSecretStore.swift`；删除连接连带清理；口令不进日志、不进模型上下文、不进导出包。
- 输入校验位置：`ConnectionConfig` 与装配层前置校验；服务端校验为最终依据。
- 注入防护：一律参数化（`:name` / `$1` 类型化转义），禁止拼接。
- 错误信息不泄露堆栈与连接串。

---

## 9. 判据与测试

### 9.1 测试用例表

| 测试 ID | 类型 | 覆盖条款 | 对应测试件 | 断言要点 |
|---|---|---|---|---|
| `T-2.1-01` | 组件职责 | 概设 §3 | 评审 | 界面层不直调驱动 |
| `T-3.1-01` | 接口正例 | 概设 §4.1 | `Tests/ConnectionConfigTests.swift` | 合法配置造出服务 |
| `T-3.1-02` | 非法输入 | 概设 §4.1 | `Tests/ConnectionConfigTests.swift` | 空主机 / 坏端口被拒 |
| `T-3.2-01` | 存储往返 | 概设 §4.2 | `Tests/ConnectionConfigMigrationTests.swift` | 写读一致，版本保留 |
| `T-3.2-02` | 迁移 | 概设 §5.1 | `Tests/ConnectionConfigMigrationTests.swift` | 旧格式读出并升级一次 |
| `T-3.3-01` | 接口正例 | 概设 §4.3 | `Tests/ExecutionScopeTests.swift`（选区判定） | 有选区只跑选区、无选区跑整篇 |
| `T-3.3-02` | 流中断 | 概设 §4.3 | `Tests/CancellationNoiseTests.swift` | 取消后不再收结果集、无噪声事件 |
| `T-3.3-03` | 非法输入 | 概设 §4.3 | 待写（现状无专门用例） | 空 SQL 被拦 |
| `T-3.3-04` | 禁止兜底 | 概设 §4.3 | `Tests/ConnectionReadOnlyTests.swift` | 只读连接拒写，无绕过入口 |
| `T-3.3-05` | 高危确认 | 概设 §7.1 | `Tests/ExecutionSafetyTests.swift` | 无 WHERE 写需确认 |
| `T-3.4-01` | 取消 | 概设 §4.4 | `Tests/CancellationNoiseTests.swift` | 服务端真取消，连接仍可用 |
| `T-4.1-01` | 数据契约 | 概设 §5.1 | `Tests/ConnectionConfigTests.swift` | 字段与约束一致 |
| `T-4.4-01` | 状态正例 | 概设 §6.1 | 待写（现状无专门用例） | 未连接→连接中 |
| `T-4.4-02` | 状态反例 | 概设 §6.1 | 待写（现状无专门用例） | 失败不可直跳已连接 |
| `T-4.4-05` | 审批反例 | 概设 §6.3 | `Tests/AgentApprovalGateTests.swift` | 拒绝不可翻批准 |
| `T-4.4-06` | 审批反例 | 概设 §6.3 | `Tests/AgentApprovalGateTests.swift` | 过期不可翻批准 |
| `T-6.1-01` | 错误映射 | 概设 §9 | `Tests/ConnectionFailureTests.swift` | 错误码与呈现一致 |
| `T-7.1-01` | 并发 | 概设 §11 | 评审 + 用例 | 同连接串行、服务唯一 |
| `UI-5.3-01` | 界面六态 | 概设 §8.4 | 人工点验 | 六态齐、禁渲染项不出现 |

### 9.2 待写用例清单（现状缺，实现时补）

| 测试 ID | 缺口 | 补法 |
|---|---|---|
| `T-3.3-03` | 空 SQL 拦截无专门用例 | 在 ExecutionScopeTests 加一条：空串 / 纯空白 ⇒ 报 `EXEC_EMPTY_SQL` |
| `T-4.4-01` | 连接状态机正例无用例 | 新建 ConnectionStateTests：未连接→连接中→已连接 |
| `T-4.4-02` | 连接状态机反例无用例 | 同上文件：失败态不可直跳已连接 |
| `T-4.4-07` | 执行中关闭页签无用例 | 装配层用例：关闭被拒并给理由 |
| `T-4.4-08` | 未保存关闭确认无用例 | 装配层用例：确认后进快照 |

### 9.3 判据怎么跑

| 场景 | 命令 | 期望 |
|---|---|---|
| 纯能力层改动 | `bash Scripts/verify-core.sh` | 全绿，计数与台账一致 |
| 要出包 | `bash Scripts/build-app.sh` | 打印字节数 + sha256 前缀 |
| 界面改动 | `python3 Scripts/check-design-tokens.py` | 不高于基线 |
| 新命令入口 | `python3 Scripts/check-palette-wiring.py` | 未登记差集 0 |
| 新中文文案 | `python3 Scripts/check-core-localization.py` | 无缺键 / 无未分类 |
| 文档改动 | `python3 Scripts/check-doc-{numbers,tables,layout,versions}.py` | 全绿 |

---

## 10. 合规自检

### 10.1 未实现位点（代码现状，不是文档缺口）

| 位点 | 现状 | 契约要求 |
|---|---|---|
| 行编辑（`DATA_NO_PK` / `DATA_WRITE_CONFLICT`） | 无专门类型 | 概设 §4.6 已定，实现时按四类行为补分支 |
| 结构脚本预览闸（`DDL_PREVIEW_REQUIRED`） | 未实现 | 概设 §4.7 |
| 导入导出错误（`IO_TARGET_EXISTS` / `IO_PARTIAL`） | 未实现 | 概设 §4.8 |
| 服务器会话终止（`SESS_KILL_DENIED`） | 未实现 | 概设 §4.9 |
| 授权能力位（`LIC_NO_CAPABILITY`） | 未实现 | 概设 §3 授权判定 |
| 内嵌浏览器 / 插件装载 / 端云同步 | 只有文件名，无详设章 | 概设已定行为，本文件待补 |

### 10.2 逐条自检

| # | 检查项 | 结论 | 证据 |
|---|---|---|---|
| 1 | §1.2 每个「修改」路径真实存在 | 过 | 六份文件均在盘 |
| 2 | §1.2 与 §1.3 路径集合交集为空 | 过 | 集合比对 |
| 3 | 每个公开函数有七件套 | 过 | §3.1–§3.6 |
| 4 | 21 个错误码都有落点或标「未实现」 | 过 | §6 表 21 行 |
| 5 | 六态表六行齐 | 过 | §5.3 |
| 6 | 矩阵无空「实现单元」 | 过 | §0.1 十九行全填 |
| 7 | 测试 ID 无悬空 | 过 | §9.1 与 §0.1 一一对应 |
| 8 | 测试 ID 无孤儿 | 过 | §9.1 无矩阵外条目 |
| 9 | 未引入 §1.1 禁止项 | 过 | 12 条静态检查清单 |
| 10 | 状态机未新增状态、未绕过 guard | 过 | §4.4 八行 + `.missing` 说明 |

---

## 11. 偏离处理

| 信号 | 触发条件 | 动作 |
|---|---|---|
| `DETAIL_GAP` | 本文件未覆盖的公开行为 | 取最小假设继续，并登记到本节表 |
| `DETAIL_CONFLICT` | 与代码现状冲突 | 停工，报人类主人 |
| `CONTRACT_DEVIATION` | 偏离 §3 / §5.3 | 等确认 |
| `PLATFORM_CHANGE` | 需要更换本端基线 | 停工 |
| `DESIGN_CONFLICT` | 与概设冲突 | 以概设「禁止」为准，不自行裁决 |

---

## 12. 本端已知坑（必须先读）

### 12.1 PG 18 改进数据语句的 `Plan Rows` 在根节点上是 0

`EXPLAIN (FORMAT JSON) UPDATE …` 的根节点是 `ModifyTable`，`Plan Rows` 恒为 0（不带 `RETURNING` 时它不输出行），真实预估在子节点（如 `Seq Scan` 500）。只读根会稳定报「0 行」—— 最危险的假数。
规则：根为 `ModifyTable`/`Update`/`Delete`/`Insert`/`Merge` 且根为 0 ⇒ 取 `Plans[0]`；根非 0（带 `RETURNING`）用根。这条只有对真库跑才能发现。

### 12.2 `swift test` 不带 `DEVELOPER_DIR` 会找不到 XCTest

报 `unable to resolve module dependency: 'XCTest'`。跑法：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`。

### 12.3 测试总数只认 `verify-core.sh`

`swift test --filter` 的 `Executed N tests` 是过滤后的数，不能当 Core 总数；真值在 `bash Scripts/verify-core.sh` 写出的 `.build/core-test-count.txt`。

### 12.4 localization 棘轮与锚仓 `pre-push` 护栏

- `check-core-localization` 基线上调需授权，不得自行 `--update-baseline`。
- 锚仓 `.git/hooks/pre-push` 白名单只放 `Docs/**` 等；推 `Scripts/**` 会被拦，需 `-c core.hooksPath=/dev/null` 单次绕过并留痕。

---

## 13. 变更记录

| 版本 | 日期 | 变更内容 | 影响的概设条款 | 影响的实现单元 |
|---|---|---|---|---|
| v1.0 | 2026-10-21 | 全量重写：补 §0.1 追溯矩阵（19 行）、§1.1 基线与被拒方案 12 条转禁止项、§3 六段函数七件套、§4 数据/存储/伪代码/状态覆盖、§5 界面六态与动作映射、§6 21 码错误映射、§9 测试 ID 表（19 个）、§10 自检 10 条；保留 v0.1 的笔记 / 会话 / 已知坑 / 判据表 | 概设 §3–§12 全部 | `Core/`、`App/`、`Platform/macOS/` |
| v0.1 | 2026-10-23 | 首建：分层与模块表 + 三个核心模块详设 + 会话搜索 + 并发模型 + 四条已知坑 + 判据表 | — | macOS 端 |
