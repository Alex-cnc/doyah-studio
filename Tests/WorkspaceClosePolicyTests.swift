import XCTest
@testable import DoyahCore

/// 关闭有未保存改动的页签时的处置（`FR-EDIT-46`）。
///
/// 需求提出者 2026-10-03 原话：「点击关闭时提示必须先保存了才能关闭，这个逻辑有问题，
/// 我的期望：用户点击关闭按钮，发现有修改，弹出确认框让用户选择，是保存关闭还是不修改直接退出」。
final class WorkspaceClosePolicyTests: XCTestCase {

    /// ① 干净页签**不弹框** —— 多一次点击就是多一次打扰。
    func testCleanTabClosesWithoutConfirmation() {
        let plan = WorkspaceClosePolicy.plan(isDirty: false)
        XCTAssertFalse(plan.needsConfirmation, "没有改动就不该弹确认框")
        XCTAssertTrue(plan.actions.isEmpty, "不弹框就没有动作可给")
    }

    /// ② 脏页签**先问**，且动作与顺序固定（保存并关闭在最前 = 默认动作）。
    func testDirtyTabAsksWithTwoBusinessActionsPlusCancel() {
        let plan = WorkspaceClosePolicy.plan(isDirty: true)
        XCTAssertTrue(plan.needsConfirmation)
        XCTAssertEqual(plan.actions, [.saveAndClose, .discardChanges, .cancel])
        // 业务动作恰好两个：保存并关闭 / 不保存直接关闭；取消是退出口，不是第三个业务选择。
        XCTAssertEqual(plan.actions.filter { $0.closesTab }.count, 2)
        XCTAssertEqual(plan.actions.last, .cancel, "退出口排在最后（ESC / 点框外也是它）")
    }

    /// 请求对象要能如实说出「有哪些动作」，界面别自己硬写三个按钮。
    func testRequestOffersThePlannedActions() {
        let request = WorkspaceCloseRequest(id: UUID(), title: "a.js", actions: WorkspaceClosePolicy.confirmActions)
        XCTAssertTrue(request.offers(.saveAndClose))
        XCTAssertTrue(request.offers(.discardChanges))
        XCTAssertTrue(request.offers(.cancel))
        let cleanPlan = WorkspaceCloseRequest(id: UUID(), title: "a.js", actions: WorkspaceClosePolicy.plan(isDirty: false).actions)
        XCTAssertFalse(cleanPlan.offers(.saveAndClose))
    }

    /// ③ 取消 ⇒ 不关（取消就是什么都没发生）。
    func testCancelNeverCloses() {
        XCTAssertTrue(WorkspaceClosePolicy.keepsTab(action: .cancel, saveSucceeded: true))
        XCTAssertTrue(WorkspaceClosePolicy.keepsTab(action: .cancel, saveSucceeded: false))
        XCTAssertFalse(WorkspaceCloseAction.cancel.closesTab)
    }

    /// ④ 「保存并关闭」**保存成功才关**；保存失败 ⇒ 不关（宁可关不掉，也不丢改动）。
    func testSaveAndCloseKeepsTabWhenSaveFails() {
        XCTAssertFalse(WorkspaceClosePolicy.keepsTab(action: .saveAndClose, saveSucceeded: true))
        XCTAssertTrue(WorkspaceClosePolicy.keepsTab(action: .saveAndClose, saveSucceeded: false))
        XCTAssertTrue(WorkspaceCloseAction.saveAndClose.closesTab, "动作本身是「关」，能不能关掉由保存结果决定")
    }

    /// ⑤ 「不保存，直接关闭」与保存结果无关 —— 用户已经明说了不要这份改动。
    func testDiscardClosesRegardlessOfSaveResult() {
        XCTAssertFalse(WorkspaceClosePolicy.keepsTab(action: .discardChanges, saveSucceeded: true))
        XCTAssertFalse(WorkspaceClosePolicy.keepsTab(action: .discardChanges, saveSucceeded: false))
        XCTAssertTrue(WorkspaceCloseAction.discardChanges.closesTab, "这个动作就是「关」，不需要保存结果")
    }

