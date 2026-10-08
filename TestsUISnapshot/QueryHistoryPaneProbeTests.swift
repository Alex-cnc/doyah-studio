import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「历史」页签（`FR-EDIT-10` v3.326 扩写 / `DR-02`）的 **App 侧探针**（队列 `HIST-2` ·
/// 派单 `T-20261009-018` / `T-20261009-010`）。
///
/// ## 这个文件要钉住的三件事（卡上的判据 2 / 3 / 4）
///
/// ① **段条件（`FR-EDIT-10`）**：「历史」**只在 Database 客户端段出现**；切到工作区段 ⇒ 页签
///    **不可见**，且若正选中它 ⇒ **自动落到该段可用页签（终端）**；切回 Database 段 ⇒
///    **恢复上次选中**。可见性判的是**渲染出来的那一行**（真视图 `LowerPaneTabStrip` 离屏渲染，
///    记录里那遍实际取到的文案 —— 文案是期望值，且由语言表本身给，不写死）。
/// ② **同源（`HIST-2` 明令「不许两处各自读盘」）**：页面与工具条时钟菜单读的是**同一份**
///    `AppState.queryHistory`；`App/` 里凡提到落盘门面 `QueryHistoryStore` 的文件**只许一个**
///    （`AppState.swift`）—— 源码锚点 + 读盘点唯一，都在这里判。
/// ③ **二次确认（`DR-02`：可清空 / 单条删除）**：点「清空」/「删除」**只挂请求**（历史条数不变、
///    库里一个字节不动）；**取消**同样一个字节不动；**确认**才落库（清空 ⇒ 0 / 单条 ⇒ 减 1）。
///    读数两处都给：内存镜像（`AppState.queryHistory`）与**库里真值**（另开一个门面实例读盘）。
///
/// ## 边界（如实登记）
///
/// · 本文件**不点界面**：确认框能不能弹、弹出来长什么样，由真机图（组长在解锁窗口补拍）承担；
///   这里判的是「挂请求 / 取消 / 确认」三态与**文案键在位**（标题 / 正文由 `AppState` 生成为非空）。
/// · **夹具只写临时数据家**：要落盘的那条用例走 `DOYAH_NOTES_DIR`（取证脚本会指到每轮清空的
///   临时目录）；没有它一律 `XCTSkip` —— 探针不许碰真实用户笔记库。
final class QueryHistoryPaneProbeTests: XCTestCase {

    /// 工具条那一行的尺寸（点）：与其它探针同一个尺子（`TerminalTabsProbeTests.stripSize`）。
    private static let stripSize = CGSize(width: 900, height: 40)

    // MARK: - 装配

    private struct Host {
        let state: AppState
        let workspace: WorkspaceStore
        let tabs: WorkspaceTabsModel
        let terminal: TerminalModel
    }

    /// 一个不连库、不碰用户数据的宿主（真 `AppState` / 真 `TerminalModel`）。
    ///
    /// 许可证取 **Ultra**：数据库段与工作区段**都必须可见**（Standard 只有笔记，
    /// 切不过去 ⇒ 段条件根本走不到）。
    @MainActor
    private func makeHost() throws -> Host {
        let scratch = UISnapshot.outputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        let state = AppState()
        state.connections = []
        state.selectedConnectionID = nil
        state.newQueryTab()
        _ = try UISnapshot.applyLicense(.ultra, to: state)

        return Host(
            state: state,
            workspace: WorkspaceStore.shared,
            tabs: WorkspaceTabsModel(
                store: WorkspaceHistoryStore(
                    fileURL: scratch.appendingPathComponent("history-pane-probe-\(UUID().uuidString).json")
                )
            ),
            terminal: TerminalModel()
        )
    }

    /// 渲染一遍**真页签条**（`LowerPaneTabStrip` —— 产品里正在用的那一个）。
    ///
    /// 能单独离屏渲染的理由与 `TerminalTabsProbeTests` 相同：它不带下方面板的内容半边
    /// （那一半挂着 `TerminalHostView`，一渲染就会真开 shell）。
    @MainActor
    private func renderStrip(_ name: String, host: Host) throws -> UISnapshot.LanguagePair {
        try UISnapshot.writeBothLanguages(name, size: Self.stripSize) {
            LowerPaneTabStrip(tab: host.state.selectedTab, isCollapsed: false)
                .snapshotEnvironment(
                    state: host.state,
                    workspace: host.workspace,
                    tabs: host.tabs,
                    terminal: host.terminal
                )
        }
    }

    // MARK: - 判据 2：段条件（可见性 + 选中项的成对读数）

