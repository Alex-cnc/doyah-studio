# Doyah产品概要设计说明书

当前 v3.3.0（2026-10-22 设计层四章重写）

> 上游：《Doyah产品能力规划说明书》v1.246（156 个能力点）、《Doyah产品需求规格说明书》v3.421（§3/§4/§7 共 438 条，另有 §5 数据与 §6 接口需求）。
> 本书按「整个产品」重写：**五个产品线 × 92 个需求域全覆盖**，契约章每节点名需求编号，指不到编号的条目不写。
> 契约层 / 实现层是**权限归属的两分**，不是章节的两分：契约条文集中在第三、四章的「必须一致」列，实现做法集中在第九章。

# 第一章 引言

## 1.1 目的

回答三个问题，使任何人在只有本书与上游两本书的情况下，能在任一平台端做出行为一致的实现：

1. **哪些东西各端必须一字不差地做到**（第三章，契约层）；
2. **哪些差异是刻意允许的，为什么**（第四章，差异登记）；
3. **各端具体怎么做**（第九章，实现层）。

本书不重复需求书的判据，也不记录进度：判据在需求书、状态在《开发计划书》§3 台账、证据在追溯表。本书只说「怎么做才让判据成立」。

## 1.2 范围

| 产品线 | 覆盖 | 需求域数 |
|---|---|---|
| 智能体（AGT） | 循环、计划、权限、记忆、工具、通道、质量核验、可观测 | 23 |
| 数据库工作台（STD） | 通用能力（构建 / CLI / 许可 / 插件 / 接口）+ 数据库域 + 界面域 | 27 |
| 笔记（NTS） | 捕获、格式、整理、搜索、同步、回收站、版本、附件、导出；待办 | 14 |
| 交易复盘（RTR） | 数据流、行情、复盘、研究报告 | 18 |
| 横切（ALL） | 性能、可靠、安全、兼容、可维护、易用、本地化、AI 使用、界面、风险 | 10 |

不在本书范围：需求取舍（上游决定）、发布排期（计划书）、风险登记册逐条内容（归计划书与风险册）。

## 1.3 读者与用法

| 读者 | 读法 |
|---|---|
| 各端开发者 | 第三、四章通读；第九章读本端那一节 |
| 需求 / 产品 | 第三、九章；契约与需求冲突时以上游为准并回流 |
| 验收 | 第十章 + 第七章「界面设计」+ 第四章「必须一致」列 |

读法：**先读第三章（契约），再读第九章本端那一节（做法）**。第四章只解释差异，不构成放宽契约的理由；契约与差异冲突时以契约为准，并补一条 `P-xx` 或改契约。任何「这一端特殊」的说法，若不在第四章表内，验收时按缺陷处理。

## 1.4 术语

| 术语 | 含义 |
|---|---|
| 契约 / 不变量 | 各端必须一致的可观察行为；换实现可以，换结果不行 |
| 差异登记 `P-xx` | 明确允许不同的点，逐条写「为什么必须不同」 |
| 契约层 / 实现层 | 权限归属：契约层单点维护，实现层各端自管 |
| 域 | 需求编号里的面与域（如 `STD-DB-CONN`），一个域对应契约章的一节 |
| 渲染派生物 | 由权威数据生成、不反向写入的产物（索引、导出、摘要） |

## 1.5 参考

上游三件：《能力规划说明书》管「是什么 / 不是什么 / 边界」；《需求规格说明书》管「要什么 / 怎么算做到」；《开发计划书》管「做到哪了」。

工程约定：`AGENT-SPEC.md`（智能体侧实现约定）、`Docs/design/能力书到需求书-派生规程.md`（派生十步）。

# 第二章 总体设计

本章写「代码放在哪、由谁调用、跑起来是什么形状」。每条判断都指向仓内文件；查不到实据的地方写「待定」，不补想象。
macOS 侧的物理形态是一个 SwiftPM 包（`Package.swift` 声明 `DoyahCore`、`DoyahPlatform`、`DoyahCLI`、`DoyahStudioApp`、`doyah-license-tool` 五个目标，外加一条到 Retro 锚仓的路径依赖）；Windows 与 Linux 的前端在 `Platform/windows`、`Platform/linux` 各自自洽，不在本章的 Swift 目标图内。

## 2.1 分层与依赖方向

四层，依赖只向下。表 2-1 给每层的目录、代表类型与禁止项；表 2-2 给「协议在上、实现在下」的落点。

**表 2-1 四层的职责与禁止项**

| 层 | 目录与规模 | 代表类型 | 职责 | 不许做的事 | 依据 |
|---|---|---|---|---|---|
| 界面层 | `App/`（131 个 `.swift`，其中 `App/Views` 93 个）、`Plugins/Notes/Views`（3 个） | `DoyahStudioApp`、`MainWindow`、`ActivityBarView`、`QueryWorkspaceView`、`NotesAreaView`、`AppState` | 画面、页签、命令、快捷键；把用户动作翻成一次领域调用 | 直接建库连接；直接拼 SQL；直接读写笔记库文件 | `App/Views/MainWindow.swift`、`App/AppState.swift:231` |
| 领域层 | `Core/` 内的值类型与纯函数 | `ExecutionSafety`、`ExecutionScope`、`StatementSplitter`、`SQLLinter`、`QueryMemory`、`TodoQuery`、`LicensePresentation` | 规则判定、状态机、格式化；进出都是值 | 持有连接；持有界面状态；自带语言 | `Core/ExecutionSafety.swift`、`Core/ExecutionScope.swift`、`Core/LicensePresentation.swift` |
| 能力层 | `Core/` 内的协议与 actor | `DatabaseService`（Core 共 21 个协议之一）、`PostgresService`/`MySQLService`/`GBaseService`、`LLMClient`、`MCPClientBridge`、`NoteLibrary` | 把外部世界（库、模型、文件、通道）收成可替换接口 | 出现「当前页签」这类页面概念 | `Core/DatabaseService.swift`、`Core/LLMClient.swift` |
| 平台适配层 | `Platform/macOS`（5 个 `.swift`） | `KeychainSecretStore`、`KeychainAgentKeyStore`、`MacDirectoryAccess`、`WebKitBrowserEngine`、`FoundationSecurityScopedBookmarking` | 唯一可以 `import Security` / Darwin / WebKit 的地方 | 定义业务规则 | `Platform/macOS/*.swift` |

**表 2-2 协议在 Core、实现在平台模块**

| 协议（Core） | 平台实现（`Platform/macOS`） | 依据 |
|---|---|---|
| `SecretStore` | `KeychainSecretStore` | `Core/SecretStore.swift`、`Platform/macOS/KeychainSecretStore.swift:14` |
| `AgentKeyStore` | `KeychainAgentKeyStore` | `Core/AgentConfigurationStore.swift`、`Platform/macOS/KeychainAgentKeyStore.swift` |
| `SecurityScopedBookmarking` | `FoundationSecurityScopedBookmarking` | `Core/SecureDirectoryAccess.swift`、`Platform/macOS/FoundationSecurityScopedBookmarking.swift` |
| `DirectoryPicker` | `MacDirectoryAccess` | 同上、`Platform/macOS/MacDirectoryAccess.swift:15` |
| `BrowserEngine` | `WebKitBrowserEngine` | `Core/BrowserPage.swift:199`、`Platform/macOS/WebKitBrowserEngine.swift:22` |

方向不是靠自觉，有三条机制：

1. **模块依赖单向**。`DoyahPlatform` 依赖 `DoyahCore`；`DoyahCore` 的 `dependencies` 里只有 `PostgresNIO`、`MySQLNIO`、`Crypto`、`CSQLite3`，没有 `DoyahPlatform`。反向引用在编译期就不成立（`Package.swift`）。
2. **静态闸门**。`Scripts/check-core-portability.py` 剥掉注释后扫 `Core/**/*.swift`，出现 `Security`、`Darwin`、`OSStatus` 一类平台符号即红；确需例外时在该行写 `// portability-ok: 理由`。它同时是 `Scripts/verify-all.sh` 的第 2 项。
3. **协议与实现分居两模块**（表 2-2）。`BrowserEngine` 的实现在平台模块里，`DatabaseService` 的三个实现都是 `Core` 里的 `actor`——因为数据库驱动本身跨平台（`Vendor/postgres-nio`、`Vendor/mysql-nio` 随仓库带走）。

一处需要如实说明：`Core` 是**平铺**的——246 个 `.swift` 直接在 `Core/` 下（另加 `Core/Plugin` 3 个），领域层与能力层之间没有目录级边界，区分靠命名与依赖方向（纯函数 vs 协议 + actor）。门禁真正强制的是「Core 不碰平台」，不是「领域不许引能力」。

越层有三个可判信号，都能落到具体文件：一是 `Core` 里出现平台符号（`Security` / `Darwin` / `OSStatus`）——这条由第 2 条机制机械判定；二是 `Core` 里出现页面概念（`selectedTab`、页签、`AppState` 这类词，`DatabaseService` 的接口上没有任何一处）；三是同一份规则在两处实现（`ExecutionScope.resolve` 判「跑哪一段」只此一处，`EditorCommandCenter` 只负责把显示中编辑器的选区交出来）。

「界面层不许碰平台」这句话要说得更准：`App/` 实测里有 2 处 `import Darwin`（`App/LocalPort.swift`、`App/TerminalSession.swift`）、1 处 `import UserNotifications`（`App/ReminderNotifier.swift`）、1 处 `import WebKit`（`App/Views/BrowserTabView.swift`）——窗口进程本来就要这些。层级纪律的强制点在**下面**那一侧：Core 保持平台中立，界面层用哪个平台框架是它的本分，不是越界。

## 2.2 组件构成

**表 2-3 组件 → 目录/主要类型**

| 组件 | 目录与主要类型 | 职责 | 依据 |
|---|---|---|---|
| 应用外壳 | `App/DoyahStudioApp.swift`、`App/Views/MainWindow.swift`、`App/AppState.swift` | 一个 `WindowGroup`；活动栏 + `NavigationSplitView` + 下方面板；`AppState` 以 `@MainActor` 持有全部界面状态 | 同左 |
| 数据库工作台 | `Core/DatabaseService.swift`、`PostgresService`、`MySQLService`、`GBaseService` | 三方言语义收在同一协议；不支持的 COPY 抛可读错误，不退化成逐条 INSERT | `Core/DatabaseService.swift:53` |
| 执行与结果 | `Core/ExecutionRegistry.swift`、`Core/QueryModels.swift`、`App/Views/ResultTableView.swift`、`App/Views/LowerPaneView.swift` | 句柄定向取消；事件单通道；结果默认上限 10 000 行且截断可见 | `Core/QueryModels.swift:113` |
| 工作区与编辑器 | `App/WorkspaceTabsModel.swift`、`Core/WorkspaceTab.swift`、`App/Views/CodeEditorView.swift`、`App/WorkspacePathIndex.swift` | Home / 文件 / 对话三种页签；FSEvents 监听磁盘改动；路径索引在自有队列上 | `Core/WorkspaceTab.swift:12` |
| 智能体运行时 | `Core/Agent*`（46 个）、`Core/LLMClient.swift`、`Core/LLMRetry.swift`、`Core/MCP*` | 循环、工具注册、审批闸门、审计、模型调用与重试 | `Core/AgentLoop.swift`、`Core/AgentApprovalGate.swift` |
| 笔记 | `Plugins/Notes/Sources`（23 个）、`Plugins/Notes/Views`（3 个） | `NoteLibrary` 是唯一入口；写库一次一个事务 | `Plugins/Notes/Sources/NoteStorage/NoteLibrary.swift:19` |
| 复盘 | `App/Views/RetroHostView.swift`、`Plugins/Retro/plugin.json`、外部包 `DoyahRetroUI` | 宿主只装配，视图代码不复制 | `App/Views/MainWindow.swift:207` |
| 插件装配 | `Core/Plugin/PluginManifest.swift`、`Core/Plugin/PluginRegistry.swift`、`Core/Plugin/PluginMounts.swift` | 「哪个挂点归谁」的唯一来源 | `Core/Plugin/PluginRegistry.swift` |
| 许可 | `Core/License.swift`、`Core/LicensePresentation.swift` | 「哪个档看到哪几块」的判据在 Core，可穷举单测 | `Core/LicensePresentation.swift:16` |
| CLI | `CLI/main.swift`、`CLI/CLIFailureText.swift`、`CLI/PluginCommands.swift`、`CLI/AgentStreamCommand.swift` | 复用 Core，不引 App | 同左 |
| 构建与门禁 | `Scripts/verify-all.sh`（1 035 行、18 项）、58 个 `check-*.py` | 一条命令跑完十八项，失败当场中止并报「哪些项没跑」 | `Scripts/verify-all.sh` |

组件之间只经能力层接口通信。`PluginRegistry` 的文件注释把反例写死了：宿主里一旦出现 `if pluginNotes { … }` 这种按插件名分支的代码，「删掉插件功能就消失」就不再可机械判定，所以挂点归属只从注册表查，由 `Scripts/check-plugin-assembly.py` 断言。

## 2.3 模块划分（五条产品线）

**表 2-4 产品线 → 目录、入口、关键类型**

| 产品线 | 主要目录 | 入口 | 关键类型 | 依据 |
|---|---|---|---|---|
| 智能体 | `Core/Agent*`（46）、`Core/LLM*`、`Core/MCP*`、`App/AgentChatModel.swift`、`App/Views/AgentChatView.swift`、`CLI/AgentStreamCommand.swift` | 对话页签（`WorkspaceTab.Kind.agentChat`）+ CLI 子命令 | `AgentLoop`、`AgentToolRegistry`、`AgentApprovalGate`、`AgentAuditLog`（actor）、`LLMClient` | `Core/WorkspaceTab.swift:12`、`Core/AgentAudit.swift:494` |
| 通用与数据库 | `Core/Connection*`、`Database*`、`SQL*`、`Result*`、`Object*`、`Table*`、`Postgres*`、`MySQL*`、`Core/Dialects.swift` | 活动栏 `.database` | `DatabaseService`、`ExecutionRegistry`、`QueryResult`、`ExecutionSafety` | `Core/LicensePresentation.swift:22` |
| 工作台界面 | `App/`（131）、`Core/Workspace*`、`Code*`、`Editor*`、`Terminal*`、`Design*`、`Menu*` | 活动栏 `.workspace`、系统菜单、命令面板 | `WorkspaceTab`、`WorkspaceTabsModel`、`AppState`、`MainMenuLocalizer` | `App/Views/MainWindow.swift:199` |
| 笔记 | `Plugins/Notes/Sources`（23）、`Plugins/Notes/Views`（3）、`Core/Todo*`、`Core/Note*` | 活动栏 `.notes` | `NoteLibrary`（actor）、`NoteDatabase`、`NoteAutosave`、`NoteBodyProjection` | `Plugins/Notes/plugin.json`、`Plugins/Notes/Sources/NoteStorage/NoteAutosave.swift` |
| 交易复盘 | `Plugins/Retro/plugin.json`、`App/Views/RetroHostView.swift`、外部包 `DoyahRetroUI` | 活动栏 `.retro` | `RetroHostView` | `Package.swift`（路径依赖）、`App/Views/MainWindow.swift:207` |

五条线在运行时共享一个 `AppState` 与一份许可判据（`LicensePresentation.activityItems` 决定活动栏上有哪几项，未授权的区**不出现**而不是灰掉）。跨线的数据通道被刻意收窄：笔记侧入口只收标题 / 正文 / SQL / 连接名，行数据必须显式 `withRowData()` 才能进笔记，且开关全仓只有一处能打开——`Scripts/check-plugin-assembly.py` 的 `FR-STD-ALL-PLUG-003` 判据守着这条。

## 2.4 运行时拓扑

单进程、多模块常驻。五个 SwiftPM 目标加一个外部视图包：

**表 2-5 进程内的模块装配**

| 目标 | 形态 | 内容 | 依据 |
|---|---|---|---|
| `DoyahCore` | library | `Core` + `Plugins/Notes/Sources` | `Package.swift` |
| `DoyahPlatform` | library | `Platform/macOS` | 同左 |
| `DoyahStudioApp` | executable | `App` + `Plugins/Notes/Views` | 同左 |
| `DoyahCLI` | executable | `CLI` | 同左 |
| `doyah-license-tool` | executable | `Tools/LicenseTool`（签发侧，不进 `.app`） | 同左 |
| `DoyahRetroUI` | 路径依赖 | `/Users/alex/dev/doyah/lead/retro/platform/macos` | 同左 |

三条事实：

- **全仓无 IPC**。`NSXPC`、`xpc_`、`import XPC` 在 `Core`/`App`/`CLI`/`Plugins` 的实测命中为 0；`Scripts/check-plugin-assembly.py` 的第一条判据就是「全仓无 IPC」。
- **插件是清单 + 注册表 + 挂点**，不是可卸载动态包。清单 `Plugins/Notes/plugin.json` 与 `Plugins/Retro/plugin.json` 声明 `id`、`version`、`apiVersion`、`entryTarget`、`contributions`、`storage`：笔记的 `entryTarget` 是 `DoyahStudio`（编进宿主模块），复盘的 `entryTarget` 是 `DoyahRetroUI`（外部包）。加载不到时返回 `PluginRegistry.empty`——「插件不在就是不在，不是错误」；能加载但降级的要写进 `PluginRegistry.Degraded` 并落诊断行。
- **不设独立进程的三条理由**，逐条有代码依据：① 取消必须定向——`ExecutionHandle` 与 `ExecutionRegistry` 的裁决（`cancelActive` / `markOnly` / `alreadyFinished`）建立在「同一连接上一次只有一条在跑」这个进程内事实上；② 结果直通——`DatabaseService.execute` 返回 `AsyncThrowingStream<QueryEvent, Error>`，`QueryResult.rows` 是 `[[String?]]`，跨进程要把整个结果集序列化；③ 失败面——插件与宿主同模块编译，清单缺失只是空注册表，不引入第二个可失败边界。

**产物与装配文件是两套，分工写死。** 发布链走 `Scripts/build-app.sh`：不依赖 Xcode GUI，用 SwiftPM 编 App 源码后组装成 `.app` 并做 ad-hoc 签名，产物落在 `dist/DoyahStudio-<发布标签>.app`，`dist/DoyahStudio.app` 只是指向最新一份的软链（身份以带版本号的实物为准）。`project.yml` 生成的 `.xcodeproj` 是**给人用 IDE 打开的入口，不参与发布链**；它与 `Package.swift` 的差异（目标集合 5 个 vs 9 个、未声明 `MySQLNIO`/`CSQLite3`/`Crypto`）已登记为已知边界。生成物不许手改、也不许过期，由 `Scripts/check-release-version.py` 判住版本号「一个值、三处逐字一致」。

**表 2-6 产物与装配文件**

| 文件 | 角色 | 是否发布链 | 依据 |
|---|---|---|---|
| `Package.swift` | 唯一的依赖与目标声明；Core 的依赖只有四个 vendor 包 | 是 | `Package.swift` |
| `Scripts/build-app.sh` | 编 App、组 `.app`、ad-hoc 签名、沙箱为显式开关 | 是 | `Scripts/build-app.sh` |
| `project.yml` → `DoyahStudio.xcodeproj` | 给人用 IDE 打开的入口 | 否 | `project.yml` |
| `dist/` | 带版本号的实物 + 最新一份的软链 | 是 | `dist/DoyahStudio.app` |

## 2.5 并发与线程模型

Swift 并发标注的实测分布：`@MainActor` 61 处（24 个文件）、`actor` 18 个、`@unchecked Sendable` 11 个、`Sendable` 出现 735 处、`nonisolated` 26 处。

**表 2-7 四个隔离域**

| 隔离域 | 载体 | 实际成员 | 规矩 | 依据 |
|---|---|---|---|---|
| 主线程 | `@MainActor` | `AppState`、`AgentChatModel`、`WorkspaceTabsModel`、`QueryEditorBuffer`、`TerminalTabsModel`、`MainMenuLocalizer`；Core 侧 4 个：`AgentLoop`、`BrowserPage`、`CodeFormatting`、`ObjectTreeRefreshGate` | 只做状态与绘制 | `App/AppState.swift:230`、`Core/AgentLoop.swift` |
| 串行 actor | `actor` | `PostgresService`、`MySQLService`、`GBaseService`、`ConnectionStore`、`SavedQueryStore`、`QueryHistoryStore`、`SQLArchiveWriter`、`DataTaskStore`、`AgentScheduleStore`、`AgentConfigurationStore`、`AgentAuditLog`、`EgressLog`、`BrowserTabStore`、`CursorFetcher`、`DirectoryBookmarkStore`、`NoteLibrary`、`NoteStore`、`OutputCollector` | IO 与连接住在这里，一次一条 | 各文件声明行 |
| 专用队列 | `DispatchQueue(label:)` | `TerminalSession`（`studio.doyah.terminal.io` / `.write` / `.reaper`）、`WorkspaceFileWatcher`（`studio.doyah.workspace-watcher`）、`WorkspacePathIndex`（`studio.doyah.workspace.path-index`，`qos: .utility`）、`MCPStdioTransport`（global） | 回调回主线程一律 `DispatchQueue.main.async` | `App/TerminalSession.swift:40`、`App/WorkspaceFileWatcher.swift:71`、`App/WorkspacePathIndex.swift:36` |
| 带锁引用 | `@unchecked Sendable` + `NSLock`（或类型本身无可变状态） | `ExecutionRegistryBox`、`AgentWriteCoordinator`、`FileSecretStore`、`FileAgentKeyStore`、`SSHTunnelProcess`、`MySQLResultBox`、`BackupExecution.LineTail`、`MCPClientBridge`、`NotImplementedDatabaseService`、`AgentQueryExecutorBridge.Box`、`AgentChatModel.CancellationFlag` | 只在「类内部真有一把锁」或「类型本身无状态」时使用 | 各文件声明行 |

跨域只传值。`QueryResult`、`ColumnMeta`、`QueryEvent`、`QuerySummary`、`WorkspaceTab`、`TabLogEntry` 都是 `Sendable` 值类型；流走 `AsyncThrowingStream<QueryEvent, Error>`；全仓 `withCheckedContinuation` / `withCheckedThrowingContinuation` 实测 0 处——不把回调桥成挂起点，需要等的地方用 `async` 本身。

四条禁止项，每条都有现行写法作反例：

- 不许把非 `Sendable` 引用塞进 actor；跨域一律值或 `Sendable` 协议存在（`DatabaseService: AnyObject, Sendable`）。
- 不许用 `@unchecked Sendable` 掩盖「其实没锁」：现有 11 处里，带锁的（`ExecutionRegistryBox`、`AgentWriteCoordinator`、`FileSecretStore`…）在类内部持 `NSLock`，无状态的（`NotImplementedDatabaseService`）本身没有可变字段，两种情况都不靠「相信编译器」。
- 不许在主线程上等 IO：笔记自动保存用 `Task.sleep` 挂起，注释写明「敲键盘这条路上只有『取消 + 新建一个 Task』，**没有一次同步写盘**」（`App/AppState.swift:7911`）。
- 取消不是故障：`CancellationNoise.isNoise(_:taskIsCancelled:)` 先把 `CancellationError` 与 `Task.isCancelled` 判成噪声，避免一次正常取消被显示成「SQL 执行失败」。

主线程上唯一的等待形态是 `await` 一次 actor 方法，且等待前后都有可见状态：`executeQuery` 在 `ensureService` 之前把状态写成「正在连接」，拿到服务后写「正在执行」，事件到达时逐条更新。这条纪律解决的是「界面看起来卡住」而不是吞吐——真正耗时的那一段在 `PostgresService` / `MySQLService` 这两个 actor 里，主线程只是挂着等一个 `Sendable` 结果。

## 2.6 启动与关闭顺序

**表 2-8 冷启动与退出**

| 序 | 动作 | 失败处置 | 依据 |
|---|---|---|---|
| 1 | 单实例判定；接管启动优先；两个探针放行 | 激活成功则自己 `exit(0)`；激活失败**继续运行**（宁可短暂多一个实例，也不让用户看不到界面） | `App/DoyahStudioApp.swift` |
| 2 | tooltip 延迟压到 150 ms；`MainMenuLocalizer.start()` | — | 同左 |
| 3 | `AppState.init`：建首页签、许可证 → 可见活动项、下方页签与段对齐、写一行档位 | 落到可见项，不让界面停在「选着但画不出来」 | `App/AppState.swift:1460` |
| 4 | `startupChain`：`loadConnections` → `loadSavedQueries` → `restoreBrowserTabs` → `reloadNotes` → `loadQueryHistory` | 各自失败各自说话 | `App/AppState.swift:1482` |
| 5 | 窗口 `.task`：工作区接线、`startWorkspaceWatching`、`loadAgentSchedules`、`startAgentScheduleTicker`、`workspaceTabs.restoreSession()`、`workspace.load()` | 快照读不动 / 源文件找不到 / 有未保存改动，三句话都说出来 | `App/Views/MainWindow.swift`、`App/WorkspaceTabsModel.swift:331` |
| 6 | 退出：`willTerminate` → `workspaceTabs.saveSession()` | 保存失败写 `errorText`，不静默 | `App/DoyahStudioApp.swift`、`App/WorkspaceTabsModel.swift:303` |

恢复语义有三处刻意的取舍。其一，快照记页签集、选中页与**选中那一页**的光标 / 滚动（只记一个位置，因为同一时刻只有一页能看见）。其二，Home 页关不掉，快照里缺它就补一个——没有它工作区就没有默认落脚点。其三，写快照的时机分两条：浏览器页签每次变化即写，工作区页签**退出时写**——后者带正文，跟着按键写等于每敲一个字写一次盘。

快照的读写收在 `WorkspaceSessionStore`（Core 里的值类型，`load()` / `save(_:)` 两个方法），界面只调 `restoreSession()` 与 `saveSession()`——恢复策略与快照格式因此可以脱离界面单测。

## 2.7 数据流

### 2.7.1 一条 SQL 从输入到结果

**表 2-9 SQL 执行路径**

| 步 | 落点 | 说明 | 依据 |
|---|---|---|---|
| 1 | `commitEditorDraft` + `ExecutionScope.resolve(text:selection:)` | 先提交编辑器缓冲；**有选区跑选区、没选区跑整篇**，选区取显示中的编辑器而非缓存 | `App/AppState.swift:6802`、`Core/ExecutionScope.swift` |
| 2 | `SQLParameters.hasParameters` → 参数面板 | 有占位符先取值，不在未取值时执行 | `Core/SQLParameters.swift` |
| 3 | `ExecutionSafety.check` | `needsConfirmation` 进确认；`refused`（只读连接）直接拒，不给「仍然执行」 | `Core/ExecutionSafety.swift` |
| 4 | `TransactionSession.prepareStatement()` | 手工模式第一条语句前懒发 BEGIN；失败事务只接受回滚 | `Core/TransactionSession.swift` |
| 5 | `ensureService(ServiceKey(connectionID:database:))` | 服务按「连接 + 库」缓存并跨页签共享 | `App/AppState.swift` |
| 6 | `service.execute(sql, options: .default, handle:)` | 返回 `AsyncThrowingStream<QueryEvent, Error>`；句柄取自 `executionHandles[tabID]` | `Core/DatabaseService.swift:23` |
| 7 | `for try await event`：`started` / `resultSet` / `notice` / `finished` | 行数只由 `AffectedRowsTally.absorb` 累加一次 | `Core/QueryModels.swift:88` |
| 8 | `QueryTab.results`、`statusMessage`（`didSet` → `TabLog`） | 有表格的结果不进 Output 日志，避免两页签重复 | `App/AppState.swift:45` |
| 9 | `recordHistory` + `archiveExecutedSQL` | 取消记 `succeeded: false` 并带原因，不记成成功 | `App/AppState.swift:1906` |
| 10 | `cancelQuery` → `service.cancel(handle)` → `CancelOutcome` | 四种结局都要说出来；拿不到后端 PID 也归 `failed(reason:)` | `Core/ExecutionRegistry.swift:31` |

### 2.7.2 一条笔记从编辑到落盘

**表 2-10 笔记写库路径**

| 步 | 落点 | 说明 | 依据 |
|---|---|---|---|
| 1 | 编辑框三个 `didSet` → `noteEditorTextChanged` | 装内容期间不算改动 | `App/AppState.swift:7901` |
| 2 | `noteSaveState = .pending` + `scheduleNoteAutoSave()` | 取消上一发、重开一发；`NoteAutosave.pauseWindow` = 1 500 ms | `Plugins/Notes/Sources/NoteStorage/NoteAutosave.swift` |
| 3 | `autosaveNoteEditor` 三条守卫 | 许可 / 有内容 / 真有改动，缺一不动库 | `App/AppState.swift:7963` |
| 4 | `noteEditorSnapshot` → `editorSpansForSave()` | 以 span 树为权威源；投影不一致时按 `NoteBodyProjection.parseInline` 从正文重投影 | 同左 |
| 5 | `writeNoteEditor` → `NoteLibrary`（actor）→ `NoteDatabase.upsert` | 本体 + 标签 + 时间线一个事务，不拆第二次写 | `Plugins/Notes/Sources/NoteStorage/NoteLibrary.swift` |
| 6 | 成功 `.idle`；写入期间又敲了字则 `.pending` 并重排 | 不抹掉 `await` 期间的新按键 | `App/AppState.swift:8040` |
| 7 | 失败 `.failed(reason)`：工具条 + 状态栏各说一次 | 自动保存不弹窗，手动保存多一个可复制错误框 | `App/AppState.swift:8064` |
| 8 | 切走：`flushNoteAutosave()` 先快照再排队 | 不等写完——手势回调里等写盘等于卡交互 | `App/AppState.swift:7986` |

两条路径的形状是同一个：**动作先被纯函数判一次，再交给能力层，结果以值的形式回到 `@MainActor` 的模型里，最后从模型派生出可见状态**。SQL 那次判在 `ExecutionSafety` / `ExecutionScope`，笔记那次判在 `NoteAutosave` 的三条守卫与 `editorSpansForSave` 的投影一致性；两次回传都是值（`QueryEvent` / `NoteSaveState`），没有一处把连接、文件句柄或事务对象交给界面层持有。

## 2.8 需要补的事实

1. `Core` 的领域层与能力层没有物理目录边界，是否拆成 `Core/Domain`、`Core/Capability` 并加一条门禁，待定。
2. 语言 / 主题切换走 `.id("\(language)-\(theme)")` 整树重建，现有读数只有「5 000 行文档每键 31.74 ms」这类局部测量；整树重建一次的全量耗时没有独立测量。
3. 复盘产品线的视图在外部包 `DoyahRetroUI`，本仓只有装配面；它的并发模型与错误分级不在本仓可测范围。
4. `Platform/windows`（147 个 `.ts`/`.tsx`）与 `Platform/linux`（8 个 `.rs`）的分层与模块划分本章未覆盖；是否另立一节写跨端同构，待定。
5. 笔记自动保存在 `kill -9` 下的最坏丢失量等于「最后一次落盘之后的编辑量」，没有定量数据。

# 第三章 契约层（跨端不变量）

本章是全书的核心：每节对应一个需求域，只写「各端必须一致」的可观察行为。判断标准是 —— **换个平台端、换个实现，做同一件事的结果必须一样**；说不出「怎么观察」的条文不写。

只写契约、不写做法：做法在第九章，允许不同的地方在第四章。任何一条在本章成立的条文，都不因平台不同而放宽（放宽必须先立一条 `P-xx`）。

## 3.1 智能体（AGT）契约

本章只写「换一个平台端照着做，结果必须相同」的可观察行为：终止条件、装配顺序、审批边界、写入与遗忘规则、失败语义、持久化一致性。四条分界先立住，后文不再重复：**先验**是本次开局就知道的，**记忆**是跨会话还记得的，**技能**是会怎么做；**会话**是这一次在干什么。治理面上**审批**管能不能做，**刹停**管该不该继续，**门控**管要不要问模型——三者互不代偿，任何一处放行都不等于另一处放行。

### 3.1.1 【契约】上下文供给与外发边界

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 六类引用各成一段可指认的外发正文 | 文件 / 目录 / 选中代码 / 当前页签 / 终端尾部 / 库结构摘要各自产生独立段落，段首带来源定位（路径、行区间、页签标识、连接标识）；缺定位的段落不得进入正文 | `FR-AGT-CORE-CTX-001` |
| 2 | 预览即外发 | 用户预览到的段落集合与实际发出的正文逐字一致，同一份组装结果不在发送前二次裁剪或补写 | `FR-AGT-CORE-CTX-001` |
| 3 | 边界过滤是减法且必须留话 | 命中不外发规则的内容不进正文，同时产出「跳过了什么、按哪条规则跳过」的说明；跳过不得以空串或静默省略表达 | `FR-AGT-CORE-CTX-001` |
| 4 | 超限先摘要后发送 | 超出体积上限时先压成摘要再发，摘要标注被摘要的部分并保留可回指的原文定位；摘要本身同样受规则 3 约束 | `FR-AGT-CORE-CTX-001` |
| 5 | 装配顺序固定 | 同一次组装中六类段落的排列顺序固定（文件 → 目录 → 选中代码 → 当前页签 → 终端尾部 → 库结构摘要），同输入两次组装逐字一致 | `FR-AGT-CORE-CTX-001` |

对应需求：`FR-AGT-CORE-CTX-001`

### 3.1.2 【契约】循环、预算与任务串行

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 终止条件是穷举的四类 | 只有「模型给出终答」「步数触顶」「令牌触顶」「取消或刹停」四种收尾；每种收尾都产出一条可读原因，写明停在哪、做完哪些，不存在第五种静默结束 | `FR-AGT-CORE-LOOP-004` `FR-AGT-CORE-LOOP-009` `FR-AGT-CORE-LOOP-007` |
| 2 | 跳数口径唯一 | 一跳 = 一次模型请求及其引发的工具执行与结果回灌；脚本化两跳场景下跳数恰为 2、工具执行恰为 1 次 | `FR-AGT-CORE-LOOP-004` |
| 3 | 预算是硬上限且不结转 | 单任务 150 步、256K token；令牌判定发生在发送之前，触顶则该次请求一次都不发出；新任务从零计数；触顶不得被表述为完成，也不得静默截断 | `FR-AGT-CORE-LOOP-009` `FR-AGT-CORE-LOOP-004` |
| 4 | 工具面 = 注册表启用集合 | 注入模型的工具集合与注册表启用条目逐条相等，不多不少；未登记的工具名、不合参数 schema 的调用一律不执行，错误原文回灌给模型继续循环，不代填默认值、不静默丢弃 | `FR-AGT-CORE-LOOP-005` `FR-AGT-CORE-LOOP-006` `FR-AGT-CORE-LOOP-004` |
| 5 | 闸门次序：刹停 → 审批 → 执行 | 命中伤害性动作判据（删库 / 覆盖未备份文件 / 对外发布）即在执行前停手：不建审批单、实测无副作用、只留痕，且停手原因模型不可自行撤销；未命中才进入审批，未获批不执行 | `FR-AGT-CORE-LOOP-007` `FR-AGT-CORE-LOOP-006` |
| 6 | 每会话一条队列、会话内严格串行 | 同一会话内任务严格串行，可查看排队、可提前、可取消未开始项；会话之间不共享可变状态、不互相阻塞；同一连接或同一文件上的写不并发执行；会话结束队列作废，排队状态不带入下一次 | `FR-AGT-CORE-LOOP-008` |

生成类任务的共同出口另有两条不可协商的边界：生成结果先进入编辑器或预览区，**不自动执行**，执行由用户触发；导出只写用户在选择器中指定并已授权的目录，取消选择不算错误，未授权或授权失效时给可读提示与恢复方式，且同一路径不重复堆积。数据生成须可复现——行数、分布与种子可指定，同种子结果逐行一致；类型按完整名称判定，不可见唯一约束时不猜。这组边界合起来是「产物归用户」，任何一端都不得代劳（`FR-AGT-CORE-LOOP-001` `FR-AGT-CORE-LOOP-002` `FR-AGT-CORE-LOOP-003`）。

对应需求：`FR-AGT-CORE-LOOP-001` `FR-AGT-CORE-LOOP-002` `FR-AGT-CORE-LOOP-003` `FR-AGT-CORE-LOOP-004` `FR-AGT-CORE-LOOP-005` `FR-AGT-CORE-LOOP-006` `FR-AGT-CORE-LOOP-007` `FR-AGT-CORE-LOOP-008` `FR-AGT-CORE-LOOP-009`

### 3.1.3 【契约】会话持久化一致性

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 追加式写入、即写即持久 | 每条消息、工具调用、审批、引用各落一条，顺序即落盘顺序；异常退出最多丢失最后一条未完成写入，不得整段丢失 | `FR-AGT-CORE-SESS-001` |
| 2 | 恢复等价 | 关闭再打开后可选回历史会话，读回的消息条数与顺序逐条一致，模型可见的上下文摘要与已调用工具清单与关闭前相同 | `FR-AGT-CORE-SESS-001` |
| 3 | 损坏隔离而非整体失效 | 损坏的会话文件跳过并计数，给出可读提示，不静默丢历史，也不使会话列表整体不可用 | `FR-AGT-CORE-SESS-001` |
| 4 | 会话与记忆互不代写 | 会话只承载「这一次在干什么」，跨会话留存走记忆通道；两条通道各有自己的写入点与删除语义，删除会话不删除记忆，删除记忆不改写历史会话 | `FR-AGT-CORE-SESS-001` |

对应需求：`FR-AGT-CORE-SESS-001`

### 3.1.4 【契约】调用门控

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 门控是纯函数 | 同输入两次调用结果逐字一致；不读时钟、不读网络、不读随机源，可用脚本直接复核 | `FR-AGT-GUARD-COST-001` |
| 2 | 无变化即零请求 | 同样的触发连来两次，第二次对模型端点 0 次请求，并留下「谁被挡下、为什么」的可读理由 | `FR-AGT-GUARD-COST-001` |
| 3 | 门控不改请求 | 放行时发出的请求与不经门控时逐字节一致，不得借门控悄悄改提示词、裁剪工具或换模型 | `FR-AGT-GUARD-COST-001` |
| 4 | 门控不判可执行性 | 门控只决定要不要问模型；门控放行后写类或执行类动作仍需逐次审批，未获批仍不执行 | `FR-AGT-GUARD-COST-001` |
| 5 | 每次挡下都留痕 | 挡下记录含时间、触发来源、理由，可导出；不留痕的挡下视为违规 | `FR-AGT-GUARD-COST-001` |

对应需求：`FR-AGT-GUARD-COST-001`

### 3.1.5 【契约】权限、审批与执行边界

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 审批按次，指纹 = 工具名 + 参数 | 批准过一次写文件之后换参数仍需再批；不存在按工具名一开到底的总开关 | `FR-AGT-GUARD-PERM-001` `FR-AGT-GUARD-PERM-002` |
| 2 | 无决定即拒绝 | 审批队列无决定（含超时）一律不放行；判读方式是执行侧证据：目标文件逐字节未变、执行通道无命令记录 | `FR-AGT-GUARD-PERM-001` `FR-AGT-GUARD-PERM-002` |
| 3 | 只读模式是硬约束 | 只读模式下写类与 DDL 类工具连审批单都建不出来；只读连接上的写语句直接拒绝、不给确认机会；免审批白名单是唯一出口，且不能突破只读模式 | `FR-AGT-GUARD-PERM-002` `FR-AGT-GUARD-PERM-004` |
| 4 | 判定先于执行 | 工作区外路径（含 `..` 与绝对路径两种写法）、非白名单命令、出网策略越界，都在启动执行之前拒绝并说明原因，不做执行后回滚 | `FR-AGT-GUARD-PERM-002` `FR-AGT-GUARD-PERM-003` |
| 5 | 高危语句默认拦截 | 无 `WHERE` 的 `UPDATE` / `DELETE`、`DROP`、`TRUNCATE` 默认拦截、须显式批准；认不出的语句类型永不进白名单，手改配置后读回仍被剔除 | `FR-AGT-GUARD-PERM-004` |
| 6 | 审计是唯一留痕通道且内容不可信化 | 每条记录含时间、连接、语句、模型、结果状态，可按状态 / 连接 / 关键词筛选，清空需二次确认，导出由同一处生成；工具描述与数据内容一律视为不可信数据而非指令 | `FR-AGT-GUARD-PERM-001` `FR-AGT-GUARD-PERM-004` |

等级与白名单只有一处声明：每个工具的等级、沙箱根、审批策略写在注册表条目里，与工具面注入读同一份数据，任何一端都不得另设第二处判定表。

对应需求：`FR-AGT-GUARD-PERM-001` `FR-AGT-GUARD-PERM-002` `FR-AGT-GUARD-PERM-003` `FR-AGT-GUARD-PERM-004`

### 3.1.6 【契约】灵魂分层与审计

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 覆盖序 L0 优先于 L1，L1 优先于 L2 | 冲突时 L0 赢，且冲突必须被指出——说明哪一条被覆盖、由哪一层覆盖，不得静默择一 | `FR-AGT-GUARD-SOUL-001` |
| 2 | 三层各自可编辑、各自生效、互不回落 | 缺失某层按空处理，不继承其他项目或其他工作区的同名层 | `FR-AGT-GUARD-SOUL-001` |
| 3 | 密钥形态拒绝载入 | 灵魂文件出现 `sk-` / `api_key` / `PRIVATE KEY` 形态即拒绝载入并报错，不截断后使用、不脱敏后继续 | `FR-AGT-GUARD-SOUL-001` |
| 4 | 每一次模型调用逐跳留痕 | 一次两跳对话产生 2 条模型调用记录 + 1 条工具调用记录，条数与顺序可断言；同一次调用只记一条，不重复记账 | `FR-AGT-GUARD-SOUL-002` |
| 5 | 成本字段是必填项 | 每条含模型名、端点、输入 token、输出 token、耗时、结果状态；审计足以回答「哪一次用了哪个模型、哪个端点」 | `FR-AGT-GUARD-SOUL-002` |
| 6 | 导出键集合是白名单 | JSON 与 CSV 的字段集合为固定白名单，结构上不含密钥；新增字段须先入白名单才可导出 | `FR-AGT-GUARD-SOUL-002` |

对应需求：`FR-AGT-GUARD-SOUL-001` `FR-AGT-GUARD-SOUL-002`

### 3.1.7 【契约】先验上下文与压缩

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 先验装配顺序固定 | 项目看料（工作区树 → 当前分支与未提交改动 → 关键文件摘要）→ 灵魂 L0 / L1 / L2（见 3.1.6）→ 记忆（已按工作区与连接过滤，见 3.1.8）→ 会话压缩摘要 → 本轮显式引用（见 3.1.1）；同输入两次装配逐字一致 | `FR-AGT-KNOW-CTX-001` |
| 2 | 看料带定位、不全量读 | 每段摘要带文件路径（需要时到行区间）以保证可被引用；不把项目文档全量灌入，只取结构、改动与关键文件摘要 | `FR-AGT-KNOW-CTX-001` |
| 3 | 冲突以盘上文件为准 | 用户手贴内容与盘上文件不一致时以盘上文件为准，并把冲突点名说出，不静默采信任一侧 | `FR-AGT-KNOW-CTX-001` |
| 4 | 压缩是超限时的默认动作，不是报错 | 上下文超限触发有损压缩而非中断任务；压缩保留结论、决定与可续跑的位置，丢弃细节 | `FR-AGT-KNOW-CTX-002` |
| 5 | 压缩必须出声且可追溯 | 压缩发生时可见地说明「已压缩，丢了哪些类细节」；压缩后仍能回答「刚才决定了什么」 | `FR-AGT-KNOW-CTX-002` |

对应需求：`FR-AGT-KNOW-CTX-001` `FR-AGT-KNOW-CTX-002`

### 3.1.8 【契约】记忆与技能

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 事实源是文件，索引是纯派生缓存 | 删除索引后可从事实源完整重建，条目与频次一致；重建不改写、不补写事实源 | `FR-AGT-KNOW-MEM-001` `FR-AGT-KNOW-MEM-003` |
| 2 | 隔离按连接与工作区 | 补全候选只来自当前连接；换连接、换工作区都看不到别处记忆（两个位置各写一条后互不可见）；无历史的连接上结果为空且不报错 | `FR-AGT-KNOW-MEM-001` `FR-AGT-KNOW-MEM-002` `FR-AGT-KNOW-MEM-003` |
| 3 | 键是白名单，结构上装不下行数据 | 记忆条目没有承载结果集行数据的字段，密钥片段被挡；记忆里不出现结果集行数据 | `FR-AGT-KNOW-MEM-003` `FR-AGT-KNOW-MEM-001` |
| 4 | 删除即时生效、遗忘有理由、生命周期按类分 | 单条删除与整层清空立即生效（重建索引与下一次组装上下文都不再出现）；每次升格与遗忘留可读理由且带实际数字；不同类别用不同生命周期，不按月龄一刀切 | `FR-AGT-KNOW-MEM-002` `FR-AGT-KNOW-MEM-003` |
| 5 | 写入有上限、坏条目跳过并计数 | 写入触顶按类淘汰且留理由；坏文件或认不出的条目跳过并计数，不让整层不可用；通用层提升前过脱敏，不带库表名与数据值 | `FR-AGT-KNOW-MEM-002` `FR-AGT-KNOW-MEM-003` |
| 6 | 升格只出建议，技能不新造能力 | 例行候选须四条统计判据全部满足才成立，且只产生建议、不自动建任务，否决长期生效，参数槽位可人工订正；技能登记含名称、适用面与触发、步骤（引用工具名）、披露面，任一为空即判红，步骤引用的工具名必须能在注册表找到，技能内的调用照走等级与审批，认不出的技能或步骤如实报「认不出」 | `FR-AGT-KNOW-MEM-004` `FR-AGT-KNOW-MEM-005` |

技能与工具的关系只有一句话：技能是**步骤的组合**，不是权限的捷径。工具注册表新增一条，技能才可能引用它；把写文件步骤包进技能，未审批照样不落盘。

对应需求：`FR-AGT-KNOW-MEM-001` `FR-AGT-KNOW-MEM-002` `FR-AGT-KNOW-MEM-003` `FR-AGT-KNOW-MEM-004` `FR-AGT-KNOW-MEM-005`

### 3.1.9 【契约】模型接入与通道

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 一个后端协议起步 | 只做 OpenAI 兼容的对话补全形状，云端与本地端点同一形状；本地端点免 API Key，且请求真的不带鉴权头（在端点侧核对，不看客户端自述） | `FR-AGT-LINK-CHAN-001` `FR-AGT-LINK-CHAN-002` |
| 2 | 总开关在最前面 | 总开关关闭时端点收到 0 次请求（以端点侧计数或外发日志核验）；密钥只进系统凭据存储，不落配置文件 | `FR-AGT-LINK-CHAN-001` `FR-AGT-LINK-CHAN-002` |
| 3 | 流式必须真流式 | 请求体带流式标志与工具数组（条数 = 注册表启用条数），工具选择取值在允许集合内；逐块拼接结果与整段发送逐字一致，收到终止标记后不再读 | `FR-AGT-LINK-CHAN-002` |
| 4 | 断流不算完成 | 中途断流标为失败并给可读原因，半截回复不得当完整回复，也不得补写成完整句 | `FR-AGT-LINK-CHAN-002` |
| 5 | 每次调用记用量 | 输入 / 输出 token、实际模型、实际端点逐次记录，与审计同一数据源 | `FR-AGT-LINK-CHAN-002` |
| 6 | 通道不改权限，配置不改语义 | 从 IM 发起的任务与桌面端同一套审批，不因来源放宽，断线重连不丢未读结果；非法的端点、超时、配额配置拒绝保存并说明原因 | `FR-AGT-LINK-CHAN-003` `FR-AGT-LINK-CHAN-001` |

对应需求：`FR-AGT-LINK-CHAN-001` `FR-AGT-LINK-CHAN-002` `FR-AGT-LINK-CHAN-003`

### 3.1.10 【契约】互操作与插件

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 接入方向：握手 → 列工具 → 调用 → 回灌 | 外部工具名与参数原样透传，不改名、不改写默认值；结果按循环口径回灌 | `FR-AGT-LINK-EXT-001` `FR-AGT-LINK-EXT-002` |
| 2 | 暴露方向只给只读四类 | 对外只暴露连接、查询、元数据、导出四类能力，不暴露连接管理、口令、文件读写；未握手或未暴露的调用被拒并留痕 | `FR-AGT-LINK-EXT-001` |
| 3 | 逐 server 开关即连接闸 | 关闭的 server 不发起任何连接（判据在 server 侧：无进程、无请求）；工具级开关设为「必须审批」则该调用入队等待，未批准不执行 | `FR-AGT-LINK-EXT-002` |
| 4 | 扩展点是封闭六类 | 记忆后端、模型来源、工具库、定时任务源、通道、存储六类之外不设扩展点；内核五项不插件化 | `FR-AGT-LINK-EXT-003` |
| 5 | 策略钩子只能收紧 | 钩子一律 fail-closed：可加约束，不可放宽审批与审计、不可绕过只读模式、不可改变数据边界 | `FR-AGT-LINK-EXT-003` |
| 6 | 装卸不改授权范围、卸载无残留 | 装卸插件不改变已装能力的授权范围；未授权能力不可调用；卸载后无残留进程与配置文件 | `FR-AGT-LINK-EXT-003` |

外部工具进来与内置工具同构：一处登记（名称、参数 schema、等级、审批策略、指纹），同一个等级判定，同一个审批通道。两处各判一次，早晚分家。

对应需求：`FR-AGT-LINK-EXT-001` `FR-AGT-LINK-EXT-002` `FR-AGT-LINK-EXT-003`

### 3.1.11 【契约】可观测、可配置、可评测

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 一次任务可按跳回看 | 每跳可查输入输出摘要、模型名、token 数、耗时；不记密钥与完整私密内容 | `FR-AGT-OPS-OBS-001` |
| 2 | 记录足以回答「它刚才为什么这么做」 | 模型跳、工具跳、审批跳、门控挡下各自可查，并共用同一会话与跳序标识，可串成一条链 | `FR-AGT-OPS-OBS-001` |
| 3 | 配置即改即生效且有据可查 | 每项配置有默认值与影响说明；变更留痕（谁改的、改前改后）；非法配置拒绝保存并说明 | `FR-AGT-OPS-OBS-002` |
| 4 | 评测可增量、可比对、可定位退步 | 评测集可增删；同一集合两次运行结果可对比；通过率下降必须指出是哪几条退步，不只给总数 | `FR-AGT-OPS-OBS-003` |

对应需求：`FR-AGT-OPS-OBS-001` `FR-AGT-OPS-OBS-002` `FR-AGT-OPS-OBS-003`

### 3.1.12 【契约】主动澄清

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 只在前三种情形开口 | 目标不清、缺关键参数、两种做法代价差很大；能从上下文、记忆、既有约定推断的不问 | `FR-AGT-PLAN-CLAR-001` |
| 2 | 一次任务同一问题只问一次 | 重复问同一个问题算失败；提问给出至多 3 个可选答案，不让用户从零描述 | `FR-AGT-PLAN-CLAR-001` |
| 3 | 缺参数不产出猜的结果 | 宁可停下等待，也不先做后改；选择「不确定但先做」时必须在结论首段写明假设，并点名哪条判据依赖该假设 | `FR-AGT-PLAN-CLAR-001` |
| 4 | 提问期间不动手 | 等答复期间不发出写类或执行类调用，澄清不产生副作用 | `FR-AGT-PLAN-CLAR-001` |

对应需求：`FR-AGT-PLAN-CLAR-001`

### 3.1.13 【契约】计划、判据与执行

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 判据在开工前立 | 任务开始时写明判据（测试通过 / 命令返回 0 / 文件含某段），结束时逐条对照给结论；判据不成立不得声称完成 | `FR-AGT-PLAN-PLAN-005` |
| 2 | 计划解析不丢行、执行入口只收已批准 | 认不出的行原样报出；写与 DDL 一律审批，只读连接上的写连批准也不能执行；高开销类一次计划最多一条且需显式放行 | `FR-AGT-PLAN-PLAN-001` |
| 3 | 规格先试运行再保存 | 保存前必须试运行并预览；空名、空规格、空表名、一次性缺时间、周期缺间隔或非正、更新策略缺冲突键、条件里出现形似语句片段，一律拒绝并给可读原因，不静默保存 | `FR-AGT-PLAN-PLAN-002` |
| 4 | 版本只追加 | 内容没变不记新版本；回滚 = 把旧内容再存一次，「曾回滚过」留在历史里；任意两版可 diff；重跑须显式声明幂等语义（覆盖 / 追加 / 断点），不默认猜 | `FR-AGT-PLAN-PLAN-003` |
| 5 | 改计划必须出声且不扩权 | 每次修订有一条可见的「改了什么 / 为什么」，修订记录留在会话里可回看；改后的计划仍受原授权范围约束，换路不换权限 | `FR-AGT-PLAN-PLAN-004` |
| 6 | 失败分类处置，不许空转 | 工具失败先重试可重试的（有上限），不可重试的换手段并说明为什么换；连续失败达阈值即停下，报出原因与已尝试的路；模型调用失败的分级与退避走 3.1.21 | `FR-AGT-PLAN-PLAN-006` |

完成判据与自验是两条不互相代偿的线：判据管「怎么算做完」（事前），自验管「产出前先跑一遍」（事后，见 3.1.14）。只做其一不算合规。

对应需求：`FR-AGT-PLAN-PLAN-001` `FR-AGT-PLAN-PLAN-002` `FR-AGT-PLAN-PLAN-003` `FR-AGT-PLAN-PLAN-004` `FR-AGT-PLAN-PLAN-005` `FR-AGT-PLAN-PLAN-006`

### 3.1.14 【契约】自验与结论纪律

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 能跑的跑、能对的对，再报完成 | 改了代码就跑测试或构建，结果写进结论；声称「已修复」必须附验证方式与输出；自验失败不得标为完成 | `FR-AGT-QUAL-VERIFY-001` |
| 2 | 「完成」必须引用当次依据 | 自报完成时给出可机械复核的判据并引用本次运行的证据；说不清就写「未验证」，不写「已完成」 | `FR-AGT-QUAL-VERIFY-001` |
| 3 | 跨小时不丢目标 | 中断、重启、换端后恢复，第一步先复述目标与已完成部分；目标被用户改过时以最新为准 | `FR-AGT-QUAL-VERIFY-002` |
| 4 | 结论三态可分 | 每条结论标为已验证 / 推断 / 未验证；把握低时给替代方案；不把猜测说成事实 | `FR-AGT-QUAL-VERIFY-003` |
| 5 | 结论可溯源，无出处不入交付物 | 关键结论挂着文件路径行号、命令输出、日志或文档链接，且可点击或可复制执行；找不到出处的结论不得写入交付物 | `FR-AGT-QUAL-VERIFY-004` |

对应需求：`FR-AGT-QUAL-VERIFY-001` `FR-AGT-QUAL-VERIFY-002` `FR-AGT-QUAL-VERIFY-003` `FR-AGT-QUAL-VERIFY-004`

### 3.1.15 【契约】局部精确编辑

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 按行或按块改，不整文件重写 | 改一个函数不触碰文件其他行；未触及的行逐字节不变 | `FR-AGT-TOOL-EDIT-001` |
| 2 | 每次修改先给差异 | 落盘前产出可查看的行级差异（带上下文），差异即审批依据，也是事后回看依据 | `FR-AGT-TOOL-EDIT-001` |
| 3 | 原文风格不因编辑改变 | 缩进、换行、引号风格保持不变；不得因为工具链默认行为顺手格式化整文件 | `FR-AGT-TOOL-EDIT-001` |
| 4 | 可一步撤销 | 应用后可一步撤销，撤销后文件逐字节回到应用前 | `FR-AGT-TOOL-EDIT-001` |

对应需求：`FR-AGT-TOOL-EDIT-001`

### 3.1.16 【契约】检索、文档与图像

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 检索与抓取是两个动作 | 各自可单独调用；检索结果每条结论挂可点开的来源链接，并区分「搜到标题」与「读到正文」 | `FR-AGT-TOOL-INGEST-001` |
| 2 | 抓不到就说抓不到 | 抓取失败如实报「只看到标题」，不得据标题编正文；来源可信度须判断并写明 | `FR-AGT-TOOL-INGEST-001` |
| 3 | 解析保留位置 | 文档解析结果带页码或表格位置以便回指；扫描件无文字层如实报「需 OCR」而非给空结果；解析失败不吞错 | `FR-AGT-TOOL-INGEST-002` |
| 4 | 看不见图是明确失败 | 模型不支持视觉时报错而非静默降级为无图推理；结论要说明来自图中哪一处 | `FR-AGT-TOOL-INGEST-003` |
| 5 | 图片外发先过边界 | 图片外发前按数据边界处理，默认需人工确认；未被确认的图片不进请求体 | `FR-AGT-TOOL-INGEST-003` |

对应需求：`FR-AGT-TOOL-INGEST-001` `FR-AGT-TOOL-INGEST-002` `FR-AGT-TOOL-INGEST-003`

### 3.1.17 【契约】语音输入输出

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 转写结果可与音频对照回看 | 保留原文与音频的对应关系，转写错误可回看核对，不做单向下游覆盖 | `FR-AGT-TOOL-MEDIA-001` |
| 2 | 转写不等于用户已确认 | 转写文本进入输入框待确认，不得直接当作已确认指令触发执行 | `FR-AGT-TOOL-MEDIA-001` |
| 3 | 识别不可用要明说 | 报「没有可用的语音服务」，不静默吞掉输入、不落空消息 | `FR-AGT-TOOL-MEDIA-001` |
| 4 | 播放可中断、长文分段不截断 | 随时可中断；长文本分段连续读完，不因分段丢句；语速可调 | `FR-AGT-TOOL-MEDIA-002` |
| 5 | 语音不可用回落为文字 | 语音服务不可用时回落为文字输出，不算任务失败 | `FR-AGT-TOOL-MEDIA-002` |

对应需求：`FR-AGT-TOOL-MEDIA-001` `FR-AGT-TOOL-MEDIA-002`

### 3.1.18 【契约】模型分档与预填

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 档位自描述，未标注即没有 | 每档标明能力（看图 / 调工具 / 上下文长度 / 语种）与价格；未标注的能力一律当作不具备 | `FR-AGT-TOOL-MODEL-001` |
| 2 | 降档必须出声 | 降档导致能力缺失时当场说明缺什么，不静默降级、不假装具备 | `FR-AGT-TOOL-MODEL-001` |
| 3 | 用量记的是实际值 | 自动降级并提示后，用量与审计记的是实际模型与实际端点，不是请求时的期望值 | `FR-AGT-TOOL-MODEL-001` |
| 4 | 预填是起点不是锁 | 预设只提供端点与模型名的起点值，每个字段当场可改、改后保存并可用；不存在「只能选、不能填」的字段 | `FR-AGT-TOOL-MODEL-002` |

对应需求：`FR-AGT-TOOL-MODEL-001` `FR-AGT-TOOL-MODEL-002`

### 3.1.19 【契约】定时调度

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 判定是纯时间计算，五档可断言 | 未排期 / 已停用 / 等待 / 到期 / 错过五档逐档可判；对话任务与数据任务共用同一套判定，不另造一套 | `FR-AGT-TOOL-SCHED-001` `FR-AGT-TOOL-SCHED-002` |
| 2 | 错过窗口不补跑 | 不自动补跑，给出「晚了约 N 分钟，是否现在执行」的可读提示，等用户决定 | `FR-AGT-TOOL-SCHED-001` `FR-AGT-TOOL-SCHED-002` |
| 3 | 定时不构成授权 | 到点触发的那一次里，写类与执行类动作仍逐次审批；只读模式下连审批单都建不出来 | `FR-AGT-TOOL-SCHED-002` |
| 4 | 可暂停、有历史 | 可暂停与停用；执行历史与失败记录可查，成功与失败同列，不只留最后一次 | `FR-AGT-TOOL-SCHED-001` `FR-AGT-TOOL-SCHED-002` |

对应需求：`FR-AGT-TOOL-SCHED-001` `FR-AGT-TOOL-SCHED-002`

### 3.1.20 【契约】界面操作与子任务委派

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 每一步可见可中断 | 每个动作留截图或坐标记录；随时可中断并回退到人工接管，不留下半截操作无人认领 | `FR-AGT-TOOL-SYS-001` |
| 2 | 破坏性点击一律审批 | 涉及删除、支付、发送的点击先审批；有接口时优先用接口，界面操作不是默认手段 | `FR-AGT-TOOL-SYS-001` |
| 3 | 子任务独立留痕、结果标来源 | 子任务有独立上下文与独立记录；汇总时标明哪条结论来自哪个子任务 | `FR-AGT-TOOL-SYS-002` |
| 4 | 子任务失败不拖垮主任务，并行度受控 | 单个子任务失败不影响主任务其余部分；并行有上限，且并行不改变审批与留痕口径 | `FR-AGT-TOOL-SYS-002` |

对应需求：`FR-AGT-TOOL-SYS-001` `FR-AGT-TOOL-SYS-002`

### 3.1.21 【契约】对话面：会话、过程与人机时序

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 会话按工作区归属，键是白名单 | 同一工作区重启后读回同一条会话（消息条数与顺序逐条一致）；换工作区看不到别的会话（两个工作区各写一条后互不可见）；可导出并按时间顺序回放，模型跳 / 工具跳 / 审批跳都在；记录结构上没有承载结果集行数据的字段；坏会话文件跳过并计数 | `FR-AGT-UX-CONV-002` |
| 2 | 对话在 Home 区页签，不在侧栏 | 对话页签与文件 / 浏览器页签同列、占据工作区主要区域且可关；页签内构成 = 消息流 + 流式渲染 + 可展开工具卡片 + 内联审批 + 差异应用与撤销；展开可见所用模型与端点，未配置或连不上时如实说「未配置 / 连不上」 | `FR-AGT-UX-CONV-003` |
| 3 | 过程可见，结论必须有当次依据 | 执行中实时追加步骤，每步可展开看参数与返回摘要，可按时间回看与导出（不含密钥）；诊断类结论分三态：取到有行 / 取到零行 / 根本没取到并写明原因，无依据或引用不存在的依据整条拒绝；建议语句走与手工执行同一条审批闸门，解读执行计划不得使用会真正执行语句的形式 | `FR-AGT-UX-CONV-006` `FR-AGT-UX-CONV-001` |
| 4 | 干预两种时延不同，通知与求助各有边界 | 改方向与追加约束在当前步完成后生效；停手立即生效——不再发下一次请求，正在跑的命令被中断或被明确标注为不可中断的等待点；干预内容进会话记录；完成 / 出错 / 需人决定三类事件各推一条带结论与下一步的通知，可配静默时段；求助须写明要什么、为什么、不给会怎样，有追问上限，不把「不会做」包装成「需要你确认」 | `FR-AGT-UX-CONV-007` `FR-AGT-UX-CONV-008` `FR-AGT-UX-CONV-009` |
| 5 | 模型侧回边：分级、退避、回灌、续跑 | 可重试错误重试、不可重试立即上报；重试次数与退避上限可配置，触顶如实报原因与已试次数；执行结果作为下一跳输入回灌；中途失败可从检查点续跑 | `FR-AGT-UX-CONV-004` |
| 6 | 执行侧回边：并发可判、完成可核、卡住可见、链路可串 | 同一文件并发写要么拒绝要么串行化并如实说明；自报完成时必须给出可机械复核的判据并引用当次依据，说不清则写「未验证」；空转、反复重试、超预算有可见告警；「会话 → 第 N 跳 → 工具调用 → 审批」可串成一条链，跨进程重启仍可串 | `FR-AGT-UX-CONV-005` |

对应需求：`FR-AGT-UX-CONV-001` `FR-AGT-UX-CONV-002` `FR-AGT-UX-CONV-003` `FR-AGT-UX-CONV-004` `FR-AGT-UX-CONV-005` `FR-AGT-UX-CONV-006` `FR-AGT-UX-CONV-007` `FR-AGT-UX-CONV-008` `FR-AGT-UX-CONV-009`

### 3.1.22 【契约】会话生命周期

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 四个动作齐备 | 新建、归档、删除、导出都存在；归档后可恢复，恢复后消息与跳序与归档前一致 | `FR-AGT-UX-SESS-001` |
| 2 | 删除即真删 | 删除后磁盘上不再有该会话数据，连同其派生的索引与缓存条目一并清除，不以软删作为默认 | `FR-AGT-UX-SESS-001` |
| 3 | 导出可带走、可再导入 | 导出件含回放所需的跳序与审批记录，且可被重新导入；导出键集合仍是白名单，不含结果集行数据与密钥 | `FR-AGT-UX-SESS-001` |
| 4 | 生命周期动作留一条账 | 归档、删除、导出各留一条可查记录（哪个工作区、哪个会话、何时）；删除后会话正文不保留，但账仍可查 | `FR-AGT-UX-SESS-001` |

对应需求：`FR-AGT-UX-SESS-001`

### 3.1.23 【契约】多端一致

| # | 不变量 | 各端可观察的一致行为 | 对应需求 |
|---|---|---|---|
| 1 | 壳不同，内容同 | 任一端发出的消息在另一端可见；消息顺序以会话内序号为唯一序，不依赖各端本机时间 | `FR-AGT-UX-SYNC-001` |
| 2 | 审批只问一次 | 一条审批在任一端被决定后，另一端不再重复询问，并显示同一决定与决定者 | `FR-AGT-UX-SYNC-001` |
| 3 | 重连补齐、重复幂等 | 断线重连后以序号游标补齐缺失消息；重复投递按条目标识去重，不产生重复消息、不重复记账 | `FR-AGT-UX-SYNC-001` |
| 4 | 进行中的状态也同步 | 排队中 / 执行中 / 已取消 / 待审批在各端一致；只同步历史消息不算完成 | `FR-AGT-UX-SYNC-001` |

对应需求：`FR-AGT-UX-SYNC-001`
## 3.2 数据库工作台（STD）契约

本章写**跨端必须一致的可观察行为**：同一份输入在任意端得到同一结果。每条不变量的判定口径统一为「拿两端产出的可比对象（字节、集合、序列、退出码、文件哈希）对差」，**不以某一端的自述或界面观感为证**。「端」指桌面各平台与无界面命令行出口；位置、实现选择、控件形态不在本章约束内。

### 3.2.1 【契约】工程生成与构建产线

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 声明式工程描述是唯一源，构建工程是**产物**：可重复生成，且生成物不得含手改 | 连跑两次生成，产物逐字节相同（哈希可比）；对产物做任意手改后重生成，改动消失；生成物里出现手改痕迹即判红 |
| 2 | 不打开图形 IDE 也能完成「解析 → 编译 → 产出可运行应用包」全程 | 干净检出后仅用命令行构建成功，退出码 0；失败时报出缺失的包或目标名；全程无 IDE 依赖 |
| 3 | 依赖来源可切换，切换失败整体回滚 | 一条命令切到镜像后依赖可解析；注入一条坏依赖源时，命令报出**哪一条依赖、什么原因**，且配置回到切换前状态（字节可比） |
| 4 | 单元验证一条命令跑完，输出计数而不是「完成」 | 输出含通过/失败计数；有失败时非零退出并点名失败项；全程不联网、不需图形会话 |
| 5 | 本机链路验证与真实库连接验证各有一条独立出口，判据不同 | 无外部库时前者可全绿；有真实库时后者能连、能按 `-c` / 标准输入 / `--tree` 三种入口取数。两者结论互不替代 |
| 6 | 文档三边同集合：正文定义、索引、计划台账 | 三处编号集合做差集，非空即判红；索引的章节列与正文节名逐条可对应 |

对应需求：`FR-STD-ALL-BLD-001` `FR-STD-ALL-BLD-002` `FR-STD-ALL-BLD-003` `FR-STD-ALL-BLD-004` `FR-STD-ALL-BLD-005` `FR-STD-ALL-BLD-006` `FR-STD-ALL-BLD-007` `FR-STD-ALL-BLD-008` `FR-STD-ALL-BLD-009`

### 3.2.2 【契约】命令行出口

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 命令行与图形端走**同一条**执行通道，不设第二套取数路径 | 同一条 SQL 分别经图形端与命令行执行，导出同一份结果：列名序列、类型名、行值与行序逐字节相同 |
| 2 | 三种输入入口同一语义：`-c`、`--command`、标准输入 | 同一 SQL 经三入口得到的输出逐字节相同；不给 `-c` 时读到输入结束（EOF）才执行；`-c` 与标准输入同时给时以显式参数为准 |
| 3 | 多语句按分号逐条执行，顺序与图形端一致 | 同一段多语句在两端产生的语句段数相同、逐段状态序列相同 |
| 4 | 对象树出口自带规模上限与空态 | `--tree` 递归打印层级可辨；单层最多 50 个对象，超出标「还有 N 个」；`--columns` 在每个对象下附列名与类型；两开关可同时用；无对象输出「(空)」而不是空行 |
| 5 | 退出码分级，错误走标准错误 | 成功 0、连接失败 1、查询失败 2、对象树失败 3；脚本按退出码分支可得同一结论，不依赖解析标准输出文案 |
| 6 | 口令不进命令行参数、不进命令历史与日志 | 环境变量入口可用（`PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABASE/PGSSLMODE`），与图形端连接同一实例；命令回显、日志、错误输出中口令出现次数为 0 |

对应需求：`FR-STD-ALL-CLI-001` `FR-STD-ALL-CLI-002` `FR-STD-ALL-CLI-003` `FR-STD-ALL-CLI-004` `FR-STD-ALL-CLI-005` `FR-STD-ALL-IFACE-012` `FR-STD-ALL-IFACE-013`

### 3.2.3 【契约】本机数据与保留

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 逻辑分区一致：连接配置、保存的查询、查询归档、任务定义、审计回执、查询历史各占一份，互不混写 | 六类数据各有一处可枚举的落点；删除其中一类不影响其余五类；位置本身属平台实现，但分区关系必须同构 |
| 2 | 写盘原子，坏文件不静默清空 | 写入过程中断后不产生半截文件；读损坏文件时给可读错误并保留原文件（字节不变），不建空目标、不自动修复 |
| 3 | 删除连接 = 配置 + 凭据 + 连接缓存三样一起清 | 删除后三样均不可再取；取消删除时三样字节均未变；确认框明示会连带删凭据 |
| 4 | 查询记录分两路，互不混写：**历史落本机库**（改判后的口径覆盖「只驻留内存、退出即清空」的旧口径），**归档按天一个可直接执行的文件** | 历史只在本机可读、不上传；按连接记录，成功与失败都留一行摘要，点击可回填；默认保留上限 500 条或 90 天（先到者为准），触限按时间淘汰最旧并明示上限，提供清空与单条删除；归档文件按天分文件、本身可直接执行、可入版本库，同一条 SQL 重复执行只累加次数不重复抄写，条目含连接、库、首次与最近执行时刻、耗时、影响行数；两路都不含口令 |
| 5 | 配置格式带版本位，升级只做能确定的正规化 | 反复加载不改文件内容（幂等）；缺版本位的旧文件读一次即升级；零或越界端口回落该类型默认值、超时零值回落默认，不猜主机/用户名/库名；来自更高版本的文件逐字节原样保留并如实告知 |
| 6 | 保存的查询与导出物不含凭据 | 保存项落盘为结构化文本（标识、名称、所属连接、库、语句、保存时刻），原子写；全量搜索文件内容，口令与敏感字面量命中 0 |

对应需求：`FR-STD-ALL-DATA-001` `FR-STD-ALL-DATA-002` `FR-STD-ALL-DATA-003` `FR-STD-ALL-DATA-004` `FR-STD-DB-EXEC-001` `FR-STD-DB-SESS-001` `FR-STD-DB-CONN-004` `FR-STD-DB-CONN-009`

### 3.2.4 【契约】内部接口与分层边界

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 执行通道是唯一取数入口：连 / 断 / 执行（可取消、可超时），返回**结构化结果**而非拼好的文本 | 界面与命令行都只经该通道；结构化结果按固定字段序列化后两端逐字段相等；任何一端出现「自己拼字符串」的第二条路径即判红 |
| 2 | 方言差异只在方言层表达，上层不出现按数据库类型的分支散落 | 新增一种数据库类型时，改动文件集合可枚举且只落在方言实现与工厂注册处；上层文件零改动 |
| 3 | 语句切分保留语句序号与原文，拆错即缺陷 | 各段按序拼接后与原文逐字一致（含空白、注释、大小写）；把一条拆成两条或反之，判红 |
| 4 | 诊断标注带行 / 列 / 区间，可直接定位到字符；着色只依赖词法输出 | 同一段 SQL 在两端得到的诊断区间集合与词法标签序列相同；视图层自行解析 SQL（出现第二套解析）即判红 |
| 5 | 凭据只在一个点进出 | 抓取全部日志、错误信息、导出物，口令出现次数为 0；缺口令时报「缺口令」并指明该填的位置，而不是报底层连接错误 |
| 6 | 元数据懒加载且失败可隔离；工厂对未知类型给可读拒绝 | 一个节点失败不拖垮整棵树；未知类型请求返回「功能尚未实现」+ 类型名 + 已支持清单，既不是空实现也不是崩溃 |

对应需求：`FR-STD-ALL-IFACE-001` `FR-STD-ALL-IFACE-002` `FR-STD-ALL-IFACE-003` `FR-STD-ALL-IFACE-004` `FR-STD-ALL-IFACE-005` `FR-STD-ALL-IFACE-006` `FR-STD-ALL-IFACE-007` `FR-STD-ALL-IFACE-008`

### 3.2.5 【契约】授权与能力位

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 离线可校验：许可证声明三块能力位与到期时间，签名可验 | 无网络时也能解析出三块能力位与到期时间；同一份许可证在两端解析结果逐字段相同 |
| 2 | 缺失 / 损坏 / 签名不符一律给可读原因，不当成全功能 | 三种坏输入各自得到可读原因；任何一种被当成「全功能」放行即判红 |
| 3 | 能力位只有一处判定，未授权入口**不出现**（不是灰掉） | 换档后活动栏与菜单跟随，无需重启；界面元素清单可枚举；出现「显示但点不动」的入口即判红 |
| 4 | 到期如实降级，绝不锁死或隐藏用户数据 | 到期后已建连接、保存的查询、历史仍可打开与导出；提示给下一步而不是制造数据已丢的措辞 |
| 5 | 一套许可证管三块；移动端是「不在管辖」而非「未授权」 | 一份许可证同时决定三块能力位；移动端不参与能力位判定，不产生「未授权」态 |
| 6 | 设备配额默认 5 台，随机标识、不用硬件指纹 | 配额可配；设备标识不含硬件特征；释放后原设备不再占位；超额点名「先移除哪一台」 |

对应需求：`FR-STD-ALL-LIC-001` `FR-STD-ALL-LIC-002` `FR-STD-ALL-LIC-003` `FR-STD-ALL-LIC-004` `FR-STD-ALL-LIC-005`

### 3.2.6 【契约】插件装配

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 插件以**同进程模块**装配：无跨进程通信、交付包内无独立可卸载插件包 | 全仓跨进程通信调用命中 0；插件源码与宿主目标一起编译，无独立插件目标；交付包内不存在可单独卸载的插件包 |
| 2 | 上下文**单向**从宿主流向插件，只传文本与标识，不传结果行数据 | 传递结构里不含行数据字段；含行数据必须显式确认才写入，写入后「含行数据」标记永久留在数据上，无撤回入口 |
| 3 | 插件数据家与工程数据家**平级**，不嵌套；迁移原子且可核 | 两个目录不互为父子；迁移为原子写并读回逐字段核对；旧文件保留为 `.migrated`；坏文件原地保留并报错，不建空目标；重跑迁移报「无需迁移」 |
| 4 | 插件可复用宿主词法 / 补全，**禁止**依赖数据库与工作区类型 | 插件源码对数据库侧与工作区类型的引用为 0；禁用名单与实际文件清单对账一致（无漏检）；插件模块可单独构建通过 |
| 5 | 各端笔记主存统一到本地库：元数据 / 正文 / 标签 / 时间线 / 附件索引入库，原件与附件二进制留文件系统 | 各端表结构与 schema 版本一致；附件二进制不在库内、库里只存路径；写入走事务，崩溃后库不自坏 |
| 6 | 装配在无授权时只剩「入口不可见」，不产生半装配状态 | 无授权时插件入口不出现，宿主与其余面照常可用；授权变化即时生效；不存在「入口出现但功能缺失」的组合 |

对应需求：`FR-STD-ALL-PLUG-001` `FR-STD-ALL-PLUG-002` `FR-STD-ALL-PLUG-003` `FR-STD-ALL-PLUG-004` `FR-STD-ALL-PLUG-005` `FR-STD-ALL-PLUG-006` `FR-STD-ALL-PLUG-007` `FR-STD-ALL-PLUG-008`

### 3.2.7 【契约】连接配置与凭据

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 类型切换联动默认值，且**只**改写仍取默认值的字段 | 切换类型后端口 / SSL 默认值 / 默认 schema 当场回填（PG 5432、GBase 8a 5258、MySQL 3306）；用户手改过的字段不被覆盖；配置里只有一份默认值出处 |
| 2 | 校验先解析再判定，校验不过则「测试连接 / 保存」都禁用 | 名称、主机、用户名非空，端口 1–65535；把非法端口塞进默认值字段不得被洗白为合法；禁用态可枚举 |
| 3 | 凭据只经**平台系统凭据存储**进出（各端用自己的凭据 API，条目以连接标识为账号）；配置文件零密码、权限 0600 | 全量搜索配置文件，无任何口令字段或字面量；同一连接在两端各自取到自己的口令，互不覆盖；编辑时口令留空 = 保持原口令（保存后旧口令仍可用）；无口令认证的库（trust / peer / 证书）也能连上 |
| 4 | 显示名 `名称 (登录用户名)` 只有一份生成逻辑 | 侧边栏、上下文栏选择器、删除确认框三处取同一结果；名称空 → 占位文案 + 用户名；用户名空 → 只显示名称，不出现空括号；同一连接在三处显示逐字相同 |
| 5 | 连接生命周期闭环：选中项跨重启恢复，删除三清并二次确认 | 选择变化即持久化，重启回到该连接；该连接已删除则回退列表首条（不报错、不留空选中）；无任何连接时不崩；删除确认明示连带删凭据，取消时零字节改动 |
| 6 | 连接建立后的后置动作与失败面如实 | 启动 SQL 在连接建立后执行一次，失败不静默并说明连接是否仍可用；只读连接上写语句被拒绝并给理由；心跳按间隔发送、可关、失败只记录不打断；隧道断开时报「隧道问题」而非「库问题」；测试连接返回服务端版本 / 当前库 / 当前用户 |

对应需求：`FR-STD-DB-CONN-001` `FR-STD-DB-CONN-002` `FR-STD-DB-CONN-003` `FR-STD-DB-CONN-005` `FR-STD-DB-CONN-006` `FR-STD-DB-CONN-007` `FR-STD-DB-CONN-008` `FR-STD-DB-CONN-010` `FR-STD-DB-CONN-011` `FR-STD-DB-CONN-012` `FR-STD-DB-CONN-013` `FR-STD-DB-CONN-014` `FR-STD-DB-CONN-015` `FR-STD-DB-CONN-016` `FR-STD-DB-CONN-017` `FR-STD-DB-CONN-018` `FR-STD-DB-CONN-019` `FR-STD-DB-CONN-020` `FR-STD-DB-CONN-021` `FR-STD-ALL-IFACE-011`

### 3.2.8 【契约】驱动适配与方言

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 方言覆盖一组固定能力面：标识符引用、分页子句、库 / schema / 表 / 列清单、版本号查询与解析、关键字与函数表 | 同一段 SQL 生成的语句文本与页大小换算在各端逐字相同；换一种库只增一份方言，上层不改 |
| 2 | 语句切分按方言：PostgreSQL 跳过 dollar-quote，MySQL 协议系认分隔符指令与 `END$` / `END $` | 同一段含 `$$…$$`、`$tag$…$tag$` 的脚本在 PostgreSQL 方言下段数固定；同一段含 `DELIMITER` 的脚本在 MySQL 协议系方言下按其分隔符切出预期段数；方言未指定时按 PostgreSQL 处理 |
| 3 | 切分只识别边界，不改写原文 | 各段按序拼接与原文逐字一致；不补分号、不改引号、不规范化空白；字符串 / 行注释 / 块注释（含嵌套）/ 带引号标识符 / dollar-quote 内的分号不触发拆分；尾随注释归上一段 |
| 4 | 执行以事件流上报，顺序与条数固定；一条语句的影响行数只报一次 | 一次执行按序产出「开始 → 结果集或影响行数 → 通知 → 结束」，两端条数与顺序可断言相等，影响行数既不随结果集又在别处重复上报一次；中途失败产出带错误的事件且**不伪造**结束事件；多语句时每条语句各自成段，段界可辨 |
| 5 | 工厂按类型给出实现；未实现类型给可读拒绝 | 未知类型返回含类型名与已支持清单的可读错误，不是空实现、不是崩溃；已支持类型不出现该错误 |
| 6 | 线协议与依赖固定：PostgreSQL 走 TCP + SSL（默认端口 5432），GBase 8a 与 MySQL 同属 MySQL 协议族（默认端口 5258 / 3306）；依赖版本被锁文件钉死、锁文件入库 | 同一组连接参数在两端的协议族、默认端口与传输加密方式一致；传递依赖可枚举且与锁文件逐条一致，锁文件与依赖清单不一致时构建判红；换实现只改驱动层，界面与核心不受影响 |

对应需求：`FR-STD-DB-DRV-001` `FR-STD-DB-DRV-002` `FR-STD-DB-DRV-003` `FR-STD-DB-DRV-004` `FR-STD-DB-DRV-005` `FR-STD-DB-DRV-006` `FR-STD-DB-DRV-007` `FR-STD-DB-DRV-008` `FR-STD-DB-DRV-009` `FR-STD-DB-DRV-010` `FR-STD-ALL-IFACE-009` `FR-STD-ALL-IFACE-010`

### 3.2.9 【契约】执行控制

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 执行目标 = 上下文栏所选库；多语句按文本顺序逐条执行，不并发打乱 | 执行后查当前库，与选择器所选一致；每条语句执行前报「正在执行第 N 条」且 N 与实际一致；逐条给出成功 / 失败、耗时、行数；失败后按设置继续或中止，并明示停在第几条 |
| 2 | 执行前把文本定形：范围自动判定 + 占位符提取与转义 | 有选区只跑选中段（含多选与块选），无选区跑整篇，无「运行范围」开关；占位符识别跳过字符串 / 行注释 / 块注释 / dollar-quote / 带引号标识符，`$1` 不被当 dollar-quote，`::` 不算参数，重复参数合并；缺值时拒绝执行并点名缺哪个 |
| 3 | 同一连接的并发请求复用同一个物理连接 | 同连接并发请求的握手次数为 1；共用连接上的语句按序不交错；连接断开后下次请求重建并告知；不同连接之间互不复用 |
| 4 | 事务边界：懒开启、整体可回滚、状态不撒谎 | 第一条语句前才开事务，没跑语句不开；手工事务下多语句在同一事务内，出错可整体回滚；语句失败或取消后只能回滚，界面不出现底层「事务已中止」原文；有进行中的事务时拒绝切回自动提交；提交 / 回滚本身失败时状态如实退回「事务已结束」 |
| 5 | 取消必须打到服务端，且不冤枉连接的其它工作 | 点停止后服务端语句确实终止（服务端会话状态可核）；取消后同一连接仍可用；被取消的执行记为**取消**而不是成功；服务端不认账时如实说仍在运行，不谎称已中断 |
| 6 | 发送前拦截：空输入、高危语句、只读连接 | 空 SQL 与未选连接给明确文案而非静默失败；无 `WHERE` 的 `UPDATE` / `DELETE` 与 `DROP` / `TRUNCATE` 在确认前**不发送**，拦截时说明命中哪条规则，判定为纯客户端静态规则且可在设置关闭；只读连接上的写语句直接拒绝，不给确认机会 |

对应需求：`FR-STD-DB-EXEC-002` `FR-STD-DB-EXEC-003` `FR-STD-DB-EXEC-004` `FR-STD-DB-EXEC-005` `FR-STD-DB-EXEC-006` `FR-STD-DB-EXEC-007` `FR-STD-DB-EXEC-008` `FR-STD-DB-EXEC-013` `FR-STD-DB-EXEC-015` `FR-STD-DB-EXEC-017` `FR-STD-DB-EXEC-018`

### 3.2.10 【契约】数据浏览与行编辑

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 双击表 / 视图只**生成**浏览语句并入新页签，不自动执行 | 生成语句按方言（PG `LIMIT n OFFSET m` / MySQL 协议系 `LIMIT m, n`）且带 schema 限定；默认 200 行，非法值夹取；同一表在两端生成的语句逐字相同；无权限对象双击给可读提示，不静默失败 |
| 2 | 条件与排序在**服务端**生效，不在客户端过滤 | 填入的 `WHERE` / `ORDER BY` 原样下发；计数语句不带 `ORDER BY`；分页子句排在 `WHERE` / `ORDER BY` 之后；界面明示条件片段是直接执行 |
| 3 | 先预览后提交：改单元格 / 加行 / 删行都先生成 DML 再确认 | 提交前弹窗逐条列出将执行的 DML；确认才发送，取消则库零改动；提交失败如实报错并保留未提交的编辑；同一批编辑在两端生成的 DML 序列逐条相同 |
| 4 | 值转义与空值语义固定 | 按列类型转义；空串与 NULL 在预览与发送两侧都可区分；文本加引号并双写单引号，数值不转义 |
| 5 | 无唯一键的表明确拒绝编辑，不做隐式匹配 | 无主键 / 唯一键的表上编辑入口给明确拒绝理由；不生成按全列匹配的隐式 DML |
| 6 | 外键导航双向可用且仅在元数据存在时出现 | 正向与反向跳转都带入该外键值作为条件；无外键元数据或无目标时入口不出现（不是灰掉） |

对应需求：`FR-STD-DB-DATA-001` `FR-STD-DB-DATA-002` `FR-STD-DB-DATA-003` `FR-STD-DB-DATA-004` `FR-STD-DB-DATA-005` `FR-STD-DB-DATA-006` `FR-STD-DB-META-012`

### 3.2.11 【契约】元数据与对象树

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 层级形状由方言声明：PostgreSQL 五层（服务器 → 库 → schema → 表 / 视图 → 列），MySQL 协议系四层（无 schema 节点） | 同一库在两端展开出的节点路径集合逐节点相同；每节点类型（库 / 模式 / 表 / 视图 / 列 / 函数）正确，表与视图不混；按连接类型自动选形状 |
| 2 | 懒加载：一层只查一层，二次展开不重复查 | 首屏只发第一层查询；未展开节点产生的查询数为 0；同一节点第二次展开不新增查询；查询次数在服务端可观测，不以实现自述为证 |
| 3 | 失败隔离：一个节点失败只影响该节点 | 失败节点标警示并给人话（不出现驱动原文）+ 可重试；其余节点照常；整树不因单点失败变空；不伪装成空树 |
| 4 | 系统对象默认过滤，且不误杀用户对象 | `information_schema`、`pg_catalog`、`pg_toast*`、`pg_temp*` 及带后缀同类默认不出现；用户自建的相似前缀不被过滤；有「显示系统对象」开关，打开后可见 |
| 5 | 元数据取数有行数上限，截断必须可见 | 超过上限（默认 10,000 行）时结果带截断标记并明示「已截断，共 N 行」，同时给继续取出口；不静默丢行、不崩 |
| 6 | 定义体取服务端原文，不靠列信息拼 | 表 / 视图 / 函数可查看等价建对象语句，视图与函数取服务端定义体；取不到如实报错，不给半截语句；结果可复制 |

对应需求：`FR-STD-DB-META-001` `FR-STD-DB-META-002` `FR-STD-DB-META-003` `FR-STD-DB-META-004` `FR-STD-DB-META-005` `FR-STD-DB-META-006` `FR-STD-DB-META-007` `FR-STD-DB-META-008` `FR-STD-DB-META-009` `FR-STD-DB-META-010` `FR-STD-DB-META-011` `FR-STD-DB-META-013` `FR-STD-DB-META-014` `FR-STD-DB-META-015`

### 3.2.12 【契约】结果集

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 结局四态可区分，空值与空串不混同 | 成功 / 失败（带可读原因）/ 被取消 / 被截断互不吞并；NULL 显示为灰色的「NULL」，空字符串显示为空白；两种情形在复制与导出里仍可区分 |
| 2 | 单元格格式化在领域层完成，两端同一份数据长得一样 | 同一结果集在两端渲染出的单元格文本逐格相同；格式化不丢原值——「查看原文」与导出拿到的是原始字节；二进制给可读占位而非乱码，复杂类型按文本呈现且可复制 |
| 3 | 排序与筛选只改「看的顺序」，不改语句、不重跑查询 | 排序 / 筛选前后执行次数不增加、语句文本不变；点表头升 / 降 / 取消三态，Shift 追加为次要键并显示次序；能解析为数字的列按数值序（2 < 10）、文本按本地化自然序（item2 < item10）；排序稳定，同值行次序不因重复排序改变；NULL 位置固定 |
| 4 | 筛选语义与 SQL 对齐，作用范围明示 | 多条件按 AND 组合，可区分大小写；NULL 只在「为空」下命中；改条件后回到第 1 页；界面明示「仅对已加载的 N 行生效」 |
| 5 | 分页只作用于已加载的行 | 每页可选 50 / 100 / 200 / 500 / 1000 与「全部」；换档回第 1 页；显示「第 N / M 页 · 共 K 行」，页码越界夹取（不出现「第 3 / 1 页」）；复制取当前页的行 |
| 6 | 复制与导出的转义规则固定、逐字节可复现 | 复制四格式（TSV 默认带表头 / Markdown / INSERT / CSV）只进剪贴板不落文件；TSV 把制表符与换行替换为空格，Markdown 转义竖线并把换行写成 `<br>`，CSV 按需加引号，INSERT 缺表名时报错而不产出坏 SQL；同一结果集在两端复制出的同一格式文本逐字节相同 |

对应需求：`FR-STD-DB-RES-001` `FR-STD-DB-RES-002` `FR-STD-DB-RES-003` `FR-STD-DB-RES-004` `FR-STD-DB-RES-005` `FR-STD-DB-RES-006` `FR-STD-DB-RES-007` `FR-STD-DB-RES-008` `FR-STD-DB-RES-009` `FR-STD-DB-RES-011` `FR-STD-DB-EXEC-009` `FR-STD-DB-EXEC-010` `FR-STD-DB-EXEC-011` `FR-STD-DB-EXEC-012` `FR-STD-DB-EXEC-014` `FR-STD-DB-EXEC-016`

### 3.2.13 【契约】表结构与结构变更

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 生成不等于执行：建表 / 删表 / 清空语句只写进新页签 | 生成物进入新页签且不覆盖当前内容；生成动作本身不发送任何语句（服务端语句计数可核）；生成语句可复制后直接执行成功 |
| 2 | 删除类语句默认带存在性判断，真跑仍过安全确认 | `DROP` 默认带「若存在」；语句文本可读可改；实际执行时仍触发高危确认 |
| 3 | 未改动的列不产出变更语句，读得见才能改 | 结构编辑器里只对改动过的列 / 索引 / 约束 / 外键生成语句；索引 / 外键 / 约束可枚举可见；执行前预览 + 二次确认；失败如实报错并保留设计器状态 |
| 4 | 结构对比先归一类型别名再判差异 | `varchar` 与 `character varying` 不计差异；差异按对象类型（表 / 列 / 索引 / 约束）分组列出；同步脚本可预览可复制；不凭空生成未改动列的变更 |
| 5 | 关系图不静默漏表 | 由外键生成关系图，无外键的孤立表同样画出；图可导出 |
| 6 | 标识符按方言引用规则加引号 | 同一份列定义在两端生成的建表语句逐字相同；带保留字 / 大小写 / 特殊字符的标识符在两端引用方式一致 |

对应需求：`FR-STD-DB-DDL-001` `FR-STD-DB-DDL-002` `FR-STD-DB-DDL-003` `FR-STD-DB-DDL-004` `FR-STD-DB-DDL-005`

### 3.2.14 【契约】导入导出

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 导出值逐值等于结果集，空值与转义按格式区分 | 导出的 CSV / JSON / TSV / Markdown / INSERT 与结果集逐行逐值一致；空值表达按格式区分（TSV 留空 / Markdown 写 `NULL`）；同一结果集同一格式在两端导出的文件逐字节相同 |
| 2 | 文本编码有明确默认与可选档，且判决规则与导入侧同一套 | 默认 UTF-8 带 BOM，可选 GB18030；编码写进导出文件名或随文件说明，不只留在内存；导入时有 BOM 认 BOM，否则严格试 UTF-8，再退 GB18030 |
| 3 | 大结果集流式写盘，峰值内存不随行数线性增长 | 整表 / 整库导出走客户端流式（服务端只提供数据流，不用服务端读写文件的写法）；取消时已写文件可弃、连接可回收；结束必须关闭游标（无悬挂事务）；完成后报告行数与文件路径 |
| 4 | 外部备份工具的参数直接交进程，不经 shell；过程可读、可中止 | 实际命令行与执行日志可见；输出按到达顺序逐行显示；取消优雅终止、超时强杀；失败给可读原因与退出码；恢复必须指定目标库，缺库名不生成参数；分段与并行可组合 |
| 5 | 导入不静默跳过失败行 | 解析失败报行号与列名；导入前预览「将写入 N 行」；缺列给默认值或明确拒绝；类型推断失败给可读提示，不静默按文本导入；空行与合并单元格按明示规则处理 |
| 6 | 敏感列默认不导出 | 未显式勾选时导出物不含敏感列；勾选动作可追溯；同一勾选状态在两端导出的列集合相同 |

对应需求：`FR-STD-DB-IO-001` `FR-STD-DB-IO-002` `FR-STD-DB-IO-003` `FR-STD-DB-IO-004` `FR-STD-DB-IO-005` `FR-STD-DB-IO-006` `FR-STD-DB-IO-007` `FR-STD-DB-RES-010` `FR-STD-DB-RES-012` `FR-STD-DB-RES-013` `FR-STD-DB-RES-014`

### 3.2.15 【契约】诊断读数

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 只给读数、不给结论；缺失项显示「—」而不是 0 | 计划摘要五项（节点数、规划耗时、执行耗时、全表扫描处数、最慢节点）与下方计划树数字一致；某端把缺失项写成 0 即判红 |
| 2 | 会真正执行语句的选项必须当场明示 | 选「实际执行」类选项时界面明确提示会真正执行语句；仅估算的选项不执行语句（服务端语句计数可核） |
| 3 | 计划解析失败回落原文，不留空白面板 | 解析失败时展示服务端原始计划文本；节点可展开、可按树或表查看；快捷键可触发并列入帮助面板 |
| 4 | 扩展没装 / 无权限就说没装，不拿别的数凑 | 依赖扩展的读数在扩展缺失或无权限时给明确提示；该版本没有的指标标「不可用」，不显示 0；列名按服务端版本适配；数值带单位与口径说明 |
| 5 | 锁与等待只显示，处置分级且由人决定 | 展示等待者、阻塞者、锁类型，可从被阻塞会话跳到阻塞会话；取消与终止确认强度不同，终止需二次确认；不自动杀会话；无权限或无锁时给可读提示 |
| 6 | 诊断上下文带入连接 / 库 / 对象与最近读数，结论可点回 | 从对象树唤起时上下文自动带入；结论里的对象名可点回对应节点；无读数时明说「未取到」，不编造 |

对应需求：`FR-STD-DB-DIAG-001` `FR-STD-DB-DIAG-002` `FR-STD-DB-DIAG-003` `FR-STD-DB-DIAG-004` `FR-STD-DB-DIAG-005` `FR-STD-DB-DIAG-006`

### 3.2.16 【契约】会话与权限

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 会话列表字段齐、排序固定、刷新不阻塞 | 展示进程号 / 用户 / 库 / 客户端地址 / 状态 / 等待事件 / 已运行时长 / 当前语句；排序为「等待中 → 活跃 → 空闲」；列名按服务端版本适配；同一实例同一时刻两端列出的会话集合与次序相同（时间读数除外） |
| 2 | 看不到的会话如实说看不到 | 普通账号只见自己的会话；权限不足时给可读说明，不显示成空表、不伪造行 |
| 3 | 取消当前语句与终止会话分级，失败原因分类 | 取消温和、终止重确认并说明会掐断连接、回滚未提交事务；失败时区分「无权限 / 会话已不存在 / 其它」；动作与目标会话一一对应，不误伤 |
| 4 | 授权变更先预览后执行，预览与执行逐字一致 | 可查看角色对库 / schema / 表 / 序列的已授权限；生成的 `GRANT` / `REVOKE` 在执行前预览，预览文本与真正发送的文本逐字相同；无权限时给可读错误 |
| 5 | 库属性与删库：留空即不改，删库须手输库名 | 非法值禁用执行并说明原因；改属性可留空表示不修改，执行前实时预览语句；删库必须手输库名才可确认并展示将执行的语句；仍被连接时给可读提示；失败区分「无权限 / 库不存在 / 仍被连接」 |
| 6 | 方言没有的对象类型不显示入口 | 该方言不存在的对象类型不出现入口（不是灰掉、不是点了才报错）；对象树与菜单里同一动作的叫法与层级一致；写操作做输入校验与风险分级 |

对应需求：`FR-STD-DB-SESS-002` `FR-STD-DB-SESS-003` `FR-STD-DB-SESS-004` `FR-STD-DB-SESS-005` `FR-STD-DB-SESS-006`

### 3.2.17 【契约】任务、审批与回执

| # | 不变量 | 可观察判定（跨端同一口径） |
| --- | --- | --- |
| 1 | 任务定义落在连接上，含目标库、只读 / 可写、影响行数上限、是否需审批 | 定义可保存并复用；定义与实际执行参数不一致时**拒绝执行**并说明差异；只读任务里出现写语句被拦下 |
| 2 | 审批是前置的，未确认不发送 | 审批框逐条列出语句、目标库与预估影响范围；未确认时服务端收到的语句数为 0；拒绝即中止，状态为「已拒绝」并可在历史里看到 |
| 3 | 批准只对这一次、这一组参数有效 | 同一任务改参数后再跑需重新审批；批过一次不产生长期豁免（第二次同类任务仍走审批） |
| 4 | 回执是读数不是「完成」二字 | 回执含成功 / 失败、影响行数、耗时、错误原文与执行时刻；失败也有回执；回执挂在执行会话上 |
| 5 | 回执脱敏且可带走 | 回执不含口令与敏感字面量（全量搜索命中 0）；可复制 / 导出；同一任务在两端产生的回执字段集相同 |

对应需求：`FR-STD-DB-TASK-001` `FR-STD-DB-TASK-002` `FR-STD-DB-TASK-003`
## 3.3 工作台界面（STD-WS）契约

本章只写**跨端必须一致的可观察行为**：换一个实现、换一套界面，下面每一条都能拿同样的步骤复现出同样的结果。实现位置、平台差异、判据脚本不在本章。

### 3.3.1 【契约】AI 辅助入口：先出差异，人点了才落盘

| 不变量 | 什么算做到（可观察结果） |
|---|---|
| **产出先以差异呈现** | 任何会写文件的产出，落地前都先给出文件清单与逐行增删；**未确认时，用工作区外的工具读该文件，内容与产出前逐字相同**；确认后内容才变，且此后一步撤销可回到确认前的那一版。 |
| **说得出模型与端点** | 每处建议旁显示当前生效的模型与端点；端点未配置或连不通时显示「未配置 / 连不上」，并且**不出现任何建议正文** —— 没有占位建议、没有「正在生成」的假状态、没有退回本机规则冒充模型。 |
| **数据边界默认最保守且写得出来** | 发出前界面写明本次发送范围（选中片段 / 当前文件 / 不发送），默认取最保守的一档；改过范围后，实际外发内容与界面所写范围一致（按外发记录逐条核对，不多发一段）。 |
| **本机算的不走模型** | 格式化、行号、语言判定、静态检查在三种情况下行为不变：AI 入口关闭、端点未配置、断网。 |
| **整批交付可整批撤回** | 跨文件任务在验收前给出改动文件清单与逐文件差异；未通过验证的产出标「没跑通」；整批撤回只还原这一批落过盘的行，**人在这之后手改的行保留**，冲突逐条报出而不是覆盖。 |

对应需求：`FR-STD-WS-AI-001`、`FR-STD-WS-AI-002`、`FR-STD-WS-EDIT-015`

### 3.3.2 【契约】编辑器的保存与撤销语义

| 不变量 | 什么算做到（可观察结果） |
|---|---|
| **保存有两条路，结果可核** | 主体保存：有路径直接写回，无路径等同另存为（弹保存面板）；成功后页签标题与路径跟着变、未保存标记消失；失败时给可读原因，**编辑器内容与未保存标记都不变**（宁可没保存成，也不清空已敲的字）。 |
| **只有人触发才落盘** | 不自动保存、退出前不静默写盘：没点保存时，磁盘上的内容与时间戳不变 —— 包括刚做完 AI 应用、格式化、检查、清空之后。 |
| **撤销按语义步进** | 一段连续输入合并成一步：连敲一段文字后一次撤销回到输入前，而不是退一个字符；行级动作（移行、复制行、注释切换、缩进、补全插入）各算一步；折叠、移动光标、改选区**不入撤销栈**（撤销一次回到最近一次文本编辑之前）。 |
| **等长替换不动光标与选区** | 任务框翻转、配对补全这类等长替换之后，光标偏移与选区范围与替换前逐项相同（不跳行、不塌成零宽）。 |
| **文件口径按内容判定并保真** | 打开即按真实编码与换行符解码（非 UTF-8 的中文正文不乱码）、按正文判定软 / 硬制表与宽度（不看扩展名）；只改人编辑过的部分，保存后编码、换行符与未改动的行逐字不变；状态栏显示当前编码、换行与缩进口径，可显式切换（缩进切换时已有行一起转换）并立即生效，未确认前不写回文件。 |
| **查找与定位只作用于当前文件** | 查找栏在当前文件内查找替换，单次替换与全部替换各算一步撤销；跳到指定行或列后光标定位并滚动到可见处，越界值夹到边界而不是报错或乱跳；关闭查找栏后文本与光标不变；清空当前页签会同时清掉旧结论，且可一步撤销。 |

对应需求：`FR-STD-WS-EDIT-001`、`FR-STD-WS-EDIT-002`、`FR-STD-WS-EDIT-003`、`FR-STD-WS-EDIT-004`、`FR-STD-WS-EDIT-005`、`FR-STD-WS-EDIT-006`、`FR-STD-WS-EDIT-007`、`FR-STD-WS-EDIT-008`、`FR-STD-WS-EDIT-009`、`FR-STD-WS-EDIT-010`、`FR-STD-WS-EDIT-011`、`FR-STD-WS-EDIT-014`、`FR-STD-WS-EDIT-016`、`FR-STD-WS-EDIT-017`、`FR-STD-WS-EDIT-018`、`FR-STD-WS-EDIT-019`、`FR-STD-WS-EDIT-020`、`FR-STD-WS-EDIT-021`、`FR-STD-WS-EDIT-022`、`FR-STD-WS-EDIT-023`

### 3.3.3 【契约】文件树与文件生命周期

| 不变量 | 什么算做到（可观察结果） |
|---|---|
| **越界从严** | 所有写操作只落在工作区目录内：`..`、绝对路径、指向外部的符号链接逐条被拒并给出可读理由，界面上不出现半完成的条目；版本库内部这类隐藏目录默认不在树里列出。 |
| **一个动作一个入口** | 文件与目录的管理动作只在行的悬浮菜单里出现（目录行三个、文件行两个），每个图标带名称提示；同一动作不出第二处入口 —— 菜单里出现同名项即算两套。 |
| **写操作不留不可逆结果** | 删除后可从系统废纸篓找回；非空目录删除前显示将影响几项，删完树上的条目数与提示数对得上；新建重名、改名撞名一律拒绝并说明，被拒时目标名下的旧文件逐字不变。 |
| **页签跟着文件身份，外部改动不吞输入** | 改名后已打开的页签标题与路径同步变，编辑器内容与光标位置不动；文件被删后其页签转为「已删除」并保留可另存的内容；打开失败给可读原因，且不留下一个空白页签；文件被工作区外的程序改动后 1 秒内出现提示，选「重新载入 / 对比」，有未保存改动时先问再覆盖。 |
| **搜索两个入口、一套匹配** | 工作区标头搜索框只搜当前工作区：文件名命中与内容命中分组列出，内容命中给文件、行号与命中摘要，回车打开该文件并跳到命中行；主搜索框把词交给同一套检索，不另写匹配；跨文件替换先出差异预览再落盘、可撤销；排除规则默认排除版本库内部、依赖目录与构建产物，二进制与超大文件跳过并报出跳过数。 |
| **切换工作区不丢状态** | 同一时刻只有一个活动工作区，切换后页签、终端、会话随之切换，原工作区未保存的内容仍在。 |

对应需求：`FR-STD-WS-FS-001`、`FR-STD-WS-FS-002`、`FR-STD-WS-FS-003`、`FR-STD-WS-FS-004`、`FR-STD-WS-FS-005`、`FR-STD-WS-FS-006`、`FR-STD-WS-FS-007`、`FR-STD-WS-FS-008`、`FR-STD-WS-FS-009`、`FR-STD-WS-FS-010`、`FR-STD-WS-EDIT-012`、`FR-STD-WS-EDIT-013`

### 3.3.4 【契约】帮助入口

| 不变量 | 什么算做到（可观察结果） |
|---|---|
| **入口常驻可用** | 任何视图下工具栏都有问号入口，可点、不置灰、不被其它控件挤掉。 |
| **快捷键表与界面同源** | 帮助里列出的快捷键，与菜单项旁标注、按钮提示里的按键逐条相同；存在一个已可用的动作却没进这张表，本条即不成立。 |
| **没内容就给占位** | 尚未定稿的条目显示明确的「尚未提供」占位，不空白、不报错、不跳外部网页。 |
| **断网可用** | 断网时帮助入口与快捷键表照常打开，内容与联网时一致。 |

对应需求：`FR-STD-WS-HELP-001`

### 3.3.5 【契约】授权呈现

| 不变量 | 什么算做到（可观察结果） |
|---|---|
| **未授权即不出现** | 未授权能力的入口在界面上不存在（不置灰、不出现升级诱导文案）；同时文件树与编辑器照常可用，既有文件可打开、可导出。 |
| **到期只减不增** | 授权到期后不再出现新的能力入口，但已有文件仍可打开与导出，不锁内容。 |
| **状态一处同答** | 版本号与授权状态在首页与帮助里给出同一答案；两处说法不一致即不成立。 |
| **不靠联网判定** | 断网时显示的授权状态与联网时相同，不存在「联网才能用」的环节。 |

对应需求：`FR-STD-WS-LIC-001`

### 3.3.6 【契约】导航、着色与检查

| 不变量 | 什么算做到（可观察结果） |
|---|---|
| **认得才着色，认不出就明说** | 语言按扩展名与文件名判定，认不出时回落纯文本（不硬安一个语言）；着色只分关键字 / 函数 / 字符串 / 注释 / 数字 / 引用标识符六类，配色只取主题令牌 —— 切主题或切深浅后全部同步变化，无一处残留旧色。 |
| **检查结论与上屏同源** | 编辑器上划出的每一处下划线，都能在检查结果里找到对应的一条，反之亦然；没有问题时不留残留标记。 |
| **文本一改，旧结论即失效** | 文本真正改变后，旧结论与下划线立即清空并重算；只移动光标或改选区不清空；重新检查后结论重新出现，计数为本次真实条数。 |
| **计数与上限如实** | 通过时显示「已检查 N 条，跳过 M 条」，N、M 与本次语句数对得上；失败最多列 3 条，另给准确的剩余条数；跳过项按类可展开查看。 |
| **补全不吞输入** | 候选含关键字与内置函数、当前文档符号、路径三类，键盘可上下选择、回车替换光标处标识符；**没有匹配时按键照常输入**，不吞键、不卡顿。 |
| **格式化可预期，重活可降级** | 格式化只改空白与大小写（及标记规范化），token 序列前后完全一致，可一步撤销；认不出或不支持的语言明说原因且内容逐字不变；超长文本暂停实时检查并显示「已跳过实时检查」，回落后恢复，跳过期间输入与光标不迟滞。 |

对应需求：`FR-STD-WS-NAV-001`、`FR-STD-WS-NAV-002`、`FR-STD-WS-NAV-003`、`FR-STD-WS-NAV-004`、`FR-STD-WS-NAV-005`、`FR-STD-WS-NAV-006`、`FR-STD-WS-NAV-007`、`FR-STD-WS-NAV-008`、`FR-STD-WS-NAV-009`、`FR-STD-WS-NAV-010`、`FR-STD-WS-NAV-011`、`FR-STD-WS-NAV-012`、`FR-STD-WS-NAV-013`、`FR-STD-WS-NAV-014`、`FR-STD-WS-EDIT-024`

### 3.3.7 【契约】内部工具面板

| 不变量 | 什么算做到（可观察结果） |
|---|---|
| **窗口级单实例，切视图不断** | 从工作区切到别的视图再切回，终端里上一段的输出仍在、命令历史仍在（会话被重建或清屏即不成立）。 |
| **显隐与尺寸可记** | 面板可拖高、可折叠、可最大化；显隐在菜单与快捷键各有一处入口且指向同一动作；下次启动时保持上次的显隐与尺寸。 |
| **页签集合固定** | 面板页签为问题 / 输出 / 终端 / 调试控制台四项；查询结果表不在其中（数据仍留在编辑器区下方自己的位置）。 |
| **终端是真实会话** | 交互式 shell 是真终端（在会话里能查到自身的设备终端）；中日韩宽字符占两格、256 色可显示；环境受限时如实说明原因，而不是静默显示成坏终端。 |
| **调试如实报状态** | 断点被外部挪动后说明「原位置已不存在」；调试期间文件被改时提示「代码与运行体不一致」；调试器不可用不影响普通编辑与保存。 |

对应需求：`FR-STD-WS-TOOL-001`、`FR-STD-WS-TOOL-002`、`FR-STD-WS-TOOL-003`

### 3.3.8 【契约】页签、界面状态与外观

| 不变量 | 什么算做到（可观察结果） |
|---|---|
| **至少留一个页签，多窗口互不牵连** | 关闭最后一个页签被拒绝或原地重建；各窗口的页签集合与选中态独立，一窗关页签不影响另一窗，同一连接可在多个窗口并行打开。 |
| **页签条高度不由内容决定** | 空白页签与有地址、有标题的页签同高；页签从 2 个加到 10 个只出现横向滚动，不换行、不撑高标题栏。 |
| **关闭脏页签先问，不阻塞** | 无改动直接关；有改动给「保存并关闭 / 不保存直接关闭 / 取消」三个动作；保存失败就不关并说明原因；动作集合只有一处定义，界面不许多出一个按钮。 |
| **会话恢复不吞改动** | 重启回到上次的工作区与页签集（顺序、活动页签、光标与滚动位置）；未保存的缓冲要么原样恢复并标「未保存」，要么启动时问一次；恢复失败如实告知，不开一个空工作区冒充上次现场。 |
| **命令与搜索共用一套动作** | 命令面板、工具栏、菜单引用同一份动作定义；匹配分档且排序稳定（同样查询两次逐条同序），空查询给出常用项；主搜索框只把词交给文件检索，不另写一套匹配。 |
| **外观只走主题令牌** | 三处可编辑文本的区域在同一主题同一深浅下底色与字色相同；主题三态、强调色、等宽字体与字号（9–20）切换立即生效并持久化；未设置或未知值回退默认且不报错，字体不可用时回落并如实报告。 |

对应需求：`FR-STD-WS-UI-001`、`FR-STD-WS-UI-002`、`FR-STD-WS-UI-003`、`FR-STD-WS-UI-004`、`FR-STD-WS-UI-005`、`FR-STD-WS-UI-006`、`FR-STD-WS-UI-007`、`FR-STD-WS-UI-008`、`FR-STD-WS-UI-009`、`FR-STD-WS-UI-010`、`FR-STD-WS-UI-011`

### 3.3.9 【契约】版本控制集成

| 不变量 | 什么算做到（可观察结果） |
|---|---|
| **只读，不给写入口** | 界面上不存在提交、推送、合并、切分支的入口；从差异视图改不动文件，改动只能在编辑器里发生。 |
| **清单与实际仓库一致** | 显示的分支与改动文件清单，与该目录仓库状态命令的结果逐条一致（多一个少一个即不成立）。 |
| **差异粒度可预期** | 改一个函数只显示对应那一段；勾选忽略空白后纯空白的改动不再出现；万行级文件按需渲染，打开与滚动不卡。 |
| **不可用时如实说明** | 未安装或目录不是仓库时给可读原因，同时编辑、文件树、保存照常可用。 |

对应需求：`FR-STD-WS-VCS-001`、`FR-STD-WS-VCS-002`

### 3.3.10 【契约】内嵌浏览器与预览

| 不变量 | 什么算做到（可观察结果） |
|---|---|
| **页签同类可关、默认空白** | 浏览页签与首页、文件页签同列，可关闭、可随会话恢复；新开时是空白页，不自动加载任何远程内容。 |
| **出网留痕** | 每次导航与每次下载各留一条可查记录（目标地址、发起页签）；查不到记录的出网即不成立。 |
| **对站点是常规浏览器** | 同一地址在页签与常规浏览器中打开，页面与登录流程一致；依赖第三方 Cookie 的登录跳转返回后仍是登录态；新窗口打开的链接有可见结果（转新页签或明确提示）；证书错误给可读原因与「继续 / 取消」；站点明确拒绝被内嵌时如实说明并给出「用常规浏览器打开」，不假装成功。 |
| **预览与源码互不覆盖** | Markdown 与网页文件可在源码与只读预览间切换或分屏；预览按文件所在目录解析相对路径（同目录样式、脚本、图片正常生效）；断网时本地页面照常渲染；预览里的链接默认在浏览页签打开，不弹外部浏览器；两边切换不丢未保存改动。 |
| **越界与超大如实** | 预览引用的路径越出工作区或已授权目录时一律拒绝并给可读原因；超大文件与二进制在预览中如实截断并报出被截掉的量。 |

对应需求：`FR-STD-WS-WEB-001`、`FR-STD-WS-WEB-002`、`FR-STD-WS-WEB-003`、`FR-STD-WS-WEB-004`
## 3.4 笔记（NTS）契约

> 本章十四个域，每条不变量都以「两个端做同一件事，可观察结果是否相同」为判法。实现手段可以不同，结论必须一样；表格末列写的是越界之后用户会看到的样子 —— 判定契约有没有守住，看的就是那一列。

### 3.4.1 【契约】快速捕获

| 不变量 | 判定条件 | 越界后的可见症状 |
|---|---|---|
| 触发即编辑 | 从触发到光标可输入之间不出现任何选择步骤（不选归属、不选模板、不填标题）；新建条目一律落在默认归属 | 随手记变成「先整理再记录」，念头在选目录那一步丢掉 |
| 无标题可存 | 空标题不阻断保存；标题缺省取正文首行的可见文本，首行为空则以「无标题」占位 | 记两行字要先想一个标题，否则存不下去 |
| 断网可记 | 捕获与保存不依赖网络与账号，写入只落本机，成功后立即可读；联网前状态是「待同步」而不是「失败」 | 没信号的地方记不进东西，或一律显示保存失败 |
| 草稿不丢 | 捕获面被关闭、切走或进程退出后，未提交内容仍可找回，且与关闭前最后一次输入逐字相同 | 「刚才写的那句哪去了」，且说不清丢在哪一步 |
| 捕获不承担整理 | 捕获路径上不出现标签、归属、模板的必填项；整理只发生在捕获完成之后，不阻塞捕获 | 每记一条都要做一次归类决策，记的频率自然下降 |

对应需求：`FR-NTS-NOTE-CAPTURE-001`

### 3.4.2 【契约】附件与图片

| 不变量 | 判定条件 | 越界后的可见症状 |
|---|---|---|
| 字节在盘、引用在库 | 库内只有引用（标识、原文件名、字节数、内容摘要）；库体积不随附件字节线性增长 | 备份与同步被图片拖到几百兆，删条目还连带丢附件 |
| 原件不改写 | 缩放、旋转、裁切只作用于显示；原始字节与像素在任何操作后摘要不变 | 插进去的图越存越糊，原图取不回来 |
| 同内容一份 | 内容摘要相同的附件只存一份，多条笔记共享同一份；引用归零才允许回收 | 同一张图在十条笔记里各存一份，占用与笔记数同速增长 |
| 缺失必须说出来 | 引用解析不到字节时显示「文件不在了」并给出原文件名与原位置，不画空白框、不静默删掉引用行 | 正文里剩一个空框，没人知道原来是什么 |
| 删除分级 | 删笔记只让引用失效（条目进回收站），不回收字节；彻底清除时才判断是否仍被其它未删条目引用，并要一次确认 | 删一条笔记，把另一个归属里还在用的图一起带走 |

对应需求：`FR-NTS-NOTE-ATTACH-001`

### 3.4.3 【契约】导出与迁移

| 不变量 | 判定条件 | 越界后的可见症状 |
|---|---|---|
| 导出是副本 | 导出前后逐条比对正文摘要、更新时间与归属，全部不变 | 导出一份 Markdown，库里时间全被刷新 |
| 三形态同源 | Markdown、纯文本、备份包由同一份正文权威源派生；同一批条目在三种产物里的条数一致 | 同一批笔记导三次得到三个不同的集合 |
| 备份包可完整还原 | 导入自己导出的备份包后，条数、标题、正文、标签集合、创建与更新时间、附件引用逐条相等 | 导进去少一半，或标签全平掉 |
| 有损要声明 | 目标格式表达不了的成分（附件、合并单元格、格式清单外的语法）在产物内逐条标注，不静默丢弃 | 导出「成功」，打开后少了几段而无人在场知晓 |
| 版本位在前 | 备份包带格式版本位与条目清单；包里版本高于本端支持范围时拒绝导入并说明，不做半懂不懂的读取 | 新端导出的包被旧端读成残缺数据，且没有任何报错 |

对应需求：`FR-NTS-NOTE-EXPORT-001`

### 3.4.4 【契约】正文格式与编辑

| 不变量 | 判定条件 | 越界后的可见症状 |
|---|---|---|
| 一份权威源 | 正文以带版本位的结构化形态为权威；Markdown、纯文本、导出产物、检索索引都是派生物，可由权威源重新算出 | 界面、导出、检索各显示一个样子，且分不清哪个是真的 |
| 格式清单封闭 | 允许的块级与行内格式是有限、可枚举的一份清单；清单外的语法按字面文本保存，不做猜测性解释 | 粘贴一段外部内容后，样式随来源漂移，收不回来 |
| 双模式往返无损 | 所见即所得与源码互相切换，每种格式进出后语义不变；同一篇文档连续往返多次，序列化结果逐字节相同 | 切一次源码，加粗变星号、缩进塌一层 |
| 撤销以段落为粒度 | 一次撤销回退一个编辑事务（一段输入或一次格式操作），不逐字符、也不整篇回退 | 敲错一个字要按十几下撤销，或一按就退回上一版 |
| 大文档可用 | 万行级正文可打开、可编辑、可检索，滚动与输入不触发整篇重排；超过单篇上限时提示并保持可读可编辑 | 长文一打开就卡，或直接被拒绝打开 |

**跨端判法**：同一条笔记在两个端打开，正文文本、块级结构、行内样式、段落顺序完全一致。允许不同的是光标位置、折叠状态、输入法临时标记这类不落库的视图状态。

对应需求：`FR-NTS-NOTE-FORMAT-001`

### 3.4.5 【契约】整理：标签 / 收藏 / 置顶 / 归档

| 不变量 | 判定条件 | 越界后的可见症状 |
|---|---|---|
| 整理不动内容 | 打标签、收藏、置顶、归档、改归属都不改标题与正文，也不刷新内容更新时间（整理另记时间） | 加个标签，笔记就蹿到「最近更新」最上面 |
| 批量先给影响面 | 任何批量操作执行前显示「将影响 N 条」；N 与实际执行由同一份判定算出，预览与执行不各算一次 | 显示影响 12 条，实际改了 40 条 |
| 一步可撤销 | 整理类操作（含批量、含跨归属移动）可整体撤销到操作前；撤销后正文、标签、归属、排序位逐条复原 | 「撤销」只退了一半，或退完顺序变了 |
| 归档不等于删除 | 归档只移出默认视图，条目仍可被检索到（受搜索范围约束）并可原样取回；归档不占回收站，不受回收站到期清除影响 | 归档几天后东西凭空消失 |
| 标签是集合 | 同一条目同一标签只有一份；删标签只解除关联，不删条目、不改正文；重名标签不擅自改写大小写与空白 | 同一个标签出现两次，或在正文里被顺手替换掉 |

对应需求：`FR-NTS-NOTE-ORG-001`

### 3.4.6 【契约】私密保护与加密边界

| 不变量 | 判定条件 | 越界后的可见症状 |
|---|---|---|
| 私密不进检索 | 标为私密的条目不出现在任何检索路径（关键词、语义、标签、全局搜索）的结果里，也不计入可见计数与摘要卡片 | 搜到了自己藏起来的那条，标题还在结果行上照旧显示 |
| 私密不外发 | 私密条目不进入助手上下文、不进入消息与外发通道、不进导出（含备份包）、不上传；被引用时以「一条私密条目」占位并明说不可读 | 私密笔记被助手复述到对话里，或被同步上云 |
| 二次验证才可读 | 打开、预览、尝试导出都要过一次验证；验证未过时不泄露标题、首行与字符数 | 锁定只画了个锁形，内容在预览缩略里露出来 |
| 存储格式不分叉 | 私密标记不改变存储形状与加密方式；存储层加密若开启属整库层的事，与单条私密标记正交 | 出现两套存储形态，换端读不了同一份数据 |
| 边界与退出要说清 | 它挡的是「本机已解锁时被人随手翻」，不挡拿到磁盘的人；取消私密要二次确认，并说明此后该条会被检索、同步与导出覆盖 | 用户以为标了私密就等于加密，真遇到拿到磁盘的人时毫无防线 |

对应需求：`FR-NTS-NOTE-PRIVACY-001`

### 3.4.7 【契约】列表与检索

| 不变量 | 判定条件 | 越界后的可见症状 |
|---|---|---|
| 两条检索都在 | 关键词检索与语义检索各自可用，结果可分栏并列对照；任何一条不能用时如实标出，不用另一条顶替 | 语义检索坏了，界面只给关键词结果，看上去像「语义从来没命中过」 |
| 降级要说话 | 语义检索不可用时明写「当前只有关键词结果」，并按可读类别给出原因（索引未建 / 能力不可用 / 离线受限） | 结果少了，界面一个字都不解释 |
| 覆盖字段一致 | 检索至少覆盖标题、正文、标签；同一查询在两个端命中的字段集合相同 | 同一条笔记一端搜标签能中，另一端搜不到 |
| 次序是总序 | 同一查询结果次序确定：先命中强度、再更新时间、再标题；刷新与重查不改变次序 | 同样的搜索连按两次，列表顺序变了 |
| 超时与无命中分开说 | 万条量级下检索在可接受响应内返回；超时报「还在查」，不把超时当成「没有匹配」 | 大库搜不到东西，用户以为笔记丢了 |

对应需求：`FR-NTS-NOTE-SEARCH-001`

### 3.4.8 【契约】同步与冲突合并

| 不变量 | 判定条件 | 越界后的可见症状 |
|---|---|---|
| 本地为主，可带走、可恢复 | 云端关闭、不达或账号失效时，新建、编辑、检索、导出、待办全部照常，唯一差异是跨端看不到，重新登录后按同一套规则接上；任何时刻可完整导出；本地数据丢失后从云端副本恢复到新位置并校验通过才切换，不就地覆盖现有库 | 断网或关掉云之后写不了也搜不了；或恢复动作把还在的本地数据覆盖掉 |
| 离线可写、联网可合、状态可见 | 离线写入在本地排队，联网后按序合并；同一批重放两次结果相同；每条或每批的同步状态至少能区分已同步 / 待同步 / 冲突，并能说出这一档的原因 | 联一次网同一条变成两条，或内容被吞掉；「刚才那段到底同步了没有」无法回答 |
| 判定键唯一、由人定 | 记录级判胜：先比严格递增的记录版本号，版本号相同再比更新时间，仍相同按固定次序（设备标识）兜底，三个端同一套比较规则；无人工选择时不做静默覆盖，默认保留两版并标冲突 | 同一场冲突两端判出不同胜者，来回同步成乒乓；或界面自动挑了一版，用户永远不知道另一版存在 |
| 落败版留底、合并可回退 | 被覆盖的那一版原样保留（不进回收站、不被裁剪），可打开、可另存为新条目，两版都标来源设备与时间；合并产出一个新版本，参与合并的两版仍可取回 | 冲突后只剩一份，另一份修改无人知道曾存在；合错了回不到合并之前 |
| 删除不被复活 | 删除以墓碑传播，墓碑的版本号严格递增，且不被更高版本号的副本按同一套判定覆盖回来 | 删除在同步里被当成一次普通修改，被另一端的历史版本顶回来 |

对应需求：`FR-NTS-NOTE-SYNC-001` `FR-NTS-NOTE-SYNC-002`

### 3.4.9 【契约】删除与回收站

| 不变量 | 判定条件 | 越界后的可见症状 |
|---|---|---|
| 删除只进回收站 | 删除把条目移入回收站，正文与附件引用保留；回收站内可看、可预览、可恢复 | 删错了没有回头路 |
| 清除只有两种触发 | 彻底清除只在两种情况发生：用户显式确认，或超过保留期 / 容量上限；两种都事前提示后果，含不可恢复与附件一并处理 | 东西某天忽然没了，全程没有提示 |
| 上限可见 | 保留期与容量上限可查；接近上限时提示，自动清除前一次提醒，清除后能说出清了哪些 | 上限只写在文档里，清理是不可预期的 |
| 墓碑跨端传播 | 删除以墓碑同步且版本号严格递增；离线端上线后不复活已删条目，也不出现「一端已删、另一端仍能编辑」 | 删掉的条目在另一端还在，还能改出新版本同步回来 |
| 恢复回原位 | 恢复放回原归属与原排序位；原归属已不存在时落默认归属并说明，不留无归属条目 | 恢复之后散在「全部」里，找不到原来的位置 |

对应需求：`FR-NTS-NOTE-TRASH-001`

### 3.4.10 【契约】历史版本

| 不变量 | 判定条件 | 越界后的可见症状 |
|---|---|---|
| 内容保存才留版 | 每次内容类保存产生一个版本；整理类动作（标签、收藏、置顶、归档、改归属）不产生内容版本 | 打一个标签就多一个版本，历史被噪声淹没 |
| 回滚生成新版本 | 回滚不删任何既有版本，回滚本身产出一个新版本（内容等于被回滚到的版本），因此回滚可再回滚 | 回滚之后「回滚前那一版」消失，等于换一种方式删除 |
| 版本可辨认 | 版本列表带时间与摘要（变更字数或首若干字的可见文本），不带附件字节；任意两版可对照看出增删的块 | 版本列表只有时间，分不清哪个是改对的那一版 |
| 保留策略写明上限 | 保留条数或天数可配，上限写在设置项当场；被策略淘汰的版本以「已清理」明示，不静默消失 | 想找上周那版，才发现早被清掉了 |
| 版本与同步同源 | 版本序列按内容版本号单调递增；冲突合并产生的两版都进同一版本序列，不另立一套历史 | 冲突留下那版只能从冲突入口看到，历史里查不到 |

对应需求：`FR-NTS-NOTE-VERSION-001`

### 3.4.11 【契约】待办清单与组织

| 不变量 | 判定条件 | 越界后的可见症状 |
|---|---|---|
| 本体四字段齐备 | 标题、截止时间、重复规则、完成态都可编辑，空值语义明确：无截止即空（不是今天）、从未完成即完成时刻为空 | 「没设截止」被存成「今天到期」，清单里冒出一堆假逾期 |
| 独立对象、同一链路 | 待办有独立入口与独立列表，不塞进笔记列表；存储、同步、加密与笔记走同一条链路，不另开第二套 | 待办在自己的通道上，笔记好了它没好 |
| 五列可见可改 | 清单行显示标题、截止时间、完成态、优先级、标签，五列都能就地改；从新建到可见不超过一个动作 | 改个优先级要先进详情，改完刷新才看见 |
| 分组筛选可组合 | 分组（按时间 / 按状态 / 按标签）、筛选（今天 / 本周 / 已过期 / 无截止）、排序可叠加，结果由同一份数据算出 | 筛「今天」再按标签分组，条数对不上 |
| 标签只有一维 | 标签与清单归类是同一维，不设第二套分类字段；未知的优先级取值按「未设置」处理，不因一个不认识的取值拒收整条 | 另一端多了一档优先级，这边整条任务读不进来 |

对应需求：`FR-NTS-TODO-LIST-001` `FR-NTS-TODO-LIST-002` `FR-NTS-TODO-LIST-003`

### 3.4.12 【契约】完成与改期

| 不变量 | 判定条件 | 越界后的可见症状 |
|---|---|---|
| 清单是唯一事实源 | 任务数据只有一份；清单与日历都是它的渲染，日历侧不存任务、不产生第二套状态 | 日历里完成一条，清单里还挂着，两边各自「看起来都对」 |
| 一次写入、两处立即可见 | 完成与改期在清单与日历上是同一条记录的同一次写入（同一事务）；写完另一处不经刷新即可见 | 在日历上划掉的任务，切回清单还在 |
| 完成态只有一条写路 | 改标题、改标签、改期、改归属都不改写完成态与完成时刻；完成与重开是独立动作 | 打开一条已完成的任务改个错字，保存后它变回未完成 |
| 改期只动截止 | 改期写新的截止时间并刷新内容更新时间；完成态、重复规则的归属（这一条还是这一串）不被顺手改写 | 改一个日期，整串重复任务的规则跟着变了 |
| 冲突不丢操作 | 两个端同时改同一条时，按同一套记录级判定出胜者，落败的那次操作留底可查 | 一边标完成、一边改期，最后两个动作都没了 |

对应需求：`FR-NTS-TODO-STATE-001` `FR-NTS-TODO-STATE-002`

### 3.4.13 【契约】日历

| 不变量 | 判定条件 | 越界后的可见症状 |
|---|---|---|
| 视图不改数据 | 月 / 周切换、翻页、选中某日都是视图状态，不落库、不复制任务；来回切换后清单条数一份不差 | 翻两个月再切回清单，任务多了几份 |
| 铺在截止那天、点了有事 | 任务出现在其截止时刻所在的那一天；点某天列出当天任务、点任务进详情；没有任务的一天明写「这天没有任务」，不留点了没反应的格子 | 无截止的任务被塞进「今天」，或点开一格什么都没有 |
| 重复按发生日铺开 | 带重复规则的任务按发生日在日历上展开，存储里仍只有一条记录，不预生成副本；改一次要显式回答改的是这一条还是这一串 | 一次重复任务生成几十条记录，删一条删不干净 |
| 日界与周界写死 | 一周从周一开始；月视图按整周补齐（前后补相邻月的日子并标为非本月），格数是七的整数倍；「今天」由调用方显式传入，不各自读系统时钟 | 两端的月视图错开一列，或月初落在错误的格子里 |
| 逾期判定唯一 | 逾期 = 未完成且截止时刻早于今天起点（正好等于今天起点算今天，不算逾期）；日历与清单给出同一结论 | 同一条任务在日历上标红、在清单上写「今天」 |

对应需求：`FR-NTS-TODO-CALENDAR-001` `FR-NTS-TODO-CALENDAR-002`

### 3.4.14 【契约】待办与笔记的双向转化

| 不变量 | 判定条件 | 越界后的可见症状 |
|---|---|---|
| 转化是新建，不是改类型 | 笔记生成任务、任务记成笔记都产出新对象，原对象的类型、正文与时间均不变 | 转成任务之后，原笔记从笔记列表里消失 |
| 双向可见可跳转 | 两端详情都能看到「来自 / 已生成」并可直接跳到对方 | 生成完就断了线，只能靠标题回忆是从哪来的 |
| 链接带快照 | 关联由目标标识与生成时刻的快照（标题与摘要）组成；目标后续被改时不自动改写对方内容 | 改一处另一处跟着变，追不出改的是谁 |
| 可撤销 | 生成动作可整体撤销：删掉新对象并解除回指，撤销后两端都不留悬挂引用 | 撤销只删了一头，另一头指着不存在的东西 |
| 来源被删要标注 | 来源进回收站或被清除时，另一端保留快照并标「来源已删除」；不显示断链、也不跟着删 | 一处删了，另一处静默消失或点开报错 |

对应需求：`FR-NTS-TODO-LINK-001`
## 3.5 交易复盘（RTR）契约

本章覆盖交易复盘的十八个域、八十二条需求。契约层只钉两件事：**同一条数据在两次运行里必须给出同一个答案**，以及**没有数据时各处的表现必须一致**。实现形状（放哪张表、用哪个库、界面用哪种控件）不在此约束。

#### 数据流与公共口径

七段流水，每段的产出都是**具名产物**（有标识、有内容摘要），下游只认产物不认「当前最新」：

| 段 | 入口 | 产出 | 确定性锚点 |
|---|---|---|---|
| 触发 | 外部调度侧 / 手动 | 任务标识 + 期号 | 期号由节拍与交易日历推出，不由运行时刻推出 |
| 取数 | 抓取 / 文件导入 | 原始快照（来源 + 抓取时刻 + 复权方式） | 快照按内容摘要去重；同源同日重跑得同内容 |
| 落库 | 单标的事务 | 库内行（幂等键 = 标的 + 周期 + 交易日 + 复权方式） | 同键覆盖，不追加 |
| 体检 | 交易日历对账 | 缺口 / 漂移 / 异常清单 | 判据只有一套，界面与导出同源 |
| 复盘 | 成交 + 行情 + 事件 | 指标、曲线、归因清单 | 输入锚 + 口径标识固定后逐值可复算 |
| 研究 | 游标 + 特征 + 规则 | 命中清单、样本统计 | 最大数据日 ≤ 游标日 |
| 报告 | 模板 + 变量 | 周报包 | 幂等键 = 规则标识 + 周期 |

**公共口径 A（输入锚）**：一次运行绑定三样标识 ——「数据快照标识 + 口径标识（复权 / 费用 / 窗口 / 参数）+ 规则或模型标识」。三者任一变化 ⇒ 结果标识必须变化并重新声明；**复算按标识取数，不按库里最新**。没有这一条，「两次运行结果不同」永远会被解释成「数据变了」。

**公共口径 B（全序）**：任何列表、序列、导出都必须给出**全序排序键**，且并列时用末位键（记录标识或标的代码升序）打破。顺序**不许**来自抓取顺序、目录遍历顺序、哈希顺序、并发完成顺序。

**公共口径 C（数字写法）**：金额以最小货币单位整数存储与累计；比率输出保留 **6 位小数**，末位**四舍五入（逢半进位）**，不用银行家舍入（两种舍入在边界样本上会给出两个答案）；中间计算不截断，**只在输出处舍入一次**。

**公共口径 D（缺失三分）**：**缺失**（未知）/ **零**（真实为零）/ **不适用**（口径上不存在）是三种语义，不得合并。落库用可空列 + 原因类别，**不用哨兵数字**（-1、0、空串一律不许充当缺失）；计算侧剔除缺失项并报「可用样本 n/N」；展示侧四处同一表现：

| 情形 | 库 / 计算 | 图表 | 表格 / 导出 | 结论区 |
|---|---|---|---|---|
| 价格缺口 | 该交易日无行，不插值、不前值填充 | 断点，两点不连线，缺口处标缺口计数 | 空单元格 + 原因「缺行情」 | 依赖该段的统计输出「不适用」并报 n/N |
| 成交量为零 | 存真实 0，与缺失分开 | 量柱高度 0（与断点可区分） | 0 | 正常参与统计 |
| 分钟线缺失 | 该笔的进出场效率无值 | 该笔区间灰带 | 空单元格 + 「无法计算」 | 分母剔除该笔并报 n/N |

**「两次运行同一个结果」的判定**：除运行时刻、耗时、日志外，产物**逐字段、逐行、逐顺序**一致（含舍入末位、含缺失标记）。出现不一致即判红，**不接受「浮点噪声」作解释**；确实需要容差的地方，容差与比较位必须先写进口径标识。

---

### 3.5.1 【契约】定时触发与缺期

① **三类触发一处登记** —— 价格 / 资金 / 事件三类条件与动作结构化入库；档案里展示的规则与判定所读的是**同一份登记**（改一处不出现两套口径）；停用只置停用态并保留历史，不提供删除。

| 触发类 | 条件要素（缺一不成立） | 判定时点 | 去重键 |
|---|---|---|---|
| 价格 | 标的 + 比较方向 + 阈值 + 复权口径 + 观察窗口 | 该标的最近一个**已收盘**交易日 | 规则标识 + 标的 + 状态档 |
| 资金 | 标的 + 指标口径（净额 / 占比）+ 阈值 + 窗口 | 同上 | 规则标识 + 标的 + 状态档 |
| 事件 | 事件类型 + 标的或板块 + 生效日 | 事件日期 ≤ 判定日 | 规则标识 + 事件标识 |

② **命中判定是纯函数** —— 给定「规则 + 该规则读取的数据行」，结论唯一；判定只读判定日及之前的数据，不读盘中、不读未收盘的当日行。数据未变时连续两次判定，结论**与引用行**完全一致。

③ **只提醒状态翻转** —— 状态档只有「未命中 / 命中」两档；同档内重复检查不再投递；回到未命中后再次命中才算新的一次。每次投递留痕三项：判定时刻、规则、判定所读数据行的引用（可回跳）。判定逻辑不许依赖「上次什么时候提醒过」这类外部状态来决定结论。

④ **定时生成本身在仓外，缺期只记一行** —— 定时器、模型调用、对外抓取三样都不在本仓进程内（三样皆可机检）。触发失败或机器未运行 ⇒ **只生成当期、不补历史**，并落一行「缺期」（期号 + 结果 + 原因类别）；**应有期号集合 − 已生成期号集合 = 缺期行集合**，缺一判红。

对应需求：`FR-RTR-FLOW-CRON-001` `FR-RTR-FLOW-CRON-002` `FR-RTR-FLOW-CRON-003` `FR-RTR-FLOW-CRON-004`

### 3.5.2 【契约】流水线编排

① **步 = 具名产物 + 显式输入清单** —— 步间只经产物交接；步内不许隐式读「当前最新」数据（否则两次运行输入不同而无人知情）。产物标识 = 内容摘要，同名同内容 ⇒ 同标识。

② **失败停在失败步** —— 已完成步的产物保留且标识不变；续跑先核「已完成步的输入锚未变」，**变了就从变化的那一步重跑**，不许半新半旧拼接。

③ **两次运行可逐步对比** —— 输出「哪几步产物相同 / 哪几步变了 / 变在哪个字段」。**输入锚与口径标识相同而产物不同 ⇒ 判红**；反之产物相同而标识不同是正常的（说明数据没变、口径变了）。

④ **写者唯一、顺序固定** —— 可并行的步只读同一份输入、不写共享状态；对同一产物的写者只有一处，落盘顺序不影响内容（否则顺序会渗进结果）。

| 运行记录字段 | 用途 |
|---|---|
| 运行标识 · 输入锚 · 口径标识 | 复算取数的依据 |
| 每步产物标识 · 失败步 | 续跑与差异对比的依据 |
| 差异摘要（步 + 字段） | 两次运行对比的直接产出 |

对应需求：`FR-RTR-FLOW-ORCH-001`

### 3.5.3 【契约】内置市场口径词条

① **词条四件齐** —— 算式 + 参数 + 时间窗 + 出处；四件不齐不收录。「放量」「背离」这类词若落不成算式，就不是词条。

② **同名多流派并列，不合流** —— 同一名词的不同流派并列陈列，**展示必带流派标注**；选一个流派 = 选一个口径标识（公共口径 A），两个流派的结果不许出现在同一张表里而不标注。

③ **参数改动即换锚** —— 参数（N、k 等）进结果锚；同参数同数据两次求值逐值一致。

| 词条 | 算式 | 参数 |
|---|---|---|
| 放量 | 当日成交量 ÷ 过去 N 个交易日成交量均值 ≥ k（均值**不含当日**） | N、k |
| 缩量 | 同上比值 ≤ 1 ÷ k′ | N、k′ |
| 突破 | 当日收盘 > 前 N 个交易日最高收盘（不含当日） | N |
| 回踩 | 当日最低 ≤ 前 N 日最高收盘 且 当日收盘 > 该值（触及不破） | N |
| 背离 | 价格创 N 日新高，而写明的那个指标未创 N 日新高 | 指标、N、比较窗口 |
| 量价配合 | 当日上涨 且 量比 ≥ k（量比 = 当日成交量 ÷ 过去 5 个交易日成交量均值） | k |
| 板块轮动 | 板块 N 日涨幅在全部板块中的排名上升 ≥ m 位 | N、m |

④ **冲突显式提示** —— 用户自定义词条与内置同名时，提示并让用户选一个，**不静默覆盖、不静默并存**。

对应需求：`FR-RTR-FLOW-MARKET-001`

### 3.5.4 【契约】行情接入：抓取、复权与文件导入

① **一次抓取两样产物，逐字段对得上** —— 原始快照（带来源、抓取时刻、复权方式）+ 库内行，对账**按字段比**，不比条数印象；快照按内容摘要去重。幂等键 = 标的 + 周期 + 交易日 + 复权方式，同键重跑**覆盖不追加**；写入按**单标的事务**，失败不落半截行（半个标的比没有更坏：它会被当成「已有数据」）。

② **复权与来源随行** —— 每条价格带来源与复权标记；复权价能用复权因子复算（相对差 ≤ 1e-6）；跨源口径不同时，界面与导出**都必须显示口径**，且不同口径的序列不进同一次计算（混算即判红）。

③ **换源不改上层** —— 取数按「能力 → 适配」组织：同一能力至少两个独立源可实现；上层（入库 / 渲染 / 查询）**不出现任何源专有字段名**；新增一个源 = 只加适配与注册，不改上层；源字段到可读名的映射有台账（否则一个字段名会从一处漏到十来处）。

④ **文件导入的拒绝与幂等** —— 时间 + 开高低收必需，成交量缺列 = **缺失**（不填 0）；缺必需列 ⇒ **整份拒绝并点名缺哪列**，不半懂不懂地导入；时间解析覆盖「仅日期」与「日期 + 时分秒」两形态；同标的同周期重复导入幂等；一个文件只放一个标的。

⑤ **内置样本开箱可用且隔离** —— 首次启动即可走完「导入 → 回放 → 标注 → 总结」四步（不依赖用户先找数据）；样本内容固定 ⇒ 可作回归基线；来源 / 处理方式 / 校验和随包可查；样本与用户数据分开存放，一键清除只清样本。

对应需求：`FR-RTR-MKT-FEED-001` `FR-RTR-MKT-FEED-002` `FR-RTR-MKT-FEED-003` `FR-RTR-MKT-FEED-004` `FR-RTR-MKT-FEED-005`

### 3.5.5 【契约】财务与事件叠加

① **事件一个形状** —— 类型 + 标的或板块 + 事件日期 + 来源指针 + 录入时刻；手工录入**必带录入时刻**（未来信息判定要用）。

| 事件类 | 关键字段 | 判据要点 |
|---|---|---|
| 财报 / 业绩预告 | 披露日 · 报告期 · 来源 | 以**披露日**入时间轴 |
| 涨跌停 / 放量突破 | 阈值参数 · 命中日 | 阈值与算式留档，命中日可复现 |
| 增减持 / 回购 | 公告日 · 方向 · 数量 | 以**公告日**入时间轴 |
| 政策 / 新闻 | 事件日 · 来源链接 · 录入时刻 | 手工条目必留录入时刻 |

② **财报按披露日，不按报告期** —— 把某报告期的数据当成它披露之前就可得，是未来函数；出现即拦住计算并说明原因，不出数。

③ **事件日期 > 游标日的一条都不出** —— 图表、表格、导出三处同一判据；手工录入的条目按**事件日期**归属，不按录入时刻归属（否则补录一条旧事会改写历史结论）。

④ **阈值可配且算式写得出** —— 如「当日涨幅 ≥ X% 且量比 ≥ k」；涨跌停按「以昨日收盘为基数、交易所规则取整」计算涨停价/跌停价，取整方式写进口径，不许一处四舍一处进位。命中时点两次运行一致。

⑤ **叠加只改绘制** —— 关掉叠加层不得改变任何指标读数、统计口径与导出的数据列；开关状态不入结果锚。

对应需求：`FR-RTR-MKT-FUND-001` `FR-RTR-MKT-FUND-002` `FR-RTR-MKT-FUND-003` `FR-RTR-MKT-FUND-004`

### 3.5.6 【契约】数据健康与告警

① **健康是实测值，不是「没报错」** —— 每次抓取一条记录 + 每接口一行明细：响应码、耗时、空字段率、是否超时；**空字段率 = 空字段数 ÷ 应有字段数**；另列「多出字段数」。最近 N 次成功率 = 成功次数 ÷ 总次数（成功 = 响应码正常且空字段率未超阈），两个量都写出来，别只给一个百分比。

② **断档按交易日历判，豁免须留痕** —— 该有却没有 ⇒ 告警；停牌 / 退市 / 尚未上市属已知豁免，豁免须**命中规则**并留痕，且**只标记不删数据**（删了就等于改口径）。

③ **字段漂移双向对账** —— 期望字段集与实际字段集比对，**缺与多都报**（只报「少了什么」会漏掉接口悄悄新增的字段），并附建议的备用源。

④ **体检表逐项落地，两处拦住计算** —— 异常行**不改写**，只加标记；表内标「拦」的两处必须拦住计算并给一句人话原因：

| 体检项 | 判据 | 是否拦计算 |
|---|---|---|
| 缺口 | 相对交易日历缺行 | 不拦，标记 + 计数 |
| 跳空 | 当日开盘 ÷ 前一日收盘 − 1 超出参数阈 | 不拦，标记 |
| 零成交 | 成交量 = 0 且当日非停牌 | 不拦（与缺失区分） |
| 复权对不上 | 复权价与因子复算值相对差 > 1e-6 | **拦** |
| 日期不连续 | 相邻两行间隔 > 1 个交易日 | 标记 |
| 财报口径错位 | 用报告期当披露日 | **拦** |

⑤ **缺口不改写成连续** —— 图上断点、表上空槽 + 原因、导出空单元格、统计分母剔除并报 n/N；四处必须同一份缺口清单（同一份数据在四处各算一遍缺口，迟早四处都不一样）。

对应需求：`FR-RTR-MKT-HEALTH-001` `FR-RTR-MKT-HEALTH-002` `FR-RTR-MKT-HEALTH-003`

### 3.5.7 【契约】成交与净值记账

① **导入如实报数** —— 成功 N 条 / 跳过 M 条（逐条可读原因）/ 去重 K 条，三项齐全；未识别行落清单并可导出回看；同一份文件重复导入不翻倍。

② **只记真实成交与持仓** —— 来源取值只有两类（手工录入 / 券商导出导入），**不设「回测」「模拟」取值**；每笔含 时间 · 标的 · 方向 · 数量 · 价格 · 费用 · 账户，缺任一项即不入账（落未入账清单，不猜、不补零）。

③ **净值口径单点** —— **净值 = 持仓市值 + 现金 − 应计费用**；市值按当日收盘**不复权价 × 当日数量**（除权当日按除权后数量与价格）；费用按 §3.5.9 的费率表逐笔应计。资金进出用**份额法**：单位净值 = 总资产 ÷ 份额，进出当日按「进出金额 ÷ 前一交易日单位净值」调整份额；分红在除权日计入资产，送转在除权日调整数量与成本。同一份数据两次算曲线**逐值一致**。

④ **真值只在本仓** —— 成交与持仓的唯一副本在本仓库内；外部侧（笔记 / 记忆）只留副本或指针，**不得作为记账依据**；每条记录可追录入方式（两取值）；**不存在自动同步通道**（无券商接口客户端）。

⑤ **口径必须换锚** —— 净值曲线的口径组（日/周、费用计入与否、基准）作为一组标识随结果留存；换口径必须换标识并整条重算，不许在同一张曲线上混两种口径。

对应需求：`FR-RTR-MKT-STORE-001` `FR-RTR-MKT-STORE-002` `FR-RTR-MKT-STORE-003` `FR-RTR-MKT-STORE-004`

### 3.5.8 【契约】成交导入、挂点与只读边界

① **差异由模板吸收，不识别的行不丢不猜** —— 字段命名 / 顺序 / 编码差异由逐券商模板吸收，上层只见统一中间格式；新增券商只加模板、不改老模板；无法识别的行落清单并如实报数；同文件重复导入幂等。

② **挂点跟数据走** —— 笔记可挂某根 K 线或某笔成交；挂点标识 = 标的 + 周期 + K 线起始时刻（或成交标识）；换周期按「时段包含关系」重新落点，**找不到对应 K 线时如实提示**，不许静默丢点；笔记随回放推进**到时出现**，不在回放时也能在列表里看全；列表视图与图上标记读同一份数据。

③ **标签可停用，决策指针必填且可回跳** —— 标签预设可改可停用（停用保留历史）、可自定义；每笔调仓必挂决策依据指针（可为多条：数据项 / 文档条号 / 快照名）；**无依据时只能取「无依据」这一个哨兵值**（留空、空串判红）；每条指针必须可回跳，回跳失败判红。

④ **月复盘覆盖全部决策、分类不混** —— 当月调仓集合 − 被复盘集合 = ∅；结论必须落三分类之一：**依据成立而结果差（运气）/ 依据不成立（纪律）/ 结果好而无依据（危险）**，不许只给赚亏；规则修订候选逐条三态表态（采纳 / 不采纳 / 改成某条），不许打包成一条。

⑤ **只读是硬不变量** —— 委托 / 撤单 / 改单 / 资金划转的调用与端点**零命中**，凭据清单里**无交易权限**；出现任何「可交易」通道判红。「不许连交易通道」**不等于**「不许导入」—— 导入只有只读文件与手工录入两条路。

对应需求：`FR-RTR-REV-TRADE-001` `FR-RTR-REV-TRADE-002` `FR-RTR-REV-TRADE-003` `FR-RTR-REV-TRADE-004` `FR-RTR-REV-TRADE-005` `FR-RTR-REV-TRADE-006`

### 3.5.9 【契约】归因指标、曲线与费用口径

① **七件套定义式单点，别处只许引用** —— 每个指标有算式与边界取值；界面上的一个数与导出的同一个数若按两套分母算，两个都不可信。

| 指标 | 算式 | 边界情形 |
|---|---|---|
| 胜率 | 盈利笔数 ÷ 已平仓笔数 | 零交易 ⇒ **不适用**（不是 0） |
| 盈亏比 | 平均盈利额 ÷ 平均亏损额（亏损取绝对值） | 无亏损笔 ⇒ 不适用并报「无亏损笔」 |
| 盈利因子 | 总盈利额 ÷ 总亏损额绝对值 | 同上 |
| 期望值 | 净盈亏合计 ÷ 已平仓笔数（元/笔） | 零交易 ⇒ 不适用 |
| 平均 R 倍数 | Σ(单笔净盈亏 ÷ 该笔初始风险) ÷ 可用笔数；初始风险 = 入场价 − 初始止损价 | 未设止损的笔不进分母，报「可用样本 n/N」 |
| 最大回撤 | 权益曲线逐点 1 − 当前值 ÷ 历史峰值，取最大 | 单点曲线 ⇒ 0 |
| 最大连续盈亏 | 按平仓日排序的最长同号连胜 / 连亏笔数 | 零交易 ⇒ 不适用 |

**恒等式（对不上即判红）**：盈利因子 = 盈亏比 × 胜率 ÷ (1 − 胜率)。这条把三个指标锁在一起 —— 只要分母口径有一处不同，等式立刻破。

② **合计闭合，对比必须同口径** —— 分组统计各组合计 = 总体（笔数与金额都闭合，差额只能来自「未分组 / 无标签」一组且该组显式列出）；权益曲线末值 = 累计净盈亏 = 各笔净盈亏之和；某月日历日盈亏之和 = 该月成交净额汇总；同行 / 板块对比面板一律同区间、同复权、同费用口径，同一份数据两次渲染逐点一致，结论里每个数字可指回库内行。

③ **单笔与费用算法写死** —— 单笔净盈亏 = 卖出净额 − 买入净额；净额 = 成交金额 − 佣金 − 印花税（仅卖出）− 过户费；单笔收益率 = 单笔净盈亏 ÷ 买入净额；输出按公共口径 C（6 位、逢半进位），中间不截断。部分成交按笔配对，配对规则 = **先进先出**，同一标的多笔买入按「时间 + 记录标识」全序。

| 费种 | 计费方式 | 默认值（可配） |
|---|---|---|
| 佣金 | 成交金额 × 费率，双边，单笔不足最低额按最低额 | 0.025%，最低 5 元 |
| 印花税 | 卖出成交金额 × 税率，单边 | 0.05% |
| 过户费 | 成交金额 × 费率，双边 | 0.001% |

默认值必须写在设置项旁并给出依据；计入与不计入两口径可切换对比，各自带口径标识，**同一次统计里不许混**。

④ **检出与提炼都不许凭空** —— 异常检出算式化：高买低卖 = 同标的 30 个交易日内买入价 ≥ 该区间最高收盘 × (1 − 参数)；逆趋势加仓 = 标的 N 日均线向下且持仓浮亏扩大时加仓；超预设仓位 = 单标的市值 ÷ 总资产 > 预设上限。每条输出带**依据的数据行**；命中笔数低于阈值 ⇒ 明说「样本不足」。策略卡片必须标注出处（哪几期周报 / 哪几条日志），可增删改并留历史，可被笔记检索命中；**无出处的卡片判红**。

⑤ **时间轴按交易日，缺数据不近似** —— 非交易日不画点；**无成交日与持平日分开显示**（前者不落点，后者落零值点）；MFE / MAE 需分钟级行情，缺则输出「无法计算」并报缺哪几笔 —— **不许用日线最高最低近似**（两种口径必然给出两个答案，而用户以为是同一个）。

对应需求：`FR-RTR-REV-ATTR-001` `FR-RTR-REV-ATTR-002` `FR-RTR-REV-ATTR-003` `FR-RTR-REV-ATTR-004` `FR-RTR-REV-ATTR-005` `FR-RTR-REV-ATTR-006` `FR-RTR-REV-ATTR-007` `FR-RTR-REV-ATTR-008` `FR-RTR-REV-ATTR-009`

### 3.5.10 【契约】AI 复盘稿

① **结论即指针** —— 每条结论挂成交标识或行情行引用，引用必须是上下文里真有的行；引用为空即「无依据」，**无依据不进结论区**。

② **不造数** —— 稿内每个数字必须能在上下文找到同值；不做镜像推算（「约赚三万」而上下文无此数即违规）；不生成不存在的成交。

③ **两次不相反** —— 同一输入两次产出，按「结论类型 + 引用集合」规范化后比对；出现互斥对（同一笔既判「止损及时」又判「该止损未止损」）即判红。改述允许，**互斥不允许** —— 确定性只要求结论集可比，不要求措辞相同。

④ **只读附注** —— 复盘稿不改成交、不改指标、不覆盖用户标注；稿与记录的关联可回跳，删稿不影响记账与统计。

对应需求：`FR-RTR-REV-AI-001`

### 3.5.11 【契约】复盘检索与报告视图

① **上下文可溯源且有界** —— 每段带来源指针（表 + 行标识 / 文件 + 行号 / 快照名）；只传文本与标识，行数据须显式确认并留痕；体积超限时的截断策略固定（按段优先级 + 每段字符上限），**截断处显式标记**，不许悄悄少给。

② **引用校验与同查询同结果** —— 结论里出现的数字必须能在上下文找到同值，找不到即标「无依据」，**不许当结论输出**；对话与审计记录可回看。区间按交易日**闭区间**，排序全序（时间升序，同一时刻按记录标识升序），两次查询逐行一致。

③ **会话可归档** —— 会话 = 游标位置 + 标注 + 结论 + 引用的输入锚；可命名、可再开、可删；标注与笔记**同一份数据**（不复制）；同一份数据可并存多个会话（不同角度）。

④ **报告视图只读** —— 左列条目与包索引**逐条一致**（不多不少），期号可排序、标题可检索、空库给空态；右区按正文渲染，标题层级 / 表格列数 / 引用 / 列表嵌套与源文一致；视图**不产生任何写回包的动作**；显示设定（字号 / 目录锚点 / 导出）**不改变包内容**。

⑤ **包入库的幂等与降级** —— 同包重复导入不新增条目；导入后离线可读（媒体随包在本机）；失败逐条报告（缺索引 / 媒体缺失 / 编码错）且不写半截；媒体缺失或路径越界 ⇒ 原位占位 + 报告，不白屏、不崩。

对应需求：`FR-RTR-REV-QUERY-001` `FR-RTR-REV-QUERY-002` `FR-RTR-REV-QUERY-003` `FR-RTR-REV-QUERY-004` `FR-RTR-REV-QUERY-005` `FR-RTR-REV-QUERY-006` `FR-RTR-REV-QUERY-007` `FR-RTR-REV-QUERY-008` `FR-RTR-REV-QUERY-009`

### 3.5.12 【契约】时间游标与回放

① **游标是唯一时间源** —— 暴露给图表、指标、规则的数据终点 = 游标日；任何计算读取的行满足**数据日 ≤ 游标日**；推进器只有一个（回放、回测、筛选共用），不许另造第二套。回退到某日再推进回同一日，全部读数逐值一致（**含中间序列，不只末端**）；「隐藏后续」是**真取不到**（数据入口按游标裁剪），不是视觉遮挡。

② **周期切换落点写死** —— 切到更大周期 ⇒ 游标落到「包含当前游标日的该周期最后一根**已完整** K 线的结束交易日」；切回更小周期 ⇒ 落在同一交易日；切换不改已产生的标注与结论，只改可见粒度。

③ **回溯查询与导出** —— 一次查询同时给「客观数据序列 + 我当时写了什么」（跟踪日志与周报观点同屏）；区间按交易日**闭区间**；缺失段**显式标「缺」**，绝不插值、不前值填充；同一查询两次结果一致。导出 CSV 的列名与类型稳定（可被脚本直接消费）、中文不乱码、内容与界面所见一致；档案与周报同样可导出 markdown。

④ **成交驱动回放** —— 时间轴以成交为主轴：时间轴上的成交标记与成交表逐笔对得上（笔数相等 **且** 标识集合相等）；推到某笔**必停**；该笔无对应行情 ⇒ 如实标「该笔无对应行情」且仍可继续推进（不许静默跳过）；日内按分钟线、跨日连成一条轴。

⑤ **对齐与历史情形同一纪律** —— 成交时刻落在**左闭右开**区间 [K 线起始, 下一根起始)，容差可配但只有一处配置；缺该时段行情 ⇒ 报出缺哪些笔（笔数 + 标识）；换周期后同一笔仍给同一答案。历史情形检索：相似度算法与阈值写明，样本量低于阈值标「不足以参考」，输出只描述过去的分布（样本量 / 中位数 / 分位 / 回撤），**不含任何面向未来的陈述与目标价**。

对应需求：`FR-RTR-RSR-SCENARIO-001` `FR-RTR-RSR-SCENARIO-002` `FR-RTR-RSR-SCENARIO-003` `FR-RTR-RSR-SCENARIO-004` `FR-RTR-RSR-SCENARIO-005` `FR-RTR-RSR-SCENARIO-006`

### 3.5.13 【契约】回测引擎：游标、规则与触发

① **未来函数是硬判据** —— 每次计算附「最大数据日」读数，> 游标日即失败；构造依赖未来的用例**必须失败**（负例只增不减）；判据进仓门禁，不设人工放行口。

② **复权切换价量同步** —— 前复权 / 不复权可切换，价格与成交量**同时**换口径（成交量按复权因子同步调整，或明确声明不调整 —— 只能选一种并写进口径标识）；界面标注当前口径；同区间两口径各自可复算。

③ **规则与信号同一求值器** —— 规则集是人类可读文本、可 diff、可单条启停、历史留痕；语法错误与未知字段必须报错到具体位置，**不许把空值当「不成立」糊过去**；规则与自定义信号共用一份求值器与一份字段表。

④ **触发与成交价口径** —— 触发点与规则求值逐步对应（可抽样核到具体交易日）；成交价口径三选一（当日收盘 / 次日开盘 / 指定价）写死并标注，**不许一处收盘一处开盘**；该口径进结果锚。

⑤ **共享时间轴与同口径读数** —— 规则回放与成交驱动回放共用一条时间轴；多标的同步回放一处推进、处处同步，图表同区间同口径，结果可导出对照表；板块联动读数的成员与权重口径写死，且与同行对比复用同一口径；回放上的标签复用笔记挂点与标签存储（不复制第二份）。

对应需求：`FR-RTR-RSR-BACKTEST-001` `FR-RTR-RSR-BACKTEST-002` `FR-RTR-RSR-BACKTEST-003` `FR-RTR-RSR-BACKTEST-004` `FR-RTR-RSR-BACKTEST-005` `FR-RTR-RSR-BACKTEST-006` `FR-RTR-RSR-BACKTEST-007` `FR-RTR-RSR-BACKTEST-008` `FR-RTR-RSR-BACKTEST-009`

### 3.5.14 【契约】特征模型

① **特征 = 算式，四件齐** —— 字段 + 参数 + 时间窗 + **缺失处理**（缺失时该特征取「不成立」还是「不适用」必须写明，二者不得混）。落不成算式的不收录。

② **两次求值逐值一致** —— 布尔阈值比较在**未舍入值**上做；输出处按公共口径 C 舍入一次（在舍入值上比较，边界样本两次会给出两个结论）。

③ **只用求值日及之前的数据** —— 求值日 = 游标日；财报类字段按披露日对齐（同 §3.5.5）。

④ **事后挑参必须标注** —— 参数是在看过结果之后选的，必须标注；样本内与样本外两组读数**同时报**，不许只报样本内（只报一半等于没说）。

对应需求：`FR-RTR-RSR-FEATURE-001`

### 3.5.15 【契约】选股与筛选

① **池与剔除规则显式** —— 股票池、ST / 停牌 / 上市不足 N 日等剔除规则全部可见，并报「剔除数 + 逐类原因」；只报候选数不报剔除数，等于藏了分母。

② **每条候选带命中原因** —— 命中的特征标识 + 命中的数据行 + 该特征当时的值；无原因不进清单。

③ **同条件同结果** —— 排序全序（命中特征数降序 → 命中强度降序 → 标的代码升序）；同条件重跑逐行一致；空结果给空态与原因（池空 / 全被剔除 / 无命中）。

④ **只读游标前数据** —— 命中判定不引用游标日之后的行（同 §3.5.13 ①）。

对应需求：`FR-RTR-RSR-SCREEN-001`

### 3.5.16 【契约】样本统计、回放与验证

① **绩效输出与归因同一套定义式** —— 直接引用 §3.5.9 ①，不另立口径；每个数字可脚本复算到笔；空仓 / 零交易输出「不适用」并说明，不静默为 0。

② **「走牛」是可配算式** —— 示例：自命中日收盘起 N 个交易日内最高收盘价 ÷ 命中日收盘价 − 1 ≥ X%；命中判定**不得引用命中日之后的行**（否则样本自身被污染，回测就只是自我实现）；命中清单可导出（时点 + 标的 + 当时特征值）。

③ **牛股倒推留档** —— 「启动前」时点由用户指定并留档；反扫与筛选回放同口径同判据；每个数字指回数据行。

④ **正负样本同判据同展示** —— 失败案例库与成功样本用同一套判据、同一张表；可检索（形态 / 区间 / 标的）；**只报成功样本判红**。

⑤ **样本外验证与成本逐项可见** —— 按当时可得数据（财报用披露日、指数成分为当时成分）；交易成本、滑点、涨跌停不可成交都计入且逐项列出；样本数低于阈值 ⇒ 结论标「不可靠」、不给单点结论；模式库条目带出处（哪几次回放 / 哪张笔记）与命中统计，历史留痕，与策略卡片同源不重复。

对应需求：`FR-RTR-RSR-SAMPLE-001` `FR-RTR-RSR-SAMPLE-002` `FR-RTR-RSR-SAMPLE-003` `FR-RTR-RSR-SAMPLE-004` `FR-RTR-RSR-SAMPLE-005` `FR-RTR-RSR-SAMPLE-006`

### 3.5.17 【契约】跟踪档案与单篇报告

① **章序固定、数字必有来源** —— 档案与报告的章序是固定清单，缺一节即缺一节（不合并、不省略）；每个数字来自库或快照并带来源，**无来源不出数**。

② **缺字段留显式空槽** —— 写「未取到」并给原因，不省略、不填 0、不用上期值补（补出来的数会被当成当期的数）。

③ **推断显式标注** —— 「为什么动」的每条理由指回数据行或事件；无依据的推断标为推断，**不得写成结论**。

④ **归档幂等且失败可见** —— 同标的同日重跑不产生第二份，命名含日期且可判；归档失败如实报错，不许「渲染成功、归档静默失败」。

对应需求：`FR-RTR-RSR-PROFILE-001` `FR-RTR-RSR-PROFILE-002` `FR-RTR-RSR-PROFILE-003`

### 3.5.18 【契约】周报生成与投递

① **产物是一份周报包，且每篇结构可缺不可乱** —— 目录名 = 期号；三件固定（索引 + 正文 + 媒体目录）；正文内引用一律**相对路径**；索引给元数据最小集（期号、日期范围、标题、标签、生成时间）；媒体白名单固定，白名单外格式**原位占位**并报告一条。每期**固定节恒在**（行情概览 / 关键驱动 / 持仓相关 / 短期关注 / 免责），偶发节按「有没有数据」决定去留；每处数字与事件可指回原始快照或抓取记录；产物带**草稿标记**，人审后才算正式稿。

② **模板可编辑、规则标识稳定** —— 骨架是可编辑的 Markdown + 变量占位；常用字段（主题 / 周期 / 数据范围 / 口径）落结构化表单，不必每次写自然语言；自然语言要求作**逃生口**，必须能表达模板里没有的口径。规则可存多条，**标识稳定**（幂等键用它）。幂等键 = 规则标识 + 周期：同规则同周期重跑**覆盖同一篇**（判据 = 篇数不变 + 正文更新）；固定两枚标签恒在；归属可配（改配置不改代码）；带「自动生成」标记，可按标记过滤与批量清理。

③ **改后不覆盖** —— 被用户编辑过的篇转为用户自己的笔记，自动版下一期**另开新篇**；「是否被编辑过」有可判据的状态，不靠人工回忆；老篇文本不被覆盖、不改写。

④ **只走交换面** —— 落笔记只走对方的导入 / 备份交换面，**不直写对方库**（机检：无对方库写入路径）；落成笔记后**正文与表格都在**（表格不塌成纯文本），共用对方既有存储形态（不另建一套），可被对方的全文检索命中（含中文）。写失败如实报错并**保留周报包**（包是唯一权威产物，视图与笔记都是投影）。

⑤ **生成侧在仓外，缺期只一行** —— 本仓无定时器、无模型端点、无抓取代码、**无对外网络出口**、不持第三方密钥；一次触发（手动按钮或本地定时）⇒ 扫描目录出现新包且期号正确；失败或错过 ⇒ 只生成当期 + 一行缺期记录 + 界面明确提示，不静默、不补历史。

对应需求：`FR-RTR-RSR-REPORT-001` `FR-RTR-RSR-REPORT-002` `FR-RTR-RSR-REPORT-003` `FR-RTR-RSR-REPORT-004` `FR-RTR-RSR-REPORT-005` `FR-RTR-RSR-REPORT-006` `FR-RTR-RSR-REPORT-007` `FR-RTR-RSR-REPORT-008` `FR-RTR-RSR-REPORT-009`
## 3.6 横切非功能契约

横切需求不属于任何单一产品线，但它们决定「整套东西能不能长期跑」。本节把可判定的部分写成契约；`ALL-GATE-RISK`（风险登记）刻意不进契约层，见 11.1。

### 3.6.1 【契约】性能预算与测量点

| # | 不变量 | 可观察判定 |
|---|---|---|
| 1 | 每个预算都有明确的起点与终点，「冷启动」从进程可用到首页可交互，「执行」从确认到首屏行渲染 | 计时口径写进回归脚本，两端同一口径 |
| 2 | 结果集超过行数上限必须截断并明示，不得静默截断也不得取全量 | 超上限时界面出现「已截断，共 N 行」提示，两端文本一致 |
| 3 | 大结果流的解码与渲染不得阻塞交互 | 滚动 1 万行 × 20 列期间输入与滚动响应连续 |
| 4 | 元数据单层加载有超时上限，超时表现为「未加载 + 可重试」而非空对象树 | 超时后对象树显示可重试状态 |
| 5 | 连接超时可配置，默认值一致 | 两端默认值相同，配置项名称与语义相同 |

对应需求：`NFR-ALL-GATE-PERF-001` `NFR-ALL-GATE-PERF-002` `NFR-ALL-GATE-PERF-003` `NFR-ALL-GATE-PERF-004` `NFR-ALL-GATE-PERF-005` `NFR-ALL-GATE-PERF-006`

### 3.6.2 【契约】可靠性：失败面不扩散

| # | 不变量 | 可观察判定 |
|---|---|---|
| 1 | 任何语句错误都不导致进程崩溃，也不丢已保存数据 | 故障注入后进程存活、重开数据完整 |
| 2 | 一次失败不污染连接：同一连接可继续执行下一条 | 失败后连跑三条语句均返回正常结果 |
| 3 | 配置文件写入原子化，断电不留半截文件 | 写入中断后文件要么旧内容要么新内容 |
| 4 | 配置损坏时给出可读错误并可恢复，不静默清空 | 人为破坏配置后启动提示具体损坏项 |
| 5 | 异步回调不得引用已关闭的视图 | 关闭页签后迟到的结果被丢弃，无越界 |

对应需求：`AC-ALL-GATE-REL-01` `AC-ALL-GATE-REL-02` `AC-ALL-GATE-REL-03` `AC-ALL-GATE-REL-04` `AC-ALL-GATE-REL-05` `AC-ALL-GATE-REL-06` `AC-ALL-GATE-REL-07` `AC-ALL-GATE-REL-08` `NFR-ALL-GATE-REL-001` `NFR-ALL-GATE-REL-002` `NFR-ALL-GATE-REL-003` `NFR-ALL-GATE-REL-004` `NFR-ALL-GATE-REL-005`

### 3.6.3 【契约】安全与隐私边界

| # | 不变量 | 可观察判定 |
|---|---|---|
| 1 | 连接密码不写入配置文件，发布形态进系统凭据存储 | 配置文件全文检索无密码原文 |
| 2 | 删除连接时同步清除凭据 | 删除后凭据存储中无对应条目 |
| 3 | 默认零外发；仅在显式开启并授权后按最小必要外发 | 关闭智能体后外发流量为 0（日志或抓包） |
| 4 | 所有离机请求进统一外发日志，可审计 | 每次外发在日志中有且仅有一条记录 |
| 5 | 权限最小化：只申请必要的网络与用户选择文件读写 | 权限声明逐条能对应到功能 |
| 6 | 结果集行数据永不外发，除非用户逐次显式确认 | 未确认时外发内容中无行数据 |

对应需求：`NFR-ALL-GATE-SEC-001` `NFR-ALL-GATE-SEC-002` `NFR-ALL-GATE-SEC-003` `NFR-ALL-GATE-SEC-004` `NFR-ALL-GATE-SEC-005` `NFR-ALL-GATE-SEC-006` `NFR-ALL-GATE-SEC-007` `NFR-ALL-GATE-SEC-008`

### 3.6.4 【契约】兼容性与可维护性

| # | 不变量 | 可观察判定 |
|---|---|---|
| 1 | 支持的系统与硬件组合逐格登记「验过 / 未验」，不留空 | 兼容矩阵无空格 |
| 2 | 新增数据库类型不改界面层代码 | 新增类型时界面层零改动 |
| 3 | 关键行为有脚本化回归，回归可一键跑完 | 回归脚本单入口、退出码可判 |
| 4 | 注释写「为什么」，README 与实现同步（含未实现清单） | README 清单与代码逐项对应 |
| 5 | 每条需求可追溯到实现位置与验证方式 | 追溯表条目数 = 需求条目数 |

对应需求：`NFR-ALL-GATE-COMP-001` `NFR-ALL-GATE-COMP-002` `NFR-ALL-GATE-COMP-003` `NFR-ALL-GATE-COMP-004` `NFR-ALL-GATE-COMP-005` `NFR-ALL-GATE-MAINT-001` `NFR-ALL-GATE-MAINT-002` `NFR-ALL-GATE-MAINT-003` `NFR-ALL-GATE-MAINT-004` `NFR-ALL-GATE-MAINT-005` `NFR-ALL-GATE-MAINT-006`

### 3.6.5 【契约】易用性与处置口径

| # | 不变量 | 可观察判定 |
|---|---|---|
| 1 | 常用操作有快捷键，且与菜单项文案一一对应 | 菜单能搜到该命令，快捷键唯一 |
| 2 | 错误文案说清「哪里错、怎么办」，中文人话，不暴露内部标识 | 错误提示中无表名、类名、堆栈 |
| 3 | 长任务有进行中状态与可取消入口 | 进行中可见、可取消，取消后状态回写 |
| 4 | 走不动的动作必须挑一种处置并写出来（禁用 / 明示未实现 / 失败态 / 降级），不许无反应 | 每个不可用入口都有明确反馈，四种处置之一 |

对应需求：`NFR-ALL-GATE-UI-001` `NFR-ALL-GATE-USE-001` `NFR-ALL-GATE-USE-002` `NFR-ALL-GATE-USE-003` `NFR-ALL-GATE-USE-004` `NFR-ALL-GATE-USE-005`

### 3.6.6 【契约】本地化

| # | 不变量 | 可观察判定 |
|---|---|---|
| 1 | 界面语言可切换，选择持久化，重启后保持 | 切换后重启仍为该语言 |
| 2 | 文案不硬编码在视图里，以键引用 | 抽样检索视图中无界面文案字面量 |
| 3 | 缺键回退默认语言并落日志，不显示键名 | 人为删键后界面显示默认语言文案 |

对应需求：`NFR-ALL-GATE-LANG-01` `NFR-ALL-GATE-LANG-02` `NFR-ALL-GATE-LANG-03`

### 3.6.7 【契约】智能体使用边界

| # | 不变量 | 可观察判定 |
|---|---|---|
| 1 | 无模型 / 未授权 / 断网时，客户端全部既有功能完整可用 | 断网与未配置模型下主流程不受影响 |
| 2 | 每次调用留可审计记录（模型、请求摘要、耗时、状态），不含密钥 | 日志可导出，检索无密钥 |
| 3 | 有 token 与调用次数上限，超限即终止并提示 | 超限后不再发起请求，界面提示明确 |
| 4 | 产出以文本形式可查看、可编辑、可 diff，无黑箱自动执行 | 产出先呈现差异，用户确认后才落盘 |
| 5 | 长会话可续跑：压缩或检查点后能接着跑，且上下文口径可解释 | 续跑后不重复已完成的步骤 |
| 6 | 支持本地端点，不强制云端 | 指向本地端点时可完整使用 |

对应需求：`AC-ALL-GATE-AI-01` `AC-ALL-GATE-AI-02` `AC-ALL-GATE-AI-03` `AC-ALL-GATE-AI-04` `NFR-ALL-GATE-AI-001` `NFR-ALL-GATE-AI-002` `NFR-ALL-GATE-AI-003` `NFR-ALL-GATE-AI-004` `NFR-ALL-GATE-AI-005` `NFR-ALL-GATE-AI-006` `NFR-ALL-GATE-AI-007` `NFR-ALL-GATE-AI-008`

# 第四章 平台差异

**权威登记表在《需求规格说明书》§9.2（`P-01`~`P-27`），与下表一一对应**；对账判据 = `Scripts/check-p-parity.py`（两侧编号集合必须互相覆盖、同号必须同物）。

每条差异写两件事：**必须一致**（换端必须一样的行为）与**允许不同**（各端各自的实现）。没有「必须一致」那一列的差异不是差异，是缺陷。

## 4.1 差异登记表

| 编号 | 领域 | 必须一致 | 允许不同（各端做法） |
|---|---|---|---|
| P-01 | GUI 框架与控件 | 信息架构（活动栏 / 侧栏 / 编辑器区 / 下方面板）、交互语义、快捷键语义、空·载入·失败三态；**终端配色 = 同一套色值（hex）与同一套对比度 / 可区分性门槛**（权威来源 `Docs/design/terminal-palette.json`，人读版 `Docs/design/终端配色方案.md`，两者由 `Scripts/check-terminal-palette.py` 与代码钉在一起） | 控件树、绘制方式、主题跟随系统的方式 |
| P-02 | 凭据存储 | 密码不落配置文件、重启后可恢复、可被明确清除、不进错误信息 | 钥匙串（macOS）/ Windows 凭据管理器（`keyring` / windows-rs）/ Secret Service / 文件 + 权限 |
| P-03 | 用户选定目录的持久授权 | 授权由用户选择产生、可跨启动恢复、失效给可读提示与补救动作 | security-scoped bookmark（macOS）/ 直接路径（Windows · Linux 无沙箱） |
| P-04 | 外部程序调用（`pg_dump` / `pg_restore` / `ssh`） | 若实现：走审批 + 审计 + 可读错误；不做则明确不呈现入口 | 进程调用方式；**macOS 沙箱构建下不可用**（T-38） |
| P-05 | 内嵌终端 | 概要设计 §3.3.7 的全部屏幕语义与按键字节序列一致 | PTY 获取方式、终端视图绘制 |
| P-06 | 菜单 / 快捷键承载 | 功能可被发现、快捷键语义一致、语言切换后菜单跟随 | 系统菜单栏 / 应用内菜单、修饰键映射 |
| P-07 | 字体与输入法 | 等宽渲染、中日韩宽字符占两格、IME 组字不丢字 | 字体选择、输入法框架 |
| P-08 | 打包与分发 | 版本号与许可证一致、第三方声明齐备、构建可复现；**应用图标同一品牌图形、同一图标名** | `.app` + 公证（macOS）、Tauri bundler（MSI / NSIS）+ 便携形态（Windows，§9.2.1）、deb·rpm·AppImage（Linux 自用第三端） |
| P-09 | 剪贴板与拖放 | 复制语义一致（表格 TSV、多格式导出） | 剪贴板 API、剪贴板格式协商 |
| P-10 | 自动更新 | 不强制、可关闭、更新前提示 | 更新机制（可暂不实现） |
| P-11 | 沙箱 / 权限模型 | 最小权限原则；被拒时给可读原因而非静默失败 | macOS 沙箱 / Windows · Linux 无沙箱或平铺 |
| P-12 | 系统级集成（通知 / Dock / 托盘） | 不打扰用户、可关闭 | 各平台机制 |
| P-13 | 配置与数据目录 | 配置 / 归档 / 书签等文件**逻辑分区一致**（连接配置、保存的查询、查询归档、任务定义、审计日志、工作区书签各占一个文件）；删除连接必须同时清掉磁盘配置与凭据；损坏时给可读错误并保留原文件 | 目录位置（应用支持目录 / 沙箱容器 / XDG）、权限模型 |
| P-14 | 内嵌浏览器 | 行为契约一致：默认不加载远程内容、导航由用户显式发起、出网全部进统一外发日志、独立数据存储（不共享 SQL 客户端凭据与 Cookie）、下载走授权目录、页面脚本不得触达客户端能力；**两侧按同一套契约实现**（`BrowserPage` 地址·历史·加载态 / `BrowserNavigationPolicy` **默认不加载远程内容** / 统一外发日志 `NFR-ALL-GATE-SEC-008`，三件同名同义） | 渲染引擎（macOS = 系统 WebKit·`WKWebView`；Windows = Tauri 2 内置系统 `WebView2`，见 `P-26`）、Cookie 存储位置、权限提示方式 |
| P-15 | 笔记存储引擎（`FR-STD-ALL-PLUG-008`） | **同一套表结构与语义**：`note` / `note_tag` / `note_timeline` / `note_attachment` + 全文索引；**WAL + 事务**、`PRAGMA user_version` 记 schema 版本、幂等升级；`NULL ≠ 空串`；**附件永不进 BLOB**（库里只存路径）；**迁移一次性且旧文件留档**（`*.migrated`，绝不覆盖已有备份）；**备份 = 单文件快照**（`VACUUM INTO`，写完读回核对），**不把活跃库文件直接交给云同步**；中文检索需 **trigram 分词器 + 查询串 ≥3 字**（<3 字按子串兜底并如实标注）；**检索必须覆盖标题 / 正文 / 标签三个字段**，且**所走路线（全文 / 子串兜底）与「检索没跑成」都要如实报告给用户**（不许把「没跑成」显示成「没找到」，「没跑成」与「没找到」是两回事） | 引擎**接入方式**（vendored `sqlite3.c` + 各端薄封装、快照落点、WAL 侧车管理） |
| P-16 | 多库驱动（FR-STD-DB-DRV-010 / 08） | §3.2.8 的六条不变量（协议与方言分离 / 影响行数问服务端 / 取消只断语句 / 同族方言共享文本 / 能力缺失如实说） | 线协议实现选型与版本、认证插件支持面（TLS / `caching_sha2_password`）、驱动对空结果集的列定义可见性 |
| P-25 | SSH 隧道（FR-STD-DB-CONN-020；**原 P-15**，2026-09-27 让号） | §3.2.7 的十条不变量（改写只作用于副本 / 只监听回环 / 按连接缓存与收场 / 不动用户 SSH 状态 / 口令分开存） | 可用的 `ssh` 二进制位置（`DOYAH_SSH_BINARY` 可覆盖）、沙箱下的子进程可见性 |
| P-17 | 终端仿真与 PTY（ConPTY / `pwsh`） | §3.3.7 的全部屏幕语义与按键字节序列（与 `P-05` 同一契约，不另立一套） | PTY 获取方式（Windows = ConPTY，`CreatePseudoConsole`，Windows 10 1809+；Tauri 2 / Rust 侧走 `portable-pty`）；外部程序不经 shell 拼接 |
| P-18 | 目录授权与沙箱模型（NTFS + 自选目录，无沙箱） | 授权由用户选择产生、可跨启动恢复、失效给可读提示与补救动作（与 `P-03` 同一契约）；**未授权目录的读写必须失败且给出可读原因**（等价验收点）；最小权限原则（`P-11`） | 用户自选目录 + NTFS 权限（Windows 无沙箱等价物） |
| P-19 | 菜单与快捷键宿主约定 | 功能可被发现、快捷键语义一致、语言切换后菜单跟随（与 `P-06` 同一契约） | 应用内菜单（Tauri 2 窗口内的前端菜单）、修饰键映射按 Windows 宿主约定 |
| P-20 | 字体回退与输入法 | 等宽渲染、中日韩宽字符占两格、IME 组字不丢字（与 `P-07` 同一契约） | 系统默认 UI 字体、输入法框架（IME） |
| P-21 | 安装 / 签名 / 更新 | 版本号与许可证一致、第三方声明齐备、构建可复现；**首版不做自动更新**（与 macOS 侧一致） | Tauri bundler 产出（MSI / NSIS）+ 便携形态；`signtool` + 代码签名证书（EV / OV） |
| P-22 | 通知与深色模式跟随 | 不打扰用户、可关闭（与 `P-12` 同一契约） | Windows 通知中心；深色跟随系统设置（`AppsUseLightTheme`） |
| P-23 | 窗口与停靠行为 | **本节无独立契约节**：不新增约束，沿用 `P-01` 的信息架构与空 / 载入 / 失败三态 | 窗口与停靠行为按 Windows 宿主约定（Tauri 2 窗口） |
| P-24 | 剪贴板大对象通道（临时文件 + `FileDrop`） | 复制语义一致（表格 TSV、多格式导出）（与 `P-09` 同一契约） | 系统剪贴板 API（Tauri 2 / WebView 宿主）；超阈值改走「临时文件 + `FileDrop`」 |
| P-26 | 系统 WebView 运行时依赖 | 装得上、跑得起来；**缺运行时时给可读提示与补救指引**（不静默失败）；第三方声明与许可证齐备（与 `P-08` / `P-21` 同一契约）；**页面不得触达客户端能力**（与 `P-14` 同一契约） | macOS = 系统 WebKit（`WKWebView`，无额外运行时）；Windows = **WebView2 运行时**（Tauri 2 依赖：随产物引导安装或首启给提示）；Linux 自用第三端 = 由**本端选定（2026-10-14 令：本仓口径作废）** |
| P-27 | 结果集网格的虚拟化方案 | §3.2.12 的结果区客户端视图契约（筛选 / 排序 / 分页 / 选中语义）与 `NFR-ALL-GATE-PERF-002` / `NFR-ALL-GATE-PERF-003` 的**同一档行数量级**口径；**基准数字不跨实现沿用**（换实现必须重测并登记） | 网格控件的虚拟化机制（Windows = Tauri 2 前端虚拟表格 / 虚拟滚动，候选 TanStack Virtual 自绘；macOS 侧走 `Table` 的行复用）、基准的**测量口径与数值**（各形态各自负责，见 §9.2.6-3 与 §8.1） |


## 4.2 差异的判定

1. 去掉这个差异，会不会让某一端违反平台规范（审核、沙箱、键位、后台策略）？会 → 差异成立。
2. 这个差异会不会让用户在两端看到不同的**数据**？会 → 不是差异，是缺陷，回到第三章。
3. 差异是否登记在表里？没登记的「偷偷不同」，验收时按缺陷处理。

新增差异的规矩：先在《需求规格说明书》§9.2 立号（`P-28` 起），再回本书登记，最后补 `check-p-parity` 的覆盖面 —— 顺序反了会出现「书里有、需求里没有」的孤号。

# 第五章 数据结构设计

> 阅读约定：本章与下一章「依据」列里的路径按仓库实际布局书写，路径片段本身不表示某节只适用于某一端；凡写「待定」的条目，是代码中确实不存在的事实，不是留白。

本产品的数据分三类载体：**一个 SQLite 库**（笔记 / 待办 / 提醒 / 查询历史）、**应用数据目录下的 JSON 与 JSONL 文件**（连接档、智能体配置、会话、记忆、审计与外发留痕）、**系统凭据存储**（口令与令牌）。三类载体的分工是硬的：凡需事务与联表查询的进库，凡「一行一条、只追加」的进 JSONL，凡秘密只进凭据存储且类型层面不留配置文件字段。

本章所有表名、列名、键名、文件名均取自代码；代码里没有的事实一律写「待定」，并在 5.7 汇总。

## 5.1 逻辑结构

### 5.1.1 实体清单

| 实体 | 载体 | 主键 / 身份 | 归属维度 | 生命周期 | 依据 |
| --- | --- | --- | --- | --- | --- |
| `ConnectionConfig` | `connections.json` | `id`（UUID） | 全局 | 用户增删改 | `Core/ConnectionConfig.swift` |
| `SSHTunnelConfig` | 内嵌于 `ConnectionConfig` | 随宿主 | 随宿主 | 随宿主 | `Core/SSHTunnel.swift` |
| `Note` | `notes.sqlite3` / `note` | `id`（UUID，列 `uuid`，UNIQUE） | `notebook_uid` | 墓碑（`deleted_at`），不物理删 | `Plugins/Notes/Sources/Note.swift`、`NoteStorage/NoteDatabase.swift` |
| `Shelf` / `Notebook` | `shelf` / `notebook` | `uid`（TEXT，UNIQUE） | `notebook.shelf_uid` | 删除有处置策略 | `NoteStorage/NoteDatabase.swift` |
| `NoteAttachment` | `note_attachment` | `id`（UUID，列 `uuid`） | `note_id` | 随笔记级联删 | 同上 |
| `NoteTimelineEntry` | `note_timeline` | 自增 `id` | `note_id` | 只增不改 | 同上 |
| `Todo` | `todo` | `id`（UUID，列 `uuid`） | 无（清单即事实源） | 物理删 | `Core/Todo.swift` |
| `Reminder` | `reminder` | `id`（UUID，列 `uuid`） | `note_id` 或 `todo_id`（恰一非空） | 随归属级联删 | `Core/Reminder.swift` |
| `QueryHistory` | `query_history` | `id`（UUID，列 `id` TEXT） | `connection_id` | 500 条 / 90 天裁剪 | `Core/QueryHistoryStore.swift` |
| `AgentConfiguration` / `AgentProfile` | `agent.json` | `profiles[].id` | 全局 | 用户改 | `Core/AgentConfiguration.swift` |
| `AgentSessionHeader` / `AgentSessionTurn` | `agent-sessions/<id>.jsonl` | `id`（会话）/ 行序 | `workspace` | 一会话一文件 | `Core/AgentSession.swift` |
| `AgentMemoryEntry` | `agent-memory/<ws>.jsonl` | `id` | `workspace` + `connection` | 上限挤出 | `Core/AgentMemory.swift` |
| `AgentCheckpoint` | `agent-checkpoints.jsonl` | `sessionID` + `stepIndex` | `sessionID` | 追加，取最后可用 | `Core/AgentCheckpoint.swift` |
| `AgentScheduleEntry` / `AgentScheduleRunRecord` | `agent-schedules.json` / `agent-schedule-runs.jsonl` | `id` / `entryID` | 全局 / 条目 | 删条目连带删历史 | `Core/AgentScheduleStore.swift` |
| `AgentActionRecord` | `agent-audit.jsonl` | `id` | 全局（含 `sessionID`/`chainID`） | 手动清空 | `Core/AgentAudit.swift` |
| `EgressEntry` | `egress-log.jsonl` | `id` | 全局（含 `tabID`） | 可查看/导出/清空 | `Core/EgressLog.swift` |
| `MCPClientServerConfig` | `mcp-servers.json` | `name`（配置内唯一） | 全局 | 用户改 | `Core/MCPClientConfiguration.swift` |
| `MCPApprovalRequest` / `MCPApprovalDecision` | `mcp-approvals/pending.jsonl`、`decisions.jsonl` | `id` / `requestID` | 全局 | 追加 | `Core/MCPApprovalQueue.swift` |
| `WorkspaceHistoryEntry` | `workspace-history.json` | `id == path` | 全局 | 最近打开 | `Core/WorkspaceHistory.swift` |
| `SavedQuery` | `saved-queries.json` | `id` | `connectionID`（可空） | 用户增删 | `Core/SavedQueryStore.swift` |
| `SQLArchiveEntry` | `<归档根>/queries/YYYY-MM-DD.sql` | `(规范化 SQL, 连接, 库)` | 按天 | 长期保留 | `Core/SQLArchive.swift`、`Core/ArchiveLocation.swift` |

### 5.1.2 连接与隧道

| 字段 | 类型 | 约束 | 依据 |
| --- | --- | --- | --- |
| `id` | `UUID` | 必填，主键 | `Core/ConnectionConfig.swift` |
| `name` | `String` | 去空白后非空（`isValid`） | 同上 |
| `dbType` | `DatabaseType` | `postgresql` / `mysql` / `gbase8a`；缺省 `postgresql` | `Core/DatabaseType.swift` |
| `host` | `String` | 去空白后非空 | `Core/ConnectionConfig.swift` |
| `port` | `Int` | `1...65535`；缺省取 `dbType.defaultPort` | 同上 |
| `database` | `String` | 可空串 | 同上 |
| `username` | `String` | 去空白后非空 | 同上 |
| `sslMode` | `SSLMode` | 缺省取 `dbType.defaultSSLMode` | 同上 |
| `timeout` | `Int` | `> 0`，缺省 `5` | 同上 |
| `schemaVersion` | `Int` | 当前 `1`；缺键解码为 `0` | 同上、`ConnectionConfigMigration.swift` |
| `environment` | `ConnectionEnvironment?` | `nil` = 未标注，不塞默认值 | 同上 |
| `colorTag` | `CategoricalTone?` | 语义色优先 | 同上 |
| `isReadOnly` | `Bool` | 缺省 `false`；客户端拒执行写语句 | 同上 |
| `startupSQL` | `String?` | 连接后逐条执行，空串与纯注释不计 | 同上 |
| `group` | `String?` | 去空白后为空视为未分组 | 同上 |
| `sshTunnel` | `SSHTunnelConfig?` | `nil` = 直连 | `Core/SSHTunnel.swift` |

`SSHTunnelConfig`：`isEnabled`、`host`、`port`（缺省 22）、`username`、`authentication`（`password` / `privateKey(path:isEncrypted:)` / `agent`）、`hostKeyPolicy`（`acceptNew` / `strict`）、`connectTimeoutSeconds`（缺省 15）。口令与私钥口令**不在本结构内**，见 5.2.3。

### 5.1.3 笔记、待办、提醒、历史

| 实体 | 字段 | 说明 | 依据 |
| --- | --- | --- | --- |
| `Note` | `id` `title` `body` `tags` `source` `createdAt` `updatedAt` `containsRowData` `isFavorite` `isPinned` | 模型层不含 `spans`；正文权威源经 `setNoteSpans(_:body:id:)` / `noteSpans(id:)` 单独读写 | `Plugins/Notes/Sources/Note.swift` |
| `NoteSource` | `kind` `connectionName` `fingerprint` `capturedAt` | `kind` 认不出即抛 `unknownSourceKind` | 同上 |
| `Todo` | `id` `title` `note` `dueAt` `done` `completedAt` `priority` `tags` `createdAt` `updatedAt` | `done` 与 `dueAt` 互不覆盖；`priority` 认不出归 `.normal` | `Core/Todo.swift` |
| `ReminderSpec` | `rule` `anchorDate` `minuteOfDay` `intervalCount` `intervalUnit` `weekdays` `untilDate` | `weekdays` 存归一文本（`1,3,5`） | `Core/Reminder.swift` |
| `QueryHistory` | `id` `connectionID` `sql` `executedAt` `duration` `succeeded` | 按 `id` 覆盖写 | `Core/ConnectionConfig.swift`、`QueryHistoryStore.swift` |

三条跨字段口径必须写在这里，否则实现会各按各的理解落库：

- **完成态与截止时间互不覆盖**：`done` 只由 `setDone` 改，`dueAt` 原值保留，重开后「逾期」仍按原截止时间判（`Core/Todo.swift`）。
- **组织类操作不刷新更新时间**：收藏、置顶、跨笔记本移动只改自己那一列，不碰 `updated_at`（`NoteDatabase.setFavorite` / `setPinned` / `move(noteIDs:toNotebook:)`）。
- **清单是唯一事实源**：待办没有「日历任务」这类第二份数据，日历侧是本类型的投影（`Core/Todo.swift` 文件头第三条）。

### 5.1.4 智能体域

| 实体 | 关键字段 | 约束 | 依据 |
| --- | --- | --- | --- |
| `AgentProfile` | `id` `name` `presetID` `endpoint` `model` `timeoutSeconds` `secretKey` `pricing` | `secretKey` 只存凭据条目键名，不存密钥 | `Core/AgentConfiguration.swift` |
| `AgentConfiguration` | `isEnabled` `profiles` `activeProfileID` `scopeMode` `quota` `guardPolicy` | 无 `apiKey` 字段（类型层面不留） | 同上 |
| `AgentSessionTurn` | `kind` `role` `text` `at` `toolName` `toolCallID` `approval` | 不承载结果集行数据 | `Core/AgentSession.swift` |
| `AgentMemoryEntry` | `id` `workspace` `connection` `kind` `note` `fingerprint` `firstSeenAt` `lastUsedAt` `useCount` | 键白名单 `keyWhitelist`；条数与字数有上限 | `Core/AgentMemory.swift` |
| `AgentCheckpoint` | `sessionID` `stepIndex` `completedSteps` `pendingMessagesDigest` `at` | 键白名单；只存摘要不存结果 | `Core/AgentCheckpoint.swift` |
| `AgentScheduleEntry` | `id` `target{kind,title,prompt,workspace}` `schedule` `isEnabled` `createdAt` `updatedAt` | `updatedAt` 由 store 统一改写 | `Core/AgentSchedule.swift`、`AgentScheduleStore.swift` |
| `AgentScheduleRunRecord` | `id` `entryID` `plannedAt` `startedAt` `finishedAt` `status` `executedActions` `withheldActions` `detail` | `failed` 无 `detail` ⇒ 抛错且不落盘 | 同上 |
| `AgentActionRecord` | `id` `timestamp` `connectionName` `database` `model` `sql` `statementKind` `risk` `findings` `outcome` `origin` `durationMilliseconds` `endpoint` `promptTokens` `completionTokens` `totalTokens` `sessionID` `hopIndex` `chainID` | `origin` 缺字段按 `action` | `Core/AgentAudit.swift` |

### 5.1.5 工作台域

| 实体 | 字段 | 约束 | 依据 |
| --- | --- | --- | --- |
| `WorkspaceHistoryEntry` | `path`（即 `id`）+ 显示名 | 两个数组：`files` / `workspaces` | `Core/WorkspaceHistory.swift` |
| `SavedQuery` | `id` `name` `connectionID` `database` `sql` `savedAt` | `connectionID` / `database` 可空 | `Core/SavedQueryStore.swift` |
| `SQLArchiveEntry` | `sql` `firstExecutedAt` `lastExecutedAt` `runCount` `connection` `database` `durationSeconds` `affectedRows` `succeeded` `note` | 时间截到整秒；说明字段转义换行 | `Core/SQLArchive.swift` |
| `MCPClientServerConfig` | `name` `transport` `command` `args` `env` `url` `headers` `enabled` `timeoutSeconds` `tools` | 缺项用默认值，不整条失败 | `Core/MCPClientConfiguration.swift` |
| `EgressEntry` | `id` `timestamp` `kind` `target` `origin` `outcome` `detail` `tabID` `tabTitle` | `target` 去 query/fragment；`detail` 不含密钥 | `Core/EgressLog.swift` |

## 5.2 物理结构

### 5.2.1 SQLite 库

库文件 `notes.sqlite3`，位于「应用数据根 / `DoyahNotes`」，可用环境变量 `DOYAH_NOTES_DIR` 整体覆盖（`Plugins/Notes/Sources/Note.swift`）。连接参数三条：`journal_mode = WAL`、`foreign_keys = ON`、`synchronous = NORMAL`；打开即幂等升到最新版（`NoteStorage/NoteDatabase.swift`）。

| 表 / 虚拟表 | 引入版本 | 列与关键约束 | 索引 / 触发器 | 依据 |
| --- | --- | --- | --- | --- |
| `note` | v1 | `id INTEGER PRIMARY KEY`、`uuid TEXT NOT NULL UNIQUE`、`title`、`body DEFAULT ''`、`source_kind`、`source_connection_name`、`source_fingerprint`、`source_captured_at REAL`、`created_at REAL`、`updated_at REAL`、`contains_row_data`（0/1 CHECK）、`storage_version`；v2 加 `notebook_uid TEXT`（无外键）；v3 加 `favorite`、v4 加 `pinned`（均 `NOT NULL DEFAULT 0` + CHECK）；v8 加 `spans TEXT`；v10 加 `deleted_at REAL` | `note_updated_at_index(updated_at DESC)`、`note_source_kind_index`、`note_notebook_index` | 同上 |
| `note_tag` | v1 | `note_id REFERENCES note(id) ON DELETE CASCADE`、`tag`，`PRIMARY KEY (note_id, tag)` | `note_tag_tag_index(tag)` | 同上 |
| `note_timeline` | v1 | `id`、`note_id` 级联、`at REAL`、`kind`、`detail` | `note_timeline_note_index(note_id, at)` | 同上 |
| `note_attachment` | v1 | `id`、`uuid UNIQUE`、`note_id` 级联、`path`、`byte_count`、`added_at` | `note_attachment_note_index(note_id)` | 同上 |
| `note_fts` | v1 | FTS5 外部内容表：`content='note'`、`content_rowid='id'`、`tokenize='trigram'` | 三个触发器 `note_fts_after_insert/delete/update` | 同上 |
| `shelf` | v2 | `id`、`uid UNIQUE`、`name`、`sort_order`、`created_at`、`is_default` CHECK | — | 同上 |
| `notebook` | v2 | `id`、`uid UNIQUE`、`shelf_uid REFERENCES shelf(uid) ON DELETE CASCADE`、`name`、`sort_order`、`created_at`、`is_default` CHECK | `notebook_shelf_index(shelf_uid, sort_order)` | 同上 |
| `todo` | v5 | `id`、`uuid UNIQUE`、`title DEFAULT ''`、`due_at REAL`、`done`（0/1 CHECK）、`completed_at REAL`、`priority DEFAULT 'normal'`（无 CHECK）、`created_at`、`updated_at`；v9 加 `note TEXT NOT NULL DEFAULT ''` | — | 同上 |
| `todo_tag` | v5 | `todo_id` 级联、`tag`，`PRIMARY KEY (todo_id, tag)` | `todo_tag_tag_index(tag)` | 同上 |
| `reminder` | v6 | `id`、`uuid UNIQUE`、`note_id` / `todo_id` 双可空且均级联、`rule`、`anchor_date`、`minute_of_day DEFAULT -1`、`interval_count`、`interval_unit`、`weekdays`、`until_date`、`created_at`、`updated_at`、`CHECK ((note_id IS NULL) <> (todo_id IS NULL))` | `reminder_note_index`、`reminder_todo_index` | 同上 |
| `query_history` | v7 | `id TEXT PRIMARY KEY`、`connection_id TEXT`、`sql TEXT`、`executed_at REAL`、`duration REAL`、`succeeded`（0/1 CHECK） | 不建索引（上限即规模） | 同上 |

时间列一律存 `REAL`（`timeIntervalSince1970`），不存 ISO8601 字符串；`NULL` 与空串不作同义处理（`source_connection_name` 为 NULL 表示「没有来源」）。

三条与并发和一致性有关的物理事实：

- **一次写成一个事务**：笔记的本体 + 标签 + 时间线在一个事务里落库，任务的标签与本体同理；删容器时「改挂笔记」与「删容器」也在同一事务，避免留下「笔记还挂着一个已不存在的笔记本」的中间态。
- **不读 `last_insert_rowid()`**：写入后按 `uuid` 反查 `rowid`。走更新分支时那个值可能是上一句留下的，会静默指向另一条记录且没有任何症状。
- **绑定变量分块**：`uuid IN (…)` 的占位符按 500 个一块切开，不假定用户数据量小；分块大小是这一层唯一的常量。

### 5.2.2 文件与目录布局

应用数据根 = `~/Library/Application Support/DoyahStudio`（`DoyahIdentity.applicationSupportDirectoryName`）；笔记数据家与之**平级**，为 `~/Library/Application Support/DoyahNotes`。

| 路径（相对数据根） | 形态 | 写入方式 | 依据 |
| --- | --- | --- | --- |
| `connections.json` | JSON 数组 | 全量重写，`prettyPrinted` + `sortedKeys`，atomic | `Core/ConnectionStore.swift` |
| `agent.json` | JSON 对象 | 全量重写，atomic | `Core/AgentConfigurationStore.swift` |
| `agent-schedules.json` | JSON 数组 | 全量重写，atomic | `Core/AgentScheduleStore.swift` |
| `agent-schedule-runs.jsonl` | JSONL | 追加；终态收尾重写整份 | 同上 |
| `agent-sessions/<id>.jsonl` | JSONL（首行 header） | 首行建会话，其余追加 | `Core/AgentSession.swift` |
| `agent-memory/<ws>.jsonl` | JSONL（首行 header） | 删除/挤出走「重读→改→原子整写」 | `Core/AgentMemory.swift` |
| `agent-memory/<ws>.index.json` | JSON | 派生缓存，可重建 | 同上 |
| `agent-checkpoints.jsonl` | JSONL | 追加；坏行跳过并计数 | `Core/AgentCheckpoint.swift` |
| `agent-audit.jsonl` | JSONL | 追加；可导出 JSON / CSV、可清空 | `Core/AgentAudit.swift` |
| `egress-log.jsonl` | JSONL | 追加；目录可用 `DOYAH_EGRESS_LOG_DIR` 覆盖 | `Core/EgressLog.swift` |
| `workspace-history.json` | JSON | 原子写 | `Core/WorkspaceHistoryStore.swift` |
| `saved-queries.json` | JSON 数组 | 原子写 | `Core/SavedQueryStore.swift` |
| `mcp-servers.json` | JSON | 原子写 | `Core/MCPClientConfiguration.swift` |
| `mcp-approvals/pending.jsonl`、`decisions.jsonl` | JSONL | 追加 | `Core/MCPApprovalQueue.swift` |
| `browser-tabs.json` | JSON | 原子写（目录可覆盖） | `Core/BrowserTabStore.swift` |
| `DoyahNotes/notes.sqlite3` (+ `-wal` / `-shm`) | SQLite | WAL | `NoteStorage/NoteDatabase.swift` |
| `DoyahNotes/notes.sqlite3.incoming` | SQLite | 迁移中间件，建完才换名 | `NoteStorage/NoteLibraryMigration.swift` |
| `DoyahNotes/notes.json.migrated` | JSON | 老格式搬完后的备份（同名顺延 `-2`） | 同上 |
| `.secrets/credentials.json` | JSON（`{version, entries}`） | 原子写，权限 0600，**每个可写候选都写一份** | `Core/LocalSecretStore.swift` |
| `<归档根>/queries/YYYY-MM-DD.sql` | 文本 SQL | 按天一个文件，可读可执行 | `Core/SQLArchive.swift`、`ArchiveLocation.swift` |

### 5.2.3 键值格式

| 键空间 | 键 | 值形态 | 依据 |
| --- | --- | --- | --- |
| 凭据文件 `entries` | `connectionID.uuidString` | `{salt, data}`，均为 Base64；`data` = 口令 XOR `MD5(盐‖键‖计数器)` 流 | `Core/LocalSecretStore.swift` |
| 凭据文件 `entries` | `SSHTunnelSecrets.secretKey(for:)`（UUID 高 8 字节与固定 16 字节盐 XOR） | 同上 | `Core/SSHTunnelSecrets.swift` |
| 凭据文件 `entries` | `agent.api-key`（`FileAgentKeyStore.defaultEntryKey`）或 `AgentProfile.secretKey` | 同上 | `LocalSecretStore.swift`、`AgentConfiguration.swift` |
| 系统钥匙串 | `kSecClassGenericPassword`，`service = DoyahIdentity.keychainServiceName`，`account = connectionID.uuidString` | 口令原文 | `Platform/macOS/KeychainSecretStore.swift` |
| 系统钥匙串 | 同上，`account` = 固定条目名（智能体会话 / 云同步令牌） | JSON 会话或密钥 | `Platform/macOS/KeychainAgentKeyStore.swift`、`Plugins/Notes/Sources/NoteSync/CloudAuth.swift` |
| JSONL 行 | 无键，一行一个 JSON 对象 | 行内键即实体字段 | 各 `*Store.swift` |
| 归档文件名 | `yyyy-MM-dd.sql`；首行 `-- Doyah Studio 查询归档` 为「是不是归档」的判据 | 条目以 `-- ===== 条目开始/结束 =====` 包裹 | `Core/SQLArchive.swift` |

`LocalSecretsLocation.candidateDirectories` 的解析顺序：`DOYAH_SECRETS_DIR` → 工程根 `.secrets` → 应用数据根 `.secrets`；读时先命中先用，写时每个可写候选都写，读不到与解不开分两类处置。

### 5.2.4 主键与唯一性

| 约束 | 落点 | 违反时的行为 | 依据 |
| --- | --- | --- | --- |
| `note.uuid` UNIQUE | `upsert(_ note:)` 的 `ON CONFLICT (uuid) DO UPDATE` | 覆盖而非新增 | `NoteDatabase.swift` |
| `note_tag` 复合主键 | 标签全量替换（先 `DELETE` 后插） | 天然去重 | 同上 |
| `notebook.uid` UNIQUE + `shelf_uid` 外键 | 新建 / 挪架 | 指向不存在的架由外键拦下 | 同上 |
| `reminder` 归属 CHECK | `upsert(_ reminder:)` | 两列同空或同非空即写入失败 | 同上 |
| `query_history.id` 主键 | `upsertQueryHistory` | 同 id 再写 = 刷新 | 同上 |
| `ConnectionConfig.id` | 内存 + 全量落盘 | 数组内无唯一约束：重复 id 会共存，去重由上层负责（JSON 文件没有库级约束可依） | `ConnectionStore.swift` |
| `MCPClientServerConfig.name` | 配置校验 | 重名记 `duplicateName`，该条不启动 | `MCPClientConfiguration.swift` |

### 5.2.5 索引清单

| 索引 | 表 | 列 | 服务的查询 | 依据 |
| --- | --- | --- | --- | --- |
| `note_updated_at_index` | `note` | `updated_at DESC` | 列表排序 | `NoteDatabase.swift` |
| `note_source_kind_index` | `note` | `source_kind` | 按来源筛 | 同上 |
| `note_notebook_index` | `note` | `notebook_uid` | 按笔记本过滤 | 同上 |
| `note_tag_tag_index` | `note_tag` | `tag` | 标签检索 | 同上 |
| `note_timeline_note_index` | `note_timeline` | `(note_id, at)` | 时间线正序 | 同上 |
| `note_attachment_note_index` | `note_attachment` | `note_id` | 附件列表 | 同上 |
| `notebook_shelf_index` | `notebook` | `(shelf_uid, sort_order)` | 架内排序 | 同上 |
| `todo_tag_tag_index` | `todo_tag` | `tag` | 标签检索 | 同上 |
| `reminder_note_index` / `reminder_todo_index` | `reminder` | `note_id` / `todo_id` | 查某归属的提醒 | 同上 |

刻意不建索引的：`query_history`（上限 500 行）、`todo`（按截止时间排在当前规模不成立）、`favorite` / `pinned`（与笔记同量级）。

## 5.3 迁移与版本链

| 链路 | 版本标识 | 机制 | 幂等保证 | 回滚点 / 失败处置 | 依据 |
| --- | --- | --- | --- | --- | --- |
| 连接配置 v0 → v1 | 字段 `schemaVersion` | 缺键解码为 `0`，迁移器补齐端口与超时并置 `1`；只做「能确定」的正常化，不动主机/账号/库名 | 已是当前版原样返回 | 发现更高版本 ⇒ **不迁移、不写回**，原样保留并计入 `skippedNewerVersions`；写回只在「发生迁移且未跳过更新版本」时进行 | `ConnectionConfigMigration.swift`、`ConnectionStore.swift` |
| 笔记库 v1 → v10 | `PRAGMA user_version` | 逐版执行 `NoteSchemaV1…V10.ddl`，每版后写 `user_version`，整段在**一个事务**内 | 已是最新版直接返回，一个字节不动 | 事务回滚即整段不生效；库版本高于代码 ⇒ 抛 `unsupportedSchemaVersion` 并**拒绝任何写入** | `NoteStorage/NoteDatabase.swift` |
| `notes.json` → `notes.sqlite3` | 文件名不同即判据 | 在 `.incoming` 建完整库（schema + 全部笔记 + 读回核对）后 `moveItem` 换名；旧文件改名 `notes.json.migrated` | 目标库已存在 ⇒ `skippedTargetExists`，不动 | 旧文件读不出 ⇒ `legacyUnreadable` 原地保留；建库失败 ⇒ `writeFailed`，目标位置不残留 | `NoteStorage/NoteLibraryMigration.swift` |
| 正文 v1 → v2（`body` → `spans`） | 列 `spans` 是否 NULL | `setNoteSpans` 为唯一写入口；迁移按 `spans IS NULL` 取行，`uuid` 升序稳定 | `migratedSpanCount` 可复算 | 单独出包执行；迁移不动 `body` 一个字节 | `NoteDatabase.swift`（`legacyBodyRows`） |
| 文件格式演进 | 无版本号 | 只增可选字段，缺键解码为默认值；**不因可选字段抬高版本号** | 反复读写不变形 | 破坏性变更才升版本号 | `ConnectionConfigMigration.swift`、`MCPClientConfiguration.swift` |

迁移的触发时机是固定的两处，不做后台轮询：连接档在 `loadWithReport` 时迁；笔记库在每次打开（`NoteDatabase.init` → `applySchemaIfNeeded`）时迁；`notes.json` 的一次性搬运在打开笔记时同步跑一次。这样「什么时候迁」有唯一答案，不会出现两条路各迁一半。

逐版迁移而不是「按最新版直接建」，是为了让存量库真的走一遍 v1 → v2 → … → v10：只在新库上跑通的路是假绿。所有 DDL 与 `user_version` 同事务提交，不会出现「表建了一半、版本已记 2」。

单向纪律：库只升不降；`user_version` 高于 `supportedVersion` 时，正确处置是**换回新版程序**，不是拿旧代码改写新库。

## 5.4 索引与检索

| 检索面 | 数据源 | 路径 | 一致性要求 | 依据 |
| --- | --- | --- | --- | --- |
| 笔记全文 | `note` + `note_fts` + `note_tag` | 查询串 ≥3 字符走 FTS5 `MATCH`（短语字面量，双引号翻倍），未命中或含空格退回 `LIKE` 子串扫描；标签命中在两条路里各补一次；结果按 `updated_at DESC, title ASC` 重排 | 返回值必须带 `SearchResult.Route`（`fullText` / `substring`），界面据此说明「按子串匹配找到」；`note_fts` 与 `note` 由触发器同步 | `NoteDatabase.swift` |
| 笔记列表 | `note` | `deleted_at IS NULL` 过滤集中在 `materialize` 一处 | 墓碑行不进列表、不进检索、不进计数 | 同上 |
| 待办 | `todo` + `todo_tag` | 稳定序 `created_at ASC, uuid ASC`；标签批量 `IN` 取，避免 N+1 | 排序口径属契约半，「按截止/优先级排」**待定** | 同上 |
| 提醒 | `reminder` | 按归属 `LEFT JOIN` 出 uuid；归属行不存在即抛错不降级 | 「恰一非空」由 CHECK 保证 | 同上 |
| 查询历史 | `query_history` | `ORDER BY executed_at DESC, rowid DESC` | 上限只在 `QueryHistoryStore.prune` 一处裁 | `QueryHistoryStore.swift` |
| 会话列表 | `agent-sessions/*.jsonl` | 目录扫描，只读首行 header；坏文件跳过并计数 | 别的 `workspace` 的会话**看不到**（不是「空会话」） | `AgentSession.swift` |
| 记忆 | `agent-memory/<ws>.jsonl` + `*.index.json` | 事实源为准，索引是派生缓存 | 索引坏不改变事实源；缺 header 或坏文件时拒写 | `AgentMemory.swift` |
| 查询归档 | `<归档根>/queries/*.sql` | 逐文件 `parse`，以首行头判据区分「空归档」与「非归档」 | `render` 与 `parse` 往返相等（时间到秒） | `SQLArchive.swift` |

两类检索的一致窗口不同，必须在界面上说清楚：

- **全文索引是结构同步的**：`note_fts` 是外部内容表，增删改由三个触发器在同一事务里维护，所以「写进去立刻搜得到」成立；不存在延迟建索引的窗口。它真正的边界是分词——trigram 只覆盖 ≥3 字的连续子串，1~2 字的中文查询只能走子串兜底，因此返回值必须带上走了哪条路。
- **记忆索引是派生缓存**：`*.index.json` 可以从事实源重建，读坏了只影响本次加速，不影响「我知道什么」；事实源本身缺首行或读不出时，写入被拒而不是覆盖。

## 5.5 保留与清理

| 数据 | 上限 / 期限 | 触发者 | 是否删凭据 | 依据 |
| --- | --- | --- | --- | --- |
| `query_history` | 500 条**或** 90 天，先到者为准；`maxEntries <= 0` 判成清空 | `QueryHistoryStore.load` / `append` 各裁一次 | 否 | `QueryHistoryStore.swift` |
| `AgentMemoryEntry` | 每工作区 200 条、单条 200 字（`AgentMemoryLimits.standard`）；超额按最近最少用挤出并报 `evictedIDs` | 每次 `record` | 否 | `AgentMemory.swift` |
| `AgentScheduleRunRecord` | 无上限（删条目时连带删该条目全部历史） | `AgentScheduleStore.delete(id:)` | 否 | `AgentScheduleStore.swift` |
| `AgentActionRecord` | 无自动过期 | 用户手动 `removeAll` | 否 | `AgentAudit.swift` |
| `EgressEntry` | 无自动过期 | 用户查看 / 导出 / 清空 | 否 | `EgressLog.swift` |
| `note` 墓碑 | 无清理任务；墓碑行保留以便跨端传播删除 | 无 | 否 | `NoteDatabase.swift`（`deleted_at`） |
| 连接口令 / 隧道口令 | 随连接删除 | `AppState.deleteConnection` 同时删两个键 | **是**：主口令与派生隧道键都删，避免留下认不出的孤儿秘密 | `App/AppState.swift` |
| 凭据文件 / 令牌 | 随显式清除 | `deletePassword` / `deleteAPIKey` / 云同步登出 | 是 | `LocalSecretStore.swift`、`CloudAuth.swift` |
| 快照备份 | 不覆盖既有文件；文件名时间戳到秒 | 调用方指定目标 | 否 | `NoteDatabase.snapshot(to:)` |

凭据不清的两种例外必须说明：删连接**必须**清；而「清空查询历史 / 清空审计」**不**触碰凭据。

## 5.6 人工处理过程

| 情形 | 判据 | 人工步骤 | 依据 |
| --- | --- | --- | --- |
| 库版本高于程序 | `user_version > supportedVersion`，抛 `unsupportedSchemaVersion` | 停止使用旧程序；换回新版；库文件原样保留 | `NoteDatabase.swift` |
| 旧 JSON 笔记读不出 | `NoteLibraryMigration` 报 `legacyUnreadable` | 保留 `notes.json` 原件，人工检查编码与 JSON 结构后再迁 | `NoteLibraryMigration.swift` |
| 口令文件损坏 | `FileSecretStore.read` 抛「口令文件损坏：<路径>（原因）」 | 按报出的路径逐个检查；确认无救后删除该条目并重设口令 | `LocalSecretStore.swift` |
| 凭据写不进 | `mutate` 报「已尝试：<全部候选路径>」 | 检查候选目录权限（应为 0600 且可写），或用 `DOYAH_SECRETS_DIR` 指到可写目录 | 同上 |
| 快照需恢复 | 备份文件自带 `user_version` 与 `integrity = ok` | 关闭应用 → 将快照文件放到笔记数据家并命名为 `notes.sqlite3` → 打开应用（打开即按需升版） | `NoteDatabase.snapshot` |
| JSONL 出现坏行 | 读回时 `skippedLines` / `skippedFiles` 计数非零 | 按会话 / 检查点标识定位文件，人工修补或整份移走；**不要**用空文件覆盖 | `AgentSession.swift`、`AgentCheckpoint.swift` |
| 记忆文件缺 header | `AgentMemoryStore.entries` 报 `missingHeader`，写入被拒 | 人工补首行 `{"workspace": "<ws>"}` 或整份移走 | `AgentMemory.swift` |

## 5.7 需要补的事实

| 编号 | 待定项 | 现状 |
| --- | --- | --- |
| D-01 | 待办排序口径（三档第一关键字、无截止排哪端、逾期是否影响排序） | 代码只给 `created_at ASC, uuid ASC` 的稳定序，明确标注属契约半 |
| D-02 | `note` 墓碑的保留期与清理策略 | 无清理任务，`deleted_at` 只增 |
| D-03 | `agent-schedule-runs.jsonl` / `agent-audit.jsonl` / `egress-log.jsonl` 的上限或轮转 | 无上限、无轮转 |
| D-04 | 云同步待传队列是否需跨重启保留 | `SyncQueueEntry` 只在内存，代码无落盘 |
| D-05 | 笔记附件二进制目录约定 | 库里只存 `path`，目录约定未在代码中固化 |

# 第六章 接口设计

接口分三层：**核心协议**（Core 声明、可替换实现）、**平台适配**（系统能力薄封装）、**外部接口**（数据库线协议、模型服务、云同步、凭据存储、MCP）。所有协议均为 `Sendable`；需要串行语义的以 actor 承担，不以锁承担。

## 6.1 接口总览

| 协议 | 定义处 | 角色 | 用途 |
| --- | --- | --- | --- |
| `DatabaseService` | `Core/DatabaseService.swift` | 驱动 | 连接、执行、取消、事务、批量导入 |
| `SQLDialect` | `Core/Dialects.swift` | 方言 | 标识符引用、分页、元数据查询 |
| `ServerObjectDialect` | `Core/ServerObjects.swift` | 方言 | 对象清单查询与近似说明 |
| `LLMClient` | `Core/LLMClient.swift` | 模型 | 一次性补全 |
| `LLMStreamingClient` | `Core/LLMStreaming.swift` | 模型 | 流式补全 |
| `HTTPTransport` | `Core/LLMClient.swift` | 传输 | 整段 HTTP |
| `HTTPStreamingTransport` | `Core/LLMStreaming.swift` | 传输 | 分块 HTTP |
| `SecretStore` | `Core/SecretStore.swift` | 凭据 | 连接口令 |
| `AgentKeyStore` | `Core/AgentConfigurationStore.swift` | 凭据 | 模型密钥 |
| `AgentToolDispatcher` | `Core/AgentLoop.swift` | 智能体 | 工具分发 |
| `AgentQueryExecutor` | `Core/AgentDatabaseTool.swift` | 智能体 | 只读 / 写执行 |
| `AgentLoopObserver` | `Core/AgentLoop.swift` | 智能体 | 逐跳事件 |
| `AgentCommandRunner` | `Core/AgentCommandPolicy.swift` | 智能体 | 命令执行 |
| `AgentAuditSink` | `Core/AgentLoop.swift` | 智能体 | 审计落账 |
| `MCPClientTransport` | `Core/MCPClientBridge.swift` | MCP | 行式传输 |
| `MCPClientCalling` | `Core/MCPClientBridge.swift` | MCP | 工具调用 |
| `ExternalProcessRunner` | `Core/ExternalProcess.swift` | 进程 | 外部程序与备份 |
| `CodeFormatProcessRunning` | `Core/CodeFormatting.swift` | 进程 | 格式化过滤器 |
| `SecurityScopedBookmarking` | `Core/SecureDirectoryAccess.swift` | 平台 | 目录书签 |
| `DirectoryPicker` | `Core/SecureDirectoryAccess.swift` | 平台 | 选目录 |
| `BrowserEngine` | `Core/BrowserPage.swift` | 平台 | 内嵌浏览 |
| `LicenseSignatureVerifying` | `Core/License.swift` | 平台 | 签名校验 |
| `ReminderDelivering` | `App/ReminderNotifier.swift` | 平台 | 系统通知 |
| `WorkspaceBrowserHost` | `App/WorkspaceBrowserModel.swift` | 视图 | 下载目录与出网留痕 |
| `ResultGridCopying` | `App/Views/ResultGrid.swift` | 视图 | 结果集复制与行操作 |

## 6.2 接口面通用约定

本节四条定义适用于 6.2 的全部接口面，后面每节只写该面特有的部分，不重复。

| 约定 | 定义 | 反例（被明确禁止的做法） | 依据 |
| --- | --- | --- | --- |
| 失败 | 必须能分类：连不上 / 认不出 / 服务端原话 / 取消结果。能用返回值表达的用返回值（`CancelOutcome`、`AgentToolOutcome`），不能用返回值表达的抛类型化错误（`LLMError`、`MCPTransportFailure`、`NoteStorageFailure`） | 返回空数组表示失败；只抛一个字符串 | `LLMClient.swift`、`MCPClientBridge.swift` |
| 取消 | 能做定向取消的接口必须收句柄；不能取消的必须在协议注释里写清「随 Task 取消」 | 用全局布尔标志「停所有查询」 | `DatabaseService.cancel(_:)` |
| 幂等 | 删除一律幂等，但「没命中」必须可分辨（返回受影响行数，由调用方如实报）；写入按业务键 upsert 即为幂等；外部调用（模型、SQL 写）默认**不幂等** | 删不掉时静默返回成功；把模型调用放进自动重试 | `LocalSecretStore.deletePassword`、`QueryHistoryStore.delete` |
| 线程 | 协议只要求 `Sendable`；串行语义由 actor 承担（`ConnectionStore`、`QueryHistoryStore`、`AgentScheduleStore`），实现内部若需锁则用递归锁并把「语义并发」留给调用方 | 在 store 里再套一层队列 | `NoteDatabase.swift` 文件头 |

### 6.2.1 数据库访问面

| 方法 | 参数 | 返回 | 抛出 / 失败 | 幂等 | 依据 |
| --- | --- | --- | --- | --- | --- |
| `connect()` | — | `ServerInfo` | `AppError.invalidConfiguration` / `notImplemented` / `queryFailed` | 否（重复连接按实现处理） | `DatabaseService.swift` |
| `disconnect()` | — | `Void` | 不抛 | 是 | 同上 |
| `execute(_:options:handle:)` | `sql: String`、`options: QueryOptions`、`handle: ExecutionHandle` | `AsyncThrowingStream<QueryEvent, Error>` | 流内抛错；非 2xx/语法错归 `queryFailed` | 否 | 同上 |
| `cancel(_:)` | `handle: ExecutionHandle` | `CancelOutcome` | **不抛**：取不到后端 PID 等一律以 `.failed(reason:)` 返回 | 是 | 同上 |
| `beginTransaction()` / `commit()` / `rollback()` | — | `Void` | `AppError` | 否 / 是 / 是 | 同上 |
| `copyFromText(table:columns:text:)` | 裸表名、列名、已编码文本 | `Void` | 不支持即 `AppError.notImplemented`，**不退化为逐条 INSERT** | 否 | 同上 |

失败语义分四档，界面按档给文案，不按错误字符串猜：

| 档 | 典型来源 | 表达 | 处置 |
| --- | --- | --- | --- |
| 连不上 | 主机不可达、隧道未建立、超时 | `AppError.queryFailed` 或驱动侧传输错 | 提示检查地址 / 隧道 / 网络；不自动重试 |
| 认不出 | 配置非法、方言不支持该能力 | `AppError.invalidConfiguration` / `notImplemented` | 指回配置页；不退化执行 |
| 服务端原话 | SQL 语法错、权限不足、约束冲突 | `queryFailed` 携带服务端原文 | 原样展示，不截断关键信息 |
| 原样 | 取消结果、连接已断开时的取消请求 | `CancelOutcome.notActive` / `.failed(reason:)` | 如实显示「没有正在执行的语句」，不假装取消成功 |

取消语义：句柄定向，只终止这一次执行——同库另一页签的语句不受影响。默认便捷入口生成的句柄外部不可取消，因此需要「停止」按钮的场景必须显式传句柄。线程：实现为 `AnyObject & Sendable`，连接内部串行化，语义并发由调用方 actor 负责。

### 6.2.2 模型访问面

| 方法 | 参数 | 返回 | 失败分类 | 取消 | 依据 |
| --- | --- | --- | --- | --- | --- |
| `LLMClient.complete(_:)` | `LLMRequest` | `LLMResponse` | `LLMError`：`disabled`、`forbidden`、`quotaExceeded`、`transport`、`httpStatus(code:message:)`、`malformedResponse`、`emptyCompletion` | 随 Task 取消 | `LLMClient.swift` |
| `LLMStreamingClient.stream(_:)` | `LLMRequest` | `AsyncThrowingStream<LLMStreamEvent, Error>` | 同上；**未收到 `[DONE]` 即结束 ⇒ `transport`** | `onTermination` 取消内部 Task | `LLMStreaming.swift` |
| `HTTPTransport.send(_:)` | `URLRequest` | `(Data, HTTPURLResponse)` | 非 HTTP 应答 ⇒ `transport` | 随 Task | `LLMClient.swift` |
| `HTTPStreamingTransport.stream(_:)` | `URLRequest` | `(HTTPURLResponse, AsyncThrowingStream<Data, Error>)` | 非 2xx 不在传输层抛，统一由上层映射 | 随 Task | `LLMStreaming.swift` |

流式实现的两条硬约束：请求体强制 `stream: true`（调用方忘了设也不会退化成整段请求）；读到 `data: [DONE]` 之后不再读，未收到 `[DONE]` 就结束则整条流以 `transport` 结束——**不把半截回复当完整回复**。传输层按行冲刷：SSE 的语义单位是行，一次一行给上去，解码器既不囤整段，也能在断流时第一时间发现；收尾那半行也要交出去，否则最后一句会被吞掉。

幂等性：模型调用**不幂等**，调用方不得自动重试（重试会产生二次计费与重复工具调用）。线程：全部 `Sendable`，流实现内部按行冲刷，不使用共享可变状态。

### 6.2.3 凭据面

| 方法 | 参数 | 返回 | 失败 | 幂等 | 依据 |
| --- | --- | --- | --- | --- | --- |
| `SecretStore.setPassword(_:for:)` | `password: String`、`connectionID: UUID` | `Void` | `AppError.credentialStore(code:)` 或 `persistence` | 是（覆盖） | `SecretStore.swift` |
| `SecretStore.password(for:)` | `connectionID: UUID` | `String?` | 同上；`nil` = 没存过 | 是 | 同上 |
| `SecretStore.deletePassword(for:)` | `connectionID: UUID` | `Void` | 同上 | 是（删不存在的键不报错） | 同上 |
| `AgentKeyStore.setAPIKey(_:)` / `apiKey()` / `deleteAPIKey()` | `key: String` | `Void` / `String?` | 同上 | 是 | `AgentConfigurationStore.swift` |

硬约束：秘密不出现在错误信息、日志、审计与外发记录里；`detail` 字段写入前统一脱敏。

### 6.2.4 智能体回路面

| 方法 | 参数 | 返回 | 失败表达 | 线程 | 依据 |
| --- | --- | --- | --- | --- | --- |
| `AgentToolDispatcher.dispatch(_:approvals:)` | `AgentToolInvocation`、已批准集合 | `AgentToolOutcome` | 以 outcome 表达，不抛 | 同步，调用方串行 | `AgentLoop.swift` |
| `AgentQueryExecutor.executeReadOnly(sql:)` / `executeWrite(sql:)` | `sql: String` | `AgentQueryExecution`（含 `errorMessage`） | 错误进 `errorMessage`，不抛 | 同步 | `AgentDatabaseTool.swift` |
| `AgentLoopObserver.observe(_:)` | `AgentLoopEvent` | `Void` | 不抛 | `async`，可并发 | `AgentLoop.swift` |
| `AgentCommandRunner.run(executable:arguments:workingDirectory:)` | 程序、参数、工作目录 | `AgentCommandResult`（退出码 + stdout + stderr） | 非零退出码是数据，不是异常 | 同步 | `AgentCommandPolicy.swift` |
| `AgentAuditSink.record(_:)` | `AgentActionRecord` | `Void` | 不抛（落账失败不阻断动作） | `async` | `AgentLoop.swift` |

参数与声明不一致时由 `AgentToolSchemaValidator.validate` 返回机器可读原因并回灌模型，**不执行**。

### 6.2.5 MCP 面

| 方法 | 参数 | 返回 | 失败 | 幂等 | 依据 |
| --- | --- | --- | --- | --- | --- |
| `MCPClientTransport.open()` | — | `MCPTransportFailure?`（`nil` = 成功） | `spawnFailed` / `closed` / `exited` / `timeout` / `protocolViolation` | 否 | `MCPClientBridge.swift` |
| `MCPClientTransport.send(_:)` | 一行 JSON-RPC | `MCPTransportFailure?` | `writeFailed` / `closed` | 否 | 同上 |
| `MCPClientTransport.receive()` | — | `Result<String, MCPTransportFailure>` | 对端关闭与超时都是失败，不是空串 | 否 | 同上 |
| `MCPClientTransport.close()` | — | `Void` | 不抛 | 是 | 同上 |
| `MCPClientCalling.call(tool:argumentsJSON:)` | 远端工具名、参数原文 | `MCPClientCallOutcome` | 状态与错误码在 outcome 内 | 由远端工具决定 | 同上 |

握手固定三步：`initialize` → `notifications/initialized` → `tools/list`。回了包但没带 `protocolVersion` 时**握手不算成功**，不猜「大概握上了」。发现阶段对每个启用的 server 起一次进程，连上与连不上都产出状态；`enabled = false` 的 server 连进程计划都不生成，本层不提供「起了再说」的入口。与内置工具重名的远端工具不合并，登记成 `nameConflict:<名>` 供界面说明。

传输为**行式同步**接口（阻塞读写，由调用方置于受控线程）；工具名与参数**原样**转发，不改名、不改形状。

### 6.2.6 平台薄适配面

| 协议 | 方法 | 失败 / 取消 | 隔离要求 | 依据 |
| --- | --- | --- | --- | --- |
| `ExternalProcessRunner` | `run(executable:arguments:environment:onOutput:) async throws -> Int32` | `launchFailed(executable:reason:)`；取消时优雅终止→超时强杀 | stdout/stderr 合流保序 | `ExternalProcess.swift` |
| `CodeFormatProcessRunning` | `runFilter(executable:arguments:input:) async throws -> CodeFormatProcessResult` | 非零退出码作为结果返回 | 同上 | `CodeFormatting.swift` |
| `DirectoryPicker` | `pickDirectory(prompt:) throws -> URL?` | 用户取消返回 `nil`，不抛 | 主线程弹框 | `SecureDirectoryAccess.swift` |
| `SecurityScopedBookmarking` | `makeBookmark` / `resolve` / `startAccessing` / `stopAccessing` | 解析失败可抛；`isStale` 表示建议重生成 | `start`/`stop` 必须成对 | 同上 |
| `BrowserEngine` | `load` / `goBack` / `goForward` / `reload`（均 `async`）、`setUpdateHandler` | 先过策略、先写出网日志，再发请求 | `@MainActor` | `BrowserPage.swift` |
| `LicenseSignatureVerifying` | `isValid(payload:signature:) -> Bool` | 不抛，返回布尔 | 纯函数 | `License.swift` |
| `ReminderDelivering` | `permission` / `requestPermission` / `schedule(id:title:body:triggerEpochMillis:)` / `cancel(id:)` | 权限未决即返回未决档，不假装成功 | `async` | `App/ReminderNotifier.swift` |
| `SQLDialect` / `ServerObjectDialect` | `quoteIdentifier` / `stringLiteral` / `limitClause` / `listQuery(for:limit:)` 等 | 不支持时返回 `nil` 或可读说明，不抛 | 纯值类型 | `Dialects.swift`、`ServerObjects.swift` |

## 6.3 外部接口

| 外部面 | 协议 / 形态 | 端点与凭据 | 失败与重试 | 密钥落点 | 依据 |
| --- | --- | --- | --- | --- | --- |
| 数据库（PostgreSQL） | PostgreSQL 线协议（驱动） | 主机 + 端口（缺省取 `dbType.defaultPort`）+ 库名 + 账号 | 失败分四档；取消定向；**不自动重试** | 系统凭据存储，`account = connectionID.uuidString` | `DatabaseService.swift`、`PostgresService` |
| 数据库（MySQL / GBase 8a） | MySQL 协议族（共用驱动、方言分对） | 同上 | 同上；不支持的能力抛 `notImplemented` | 同上 | `DatabaseServiceFactory` |
| SSH 隧道 | `ssh` 可执行（默认 `/usr/bin/ssh`，可被 `DOYAH_SSH_BINARY` 覆盖） | 跳板机主机 + 端口 + 账号 | 建隧道超时缺省 15 秒 | 隧道口令按键派生，存凭据存储 | `SSHTunnel.swift`、`SSHTunnelSecrets.swift` |
| 模型服务 | HTTPS POST `…/chat/completions`（OpenAI 兼容） | `AgentProfile.endpoint` + `model`；`Authorization: Bearer` | `transport` / `httpStatus` 分类；流式断流即 `transport`，不重试 | 系统凭据存储；文件形态条目键 `agent.api-key` 或 `secretKey` | `LLMClient.swift`、`LLMStreaming.swift` |
| 云同步（数据面） | HTTPS + PostgREST 形态 | `https://<envId>.api.tcloudbasegateway.com`，`/v1/rdb/rest/<table>`；`Authorization: Bearer <access_token>` | `transport` 视为断网，入队 + 指数退避；服务端非 2xx 记 `server(code:status:)` | 会话令牌进系统钥匙串 | `Plugins/Notes/Sources/NoteSync/CloudSyncService.swift` |
| 云同步（账号面） | HTTPS `/auth/v1/signin`、`/auth/v1/token`、`/auth/v1/revoke` | 同上基址 | 刷新失败即登出并清令牌 | 令牌（`access_token` / `refresh_token`）进钥匙串，**不落明文文件** | `NoteSync/CloudAuth.swift` |
| 系统凭据存储 | `kSecClassGenericPassword` | `service = DoyahIdentity.keychainServiceName` | `credentialStore(code:)` 原样上报状态码 | 键即 `account` | `Platform/macOS/KeychainSecretStore.swift` |
| MCP server | JSON-RPC 2.0（`MCPProtocol.version = "2024-11-05"`）over stdio | 用户配置的 `command` + `args` + `env`（原样启动，不经 shell） | 握手 `initialize` → `notifications/initialized` → `tools/list`；每 server 都产出状态 | 配置里的 `env` / `headers` 由用户自填；本产品不代管其密钥 | `MCPClientBridge.swift`、`MCPProtocol.swift` |
| 出网留痕 | 本地 JSONL（非网络面） | `egress-log.jsonl` | 写失败只警告，不阻断主流程 | 无 | `EgressLog.swift` |
| 行情源 | 待定 | 代码中无实现 | 待定 | 待定 | — |
| IM 通道 | 待定 | 代码中无实现 | 待定 | 待定 | — |

超时与重试按面分开定，不设全局默认：数据库连接超时来自 `ConnectionConfig.timeout`（缺省 5 秒），隧道握手缺省 15 秒，MCP 单次往返来自 `timeoutSeconds`（缺省 20 秒），模型请求来自 `AgentProfile.timeoutSeconds`。四个值都在配置里可改，且都只作用于本面。

重试纪律（三条）：数据库与模型调用**不自动重试**；云同步只在 `transport` 一档入队重试，非 2xx 不入队；外部程序由调用方决定，重试必须显式。

密钥落点的三条硬边界：连接口令与隧道口令只进凭据存储，配置文件里没有可写字段；模型密钥只进 `Authorization` 头，**不写进请求体**，避免被日志或审计顺手抄走；云同步令牌只进钥匙串，不落明文文件。任何日志、审计与外发记录的 `detail` 写入前统一脱敏，`target` 去掉 query 与 fragment。

## 6.4 接口演进纪律

| 编号 | 纪律 | 理由 | 依据 |
| --- | --- | --- | --- |
| I-01 | 协议只增方法，不改既有签名语义 | 假实现与判据都按既有签名写，改签名等于推翻一整族判据 | `LLMStreaming.swift`（新增流式协议而非改 `HTTPTransport`） |
| I-02 | 新增可选字段不抬版本号 | 抬版本会让老程序把新文件判成「来自更新版本」而拒绝改写 | `ConnectionConfigMigration.swift` |
| I-03 | 认不出的枚举值分两类处置：来源类抛错、优先级类「当没给」 | 前者是数据损坏必须让人知道，后者只是别端多一档 | `NoteDatabase.materialize` 与 `TodoPriority.init(raw:)` |
| I-04 | 协议不提供「悄悄降级」的实现 | 不支持就抛可读错误，绝不退化成慢路径 | `copyFromText` 默认实现 |
| I-05 | 平台差异只允许存在于实现侧，协议层不出现平台名 | 协议是跨端契约 | `SecretStore.swift`、`AgentKeyStore` |
| I-06 | 失败必须可分类型，不得只有一句「失败」 | 调用方要按类别决定重试、入队或提示 | `LLMError`、`MCPTransportFailure`、`NoteStorageFailure` |
| I-07 | 新增出网入口必须同时在 `EgressKind` 加一档 | 否则外发日志会漏，「零外发」无法审计 | `EgressLog.swift` |
| I-08 | 取消语义写进协议：能取消的必须给句柄，不能取消的必须写清 | 「停止」按钮要定向到这一次执行 | `DatabaseService.execute(handle:)` |

这套纪律之所以要写成条目而不是原则，是因为它每一条都能被机械检查：协议只增方法可以比对既有签名；新增可选字段是否抬版本可以比对解码分支；「不支持就抛」可以搜默认实现里有没有退化路径；新增出网入口可以比对 `EgressKind` 的档数与实现里的出口。

## 6.5 需要补的事实

| 编号 | 待定项 | 现状 |
| --- | --- | --- |
| I-09 | 行情源的提供方、协议与密钥落点 | 代码无实现 |
| I-10 | IM 通道的接入协议与消息格式 | 代码无实现 |
| I-11 | 云同步待传队列的重启恢复语义 | 队列仅在内存 |
| I-12 | MCP `http` 传输的支持时点 | 配置保留 `url` / `headers` 字段，当前只支持 `stdio` |

# 第七章 界面设计（契约部分）

界面天然与平台绑定：窗口模型、控件集、键位、导航模式各端由系统规范决定，**不可能也不应该统一**。所以本章只锁定「必须一致」的那一半 —— 区域划分与信息层级、控件状态集、视觉令牌语义、命令入口的四处同文案、处置口径、可及性目标；**具体用什么控件、怎么排布、走哪套平台规范，写在第九章各端的「界面设计」段**（macOS / iOS 归本侧，Windows / Linux 由该侧写）。

界面是契约的可见面：第三章规定「结果必须一致」，本章规定「一致长什么样」。这里的取值是**可量的数值与可枚举的状态**，不是观感形容词；跨端对比以本章为准，差异走第四章登记。

## 7.1 界面构成与区域划分

主窗口固定五个区域，滚动与拉伸的优先次序也固定：

| 区域 | 内容 | 伸缩行为 |
|---|---|---|
| chrome 行 | 页签条 + 全局搜索入口 | **高度由令牌定，不由内容定**（`FR-STD-WS-UI-010`） |
| 侧栏 | 连接树 / 对象树 / 文件树 | 可折叠，宽度可拖 |
| 编辑区 | SQL / 文本编辑面 | 占主伸缩权重 |
| 结果区 | 结果集 / 消息 / 诊断 | 可折叠，与编辑区之间可拖拽分配 |
| 状态栏 | 连接状态、行数、耗时、后台任务 | 固定高度，不参与伸缩 |

多窗口与多页签是同一份会话模型的两种视图（`FR-STD-WS-UI-001`）；新建查询页签的编号在应用生命周期内单调递增、不因关闭或重命名回收（`FR-STD-WS-UI-002`）；重启后页签与连接恢复（`FR-STD-WS-UI-004`）。关闭带未保存改动的文件页签要确认，但**确认不得阻塞其余窗口与页签**（`FR-STD-WS-UI-003`）。

## 7.2 布局、栅格与分隔

| 项 | 取值 | 说明 |
|---|---|---|
| 编辑区 / 结果区 | 可拖拽分隔条，实时生效并记忆 | 放大或缩小结果区不重建编辑器实例（`FR-STD-WS-UI-007`） |
| 侧栏宽度 | 默认值 + 可拖范围上下限 | 拖到下限自动折叠 |
| 内容外边距 | 一级容器 16，二级 8 | 同一层级在所有端同值 |
| 行高 | 列表行与树行分别取值 | 不随字号线性膨胀，避免大字号下信息密度崩坏 |

拖拽中的实时重排只影响布局，不改变文档或查询状态：拖动结束不得触发「标脏」（`FR-STD-WS-EDIT` 的保存语义）。

## 7.3 视觉：主题、配色与字体

三条不可换的实现细节：

1. **主题是令牌，不是散落的颜色字面量**：浅色 / 深色跟随系统或手动指定，主题（配色方案）可选并一键切换（`FR-STD-WS-UI-008`、`FR-STD-WS-UI-009`）。
2. **能编辑多行文本的区域，底色与字色只能来自主题令牌**（`FR-STD-WS-UI-011`）——这是防止「某个面板在深色下白得刺眼」的唯一机械约束。
3. **语法着色的颜色走主题令牌，规则按语言可扩展**：关键字 / 函数 / 字符串 / 注释 / 数字 / 引用标识符分别配色，运算符保持默认色；新增语言只加规则、不改内核（`FR-STD-WS-NAV-001`、`FR-STD-WS-NAV-002`）。

字体：编辑器等宽字体与字号可调（`FR-STD-WS-UI-008`）；界面字体跟随系统。字号与行距的取值一致要求见第四章 `P-07`。

## 7.4 控件状态与处置口径

同一控件在任意端必须是**同一组状态**，缺一个状态就是缺陷：

| 状态 | 必须出现 | 判定 |
|---|---|---|
| 空 | 说明为什么空 + 一个可点的下一步 | 不出现空白面板（`NFR-ALL-GATE-USE-005`） |
| 加载 | 进行中提示；超过 300 ms 才出现 | 快速完成不闪提示 |
| 进行中 | 可取消入口（长任务） | 取消后状态回写为「已取消」（`NFR-ALL-GATE-USE-003`） |
| 失败 | 可读原因 + 重试入口 | 不留「无反应」（`NFR-ALL-GATE-USE-002`） |
| 禁用 | 说明为何禁用（悬停或行内） | 不允许「灰着但不解释」 |
| 已截断 | 「共 N 行，已截断」明示 | 静默截断视为缺陷（`NFR-ALL-GATE-PERF-003`） |

**走不动的动作必须挑一种处置并写出来**：禁用 / 明示未实现 / 失败态 / 降级，四选一，不允许无反应（`NFR-ALL-GATE-USE-005`）。

## 7.5 编辑器界面

| 能力 | 界面表现 | 判定 |
|---|---|---|
| 补全 | 编辑器内可触发，含关键字与内置函数 | 输入即出候选，键盘可选中（`FR-STD-WS-NAV-003`、`FR-STD-WS-NAV-004`） |
| 片段 | 输入触发词展开骨架，展开后可撤销 | 展开结果可编辑（`FR-STD-WS-NAV-005`） |
| 悬停 / 跳转 | 悬停给一句话说明与定义位置；可跳到定义 | 同文件符号表起步（`FR-STD-WS-NAV-006`） |
| 静态检查 | 结论画到编辑器上：问题范围下划线、悬停看原因 | 已有结论在修改后清空（`FR-STD-WS-NAV-007`、`FR-STD-WS-NAV-011`、`FR-STD-WS-NAV-012`） |
| 服务端检查 | 「检查」对可 EXPLAIN 的语句执行，不真正跑 DML | 通过显示「已检查 N 条，跳过 M 条」（`FR-STD-WS-NAV-009`、`FR-STD-WS-NAV-010`） |
| 格式化 | 菜单 / 快捷键入口，按语言格式化 | 格式化前后可撤销（`FR-STD-WS-NAV-013`、`FR-STD-WS-NAV-014`） |

## 7.6 导航与命令入口

| 入口 | 位置 | 覆盖范围 |
|---|---|---|
| 全局搜索 | 中间区域顶部、标题栏正中，是**唯一**输入面 | Studio 自带命令 + 打开的对象，不混入内容检索（`FR-STD-WS-UI-006`） |
| 命令面板 | 快捷键唤起，可搜索并执行命令 | 新建查询 / 执行 / 检查 / 格式化 / 导出 / 切换连接 / 打开表（`FR-STD-WS-UI-005`） |
| 菜单 | 系统菜单栏 | 命令与面板逐项对应，文案一致 |
| 快捷键 | 见本节表下规则 | 同一命令唯一主键位（`NFR-ALL-GATE-USE-001`、`P-04`） |

**唯一性规则**：一个命令在全局搜索、命令面板、菜单、快捷键四处必须都能找到，且文案相同；四处之中任何一处缺失即视为未实现。

## 7.7 主要操作流程

三条主流程的界面步数与「必须一致」的部分：

| 流程 | 步骤 | 必须一致 |
|---|---|---|
| 连库到出结果 | 新建连接 → 测试 → 选库 → 写语句 → 执行 → 看结果 → 导出 | 每步都有可见的进行中与失败态；结果区列名与类型一致（`P-16`） |
| 智能体会话 | 打开会话 → 描述任务 → 审计划 → 逐次审批写操作 → 看产出差异 | 审批按次、拒绝可解释、产出先看差异再落盘（`AGT-GUARD-PERM`、`NFR-ALL-GATE-AI-005`） |
| 笔记与待办 | 捕获 → 编辑 → 整理 → 检索 → 同步 | 同一条笔记在两端正文与样式一致（`NTS-NOTE-FORMAT`、`NTS-NOTE-SYNC`） |

## 7.8 跨端一致性与可及性

**设计语言在产品内统一**：同一产品的各端与各模块用同一套视觉语言，不按端各立一套（`NFR-ALL-GATE-UI-001`）。允许的差异只有第四章 `P-01`~`P-27` 登记过的项。

可及性：大字号与屏幕阅读器可用；界面为**原生观感**（系统控件、系统导航模式），不做跨端自绘的「统一皮肤」（`NFR-ALL-GATE-USE-004`）——统一的是信息层级与视觉数值，不是像素级复制。

对应需求：`NFR-ALL-GATE-UI-001` `NFR-ALL-GATE-USE-001` `NFR-ALL-GATE-USE-002` `NFR-ALL-GATE-USE-003` `NFR-ALL-GATE-USE-004` `NFR-ALL-GATE-USE-005` `FR-STD-WS-UI-001`~`FR-STD-WS-UI-011` `FR-STD-WS-NAV-001`~`FR-STD-WS-NAV-014`

# 第八章 错误处理与本地化

本章写三件事：错怎么分级、话怎么说、哪种语言说。判断口径以 `Core` 的错误类型与 `Core/Localization.swift` 的语言表为准，不另立说法。全仓 `Core`/`App`/`CLI`/`Plugins` 里实现 `Error` 的类型实测 40 个，其中 24 个同时实现 `LocalizedError`。

## 8.1 错误分级

三级：**可恢复 / 阻断 / 静默**。分级不是文案风格，是「界面还能不能继续走」。

**表 8-1 分级 → 真实错误类型**

| 级别 | 判定 | 界面表现 | 真实错误类型 | 依据 |
|---|---|---|---|---|
| 可恢复 | 用户不必先改前置条件，重试或改输入即可 | 留在当前界面；错误进 Problem 页签或错误框；可再执行 | `AppError`、`DataTaskRunError`、`ImportError`、`ResultStreamError`、`ResultExportEncodingError`、`LLMError`、`LLMRetryExhausted`、`MySQLServiceError`、`CursorPagingError`、`BindError`、`SSHTunnelError` | `Core/AppError.swift:3`、`Core/DataTaskRun.swift:9`、`Core/LLMRetry.swift:79`、`Core/ResultStreamWriter.swift:4` |
| 阻断 | 缺一个用户必须先给的东西：授权、连接、批准、许可 | 停在原地，给出口与下一步；**不给「继续」** | `AppError.notConnected`、`DirectoryAccessError`、`AgentApprovalError`、`DeviceError`、`TerminationBlocked`、`CloudAuthError` | `Core/SecureDirectoryAccess.swift:9`、`Core/AgentAudit.swift:295`、`Core/License.swift:115`、`App/AppRelauncher.swift:45` |
| 静默 | 控制流或后台动作；报出来只会误导 | 只进日志 / 状态栏，不打断输入 | `CancellationError`（经 `CancellationNoise` 判定）、`PluginRegistry.Degraded`、`EgressLog` 落盘失败 | `Core/CancellationNoise.swift`、`Core/Plugin/PluginRegistry.swift`、`Core/EgressLog.swift:155` |

两条口径要补在两处容易走偏的地方。

**「阻断」里最硬的一档是只读连接。** `ExecutionSafety.Decision` 把「高危语句要确认」与「只读连接拒绝写」分成两个分支：前者可绕过（点确认），后者**不允许绕过**——否则用户关掉 Safe Mode 就等于顺手关掉了只读保护（`Core/ExecutionSafety.swift:72`）。

**「静默」不等于「不记录」。** `EgressLog` 的文件注释把两件事分开：「想发但没发出去」与「根本没想发」是两件事，`EgressOutcome.denied` 必须存在，否则「零外发」这句话无法被审计。插件降级同理：`PluginRegistry.Degraded` 列出来、走 `diagnosticLine`，不静默。

**表 8-2 尚未归级的类型**

| 类型 | 依据（文件） | 现状 |
|---|---|---|
| `AgentMemoryIndexError` | `Core/AgentMemoryContext.swift:153` | 调用点抛给上层，界面档位待定 |
| `AgentScheduleLedgerError` | `Core/AgentSchedule.swift:303` | 同上 |
| `MCPTransportFailure` / `MCPClientConfigurationError` / `MCPError` | `Core/MCPClientBridge.swift:7`、`Core/MCPClientConfiguration.swift:165`、`Core/MCPProtocol.swift:39` | 未实现 `LocalizedError`，显示落 `ErrorPresenter` 的反射兜底 |
| `NoteStorageFailure` / `SQLiteFailure` / `MigrationError` | `Plugins/Notes/Sources/NoteStorage/NoteDatabase.swift:484`、`Plugins/Notes/Sources/NoteStorage/SQLiteKit.swift:115`、`Plugins/Notes/Sources/NoteBody.swift:126` | `NoteStorageFailure` 只实现 `CustomStringConvertible`，写库失败经 `ErrorPresenter` 会落到反射串 |
| `BuildError` / `Failure`（工作区文件操作、会话快照） | `Core/RowBrowsing.swift:43`、`Core/WorkspaceFileOperations.swift:16`、`Core/WorkspaceSession.swift:106` | 调用点各自处置，未统一 |

## 8.2 错误分类与包装

界面侧只有一个入口：`ErrorPresenter.message(for:)`。它按固定顺序试七个档，**顺序本身是设计**——放错一档，用户看到的就是反射串。

**表 8-3 包装链的七个档**

| 序 | 档 | 触发条件 | 输出 | 依据 |
|---|---|---|---|---|
| 1 | `AppError` | 类型判等 | 走语言表（6 个 `error*` 键） | `App/Utilities/ErrorPresenter.swift:8` |
| 2 | `SSHTunnelError` | 类型判等 | `describe(language:)`；只有 `.portInUse` 需要拼句子 | `Core/SSHTunnelProcess.swift:268` |
| 3 | 通用 `LocalizedError` | `errorDescription` 非空 | 直接用它给的可读说明 | `App/Utilities/ErrorPresenter.swift:35` |
| 4 | 连接类 | `ConnectionFailure.describe` 认得 | 人话 + 排查建议 | `Core/ConnectionFailure.swift:76` |
| 5 | 驱动非连接类 | `describeNonConnection` | 中性归因 +「（技术细节：…）」 | `Core/ConnectionFailure.swift:179` |
| 6 | 服务端原话 | 带 SQLSTATE 的查询类错误 | 只端原话，不翻译、不归类、不给方向 | `Core/ConnectionFailure.swift:235` |
| 7 | 兜底 | 都认不出 | `String(reflecting:)`，超 800 字符截断 | `App/Utilities/ErrorPresenter.swift:69` |

**原始信息保留策略：三处都留尾巴，一处都不换掉原串。** `ConnectionFailure.Description` 里 `code`（SQLSTATE 或驱动错误类别）与 `technicalDetail` 并存；`ErrorPresenter` 在第 5、6 档后追加「（技术细节：…）」；`CLIFailureText` 在可读化成功时追加「（原始信息：…）」。文件头把理由写明了：排查时「到底是哪个码」往往才是关键，把原串换掉等于帮倒忙。

**用户可见 vs 内部。** `LocalizedError.errorDescription` 在 `Core` 里被明确定性为**技术串、不冒充人话**——`Core/SSHTunnelProcess.swift:291` 那句注释就是这条纪律的原文；真正给人看的句子必须由带 `language:` 的渲染入口产出。CLI 侧另设唯一入口 `CLIFailureText.oneLine` / `block`，四档顺序与 App 侧同源，并由 `Scripts/check-cli-failure-readability.py` 钉住两件事：CLI 里不许出现绕过入口的裸英文失败输出，入口调用点不得少于台账的 57 处。

## 8.3 文案规则

**表 8-4 语言表与门禁**

| 规则 | 现状 | 依据 |
|---|---|---|
| 键的形状 | `LKey` 是 `enum`，`rawValue` = case 名；camelCase + 区域前缀（`common` / `menu` / `workspace` / `tableDesign` / `notes` / `todo` / `dataTask` / `import` / `account` / `license` / `designTheme`），实测 2 223 条 | `Core/Localization.swift:30` |
| 表的形状 | `[LKey: [AppLanguage: String]]`，两种语言各一格 | `Core/Localization.swift:2599` |
| 缺键兜底 | `table[key]?[language] ?? key.rawValue`——运行时回退到**键名本身** | 同左 |
| 真正的防线 | 两条单测：每个键两语齐全且非空；`table.count == LKey.allCases.count` | `Tests/LocalizationTests.swift` |
| 占位符 | printf 风格 `%@` / `%d` / `%.2f`；`String(format:locale:)` 按该语言的 locale 格式化 | `Core/Localization.swift:2604` |
| 占位符对账 | 六条判据：数字实参不许落 `%@` 槽（否则渲染成 `(null)`）、字符串不许落数字槽、实参数须等于占位符数、类型不明的逐条登记 | `Scripts/check-format-arguments.py` |
| 语言参数 | App 侧统一 `L(...)` → `LocalizationManager.text` → `effectiveLanguage`（宿主语境优先，其次用户选择）；Core 侧一律显式 `language:` 形参 | `App/LocalizationManager.swift`、`Scripts/check-effective-language.py` |
| 写死语言 | 逐文件登记处数上限，只许降；`CLI/main.swift` 现有 10 处 | `Scripts/check-literal-language.py`、`Scripts/literal-language-dispositions.json` |
| 文案即所见 | 语言表里不许出现 markdown 强调标记 `**`；渲染点不许再出现 `LocalizedStringKey` | `Scripts/check-copy-emphasis.py` |
| 中文棘轮 | `Core` 里「字符串字面量含汉字」的文件数与行数只许降，台账基线 73 个文件 / 730 行 | `Scripts/check-core-localization.py`、`Scripts/core-localization-baseline.json` |

语言切换是**就地**的：`.id("\(language)-\(theme)")` 让整棵树重建；系统菜单由 `MainMenuLocalizer` 在运行时逐项改写 `NSMenuItem.title`，并在切换后开一个 3 秒补刷窗口——原因是 SwiftUI 重建命令图会把系统菜单项恢复成启动语言的标题，实测在 0.1~3 秒之间被改回去。`AppleLanguages` 只对「用的时候才创建」的系统界面（打开 / 保存面板按钮、服务子菜单）生效，下一次启动才一致，这条已写进 `App/LocalizationManager.swift` 的注释，不弹窗拦人。

## 8.4 本地化矩阵

**表 8-5 哪些面必须双语**

| 面 | 语言 | 机制 | 为什么 | 依据 |
|---|---|---|---|---|
| macOS 界面（SwiftUI） | 中 / 英必须齐 | 2 223 条键，两语单测 | 界面是产品面 | `Core/Localization.swift`、`Tests/LocalizationTests.swift` |
| macOS 系统菜单 | 中 / 英 | `MainMenuLocalizer` 逐项改标题；`MenuLocalization.menuKeys` 反查 | AppKit 菜单不跟 SwiftUI 走 | `App/MainMenuLocalizer.swift`、`Core/MenuLocalization.swift:24` |
| Core 的诊断 / 建议句子 | 中 / 英（调用方传 `language:`） | `LocalizedStrings.text/format`、`describe(language:)` | 句子进界面就得分语 | `Core/DiagnosisContext.swift`、`Core/SSHTunnelProcess.swift` |
| CLI 输出 | 只中文（有意） | 10 处字面语言逐条登记 | 命令行没有界面语境 | `Scripts/literal-language-dispositions.json`（`CLI/main.swift` 条目） |
| 日志与审计 | 中文 + 技术串 | 直接写 | 排障要稳定文本，不随界面语言漂 | `App/DoyahStudioApp.swift`（`StartupLog`）、`Core/AgentAudit.swift` |
| Windows 前端 | 中 / 英（只覆盖外壳） | 自建 `DICT`，缺一种语言**编译不过**；实测 827 条 | 外壳面已双语；正文说明、服务端错误提示、领域层 hint 未覆盖 | `Platform/windows/App/src/i18n/index.ts` |
| Linux 前端 | 只中文 | 无语言切换（源码 18 处汉字） | 现状 | `Platform/linux/src-tauri/src/lib.rs` |
| 数据面：对象名 / SQL / 正文 / 导出 | 不随语言 | — | 语言只改「界面怎么说」，不改「数据是什么」 | `Core/WorkspaceTab.swift:23`、`Core/ResultExporter.swift` |
| 错误码 / SQLSTATE | 不翻译 | 原样保留 | 排查靠码 | `Core/ConnectionFailure.swift` |

由此得到一条判定标准：**双语义务的边界是「用户读到的句子」**。凡进界面的一句话都必须过 `LKey` 或带 `language:` 的渲染入口；凡落盘给别人读的（日志、审计、导出）都不跟着界面语言变。Windows 侧的 `Platform/windows/App/src/i18n/index.ts` 文件头自己把边界写清楚了——已覆盖外壳，未覆盖正文说明与服务端提示，属于已登记欠账，不是「双语做完了」。

## 8.5 日志与隐私

**表 8-6 五条记录通道的记与不记**

| 通道 | 位置 | 记什么 | 不记什么 | 依据 |
|---|---|---|---|---|
| `startup.log` | 应用数据目录，最多留 200 行 | 启动决策（接管 / 激活失败 / 继续启动）、tooltip 延迟、许可证**档位与活动栏项**、选区缓存与实编辑器不一致 | 许可证内容；口令 | `App/DoyahStudioApp.swift`（`StartupLog`） |
| `TabLog`（Output / Problem） | 内存，每页签 500 条 | 状态、错误、语法检查结果；空串跳过、相邻重复去掉 | — | `Core/TabLog.swift` |
| `agent-audit.jsonl` | 应用数据目录，JSONL 追加 | 动作、连接名、库名、模型名、SQL、风险级别、护栏发现、结局（8 档 `Outcome`） | **类型上没有密钥字段**；写入即过 `AgentAudit.redacted`，导出再脱敏一次 | `Core/AgentAudit.swift` |
| 越界日志（`EgressLog`） | JSONL | 时间、类别（4 档）、目标、触发来源、结局（3 档）、页签 | 密钥与**结果集行数据**；`target` 去掉 query 与 fragment | `Core/EgressLog.swift:37` |
| 错误呈现 | 界面 | `String(reflecting:)` 截断至 800 字符 | 超长反射转储 | `App/Utilities/ErrorPresenter.swift` |

脱敏不是「查一下有没有」，而是**整条重写一遍**：`EgressLog.append` 会新建一个 `sanitized` 的 `EgressEntry`，`target`、`origin`、`detail`、`tabTitle` 各过一次 `AgentAudit.redacted`；注释记了此前漏掉 `tabID` / `tabTitle` 的那次修补。`redacted` 用正则表替换成占位符，另给 `containsSecretLikeText` 做导出后的自检。

`AgentActionRecord` 的隐私边界落在类型上：**没有密钥字段**——审计记录从类型上就装不下 API Key。连接信息只留连接名与库名，不留口令，也不留完整连接串。

## 8.6 需要补的事实

1. `AppError.errorDescription` 是中文硬编码（`Core/AppError.swift`），界面靠 `ErrorPresenter` 换成语言表；若有调用点不经 `ErrorPresenter`，英文界面会出中文。这类调用点未清点完。
2. 表 8-2 那批类型「属于哪一级」只在调用点各自处置，逐条核到界面档位这件事没做完；`NoteStorageFailure` 只实现 `CustomStringConvertible`，写库失败最终显示的是反射串而不是它自己的描述，是否补 `LocalizedError` 待定。
3. 静默档的证据目前只覆盖 `CancellationNoise`、`EgressLog`、`TabLog`、`PluginRegistry.Degraded` 四处。
4. 缺键回退到键名（`key.rawValue`）与「不显示键名」的表述相反；现行防线是两条单测而非运行时兜底。是否加运行时兜底并落日志，待定。
5. Windows / Linux 的错误分级是否与本章三级一致，本仓无法判定；两端的 i18n 覆盖率也未纳入本仓门禁。

# 第九章 实现要点

本章写「各端怎么做」，与第三章的「必须一致」相对。带 `[独占:…]` 的节只归该端维护（8.1 macOS / 8.4 iOS 归本侧）；8.2 / 8.3 两节是**代拟的落地建议**，做法由 Windows / Linux 侧在自己的独占节内改写，契约不能换。

## 9.1 macOS 实现要点 [独占:macos]

- 多窗口原生承载，页签与窗口都是同一份会话模型的不同视图；关闭窗口不等于关闭会话。
- 数据库驱动以动态库加载，连接对象串行化访问（同一连接不并发执行两条语句）。
- 存储走系统库；迁移在启动期一次完成，失败进失败态而非半可用。
- 智能体长任务放后台队列，界面只订阅进度；取消立刻生效并回写「已取消」。

**界面设计**：侧栏 + 页签条 + 编辑区 / 结果区，采用系统分栏视图与原生工具栏；菜单栏承载全部命令（与 7.6 四处同文案对应）；快捷键走 Command 系；深浅色跟随系统；多窗口各自持有页签，关闭窗口不等于关闭会话。输入法、查找面板、拼写检查一律用系统原生能力，不自绘。

## 9.2 契约 → Windows 实现 [独占:windows]

> 本节是 Windows 侧的实现节，归属 `babyhippo`；正文按 v3.2 全书统一编号，节内引用一律指本版节号。

**归属与读法（形态 A，2026-09-27）**：本节由 **Windows 平台侧（小河马）首建并自行加 `[独占:windows]` 标记** —— 自此本节（含子节）只由该侧修改，macOS 侧只读。本节只写**实现层**：可以替换实现，**不得改变 §3 的契约与不变量**；若发现契约本身有问题 → 走提案（登记 Studio spec §6 待拍板队列，由契约侧修改）。
**本方在 Studio 仓的动作范围** = 本节 + 状态登记里的 Windows 列；契约层与 `[独占:macos]` 节只读。

### 9.2.1 技术栈与工程结构（本侧决策，2026-09-27）

| 层 | macOS 侧（现有，§9.1）| **Windows 侧（本节）** |
|---|---|---|
| 领域层（核心） | Swift `Core/`（无平台依赖）| **Rust（工作区 `windows/Cargo.toml`，crate 落 `Core/`）** —— 纯逻辑、零 UI 依赖、起步零第三方依赖、可单测 |
| 表示层 | SwiftUI + AppKit 桥接 | **Tauri 2 外壳（Windows 上用系统 WebView2）+ Vue 3 + TypeScript**（落 `App/`）|
| 无界面验证入口 | Swift `CLI/` | **`Cli/`（Rust 二进制：子命令 + 退出码表 + `--json`）** —— 等价物：无 GUI 也能验证领域层 |
| 平台适配层 | `Platform/macOS/` | **`Platform/Windows/`** —— 只有这里引 Windows 专有 API（凭据管理器 / ConPTY / 通知），Rust 侧经 `windows` crate 调用，不手写 FFI 面 |
| 测试 | XCTest（`Tests/`、`TestsPlatform/`）| **`cargo test`（Rust，含 `Core/tests/`）＋ `vitest`（前端）** |

**表示层选型与换栈留痕（可复议）**：2026-09-27 本节首建时选 **WPF**（理由 = `DataGrid` 行虚拟化成熟、分发不要求目标机预装 Windows App SDK 运行时；WinUI 3 备选）；2026-09-28 需求提出者以「界面最精致好看」为第一判据要求重排，本侧出调研 `windows/调研-技术栈-2026-09-28.md`（收敛为两条路线 + 后台三候选，并把「Linux 端被迫用 Electron」与「原生界面栈」的字面冲突作为发现上报）。**2026-09-28 开工令拍板：本侧三条线同栈 = 前端 Tauri 2 + Vue 3 + TypeScript、后端 Rust、测试 `cargo test` + `vitest`、分发 Tauri bundler（MSI / NSIS）；原 .NET 路线作废**（随之作废的还有「本机装 .NET SDK 8」这条放行）。**与契约的字面冲突（Web 外壳 vs `Doyah产品需求规格说明书.md` §1.3-1「原生界面栈」）走提案 `Docs/proposals/0004`，本侧不自行放宽契约**；§8.2 树里的 `C# / .NET 8` / `WPF` / `xUnit` 三处字样属契约层，同样在 0004 里请契约侧同步。**§9.2.6-3 的旧 WPF 基线（50 万行 × 6 列）随之作废，保留为历史留痕**，新口径按 40 万行 × 20 列复测。
**领域层边界由工程结构强制**：Rust 工作区里 `Core/` 的 `Cargo.toml` 不得依赖 GUI / 平台包（`tauri` / `windows` / `winit` 一类），判据 = `windows/Tools/check-core-boundary.ps1`（本侧自有，见 §9.2.3）。**判据面（第 25 轮按 Rust 形态重建）** = ① `Core/Cargo.toml` 的依赖段（`dependencies` / `dev-dependencies` / `build-dependencies` / `target.*.dependencies`）逐名比 GUI / 平台面清单；② `Core/**/*.rs` 的 `use` / crate 路径 / 平台专有 std（`std::os::windows`·`unix`）/ FFI 形状（`extern "C"`·`#[link(`·`windows_targets`·`libc::`），判红一律点名 `文件:行号`；③ **判据面为空即判红**（空跑不许通过 —— 工程在盘上就必须判，本项没有「跳过」档）。
**依赖（全部开源、无运行时授权费）**：**Rust 领域层起步零第三方依赖**（纯标准库；判据 `check-core-boundary.ps1` 会扫）；后续放开面 = `rusqlite`（SQLite，笔记存储分层 §3.2.3）、PostgreSQL / MySQL 驱动（§3.2 / §3.2.8，具体 crate 待选型）、Windows 专有能力经 `windows` crate；前端 = Tauri 2 + Vue 3 + TypeScript + TanStack Virtual（结果网格虚拟化）。

```
DoyahStudio/            # 现有 macOS 侧（Swift），本节不改
├── Core/  App/  CLI/  Platform/macOS/  Tests/  Scripts/  Docs/  Vendor/
Platform/windows/        # 本节对应的 Windows 侧（落点 = 同仓本块，见 9.2.6-1）
├── Cargo.toml          # Rust 工作区（2026-09-28 第 24 轮落地）
├── Core/               # 领域层（Rust：dataset / result_set / bin/grid_bench + tests/）—— 首片已落地
├── Bench/grid/         # 结果网格压力基准台（Vue 3 + TS + Vite + TanStack Virtual）—— 首片已落地
├── App/                # 表示层（Tauri 2 外壳 + Vue 3 + TS：外壳 + 结果网格 + 令牌层）—— 首片已落地
├── Cli/  Platform/Windows/   # 无界面入口 / 平台适配层 —— 未建
└── Tools/              # 闸门（13 项一条命令跑全）
```

### 9.2.2 平台适配点落地（对应 §2 的三处适配点）

1. **GUI 框架**：**Tauri 2（系统 WebView2 承载）+ Vue 3** —— 菜单 / 快捷键按 Windows 宿主约定（`P-19`）；结果网格、对象树、终端视图各自独立视图。**取值一律走设计令牌，且只有一处来源** = macOS 侧 `Core/DesignTokens.swift`：本侧不抄值（`windows/App/tools/gen-tokens.mjs` 从它生成 CSS 变量；对侧改名 / 删项 / 加项即非零退出），生成物与源不一致即判红，裸值由 `token-ratchet.mjs` 按**与 mac 基线同名**的六条规则判（`P-27` 的虚拟化方案与取值口径分开）。**第 30 轮按对侧第 77 轮「值表按主题分组」这条轴归位**：取值源由**一件**变**两件**（值表 `Core/DesignTheme.swift` + 角色与规矩 `Core/DesignTokens.swift`），生成物也由**一件**变**两件**（每主题一个变量块 `[data-theme-scheme=…]` 的 CSS + 主题集 `src/theme/themes.generated.ts`）；同名下拉的候选、「推导草案」标记与默认主题**都从生成物派生**（本侧不手抄，对侧改了主题集即 `--check` 判红），发丝线浅色档改**源侧实色**（本侧不再合成黑透明度）。
2. **系统能力**（Rust 侧经 `windows` crate 与生态 crate，**不手写 FFI**；只有 `Platform/Windows/` 引平台专有 API）：
   - **凭据存储 = Windows 凭据管理器**（Generic 类型，目标名 `doyah-studio/<连接ID>`；落地候选 `keyring`，或 `windows` crate 直调 `CredReadW` / `CredWriteW`）。语义对齐 §3.1：不落配置文件、重启可恢复、可被明确清除、不进错误信息与日志（`P-02`）。
   - **目录授权 = 用户自选目录 + NTFS 权限**（Windows 无沙箱等价物）：等价验收点 = 未授权目录的读写必须失败且给出可读原因（`P-18`）。
   - **剪贴板** = 系统剪贴板（Tauri 剪贴板能力 / `windows` crate）；超过阈值改走「临时文件 + 文件拖放」，避开大对象剪贴板限制（`P-24`）。
   - **进程与 PTY = ConPTY**（`CreatePseudoConsole`，Windows 10 1809+）跑 `pwsh` / `cmd`，Rust 侧走 **`portable-pty`**（含 ConPTY 后端），对齐 §3.3.7 终端屏幕模型与按键字节序列（`P-17`）；外部程序一律 `Command` 直起、**不经 shell 拼接**。
   - **字体与输入法** = 系统 UI 字体栈（前端 `--ds-font-stack`）+ IME（`P-20`）；**通知 / 深色跟随** = Windows 通知中心 + `AppsUseLightTheme` 跟随（`P-22`）。
3. **打包与分发 = Tauri bundler（MSI / NSIS）+ 便携形态**：签名走 `signtool` + 代码签名证书（EV 证书可直过 SmartScreen，OV 证书需累积声誉）；**首版不做自动更新**（与 macOS 侧一致）；差异登记 `P-21`；**系统 WebView 运行时依赖**登记 `P-26`（Win10 1803+ 系统自带；缺运行时必须给可读提示与补救指引、不静默失败）。
4. **数据库驱动映射（按目标能力写；作废栈的驱动名只作历史对照）**：**PostgreSQL 驱动 = `tokio-postgres`（已选定并落地）** / **MySQL 协议系驱动 = 待选** / **本地 SQLite = `rusqlite`（已在本机依赖缓存，供笔记存储分层用）**。落地证据：`windows/App/src-tauri/Cargo.toml`（依赖面）+ `windows/App/src-tauri/src/postgres.rs`（驱动接线；**驱动只在这一层**，领域层 `windows/Db` 保持零驱动）。**历史对照（旧栈的驱动名，仅备注，不作为选型依据）**：Npgsql / MySqlConnector / Microsoft.Data.Sqlite —— 那是 2026-09-28 换栈前（C#/.NET 路线）的映射，路线已作废（见 §9.2.1 的换栈留痕）。**MySQL 面在选型前不写进实现**（选型属本侧实现层，落地时在本节补登记）。

### 9.2.3 本节自己的闸门（§3.6.4 的等价实现）

| 闸门 | Windows 侧等价物 | 判据 |
|---|---|---|
| 领域层单测 | `cargo test`（Rust 工作区） | 等价覆盖；**GUI / 平台依赖不得进入领域层**（`windows/Tools/check-core-boundary.ps1` 机械判：依赖面 + 源码面 + 空跑判红；**2026-09-28 第 25 轮按 Rust 形态重建** —— 旧 C# 形态判据作废留痕，第 21~24 轮该项一直如实跳过）|
| 设计令牌棘轮 | `Tools/check-design-tokens.ps1` + **同一份基线取值** | 令牌取值属「一样」的五项之一（§1.2 平台责任表 + §4「必须一致」列），不得各写一套。**本侧落法（2026-09-28 第 26 轮）**：判据 ①② 仍由该脚本判（六条规则名与 mac 基线同名、令牌源 `Core/DesignTokens.swift` 在盘），③ 交给**表示层自己的 node 判据**（判据跟着代码走）：`windows/App/tools/gen-tokens.mjs --check`（令牌生成物 ⇄ 源**逐字一致**；分组条数写死在期望值里 ⇒ 对侧改名 / 删项 / 加项即非零退出）+ `windows/App/tools/token-ratchet.mjs`（六条同名规则的裸值棘轮，基线 `windows/Tools/design-token-baseline.json` 只降不升；**扫描集为空即判红**；外加**引用面 ⊆ 定义面** —— 前端 `var(--ds-*)` 拼错名字不报错、只是不生效，这一类静默失效单独判）**；第 30 轮按对侧第 77 轮的「值表按主题分组」补齐本侧那一半**：生成物**两件**（CSS 变量 + 主题集 TS）、取值源**两件**（`Core/DesignTheme.swift` + `Core/DesignTokens.swift`）；每主题一个变量块 `[data-theme-scheme=…]`（浅 / 深 / 跟随系统三态；**默认主题同时写在 `:root` 上** ⇒ 未写属性的场景照常），主题 id / 默认主题 / 「推导草案」标记**全部由生成物派生**；发丝线浅色档 = **源侧实色**（不再是本侧合成的黑透明度），与 mac 侧同名同值同标记 |
| 文档计数校验 | `Tools/check-doc-tables.ps1`（等价 `check-doc-tables.py`）| 派生数字与三书一致 |
| 平台中立性 | `Tools/check-platform-neutrality.ps1`（等价同名脚本）| 需求条目不得出现平台词，棘轮只降不升 |
| **独占节越界** | 复用 `Scripts/check-exclusive-sections.py --mine windows --base origin/master` | 一次改动不得落在对侧独占节内 |
| **多平台等价矩阵**（L-26 起，2026-09-27）| `python3 Scripts/gen-platform-parity.py --check` —— 列由台账 `Docs/平台实现状态.json` 决定，Windows 列已并入 SRS 计划书 §5 | Windows 列状态与台账 `platforms.windows.overrides` 一致；台账写坏（编号拼错 / 状态取值非法 / 缺 `label`·`role`·`owner`）由 `--self-test` 11 例拦 |
| **一条命令跑全** | `windows/Tools/verify-all.ps1`（**已建，2026-09-27 第 21 轮**；落点 = 同仓 `windows/`，见 9.2.6-1；同目录另有 `build.ps1` / `test.ps1` / 结果网格压力基准 / 领域层边界 / `P-*` 对账 / 令牌棘轮等子闸门；**第 28 轮实测：14 项中跑 14 / 跳过 0 / 失败 0**（本侧自此没有「跳过」档））| 不靠人记得：收尾行如实报「N 项中跑 X / 跳过 Y / 失败 Z」并逐条列出跳过项；`-RequireAll` 令**跳过即红**（§3.6.4）|
| **文档版本与取号**（契约侧 L-32 起，2026-09-27；接进 `Scripts/verify-all.sh` **第 4 项，项数仍十八**）| 判据：`python Scripts/check-doc-versions.py`；取号：`python Scripts/next-doc-version.py <文档…>` | ① 变更记录版本号唯一；② 头部版本格可判（= 变更记录最高号，或带「基线 / 首版」标注并在标注里写出当前号）；③ 队列**定义行**条目号唯一。**本侧义务**：改本节或台账行时**版本号只能由工具取，禁手抄**（上一轮本侧已撞号一次 —— 对侧保原号、本侧顺延 v2.42）。**本机实测缺口**：`--ids L` 在本机**报错退出**（依赖不入库的 `Docs/智能体助手-开发spec.md`），故本侧当前只能对**入库文档**取号 |
| **`P-*` 平台差异登记两侧对账**（契约侧 L-45 起，2026-09-27；接进 `Scripts/verify-all.sh` **第 7 项，项数仍十八**）| 判据：`python Scripts/check-p-parity.py`；**本侧入口** `windows/Tools/check-p-parity.ps1`（**已建，第 22 轮**）| ① **双向覆盖**：SRS §9.2 与 §4 的编号集合必须相等；② **同号同物**；③ **本节 §9.2.5 已落条但未并入 §4 / §9.2 即判红** —— 本侧此后新登记一条平台差异，在契约侧并入前会**保持判红**（设计意图：不许静默）；判据自带负例 **8/8** |
| **生成物一致性：发布产物版本号一个值三处一致**（契约侧 L-70 · §3.6.4 同名行；第 27 轮落）| 台账 `windows/Tools/release-version.json` + 判据 `windows/Tools/check-release-version.ps1`（本侧自有判据 = 闸门**第 13 项**；判据自测 **11 例**）| 权威处 = `App/src-tauri/tauri.conf.json` 的 `version`（Tauri bundler 把它写进 MSI / NSIS 元数据），镜像 = `App/package.json` 与 `App/src-tauri/Cargo.toml` 的 `[package] version`：发布产物版本号 `0.3.0`（三处逐字一致）；**任一处改动即判红并点名**，缺键 / 同一处出现第二个同名键同样判红。另判**与 mac 侧发布台账同源**（`Scripts/release-version.json` 的 `marketingVersion`；不等即判红，对侧 `buildVersion` 不跟随）。本侧三处**都是源**，仓内没有携带它的生成物（MSI / NSIS 与 `dist/` / `target/` 都不入库）⇒「生成物 ↔ 源」那一半**无对象**，已在台账 `generatedArtifactsReason` 里如实写明 |

> 说明：Swift 侧门禁（`verify-core.sh` / `verify-all.sh` / `build-app.sh`）在 Windows 上不可执行，本节的等价物以 PowerShell + `cargo` / `npm` 重建（2026-09-28 开工令换栈：构建 = `cargo build` + 前端 `vite build`，单测 = `cargo test` + `vitest`）；**等价性由本节 9.2.4 的「一样」清单判定**，不靠口头承诺。
>
> **本侧现在就能跑的两项（不需要 Windows 侧代码，2026-09-27 实测）**：① **多平台等价矩阵** `python Scripts/gen-platform-parity.py --check`（本端开工前，判据 = Windows 列与台账一致、且全 ⬜ 是唯一如实状态）；② **独占节越界** `python Scripts/check-exclusive-sections.py --mine windows --base origin/master`（本侧视角；**该脚本 `--mine` 默认按平台推断，Windows 上不传参数即 windows 视角**）。**`Scripts/verify-all.sh` 整条在 Windows 上跑不了** —— 第 1 / 2 / 3 / 6 / 11 项要 macOS 工具链，**第 4 项要 5 份被 `.gitignore` 排除的本地文档**（详见 9.2.6-4 与 9.2.7 的逐项实测）。

### 9.2.4 「一样」与「允许不同」的可执行口径

- **一样**：能力清单、行为语义、验收标准、**设计令牌取值**、文档单一来源（§1.2 平台责任表 + §4「必须一致」列）。
- **允许不同（必须登记）**：宿主约定、窗口与停靠、字体回退、原生控件外观、安装与签名方式、终端仿真与 PTY、沙箱与文件授权机制、系统集成（通知 / 深色跟随）—— 本节登记在 9.2.5。

### 9.2.5 平台差异登记（§4 的 `P-*` 续排；**本节 8 条已于契约侧 L-45（2026-09-27）并入 §4 与 SRS §9.2**）

`P-17` 终端仿真与 PTY（ConPTY / `pwsh`）｜`P-18` 目录授权与沙箱模型（NTFS + 自选目录，无沙箱）｜`P-19` 菜单与快捷键宿主约定｜`P-20` 字体回退与输入法｜`P-21` 安装 / 签名 / 更新｜`P-22` 通知与深色模式跟随｜`P-23` 窗口与停靠行为｜`P-24` 剪贴板大对象通道（临时文件 + `FileDrop`）。

> 每条并入 §4 时补两句：「为什么必须不同」+「用户可感知的差异」；**编号保持不变**，避免两侧对同一差异各起一个号。
>
> **并入状态与长期义务（第 22 轮）**：本节 8 条（`P-17`~`P-24`）已由契约侧 **L-45**（2026-09-27，概要设计 v2.48 / SRS v3.245）**照抄并入** §4 与 §9.2（编号未变；`P-16` / `P-25` 同批补进 §9.2），两侧现均为 `P-01`~`P-25`；对账判据 = `Scripts/check-p-parity.py`（本侧闸门第 11 项，见 §9.2.3）。
> **本侧此后新登记一条平台差异时**：契约侧并入前该判据会**判红并点名本行**（判据第 3 类）—— 这是设计意图（「已落条但未并入」不许静默），**不是故障**。处置 = 在本节写明该条待契约侧并入（必要时同时走 `Docs/proposals/`），**不要**因为判红就把条目删掉或改号。

### 9.2.6 待定与提案（本侧不擅自决定）

1. **Windows 实现的落点** —— **已定：同仓 `windows/`**。① 本侧先按通道出提案 `Docs/proposals/0002-windows-实现落点-同仓多端.md`；② 契约侧在 L-30（`991ff6f`）**同一时段落地同一落点** —— §8.2 里 `doyah-linux/` 块换成 **`windows/`** 块（层与目录照 §9.2.1，不另立一份），并写明 Linux 自用第三端不在本仓；③ 两路结论一致 ⇒ 提案标 **已采纳**（回填 `991ff6f`）、本条销账。**开工前置已清空（第 21 轮落闸门）**：闸门于 2026-09-27 落在 `windows/Tools/`（13 项一条命令跑全，见 §9.2.3 与 §9.2.7 实测表；第 22 轮由 11 项扩为 12 项、第 24 轮 12 → 13 项），**先有闸门再有功能** ⇒ 下一步 = 工程本体（§9.2.1 结构）。**留给契约侧一处小尾巴**：§8.2 那行的括注仍写着「落点见 §9.2.6-1」（该条已销账），本侧不改契约层，仅在此记明。
2. **机械设施扩多平台（队列 L-26）** —— **已落地（契约侧 `cfd91c1`，2026-09-27 第 25 轮）**，本条从「本方出提案、对侧落笔」销账：① `Docs/平台实现状态.json` 改形状 = `{default, platforms:{linux,windows}, notPlatforms:{mobile}}`，每平台带 `label` / `role` / `owner` / `overrides`，**macOS 不许进台账**（它是基线，状态来自 SRS §9.1 —— 同一个真相只允许一个来源）；② `Scripts/gen-platform-parity.py` 的**列由台账决定**（不再写死两列），SRS 计划书 §5 由四列扩为**五列**（编号 / 需求摘要 / macOS / Linux / Windows）+ 每域「与 macOS 基线一致：Linux n / Windows m 条」；③ 同批补三道判据（台账校验 / `--check` 报行号与两侧内容 / `--self-test` 11 例）。**本侧义务（从本条起长期有效）**：`platforms.windows.overrides` 与 计划书 §5 的 Windows 列必须**如实** —— 本端未开工时**全 ⬜ 是唯一可接受的状态**，不许为「看起来在推进」改 🟡；开工后状态只从台账改，改完跑 `python3 Scripts/gen-platform-parity.py` 重生成表格（手工改表会被 `--check` 判红）。
3. **结果网格性能基准**（对齐 `NFR-PERF`；**口径以 2026-09-28 开工令为准 = 40 万行 × 20 列**，三选一实现：TanStack Virtual 自绘 / AG Grid Community / Rust 侧切片喂前端）—— **本侧选定的形态 = TanStack Virtual 自绘渲染 + Rust 侧窗口取数**（前端一次只拿要渲染的那几十行）。
   **首份新栈基线已产出（第 24 轮，仪器 = 本仓 `windows/Core` 的 `grid-bench` + `windows/Bench/grid` 基准台，两者都可复跑）**：**Rust 侧**（40 万行 × 20 列，release）—— 生成 386.3 ms / 排序（40 万行降序置换）**77.8 ms** / 文本等值筛选 3.17 ms / 数值区间筛选 2.49 ms / 200 个 64 行窗口实体化 144.5 ms / 20 万次随机单元格取文本 118.9 ms / 列数据 102.9 MB（**字节估算，非进程 RSS**）；**前端侧**（无头 Chromium 151、软件光栅）—— 40 万行 × 20 列虚拟滚动 240 帧 **p50 21.3 ms / p95 31.2 ms / 均 22.0 ms（45.4 fps）/ 超 16.7 ms 204 帧 / DOM 只实体化 31 行**，首屏载入 942.1 ms（含 64 MB 数据读入），JS 堆 90.1 MB，前端排序 494.5 ms、前端筛选 13.2 ms。
   **方向性结论（第 24 轮）**：① **排序必须落在后端**（Rust 77.8 ms 对前端 494.5 ms，约 6 倍）—— 与上一份 WPF 基线的方向性结论一致；② **行虚拟化有效**（40 万行只产生 31 行 DOM）；③ 前端帧耗时仍高于 16.7 ms，但读数是**无头软件光栅**、不含 GPU 合成 ⇒ **不作真机达标依据**（真机 = WebView2 + GPU，待表示层落地后复测）。
   **旧基线（WPF 口径，2026-09-27 第 20 轮，**已随换栈作废**，仅留痕）：绑定 50 万行 16 ms / 首次布局 906 ms（实体化 48 行）/ 热重布局 0 ms / 末行 `ScrollIntoView` 17 ms / **按列排序 + 重布局 5493 ms（瓶颈）** / 筛选重布局 250 ms / 托管内存 112.7 MB；口径限制 = .NET 6、离屏 `Measure/Arrange`、单次运行、POCO 模型。**
   **口径限制（新基线，不得据此宣布达标）**：① 前端读数是无头 Chromium 软件光栅，不含 GPU 合成与输入延迟；② 数据窗口由同一块 ArrayBuffer 直接切出（Rust 侧窗口 API 的等价语义），**未含 Tauri IPC 开销**；③ 单次运行、无统计分布；④ 前端排序 / 筛选用 JS 实现，仅作与 Rust 侧的对照。**正式基准待 `windows/App` 表示层落地后在 WebView2 上复测。**
   **真机复测已落地（第 28 轮，仪器 = `windows/Bench/webview2/`，可复跑）**：真外壳（`tauri://localhost` 承载嵌入产物）+ **WebView2 153.0.4234.48 / ANGLE·Intel Iris Xe（D3D11）**（GPU 证据取自 `WEBGL_debug_renderer_info`），窗口 1280×800、网格视口 1000×669，40 万行 × 20 列 —— **空转档（不滚动、只等帧）p50 16.7 ms（60.1 fps）**（宿主本身有 60 fps 能力），**滚动 240 帧 p50 48.8~50.1 ms / p95 63.1~64.4 ms（4 轮）⇒ ≈20 fps、240/240 帧超 16.7 ms**，DOM 只实体化 38 行；首屏 559.6 ms；IPC 取 64 行 p50 6.3 ms / p95 8.1 ms（200 次）；排序（换方向重算置换）118.7 ms；引擎增量 = 布局 272 次 / 3.71 s、样式重算 272 次 / 1.14 s、任务总时长 14.2 s（≈该档墙钟 ⇒ 主线程饱和）、`ScriptDuration` 0.04 s（≈0 ⇒ **瓶颈不是 JS 逻辑**）；长任务 53 次 / 3.0 s / 最长 73 ms；进程树峰值 ≈789 MB（估算）。
   **两档诊断（第 28 轮，同一次运行内）**：① **行数与规模无关** —— 同协议下 5 万行 p50 50.3 ms、2 千行 p50 49.4 ms（40 万行 50.1 ms；复跑一轮为 54.2 / 42.6 / 48.8 ms）⇒ 三档**同一量级**，数据集规模与 1000 万像素滚动高度都不是主因；② ~~**IPC 无关** —— 把取数传输换成「缓存立即返回」后 p50 51.0 ms（对照 50.1 ms）~~ ⇒ **本条诊断已作废（第 29 轮实测：那一档根本没生效）**：它的做法是在页面里把 `__TAURI_INTERNALS__.invoke` 换成「缓存立即返回」，而宿主把该属性定义成**不可写且不可配置**（第 29 轮实测描述符 `writable:false, configurable:false`；`defineProperty` 抛 `Cannot redefine property: invoke`）⇒ 那一步**静默失效**（sloppy mode 不抛错），该档量的是**与基线完全相同**的东西；铁证一直在读数里 —— `cachedWindowCalls: 0`（产品一次都没命中补丁）。诊断②已由第 29 轮的**慢速滚动消融档**取代（见下）。
   **消融档与同轮内对照（第 29 轮）**：① **仪器自查**：把「消融档是否真的生效」变成仪器的自证 —— 收尾当场探一遍宿主是否允许替换 `invoke` 并把结论写进读数（`invokePatchability`：`{writable:false, configurable:false}` / `definePropertyOk=false`）；**消融没生效不许当读数**。② **换一个不需要改页面代码的消融档 = 慢速滚动**（步长 1px/帧 ⇒ 240 帧只走 240px，窗口每 ~26 帧才换一次；其余帧产品**照样**每帧发窗口取数、照样跑响应式与 vnode 比对，只是 DOM 文本没变）⇒ 读数 **p50 17.9 ms（46.9 fps）、布局 0.33 s / 160 次、样式重算 0.06 s / 160 次、窗口只换了 4 次**，与同轮**空转档（17.9 ms / 56 fps）同日而语**；对照同轮**基线档 79.1 ms（8.5 fps）、布局 6.39 s / 295 次（≈21.6 ms/次）、样式重算 1.99 s / 295 次** ⇒ **传输（IPC）+ 响应式 + vnode 比对 + 滚动簿记合计不足一个 vsync 周期，61 ms/帧 全部花在「把新的 38×20 个单元格文本写进 DOM + 重排版 / 重绘」上**。③**行数与规模仍无关**（5 万行 79.4 ms / 2 千行 76.1 ms，与 40 万行同量级）。④ **本轮新增一条会反噬的坑**：**跨会话漂移 > 50%** —— 同一二进制、同一窗口尺寸、同一 GPU，第 28 轮 p50 48.8~50.1 ms、第 29 轮 79.1 / **78.6 ms（同轮复跑，两次相差 0.5 ms）** ⇒ **只有同一轮内的两个数可以相减**，仪器已加**基线复跑档**供成对读；三候选比较一律同轮 A/B。
   **未达标（不得据此宣布通过）**：**19~21 fps（第 28 轮）/ 8.5 fps（第 29 轮；跨会话漂移见口径限制 ⑦）** 远低于 60 fps ⇒ 按开工令「**过了再铺功能**」，本项**不算过**；三候选取舍仍挂在 §9.2.6-5 ⑦ 之下。**下一轮的复测候选**（按第 29 轮的消融档读数，成本已被钉在「写 DOM + 重排版 / 重绘」上 ⇒ 「不改产品代码」的候选已不足以定因，候选改为**产品侧可改的三条**，每条都必须与**同轮基线**成对量）：① **行池 + 整体平移**（按滚动位移只改最上 / 最下一两行内容，其余行不动 ⇒ 每帧写入的单元格数从 ~760 降到 ~20）；② **按插槽 key 复用行节点**（当前行的 key 是**绝对行号** ⇒ 换一次窗口就整片重建，先降成「只改文本」）；③ **摊薄单格布局成本**（布局每次 ≈21.6 ms、样式重算 ≈6.7 ms，逐项查 `text-overflow: ellipsis` / 固定 flex 基宽 / `nth-child` 斑马纹等重排触发项，并给行加 `contain`）。
   **产品侧三候选的落地与同轮 A/B（第 30 轮）**：① **仪器先补两类证据**：**(a) 样式消融档** —— 不改产品代码，从**真实样式来源**提选择器并注入 `<style>` 提特异性（产品样式是 scoped、选择器带 `data-v-*`，同名类选择器特异性更低**不会生效**），档里把**计算后取值**记进读数当实证（`ablation.proof`），没生效不许当读数；**(b) 变更观察档** —— `MutationObserver` 数每帧的节点增删 / 属性写入，并按**节点名**与**目标元素的类**分组（把「写了多少 DOM」变成可读的数）；另加 `--quick`（只跑空转 + 基线 + 基线复跑）供同一坐席内交替 A/B。② **样式消融读数（在改动前的产品二进制上量，四档同一轮）**：基线 **79.3 ms**（复跑 77.6）→ `contain-row`（行 `contain: layout paint`）**78.4 ms**、`contain-cell`（按格同款）**79.7 ms** ⇒ **单独加布局 / 绘制隔离当时无效**（说明开销不在失效扩散）；`clip-cell`（格 `text-overflow: clip`，省掉省略号整段整形）**66.0 ms** ⇒ **≈13 ms/帧**；`hidden-rows`（行 `visibility: hidden`，文字不画）**52.7 ms** ⇒ **≈27 ms/帧**，且 p95 **526.7 → 72.4 ms**、长任务 **267 次 / 21.0 s → 136 次 / 7.7 s**。③ **变更观察（同一档，270 帧）**：每帧新增 **623** 个节点、属性写入 **612** 次（**全是 `title`**），`characterData` 恒为 **0** ⇒ 文本是靠**替换文本节点**写的，被写的目标几乎全是可视格（38 × 21）。④ **产品侧落地三处**（都在本侧独占节内、可直接改）：**(a) 行池 + 轮转槽位** —— 新增 `windows/App/src/grid/windowing.ts::poolSlots`（槽位 key 固定 `0..N-1`、行号按池长轮转分配 ⇒ **窗口平移一行只换一个槽位的内容**；旧写法 key 用**绝对行号**，窗口一平移就有 ≈623 个节点被建 / 删）；斑马纹从 `:nth-child(even)` 改成按**行号奇偶**的类（槽位轮转后 `nth-child` 会随滚动闪）；**(b) 取数带前瞻行**（`LOOKAHEAD = 12`）—— 只取池子那几行时，池子一平移，**新进入的行当帧还没有数据** ⇒ 先渲染一帧空白、下一帧再填真值（变更观察实测：每帧被重写的单元格从 ~231 涨到 **815**，目标类全是 `results__cell`、新增节点全是 `#text`）；多取一段前瞻行后「进入的行」当帧就有值，写一次就够；渲染只看**已取到的那一对**（起点 + 内容）、不看「正在请求的那一片」；**(c) 单格绘制** —— `text-overflow: clip`（整值靠 `title` 悬停看）＋ 行加 `contain: layout paint`。⑤ **同轮 A/B（三臂，`--quick`；基线-行池-行池+前瞻两两相邻跑，全部在 5 分钟内）**：基线 **49.6 ms**（51.3 / 49.2 · 48.0 / 50.0）→ 只落 (a) **36.5 ms**（37.3 / 35.7，−26%）→ (a)+(b)+(c) **26.2 ms**（26.5 / 26.6 · 26.2 / 25.4，**−47%**）；p95 **67.9~69.1 → 40.9~41.0 ms**，`over16` **240/240 → 168~182/240**，变更观察 **623 + 612 → 207 + 87**（每帧；`title` 76 + `style` 11），布局 **3.58~3.92 s → 1.28~1.35 s**、样式重算 **1.12~1.18 s → 0.37~0.38 s**。⑥ **仪器有地板（本轮新记，最要紧的口径）**：同一坐席的**空转档 p50 = 16.7~18.0 ms**（不滚动、只等帧）⇒ **本仪器窗口下 rAF 节奏本身 ≈17.9 ms（≈56 fps），空转就到不了 16.7 ms** ⇒ ① 本仪器**读不出 60 fps**；② 有意义的口径改成 **「内容成本 = 帧 p50 − 同轮空转地板」**：基线 ≈**31.7 ms** → 只落 (a) ≈**19.8 ms** → (a)+(b)+(c) ≈**8.3 ms**（**已低于一个 16.7 ms 的帧预算**）；③ 「是否达标 60 fps」**在本形态下无法由本仪器定论** —— 要么承认这个口径、要么换测量形态（前台窗口 / 真实输入事件），**待需求提出者拍板**。⑦ **仍未达标 / 仍未下结论**：p50 **26.2 ms（38.5 fps）** 距 60 fps 仍有距离；三选一（TanStack Virtual 自绘 / AG Grid Community / Rust 侧切片）**本轮仍不下结论** —— 但 (a)(b)(c) 三条与「自绘」同路（当前形态 = 自绘行池 + Rust 侧窗口取数）。**下一轮候选**：**(a2)** 逐格文本改成**原地写 `Node.data`**（现每帧仍有 ≈207 个节点被建 / 删 ⇒ 目标归零）；**(a3)** 去掉数据格 `title`（每帧 76 次属性写入；`clip` 后整值只剩悬停一条路 ⇒ 先判可读性）；**(b2)** **重排本身**（布局仍 1.28~1.35 s / 368 次 ≈ **3.5~3.7 ms/帧**）逐项量 flex 基宽 / 行高取整 / 斑马纹类切换。
   **与无头读数的关系（结论不许跨形态沿用，见 `P-27`）**：无头读数（p50 21.3 ms / 45.4 fps）与真机读数（p50 50.1 ms / 19.3 fps）**方向相反** —— 两者不是同形态：基准台的数据已在前端内存、无 IPC，且无头下 `requestAnimationFrame` 不受 vsync 约束（真机帧耗时被量化到 16.7 ms 的整数倍：50.1 ≈ 3 帧、63.1 ≈ 3.8 帧）⇒ **两套数字不能相减**，各自只对自己的形态负责。
   **口径限制（真机读数，同样不得据此宣布达标）**：① 单次运行（本侧手工跑了 **4 轮**：p50 = 46.1 / 49.6 / 50.1 / 48.8 ms，首屏 702.9 / 576.7 / 559.6 / 452.3 ms，IPC p50 12.1 / 5.9 / 6.3 / 5.2 ms ⇒ 轮间波动可观，**没有统计分布**）；② 仪器给宿主加了 `--disable-backgrounding-occluded-windows` / `--disable-renderer-backgrounding`（否则窗口被遮挡时 Chromium 把 rAF 压到 1 Hz，量到的是节流后的帧率）；③ 滚动由**程序化**赋值 `scrollTop` 驱动，**不含真实指针 / 滚轮事件与输入延迟**；④ 进程树内存是 `Win32_Process` 工作集求和（**估算**，含 6~7 个 WebView2 子进程），不是本应用的常驻；⑤ `performance.memory` 在 WebView2 下读数小且离散（2~13 MB），**不可用于内存结论**；⑥ 首屏 / 排序读数含数据集生成（40 万 × 20 列首次生成那一档未单列）；⑦ **跨会话漂移 > 50%（第 29 轮新记）**：同一二进制、同一窗口尺寸、同一 GPU，第 28 轮 p50 48.8~50.1 ms、第 29 轮 78.6~79.1 ms（**同轮内两次相差 0.5 ms**）⇒ **只有同一轮内的一对可以相减**，仪器已加基线复跑档；慢速滚动档的 17.9 ms 只说明「该档工作量 < 一个 vsync 周期」，**不是**「它的纯工作量是 17.9 ms」。**⑧ 仪器有地板（第 30 轮新记，最要紧的一条）**：**空转档（不滚动、只等帧）本身 p50 = 16.7 ~ 18.0 ms** ⇒ 本仪器窗口下 rAF 节奏 ≈17.9 ms（≈56 fps），**空转就到不了 16.7 ms** ⇒ ① 本仪器**读不出 60 fps**；② 有意义的口径是「**内容成本 = 帧 p50 − 同轮空转地板**」（第 30 轮三臂：基线 ≈31.7 ms → 行池 ≈19.8 ms → 再 + 前瞻取数 / 单格绘制 ≈8.3 ms）；③ 「60 fps 达标与否」在本形态下无法由本仪器定论 —— 待需求提出者拍板口径（承认这个口径 / 换测量形态）。
   **方向性结论**：本场景 **开销在排序（集合视图建序）而不在渲染或虚拟化**；实现阶段应优先考虑「后端排序 + 分页/增量取数」而不是在 50 万行上直接 `SortDescriptions`。
   **口径限制（不得据此宣布达标）**：① 运行时是 **.NET 6**（本机现有 SDK，非 8）；② **离屏** `Measure/Arrange`，不含 GPU / 渲染管线 / 输入延迟；③ 单次运行、无统计分布；④ 数据模型是简单 POCO，不是真实业务对象。**正式基准待 `windows/` 工程成型后在 .NET 8 上复测并入库**（本项**仍未闭合**）。
4. **`Scripts/verify-all.sh` 在 Windows 上不可整条复跑（2026-09-27 逐项实测）**：① 第 16 项（越界）**没有写死视角** —— `--mine` 默认**按平台推断**（`darwin → macos`，其它 → windows），本侧在 Windows 上跑它本就是本侧视角（实测：不传参数与显式 `--mine windows` 的输出逐字一致，均为 `本侧=windows`）；**结论按显式参数写进 9.2.3**（在 macOS 上跑同一条命令是 macos 视角，故不写死 `--mine`，只补显式基线）。② 第 1 / 2 / 3 / 6 / 11 项依赖 macOS 工具链（`verify-core.sh` / `build-app.sh` / `.app` 打包），本机跑不了。③ **第 4 项在本机必红、且与本侧改动无关**：`Scripts/check-doc-tables.py` 的受检清单写死 5 份**被 `.gitignore` 排除**的文档（`兼容性矩阵` / `GBase-技术验证` / `测试用例` / `发布方案` / `手工验收运行手册` —— `.gitignore` 第 27 行 `/Docs/*` + 白名单），它们只存在于 macOS 主开发机 ⇒ **任何干净克隆上报「文件不存在」**。本侧做法 = 只跑本侧有意义的项（等价矩阵 + 越界，带显式视角与基线），其余如实标「本机不可跑、非本侧改动所致」。**建议契约侧**把第 4 项的清单改成「文件存在才查 / 不存在即跳过并提示」（属 `Scripts/`，本侧不改）。
5. **表示层技术栈复议：以「界面最精致好看」为第一判据重排（2026-09-28，需求提出者提出）** —— 本侧出调研 `windows/调研-技术栈-2026-09-28.md`。**两条新前提**：Windows 版全新实现（**无迁移包袱** ⇒ 不拿「从 WPF 迁移的成本」当判据）；**Linux 第三端现用 = Rust 后台 + Electron 前台**。
   **① 本轮最要紧的发现：Linux 端的 Electron 撞契约。** `Docs/Doyah产品需求规格说明书.md` §1.3-1 明写「**原生体验**：使用各平台**原生界面栈** …… **无 JVM / 无 Electron**」，`Docs/Doyah产品能力规划说明书.md` **P6**「原生轻量 — 无 JVM / 无 Electron；不为功能引入重量级运行时」⇒ Linux 端现用栈与这两条**直接相抵**，Windows 端若跟 Linux 走 Web 外壳撞的是同一条。**另需澄清**：「原生界面栈」按字面 = 系统控件（macOS SwiftUI/AppKit、Windows WinUI/WPF），**Skia 自绘类（Avalonia）严格读法也不满足**（它满足 P6 的「无重量级运行时」）。**宽严由契约侧定，本侧只报不动笔。**
   **② 收敛为两条路线**（不再是四个并列候选）：**路线 1「守契约的原生路线」（本侧推荐）** = 前端 **WinUI 3**（原生 Fluent，唯一同时贴「原生界面栈」与「精致上限」；代价 = 随附 WASDK 运行时、无 VS XAML 设计器）+ 后台 **.NET 8 + `Microsoft.Data.Sqlite`**（同栈同进程；若接受跨语言边界也可选 Rust 留共享 core 的门）；两端前后都不共享代码。**路线 2「跨端复用路线」** = 前端 **Web（与 Linux renderer 同源）+ 系统 WebView2 外壳**（不打包 Chromium ⇒ 不触「无 Electron」字样，但仍触「原生界面栈」字面）+ 后台 **Rust**（与 Linux 同核）；收益 = renderer 与 core 有望一次写两端用，代价 = 仍须放宽契约、Electron 外壳 API 换宿主后**不存在**（只能共享 renderer 与 core，不能共享外壳）、50 万行网格走前端虚拟化须复测。
   **③ 后台三候选（SQLite、排除 Java）两条路线下都成立**：.NET 8 + `Microsoft.Data.Sqlite`〔路线 1 首选〕/ Rust + `rusqlite`〔路线 2 必选〕/ Go + `modernc.org/sqlite`。
   **④ 待拍板四项**：契约口径（放宽 / ~~Linux 改栈~~ / ~~差异登记例外~~；「原生界面栈」是否容 Skia 自绘）、Windows 路线 1 还是 2、后台 A/B/C、是否同意由本侧挂提案改契约层三处（`§3` GUI 框架行、`P-19`/`P-23`/`P-24` 的 WPF 字样、「无 Electron / 原生界面栈」的宽严）。**`§9.2.6-3` 的 50 万行基线是 WPF 口径，换前端须复测。** <!-- exclusive-allow：**2026-10-14 人类主人裁决同步** —— 本项里的「Linux 改栈」与「差异登记例外」两半**就此关闭**（原由「Linux 被迫用 Electron（公司老机器）」已随「清公司 Linux 描述」作废 ⇒ 被迫理由消失；裁决原文「**Linux 端『Electron 例外』不予开 —— 守契约**」）。**剩余待拍板 = Skia 自绘口径 / Windows 路线 / 后台档 / 契约层三处提案** 四项。（单 `T-20261014-019`；本行属本侧 `[独占:windows]` 节，直接落笔。） -->
   **⑤ 追加口径（2026-09-28 同次）**：~~**Linux 端用 Electron 是被迫** —— 那台机器是**公司资产、系统老旧、没有软件源、装不了最新版本** ⇒ …不必为此放宽总契约~~ ⇒ **2026-10-14 令：该前提作废**（不再受「公司老机器」约束，Linux 端在本仓自行实现）⇒ **技术栈按总契约「原生界面栈 / 无 JVM / 无 Electron」（§1 条 1）重新评估**，若仍要例外须按**平台差异例外**独立拍板并登记进 §9.2；相应地 **Windows 端是否允许 Web 外壳不得以 Linux 为先例**，仍须独立拍板。 <!-- exclusive-allow：人类主人 2026-10-14 令「公司那个描述都可以去掉了」⇒ 清除本节内残留的 Linux-公司口径（该行讲 Linux、却落在 [独占:windows] 节内；前门代改并留痕） -->
   **⑥ 优先序（**以 2026-09-28 开工令为准**）**：① **Studio（工作区，Windows 侧）= 高** → ② **Notes = 中**（三书 `b711548`：需求 121 条 / 看板 79 项）→ ③ **Retro = 低**（`T05` 首片按新栈需改写成 Rust）｜**记账挂起、iOS 挂起、Linux 端不投入**。**留痕**：本轮之前本侧曾把「Studio 工作区 = 高」记成误投（当作大河马侧口径）、把优先序记成 Notes 优先 —— **该判断已被开工令推翻**，以本行为准。
   **⑦ 拍板结果（2026-09-28 需求提出者开工令；实测落地见 §9.2.7）**：**本侧三线同栈** = 前端 **Tauri 2 + Vue 3 + TypeScript**、后端 **Rust**、测试 `cargo test` + `vitest`、分发 Tauri bundler（MSI / NSIS）；**能共用的能力尽量落同一个 Rust 共享库**；**Studio 开工后第一件事不是写功能，而是结果集网格压力基准（40 万行 × 20 列）—— 过了再铺功能**（本侧第 24 轮落 `windows/Core` + `windows/Bench/grid` + 闸门第 12 项）。④ 里的四项待拍板**仍然有效**（契约口径 / 路线 / 后台 / 提案）：开工令定的是**本侧栈**，没动契约层字面。
   （`§9.2.1` 属本侧节、可直接改；契约层三处**必须走 `Docs/proposals/`**。）

### 9.2.7 当前状态

**实现本体 🟡 首片已落地（2026-09-28 第 24 轮）；闸门 ✅ 已就位（13 项）**（2026-09-27 需求提出者拍板「Windows 版本的 Doyah Studio 也可以动工了」；2026-09-28 开工令把本侧栈换成 **Tauri 2 + Vue 3 + TS / Rust**）。本节 = **实现层的设计落位（首建，2026-09-27，小河马）**；口径「先有闸门再有功能」已满足 ⇒ 第 24 轮按开工令先做**结果集网格压力基准**（`windows/Core` + `windows/Bench/grid`），**过了再铺功能**。**注意：闸门与基准台都不是功能进度**，故 计划书 §5 平台等价矩阵的 Windows 列仍全 ⬜（唯一如实状态）。**第 25 轮**：把闸门里一处「如实跳过」变成「真跑」—— `check-core-boundary.ps1` 按 Rust 形态重建（读数见本节末表）。

**开工前置与首片进度**：① §9.2.6-2（机械设施扩多平台）**已就位**（契约侧 `cfd91c1`）；② §9.2.6-1（落点）**已定 = 同仓 `windows/`**（契约侧 `991ff6f` 已落 §8.2；提案 `0002` 标已采纳）；③ §9.2.3 表里的等价物已全部落到 `windows/Tools/` —— `verify-all.ps1`（**第 24 轮 12 → 13 项**：新增第 12 项 = 结果网格压力基准可复跑；第 ③④ 两项按新栈改为 `cargo` / `npm`）+ 其余子闸门；④ **首片落地物** = Rust 领域层 `windows/Core`（工作区 + 15 个 `cargo test` 用例）与基准台 `windows/Bench/grid`（Vue 3 + TS + Vite + TanStack Virtual，`vitest` 5 例、`tsc --noEmit` 干净）；⑤ `App/` `Cli/` `Platform/Windows/` **仍未建**（⬜ 不半建）。

**本机实测（2026-09-27 第 19 / 20 / 22 轮，命令与输出照录）**：

| 项 | 命令 | 实测结果 |
|---|---|---|
| 等价矩阵（Windows 列已并入 计划书 §5）| `python Scripts/gen-platform-parity.py --check` | `✅ 平台等价矩阵与现状一致（176 条；平台列 3）` · RC 0 |
| 越界门禁（不传参数 = 本机推断为 windows）| `python Scripts/check-exclusive-sections.py` | 与显式 `--mine windows` 的输出逐字一致 · RC 0 |
| 越界门禁（**推前姿势**）| `python Scripts/check-exclusive-sections.py --mine windows --base origin/master` | `✅ 越界检查通过：受检改动 29 行（含契约层），均合法（本侧=windows，契约层属 macos）` · RC 0 |
| 越界门禁（**合并对侧提交后**仍用 `--base HEAD`）| `python Scripts/check-exclusive-sections.py --mine windows --base HEAD` | ❌ **76 处假红** —— 全是**对侧刚合并进来那笔提交**的契约层改动（`HEAD` 里还没它）⇒ **merge 后推前一律用 `--base origin/master`**，或先提交 merge 再跑；本侧改动在该视图下全部合法 |
| 文档表格（受检清单含本地文档 ⇒ 本机必红）| `python Scripts/check-doc-tables.py` | ❌ 5 处，**全部为「文件不存在」**（即被 `.gitignore` 排除的那 5 份），**与本侧改动无关** |
| 文档表格（只查入库文档）| `python Scripts/check-doc-tables.py Docs/Doyah产品概要设计说明书.md Docs/Doyah产品需求规格说明书.md Docs/README.md Docs/proposals/README.md Docs/proposals/0002-*.md` | `✅ 表格校验通过（5 个文件）` · RC 0 |
| **文档版本与取号**（契约侧 L-32 新门禁）| `python Scripts/check-doc-versions.py` | `✅ 变更记录版本号唯一、头部版本可判、队列条目号唯一` · RC 0；另有 4 条**「文件不在盘上，跳过（不是「已通过」）」**提示（兼容性矩阵 / 发布方案 / 手工验收运行手册 / 开发循环-任务队列 —— 均为 `.gitignore` 排除的本地文档，与 9.2.6-4 ③ 同源）|
| 取号（入库文档，**禁手抄**）| `python Scripts/next-doc-version.py Docs/Doyah产品概要设计说明书.md Docs/Doyah产品需求规格说明书.md` | `v2.44 ← Docs/Doyah产品概要设计说明书.md`、`v3.245 ← Docs/Doyah产品需求规格说明书.md` ⇒ 本轮台账行取 **v2.44**（由工具给出，未手抄）|
| 取号（队列条目号）| `python Scripts/next-doc-version.py --ids L` | ❌ **RC 1**：`FileNotFoundError: Docs/智能体助手-开发spec.md`（该文件不入库）⇒ **本侧在该机上不可用**；队列号本侧仍按对侧既有编号顺延（见建议）|
| **闸门 · 一条命令跑全（第 21 轮新落）** | `powershell -NoProfile -ExecutionPolicy Bypass -File windows/Tools/verify-all.ps1` | `== 收尾：11 项中跑 7 / 跳过 4 / 失败 0` + 逐条列出跳过项；`RESULT: SKIP (exit 2)`（**跳过不是「已通过」**，§3.6.4）|
| **闸门 · 跳过即红** | 同命令加 `-RequireAll` | ❌ `RESULT: FAIL (exit 1)` —— 4 项跳过即判红 |
| **`P-*` 两侧对账**（契约侧 L-45 新判据，第 22 轮接进本侧闸门）| `python Scripts/check-p-parity.py`（本侧入口 `windows/Tools/check-p-parity.ps1`）| `✅ P-* 对账通过（双向覆盖 + 同号同物 + §9.2.5 无未并入条目）` —— 两侧均 `P-01` ~ `P-25`、同号同物逐条一致、**本节 8 条全部已并入** · RC 0；判据 `--self-test` **8/8**（含「§9.2.5 已落条但未并入」那一例）|
| **闸门 · 一条命令跑全（第 22 轮：11 → 12 项）** | `powershell -NoProfile -ExecutionPolicy Bypass -File windows/Tools/verify-all.ps1` | `== 收尾：12 项中跑 8 / 跳过 4 / 失败 0` + `RESULT: SKIP (exit 2)`；跳过 4 项仍是构建 / 单测 / 领域层边界 / 令牌棘轮（工程未建），逐条列出 |
| **闸门 · 注入自证（第 22 轮新增第 11 项）**| 往 §9.2.5 加一条只在本节出现的 `P-26`（不写进 §4 / §9.2）| ✅ 判据 **RC 1** 并点名 `Docs/Doyah产品概要设计说明书.md:1039：§9.2.5（[独占:windows]）已落条目 `P-26`，但它还没进 §9.2 / §4`；本侧第 11 项 `RESULT: FAIL (exit 1)` ⇒ `git checkout HEAD -- Docs/Doyah产品概要设计说明书.md` 还原后**逐字节一致**、转绿 RC 0 |
| **闸门 · 一处假红及其修复（第 22 轮）**| 修复前：`verify-all.ps1`（第 ③ 项）| ❌ 第 ③ 项 `抛异常：…check-doc-tables.py:46: SyntaxWarning: invalid escape sequence '\|'` —— 判据本身 **rc 0**（`✅ 表格校验通过（6 个文件，跳过 7 份）`），坏在 **PowerShell 5.1 把原生命令写到 stderr 的任意一行**在 `$ErrorActionPreference='Stop'` 下当**终止错误** ⇒ `_common.ps1` 改为**只由退出码决定判红**（stderr 照原样打印、不吞、不静默），修复后即 `跑 8 / 跳过 4 / 失败 0` |
| **越界门禁（第 22 轮复跑）** | `python Scripts/check-exclusive-sections.py --mine windows --base origin/master` | `✅ 越界检查通过：受检改动 18 行（含契约层），均合法（本侧=windows，**契约层属 apple**）` · RC 0 —— 尾巴的 `apple` 是本轮新现象：三副本并集收敛（L-51 `e340782`）后本仓副本的 `--contract-owner` 默认值成了 Notes 词表的 `apple`（**别名等价 `macos`，功能无碍**，仅显示串与 docstring 示例改了词表）⇒ 建议对侧把本仓副本的默认值 / 示例串写回 `macos`（本侧只报不动 `Scripts/`）|
| **闸门 · 注入自证四例**（逐例：注入 → 红 → 还原 → **逐字节一致** → 绿）| ① 台账给 Windows 登记 1 条 overrides；② 子脚本去 UTF-8 BOM；③ 夹具 `windows/Core` 开 `UseWPF` + 写 `DllImport`；④ 缺本地文档 | 四例全中：① `未开工却登记了 1 条 overrides ⇒ 不如实`；② `verify-all` 第 1 项判红、整条 FAIL；③ 两条都点名（`UseWPF` / `DllImport`）；④ `check-doc-tables.ps1 -RequireAll` = FAIL。还原后逐字节一致、门禁转绿（本侧第 21 轮复跑同 harness，逐例一致）；用例细节与另两条实测坑见 `windows/Tools/README.md` |
| **结果网格性能（50 万行 × 6 列，首份基线）**| 仓外临时 WPF 探针（`dotnet run`，**离屏**、.NET 6；工程未入库）| 绑定 16 ms / 冷布局 906 ms（实体化 **48** 行）/ 热布局 0 ms / 末行 `ScrollIntoView` 17 ms / **排序 5493 ms** / 筛选重布局 250 ms / 内存 112.7 MB（峰值 WS 246.1 MB）⇒ 详见 9.2.6-3（**瓶颈在排序**；口径限制四条，不据此宣布达标）|
| **领域层边界（第 25 轮按 Rust 形态重建）** | `powershell -NoProfile -ExecutionPolicy Bypass -File windows/Tools/check-core-boundary.ps1` | `✅ 领域层边界干净（Core 依赖 0 条 / 源文件 5 个；GUI 与平台能力只在 Platform\Windows\）` + `自测：7/7 例通过`（基线 / 依赖注入 / 源码 crate 名 / FFI 形状 / 空跑 / 逃生门 / 末例核对真仓库逐字节未变）· `RESULT: PASS (exit 0)` |
| **闸门 · 重跑（第 25 轮）** | `powershell -NoProfile -ExecutionPolicy Bypass -File windows/Tools/verify-all.ps1` | `== 收尾：13 项中跑 12 / 跳过 1 / 失败 0` + `RESULT: SKIP (exit 2)`；**跳过 1 项 = 设计令牌棘轮**（唯一剩项，等 `App/` 落地）；第 24 轮那一项判红（本地落后远端未合并的独占节越界）在合并对侧 `9cab5a9` 后已绿 |
| **闸门 · 领域层边界注入自证（第 25 轮，真仓库三例）** | ① `Core/Cargo.toml` 的 `[dependencies]` 加 `tauri = "2"`；② `Core/src/lib.rs` 加 `use windows::core::*;`；③ 同文件加 `extern "C" { fn probe(); }` | ❌ 三例全中并点名：`Cargo.toml:8 依赖面命中 GUI / 平台 crate：tauri` / `windows\Core\src\lib.rs:13 出现 use GUI / 平台 crate`（同行 crate 路径规则亦命中）/ `lib.rs:13 出现 FFI：extern "C"` ⇒ 逐例**按原始字节还原**（sha256 逐字节一致）后净跑 `RESULT: PASS (exit 0)` |

| **表示层外壳（第 26 轮首片）** | `cd windows/App && npm run build`（先 `npm run typecheck`） | ✅ 通过（`tsc --noEmit` 干净、Vite 产物 `dist/`）；**前端产物必须先于 `cargo build`** —— Tauri 编译期把 `frontendDist` 嵌进产物，顺序反了在干净克隆上必炸 |
| **表示层单测（第 26 轮）** | `cd windows/App && npm test`（vitest） | ✅ **24 例全绿**（IPC 旁路 / 窗口取数数学 / 令牌名拼法 / 两个 node 判据的真仓库复核） |
| **Rust 侧单测（第 26 轮）** | `cargo test --workspace` | ✅ **23 例全绿**（Core 15 + 外壳 8 = `query.rs` 内核 6 + IPC 双向 2） |
| **令牌层（第 26 轮接真）** | `node tools/gen-tokens.mjs --check` + `node tools/token-ratchet.mjs` | ✅ 生成物 ⇄ `Core/DesignTokens.swift` 逐字一致；棘轮未升高（**扫描集为空即判红**已内置）、引用面无悬空命名。**落网抓到两处真分叉**：`app.css` 三处叠加层变量名拼错（`var()` 拼错在 CSS 里不报错、只是不生效）+ 生成器对叠加层 / 发丝线没做 kebab 归一（同一批变量两种拼法） |
| **闸门 · 令牌层注入自证（第 26 轮，四例）** | `check-design-tokens.ps1` 第 ③ 项的两个 node 判据 | ✅ **4/4**：裸色值 ⇒ 计数超基线并点名文件；变量名拼错 ⇒ 点名「在令牌层没有定义」；令牌源改值 ⇒ 生成物漂移点名；令牌源删项 ⇒ 形状点名（`spacing：期望 7 条，实际 6 条`）。逐例按**原始字节**还原、sha256 一致、净跑绿 |
| **闸门 · 重跑（第 26 轮）** | `powershell -NoProfile -ExecutionPolicy Bypass -File windows/Tools/verify-all.ps1` | `== 收尾：13 项中跑 13 / 跳过 0 / 失败 0` + `RESULT: PASS (exit 0)`；**设计令牌棘轮不再跳过** —— 本侧自此**没有跳过档** |
| **生成物一致性判据（第 27 轮新落）** | `powershell -NoProfile -ExecutionPolicy Bypass -File windows/Tools/check-release-version.ps1` | `✅ 发布产物版本号三处逐字一致 + 与 mac 侧发布台账同源（比对点 6 处；受检 4 份文件）` + 自测 **11/11 例通过**（基线 / 三处各改一处 / 缺 `[package]` 版本键 / 权威处第二个同名键 / 跨端不等 / 跨端独立策略放行 / 锚点写错 / 判据面缺失 / 末例核对真仓库逐字节未变）· `RESULT: PASS (exit 0)` |
| **闸门 · 生成物一致性注入自证（第 27 轮，真仓库三例）** | ① `App/package.json` 的 `version` → `9.9.9`；② `App/src-tauri/tauri.conf.json` 的 `version` → `9.9.9`；③ `App/src-tauri/Cargo.toml` 的 `[package] version` → `9.9.9` | ❌ 三例全中并点名：`镜像处：windows/App/package.json:4 的值 = \`9.9.9\`，台账 = \`0.2.0\`` / `权威处：…tauri.conf.json:4 …` / `镜像处：…Cargo.toml:3 …` ⇒ 逐例**按原始字节还原**（sha256 逐字节一致）后净跑 `RESULT: PASS (exit 0)` |
| **闸门 · 重跑（第 27 轮）** | `powershell -NoProfile -ExecutionPolicy Bypass -File windows/Tools/verify-all.ps1` | `== 收尾：14 项中跑 14 / 跳过 0 / 失败 0` + `RESULT: PASS (exit 0)`；新增第 13 项 = 生成物一致性（发布产物版本号三处一致）|
| **令牌层按主题归位（第 30 轮）** | `node tools/gen-tokens.mjs --check` + `npm test`（App） | ✅ 生成物**两件** ⇄ 源**两件**逐字一致；主题 **3** 个、每主题变量块 **3 态**（浅 / 深 / 跟随系统）；`themes.generated.ts` 与源的主题集逐字一致（id / 默认主题 / 「推导草案」标记）；发丝线浅色档 = 源侧实色 |
| **闸门 · 两处假绿修复（第 30 轮）** | ① 平台中立性判据的受检三书不在盘上；② 子闸门抛异常后工作目录没还 | ❌ 两处都当场复现并修：① 判据整批**跳过**却 `exit 0` ⇒ 本侧报「✅ 通过」（受检输入不在盘上**必须先判红** ⇒ 包装补一条盘上检查）；② 子闸门 `Push-Location` 后抛异常 ⇒ **后续项全跑在错的目录**（令牌项的红被记到平台等价项头上）⇒ 包装在 `finally` 里还原并打印泄露路径 |
| **闸门 · 单测项补类型检查（第 30 轮）** | `cd windows/App && npm run typecheck` | ✅ 通过（`tsc --noEmit` 干净）。**补它的由头**：`vite build` **不做类型检查**、`vitest` 只跑被 import 到的用例 ⇒ 一个 `.vue` / `.ts` 里的类型错误此前能同时绕过 ① 与 ②（改坏了照样全绿） |
| **闸门 · 重跑（第 30 轮）** | `powershell -NoProfile -ExecutionPolicy Bypass -File windows/Tools/verify-all.ps1` | `== 收尾：14 项中跑 14 / 跳过 0 / 失败 0` + `RESULT: PASS (exit 0)` |
| **真机基准 · 起真外壳并注入驱动（第 28 轮新落）** | `cd windows/Bench/webview2 && node bench.mjs`（产物 = `target/release/doyah-studio.exe`，**须生产形态**） | `页面 = http://tauri.localhost/`；`首屏 559.6 ms · GPU renderer = ANGLE (Intel, Intel(R) Iris(R) Xe Graphics (0x00009A49) Direct3D11 vs_5_0 ps_5_0, D3D11)`；**空转 16.7 ms / 60.1 fps**；**滚动 40 万行 p50 50.1 / p95 63.1 ms（19.3 fps，240/240 超 16.7 ms）**；5 万行 50.3 ms；2 千行 49.4 ms；**IPC 隔离档 51.0 ms**；DOM 38 行；布局 272 次 / 3.71 s；样式重算 272 次 / 1.14 s；进程树峰值 789 MB（估算） ⇒ 复跑 4 轮 p50 = 46.1 / 49.6 / 50.1 / 48.8 ms（口径限制六条见 §9.2.6-3）|
| **构建入口 · 产物「生产形态」判据（第 28 轮新落，在 `build.ps1` 内）** | `powershell -NoProfile -ExecutionPolicy Bypass -File windows/Tools/build.ps1` | `✅ 生产形态核对：前端产物 2 份（index-BZikEOCC.css、index-CzsUUTBT.js）已编进 doyah-studio.exe` · `RESULT: PASS (exit 0)`；**注入自证**（去掉 cargo 调用的 `--features doyah-studio-shell/custom-protocol`）⇒ `❌ 判红：产物不是生产形态：前端产物没被编进可执行文件（缺 index-BZikEOCC.css、index-CzsUUTBT.js）—— 构建必须带 custom-protocol 特性` · `RESULT: FAIL (exit 1)`；按**原始字节**还原后 sha256 一致（`afd2b565194a`）⇒ 净跑转绿 |
| **真机基准 · 注入前的形态缺陷（第 28 轮实测）** | 不带特性开关编出来的 `target/release/doyah-studio.exe` 直接起（本仪器第一次运行） | ❌ 页面 URL = `http://localhost:5274/`（连 `devUrl`，盘上无 dev server ⇒ 空窗口）；本仪器打印 `NO_PAGE`（只认 `tauri://localhost`）。**这说明「构建入口通过」当时并不等于「产物能跑」** —— 现已由上面的判据机械拦下 |
| **真机基准 · 消融档与同轮内对照（第 29 轮新落）** | `cd windows/Bench/webview2 && node bench.mjs`（同一产物；本轮只改仪器，产品代码与二进制未动） | `invoke 可替换性：descriptor={"writable":false,"configurable":false,"accessor":false} · definePropertyOk=false`（**第 28 轮「IPC 隔离档」从未生效的机械证据**，旧读数里 `cachedWindowCalls: 0` 与它互相印证）；**慢速滚动消融档 p50 17.9 ms / 46.9 fps**（布局 0.33 s / 160 次、样式重算 0.06 s / 160 次、窗口只换 4 次、`windowShifts` 记进读数）· **同轮基线 p50 79.1 ms / 8.5 fps**（布局 6.39 s / 295 次、样式重算 1.99 s / 295 次）· **基线复跑 78.6 ms**（轮内两次相差 0.5 ms）· 空转 17.9 ms / 56 fps ⇒ 结论 = **传输 / 响应式 / diff / 滚动簿记合计不足一个 vsync 周期，61 ms/帧 全在「写 DOM + 重排版 / 重绘」**（口径限制七条见 §9.2.6-3）|
| **真机基准 · 样式消融与变更观察（第 30 轮新落）** | `cd windows/Bench/webview2 && node bench.mjs`（在**改动前**的产品二进制上量四档消融 + 变更观察档） | 消融：基线 **79.3 ms**（复跑 77.6）· `contain-row` 78.4 / `contain-cell` 79.7（**单独加隔离无效**）· `clip-cell` **66.0**（≈13 ms/帧）· `hidden-rows` **52.7**（≈27 ms/帧；p95 526.7 → 72.4、长任务 267 次 / 21.0 s → 136 次 / 7.7 s）；变更观察（270 帧）：每帧新增 **623** 节点 + 属性 **612** 次（全 `title`）、`characterData` 恒 0 ⇒ 脚本/仪器侧改动见 `Bench/webview2/README.md` |
| **真机基准 · 产品侧三候选同轮 A/B（第 30 轮）** | `node bench.mjs --quick --exe ../../target/bench-exe/<臂>.exe`（三臂交替相邻跑，全部在 5 分钟内；注意跨会话漂移 > 50%） | 基线 **49.6 ms**（51.3 / 49.2 · 48.0 / 50.0）→ 行池 + 轮转槽位 **36.5**（37.3 / 35.7，−26%）→ 再 + 前瞻取数 `LOOKAHEAD=12` + `text-overflow: clip` + 行 `contain` **26.2**（26.5 / 26.6 · 26.2 / 25.4，**−47%**）；p95 67.9~69.1 → **40.9~41.0**，`over16` 240/240 → **168~182/240**，变更观察 623 + 612 → **207 + 87** 每帧，布局 3.58~3.92 s → **1.28~1.35 s**、样式重算 1.12~1.18 s → **0.37~0.38 s**；**内容成本（p50 − 同轮空转地板 17.9 ms）31.7 → 19.8 → 8.3 ms**（口径与「读不出 60 fps」见 §9.2.6-3 ⑥⑦） |
| **闸门 · 重跑（第 30 轮）** | `powershell -NoProfile -ExecutionPolicy Bypass -File windows/Tools/verify-all.ps1` | `== 收尾：14 项中跑 14 / 跳过 0 / 失败 0` + `RESULT: PASS (exit 0)`（本轮改产品代码 + 仪器，闸门项数与清单未动） |

**本轮（第 20 轮）未改契约语义、未改 §3、未改 macOS / Linux 节**：改动只落在本节（`[独占:windows]`）与 §10 台账行（`[开放]`）；**唯一落在无标记节的一处 = 头部「版本」格的「当前」号**（按 `check-doc-versions.py` 判据同步 v2.43 → v2.44，已在**同一行单元格内**注 `contract-change：理由` 痕迹）。Windows 列状态一字未动（仍全 ⬜ —— 未开工时唯一如实状态）。第 19 轮的改动范围见 v2.42 行。**第 21 轮**（落闸门）改动范围同上：新增 `windows/`（实现层目录，不受越界门禁管辖 —— 门禁只管三书 + 本地文档）+ 本节三处 + §10 一行；**唯一落在无标记节的仍是头部「版本」格那一行**（按判据同步「当前」号，已在同一格内注 `contract-change` 痕迹）。**第 22 轮**（接契约侧 L-45 的 `P-*` 对账判据 + 修一处假红 + 销 §9.2.5 的并入状态）改动范围：`windows/Tools/`（新增 `check-p-parity.ps1`、`verify-all.ps1` 11 → 12 项、`_common.ps1` 加「只认退出码」护栏）+ 本节四处（9.2.3 / 9.2.5 / 9.2.6-1 / 9.2.7）+ §10 一行；**唯一落在无标记节的仍是头部「版本」格那一行**（同步 v2.49，同一格内注 `contract-change` 痕迹）。

### 9.2.8 插件架构落地（本侧实现层；契约依据 = §3.2.6，2026-10-13 落笔） [独占:windows]

**归属与读法**：本节属 `[独占:windows]`，**只由 Windows 侧修改**；契约层（§3.2.6 / §3.13 `FR-PLUG` 族）**只读**，要改走「待落笔清单」给契约所有者 `bluewhale`。
**本节只写实现层**：把 §3.2.6 的**六条契约**翻译成 **Windows 侧（Tauri 2 + Vue 3 + Rust）的可执行落法**。
**人类主人 2026-10-13 令（本侧口径）**：**Windows 侧独立实现**（macOS 侧已实现，只作对照）· Notes / Retro 的功能本体**取自《产品能力规划说明书》** · **本轮先做「插件骨架 + 空模块」**。

#### 9.2.8.1 现状与差距（先把事实摆平） [独占:windows]

| 项 | 现状 | 与 §3.2.6 的差距 |
|---|---|---|
| 插件清单 | **无**（活动栏四项**写死在类型里**：`App/src/shell/activityBar.ts` 的 `ActivityBarItemId = 'workspace'｜'database'｜'notes'｜'retro'`） | 契约②要求**一处声明**、界面与构建**只消费它** ⇒ 需把"写死的四项"改成"**清单驱动**" |
| Notes / Retro | **无实现**（`notes` 是占位、`retro` 未开工） | 需各落一个**模块**（本轮 = 空模块 + 骨架） |
| 活动栏可见性 | **已单点**：`resolveActivityBarItem(item, visible)` 一个判据（`activityBar.ts:100`） | ✅ **已满足契约④的一半**（"可见性只有一处判据"）—— 新增插件只需把它的项**并进清单**，不动判据 |
| 视图挂载 | **硬编码**：`App.vue` 里 `WorkspaceView` / `DatabaseView` 直接 import | 契约③要求**经"主区页签"挂点接入** ⇒ 需引入**视图注册表** |
| 领域层边界 | **已有机械判据**：`Tools/check-core-boundary.ps1`（GUI / 平台依赖不得进 `Core/`） | 可**直接复用**来守"插件不得触碰宿主内部模型" |
| 存储 | 数据库面走自己的路径；**无插件存储工厂** | 契约⑤要求"二选一并在清单声明" ⇒ 需 `StorageFactory` 挂点 |

**一句话**：**挂点骨架已有雏形（活动栏 + 单点可见性判据 + 领域层边界闸门），缺的是"清单唯一出处 + 视图注册表 + 装卸语义"这三块。**

#### 9.2.8.2 三层结构（本侧实现决策） [独占:windows]

```
① 插件清单（唯一出处）      Plugin 声明：名称/版本/入口/能力/挂点/存储归属
        ↑ 只消费，不复制
② 宿主挂点（插件唯一入口）    活动栏 · 主区页签 · 菜单 · 搜索索引 · 设置段 · 存储工厂 · 通知投递
        ↑ 插件经挂点注册自己
③ 插件模块（Notes / Retro）   每个 = 一份声明 + 一组挂点注册（本轮：空实现）
```

**分层归属（映射到本侧已有工程结构，见 §9.2.1）**：

| 层 | 落点 | 为什么 |
|---|---|---|
| **插件清单与装载**（纯逻辑，可单测） | **Rust `Core/`**（领域层，零 UI 依赖） | 清单的**校验与合并是纯逻辑** ⇒ 放领域层才能被 `cargo test` 判；且天然满足"插件不得触碰宿主内部模型"（领域层不依赖 GUI） |
| **挂点接口与注册表** | **Rust 命令 + `App/src/shell/plugins.ts`** | 命令面与界面面各一处，**薄**（只转发与注册，不写业务） |
| **插件界面** | `App/src/plugins/<id>/` | 每个插件一个目录，**可整目录拔掉** |
| **插件闸门** | `Tools/check-plugins.ps1`（新增） | 见 9.2.8.4 |

#### 9.2.8.3 宿主挂点 → 本侧具体接口（一张对账表） [独占:windows]

| §3.2.6 挂点 | 本侧落点 | 关键约束 |
|---|---|---|
| **活动栏项** | `activityBar.ts` 的项集合**改为由清单派生**（保留 `resolveActivityBarItem` 这唯一判据） | 未授权的插件项**不出现**（不是灰掉）——沿用现有 `visible` 机制 |
| **主区页签**（含 Home） | 新增**视图注册表** `App/src/shell/viewRegistry.ts`：`id → 组件（懒加载）`；`App.vue` 只查表、不再直接 import 各视图 | 视图 id **不在类型里写死**，从清单来 |
| **菜单项** | 复用现有**命令清单**（`shell/commands.ts`，已是"面板/快捷键/菜单"三者唯一出处）——插件命令**并进同一份清单** | 新命令必须在清单登记（已有纪律） |
| **搜索索引挂点** | 复用现有命令面板的目标合并（`shell/paletteTargets.ts`）；插件贡献自己的可搜目标 | 插件**只贡献条目**，不接管搜索算法 |
| **设置面板段** | 现有外观区旁新增"插件设置段"挂点 | 段由插件声明，宿主只渲染 |
| **存储工厂** | **清单里声明二选一**：① `bundled`（插件自带库/目录，宿主只给路径）② `host`（宿主提供插入式接口） | 见 9.2.8.5 |
| **通知与审计投递** | 复用现有**底部面板**（问题 / 输出）作为投递面 | 插件不自己弹窗 |

**"插件不得直接触碰宿主内部模型"怎么判**（成对判据）：
① **静态**：插件目录**不得** import 宿主内部模块（只允许挂点契约模块与公共类型）；② **运行**：拔掉插件后核心功能全绿（9.2.8.4）。

#### 9.2.8.4 可装卸语义（契约④）→ 本侧机械判据 [独占:windows]

**判据对象**：`Tools/check-plugins.ps1`（新增，接进 `verify-all.ps1` 作为一项）。**五道**：

| 道 | 判什么 | 注入自证（必须做，否则是假绿） |
|---|---|---|
| ① **清单 ⇄ 界面 ⇄ 构建 三处对账** | 清单里的每个插件，其挂点（活动栏项 / 视图 id / 命令 id / 设置段）在三处都能对上；反之界面里出现的挂点必须能在清单里找到出处 | 往界面**硬加**一个未登记的项 ⇒ 判红 |
| ② **拔掉即消失且不报错** | **拆掉**某插件的目录（或置 `enabled: false`）后：其挂点**整体消失**、**控制台无异常**、核心功能（工作区 / 数据库 / 终端）照常 | 真拔一次跑一遍（成对读数：拔前 / 拔后） |
| ③ **装回即恢复（幂等）** | 装回后与拔前**逐项一致**（挂点集合、可见性、核心数据未变） | 拔 → 装 → 对账 |
| ④ **装卸不改基础核心数据** | 装卸前后**核心数据家**的指纹不变 | 指纹对比 |
| ⑤ **插件不碰宿主内部模型** | 静态扫描插件目录的 import 面（只允许挂点契约） | 加一条违规 import ⇒ 判红 |

**纪律**：这五道里 **②③④ 必须"真拔一次"**——只看代码不下结论（沿用本侧既有纪律：**空跑不许通过**）。

#### 9.2.8.5 存储边界（契约⑤）→ 本侧落法 [独占:windows]

| 插件 | 存储归属（清单里声明） | 本侧落法 |
|---|---|---|
| **Notes** | **`bundled`（自带存储）** | 本机 **SQLite**（沿用 `FR-STD-ALL-PLUG-008` 口径：主存进库、附件二进制留文件系统）；**数据家独立**于工程数据家（`FR-STD-ALL-PLUG-004`） |
| **Retro** | 本轮**声明为 `bundled`**，具体引擎在功能本体落地时定 | 空模块阶段只落声明与目录 |

**云同步**：按契约⑤，**笔记的云同步面跟着插件走**，宿主**只提供网络与凭据能力**（凭据仍走 Windows 凭据管理器，见 §9.2.2）。

#### 9.2.8.6 本轮做什么（先骨架 + 空模块） [独占:windows]

| # | 交付物 | 判据 |
|---|---|---|
| 1 | **插件清单（唯一出处）** + 领域层校验与合并 | `cargo test`：清单解析 / 重复 id / 未知挂点 / 空清单 等负例成对 |
| 2 | **视图注册表**（`App.vue` 改为查表） | `vitest`：查表命中 / 未登记 id / 拔掉插件后查表为空 **都不报错** |
| 3 | **挂点接口**（七类，最小面） | 每类一个"注册 → 消费"的成对用例 |
| 4 | **Notes / Retro 空模块** | 各含：清单条目 + 挂点注册 + 空视图（"未开工"如实显示，**不放假界面**） |
| 5 | **`Tools/check-plugins.ps1` 五道** | 四道注入自证（逐例：注入 → 红 → 还原 → 逐字节一致 → 绿） |
| 6 | **本节 + 变更记录 + 取号跟版** | `check-doc-tables` / `check-doc-versions` rc=0 |

#### 9.2.8.7 验收判据（成对：静态一条 + 端上一条 + 否定面） [独占:windows]

| # | 判据 | 否定面（必须也判） |
|---|---|---|
| A1 | 清单是**唯一出处**：界面 / 构建 / 命令三处都能追溯到清单 | 界面硬编码一个未登记项 ⇒ **判红** |
| A2 | **拔掉即消失且不报错** | 拔掉后核心功能仍全绿；**若出现报错 ⇒ 判红** |
| A3 | **装回即恢复**（幂等） | 装回后与拔前逐项一致 |
| A4 | **装卸不改核心数据** | 核心数据家指纹不变 |
| A5 | 插件**不碰宿主内部模型** | 违规 import ⇒ 判红 |

**端上一条**（真机）：装包后**活动栏出现 Notes 入口**、点进去是"未开工"空态、**控制台无异常**；把插件目录临时移走后**入口消失且仍无异常**。

#### 9.2.8.8 待定与报请（本侧不擅自决定） [独占:windows]

1. **Retro 的功能本体出处**：契约只说"回放"，**具体功能条目**需从《产品能力规划说明书》/ SRS 取。**本轮按"空模块"处理**；本体落地前**报请人类主人指定条目范围**。
2. **插件清单的物理形态**（Rust 常量 / 独立 `plugins.toml` / 生成物）：**本侧实现细节**，本节先按 **Rust 单一常量 + 生成前端可见清单** 落；若契约侧要跨端统一形态，走「待落笔清单」。
3. **`FR-PLUG` 族与 §3.2.6 的隶属关系**：§3.2.6-⑥ 已写明"本节是前身条文的上升"，本侧**按 §3.2.6 落**；若契约侧后续拆分/合并该族，本侧跟版。

#### 9.2.8.9 本轮明确不做（避免误会） [独占:windows]

- **不做** Notes / Retro 的功能本体（本轮 = 骨架 + 空模块）
- **不做** 独立进程 / IPC / 可卸载组件包（`FR-STD-ALL-PLUG-001` **明文禁止**："同进程内模块装配"）
- **不做** 插件独立授权与单独开关（`FR-STD-ALL-PLUG-006`：一套许可证覆盖三个能力位）
- **不动** 契约层与 `[独占:macos]` 节；**不参照** macOS 实现细节（只读契约，实现自决）

## 9.3 契约 → Linux 实现 [独占:linux]

> 本节是 Linux 侧的实现节，归属 `hugehippo`（本侧）；正文按 v3.2 全书统一编号，节内引用一律指本版节号。

> **本节归 Linux 侧（`babyhippo`）· 本仓自行落笔**（2026-10-14 人类主人令「Doyah Studio 全量 PC 端还要补一个 Linux 平台，小河马负责的」—— 原「三书带出本仓、平台设计层文字回传后贴入」的环节**作废**）：本端平台设计层（技术栈 / 构建入口 / 打包形态 / 桌面集成方式）由本侧按下列各条**直接落笔**。
> **本节内容不由 macOS 侧 / Windows 侧决定**；其它侧若代笔，须在原行或提交信息带上豁免注记（`exclusive-allow` 加理由）。

**状态**：🟡 **设计层已落**（2026-10-14 · 派单 `T-20261014-021` —— 人类主人 2026-10-14 裁决「Linux 端技术栈 = Tauri」，概设 §2 GUI 框架行 v2.169 由契约所有者落笔）；**实现面 🟡 骨架已落地**（骨架 `Platform/linux/{README.md,build.sh}` + **应用工程** `src-tauri/`（`Core` / `Cli` / `Platform/Linux` 三层）+ **前端同源装配** + 本端判据 `Tools/check-linux-skeleton.py` 均已落 —— 派单 `T-20261014-016`；**真构建与真绑定未跑**，七项未验证见 §9.3.6 末的「未接网清单」与 `Platform/linux/README.md`）。原「要落的 5 项」清单**已由本节内容兑现**（逐项对应：1 → §9.3.1 · 2 → §9.3.2 / §9.3.3 · 3 → §9.3.4 · 4 → §9.3.5 · 5 → §9.3.6）。

### 9.3.1 技术栈与工程结构 [独占:linux]

| 层 | macOS 侧（§9.1） | **Linux 侧（本节）** |
|---|---|---|
| 领域层（核心） | Swift `Core/`（无平台依赖） | **Rust**（落 `Platform/linux/src-tauri/Core/`）：纯逻辑、零 UI 依赖、可 `cargo test` |
| 表示层 | SwiftUI + AppKit 桥接 | **Tauri 2 外壳（系统 WebView = WebKitGTK `webkit2gtk-4.1`）+ Vue 3 + TypeScript** —— **前端与 Windows 侧同源**（同一套 `Platform/windows/App/`） |
| 无界面验证入口 | Swift `CLI/` | **`src-tauri/Cli/`（Rust 二进制：子命令 + 退出码表 + `--json`）** |
| 平台适配层 | `Platform/macOS/` | **`Platform/linux/src-tauri/Platform/Linux/`** —— 只有这里引 Linux 专有依赖（WebViewGTK / 密钥环 / PTY），不手写 FFI |
| 测试 | XCTest（`Tests/`） | **`cargo test`（Rust）+ `vitest`（前端）** |

**版本口径**：**Tauri 2.x**（与 Windows 侧同大版本 —— 前端同源、命令面与插件面一致）；**Rust toolchain ≥ 1.77**（Tauri 2 下限）；**Node ≥ 20 + `npm`**（前端，与 Windows 侧同包管理器）—— **骨架片就地订正**：原文写 `pnpm`，而**实体前端** `Platform/windows/App/` 里是 `package-lock.json`、Windows 侧 `Tools/build.ps1` 用 `npm run build` ⇒ 按实体前端收口为 **npm**（`build.sh` 探测项与 `tauri.conf.json` 的 `beforeBuildCommand` 同批跟版）。

**前端复用边界**（哪些与 Windows 侧共用 / 哪些 Linux 特有）：

- **共用（不另写一份）**：`App/` 前端整体 —— Vue 3 组件树、设计令牌层、领域模型的前端投影、结果网格与对象树视图、语言表读取、Tauri 命令面（IPC）调用的形状。**两侧是同一套前端源码**，Linux 只换外壳与平台适配层。
- **Linux 特有**：`src-tauri/` Rust 侧的平台适配 —— WebView 运行时依赖探测与**可读缺失提示**、系统密钥环后端、PTY 与 shell 探测、`.desktop` 集成（文件关联 / 图标）、字体与输入法。
- **前端不得按平台分支**：平台差异只能通过**取值**表达（命令面的平台能力表），不许在组件里写「若 linux 则…」—— 与 §9.1 语言登记表 / §9.2.4「一样与允许不同」同一条口径。

**形态红线**（继承契约，本节不另立）：**不打包浏览器内核**、**不引入虚拟机运行时**（§1.2 的形态红线；与 §2 GUI 框架行已写死）⇒ 承载面只能是**系统 WebView**；该前置缺失时**给可读提示与补救指引，不静默失败**（与 Windows 侧 `P-26` 同一口径）。

**工程结构边界**：`src-tauri/Core/` 的 `Cargo.toml` **不得依赖 GUI / 平台包**（Tauri / GTK / WebViewGTK 一类）—— 与 Windows 侧 `check-core-boundary` 同形的判据面**已落** = `Platform/linux/Tools/check-linux-skeleton.py` 的 B / C 两条（依赖面逐名比清单 + 源码面点名 `文件:行号` + **空跑判红**），见 §9.3.6。

**工程结构（盘上实物 · 2026-10-14 骨架片 `T-20261014-016`）**：

| 路径 | 层 | 内容 |
|---|---|---|
| `src-tauri/Cargo.toml` | 工作区 + 外壳包 | 成员 = `Core` / `Cli` / `Platform/Linux`；外壳包 `doyah-studio-linux-shell`（bin `doyah-studio`）|
| `src-tauri/Core/` | 领域层 | **零第三方依赖**：交付物身份四项（§9.3.3）+ 能力取值解析（「前端不得按平台分支」的落点）· `cargo test` **9 例** |
| `src-tauri/Cli/` | 无界面入口 | 子命令 `capabilities [--json]` / `version` + 退出码表（0 完成 / 1 用法错 / 2 有缺失项）· 零第三方依赖 |
| `src-tauri/Platform/Linux/` | 平台适配层 | 六项能力探测（**存在性检查，不手写 FFI**）+ 可读缺失提示 · `cargo test` **4 例** |
| `src-tauri/tauri.conf.json` | 表示层外壳 | `frontendDist` = `../../windows/App/dist` · `devUrl` = `http://localhost:5274`（**前端同源指向**）|
| `Tools/check-linux-skeleton.py` | 本端判据 | 骨架 / 领域层边界 / 前端同源五条；**空跑判红** · `--self-test` **9/9** |

### 9.3.2 构建入口（一条命令可复跑） [独占:linux]

```
Platform/linux/build.sh --deps     # 依赖探测（只读；缺项逐条点名）
Platform/linux/build.sh            # 构建 + 打包，收尾打印交付物身份四项
```

**依赖**（Debian / Ubuntu 参考安装行由脚本自己打印）：`cargo`（≥ 1.77）· **`libwebkit2gtk-4.1-dev`**（系统 WebView 前置）· `libgtk-3-dev` · `librsvg2-dev` · `libayatana-appindicator3-dev`（可选，缺则不打托盘）· Node ≥ 20 + `pnpm`。

| 退出码 | 含义 |
|---|---|
| 0 | 完成 |
| 1 | 依赖缺失（`--deps` 判定；缺项逐条点名） |
| 2 | **非 Linux 宿主 ⇒ 如实拒绝**（本入口不在别处假装能构建） |
| 3 | 应用骨架未落地（`src-tauri/` 不在盘上；属骨架落地片，不是脚本故障 —— **2026-10-14 骨架落地后该档不再命中**）|
| 4 | **同源前端缺失**（`Platform/windows/App/` 不在盘上 ⇒ 前端同源前提不成立）|

**实测读数（2026-10-14 · 宿主 = Windows 开发机，`uname -s` = `MINGW64_NT-10.0-26300`）**：

| 命令 | rc | 读数 |
|---|---|---|
| `bash Platform/linux/build.sh --deps` | **1** | `cargo` / `node` / **`npm`** 在；`webkit2gtk-4.1` / `gtk+-3.0` / `libayatana-appindicator3-0.1` **缺 3 项**（逐条点名）+ 参考安装行 |
| `cargo test`（Core / Platform / Cli，`Platform/linux/src-tauri`） | **0** | Core **9 例** + Platform **4 例** 全过（Cli 只编译，无单测）|
| `python Platform/linux/Tools/check-linux-skeleton.py` | **0** | 骨架 / 边界 / 同源三条干净（工作区 3 层 · Core 依赖 **0** 条 / 源文件 3 个）· `--self-test` **9/9** |
| `doyah-studio-cli capabilities` | **2** | 本机六项如实读数：`present` = `pty` / `clipboard`（X11）；`missing` = `webview` / `secret-service` / `notifications` / `tray` |
| `bash Platform/linux/build.sh` | **2** | 非 Linux 宿主 ⇒ **如实拒绝**，并指向对应端的入口 |

**未验证（如实）**：真构建与安装包**未跑** —— 本机非 Linux 宿主、无 WebKitGTK 开发包；本节的构建判据要到 **Linux 宿主 / 公司验机场地**上取读数（沿用「不填个人凭据」纪律）。该两项属**骨架落地片**的判据，**本片不当绿**。

### 9.3.3 打包形态 [独占:linux]

**选两种**：**`.deb`** + **`.AppImage`**。

| 形态 | 给谁用 | 为什么 |
|---|---|---|
| **`.deb`** | Debian / Ubuntu 系（内测与常见发行版） | 系统包管理器安装、**依赖自动解析**（WebKitGTK 这类前置不必手装）；升级 / 卸载可被系统管理 |
| **`.AppImage`** | 其余发行版 / 免安装试跑 | **单文件便携、跨发行版**；仍依赖系统 WebView 的存在与版本，缺则**给可读提示**（同上「不静默失败」） |

**交付物身份四项**（**目录 / 标签 / `sha256` / 构建时刻**）由 `build.sh` 收尾打印，**身份卡随包走**；**目前只有脚本出口、尚无实物**（应用骨架未落地）。

**本轮不选的形态**：发行版原生包（`rpm` / `pacman`）、Flatpak、Snap —— 需求是「本仓自用的全量 PC 端第三端」，先收两种最常用形态；内测若确需再补，走 §9.3.6 的待定项。

### 9.3.4 桌面集成方式（对应 §3 契约的落地） [独占:linux]

| 面 | Linux 落法 |
|---|---|
| **菜单** | 应用内菜单栏（Tauri 2 menu API）；**菜单项集合与 Windows 侧同形**，宿主差异（全局菜单 / GTK 主题菜单样式）由外壳承担 |
| **快捷键** | 与 Windows 侧**同键位**；宿主占用导致的冲突**逐条登记**（见 §9.3.6 待定项），不在本节另发明一套键位 |
| **文件关联** | 走 `.desktop` 的 `MimeType`（笔记库 / 导出件后缀）；`.desktop` 只做**宿主投递**，关联后的行为仍归领域层 |
| **深色跟随** | 跟随系统主题（WebKitGTK `prefers-color-scheme` + 宿主 `gtk-application-prefer-dark-theme`）；**深浅两态都用主题令牌**，不自造色（§3.3.8 / §3.3.8 同口径） |
| **凭据** | **系统密钥环**（Secret Service API，落地候选 `keyring` crate；GNOME Keyring / KWallet 走同一接口）—— 语义对齐 §3.2.7：不落配置文件、重启可恢复、可被用户自行清除；**无可用密钥环时如实报错，不回落明文** |
| **目录授权** | Linux 无沙箱等价物 ⇒ **用户自选目录 + 文件权限**：未授权目录的读写**必须失败并给出可读原因**（与 `P-18` 同口径） |
| **终端** | PTY（候选 `portable-pty`）+ shell 探测（`$SHELL`，`/bin/sh` 兜底）；屏幕模型仍走 §3.3.7 契约，不手写 `termios` |
| **通知** | 走系统通知（freedesktop 通知规范）；**权限未授予时如实降级并说明**，不静默丢 |
| **剪贴板** | 系统剪贴板（Tauri clipboard 面）；多选区 / 富文本口径与 §3 一致 |

### 9.3.5 与 §3 契约的对应关系表 [独占:linux]

| §3 契约面 | 本端落点（规划模块） |
|---|---|
| §2 平台适配点 ①：GUI 框架 | `src-tauri/` 外壳（Tauri 2 + WebKitGTK）+ 复用 `App/` 前端 |
| §2 平台适配点 ②：系统能力（凭据 / 目录授权 / 终端 / 通知 / 剪贴板） | `src-tauri/Platform/Linux/`（**只有这一层引 Linux 专有依赖**） |
| §2 平台适配点 ③：打包与分发 | `Platform/linux/build.sh` → `.deb` / `.AppImage` + 身份四项 |
| §3.2.7 连接配置与凭据 | `src-tauri/Platform/Linux/`（系统密钥环） |
| §3.3.7 终端屏幕模型 | `src-tauri/Core/`（屏幕模型）+ 平台层 PTY |
| §3.3.3 工作区（用户自选目录） | 平台层目录授权 + `Core/` 的路径契约 |
| §3.3.8 / §3.3.8 设计令牌与编辑面底色 | 复用 `App/` 前端令牌层（**不另立一份**） |
| §3.2.12 结果区客户端视图 | 复用 `App/` 前端视图面 |
| §3.1.10 MCP 互操作 / §3.2.6 插件装配 | `src-tauri/` 宿主挂点（按 §3.2.6 装配契约） |
| §3.2.3 笔记存储分层 | `src-tauri/Core/` + 本地 SQLite（**进程内零网络出口**） |
| `FR-STD-ALL-PLUG-005`（Linux 装配笔记且**本地离线**） | 随包装配笔记模块；数据只落本机 SQLite（笔记自己的数据家）、不同步 / 不遥测 |

> **边界**：上表是**落点规划**（模块尚未落地），不是「已实现」；实现按片推进，每片回执按 D5「证据 = 命令输出」给读数。

### 9.3.6 自检与待定项 [独占:linux]

**自检命令（本端）**：

| 面 | 命令 | 本轮读数（2026-10-14） |
|---|---|---|
| 依赖 / 构建入口 | `bash Platform/linux/build.sh --deps` · `bash Platform/linux/build.sh` | rc=1（缺 3 项）· rc=2（非 Linux 宿主，如实拒绝）—— 见 §9.3.2 |
| 一条命令跑全（本仓闭环） | `DOYAH_PLATFORM=linux bash Scripts/verify-all.sh` | **待 Linux 宿主上取读数**（macOS 专属项按 §3.6.4 如实分栏跳过） |
| 越界（本节归属） | `python Scripts/check-exclusive-sections.py --mine babyhippo` | rc=0（本节改动全在 `[独占:linux]` 内） |
| 归属登记 | `python Scripts/check-path-ownership.py --actor babyhippo` | rc=0（`Platform/linux/` 已登记，派单 `T-20261014-016`） |
| **本端判据**（骨架 / 领域层边界 / 前端同源） | `python Platform/linux/Tools/check-linux-skeleton.py --self-test` | **rc=0** · 骨架 / 边界 / 同源三条干净（工作区 **3** 层 · Core 依赖 **0** 条 / 源文件 **3** 个）· 自测 **9/9**（含空跑判红 · 前端另存一份判红 · `frontendDist` 指错判红）|
| 平台等价矩阵 | `python Scripts/gen-platform-parity.py --check` | rc=0（矩阵与现状一致） |

**待定项（本侧不擅自决定）**：

1. **快捷键宿主冲突清单**：与 Windows 侧同键位在 GNOME / KDE 下的实际占用（如 `Super` 组合）**待端上实测后逐条登记**，不预先发明替代键位。
2. **托盘指示器降级形态**：`libayatana-appindicator3` 在部分发行版缺席 ⇒「无托盘时降级成什么」**待定**（属产品取舍 → 报前门 / 人类主人裁）。
3. **WebView 版本下限**：WebKitGTK 各发行版版本跨度大，「低于哪个版本给什么提示」待定 —— 与 Windows 侧 `P-26` 同族，口径宜两侧一致。
4. **验机场地**：Linux 真构建与真验机在何处跑，按人类主人 2026-10-14 令「公司环境仍可作构建与验机场地」执行；**不填个人凭据**纪律照旧。

**不可动的**：§3 契约节（架构骨架、数据契约、接口不变量）。Linux 端**必须实现契约**，只在平台层自由。

**本节整节豁免已销（队列 L-40 关闭 · 2026-10-14）**：原「首建占位整节豁免」注记（整节豁免标记）的前提 = 「等 Linux 侧**回传**、首建占位」；2026-10-14 人类主人令后该环节作废（本仓自行落笔），故**豁免注记行已删除**，本节自此恢复 `[独占:linux]` **严格判定**。

## 9.4 iOS 实现要点 [独占:ios]

- 只做智能体与笔记两面（能力书已定：iOS 不做数据库域）；数据库域不在此端出现，相关入口不显示而不是显示后报错。
- 后台受限：抓取在打开时补跑，补跑结果与桌面端同构，去重规则共用。
- 笔记正文与桌面端同格式，导入导出走系统分享面，内容逐字节一致。
- 长任务在离开应用时转「可恢复」状态，回到前台继续，不从头重来。

**界面设计**：单栈导航（列表 → 编辑 → 结果），底部工具条放主操作；手势承担返回与撤销；不做多窗口与平板两栏（能力书已定不做）；导出走系统分享面，内容与桌面端逐字节一致。

## 9.5 共用件

| 共用件 | 形态 | 一致性要求 |
|---|---|---|
| 契约常量 | 一份定义，各端编译期引用 | 逐字一致（第三、四章） |
| 错误分类 | 一份枚举 | 分类与可重试标记一致 |
| 导出渲染 | 一份实现 | 同一数据两次导出逐字节相同 |
| 视觉数值 | 一份 token 表 | 数值一致，观感差异走 `P-07` |
| 文案键表 | 一份键定义 | 键一致、译文可不同 |

# 第十章 验收映射

本章回答一个问题：**每条需求去哪一章找设计依据、用什么方式证明它做到了**。条数由《需求规格说明书》机器对账得出（`Scripts/check-req-ids.py` 同一份定义域），**不手写**。

## 10.1 需求域到设计落点

| 产品线 | 需求条数 | 域数 | 设计落点 | 证明方式 |
|---|---|---|---|---|
| 智能体 `AGT-*` | 68 | 23 | 3.1（3.1.1~3.1.23） | 场景回放 + 单测（循环终止、权限边界、工具失败、上下文压缩） |
| 通用与工程 `STD-ALL-*` | 44 | 6 | 3.2.1~3.2.6、6.1 | 单测（接口契约）+ 构建产物比对 + 三仓脚本自检 |
| 数据库 `STD-DB-*` | 111 | 11 | 3.2.7~3.2.17、5.1~5.4、6.2 | 真实库联调（连接 / 执行 / 取消 / 分页 / DDL / 导入导出 / 锁诊断） |
| 工作台界面 `STD-WS-*` | 72 | 10 | 3.3.1~3.3.10、第七章、6.3 | 点击点验 + 单测（保存与撤销语义）+ 视觉数值核对 |
| 笔记 `NTS-*` | 19 | 14 | 3.4.1~3.4.14、5.2 | 点击点验 + 跨端数据互换（同一份导出 diff） |
| 交易复盘 `RTR-*` | 82 | 18 | 3.5.1~3.5.18、5.4 | 同一批数据跑两次逐字段比对 + 缺数据表现 |
| 横切与闸门 `ALL-GATE-*` | 122 | 10 | 3.6.1~3.6.7、第四、七、八章 | 门禁脚本 + 故障注入 + 计时（不靠眼看） |
| **合计** | **518** | **92** | — | — |

## 10.2 覆盖账：92 个域 ↔ 89 个契约节，差的三口在哪

差 3，逐条说清，**不是漏写**：

| 域 | 处理 | 理由 |
|---|---|---|
| `ALL-GATE-RISK` | 不设契约节 | 风险登记是台账，不是设计约束；落点在 11.1 与《开发计划书》§3 |
| `ALL-GATE-COMP` + `ALL-GATE-MAINT` | 合并为 **3.6.4 兼容性与可维护性** | 两者都是「改动不破坏既有行为」，同一套判据，拆两节会出现两处说法 |
| `ALL-GATE-UI` | 并入 **第七章 界面设计（契约部分）** | 跨端视觉与可及性的一致性判据属于界面章，留在横切章会被当成纯非功能条目看待 |

## 10.3 容易「以为验过了」的三处

1. **跨端一致**：截图看着一样不算 —— 要拿同一份输入在两端的产物 **diff 一次**（导出的笔记、执行的 SQL 结果、复盘报告）。
2. **迁移**：只在干净库跑过不算 —— 要拿真实旧数据跑一次，并验证失败回滚。
3. **确定性**：跑一次结果对不算 —— 同一批数据跑两次，逐字段比对，尤其浮点聚合与排序。

# 第十一章 附录

## 11.1 非功能需求的设计归属

| 域 | 条数 | 设计落点 | 判据落点 |
|---|---|---|---|
| `PERF` | 8 | 2.3 运行时间、5.4 索引、第三章各域的预算条款 | 计时（冷启动、执行、保存、搜索） |
| `REL` | 14 | 5.3 迁移、7.1 错误分级 | 故障注入（断库、损坏数据、连点） |
| `SEC` | 10 | 5.2 凭据、6.2 外部接口 | 代码审查（无多余权限）+ 抓包 |
| `COMP` | 8 | 第四章差异表、5.3 版本兼容 | 兼容矩阵逐格登记 |
| `MAINT` | 6 | 2.1 依赖方向、2.4 技术栈 | 代码审查 + 依赖锁定检查 |
| `USE` | 5 | 6.3 用户接口 | 点击（首次使用无需说明） |
| `UI` | 1 | 8.5 视觉 token | 数值核对 |
| `LANG` | 5 | 7.3 本地化 | 键完整性 + 缺键回退 |
| `AI` | 12 | 3.1 智能体契约、6.1 模型接口 | 场景回放 + 用量核算 |
| `RISK` | 69 | **不进契约层** | 归计划书与风险登记册（本书只在 10.2 登记设计侧未决） |

`RISK` 刻意不进契约层：风险册管「可能出什么事」，契约管「各端必须做成什么样」；把风险写成契约会让契约变成愿望清单。

## 11.2 尚未解决的问题与回流

| 项 | 现状 | 去向 |
|---|---|---|
| 智能体循环的并发上限 | 未定 | 由 `AGT-CORE-LOOP` 细化判据后补契约 |
| 跨端会话迁移的冲突合并 | 未定 | 由 `AGT-UX-SYNC` 与 `NTS-NOTE-SYNC` 合并定义 |
| 超大结果集的分页与导出边界 | 未定 | `STD-DB-RES` 与 `STD-DB-IO` 联合细化 |
| 回测的统计口径（样本内外） | 未定 | `RTR-RSR-BACKTEST` 细化后再入契约 |
| 插件装配形态的第三方扩展点 | 已定「同进程模块、不做可卸载第三方包」 | 无欠账，若将来要扩展需先改能力书 |

三种处理方式的选择标准：能被用户在界面观察到的行为 → 回流成需求；只在工程约束上成立的（如「迁移必须幂等」的实现手法）→ 判为实现纪律并在正文写由头；两者都说不通的 → 删除。

## 11.3 与需求书的对应关系

本书不新增需求编号。出现「设计有、需求无」时，按 11.2 的三条处理并留记录；出现「需求无、设计也没有」时，说明需求条目的设计归属缺失，属本书的欠账，登记在 10.2。

派生关系是单向的：能力书 → 需求书 → 本书 → 代码。反向修改必须先动上游，再回流本书；直接从代码改本书会制造「设计与需求两张皮」。
