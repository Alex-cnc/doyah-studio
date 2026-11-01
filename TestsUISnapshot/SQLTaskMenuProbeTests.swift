import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 工具栏「任务」菜单的 **App 侧探针**（`FR-STD-DB-TASK-001`）—— B1 批次第二片。
///
/// ## 这一行为什么停在 🟡（台账备注原文「差人工点一次」）
///
/// 核盘之后要分开说三件事：
///   · 定义实体 / 存盘 / 执行前逐项核对（`SQLTaskGuard`）早有 21 例判据 —— 那是**语义**那一面；
///   · 但菜单里**有哪些行、点了之后发生什么**此前只写在 `QueryToolbar.taskMenu` 那段
///     SwiftUI `Menu` 的闭包里：离屏宿主里 SwiftUI 菜单不落任何可点的 AppKit 控件
///     （同 `PanelIconButton` 文件头记的实测），于是「点载入真的切了库没有」「点解绑真的解了没有」
///     一次都没人量过；
///   · 用户拿到的就是这个菜单 —— 菜单点不动，Core 的 21 例照样全绿。
///
/// ## 这一片怎么量
///
/// ① 菜单内容收成 `Core/SQLTaskMenuPlan`（纯值），② 铺设收成 `SQLTaskAppKitMenu.build`
/// （真 `NSMenu`，行是真 `ClosureMenuItem`），③ 动作接线收成 `SQLTaskAppKitMenu.actions`
/// —— 工具栏与探针**读同一处**。
///
/// 探针拿到的是**用户点开的那一份菜单**：按文案认行，再 `performActionForItem(at:)`
/// 让它走行自己的 `target/action`（不是把实现里的闭包自己调一遍）。判据读的是
/// `AppState` 里的**状态**（页签语句 / 选中库 / 选中连接 / 绑定）与回调次数，不是截图。
///
/// ## 边界（如实登记，别把这条读成「全点过了」）
///
/// · **不真弹菜单**：`NSMenu.popUp` 是模态的（跑跟踪循环直到用户放掉鼠标），无人值守的机器上
///   弹出来就再也回不来。所以「点按钮 → 菜单出现在哪」这一跳由人承担；菜单**里面**的每一行
///   由本文件按行自己的 action 派发，与用户点它走的是同一条路径。
/// · **「保存」之后那张表单没填**：`SQLTaskSaveSheet` 的字段与保存落盘由
///   `Tests/SQLTaskDefinitionTests` 21 例判（同名拒 / 原地改 / 定义不完整一次列全）；
///   本文件只判「点这一项 → 窗口层收到一次要立表单的请求」。
/// · **删除走的是异步**（`Task { await appState.deleteSQLTask }`），本文件等它落地再判；
///   落盘本身要写 `sql-tasks.json`，所以这一条在**临时目录**里跑（不碰用户的真账）。
final class SQLTaskMenuProbeTests: XCTestCase {

    // MARK: - 夹具

    /// 一条任务定义（`sql` 与目标库都写死，方便判「载入之后页签变成了什么」）。
    private func task(
        id: UUID = UUID(),
        name: String,
        sql: String,
        database: String,
        accessMode: SQLTaskDefinition.AccessMode = .readOnly,
        rowLimit: Int? = nil,
        connectionID: UUID? = nil,
        connectionName: String? = nil
    ) -> SQLTaskDefinition {
        SQLTaskDefinition(
            id: id,
            name: name,
            sql: sql,
            connectionID: connectionID,
            connectionName: connectionName,
            targetDatabase: database,
            accessMode: accessMode,
            rowLimit: rowLimit,
            requiresApproval: true
        )
    }

