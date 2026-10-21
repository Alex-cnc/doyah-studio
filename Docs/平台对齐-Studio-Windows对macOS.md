# Doyah Studio · Windows 对 macOS 对齐件

> **本件身份：派生视图（非契约）** —— 真值源 = `Docs/Doyah产品需求分析说明书.md` §10.1（状态）/ §10.2（落点）+ `Docs/平台实现状态.json`（其他平台状态）。
> **两处不一致时以三书为准**。**不要手工编辑本表** —— 改了必漂移：本件由 `Scripts/gen-studio-win-align.py` 产出，`--check` 在闭环第 7 项判漂移。
>
> **用途**：`fatshark`（Windows / Harmony 侧）对齐 macOS 版 Doyah Studio 开发进度时的**逐条索引** —— 每行 = 一条需求 → 所属域 → 层次 → macOS 状态 → **macOS 落点（去这里读实现）** → Windows 现状。
>
> **统计**：需求 **262** 条 · 有落点 **174** 条 · 追溯表有行未标路径 **17** 条 · 无追溯行（落点列 `—`）**71** 条 · 台账 Windows `overrides` **145 条**（缺失一律按 `⬜` 记 —— 整列 `⬜` = Windows Studio 未开工）。
> §10.2 里另有 **5** 行不是需求编号（分组行 / 决定行，如 `NFR-PERF / COMP`），它们不对应单条需求 ⇒ 不进本索引。
>
> **口径**：`macOS` 列 = §10.1 状态格的**第一个取值**；`macOS 落点` = §10.2 该条所在行的**反引号片段**（前 3 个 + 「等 N 处」；同一编号出现在多行时取**最后一行**；范围行展开到每一条）。**无追溯行写 `—`、有行未标路径写「（追溯表有行、未标路径）」—— 两种都不编落点**。
> `Windows` 列 = 台账**原值**（不带 §10.10 的 ⚠️ 差异标记：等价判定在矩阵，本件只给落点索引）。
>
> **与派单仓一次性快照的差异（1 行，如实登记）**：`DoyahDispatch` 的 `docs/平台对齐-Studio-Windows对macOS.md`（2026-10-14 前门一次性快照）把 `FR-STD-ALL-PLUG-004` 记成 `—` —— 该条的 §10.2 格内有**转义竖线**（`CLI/main.swift`（`notes path\|legacy-path\|migrate`）），快照按裸 `|` 切格 ⇒ 整行错位、落点读不出来。本脚本按字面处理转义竖线 ⇒ 该条落点读得出来，故两处数目不同（快照 173 / 17 / **72**，本件 174 / 17 / **71**；合计均 262）。**以本件为准**（它可复跑）。

