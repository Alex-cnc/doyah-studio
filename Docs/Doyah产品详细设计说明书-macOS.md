# Doyah产品详细设计说明书 · macOS

> **版本** v1.7（2026-10-25 补 §3.20 并行编排契约 + 矩阵 46→47 行 + T-3.20-01~03；v1.6：2026-10-25 补 §3.18 代码执行、§3.19 工具目录两节七段契约 + 矩阵 §8.11/命令执行/代码执行/工具目录四行 + 5 个新用例；v1.5：2026-10-25 补 §3.17 命令执行七段契约 + 矩阵 §8.11 行 + 4 个 T-3.17 用例；v1.4：2026-10-25 Agent 界面按 Hermes TUI 基准补齐 §5.3.8.1–5.3.8.3；v1.3：2026-10-25 `DETAIL_CONFLICT` 第 1 条已裁决并落地（口令/模型密钥改注入系统钥匙串）；v1.2 内容：按 `detail-design-spec-writing` 自检修齐：补 §2.2 注入点与 §2.3 命名约束；§3 由六节散文改为十六节逐函数契约；§5.3 拆七个组件六态小节并新增 §5.8 界面用例表；§6 拆 6.1/6.2/6.3；§7、§8 拆子节；§0.1 矩阵由 21 行拆到 42 行逐条对齐；§11 增 DETAIL_GAP 登记；已知坑移 §13）

> v1.1（2026-10-21 扫差补齐：加笔记域与复盘宿主两章、矩阵补笔记域与复盘域两行）

> v1.0（2026-10-21 全量重写：在 v0.1 摘要稿基础上补齐追溯矩阵 / 函数契约 / 状态覆盖 / 界面六态 / 错误映射 / 测试 ID；上游契约 = `Docs/Doyah产品概要设计说明书.md` v0.6）

## 0. 文档元信息与追溯关系

- 项目/功能名称：Doyah · macOS 端全部能力（Studio 工作区与数据库 / Notes / Retro 宿主 / Agent 在 Studio 内的表现 / 授权呈现）
- 文档版本：v1.7（正文任何改动必须同步本节与 §12）
- 实现范围（2026-10-25 实测件数）：`Core/` 260 个 `.swift` + `App/` 133 个 `.swift` + `Platform/macOS/` 5 个文件 + `CLI/` 4 个文件；测试面 `Tests/` 283 个文件
- 上游依据：
  - 概要设计说明书：`Docs/Doyah产品概要设计说明书.md` v0.10（含 §11.4 非功能归属 47 条与 §21 标准对照）
  - 需求规格书：`Docs/Doyah产品需求规格说明书.md` v3.425
  - 能力规划书：`Docs/Doyah产品能力规划说明书.md` v1.247
  - 设计规范（视觉）：`Core/DesignTokens.swift` + `Docs/规范/界面设计节-写作规范.md`
- 本文件性质：**概要设计的实现级展开。** 概要设计说「不许做什么」，本文件说「具体怎么做、做完怎么证明」。本文件允许出现平台名、类型名、文件路径与库版本。
- 优先级：需求规格书 > 概要设计 > 本详细设计 > 现有代码。
- 冲突处理：与概要设计冲突时以概要设计的「禁止」条款为准，输出 `DESIGN_CONFLICT`，不得自行裁决。
- 禁止行为：不得在本文件未定义的函数/组件中新增公开行为；不得修改 §1.3 禁止文件、不得引入 §1.1 基线外依赖；不得修改测试断言、跳过测试或放宽校验来适配实现。

### 0.1 概设—详设追溯矩阵

> 每一行 = 概要设计一条契约 → 本文件一个落点节 → 一个实现单元 → 至少一个真实存在的测试 ID。区间行一律拆到单条。

| 概设章节 | 概设条款摘要 | 详设落点 | 实现单元 | 测试用例 ID |
|---|---|---|---|---|
| 概要设计 §3 | 20 组件必须做/禁止做；禁越层、禁界面持句柄、禁方言分支散落 | 2.1 | `AppState`、`DatabaseService` 协议 | `T-2.1-01` |
| 概要设计 §3.1 | 浏览页签与文件页签同类；禁并入执行面、禁预览侧改写源文件 | 2.1、5.3.7 | `BrowserTabView`、`Core/BrowserTabStore.swift` | `UI-5.3.7-01` |
| 概要设计 §4.1 | 连接建立四类行为；凭据不入请求体；不自动重试认证失败 | 3.1、2.2 | `DatabaseServiceFactory.make`、`ConnectionConfig` | `T-3.1-01`、`T-3.1-02`、`T-2.2-01` |
| 概要设计 §4.2 | 删除连带清凭据；重复删报已不存在；执行中禁删 | 3.2 | `ConnectionStore.save`、`SecretStore` 实现 | `T-3.2-01`、`T-3.2-02` |
| 概要设计 §4.3 | 选区判定、按文本顺序逐条、多结果集全保留 | 3.3、3.5 | `DatabaseService.execute`、`ExecutionSafety.check` | `T-3.3-01`、`T-3.3-02`、`T-3.3-03`、`T-3.5-01` |
| 概要设计 §4.4 | 服务端真取消、连接仍可用、重复取消同一结局 | 3.4 | `DatabaseService.cancel` | `T-3.4-01` |
| 概要设计 §4.5 | 层级按类型；刷新不清选择；禁伪造占位节点 | 3.7 | `MetadataService.loadChildren` | `T-3.7-01` |
| 概要设计 §4.6 | 浏览前 N 行在服务端过滤；无主键不给行编辑；影响 0 行报冲突 | 3.8、3.9 | `RowBrowsingQuery.browse`、`AppState.applyRowEdits` | `T-3.8-01`、`T-3.9-01` |
| 概要设计 §4.7 | 未预览不得执行；删表带存在才删；禁把 DDL 当普通查询 | 3.10 | `SchemaScriptRunner.run`、`TableDesign.validate` | `T-3.10-01`、`T-3.10-02` |
| 概要设计 §4.8 | 流式写文件；目标存在必询问；部分失败列明细 | 3.11、3.12 | `ResultExporter.text`、`TableImport.plan` | `T-3.11-01`、`T-3.12-01` |
| 概要设计 §4.9 | 终止需二次确认并说明后果；权限不足上浮原话 | 3.13 | `SessionMonitor.sessions` | `T-3.13-01` |
| 概要设计 §4.10 | 行数据须确认并留痕；禁投递凭据与连接串 | 3.14 | `AgentContext.assemble` | `T-3.14-01` |
| 概要设计 §5.1 | 连接配置字段、允许读写方、不含口令本体 | 4.1、4.2 | `ConnectionConfig` | `T-4.1-01` |
| 概要设计 §5.2 | 执行记录按天一份、同 SQL 只计次数、归档失败不回滚业务 | 4.1、4.2 | `QueryHistoryStore` | `T-4.2-01` |
| 概要设计 §5.3 | 任务定义字段（读写模式 / 影响行数上限 / 是否需审批） | 4.1、4.2 | 任务配置件 | `T-4.2-02` |
| 概要设计 §5.4 | 审批单与回执；预估取不到写「未接」，禁编造 | 4.1、4.2、3.6、3.16 | `AgentApprovalConsumption`、`AgentPlanRows.estimate` | `T-3.6-01`、`T-3.16-01` |
| 概要设计 §6.1 | 连接状态机闭集；禁失败直跳已连接 | 4.4 | `ConnectionState` | `T-4.4-01`、`T-4.4-02` |
| 概要设计 §6.2 | 语句执行状态机闭集；禁已取消转已完成 | 4.4 | `QueryEvent` | `T-4.4-03`、`T-4.4-04` |
| 概要设计 §6.3 | 审批单状态机闭集；禁已拒绝/已过期转已批准 | 4.4、3.6 | `AgentApprovalVerdict` | `T-4.4-05`、`T-4.4-06` |
| 概要设计 §6.4 | 页签状态机闭集；执行中不可关闭；恢复不重放语句 | 4.4 | `QueryTabState` | `T-4.4-07`、`T-4.4-08` |
| 概要设计 §7.1 | 查询全链调用顺序与失败处理表 | 4.3 | `AppState` 执行入口 | `T-3.3-01`、`T-3.5-01` |
| 概要设计 §7.2 | 结构变更顺序：生成→预览→二次确认→执行 | 4.3、3.10 | `ExecutionSafety`、`SchemaScriptRunner` | `T-3.10-01`、`T-3.10-02` |
| 概要设计 §7.3 | 外部改动提示二选一；保存失败不清脏标记 | 4.8 | `WorkspaceSession` 与编辑器状态 | `T-4.8-01` |
| 概要设计 §8.1 | 界面范围与边界；禁新增未登记入口、禁新界面库 | 5.1 | `App/Views/*` | `UI-5.1-01` |
| 概要设计 §8.2 | 八类页面/视图职责与禁止呈现项 | 5.1 | 视图清单表 | `UI-5.1-02` |
| 概要设计 §8.3 | 导航允许流转四条与禁止跳转 | 5.7 | 页签模型与活动栏路由 | `UI-5.7-01` |
| 概要设计 §8.4 | 界面六态必须呈现与禁止行为 | 5.3 | 六态落点表与七个组件小节 | `UI-5.3-01`、`UI-5.3-02`、`UI-5.3.1-01`、`UI-5.3.2-01`、`UI-5.3.3-01`、`UI-5.3.4-01`、`UI-5.3.5-01`、`UI-5.3.6-01` |
| 概要设计 §8.5 | 交互规则：校验前禁提交、不可逆二次确认、禁 toast 承载决策 | 5.5 | 事件绑定表 | `UI-5.5-01` |
| 概要设计 §8.6 | 表单字段校验规则与错误定位位置 | 5.6 | `ConnectionFormView` 校验分支 | `UI-5.6-01` |
| 概要设计 §8.7 | 八个界面动作 → 接口映射与禁止行为 | 5.5 | 动作映射表 | `UI-5.5-02` |
| 概要设计 §8.8 | 字段级/页面级/服务器错误呈现规则 | 6.1 | `AppError` 呈现路径 | `T-6.1-01` |
| 概要设计 §8.9 | 键盘路径成套、读屏语义、快捷键只在一处定义 | 5.6、5.7 | `AppCommandCatalog` | `UI-5.7-02` |
| 概要设计 §8.10 | 界面契约验收八条判据 | 5.8 | 界面用例表 | `UI-5.8-01` |
| 概要设计 §9 | 21 个错误码 + 四级兜底禁令 + 日志要求 | 6.1、6.2、6.3 | `AppError`、`ConnectionFailure` | `T-6.1-01`、`T-6.2-01` |
| 概要设计 §10 | 12 条被拒绝方案 | 1.1 | — | 静态检查 |
| 概要设计 §11.4 | 47 条非功能需求的设计归属 | 2.2、7.1、7.2、8.1、8.2 | `actor` 与 `@MainActor` 边界、`EgressLog` | `T-7.1-01`、`T-7.2-01`、`T-8.1-01`、`T-8.2-01` |
| 概要设计 §12 | 设计合规验收判据十条 | 10.2 | — | 自检输出 |
| 概要设计 §14.1 | 缺口清单与四条暂定口径（过期/预估/自动附带/设备配额） | 11 | 本文件「暂定口径承接」 | 人工点验 |
| 概要设计 §15 | 笔记域 14 节不变量（捕获/附件/私密/回收站/待办/日历） | 4.5 | `NoteLibrary`、`NoteDatabase`、`NoteAutosave` | `T-4.5-01` |
| 概要设计 §16 | 复盘域 18 节（行情/特征/回测/复盘稿/周报） | 4.7 | `App/Views/RetroHostView.swift`（宿主；实现不在本仓） | `T-4.7-01` |
| 概要设计 §18.1 | 循环与工具：参数先校验、观测有界、预算耗尽即结束 | 3.15 | `AgentStandardDispatcher.dispatch` | `T-3.15-01` |
| 概要设计 §19.2 | 插件装配：同进程模块、清单为唯一装配源 | 2.3 | `Scripts/check-plugin-assembly.py` 对应清单 | `T-2.3-01` |
| §3 组件契约（命令执行） | 起一条命令并带回 stdout/stderr/退出码；后台可中断；审批+审计；仅授权目录 | §3.17 | `AgentCommandRunner.run(_:in:timeout:)` | `T-3.17-01` `T-3.17-02` `T-3.17-03` `T-3.17-04` |
| §8.11 界面语汇与可配置项 | 行首栏字形 / 一个字号 / 状态行字段序 / 九个显示开关 / 主题按角色 | §5.3.8.1 / §5.3.8.2 / §5.3.8.3 | `AgentChatView`（字形与状态行）· `AgentMarkdownBody` · 主题值表 | `UI-5.8-01` `UI-5.8-02` |
| §3 组件契约（代码执行） | 受限目录跑多行代码，沙箱无网、超时/内存上限、输出截断 | §3.18 | `AgentCodeRunner.run(_:language:in:)` | `T-3.18-01` `T-3.18-02` `T-3.18-03` |
| §3 组件契约（工具目录） | 按名/用途检索工具并取回 schema；未取回不得调用 | §3.19 | `AgentToolCatalog.search(_:limit:)` | `T-3.19-01` `T-3.19-02` |
| §3 组件契约（并行编排） | 多路无依赖子任务并行、各自隔离、逐路给结局并归并、可改方向或叫停 | §3.20 | `AgentOrchestrator.run(_:options:)` | `T-3.20-01` `T-3.20-02` `T-3.20-03` |

矩阵数据行：42 行。概设契约节（§3.1、§4.1–§4.10、§5.1–§5.4、§6.1–§6.4、§7.1–§7.3、§8.1–§8.10、§11.4）在本表逐节有落点，无缺口。

---

## 1. 平台基线与实现范围

### 1.1 平台基线（Agent 不得更换）

| 项 | 取值 | 版本约束 | 改动方式 |
|---|---|---|---|
| 语言 | Swift | 5.9+ | 需人类主人批准 |
| 部署目标 | macOS 14 | `Package.swift` 的平台声明 | 需人类主人批准 |
| 界面框架 | SwiftUI（AppKit 兜底桥接） | 随 toolchain | 需人类主人批准 |
| 嵌入式库 | SQLite（笔记数据家，vendored） | `Scripts/vendored-sqlite.json` | 需人类主人批准 |
| 构建 | SwiftPM + `Scripts/build-app.sh` | 见 §9.3 | 需人类主人批准 |
| 测试 | XCTest（`Tests/` 283 文件） | `Scripts/verify-core.sh` | 需人类主人批准 |
| 版本控制 | 只读展示（禁提交/推送/合并/切分支） | — | — |

概要设计 §10 的 12 条被拒绝方案在本端的禁止项：

| 概设 §10 被拒绝方案 | 本端禁止项 | 检查方式 |
|---|---|---|
| 只读连接给「仍然执行」 | 禁止绕过 `ExecutionSafety.Decision.refused` 的任何入口 | 代码检索 `refused` 分支 + `rg '仍然执行'` 为空 |
| `EXPLAIN ANALYZE` 估行数 | 仅允许 `EXPLAIN (FORMAT JSON)` | 代码检索 `rg 'EXPLAIN ANALYZE'` 为空 |
| 行数用表总行数或猜测 | `AgentPlanRows` 取不到即如实说「未接」，不报 0 | `T-3.16-01` |
| 写语句自动重试 | 禁止对写语句自动重试 | 代码检索 + `T-3.3-02` |
| 界面层缓存服务对象 | 服务按「连接 + 库」唯一（`AppState.ensureService`） | 评审 + `T-7.1-01` |
| 整表读进内存导出 | 必须流式写文件 | 代码检索 + `T-3.11-01` |
| 多语句并发执行 | 必须按文本顺序逐条 | `T-3.3-01` |
| 未授权入口显示灰色 | 未授权即不出现 | `UI-5.5-01` |
| 到期锁死数据 | 降级入口，数据可开可导出 | `UI-5.3-01` |
| 结果行数据默认投给助理 | 必须显式确认并留痕 | `T-3.14-01` |
| 实现读数写进契约 | 读数只进台账 | 评审 |
| 只读日志面板冒充终端 | 终端必须真交互（PTY） | `UI-5.1-02` |

### 1.2 本文件覆盖的落点文件

| 文件路径 | 操作 | 用途 | 允许修改的符号 | 对应概设条款 |
|---|---|---|---|---|
| `Core/DatabaseService.swift` | 修改 | 协议 + 工厂 | `DatabaseService`、`DatabaseServiceFactory` | 概要设计 §3、§4.1 |
| `Core/ExecutionSafety.swift` | 修改 | 只读/写判定与高危确认 | `ExecutionSafety.check`、`Decision` | 概要设计 §4.3、§7.1 |
| `Core/ConnectionStore.swift` | 修改 | 连接清单持久化 | `load`、`save`、`fileLocation` | 概要设计 §4.1、§5.1 |
| `Core/AgentApprovalGate.swift` | 修改 | 审批单与消费记录 | `request`、`grant`、`peek` | 概要设计 §5.4、§6.3 |
| `Core/MetadataService.swift` | 修改 | 对象树与表结构取数 | `loadRoot`、`loadChildren`、`tableStructure` | 概要设计 §4.5 |
| `Core/RowBrowsing.swift` | 修改 | 前 N 行浏览与过滤 | `RowBrowsingQuery.browse`、`Filter` | 概要设计 §4.6 |
| `Core/TableDesign.swift` | 修改 | 列定义校验 | `TableDesign.validate`、`columnChanges` | 概要设计 §4.7 |
| `Core/ResultExporter.swift` | 修改 | 结果集多格式导出 | `ResultExporter.text`、`data` | 概要设计 §4.8 |
| `Core/AgentContext.swift` | 修改 | 助理上下文装配与脱敏 | `assemble`、`filterSecretsOnly` | 概要设计 §4.10 |
| `Core/AgentPlanRows.swift` | 修改 | 影响行数预估 | `estimate`、`rows(fromExplainJSON:)` | 概要设计 §5.4 |
| `App/AppState.swift` | 修改 | 界面意图 → 能力层 | 相关 `@MainActor` 方法 | 概要设计 §3、§7.1 |
| `App/Views/ConnectionFormView.swift` | 修改 | 连接表单与校验呈现 | 校验分支 | 概要设计 §8.6 |
| `App/Views/ObjectTreeView.swift` | 修改 | 对象树六态与刷新语义 | 刷新分支 | 概要设计 §4.5、§8.4 |
| `App/Views/AgentApprovalSheet.swift` | 修改 | 审批单呈现与确认 | 提交分支 | 概要设计 §5.4、§8.5 |
| `Platform/macOS/KeychainSecretStore.swift` | 修改 | 凭据存取落点 | `setPassword`、`password`、`deletePassword` | 概要设计 §3、§4.2 |

### 1.3 禁止修改的文件

| 文件/目录 | 原因 |
|---|---|
| `Platform/linux/` 整棵子树 | 对侧端实现，本侧不改、不判红 |
| `Platform/windows/` 整棵子树 | 对侧端实现，本侧不改、不判红 |
| `Tests/` 下已有断言 | 不许放宽校验来适配实现 |
| `Scripts/path-ownership.json` | 归属真值，改动需派单 |
| `Docs/` 下他人署名的契约节 | 契约层归契约所有者 |

### 1.4 本文件不覆盖的内容

- 跨端行为判据（在概要设计）；进度与状态（开发计划书）；测试读数（台账）。
- Windows / Linux / 移动端实现（各自的详细设计文件）。
- 概要设计 §14.1 的四条暂定口径本身（过期终局 / 预估取不到 / 自动附带上下文 / 设备配额交互）：本文件只承接其落点，口径由人类主人可否决。

