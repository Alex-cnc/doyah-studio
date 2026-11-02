import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 编辑区 AI 辅助的**行为判据**（`FR-STD-WS-AI-001`）—— 队列 `L-90` 那一套（零权限、自渲染）。
///
/// 为什么 Core 单测不够：Core 判的是「该不该发 / 发什么 / 结果怎么解析」，
/// 判不住这四件事在真界面上是不是这么发生的 ——
///
///   ① **闸门在发请求之前**：端点没配时点「发送」一个字节都不许出去（契约 ②）；
///   ② **说得出模型与端点**：面板上那两行读的是真配置（不是写死的占位）；
///   ③ **不许静默改文件**：只有点了「应用」才落笔，且**落笔走的是可撤销那条路**（契约 ①）；
///   ④ **解释只需文字**：`answer` 态下「应用」不产生任何文件改动。
///
/// 跑法：`env DOYAH_UI_SNAPSHOT=1 swift test --filter EditAssistProbeTests`
final class EditAssistProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    private func makeContext(text: String = "let a = 1\n",
                             selection: NSRange = NSRange(location: 8, length: 1)) -> EditAssist.Context {
        EditAssist.Context(fileName: "Demo.swift", language: .plainText,
                           fileText: text, selection: selection)
    }

    // MARK: - ① 闸门在发请求之前

    @MainActor
    func testGateRefusesBeforeAnyRequest() async throws {
        let model = EditAssistModel()
        var calls = 0
        model.runner = { _ in
            calls += 1
            return LLMResponse(text: "不该被调用")
        }
        model.open(action: .explain, context: makeContext(), endpoint: "", model: "m")
        XCTAssertEqual(model.phase, .refused(.endpointNotConfigured), "端点没配就必须当场说未配置")
        XCTAssertFalse(model.canSend, "「发送」在这一态下不可点")
        model.send()
        XCTAssertEqual(calls, 0, "端点没配却发了请求 —— 契约 ② 破在发请求前那一关")
    }

    /// 端点有了、模型没填 ⇒ 说的是「模型名没配」，不是笼统的「连不上」。
    @MainActor
    func testMissingModelIsDistinguishedFromUnreachable() {
        let model = EditAssistModel()
        model.open(action: .explain, context: makeContext(), endpoint: "http://127.0.0.1:11434/v1", model: "")
        XCTAssertEqual(model.phase, .refused(.modelNotConfigured))
    }

    // MARK: - ② 面板说得出模型与端点

    @MainActor
    func testPanelCarriesRealModelAndEndpoint() {
        let model = EditAssistModel()
        model.open(action: .explain, context: makeContext(),
                   endpoint: "http://127.0.0.1:11434/v1", model: "qwen2.5-coder")
        XCTAssertEqual(model.modelName, "qwen2.5-coder")
        XCTAssertEqual(model.endpointName, "http://127.0.0.1:11434/v1")
        XCTAssertTrue(model.isPresented)

        // 界面那一半：面板视图必须把这两行读出来（源锚点 —— 不是写死的占位串）。
        let source = try! String(contentsOfFile: #filePath
            .replacingOccurrences(of: "TestsUISnapshot/EditAssistProbeTests.swift", with: "")
            + "App/Views/EditAssistSheet.swift", encoding: .utf8)
        XCTAssertTrue(source.contains("editAssistModelLine"), "面板没有「模型：」那一行")
        XCTAssertTrue(source.contains("editAssistEndpointLine"), "面板没有「端点：」那一行")
        XCTAssertTrue(source.contains("model.modelName"), "那一行必须读真配置，不许写死")
        XCTAssertTrue(source.contains("model.endpointName"))
    }

    // MARK: - ③ 点了「应用」才落笔，且可撤销

    private struct Harness: View {
        let tabID: UUID
        let text: String
        let delivery: WorkspaceTabsModel.AssistDelivery?
        var body: some View {
            CodeEditorView(
                tabID: tabID,
                text: text,
                language: .plainText,
                pendingAssist: delivery,
                onTextChange: { _ in },
                onSave: {},
                onFormat: {}
            )
        }
    }

    @MainActor
    func testApplyLandsThroughTheUndoableEditPath() throws {
        let tabID = UUID()
        let original = "let a = 1\n"
        let proposal = EditAssist.Proposal(
            action: .rewrite,
            range: NSRange(location: 8, length: 1),
            original: "1",
            replacement: "42",
            diff: AgentTextDiff.lines(before: "1", after: "42")
        )
        let delivery = WorkspaceTabsModel.AssistDelivery(
            id: UUID(), tabID: tabID, range: proposal.range, replacement: proposal.replacement,
            caret: proposal.range.location + (proposal.replacement as NSString).length
        )
        let host = UISnapshot.LiveHost(
            Harness(tabID: tabID, text: original, delivery: delivery),
            size: CGSize(width: 640, height: 240)
        )
        host.pump(0.5)
        let textView = try XCTUnwrap(
            UISnapshot.LiveHost<Harness>.findViews(ofType: CodeTextView.self, in: host.hosting).first
        )
        XCTAssertEqual(textView.string, "let a = 42\n", "投递之后编辑器里应是应用过的正文")
        XCTAssertEqual(textView.selectedRange().location, 10, "落点应在替换之后")

        // 「可撤销」这一半：**离屏宿主量不出 `NSTextView.undoManager`**（它由窗口给，这里恒为 nil），
        // 所以按本仓既有做法判两件可测的事 ——
        // ① 落笔**走的是那条唯一可撤销的编辑路径**（源锚点：`applyEditPlan(range:replacement:caret:kind:)`）；
        // ② 这一步在 Core 里是**原子步且有自己的撤销名**（`EditAssistTests.testAssistHasItsOwnUndoStep`）。
        // 只判①会放过「应用了但绕开撤销栈」；只判②会放过「策略对、编辑器没走那条路」。
        let editorSource = try String(contentsOfFile: #filePath
            .replacingOccurrences(of: "TestsUISnapshot/EditAssistProbeTests.swift", with: "")
            + "App/Views/CodeEditorView.swift", encoding: .utf8)
        XCTAssertTrue(editorSource.contains("replacement: assist.replacement"),
                      "应用投递没有交给编辑器的落笔入口")
        XCTAssertTrue(editorSource.contains("kind: .assist"),
                      "应用投递没有带上 `.assist` 这个撤销步 —— 等于绕开撤销栈")
        XCTAssertTrue(editorSource.contains("applyEditPlan(range: assist.range"),
                      "应用投递必须走 `applyEditPlan`（唯一注册撤销的落笔点）")
    }

    /// 同一内容不变时不许把用户后来手改的东西顶掉：同一条投递只应用一次。
    @MainActor
    func testSameDeliveryAppliesOnlyOnce() throws {
        let tabID = UUID()
        let proposal = EditAssist.Proposal(
            action: .rewrite, range: NSRange(location: 0, length: 3), original: "abc",
            replacement: "xyz", diff: AgentTextDiff.lines(before: "abc", after: "xyz")
        )
        let delivery = WorkspaceTabsModel.AssistDelivery(
            id: UUID(), tabID: tabID, range: proposal.range, replacement: proposal.replacement, caret: 3
        )
        let host = UISnapshot.LiveHost(
            Harness(tabID: tabID, text: "abc", delivery: delivery),
            size: CGSize(width: 640, height: 240)
        )
        host.pump(0.6)
        let textView = try XCTUnwrap(
            UISnapshot.LiveHost<Harness>.findViews(ofType: CodeTextView.self, in: host.hosting).first
        )
        XCTAssertEqual(textView.string, "xyz")
        // 用户接着自己改：再跑一轮布局（同一份投递）不许把他的手改撤掉。
        textView.insertText("!", replacementRange: NSRange(location: 3, length: 0))
        host.pump(0.3)
        XCTAssertEqual(textView.string, "xyz!", "同一条投递被重复应用 = 用户的手改被顶掉")
    }

    // MARK: - ⑤ 契约 ③ 第三档：拨到「不发送」⇒ 一次请求都不发

    @MainActor
    func testNoSendBoundaryNeverCallsTheRunner() {
        let model = EditAssistModel()
        var calls = 0
        model.runner = { _ in
            calls += 1
            return LLMResponse(text: "不该被调用")
        }
        model.open(action: .explain, context: makeContext(),
                   endpoint: "http://127.0.0.1:11434/v1", model: "qwen2.5-coder")
        XCTAssertTrue(model.canSend, "端点是好的，这一档本身可发")

        model.boundary = .none
        XCTAssertEqual(model.outboundSummary?.scope, EditAssist.Boundary.none)
        XCTAssertFalse(model.canSend, "拨到「不发送」之后「发送」必须点不动")
        model.send()
        XCTAssertEqual(calls, 0, "「不发送」档却发了请求 —— 契约 ③ 破在发请求前那一关")
        XCTAssertEqual(model.phase, .refused(.notSending))

        // 界面那一半：三档都在选择器里（枚举驱动，不是手写两档）。
        let source = try! String(contentsOfFile: #filePath
            .replacingOccurrences(of: "TestsUISnapshot/EditAssistProbeTests.swift", with: "")
            + "App/Views/EditAssistSheet.swift", encoding: .utf8)
        XCTAssertTrue(source.contains("EditAssist.Boundary.allCases"),
                      "面板的边界选择器必须由 `Boundary.allCases` 出档位，否则加了第三档界面上也看不见")
    }

    // MARK: - ⑥ 契约 ②：连不上就如实说「连不上」（不许假装在跑）

    private struct ConnectionRefused: LocalizedError {
        var errorDescription: String? { "connect ECONNREFUSED 127.0.0.1:11434" }
    }

    @MainActor
    func testUnreachableSaysSoInsteadOfPretending() throws {
        let model = EditAssistModel()
        var applied = 0
        model.apply = { _ in applied += 1 }
        model.runner = { _ in throw ConnectionRefused() }
        model.open(action: .explain, context: makeContext(),
                   endpoint: "http://127.0.0.1:11434/v1", model: "qwen2.5-coder")
        model.send()

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if case .sending = model.phase { hostPumpOnce() } else { break }
        }
        guard case .refused(.unreachable(let detail)) = model.phase else {
            return XCTFail("连不上时界面应当说「连不上」，实测 = \(model.phase)")
        }
        XCTAssertTrue(detail.contains("ECONNREFUSED"), "原因被吃掉了，界面只剩一句笼统的话")
        XCTAssertFalse(model.canApply, "没有产出时不许出现「应用」")
        XCTAssertEqual(applied, 0)
    }

    // MARK: - ⑦ 契约 ①：应用之后 ⌘Z 能逐字回到原文

    private struct TabsHarness: View {
        @ObservedObject var tabs: WorkspaceTabsModel
        let tabID: UUID
        var body: some View {
            CodeEditorView(
                tabID: tabID,
                text: tabs.tabs.first(where: { $0.id == tabID })?.content ?? "",
                language: tabs.tabs.first(where: { $0.id == tabID })?.language ?? .plainText,
                pendingAssist: tabs.assistDelivery,
                onTextChange: { tabs.updateContent($0, for: tabID) },
                onSave: {},
                onFormat: {}
            )
        }
    }

    /// 与 `FR-STD-WS-NAV-014` ② 同一口径：真 `CodeTextView` + 真 `undoManager`，
    /// 量「应用 → 一次撤销 → 视图与模型正文都逐字等于原文」。
    /// 只判源锚点会放过「应用了但绕开撤销栈」，只判 Core 会放过「策略对、编辑器没走那条路」。
    @MainActor
    func testApplyingAssistIsUndoableBackToTheExactOriginal() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("assist-undo-\\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Demo.swift")
        let original = "let a = 1\n"
        try original.write(to: file, atomically: true, encoding: .utf8)

        let tabs = WorkspaceTabsModel()
        tabs.openFile(at: file)
        guard let tab = tabs.tabs.first(where: { !$0.isHome }) else {
            return XCTFail("文件没开成页签")
        }
        tabs.select(tab.id)

        let host = UISnapshot.LiveHost(TabsHarness(tabs: tabs, tabID: tab.id),
                                       size: CGSize(width: 640, height: 240))
        host.pump(0.4)
        let textView = try XCTUnwrap(
            UISnapshot.LiveHost<TabsHarness>.findViews(ofType: CodeTextView.self, in: host.hosting).first,
            "真编辑器不在宿主视图树里 —— 判据的入口没了"
        )
        XCTAssertEqual(textView.string, original)

        let proposal = EditAssist.Proposal(
            action: .rewrite, range: NSRange(location: 8, length: 1), original: "1",
            replacement: "42", diff: AgentTextDiff.lines(before: "1", after: "42")
        )
        tabs.deliverAssist(proposal, for: tab.id)
        host.pump(0.6)
        XCTAssertEqual(textView.string, "let a = 42\n", "点了「应用」之后编辑器里没变")
        XCTAssertEqual(tabs.tabs.first(where: { $0.id == tab.id })?.content, "let a = 42\n")

        guard let undoManager = textView.undoManager else {
            return XCTFail("编辑器没有撤销管理器 ⇒ 「可撤销」这条判据无从成立（不是通过）")
        }
        XCTAssertTrue(undoManager.canUndo, "应用 AI 产出没有进撤销栈 ⇒ ⌘Z 拿不回来")
        undoManager.undo()
        host.pump(0.3)
        XCTAssertEqual(textView.string, original, "撤销之后与原文不逐字一致")
        XCTAssertEqual(tabs.tabs.first(where: { $0.id == tab.id })?.content, original,
                       "模型里的正文没有跟着撤销回来（下一次保存会把 AI 改动写回磁盘）")
    }

    // MARK: - ④ 解释只出文字，没有可应用的东西

    @MainActor
    func testAnswerPhaseHasNothingToApply() throws {
        let model = EditAssistModel()
        var applied = 0
        model.apply = { _ in applied += 1 }
        model.runner = { _ in LLMResponse(text: "这段代码把 a 设为 1。") }
        model.open(action: .explain, context: makeContext(),
                   endpoint: "http://127.0.0.1:11434/v1", model: "m")
        model.send()
        // 等这一跳的 Task 落定（Runner 是同步返回的假实现）。
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, model.phase == .sending { hostPumpOnce() }
        XCTAssertEqual(model.phase, .answer("这段代码把 a 设为 1。"))
        XCTAssertFalse(model.canApply, "解释没有可应用的改动")
        model.applyProposal()
        XCTAssertEqual(applied, 0, "answer 态下「应用」不许改文件（契约 ①）")
    }

    /// 让主线程跑一小段 runloop（上面那个 Task 需要它才落地）。
    @MainActor
    private func hostPumpOnce() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
}
