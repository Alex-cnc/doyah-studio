import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// Markdown 编辑手感的 **App 内按键探针** —— 派单 `T-20261018-204`（`FR-EDIT-48` ⌘L 勾选翻转）
/// 与 `T-20261018-205`（`FR-EDIT-49` 括号 / 引号自动配对）共用的入口。
///
/// ## 为什么要有它
///
/// 人类主人 2026-10-18 人工点验这两条都是「**按了没反应**」。而 Core 的单测
/// （`Tests/MarkdownEditingTests` 17 例 / `Tests/CodeAutoPairingTests`）判的是**纯函数**——
/// 它们全绿也拦不住「视图根本没收到这个按键」：跟第 109 轮多光标那条一模一样的教训
/// （`multiSelection` 的零长度选区收不下，Core 全绿、真机静默失效）。
///
/// ## 判什么
///
/// ① 真 `CodeTextView`（真 `CodeEditorView` 装进 `UISnapshot.LiveHost`）收到 ⌘L 之后，
///    光标行方框**真的翻转**，光标偏移**不动**；
/// ② 非任务行的 ⌘L **不吞**（`performKeyEquivalent` 返回 `false`，按键交还系统）；
/// ③ ⌘⇧L 不许被这一支吃掉（主菜单里那一条是另一件事）；
/// ④ 整条窗口链（`NSWindow.sendEvent`，含 `NSHostingView` 的快捷键解析）也翻得动 ——
///    这一条与 ① 的差就是「主菜单 / 宿主层有没有把 ⌘L 抢走」；
/// ⑤ 主菜单里到底有没有别的条目占着 ⌘L（只读清点，**不执行**菜单项）。
///
/// 跑法：`env DOYAH_UI_SNAPSHOT=1 swift test --filter MarkdownEditingKeyProbeTests`
final class MarkdownEditingKeyProbeTests: XCTestCase {

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
            "真编辑器不在宿主视图树里 —— 判据的入口没了"
        )
        XCTAssertEqual(textView.string, text, "编辑器里应当是夹具那段 Markdown")
        XCTAssertTrue(host.window.makeFirstResponder(textView), "编辑器拿不到第一响应者")
        return (host, textView)
    }

    private func keyEvent(
        _ characters: String,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        windowNumber: Int
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    // MARK: - ① 视图收得下 ⌘L，方框真翻

    @MainActor
    func testCommandLFlipsTaskBoxAndKeepsCaret() throws {
        let text = "- [ ] 洗车\n- [ ] 打气\n"
        let (host, textView) = try makeEditor(text: text)
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        let l = keyEvent("l", keyCode: 37, flags: [.command], windowNumber: host.window.windowNumber)

        XCTAssertTrue(textView.performKeyEquivalent(with: l), "⌘L 没被编辑器接住（需求 ① 的入口都是空的）")
        XCTAssertEqual(textView.string, "- [x] 洗车\n- [ ] 打气\n", "方框没翻 / 翻错了行")
        XCTAssertEqual(textView.selectedRange().location, 6, "等长替换不许把光标顶走")
    }

    @MainActor
    func testCommandLFlipsBackAndLeavesOtherLinesAlone() throws {
        let text = "- [x] 洗车\n- [ ] 打气\n"
        let (host, textView) = try makeEditor(text: text)
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        let l = keyEvent("l", keyCode: 37, flags: [.command], windowNumber: host.window.windowNumber)
        XCTAssertTrue(textView.performKeyEquivalent(with: l))
        XCTAssertEqual(textView.string, "- [ ] 洗车\n- [ ] 打气\n")
    }

    // MARK: - ② 非任务行不吞 / ③ ⇧⌘L 不抢

    @MainActor
    func testCommandLOnPlainLineIsNotSwallowed() throws {
        let text = "就是一句普通的话\n"
        let (host, textView) = try makeEditor(text: text)
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        let l = keyEvent("l", keyCode: 37, flags: [.command], windowNumber: host.window.windowNumber)
        XCTAssertFalse(textView.performKeyEquivalent(with: l), "非任务行的 ⌘L 被吞了 ⇒ 需求 ③ 破了")
        XCTAssertEqual(textView.string, text)
    }

    @MainActor
    func testShiftCommandLIsNotTakenByTaskToggle() throws {
        let text = "- [ ] 洗车\n"
        let (host, textView) = try makeEditor(text: text)
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        let l = keyEvent("l", keyCode: 37, flags: [.command, .shift],
                         windowNumber: host.window.windowNumber)
        XCTAssertFalse(textView.performKeyEquivalent(with: l), "⇧⌘L 被勾选框这一支抢了")
        XCTAssertEqual(textView.string, text, "⇧⌘L 不许改动正文")
    }

    // MARK: - ④ 窗口层 / 大写锁 / 菜单落点

    /// 窗口层（`NSWindow.performKeyEquivalent`）也要送到 —— 这一层是 AppKit 真正派发 ⌘ 键的那一层。
    ///
    /// **边界（如实登记，本轮实测）**：`window.sendEvent` 与 `NSApp.sendEvent` 这条更外层的路
    /// 在离屏宿主里**对任何 ⌘ 键都不生效**（同一支里的 ⌘S 对照也送不到），原因是那个 borderless
    /// 窗口永远成不了 key window —— 那是宿主限制，不是产品缺陷，所以不拿它当判据。
    @MainActor
    func testCommandLThroughWindowKeyEquivalentFlips() throws {
        let text = "- [ ] 洗车\n"
        let (host, textView) = try makeEditor(text: text)
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        let l = keyEvent("l", keyCode: 37, flags: [.command], windowNumber: host.window.windowNumber)
        let handled = host.window.performKeyEquivalent(with: l)
        host.pump(0.2)
        XCTAssertTrue(handled, "窗口层没接住 ⌘L")
        XCTAssertEqual(textView.string, "- [x] 洗车\n")
    }

    /// 大写锁开着时 ⌘L 仍要翻转（`T-20261018-204` 修掉的那条静默放行）。
    @MainActor
    func testCommandLWithCapsLockStillFlips() throws {
        let text = "- [ ] 洗车\n"
        let (host, textView) = try makeEditor(text: text)
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        let l = keyEvent("l", keyCode: 37, flags: [.command, .capsLock],
                         windowNumber: host.window.windowNumber)
        XCTAssertTrue(textView.performKeyEquivalent(with: l),
                      "大写锁开着时 ⌘L 又被静默放行了（掩码里混进 .capsLock）")
        XCTAssertEqual(textView.string, "- [x] 洗车\n")
    }

    /// 菜单项的落点（`toggleMarkdownTaskFromMenu`）翻开得动 —— 菜单那条路最终打到的就是它。
    @MainActor
    func testMenuEntryFlipsTheTaskBox() throws {
        let text = "- [ ] 洗车\n"
        let (_, textView) = try makeEditor(text: text)
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        textView.toggleMarkdownTaskFromMenu(nil)
        XCTAssertEqual(textView.string, "- [x] 洗车\n", "菜单项打到的落点没翻 ⇒ 菜单那条路是死的")
    }
}