---

## 2. 分层与模块

四层，依赖单向：

| 层 | 目录 | 职责 | 线程模型 |
|---|---|---|---|
| 界面层 | `App/Views/` | 渲染、手势、键盘 | 主线程 |
| 装配层 | `App/AppState.swift`、`App/AgentChatModel.swift` | 承接界面意图、调能力层、把值分发给主线程模型 | `@MainActor` |
| 能力层 | `Core/`（260 个文件）、`Plugins/Notes/Sources/` | 数据库执行、智能体、笔记、同步、导入导出 | 无 UI 依赖；阻塞工作不在主线程 |
| 平台接入 | `Platform/macOS/` | 系统能力（Keychain、目录授权、WebKit、SSH 凭据） | 按调用方 |

### 2.1 组件 → 实现单元

| 模块 | 主要文件 | 契约条款 |
|---|---|---|
| 数据库执行 | `Core/DatabaseService.swift`、`PostgresService.swift`、`MySQLService.swift`、`GBaseService.swift`、`ExecutionSafety.swift` | 概要设计 §4.1 / §4.3 / §4.4 |
| 连接与凭据 | `Core/ConnectionStore.swift`、`ConnectionConfig.swift`、`Platform/macOS/KeychainSecretStore.swift` | 概要设计 §4.1 / §4.2 / §5.1 |
| 元数据与对象树 | `Core/MetadataService.swift`、`DatabaseObjectRef.swift`、`ObjectTreeRefreshGate.swift` | 概要设计 §4.5 |
| 行浏览与写回 | `Core/RowBrowsing.swift`、`App/Views/BrowseRowsSheet.swift` | 概要设计 §4.6 |
| 结构变更 | `Core/TableDesign.swift`、`App/Views/TableDesignSheet.swift` | 概要设计 §4.7 |
| 导入导出 | `Core/ResultExporter.swift`、`Core/TableImport.swift`、`App/Views/ImportPanel.swift` | 概要设计 §4.8 |
| 服务器会话 | `Core/SessionMonitor.swift`、`App/Views/SessionPanel.swift` | 概要设计 §4.9 |
| 智能体回合 | `Core/AgentLoop.swift`、`AgentToolRegistry.swift`、`AgentStandardDispatcher.swift`、`AgentSQLGenerator.swift` | 概要设计 §18.1 |
| 审批与审计 | `Core/AgentApprovalGate.swift`、`AgentAudit.swift`、`AgentPlanRows.swift` | 概要设计 §5.4 / §6.3 |
| 会话与上下文 | `Core/AgentSession.swift`、`AgentContext.swift`、`AgentMemory.swift` | 概要设计 §4.10 / §5.1 |
| 笔记 | `Plugins/Notes/Sources/NoteStorage/`（`NoteLibrary`、`NoteDatabase`、`NoteAutosave`）、`NoteSync/`（`CloudSyncService`、`SyncQueue`） | 概要设计 §15 |
| 内嵌浏览器 | `App/Views/BrowserTabView.swift`、`Core/BrowserTabStore.swift`、`Platform/macOS/WebKitBrowserEngine.swift` | 概要设计 §3.1 |
| 命令登记 | `App/AppCommandCatalog.swift` | 概要设计 §8.3 / §8.9 |

概要设计 §3 的「禁止做」在本端的实现级禁令：

- 界面层禁止 `import` 驱动实现（`PostgresService` / `MySQLService` / `GBaseService`）：`rg -n 'PostgresService|MySQLService|GBaseService' App/` 必须为空。
- 任意组件禁止跨层持有连接句柄、事务句柄、文件句柄：句柄只存在于 `DatabaseService` 实现内部，对外只暴露 `ExecutionHandle` 值类型。
- 方言分支禁止散进界面或业务层：方言差异只允许出现在 `Core/Dialects.swift` 与各 `*Service.swift`。
- 能力层禁止回调界面刷新：能力层只递值（`AsyncStream` / 闭包），界面更新一律回 `@MainActor`。

### 2.2 注入点与可替换依赖

| 依赖 | 注入方式（三选一，写死） | 注入点 | 测试替身 | 禁止做法 |
|---|---|---|---|---|
| 数据库执行 | 协议 + 构造函数参数 | `DatabaseServiceFactory.make(for:password:language:)` 是唯一造实例入口；测试直接用 `FakeDatabaseService` 实现 `DatabaseService` 协议 | `FakeDatabaseService`（`Tests/`，实现同一协议） | 界面或装配层 `PostgresService(...)` 直接 new；实现内部按 `dbType` 再分支 |
| 方言 | 构造函数参数 | `ResultExporter.text(for:format:tableName:schema:dialect:)`、`RowBrowsingQuery.browse(table:schema:filter:dialect:)`、`ExecutionSafety.check(...)` 均收 `any SQLDialect` / `DatabaseType` 形参 | `FakeSQLDialect`（实现 `SQLDialect` 协议） | 在函数体内按 `config.dbType` 取全局方言单例 |
| 时钟 | 构造函数参数（调用点传 `Date`） | `QueryHistoryStore.load(now:)`、`append(_:now:)`、`AgentApprovalGate.grant(fingerprint:at:)`、`peek(fingerprint:at:)`、`ServerSession.elapsedSeconds(now:)` 全部收 `Date` 形参，默认值 `Date()` 只许出现在签名 | 固定 `Date(timeIntervalSince1970:)` | 函数体内直接 `Date()` 而绕开形参；用 `Timer` 当时间源 |
| ID 生成器 | Provider 协议 | `IDProvider { func makeID() -> UUID }` 由装配层持有并注入；`QueryTabState.init(id: UUID = UUID())` 一类签名保留 `id` 形参供替身注入 | `SequentialIDProvider` | 业务代码里散落 `UUID()`（`rg -n 'UUID\(\)' Core/` 只允许出现在默认参数与 `IDProvider` 实现里） |
| HTTP / 模型出口 | Provider 协议 | `HTTPTransport` 与 `HTTPStreamingTransport` 协议；会话内不出现 `URLSession.shared` | `StubTransport`（离线固定响应） | 视图或装配层直接 `URLSession.shared`；实现内部硬编码端点 |
| 密钥存储 | 构造函数参数 | 调用方持 `any SecretStore`（协议在 `Core/SecretStore.swift`，macOS 实现 `Platform/macOS/KeychainSecretStore.swift`），由装配层构造时给 | `InMemorySecretStore` | 业务代码直连 `SecItemAdd` 而不经协议 |
| 文件系统定位 | 构造函数参数 | `ConnectionStore.init(directoryURL:)`、`NoteLibrary` 的库路径由装配层给 | 临时目录 | 硬编码 `~/Library/Application Support` 字符串 |

- 三选一的落地口径：**主注入手段 = 构造函数参数**（凡有实现类的依赖）；**Provider 协议**只用于「同一接口多实现且运行期选择」的两种依赖（ID 生成器、HTTP 出口）。工厂（Factory）只用于 `DatabaseServiceFactory` 一处，因为方言选择必须与 `ConnectionConfig` 同源。
- **已修（2026-10-25 人类主人裁定「改实现」）**：`AppState.secretStore` 不再是 `FileSecretStore()` 写死 —— `AppState.init` 改为**构造函数注入**，默认 `KeychainSecretStore()`（`Platform/macOS/KeychainSecretStore.swift`），`FileSecretStore()` 只作测试 / 开发态显式注入。同一处 `agentKeyStore` 默认改为 `KeychainAgentKeyStore()`（`NFR-ALL-GATE-AI-007`）。本行原为 `DETAIL_CONFLICT` 登记，现已闭合。

### 2.3 目录与命名约束

- 新增文件目录：能力代码只进 `Core/`；界面代码只进 `App/Views/`；平台专属实现只进 `Platform/macOS/`；测试只进 `Tests/`（单元）或 `TestsUISnapshot/`（快照）。
- 命名：类型 `UpperCamelCase`；函数与属性 `lowerCamelCase`；协议名不加 `Protocol` 后缀；测试文件与被测类型同名加 `Tests`；测试方法名 `test_<被测>_<条件>_<期望>`。
- 插件装配唯一来源：`Plugins/*/manifest` 一类清单文件；新增插件必须同时登记清单与 `Scripts/check-plugin-assembly.py` 的期望列表，两处不一致即判红（`T-2.3-01`）。
- 禁止跨层引用：`App/Views/**` 不得 `import` 数据库驱动实现、不得引用 `Core/` 下以 `Service` 结尾的具体类型；`Core/` 不得引用 `App/` 任何符号。
- 判据：`rg -n 'import ' App/Views/ | rg 'Postgres|MySQL|GBase'` 为空；`rg -n 'AppState' Core/` 为空。

---

## 3. 函数/方法级契约

> 每节 = 一个公开函数；七段齐：前置条件 / 后置条件 / 错误契约表 / 禁止行为 / 并发·幂等·事务 / 日志字段 / 测试 ID。错误契约表是本节的唯一表格，逐行必须有「可重试」判定。

### 3.1 `DatabaseServiceFactory.make(for:password:language:)`

- 所属单元：`Core/DatabaseService.swift` ｜ 对应概设条款：概要设计 §4.1
- 用途：按 `ConnectionConfig.dbType` 造出方言实现，口令与界面语言由调用方显式给。
- 前置条件：
  - [ ] `config.dbType` ∈ {`postgresql`、`mysql`、`gbase8a`}（`DatabaseType` 闭集）
  - [ ] `host` 非空；`port` 先解析再校验且 ∈ 1…65535；`database`、`username` 均非空
  - [ ] `password` 由 `SecretStore` 取到；取不到走 `CONN_NO_CREDENTIAL`，不得用空串顶替
  - [ ] `language` 必填，签名不得给默认值
- 后置条件：
  - [ ] 返回 `DatabaseService`，懒连：本函数不建连、不发任何网络请求
  - [ ] `service.config` 与入参 `config` 逐字段相等
  - [ ] 不写任何持久化状态；不在内部缓存实例（实例由 `AppState.ensureService` 以「连接 id + 库」为键持有）
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 参数非法（空主机 / 端口越界 / 库名空） | `CONN_INVALID_CONFIG` | `AppError.invalidConfiguration` | 否 | 禁止用默认值补参后照造实例 |
| 类型不在闭集 | `CONN_INVALID_CONFIG` | `AppError.notImplemented` | 否 | 禁止回落到别的方言冒充支持 |
| 凭据缺失 | `CONN_NO_CREDENTIAL` | 调用方在造实例前抛，本函数不吞 | 人工 | 禁止用空口令尝试连接 |
| 依赖超时 | 不适用（本函数无 IO） | 不适用 | 不适用 | 禁止在工厂内建连来「提前发现」故障 |

- 禁止行为：
  - 禁止在内部读环境变量或偏好补齐缺参；缺参即失败。
  - 禁止把方言分支写进界面层或装配层。
  - 禁止用 `fatalError` / `preconditionFailure` 代替可显示错误。
- 并发·幂等·事务：纯构造，无共享可变状态；不持有事务；并发调用互不影响。
- 日志字段：`connection_id`、`db_type`、`elapsed_ms`；禁记 `password`、`dsn`、凭据引用原文。
- 测试 ID：`T-3.1-01`（正例）、`T-3.1-02`（非法输入）

### 3.2 `ConnectionStore.save(_:)`

- 所属单元：`Core/ConnectionStore.swift` ｜ 对应概设条款：概要设计 §4.2、§5.1
- 用途：把整份连接清单原子落盘，供连接管理与执行路径读取。
- 前置条件：
  - [ ] 入参数组内 `id` 唯一；`name` 在同一工作区内唯一
  - [ ] 每项通过 `ConnectionConfig` 校验（端口 1…65535、必填非空、SSL 模式属于该类型集合）
  - [ ] 无「执行中语句」的连接被删除（删除前由装配层判，判不过即拒）
- 后置条件：
  - [ ] 整文件原子替换：要么全写成功，要么旧文件逐字节不变
  - [ ] `fileLocation()` 可读回刚写的条目数
  - [ ] `schemaVersion` 保留并只升级一次（旧格式读入后立即回写新格式）
  - [ ] 删除连接时连带清 `SecretStore` 条目，清理失败必须上浮残留位置
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 目录不可写 | `CRED_PURGE_FAILED` | `AppError.persistence` | 人工 | 禁止静默丢配置后返成功 |
| 迁移失败（旧格式解析不通过） | `CONN_INVALID_CONFIG` | `AppError.persistence` | 否 | 禁止用默认值覆盖旧文件 |
| 凭据清理失败 | `CRED_PURGE_FAILED` | 上浮残留条目位置 | 人工 | 禁止只删列表项而留下凭据 |
| 依赖超时（磁盘 IO 超时） | 不适用（无网络） | 不适用 | 不适用 | 禁止在超时后当作已保存 |

- 禁止行为：
  - 禁止先删旧文件再写新文件（半写会丢全部连接）。
  - 禁止在 `save` 内部改 `ConnectionConfig` 字段（迁移只补版本号）。
  - 禁止捕获写盘错误后不记录、不返回。
- 并发·幂等·事务：`actor` 内串行；同一份内容的重复 `save` 结果逐字节一致；单次写在同一原子替换内完成，不跨多次写。
- 日志字段：`entry_count`、`target_path`、`schema_version`、`elapsed_ms`；禁记口令与凭据引用原文。
- 测试 ID：`T-3.2-01`（往返）、`T-3.2-02`（迁移）

### 3.3 `DatabaseService.execute(_:options:handle:)`

- 所属单元：`Core/DatabaseService.swift` ｜ 对应概设条款：概要设计 §4.3、§7.1
- 用途：执行一段 SQL（选区或整篇），逐条上报进度并保留全部结果集。
- 前置条件：
  - [ ] SQL 文本非空（空串或纯空白在上层即被拦，报 `EXEC_EMPTY_SQL`）
  - [ ] 已过 `ExecutionSafety.check`：`refused` 不得进入本函数；`needsConfirmation` 须已确认
  - [ ] 连接处于已连接态；目标库与上下文栏一致
  - [ ] `handle` 由调用方新建且只用于本次执行
- 后置条件：
  - [ ] 事件序列为 `started` → `resultSet`×N → `finished`，或 `cancelled` / `failed` 收尾
  - [ ] 语句按文本顺序逐条执行，第 N 条的序号随事件上报
  - [ ] 多结果集全部保留在流里，不覆盖、不丢弃
  - [ ] 行数只累加一次；耗时按语句与整体各记一份
  - [ ] 失败即停：后续语句不再发送，事务状态标记为未知或已回滚
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 服务端报错 | `EXEC_SERVER_ERROR` | 流内 `failed`（含序号与原文） | 视错误码，写语句一律人工 | 禁止改写成模糊文案 |
| 链路断开 | `EXEC_CONNECTION_LOST` | 流内 `failed` | 否 | 禁止静默重连后重放写语句 |
| 未连接 | `EXEC_NO_CONNECTION` | `AppError.notConnected` | 否 | 禁止默认连第一个连接 |
| 只读连接遇写语句 | `EXEC_READONLY_DENIED` | `refused`（本函数不接收） | 否 | 禁止提供「仍然执行」入口 |
| 依赖超时（服务端无响应） | `EXEC_SERVER_ERROR` | 流内 `failed`（原话） | 人工（重跑是新执行） | 禁止超时后自动重发写语句 |

- 禁止行为：
  - 禁止并发打乱同一批语句的顺序；禁止把多结果集只留最后一个。
  - 禁止在事务进行中切换连接或目标库。
  - 禁止把「用户取消」写进执行记录的成功分支。
- 并发·幂等·事务：同一连接上串行（服务内部串行队列）；查询幂等，写不自动重试；手工事务由调用方驱动 `beginTransaction` / `commit` / `rollback`。
- 日志字段：`connection_id`、`statement_index`、`elapsed_ms`、`error_code`、`row_count`；禁记结果行数据与凭据。
- 测试 ID：`T-3.3-01`（顺序与选区）、`T-3.3-02`（取消即止）、`T-3.3-03`（空 SQL）

### 3.4 `DatabaseService.cancel(_:)`

- 所属单元：`Core/DatabaseService.swift` ｜ 对应概设条款：概要设计 §4.4
- 用途：让服务端语句真被取消，并把结局如实交回界面。
- 前置条件：
  - [ ] `handle` 属于当前连接且由本连接的一次 `execute` 产生
  - [ ] 该次执行仍处于执行中（已结束的句柄走同一路径返回既有结局）
- 后置条件：
  - [ ] 返回 `CancelOutcome`：成功取消 / 服务端已结束 / `failed(reason:)`
  - [ ] 成功取消后流不再产出 `resultSet`；半截结果不落历史库
  - [ ] 连接保持可用（取消不等于断开）
  - [ ] 重复取消返回同一结局，不产生第二次服务端动作
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 句柄不属于本连接 | `EXEC_CANCEL_ILLEGAL` | `CancelOutcome.failed(reason:)` | 否 | 禁止「尽力取消」后报成功 |
| 方言不支持取消 | `EXEC_CANCEL_FAILED` | `CancelOutcome.failed(reason:)` | 否 | 禁止只停界面接口而不停服务端 |
| 连接已断 | `EXEC_CONNECTION_LOST` | `CancelOutcome.failed(reason:)` | 人工 | 禁止把连接标成不可用 |
| 服务端拒绝 | `EXEC_CANCEL_FAILED` | `failed(reason:)` 带上服务端原话 | 人工 | 禁止把原话改写成模糊文案 |

- 禁止行为：
  - 禁止用「关掉界面进度条」冒充取消成功。
  - 禁止在取消后清空已有结果（已收到的结果集照常保留）。
- 并发·幂等·事务：以 `handle` 为幂等键；并发重复取消只发一次服务端请求，其余等同一结局；不在锁内做网络等待。
- 日志字段：`connection_id`、`handle_id`、`outcome`、`elapsed_ms`；禁记 SQL 原文中的敏感字面量。
- 测试 ID：`T-3.4-01`

### 3.5 `ExecutionSafety.check(sql:databaseType:policy:)`

- 所属单元：`Core/ExecutionSafety.swift` ｜ 对应概设条款：概要设计 §4.3、§7.1
- 用途：执行前判定「允许 / 需确认 / 直接拒绝」，结论只读一次。
- 前置条件：
  - [ ] `sql` 非空（空串由上层拦，本函数返回 `allow` 不得被当作放行依据）
  - [ ] `policy` 必传；`policy.isReadOnly` 是连接属性，总开关关掉也不得绕过
  - [ ] 语句切分按 `databaseType` 的方言规则进行
- 后置条件：
  - [ ] 返回 `.allow` / `.needsConfirmation(reasons:findings:statements:)` / `.refused(reasons:statements:)`
  - [ ] `refused` 必带可显示原因与涉事语句（`readOnlyRefusal` 生成的文案非空）
  - [ ] 结论在本次执行内不再改判：界面状态变化不得翻转已下的结论
  - [ ] 不修改入参、不落盘、不发网络
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 只读连接遇写语句 | `EXEC_READONLY_DENIED` | `.refused(reasons:statements:)` | 否 | 禁止退化成 `needsConfirmation` 让用户点过去 |
| 无 WHERE 的 UPDATE/DELETE | `EXEC_CONFIRM_REQUIRED` | `.needsConfirmation(...)` | 不适用（等人确认） | 禁止先执行后补确认 |
| DROP / TRUNCATE | `EXEC_CONFIRM_REQUIRED` | `.needsConfirmation(...)` | 不适用 | 禁止强制确认策略关闭时放行生产连接 |
| 语句切分失败 | `EXEC_SERVER_ERROR` | `.needsConfirmation` 并把原文列入 findings | 否 | 禁止把切分失败当 `allow` |