    /// `FR-EDIT-10` 段条件那一句的机械形状（三态、成对读数）。
    @MainActor
    func testHistoryTabFollowsSegmentAndRestoresSelection() throws {
        try XCTSkipUnless(UISnapshot.isEnabled, "快照要 DOYAH_UI_SNAPSHOT=1")

        let host = try makeHost()
        // 期望值**取自语言表本身**（同一遍宿主语境里取），不写死中文 —— 写死就与语言表脱钩了。
        let historyText = UISnapshot.localizedText(.simplifiedChinese) { L(.lowerPaneHistory) }
        XCTAssertEqual(historyText, "历史", "语言表里「历史」页签的简中文案变了 —— 下面的期望值要跟着改")

        // 甲：**Database 段** ⇒ 页签可见，且序里「历史」在**最后一位**。
        host.state.selectActivityItem(.database)
        host.state.lowerPaneTab = .history
        XCTAssertEqual(
            host.state.availableLowerPaneTabs,
            LowerPaneTab.allCases,
            "Database 段必须给出全部页签（含「历史」）"
        )
        XCTAssertEqual(host.state.availableLowerPaneTabs.last, .history, "「序」要求历史排在最后")
        let database = try renderStrip("manual-check-history-strip-database", host: host)
        XCTAssertTrue(
            database.records[0].localizedStrings.contains(historyText),
            "Database 段渲染出的页签条里没有「历史」——段条件把该出现的页签藏了"
                + "（观测到的文案：\(database.records[0].localizedStrings.sorted().joined(separator: " / "))）"
        )
        print(
            "[HIST-2] 甲 段=database 选中页签=\(host.state.lowerPaneTab.rawValue)"
                + " 可见页签=\(host.state.availableLowerPaneTabs.map(\.rawValue).joined(separator: ","))"
        )

        // 乙：**切到工作区段** ⇒ 页签不可见；正选中「历史」⇒ 自动落到该段可用页签（终端）。
        host.state.selectActivityItem(.workspace)
        XCTAssertEqual(
            host.state.lowerPaneTab,
            .terminal,
            "切到工作区段时正选中「历史」⇒ 必须自动落到该段可用页签（终端）"
        )
        XCTAssertFalse(host.state.availableLowerPaneTabs.contains(.history), "工作区段不该有「历史」")
        XCTAssertEqual(
            host.state.availableLowerPaneTabs.count,
            LowerPaneTab.allCases.count - 1,
            "工作区段只该少「历史」这一枚"
        )
        let workspace = try renderStrip("manual-check-history-strip-workspace", host: host)
        XCTAssertFalse(
            workspace.records[0].localizedStrings.contains(historyText),
            "工作区段渲染出的页签条里出现了「历史」——段条件没生效"
        )
        print(
            "[HIST-2] 乙 段=workspace 选中页签=\(host.state.lowerPaneTab.rawValue)"
                + " 可见页签=\(host.state.availableLowerPaneTabs.map(\.rawValue).joined(separator: ","))"
        )

        // 丙：**切回 Database 段** ⇒ 恢复上次选中（历史）。
        host.state.selectActivityItem(.database)
        XCTAssertEqual(host.state.lowerPaneTab, .history, "切回 Database 段必须恢复上次选中（历史）")
        print("[HIST-2] 丙 段=database 选中页签=\(host.state.lowerPaneTab.rawValue)（= 恢复上次选中）")

        // 反向对照：切到工作区段时**没**选中「历史」的那条路不该被改动
        // （只该动「历史」这一档，别的页签跨段原样保留）。
        host.state.selectActivityItem(.workspace)
        host.state.lowerPaneTab = .output
        host.state.selectActivityItem(.database)
        XCTAssertEqual(host.state.lowerPaneTab, .output, "别的页签跨段往返必须原样保留（不许被「恢复」逻辑顺手改掉）")
    }

    // MARK: - 判据 3：同源（源码锚点 + 读盘点唯一）

