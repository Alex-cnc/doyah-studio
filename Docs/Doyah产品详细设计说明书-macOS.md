# Doyah 产品详细设计说明书 · macOS

> **版本** v0.1（2026-10-23 首建；替代原「实现要点」草稿）

## 0. 元信息

- 读者：承担 macOS 端开发任务的 Agent 与人。
- 上游：需求规格书（`FR-*`）> 《概要设计说明书（执行契约）》> 本文件 > 现有代码。
- 本文件写**这一端怎么实现**：模块划分、类型与职责、时序、并发、错误映射、已知坑、判据怎么跑。
- 本文件不写：跨端行为判据（在契约里）、进度、测试读数（在台账）。
- 冲突：与契约冲突 ⇒ 以契约为准并输出 `BLOCKED`。

## 1. 分层与模块

四层，依赖单向：

| 层 | 目录 | 职责 | 线程模型 |
|---|---|---|---|
| 界面层 | `App/Views/` | 渲染、手势、键盘 | 主线程 |
| 装配层 | `App/AppState.swift`、`App/AgentChatModel.swift` | 承接界面意图、调能力层、把值分发给主线程模型 | `@MainActor` |
| 能力层 | `Core/`（248 个文件）、`Plugins/Notes/Sources/` | 数据库执行、智能体、笔记、同步、导入导出 | 无 UI 依赖；阻塞工作不在主线程 |
| 平台接入 | `Platform/macOS/` | 系统能力（剪贴板、打开文件、Keychain 等） | 按调用方 |

模块清单（本端）：

| 模块 | 主要文件 | 契约条款 |
|---|---|---|
| 数据库执行 | `Core/DatabaseService.swift`（协议）、`Core/PostgresService.swift`、`Core/MySQLService.swift`、`Core/GBaseService.swift`、`Core/ExecutionSafety.swift` | §4.1、§4.2、§7.1 |
| 智能体回合 | `Core/AgentLoop.swift`、`Core/AgentToolRegistry.swift`、`Core/AgentSQLGenerator.swift`、`Core/AgentDatabaseTool.swift` | §4.3、§4.4、§7.2 |
| 审批与审计 | `Core/AgentApprovalGate.swift`、`Core/AgentAudit.swift`、`Core/AgentPlanRows.swift` | §5.2、§6.3 |
| 会话 | `Core/AgentSession.swift` | §5.1 |
| 笔记 | `Plugins/Notes/Sources/NoteStorage/`（`NoteLibrary`、`NoteDatabase`、`NoteAutosave`）、`Plugins/Notes/Sources/NoteSync/`（`CloudSyncService`、`SyncQueue`） | §4.5、§6.2 |
| MCP | `Core/MCPClientBridge.swift`、`Core/MCPSession.swift` | §4.4 |
| 令牌与文案 | `Core/DesignTokens.swift`、`Core/Localization.swift` | §8.1、§8.8 |
| 命令登记 | `App/AppCommandCatalog.swift`（39 条） | §8.3 |

## 2. 数据库执行模块

### 2.1 类型与职责

- `DatabaseService`（协议）：`execute(...)` 返回 `AsyncThrowingStream`，`cancel(_ handle:) async -> CancelOutcome`。
- 三个方言实现：`PostgresService`、`MySQLService`、`GBaseService`。方言差异只在实现内部（语句切分、取消方式、元数据查询），上层只见协议。
- `ExecutionSafety`：执行前的只读/写判定（`needsConfirmation` / `refused`）。
- `ExecutionHandle`：一次执行的归属句柄，取消与并发控制都以它为键。

### 2.2 时序（执行一条 SQL）

1. 装配层取**显示中**编辑器（有选区跑选区，无选区跑整篇）——不读缓存内容。
2. 参数未取齐 ⇒ 停在参数面板，不连库。
3. `ExecutionSafety` 判：`refused`（只读连接上的写语句）直接拒，不提供「仍然执行」。
4. 手工事务模式：首条语句前懒发 `BEGIN`。
5. 服务 `execute` → 事件流：`started` / `resultSet`×N / `finished`（或 `cancelled` / `failed`）。
6. 结果进页签，行数只累加一次；随后写历史与 SQL 归档。

### 2.3 取消