- 禁止行为：
  - 禁止返回空原因的 `refused`；禁止把原因写成「不允许」这类无信息文案。
  - 禁止在判定里读界面状态（页签是否脏、按钮是否灰）。
  - 禁止为「生产标签连接」这类未实现特性造旁路开关（标签与只读连接联动尚未实现，登记于 §10.1）。
- 并发·幂等·事务：纯函数，无共享可变状态；同一 `(sql, policy)` 结论恒定；不持有事务。
- 日志字段：`decision`、`reason_code`、`statement_count`；禁记完整 SQL 原文中的敏感字面量。
- 测试 ID：`T-3.5-01`

### 3.6 `AgentApprovalGate.grant(fingerprint:at:)`

- 所属单元：`Core/AgentApprovalGate.swift` ｜ 对应概设条款：概要设计 §5.4、§6.3
- 用途：把用户的批准按次消费到某条待审语句上，并落一条不可重放的消费记录。
- 前置条件：
  - [ ] `fingerprint` 对应一条 `pending` 审批单（由 `request` 造出）
  - [ ] `at` 由调用方给（时钟注入，见 §2.2）
  - [ ] 该 `fingerprint` 尚未被消费（消费集合不含它）
- 后置条件：
  - [ ] 返回 `AgentApprovalVerdict`；批准路径必落一条 `AgentApprovalConsumption`
  - [ ] 消费记录追加式写入，不覆盖既有行
  - [ ] 同一条批准不可重放：第二次 `grant` 同一 `fingerprint` 返回 `.missing`
  - [ ] 审批终态只前进不后退：`approved` 之后不改回 `pending`
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 无该审批单 | 不适用（判决值） | `.missing` | 否 | 禁止把 `.missing` 当通过 |
| 已拒绝 | 不适用（判决值） | `.denied(requestID:)` | 否 | 禁止 `denied → approved` 翻转 |
| 已过期 | 不适用（判决值） | `.expired(requestID:)` | 否 | 禁止 `expired → approved` 翻转 |
| 依赖超时（写消费记录失败） | 不适用 | 抛 `AppError.persistence` | 人工 | 禁止在消费记录未落盘时返回 `.approved` |

- 禁止行为：
  - 禁止把 `pending` / `denied` / `expired` / `.missing` 四档任一当通过。
  - 禁止一次批准复用到另一条语句（`fingerprint` 与语句清单一对一）。
  - 禁止在回执里写口令、连接串原文、敏感字面量。
- 并发·幂等·事务：以 `fingerprint` 为幂等键；消费写入与判决返回在同一原子操作里；并发 `grant` 同一 `fingerprint` 只允许一次成功，其余得 `.missing`。
- 日志字段：`request_id`、`fingerprint`、`verdict`、`at`；禁记语句原文。
- 测试 ID：`T-3.6-01`

### 3.7 `MetadataService.loadChildren(of:)`

- 所属单元：`Core/MetadataService.swift` ｜ 对应概设条款：概要设计 §4.5
- 用途：按数据库类型返回某节点的下一层对象，供对象树展开。
- 前置条件：
  - [ ] 已连接；`object` 来自同一次连接的 `loadRoot()` 或上一层的 `loadChildren`
  - [ ] `object.kind` 属于该方言支持的层级（服务器 → 库 → schema → 表/视图 → 列）
- 后置条件：
  - [ ] 返回 `DatabaseObject` 数组，每项带名称、种类、是否有子节点
  - [ ] 层级形状随 `databaseType` 变化，不做跨类型强制统一
  - [ ] 刷新不清空用户已选中节点（选中态由界面按 `id` 保留）
  - [ ] 不返回任何占位节点（除真正的加载中态由界面渲染）
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 该类型不支持该层级 | `META_UNSUPPORTED` | 抛出并说明层级差异 | 否 | 禁止拿上一层的对象冒充子节点 |
| 服务端查询失败 | `META_FAILED` | 抛出服务端原话 | 人工 | 禁止返回空数组冒充「没有对象」 |
| 未连接 | `EXEC_NO_CONNECTION` | `AppError.notConnected` | 否 | 禁止自动连第一个连接 |
| 依赖超时 | `META_FAILED` | 抛出（含耗时） | 是，重试 1 次，退避 300 ms | 禁止超时后返回部分结果并标成功 |

- 禁止行为：
  - 禁止把不同数据库类型的层级强行统一成一种。
  - 禁止在树里伪造「加载中」以外的占位节点。
  - 禁止把结果写进任何缓存而不带过期判定。
- 并发·幂等·事务：读取幂等；同一节点并发展开只发一次请求（`ObjectTreeRefreshGate` 合并）；不持有事务。
- 日志字段：`connection_id`、`object_kind`、`child_count`、`elapsed_ms`；禁记列注释原文中的敏感内容。
- 测试 ID：`T-3.7-01`

### 3.8 `RowBrowsingQuery.browse(table:schema:filter:dialect:)`

- 所属单元：`Core/RowBrowsing.swift` ｜ 对应概设条款：概要设计 §4.6
- 用途：生成「前 N 行 + 服务端过滤 + 服务端排序」的查询语句。
- 前置条件：
  - [ ] `table` 非空；`schema` 可为 nil
  - [ ] `filter.limit` > 0 且默认 200；`filter.where` / `orderBy` 未经转义时拒绝
  - [ ] `dialect` 必传（标识符引用与分页语法随方言）
- 后置条件：
  - [ ] 返回可执行 SQL 文本；行数上限、排序、过滤全部落在语句里，不由前端过滤
  - [ ] 标识符经 `SQLGenerator.qualifiedName` 转义；不拼接用户原串
  - [ ] 同一 `(table, filter, dialect)` 生成逐字节一致的语句
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 过滤条件非法（空 WHERE 值 / 非法 ORDER BY） | `DATA_WRITE_CONFLICT` 不适用；此处 `BuildError` | `Result.failure(BuildError)` | 否 | 禁止忽略坏条件返回全表 |
| 表名含非法标识符 | `META_UNSUPPORTED` | `Result.failure(BuildError)` | 否 | 禁止直接把表名拼进 SQL |
| 行数上限越界 | 不适用 | 夹到 1…上限并由界面提示 | 否 | 禁止静默夹取不提 |
| 依赖超时 | 不适用（纯字符串生成） | 不适用 | 不适用 | 禁止在此处发起 IO |

- 禁止行为：
  - 禁止把整表读进内存再截断前 N 行。
  - 禁止前端排序冒充服务端排序。
  - 禁止在只读连接上生成写语句（本函数只生成 `SELECT`）。
- 并发·幂等·事务：纯函数；不持有事务；并发调用互不影响。
- 日志字段：`table`、`limit`、`elapsed_ms`；禁记 `where` 里的字面量。
- 测试 ID：`T-3.8-01`

### 3.9 `AppState.applyRowEdits(_:on:key:)`

- 所属单元：`App/AppState.swift` ｜ 对应概设条款：概要设计 §4.6
- 用途：把行编辑按主键写回，逐行报结局。状态：**未实现**（登记于 §10.1），本签名为实现时的目标契约。
- 前置条件：
  - [ ] 结果集存在可定位标识（主键或唯一键），否则不开放行编辑入口（`DATA_NO_PK`）
  - [ ] 连接非只读（`policy.isReadOnly == false`）
  - [ ] 每条改动带旧值快照，写回语句带主键条件与旧值条件
- 后置条件：
  - [ ] 逐行返回结局：成功 / 影响 0 行（冲突）/ 失败（原话）
  - [ ] 影响 0 行必须报 `DATA_WRITE_CONFLICT`，不得当成功
  - [ ] 成功的行更新本地快照；失败的行保留用户输入
  - [ ] 写回语句逐条执行，不并发
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 无可定位标识 | `DATA_NO_PK` | 不开放入口并说明原因 | 否 | 禁止按「全列相等」猜行 |
| 影响 0 行 | `DATA_WRITE_CONFLICT` | 逐行结局：冲突 + 原话 | 人工（重新读行） | 禁止当成功；禁止整批回滚后报成功 |
| 服务端拒绝 | `DATA_WRITE_FAILED` | 逐行结局：失败 + 原话 | 否 | 禁止改写成模糊文案 |
| 只读连接 | `EXEC_READONLY_DENIED` | 拒绝并不渲染写入口 | 否 | 禁止只灰掉按钮 |
| 依赖超时 | `DATA_WRITE_FAILED` | 逐行结局：失败 | 人工 | 禁止自动重发写语句 |

- 禁止行为：
  - 禁止无 WHERE 的整表写回。
  - 禁止把「部分行成功」汇总成一条成功提示。
  - 禁止在写回途中重新排列行的执行顺序。
- 并发·幂等·事务：以主键为幂等键；同一行重复写回结果一致（旧值条件不满足时报冲突）；一批写回在一个事务内，冲突行不阻断其他行，但必须逐行如实上报。
- 日志字段：`connection_id`、`table`、`row_key`、`outcome`、`affected_rows`；禁记列值原文。
- 测试 ID：`T-3.9-01`

### 3.10 `SchemaScriptRunner.run(script:previewed:confirmedTableName:)`

- 所属单元：`Core/TableDesign.swift` 与新增执行闸 ｜ 对应概设条款：概要设计 §4.7
- 用途：在「已预览 + 已二次确认」两个前提下执行结构脚本。状态：**未实现**（登记于 §10.1），`TableDesign.validate(tableName:columns:)` 已实现并列定义校验。
- 前置条件：
  - [ ] `script` 由 `TableDesign` 生成且与预览时展示的文本逐字节相同
  - [ ] `previewed == true`（未预览直接拒绝）
  - [ ] 删除类动作必须手输表名且与目标表相等（`confirmedTableName`）
  - [ ] 连接与任务均非只读；任务影响行数上限未越界
- 后置条件：
  - [ ] 返回执行结局与回执读数（成功/失败、耗时、错误原文）
  - [ ] 删表语句带「存在才删」语义
  - [ ] 执行后写执行记录与审计；「预览成功」不得记为「执行成功」
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 未预览即执行 | `DDL_PREVIEW_REQUIRED` | 拒绝并回预览步骤 | 否 | 禁止把脚本当普通查询静默执行 |
| 未二次确认 | `DDL_CONFIRM_REQUIRED` | 拒绝并要求确认 | 否 | 禁止默认确认 |
| 只读连接或只读任务 | `EXEC_READONLY_DENIED` | `.refused` | 否 | 禁止为 DDL 开旁路 |
| 服务端拒绝 | `DDL_FAILED` | 抛出服务端原话 | 人工 | 禁止改写成模糊文案 |
| 依赖超时 | `DDL_FAILED` | 抛出（含语句） | 人工（重跑需重新预览） | 禁止超时后自动重发 DDL |

- 禁止行为：
  - 禁止跳过预览；禁止把预览文本与实际执行文本分成两份来源。
  - 禁止在生成的脚本里写入用户数据或口令。
  - 禁止对影响行数超上限的任务继续执行。
- 并发·幂等·事务：同一表同一时刻只允许一个结构变更任务（以表名为锁键）；DDL 不幂等，重跑需重新预览与确认；执行期不与其他写语句共用事务。
- 日志字段：`connection_id`、`table`、`script_kind`、`previewed`、`outcome`、`elapsed_ms`；禁记脚本里的敏感字面量。
- 测试 ID：`T-3.10-01`（预览闸）、`T-3.10-02`（只读与上限）

### 3.11 `ResultExporter.text(for:format:tableName:schema:dialect:)`

- 所属单元：`Core/ResultExporter.swift` ｜ 对应概设条款：概要设计 §4.8
- 用途：把结果集渲染成 CSV / JSON / TSV / Markdown / INSERT 文本。
- 前置条件：
  - [ ] `format` ∈ `ResultExportFormat` 闭集
  - [ ] 结果集列结构完整（列名非空、行数与列数一致）
  - [ ] 生成 INSERT 时 `dialect` 非空（标识符引用随方言）
- 后置条件：
  - [ ] 返回字符串；列顺序与 `result.columns` 一致
  - [ ] 单元格内的分隔符、引号、换行按格式规范转义
  - [ ] 同一 `(result, format, tableName, schema, dialect)` 输出逐字节一致
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 格式不在闭集 | `IO_FORMAT_UNSUPPORTED` | `AppError.notImplemented` | 否 | 禁止生成不支持格式的空文件 |
| 编码与格式组合不适用 | `IO_FORMAT_UNSUPPORTED` | `ResultExportEncodingError.notApplicableToFormat` | 否 | 禁止静默忽略编码参数 |
| 列结构不齐 | `IO_PARTIAL` | 抛出并指明列名 | 否 | 禁止补空列后照常导出 |
| 依赖超时 | 不适用（纯内存渲染） | 不适用 | 不适用 | 禁止在此处读整表到内存 |

- 禁止行为：
  - 禁止把口令、连接串原文、凭据引用写进导出文本。
  - 禁止在导出路径上先把整表载入内存（流式写由调用方按批喂入）。
  - 禁止按界面当前排序改写结果顺序（顺序以结果集为准）。
- 并发·幂等·事务：纯函数；不持有事务；不共享可变状态。
- 日志字段：`format`、`row_count`、`column_count`、`elapsed_ms`；禁记单元格原文。
- 测试 ID：`T-3.11-01`

### 3.12 `TableImport.plan(source:target:mapping:mode:)`

- 所属单元：`Core/TableImport.swift` ｜ 对应概设条款：概要设计 §4.8
- 用途：把导入源按目标列映射编成可执行计划（逐条 INSERT 或 `COPY` 批次），并在落地前校验。
- 前置条件：
  - [ ] `source` 的列数与 `mapping` 一致；`mapping` 每项指向目标表真实列
  - [ ] `mode` ∈ `ImportWriteMode` 闭集（新建 / 追加 / 覆盖）
  - [ ] 覆盖模式下目标表存在性已询问过用户并得到明确答复
- 后置条件：
  - [ ] 返回 `Plan`：语句批次、每批行数、目标列顺序
  - [ ] 值类型转换按 `valueType(forTypeName:)` 判定；不可转的值进 `invalidValues`
  - [ ] 批次划分固定（不随机分批），同一输入同一切分
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 目标已存在且未确认 | `IO_TARGET_EXISTS` | 拒绝并回询问 | 不适用（等答复） | 禁止静默覆盖既有表 |
| 部分行不可转 | `IO_PARTIAL` | 返回 `invalidValues` 明细 | 人工 | 禁止丢坏行后报全部成功 |
| 列不匹配 | `IO_FORMAT_UNSUPPORTED` | 抛出并指明列 | 否 | 禁止按位置硬塞 |
| 导入中途失败 | `IO_PARTIAL` | 逐批结局：成功批与失败批 | 人工 | 禁止留半张表且不告知 |
| 依赖超时 | `IO_PARTIAL` | 逐批结局：失败批 | 人工 | 禁止超时后自动重发整批 |

- 禁止行为：
  - 禁止在失败后静默删除已导入数据来「假装没发生」。
  - 禁止在方言不支持 `COPY` 时悄悄退回逐条 INSERT 而不告知。
  - 禁止把凭据或连接串写进导入日志。
- 并发·幂等·事务：以「目标表 + 批次序号」为幂等键；同一批重跑会重复写入，故重跑前必须清目标或换模式；批次各自成事务，不做跨批大事务。
- 日志字段：`table`、`batch_index`、`row_count`、`invalid_count`、`elapsed_ms`；禁记行值原文。
- 测试 ID：`T-3.12-01`

### 3.13 `SessionMonitor.sessions(from:)`

- 所属单元：`Core/SessionMonitor.swift` ｜ 对应概设条款：概要设计 §4.9
- 用途：把服务端会话查询结果映射成会话列表（进程号、用户、库、状态、等待事件、已运行时长、当前 SQL）。
- 前置条件：
  - [ ] `result` 的列名可被识别（兼容 `pg_stat_activity` 与 `SHOW PROCESSLIST` 两套命名）
  - [ ] 已连接且当前用户有读会话视图的权限
- 后置条件：
  - [ ] 返回 `ServerSession` 数组；无法解析出进程号的行被丢弃并可报数
  - [ ] 多行 SQL 压成一行供列表显示（`summarize(_:limit:)`）
  - [ ] 时长由 `elapsedSeconds(since:now:)` 计算，解析失败返回 nil 并显示原始字符串
  - [ ] 只映射，不发取消、不终止任何会话
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 无权限读会话视图 | `SESS_KILL_DENIED` 不适用；此处 `META_UNSUPPORTED` | 抛出并说明缺哪个权限 | 否 | 禁止显示空列表冒充「没有会话」 |
| 时间戳形态不可解析 | 不适用（返回值） | `nil`，界面显示原串 | 不适用 | 禁止猜一个时长 |
| 终止会话（动作路径） | `SESS_KILL_DENIED` | 上浮服务端原话 | 否 | 禁止无二次确认就终止 |
| 终止前未确认 | `SESS_KILL_REQUIRED_CONFIRM` | 拒绝 | 不适用 | 禁止默认确认 |
| 依赖超时 | `META_FAILED` | 抛出（含耗时） | 是，重试 1 次 | 禁止超时后返回半份列表并标成功 |

- 禁止行为：
  - 禁止不说明「会掐断连接并回滚未提交事务」就执行终止。
  - 禁止把「读列表」与「终止」合成一个动作。
  - 禁止在会话视图里展示其他连接的会话（作用域限当前连接）。
- 并发·幂等·事务：读取幂等；终止动作不幂等，重复终止报 `SESS_NOT_FOUND`；不在事务内终止。
- 日志字段：`connection_id`、`session_count`、`action`、`target_pid`、`outcome`；禁记会话当前 SQL 原文中的敏感字面量。
- 测试 ID：`T-3.13-01`

### 3.14 `AgentContext.assemble(_:limits:)`

- 所属单元：`Core/AgentContext.swift` ｜ 对应概设条款：概要设计 §4.10
- 用途：把当前连接、库表、选中 SQL 的文本与标识装配成投给助理的上下文摘要。
- 前置条件：
  - [ ] 每条 `AgentContextReference` 指向当前工作区可见对象
  - [ ] 含结果行数据时必须带用户显式确认标记；无标记即拒
  - [ ] `limits` 给出单段与总长上限
- 后置条件：
  - [ ] 返回可核对的摘要（投了什么、多长、是否含行数据）
  - [ ] 含行数据的投递写一条审计（谁、何时、哪条连接、投了什么类型）
  - [ ] 凭据、连接串原文、口令一律被 `filterSecretsOnly` 剥掉
  - [ ] 超限内容是报错，不静默截断
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 含行数据未确认 | `BRIDGE_ROW_DATA_REQUIRES_CONFIRM` | 拒绝并说明需确认 | 不适用（等确认） | 禁止静默投递行数据 |
| 上下文为空 | `BRIDGE_EMPTY_CONTEXT` | 拒绝 | 否 | 禁止投一条空上下文占位 |
| 超长 | `BRIDGE_EMPTY_CONTEXT` 不适用；超限按错误返回 | 抛出超限说明 | 人工（缩小范围） | 禁止静默截断后当完整上下文 |
| 依赖超时 | 不适用（本地装配） | 不适用 | 不适用 | 禁止在装配期发起网络调用 |

