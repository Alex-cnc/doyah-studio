# Doyah Studio · Windows 对 macOS 对齐件

> **本件身份：派生视图（非契约）** —— 真值源 = `Docs/Doyah产品需求规格说明书-需求索引.md`（编号 / 域 / 层次）+ 《开发计划书》§3（macOS 状态）+ `Docs/Doyah产品需求规格说明书-追溯表.md`（落点）+ `Docs/平台实现状态.json`（其他平台状态）。
> **两处不一致时以三书为准**。**不要手工编辑本表** —— 改了必漂移：本件由 `Scripts/gen-studio-win-align.py` 产出，`--check` 在闭环第 7 项判漂移。
>
> **用途**：`babyhippo`（Windows / Harmony 侧）对齐 macOS 版 Doyah Studio 开发进度时的**逐条索引** —— 每行 = 一条需求 → 所属域 → 层次 → macOS 状态 → **macOS 落点（去这里读实现）** → Windows 现状。
>
> **统计**：需求 **379** 条 · 有落点 **173** 条 · 追溯表有行未标路径 **16** 条 · 无追溯行（落点列 `—`）**190** 条 · 台账 Windows `overrides` **159 条**（缺失一律按 `⬜` 记 —— 整列 `⬜` = Windows Studio 未开工）。
> 本表只列 **`FR` 类**（379 条 = 平台差异的判定面）；需求索引里另有 **NFR 47** 条 / **AC 12** 条不进本表 —— 它们不分平台，也不在平台等价矩阵里，进表只会在 `Windows` 列造出一片假 `⬜`。
> 追溯表里另有 **4** 行不是需求编号（分组行 / 决定行，如 `NFR-PERF / COMP`），以及 **228** 行指向索引外的编号（范围行外沿 / 按 SRS 分工不进索引的 `FR-STD-ALL-DATA-*`（§5）与 `FR-STD-ALL-IFACE-*`（§6））—— 都不对应本索引里的单条需求 ⇒ 不进本表、不编落点。
>
> **口径**：`macOS` 列 = 计划书 §3 台账状态格的**第一个取值**；`macOS 落点` = 追溯表该条所在行的**反引号片段**（前 3 个 + 「等 N 处」；同一编号出现在多行时取**最后一行**；范围行展开到每一条）。**无追溯行写 `—`、有行未标路径写「（追溯表有行、未标路径）」—— 两种都不编落点**。
> `Windows` 列 = 台账**原值**（不带矩阵里的 ⚠️ 差异标记：等价判定在矩阵，本件只给落点索引）。
>
> **与派单仓一次性快照的差异（1 行，如实登记）**：`DoyahDispatch` 的 `docs/平台对齐-Studio-Windows对macOS.md`（2026-10-14 前门一次性快照）把 `FR-STD-ALL-PLUG-004` 记成 `—` —— 该条的追溯格内有**转义竖线**（`CLI/main.swift`（`notes path\|legacy-path\|migrate`）），快照按裸 `|` 切格 ⇒ 整行错位、落点读不出来。本脚本按字面处理转义竖线 ⇒ 该条落点读得出来，故两处数目不同（快照 173 / 17 / **72**，本件 173 / 16 / **190**；合计均 379）。**以本件为准**（它可复跑）。