- 先按句柄找后端 PID；拿不到（连接已断 / 方言不支持）⇒ `CancelOutcome.failed(reason:)`，原因必须能显示给人。
- 取消成功后状态是 `cancelled`，**不能**再收 `resultSet`；半截结果不落库。

### 2.4 事务

- 手工模式与自动提交分开；一个页签一个事务会话。
- 事务进行中不换连接：换连接 = 事务悬空，实现上直接禁掉。

### 2.5 错误映射

驱动错误三元组（SQLSTATE / 消息 / 位置）→ 平台中立错误类型 → 界面按契约 §9 三级呈现。原始错误串只在日志里，用户可见文案走语言表。

## 3. 智能体回合模块

### 3.1 事件与限流

- `AgentLoopEvent` 是回合对外唯一形状；`AgentLoopObserver` 接事件。
- 异常事件用**机器码**（`stalled` / `spinning` / `retryStorm` / `budgetApproaching` / `budgetExhausted`），文案由语言表映射——机器码不进界面字符串。
- `AgentLoopLimits` 管预算（token/时长/工具次数）；耗尽即结束回合并留审计，不静默续命。

### 3.2 工具调用

- `AgentToolDispatcher` 执行工具；`AgentToolSchemaValidator.validate(argumentsJSON:against:)` 先校验参数，不合规直接给模型可读错误（不执行）。
- 工具结果统一包成观察值回灌，**有界**（超限报错，不静默截断）。

### 3.3 审批与审计

- `AgentApprovalGate` 产出 `AgentApprovalVerdict`；`AgentApprovalConsumption` 记录一次批准被消费（requestID + 时间），防同一条批准被重放。
- 改数据动作的执行路径必须穿过审批门；审计追加一条（含 SQL 原文、风险档、结论）。
- 未裁决的审批**不得**落成「已通过」。

### 3.4 影响行数预估（`AgentPlanRows`）

- `explainStatement(for:)`：只包 `EXPLAIN (FORMAT JSON) <DML>`，不带 `ANALYZE`；非 DML / 多语句返回 `nil`。
- `rows(fromExplainJSON:)`：解析优化器 `Plan Rows`。**已知坑见 §8.1**。
- `estimate(json:)`：四档结论——有值 / `noAnswer` / `parseFailed` / 上游原因码（`notDataChange`、`dialectUnsupported`、`noConnection`）。
- 结果只作**批准前的参考读数**，不作为执行依据；估不出来就如实说，不报 0。

## 4. 笔记模块

### 4.1 存储

- `NoteLibrary` 是 `actor`：库连接只在它内部持有，界面层拿不到连接。
- `NoteDatabase` 负责 SQLite；本体 + 标签 + 时间线**同一事务**写入。
- 正文权威源是 span 树，正文视图是投影；投影与正文不一致时按 span 树重投影，不反向写。

### 4.2 自动保存

- `NoteAutosave` 合并窗口 **1.5 s**（比工作区编辑器的 0.12 / 0.45 s 大，因为自动保存是落盘不是重绘）。
- 三条守卫：许可通过 / 有内容 / 有改动；缺一不写。
- 状态 `idle` / `pending` / `failed(reason)`：`pending` 期间再编辑 ⇒ 保持 `pending` 并重排，**不丢新按键**；失败时工具条与状态栏各说一次，自动保存不弹窗。
- 切走时先快照再排队，不等写盘完成。

### 4.3 同步

- `CloudSyncService` 管同步态，`SyncQueue` 串行上传（单飞）。
- 401 ⇒ 续期一次并重放一次；仍失败 ⇒ 同步态降级、**保留队列**；续期失败不当作登出。
- 登录态与同步态是两个状态，不许合并。

## 5. 会话与搜索

- `AgentSessionStore.defaultDirectory`：一会话一文件，文件名即 id；`summaryList(workspace:)` 返回 `AgentSessionSummaryResult`（含跳过文件数）。
- 搜索：按 `Character` 偏移切分（不按 `utf8`/`utf16`，否则中文会错位），命中不重叠，返回 `total` 与 `firstMatchID`；`firstMatchID` 供 UI 跳转。
- 界面侧 `AgentChatModel` 只读派生，打开会话要显式切 `sessionID`，不隐式切。

