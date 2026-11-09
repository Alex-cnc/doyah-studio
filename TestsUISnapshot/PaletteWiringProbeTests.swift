import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 命令面板**接线**的行为判据（FR-EDIT-25）—— 待人工验收清单 B 类的一行
/// （队列 `L-89` ㈡，开发循环第 92 轮）。
///
/// ## 为什么静态判据不够（这一条为什么还占着人的时间）
///
/// 清单里那一句人话是：「能搜到并执行；**每个命令都真的打开了对应面板（不是点了没反应）**」。
/// 原先还有一条 `Scripts/check-palette-wiring.py` 判的是**源码级**三件事（2026-11-10 摘离，本文件接手）：清单 id ↔ 分派器 case ↔
/// 标志位有没有视图读。它判不住的是**点下去真的会发生**——历史缺陷正是从那道缝里过的：
/// 10 条命令里 9 条设的标志位**没有任何视图读**（界面完全没反应），剩下那条**设错了**标志位
/// （`isAgentSQLCommandPresented` vs 界面绑的 `isAgentSQLPresented`）。两处都编译得过、
/// 单测全绿、静态判据也全绿。
///
/// 所以本文件走的是**真调用**：每一条命令都拿一个真的 `AppState` 调一遍
/// `performPaletteCommand(_:)`，断言**登记在案的落点**确实变了（标志位 / 新页签 / 编辑器命令 /
/// 状态栏说法 / 页签上的错误），且**「需要上下文」的三条命令在没有上下文时必须给一句说法**
/// 而不是静默返回。落点表与命令清单**双向对账**：新增一条命令却没人写它的落点 ⇒ 判红
/// （否则「点了没反应」会以同样的方式再长出来）。
///
/// ## 三条纪律（与 `UISnapshotKit` / 其他 App 内探针同源）
///
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 取证工具，不进每轮门禁；
/// · **不连任何数据库**：需要「当前连接」的那些命令只把 `connections` 里塞一条**内存里的**配置，
///   面板只是被打开、不发生任何网络动作；
/// · **不改用户偏好**：命令里 `focusObjectTreeSidebar()` 会走产品真实的 `selectActivityItem`
///   （它写活动栏偏好），本文件在 setUp 里记下原值、tearDown 原样放回。
///
/// ## 边界（如实登记）
///
/// · 「异步执行链」那几条（执行 / 检查 / 执行计划 / 导出）判的是**无连接时的落点**
///   （页签上的可读错误）——**真连库之后的落点**由 `Tests/` 里那些真库证据脚本守着，本文件不越界；
/// · 「停止」在没有在跑的查询时**按口径直接返回**（`executionTasks[tabID] == nil`），
///   本文件把这条静默**登记在案**（理由写在断言里），不假装它也会改状态；
/// · 落点表覆盖的是**命令清单**里的 id（40 条），不覆盖 ⌘K 之外的其他入口（菜单 / 工具栏）；
/// · 笔记面那 6 条（`N-UI-4`）的落点 = **人被带到笔记面** + 那一条命令自己的状态；内容那一半
///   （新建后正文为空）只判「空」，不预置内容 —— 预置会让 `beginNewNote()` 的「切走即存」
///   真往用户库里写一条，探针不许碰用户数据。
final class PaletteWiringProbeTests: XCTestCase {