    /// 动作的 rawValue 是稳定的（将来要落盘 / 进日志时不能靠 case 顺序）。
    func testActionRawValuesAreStable() {
        XCTAssertEqual(
            WorkspaceCloseAction.allCases.map(\.rawValue),
            ["saveAndClose", "discardChanges", "cancel"]
        )
    }

    /// ⑥ **界面只许照规则画**（源码判据）：页签条上的关闭按钮走 `requestClose(_:)`（不是直接 `close(_:)`），
    /// 确认框里出现的动作**恰好**是 `WorkspaceClosePolicy.confirmActions` 那三个、一个不多一个不少。
    ///
    /// 为什么只能扫源码：SwiftUI 的 `confirmationDialog` 构建器**必须逐条写出 `Button`**，
    /// 没法把 `[WorkspaceCloseAction]` 铺开渲染 ⇒ 「动作集合只有一处出处」这条不变量在类型层面拦不住
    /// （本工程同族做法 = 谓词 / 归一化的「唯一出处」判据。**判前先剥注释**：注释里写着同一个词
    /// 会让扫描假命中，这个坑已在 `AGENT-SPEC` §9 第 118 / 119 条记过两次）。
    func testTabStripDrawsExactlyThePlannedActions() throws {
        let source = try stripComments(readSource("App/Views/WorkspaceTabStrip.swift"))
        XCTAssertTrue(
            source.contains("tabs.requestClose(tab.id)"),
            "关闭按钮必须走 requestClose（干净页签直接关 / 脏页签先确认），不许直接 close"
        )
        for action in WorkspaceClosePolicy.confirmActions {
            XCTAssertTrue(
                source.contains("resolvePendingClose(.\(action.rawValue))") || source.contains("cancelPendingClose()"),
                "确认框里少了 \(action.rawValue) 这一支"
            )
        }
        // 正好那两处「真的会关」的动作（取消走 cancelPendingClose，不是 resolvePendingClose(.cancel)）。
        XCTAssertEqual(
            occurrences(of: "resolvePendingClose(.saveAndClose)", in: source), 1,
            "`保存并关闭` 只许出现一次")
        XCTAssertEqual(
            occurrences(of: "resolvePendingClose(.discardChanges)", in: source), 1,
            "`不保存，直接关闭` 只许出现一次")
        XCTAssertEqual(
            occurrences(of: "resolvePendingClose(", in: source), 2,
            "确认框里只许有这两个业务动作 —— 多出来的那个就是第二套规则")
        XCTAssertTrue(
            source.contains("cancelPendingClose()"),
            "取消 / ESC / 点框外都要收掉请求且不关页签")
    }

