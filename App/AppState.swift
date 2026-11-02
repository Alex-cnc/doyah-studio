import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers
import DoyahCore
import DoyahPlatform

/// **笔记编辑器的模式**（片 `N2-3a`「单击预览」· 人类主人令 `T-20261007-004` 第三节第 3 条）。
///
/// · `.preview` —— 在列表里**单击**一条 ⇒ 右栏打开这一条**看内容**，**正文只读**；
/// · `.edit` —— 「新建」/「改」，以及**双击进编辑**（片 `N2-3b`）⇒ 正文可编辑
///   （「新建」/「改」的语义与本片之前一字未改）。
///
/// **只此一处**判「正文那一块可不可编辑」：视图（`Plugins/Notes/Views/NotesPanel.swift` 的
/// `NotesEditorView`）与判据（`TestsUISnapshot/NotesLayoutProbeTests.swift`）读的是同一个值。
///
/// **`N2-3a` 只改了一半**（单击 ⇒ 预览）；**双击进编辑**是片 `N2-3b` 补上的那另一半
/// （人类主人令 `T-20261007-004` 第 4 条：「双击编辑 + 顶部编辑工具条」）。
/// 两个双击入口共用同一件事、**不是两套判断**：内容区双击走 `beginEditingCurrentNote()`
/// （内容已经从预览装好了 ⇒ 只翻模式），列表行双击走既有的 `edit(_:)`（那一刻手上有一条笔记
/// ⇒ 内容与模式一起给）。
enum NoteEditorMode: Equatable {
    case preview
    case edit
}

struct QueryTab: Identifiable {
    let id: UUID
    var title: String
    var sql: String
    /// 多语句执行时，每个返回结果集的语句对应一个 QueryResult。
    var results: [QueryResult]
    var selectedResultIndex: Int
    var isExecuting: Bool
    /// 这张结果是从哪张表浏览出来的（FR-DATA-06 的跳转要它来判外键）。
    ///
    /// 只由「浏览数据」这类**明确知道表名**的入口写入；手写 SQL 的结果没有它 ——
    /// 靠解析 SQL 猜表名会把跳转指向错表，宁可说"不知道"。
    var sourceTable: DatabaseObjectRef?

    /// 是否有**可展示的表格结果** —— 决定结果区要不要出现。
    ///
    /// 只认「有列的」结果集：`CREATE TABLE` / `INSERT` 这类没有结果集，它们的交代在
    /// Output / Problem 页签里，硬在结果区摆一张空表只是噪音。
    var hasTabularResult: Bool {
        results.contains { $0.columnCount > 0 }
    }

    /// 每个结果集的「出处」标签，与 `results` 一一对应（例：`第 2 条语句返回 5 行 × 3 列`）。
    ///
    /// **刻意不写进 Output 日志**：行 × 列 结果表自己就展示了，写进日志会让 Result 与 Output
    /// 两个页签看起来重复。它作为结果集的出处，挂在 Result 页签的表头。
    /// 注意没有 `didSet` —— 这正是它不进日志的原因。
    var resultSummaries: [String] = []

    /// 执行输出日志（下方面板 Output 页签）。
    ///
    /// 用 `didSet` 在**模型层**拦截，而不是去改那 70 多处赋值点：
    /// 那些地方遍布 AppState（执行 / 导出 / 建库 / 权限 / 数据任务…），逐个改必漏。
    /// 追加规则本身在 `Core/TabLog.swift` 里，是可单测的纯函数。
    var outputLog: [TabLogEntry] = []

    /// 问题日志（下方面板 Problem 页签）：执行错误与语法检查失败、告警。
    var problemLog: [TabLogEntry] = []

    /// **执行回执册**（`FR-STD-DB-TASK-003`）：每次执行（成功 / 失败 / 被拦下 / 取消）留一条，
    /// 挂在页签上 —— 回执回答的是「我刚才那一跑发生了什么」，跨页签混在一起就答不出「哪一跑」。
    /// 与 Output 日志分工：Output 是**过程流水**（每次执行清空重来），回执是**审计读数**
    /// （四项读数 + 执行时刻，可复制 / 导出，且构造时已脱敏）。
    var receiptLog = ExecutionReceiptLog()

    var statusMessage: String {
        didSet { outputLog = TabLog.appended(outputLog, message: statusMessage, severity: .info) }
    }

    var errorMessage: String? {
        didSet {
            guard let errorMessage else { return }
            problemLog = TabLog.appended(problemLog, message: errorMessage, severity: .error)
        }
    }

    /// 「检查」按钮的结果（服务器端 EXPLAIN 校验）。赋值顺序上 `syntaxCheckFailed` 先于本字段。
    var syntaxCheckMessage: String? {
        didSet {
            guard let syntaxCheckMessage else { return }
            problemLog = TabLog.appended(
                problemLog,
                message: syntaxCheckMessage,
                severity: syntaxCheckFailed ? .error : .info
            )
        }
    }

    var syntaxCheckFailed: Bool
    /// 最近一次执行使用的连接；切换左侧连接后仍可正确取消本页签的查询。
    var connectionID: ConnectionConfig.ID?
    /// 最近一次执行使用的数据库（同一连接可浏览 / 执行在不同库上）。
    var database: String?
    /// 关联的磁盘文件（由「打开文件」或「另存为」设置）。
    var fileURL: URL?
    /// 相对上次保存是否有改动（仅文件页签展示圆点）。
    var isDirty: Bool

    init(
        id: UUID = UUID(),
        title: String,
        sql: String = "",
        results: [QueryResult] = [],
        isExecuting: Bool = false,
        statusMessage: String = "",
        errorMessage: String? = nil,
        syntaxCheckMessage: String? = nil,
        syntaxCheckFailed: Bool = false,
        connectionID: ConnectionConfig.ID? = nil,
        database: String? = nil,
        fileURL: URL? = nil,
        isDirty: Bool = false
    ) {
        self.id = id
        self.title = title
        self.sql = sql
        self.results = results
        self.selectedResultIndex = 0
        self.isExecuting = isExecuting
        self.statusMessage = statusMessage
        self.errorMessage = errorMessage
        self.syntaxCheckMessage = syntaxCheckMessage
        self.syntaxCheckFailed = syntaxCheckFailed
        self.connectionID = connectionID
        self.database = database
        self.fileURL = fileURL
        self.isDirty = isDirty
    }

    var result: QueryResult? {
        guard results.indices.contains(selectedResultIndex) else { return nil }
        return results[selectedResultIndex]
    }
}

/// 高危语句保护相关的偏好键（FR-EXEC-16）。
///
/// 单独放在文件级：存储属性的初始化器里不能引用 `Self`，用具体类型名又会让
/// 「谁拥有这些键」变得含糊，这里直接显式命名。
private enum ExecutionSafetyDefaults {
    static let safeModeKey = "execution.safeMode"
    static let confirmAllWritesKey = "execution.confirmAllWrites"
}

/// 一条「被高危语句保护拦下、等待用户确认」的执行请求（FR-EXEC-16）。
struct PendingExecution: Identifiable {
    let id = UUID()
    let tabID: UUID
    let sql: String
    let decision: ExecutionSafety.Decision
    /// 这一份 SQL 是从「选中片段 / 整篇」哪一段来的。
    /// 用户批准后执行的是**这一份**，Output 里也要照实说这一份的来源，
    /// 不能等到确认回来再从编辑器重新解析一遍（那时候选区可能已经变了）。
    let source: ExecutionScope.Source

    var reasons: [String] {
        if case .needsConfirmation(let reasons, _, _) = decision { return reasons }
        return []
    }

    /// 涉事语句（确认弹窗里并排摊开的东西）。
    var statements: [String] {
        switch decision {
        case .allow:
            return []
        case .needsConfirmation(_, _, let statements), .refused(_, let statements):
            return statements
        }
    }
}

/// 一次「已提交审批、等待人工决定」的数据任务执行（FR-AI-06）。
///
/// 审批本身复用 `AgentActionGate` / `AgentApproval`（不另造第二套审批机制）；
/// 这里只记住「批准之后还要做什么」：导出产物、记一条执行历史。
struct PendingDataTaskRun {
    let task: DataTaskDefinition
    let plannedAt: Date?
    let startedAt: Date
    /// 提交审批的那段写语句（批准后原样执行）。
    let writeSQL: String
}

/// 一列被多条外键引用时，等用户选一个目标（FR-DATA-06）。
///
/// 为什么要一个显式的"待选择"对象而不是把选项塞进某个数组：面板用 `.sheet(item:)` 呈现，
/// 需要 `Identifiable`；用 `Bool` 开关 + 另一个数组会出现"开关还在、选项已被清空"的中间态。
struct ForeignKeyJumpRequest: Identifiable {

    let id = UUID()
    var options: [ForeignKeyNavigation.Option]
    var value: String
    var source: DatabaseObjectRef
    var column: String
}

/// 一次导入请求（FR-IO-03）：界面选好的映射、数据与写入通道。
///
/// 全部是纯值：它要跨到 `Task` 里执行，也需要在"安全检查 → 二次确认 → 真执行"
/// 之间保持同一份内容（否则用户确认的是 A、执行的是 B）。
struct TableImportRequest {
    var table: String
    var schema: String?
    var plan: TableImport.Plan
    var rows: [[String?]]
    var mode: ImportWriteMode
    /// 已确认过（`needsConfirmation` 走过一次）时为 true，避免重复弹窗。
    var bypassingSafetyCheck: Bool
}

/// `startTableImport` 的结论：起了 / 需要确认 / 被拒。
///
/// 把三种结果显式分开，是为了让界面**永远不会**在"被拒"之后还去执行 ——
/// 只返回 `Bool` 时，"false 到底是需要确认还是被拒"就得靠调用方猜。
enum TableImportStart {
    case started
    case needsConfirmation(ExecutionSafety.Decision)
    case refused(String)
}

/// 「改期」弹框正在编的那一条（队列 `L-100` 界面半第二片）：视图与 `AppState` 之间的**草稿**，
/// 不落库 —— 点「保存」才走 `upsert`。`id` 既是「改哪一条」也是弹框的身份（`sheet(item:)` 要 `Identifiable`）。
struct TodoRescheduleDraft: Identifiable, Equatable {
    /// 目标任务的 `id`（`Todo` 的 `id` 是 `UUID`）。
    let id: UUID
    /// 改到哪一刻。
    var dueAt: Date
}

@MainActor
final class AppState: ObservableObject {
    @Published var connections: [ConnectionConfig] = []

    /// 启动时凭据条目核对的一行读数（★00；不上面板，只供诊断与日志 —— 用户能感知的结果是
    /// 「不再弹密码」本身，多造一个面板格反而要多一条只有我们自己看得懂的数字）。
    private(set) var keychainReconcileSummary: String?

    /// 侧边栏里**被折叠**的连接分组（FR-CONN-15）。
    ///
    /// **为什么这个状态归 `AppState`、不归视图**：侧栏内容由 `MainWindow.sidebarContent`
    /// **按活动栏分支创建** —— 切到「工作区 / 笔记」再切回来，那个分支被整个重建，
    /// 视图局部 `@State` 当场归零（人工点验批次 1 第 3 条实测：「折叠状态记不住」；队列 L-59）。
    /// 折叠是**用户对分组做的决定**，不是这一次渲染的临时量，所以它得活在视图之外。
    ///
    /// 只存**被折叠的**那些组（默认全部展开）：一进来就把组都收起来，会让人以为连接没了。
    /// 未分组那一段不参与（它是兜底容器，设计上不给折叠 —— 见 `ConnectionListView.sectionView`）。
    @Published private(set) var collapsedConnectionGroups: Set<String> = []

    /// 这一组现在是不是折叠的。
    func isConnectionGroupCollapsed(_ group: String) -> Bool {
        collapsedConnectionGroups.contains(group)
    }

    /// 折叠 / 展开一个分组。**写入口只有这一个**（集合本身是 `private(set)`）——
    /// 视图、快捷键、命令面板要改都走它，免得几条路各写一份判断、口径再分叉。
    func setConnectionGroup(_ group: String, collapsed: Bool) {
        if collapsed {
            collapsedConnectionGroups.insert(group)
        } else {
            collapsedConnectionGroups.remove(group)
        }
    }

    @Published var selectedConnectionID: ConnectionConfig.ID? {
        didSet {
            // 换连接 = 离开旧连接：旧连接上未提交的手工事务必须先结算（回滚并说明），
            // 否则它会一直挂在那个连接上（连接还活着，事务也还开着），用户却再也看不到它。
            if oldValue != selectedConnectionID {
                settleTransactions(leaving: selectedConnectionID)
            }
            rememberSelectedConnection()
            // 换连接后建库权限结论作废，等对象树加载时重新探测（FR-META-11）。
            setIfChanged(\.canCreateDatabase, nil)
        }
    }
    /// 查询历史（`DR-02` 持久化：**本机数据库 / 本地 only / 上限 500 条或 90 天 · 可清空 + 单条删**）。
    ///
    /// 内存这一份是门面 `QueryHistoryStore` 的**回读镜像**：写入 / 清空 / 启动加载都走它，
    /// 上限也在它那一处裁 —— 这里不再自己 `removeLast`（两处各裁一次就会各说各话）。
    @Published var queryHistory: [QueryHistory] = []

    /// 当前登录用户能否创建数据库（FR-META-11）。
    /// `nil` = 未知 / 该方言不支持探测 —— 此时不呈现「新建数据库」入口。
    @Published var canCreateDatabase: Bool?

    /// 对象树刷新令牌：新建数据库等操作后自增，驱动的视图重新加载根节点。
    @Published var metadataRevision = 0

    /// 「同一次刷新只许有一次在途」（队列 `L-96`）—— 根节点刷新的闸门。
    ///
    /// **为什么住在 `AppState` 上、不是视图的 `@State`**：视图被销毁重建时（`List` / `Section`
    /// 重建等）`@State` 会归零，而 `RefreshKey`（连接 + 元数据版本）**一字不变** —— 闸门必须比
    /// 视图活得久，新起来的那个实例才有东西可并；否则两次刷新就是各查一遍库。
    ///
    /// **不是 `@Published`**：写它**不该**触发一次重绘（它不参与画面）。
    let objectTreeRefreshGate = ObjectTreeRefreshGate()
    /// 当前查询目标数据库（上下文栏选择）。
    @Published var selectedDatabase: String?
    /// 当前服务器上当前用户可连接的数据库列表。
    @Published var availableDatabases: [String] = []
    @Published var isLoadingDatabases = false
    @Published var databaseError: String?
    @Published var tabs: [QueryTab] = []
    @Published var selectedTabID: UUID?
    @Published var savedQueries: [SavedQuery] = []
    /// 已保存的**可执行任务**定义（`sql-tasks.json`，`FR-STD-DB-TASK-001`）。
    ///
    /// 与 `savedQueries` 分开两份：那边是 SQL 片段（书签），这边是带「连接 / 目标库 / 读写模式 /
    /// 行数上限 / 要不要审批」的可执行任务 —— 混成一份文件，两种语义迟早互相污染。
    @Published var sqlTasks: [SQLTaskDefinition] = []
    /// 每个页签当前绑定的任务（tabID → 任务 id）。绑定着的时候，执行前要过 `SQLTaskGuard`。
    @Published var boundSQLTaskIDs: [UUID: UUID] = [:]

    /// 查询编辑器里**正在编辑的文本**（队列 `L-148`）。
    ///
    /// **刻意不是 `@Published`**：每敲一个键都写它，写进 `AppState` 就等于每键重算整个窗口
    /// （5,000 行实测 31.74 ms/键，见 `QueryEditorBuffer` 的注释）。它由视图单独观测
    /// （`.environmentObject(appState.editorBuffer)`）⇒ 重算范围缩到编辑区那一小块。
    /// `tabs[i].sql` 仍是**唯一权威副本**，由提交点 `commitEditorDraft(for:)` 同步。
    let editorBuffer = QueryEditorBuffer()

    /// 工作区的浏览器页签（`FR-EDIT-34` / 队列 `L-149` 剩余①「结构债」）。
    ///
    /// **刻意不是 `@Published`**（与 `editorBuffer` 同一条口径）：浏览器只是工作区的一类页签，
    /// 它的状态变化只该重算**观测它自己**的那一小块（工作区），而本类被整个窗口观测 ——
    /// 挂在 `@Published` 上的话，引擎每回报一次标题 / 加载中都会让整个窗口重算。
    /// 视图单独观测它（`.environmentObject(appState.workspaceBrowser)`）。
    ///
    /// 本类只借同一个实例做**接线**（它自己不看这些状态）：启动链恢复页签、
    /// 下载落盘目录、外发留痕 —— 见 `extension AppState: WorkspaceBrowserHost`。
    let workspaceBrowser = WorkspaceBrowserModel()

    /// **提交点**：把编辑器缓冲里的草稿写回权威副本。
    ///
    /// 读 `tab.sql` 的入口（执行、保存、关闭、切页签）都要先调它，否则会读到旧 SQL ——
    /// 这是 `L-148` 这条修法**唯一**需要小心的地方。
    func commitEditorDraft(for tabID: UUID) {
        editorBuffer.commit(for: tabID) { [weak self] sql in
            self?.updateSQL(sql, for: tabID)
        }
    }

    /// 有未保存改动的页签数。重启前提示会用到（NFR-I18N-03）：
    /// 不能让人为了换个界面语言把正在写的查询丢掉。
    var dirtyTabCount: Int {
        tabs.filter(\.isDirty).count
    }
    // MARK: 智能体（FR-AI-01）

    /// 智能体接入配置；默认是「总开关关闭 + 端点为空」的安全默认（AC-AI-01）。
    @Published var agentConfiguration: AgentConfiguration = .default
    /// 已保存的 API Key（只存在于内存与系统钥匙串，**永不写入配置文件**）。
    @Published var agentAPIKey: String?

    /// 编辑区 AI 辅助的状态机（`FR-STD-WS-AI-001`）。挂在 AppState 上是因为
    /// 菜单命令与工作区面板分处两棵树，只有这里同时够得着「页签」与「模型配置」。
    let editAssist = EditAssistModel()

    /// 调试会话（`FR-STD-WS-TOOL-003`）。与编辑区 AI 同一个理由：菜单与工作区面板分处两棵树。
    let debugSession = DebugSessionModel()
    /// 调试面板是否呈现。
    @Published var isDebugPanelPresented = false
    /// 钥匙串里是否已有 Key（界面显示「已配置 / 未配置」）。
    @Published var hasAgentAPIKey = false

    /// IM 通道（QQ）的 AppID（明文，非敏感；只有它是可读的）。
    @Published var agentIMAppID = ""
    /// 钥匙串里是否已有通道 Secret。
    @Published var hasAgentIMSecret = false
    /// 面板只显示「长度 + 尾 4」，不回显本体。
    @Published var agentIMSecretLength: Int?
    @Published var agentIMSecretTail: String?
    /// 通道的非敏感配置面（环境 / 自建中继地址 / 接收任务开关）—— 与凭据同一份文件。
    @Published var agentIMSettings: AgentIMChannelSettings = .empty
    /// 程序**自己取到的**网关地址那一行（★0：地址不再由用户填 ⇒ 至少要说清用的是哪一个）。
    @Published var agentIMGatewayLine: String?
    /// 手里那把 token 的尾 4 位（`nil` = 还没取到；本体只在内存里过一手）。
    @Published var agentIMTokenPreview: String?
    /// 传输层状态：**只有传输层自己发出来的那一档**（界面不许自己猜「大概连上了」）。
    @Published var agentIMConnectionState: AgentIMConnectionState = .idle
    /// 最近一次「测试连接 / 连接」的结论行（面板那一行；`nil` = 还没测过）。
    @Published var agentIMProbeLine: String?
    /// 入站任务的登记（最近 20 条原文；面板只拿它做「最近收了什么」的读数）。
    @Published var agentIMInboundTexts: [String] = []
    /// 最近一条被策略挡下的原因（`nil` = 没挡过）。
    @Published var agentIMLastInboundDrop: AgentIMInboundDropReason?
    /// 真跑过几轮（`FR-AGT-LINK-CHAN-003` 后半：入站任务接进对话循环之后才有意义）。
    @Published var agentIMInboundHandled = 0
    /// 推回了几条结论（推成才算；留在队列里等补发的不算）。
    @Published var agentIMInboundReplied = 0
    /// 最近一次**外发**的结论行（发不出去时面板要说清是凭据不对、限流，还是网络）。
    /// `nil` = 还没发过；发送成功也会写一句（否则「上一条红字」会一直挂着像还在失败）。
    @Published var agentIMOutboundLine: String?
    /// **跑一轮**的接线口（与 `agentScheduleRunner` 同形）：由 `DoyahStudioApp` 注入 ——
    /// `AppState` 不认识界面侧的 `AgentChatModel`，这条闭包是唯一通路。
    var agentIMTaskRunner: ((AgentIMTask) async -> AgentIMTaskRunResult)?
    /// 传输层本体：连上后由 AppState 持有（面板关掉不掉线）。
    private var agentIMTransport: AgentIMTransport?
    /// 取 token / 取网关的那一层（★0）。真实现走 REST；判据在 Core 直测（不碰网络）。
    private let agentIMProvisioner = AgentIMQQProvisioner(client: AgentIMQQClients.system())
    /// token 的**唯一持有处**（只在内存：到期前换、同时来的调用共用一次请求；绝不落盘）。
    private let agentIMTokenVault = AgentIMQQTokenVault()
    /// 结果队列与去重台账（落盘：ack 前的结论重启也还在；重投的同一条消息不跑第二遍）。
    private let agentIMResultQueue = AgentIMResultQueue(directory: AgentIMResultQueue.defaultDirectory)
    private let agentIMInboundLedger = AgentIMInboundLedger(directory: AgentIMResultQueue.defaultDirectory)
    /// 官方 REST 外发的出口（与取 token 同一个实现；装配缝里不出现出网 API 的名字）。
    private let agentIMOutboundClient = AgentIMQQClients.outbound()
    /// `msg_seq` 的唯一分配处（落盘：同一条结果重发复用同一个序号，不会在手机上冒出两条）。
    private let agentIMReplySeqLedger = AgentIMReplySeqLedger(directory: AgentIMResultQueue.defaultDirectory)
    /// 同一时刻只跑一条 IM 任务（两条同时进来 ⇒ 第二条如实回「上一轮还在跑」）。
    private var agentIMRunInFlight = false
    /// 「智能体设置…」面板的呈现开关（菜单命令驱动）。
    @Published var isAgentSettingsPresented = false
    /// 从菜单「用 QQ 扫码接入…」直接落到 IM 通道页（`FR-AGT-LINK-CHAN-003` 的入口那一半）。
    @Published var agentSettingsOpenIM = false
    /// 菜单直开扫码面板：不进设置也能扫码（2026-10-30 主人「可我没有看到哪里有啊」）。
    @Published var isQQScanPresented = false

    /// 「外观」面板（FR-EDIT-33：强调色可配置）。
    @Published var isAppearancePresented = false

    /// 「连接设置」面板（FR-CONN-20：保活心跳的开关与间隔）。
    ///
    /// 保活是**应用级**策略，所以开关不放连接表单 —— 放那儿会让人以为它是逐连接的属性。
    @Published var isConnectionSettingsPresented = false

    // MARK: - 应用主题（FR-EDIT-26）

    /// 主题：跟随系统 / 总是浅色 / 总是深色。
    ///
    /// 与终端配色**共用同一个 Core 类型**（`AppearancePreference`），但**偏好分开存**：
    /// 终端允许单独覆盖（浅色界面里配深色终端是常见偏好），所以键名不同。
    @Published var appearanceMode: AppearancePreference =
        AppearancePreference.resolve(rawValue: UserDefaults.standard.string(forKey: AppearancePreference.Storage.appKey)) {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: AppearancePreference.Storage.appKey) }
    }

    // 说明：这里**不**直接给 `ColorScheme?` —— AppState 不依赖 SwiftUI（只用 AppKit + Combine），
    // 由根视图把 `appearanceMode.forcedDark` 翻成 `.preferredColorScheme(...)`。
    // Core 的 `forcedDark` 已经把「哪一档等于跟随系统」定死了，视图不必再写一次 switch。

    // MARK: - 终端偏好（FR-EDIT-29）

    /// 终端外观：跟随系统 / 总是深色 / 总是浅色。
    ///
    /// 未知值回落「跟随系统」（`TerminalAppearance.resolve`）：偏好被手改、或版本降级读到新值，
    /// 都不该让终端起不来 —— 与强调色、活动栏同一条纪律。
    @Published var terminalAppearance: TerminalAppearance =
        TerminalAppearance.resolve(rawValue: UserDefaults.standard.string(forKey: "terminal.appearance")) {
        didSet { UserDefaults.standard.set(terminalAppearance.rawValue, forKey: "terminal.appearance") }
    }

    /// 终端字号（pt）。**夹取逻辑在 Core**（`TerminalFontSize`），这里只负责持久化：
    /// 写进来的越界值会被夹回区间，且夹回后的值才落盘 —— 偏好里不留非法值。
    /// 终端光标形状（FR-EDIT-29）：前台程序用 DECSCUSR 要求过就听它的，否则用这里。
    @Published var terminalCursorPreference: TerminalCursorPreference = TerminalCursorPreference.resolve(
        style: UserDefaults.standard.string(forKey: TerminalCursorPreference.Storage.styleKey),
        blinks: UserDefaults.standard.object(forKey: TerminalCursorPreference.Storage.blinksKey)
    ) {
        didSet {
            UserDefaults.standard.set(
                terminalCursorPreference.appearance.style.rawValue,
                forKey: TerminalCursorPreference.Storage.styleKey
            )
            UserDefaults.standard.set(
                terminalCursorPreference.appearance.blinks,
                forKey: TerminalCursorPreference.Storage.blinksKey
            )
        }
    }

    @Published var terminalFontSize: Int =
        TerminalFontSize.resolve(rawValue: UserDefaults.standard.object(forKey: "terminal.fontSize")) {
        didSet {
            let clamped = TerminalFontSize.clamped(terminalFontSize)
            if clamped != terminalFontSize {
                terminalFontSize = clamped
                return
            }
            UserDefaults.standard.set(terminalFontSize, forKey: "terminal.fontSize")
        }
    }

    /// 终端当前该用深色还是浅色：偏好解析 + 系统外观。视图据此取色板。
    var terminalIsDark: Bool {
        terminalAppearance.resolvesToDark(systemIsDark: Self.systemIsDarkAppearance)
    }

    /// 系统当前是否为深色外观（AppKit 口径；界面其余部分走 SwiftUI 的 `colorScheme`）。
    static var systemIsDarkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// 「数据库统计」面板（FR-DIAG-04）。
    @Published var isDatabaseStatsPresented = false

    /// 「慢查询排行」面板（FR-DIAG-03）。
    @Published var isSlowQueryPresented = false

    // 对话式诊断（FR-AI-03）：面板状态与取证结果。
    // 与 Core 的分工：这里只负责"把证据取回来、把回答交出去解读"，判据全在 Core。
    @Published var isDiagnosisPresented = false

    /// 连接上下文里的诊断入口（`FR-STD-DB-DIAG-006`）：从对象树右键带进来的作用域。
    ///
    /// `nil` = 这一轮诊断是从编辑器那条语句发起的（老入口），作用域与以前完全一样。
    /// 有值 = 连接 / 库 / 对象 / 最近一次执行的读数都已带进上下文，取证按**对象**取。
    @Published var objectDiagnosisScope: DiagnosisScope?

    /// 结论里点对象名 → 树上那个节点的一次**跳转请求**（`FR-STD-DB-DIAG-006` ②）。
    ///
    /// 展开状态住在树视图本地（`ObjectTreeView.expandedIDs`），面板够不到，所以面板只发请求；
    /// 树在 `onChange` 里展开路径、选中节点，然后把请求清掉（一次性，不重放）。
    @Published var treeJumpRequest: ObjectTreeJumpRequest?


    // 维护任务编排（FR-AI-04）：计划文本、审阅结果与执行状态。
    @Published var isMaintenancePresented = false

    // 外部调用审批（FR-AI-10 的界面那一半）：待审批队列 + 决定。
    @Published var isMCPApprovalPresented = false
    // 笔记（DOYAH-01/03）：面板状态。判据（检索/来源/安全边界）都在 Core，这里只做搬运。
    // 注意：**不再有 `isNotesPresented`** —— 笔记是活动栏上的一栏（`ActivityBarItem.notes`），
    // 不是浮在上面的弹窗；两个入口并存会让人不确定"关掉这个窗口笔记还在不在"。
    @Published var notes: [Note] = []
    @Published var notesQuery = ""
    /// **「查」那一格的展开态**（`FR-NOTEUI-04` · 人类主人 2026-10-10 原话见
    /// `App/Views/SearchPresentation.swift`）：**默认收起** —— 左区顶部那一行上不再有一格
    /// 常驻的搜索框，只有一枚放大镜图标，点它才把框子浮出来。
    ///
    /// 状态住在这里（不是视图里的 `@State`）的口径与其它面板一致：**探针要能驱动它**
    /// —— `TestsUISnapshot/NotesSearchRevealProbeTests.swift` 的「点图标前 / 后」两态读数
    /// 就是它；视图里的 `@State` 外面读不到、也写不进。
    @Published var noteSearchRevealed = false
    /// **两级导航的树与归属**（队列 `L-97` 界面半第一片）：架 / 笔记本 + 每条笔记挂在谁名下。
    /// 纯逻辑在 `Plugins/Notes/Sources/NoteNavigation.swift`（判据 `Tests/NoteNavigationTests.swift`），这里只做搬运 ——
    /// 宿主层不自己写过滤（「按笔记本筛笔记」只许经 `NotesNavigation.filter`）。
    @Published var notesNavigation = NotesNavigation(directory: NotebookDirectory(shelves: [], notebooks: []), placements: [])
    /// 界面上「正在看哪一块」：全部 / 某个架 / 某个笔记本 / 某个标签 / 最近。认不出的目标由 Core 归一成 `.all`。
    @Published var notesScope: NotesScope = .all
    /// **中栏列表的排序**（队列 `L-184` 第二片）：默认「最近更新在前」（三栏重排之前就是这个口径）。
    /// 总序与第二关键字在 Core（`NotesSortOrder.comparator`）—— 视图只画一个选择器。
    @Published var notesSortOrder: NotesSortOrder = .updatedDesc
    /// 搜索范围那枚开关（当前范围 / 全部笔记本）—— 只影响搜索结果的筛选。
    @Published var notesSearchScope: NotesSearchScope = .current
    /// **浮动式书架的两态**（`FR-NOTEUI-02`/`-03` · 派单 `T-20261010-166` §三.2 · 人类主人
    /// 2026-10-10 原话②：「**笔记本管理栏可以节约空间改成浮动式的，把笔记管理左栏放到目前的
    /// 笔记本管理导航栏去。**」）。
    ///
    /// ## 为什么这个状态住在 `AppState`
    ///
    /// 「悬停浮出 / 移开收起」是**跨两处视图**的一件事：入口那一枚图标画在**笔记列表的栏头里**
    /// （左边那一栏的顶部），浮出来的那一块是它上面的**覆盖层**（`NotesAreaView` 的 overlay）。
    /// 一个视图局部 `@State` 盖不住两处 —— 两处各揣一个的话，「悬停入口 ⇒ 覆盖层出现、移开 ⇒
    /// 两块一起收」永远对不上（`L-59` 那一课的同一个形状：状态活在哪，决定了它能不能被两处共用）。
    /// 写入口唯一 = `setNotesShelfRevealed(_:)`。
    ///
    /// ## 边界（如实登记）
    ///
    /// 这一位记的是**结果**（浮出 / 收起），不是「鼠标坐标」：鼠标进出的判定在视图那一层
    /// （`.onHover`），这里只留两态。所以探针可以**直接把它摆到「悬停后」那一档**再量几何
    /// —— 离屏宿主里合成悬停不响应（见 `NotesLayoutProbeTests` 头注释那三条硬边界），
    /// 「鼠标真悬停」那一下仍归实跑的人眼证据。
    @Published private(set) var notesShelfRevealed = false
    /// **删除确认框**（队列 `L-97` 界面半第二片）：挂在界面上的那一个删除请求。
    /// 计划从库里**现算**（`NoteLibrary.removalPlan`）——界面算不出来，也不该自己算一遍。
    @Published var pendingContainerRemoval: ContainerRemovalRequest?
    /// **单条删除的确认**（人类主人令 `T-20261007-079` ② / `T-20261007-081`）：挂在界面上的那一个
    /// 删除请求。破坏性操作先问一次 —— **判据：点删除后条目数不变，直到确认**。
    /// 规则在 Core `NoteRemovalPrompt`（判据 `TestsUISnapshot/NotesLayoutProbeTests.swift`）。
    @Published var pendingNoteRemoval: NoteRemovalRequest?
    /// **容器编辑**（队列 `L-97` 界面半第四片：新建 / 重命名）：挂在界面上的那一次编辑请求
    /// （`nil` = 没在编辑）。规则在 Core `NotebookEditPrompt`，这里只做搬运。
    @Published var pendingContainerEdit: ContainerEditRequest?
    /// 编辑弹框里那个名字输入框的当前值（**唯一来源**：「确定」的灰着与 `commitContainerEdit`
    /// 的守卫都读它 —— `L-50` 那一课：两处各写一遍必分家）。
    @Published var containerEditName = ""
    /// **多选集合**（队列 `L-97` 界面半第五片）：行上 ⌘ / ⇧ 点选出来的那一批。
    /// 规则在 Core `NoteSelectionRule`（判据 `Tests/NoteSelectionPromptTests.swift`）——
    /// 视图只把**当前事件的修饰键**交进来，本文件不自己判修饰键。
    @Published var selectedNoteIDs: Set<UUID> = []
    /// 范围选择的锚点（⇧ 点从哪儿起算）。**不进界面**：它只影响下一次 ⇧ 点。
    private var noteSelectionAnchor: UUID?
    /// **检索状态**（队列 L-44，2026-09-28）：界面检索改走库以后，「这一屏的结果是怎么来的」
    /// 就成了必须有出处的一件事 —— 三种态各自对应一句如实话（见 `noteSearchHint`）。
    @Published private(set) var noteSearchState: NoteSearchState = .idle
    /// 三个编辑框（标题 / 正文 / 标签）：**任何一个变了都算「编辑器有改动」**（片 `N2-4`）。
    /// `didSet` 里只做两件事（见 `noteEditorTextChanged`）：标脏 + 重排**停顿计时**——
    /// 计时不是「每键入一次写一次库」，而是「停手 `NoteAutosave.pauseWindow` 之后写一次」。
    @Published var noteEditorTitle = "" {
        didSet { noteEditorTextChanged() }
    }
    @Published var noteEditorBody = "" {
        didSet { noteEditorTextChanged() }
    }
    /// **编辑器里那一份正文的权威源**（片 `WY-2a`）：编辑面（`NotesRichTextEditor`）每敲一次就把
    /// 整棵 span 树回推到这里，`writeNoteEditor` 用它经 `setNoteSpans` 落库。
    ///
    /// 与 `noteEditorBody` 的关系是**单向投影**：spans 是源，`body` = `NoteBodyProjection.markdown(from:)`。
    /// 为什么它**没有** `didSet`：它从不单独变 —— 每一次都由编辑面同一批回调（`textDidChange` /
    /// `install`）与 `noteEditorBody` **一起**推上来，脏标记由 `noteEditorBody` 那一处记（一处记两次
    /// 就会多出一串重复的停顿计时，`L-172` 同一课）。
    @Published var noteEditorSpans: [NoteSpan] = []
    @Published var noteEditorTags = "" {
        didSet { noteEditorTextChanged() }
    }
    /// **当前这条笔记挂着的附件索引**（`FR-NTS-NOTE-ATTACH-001`）：界面只画这份读数。
    /// 库里的 `note_attachment` 只存路径，二进制在文件系统（`NoteAttachmentStore`）。
    @Published private(set) var noteAttachments: [NoteAttachment] = []
    /// 其中**文件已经不在了**的那些（判据②「附件缺失时明确提示」的读数面 —— 界面按它画缺失态）。
    @Published private(set) var missingNoteAttachments: [NoteAttachment] = []
    /// 删笔记之后**还留在盘上的附件清单**（判据③：另行确认才删文件）。
    /// 非空 ⇒ 界面弹一次「文件要一起删吗」，两个出口都是人按的。
    @Published var pendingAttachmentCleanup: [NoteAttachment] = []
    @Published var isAttachmentCleanupPresented = false
    /// **当前是「预览」还是「改」**（片 `N2-3a`「单击预览」；枚举见文件头的 `NoteEditorMode`）。
    ///
    /// 默认 `.edit` —— 与 `N2-3a` 之前一致（没点过任何行时编辑器就是可编辑的）。
    /// **四个入口**改它：`handleNoteRowClick`（单击 ⇒ `.preview`）、`beginEditingCurrentNote`
    /// （双击**内容区** ⇒ `.edit`；片 `N2-3b`）、`edit(_:)` 与 `beginNewNote()`
    /// （既有的「改」/「新建」，以及列表行**双击** ⇒ `.edit`）。
    @Published var editorMode: NoteEditorMode = .edit
    private var noteBeingEdited: UUID?

    // MARK: - 自动保存（片 `N2-4` · 人类主人令 `T-20261007-006` 第二节第六条）

    /// 编辑器现在这一份的**保存状态**（工具条画它、状态栏说它、机器判据也读它 —— 唯一出处）。
    /// 口径与停顿窗口在 `Plugins/Notes/Sources/NoteStorage/NoteAutosave.swift`。
    @Published private(set) var noteSaveState: NoteSaveState = .idle
    /// 编辑器里有没有**还没落库**的改动（`noteSaveState == .idle` ⇔ 没有）。
    private var noteEditorDirty = false
    /// 正在跑的计时 / 写库那一发（**唯一一处**：新一轮改动与「切走即存」都会把上一发收掉重排）。
    private var noteAutoSaveTask: Task<Void, Never>?
    /// 正在跑的「从库里读回正文权威源 spans」那一发（片 `WY-2a`；见 `loadEditorSpans`）。
    /// 换一条笔记就把它收掉重排 —— 迟到的读数属于上一条，装到当前这一条上就是串内容。
    private var noteSpansLoadTask: Task<Void, Never>?
    /// 正在跑的「读这条笔记的附件索引 + 文件在不在」那一发（`FR-NTS-NOTE-ATTACH-001`）。
    /// 与 spans 那一发同一条口径：换一条笔记就收掉重排，迟到的读数不许装到当前这一条上。
    private var noteAttachmentLoadTask: Task<Void, Never>?
    /// 装内容进编辑器期间置真 —— 那三个 `didSet` 据此**不把「装进来的」当成「用户改的」**。
    private var isLoadingNoteEditor = false
    /// 刚落库、还没被 `reloadNotes()` 反映到 `notes` 里的那一份（**读旧列表的窗口期**）。
    /// 回到同一条笔记时优先用它，否则用户会看到「自己刚写的字不在了」（见 `loadEditorContent`）。
    private var pendingNoteSnapshot: NoteEditorSnapshot?

    /// **编辑器里的一份内容快照**：写库与「切走即存」都以它为据。
    ///
    /// 为什么要有它：「切走即存」那些入口**紧接着**就会改写编辑器那三个 `@Published`，
    /// 而写库是异步的 —— 不快照的话，写下去的是**下一条**的内容。
    ///
    /// **片 `WY-2a`**：多带一棵 `spans`（正文权威源）。`body` 是它的**单向投影**
    /// （构造时由 `NoteBodyProjection.markdown(from:)` 派生，与 `NoteBody.body` 同一个函数）——
    /// 快照里不保留「另一个源的正文」，落库的两列（`spans` / `body`）因此恒为同一棵树的两个形态。
    private struct NoteEditorSnapshot {
        let id: UUID?
        let title: String
        let spans: [NoteSpan]
        let body: String
        let tags: String

        /// 按「正文那一份 span 树」造一个快照（`body` 由 spans 派生 —— 单向）。
        init(id: UUID?, title: String, spans: [NoteSpan], tags: String) {
            self.id = id
            self.title = title
            self.spans = spans
            self.body = NoteBodyProjection.markdown(from: spans)
            self.tags = tags
        }

        /// 转成落库用的草稿（空标题落 `无标题`，与手动「保存」同一口径）。
        func draft(untitled: String) -> NoteDraft {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return NoteDraft(
                title: trimmed.isEmpty ? untitled : trimmed,
                body: body,
                tags: tags.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "，" }).map(String.init),
                source: NoteSource(kind: .manual)
            )
        }
    }

    // MARK: - 待办（队列 `L-100` 界面半第一片 · 清单屏）
    /// 笔记区里当前看哪一屏（笔记 / 待办）—— `FR-NOTE-36` 的「各自入口与列表，不塞进笔记列表」。
    @Published private(set) var notesModule: NotesModule = .notes
    /// 从库里读回来的任务（**创建时间正序**，与 `NoteLibrary.todos()` 同源）。
    /// 分区只经 Core 的 `TodoPresentation.sections`（本文件不自己 `filter` 两遍 —— 那正是分家现场）。
    @Published var todos: [Todo] = []
    @Published var todoEditorTitle = ""
    @Published var todoEditorHasDue = false
    @Published var todoEditorDueAt = Date()
    @Published var todoEditorPriority: TodoPriority = .normal
    @Published var todoEditorTags = ""
    /// 编辑面里那一格「重复」的草稿（`FR-NTS-TODO-LIST-001` 的第四个本体字段；`nil` = 不重复）。
    /// 与标题 / 标签一样是**编辑器草稿**：进编辑态时从库里那一份灌进来（`edit(_:)`），
    /// 新建态清空（`beginNewTodo`），保存时随 `saveTodoFromEditor()` 一起写回。
    /// **归一不在这里**：`TodoRepeat.normalized()` 是唯一一处（界面只负责选，选完存的是归一后的值）。
    @Published var todoEditorRepeat: TodoRepeat?
    /// 编辑面里那一格「备注」的正文本（**纯文本、允换行**；契约 `Todo.note` · 片 `TD-NOTE`）。
    /// 与标题 / 标签一样是**编辑器草稿**：进编辑态时从库里那一份灌进来（`edit(_:)`），
    /// 新建态清空（`beginNewTodo`），保存时随 `saveTodoFromEditor()` 一起写回。
    @Published var todoEditorNote = ""
    /// **已完成分区默认折叠**（`FR-NOTE-36` 原文）—— 折叠状态是界面状态，默认值由 Core 给
    /// （`TodoSectionKind.isCollapsedByDefault`），这里不写第二遍。
    @Published var todoCompletedExpanded = !TodoSectionKind.completed.isCollapsedByDefault
    // MARK: - 待办：清单的「组织与检索」（队列 `L-100` 组织与检索界面半）
    /// 清单按什么排（三档；默认档由 Core 给 —— `TodoSort.Order.defaultOrder`）。
    /// 上屏的是**档位本身**，界面拿它去 `TodoQuery.board` 换一屏；本文件不自己排。
    @Published var todoSortOrder: TodoSort.Order = .defaultOrder
    /// 清单只留哪一档（五档；默认「全部」）。
    @Published var todoFilter: TodoFilter = .defaultFilter
    /// 清单怎么归堆（四档；默认「不分组」= 与界面半第一片同形）。
    @Published var todoGroupBy: TodoGroupBy = .defaultGroupBy
    /// 清单的**本地关键字检索词**（片 `TD-LIST-1` · 派单 `T-20261009-026` 的 B4）。
    ///
    /// 与 `todoFilter` / `todoSortOrder` / `todoGroupBy` **同类**（界面状态，住 `AppState`）：
    /// 切一个字只重画这一屏（`todoBoard` 重算），**不重读库、不写库** —— 清单与日历仍看同一份
    /// `todos`（`FR-NOTE-39`）。判定本身在 Core（`TodoSearch`），这里只存那个词。
    @Published var todoSearchText = ""
    /// **只读详情**看的是哪一条（片 `TD-LIST-1` 的 A6；`nil` = 没在看详情）。
    ///
    /// 与 `todoBeingEdited` 是**互斥的两态**：点清单里的一行 ⇒ 这一格被设上（只读详情）；
    /// 显式「编辑」（行的右键 / 左区那枚「编辑」）⇒ 这一格清掉、进编辑器。两态同时只可能有一个非空
    /// （`todoDetailTodo` 的口径），所以右栏不必自己判「谁优先」。
    @Published var todoDetailID: UUID?
    // MARK: - 待办：清单 / 日历（队列 `L-100` 界面半第二片 · 日历屏）
    /// 中栏看哪一档（清单 / 日历）—— `L-184` ⑤「`L-100` 待办沿用同一骨架（中栏在清单 / 日历间切）」。
    @Published var todoPane: TodoPane = .defaultPane
    /// 日历看月还是看周。
    @Published var todoCalendarView: TodoCalendarView = .initial
    /// 日历翻到的那一天（月视图看它所在的月、周视图看它所在的周）。
    /// **参照时刻由界面给**：`TodoCalendar` 自己一律不读系统时钟（同一条纪律，见那份文件的四条口径）。
    @Published var todoCalendarAnchor: Date = Date()
    /// 点中的那一天（`nil` = 还没点过 —— 当天任务区如实显示空态，不替用户选一天）。
    @Published var todoCalendarSelectedDay: Date?
    /// 正在改期的那一条（`nil` = 没开改期框）。
    @Published var todoRescheduleDraft: TodoRescheduleDraft?

    // MARK: 待办：提醒（队列 `L-100` 落法 ④ 的界面入口半）

    /// 「提醒」区当前选中的档位（**界面状态**；默认档由 Core 给）。
    @Published var todoReminderPreset: ReminderPreset = ReminderPreset.presetDefault

    /// 系统通知权限那一档（端侧唯一的读数处写它；读不出来 ⇒ 未决）。
    @Published var reminderPermission: ReminderPermission = .notDetermined

    /// 库里所有提醒，按**所属任务 id** 索引（清单行那枚小铃铛与「提醒」区读同一份）。
    @Published var todoReminders: [UUID: Reminder] = [:]

    /// 系统通知那一层的适配器（**界面只认协议** —— 谁碰 `UNUserNotificationCenter` 在源码上是一处）。
    let reminderDeliverer: ReminderDelivering = SystemReminderDeliverer()

    /// 正在编辑的那一条（`nil` = 新建）。
    private var todoBeingEdited: UUID?
    @Published var mcpPendingApprovals: [MCPApprovalRequest] = []
    @Published var mcpApprovalMessage: String?
    @Published var mcpApprovalBadLines = 0
    private var mcpApprovalWatcher: Task<Void, Never>?
    @Published var maintenancePlanText = ""
    @Published var maintenanceReview: MaintenancePlanReview?
    @Published var maintenanceMessage: String?
    @Published var maintenanceAllowMultipleHighCost = false
    @Published var maintenanceIsRunning = false
    @Published var diagnosisQuestion = ""
    @Published var diagnosisEvidence: [DiagnosisEvidence] = []
    @Published var diagnosisReply = ""
    @Published var diagnosisReport: DiagnosisAdviceReport?
    @Published var diagnosisIsGathering = false
    @Published var diagnosisMessage: String?
    /// 上一次「存进笔记」**没有重复存**、而是指回的那条已有笔记（队列 `L-134`）。
    /// 界面据此给一个「打开那条」的入口 —— 只有真的发生了「同指纹已存在」才有值。
    @Published var reusedCapturedNote: Note?

    /// 「Schema 对比与同步」面板（FR-DDL-04）。
    @Published var isSchemaDiffPresented = false
    /// ER 图面板（FR-DDL-05）：由外键元数据画的图。
    @Published var isERDiagramPresented = false

    /// 「服务器级对象」面板（FR-SESS-03）：角色 / 表空间 / 扩展的浏览与增删改。
    @Published var isServerObjectsPresented = false

    /// 多个外键目标时的待选择请求（FR-DATA-06）。
    /// 结果来源表上**真的挂着外键的列**（FR-DATA-06 的入口判定用）。
    ///
    /// key = `DatabaseObjectRef.qualifiedName`；值 = 正向可跳转的列名。
    /// 没有 key = **还没读到**（界面据此不露入口），有 key 但是空集 = 读到了、这张表没有外键。
    @Published private(set) var foreignKeyColumns: [String: Set<String>] = [:]
    /// 正在读的表（避免同一张表被几次刷新同时查询）。
    private var loadingForeignKeyTables: Set<String> = []
    @Published var pendingForeignKeyJump: ForeignKeyJumpRequest?

    /// 活动栏当前选中的视图（FR-EDIT-32）。未知值回退到数据库视图，界面永远起得来。
    ///
    /// **写入口只有 `selectActivityItem(_:)` 一个**（所以是 `private(set)`）：偏好文件、
    /// 快捷键、命令面板、代码里的直接赋值都能改它，只要有一条绕过许可证分档，
    /// "Standard 下工作区与数据库不可达"就成了摆设。收成一个入口、在入口里过一遍
    /// `LicensePresentation.resolveSelection`，这条口径才是**结构性**的而不是靠自觉。
    @Published private(set) var selectedActivityItem: ActivityBarItem = ActivityBarItem.resolve(
        id: UserDefaults.standard.string(forKey: ActivityBarItem.storageKey)
    )

    // MARK: 版本与许可证（FR-LIC-01~05）

    /// 本机许可证的装载结果 —— 界面（活动栏 / 关于页）的**唯一来源**。
    ///
    /// 构造 `AppState` 时就同步读一次：读一个小文件而已，而"先按全量画出来、稍后再偷偷改掉"
    /// 会让用户在心里数过一遍的图标发生变化（启动瞬间闪出未授权的区，然后消失）。
    @Published private(set) var licenseLoad: LicenseLoader.LoadResult =
        LicenseLoader.load(language: LocalizationManager.shared.effectiveLanguage)

    /// 「版本与许可证」页的呈现开关。
    @Published var isAboutLicensePresented = false

    /// 当前档位的能力位（没许可证 = Standard，见 `LicenseGate`）。
    var licenseCapabilities: LicenseCapabilities { licenseLoad.entitlements.capabilities }

    /// 插件挂点装配（契约 §3.52④）：缺位的插件，其活动栏项**整体不出现且不报错**。
    /// 启动时读一次盘（清单是随包发的静态文件）；测试 / 预览可注入。
    lazy var pluginMounts: PluginMounts = .live(registry: PluginRegistry.loadDefault())

    /// 活动栏上**该出现**的那几项（未授权的区不出现，Q11 口径）。
    /// 两道判据：许可（`LicensePresentation` 那一处）+ 挂点（插件在不在）。
    var visibleActivityItems: [ActivityBarItem] {
        LicensePresentation.activityItems(for: licenseCapabilities, mounts: pluginMounts)
    }

    /// 当前档位是否含笔记。写笔记的入口都要先问这一句：Pro 里笔记区不显示，
    /// 但「诊断结论入笔记」「维护计划入笔记」这些按钮住在数据库区里，仍然点得到。
    var notesEnabled: Bool { licenseCapabilities.contains(.notes) }

    /// 切换活动栏视图。未授权的项会被落到当前档位下可见的项，并**如实说明**为什么没切过去。
    func selectActivityItem(_ item: ActivityBarItem) {
        guard let resolved = LicensePresentation.resolveSelection(item, for: licenseCapabilities) else {
            // 一个区都没授权（坏许可证）：界面照常起来，但不假装切成功了。
            statusMessage = licenseSummary
            return
        }
        if resolved != item {
            statusMessage = L(.licenseAreaNotInEdition, L(item.titleKey))
        }
        guard resolved != selectedActivityItem else { return }
        selectedActivityItem = resolved
        UserDefaults.standard.set(resolved.rawValue, forKey: ActivityBarItem.storageKey)
        // **换段就把下方面板的页签口径跟着换**（`FR-EDIT-10` 段条件：历史只在 Database 段出现，
        // 切走时若正选中它就落到该段可用页签、切回恢复）—— 判定收在 `syncLowerPaneTabWithSegment`。
        syncLowerPaneTabWithSegment()
        // 广播换区（2026-10-02 需求提出者：菜单显示要跟活动栏联动）——
        // 菜单栏那一层（`MainMenuLocalizer`）不持有本对象，靠这条对齐菜单项的显示。
        NotificationCenter.default.post(name: .doyahActivityItemChanged, object: resolved)
    }

    /// 把选中项落到当前档位下可见的项上。
    ///
    /// **不提示**：这是修一个自相矛盾的状态（上次选的项这一档看不见了），不是替用户做选择，
    /// 每次启动都弹一句"已切到笔记"只会变成噪音。
    func ensureActivitySelectionVisible() {
        guard let resolved = LicensePresentation.resolveSelection(selectedActivityItem, for: licenseCapabilities),
              resolved != selectedActivityItem else { return }
        selectedActivityItem = resolved
        UserDefaults.standard.set(resolved.rawValue, forKey: ActivityBarItem.storageKey)
        // 与 `selectActivityItem` 同一条口径：这里也是**换段**（只是不提示），页签跟着换。
        syncLowerPaneTabWithSegment()
        NotificationCenter.default.post(name: .doyahActivityItemChanged, object: resolved)
    }

    /// 重新读许可证 —— 用户刚把许可证文件放进去时用，**不用重启**。
    func reloadLicense() {
        licenseLoad = LicenseLoader.load(language: LocalizationManager.shared.effectiveLanguage)
        ensureActivitySelectionVisible()
        statusMessage = licenseSummary
    }

    /// 许可证状态的一句话。
    ///
    /// **不再自己抄一份**（队列 L-65）：此前这里是 `LicenseLoader.summary(for:)` 的**副本** ——
    /// 因为那一份把语言写死成中文，界面上切到英文时这一行仍是中文。代价是**两份实现会漂移**，
    /// 而且已经漂了：界面这份把 `.unreadable` 的**原因丢掉了**（只显示「读不出来」，
    /// 不显示为什么），Core 那份（日志 / CLI）却说了原因。现在 Core 那份收 `language:`
    /// （语言由调用方给定），界面直接用它 —— **一句话只有一个出处**。
    var licenseSummary: String {
        LicenseLoader.summary(
            for: licenseLoad,
            language: LocalizationManager.shared.effectiveLanguage
        )
    }

    /// 「账户」占位说明（R-23：语义未定，只放占位不实现登录）。
    @Published var isAccountNoticePresented = false

    /// 「账户与同步…」面板的呈现开关（片 `云F` · 契约 §6.4「账号与同步界面（最小集）」）。
    ///
    /// 与上面那条 R-23 占位说明**不是同一件事**：这一条打开的是真界面（注册页 / 登录页 /
    /// 同步开关（`S4` 原文）/ 登出 / 多端会话 / 找回入口位），而占位那条是「登录后提供什么还没定」
    /// 那个年代的说明。占位那条**本片不删、活动栏那颗按钮也不改**（不扩范围）：换不换既有入口
    /// 属语义变更，归组长裁；本片只补一处**门** + 一条菜单项。
    @Published var isAccountSyncPresented = false

    // MARK: 执行计划（FR-DIAG-01）

    /// 执行计划面板的呈现开关。
    @Published var isExecutionPlanPresented = false
    /// 最近一次解析出的计划树；`nil` = 还没跑过或解析失败。
    @Published var executionPlan: ExplainPlan?
    @Published var executionPlanError: String?
    @Published var executionPlanIsLoading = false
    /// `ANALYZE` 会**真正执行**语句，因此默认关闭；BUFFERS / JSON 只是多要些信息。
    @Published var planRunAnalyze = false
    @Published var planIncludeBuffers = false
    @Published var planUseJSON = true

    /// 「自然语言 → SQL」面板的呈现开关（菜单命令驱动）。
    @Published var isAgentSQLPresented = false

    // MARK: 执行审批与审计（FR-AI-09 / NFR-AI-03）

    /// 「审批与审计…」面板的呈现开关（菜单命令驱动）。
    @Published var isAgentAuditPresented = false

    // MARK: 统一外发日志（NFR-SEC-08）
    //
    // 浏览器页签的**状态**（页签集 / 选中 / 引擎缓存）不在这里（队列 `L-149` 剩余①）：
    // 它归 `WorkspaceBrowserModel`，由工作区单独观测 —— 浏览器只是工作区的一类页签，
    // 它的加载状态不该惊动整个窗口（同族的病与修法见 `QueryEditorBuffer`）。
    // 本类只留两件**与全局有关**的事：外发日志面板、下载用的授权目录。

    /// 统一外发日志面板（NFR-SEC-08）。
    @Published var isEgressLogPresented = false
    @Published var egressEntries: [EgressEntry] = []
    @Published var egressMessage: String?
    @Published var egressError: String?
    /// 审计记录（读自本地 JSONL，顺序 = 写入顺序 = 时间顺序）。
    @Published var agentAuditRecords: [AgentActionRecord] = []
    @Published var isAgentAuditLoading = false
    /// 已提交、等待人工决策的智能体动作（FR-AI-09 逐次审批）。
    @Published var pendingAgentApprovals: [AgentApproval] = []
    /// 需要弹出审批单的那个动作；`nil` = 不弹。
    @Published var agentApprovalRequest: AgentApproval?
    /// 面板内的一行提示（导出成功 / 已清空 / 已批准…）。
    @Published var agentAuditMessage: String?
    /// 面板内的错误（读取 / 导出失败、执行失败…）。
    @Published var agentAuditError: String?

    // MARK: 数据任务（FR-AI-05 / FR-AI-06 / FR-AI-08）

    /// 「数据任务…」面板的呈现开关（菜单命令驱动）。
    @Published var isDataTaskPresented = false
    /// 已保存的数据任务定义（`data-tasks.json`）。
    @Published var dataTasks: [DataTaskDefinition] = []
    /// 执行历史（`task-runs.jsonl`，追加式；状态 / 行数 / 耗时 / 消息都在记录里）。
    @Published var dataTaskRuns: [TaskRunRecord] = []
    /// 每个任务当前的调度判定（App 侧 tick 更新，界面直接展示）。
    @Published var dataTaskDecisions: [UUID: ScheduleDecision] = [:]
    /// 已授权目录（`directory-bookmarks.json`），可在多个任务间复用（FR-AI-08）。
    @Published var storedDirectoryBookmarks: [DirectoryBookmark] = []
    /// 下载期间保持的目录访问权（FR-EDIT-34，完成 / 失败后统一释放）。
    private var browserDownloadGrants: [DirectoryGrant] = []
    /// 面板内的一行提示（保存成功 / 已提交审批 / 产物已导出…）。
    @Published var dataTaskMessage: String?
    /// 面板内的错误（读取 / 保存 / 导出 / 执行失败）。
    @Published var dataTaskError: String?

    private let dataTaskStore = DataTaskStore.shared
    private let directoryBookmarkStore = DirectoryBookmarkStore.shared
    /// 目录选择器：Core 只定义 `DirectoryPicker` 协议，真实实现用 `NSOpenPanel`（FR-AI-08）。
    private let dataTaskDirectoryPicker: any DirectoryPicker = OpenPanelDirectoryPicker()

    // MARK: - 查询自动归档（FR-EDIT-31）

    /// 是否把执行过的 SQL 自动归档成当天的 `.sql` 文件（默认关闭，需先选目录）。
    @Published var isSQLArchiveEnabled: Bool =
        UserDefaults.standard.object(forKey: "sqlArchive.enabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(isSQLArchiveEnabled, forKey: "sqlArchive.enabled") }
    }

    // MARK: 备份 / 恢复面板（FR-IO-04）

    /// 面板是否呈现。
    @Published var isBackupRestorePresented = false
    /// 执行日志（逐行追加；面板直接显示它 —— 与 CLI 是同一份输出）。
    @Published private(set) var backupRestoreLog: [String] = []
    /// 正在执行。
    @Published private(set) var isBackupRunning = false

    /// 备份 / 恢复**起子进程用的执行器**（探针缝）。
    ///
    /// 生产 = `FoundationProcessRunner`（真起 `pg_dump` / `pg_restore`）。探针换上假的之后，
    /// `runBackupPlan` / `runRestoreSections` 走的仍是生产那条路 —— 计划 → argv → 环境变量 →
    /// 日志逐行 → 退出码判读 —— 只有「谁去执行」换掉了。
    ///
    /// 为什么要开这一处：`FR-STD-DB-IO-003` / `-004` 的台账备注长期是「界面点击待人工点验」，
    /// 而「点了执行到底跑了几条命令、argv 长什么样、失败后有没有说清从哪一段续跑」这些
    /// **都不是只有人眼能判** —— 卡住的是 `BackupExecutor()` 在方法体里直接 new，探针没处注入。
    var backupRunner: any ExternalProcessRunner = FoundationProcessRunner()

    /// 前置诊断（工具与服务器主版本不兼容时给出「为什么 + 怎么办」）。
    func diagnoseBackupTool(_ plan: BackupPlan, password: String?) async -> String? {
        // 工具版本：跑一次 `--version` 并解析（Core 已有解析器，不重复实现）
        var toolVersion: DatabaseVersion?
        if let arguments = plan.arguments {
            let versionArguments = [arguments[0], "--version"]
            let output = await runExternalProcess(executable: versionArguments[0], arguments: Array(versionArguments.dropFirst()))
            toolVersion = BackupToolCheck.parseToolVersion(output)
        }
        // 服务器版本：用当前连接已经取到的那份（`serverInfos`），**不再建新连接**；
        // 解析交给方言层（各家的版本串写法不同，解析规则只有一处）
        let serverVersion = selectedConnection.flatMap { configuration in
            serverInfos[configuration.id].map {
                SQLDialectFactory.make(for: configuration.dbType).parseServerVersion($0.version)
            }
        }
        // 拿不到时**不假装通过**：说清"不确定"，由用户决定
        guard let serverVersion else {
            return "拿不到服务器版本，无法判断工具兼容性（可继续，但可能跑到一半才失败）"
        }
        let compatibility = BackupToolCheck.evaluate(toolVersion: toolVersion, serverVersion: serverVersion)
        guard !compatibility.isUsable else { return nil }
        return BackupToolCheck.diagnosis(for: compatibility, toolName: plan.executableName)
    }

    /// 跑一个外部程序并把输出**收集**回来（只用于 `--version` 这类只读探测）。
    ///
    /// 执行器是回调式的（返回退出码、输出逐行走回调），所以这里用一个 actor 收集 ——
    /// 回调是 `@Sendable` 且可能来自别的线程，直接往数组里 append 会踩并发。
    private func runExternalProcess(executable: String, arguments: [String]) async -> String {
        let collector = OutputCollector()
        do {
            _ = try await FoundationProcessRunner().run(
                executable: executable,
                arguments: arguments,
                environment: [:]
            ) { line in
                Task { await collector.append(line) }
            }
            return await collector.joined()
        } catch {
            return ""
        }
    }

    /// 把面板要给用户看的话写进备份日志。
    ///
    /// `backupRestoreLog` 是 `private(set)`：面板「点了执行但缺目标库」这类前置拒绝
    /// 也必须**说在同一个地方**（用户看的就是这块日志），所以开一个写入口，
    /// 而不是把面板自己的提示摆到别处。
    func noteBackupLog(_ lines: [String]) {
        backupRestoreLog = lines
    }

    /// 把一句人话写进**页签的**状态（下方面板 Output 页签会显示它）。
    ///
    /// 为什么不用 `AppState.statusMessage`（全局那个）：目前**没有任何视图读它** ——
    /// 写进去等于没写。页签的 `statusMessage` 有 `didSet`，会追加进 Output 日志，
    /// 那才是用户看得见的交代（导出的进度与去向就写在那里）。
    func reportTabStatus(_ message: String, for tabID: UUID) {
        _ = updateTab(tabID) { $0.statusMessage = message }
    }

    /// 执行备份 / 恢复。
    ///
    /// **沙箱下起子进程可能被拒** —— 那种失败要给可读指引，而不是把原始错误丢给用户：
    /// 这条纪律与"外部程序调用"一致（用户必须知道为什么点了没反应、以及替代路径是什么）。
    @discardableResult
    func runBackupPlan(_ plan: BackupPlan, password: String?) async -> Int32 {
        backupRestoreLog = [L(.backupRestoreLogCommand, plan.displayCommand(password: password))]
        isBackupRunning = true
        defer { isBackupRunning = false }
        do {
            let result = try await BackupExecutor(runner: backupRunner).execute(plan, password: password) { [weak self] line in
                Task { @MainActor in self?.backupRestoreLog.append(line) }
            }
            if result.isFailure {
                backupRestoreLog.append("失败（退出码 \(result.exitCode)）：")
                if let summary = result.failureSummary { backupRestoreLog.append(summary) }
                return result.exitCode
            }
            backupRestoreLog.append("完成：\(result.outputLineCount) 行输出")
            return 0
        } catch {
            backupRestoreLog.append(L(.backupSandboxHint))
            backupRestoreLog.append(L(.backupRestoreLogReason, error.localizedDescription))
            return 68
        }
    }

    // MARK: 连接保活心跳（FR-CONN-20）

    /// 是否开启保活（间隔可配置、可关闭）。持久化到 UserDefaults。
    @Published var isKeepAliveEnabled: Bool =
        UserDefaults.standard.object(forKey: "keepAlive.enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isKeepAliveEnabled, forKey: "keepAlive.enabled") }
    }

    /// 空闲多久发一次心跳（秒）。
    @Published var keepAliveIntervalSeconds: Int =
        UserDefaults.standard.object(forKey: "keepAlive.intervalSeconds") as? Int ?? 60 {
        didSet { UserDefaults.standard.set(keepAliveIntervalSeconds, forKey: "keepAlive.intervalSeconds") }
    }

    /// 每条连接的最后一次**真实活动**时间（心跳成功也会刷新它）。
    private var serviceLastActivity: [ServiceKey: Date] = [:]

    /// 心跳结果（界面可显示"连接已不通"）。
    @Published private(set) var keepAliveRecord = KeepAliveRecord()

    private var keepAliveTask: Task<Void, Never>?

    var keepAlivePolicy: KeepAlivePolicy {
        KeepAlivePolicy(isEnabled: isKeepAliveEnabled, intervalSeconds: keepAliveIntervalSeconds)
    }

    /// 启动心跳循环。**每 15 秒看一次**（比最小间隔还密），
    /// 只有"确实空闲够久"的连接才会收到心跳 —— 见 `KeepAliveScheduler`。
    func startKeepAliveTicker() {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                await self?.keepAliveTick()
            }
        }
    }

    /// 一次心跳检查（可单测地暴露出来：判定全在 Core 的纯函数里）。
    func keepAliveTick(now: Date = Date()) async {
        let policy = keepAlivePolicy
        guard policy.isEnabled else { return }
        for (key, service) in services {
            let last = serviceLastActivity[key] ?? now
            guard KeepAliveScheduler.shouldPing(lastActivity: last, now: now, policy: policy) else { continue }
            do {
                // 心跳语句按**该连接的方言**取（现在两个方言都是 SELECT 1，但口径要接对，
                // 免得将来加方言时这里悄悄用错）
                let dbType = connections.first { $0.id == key.connectionID }?.dbType ?? .postgresql
                _ = try await runSingleQuery(KeepAlivePolicy.statement(for: dbType), on: service)
                // **心跳成功本身也算活动**，否则它会每隔几秒连发
                serviceLastActivity[key] = now
                keepAliveRecord.record(success: true, at: now)
            } catch {
                // 失败**只记录、不打断连接**：掐断可能发生在任何一刻，
                // 工具该做的是如实报告"这条连接已经不通了"，而不是替用户弹一堆错误。
                keepAliveRecord.record(success: false, at: now, failure: ErrorPresenter.message(for: error))
            }
        }
    }

    /// 记一次真实活动（执行查询后调用），心跳据此判断"是否空闲"。
    func noteServiceActivity(for key: ServiceKey, at date: Date = Date()) {
        serviceLastActivity[key] = date
    }

    /// 归档面板是否呈现。
    @Published var isSQLArchivePresented = false

    /// 归档目录的当前状态（界面直接显示整句）。
    @Published private(set) var sqlArchiveStatus: DirectoryAccessStatus?

    /// 归档根目录的来源：单独指定 / 跟随工作区 / 没有（FR-EDIT-32 衔接）。
    @Published private(set) var sqlArchiveSource: ArchiveLocation.Source = .none

    /// 查询记忆索引（FR-AI-13 S2）：**纯派生缓存**，事实源始终是归档 `.sql` 文件。
    ///
    /// 删掉重建即可、不丢任何数据 —— 所以这里不需要任何持久化，也不必为它做迁移。
    @Published private(set) var queryMemoryIndex = QueryMemory.Index()

    /// 索引正在后台重建：避免一次执行后又触发一次重建（同一条 SQL 只该索引一遍）。
    private var isBuildingQueryMemoryIndex = false

    /// 工作区路径的提供者（由 App 层注入；AppState 不该直接依赖工作区存储）。
    var workspacePathProvider: (() -> String?)?

    /// 归档目录的书签**单独存一个文件**，免得出现在数据任务面板的「使用已授权目录」列表里。
    private let sqlArchiveBookmarks = DirectoryBookmarkStore(fileName: "sql-archive-bookmark.json")

    /// 写入串行化：两次执行几乎同时结束时不至于互相覆盖。
    private let sqlArchiveWriter = SQLArchiveWriter()

    /// 查询历史的落盘门面（`DR-02` 持久化 · 队列 `HIST-1`）—— **写入 / 清空 / 单条删 /
    /// 启动加载的唯一入口**。内存里的 `queryHistory` 只是它的回读镜像；
    /// 「500 条 / 90 天」的上限在门面 `QueryHistoryStore.prune` 那一处裁（这里不自己截断）。
    private let queryHistoryStore = QueryHistoryStore.defaultStore()
    /// App 侧调度 tick（Core 的 `TaskScheduler` 不启定时器、只做纯时间计算）。
    private var dataTaskTicker: Task<Void, Never>?
    /// 已提交审批、等待人工决定的任务执行（审批单 id → 待办）。
    private var pendingDataTaskRuns: [UUID: PendingDataTaskRun] = [:]
    /// 已尝试过的计划时刻：**同一个时间点不会被反复补跑**（错过窗口默认不自动补跑的落地）。
    private var dataTaskLastAttempts: [UUID: Date] = [:]
    /// 上次成功执行时刻（调度器判重依据；从执行历史重建，不额外落盘）。
    private var dataTaskLastSuccessfulRuns: [UUID: Date] = [:]

    /// 调度宽限：计划时间过去不超过 5 分钟算「到点」按计划执行；
    /// 超过 5 分钟的算「错过」——**只提示、不自动补跑**（客户端可能整天没打开，
    /// 一开就补跑十几个写库任务的风险远大于收益，见 Core 的 `TaskScheduler` 注释）。
    static let dataTaskGrace: TimeInterval = 300
    /// 调度 tick 间隔。
    static let dataTaskTickInterval: Duration = .seconds(30)

    // MARK: 高危语句保护（FR-EXEC-16）

    /// Safe Mode 开关；默认开启（安全默认）。用 `UserDefaults` 记住，与语言偏好同一套做法。
    @Published var isSafeModeEnabled: Bool =
        UserDefaults.standard.object(forKey: ExecutionSafetyDefaults.safeModeKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(isSafeModeEnabled, forKey: ExecutionSafetyDefaults.safeModeKey) }
    }
    /// 是否连普通写操作也要确认（默认关：凡事弹窗会让人闭眼点继续）。
    @Published var isConfirmAllWritesEnabled: Bool =
        UserDefaults.standard.object(forKey: ExecutionSafetyDefaults.confirmAllWritesKey) as? Bool ?? false {
        didSet { UserDefaults.standard.set(isConfirmAllWritesEnabled, forKey: ExecutionSafetyDefaults.confirmAllWritesKey) }
    }
    /// 被拦下、等待确认的执行请求；`nil` 表示没有待确认项。
    @Published var pendingExecution: PendingExecution?

    // 运行范围不再是一个用户设置（FR-EXEC-14，2026-09-27 需求提出者拍板）：
    // **有选区就跑选中的那段，没选区就跑整篇** —— 由 `ExecutionScope.resolve` 自动判定，
    // 工具条上那个三档菜单已删。原 `execution.scope` 这个 `UserDefaults` 键不再读取。

    // MARK: 下方面板（结果 / 问题 / 输出 / 终端 / 调试控制台）

    /// 下方面板是否显示。用 `UserDefaults` 记住，与 Safe Mode / 运行范围同一套做法。
    @Published var isLowerPaneVisible: Bool =
        UserDefaults.standard.object(forKey: "ui.lowerPaneVisible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isLowerPaneVisible, forKey: "ui.lowerPaneVisible") }
    }

    /// 下方面板是否最大化（占满编辑区，编辑器让位）。同样用 `UserDefaults` 记住。
    @Published var isLowerPaneMaximized: Bool =
        UserDefaults.standard.object(forKey: "ui.lowerPaneMaximized") as? Bool ?? false {
        didSet { UserDefaults.standard.set(isLowerPaneMaximized, forKey: "ui.lowerPaneMaximized") }
    }

    /// 下方面板的**用户拖出来的高度**（队列 `L-181`：顶边拖拽把手）。持久化，与上面两项同一套做法。
    /// 未拖过时用 `LowerPaneSizing.expandedIdealHeight`（面板默认高度口径）。
    @Published var lowerPaneHeight: CGFloat =
        UserDefaults.standard.object(forKey: "ui.lowerPaneHeight") as? Double
            ?? Double(LowerPaneSizing.expandedIdealHeight) {
        didSet { UserDefaults.standard.set(Double(lowerPaneHeight), forKey: "ui.lowerPaneHeight") }
    }

    /// 当前选中的下方面板页签。
    @Published var lowerPaneTab: LowerPaneTab =
        LowerPaneTab(rawValue: UserDefaults.standard.string(forKey: "ui.lowerPaneTab") ?? "") ?? .problem {
        didSet {
            UserDefaults.standard.set(lowerPaneTab.rawValue, forKey: "ui.lowerPaneTab")
            // 用户在**非 Database 段**又自己换了一枚（比如在工作区段点「输出」）⇒ 那次「历史」
            // 不再需要恢复 —— 「恢复上次选中」恢复的是**切走那一刻**的选中；之后用户明确点过
            // 别的，就听用户当下的（否则切回来会把他刚点的那一枚顶掉）。
            if !isHistoryPaneAvailable, lowerPaneTab != .history {
                restoresHistoryTabOnReturnToDatabase = false
            }
        }
    }

    /// 下方面板的页签里**这一档可见的那几枚**（外层页签条只画它给的那几枚）。
    ///
    /// `FR-EDIT-10`（v3.326 扩写 · 队列 `HIST-2`）：「历史」**只在 Database 客户端段出现**
    /// —— 工作区段没有查询上下文。段条件的**唯一出处就是这一句**：视图里再写一遍 `if`
    /// 就是第二处口径，页签条与将来别的消费者迟早各说各话。
    /// 序 = 问题 / 输出 / 终端 / 调试控制台 / 变更 / 回执 / 历史（`LowerPaneTab.allCases` 的顺序就是显示顺序）。
    /// **「变更」两段都在**（`FR-STD-WS-VCS-001`）：仓库身份跟着工作区走，跟用户此刻在哪一段无关；
    /// 没有工作区时那一页如实画空态，不藏起来（藏起来会让「为什么这里没有 Git」多一次提问）。
    var availableLowerPaneTabs: [LowerPaneTab] {
        isHistoryPaneAvailable ? LowerPaneTab.allCases : LowerPaneTab.allCases.filter { $0 != .history }
    }

    /// 「历史」页签本档可见吗（`FR-EDIT-10` 的段条件：仅 Database 客户端段）。
    var isHistoryPaneAvailable: Bool { selectedActivityItem == .database }

    /// 切段前「历史」是不是正被选中 —— 供「切回 Database 段 ⇒ 恢复上次选中」用。
    ///
    /// **记在内存里、不落盘**：它记的是「上一次在 Database 段选的是哪一枚」，而落盘的
    /// `ui.lowerPaneTab` 记的是**当前真正生效的那一枚**（切到工作区段时是终端）。
    private var restoresHistoryTabOnReturnToDatabase = false

    /// **段切换时的页签口径**（`FR-EDIT-10` 段条件那一句）—— 唯一一处：
    ///   · 切到**非 Database 段** ⇒ 「历史」页签隐藏；若正选中它 ⇒ 自动切到该段可用页签
    ///     （取**终端**：两段都成立、且与「执行过的 SQL」最贴近的那一页）；
    ///   · 切回 **Database 段** ⇒ 恢复上次选中（那次正是「历史」的话）。
    ///
    /// 为什么收成一个方法：`selectActivityItem` / `ensureActivitySelectionVisible` / 构造三处
    /// 都可能改段 —— 各写一段就是三份口径（本工程同族事故见 `L-143`）。
    private func syncLowerPaneTabWithSegment() {
        guard !isHistoryPaneAvailable else {
            guard restoresHistoryTabOnReturnToDatabase else { return }
            restoresHistoryTabOnReturnToDatabase = false
            lowerPaneTab = .history
            return
        }
        guard lowerPaneTab == .history else { return }
        // **先落页签、后立标记**：`lowerPaneTab` 的 `didSet` 会把「非 Database 段 + 非历史」
        // 当成用户自己换了一枚而清掉标记 —— 顺序反过来就会当场把自己刚立的那一个清掉。
        lowerPaneTab = .terminal
        restoresHistoryTabOnReturnToDatabase = true
    }

    /// 某个页签当前生效的连接：优先用它自己最近一次执行用的连接，否则退回左侧选中的连接。
    ///
    /// 编辑器与下方面板的问题页签都要用它算诊断，所以收成一处。
    func connection(for tab: QueryTab) -> ConnectionConfig? {
        if let connectionID = tab.connectionID,
           let connection = connections.first(where: { $0.id == connectionID }) {
            return connection
        }
        return selectedConnection
    }

    /// 读取一张表的结构（列 / 类型 / 可空 / 默认值 / 主键），供表结构编辑器算差异。
    func tableStructure(of object: DatabaseObject) async throws -> [TableColumnDefinition] {
        guard let configuration = selectedConnection else {
            throw AppError.notConnected
        }
        let database = object.database ?? currentDatabaseName(for: configuration)
        let metadata = try await makeMetadataService(configuration: configuration, database: database)
        return try await metadata.tableStructure(of: object)
    }

    /// 把编辑后的列定义与原始结构比对，生成并**逐条**执行 `ALTER TABLE`（FR-DDL-03）。
    ///
    /// 逐条执行而不是拼成一整段：失败时能指出是第几条，使用者知道"改到哪儿断了"。
    /// 已经执行的语句**不回滚**（DDL 在多数方言里本就不可回滚），这一点在界面提示里讲清楚。
    /// 读取一张表既有的索引与约束（FR-DDL-03 的「删」要先看得见）。
    ///
    /// 方言不支持时**返回空数组**，界面据此显示"暂不支持读取" ——
    /// 不能让人以为"这张表没有索引"。
    func tableExtras(of object: DatabaseObject) async throws -> (indexes: [TableIndexInfo], constraints: [TableConstraintInfo]) {
        guard let configuration = selectedConnection else {
            throw AppError.notConnected
        }
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        let database = object.database ?? currentDatabaseName(for: configuration)
        let service = try await ensureService(for: configuration, database: database)

        var indexes: [TableIndexInfo] = []
        if let query = dialect.tableIndexesQuery(table: object.name, schema: object.schema) {
            indexes = TableDesignChangeSet.indexes(from: try await runSingleQuery(query, on: service))
        }

        var constraints: [TableConstraintInfo] = []
        if let query = dialect.tableConstraintsQuery(table: object.name, schema: object.schema) {
            constraints = TableDesignChangeSet.constraints(from: try await runSingleQuery(query, on: service))
        }

        return (indexes, constraints)
    }

    /// 应用一份表设计变更（列 + 索引 + 外键 + 约束）。
    ///
    /// 语句顺序由 Core 决定（删约束 → 删索引 → 列变更 → 新索引 → 新外键 → 新约束）；
    /// 中间失败时**指明第几条**并让对象树刷新（前面的语句可能已生效），绝不谎报成功。
    func alterTable(_ object: DatabaseObject, changeSet: TableDesignChangeSet) async -> Bool {
        guard let configuration = selectedConnection else {
            errorMessage = L(.stateSelectConnectionFirst)
            return false
        }

        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        let statements = TableDesignChangeSet.statements(
            for: changeSet,
            table: object.name,
            schema: object.schema,
            dialect: dialect
        )
        // **未预览不得执行**（详设 §6 `DDL_PREVIEW_REQUIRED`）：预览与执行必须是同一份脚本。
        let alterScript = statements.joined(separator: "\n")
        guard DDLPreviewGate.decide(script: alterScript, previewedScript: previewedDDLScript) == .allowed else {
            errorMessage = L(.ddlPreviewRequired)
            return false
        }

        // 非空变更集却生成不出语句 = 某条输入非法（Core 整批返回空），必须说出来。
        guard !statements.isEmpty else {
            if changeSet.hasChanges {
                errorMessage = L(.tableDesignInvalid)
                return false
            }
            return true
        }

        do {
            let database = object.database ?? currentDatabaseName(for: configuration)
            let service = try await ensureService(for: configuration, database: database)
            for (index, statement) in statements.enumerated() {
                do {
                    _ = try await runSingleQuery(statement, on: service)
                } catch {
                    errorMessage = L(.tableDesignAlterFailed, index + 1, ErrorPresenter.message(for: error))
                    metadataRevision += 1 // 前面几条可能已经生效，让对象树刷新
                    return false
                }
            }

            statusMessage = L(.tableDesignAltered, object.name, "\(statements.count)")
            metadataRevision += 1
            return true
        } catch {
            errorMessage = L(.tableDesignAlterFailed, 1, ErrorPresenter.message(for: error))
            return false
        }
    }

    // MARK: - 新建表（FR-DDL-03）

    /// 按表设计生成并执行 `CREATE TABLE`。
    ///
    /// 与建库 / 删库同一套路：本地先校验 → 生成语句 → 执行 → 成功后 `metadataRevision += 1`
    /// 让对象树把新表刷出来。**界面会先把 DDL 摊开给使用者看**，所以这里不再二次确认。
    func createTable(
        named rawName: String,
        schema: String?,
        columns: [TableColumnDefinition],
        extras: TableDesignChangeSet? = nil
    ) async -> Bool {
        guard let configuration = selectedConnection else {
            errorMessage = L(.stateSelectConnectionFirst)
            return false
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TableDesign.validate(tableName: name, columns: columns).isEmpty else {
            errorMessage = L(.tableDesignInvalid)
            return false
        }

        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        let trimmedSchema = schema?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSchema = (trimmedSchema?.isEmpty ?? true) ? nil : trimmedSchema
        // **计划由 Core 给**（`createTablePlan`）：预览与执行同一份语句。
        // 以前这里自己拼"建表 + 完整变更集"，而预览拼的是"建表 + 索引/约束" ——
        // 于是每个列又被 `ADD COLUMN` 一次（MySQL：Duplicate column name 'id'，2026-09-25 实测）。
        let plan = TableDesignChangeSet.createTablePlan(
            table: name,
            columns: columns,
            schema: resolvedSchema,
            extras: extras,
            dialect: dialect
        )
        // **未预览不得执行**（详设 §6 `DDL_PREVIEW_REQUIRED`）：与 alterTable 同一口径。
        guard DDLPreviewGate.decide(script: plan.joined(separator: "\n"), previewedScript: previewedDDLScript) == .allowed else {
            errorMessage = L(.ddlPreviewRequired)
            return false
        }
        guard let createStatement = plan.first else {
            errorMessage = L(.tableDesignInvalid)
            return false
        }

        do {
            let service = try await ensureService(
                for: configuration,
                database: currentDatabaseName(for: configuration)
            )
            _ = try await runSingleQuery(createStatement, on: service)

            // 建表带的索引 / 约束：建表成功后按同一份顺序补上（各自独立语句）。
            // 中途失败要**说清第几条**并让对象树刷新 —— 表已经建出来了，不能让人以为什么都没发生。
            for (index, statement) in plan.dropFirst().enumerated() {
                do {
                    _ = try await runSingleQuery(statement, on: service)
                } catch {
                    errorMessage = L(.tableDesignAlterFailed, index + 1, ErrorPresenter.message(for: error))
                    metadataRevision += 1
                    return false
                }
            }

            statusMessage = L(.tableDesignCreated, name)
            metadataRevision += 1
            return true
        } catch {
            errorMessage = L(.tableDesignFailed, ErrorPresenter.message(for: error))
            return false
        }
    }

    /// 清空当前下方面板页签对应的日志（Problem / Output 页签上的「清空」）。
    func clearLowerPaneLog(for tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        switch lowerPaneTab {
        case .problem: tabs[index].problemLog = TabLog.cleared()
        case .output: tabs[index].outputLog = TabLog.cleared()
        // 「历史」页不是日志页（它读的是查询历史、清空走 `requestClearQueryHistory` 那条确认路）；
        // 「变更」页（`FR-STD-WS-VCS-001`）同理 —— 它的内容是 git 的输出，不是这个页签的日志。
        // 「回执」页也不吃这枚 trash —— 它的清空走自己那一页的 `clearReceipts`（口径分开：
        // 清日志不许顺手抹掉审计读数）。
        case .terminal, .debugConsole, .changes, .receipts, .history: break
        }
    }

    // MARK: 执行回执（`FR-STD-DB-TASK-003`）

    /// 回执渲染要用的文案 —— **唯一出处**（Core 里没有面向用户的字面量，这里把语言表搬过去）。
    var receiptLabels: ExecutionReceipt.ReceiptLabels {
        ExecutionReceipt.ReceiptLabels(
            title: L(.receiptTitle),
            executedAt: L(.receiptExecutedAt),
            outcome: L(.receiptOutcome),
            duration: L(.receiptDuration),
            durationFormat: { L(.receiptSeconds, $0) },
            affectedRows: L(.receiptAffectedRows),
            affectedRowsUnmeasured: L(.receiptAffectedUnmeasured),
            statements: L(.receiptStatements),
            connection: L(.receiptConnection),
            database: L(.receiptDatabase),
            scope: L(.receiptScope),
            results: L(.receiptResults),
            resultsFormat: { L(.receiptResultsFormat, $0, $1, $2) },
            resultsTruncated: { L(.receiptResultsTruncated, $0) },
            error: L(.receiptError),
            sql: L(.receiptSQL),
            redaction: L(.receiptRedaction),
            redactionFormat: { L(.receiptRedactionFormat, $0, $1, $2) },
            outcomes: [
                .succeeded: L(.receiptOutcomeSucceeded),
                .failed: L(.receiptOutcomeFailed),
                .cancelled: L(.receiptOutcomeCancelled),
                .refused: L(.receiptOutcomeRefused)
            ]
        )
    }

    /// 复制**一条**回执（验收 ②「可复制」）：上剪贴板的就是渲染后的**已脱敏**文本。
    func copyReceipt(_ receipt: ExecutionReceipt) {
        putReceiptsOnPasteboard(receipt.render(labels: receiptLabels), count: 1)
    }

    /// 复制**整本**（同一页签的全部回执，旧 → 新）。
    func copyReceipts(for tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }), !tab.receiptLog.isEmpty else {
            statusMessage = L(.receiptCopyEmpty)
            return
        }
        putReceiptsOnPasteboard(tab.receiptLog.exportText(labels: receiptLabels), count: tab.receiptLog.count)
    }

    /// 导出成 JSON 文件（验收 ②「可导出」）。写出去的是**结构里那些已脱敏字段** ——
    /// 导出路径上没有任何一处能碰到 SQL 原文（它在 `ExecutionReceipt.init` 里就没进来）。
    ///
    /// 分两半写：这一半只管**问路径**（`NSSavePanel`），落盘那一半是 `writeReceipts(_:to:)`。
    /// 为什么拆开：面板是模态的，探针点不动它（也不该在无人值守的机器上弹窗）；
    /// 而「写出去的那份 JSON 里到底有没有原文」是这条验收里唯一能把住的一环，
    /// 拆开之后探针能拿**同一个函数**、只把路径换成一个临时文件来判 —— 不另开一条写盘路。
    func exportReceipts(for tabID: UUID) -> Bool {
        guard let tab = tabs.first(where: { $0.id == tabID }), !tab.receiptLog.isEmpty else {
            statusMessage = L(.receiptExportEmpty)
            return false
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "execution-receipts.json"
        if let type = UTType(filenameExtension: "json") {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        return writeReceipts(tab.receiptLog, to: url)
    }

    /// 落盘那一半（**唯一**写盘出口，面板与探针共用）：成功返回真、并把「N 条 → 文件名」写进状态栏，
    /// 失败给可读原因并返回假（不写半截文件：`.atomic` 由这里统一给）。
    @discardableResult
    func writeReceipts(_ log: ExecutionReceiptLog, to url: URL) -> Bool {
        do {
            let data = try log.exportData()
            try data.write(to: url, options: [.atomic])
            statusMessage = L(.receiptExported, log.count, url.lastPathComponent)
            return true
        } catch {
            errorMessage = L(.receiptExportFailed, ErrorPresenter.message(for: error))
            return false
        }
    }

    /// 清空这个页签的回执（它与「清空输出日志」是两枚按钮：日志是流水，回执是审计读数）。
    func clearReceipts(for tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }), !tabs[index].receiptLog.isEmpty else {
            statusMessage = L(.receiptClearEmpty)
            return
        }
        tabs[index].receiptLog.removeAll()
        statusMessage = L(.receiptCleared)
    }

    private func putReceiptsOnPasteboard(_ text: String, count: Int) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        statusMessage = L(.receiptCopied, count)
    }

    /// 当前生效的执行安全策略。
    ///
    /// **生产标签会强制高危确认**（FR-CONN-16 与 FR-EXEC-16 的联动）：
    /// 用户把 Safe Mode 总开关关掉也照样提示 —— 总开关的语义是"别烦我"，
    /// 但生产库上误删的代价与该诉求不对称。
    var executionSafetyPolicy: ExecutionSafetyPolicy {
        ExecutionSafetyPolicy.policy(
            for: selectedConnection?.appearance ?? ConnectionAppearance(),
            isEnabled: isSafeModeEnabled,
            confirmAllWrites: isConfirmAllWritesEnabled,
            // 只读是连接的属性，不受 Safe Mode 开关影响（见 `ExecutionSafetyPolicy.isReadOnly`）
            isReadOnly: selectedConnection?.isReadOnly ?? false
        )
    }

    /// 用户点了「仍然执行」。
    ///
    /// - Parameter pending: **确认过的那个待执行项**，由弹窗所在视图直接传进来。
    ///
    /// 两处不能再这么写（2026-09-27 人工点验实测：点「仍然执行」什么都不发生）：
    /// ① **不读 `pendingExecution` 这个状态**。SwiftUI 的 `.sheet(item:)` 在关闭时会把绑定置空，
    ///    而按钮的动作是「先 `onConfirm()`（起一个 `Task`）再 `dismiss()`」—— 等 `Task` 真跑起来，
    ///    状态已经是 `nil`，`guard let … else { return }` 就**静默返回**了：既不执行，也不报错。
    ///    服务器对象面板一直把 `pending.command` 直接传进闭包（正确形状），编辑器这条照它改。
    /// ② **执行弹窗里确认过的那一份 SQL**（`sqlOverride`），不重新从编辑器解析一遍 ——
    ///    用户在弹窗上看到并批准的是这几条，期间选区变了也不该换一份跑。
    func confirmPendingExecution(_ pending: PendingExecution) async {
        pendingExecution = nil
        StartupLog.write(
            "确认执行已批准的高危语句：\(pending.statements.count) 条"
            + "（来源 \(pending.source.rawValue)，页签 \(pending.tabID.uuidString.prefix(8)))"
        )
        await executeQuery(
            for: pending.tabID,
            bypassingSafetyCheck: true,
            sqlOverride: pending.sql,
            runningSource: pending.source
        )
    }

    /// 用户点了「取消」。
    func cancelPendingExecution() {
        pendingExecution = nil
    }

    /// 判定不出可执行内容时的可读提示（**不静默改成跑整篇** —— 那等于把一次小操作放大）。
    private func message(forRunScopeIssue issue: ExecutionScope.Issue) -> String {
        switch issue {
        case .emptySelection: return L(.runScopeEmptySelection)
        case .emptyText: return L(.runScopeEmptyText)
        }
    }

    @Published var errorMessage: String?
    @Published var statusMessage: String = L(.stateNotConnected)

    private let store = ConnectionStore.shared
    // 口令存**项目内的混淆文件**（`.secrets/credentials.json`），不用系统钥匙串：
    // 钥匙串每次访问都要人工授权系统密码，远程 / IM 遥控开发时等于把自动化堵死。
    // 安全边界见 `Core/LocalSecretStore.swift`：MD5 派生密钥做 XOR 混淆 —— **是混淆不是加密**，
    /// 凭据存储：**发布形态 = 系统钥匙串**（`KeychainSecretStore`，实现在 `Platform/macOS/`）。
    ///
    /// 为什么不再写死 `FileSecretStore()`：文件实现是 **XOR 混淆**（`Core/LocalSecretStore.swift`
    /// 自己写明「是混淆不是加密」），与概要设计 §3「口令只存密钥存储」冲突
    /// （详设 §11 `DETAIL_CONFLICT` 第 1 条，2026-10-25 人类主人裁定「改实现」）。
    /// 开发 / 验收形态需要文件实现时**显式注入**，不再靠改源码默认值。
    private let secretStore: SecretStore
    private let savedQueryStore = SavedQueryStore.shared
    /// 任务册子落在哪 —— 生产恒为 `SQLTaskStore.shared`；探针可以把它指到临时目录，
    /// 免得验一次「点删除真的删掉了」就把用户真册子里那条删了。
    var sqlTaskStoreOverride: SQLTaskStore?

    private var sqlTaskStore: SQLTaskStore { sqlTaskStoreOverride ?? .shared }
    private let agentConfigurationStore = AgentConfigurationStore.shared
    /// 模型 API Key 的存储：同样是系统钥匙串（`NFR-ALL-GATE-AI-007`「密钥只进系统凭据存储」）。
    private let agentKeyStore: AgentKeyStore
    /// IM 通道凭据的落点（AppID 在配置文件、Secret 在系统钥匙串；`FR-AGT-LINK-CHAN-003`）。
    private let agentIMCredentialStore: AgentIMCredentialStore
    /// 审计日志（追加式 JSONL）；导出前脱敏在 Core 里完成（NFR-AI-03）。
    ///
    /// 探针可以把它指到**临时目录**：验一次「点拒绝 ⇒ 历史读作已拒绝」不该往用户的真审计
    /// （`agent-audit.jsonl`）里写一行 —— 与 `sqlTaskStoreOverride` 同一条纪律。
    var agentAuditLogOverride: AgentAuditLog?

    private var agentAuditLog: AgentAuditLog { agentAuditLogOverride ?? .shared }
    private let egressLog = EgressLog.shared


    /// 连接缓存键：同一个「已保存连接」可以在多个数据库上各持有一条连接。
    struct ServiceKey: Hashable {
        let connectionID: UUID
        let database: String
    }

    /// 事务上下文：**按「连接 + 数据库」归属**（FR-EXEC-15）。
    ///
    /// 事务属于连接会话而不是页签：同一连接下的多个页签共用一条连接，因此也共用同一个事务。
    /// 这也是界面必须把它显示出来的原因 —— 在别的页签里提交 / 回滚，会影响你手上这条语句。
    @Published private(set) var transactionSessions: [ServiceKey: TransactionSession] = [:]

    private var services: [ServiceKey: any DatabaseService] = [:]

    /// 探针缝（见 `ensureService`）：`nil` = 按连接真连（生产）。
    ///
    /// 为什么开在**连接的唯一收口**而不是每个只读面各开一处：会话列表 / 取消终止 /
    /// 服务器级对象 / 统计面板 / 慢查询排行这五个面都从这里取服务 ——
    /// 一处口子 ⇒ 五条都能从「界面按下去」量到「语句真的发出去」；
    /// 各开一处只会让其中一条被漏掉（漏掉的那条又会以「待人工点验」的名义挂回 🟡）。
    var serviceOverride: (any DatabaseService)?
    /// SSH 隧道（FR-CONN-18）：按连接缓存 —— 一条隧道可以被该连接的多个库共用，
    /// 断开连接时统一收掉（见 `invalidateService`）。
    private var sshTunnels: [UUID: SSHTunnelProcess] = [:]
    private var serverInfos: [UUID: ServerInfo] = [:]
    private var connectTasks: [ServiceKey: Task<(any DatabaseService, ServerInfo), Error>] = [:]
    private var executionTasks: [UUID: Task<Void, Never>] = [:]
    /// 每个页签当前这次执行的句柄：停止按钮据此**定向取消**，
    /// 而不是把同库另一个页签正在跑的语句一起干掉（R-30）。
    private var executionHandles: [UUID: ExecutionHandle] = [:]

    /// 新建查询页签的编号：应用生命周期内只增不减（关闭 / 重命名不影响）。
    private var tabNumbers = TabNumberGenerator()

    /// 「上次选中的连接」持久化键（FR-CONN-11）。
    private static let selectedConnectionDefaultsKey = "settings.selectedConnectionID"

    /// 历史条数的上限**不在这一层记**：唯一出处是门面 `QueryHistoryStore.maxEntries`（500），
    /// `DR-02` 的「500 条或 90 天（先到者为准）」在门面那一处裁（`QueryHistoryStore.prune`）。
    /// 换上限只改门面一个数，界面这一侧自动跟上。

    /// 启动链的句柄（连接 / 保存的查询 / 浏览器页签 / **笔记列表**）。
    ///
    /// 存这个句柄不是为了产品行为（它照旧不受启动链影响），而是为了**能让调用方等它落地**：
    /// 链尾那一步会去读一次笔记库，而离屏快照测试会在建完 `AppState` 之后往库里播种夹具 ——
    /// 不等就播种，那条后台读会**晚于**播种落地、把内存列表填成刚播下的那几条。
    /// 第 59 轮实测到一次真实假红（`UISnapshotPanelsTests:702`「这一步不该往内存列表里塞东西」），
    /// 就是这条抢跑：它**看运气**（读到库的时刻与播种时刻谁先谁后），不是每次必红。
    private(set) var startupChain: Task<Void, Never>?

    /// - Parameters:
    ///   - secretStore: 连接口令的存储。默认系统钥匙串；测试 / 开发态可注入 `FileSecretStore()`。
    ///   - agentKeyStore: 模型 API Key 的存储。默认系统钥匙串；同上可注入。
    ///   - agentIMCredentialStore: IM 通道凭据的存储。默认 = 配置文件（AppID）+ 系统钥匙串（Secret）。
    init(
        // 2026-10-31 05:57 实测：连库取口令走 `KeychainSecretStore` 时，钥匙串弹框会**卡住主线程**
        //（stack: SecItemCopyMatching → mach_msg 等授权），整轮对话与 IM 派活一起静默挂死，
        //  连主窗口都出不来。库口令因此也改走 0600 文件（`FileSecretStore`），钥匙串不再是热路径。
        secretStore: SecretStore = FileSecretStore(),
        // 2026-10-30 主人：「这个 keychain 太烦人了，总是要输入」——Ad-hoc 签名每装一版就变，
        // 钥匙串 ACL 跟着失效 ⇒ 改成 0600 文件后端（见 `FileAgentSecretStore` 的头注）。
        agentKeyStore: AgentKeyStore = FileAgentSecretStore(),
        agentIMCredentialStore: AgentIMCredentialStore = AgentIMCredentialStore(secretStore: FileAgentSecretStore())
    ) {
        FileAgentSecretStore.migrateFromKeychainOnce()
        self.secretStore = secretStore
        self.agentKeyStore = agentKeyStore
        self.agentIMCredentialStore = agentIMCredentialStore
        let firstTab = QueryTab(title: L(.workspaceTabTitle, tabNumbers.next()))
        tabs = [firstTab]
        selectedTabID = firstTab.id
        // 许可证决定栏上有哪几项：上次选的项在这一档可能已经不可见（Ultra 换成 Standard 时
        // `ui.activityBarItem` 里还存着 `database`）。启动就落到可见项上，否则界面会停在
        // 一个"选着但画不出来"的视图上 —— 那是最难查的一类"空白界面"。
        ensureActivitySelectionVisible()
        // **启动时对一次段与页签的口径**（`FR-EDIT-10` 段条件）：`ui.lowerPaneTab` 里可能存着
        // 「历史」，而 `ui.activityBarItem` 存的是工作区段 —— 那种组合下这一枚画不出来，
        // 面板会停在一个「选着但不显示」的页签上。判定与换段同一条（`syncLowerPaneTabWithSegment`）。
        syncLowerPaneTabWithSegment()
        // 启动时把"这一档能看到什么"记一行。理由很实际：用户来问「我的工作区 / 数据库不见了」
        // 时，看一眼 `startup.log` 就知道是哪一档、为什么（不用让他把许可证文件翻出来）。
        // 只记档位与来源，不记许可证内容。
        StartupLog.write(
            "许可证：\(licenseLoad.entitlements.edition.rawValue)"
                + " / 活动栏 [" + visibleActivityItems.map(\.rawValue).joined(separator: ",") + "]"
                + " / " + licenseSummary
        )
        // 浏览器页签的宿主接线：下载落盘目录 / 外发留痕 / 失败告知。模型只**弱**持有本类。
        workspaceBrowser.host = self
        startupChain = Task {
            await loadConnections()
            await loadSavedQueries()
            await loadSQLTasks()
            await workspaceBrowser.restoreBrowserTabs()
            // 笔记列表在启动时就载入：它现在是活动栏上的一栏，切过去必须**立刻有内容**，
            // 不能再依赖"先点一下菜单项"来触发加载。
            await reloadNotes()
            // 查询历史（`DR-02` 持久化）：启动就回读 —— 重启后历史仍在，不等「先执行一条 SQL」。
            await loadQueryHistory()
        }
    }

    var selectedConnection: ConnectionConfig? {
        connections.first { $0.id == selectedConnectionID }
    }

    var selectedTab: QueryTab? {
        tabs.first { $0.id == selectedTabID }
    }

    func serverInfo(for connectionID: UUID) -> ServerInfo? {
        serverInfos[connectionID]
    }

    func loadConnections() async {
        do {
            // 迁移与提示一起处理（FR-CONN-10）：老格式静默升级，来自更新版本的配置
            // 必须**说出来** —— 否则用户只会看到"我的连接怎么少字段了"（见 R-40）。
            let (loaded, migration) = try await store.loadWithReport()
            connections = loaded
            if migration.didMigrate {
                statusMessage = L(.connectionMigrated, migration.migrated.count)
            }
            if migration.didSkipNewer {
                let versions = migration.skippedNewerVersions.keys.sorted().map(String.init).joined(separator: "、")
                errorMessage = L(.connectionNewerVersionKept, versions)
            }
            canCreateDatabase = nil
            if selectedConnectionID == nil {
                // 上次选中的连接仍然存在时优先恢复（FR-CONN-11），否则退回第一条。
                selectedConnectionID = restoredConnectionID(in: connections) ?? connections.first?.id
            }
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func addConnection(_ configuration: ConnectionConfig, password: String, sshPassword: String? = nil) async {
        do {
            try secretStore.setPassword(password, for: configuration.id)
            try applySSHPassword(sshPassword, for: configuration.id)
            // 与 deleteConnection 同理：内存变更一次做完再落盘，
            // 否则 await 会把它拆成两轮渲染（列表先更新、选中项再跳）。
            connections.append(configuration)
            selectedConnectionID = configuration.id
            try await store.save(connections)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func updateConnection(_ configuration: ConnectionConfig, password: String?, sshPassword: String? = nil) async {
        do {
            if let password, !password.isEmpty {
                try secretStore.setPassword(password, for: configuration.id)
            }
            try applySSHPassword(sshPassword, for: configuration.id)

            invalidateService(for: configuration.id)

            if let index = connections.firstIndex(where: { $0.id == configuration.id }) {
                connections[index] = configuration
            } else {
                connections.append(configuration)
            }
            selectedConnectionID = configuration.id
            try await store.save(connections)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 只在值真的变了才写 `@Published`。
    ///
    /// 给 `@Published` 赋一个**相同的值**同样会触发一次重绘；删除连接时这类白刷会叠加成
    /// 肉眼可见的抖动，所以状态重置类赋值统一走这里。
    private func setIfChanged<T: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<AppState, T>,
        _ value: T
    ) {
        guard self[keyPath: keyPath] != value else { return }
        self[keyPath: keyPath] = value
    }

    // MARK: - 上次选中的连接

    private func restoredConnectionID(in connections: [ConnectionConfig]) -> ConnectionConfig.ID? {
        guard let raw = UserDefaults.standard.string(forKey: Self.selectedConnectionDefaultsKey),
              let id = UUID(uuidString: raw),
              connections.contains(where: { $0.id == id }) else {
            return nil
        }
        return id
    }

    private func rememberSelectedConnection() {
        guard let selectedConnectionID else {
            UserDefaults.standard.removeObject(forKey: Self.selectedConnectionDefaultsKey)
            return
        }
        UserDefaults.standard.set(
            selectedConnectionID.uuidString,
            forKey: Self.selectedConnectionDefaultsKey
        )
    }

    // MARK: - 查询历史（`DR-02` 持久化 · 门面 `QueryHistoryStore`）

    /// 清空历史（`DR-02`：可清空）—— **只有确认步会调它**（`confirmHistoryRemoval`）。
    ///
    /// **签名从同步改成了 `async`**（`HIST-2`，2026-10-08）：`HIST-1` 那一版保持同步，理由写在
    /// 「调用点在 `App/Views/QueryToolbar.swift`、本片不许碰 `App/Views/**` ⇒ 落盘 `await` 塞进
    /// `Task`」。`HIST-2` 把两个入口都改成**先挂确认请求**，调用点随之收进本类（`confirmHistoryRemoval`）
    /// —— 于是那条理由不成立了，而「确认 ⇒ 落库」这件事**必须能被判据读到**：落盘塞进游离 `Task`，
    /// 判据读到的是**清空之前**的库（本轮实测就是这么抓到的：内存已空、库里还是 3 条）。
    /// 内存那一份仍然**当场**清空（界面立刻反映），落盘 await 在本调用里完成。
    func clearQueryHistory() async {
        queryHistory.removeAll()
        do {
            try await queryHistoryStore.clear()
        } catch {
            // 落盘失败如实说出来（不静默吞）—— 下次启动回读会以后端的真值为准。
            statusMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 启动加载查询历史（`DR-02`：**重启后仍在**）。
    ///
    /// 与 `reloadNotes()` 放在同一条启动链上：历史要能在用户切到「历史」页 / 打开时钟菜单时
    /// **已经有内容**，而不是等「先执行一条 SQL」把列表喂出来。读不出来不拦启动：如实说明，列表留空。
    func loadQueryHistory() async {
        do {
            queryHistory = try await queryHistoryStore.load()
        } catch {
            statusMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 把历史 SQL 载入指定页签。
    func loadHistory(_ entry: QueryHistory, into tabID: UUID) {
        updateTab(tabID) {
            $0.sql = entry.sql
            $0.fileURL = nil
            $0.isDirty = true
        }
    }

    // MARK: - 清空 / 单条删除的确认（`DR-02`：可清空 · 单条删除）

    /// **挂在界面上的那一个（清空 / 删除）请求**（`nil` = 没有待确认的动作）。
    ///
    /// 规则（动作与顺序、文案键）在 Core `QueryHistoryRemovalPrompt` —— **唯一出处**；
    /// 这里只做搬运。判据：挂请求这一步**库一个字节不动**，直到 `confirmHistoryRemoval()`；
    /// 取消 = 只收掉请求（`TestsUISnapshot/QueryHistoryPaneProbeTests.swift`）。
    @Published var pendingHistoryRemoval: QueryHistoryRemovalRequest?

    /// 点「清空历史」：把动作摆到确认框上，**先不落库**。
    ///
    /// 两个入口（页签里的「清空」与工具条时钟菜单里那一项）都走它 ——
    /// 一处先问、另一处直接清就是「一半有的行为」（`L-143` 那一课）。
    /// 没有可清的东西时按钮是**灰着**的（判据属性 `canClearQueryHistory`，唯一出处见下）。
    func requestClearQueryHistory() {
        guard canClearQueryHistory else { pendingHistoryRemoval = nil; return }
        pendingHistoryRemoval = QueryHistoryRemovalPrompt.request(target: .all)
    }

    /// 「清空历史」有没有可清的东西 —— **判据属性唯一出处**（`L-50` ②）。
    ///
    /// `requestClearQueryHistory` 的守卫与历史页签那枚「清空」的 `.disabled` 用的是**同一条判断**；
    /// 视图侧不许再自己写一遍 `queryHistory.isEmpty`（两处各写一遍正是 `L-50` 那一轮抓到的病根）。
    /// 台账：`Scripts/empty-action-button-dispositions.json`（`view-disabled` 档）。
    var canClearQueryHistory: Bool { !queryHistory.isEmpty }

    /// 点某一条的「删除」：同上，先挂请求。
    ///
    /// `subject` = 那一条 SQL 的**单行摘要**（确认框正文里写出来，用户才知道删的是哪一条）。
    func requestDeleteHistory(_ entry: QueryHistory) {
        pendingHistoryRemoval = QueryHistoryRemovalPrompt.request(
            target: .one(entry.id),
            subject: Self.historyPreview(entry.sql)
        )
    }

    /// 退出口（按 ESC / 点框外 / 点「取消」）：只收掉请求，库一个字节不动。
    func cancelHistoryRemoval() {
        pendingHistoryRemoval = nil
    }

    /// 确认框标题（**唯一生产点**；视图不自己拼句子）。
    var pendingHistoryRemovalTitle: String? {
        guard let request = pendingHistoryRemoval else { return nil }
        return L(QueryHistoryRemovalPrompt.titleKey(for: request.target))
    }

    /// 确认框正文：单条时把那条 SQL 的摘要写出来（清空那一档是通用一句）。
    var pendingHistoryRemovalMessage: String? {
        guard let request = pendingHistoryRemoval else { return nil }
        let base = L(QueryHistoryRemovalPrompt.messageKey(for: request.target))
        // 单条才把摘要补上（清空那一档没有「哪一条」这回事）。这里是**两句拼装**，
        // 不是「空数据按钮」的前置守卫 —— 所以刻意写成 `if` 而不是 `guard`（后者会被
        // `check-empty-action-buttons.py` 当成 AppState 的空守卫要求登记，而它并不是一处按钮前置）。
        if case .one = request.target, !request.subject.isEmpty {
            return base + "\n" + request.subject
        }
        return base
    }

    /// 用户在确认框里点了「清空」/「删除」：**这才动库**，然后落地。
    func confirmHistoryRemoval() async {
        guard let request = pendingHistoryRemoval else { return }
        pendingHistoryRemoval = nil
        switch request.target {
        case .all:
            await clearQueryHistory()
        case .one(let id):
            await deleteQueryHistory(id: id)
        }
    }

    /// 删一条历史（`DR-02` 单条删）：内存镜像当场跟上，库那一侧走门面。
    ///
    /// 与 `clearQueryHistory` 同一条口径：内存先落（界面立刻反映），落盘 `await` 在本调用里完成
    /// —— 「确认 ⇒ 落库」得能被判据读到（游离 `Task` 会让判据读到删之前的库）。
    /// 落盘失败如实说出来（不静默吞），下次启动回读以后端真值为准。
    func deleteQueryHistory(id: UUID) async {
        queryHistory.removeAll { $0.id == id }
        let store = queryHistoryStore
        do {
            try await store.delete(id: id)
        } catch {
            statusMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 把一条历史**手动归档**（`FR-EDIT-10`：历史页签内的「归档」动作 → `Core/SQLArchive`）。
    ///
    /// 与执行期归档（`archiveExecutedSQL`）走**同一条写盘路**（`openQueriesDirectory` +
    /// `sqlArchiveWriter.append`）—— 不另开第二套写盘（两套迟早在一边改掉）。
    /// 目录取不到 ⇒ 用归档面板那句「未授权」如实说出来（**不静默吞**：点了没反应是这里最忌的）。
    ///
    /// **刻意不再过一遍 `memoryRecordingPolicy`**：那一句判的是「本次执行要不要记录」
    /// （`FR-AI-15`，自动记录），而这里是用户对**某一条既有历史**的显式动作 —— 两回事，
    /// 用同一句判据糊住会让显式动作看起来没反应。
    func archiveHistoryEntry(_ entry: QueryHistory) {
        let configuration = connections.first { $0.id == entry.connectionID }
        let archiveEntry = SQLArchiveEntry(
            sql: entry.sql,
            firstExecutedAt: entry.executedAt,
            lastExecutedAt: entry.executedAt,
            connection: configuration?.displayTitle(untitled: L(.connectionUntitled))
                ?? L(.connectionUntitled),
            database: selectedDatabase ?? "",
            durationSeconds: entry.duration,
            affectedRows: nil,
            succeeded: entry.succeeded,
            note: nil
        )

        Task { [weak self] in
            guard let self else { return }
            do {
                guard let opened = try await self.openQueriesDirectory() else {
                    self.statusMessage = L(.archiveDirectoryNotAuthorized)
                    return
                }
                defer { opened.grant?.stopAccessing() }
                let directory = opened.url
                let count = try await self.sqlArchiveWriter.append(archiveEntry, in: directory)
                self.reportArchived(directory: directory, count: count)
                // 刚归档的这条应该马上可用于补全（FR-AI-13 S4）；重建在后台、失败也不影响归档结果。
                await self.refreshQueryMemoryIndex()
            } catch {
                self.statusMessage = L(.archiveFailed, ErrorPresenter.message(for: error))
            }
        }
    }

    /// 「已归档到 …（当天 N 条）」这一句的**唯一生产点**（执行期归档与历史页的手动归档共用）。
    ///
    /// 为什么收成一处而不是两处各写一遍：`format-argument` 那条台账按**实参形状**记调用点
    /// （`Scripts/format-argument-dispositions.json`），同一个形状两处各写一遍就要再登记一次
    /// —— 而那正是「同一句话有两份口径」的机械形状。收成一处之后台账一处都不动。
    private func reportArchived(directory: URL, count: Int) {
        statusMessage = L(
            .archiveSaved,
            directory.deletingLastPathComponent().lastPathComponent,
            count
        )
    }

    /// 一条 SQL 的**单行摘要**（确认框正文 / 菜单项文案共用一条口径）。
    ///
    /// 换行 / 制表符压成空格、超长截断 —— 两处各写一份迟早一边改了另一边没改。
    static func historyPreview(_ sql: String, limit: Int = 48) -> String {
        let singleLine = sql
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
        return singleLine.count > limit ? String(singleLine.prefix(limit)) + "…" : singleLine
    }

    /// 读取归档目录书签并刷新状态（界面打开归档面板时调用）。
    func refreshSQLArchiveStatus() async {
        await resolveSQLArchiveStatus()
        // 归档位置可能刚变（换目录 / 工作区切换）—— 记忆索引跟着重算（FR-AI-13 S2）。
        await refreshQueryMemoryIndex()
    }

    private func resolveSQLArchiveStatus() async {
        do {
            let bookmark = try await sqlArchiveBookmarks.all().first
            let chosenStatus = bookmark.map { MacDirectoryAccess.status(for: $0) }
            // **优先级：单独指定 > 工作区 > 没有**（判定收在 Core 的 ArchiveLocation，可单测）
            guard let resolved = ArchiveLocation.queriesDirectory(
                chosenPath: chosenStatus?.path,
                workspacePath: workspacePathProvider?()
            ) else {
                sqlArchiveSource = .none
                sqlArchiveStatus = .notAuthorized
                return
            }
            sqlArchiveSource = resolved.source
            switch resolved.source {
            case .chosen:
                sqlArchiveStatus = chosenStatus
            case .workspace:
                // 跟随工作区时**没有归档自己的书签**，但工作区的书签已经授权了这块位置。
                sqlArchiveStatus = .granted(path: resolved.url.path, isStale: false)
            case .none:
                sqlArchiveStatus = .notAuthorized
            }
        } catch {
            sqlArchiveSource = .none
            sqlArchiveStatus = .resolutionFailed(reason: ErrorPresenter.message(for: error))
        }
    }

    /// 让用户选归档目录（**取消不是错误**，只是什么都不做）。
    func chooseSQLArchiveDirectory() async {
        do {
            guard let url = try dataTaskDirectoryPicker.pickDirectory(prompt: L(.archiveChooseDirectory))
            else { return }
            let bookmark = try MacDirectoryAccess.makeBookmark(for: url, displayName: L(.archiveTitle))
            _ = try await sqlArchiveBookmarks.save(bookmark)
            await refreshSQLArchiveStatus()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 归档目录路径（展示用；没授权时为 nil）。
    var sqlArchiveDirectoryPath: String? {
        sqlArchiveStatus?.path
    }

    /// 打开归档的 `queries/` 目录，并把授权范围交回调用方释放。
    ///
    /// 「单独指定 > 跟随工作区」的判定只在 `ArchiveLocation` 里写一次：
    /// 写入归档和重建记忆索引都走这里，免得两处各写一遍（补必漏）。
    private func openQueriesDirectory() async throws -> (url: URL, grant: DirectoryGrant?)? {
        var grant: DirectoryGrant?
        var chosenPath: String?
        if let bookmark = try await sqlArchiveBookmarks.all().first {
            let opened = try MacDirectoryAccess.open(bookmark)
            grant = opened
            chosenPath = opened.url.path
        }
        guard let resolved = ArchiveLocation.queriesDirectory(
            chosenPath: chosenPath,
            workspacePath: workspacePathProvider?()
        ) else {
            grant?.stopAccessing()
            return nil
        }
        return (resolved.url, grant)
    }

    /// 重建查询记忆索引（FR-AI-13 S2）。
    ///
    /// 三条纪律：
    /// 1. **纯派生** —— 事实源是归档文件，这里只重算缓存，失败就退回空索引（补全退回只有关键字）；
    /// 2. **不上主线程** —— 归档按天一个文件，一年就是几百个，解析放后台；
    /// 3. **失败不打扰用户** —— 记忆只是补全的加分项，出错不该弹任何东西。
    func refreshQueryMemoryIndex() async {
        guard isSQLArchiveEnabled else {
            queryMemoryIndex = QueryMemory.Index()
            return
        }
        // 一次执行刚写完归档又立刻重建，不如让前一次重建覆盖它 —— 索引始终是派生的，晚一点不影响正确性。
        guard !isBuildingQueryMemoryIndex else { return }
        isBuildingQueryMemoryIndex = true
        defer { isBuildingQueryMemoryIndex = false }

        do {
            guard let opened = try await openQueriesDirectory() else {
                queryMemoryIndex = QueryMemory.Index()
                return
            }
            defer { opened.grant?.stopAccessing() }
            let directory = opened.url
            let index = await Task.detached(priority: .utility) {
                QueryMemory.buildIndex(directory: directory)
            }.value
            queryMemoryIndex = index
        } catch {
            queryMemoryIndex = QueryMemory.Index()
        }
    }

    /// 把一次执行写进当天归档。
    ///
    /// **归档失败绝不影响执行结果** —— 只把可读原因写进状态栏：
    /// 一个"顺手存文件"的功能不该让查询看起来失败了。
    private func archiveExecutedSQL(
        sql: String,
        configuration: ConnectionConfig,
        database: String?,
        duration: TimeInterval,
        affectedRows: Int?,
        succeeded: Bool,
        note: String?
    ) {
        // 「本次执行不记录」（FR-AI-15）：判定收在 Core 的 `MemoryRecordingPolicy` ——
        // 这里再写一遍 `if isSQLArchiveEnabled && !suppress` 就是第二套判据，迟早漂移。
        guard memoryRecordingPolicy.shouldRecord else { return }

        let entry = SQLArchiveEntry(
            sql: sql,
            firstExecutedAt: Date(),
            lastExecutedAt: Date(),
            connection: configuration.displayTitle(untitled: L(.connectionUntitled)),
            database: database ?? "",
            durationSeconds: duration,
            affectedRows: affectedRows,
            succeeded: succeeded,
            note: note
        )

        Task { [weak self] in
            guard let self else { return }
            do {
                // 「单独指定 > 跟随工作区」的解析与记忆索引用同一个入口，不写两遍。
                guard let opened = try await self.openQueriesDirectory() else { return }
                defer { opened.grant?.stopAccessing() }
                let directory = opened.url

                // 归档落在 queries/ 子目录，避免和数据任务产物、以及工作区里的代码混在一起。
                let count = try await self.sqlArchiveWriter.append(entry, in: directory)
                self.reportArchived(directory: directory, count: count)
                // 刚写进去的这条应该马上可用于补全（FR-AI-13 S4）；重建在后台、失败也不影响执行结果。
                await self.refreshQueryMemoryIndex()
            } catch {
                self.statusMessage = L(.archiveFailed, ErrorPresenter.message(for: error))
            }
        }
    }

    /// 记录一次执行（成功与失败两条路径都经过这里 —— **单一收口点**）。
    ///
    /// `DR-02` 改判后这一段同时做两件事，但**分工不覆盖**：
    ///   · **归档**（`SQLArchive`，磁盘上的 `*.sql`）= 用户主动收藏、长期保留；
    ///   · **历史**（`QueryHistoryStore` → 库表 `query_history`）= 会话历史、有上限、可清空。
    ///
    /// 落盘失败**不改变执行结果** —— 历史写不进去只该说一声，不该让一次已经跑完的查询看起来失败了。
    private func recordHistory(
        sql: String,
        connectionID: UUID,
        duration: TimeInterval,
        succeeded: Bool,
        affectedRows: Int? = nil,
        note: String? = nil
    ) async {
        if let configuration = connections.first(where: { $0.id == connectionID }) {
            archiveExecutedSQL(
                sql: sql,
                configuration: configuration,
                database: selectedDatabase,
                duration: duration,
                affectedRows: affectedRows,
                succeeded: succeeded,
                note: note
            )
        }

        // 连续重复执行同一条 SQL 时只刷新最新一条，避免刷屏：**复用最新那一条的 id**，
        // 门面按 id 覆盖写（不新插一行、也不在库里开第二条更新写路）。
        let repeated = queryHistory.first.flatMap { first -> QueryHistory? in
            first.sql == sql && first.connectionID == connectionID ? first : nil
        }
        let entry = QueryHistory(
            id: repeated?.id ?? UUID(),
            connectionID: connectionID,
            sql: sql,
            executedAt: Date(),
            duration: duration,
            succeeded: succeeded
        )

        do {
            // 上限（500 条 / 90 天）由门面在同一处裁；回来的是**裁剪后**的完整列表（倒序）。
            queryHistory = try await queryHistoryStore.append(entry)
        } catch {
            // 落盘失败：内存镜像照旧如实更新（这次执行确实发生了），但**说出来**（不静默吞）。
            queryHistory.removeAll { $0.id == entry.id }
            queryHistory.insert(entry, at: 0)
            statusMessage = ErrorPresenter.message(for: error)
        }
    }

    // MARK: - 结果导出（FR-RES-06）

    /// 结果行数超过这个值才走流式（游标逐页）导出。
    ///
    /// 为什么要有阈值而不是"一律流式"：小结果集走游标要额外发 `BEGIN` / `DECLARE` / `CLOSE` / `COMMIT`
    /// 四条语句，**日常导出反而变慢**；而流式的收益（峰值内存与行数无关）只在结果很大时才成立。
    /// 5000 行是"人的日常"与"大结果集"之间的一条线：结果表自己的分页默认档也在同一量级。
    static let streamingExportRowThreshold = 5_000
    /// 游标每页取多少行（与 CLI 的默认档一致）。
    static let streamingExportPageSize = CursorPaging.defaultPageSize

    /// 导出当前页签的当前结果集。没有可导出内容时返回 false，由调用方提示。
    ///
    /// 两条路径（FR-RES-13）：
    /// * **大结果集（> `streamingExportRowThreshold`）且 SQL 是单条查询**：服务端游标逐页取、
    ///   逐页写盘（`ResultStreamWriter`），峰值内存与总行数无关；
    /// * 其余（小结果集 / 不是单条查询 / 处在手工事务里）：沿用一次性导出。
    ///   走不了流式时**明说原因**（`exportStreamNotPossible`），不假装流式。
    @discardableResult
    func exportResult(
        for tabID: UUID,
        format: ResultExportFormat,
        encoding: ResultExportEncoding = .utf8
    ) async -> Bool {
        guard let tab = tabs.first(where: { $0.id == tabID }),
              let result = tab.result else {
            errorMessage = L(.exportNoData)
            return false
        }

        guard ResultExporter.hasExportableContent(result) else {
            errorMessage = L(.exportNoData)
            return false
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        let baseName = tab.fileURL?.deletingPathExtension().lastPathComponent
            ?? ResultExportFormat.csv.defaultBaseName
        panel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        // xlsx 是二进制工作簿（ZIP 的中央目录要等所有行写完才能落）——**天生不能流式**。
        // 这里提前分支并如实交代，而不是让流式写入器在 begin() 里抛错（那样用户只看到"导出失败"）。
        if format.isBinary {
            reportTabStatus(L(.exportBinaryOneShot, url.lastPathComponent), for: tabID)
            do {
                let payload = try ResultExporter.data(
                    for: result,
                    format: format,
                    tableName: tab.fileURL == nil ? "table_name" : baseName
                )
                try payload.write(to: url)
                reportTabStatus(L(.exportSucceeded, result.rowCount, url.lastPathComponent), for: tabID)
                return true
            } catch {
                errorMessage = L(.exportFailed, ErrorPresenter.message(for: error))
                return false
            }
        }

        if result.rowCount > Self.streamingExportRowThreshold {
            if let reason = streamingExportRefusal(for: tab) {
                // 如实说明：这次仍然会把整份结果取回内存。写到**页签**的日志里 ——
                // 全局 `statusMessage` 没有视图在读，写进去等于没说。
                reportTabStatus(L(.exportStreamNotPossible, reason), for: tabID)
            } else {
                return await exportResultStreaming(
                    tab: tab,
                    fallbackColumns: result.columns,
                    format: format,
                    url: url,
                    baseName: baseName,
                    encoding: encoding
                )
            }
        }

        // INSERT 语句需要表名与方言：表名取页签标题（文件名为准，导出后由用户确认），
        // 方言按该页签绑定的连接决定（未绑定连接时退回 SQL 标准双引号）。
        do {
            // 用 `data(...)` 而不是 `text(...)` + UTF-8：文本格式两者等价（同一个编码），
            // 而二进制格式（xlsx）只有前者能写对；编码选择（FR-IO-07）也只有它能表达。
            let payload = try ResultExporter.data(
                for: result,
                format: format,
                tableName: tab.fileURL == nil ? "table_name" : baseName,
                dialect: connections
                    .first { $0.id == tab.connectionID }
                    .map { SQLDialectFactory.make(for: $0.dbType) },
                encoding: encoding
            )
            try payload.write(to: url)
            if encoding != .utf8 {
                reportTabStatus(L(.exportEncodingNote, encoding.shortName), for: tabID)
            }
            // 与流式路径同一处交代（页签日志）：小结果集也要看得见"导到哪个文件、多少行"。
            reportTabStatus(L(.exportSucceeded, result.rowCount, url.lastPathComponent), for: tabID)
            return true
        } catch {
            errorMessage = L(.exportFailed, ErrorPresenter.message(for: error))
            return false
        }
    }

    /// 为什么这次**不能**走流式；能走时返回 nil。
    ///
    /// 只判两类硬约束（都是"流式在语义上就不成立"，不是性能取舍）：
    /// ① 页签里的 SQL 不是**单条查询**（游标只能 `DECLARE ... CURSOR FOR <一条查询>`）；
    /// ② 当前连接正处在**手工事务**里 —— 游标导出会自己 `BEGIN` / `COMMIT`，
    ///    那会把用户的手工事务一起提交掉（`CursorPaging` 的类型注释里写明了这条责任）。
    private func streamingExportRefusal(for tab: QueryTab) -> String? {
        if let key = transactionKey(for: tab),
           let session = transactionSessions[key],
           session.phase.isOpen {
            return L(.exportStreamReasonManualTransaction)
        }
        let databaseType = connections.first { $0.id == tab.connectionID }?.dbType ?? .postgresql
        let statements = StatementSplitter(databaseType: databaseType).split(tab.sql)
        if statements.count != 1 { return L(.exportStreamReasonMultiStatement) }
        if case .failure = CursorPaging.plan(query: tab.sql, pageSize: Self.streamingExportPageSize) {
            return L(.exportStreamReasonNotQuery)
        }
        return nil
    }

    /// 流式导出：服务端游标逐页取 → `ResultStreamWriter` 逐页写盘。
    ///
    /// 与 CLI 的 `exportQueryToFile` 是同一条口径（同一对 Core 类型），差别只在进度写进页签日志。
    /// 取数方式是**重跑页签里的 SQL** —— 所以界面上的结果集与导出的内容在"行的顺序不保证一致"
    /// 这一点上必须诚实：没有 `ORDER BY` 的查询本来就不保证顺序，这里不额外排序
    /// （排序需要全量数据，正好会毁掉流式的意义）。
    private func exportResultStreaming(
        tab: QueryTab,
        fallbackColumns: [ColumnMeta],
        format: ResultExportFormat,
        url: URL,
        baseName: String,
        encoding: ResultExportEncoding = .utf8
    ) async -> Bool {
        guard let configuration = connection(for: tab) else {
            errorMessage = L(.exportFailed, AppError.notConnected.localizedDescription)
            return false
        }
        let database = tab.database?.isEmpty == false
            ? tab.database!
            : queryDatabase(for: configuration)
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        do {
            let service = try await ensureService(for: configuration, database: database)
            return await exportResultStreaming(
                tab: tab,
                fallbackColumns: fallbackColumns,
                format: format,
                url: url,
                baseName: baseName,
                encoding: encoding,
                dialect: dialect,
                service: service
            )
        } catch {
            errorMessage = L(.exportFailed, ErrorPresenter.message(for: error))
            return false
        }
    }

    /// 流式导出的**唯一落地口**（取数与写盘那一段）。
    ///
    /// 为什么把 service / dialect 提成形参：与 `streamTable` 同一条口径 —— 「服务从哪来」由调用方
    /// 决定，于是探针能拿假服务把这条链**真跑一遍**（真 `CursorFetcher` 逐页取、真
    /// `ResultStreamWriter` 逐页写盘），而不是只能靠人在保存面板上点一次。
    ///
    /// - Parameter onReport: 写盘结束后的读数（行数 / 字节数 / 落盘次数）。生产调用不传；
    ///   判据拿它证明「确实是分块落盘」而不是「攒到最后一次写出去」。
    func exportResultStreaming(
        tab: QueryTab,
        fallbackColumns: [ColumnMeta],
        format: ResultExportFormat,
        url: URL,
        baseName: String,
        encoding: ResultExportEncoding = .utf8,
        dialect: any SQLDialect,
        service: any DatabaseService,
        onReport: ((ResultStreamWriter.Report) -> Void)? = nil
    ) async -> Bool {
        let plan: CursorPagingPlan
        switch CursorPaging.plan(query: tab.sql, pageSize: Self.streamingExportPageSize) {
        case .success(let value): plan = value
        case .failure(let error):
            errorMessage = L(.exportFailed, error.localizedDescription)
            return false
        }

        do {
            // `BEGIN` / `DECLARE` / `CLOSE` / `COMMIT` 都**没有结果集**，所以不能走
            // `runSingleQuery`（它把"没有结果集"当错误）—— 与 CLI 一样只取最后一个结果集，没有就空着。
            let fetcher = CursorFetcher(plan: plan, execute: { [self] sql in
                try await runTakingLastResultSet(sql, service: service)
            })
            var streamWriter: ResultStreamWriter?
            do {
                try await fetcher.open()
                guard let first = try await fetcher.nextPage() else {
                    await fetcher.close()
                    errorMessage = L(.exportStreamNoRows)
                    return false
                }

                // 列定义取自**第一页**（流式路径的真正来源），拿不到时退回当前结果集的列。
                let writer = ResultStreamWriter(
                    targetURL: url,
                    format: format,
                    columns: first.columns.isEmpty ? fallbackColumns : first.columns,
                    tableName: tab.fileURL == nil ? "table_name" : baseName,
                    dialect: dialect,
                    encoding: encoding
                )
                streamWriter = writer

                try writer.begin()
                try writer.write(first.rows)
                reportTabStatus(
                    L(.exportStreamProgress, await fetcher.rowCount, await fetcher.pageCount),
                    for: tab.id
                )
                while let page = try await fetcher.nextPage() {
                    try writer.write(page.rows)
                    reportTabStatus(
                        L(.exportStreamProgress, await fetcher.rowCount, await fetcher.pageCount),
                        for: tab.id
                    )
                }
                let report = try writer.finish()
                onReport?(report)
                reportTabStatus(
                    L(
                        .exportStreamSucceeded,
                        report.rowCount,
                        await fetcher.pageCount,
                        url.lastPathComponent
                    ),
                    for: tab.id
                )
                return true
            } catch {
                streamWriter?.abort()
                await fetcher.close()
                errorMessage = L(.exportFailed, ErrorPresenter.message(for: error))
                return false
            }
        } catch {
            errorMessage = L(.exportFailed, ErrorPresenter.message(for: error))
            return false
        }
    }

    // MARK: - 整表 / 整库导出（FR-STD-DB-IO-002）

    /// 「执行一条语句、只取最后一个结果集」的唯一出口。
    ///
    /// 为什么抽出来：`BEGIN` / `DECLARE` / `CLOSE` / `COMMIT` 都没有结果集，而 `runSingleQuery`
    /// 把「没有结果集」当错误。这条循环原来写在流式结果集导出里，整表导出要用同一条 ——
    /// 两处各写一份的话，一处改了另一处没改，两边的「空页 / 空结果集」口径迟早对不上。
    func runTakingLastResultSet(_ sql: String, service: any DatabaseService) async throws -> QueryResult {
        var last: QueryResult?
        for try await event in service.execute(sql, options: .default) {
            if case .resultSet(let result) = event { last = result }
        }
        return last ?? QueryResult()
    }

    /// 整表 / 整库导出的小结（sheet 的数据源）。
    ///
    /// 为什么要有它：验收要点 ④ 要求「完成后报告行数与文件路径」，而对象树上的动作**没有页签**
    /// （`reportTabStatus` 得给 tabID，全局 `statusMessage` 的下读方又是页签的 outputLog）
    /// ⇒ 这条路线的成果原来无处可看。小结单独成一块面板，整库导出（下一批）复用同一个。
    struct TableExportSummary: Identifiable, Equatable {
        enum Phase: Equatable { case running, done, failed }
        let id = UUID()
        var title: String
        var phase: Phase
        var text: String
    }

    @Published var tableExportSummary: TableExportSummary?

    /// 整表 / 整库导出的空表结局：一页都取不到 ⇒ 连列定义都没有，生成不了只有表头的文件。
    ///
    /// 单独一个错误类型（而不是抛一句裸字符串）是为了让整库那条路能把它**按表**记进账：
    /// 一张空表不该让整批停下，也不该被报成「导出成功」。
    struct TableExportEmptyTable: LocalizedError {
        var errorDescription: String? { L(.tableExportEmpty) }
    }

    /// 一张表 → 一个文件的**唯一**落地口（整表导出与整库导出共用）。
    ///
    /// 取数走服务端游标逐页取、写盘走 `ResultStreamWriter` 逐页写 —— 与 CLI 同一条路，
    /// 因此界面导出的文件与命令行导出的文件同源，不另造一套（CLI 那条已真机验证：
    /// 12 万行 / 27 MB，内存增量远小于数据量，见需求规格 R-036）。
    ///
    /// 为什么抽成一处：整库导出要按名单反复调用它，两处各写一份循环的话，
    /// 「空表算失败还是成功」「取到一半出错要不要留半成品」这类口径迟早分叉。
    ///
    /// - Returns: 写成的行数。
    /// - Throws: 名字非法 / 空表（`TableExportEmptyTable`）/ 取数与写盘的任何错误。
    func streamTable(
        _ table: String,
        schema: String?,
        to url: URL,
        format: ResultExportFormat,
        dialect: any SQLDialect,
        service: any DatabaseService,
        onProgress: (Int, Int) -> Void
    ) async throws -> Int {
        let query = try TableExport.selectSQL(table: table, schema: schema, dialect: dialect)
        let plan: CursorPagingPlan
        switch CursorPaging.plan(query: query, pageSize: Self.streamingExportPageSize) {
        case .success(let value): plan = value
        case .failure(let error): throw error
        }
        let fetcher = CursorFetcher(plan: plan, execute: { [self] sql in
            try await runTakingLastResultSet(sql, service: service)
        })
        var writer: ResultStreamWriter?
        do {
            try await fetcher.open()
            // 空表要**在写盘之前**认出来：游标的第一页就是「取到 0 行」，
            // 而 `CursorFetcher.nextPage()` 对空页返回的是**那一页本身**（不是 nil ——
            // nil 只表示「已经取完」）。早先只判 nil，于是空表会落一个只有表头的文件、
            // 面板还报「导出成功 0 行」；验收要点 ③ 要的是「表里没有行…没有生成文件」。
            guard let first = try await fetcher.nextPage(), !first.rows.isEmpty else {
                await fetcher.close()
                throw TableExportEmptyTable()
            }
            let streamWriter = ResultStreamWriter(
                targetURL: url,
                format: format,
                columns: first.columns,
                tableName: table,
                dialect: dialect,
                encoding: .utf8
            )
            writer = streamWriter
            try streamWriter.begin()
            try streamWriter.write(first.rows)
            onProgress(await fetcher.rowCount, await fetcher.pageCount)
            while let page = try await fetcher.nextPage() {
                try streamWriter.write(page.rows)
                onProgress(await fetcher.rowCount, await fetcher.pageCount)
            }
            let report = try streamWriter.finish()
            await fetcher.close()
            return report.rowCount
        } catch {
            writer?.abort()
            await fetcher.close()
            throw error
        }
    }

    /// 对象树右键「导出整表…」的唯一落地口。
    ///
    /// 取数与写盘全部交给 `streamTable`（整库导出走同一条），这里只管界面层的三件事：
    /// 连接与方言能不能走流式、名字能不能用、文件存到哪。
    func exportTable(_ object: DatabaseObject, format: ResultExportFormat) async {
        guard let configuration = selectedConnection else {
            statusMessage = L(.stateSelectConnectionFirst)
            return
        }
        // 服务端游标只有 PostgreSQL 有 —— 在**入口**就拦住，并给一条今天就能走的路，
        // 而不是让用户点一个必然失败的按钮。
        guard TableExport.streamingSupported(configuration.dbType) else {
            tableExportSummary = TableExportSummary(
                title: L(.tableExportTitle),
                phase: .failed,
                text: L(.tableExportUnsupported, configuration.dbType.displayName)
            )
            return
        }
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        // 名字先查一遍：不让用户先选完保存路径再被告知「这张表导不了」。
        do {
            _ = try TableExport.selectSQL(table: object.name, schema: object.schema, dialect: dialect)
        } catch {
            tableExportSummary = TableExportSummary(
                title: L(.tableExportTitle),
                phase: .failed,
                text: L(.tableExportBadName, object.name)
            )
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(TableExport.safeBaseName(object.name)).\(format.fileExtension)"
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        tableExportSummary = TableExportSummary(
            title: L(.tableExportTitle),
            phase: .running,
            text: L(.tableExportRunning, 0, 0)
        )
        var ledger = TableExport.Ledger()
        do {
            let database = object.database?.isEmpty == false ? object.database : configuration.database
            let service = try await ensureService(for: configuration, database: database)
            let rows = try await streamTable(
                object.name,
                schema: object.schema,
                to: url,
                format: format,
                dialect: dialect,
                service: service
            ) { [weak self] rows, pages in
                self?.tableExportSummary?.text = L(.tableExportRunning, rows, pages)
            }
            ledger.record(.succeeded(table: object.name, rows: rows, path: url.path))
            tableExportSummary = TableExportSummary(
                title: L(.tableExportDoneTitle),
                phase: .done,
                text: ledger.report(labels: tableExportLabels(), orderGuaranteed: false)
            )
        } catch {
            ledger.record(.failed(table: object.name, reason: ErrorPresenter.message(for: error)))
            tableExportSummary = TableExportSummary(
                title: L(.tableExportFailedTitle),
                phase: .failed,
                text: ledger.report(labels: tableExportLabels(), orderGuaranteed: false)
            )
        }
    }

    /// 对象树右键「导出整库…」的唯一落地口（`FR-STD-DB-IO-002` 的整库那一半）。
    ///
    /// 与整表导出**同一条取数路**（`streamTable`）、**同一个格式清单**（右键菜单里那份子菜单）、
    /// **同一块小结面板**（`TableExportSheet`）—— 三处复用是这一批的口径：
    /// 另写一套「整库专用」的循环，就等着两条路的说法分叉。
    ///
    /// 逐表结局进 `TableExport.Ledger`：一张失败**不许**把前面导成的也一起变成「失败」，
    /// 用户要的是「哪几张成了、哪几张没成、各多少行」。
    func exportDatabase(_ object: DatabaseObject, format: ResultExportFormat) async {
        guard let configuration = selectedConnection else {
            statusMessage = L(.stateSelectConnectionFirst)
            return
        }
        guard TableExport.streamingSupported(configuration.dbType) else {
            tableExportSummary = TableExportSummary(
                title: L(.tableExportDatabaseTitle),
                phase: .failed,
                text: L(.tableExportUnsupported, configuration.dbType.displayName)
            )
            return
        }

        // 名单：树的一层子节点；碰到 schema 节点就再展开一层（PG 的树是 库 → schema → 表）。
        let candidates: [TableExport.Candidate]
        do {
            candidates = try await exportCandidates(for: object)
        } catch {
            tableExportSummary = TableExportSummary(
                title: L(.tableExportFailedTitle),
                phase: .failed,
                text: L(.tableExportFailedLine, object.name, ErrorPresenter.message(for: error))
            )
            return
        }
        let plan = TableExport.databasePlan(candidates, format: format)
        guard !plan.isEmpty else {
            tableExportSummary = TableExportSummary(
                title: L(.tableExportFailedTitle),
                phase: .failed,
                text: L(.tableExportNoTables, object.name)
            )
            return
        }

        // 落点：选一个目录（不选文件）—— 整库导出是「十来张表各一个文件」，
        // 逐个弹保存面板等于让用户点十几次。
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L(.tableExportChooseFolder)
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        let database = object.database?.isEmpty == false ? object.database : configuration.database
        var ledger = TableExport.Ledger()
        tableExportSummary = TableExportSummary(
            title: L(.tableExportDatabaseTitle),
            phase: .running,
            text: L(.tableExportDatabaseRunning, 1, plan.jobs.count, plan.jobs[0].label, 0)
        )
        do {
            let service = try await ensureService(for: configuration, database: database)
            ledger = await streamDatabase(
                plan: plan,
                directory: directory,
                format: format,
                dialect: dialect,
                service: service
            ) { index, total, label, rows in
                self.tableExportSummary?.text = L(.tableExportDatabaseRunning, index, total, label, rows)
            }
        } catch {
            // 连服务都建不起来（连接断了 / 权限不足）：整批一张都导不出来，如实报在对象名上。
            ledger.record(.failed(table: object.name, reason: ErrorPresenter.message(for: error)))
        }

        var text = ledger.report(labels: tableExportLabels(), orderGuaranteed: false)
        if plan.skippedCount > 0 {
            text += "\n" + L(.tableExportSkipped, plan.skippedCount)
        }
        let anyFailure = ledger.failedCount > 0
        tableExportSummary = TableExportSummary(
            title: anyFailure ? L(.tableExportFailedTitle) : L(.tableExportDoneTitle),
            phase: anyFailure ? .failed : .done,
            text: text
        )
    }

    /// 整库导出**逐表落盘那一半**（面板之后），单拎出来是为了它能被探针真跑一遍。
    ///
    /// 口径三条，与整表导出**同一处**：取数与写盘都走 `streamTable`；一张失败只记一笔账、
    /// **不打断**整批；账分成功 / 没成两栏，没成的行数不并进总数。
    ///
    /// 名字收窄成一条缝的理由：`exportDatabase` 里那一段只跟「有没有面板」有关，剩下的
    /// 「按名单逐张导 → 记账」是纯逻辑 —— 不抽出来的话，这一段永远只能靠人点一次来验。
    ///
    /// - Parameter onProgress: (第几张, 共几张, 这一张的称呼, 这一张已取行数)。
    func streamDatabase(
        plan: TableExport.DatabasePlan,
        directory: URL,
        format: ResultExportFormat,
        dialect: any SQLDialect,
        service: any DatabaseService,
        onProgress: (Int, Int, String, Int) -> Void = { _, _, _, _ in }
    ) async -> TableExport.Ledger {
        var ledger = TableExport.Ledger()
        for (index, job) in plan.jobs.enumerated() {
            let url = directory.appendingPathComponent(job.fileName)
            do {
                let rows = try await streamTable(
                    job.table,
                    schema: job.schema,
                    to: url,
                    format: format,
                    dialect: dialect,
                    service: service
                ) { rows, _ in
                    onProgress(index + 1, plan.jobs.count, job.label, rows)
                }
                ledger.record(.succeeded(table: job.label, rows: rows, path: url.path))
            } catch {
                // 单张失败不打断整批：后面还有表要导，账上记一笔就继续。
                ledger.record(.failed(table: job.label, reason: ErrorPresenter.message(for: error)))
            }
        }
        return ledger
    }

    /// 整库导出的名单来源：对象树**一层**子节点；schema 节点再展开一层。
    ///
    /// 用与树**同一个**取数方法（`loadMetadataChildren`）—— 另写一条「整库专用」的元数据查询，
    /// 迟早和树上看到的东西对不上（树上 8 张、导出 7 张是最难查的一类缺陷）。
    private func exportCandidates(for object: DatabaseObject) async throws -> [TableExport.Candidate] {
        let children = try await loadMetadataChildren(of: object)
        var candidates: [TableExport.Candidate] = []
        for child in children {
            if child.kind == .schema {
                let nested = try await loadMetadataChildren(of: child)
                candidates += nested.map { TableExport.Candidate($0, fallbackSchema: child.name) }
            } else {
                candidates.append(
                    TableExport.Candidate(
                        child,
                        fallbackSchema: object.kind == .schema ? object.name : nil
                    )
                )
            }
        }
        return candidates
    }


    /// 导出小结的文案来源（与 `TableExport.Labels` 一一对应，实参与模板写在同一句里）。
    private func tableExportLabels() -> TableExport.Labels {
        TableExport.Labels(
            row: { table, rows, path in L(.tableExportRowLine, table, rows, path) },
            failedRow: { table, reason in L(.tableExportFailedLine, table, reason) },
            summary: { ok, failed, rows in L(.tableExportSummaryLine, ok, failed, rows) },
            orderNote: L(.tableExportOrderNote)
        )
    }

    // MARK: - 结果集内联编辑（FR-DATA-04）

    /// 生成内联编辑将要执行的 DML 计划（**不执行任何东西**）。
    ///
    /// 分工写清楚：语句怎么拼、要不要拒绝，全部由 Core 的 `InlineEdit.plan` 决定
    /// （预览与执行因此是**同一份**语句）；这里只负责三件界面层的事 ——
    /// ① 来源表从哪来（只认 `QueryTab.sourceTable`，没有就**不猜表名**）；
    /// ② 主键 / 可空这些列元信息从**表结构**读（不靠结果集猜）；
    /// ③ 用页签所在连接的方言。
    func inlineEditPlan(
        for tabID: UUID,
        rows: [[String?]],
        changes: [InlineEdit.Change]
    ) async throws -> InlineEdit.Plan {
        guard let tab = tabs.first(where: { $0.id == tabID }), let result = tab.result else {
            throw AppError.queryFailed(L(.stateQueryNoResultSet))
        }
        // 手写 SQL 的结果没有来源表：直说，不去猜一个表名。
        guard let source = tab.sourceTable else {
            throw AppError.invalidConfiguration(L(.inlineEditNoSourceTable))
        }
        guard let configuration = connection(for: tab) else {
            throw AppError.notConnected
        }
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        guard let query = dialect.tableStructureQuery(table: source.name, schema: source.schema) else {
            throw AppError.notImplemented(L(.inlineEditUnsupportedDialect))
        }

        let database = tab.database?.isEmpty == false
            ? tab.database!
            : queryDatabase(for: configuration)
        let service = try await ensureService(for: configuration, database: database)
        let definitions = MetadataService.columnDefinitions(from: try await runSingleQuery(query, on: service))
        let columns = definitions.map {
            InlineEdit.Column(
                name: $0.name,
                typeName: $0.typeName,
                isPrimaryKey: $0.isPrimaryKey,
                isNullable: $0.isNullable
            )
        }

        // `rows` 由界面传进来的是**当前显示的那些行**（分页 / 排序 / 筛选之后），
        // 它们与 `result.columns` 逐列对齐 —— 所以 `columnNames` 必须取同一份列顺序，
        // 否则按主键定位的 WHERE 会读到别的列（这类错位在预览里几乎看不出来）。
        return InlineEdit.plan(
            table: source.name,
            schema: source.schema,
            columnNames: result.columns.map(\.name),
            columns: columns,
            rows: rows,
            changes: changes,
            dialect: dialect,
            // 拒绝理由会原样显示在预览弹窗里 → 用**当前界面语言**生成（R-45 的同一类问题）。
            // 「当前界面语言」= 宿主语境优先（L-13）：取 `effectiveLanguage` 而不是用户选择，
            // 否则离屏快照里会出现"界面中文、这句英文"的混排。
            language: LocalizationManager.shared.effectiveLanguage
        )
    }

    /// 执行一份**已经预览过**的计划：单个事务，任何一条失败即整批回滚。
    ///
    /// 事务语义由 Core 的 `InlineEdit` 刻画（一批变更一个事务、失败整批回滚），
    /// 这里不发明新的语义 —— 只是把 `beginTransaction` / `commit` / `rollback` 照做。
    @discardableResult
    func applyInlineEdit(_ plan: InlineEdit.Plan, for tabID: UUID) async -> Bool {
        guard plan.isApplicable else {
            errorMessage = L(.inlineEditPlanFailed, plan.refusals.first ?? "")
            return false
        }
        guard let tab = tabs.first(where: { $0.id == tabID }),
              let configuration = connection(for: tab) else {
            errorMessage = L(.inlineEditPlanFailed, AppError.notConnected.localizedDescription)
            return false
        }
        // 手工事务里**不做**内联编辑：这里要自己 `BEGIN`，会把用户的事务一起提交掉。
        if let key = transactionKey(for: tab),
           let session = transactionSessions[key],
           session.phase.isOpen {
            errorMessage = L(.inlineEditManualTransaction)
            return false
        }

        let database = tab.database?.isEmpty == false
            ? tab.database!
            : queryDatabase(for: configuration)
        do {
            let service = try await ensureService(for: configuration, database: database)
            try await service.beginTransaction()
            do {
                for statement in plan.statements {
                    for try await _ in service.execute(statement, options: .default) {}
                }
                try await service.commit()
            } catch {
                try? await service.rollback()
                errorMessage = L(.inlineEditRolledBack, ErrorPresenter.message(for: error))
                return false
            }
            reportTabStatus(L(.inlineEditSucceeded, plan.statements.count), for: tabID)
            return true
        } catch {
            errorMessage = L(.inlineEditPlanFailed, ErrorPresenter.message(for: error))
            return false
        }
    }

    // MARK: - 逐段恢复到指定库（FR-IO-05）

    /// 逐段恢复到**指定的目标库**：结构（pre-data）→ 数据（data）→ 索引与约束（post-data）。
    ///
    /// 为什么由这里循环而不是让界面循环：段的顺序是**依赖顺序**，而"停在哪一段"必须变成
    /// 一条能直接粘的续跑命令 —— 那条命令由 Core 的 `RestoreResume.hint` 生成（已有单测与
    /// 真机脚本钉着），界面只负责把它显示出来，不另拼一份。
    ///
    /// 遇错即停（`exitOnError`）是硬要求：不停下来，就不知道该从哪一段接着做。
    @discardableResult
    func runRestoreSections(_ plan: BackupPlan, password: String?) async -> Int32 {
        guard let archive = plan.filePath, !archive.isEmpty,
              let database = plan.target.database, !database.isEmpty else {
            backupRestoreLog = [L(.backupRestoreTargetDatabaseHint)]
            return 64
        }

        backupRestoreLog = []
        isBackupRunning = true
        defer { isBackupRunning = false }

        for section in RestoreSection.allCases {
            var sectionPlan = plan
            sectionPlan.section = section.rawValue
            sectionPlan.exitOnError = true
            let name = restoreSectionName(section)

            backupRestoreLog.append(L(.backupRestoreSectionStarting, name))
            backupRestoreLog.append(L(.backupRestoreLogCommand, sectionPlan.displayCommand(password: password)))
            do {
                let result = try await BackupExecutor(runner: backupRunner).execute(sectionPlan, password: password) { [weak self] line in
                    Task { @MainActor in self?.backupRestoreLog.append("  " + line) }
                }
                if result.isFailure {
                    backupRestoreLog.append(L(.backupRestoreSectionFailed, name, Int(result.exitCode)))
                    if let summary = result.failureSummary { backupRestoreLog.append(summary) }
                    appendRestoreResumeHint(archive: archive, database: database, failed: section, jobs: plan.jobs, clean: plan.clean)
                    return result.exitCode
                }
            } catch {
                // 沙箱下起 `pg_restore` 会被拒：沿用既有指引口径，不放宽沙箱。
                backupRestoreLog.append(L(.backupSandboxHint))
                backupRestoreLog.append(L(.backupRestoreLogReason, error.localizedDescription))
                appendRestoreResumeHint(archive: archive, database: database, failed: section, jobs: plan.jobs, clean: plan.clean)
                return 68
            }
        }

        backupRestoreLog.append(L(.backupRestoreSectionsDone))
        return 0
    }

    /// 失败后把"接下来做什么"写进日志：停在哪一段 + 可粘贴的续跑命令（Core 生成）。
    ///
    /// 面板在**一次性 / 单段**恢复失败时也调它（`failed` 为 nil 表示"这次没分段，不知道停在哪"）——
    /// 续跑建议只有一处产出，界面各入口共用，免得三条路径各写一种说法。
    func appendRestoreResumeHint(
        archive: String,
        database: String,
        failed: RestoreSection?,
        jobs: Int?,
        clean: Bool
    ) {
        if let failed {
            backupRestoreLog.append(L(.backupRestoreStopped, restoreSectionName(failed)))
        } else {
            backupRestoreLog.append(L(.backupRestoreFailedUnknownSection))
        }
        backupRestoreLog.append(L(.backupRestoreResumeLead))
        backupRestoreLog.append(RestoreResume.hint(
            archivePath: archive,
            database: database,
            failed: failed,
            jobs: jobs,
            clean: clean
        ))
    }

    /// 段的**界面文案**：`RestoreSection.displayName` 是 Core 层的中文短名（CLI 也在用），
    /// 界面按当前语言取自己那份，避免英文界面里冒出中文。
    private func restoreSectionName(_ section: RestoreSection) -> String {
        switch section {
        case .preData: return L(.backupRestoreSectionPreData)
        case .data: return L(.backupRestoreSectionData)
        case .postData: return L(.backupRestoreSectionPostData)
        }
    }

    func deleteConnection(_ configuration: ConnectionConfig) async {
        do {
            try secretStore.deletePassword(for: configuration.id)
            // 隧道口令是**另一个键**（由连接 ID 派生，见 `SSHTunnelSecrets`）：不清就会在
            // 钥匙串里留下一条谁也认不出来的孤儿秘密。
            try? secretStore.deletePassword(for: SSHTunnelSecrets.secretKey(for: configuration.id))
            invalidateService(for: configuration.id)

            // 内存里的两处变更**必须在同一次同步执行里做完**，落盘推到它们之后。
            // 原先的顺序是「先删列表 → await 落盘 → 再改选中项」：那个 await 会把
            // 「列表里已经没有它、选中项还指着它」的中间状态交给界面渲染一次，
            // 于是侧栏选中行瞬间指向一个不存在的行再跳到别的行 —— 就是删除连接时
            // 界面连闪的来源（实测一次删除会出现 4 次这种中间状态）。
            let wasSelected = selectedConnectionID == configuration.id
            connections.removeAll { $0.id == configuration.id }
            if wasSelected {
                selectedConnectionID = connections.first?.id
            }

            try await store.save(connections)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 把表单里的 SSH 口令写进（或清出）钥匙串。
    ///
    /// 三种输入对应三种动作，语义写死在注释里，免得以后有人"顺手简化"：
    ///   · `nil`  → **不改动**已存的口令（编辑已有连接时留空就是这个）；
    ///   · `""`   → 明确清除（换成 agent / 普通私钥后，旧口令不该再留着）；
    ///   · 非空   → 写入。
    private func applySSHPassword(_ sshPassword: String?, for connectionID: UUID) throws {
        guard let sshPassword else { return }
        let key = SSHTunnelSecrets.secretKey(for: connectionID)
        if sshPassword.isEmpty {
            try secretStore.deletePassword(for: key)
        } else {
            try secretStore.setPassword(sshPassword, for: key)
        }
    }

    func password(for configuration: ConnectionConfig) -> String? {
        do {
            if let fileStore = secretStore as? FileSecretStore {
                // 多候选之后，"口令读不到"必须能自己说清是在哪儿找的 ——
                // 否则沙箱构建读不到项目内那份时，只能靠人猜（本轮就踩过这个坑）。
                if let password = try fileStore.password(for: configuration.id) {
                    return password
                }
                let searched = fileStore.searchedLocations().map(\.path).joined(separator: "、")
                errorMessage = L(.stateMissingPassword) + "\n" + L(.statePasswordSearched, searched)
                return nil
            }
            return try secretStore.password(for: configuration.id)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
            return nil
        }
    }

    // MARK: - 元数据（对象树）

    /// 对象树里当前选中的节点。
    ///
    /// 为什么由 AppState 持有、而不是留在 `ObjectTreeView` 的 `@State`：
    /// ⌘K 命令面板是**全局**入口，而「浏览数据 / 查看 DDL / 合成数据」都必须作用在
    /// "用户在树里选中的那个对象"上。面板自己猜一个对象比直说"请先选中"更糟，
    /// 所以选中项必须放在两个入口都能读到的地方。
    @Published var selectedTreeObject: DatabaseObject?

    /// 全库对象搜索面板（FR-META-12 的界面部分）的呈现开关。
    ///
    /// 面板挂在 `MainWindow` 上（那里永远在视图树里），由对象树的工具条按钮与 ⌘K 一起打开。
    @Published var isObjectSearchPresented = false

    // MARK: - 对象树：连接 / 断开 / 建库权限（FR-META-11）

    /// 当前连接是否已建立（对象树根部以此决定菜单里「连接 / 断开」的可用性）。
    var isObjectTreeConnected: Bool {
        guard let configuration = selectedConnection else { return false }
        return services.keys.contains { $0.connectionID == configuration.id }
    }

    /// 连接状态机（概设 §6.1 闭集 · 详设 §4.4）。界面只读该值呈现「加载中 / 错误」两态；
    /// 流转必须走 `applyConnectionState`，非法流转记日志并按现状保持（不静默「修好」）。
    @Published private(set) var objectTreeConnectionState: ConnectionState = .idle

    /// 上一次**在预览里被用户看过**的结构脚本（详设 `DDL_PREVIEW_REQUIRED` 的唯一依据）。
    @Published private(set) var previewedDDLScript: String?

    /// 记录预览（由设计面板在用户点「执行/应用」时把**当时展示的脚本**交进来）。
    func recordDDLPreview(_ script: String) { previewedDDLScript = script }

    /// 未保存关闭的待确认页签（`nil` = 没有待确认）。
    @Published var pendingCloseTabID: UUID?
    /// 已确认关闭的页签快照（内存，有界；详设 `T-4.4-08`）。
    @Published private(set) var closedTabSnapshots = ClosedTabSnapshotStore()

    /// 唯一写入口：合法才改，非法留痕不动。
    private func applyConnectionState(_ next: ConnectionState) {
        guard let moved = objectTreeConnectionState.transition(to: next) else {
            StartupLog.write(
                "连接状态非法流转被拒：\(objectTreeConnectionState.rawValue) → \(next.rawValue)"
            )
            return
        }
        objectTreeConnectionState = moved
    }

    /// 右键菜单「连接」：按当前连接/数据库建立连接，并顺带刷新建库权限。
    func connectObjectTree() async {
        guard let configuration = selectedConnection else {
            errorMessage = L(.stateSelectConnectionFirst)
            return
        }

        applyConnectionState(.connecting)
        do {
            let database = currentDatabaseName(for: configuration)
            _ = try await ensureService(for: configuration, database: database)
            applyConnectionState(.connected)
            statusMessage = L(
                .objectTreeStatusConnected,
                configuration.displayTitle(untitled: L(.connectionUntitled))
            )
            await refreshDatabaseCreationPermission()
        } catch {
            applyConnectionState(.failed)
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 右键菜单「断开」：释放该连接的所有服务实例（含对象树按需建立的其它库连接）。
    func disconnectObjectTree() async {
        guard let configuration = selectedConnection else { return }

        invalidateService(for: configuration.id)
        applyConnectionState(.disconnected)
        serverInfos[configuration.id] = nil
        canCreateDatabase = nil
        statusMessage = L(
            .objectTreeStatusDisconnected,
            configuration.displayTitle(untitled: L(.connectionUntitled))
        )
    }

    /// 探测「当前用户能否创建数据库」，结果写入 `canCreateDatabase`（FR-META-11）。
    ///
    /// 探测失败或方言不支持时置为 nil：按「未知 = 不呈现」处理，避免给出会失败的入口。
    func refreshDatabaseCreationPermission() async {
        guard let configuration = selectedConnection else {
            canCreateDatabase = nil
            return
        }

        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        guard let query = dialect.databaseCreationPrivilegeQuery() else {
            canCreateDatabase = nil
            return
        }

        do {
            let service = try await ensureService(
                for: configuration,
                database: currentDatabaseName(for: configuration)
            )
            let result = try await runSingleQuery(query, on: service)
            canCreateDatabase = PrivilegeProbe.databaseCreationAllowed(
                from: result.rows.first?.first ?? nil
            )
        } catch {
            canCreateDatabase = nil
        }
    }

    /// 右键菜单「新建数据库」：执行 `CREATE DATABASE`，成功后刷新数据库列表与对象树。
    @discardableResult
    func createDatabase(named rawName: String) async -> Bool {
        guard let configuration = selectedConnection else {
            errorMessage = L(.stateSelectConnectionFirst)
            return false
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PrivilegeProbe.isValidDatabaseName(name) else {
            errorMessage = L(.createDatabaseInvalid)
            return false
        }

        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        let sql = "CREATE DATABASE \(dialect.quoteIdentifier(name))"

        do {
            let service = try await ensureService(
                for: configuration,
                database: currentDatabaseName(for: configuration)
            )
            _ = try await runSingleQuery(sql, on: service)

            statusMessage = L(.createDatabaseSucceeded, name)
            await loadDatabases()
            metadataRevision += 1
            return true
        } catch {
            errorMessage = L(.createDatabaseFailed, ErrorPresenter.message(for: error))
            return false
        }
    }

    /// 「库属性…」/「删除数据库…」的目标库：优先上下文栏选择，其次连接配置里的库。
    ///
    /// 服务器节点本身不带数据库，因此入口必须以「当前正在用的库」为目标，
    /// 而不是猜一个名字。
    var adminTargetDatabase: String? {
        guard let configuration = selectedConnection else { return nil }
        let selected = selectedDatabase?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selected, !selected.isEmpty { return selected }
        let configured = currentDatabaseName(for: configuration)
        return configured.isEmpty ? nil : configured
    }

    // MARK: - 库属性 / 删除数据库（FR-SESS-05）

    /// 生成 `ALTER DATABASE` 语句，供界面**执行前预览**（不执行）。
    func alterDatabaseStatements(
        name: String,
        alterations: SQLGenerator.DatabaseAlterations
    ) -> String? {
        guard let configuration = selectedConnection else { return nil }
        return SQLGenerator.alterDatabase(
            name: name,
            alterations: alterations,
            dialect: SQLDialectFactory.make(for: configuration.dbType)
        )
    }

    /// 执行 `ALTER DATABASE`（FR-SESS-05）；成功后刷新数据库列表与对象树。
    @discardableResult
    func alterDatabase(
        name: String,
        alterations: SQLGenerator.DatabaseAlterations
    ) async -> Bool {
        guard let configuration = selectedConnection else {
            errorMessage = L(.stateSelectConnectionFirst)
            return false
        }
        guard let sql = alterDatabaseStatements(name: name, alterations: alterations) else {
            errorMessage = L(.dbPropsInvalid)
            return false
        }

        do {
            let service = try await ensureService(
                for: configuration,
                database: currentDatabaseName(for: configuration)
            )
            try await runStatements(sql, databaseType: configuration.dbType, on: service)

            statusMessage = L(.dbPropsSucceeded, name)
            await loadDatabases()
            metadataRevision += 1
            return true
        } catch {
            errorMessage = L(.dbPropsFailed, ErrorPresenter.message(for: error))
            return false
        }
    }

    /// 生成 `DROP DATABASE` 语句，供界面**执行前预览**（不执行）。
    func dropDatabaseStatement(name: String, ifExists: Bool = true) -> String? {
        guard let configuration = selectedConnection else { return nil }
        return SQLGenerator.dropDatabase(
            name: name,
            ifExists: ifExists,
            dialect: SQLDialectFactory.make(for: configuration.dbType)
        )
    }

    /// 执行 `DROP DATABASE`（FR-SESS-05）。
    ///
    /// 调用方必须先完成「手输库名」二次确认；这里只负责执行与**可读的错误归类**
    /// （「还有其他会话连接」等由 `DatabaseAdminHint` 翻成整句提示）。
    @discardableResult
    func dropDatabase(name: String) async -> Bool {
        guard let configuration = selectedConnection else {
            errorMessage = L(.stateSelectConnectionFirst)
            return false
        }
        guard let sql = dropDatabaseStatement(name: name) else {
            errorMessage = L(.createDatabaseInvalid)
            return false
        }

        do {
            let service = try await ensureService(
                for: configuration,
                database: currentDatabaseName(for: configuration)
            )
            try await runStatements(sql, databaseType: configuration.dbType, on: service)

            statusMessage = L(.dropDbSucceeded, name)
            await loadDatabases()
            metadataRevision += 1
            return true
        } catch {
            errorMessage = L(.dropDbFailed, dropDatabaseFailureReason(error))
            return false
        }
    }

    /// 把删库失败归类成可读原因；无法归类时回退为原始错误文本。
    private func dropDatabaseFailureReason(_ error: Error) -> String {
        let raw = ErrorPresenter.message(for: error)
        switch DatabaseAdminHint.classify(serverMessage: raw) {
        case .activeConnections:
            return L(.dropDbActiveConnections)
        case .currentDatabase:
            return L(.dropDbCurrentDatabase)
        case .databaseDoesNotExist:
            return L(.dropDbNotExist)
        case .insufficientPrivilege:
            return L(.dropDbNoPrivilege)
        case nil:
            return raw
        }
    }

    // MARK: - 对象权限（FR-SESS-04）

    /// 查询指定角色在当前库上的已授权限；方言不支持时抛可读错误。
    func loadObjectPrivileges(role rawRole: String) async throws -> [ObjectPrivilege] {
        guard let configuration = selectedConnection else {
            throw AppError.notConnected
        }

        let role = rawRole.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PrivilegeProbe.isValidRoleName(role) else {
            throw AppError.queryFailed(L(.privilegeInvalidRole))
        }

        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        guard let query = dialect.objectPrivilegeQuery(role: role) else {
            throw AppError.notImplemented(L(.privilegeUnsupported))
        }

        let service = try await ensureService(
            for: configuration,
            database: currentDatabaseName(for: configuration)
        )
        let result = try await runSingleQuery(query, on: service)
        return ObjectPrivilegeParser.privileges(from: result)
    }

    /// 生成 `GRANT` / `REVOKE` 语句，供界面**执行前预览**（不执行）。
    func privilegeStatement(
        _ change: SQLGenerator.PrivilegeChange,
        revoke: Bool
    ) -> String? {
        guard let configuration = selectedConnection else { return nil }
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        return revoke
            ? SQLGenerator.revoke(change, dialect: dialect)
            : SQLGenerator.grant(change, dialect: dialect)
    }

    /// 执行 `GRANT` / `REVOKE`（FR-SESS-04；界面已先展示预览 SQL）。
    @discardableResult
    func applyPrivilegeChange(
        _ change: SQLGenerator.PrivilegeChange,
        revoke: Bool
    ) async -> Bool {
        guard let configuration = selectedConnection else {
            errorMessage = L(.stateSelectConnectionFirst)
            return false
        }
        guard let sql = privilegeStatement(change, revoke: revoke) else {
            errorMessage = L(.privilegeInvalid)
            return false
        }

        do {
            let service = try await ensureService(
                for: configuration,
                database: currentDatabaseName(for: configuration)
            )
            try await runStatements(sql, databaseType: configuration.dbType, on: service)
            statusMessage = L(.privilegeSucceeded)
            return true
        } catch {
            errorMessage = L(.privilegeFailed, ErrorPresenter.message(for: error))
            return false
        }
    }

    // MARK: - 智能体接入配置（FR-AI-01）

    // MARK: - 联网检索（`FR-AGT-TOOL-INGEST-004`）

    /// 联网 key 的落盘处（与模型 key / IM 凭据分开槽位，0600 文件）。
    private let webSecretStore = FileAgentSecretStore()

    /// 后端选择：`auto`（有 Tavily key 就走它）/ 强制 DDG / 强制 Tavily。
    var agentWebSearchBackend: AgentWebSearchConfig.Backend {
        get {
            let raw = UserDefaults.standard.string(forKey: "agent.webSearch.backend") ?? "auto"
            return AgentWebSearchConfig.Backend(rawValue: raw) ?? .auto
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "agent.webSearch.backend") }
    }

    /// 当前生效的联网配置（key 从 0600 文件读，**不回显**）。
    var agentWebSearchConfig: AgentWebSearchConfig {
        let key = (try? webSecretStore.webSearchKey()) ?? nil
        return AgentWebSearchConfig(backend: agentWebSearchBackend, tavilyAPIKey: key)
    }

    /// 设置页那一行读数：当前到底走谁（`auto` 解析之后的结果，不是用户点的那个选项）。
    var agentWebSearchBackendLine: String { agentWebSearchConfig.displayName }

    /// 保存 Tavily key：只进文件、只回一句「已配置 / 长度 / 尾 4 位」。
    func saveAgentWebSearchKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try? webSecretStore.deleteWebSearchKey()
            return "已清除 Tavily key"
        }
        do {
            try webSecretStore.setWebSearchKey(trimmed)
            let tail = String(trimmed.suffix(4))
            return "已保存（长度 \(trimmed.count)，尾 4 位 \(tail)）"
        } catch {
            return "保存失败：\(error.localizedDescription)"
        }
    }

    /// 凭据后端开关：`false` = 全部走 0600 文件（`FileAgentSecretStore` / `FileSecretStore`），
    /// 启动与对话链上**一次都不碰钥匙串**。切回钥匙串要同时把 `secretStore` 的注入换回去。
    static let credentialsUseKeychain = false

    /// 读取智能体配置与 Key 状态（进入面板 / 启动时调用）。
    ///
    /// 配置读失败不弹错误框：退回安全默认即可（关掉开关不会外发任何东西），
    /// 把原因留在状态栏，避免一个坏文件把整个界面卡在错误弹窗里。
    func loadAgentConfiguration() async {
        do {
            agentConfiguration = try await agentConfigurationStore.load()
        } catch {
            agentConfiguration = .default
            statusMessage = L(.agentSaveFailed, ErrorPresenter.message(for: error))
        }

        // 凭据后端：本机开发形态**一律 0600 文件**（主人 2026-10-31：
        // 「还是不用 keychain 了，每次打开要输入无数次密码」）。钥匙串的 ACL 绑签名，
        // 开发期每装一版签名就变 ⇒ 每次启动都要重新授权，等于不可用；这两步都会碰钥匙串，
        // 于是在文件后端下**整个跳过**（不是「读失败就算了」，是根本不发起那次读）。
        if Self.credentialsUseKeychain {
            // 钥匙串不可用时（未签名 / 无授权）按「没有 Key」处理，不阻断界面。
            migrateLegacySecretsIfNeeded()
            // ★00：把**旧签名留下的**条目按当前这套签名重写一遍并记账（同一签名下只做一次）。
            reconcileKeychainCredentials()
        }
        let key = (try? agentKeyStore.apiKey()) ?? nil
        agentAPIKey = key
        hasAgentAPIKey = !(key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        // IM 通道凭据：读不到就按「没配」处理（钥匙串不可用不该把设置面板锁死）。
        refreshAgentIMCredentials()
    }

    /// 把盘上与钥匙串里的通道凭据读进界面状态（AppID 明文 + Secret 只留长度与尾 4）。
    func refreshAgentIMCredentials() {
        guard let status = try? agentIMCredentialStore.status(for: .qq) else {
            agentIMAppID = ""
            hasAgentIMSecret = false
            agentIMSecretLength = nil
            agentIMSecretTail = nil
            return
        }
        agentIMAppID = status.appID ?? ""
        hasAgentIMSecret = status.secretConfigured
        agentIMSecretLength = status.secretLength
        agentIMSecretTail = status.secretTail
        // 配置面与凭据同一份文件：刷新凭据时一起读，避免「凭据换了、地址还是上一次的」。
        agentIMSettings = agentIMCredentialStore.settings(for: .qq)
    }

    /// 存通道凭据。`secret` 传 nil（面板留空）⇒ 只改 AppID，不动已存的 Secret。
    /// - Returns: 是否成功；失败原因落在 `errorMessage`，不吞。
    @discardableResult
    func saveAgentIMCredentials(appID: String, secret: String?, clearFirst: Bool = false) -> Bool {
        do {
            if clearFirst {
                try agentIMCredentialStore.clear(for: .qq)
                refreshAgentIMCredentials()
                statusMessage = L(.agentIMCleared)
                return true
            }
            _ = try agentIMCredentialStore.save(appID: appID, secret: secret, for: .qq)
            refreshAgentIMCredentials()
            statusMessage = L(.agentIMSaved)
            return true
        } catch let problem as AgentIMCredentialProblem {
            errorMessage = AgentIMCredentialRejectionText.line(
                for: problem, language: LocalizationManager.shared.effectiveLanguage)
            return false
        } catch {
            errorMessage = L(.agentSaveFailed, ErrorPresenter.message(for: error))
            return false
        }
    }


    // MARK: - IM 通道：配置面 / 连接 / 测试（`FR-AGT-LINK-CHAN-003`）

    /// 通道要连起来还缺什么（面板、连接按钮、测试按钮读**同一份**答复）。
    var agentIMReadiness: AgentIMReadiness {
        AgentIMReadiness.evaluate(settings: agentIMSettings,
                                  appID: agentIMAppID,
                                  secretConfigured: hasAgentIMSecret)
    }

    /// 面板那一行状态：配置齐不齐 + 传输层状态合成**一档**（不许出现「未配置」与「已连接」并存）。
    var agentIMStatusKind: AgentIMStatusKind {
        AgentIMStatusKind.of(readiness: agentIMReadiness, connection: agentIMConnectionState)
    }

    private var agentIMLanguage: AppLanguage { LocalizationManager.shared.effectiveLanguage }

    /// 存配置面（环境 / 自建中继 / 开关）。校验失败时**什么都不落盘**，原因写进 `errorMessage`。
    ///
    /// ★0 之后这里不再有「网关端点」与「机器人标识」：地址由程序自己取（`AgentIMQQProvisioner`）。
    /// 环境或中继地址**变了就断开**：留着连接 = 面板显示「已连接」而实际连的是上一个环境 ——
    /// 最坏的一种假绿。
    @discardableResult
    func saveAgentIMSettings(environment: AgentIMQQEnvironment?,
                             relayURL: String,
                             receiveTasks: Bool) -> Bool {
        let draft = AgentIMChannelSettings(environment: environment,
                                           relayURL: relayURL,
                                           receiveTasks: receiveTasks)
        let changedGateway = draft.environment != agentIMSettings.environment
            || draft.relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
                != agentIMSettings.relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let clean = try agentIMCredentialStore.save(settings: draft, for: .qq)
            agentIMSettings = clean
            statusMessage = L(.agentIMSaved)
            // 关掉「接收任务」= 真断开：留着连接却一条都不投递，面板上那句「已连接」就是假话。
            if !clean.receiveTasks, agentIMTransport != nil {
                disconnectAgentIM(reason: "receiveDisabled")
            } else if changedGateway, agentIMTransport != nil {
                // 换了环境 / 中继：手里那条连接与那把 token 都不对应现在的配置。
                disconnectAgentIM(reason: "settingsChanged")
            }
            return true
        } catch let problem as AgentIMSettingsProblem {
            errorMessage = AgentIMSettingsProblemText.line(for: problem, language: agentIMLanguage)
            return false
        } catch {
            errorMessage = L(.agentSaveFailed, ErrorPresenter.message(for: error))
            return false
        }
    }

    // MARK: - 凭据 → token → 网关（★0：地址由程序自己取）

    /// 取一把能用的 token：还新鲜就复用，快到期才换，同时来的调用共用一次请求（`AgentIMQQTokenVault`）。
    private func fetchAgentIMQQToken() async throws -> AgentIMQQToken {
        guard let environment = agentIMSettings.environment else {
            throw AgentIMQQProvisionProblem.environmentMissing
        }
        let appID = agentIMAppID
        let secret = (try? agentIMCredentialStore.secret(for: .qq)) ?? nil
        guard let secret else { throw AgentIMQQProvisionProblem.secretMissing }
        let provisioner = agentIMProvisioner
        return try await agentIMTokenVault.current(fetch: {
            try await provisioner.requestToken(appID: appID, secret: secret, environment: environment)
        })
    }

    /// 一次准备齐（token + 网关地址）；**连接与测试都只调这一个**（两处各写一遍就会「测通了、连不上」）。
    private func provisionAgentIM() async throws -> AgentIMQQProvisioning {
        guard let environment = agentIMSettings.environment else {
            throw AgentIMQQProvisionProblem.environmentMissing
        }
        let token = try await fetchAgentIMQQToken()
        let relay = (try? AgentIMSettingsValidator.normalizedRelayURL(agentIMSettings.relayURL)) ?? nil
        let gateway: AgentIMQQGatewayResolution
        if let relay {
            gateway = AgentIMQQGatewayResolution(url: relay, source: .relay)
        } else {
            gateway = await agentIMProvisioner.resolveGateway(token: token, environment: environment)
        }
        return AgentIMQQProvisioning(token: token, gateway: gateway)
    }

    /// token 那一行（只有尾 4 位；句子的拼法在 Core，界面不自己拼）。
    var agentIMTokenLine: String {
        guard let preview = agentIMTokenPreview else { return "" }
        return AgentIMQQProvisionText.tokenLine(redacted: preview, language: agentIMLanguage)
    }

    /// 地址那一行读数落进面板（**取到的 / 兜底的 / 自建中继**说不同的话）。
    private func recordAgentIMProvisioning(_ provisioning: AgentIMQQProvisioning) {
        agentIMTokenPreview = provisioning.token.redactedPreview
        agentIMGatewayLine = AgentIMQQProvisionText.gatewayLine(for: provisioning.gateway,
                                                               language: agentIMLanguage)
    }

    /// 官方握手口径：头与 Identify 都**现取** token（到期前换；换不到就用手上那把再试一次）。
    private func makeAgentIMQQHandshake(fallbackToken: AgentIMQQToken) -> AgentIMGatewayHandshake {
        AgentIMGatewayHandshake(
            authorizationHeaders: { [weak self] in
                guard let self else { return fallbackToken.authorizationHeaders }
                let token = (try? await self.fetchAgentIMQQToken()) ?? fallbackToken
                return token.authorizationHeaders
            },
            identify: { [weak self] in
                guard let self else { return AgentIMQQHandshake.identifyFrame(token: fallbackToken) }
                let token = (try? await self.fetchAgentIMQQToken()) ?? fallbackToken
                return AgentIMQQHandshake.identifyFrame(token: token)
            },
            heartbeat: { sequence in
                AgentIMQQHandshake.heartbeatFrame(sequence: sequence)
            },
            sequence: { text in AgentIMQQHandshake.sequence(of: text) },
            decode: { text, at in AgentIMQQHandshake.decode(text, receivedAt: at) },
            // 断线恢复：带 session id 与最后 seq 发 `op=6`，网关把断线期间的 event 补回来。
            resume: { [weak self] sessionID, sequence in
                guard let self else { return nil }
                let token = (try? await self.fetchAgentIMQQToken()) ?? fallbackToken
                return AgentIMQQHandshake.resumeFrame(token: token, sessionID: sessionID, sequence: sequence)
            })
    }

    /// 建连：配置齐才动手；缺什么 / 取不到 token 都**当场说出来**，不静默失败。
    /// 启动时**自动接上** IM 通道（`FR-AGT-LINK-CHAN-003`）。
    ///
    /// 主人 2026-10-30：「QQ 通道虽然配置了，但还是不能对话」——根因之一：连接只在
    /// 「智能体设置 → IM 通道 → 连接」那一下发生，**重启就断**，而人不会每次开 App 都去点一遍。
    /// 口径：凭据齐（`readiness.isReady`）且「接收任务」开着 ⇒ 启动即连；关着就老实不连。
    func startAgentIMIfConfigured() {
        guard agentIMSettings.receiveTasks else {
            StartupLog.write("IM 启动：接收任务关着，不自动连")
            return
        }
        guard agentIMReadiness.isReady else {
            StartupLog.write("IM 启动：凭据不齐（\(AgentIMStatusText.fieldList(agentIMReadiness.missing, language: agentIMLanguage))），不自动连")
            return
        }
        StartupLog.write("IM 启动：自动连接")
        connectAgentIM()
    }

    func connectAgentIM() {
        let readiness = agentIMReadiness
        guard readiness.isReady else {
            agentIMProbeLine = L(.agentIMTestNotReady,
                                 AgentIMStatusText.fieldList(readiness.missing, language: agentIMLanguage))
            return
        }
        guard agentIMTransport == nil else { return }
        agentIMConnectionState = .connecting(attempt: 1)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let provisioning = try await self.provisionAgentIM()
                self.recordAgentIMProvisioning(provisioning)
                guard self.agentIMTransport == nil else { return }
                self.startAgentIMTransport(with: provisioning)
            } catch let problem as AgentIMQQProvisionProblem {
                self.agentIMProbeLine = AgentIMQQProvisionText.line(for: problem, language: self.agentIMLanguage)
                self.agentIMConnectionState = .stopped(reason: "connectFailed")
                StartupLog.write("IM 建连失败（取 token / 地址那一档）：\(self.agentIMProbeLine)")
            } catch {
                self.agentIMProbeLine = L(.agentIMTestOpenFailed)
                self.agentIMConnectionState = .stopped(reason: "connectFailed")
                StartupLog.write("IM 建连失败（其它）：\(error)")
            }
        }
    }

    /// 真正把传输层建起来（**官方路径走 token 头 + Identify；自建中继沿用 HMAC 头 + 本侧 ping**）。
    private func startAgentIMTransport(with provisioning: AgentIMQQProvisioning) {
        let usesRelay = !agentIMSettings.relayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let secret = ((try? agentIMCredentialStore.secret(for: .qq)) ?? nil) ?? ""
        let transport = AgentIMTransport(
            config: AgentIMTransportConfig(gatewayURL: provisioning.gateway.url),
            signer: AgentIMGatewaySigner(appID: agentIMAppID, secret: secret),
            makeSocket: AgentIMSocketFactories.webSocket(),
            handshake: usesRelay ? nil : makeAgentIMQQHandshake(fallbackToken: provisioning.token),
            log: { line in StartupLog.write(line) })
        agentIMTransport = transport
        // 结果队列**在 start() 之前**接上：连上那一刻的补发走的就是这条真路
        // （连完再接 = 断线期间攒下的结论要等下一次重连才出去）。
        let queue = agentIMResultQueue
        Task { [weak self] in
            await transport.attachResultQueue(queue)
            await transport.onStateChange { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    self.agentIMConnectionState = state
                    // **状态要留痕**：2026-10-31 主人报「QQ 发消息没回应」，而日志里只有一句
                    // 「IM 启动：自动连接」——连没连上、断在哪一档，全看不出来。
                    StartupLog.write("IM 状态：\(state)")
                    // 连上就把官方那条路的未投递结论补发一遍（传输层只补 WebSocket 那一路）。
                    if state.isOnline { await self.flushAgentIMOutboundQueue() }
                }
            }
            await transport.onInbound { [weak self] frame in
                await MainActor.run { self?.acceptAgentIMInbound(frame) }
            }
            await transport.start()
        }
    }

    /// 断开（`reason` 是机器码：面板会翻成人话，`receiveDisabled` = 用户关掉了接收开关，
    /// `settingsChanged` = 换了环境 / 中继地址）。
    func disconnectAgentIM(reason: String = "stopped") {
        guard let transport = agentIMTransport else { return }
        agentIMTransport = nil
        // 断开就把 token 作废：下一次连接必须按**当前**配置重新取（否则会拿着上一个环境的 token 去连）。
        Task { await agentIMTokenVault.reset() }
        Task { await transport.stop(reason: reason) }
    }

    /// 测试连接：**先取 token 与地址**（取不到就报那一档），再真发一帧看网关答不答。
    ///
    /// 只判 `open` 成功 = 把「握手口径错」画成通；官方路径的第一帧是 Identify（不是 ping）。
    func testAgentIMConnection() async -> String {
        let readiness = agentIMReadiness
        guard readiness.isReady else {
            let line = L(.agentIMTestNotReady,
                         AgentIMStatusText.fieldList(readiness.missing, language: agentIMLanguage))
            agentIMProbeLine = line
            return line
        }
        let provisioning: AgentIMQQProvisioning
        do {
            provisioning = try await provisionAgentIM()
        } catch let problem as AgentIMQQProvisionProblem {
            let line = AgentIMQQProvisionText.line(for: problem, language: agentIMLanguage)
            agentIMProbeLine = line
            return line
        } catch {
            let line = L(.agentIMTestOpenFailed)
            agentIMProbeLine = line
            return line
        }
        recordAgentIMProvisioning(provisioning)
        let usesRelay = !agentIMSettings.relayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let secret = ((try? agentIMCredentialStore.secret(for: .qq)) ?? nil) ?? ""
        let headers = usesRelay
            ? AgentIMGatewaySigner(appID: agentIMAppID, secret: secret)
                .headers(timestamp: Int(Date().timeIntervalSince1970),
                         nonce: UUID().uuidString,
                         body: "")
            : provisioning.token.authorizationHeaders
        let frame = usesRelay ? nil : AgentIMQQHandshake.identifyFrame(token: provisioning.token)
        let outcome = await AgentIMConnectivityProbe.run(
            makeSocket: AgentIMSocketFactories.webSocket(),
            url: provisioning.gateway.url,
            headers: headers,
            frame: frame)
        let line = AgentIMConnectivityProbe.line(for: outcome,
                                                 receiveTimeout: AgentIMConnectivityProbe.defaultReceiveTimeout,
                                                 language: agentIMLanguage)
        agentIMProbeLine = line
        return line
    }

    /// 入站一帧：**先过策略**（开关关掉 / 离线 / 没配齐 一条都不收），再**真跑一轮**，
    /// 结论经结果队列推回原 chat（`FR-AGT-LINK-CHAN-003` 后半）。
    ///
    /// 顺序不在界面这一层定 —— `AgentIMInboundRunner.handle` 是唯一一条链
    /// （策略 → 去重 → 建任务 → 跑 → 入队 → 推 → 推成才 ack）；这里只把两个闭包给它：
    /// 一个跑（接进界面的对话模型，审批照旧）、一个推（传输层 send）。
    private func acceptAgentIMInbound(_ frame: AgentIMInboundFrame) {
        guard case .message(let message) = frame else { return }
        // 留痕（2026-10-30 主人「配置了但不能对话」）：整条链每一步都写一行，
        // 出问题能直接指着日志说卡在哪一步，不靠猜。
        StartupLog.write("IM 收到消息 id=\(message.platformMessageID) chat=\(message.chatID) 字数=\(message.text.count)")
        let runner = makeAgentIMInboundRunner()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await runner.handle(frame,
                                              receiveTasks: self.agentIMSettings.receiveTasks,
                                              readiness: self.agentIMReadiness,
                                              connection: self.agentIMConnectionState,
                                              language: self.agentIMLanguage)
            StartupLog.write("IM 一轮结束 outcome=\(String(describing: outcome))")
            self.recordAgentIMInbound(outcome, message: message)
        }
    }

    /// 组装一条链（会话映射 / 结果队列 / 去重台账都落盘，重启接着用）。
    private func makeAgentIMInboundRunner() -> AgentIMInboundRunner {
        AgentIMInboundRunner(sessionMap: AgentIMSessionMap(directory: AgentIMResultQueue.defaultDirectory),
                             resultQueue: agentIMResultQueue,
                             ledger: agentIMInboundLedger,
                             run: { [weak self] task in
                                 guard let self else { return .unavailable(code: "noRunner") }
                                 return await self.runAgentIMTask(task)
                             },
                             deliver: { [weak self] entry in
                                 guard let self else { return false }
                                 return await self.deliverAgentIMResult(entry)
                             })
    }

    /// **Agent 那条 shell**：每个工作区根一条，建一次复用（`cd` / 变量才能延续）。
    ///
    /// 第一次要到它时建会话并通知宿主开一个终端页签 —— 于是「命令在 Terminal 里跑」
    /// 不是一句说法，而是人能在面板上看见的那条会话。
    private var agentShellSessions: [String: AgentShellSession] = [:]
    var onAgentShellReady: ((AgentShellSession) -> Void)?

    func agentShell(for workspacePath: String) -> AgentShellSession {
        if let existing = agentShellSessions[workspacePath] { return existing }
        let shell = AgentShellSession(workingDirectory: workspacePath)
        agentShellSessions[workspacePath] = shell
        _ = shell.startIfNeeded()
        onAgentShellReady?(shell)
        return shell
    }

    /// 跑一轮：**同一时刻只跑一条**（同时进来两条时第二条如实回「上一轮还在跑」，
    /// 不排队、也不并行 —— 两条并行会互相盖上下文）。
    private func runAgentIMTask(_ task: AgentIMTask) async -> AgentIMTaskRunResult {
        guard let runner = agentIMTaskRunner else {
            StartupLog.write("IM 跑一轮：没有注入 runner（noRunner）")
            return .unavailable(code: "noRunner")
        }
        guard !agentIMRunInFlight else { return .unavailable(code: "busy") }
        agentIMRunInFlight = true
        StartupLog.write("IM 跑一轮开始 chat=\(task.chatID) 会话=\(task.sessionID)")
        defer { agentIMRunInFlight = false }
        // **硬超时**：一轮挂住（等审批 / 模型不返回）时，人在这边只会看到「没反应」——
        // 超时就如实回一句，并把结局写进日志，不静默。
        let result = await withTaskGroup(of: AgentIMTaskRunResult?.self) { group in
            group.addTask { await runner(task) }
            group.addTask {
                try? await Task.sleep(nanoseconds: 180 * 1_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let result {
            StartupLog.write("IM 跑一轮结束 result=\(String(describing: result))")
            return result
        }
        StartupLog.write("IM 跑一轮超时（180s，按超时回话）")
        return .unavailable(code: "timeout")
    }

    /// 推一条已入队的结果。
    ///
    /// 两条路**在这里分岔**（分岔口只有一个）：
    /// - 官方（没配自建中继）：走 REST `POST /v2/{users|groups}/{openid}/messages`，
    ///   带 `msg_id` + `msg_seq` 的被动回复（`FR-AGT-LINK-CHAN-003` 第四十三批）；
    /// - 自建中继：第四十一批那条路原样保留 —— 结果正文现拼成本侧帧再往 WebSocket 上写。
    ///
    /// 推不出去就返回 `false`（条目留在队列里：官方那次由 `flushAgentIMOutboundQueue` 补发，
    /// 中继那次由传输层 `replayPending` 补发）。
    private func deliverAgentIMResult(_ entry: AgentIMResultQueue.Entry) async -> Bool {
        if !agentIMUsesRelay {
            guard let sender = makeAgentIMOutboundSender() else {
                agentIMOutboundLine = AgentIMSendText.line(for: .notReady(code: "environmentMissing"),
                                                            language: agentIMLanguage)
                return false
            }
            let outcome = await sender.send(entry: entry)
            agentIMOutboundLine = AgentIMSendText.line(for: outcome, language: agentIMLanguage)
            // 投递失败的原因必须留痕（不然只会看到「没回应」）。
            StartupLog.write("IM 投递 outcome=\(String(describing: outcome)) openid=\(entry.target?.openID.prefix(8) ?? "-")…")
            return outcome.isDelivered
        }
        guard let transport = agentIMTransport else { return false }
        do {
            try await transport.send(AgentIMOutboundFrame.reply(chatID: entry.chatID, text: entry.text))
            return true
        } catch {
            return false
        }
    }

    /// 用户在高级项里填了自建中继地址（⇒ 回话走 WebSocket 帧，不走官方 REST）。
    private var agentIMUsesRelay: Bool {
        !agentIMSettings.relayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 一条能用的外发器（环境没选 / 没配齐就 `nil` —— 不许拿一个假环境去发）。
    private func makeAgentIMOutboundSender() -> AgentIMOutboundSender? {
        guard let environment = agentIMSettings.environment else { return nil }
        let client = agentIMOutboundClient
        return AgentIMOutboundSender(client: client,
                                     environment: environment,
                                     sequences: agentIMReplySeqLedger,
                                     token: { [weak self] in
                                         guard let self else {
                                             throw AgentIMQQProvisionProblem.environmentMissing
                                         }
                                         return try await self.fetchAgentIMQQToken()
                                     })
    }

    /// 连上之后把**官方那条路**的未投递结论补发一遍。
    ///
    /// 为什么必须要它：官方结论走 REST，而传输层补发只往 WebSocket 上写帧 ⇒
    /// 断线期间攒下的官方结论没有人补发（队列里躺着，永远不会出去）。
    private func flushAgentIMOutboundQueue() async {
        guard !agentIMUsesRelay, let sender = makeAgentIMOutboundSender() else { return }
        let drain = AgentIMOutboundDrain(queue: agentIMResultQueue,
                                        send: { entry in await sender.send(entry: entry) })
        let report = await drain.run()
        guard report.delivered > 0 || report.failed > 0 else { return }
        let last = report.lastFailure ?? .delivered(messageID: nil)
        agentIMOutboundLine = AgentIMSendText.line(for: last, language: agentIMLanguage)
    }

    /// 结局落成面板读数（`ignored` / `duplicate` 不记：它们不是「收了却没做」）。
    private func recordAgentIMInbound(_ outcome: AgentIMInboundOutcome, message: AgentIMInboundMessage) {
        switch outcome {
        case .ignored, .duplicate:
            return
        case .dropped(let reason):
            agentIMLastInboundDrop = reason
        case .replied(let delivered):
            agentIMLastInboundDrop = nil
            agentIMInboundHandled += 1
            if delivered { agentIMInboundReplied += 1 }
            appendAgentIMInboundText(message.text)
        case .failed(let reason, let delivered):
            agentIMLastInboundDrop = nil
            agentIMInboundHandled += 1
            if delivered { agentIMInboundReplied += 1 }
            appendAgentIMInboundText(message.text)
            print("[Doyah] IM 入站任务失败：\(reason)")
        }
    }

    private func appendAgentIMInboundText(_ text: String) {
        agentIMInboundTexts.append(text)
        if agentIMInboundTexts.count > 20 { agentIMInboundTexts.removeFirst(agentIMInboundTexts.count - 20) }
    }

    /// 一次性迁移：把旧版**文件存储**（`FileAgentKeyStore` / `FileSecretStore`，XOR 混淆）
    /// 里的凭据搬进系统钥匙串，搬完删文件里的明文槽位。
    ///
    /// 由头（2026-10-25 实机）：口令与模型 Key 改注入钥匙串后，**旧用户的数据还在文件里** ⇒
    /// 钥匙串读不到 ⇒ 界面判「没有 Key」、连接口令丢失。迁移只在「钥匙串为空 + 文件有值」时发生，
    /// 且只跑一次（`ui.secretsMigratedToKeychain`），重复启动不会反复搬。
    private func migrateLegacySecretsIfNeeded() {
        let flag = "ui.secretsMigratedToKeychain"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        var migrated = 0

        // ① 模型 API Key
        let legacyAgentKey = try? FileAgentKeyStore().apiKey()
        let keychainAgentKey = try? agentKeyStore.apiKey()
        if (keychainAgentKey ?? nil) == nil, let legacy = legacyAgentKey ?? nil, !legacy.isEmpty {
            if (try? agentKeyStore.setAPIKey(legacy)) != nil { migrated += 1 }
        }

        // ② 连接口令（逐连接搬：只搬钥匙串里还没有的那几条）
        let legacyStore = FileSecretStore()
        for configuration in connections {
            let existing = try? secretStore.password(for: configuration.id)
            guard (existing ?? nil) == nil,
                  let password = (try? legacyStore.password(for: configuration.id)) ?? nil,
                  !password.isEmpty else { continue }
            if (try? secretStore.setPassword(password, for: configuration.id)) != nil {
                _ = try? legacyStore.deletePassword(for: configuration.id)
                migrated += 1
            }
        }

        UserDefaults.standard.set(true, forKey: flag)
        if migrated > 0 {
            // 用 os.Logger 会牵进 Core 的日志设施；这里只留一条控制台行，够查
            print("[Doyah] 凭据迁移：\(migrated) 条从文件存储搬进系统钥匙串")
        }
    }

    /// 凭据条目按**当前这套签名**核对一次（★00：主人 2026-10-29「每次启动都要输入密码」）。
    ///
    /// 三档口径（判定住 `Core/CredentialItemReconciliation.swift`，这里只接线）：
    ///   · 已经按这套签名重写过的条目 ⇒ **不读内容、不重写**（读内容正是会弹授权的那一下）；
    ///   · 旧签名留下的条目（含回退 ad-hoc 时建的）⇒ 读 → 删 → 按当前签名写回：
    ///     这一步之后 ACL 里才有**当前这个应用**，否则永远「谁建的谁读」；
    ///   · 读不出来 ⇒ **不删**（删了就丢凭据），失败码进读数。
    ///
    /// 账本落在应用支持目录（`keychain-rewrite-ledger.json`）：没有它就会每次启动都重读旧条目 ⇒
    /// 每次弹 —— 治这个症状靠的是**记账**，不是更努力地读写。
    private func reconcileKeychainCredentials() {
        let report = KeychainCredentialReconciler.run(
            connectionIDs: connections.map(\.id),
            connectionLabel: { id in
                connections.first { $0.id == id }?.name ?? "连接 \(id.uuidString.prefix(8))"
            }
        )
        keychainReconcileSummary = report.summaryLine()
        print("[Doyah] \(report.summaryLine())")
        for entry in report.problems {
            print("[Doyah] 凭据核对未治好：\(entry.label) · \(entry.outcome)")
        }
    }

    /// 保存智能体配置；`apiKey` 传 `nil` 表示不改动已保存的 Key，传空串表示清除。
    @discardableResult
    func saveAgentConfiguration(_ incoming: AgentConfiguration, apiKey: String?) async -> Bool {
        // **多档（`FR-AI-32`）不许被"保存一次"吃掉**：面板这一版只编辑**当前档**（多档编辑面在下一笔），
        // 它交上来的是一个"单档形状"的草稿 ⇒ 在这里把**别档原样留住**，只更新当前档那一格，
        // 再取草稿的全局三格（总开关 / 配额 / 护栏）。留住别档是宿主（真值持有者）的责任，不是面板的。
        var configuration = incoming
        if let edited = incoming.activeProfile, let existing = agentConfiguration.activeProfile {
            var merged = existing
            merged.name = edited.name
            merged.presetID = edited.presetID
            merged.endpoint = edited.endpoint
            merged.model = edited.model
            merged.timeoutSeconds = edited.timeoutSeconds
            // **真值源跟着档走**（`FR-AI-25` 信息面）：窗口 / 价目是这一档的属性，
            // 面板交上来的草稿里带着它；不并这一格 = 用户填了价目、保存后**静默消失**。
            merged.pricing = edited.pricing
            configuration = agentConfiguration
            configuration.updateProfile(merged)
            configuration.isEnabled = incoming.isEnabled
            configuration.quota = incoming.quota
            configuration.guardPolicy = incoming.guardPolicy
            // **授权粒度**（`FR-AI-34`）：面板上有这个选择器，从前这里没并 ⇒
            // 选「每个动作都问」保存后等于没选（开关点了不生效，且没有任何提示）。
            configuration.scopeMode = incoming.scopeMode
        }

        do {
            try await agentConfigurationStore.save(configuration)
            agentConfiguration = configuration
        } catch {
            errorMessage = L(.agentSaveFailed, ErrorPresenter.message(for: error))
            return false
        }

        if let apiKey {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                if trimmed.isEmpty {
                    try agentKeyStore.deleteAPIKey()
                    agentAPIKey = nil
                    hasAgentAPIKey = false
                } else {
                    try agentKeyStore.setAPIKey(trimmed)
                    agentAPIKey = trimmed
                    hasAgentAPIKey = true
                }
            } catch {
                // 配置已存下、Key 没存下：如实告知，不要把失败吞掉。
                errorMessage = L(.agentSaveFailed, ErrorPresenter.message(for: error))
                return false
            }
        }

        statusMessage = L(.agentSaved)
        return true
    }

    // MARK: - 审批与审计（FR-AI-09 / NFR-AI-03）

    /// 当前生效的护栏 / 审批策略：只读模式与白名单来自配置（FR-AI-09）。
    var agentGuardPolicy: AgentGuardPolicy { agentConfiguration.effectiveGuardPolicy }

    // MARK: - 对话页签的接线（`FR-AI-25`）

    /// 端点状态：**没配就是没配**（连不连得上要等真发一次才知道 —— 失败那一档由失败回执如实转成 `unreachable`）。
    var agentChatEndpointState: AgentChatEndpointState {
        let endpoint = agentConfiguration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = agentConfiguration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty, URL(string: endpoint) != nil, !model.isEmpty else { return .notConfigured }
        return .ready(model: model, endpoint: endpoint)
    }

    /// 信息面三格的**真值源**（`FR-AI-25`）：当前档的模型名 + 窗口 / 价目。
    ///
    /// 只读当前档 —— 切档（`FR-AI-32`）后三格跟着换，不需要第二份真相。
    var agentMeterInput: AgentMeterInput {
        let profile = agentConfiguration.activeProfile
        return AgentMeterInput(model: profile?.model ?? "", pricing: profile?.pricing)
    }

    /// 工作区**现场读数**的供给口（`FR-AI-22` ②）：当前文件 / 选中范围 / 终端尾部。
    ///
    /// 为什么是闭包而不是属性：这三样分别长在三个**视图级模型**上（工作区页签 / 编辑器视图 /
    /// 终端面板），`AppState` 刻意不持有它们（那会把整个窗口拉进它的观测面，见 `editorBuffer`
    /// 那条纪律）。界面在启动时把这个口接上；没接（单测 / 老路径）⇒ 这一段**如实不带**。
    var agentWorkspaceFactsProvider: (@MainActor () -> AgentWorkspaceFacts)?

    /// **MCP 桥**（`FR-AI-21`）：用户自配 server 的连接与工具登记。
    ///
    /// 一次会话内复用（不每条消息重起进程）；改过配置调 `resetAgentMCP()` 重来。
    /// 关掉的 server 在 `discover` 里连计划都不生成 —— 这里没有「悄悄起一下」的路径。
    private var agentMCPBridge: MCPClientBridge?
    private var agentMCPRegistry: AgentToolRegistry?
    /// 每条 server 的连接状态（含**连不上 / 坏配置 / 关掉**三种）—— 界面读它，不静默消失。
    @Published private(set) var agentMCPReports: [MCPClientServerReport] = []
    /// 配置文件本身读不出来时的原因（与「一条都没配」分开记）。
    @Published private(set) var agentMCPLoadError: String?

    /// 用户自配 MCP server 的**当前配置**（界面读它、改它、存它）。
    ///
    /// 与 `agentMCPReports` 分开：前者是「文件里写着什么」，后者是「这一轮连成了什么样」。
    /// 面板要同时显示两件事 —— 光有读数改不了，光有配置看不出连不上。
    @Published private(set) var agentMCPConfiguration = MCPClientConfiguration()
    /// 这份配置是否已经从盘上读过（读过就不再重读，免得面板每开一次都盖掉刚存的草稿）。
    @Published private(set) var agentMCPConfigurationLoaded = false

    /// 读配置（**幂等**：读过就返回内存里那份）。
    ///
    /// 读不出来 ⇒ 当没配，但把原因留在 `agentMCPLoadError` 里 —— 面板据此说「配置读不了：…」，
    /// 而不是让用户对着一个「未配置」发呆。
    @discardableResult
    func loadAgentMCPConfiguration() -> MCPClientConfiguration {
        if agentMCPConfigurationLoaded { return agentMCPConfiguration }
        switch MCPClientConfiguration.load() {
        case .success(let loaded):
            agentMCPConfiguration = loaded ?? MCPClientConfiguration()
            agentMCPLoadError = nil
        case .failure(let error):
            agentMCPConfiguration = MCPClientConfiguration()
            agentMCPLoadError = error.detail
        }
        agentMCPConfigurationLoaded = true
        return agentMCPConfiguration
    }

    /// 存配置（界面那一半的落盘口）：写文件 → 更新内存 → **关掉旧进程**（下次对话按新配置发现）。
    ///
    /// 返回 `nil` = 存成功。写不进去（目录建不出来 / 编码失败）**如实返回原因**，
    /// 不许「看起来存了、其实没写」—— 那会让用户在面板上改半天而配置一动不动。
    @discardableResult
    func saveAgentMCPConfiguration(_ configuration: MCPClientConfiguration) -> MCPClientConfigurationError? {
        let url = MCPClientConfiguration.defaultFileURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                   withIntermediateDirectories: true)
            guard let data = configuration.encoded() else { return .malformed("encode") }
            try data.write(to: url, options: .atomic)
        } catch {
            return .malformed(url.lastPathComponent)
        }
        agentMCPConfiguration = configuration
        agentMCPConfigurationLoaded = true
        agentMCPLoadError = nil
        // 配置变了 ⇒ 旧进程按旧配置起的，必须关掉（否则「改了命令还在用老进程」这种假象没人查得出）。
        resetAgentMCP()
        return nil
    }

    /// 现在就连一次（面板上的「保存并重连」/「重新连接」）：先丢掉旧桥，再按当前配置发现。
    ///
    /// 返回发现结果（每条 server 的状态），面板直接拿它这一轮的读数。
    @discardableResult
    func connectAgentMCPNow() async -> [MCPClientServerReport] {
        resetAgentMCP()
        _ = await agentMCPReady()
        return agentMCPReports
    }

    /// 连上用户自配的 MCP server，并把远端工具并进**同一张**注册表（`FR-AI-21` ①）。
    ///
    /// 起进程是同步阻塞的 ⇒ 挪进 `detached`：一条慢 server 不许把主 actor（整个窗口）拖住。
    private func agentMCPReady() async -> (registry: AgentToolRegistry, bridge: MCPClientBridge?) {
        if let agentMCPRegistry { return (agentMCPRegistry, agentMCPBridge) }
        let configuration = loadAgentMCPConfiguration()
        let bridge = MCPClientBridge(configuration: configuration,
                                     inheritedEnvironment: ProcessInfo.processInfo.environment) { _, plan in
            MCPStdioTransport(plan: plan)
        }
        let reports = await Task.detached(priority: .userInitiated) { bridge.discover() }.value
        let merged = AgentToolRegistry.standard.merging(bridge.discoveredDefinitions())
        agentMCPBridge = bridge
        agentMCPRegistry = merged.registry
        agentMCPReports = reports
        return (merged.registry, bridge)
    }

    /// 改过 MCP 配置（或想重连）⇒ 关掉旧进程、下次对话重新发现。
    func resetAgentMCP() {
        agentMCPBridge?.shutdown()
        agentMCPBridge = nil
        agentMCPRegistry = nil
        agentMCPReports = []
        agentMCPLoadError = nil
    }

    /// 造一条对话循环：流式网关（`FR-AI-16`）+ 循环（`FR-AI-18`）+ 六个工具（`FR-AI-19/20`）+ 审计（`FR-AI-24`）。
    ///
    /// 造不出来（端点没配 / 地址不合法）⇒ 返回 `nil` —— 界面那边**如实拦**，不假装在跑。
    func makeAgentChatLoop(prompt: String,
                           history: [LLMTurn] = [],
                           sessionID: String,
                           workspacePath: String,
                           checkpointScopeID: String? = nil,
                           observer: any AgentLoopObserver) async -> (loop: AgentLoop, context: AgentLoopContext)? {
        guard case .ready(let model, let endpoint) = agentChatEndpointState,
              let url = URL(string: endpoint) else { return nil }
        // `FR-AI-22` 上下文供给（第一批：**当前连接的表结构摘要 + 活跃页签**）：
        // · 摘要**与 NL→SQL 共用同一处**（`agentSchemaSummary`）—— 不另起一份；表数 / 列数预算（NFR-AI-01）也只有一处；
        // · 取不到摘要（没连库 / 元数据拿不到）⇒ **不带这一段**，而不是编一个空壳出来；
        // · 文件 / 选中 / 终端尾部三类挂在编辑器侧那条路上（下一片），此处不假装带上。
        var references: [AgentContextReference] = []
        // **带超时**：这一段是「锦上添花」的上下文，取不到就该照常跑。
        // 2026-10-31 05:53 实测：库连不上时 `ensureService` 会一直等，整轮对话**静默挂死**
        // （IM 那条链上只留下「跑一轮开始」，既没模型请求也没有回话）。
        if let summary = await agentSchemaSummaryWithTimeout() {
            references.append(.schemaSummary(
                database: selectedConnection?.database ?? "",
                tables: summary.tables.map {
                    AgentContextReference.Table(schema: $0.schema ?? "", name: $0.name,
                                                columns: $0.columns.map(\.name))
                }))
        }
        if let tab = selectedTab {
            references.append(.activeTab(title: tab.title, kind: "query"))
        }
        // `FR-AI-29` 对话记忆（跨会话长期记忆）的**接线段**：记忆进上下文只有这一个口 ——
        // `AgentMemoryContext.references` 自己按 `FR-AI-15` 的口径挑「还该记的」（该忘的不挂），
        // 本处**不重挑、不拼提示词、不新增第七个 case**（产出的是既有 `AgentContextReference`）。
        // 读不回来（这一工作区还没有记忆 / 整份文件读不了）⇒ **这一段不带**，而不是编一个空壳出来
        //（与本函数上面那条「取不到摘要就不带」同一条口径）。
        // 隔离的第二层（连接）在这里落到读法上：选了连接就只看那个连接的记忆。
        let memoryRead = AgentMemoryStore(directory: AgentMemoryStore.defaultDirectory)
            .entries(workspace: workspacePath, connection: selectedConnection?.name)
        if !memoryRead.entries.isEmpty {
            // `FR-AGT-KNOW-MEM-007`：**按本次任务挑**，不再「最近八条一律带上」。
            // 零命中 = 一条都不挂（宁可少给）；命中理由由检索层给，界面不复算。
            references.append(contentsOf: AgentMemoryRetrieval.references(from: memoryRead.entries,
                                                                         query: prompt,
                                                                         now: Date()))
        }
        // `FR-AI-22` ①：**用户点名的东西真的读进来** —— `@a.swift` / `@Sources/` 以前没人解析。
        // 越界（`../`、绝对路径、`~`）与不存在由解析器拒掉并给一句说法，不静默丢。
        let workspaceRoot = URL(fileURLWithPath: workspacePath)
        let mentionResult = AgentMentionParser.parse(prompt, workspaceRoot: workspaceRoot)
        let resolvedMentions = AgentMentionResolver.references(
            for: mentionResult,
            root: workspaceRoot,
            reader: AgentMentionResolver.fileReader(root: workspaceRoot,
                                                    maxCharacters: AgentContextLimits().maxFileCharacters),
            lister: AgentMentionResolver.directoryLister(root: workspaceRoot,
                                                         maxEntries: AgentWorkspaceContext.maxDirectoryEntries))
        references.append(contentsOf: resolvedMentions.references)
        // 没带上的提及（二进制 / 读不到 / 越界 / 不存在）**说清**：附在用户原话之后、带标记；
        // 用户写的字一个不改（解析器与本段都不重写 prompt 本体）。
        let promptWithNotes = resolvedMentions.notes.isEmpty
            ? prompt
            : prompt + "\n\n[未带上的提及]\n" + resolvedMentions.notes.joined(separator: "\n")

        // `FR-AI-22` ②：**不写 `@` 也让它看见我正在改什么** —— 当前文件 / 选中范围 / 终端尾部。
        // 取数在界面（三样分属三个视图级模型，`AppState` 不持有它们）；裁留在
        // `AgentWorkspaceFacts` → `AgentWorkspaceContext`（空的不带、选中在前、终端留尾）。
        // 没接供给口（单测 / 工作区没打开）⇒ 如实不带，不编一段空壳。
        if let facts = agentWorkspaceFactsProvider?() {
            references.append(contentsOf: AgentWorkspaceContext.references(from: facts))
        }

        // 灵魂（`FR-AI-34`）：L0 读包内 `soul-L0.md`、L1 读 `<工作区>/.doyah/soul-role.md`；
        // 缺项由 `AgentSoul.compose` **如实写进提示词**（不静默当没有），缺 L0 属缺陷。
        let soul = AgentSoul.load(workspacePath: workspacePath)
        let systemPrompt = AgentSystemPrompt.build(model: model, endpoint: endpoint,
                                                   workspacePath: workspacePath,
                                                   references: references,
                                                   soul: soul)
        let request = LLMRequest(endpoint: url,
                                 model: model,
                                 apiKey: agentAPIKey,
                                 timeoutSeconds: agentConfiguration.timeoutSeconds,
                                 systemPrompt: systemPrompt,
                                 userPrompt: promptWithNotes,
                                 // `NFR-AI-04` 单次输出上限：配额里配了就下发给模型（同时作 `max_tokens`），
                                 // 没配就**不出现**这个字段（与旧请求体逐字节一致）。
                                 maxOutputTokens: agentConfiguration.quota.maxOutputTokensPerRequest)
        let tools = AgentWorkspaceTools(root: URL(fileURLWithPath: workspacePath),
                                               harmStopLog: .default)
        // 六个 MVP 工具**全接上**（`FR-AI-20` ①）：
        // · 工作区五个（读 / 列目录 / 搜 / 写 / 跑命令）⇒ `AgentWorkspaceTools` + 真起进程的 `AgentLocalCommandRunner`；
        // · 查库（`query_db`）⇒ `AgentDatabaseTool` + 挂在**当前连接**上的 `AgentConnectionQueryExecutor`
        //   （**A 口径**：只回结构 / 行数 / 语句类型，**行数据不出本机** —— 由 `AgentQueryExecution` 的类型保证）。
        // 写文件与跑命令仍**逐次审批**（`FR-AI-09` / `FR-AI-23`）：判定只在 `AgentGuardPolicy` + `prepare*` 那一处，
        // 不在这里重判。缺连接 / 起不来进程都**如实拒**，不假装能做。
        let databaseTool = AgentDatabaseTool(
            policy: agentGuardPolicy,
            databaseType: selectedConnection?.dbType ?? .postgresql,
            executor: AgentConnectionQueryExecutor { [weak self] sql in
                guard let self else { throw AppError.notConnected }
                return try await self.runAgentDatabaseQuery(sql)
            }
        )
        // `FR-AI-21`：先把用户自配的 MCP server 接上（发现的工具并进同一张注册表）。
        // 没配 / 连不上都不影响既有六个工具 —— 状态另记一份（`agentMCPReports`）如实报。
        let mcpReady = await agentMCPReady()
        // **运行策略的生效面**（`FR-AGT-OPS-OBS-002`「改完立即生效」）：
        // 循环每次开跑都重建，所以在这里读一遍配置就等于「面板改完，下一轮就是新的」，不必重启。
        // ① 工具白名单 ⇒ 名单外的工具从可见面移出（不是「还能调、只是不显示」）；
        //    写了不存在的工具名如实记下来（面板上那句「只放开这几个」才不会是空话）。
        // ② 命令超时 ⇒ 真起进程那一层的上限（超时被终止并如实写进结果）。
        loadAgentRuntimeConfigIfNeeded()
        let runtimePolicy = agentRuntimeConfig.snapshot
        let whitelisted = mcpReady.registry.applyingWhitelist(runtimePolicy.toolWhitelist)
        agentToolWhitelistUnknown = whitelisted.unknown
        let commandRunner = AgentLocalCommandRunner(
            limits: AgentCommandLimits(timeoutSeconds: TimeInterval(runtimePolicy.commandTimeoutSeconds)),
            // **循环这条路也要进同一条 Agent shell**（2026-10-31）：只接审批那条路的话，
            // 模型自己发起的 `run_command` 仍走独立进程 —— 那就等于「看得见」只对一半命令成立。
            shell: agentShell(for: workspacePath))
        let dispatcher = AgentStandardDispatcher(registry: whitelisted.registry,
                                                workspace: tools,
                                                database: databaseTool,
                                                commandRunner: commandRunner,
                                                // `FR-AI-21`：远端工具走同一条分发（名字原样、结果原样回灌）。
                                                mcp: mcpReady.bridge,
                                                // **联网**（`FR-AGT-TOOL-INGEST-001/004`）：后端与 key 从设置里现读，
                                                // 面板改完下一轮就是新的（与其余运行策略同一口径）。
                                                web: AgentWebTools(config: agentWebSearchConfig,
                                                                   transport: URLSessionTransport()),
                                                guardPolicy: agentGuardPolicy)
        // 插件目录**先建出来**：用户要往里放东西，得先看得见这个位置（不存在就建，失败也不拦本轮）。
        // 扫描归口到 `rescanAgentExtensions()`：面板与循环读的是同一份台账（各读各的会造出
        // 「面板说装了、循环里没生效」这类最难查的假绿）。
        rescanAgentExtensions()
        let extensionLoad = AgentExtensionCatalogLoad(desk: agentExtensionDesk,
                                                     problems: agentExtensionProblems)
        let loop = AgentLoop(client: OpenAICompatibleStreamingClient(),
                             dispatcher: dispatcher,
                             registry: whitelisted.registry,
                             // `FR-AI-17` 会话持久化：每跳落一份 `.jsonl`（与其余本机数据同一处，不另开文件体系）。
                             sessionStore: AgentSessionStore(directory: AgentSessionStore.defaultDirectory),
                             audit: AgentAuditLog.shared,
                             observer: observer,
                             // `FR-AGT-UX-CONV-007` 中途干预：给循环一个**干预信箱** ——
                             // 斜杠 `/steer` 往这里塞 `redirect`，循环在每跳边界取（当前步做完生效，
                             // 不清空已产生的中间结果）。此前只有 Core 有信箱、宿主没接 ⇒ `/steer` 无处可插。
                             interventionInbox: AgentInterventionInbox(),
                             // `NFR-AI-08` ⑤ 检查点：**这一条此前只有存储半、宿主没接** —— 现在接上。
                             // 落点键由 `AgentTurnPlanner` 按「哪一轮提问」给（见 `context.checkpointScopeID`），
                             // 所以同一个会话里换一个提问就不会接上一个问题的检查点。
                             checkpointStore: AgentCheckpointStore(directory: AgentCheckpointStore.defaultDirectory),
                             checkpointEvery: 2,
                             // `NFR-AI-08` ③ 压缩：超预算才动手，界面上那一行读数就是它报出来的。
                             // 阈值是**参数**（契约只钉「有损但可数可报」）—— 24k 字符 ≈ 6k token，远小于常见窗口，
                             // 留出工具返回与模型输出的余量。
                             compressionBudget: AgentContextCompressionBudget(),
                             // `FR-AI-31` ② 完成判据：模型说「完成」时按**当次工具证据 + 盘上现状**复核，
                             // 拿不出就如实说「未验证」。复核要读盘 ⇒ 给它工作区根（相对路径都相对它）。
                             completionVerifier: AgentCompletionVerifier(workspaceRoot: workspaceRoot),
                             // `FR-AGT-LINK-EXT-003` ⑤ 调用点：插件目录里声明的策略钩子
                             // 在**每次工具调用之前**求值，只能往严重一侧走（转待批 / 直接拒）。
                             // 目录里没有插件 ⇒ 没有钩子 ⇒ 与旧行为逐字一致；清单写坏的那几份
                             // 不参与判定，但会在面板上逐条点名（`agentExtensionProblems`）。
                             policyHooks: AgentExtensionPolicySource(desk: extensionLoad.desk),
                             // `FR-AGT-OPS-OBS-002` 的「审批策略可配置」：基线从运行策略面板那一格来
                             // （`allow` / `ask` / `deny`），**每轮开跑重新读一次快照** ⇒ 改完下一轮就生效。
                             // 钩子只能在这条基线之上收紧；基线是 `allow` 且没装插件时与旧行为逐字一致。
                             policyBaseline: agentRuntimeConfig.snapshot.approvalPolicy,
                             // `NFR-AI-04` 配额：**对话这条路上此前根本没接**（`AgentQuota` 只接在
                             // 自然语言生成 SQL 那条路上）⇒ 长跑时会把配额悄悄烧掉。现在每跳发送前判定，
                             // 账本由 `AppState.agentQuotaLedger` 跨轮累计（跑完回写，见 `finish`）。
                             quota: agentConfiguration.quota,
                             quotaLedger: agentQuotaLedger,
                             // `FR-AI-31` ③ 长跑监控：空转 / 反复重试 / 预算将尽各出一条可读告警；
                             // 「卡住」那一档由界面看门狗按秒判（循环卡在 await 里喊不出来），
                             // 两边共用 `AgentRunMonitor.stallAlert` 这一条判定。
                             monitor: AgentRunMonitor(),
                             // `FR-AGT-TOOL-SYS-002` 的**接线面**：给了策略，循环才认领
                             // `dispatch_subtasks`（并发上限只从这份快照的
                             // `maxConcurrentSubtasks` 来；每轮开跑重读 ⇒ 面板改完下一轮生效）。
                             subagentPolicy: AgentSubagentPolicy(snapshot: runtimePolicy))
        var context = AgentLoopContext(systemPrompt: systemPrompt, userPrompt: promptWithNotes,
                                       baseRequest: request, sessionID: sessionID, workspace: workspacePath,
                                       checkpointScopeID: checkpointScopeID)
        // 多轮：把这一段会话里已经说过的话带上（`FR-AI-17` 续聊）。空数组 = 单轮，行为不变。
        context.priorTurns = history
        // 审批决议：`run_command` / `write_file` 这类要人点头的工具，循环拿着单子来这里等
        // 「行 / 不行」。没有这条，人点了批准也回不到循环里 —— 卡片一遍遍被重新要，命令永不执行。
        context.approvalDecision = { [weak self] request in
            guard let self else { return false }
            return await self.awaitAgentApproval(request)
        }
        return (loop, context)
    }

    // MARK: - 审批决议（`FR-AI-23`）

    /// 正在等「人点头」的循环（按指纹排队）。同一张单可能被两条路同时问（循环 + 界面），
    /// 所以是**数组**：每个等待者都要被唤醒，不能只叫醒一个、剩下的干等到超时。
    private var agentApprovalWaiters: [String: [CheckedContinuation<Bool, Never>]] = [:]

    /// **已经批了、但循环还没开始等**的指纹。
    ///
    /// 为什么需要：卡片是「先推到界面、再开始等」的（不先推，人根本看不见要批什么）。这张卡的
    /// 自动批准 / 人手快点点下去，可能就发生在循环挂上等待之前的几毫秒里 —— 那一刻没有等待者，
    /// 批准会当场丢掉，循环随后挂上去等 600 秒，最后按拒绝处理（2026-10-31 实测就是这个时序）。
    /// 所以「先到的批准」先记在这儿，循环来等的时候**立刻兑现**。
    private var agentPendingGrants: Set<String> = []

    /// **本会话内已批准过的指纹**（策略类出单）。
    ///
    /// 为什么：同一条命令重跑是常态（模型改正后重试、人反复验证），每次重问等于让人重复点同一个「批准」——
    /// 2026-10-31 现场一条 `python3 hello.py` 让人点了上百次。**越界单不进这里**：越界授权仍是
    /// 「一次一单、批准前不动盘」（§3.26），同一条路径改一次就要再问一次。
    private var agentSessionGrants: Set<String> = []

    /// 这一张单能不能「批一次、本会话免重问」。
    private func isSessionGrantable(_ request: AgentApprovalRequest) -> Bool {
        !request.payload.hasPrefix("越界")
    }

    /// 循环来这里等一个决定。**超时就按「不行」**（`AgentApprovalDecision.timeout`）——
    /// 挂死人比误拒更糟：挂住的那一轮会把步数和令牌都耗在原地。
    func awaitAgentApproval(_ request: AgentApprovalRequest) async -> Bool {
        // 同类命令本会话已经批过 ⇒ 不再问人（越界单除外）。
        if isSessionGrantable(request), agentSessionGrants.contains(request.fingerprint) {
            StartupLog.write("同类命令已批过：\(request.toolName) 指纹=\(request.fingerprint.prefix(8)) ⇒ 直接放行")
            return true
        }
        // 批准先到（卡片先推给界面、人先点了）⇒ 立刻兑现，不进等待队列。
        if agentPendingGrants.remove(request.fingerprint) != nil {
            StartupLog.write("审批已先行：\(request.toolName) 指纹=\(request.fingerprint.prefix(8)) ⇒ 批准")
            if isSessionGrantable(request) { agentSessionGrants.insert(request.fingerprint) }
            return true
        }
        StartupLog.write("等审批：\(request.toolName) 指纹=\(request.fingerprint.prefix(8))")
        let decided = await withTaskGroup(of: Bool?.self) { group -> Bool? in
            group.addTask { [weak self] in
                await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    Task { @MainActor in
                        self?.agentApprovalWaiters[request.fingerprint, default: []].append(cont)
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(Self.agentApprovalTimeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let decided else {
            StartupLog.write("审批超时：\(request.toolName) 指纹=\(request.fingerprint.prefix(8)) ⇒ 按拒绝处理")
            resolveAgentApproval(fingerprint: request.fingerprint, granted: false)
            return false
        }
        StartupLog.write("审批决议：\(request.toolName) 指纹=\(request.fingerprint.prefix(8)) ⇒ \(decided ? "批准" : "拒绝")")
        if decided, isSessionGrantable(request) { agentSessionGrants.insert(request.fingerprint) }
        return decided
    }

    /// 等人的上限（秒）。到点按拒绝处理并留痕。
    static let agentApprovalTimeout: TimeInterval = 600

    /// 界面点了「批准 / 拒绝」⇒ 唤醒正在等的循环。没有等待者（例如重放旧卡片）就什么都不做。
    func resolveAgentApproval(fingerprint: String?, granted: Bool) {
        guard let fingerprint, !fingerprint.isEmpty else { return }
        if agentApprovalWaiters[fingerprint] == nil {
            StartupLog.write("决议无等待者：\(fingerprint.prefix(8))（走旧兑现路径）")
        }
        for cont in agentApprovalWaiters.removeValue(forKey: fingerprint) ?? [] {
            cont.resume(returning: granted)
        }
    }

    /// `query_db` 的宿主实现（`FR-AI-20` ①）：对着**当前选中连接**跑一次 SQL，
    /// 只回**结构化结果**（列名 / 影响行数 / 语句类型）—— **行数据在这里就地丢弃**（A 口径）。
    ///
    /// 两条既有纪律照旧：
    /// · 计数走 `AffectedRowsTally`（**全工程唯一计数入口**，R-32）—— 不在这里自己 `switch` 累加；
    /// · 起服务走既有的 `ensureService`（与手工执行同一条路），不另开一个连接。
    private func runAgentDatabaseQuery(_ sql: String) async throws -> AgentQueryExecution {
        guard let configuration = selectedConnection else { throw AppError.notConnected }
        let service = try await ensureService(for: configuration,
                                              database: queryDatabase(for: configuration))
        var tally = AffectedRowsTally()
        var columns: [String] = []
        for try await event in service.execute(sql, options: .default, handle: ExecutionHandle()) {
            switch event {
            case .resultSet(let result):
                columns = result.columns.map(\.name)     // 只取**列名**：行数据到此为止
                tally.absorb(event)
            case .finished(let summary):
                tally.absorb(event)
                if let affected = summary.affectedRows, affected > 0 {
                    return AgentQueryExecution(columns: columns,
                                               affectedRows: affected,
                                               statementKind: Self.statementKind(of: sql))
                }
            default:
                tally.absorb(event)
            }
        }
        return AgentQueryExecution(columns: columns,
                                   affectedRows: tally.total,
                                   statementKind: Self.statementKind(of: sql))
    }

    /// 语句类型（`query_db` 回灌里那一格）：取首个关键字并大写。
    ///
    /// **只作说明用，不参与任何判定** —— 判定权在 `AgentGuardrail` / `AgentDatabaseTool.plan`，
    /// 这里另立一套就会分叉（R-32 同族：判定只许有一个出处）。
    private static func statementKind(of sql: String) -> String {
        let first = sql.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace || $0 == ";" || $0 == "(" })
            .first ?? ""
        return String(first).uppercased()
    }

    /// 已应用写入的账（`FR-AI-25` ⑤ 一步撤销用）。
    ///
    /// 放在 `AppState` 而不是视图模型里：撤销要在**工作区根**下解析路径、要动**页签缓冲区**，
    /// 这两样都只有这里同时握着。账本身（记录 / 取原文 / 一步撤销取哪一条）是 Core 的纯值
    /// `AgentEditJournal` —— 判据在那边咬，这里只做接线。
    private var agentEditJournal = AgentEditJournal()

    /// 整批撤回（`FR-STD-WS-EDIT-015`）在界面上的三样读数。
    ///
    /// 账还是上面那一本（**不为整批撤回另存一份前像**）：这里只多加两样 ——
    /// 上一批的**回执**（留痕）与「撤销这次撤回」要用的**反向批次**（可再撤回）。
    @Published private(set) var agentBatchRevert = AgentBatchRevertState()

    /// 「撤销这次撤回」的反向批次。只留一层：再撤一次就用掉了（撤 → 再撤不是无限栈）。
    private var agentBatchRedo: AgentWriteBatchStore?

    /// 这一批还能撤几个文件（按路径去重：同一文件被改两次只算一个）。
    var agentBatchRevertPending: Int { Set(agentEditJournal.undoable.map(\.path)).count }

    /// 许愿式编程（`FR-STD-WS-AI-002`）的**交付面**：这一批改了哪些文件 + 逐行差异 + 跑没跑通。
    ///
    /// 清单不另存一份：账还是 `agentEditJournal` 那一本，这里只是把它投影成
    /// `WishProposal`（`WishDelivery`，与暂存面同一份类型 —— 差异切分与审批单同源）。
    /// 「这一批」的口径与整批撤回**同一个边界**：自上次整批撤回以来还能撤的那些改动。
    /// `nil` = 这一批还没有任何改动（界面据此不占位置）。
    @Published private(set) var wishDelivery: WishProposal?

    /// 这一批的验证读数（最后一条**真跑起来**的命令的退出码 + 输出尾）。
    ///
    /// 为什么要记：验收要点 ③ 是「未通过验证的产出必须标明没跑通」。没有这份读数时
    /// 交付面必须写「未验证」，**不许默认成功** —— 所以 `nil` 与「rc=0」是两件事，
    /// 压成一个布尔就会对用户说错话。
    private var wishDeliveryValidation: WishValidation?

    /// 兑现一次已批准的写（`FR-AI-23` ④：批准之后才应用）。
    ///
    /// `FR-AI-25` ⑤ 的两半都在这一段里：
    /// · **落到编辑器缓冲区**：写盘之后，若这份文件正开在某个页签且**没有未保存改动**，
    ///   立刻把新正文推进缓冲区（不用等文件监听那一拍）；有未保存改动 ⇒ 缓冲区不动，
    ///   交给既有的「磁盘已改」提示（`reloadTab(force: false)` 的老口径，站人这一边）。
    /// · **留下可撤销的原文**：写之前把 `before` 读下来记账 —— 账记在**写成功之后**，
    ///   写失败就不该留下一条「能撤销」的空账。
    func applyAgentChatApproval(card: AgentToolCard, workspacePath: String) async -> AgentChatModel.ApplyResult {
        StartupLog.write("批准兑现：\(card.name) 指纹=\(card.approvalFingerprint?.prefix(8) ?? "nil")")
        // **执行口只有一处：循环**。这里只负责「把批准送到循环手上」：
        // · 循环正在等 ⇒ 当场唤醒，它就地重派；
        // · 循环还没开始等（几毫秒的时序差）⇒ 先记账，它来等的时候立刻兑现。
        // 以前这里也自己执行一遍，于是「循环重发 + 这侧执行」两条路各跑一次，还互相覆盖。
        if let fingerprint = card.approvalFingerprint, !fingerprint.isEmpty {
            if agentApprovalWaiters[fingerprint] != nil {
                resolveAgentApproval(fingerprint: fingerprint, granted: true)
            } else {
                agentPendingGrants.insert(fingerprint)
                StartupLog.write("批准先到：\(card.name) 指纹=\(fingerprint.prefix(8)) ⇒ 已记账，等循环来取")
            }
            return .success
        }
        guard let fingerprint = card.approvalFingerprint,
              let arguments = AgentToolArguments.parse(card.arguments),
              let definition = (agentMCPRegistry ?? AgentToolRegistry.standard).definition(named: card.name)
                ?? AgentToolRegistry.standard.definition(named: card.name) else { return .failure("applyFailed") }
        let root = URL(fileURLWithPath: workspacePath)
        let tools = AgentWorkspaceTools(root: root, harmStopLog: .default)
        let targetPath = arguments["path"] ?? ""
        // **先读原文**：撤销要用的就是它（应用前不存在 ⇒ nil）。
        let beforeText: String? = {
            guard case .file(let output) = tools.readFile(path: targetPath) else { return nil }
            return output.truncated ? nil : output.text
        }()
        // 截断过就不记「原文」：拿半截正文当撤销目标会把文件删短 —— 宁可不给撤销，也不给错的撤销。
        let canRestore = beforeText != nil || !fileExists(at: targetPath, root: root)

        // 按**能力**分派，不按工具名试错（试错的代价是「第一次尝试被拒」也留痕，
        // 而这一步正是要把「批了的那一条」原样送进执行器）。
        switch definition.capability {
        // ① 写文件那一档（`FR-AI-23` ④）。
        case .writeFile:
            let outcome = tools.writeFile(path: targetPath,
                                          content: arguments["content"] ?? "",
                                          tool: definition,
                                          guardPolicy: agentGuardPolicy,
                                          fingerprint: fingerprint,
                                          granted: [fingerprint],
                                          // `FR-AI-31` ①：出单那一刻的基线（卡片上记着）——
                                          // 审批之后文件被改过 ⇒ 不拿旧审批盖新内容，如实拒。
                                          baseDigest: card.baseDigest)
            switch outcome {
            case .wrote(let written):
                if canRestore {
                    agentEditJournal.record(cardID: card.id, path: written.path,
                                            before: beforeText, after: written.text)
                }
                // 账变了 ⇒ 界面上「这一批还能撤几个」跟着变（整批撤回的入口靠它显示/隐藏）。
                syncAgentBatchRevertState()
                syncEditorBuffer(path: written.path, root: root)
                return .success
            case .refused(let code, _):
                // **原因原样报出来**（写冲突 / 基线过期 / 写盘失败各是一件事）。
                return .failure(code.rawValue)
            default:
                return .failure("applyFailed")
            }
        // ①' 定点改代码那一档：与整篇重写**同一套**兑现与撤销（差异预览、逐次指纹、逐字节撤销）。
        // 这一段此前**没有**：`edit_file` 有审批单、Dispatcher 也认，但从界面批了之后没人兑现 ——
        // 「批了没落地」比「不给批」更坏，所以随本轮的「应用 + 撤销」一起补上。
        case .editFile:
            let outcome = tools.editFile(path: targetPath,
                                         oldString: arguments["old_string"] ?? "",
                                         newString: arguments["new_string"] ?? "",
                                         tool: definition,
                                         guardPolicy: agentGuardPolicy,
                                         fingerprint: fingerprint,
                                         granted: [fingerprint])
            switch outcome {
            case .wrote(let written):
                if canRestore {
                    agentEditJournal.record(cardID: card.id, path: written.path,
                                            before: beforeText, after: written.text)
                }
                // 账变了 ⇒ 界面上「这一批还能撤几个」跟着变（整批撤回的入口靠它显示/隐藏）。
                syncAgentBatchRevertState()
                syncEditorBuffer(path: written.path, root: root)
                return .success
            case .refused(let code, _):
                return .failure(code.rawValue)
            default:
                return .failure("applyFailed")
            }
        // ② MCP 工具那一档（`FR-AI-21` ④）：用户在页签里点了「批准」⇒ **这一次**才真的发给远端。
        // 名字与参数原样（卡片上存的就是模型给的那份），远端报错原样回来（不改写成「成功」）。
        case .mcpTool:
            guard let mcp = agentMCPBridge else { return .failure(AgentToolRefusal.mcpNotConfigured.rawValue) }
            switch mcp.call(tool: card.name, argumentsJSON: card.arguments) {
            case .result(let call):
                return call.isError ? .failure("mcpRemoteError") : .success
            case .failure(let code, _):
                return .failure(code)
            }
        default:
            break
        }
        // ② 跑命令那一档（`FR-AI-20`）：**同一张单、同一份指纹** —— 兑现在这里。
        // 判定**不在这里重做**：`runCommand` 内部会拿这张单的指纹再核一次，并再走一次白名单
        //（对不上 ⇒ `.refused`，不执行）。换句话说，这里只是"把已批准的那一条送进执行器"，
        // 真正的闸始终只有一处。
        StartupLog.write("兑换命令：cmd=\(arguments["command"] ?? "") 指纹=\(fingerprint.prefix(8)) readOnly=\(agentGuardPolicy.readOnly)")
        let commandOutcome = await tools.runCommand(arguments["command"] ?? "",
                                              tool: definition,
                                              guardPolicy: agentGuardPolicy,
                                              fingerprint: fingerprint,
                                              granted: [fingerprint],
                                              runner: AgentLocalCommandRunner(shell: agentShell(for: workspacePath)))
        StartupLog.write("兑换命令结局：\(String(describing: commandOutcome).prefix(80))")
        switch commandOutcome {
        case .command(let result):
            // 交付面（`FR-STD-WS-AI-002` ③）：这一批**最后一条真跑起来的命令**的读数。
            // 非零退出必须留下来 —— 交付面据此写「没跑通」，而不是默认「跑通了」。
            // 输出尾只取末 12 行（界面折叠看，不参与判定）。
            wishDeliveryValidation = WishValidation(command: arguments["command"] ?? "",
                                                    exitCode: Int(result.exitCode),
                                                    outputTail: AgentWorkspaceContext.tailLines(of: result.combined,
                                                                                                keeping: 12))
            syncAgentBatchRevertState()
            return .success
        case .refused(let code, _):
            return .failure(code.rawValue)
        default:
            return .failure("applyFailed")
        }
    }

    /// **一步撤销**（`FR-AI-25` ⑤）：把这张卡片已经落盘的改动退回去。
    ///
    /// 结局分三种，界面话不一样（不许压成一句「撤不了」）：
    /// · `.success` —— 文件已逐字节回到应用前（或应用前本来没有 ⇒ 已删掉）；
    /// · `.failure("drifted")` —— 应用之后文件又被改过（人 / 别的工具）⇒ **不回退**，让人先看正文；
    /// · `.failure("failed")` —— 写盘出错 / 路径越界 / 账上没有这一笔，可原样重试或如实报。
    func undoAgentChatApproval(card: AgentToolCard, workspacePath: String) async -> AgentChatModel.UndoResult {
        guard let edit = agentEditJournal.entry(for: card.id) else { return .failure("failed") }
        let reverter = AgentEditReverter(root: URL(fileURLWithPath: workspacePath))
        switch reverter.revert(edit) {
        case .restored, .removed:
            agentEditJournal.markUndone(card.id)
            syncEditorBuffer(path: edit.path, root: URL(fileURLWithPath: workspacePath))
            return .success
        case .refused(_, let detail):
            // `drifted` 是「不改」而不是「没改成」—— 单独一档，界面上说的是「先看正文」。
            return .failure(detail == "drifted" ? "drifted" : "failed")
        }
    }

    /// 文件在不在（撤销账用：应用前不存在 ⇒ 撤销 = 删）。
    private func fileExists(at path: String, root: URL) -> Bool {
        guard case .inside(let url) = AgentWorkspaceSandbox.resolve(path, in: root) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - 整批撤回（`FR-STD-WS-EDIT-015`）

    /// 整批撤回里唯一的「我们自己的」失败（写盘错误照原样抛上去，由调用方统一记成 `failed`）。
    private enum AgentBatchRevertError: Error {
        /// 账上的路径解析出了工作区（撤回**绝不**越界写盘）。
        case outsideWorkspace(String)
    }

    /// **一批一次撤回**（`FR-STD-WS-EDIT-015` ①）：把这一次任务里 Agent 写过的文件一次退回去。
    ///
    /// 三条纪律都不在这里判（判定在 Core，判据也在那边咬）：
    /// · **只撤 Agent 改的** —— 账上只有 Agent 真写成功的那些，人手改的文件根本不在账上；
    /// · **人改过的不覆盖**：`plan` 给 `conflict`、`apply` 一个字都不动，撤不了的进回执逐条点名（②）；
    /// · 撤完留**回执** + **反向批次** ⇒ 「撤销这次撤回」把文件送回 Agent 写完那一份（③）。
    ///
    /// 结局：至少撤成一条 ⇒ `.success`（哪几条没撤在回执里，由界面说出来）；一条都没撤成 ⇒ `.failure("drifted")`。
    func revertAgentBatch(workspacePath: String) async -> AgentChatModel.UndoResult {
        let root = URL(fileURLWithPath: workspacePath)
        let edits = agentEditJournal.undoable
        guard !edits.isEmpty else { return .failure("failed") }
        let batchID = UUID()
        do {
            let run = try runAgentBatch(AgentWriteBatchRevert.snapshots(from: edits), root: root)
            let cardIDs = edits.filter { run.moved.contains($0.path) }.map(\.cardID)
            for id in cardIDs { agentEditJournal.markUndone(id) }
            for path in run.moved { syncEditorBuffer(path: path, root: root) }
            let receipt = AgentBatchRevertReceipt.make(batchID: batchID, at: Date(),
                                                       result: run.result, cardIDs: cardIDs)
            // 反向批次：撤完之后还能退回去（空批次 = 一条都没动，别留一个空壳）。
            let redo = AgentWriteBatchStore(runID: "redo-" + batchID.uuidString)
            for snapshot in run.inverse { redo.record(snapshot) }
            agentBatchRedo = redo.isEmpty ? nil : redo
            agentBatchRevert = AgentBatchRevertState(pending: agentBatchRevertPending,
                                                     receipt: receipt,
                                                     redoPending: redo.all.count)
            return run.result.applied > 0 ? .success : .failure("drifted")
        } catch {
            syncAgentBatchRevertState(lastFailure: "failed")
            return .failure("failed")
        }
    }

    /// 「撤销这次撤回」：把这一批送回 Agent 写完那一份（验收 ③ 的可再撤回）。
    ///
    /// 只留一层反向批次：用掉就没有了 —— 再往回走要重新点「整批撤回」。
    /// 栈不留两深，因为「我现在停在哪一版」靠这行字说不清。
    func redoAgentBatchRevert(workspacePath: String) async -> AgentChatModel.UndoResult {
        let root = URL(fileURLWithPath: workspacePath)
        guard let redo = agentBatchRedo, !redo.isEmpty else { return .failure("failed") }
        do {
            let run = try runAgentBatch(redo.all, root: root)
            // 送回去之后这一笔重新算「可撤」（撤 → 再撤 → 再撤…… 每一层都由人点）。
            for id in agentBatchRevert.receipt?.cardIDs ?? [] { agentEditJournal.unmarkUndone(id) }
            for path in run.moved { syncEditorBuffer(path: path, root: root) }
            agentBatchRedo = nil
            agentBatchRevert = AgentBatchRevertState(pending: agentBatchRevertPending,
                                                     receipt: agentBatchRevert.receipt,
                                                     redoPending: 0)
            return run.result.applied > 0 ? .success : .failure("drifted")
        } catch {
            syncAgentBatchRevertState(lastFailure: "failed")
            return .failure("failed")
        }
    }

    /// 界面读数跟着账走（还能撤几个 / 上一批回执 / 可再撤回几步）。
    private func syncAgentBatchRevertState(lastFailure: String? = nil) {
        agentBatchRevert = AgentBatchRevertState(pending: agentBatchRevertPending,
                                                 receipt: agentBatchRevert.receipt,
                                                 redoPending: agentBatchRedo?.all.count ?? 0,
                                                 lastFailure: lastFailure)
        // 交付面（`FR-STD-WS-AI-002` ①）与撤账同一把边界：账变一次，清单跟着变一次。
        syncWishDelivery()
    }

    /// 交付面跟着「账 + 验证读数」走（`FR-STD-WS-AI-002` ①③）。
    ///
    /// · 账空、也没有验证读数 ⇒ `nil`：这一批什么都没发生，界面上不留空壳清单；
    /// · 账空但跑过命令 ⇒ 照样出清单，判定落 `.noChanges`（**没改就是没改**，不编工作量）；
    /// · 清单本身由 `WishDelivery` 从账反推 —— 这里不另存前像、也不自己数行数。
    private func syncWishDelivery() {
        let edits = agentEditJournal.undoable
        guard !edits.isEmpty || wishDeliveryValidation != nil else {
            wishDelivery = nil
            return
        }
        wishDelivery = WishDelivery.proposal(runID: "delivery-batch",
                                             root: WorkspaceStore.shared.rootPath ?? "",
                                             edits: edits,
                                             validation: wishDeliveryValidation)
    }

    /// 一批快照 → 计划 → 落盘。**反向批次在落盘之前算**（落盘后盘上已是撤后的样子，前像就没了）。
    ///
    /// 返回的三样都不是这里数的：`applied` / `conflicts` 是 `apply` 的读数，
    /// `moved` 是计划里真会动盘的那几步（冲突步不算动过）。
    private func runAgentBatch(_ snapshots: [AgentWriteSnapshot],
                               root: URL) throws
        -> (result: (applied: Int, conflicts: [AgentRevertStep]), inverse: [AgentWriteSnapshot], moved: [String]) {
        let reader = agentBatchReader(root: root)
        let steps = AgentWriteBatchRevert.plan(snapshots: snapshots, reader: reader)
        let inverse = AgentWriteBatchRevert.inverse(of: steps, reader: reader)
        let result = try AgentWriteBatchRevert.apply(steps) { path, text in
            guard case .inside(let url) = AgentWorkspaceSandbox.resolve(path, in: root) else {
                throw AgentBatchRevertError.outsideWorkspace(path)
            }
            if let text {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } else {
                try FileManager.default.removeItem(at: url)
            }
        }
        let moved = steps.compactMap { step -> String? in
            switch step {
            case .restore(let path, _), .delete(let path): return path
            case .conflict: return nil
            }
        }
        return (result, inverse, moved)
    }

    /// 撤回时要读的「盘上现在这一份」——越界一律回 `nil`（于是那一条按冲突处理，不写盘）。
    private func agentBatchReader(root: URL) -> (String) -> String? {
        { path in
            guard case .inside(let url) = AgentWorkspaceSandbox.resolve(path, in: root) else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }
    }

    /// 把磁盘上的新正文同步进正开着的那个页签（`FR-AI-25` ⑤ 的界面半）。
    ///
    /// 判定是 Core 的纯函数（`AgentEditBufferPlan`）：开着且**没有未保存改动**才重载。
    /// 走既有的 `reloadTab(force: false)` —— 一份文件只有一个重载出口，不为撤销再写第二条。
    private func syncEditorBuffer(path: String, root: URL) {
        guard let index = tabs.firstIndex(where: { $0.fileURL?.path == root.appendingPathComponent(path).path })
        else { return }
        let plan = AgentEditBufferPlan.action(hasOpenTab: true, isDirty: tabs[index].isDirty)
        guard plan == .reload else { return }
        reloadTab(at: index, force: false)
    }

    /// 保存只读模式与白名单（复用配置持久化，不另开一份存储）。
    @discardableResult
    func saveAgentGuardPolicy(_ policy: AgentGuardPolicy) async -> Bool {
        var configuration = agentConfiguration
        configuration.guardPolicy = policy.sanitized
        let succeeded = await saveAgentConfiguration(configuration, apiKey: nil)
        if succeeded {
            agentAuditMessage = L(.agentGuardSaved)
        }
        return succeeded
    }

    /// 读取本地审计日志（打开面板 / 刷新 / 清空后调用）。
    ///
    /// 顺带用日志重建待审批队列：审计是追加式的，重启后内存队列会空，
    /// 但日志里「待批准」那条还挂着 —— 按「同一动作取最后一条」恢复，
    /// 界面上才不会出现「日志说待批准、列表却说没有」。
    func refreshAgentAudit() async {
        isAgentAuditLoading = true
        defer { isAgentAuditLoading = false }
        do {
            agentAuditRecords = try await agentAuditLog.entries()
            pendingAgentApprovals = AgentApproval.pending(from: agentAuditRecords)
            agentAuditError = nil
        } catch {
            agentAuditError = L(.agentAuditLoadFailed, ErrorPresenter.message(for: error))
        }
    }

    /// 清空本地审计记录（界面必须二次确认后才会调用）。
    func clearAgentAudit() async {
        do {
            try await agentAuditLog.removeAll()
            agentAuditRecords = []
            agentAuditError = nil
            agentAuditMessage = L(.agentAuditCleared)
        } catch {
            agentAuditError = L(.agentAuditLoadFailed, ErrorPresenter.message(for: error))
        }
    }

    /// 导出审计记录（JSON / CSV）。
    ///
    /// **导出内容完全由 Core 生成**（`AgentAuditLog.export(_:)` → 已过
    /// `AgentAudit.redacted`），界面只负责选路径与写文件 —— 不在这里另拼一份导出，
    /// 否则「导出前脱敏」就成了看遵守不遵守的君子协定。
    @discardableResult
    // MARK: - 统一外发日志（NFR-SEC-08）

    /// 读取外发日志（新的在前）。
    func refreshEgressLog() async {
        do {
            egressEntries = try await egressLog.entries()
            egressError = nil
        } catch {
            egressError = ErrorPresenter.message(for: error)
        }
    }

    /// 清空外发日志（二次确认在界面上做）。
    func clearEgressLog() async {
        do {
            try await egressLog.clear()
            egressEntries = []
            egressMessage = L(.egressCleared)
            egressError = nil
        } catch {
            egressError = ErrorPresenter.message(for: error)
        }
    }

    /// 导出外发日志（JSON / CSV）。
    func exportEgressLog(asCSV: Bool) async -> Bool {
        guard !egressEntries.isEmpty else {
            egressError = L(.egressExportEmpty)
            return false
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        let baseName = asCSV ? "egress-log" : "egress-log"
        let ext = asCSV ? "csv" : "json"
        panel.nameFieldStringValue = "\(baseName).\(ext)"
        if let type = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            let data: Data = asCSV
                ? Data(try await egressLog.exportCSV().utf8)
                : try await egressLog.exportJSON()
            try data.write(to: url, options: [.atomic])
            egressError = nil
            egressMessage = L(.egressExported, egressEntries.count, url.lastPathComponent)
            return true
        } catch {
            egressError = L(.egressExportFailed, ErrorPresenter.message(for: error))
            return false
        }
    }

    func exportAgentAudit(format: AgentAuditExportFormat) async -> Bool {
        guard !agentAuditRecords.isEmpty else {
            agentAuditError = L(.agentAuditExportEmpty)
            return false
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(format.defaultBaseName).\(format.fileExtension)"
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            let data = try await agentAuditLog.export(format)
            try data.write(to: url, options: [.atomic])
            agentAuditError = nil
            agentAuditMessage = L(.agentAuditExported, agentAuditRecords.count, url.lastPathComponent)
            return true
        } catch {
            agentAuditError = L(.agentAuditExportFailed, ErrorPresenter.message(for: error))
            return false
        }
    }

    /// 智能体发起一次动作：过护栏 → 建审批单 / 直接拒绝 → **留痕**（FR-AI-09）。
    ///
    /// 行为边界值得写清楚：本方法**只判定与留痕，不执行**。
    /// - 只读模式下被拒的写操作 / DDL：连审批单都建不出来（`AgentActionGate` 返回 `.denied`），
    ///   只留一条 `denied` 记录并给出可读原因（AC-AI-02）；
    /// - 需要审批的：进待审批队列并弹出审批单，**批准之前不会执行**；
    /// - 无需审批的（只读查询 / 白名单类别）：返回 `.approved`，由调用方决定怎么处理，
    ///   `AgentSQLPanel` 仍走「放进新页签」——不自动执行（FR-AI-02）。
    @discardableResult
    func submitAgentAction(_ sql: String) async -> AgentActionSubmission {
        let submission = AgentActionGate.submit(
            sql: sql,
            databaseType: selectedConnection?.dbType ?? .postgresql,
            policy: agentGuardPolicy,
            context: agentActionContext,
            // 客户端连接权限校验（`FR-AI-12` 客户端半，队列 `L-125`）：事实来自连接自己的属性
            // （`isReadOnly`，FR-CONN-17）与 `refreshDatabaseCreationPermission` 探到的结论（FR-META-11）。
            permissions: AgentConnectionPermissions(
                isReadOnly: selectedConnection?.isReadOnly ?? false,
                canCreateDatabase: canCreateDatabase
            ),
            language: LocalizationManager.shared.effectiveLanguage
        )

        await appendAgentAudit(submission.record)

        switch submission {
        case .denied:
            agentAuditError = submission.message
        case .approved:
            agentAuditError = nil
        case .awaitingApproval(let approval):
            agentAuditError = nil
            pendingAgentApprovals.append(approval)
            agentApprovalRequest = approval
        }
        return submission
    }

    /// 审批单上的「预计影响行数」（§9.1.16 A4）：**问数据库自己的优化器**，不本地猜。
    ///
    /// 只跑 `EXPLAIN (FORMAT JSON)`（**不带 `ANALYZE`**）⇒ 不执行、不改任何数据。
    /// 估不出来时给**原因码**（界面翻成人话）—— 不报 `0`：`0` 是「一条都不命中」这个具体答案，
    /// 与「估不出来」是两件事，混在一起会让人拿假数当依据去点批准。
    func estimateAgentPlanRows(for sql: String) async -> AgentPlanRows.Estimate {
        guard let statement = AgentPlanRows.explainStatement(for: sql) else {
            return .unavailable("notDataChange")
        }
        guard let configuration = selectedConnection else {
            return .unavailable("noConnection")
        }
        // 目前只有 PostgreSQL 这一支有 `EXPLAIN (FORMAT JSON)` 这个形状；别方言**如实说没接**，
        // 不拿别的语法去套（MySQL 的 `EXPLAIN FORMAT=JSON` 字段名不同，套了就是假数）。
        guard configuration.dbType == .postgresql else {
            return .unavailable("dialectUnsupported")
        }
        guard let service = try? await ensureService(for: configuration,
                                                     database: queryDatabase(for: configuration)) else {
            return .unavailable("noConnection")
        }
        var json: String?
        do {
            for try await event in service.execute(statement, options: .default, handle: ExecutionHandle()) {
                if case .resultSet(let result) = event {
                    // 结果只有一行一列（整份计划 JSON）—— 它留在本机给审批单看，不进模型上下文。
                    json = result.rows.first?.first ?? nil
                }
            }
        } catch {
            return .unavailable("queryFailed")
        }
        return AgentPlanRows.estimate(json: json)
    }

    /// 高危任务的**逐条**影响面（`FR-STD-DB-TASK-002` 判据①「预估影响范围」）。
    ///
    /// 为什么逐条各问一次而不是整批一个数：`TRUNCATE` + `INSERT ... SELECT` 这种批量，
    /// 合计会把「其中一条扫全表」摊平；人能拿来做决定的正是**哪一条**要大动。
    /// 每一条都走同一条 `EXPLAIN (FORMAT JSON)`（不带 `ANALYZE`，不发语句本身），
    /// 估不出来就按原因码如实标 —— 不填 0。
    func estimateHighRiskPlan(_ plan: HighRiskTaskApproval.Plan) async -> HighRiskTaskApproval.Plan {
        var filled = plan
        for statement in plan.statements {
            switch await estimateAgentPlanRows(for: statement.sql) {
            case .rows(let count):
                filled.setImpact(.rows(count), forIndex: statement.index)
            case .unavailable(let code):
                filled.setImpact(.unavailable(code), forIndex: statement.index)
            }
        }
        return filled
    }

    /// 给审批单摆出「逐条」形状的计划（没指定库时也照建：目标库那一格如实写「未指定」）。
    func highRiskPlan(for record: AgentActionRecord) -> HighRiskTaskApproval.Plan? {
        try? HighRiskTaskApproval.plan(
            sql: record.sql,
            targetDatabase: record.database,
            databaseType: selectedConnection?.dbType ?? .postgresql
        )
    }

    /// 批准并执行一条待审批动作（审批单上的「批准并执行」）。
    func approveAgentAction(id: UUID, note: String? = nil) async {
        await decideAgentAction(id: id, approve: true, note: note)
    }

    /// 拒绝一条待审批动作：**不执行**，留痕。
    func rejectAgentAction(id: UUID, note: String? = nil) async {
        await decideAgentAction(id: id, approve: false, note: note)
    }

    /// 重新弹出某条待审批动作的审批单（面板里点「查看…」）。
    func presentAgentApproval(_ approval: AgentApproval) {
        guard approval.awaitsHumanDecision else { return }
        agentApprovalRequest = approval
    }

    /// 关掉审批单但不做决定：动作**留在待审批队列里**，关窗不等于批准。
    func dismissAgentApprovalSheet() {
        agentApprovalRequest = nil
    }

    /// 审计记录的上下文：连接名 / 库 / 模型（**不含口令，也不含完整连接串**）。
    private var agentActionContext: AgentActionRecord.Context {
        AgentActionRecord.Context(
            connectionName: selectedConnection?.name,
            database: selectedConnection.map { queryDatabase(for: $0) },
            model: agentConfiguration.normalizedModel
        )
    }

    // MARK: - 浏览器页签：宿主侧的三件事（队列 `L-149` 剩余①）
    //
    // 页签集 / 选中 / 引擎缓存 / 导航动作**都不在本类**了 —— 它们随状态一起搬进
    // `App/WorkspaceBrowserModel.swift`（新建 / 选中 / 关闭页签、取引擎、状态写回、
    // 地址栏导航、在浏览器里打开、会话恢复与落盘）。
    //
    // 这里刻意**不写出那几个入口的名字**：门禁 `check-browser-tab-ownership.py` 对它们做的是
    // **文本级**台账对账，写在本文件里会当场报红（这条纪律本身就是在钉「数据库侧 / 全局状态
    // 不许再出现浏览器」）。要看名字，去 `WorkspaceBrowserModel`。
    //
    // **为什么搬**：浏览器只是工作区的一类页签，它的加载状态不该惊动整个窗口（本类被整个窗口
    // 观测）。同族的病在数据库侧已用 `QueryEditorBuffer` 治过一次。
    //
    // 留下的三件都是**与全局有关**的：目录书签、外发日志面板、启动链上的失败告知 ——
    // 形状由 `WorkspaceBrowserHost` 协议定（实现即下面这三个方法 + `authorizedDownloadDirectory()`）。

    /// 下载用的授权目录（FR-EDIT-34，与 FR-AI-08 同一套 `SecureDirectoryAccess`）。
    ///
    /// 取**最近一次授权过**的目录。返回 `nil` 时引擎会拒绝这次下载并说明原因 ——
    /// 这是有意的：沙箱里往未授权的地方写不进去，而"悄悄落到 App 容器里"更糟
    /// （用户看到下载完成，却在任何地方都找不到文件）。
    func authorizedDownloadDirectory() -> URL? {
        guard let bookmark = storedDirectoryBookmarks.last else { return nil }
        guard let grant = try? MacDirectoryAccess.open(bookmark) else { return nil }
        // 访问权要保持到下载结束（WebKit 是异步写的），所以在这里攒着，完成 / 失败时统一释放。
        browserDownloadGrants.append(grant)
        return grant.url
    }

    /// 浏览器模型要落盘的目录（`WorkspaceBrowserHost` 的那一条）。
    ///
    /// 引擎的下载回调走这里 —— 目录的权威数据（用户授权过的书签）在本类，模型不自己抄一份。
    func browserDownloadDirectory() -> URL? {
        authorizedDownloadDirectory()
    }

    /// 统一外发日志（NFR-SEC-08）：**下载也是出网**，成功 / 失败 / 被拒都留一条账。
    ///
    /// 形状（目标 / 明细 / 页签身份）由 `WorkspaceBrowserModel.handleBrowserDownload` 出；
    /// 这里只写盘 + 刷面板。**终态（完成 / 失败）** 顺带归还目录访问权 —— 写盘是异步的，
    /// 持有期必须覆盖它（原先这两处 `releaseDownloadGrants()` 长在 `handleBrowserDownload`
    /// 的 `.finished` / `.failed` 分支里，随实现一起搬到这里，顺序与语义未变）。
    func recordBrowserDownloadEgress(
        outcome: EgressOutcome,
        target: String,
        detail: String,
        tabID: UUID,
        tabTitle: String?
    ) {
        if outcome == .allowed || outcome == .failed {
            releaseDownloadGrants()
        }
        Task {
            await egressLog.record(
                kind: .browser,
                target: target,
                origin: "浏览器 · 下载",
                outcome: outcome,
                detail: detail,
                tabID: tabID,
                tabTitle: tabTitle
            )
            await refreshEgressLog()
        }
    }

    /// 启动链上的失败（页签库损坏之类）如实说出来，但不打断启动。
    func reportBrowserStatusMessage(_ message: String) {
        statusMessage = message
    }

    /// 释放下载期间保持的目录访问权（幂等）。
    private func releaseDownloadGrants() {
        for grant in browserDownloadGrants { grant.stopAccessing() }
        browserDownloadGrants.removeAll()
    }

    /// 追加一条审计记录：先落到内存（面板立刻看得见），再追加到 JSONL。
    /// 写盘失败必须说出来 —— 审计写不进去是安全问题，不能静默吞掉。
    private func appendAgentAudit(_ record: AgentActionRecord) async {
        agentAuditRecords.append(record)
        do {
            try await agentAuditLog.append(record)
        } catch {
            agentAuditError = L(.agentAuditLoadFailed, ErrorPresenter.message(for: error))
        }
    }

    // MARK: - 斜杠命令的宿主侧两口（`FR-AGT-UX-CONV-014` / `-015`）

    /// 斜杠命令那一行审计的落点（与工具 / 模型调用走**同一条**追加通道）。
    func recordAgentSlashAudit(_ record: AgentActionRecord) async {
        await appendAgentAudit(record)
    }

    /// 一条**已批准**的配置变更真的落地。
    ///
    /// 本版只接得了 `/theme` —— 外观偏好已经是本进程的配置真值源（`appearanceMode`，
    /// 改完立即生效并落 `UserDefaults`）。`/model` 还没接：模型名归智能体设置面板
    /// （`FR-AGT-OPS-OBS-002` 那条「设置面板接线」），本函数**如实返回 `false`**，
    /// 由界面说「已批准但没有落地入口」—— 不假装改过。
    func applyAgentSlashConfigChange(kind: AgentSlashCommandKind, argument: String) -> Bool {
        switch kind {
        case .theme:
            guard let preference = AgentSlashThemeArgument.preference(from: argument) else { return false }
            appearanceMode = preference
            return true
        case .model, .help, .clear, .compact, .search, .stop, .steer, .queue:
            return false
        }
    }

    /// 审批决策：状态机流转 → （批准时）执行 → 追加终态记录。
    private func decideAgentAction(id: UUID, approve: Bool, note: String?) async {
        guard let index = pendingAgentApprovals.firstIndex(where: { $0.id == id }) else { return }
        var approval = pendingAgentApprovals[index]

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote

        // `FR-STD-DB-TASK-002`：**整批一次决定** —— 批准才交出语句、拒绝一条都不交、
        // 同一批没有「先发前两条试试」这一档。计划建不出来（空白语句等）时退回人点的那个选择，
        // 不因为构造失败反过来拦住审批。
        let batchPlan = highRiskPlan(for: approval.record)
        let batchOutcome = batchPlan.map {
            HighRiskTaskApproval.outcome(for: $0, decision: approve ? .approve : .reject)
        }
        let effectivelyApproved = batchOutcome.map(\.sendsAnything) ?? approve

        do {
            if effectivelyApproved {
                try approval.approve(by: NSUserName(), note: noteValue)
            } else {
                try approval.reject(by: NSUserName(), note: noteValue)
            }
        } catch {
            // 非法流转（例如已被处理过）不猜、不硬改，照实报错。
            agentAuditError = ErrorPresenter.message(for: error)
            return
        }

        pendingAgentApprovals.remove(at: index)
        if agentApprovalRequest?.id == id { agentApprovalRequest = nil }

        if effectivelyApproved {
            // R-27（2026-09-23 评审）：**先落审计，再执行**。
            //
            // 执行是不可逆的；原来是先执行、后追加终态记录 —— 进程若在两者之间死掉，
            // 日志里就什么都没有：一次真打到库上的写操作，审计上等于没发生过。
            // 现在先写一条「已批准」（这本身就是必须留痕的事实），写不进去就**不执行**。
            do {
                try await agentAuditLog.append(approval.record)
                agentAuditRecords.append(approval.record)
            } catch {
                let message = L(.agentAuditLoadFailed, ErrorPresenter.message(for: error))
                try? approval.markFailed(detail: message)
                agentAuditError = message
                if let pending = pendingDataTaskRuns.removeValue(forKey: id) {
                    await failDataTaskRun(pending, message: message)
                }
                await appendAgentAudit(approval.record)
                return
            }

            // R-26（同日评审）：**执行必须绑在审批时的那条连接上**。
            //
            // 审批单上写的是哪台库，执行时就该打哪台库；原来用的是"当前选中连接" ——
            // 批准之后切一下连接，同一条语句就落到生产上了。这是最不该有的错配。
            let current = agentActionContext
            let connectionMismatch = approval.record.connectionName != nil
                && approval.record.connectionName != current.connectionName
            let databaseMismatch = approval.record.database != nil
                && current.database != nil
                && approval.record.database != current.database
            if connectionMismatch || databaseMismatch {
                let message = L(
                    .agentApprovalConnectionMismatch,
                    approval.record.connectionName ?? "—",
                    current.connectionName ?? "—"
                )
                try? approval.markFailed(detail: message)
                agentAuditError = message
                if let pending = pendingDataTaskRuns.removeValue(forKey: id) {
                    await failDataTaskRun(pending, message: message)
                }
                await appendAgentAudit(approval.record)
                return
            }

            do {
                let rowsWritten = try await executeApprovedAgentAction(approval.record.sql)
                try approval.markExecuted()
                agentAuditError = nil
                agentAuditMessage = L(.agentApprovalApproved)
                // 数据任务的执行要接着收尾（导出产物 + 记执行历史）。
                if let pending = pendingDataTaskRuns.removeValue(forKey: id) {
                    await finishApprovedDataTaskRun(pending, rowsWritten: rowsWritten)
                }
            } catch {
                // 批准了但执行失败：记为 `failed`，失败原因进审计（不是静默失败）。
                let message = ErrorPresenter.message(for: error)
                try? approval.markFailed(detail: message)
                agentAuditError = L(.errorQueryFailed, message)
                if let pending = pendingDataTaskRuns.removeValue(forKey: id) {
                    await failDataTaskRun(pending, message: message)
                }
            }
        } else {
            agentAuditError = nil
            agentAuditMessage = L(.agentApprovalRejected)
            if let pending = pendingDataTaskRuns.removeValue(forKey: id) {
                await rejectDataTaskRun(pending, message: L(.dataTaskRunRejected))
            }
        }

        await appendAgentAudit(approval.record)
    }

    /// 已获批准的数据任务执行收尾：导出产物 → 记一条执行历史。
    private func finishApprovedDataTaskRun(_ pending: PendingDataTaskRun, rowsWritten: Int?) async {
        var artifactName: String?
        var artifactFailure: String?
        if pending.task.output != nil {
            do {
                artifactName = try await exportDataTaskArtifact(pending.task)
            } catch {
                artifactFailure = ErrorPresenter.message(for: error)
            }
        }

        let message = artifactName.map { L(.dataTaskRunSucceeded, rowsWritten ?? 0, $0) }
            ?? L(.dataTaskRunSucceededNoArtifact, rowsWritten ?? 0)

        await recordDataTaskRun(
            task: pending.task,
            plannedAt: pending.plannedAt,
            startedAt: pending.startedAt,
            status: .succeeded,
            rowsWritten: rowsWritten,
            message: message
        )

        if let artifactFailure {
            dataTaskError = L(.dataTaskRunArtifactFailed, artifactFailure)
            dataTaskMessage = message
        } else {
            dataTaskError = nil
            dataTaskMessage = message
        }
    }

    /// 执行一条**已获批准**的智能体语句，复用既有的连接与逐条下发路径；
    /// 返回影响行数合计（没有该事件时为 `nil`），供执行历史记录「写入行数」。
    private func executeApprovedAgentAction(_ sql: String) async throws -> Int? {
        guard let configuration = selectedConnection else { throw AppError.notConnected }
        let service = try await ensureService(
            for: configuration,
            database: queryDatabase(for: configuration)
        )
        return try await runStatementsCountingAffected(
            sql,
            databaseType: configuration.dbType,
            on: service
        )
    }

    /// 与 `runStatements` 同一条下发路径，额外把影响行数累加起来。
    private func runStatementsCountingAffected(
        _ sql: String,
        databaseType: DatabaseType,
        on service: any DatabaseService
    ) async throws -> Int? {
        let statements = StatementSplitter(databaseType: databaseType).split(sql)
        var tally = AffectedRowsTally()
        for statement in statements {
            for try await event in service.execute(statement.sql, options: .default) {
                tally.absorb(event)      // 计数只有这一处（R-32）
            }
        }
        return tally.value
    }

    /// 供模型参考的 schema 摘要（NFR-AI-01：只有结构，没有行数据）。
    ///
    /// 取表清单走**一条**查询（方言的 `listTablesQuery`），并把数量封顶 ——
    /// 「最小外发」不只是不发结果集，也包括别把上千张表一股脑倒出去。
    /// 表结构摘要的**有界**取法：最多等 `seconds` 秒，超时就当没取到。
    ///
    /// 为什么必须有界：`agentSchemaSummary` 会经 `ensureService` 去连库，库不可达时
    /// 连接层可能长时间不返回（没有连接超时）—— 而它坐在**每一轮对话的必经之路**上，
    /// 一条等不到结果的 await 会把整轮（含 IM 派活）静默挂住。上下文是附加物，不是前置条件。
    private func agentSchemaSummaryWithTimeout(seconds: UInt64 = 3) async -> AgentSQLGenerator.SchemaSummary? {
        await withTaskGroup(of: AgentSQLGenerator.SchemaSummary?.self) { group in
            group.addTask { [weak self] in
                guard let self else { return nil }
                return try? await self.agentSchemaSummary(includeTableList: true)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    func agentSchemaSummary(includeTableList: Bool) async throws -> AgentSQLGenerator.SchemaSummary {
        guard let configuration = selectedConnection else {
            throw AppError.notConnected
        }
        let database = currentDatabaseName(for: configuration)
        guard includeTableList else {
            return AgentSQLGenerator.SchemaSummary(database: database, tables: [])
        }

        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        let service = try await ensureService(for: configuration, database: database)
        let result = try await runSingleQuery(dialect.listTablesQuery(database: database, schema: nil), on: service)
        // 列名兼容两套命名（PG 的 information_schema 用 table_name，GBase 的 SHOW TABLES 用第一列）；
        // 这里只认表名这一列，避免把整行原样外发。
        let nameIndex = result.columns.firstIndex { column in
            ["table_name", "name", "tables_in_" + database.lowercased()].contains(
                column.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
        } ?? (result.columns.isEmpty ? nil : 0)
        // 有 table_schema 就用它（不同方言 / 版本给不给这一列不一样，缺了就退回方言默认）。
        let schemaIndex = result.columns.firstIndex {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "table_schema"
        }

        guard let nameIndex else {
            return AgentSQLGenerator.SchemaSummary(database: database, tables: [])
        }

        let listed = result.rows.prefix(Self.agentTableListLimit).compactMap { row -> (name: String, schema: String?)? in
            guard nameIndex < row.count,
                  let raw = row[nameIndex],
                  case let name = raw.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty
            else { return nil }
            var schema: String?
            if let schemaIndex, schemaIndex < row.count, let rawSchema = row[schemaIndex] {
                let trimmed = rawSchema.trimmingCharacters(in: .whitespacesAndNewlines)
                schema = trimmed.isEmpty ? nil : trimmed
            }
            return (name, schema)
        }

        // 补列：**模型看不到列名就写不准查询**，所以列才是 schema 摘要里最有用的部分。
        // 同时封两道口子——表数与总列数都设上限，避免一次外发把整库结构倒出去（NFR-AI-01）。
        var tables: [AgentSQLGenerator.SchemaSummary.Table] = []
        var columnBudget = Self.agentColumnBudget

        for entry in listed {
            guard columnBudget > 0 else {
                tables.append(AgentSQLGenerator.SchemaSummary.Table(schema: entry.schema, name: entry.name))
                continue
            }
            let specs = (try? await agentColumnSpecs(
                table: entry.name,
                schema: entry.schema,
                database: database,
                configuration: configuration,
                dialect: dialect
            )) ?? []
            let columns = specs.prefix(columnBudget).map {
                AgentSQLGenerator.SchemaSummary.Column(name: $0.name, type: $0.typeName)
            }
            columnBudget -= columns.count
            tables.append(
                AgentSQLGenerator.SchemaSummary.Table(
                    schema: entry.schema,
                    name: entry.name,
                    columns: Array(columns)
                )
            )
        }

        return AgentSQLGenerator.SchemaSummary(database: database, tables: tables)
    }

    /// 取某张表的列（供 schema 摘要外发使用）；失败返回空数组，不让整次生成失败。
    private func agentColumnSpecs(
        table: String,
        schema: String?,
        database: String,
        configuration: ConnectionConfig,
        dialect: any SQLDialect
    ) async throws -> [ColumnMeta] {
        let service = try await ensureService(for: configuration, database: database)
        let result = try await runSingleQuery(
            dialect.listColumnsQuery(table: table, schema: schema),
            on: service
        )
        return ColumnSpecParser.columns(from: result)
    }

    /// **本次运行**的智能体用量账本（NFR-AI-04）。
    ///
    /// 为什么必须留在内存里跨调用累计：配额判定的输入就是它 —— 每次都传 `.empty` 的话，
    /// 「调用次数上限 / 累计 token 上限」**永远触发不了**（本轮发现的真缺口）。
    /// 按需求口径它是「单次会话」，所以退出应用即清零，不落盘。
    @Published private(set) var agentQuotaLedger: AgentQuotaLedger = .empty

    /// **对话那条路的配额回写**（`NFR-AI-04` + `FR-AI-31` ③）：一轮跑完把账本交回来。
    ///
    /// 不接这一步 ⇒ 每轮都从同一个旧账本起算，「调用次数 / 累计 token」两个上限在真实路径上
    /// 仍然永远不会触发（v3.88 修掉的那条第 1 项缺口在对话侧原样复发）。
    func recordAgentChatQuota(_ ledger: AgentQuotaLedger) {
        agentQuotaLedger = ledger
    }

    // MARK: - 运行策略（`FR-AGT-OPS-OBS-002`：可配置 + 立即生效 + 有据可查）

    /// 运行策略在盘上的那一份（与其余本机数据同一目录，不另开文件体系）。
    private var agentRuntimeConfigFile: AgentRuntimeConfigFile {
        AgentRuntimeConfigFile(directory: AgentSessionStore.defaultDirectory)
    }

    /// 当日 token 账（日配额的生效面）。
    private var agentDailyUsageLedger: AgentDailyUsageLedger {
        AgentDailyUsageLedger(directory: AgentSessionStore.defaultDirectory)
    }

    /// 进程内持有的那一份运行策略（改一项立刻写回，**下一轮**就按新的来 —— 不必重启）。
    @Published private(set) var agentRuntimeConfig = AgentConfigStore()
    /// 盘上那份的载入结论（`fresh` / `loaded` / `degraded`）—— 面板照实说一句。
    @Published private(set) var agentRuntimeConfigState: AgentRuntimeConfigFile.LoadState = .fresh
    private var agentRuntimeConfigLoaded = false
    /// 白名单里写了但注册表里没有的工具名（面板照实点名 —— 用户写错一个字要看得见）。
    @Published private(set) var agentToolWhitelistUnknown: [String] = []
    /// 插件目录里没装上的清单（`FR-AGT-LINK-EXT-003`：逐条点名「哪个文件 + 为什么」，
    /// 不是静默跳过 —— 用户把插件丢进目录后没生效，得能看见原因）。
    @Published private(set) var agentExtensionProblems: [AgentExtensionCatalogProblem] = []

    /// 插件目录（`FR-AGT-LINK-EXT-003` 的装卸入口）：用户把插件文件夹丢进这里，
    /// 面板点「重新扫描」即可 —— **目录扫出来的就是已装清单**（面板只是这件事的另一个入口，
    /// 不是唯一的真值源，所以面板没打开时循环照样按目录装）。
    var agentExtensionDirectory: URL {
        AgentSessionStore.defaultDirectory
            .appendingPathComponent(AgentExtensionCatalog.folderName, isDirectory: true)
    }

    /// 已装插件的台账。面板与循环**读同一份**：面板显示「已装」而循环用的是另一份，是最难查的一类假绿。
    @Published private(set) var agentExtensionDesk = AgentExtensionDesk()

    /// 面板上「最近一次卸载」的收据：残留读数照它说，不许凭空说一句「已卸载」。
    @Published private(set) var agentExtensionLastUninstall: AgentExtensionUninstallReceipt?

    /// 扫一遍插件目录：装上 / 没装上 / 目录不存在 三种情形都归口到这里。
    func rescanAgentExtensions() {
        // 目录先建出来：用户要往里放东西，得先看得见这个位置（失败也不拦，扫出来就是空的）。
        try? FileManager.default.createDirectory(at: agentExtensionDirectory, withIntermediateDirectories: true)
        let loaded = AgentExtensionCatalog.load(directory: agentExtensionDirectory)
        agentExtensionDesk = loaded.desk
        agentExtensionProblems = loaded.problems
    }

    /// 卸载一个插件：**它自己声明拥有的路径真删**，要停的子进程交回去（谁家起的谁停）。
    ///
    /// 卸不存在的不假装成功（收据 `wasInstalled = false`，面板据此说「什么都没动」）。
    /// 卸载不动别家的授权面 —— 台账按 id 逐个摘，不重建整份。
    func uninstallAgentExtension(pluginID: String) {
        var desk = agentExtensionDesk
        let receipt = desk.uninstall(pluginID: pluginID)
        agentExtensionDesk = desk
        agentExtensionLastUninstall = receipt
    }

    /// 读一次盘（幂等；面板打开、建循环前都会调）。
    func loadAgentRuntimeConfigIfNeeded() {
        guard !agentRuntimeConfigLoaded else { return }
        agentRuntimeConfigLoaded = true
        let loaded = agentRuntimeConfigFile.load()
        agentRuntimeConfig = loaded.store
        agentRuntimeConfigState = loaded.state
    }

    /// 保存结果：没改动 / 存进去了（附每条的「改前 → 改后」）/ 被拒（附原因）。
    enum AgentRuntimeConfigSaveResult: Equatable {
        case noChange
        case saved([String])
        case rejected(String)
    }

    /// 面板上按一次「保存策略」：差异 → 原子校验 → 落盘 → 换内存那份。
    ///
    /// 顺序是刻意的：**先校验通过再写盘**（写盘成功但校验失败等于把非法配置留在盘上）。
    func saveAgentRuntimeConfig(draft: AgentRuntimeConfigDraft, reason: String) -> AgentRuntimeConfigSaveResult {
        loadAgentRuntimeConfigIfNeeded()
        let edits = draft.edits(against: agentRuntimeConfig.snapshot)
        guard !edits.isEmpty else { return .noChange }
        var next = agentRuntimeConfig
        do {
            let applied = try next.applyBatch(edits, reason: reason)
            try agentRuntimeConfigFile.save(next)
            agentRuntimeConfig = next
            return .saved(applied.map(\.summaryLine))
        } catch let error as AgentConfigError {
            return .rejected(AgentConfigRejectionText.line(for: error))
        } catch {
            return .rejected(ErrorPresenter.message(for: error))
        }
    }

    /// 开跑前问一次：今天的额度还剩多少（配额为 0 或已用满 ⇒ 拦住）。
    func agentDailyQuotaVerdict() -> AgentDailyUsageLedger.Verdict {
        loadAgentRuntimeConfigIfNeeded()
        return agentDailyUsageLedger.verdict(quota: agentRuntimeConfig.snapshot.dailyTokenQuota)
    }

    /// 一轮跑完记当日用量（记账是旁路：写不进去不影响这一轮的结果）。
    func recordAgentDailyTokens(_ tokens: Int) {
        guard tokens > 0 else { return }
        _ = agentDailyUsageLedger.record(tokens: tokens)
    }

    /// 今日用量读数（面板那一行「今日已用 N / M」）。
    func agentDailyTokenReading() -> (used: Int, quota: Int, degraded: Bool) {
        loadAgentRuntimeConfigIfNeeded()
        let reading = agentDailyUsageLedger.reading()
        return (reading.tokens, agentRuntimeConfig.snapshot.dailyTokenQuota, reading.degraded)
    }

    // MARK: - 显示开关（`FR-AGT-UX-CONV-012`：九项、改一项立刻生效并落盘）

    /// 九个开关在盘上的那一份（与其余本机数据同一目录）。
    private var agentDisplayPreferencesFile: AgentDisplayPreferencesFile {
        AgentDisplayPreferencesFile(directory: AgentSessionStore.defaultDirectory)
    }

    /// 进程内那一份。**视图直接读它**：改一项立刻换值 ⇒ 这一屏下一次重绘就是新形态
    /// （契约①「立即生效」；不需要重启、也不需要重建会话）。
    @Published private(set) var agentDisplayPreferences = AgentDisplayPreferences()
    /// 盘上那份的载入结论（面板照实说一句「哪一项读不出来、已按默认值」）。
    @Published private(set) var agentDisplayPreferencesState: AgentDisplayPreferencesFile.LoadState = .fresh
    private var agentDisplayPreferencesLoaded = false

    /// 读一次盘（幂等；面板打开与对话页首次出现时都会调）。
    func loadAgentDisplayPreferencesIfNeeded() {
        guard !agentDisplayPreferencesLoaded else { return }
        agentDisplayPreferencesLoaded = true
        let loaded = agentDisplayPreferencesFile.load()
        agentDisplayPreferences = loaded.preferences
        agentDisplayPreferencesState = loaded.state
    }

    enum AgentDisplaySaveResult: Equatable {
        case saved
        /// 被拒（一句人话：哪个键、给了什么、允许什么）。
        case rejected(String)
    }

    /// 改一项：**校验 → 落盘 → 换内存那份**。顺序是刻意的 ——
    /// 先写盘后校验会让非法值留在盘上，下次启动就带着一份坏配置起来。
    ///
    /// 显示开关**不要理由、不留改动史**（与运行策略的差别写在 `AgentDisplayPreferences` 的注释里）：
    /// 它只改变「看起来什么样」，把观感改动也塞进审计会把真审计淹掉。
    func setAgentDisplay(key: AgentDisplayKey, value: String) -> AgentDisplaySaveResult {
        loadAgentDisplayPreferencesIfNeeded()
        var next = agentDisplayPreferences
        do {
            try next.apply(key: key.rawValue, value: value)
        } catch let error as AgentDisplayError {
            return .rejected(AgentDisplayRejectionText.line(for: error,
                                                            language: LocalizationManager.shared.effectiveLanguage))
        } catch {
            return .rejected(ErrorPresenter.message(for: error))
        }
        do {
            try agentDisplayPreferencesFile.save(next)
            agentDisplayPreferences = next
            agentDisplayPreferencesState = .loaded
            return .saved
        } catch {
            // 写不进去就**不换内存那份**：界面看到的必须与盘上一致，
            // 否则「重启后保持」这条会变成「这次看着生效了、下次没了」。
            return .rejected(ErrorPresenter.message(for: error))
        }
    }

    /// 把九项一次恢复到契约默认（面板上「恢复默认」那一下）。
    func resetAgentDisplayPreferences() -> AgentDisplaySaveResult {
        loadAgentDisplayPreferencesIfNeeded()
        do {
            try agentDisplayPreferencesFile.save(.contractDefaults)
            agentDisplayPreferences = .contractDefaults
            agentDisplayPreferencesState = .loaded
            return .saved
        } catch {
            return .rejected(ErrorPresenter.message(for: error))
        }
    }

    /// 表清单外发上限（防止把上千张表发出去）。
    static let agentTableListLimit = 60
    /// 列信息外发总量上限（按列累计，超出后的表只发表名）。
    static let agentColumnBudget = 400

    // MARK: - 编辑区 AI 辅助（`FR-STD-WS-AI-001`）

    /// 打开编辑区 AI 辅助面板：上下文（文件 / 语言 / 选区）从**真编辑器**现取，
    /// 闸门（端点 / 模型 / 边界 / 本机能力）由 Core 的 `EditAssist.gate` 判在发请求之前。
    ///
    /// 这里只做三件界面侧的事：取上下文、把「发请求」与「应用改动」两根线交给 AppState
    /// （密钥 / 外发留痕 / 撤销栈都在这两侧），其余判断一概不重复实现。
    @MainActor
    func presentEditAssist(_ action: EditAssist.Action,
                           model: EditAssistModel,
                           tabs: WorkspaceTabsModel) {
        guard let tab = tabs.selectedTab, let path = tab.path, !tab.isHome, !tab.isAgentChat else {
            model.open(
                action: action,
                context: EditAssist.Context(fileName: "", language: .plainText, fileText: "",
                                            selection: NSRange(location: 0, length: 0)),
                endpoint: agentConfiguration.endpoint,
                model: agentConfiguration.model
            )
            return
        }
        let selection = EditorCommandCenter.shared.liveSelection(for: tab.id)
            ?? NSRange(location: 0, length: 0)
        let context = EditAssist.Context(
            fileName: WorkspaceTabSet.title(for: path),
            language: tab.language,
            fileText: tab.content,
            selection: selection
        )
        model.runner = { [weak self] request in
            guard let self else { throw LLMError.disabled }
            return try await self.editAssistComplete(request)
        }
        model.apply = { [weak tabs] proposal in
            tabs?.deliverAssist(proposal, for: tab.id)
        }
        model.open(action: action, context: context,
                   endpoint: agentConfiguration.endpoint, model: agentConfiguration.model)
    }

    // MARK: - 调试器（`FR-STD-WS-TOOL-003`）

    /// 打开调试面板；工作区里有文件时把「要调试的程序」预填成它（用户可改）。
    @MainActor
    func presentDebugPanel(tabs: WorkspaceTabsModel) {
        if debugSession.program.isEmpty, let path = tabs.selectedTab?.path {
            debugSession.program = path
        }
        isDebugPanelPresented = true
    }

    /// 「在当前行切换断点」：行号由 `Core/CodeLines` 从光标偏移算（与行号列同一份实现）。
    @MainActor
    func toggleBreakpointAtCaret(tabs: WorkspaceTabsModel) {
        guard let tab = tabs.selectedTab, let path = tab.path, !tab.isHome else {
            isDebugPanelPresented = true
            return
        }
        let offset = EditorCommandCenter.shared.liveSelection(for: tab.id)?.location ?? 0
        let line = CodeLines.lineNumber(at: offset, in: tab.content)
        debugSession.toggleBreakpoint(line: line, in: path)
    }

    /// 真发这一次「编辑区 AI 辅助」请求。
    ///
    /// 与既有的智能体通道同一套：密钥显式带上（漏了必 401，2026-10-16 实机踩过）、
    /// 外发进 `Egress` 日志、失败也留痕（NFR-AI-03）。
    func editAssistComplete(_ request: EditAssist.Request) async throws -> LLMResponse {
        let raw = agentConfiguration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), url.scheme != nil else {
            throw LLMError.forbidden(L(.editAssistRefusedEndpoint))
        }
        let started = Date()
        let llmRequest = LLMRequest(
            endpoint: url,
            model: agentConfiguration.model,
            apiKey: agentAPIKey,
            timeoutSeconds: agentConfiguration.timeoutSeconds,
            systemPrompt: request.systemPrompt,
            userPrompt: request.userPrompt
        )
        let client = RetryingLLMClient(
            base: OpenAICompatibleClient(
                transport: EgressRecordingTransport(
                    origin: "编辑区 AI 辅助",
                    wrapped: URLSessionTransport()
                )
            )
        )
        do {
            let response = try await client.complete(llmRequest)
            await recordAgentModelCall(summary: request.action.rawValue, outcome: .generated, since: started)
            return response
        } catch {
            await recordAgentModelCall(summary: request.action.rawValue, outcome: .failed,
                                       since: started, detail: ErrorPresenter.message(for: error))
            throw error
        }
    }

    /// 走完整条「自然语言 → SQL」通道；产物是文本，**不会被自动执行**（FR-AI-02）。
    func generateAgentSQL(
        instruction: String,
        schema: AgentSQLGenerator.SchemaSummary,
        currentStatement: String?,
        observation: AgentObservation? = nil
    ) async throws -> AgentSQLGenerator.Result {
        let started = Date()
        do {
            let result = try await AgentSQLGenerator.generate(
                request: AgentSQLGenerator.Request(
                    instruction: instruction,
                    schema: schema,
                    currentStatement: currentStatement,
                    observation: observation
                ),
                configuration: agentConfiguration,
                apiKey: agentAPIKey,
                // 只读模式 / 白名单来自配置（FR-AI-09），不再写死默认策略。
                policy: agentGuardPolicy,
                // 传**累计账本**，否则配额永远触发不了（见 agentQuotaLedger 的说明）。
                ledger: agentQuotaLedger,
                client: RetryingLLMClient(
                    base: OpenAICompatibleClient(
                    transport: EgressRecordingTransport(
                        origin: "智能体 · 用自然语言生成 SQL",
                        wrapped: URLSessionTransport()
                    )
                    )
                )
            )
            await recordAgentModelCall(summary: instruction, outcome: .generated, since: started)
            // 记账：下一次调用的配额判定要用它（NFR-AI-04）。
            agentQuotaLedger = result.quotaLedger
            return result
        } catch {
            // 失败的调用同样留痕：审计要能回答「哪次调用失败了、花了多久」（NFR-AI-03）。
            await recordAgentModelCall(
                summary: instruction,
                outcome: .failed,
                since: started,
                detail: ErrorPresenter.message(for: error)
            )
            throw error
        }
    }

    /// 模型调用留痕（NFR-AI-03：模型 / 请求摘要 / 耗时 / 结果状态）。
    ///
    /// 用的是与动作提交同一份审计日志与同一个上下文（连接 / 库 / 模型，**不含口令**），
    /// 所以导出、筛选、清空、脱敏全都自动生效，不需要为「模型调用」另开一条存储。
    private func recordAgentModelCall(
        summary: String,
        outcome: AgentActionRecord.Outcome,
        since start: Date,
        detail: String? = nil
    ) async {
        let record = AgentActionRecord.makeModelCall(
            requestSummary: summary,
            model: nil,                      // 上下文里已经带了模型名
            context: agentActionContext,
            durationMilliseconds: Int(Date().timeIntervalSince(start) * 1000),
            outcome: outcome,
            detail: detail
        )
        await appendAgentAudit(record)
    }

    // MARK: - 连接测试（人类主人 2026-10-16 要求：配置界面要有一个「测试」按钮）

    /// 一次连接测试的结果：**两态如实分开**（通了给模型与用时；不通给原因原文），不合并成一个含混的结论。
    enum AgentConnectionTest: Equatable {
        case passed(model: String, millis: Int)
        case failed(String)
    }

    /// 真发一次**最小的**模型往返（不是"假装试一下"）。
    ///
    /// 三条纪律：① 走**和 Agent 循环同一个**流式客户端与请求构造（不另起一套、不硬编码 URL）；
    /// ② **不绕过闸门** —— 总开关关着 / 配置不完整 / 缺密钥时，这次请求会被既有判定挡下，错误原文如实回传
    /// （测试**不等于**放行，它只是一次真实往返）；③ **不写会话留痕**（它不是对话内容）。
    /// 如实登记：这条路与循环一样走**默认流式传输**，所以它**不进** `egress-log.jsonl`（那份日志记的是
    /// 非流式传输那一条路）—— 配通没配通仍以 App 里的结果行为准。
    /// - Parameter apiKeyOverride: 面板里**刚输入、还没保存**的 Key。测连接必须测「用户眼前这一份」，
    ///   否则刚填完 Key 点测试仍会用旧值（实机现象：填了新 Key，测试照样 401）。
    func testAgentConnection(apiKeyOverride: String? = nil) async -> AgentConnectionTest {
        let configuration = agentConfiguration
        guard let url = URL(string: configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failed(L(.agentTestMisconfigured))
        }
        // **踩过的坑（2026-10-16 实机 401）**：第一版这里漏了 `apiKey` ⇒ 发出去的是**裸请求**，
        // 端点原样回 401，看上去像"用户的 key 不对"。密钥是靠 `LLMRequest.apiKey` 进 `Authorization` 头的
        // （`LLMClient.swift` 里那一处唯一出口）—— 任何新造的请求都必须显式带上它，否则必然 401。
        // 面板里刚输入的那份优先（空 = 没填，退回已保存的那份）
        let draft = apiKeyOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let effectiveKey = draft.isEmpty ? agentAPIKey : draft
        let request = LLMRequest(endpoint: url, model: configuration.model,
                                 apiKey: effectiveKey,
                                 timeoutSeconds: configuration.timeoutSeconds,
                                 systemPrompt: "这是一次连接测试。", userPrompt: "回复两个字：收到。")
        // 用**与 Agent 循环同一个**流式客户端（`AppState` 里那条循环也是这么造的），不另起一套。
        let client = OpenAICompatibleStreamingClient()
        let started = Date()
        do {
            let stream = try await client.stream(request)
            for try await event in stream {
                if case .done = event { break }
            }
            return .passed(model: configuration.model,
                           millis: Int(Date().timeIntervalSince(started) * 1000))
        } catch {
            return .failed(ErrorPresenter.message(for: error))
        }
    }

    /// 把生成结果放进**新页签**的编辑器里（不覆盖用户正在写的内容，也不执行）。
    func openGeneratedSQLInNewTab(_ sql: String) {
        openSQLInNewTab(sql, status: L(.agentSQLNotExecuted))
    }

    /// 走完整条「规格说明 → 数据任务定义」通道（FR-AI-05）；产物是**定义草案**，
    /// 既不保存也不执行 —— 保存要过试运行 + 校验，执行要走审批（FR-AI-09）。
    func generateDataTaskSpec(
        specs: String,
        schema: AgentSQLGenerator.SchemaSummary,
        hints: String?
    ) async throws -> DataTaskSpecGenerator.Result {
        let started = Date()
        do {
            let result = try await DataTaskSpecGenerator.generate(
                request: DataTaskSpecGenerator.Request(specs: specs, schema: schema, hints: hints),
                configuration: agentConfiguration,
                apiKey: agentAPIKey,
                // 只读模式 / 白名单来自配置（FR-AI-09），与其它智能体路径同一份策略。
                policy: agentGuardPolicy,
                ledger: agentQuotaLedger,
                client: OpenAICompatibleClient(
                    transport: EgressRecordingTransport(
                        origin: "智能体 · 数据任务规格",
                        wrapped: URLSessionTransport()
                    )
                )
            )
            await recordAgentModelCall(summary: specs, outcome: .generated, since: started)
            // 记账：下一次调用的配额判定要用它（NFR-AI-04）。
            agentQuotaLedger = result.quotaLedger
            return result
        } catch {
            await recordAgentModelCall(
                summary: specs,
                outcome: .failed,
                since: started,
                detail: ErrorPresenter.message(for: error)
            )
            throw error
        }
    }

    /// 把生成的 SQL 放进**新页签**的编辑器：不覆盖用户正在写的内容，也不执行（FR-META-14）。
    func openSQLInNewTab(
        _ sql: String,
        status: String? = nil,
        execute: Bool = false,
        source: DatabaseObjectRef? = nil
    ) {
        newQueryTab()
        guard let tabID = selectedTabID else { return }
        updateSQL(sql, for: tabID)
        if let source, let index = tabs.firstIndex(where: { $0.id == tabID }) {
            tabs[index].sourceTable = source
        }
        statusMessage = status ?? L(.objectTreeOpenedInNewTab)
        // `execute: true` 只用于"用户刚刚在面板上确认过语句"的入口（浏览 / 计数）：
        // 语句在面板里已经**实时预览**过，且仍然走 Safe Mode 那一关。
        if execute {
            Task { await executeQuery(for: tabID) }
        }
    }

    /// 按条件浏览（FR-DATA-02）：条件发给数据库执行，结果进新页签并立刻执行。
    func browseRows(_ object: DatabaseObject, filter: RowBrowsingQuery.Filter) {
        guard let configuration = selectedConnection else {
            errorMessage = L(.stateSelectConnectionFirst)
            return
        }
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        switch RowBrowsingQuery.browse(table: object.name, schema: object.schema, filter: filter, dialect: dialect) {
        case .success(let sql):
            openSQLInNewTab(sql, status: L(.browseSheetBrowsing), execute: true, source: DatabaseObjectRef(schema: object.schema, name: object.name))
        case .failure(let error):
            errorMessage = L(.browseSheetRefused, error.identifier)
        }
    }

    /// 统计行数（FR-DATA-02）：`count(*)` 带上同一份 WHERE，结果进新页签并立刻执行。
    func countRows(_ object: DatabaseObject, filter: RowBrowsingQuery.Filter) {
        guard let configuration = selectedConnection else {
            errorMessage = L(.stateSelectConnectionFirst)
            return
        }
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        switch RowBrowsingQuery.count(table: object.name, schema: object.schema, filter: filter, dialect: dialect) {
        case .success(let sql):
            openSQLInNewTab(sql, status: L(.browseSheetCounting), execute: true)
        case .failure(let error):
            errorMessage = L(.browseSheetRefused, error.identifier)
        }
    }

    /// 例行候选面板（FR-AI-14 的界面入口）。
    @Published var isRoutineCandidatesPresented = false

    /// 最近一次评估结果（`nil` = 还没算过）。
    @Published private(set) var routineReport: RoutineCandidate.Report?

    /// 重算例行候选。
    ///
    /// 与索引重建同一套目录解析（`openQueriesDirectory`），决定文件与 `memory` 子命令共用 ——
    /// 界面里否决掉的东西，CLI 再查也不会冒出来（同一份 `memory-decisions.json`）。
    func refreshRoutineCandidates() async {
        guard let opened = try? await openQueriesDirectory() else {
            routineReport = nil
            return
        }
        defer { opened.grant?.stopAccessing() }
        let directory = opened.url
        let loaded = MemoryDecisionsStore.load(from: directory)
        let index = await Task.detached(priority: .utility) {
            QueryMemory.buildIndex(directory: directory)
        }.value
        // 顺带把索引缓存放进 `queryMemoryIndex`：面板的「记忆」页签读的是它 ——
        // 否则同一份归档要在同一个面板里被解析两遍，而且两处可能显示不同的快照。
        queryMemoryIndex = index
        routineReport = RoutineCandidate.evaluate(index: index, decisions: loaded.decisions)
        for warning in loaded.warnings { statusMessage = L(.routineCandidatesHint) + "（\(warning)）" }
    }

    /// 否决一条候选：**只写人工决定**，不动归档（归档是事实源，决定是人的选择）。
    func vetoRoutineCandidate(fingerprint: String) async {
        guard let opened = try? await openQueriesDirectory() else { return }
        defer { opened.grant?.stopAccessing() }
        var loaded = MemoryDecisionsStore.load(from: opened.url)
        loaded.decisions.veto(fingerprint: fingerprint)
        do {
            try MemoryDecisionsStore.save(loaded.decisions, to: opened.url)
            await refreshRoutineCandidates()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 把候选模板放进新页签（**不自动执行** —— 它是"建议"，跑不跑由人决定）。
    func insertRoutineTemplate(_ template: String) {
        openSQLInNewTab(template)
        isRoutineCandidatesPresented = false
    }

    // MARK: - 记忆治理（FR-AI-15 的界面入口，住在例行候选面板的「记忆」页签里）

    /// 「本次执行不记录」（FR-AI-15）：**会话级**开关。
    ///
    /// 放在 AppState 而不是视图里，因为它的效果必须真的落到归档收口点上 ——
    /// 一个只改界面文字的开关等于骗人。
    @Published var suppressesCurrentExecutionRecording = false

    /// 归档策略：**判定交给 Core 的 `MemoryRecordingPolicy`**，
    /// 界面与 `archiveExecutedSQL` 读的是同一个结论（不在这里另写一遍 `if`）。
    var memoryRecordingPolicy: MemoryRecordingPolicy {
        MemoryRecordingPolicy(
            isArchiveEnabled: isSQLArchiveEnabled,
            suppressesCurrentRun: suppressesCurrentExecutionRecording
        )
    }

    /// 记忆治理的一次性提示 / 错误（与其它面板一致：就地显示，不弹打断）。
    @Published var memoryGovernanceMessage: String?
    @Published var memoryGovernanceError: String?

    /// 删除一条记忆：作用在**归档**上（记忆只是派生索引），随后重建索引与候选。
    ///
    /// 复用 `openQueriesDirectory` 的目录解析 —— 与写入归档、重建索引同一处，
    /// 免得"界面删的是 A 目录、记忆读的是 B 目录"。
    func deleteMemory(fingerprint: String) async {
        guard let opened = try? await openQueriesDirectory() else {
            memoryGovernanceError = L(.memoryGovernanceDeleteFailed, L(.archiveDirectoryNotAuthorized))
            return
        }
        defer { opened.grant?.stopAccessing() }
        let directory = opened.url
        do {
            let report = try await Task.detached(priority: .utility) {
                try SQLArchiveEditor.removeEntries(matchingFingerprint: fingerprint, in: directory)
            }.value
            memoryGovernanceError = nil
            memoryGovernanceMessage = L(
                .memoryGovernanceDeleted,
                report.removedEntryCount,
                report.changedFiles.count
            )
            await refreshQueryMemoryIndex()
            await refreshRoutineCandidates()
        } catch {
            memoryGovernanceError = L(.memoryGovernanceDeleteFailed, ErrorPresenter.message(for: error))
        }
    }

    /// 整层清空（环境层 = 归档）。**调用方必须先拿到显式确认** —— Core 的纪律是
    /// 「清空需确认」，这里只负责执行，不负责替用户点头。
    func clearMemoryEnvironmentLayer() async {
        guard let opened = try? await openQueriesDirectory() else {
            memoryGovernanceError = L(.memoryGovernanceClearFailed, L(.archiveDirectoryNotAuthorized))
            return
        }
        defer { opened.grant?.stopAccessing() }
        let directory = opened.url
        do {
            let report = try await Task.detached(priority: .utility) {
                try SQLArchiveEditor.removeAll(in: directory)
            }.value
            memoryGovernanceError = nil
            memoryGovernanceMessage = L(
                .memoryGovernanceCleared,
                report.removedEntryCount,
                report.changedFiles.count
            )
            await refreshQueryMemoryIndex()
            await refreshRoutineCandidates()
        } catch {
            memoryGovernanceError = L(.memoryGovernanceClearFailed, ErrorPresenter.message(for: error))
        }
    }

    /// 对象搜索结果 → 「浏览数据」：在新页签里打开前 N 行（FR-META-12 的界面动作）。
    ///
    /// 复用 `RowBrowsingQuery`，不在这里手拼 `SELECT * FROM …` ——
    /// 手拼就会漏掉方言的标识符引号（限定名里的点、大小写都要靠它）。
    func browseSearchHit(schema: String?, name: String) {
        guard let configuration = selectedConnection else {
            errorMessage = L(.stateSelectConnectionFirst)
            return
        }
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        let filter = RowBrowsingQuery.Filter()
        switch RowBrowsingQuery.browse(table: name, schema: schema, filter: filter, dialect: dialect) {
        case .success(let sql):
            // `execute: true`：语句完全由搜索结果决定（没有用户输入），
            // 而且用户点这个按钮就是想看数据 —— 只往编辑器里塞一句等于没反应。
            openSQLInNewTab(sql, status: L(.browseSheetBrowsing), execute: true, source: DatabaseObjectRef(schema: schema, name: name))
        case .failure(let error):
            errorMessage = L(.browseSheetRefused, error.identifier)
        }
    }

    /// 当前是否允许外发，以及原因（界面与后续 AI 功能共用这一处判定）。
    var agentOutboundDecision: AgentOutboundDecision {
        AgentGate.decide(configuration: agentConfiguration, apiKey: agentAPIKey)
    }

    // MARK: - 数据任务（FR-AI-05 / FR-AI-06 / FR-AI-08）

    /// 当前连接对应的方言（数据任务的 SQL 编译与护栏判定都用它）。
    var dataTaskDialect: any SQLDialect {
        SQLDialectFactory.make(for: selectedConnection?.dbType ?? .postgresql)
    }

    // MARK: 读取与保存

    /// 读取任务定义、执行历史与已授权目录（启动 / 打开面板 / 刷新时调用）。
    func loadDataTasks() async {
        do {
            dataTasks = try await dataTaskStore.tasks()
        } catch {
            dataTasks = []
            dataTaskError = L(.dataTaskLoadFailed, ErrorPresenter.message(for: error))
        }
        await reloadDataTaskRuns()
        storedDirectoryBookmarks = (try? await directoryBookmarkStore.all()) ?? []
    }

    /// 只刷新执行历史（顺带重建「上次成功执行时刻」）。
    func reloadDataTaskRuns() async {
        do {
            dataTaskRuns = try await dataTaskStore.runs()
        } catch {
            dataTaskRuns = []
            dataTaskError = L(.dataTaskLoadFailed, ErrorPresenter.message(for: error))
        }

        var lastSuccess: [UUID: Date] = [:]
        for record in dataTaskRuns where record.status == .succeeded {
            if let previous = lastSuccess[record.taskID], previous >= record.startedAt { continue }
            lastSuccess[record.taskID] = record.startedAt
        }
        dataTaskLastSuccessfulRuns = lastSuccess
    }

    /// 保存任务定义；**定义不合法就不写盘**（界面同时会禁用保存按钮）。
    @discardableResult
    func saveDataTask(_ task: DataTaskDefinition) async -> Bool {
        guard task.isValid else {
            dataTaskError = L(.dataTaskSaveBlocked)
            return false
        }
        return await persistDataTask(task, successMessage: L(.dataTaskSaved, task.name))
    }

    /// 删除任务定义（不动执行历史 —— 历史是审计材料，删了就无法追溯）。
    @discardableResult
    func deleteDataTask(id: UUID) async -> Bool {
        let name = dataTasks.first { $0.id == id }?.name ?? ""
        do {
            try await dataTaskStore.delete(id: id)
            dataTasks.removeAll { $0.id == id }
            dataTaskDecisions[id] = nil
            dataTaskError = nil
            dataTaskMessage = L(.dataTaskDeleted, name)
            return true
        } catch {
            dataTaskError = L(.dataTaskDeleteFailed, ErrorPresenter.message(for: error))
            return false
        }
    }

    /// 停用 / 恢复任务（FR-AI-06 的「可暂停 / 停用」）。
    func setDataTaskEnabled(_ isEnabled: Bool, id: UUID) async {
        guard var task = dataTasks.first(where: { $0.id == id }) else { return }
        task.isEnabled = isEnabled
        _ = await persistDataTask(task, successMessage: nil)
    }

    /// 上次成功执行时刻（面板用它算「下次执行」）。
    func dataTaskLastSuccessfulRun(for taskID: UUID) -> Date? {
        dataTaskLastSuccessfulRuns[taskID]
    }

    /// 某个任务当前的调度判定；没 tick 过时给一个即时判定（不写状态）。
    func dataTaskDecision(for task: DataTaskDefinition, now: Date = Date()) -> ScheduleDecision {
        dataTaskDecisions[task.id]
            ?? TaskScheduler.decision(
                for: task,
                now: now,
                lastRun: dataTaskLastSuccessfulRuns[task.id],
                grace: Self.dataTaskGrace
            )
    }

    // MARK: 版本历史与回滚（FR-AI-11 的界面入口）

    /// 版本记录所在目录：与 `DataTaskStore` 的 `data-tasks.json` **同一个目录**
    /// （Core 的 `DataTaskStore.save` 就是往那里记版本）。
    ///
    /// 目录来源交给 store（读 `tasksFileLocation()`），**不自己拼路径** ——
    /// 拼错了症状是"界面里历史为空，CLI 里却查得到"，很难查。
    private func specVersionStore() async -> SpecVersionStore {
        let directory = (await dataTaskStore.tasksFileLocation()).deletingLastPathComponent()
        return SpecVersionStore(directoryURL: directory)
    }

    /// 读某个任务的全部版本（按版本号升序）。解析放后台：一天几百条保存时不至于卡住界面。
    func dataTaskVersions(taskID: UUID) async -> [SpecVersion] {
        let store = await specVersionStore()
        return await Task.detached(priority: .utility) {
            store.versions(taskID: taskID)
        }.value
    }

    /// 回滚到某个版本：**把那份旧内容再存一次**（Core 的"只追加"语义），
    /// 于是"曾经回滚过"本身也留在历史里。走 `persistDataTask` 这条唯一收口点，
    /// 与 CLI `specs --rollback` 落的是同一份历史。
    @discardableResult
    func rollbackDataTask(taskID: UUID, to number: Int) async -> DataTaskDefinition? {
        let store = await specVersionStore()
        guard let version = store.version(taskID: taskID, number: number) else {
            dataTaskError = L(.dataTaskVersionsRollbackFailed, "v\(number)")
            return nil
        }
        let ok = await persistDataTask(
            version.definition,
            successMessage: L(.dataTaskVersionsRolledBack, number),
            // 版本自己解释自己：这一条在历史里会写明「回滚到 vN」。
            note: L(.dataTaskVersionsRollbackNote, number)
        )
        guard ok else { return nil }
        return dataTasks.first { $0.id == version.definition.id }
    }

    /// 写盘并把内存里的那份同步成「落盘后的版本」（`updatedAt` 会变）。
    ///
    /// - Parameter note: 这次保存的原因（写进版本历史）。回滚会带「回滚到 vN」——
    ///   否则事后只看内容分不出"用户改的"与"回滚来的"。
    @discardableResult
    private func persistDataTask(
        _ task: DataTaskDefinition,
        successMessage: String?,
        note: String? = nil
    ) async -> Bool {
        do {
            let stored = try await dataTaskStore.save(task, note: note)
            if let index = dataTasks.firstIndex(where: { $0.id == stored.id }) {
                dataTasks[index] = stored
            } else {
                dataTasks.append(stored)
            }
            dataTaskError = nil
            if let successMessage { dataTaskMessage = successMessage }
            return true
        } catch {
            dataTaskError = L(.dataTaskSaveFailed, ErrorPresenter.message(for: error))
            return false
        }
    }

    // MARK: 目录授权（FR-AI-08）

    /// 让用户选一个目录并授权（`NSOpenPanel` → security-scoped bookmark）。
    ///
    /// **用户取消不是错误**：返回 `nil`，面板什么都不做。
    func chooseDataTaskExportDirectory(
        displayName: String,
        format: DataTaskDefinition.ExportSettings.Format,
        fileNameTemplate: String?
    ) async -> DataTaskDefinition.ExportSettings? {
        dataTaskError = nil
        do {
            guard let settings = try MacDirectoryAccess.requestExportSettings(
                prompt: L(.dataTaskChooseDirectory),
                format: format,
                fileNameTemplate: fileNameTemplate,
                picker: dataTaskDirectoryPicker
            ) else { return nil }

            await rememberDirectoryBookmark(from: settings, displayName: displayName)
            return settings
        } catch {
            // 未授权 / 创建书签失败：给可读原因与补救建议，绝不静默。
            dataTaskError = ErrorPresenter.message(for: error)
            return nil
        }
    }

    /// 用已经授权过的目录作为任务的导出目录（不重新弹面板）。
    func dataTaskExportSettings(
        using bookmark: DirectoryBookmark,
        format: DataTaskDefinition.ExportSettings.Format,
        fileNameTemplate: String?
    ) -> DataTaskDefinition.ExportSettings {
        DataTaskDefinition.ExportSettings(
            format: format,
            directoryBookmark: bookmark.bookmarkData,
            fileNameTemplate: fileNameTemplate
        )
    }

    /// 当前授权状态；`nil` = 任务还没设导出目录。
    func dataTaskDirectoryStatus(
        _ settings: DataTaskDefinition.ExportSettings?
    ) -> DirectoryAccessStatus? {
        guard let settings, let bookmark = MacDirectoryAccess.bookmark(from: settings) else {
            return nil
        }
        return MacDirectoryAccess.status(for: bookmark)
    }

    /// 验证授权目录真的可写：把「任务定义 + 试运行预览」写成一份说明文件。
    ///
    /// 刻意**不碰数据库**：这条路径只验证「书签 → 解析 → 写文件」，因此在没有可达实例时
    /// 也能证明 FR-AI-08 的接线是通的。
    @discardableResult
    func verifyDataTaskExportDirectory(_ task: DataTaskDefinition) async -> Bool {
        guard let settings = task.output,
              let bookmark = MacDirectoryAccess.bookmark(from: settings)
        else {
            dataTaskError = DataTaskRunError.missingExportSettings.errorDescription
            return false
        }

        do {
            let grant = try MacDirectoryAccess.open(bookmark)
            defer { grant.stopAccessing() }
            let url = try DataTaskRunner.exportPreviewReport(
                for: task,
                preview: task.dryRun(dialect: dataTaskDialect),
                grant: grant
            )
            dataTaskError = nil
            dataTaskMessage = L(.dataTaskExportVerifySucceeded, url.lastPathComponent)
            return true
        } catch {
            dataTaskError = ErrorPresenter.message(for: error)
            return false
        }
    }

    /// 把新授权的书签记进 `directory-bookmarks.json`（同一目录就地更新，不重复堆积）。
    private func rememberDirectoryBookmark(
        from settings: DataTaskDefinition.ExportSettings,
        displayName: String
    ) async {
        guard var bookmark = MacDirectoryAccess.bookmark(from: settings, displayName: displayName) else {
            return
        }
        if case .granted(let path, _) = MacDirectoryAccess.status(for: bookmark) {
            bookmark.lastKnownPath = path
        }
        if let existing = storedDirectoryBookmarks.first(where: {
            $0.lastKnownPath != nil && $0.lastKnownPath == bookmark.lastKnownPath
        }) {
            bookmark.id = existing.id
        }
        try? await directoryBookmarkStore.save(bookmark)
        storedDirectoryBookmarks = (try? await directoryBookmarkStore.all()) ?? storedDirectoryBookmarks
    }

    // MARK: 调度 tick 与执行（FR-AI-06）

    /// 启动 App 侧调度 tick（幂等；在窗口出现时调用一次）。
    ///
    /// `TaskScheduler` 只做纯时间计算，这里负责「隔一会儿问一次」并把到点的任务送进审批流程。
    func startDataTaskTicker() {
        guard dataTaskTicker == nil else { return }
        dataTaskTicker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tickDataTasks()
                try? await Task.sleep(for: AppState.dataTaskTickInterval)
            }
        }
    }

    func stopDataTaskTicker() {
        dataTaskTicker?.cancel()
        dataTaskTicker = nil
    }

    /// 走一次调度判定：刷新界面状态，并把**到点**的任务按计划执行。
    ///
    /// 错过窗口（超过宽限）**不自动补跑**，只把 `.missed` 摆到界面上等用户确认。
    func tickDataTasks() async {
        guard !dataTasks.isEmpty else { return }
        let now = Date()

        for task in dataTasks {
            let lastRun = dataTaskLastSuccessfulRuns[task.id]
            let decision = TaskScheduler.decision(
                for: task,
                now: now,
                lastRun: lastRun,
                grace: Self.dataTaskGrace
            )
            dataTaskDecisions[task.id] = decision

            guard case .due(let plannedAt) = decision else { continue }
            // 同一个计划时刻只跑一次：审批被拒 / 执行失败都不会让它每 30 秒重试一遍。
            if let attempted = dataTaskLastAttempts[task.id], attempted >= plannedAt { continue }
            guard selectedConnection != nil else { continue }

            // 到点的写语句要人工批准，而审批单需要宿主视图：面板没开时先把它带到前台，
            // 下一个 tick（30 秒后，宽限 5 分钟足够）再提交，让审批单在面板里弹出来。
            // 否则「提交了但用户看不到任何窗口」，等于把审批悬在半空。
            guard isDataTaskPresented else {
                isDataTaskPresented = true
                statusMessage = L(.dataTaskDueNotice)
                continue
            }
            // 已经有一张审批单摆在界面上时先不叠加：同一个时刻只会提交一次（`dataTaskLastAttempts`），
            // 等用户处理完这张，下一个 tick 再推进其他到点任务。
            guard agentApprovalRequest == nil else { continue }

            dataTaskLastAttempts[task.id] = plannedAt
            await requestDataTaskRun(task, plannedAt: plannedAt, startedAt: now)
        }
    }

    /// 手动执行（「现在执行…」，包括错过窗口后用户确认执行）。
    func runDataTaskNow(_ task: DataTaskDefinition, plannedAt: Date? = nil) async {
        dataTaskMessage = nil
        await requestDataTaskRun(task, plannedAt: plannedAt, startedAt: Date())
    }

    /// 提交一次任务执行：**写语句先进 `AgentActionGate`**（FR-AI-09 的同一套审批与审计），
    /// 批准之前不会碰数据库。
    private func requestDataTaskRun(
        _ task: DataTaskDefinition,
        plannedAt: Date?,
        startedAt: Date
    ) async {
        guard selectedConnection != nil else {
            dataTaskError = L(.dataTaskRunNotConnected)
            return
        }
        guard task.isValid else {
            dataTaskError = L(.dataTaskRunFailed, ErrorPresenter.message(for: DataTaskRunError.invalidDefinition(task.issues)))
            return
        }

        let sql: String
        do {
            sql = try DataTaskRunner.writeStatementText(for: task, dialect: dataTaskDialect)
        } catch {
            dataTaskError = ErrorPresenter.message(for: error)
            return
        }

        let submission = await submitAgentAction(sql)
        let pending = PendingDataTaskRun(
            task: task,
            plannedAt: plannedAt,
            startedAt: startedAt,
            writeSQL: sql
        )

        switch submission {
        case .denied:
            // 只读模式 / 策略拒绝：**没有审批单**，但仍留一条失败记录（不静默）。
            let reason = submission.message
            dataTaskError = L(.dataTaskRunDenied, reason)
            await recordDataTaskRun(
                task: task,
                plannedAt: plannedAt,
                startedAt: startedAt,
                status: .failed,
                rowsWritten: nil,
                message: reason
            )

        case .awaitingApproval(let approval):
            // 审批单由 `submitAgentAction` 弹出（面板上挂着 `AgentApprovalSheet`）。
            pendingDataTaskRuns[approval.id] = pending
            dataTaskError = nil
            dataTaskMessage = L(.dataTaskRunPending)

        case .approved:
            // 白名单等免审批出口：直接执行。
            await executeApprovedDataTask(pending)
        }
    }

    /// 执行一条已获批的任务写入，随后（若配了导出目录）把产物写进授权目录并记执行历史。
    private func executeApprovedDataTask(_ pending: PendingDataTaskRun) async {
        do {
            let rowsWritten = try await executeApprovedAgentAction(pending.writeSQL)
            await finishApprovedDataTaskRun(pending, rowsWritten: rowsWritten)
        } catch {
            await failDataTaskRun(pending, message: ErrorPresenter.message(for: error))
        }
    }

    /// 读源表 → 按任务导出设置写进**授权目录**（目录来自书签解析，不硬编码）。
    private func exportDataTaskArtifact(_ task: DataTaskDefinition) async throws -> String {
        guard let settings = task.output,
              let bookmark = MacDirectoryAccess.bookmark(from: settings)
        else { throw DataTaskRunError.missingExportSettings }
        guard let configuration = selectedConnection else { throw AppError.notConnected }

        let grant = try MacDirectoryAccess.open(bookmark)
        defer { grant.stopAccessing() }

        let service = try await ensureService(
            for: configuration,
            database: queryDatabase(for: configuration)
        )
        let result = try await DataTaskRunner.read(
            task,
            on: service,
            dialect: dataTaskDialect
        )
        let url = try DataTaskRunner.exportArtifact(result, for: task, grant: grant)
        return url.lastPathComponent
    }

    private func failDataTaskRun(_ pending: PendingDataTaskRun, message: String) async {
        dataTaskError = L(.dataTaskRunFailed, message)
        await recordDataTaskRun(
            task: pending.task,
            plannedAt: pending.plannedAt,
            startedAt: pending.startedAt,
            status: .failed,
            rowsWritten: nil,
            message: message
        )
    }

    /// 人工在审批单上拒绝的那一次执行（`FR-STD-DB-TASK-002` 判据③）。
    ///
    /// 与「跳过」分开记：跳过是「没到点 / 错过了、没人决定」，拒绝是**有人明确说不**。
    /// 两者混成一条，历史里就读不出「这批高危语句是被否决掉的」。
    private func rejectDataTaskRun(_ pending: PendingDataTaskRun, message: String) async {
        await recordDataTaskRun(
            task: pending.task,
            plannedAt: pending.plannedAt,
            startedAt: pending.startedAt,
            status: .rejected,
            rowsWritten: nil,
            message: message
        )
    }

    /// 追加一条执行历史（先落内存让面板立刻看得见，再写 `task-runs.jsonl`）。
    ///
    /// 写盘失败必须说出来：执行历史是「有执行记录与失败记录」的依据，静默丢掉等于没做。
    private func recordDataTaskRun(
        task: DataTaskDefinition,
        plannedAt: Date?,
        startedAt: Date,
        status: TaskRunRecord.Status,
        rowsWritten: Int?,
        message: String?
    ) async {
        let record = TaskRunRecord(
            taskID: task.id,
            plannedAt: plannedAt,
            startedAt: startedAt,
            finishedAt: Date(),
            status: status,
            rowsWritten: rowsWritten,
            message: message
        )
        dataTaskRuns.append(record)
        if status == .succeeded {
            dataTaskLastSuccessfulRuns[task.id] = startedAt
        }
        do {
            try await dataTaskStore.appendRun(record)
        } catch {
            dataTaskError = L(.dataTaskSaveFailed, ErrorPresenter.message(for: error))
        }
    }

    // MARK: - 定时 agent（FR-AI-27）：到点起会话、错过只提示、停用不排期

    /// 定时条目（盘上是唯一事实源，这里是面板这一份）。
    @Published var agentSchedules: [AgentScheduleEntry] = []
    /// 执行历史（⑤ 的落盘读回）。
    @Published var agentScheduleRuns: [AgentScheduleRunRecord] = []
    /// 每条目最近一次的判定档（面板与判据都读它，不各算一份）。
    @Published var agentScheduleDecisions: [UUID: ScheduleDecision] = [:]
    /// 有错过窗口的那一条（② 的界面半：默认不补跑，面板据此摆「是否现在执行」）。
    @Published var agentScheduleMissedEntryID: UUID?
    @Published var isAgentSchedulePresented = false

    private let agentScheduleStore = AgentScheduleStore.shared
    private var agentScheduleTicker: Task<Void, Never>?
    /// 同一个计划时刻只跑一次（与数据任务同一口径：审批被拒 / 起不来都不许每 30 秒重试一遍）。
    private var agentScheduleLastAttempts: [UUID: Date] = [:]

    /// 宽限 5 分钟（打开客户端时「刚过期一会儿」仍算到点，真错过的才提示）、节拍 30 秒 —— 与数据任务同口径。
    static let agentScheduleGrace: TimeInterval = 300
    static let agentScheduleTickInterval: Duration = .seconds(30)

    /// 宿主注入：把「该起一次会话」真起起来（打开对话页签 → 填提示词 → 发）。
    /// 返回 `false` = 起不来（照实记一条失败，不静默）。**不在这里判断能不能执行** ——
    /// 写 / 执行类动作仍走既有审批闸门（`FR-AI-09` / `FR-AI-23`），定时不构成授权。
    var agentScheduleRunner: ((AgentScheduleEntry, Date) async -> Bool)?

    /// 启动 App 侧调度 tick（幂等；窗口出现时调一次）。判定是纯时间计算（Core），这里只负责「隔一会儿问一次」。
    func startAgentScheduleTicker() {
        guard agentScheduleTicker == nil else { return }
        agentScheduleTicker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tickAgentSchedules()
                try? await Task.sleep(for: AppState.agentScheduleTickInterval)
            }
        }
    }

    func stopAgentScheduleTicker() {
        agentScheduleTicker?.cancel()
        agentScheduleTicker = nil
    }

    /// 读条目与历史（打开面板 / 起 tick 前各一次）。
    func loadAgentSchedules() async {
        do {
            agentSchedules = try await agentScheduleStore.entries()
            agentScheduleRuns = try await agentScheduleStore.runs()
        } catch {
            agentSchedules = []
            agentScheduleRuns = []
        }
        refreshAgentScheduleDecisions()
    }

    func saveAgentSchedule(_ entry: AgentScheduleEntry) async {
        _ = try? await agentScheduleStore.save(entry)
        await loadAgentSchedules()
    }

    func setAgentScheduleEnabled(_ isEnabled: Bool, id: UUID) async {
        _ = try? await agentScheduleStore.setEnabled(isEnabled, id: id)
        await loadAgentSchedules()
    }

    func deleteAgentSchedule(id: UUID) async {
        try? await agentScheduleStore.delete(id: id)
        if agentScheduleMissedEntryID == id { agentScheduleMissedEntryID = nil }
        await loadAgentSchedules()
    }

    /// 最近一次**成功**触发的时刻 —— 判定与「下次执行」都用它（不另存一份）。
    func agentScheduleLastSuccessfulRun(for entryID: UUID) -> Date? {
        AgentScheduleLedger(records: agentScheduleRuns).lastSuccessfulRun(for: entryID)
    }

    /// 最近一次留痕（列表行那一句「最近一跑」用）。
    func agentScheduleLatestRun(for entryID: UUID) -> AgentScheduleRunRecord? {
        agentScheduleRuns.last { $0.entryID == entryID }
    }

    /// 某条目当前的判定；没 tick 过时给一个即时判定（不写状态）。
    func agentScheduleDecision(for entry: AgentScheduleEntry, now: Date = Date()) -> ScheduleDecision {
        agentScheduleDecisions[entry.id]
            ?? AgentSchedulePlanner.decision(
                for: entry,
                now: now,
                lastRun: agentScheduleLastSuccessfulRun(for: entry.id),
                grace: Self.agentScheduleGrace
            )
    }

    private func refreshAgentScheduleDecisions() {
        let now = Date()
        var decisions: [UUID: ScheduleDecision] = [:]
        for entry in agentSchedules {
            decisions[entry.id] = AgentSchedulePlanner.decision(
                for: entry,
                now: now,
                lastRun: agentScheduleLastSuccessfulRun(for: entry.id),
                grace: Self.agentScheduleGrace
            )
        }
        agentScheduleDecisions = decisions
        agentScheduleMissedEntryID = agentSchedules.first { isMissed(decisions[$0.id]) }?.id
    }

    /// 用户确认「现在就执行那一次错过的」（②：只有这里能让错过的那一次跑起来；留痕记的仍是**原**计划时刻）。
    func runMissedAgentScheduleNow() async {
        guard let entryID = agentScheduleMissedEntryID,
              let entry = agentSchedules.first(where: { $0.id == entryID }) else { return }
        let lastRun = agentScheduleLastSuccessfulRun(for: entryID)
        let plan = AgentSchedulePlanner.plan(
            for: entry,
            now: Date(),
            lastRun: lastRun,
            confirmedMissed: true,
            grace: Self.agentScheduleGrace
        )
        if case .missed(let plannedAt, _) = AgentSchedulePlanner.decision(
            for: entry, now: Date(), lastRun: lastRun, grace: Self.agentScheduleGrace
        ) {
            agentScheduleLastAttempts[entryID] = plannedAt
        }
        await applyAgentSchedulePlan(plan, entry: entry)
        agentScheduleMissedEntryID = nil
    }

    func dismissAgentScheduleMissed() {
        // 只把提示收起来（同一计划时刻仍不补跑：`agentScheduleLastAttempts` 已经把它钉住）。
        if let entryID = agentScheduleMissedEntryID {
            if let decision = agentScheduleDecisions[entryID], case .missed(let plannedAt, _) = decision {
                agentScheduleLastAttempts[entryID] = plannedAt
            }
        }
        agentScheduleMissedEntryID = nil
    }

    /// 判定是不是「错过」这一档（`ScheduleDecision` 只给了 `isDue`，这里不往 Core 件加东西）。
    private func isMissed(_ decision: ScheduleDecision?) -> Bool {
        guard let decision else { return false }
        if case .missed = decision { return true }
        return false
    }

    /// 走一次调度判定：到点的起会话、错过的摆提示（**默认不补跑**）、停用与未到的一律不动（④）。
    func tickAgentSchedules() async {
        guard !agentSchedules.isEmpty else { return }
        let now = Date()
        for entry in agentSchedules {
            let lastRun = agentScheduleLastSuccessfulRun(for: entry.id)
            let decision = AgentSchedulePlanner.decision(
                for: entry, now: now, lastRun: lastRun, grace: Self.agentScheduleGrace
            )
            agentScheduleDecisions[entry.id] = decision
            let plan = AgentSchedulePlanner.plan(
                for: entry, now: now, lastRun: lastRun, grace: Self.agentScheduleGrace
            )
            await applyAgentSchedulePlan(plan, entry: entry)
        }
        agentScheduleMissedEntryID = agentSchedules.first { entry in
            isMissed(agentScheduleDecisions[entry.id])
                && agentScheduleLastAttempts[entry.id] == nil
        }?.id
    }

    /// 把一份计划落到盘上（留痕）并（到点 / 已确认错过时）起一次会话。
    private func applyAgentSchedulePlan(_ plan: AgentScheduleRunPlan, entry: AgentScheduleEntry) async {
        switch plan {
        case .idle(let reason):
            // 错过窗口：记一条 **skipped** —— 它正是「没补跑」的证据（同一计划时刻只记一次）。
            guard case .missed(let plannedAt, _) = reason else { return }
            if let attempted = agentScheduleLastAttempts[entry.id], attempted >= plannedAt { return }
            agentScheduleLastAttempts[entry.id] = plannedAt
            guard let record = plan.record(entryID: entry.id, startedAt: Date(),
                                           detail: L(.agentScheduleRunNotStarted)) else { return }
            try? await agentScheduleStore.appendRun(record)

        case .run(let plannedAt, _):
            if let attempted = agentScheduleLastAttempts[entry.id], attempted >= plannedAt { return }
            agentScheduleLastAttempts[entry.id] = plannedAt
            guard let record = plan.record(entryID: entry.id, startedAt: Date()) else { return }
            try? await agentScheduleStore.appendRun(record)
            let started = await agentScheduleRunner?(entry, plannedAt) ?? false
            _ = try? await agentScheduleStore.finishRun(
                id: record.id,
                status: started ? .succeeded : .failed,
                at: Date(),
                detail: started ? L(.agentScheduleRunStarted) : L(.agentScheduleRunNotStarted)
            )
        }
        agentScheduleRuns = (try? await agentScheduleStore.runs()) ?? agentScheduleRuns
    }

    // MARK: - 执行计划（FR-DIAG-01）

    /// 对当前页签的语句跑 `EXPLAIN` 并解析成计划树。
    ///
    /// 只分析**第一条**语句（多条时给出提示）；`ANALYZE` 打开时会真正执行该语句 ——
    /// 界面必须显著提示，这里不做额外确认，因为用户是显式打开的开关。
    func runExecutionPlan(for tabID: UUID) async {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == tabID }) else { return }

        guard let configuration = selectedConnection else {
            executionPlan = nil
            executionPlanError = L(.stateSelectConnectionFirst)
            return
        }

        let sql = tabs[tabIndex].sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else {
            executionPlan = nil
            executionPlanError = L(.stateSQLEmpty)
            return
        }

        let statements = StatementSplitter(databaseType: configuration.dbType)
            .split(sql)
            .map { $0.sql.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = statements.first else {
            executionPlan = nil
            executionPlanError = L(.stateSQLEmpty)
            return
        }

        let firstKeyword = firstKeyword(in: first)
        let explainable = ["SELECT", "INSERT", "UPDATE", "DELETE", "WITH", "VALUES", "TABLE"]
        guard explainable.contains(firstKeyword) else {
            executionPlan = nil
            executionPlanError = L(.planUnsupported)
            return
        }

        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        let explainSQL = SQLGenerator.explain(
            sql: first,
            analyze: planRunAnalyze,
            buffers: planIncludeBuffers,
            formatJSON: planUseJSON,
            dialect: dialect
        )

        executionPlanIsLoading = true
        executionPlanError = statements.count > 1 ? L(.planMultipleStatements, statements.count) : nil
        defer { executionPlanIsLoading = false }

        do {
            let service = try await ensureService(
                for: configuration,
                database: queryDatabase(for: configuration)
            )
            let result = try await runSingleQuery(explainSQL, on: service)
            // 文本格式是多行、每行一列；JSON 格式是一行一列，两种都按「逐行首列拼接」处理。
            let raw = result.rows.compactMap { $0.first ?? nil }.joined(separator: "\n")
            executionPlan = ExplainPlanParser.parse(raw)
        } catch {
            executionPlan = nil
            executionPlanError = L(.planFailed, ErrorPresenter.message(for: error))
        }
    }

    // MARK: - 对象树节点动作（FR-META-14 / FR-DATA-01 / FR-META-13）

    /// 取表 / 视图的列定义（含可空性）；供生成 DDL 与模板使用。
    ///
    /// 单独查一次而不是复用节点树里的列节点：树里的列信息只有类型名，
    /// 拿不到 `is_nullable` —— 少了它，导出的建表语句会悄悄丢掉 NOT NULL。
    func columnSpecs(for object: DatabaseObject) async throws -> [ColumnMeta] {
        guard let configuration = selectedConnection else {
            throw AppError.notConnected
        }
        let database = object.database ?? currentDatabaseName(for: configuration)
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        let schema = object.schema ?? (configuration.dbType == .postgresql ? "public" : nil)

        let service = try await ensureService(for: configuration, database: database)
        let result = try await runSingleQuery(
            dialect.listColumnsQuery(table: object.name, schema: schema),
            on: service
        )
        return ColumnSpecParser.columns(from: result)
    }

    /// 执行一个对象树动作：生成 SQL 进新页签，或把文本复制到剪贴板。
    ///
    /// **一律不自动执行**；破坏性动作（清空 / 删除）也只是把语句写进编辑器，
    /// 真正运行时还会被 Safe Mode（FR-EXEC-16）再拦一次。
    func performTreeAction(_ action: ObjectTreeAction, on object: DatabaseObject) async {
        guard let configuration = selectedConnection else {
            errorMessage = L(.stateSelectConnectionFirst)
            return
        }
        let dialect = SQLDialectFactory.make(for: configuration.dbType)

        // 需要列的动作：按需加载；加载失败就退回「无列」由 Core 判定（生成 SELECT 仍可用，
        // 生成 INSERT / DDL 会明确失败并提示，而不是猜列）。
        // 视图 / 函数的 DDL 不在"列信息"里 —— 它们的定义体只存在于服务端元数据中，
        // 必须查询取回（FR-META-13）；表仍走「读列 + 拼装」的老路。
        if action == .viewDDL, object.kind == .view || object.kind == .function {
            await openObjectDDL(for: object, dialect: dialect, configuration: configuration)
            return
        }

        var columns: [ColumnMeta] = []
        if action == .selectTemplate || action == .insertTemplate || action == .viewDDL {
            columns = (try? await columnSpecs(for: object)) ?? []
        }
        let target = ObjectTreeTarget(object: object, columns: columns)

        if let text = ObjectTreeActions.copiedText(for: action, target: target, dialect: dialect) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            statusMessage = L(.objectTreeCopied, text)
            return
        }

        guard let sql = ObjectTreeActions.sql(for: action, target: target, dialect: dialect) else {
            errorMessage = L(.treeActionUnavailable)
            return
        }
        // 「浏览前 N 行」= 对**这一张表**取前 N 行 ⇒ 页签必须记下来源表：结果格的内联编辑
        // （FR-DATA-04）只认 `QueryTab.sourceTable`，没有它就会拒编辑并说「这个结果来自手写 SQL，
        // 无法确定来源表」（2026-09-29 人工点验第 3 条抓到的真缺陷 —— 同一个动作走面板那条路
        // 是带来源表的，只有右键这一条丢）。
        // 模板类动作（生成 SELECT / INSERT 模板）**不带**来源表：执行 INSERT 的结果不是这张表的
        // 行集，附上来源表反而会让结果格误判成可编辑。
        if action == .browseRows {
            openSQLInNewTab(
                sql,
                status: L(.browseSheetBrowsing),
                source: DatabaseObjectRef(schema: object.schema, name: object.name)
            )
        } else {
            openSQLInNewTab(sql)
        }
    }

    /// 取视图 / 函数的 DDL 并**放进新页签**（不执行）。
    ///
    /// 三条口径：① 方言不支持时给可读提示，不静默失败；② 结果为空时也说清楚
    /// （可能是权限不足 —— 元数据函数对无权限对象返回空而不是报错）；③ 一律只进编辑器，不执行。
    private func openObjectDDL(
        for object: DatabaseObject,
        dialect: any SQLDialect,
        configuration: ConnectionConfig
    ) async {
        let query: ObjectDDLQuery?
        switch object.kind {
        case .view:
            query = ObjectDDL.view(schema: object.schema, name: object.name, dialect: dialect)
        case .function:
            query = ObjectDDL.function(schema: object.schema, name: object.name, dialect: dialect)
        default:
            query = nil
        }

        guard let query else {
            errorMessage = L(.treeDDLUnsupported)
            return
        }

        let database = object.database ?? currentDatabaseName(for: configuration)
        do {
            let service = try await ensureService(for: configuration, database: database)
            let result = try await runSingleQuery(query.sql, on: service)
            let text = ObjectDDL.assemble(
                query,
                columns: result.columns.map(\.name),
                rows: result.rows,
                dialect: dialect
            )
            guard let text else {
                errorMessage = L(.treeDDLEmpty, object.name)
                return
            }
            openSQLInNewTab(text)
            statusMessage = L(.treeDDLReady, object.name)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    // MARK: - 命令面板（FR-EDIT-25）

    @Published var isCommandPalettePresented = false

    /// 标题栏搜索栏的输入（FR-EDIT-37，2026-09-30 需求提出者「标题后面居中可以放一个长长的搜索栏」）。
    ///
    /// 搜索栏**不自己实现一套搜索**：回车把词交给命令面板，面板直接读**这一份**词
    /// （队列 `L-122` ⑤「词只留一份」—— 面板不再自己存一份、也没有「种子」字段）。
    /// 匹配（`CommandPalette.search`）与命令清单（`AppCommandCatalog`）仍是唯一来源。
    @Published var globalSearchQuery = ""

    /// 打开命令面板（`FR-EDIT-25`）。
    ///
    /// **词不在这里带来带去**（队列 `L-122` ⑤「词只留一份」）：面板的查询就是
    /// `globalSearchQuery` 那一份，⌘K 与标题栏搜索栏两个入口都只是「把面板打开」。
    /// 旧形状（`commandPaletteSeedQuery` + `presentCommandPalette(seed:)`）是同一份词存两处，
    /// 本片删掉的是**第二份**，不是功能。
    func presentCommandPalette() {
        isCommandPalettePresented = true
    }

    /// 执行命令面板选中的命令。
    ///
    /// 分派键是**稳定 id**（不是标题 —— 改文案就会把动作改没）。
    /// 每个分支都调**既有入口**，不复制一份逻辑：面板只是"另一个按钮"。
    func performPaletteCommand(_ id: String) {
        switch id {
        case "newQuery": newQueryTab()
        case "execute":
            guard let tabID = activeQueryTab?.id else { return }
            Task { await executeQuery(for: tabID) }
        case "stop":
            guard let tabID = activeQueryTab?.id else { return }
            Task { await cancelQuery(for: tabID) }
        case "check":
            guard let tabID = activeQueryTab?.id else { return }
            Task { await checkSyntax(for: tabID) }
        case "format": formatActiveQuery()
        case "executionPlan":
            guard let tabID = activeQueryTab?.id else { return }
            Task { await runExecutionPlan(for: tabID) }
        case "find": EditorCommandCenter.shared.send(.showFind, to: activeTabIDForEditor)
        case "replace": EditorCommandCenter.shared.send(.showReplace, to: activeTabIDForEditor)
        case "goToLine":
            // 面板里没有行号输入框：这里的正确行为是**把 ⌘L 的入口指给用户**，
            // 而不是随便跳到一个行号（那只会让人莫名其妙）。
            statusMessage = L(.commandGoToLineHint, AppShortcut.goToLine.display)
        case "exportCSV":
            guard let tabID = activeQueryTab?.id else { return }
            Task { await exportResult(for: tabID, format: .csv) }
        case "exportJSON":
            guard let tabID = activeQueryTab?.id else { return }
            Task { await exportResult(for: tabID, format: .json) }
        case "browseRows":
            // 面板的目标 = 对象树当前选中项（`isBrowseRowsCommandPresented` 的 sheet 读它），
            // 选中项不够格就由 `paletteTreeObject` 给出可读提示。
            guard paletteTreeObject(where: { ObjectTreeActions.isAvailable(.browseRows, for: $0.kind) }) != nil else { return }
            isBrowseRowsCommandPresented = true
        case "tableDDL":
            // 「查看 DDL」在对象树里**没有面板**：它就是"生成建表 / 视图定义语句进新页签"。
            // 所以这条命令直接走同一个既有入口，不摆一个假界面。
            guard let object = paletteTreeObject(where: { ObjectTreeActions.isAvailable(.viewDDL, for: $0.kind) }) else { return }
            Task { await performTreeAction(.viewDDL, on: object) }
        case "sessions":
            guard prepareObjectTreePanel() else { return }
            isSessionCommandPresented = true
        case "locks":
            guard prepareObjectTreePanel() else { return }
            isLockCommandPresented = true
        case "switchConnection": isConnectionSwitchPresented = true
        case "agentSQL":
            // 这里必须设 `isAgentSQLPresented` —— 界面订阅的是它（与「智能体」菜单同一个开关）。
            // 原来这里设的是一个名字很像的 `isAgentSQLCommandPresented`：两条命令因此
            // **设了一个没人看的标志位**，点了完全没反应。这是这一批命令的共同病根。
            isAgentSQLPresented = true
        case "syntheticData":
            // 合成数据只对**表**成立（视图不可写、序列没有列）—— 与对象树右键菜单同一条规则。
            guard paletteTreeObject(where: { $0.kind == .table }) != nil else { return }
            isSyntheticCommandPresented = true
        case "egressLog": isEgressLogPresented = true
        case "help": isShortcutHelpCommandPresented = true
        case "objectSearch": isObjectSearchPresented = true
        case "routineCandidates": isRoutineCandidatesPresented = true
        case "importData":
            // 与「浏览数据」不同：导入的目标表可以手输，所以**没有对象树选中项也照开**，
            // 只是少一个默认值（刚打开时把它设成选中的表，见面板的 `onAppear`）。
            isImportPresented = true
        case "backupRestore": isBackupRestorePresented = true
        case "connectionSettings": isConnectionSettingsPresented = true
        case "databaseStats": isDatabaseStatsPresented = true
        case "slowQuery": isSlowQueryPresented = true
        case "diagnoseQuery": openDiagnosis()
        case "maintenanceTasks": openMaintenance()
        case "mcpApprovals": openMCPApprovals()
        case "notes": openNotes()
        // **「笔记」菜单那几条**（`N-UI-4`）：菜单项与 ⌘K 面板走的是这同一个分派器 ——
        // 动作全部落在**既有入口**上，这里不新造行为。
        //
        // 每条都先过 `enterNotesAreaForNotesCommand()`：面板是**全局**的（不看当前活动面），
        // 人可能站在数据库面 / 工作区面点中它们 —— 那时只改笔记面的状态就等于「点了没反应」。
        case "newNote":
            guard enterNotesAreaForNotesCommand() else { return }
            beginNewNote()
        case "newNotebook":
            guard enterNotesAreaForNotesCommand() else { return }
            beginNewNotebook()
        // 快速捕获：**不必先进笔记面**（捕获的意义就是「在任何地方都能记」），
        // 所以这条不走 `enterNotesAreaForNotesCommand` —— 面自己浮出来。
        case "quickCapture":
            beginQuickCapture()
        // 「搜索范围」两档：改的就是笔记面那枚分段控件的状态（`notesSearchScope`）——
        // 菜单与控件是同一份状态的两个入口，不另存一份。
        case "noteSearchScopeCurrent":
            guard enterNotesAreaForNotesCommand() else { return }
            notesSearchScope = .current
        case "noteSearchScopeAll":
            guard enterNotesAreaForNotesCommand() else { return }
            notesSearchScope = .all
        // 「已收藏 / 全部笔记」：与左栏那两行**同一条入口**（`selectNotesScope`）。
        case "noteFavorites":
            guard enterNotesAreaForNotesCommand() else { return }
            selectNotesScope(.favorites)
        case "noteAllNotes":
            guard enterNotesAreaForNotesCommand() else { return }
            selectNotesScope(.all)
        case "schemaDiff": isSchemaDiffPresented = true
        case "erDiagram": isERDiagramPresented = true
        case "serverObjects":
            // 与「数据库统计」同一模式：面板自己按 `selectedConnection` 取数；
            // 没连接时由面板显示 `AppError.notConnected` 的人话，而不是在这里静默不开。
            isServerObjectsPresented = true
        default:
            // 未知 id 不静默：说一句，免得"点了没反应"变成悬案。
            statusMessage = L(.commandPaletteNoMatch)
        }
    }

    /// 「笔记」菜单那 6 条命令的**统一前置**：先把人带到笔记面，再执行动作。
    ///
    /// 为什么必须有这一步：这 6 条也挂在 `⌘K` 面板上，而**面板是全局的**（`CommandPaletteView`
    /// 不按活动面过滤）。从前它们在数据库面 / 工作区面被点中时只改笔记面的状态
    /// （`notesScope` / `notesSearchScope` / 编辑器草稿 / 新建笔记本的请求）——
    /// 屏幕上**一个像素都不动**，正是这批命令当初那一族「点了没反应」，只是这次藏在
    /// 「状态改了、但改在看不见的地方」里（静态判据第 3 项与探针的旧落点表都看不见它）。
    ///
    /// 档位口径与 `openNotes()` 同源：不含笔记的档位（Pro）**照实说一句**，不假装切过去。
    /// 返回 `false` ⇒ 已经给过说法，调用方直接 `return`（别再执行动作）。
    private func enterNotesAreaForNotesCommand() -> Bool {
        guard visibleActivityItems.contains(.notes) else {
            statusMessage = L(.licenseNotesNotIncluded)
            return false
        }
        selectActivityItem(.notes)
        return true
    }

    /// 命令面板里"需要对象上下文"的三条命令（浏览数据 / 查看 DDL / 合成数据）取目标的方式。
    ///
    /// 面板是全局入口，它**不知道用户在树里选了谁**：所以目标只认对象树当前选中项，
    /// 没有、或类型不够格就直说一句 —— 不猜对象，也不留下一个没人消费的标志位
    /// （那正是这批命令"点了没反应"的成因）。
    private func paletteTreeObject(where isEligible: (DatabaseObject) -> Bool) -> DatabaseObject? {
        guard let object = selectedTreeObject, isEligible(object) else {
            statusMessage = L(.paletteNeedsTreeObject)
            return nil
        }
        focusObjectTreeSidebar()
        return object
    }

    /// 会话 / 锁这类"作用在当前连接上"的命令：没连接就直接说，别开一个必然报错的面板。
    private func prepareObjectTreePanel() -> Bool {
        guard selectedConnection != nil else {
            statusMessage = L(.stateSelectConnectionFirst)
            return false
        }
        focusObjectTreeSidebar()
        return true
    }

    /// 上述面板都住在**数据库侧栏的对象树**里：命令面板是全局入口，先把它切出来，
    /// 否则请求会落在一个没挂载的视图上 —— 那又是一次"点了没反应"。
    ///
    /// 走 `selectActivityItem` 而不是直接赋值：数据库区在当前档位不可见时，
    /// 它会照实说"当前版本不含数据库"，而不是把界面切到一个画不出来的视图上。
    private func focusObjectTreeSidebar() {
        selectActivityItem(.database)
    }

    /// 面板里"浏览/DDL/会话"等条目需要宿主视图提供对象；这里用标志位把请求交回界面，
    /// 由它在**当前选中的对象**（`selectedTreeObject`）上打开对应面板 ——
    /// 面板是通用入口，不该硬编码某个对象、也不该自己猜一个。
    @Published var isBrowseRowsCommandPresented = false
    @Published var isSessionCommandPresented = false
    @Published var isLockCommandPresented = false
    @Published var isSyntheticCommandPresented = false

    // MARK: 对象树里的面板目标（为什么放这里，而不是留在 ObjectTreeView 的 @State）
    //
    // 2026-09-24 修「编辑表结构」点取消时界面连续闪烁时定的规矩：**呈现方必须挂在单个视图上**。
    // 元凶是 `.sheet` 挂在 `Group` 上 —— SwiftUI 会把修饰符**分发到每个子视图**，而对象树的
    // 内容就是"N 行"，于是每行各挂一份（实测 16 行 × 11 个 sheet = 176 个呈现槽），
    // 取消时它们逐个收起 ⇒ 界面来回闪很多次才关。
    // 修法是把这些 sheet 移到**父级那个唯一的 `List`** 上（`ConnectionListView`），
    // 而目标状态必须跟着上移，于是放进 AppState（与 `isBrowseRowsCommandPresented` 同一套路）。
    @Published var createTableTarget: DatabaseObject?
    @Published var alterTableTarget: DatabaseObject?
    @Published var isCreateDatabasePresented = false
    @Published var isPropertiesPresented = false
    @Published var isDropDatabasePresented = false
    @Published var isPrivilegePanelPresented = false
    /// 切换连接（⌘K → 切换连接）：侧栏与查询上下文栏都有连接选择器，但没有全局入口，
    /// 所以这条命令弹一个**最小可用的**切换 sheet（见 `MainWindow` 的 `ConnectionSwitchSheet`）。
    @Published var isConnectionSwitchPresented = false
    // 注意：`isEgressLogPresented` 已经存在（外发日志面板用的就是它），
    // 这里**不要**再声明一遍 —— 本轮我就多写了一次，编译报 "ambiguous use"。
    /// 快捷键帮助（⌘K → 帮助）：与工具栏那个 help 气泡共用 `ShortcutHelpContent`，
    /// 不在这里再抄一份快捷键清单（抄两份迟早只改一处）。
    @Published var isShortcutHelpCommandPresented = false

    private var activeTabIDForEditor: UUID { activeQueryTab?.id ?? UUID() }

    /// 格式化当前页签（与「编辑 → 格式化」同一入口）。
    private func formatActiveQuery() {
        guard let tabID = activeQueryTab?.id else { return }
        EditorCommandCenter.shared.send(.format, to: tabID)
    }

    // MARK: - 查询参数（FR-EXEC-17）

    /// 待填参数的执行请求（弹面板用）。
    struct PendingQueryParameters: Equatable {
        var tabID: UUID
        /// 抠出运行范围之后、**尚未绑定**的语句。
        var sql: String

        var parameters: [SQLParameters.Parameter] { SQLParameters.extract(from: sql) }
    }

    @Published var pendingQueryParameters: PendingQueryParameters?
    @Published var isQueryParameterSheetPresented = false

    /// 面板确认：绑定后执行（**不改写编辑器**）。
    func runPendingQueryParameters(values: [String: (type: SQLParameters.ValueType, raw: String)]) async {
        guard let pending = pendingQueryParameters else { return }
        switch SQLParameters.bind(sql: pending.sql, values: values) {
        case .success(let bound):
            pendingQueryParameters = nil
            isQueryParameterSheetPresented = false
            if !bound.unusedNames.isEmpty {
                statusMessage = L(.queryParameterUnused, bound.unusedNames.joined(separator: "、"))
            }
            await executeQuery(for: pending.tabID, bypassingSafetyCheck: true, sqlOverride: bound.sql)
        case .failure(let error):
            // 面板上就地显示（`queryParameterError`），不静默、也不执行。
            queryParameterError = error.localizedDescription
        }
    }

    /// 面板取消：**什么也不执行**（不是"用空值执行"）。
    func cancelPendingQueryParameters() {
        pendingQueryParameters = nil
        isQueryParameterSheetPresented = false
        queryParameterError = nil
    }

    @Published var queryParameterError: String?

    // MARK: - 合成数据（FR-AI-07）

    /// 面板上的错误 / 提示（与其它面板一致：不弹窗打断，就地显示）。
    @Published var syntheticDataError: String?
    @Published var syntheticDataMessage: String?

    /// 按表结构推断一份合成数据规格（主键→序列、非空列不给 NULL）。
    func syntheticSpec(for object: DatabaseObject, rowCount: Int, seed: UInt64) async throws -> SyntheticTableSpec {
        guard let configuration = selectedConnection else { throw AppError.notConnected }
        let structure = try await tableStructure(of: object)
        return SyntheticSpecBuilder.spec(
            table: object.name,
            schema: object.schema,
            columns: structure.map(SyntheticSpecBuilder.ColumnShape.init),
            rowCount: rowCount,
            seed: seed
        )
    }

    /// 生成行（纯计算，不碰库）。
    func generateSyntheticRows(_ spec: SyntheticTableSpec) throws -> [[String?]] {
        try Self.syntheticRows(for: spec)
    }

    /// 「规格 → 行」的**唯一出处**（纯计算，`nonisolated`：不碰任何实例状态）。
    ///
    /// 为什么要有它（队列 L-60）：合成数据面板的**注入那一路**要在 `init` 里就把行算好
    /// （`@EnvironmentObject` 在 `init` 里还没有值 ⇒ 拿不到这个实例），查库那一路则在拿到结构之后
    /// 算 —— 两处必须是同一份实现，否则「同一个规格、两条路给不同的行」（L-50 的病根就是两处各写一遍）。
    /// 生成失败时的错误措辞也因此逐字一致。
    nonisolated static func syntheticRows(for spec: SyntheticTableSpec) throws -> [[String?]] {
        let issues = SyntheticDataGenerator.issues(in: spec)
        guard issues.isEmpty else {
            throw AppError.invalidConfiguration(issues.joined(separator: "；"))
        }
        return try SyntheticDataGenerator.generate(spec)
    }

    /// 生成 INSERT 语句并**放进新页签**（不执行）—— 与其它"产出 SQL"的入口同一纪律。
    func exportSyntheticInsert(_ spec: SyntheticTableSpec, rows: [[String?]], overwrite: Bool) {
        guard let dialect = selectedConnection.map({ SQLDialectFactory.make(for: $0.dbType) }) else {
            syntheticDataError = L(.stateSelectConnectionFirst)
            return
        }
        guard let sql = SyntheticDataGenerator.insertStatements(
            rows: rows,
            spec: spec,
            writeMode: overwrite ? .overwrite : .append,
            dialect: dialect
        ) else {
            syntheticDataError = L(.syntheticInsertFailed)
            return
        }
        syntheticDataError = nil
        openSQLInNewTab(sql, status: L(.syntheticExported))
    }

    /// 写入目标表：**走既有审批闸门**（与数据任务同一条路，不另造一套）。
    ///
    /// 只读模式下 `submitAgentAction` 直接 `.denied` —— 连审批单都建不出来；
    /// 需要人工批准时审批单由它自己弹出，批准后的执行读的是**审批单里那条 SQL**，
    /// 因此这里不需要再存一份待执行内容。
    func writeSyntheticData(_ spec: SyntheticTableSpec, rows: [[String?]], overwrite: Bool) async {
        guard let dialect = selectedConnection.map({ SQLDialectFactory.make(for: $0.dbType) }) else {
            syntheticDataError = L(.stateSelectConnectionFirst)
            return
        }
        guard let sql = SyntheticDataGenerator.insertStatements(
            rows: rows,
            spec: spec,
            writeMode: overwrite ? .overwrite : .append,
            dialect: dialect
        ) else {
            syntheticDataError = L(.syntheticInsertFailed)
            return
        }

        let submission = await submitAgentAction(sql)
        switch submission {
        case .denied:
            syntheticDataMessage = nil
            syntheticDataError = L(.syntheticWriteDenied, submission.message)
        case .awaitingApproval:
            syntheticDataError = nil
            syntheticDataMessage = L(.syntheticWritePending)
        case .approved:
            syntheticDataError = nil
            do {
                let affected = try await executeApprovedAgentAction(sql)
                syntheticDataMessage = L(.syntheticWriteDone, affected ?? 0)
            } catch {
                syntheticDataError = ErrorPresenter.message(for: error)
            }
        }
    }

    // MARK: - 导入（FR-IO-03 的界面入口）

    /// 导入面板是否呈现（「文件」菜单与 ⌘K 命令 `importData` 都打开它）。
    @Published var isImportPresented = false
    @Published private(set) var isImportRunning = false
    /// 0…1；COPY 路径只有 0 / 0.5 / 1 三档（驱动一次性提交整段数据，取不到更细的粒度）。
    @Published private(set) var importProgress: Double = 0
    /// 逐批日志（与备份 / 恢复面板同一做法：用户要能看到"跑到第几批、写了几行"）。
    @Published private(set) var importLog: [String] = []
    @Published var importError: String?
    @Published var importMessage: String?
    private var importTask: Task<Void, Never>?

    /// 导入往哪儿写（探针缝）：为 `nil` 时按连接真连（生产）；探针放进一个假 `DatabaseService`
    /// 之后，`startTableImport` 走的仍是生产那条路 —— 安全检查 → 通道选择 → `SET search_path` →
    /// COPY 负载 / 分批 INSERT → 进度与日志 —— 只有「数据落到哪」换成了假的。
    ///
    /// 为什么开这一处：`FR-STD-DB-IO-006` / `-007` 的台账备注是「界面点击待人工点验」，
    /// 而「点执行之后到底发了哪些语句、负载里每个值有没有串列、NULL 与空串分不分得开」
    /// 完全可以由探针从**假服务收到的字节**上判（`performTableImport` 原先把服务从私有
    /// `ensureService` 里取，注不进去）。
    var importServiceOverride: (any DatabaseService)?

    /// 读目标表结构 → 生成列映射。**映射用 Core 的 `TableImport.plan`**，
    /// 界面不自己写一套"名字对上就映射"的规则（那会与 CLI 的映射漂移）。
    func tableImportPlan(
        table: String,
        schema: String?,
        sourceHeader: [String],
        hasHeader: Bool = true
    ) async throws -> TableImport.Plan {
        guard let configuration = selectedConnection else { throw AppError.notConnected }
        let object = DatabaseObject(
            id: "import:\(schema.map { "\($0)." } ?? "")\(table)",
            name: table,
            kind: .table,
            database: currentDatabaseName(for: configuration),
            schema: schema
        )
        let structure = try await tableStructure(of: object)
        return TableImport.plan(
            table: table,
            schema: schema,
            sourceHeader: sourceHeader,
            targetColumns: structure.map { TableImport.TargetColumn($0) },
            // 文件没有表头 → 只能按位置对（用户显式关掉表头开关才走这条）。
            sourceLayout: hasHeader ? .byName : .byPosition
        )
    }

    /// 安全检查：**用界面上真正会下发的那条语句**过 `ExecutionSafety`。
    ///
    /// 为什么不复用智能体审批闸门：那条路会在批准后**执行审批单里的 SQL**，
    /// 而 COPY 的实际下发由驱动完成（审批单里那条语句根本不能单独执行）。
    /// 手动导入与"在编辑器里敲一条 INSERT"是同一类动作，因此走同一道
    /// `ExecutionSafety`（只读连接直接拒绝、`needsConfirmation` 时二次确认）。
    func tableImportSafetyDecision(_ request: TableImportRequest) -> ExecutionSafety.Decision {
        let databaseType = selectedConnection?.dbType ?? .postgresql
        let dialect: any SQLDialect = SQLDialectFactory.make(for: databaseType)
        let representative: String?
        switch request.mode {
        case .copy:
            representative = TableImport.copyStatement(
                table: request.plan.table,
                schema: request.plan.schema,
                columns: request.plan.mappedColumns.map(\.targetName),
                dialect: dialect
            )
        case .batchInsert:
            // 代表性语句：一条只含映射列、值为 NULL 的 INSERT —— 分类与"是否写操作"
            // 与真实批次完全一致，但不必把几百行真实数据丢进词法扫描。
            let row: [String?] = request.plan.mappedColumns.map { _ in nil }
            representative = TableImport.insertStatement(rows: [row], plan: request.plan, dialect: dialect)
        }
        guard let representative, !representative.isEmpty else { return .allow }
        return ExecutionSafety.check(
            sql: representative,
            databaseType: databaseType,
            policy: executionSafetyPolicy
        )
    }

    /// 启动一次导入。返回"起了 / 需要确认 / 被拒"，**被拒时一定不执行**。
    @discardableResult
    func startTableImport(_ request: TableImportRequest) -> TableImportStart {
        guard !isImportRunning else { return .refused(L(.importRunning)) }
        guard selectedConnection != nil else {
            importError = L(.importNeedsConnection)
            return .refused(L(.importNeedsConnection))
        }
        guard !request.plan.mappedColumns.isEmpty else {
            importError = L(.importNothingMapped)
            return .refused(L(.importNothingMapped))
        }
        if !request.bypassingSafetyCheck {
            let decision = tableImportSafetyDecision(request)
            switch decision {
            case .allow:
                break
            case .needsConfirmation:
                return .needsConfirmation(decision)
            case .refused(let reasons, _):
                let message = reasons.first ?? L(.safetyReadOnlyRefused)
                importError = message
                return .refused(message)
            }
        }

        importError = nil
        importMessage = nil
        importProgress = 0
        importLog = []
        isImportRunning = true
        importTask = Task { [weak self] in
            guard let self else { return }
            await self.performTableImport(request)
        }
        return .started
    }

    /// 停止导入：只在**批次之间**生效（COPY 是单条语句，驱动不给中途取消的钩子）。
    func cancelTableImport() {
        importTask?.cancel()
    }

    func clearImportLog() {
        importLog = []
        importError = nil
        importMessage = nil
        importProgress = 0
    }

    private func appendImportLog(_ line: String) {
        importLog.append(line)
        // 2 万行 / 500 一批只有 40 条；上限只是防御性措施，免得异常情况下无限增长。
        if importLog.count > 500 { importLog.removeFirst(importLog.count - 500) }
    }

    private func performTableImport(_ request: TableImportRequest) async {
        defer {
            isImportRunning = false
            importTask = nil
        }
        guard let configuration = selectedConnection else {
            importError = L(.importNeedsConnection)
            return
        }
        let dialect: any SQLDialect = SQLDialectFactory.make(for: configuration.dbType)
        let columns = request.plan.mappedColumns.map(\.targetName)
        var written = 0

        do {
            let service: any DatabaseService
            if let importServiceOverride {
                service = importServiceOverride
            } else {
                service = try await ensureService(
                    for: configuration,
                    database: queryDatabase(for: configuration)
                )
            }

            if request.mode == .copy {
                // 驱动的 COPY 自己给表名加引号，表达不了 schema 限定名 ——
                // 与 CLI `import --copy --schema` 同一做法：先在同一个连接上设 search_path。
                if let schema = request.plan.schema, !schema.isEmpty {
                    let statement = "SET search_path TO \(dialect.quoteIdentifier(schema))"
                    appendImportLog(statement)
                    for try await _ in service.execute(statement, options: .default) {}
                }
                appendImportLog(L(.importCopyAtomicNote))
                let payload = TableImport.copyRows(rows: request.rows, plan: request.plan)
                    .map { CopyTextFormat.encode(row: $0) + CopyTextFormat.rowSeparator }
                    .joined()
                appendImportLog(L(.importCopyStarted, request.rows.count, columns.count, payload.utf8.count))
                importProgress = 0.5

                let started = Date()
                try await service.copyFromText(
                    table: request.plan.table,
                    columns: columns,
                    text: payload
                )
                written = request.rows.count
                importProgress = 1
                importMessage = L(.importDoneCopy, written, Date().timeIntervalSince(started))
                return
            }

            let batches = TableImport.batches(request.rows, size: request.plan.batchSize)
            for (index, batch) in batches.enumerated() {
                if Task.isCancelled {
                    importMessage = L(.importCancelled, written)
                    return
                }
                guard let sql = TableImport.insertStatement(rows: batch, plan: request.plan, dialect: dialect) else {
                    importError = L(.importNothingMapped)
                    return
                }
                var tally = AffectedRowsTally()
                for try await event in service.execute(sql, options: .default) {
                    tally.absorb(event)
                }
                // 驱动不报行数时按本批行数计（INSERT 的值个数就是写进去的行数）。
                written += tally.value ?? batch.count
                importProgress = Double(index + 1) / Double(batches.count)
                appendImportLog(L(.importProgress, index + 1, batches.count, written))
            }
            importMessage = L(.importDone, written, batches.count)
        } catch is CancellationError {
            importMessage = L(.importCancelled, written)
        } catch {
            let reason = ErrorPresenter.message(for: error)
            if written > 0, request.mode == .batchInsert {
                // 前面批次已生效：这说明白，别让用户以为"整体回滚了"。
                importMessage = L(.importPartial, written)
            }
            importError = L(.importFailed, reason)
        }
    }

    // MARK: - 服务器会话（FR-SESS-01 / FR-SESS-02）

    /// 读取当前实例的会话列表（按「等待中 → 活跃 → 空闲」排序，排序规则在 Core 里可单测）。
    func loadServerSessions() async throws -> [ServerSession] {
        guard let configuration = selectedConnection else {
            throw AppError.notConnected
        }
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        guard let query = dialect.serverActivityQuery() else {
            throw AppError.notImplemented(L(.sessionUnsupported))
        }

        let database = currentDatabaseName(for: configuration)
        let service = try await ensureService(for: configuration, database: database)
        let result = try await runSingleQuery(query, on: service)
        return SessionMonitor.sorted(SessionMonitor.sessions(from: result))
    }

    /// 「取消当前语句」：温和（语句被中断，连接还在）。返回**空串表示成功**，否则是可读错误。
    ///
    /// 为什么用"空串=成功"这种不优雅的约定：这个方法被面板直接用来填错误区，
    /// 成功时不该弹任何东西；返回 `String?` 会让调用方写成两层判断，反而更容易漏。
    func cancelSessionStatement(pid: Int) async -> String {
        await runSessionSignal(pid: pid, kind: .cancel)
    }

    /// 「终止会话」：掐断整条连接（不可逆），界面必须二次确认后调它。
    func terminateSession(pid: Int) async -> String {
        await runSessionSignal(pid: pid, kind: .terminate)
    }

    private enum SessionSignal {
        case cancel
        case terminate

        var isDestructive: Bool { self == .terminate }
    }

    private func runSessionSignal(pid: Int, kind: SessionSignal) async -> String {
        guard let configuration = selectedConnection else {
            return L(.stateSelectConnectionFirst)
        }
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        let statement: String?
        switch kind {
        case .cancel: statement = dialect.cancelSessionStatement(pid: pid)
        case .terminate: statement = dialect.terminateSessionStatement(pid: pid)
        }
        guard let statement else {
            return L(.sessionSignalUnsupported)
        }

        do {
            let database = currentDatabaseName(for: configuration)
            let service = try await ensureService(for: configuration, database: database)
            // 「不许掐自己的会话」：能取到自己的会话号就当场拒（详设 §6 `SESS_KILL_DENIED`）。
            // 拒在这里而不是等服务端 —— 服务端拒的是「没权限」，这里拒的是「你正在用它」，
            // 两者文案与后果都不同：前者还能换个有权限的账号，后者一发就自断连接。
            if kind.isDestructive,
               let reporting = service as? OwnSessionReporting,
               let own = await reporting.ownSessionPID(),
               SessionKillGuard.decide(isOwnSession: own == pid,
                                       confirmed: true,
                                       canTerminate: true) == .selfSessionRefused {
                return L(.sessionOwnRefused, pid)
            }
            let result = try await runSingleQuery(statement, on: service)
            // 服务端返回布尔：false 通常意味着**权限不够**（PG 要求同用户或 pg_signal_backend）。
            // 这一步必须如实区分，否则用户会以为"点了没反应"。
            let succeeded = result.rows.first?.first??.lowercased()
            switch succeeded {
            case "t", "true", "1":
                statusMessage = kind.isDestructive
                    ? L(.sessionTerminated, pid)
                    : L(.sessionStatementCancelled, pid)
                return ""
            case .some:
                return L(.sessionSignalDenied, pid)
            case nil:
                // 没有返回值的方言（例如 GBase 的 KILL）：只能按"语句执行成功"处理，并如实说明。
                statusMessage = kind.isDestructive ? L(.sessionTerminated, pid) : L(.sessionStatementCancelled, pid)
                return ""
            }
        } catch {
            return ErrorPresenter.message(for: error)
        }
    }

    // MARK: - 锁与阻塞链（FR-DIAG-05）

    /// 查询锁等待关系；方言不支持时抛可读错误。
    func loadLockWaits() async throws -> [LockWait] {
        guard let configuration = selectedConnection else {
            throw AppError.notConnected
        }

        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        guard let query = dialect.lockWaitingQuery() else {
            throw AppError.notImplemented(L(.lockUnsupported))
        }

        let service = try await ensureService(
            for: configuration,
            database: currentDatabaseName(for: configuration)
        )
        let result = try await runSingleQuery(query, on: service)
        return LockMonitor.waits(from: result)
    }

    // MARK: - 管理语句执行

    /// 逐条执行管理类语句。
    ///
    /// `ALTER DATABASE` 会被生成器拆成多条，因此走 `StatementSplitter` 逐条下发；
    /// 这类语句没有结果集，事件丢弃即可，服务端报错会从流里抛出。
    private func runStatements(
        _ sql: String,
        databaseType: DatabaseType,
        on service: any DatabaseService
    ) async throws {
        let statements = StatementSplitter(databaseType: databaseType).split(sql)
        for statement in statements {
            for try await _ in service.execute(statement.sql, options: .default) {}
        }
    }

    func loadMetadataRoot() async throws -> [DatabaseObject] {
        guard let configuration = selectedConnection else {
            throw AppError.notConnected
        }
        // 建库权限决定右键菜单是否呈现「新建数据库」；探测失败不影响对象树加载。
        await refreshDatabaseCreationPermission()

        let database = currentDatabaseName(for: configuration)
        let metadata = try await makeMetadataService(
            configuration: configuration,
            database: database
        )
        return try await metadata.loadRoot()
    }

    func loadMetadataChildren(of object: DatabaseObject) async throws -> [DatabaseObject] {
        guard let configuration = selectedConnection else {
            throw AppError.notConnected
        }
        // 表 / 列 / schema 节点自带所属数据库；服务器或数据库节点用当前库。
        let database = object.database ?? currentDatabaseName(for: configuration)
        let metadata = try await makeMetadataService(
            configuration: configuration,
            database: database
        )
        return try await metadata.loadChildren(of: object)
    }

    /// 全库对象搜索（FR-META-12）：**一次**元数据查询取回表 / 视图 / 列 / 函数，
    /// 过滤与排序都由 Core 的 `ObjectSearch` 负责（那里可单测）。
    ///
    /// 这里**不查方言能力**：`ObjectSearch.query` 是固定的 PostgreSQL 系统目录口径
    /// （`information_schema` + `pg_proc`），方言层还没有对应的能力开关。
    /// 在别的方言上它会以一条可读的 SQL 错误抛出、由面板显示出来 ——
    /// 比在这里猜一个"支持 / 不支持"的判定诚实。
    func searchObjects(_ keyword: String, schema: String? = nil) async throws -> ObjectSearch.Outcome {
        guard let configuration = selectedConnection else {
            throw AppError.notConnected
        }
        // 走方言能力开关（nil = 该方言不支持）：非 PG 连接上给一句人话，
        // 而不是把一条 PG 口径的 SQL 丢过去换回一句莫名其妙的报错。
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        guard let query = dialect.objectSearchQuery(schema: schema, limit: ObjectSearch.defaultLimit) else {
            throw AppError.notImplemented(L(.objectSearchUnsupported, configuration.dbType.displayName))
        }

        let database = currentDatabaseName(for: configuration)
        let service = try await ensureService(for: configuration, database: database)
        let result = try await runSingleQuery(query, on: service)
        return ObjectSearch.outcome(keyword: keyword, in: ObjectSearch.hits(from: result))
    }

    /// 数据库统计（FR-DIAG-04）：四条只读查询，走方言能力开关。
    ///
    /// 方言不支持（GBase）时给一句人话，而不是把 PG 口径的 SQL 丢过去换回一句莫名其妙的报错。
    /// 某一条拿不到不影响其余三条 —— 诊断面板要的是"有什么看什么"。
    func databaseStats(limit: Int = 20) async throws -> DatabaseStats.Report {
        guard let configuration = selectedConnection else {
            throw AppError.notConnected
        }
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        guard DatabaseStats.Metric.allCases.contains(where: { dialect.databaseStatsQuery($0, limit: limit) != nil }) else {
            throw AppError.notImplemented(L(.databaseStatsUnsupported, configuration.dbType.displayName))
        }

        let database = currentDatabaseName(for: configuration)
        let service = try await ensureService(for: configuration, database: database)

        func run(_ metric: DatabaseStats.Metric) async -> QueryResult? {
            guard let sql = dialect.databaseStatsQuery(metric, limit: limit) else { return nil }
            return try? await runSingleQuery(sql, on: service)
        }

        return DatabaseStats.report(
            tableSizes: await run(.tableSizes),
            tableScans: await run(.indexHitRate),
            connections: await run(.connections),
            cacheHit: await run(.cacheHitRate),
            limit: limit
        )
    }

    // MARK: - 慢查询排行（FR-DIAG-03）

    /// 慢查询排行的一次读数：**三态分开**（排行 / 没装扩展 / 没法判）。
    ///
    /// 为什么不是「返回空数组」：需求原文「无扩展或无权限时明确提示，不静默失败」——
    /// 把「没装扩展」显示成「一条慢查询都没有」是这条需求点名不许做的事。
    enum SlowQueryOutcome: Equatable {
        case ranking([SlowQueryReport.Entry])
        /// 扩展没装 / 关系不在：带一份可照做的安装指引（文案在 Core，不在这里另写一份）。
        case missingExtension(String)
        /// 方言不支持，或拿不到服务器主版本（列名 PG 13 前后不同 —— 不猜）。
        case unsupported(String)
    }

    /// 慢查询排行：先判扩展在不在，再按口径取前 N 条。
    ///
    /// 排序口径与列名适配全在 `Core/SlowQueryReport`（按服务器主版本选 `total_time` /
    /// `total_exec_time`），这里只做「取哪一经、发给谁、拿不到怎么说」。
    func slowQueryRanking(
        sort: SlowQueryReport.Sort = .totalTime,
        limit: Int = 20
    ) async throws -> SlowQueryOutcome {
        guard let configuration = selectedConnection else { throw AppError.notConnected }
        guard configuration.dbType == .postgresql else {
            return .unsupported(L(.slowQueryUnsupported, configuration.dbType.displayName))
        }
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        let service = try await ensureService(
            for: configuration,
            database: currentDatabaseName(for: configuration)
        )

        let availability = try await runSingleQuery(SlowQueryReport.extensionCheckQuery, on: service)
        guard SlowQueryReport.isExtensionInstalled(availability) else {
            return .missingExtension(SlowQueryReport.missingExtensionMessage)
        }
        // 主版本决定列名。拿不到版本时**不猜**：猜错的后果是一条「column does not exist」，
        // 用户会以为扩展坏了 —— 那比说「不知道」更糟。
        guard let version = serverInfos[configuration.id],
              dialect.parseServerVersion(version.version).major > 0 else {
            return .unsupported(L(.slowQueryVersionUnknown))
        }
        let major = dialect.parseServerVersion(version.version).major
        let result = try await runSingleQuery(
            SlowQueryReport.query(sort: sort, limit: limit, serverMajor: major),
            on: service
        )
        return .ranking(SlowQueryReport.entries(from: result))
    }

    /// 排行里点一条：把它的原文放进编辑器（**不执行** —— 与诊断建议同一条口径）。
    func putSlowQueryInEditor(_ entry: SlowQueryReport.Entry) {
        guard let tab = selectedTab else { return }
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs[index].sql = entry.query
            statusMessage = L(.slowQueryInserted)
        }
    }

    // MARK: - 服务器级对象（FR-SESS-03）

    /// 读三类服务器级对象（角色 / 表空间 / 扩展）。
    ///
    /// 与 `databaseStats(limit:)` 同一分工：**查什么由 Core 的方言能力开关决定**
    /// （`ServerObjects.browsePlan`）。不支持的那一类既不发查询、也不编造空列表 ——
    /// Core 给的可读理由原样带回界面，界面才能说「GBase 8a 没有表空间概念」，
    /// 而不是摆一个空表格让人以为「恰好一个都没有」。
    func serverObjectSections(limit: Int = ServerObjects.defaultLimit) async throws -> [ServerObjectSection] {
        guard let configuration = selectedConnection else {
            throw AppError.notConnected
        }
        let dialect = ServerObjectDialectFactory.make(for: configuration.dbType)
        let database = currentDatabaseName(for: configuration)
        let service = try await ensureService(for: configuration, database: database)

        var sections: [ServerObjectSection] = []
        for kind in ServerObjectKind.allCases {
            let plan = ServerObjects.browsePlan(kind, dialect: dialect, limit: limit)
            guard let sql = plan.sql else {
                sections.append(
                    ServerObjectSection(kind: kind, unsupportedReason: plan.unsupportedReason)
                )
                continue
            }
            // 单类失败不影响其它类：与统计面板同一条口径（"有什么看什么"）。
            let result = try? await runSingleQuery(sql, on: service)
            sections.append(
                ServerObjectSection(
                    kind: kind,
                    objects: result.map { ServerObjects.objects(from: $0, kind: kind) } ?? [],
                    approximationNote: plan.note
                )
            )
        }
        return sections
    }

    /// 生成一条写操作的**预览**（语句 / 风险等级 / 提醒）—— **不执行任何东西**。
    ///
    /// 校验与语句构造都在 Core 的 `ServerObjects.plan`：非法名字在这里就变成一条可读的拒绝理由，
    /// 而不是等数据库报错（那会把「名字写错了」说成「权限不足 / 语法错误」）。
    func serverObjectWritePlan(_ request: ServerObjectRequest) throws -> ServerObjectWritePlan {
        guard let configuration = selectedConnection else {
            throw AppError.notConnected
        }
        return ServerObjects.plan(request, dialect: ServerObjectDialectFactory.make(for: configuration.dbType))
    }

    /// 服务器级对象写操作的**统一安全闸门**（FR-EXEC-16 的同一条线）。
    ///
    /// 与「在编辑器里敲一条 `CREATE ROLE`」用的是**同一份策略**：Safe Mode 总开关、
    /// 「所有写操作都确认」、生产标签强制确认、以及只读连接的直接拒绝 —— 判据只有一处
    /// （`Core/ExecutionSafety`），界面层不再各写一套。语句分类走既有的词法判定：
    /// `CREATE` / `ALTER` / `DROP` 属结构变更，`GRANT` / `REVOKE` 属权限变更，都是写操作。
    func serverObjectSafetyDecision(_ command: ServerObjectCommand) -> ExecutionSafety.Decision {
        ExecutionSafety.check(
            sql: command.statement,
            databaseType: selectedConnection?.dbType ?? .postgresql,
            policy: executionSafetyPolicy
        )
    }

    /// 一条服务器级写操作的启动结果。
    ///
    /// 用显式结果而不是 `Bool`：调用方必须分别面对「真的执行了 / 需要更高一级确认 /
    /// 被安全闸门拒绝」三种情况 —— 尤其**被拒时绝不能执行**，这一点不能靠返回值猜。
    enum ServerObjectWriteStart: Equatable {
        case started
        case needsConfirmation(ExecutionSafety.Decision)
        case refused(String)
    }

    /// 执行一条**已经预览**的写操作（**先过统一安全闸门**）。
    ///
    /// 只接受 `ServerObjectCommand`（而不是任意 SQL）：命令带着风险等级与目标名，
    /// 上层没法「绕过预览直接执行一条谁也没看过的语句」。
    /// `bypassingSafetyCheck` 只在用户**已经看过统一确认弹窗并点了继续**后使用，
    /// 与编辑器路径同一个约定（避免重复弹窗）。
    @discardableResult
    func executeServerObjectWrite(
        _ command: ServerObjectCommand,
        bypassingSafetyCheck: Bool = false
    ) async throws -> ServerObjectWriteStart {
        guard let configuration = selectedConnection else {
            throw AppError.notConnected
        }
        if !bypassingSafetyCheck {
            let decision = serverObjectSafetyDecision(command)
            switch decision {
            case .allow:
                break
            case .needsConfirmation:
                // 不执行：由界面弹出**与编辑器同一张**确认弹窗，确认后再带 bypass 回来。
                return .needsConfirmation(decision)
            case .refused(let reasons, let statements):
                // 只读连接的拒绝不是「要不要冒险」，而是「这条连接不写」——绝不执行。
                let detail = (reasons + statements.map { "· " + $0 }).joined(separator: "\n")
                statusMessage = reasons.first ?? L(.safetyReadOnlyRefused)
                return .refused(detail)
            }
        }

        let database = currentDatabaseName(for: configuration)
        let service = try await ensureService(for: configuration, database: database)
        // DDL / DCL 可能**没有结果集**（`CREATE ROLE` 就是），所以不能用 `runSingleQuery`
        // —— 那个入口把「没有结果集」当成错误，会把一次成功的建角色报成失败。
        for try await _ in service.execute(command.statement, options: .default) {}
        statusMessage = L(.serverObjectsExecuted, command.statement)
        return .started
    }


    // MARK: - 外键引用导航的界面入口（FR-DATA-06）

    /// 结果表格里点了「跳到被引用行」：先判这张结果的来源表与这一列的外键，
    /// 再把跳转语句送到新页签（**真的执行**，因为用户点的就是"看被引用的那一行"）。
    ///
    /// 三条"宁可说不知道"的口径：
    /// ① 结果不是从某张表浏览出来的（手写 SQL）→ 不猜表名；
    /// ② 这一列没有外键 → 直说，不生成一条必然查不到的语句；
    /// ③ 单元格是 NULL → 直说，`WHERE id = NULL` 永远查不到任何行。
    func jumpToReferencedRow(column: String, value: String?) {
        guard let tab = selectedTab, let source = tab.sourceTable else {
            statusMessage = L(.fkJumpUnknownTable)
            return
        }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            statusMessage = L(.fkJumpNullValue, column)
            return
        }
        Task { await resolveForeignKeyJump(source: source, column: column, value: trimmed) }
    }

    /// 「跳到被引用行…」这一格露不露面的依据（FR-DATA-06）。
    ///
    /// `nil` = 这张表的元数据还没读到 ⇒ 不露；空集 = 读到了、没有外键 ⇒ 也不露。
    /// 两条都归 `ForeignKeyNavigation.entryVisible` 判，视图不自己写一遍。
    func jumpableColumns(for table: DatabaseObjectRef?) -> Set<String>? {
        guard let table else { return nil }
        return foreignKeyColumns[table.qualifiedName]
    }

    /// 读一张表「哪些列真的挂着外键」；读到就缓存，读不到**不缓存**（下次挂载再试）。
    ///
    /// 为什么先读再露：需求原文的验收是「存在外键元数据时才呈现入口」。以前这个入口
    /// 常驻，点下去才说「这一列没有外键」—— 那是把「没做」画成「做了」。
    /// 只读本表的约束（正向）；反向（谁引用我）需要扫整个 schema，属后续版本，不在这里假装。
    func ensureForeignKeyColumns(for table: DatabaseObjectRef) async {
        let key = table.qualifiedName
        if foreignKeyColumns[key] != nil || loadingForeignKeyTables.contains(key) { return }
        loadingForeignKeyTables.insert(key)
        defer { loadingForeignKeyTables.remove(key) }
        guard let edges = try? await foreignKeyEdges(table: table) else { return }
        foreignKeyColumns[key] = ForeignKeyNavigation.forwardColumns(
            table: table.name,
            edges: edges,
            schema: table.schema
        )
    }

    private func resolveForeignKeyJump(source: DatabaseObjectRef, column: String, value: String) async {
        do {
            let edges = try await foreignKeyEdges(table: source)
            let options = ForeignKeyNavigation.options(
                table: source.name,
                column: column,
                edges: edges,
                schema: source.schema
            )
            guard !options.isEmpty else {
                statusMessage = L(.fkJumpNoForeignKey, column)
                return
            }
            if options.count == 1 {
                await openReferencedRow(options[0], value: value, source: source, column: column)
            } else {
                // 多个目标（同一列被多条外键引用）时让用户选，而不是替他按字母序挑一个。
                pendingForeignKeyJump = ForeignKeyJumpRequest(
                    options: options,
                    value: value,
                    source: source,
                    column: column
                )
            }
        } catch {
            statusMessage = L(.fkJumpFailed, error.localizedDescription)
        }
    }

    /// 选中某个目标后的跳转（面板与单选路径共用）。
    func performForeignKeyJump(_ request: ForeignKeyJumpRequest, option: ForeignKeyNavigation.Option) async {
        await openReferencedRow(option, value: request.value, source: request.source, column: request.column)
    }

    private func openReferencedRow(
        _ option: ForeignKeyNavigation.Option,
        value: String,
        source: DatabaseObjectRef,
        column: String
    ) async {
        guard let configuration = selectedConnection else { return }
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        // 类型名从**源表结构**取：数字列写成 `'42'` 会让数据库做隐式转换，
        // 索引可能用不上（而且 PG 上某些类型直接报错）。
        let typeName = await columnTypeName(schema: source.schema, table: source.name, column: column)
        let sql = ForeignKeyNavigation.query(option: option, value: value, typeName: typeName, dialect: dialect)
        openSQLInNewTab(
            sql,
            status: L(.fkJumpStatus, option.targetTable, column, value),
            execute: true
        )
    }

    /// 读一张表的外键边。
    ///
    /// 现状（写进需求行的"仍未做"里，不假装有缓存）：每次跳转读一次该表的约束，
    /// 不缓存也不扫全库 —— 大库上的外键图缓存仍属后续。
    private func foreignKeyEdges(table source: DatabaseObjectRef) async throws -> [ForeignKeyNavigation.Edge] {
        guard let configuration = selectedConnection else {
            throw AppError.notConnected
        }
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        guard let query = dialect.tableConstraintsQuery(table: source.name, schema: source.schema) else {
            return []
        }
        let database = currentDatabaseName(for: configuration)
        let service = try await ensureService(for: configuration, database: database)
        let result = try await runSingleQuery(query, on: service)

        var edges: [ForeignKeyNavigation.Edge] = []
        for row in result.rows {
            let constraintName = row.indices.contains(0) ? row[0] : nil
            let kind = (row.indices.contains(1) ? row[1] : nil) ?? ""
            let definition = (row.indices.contains(2) ? row[2] : nil) ?? ""
            if let edge = ForeignKeyNavigation.parseEdge(
                constraintName: constraintName,
                kind: kind,
                definition: definition,
                table: source.name,
                schema: source.schema,
                // 同 schema 的引用在 `pg_get_constraintdef` 里不带 schema，这里让它继承源表 schema
                defaultSchema: source.schema
            ) {
                edges.append(edge)
            }
        }
        return edges
    }

    private func columnTypeName(schema: String?, table: String, column: String) async -> String {
        guard let configuration = selectedConnection else { return "text" }
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        guard let query = dialect.tableStructureQuery(table: table, schema: schema) else { return "text" }
        let database = currentDatabaseName(for: configuration)
        guard let service = try? await ensureService(for: configuration, database: database),
              let structure = try? await runSingleQuery(query, on: service) else {
            return "text"
        }
        let definitions = MetadataService.columnDefinitions(from: structure)
        return definitions.first { $0.name.caseInsensitiveCompare(column) == .orderedSame }?.typeName ?? "text"
    }

    // MARK: - Schema 对比与同步（FR-DDL-04 的界面差异视图）

    /// 抓一张 schema 快照（表 + 列）。界面差异视图的两侧各抓一张，差异计算交给 Core 纯函数。
    ///
    /// 为什么快照在 App 侧编排而不是 Core：它要**真的连库跑查询**，而 Core 只管纯逻辑。
    /// 解析仍复用 Core 的 `MetadataService.columnDefinitions`（既有单测），不另写一套。
    func schemaSnapshot(
        connectionID: UUID,
        database: String,
        schema: String
    ) async throws -> SchemaSnapshot {
        guard let configuration = connections.first(where: { $0.id == connectionID }) else {
            throw AppError.notConnected
        }
        return try await captureSnapshot(configuration: configuration, database: database, schema: schema)
    }

    /// 两侧对比并生成同步脚本：先各抓一张快照，再走 Core 的 `SchemaDiffer.plan`。
    ///
    /// `allowsDrop` **默认 false**：需求原文是"默认不动目标库多出来的表"，
    /// 删除必须由用户显式打开 —— 这里不做任何"聪明"的默认。
    func schemaDiffPlan(
        sourceConnectionID: UUID,
        sourceDatabase: String,
        targetConnectionID: UUID,
        targetDatabase: String,
        schema: String,
        allowsDrop: Bool
    ) async throws -> SchemaSyncPlan {
        guard let sourceConfiguration = connections.first(where: { $0.id == sourceConnectionID }),
              let targetConfiguration = connections.first(where: { $0.id == targetConnectionID }) else {
            throw AppError.notConnected
        }
        let expected = try await captureSnapshot(
            configuration: sourceConfiguration,
            database: sourceDatabase,
            schema: schema
        )
        let actual = try await captureSnapshot(
            configuration: targetConfiguration,
            database: targetDatabase,
            schema: schema
        )
        return SchemaDiffer.plan(
            left: expected,
            right: actual,
            allowDrop: allowsDrop,
            dialect: SQLDialectFactory.make(for: targetConfiguration.dbType)
        )
    }


    /// 抓取当前连接的 ER 图数据（FR-DDL-05）。
    ///
    /// 与 `captureSnapshot` 同一口径取表与列，另外**一次**取回整个 schema 的外键：
    /// 逐表查约束在大 schema 上要发 N 次往返，而外键本来就是"全库一张图"的事。
    /// 视图排除在外 —— 视图没有外键约束，画进去只会让人以为它们参与关系。
    func erDiagram(schema: String, database: String?) async throws -> ERDiagram {
        guard let configuration = selectedConnection else { throw AppError.notConnected }
        let target = database?.isEmpty == false ? database! : queryDatabase(for: configuration)
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        let service = try await ensureService(for: configuration, database: target)

        let listResult = try await runSingleQuery(
            dialect.listTablesQuery(database: target, schema: schema),
            on: service
        )
        let names = listResult.rows.compactMap { row -> String? in
            guard row.indices.contains(0), let name = row[0], !name.isEmpty else { return nil }
            if row.indices.contains(1), let kind = row[1], kind.uppercased().contains("VIEW") { return nil }
            return name
        }.sorted()

        var snapshots: [TableSnapshot] = []
        for name in names {
            guard let structureQuery = dialect.tableStructureQuery(table: name, schema: schema) else { continue }
            let structure = try await runSingleQuery(structureQuery, on: service)
            snapshots.append(
                TableSnapshot(
                    schema: schema,
                    name: name,
                    columns: MetadataService.columnDefinitions(from: structure)
                )
            )
        }

        let foreignKeys = try await runSingleQuery(
            ERDiagramSource.foreignKeysQuery(schema: schema),
            on: service
        )
        return ERDiagramSource.diagram(snapshots: snapshots, foreignKeys: foreignKeys)
    }

    private func captureSnapshot(
        configuration: ConnectionConfig,
        database: String,
        schema: String
    ) async throws -> SchemaSnapshot {
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        let service = try await ensureService(for: configuration, database: database)

        let listResult = try await runSingleQuery(
            dialect.listTablesQuery(database: database, schema: schema),
            on: service
        )
        let names = listResult.rows
            .compactMap { row -> String? in row.indices.contains(0) ? row[0] : nil }
            .sorted()

        var tables: [TableSnapshot] = []
        for name in names {
            guard let structureQuery = dialect.tableStructureQuery(table: name, schema: schema) else { continue }
            let structure = try await runSingleQuery(structureQuery, on: service)
            tables.append(
                TableSnapshot(
                    schema: schema,
                    name: name,
                    columns: MetadataService.columnDefinitions(from: structure)
                )
            )
        }
        return SchemaSnapshot(label: "\(database).\(schema)", tables: tables)
    }

    private func makeMetadataService(
        configuration: ConnectionConfig,
        database: String
    ) async throws -> MetadataService {
        let service = try await ensureService(for: configuration, database: database)
        return MetadataService(
            service: service,
            dialect: SQLDialectFactory.make(for: configuration.dbType),
            databaseName: database,
            serverLabel: serverLabel(for: configuration)
        )
    }

    private func currentDatabaseName(for configuration: ConnectionConfig) -> String {
        serverInfos[configuration.id]?.database ?? configuration.database
    }

    private func serverLabel(for configuration: ConnectionConfig) -> String {
        let name = configuration.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? configuration.endpointDescription : "\(name) · \(configuration.endpointDescription)"
    }

    // MARK: - 服务器 / 数据库选择栏

    /// 枚举当前服务器上当前登录用户可连接的数据库（方言层按权限过滤）。
    func loadDatabases() async {
        guard let configuration = selectedConnection else {
            setIfChanged(\.availableDatabases, [])
            setIfChanged(\.selectedDatabase, nil)
            setIfChanged(\.databaseError, nil)
            return
        }

        setIfChanged(\.isLoadingDatabases, true)
        setIfChanged(\.databaseError, nil)
        defer { setIfChanged(\.isLoadingDatabases, false) }

        do {
            let service = try await ensureService(for: configuration)
            let dialect = SQLDialectFactory.make(for: configuration.dbType)
            let result = try await runSingleQuery(dialect.listDatabasesQuery(), on: service)

            let names = result.rows.compactMap { row -> String? in
                guard let value = row.first ?? nil, !value.isEmpty else { return nil }
                return value
            }
            setIfChanged(\.availableDatabases, names)

            let preferred = selectedDatabase
                ?? serverInfos[configuration.id]?.database
                ?? configuration.database

            if names.isEmpty {
                setIfChanged(\.selectedDatabase, configuration.database)
            } else if names.contains(preferred) {
                setIfChanged(\.selectedDatabase, preferred)
            } else {
                setIfChanged(\.selectedDatabase, serverInfos[configuration.id]?.database ?? names.first)
            }
        } catch {
            // 取消（`.task(id:)` 在连接切换 / 视图重建时必然发生）**不是故障**，不写错误状态。
            guard !CancellationNoise.isNoise(error, taskIsCancelled: Task.isCancelled) else { return }
            setIfChanged(\.availableDatabases, [])
            setIfChanged(\.databaseError, ErrorPresenter.message(for: error))
        }
    }

    /// 当前查询目标数据库：优先用户在上下文栏选择的库。
    private func queryDatabase(for configuration: ConnectionConfig) -> String {
        if let selectedDatabase, !selectedDatabase.isEmpty {
            return selectedDatabase
        }
        return currentDatabaseName(for: configuration)
    }

    private func runSingleQuery(_ sql: String, on service: any DatabaseService) async throws -> QueryResult {
        var lastResult: QueryResult?
        for try await event in service.execute(sql, options: .default) {
            if case .resultSet(let result) = event {
                lastResult = result
            }
        }
        guard let lastResult else {
            // 取消不是"没有结果集"：`.task` 被取消时流会**提前结束**，调用方看到的同样是"什么都没拿到"。
            // 不区分这两者，一次正常的取消就会被显示成「SQL 执行失败：查询没有返回结果集」
            // （实测：启动时 `loadDatabases` 就是这么报出来的）。
            if Task.isCancelled { throw CancellationError() }
            throw AppError.queryFailed(L(.stateQueryNoResultSet))
        }
        return lastResult
    }

    // MARK: - 保存的查询

    func loadSavedQueries() async {
        do {
            savedQueries = try await savedQueryStore.load().sorted { $0.savedAt > $1.savedAt }
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 用 SQL 首行生成一个默认名称，方便直接保存。
    func suggestedQueryName(for tab: QueryTab) -> String {
        let firstLine = tab.sql
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        let cleaned = firstLine
            .replacingOccurrences(of: "--", with: "")
            .trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty {
            return L(.workspaceTabTitle, savedQueries.count + 1)
        }
        return String(cleaned.prefix(30))
    }

    func saveCurrentQuery(for tabID: UUID, name: String) async {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }

        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalName.isEmpty else { return }

        let connectionID = tab.connectionID ?? selectedConnectionID
        let database = tab.database ?? selectedDatabase

        if let index = savedQueries.firstIndex(where: { $0.name == finalName }) {
            savedQueries[index].sql = tab.sql
            savedQueries[index].connectionID = connectionID
            savedQueries[index].database = database
            savedQueries[index].savedAt = Date()
        } else {
            savedQueries.append(
                SavedQuery(
                    name: finalName,
                    connectionID: connectionID,
                    database: database,
                    sql: tab.sql
                )
            )
        }

        savedQueries.sort { $0.savedAt > $1.savedAt }

        do {
            try await savedQueryStore.save(savedQueries)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func loadSavedQuery(_ query: SavedQuery, into tabID: UUID) {
        updateTab(tabID) {
            $0.sql = query.sql
            $0.syntaxCheckMessage = nil
            $0.syntaxCheckFailed = false
        }
    }

    func deleteSavedQuery(_ query: SavedQuery) async {
        savedQueries.removeAll { $0.id == query.id }
        do {
            try await savedQueryStore.save(savedQueries)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    // MARK: - 任务定义（`FR-STD-DB-TASK-001`）

    /// 从盘上读回已保存的任务（启动时与每次改完都过这里 —— 单一读盘点）。
    func loadSQLTasks() async {
        do {
            sqlTasks = try await sqlTaskStore.tasks()
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 这个页签当前绑定的任务（没有就是 `nil`）。执行前判定读它。
    func boundSQLTask(for tabID: UUID) -> SQLTaskDefinition? {
        guard let id = boundSQLTaskIDs[tabID] else { return nil }
        return sqlTasks.first { $0.id == id }
    }

    /// 把当前页签存成一条任务定义：目标库取**当前库**，连接取这个页签的连接。
    ///
    /// - Returns: 失败时的可读原因（成功为 `nil`）—— 界面直接显示它，不再自己拼话术。
    @discardableResult
    func saveCurrentTabAsSQLTask(
        tabID: UUID,
        name: String,
        accessMode: SQLTaskDefinition.AccessMode,
        rowLimitText: String,
        requiresApproval: Bool
    ) async -> String? {
        guard let tab = tabs.first(where: { $0.id == tabID }) else {
            return L(.sqlTaskNoTab)
        }

        let limitText = rowLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        var rowLimit: Int?
        if !limitText.isEmpty {
            guard let value = Int(limitText) else { return L(.sqlTaskRowLimitInvalid) }
            rowLimit = value
        }

        let definition = SQLTaskDefinition(
            name: name,
            sql: tab.sql,
            connectionID: tab.connectionID ?? selectedConnectionID,
            connectionName: selectedConnection?.name,
            targetDatabase: (tab.database ?? selectedDatabase ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            accessMode: accessMode,
            rowLimit: rowLimit,
            requiresApproval: requiresApproval
        )

        do {
            let saved = try await sqlTaskStore.save(definition)
            await loadSQLTasks()
            // 存完就绑上：用户刚写的这条定义，下一次执行的基准就是它。
            boundSQLTaskIDs[tabID] = saved.id
            statusMessage = L(.sqlTaskSavedStatus, saved.name)
            return nil
        } catch {
            let message = ErrorPresenter.message(for: error)
            errorMessage = message
            return message
        }
    }

    /// 载入一条任务（复用）：语句进页签、连接与库切到定义那一对、页签绑上它。
    ///
    /// 三样一起做是刻意的：只把 SQL 贴回来、不切库，下一次执行就会撞上「目标库与定义不符」，
    /// 而那个拒绝本身是对的 —— 不该让用户先撞一次才知道。
    func loadSQLTask(_ task: SQLTaskDefinition, into tabID: UUID) {
        if let connectionID = task.connectionID,
           connections.contains(where: { $0.id == connectionID }) {
            selectedConnectionID = connectionID
        }
        selectedDatabase = task.targetDatabase
        updateTab(tabID) {
            $0.sql = task.sql
            $0.syntaxCheckMessage = nil
            $0.syntaxCheckFailed = false
            $0.statusMessage = L(.sqlTaskLoadedStatus, task.name)
        }
        boundSQLTaskIDs[tabID] = task.id
    }

    /// 解除绑定：之后这个页签按普通 SQL 执行（安全判定仍照旧走 `ExecutionSafety`）。
    func unbindSQLTask(from tabID: UUID) {
        boundSQLTaskIDs[tabID] = nil
    }

    func deleteSQLTask(_ task: SQLTaskDefinition) async {
        do {
            try await sqlTaskStore.delete(id: task.id)
            boundSQLTaskIDs = boundSQLTaskIDs.filter { $0.value != task.id }
            await loadSQLTasks()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    // MARK: - 查询文件（打开 / 保存）

    private static let noConnectionID = UUID()

    private static var textContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .text, .sourceCode]
        if let sql = UTType(filenameExtension: "sql") {
            types.insert(sql, at: 0)
        }
        return types
    }

    // MARK: - 工作区文件监听（实时感知磁盘改动 ⇒ 页签重载）

    /// 工作区文件监听（FSEvents 挂工作区根；来由见 `WorkspaceFileWatcher` 注释）。
    private var workspaceWatcher: WorkspaceFileWatcher?
    /// 当前监听挂在哪个根上（换工作区时据此判断要不要重挂）。
    private var watchedWorkspaceRoot: String?
    /// **磁盘已变、但页签里有未保存改动**的那些页签 —— 界面据此让人决定是否以磁盘为准（**不许悄悄覆盖**）。
    @Published var diskChangedTabIDs: Set<UUID> = []

    /// 开始监听（宿主设好工作区根之后调；**换工作区必须再调一次**）。
    ///
    /// 根没变就什么都不做（`FSEvents` 一条流足够）；根变了先把旧流停掉再挂新的 ——
    /// 否则监听还挂在旧根上：新工作区的外部改动收不到，旧根的改动反而照报。
    func startWorkspaceWatching(root: String) {
        guard watchedWorkspaceRoot != root else { return }
        if watchedWorkspaceRoot != nil {
            workspaceWatcher?.stop()
            workspaceWatcher = nil
            // 旧工作区的「磁盘已变」标记对新工作区没有意义
            diskChangedTabIDs.removeAll()
        }
        let watcher = WorkspaceFileWatcher()
        workspaceWatcher = watcher
        watchedWorkspaceRoot = root
        watcher.start(root: root) { [weak self] paths in
            Task { @MainActor in self?.handleDiskChanges(paths) }
        }
    }

    func stopWorkspaceWatching() {
        workspaceWatcher?.stop()
        workspaceWatcher = nil
        watchedWorkspaceRoot = nil
    }

    /// 磁盘变了一批路径：文件树刷新 + 开着这些文件的页签重载。
    private func handleDiskChanges(_ paths: [String]) {
        // 只重列被改目录（不整树重来 —— `refresh()` 会清掉展开状态，见 `reloadDirectories` 注释）
        WorkspaceStore.shared.reloadDirectories(forChangedPaths: paths)
        // 路径口径要**先解析符号链接再比**：FSEvents 报的是 realpath（`/var/...` 报成 `/private/var/...`），
        // 而页签记的是用户打开时那个写法。逐字符串比会漏判 ⇒ 外部改了盘、干净页签不重载，
        // 看起来正是「外部改动没反映」（2026-11-01 由 `WorkspaceExternalChangeProbeTests` 实测抓出）。
        let changed = Set(paths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path })
        for index in tabs.indices {
            guard let url = tabs[index].fileURL,
                  changed.contains(url.resolvingSymlinksInPath().path) else { continue }
            reloadTab(at: index, force: false)
        }
    }

    /// 重载一个页签的正文（`force` = 人已表态"以磁盘为准"）。
    ///
    /// **有未保存改动就不覆盖** —— 只记进 `diskChangedTabIDs` 由界面问人：丢数据不可逆，
    /// "编辑器看着没变"只是误会，两者不对等，所以这里一律站人这一边。
    func reloadTab(at index: Int, force: Bool) {
        guard tabs.indices.contains(index), let url = tabs[index].fileURL else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let id = tabs[index].id
        if text == tabs[index].sql {
            // 内容没变（多半是**自己刚存的**触发的事件）⇒ 只清标记，不动正文。
            diskChangedTabIDs.remove(id)
            return
        }
        if tabs[index].isDirty && !force {
            diskChangedTabIDs.insert(id)
            statusMessage = L(.workspaceDiskChangedHint, url.lastPathComponent)
            return
        }
        tabs[index].sql = text
        tabs[index].isDirty = false
        diskChangedTabIDs.remove(id)
        statusMessage = L(.workspaceReloadedFromDisk, url.lastPathComponent)
    }

    /// 人确认「以磁盘为准重载这一页签」。
    func reloadTabFromDisk(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        reloadTab(at: index, force: true)
    }

    /// 工作区根**之外**的文件按单文件监听（根之内的由整根监听覆盖，不用重复挂）。
    private func noteOpenedFileForWatching(_ url: URL) {
        guard let watcher = workspaceWatcher else { return }
        let root = WorkspaceStore.shared.rootPath ?? ""
        if !root.isEmpty, url.path.hasPrefix(root) { return }
        watcher.watch(file: url.path)
    }

    /// 打开系统面板选择 SQL / 文本文件，内容载入新页签（默认不绑定连接）。
    func openFileFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.textContentTypes
        panel.message = L(.toolbarOpenFileHelp)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFile(at: url)
    }

    func openFile(at url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let tab = QueryTab(
                title: url.lastPathComponent,
                sql: text,
                fileURL: url
            )
            tabs.append(tab)
            selectedTabID = tab.id
            statusMessage = url.lastPathComponent
            noteOpenedFileForWatching(url)
        } catch {
            errorMessage = L(.fileOpenFailed, error.localizedDescription)
        }
    }

    /// 保存当前页签：`forceSaveAs` 为 false 时优先写回原文件，否则弹「另存为」。
    func saveCurrentFile(for tabID: UUID, forceSaveAs: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }

        if !forceSaveAs, let url = tabs[index].fileURL {
            writeFile(tabAt: index, to: url)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = Self.textContentTypes
        panel.nameFieldStringValue = tabs[index].fileURL?.lastPathComponent
            ?? "\(tabs[index].title).sql"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeFile(tabAt: index, to: url)
    }

    private func writeFile(tabAt index: Int, to url: URL) {
        do {
            try tabs[index].sql.write(to: url, atomically: true, encoding: .utf8)
            tabs[index].fileURL = url
            tabs[index].title = url.lastPathComponent
            tabs[index].isDirty = false
            statusMessage = L(.fileSaved, url.lastPathComponent)
        } catch {
            errorMessage = L(.fileSaveFailed, error.localizedDescription)
        }
    }

    /// 「未绑定连接」在服务器下拉里的占位 id。
    static var unboundConnectionID: UUID { noConnectionID }

    func newQueryTab() {
        // **先切到数据库区再建页签**（2026-10-02 需求提出者实测：在工作区里点「新建查询」，
        // 页签建好了、界面还停在工作区 ⇒ 看起来像"点了没反应"）。
        // 放在这一个入口里而不是菜单按钮上：菜单 / 命令面板 / 界面按钮最终都走这里。
        selectActivityItem(.database)
        let tab = QueryTab(title: L(.workspaceTabTitle, tabNumbers.next()))
        tabs.append(tab)
        selectedTabID = tab.id
    }

    /// 关闭页签（详设 `T-4.4-07` / `T-4.4-08`）：**不再静默 return** ——
    /// 执行中与「只剩一个」都给出理由；有未保存改动时挂起待确认，确认后先落快照再关。
    @discardableResult
    func closeTab(_ tabID: UUID) -> TabCloseDecision {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return .close }
        let decision = TabClosePolicy.decide(
            isExecuting: tab.isExecuting,
            isDirty: tab.isDirty,
            tabCount: tabs.count
        )
        switch decision {
        case .refuseLastTab:
            statusMessage = L(.tabCloseRefusedLastTab)
        case .refuseExecuting:
            statusMessage = L(.tabCloseRefusedExecuting)
        case .needsConfirmation:
            pendingCloseTabID = tabID
            statusMessage = L(.tabCloseConfirmUnsaved)
        case .close:
            performCloseTab(tabID)
        }
        return decision
    }

    /// 未保存关闭被确认后调用：**先落快照，再关**（快照可在内存里找回）。
    func confirmClosePendingTab() {
        guard let tabID = pendingCloseTabID else { return }
        pendingCloseTabID = nil
        if let tab = tabs.first(where: { $0.id == tabID }) {
            closedTabSnapshots.push(
                ClosedTabSnapshot(id: tab.id, title: tab.title, sql: tab.sql)
            )
        }
        performCloseTab(tabID)
    }

    /// 取消未保存关闭：什么都不做，页签留在原地。
    func cancelClosePendingTab() {
        pendingCloseTabID = nil
    }

    private func performCloseTab(_ tabID: UUID) {
        // **提交点**（队列 `L-148`）：关页签前把编辑器缓冲里的草稿写回权威副本 ——
        // 否则"页签内容"在关闭这一刻就丢了最后一段编辑（保存/持久化读的是权威副本）。
        commitEditorDraft(for: tabID)
        EditorCommandCenter.shared.forgetSelection(tabID: tabID)
        tabs.removeAll { $0.id == tabID }
        // 页签没了，绑定也该跟着没：留着的 id 会让「同一 tabID」在重建后莫名其妙地重新绑上旧任务。
        boundSQLTaskIDs[tabID] = nil
        if selectedTabID == tabID {
            selectedTabID = tabs.last?.id
        }
    }

    /// R-21：把结果区筛出的条件变成 `WHERE` **注入编辑器**（只改文本，**绝不自动执行**）。
    ///
    /// 拿不准就明说而不是硬插：已有 `WHERE`、多条语句、含 UNION 时都不动原语句，
    /// 只给一条提示 —— 悄悄改掉用户的查询比不做更糟。
    func applyClientFilterWhere(_ whereClause: String, for tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }

        switch SQLFilterInjector.inject(whereClause: whereClause, into: tabs[index].sql) {
        case .injected(let newSQL):
            updateSQL(newSQL, for: tabID)
            statusMessage = L(.resultFilterWhereInjected)
        case .alreadyHasWhere:
            statusMessage = L(.resultFilterWhereAlreadyPresent)
        case .unsupported(let reason):
            statusMessage = L(.resultFilterWhereFailed, reason)
        }
    }

    // MARK: - 事务模式（FR-EXEC-15）

    /// 当前选中的查询页签（浏览器页签没有 SQL，不参与事务界面）。
    var activeQueryTab: QueryTab? {
        if let selectedTabID, let tab = tabs.first(where: { $0.id == selectedTabID }) {
            return tab
        }
        return tabs.last
    }

    /// 当前页签所在连接上的事务状态；连接未知时为 nil（界面据此隐藏事务控件）。
    var activeTransactionSession: TransactionSession? {
        guard let tab = activeQueryTab, let key = transactionKey(for: tab) else { return nil }
        return transactionSessions[key] ?? TransactionSession()
    }

    /// 当前页签的事务模式（默认自动提交）。
    var activeTransactionMode: TransactionMode { activeTransactionSession?.mode ?? .autoCommit }

    /// 当前页签的事务阶段。
    var activeTransactionPhase: TransactionPhase { activeTransactionSession?.phase ?? .idle }

    private func transactionKey(for tab: QueryTab) -> ServiceKey? {
        guard let connectionID = tab.connectionID,
              let configuration = connections.first(where: { $0.id == connectionID }) else { return nil }
        let database = tab.database?.isEmpty == false ? tab.database! : queryDatabase(for: configuration)
        return ServiceKey(connectionID: connectionID, database: database)
    }

    /// 切换自动提交 / 手工事务。有进行中的事务时**拒绝切回自动提交**（静默提交与静默丢弃都是事故）。
    func setTransactionMode(_ mode: TransactionMode, for tabID: UUID) async {
        guard let tab = tabs.first(where: { $0.id == tabID }),
              let key = transactionKey(for: tab) else { return }

        var session = transactionSessions[key] ?? TransactionSession()
        switch session.setMode(mode) {
        case .refuse(let refusal):
            statusMessage = transactionRefusalMessage(refusal)
        case .nothing, .begin, .commit, .rollback:
            transactionSessions[key] = session
            statusMessage = session.mode.isManual ? L(.transactionModeManual) : L(.transactionModeAuto)
        }
    }

    /// 提交手工事务。
    func commitTransaction(for tabID: UUID) async {
        await performTransactionCommand(for: tabID) { $0.commit() }
    }

    /// 回滚手工事务。
    func rollbackTransaction(for tabID: UUID) async {
        await performTransactionCommand(for: tabID) { $0.rollback() }
    }

    /// 事务命令的统一执行路径：**先由状态机判定能不能做**，再发命令，再按结果更新界面。
    private func performTransactionCommand(
        for tabID: UUID,
        _ decide: (inout TransactionSession) -> TransactionAction
    ) async {
        guard let tab = tabs.first(where: { $0.id == tabID }),
              let key = transactionKey(for: tab),
              let configuration = connections.first(where: { $0.id == key.connectionID }) else { return }

        var session = transactionSessions[key] ?? TransactionSession()
        let action = decide(&session)
        switch action {
        case .refuse(let refusal):
            statusMessage = transactionRefusalMessage(refusal)
            return
        case .commit, .rollback:
            // 先把状态落到内存，再发命令：命令失败时会改写回去。
            transactionSessions[key] = session
            do {
                let service = try await ensureService(for: configuration, database: key.database)
                if case .commit = action {
                    try await service.commit()
                    statusMessage = L(.transactionCommitted)
                } else {
                    try await service.rollback()
                    statusMessage = L(.transactionRolledBack)
                }
            } catch {
                // 命令没成功：状态退回「事务已结束」，别让界面显示「已提交」而库里其实没有。
                session.serverCommandFailed()
                transactionSessions[key] = session
                errorMessage = ErrorPresenter.message(for: error)
            }
        case .begin, .nothing:
            transactionSessions[key] = session
        }
    }

    private func transactionRefusalMessage(_ refusal: TransactionRefusal) -> String {
        switch refusal {
        case .notInManualMode: return L(.transactionRefusedNotManual)
        case .nothingToDo: return L(.transactionRefusedNothing)
        case .aborted: return L(.transactionRefusedAborted)
        case .hasOpenTransaction: return L(.transactionRefusedOpen)
        }
    }

    /// 切换连接 / 数据库前，把**别处**未提交的事务回滚掉并说明。
    ///
    /// 为什么不是自动提交：未提交的事务在新连接上根本不存在，替用户提交是数据事故；
    /// 回滚 + 明说是唯一可预期的处置。**绝不静默丢弃**。
    private func settleTransactions(leaving connectionID: UUID?) {
        for key in Array(transactionSessions.keys) {
            guard var session = transactionSessions[key], session.phase.isOpen else { continue }
            if let connectionID, key.connectionID == connectionID { continue }
            guard session.connectionDidChange() == .rollback else { continue }
            transactionSessions[key] = session
            let service = services[key]
            Task { try? await service?.rollback() }
            statusMessage = L(.transactionRolledBackOnLeave)
        }
    }

    func updateSQL(_ sql: String, for tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].sql = sql
        // 改动 SQL 后，上一次的检查结果不再有效。
        tabs[index].syntaxCheckMessage = nil
        tabs[index].syntaxCheckFailed = false
        // 仅文件页签展示「未保存」标记。
        if tabs[index].fileURL != nil {
            tabs[index].isDirty = true
        }
    }

    /// 服务器端语法检查：对可 EXPLAIN 的语句执行 `EXPLAIN <sql>`。
    /// EXPLAIN 只做解析/规划，不会真正执行 INSERT / UPDATE / DELETE。
    func checkSyntax(for tabID: UUID) async {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == tabID }) else { return }

        guard let configuration = selectedConnection else {
            updateTab(tabID) {
                $0.syntaxCheckFailed = true
                $0.syntaxCheckMessage = L(.stateSelectConnectionFirst)
            }
            return
        }

        let sql = tabs[tabIndex].sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else {
            updateTab(tabID) {
                $0.syntaxCheckFailed = true
                $0.syntaxCheckMessage = L(.stateSQLEmpty)
            }
            return
        }

        updateTab(tabID) {
            $0.syntaxCheckFailed = false
            $0.syntaxCheckMessage = L(.stateChecking)
        }

        do {
            let targetDatabase = queryDatabase(for: configuration)
            let service = try await ensureService(for: configuration, database: targetDatabase)
            let statements = StatementSplitter(databaseType: configuration.dbType).split(sql)

            var checked = 0
            var skipped = 0
            var failures: [String] = []

            for statement in statements {
                let text = statement.sql.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                let firstWord = firstKeyword(in: text)

                guard ["SELECT", "INSERT", "UPDATE", "DELETE", "WITH", "VALUES", "TABLE"].contains(firstWord) else {
                    skipped += 1
                    continue
                }

                do {
                    for try await _ in service.execute("EXPLAIN \(text)", options: .default) {}
                    checked += 1
                } catch {
                    failures.append(L(.stateCheckFailedItem, statement.index + 1, ErrorPresenter.message(for: error)))
                }
            }

            if failures.isEmpty {
                var message = L(.stateCheckPassed, checked)
                if skipped > 0 {
                    message += L(.stateCheckSkipped, skipped)
                }
                updateTab(tabID) {
                    $0.syntaxCheckFailed = false
                    $0.syntaxCheckMessage = message
                }
            } else {
                var message = failures.prefix(3).joined(separator: "\n")
                if failures.count > 3 {
                    message += L(.stateCheckMoreErrors, failures.count - 3)
                }
                updateTab(tabID) {
                    $0.syntaxCheckFailed = true
                    $0.syntaxCheckMessage = message
                }
            }
        } catch {
            let message = ErrorPresenter.message(for: error)
            updateTab(tabID) {
                $0.syntaxCheckFailed = true
                $0.syntaxCheckMessage = message
            }
        }
    }

    /// 记一条**执行回执**（`FR-STD-DB-TASK-003` 的**唯一写入口**）。
    ///
    /// 为什么收成一处：回执有六处出口（成功 / 失败 / 取消 / 安全判定拦下 / 任务定义拦下 / 事务态拦下），
    /// 各写一遍必然有一处漏字段 —— 漏的那一处正是需求 ③ 的否定面（「失败也有回执，不因报错丢失」）。
    ///
    /// 脱敏在 `ExecutionReceipt.init` 里做（原文根本不进那个结构），所以这里照原样传 SQL 与错误原文。
    private func recordReceipt(
        for tabID: UUID,
        configuration: ConnectionConfig,
        database: String,
        sql: String,
        scopeTitle: String,
        statementCount: Int,
        outcome: ExecutionOutcome,
        affectedRows: Int?,
        results: ExecutionReceipt.ResultReading,
        executedAt: Date,
        duration: TimeInterval,
        errorText: String?
    ) {
        let receipt = ExecutionReceipt(
            executedAt: executedAt,
            duration: duration,
            connectionName: configuration.name,
            database: database,
            scopeTitle: scopeTitle,
            statementCount: statementCount,
            outcome: outcome,
            affectedRows: affectedRows,
            results: results,
            sql: sql,
            errorText: errorText
        )
        updateTab(tabID) { $0.receiptLog.append(receipt) }
    }

    /// 从 UI 触发执行：把执行放到可跟踪的 Task 里，「停止」按钮才能取消它。
    func startQuery(for tabID: UUID) {
        guard executionTasks[tabID] == nil else { return }

        // 句柄先于任务建立：**用户可能在连接/排队阶段就按停止**，
        // 那时也必须能记住"这次执行已被取消，别跑了"。
        executionHandles[tabID] = ExecutionHandle()

        let task = Task { @MainActor in
            await executeQuery(for: tabID)
            executionTasks[tabID] = nil
            executionHandles[tabID] = nil
        }
        executionTasks[tabID] = task
    }

    /// - Parameter sqlOverride: 参数绑定后的语句（FR-EXEC-17）。传了就执行它，
    ///   **不改写编辑器** —— 占位符是可复用的模板，不该被一次取值覆盖掉。
    /// - Parameter runningSource: 本次真的要跑的那一段的来源。只在高危确认回来时传
    ///   （`sqlOverride` + 批准过的那一份），让 Output 的范围交代说的是**实际跑的这一份**，
    ///   而不是此刻从编辑器重新解析出来的另一份。
    func executeQuery(
        for tabID: UUID,
        bypassingSafetyCheck: Bool = false,
        sqlOverride: String? = nil,
        runningSource: ExecutionScope.Source? = nil
    ) async {
        // **提交点**（队列 `L-148`）：执行读的是权威副本 `tab.sql`，而打字先落在编辑器缓冲里
        // ⇒ 不先提交就会执行到"最后一次提交之前"的 SQL。
        commitEditorDraft(for: tabID)
        guard let tabIndex = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        guard !tabs[tabIndex].isExecuting else { return }

        guard let configuration = selectedConnection else {
            updateTab(tabID) {
                $0.errorMessage = L(.stateSelectConnectionFirst)
                $0.statusMessage = L(.stateNotExecuted)
            }
            return
        }

        // 执行目标判定（FR-EXEC-14，2026-09-27 需求提出者拍板的口径）：
        // **有选区就跑选中的那段，没选区就跑整篇** —— 没有"运行范围"开关要用户先设一次。
        // 后续的连接、Safe Mode 判定、执行全都基于这一段。
        //
        // 选区取**显示中的编辑器**（`selectionForExecution`），不是那份缓存记录：
        // 2026-09-27 人工点验现场 —— 需求提出者选中 `DELETE` 执行，到服务器的却是脚本里
        // 第 1 条 `SELECT`（数据库侧 `n_tup_del = 0` 可证那条 DELETE 从未到达服务器），
        // 缓存记录被重建 / 外部文本同步冲掉过。**用户眼里高亮的那一段才算数。**
        let resolution = ExecutionScope.resolve(
            text: tabs[tabIndex].sql,
            selection: EditorCommandCenter.shared.selectionForExecution(tabID: tabID)
        )
        if let mismatch = EditorCommandCenter.shared.lastSelectionMismatch {
            // 判据看不见的时序，只能在现场留痕：缓存说 a+b，实际是 c+d。
            StartupLog.write(
                "选区缓存与编辑器实际不一致：缓存 \(mismatch.recorded.location)+\(mismatch.recorded.length)"
                + " / 实际 \(mismatch.live.location)+\(mismatch.live.length) —— 已按实际执行"
            )
        }
        if let issue = resolution.issue {
            updateTab(tabID) {
                $0.errorMessage = message(forRunScopeIssue: issue)
                $0.statusMessage = L(.stateNotExecuted)
            }
            return
        }

        let sql = (sqlOverride ?? resolution.sql).trimmingCharacters(in: .whitespacesAndNewlines)

        // 查询参数（FR-EXEC-17）：有占位符就先弹面板填值，**不在没填值的情况下执行**。
        // `sqlOverride != nil` 说明值已经填过一轮了，不会再弹（避免自激）。
        if sqlOverride == nil, SQLParameters.hasParameters(sql) {
            pendingQueryParameters = PendingQueryParameters(tabID: tabID, sql: sql)
            isQueryParameterSheetPresented = true
            return
        }
        guard !sql.isEmpty else {
            updateTab(tabID) {
                $0.errorMessage = L(.stateSQLEmpty)
                $0.statusMessage = L(.stateNotExecuted)
            }
            return
        }

        // 高危语句保护（FR-EXEC-16）：纯客户端静态判定，拦下后不发起任何连接。
        // 用户确认后走 `bypassingSafetyCheck: true` 再回来，避免重复弹窗。
        if !bypassingSafetyCheck {
            let decision = ExecutionSafety.check(
                sql: sql,
                databaseType: configuration.dbType,
                policy: executionSafetyPolicy
            )
            if case .needsConfirmation = decision {
                pendingExecution = PendingExecution(tabID: tabID, sql: sql, decision: decision, source: resolution.source)
                return
            }
            // 只读连接的拒绝**不走确认流程**：它不是"要不要冒险"，而是"这个连接不写"。
            // 若把它塞进确认弹窗，用户点一次「仍然执行」就等于关掉了只读标记。
            if case .refused(let reasons, let statements) = decision {
                let detail = (reasons + statements.map { "· " + $0 }).joined(separator: "\n")
                updateTab(tabID) { $0.errorMessage = detail }
                statusMessage = reasons.first ?? L(.safetyReadOnlyRefused)
                // 回执（`FR-STD-DB-TASK-003`）：**被拦下也是一次尝试** —— 一条语句都没发出去，
                // 因此里读作「未发出」（`.refused`）而不是失败，更不是成功。
                recordReceipt(
                    for: tabID,
                    configuration: configuration,
                    database: queryDatabase(for: configuration),
                    sql: sql,
                    scopeTitle: resolution.source.title,
                    statementCount: StatementSplitter(databaseType: configuration.dbType).split(sql).count,
                    outcome: .refused,
                    affectedRows: nil,
                    results: ExecutionReceipt.ResultReading(),
                    executedAt: Date(),
                    duration: 0,
                    errorText: detail
                )
                return
            }
        }

        let targetDatabase = queryDatabase(for: configuration)

        // 任务定义（`FR-STD-DB-TASK-001`）：这个页签绑着一条保存过的任务时，
        // **先逐项核对定义与这次的实际参数**，再谈安全判定。
        //
        // 位置刻意在这里（不是更早）：`targetDatabase` 是这次真要连的库，判定必须拿它比；
        // 又不能更晚 —— 晚了就已经建了连接、发了语句，那时候拒绝只是事后诸葛亮。
        // 拒绝**不经过确认流程**：库不符 / 只读任务里出现写语句都不是「要不要冒险」，
        // 与 `ExecutionSafetyPolicy.isReadOnly` 同一条道理（能点「仍然执行」就等于没拦）。
        if let task = boundSQLTask(for: tabID) {
            let planned = SQLTaskExecution(
                connectionID: configuration.id,
                database: targetDatabase,
                accessMode: configuration.isReadOnly ? .readOnly : .writable,
                // 本侧没有「执行时放宽上限」的入口，所以这里带的就是定义自己那一条；
                // 判定口仍按「更松即拒」写 —— 让 CLI / 以后的调度器走同一套时不会漏。
                rowLimit: task.rowLimit,
                sql: sql
            )
            switch SQLTaskGuard.check(task: task, execution: planned, databaseType: configuration.dbType) {
            case .allow:
                break

            case .refused(let reasons, let statements):
                let detail = (reasons + statements.map { "· " + $0 }).joined(separator: "\n")
                updateTab(tabID) {
                    $0.errorMessage = detail
                    $0.statusMessage = L(.sqlTaskRefusedStatus, task.name)
                }
                // 回执同 A：定义与实际参数不一致 ⇒ 一条语句都没发，里读「未发出」。
                recordReceipt(
                    for: tabID,
                    configuration: configuration,
                    database: targetDatabase,
                    sql: sql,
                    scopeTitle: resolution.source.title,
                    statementCount: StatementSplitter(databaseType: configuration.dbType).split(sql).count,
                    outcome: .refused,
                    affectedRows: nil,
                    results: ExecutionReceipt.ResultReading(),
                    executedAt: Date(),
                    duration: 0,
                    errorText: detail
                )
                return

            case .needsApproval(let reasons, let statements):
                // 已经批准过一轮（`bypassingSafetyCheck`）就不再问第二次；拒绝那一档上面已挡掉。
                guard !bypassingSafetyCheck else { break }
                pendingExecution = PendingExecution(
                    tabID: tabID,
                    sql: sql,
                    // 复用同一张确认弹窗：用户看到的是**任务要求审批**的理由与语句，不是伪造的风险点。
                    decision: .needsConfirmation(reasons: reasons, findings: [], statements: statements),
                    source: resolution.source
                )
                return
            }
        }

        updateTab(tabID) {
            $0.isExecuting = true
            $0.errorMessage = nil
            // **Output 日志按「每次执行」重来**（2026-09-27 人工点验，需求提出者原话：
            // 「Output 应该只有当前执行的 query 的结果，不能一直往后追加」）。
            // ⚠️ 清空必须排在下一条 `statusMessage` 赋值**之前** —— `statusMessage` 的 `didSet`
            // 会往日志里追加，顺序反了会把本次执行的第一行（"正在连接…"）也一起清掉。
            // 交付的是**本次执行**的流水；跨执行的追溯交给查询历史与归档，不靠这块面板堆着。
            $0.outputLog = []
            $0.statusMessage = L(.stateConnecting, configuration.endpointDescription, targetDatabase)
            $0.results = []
            $0.resultSummaries = []
            $0.selectedResultIndex = 0
            $0.connectionID = configuration.id
            $0.database = targetDatabase
        }

        // **这一跑跑的是哪一段**必须写在明面上（2026-09-27 人工点验现场：需求提出者选中
        // `delete` 执行，实际跑的是脚本第 1 条 `select`，而界面上没有一句话交代范围 ⇒
        // 一次"静默跑错段落"没有任何痕迹）。三件事一起说清：范围、本次几条、脚本共几条。
        let scopeSplitter = StatementSplitter(databaseType: configuration.dbType)
        let scopeSummary = ExecutionScopeSummary(
            scopeName: (runningSource ?? resolution.source).title,
            runningStatements: scopeSplitter.split(sql).count,
            scriptStatements: scopeSplitter.split(tabs[tabIndex].sql).count
        )
        updateTab(tabID) {
            $0.statusMessage = L(.stateRunScope, scopeSummary.scopeName, scopeSummary.runningStatements)
        }
        if scopeSummary.skipsStatements {
            updateTab(tabID) {
                $0.statusMessage = L(.stateRunScopeSkipped, scopeSummary.scriptStatements)
            }
        }

        let executionStart = Date()

        // 归档要写「影响行数」，在执行过程中累计一次（原先只在事件里即时展示）。
        // 声明在 `do` 之外：**失败分支也要用到它**（出错前可能已经写过几行）。
        //
        // 计数收进 AffectedRowsTally：**全工程唯一的计数入口**。R-32 的教训是
        // 「DML 同时发两个事件、上层两条分支都累加」⇒ 落盘行数翻倍，而现在
        // 通道只剩 `.resultSet(affectedRows:)` 一条，且只有 absorb 一处会加。
        var affectedTally = AffectedRowsTally()

        // 回执的结果集读数（`FR-STD-DB-TASK-003`）：与 Output 的逐条摘要**分开累计** ——
        // 回执要的是「这一跑一共返回了什么」，Output 是逐条流水。
        var receiptRows = 0
        var receiptColumns = 0
        var receiptTruncated = 0
        // 结果集条数也要在 `do` 之外 —— **失败分支的回执同样要报「这一跑返回了几个结果集」**
        // （出错前可能已经成功返回过几条）。
        var resultCount = 0

        // 事务上下文按「连接 + 数据库」归属（FR-EXEC-15）。
        // 声明在 `do` 之外：失败分支也要用它把事务标记成失败态。
        let transactionKey = ServiceKey(connectionID: configuration.id, database: targetDatabase)

        do {
            let service = try await ensureService(for: configuration, database: targetDatabase)
            updateTab(tabID) { $0.statusMessage = L(.stateExecuting) }

            var currentStatementIndex = 0

            let handle = executionHandles[tabID] ?? ExecutionHandle()
            executionHandles[tabID] = handle

            // 事务时序（FR-EXEC-15）：手工模式下**第一条语句前**才发 BEGIN（懒开启），
            // 失败的事务里直接拒绝继续执行 —— 否则用户会看到一条难懂的
            // 「current transaction is aborted」服务端错误。
            var transactionSession = transactionSessions[transactionKey] ?? TransactionSession()
            let transactionAction = transactionSession.prepareStatement()
            if case .refuse(let refusal) = transactionAction {
                transactionSessions[transactionKey] = transactionSession
                let refusalMessage = transactionRefusalMessage(refusal)
                updateTab(tabID) {
                    $0.isExecuting = false
                    $0.errorMessage = refusalMessage
                    $0.statusMessage = L(.stateNotExecuted)
                }
                // 回执：事务已进入失败态 ⇒ 这次一条语句都没发出去（`.refused`，不是失败）。
                recordReceipt(
                    for: tabID,
                    configuration: configuration,
                    database: targetDatabase,
                    sql: sql,
                    scopeTitle: (runningSource ?? resolution.source).title,
                    statementCount: scopeSummary.runningStatements,
                    outcome: .refused,
                    affectedRows: nil,
                    results: ExecutionReceipt.ResultReading(),
                    executedAt: executionStart,
                    duration: Date().timeIntervalSince(executionStart),
                    errorText: refusalMessage
                )
                return
            }
            transactionSessions[transactionKey] = transactionSession
            if case .begin = transactionAction {
                do {
                    try await service.beginTransaction()
                } catch {
                    // BEGIN 没成功 = 没有事务：状态退回 idle，别让界面显示「事务进行中」。
                    transactionSession.serverCommandFailed()
                    transactionSessions[transactionKey] = transactionSession
                    let beginMessage = L(.transactionBeginFailed, ErrorPresenter.message(for: error))
                    updateTab(tabID) {
                        $0.isExecuting = false
                        $0.errorMessage = beginMessage
                        $0.statusMessage = L(.stateNotExecuted)
                    }
                    // 回执：BEGIN 失败 = 已经连上了但没跑起来 ⇒ `.failed`（不是 `.refused`）。
                    recordReceipt(
                        for: tabID,
                        configuration: configuration,
                        database: targetDatabase,
                        sql: sql,
                        scopeTitle: (runningSource ?? resolution.source).title,
                        statementCount: scopeSummary.runningStatements,
                        outcome: .failed,
                        affectedRows: nil,
                        results: ExecutionReceipt.ResultReading(),
                        executedAt: executionStart,
                        duration: Date().timeIntervalSince(executionStart),
                        errorText: beginMessage
                    )
                    return
                }
            }

            for try await event in service.execute(sql, options: .default, handle: handle) {
                // 页签可能在执行过程中被关闭；此时停止更新，避免下标越界。
                guard tabs.contains(where: { $0.id == tabID }) else { break }

                switch event {
                case .started(let index):
                    currentStatementIndex = index
                    updateTab(tabID) { $0.statusMessage = L(.stateExecutingStatement, index + 1) }

                case .resultSet(let result):
                    resultCount += 1
                    let statementNumber = currentStatementIndex + 1
                    // 有表格的结果集：行 × 列 交给 Result 页签的表头，**不进 Output 日志**，
                    // 否则两个页签会重复同一件事。没有表格的（影响行数 / 无结果集）才进日志，
                    // 因为结果表里根本不会出现它们。
                    affectedTally.absorb(event)
                receiptRows += result.rowCount
                receiptColumns = max(receiptColumns, result.columnCount)
                if result.isTruncated { receiptTruncated += 1 }
                    let isTabular = result.affectedRows == nil && result.columnCount > 0
                    let logLine: String?
                    if let affected = result.affectedRows {
                        logLine = L(.stateStatementAffectedRows, statementNumber, affected)
                    } else if result.columnCount == 0 {
                        logLine = L(.stateStatementNoResultSet, statementNumber)
                    } else {
                        logLine = nil
                    }
                    var provenance = L(.stateStatementResult, statementNumber, result.rowCount, result.columnCount)
                    if result.isTruncated {
                        // 摘要与状态栏都写明「被截断」：归档、日志、界面三处口径一致（R-33）。
                        provenance += " · \(L(.resultTruncatedTag))"
                    }
                    updateTab(tabID) {
                        $0.results.append(result)
                        $0.resultSummaries.append(isTabular ? provenance : "")
                        $0.selectedResultIndex = $0.results.count - 1
                        if result.isTruncated {
                            $0.statusMessage = L(.resultTruncated, result.truncationLimit ?? result.rowCount)
                        } else if let logLine {
                            $0.statusMessage = logLine
                        }
                    }

                case .notice(let message):
                    updateTab(tabID) { $0.statusMessage = message }

                case .finished(let summary):
                    let duration = String(format: "%.3f", summary.duration)
                    let finishedMessage: String
                    if summary.statementCount == 0 {
                        finishedMessage = L(.stateFinishedNoResult, duration)
                    } else if resultCount > 1 {
                        finishedMessage = L(.stateFinishedMulti, summary.statementCount, resultCount, duration)
                    } else {
                        finishedMessage = L(.stateFinished, summary.statementCount, duration)
                    }
                    updateTab(tabID) { $0.statusMessage = finishedMessage }
                }
            }

            if resultCount == 0 {
                updateTab(tabID) { $0.statusMessage = L(.stateFinishedEmpty) }
            }

            // 影响行数上限（`FR-STD-DB-TASK-001`）：**执行之后**才量得到读数。
            // 超了 / 量不到都要当场说 —— 已经执行的那部分不会被撤销，
            // 而「没有读数」更不许当「动了 0 行」（`unmeasured` 与 `within(0)` 是两条结论）。
            if let task = boundSQLTask(for: tabID) {
                let verdict = SQLTaskGuard.rowVerdict(limit: task.rowLimit, actual: affectedTally.value)
                if !verdict.message.isEmpty {
                    updateTab(tabID) { $0.errorMessage = verdict.message }
                }
            }

            // 取消必须在历史里留痕，且**不得记成成功**（R-31）。
            // 原先这里无条件写 `succeeded: true`：取消若发生在流正常结束的瞬间
            // （或驱动没把取消变成抛错），归档里就留下一条"成功执行"的假记录 ——
            // 归档是审计依据，假成功比失败更糟。
            let cancelled = Task.isCancelled
            // 回执（`FR-STD-DB-TASK-003`）：这一跑的**四项读数 + 执行时刻**都记下来。
            // 取消这一档也走这里 —— 回执面上它读「已取消」，与归档里 `succeeded: false` 同一条口径。
            recordReceipt(
                for: tabID,
                configuration: configuration,
                database: targetDatabase,
                sql: sql,
                scopeTitle: (runningSource ?? resolution.source).title,
                statementCount: scopeSummary.runningStatements,
                outcome: cancelled ? .cancelled : .succeeded,
                affectedRows: affectedTally.value,
                results: ExecutionReceipt.ResultReading(
                    resultSetCount: resultCount,
                    rowCount: receiptRows,
                    columnCount: receiptColumns,
                    truncatedCount: receiptTruncated
                ),
                executedAt: executionStart,
                duration: Date().timeIntervalSince(executionStart),
                errorText: cancelled ? L(.stateCancelled) : nil
            )
            await recordHistory(
                sql: sql,
                connectionID: configuration.id,
                duration: Date().timeIntervalSince(executionStart),
                succeeded: !cancelled,
                affectedRows: affectedTally.value,
                note: cancelled ? L(.stateCancelled) : nil
            )
        } catch {
            // 取消同样留痕（`succeeded: false` + 可读原因），不再"什么都不记"。
            let cancelled = Task.isCancelled || error is CancellationError
            // FR-CONN-18 判据 ②：隧道断了要**指明是隧道问题**，不能只报「连接已断开」——
            // 归因与「作废这条连接」都在 `tunnelAwareMessage` 一处（判据在 `SSHTunnelDiagnosis`）。
            let message = cancelled
                ? L(.stateCancelled)
                : tunnelAwareMessage(ErrorPresenter.message(for: error), configuration: configuration)
            updateTab(tabID) {
                if cancelled {
                    $0.statusMessage = message
                } else {
                    $0.errorMessage = message
                    $0.statusMessage = L(.stateExecutionFailed)
                }
            }
            // 需求 ③：**失败也有回执**（不因报错丢失）—— 错误原文照实带上（构造时脱敏）。
            recordReceipt(
                for: tabID,
                configuration: configuration,
                database: targetDatabase,
                sql: sql,
                scopeTitle: (runningSource ?? resolution.source).title,
                statementCount: scopeSummary.runningStatements,
                outcome: cancelled ? .cancelled : .failed,
                affectedRows: affectedTally.value,
                results: ExecutionReceipt.ResultReading(
                    resultSetCount: resultCount,
                    rowCount: receiptRows,
                    columnCount: receiptColumns,
                    truncatedCount: receiptTruncated
                ),
                executedAt: executionStart,
                duration: Date().timeIntervalSince(executionStart),
                errorText: message
            )
            await recordHistory(
                sql: sql,
                connectionID: configuration.id,
                duration: Date().timeIntervalSince(executionStart),
                succeeded: false,
                affectedRows: affectedTally.value,
                note: message
            )

            // 手工事务里的失败（含取消）会让事务进入失败态：之后只接受回滚。
            var session = transactionSessions[transactionKey] ?? TransactionSession()
            session.statementFailed(reason: message)
            transactionSessions[transactionKey] = session
        }

        if Task.isCancelled {
            updateTab(tabID) { $0.statusMessage = L(.stateCancelled) }
        }

        updateTab(tabID) { $0.isExecuting = false }
    }

    func selectResult(_ index: Int, for tabID: UUID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        guard tabs[tabIndex].results.indices.contains(index) else { return }
        tabs[tabIndex].selectedResultIndex = index
    }

    func cancelQuery(for tabID: UUID) async {
        // ① 先停本地的消费与生产（R-29：生产端会随消费者终止，剩余语句不再下发）。
        executionTasks[tabID]?.cancel()

        guard let tab = tabs.first(where: { $0.id == tabID }),
              let connectionID = tab.connectionID,
              let configuration = connections.first(where: { $0.id == connectionID }) else {
            return
        }

        let database = tab.database ?? currentDatabaseName(for: configuration)
        let key = ServiceKey(connectionID: connectionID, database: database)
        guard let service = services[key] else { return }

        // ② 再定向地把取消下发到服务端，并**如实显示结果** ——
        // 拿不到后端 PID 时以前是静默返回，用户看到"已取消"而查询还在跑（R-30）。
        let handle = executionHandles[tabID] ?? ExecutionHandle()
        switch await service.cancel(handle) {
        case .cancelled, .cancelledBeforeStart:
            updateTab(tabID) { $0.statusMessage = L(.stateCancelled) }
        case .notActive:
            updateTab(tabID) { $0.statusMessage = L(.stateCancelAlreadyDone) }
        case .failed(let reason):
            updateTab(tabID) {
                $0.statusMessage = L(.stateCancelNotDelivered, reason)
                $0.errorMessage = L(.stateCancelNotDelivered, reason)
            }
        }
    }

    @discardableResult
    private func updateTab(_ tabID: UUID, _ body: (inout QueryTab) -> Void) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return false }
        body(&tabs[index])
        return true
    }

    /// 取语句的第一个关键字，跳过前导空白与注释。
    private func firstKeyword(in text: String) -> String {
        var remainder = Substring(text)

        while true {
            remainder = remainder.drop(while: { $0.isWhitespace })

            if remainder.hasPrefix("--") {
                guard let newline = remainder.firstIndex(of: "\n") else { return "" }
                remainder = remainder[remainder.index(after: newline)...]
                continue
            }

            if remainder.hasPrefix("/*") {
                guard let end = remainder.range(of: "*/") else { return "" }
                remainder = remainder[end.upperBound...]
                continue
            }

            break
        }

        let word = remainder.prefix(while: { !$0.isWhitespace && $0 != "(" && $0 != ";" })
        return word.uppercased()
    }

    /// 取得（必要时建立）指向指定数据库的连接。
    /// `database` 为空时使用连接配置里的数据库。
    private func ensureService(
        for configuration: ConnectionConfig,
        database: String? = nil
    ) async throws -> any DatabaseService {
        let requested = database?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetDatabase = (requested?.isEmpty == false) ? requested! : configuration.database

        // 探针缝（见属性声明）：走的仍是**同一条收口**——版本照样落进 `serverInfos`
        // （慢查询排行按服务器主版本选列名就靠它），只是不真的建连接。
        if let serviceOverride {
            if serverInfos[configuration.id] == nil || targetDatabase == configuration.database {
                serverInfos[configuration.id] = try await serviceOverride.connect()
            }
            return serviceOverride
        }

        let key = ServiceKey(connectionID: configuration.id, database: targetDatabase)

        if let service = services[key] {
            return service
        }

        // FR-CONN-18：配了 SSH 隧道就先把它拉起来，再把连接指向本机转发端口。
        // **直连路径一行没改** —— 没配隧道的连接走到这里就是个 nil。
        let tunnelEndpoint = try await ensureTunnel(for: configuration)

        // 多个页签 / 多个树节点可能几乎同时触发；复用同一个连接 Task，避免重复建立连接。
        let task: Task<(any DatabaseService, ServerInfo), Error>
        if let existing = connectTasks[key] {
            task = existing
        } else {
            // 口令：**没存也照连**（R-46）。本机 `trust`、`peer`、证书、IAM 这些认证方式本来就
            // 不需要口令，而客户端在连接前无从判断服务端要不要 —— 以前这里"没存口令就直接拒绝"，
            // 代价是这类库在 App 里**永远连不上**（实测：本机 trust 集群报「缺少口令」，`psql` 却连得上）。
            // 空串与"没存"等价：把空口令发出去只会让服务端困惑。
            let storedPassword: String? = (try? secretStore.password(for: configuration.id)) ?? nil
            let password = (storedPassword?.isEmpty == false) ? storedPassword : nil
            // 真被服务端要口令时，把"找过哪些位置"补进诊断 —— 原来那条更有用的信息不能丢。
            let searched = (secretStore as? FileSecretStore).map {
                $0.searchedLocations().map(\.path).joined(separator: "、")
            }

            var derived = SSHTunnelEndpoint.rewrite(configuration, localPort: tunnelEndpoint?.port)
            derived.database = targetDatabase

            let newTask = Task<(any DatabaseService, ServerInfo), Error> {
                let service = DatabaseServiceFactory.make(
                    for: derived,
                    password: password,
                    language: LocalizationManager.shared.effectiveLanguage
                )
                do {
                    let serverInfo = try await service.connect()
                    return (service, serverInfo)
                } catch {
                    guard password == nil, ConnectionFailure.requiresPassword(error) else { throw error }
                    let hint = searched.map { L(.statePasswordSearched, $0) }
                    throw AppError.invalidConfiguration(
                        [L(.stateMissingPassword), hint].compactMap { $0 }.joined(separator: "\n")
                    )
                }
            }
            connectTasks[key] = newTask
            task = newTask
        }

        do {
            let (service, serverInfo) = try await task.value
            services[key] = service
            connectTasks[key] = nil
            serviceLastActivity[key] = Date()
            // 启动 SQL（FR-CONN-17）：只在**新建连接**后执行一次（缓存命中不重跑），
            // 且放在这个唯一收口点 —— 连接别处也建，散着写必漏。
            await runStartupStatements(configuration.startupStatements, for: configuration, on: service)
            // 只有主库（连接配置里的库）刷新 serverInfo，避免浏览其他库时覆盖工具栏显示。
            if serverInfos[configuration.id] == nil || targetDatabase == configuration.database {
                serverInfos[configuration.id] = serverInfo
            }
            return service
        } catch {
            connectTasks[key] = nil
            throw error
        }
    }

    /// 逐条执行启动 SQL。
    ///
    /// 三条口径：
    /// 1. **逐条发、逐条报错** —— 一条失败不该吞掉后面的，用户要知道是哪条没生效
    ///    （`search_path` 没设上，后面所有查询都可能找错表）；
    /// 2. **只读连接上写语句直接拒绝**：复用 `ExecutionSafety` 的只读判定（关掉 Safe Mode 也拦得住），
    ///    但**不启用**高危确认 —— 启动 SQL 是用户自己配的常规设置（`SET`），不该每次连接都弹窗；
    /// 3. 失败只写状态栏，**不阻断连接**：连上了就是连上了，配置写错是另一件事。
    private func runStartupStatements(
        _ statements: [String],
        for configuration: ConnectionConfig,
        on service: any DatabaseService
    ) async {
        guard !statements.isEmpty else { return }

        let readOnlyOnly = ExecutionSafetyPolicy(isEnabled: false, isReadOnly: configuration.isReadOnly)
        let decision = ExecutionSafety.check(
            statements: statements,
            databaseType: configuration.dbType,
            policy: readOnlyOnly
        )
        if case .refused(let reasons, let offenders) = decision {
            statusMessage = L(.startupSQLRefused, offenders.count) + " " + (reasons.first ?? "")
            return
        }

        for statement in statements {
            do {
                _ = try await runSingleQuery(statement, on: service)
            } catch {
                statusMessage = L(.startupSQLFailed, statement, ErrorPresenter.message(for: error))
            }
        }
    }

    /// 查询失败时按隧道状态改写那句人话（FR-CONN-18 判据 ②）。
    ///
    /// 三件事一次做完，顺序不能反：
    /// 1. **先如实改判**（`markDeadIfExited`）：进程没了但状态还停在 `.ready` 时，先把它改成 `.failed`；
    /// 2. **再决定说不说**（`SSHTunnelDiagnosis.annotate`）：只有「配置了隧道 + 隧道真的死了」才加话，
    ///    直连与隧道好好的两种情况下，一个字节都不改；
    /// 3. **最后收掉这条连接**：死隧道 + 挂在它上面的连接一起作废，下一次执行重建 ——
    ///    否则会一直复用一条已经断掉的连接，报出来的又是看不懂的连接错误。
    private func tunnelAwareMessage(_ message: String, configuration: ConnectionConfig) -> String {
        guard let tunnel = sshTunnels[configuration.id] else { return message }
        let language = LocalizationManager.shared.effectiveLanguage
        _ = tunnel.markDeadIfExited(language: language)
        let state = tunnel.currentState
        let annotated = SSHTunnelDiagnosis.annotate(
            message: message,
            tunnel: configuration.sshTunnel,
            state: state,
            language: language
        )
        guard SSHTunnelDiagnosis.shouldRebuild(state: state, tunnel: configuration.sshTunnel) else {
            return annotated
        }
        invalidateService(for: configuration.id)
        return annotated
    }

    /// 按需建/复用 SSH 隧道（FR-CONN-18）；没配隧道时返回 `nil`。
    ///
    /// 返回的是**改写后的连接目标**（本机转发端口）——调用方据此把连接指过去。
    /// 隧道按连接缓存：同一连接的多个库共用一条隧道（跳板机通常只允许少量并发通道）。
    private func ensureTunnel(for configuration: ConnectionConfig) async throws -> (host: String, port: Int)? {
        guard let tunnelConfig = configuration.sshTunnel, tunnelConfig.isEnabled else { return nil }

        if let existing = sshTunnels[configuration.id] {
            if case .ready(let port) = existing.currentState {
                return (SSHTunnelEndpoint.loopbackHost, port)
            }
            // 已经死掉的隧道**不能留在表里**：既占着一个本地端口，又会让下一次连接
            // 悄悄走一条不存在的转发。收掉它，按新参数重来。
            existing.stop()
            sshTunnels.removeValue(forKey: configuration.id)
        }

        guard let localPort = LocalPort.free() else {
            throw AppError.invalidConfiguration(L(.sshTunnelNoFreePort))
        }

        // 口令 / 私钥口令与数据库口令**分开存**（键由连接 ID 派生，见 `SSHTunnelSecrets`）。
        let storedSecret = (try? secretStore.password(for: SSHTunnelSecrets.secretKey(for: configuration.id))) ?? nil
        let secret = (storedSecret?.isEmpty == false) ? storedSecret : nil

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let knownHosts = base
            .appendingPathComponent(DoyahIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("known_hosts", isDirectory: false)

        // 口令（或带口令的私钥）才需要把口令喂给 `ssh`；agent 模式没有口令可喂。
        let needsPassword: Bool
        switch tunnelConfig.authentication {
        case .password: needsPassword = true
        case .privateKey(_, let isEncrypted): needsPassword = isEncrypted
        case .agent: needsPassword = false
        }

        let tunnel = SSHTunnelProcess(
            config: tunnelConfig,
            target: SSHTunnelTarget(host: configuration.host, port: configuration.port),
            localPort: localPort,
            knownHostsPath: knownHosts.path,
            password: needsPassword ? secret : nil,
            executable: SSHTunnelSecrets.executable(),
            isPortOpen: { host, port in LocalPort.isOpen(host: host, port: port) }
        )
        do {
            _ = try await tunnel.start(language: LocalizationManager.shared.effectiveLanguage)
        } catch {
            // 隧道起不来就**别继续连**：直接连数据库会给出误导性的网络错误。
            errorMessage = L(.sshTunnelFailed, tunnelConfig.displayName, ErrorPresenter.message(for: error))
            throw error
        }
        sshTunnels[configuration.id] = tunnel
        statusMessage = L(.sshTunnelReady, String(localPort))
        return (SSHTunnelEndpoint.loopbackHost, localPort)
    }

    // MARK: - 笔记（DOYAH-01 / 03）

    /// 笔记检索的三种态（队列 L-44）。**为什么要显式分态**：以前界面在内存里过滤，
    /// 「有结果 / 没结果」只有两种可能；改走库之后**走的是哪条路**本身成了用户该知道的事实
    /// （全文检索 / 子串兜底），而「库读不出来」也必须与「没找到」分开 —— 后者是结论，
    /// 前者是失败，混成一个空列表就等于把失败说成了结论。
    enum NoteSearchState: Equatable {
        /// **没有一次库检索发生**：搜索框是空的（显示已加载的列表），或库还不存在（检索不该顺手建库）。
        case idle
        /// 走库的结果 + 这条结果**走的是哪条路**（由 Core 给：全文检索 / 子串兜底）。
        case library(route: NoteDatabase.SearchResult.Route, notes: [Note])
        /// 库读不出来（打开 / 查询失败）：**不假装「没找到」** —— 如实说清原因，列表退回全部笔记。
        case unavailable(failure: String)
    }

    /// 一次库检索的**结果**（成功 / 失败两档）—— 队列 `L-89` ㈡ 第 8 条（键盘快打竞态）。
    ///
    /// 为什么要有这个类型：落地这一步从前写在 `searchNotes()` 的 `do` / `catch` 两处，
    /// **同一个口径抄了两遍**（「结果对应的还是不是搜索框里的词」），改一处漏一处；
    /// 而且「判断到底在不在」这件事**没有任何东西看得见**。收成一个出入参之后，
    /// 落地只有一个出口（`settleNoteSearch(_:for:)`），判断只有一份。
    enum NoteSearchOutcome: Equatable {
        /// 库给了结果（含它走的哪条路）。
        case results(NoteDatabase.SearchResult)
        /// 库没读出来（原因照原样留着，界面上如实说）。
        case failure(String)
    }

    /// **点那一枚放大镜图标 ⇒ 把搜索框浮出来**（`FR-NOTEUI-04`）。
    ///
    /// 「有个搜索图标就行，用户点击时再出现框子」那一句的机器面：图标与框子由
    /// `App/Views/SearchPresentation.swift` 的**同一呈现函数**给（收起 `SearchRevealButton` /
    /// 展开 `SearchField`），状态就是这一个布尔值。
    func revealNoteSearch() {
        noteSearchRevealed = true
    }

    /// **收起搜索**（`FR-NOTEUI-04` 判据 §三.1 ③）：ESC / 点外部 / 框里那枚 ×，三条路都走这里。
    ///
    /// **收框与清词是同一件事**：只收框不清词的话，列表还按一个**看不见的词**过滤着
    /// （症状 = 界面上没有搜索框，列表却少几条）—— 清词之后 `.task(id: notesQuery)` 会把
    /// 全量列表重查回来，用户看到的就是「收起来了，列表也回来了」。
    func collapseNoteSearch() {
        noteSearchRevealed = false
        notesQuery = ""
    }

    /// **检索结果的唯一落地出口**（队列 `L-89` ㈡ 第 8 条）。
    ///
    /// 打字比查库快：这一次的结果对应的**已经不是搜索框里的词** ⇒ 丢掉，绝不用旧结果覆盖新的。
    /// 判断只在这一处：`searchNotes()` 的两条分支都走这里（从前各写一遍）。
    ///
    /// 返回值 = 这一次**到底落了没** —— 让「迟到的结果被丢掉」这件事可以直接被断言，
    /// 而不必去撞时序窗口（竞态的窗口不可控，判据不该靠运气）。
    @discardableResult
    func settleNoteSearch(_ outcome: NoteSearchOutcome, for query: String) -> Bool {
        guard query == notesQuery else { return false }
        switch outcome {
        case .results(let result):
            noteSearchState = .library(route: result.route, notes: result.notes)
            // 结果换了 ⇒ 可见列表换了 ⇒ 多选集合要跟着收（队列 `L-97` 界面半第五片）。
            pruneNoteSelection()
        case .failure(let failure):
            noteSearchState = .unavailable(failure: failure)
        }
        return true
    }

    /// 界面上这一屏要显示的笔记（队列 L-44）。
    ///
    /// **检索走库**：搜索框非空时显示的是 `NoteLibrary.search` 给的**库的结果**（库说什么就是什么）；
    /// 空查询不是检索 —— 显示已加载的列表；库读不出来时显示**全部笔记**并在副行如实说明。
    ///
    /// 过滤 + 排序都交给 Core 的 `NotesNavigation.listing`（队列 `L-184` 第二片）：
    /// 范围那份兜底（缺归属 ⇒ 默认笔记本 / 认不出的范围 ⇒ 全部）与排序那份**总序**
    /// （第二关键字 = 标题、第三 = uid）只许有一处 —— 宿主自己拼一遍就会出现
    /// 「列表顺序与判据不一致」这种没人能复现的错。
    var visibleNotes: [Note] {
        switch noteSearchState {
        case .idle, .unavailable:
            return notesNavigation.listing(notes, scope: notesScope, sort: notesSortOrder)
        case .library(_, let results):
            // 检索结果同样过范围：搜索范围那枚开关（当前范围 / 全部笔记本）在这里起作用。
            return notesNavigation.listing(
                results, scope: notesScope, searchScope: notesSearchScope, sort: notesSortOrder
            )
        }
    }

    /// 一级导航的选中态入口（唯一一处）：归一（认不出的目标 ⇒ 全部）后重算检索。
    /// 为什么要重算检索：范围变了 ⇒ 上一次的结果已经不属于这一屏（同一族的老毛病见 `settleNoteSearch`）。
    func selectNotesScope(_ scope: NotesScope) {
        // **切走即存**（片 `N2-4`）：换左栏那一行 = 离开手上这一条笔记（列表整块换掉）。
        flushNoteAutosave()
        notesScope = notesNavigation.normalized(scope, notes: notes)
        // 换了一块 ⇒ 可见列表立刻换（`.idle` 那一支不经过库）⇒ 多选集合跟着收一遍。
        pruneNoteSelection()
        Task { await searchNotes() }
    }

    /// **中栏那枚「只看收藏」筛选开关的当前值**（队列 `L-184` 第三片）。
    ///
    /// 刻意**不另立一个状态**：左栏的「已收藏」那一行与中栏这枚开关说的是同一件事
    /// （「只看收藏过的」），共用 `notesScope` 一个变量 ⇒ 不可能出现「开关说开着、列表却在看全部」
    /// 这种两处各有一份状态才会有的错（这一族的老毛病：两处各写一遍必分家）。
    var notesFavoriteOnly: Bool { notesScope == .favorites }

    /// **开关的唯一入口**：打开 ⇒ 看「已收藏」；关掉 ⇒ 回到「全部」。
    ///
    /// 关掉时回「全部」而不是「上一个范围」：那一份「上一个」要么再存一个变量（第二个状态 ⇒ 又分家），
    /// 要么让开关的语义变成「临时叠加」而左栏的选中态却停在别处（用户看到的选中态与开关不一致）。
    /// 当前语义一句话能说清：**开关 = 左栏那一行**。
    func setNotesFavoriteOnly(_ on: Bool) {
        selectNotesScope(on ? .favorites : .all)
    }

    /// **浮动式书架的唯写入口**（`FR-NOTEUI-02` · 状态见 `notesShelfRevealed`）。
    ///
    /// 三条路都走它：入口那一枚图标的**悬停进入**、覆盖层自己的**悬停进入 / 离开**
    /// （离开＝「移开收起」那一下）、以及**点一下入口**（键盘 / 精确定位的人不必悬停）。
    ///
    /// 幂等：`guard` 掉同值写入，免得同一档状态把整棵视图树无谓地推一遍（悬停事件会连发）。
    func setNotesShelfRevealed(_ revealed: Bool) {
        guard notesShelfRevealed != revealed else { return }
        notesShelfRevealed = revealed
    }

    /// **收藏 / 取消收藏一条笔记**（队列 `L-184` 第三片）：写库 → 重读 → 界面按重读后的事实重画。
    ///
    /// 为什么落库返回 0 行也要如实说：`setFavorite` 认不出 id 时一行都不匹配 —— 那时界面上的星
    /// 不会变（重读之后还是原样），用户点了一下没反应，必须有一句话解释，而不是静默。
    func toggleNoteFavorite(_ note: Note) async {
        let target = !note.isFavorite
        do {
            let changed = try await NoteLibrary.defaultLibrary().setFavorite(id: note.id, target)
            if changed == 0 {
                statusMessage = L(.notesFavoriteMissing)
                await reloadNotes()
                return
            }
            await reloadNotes()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// **置顶 / 取消置顶一条笔记**（队列 `L-184` 第四片）：与 `toggleNoteFavorite` 同一条路
    /// （写库 → 重读 → 界面按重读后的事实重画），失败与「认不出这条」都不静默。
    func toggleNotePinned(_ note: Note) async {
        let target = !note.isPinned
        do {
            let changed = try await NoteLibrary.defaultLibrary().setPinned(id: note.id, target)
            if changed == 0 {
                statusMessage = L(.notesPinnedMissing)
                await reloadNotes()
                return
            }
            await reloadNotes()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    // MARK: - 删除确认框（队列 `L-97` 界面半第二片）

    /// 确认框正文（**唯一生产点**）：按 `ContainerRemovalSummary` 给的形状出句子 ——
    /// 视图不自己拼（拼错一次就是「将影响 0 条笔记」这种与事实相反的交代）。
    var pendingContainerRemovalMessage: String? {
        guard let request = pendingContainerRemoval else { return nil }
        switch request.summary {
        case .empty:
            return L(.notesRemoveSummaryEmpty)
        case .notes(let noteCount):
            return L(.notesRemoveSummaryNotes, noteCount)
        case .notebooks(let notebookCount):
            return L(.notesRemoveSummaryNotebooks, notebookCount)
        case .notebooksAndNotes(let notebookCount, let noteCount):
            return L(.notesRemoveSummaryBoth, notebookCount, noteCount)
        }
    }

    /// 树上点了「删除」：从库里**现算**处置计划，然后把它挂到界面上（确认框据此弹）。
    ///
    /// 默认容器 / 认不出的 uid ⇒ 计划是 `nil` ⇒ 只给一句「默认容器删不掉」的人话，**不弹框** ——
    /// 弹一个「要删除吗」再告诉你不能删，是把两种事实混成一件（用户会以为点了确定就删了）。
    func requestContainerRemoval(kind: NotebookContainerKind, uid: String, name: String) {
        Task {
            do {
                let library = NoteLibrary.defaultLibrary()
                let plan: ContainerRemovalPlan?
                if kind == .notebook {
                    plan = try await library.removalPlan(forNotebook: uid)
                } else {
                    plan = try await library.removalPlan(forShelf: uid)
                }
                guard let plan else {
                    pendingContainerRemoval = nil
                    statusMessage = L(ContainerRemovalPrompt.notAllowedKey, name)
                    return
                }
                pendingContainerRemoval = ContainerRemovalPrompt.request(plan: plan, containerName: name)
            } catch {
                pendingContainerRemoval = nil
                errorMessage = ErrorPresenter.message(for: error)
            }
        }
    }

    /// 退出口（按 ESC / 点框外）：只收掉请求，库一个字节不动。
    func cancelContainerRemoval() {
        pendingContainerRemoval = nil
    }

    /// 用户在确认框里选了某个动作：按它对应的档位落库，然后**重新读一次库**。
    ///
    /// 「取消」不落库（`action.policy == nil`）。落库走 `NoteLibrary.removeNotebook / removeShelf`，
    /// 计划在那一次调用里**重算**再落 —— 确认框上的数字与真正动手之间隔着一次点击，中间库可能
    /// 已经变了，按过期的影响面删除，删掉的东西就不是用户确认过的那个了。
    func resolveContainerRemoval(_ action: ContainerRemovalAction) {
        guard let request = pendingContainerRemoval, let policy = action.policy else {
            // 取消：什么都没发生（连重新读库都不必）。
            pendingContainerRemoval = nil
            return
        }
        Task {
            do {
                let library = NoteLibrary.defaultLibrary()
                if request.kind == .notebook {
                    _ = try await library.removeNotebook(uid: request.id, policy: policy)
                } else {
                    _ = try await library.removeShelf(uid: request.id, policy: policy)
                }
                pendingContainerRemoval = nil
                // 删完重读：树、条数、列表、当前范围的归一（被删的范围回落「全部」）都在这一条路上。
                await reloadNotes()
            } catch {
                pendingContainerRemoval = nil
                errorMessage = ErrorPresenter.message(for: error)
            }
        }
    }

    /// 跨笔记本的列表行里，这一条属于哪个笔记本（队列 `L-97` ⑤「跨笔记本结果显示所属笔记本」）。
    /// 只在**真的跨了**的时候显示：① 当前范围本身就是跨笔记本的（标签 / 最近 / 全部）；
    /// ② 或者搜「全部笔记本」且当前不是「全部」范围。两条都收在 Core 的 `isCrossNotebook` 里
    /// （视图不许自己 `switch` 范围 —— 两处各写一遍必分家）。否则每一行都挂同一个名字，那是噪音不是信息。
    var showsNotebookInNoteRow: Bool {
        if notesScope.isCrossNotebook { return notesScope != .all || notesSearchScope == .all }
        return notesSearchScope == .all
    }

    func notebookName(for note: Note) -> String? {
        notesNavigation.notebook(forNote: note.id.uuidString)?.name
    }

    /// 副行那一句如实话（`nil` = 这一屏没什么要补充的）。
    ///
    /// 文案键由 Core 的 `NoteSearchDisclosure` 给（路线 → 键是一处可单测的映射），
    /// 界面只负责显示 —— 「哪条路要不要交代」不该由视图各自判断。
    var noteSearchHint: String? {
        switch noteSearchState {
        case .idle:
            return nil
        case .library(let route, _):
            return NoteSearchDisclosure.key(for: route).map { L($0) }
        case .unavailable(let failure):
            return L(.noteSearchUnavailable, failure)
        }
    }

    /// **界面检索的唯一生产点**（队列 L-44）：搜索框里每变一个字就重算一次，
    /// 结果与「所走路线」都从库来（`NoteLibrary` 是笔记库的唯一入口）。
    ///
    /// 三条与「如实」有关的口径：
    /// ① **空查询不是检索**（`idle`）—— 显示已加载的列表，不编一次「查了个空串」；
    /// ② **库不存在就不开库**（`idle`）：检索不该顺手建出一个空库来；
    /// ③ **失败不说成「没找到」**（`unavailable`）：把原因照出来，列表退回全部笔记。
    func searchNotes() async {
        let query = notesQuery
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard notesEnabled, !trimmed.isEmpty else {
            noteSearchState = .idle
            return
        }
        let library = NoteLibrary.defaultLibrary()
        guard FileManager.default.fileExists(atPath: library.fileURL.path) else {
            // 库还没建（第一次用）：一条笔记都没有，别为了搜索把它建出来。
            noteSearchState = .idle
            return
        }
        await runSearch(trimmed, for: query)
    }

    /// **查一次库并把结果落到唯一出口**（队列 `L-89` ㈡ 第 8 条）。
    ///
    /// 词是**参数**：这一步不再读搜索框 —— 一次检索属于哪个词由调用方定，
    /// 半路上搜索框变成别的词也改不了这一次的归属。于是「迟到」这件事只可能发生在
    /// 落地那一刻，而落地只有一个出口（`settleNoteSearch`，判断也在那里）。
    func runSearch(_ trimmed: String, for query: String) async {
        do {
            // **界面检索的唯一生产点**（门禁锚点，见 `Scripts/note-search-route.json`）：
            // 结果与「走的哪条路」都从库里来 —— 界面不再拿已加载的列表自己过滤。
            let result = try await NoteLibrary.defaultLibrary().search(trimmed)
            // 打字比查库快：这一次的结果对应的已经不是搜索框里的词 ⇒ 丢掉，
            // 别用旧结果覆盖新的（同时 `NotesListView` 的 `.task(id:)` 会取消上一次任务）。
            // 判断在**唯一落地出口**里 —— 与下面 catch 那一支同一个出口。
            settleNoteSearch(.results(result), for: query)
        } catch {
            settleNoteSearch(.failure(String(describing: error)), for: query)
        }
    }

    /// 最近更新在前（同一时刻按标题定序）—— **已搬进 Core**（队列 `L-184` 第二片）：
    /// 中栏排序条之后这条口径是 `NotesSortOrder.updatedDesc` 那一档（并且多了第三关键字 `uid`，
    /// 标题重名时次序仍然确定）。宿主层不再自己排一遍。

    // MARK: - 笔记历史版本 / 私密（v0.4.0 · `FR-NTS-NOTE-VERSION-001` / `FR-NTS-NOTE-PRIVACY-001`）

    /// 当前编辑面那一条的历史版本（**最新在前**；每版带时间与摘要）。
    @Published var noteVersions: [NoteVersionEntry] = []
    @Published var isNoteVersionsPresented = false
    /// 「私密」那一栏的门牌（**无正文**）：列表里只显示标题，点开要二次验证。
    @Published var notePrivateSummaries: [NoteDatabase.PrivateNoteSummary] = []
    /// 撤私密的二次确认（判据③：**不是默认动作**，要人按一次）。
    @Published var isUnprivateConfirmPresented = false
    /// 编辑面上有没有一条真笔记（工具条那两枚入口的灰亮判据；`noteBeingEdited` 本身是私有的，
    /// 视图不许伸手进去读它 —— 一处判断出了两层就迟早分家）。
    var noteEditorHasNote: Bool { noteBeingEdited != nil }

    /// 编辑面上这一条**现在是不是私密**（工具条那枚锁的形态读它；列表里看不到私密条目，
    /// 所以不能拿 `notes` 数组反推）。
    @Published private(set) var noteEditorIsPrivate = false

    // MARK: - 快速捕获（v0.4.0 · `FR-NTS-NOTE-CAPTURE-001`）

    /// 捕获面的状态（判据①）：`begin()` 之后立刻可输入 —— 不选笔记本、不选标签、不选模板。
    @Published var quickCapture = QuickCaptureSession()
    /// 全局快捷键（⌥⌘N）。组合被别人占住时**不静默**：结果留在 `quickCaptureHotKeyOutcome` 里。
    private var quickCaptureHotKey: QuickCaptureHotKey?
    @Published private(set) var quickCaptureHotKeyOutcome: QuickCaptureHotKey.Outcome?

    /// 装全局快捷键（**幂等**：每建一次窗都会调一次，重复注册会变成「一次按键弹两个面」）。
    func startQuickCaptureHotKey() {
        guard quickCaptureHotKey == nil else { return }
        let hotKey = QuickCaptureHotKey(backend: CarbonQuickCaptureHotKeyBackend())
        quickCaptureHotKey = hotKey
        quickCaptureHotKeyOutcome = hotKey.start { [weak self] in
            Task { @MainActor [weak self] in self?.beginQuickCapture() }
        }
    }

    /// **一个动作**：快捷键 / 命令面板 → 捕获面出现，焦点直接进正文框。
    func beginQuickCapture() {
        quickCapture.begin()
    }

    /// 不记了（人按的取消）：一个字节都不落盘。
    func cancelQuickCapture() {
        quickCapture.end()
    }

    /// 存下这一条：**只写本地库**（判据② —— 捕获路径里没有网络调用），存完刷新列表。
    func commitQuickCapture() async {
        do {
            let note = try await QuickCapture.commit(
                body: quickCapture.body,
                fallbackTitle: L(.notesQuickCaptureUntitled),
                into: NoteLibrary.defaultLibrary()
            )
            quickCapture.end()
            await reloadNotes()
            selectedNoteIDs = [note.id]
            statusMessage = L(.notesQuickCaptured, note.title)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func refreshNotePrivateSummaries() async {
        let summaries = (try? await NoteLibrary.defaultLibrary().privateSummaries()) ?? []
        notePrivateSummaries = summaries
    }

    /// **标 / 撤私密**：标私密直接落；撤私密先弹二次确认（判据③）。
    func toggleNotePrivacy() async {
        guard let id = noteBeingEdited else { return }
        let library = NoteLibrary.defaultLibrary()
        let current = (try? await library.isPrivate(id: id)) ?? false
        if current {
            isUnprivateConfirmPresented = true
            return
        }
        await applyPrivacy(id: id, true, confirmed: false)
    }

    /// 二次确认那一下「确认」按的入口（撤私密）。
    func confirmUnprivateNote() async {
        guard let id = noteBeingEdited else { return }
        await applyPrivacy(id: id, false, confirmed: true)
    }

    private func applyPrivacy(id: UUID, _ isPrivate: Bool, confirmed: Bool) async {
        do {
            let outcome = try await NoteLibrary.defaultLibrary().setPrivate(id: id, isPrivate, confirmed: confirmed)
            switch outcome {
            case .confirmationRequired:
                isUnprivateConfirmPresented = true
            case .changed(let rows):
                if rows == 0 { statusMessage = L(.notesNoteMissing) }
                noteEditorIsPrivate = isPrivate
                statusMessage = isPrivate ? L(.notesPrivateOn) : L(.notesPrivateOff)
                // 重读列表 + 私密门牌：标私密之后它从中栏消失、在「私密」那一栏出现（同一份库）。
                await reloadNotes()
            }
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 打开历史版本面板（读库，界面只画）。
    func loadNoteVersions() async {
        guard let id = noteBeingEdited else { noteVersions = []; return }
        noteVersions = (try? await NoteLibrary.defaultLibrary().versions(of: id)) ?? []
    }

    /// **回滚到某一版**（回滚本身也生成新版本 —— 由 `NoteLibrary.rollback` 的形状保证）。
    func rollbackNote(to version: Int) async {
        guard let id = noteBeingEdited else { return }
        flushNoteAutosave()
        do {
            guard let restored = try await NoteLibrary.defaultLibrary().rollback(id: id, to: version) else {
                statusMessage = L(.notesVersionRollbackMissing)
                return
            }
            await reloadNotes()
            loadEditorContent(restored)
            await loadNoteVersions()
            statusMessage = L(.notesVersionRolledBack)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// **打开一条私密笔记**（判据「需二次验证才可查看」）：验证不过就一个字都不装进编辑面。
    func openPrivateNote(_ summary: NoteDatabase.PrivateNoteSummary) async {
        do {
            let outcome = try await NoteLibrary.defaultLibrary().revealPrivate(
                id: summary.id,
                authorizer: SystemNotePrivacyAuthorizer(),
                reason: L(.notesPrivateUnlockReason)
            )
            switch outcome {
            case .revealed(let payload):
                flushNoteAutosave()
                loadEditorContent(payload.note)
                editorMode = .preview
            case .denied:
                statusMessage = L(.notesPrivateDenied)
            case .notFound:
                statusMessage = L(.notesNoteMissing)
            case .notPrivate:
                if let note = notes.first(where: { $0.id == summary.id }) { loadEditorContent(note) }
            }
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func openNotes() {
        // 笔记有了"活动栏那一栏"这个正式的家（以前只弹一个面板）：入口统一走切换视图，
        // 于是 Standard 下打开笔记 = 整个界面就是笔记，而不是浮一个窗口在上面。
        // Pro 不含笔记 —— 那就**照实说**，不要弹一个空面板让人以为坏了。
        guard visibleActivityItems.contains(.notes) else {
            statusMessage = L(.licenseNotesNotIncluded)
            return
        }
        selectActivityItem(.notes)
        Task { await reloadNotes() }
        refreshSyncConflicts()
    }

    // MARK: - 冲突留两版（`FR-NTS-NOTE-SYNC-002` ①–④ · 人这一侧）

    /// 本机同步状态文件里留着的冲突副本（**判负的那一版**）。
    ///
    /// 为什么从状态文件现读、而不是从 `CloudSyncService`：留底是**本地事实**，没有账号也该看得见
    /// （登录过期后「我那条被覆盖的版本在哪」不该跟着消失）。
    @Published private(set) var syncConflicts: [CloudConflictCopy] = []
    /// 冲突面（两版并排）是否浮出来。
    @Published var isSyncConflictsPresented = false

    /// 冲突面用的展示数据：两版都带来源设备与时间（判据②）。
    var syncConflictPresentations: [SyncConflictPresentation] {
        syncConflicts.map {
            SyncConflictResolver.presentation(of: $0, untitledFallback: L(.notesUntitled))
        }
    }

    /// 从状态文件现读一遍（**不碰网络、不需要登录**）。
    func refreshSyncConflicts() {
        syncConflicts = (try? FileCloudSyncStateStore().load().conflicts) ?? []
    }

    /// 判据① 的「可打开」：落败版正文（`NoteBody` 解得出来就投影，解不出来原样给）。
    func conflictLosingText(_ copy: CloudConflictCopy) -> String {
        SyncConflictResolver.text(ofPayload: copy.losing.payload)
    }

    /// 判据① 的「可另存」：把落败版**原样**写成一条**新笔记**（新 id、来源 = 冲突副本、逐字保留）。
    func saveConflictCopyAsNote(_ copy: CloudConflictCopy) async {
        let payload = SyncConflictResolver.newNotePayload(from: copy, untitledFallback: L(.notesUntitled))
        do {
            let saved = try await NoteLibrary.defaultLibrary().save(
                NoteDraft(
                    title: payload.title,
                    body: payload.body,
                    source: SyncConflictResolver.source(for: copy)
                ),
                spans: payload.spans
            )
            await reloadNotes()
            noteBeingEdited = saved.id
            statusMessage = L(.notesSyncConflictSavedAsNote, payload.title)
            resolveConflictCopy(copy)
            refreshSyncConflicts()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 判据③④ 的「以我这版为准」——**人按的这一下**：写成这条笔记的新版本（`rev = 两版最大 + 1`），
    /// 记一版历史（`reason == .conflict` ⇒ 可用版本历史回退），再把副本销账。
    ///
    /// 名字里带「HumanChoice」的那条 Core 入口只从这里调用（`Tests/NoteSyncConflictResolutionTests`
    /// 的源树判据钉住「自动路径零引用」）。
    func keepConflictLosingVersion(_ copy: CloudConflictCopy) async {
        let payload = SyncConflictResolver.newNotePayload(from: copy, untitledFallback: L(.notesUntitled))
        let service = try? cloudSync()
        let record = SyncConflictResolver.keepLosingVersionAsHumanChoice(
            copy,
            currentRevision: service?.revision(for: copy.uid),
            deviceId: service?.deviceId ?? CloudSyncState.defaultDeviceId(),
            at: Date()
        )
        guard let noteID = UUID(uuidString: copy.uid) else {
            // `uid` 不是本机 UUID 形状（别端造的 id）：不硬塞进一个错的 id，改成「另存一条新笔记」。
            await saveConflictCopyAsNote(copy)
            return
        }
        do {
            _ = try await NoteLibrary.defaultLibrary().save(
                NoteDraft(
                    title: payload.title,
                    body: payload.body,
                    source: SyncConflictResolver.source(for: copy)
                ),
                spans: payload.spans,
                id: noteID,
                reason: .conflict
            )
            await reloadNotes()
            noteBeingEdited = noteID
            resolveConflictCopy(copy, newRevision: record.rev)
            refreshSyncConflicts()
            // 这一版也欠云端一次：入队 + 立刻试上行（断网只留队，不打扰）。
            await enqueueCloudSync(uid: copy.uid)
            statusMessage = L(.notesSyncConflictKeptMine, payload.title)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 「就以现在这版为准」：副本销账，库里这一版一个字都不动。
    func dismissConflictCopy(_ copy: CloudConflictCopy) {
        resolveConflictCopy(copy)
        refreshSyncConflicts()
        statusMessage = L(.notesSyncConflictKeptCurrent)
    }

    /// 销账：有会话就走服务（状态一起落盘），没有会话就直接改状态文件（删副本不依赖账号）。
    private func resolveConflictCopy(_ copy: CloudConflictCopy, newRevision: Int? = nil) {
        if let service = try? cloudSync() {
            try? service.resolveConflictCopy(copy, newRevision: newRevision)
            return
        }
        let store = FileCloudSyncStateStore()
        guard var state = try? store.load() else { return }
        state.conflicts.removeAll { $0.uid == copy.uid && $0.losing == copy.losing }
        if let newRevision {
            state.revByUID[copy.uid] = max(state.revByUID[copy.uid] ?? 0, newRevision)
        }
        try? store.save(state)
    }

    /// 打开「账户与同步…」面板（片 `云F` · 契约 §6.4「账号与同步界面（最小集）」）。
    ///
    /// 一扇门、一个写入口：菜单项（`DoyahStudioCommands`）与将来的活动栏入口都只许调它 ——
    /// 「面板开没开」这件事在 `AppState` 里只有一个 `@Published`（`isAccountSyncPresented`）。
    func showAccountSync() {
        isAccountSyncPresented = true
    }

    func reloadNotes() async {
        // 不含笔记的档位（Pro）不必读这份文件，更不该把"用户看不见的笔记"留在内存里。
        guard notesEnabled else {
            notes = []
            return
        }
        // 一次性数据边界迁移（FR-PLUG-04）：老版本的笔记库在工程数据家里，搬进笔记自己的数据家。
        // 放在「打开笔记」这条路上做（而不是启动时）：只有真要看笔记的人才付这份代价，
        // 而且迁移本身是幂等的 —— 搬过一次之后这里只是两次 fileExists 的开销。
        let migration = NoteStoreMigration.migrateIfNeeded()
        if migration.needsAttention {
            errorMessage = L(.notesMigrationNeedsAttention, migration.failure ?? "")
        } else if migration.didMigrate {
            statusMessage = L(.notesDataMigrated, migration.noteCount)
        }
        // 引擎迁移（FR-PLUG-08 第 3 批）：`notes.json` → `notes.sqlite3`。同样**幂等** ——
        // 库已在就一个字节都不动，所以常态下这一步只是两次 fileExists 的开销。
        // 顺序不能反：先把旧文件归位（上面那条），再把它搬进库。
        let engine = NoteLibraryMigration.migrateIfNeeded()
        if engine.needsAttention {
            errorMessage = L(.notesMigrationNeedsAttention, engine.failure ?? "")
        } else if engine.didMigrate {
            statusMessage = L(.notesEngineMigrated, engine.noteCount)
        }
        // **旧正文迁移**（`FR-RT-11` · 片 `WY-2b`）：v1 存量笔记的正文（Markdown 文本、`spans` 为
        // `NULL`）迁成 v2 权威源（span 树）—— **迁移前的全量原文先落盘备份**
        //（`note-bodies-backup.json`，同名在盘则顺延 `-2`）。同样**幂等**：库里每条都有 `spans`
        // 之后，这一步只是一次 `SELECT … WHERE spans IS NULL` 的开销。
        do {
            let bodies = try await NoteLibrary.defaultLibrary().migrateLegacyBodiesIfNeeded()
            if bodies.outcome == .partial {
                // 迁移前后投影对不上 / 有行没写成 ⇒ **不许静默**（判据 ① 就靠这条出声）。
                // 显式类型标注（`detail: String`）：`check-format-arguments.py` 只对**能机械引用到
                // 类型**的实参做槽位交叉检查（`%@` ↔ String）；写成内联拼接表达式就落进「类型不明」
                // 那一档、要另占预算（`Scripts/format-argument-dispositions.json`）。本处从内联改成
                // 具名 + 标注 ⇒ 预算回到 130 以内、且槽位对账真的跑了（台账 v1.324 记）。
                let detail: String = (bodies.mismatches + bodies.failures).joined(separator: " / ")
                errorMessage = L(.notesMigrationNeedsAttention, detail)
            }
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
        // 两层归属（队列 L-97 第二片）：一次性把「缺归属」的笔记落进默认笔记本 —— **幂等**，
        // 常态下这一步只是两次 SELECT 的开销。默认容器的名字从语言表给（Core 不许写死文案：
        // 名字是要落库、要显示给用户的数据）。
        do {
            _ = try await NoteLibrary.defaultLibrary().ensureOwnership(
                shelfName: L(.notesDefaultShelfName),
                notebookName: L(.notesDefaultNotebookName)
            )
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
        // 两级导航的树与归属（队列 `L-97` 界面半第一片）：读一次库把「架 / 笔记本」与每条笔记的归属
        // 取回来。**先确保默认容器存在**（上面那一步），所以这里读到的目录一定是补过的。
        do {
            let library = NoteLibrary.defaultLibrary()
            let directory = try await library.notebookDirectory()
            let placements = try await library.placements()
            notesNavigation = NotesNavigation(directory: directory, placements: placements)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
        let outcome = await NoteLibrary.defaultLibrary().loadOutcome()
        switch outcome {
        case .loaded(let loaded):
            notes = loaded
        case .absent:
            notes = []
        case .unreadable(let failure):
            // 坏文件**如实说**：以前这里会静默回退成空列表，看着就像"笔记全没了"。
            notes = []
            errorMessage = L(.notesFileUnreadable, failure)
        }
        // 选中态归一（队列 `L-184` 第二片起也管**标签**）：库可能刚被别的入口改过
        //（笔记本删了 / 换过库 / 这个标签下最后一条被删了）⇒ 停在已不存在的范围上会显示成空列表，
        // 被读成「笔记没了」。判断要拿**刚读回来的**那份笔记 —— 上面那条加载之后才做得了。
        notesScope = notesNavigation.normalized(notesScope, notes: notes)
        // 列表变了，正在跑的检索要跟着重算（队列 L-44）—— 否则刚存下的那条在搜索结果里
        // 永远不出现、刚删掉的那条还在结果里。空查询时这一步只是把状态置回 `.idle`。
        await searchNotes()
        // 列表 / 范围 / 库都变了 ⇒ 多选集合收一遍（看不见的条目不许留在集合里）。
        pruneNoteSelection()
        // 私密那一栏与中栏列表同源（都是这份库）：标 / 撤私密之后两处必须一起变，
        // 少刷一处就会出现「列表里没了、私密那一栏也没有」这种藏起来的效果。
        await refreshNotePrivateSummaries()
        // 关联行也跟着重读：笔记被删 / 还原之后，「来源已删除」那一句要在同一轮里翻面
        // （判据④；链接行不级联删，所以这一句由**读的一方**现判）。
        await reloadTodoLinks()
    }

    /// 把一条笔记装进编辑器的**内容**（标题 / 正文 / 标签 + 正在编辑的 id）——**不动模式**。
    /// 模式由三个入口各自定（单击 ⇒ `.preview`；「改」/「新建」⇒ `.edit`），见 `NoteEditorMode`。
    ///
    /// **优先用「刚落库、还没反映到 `notes` 里的那一份」**（片 `N2-4`）：自动保存是异步的，
    /// 而「点走再点回来」是同步的两下 —— 在写完 `reloadNotes()` 之前读到的是库里**写之前**的那一份，
    /// 用户会看到自己刚敲的字没了。`pendingNoteSnapshot` 就是补这个窗口期的（写完即清）。
    private func loadEditorContent(_ note: Note) {
        if let pending = pendingNoteSnapshot, pending.id == note.id {
            setNoteEditorContent(
                id: note.id, title: pending.title, spans: pending.spans, tags: pending.tags
            )
            return
        }
        // 先按正文投影（`parseInline` —— 与装进编辑面**同一个函数**）垫上，紧接着从库里把权威源
        // 读回来换掉（`loadEditorSpans`）：`Note.body` 只是 `spans` 的投影，下划线 / 底色 / 块级
        // 这些 Markdown 表达不了的东西**只在 `spans` 列里**（片 `WY-2a`）。
        setNoteEditorContent(
            id: note.id,
            title: note.title,
            spans: NoteBodyProjection.parseInline(note.body),
            tags: note.tags.joined(separator: " ")
        )
        loadEditorSpans(id: note.id)
    }

    /// **唯一一处**把内容写进编辑器（三个 `@Published` + 权威源 spans + 正在编辑的 id）。
    ///
    /// 为什么要收成一个入口：那三个 `didSet` 是「有改动就自动保存」的判据，而这里是
    /// 「**读进来的，不是用户写的**」那道闸（`isLoadingNoteEditor`）—— 谁再自己逐个赋一次值，
    /// 就会凭空多出一串「改动」：刚点开一条笔记就被自动保存写回去一次（`L-172` 同一课）。
    /// 片 `WY-2a` 起 `spans` 也是这一处装（它没有 `didSet`，但必须与 `body` **同一批**装上——
    /// 两处分着装就会出现「正文换了、权威源还是上一条的」）。
    private func setNoteEditorContent(id: UUID?, title: String, spans: [NoteSpan], tags: String) {
        isLoadingNoteEditor = true
        noteBeingEdited = id
        noteEditorTitle = title
        noteEditorSpans = spans
        noteEditorBody = NoteBodyProjection.markdown(from: spans)
        noteEditorTags = tags
        isLoadingNoteEditor = false
        // 装进来 = 与库里一致 ⇒ 不脏，也不该再挂着上一条留下的保存状态。
        noteEditorDirty = false
        noteSaveState = .idle
        // **私密挡位跟着这一条走**（`nil` = 新建态 ⇒ 不是私密）。
        noteEditorIsPrivate = id.flatMap { identifier in notes.first { $0.id == identifier }?.isPrivate } ?? false
        // **附件索引也跟着这一条走**（`FR-NTS-NOTE-ATTACH-001`）：换一条就必须换一份清单，
        // 否则「切到 B 却看见 A 的附件」—— 与正文串内容同一族的错。
        if let id {
            loadNoteAttachments(id: id)
        } else {
            noteAttachmentLoadTask?.cancel()
            noteAttachments = []
            missingNoteAttachments = []
        }
    }

    /// 把库里那一条的**正文权威源**（`spans`）读回来重挂在编辑面上（片 `WY-2a`）。
    ///
    /// 为什么要有这一跳：`body` 只是 `spans` 的**单向投影** —— 下划线 / 荧光底色 / 块级三枚
    /// （勾选框 / 有序 / 无序）在 Markdown 里**没有形状**。不读回来的话，「打开一条带下划线的笔记、
    /// 再保存一次」会按投影重新解析、把这几个字段**静默抹掉**（那正是 `WY-1b1` 头注释登记的
    /// 过渡期边界，本片收口它）。
    ///
    /// 两条守卫**在读数回来那一刻**再判（不是发起时判）：
    ///   · 编辑器**还停在**这一条上（用户可能已经点去别的笔记 ⇒ 迟到的读数属于上一条）；
    ///   · 用户**还没动手改**（`noteEditorDirty` ⇒ 迟到的读数不许盖掉刚敲的字）。
    private func loadEditorSpans(id: UUID) {
        noteSpansLoadTask?.cancel()
        noteSpansLoadTask = Task { [weak self] in
            guard let self else { return }
            let spans = await self.readNoteSpans(id: id)
            guard !Task.isCancelled, let spans else { return }
            self.applyLoadedSpans(spans, id: id)
        }
    }

    /// 从库里读一条笔记的正文权威源（读不回来 / 该列还是 v1 的 NULL ⇒ `nil`，**不猜也不兜底成空树**）。
    private func readNoteSpans(id: UUID) async -> [NoteSpan]? {
        guard notesEnabled else { return nil }
        do {
            guard let json = try await NoteLibrary.defaultLibrary().noteSpans(id: id) else { return nil }
            return Self.decodedSpans(json)
        } catch {
            // 读权威源失败**不静默**（与 `reloadNotes` 同一条口径：存储层的失败走 `errorMessage`，
            // 不新造一句文案键）。
            errorMessage = ErrorPresenter.message(for: error)
            return nil
        }
    }

    /// 把读回来的权威源装上（守卫见 `loadEditorSpans`）。正文一并按它投影一次 —— 两列重新对齐
    /// （库里那份 `body` 本来就是这棵树的投影，正常这一句一个字节都不改）。
    private func applyLoadedSpans(_ spans: [NoteSpan], id: UUID) {
        guard noteBeingEdited == id, !noteEditorDirty else { return }
        isLoadingNoteEditor = true
        noteEditorSpans = spans
        let projected = NoteBodyProjection.markdown(from: spans)
        if noteEditorBody != projected { noteEditorBody = projected }
        isLoadingNoteEditor = false
    }

    /// 等「读回权威源 spans」那一发**收口**（判据要确定性，不能靠 `sleep` 撞 —— 与
    /// `awaitPendingNoteAutosave()` 同一条理由）。
    func awaitPendingNoteSpansLoad() async {
        await noteSpansLoadTask?.value
    }

    // MARK: - 附件（`FR-NTS-NOTE-ATTACH-001`）

    /// 读一条笔记的附件索引，并顺手标出**文件已经不在**的那些（判据②）。
    ///
    /// 为什么「在不在」要在这里算一次而不是视图里现判：视图每帧去摸文件系统既慢又会在
    /// 外接盘拔掉时抖；读数收在一处，界面只画 `missingNoteAttachments` 给出的结论。
    private func loadNoteAttachments(id: UUID) {
        noteAttachmentLoadTask?.cancel()
        noteAttachmentLoadTask = Task { [weak self] in
            await self?.refreshNoteAttachments(id: id)
        }
    }

    private func refreshNoteAttachments(id: UUID) async {
        guard notesEnabled else { return }
        do {
            let store = NoteLibrary.defaultLibrary()
            let all = try await store.attachments(of: id)
            let missing = try await store.missingAttachments(of: id)
            guard noteBeingEdited == id else { return }   // 迟到的读数属于上一条
            noteAttachments = all
            missingNoteAttachments = missing
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 等「读附件」那一发收口（判据要确定性，不靠 `sleep` 撞 —— 与 `awaitPendingNoteSpansLoad` 同一条理由）。
    func awaitPendingNoteAttachments() async {
        await noteAttachmentLoadTask?.value
    }

    /// 一条附件**文件还在不在**（界面那枚缺失标记读它；判定处仍是 `NoteAttachmentStore.isMissing`）。
    func attachmentIsMissing(_ attachment: NoteAttachment) -> Bool {
        missingNoteAttachments.contains { $0.id == attachment.id }
    }

    /// **插入图片 / 文件**（判据①：一次动作；原文件按字节原样收进来，不压缩不改写）。
    ///
    /// 新建态（还没落库）先按正常保存路把这一条写下去再挂 —— 否则附件没有可挂的笔记 id。
    /// 为空（没东西可挂）时**不弹文件选择框**、给一句人话（`notesAttachNothingToAttachTo`）。
    func attachFiles(at urls: [URL]) async {
        guard notesEnabled else {
            statusMessage = L(.licenseNotesNotIncluded)
            return
        }
        guard !urls.isEmpty else { return }
        var target = noteBeingEdited
        if target == nil {
            guard noteEditorHasContent else {
                statusMessage = L(.notesAttachNothingToAttachTo)
                return
            }
            guard await writeNoteEditor(snapshot: noteEditorSnapshot(), automatic: false) else { return }
            target = noteBeingEdited
        }
        guard let noteID = target else {
            statusMessage = L(.notesAttachNothingToAttachTo)
            return
        }
        let store = NoteLibrary.defaultLibrary()
        var attached: Int = 0
        var failure: Error?
        for url in urls {
            do {
                _ = try await store.attach(fileAt: url, to: noteID)
                attached += 1
            } catch {
                // 一份失败不拦其余（拖进来三份、坏了一份，另外两份照挂），但**不静默**。
                failure = failure ?? error
            }
        }
        await refreshNoteAttachments(id: noteID)
        if let failure {
            statusMessage = L(.notesAttachFailed, String(describing: failure))
        } else if attached > 0 {
            statusMessage = L(.notesAttached, Int(attached))
        }
    }

    /// 删笔记确认框里那句正文要带上的附件条数（判据③：先说清「有 N 个附件」再让人按删除）。
    var pendingNoteRemovalAttachmentCount: Int {
        guard let request = pendingNoteRemoval else { return 0 }
        let ids: [UUID]
        if case .notes(let targets) = request.target {
            ids = targets
        } else {
            ids = []
        }
        return ids.reduce(0) { total, id in
            total + (noteAttachmentsForDeletion[id]?.count ?? 0)
        }
    }

    /// 确认框挂出来之前先读各条的附件条数（`requestNoteRemoval` 里同步填不了 —— 库是 actor）。
    /// 只存条数，不存内容：这一格只用来拼那句话。
    @Published var noteAttachmentsForDeletion: [UUID: [NoteAttachment]] = [:]

    func loadAttachmentsForPendingRemoval() async {
        guard let request = pendingNoteRemoval, case .notes(let ids) = request.target else {
            noteAttachmentsForDeletion = [:]
            return
        }
        var counts: [UUID: [NoteAttachment]] = [:]
        let store = NoteLibrary.defaultLibrary()
        for id in ids {
            counts[id] = (try? await store.attachments(of: id)) ?? []
        }
        noteAttachmentsForDeletion = counts
    }

    /// **保留附件文件**（判据③的「另行确认」里那一条「不删」的出口）。
    func keepPendingAttachmentFiles() {
        pendingAttachmentCleanup = []
        isAttachmentCleanupPresented = false
    }

    /// **一起删掉附件文件**（判据③的另一个出口：人按了「一起删掉」才动文件）。
    func deletePendingAttachmentFiles() async {
        let files = pendingAttachmentCleanup
        pendingAttachmentCleanup = []
        isAttachmentCleanupPresented = false
        guard !files.isEmpty else { return }
        do {
            let removed: Int = try await NoteLibrary.defaultLibrary().deleteAttachmentFiles(files)
            statusMessage = L(.notesAttachmentFilesDeleted, Int(removed))
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// span 树 → 落库那份 JSON（`NoteBody` 的编解码面 = 交换面，**不另起一套序列化**）。
    ///
    /// **canonical（片 `云-编码canonical`）**：编码配置由 `NoteBodyCanonical.encoder()` **一处**给出
    /// （键按字典序 / 紧凑 / `/` 不转义）—— 修掉 `云E` 实测的「跨进程字节不稳」（默认 `JSONEncoder()`
    /// 的键序不保序：同一份正文两次运行给出不同字节）。**为什么不在这一行就地 `JSONEncoder()`**：
    /// 那样写入口、单测、探针就是三份配置，同一件事三套口径 —— 与「不另起一套序列化」相反。
    private static func encodedSpans(_ spans: [NoteSpan]) throws -> String {
        try NoteBodyCanonical.json(NoteBody(spans: spans))
    }

    /// 落库那份 JSON → span 树（读不回来 ⇒ `nil`：不猜、也不静默当成空树）。
    private static func decodedSpans(_ json: String) -> [NoteSpan]? {
        guard let body = try? JSONDecoder().decode(NoteBody.self, from: Data(json.utf8)) else { return nil }
        return body.spans
    }

    func beginNewNote() {
        // **切走即存**（片 `N2-4`）：点「新建」就是离开手上这一条 —— 先把改动落下去再清空。
        flushNoteAutosave()
        setNoteEditorContent(id: nil, title: "", spans: [], tags: "")
        // 新建 ⇒ 正文要能写（片 `N2-3a`：`.edit` 是本片之前那一个语义）。
        editorMode = .edit
    }

    func edit(_ note: Note) {
        // **切走即存**（片 `N2-4`）：换一条之前先把手上这条的改动落下去 ——
        // 否则「编辑完直接点开另一条」这几秒里敲的字全丢（验收判据①/②）。
        flushNoteAutosave()
        loadEditorContent(note)
        // 「改」入口（左区顶部那枚铅笔，`NotesPanel.crudEntries`）⇒ 正文可编辑。
        // **列表行的双击也走这里**（片 `N2-3b`）：那一刻手上有一条笔记 ⇒ 内容与模式一起给。
        // 单击进的是**预览**（见 `handleNoteRowClick`）。
        editorMode = .edit
    }

    /// **双击进编辑**（片 `N2-3b`「双击编辑」· 人类主人令 `T-20261007-004` 第 4 条）——
    /// **内容区**（右栏正文那一块）双击走这一条。
    ///
    /// 内容此刻**已经在编辑器里**（单击预览 `handleNoteRowClick` 已经把它装好并置了 `.preview`）
    /// ⇒ 这里**只翻模式**：再装一遍内容不会出错，但会把「谁装的」变成两处，而
    /// 「正文那一块可不可编辑」这个值的出处必须只有一处（`NoteEditorMode` 头注释同一条纪律）。
    ///
    /// 空编辑器（`noteBeingEdited == nil`：没点过任何一条 / 刚 `beginNewNote()` 过）双击没有对象
    /// ⇒ 什么都不做 —— 而不是把一块空正文切成「可编辑」让用户以为在改某一条。
    func beginEditingCurrentNote() {
        guard noteBeingEdited != nil else { return }
        editorMode = .edit
    }

    /// 「编辑器里到底有没有可保存的内容」（队列 **L-50**）。
    ///
    /// **唯一出处**：`NotesEditorView` 的「保存」按钮那一个 `.disabled` 与 `saveNoteFromEditor()`
    /// 的这一句守卫**必须是同一条判断**。从前两处各写一遍、视图那侧干脆没写 ⇒ 标题与正文都空时
    /// 「保存」满色可点，点下去静默 `return`（屏幕上什么都不发生、也没有一句解释 —— 用户会以为按钮坏了）。
    ///
    /// 口径 = **灰着**（取三者中最贴合产品现状的一档）：① 同一个动作族里已有的先例 ——
    /// `SaveQuerySheet` 的「保存」在空名字时就是 `.disabled(trimmedName.isEmpty)`；
    /// ② 外发日志的「清空」也是灰着（`.disabled(appState.egressEntries.isEmpty)`）；
    /// ③ 而「导出」的「可点 + 给一句理由」（`egressExportEmpty`）是**有意为之的例外**，不是缺陷。
    /// 判据逐条对账见 `Scripts/check-empty-action-buttons.py`（改口径要同时动台账与视图，不许半改）。
    var noteEditorHasContent: Bool {
        !noteEditorTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !noteEditorBody.isEmpty
    }

    /// **手动「保存」**（工具条那一枚）：与自动保存**同一条写路**（`writeNoteEditor`），
    /// 区别只有收尾 —— 手动保存之后编辑器清空、回到「新建态」（本片之前的口径，一字未改）。
    func saveNoteFromEditor() async {
        guard notesEnabled else {
            statusMessage = L(.licenseNotesNotIncluded)
            return
        }
        // 许可那一档是**可点 + 给理由**（Pro 档要点得到「本档不含笔记」这句人话）；
        // 内容为空那一档是**灰着** —— 两句守卫的处置不同，别合并。
        guard noteEditorHasContent else { return }
        let saved = await writeNoteEditor(snapshot: noteEditorSnapshot(), automatic: false)
        if saved { beginNewNote() }
    }

    // MARK: - 自动保存（片 `N2-4` · 停顿即存 + 切走即存）

    /// 编辑器那三个框**任何一个**变了都走这里：标脏 + 重排停顿计时。
    /// 装内容期间（`isLoadingNoteEditor`）不算改动 —— 那是「读进来的」，不是「用户写的」。
    private func noteEditorTextChanged() {
        guard !isLoadingNoteEditor else { return }
        noteEditorDirty = true
        noteSaveState = .pending
        scheduleNoteAutoSave()
    }

    /// 重排**停顿计时**：把上一发收掉、重开一发 —— 只有**停手之后**那一发才写库。
    ///
    /// 计时走 `Task.sleep`（挂起）：敲键盘这条路上只有「取消 + 新建一个 Task」，
    /// **没有一次同步写盘** —— 片上边界「不许把自动保存做成阻塞输入」说的就是这一条。
    private func scheduleNoteAutoSave() {
        noteAutoSaveTask?.cancel()
        noteAutoSaveTask = Task { [weak self] in
            try? await Task.sleep(for: NoteAutosave.pauseWindow)
            guard !Task.isCancelled else { return }
            await self?.autosaveNoteEditor()
        }
    }

    /// 编辑器里这一份的快照（写库与「切走即存」共用的**唯一出处**）。
    ///
    /// **片 `WY-2a`**：正文那一份取的是**权威源那棵树**（`editorSpansForSave()`），`body` 由它派生 ——
    /// 从此写库的两列不会各说各话（`NoteDatabase.setNoteSpans` 把这条写进了它的口径里）。
    private func noteEditorSnapshot() -> NoteEditorSnapshot {
        NoteEditorSnapshot(
            id: noteBeingEdited, title: noteEditorTitle,
            spans: editorSpansForSave(), tags: noteEditorTags
        )
    }

    /// **写库用的正文权威源**（编辑面那一棵 span 树）。
    ///
    /// 两条路（判据是**投影一致**，不是「哪一边非空」）：
    ///   · **编辑面在场**（常态）：它每敲一次就把整棵树与正文**一起**回推
    ///     （`NotesRichTextEditor.Coordinator.textDidChange`）⇒ 这一棵的投影**恒等于**当前正文，
    ///     直接用它（下划线 / 底色 / 块级只有它带得住）。
    ///   · **编辑面不在场 / 这一棵已经过期**（纯数据入口、判据直接灌正文，或正文被单独改过而树没跟上）：
    ///     按**与装进编辑面同一个函数**（`NoteBodyProjection.parseInline`，Markdown 行内解析的唯一出处）
    ///     从当前正文投影一份 —— 既不凭空写一条空正文，也不是另起一套解析。
    ///     **过期那一档必须由正文说了算**：`noteEditorSpans` 是装笔记时按投影垫上的，正文改了它并不会
    ///     自己变（它没有 `didSet`），拿它当权威源就会把**刚敲的字**整段写回去。
    private func editorSpansForSave() -> [NoteSpan] {
        if !noteEditorSpans.isEmpty,
           NoteBodyProjection.markdown(from: noteEditorSpans) == noteEditorBody {
            return noteEditorSpans
        }
        return NoteBodyProjection.parseInline(noteEditorBody)
    }

    /// 手上这一份是不是**就是刚写下去的那一份**（写入期间用户还在敲 ⇒ 判假，见 `writeNoteEditor`）。
    private func noteEditorMatches(_ written: NoteEditorSnapshot) -> Bool {
        written.id == noteBeingEdited
            && written.title == noteEditorTitle
            && written.spans == editorSpansForSave()
            && written.body == noteEditorBody
            && written.tags == noteEditorTags
    }

    /// **停顿即存**：停顿窗口到了 ⇒ 把编辑器里那一份落库。
    /// 三条守卫（许可 / 有内容 / 真的有改动）：一条不满足就**不动库、也不改状态** ——
    /// 空编辑器上不许凭空写出一条空笔记来。
    @discardableResult
    func autosaveNoteEditor() async -> Bool {
        guard notesEnabled, noteEditorDirty, noteEditorHasContent else { return false }
        return await writeNoteEditor(snapshot: noteEditorSnapshot(), automatic: true)
    }

    /// **切走即存**：离开这一条笔记之前，把手上的改动**先快照、再排进写库队列**。
    ///
    /// 为什么是「先快照」：紧接着那些入口（点另一行 / 换范围 / 换模块 / 新建）就会改写编辑器
    /// 那三个 `@Published`，而写库是异步的 —— 不快照的话写下去的是**下一条**的内容。
    /// 为什么**不等它写完**：那些入口都在手势回调里（同步的），等 = 把交互卡在写盘上。
    /// 需要确定收口的地方只有两处：机器判据（`awaitPendingNoteAutosave()`）与
    /// 「重新打开这一条时优先用它」那份快照（`pendingNoteSnapshot`）。
    func flushNoteAutosave() {
        guard noteEditorDirty, noteEditorHasContent else { return }
        noteAutoSaveTask?.cancel()
        let snapshot = noteEditorSnapshot()
        pendingNoteSnapshot = snapshot
        noteAutoSaveTask = Task { [weak self] in
            await self?.writeNoteEditor(snapshot: snapshot, automatic: true)
        }
    }

    /// 等手上那一发自动保存**收口**（停顿计时 + 写库）。
    ///
    /// 生产路径不需要「等」—— 它是后台的；需要确定性的只有机器判据：
    /// 「切走即存」之后要断言「内容已经在库里」，不能靠 `sleep` 去撞（撞早了就是假绿）。
    func awaitPendingNoteAutosave() async {
        await noteAutoSaveTask?.value
    }

    /// **唯一一条写库路**（手动「保存」与自动保存都走它）：新建 / 覆盖 + 落点 + 重读。
    ///
    /// 两条纪律：
    ///   · **编辑已有笔记保留原来源**（来源是事实，不该因为改了几个字就丢掉 —— 本片之前的口径）；
    ///   · 失败**分两种处置**：自动保存是**后台**的（验收判据④：全程无弹窗）⇒ 工具条那一枚状态
    ///     ＋ 状态栏一句人话；手动保存是**用户正看着**的动作 ⇒ 多一个可复制的错误框（既有口径）。
    ///   两种都不静默（验收判据⑥）。
    @discardableResult
    private func writeNoteEditor(snapshot: NoteEditorSnapshot, automatic: Bool) async -> Bool {
        noteSaveState = .saving
        // 写下去的那一份（新建那一支会补上刚落库的 id —— 见下面那句注释）。
        var written = snapshot
        do {
            let store = NoteLibrary.defaultLibrary()
            // **正文权威源**：先把 span 树编成落库那份 JSON（`NoteBody` 的编解码面 —— 与交换面同一份，
            // 不另起一套序列化）。编不出来就抛，走下面失败那一条，绝不静默写半份。
            let spansJSON = try Self.encodedSpans(snapshot.spans)
            if let id = snapshot.id {
                let existing = notes.first { $0.id == id }
                var merged = snapshot.draft(untitled: L(.notesUntitled))
                merged.source = existing?.source ?? merged.source
                // **一次保存 = 本体 + 正文权威源 + 历史版本**（`NoteLibrary.save`）：
                // 版本记在两次写都完成之后，回滚才有「保存当时那一份」可取（`FR-NTS-NOTE-VERSION-001`）。
                _ = try await store.save(merged, spans: spansJSON, id: id)
            } else {
                let saved = try await store.save(snapshot.draft(untitled: L(.notesUntitled)), spans: spansJSON)
                // **新建这一条已经在库里了** ⇒ 编辑器改认它（`noteBeingEdited = saved.id`）：
                // 否则每一次自动保存都会**再建一条**（敲一会儿就多出好几条几乎一样的笔记）。
                written = NoteEditorSnapshot(
                    id: saved.id, title: snapshot.title, spans: snapshot.spans, tags: snapshot.tags
                )
                noteBeingEdited = saved.id
                // **在哪个笔记本里新建就落在哪个笔记本**（队列 `L-97` 界面半第一片）：
                // 落点由 Core 给（`destinationNotebookUid`：在笔记本里 ⇒ 那个；全部 / 架 ⇒ 默认笔记本）。
                // 不显式搬的话新笔记会落默认笔记本 —— 用户在「笔记本B1」里新建一条，
                // 它却出现在另一个笔记本里（保存成功、却找不到，这是最难自证的一类）。
                let destination = notesNavigation.destinationNotebookUid(for: notesScope)
                if destination != notesNavigation.directory.resolvedNotebookUid(nil) {
                    _ = try await store.move(noteIDs: [saved.id], toNotebook: destination)
                }
                // 新建这一支的正文权威源已在 `store.save` 里同一个调用写完（上面那一支的理由逐字适用）。
            }
            if written.id == noteBeingEdited {
                // 写入期间用户还在敲（`await` 那一瞬主 actor 是让出来的）⇒ **不能**一句「干净了」
                // 把这段时间里的按键抹掉：手上这一份与刚写下去的那一份不一样就保持「脏」并重排。
                if noteEditorMatches(written) {
                    noteEditorDirty = false
                    noteSaveState = .idle
                    pendingNoteSnapshot = nil
                } else {
                    noteEditorDirty = true
                    noteSaveState = .pending
                    scheduleNoteAutoSave()
                }
            }
            // 编辑器已经换到别的笔记上（`written.id != noteBeingEdited`）：这一发写的是**上一条**的
            // 收尾 ⇒ 当前编辑器那份「脏 / 净」由它自己的改动说了算，这里一个字都不碰。
            await reloadNotes()
            // 片 `云D`：写库成功之后入队 + 尝试上行（在线补传 / 断网留队，`IR-16` / `IR-21`）。
            // **同步失败不打扰保存**（笔记已在本地库 = 唯一事实源）。
            // **私密笔记不同步**（`FR-NTS-NOTE-PRIVACY-001` 判据②）：进队之前就拦住 ——
            // 进队再拦等于把内容留在队列文件里，那是同一处泄漏换了个位置。
            var shouldSync = true
            if let id = written.id {
                shouldSync = ((try? await store.isPrivate(id: id)) ?? false) != true
            }
            if let uid = written.id?.uuidString, shouldSync {
                await enqueueCloudSync(uid: uid, operation: .upsert)
            }
            return true
        } catch {
            let reason = ErrorPresenter.message(for: error)
            // **失败绝不静默**（判据⑥）：状态那一格记住原因 —— 工具条画红、悬停给原因、
            // 状态栏把这句话说出来；手动保存再加一个可复制的框（既有口径，自动保存那条不弹）。
            noteSaveState = .failed(reason)
            statusMessage = L(.notesAutoSaveFailedStatus, reason)
            if !automatic { errorMessage = reason }
            return false
        }
    }

    // MARK: - 云同步触发点（片 `云D` · 上行 `IR-16` / 增量下拉 `IR-15` / 断网重试 `IR-21`）

    /// 上一次云同步的读数（**只留读数**，本片不新画界面）。
    private(set) var lastCloudSyncReport: CloudSyncService.FlushReport?

    /// 缓存的同步服务（按登录账号 `sub` 换一次）。**网络调用仍只落在 `Core/NoteSync/`** ——
    /// 这里只是装配缝（与 `AccountFlowModel.liveClient()` 同一条纪律：界面这一层不碰 `URLSession`）。
    private var cloudSyncService: CloudSyncService?
    private var cloudSyncSubject: String?

    /// 写库成功之后的**触发点**：入队 + 立刻尝试上行。
    ///
    /// 三条口径：
    ///   · **开关默认关**（`S3`）：`CloudSyncPreference.isEnabled()` 为假 ⇒ 一个字都不发；
    ///   · **没登录就没有云同步**（`S1`/`S2` 的前提是账号）：本机钥匙串里没有会话 ⇒ 直接让路；
    ///   · **失败不打扰保存**（笔记已在本地库 = 唯一事实源）：断网只让这一条留在队列里（`IR-21`），
    ///     不写用户可见错误面 —— 本片不新画同步界面。
    private func enqueueCloudSync(
        uid: String,
        operation: SyncOperation = .upsert,
        family: SyncFamily = .note
    ) async {
        guard CloudSyncPreference.isEnabled() else { return }
        do {
            let service = try cloudSync()
            let report: CloudSyncService.FlushReport?
            switch family {
            case .note:
                report = await service.enqueueAndPush(
                    uid: uid, operation: operation, source: NoteLibraryCloudSource()
                )
            case .todo:
                // 待办：**同一个服务、同一个队列、同一份退避**，只是多给一个现取源
                // （`TodoLibraryCloudSource` 读同一个库文件）。
                report = await service.enqueueAndPush(
                    uid: uid,
                    operation: operation,
                    source: NoteLibraryCloudSource(),
                    family: .todo,
                    todoSource: TodoLibraryCloudSource()
                )
            }
            lastCloudSyncReport = report
        } catch {
            // 装配不起来（没会话 / 状态文件坏）：同步这一侧静默让路，保存照常成功。
        }
    }

    /// 懒装配同步服务：会话在钥匙串里（`云C`）⇒ 取当前 `access_token` 作数据面认证头；
    /// 换账号（`sub` 变了）就重建一次，免得把上一个账号的令牌带过去。
    private func cloudSync() throws -> CloudSyncService {
        let client = AccountFlowModel.liveClient()
        guard let session = (try? client.currentSession()) ?? nil else {
            throw CloudSyncError.notAuthenticated
        }
        if let cached = cloudSyncService, cloudSyncSubject == session.subject { return cached }
        let service = try CloudSyncService.live(
            environmentID: AccountFlowModel.environmentID,
            tokenProvider: {
                guard let token = (try? client.currentSession()) ?? nil else {
                    throw CloudSyncError.notAuthenticated
                }
                return token.accessToken
            },
            // 契约 §3.4.8 / §6.3：到期前 60 秒先续期；业务面 401 也走同一条续期（`CloudSyncService.send`）。
            // 刷新令牌本身失效时 `refresh()` 抛错 ⇒ 服务转成 `notAuthenticated`，界面提示「需要重新登录」。
            tokenRefresher: {
                try client.refresh().accessToken
            },
            tokenExpiring: {
                guard let session = (try? client.currentSession()) ?? nil else { return true }
                return session.isExpired(leeway: 60)
            }
        )
        cloudSyncService = service
        cloudSyncSubject = session.subject
        return service
    }

    func deleteNote(id: UUID) async {
        do {
            // **墓碑入口**（`IR-17`）：`changeCount == 0`（库里没有这条）会抛 `noteNotFound`，
            // 由下面那条 `catch` 如实报出来 —— 不再静默 no-op（`T-20261009-161/162`）。
            //
            // **附件清单先读回来**（`FR-NTS-NOTE-ATTACH-001` 判据③）：墓碑只删索引行、**不动文件**，
            // 于是「这条原来挂着哪些附件」必须在这里接住，删完由界面再问一次「文件要一起删吗」。
            // 不问就把清单丢掉 = 文件变成谁也找不到的孤儿（占地方、还可能含敏感内容）。
            let receipt = try await NoteLibrary.defaultLibrary().deleteReturningAttachments(id: id, at: Date())
            if noteBeingEdited == id { beginNewNote() }
            await reloadNotes()
            if !receipt.attachments.isEmpty {
                pendingAttachmentCleanup.append(contentsOf: receipt.attachments)
            }
            // **删除也是一次内容变更**：写库成功之后入队 + 尝试上行（`IR-17` 墓碑 / `IR-21` 断网留队）。
            // 契约 v3.96 新纪律：墓碑上行 `rev` 必须 +1 —— 由 `flush` 的 `.delete` 那一支用
            // `nextRevision(for:)` 落实（否则另一端持更高 `rev` 的副本会把删除 LWW 覆盖回来）。
            await enqueueCloudSync(uid: id.uuidString, operation: .delete)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    // MARK: - 待办（队列 `L-100` 界面半第一片 · 清单屏）

    /// 切「看哪一屏」（笔记 / 待办）。切到待办时**读一次库** —— 与 `openNotes()` 同一条：
    /// 界面上能看见的东西必须来自库，不能来自上一次的残留（`todos` 是内存态，库才是事实）。
    func setNotesModule(_ module: NotesModule) {
        guard notesModule != module else { return }
        // **切走即存**（片 `N2-4`）：切走 / 切回都会换掉右栏那一块 ⇒ 先把手上这份落下去。
        flushNoteAutosave()
        notesModule = module
        if module == .todos {
            Task {
                await reloadTodos()
                await reloadReminders()
                await refreshReminderPermission()
            }
        }
    }

    /// 读任务（`NoteLibrary.todos()`：**库不存在 ⇒ 空表**，不顺手建库 —— 那条纪律在门面里）。
    func reloadTodos() async {
        guard notesEnabled else {
            todos = []
            return
        }
        do {
            todos = try await NoteLibrary.defaultLibrary().todos()
        } catch {
            todos = []
            errorMessage = ErrorPresenter.message(for: error)
        }
        // 关联行随任务一起重读：清单 / 详情里那句「来自笔记 / 已生成任务」不能比任务本身落后一轮。
        await reloadTodoLinks()
    }

    /// 清单那一族共用的**参照窗口**（今天零点 / 明天零点 / 下周一零点）。
    ///
    /// 分工：**App 层可以读系统时钟**（它就是端侧），**边界换算仍只有 `TodoWindow.of` 一处**
    /// （Core 里不读时钟，与提醒 / 日历同一条纪律）。端侧只提供「今天这个日历日 + 时区偏移」两样，
    /// 与对侧 `NotesViewModel.todoWindow()` 同口径。
    var todoWindow: TodoWindow {
        let now = Date()
        let offset = todoZoneOffsetMillis
        let today = ReminderSchedule.dateOfEpoch(
            epochMillis: Int(now.timeIntervalSince1970 * 1000),
            zoneOffsetMillis: offset
        )
        return TodoWindow.of(today: today, zoneOffsetMillis: offset)
    }

    /// 端侧**唯一**的时区偏移读数处（清单窗口 / 提醒 / 日历都从它拿）。
    ///
    /// 为什么抽出来：提醒的「提前 1 小时」与清单的「今天」必须是**同一把尺** —— 两处各读一次
    /// 系统时区，在换时区 / 夏令时那一会儿就会各自算出一个不同的日子，而两个功能各自的用例
    /// 都会是绿的（这正是「同一个数在不同文件里各算一遍」那一族）。
    var todoZoneOffsetMillis: Int {
        TimeZone.current.secondsFromGMT(for: Date()) * 1000
    }

    func beginNewTodo() {
        todoBeingEdited = nil
        // 新建态 = 编辑器那一屏：把「只读详情」那一格清掉（否则右栏还画着上一次点开的那一条的详情）。
        todoDetailID = nil
        todoEditorTitle = ""
        todoEditorHasDue = false
        todoEditorDueAt = Date()
        todoEditorPriority = .normal
        todoEditorTags = ""
        todoEditorRepeat = nil
        todoEditorNote = ""
    }

    // MARK: - 五列就地改（`FR-NTS-TODO-LIST-002` 判据①：五列都显示且可改）

    /// 正在就地改的那一行（`nil` = 没有一行在改）。
    /// **一行只一个**：两行同时在改就有两份草稿、两条写路，判据①「同一次写入」在形状上就不成立。
    @Published var todoInlineEditingID: UUID?
    @Published var todoInlineTitle = ""
    @Published var todoInlineHasDue = false
    @Published var todoInlineDueAt = Date()
    @Published var todoInlinePriority: TodoPriority = .normal
    @Published var todoInlineTags = ""

    /// 进就地改：草稿从**库里那一份**灌进来（与编辑面 `edit(_:)` 同一条纪律：
    /// 草稿永远是某个已知状态的拷贝，不是界面自己攒的）。
    func beginTodoInlineEdit(_ todo: Todo) {
        todoInlineEditingID = todo.id
        todoInlineTitle = todo.title
        todoInlineHasDue = todo.dueAt != nil
        todoInlineDueAt = todo.dueAt ?? Date()
        todoInlinePriority = todo.priority
        todoInlineTags = todo.tags.joined(separator: " ")
    }

    /// 退出就地改（Esc / 改到一半点别处）：**什么都不写**。
    func cancelTodoInlineEdit() {
        todoInlineEditingID = nil
    }

    /// 就地改的提交：五列**一次写完**，仍是一次 `upsert`（同一次写入、同一行）。
    ///
    /// 认不出的 id（那一行已被别处删掉）⇒ 静默收起草稿，**不假装改成了**。
    func commitTodoInlineEdit() async {
        guard notesEnabled else {
            statusMessage = L(.licenseNotesNotIncluded)
            return
        }
        guard let id = todoInlineEditingID,
              var value = todos.first(where: { $0.id == id }) else {
            todoInlineEditingID = nil
            return
        }
        let now = Date()
        value = TodoInlineEdit.settingTitle(todoInlineTitle, on: value, now: now)
        value = TodoInlineEdit.settingDueAt(todoInlineHasDue ? todoInlineDueAt : nil, on: value, now: now)
        value = TodoInlineEdit.settingPriority(todoInlinePriority, on: value, now: now)
        value = TodoInlineEdit.settingTags(todoInlineTags, on: value, now: now)
        do {
            _ = try await NoteLibrary.defaultLibrary().upsert(value)
            todoInlineEditingID = nil
            await reloadTodos()
            await enqueueCloudSync(uid: value.id.uuidString, family: .todo)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 优先级那一列的直接入口（判据①「五列都可改」的第五格之外的那一格）：
    /// 点行上的优先级 ⇒ 三档菜单 ⇒ **只改这一格**，一次 `upsert`、不经过编辑面。
    func setTodoPriorityInline(_ todo: Todo, _ priority: TodoPriority) async {
        guard notesEnabled else {
            statusMessage = L(.licenseNotesNotIncluded)
            return
        }
        guard priority != todo.priority else { return }
        do {
            let value = TodoInlineEdit.settingPriority(priority, on: todo)
            _ = try await NoteLibrary.defaultLibrary().upsert(value)
            await reloadTodos()
            await enqueueCloudSync(uid: value.id.uuidString, family: .todo)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    // MARK: - 删除可撤销（`FR-NTS-TODO-LIST-002` 判据③）

    /// 删掉的那一条的完整快照（删前抓；撤销时原样写回）。
    /// 只留**最近一次**：需求给的是「当场的那个撤销」，不是回收站（理由见 `TodoRemovalUndo`）。
    @Published var todoUndoRemoval: TodoRemovalUndo?

    /// 撤销上一次删除：同 id、同全部字段写回（一次 `upsert`，不产生第二条）。
    func undoLastTodoRemoval() async {
        guard notesEnabled else {
            statusMessage = L(.licenseNotesNotIncluded)
            return
        }
        guard let undo = todoUndoRemoval else { return }
        do {
            let restored = undo.restored()
            _ = try await NoteLibrary.defaultLibrary().upsert(restored)
            todoUndoRemoval = nil
            await reloadTodos()
            await reloadReminders()
            statusMessage = L(.todoRemovalUndone)
            await enqueueCloudSync(uid: restored.id.uuidString, family: .todo)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    // MARK: - 待办「重复」那一格（`FR-NTS-TODO-LIST-001` 判据①的第四个字段）

    /// 编辑器当前落在哪一档（回显用；`nil` 规则 ⇒ `.none`）。
    var todoEditorRepeatMode: TodoRepeatMode { todoEditorRepeat?.mode ?? .none }

    /// 切档：**取值与归一都来自 Core**（`TodoRepeat.defaultValue(for:)`），这里只接受那一个结果。
    func setTodoEditorRepeatMode(_ mode: TodoRepeatMode) {
        // 同档位再点一次不该把用户已经调好的次数重置掉 —— 只在**真的换档**时换值。
        if todoEditorRepeatMode == mode { return }
        todoEditorRepeat = TodoRepeat.defaultValue(for: mode)
    }

    /// 间隔次数（1...30；`< 1` 归一在 Core，界面只给合法范围）。
    func setTodoEditorRepeatCount(_ count: Int) {
        guard let current = todoEditorRepeat, current.rule == .interval else { return }
        todoEditorRepeat = TodoRepeat(
            rule: .interval,
            intervalCount: max(1, count),
            intervalUnit: current.intervalUnit
        ).normalized()
    }

    /// 间隔单位（天 / 周）。
    func setTodoEditorRepeatUnit(_ unit: ReminderUnit) {
        guard let current = todoEditorRepeat, current.rule == .interval else { return }
        todoEditorRepeat = TodoRepeat(
            rule: .interval,
            intervalCount: current.intervalCount,
            intervalUnit: unit
        ).normalized()
    }

    /// 周内某一天的开 / 关。**一天都不剩时保持最后一天**（不是把规则清空）：
    /// 清空是「不重复」那一档的事，这里只是勾选 —— 静默变成「不重复」会让用户以为勾掉了没生效。
    func toggleTodoEditorRepeatWeekday(_ weekday: Int) {
        guard let current = todoEditorRepeat, current.rule == .weekly else { return }
        var days = current.weekdays
        if let index = days.firstIndex(of: weekday) {
            guard days.count > 1 else { return }
            days.remove(at: index)
        } else {
            days.append(weekday)
        }
        todoEditorRepeat = TodoRepeat.weekly(days)
    }

    /// **点清单里的一行 ⇒ 只读详情**（片 `TD-LIST-1` · 派单 `T-20261009-026` 的 A6）。
    ///
    /// 与 `edit(_:)` 明确分开（**只读 ≠ 编辑**）：这里只把「看哪一条」记下来，**不进编辑态**
    /// （清掉 `todoBeingEdited`）—— 于是右栏出的是 `TodoDetailView`（无编辑控件），
    /// 而不是把同一份数据灌进编辑器（那样「点一下」就等于「可改」，是这一片要挡掉的形状）。
    func showTodoDetail(_ todo: Todo) {
        todoBeingEdited = nil
        todoDetailID = todo.id
    }

    /// **右栏那一屏的只读详情**（`nil` = 不画详情 ⇒ 画编辑器）。
    ///
    /// 三件事一起回答，所以收在一处（散在视图里就会出现「编辑态与详情态同时成立」这种自相矛盾的屏）：
    /// ① 在编辑 ⇒ 不给详情（编辑器优先，`edit(_:)` 已经把这一格清掉了）；
    /// ② 那一格为空 ⇒ 不给详情；
    /// ③ 详情那一条**必须还在库里**（被删掉的 id ⇒ 退回编辑器那一屏，而不是画一条已经不存在的任务）。
    var todoDetailTodo: Todo? {
        guard todoBeingEdited == nil, let id = todoDetailID else { return nil }
        return todos.first { $0.id == id }
    }

    func edit(_ todo: Todo) {
        // 进编辑器 = 与「只读详情」互斥（右栏只画得下一样）。
        todoDetailID = nil
        todoBeingEdited = todo.id
        todoEditorTitle = todo.title
        todoEditorHasDue = todo.dueAt != nil
        todoEditorDueAt = todo.dueAt ?? Date()
        todoEditorPriority = todo.priority
        todoEditorTags = todo.tags.joined(separator: " ")
        todoEditorRepeat = todo.repeatRule
        todoEditorNote = todo.note
        // 档位回显（界面入口半）：这条任务已经挂着提醒 ⇒ 档位选择器落在**它那一档**上
        // （重算不出来 = 那条规则不是四个档位之一 ⇒ 回落默认档，但那条规则照样照实显示）。
        let existing = todoReminders[todo.id]?.spec
        todoReminderPreset = existing.flatMap {
            ReminderPresentation.preset(of: $0, dueAt: todo.dueAt, zoneOffsetMillis: todoZoneOffsetMillis)
        } ?? ReminderPreset.presetDefault
    }

    /// 正在编辑哪一条（`nil` = 新建）。视图据此决定「删除」这枚按钮画不画。
    var todoEditingID: UUID? { todoBeingEdited }

    /// 「编辑器里到底有没有可保存的内容」—— 与 `noteEditorHasContent` **同一条形状**（`L-50`）：
    /// 视图那枚「保存」的灰着与 `saveTodoFromEditor()` 的第一句内容守卫读**同一句**
    /// （两处各写一遍必然分家：一边灰着、一边还能点进去）。
    var todoEditorHasContent: Bool {
        !todoEditorTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 保存（新建 / 编辑）。三条纪律：
    ///  ① **完成态与完成时刻只认库里那一份**（门面 `upsert` 保证）⇒ 「打开一条已完成的任务、
    ///     改个标题、保存」不会把它静默改回未完成；
    ///  ② **清截止是显式动作**：界面那枚「有截止时间」关掉时 `dueAt` 写 `nil`
    ///     （截止时间跟着调用方走 —— 门面就是这么定的）；
    ///  ③ 新建那条的 `createdAt` / `updatedAt` 由 `Todo` 的默认值给（改的那条显式刷新 `updatedAt`）。
    func saveTodoFromEditor() async {
        guard notesEnabled else {
            statusMessage = L(.licenseNotesNotIncluded)
            return
        }
        guard todoEditorHasContent else { return }
        let title = todoEditorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = todoEditorTags
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "，" })
            .map(String.init)
        var value = todoBeingEdited.flatMap { id in todos.first { $0.id == id } } ?? Todo(title: title)
        value.title = title
        value.dueAt = todoEditorHasDue ? todoEditorDueAt : nil
        value.priority = todoEditorPriority
        value.tags = tags
        // 重复规则：存的是**归一后**的那一份（`TodoRepeat.normalized()`；`nil` = 不重复）。
        value.repeatRule = todoEditorRepeat?.normalized()
        value.note = todoEditorNote
        if todoBeingEdited != nil { value.updatedAt = Date() }
        do {
            _ = try await NoteLibrary.defaultLibrary().upsert(value)
            await reloadTodos()
            await enqueueCloudSync(uid: value.id.uuidString, family: .todo)
            beginNewTodo()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 完成 / 重开。`FR-NOTE-36`：完成态切换**不丢**原始截止时间 —— 那条纪律在库里
    /// （写路只有 `setDone` 一条，它碰不到 `due_at` 那一列），这里只调它。
    /// 认不出的 id ⇒ 门面回 `0` ⇒ **如实说一句**，不假装改成了。
    func toggleTodoDone(_ todo: Todo) async {
        guard notesEnabled else {
            statusMessage = L(.licenseNotesNotIncluded)
            return
        }
        do {
            let changed = try await NoteLibrary.defaultLibrary().setDone(id: todo.id, !todo.done)
            if changed == 0 { statusMessage = L(.todoMissing) }
            await reloadTodos()
            // 完成 / 重开也是任务本体的一次变更 ⇒ 与保存走同一条上行（判据②「同一条链路」）。
            if changed > 0 { await enqueueCloudSync(uid: todo.id.uuidString, family: .todo) }
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func deleteTodo(id: UUID) async {
        guard notesEnabled else {
            statusMessage = L(.licenseNotesNotIncluded)
            return
        }
        do {
            // 系统的通知**不归库的级联管**（`ON DELETE CASCADE` 只清库里的行）⇒ 删任务时
            // 同批把它已经排上的那一条撤掉（库与通知中心两处必须一起变）。
            let pending = todoReminders[id]
            // **删除可撤销**（`FR-NTS-TODO-LIST-002` 判据③）：删之前把那一行整份留下 ——
            // 撤回来的必须是同一条（同 id、同备注、同重复规则、同标签），不是「一条新的同名任务」。
            if let removed = todos.first(where: { $0.id == id }) {
                todoUndoRemoval = TodoRemovalUndo(todo: removed)
            }
            try await NoteLibrary.defaultLibrary().deleteTodo(id: id)
            if let pending { await reminderDeliverer.cancel(id: pending.id) }
            if todoBeingEdited == id { beginNewTodo() }
            // 删掉的正是右栏详情那一条 ⇒ 收掉那一屏（不然右栏会画一条已经不在库里的任务）。
            if todoDetailID == id { todoDetailID = nil }
            await reloadTodos()
            await reloadReminders()
            // 墓碑上行（`IR-17`）：队列只记「欠哪一条删」，正文不需要（`flush` 现造墓碑行）。
            await enqueueCloudSync(uid: id.uuidString, operation: .delete, family: .todo)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }


    // MARK: - 任务 ↔ 笔记的转化（`FR-NTS-TODO-LINK-001` · 概设 §15.14）

    /// 库里的全部链接（界面一次读齐 —— 「对方还在不在」靠它与 `notes` / `todos` 现算）。
    /// **判据⑤ 的前提**：链接行不随对象级联删，所以对象没了这一行还在，快照就还在。
    @Published var todoNoteLinks: [TodoNoteLink] = []

    func reloadTodoLinks() async {
        guard notesEnabled else {
            todoNoteLinks = []
            return
        }
        do {
            todoNoteLinks = try await NoteLibrary.defaultLibrary().links()
        } catch {
            // 读链接失败**不许**把上一次的读数留着（那会画出已经不存在的「来自笔记」行）；
            // 也不弹错 —— 清单 / 笔记本身是好的，这一屏只是少一行关联。
            todoNoteLinks = []
        }
    }

    /// 正文区当前这一条（**没有 id 的草稿不算**：链接要给两端各一个 id）。
    var linkingNote: Note? {
        guard let id = noteBeingEdited else { return nil }
        return notes.first { $0.id == id }
    }

    /// 一条笔记看到的关联行（判据②「双方详情都能看到」的笔记侧）。
    func linkReadings(forNote id: UUID) -> [TodoLinkReading] {
        let live = Set(todos.map(\.id))
        return todoNoteLinks
            .filter { $0.noteID == id }
            .map { TodoLinkFactory.reading(of: $0, viewer: .note, counterpartExists: live.contains($0.todoID)) }
    }

    /// 一条任务看到的关联行（任务侧）。
    func linkReadings(forTodo id: UUID) -> [TodoLinkReading] {
        let live = Set(notes.map(\.id))
        return todoNoteLinks
            .filter { $0.todoID == id }
            .map { TodoLinkFactory.reading(of: $0, viewer: .todo, counterpartExists: live.contains($0.noteID)) }
    }

    /// 正文区那一屏要画的那几行（视图不自己 filter）。
    var linkReadingsForCurrentNote: [TodoLinkReading] {
        guard let note = linkingNote else { return [] }
        return linkReadings(forNote: note.id)
    }

    /// **笔记 ⇒ 任务**（判据①：只造新任务，原笔记一个字节都不改）。
    ///
    /// 「新建到可见」的那一下在这里：写完库立刻 `reloadTodos()` —— 清单里当场多一行，
    /// 不需要用户再按一次刷新（概设 §15.14 与清单那一条同一纪律）。
    func createTodoFromNote(_ note: Note) async {
        guard notesEnabled else {
            statusMessage = L(.licenseNotesNotIncluded)
            return
        }
        let todo = TodoLinkFactory.todo(from: note, fallbackTitle: L(.notesUntitled))
        do {
            let library = NoteLibrary.defaultLibrary()
            let saved = try await library.upsert(todo)
            let link = TodoLinkFactory.link(note: note, todo: saved, origin: .fromNote)
            _ = try await library.saveLink(link)
            await reloadTodos()
            await reloadTodoLinks()
            await enqueueCloudSync(uid: saved.id.uuidString, family: .todo)
            statusMessage = L(.todoLinkCreatedTodo, TodoPresentation.title(saved) ?? L(.notesUntitled))
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// **任务 ⇒ 笔记**（判据①：只造新笔记，原任务一个字节都不改）。
    func createNoteFromTodo(_ todo: Todo) async {
        guard notesEnabled else {
            statusMessage = L(.licenseNotesNotIncluded)
            return
        }
        let note = TodoLinkFactory.note(from: todo, fallbackTitle: L(.notesUntitled))
        do {
            let library = NoteLibrary.defaultLibrary()
            let saved = try await library.save(
                NoteDraft(title: note.title, body: note.body, tags: note.tags, source: note.source),
                id: note.id
            )
            let link = TodoLinkFactory.link(note: saved, todo: todo, origin: .fromTodo)
            _ = try await library.saveLink(link)
            await reloadNotes()
            await reloadTodoLinks()
            flushNoteAutosave()
            loadEditorContent(saved)
            editorMode = .preview
            notesModule = .notes
            statusMessage = L(.todoLinkCreatedNote, note.title)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// **撤销**（判据③）：删掉**这次生成的那一个**，再销掉链接；源头一个字不动。
    /// 两次删除分开做，任一步失败都如实说 —— 不做「删了一半也算成功」。
    func undoConversion(linkID: UUID) async {
        guard let link = todoNoteLinks.first(where: { $0.id == linkID }) else {
            statusMessage = L(.todoLinkMissingObject)
            return
        }
        do {
            let library = NoteLibrary.defaultLibrary()
            switch TodoLinkFactory.undoTarget(of: link) {
            case .todo(let id):
                try await library.deleteTodo(id: id)
                if let pending = todoReminders[id] { await reminderDeliverer.cancel(id: pending.id) }
                await reloadTodos()
                await reloadReminders()
            case .note(let id):
                _ = try await library.delete(id: id, at: Date())
                await reloadNotes()
            }
            _ = try await library.deleteLink(id: link.id)
            await reloadTodoLinks()
            statusMessage = L(.todoLinkUndoneStatus)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// **跳转**（判据②「可直接跳到对方」）：按对方是哪一面换屏 + 打开那一条。
    /// 对方已被删 ⇒ 如实说一句（不假装跳过去）。
    func openLinkedCounterpart(_ reading: TodoLinkReading) {
        if reading.counterpartMissing {
            statusMessage = L(.todoLinkMissingObject)
            return
        }
        switch reading.counterpart {
        case .todo:
            notesModule = .todos
            todoBeingEdited = nil
            todoDetailID = reading.counterpartID
        case .note:
            guard let note = notes.first(where: { $0.id == reading.counterpartID }) else {
                statusMessage = L(.todoLinkMissingObject)
                return
            }
            notesModule = .notes
            flushNoteAutosave()
            handleNoteRowClick(note, modifiers: [])
        }
    }

    // MARK: - 单条删除的确认（人类主人令 `T-20261007-079` ② / `T-20261007-081`）

    /// 点「删除」：把要删的东西摆到确认框上，**先不落库**。
    ///
    /// 判据的落点（`TestsUISnapshot/NotesLayoutProbeTests.swift`）：调它之后**条目数不变** ——
    /// 真正的库动作在 `confirmNoteRemoval()`。这就是「破坏性操作先问一次」那句话的机械形状：
    /// 点删除 ⇒ 只挂请求；确认 ⇒ 才 `deleteNote` / `deleteTodo`；取消 ⇒ 库一个字节不动。
    func requestNoteRemoval() {
        switch notesModule {
        case .notes:
            let ids = selectedNoteIDs
            guard !ids.isEmpty else {
                // **不许静默**（人类主人真机点验缺陷 `T-20261009-161`）：没有选中任何一条时
                // 给一句人话。改前这里 `pendingNoteRemoval = nil; return` —— 不弹框、不提示、
                // 什么都不发生，用户看到的就是"点了删除没反应"。
                pendingNoteRemoval = nil
                statusMessage = L(.notesRemoveNoSelection)
                return
            }
            let subject = ids.count == 1
                ? (notes.first { $0.id == ids.first }?.title ?? "")
                : ""
            pendingNoteRemoval = NoteRemovalPrompt.request(target: .notes(Array(ids)), subject: subject)
            // **先读附件条数**（`FR-NTS-NOTE-ATTACH-001` 判据③）：确认框那句正文要说「这条挂着 N 个附件，
            // 删笔记不动文件」。读库是异步的，所以这里发一发，框上那句话随读数更新。
            Task { await loadAttachmentsForPendingRemoval() }
        case .todos:
            guard let id = todoEditingID else {
                pendingNoteRemoval = nil
                statusMessage = L(.notesRemoveNoSelection)
                return
            }
            let subject = todos.first { $0.id == id }?.title ?? ""
            pendingNoteRemoval = NoteRemovalPrompt.request(target: .todo(id), subject: subject)
        }
    }

    /// **行内右键那一枚「删除」的入口**（片 `A5-DEL` · 派单 `T-20261009-038`）：把**被点的那一条**待办
    /// 摆到**同一个**确认框上，先不落库。
    ///
    /// 为什么另开一个「按 id」的入口而不复用 `requestNoteRemoval()`：那个函数按 `notesModule` 分流、
    /// 待办那一支取的是 `todoEditingID`（编辑器里那一条）—— 而行内右键发生在清单 / 日历那一栏，与
    /// 「正在编辑哪一条」无关，硬塞进去会把「右键的那条」与「编辑器那条」糊成一个（右键删 A、确认删 B）。
    /// 出口与 `requestNoteRemoval()` 的 `.todos` 分支**同一处**（`NoteRemovalPrompt.request`）——
    /// 待办的三处删除入口（左区顶部 / 编辑面 / 行内右键）由此全经确认框。
    /// 判据：`TestsUISnapshot/NotesLayoutProbeTests.swift`（点删除后条目数不变，直到确认）。
    func requestTodoRemoval(id: UUID) {
        let subject = todos.first { $0.id == id }?.title ?? ""
        pendingNoteRemoval = NoteRemovalPrompt.request(target: .todo(id), subject: subject)
    }

    /// 退出口（按 ESC / 点框外 / 点「取消」）：只收掉请求，库一个字节不动。
    func cancelNoteRemoval() {
        pendingNoteRemoval = nil
    }

    /// 确认框标题（**唯一生产点**）：单条写明名字，多选写「删除」（条数放到正文那句里）。
    /// 视图不自己拼句子 —— 拼错一次就是「要删除「」吗？」这种与事实相反的交代。
    var pendingNoteRemovalTitle: String? {
        guard let request = pendingNoteRemoval else { return nil }
        if case .notes = request.target, request.target.isMultipleNotes {
            return L(.notesDelete)
        }
        return L(.notesRemoveConfirmTitle, request.subject)
    }

    /// 确认框正文（多选才写条数；单条的名字已经在标题里了）。
    ///
    /// **附件那一句也要在这里说**（`FR-NTS-NOTE-ATTACH-001` 判据③）：删笔记只删索引、不动文件 ——
    /// 不提前说，用户会以为「删了就是删干净了」，那些文件却还在盘上。
    var pendingNoteRemovalMessage: String? {
        guard let request = pendingNoteRemoval else { return nil }
        var lines: [String] = []
        if request.target.isMultipleNotes {
            lines.append(L(.notesRemoveSummaryNotes, request.target.count))
        }
        let attachmentCount: Int = pendingNoteRemovalAttachmentCount
        if attachmentCount > 0 {
            lines.append(L(.notesAttachmentCleanupMessage, Int(attachmentCount)))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// 用户在确认框里点了「删除」：**这才落库**，然后重读库。
    func confirmNoteRemoval() async {
        guard let request = pendingNoteRemoval else { return }
        pendingNoteRemoval = nil
        switch request.target {
        case .notes(let ids):
            pendingAttachmentCleanup = []
            for id in ids { await deleteNote(id: id) }
            noteAttachmentsForDeletion = [:]
            // **附件文件另行确认**（判据③）：上面那些 `deleteNote` 只把清单攒起来，一个文件都没删。
            // 这里只负责把框挂出来 —— 「保留」与「一起删」两个出口都是人按的。
            isAttachmentCleanupPresented = !pendingAttachmentCleanup.isEmpty
        case .todo(let id):
            await deleteTodo(id: id)
        }
    }

    // MARK: - 待办：提醒的界面入口（队列 `L-100` 落法 ④「有截止时间的任务一键挂提醒」）

    /// 「提醒」区那一份合成状态（**唯一合成处** = `ReminderEntry.make`；视图不许自己拼一份）。
    ///
    /// 参照时刻与偏移都由端侧给（Core 不读表）—— 与 `todoWindow` 共用**同一个** `todoZoneOffsetMillis`。
    func todoReminderEntry(for todo: Todo) -> ReminderEntry {
        ReminderEntry.make(
            dueAt: todo.dueAt,
            preset: todoReminderPreset,
            existing: todoReminders[todo.id]?.spec,
            permission: reminderPermission,
            now: Date(),
            zoneOffsetMillis: todoZoneOffsetMillis
        )
    }

    /// 换档位（四档）。切档**不写库、不排通知** —— 它只换「下一次点『挂提醒』会用哪一档」。
    func setTodoReminderPreset(_ preset: ReminderPreset) {
        todoReminderPreset = preset
    }

    /// 读提醒（`NoteLibrary.reminders()`：**库不存在 ⇒ 空表**，不顺手建库）。
    ///
    /// 一条任务上有多条提醒时取**最早建的那一条**：界面那一枚标记只回答「有没有」，
    /// 多条并存是提醒编辑器（本片之外）的事。
    func reloadReminders() async {
        guard notesEnabled else {
            todoReminders = [:]
            return
        }
        do {
            let all = try await NoteLibrary.defaultLibrary().reminders()
            let byTodo = all.compactMap { reminder in
                reminder.owner.todoID.map { ($0, reminder) }
            }
            todoReminders = Dictionary(byTodo, uniquingKeysWith: { $0.createdAt <= $1.createdAt ? $0 : $1 })
        } catch {
            todoReminders = [:]
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 读一次系统通知权限那一档（进待办那一屏时读；读不出来 ⇒ 未决）。
    func refreshReminderPermission() async {
        reminderPermission = await reminderDeliverer.permission()
    }

    /// **一键挂提醒**：算规则（Core）→ 落库（门面）→ 按权限那一档决定现在排不排。
    ///
    /// 三步各有其主：**能不能挂**是 Core 的判定（`attachment`；不能挂时说一句原因，**不静默**）、
    /// **落库**只有门面一条路、**排不排**也是 Core 的判定（`notificationDecision`）——
    /// 这一层只是把「排」的执行交给通知那一层的适配器。
    func attachReminder(to todo: Todo) async {
        guard notesEnabled else {
            statusMessage = L(.licenseNotesNotIncluded)
            return
        }
        let entry = todoReminderEntry(for: todo)
        guard let spec = entry.attachment.spec else {
            statusMessage = L(entry.attachment.reasonKey ?? .reminderNeedsDue)
            return
        }
        do {
            var value = todoReminders[todo.id] ?? Reminder(owner: .todo(todo.id), spec: spec)
            value.spec = spec
            value.updatedAt = Date()
            try await NoteLibrary.defaultLibrary().addReminder(value)
            await reloadReminders()
            await deliverReminder(todo: todo, reminder: value)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 移除这一条任务的提醒：库里删掉那一条，**并把已经排上的系统通知一并撤掉**
    /// （不撤就是「删了提醒却照样响」—— 用户最难查的那种）。
    func removeReminder(from todo: Todo) async {
        guard let existing = todoReminders[todo.id] else { return }
        do {
            try await NoteLibrary.defaultLibrary().deleteReminder(id: existing.id)
            await reminderDeliverer.cancel(id: existing.id)
            await reloadReminders()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 把一条**已经在库里**的提醒交给系统通知（**唯一的投递处**）。
    ///
    /// 未决 ⇒ 先问一次权限（用户已经选过就不再弹框，由适配器判）；问完仍读不出 ⇒ 如实说一句；
    /// 已授权且有待发时刻 ⇒ 现算触发瞬间排上；被拒 / 已结束 / 规则认不出 ⇒ 各出各的话（不静默不响）。
    func deliverReminder(todo: Todo, reminder: Reminder) async {
        var permission = reminderPermission
        if permission == .notDetermined {
            permission = await reminderDeliverer.requestPermission()
            reminderPermission = permission
        }
        guard permission != .notDetermined else {
            statusMessage = L(.reminderPermissionNotDetermined)
            return
        }
        let entry = ReminderEntry.make(
            dueAt: todo.dueAt,
            preset: todoReminderPreset,
            existing: reminder.spec,
            permission: permission,
            now: Date(),
            zoneOffsetMillis: todoZoneOffsetMillis
        )
        switch entry.decision {
        case .schedule(let triggerEpochMillis):
            await reminderDeliverer.schedule(
                id: reminder.id,
                title: ReminderPresentation.notificationTitle(todo.title) ?? L(.notesUntitled),
                body: ReminderPresentation.notificationBody(
                    entry.plan.due,
                    language: LocalizationManager.shared.effectiveLanguage
                ),
                triggerEpochMillis: triggerEpochMillis
            )
        case .askPermission:
            statusMessage = L(.reminderPermissionNotDetermined)
        case .inactive(let key):
            statusMessage = L(key)
        }
    }

    /// 清单那一屏（**唯一查询入口** = `TodoQuery.board`）：筛 → 排 → 分区 → 归堆一次算完。
    ///
    /// 为什么不让视图各调各的：界面若自己 `filter` 一遍再 `sorted` 一遍，就是第二套「哪些行进来、
    /// 按什么排」（两套各自的用例都会是绿的 —— 对侧 `check-ui-parity.py` 的 V 条就是为这一族立的）。
    /// 参照窗口仍是 `todoWindow`（端侧唯一的时钟读数处，Core 不读表）。
    var todoBoard: TodoBoard {
        TodoQuery.board(
            todos,
            filter: todoFilter,
            search: todoSearchText,
            window: todoWindow,
            groupBy: todoGroupBy,
            order: todoSortOrder
        )
    }

    /// 清单空态那一句该说什么（判定在 Core：`TodoQuery.emptyKind`）。
    ///
    /// 「有没有在搜」也要给（片 `TD-LIST-1`）：搜一个词一条都不命中时，库里明明有任务 ——
    /// 说成「还没有待办」就是一句假话（用户会以为任务丢了）。
    var todoEmptyKind: TodoEmptyKind {
        TodoQuery.emptyKind(
            hasAnyTask: !todos.isEmpty,
            filter: todoFilter,
            searching: !TodoSearch.normalized(todoSearchText).isEmpty
        )
    }

    /// 换排序档（三档）。切档**不重读库、不改任何一条数据** —— 它只换一屏的画法。
    func setTodoSortOrder(_ order: TodoSort.Order) {
        todoSortOrder = order
    }

    /// 换筛选档（五档）。
    func setTodoFilter(_ filter: TodoFilter) {
        todoFilter = filter
    }

    /// 换分组档（四档）。
    func setTodoGroupBy(_ groupBy: TodoGroupBy) {
        todoGroupBy = groupBy
    }

    // MARK: - 待办：日历那一屏（队列 `L-100` 界面半第二片）

    /// 切中栏（清单 / 日历）。切档**不重读库** —— 两档看的是同一份 `todos`
    /// （`FR-NOTE-39` 的唯一事实源：日历不另存任务，也就没有第二份内存态可同步）。
    func setTodoPane(_ pane: TodoPane) {
        todoPane = pane
    }

    /// 切月 / 周。
    func setTodoCalendarView(_ view: TodoCalendarView) {
        todoCalendarView = view
    }

    /// 翻页：月视图整月翻、周视图整周翻（`delta` 正负都收）。
    /// 日期算术一律走 `TodoCalendar`（本文件不自己 `date(byAdding:)` —— 那正是第二套算术的起点）。
    func shiftTodoCalendar(_ delta: Int) {
        let calendar = Calendar.current
        switch todoCalendarView {
        case .month:
            let parts = calendar.dateComponents([.year, .month], from: todoCalendarAnchor)
            guard let year = parts.year, let month = parts.month,
                  let shifted = TodoCalendar.shiftMonth(year: year, month: month, delta: delta),
                  let anchor = TodoCalendar.firstDate(year: shifted.year, month: shifted.month, calendar: calendar)
            else { return }
            todoCalendarAnchor = anchor
        case .week:
            guard let anchor = TodoCalendar.shift(
                days: delta * TodoCalendar.columns,
                from: todoCalendarAnchor,
                calendar: calendar
            ) else { return }
            todoCalendarAnchor = anchor
        }
    }

    /// 「今天」：翻回今天**并选中它**（日历上最常用的一跳）。
    func todoCalendarGoToday() {
        let today = TodoCalendar.calendarDay(of: Date(), calendar: .current)
        todoCalendarAnchor = today
        todoCalendarSelectedDay = today
    }

    /// 点某一天：锚点跟着走（翻月之后，选中态不该留在上个月里）。
    func selectTodoCalendarDay(_ date: Date) {
        let day = TodoCalendar.calendarDay(of: date, calendar: .current)
        todoCalendarAnchor = day
        todoCalendarSelectedDay = day
    }

    /// 日历的格子（月 / 周两档都走 `TodoCalendar`）—— 本文件只挑档，不算日期。
    var todoCalendarCells: [TodoCalendarCell] {
        let calendar = Calendar.current
        switch todoCalendarView {
        case .month:
            let parts = calendar.dateComponents([.year, .month], from: todoCalendarAnchor)
            guard let year = parts.year, let month = parts.month else { return [] }
            return TodoCalendar.monthCells(year: year, month: month, calendar: calendar)
        case .week:
            return TodoCalendar.weekCells(anchor: todoCalendarAnchor, calendar: calendar)
        }
    }

    /// 把任务铺到当前的格子上（**同一份 `todos`**，空的天不出现 —— 界面据此决定画不画点）。
    /// 这里只是把 `TodoCalendar.tasksByDay` 的产出摆成查表形态：投影本身仍只有那一处出处。
    var todoCalendarDays: [Date: TodoDayTasks] {
        let days = TodoCalendar.tasksByDay(
            todos,
            cells: todoCalendarCells,
            now: Date(),
            calendar: .current
        )
        return Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
    }

    /// 这一格是不是选中那一天（「同一天」只有 `TodoCalendar.calendarDay` 一处判据）。
    func isTodoCalendarSelected(_ cell: TodoCalendarCell) -> Bool {
        guard let selected = todoCalendarSelectedDay else { return false }
        return TodoCalendar.calendarDay(of: selected, calendar: .current) == cell.date
    }

    /// 这一格是不是今天。
    func isTodoCalendarToday(_ cell: TodoCalendarCell) -> Bool {
        TodoCalendar.calendarDay(of: Date(), calendar: .current) == cell.date
    }

    /// 选中那一天的两区（**段序与分区仍走 `TodoPresentation.sections`** —— 与清单屏同一处口径）；
    /// 没点过某天 ⇒ 空。
    var todoCalendarSelectedDaySections: [TodoSection] {
        guard let day = todoCalendarSelectedDay,
              let tasks = todoCalendarDays[TodoCalendar.calendarDay(of: day, calendar: .current)]
        else { return [] }
        return TodoPresentation.sections(tasks.open + tasks.done)
    }

    /// 选中那一天有没有任务（空态那句话的判据 —— 与上面那份分区同源，不另数一遍）。
    var todoCalendarSelectedDayHasTasks: Bool {
        todoCalendarSelectedDaySections.contains { $0.count > 0 }
    }

    // MARK: - 日历「选中日」那两枚入口（片 `TD-CAL-1` · 派单 `T-20261009-026`）

    /// **① 选中日直接新建**：把新建态摆成「截止 = 该日 09:00」，再交给**既有**的那份编辑器草稿。
    ///
    /// 三条口径：
    ///  ① **不新开写路**：本函数只摆草稿（`beginNewTodo()` 那几格 + 截止那两格），
    ///     落库仍是编辑器那一条（`saveTodoFromEditor()` → 门面 `upsert`）；
    ///  ② **日期换算走 Core**（`TodoCalendar.moment`）：本文件不自己拼 `DateComponents` ——
    ///     与 `calendarDay` / `shift(days:)` 同一条纪律，端侧再拼一份就是第二套「09:00 是哪一刻」；
    ///  ③ **没选中那天 ⇒ 不预填截止**：日历「不替用户选一天」（`todoCalendarSelectedDay` 头注释），
    ///     这一支就退化成普通的新建，而不是替他把截止挂到「今天」上。
    func newTodoOn(selectedDay day: Date?) {
        beginNewTodo()
        guard let day,
              let due = TodoCalendar.moment(
                  hour: Self.calendarNewTodoHour, minute: 0, on: day, calendar: .current
              )
        else { return }
        todoEditorHasDue = true
        todoEditorDueAt = due
    }

    /// 「选中日直接新建」预填的**钟点**（唯一出处：口径要改只改这一处，别在两处各写一个 9）。
    private static let calendarNewTodoHour = 9

    /// **② 写笔记**：切到笔记面并新开一篇。
    ///
    /// 两件事各走**既有**的单一入口 —— `setNotesModule(.notes)`（切面，内含「切走即存」那一步，
    /// 所以切面不丢手上这条的字）与 `beginNewNote()`（清空编辑器 + 进 `.edit`）；
    /// 本函数自己不碰库、也不自己拼编辑器内容。
    ///
    /// **为什么不带日期实参**：笔记不像待办那样挂在某一天上（`Note` 没有截止日）——
    /// 把日期塞进标题 / 正文就是替产品发明一条「日期怎么写进笔记」的口径，而那条口径**没有单据**。
    func writeNote() {
        setNotesModule(.notes)
        beginNewNote()
    }

    /// 打开「改期」框（`FR-NOTE-38` 的「日历上直接完成 / 改期」）。
    /// 没有截止时间的任务也能改期 —— 那就是给它**挂上**一个截止时间。
    func beginReschedule(_ todo: Todo) {
        todoRescheduleDraft = TodoRescheduleDraft(id: todo.id, dueAt: todo.dueAt ?? Date())
    }

    func cancelReschedule() {
        todoRescheduleDraft = nil
    }

    /// 落改期：写新的 `dueAt` + 刷 `updatedAt`（改期属**内容类编辑**，见 `Todo.updatedAt` 的说明）。
    /// 完成态**不在这里碰**（它只有 `setDone` 一条写路）—— 与编辑器保存同一条纪律。
    func applyReschedule() async {
        guard notesEnabled else {
            statusMessage = L(.licenseNotesNotIncluded)
            return
        }
        guard let draft = todoRescheduleDraft else { return }
        todoRescheduleDraft = nil
        guard var value = todos.first(where: { $0.id == draft.id }) else {
            statusMessage = L(.todoMissing)
            await reloadTodos()
            return
        }
        value.dueAt = draft.dueAt
        value.updatedAt = Date()
        do {
            _ = try await NoteLibrary.defaultLibrary().upsert(value)
            await reloadTodos()
            await enqueueCloudSync(uid: value.id.uuidString, family: .todo)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    // MARK: - 跨笔记本移动（队列 `L-97` 界面半第三片）

    /// 菜单要的那份「能移到哪」——**规则与顺序只在 Core 一处**（`NotebookMovePrompt.targets`）。
    /// 界面不自己拼清单：拼一份就会出现「菜单里有、树上没有」这种分家（`L-97` 同一课）。
    func noteMoveTargets(for noteIDs: [UUID]) -> [NotebookMoveTarget] {
        NotebookMovePrompt.targets(
            directory: notesNavigation.directory,
            placements: notesNavigation.placements,
            noteIDs: noteIDs
        )
    }

    /// 把若干条笔记移到目标笔记本（契约 §2.12 第 4 条：**只改归属、不刷新 `updatedAt`**）。
    /// 已经待在目标笔记本里的那几条**不写库** —— 视图那一侧不给选，这里是第二道；
    /// 白写一次会让「位置不是内容」这条口径变成一句空话。
    func moveNotes(_ noteIDs: [UUID], toNotebook notebookUid: String) async {
        let moves = noteIDs.filter { notesNavigation.notebookUid(forNote: $0.uuidString) != notebookUid }
        guard !moves.isEmpty else { return }
        do {
            _ = try await NoteLibrary.defaultLibrary().move(noteIDs: moves, toNotebook: notebookUid)
            await reloadNotes()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    // MARK: - 批量多选与拖拽（队列 `L-97` 界面半第五片）

    /// 界面上「已选几条」——只有多选（>1）时才显示那一行。
    var noteSelectionCount: Int { selectedNoteIDs.count }

    /// 点在笔记行上：处置**全在 Core**（`NoteSelectionRule.clicked`），这里只搬运结果。
    /// `modifiers` 由视图从当前事件读（Core 不认识 AppKit）—— 视图不许自己判修饰键：
    /// 判一次就会出现「⇧ 点了也在编辑器里换了一条」这种两处不一致。
    func handleNoteRowClick(_ note: Note, modifiers: NoteSelectionModifiers) {
        let outcome = NoteSelectionRule.clicked(
            note.id,
            modifiers: modifiers,
            ordered: visibleNotes.map(\.id),
            selection: selectedNoteIDs,
            anchor: noteSelectionAnchor
        )
        selectedNoteIDs = outcome.selection
        noteSelectionAnchor = outcome.anchor
        if let editedID = outcome.edited, let target = notes.first(where: { $0.id == editedID }) {
            // **切走即存**（片 `N2-4`）：这一下要么换到另一条、要么把同一条重新装一遍 ——
            // 两种都会**覆盖编辑器里的内容** ⇒ 先把手上这份落下去（验收判据①/②）。
            flushNoteAutosave()
            // **单击 = 预览**（片 `N2-3a`「单击预览」· 人类主人令 `T-20261007-004` 第三节第 3 条）：
            // 这一条的内容进右栏，但**正文只读**。Core 只给「要不要打开这一条」（`outcome.edited`），
            // 「打开成看 / 打开成改」是界面这一侧的事 ⇒ 模式在这里定点。
            loadEditorContent(target)
            editorMode = .preview
        }
    }

    func clearNoteSelection() {
        selectedNoteIDs = []
        noteSelectionAnchor = nil
    }

    /// 把多选集合对着**当前可见列表**收一遍（口径见 Core 那段注释：看不见却生效是最坏的一种）。
    /// 三个入口都调它：范围变了 / 检索落定 / 重读库。幂等、便宜（集合操作而已）。
    private func pruneNoteSelection() {
        let pruned = NoteSelectionRule.pruned(selectedNoteIDs, within: visibleNotes.map(\.id))
        if pruned != selectedNoteIDs { selectedNoteIDs = pruned }
        if let anchor = noteSelectionAnchor, !pruned.contains(anchor) { noteSelectionAnchor = nil }
    }

    /// 右键某一行的「移动…」/ 拖某一行时**带走哪些**（口径 ③：在选中集合里 ⇒ 整捆）。
    func noteMoveIDs(for note: Note) -> [UUID] {
        NoteSelectionRule.draggedNoteIDs(
            clicked: note.id,
            selection: selectedNoteIDs,
            ordered: visibleNotes.map(\.id)
        )
    }

    /// 拖拽载荷（**唯一生产点**）：视图不自己拼字符串（拼法与解法不一致的症状是「拖过去什么都没发生」，
    /// 而拖拽失败**没有任何报错**）。
    func noteDragPayload(for note: Note) -> String {
        NoteDragPayload.encode(noteMoveIDs(for: note))
    }

    /// 拖到某个笔记本上：解载荷 → 现算计划 → 一条都不用动就不写库（给一句人话）。
    func handleNoteDrop(payload: String?, into notebookUid: String) async {
        guard let payload else { return }
        await dropNotes(NoteDragPayload.decode(payload), into: notebookUid)
    }

    /// 落点（拖拽与批量移动共用这一条路 —— 不新写第二条写库路）。
    ///
    /// 计划由 Core 算：已经在目标里的那几条**不在 `movingNoteIDs` 里**（位置不是内容，白写一次
    /// 会让契约 §2.12 第 4 条那句「移动不刷新 `updatedAt`」变成空话）；整捆都已在 ⇒ 不写库、
    /// 给一句人话（静默什么都不发生是最坏的一种）。
    func dropNotes(_ noteIDs: [UUID], into notebookUid: String) async {
        guard !noteIDs.isEmpty else { return }
        let plan = NoteDropRule.plan(
            noteIDs: noteIDs,
            toNotebook: notebookUid,
            directory: notesNavigation.directory,
            placements: notesNavigation.placements
        )
        guard !plan.isNoop else {
            statusMessage = L(NoteSelectionPrompt.alreadyThereKey, plan.targetNotebookName)
            return
        }
        await moveNotes(plan.movingNoteIDs, toNotebook: plan.targetNotebookUid)
    }

    // MARK: - 容器编辑：新建 / 重命名 / 排序（队列 `L-97` 界面半第四片）

    /// 「这个名字能不能落库」——**判据属性（唯一出处）**：编辑弹框里「确定」的 `.disabled`
    /// 与 `commitContainerEdit` 的第一句守卫**必须是同一条判断**（`L-50` 那一课）。
    var containerEditNameIsAcceptable: Bool {
        ContainerNameRule.isAcceptable(containerEditName)
    }

    /// 弹框标题：新建与重命名不是同一件事（重命名框里预填原名、新建是空的）。
    var containerEditTitle: String {
        switch pendingContainerEdit?.mode {
        case .createNotebook: return L(NotebookCreation.titleKey)
        case .rename: return L(ContainerEditPrompt.titleKey)
        case nil: return ""
        }
    }

    /// **新建笔记本**（入口）：落点由 Core 按**当前范围**给（架里 ⇒ 那个架；笔记本里 ⇒ 它所属的架；
    /// 全部 ⇒ 默认架）。从某一行的右键进来时用 `inShelf` 显式指定那一行自己的架 ——
    /// 右键一个架却把笔记本建到别处，是「点了没反应」之外最让人困惑的一种。
    /// 一个架都没有 ⇒ **不弹框**，只给一句人话（弹一个落不了地的框是把两种事实混成一件）。
    func beginNewNotebook(inShelf shelfUid: String? = nil) {
        let directory = notesNavigation.directory
        let destination: String?
        if let shelfUid {
            destination = directory.shelf(uid: shelfUid)?.uid
        } else {
            destination = NotebookCreation.destinationShelfUid(for: notesScope, directory: directory)
        }
        guard let destination else {
            statusMessage = L(NotebookCreation.noShelfKey)
            return
        }
        containerEditName = ""
        pendingContainerEdit = ContainerEditRequest(
            id: destination,
            mode: .createNotebook,
            kind: .notebook,
            currentName: "",
            destinationShelfUid: destination,
            isDefault: false
        )
    }

    /// **重命名**（入口）：默认架 / 默认笔记本**也可改名**（契约 §2.12 第 2 条：不可删、可改名）
    /// —— 这里刻意不判 `isDefault`，它只用来让界面如实交代「默认容器删不掉、但可以改名」。
    func beginRenameContainer(kind: NotebookContainerKind, uid: String, name: String, isDefault: Bool) {
        containerEditName = name
        pendingContainerEdit = ContainerEditRequest(
            id: uid,
            mode: .rename,
            kind: kind,
            currentName: name,
            destinationShelfUid: nil,
            isDefault: isDefault
        )
    }

    /// 退出口（按 ESC / 点框外）：只收掉请求，库一个字节不动。
    func cancelContainerEdit() {
        pendingContainerEdit = nil
        containerEditName = ""
    }

    /// 点「确定」：**先同步取走**这一次编辑（请求 + 洗净后的名字），再异步落库。
    ///
    /// 为什么不在 `Task` 里读 `pendingContainerEdit`：弹框一关，`isPresented` 的 `set` 就会
    /// 把请求收掉（按 ESC / 点框外走的也是它）—— 两个动作谁先谁后由 SwiftUI 定，读晚一步的
    /// 症状正是「点了确定、什么都没发生」（`L-50` 那一族里最坏的一种）。
    /// 判据属性 `containerEditNameIsAcceptable` 是「确定」灰着那条判断的**唯一出处**。
    func confirmContainerEdit() {
        guard let request = pendingContainerEdit, containerEditNameIsAcceptable else {
            cancelContainerEdit()
            return
        }
        let name = ContainerNameRule.sanitized(containerEditName)
        pendingContainerEdit = nil
        containerEditName = ""
        Task { await applyContainerEdit(request, name: name) }
    }

    /// 编辑落库（**一个入口**）：新建 / 重命名各一条路，落完都**重新读库**
    /// （树、条数、范围归一会跟着变）。名字与请求都是**调用时传进来的那一份**，
    /// 不再回读界面状态 —— 界面早已关掉。
    private func applyContainerEdit(_ request: ContainerEditRequest, name: String) async {
        do {
            let library = NoteLibrary.defaultLibrary()
            switch request.mode {
            case .createNotebook:
                if let shelfUid = request.destinationShelfUid {
                    _ = try await library.createNotebook(inShelf: shelfUid, name: name)
                }
            case .rename:
                if request.kind == .shelf {
                    _ = try await library.renameShelf(uid: request.id, name: name)
                } else {
                    _ = try await library.renameNotebook(uid: request.id, name: name)
                }
            }
            await reloadNotes()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 排序：能不能挪这一步（视图的 `.disabled` 读它，规则在 Core `ContainerReorder`）。
    func canMoveContainer(kind: NotebookContainerKind, uid: String, direction: ContainerReorderDirection) -> Bool {
        ContainerReorder.canMove(
            kind: kind,
            containerUid: uid,
            direction: direction,
            directory: notesNavigation.directory
        )
    }

    /// 排序：挪一步（写库 + 重读）。挪不动（已在最前 / 最后 / 认不出）⇒ 不写库 —— 视图那侧本来
    /// 就不给点，这里是第二道（与 `moveNotes` 同族）。
    func moveContainer(kind: NotebookContainerKind, uid: String, direction: ContainerReorderDirection) async {
        do {
            let moved = try await NoteLibrary.defaultLibrary().reorder(
                kind: kind,
                containerUid: uid,
                direction: direction
            )
            guard moved else { return }
            await reloadNotes()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    // MARK: - 跨架移动（队列 `L-97` 界面半第六片：落法 ① 的第四格）

    /// 菜单要的那份「这个笔记本能挪到哪些架」——**规则与顺序只在 Core 一处**
    /// （`NotebookShelfMovePrompt.targets`）：界面不自己拼清单，拼一份就会出现
    /// 「菜单里有、树上没有」这种分家（`L-97` 同一课）。
    func notebookShelfMoveTargets(for notebookUid: String) -> [NotebookShelfMoveTarget] {
        NotebookShelfMovePrompt.targets(notebookUid: notebookUid, directory: notesNavigation.directory)
    }

    /// 把一个笔记本挪到另一个架（落库只改 `shelf_uid` + 排序位；**不碰** `createdAt` /
    /// `isDefault`，也不碰里面的笔记）。
    ///
    /// 落库前的守卫走 Core 的 `moveDestination`（**唯一一处判定**）：认不出的笔记本 /
    /// 认不出的目标架 / 已经在该架 ⇒ 不写库。视图那一侧本来就不给点（清单里 `isSelectable`
    /// 由同一个 `isCurrent` 算出来），这里是第二道；白写一次库只是把「点了没反应」从界面挪到库里。
    func moveNotebook(uid: String, toShelf shelfUid: String) async {
        guard let destination = NotebookShelfMovePrompt.moveDestination(
            notebookUid: uid,
            targetShelfUid: shelfUid,
            directory: notesNavigation.directory
        ) else { return }
        do {
            _ = try await NoteLibrary.defaultLibrary().moveNotebook(uid: uid, toShelf: destination)
            await reloadNotes()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    // MARK: - 外部调用审批（FR-AI-10 界面那一半）

    /// 队列位置由 Core 给（两侧必须算同一个路径，界面写的决定 CLI 才读得到）。
    var mcpApprovalStore: MCPApprovalStore { MCPApprovalStore.defaultStore() }

    func openMCPApprovals() {
        mcpApprovalMessage = nil
        refreshMCPApprovals()
        isMCPApprovalPresented = true
        startMCPApprovalWatching()
    }

    func closeMCPApprovals() {
        mcpApprovalWatcher?.cancel()
        mcpApprovalWatcher = nil
        isMCPApprovalPresented = false
    }

    /// 轮询队列：外部调用可能在我们看别处时进来（**界面上要能"冒出来"**，
    /// 否则用户永远不知道有人在等审批）。
    private func startMCPApprovalWatching() {
        mcpApprovalWatcher?.cancel()
        mcpApprovalWatcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, !Task.isCancelled else { return }
                await MainActor.run { self.refreshMCPApprovals() }
            }
        }
    }

    func refreshMCPApprovals() {
        let store = mcpApprovalStore
        do {
            mcpPendingApprovals = try store.pending()
            mcpApprovalBadLines = store.malformedLineCount()
        } catch {
            mcpApprovalMessage = error.localizedDescription
        }
    }

    /// 写一条决定（批准只对**这一次**有效 —— 判据在 Core，界面不改判据）。
    func decideMCPApproval(requestID: String, approved: Bool) {
        do {
            try mcpApprovalStore.decide(requestID: requestID, approved: approved)
            mcpApprovalMessage = L(
                .mcpApprovalDecided,
                approved ? L(.mcpApprovalAllow) : L(.mcpApprovalDeny),
                requestID
            )
            refreshMCPApprovals()
        } catch {
            mcpApprovalMessage = error.localizedDescription
        }
    }

    // MARK: - 维护任务编排（FR-AI-04）

    /// 当前是不是沙箱构建（决定"起外部程序"的任务能不能跑，R-18）。
    var isSandboxedBuild: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    func openMaintenance() {
        maintenanceMessage = nil
        if maintenancePlanText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 给一份模板：类别与行格式是我们自己声明的，**示例比说明更快**。
            maintenancePlanText = """
            task: analyze | 更新 customers 的统计信息 | sql: ANALYZE public.customers
            """
        }
        isMaintenancePresented = true
    }

    private var maintenancePolicy: MaintenancePolicy {
        MaintenancePolicy(
            allowMultipleHighCost: maintenanceAllowMultipleHighCost,
            isReadOnly: selectedConnection?.isReadOnly ?? false,
            isSandboxed: isSandboxedBuild
        )
    }

    private var maintenanceDatabaseType: DatabaseType {
        selectedConnection?.dbType ?? .postgresql
    }

    /// 审阅计划：解析 + 逐条定"能不能跑 / 要不要审批"（判据全在 Core）。
    func reviewMaintenancePlan() {
        let review = MaintenancePlanner.makePlan(
            from: maintenancePlanText,
            policy: maintenancePolicy,
            databaseType: maintenanceDatabaseType,
            // 逐条「能不能跑 / 要不要审批」的理由是要显示给人看的（队列 L-65 第 3 批）。
            language: LocalizationManager.shared.effectiveLanguage
        )
        maintenanceReview = review
        if review.tasks.isEmpty {
            maintenanceMessage = L(.maintenanceNoPlan)
        } else {
            maintenanceMessage = nil
        }
    }

    func approveMaintenanceTask(id: String) {
        guard let review = maintenanceReview else { return }
        maintenanceReview = MaintenancePlanner.approve(review, ids: [id])
    }

    func rejectMaintenanceTask(id: String) {
        guard let review = maintenanceReview else { return }
        maintenanceReview = MaintenancePlanner.reject(review, ids: [id])
    }

    /// 把当前维护计划**存进笔记**（含逐条状态与理由、以及"没看懂的行"）。
    ///
    /// 为什么要存"被拒绝的条目"：那是**过程事实** —— 不记下来，下次模型还会提同一个被限流拒绝的计划，
    /// 而用户已经拒绝过一次了。
    ///
    /// 判重走**唯一入口** `AICaptureIntake`（队列 `L-138`）：从前这里直接 `upsert`，
    /// 而 `maintenanceNote` 又没给指纹 —— 「同一份产物只存一条」对维护计划**结构上不适用**。
    /// 现在与诊断面板同形：默认不重复存、显式要副本才存第二份。
    ///
    /// - Parameter forceNew: 显式要副本（界面上的「再存一份」）。
    func saveMaintenanceNote(forceNew: Bool = false) async {
        // 「存进笔记」按钮住在数据库区里，而笔记是**独立的一块能力**（Pro 不含它）：
        // 不先问一句，这个按钮在 Pro 上就会写进一个用户根本看不到的地方。
        guard notesEnabled else {
            maintenanceMessage = L(.licenseNotesNotIncluded)
            return
        }
        guard let review = maintenanceReview, !review.tasks.isEmpty else {
            maintenanceMessage = L(.maintenanceNoPlan)
            return
        }
        do {
            let draft = AICapture.maintenanceNote(
                planText: maintenancePlanText,
                review: review,
                target: selectedConnection.map { "\($0.username)@\($0.endpointDescription)" } ?? "",
                language: LocalizationManager.shared.effectiveLanguage
            )
            let result = try await AICaptureIntake.receive(
                draft,
                into: NoteLibrary.defaultLibrary(),
                forceNew: forceNew
            )
            switch result.outcome {
            case .saved:
                reusedCapturedNote = nil
                maintenanceMessage = L(.diagnosisNoteSaved, result.note.title)
            case .savedCopy:
                reusedCapturedNote = nil
                maintenanceMessage = L(.diagnosisNoteSavedCopy, result.note.title)
            case .reusedExisting:
                // 没重复存 ⇒ 把**已有那条**记下来，界面上给一个「打开那条」的入口（与诊断面板同形）。
                reusedCapturedNote = result.note
                maintenanceMessage = L(.diagnosisNoteReused, result.note.title)
            }
            await reloadNotes()
        } catch {
            maintenanceMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 执行**已批准且可执行**的任务。失败要带服务端原话，且失败的任务不会因为再批准而复活。
    func executeApprovedMaintenanceTasks() async {
        guard var review = maintenanceReview else { return }
        let runnable = review.executableTasks(isSandboxed: isSandboxedBuild)
        guard !runnable.isEmpty else {
            maintenanceMessage = L(.maintenanceNothingApproved)
            return
        }
        guard let tab = selectedTab, let configuration = connection(for: tab) else {
            maintenanceMessage = L(.stateNotConnected)
            return
        }
        maintenanceIsRunning = true
        defer { maintenanceIsRunning = false }

        do {
            let service = try await ensureService(for: configuration, database: tab.database)
            for task in runnable {
                guard let sql = task.sql else { continue }
                do {
                    _ = try await runSingleQuery(sql, on: service)
                    review = MaintenancePlanner.record(review, taskID: task.id)
                    maintenanceMessage = L(.maintenanceExecutedOne, task.summary)
                } catch {
                    if error is CancellationError { break }
                    // 失败说明**两半**（队列 L-66 拍板口径 ①）：原串进机器载荷（JSON / 记录），
                    // 人话进界面那一行 —— 从前两处共用一份值 ⇒ 原串直接打到用户眼前。
                    let failure = MaintenanceTask.FailureNote(
                        raw: error.localizedDescription,
                        readable: ErrorPresenter.message(for: error)
                    )
                    review = MaintenancePlanner.record(review, taskID: task.id, failure: failure)
                    maintenanceMessage = L(.maintenanceFailedOne, task.id, failure.readable)
                }
                maintenanceReview = review
            }
            maintenanceReview = review
        } catch {
            maintenanceMessage = ErrorPresenter.message(for: error)
        }
    }

    // MARK: - 对话式诊断（FR-AI-03）

    /// 打开诊断面板：SQL 取**当前页签**的（用户正看着的那条）。
    ///
    /// 这个入口同时负责**把上一轮的对象作用域清掉**：它代表「诊断编辑器里这条语句」，
    /// 而「从对象树唤起」那一路（`beginObjectDiagnosis`）在调它之后立刻把作用域写回 ——
    /// 于是「面板开着、作用域却是上一个对象」这种漂移不可能发生
    /// （与 `selectTreeObject` 「唯一写入口」同一条口径）。
    func openDiagnosis() {
        objectDiagnosisScope = nil
        diagnosisQuestion = L(.diagnosisQuestionField)
        diagnosisEvidence = []
        diagnosisReport = nil
        diagnosisMessage = nil
        isDiagnosisPresented = true
    }

    /// 从对象树右键唤起诊断（`FR-STD-DB-DIAG-006` ①）：
    /// 连接 / 库 / 对象 / **最近一次执行的读数**一并带进上下文。
    ///
    /// 「最近一次执行」的来源只有一处 = 页签上的 `ExecutionReceiptLog`；哪几种结局算真的执行过
    /// 由 Core 的 `DiagnosisScope.LastExecution(receipt:)` 判（被拒 / 未发出的不算）。
    func beginObjectDiagnosis(for object: DatabaseObject) {
        let scope = DiagnosisScope(
            object: object,
            connectionLabel: selectedConnection.map { "\($0.username)@\($0.endpointDescription)" } ?? "",
            database: selectedTab?.database ?? selectedConnection?.database,
            lastExecution: selectedTab?.receiptLog.receipts.last
        )
        openDiagnosis()          // 清上一轮证据（它也会把作用域清空）
        objectDiagnosisScope = scope
        diagnosisQuestion = L(.diagnosisScopeQuestion, scope.qualifiedName)
        statusMessage = L(.diagnosisScopeOpened, scope.qualifiedName)
    }

    /// 诊断的默认语句：有作用域时按**对象**给（表 / 视图是自己那条浏览语句），否则取当前页签。
    var diagnosisTargetSQL: String {
        if let scope = objectDiagnosisScope {
            return scope.targetSQL(dialect: diagnosisDialect) ?? ""
        }
        return selectedTab?.sql ?? ""
    }

    /// 这一轮诊断用的方言。
    private var diagnosisDialect: any SQLDialect {
        SQLDialectFactory.make(for: selectedConnection?.dbType ?? .postgresql)
    }

    /// 结论里可点的对象名（本片只有作用域那一个 —— 见 `DiagnosisScope.linkTargets` 那段理由）。
    var diagnosisLinkTargets: [DiagnosisObjectLinker.Target] {
        objectDiagnosisScope?.linkTargets ?? []
    }

    /// 结论里点了对象名：发一次跳转请求并收起面板（`FR-STD-DB-DIAG-006` ②）。
    ///
    /// 面板**不直接改树**：展开状态是树视图本地的，直接改选中项只会跳到一个没展开的节点上
    /// （用户看到的是「什么都没发生」）。请求交给树，由它展开路径再选中。
    func jumpToDiagnosisObject(_ target: DiagnosisObjectLinker.Target) {
        treeJumpRequest = ObjectTreeJumpRequest(
            kind: target.kind,
            name: target.name,
            schema: target.schema,
            database: objectDiagnosisScope?.database ?? selectedTab?.database
        )
        isDiagnosisPresented = false
    }

    /// 取证：对真实库跑执行计划 / 锁 / 统计，取不到的那几条**如实记下原因**。
    ///
    /// 为什么这段在 App 而判据在 Core：`ensureService` 只有 App 有（连接与页签都在这儿），
    /// 而"取哪几种证据、怎么标注"是规则 —— 规则在 Core，取数在这儿。
    func gatherDiagnosisEvidence(sql: String) async {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        // 从对象树唤起时**不要求有语句**：列 / 函数 / 库这类节点本来就没有「那条语句」，
        // 它们的取证是对象统计 + 最近一次执行的读数（没有就如实记「未取到」）。
        // 老入口（诊断编辑器里那条语句）仍然要求语句非空 —— 空语句取不到任何执行计划。
        // 写成 `guard` 而不是 `if … { return }`：空数据按钮对账门禁（`Scripts/check-empty-action-buttons.py`）
        // 只扫 `guard` 形态，写成 `if` 这一处就从对账里消失了（2026-11-02 实测：台账条目被报陈旧）。
        guard !trimmed.isEmpty || objectDiagnosisScope != nil else {
            diagnosisMessage = L(.diagnosisEmpty)
            return
        }
        guard let tab = selectedTab, let configuration = connection(for: tab) else {
            diagnosisMessage = L(.stateNotConnected)
            return
        }
        diagnosisIsGathering = true
        diagnosisMessage = nil
        defer { diagnosisIsGathering = false }

        // 证据里的文案（「查到了，但没有行」这类标注）与提示词同一种语言：
        // 取的是**当前界面语言**（宿主语境优先），队列 L-47 —— 此前 Core 写死中文，
        // 英文界面上「给模型的资料」整块是中文。
        let language = LocalizationManager.shared.effectiveLanguage
        let dialect = SQLDialectFactory.make(for: configuration.dbType)
        var collected: [DiagnosisEvidence] = []
        do {
            let service = try await ensureService(for: configuration, database: tab.database)
            // 有作用域（从对象树唤起）= 按**对象**取；没有 = 按语句取（老入口，计划一个字都没变）。
            let plan: [DiagnosisScope.Planned]
            if let scope = objectDiagnosisScope {
                plan = scope.plannedEvidence(dialect: dialect, language: language)
            } else {
                plan = DiagnosisContextBuilder.evidencePlan(for: trimmed, dialect: dialect)
                    .map { DiagnosisScope.Planned(kind: $0.kind, sql: $0.sql) }
            }
            for (index, item) in plan.enumerated() {
                let id = DiagnosisContextBuilder.evidenceID(index: index)
                if item.kind == .statement {
                    collected.append(
                        DiagnosisContextBuilder.makeEvidence(
                            id: id, kind: .statement, sql: item.sql ?? trimmed, rows: [], language: language
                        )
                    )
                    continue
                }
                // 「最近一次执行」不是一条查询：读数从作用域来，没有就**明说未取到**（判据 ③）。
                if item.kind == .lastExecution {
                    collected.append(lastExecutionEvidence(id: id, language: language))
                    continue
                }
                guard let statement = item.sql else {
                    // 没有查询可跑（这一级没有统计视图 / 方言不支持 / 名字不是合法标识符）：
                    // 记一条**取不到**的证据并写清为什么 —— 不给空表（空表会被读成「没扫过」）。
                    collected.append(
                        DiagnosisContextBuilder.makeEvidence(
                            id: id, kind: item.kind, sql: "", rows: nil,
                            language: language,
                            failureReason: item.unavailableReason ?? L(.diagnosisStatsNoDialect)
                        )
                    )
                    continue
                }
                do {
                    let rows = try await runDiagnosisQuery(statement, on: service)
                    collected.append(
                        DiagnosisContextBuilder.makeEvidence(
                            id: id, kind: item.kind, sql: statement, rows: rows, language: language
                        )
                    )
                } catch {
                    // 取不到就是取不到：把服务端说的话带上（"扩展没装"和"权限不够"要分得开）。
                    collected.append(
                        DiagnosisContextBuilder.makeEvidence(
                            id: id, kind: item.kind, sql: statement, rows: nil,
                            language: language,
                            failureReason: error.localizedDescription
                        )
                    )
                }
            }
            diagnosisEvidence = collected
        } catch {
            diagnosisMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 「最近一次执行」那条证据：有读数就是一行（语句 / 耗时 / 行数 / 影响行数 / 结局）；
    /// 没有就**明说未取到**，不拿 0 行 0 ms 冒充一跑（判据 ③）。
    private func lastExecutionEvidence(id: String, language: AppLanguage) -> DiagnosisEvidence {
        guard let reading = objectDiagnosisScope?.lastExecution else {
            return DiagnosisEvidence(
                id: id,
                kind: .lastExecution,
                sql: "",
                note: L(.diagnosisLastExecutionNone),
                isAvailable: false
            )
        }
        return DiagnosisEvidence(
            id: id,
            kind: .lastExecution,
            sql: reading.statement,
            rows: [reading.evidenceRow(language: language)],
            note: reading.readingLine(language: language),
            isAvailable: true
        )
    }

    private func runDiagnosisQuery(_ sql: String, on service: any DatabaseService) async throws -> [[String?]] {
        var rows: [[String?]] = []
        for try await event in service.execute(sql, options: .default) {
            if case .resultSet(let result) = event {
                rows.append(contentsOf: result.rows)
            }
        }
        return rows
    }

    /// 当前的诊断上下文（提示词与解读共用同一份，**不许各拼一份**）。
    var diagnosisContext: DiagnosisContext {
        // 目标这一段必须把**库与对象**写进去（`FR-STD-DB-DIAG-006` 判据 ①）：
        // 只写「谁@哪台机」，模型没法知道说的是这个库里的这张表。
        let target: String
        if let scope = objectDiagnosisScope {
            target = scope.promptTarget
        } else {
            target = selectedConnection.map { "\($0.username)@\($0.endpointDescription)" } ?? ""
        }
        return DiagnosisContext(
            question: diagnosisQuestion,
            target: target,
            evidence: diagnosisEvidence
        )
    }

    /// 解读模型回答：采纳有依据的、拒绝没依据的（判据在 Core）。
    ///
    /// 语言与提示词**同一个值**（队列 L-47）：行格式的语法记号按语言取，
    /// 英文提示词 + 中文语法记号会把整篇判成「没看懂」。
    func parseDiagnosisReply() {
        let configuration = selectedConnection
        diagnosisReport = DiagnosisAdvice.parse(
            reply: diagnosisReply,
            context: diagnosisContext,
            language: LocalizationManager.shared.effectiveLanguage,
            databaseType: configuration?.dbType ?? .postgresql,
            policy: ExecutionSafetyPolicy.policy(
                for: selectedConnection.map { ConnectionAppearance(environment: $0.environment, colorTag: $0.colorTag) } ?? ConnectionAppearance(),
                isEnabled: isSafeModeEnabled,
                confirmAllWrites: false,
                isReadOnly: configuration?.isReadOnly ?? false
            )
        )
    }

    /// 把当前诊断结果**存进笔记**（DOYAH-10 的界面入口）。
    ///
    /// 只收**采纳的条目**（被拒绝的结论是过程、不是结论），并走 `AICapture` 统一元信息 ——
    /// 界面不自己拼正文，否则来源类型、指纹、安全边界会各拼一份、迟早不一致。
    ///
    /// **同一份产物默认不重复存**（队列 `L-134`，依据 `Q14=A`）：判定与写库都在
    /// `AICaptureIntake.receive` 一处 —— 这里从前自己算过一遍同指纹、算完却照样存第二份，
    /// 于是「只存一条」谁也不负责。要副本必须走 `forceNew`（界面上单独一颗按钮）。
    func saveDiagnosisNote(forceNew: Bool = false) async {
        guard notesEnabled else {
            diagnosisMessage = L(.licenseNotesNotIncluded)
            return
        }
        guard let report = diagnosisReport, !report.items.isEmpty else {
            diagnosisMessage = L(.diagnosisEmpty)
            return
        }
        do {
            let draft = AICapture.diagnosisNote(
                question: diagnosisQuestion,
                target: selectedConnection.map { "\($0.username)@\($0.endpointDescription)" } ?? "",
                context: diagnosisContext,
                report: report,
                language: LocalizationManager.shared.effectiveLanguage
            )
            let result = try await AICaptureIntake.receive(
                draft,
                into: NoteLibrary.defaultLibrary(),
                forceNew: forceNew
            )
            switch result.outcome {
            case .saved:
                reusedCapturedNote = nil
                diagnosisMessage = L(.diagnosisNoteSaved, result.note.title)
            case .savedCopy:
                reusedCapturedNote = nil
                diagnosisMessage = L(.diagnosisNoteSavedCopy, result.note.title)
            case .reusedExisting:
                // 没重复存 ⇒ 把**已有那条**记下来，界面上给一个「打开那条」的入口。
                reusedCapturedNote = result.note
                diagnosisMessage = L(.diagnosisNoteReused, result.note.title)
            }
            await reloadNotes()
        } catch {
            diagnosisMessage = ErrorPresenter.message(for: error)
        }
    }

    /// 打开「上一次没有重复存的那条」笔记（诊断面板上那个入口）。
    ///
    /// 存完把用户丢在原地、只说一句「之前存过」，等于让他自己去列表里翻 —— 入口就在这里。
    func revealReusedCapturedNote() {
        guard let note = reusedCapturedNote else { return }
        reusedCapturedNote = nil
        selectActivityItem(.notes)
        edit(note)
    }

    /// 把建议的 SQL 放进编辑器（**不执行**：执行仍然走用户自己那一步与那道审批闸门）。
    func putDiagnosisSQLInEditor(_ sql: String) {
        guard let tab = selectedTab else { return }
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs[index].sql = sql
            statusMessage = L(.diagnosisInserted)
        }
    }

    private func invalidateService(for connectionID: UUID) {
        // 隧道跟着连接一起收：留着它只是占一个本地端口 + 一条跳板机通道。
        if let tunnel = sshTunnels.removeValue(forKey: connectionID) {
            tunnel.stop()
        }
        for key in Array(connectTasks.keys) where key.connectionID == connectionID {
            connectTasks[key]?.cancel()
            connectTasks[key] = nil
        }

        for key in Array(services.keys) where key.connectionID == connectionID {
            // 断开连接会连带丢弃未提交事务（服务端在连接关闭时回滚）——
            // 这是**隐式**回滚，必须显式说出来，不能让用户以为它提交了。
            if var session = transactionSessions[key], session.phase.isOpen {
                session.serverCommandFailed()
                transactionSessions[key] = nil
                let service = services[key]
                Task { try? await service?.rollback() }
                statusMessage = L(.transactionRolledBackOnLeave)
            }
            if let service = services[key] {
                Task {
                    await service.disconnect()
                }
            }
            services[key] = nil
        }

        serverInfos[connectionID] = nil
    }
}

/// `AppState` 就是浏览器页签的宿主：它给模型的三件东西（下载落盘目录 / 统一外发留痕 / 启动链上的
/// 失败告知）全是**它自己的数据**（目录书签、外发日志面板、状态栏）。
///
/// **为什么空扩展 + 实现在类内**：三处实现要用的 `authorizedDownloadDirectory()` /
/// `releaseDownloadGrants()` / `egressLog` / `statusMessage` 都在类内，而「模型要什么、
/// 宿主给什么」这一问的答案放在宿主那一节（`// MARK: - 浏览器页签：宿主侧的三件事`）最好读 ——
/// 空扩展只负责把协议关系写出来（`AppState` 是 `WorkspaceBrowserHost`）。
extension AppState: WorkspaceBrowserHost {}

/// 逐行收集外部程序输出（见 `runExternalProcess` 的说明）。
private actor OutputCollector {
    private var lines: [String] = []

    func append(_ line: String) { lines.append(line) }

    func joined() -> String { lines.joined(separator: "\n") }
}