    /// 一个页签 + 一个空册子的状态（`sqlTasks` 由各用例自己塞）。
    @MainActor
    private func stateWithTab(sql: String = "select 1") throws -> (AppState, UUID) {
        let state = AppState()
        state.connections = []
        state.selectedConnectionID = nil
        state.newQueryTab()
        let tabID = try XCTUnwrap(state.tabs.last?.id, "建不出查询页签 —— 夹具坏了")
        if let index = state.tabs.firstIndex(where: { $0.id == tabID }) {
            state.tabs[index].sql = sql
        }
        return (state, tabID)
    }

    /// 生产那一份菜单（`AppState` + 页签 id → 与工具栏同一个入口）。
    @MainActor
    private func makeMenu(
        state: AppState,
        tabID: UUID,
        onSave: @escaping () -> Void = {}
    ) -> NSMenu {
        let plan = SQLTaskMenuPlan.make(
            tasks: state.sqlTasks,
            tabSQL: state.tabs.first(where: { $0.id == tabID })?.sql ?? "",
            boundTaskID: state.boundSQLTaskIDs[tabID]
        )
        return SQLTaskAppKitMenu.build(
            plan: plan,
            actions: SQLTaskAppKitMenu.actions(appState: state, tabID: tabID, onSave: onSave)
        )
    }

    /// 按文案认行（文案来自 Core 的 `Row.label`，不写死字面量）。
    private func item(_ menu: NSMenu, titled title: String) -> NSMenuItem? {
        menu.items.first { $0.title == title }
    }

    /// 点一行 —— 走的是行自己的 `target/action`（用户点它时 AppKit 派发的就是这一条），
    /// 但不跑菜单的跟踪循环（那是模态的：无人值守的机器上弹出来就回不来）。
    @discardableResult
    private func click(_ item: NSMenuItem, in menu: NSMenu) throws -> Bool {
        _ = NSApplication.shared // 保证有 NSApp（`sendAction` 要它）
        XCTAssertFalse(item.isSeparatorItem, "认到了一根分隔线")
        if !item.isEnabled { return false }
        guard let action = item.action else {
            XCTFail("「\(item.title)」这一行没有 action —— 点了什么都不会发生")
            return false
        }
        return NSApplication.shared.sendAction(action, to: item.target, from: item)
    }

    // MARK: - ① 每一行写清「名字 · 库 · 模式 · 上限」

    @MainActor
    func testEachRowCarriesNameDatabaseModeAndLimit() throws {
        let (state, tabID) = try stateWithTab()
        let readOnly = task(name: "日报", sql: "select * from daily", database: "analytics", rowLimit: 500)
        let writable = task(name: "修数据", sql: "update orders set note='x'", database: "shop", accessMode: .writable)
        state.sqlTasks = [readOnly, writable]

        let menu = makeMenu(state: state, tabID: tabID)
        let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)

        let readOnlyLabel = SQLTaskMenuPlan.Row(
            id: readOnly.id, name: readOnly.name, targetDatabase: readOnly.targetDatabase,
            accessMode: readOnly.accessMode, rowLimit: readOnly.rowLimit
        ).label(readOnlyText: L(.sqlTaskModeReadOnly), writableText: L(.sqlTaskModeWritable))
        let writableLabel = SQLTaskMenuPlan.Row(
            id: writable.id, name: writable.name, targetDatabase: writable.targetDatabase,
            accessMode: writable.accessMode, rowLimit: writable.rowLimit
        ).label(readOnlyText: L(.sqlTaskModeReadOnly), writableText: L(.sqlTaskModeWritable))

        XCTAssertTrue(titles.contains(readOnlyLabel), "菜单里没有「\(readOnlyLabel)」这一行，实际：\(titles)")
        XCTAssertTrue(titles.contains(writableLabel), "菜单里没有「\(writableLabel)」这一行，实际：\(titles)")
        // 四段都在：只写名字的话，同名不同库的两条定义在菜单里长得一模一样。
        XCTAssertTrue(readOnlyLabel.contains("analytics") && readOnlyLabel.contains("500"),
                      "只读那条没把库或上限写出来：\(readOnlyLabel)")
        XCTAssertTrue(writableLabel.contains("shop") && writableLabel.contains(L(.sqlTaskModeWritable)),
                      "可写那条没把库或模式写出来：\(writableLabel)")

