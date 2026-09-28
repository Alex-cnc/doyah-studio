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
    @discardableResult
    private func snapshotLightAndDark<V: View>(
        _ name: String,
        size: CGSize,
        host: (
            state: AppState, workspace: WorkspaceStore, tabs: WorkspaceTabsModel, terminal: TerminalModel
        ),
        @ViewBuilder content: () -> V
    ) throws -> [UISnapshot.LanguagePair] {
        var pairs: [UISnapshot.LanguagePair] = []
        for scheme in [ColorScheme.light, .dark] {
            pairs.append(
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
            )
        }
        return pairs
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

    // MARK: - 第 5 批（队列 L-16，2026-09-27）

    /// **第 5 批**（队列 L-16「其余面板空态」）：**笔记（列表 + 正文）/ 统一外发日志**。
    ///
    /// 条目原文给的第 5 批候选有五个，本轮只做**能拍到真空态的两个**，另三个的前置如实登记在方法末 ——
    /// 这一批的「每张图都是空态」是个判据，不能拿错误态来凑数：
    ///   · **权限**（`FR-SESS-04`）/ **服务器对象**（`FR-SESS-03`）：`@State` 私有 + `.task` 打开即查库，
    ///     没连接时离屏只能拿到错误分支 ⇒ 要 **L-18** 的面板级参数注入才能拍「连上了但 0 条」；
    ///   · **合成数据**（`FR-AI-07`）：列规格来自真库结构 ⇒ 只能停在「取不到结构」那一支，
    ///     那是**错误态不是空态**（混进来会让本批的空态判据失效）。
    ///
    /// 两处数据源都走**产品自带的正式覆盖口子**（不是测试后门），由 `Scripts/make-ui-snapshots.sh`
    /// 指到一个**每轮清空**的临时目录：
    ///   · 笔记 —— `DOYAH_NOTES_DIR`（`NoteLibrary.defaultDirectory` → `NoteStore.defaultDirectory`）；
    ///   · 统一外发日志 —— `DOYAH_EGRESS_LOG_DIR`（`EgressLog.init`）。
    /// 于是「一条都没有」是**每次都能复现的态**：本机真实数据里笔记有 1 条、外发日志 60 KB，
    /// 不隔离就永远拍不到这两张空态（第 16 轮登记这条时就是这么判的）。
    /// 两个一次性迁移在覆盖生效时都**主动让路**，所以这轮渲染不写用户的真实数据。
    ///
    /// 纪律同前几批：**渲染前显式置空 + 渲染后再断言一遍**（离屏宿主里 `.task` 会跑完）。
    @MainActor
    func testPanelEmptyStatesBatchFive() throws {
        let host = makeEmptyHost()
        defer { UISnapshot.clearLicense(from: host.state) }

        // 笔记在 **Standard 档**下就是整个应用（`LicenseEdition.standard` → `.notesOnly`），
        // 所以这两张图要在 Standard 下拍；档位没落到就说明拍的是别的档，图不作数。
        let load = try UISnapshot.applyLicense(.standard, to: host.state)
        XCTAssertEqual(load.entitlements.edition, .standard, "笔记区在 Standard 档下才是「整个应用」")
        XCTAssertEqual(load.entitlements.basis, .licensed, "签名校验没通过（临时许可证链路断了）")
        XCTAssertTrue(host.state.notesEnabled, "Standard 档必须带笔记能力（capabilities.notes）")

        // 前置：这一批拍的都是「一条都没有」；两句空态文案必须在语言表里。
        XCTAssertTrue(host.state.connections.isEmpty, "本批要拍空态：不该有任何连接")
        XCTAssertTrue(
            host.state.notes.isEmpty,
            "本批要拍空态：笔记必须一条都没有（`DOYAH_NOTES_DIR` 指向每轮清空的临时目录）"
        )
        XCTAssertTrue(
            host.state.egressEntries.isEmpty,
            "本批要拍空态：外发日志必须为空（`DOYAH_EGRESS_LOG_DIR` 指向每轮清空的临时目录）"
        )
        XCTAssertFalse(L(.notesEmpty).isEmpty, "空态文案缺失（语言表里没有 notesEmpty）")
        XCTAssertFalse(L(.egressEmpty).isEmpty, "空态文案缺失（语言表里没有 egressEmpty）")

        // ① 笔记 · 列表空态（侧栏那一栏）：`notesEmpty` 那一支
        try snapshotLightAndDark("notes-list-empty", size: sidebarSize, host: host) {
            NotesListView()
        }
        XCTAssertTrue(host.state.visibleNotes.isEmpty, "渲染期间笔记被填上了 —— 空态没站稳")
        XCTAssertTrue(host.state.notes.isEmpty, "渲染期间笔记被填上了 —— 空态没站稳")

        // ② 笔记 · 正文空态（`.notes` 活动项下的右半边）：还没选中、也还没开始写。
        //    面板的「选中了哪条」`noteBeingEdited` 是 `private`（`@testable` 也拿不到）——
        //    所以这里断言的是**它对外露出的那三个初值**：标题 / 标签 / 正文都还空着。
        XCTAssertTrue(host.state.noteEditorTitle.isEmpty, "没有选中的笔记 ⇒ 标题该是空的")
        XCTAssertTrue(host.state.noteEditorTags.isEmpty, "没有选中的笔记 ⇒ 标签该是空的")
        XCTAssertTrue(host.state.noteEditorBody.isEmpty, "没有选中的笔记 ⇒ 正文该是空的")
        try snapshotLightAndDark(
            "notes-editor-empty",
            size: CGSize(width: 900, height: 560),
            host: host
        ) {
            NotesEditorView()
        }
        XCTAssertTrue(host.state.noteEditorBody.isEmpty, "渲染期间正文被填上了 —— 空态没站稳")
        XCTAssertTrue(host.state.noteEditorTitle.isEmpty, "渲染期间标题被填上了 —— 空态没站稳")

        // ③ 统一外发日志空态（NFR-SEC-08）：**空态本身就是结论** ——「默认零外发」最直接的证据。
        // 三个筛选选择器此时都没有可选项（`tabOptions` 由日志派生 ⇒ 空日志时禁用），
        // 「清空」按钮也灰着（`disabled(appState.egressEntries.isEmpty)`）—— 这两点正是读图要看的东西。
        host.state.egressEntries = []
        host.state.egressError = nil
        host.state.egressMessage = nil
        try snapshotLightAndDark(
            "egress-log-empty",
            // sheet 自己钉的是 `minWidth: 760, minHeight: 480`；表头一行要放三个选择器 + 三个按钮，
            // 760 会挤，所以宿主给 860×520（宽一点才是真机上的样子，高度按最小值再给余量）。
            size: CGSize(width: 860, height: 520),
            host: host
        ) {
            EgressLogSheet()
        }
        XCTAssertTrue(
            host.state.egressEntries.isEmpty,
            "渲染期间外发日志被读回来了 —— 空态没站稳（面板的 `.task` 会 `refreshEgressLog()`）"
        )
        XCTAssertNil(host.state.egressError, "渲染期间外发日志读出错 —— 空态没站稳")

        // **本批未做（前置见方法开头）**：权限 / 服务器对象（等 L-18 的口子）、
        // 合成数据（列规格来自真库 ⇒ 只能拍错误支，不进「空态」这一批）。
    }

    // MARK: - L-18：可注入口子的其余面板（2026-09-27 第 39 轮）

    /// **注入判据**（队列 L-18）：这一张图上必须出现**只有注入的数据才写得出来**的那句文案，
    /// 且必须**没有**「没连库」那句 —— 两句一起判才说明面板这一遍**没去取数**。
    ///
    /// 为什么判文案而不是判「像素变了」：`Record.localizedStrings` 记的是**这一遍渲染里
    /// `L(...)` 真正取到的文案**（L-13 那份基础设施），所以它是「渲染走的是哪一支」的机械证据；
    /// 而「两张图不一样」在只有一张图可拍时无从比较。**如实说明局限**：它判的是**文案到了渲染上**，
    /// 不是逐像素比对 —— 像素那一半由人眼读图（每张都读，见本方法的交付清单）。
    @MainActor
    private func assertInjectedCopy(
        _ pairs: [UISnapshot.LanguagePair],
        present: LKey,
        absent: LKey?,
        line: UInt = #line
    ) {
        XCTAssertEqual(pairs.count, 2, "浅色 / 深色两遍都要拍到", line: line)
        for pair in pairs {
            XCTAssertEqual(pair.records.count, 2, "\(pair.base)：中英两遍都要在", line: line)
            for (index, language) in UISnapshot.coverageLanguages.enumerated() {
                let record = pair.records[index]
                let expected = UISnapshot.localizedText(language) { L(present) }
                XCTAssertTrue(
                    record.localizedStrings.contains(expected),
                    "\(record.name)：\(record.language) 那遍没有出现「\(expected)」"
                        + " —— 注入的态没走到渲染上（这一步是 L-18 的口子能作数的唯一证据）",
                    line: line
                )
                if let absent {
                    let forbidden = UISnapshot.localizedText(language) { L(absent) }
                    XCTAssertFalse(
                        record.localizedStrings.contains(forbidden),
                        "\(record.name)：\(record.language) 那遍出现了「\(forbidden)」"
                            + " —— 说明面板这一遍仍然去取了数（`.task` 的「给了初值就不去取」那道守卫没了？）",
                        line: line
                    )
                }
            }
        }
    }

    /// **L-18 批**：`SessionPanel` / `LockPanel` / `DatabaseStatsPanel` / `RoutineCandidatesPanel`
    /// 的**纯空态**（另有 `PrivilegePanel` / `ServerObjectsPanel` —— L-16 第 6 批的前置，见方法末）。
    ///
    /// 这四处此前**拍不到**，原因都是同一个：状态是**私有 `@State`**、`.task` 打开即查库，
    /// 没选连接时离屏只能拿到**错误分支**（L-11 / L-16 四批实测逐条登记过）。第 39 轮给它们
    /// 各开了一个**面板级注入**口子（形状由 L-12 定：只给初值 / 不是测试后门 / 生产路径不传），
    /// 于是「连上了、这次就是 0 条」这一类态第一次可见。
    ///
    /// **判据分两层**（缺一层就是「图好看」而不是证据）：
    ///   ① **渲染后断言**：注入的态在渲染后仍然成立（面板没把它取掉）—— 落在 `assertInjectedCopy`：
    ///      空态文案**在**、未连接文案**不在**。为什么「不在」才是关键那条：`.task` 一旦跑了、
    ///      抛了 `notConnected`，出问题的正是那句文案（L-11 第 11 轮那张 `session-empty` 图上
    ///      两样东西同时出现过）；所以「不在」= 这次取数**真的被拦下了**。
    ///   ② **人眼读图**：文案齐 ≠ 版面对（垂直居中、裁切、重叠都只有看图才知道，L-11 踩过）。
    ///
    /// 诚实边界：注入的是**面板级初值**，不是真库返回的 —— 它证明「拿到这样的数据时界面长什么样」，
    /// 不证明「真库会返回这样的数据」。这条边界与 L-12 那批完全一致。
    @MainActor
    func testInjectedEmptyStatesBatchSix() throws {
        let host = makeEmptyHost()
        XCTAssertTrue(host.state.connections.isEmpty, "本批要拍空态：不该有任何连接")
        XCTAssertNil(host.state.selectedConnectionID, "本批要拍空态：不该有选中的连接")

        // ① 会话：**连上了、这次查到 0 条**（此前只有「未选连接」那种真运行态）
        //    `SessionPanel` 自己钉了 `860×520`，所以宿主尺寸不会有「垂直居中」那条坑。
        let sessions = try snapshotLightAndDark(
            "session-connected-empty",
            size: CGSize(width: 860, height: 520),
            host: host
        ) {
            SessionPanel(initialSessions: [])
        }
        assertInjectedCopy(sessions, present: .sessionEmpty, absent: .errorNotConnected)
        XCTAssertTrue(host.state.connections.isEmpty, "渲染期间连接被填上了 —— 这次取数没被拦下")

        // ② 锁与阻塞：**连上了、这次 0 条等待**（L-16 第 3 批那张是「提示 + 空文案同屏」）
        let locks = try snapshotLightAndDark(
            "lock-panel-connected-empty",
            size: CGSize(width: 760, height: 560),
            host: host
        ) {
            LockPanel(initialWaits: [])
        }
        assertInjectedCopy(locks, present: .lockEmpty, absent: .errorNotConnected)

        // ③ 数据库统计：**连上了、四类都取到了报告、但这四类各自都没有数据**
        //    注入路径**不参与** `load()` 里「四类全空 ⇒ 方言不支持」那条双保险（那是**取数**的结果判定），
        //    所以这一张看到的是四个空行，不是「不支持」—— 判据就用四个分节表头 + 空行文案：
        //    它们在「错误分支」里一个都不会出现（`content` 先判 `errorMessage`，再判 `report`）。
        let stats = try snapshotLightAndDark(
            "database-stats-empty-report",
            size: CGSize(width: 660, height: 640),
            host: host
        ) {
            DatabaseStatsPanel(initialReport: DatabaseStats.Report())
        }
        assertInjectedCopy(stats, present: .databaseStatsEmptySection, absent: nil)
        assertInjectedCopy(stats, present: .databaseStatsTableSizes, absent: nil)

        // ④ 例行候选的**另一半**：记忆治理页签（面板默认落在「例行候选」页签 ⇒ 这一页从没被拍过）
        //    页签只给初值；这里的 `.task` 刷的是 appState 的报告、不写 `tab`，所以没有「拦下取数」那回事
        //    —— 反过来要**显式确认这一遍没有记忆可显示**，否则拍出来的不是空态。
        //    高度按内容实测取 **312pt**：这一页比「例行候选」那一页高（多了归档开关说明 + 记录策略卡片），
        //    而面板只钉了宽度 700 —— 宿主给多了 SwiftUI 会把内容**垂直居中**（第一版 420 实测顶部
        //    凭空多出 54pt 留白，与 L-11 的 `routine-candidates` 踩的是同一个坑）。
        let memory = try snapshotLightAndDark(
            "routine-candidates-memory-empty",
            size: CGSize(width: 700, height: 312),
            host: host
        ) {
            RoutineCandidatesPanel(initialTab: .memory)
        }
        assertInjectedCopy(memory, present: .memoryGovernanceEmpty, absent: nil)
        XCTAssertTrue(
            host.state.queryMemoryIndex.memories.isEmpty,
            "渲染期间记忆索引被填上了（`.task → refreshRoutineCandidates()` 读的是磁盘上的归档目录）"
                + " —— 这张图不能当空态证据"
        )

        // ⑤⑥ L-16 第 6 批的前置（同一族：私有 `@State` + `.task` 打开即查库）：
        //    **权限**（`FR-SESS-04`）与**服务器对象**（`FR-SESS-03`）。
        //    面板各自钉了尺寸（720×620 / 720×700），所以宿主尺寸没有居中那类坑。
        let privileges = try snapshotLightAndDark(
            "privilege-panel-empty",
            size: CGSize(width: 720, height: 620),
            host: host
        ) {
            PrivilegePanel(initialRole: "app_readonly", initialPrivileges: [])
        }
        assertInjectedCopy(privileges, present: .privilegeEmpty, absent: .errorNotConnected)

        let serverObjects = try snapshotLightAndDark(
            "server-objects-empty",
            size: CGSize(width: 720, height: 700),
            host: host
        ) {
            ServerObjectsPanel(initialSections: [ServerObjectSection(kind: .role)])
        }
        assertInjectedCopy(serverObjects, present: .serverObjectsEmpty, absent: .errorNotConnected)
    }

    // MARK: - L-44：界面检索走库（2026-09-28 第 54 轮）

    /// **界面检索走库 + 所走路线如实标注**（队列 L-44）。
    ///
    /// 这一族图要证明三件事 —— 只有第一件靠读图，另两件在渲染记录与状态上：
    ///   ① 副行真的写出了「这次是子串匹配」（渲染记录里必须有那句文案，中英各判各的）；
    ///   ② 结果**来自库**：内存里的 `state.notes` 整段**一直是空的**，而 `visibleNotes` 有两条 ——
    ///      「内存过滤」给不出这个组合（这正是 L-44 要改掉的那件事）；
    ///   ③ **全文检索命中不挂那句话**（`fullText` 的交代是 `nil`）：否则「如实标注」就退化成
    ///      「永远挂一行小字」，标了等于没标。第三张再拍**库读不出来**那一支 ——
    ///      「检索没跑成」不许说成「没找到」，列表退回**全部笔记**。
    ///
    /// 数据走的是**产品自己的库**（`DOYAH_NOTES_DIR` 指向每轮清空的临时目录），不是测试后门；
    /// 三条路都先把结果**算出来**再渲染（`.task(id:)` 在生产里负责这件事，图里不靠时间差）。
    @MainActor
    func testNoteSearchGoesThroughTheLibraryAndDisclosesTheRoute() async throws {
        let host = makeEmptyHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        _ = try UISnapshot.applyLicense(.standard, to: host.state)
        XCTAssertTrue(host.state.notesEnabled, "笔记区要在 Standard 档下才拍得到")

        // 夹具：两条笔记进库（一条正文含「洞庭湖」与「骑行」，另一条只有标签）。
        let library = NoteLibrary.defaultLibrary()
        let seeded = [
            try await library.upsert(
                NoteDraft(title: "环洞庭湖", body: "洞庭湖骑行手记", tags: ["骑行"], source: NoteSource(kind: .manual))
            ),
            try await library.upsert(
                NoteDraft(title: "南太行", body: "拉练前的准备清单", tags: ["骑行"], source: NoteSource(kind: .manual))
            )
        ]

        // ① 两字查询（中文里最常见的长度）⇒ 库里只能走子串兜底，界面必须如实标出。
        host.state.notesQuery = "骑行"
        await host.state.searchNotes()
        XCTAssertTrue(
            host.state.notes.isEmpty,
            "这一步不该往内存列表里塞东西 —— 下面那两条结果只能来自库（内存里是空的）"
        )
        XCTAssertEqual(host.state.visibleNotes.count, 2, "库里两条都命中「骑行」（正文 / 标签都算）")
        let substringPairs = try snapshotLightAndDark("notes-search-substring", size: sidebarSize, host: host) {
            NotesListView()
        }
        for pair in substringPairs {
            for (index, language) in UISnapshot.coverageLanguages.enumerated() {
                let record = pair.records[index]
                let expected = UISnapshot.localizedText(language) { L(.noteSearchSubstring) }
                XCTAssertTrue(
                    record.localizedStrings.contains(expected),
                    "\(record.name)：\(record.language) 那遍没有出现「\(expected)」"
                        + " —— 子串兜底没被如实标出（这一句就是 L-44 的交付物）"
                )
            }
        }

        // ② 三字以上且命中全文索引 ⇒ **不挂那一行**（对照图：标了就等于没标）。
        host.state.notesQuery = "洞庭湖"
        await host.state.searchNotes()
        XCTAssertEqual(host.state.visibleNotes.count, 1, "「洞庭湖」只有第一条正文里有")
        XCTAssertNil(host.state.noteSearchHint, "全文检索命中是检索的正常结果，不该额外解释")
        let fullTextPairs = try snapshotLightAndDark("notes-search-fulltext", size: sidebarSize, host: host) {
            NotesListView()
        }
        for pair in fullTextPairs {
            for (index, language) in UISnapshot.coverageLanguages.enumerated() {
                let record = pair.records[index]
                let forbidden = UISnapshot.localizedText(language) { L(.noteSearchSubstring) }
                XCTAssertFalse(
                    record.localizedStrings.contains(forbidden),
                    "\(record.name)：\(record.language) 那遍出现了子串兜底那句 —— 全文检索命中不该有它"
                )
            }
        }

        // ③ 库读不出来：**失败不许说成「没找到」**。
        //    先把列表读进内存（模拟应用已经打开过笔记），再把库文件换成一段垃圾 ——
        //    这样「检索没跑成」与「列表退回全部笔记」两件事能同时被看到。
        await host.state.reloadNotes()
        XCTAssertEqual(host.state.notes.count, 2, "前置：内存列表里有两条（库还没坏的时候读的）")
        try Data("not a sqlite database".utf8).write(to: library.fileURL)
        host.state.notesQuery = "骑行"
        await host.state.searchNotes()
        guard case .unavailable = host.state.noteSearchState else {
            XCTFail("库文件已经是垃圾了，这次检索该报「没跑成」，实际是 \(host.state.noteSearchState)")
            return
        }
        XCTAssertEqual(host.state.visibleNotes.count, 2, "检索没跑成时列表退回**全部笔记**（不是空的「没找到」）")
        let unavailablePairs = try snapshotLightAndDark("notes-search-unavailable", size: sidebarSize, host: host) {
            NotesListView()
        }
        for pair in unavailablePairs {
            for (index, language) in UISnapshot.coverageLanguages.enumerated() {
                let record = pair.records[index]
                let hint = UISnapshot.localizedText(language) { L(.noteSearchUnavailable, "…") }
                // 文案里带原因（`%@`），所以判**前缀**：模板前半句必须在渲染记录里。
                let head = String(hint.prefix(while: { $0 != "：" && $0 != ":" }))
                XCTAssertTrue(
                    record.localizedStrings.contains { $0.hasPrefix(head) },
                    "\(record.name)：\(record.language) 那遍没有说话「检索没跑成」"
                )
                let noMatch = UISnapshot.localizedText(language) { L(.noteSearchNoMatch) }
                XCTAssertFalse(
                    record.localizedStrings.contains(noMatch),
                    "\(record.name)：\(record.language) 那遍把「检索没跑成」说成了「没找到」"
                )
            }
        }

        // 收尾：把夹具清掉（库已损坏 ⇒ 直接删文件；迁移留档没参与过）。
        try? FileManager.default.removeItem(at: library.fileURL)
        try? FileManager.default.removeItem(at: library.fileURL.appendingPathExtension("wal"))
        _ = seeded
    }

    // MARK: - 清单

    override class func tearDown() {
        UISnapshot.finishManifestIfEnabled()
        super.tearDown()
    }
}