- 禁止行为：
  - 禁止投递凭据或连接串原文。
  - 禁止让助理据此直接执行写操作而不经 §3.6 的审批链。
  - 禁止把「自动附带」当默认值（概要设计 §14.1 第 6 条：默认关闭，仅显式勾选时附带并写审计）。
- 并发·幂等·事务：装配幂等（同输入同摘要）；不持有事务；审计为追加写，不覆盖。
- 日志字段：`connection_id`、`reference_count`、`contains_row_data`、`total_chars`、`at`；禁记被投递的正文。
- 测试 ID：`T-3.14-01`

### 3.15 `AgentStandardDispatcher.dispatch(_:approvals:)`

- 所属单元：`Core/AgentStandardDispatcher.swift` ｜ 对应概设条款：概要设计 §18.1
- 用途：执行一个模型发起的工具调用，返回观察值。
- 前置条件：
  - [ ] `invocation` 的工具名在 `AgentToolRegistry` 里已登记
  - [ ] 参数 JSON 通过 `AgentToolSchemaValidator.validate(argumentsJSON:against:)`
  - [ ] 需审批的工具，其 `fingerprint` 在 `approvals` 集合里且已被消费
- 后置条件：
  - [ ] 返回 `AgentToolOutcome`；拒绝类返回 `AgentToolRefusal` 机器码
  - [ ] 观察值有界：超限报错，不静默截断
  - [ ] 每次调用留审计（工具名、参数摘要、结局）
  - [ ] 拒绝时不产生任何副作用（不写文件、不执行 SQL）
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 工具未登记 | `META_UNSUPPORTED` | `AgentToolOutcome` 失败 + 机器码 | 否 | 禁止执行未登记工具 |
| 参数不合规 | `CONN_INVALID_CONFIG` 不适用；返回模型可读错误 | 失败 + 校验明细 | 是（模型改参数后重试） | 禁止「宽容解析」后照执行 |
| 未获审批 | `EXEC_CONFIRM_REQUIRED` | `AgentToolRefusal` | 不适用（等审批） | 禁止绕过审批执行写操作 |
| 工具内部超时 | `EXEC_SERVER_ERROR` | 失败 + 原因码 | 是，重试 1 次（仅只读工具） | 禁止对写工具自动重试 |

- 禁止行为：
  - 禁止在参数不合规时执行工具再报错。
  - 禁止对写类工具自动重试。
  - 禁止把异常事件文案写进界面字符串（文案由语言表按机器码映射）。
- 并发·幂等·事务：同一回合内工具串行；写类工具不幂等，重跑需重新审批；预算耗尽即结束回合（`AgentLoopLimits`），不静默续命。
- 日志字段：`tool_name`、`arguments_summary`、`outcome`、`elapsed_ms`、`request_id`；禁记完整参数里的敏感字面量。
- 测试 ID：`T-3.15-01`

### 3.16 `AgentPlanRows.estimate(json:)`

- 所属单元：`Core/AgentPlanRows.swift` ｜ 对应概设条款：概要设计 §5.4
- 用途：把 `EXPLAIN (FORMAT JSON)` 的结果解析成影响行数预估四档结论。
- 前置条件：
  - [ ] `json` 来自 `EXPLAIN (FORMAT JSON) <DML>`，且该语句不带 `ANALYZE`
  - [ ] 非 DML 或多语句时上游不应调用本函数（`explainStatement(for:)` 返回 nil）
- 后置条件：
  - [ ] 返回四档之一：有值 / `noAnswer` / `parseFailed` / 上游原因码（`notDataChange`、`dialectUnsupported`、`noConnection`）
  - [ ] 根节点为 `ModifyTable` 一类且 `Plan Rows` 为 0 时取 `Plans` 的第 0 项（坑见 §13.1）
  - [ ] 取不到就返回 `noAnswer` / `parseFailed`，不返回 0
  - [ ] 结果只作批准前参考读数，不参与任何执行判定
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 没有 JSON | 不适用（结论值） | `.unavailable("noAnswer")` | 不适用 | 禁止用表总行数填充 |
| 解析失败 | 不适用（结论值） | `.unavailable("parseFailed")` | 不适用 | 禁止返回 0 当「没有影响行」 |
| 非数据变更语句 | 不适用（上游码） | `.unavailable("notDataChange")` | 不适用 | 禁止给非 DML 造一个数 |
| 方言不支持 | 不适用（上游码） | `.unavailable("dialectUnsupported")` | 不适用 | 禁止换用 `ANALYZE` 取数 |
| 依赖超时 | 不适用（解析本地 JSON） | 上游已收不到结果，走 `noConnection` | 不适用 | 禁止本地估算 |

- 禁止行为：
  - 禁止为了拿到数而执行 `EXPLAIN ANALYZE`。
  - 禁止把预估写回审批单的「已确认」字段（审批与读数是两件事）。
  - 禁止把读数写进契约文档（读数只进台账）。
- 并发·幂等·事务：纯解析；幂等；不持有事务；不发网络。
- 日志字段：`conclusion`、`plan_node`、`duration_ms`；禁记完整执行计划 JSON。
- 测试 ID：`T-3.16-01`

---

### 3.17 `AgentCommandRunner.run(_ command: String, in directory: URL, timeout: TimeInterval) async -> CommandOutcome`

- 对应概设条款：概要设计 §3 组件契约（命令执行）· §4 接口契约 · §11.4 `PERF-006`
- 用途：在本机跑**一条**命令，带回标准输出、标准错误与退出码。**它是 Agent 侧唯一起进程的入口**。

**前置条件**
- `directory` 必须是用户已授权的工作区目录（`WorkspaceAccessScope` 判定为真）；未授权 ⇒ 直接返回 `.refused(.directoryNotAuthorized)`，**不落任何进程**。
- `command` 非空且不含 NUL；`timeout` ∈ [1, 600]，缺省取配置 60 s。

**后置条件**
- 成功：返回 `.finished(exitCode:stdout:stderr:truncated:)`，`exitCode == 0` 才算成功。
- 失败：返回 `.finished(exitCode: != 0)` 或 `.timedOut` / `.refused(reason)`，**三者互斥且必须有一个**。
- 输出超 2000 行或 1 MB ⇒ `truncated = true`，内容按行截断，**不静默吞**。

**错误契约**

| 情形 | 返回 | 可重试 | 说明 |
|---|---|---|---|
| 目录未授权 | `.refused(.directoryNotAuthorized)` | 否 | 不启动进程 |
| 需要 TTY 的交互式命令 | `.refused(.interactiveUnsupported)` | 否 | 不启动进程 |
| 危险形态（`DROP DATABASE` / `rm -rf` / 改系统路径 / 下载即执行） | 先出审批单（含完整命令），**批准前不启动** | 否 | 审批拒绝 = `.refused(.approvalDenied)` |
| 超时 | `.timedOut` | 是（同一命令最多 1 次，超时不自动重试） | 进程必须被**终止并回收**，不留下孤儿 |
| 二进制不存在 | `.finished(exitCode: 127, stderr: …)` | 是（同一命令最多 1 次，超时不自动重试） | 原样回传，不翻译成「未知错误」 |

**禁止行为**
- 禁止用 `sh -c` 拼接未转义的模型参数（一律 argv 直传；需要 shell 语法时必须走同一审批）。
- 禁止在**主线程**或界面同步链路上起进程。
- 禁止把非零退出码包装成「已完成」，也禁止在输出里塞进自己编的摘要替代原文。

**并发 / 幂等 / 事务**
- 同一会话内**串行**执行（一个 runner 一条跑道）；并发发起时排队，不并行起两个进程。
- 无事务概念；命令本身的副作用由审批与审计兜底，本层不做回滚。

**日志字段**（写审计，不写会话正文）
- 必记：`commandHash`（sha256 前 16 位）· `directory`（绝对路径）· `exitCode` · `durationMs` · `truncated` · `approvalID`（有审批时）。
- 禁记：命令的完整原文（脱敏后只留前 120 字）· 任何口令 / token · 标准输出原文。

**测试 ID**：`T-3.17-01`（正例：退出码 0 且带回 stdout）· `T-3.17-02`（负例：未授权目录被拒且未起进程）· `T-3.17-03`（负例：超时被终止且不留孤儿）· `T-3.17-04`（负例：危险形态进审批，拒绝后未执行）


### 3.18 `AgentCodeRunner.run(_ code: String, language: AgentCodeLanguage, in directory: URL) async -> CodeOutcome`

- 对应概设条款：概要设计 §3 组件契约（代码执行）· §11.4 `SEC-005`（默认零外发）

**前置条件**：`directory` 为授权工作区目录；`language` ∈ {python, shell}（本机已装版本，缺失则 `.refused(.interpreterMissing)`）；`code` 非空。

**后置条件**：`.finished(exitCode:stdout:stderr:truncated:)` / `.timedOut` / `.refused(reason)` 三选一且必有一个；临时文件落会话临时目录并在返回前删除。

**错误契约**

| 情形 | 返回 | 可重试 | 说明 |
|---|---|---|---|
| 解释器未安装 | `.refused(.interpreterMissing)` | 否 | 报「未安装 <lang>」，不自动联网安装 |
| 超时（默认 30 s） | `.timedOut` | 否 | 子进程终止并回收 |
| 内存超 512 MB | `.refused(.memoryLimit)` | 否 | 内核级限制，先于 OOM |
| 试图联网 | `.refused(.networkForbidden)` | 否 | 沙箱无网络出口；命中即拒并记审计 |
| 退出码非零 | `.finished(exitCode: != 0)` | 是（同一段最多 1 次） | 原样回传 stderr |

**禁止行为**：禁止继承宿主全部权限；禁止写授权目录外路径；禁止在界面线程运行；禁止把失败包装成「已完成」。

**并发 / 幂等 / 事务**：同会话串行；每次运行独立临时目录；无事务（改盘走 §3.1 `edit_file`）。

**日志字段**：必记 `codeHash`（sha256 前 16 位）· `language` · `exitCode` · `durationMs` · `truncated`；禁记代码原文与 stdout 全文。

**测试 ID**：`T-3.18-01`（正例：退出码 0 且带回 stdout）· `T-3.18-02`（负例：试图联网被拒且零外发）· `T-3.18-03`（负例：超时终止、临时目录已清）

### 3.19 `AgentToolCatalog.search(_ query: String, limit: Int) async -> [AgentToolCandidate]`

- 对应概设条款：概要设计 §3 组件契约（工具目录）

**前置条件**：`limit ∈ [1,20]`（超上限按 20 截断）；`query` 非空。

**后置条件**：返回候选（名 / 用途一句 / 来源内置或接入）；同一会话内 schema 取回后缓存，二次取回不发请求；未取回 schema 的调用由派发层拒绝。

**错误契约**

| 情形 | 返回 | 可重试 | 说明 |
|---|---|---|---|
| 无匹配 | `[]` + `hint = .noSuchTool` | 是（换词） | 不回退到全表 |
| 超过 limit | 截断 + `remaining` 计数 | 否 | 界面显示「还有 N 件」 |
| 接入类工具离线 | 该件标 `unavailable` | 是 | 目录仍返回，不整表失败 |

**禁止行为**：禁止把全部工具塞进上下文；禁止替模型选择；禁止对未登记名字静默回退。

**并发 / 幂等 / 事务**：只读，可并发；同 query 结果 60 秒内复用。

**日志字段**：必记 `queryHash` · `hitCount` · `limit`；禁记 query 原文（含用户意图）。

**测试 ID**：`T-3.19-01`（按用途检索命中内置与接入两类）· `T-3.19-02`（未取回 schema 直接调用被拒）

### 3.20 `AgentOrchestrator.run(_ tasks: [Subtask], options: OrchestrationOptions) async -> [SubtaskOutcome]`

- 对应概设条款：概要设计 §3 组件契约（并行编排）· §11.4 `AI-004`（配额与超时）

**前置条件**：`tasks` 非空且两两**无依赖**（有依赖者由调用方先排序，本层不猜顺序）；`options.maxConcurrency` ∈ [1,8]，缺省 4；每个 `Subtask` 带 `id`、`goal`、`workdir`；子任务 `depth` 必须为 0（**禁止再派**）。

**后置条件**：返回数组与输入**等长同序**，每项含 `id` / `outcome`（finished / failed / timedOut / cancelled）/ `summary` / `artifactPaths`；超并发上限的任务**排队后仍全部执行完**；单路失败不改变其余各项。

**错误契约**

| 情形 | 返回 | 可重试 | 说明 |
|---|---|---|---|
| 有依赖却并发提交 | `.refused(.dependencyCycleOrOrder)` | 否 | 先排序再提交 |
| 超并发上限 | 排队（不报错） | — | 按到达序启动 |
| 单路超时（默认 10 min） | 该路 `.timedOut` | 否 | 终止该路，其余继续 |
| 子执行体试图再派 | 该路 `.failed(.nestedDelegationForbidden)` | 否 | 深度锁死为 0 |
| 需审批动作 | 主控出审批单，该路挂起等待 | 是（批准后继续） | 子执行体不得代签 |

**禁止行为**：禁止把有依赖的步骤并发；禁止无上限并发；禁止让子执行体继承主控的凭据与授权；禁止归并时收整段上下文（只收摘要与产物路径）。

**并发 / 幂等 / 事务**：并发度由 `options.maxConcurrency` 控制；同一 `Subtask.id` 重复提交幂等（返回已有结局）；无跨子任务事务。

**日志字段**：必记 `runID` · 每路 `subtaskID` / `outcome` / `durationMs` / `depth`；禁记子任务 prompt 原文（只记 `goalHash`）。

**测试 ID**：`T-3.20-01`（三路并行全部完成且等长同序）· `T-3.20-02`（并发上限 4：第 5 路排队后仍完成）· `T-3.20-03`（一路失败其余不受影响）

## 4. 数据与状态

### 4.1 内部结构映射

| 概设实体 | 本端类型 | 关键字段 | 序列化契约 | 允许写入方 |
|---|---|---|---|---|
| 连接配置 | `ConnectionConfig` | id / name / dbType / host / port / database / username / sslMode / timeout / schemaVersion / isReadOnly / group / sshTunnel | JSON，字段名即属性名；日期 `ISO8601`；缺省值用 `null` 不用空串；口令不入结构体 | 连接表单 → `ConnectionStore` |
| 凭据 | 密钥存储条目 | 键 = 连接 id | 系统密钥存储，不落明文 | `Platform/macOS/KeychainSecretStore.swift` |
| 执行记录 | `QueryHistory` | 归档日 / SQL 文本 / 连接 id / 目标库 / 时刻 / 耗时 / 重复次数 | 按天一份；JSON 行；时间 `ISO8601` | 执行路径 → `QueryHistoryStore` |
| 任务定义 | 任务配置件 | 目标库 / 读写模式 / 影响行数上限 / 是否需审批 | JSON；布尔显式写 `true`/`false` | 任务面板 |
| 审批与回执 | `AgentApprovalConsumption` | requestID / fingerprint / 时间 | 追加式 JSON 行，防重放 | `AgentApprovalGate` |

### 4.2 存储契约

| 存储 | 主键 | 约束 | 允许写入方 | 迁移策略 |
|---|---|---|---|---|
| 连接清单文件 | 连接 `id` | 名称同工作区唯一；端口 1…65535；`schemaVersion` 非空 | `ConnectionStore` | `schemaVersion` 升级一次，旧文件先备份再写 |
| 查询历史（本机库） | 自增 | 只本机不上传；上限 500 条 / 90 天先到者为准 | `QueryHistoryStore` | 只增不改 |
| 审批消费记录 | requestID | 追加式，不覆盖；同 fingerprint 只一条 | `AgentApprovalGate` | 只增不改 |
| 笔记库（SQLite） | note id | 本体 / 标签 / 时间线同事务；正文权威源是 span 树 | `NoteLibrary` | 迁移只增不改 |
| 审计日志 | 追加序号 | JSONL 追加，不删不改 | `AgentAudit`、`EgressLog` | 只增不改 |

- 事务边界：一次业务动作一个事务；归档与审计属「动作后置」，失败只报「记录未落盘」，不回滚已成功的业务执行。
- 迁移文件只增不改：`Plugins/Notes/Sources/` 下的迁移脚本与 `Core/` 的 schema 版本号表，历史条目禁止编辑。

### 4.3 算法伪代码

- 对应概设：概要设计 §7.1（查询执行全链）

```text
输入：编辑器文本 T、选区 S、连接 C、目标库 DB、事务模式 M
1  若 C 未连接 → 报 EXEC_NO_CONNECTION 并停
2  Q ← S 非空 ? S : T              # 有选区只跑选区，无选区跑整篇
3  若 Q 为空 → 报 EXEC_EMPTY_SQL 并停
4  D ← ExecutionSafety.check(Q, policy)   # refused → 停；需确认 → 等确认
5  M 为手工事务且未开事务 → beginTransaction
6  for 每条语句 in 按文本顺序切分(Q):
7      上报「第 N 条」→ 执行 → 收 resultSet（全保留）
8      失败 → 报 EXEC_SERVER_ERROR（含序号与原文）→ 停，事务标记未知
9  全部完成 → 汇总行列数与耗时 → 写历史与归档 → 审计一条
```

- 对应概设：概要设计 §7.2（结构变更与高危写）

```text
输入：列定义 L、目标表 TB、脚本种类 K、连接 C
1  issues ← TableDesign.validate(TB, L)；issues 非空 → 停并逐条显示
2  script ← 生成脚本(K, TB, L)        # 不执行
3  展示 script + TB + K；预览未完成 → 停
4  K 为删表/清表 → 要求手输表名；不一致 → 停
5  refusals ← ExecutionSafety.check(script)   # refused → 停
6  执行 → 回执（成功/失败、耗时、错误原文）→ 写执行记录与审计
```

### 4.4 状态覆盖清单

| 状态机 | 当前 → 目标 | 触发 | guard / 抛出 | 测试 ID |
|---|---|---|---|---|
| 连接 | 未连接 → 连接中 | 建立请求且校验通过 | `ConnectionConfig` 校验失败抛 `AppError.invalidConfiguration` | `T-4.4-01` |
| 连接 | 失败 → 已连接 | — | **禁止**跳转，必须先经连接中再握手 | `T-4.4-02` |
| 语句执行 | 待发 → 执行中 | 开始执行 | 空 SQL 被拦（`EXEC_EMPTY_SQL`），不进入执行中 | `T-3.3-03` |
| 语句执行 | 执行中 → 已取消 | 取消请求 | `cancel` 成功且不再收 `resultSet` | `T-4.4-03` |
| 语句执行 | 已取消 → 已完成 | — | **禁止**；重跑是一次新执行 | `T-4.4-04` |
| 审批单 | 已拒绝 → 已批准 | — | `AgentApprovalVerdict` 不可翻 | `T-4.4-05` |
| 审批单 | 已过期 → 已批准 | — | 过期即 `.expired`；按概要设计 §14.1 第 4 条暂定口径 = 拒绝 | `T-4.4-06` |
| 查询页签 | 执行中 → 已关闭 | 关闭请求 | 拒绝并提示「执行中，请先停止」 | `T-4.4-07` |
| 查询页签 | 有未保存改动 → 已关闭 | 关闭请求 | 需确认后进会话快照；保存失败时脏标记不回退 | `T-4.4-08` |

实现口径：`AgentApprovalVerdict` 还有第五档 `.missing`（无记录）。它不是概要设计 §6.3 的四态之一，语义等价于「不能批准」，禁止被当成通过；判定落点见 §3.6。

