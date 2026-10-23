# Doyah 实现要点 · macOS

> **版本** v0.1（2026-10-23 首建；从执行契约 v0.4 切出的平台落点）

## 0. 本文件性质

执行契约（`Docs/Doyah产品概要设计说明书-执行契约-v0.1.md`）只写**跨端必须一致的行为**；
本文件写 **macOS 这一端怎么落**：哪个组件在哪个文件、调用点叫什么、数据落在哪、用哪条工具链。

- 读者：承担 macOS 端开发任务的 Agent。
- 优先级：需求规格书 > 执行契约 > **本文件** > 现有代码。
- 冲突处理：本文件与执行契约冲突 ⇒ 以契约为准并输出 `BLOCKED`（说明哪一条不一致）。
- 禁止：在本文件里新增能力、改判据口径、放宽契约里的「禁止」条款。
- 每条都挂「契约条款」列，指回执行契约的节号；挂不上的条目不属于本文件。

## 1. 组件落点

| 组件（契约里的名字） | 路径 | 关键类型 | 契约条款 |
|---|---|---|---|
| 数据库能力层 | `Core/PostgresService.swift`、`Core/MySQLService.swift`、`Core/GBaseService.swift` | `PostgresService` / `MySQLService` / `GBaseService`，统一 `execute(_:options:handle:)` | §3、§4.1 |
| 智能体回合 | `Core/AgentLoop.swift` | `AgentLoop` | §3、§7.2 |
| 工具层 | `Core/AgentToolRegistry.swift`、`Core/AgentSQLGenerator.swift`、`Core/AgentDatabaseTool.swift` | `AgentToolRegistry` 等 | §3、§4.4 |
| 审批与审计 | `Core/AgentApprovalGate.swift`、`Core/AgentAudit.swift`、`Core/AgentPlanRows.swift`、`Core/ExecutionSafety.swift` | `AgentApprovalGate` / `AgentAudit` / `AgentPlanRows` | §3、§4.4、§6.3 |
| 笔记存储 | `Plugins/Notes/Sources/NoteStorage/`（`NoteLibrary.swift`、`NoteDatabase.swift`） | `NoteLibrary`（actor）/ `NoteDatabase` | §3、§4.5、§6.2 |
| 笔记同步 | `Plugins/Notes/Sources/NoteSync/`（`CloudSyncService.swift`、`SyncQueue.swift`） | `CloudSyncService` / `SyncQueue` | §3、§4.6 |
| 会话持久化 | `Core/AgentSession.swift` | `AgentSessionStore` / `AgentSessionSummary` / `AgentTranscriptSearch` | §3、§5.1 |
| MCP 桥 | `Core/MCPClientBridge.swift`、`Core/MCPSession.swift` | `MCPClientBridge` / `MCPSession` | §3、§4.4 |
| 应用装配层 | `App/AppState.swift` | `AppState`（`@MainActor`），`ensureService` 按「连接 + 库」缓存 | §3、§7.1 |
| 界面层 | `App/Views/*`、`App/AgentChatModel.swift` | `AgentChatView` / `AgentChatModel` / `CommandPaletteView` | §3、§8 |
| 主题令牌 | `Core/DesignTokens.swift` | `Theme` / `Spacing` | §8.1、§11 |
| 语言表 | `Core/Localization.swift` | `L` / `L(...)` 取文案 | §8.8 |
| 命令登记 | `App/AppCommandCatalog.swift` | 39 条已登记命令 | §8.1、§8.3 |

调用链（macOS 端）：`App/Views` → `App/AppState` → `Core/*Service` → 驱动 / 磁盘 / 外部进程。
反向依赖、界面直调 Service、插件反向 import `App` 都算越层，与契约 §3 的禁止项同一判据。

## 2. 关键调用点