## 6. 并发与线程模型

| 约束 | 落法 |
|---|---|
| 界面状态只在主线程改 | 装配层与模型 `@MainActor`；能力层回调只递值，不直接改 UI |
| 一个「连接 + 库」只有一个服务实例 | `AppState.ensureService` 以「连接 + 库」为缓存键；跨页签共享同一服务与事务 |
| 同一连接上的语句串行 | 服务内部串行队列；取消走句柄，不靠抢占 |
| 笔记写入单事务 | `NoteLibrary` actor 内串行 |
| 同步单飞 | `SyncQueue` 串行，重入即排队 |

## 7. 错误与降级

三级（与契约 §9 同一套）：可恢复（就地提示 + 重试入口）、阻断（说明原因与下一步）、静默（只进日志，且不得掩盖影响结果的问题）。

错误在层间只加信息不改语义；跨层错误一律转成能力层错误类型再上浮。

## 8. 本端已知坑（必须先读）

### 8.1 PG 18 改进数据语句的 `Plan Rows` 在根节点上是 0

`EXPLAIN (FORMAT JSON) UPDATE …` 的根节点是 `ModifyTable`，`Plan Rows` 恒为 0（不带 `RETURNING` 时它不输出行），真实预估在**子节点**（如 `Seq Scan` 500）。只读根会稳定报「0 行」——最危险的假数。
规则：根为 `ModifyTable`/`Update`/`Delete`/`Insert`/`Merge` 且根为 0 ⇒ 取 `Plans[0]`；根非 0（带 `RETURNING`）用根。**这条只有对真库跑才能发现。**

### 8.2 `swift test` 不带 `DEVELOPER_DIR` 会找不到 XCTest

报 `unable to resolve module dependency: 'XCTest'`。跑法：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`。

### 8.3 测试总数只认 `verify-core.sh`

`swift test --filter` 的 `Executed N tests` 是**过滤后**的数，不能当 Core 总数；真值在 `bash Scripts/verify-core.sh` 写出的 `.build/core-test-count.txt`。

### 8.4 localization 棘轮与锚仓 `pre-push` 护栏

- `check-core-localization` 基线 730→**746**；无授权不得 `--update-baseline`。
- Studio 锚仓 `.git/hooks/pre-push` 白名单只放 `Docs/**` 等；推 `Scripts/**` 会被拦，需 `-c core.hooksPath=/dev/null` 单次绕过并留痕。

## 9. 判据怎么跑

| 场景 | 命令 | 期望 |
|---|---|---|
| 纯能力层改动 | `bash Scripts/verify-core.sh` | 全绿，计数与台账一致 |
| 要出包 | `bash Scripts/build-app.sh` | 打印字节数 + sha256 前缀 |
| 界面改动 | `python3 Scripts/check-design-tokens.py` | 不高于基线 |
| 新命令入口 | `python3 Scripts/check-palette-wiring.py` | 未登记差集 0 |
| 新中文文案 | `python3 Scripts/check-core-localization.py` | 无缺键 / 无未分类 |
| 文档改动 | `python3 Scripts/check-doc-{numbers,tables,layout,versions}.py` | 全绿 |

## 10. 本文件尚未展开的模块（⬜）

| 模块 | 现状 |
|---|---|
| 导入导出（`DelimitedTextReader` / `XLSXReader` / `ResultExporter`） | 只有文件名，无详设 |
| 内嵌浏览器（`BrowserPage`） | 只有文件名，无详设 |
| 端云同步三端 | 契约未定，详设无从写 |
| 复盘（RTR） | 实现不在本仓，本端只有宿主视图 `App/Views/RetroHostView.swift` |
| 插件装载（`Core/Plugin/`） | 只有文件名，无详设 |

## 11. 变更记录

| 版本 | 日期 | 变更内容 | 影响范围 |
|---|---|---|---|
| v0.1 | 2026-10-23 | 首建：分层与模块表 + 三个核心模块详设（数据库执行 / 智能体回合 / 笔记）+ 会话搜索 + 并发模型 + 四条已知坑 + 判据表 + 未展开清单。替代原「实现要点」草稿（那份只是路径索引，已删） | macOS 端 |