- 闭集约束：禁止新增未列出的状态或事件；禁止绕过 guard 直接赋值状态；`ConnectionState` / `QueryEvent` / `AgentApprovalVerdict` / `QueryTabState` 四个枚举新增 case 必须先改概要设计 §6。

### 4.5 笔记模块（域契约 = 概要设计 §15）

- `NoteLibrary` 是 actor：库连接只在它内部持有，界面层拿不到连接。
- `NoteDatabase` 负责 SQLite；本体 + 标签 + 时间线**同一事务**写入，失败整笔回滚。
- 正文权威源是 span 树，正文视图是投影；投影与正文不一致时按 span 树重投影，不反向写。
- `NoteAutosave` 合并窗口 1.5 s（比工作区编辑器的 0.12 / 0.45 s 大，自动保存是落盘不是重绘）；三条守卫（许可 / 有内容 / 有改动）缺一不写；`idle` / `pending` / `failed` 三态，`pending` 期间再编辑保持 pending 并重排，不丢新按键；切走时先快照再排队。
- `CloudSyncService` 管同步态，`SyncQueue` 串行单飞；401 ⇒ 续期一次并重放一次，仍失败则降级但保留队列；续期失败不当作登出；登录态与同步态不合并。
- 私密保护与加密边界、回收站与历史版本、待办与日历：落点在 `Plugins/Notes/Sources/`，本仓只做宿主装配与能力位判定，业务判据在笔记分册自跑。

### 4.6 会话与搜索

- `AgentSessionStore`：一会话一文件，文件名即 id；`summaryList(workspace:)` 含跳过文件数（跳过不许静默）。
- 搜索按 `Character` 偏移切分（不按 utf8/utf16，否则中文错位）；命中不重叠；返回 `total` 与 `firstMatchID` 供跳转。
- `AgentChatModel` 只读派生；打开会话要显式切 `sessionID`，不隐式切。
- 命令面板是全产品命令的唯一输入面（`AppCommandCatalog` 为唯一出处），新增命令必须同时登记目录与 `Scripts/check-palette-wiring.py`。

### 4.7 复盘宿主（概要设计 §16 域）

- 本端**只做宿主装配**：`App/Views/RetroHostView.swift` 承载复盘插件的界面槽位；复盘实现本体在独立仓（`retro`），不在本仓。
- 契约口径：概要设计 §16 十八节（行情接入 / 特征 / 回测 / 复盘稿 / 周报）由复盘仓实现；本端只保证宿主侧「插件装配 + 单向上下文 + 数据家隔离」。
- 禁止：把复盘业务逻辑写进 Studio 仓；让复盘插件反向依赖 Studio 装配层；宿主向复盘插件回写其数据家。
- 判据：宿主装配门禁（插件装载 6 组绿）+ `RetroHostView` 可挂载；业务判据在复盘仓自跑（`T-4.7-01` 标「他仓」）。

### 4.8 工作区编辑器与外部改动（概要设计 §7.3）

- 脏标记唯一来源：编辑器缓冲与上次落盘内容的比对；`isDirty` 只在保存成功后清零。
- 保存：有路径直接写回；无路径走系统保存面板；保存失败不得清脏标记、不得关闭页签。
- 外部改动：监听磁盘变更 → 提示「磁盘上已变」→ 二选一（重新载入 / 保留本地）；禁止静默覆盖任何一侧。
- 编码与换行：识别结果必须显示在状态行；禁止把猜测结果写回文件而不告知。
- 撤销粒度合并窗口：0.12 s（输入）/ 0.45 s（结构输入），两档都写在编辑器状态机里，不在视图层各写一份。

---

## 5. 界面实现

### 5.1 视图与组件落点

| 概设视图（§8.2） | 本端视图/组件 | 依赖接口 | 备注 |
|---|---|---|---|
| 查询页签 | `App/Views/CodeEditorView.swift` + `ResultTableView.swift` | 概要设计 §4.3 / §4.4 | 执行/停止按钮状态互换 |
| 结果区 | `App/Views/ResultTableView.swift` | 概要设计 §4.3 / §4.8 | 多结果集切换器、导出入口 |
| 连接表单 | `App/Views/ConnectionFormView.swift` | 概要设计 §4.1 | 类型切换联动默认端口与 SSL |
| 连接清单 | `App/Views/ConnectionListView.swift` | 概要设计 §4.1 / §4.2 | 删除二次确认并明说连带删凭据 |
| 对象树 | `App/Views/ObjectTreeView.swift` + `BrowseRowsSheet.swift` | 概要设计 §4.5 / §4.6 | 刷新不清选中 |
| 表设计 | `App/Views/TableDesignSheet.swift` | 概要设计 §4.7 | 预览与执行是两个动作 |
| 导入导出 | `App/Views/ImportPanel.swift` + `BackupRestoreSheet.swift` | 概要设计 §4.8 | 部分失败列明细 |
| 会话视图 | `App/Views/SessionPanel.swift` + `AgentAuditPanel.swift` | 概要设计 §4.9 | 四项读数 + 确认终止 |
| 对话页签 | `App/Views/AgentChatView.swift` | 概要设计 §4.10 / §4.3 | 工具卡片可展开 |
| 审批 | `App/Views/AgentApprovalSheet.swift` | 概要设计 §5.4 | 逐条列语句与目标库 |
| 浏览页签 | `App/Views/BrowserTabView.swift` | 概要设计 §3.1 | 与文件页签同类，可 ⌘W |
| 命令面板 | `App/Views/CommandPaletteView.swift` | 命令目录 | 全局搜索唯一输入面 |

- 视图清单外的入口一律不得新增：`Scripts/check-palette-wiring.py` 的「未登记差集」必须为 0。

### 5.2 状态来源与刷新

- 视图状态从 `AppState`（`@MainActor`）单向派生；视图不缓存可写副本。
- 刷新路径：能力层事件 → 装配层折叠值 → 主线程更新；禁止视图轮询、禁止双写。
- 派生值（行数、耗时、可编辑判定）只在装配层算一次，视图只读。

### 5.3 组件级六态契约

> 六态 = 加载中 / 空数据 / 错误 / 权限不足 / 提交中 / 部分失败。每个组件六行齐；「禁止渲染」列逐行给出必须为空的渲染结果，任一行留空即判缺陷（`UI-5.3-01`）。

#### 5.3.1 查询页签 `QueryTabView`

- 对应概设条款：概要设计 §8.4 / §8.5 / §8.7
- 输入（Props）：`tabID`、`connectionID?`、`database?`、`sql`、`isReadOnly`
- 内部状态：`isExecuting`、`results`、`selectedResultIndex`、`errorMessage`、`statusMessage`、`isSaving`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | `isExecuting == true` | 执行按钮换停止 + 逐条进度 | 空白结果区；允许重复点执行 |
| 空数据 | `results.isEmpty && !isExecuting && errorMessage == nil` | 空态文案 + 「执行当前 SQL」引导 | 错误件；无说明的空白页 |
| 错误 | `errorMessage != nil` | 错误件（原因 + 语句序号 + 位置）+ 重试入口 | 静默失败；空结果冒充成功 |
| 权限不足 | `ExecutionSafety.Decision.refused` | 只读原因 + 涉事语句 | 灰色「仍然执行」入口；先渲染再报错 |
| 提交中 | `isSaving == true` | 按钮进行中态 + 禁用 | 重复发起第二次保存 |
| 部分失败 | 多语句汇总含失败条 | 逐条列成功/失败 + 行数 | 整体报成功；丢失败条 |

- 副作用：执行成功写历史与审计；取消写「已取消」结局；关闭页签走 §4.4 页签 guard。
- 禁止行为：失败后清空编辑器；只改界面状态冒充取消；把多结果集折叠成一个。

#### 5.3.2 连接表单 `ConnectionFormView`

- 对应概设条款：概要设计 §8.4 / §8.6
- 输入：`mode`（新建 / 编辑）、`ConnectionConfig?`、`databases`（已接入类型）
- 内部状态：`draft`、`fieldErrors`、`isSubmitting`、`testResult`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | `isTesting == true` | 试探连接进度 + 表单禁用 | 无反馈地卡住按钮 |
| 空数据 | `databases.isEmpty` | 「无可用类型」+ 引导 | 空下拉可提交 |
| 错误 | `fieldErrors` 非空或 `testError` | 字段下方错误 + 原因原话 | 只弹全局提示 |
| 权限不足 | 授权能力位缺失 | 明说缺哪个能力位与怎么给 | 先展示表单再报错 |
| 提交中 | `isSubmitting == true` | 提交按钮进行中态 + 禁用 | 重复提交产生两条连接 |
| 部分失败 | 校验通过但试探连接失败 | 保存结果与试探结论分开列 | 试探失败却把配置标成已就绪 |

- 副作用：保存成功刷新清单并保持选中；试探连接不写盘。
- 禁止行为：明文口令回显；端口越界静默夹取；类型切换不联动默认 SSL。

#### 5.3.3 连接清单 `ConnectionListView`

- 对应概设条款：概要设计 §8.4 / §8.7
- 输入：`ConnectionConfig` 数组、选中 id
- 内部状态：`pendingDelete`、`isDeleting`、`errorMessage`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | `isLoading == true` | 列表骨架 + 禁用删除 | 空白列表冒充无连接 |
| 空数据 | `connections.isEmpty` | 空态文案 + 「新建连接」 | 错误件 |
| 错误 | `errorMessage != nil` | 原因 + 重试 | 空列表冒充成功 |
| 权限不足 | 无授权能力位 | 入口不出现 | 灰色条目诱导点击 |
| 提交中 | `isDeleting == true` | 该行进行中态 + 全局禁用重复删 | 重复发删除请求 |
| 部分失败 | 删除成功但凭据清理失败 | 明说残留位置 | 报整体成功 |

- 副作用：删除连带清凭据；执行中的连接不允许删除。
- 禁止行为：无确认删除；只删列表项留凭据；删除后自动切到别的连接执行。

#### 5.3.4 对象树 `ObjectTreeView`

- 对应概设条款：概要设计 §4.5 / §8.4
- 输入：连接 id、根节点、选中节点 id
- 内部状态：`expanded`、`childrenCache`、`loadingNodes`、`metaError`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | `loadingNodes` 含该节点 | 该节点加载指示 | 伪造占位子节点 |
| 空数据 | 该节点子数组为空 | 「该层无对象」 | 空白无说明 |
| 错误 | `metaError` 对该节点置位 | 节点级错误 + 重试 | 空树冒充无对象 |
| 权限不足 | `META_UNSUPPORTED` 或权限缺失 | 层级差异说明 | 抹平层级强行展示 |
| 提交中 | 刷新请求进行中 | 刷新按钮进行中态 | 重复刷新叠请求 |
| 部分失败 | 部分子节点取数失败 | 成功子节点照常 + 失败提示 | 整树清空 |

- 副作用：刷新不清选中；展开请求按 `ObjectTreeRefreshGate` 合并。
- 禁止行为：跨类型统一层级；刷新清空选择；在树里塞未授权入口。

#### 5.3.5 审批单 `AgentApprovalSheet`

- 对应概设条款：概要设计 §5.4 / §6.3 / §8.4
- 输入：`AgentApprovalRequest`、语句清单、目标库、预估读数
- 内部状态：`verdict`、`isSubmitting`、`estimate`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | 预估读数计算中 | 「预估计算中」占位 | 编造一个行数 |
| 空数据 | 语句清单为空 | 「无待审语句」并禁用批准 | 空白批准按钮 |
| 错误 | `verdict == .expired` / `.missing` | 终局说明 + 关闭 | 把过期当待审 |
| 权限不足 | 任务只读或能力位缺失 | 只读原因 + 禁止批准 | 灰掉批准但可点 |
| 提交中 | `isSubmitting == true` | 批准按钮进行中态 + 禁用 | 重复批准产生两条消费记录 |
| 部分失败 | 多语句中部分语句被 `refused` | 逐条列被拒语句 | 整单批准成功 |

- 副作用：批准按次消费（`grant`）；拒绝与过期留痕。
- 禁止行为：把 `.pending` / `.denied` / `.expired` / `.missing` 当通过；回执写口令或敏感字面量；预估取不到时编数（取不到写「未接」）。

#### 5.3.6 导入导出面板 `ImportPanel`

- 对应概设条款：概要设计 §4.8 / §8.4
- 输入：来源（结果集 / 表 / 库）、格式集合、目标路径
- 内部状态：`phase`、`writtenRows`、`failedItems`、`targetExistsPrompt`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | `phase == .running` | 已写行数 + 进度 | 无反馈的空白进度条 |
| 空数据 | 来源为空 | 「无数据可导出」 | 生成空文件并报成功 |
| 错误 | `phase == .failed` | 原因 + 重试 | 失败留半成品不说 |
| 权限不足 | 目标路径无写权限 | 明说缺哪个目录授权 | 静默改写到别处 |
| 提交中 | 导入覆盖确认未答 | 询问对话框 + 按钮禁用 | 直接覆盖既有表 |
| 部分失败 | `failedItems` 非空 | 成功项与失败项分别列出 | 整体回滚却不告知 |

- 副作用：导出流式写文件；导入逐批成事务。
- 禁止行为：把整表读进内存再写；导出夹带凭据；失败后静默删数据。

#### 5.3.7 浏览页签 `BrowserTabView`

- 对应概设条款：概要设计 §3.1 / §8.4
- 输入：`tabID`、`initialURL?`
- 内部状态：`url`、`canGoBack`、`canGoForward`、`isLoading`、`loadError`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | `isLoading == true` | 进度指示 + 刷新按钮换停止 | 白屏无反馈 |
| 空数据 | `url == nil` | 地址栏 + 起始页 | 空白页冒充已加载 |
| 错误 | `loadError != nil` | 错误页（URL + 原因）+ 重试 | 空白页冒充 200 |
| 权限不足 | 目录授权或网络策略拒绝 | 明说缺哪个授权 | 静默拦请求 |
| 提交中 | 表单提交中（页面内） | 保持页面可交互并显示进行中 | 重复提交 |
| 部分失败 | 页面资源部分加载失败 | 已加载内容 + 失败资源提示 | 整页清空 |

- 副作用：导航历史进页签模型；关闭走页签 guard（执行中页签无此态）。
- 禁止行为：把浏览页签并入 SQL 工作区；跨页签共享登录态以外的用户数据；预览侧改写源文件。

#### 5.3.8 Agent 对话页签 `AgentChatView`