    /// 命令里 `focusObjectTreeSidebar()` 会写活动栏偏好：先记下来，跑完放回去。
    private var savedActivityItem: String?

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "命令面板接线探针要真调用产品接口：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
        savedActivityItem = UserDefaults.standard.string(forKey: ActivityBarItem.storageKey)
    }

    override func tearDownWithError() throws {
        if let savedActivityItem {
            UserDefaults.standard.set(savedActivityItem, forKey: ActivityBarItem.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ActivityBarItem.storageKey)
        }
    }

    // MARK: - 面板标志位（落点的一种）

    /// 命令面板能打开的那几处面板标志位。
    ///
    /// 前 **17** 个正是 `Scripts/check-palette-wiring.py` 在 `performPaletteCommand` 里数出来的那 17 个
    /// （静态判据判「至少有一个视图读它们」）；后 **3** 个由 `open*()` helper 设置、同样落到界面上。
    enum Flag: CaseIterable {
        case browseRows, session, lock, synthetic
        case connectionSwitch, agentSQL, egressLog, shortcutHelp
        case objectSearch, routineCandidates, importData, backupRestore
        case connectionSettings, databaseStats, schemaDiff, erDiagram
        case serverObjects, diagnosis, maintenance, mcpApproval
        case slowQuery

        var name: String {
            switch self {
            case .browseRows: return "isBrowseRowsCommandPresented"
            case .session: return "isSessionCommandPresented"
            case .lock: return "isLockCommandPresented"
            case .synthetic: return "isSyntheticCommandPresented"
            case .connectionSwitch: return "isConnectionSwitchPresented"
            case .agentSQL: return "isAgentSQLPresented"
            case .egressLog: return "isEgressLogPresented"
            case .shortcutHelp: return "isShortcutHelpCommandPresented"
            case .objectSearch: return "isObjectSearchPresented"
            case .routineCandidates: return "isRoutineCandidatesPresented"
            case .importData: return "isImportPresented"
            case .backupRestore: return "isBackupRestorePresented"
            case .connectionSettings: return "isConnectionSettingsPresented"
            case .databaseStats: return "isDatabaseStatsPresented"
            case .schemaDiff: return "isSchemaDiffPresented"
            case .erDiagram: return "isERDiagramPresented"
            case .serverObjects: return "isServerObjectsPresented"
            case .diagnosis: return "isDiagnosisPresented"
            case .maintenance: return "isMaintenancePresented"
            case .mcpApproval: return "isMCPApprovalPresented"
            case .slowQuery: return "isSlowQueryPresented"
            }
        }

        @MainActor
        func isOn(_ state: AppState) -> Bool {
            switch self {
            case .browseRows: return state.isBrowseRowsCommandPresented
            case .session: return state.isSessionCommandPresented
            case .lock: return state.isLockCommandPresented
            case .synthetic: return state.isSyntheticCommandPresented
            case .connectionSwitch: return state.isConnectionSwitchPresented
            case .agentSQL: return state.isAgentSQLPresented
            case .egressLog: return state.isEgressLogPresented
            case .shortcutHelp: return state.isShortcutHelpCommandPresented
            case .objectSearch: return state.isObjectSearchPresented
            case .routineCandidates: return state.isRoutineCandidatesPresented
            case .importData: return state.isImportPresented
            case .backupRestore: return state.isBackupRestorePresented
            case .connectionSettings: return state.isConnectionSettingsPresented
            case .databaseStats: return state.isDatabaseStatsPresented
            case .schemaDiff: return state.isSchemaDiffPresented
            case .erDiagram: return state.isERDiagramPresented
            case .serverObjects: return state.isServerObjectsPresented
            case .diagnosis: return state.isDiagnosisPresented
            case .maintenance: return state.isMaintenancePresented
            case .mcpApproval: return state.isMCPApprovalPresented
            case .slowQuery: return state.isSlowQueryPresented
            }
        }
    }

    // MARK: - 落点（点下去之后**必须变**的东西）

    indirect enum Landing {
        /// 同步：这个面板标志位必须变 true。
        case panel(Flag)
        /// 同步：必须多出一个查询页签，且它被选中。
        case newTab
        /// 同步：编辑器命令中心收到的必须是这条命令（且指向活动页签）。
        case editor(EditorCommand)
        /// 同步：状态栏必须变成这句（无上下文时的「说法」）。
        case status(String)
        /// 异步：`state.errorMessage` 必须变成这句（执行链在无连接 / 无结果集时的落点）。
        case appError(String)
        /// 异步：`state.executionPlanError` 必须变成这句。
        case planError(String)
        /// 异步：活动页签的 `errorMessage` 必须变成这句。
        case tabError(String)
        /// 异步：活动页签的 `syntaxCheckMessage` 必须变成这句。
        case tabSyntaxError(String)
        /// 笔记入口：**两档各判一面**（Pro 不含笔记 ⇒ 照实说；Standard ⇒ 真的切过去）。
        case notesEntry
        /// 笔记面命令（`N-UI-4` 那 6 条）：**先判「人有没有被带到笔记面」，再看具体状态**。
        case notes(NotesLanding)
        /// 快速捕获（`FR-NTS-NOTE-CAPTURE-001`）：**不切活动面** —— 捕获面的意义就是
        /// 「在任何面都能记」，把人拽去笔记面反而是错的。
        case quickCapture
        /// 按口径**直接返回**（理由必须写在断言里，免得「真的没反应」混进来）。
        case silentByDesign(String)
        /// 需要**对象树选中项**（`paletteTreeObject`）：备好表 ⇒ 内层落点；没备 ⇒ 必须给这句说法。
        case withTable(Landing, withoutObject: String)
        /// 需要**当前连接**（`prepareObjectTreePanel`）：备好 ⇒ 内层落点；没备 ⇒ 必须给这句说法。
        case withConnection(Landing, withoutConnection: String)
    }

    /// 笔记面那 6 条命令的**具体落点**（`N-UI-4`）。
    ///
    /// 为什么「切到笔记面」必须也是判据的一半：这 6 条挂在**全局**的 `⌘K` 面板上（面板不按
    /// 活动面过滤），人可能站在数据库面点中它们。从前它们只改笔记面的状态 —— 状态改了、
    /// 改在看不见的地方，屏幕上什么都不动，与这批命令当初那一族「点了没反应」同一种病，
    /// 只是这次藏在「状态确实变了」后面。只登记「状态变了」会把那件事判成通过。
    enum NotesLanding {
        /// 编辑器回到**新建态**（并且可写）。内容那一半不在这里判：往预置编辑器里塞内容会让
        /// `beginNewNote()` 的「切走即存」真的往用户库里写一条 —— 探针不许碰用户数据。
        case newNoteDraft
        /// 弹「新建笔记本」；库上一个架都没有时**不许弹一个落不了地的框**，只许如实说一句。
        case notebookCreation
        case searchScope(NotesSearchScope)
        case scope(NotesScope)
        /// 导出 / 导入（`FR-NTS-NOTE-EXPORT-001`）：命令只发请求，面板由笔记面视图弹 ——
        /// 探针宿主里没有视图，所以判的是「请求已发出」，不是「面板已弹」。
        case archiveExport(NoteArchiveFormat.Kind)
        case archiveImport
    }

    // MARK: - 落点表（与命令清单双向对账见 testEveryCommandHasARegisteredLanding）

    private static var wiring: [(id: String, landing: Landing)] {
        [
            ("newQuery", .newTab),
            // 下面这些的落点在**异步执行链**上：无连接时页签上必须出现可读错误（不是静默）。
            ("execute", .tabError(L(.stateSelectConnectionFirst))),
            ("check", .tabSyntaxError(L(.stateSelectConnectionFirst))),
            ("executionPlan", .planError(L(.stateSelectConnectionFirst))),
            ("exportCSV", .appError(L(.exportNoData))),
            ("exportJSON", .appError(L(.exportNoData))),
            ("format", .editor(.format)),
            ("find", .editor(.showFind)),
            ("replace", .editor(.showReplace)),
            ("goToLine", .status(L(.commandGoToLineHint, AppShortcut.goToLine.display))),
            // 「停止」：没有在跑的查询时按口径直接返回（`executionTasks[tabID] == nil`）——
            // 这一条不是「点了没反应」的缺陷，是设计；登记在案（真取消链路由 Tests/ 里的取消证据守）。
            ("stop", .silentByDesign("当前页签没有在跑的查询（`executionTasks[tabID] == nil`）⇒ 按口径直接返回")),
            // 需要对象上下文的四条：备好 ⇒ 落点成立；没备 ⇒ 必须说一句（旧缺陷就是这里静默）。
            ("browseRows", .withTable(.panel(.browseRows), withoutObject: L(.paletteNeedsTreeObject))),
            ("syntheticData", .withTable(.panel(.synthetic), withoutObject: L(.paletteNeedsTreeObject))),
            // 「查看 DDL」没有面板：它就是**生成语句进新页签**（要先有连接才取得到定义）
            // ⇒ 有表选中但没连接时，落点是 `performTreeAction` 的那句可读错误。
            ("tableDDL", .withTable(.appError(L(.stateSelectConnectionFirst)), withoutObject: L(.paletteNeedsTreeObject))),
            ("sessions", .withConnection(.panel(.session), withoutConnection: L(.stateSelectConnectionFirst))),
            ("locks", .withConnection(.panel(.lock), withoutConnection: L(.stateSelectConnectionFirst))),
            // 其余面板类：同步设标志位，界面订阅它。
            ("importData", .panel(.importData)),
            ("backupRestore", .panel(.backupRestore)),
            ("connectionSettings", .panel(.connectionSettings)),
            ("databaseStats", .panel(.databaseStats)),
            ("serverObjects", .panel(.serverObjects)),
            ("schemaDiff", .panel(.schemaDiff)),
            ("erDiagram", .panel(.erDiagram)),
            ("routineCandidates", .panel(.routineCandidates)),
            ("objectSearch", .panel(.objectSearch)),
            ("switchConnection", .panel(.connectionSwitch)),
            ("agentSQL", .panel(.agentSQL)),
            ("diagnoseQuery", .panel(.diagnosis)),
            ("maintenanceTasks", .panel(.maintenance)),
            ("mcpApprovals", .panel(.mcpApproval)),
            ("egressLog", .panel(.egressLog)),
            ("help", .panel(.shortcutHelp)),
            // 慢查询排行（`FR-DIAG-03`）：分派器把 `isSlowQueryPresented` 设 true，`MainWindow` 的
            // `.sheet(isPresented:)` 打开 `SlowQueryPanel` —— 与「显示」菜单同一处面板。
            ("slowQuery", .panel(.slowQuery)),
            ("notes", .notesEntry),
            // 笔记面那 6 条（`N-UI-4`）：命令在**全局**面板里，落点 = ① 人真的被带到笔记面
            // ② 那一条命令自己的状态变化（编辑器新建态 / 新建笔记本请求 / 搜索范围 / 一级导航）。
            ("newNote", .notes(.newNoteDraft)),
            ("quickCapture", .quickCapture),
            ("newNotebook", .notes(.notebookCreation)),
            ("noteSearchScopeCurrent", .notes(.searchScope(.current))),
            ("noteSearchScopeAll", .notes(.searchScope(.all))),
            ("noteFavorites", .notes(.scope(.favorites))),
            ("noteAllNotes", .notes(.scope(.all))),
            ("notesExportMarkdown", .notes(.archiveExport(.markdown))),
            ("notesExportPlainText", .notes(.archiveExport(.plainText))),
            ("notesExportBackup", .notes(.archiveExport(.package))),
            ("notesImportBackup", .notes(.archiveImport)),
        ]
    }

    // MARK: - 装配

    private struct Context {
        let state: AppState
        let tabID: UUID
    }

    /// 一个**不连库、不碰用户数据**的宿主：Standard 档许可证（笔记 / 数据库都在），
    /// 起点是「一条连接都没有、对象树没选中项」—— 命令要什么上下文，由落点表那一侧显式备。
    @MainActor
    private func makeState(withConnection: Bool, withTable: Bool) throws -> Context {
        let state = AppState()
        state.connections = []
        state.selectedConnectionID = nil
        state.selectedTreeObject = nil
        try UISnapshot.applyLicense(.standard, to: state)
        // 活动栏先落回「数据库」：命令里的 `focusObjectTreeSidebar()` 于是不需要改偏好
        // （真改了也在 tearDown 放回）。许可刚换过，`reloadLicense()` 会把状态栏写成许可证摘要，
        // 所以清空必须放在它后面 —— 否则「有没有说法」的起点不干净。
        state.selectActivityItem(.database)
        state.statusMessage = ""
        state.errorMessage = nil
        state.executionPlanError = nil
        if withConnection {
            let config = ConnectionConfig(
                name: "探针库（不连）", dbType: .postgresql, port: 5432, database: "demo", username: "alex"
            )
            state.connections = [config]
            state.selectedConnectionID = config.id
            XCTAssertNotNil(state.selectedConnection, "探针前提：内存里的那条配置应当成为「当前连接」")
        }
        if withTable {
            state.selectedTreeObject = DatabaseObject(
                id: "probe:orders", name: "orders", kind: .table, database: "demo", schema: "public"
            )
        }
        state.newQueryTab()
        return Context(state: state, tabID: state.selectedTabID ?? UUID())
    }

    /// 等待异步执行链落到界面上（都跑在主 actor 上，让几拍就够）。
    @MainActor
    private func settle(_ condition: @escaping () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }

    // MARK: - 驱动

    @MainActor
    private func drive(
        _ id: String,
        _ landing: Landing,
        context: Context,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let state = context.state
        let tabID = context.tabID
        let tab = { state.tabs.first { $0.id == tabID } }

        switch landing {
        case .panel(let flag):
            state.performPaletteCommand(id)
            await settle { true }
            XCTAssertTrue(
                flag.isOn(state),
                "「\(id)」点下去必须打开面板（\(flag.name) 为 true）—— 点了没反应就是这个缺陷",
                file: file, line: line
            )

        case .newTab:
            let before = state.tabs.count
            state.performPaletteCommand(id)
            XCTAssertEqual(state.tabs.count, before + 1, "「\(id)」应当新开一个查询页签", file: file, line: line)
            XCTAssertEqual(state.selectedTabID, state.tabs.last?.id, "「\(id)」新开的页签应当被选中", file: file, line: line)

        case .editor(let command):
            state.performPaletteCommand(id)
            let request = EditorCommandCenter.shared.request
            XCTAssertEqual(request?.command, command, "「\(id)」必须把这条命令交给编辑器命令中心", file: file, line: line)
            XCTAssertEqual(request?.tabID, tabID, "「\(id)」交给编辑器命令中心的必须是**活动页签**", file: file, line: line)

        case .status(let expected):
            state.performPaletteCommand(id)
            XCTAssertEqual(state.statusMessage, expected, "「\(id)」应当在状态栏给这句话", file: file, line: line)

        case .appError(let expected):
            state.performPaletteCommand(id)
            let landed = await settle { state.errorMessage == expected }
            XCTAssertTrue(landed, "「\(id)」异步落点应当是 \(expected)，实际 \(state.errorMessage ?? "（空）")", file: file, line: line)

        case .planError(let expected):
            state.performPaletteCommand(id)
            let landed = await settle { state.executionPlanError == expected }
            XCTAssertTrue(landed, "「\(id)」异步落点应当是 \(expected)，实际 \(state.executionPlanError ?? "（空）")", file: file, line: line)

        case .tabError(let expected):
            state.performPaletteCommand(id)
            let landed = await settle { tab()?.errorMessage == expected }
            XCTAssertTrue(
                landed, "「\(id)」应当在页签上留下可读错误 \(expected)，实际 \(tab()?.errorMessage ?? "（空）")",
                file: file, line: line
            )

        case .tabSyntaxError(let expected):
            state.performPaletteCommand(id)
            let landed = await settle { tab()?.syntaxCheckMessage == expected }
            XCTAssertTrue(
                landed, "「\(id)」应当在页签上留下可读的检查结果 \(expected)，实际 \(tab()?.syntaxCheckMessage ?? "（空）")",
                file: file, line: line
            )

        case .quickCapture:
            XCTAssertFalse(
                state.quickCapture.isPresenting,
                "探针前提：起点不该已经开着捕获面", file: file, line: line
            )
            state.performPaletteCommand(id)
            XCTAssertTrue(
                state.quickCapture.isPresenting,
                "「\(id)」必须把捕获面打开 —— 判据①是「一个动作就能输入」，打不开就等于这条命令没接线",
                file: file, line: line
            )
            XCTAssertTrue(
                state.quickCapture.focusRequested,
                "「\(id)」打开捕获面时焦点必须直接进正文框（否则人还要再点一下）",
                file: file, line: line
            )
            XCTAssertEqual(
                state.selectedActivityItem, .database,
                "「\(id)」不许把人从当前面拽走（捕获是在任何地方都能记）",
                file: file, line: line
            )

        case .notesEntry:
            try await driveNotesEntry(state, file: file, line: line)

        case .notes(let inner):
            try await driveNotesCommand(id, inner, file: file, line: line)

        case .silentByDesign(let reason):
            let before = (state.statusMessage, state.errorMessage, state.tabs.count, tab()?.errorMessage)
            state.performPaletteCommand(id)
            await settle { false }
            let after = (state.statusMessage, state.errorMessage, state.tabs.count, tab()?.errorMessage)
            XCTAssertEqual(after.0, before.0, "「\(id)」登记为「静默」但动了状态栏：\(reason)", file: file, line: line)
            XCTAssertEqual(after.1, before.1, "「\(id)」登记为「静默」但写了错误：\(reason)", file: file, line: line)
            XCTAssertEqual(after.2, before.2, "「\(id)」登记为「静默」但开了页签：\(reason)", file: file, line: line)

        case .withTable(let inner, let withoutObject):
            // ① 没备对象：**必须给一句说法**，且不许悄悄打开面板（旧缺陷的静默就长这样）。
            let empty = try makeState(withConnection: false, withTable: false)
            empty.state.performPaletteCommand(id)
            await settle { false }
            XCTAssertEqual(
                empty.state.statusMessage, withoutObject,
                "「\(id)」没有对象树选中项时必须说一句（这句话是「不是点了没反应」的证据）",
                file: file, line: line
            )
            if case .panel(let flag) = inner {
                XCTAssertFalse(flag.isOn(empty.state), "「\(id)」没有对象上下文时不该打开面板（\(flag.name)）", file: file, line: line)
            }
            // ② 备好对象：内层落点必须成立。
            let prepared = try makeState(withConnection: false, withTable: true)
            try await drive(id, inner, context: prepared, file: file, line: line)

        case .withConnection(let inner, let withoutConnection):
            let empty = try makeState(withConnection: false, withTable: false)
            empty.state.performPaletteCommand(id)
            await settle { false }
            XCTAssertEqual(
                empty.state.statusMessage, withoutConnection,
                "「\(id)」没有当前连接时必须说一句（而不是开一个必然报错的面板）",
                file: file, line: line
            )
            let prepared = try makeState(withConnection: true, withTable: true)
            try await drive(id, inner, context: prepared, file: file, line: line)
        }
    }

    /// 笔记入口：**档位不同，落点不同** —— Pro 不含笔记，就得照实说，不许切过去装成功。
    @MainActor
    private func driveNotesEntry(_ state: AppState, file: StaticString, line: UInt) async throws {
        try UISnapshot.applyLicense(.pro, to: state)
        state.statusMessage = ""
        XCTAssertFalse(
            state.visibleActivityItems.contains(.notes),
            "探针前提：Pro 档位不该有笔记区（没有这个前提，下面那条断言是空的）",
            file: file, line: line
        )
        state.performPaletteCommand("notes")
        XCTAssertEqual(
            state.statusMessage, L(.licenseNotesNotIncluded),
            "Pro 档位下「笔记」必须照实说本档位不含笔记（不是静默、也不是假装切过去）",
            file: file, line: line
        )
        XCTAssertNotEqual(state.selectedActivityItem, .notes, "Pro 档位下不该切到笔记区", file: file, line: line)

        try UISnapshot.applyLicense(.standard, to: state)
        state.statusMessage = ""
        XCTAssertTrue(
            state.visibleActivityItems.contains(.notes),
            "探针前提：Standard 档位必须有笔记区",
            file: file, line: line
        )
        state.performPaletteCommand("notes")
        XCTAssertEqual(state.selectedActivityItem, .notes, "Standard 档位下「笔记」应当真的切到笔记区", file: file, line: line)
    }

    /// 笔记面那 6 条命令（`N-UI-4`）：起点站在**数据库面**，先判「人有没有被带到笔记面」，
    /// 再判那一条命令自己的状态落点。
    ///
    /// 为什么起点一定要是数据库面：面板是全局的（`CommandPaletteView` 不按活动面过滤），
    /// 这 6 条从数据库面也点得到。只判「状态变了」会放过「状态改了、但改在看不见的地方」。
    /// 档位用 Ultra（工作区 + 数据库 + 笔记三块都在）—— Standard 只有笔记，站在数据库面这件事
    /// 在那一档根本构造不出来（`selectActivityItem(.database)` 会被落回可见项并给一句说明）。
    @MainActor
    private func driveNotesCommand(
        _ id: String,
        _ landing: NotesLanding,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let state = AppState()
        try UISnapshot.applyLicense(.ultra, to: state)
        state.selectActivityItem(.database)
        XCTAssertEqual(
            state.selectedActivityItem, .database,
            "探针前提：Ultra 档下起点必须真的是数据库面（否则「会不会切过去」这半条断言是空的）",
            file: file, line: line
        )
        state.statusMessage = ""
        state.errorMessage = nil

        // 起点先摆成「不是落点」的值，免得断言在默认值上空转。
        switch landing {
        case .newNoteDraft:
            state.editorMode = .preview
        case .notebookCreation:
            state.pendingContainerEdit = nil
            state.statusMessage = ""
        case .searchScope(let target):
            state.notesSearchScope = (target == .all) ? .current : .all
        case .scope(let target):
            state.notesScope = (target == .favorites) ? .all : .favorites
        case .archiveExport, .archiveImport:
            state.notesArchiveRequest = nil
        }

        state.performPaletteCommand(id)

        XCTAssertEqual(
            state.selectedActivityItem, .notes,
            "「\(id)」在数据库面点下去必须把人带到笔记面 —— 否则状态改在看不见的地方，屏幕上什么都没发生",
            file: file, line: line
        )

        switch landing {
        case .newNoteDraft:
            XCTAssertEqual(
                state.editorMode, .edit,
                "「\(id)」新建之后编辑器必须是**可写**态（`.edit`），实际 \(state.editorMode)",
                file: file, line: line
            )
            XCTAssertEqual(state.noteEditorTitle, "", "「\(id)」新建之后标题格必须是空的", file: file, line: line)
            XCTAssertEqual(state.noteEditorBody, "", "「\(id)」新建之后正文必须是空的", file: file, line: line)
            XCTAssertTrue(state.noteEditorSpans.isEmpty, "「\(id)」新建之后 span 树必须是空的", file: file, line: line)
            XCTAssertEqual(state.noteEditorTags, "", "「\(id)」新建之后标签格必须是空的", file: file, line: line)

        case .notebookCreation:
            if state.notesNavigation.directory.shelves.isEmpty {
                // 一个架都没有：**不弹框**，如实说一句（弹一个落不了地的框是把两件事混成一件）。
                XCTAssertNil(
                    state.pendingContainerEdit,
                    "「\(id)」在没有架的时候不该弹「新建笔记本」框 —— 那个框落不了地",
                    file: file, line: line
                )
                XCTAssertEqual(
                    state.statusMessage, L(NotebookCreation.noShelfKey),
                    "「\(id)」在没有架的时候必须说一句人话，实际「\(state.statusMessage)」",
                    file: file, line: line
                )
            } else {
                XCTAssertEqual(
                    state.pendingContainerEdit?.mode, .createNotebook,
                    "「\(id)」在有架的时候应当弹出「新建笔记本」请求，实际 \(String(describing: state.pendingContainerEdit?.mode))",
                    file: file, line: line
                )
            }

        case .searchScope(let target):
            XCTAssertEqual(
                state.notesSearchScope, target,
                "「\(id)」必须把搜索范围切到 \(target)，实际 \(state.notesSearchScope)",
                file: file, line: line
            )

        case .archiveExport(let kind):
            XCTAssertEqual(
                state.notesArchiveRequest, .export(kind),
                "「\(id)」点下去必须发出导出请求 —— 否则「点了没反应」", file: file, line: line
            )
        case .archiveImport:
            XCTAssertEqual(
                state.notesArchiveRequest, .importPackage,
                "「\(id)」点下去必须发出导入请求 —— 否则「点了没反应」", file: file, line: line
            )
        case .scope(let target):
            XCTAssertEqual(
                state.notesScope, target,
                "「\(id)」必须把一级导航切到 \(target)，实际 \(state.notesScope)",
                file: file, line: line
            )
        }
    }

    // MARK: - 用例

    /// ① 双向对账：命令清单里的每一条都要有登记在案的**落点**。
    @MainActor
    func testEveryCommandHasARegisteredLanding() throws {
        let catalog = AppCommandCatalog.all().map(\.id)
        let registered = Self.wiring.map(\.id)
        XCTAssertEqual(
            Set(catalog).count, catalog.count,
            "命令清单里有重复 id：\(catalog.count) 条 / 去重后 \(Set(catalog).count) 条"
        )
        XCTAssertEqual(
            Set(registered).count, registered.count,
            "落点表里有重复 id：\(registered.count) 条 / 去重后 \(Set(registered).count) 条"
        )
        let missing = Set(catalog).subtracting(registered).sorted()
        let extra = Set(registered).subtracting(catalog).sorted()
        XCTAssertTrue(
            missing.isEmpty,
            "这 \(missing.count) 条命令没人登记落点 ⇒ 它们点了有没有反应没人管：\(missing)"
        )
        XCTAssertTrue(
            extra.isEmpty,
            "落点表里这 \(extra.count) 条已经不是命令了（漂移）：\(extra)"
        )
    }

    /// ② 每条命令**真的点一遍**：落点必须发生。
    @MainActor
    func testEveryCommandLandsItsRegisteredEffect() async throws {
        for (id, landing) in Self.wiring {
            let context = try makeState(withConnection: false, withTable: false)
            try await drive(id, landing, context: context)
        }
    }
}
