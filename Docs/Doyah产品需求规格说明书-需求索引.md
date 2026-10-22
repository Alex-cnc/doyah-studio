# 《Doyah 产品需求规格说明书》需求编号索引

> 这份文件是**需求编号的总账**：正文每一条 `FR-*` / `NFR-*` / `AC-*` 在这里有一行，与正文一一对应。
> 2026-10-20 从正文附录（原 §9.1）整体移出 —— 它是**机械派生件**（410 行），不是需求本身，留在正文占 25%。
>
> **收录范围**：本索引只收 **`FR` / `NFR` / `AC`** 三类（共 438 条）；**数据需求 `FR-STD-ALL-DATA-001~04`** 见正文 §5、**接口需求 `FR-STD-ALL-IFACE-001~13`** 见正文 §6 —— 它们不在这里，不是漏登。
>
> **怎么用**：查编号 → 这里找域与层次 → 回正文该域看条文。**改条文必改这里**（`Scripts/check-plan-coverage.py` 与 `check-doc-tables.py` 会钉死「索引 ↔ 正文 ↔ 计划书台账」三边集合相等）。

## 需求编号索引

共 **438** 条（FR 379 · NFR 47 · AC 12）；编号规则见 §1.5。本索引由需求定义行自动生成，与正文一一对应。 <!-- contract-change：契约侧（前门 `bluewhale`）2026-10-11 落笔 —— **工作区对话式助手**：§3.2 新增 `FR-AGT-LINK-CHAN-002` ~ `FR-AGT-UX-CONV-003`（人类主人 2026-10-10 令 + 同日更正「我不想搞成侧栏，而是在 Home 那边新开一个 tab，直接占据工作区主要区域」）⇒ §9.1 索引跟登 10 行、合计 **244 → 254** 条（FR **188 → 198**），十条状态一律 ⬜（只登记、未开工）；**同日增补 `NFR-ALL-GATE-AI-007`**（调研件 §7 · 前门裁「加」）⇒ 合计 **254 → 255** 条（NFR **44 → 45**）；**§8.y 新增里程碑 `M-AI-4`**；条文为新增，未改既有条目；调研件 = `doyah-dispatch/docs/AI助手对话能力-调研-20261010.md` --> <!-- contract-change：契约侧落笔（2026-10-11 · 前门 `bluewhale` · 人类主人令「台账归台账，契约归契约」）—— 本批新增 `FR-AGT-KNOW-MEM-005` ~ `FR-AGT-KNOW-MEM-003`（AI 助手 M2），索引跟登 4 行：合计 **255 → 259** 条（FR **198 → 202**），四条状态一律 ⬜；条文为新增、未改既有条目 --> <!-- contract-change：契约所有者 `bluewhale` 2026-10-12 落笔（人类主人 2026-10-12 令「Demo 到生产 Agent……」+ 回答「你现在就是鲸鱼娘，负责三书维护，当然可以直接进三书」）—— **本批新增 `FR-AGT-UX-CONV-004` / `FR-AGT-UX-CONV-005` / `NFR-ALL-GATE-AI-008` 三条**（回边三件 / 回边四件 / 检查点与压缩；状态一律 ⬜），索引跟登 3 行：合计 **259 → 262** 条（FR **202 → 204**、NFR **45 → 46**，AC 12 不变）；**`G1` / `G6` 两处「拟」号由本批兑现**（`FR-AGT-UX-CONV-004` / `NFR-ALL-GATE-AI-008`），`FR-AGT-LINK-CHAN-002` ~ `29` 那条对话式助手线**一字未动** -->

