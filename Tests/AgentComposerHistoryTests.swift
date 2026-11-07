import XCTest
import AppKit
@testable import DoyahCore
@testable import DoyahStudioApp

/// 对话输入框的 shell 式历史导航（详设 §3.35）。
///
/// 六条判据各对应一条契约，**每条都带一条反例**（写在这一段注释里，判据本身断言正例）：
/// ① 回填顺序（发 A、发 B ⇒ ↑ B、↑ A、↓ B、↓ 草稿）；反例：↑ 从最旧开始 ⇒ 判红。
/// ② 草稿保真（「草稿文字」↑ 再 ↓ ⇒ 原样回来）；反例：回来是空 ⇒ 判红。
/// ③ 不抢光标（多行第二行行中 ↑ ⇒ 文字不变、光标上移一行）；反例：文字被换成历史 ⇒ 判红。
/// ④ 回填不发送（↑ 之后 `onSubmit` / `makeLoop` 计数必须是 0）；反例：计数 1 ⇒ 判红。
/// ⑤ 持久化（写两条 → 新 store 载入仍在；A、A、B ⇒ A、B；超 200 挤掉最旧）。
/// ⑥ 边界（最旧再 ↑ 不变；草稿态再 ↓ 不变）。
@MainActor
final class AgentComposerHistoryTests: XCTestCase {

    // MARK: - 小工具