    /// 「页签与时钟菜单**同一份数据**」这件事的机械形状。
    ///
    /// 为什么用源码锚点而不是渲染：这两处一个在工具条（`QueryToolbar`）、一个在下方面板
    /// （`LowerPaneView`），离屏渲染两个视图也证不出「读的是同一个属性」——
    /// 那件事的形状就是**锚点 + 读盘点唯一**（卡上的判据 3 原话：「grep 命中数 = 1 处读盘」）。
    func testHistoryPaneAndClockMenuShareOneSourceAndOneReader() throws {
        let root = UISnapshot.packageRoot
        let strip = try read("App/Views/LowerPaneTabStrip.swift", from: root)
        let pane = try read("App/Views/LowerPaneView.swift", from: root)
        let toolbar = try read("App/Views/QueryToolbar.swift", from: root)

        // 页签条：画的是**唯一出处**给的页签、且承载两处确认框（收请求 / 取消 / 确认）。
        for anchor in [
            "appState.availableLowerPaneTabs",
            "pendingHistoryRemoval",
            "cancelHistoryRemoval",
            "confirmHistoryRemoval",
            "pendingHistoryRemovalTitle",
            "pendingHistoryRemovalMessage",
            "QueryHistoryRemovalPrompt.actionTitleKey",
        ] {
            XCTAssertTrue(strip.contains(anchor), "`LowerPaneTabStrip.swift` 缺锚点 `\(anchor)`")
        }

        // 历史页：读**同一份** `appState.queryHistory`；两枚动作都只是**挂请求**。
        for anchor in [
            "case .history:",
            "appState.queryHistory",
            "requestClearQueryHistory()",
            "requestDeleteHistory(entry)",
            "appState.canClearQueryHistory",
        ] {
            XCTAssertTrue(pane.contains(anchor), "`LowerPaneView.swift` 缺锚点 `\(anchor)`")
        }
        XCTAssertFalse(pane.contains("queryHistoryStore"), "历史页**不许自己去开门面**（读盘只能有一处）")

        // 时钟菜单：列表与摘要是**同一份 / 同一口径**；清空走**同一个**确认入口。
        for anchor in ["appState.queryHistory", "requestClearQueryHistory()", "AppState.historyPreview"] {
            XCTAssertTrue(toolbar.contains(anchor), "`QueryToolbar.swift` 缺锚点 `\(anchor)`")
        }

        // **读盘点唯一**：`App/` 里提到落盘门面 `QueryHistoryStore` 的文件只许 `AppState.swift` 一个。
        var readers: [String] = []
        for path in try swiftFiles(under: root.appendingPathComponent("App")) {
            if try read(path, from: root).contains("QueryHistoryStore") {
                readers.append(path)
            }
        }
        readers.sort()
        XCTAssertEqual(
            readers,
            ["App/AppState.swift"],
            "落盘门面的提及点不止一处（实测：\(readers.joined(separator: "、"))）——「同源」要求读盘只有一处"
        )
        print("[HIST-2] 同源 读数：读盘点=\(readers.joined(separator: ",")) 页面读属性=appState.queryHistory 菜单读属性=appState.queryHistory")
    }

    // MARK: - 判据 4：清空 / 单条删除的两处二次确认

