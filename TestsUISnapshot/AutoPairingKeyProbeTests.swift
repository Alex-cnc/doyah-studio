import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 括号 / 引号自动配对的 **App 内键入探针** —— 派单 `T-20261018-205`（`FR-EDIT-49`）。
///
/// 人类主人 2026-10-18 人工点验「按了没反应，不清楚是不是因为在 markdown 源码里」。
/// `Tests/CodeAutoPairingTests` 判的是 Core 的纯函数（全绿也拦不住「路根本没通」），
/// 所以这一组**只判真实按键能不能走到 Core**：同一夹具分别走
/// ① 直接 `insertText` ② `interpretKeyEvents`（AppKit 的键→文本转换入口）
/// ③ `NSWindow.sendEvent`（用户真正按键时的那一层）。
final class AutoPairingKeyProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    private struct Harness: View {
        let tabID = UUID()
        let text: String
        let language: TextLanguage
        var body: some View {
            CodeEditorView(
                tabID: tabID,
                text: text,
                language: language,
                onTextChange: { _ in },
                onSave: {},
                onFormat: {}
            )
        }
    }

    @MainActor
    private func makeEditor(
        text: String,
        language: TextLanguage = .markdown
    ) throws -> (host: UISnapshot.LiveHost<Harness>, textView: CodeTextView) {
        let host = UISnapshot.LiveHost(Harness(text: text, language: language),
                                       size: CGSize(width: 640, height: 240))
        host.pump(0.5)
        let textView = try XCTUnwrap(
            UISnapshot.LiveHost<Harness>.findViews(ofType: CodeTextView.self, in: host.hosting).first,
            "真编辑器不在宿主视图树里"
        )
        XCTAssertTrue(host.window.makeFirstResponder(textView), "编辑器拿不到第一响应者")
        return (host, textView)
    }

    private func keyEvent(_ characters: String, keyCode: UInt16, windowNumber: Int) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        )!
    }

    // MARK: - ① 直接 insertText（宿主层这一环通不通）

    @MainActor
    func testDirectInsertTextPairsBracket() throws {
        let (_, tv) = try makeEditor(text: "")
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.insertText("(", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(tv.string, "()", "宿主层没把 Core 的配对计划搬过来")
        XCTAssertEqual(tv.selectedRange().location, 1)
    }

    // MARK: - ② interpretKeyEvents（AppKit 把按键转成文本的那一环）

    @MainActor
    func testTypedBracketThroughInterpretKeyEvents() throws {
        let (host, tv) = try makeEditor(text: "")
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.interpretKeyEvents([keyEvent("(", keyCode: 33, windowNumber: host.window.windowNumber)])
        XCTAssertEqual(tv.string, "()", "按键经 AppKit 转换后没配对")
    }

    // MARK: - ③ 窗口层（用户真正按键时的那一层）

    @MainActor
    func testTypedBracketThroughWindowSendEvent() throws {
        let (host, tv) = try makeEditor(text: "")
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        host.window.makeKey()
        host.window.sendEvent(keyEvent("(", keyCode: 33, windowNumber: host.window.windowNumber))
        host.pump(0.2)
        XCTAssertEqual(tv.string, "()", "窗口层没把键送到编辑器 / 送到了但没配对")
    }

    /// 中文输入法上屏全角（`（`）：真视图这一环也必须补上 `）`。
    @MainActor
    func testFullWidthBracketThroughRealView() throws {
        let (host, tv) = try makeEditor(text: "")
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        host.window.makeKey()
        host.window.sendEvent(keyEvent("（", keyCode: 33, windowNumber: host.window.windowNumber))
        host.pump(0.2)
        XCTAssertEqual(tv.string, "（）", "全角括号经真按键路径没配对（中文输入法下的那种\"没反应\"）")
        XCTAssertEqual(tv.selectedRange().location, 1)
    }

    // MARK: - 四条口径在真视图里各走一遍

    @MainActor
    func testQuotePairsInSwiftButNotInMarkdown() throws {
        let (_, md) = try makeEditor(text: "")
        md.insertText("\"", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(md.string, "\"", "Markdown（散文族）不该配对引号")

        let (_, swift) = try makeEditor(text: "", language: .swift)
        swift.insertText("\"", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(swift.string, "\"\"", "代码族的引号要配对")
        XCTAssertEqual(swift.selectedRange().location, 1)
    }

    @MainActor
    func testClosingBracketSkipsInsteadOfInserting() throws {
        let (_, tv) = try makeEditor(text: "()")
        tv.setSelectedRange(NSRange(location: 1, length: 0))
        tv.insertText(")", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(tv.string, "()", "已配对处又插了一个闭合符")
        XCTAssertEqual(tv.selectedRange().location, 2, "应当跳过而不是插入")
    }

    @MainActor
    func testSelectionIsWrappedNotOverwritten() throws {
        let (_, tv) = try makeEditor(text: "abc", language: .swift)
        tv.setSelectedRange(NSRange(location: 0, length: 3))
        tv.insertText("(", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(tv.string, "(abc)")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 1, length: 3), "选区要保持包住原文")
    }
}