        // 顺序 = 册子顺序（`AppState.sqlTasks` 已按最近改过倒序）。
        XCTAssertLessThan(
            try XCTUnwrap(titles.firstIndex(of: readOnlyLabel)),
            try XCTUnwrap(titles.firstIndex(of: writableLabel)),
            "菜单行序与册子序不一致"
        )

        // 删除子菜单里一行一条，用的是**名字**不是整段标签（子菜单本身就是「删」，不必再讲库）。
        let deleteItem = try XCTUnwrap(titles.contains(L(.commonDelete)) ? item(menu, titled: L(.commonDelete)) : nil,
                                       "菜单里没有「\(L(.commonDelete))」这一项")
        let submenu = try XCTUnwrap(deleteItem.submenu, "删除那一项没有子菜单 —— 点它等于什么都没有")
        XCTAssertEqual(submenu.items.map(\.title), [readOnly.name, writable.name], "删除子菜单与册子对不上")
        print("🧪 菜单行：\(titles)")
    }

    // MARK: - ② 空册子给一句人话；「保存」跟着页签里有没有语句走

    @MainActor
    func testEmptyBookExplainsItselfAndSaveFollowsTheScript() throws {
        let (state, tabID) = try stateWithTab(sql: "   \n  ")
        state.sqlTasks = []

        let emptyMenu = makeMenu(state: state, tabID: tabID)
        let save = try XCTUnwrap(item(emptyMenu, titled: L(.sqlTaskSaveAction)), "菜单里没有「保存」这一项")
        XCTAssertFalse(save.isEnabled, "空白脚本时「保存」还能点 —— 存下去就是一条永远只能被拒的定义")

        let empty = try XCTUnwrap(item(emptyMenu, titled: L(.sqlTaskListEmpty)),
                                  "册子空时菜单里一句话都没有（一条空菜单比一句「还没有保存过任务」更让人困惑）")
        XCTAssertFalse(empty.isEnabled, "空态那句是灰的（它只是说明，不是一项操作）")

        // 有语句之后同一项就点得动了 —— 判据跟着**输入**变，不是常量。
        if let index = state.tabs.firstIndex(where: { $0.id == tabID }) {
            state.tabs[index].sql = "select 1"
        }
        let filled = makeMenu(state: state, tabID: tabID)
        XCTAssertTrue(try XCTUnwrap(item(filled, titled: L(.sqlTaskSaveAction))).isEnabled,
                      "有语句时「保存」还是灰的 —— 入口等于不存在")

        // 点一下：「保存」只负责把窗口层叫起来一次（表单本身归 SQLTaskSaveSheet）。
        var saveRequests = 0
        let clickable = makeMenu(state: state, tabID: tabID, onSave: { saveRequests += 1 })
        XCTAssertTrue(try click(try XCTUnwrap(item(clickable, titled: L(.sqlTaskSaveAction))), in: clickable),
                      "「保存」那一行点不动（action 没派发出去）")
        XCTAssertEqual(saveRequests, 1, "点「保存」没有把表单叫起来（或叫了 \(saveRequests) 次）")

        // 灰着的那一项点了什么都不该发生（AppKit 会在菜单项这一层就拦下）。
        var refusedRequests = 0
        if let index = state.tabs.firstIndex(where: { $0.id == tabID }) {
            state.tabs[index].sql = ""
        }
        let disabled = makeMenu(state: state, tabID: tabID, onSave: { refusedRequests += 1 })
        let disabledSave = try XCTUnwrap(item(disabled, titled: L(.sqlTaskSaveAction)))
        XCTAssertFalse(try click(disabledSave, in: disabled), "灰着的「保存」居然被点动了")
        XCTAssertEqual(refusedRequests, 0, "灰着的「保存」被点开了表单 —— 空脚本能存成任务")
        print("🧪 保存那一项：空白脚本 \(save.isEnabled ? "可点" : "灰") / 有语句 \(filled.items.first { $0.title == L(.sqlTaskSaveAction) }?.isEnabled == true ? "可点" : "灰")")
    }

    // MARK: - ③ 点「载入」：语句进页签、库与连接切过去、页签绑上

    @MainActor
    func testClickingLoadBringsScriptConnectionDatabaseAndBinding() throws {
        let connection = ConnectionConfig(name: "本机测试库", database: "other")
        let (state, tabID) = try stateWithTab(sql: "select 0")
        state.connections = [connection]
        state.selectedConnectionID = nil
        state.selectedDatabase = "before"
        let target = task(
            name: "月结",
            sql: "select count(*) from orders",
            database: "shop",
            accessMode: .writable,
            rowLimit: 100,
            connectionID: connection.id,
            connectionName: connection.name
        )
        state.sqlTasks = [target]

        let menu = makeMenu(state: state, tabID: tabID)
        let row = try XCTUnwrap(menu.items.first { $0.title.contains(target.name) }, "菜单里找不到那条任务")
        XCTAssertTrue(try click(row, in: menu), "「\(row.title)」点不动")

        XCTAssertEqual(state.tabs.first { $0.id == tabID }?.sql, target.sql,
                       "点载入没把语句送进页签")
        XCTAssertEqual(state.selectedDatabase, target.targetDatabase, "点载入没把库切到定义那一对")
        XCTAssertEqual(state.selectedConnectionID, connection.id, "点载入没把连接切到定义那一个")
        XCTAssertEqual(state.boundSQLTaskIDs[tabID], target.id, "载入之后页签没绑上这条定义")
        XCTAssertEqual(state.boundSQLTask(for: tabID)?.name, target.name, "绑上了但读不出来（绑定指向了别处）")
        print("🧪 载入读数：库 \(state.selectedDatabase ?? "nil") / 绑 \(state.boundSQLTask(for: tabID)?.name ?? "nil")")
    }

    // MARK: - ④ 点「解除绑定」：页签松开，册子里那条还在

    @MainActor
    func testClickingUnbindReleasesTheTabAndKeepsTheTask() throws {
        let (state, tabID) = try stateWithTab()
        let bound = task(name: "月结", sql: "select 1", database: "shop")
        state.sqlTasks = [bound]
        state.boundSQLTaskIDs[tabID] = bound.id

        let menu = makeMenu(state: state, tabID: tabID)
        let titles = menu.items.map(\.title)
        XCTAssertTrue(titles.contains(L(.sqlTaskBoundTo, bound.name)),
                      "绑着的时候菜单没写「本页签绑定任务：…」，实际：\(titles)")

        XCTAssertTrue(try click(try XCTUnwrap(item(menu, titled: L(.sqlTaskUnbind))), in: menu), "「解绑」点不动")
        XCTAssertNil(state.boundSQLTaskIDs[tabID], "点了解除绑定，页签还绑着")
        XCTAssertEqual(state.sqlTasks.count, 1, "解除绑定把任务本身也删了（那是两件事）")

        // 解开之后菜单里不该再出现「本页签绑定任务」那一行。
        let after = makeMenu(state: state, tabID: tabID)
        XCTAssertFalse(after.items.map(\.title).contains(L(.sqlTaskBoundTo, bound.name)),
                       "解绑之后菜单还写着绑定关系")
        print("🧪 解绑读数：绑定 \(state.boundSQLTaskIDs[tabID] == nil ? "已清" : "还在") / 册子 \(state.sqlTasks.count) 条")
    }

    // MARK: - ⑤ 点删除子菜单那一项：册子里真的少一条（落盘在临时目录）

    @MainActor
    func testClickingDeleteRemovesExactlyThatTask() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sql-task-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SQLTaskStore(directoryURL: directory)
        let doomed = task(name: "待删", sql: "select 1", database: "shop")
        let keeps = task(name: "留下", sql: "select 2", database: "shop")
        _ = try await store.save(doomed)
        _ = try await store.save(keeps)

        let (state, tabID) = try stateWithTab()
        state.sqlTaskStoreOverride = store
        state.sqlTasks = try await store.tasks()

        let menu = makeMenu(state: state, tabID: tabID)
        let deleteItem = try XCTUnwrap(item(menu, titled: L(.commonDelete)), "菜单里没有删除那一项")
        let submenu = try XCTUnwrap(deleteItem.submenu, "删除那一项没有子菜单")
        let target = try XCTUnwrap(submenu.items.first { $0.title == doomed.name }, "删除子菜单里找不到那条任务")
        let index = try XCTUnwrap(submenu.items.firstIndex(of: target))
        XCTAssertTrue(try click(target, in: submenu), "删除子菜单那一项点不动")

        // 删除是 `Task { … }`，等它写完盘再判（限时轮询，不靠一次 sleep 猜）。
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, state.sqlTasks.count > 1 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(state.sqlTasks.map(\.name), [keeps.name], "点删除没有把那一行从册子里去掉")
        let onDisk = try await store.tasks().map(\.name).sorted()
        XCTAssertEqual(onDisk, [keeps.name].sorted(), "册子里没了但盘上还在 —— 下次启动它会回来")
        print("🧪 删除读数：盘上 \(onDisk)")
    }

    // MARK: - ⑥ 工具栏用的就是这一份（源锚点）

    /// 源树判据：菜单内容与铺设只许有一处，工具栏不许再自己写一套。
    ///
    /// 盯三件事：① 工具栏调 `SQLTaskMenuPlan.make` 与 `SQLTaskAppKitMenu.build`；
    /// ② 工具栏里**不再**有那段 SwiftUI `Menu { … } label: { toolbarIcon("checklist") }`
    /// （有的话就说明「能点的那份」和「写着的那份」又分家了）；③ 动作接线只有一处
    /// （`SQLTaskAppKitMenu.actions`），工具栏不许自己拼 `Actions`。
    func testToolbarUsesTheSameMenuBuilder() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let toolbar = try String(
            contentsOf: root.appendingPathComponent("App/Views/QueryToolbar.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(toolbar.contains("SQLTaskMenuPlan.make("), "工具栏没走 Core 那份菜单判定")
        XCTAssertTrue(toolbar.contains("SQLTaskAppKitMenu.build("), "工具栏没走 AppKit 那份铺设")
        XCTAssertTrue(toolbar.contains("SQLTaskAppKitMenu.actions("), "工具栏自己拼了一份动作接线")
        XCTAssertFalse(toolbar.contains("menuStyle(.borderlessButton)\n        .menuIndicator(.hidden)\n        .fixedSize()\n        .help(L(.sqlTaskMenuHelp))"),
                       "工具栏里还留着那一段 SwiftUI `Menu` —— 用户点不到的那一份又回来了")

        let menuFile = try String(
            contentsOf: root.appendingPathComponent("App/Views/SQLTaskAppKitMenu.swift"),
            encoding: .utf8
        )
        // 菜单内容不许在 AppKit 那层再判一遍（第二个真相）：`build` 那段里一个 `appState` 都不该出现，
        // 册子里有什么、哪一项能不能点，全部由传进来的 `SQLTaskMenuPlan` 说。
        let buildStart = try XCTUnwrap(menuFile.range(of: "static func build(plan:"))
        let buildEnd = try XCTUnwrap(
            menuFile.range(of: "/// 工具栏上那枚", range: buildStart.upperBound..<menuFile.endIndex)
        )
        let buildBody = String(menuFile[buildStart.lowerBound..<buildEnd.lowerBound])
        XCTAssertFalse(buildBody.contains("appState"), "AppKit 铺设那段里在直接读 AppState —— 内容判定分了两处")
    }
}