    private func tempStore(_ label: String = "history") -> AgentInputHistoryStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("doyah-composer-\(label)-\(UUID().uuidString)", isDirectory: true)
        return AgentInputHistoryStore(fileURL: dir.appendingPathComponent("agent-input-history.json"))
    }

    private func makeTextView(_ text: String = "", width: CGFloat = 400) -> AgentComposerTextView {
        let view = AgentComposerTextView.make(font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        view.frame = NSRect(x: 0, y: 0, width: width, height: 80)
        view.string = text
        return view
    }

    private func arrowKey(_ arrow: AgentComposerArrow,
                          modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        let characters = arrow == .up ? "\u{F700}" : "\u{F701}"
        let code: UInt16 = arrow == .up ? 126 : 125
        return NSEvent.keyEvent(with: .keyDown,
                                location: .zero,
                                modifierFlags: modifiers,
                                timestamp: 0,
                                windowNumber: 0,
                                context: nil,
                                characters: characters,
                                charactersIgnoringModifiers: characters,
                                isARepeat: false,
                                keyCode: code)!
    }

    // MARK: - ① 回填顺序

    func testArrowSequenceWalksHistoryNewestFirstThenRestoresDraft() {
        var history = AgentInputHistory()
        history.record("A")
        history.record("B")
        var navigator = AgentInputHistoryNavigator()
        var text = ""   // 空输入

        XCTAssertEqual(navigator.up(current: text, history: history), "B", "第一次 ↑ 必须是最新一条（反例：从最旧开始 ⇒ 判红）")
        text = "B"
        XCTAssertEqual(navigator.up(current: text, history: history), "A")
        text = "A"
        XCTAssertEqual(navigator.down(current: text, history: history), "B")
        text = "B"
        XCTAssertEqual(navigator.down(current: text, history: history), "", "再 ↓ 回到草稿（这里草稿是空串）")
        XCTAssertFalse(navigator.isBrowsing, "回草稿即退出浏览")
        print("⌨️ ① A/B 历史 ⇒ ↑ B、↑ A、↓ B、↓ 空（草稿），共 \(history.count) 条")
    }

    /// 真控件上跑同一串（`keyDown` → 回填 → 文本），并顺带量 ④ 的提交计数。
    func testArrowSequenceThroughRealTextViewNeverSubmits() {
        let store = tempStore("real-view")
        let model = AgentChatModel(inputHistoryStore: store)
        model.recordInputHistory("A")
        model.recordInputHistory("B")
        model.input = ""

        let view = makeTextView("")
        var submitCount = 0
        view.onSubmit = { submitCount += 1 }
        view.onHistoryRecall = { arrow in model.recallHistory(arrow) }

        func press(_ arrow: AgentComposerArrow) {
            view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
            if arrow == .up { view.setSelectedRange(NSRange(location: 0, length: 0)) }
            view.keyDown(with: arrowKey(arrow))
        }

        press(.up)
        XCTAssertEqual(view.string, "B")
        press(.up)
        XCTAssertEqual(view.string, "A")
        press(.down)
        XCTAssertEqual(view.string, "B")
        press(.down)
        XCTAssertEqual(view.string, "")
        XCTAssertEqual(submitCount, 0, "④ 回填绝不能触发提交（反例：计数 1 ⇒ 判红）")
        print("⌨️ ①④ 真控件：↑↑↓↓ ⇒ B / A / B / 空，提交回调计数 \(submitCount)")
    }

    // MARK: - ② 草稿保真

    func testDraftSurvivesBrowsingAndComesBackVerbatim() {
        var history = AgentInputHistory()
        history.record("历史一")
        history.record("历史二")
        var navigator = AgentInputHistoryNavigator()

        let draft = "草稿文字"
        XCTAssertEqual(navigator.up(current: draft, history: history), "历史二")
        XCTAssertEqual(navigator.down(current: "历史二", history: history), draft,
                       "回到底必须是那份草稿（反例：变空 ⇒ 判红）")
        print("⌨️ ② 草稿「\(draft)」↑→「历史二」→↓→「\(draft)」")
    }

    func testDraftWithNewlinesAndTrailingSpacesComesBackVerbatim() {
        var history = AgentInputHistory()
        history.record("X")
        var navigator = AgentInputHistoryNavigator()
        let draft = "第一行\n第二行  "
        _ = navigator.up(current: draft, history: history)
        XCTAssertEqual(navigator.down(current: "X", history: history), draft)
    }

    // MARK: - ③ 不抢光标

    func testRouterOnlyClaimsEdges() {
        let multi = "第一行\n第二行"
        let utf16 = (multi as NSString).length   // 7
        // 第二行行中（偏移 5，在「第二」之间）⇒ 不接管
        XCTAssertFalse(AgentComposerArrowRouter.takesHistory(.up, text: multi, caret: 5),
                       "多行中间 ↑ 必须走光标（反例：被换成历史 ⇒ 判红）")
        XCTAssertFalse(AgentComposerArrowRouter.takesHistory(.down, text: multi, caret: 5))
        // 首行行首 ⇒ 接管；末行行末 ⇒ 接管
        XCTAssertTrue(AgentComposerArrowRouter.takesHistory(.up, text: multi, caret: 0))
        XCTAssertTrue(AgentComposerArrowRouter.takesHistory(.down, text: multi, caret: utf16))
        // 首行中间 ↑ / 第二行行首 ↑（偏移 4）⇒ 都不接管
        XCTAssertFalse(AgentComposerArrowRouter.takesHistory(.up, text: multi, caret: 2))
        XCTAssertFalse(AgentComposerArrowRouter.takesHistory(.up, text: multi, caret: 4))
        // 有选区 / 浮层开着 ⇒ 都不接管
        XCTAssertFalse(AgentComposerArrowRouter.takesHistory(.up, text: multi, caret: 0, selectionLength: 2))
        XCTAssertFalse(AgentComposerArrowRouter.takesHistory(.up, text: multi, caret: 0, overlayOpen: true))
        print("⌨️ ③ 多行「第一行/第二行」：行中 5 ⇒ false；行首 0 ⇒ true；末行末 \(utf16) ⇒ true；行首 4 ⇒ false")
    }

    /// 真控件：光标在第二行行中按 ↑ ⇒ **文字一个字都不变**，且系统默认移动把光标带到上一行。
    func testUpInsideSecondLineKeepsTextAndMovesCaretUp() {
        let store = tempStore("caret")
        let model = AgentChatModel(inputHistoryStore: store)
        model.recordInputHistory("不该被填进来")

        let text = "第一行\n第二行"
        let view = makeTextView(text)
        var recallCount = 0
        view.onHistoryRecall = { arrow in
            recallCount += 1
            return model.recallHistory(arrow)
        }
        let caret = (text as NSString).range(of: "二").location   // 第二行行中
        view.setSelectedRange(NSRange(location: caret, length: 0))
        view.keyDown(with: arrowKey(.up))

        XCTAssertEqual(view.string, text, "③ 反例：文字被历史换掉 ⇒ 判红")
        XCTAssertEqual(recallCount, 0, "③ 这一次按键不该归历史")
        XCTAssertEqual(model.input, "")

        // 系统默认那一条路（我们不接管时按键会落到它上面）：真的把光标带到上一行。
        view.moveUp(nil)
        let moved = view.selectedRange().location
        XCTAssertLessThan(moved, 4, "光标应落在第一行（偏移 < 4，反例：还在第二行 ⇒ 判红）")
        print("⌨️ ③ 行中 ↑ 后文字仍为「\(view.string.replacingOccurrences(of: "\n", with: "⏎"))」、回填计数 \(recallCount)、光标 \(caret) → \(moved)")
    }

    // MARK: - ④ 回填不发送（控件层）

    func testRecallAtEmptyInputFillsWithoutCallingSubmit() {
        let view = makeTextView("")
        var submitCount = 0
        var recalled: [AgentComposerArrow] = []
        view.onSubmit = { submitCount += 1 }
        view.onHistoryRecall = { arrow in
            recalled.append(arrow)
            return "上一条"
        }
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.keyDown(with: arrowKey(.up))

        XCTAssertEqual(view.string, "上一条")
        XCTAssertEqual(view.selectedRange().location, (view.string as NSString).length, "回填后光标落到末尾，接着就能改")
        XCTAssertEqual(submitCount, 0, "④ ↑ 之后提交回调必须为 0（反例：1 ⇒ 判红）")
        XCTAssertEqual(recalled, [.up])
        print("⌨️ ④ ↑ 回填「上一条」，提交计数 \(submitCount)")
    }

    func testEnterSubmitsButShiftStyleNewlineDoesNot() {
        let view = makeTextView("问一句")
        var submitCount = 0
        view.onSubmit = { submitCount += 1 }
        view.insertNewline(nil)                    // ⏎
        XCTAssertEqual(submitCount, 1)
        view.insertNewlineIgnoringFieldEditor(nil) // ⌥⏎ / ⇧⏎ 那一档：换行不提交
        XCTAssertEqual(submitCount, 1)
        XCTAssertEqual(view.string, "问一句\n")
        print("⌨️ ⑥ ⏎ ⇒ 提交 \(submitCount) 次；换行档 ⇒ 文本多一行、仍是 \(submitCount) 次")
    }

    // MARK: - ⑤ 历史口径（去重 / 上限 / 落盘）

    func testEmptyAndConsecutiveDuplicatesAreIgnored() {
        var history = AgentInputHistory()
        XCTAssertFalse(history.record(""))
        XCTAssertFalse(history.record("   \n "))
        XCTAssertTrue(history.record("A"))
        XCTAssertFalse(history.record("A"), "连续重复去重")
        XCTAssertTrue(history.record("B"))
        XCTAssertEqual(history.entries, ["A", "B"])
        XCTAssertTrue(history.record("A"), "隔开的重复照样收（那是真的又问了一次）")
        XCTAssertEqual(history.entries, ["A", "B", "A"])
        print("⌨️ ⑤ A、A、B、A ⇒ \(history.entries)")
    }

    func testHistoryKeepsOnlyNewestTwoHundred() {
        var history = AgentInputHistory()
        for index in 1...205 { history.record("q\(index)") }
        XCTAssertEqual(history.count, AgentInputHistory.defaultLimit)
        XCTAssertEqual(history.count, 200)
        XCTAssertEqual(history.entries.first, "q6", "超上限挤掉最旧的（反例：挤掉最新的 ⇒ 判红）")
        XCTAssertEqual(history.entries.last, "q205")
        print("⌨️ ⑤ 205 条 ⇒ 保留 \(history.count) 条，首条 \(history.entries.first ?? "-")、末条 \(history.entries.last ?? "-")")
    }

    func testHistorySurvivesStoreReload() throws {
        let store = tempStore("reload")
        var history = AgentInputHistory()
        history.record("第一条")
        history.record("第二条")
        try store.save(history)

        let reloaded = try AgentInputHistoryStore(fileURL: store.fileURL).load()
        XCTAssertEqual(reloaded.entries, ["第一条", "第二条"], "顺序必须保持「旧 → 新」")
        print("⌨️ ⑤ 落盘 → 新 store 载入 ⇒ \(reloaded.entries)")
    }

    func testCorruptFileLoadsAsEmptyButThrows() {
        let store = tempStore("corrupt")
        try? FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? Data("{not json".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load(), "坏文件要如实抛错，由调用方决定要不要说出来")
    }

    // MARK: - ⑥ 边界

    func testOldestBoundaryAndDraftBoundaryDoNothing() {
        var history = AgentInputHistory()
        history.record("A")
        var navigator = AgentInputHistoryNavigator()

        XCTAssertEqual(navigator.up(current: "", history: history), "A")
        XCTAssertNil(navigator.up(current: "A", history: history), "最旧再 ↑ ⇒ 不变（不循环到最新）")
        XCTAssertEqual(navigator.up(current: "A", history: history), nil, "仍然停在最旧")
        XCTAssertEqual(navigator.down(current: "A", history: history), "")
        XCTAssertNil(navigator.down(current: "", history: history), "草稿态再 ↓ ⇒ 什么都不做")
        print("⌨️ ⑥ 最旧再 ↑ = nil；草稿态再 ↓ = nil")
    }

    func testEmptyHistoryIgnoresArrows() {
        let history = AgentInputHistory()
        var navigator = AgentInputHistoryNavigator()
        XCTAssertNil(navigator.up(current: "abc", history: history))
        XCTAssertNil(navigator.down(current: "abc", history: history))
        XCTAssertEqual(navigator.draft, nil, "没有历史时不该把草稿记下来（下一 ↑ 要能记新的）")
    }

    // MARK: - 模型接线（落盘 + 只回填不发送）

    func testModelRecordsOnSubmitAndReloadsFromDisk() {
        let store = tempStore("model")
        let model = AgentChatModel(inputHistoryStore: store)
        model.recordInputHistory("发出去的一句")

        let reloaded = AgentChatModel(inputHistoryStore: store)
        XCTAssertEqual(reloaded.inputHistory.entries, ["发出去的一句"], "重启（新 model）后历史仍在")
        XCTAssertNil(model.inputHistorySaveError)
        print("⌨️ ⑤ 模型落盘 ⇒ 新 model 载入 \(reloaded.inputHistory.entries)")
    }

    func testRecallHistoryDoesNotStartATurn() async {
        let store = tempStore("recall")
        let model = AgentChatModel(inputHistoryStore: store)
        model.recordInputHistory("A")
        model.recordInputHistory("B")
        model.input = ""

        var loopBuilds = 0
        model.makeLoop = { _, _, _ in
            loopBuilds += 1
            return nil
        }

        XCTAssertEqual(model.recallHistory(.up), "B")
        XCTAssertEqual(model.input, "B")
        XCTAssertEqual(loopBuilds, 0, "④ 回填不能造循环（= 不能发送）")
        XCTAssertTrue(model.messages.isEmpty)
        print("⌨️ ④ 模型层：回填后 loop 构造次数 \(loopBuilds)、消息条数 \(model.messages.count)")
    }
}