    /// ⑦ **三个选项必须看得见**（2026-10-18 人工点验不过的回归）。
    ///
    /// ⑥ 那条只钉住「动作接上了」—— 于是「动作接过来了、但按钮上没有字」能骗过它：
    /// 关闭确认框在 macOS 上是 NSAlert 面板，按钮**只按标题渲染**；`ToolbarIconButton` 的标题是空串，
    /// 面板上就只剩一个空按钮 ⇒ 人类主人看到「没有选择性、只有一个『好』、关不掉未保存文件」。
    /// 所以这一条判的是**形态**：三支动作的按钮标题必须是三个本地化文案，
    /// 且框里不许出现只给图标的按钮构造器。
    func testConfirmationDialogActionsCarryVisibleTitles() throws {
        let block = try confirmationDialogBlock()
        let problems = closeDialogViolations(in: block)
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "；"))

        // 顺序 = 规则给的顺序（保存并关闭在最前 = 默认动作；取消在最后 = 退出口）。
        let positions = WorkspaceClosePolicy.confirmActions.compactMap { action in
            block.range(of: "Button(L(\(titleKey(for: action))")?.lowerBound
        }
        XCTAssertEqual(positions.count, WorkspaceClosePolicy.confirmActions.count, "三个动作都要有带标题的按钮")
        XCTAssertEqual(positions, positions.sorted(), "确认框按钮顺序必须与 WorkspaceClosePolicy.confirmActions 一致")
    }

    /// ⑦ 的反例自证：把有标题的按钮换成只给图标的（= 2026-10-18 那次的形状）**必须判红**。
    func testIconOnlyCloseActionsAreRejected() throws {
        let block = try confirmationDialogBlock()
        let regressed = block
            .replacingOccurrences(of: "Button(L(.workspaceCloseSaveAndClose))", with: "ToolbarIconButton(systemName: \"square.and.arrow.down\", help: L(.workspaceCloseSaveAndClose))")
        let problems = closeDialogViolations(in: regressed)
        XCTAssertFalse(problems.isEmpty, "只给图标的按钮必须被判红（面板上没有标题 = 没有选项）")
        XCTAssertTrue(problems.contains { $0.contains("ToolbarIconButton") }, "要点名 ToolbarIconButton：\(problems)")
        XCTAssertTrue(problems.contains { $0.contains("workspaceCloseSaveAndClose") }, "要点名缺了哪个选项：\(problems)")
    }

    /// 关掉注释后的「关闭确认框」那一段源码（从 `.confirmationDialog(` 到它的 `} message:`）。
    private func confirmationDialogBlock() throws -> String {
        let source = try readSource("App/Views/WorkspaceTabStrip.swift")
        guard let start = source.range(of: ".confirmationDialog(") else {
            XCTFail("页签条上找不到关闭确认框")
            return ""
        }
        guard let end = source.range(of: "} message:", range: start.upperBound..<source.endIndex) else {
            XCTFail("确认框缺少 message 段 —— 找不到边界")
            return ""
        }
        return String(source[start.lowerBound..<end.upperBound])
    }

    /// 三个动作各自的文案键（**顺序 = `WorkspaceClosePolicy.confirmActions`**）。
    private func titleKey(for action: WorkspaceCloseAction) -> String {
        switch action {
        case .saveAndClose: return ".workspaceCloseSaveAndClose"
        case .discardChanges: return ".workspaceCloseDiscardChanges"
        case .cancel: return ".workspaceCloseCancel"
        }
    }

    /// 一段「关闭确认框」源码里有什么问题（空数组 = 三个选项都看得见）。
    /// **判据与反例跑同一份逻辑** —— 反例才证明得了这条判据没瞎。
    private func closeDialogViolations(in block: String) -> [String] {
        let code = stripComments(block)
        var problems: [String] = []
        if code.contains("ToolbarIconButton(") {
            problems.append("确认框里用了只给图标的 ToolbarIconButton —— macOS 的面板只按标题渲染，图标没有标题 ⇒ 框里只剩一个空按钮")
        }
        for action in WorkspaceClosePolicy.confirmActions {
            let key = titleKey(for: action)
            if !code.contains("Button(L(\(key))") {
                problems.append("确认框里缺一支带标题的按钮：Button(L(\(key)))（\(action.rawValue)）")
            }
        }
        return problems
    }

    // MARK: 源码判据的小工具

    /// 读仓内文件（`Tests/…` 的上一级 = 仓根）。
    private func readSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // 仓根
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// 剥掉 `//` 行注释与 `///` 文档注释（判据要判的是**代码**，不是散文）。
    private func stripComments(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let range = line.range(of: "//") else { return line }
                return line[line.startIndex..<range.lowerBound]
            }
            .joined(separator: "\n")
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var search = haystack[...]
        while let range = search.range(of: needle) {
            count += 1
            search = search[range.upperBound...]
        }
        return count
    }
}