| 契约流程 | 落点 | 说明 | 契约条款 |
|---|---|---|---|
| 执行一条 SQL | `AppState` → `ExecutionScope.resolve` → `ExecutionSafety.check` → `TransactionSession.prepareStatement()` → 服务 `execute` | `ExecutionScope.resolve` 取**显示中**编辑器：有选区跑选区、无选区跑整篇 | §7.1 |
| 取消查询 | `AppState` → `ExecutionRegistry` → 服务 `cancel(handle:)` | 拿不到后端 PID 要如实说，不记成功 | §4.2、§7.1 |
| 智能体一轮 | `AgentLoop` → 模型流 → `AgentToolRegistry` → 审批 → `AgentAudit` → 落会话 | 轮内不并行两个改数据工具 | §7.2、§6.4 |
| 笔记自动保存 | `App/Views` didSet → `NoteAutosave`（**1.5 s** 窗口）→ `NoteLibrary.write` | 三条守卫：许可 / 有内容 / 有改动 | §6.2、§7.3 |
| 审批单行数预估 | `AppState.estimateAgentPlanRows(for:)` → `AgentPlanRows.explainStatement` → 服务 `execute` | 只发 `EXPLAIN (FORMAT JSON)`，不带 `ANALYZE` | §4.4、§10 |
| 会话列表 / 搜索 | `AgentChatModel.reloadSessions` / `AgentTranscriptSearch` | 按 `Character` 偏移、不重叠、给 `total` 与 `firstMatchID` | §5.1、§8.2 |
| 命令面板分组 | `AppCommandCatalog.splitAgentMatches(_:)` → `CommandPalette.grouped(commands:files:agent:)` | 智能体组恒排最前，空组不出标题 | §8.7 |

## 3. 数据落点（macOS）

| 数据 | 落点 | 约束 | 契约条款 |
|---|---|---|---|
| 连接配置 | `~/Library/Application Support/DoyahStudio/connections.json` | **不含口令**；读取时排除 secret 字段 | §5.3 |
| 口令 / secret | `SecretStore` / `LocalSecretStore`（Keychain 或加密文件） | 不进日志、不进模型上下文 | §5.3 |
| 会话条目 | `AgentSessionStore.defaultDirectory`（每会话一个文件，文件名即 id） | 只由存储层写；界面只读派生 | §5.1 |
| 审计记录 | `Core/AgentAudit` 追加式落盘 | 执行未入审计即缺陷 | §5.2 |
| 笔记库 | 本机 SQLite（`NoteDatabase` 单事务） | 本体 + 标签 + 时间线同事务 | §5.4 |
| 出包 | `dist/DoyahStudio-beta1.0.app` + `dist/发布说明-beta1.0.md` | 两处 sha 必须一致；发布说明与包同版 | §12.5 |

## 4. 工具链与构建

| 项 | 值 | 备注 |
|---|---|---|
| Xcode | 27.1（`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`） | 不带它跑 `swift test` 会报 `unable to resolve module dependency: 'XCTest'` |
| Swift | 6（macOS 27 SDK） | 语言模式与包清单见 `Package.swift` |
| 纯 Core 验证 | `bash Scripts/verify-core.sh` | 只认它写出的 `.build/core-test-count.txt`，`swift test --filter` 的计数不算总数 |
| 出包 | `bash Scripts/build-app.sh` | 打印字节数与 sha256 前缀；装到 `~/Applications` 用 `ditto` |
| 单测过滤 | `swift test --filter <Case>` | 调试用；判据读数不取它 |

## 5. 本端门禁清单

改 macOS 端代码后至少跑：

| 门禁 | 管什么 |
|---|---|
| `Scripts/verify-core.sh` | Core 全量测试计数 |
| `Scripts/build-app.sh` | 能出包（否则「能编」不等于「能发」） |
| `check-core-portability.py` / `check-platform-neutrality.py` | Core 不许 import 平台框架 |
| `check-design-tokens.py` | 界面不许裸数字 |
| `check-palette-wiring.py` | 新命令必须登记 |
| `check-core-localization.py` | 中文缺键 / 未分类英文 |
| `check-note-module-isolation.py` | 插件不许反向依赖 App |

## 6. 变更记录

| 版本 | 日期 | 变更内容 | 影响范围 |
|---|---|---|---|
| v0.1 | 2026-10-23 | 首建：从执行契约 v0.4 切出 macOS 落点（组件路径 / 调用点 / 数据落点 / 工具链 / 本端门禁），契约侧只留行为 | macOS 端；契约册减重 |