| 编号 | 所属域 / 章节 | 层次 |
| --- | --- | --- |
| FR-RTR-MKT-HEALTH-003 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-FLOW-ORCH-001 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-FLOW-MARKET-001 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-REV-AI-001 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-FEATURE-001 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-SCREEN-001 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-SAMPLE-006 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-SCENARIO-006 | 3.6 Doyah Retro | 常用增强 |
| FR-NTS-NOTE-CAPTURE-001 | 3.5 Doyah Notes | 基线必备 |
| FR-NTS-NOTE-FORMAT-001 | 3.5 Doyah Notes | 基线必备 |
| FR-NTS-NOTE-ATTACH-001 | 3.5 Doyah Notes | 基线必备 |
| FR-NTS-NOTE-SEARCH-001 | 3.5 Doyah Notes | 基线必备 |
| FR-NTS-NOTE-ORG-001 | 3.5 Doyah Notes | 基线必备 |
| FR-NTS-NOTE-VERSION-001 | 3.5 Doyah Notes | 基线必备 |
| FR-NTS-NOTE-TRASH-001 | 3.5 Doyah Notes | 基线必备 |
| FR-NTS-NOTE-SYNC-001 | 3.5 Doyah Notes | 基线必备 |
| FR-NTS-NOTE-SYNC-002 | 3.5 Doyah Notes | 基线必备 |
| FR-NTS-NOTE-EXPORT-001 | 3.5 Doyah Notes | 基线必备 |
| FR-NTS-NOTE-PRIVACY-001 | 3.5 Doyah Notes | 基线必备 |
| AC-ALL-GATE-AI-01 | 7.4 智能体验收 | — |
| AC-ALL-GATE-AI-02 | 7.4 智能体验收 | — |
| AC-ALL-GATE-AI-03 | 7.4 智能体验收 | — |
| AC-ALL-GATE-AI-04 | 7.4 智能体验收 | — |
| AC-ALL-GATE-REL-01 | 7.1 发布门槛 | — |
| AC-ALL-GATE-REL-02 | 7.1 发布门槛 | — |
| AC-ALL-GATE-REL-03 | 7.1 发布门槛 | — |
| AC-ALL-GATE-REL-04 | 7.1 发布门槛 | — |
| AC-ALL-GATE-REL-05 | 7.1 发布门槛 | — |
| AC-ALL-GATE-REL-06 | 7.1 发布门槛 | — |
| AC-ALL-GATE-REL-07 | 7.1 发布门槛 | — |
| AC-ALL-GATE-REL-08 | 7.1 发布门槛 | — |
| FR-AGT-LINK-CHAN-001 | 3.2 Doyah Agent | 基线必备 |
| FR-AGT-PLAN-CLAR-001 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-PLAN-PLAN-004 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-GUARD-SOUL-001 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-TOOL-INGEST-001 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-TOOL-INGEST-002 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-TOOL-INGEST-003 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-TOOL-MEDIA-001 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-TOOL-MEDIA-002 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-TOOL-SYS-001 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-TOOL-SYS-002 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-TOOL-MODEL-001 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-TOOL-MODEL-002 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-UX-CONV-007 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-UX-CONV-008 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-UX-CONV-009 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-GUARD-PERM-003 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-OPS-OBS-001 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-OPS-OBS-002 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-OPS-OBS-003 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-UX-SYNC-001 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-CORE-LOOP-007 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-CORE-LOOP-001 | 3.2 Doyah Agent | 基线必备 |
| FR-AGT-UX-CONV-001 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-PLAN-PLAN-001 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-PLAN-PLAN-002 | 3.2 Doyah Agent | 基线必备 |
| FR-AGT-TOOL-SCHED-001 | 3.2 Doyah Agent | 基线必备 |
| FR-AGT-CORE-LOOP-002 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-CORE-LOOP-003 | 3.2 Doyah Agent | 基线必备 |
| FR-AGT-GUARD-PERM-001 | 3.2 Doyah Agent | 基线必备 |
| FR-AGT-LINK-EXT-001 | 3.2 Doyah Agent | 进阶可选 |
| FR-AGT-PLAN-PLAN-003 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-GUARD-PERM-004 | 3.2 Doyah Agent | 基线必备 |
| FR-AGT-KNOW-MEM-001 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-KNOW-MEM-004 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-KNOW-MEM-002 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-LINK-CHAN-002 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-UX-CONV-002 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-CORE-LOOP-004 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-CORE-LOOP-005 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-CORE-LOOP-006 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-LINK-EXT-002 | 3.2 Doyah Agent | 进阶可选 |
| FR-AGT-CORE-CTX-001 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-GUARD-PERM-002 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-GUARD-SOUL-002 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-UX-CONV-003 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-KNOW-MEM-005 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-TOOL-SCHED-002 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-GUARD-COST-001 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-KNOW-MEM-003 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-UX-CONV-004 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-UX-CONV-005 | 3.2 Doyah Agent | 常用增强 |
| FR-STD-ALL-BLD-001 | 3.1.1 工程与工具链 | 基线必备 |
| FR-STD-ALL-BLD-002 | 3.1.1 工程与工具链 | 常用增强 |
| FR-STD-ALL-BLD-003 | 3.1.1 工程与工具链 | 基线必备 |
| FR-STD-ALL-BLD-004 | 3.1.1 工程与工具链 | 常用增强 |
| FR-STD-ALL-BLD-005 | 3.1.1 工程与工具链 | 常用增强 |
| FR-STD-ALL-BLD-006 | 3.1.1 工程与工具链 | 常用增强 |
| FR-STD-ALL-BLD-007 | 3.1.1 工程与工具链 | 常用增强 |
| FR-STD-ALL-BLD-008 | 3.1.1 工程与工具链 | 进阶可选 |
| FR-STD-ALL-BLD-009 | 3.1.1 工程与工具链 | 常用增强 |
| FR-STD-ALL-CLI-001 | 3.1.4 命令行出口 | 常用增强 |
| FR-STD-ALL-CLI-002 | 3.1.4 命令行出口 | 常用增强 |
| FR-STD-ALL-CLI-003 | 3.1.4 命令行出口 | 常用增强 |
| FR-STD-ALL-CLI-004 | 3.1.4 命令行出口 | 常用增强 |
| FR-STD-ALL-CLI-005 | 3.1.4 命令行出口 | 常用增强 |
| FR-STD-DB-CONN-007 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-CONN-001 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-CONN-002 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-CONN-008 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-CONN-009 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-CONN-003 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-CONN-017 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-CONN-018 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-CONN-021 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-CONN-004 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-CONN-010 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-CONN-015 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-CONN-016 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-CONN-011 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-CONN-012 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-CONN-013 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-CONN-014 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-CONN-020 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-CONN-005 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-CONN-006 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-DATA-001 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-DATA-002 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-DATA-003 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-DATA-004 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-DATA-005 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-DATA-006 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-DDL-001 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-DDL-002 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-DDL-003 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-DDL-004 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-DDL-005 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-DIAG-001 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-DIAG-002 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-DIAG-003 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-DIAG-004 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-DIAG-005 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-DRV-005 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-DRV-006 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-DRV-007 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-DRV-008 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-DRV-001 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-DRV-002 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-DRV-003 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-DRV-009 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-DRV-010 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-WS-UI-001 | 3.3 Doyah Studio · 工作区 | 基线必备 |
| FR-STD-WS-VCS-001 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-TOOL-003 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-AI-002 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-015 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-FS-009 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-FS-010 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-WEB-003 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-WEB-004 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-NAV-001 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-NAV-007 | 3.3 Doyah Studio · 工作区 | 基线必备 |
| FR-STD-WS-NAV-008 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-NAV-009 | 3.3 Doyah Studio · 工作区 | 基线必备 |
| FR-STD-WS-NAV-010 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-NAV-011 | 3.3 Doyah Studio · 工作区 | 进阶可选 |
| FR-STD-DB-EXEC-014 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-WS-NAV-003 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-DB-SESS-001 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-CONN-019 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-WS-EDIT-024 | 3.3 Doyah Studio · 工作区 | 进阶可选 |
| FR-STD-WS-UI-007 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-001 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-FS-007 | 3.3 Doyah Studio · 工作区 | 基线必备 |
| FR-STD-WS-EDIT-002 | 3.3 Doyah Studio · 工作区 | 基线必备 |
| FR-STD-WS-EDIT-003 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-010 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-011 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-018 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-004 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-NAV-013 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-HELP-001 | 3.3 Doyah Studio · 工作区 | 进阶可选 |
| FR-STD-WS-UI-002 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-UI-005 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-UI-008 | 3.3 Doyah Studio · 工作区 | 进阶可选 |
| FR-STD-WS-EDIT-016 | 3.3 Doyah Studio · 工作区 | 进阶可选 |
| FR-STD-WS-EDIT-005 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-TOOL-001 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-TOOL-002 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-DB-EXEC-001 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-FS-002 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-UI-009 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-UI-010 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-UI-011 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-WEB-001 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-FS-001 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-FS-008 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-UI-006 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-NAV-002 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-NAV-014 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-AI-001 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-FS-003 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-012 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-UI-004 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-013 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-WEB-002 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-UI-003 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-006 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-007 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-019 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-020 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-008 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-009 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-021 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-022 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-EDIT-017 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-NAV-012 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-NAV-004 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-NAV-006 | 3.3 Doyah Studio · 工作区 | 进阶可选 |
| FR-STD-WS-NAV-005 | 3.3 Doyah Studio · 工作区 | 进阶可选 |
| FR-STD-WS-EDIT-014 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-DB-EXEC-002 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-DRV-004 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-EXEC-003 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-EXEC-009 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-EXEC-010 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-EXEC-011 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-EXEC-012 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-EXEC-018 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-EXEC-004 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-EXEC-013 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-EXEC-015 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-EXEC-005 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-EXEC-016 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-EXEC-006 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-EXEC-007 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-EXEC-017 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-EXEC-008 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-IO-001 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-IO-002 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-IO-006 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-IO-003 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-IO-004 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-IO-007 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-IO-005 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-META-001 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-META-002 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-META-003 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-META-004 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-META-009 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-META-005 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-META-013 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-META-014 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-META-006 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-META-007 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-META-010 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-META-015 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-META-011 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-META-012 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-META-008 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-ALL-PLUG-001 | 3.1.3 插件装配 | 基线必备 |
| FR-STD-ALL-PLUG-002 | 3.1.3 插件装配 | 基线必备 |
| FR-STD-ALL-PLUG-003 | 3.1.3 插件装配 | 基线必备 |
| FR-STD-ALL-PLUG-004 | 3.1.3 插件装配 | 常用增强 |
| FR-STD-ALL-PLUG-005 | 3.1.3 插件装配 | 基线必备 |
| FR-STD-ALL-PLUG-006 | 3.1.3 插件装配 | 基线必备 |
| FR-STD-ALL-PLUG-007 | 3.1.3 插件装配 | 基线必备 |
| FR-STD-ALL-PLUG-008 | 3.1.3 插件装配 | 基线必备 |
| FR-STD-DB-RES-001 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-RES-002 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-RES-003 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-RES-004 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-RES-005 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-RES-010 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-RES-011 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-RES-007 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-RES-008 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-RES-009 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-RES-012 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-RES-006 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-RES-013 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-RES-014 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-SESS-002 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-SESS-003 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-SESS-004 | 3.4 Doyah Studio · 数据库 | 进阶可选 |
| FR-STD-DB-SESS-005 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-SESS-006 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| NFR-ALL-GATE-AI-001 | 4.8 AI 智能体 | 基线必备 |
| NFR-ALL-GATE-AI-002 | 4.8 AI 智能体 | 基线必备 |
| NFR-ALL-GATE-AI-003 | 4.8 AI 智能体 | 基线必备 |
| NFR-ALL-GATE-AI-004 | 4.8 AI 智能体 | 常用增强 |
| NFR-ALL-GATE-AI-005 | 4.8 AI 智能体 | 基线必备 |
| NFR-ALL-GATE-AI-006 | 4.8 AI 智能体 | 常用增强 |
| NFR-ALL-GATE-AI-007 | 4.8 AI 智能体 | 常用增强 |
| NFR-ALL-GATE-AI-008 | 4.8 AI 智能体 | 常用增强 |
| NFR-ALL-GATE-COMP-004 | 4.5 NFR-COMP | 基线必备 |
| NFR-ALL-GATE-COMP-005 | 4.5 NFR-COMP | 基线必备 |
| NFR-ALL-GATE-COMP-001 | 4.5 NFR-COMP | 基线必备 |
| NFR-ALL-GATE-COMP-002 | 4.5 NFR-COMP | 进阶可选 |
| NFR-ALL-GATE-COMP-003 | 4.5 NFR-COMP | 常用增强 |
| NFR-ALL-GATE-LANG-01 | 4.7 国际化 | 常用增强 |
| NFR-ALL-GATE-LANG-02 | 4.7 国际化 | 常用增强 |
| NFR-ALL-GATE-LANG-03 | 4.7 国际化 | 常用增强 |
| NFR-ALL-GATE-MAINT-001 | 4.6 NFR-MAINT | 常用增强 |
| NFR-ALL-GATE-MAINT-002 | 4.6 NFR-MAINT | 常用增强 |
| NFR-ALL-GATE-MAINT-003 | 4.6 NFR-MAINT | 常用增强 |
| NFR-ALL-GATE-MAINT-004 | 4.6 NFR-MAINT | 常用增强 |
| NFR-ALL-GATE-MAINT-005 | 4.6 NFR-MAINT | 常用增强 |
| NFR-ALL-GATE-MAINT-006 | 4.6 NFR-MAINT | 常用增强 |
| NFR-ALL-GATE-PERF-001 | 4.1 NFR-PERF | 基线必备 |
| NFR-ALL-GATE-PERF-002 | 4.1 NFR-PERF | 基线必备 |
| NFR-ALL-GATE-PERF-003 | 4.1 NFR-PERF | 基线必备 |
| NFR-ALL-GATE-PERF-004 | 4.1 NFR-PERF | 基线必备 |
| NFR-ALL-GATE-PERF-005 | 4.1 NFR-PERF | 基线必备 |
| NFR-ALL-GATE-PERF-006 | 4.1 NFR-PERF | 基线必备 |
| NFR-ALL-GATE-REL-001 | 4.2 NFR-REL | 基线必备 |
| NFR-ALL-GATE-REL-002 | 4.2 NFR-REL | 基线必备 |
| NFR-ALL-GATE-REL-003 | 4.2 NFR-REL | 基线必备 |
| NFR-ALL-GATE-REL-004 | 4.2 NFR-REL | 基线必备 |
| NFR-ALL-GATE-REL-005 | 4.2 NFR-REL | 基线必备 |
| NFR-ALL-GATE-SEC-001 | 4.3 NFR-SEC | 基线必备 |
| NFR-ALL-GATE-SEC-002 | 4.3 NFR-SEC | 基线必备 |
| NFR-ALL-GATE-SEC-003 | 4.3 NFR-SEC | 基线必备 |
| NFR-ALL-GATE-SEC-004 | 4.3 NFR-SEC | 基线必备 |
| NFR-ALL-GATE-SEC-005 | 4.3 NFR-SEC | 基线必备 |
| NFR-ALL-GATE-SEC-006 | 4.3 NFR-SEC | 基线必备 |
| NFR-ALL-GATE-SEC-007 | 4.3 NFR-SEC | 基线必备 |
| NFR-ALL-GATE-SEC-008 | 4.3 NFR-SEC | 基线必备 |
| NFR-ALL-GATE-UI-001 | 4.9 NFR-UI | 基线必备 |
| NFR-ALL-GATE-USE-001 | 4.4 NFR-USE | 常用增强 |
| NFR-ALL-GATE-USE-002 | 4.4 NFR-USE | 常用增强 |
| NFR-ALL-GATE-USE-003 | 4.4 NFR-USE | 常用增强 |
| NFR-ALL-GATE-USE-004 | 4.4 NFR-USE | 常用增强 |
| NFR-ALL-GATE-USE-005 | 4 非功能需求 | 基线必备 |
| FR-RTR-MKT-FEED-001 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-REV-TRADE-001 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-MKT-FEED-002 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-MKT-FEED-004 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-MKT-FEED-005 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-MKT-STORE-001 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-MKT-FEED-003 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-RSR-PROFILE-001 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-RSR-PROFILE-002 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-RSR-PROFILE-003 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-RSR-REPORT-001 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-REPORT-002 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-SCENARIO-001 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-SCENARIO-002 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-FLOW-CRON-001 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-FLOW-CRON-002 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-REV-ATTR-001 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-REV-ATTR-002 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-REV-ATTR-003 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-REV-QUERY-001 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-REV-QUERY-002 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-MKT-HEALTH-001 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-MKT-HEALTH-002 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-SCENARIO-003 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-RSR-SCENARIO-004 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-REV-QUERY-003 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-RSR-SCENARIO-005 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-REV-ATTR-004 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-REV-ATTR-005 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-REV-ATTR-006 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-REV-ATTR-007 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-REV-ATTR-008 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-REV-ATTR-009 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-REV-TRADE-002 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-REV-TRADE-003 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-REV-QUERY-004 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-REV-QUERY-005 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-REV-QUERY-006 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-REV-QUERY-007 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-REV-QUERY-008 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-FLOW-CRON-003 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-REPORT-003 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-REPORT-004 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-REPORT-005 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-REPORT-006 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-REPORT-007 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-REPORT-008 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-REV-QUERY-009 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-REPORT-009 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-FLOW-CRON-004 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-BACKTEST-001 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-BACKTEST-002 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-BACKTEST-003 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-BACKTEST-004 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-BACKTEST-005 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-BACKTEST-006 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-SAMPLE-001 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-MKT-FUND-001 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-MKT-FUND-002 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-MKT-FUND-003 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-MKT-FUND-004 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-BACKTEST-007 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-BACKTEST-008 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-SAMPLE-002 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-SAMPLE-003 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-SAMPLE-004 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-BACKTEST-009 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-RSR-SAMPLE-005 | 3.6 Doyah Retro | 常用增强 |
| FR-RTR-MKT-STORE-002 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-REV-TRADE-004 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-MKT-STORE-003 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-REV-TRADE-005 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-MKT-STORE-004 | 3.6 Doyah Retro | 基线必备 |
| FR-RTR-REV-TRADE-006 | 3.6 Doyah Retro | 基线必备 |
| FR-STD-ALL-LIC-001 | 3.1.2 授权与版本 | 基线必备 |
| FR-STD-ALL-LIC-002 | 3.1.2 授权与版本 | 基线必备 |
| FR-STD-ALL-LIC-003 | 3.1.2 授权与版本 | 基线必备 |
| FR-STD-ALL-LIC-004 | 3.1.2 授权与版本 | 基线必备 |
| FR-STD-ALL-LIC-005 | 3.1.2 授权与版本 | 常用增强 |
| FR-AGT-CORE-SESS-001 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-CORE-LOOP-008 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-CORE-LOOP-009 | 3.2 Doyah Agent | 基线必备 |
| FR-AGT-PLAN-PLAN-005 | 3.2 Doyah Agent | 基线必备 |
| FR-AGT-PLAN-PLAN-006 | 3.2 Doyah Agent | 基线必备 |
| FR-AGT-KNOW-CTX-001 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-KNOW-CTX-002 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-TOOL-EDIT-001 | 3.2 Doyah Agent | 基线必备 |
| FR-AGT-LINK-CHAN-003 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-LINK-EXT-003 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-UX-CONV-006 | 3.2 Doyah Agent | 基线必备 |
| FR-AGT-UX-SESS-001 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-QUAL-VERIFY-001 | 3.2 Doyah Agent | 基线必备 |
| FR-AGT-QUAL-VERIFY-002 | 3.2 Doyah Agent | 常用增强 |
| FR-AGT-QUAL-VERIFY-003 | 3.2 Doyah Agent | 基线必备 |
| FR-AGT-QUAL-VERIFY-004 | 3.2 Doyah Agent | 基线必备 |
| FR-STD-WS-FS-004 | 3.3 Doyah Studio · 工作区 | 基线必备 |
| FR-STD-WS-FS-005 | 3.3 Doyah Studio · 工作区 | 基线必备 |
| FR-STD-WS-FS-006 | 3.3 Doyah Studio · 工作区 | 基线必备 |
| FR-STD-WS-EDIT-023 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-VCS-002 | 3.3 Doyah Studio · 工作区 | 常用增强 |
| FR-STD-WS-LIC-001 | 3.1.2 授权与版本 | 基线必备 |
| FR-STD-DB-DIAG-006 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-TASK-001 | 3.4 Doyah Studio · 数据库 | 常用增强 |
| FR-STD-DB-TASK-002 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-STD-DB-TASK-003 | 3.4 Doyah Studio · 数据库 | 基线必备 |
| FR-NTS-TODO-LIST-001 | 3.5 Doyah Notes | 基线必备 |
| FR-NTS-TODO-LIST-002 | 3.5 Doyah Notes | 基线必备 |
| FR-NTS-TODO-LIST-003 | 3.5 Doyah Notes | 常用增强 |
| FR-NTS-TODO-CALENDAR-001 | 3.5 Doyah Notes | 常用增强 |
| FR-NTS-TODO-CALENDAR-002 | 3.5 Doyah Notes | 常用增强 |
| FR-NTS-TODO-STATE-001 | 3.5 Doyah Notes | 基线必备 |
| FR-NTS-TODO-STATE-002 | 3.5 Doyah Notes | 基线必备 |
| FR-NTS-TODO-LINK-001 | 3.5 Doyah Notes | 常用增强 |
