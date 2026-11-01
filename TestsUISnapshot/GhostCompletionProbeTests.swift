import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 行内灰字补全（`FR-STD-WS-NAV-004` 的接线那一半）的 **App 内按键探针**。
///
/// ## 为什么要有它
///
/// 灰字的验收口径是「敲字时光标右边出一条淡色建议，Tab 接受、Esc 忽略、移动光标就撤」——
/// 这些**全都发生在真编辑器里**。`Tests/InlineGhostCompletionTests` 判的是 Core 的纯函数
/// （给定文本与选区算什么建议），它绿着也可以整个功能没接线：宿主没调 `refreshGhost`、
/// `insertTab` 里没有接受那一支、词表从来没递进去。第 109 / 135 轮的两次教训都是这个形状
/// （Core 全绿、真机静默失效）。
///
/// ## 判什么（每条都是行为面）
///
/// ① 真编辑器里敲 `retu` ⇒ 出灰字（`insertText == "return"`、灰字 `rn`），
///    而**正文仍是 `retu`**（灰字只画不写：撤销栈 / 保存的文件 / 复制走的文本里都不许有它）；
/// ② 按 Tab ⇒ 整词 `return` 落进正文、光标到词尾（这才是「接受」）；
/// ③ 按 Esc ⇒ 灰字撤掉，而且**不会原地复活**（再刷新一拍也还是 `nil`）；
/// ④ 移动光标 ⇒ 灰字撤掉（光标离开那个词之后还挂着一条建议，就是最典型的假提示）；
/// ⑤ 词法候选来自**当前文档词表**：文档里 `customerTotal` 出现过两次时，敲 `cust` 补的是它
///    （类别是 `.word`，不是关键字）；
/// ⑥ 字符串里不出灰字（在那里补全是纯破坏）。
///
/// ## 发现但未修（本轮实测）
///
/// **`CodeCompletion` 的承诺与候选表顺序不一致**：`Core/CodeCompletion.swift:33` 的注释写着
/// 「`ret` 第一个永远是 `return`」，但 Swift 关键字表里 `rethrows` 排在 `return` 前面
/// （`Core/CodeLanguageDefinitions.swift` 的 swift `keywords`），所以真编辑器里敲 `ret`
/// 得到的第一条候选 / 灰字是 **`rethrows`（灰字 `hrows`）**。后果：灰字在写 `return` 时
/// 给的是另一个词，Tab 一接受就写错。本族因此改用 `retu` 判「链路通不通」，不把排序口径混进来。
///
/// **没有灰字时按 Esc 会抛异常**：`CodeTextView.cancelOperation`（同文件 918-921 行）在没有灰字时
/// 走到 `super.cancelOperation(sender)`，而 `cancelOperation:` 是 `NSStandardKeyBindingResponding`
/// 的**可选**方法、`NSResponder` 并无实现 ⇒ 实测（本轮判红那一跑）抛
/// `-[CodeTextView cancelOperation:]: unrecognized selector sent to instance`，
/// 由 AppKit 的按键处理兜底吞掉（控制台一行 `Exception detected while handling key input`）。
/// 用户侧表现为「没有灰字时按 Esc 什么都没发生（本该有的兜底行为也永远不会跑）」。
/// 本族只在**有灰字**时判 Esc（那一支会 `return`，不会撞上），这一条按「发现但未修」登记。
///
/// ## 判不到的（如实登记）
///
/// · **像素**：灰字是 `GhostTextOverlay.draw` 画的（不进 `textStorage`），它的位置/淡色这一档
///   本族没有机器判据 —— 判的是「该画什么」（`ghost` 状态）与「按 Tab 之后正文变成什么」。
///   画到屏幕上的样子仍归人工点验（清单 §10）。
///
/// ## 判红自证（红 → 逐字节还原 → 绿）
///
/// 把 `App/Views/CodeEditorView.swift` 的 `refreshGhost()` 方法体临时改成
/// `ghostOverlay.language = completionLanguage`（＝不再重算灰字）：
/// 红 —— ①②③④⑤ 五条红（`tv.ghost` 恒为 `nil`；⑥ 是**反向**判据「字符串里不出灰字」，
/// 这一档下它必然还绿，不算证据）。另把 `insertTab` 里 `if acceptGhost() { return }` 删掉
/// ⇒ ② 单独红（Tab 插的是缩进不是整词：`retu    ` vs `return`）。
/// 两处都用 `git checkout -- App/Views/CodeEditorView.swift` 逐字节还原后同一批用例转绿。
///
/// 跑法：`env DOYAH_UI_SNAPSHOT=1 swift test --filter GhostCompletionProbeTests`
final class GhostCompletionProbeTests: XCTestCase {

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
        language: TextLanguage = .swift
    ) throws -> (host: UISnapshot.LiveHost<Harness>, textView: CodeTextView) {
        let host = UISnapshot.LiveHost(Harness(text: text, language: language),
                                       size: CGSize(width: 640, height: 240))
        // 多泵一拍：词表是跟着**着色那一拍**递进视图的（`updateGhostWords`），不等它就只有关键字、
        // 没有文档词 —— 那会把「词表没接上」误判成「本来就没有候选」。
        host.pump(1.0)
        let textView = try XCTUnwrap(
            UISnapshot.LiveHost<Harness>.findViews(ofType: CodeTextView.self, in: host.hosting).first,
            "真编辑器不在宿主视图树里 —— 这条判据的入口没了"
        )
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        XCTAssertTrue(host.window.makeFirstResponder(textView), "编辑器拿不到第一响应者")
        return (host, textView)
    }

    private func tabKey(windowNumber: Int) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: windowNumber, context: nil,
            characters: "\t", charactersIgnoringModifiers: "\t",
            isARepeat: false, keyCode: 48
        )!
    }

    private func escapeKey(windowNumber: Int) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53
        )!
    }

    private func leftArrowKey(windowNumber: Int) -> NSEvent {
        let arrow = String(Unicode.Scalar(0xF702)!)
        return NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: windowNumber, context: nil,
            characters: arrow, charactersIgnoringModifiers: arrow,
            isARepeat: false, keyCode: 123
        )!
    }

    @MainActor
    private func type(_ text: String, into tv: CodeTextView) {
        for character in text {
            tv.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    // MARK: - ① 出灰字，但正文不变

    @MainActor
    func testTypingPrefixShowsGhostWithoutTouchingText() throws {
        // 前缀取 `retu` 而不是 `ret`：Swift 关键字表里 `rethrows` 排在 `return` 前面，敲 `ret`
        // 第一条候选是 `rethrows`（见报告里「发现但未修」那一条）。这里只判「灰字这条链路通不通」，
        // 不把候选排序的口径混进来。
        let (_, tv) = try makeEditor(text: "")
        type("retu", into: tv)

        let ghost = try XCTUnwrap(tv.ghost,
                                  "敲了 `retu` 却没有灰字 —— 补全这一条在真编辑器里根本没触发")
        XCTAssertEqual(ghost.insertText, "return", "灰字补的不是 `return`（而是 \(ghost.insertText)）")
        XCTAssertEqual(ghost.ghost, "rn", "灰字应当只画「前缀之后的那一截」")
        XCTAssertEqual(ghost.range, NSRange(location: 0, length: 4), "灰字替换的应当是已输入的前缀")
        XCTAssertEqual(tv.string, "retu",
                       "灰字被写进正文了 —— 它必须只画不写（否则撤销栈、保存的文件里都有它）")
    }

    // MARK: - ② Tab 接受

    @MainActor
    func testTabAcceptsGhostAndInsertsWholeWord() throws {
        let (host, tv) = try makeEditor(text: "")
        type("retu", into: tv)
        XCTAssertNotNil(tv.ghost, "前置：`retu` 应当有一条灰字")

        tv.interpretKeyEvents([tabKey(windowNumber: host.window.windowNumber)])
        host.pump(0.05)

        XCTAssertEqual(tv.string, "return", "Tab 没把灰字接受下来（插进去的正文不对）")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 6, length: 0),
                       "接受灰字后光标应当落在词尾，而不是停在原处 / 选中整词")
        XCTAssertNil(tv.ghost, "接受之后灰字还挂着（会盖在已经写进去的正文上）")
    }

    // MARK: - ③ Esc 撤掉且不复活

    @MainActor
    func testEscapeDismissesGhostAndItDoesNotComeBack() throws {
        let (host, tv) = try makeEditor(text: "")
        type("retu", into: tv)
        XCTAssertNotNil(tv.ghost, "前置：`retu` 应当有一条灰字")

        tv.interpretKeyEvents([escapeKey(windowNumber: host.window.windowNumber)])
        host.pump(0.05)
        XCTAssertNil(tv.ghost, "Esc 没撤掉灰字")
        XCTAssertEqual(tv.string, "retu", "Esc 不该改正文")

        // 再刷新一拍（光标动一下就会刷新）：撤掉的建议不许原地复活。
        tv.refreshGhost()
        XCTAssertNil(tv.ghost, "Esc 之后灰字又原地复活了（按了没反应比没有还糟）")
    }

    // MARK: - ④ 移动光标就撤

    @MainActor
    func testMovingCaretCancelsGhost() throws {
        let (host, tv) = try makeEditor(text: "")
        type("retu", into: tv)
        XCTAssertNotNil(tv.ghost, "前置：`retu` 应当有一条灰字")

        tv.interpretKeyEvents([leftArrowKey(windowNumber: host.window.windowNumber)])
        host.pump(0.05)

        XCTAssertNil(tv.ghost, "光标已经离开词尾，灰字还挂在那儿（提示落在错的位置上）")
        XCTAssertEqual(tv.string, "retu", "移动光标不该改正文")
    }

    // MARK: - ⑤ 词法候选来自当前文档词表

    @MainActor
    func testGhostComesFromDocumentWordTable() throws {
        // 文档里 `customerTotal` 出现两次 ⇒ 它是这份文件的词表里最像的那个词。
        let (_, tv) = try makeEditor(text: "let customerTotal = 1\ncustomerTotal = 2\ncust")
        // 程序化设选区不一定发通知，这里显式走一次视图自己的刷新入口（产品入口，不是测试后门）。
        tv.refreshGhost()

        let ghost = try XCTUnwrap(tv.ghost, "文档里明明有 `customerTotal`，敲 `cust` 却没灰字")
        XCTAssertEqual(ghost.insertText, "customerTotal", "灰字候选不是文档里那个词")
        XCTAssertEqual(ghost.kind, .word, "这条候选应当来自文档词表（`.word`），而不是关键字")
        XCTAssertEqual(tv.string.hasSuffix("cust"), true, "灰字不许写进正文")
    }

    // MARK: - ⑥ 字符串里不出灰字

    @MainActor
    func testNoGhostInsideString() throws {
        let (_, tv) = try makeEditor(text: "\"ret\"")
        tv.setSelectedRange(NSRange(location: 4, length: 0))   // 光标在右引号前
        tv.refreshGhost()

        XCTAssertNil(tv.ghost, "在字符串里补全代码词是纯破坏（这里应当一条灰字都不出）")
    }
}
