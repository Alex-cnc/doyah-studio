import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **界面快照 · 第二批：侧栏与面板的空态**（队列 L-11）。
///
/// L-01 那批覆盖的是「有内容」的界面（三档活动栏 / Home 空态 / 结果表 / ER 图初始态）。
/// 本批补的是 spec §5.2 里那批**只能靠人工点开才看得到**的面板空态 ——
/// 想拿到它们，人得先点开菜单、再截图；离屏渲染不需要任何人到场：
///
///   · 连接列表空态（`FR-CONN-*`：一条连接都没有时侧栏该说什么）
///   · 对象树空态（没选连接时树该说什么）
///   · 智能体审计空态（`FR-AI-13`：没有审计记录时）
///   · 维护面板空态（`FR-DB-*`：没有维护计划时）
///
/// 第二批（`testPanelEmptyStatesBatchTwo`）：
///   · 数据任务空态（`FR-AI-05/06/08`：一条任务都没有）
///   · 导入空态（`FR-IO-03/06/07`：没选文件）
///   · 例行候选空态（`FR-AI-14/15`：一条候选都没有）
///   · 会话空态（`FR-SESS-01/02`：空列表）
///
/// **分批**：L-11 条目按「一批 4 个面板 × 深浅各一」推进，每批独立提交（见队列 L-11）。
/// 第二批 = `testPanelEmptyStatesBatchTwo`（数据任务 / 导入 / 例行候选 / 会话）。
///
/// 三条纪律与 L-01 同源（见 `UISnapshotKit`）：不进每轮门禁、产物落 `.build/`、每张图都带断言。
final class UISnapshotPanelsTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "界面快照要显式打开：DOYAH_UI_SNAPSHOT=1（它是取证工具，不进每轮门禁）"
        )
    }

    // MARK: - 共用装配

    /// 侧栏视图（连接列表 / 对象树）的面积：按侧栏真实宽度取，高度给足几个分组。
    private let sidebarSize = CGSize(width: 320, height: 560)

    /// 一个**空态**宿主：工作区历史指到临时文件，且**显式**把连接清空。
    ///
    /// **第 11 轮更正（实测推翻）**：这段原写的「测试体里没有 `await`，主线程上的加载任务
    /// 不会插进来，所以这里的清空在整张图的渲染期间一直成立」**是错的** ——
    /// 离屏宿主的布局 / 绘制会泵一次运行循环，`.task` 里的加载**会跑完**。
    /// 实证：会话面板那张图里出现了 `Could not load sessions: No database connection is established`
    /// 这行红字 —— 它只可能由 `.task → reload()` 的 `catch` 写出，别处没有写它的路径。
    /// 所以空态能站稳靠的是「显式置空 **+ 渲染后再断言一遍」，不是「异步任务跑不起来」；
    /// 各面板的渲染后断言见 `testPanelEmptyStatesBatchTwo`。
    ///
    /// 读的是**只读**路径：全程不写用户数据、不连任何数据库。
    @MainActor
    private func makeEmptyHost() -> (
        state: AppState, workspace: WorkspaceStore, tabs: WorkspaceTabsModel, terminal: TerminalModel
    ) {
        let scratch = UISnapshot.outputDirectory.deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let historyURL = scratch.appendingPathComponent("workspace-history-\(UUID().uuidString).json")

        let state = AppState()
        let workspace = WorkspaceStore.shared
        let tabs = WorkspaceTabsModel(store: WorkspaceHistoryStore(fileURL: historyURL))
        let terminal = TerminalModel()

        state.connections = []
        state.selectedConnectionID = nil
        return (state, workspace, tabs, terminal)
    }

    // MARK: - 一批四张（深浅各一）

    @MainActor
    func testPanelEmptyStates() throws {
        let host = makeEmptyHost()

        // 前置：这一批拍的**确实是空态**。三条断言都不成立的话，图再好看也没意义。
        XCTAssertTrue(host.state.connections.isEmpty, "本批要拍空态：连接列表必须为空")
        XCTAssertNil(host.state.selectedConnectionID, "本批要拍空态：不该有选中的连接")
        XCTAssertFalse(L(.connectionListEmpty).isEmpty, "空态文案缺失（语言表里没有 connectionListEmpty）")

        try snapshotLightAndDark("connection-list-empty", size: sidebarSize, host: host) {
            ConnectionListView(onAdd: {}, onEdit: { _ in })
        }

        try snapshotLightAndDark("object-tree-empty", size: sidebarSize, host: host) {
            ObjectTreeView()
        }

        // 审计空态：读审计档是只读的（`~/Library/Application Support/DoyahStudio/agent-audit.json`）。
        // 真机上已有记录时这里会先读到内容 —— 所以显式置空，让这张图**每次都是同一个态**。
        host.state.agentAuditRecords = []
        XCTAssertTrue(host.state.agentAuditRecords.isEmpty, "审计记录必须为空才能拍空态")
        try snapshotLightAndDark(
            "agent-audit-empty",
            size: CGSize(width: 940, height: 790),
            host: host
        ) {
            AgentAuditPanel()
        }

        // 维护面板空态：没有计划文本、也没有解析结果（`maintenanceReview == nil`）。
        host.state.maintenancePlanText = ""
        host.state.maintenanceReview = nil
        try snapshotLightAndDark(
            "maintenance-panel-empty",
            size: CGSize(width: 760, height: 680),
            host: host
        ) {
            MaintenancePanel()
        }
    }

    /// 同一张图拍浅色 / 深色两遍：深色一遍看的是**对比度与动态色**（L-13 记的另一半：
    /// 语言遍地还没成对，那是 L-13 的范围，这里不做）。
    @MainActor
    private func snapshotLightAndDark<V: View>(
        _ name: String,
        size: CGSize,
        host: (
            state: AppState, workspace: WorkspaceStore, tabs: WorkspaceTabsModel, terminal: TerminalModel
        ),
        @ViewBuilder content: () -> V
    ) throws {
        for scheme in [ColorScheme.light, .dark] {
            try UISnapshot.writeBothLanguages(
                "\(name)\(scheme == .dark ? "-dark" : "")",
                size: size,
                scheme: scheme
            ) {
                content().snapshotEnvironment(
                    state: host.state,
                    workspace: host.workspace,
                    tabs: host.tabs,
                    terminal: host.terminal
                )
            }
        }
    }

    // MARK: - 一批四张（深浅各一）

    /// **第二批**：数据任务 / 导入 / 例行候选（记忆治理）/ 会话。
    ///
    /// 四条途径各不相同，所以「空态怎么造」也各不相同：
    ///   · **数据任务**（`FR-AI-05/06/08`）：列表来自 `appState.dataTasks` —— 直接摆空，
    ///     并让右侧停在「没有选中项」那一支（`dataTaskNoSelection`）；
    ///   · **导入**（`FR-IO-03/06/07`）：面板自持状态（没选文件 / 没解析），只需要把
    ///     `appState` 里的导入痕迹（日志 / 消息 / 错误 / 选中对象）清掉；
    ///   · **例行候选**（`FR-AI-14/15`）：报告为 `nil`（还没算过）时给的是「一条候选都没有」的文案；
    ///   · **会话**（`FR-SESS-01/02`）：`sessions` 是**私有 `@State`**，外面注不进去 ——
    ///     离屏拿到的只能是它自己那个初值分支（空列表）。**如实说明**：这张图里**两样东西同时在**——
    ///     ① 红色 `Could not load sessions: …`（`.task → reload()` 抛 `notConnected` 的分支，
    ///     说明离屏宿主里加载**真的跑过**）② 中间的空占位 `sessionEmpty`（`sessions.isEmpty` 那一支）。
    ///     也就是说它是「**没选连接**时的首次绘制」的**真运行态**；
    ///     而「连上服务器、这次查到 0 条会话」那个**纯空列表**态仍然拍不到，
    ///     要按需造态得先有**可注入口子** —— 那是 **L-12** 的范围。
    ///
    /// **本轮更正一条工具假设 + 新增一条纪律**：`.task` / `onAppear` 在离屏宿主里**是会跑的**
    /// （实证同上：那行红字只有 `reload()` 写得出来）—— 第一批注释里「主线程的加载任务插不进来」
    /// **是错的**。于是对本批三个读 `appState` 的面板，空态站稳靠两件事：① 渲染前显式置空；
    /// ② **渲染后再断言一遍状态仍然为空** —— 一旦哪天磁盘上真有了数据任务 / 归档目录，
    /// 这里会**当场变红**，而不是悄悄拍出一张与注释不符的图
    /// （第一批的 `List` 假绿已经说明：工具自己的假设要靠实测钉住，不能靠注释）。
    @MainActor
    func testPanelEmptyStatesBatchTwo() throws {
        let host = makeEmptyHost()

        // ① 数据任务空态（FR-AI-05 / 06 / 08）
        host.state.dataTasks = []
        host.state.dataTaskRuns = []
        host.state.dataTaskMessage = nil
        host.state.dataTaskError = nil
        XCTAssertTrue(host.state.dataTasks.isEmpty, "本张要拍空态：一条数据任务都不该有")
        try snapshotLightAndDark(
            "data-task-empty",
            size: CGSize(width: 1_060, height: 860),
            host: host
        ) {
            DataTaskPanel()
        }
        XCTAssertTrue(
            host.state.dataTasks.isEmpty,
            "渲染期间数据任务被重填了（离屏宿主里面板的 .task 会跑，读的是磁盘上的 data-tasks.json）"
                + " —— 这张图不能当空态证据，要与磁盘状态解耦得先做 L-12 的可注入口子"
        )

        // ② 导入空态（FR-IO-03 / 06 / 07）：没选文件、没解析、没有日志
        host.state.importError = nil
        host.state.importMessage = nil
        host.state.selectedTreeObject = nil
        XCTAssertTrue(host.state.importLog.isEmpty, "本张要拍空态：导入日志该是空的")
        XCTAssertFalse(host.state.isImportRunning, "本张要拍空态：不该正在导入")
        XCTAssertNil(host.state.selectedTreeObject, "没选对象时目标表才该是空的")
        try snapshotLightAndDark(
            "import-empty",
            size: CGSize(width: 780, height: 760),
            host: host
        ) {
            ImportPanel()
        }
        XCTAssertTrue(host.state.importLog.isEmpty, "渲染期间导入日志被写入了 —— 空态没站稳")

        // ③ 例行候选空态（FR-AI-14 / 15）：报告还没算出来（`nil`）
        // 高度取内容实际所需（面板自己没有固定高度：它只钉了宽度 700）：给多了会看到
        // SwiftUI 把内容在宿主里**垂直居中**，那不是面板在真机上的样子（sheet 只给内容所需的高度）。
        XCTAssertNil(host.state.routineReport, "本张要拍空态：例行候选报告该还没算过")
        try snapshotLightAndDark(
            "routine-candidates-empty",
            size: CGSize(width: 700, height: 240),
            host: host
        ) {
            RoutineCandidatesPanel()
        }
        XCTAssertNil(host.state.routineReport, "渲染期间例行候选报告被算出来了 —— 空态没站稳")

        // ④ 会话空态（FR-SESS-01 / 02）：见本方法开头的「如实说明」
        XCTAssertTrue(host.state.connections.isEmpty, "会话面板要拍空列表：先确认没有连接")
        try snapshotLightAndDark(
            "session-empty",
            size: CGSize(width: 860, height: 520),
            host: host
        ) {
            SessionPanel()
        }
    }

    // MARK: - 第 3 批（队列 L-16，2026-09-27）

    /// **第 3 批**（队列 L-16「其余面板空态」）：**执行计划 / Schema 对比 / 锁与阻塞 / MCP 审批**
    /// —— 条目原文点名的第 3 批就是这四个（其余候选留给后续批次）。
    ///
    /// 四条途径各不相同，所以「空态怎么造」也各不相同：
    ///   · **执行计划**（`FR-DIAG-01`）：面板读 `appState.executionPlan` —— 空态 = 没有计划 +
    ///     没有错误 + 不在加载中（`planEmpty` 那一支）；ANALYZE 开关显式关掉（打开会多一行
    ///     橙色警告，那是**另一张图**，不是空态）；
    ///   · **Schema 对比**（`FR-DDL-04`）：两侧选择器是面板自持的 `@State`，`.onAppear` 会按
    ///     `appState.connections` **预选** —— 连接为空时预选无事可做，于是停在
    ///     「先选两侧连接」那一支（`schemaDiffPickConnections`，`Compare` 也灰着）；
    ///   · **锁与阻塞**（`FR-DIAG-05`）：`.task { await load() }` 在离屏宿主里**会跑**
    ///     （第 11 轮实测）—— 没选连接时它走 `catch`，于是图上**两样同时在**：
    ///     ① 未选连接的提示 ② 空列表文案 `lockEmpty`。**如实说明**：这张图是「未选连接时的
    ///     首次绘制」的**真运行态**；「连上服务器、这次 0 条等待」那个**纯空态**拍不到 ——
    ///     `waits` 是私有 `@State`、打开即查库（与 `SessionPanel` 同一族）→ 该口子**并入 L-18 的范围**；
    ///   · **MCP 审批**（`FR-AI-10` 的界面那一半）：面板读 `appState.mcpPendingApprovals` ——
    ///     摆空即「没有待审批项」（`mcpApprovalEmpty`），另把坏行计数与消息一并清零。
    ///
    /// 纪律同第二/三批：**渲染前显式置空 + 渲染后再断言一遍**（离屏宿主里 `.task` / `onAppear` 会跑完）。
    @MainActor
    func testPanelEmptyStatesBatchThree() throws {
        let host = makeEmptyHost()

        // 前置：本批四张都是「什么都还没发生」的态；四句空态文案必须在语言表里。
        XCTAssertTrue(host.state.connections.isEmpty, "本批要拍空态：不该有任何连接")
        XCTAssertNil(host.state.selectedConnectionID, "本批要拍空态：不该有选中的连接")
        XCTAssertFalse(L(.planEmpty).isEmpty, "空态文案缺失（语言表里没有 planEmpty）")
        XCTAssertFalse(L(.lockEmpty).isEmpty, "空态文案缺失（语言表里没有 lockEmpty）")
        XCTAssertFalse(L(.mcpApprovalEmpty).isEmpty, "空态文案缺失（语言表里没有 mcpApprovalEmpty）")
        XCTAssertFalse(
            L(.schemaDiffPickConnections).isEmpty,
            "空态文案缺失（语言表里没有 schemaDiffPickConnections）"
        )

        // ① 执行计划空态（FR-DIAG-01）
        host.state.executionPlan = nil
        host.state.executionPlanError = nil
        host.state.executionPlanIsLoading = false
        host.state.planRunAnalyze = false
        XCTAssertNil(host.state.executionPlan, "本张要拍空态：还没跑过执行计划")
        try snapshotLightAndDark(
            "execution-plan-empty",
            size: CGSize(width: 720, height: 620),
            host: host
        ) {
            ExecutionPlanPanel(tabID: UUID())
        }
        XCTAssertNil(host.state.executionPlan, "渲染期间执行计划被填上了 —— 空态没站稳")
        XCTAssertNil(host.state.executionPlanError, "渲染期间执行计划报错被写入了 —— 空态没站稳")

        // ② Schema 对比初始态（FR-DDL-04）：两侧都没得选（连接为空）
        try snapshotLightAndDark(
            "schema-diff-empty",
            size: CGSize(width: 760, height: 700),
            host: host
        ) {
            SchemaDiffPanel()
        }
        XCTAssertTrue(
            host.state.connections.isEmpty,
            "渲染期间连接被填上了 —— 面板的 .onAppear 会预选，这张图就不再是「两侧都空」"
        )

        // ③ 锁与阻塞空态（FR-DIAG-05）：见本方法开头的「如实说明」
        try snapshotLightAndDark(
            "lock-panel-empty",
            size: CGSize(width: 760, height: 560),
            host: host
        ) {
            LockPanel()
        }
        XCTAssertTrue(host.state.connections.isEmpty, "渲染期间连接被填上了 —— 锁面板的取数依赖选中连接")

        // ④ MCP 审批空态（FR-AI-10 界面侧）：没有待审批项
        host.state.mcpPendingApprovals = []
        host.state.mcpApprovalBadLines = 0
        host.state.mcpApprovalMessage = nil
        XCTAssertTrue(host.state.mcpPendingApprovals.isEmpty, "本张要拍空态：不该有待审批项")
        try snapshotLightAndDark(
            "mcp-approval-empty",
            size: CGSize(width: 720, height: 600),
            host: host
        ) {
            MCPApprovalPanel()
        }
        XCTAssertTrue(host.state.mcpPendingApprovals.isEmpty, "渲染期间待审批项被填上了 —— 空态没站稳")
    }

    // MARK: - 第 4 批（队列 L-16，2026-09-27）

    /// **第 4 批**（队列 L-16「其余面板空态」）：**诊断 / 对象搜索 / 备份恢复 / 数据库统计**。
    ///
    /// 选这四个的理由：每个都正对着 spec §5.2 里一条**只差「有人点开看一眼」**的条目 ——
    /// 诊断（第 3 条 / `FR-AI-03`）、对象搜索（第 29 条 / `FR-META-12`）、
    /// 备份恢复（第 44 条 / `FR-IO-05`）、数据库统计四类指标（第 40 条 / `FR-DIAG-04`）。
    /// 而它们的「空」来源各不相同，造法也就各不相同：
    ///   · **诊断**（`FR-AI-03`）：四个 `@Published` 都还是 `AppState` 的初值（没跑过取证）→
    ///     面板该显示「还没取证」+ 取证按钮**灰着**（语句框空 ⇒ 没有可诊断的对象，
    ///     `.onAppear` 从当前页签取语句、没有页签就是空串）。这张图是「没有模型端点也能用」
    ///     那条口径的另一半：先看**证据区**是什么样子。
    ///   · **对象搜索**（`FR-META-12`）：关键词是面板自持的 `@State`，空关键词时
    ///     `.task(id:)` **第一句就早退**（不发请求、不查库）→ 停在 `objectSearchHint` 那一支。
    ///   · **备份恢复**（`FR-IO-05`）：面板自持表单 + `.onAppear` 的兜底（工具路径取默认值、
    ///     目标库取当前库）—— 没连库、没选归档 ⇒ 预览给 `backupRestoreIncomplete`、
    ///     执行按钮**灰着**（`isDraftRunnable == false`）。这是「刚打开、还没选文件」的真实态。
    ///   · **数据库统计**（`FR-DIAG-04`）：`report` 是**私有 `@State`**、`.task` 打开即采数 →
    ///     没连库时走 `catch`，图上是一条失败文案而不是四类指标。**如实说明**：这张图是
    ///     「**未选连接**时打开统计面板」的**真运行态**；「连上服务器、四类指标都取到了」与
    ///     「连上了但这四类都没数据」（`databaseStatsEmpty`）两个态**都拍不到** ——
    ///     `report` 是私有 `@State`、数据来自真库，与 `LockPanel` / `SessionPanel` 同一族。
    ///
    /// 纪律同前几批：**渲染前显式置空 + 渲染后再断言一遍**（离屏宿主里 `.task` / `.onAppear` 会跑完）。
    @MainActor
    func testPanelEmptyStatesBatchFour() throws {
        let host = makeEmptyHost()

        XCTAssertTrue(host.state.connections.isEmpty, "本批要拍空态：不该有任何连接")
        XCTAssertNil(host.state.selectedConnectionID, "本批要拍空态：不该有选中的连接")
        XCTAssertFalse(L(.diagnosisEmpty).isEmpty, "空态文案缺失（语言表里没有 diagnosisEmpty）")
        XCTAssertFalse(L(.objectSearchHint).isEmpty, "空态文案缺失（语言表里没有 objectSearchHint）")
        XCTAssertFalse(L(.backupRestoreHint).isEmpty, "空态文案缺失（语言表里没有 backupRestoreHint）")
        XCTAssertFalse(L(.databaseStatsEmpty).isEmpty, "空态文案缺失（语言表里没有 databaseStatsEmpty）")

        // ① 诊断空态：没跑过取证（FR-AI-03）
        host.state.diagnosisEvidence = []
        host.state.diagnosisReport = nil
        host.state.diagnosisMessage = nil
        host.state.diagnosisQuestion = ""
        host.state.diagnosisIsGathering = false
        XCTAssertTrue(host.state.diagnosisEvidence.isEmpty, "本张要拍空态：还没取过证")
        XCTAssertNil(host.state.diagnosisReport, "本张要拍空态：还没有模型给出的建议")
        XCTAssertTrue(
            host.state.diagnosisTargetSQL.isEmpty,
            "语句框该是空的 —— 诊断面板 `.onAppear` 从当前页签取语句，没有页签就没有可诊断的对象"
        )
        try snapshotLightAndDark(
            "diagnosis-empty",
            size: CGSize(width: 760, height: 700),
            host: host
        ) {
            DiagnosisPanel()
        }
        XCTAssertTrue(host.state.diagnosisEvidence.isEmpty, "渲染期间取证结果被填上了 —— 空态没站稳")
        XCTAssertNil(host.state.diagnosisReport, "渲染期间建议被填上了 —— 空态没站稳")

        // ② 对象搜索空态：还没输关键词（FR-META-12）
        try snapshotLightAndDark(
            "object-search-empty",
            size: CGSize(width: 640, height: 480),
            host: host
        ) {
            ObjectSearchPanel()
        }
        XCTAssertTrue(host.state.connections.isEmpty, "渲染期间连接被填上了 —— 搜索面板的取数依赖选中连接")

        // ③ 备份恢复初始态（FR-IO-05）：还没选归档、还没连库
        XCTAssertTrue(host.state.backupRestoreLog.isEmpty, "本张要拍空态：还没有备份 / 恢复日志")
        XCTAssertFalse(host.state.isBackupRunning, "本张要拍空态：不该正在跑")
        XCTAssertNil(host.state.selectedDatabase, "没连库 ⇒ 目标库兜底取不到值，归档路径也只能是空")
        try snapshotLightAndDark(
            "backup-restore-empty",
            // 这张面板自己没有钉高度（内容 `.frame(width: 700, alignment: .leading)`），
            // 所以宿主高度**按内容实测取**：给多了 SwiftUI 会把内容在宿主里垂直居中，
            // 留白就不是真机比例了（L-11 的 `routine-candidates` 踩过同一坑，实测一次后收紧）。
            size: CGSize(width: 700, height: 340),
            host: host
        ) {
            BackupRestoreSheet()
        }
        XCTAssertTrue(host.state.backupRestoreLog.isEmpty, "渲染期间备份日志被写入了 —— 空态没站稳")
        XCTAssertFalse(host.state.isBackupRunning, "渲染期间备份被启动了 —— 空态没站稳")

        // ④ 数据库统计：见本方法开头的「如实说明」（未选连接 ⇒ 失败文案那一支，FR-DIAG-04）
        try snapshotLightAndDark(
            "database-stats-empty",
            size: CGSize(width: 660, height: 640),
            host: host
        ) {
            DatabaseStatsPanel()
        }
        XCTAssertTrue(host.state.connections.isEmpty, "渲染期间连接被填上了 —— 统计面板的取数依赖选中连接")
    }

    // MARK: - 清单

    override class func tearDown() {
        UISnapshot.finishManifestIfEnabled()
        super.tearDown()
    }
}
