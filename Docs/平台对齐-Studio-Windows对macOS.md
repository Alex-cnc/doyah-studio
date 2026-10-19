# Doyah Studio · Windows 对 macOS 对齐件

> **本件身份：派生视图（非契约）** —— 真值源 = `Docs/Doyah产品需求说明书.md` §10.1（状态）/ §10.2（落点）+ `Docs/平台实现状态.json`（其他平台状态）。
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
> **与派单仓一次性快照的差异（1 行，如实登记）**：`DoyahDispatch` 的 `docs/平台对齐-Studio-Windows对macOS.md`（2026-10-14 前门一次性快照）把 `FR-PLUG-04` 记成 `—` —— 该条的 §10.2 格内有**转义竖线**（`CLI/main.swift`（`notes path\|legacy-path\|migrate`）），快照按裸 `|` 切格 ⇒ 整行错位、落点读不出来。本脚本按字面处理转义竖线 ⇒ 该条落点读得出来，故两处数目不同（快照 173 / 17 / **72**，本件 174 / 17 / **71**；合计均 262）。**以本件为准**（它可复跑）。

| 编号 | 域 | 类别 | macOS | macOS 落点 | Windows |
|---|---|---|---|---|---|
| AC-AI-01 | 7.4 智能体验收 | — | ⬜ | — | ⬜ |
| AC-AI-02 | 7.4 智能体验收 | — | ✅ | — | ⬜ |
| AC-AI-03 | 7.4 智能体验收 | — | ✅ | — | ⬜ |
| AC-AI-04 | 7.4 智能体验收 | — | ⬜ | — | ⬜ |
| AC-REL-01 | 7.1 发布门槛 | — | ✅ | — | ⬜ |
| AC-REL-02 | 7.1 发布门槛 | — | ✅ | — | ⬜ |
| AC-REL-03 | 7.1 发布门槛 | — | ✅ | — | ⬜ |
| AC-REL-04 | 7.1 发布门槛 | — | 🟡 | — | ⬜ |
| AC-REL-05 | 7.1 发布门槛 | — | ⬜ | — | ⬜ |
| AC-REL-06 | 7.1 发布门槛 | — | ⬜ | — | ⬜ |
| AC-REL-07 | 7.1 发布门槛 | — | ✅ | — | ⬜ |
| AC-REL-08 | 7.1 发布门槛 | — | ✅ | — | ⬜ |
| FR-AI-01 | 3.12 AI 智能体 | 基线必备 | ✅ | — | ⬜ |
| FR-AI-02 | 3.12 AI 智能体 | 基线必备 | ✅ | — | ⬜ |
| FR-AI-03 | 3.12 AI 智能体 | 常用增强 | 🟡 | — | ⬜ |
| FR-AI-04 | 3.12 AI 智能体 | 常用增强 | 🟡 | — | ⬜ |
| FR-AI-05 | 3.12 AI 智能体 | 基线必备 | ✅ | `Core/DataTask.swift`、`issues`、`dryRun` 等 10 处 | ⬜ |
| FR-AI-06 | 3.12 AI 智能体 | 基线必备 | ✅ | `Core/DataTask.swift`、`TaskScheduler`、`TaskRunRecord` 等 11 处 | ⬜ |
| FR-AI-07 | 3.12 AI 智能体 | 常用增强 | 🟡 | — | ⬜ |
| FR-AI-08 | 3.12 AI 智能体 | 基线必备 | ✅ | `Core/SecureDirectoryAccess.swift`、`Core/DataTaskRun.swift`、`App/DirectoryPanelPicker.swift` 等 7 处 | ⬜ |
| FR-AI-09 | 3.12 AI 智能体 | 基线必备 | ✅ | — | ⬜ |
| FR-AI-10 | 3.12 AI 智能体 | 进阶可选 | 🟡 | — | ⬜ |
| FR-AI-11 | 3.12 AI 智能体 | 常用增强 | 🟡 | — | ⬜ |
| FR-AI-12 | 3.12 AI 智能体 | 基线必备 | 🟡 | — | ⬜ |
| FR-AI-13 | 3.12 AI 智能体 | 常用增强 | ✅ | `Docs/Doyah产品能力说明书.md` | ⬜ |
| FR-AI-14 | 3.12 AI 智能体 | 常用增强 | 🟡 | `Docs/Doyah产品能力说明书.md` | ⬜ |
| FR-AI-15 | 3.12 AI 智能体 | 常用增强 | 🟡 | `Docs/Doyah产品能力说明书.md` | ⬜ |
| FR-AI-16 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力说明书.md` 等 4 处 | ⬜ |
| FR-AI-17 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力说明书.md` 等 4 处 | ⬜ |
| FR-AI-18 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力说明书.md` 等 4 处 | ⬜ |
| FR-AI-19 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力说明书.md` 等 4 处 | ⬜ |
| FR-AI-20 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力说明书.md` 等 4 处 | ⬜ |
| FR-AI-21 | 3.12 AI 智能体 | 进阶可选 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力说明书.md` 等 4 处 | ⬜ |
| FR-AI-22 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力说明书.md` 等 4 处 | ⬜ |
| FR-AI-23 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力说明书.md` 等 4 处 | ⬜ |
| FR-AI-24 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力说明书.md` 等 4 处 | ⬜ |
| FR-AI-25 | 3.12 AI 智能体 | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力说明书.md` 等 4 处 | ⬜ |
| FR-AI-26 | 3.12 AI 智能体 | 常用增强 | ⬜ | `TaskScheduler`、`FR-AI-15`、`Docs/Doyah产品概要设计说明书.md` | ⬜ |
| FR-AI-27 | 3.12 AI 智能体 | 常用增强 | ⬜ | `TaskScheduler`、`FR-AI-15`、`Docs/Doyah产品概要设计说明书.md` | ⬜ |
| FR-AI-28 | 3.12 AI 智能体 | 常用增强 | ⬜ | `TaskScheduler`、`FR-AI-15`、`Docs/Doyah产品概要设计说明书.md` | ⬜ |
| FR-AI-29 | 3.12 AI 智能体 | 常用增强 | ⬜ | `TaskScheduler`、`FR-AI-15`、`Docs/Doyah产品概要设计说明书.md` | ⬜ |
| FR-AI-30 | 3.12 AI 智能体 | 常用增强 | ⬜ | `FR-AI-30`、`FR-AI-31`、`Docs/Doyah产品概要设计说明书.md` 等 8 处 | ⬜ |
| FR-AI-31 | 3.12 AI 智能体 | 常用增强 | ⬜ | `FR-AI-30`、`FR-AI-31`、`Docs/Doyah产品概要设计说明书.md` 等 8 处 | ⬜ |
| FR-BLD-01 | 3.11 构建与工具链 | 基线必备 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-BLD-02 | 3.11 构建与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-BLD-03 | 3.11 构建与工具链 | 基线必备 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-BLD-04 | 3.11 构建与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-BLD-05 | 3.11 构建与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-BLD-06 | 3.11 构建与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-BLD-07 | 3.11 构建与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ⬜ |
| FR-BLD-08 | 3.11 构建与工具链 | 进阶可选 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-BLD-09 | 3.11 构建与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-CLI-01 | 3.11 构建与工具链 | 常用增强 | ✅ | `CLI/main.swift` | ✅ |
| FR-CLI-02 | 3.11 构建与工具链 | 常用增强 | ✅ | `CLI/main.swift` | ✅ |
| FR-CLI-03 | 3.11 构建与工具链 | 常用增强 | ✅ | `CLI/main.swift` | ✅ |
| FR-CLI-04 | 3.11 构建与工具链 | 常用增强 | ✅ | `CLI/main.swift` | ✅ |
| FR-CLI-05 | 3.11 构建与工具链 | 常用增强 | ✅ | `CLI/main.swift` | ✅ |
| FR-CONN-01 | 3.1 连接与凭据 | 基线必备 | ✅ | `App/Views/ConnectionListView.swift`、`ConnectionFormView.swift`、`Core/ConnectionConfig.swift` 等 4 处 | ✅ |
| FR-CONN-02 | 3.1 连接与凭据 | 基线必备 | ✅ | `App/Views/ConnectionListView.swift`、`ConnectionFormView.swift`、`Core/ConnectionConfig.swift` 等 4 处 | ✅ |
| FR-CONN-03 | 3.1 连接与凭据 | 常用增强 | ✅ | `App/Views/ConnectionListView.swift`、`ConnectionFormView.swift`、`Core/ConnectionConfig.swift` 等 4 处 | ⬜ |
| FR-CONN-04 | 3.1 连接与凭据 | 基线必备 | ✅ | `App/Views/MainWindow.swift`、`.sheet(item:)`、`ConnectionFormMode` | ✅ |
| FR-CONN-05 | 3.1 连接与凭据 | 基线必备 | ✅ | `App/Views/ConnectionListView.swift`、`confirmationDialog`、`AppState.deleteConnection` 等 4 处 | ✅ |
| FR-CONN-06 | 3.1 连接与凭据 | 基线必备 | ✅ | `Core/ConnectionConfig.isValid`、`App/Views/ConnectionFormView.swift::isValid` | ✅ |
| FR-CONN-07 | 3.1 连接与凭据 | 基线必备 | ✅ | `Core/KeychainHelper.swift`、`App/AppState.swift::updateConnection` | ✅ |
| FR-CONN-08 | 3.1 连接与凭据 | 常用增强 | ✅ | `Core/KeychainHelper.swift`、`App/AppState.swift::updateConnection` | ✅ |
| FR-CONN-09 | 3.1 连接与凭据 | 基线必备 | ✅ | `ConnectionFormView.testConnection`、`Core/PostgresService.connect` | ✅ |
| FR-CONN-10 | 3.1 连接与凭据 | 进阶可选 | ✅ | `Core/ConnectionConfig.swift` | ✅ |
| FR-CONN-11 | 3.1 连接与凭据 | 进阶可选 | ✅ | `AppState.restoredConnectionID(in:)`、`rememberSelectedConnection()`、`UserDefaults` | ✅ |
| FR-CONN-12 | 3.1 连接与凭据 | 常用增强 | ✅ | `App/Views/QueryContextBar.swift`、`AppState.selectedConnectionID` | ✅ |
| FR-CONN-13 | 3.1 连接与凭据 | 常用增强 | ✅ | `Core/Dialects.swift::listDatabasesQuery`、`AppState.loadDatabases`、`App/Views/QueryContextBar.swift` | ✅ |
| FR-CONN-14 | 3.1 连接与凭据 | 常用增强 | ✅ | `Core/ConnectionConfig.swift::displayTitle(untitled:)`、`App/Views/ConnectionListView.swift`、`QueryContextBar.swift` | ✅ |
| FR-CONN-15 | 3.1 连接与凭据 | 常用增强 | 🟡 | （追溯表有行、未标路径） | ✅ |
| FR-CONN-16 | 3.1 连接与凭据 | 常用增强 | ✅ | （追溯表有行、未标路径） | ✅ |
| FR-CONN-17 | 3.1 连接与凭据 | 常用增强 | ✅ | （追溯表有行、未标路径） | ✅ |
| FR-CONN-18 | 3.1 连接与凭据 | 常用增强 | 🟡 | （追溯表有行、未标路径） | ⬜ |
| FR-CONN-19 | 3.1 连接与凭据 | 进阶可选 | ✅ | （追溯表有行、未标路径） | ✅ |
| FR-CONN-20 | 3.1 连接与凭据 | 进阶可选 | ✅ | （追溯表有行、未标路径） | ✅ |
| FR-DATA-01 | 3.5 数据编辑与写回 | 基线必备 | ✅ | `Core/SQLGenerator.swift` | ✅ |
| FR-DATA-02 | 3.5 数据编辑与写回 | 常用增强 | 🟡 | `Core/SQLGenerator.swift` | ✅ |
| FR-DATA-03 | 3.5 数据编辑与写回 | 常用增强 | ✅ | `Core/SQLGenerator.swift` | ✅ |
| FR-DATA-04 | 3.5 数据编辑与写回 | 常用增强 | ✅ | — | ✅ |
| FR-DATA-05 | 3.5 数据编辑与写回 | 进阶可选 | 🟡 | （追溯表有行、未标路径） | ✅ |
| FR-DATA-06 | 3.5 数据编辑与写回 | 进阶可选 | 🟡 | — | ✅ |
| FR-DDL-01 | 3.6 表结构与 DDL | 常用增强 | ✅ | `Core/SQLGenerator.swift` | ✅ |
| FR-DDL-02 | 3.6 表结构与 DDL | 进阶可选 | ✅ | `Core/SQLGenerator.swift` | ✅ |
| FR-DDL-03 | 3.6 表结构与 DDL | 常用增强 | 🟡 | `Core/TableDesign.swift`、`Core/SQLGenerator.alterTableStatements`、`Core/MetadataService.tableStructure` 等 5 处 | ✅ |
| FR-DDL-04 | 3.6 表结构与 DDL | 进阶可选 | 🟡 | （追溯表有行、未标路径） | ⬜ |
| FR-DDL-05 | 3.6 表结构与 DDL | 进阶可选 | ✅ | （追溯表有行、未标路径） | ✅ |
| FR-DIAG-01 | 3.7 性能与诊断 | 基线必备 | ✅ | `Core/ExplainPlan.swift`、`Core/SQLGenerator.swift::explain`、`Core/Dialects.swift` | ✅ |
| FR-DIAG-02 | 3.7 性能与诊断 | 常用增强 | ✅ | `Core/ExplainPlan.swift`、`Core/SQLGenerator.swift::explain`、`Core/Dialects.swift` | ✅ |
| FR-DIAG-03 | 3.7 性能与诊断 | 进阶可选 | 🟡 | `pg_stat_statements` | ⬜ |
| FR-DIAG-04 | 3.7 性能与诊断 | 进阶可选 | 🟡 | `pg_stat_statements` | ✅ |
| FR-DIAG-05 | 3.7 性能与诊断 | 进阶可选 | ✅ | — | ✅ |
| FR-DRV-01 | 3.10 驱动与方言兼容 | 基线必备 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ✅ |
| FR-DRV-02 | 3.10 驱动与方言兼容 | 常用增强 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ✅ |
| FR-DRV-03 | 3.10 驱动与方言兼容 | 基线必备 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ✅ |
| FR-DRV-04 | 3.10 驱动与方言兼容 | 基线必备 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ✅ |
| FR-DRV-05 | 3.10 驱动与方言兼容 | 基线必备 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ✅ |
| FR-DRV-06 | 3.10 驱动与方言兼容 | 基线必备 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ✅ |
| FR-DRV-07 | 3.10 驱动与方言兼容 | 常用增强 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ⬜ |
| FR-DRV-08 | 3.10 驱动与方言兼容 | 进阶可选 | 🟡 | `Core/Dialects.swift::GBaseDialect`、`Core/StatementSplitter.swift`、`DELIMITER` | ✅ |
| FR-DRV-09 | 3.10 驱动与方言兼容 | 常用增强 | ✅ | `MySQLService`、`MySQLDialect`、`DatabaseType.mysql` | ⬜ |
| FR-EDIT-01 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `AppState.tabs`、`App/Views/QueryWorkspaceView.swift`、`DoyahStudioApp.swift` | ✅ |
| FR-EDIT-02 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/SQLTokenizer.swift`、`App/Views/SQLEditorView.swift` | ✅ |
| FR-EDIT-03 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `Core/SQLLinter.swift`、`QueryEditorView.diagnosticsBar` | ✅ |
| FR-EDIT-04 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/SQLLinter.swift`、`QueryEditorView.diagnosticsBar` | ✅ |
| FR-EDIT-05 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `AppState.checkSyntax`、`QueryEditorView` | ✅ |
| FR-EDIT-06 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `AppState.checkSyntax`、`QueryEditorView` | ✅ |
| FR-EDIT-07 | 3.2 SQL 编辑与执行 | 进阶可选 | ✅ | `AppState.checkSyntax`、`QueryEditorView` | ✅ |
| FR-EDIT-08 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/Views/QueryToolbar.swift` | ✅ |
| FR-EDIT-09 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/Utilities/SQLCompleter.swift`、`App/Views/SQLEditorView.swift`、`textView(_:completions:forPartialWordRange:indexOfSelectedItem:)` 等 4 处 | ✅ |
| FR-EDIT-10 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/ConnectionConfig.swift::QueryHistory`、`AppState.queryHistory`、`recordHistory` 等 5 处 | ✅ |
| FR-EDIT-11 | 3.2 SQL 编辑与执行 | 进阶可选 | ✅ | `App/Utilities/SecureASCIIField.swift` | ✅ |
| FR-EDIT-12 | 3.2 SQL 编辑与执行 | 进阶可选 | ✅ | `QueryEditorView.diagnostics` | ✅ |
| FR-EDIT-13 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/Views/QueryWorkspaceView.swift`、`VSplitView` | ⬜ |
| FR-EDIT-14 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/Views/QueryToolbar.swift`、`App/Views/SaveQuerySheet.swift`、`Core/SavedQueryStore.swift` 等 4 处 | ⬜ |
| FR-EDIT-15 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `App/AppState.swift::openFileFromPanel / openFile`、`App/Views/QueryToolbar.swift`、`App/Views/QueryWorkspaceView.swift` | ✅ |
| FR-EDIT-16 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `AppState.saveCurrentFile / writeFile`、`QueryToolbar`、`Menu(primaryAction:)` | ✅ |
| FR-EDIT-17 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-EDIT-18 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ✅ |
| FR-EDIT-19 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-EDIT-20 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-EDIT-21 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ✅ |
| FR-EDIT-22 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ✅ |
| FR-EDIT-23 | 3.2 SQL 编辑与执行 | 进阶可选 | ✅ | `App/Views/QueryToolbar.swift::helpButton` | ✅ |
| FR-EDIT-24 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/TabNumberGenerator.swift`、`AppState.tabNumbers` | ✅ |
| FR-EDIT-25 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | （追溯表有行、未标路径） | ✅ |
| FR-EDIT-26 | 3.2 SQL 编辑与执行 | 进阶可选 | 🟡 | （追溯表有行、未标路径） | ⬜ |
| FR-EDIT-27 | 3.2 SQL 编辑与执行 | 进阶可选 | 🟡 | （追溯表有行、未标路径） | ⬜ |
| FR-EDIT-28 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/ShortcutCatalog.swift`、`App/Views/QueryToolbar.swift` | ✅ |
| FR-EDIT-29 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/TerminalTabs.swift`、`TerminalTabTitle`、`TerminalTab` 等 16 处 | ✅ |
| FR-EDIT-30 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/LowerPaneTab.swift`、`Core/TabLog.swift`、`App/Views/LowerPaneView.swift` | ✅ |
| FR-EDIT-31 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/SQLArchive.swift`、`Core/SQLArchiveStore.swift`、`App/AppState.swift` 等 5 处 | ⬜ |
| FR-EDIT-32 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Docs/design/外观方案-v1.md` | ✅ |
| FR-EDIT-33 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/AccentTheme.swift`、`App/AccentManager.swift`、`.tint` 等 12 处 | ✅ |
| FR-EDIT-34 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | — | ⬜ |
| FR-EDIT-35 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/WorkspaceTab.swift`、`Core/WorkspaceHistory.swift`、`Core/WorkspaceHistoryStore.swift` 等 7 处 | ✅ |
| FR-EDIT-36 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/TextLanguage.swift`、`Core/CodeSyntax.swift`、`Core/CodeLexer.swift` 等 7 处 | ✅ |
| FR-EDIT-37 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/ActivityBar.swift`、`WindowTitle`、`Core/Localization.swift` 等 23 处 | ✅ |
| FR-EDIT-38 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/CodeLanguageDefinitions.swift`、`detect`、`TextLanguage` 等 21 处 | ✅ |
| FR-EDIT-39 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/CodeFormatting.swift`、`CodeFormatProcessRunning`、`Core/CodeLanguageDefinitions.swift` 等 10 处 | ✅ |
| FR-EDIT-40 | 3.2 SQL 编辑与执行 | 常用增强 | ⬜ | `Core/AIAssist.swift`、`App/Views/AIAssistPanel.swift`、`Core/ModelEndpoint.swift` | ⬜ |
| FR-EDIT-41 | 3.2 SQL 编辑与执行 | 常用增强 | ⬜ | `Core/WorkspaceTree.swift`、`App/Views/WorkspaceExplorerView.swift` | ✅ |
| FR-EDIT-42 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/WorkspaceSearch.swift`、`App/Views/WorkspaceSearchPanel.swift` | ✅ |
| FR-EDIT-43 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/WorkspaceSession.swift`、`App/WorkspaceTabsModel.swift` | ✅ |
| FR-EDIT-44 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/WorkspaceSearch.swift`、`FR-EDIT-42`、`App/Views/WorkspaceHeaderSearch.swift` | ✅ |
| FR-EDIT-45 | 3.2 SQL 编辑与执行 | 常用增强 | ⬜ | `Core/`、`App/Views/MarkdownPreview.swift`、`Core/MarkdownDocument.swift` 等 10 处 | ✅ |
| FR-EDIT-46 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/WorkspaceClose.swift`、`App/WorkspaceTabsModel.swift`、`requestClose` 等 8 处 | ✅ |
| FR-EDIT-47 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/MarkdownEditing.swift`、`MarkdownListEditing.continuation`、`App/Views/CodeEditorView.swift` 等 7 处 | ⬜ |
| FR-EDIT-48 | 3.2 SQL 编辑与执行 | 常用增强 | 🟡 | `Core/MarkdownEditing.swift`、`toggleTask`、`App/Views/CodeEditorView.swift::performKeyEquivalent` | ⬜ |
| FR-EXEC-01 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `App/AppState.swift::executeQuery`、`Core/PostgresService.swift::performExecute`、`StatementSplitter.swift` | ✅ |
| FR-EXEC-02 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `App/AppState.swift::executeQuery`、`Core/PostgresService.swift::performExecute`、`StatementSplitter.swift` | ✅ |
| FR-EXEC-03 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `App/AppState.swift::executeQuery`、`Core/PostgresService.swift::performExecute`、`StatementSplitter.swift` | ✅ |
| FR-EXEC-04 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `QueryTab.results`、`App/Views/ResultTableView.swift`、`ResultGrid.swift` | ✅ |
| FR-EXEC-05 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `QueryTab.results`、`App/Views/ResultTableView.swift`、`ResultGrid.swift` | ✅ |
| FR-EXEC-06 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `AppState`、`closeTab` | ✅ |
| FR-EXEC-07 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `AppState`、`closeTab` | ⬜ |
| FR-EXEC-08 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `PostgresService.cancel()`、`pg_cancel_backend`、`AppState.cancelQuery` 等 4 处 | ✅ |
| FR-EXEC-09 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `AppState.ensureService`、`connectTasks` | ✅ |
| FR-EXEC-10 | 3.2 SQL 编辑与执行 | 进阶可选 | ✅ | `PostgresService.reportsAffectedRows(_:)`、`PostgresQueryMetadata.rows`、`QueryResult.affectedRows` | ✅ |
| FR-EXEC-11 | 3.2 SQL 编辑与执行 | 进阶可选 | ✅ | `Core/DatabaseService.swift`、`PostgresService.begin/commit/rollback` | ✅ |
| FR-EXEC-12 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `AppState.executeQuery` | ✅ |
| FR-EXEC-13 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `App/Views/QueryToolbar.swift`、`QueryEditorView`、`AppState.startQuery/cancelQuery` | ✅ |
| FR-EXEC-14 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `Core/ExecutionScope.swift`、`AppState.executeQuery`、`App/ExecutionScopeTitle.swift` 等 5 处 | ✅ |
| FR-EXEC-15 | 3.2 SQL 编辑与执行 | 常用增强 | ✅ | `Core/TransactionSession.swift`、`App/Views/TransactionControl.swift`、`AppState.executeQuery` | ✅ |
| FR-EXEC-16 | 3.2 SQL 编辑与执行 | 基线必备 | ✅ | `Core/ExecutionSafety.swift`、`AppState.executeQuery`、`App/Views/SafeModeConfirmSheet.swift` 等 4 处 | ✅ |
| FR-EXEC-17 | 3.2 SQL 编辑与执行 | 进阶可选 | ✅ | `Core/SQLParameters.swift`、`App/Views/QueryParameterSheet.swift`、`AppState.executeQuery` 等 4 处 | ⬜ |
| FR-IO-01 | 3.9 导入导出与备份 | 基线必备 | ✅ | （追溯表有行、未标路径） | ✅ |
| FR-IO-02 | 3.9 导入导出与备份 | 常用增强 | 🟡 | `COPY … TO / FROM STDIN` | ⬜ |
| FR-IO-03 | 3.9 导入导出与备份 | 进阶可选 | 🟡 | `COPY … TO / FROM STDIN` | ✅ |
| FR-IO-04 | 3.9 导入导出与备份 | 常用增强 | 🟡 | `COPY … TO / FROM STDIN` | ⬜ |
| FR-IO-05 | 3.9 导入导出与备份 | 进阶可选 | 🟡 | `COPY … TO / FROM STDIN` | ⬜ |
| FR-IO-06 | 3.9 导入导出与备份 | 进阶可选 | 🟡 | `Core/XLSXReader.swift`、`Core/Inflate.swift`、`CLI/main.swift` 等 5 处 | ✅ |
| FR-IO-07 | 3.9 导入导出与备份 | 常用增强 | ✅ | `Core/ResultExportEncoding.swift`、`Core/TextFileDecoder.swift`、`Core/ResultExporter.swift` 等 11 处 | ✅ |
| FR-META-01 | 3.4 对象浏览与元数据 | 基线必备 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-META-02 | 3.4 对象浏览与元数据 | 常用增强 | 🟡 | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ⬜ |
| FR-META-03 | 3.4 对象浏览与元数据 | 基线必备 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-META-04 | 3.4 对象浏览与元数据 | 常用增强 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-META-05 | 3.4 对象浏览与元数据 | 常用增强 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-META-06 | 3.4 对象浏览与元数据 | 进阶可选 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-META-07 | 3.4 对象浏览与元数据 | 进阶可选 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-META-08 | 3.4 对象浏览与元数据 | 常用增强 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-META-09 | 3.4 对象浏览与元数据 | 基线必备 | 🟡 | `App/Views/ObjectTreeView.swift`、`Core/MetadataService.swift` | ✅ |
| FR-META-10 | 3.4 对象浏览与元数据 | 基线必备 | 🟡 | `Core/MetadataService.swift`、`App/AppState.swift`、`CLI/main.swift` | ⬜ |
| FR-META-11 | 3.4 对象浏览与元数据 | 常用增强 | ✅ | `Core/Dialects.swift::databaseCreationPrivilegeQuery()`、`Core/PrivilegeProbe.swift`、`App/AppState.swift` 等 6 处 | ✅ |
| FR-META-12 | 3.4 对象浏览与元数据 | 常用增强 | 🟡 | `Core/SQLGenerator.swift` | ✅ |
| FR-META-13 | 3.4 对象浏览与元数据 | 常用增强 | 🟡 | `Core/ObjectTreeActions.swift`、`App/Views/ObjectTreeView.swift`、`AppState.performTreeAction` | ✅ |
| FR-META-14 | 3.4 对象浏览与元数据 | 基线必备 | ✅ | `Core/ObjectTreeActions.swift`、`App/Views/ObjectTreeView.swift`、`AppState.performTreeAction` | ✅ |
| FR-META-15 | 3.4 对象浏览与元数据 | 进阶可选 | 🟡 | — | ✅ |
| FR-PLUG-01 | 3.13 插件装配 | 基线必备 | ✅ | `Core/Note*.swift`、`AICapture*.swift`、`App/Views/NotesPanel.swift` | ✅ |
| FR-PLUG-02 | 3.13 插件装配 | 基线必备 | ✅ | `Core/ActivityBar.swift`、`case notes`、`Core/LicensePresentation.swift` 等 4 处 | ✅ |
| FR-PLUG-03 | 3.13 插件装配 | 基线必备 | ✅ | `Core/AICapture.swift`、`Core/Note.swift`、`NoteDraft` 等 5 处 | ✅ |
| FR-PLUG-04 | 3.13 插件装配 | 常用增强 | ✅ | `Core/Note.swift`、`NoteStore.defaultFileURL`、`legacyFileURL` 等 11 处 | ✅ |
| FR-PLUG-05 | 3.13 插件装配 | 基线必备 | 🟡 | `linux/`、`Scripts/check-notes-offline.py`、`Scripts/notes-offline-gate.json` 等 4 处 | ⬜ |
| FR-PLUG-06 | 3.13 插件装配 | 基线必备 | ✅ | `Core/License.swift`、`LicenseCapabilities.all` | ✅ |
| FR-PLUG-07 | 3.13 插件装配 | 基线必备 | ✅ | `Scripts/check-note-module-isolation.py` | ✅ |
| FR-PLUG-08 | 3.13 插件装配 | 基线必备 | 🟡 | `Core/NoteStorage/`、`SQLiteKit`、`NoteDatabase` 等 9 处 | ✅ |
| FR-RES-01 | 3.3 结果集与导出 | 基线必备 | ✅ | `App/Views/ResultGrid.swift`、`ResultTableView.swift`、`Core/PostgresCellFormatter.swift` | ✅ |
| FR-RES-02 | 3.3 结果集与导出 | 常用增强 | ✅ | `App/Views/ResultGrid.swift`、`ResultTableView.swift`、`Core/PostgresCellFormatter.swift` | ✅ |
| FR-RES-03 | 3.3 结果集与导出 | 基线必备 | ✅ | `App/Views/ResultGrid.swift`、`ResultTableView.swift`、`Core/PostgresCellFormatter.swift` | ✅ |
| FR-RES-04 | 3.3 结果集与导出 | 常用增强 | ✅ | `App/Views/ResultGrid.swift`、`ResultTableView.swift`、`Core/PostgresCellFormatter.swift` | ✅ |
| FR-RES-05 | 3.3 结果集与导出 | 常用增强 | ✅ | `App/Views/ResultGrid.swift`、`ResultTableView.swift`、`Core/PostgresCellFormatter.swift` | ✅ |
| FR-RES-06 | 3.3 结果集与导出 | 常用增强 | ✅ | `Core/ResultExporter.swift`、`App/Views/ResultTableView.swift`、`AppState.exportResult(for:format:)` | ✅ |
| FR-RES-07 | 3.3 结果集与导出 | 常用增强 | 🟡 | （追溯表有行、未标路径） | ✅ |
| FR-RES-08 | 3.3 结果集与导出 | 常用增强 | 🟡 | `Core/ResultView.swift` | ✅ |
| FR-RES-09 | 3.3 结果集与导出 | 常用增强 | 🟡 | `Core/ResultView.swift` | ✅ |
| FR-RES-10 | 3.3 结果集与导出 | 常用增强 | 🟡 | `Core/ResultView.swift` | ✅ |
| FR-RES-11 | 3.3 结果集与导出 | 常用增强 | ✅ | `Core/ResultExporter.swift`、`App/Views/ResultTableView.swift`、`AppState.exportResult` | ✅ |
| FR-RES-12 | 3.3 结果集与导出 | 常用增强 | 🟡 | （追溯表有行、未标路径） | ✅ |
| FR-RES-13 | 3.3 结果集与导出 | 进阶可选 | 🟡 | `Core/ResultStreamWriter.swift`、`Core/ResultExporter.swift` | ✅ |
| FR-RES-14 | 3.3 结果集与导出 | 进阶可选 | 🟡 | — | ✅ |
| FR-SESS-01 | 3.8 会话与服务器管理 | 常用增强 | 🟡 | `Core/SessionMonitor.swift`、`Core/Dialects.swift`、`serverActivityQuery` 等 5 处 | ✅ |
| FR-SESS-02 | 3.8 会话与服务器管理 | 常用增强 | 🟡 | `Core/SessionMonitor.swift`、`Core/Dialects.swift`、`serverActivityQuery` 等 5 处 | ✅ |
| FR-SESS-03 | 3.8 会话与服务器管理 | 进阶可选 | 🟡 | （追溯表有行、未标路径） | ⬜ |
| FR-SESS-04 | 3.8 会话与服务器管理 | 常用增强 | ✅ | — | ✅ |
| FR-SESS-05 | 3.8 会话与服务器管理 | 常用增强 | ✅ | — | ✅ |
| NFR-AI-01 | 4.8 AI 智能体 | 基线必备 | ✅ | — | ⬜ |
| NFR-AI-02 | 4.8 AI 智能体 | 基线必备 | ✅ | — | ⬜ |
| NFR-AI-03 | 4.8 AI 智能体 | 基线必备 | ✅ | — | ⬜ |
| NFR-AI-04 | 4.8 AI 智能体 | 常用增强 | 🟡 | — | ⬜ |
| NFR-AI-05 | 4.8 AI 智能体 | 基线必备 | ✅ | — | ⬜ |
| NFR-AI-06 | 4.8 AI 智能体 | 常用增强 | 🟡 | — | ⬜ |
| NFR-AI-07 | 4.8 AI 智能体 | 常用增强 | ⬜ | `AgentKeyStore`、`AgentAudit`、`AgentQuota` 等 7 处 | ⬜ |
| NFR-AI-08 | 4.8 AI 智能体 | 常用增强 | ⬜ | `G6`、`NFR-AI-07`、`FR-AI-30` 等 4 处 | ⬜ |
| NFR-COMP-01 | 4.5 NFR-COMP | 基线必备 | 🟡 | — | ⬜ |
| NFR-COMP-02 | 4.5 NFR-COMP | 基线必备 | 🟡 | — | ⬜ |
| NFR-COMP-03 | 4.5 NFR-COMP | 基线必备 | 🟡 | — | ⬜ |
| NFR-COMP-04 | 4.5 NFR-COMP | 进阶可选 | ⬜ | — | ⬜ |
| NFR-COMP-05 | 4.5 NFR-COMP | 常用增强 | ⬜ | （追溯表有行、未标路径） | ⬜ |
| NFR-I18N-01 | 4.7 NFR-I18N | 常用增强 | 🟡 | — | ⬜ |
| NFR-I18N-02 | 4.7 NFR-I18N | 常用增强 | ✅ | — | ⬜ |
| NFR-I18N-03 | 4.7 NFR-I18N | 常用增强 | ✅ | `Core/Localization.swift`、`Core/MenuLocalization.swift`、`App/LocalizationManager.swift` 等 8 处 | ⬜ |
| NFR-MAINT-01 | 4.6 NFR-MAINT | 常用增强 | ✅ | — | ⬜ |
| NFR-MAINT-02 | 4.6 NFR-MAINT | 常用增强 | ✅ | — | ⬜ |
| NFR-MAINT-03 | 4.6 NFR-MAINT | 常用增强 | ✅ | — | ⬜ |
| NFR-MAINT-04 | 4.6 NFR-MAINT | 常用增强 | ✅ | — | ⬜ |
| NFR-MAINT-05 | 4.6 NFR-MAINT | 常用增强 | ✅ | — | ⬜ |
| NFR-MAINT-06 | 4.6 NFR-MAINT | 常用增强 | ✅ | — | ⬜ |
| NFR-PERF-01 | 4.1 NFR-PERF | 基线必备 | 🟡 | — | ⬜ |
| NFR-PERF-02 | 4.1 NFR-PERF | 基线必备 | 🟡 | — | ⬜ |
| NFR-PERF-03 | 4.1 NFR-PERF | 基线必备 | 🟡 | — | ⬜ |
| NFR-PERF-04 | 4.1 NFR-PERF | 基线必备 | 🟡 | — | ⬜ |
| NFR-PERF-05 | 4.1 NFR-PERF | 基线必备 | ✅ | — | ⬜ |
| NFR-PERF-06 | 4.1 NFR-PERF | 基线必备 | ✅ | — | ⬜ |
| NFR-REL-01 | 4.2 NFR-REL | 基线必备 | ✅ | — | ⬜ |
| NFR-REL-02 | 4.2 NFR-REL | 基线必备 | ✅ | — | ⬜ |
| NFR-REL-03 | 4.2 NFR-REL | 基线必备 | ✅ | — | ⬜ |
| NFR-REL-04 | 4.2 NFR-REL | 基线必备 | ✅ | — | ⬜ |
| NFR-REL-05 | 4.2 NFR-REL | 基线必备 | ✅ | — | ⬜ |
| NFR-SEC-01 | 4.3 NFR-SEC | 基线必备 | ✅ | — | ⬜ |
| NFR-SEC-02 | 4.3 NFR-SEC | 基线必备 | ✅ | — | ⬜ |
| NFR-SEC-03 | 4.3 NFR-SEC | 基线必备 | ✅ | — | ⬜ |
| NFR-SEC-04 | 4.3 NFR-SEC | 基线必备 | ✅ | — | ⬜ |
| NFR-SEC-05 | 4.3 NFR-SEC | 基线必备 | ✅ | — | ⬜ |
| NFR-SEC-06 | 4.3 NFR-SEC | 基线必备 | ✅ | — | ⬜ |
| NFR-SEC-07 | 4.3 NFR-SEC | 基线必备 | ✅ | — | ⬜ |
| NFR-SEC-08 | 4.3 NFR-SEC | 基线必备 | 🟡 | — | ⬜ |
| NFR-UI-01 | 4.9 NFR-UI | 基线必备 | ⬜ | — | ⬜ |
| NFR-USE-01 | 4.4 NFR-USE | 常用增强 | ✅ | — | ⬜ |
| NFR-USE-02 | 4.4 NFR-USE | 常用增强 | ✅ | — | ⬜ |
| NFR-USE-03 | 4.4 NFR-USE | 常用增强 | ✅ | — | ⬜ |
| NFR-USE-04 | 4.4 NFR-USE | 常用增强 | ✅ | — | ⬜ |