| 编号 | 域 | 类别 | macOS | macOS 落点 | Windows |
|---|---|---|---|---|---|
| AC-ALL-GATE-AI-01 | 7.4 智能体验收 | — | ⬜ | — | ⬜ |
| AC-ALL-GATE-AI-02 | 7.4 智能体验收 | — | ✅ | — | ⬜ |
| AC-ALL-GATE-AI-03 | 7.4 智能体验收 | — | ✅ | — | ⬜ |
| AC-ALL-GATE-AI-04 | 7.4 智能体验收 | — | ⬜ | — | ⬜ |
| AC-ALL-GATE-REL-01 | 7.1 发布门槛 | — | ✅ | — | ⬜ |
| AC-ALL-GATE-REL-02 | 7.1 发布门槛 | — | ✅ | — | ⬜ |
| AC-ALL-GATE-REL-03 | 7.1 发布门槛 | — | ✅ | — | ⬜ |
| AC-ALL-GATE-REL-04 | 7.1 发布门槛 | — | 🟡 | — | ⬜ |
| AC-ALL-GATE-REL-05 | 7.1 发布门槛 | — | ⬜ | — | ⬜ |
| AC-ALL-GATE-REL-06 | 7.1 发布门槛 | — | ⬜ | — | ⬜ |
| AC-ALL-GATE-REL-07 | 7.1 发布门槛 | — | ✅ | — | ⬜ |
| AC-ALL-GATE-REL-08 | 7.1 发布门槛 | — | ✅ | — | ⬜ |
| FR-AGT-LINK-CHAN-001 | 3.12 AI 智能体 | 基线必备 | ✅ | — | ⬜ |
| FR-AGT-CORE-LOOP-001 | 3.12 AI 智能体 | 基线必备 | ✅ | — | ⬜ |
| FR-AGT-UX-CONV-001 | 3.12 AI 智能体 | 常用增强 | 🟡 | — | ⬜ |
| FR-AGT-PLAN-PLAN-001 | 3.12 AI 智能体 | 常用增强 | 🟡 | — | ⬜ |
| FR-AGT-PLAN-PLAN-002 | 3.12 AI 智能体 | 基线必备 | ✅ | `Core/DataTask.swift`、`issues`、`dryRun` 等 10 处 | ⬜ |
| FR-AGT-TOOL-SCHED-001 | 3.12 AI 智能体 | 基线必备 | ✅ | `Core/DataTask.swift`、`TaskScheduler`、`TaskRunRecord` 等 11 处 | ⬜ |
| FR-AGT-CORE-LOOP-002 | 3.12 AI 智能体 | 常用增强 | 🟡 | — | ⬜ |
| FR-AGT-CORE-LOOP-003 | 3.12 AI 智能体 | 基线必备 | ✅ | `Core/SecureDirectoryAccess.swift`、`Core/DataTaskRun.swift`、`App/DirectoryPanelPicker.swift` 等 7 处 | ⬜ |
| FR-AGT-GUARD-PERM-001 | 3.12 AI 智能体 | 基线必备 | ✅ | — | ⬜ |
| FR-AGT-LINK-EXT-001 | 3.12 AI 智能体 | 进阶可选 | 🟡 | — | ⬜ |
| FR-AGT-PLAN-PLAN-003 | 3.12 AI 智能体 | 常用增强 | 🟡 | — | ⬜ |
| FR-AGT-GUARD-PERM-004 | 3.12 AI 智能体 | 基线必备 | 🟡 | — | ⬜ |
| FR-AGT-KNOW-MEM-001 | 3.12 AI 智能体 | 常用增强 | ✅ | `Docs/Doyah产品能力规划说明书.md` | ⬜ |
| FR-AGT-KNOW-MEM-004 | 3.12 AI 智能体 | 常用增强 | 🟡 | `Docs/Doyah产品能力规划说明书.md` | ⬜ |
| FR-AGT-KNOW-MEM-002 | 3.12 AI 智能体 | 常用增强 | 🟡 | `Docs/Doyah产品能力规划说明书.md` | ⬜ |
| FR-AGT-LINK-CHAN-002 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力规划说明书.md` 等 4 处 | ⬜ |
| FR-AGT-UX-CONV-002 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力规划说明书.md` 等 4 处 | ⬜ |
| FR-AGT-CORE-LOOP-004 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力规划说明书.md` 等 4 处 | ⬜ |
| FR-AGT-CORE-LOOP-005 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力规划说明书.md` 等 4 处 | ⬜ |
| FR-AGT-CORE-LOOP-006 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力规划说明书.md` 等 4 处 | ⬜ |
| FR-AGT-LINK-EXT-002 | 3.12 AI 智能体 | 进阶可选 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力规划说明书.md` 等 4 处 | ⬜ |
| FR-AGT-CORE-CTX-001 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力规划说明书.md` 等 4 处 | ⬜ |
| FR-AGT-GUARD-PERM-002 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力规划说明书.md` 等 4 处 | ⬜ |
| FR-AGT-GUARD-SOUL-002 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力规划说明书.md` 等 4 处 | ⬜ |
| FR-AGT-UX-CONV-003 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力规划说明书.md` 等 4 处 | ⬜ |
| FR-AGT-KNOW-MEM-005 | 3.12 AI 智能体 | 常用增强 | ⬜ | `TaskScheduler`、`FR-AGT-KNOW-MEM-002`、`Docs/Doyah产品概要设计说明书.md` | ⬜ |
| FR-AGT-TOOL-SCHED-002 | 3.12 AI 智能体 | 常用增强 | ⬜ | `TaskScheduler`、`FR-AGT-KNOW-MEM-002`、`Docs/Doyah产品概要设计说明书.md` | ⬜ |
| FR-AGT-GUARD-COST-001 | 3.12 AI 智能体 | 常用增强 | ⬜ | `TaskScheduler`、`FR-AGT-KNOW-MEM-002`、`Docs/Doyah产品概要设计说明书.md` | ⬜ |
| FR-AGT-KNOW-MEM-003 | 3.12 AI 智能体 | 常用增强 | ⬜ | `TaskScheduler`、`FR-AGT-KNOW-MEM-002`、`Docs/Doyah产品概要设计说明书.md` | ⬜ |
| FR-AGT-UX-CONV-004 | 3.12 AI 智能体 | 常用增强 | ⬜ | `FR-AGT-UX-CONV-004`、`FR-AGT-UX-CONV-005`、`Docs/Doyah产品概要设计说明书.md` 等 8 处 | ⬜ |
| FR-AGT-UX-CONV-005 | 3.12 AI 智能体 | 常用增强 | ⬜ | `FR-AGT-UX-CONV-004`、`FR-AGT-UX-CONV-005`、`Docs/Doyah产品概要设计说明书.md` 等 8 处 | ⬜ |
| FR-STD-ALL-BLD-001 | 3.11 构建与工具链 | 基线必备 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-BLD-002 | 3.11 构建与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-BLD-003 | 3.11 构建与工具链 | 基线必备 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-BLD-004 | 3.11 构建与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-BLD-005 | 3.11 构建与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-BLD-006 | 3.11 构建与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-BLD-007 | 3.11 构建与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ⬜ |
| FR-STD-ALL-BLD-008 | 3.11 构建与工具链 | 进阶可选 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-BLD-009 | 3.11 构建与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-CLI-001 | 3.11 构建与工具链 | 常用增强 | ✅ | `CLI/main.swift` | ✅ |
| FR-STD-ALL-CLI-002 | 3.11 构建与工具链 | 常用增强 | ✅ | `CLI/main.swift` | ✅ |
| FR-STD-ALL-CLI-003 | 3.11 构建与工具链 | 常用增强 | ✅ | `CLI/main.swift` | ✅ |
| FR-STD-ALL-CLI-004 | 3.11 构建与工具链 | 常用增强 | ✅ | `CLI/main.swift` | ✅ |
| FR-STD-ALL-CLI-005 | 3.11 构建与工具链 | 常用增强 | ✅ | `CLI/main.swift` | ✅ |
| FR-STD-DB-CONN-007 | 3.1 连接与凭据 | 基线必备 | ✅ | `App/Views/ConnectionListView.swift`、`ConnectionFormView.swift`、`Core/ConnectionConfig.swift` 等 4 处 | ✅ |
| FR-STD-DB-CONN-001 | 3.1 连接与凭据 | 基线必备 | ✅ | `App/Views/ConnectionListView.swift`、`ConnectionFormView.swift`、`Core/ConnectionConfig.swift` 等 4 处 | ✅ |
| FR-STD-DB-CONN-002 | 3.1 连接与凭据 | 常用增强 | ✅ | `App/Views/ConnectionListView.swift`、`ConnectionFormView.swift`、`Core/ConnectionConfig.swift` 等 4 处 | ⬜ |
| FR-STD-DB-CONN-008 | 3.1 连接与凭据 | 基线必备 | ✅ | `App/Views/MainWindow.swift`、`.sheet(item:)`、`ConnectionFormMode` | ✅ |
| FR-STD-DB-CONN-009 | 3.1 连接与凭据 | 基线必备 | ✅ | `App/Views/ConnectionListView.swift`、`confirmationDialog`、`AppState.deleteConnection` 等 4 处 | ✅ |
| FR-STD-DB-CONN-003 | 3.1 连接与凭据 | 基线必备 | ✅ | `Core/ConnectionConfig.isValid`、`App/Views/ConnectionFormView.swift::isValid` | ✅ |
| FR-STD-DB-CONN-017 | 3.1 连接与凭据 | 基线必备 | ✅ | `Core/KeychainHelper.swift`、`App/AppState.swift::updateConnection` | ✅ |
| FR-STD-DB-CONN-018 | 3.1 连接与凭据 | 常用增强 | ✅ | `Core/KeychainHelper.swift`、`App/AppState.swift::updateConnection` | ✅ |
| FR-STD-DB-CONN-021 | 3.1 连接与凭据 | 基线必备 | ✅ | `ConnectionFormView.testConnection`、`Core/PostgresService.connect` | ✅ |
| FR-STD-DB-CONN-004 | 3.1 连接与凭据 | 进阶可选 | ✅ | `Core/ConnectionConfig.swift` | ✅ |
| FR-STD-DB-CONN-010 | 3.1 连接与凭据 | 进阶可选 | ✅ | `AppState.restoredConnectionID(in:)`、`rememberSelectedConnection()`、`UserDefaults` | ✅ |
| FR-STD-DB-CONN-015 | 3.1 连接与凭据 | 常用增强 | ✅ | `App/Views/QueryContextBar.swift`、`AppState.selectedConnectionID` | ✅ |
| FR-STD-DB-CONN-016 | 3.1 连接与凭据 | 常用增强 | ✅ | `Core/Dialects.swift::listDatabasesQuery`、`AppState.loadDatabases`、`App/Views/QueryContextBar.swift` | ✅ |
| FR-STD-DB-CONN-011 | 3.1 连接与凭据 | 常用增强 | ✅ | `Core/ConnectionConfig.swift::displayTitle(untitled:)`、`App/Views/ConnectionListView.swift`、`QueryContextBar.swift` | ✅ |
| FR-STD-DB-CONN-012 | 3.1 连接与凭据 | 常用增强 | 🟡 | （追溯表有行、未标路径） | ✅ |
| FR-STD-DB-CONN-013 | 3.1 连接与凭据 | 常用增强 | ✅ | （追溯表有行、未标路径） | ✅ |
| FR-STD-DB-CONN-014 | 3.1 连接与凭据 | 常用增强 | ✅ | （追溯表有行、未标路径） | ✅ |
| FR-STD-DB-CONN-020 | 3.1 连接与凭据 | 常用增强 | 🟡 | （追溯表有行、未标路径） | ⬜ |
| FR-STD-DB-CONN-005 | 3.1 连接与凭据 | 进阶可选 | ✅ | （追溯表有行、未标路径） | ✅ |
| FR-STD-DB-CONN-006 | 3.1 连接与凭据 | 进阶可选 | ✅ | （追溯表有行、未标路径） | ✅ |
| FR-STD-DB-DATA-001 | 3.5 数据编辑与写回 | 基线必备 | ✅ | `Core/SQLGenerator.swift` | ✅ |
| FR-STD-DB-DATA-002 | 3.5 数据编辑与写回 | 常用增强 | 🟡 | `Core/SQLGenerator.swift` | ✅ |
| FR-STD-DB-DATA-003 | 3.5 数据编辑与写回 | 常用增强 | ✅ | `Core/SQLGenerator.swift` | ✅ |
| FR-STD-DB-DATA-004 | 3.5 数据编辑与写回 | 常用增强 | ✅ | — | ✅ |
| FR-STD-DB-DATA-005 | 3.5 数据编辑与写回 | 进阶可选 | 🟡 | （追溯表有行、未标路径） | ✅ |
| FR-STD-DB-DATA-006 | 3.5 数据编辑与写回 | 进阶可选 | 🟡 | — | ✅ |
| FR-STD-DB-DDL-001 | 3.6 表结构与 DDL | 常用增强 | ✅ | `Core/SQLGenerator.swift` | ✅ |
| FR-STD-DB-DDL-002 | 3.6 表结构与 DDL | 进阶可选 | ✅ | `Core/SQLGenerator.swift` | ✅ |
| FR-STD-DB-DDL-003 | 3.6 表结构与 DDL | 常用增强 | 🟡 | `Core/TableDesign.swift`、`Core/SQLGenerator.alterTableStatements`、`Core/MetadataService.tableStructure` 等 5 处 | ✅ |
| FR-STD-DB-DDL-004 | 3.6 表结构与 DDL | 进阶可选 | 🟡 | （追溯表有行、未标路径） | ⬜ |
| FR-STD-DB-DDL-005 | 3.6 表结构与 DDL | 进阶可选 | ✅ | （追溯表有行、未标路径） | ✅ |
| FR-STD-DB-DIAG-001 | 3.7 性能与诊断 | 基线必备 | ✅ | `Core/ExplainPlan.swift`、`Core/SQLGenerator.swift::explain`、`Core/Dialects.swift` | ✅ |
| FR-STD-DB-DIAG-002 | 3.7 性能与诊断 | 常用增强 | ✅ | `Core/ExplainPlan.swift`、`Core/SQLGenerator.swift::explain`、`Core/Dialects.swift` | ✅ |
| FR-STD-DB-DIAG-003 | 3.7 性能与诊断 | 进阶可选 | 🟡 | `pg_stat_statements` | ⬜ |
| FR-STD-DB-DIAG-004 | 3.7 性能与诊断 | 进阶可选 | 🟡 | `pg_stat_statements` | ✅ |
| FR-STD-DB-DIAG-005 | 3.7 性能与诊断 | 进阶可选 | ✅ | — | ✅ |
| FR-STD-DB-DRV-005 | 3.10 驱动与方言兼容 | 基线必备 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ✅ |
| FR-STD-DB-DRV-006 | 3.10 驱动与方言兼容 | 常用增强 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ✅ |
| FR-STD-DB-DRV-007 | 3.10 驱动与方言兼容 | 基线必备 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ✅ |
| FR-STD-DB-DRV-008 | 3.10 驱动与方言兼容 | 基线必备 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ✅ |
| FR-STD-DB-DRV-001 | 3.10 驱动与方言兼容 | 基线必备 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ✅ |
| FR-STD-DB-DRV-002 | 3.10 驱动与方言兼容 | 基线必备 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ✅ |
| FR-STD-DB-DRV-003 | 3.10 驱动与方言兼容 | 常用增强 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ⬜ |
| FR-STD-DB-DRV-009 | 3.10 驱动与方言兼容 | 进阶可选 | 🟡 | `Core/Dialects.swift::GBaseDialect`、`Core/StatementSplitter.swift`、`DELIMITER` | ✅ |
| FR-STD-DB-DRV-010 | 3.10 驱动与方言兼容 | 常用增强 | ✅ | `MySQLService`、`MySQLDialect`、`DatabaseType.mysql` | ⬜ |
| FR-STD-WS-UI-001 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `AppState.tabs`、`App/Views/QueryWorkspaceView.swift`、`DoyahStudioApp.swift` | ✅ |
| FR-STD-WS-NAV-001 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/SQLTokenizer.swift`、`App/Views/SQLEditorView.swift` | ✅ |
| FR-STD-WS-NAV-007 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `Core/SQLLinter.swift`、`QueryEditorView.diagnosticsBar` | ✅ |
| FR-STD-WS-NAV-008 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/SQLLinter.swift`、`QueryEditorView.diagnosticsBar` | ✅ |
| FR-STD-WS-NAV-009 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `AppState.checkSyntax`、`QueryEditorView` | ✅ |
| FR-STD-WS-NAV-010 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `AppState.checkSyntax`、`QueryEditorView` | ✅ |
| FR-STD-WS-NAV-011 | 3.2 SQL 编辑与执行 | 进阶可选 | ✅ | `AppState.checkSyntax`、`QueryEditorView` | ✅ |
| FR-STD-DB-EXEC-014 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/Views/QueryToolbar.swift` | ✅ |
| FR-STD-WS-NAV-003 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/Utilities/SQLCompleter.swift`、`App/Views/SQLEditorView.swift`、`textView(_:completions:forPartialWordRange:indexOfSelectedItem:)` 等 4 处 | ✅ |
| FR-STD-DB-SESS-001 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/ConnectionConfig.swift::QueryHistory`、`AppState.queryHistory`、`recordHistory` 等 5 处 | ✅ |
| FR-STD-DB-CONN-019 | 3.2 SQL 编辑与执行 | 进阶可选 | ✅ | `App/Utilities/SecureASCIIField.swift` | ✅ |
| FR-STD-WS-EDIT-024 | 3.2 SQL 编辑与执行 | 进阶可选 | ✅ | `QueryEditorView.diagnostics` | ✅ |
| FR-STD-WS-UI-007 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/Views/QueryWorkspaceView.swift`、`VSplitView` | ⬜ |
| FR-STD-WS-EDIT-001 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/Views/QueryToolbar.swift`、`App/Views/SaveQuerySheet.swift`、`Core/SavedQueryStore.swift` 等 4 处 | ⬜ |
| FR-STD-WS-FS-007 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `App/AppState.swift::openFileFromPanel / openFile`、`App/Views/QueryToolbar.swift`、`App/Views/QueryWorkspaceView.swift` | ✅ |
| FR-STD-WS-EDIT-002 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `AppState.saveCurrentFile / writeFile`、`QueryToolbar`、`Menu(primaryAction:)` | ✅ |
| FR-STD-WS-EDIT-003 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-STD-WS-EDIT-010 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ✅ |
| FR-STD-WS-EDIT-011 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-STD-WS-EDIT-018 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-STD-WS-EDIT-004 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ✅ |
| FR-STD-WS-NAV-013 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ✅ |
| FR-STD-WS-HELP-001 | 3.2 SQL 编辑与执行 | 进阶可选 | ✅ | `App/Views/QueryToolbar.swift::helpButton` | ✅ |
| FR-STD-WS-UI-002 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/TabNumberGenerator.swift`、`AppState.tabNumbers` | ✅ |
| FR-STD-WS-UI-005 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | （追溯表有行、未标路径） | ✅ |
| FR-STD-WS-UI-008 | 3.2 SQL 编辑与执行 | 进阶可选 | 🟡 | （追溯表有行、未标路径） | ⬜ |
| FR-STD-WS-EDIT-016 | 3.2 SQL 编辑与执行 | 进阶可选 | 🟡 | （追溯表有行、未标路径） | ⬜ |
| FR-STD-WS-EDIT-005 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/ShortcutCatalog.swift`、`App/Views/QueryToolbar.swift` | ✅ |
| FR-STD-WS-TOOL-001 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/TerminalTabs.swift`、`TerminalTabTitle`、`TerminalTab` 等 16 处 | ✅ |
| FR-STD-WS-TOOL-002 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/LowerPaneTab.swift`、`Core/TabLog.swift`、`App/Views/LowerPaneView.swift` | ✅ |
| FR-STD-DB-EXEC-001 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/SQLArchive.swift`、`Core/SQLArchiveStore.swift`、`App/AppState.swift` 等 5 处 | ⬜ |
| FR-STD-WS-FS-002 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Docs/design/外观方案-v1.md` | ✅ |
| FR-STD-WS-UI-009 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/AccentTheme.swift`、`App/AccentManager.swift`、`.tint` 等 12 处 | ✅ |
| FR-STD-WS-WEB-001 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | — | ⬜ |
| FR-STD-WS-FS-001 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/WorkspaceTab.swift`、`Core/WorkspaceHistory.swift`、`Core/WorkspaceHistoryStore.swift` 等 7 处 | ✅ |
| FR-STD-WS-FS-008 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/TextLanguage.swift`、`Core/CodeSyntax.swift`、`Core/CodeLexer.swift` 等 7 处 | ✅ |
| FR-STD-WS-UI-006 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/ActivityBar.swift`、`WindowTitle`、`Core/Localization.swift` 等 23 处 | ✅ |
| FR-STD-WS-NAV-002 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/CodeLanguageDefinitions.swift`、`detect`、`TextLanguage` 等 21 处 | ✅ |
| FR-STD-WS-NAV-014 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/CodeFormatting.swift`、`CodeFormatProcessRunning`、`Core/CodeLanguageDefinitions.swift` 等 10 处 | ✅ |
| FR-STD-WS-AI-001 | 3.2 SQL 编辑与执行 | 常用增强 | ⬜ | `Core/AIAssist.swift`、`App/Views/AIAssistPanel.swift`、`Core/ModelEndpoint.swift` | ⬜ |
| FR-STD-WS-FS-003 | 3.2 SQL 编辑与执行 | 常用增强 | ⬜ | `Core/WorkspaceTree.swift`、`App/Views/WorkspaceExplorerView.swift` | ✅ |
| FR-STD-WS-EDIT-012 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/WorkspaceSearch.swift`、`App/Views/WorkspaceSearchPanel.swift` | ✅ |
| FR-STD-WS-UI-004 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/WorkspaceSession.swift`、`App/WorkspaceTabsModel.swift` | ✅ |
| FR-STD-WS-EDIT-013 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/WorkspaceSearch.swift`、`FR-STD-WS-EDIT-012`、`App/Views/WorkspaceHeaderSearch.swift` | ✅ |
| FR-STD-WS-WEB-002 | 3.2 SQL 编辑与执行 | 常用增强 | ⬜ | `Core/`、`App/Views/MarkdownPreview.swift`、`Core/MarkdownDocument.swift` 等 10 处 | ✅ |
| FR-STD-WS-UI-003 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/WorkspaceClose.swift`、`App/WorkspaceTabsModel.swift`、`requestClose` 等 8 处 | ✅ |
| FR-STD-WS-EDIT-006 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/MarkdownEditing.swift`、`MarkdownListEditing.continuation`、`App/Views/CodeEditorView.swift` 等 7 处 | ⬜ |
| FR-STD-WS-EDIT-007 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/MarkdownEditing.swift`、`toggleTask`、`App/Views/CodeEditorView.swift::performKeyEquivalent` | ⬜ |
| FR-STD-DB-EXEC-002 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `App/AppState.swift::executeQuery`、`Core/PostgresService.swift::performExecute`、`StatementSplitter.swift` | ✅ |
| FR-STD-DB-DRV-004 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `App/AppState.swift::executeQuery`、`Core/PostgresService.swift::performExecute`、`StatementSplitter.swift` | ✅ |
| FR-STD-DB-EXEC-003 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/AppState.swift::executeQuery`、`Core/PostgresService.swift::performExecute`、`StatementSplitter.swift` | ✅ |
| FR-STD-DB-EXEC-009 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `QueryTab.results`、`App/Views/ResultTableView.swift`、`ResultGrid.swift` | ✅ |
| FR-STD-DB-EXEC-010 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `QueryTab.results`、`App/Views/ResultTableView.swift`、`ResultGrid.swift` | ✅ |
| FR-STD-DB-EXEC-011 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `AppState`、`closeTab` | ✅ |
| FR-STD-DB-EXEC-012 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `AppState`、`closeTab` | ⬜ |
| FR-STD-DB-EXEC-018 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `PostgresService.cancel()`、`pg_cancel_backend`、`AppState.cancelQuery` 等 4 处 | ✅ |
| FR-STD-DB-EXEC-004 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `AppState.ensureService`、`connectTasks` | ✅ |
| FR-STD-DB-EXEC-013 | 3.2 SQL 编辑与执行 | 进阶可选 | ✅ | `PostgresService.reportsAffectedRows(_:)`、`PostgresQueryMetadata.rows`、`QueryResult.affectedRows` | ✅ |
| FR-STD-DB-EXEC-015 | 3.2 SQL 编辑与执行 | 进阶可选 | ✅ | `Core/DatabaseService.swift`、`PostgresService.begin/commit/rollback` | ✅ |
| FR-STD-DB-EXEC-005 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `AppState.executeQuery` | ✅ |
| FR-STD-DB-EXEC-016 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `App/Views/QueryToolbar.swift`、`QueryEditorView`、`AppState.startQuery/cancelQuery` | ✅ |
| FR-STD-DB-EXEC-006 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `Core/ExecutionScope.swift`、`AppState.executeQuery`、`App/ExecutionScopeTitle.swift` 等 5 处 | ✅ |
| FR-STD-DB-EXEC-007 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/TransactionSession.swift`、`App/Views/TransactionControl.swift`、`AppState.executeQuery` | ✅ |
| FR-STD-DB-EXEC-017 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `Core/ExecutionSafety.swift`、`AppState.executeQuery`、`App/Views/SafeModeConfirmSheet.swift` 等 4 处 | ✅ |
| FR-STD-DB-EXEC-008 | 3.2 SQL 编辑与执行 | 进阶可选 | ✅ | `Core/SQLParameters.swift`、`App/Views/QueryParameterSheet.swift`、`AppState.executeQuery` 等 4 处 | ⬜ |
| FR-STD-DB-IO-001 | 3.9 导入导出与备份 | 基线必备 | ✅ | （追溯表有行、未标路径） | ✅ |
| FR-STD-DB-IO-002 | 3.9 导入导出与备份 | 常用增强 | 🟡 | `COPY … TO / FROM STDIN` | ⬜ |
| FR-STD-DB-IO-006 | 3.9 导入导出与备份 | 进阶可选 | 🟡 | `COPY … TO / FROM STDIN` | ✅ |
| FR-STD-DB-IO-003 | 3.9 导入导出与备份 | 常用增强 | 🟡 | `COPY … TO / FROM STDIN` | ⬜ |
| FR-STD-DB-IO-004 | 3.9 导入导出与备份 | 进阶可选 | 🟡 | `COPY … TO / FROM STDIN` | ⬜ |
| FR-STD-DB-IO-007 | 3.9 导入导出与备份 | 进阶可选 | 🟡 | `Core/XLSXReader.swift`、`Core/Inflate.swift`、`CLI/main.swift` 等 5 处 | ✅ |
| FR-STD-DB-IO-005 | 3.9 导入导出与备份 | 常用增强 | ✅ | `Core/ResultExportEncoding.swift`、`Core/TextFileDecoder.swift`、`Core/ResultExporter.swift` 等 11 处 | ✅ |
| FR-STD-DB-META-001 | 3.4 对象浏览与元数据 | 基线必备 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-STD-DB-META-002 | 3.4 对象浏览与元数据 | 常用增强 | 🟡 | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ⬜ |
| FR-STD-DB-META-003 | 3.4 对象浏览与元数据 | 基线必备 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-STD-DB-META-004 | 3.4 对象浏览与元数据 | 常用增强 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-STD-DB-META-009 | 3.4 对象浏览与元数据 | 常用增强 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-STD-DB-META-005 | 3.4 对象浏览与元数据 | 进阶可选 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-STD-DB-META-013 | 3.4 对象浏览与元数据 | 进阶可选 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-STD-DB-META-014 | 3.4 对象浏览与元数据 | 常用增强 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-STD-DB-META-006 | 3.4 对象浏览与元数据 | 基线必备 | 🟡 | `App/Views/ObjectTreeView.swift`、`Core/MetadataService.swift` | ✅ |
| FR-STD-DB-META-007 | 3.4 对象浏览与元数据 | 基线必备 | 🟡 | `Core/MetadataService.swift`、`App/AppState.swift`、`CLI/main.swift` | ⬜ |
| FR-STD-DB-META-010 | 3.4 对象浏览与元数据 | 常用增强 | ✅ | `Core/Dialects.swift::databaseCreationPrivilegeQuery()`、`Core/PrivilegeProbe.swift`、`App/AppState.swift` 等 6 处 | ✅ |
| FR-STD-DB-META-015 | 3.4 对象浏览与元数据 | 常用增强 | 🟡 | `Core/SQLGenerator.swift` | ✅ |
| FR-STD-DB-META-011 | 3.4 对象浏览与元数据 | 常用增强 | 🟡 | `Core/ObjectTreeActions.swift`、`App/Views/ObjectTreeView.swift`、`AppState.performTreeAction` | ✅ |
| FR-STD-DB-META-012 | 3.4 对象浏览与元数据 | 基线必备 | ✅ | `Core/ObjectTreeActions.swift`、`App/Views/ObjectTreeView.swift`、`AppState.performTreeAction` | ✅ |
| FR-STD-DB-META-008 | 3.4 对象浏览与元数据 | 进阶可选 | 🟡 | — | ✅ |
| FR-STD-ALL-PLUG-001 | 3.13 插件装配 | 基线必备 | ✅ | `Core/Note*.swift`、`AICapture*.swift`、`App/Views/NotesPanel.swift` | ✅ |
| FR-STD-ALL-PLUG-002 | 3.13 插件装配 | 基线必备 | ✅ | `Core/ActivityBar.swift`、`case notes`、`Core/LicensePresentation.swift` 等 4 处 | ✅ |
| FR-STD-ALL-PLUG-003 | 3.13 插件装配 | 基线必备 | ✅ | `Core/AICapture.swift`、`Core/Note.swift`、`NoteDraft` 等 5 处 | ✅ |
| FR-STD-ALL-PLUG-004 | 3.13 插件装配 | 常用增强 | ✅ | `Core/Note.swift`、`NoteStore.defaultFileURL`、`legacyFileURL` 等 11 处 | ✅ |
| FR-STD-ALL-PLUG-005 | 3.13 插件装配 | 基线必备 | 🟡 | `linux/`、`Scripts/check-notes-offline.py`、`Scripts/notes-offline-gate.json` 等 4 处 | ⬜ |
| FR-STD-ALL-PLUG-006 | 3.13 插件装配 | 基线必备 | ✅ | `Core/License.swift`、`LicenseCapabilities.all` | ✅ |
| FR-STD-ALL-PLUG-007 | 3.13 插件装配 | 基线必备 | ✅ | `Scripts/check-note-module-isolation.py` | ✅ |
| FR-STD-ALL-PLUG-008 | 3.13 插件装配 | 基线必备 | 🟡 | `Core/NoteStorage/`、`SQLiteKit`、`NoteDatabase` 等 9 处 | ✅ |
| FR-STD-DB-RES-001 | 3.3 结果集与导出 | 基线必备 | ✅ | `App/Views/ResultGrid.swift`、`ResultTableView.swift`、`Core/PostgresCellFormatter.swift` | ✅ |
| FR-STD-DB-RES-002 | 3.3 结果集与导出 | 常用增强 | ✅ | `App/Views/ResultGrid.swift`、`ResultTableView.swift`、`Core/PostgresCellFormatter.swift` | ✅ |
| FR-STD-DB-RES-003 | 3.3 结果集与导出 | 基线必备 | ✅ | `App/Views/ResultGrid.swift`、`ResultTableView.swift`、`Core/PostgresCellFormatter.swift` | ✅ |
| FR-STD-DB-RES-004 | 3.3 结果集与导出 | 常用增强 | ✅ | `App/Views/ResultGrid.swift`、`ResultTableView.swift`、`Core/PostgresCellFormatter.swift` | ✅ |
| FR-STD-DB-RES-005 | 3.3 结果集与导出 | 常用增强 | ✅ | `App/Views/ResultGrid.swift`、`ResultTableView.swift`、`Core/PostgresCellFormatter.swift` | ✅ |
| FR-STD-DB-RES-010 | 3.3 结果集与导出 | 常用增强 | ✅ | `Core/ResultExporter.swift`、`App/Views/ResultTableView.swift`、`AppState.exportResult(for:format:)` | ✅ |
| FR-STD-DB-RES-011 | 3.3 结果集与导出 | 常用增强 | 🟡 | （追溯表有行、未标路径） | ✅ |
| FR-STD-DB-RES-007 | 3.3 结果集与导出 | 常用增强 | 🟡 | `Core/ResultView.swift` | ✅ |
| FR-STD-DB-RES-008 | 3.3 结果集与导出 | 常用增强 | 🟡 | `Core/ResultView.swift` | ✅ |
| FR-STD-DB-RES-009 | 3.3 结果集与导出 | 常用增强 | 🟡 | `Core/ResultView.swift` | ✅ |
| FR-STD-DB-RES-012 | 3.3 结果集与导出 | 常用增强 | ✅ | `Core/ResultExporter.swift`、`App/Views/ResultTableView.swift`、`AppState.exportResult` | ✅ |
| FR-STD-DB-RES-006 | 3.3 结果集与导出 | 常用增强 | 🟡 | （追溯表有行、未标路径） | ✅ |
| FR-STD-DB-RES-013 | 3.3 结果集与导出 | 进阶可选 | 🟡 | `Core/ResultStreamWriter.swift`、`Core/ResultExporter.swift` | ✅ |
| FR-STD-DB-RES-014 | 3.3 结果集与导出 | 进阶可选 | 🟡 | — | ✅ |
| FR-STD-DB-SESS-002 | 3.8 会话与服务器管理 | 常用增强 | 🟡 | `Core/SessionMonitor.swift`、`Core/Dialects.swift`、`serverActivityQuery` 等 5 处 | ✅ |
| FR-STD-DB-SESS-003 | 3.8 会话与服务器管理 | 常用增强 | 🟡 | `Core/SessionMonitor.swift`、`Core/Dialects.swift`、`serverActivityQuery` 等 5 处 | ✅ |
| FR-STD-DB-SESS-004 | 3.8 会话与服务器管理 | 进阶可选 | 🟡 | （追溯表有行、未标路径） | ⬜ |
| FR-STD-DB-SESS-005 | 3.8 会话与服务器管理 | 常用增强 | ✅ | — | ✅ |
| FR-STD-DB-SESS-006 | 3.8 会话与服务器管理 | 常用增强 | ✅ | — | ✅ |
| NFR-ALL-GATE-AI-001 | 4.8 AI 智能体 | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-AI-002 | 4.8 AI 智能体 | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-AI-003 | 4.8 AI 智能体 | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-AI-004 | 4.8 AI 智能体 | 常用增强 | 🟡 | — | ⬜ |
| NFR-ALL-GATE-AI-005 | 4.8 AI 智能体 | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-AI-006 | 4.8 AI 智能体 | 常用增强 | 🟡 | — | ⬜ |
| NFR-ALL-GATE-AI-007 | 4.8 AI 智能体 | 常用增强 | ⬜ | `AgentKeyStore`、`AgentAudit`、`AgentQuota` 等 7 处 | ⬜ |
| NFR-ALL-GATE-AI-008 | 4.8 AI 智能体 | 常用增强 | ⬜ | `G6`、`NFR-ALL-GATE-AI-007`、`FR-AGT-UX-CONV-004` 等 4 处 | ⬜ |
| NFR-ALL-GATE-COMP-004 | 4.5 NFR-COMP | 基线必备 | 🟡 | — | ⬜ |
| NFR-ALL-GATE-COMP-005 | 4.5 NFR-COMP | 基线必备 | 🟡 | — | ⬜ |
| NFR-ALL-GATE-COMP-001 | 4.5 NFR-COMP | 基线必备 | 🟡 | — | ⬜ |
| NFR-ALL-GATE-COMP-002 | 4.5 NFR-COMP | 进阶可选 | ⬜ | — | ⬜ |
| NFR-ALL-GATE-COMP-003 | 4.5 NFR-COMP | 常用增强 | ⬜ | （追溯表有行、未标路径） | ⬜ |
| NFR-I18N-01 | 4.7 NFR-I18N | 常用增强 | 🟡 | — | ⬜ |
| NFR-I18N-02 | 4.7 NFR-I18N | 常用增强 | ✅ | — | ⬜ |
| NFR-I18N-03 | 4.7 NFR-I18N | 常用增强 | ✅ | `Core/Localization.swift`、`Core/MenuLocalization.swift`、`App/LocalizationManager.swift` 等 8 处 | ⬜ |
| NFR-ALL-GATE-MAINT-001 | 4.6 NFR-MAINT | 常用增强 | ✅ | — | ⬜ |
| NFR-ALL-GATE-MAINT-002 | 4.6 NFR-MAINT | 常用增强 | ✅ | — | ⬜ |
| NFR-ALL-GATE-MAINT-003 | 4.6 NFR-MAINT | 常用增强 | ✅ | — | ⬜ |
| NFR-ALL-GATE-MAINT-004 | 4.6 NFR-MAINT | 常用增强 | ✅ | — | ⬜ |
| NFR-ALL-GATE-MAINT-005 | 4.6 NFR-MAINT | 常用增强 | ✅ | — | ⬜ |
| NFR-ALL-GATE-MAINT-006 | 4.6 NFR-MAINT | 常用增强 | ✅ | — | ⬜ |
| NFR-ALL-GATE-PERF-001 | 4.1 NFR-PERF | 基线必备 | 🟡 | — | ⬜ |
| NFR-ALL-GATE-PERF-002 | 4.1 NFR-PERF | 基线必备 | 🟡 | — | ⬜ |
| NFR-ALL-GATE-PERF-003 | 4.1 NFR-PERF | 基线必备 | 🟡 | — | ⬜ |
| NFR-ALL-GATE-PERF-004 | 4.1 NFR-PERF | 基线必备 | 🟡 | — | ⬜ |
| NFR-ALL-GATE-PERF-005 | 4.1 NFR-PERF | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-PERF-006 | 4.1 NFR-PERF | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-REL-001 | 4.2 NFR-REL | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-REL-002 | 4.2 NFR-REL | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-REL-003 | 4.2 NFR-REL | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-REL-004 | 4.2 NFR-REL | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-REL-005 | 4.2 NFR-REL | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-SEC-001 | 4.3 NFR-SEC | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-SEC-002 | 4.3 NFR-SEC | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-SEC-003 | 4.3 NFR-SEC | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-SEC-004 | 4.3 NFR-SEC | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-SEC-005 | 4.3 NFR-SEC | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-SEC-006 | 4.3 NFR-SEC | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-SEC-007 | 4.3 NFR-SEC | 基线必备 | ✅ | — | ⬜ |
| NFR-ALL-GATE-SEC-008 | 4.3 NFR-SEC | 基线必备 | 🟡 | — | ⬜ |
| NFR-ALL-GATE-UI-001 | 4.9 NFR-UI | 基线必备 | ⬜ | — | ⬜ |
| NFR-ALL-GATE-USE-001 | 4.4 NFR-USE | 常用增强 | ✅ | — | ⬜ |
| NFR-ALL-GATE-USE-002 | 4.4 NFR-USE | 常用增强 | ✅ | — | ⬜ |
| NFR-ALL-GATE-USE-003 | 4.4 NFR-USE | 常用增强 | ✅ | — | ⬜ |
| NFR-ALL-GATE-USE-004 | 4.4 NFR-USE | 常用增强 | ✅ | — | ⬜ |