- 对应概设条款：概要设计 §4.10（助理上下文传递）/ §8.4（界面状态契约）/ §15（笔记侧 Markdown 单一口径）
- 输入（Props）：`sessionID`、`readOnly`（会话已归档时为真）
- 内部状态：`messages`、`streamingText`、`isRunning`、`pendingApproval`、`errorMessage`
- **正文渲染（本节新增，2026-10-25 实机缺陷补齐）**：消息正文必须**渲染成富文本**，不许把 Markdown 源码直出。
  - 解析层**只许复用** `Core` 的 Markdown 解析（`MarkdownDocument`，判据 `Scripts/check-markdown-single-source.py`）；**禁止**在 `AgentChatView` 里自写第二套行内/块级解析。
  - 必须渲染：代码块（含语言标注与等宽底色）、有序/无序列表、任务列表勾选状态、引用块、表格、行内强调（粗体/斜体/行内代码/链接）。
  - 流式未闭合（如围栏 ```` ``` ```` 只出现一半）⇒ **原文照发、不做猜测性渲染**；收尾后按完整文档重排，不许在中途抖动整块高度。
  - 复制按钮复制的是**源码文本**，不是渲染后的可见文本（用户要拿去粘回终端）。
  - 工具卡片（tool call / 结果）与正文分开渲染，不参与 Markdown 解析。

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | `isRunning && streamingText.isEmpty` | 逐字追加的占位行 + 停止入口 | 空白气泡；重复发出同一请求 |
| 空数据 | `messages.isEmpty && !isRunning` | 空态引导（一句话 + 示例提问） | 错误件；无说明的空白页 |
| 错误 | `errorMessage != nil` | 错误件（原因 + 可重试入口）+ 已产生的部分消息照常显示 | 清空历史冒充「没发生过」；把网络错误渲染成模型回答 |
| 权限不足 | `pendingApproval != nil` 或 `readOnly` | 审批卡（逐条语句与目标库）+ 输入框禁用 | 灰色「仍然发送」；先发后问 |
| 提交中 | `isRunning` | 发送按钮换停止 + 队列提示 | 重复入队同一句话；静默丢弃 |
| 部分失败 | 工具调用中部分成功 | 逐条标成功/失败 + 失败原因 | 整轮报失败；丢失败条目 |

- 副作用：一轮结束写会话留痕（不含审批正文）；停止按钮经 `§3.13` 定向到本次执行。
- 禁止行为：把 Markdown 源码当正文直接 `Text(...)` 显示；自写第二套 Markdown 解析；流式中途重排导致滚动跳位。

##### 5.3.8.1 版式语汇（对照 Hermes TUI 的两张基准图，逐项照抄）

> **跨端出处**：语汇 / 骨架 / 开关 / 主题四层的**唯一权威在《Doyah产品概要设计说明书》§8.11**；本节只做「映射到本端落点」，不得重新定义语汇。
>
> **参考基准登记（比对面 = 以下四项，缺一项就算没参考）**
> ① 启动界面截图：`~/Desktop/Hermes-startup.png` ② 工作界面截图：`~/Desktop/Hermes-GUI.png`
> ③ 实现骨架源码（TUI 侧）：`ui-tui/src/components/appLayout.tsx`（主骨架）· `appChrome.tsx`（`statusBarSegments(cols)`）· `theme.ts`（30+ 配色键）· `blockLayout.test.ts`（行数分配）
> ④ 行为开关：`config.yaml` 的 `display:` 段；配色/品牌/符号：皮肤引擎 `hermes_cli/skin_engine.py` + `~/.hermes/skins/<名>.yaml`
>
> 纪律：以后改这一节，先重新看这四项再动笔；只凭文字描述改版式 = 返工。

> 基准：启动界面 = 桌面 `Hermes-startup.png`；工作界面 = 桌面 `Hermes-GUI.png`。两张图是**唯一比对面**，不是「风格参考」。以下每题都写成可核项。

**① 一个字号**：正文、工具行、状态行、输入行**同一字号**（`Theme.font(.body)` 同档），层级只靠颜色与字形，**不许**把工具行/状态行缩小一号。判据：`grep -c 'Theme.font(.caption)'` 在本视图内为 0（除表头与 `⌘` 提示）。

**② 行首栏（固定两字符列宽，等宽字形，不用 SF Symbol）**

| 位置 | 字形 | 含义 |
|---|---|---|
| 用户消息 | `>` | 人说的一句 |
| 助手正文 | （无字形，顶格） | 模型回答 |
| 工具块折叠头 | `└─ ▼` / `└─ ▶` | 一组工具调用，可折叠 |
| 工具条目 | `├─ ⏺`（末条 `└─ ⏺`） | 单次调用 |
| 提示/警告 | `▼` / `⚠` | 启动界面里的分节头与告警 |

工具条目一行内四段：`⏺ <工具名>("<参数摘要>") (<耗时>s)`；参数摘要超 60 字截断加 `…`。**耗时必须写**（对照图里每条都带 `(0.5s)`）。

**③ 边框只给「要人动手」的卡**：终端语汇里**没有通栏底纹、没有通栏卡片**。
- 允许描边：审批卡（等用户点）、发起界面里的信息面（启动图中间那一圈细边框，**棕色 1pt**，圆角 `Radius.badge`）。
- 禁止：给每条助手消息加卡片/底纹；用分隔横线（`---`，`Spacing.m` 上下留白、`Metrics.hairline` 细线）代替卡片。

**④ 状态行（底部，字段顺序固定，`|` 分隔，右端对齐工作目录/会话名）**

```
— ready | <模型名> | <上下文已用>/<窗口> | [████░░] <百分比> | ⊙ <缓存命中> | ↑ <t/s> | voice off      — <会话标题>
```
- 无读数时**整段不出现**（不写 `0`、不写 `n/a`）；运行中把 `ready` 换成 `( •_•)>◉─ computing…` 并附已跑时长。
- 花费**不在状态行**（2026-10-25 令：成本只看 token）。

**⑤ 输入行**：`>` 提示符 + 等宽输入框；右侧动作控件一律等宽字形（`⏎` 发送 / `■` 停止 / `▶` 继续 / `⏱` 定时），**不用 SF Symbol**；运行中在输入框下常驻一行灰字 `⏎rl+C to interrupt…` 的等价提示（本端为 `⌘.` 中断）。

**⑥ 启动界面（空会话 / 首启）**：自上而下五块，块间距 `Spacing.l`：
1. 品牌块：大号等宽艺术字（`HERMES-AGENT` 等价物 = 本产品名）+ 一行暗色副题；不出现 logo 位图。
2. 信息面（唯一允许描边的块）：左侧三行（模型 · 品牌 / 数据目录 / `Session: <id 前 8 位>`），右侧三组折叠头（`▼ 可用工具` / `▼ 可用技能 (N)` / `▼ MCP 服务器 (N)`），底部一行汇总 `N tools · N skills · /help for commands`，右上角版本号。
3. 空态引导一句话（灰色）。
4. 状态行（同 ④）。
5. 输入行（同 ⑤）。

**⑦ 颜色分配（只用令牌，不写字面色）**：强调 = `Theme.text(.bright)` 或 `Theme.status(.warning)` 档（对照图里的金/琥珀是强调色家族）；次要 = `Theme.text(.secondary)`；正文 = `Theme.text(.primary)`；链接 = 强调色 + 下划线。**禁止**仅靠颜色传达状态（`NFR-ALL-GATE-UI-001`）。

**⑧ 尺寸取令牌**：行高 `Metrics.listRowHeight`（20）· 工具块缩进 `Metrics.listIndent`（14）· 块间距 `Spacing.s/m/l` · 圆角 `Radius.badge/control`。**禁止**在视图里写裸数字（判据 `Scripts/check-design-tokens.py`）。

**⑨ 不许出现的东西**（对照图里没有的，本端也不许有）：通栏卡片、气泡尾巴、头像圆点、工具栏按钮文字、二级标题用更大字号、同一条信息画两遍（行内一句 + 下面卡片一次）。

##### 5.3.8.2 渲染骨架与可配置项（对照 Hermes TUI 的实现骨架）

> 参考来源（人类主人 2026-10-25 给出的实现骨架）：`ui-tui/src/components/appLayout.tsx`（主骨架）· `appChrome.tsx`（顶栏/状态栏分段，`statusBarSegments(cols)` 决定显示哪些段）· `theme.ts`（30+ 配色键 → 皮肤色值）· `blockLayout.test.ts`（消息块**行数分配算法**）；行为开关在 `config.yaml` 的 `display:` 段；配色/品牌/符号在皮肤系统（9 套内置 + `~/.hermes/skins/<名>.yaml`，合并规则见下）。

**① 三个骨架部件 ↔ 本端落点（骨架是代码，不是配置）**

| 职责 | TUI 侧 | 本端落点 | 契约 |
|---|---|---|---|
| 滚动正文 | `TranscriptPane` | `AgentChatView` 的 `ScrollView` + `LazyVStack` | 只在这一处滚；工具块折展不重排整列 |
| 输入框 | `PromptPrefix` + `composer` | `AgentChatView` 的输入行（`>` 前缀） | 输入行**永不随正文滚动** |
| 状态栏分段 | `statusBarSegments(cols)` | `AgentChatView.statusBar`（纯函数 `segments(width:)`） | **按宽度决定显示哪些段**：宽度不足时从右往左丢段（丢缓存率 → 丢 t/s → 丢 token 用量），**永不丢模型名与 ready/computing** |
| 行数分配 | `blockLayout` 算法 | `AgentBlockLayout.rows(for:width:)`（纯函数，可单测） | 同一块在窄/宽两档的**折叠行数**由它算，视图不自己数行 |

`blockLayout` 必须抽成**纯函数**并单测（窄 40 列 / 宽 120 列两档，断言折叠头行数与截断字符数），否则「窄屏挤成两行」这类走样只能靠肉眼抓。

**② 行为开关（等价物 = 本端 `ui.agent.*` 偏好，可在设置里改，不改代码）**

| 键 | 默认 | 影响 | 判据 |
|---|---|---|---|
| `streaming` | `true` | 逐字追加 vs 收齐再显示 | 关掉时首字延迟 = 整轮耗时 |
| `compact` | `false` | 紧凑模式：工具块默认折叠、块间距 `Spacing.hair` | 切换后同一屏幕可见消息数增加 |
| `show_reasoning` | `false` | 是否显示思考段（灰字缩进） | 关掉时思考段**零占位**（不留空行） |
| `timestamps` | `false` | 每条消息前加 `HH:mm` | 关掉时行首栏宽度不变（不抖动） |
| `show_cost` | **`false`（2026-10-25 令：固定关，不设开关）** | 花费——已从界面撤除 | `grep 'estimatedCost'` 在 App/ 视图面 0 处 |
| `tool_progress` | `all` | `all` / `summary` / `off` 三档 | `summary` 只显示折叠头 + 条数；`off` 只剩「调用 N 次」一行 |
| `status_indicator` | `kaomoji` | `kaomoji` / `unicode` / `ascii` 三档字形 | 三档都能表示 computing / ready / error 三态 |
| `user_message_preview` | `首2末2` | 长用户消息折成「前 2 行 … 后 2 行」 | 折叠处有 `…` 且可点开全文 |
| `runtime_footer` | `false` | 底栏附加 模型 / 上下文百分比 / 工作目录 | 关掉时状态行少这三段，其余不动 |
| `busy_input_mode` | `interrupt` | 运行中提交 = 打断 vs 排队 | `interrupt` 时先停后发（与 §5.3.8 提交中一列一致） |

**③ 配色 / 品牌 / 符号 = 主题集（唯一可自由配置的一层）**

- 本端等价物 = `Core/DesignTheme.swift` 的 5 套主题（tech-blue / bean-green / rose-gold / stardust / deep-space）+ `Core/DesignTokens.swift` 的角色表；**不许**在视图里写字面色（判据 `check-design-tokens.py`）。
- TUI 的 30+ 键按**角色**归并到本端令牌（`Surface` / `TextTone` / `StatusTone` / `SyntaxTone`），**不 1:1 照搬键名** —— 键名进了视图就会长成两套口径。
- **合并规则的坑（照抄，免得返工）**：TUI 的 `colors` / `spinner` / `branding` 在 `default` 之上**逐键合并**（只写想改的）；而 `light_colors` / `dark_colors` **不合并** —— 留空 = 该皮肤没有手调明暗变体，由引擎自动适配。本端对应实现：主题值表按「角色 × 明暗」两列给值，**缺失的明暗变体必须回落推导值并登记**（不许静默落成同一色，那就等于没有明暗两套）。
- 品牌与符号：`tool_prefix` 等价物 = 行首栏字形表（见 §5.3.8.1 ②）；`branding.name/icon/prompt/welcome` = 启动界面 §5.3.8.1 ⑥ 的品牌块与提示符；这些**进主题表、不进视图代码**。

##### 5.3.8.3 皮肤与品牌值表（TUI 皮肤 YAML 字段 → 本端主题表）

**字段对照（写全，缺一个就会「改了不生效」）**

| TUI 皮肤字段 | 含义 | 本端落点 | 口径 |
|---|---|---|---|
| `colors.*`（`banner_border` / `banner_title` / `ui_accent` / `ui_ok` / `prompt` / `status_bar_bg` 等 30+ 键） | 各角色色值 | `Core/DesignTheme.swift` 每个主题一份 `palette`，按 `Surface` / `TextTone` / `StatusTone` / `AccentFamily` 角色取值 | **按角色归并，不 1:1 搬键名** |
| `light_colors` / `dark_colors` | 手调明暗变体 | 主题值表的 `light` / `dark` 两列 | **不合并**：缺失的变体必须回落推导值并在值表里登记理由（静默落成同一色 = 没有明暗两套） |
| `spinner` | 加载动画字形 | `status_indicator` 三档 + `busy` 字形（`kaomoji` / `unicode` / `ascii`） | 三档都要能表达 computing / ready / error |
| `branding.{name,icon,prompt,welcome,goodbye,tool,help_header}` | 品牌与提示语 | 启动界面品牌块、输入行提示符 `>`、欢迎/告别文案（走语言表） | 文案**只从语言表取**，不写在视图里 |
| `tool_prefix`（如 `┊`） | 工具行行首字形 | 行首栏字形表（§5.3.8.1 ②：`└─ ▼` / `├─ ⏺`） | 字形常量集中在 `AgentGlyphs`，视图不散写 |
| `tool_emojis` | 工具图标 | 本端不用 emoji（终端语汇里 emoji 破坏等宽列） | 只用等宽字形；判据：本视图内 emoji 0 处 |
| `banner_logo` / `banner_hero` | 大图 / 艺术字 | 启动界面品牌块（等宽艺术字） | 用文本字形，不用位图 |
| `customCSS`（上限 32KB） | 注入样式 | **本端不提供** | 理由：原生渲染无 CSS；等价能力 = 主题值表 + 令牌，且必须过对比度门槛（`Scripts/check-theme-set.py` 的 310 条） |

**皮肤清单与覆盖度**

- TUI 侧内置 **9 套**（`default` / `ares` / `mono` / `slate` / `daylight` / `warm-lightmode` / `poseidon` / `sisyphus` / `charizard`），自定义放 `~/.hermes/skins/<名>.yaml`。
- 本端**不照搬 9 套**：主题集是 5 套（tech-blue / bean-green / rose-gold / stardust / deep-space，见 `Docs/design/外观方案-v1.md`），每套必须给全「角色 × 明暗」两列值并过对比度门槛 —— 这是本端比 TUI 严的一条（TUI 允许某皮肤没有手调明暗变体，本端不允许缺值不登记）。
- 存放与切换：TUI = 用户自建 YAML；本端 = 主题选择持久化在 `ui.designTheme`，**不开放用户自带皮肤包**（理由：值表要过 100 角色 / 310 条门槛的独立复算，外部 YAML 无法保证；新增一套主题走代码 + 值表 + 判据三处同改）。

**合并规则的两条坑（都照抄进本端）**

1. `colors` / `spinner` / `branding` 在 `default` 之上**逐键合并** ⇒ 本端主题值表也按「只写覆盖项、其余继承基准主题」实现，别要求每套主题写满 100 个角色。
2. `light_colors` / `dark_colors` **不合并** ⇒ 本端对应实现是「明暗两列独立求值 + 缺值必须登记」，**不许**用「合并成一套」偷懒（那会让深色主题在浅色档里失真）。

### 5.3.9 浮层（paper）版式语汇

本端有三类「压在内容之上的层」，**口径唯一，各视图不得各自发挥**：

| 类型 | 用在哪 | 衬底 | 外形 | 备注 |
|---|---|---|---|---|
| 浮层 paper | 笔记本架、期次浮层、行内悬停菜单 | `.thickMaterial`（≈95% 不透，随明暗自适应） | `Radius.card` 圆角 + 阴影 `black 0.28 / r12 / y2` | **不得用系统控件底色**（暗色下会是死黑），**不得只用半透明 surface**（壁纸透上来字发糊） |
| 面板 panel | 结果面板、审批单 | `Theme.surface(.panel)` | 1pt 描边 `Theme.hairline` | 与内容同层，不浮起，无阴影 |
| 对话框 sheet | 设置、确认框 | 系统 sheet | 系统 | 只放系统控件，不套本端语汇 |

**四条硬纪律**：

1. **压住内容的层必须不透明**：凡是浮在壁纸之上的层，衬底不透明度 ≥ 0.9；半透明只允许出现在**不承载文字**的装饰层。
2. **不透明不等于纯色黑**：浮层衬底**一律 `Theme.paper(_:)`** —— 它取主题面板色的**不透明**取值，随明暗主题各自求值。
   **禁止在浮层上调用 `Theme.surface(_:)`**：壁纸皮肤（如「深空苍穹」）下它按值表**故意半透明**，
   照片从内容层与浮层两层透上来，文字必糊；也**禁止**改用 `.thickMaterial` / 系统控件底色
   （暗色主题下偏黑，且与主题配色不同源）。2026-10-25 实机连撞三次（半透明 → 系统控件色死黑 → thickMaterial 偏黑）才定位到这一层。
3. **浮层不参与布局**：挂 `.overlay`，不得进 `HStack`/`VStack` 的尺寸协商 —— 浮出与收起时内容区宽度逐点相同。
4. **入口悬停出、离开收**：行内与分组标题上的动作（`＋` / `…`）常驻不占位，鼠标进入时才浮出；同一条动作**只画一次**，工具条与行内不得并存两份。

### 5.4 状态与数据流

- 单一数据源：页签模型在 `AppState.tabs`；结果集在页签对象内；视图不持有可写副本。
- 派生：行数、耗时、可编辑判定、预估读数由装配层算出后单向下发；视图不得自行重算。
- 缓存失效：对象树按「连接 + 库」缓存，连接断开或结构变更成功后整体失效；不设基于时间的过期。
- 跨页签共享：同一「连接 + 库」共享一个 `DatabaseService`（`AppState.ensureService`）；事务状态挂在该服务上，页签不得各自开事务。

### 5.5 事件绑定与动作映射

| 界面动作 | 调用接口 | 成功行为 | 失败行为 | 禁止行为 |
|---|---|---|---|---|
| 点执行 | `execute`（§3.3） | 逐条上报 + 渲染 + 写历史 | 错误件 + 保留 SQL | 失败后清空编辑器 |
| 点停止 | `cancel`（§3.4） | 状态已取消、连接可用 | 明说服务端拒绝原话 | 只改界面状态 |
| 保存连接 | `ConnectionStore.save`（§3.2） | 清单刷新 + 选中保持 | 字段级错误 | 静默丢配置 |
| 删除连接 | `ConnectionStore.save` + 凭据清理 | 条目消失 + 清理项清单 | 明说残留位置 | 无确认删除 |
| 展开节点 | `loadChildren`（§3.7） | 渲染层级 | 节点级错误 + 重试 | 显示空树冒充无对象 |
| 行写回 | `applyRowEdits`（§3.9） | 逐行结局 | 冲突行明示 + 保留输入 | 影响 0 行当成功 |
| 生成脚本 | `TableDesign.validate` + 预览 | 展示脚本 + 待确认 | 明说缺什么 | 直接执行 |
| 导出 | `ResultExporter`（§3.11） | 进度 + 完成 + 文件大小 | 部分成功列明细 | 失败留半成品不说 |
| 终止会话 | `SessionMonitor` + 确认（§3.13） | 结局 + 刷新列表 | 权限原话 | 无确认终止 |
| 投递上下文 | `AgentContext.assemble`（§3.14） | 摘要可核对 | 拒绝并说明需确认 | 静默投递行数据 |

- 通用禁令：不可逆操作（删连接、删表、清表、终止会话、高危写）必须先二次确认并说明后果；需要用户决策的错误不得用 toast 承载；未授权入口不出现（不是灰掉）。

### 5.6 表单实现与校验落点

| 表单/字段 | 前端校验 | 后端校验 | 错误定位位置 | 禁止行为 |
|---|---|---|---|---|
| 连接名称 | 非空、同工作区唯一 | 同左 | 字段下方 | 仅前端校验 |
| 主机 | 非空 | 同左 | 字段下方 | 前端拼连接串 |
| 端口 | 整数，先解析再校验 1…65535 | 同左 | 字段下方 | 越界静默夹取 |
| 用户名 | 非空 | 非空 | 字段下方 | 空口令尝试连接 |
| SQL 文本 | 非空 | 非空 + 目标库一致 | 编辑器下方错误件 + 消息面 | 空执行静默通过 |
| 导出格式 | 取值为支持集合 | 同左 | 字段下方 | 生成不支持格式的空文件 |
| 导入目标 | 目标存在必须询问 | 同左 | 顶部汇总 + 字段 | 静默覆盖既有表 |

- 前后端校验必须一致，后端为最终依据；前端通过不得假定后端成功。
- 可访问性落点：每个视图主动作有键盘路径；容器、按钮、输入框、状态提示带可读名称；空/加载/错误三态有文字表述；同一动作的文案、图标、快捷键、禁用条件只在 `AppCommandCatalog` 定义一次。

### 5.7 导航与权限落点

| 起点 | 触发 | 终点 | 前置条件 | 禁止行为 |
|---|---|---|---|---|
| 活动栏 | 点「数据库」 | 查询页签 | 有可用连接（无连接先给建连引导） | 直接报错 |
| 对象树节点 | 双击表 | 新查询页签（浏览前 N 行） | 连接已就绪 | 未连接时打开空页签 |
| 查询页签 | 执行成功 | 同页签结果区 | 至少一条语句完成 | 自动跳到别的页签 |
| 会话视图 | 终止会话 | 同视图 | 已二次确认 | 未确认离开 |
| 对话页签 | 点写操作卡片 | 审批单 | 该动作需审批 | 越过审批直接执行 |

- 路由守卫落点：`AppState.openTab(kind:)` 一处判定入口可见性与前置条件；界面不得各自判一次。
- 未授权处理：入口不渲染；到期只降级入口，数据可开可导出（禁锁死用户数据）。
- 禁止：新增未列出的路由或入口；未确认离开导致未保存内容丢失；同一入口在两处各判权限。

### 5.8 界面测试契约

| 用例 ID | 类型 | 覆盖条款 | Given | When | Then |
|---|---|---|---|---|---|
| `UI-5.1-01` | 路由清单 | 概要设计 §8.1 / §8.2 | 视图清单与命令目录 | 遍历所有可打开入口 | 无清单外路由，`check-palette-wiring.py` 差集 0 |
| `UI-5.1-02` | 职责 | 概要设计 §8.2 | 八类视图各打开一次 | 逐视图核对呈现项 | 禁止呈现项（口令/连接串/未授权入口）出现 0 次 |
| `UI-5.3-01` | 组件 | 概要设计 §8.4 | 七个组件各造六态 | 逐态渲染 | 六态齐，六张表的「禁止渲染」列各行为空 |
| `UI-5.3-02` | 错误呈现 | 概要设计 §8.8 | 注入四类错误（字段/页面/服务器/不可恢复） | 渲染 | 每类都含原因 + 位置 + 重试入口 |
| `UI-5.3.1-01` | 组件 | 概要设计 §8.4 / §8.7 | 查询页签六态夹具 | 逐态渲染 | 只在 `isExecuting` 时出现停止按钮；失败不清空 SQL |
| `UI-5.3.2-01` | 组件 | 概要设计 §8.6 | 连接表单六态夹具 | 逐态渲染 | 校验未过时提交按钮禁用且零请求 |
| `UI-5.3.3-01` | 组件 | 概要设计 §8.4 / §8.7 | 连接清单六态夹具 | 逐态渲染 | 删除必先确认；凭据清理失败要明说残留 |
| `UI-5.3.4-01` | 组件 | 概要设计 §4.5 / §8.4 | 对象树六态夹具 | 逐态渲染 | 刷新后选中节点不变；无伪造占位节点 |
| `UI-5.3.5-01` | 组件 | 概要设计 §5.4 / §6.3 | 审批单六态夹具 | 逐态渲染 | 过期/无记录不可批准；预估缺失显示「未接」 |
| `UI-5.3.6-01` | 组件 | 概要设计 §4.8 / §8.4 | 导入导出六态夹具 | 逐态渲染 | 部分失败分别列成功与失败项 |
| `UI-5.3.7-01` | 组件 | 概要设计 §3.1 / §8.4 | 浏览页签六态夹具 | 逐态渲染 | 加载失败不出现空白成功页；关闭参与 ⌘W 口径 |
| `UI-5.5-01` | 交互 | 概要设计 §8.5 | 五类不可逆动作 | 触发动作 | 每次都先出确认并说明后果；需要决策的错误不走 toast |
| `UI-5.5-02` | 动作映射 | 概要设计 §8.7 | 十行动作表 | 逐行制造失败 | 失败保留用户输入，无一条冒充成功 |
| `UI-5.6-01` | 表单 | 概要设计 §8.6 / §8.9 | 七行字段表 | 逐字段注入非法值 | 错误定位到字段；键盘可走完连库→执行→看结果→关页 |
| `UI-5.7-01` | 导航 | 概要设计 §8.3 | 五条允许流转 + 非法跳转 | 逐条触发 | 非法跳转被拒并给理由 |
| `UI-5.7-02` | 可访问性 | 概要设计 §8.9 | 三主题 × 各视图 | 纯键盘 + 读屏走一遍 | 焦点可见、三态有文字、快捷键只在命令目录一处 |
| `UI-5.8-01` | 覆盖率 | 概要设计 §8.10 | 本表与 §0.1 矩阵 | 比对矩阵 UI 行 | 矩阵每个 UI 行在本表都有用例；本表无用例游离 |
| `UI-5.8-02` | 概要设计 §8.11 | §5.3.8.1 / §5.3.8.2 | 一屏真实对话（含工具块与状态行） | 逐条比对行首栏字形 / 字号唯一 / 状态行字段序 / 有无通栏卡片 | 六项全合规，任一不符即红 |

测试禁止行为：禁止 `XCTSkip` / 只跑一个用例 / `sleep` 等待 / 依赖真实网络与真实库 / 改动断言适配实现。

---

## 6. 错误映射与日志

### 6.1 错误码映射（概要设计 §9 的 21 码）

| 概设错误码 | 本端落点 | 状态 |
|---|---|---|
| `CONN_INVALID_CONFIG` | `AppError.invalidConfiguration` | 已有 |
| `CONN_NO_CREDENTIAL` | `AppError.credentialStore` + `SecretStore` 实现 | 已有 |
| `CONN_UNREACHABLE` | `ConnectionFailure`（不可达分类） | 已有 |
| `CONN_AUTH_FAILED` | `ConnectionFailure`（认证分类） | 已有 |
| `CONN_NOT_FOUND` | 连接清单查找路径（按 `.notConnected` 呈现） | 无专门类型 |
| `CRED_PURGE_FAILED` | `AppError.credentialStore` + 残留位置上浮 | 已有 |
| `EXEC_EMPTY_SQL` | 装配层前置校验（`ExecutionScope.Issue`） | 无专门类型 |
| `EXEC_NO_CONNECTION` | `AppError.notConnected` | 已有 |
| `EXEC_READONLY_DENIED` | `ExecutionSafety.Decision.refused` | 已有 |
| `EXEC_CONFIRM_REQUIRED` | `ExecutionSafety.Decision.needsConfirmation` | 已有 |
| `EXEC_SERVER_ERROR` | `AppError.queryFailed` + 服务端原文 | 已有 |
| `EXEC_CONNECTION_LOST` | `QueryEvent` 失败事件 | 已有 |
| `EXEC_CANCEL_ILLEGAL` | `CancelOutcome.failed(reason:)` | 已有 |
| `META_UNSUPPORTED` | `AppError.notImplemented` + 层级差异说明 | 已有 |
| `DATA_NO_PK` | `applyRowEdits` 前置（§3.9） | 未实现（§10.1） |
| `DATA_WRITE_CONFLICT` | `applyRowEdits` 逐行结局（§3.9） | 未实现（§10.1） |
| `DDL_PREVIEW_REQUIRED` | `SchemaScriptRunner.run` 预览闸（§3.10） | 未实现（§10.1） |
| `IO_TARGET_EXISTS` | `TableImport.plan` 覆盖询问（§3.12） | 未实现（§10.1） |
| `IO_PARTIAL` | `TableImport.plan` 逐批结局（§3.12） | 未实现（§10.1） |
| `SESS_KILL_DENIED` | `SessionMonitor` 动作路径（§3.13） | 未实现（§10.1） |
| `LIC_NO_CAPABILITY` | 授权判定（入口可见性） | 未实现（§10.1） |

- 概要设计 §4.x 另有 10 个接口级码不在 §9 的 21 码清单内：`EXEC_CANCEL_FAILED`、`META_FAILED`、`DATA_WRITE_FAILED`、`DDL_CONFIRM_REQUIRED`、`DDL_FAILED`、`IO_FORMAT_UNSUPPORTED`、`SESS_NOT_FOUND`、`SESS_KILL_REQUIRED_CONFIRM`、`BRIDGE_ROW_DATA_REQUIRES_CONFIRM`、`BRIDGE_EMPTY_CONTEXT`。这 10 个码逐条落在 §3 各节的错误契约表里，不另立映射表。
- 呈现规则：字段级错误呈现在字段附近；页面级错误呈现在结果区或页面顶部并带重试入口；服务器错误保留原文（可复制）并附语句序号与目标库；不可恢复错误阻断当前动作并给下一步。

### 6.2 四条禁止兜底在本端的实现级禁令

| 概设禁令 | 本端落点 | 判据 |
|---|---|---|
| 禁止返回空对象冒充成功 | `AppError` 全枚举无 `.empty` 型成功值；`loadChildren` 只能在真有 0 个子节点时返回空数组 | `T-6.2-01` 反例：注入失败 ⇒ 必须抛错，不得返回 `[]` |
| 禁止用默认值掩盖缺失 | 缺参一律失败（§3.1 前置）；预估缺数写「未接」（§3.16） | `T-3.1-02`、`T-3.16-01` |
| 禁止捕获异常后不记录、不返回、不处理 | 每个 `catch` 必须至少做「记 + 返」之一；`rg -n 'catch \{ *\}'` 为空 | `T-6.2-01` |
| 禁止把依赖失败降级为业务成功 | 归档失败只报「记录未落盘」，业务结果不回滚（§4.2）；同步续期失败不当作登出 | `T-4.2-01`、`T-4.5-01` |

### 6.3 日志字段

- 必记：错误码、连接标识、会话/页签标识、调用方、时间、耗时、结局。
- 禁记：口令、凭据引用原文、完整连接串、结果行数据、执行计划全文、导出正文。
- 落点：审计与出口日志统一走 `AgentAudit` / `EgressLog`（追加式 JSONL）；日志写入失败不得吞掉（记到 stderr 并保留计数）。
- 判据：`rg -n 'password|secret|dsn' Core/ | rg -i 'log|print'` 为空；导出前脱敏由 `AgentContext.filterSecretsOnly` 承担。

---

## 7. 并发与线程模型

### 7.1 并发模型与共享可变状态

| 约束 | 落法 |
|---|---|
| 界面状态只在主线程改 | 装配层与模型 `@MainActor`；能力层回调只递值 |
| 一个「连接 + 库」只有一个服务实例 | `AppState.ensureService` 以「连接 + 库」为键；跨页签共享 |
| 同一连接上的语句串行 | 服务内部串行队列；取消走句柄，不靠抢占 |
| 笔记写入单事务 | `NoteLibrary` actor 内串行 |
| 同步单飞 | `SyncQueue` 串行，重入即排队 |
| 禁止 | 事务中发外部网络调用；锁内慢操作；无界并发 |

### 7.2 事务边界与幂等

- 事务边界：一次执行一个事务；手工事务由用户驱动，跨页签不共享事务对象。
- 幂等键：连接建立 = 连接 id；取消 = 执行句柄；行写回 = 主键；审批 = fingerprint；导入 = 目标表 + 批次序号。
- 归档与审计属动作后置：失败只报「记录未落盘」，不回滚业务；写入原子（JSONL 追加 + 换行）。
- 禁止：事务进行中切换连接或目标库；把取消写进成功分支；对写语句自动重试。

---

## 8. 安全

### 8.1 鉴权与凭据落点

- 鉴权落点：能力层与驱动层判定（只读、能力位）；界面只呈现结果，禁止前端-only 判定。
- 凭据：只经 `SecretStore` 协议取用，macOS 实现 `Platform/macOS/KeychainSecretStore.swift`；删除连接连带清理；口令不进日志、不进模型上下文、不进导出包。
- 已修：`AppState.init(secretStore:agentKeyStore:)` 默认注入 `KeychainSecretStore()` / `KeychainAgentKeyStore()`；文件实现仅测试态显式注入（见 §2.2）。
- 到期与授权：能力位解析离线可校验，入口可见性只在一处判定；到期降级入口但保留数据可开可导出。

### 8.2 输入校验与注入防护

- 输入校验位置：`ConnectionConfig` 与装配层前置校验；服务端校验为最终依据。
- 注入防护：一律参数化（`:name` / `$1` 类型化转义），禁止字符串拼接；标识符经 `SQLGenerator` 转义。
- 外部工具输出一律不可信：工具观察值进模型前先脱敏与限长。
- 错误信息不泄露堆栈、连接串与凭据引用；`EgressLog` 记录每一次外发（目的地、体量、时刻），不含正文。

---

## 9. 判据与测试

### 9.1 测试文件与组织

| 测试文件 | 被测单元 | 类型 | 必须覆盖的条款 |
|---|---|---|---|
| `Tests/ConnectionConfigTests.swift` | `ConnectionConfig`、`DatabaseServiceFactory` | 单元 | §3.1、§4.1 |
| `Tests/ConnectionConfigMigrationTests.swift` | `ConnectionStore` | 单元 | §3.2、§4.2 |
| `Tests/ExecutionScopeTests.swift` | 选区判定与空 SQL 拦截 | 单元 | §3.3 前置 |
| `Tests/ExecutionSafetyTests.swift` | `ExecutionSafety.check` | 单元 | §3.5 |
| `Tests/CancellationNoiseTests.swift` | `execute` / `cancel` 流语义 | 单元 | §3.3 后置、§3.4 |
| `Tests/ConnectionReadOnlyTests.swift` | 只读连接拒写 | 单元 | §3.5、§4.4 |
| `Tests/AgentApprovalGateTests.swift` | `AgentApprovalGate` | 单元 | §3.6、§4.4 |
| `Tests/ConnectionFailureTests.swift` | 错误码呈现 | 单元 | §6.1 |
| `Tests/AgentPlanRowsTests.swift` | 影响行数预估 | 单元 | §3.16 |
| `TestsPlatform/`（快照面） | 视图六态 | 快照 | §5.3、§5.8 |
| `Scripts/verify-core.sh` | 全能力层回归 | 集成 | §9.3 |

### 9.2 必测用例清单（后端）

| 用例 ID | 对应概设条款 | 对应详设契约 | Given | When | Then |
|---|---|---|---|---|---|
| `T-2.1-01` | 概要设计 §3 | §2.1 禁令 | 全仓源码 | 检索界面层对驱动的引用 | 命中 0 处；界面不持句柄 |
| `T-2.2-01` | 概要设计 §4.1 / §11.4 | §2.2 注入点 | 注入替身（方言 / 时钟 / ID / HTTP） | 跑 §3.1–§3.16 各用例 | 全部可用替身驱动，无需改生产代码 |
| `T-2.3-01` | 概要设计 §19.2 | §2.3 插件清单 | 插件清单与门禁期望列表 | 比对两处 | 差集 0；跨层引用检索为空 |
| `T-3.1-01` | 概要设计 §4.1 | §3.1 后置 | 合法 `ConnectionConfig` | 调 `make` | 返回服务且 `config` 逐字段相等；未建连 |
| `T-3.1-02` | 概要设计 §4.1 | §3.1 错误表 | 空主机 / 端口 0 / 未知类型 | 调 `make` | 分别抛 `invalidConfiguration` / `notImplemented`，无实例产生 |
| `T-3.2-01` | 概要设计 §4.2 | §3.2 后置 | 两条连接配置 | `save` 后 `load` | 逐字段一致；`schemaVersion` 保留 |
| `T-3.2-02` | 概要设计 §5.1 | §3.2 迁移 | 旧格式文件 | `loadWithReport` | 读出新条目并升级一次，二次读不再升级 |
| `T-3.3-01` | 概要设计 §4.3 / §7.1 | §3.3 后置 | 两段 SQL + 一段选区 | 执行 | 有选区只跑选区；按文本顺序逐条上报；结果集全保留 |
| `T-3.3-02` | 概要设计 §4.3 | §3.3 后置 | 长查询 | 执行中取消 | 不再收 `resultSet`；无噪声事件；连接仍可用 |
| `T-3.3-03` | 概要设计 §4.3 | §3.3 前置 | 空串 / 纯空白 | 点执行 | 报 `EXEC_EMPTY_SQL`，不发语句 |
| `T-3.4-01` | 概要设计 §4.4 | §3.4 后置 | 执行中句柄 | 重复 `cancel` 两次 | 两次同一结局；连接仍可用；服务端真取消 |
| `T-3.5-01` | 概要设计 §4.3 / §7.1 | §3.5 后置 | 只读连接 / 无 WHERE 写 / DROP | 调 `check` | 分别 `refused`（原因非空）/ `needsConfirmation` |
| `T-3.6-01` | 概要设计 §5.4 / §6.3 | §3.6 后置 | 一条 pending 审批单 | 连续两次 `grant` 同一 fingerprint | 第一次 approved 且落一条消费；第二次 `.missing` |
| `T-3.7-01` | 概要设计 §4.5 | §3.7 后置 | 已展开并选中的对象树 | 刷新 | 层级随类型；选中不变；无占位节点 |
| `T-3.8-01` | 概要设计 §4.6 | §3.8 后置 | 表名 + 过滤 + 上限 | 生成浏览语句 | 上限与排序在服务端；坏条件返回 failure |
| `T-3.9-01` | 概要设计 §4.6 | §3.9 错误表 | 无主键结果集 / 并发改行 | 写回 | 前者不开放入口；后者报 `DATA_WRITE_CONFLICT` |
| `T-3.10-01` | 概要设计 §4.7 / §7.2 | §3.10 前置 | 已生成脚本未预览 | 执行 | 报 `DDL_PREVIEW_REQUIRED`，服务端未收语句 |
| `T-3.10-02` | 概要设计 §4.7 / §7.2 | §3.10 错误表 | 只读连接 / 超上限任务 | 执行 DDL | 前者 `refused`；后者拒绝且不改表 |
| `T-3.11-01` | 概要设计 §4.8 | §3.11 后置 | 含特殊字符的结果集 | 五种格式导出 | 转义正确；输出逐字节可重现；不含凭据 |
| `T-3.12-01` | 概要设计 §4.8 | §3.12 错误表 | 目标已存在 / 部分行不可转 | 导入 | 前者先询问；后者列 `invalidValues` |
| `T-3.13-01` | 概要设计 §4.9 | §3.13 错误表 | 无终止权限的会话 | 终止 | 上浮服务端原话；无确认时先拒绝 |
| `T-3.14-01` | 概要设计 §4.10 | §3.14 错误表 | 含结果行数据的上下文 | 未确认投递 | 报 `BRIDGE_ROW_DATA_REQUIRES_CONFIRM`；审计 0 条 |
| `T-3.15-01` | 概要设计 §18.1 | §3.15 错误表 | 参数不合规的工具调用 | `dispatch` | 直接给模型可读错误；工具未执行、无副作用 |
| `T-3.16-01` | 概要设计 §5.4 | §3.16 后置 | `ModifyTable` 根节点 `Plan Rows` 为 0 | `estimate` | 取子节点行数；取不到返回 `noAnswer`，不返回 0 |
| `T-4.1-01` | 概要设计 §5.1 | §4.1 | 一份连接配置 | 编码再解码 | 字段与约束一致；不含口令字段 |
| `T-4.2-01` | 概要设计 §5.2 | §4.2 | 同一 SQL 执行两次 | 读历史 | 一条记录、重复次数 2；归档失败不回滚业务 |
| `T-4.2-02` | 概要设计 §5.3 | §4.2 | 任务定义 | 执行时参数与定义不一致 | 拒绝执行；上限越界拒绝 |
| `T-4.4-01` | 概要设计 §6.1 | §4.4 | 未连接 | 建立连接 | 进入连接中，再进已连接 |
| `T-4.4-02` | 概要设计 §6.1 | §4.4 | 失败态 | 直接置已连接 | 拒绝；必须经连接中 |
| `T-4.4-03` | 概要设计 §6.2 | §4.4 | 执行中 | 取消 | 进入已取消 |
| `T-4.4-04` | 概要设计 §6.2 | §4.4 | 已取消 | 置已完成 | 拒绝；重跑是新执行 |
| `T-4.4-05` | 概要设计 §6.3 | §4.4 | 已拒绝 | 置已批准 | 判决为 `.denied`，不可翻 |
| `T-4.4-06` | 概要设计 §6.3 | §4.4 | 已过期 | 置已批准 | 判决为 `.expired`，不可翻 |
| `T-4.4-07` | 概要设计 §6.4 | §4.4 | 执行中页签 | 关闭 | 拒绝并给理由「执行中，请先停止」 |
| `T-4.4-08` | 概要设计 §6.4 | §4.4 | 有未保存改动页签 | 关闭并确认 | 进会话快照；保存失败时脏标记保留 |
| `T-4.5-01` | 概要设计 §15 | §4.5 | 一条带标签与时间线的笔记 | 写入中断 | 本体/标签/时间线同事务回滚；续期失败不登出 |
| `T-4.7-01` | 概要设计 §16 | §4.7 | 插件装载清单 | 装载复盘宿主 | 宿主可挂载；业务判据在复盘仓自跑（他仓） |
| `T-4.8-01` | 概要设计 §7.3 | §4.8 | 磁盘文件被外部改动 | 保存与重新载入二选一 | 无静默覆盖；保存失败不清脏标记 |
| `T-6.1-01` | 概要设计 §9 | §6.1 | 21 个错误码各造一次 | 触发并呈现 | 每码有落点与呈现形态；文案来自文案表 |
| `T-6.2-01` | 概要设计 §9 | §6.2 | 四类兜底场景（空对象 / 默认值 / 吞异常 / 降级） | 注入失败 | 四类均不被当成成功；空 `catch` 检索为空 |
| `T-7.1-01` | 概要设计 §11.4 | §7.1 | 同连接两个页签并发执行 | 同时点执行 | 语句串行；服务实例唯一；无事务串台 |
| `T-7.2-01` | 概要设计 §11.4 | §7.2 | 手工事务进行中 | 切换连接 | 拒绝；归档失败只报「记录未落盘」 |
| `T-8.1-01` | 概要设计 §11.4 | §8.1 | 删除连接 | 观察凭据与日志 | 凭据条目清空；日志无口令与连接串 |
| `T-8.2-01` | 概要设计 §11.4 | §8.2 | 含引号与分号的值 | 参数化执行 | 值不参与语句拼接；注入样例不改变语法结构 |
| `T-3.17-01` | 概要设计 §3 / §4 | §3.17 | 授权目录 + `echo hi` | 执行 | 返回 exitCode 0，stdout 含 `hi`，无截断 |
| `T-3.17-02` | 概要设计 §3 / §11.4 | §3.17 | 未授权目录 | 执行任意命令 | 返回 `.refused(.directoryNotAuthorized)`，进程启动次数 0 |
| `T-3.17-03` | 概要设计 §3 / §11.4 | §3.17 | `sleep 5` + timeout 1s | 执行 | 返回 `.timedOut`，子进程已终止（`ps` 查不到） |
| `T-3.17-04` | 概要设计 §3 / §5.4 | §3.17 | `rm -rf build` | 执行 | 先出审批单且命令完整；拒绝后进程启动次数 0 |
| `T-3.18-01` | 概要设计 §3 | §3.18 | 授权目录 + `print(1+1)` | 执行 | exitCode 0，stdout 含 `2`，无截断 |
| `T-3.18-02` | 概要设计 §3 / §11.4 | §3.18 | 代码里发起 HTTP 请求 | 执行 | `.refused(.networkForbidden)`，外发日志 0 条 |
| `T-3.18-03` | 概要设计 §3 | §3.18 | `while True: pass` | 执行 | `.timedOut`，进程已终止，临时目录已清 |
| `T-3.19-01` | 概要设计 §3 | §3.19 | query=「跑代码」 | 检索 | 命中内置代码执行与接入类各一，标注来源 |
| `T-3.19-02` | 概要设计 §3 | §3.19 | 未取回 schema 直接调用未知工具 | 派发 | 被拒并说明「未取回参数说明」 |
| `T-3.20-01` | 概要设计 §3 | §3.20 | 三个无依赖子任务 | 并发执行 | 返回长度 3、顺序与输入一致、全部 finished |
| `T-3.20-02` | 概要设计 §3 / §11.4 | §3.20 | 五路 + 并发上限 4 | 执行 | 第 5 路排队后仍完成；峰值并发 ≤ 4 |
| `T-3.20-03` | 概要设计 §3 | §3.20 | 三路，中间一路抛错 | 执行 | 该路 failed，另两路 finished，归并含三路结局 |

### 9.3 判据怎么跑

| 场景 | 命令 | 期望 |
|---|---|---|
| 纯能力层改动 | `bash Scripts/verify-core.sh` | 全绿，计数与台账一致 |
| 要出包 | `bash Scripts/build-app.sh` | 打印字节数 + sha256 前缀 |
| 界面改动 | `python3 Scripts/check-design-tokens.py` | 不高于基线 |
| 新命令入口 | `python3 Scripts/check-palette-wiring.py` | 未登记差集 0 |
| 新中文文案 | `python3 Scripts/check-core-localization.py` | 无缺键 / 无未分类 |
| 插件装配 | `python3 Scripts/check-plugin-assembly.py` | 装载 6 组绿 |
| 文档改动 | `python3 Scripts/check-doc-tables.py && python3 Scripts/check-doc-layout.py` | 两者 rc=0 |
| 本文件自检 | `python3 <skill>/scripts/audit_lld.py Docs/Doyah产品详细设计说明书-macOS.md --hld Docs/Doyah产品概要设计说明书.md --repo .` | 硬失败 0 / 告警 0 |

---

## 10. 合规自检

### 10.1 未实现位点（代码现状，不是文档缺口）

| 位点 | 现状 | 契约要求 |
|---|---|---|
| 行编辑（`DATA_NO_PK` / `DATA_WRITE_CONFLICT`） | 无专门类型，`RowBrowsing` 只做浏览 | §3.9 四类行为，实现时按错误表补分支 |
| 结构脚本预览闸（`DDL_PREVIEW_REQUIRED`） | 未实现（`TableDesign` 只做列定义校验） | §3.10 两个前置不可绕 |
| 导入导出错误（`IO_TARGET_EXISTS` / `IO_PARTIAL`） | `ResultExporter` 已实现；导入询问与部分失败汇总未实现 | §3.12 逐批结局 |
| 服务器会话终止（`SESS_KILL_DENIED`） | `SessionMonitor` 只解析列表 | §3.13 确认 + 原话上浮 |
| 授权能力位（`LIC_NO_CAPABILITY`） | 未实现，入口可见性无统一判据 | §8.1 单点判定 |
| 凭据存储注入 | **已修（2026-10-25）**：`AppState.init` 默认 `KeychainSecretStore()` / `KeychainAgentKeyStore()`，文件实现只在测试态注入 | §2.2 构造函数注入（已落地） |
| 只读连接与生产标签联动 | 标签特性未实现，当前由 `policy.isEnabled` 全局开关承担 | §3.5 不得造旁路开关 |
| 内嵌浏览器 / 插件装载 / 端云同步 | 有实现文件但本节未逐函数展开 | 概要设计已定行为，本文件待补（§11 `DETAIL_GAP` 第 6 条） |

### 10.2 逐条自检

| # | 检查项 | 结论 | 证据 |
|---|---|---|---|
| 1 | §1.2 每个「修改」路径真实存在 | 过 | 15 张文件均在盘（`ls` 逐条） |
| 2 | §1.2 与 §1.3 路径集合交集为空 | 过 | 集合比对，交集 0 |
| 3 | 每个公开函数七段齐 | 过 | §3.1–§3.16 各含前置/后置/错误表/禁止/并发/日志/测试 ID |
| 4 | 每张错误表有「可重试」列且逐行有判定 | 过 | `audit_lld.py` 的 C01 读数 0 |
| 5 | 21 个错误码都有落点或标「未实现」 | 过 | §6.1 表 21 行 |
| 6 | 七个组件六态齐且「禁止渲染」非空 | 过 | §5.3.1–§5.3.7；U01 读数 0 |
| 7 | 矩阵无空「落点/测试 ID」 | 过 | §0.1 42 行全填 |
| 8 | 测试 ID 无悬空 | 过 | `audit_lld.py` 的 T01 读数 0 |
| 9 | 测试 ID 无孤儿 | 过 | `audit_lld.py` 的 T02 读数 0 |
| 10 | 未引入 §1.1 禁止项 | 过 | 12 条静态检查清单逐条检索为空 |
| 11 | 状态机未新增状态、未绕过 guard | 过 | §4.4 九行 + `.missing` 实现口径 |
| 12 | 落点节引用全部解析得到 | 过 | `audit_lld.py` 的 M04 读数 0 |
| 13 | 概设契约节全覆盖 | 过 | `audit_lld.py` 的 H02 读数 0（33 节逐节有行） |
| 14 | 无禁用词、无占位符 | 过 | `audit_lld.py` 的 W01 / P01 读数 0 |

---

## 11. 偏离处理与登记

| 信号 | 触发条件 | 动作 |
|---|---|---|
| `DETAIL_GAP` | 本文件未覆盖的公开行为 | 取最小假设继续，并登记到本节表 |
| `DETAIL_CONFLICT` | 与代码现状冲突 | 停工，报人类主人 |
| `CONTRACT_DEVIATION` | 偏离 §3 / §5.3 契约 | 等确认 |
| `PLATFORM_CHANGE` | 需要更换本端基线 | 停工 |
| `DESIGN_CONFLICT` | 与概要设计冲突 | 以概要设计的「禁止」为准，不自行裁决 |

已登记的 `DETAIL_GAP`（概要设计未定义、本文件按最小假设落地）：

| # | 未覆盖点 | 所做选择 | 影响范围 | 建议补的条款 |
|---|---|---|---|---|
| 1 | 行写回 SQL 的具体形态（是否带旧值条件） | 带主键 + 旧值条件，影响 0 行报冲突 | §3.9 | 概要设计 §4.6 补一句「写回带旧值条件」 |
| 2 | 导入批大小与回滚粒度 | 每批一个事务，批大小固定常量 | §3.12 | 概要设计 §4.8 补批粒度 |
| 3 | 笔记库事务隔离级别 | 同库单连接串行，用默认隔离级别 | §4.5 | 概要设计 §15.1 补隔离级别 |
| 4 | 「到期降级」后允许的导出格式集合 | 全部已支持格式均允许导出 | §8.1 | 概要设计 §3 授权判定补格式白名单 |
| 5 | 复盘插件装载失败时宿主的界面表现 | 宿主显示占据位 + 失败原因，不隐藏槽位 | §4.7 | 概要设计 §16.2 补宿主失败态 |
| 6 | 内嵌浏览器/插件装载/端云同步的逐函数契约 | 本文件暂不展开，只给禁止项 | §2.3、§5.3.7 | 本文件下一版补，或概要设计补组件级接口 |

已登记的 `DETAIL_CONFLICT`（与代码现状冲突，须人类主人裁决，Agent 不得自行改设计或改代码）：

| # | 冲突点 | 代码现状 | 契约要求 | 处置 |
|---|---|---|---|---|
| 1 | 凭据存储形态（**已闭合**） | 原：`AppState.secretStore = FileSecretStore()`（XOR 混淆）。现：`AppState.init(secretStore:)` 默认 `KeychainSecretStore()` | 概要设计 §3「口令只存密钥存储」；本文件 §2.2 构造函数注入 `SecretStore` | **已裁决（2026-10-25 人类主人令「改实现」）**：`AppState.init` 默认注入 `KeychainSecretStore()` / `KeychainAgentKeyStore()`，`FileSecretStore` 退为测试态；本行保留留痕，冲突关闭 |

暂定口径承接（概要设计 §14.1 第 4、5、6、8 条，本端按暂定口径实现，人类主人可否决）：

- 审批单过期 = 拒绝（`.expired` 不可翻批准）；撤回 = `.denied` 并留痕；已批准未执行的按拒绝处理。
- 影响行数取不到 ⇒ 审批单写「未接」并照常提交，不得用表总行数或本地估算填充。
- 助理桥「自动附带上下文」默认关闭，仅当前会话显式勾选时附带，每次附带写审计。
- 设备配额超限：提示「先移除最久未使用的一台」并列出候选，禁止自动踢设备。

---

## 12. 变更记录

| 版本 | 日期 | 变更内容 | 影响的概设条款 | 影响的实现单元 |
|---|---|---|---|---|
| v1.7 | 2026-10-25 | **并行编排落地到实现级契约**：新增 §3.20 `AgentOrchestrator.run(_:options:)`（无依赖前置校验 / 并发上限 1–8 缺省 4 / 单路 10 分钟超时 / 失败隔离 / 深度锁死禁止再派 / 需审批回主控 / 归并只收摘要与产物路径）；矩阵 +1 行（46→47）；§9.2 +3 用例。 | 概设 §3 组件契约（并行编排）· §11.4 AI-004 | `AgentOrchestrator` |
| v1.6 | 2026-10-25 | **对齐 Hermes 工具能力箱的两项缺口落地到实现级契约**：新增 §3.18 `AgentCodeRunner`（沙箱无网 / 30s / 512MB / 输出截断 / 临时目录即清 / 缺解释器如实报）与 §3.19 `AgentToolCatalog`（按名与用途检索、schema 可取回缓存、未取回不得调用、接入类离线标 unavailable）；矩阵 +2 行（44→46）；§9.2 +5 用例（`T-3.18-01`~`03`、`T-3.19-01`~`02`）。 | 概设 §3 组件契约（代码执行 / 工具目录）· §11.4 SEC-005 | `AgentCodeRunner` · `AgentToolCatalog` |
| v1.5 | 2026-10-25 | **补 Agent 命令执行能力（人类主人发现 `run_command` 在代码里、书里没有）**：新增 §3.17 `AgentCommandRunner.run(_:in:timeout:)` 七段契约（前置授权目录 / 后置三选一 / 错误表含「可重试」列 / 禁止 `sh -c` 拼接与主线程起进程 / 串行不并行 / 审计只记命令哈希不记原文）；矩阵补 §3 命令执行行与 §8.11 界面语汇行（44 行）；§9.2 新增 `T-3.17-01`~`04` 与 `UI-5.8-02`。 | 概设 §3 组件契约（命令执行）· §8.11 · §11.4 PERF-006 | `AgentCommandRunner` · `AgentChatView` |
| v1.4 | 2026-10-25 | **Agent 界面按 Hermes TUI 基准补齐三节**：§5.3.8.1 版式语汇（行首栏字形表 / 一个字号 / 边框只给要人动手的卡 / 状态行字段序 / 启动界面五块 / 令牌尺寸 / 九条禁止）+ 参考基准登记（两张截图 + TUI 四个骨架源码 + display 段与皮肤引擎）；§5.3.8.2 渲染骨架与可配置项（三个骨架部件↔本端落点、`statusBarSegments`/`blockLayout` 必须纯函数并单测、10 个行为开关表、主题键按角色归并、明暗不合并的坑）；§5.3.8.3 皮肤与品牌值表（YAML 字段→本端主题表逐条、9 套内置不照搬只作覆盖度参考、customCSS 不提供、两条合并规则坑）。 | 概设 §4.10 / §8.4；§11.4 `UI-001` | `App/Views/AgentChatView.swift` · `Core/DesignTheme.swift` · `Core/DesignTokens.swift` · `App/AppTheme.swift` |
| v1.3 | 2026-10-25 | **`DETAIL_CONFLICT` 第 1 条闭合（人类主人令「改实现」）**：`AppState.init(secretStore:agentKeyStore:)` 默认注入 `KeychainSecretStore()` / `KeychainAgentKeyStore()`，`FileSecretStore`（XOR 混淆）退为测试 / 开发态显式注入；§2.2 / §8.1 / §10.1 / §11 / §13.5 五处同步改写，冲突行保留留痕。判据：`grep -n 'FileSecretStore()' App/` 只命中测试注入点。 | 概设 §3 平台适配层契约（凭据存取）；§11.4 `AI-007` | `App/AppState.swift`（init 注入）· `Platform/macOS/KeychainSecretStore.swift` · `Platform/macOS/KeychainAgentKeyStore.swift` |
| v1.2 | 2026-10-25 | 按 `detail-design-spec-writing` 自检修齐：新增 §2.2 注入点（数据库/方言/时钟/ID/HTTP/凭据/文件定位的注入方式写死）与 §2.3 命名约束；§3 由 6 节散文改为 16 节逐函数契约（每节七段 + 唯一错误契约表 + 可重试列）；§5.3 拆成 5.3.1–5.3.7 七个组件六态小节（每节六态齐、禁止渲染列逐行非空），新增 §5.4–§5.8（状态流、动作映射、表单校验、导航权限、界面用例表 17 条）；§6 拆 6.1/6.2/6.3；§7 拆 7.1/7.2；§8 拆 8.1/8.2；§0.1 矩阵由 21 行拆到 42 行（概设契约节逐节有行，含 §3.1、§4.5–§4.10、§5.2–§5.4、§6.2–§6.4、§7.2、§7.3、§8.2–§8.10、§11.4、§14.1、§18.1、§19.2）；§11 增 `DETAIL_GAP` 6 条与 `DETAIL_CONFLICT` 1 条；已知坑移至 §13。读数（审计脚本实跑）：硬失败 6→0、告警 3→0、矩阵 21→42 行、悬空测试 ID 18→0、孤儿测试 8→0、占位符 1→0、禁用词 1→0；门禁 `check-doc-tables.py` / `check-doc-layout.py` 均 rc=0 | 概要设计 §3 / §4.1–§4.10 / §5.1–§5.4 / §6.1–§6.4 / §7.1–§7.3 / §8.1–§8.10 / §9 / §11.4 / §14.1 / §18.1 / §19.2 | `Core/DatabaseService.swift`、`ExecutionSafety.swift`、`ConnectionStore.swift`、`AgentApprovalGate.swift`、`MetadataService.swift`、`RowBrowsing.swift`、`TableDesign.swift`、`ResultExporter.swift`、`AgentContext.swift`、`AgentPlanRows.swift`、`App/AppState.swift`、`App/Views/*` |
| v1.1 | 2026-10-21 | 扫差补齐：§0 范围加 Notes / Retro；矩阵补 §15 笔记域、§16 复盘域两行；新增复盘宿主节（本端只宿主，实现在他仓） | 概要设计 §15 / §16 | `App/Views/RetroHostView.swift`、`Plugins/Notes/Sources/` |
| v1.0 | 2026-10-21 | 全量重写：补追溯矩阵、基线与被拒方案 12 条转禁止项、函数七件套、数据/存储/伪代码/状态覆盖、界面六态与动作映射、21 码错误映射、测试 ID 表、自检 10 条；保留 v0.1 的笔记 / 会话 / 已知坑 / 判据表 | 概要设计 §3–§12 全部 | `Core/`、`App/`、`Platform/macOS/` |
| v0.1 | 2026-10-23 | 首建：分层与模块表 + 三个核心模块详设 + 会话搜索 + 并发模型 + 四条已知坑 + 判据表 | — | macOS 端 |

---

## 13. 本端已知坑（必须先读）

### 13.1 PG 18 改进数据语句的 `Plan Rows` 在根节点上是 0

`EXPLAIN (FORMAT JSON) UPDATE …` 的根节点是 `ModifyTable`，`Plan Rows` 恒为 0（不带 `RETURNING` 时它不输出行），真实预估在子节点（如 `Seq Scan` 500）。只读根会稳定报「0 行」，这是最危险的假数。

规则：根为 `ModifyTable` / `Update` / `Delete` / `Insert` / `Merge` 且根值为 0 ⇒ 取 `Plans` 的第 0 项；根非 0（带 `RETURNING`）用根。这条只有对真库跑才能发现，落点见 §3.16。

### 13.2 `swift test` 不带 `DEVELOPER_DIR` 会找不到 XCTest

报 `unable to resolve module dependency: 'XCTest'`。跑法：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`。

### 13.3 测试总数只认 `verify-core.sh`

`swift test --filter` 的 `Executed N tests` 是过滤后的数，不能当 Core 总数；真值在 `bash Scripts/verify-core.sh` 写出的 `.build/core-test-count.txt`。

### 13.4 localization 棘轮与锚仓 `pre-push` 护栏

- `check-core-localization` 基线上调需授权，不得自行 `--update-baseline`。
- 锚仓 `.git/hooks/pre-push` 白名单只放 `Docs/` 一类路径；推 `Scripts/` 会被拦，需 `-c core.hooksPath=/dev/null` 单次绕过并留痕。

### 13.5 `FileSecretStore` 仍留在仓里，只能测试态注入

2026-10-25 人类主人裁定「改实现」后：`AppState.init(secretStore:agentKeyStore:)` 默认注入 `KeychainSecretStore()` / `KeychainAgentKeyStore()`，口令与模型密钥都进系统钥匙串。`FileSecretStore`（XOR 混淆）只剩测试 / 开发态用途 —— **任何新代码不得把它当默认值**，判据：`grep -n 'FileSecretStore()' App/` 只能命中测试注入点，不许命中 `AppState` 的存储声明。

### 13.6 文档门禁的两条本端口径

- `audit_lld.py` 的测试 ID 定义面只认 §4.4 / §5.8 / §9.2 三节正文：用例只写进 §9.1 会被算成悬空，必须落 §9.2。
- `check-doc-tables.py` 会把「表格后紧跟一行普通散文」判成续行：每张表后面必须留空行或起新块。