| 编号 | 域 | 类别 | macOS | macOS 落点 | Windows |
|---|---|---|---|---|---|
| FR-RTR-MKT-HEALTH-003 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-FLOW-ORCH-001 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-FLOW-MARKET-001 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-REV-AI-001 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-FEATURE-001 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-SCREEN-001 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-SAMPLE-006 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-SCENARIO-006 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-NTS-NOTE-CAPTURE-001 | 3.5 Doyah Notes | 基线必备 | 🟡 | （追溯表有行、未标路径） | ⬜ |
| FR-NTS-NOTE-FORMAT-001 | 3.5 Doyah Notes | 基线必备 | ✅ | — | ⬜ |
| FR-NTS-NOTE-ATTACH-001 | 3.5 Doyah Notes | 基线必备 | 🟡 | — | ⬜ |
| FR-NTS-NOTE-SEARCH-001 | 3.5 Doyah Notes | 基线必备 | ✅ | — | ⬜ |
| FR-NTS-NOTE-ORG-001 | 3.5 Doyah Notes | 基线必备 | ✅ | — | ⬜ |
| FR-NTS-NOTE-VERSION-001 | 3.5 Doyah Notes | 基线必备 | 🟡 | — | ⬜ |
| FR-NTS-NOTE-TRASH-001 | 3.5 Doyah Notes | 基线必备 | ✅ | — | ⬜ |
| FR-NTS-NOTE-SYNC-001 | 3.5 Doyah Notes | 基线必备 | ✅ | — | ⬜ |
| FR-NTS-NOTE-SYNC-002 | 3.5 Doyah Notes | 基线必备 | 🟡 | — | ⬜ |
| FR-NTS-NOTE-EXPORT-001 | 3.5 Doyah Notes | 基线必备 | ✅ | — | ⬜ |
| FR-NTS-NOTE-PRIVACY-001 | 3.5 Doyah Notes | 基线必备 | ⬜ | — | ⬜ |
| FR-AGT-LINK-CHAN-001 | 3.2 Doyah Agent | 基线必备 | ✅ | — | 🟡 |
| FR-AGT-PLAN-CLAR-001 | 3.2 Doyah Agent | 常用增强 | ⬜ | （追溯表有行、未标路径） | ⬜ |
| FR-AGT-PLAN-PLAN-004 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-GUARD-SOUL-001 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-TOOL-INGEST-001 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-TOOL-INGEST-002 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-TOOL-INGEST-003 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-TOOL-MEDIA-001 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-TOOL-MEDIA-002 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-TOOL-SYS-001 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-TOOL-SYS-002 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-TOOL-MODEL-001 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-TOOL-MODEL-002 | 3.2 Doyah Agent | 常用增强 | ⬜ | `Core/AgentProviderPreset.swift` | ⬜ |
| FR-AGT-UX-CONV-007 | 3.2 Doyah Agent | 常用增强 | ⬜ | `FR-AGT-UX-CONV-004`、`FR-AGT-UX-CONV-005`、`Docs/Doyah产品概要设计说明书.md` 等 8 处 | ⬜ |
| FR-AGT-UX-CONV-008 | 3.2 Doyah Agent | 常用增强 | ⬜ | `FR-AGT-UX-CONV-004`、`FR-AGT-UX-CONV-005`、`Docs/Doyah产品概要设计说明书.md` 等 8 处 | ⬜ |
| FR-AGT-UX-CONV-009 | 3.2 Doyah Agent | 常用增强 | ⬜ | `FR-AGT-UX-CONV-004`、`FR-AGT-UX-CONV-005`、`Docs/Doyah产品概要设计说明书.md` 等 8 处 | ⬜ |
| FR-AGT-GUARD-PERM-003 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-OPS-OBS-001 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-OPS-OBS-002 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-OPS-OBS-003 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-UX-SYNC-001 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-CORE-LOOP-007 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-CORE-LOOP-001 | 3.2 Doyah Agent | 基线必备 | ✅ | — | ⬜ |
| FR-AGT-UX-CONV-001 | 3.2 Doyah Agent | 常用增强 | 🟡 | — | ⬜ |
| FR-AGT-PLAN-PLAN-001 | 3.2 Doyah Agent | 常用增强 | 🟡 | — | ⬜ |
| FR-AGT-PLAN-PLAN-002 | 3.2 Doyah Agent | 基线必备 | ✅ | `Core/DataTask.swift`、`issues`、`dryRun` 等 10 处 | ⬜ |
| FR-AGT-TOOL-SCHED-001 | 3.2 Doyah Agent | 基线必备 | ✅ | `Core/DataTask.swift`、`TaskScheduler`、`TaskRunRecord` 等 11 处 | ⬜ |
| FR-AGT-CORE-LOOP-002 | 3.2 Doyah Agent | 常用增强 | 🟡 | — | ⬜ |
| FR-AGT-CORE-LOOP-003 | 3.2 Doyah Agent | 基线必备 | ✅ | `Core/SecureDirectoryAccess.swift`、`Core/DataTaskRun.swift`、`App/DirectoryPanelPicker.swift` 等 7 处 | ⬜ |
| FR-AGT-GUARD-PERM-001 | 3.2 Doyah Agent | 基线必备 | ✅ | — | 🟡 |
| FR-AGT-LINK-EXT-001 | 3.2 Doyah Agent | 进阶可选 | 🟡 | — | ⬜ |
| FR-AGT-PLAN-PLAN-003 | 3.2 Doyah Agent | 常用增强 | 🟡 | — | ⬜ |
| FR-AGT-GUARD-PERM-004 | 3.2 Doyah Agent | 基线必备 | 🟡 | — | ⬜ |
| FR-AGT-KNOW-MEM-001 | 3.2 Doyah Agent | 常用增强 | ✅ | `Docs/Doyah产品能力规划说明书.md` | ⬜ |
| FR-AGT-KNOW-MEM-004 | 3.2 Doyah Agent | 常用增强 | 🟡 | `Docs/Doyah产品能力规划说明书.md` | ⬜ |
| FR-AGT-KNOW-MEM-002 | 3.2 Doyah Agent | 常用增强 | 🟡 | `Docs/Doyah产品能力规划说明书.md` | ⬜ |
| FR-AGT-LINK-CHAN-002 | 3.2 Doyah Agent | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力规划说明书.md` 等 4 处 | ⬜ |
| FR-AGT-UX-CONV-002 | 3.2 Doyah Agent | 常用增强 | 🟡 | — | ⬜ |
| FR-AGT-CORE-LOOP-004 | 3.2 Doyah Agent | 常用增强 | 🟡 | — | ⬜ |
| FR-AGT-CORE-LOOP-005 | 3.2 Doyah Agent | 常用增强 | ✅ | — | ⬜ |
| FR-AGT-CORE-LOOP-006 | 3.2 Doyah Agent | 常用增强 | 🟡 | — | ⬜ |
| FR-AGT-LINK-EXT-002 | 3.2 Doyah Agent | 进阶可选 | 🟡 | — | ⬜ |
| FR-AGT-CORE-CTX-001 | 3.2 Doyah Agent | 常用增强 | 🟡 | — | ⬜ |
| FR-AGT-GUARD-PERM-002 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-GUARD-SOUL-002 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-UX-CONV-003 | 3.2 Doyah Agent | 常用增强 | 🟡 | — | ⬜ |
| FR-AGT-KNOW-MEM-005 | 3.2 Doyah Agent | 常用增强 | 🟡 | `TaskScheduler`、`FR-AGT-KNOW-MEM-002`、`Docs/Doyah产品概要设计说明书.md` | ⬜ |
| FR-AGT-TOOL-SCHED-002 | 3.2 Doyah Agent | 常用增强 | 🟡 | — | ⬜ |
| FR-AGT-GUARD-COST-001 | 3.2 Doyah Agent | 常用增强 | 🟡 | — | ⬜ |
| FR-AGT-KNOW-MEM-003 | 3.2 Doyah Agent | 常用增强 | 🟡 | `Docs/Doyah产品能力规划说明书.md` | ⬜ |
| FR-AGT-UX-CONV-004 | 3.2 Doyah Agent | 常用增强 | ⬜ | `FR-AGT-UX-CONV-004`、`FR-AGT-UX-CONV-005`、`Docs/Doyah产品概要设计说明书.md` 等 8 处 | ⬜ |
| FR-AGT-UX-CONV-005 | 3.2 Doyah Agent | 常用增强 | 🟡 | `FR-AGT-UX-CONV-004`、`FR-AGT-UX-CONV-005`、`Docs/Doyah产品概要设计说明书.md` 等 8 处 | ⬜ |
| FR-STD-ALL-BLD-001 | 3.1.1 工程与工具链 | 基线必备 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-BLD-002 | 3.1.1 工程与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-BLD-003 | 3.1.1 工程与工具链 | 基线必备 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-BLD-004 | 3.1.1 工程与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-BLD-005 | 3.1.1 工程与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-BLD-006 | 3.1.1 工程与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-BLD-007 | 3.1.1 工程与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-BLD-008 | 3.1.1 工程与工具链 | 进阶可选 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-BLD-009 | 3.1.1 工程与工具链 | 常用增强 | ✅ | `project.yml`、`Scripts/*`、`Package.swift` 等 4 处 | ✅ |
| FR-STD-ALL-CLI-001 | 3.1.4 命令行出口 | 常用增强 | ✅ | `CLI/main.swift` | ✅ |
| FR-STD-ALL-CLI-002 | 3.1.4 命令行出口 | 常用增强 | ✅ | `CLI/main.swift` | ✅ |
| FR-STD-ALL-CLI-003 | 3.1.4 命令行出口 | 常用增强 | ✅ | `CLI/main.swift` | ✅ |
| FR-STD-ALL-CLI-004 | 3.1.4 命令行出口 | 常用增强 | ✅ | `CLI/main.swift` | ✅ |
| FR-STD-ALL-CLI-005 | 3.1.4 命令行出口 | 常用增强 | ✅ | `CLI/main.swift` | ✅ |
| FR-STD-DB-CONN-007 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `App/Views/ConnectionListView.swift`、`ConnectionFormView.swift`、`Core/ConnectionConfig.swift` 等 4 处 | ✅ |
| FR-STD-DB-CONN-001 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `App/Views/ConnectionListView.swift`、`ConnectionFormView.swift`、`Core/ConnectionConfig.swift` 等 4 处 | ✅ |
| FR-STD-DB-CONN-002 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `App/Views/ConnectionListView.swift`、`ConnectionFormView.swift`、`Core/ConnectionConfig.swift` 等 4 处 | ✅ |
| FR-STD-DB-CONN-008 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `App/Views/MainWindow.swift`、`.sheet(item:)`、`ConnectionFormMode` | ✅ |
| FR-STD-DB-CONN-009 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `App/Views/ConnectionListView.swift`、`confirmationDialog`、`AppState.deleteConnection` 等 4 处 | ✅ |
| FR-STD-DB-CONN-003 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `Core/ConnectionConfig.isValid`、`App/Views/ConnectionFormView.swift::isValid` | ✅ |
| FR-STD-DB-CONN-017 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `Core/ConnectionGrouping.swift`、`Core/ConnectionAppearance.swift`、`ExecutionSafety` 等 5 处 | ✅ |
| FR-STD-DB-CONN-018 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/ConnectionGrouping.swift`、`Core/ConnectionAppearance.swift`、`ExecutionSafety` 等 5 处 | ✅ |
| FR-STD-DB-CONN-021 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `ConnectionFormView.testConnection`、`Core/PostgresService.connect` | ✅ |
| FR-STD-DB-CONN-004 | 3.4 Doyah Studio · 数据库 | 进阶可选 | ✅ | `Core/ConnectionConfig.swift` | ✅ |
| FR-STD-DB-CONN-010 | 3.4 Doyah Studio · 数据库 | 进阶可选 | ✅ | `AppState.restoredConnectionID(in:)`、`rememberSelectedConnection()`、`UserDefaults` | ✅ |
| FR-STD-DB-CONN-015 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/ConnectionGrouping.swift`、`Core/ConnectionAppearance.swift`、`ExecutionSafety` 等 5 处 | ✅ |
| FR-STD-DB-CONN-016 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/ConnectionGrouping.swift`、`Core/ConnectionAppearance.swift`、`ExecutionSafety` 等 5 处 | ✅ |
| FR-STD-DB-CONN-011 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/ConnectionConfig.swift::displayTitle(untitled:)`、`App/Views/ConnectionListView.swift`、`QueryContextBar.swift` | ✅ |
| FR-STD-DB-CONN-012 | 3.4 Doyah Studio · 数据库 | 常用增强 | 🟡 | `Core/ConnectionGrouping.swift`、`Core/ConnectionAppearance.swift`、`ExecutionSafety` 等 5 处 | ✅ |
| FR-STD-DB-CONN-013 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/ConnectionGrouping.swift`、`Core/ConnectionAppearance.swift`、`ExecutionSafety` 等 5 处 | ✅ |
| FR-STD-DB-CONN-014 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/ConnectionGrouping.swift`、`Core/ConnectionAppearance.swift`、`ExecutionSafety` 等 5 处 | ✅ |
| FR-STD-DB-CONN-020 | 3.4 Doyah Studio · 数据库 | 常用增强 | 🟡 | `Core/ConnectionGrouping.swift`、`Core/ConnectionAppearance.swift`、`ExecutionSafety` 等 5 处 | ⬜ |
| FR-STD-DB-CONN-005 | 3.4 Doyah Studio · 数据库 | 进阶可选 | ✅ | `App/Views/ConnectionListView.swift`、`ConnectionFormView.swift`、`Core/ConnectionConfig.swift` 等 4 处 | ✅ |
| FR-STD-DB-CONN-006 | 3.4 Doyah Studio · 数据库 | 进阶可选 | ✅ | `Core/KeepAlive.swift` | ✅ |
| FR-STD-DB-DATA-001 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `Core/SQLGenerator.swift` | ✅ |
| FR-STD-DB-DATA-002 | 3.4 Doyah Studio · 数据库 | 常用增强 | 🟡 | `Core/SQLGenerator.swift` | ✅ |
| FR-STD-DB-DATA-003 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/SQLGenerator.swift` | ✅ |
| FR-STD-DB-DATA-004 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | — | ✅ |
| FR-STD-DB-DATA-005 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 🟡 | （追溯表有行、未标路径） | ✅ |
| FR-STD-DB-DATA-006 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 🟡 | — | ✅ |
| FR-STD-DB-DDL-001 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/SQLGenerator.swift` | ✅ |
| FR-STD-DB-DDL-002 | 3.4 Doyah Studio · 数据库 | 进阶可选 | ✅ | `Core/SQLGenerator.swift` | ✅ |
| FR-STD-DB-DDL-003 | 3.4 Doyah Studio · 数据库 | 常用增强 | 🟡 | `Core/TableDesign.swift`、`Core/SQLGenerator.alterTableStatements`、`Core/MetadataService.tableStructure` 等 5 处 | ✅ |
| FR-STD-DB-DDL-004 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 🟡 | （追溯表有行、未标路径） | ✅ |
| FR-STD-DB-DDL-005 | 3.4 Doyah Studio · 数据库 | 进阶可选 | ✅ | （追溯表有行、未标路径） | ✅ |
| FR-STD-DB-DIAG-001 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `Core/ExplainPlan.swift`、`Core/SQLGenerator.swift::explain`、`Core/Dialects.swift` | ✅ |
| FR-STD-DB-DIAG-002 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/ExplainPlan.swift`、`Core/SQLGenerator.swift::explain`、`Core/Dialects.swift` | ✅ |
| FR-STD-DB-DIAG-003 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 🟡 | `pg_stat_statements` | 🟡 |
| FR-STD-DB-DIAG-004 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 🟡 | `pg_stat_statements` | ✅ |
| FR-STD-DB-DIAG-005 | 3.4 Doyah Studio · 数据库 | 进阶可选 | ✅ | — | ✅ |
| FR-STD-DB-DRV-005 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ✅ |
| FR-STD-DB-DRV-006 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ✅ |
| FR-STD-DB-DRV-007 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `Core/DatabaseService.swift`、`PostgresService.swift`、`Dialects.swift` 等 4 处 | ✅ |
| FR-STD-DB-DRV-008 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | — | ✅ |
| FR-STD-DB-DRV-001 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | — | ✅ |
| FR-STD-DB-DRV-002 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | — | ✅ |
| FR-STD-DB-DRV-003 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | — | ✅ |
| FR-STD-DB-DRV-009 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 🟡 | `Core/Dialects.swift::GBaseDialect`、`Core/StatementSplitter.swift`、`DELIMITER` | ✅ |
| FR-STD-DB-DRV-010 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `MySQLService`、`MySQLDialect`、`DatabaseType.mysql` | 🟡 |
| FR-STD-WS-UI-001 | 3.3 Doyah Studio · 工作区 | 基线必备 | ✅ | `AppState.tabs`、`App/Views/QueryWorkspaceView.swift`、`DoyahStudioApp.swift` | ✅ |
| FR-STD-WS-VCS-001 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | （追溯表有行、未标路径） | ⬜ |
| FR-STD-WS-TOOL-003 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | — | ⬜ |
| FR-STD-WS-AI-002 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | — | ⬜ |
| FR-STD-WS-EDIT-015 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-STD-WS-FS-009 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | — | ⬜ |
| FR-STD-WS-FS-010 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | — | ⬜ |
| FR-STD-WS-WEB-003 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | — | ⬜ |
| FR-STD-WS-WEB-004 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | — | ⬜ |
| FR-STD-WS-NAV-001 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | `Core/SQLTokenizer.swift`、`App/Views/SQLEditorView.swift` | ✅ |
| FR-STD-WS-NAV-007 | 3.3 Doyah Studio · 工作区 | 基线必备 | ✅ | `AppState.checkSyntax`、`QueryEditorView` | ✅ |
| FR-STD-WS-NAV-008 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | `AppState.checkSyntax`、`QueryEditorView` | ✅ |
| FR-STD-WS-NAV-009 | 3.3 Doyah Studio · 工作区 | 基线必备 | ✅ | `AppState.checkSyntax`、`QueryEditorView` | ✅ |
| FR-STD-WS-NAV-010 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | — | ✅ |
| FR-STD-WS-NAV-011 | 3.3 Doyah Studio · 工作区 | 进阶可选 | ✅ | — | ✅ |
| FR-STD-DB-EXEC-014 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `App/Views/QueryToolbar.swift` | ✅ |
| FR-STD-WS-NAV-003 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | `App/Utilities/SQLCompleter.swift`、`App/Views/SQLEditorView.swift`、`textView(_:completions:forPartialWordRange:indexOfSelectedItem:)` 等 4 处 | ✅ |
| FR-STD-DB-SESS-001 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/ConnectionConfig.swift::QueryHistory`、`AppState.queryHistory`、`recordHistory` 等 5 处 | ✅ |
| FR-STD-DB-CONN-019 | 3.4 Doyah Studio · 数据库 | 进阶可选 | ✅ | `Core/ConnectionGrouping.swift`、`Core/ConnectionAppearance.swift`、`ExecutionSafety` 等 5 处 | ✅ |
| FR-STD-WS-EDIT-024 | 3.3 Doyah Studio · 工作区 | 进阶可选 | ✅ | `QueryEditorView.diagnostics` | ✅ |
| FR-STD-WS-UI-007 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | （追溯表有行、未标路径） | ⬜ |
| FR-STD-WS-EDIT-001 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | `App/Views/QueryToolbar.swift`、`App/Views/SaveQuerySheet.swift`、`Core/SavedQueryStore.swift` 等 4 处 | ⬜ |
| FR-STD-WS-FS-007 | 3.3 Doyah Studio · 工作区 | 基线必备 | ✅ | `App/AppState.swift::openFileFromPanel / openFile`、`App/Views/QueryToolbar.swift`、`App/Views/QueryWorkspaceView.swift` | ✅ |
| FR-STD-WS-EDIT-002 | 3.3 Doyah Studio · 工作区 | 基线必备 | ✅ | `AppState.saveCurrentFile / writeFile`、`QueryToolbar`、`Menu(primaryAction:)` | ✅ |
| FR-STD-WS-EDIT-003 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-STD-WS-EDIT-010 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ✅ |
| FR-STD-WS-EDIT-011 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-STD-WS-EDIT-018 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-STD-WS-EDIT-004 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ✅ |
| FR-STD-WS-NAV-013 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | — | ✅ |
| FR-STD-WS-HELP-001 | 3.3 Doyah Studio · 工作区 | 进阶可选 | ✅ | `App/Views/QueryToolbar.swift::helpButton` | ✅ |
| FR-STD-WS-UI-002 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | `Core/TabNumberGenerator.swift`、`AppState.tabNumbers` | ✅ |
| FR-STD-WS-UI-005 | 3.3 Doyah Studio · 工作区 | 常用增强 | 🟡 | （追溯表有行、未标路径） | ✅ |
| FR-STD-WS-UI-008 | 3.3 Doyah Studio · 工作区 | 进阶可选 | 🟡 | （追溯表有行、未标路径） | ⬜ |
| FR-STD-WS-EDIT-016 | 3.3 Doyah Studio · 工作区 | 进阶可选 | 🟡 | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-STD-WS-EDIT-005 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | `App/ShortcutCatalog.swift`、`App/Views/QueryToolbar.swift` | ✅ |
| FR-STD-WS-TOOL-001 | 3.3 Doyah Studio · 工作区 | 常用增强 | 🟡 | `Core/TerminalTabs.swift`、`TerminalTabTitle`、`TerminalTab` 等 16 处 | ✅ |
| FR-STD-WS-TOOL-002 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | `Core/LowerPaneTab.swift`、`Core/TabLog.swift`、`App/Views/LowerPaneView.swift` | ✅ |
| FR-STD-DB-EXEC-001 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | `Core/SQLArchive.swift`、`Core/SQLArchiveStore.swift`、`App/AppState.swift` 等 5 处 | ⬜ |
| FR-STD-WS-FS-002 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | `Docs/design/外观方案-v1.md` | ✅ |
| FR-STD-WS-UI-009 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | `Core/AccentTheme.swift`、`App/AccentManager.swift`、`.tint` 等 12 处 | ✅ |
| FR-STD-WS-UI-010 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | （追溯表有行、未标路径） | ⬜ |
| FR-STD-WS-UI-011 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | （追溯表有行、未标路径） | ⬜ |
| FR-STD-WS-WEB-001 | 3.3 Doyah Studio · 工作区 | 常用增强 | 🟡 | — | ⬜ |
| FR-STD-WS-FS-001 | 3.3 Doyah Studio · 工作区 | 常用增强 | 🟡 | `Core/WorkspaceTab.swift`、`Core/WorkspaceHistory.swift`、`Core/WorkspaceHistoryStore.swift` 等 7 处 | ✅ |
| FR-STD-WS-FS-008 | 3.3 Doyah Studio · 工作区 | 常用增强 | 🟡 | `Core/TextLanguage.swift`、`Core/CodeSyntax.swift`、`Core/CodeLexer.swift` 等 7 处 | ✅ |
| FR-STD-WS-UI-006 | 3.3 Doyah Studio · 工作区 | 常用增强 | 🟡 | `Core/ActivityBar.swift`、`WindowTitle`、`Core/Localization.swift` 等 23 处 | ✅ |
| FR-STD-WS-NAV-002 | 3.3 Doyah Studio · 工作区 | 常用增强 | 🟡 | `Core/CodeLanguageDefinitions.swift`、`detect`、`TextLanguage` 等 21 处 | ✅ |
| FR-STD-WS-NAV-014 | 3.3 Doyah Studio · 工作区 | 常用增强 | 🟡 | `Core/CodeFormatting.swift`、`CodeFormatProcessRunning`、`Core/CodeLanguageDefinitions.swift` 等 10 处 | ✅ |
| FR-STD-WS-AI-001 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | `Core/AIAssist.swift`、`App/Views/AIAssistPanel.swift`、`Core/ModelEndpoint.swift` | ⬜ |
| FR-STD-WS-FS-003 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | `Core/WorkspaceTree.swift`、`App/Views/WorkspaceExplorerView.swift` | ✅ |
| FR-STD-WS-EDIT-012 | 3.3 Doyah Studio · 工作区 | 常用增强 | ✅ | `Core/WorkspaceSearch.swift`、`App/Views/WorkspaceSearchPanel.swift` | ✅ |
| FR-STD-WS-UI-004 | 3.3 Doyah Studio · 工作区 | 常用增强 | 🟡 | `Core/WorkspaceSession.swift`、`App/WorkspaceTabsModel.swift` | ✅ |
| FR-STD-WS-EDIT-013 | 3.3 Doyah Studio · 工作区 | 常用增强 | 🟡 | `Core/WorkspaceSearch.swift`、`FR-STD-WS-EDIT-012`、`App/Views/WorkspaceHeaderSearch.swift` | ✅ |
| FR-STD-WS-WEB-002 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | `Core/`、`App/Views/MarkdownPreview.swift`、`Core/MarkdownDocument.swift` 等 10 处 | ✅ |
| FR-STD-WS-UI-003 | 3.3 Doyah Studio · 工作区 | 常用增强 | 🟡 | `Core/WorkspaceClose.swift`、`App/WorkspaceTabsModel.swift`、`requestClose` 等 8 处 | ✅ |
| FR-STD-WS-EDIT-006 | 3.3 Doyah Studio · 工作区 | 常用增强 | 🟡 | `Core/MarkdownEditing.swift`、`MarkdownListEditing.continuation`、`App/Views/CodeEditorView.swift` 等 7 处 | ⬜ |
| FR-STD-WS-EDIT-007 | 3.3 Doyah Studio · 工作区 | 常用增强 | 🟡 | `Core/MarkdownEditing.swift`、`toggleTask`、`App/Views/CodeEditorView.swift::performKeyEquivalent` | ⬜ |
| FR-STD-WS-EDIT-019 | 3.3 Doyah Studio · 工作区 | 常用增强 | 🟡 | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-STD-WS-EDIT-020 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-STD-WS-EDIT-008 | 3.3 Doyah Studio · 工作区 | 常用增强 | 🟡 | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-STD-WS-EDIT-009 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-STD-WS-EDIT-021 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-STD-WS-EDIT-022 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-STD-WS-EDIT-017 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-STD-WS-NAV-012 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | — | ⬜ |
| FR-STD-WS-NAV-004 | 3.3 Doyah Studio · 工作区 | 常用增强 | 🟡 | `Core/SQLLinter.swift`、`QueryEditorView.diagnosticsBar` | ⬜ |
| FR-STD-WS-NAV-006 | 3.3 Doyah Studio · 工作区 | 进阶可选 | ⬜ | `Core/SQLLinter.swift`、`QueryEditorView.diagnosticsBar` | ⬜ |
| FR-STD-WS-NAV-005 | 3.3 Doyah Studio · 工作区 | 进阶可选 | ⬜ | `Core/SQLLinter.swift`、`QueryEditorView.diagnosticsBar` | ⬜ |
| FR-STD-WS-EDIT-014 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | `App/EditorCommandCenter.swift`、`App/Views/QueryToolbar.swift`、`App/Views/SQLEditorView.swift` 等 5 处 | ⬜ |
| FR-STD-DB-EXEC-002 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `App/AppState.swift::executeQuery`、`Core/PostgresService.swift::performExecute`、`StatementSplitter.swift` | ✅ |
| FR-STD-DB-DRV-004 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | — | ✅ |
| FR-STD-DB-EXEC-003 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `App/AppState.swift::executeQuery`、`Core/PostgresService.swift::performExecute`、`StatementSplitter.swift` | ✅ |
| FR-STD-DB-EXEC-009 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `QueryTab.results`、`App/Views/ResultTableView.swift`、`ResultGrid.swift` | ✅ |
| FR-STD-DB-EXEC-010 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | — | ✅ |
| FR-STD-DB-EXEC-011 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `AppState`、`closeTab` | ✅ |
| FR-STD-DB-EXEC-012 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `AppState`、`closeTab` | ✅ |
| FR-STD-DB-EXEC-018 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `PostgresService.cancel()`、`pg_cancel_backend`、`AppState.cancelQuery` 等 4 处 | ✅ |
| FR-STD-DB-EXEC-004 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `AppState.ensureService`、`connectTasks` | ✅ |
| FR-STD-DB-EXEC-013 | 3.4 Doyah Studio · 数据库 | 进阶可选 | ✅ | `PostgresService.reportsAffectedRows(_:)`、`PostgresQueryMetadata.rows`、`QueryResult.affectedRows` | ✅ |
| FR-STD-DB-EXEC-015 | 3.4 Doyah Studio · 数据库 | 进阶可选 | ✅ | `Core/DatabaseService.swift`、`PostgresService.begin/commit/rollback` | ✅ |
| FR-STD-DB-EXEC-005 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `AppState.executeQuery` | ✅ |
| FR-STD-DB-EXEC-016 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `App/Views/QueryToolbar.swift`、`QueryEditorView`、`AppState.startQuery/cancelQuery` | ✅ |
| FR-STD-DB-EXEC-006 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `Core/ExecutionScope.swift`、`AppState.executeQuery`、`App/ExecutionScopeTitle.swift` 等 5 处 | ✅ |
| FR-STD-DB-EXEC-007 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/TransactionSession.swift`、`App/Views/TransactionControl.swift`、`AppState.executeQuery` | ✅ |
| FR-STD-DB-EXEC-017 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `Core/ExecutionSafety.swift`、`AppState.executeQuery`、`App/Views/SafeModeConfirmSheet.swift` 等 4 处 | ✅ |
| FR-STD-DB-EXEC-008 | 3.4 Doyah Studio · 数据库 | 进阶可选 | ✅ | `Core/SQLParameters.swift`、`App/Views/QueryParameterSheet.swift`、`AppState.executeQuery` 等 4 处 | ✅ |
| FR-STD-DB-IO-001 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | （追溯表有行、未标路径） | ✅ |
| FR-STD-DB-IO-002 | 3.4 Doyah Studio · 数据库 | 常用增强 | 🟡 | `COPY … TO / FROM STDIN` | 🟡 |
| FR-STD-DB-IO-006 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 🟡 | — | ✅ |
| FR-STD-DB-IO-003 | 3.4 Doyah Studio · 数据库 | 常用增强 | 🟡 | `COPY … TO / FROM STDIN` | ✅ |
| FR-STD-DB-IO-004 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 🟡 | `COPY … TO / FROM STDIN` | 🟡 |
| FR-STD-DB-IO-007 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 🟡 | `Core/XLSXReader.swift`、`Core/Inflate.swift`、`CLI/main.swift` 等 5 处 | ✅ |
| FR-STD-DB-IO-005 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/ResultExportEncoding.swift`、`Core/TextFileDecoder.swift`、`Core/ResultExporter.swift` 等 11 处 | ✅ |
| FR-STD-DB-META-001 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-STD-DB-META-002 | 3.4 Doyah Studio · 数据库 | 常用增强 | 🟡 | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ⬜ |
| FR-STD-DB-META-003 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-STD-DB-META-004 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-STD-DB-META-009 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | — | ✅ |
| FR-STD-DB-META-005 | 3.4 Doyah Studio · 数据库 | 进阶可选 | ✅ | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-STD-DB-META-013 | 3.4 Doyah Studio · 数据库 | 进阶可选 | ✅ | `Core/ObjectTreeActions.swift`、`App/Views/ObjectTreeView.swift`、`AppState.performTreeAction` | ✅ |
| FR-STD-DB-META-014 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/ObjectTreeActions.swift`、`App/Views/ObjectTreeView.swift`、`AppState.performTreeAction` | ✅ |
| FR-STD-DB-META-006 | 3.4 Doyah Studio · 数据库 | 基线必备 | 🟡 | `App/Views/ObjectTreeView.swift`、`Core/MetadataService.swift` | ✅ |
| FR-STD-DB-META-007 | 3.4 Doyah Studio · 数据库 | 基线必备 | 🟡 | `Core/MetadataService.swift`、`App/AppState.swift`、`CLI/main.swift` | 🟡 |
| FR-STD-DB-META-010 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/Dialects.swift::databaseCreationPrivilegeQuery()`、`Core/PrivilegeProbe.swift`、`App/AppState.swift` 等 6 处 | ✅ |
| FR-STD-DB-META-015 | 3.4 Doyah Studio · 数据库 | 常用增强 | 🟡 | `Core/SQLGenerator.swift` | ✅ |
| FR-STD-DB-META-011 | 3.4 Doyah Studio · 数据库 | 常用增强 | 🟡 | `Core/ObjectTreeActions.swift`、`App/Views/ObjectTreeView.swift`、`AppState.performTreeAction` | ✅ |
| FR-STD-DB-META-012 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `Core/ObjectTreeActions.swift`、`App/Views/ObjectTreeView.swift`、`AppState.performTreeAction` | ✅ |
| FR-STD-DB-META-008 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 🟡 | `Core/MetadataService.swift`、`Core/Dialects.swift`、`App/Views/ObjectTreeView.swift` | ✅ |
| FR-STD-ALL-PLUG-001 | 3.1.3 插件装配 | 基线必备 | ✅ | `Core/Note*.swift`、`AICapture*.swift`、`App/Views/NotesPanel.swift` | ✅ |
| FR-STD-ALL-PLUG-002 | 3.1.3 插件装配 | 基线必备 | ✅ | `Core/ActivityBar.swift`、`case notes`、`Core/LicensePresentation.swift` 等 4 处 | ✅ |
| FR-STD-ALL-PLUG-003 | 3.1.3 插件装配 | 基线必备 | ✅ | `Core/AICapture.swift`、`Core/Note.swift`、`NoteDraft` 等 5 处 | ✅ |
| FR-STD-ALL-PLUG-004 | 3.1.3 插件装配 | 常用增强 | ✅ | `Core/Note.swift`、`NoteStore.defaultFileURL`、`legacyFileURL` 等 11 处 | ✅ |
| FR-STD-ALL-PLUG-005 | 3.1.3 插件装配 | 基线必备 | 🟡 | `linux/`、`Scripts/check-notes-offline.py`、`Scripts/notes-offline-gate.json` 等 4 处 | ⬜ |
| FR-STD-ALL-PLUG-006 | 3.1.3 插件装配 | 基线必备 | ✅ | `Core/License.swift`、`LicenseCapabilities.all` | ✅ |
| FR-STD-ALL-PLUG-007 | 3.1.3 插件装配 | 基线必备 | ✅ | `Scripts/check-note-module-isolation.py` | ✅ |
| FR-STD-ALL-PLUG-008 | 3.1.3 插件装配 | 基线必备 | 🟡 | `Core/NoteStorage/`、`SQLiteKit`、`NoteDatabase` 等 9 处 | ✅ |
| FR-STD-DB-RES-001 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `App/Views/ResultGrid.swift`、`ResultTableView.swift`、`Core/PostgresCellFormatter.swift` | ✅ |
| FR-STD-DB-RES-002 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `App/Views/ResultGrid.swift`、`ResultTableView.swift`、`Core/PostgresCellFormatter.swift` | ✅ |
| FR-STD-DB-RES-003 | 3.4 Doyah Studio · 数据库 | 基线必备 | ✅ | `App/Views/ResultGrid.swift`、`ResultTableView.swift`、`Core/PostgresCellFormatter.swift` | ✅ |
| FR-STD-DB-RES-004 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `App/Views/ResultGrid.swift`、`ResultTableView.swift`、`Core/PostgresCellFormatter.swift` | ✅ |
| FR-STD-DB-RES-005 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `App/Views/ResultGrid.swift`、`ResultTableView.swift`、`Core/PostgresCellFormatter.swift` | ✅ |
| FR-STD-DB-RES-010 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/ResultView.swift` | ✅ |
| FR-STD-DB-RES-011 | 3.4 Doyah Studio · 数据库 | 常用增强 | 🟡 | （追溯表有行、未标路径） | ✅ |
| FR-STD-DB-RES-007 | 3.4 Doyah Studio · 数据库 | 常用增强 | 🟡 | `Core/ResultView.swift` | ✅ |
| FR-STD-DB-RES-008 | 3.4 Doyah Studio · 数据库 | 常用增强 | 🟡 | `Core/ResultView.swift` | ✅ |
| FR-STD-DB-RES-009 | 3.4 Doyah Studio · 数据库 | 常用增强 | 🟡 | `Core/ResultView.swift` | ✅ |
| FR-STD-DB-RES-012 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | `Core/ResultExporter.swift`、`App/Views/ResultTableView.swift`、`AppState.exportResult` | ✅ |
| FR-STD-DB-RES-006 | 3.4 Doyah Studio · 数据库 | 常用增强 | 🟡 | （追溯表有行、未标路径） | ✅ |
| FR-STD-DB-RES-013 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 🟡 | `Core/ResultStreamWriter.swift`、`Core/ResultExporter.swift` | ✅ |
| FR-STD-DB-RES-014 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 🟡 | — | ✅ |
| FR-STD-DB-SESS-002 | 3.4 Doyah Studio · 数据库 | 常用增强 | 🟡 | `Core/SessionMonitor.swift`、`Core/Dialects.swift`、`serverActivityQuery` 等 5 处 | ✅ |
| FR-STD-DB-SESS-003 | 3.4 Doyah Studio · 数据库 | 常用增强 | 🟡 | — | ✅ |
| FR-STD-DB-SESS-004 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 🟡 | （追溯表有行、未标路径） | ⬜ |
| FR-STD-DB-SESS-005 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | — | ✅ |
| FR-STD-DB-SESS-006 | 3.4 Doyah Studio · 数据库 | 常用增强 | ✅ | — | ✅ |
| FR-RTR-MKT-FEED-001 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-REV-TRADE-001 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-MKT-FEED-002 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-MKT-FEED-004 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-MKT-FEED-005 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-MKT-STORE-001 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-MKT-FEED-003 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-RSR-PROFILE-001 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-RSR-PROFILE-002 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-RSR-PROFILE-003 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-RSR-REPORT-001 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-REPORT-002 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-SCENARIO-001 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-SCENARIO-002 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-FLOW-CRON-001 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-FLOW-CRON-002 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-REV-ATTR-001 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-REV-ATTR-002 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-REV-ATTR-003 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-REV-QUERY-001 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-REV-QUERY-002 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-MKT-HEALTH-001 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-MKT-HEALTH-002 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-SCENARIO-003 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-RSR-SCENARIO-004 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-REV-QUERY-003 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-RSR-SCENARIO-005 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-REV-ATTR-004 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-REV-ATTR-005 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-REV-ATTR-006 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-REV-ATTR-007 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-REV-ATTR-008 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-REV-ATTR-009 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-REV-TRADE-002 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-REV-TRADE-003 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-REV-QUERY-004 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-REV-QUERY-005 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-REV-QUERY-006 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-REV-QUERY-007 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-REV-QUERY-008 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-FLOW-CRON-003 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-REPORT-003 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-REPORT-004 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-REPORT-005 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-REPORT-006 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-REPORT-007 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-REPORT-008 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-REV-QUERY-009 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-REPORT-009 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-FLOW-CRON-004 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-BACKTEST-001 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-BACKTEST-002 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-BACKTEST-003 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-BACKTEST-004 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-BACKTEST-005 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-BACKTEST-006 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-SAMPLE-001 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-MKT-FUND-001 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-MKT-FUND-002 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-MKT-FUND-003 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-MKT-FUND-004 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-BACKTEST-007 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-BACKTEST-008 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-SAMPLE-002 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-SAMPLE-003 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-SAMPLE-004 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-BACKTEST-009 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-RSR-SAMPLE-005 | 3.6 Doyah Retro | 常用增强 | ⬜ | — | ⬜ |
| FR-RTR-MKT-STORE-002 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-REV-TRADE-004 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-MKT-STORE-003 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-REV-TRADE-005 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-MKT-STORE-004 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-RTR-REV-TRADE-006 | 3.6 Doyah Retro | 基线必备 | ⬜ | — | ⬜ |
| FR-STD-ALL-LIC-001 | 3.1.2 授权与版本 | 基线必备 | 🟡 | — | ⬜ |
| FR-STD-ALL-LIC-002 | 3.1.2 授权与版本 | 基线必备 | 🟡 | — | ⬜ |
| FR-STD-ALL-LIC-003 | 3.1.2 授权与版本 | 基线必备 | 🟡 | — | ⬜ |
| FR-STD-ALL-LIC-004 | 3.1.2 授权与版本 | 基线必备 | 🟡 | — | ⬜ |
| FR-STD-ALL-LIC-005 | 3.1.2 授权与版本 | 常用增强 | 🟡 | — | ⬜ |
| FR-AGT-CORE-SESS-001 | 3.2 Doyah Agent | 常用增强 | ✅ | — | ⬜ |
| FR-AGT-CORE-LOOP-008 | 3.2 Doyah Agent | 常用增强 | ✅ | — | ⬜ |
| FR-AGT-CORE-LOOP-009 | 3.2 Doyah Agent | 基线必备 | ✅ | — | ⬜ |
| FR-AGT-PLAN-PLAN-005 | 3.2 Doyah Agent | 基线必备 | ✅ | — | ⬜ |
| FR-AGT-PLAN-PLAN-006 | 3.2 Doyah Agent | 基线必备 | ✅ | — | ⬜ |
| FR-AGT-KNOW-CTX-001 | 3.2 Doyah Agent | 常用增强 | ✅ | — | ⬜ |
| FR-AGT-KNOW-CTX-002 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-TOOL-EDIT-001 | 3.2 Doyah Agent | 基线必备 | ⬜ | — | ⬜ |
| FR-AGT-LINK-CHAN-003 | 3.2 Doyah Agent | 常用增强 | ⬜ | `tools`、`doyah-dispatch/docs/AI助手对话能力-调研-20261010.md`、`Docs/Doyah产品能力规划说明书.md` 等 4 处 | ⬜ |
| FR-AGT-LINK-EXT-003 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-UX-CONV-006 | 3.2 Doyah Agent | 基线必备 | ⬜ | `FR-AGT-UX-CONV-004`、`FR-AGT-UX-CONV-005`、`Docs/Doyah产品概要设计说明书.md` 等 8 处 | ⬜ |
| FR-AGT-UX-SESS-001 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-QUAL-VERIFY-001 | 3.2 Doyah Agent | 基线必备 | ✅ | — | ⬜ |
| FR-AGT-QUAL-VERIFY-002 | 3.2 Doyah Agent | 常用增强 | ⬜ | — | ⬜ |
| FR-AGT-QUAL-VERIFY-003 | 3.2 Doyah Agent | 基线必备 | ⬜ | — | ⬜ |
| FR-AGT-QUAL-VERIFY-004 | 3.2 Doyah Agent | 基线必备 | ⬜ | — | ⬜ |
| FR-STD-WS-FS-004 | 3.3 Doyah Studio · 工作区 | 基线必备 | ⬜ | — | ⬜ |
| FR-STD-WS-FS-005 | 3.3 Doyah Studio · 工作区 | 基线必备 | ⬜ | — | ⬜ |
| FR-STD-WS-FS-006 | 3.3 Doyah Studio · 工作区 | 基线必备 | ⬜ | — | ⬜ |
| FR-STD-WS-EDIT-023 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | — | ⬜ |
| FR-STD-WS-VCS-002 | 3.3 Doyah Studio · 工作区 | 常用增强 | ⬜ | （追溯表有行、未标路径） | ⬜ |
| FR-STD-WS-LIC-001 | 3.1.2 授权与版本 | 基线必备 | ⬜ | — | ⬜ |
| FR-STD-DB-DIAG-006 | 3.4 Doyah Studio · 数据库 | 常用增强 | ⬜ | — | ⬜ |
| FR-STD-DB-TASK-001 | 3.4 Doyah Studio · 数据库 | 常用增强 | ⬜ | — | ⬜ |
| FR-STD-DB-TASK-002 | 3.4 Doyah Studio · 数据库 | 基线必备 | ⬜ | — | ⬜ |
| FR-STD-DB-TASK-003 | 3.4 Doyah Studio · 数据库 | 基线必备 | ⬜ | — | ⬜ |
| FR-NTS-TODO-LIST-001 | 3.5 Doyah Notes | 基线必备 | 🟡 | — | ⬜ |
| FR-NTS-TODO-LIST-002 | 3.5 Doyah Notes | 基线必备 | 🟡 | — | ⬜ |
| FR-NTS-TODO-LIST-003 | 3.5 Doyah Notes | 常用增强 | 🟡 | — | ⬜ |
| FR-NTS-TODO-CALENDAR-001 | 3.5 Doyah Notes | 常用增强 | 🟡 | — | ⬜ |
| FR-NTS-TODO-CALENDAR-002 | 3.5 Doyah Notes | 常用增强 | 🟡 | — | ⬜ |
| FR-NTS-TODO-STATE-001 | 3.5 Doyah Notes | 基线必备 | 🟡 | — | ⬜ |
| FR-NTS-TODO-STATE-002 | 3.5 Doyah Notes | 基线必备 | 🟡 | — | ⬜ |
| FR-NTS-TODO-LINK-001 | 3.5 Doyah Notes | 常用增强 | 🟡 | — | ⬜ |