    /// 点「清空」/「删除」⇒ **只挂请求**（条数不变、库不动）；取消 ⇒ 不动；确认 ⇒ 才落库。
    ///
    /// 读数两处都给：内存镜像（`AppState.queryHistory`）与**库里真值**（另开一个门面实例读盘）
    /// —— 只看内存会漏掉「界面清空了、库里还在」这一类假绿。
    @MainActor
    func testClearAndDeleteBothWaitForConfirmation() async throws {
        try XCTSkipUnless(UISnapshot.isEnabled, "快照要 DOYAH_UI_SNAPSHOT=1")
        try requireIsolatedNotesDirectory()

        let host = try makeHost()
        host.state.selectActivityItem(.database)

        // 历史与笔记**同库同连接**：门面与 `AppState` 用的是同一个文件（`DOYAH_NOTES_DIR` 指到临时家）。
        let store = QueryHistoryStore(databaseURL: NoteDatabase.defaultFileURL())
        try await store.clear()
        try await seed(store, sqls: ["SELECT 1", "SELECT 2", "SELECT 3"])
        await host.state.loadQueryHistory()
        XCTAssertEqual(host.state.queryHistory.count, 3, "回读镜像应有 3 条")
        let seeded = try await store.load()
        XCTAssertEqual(seeded.count, 3, "库里应有 3 条（夹具没落到临时库？）")
        print("[HIST-2] 夹具：内存 \(host.state.queryHistory.count) 条 / 库 \(seeded.count) 条")

        // 甲：点「清空」⇒ 只挂请求。
        host.state.requestClearQueryHistory()
        let clearRequest = try XCTUnwrap(host.state.pendingHistoryRemoval, "点了「清空」没有挂确认请求")
        XCTAssertEqual(clearRequest.target, .all)
        XCTAssertEqual(
            clearRequest.actions,
            QueryHistoryRemovalPrompt.clearActions,
            "动作与顺序必须来自 Core 的 `QueryHistoryRemovalPrompt`（唯一出处）"
        )
        let clearTitle = host.state.pendingHistoryRemovalTitle
        let clearMessage = host.state.pendingHistoryRemovalMessage
        XCTAssertNotNil(clearTitle, "清空确认框没有标题")
        XCTAssertNotNil(clearMessage, "清空确认框没有正文")
        print(
            "[HIST-2] 甲 清空挂请求：title=\(clearTitle ?? "nil") message=\(clearMessage ?? "nil")"
                + " actions=\(clearRequest.actions.map(\.rawValue).joined(separator: ","))"
        )
        XCTAssertEqual(host.state.queryHistory.count, 3, "未确认 ⇒ 不删（内存）")
        let afterRequest = try await store.load()
        XCTAssertEqual(afterRequest.count, 3, "未确认 ⇒ 不删（库）")

        // 乙：取消 ⇒ 一个字节不动。
        host.state.cancelHistoryRemoval()
        XCTAssertNil(host.state.pendingHistoryRemoval, "取消之后确认请求该被收掉")
        let afterCancel = try await store.load()
        XCTAssertEqual(afterCancel.count, 3, "取消 ⇒ 库一个字节不动")
        print("[HIST-2] 乙 取消后：内存 \(host.state.queryHistory.count) 条 / 库 \(afterCancel.count) 条")

        // 丙：确认 ⇒ 才清空。
        host.state.requestClearQueryHistory()
        await host.state.confirmHistoryRemoval()
        XCTAssertNil(host.state.pendingHistoryRemoval)
        XCTAssertTrue(host.state.queryHistory.isEmpty, "确认后内存该清空")
        let afterClear = try await store.load()
        XCTAssertEqual(afterClear.count, 0, "确认后库该清空")
        print("[HIST-2] 丙 清空确认后：内存 \(host.state.queryHistory.count) 条 / 库 \(afterClear.count) 条")

        // 丁：单条删除 —— 同样是「挂请求 ⇒ 取消不动 / 确认才减 1」。
        try await seed(store, sqls: ["SELECT 10", "SELECT 11", "SELECT 12"])
        await host.state.loadQueryHistory()
        let victim = try XCTUnwrap(host.state.queryHistory.first, "没有可删的那一条")
        host.state.requestDeleteHistory(victim)
        let deleteRequest = try XCTUnwrap(host.state.pendingHistoryRemoval, "点了「删除」没有挂确认请求")
        XCTAssertEqual(deleteRequest.target, .one(victim.id), "删除请求要指向**被点的那一条**")
        XCTAssertEqual(deleteRequest.actions, QueryHistoryRemovalPrompt.deleteActions)
        let deleteTitle = host.state.pendingHistoryRemovalTitle
        let deleteMessage = host.state.pendingHistoryRemovalMessage
        XCTAssertNotNil(deleteTitle, "单条删确认框没有标题")
        XCTAssertNotNil(deleteMessage, "单条删确认框没有正文")
        print(
            "[HIST-2] 丁 单条删挂请求：target=.one title=\(deleteTitle ?? "nil")"
                + " message=\(deleteMessage ?? "nil") actions=\(deleteRequest.actions.map(\.rawValue).joined(separator: ","))"
        )
        let beforeDelete = try await store.load()
        XCTAssertEqual(beforeDelete.count, 3, "未确认 ⇒ 不删（库）")
        XCTAssertEqual(host.state.queryHistory.count, 3, "未确认 ⇒ 不删（内存）")

        await host.state.confirmHistoryRemoval()
        XCTAssertEqual(host.state.queryHistory.count, 2, "确认后内存该少 1 条")
        let afterDelete = try await store.load()
        XCTAssertEqual(afterDelete.count, 2, "确认后库该少 1 条")
        XCTAssertFalse(afterDelete.contains { $0.id == victim.id }, "删掉的必须正是被点的那一条")
        print("[HIST-2] 戊 单条删确认后：内存 \(host.state.queryHistory.count) 条 / 库 \(afterDelete.count) 条")
    }

    // MARK: - 工具

    /// 往临时库播几条历史（**只经由门面**，不自己拼 SQL）。
    private func seed(_ store: QueryHistoryStore, sqls: [String]) async throws {
        for (index, sql) in sqls.enumerated() {
            try await store.append(
                QueryHistory(
                    connectionID: UUID(),
                    sql: sql,
                    duration: Double(index) / 10,
                    succeeded: index % 2 == 0
                )
            )
        }
    }

    /// 「夹具要落盘」的前置：口径与 `NotesLayoutProbeTests` / `UISnapshotPanelsTests` 同一条。
    private func requireIsolatedNotesDirectory() throws {
        try XCTSkipIf(
            (ProcessInfo.processInfo.environment["DOYAH_NOTES_DIR"] ?? "").isEmpty,
            "本用例要往笔记库（历史与笔记同库）写夹具 ⇒ 必须在临时数据家里跑"
                + "（`DOYAH_NOTES_DIR` 没设就跳过）—— 取证脚本 `Scripts/run-manual-verification-probes.sh` 会设它"
        )
    }

    private func read(_ relativePath: String, from root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// `App/` 下的所有 Swift 文件（相对工程根的路径，排序）。
    private func swiftFiles(under directory: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        let root = UISnapshot.packageRoot
        var result: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            result.append(
                url.path.replacingOccurrences(of: root.path + "/", with: "")
            )
        }
        return result.sorted()
    }
}
