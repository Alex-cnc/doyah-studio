import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 多光标与列编辑（FR-EDIT-27）的 **App 内探针** —— 队列 `L-90` ㈡ 第 1 条 / 开发循环第 109 轮。
///
/// ## 判什么（清单 §3 那一行的人话）
///
/// 「编辑器里：⌥ 拖拽列选；⌥⌘D 选下一处；⌥⌘↑ / ↓ 加光标；多光标下打字与 ⌫」
/// 「改动**一次撤销**能全回退；光标位置不漂」—— 前半句是**入口**、后半句是**验收面**。
///
/// ## 怎么判（自己点自己，零权限）
///
/// 把**真 `SQLEditorView`** 放进活宿主（`UISnapshot.LiveHost`），从视图树里取出真
/// `SQLTextView`，把合成的 `NSEvent`（⌥⌘D / ⌥⌘↑↓ / ⌥ 拖拽）**直接交给它的方法** ——
/// 合成事件只有跨进程投递才需要辅助功能授权（路线与理由见 `L-90` ㈠ 那个文件）。
/// 「界面上到底有几个光标」读的是 `SQLTextView.multiSelection`（视图自己那份唯一出处）。
///
/// ## 本轮（第 109 轮）顺手抓出并修掉的真缺陷
///
/// `NSTextView` **只收得下第一个零长度选区**（实测 macOS 27：设 `[{4,0},{30,0}]` 读回来
/// `[{4,0}]`；**非零长度**的多选区则原样收下，`[{5,3},{31,3}]` 回来还是两条）。
/// ⇒ **⌥⌘↑ / ⌥⌘↓「加光标」在真机上一直是静默失效的**（`selectedRanges` 恒为一条 ⇒
/// 打字 / 退格的多光标分支与 `drawInsertionPoint` 里画次光标那段**都是死代码**），
/// 而 `MultiCursorTests` 21 项判的是 Core ⇒ 全绿也拦不住这件事。
/// 修法：零长度那些由视图自己记（`SQLTextView.rememberedCarets`），`rangeValues` 取两份的并集。
/// 本文件里「⌥⌘↑ 之后 `multiSelection` 必须 ≥ 2」那条就是这条缺陷的**回归钉**。
///
/// ## 口径与边界（如实登记）
///
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`），跑法 `./Scripts/verify-ui-interactions.sh`；
/// · **语言无关**：这几张图里没有一句界面文案（画面就是 SQL 文本与光标），故不按语言各出一张；
/// · 「一次撤销」判的是**文本**回到旧样；AppKit 的 undo 会把光标收回到一处 —— 那是框架行为，
///   如实登记，不当判据；
/// · 判得到「视图拿到这个事件之后做什么」，判不到「系统把事件送到这个视图」。
final class MultiCursorProbeTests: XCTestCase {

    // MARK: - 宿主与工具

    /// 被测的真编辑器宿主（`@State` 的文本绑在宿主上，编辑器就是产品那一个）。
    private struct Harness: View {
        @State var text: String
        var body: some View {
            SQLEditorView(text: $text, databaseType: .postgresql, diagnostics: [], tabID: UUID())
        }
    }

    /// 三行文本：每行都有 `alpha`（判 ⌥⌘D 落三处）；行宽不同（判列选逐行取值）。
    private static let sql =
        "select alpha from t\nselect alpha, beta from t\nselect alpha, beta, gamma from t\n"

    private func keyEvent(
        _ characters: String,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags = [],
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

    /// 起一个真编辑器宿主，并把真 `SQLTextView` 取出来。
    @MainActor
    private func makeHost(
        text: String = MultiCursorProbeTests.sql,
        height: CGFloat = 240
    ) throws -> (host: UISnapshot.LiveHost<Harness>, textView: SQLTextView) {
        guard ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1" else {
            throw XCTSkip("要 DOYAH_UI_SNAPSHOT=1（跑法 ./Scripts/verify-ui-interactions.sh）")
        }
        let host = UISnapshot.LiveHost(Harness(text: text), size: CGSize(width: 640, height: height))
        host.pump(0.5)
        let textView = try XCTUnwrap(
            UISnapshot.LiveHost<Harness>.findViews(ofType: SQLTextView.self, in: host.hosting).first,
            "真编辑器不在宿主视图树里 —— 判据的入口没了"
        )
        XCTAssertEqual(textView.string, text, "编辑器里应当是夹具那段 SQL")
        return (host, textView)
    }

    // MARK: - ① ⌥⌘D 选下一处 + 多光标打字 + 一次撤销

    @MainActor
    func testOptionCommandDTypesInEveryOccurrenceAndOneUndoRevertsAll() throws {
        let (host, textView) = try makeHost()
        let d = keyEvent("d", keyCode: 2, flags: [.command, .option], windowNumber: host.window.windowNumber)

        // 从**光标**在词里开始：第一下只扩成词，第二下才新增光标（语义在 Core，这里判接线）
        textView.setSelectedRange(NSRange(location: 8, length: 0))
        textView.keyDown(with: d)
        XCTAssertEqual(
            textView.multiSelection,
            [NSRange(location: 7, length: 5)],
            "光标在词里时，第一下 ⌥⌘D 只应当把当前这个词选中"
        )
        textView.keyDown(with: d)
        XCTAssertEqual(
            textView.multiSelection,
            [NSRange(location: 7, length: 5), NSRange(location: 27, length: 5)],
            "第二下应当把**下一处**同样的内容也选进来（两个选区）"
        )

        // 从已选中的词开始：一下一处
        textView.setSelectedRange(NSRange(location: 7, length: 5))
        textView.keyDown(with: d)
        textView.keyDown(with: d)
        let expected = [
            NSRange(location: 7, length: 5),
            NSRange(location: 27, length: 5),
            NSRange(location: 53, length: 5),
        ]
        XCTAssertEqual(textView.multiSelection, expected, "三处 alpha 都该在选区集合里")
        for range in textView.multiSelection {
            XCTAssertEqual(
                (textView.string as NSString).substring(with: range),
                "alpha",
                "每个选区选中的都该是同一处内容"
            )
        }
        try host.capture(name: "interaction-editor-occurrence-selection")

        // 多光标打字：三处一起改，每个光标各自往前推进一格（位置不漂）
        let original = textView.string
        textView.insertText("X", replacementRange: textView.selectedRange())
        XCTAssertEqual(
            textView.string,
            "select X from t\nselect X, beta from t\nselect X, beta, gamma from t\n",
            "多光标打字必须三处都改"
        )
        XCTAssertEqual(
            textView.multiSelection,
            [
                NSRange(location: 8, length: 0),
                NSRange(location: 24, length: 0),
                NSRange(location: 46, length: 0),
            ],
            "三个光标都该各自往前推进一格（左处的插入不许把右处顶偏）"
        )

        // 一次撤销：整批回到原样
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, original, "多光标改动必须是**一次**撤销就能全回退（按一下 ⌘Z）")
    }

    // MARK: - ② ⌥⌘↑ / ⌥⌘↓ 加光标 + 每个光标各自打字 / 回车 / ⌫ + Esc 收敛

    @MainActor
    func testOptionArrowMultipliesCaretsAndEditingHitsEveryCaret() throws {
        let (host, textView) = try makeHost()
        let up = keyEvent("\u{F700}", keyCode: 126, flags: [.command, .option], windowNumber: host.window.windowNumber)
        let down = keyEvent("\u{F701}", keyCode: 125, flags: [.command, .option], windowNumber: host.window.windowNumber)

        // 第 2 行第 11 列（行 1 起于 20 ⇒ 偏移 30）放一个光标
        textView.setSelectedRange(NSRange(location: 30, length: 0))
        textView.keyDown(with: up)
        XCTAssertEqual(
            textView.multiSelection,
            [NSRange(location: 10, length: 0), NSRange(location: 30, length: 0)],
            "⌥⌘↑ 必须在上一行**同列加**一个光标（不是把光标挪走）—— 本轮修的就是这一条"
        )
        textView.keyDown(with: down)
        XCTAssertEqual(
            textView.multiSelection,
            [
                NSRange(location: 10, length: 0),
                NSRange(location: 30, length: 0),
                NSRange(location: 56, length: 0),
            ],
            "⌥⌘↓ 再加一个：三个光标分别在 1 / 2 / 3 行同列"
        )
        XCTAssertTrue(
            textView.multiSelection.allSatisfy { $0.length == 0 },
            "加出来的都该是裸光标（零长度），不是选区"
        )
        try host.capture(name: "interaction-editor-multi-caret")

        // 打字 / 退格：每个光标各自生效，且**一次撤销**全回退
        let original = textView.string
        textView.insertText("-", replacementRange: textView.selectedRange())
        XCTAssertEqual(
            textView.string,
            "select alp-ha from t\nselect alp-ha, beta from t\nselect alp-ha, beta, gamma from t\n",
            "三个光标各插一个字符"
        )
        XCTAssertEqual(
            textView.multiSelection,
            [
                NSRange(location: 11, length: 0),
                NSRange(location: 32, length: 0),
                NSRange(location: 59, length: 0),
            ],
            "每个光标都该跟着自己那一处往前走"
        )
        textView.deleteBackward(nil)
        XCTAssertEqual(textView.string, original, "⌫ 在三个光标上各删一个字符 ⇒ 文本回到原样")
        XCTAssertEqual(
            textView.multiSelection,
            [
                NSRange(location: 10, length: 0),
                NSRange(location: 30, length: 0),
                NSRange(location: 56, length: 0),
            ],
            "⋆ 删完之后三个光标**回到加光标时那三个位置**（左边那一处缩短了，右边的跟着左移 —— 位置不漂）"
        )

        // 回车：每个光标一个换行
        let newlineCount = textView.string.components(separatedBy: "\n").count - 1
        textView.insertNewline(nil)
        XCTAssertEqual(
            textView.string.components(separatedBy: "\n").count - 1,
            newlineCount + 3,
            "多光标下回车必须每个光标各换一行（「一个回车换 2 行」那次的教训）"
        )
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, original, "回车那一批也是一次撤销")

        // Esc：收敛回一个光标（多余光标的出口）
        textView.setSelectedRange(NSRange(location: 30, length: 0))
        textView.keyDown(with: up)
        XCTAssertEqual(textView.multiSelection.count, 2)
        textView.keyDown(with: self.keyEvent("\u{1B}", keyCode: 53, windowNumber: host.window.windowNumber))
        XCTAssertEqual(textView.multiSelection.count, 1, "Esc 必须把多光标收敛回一个")

        // 用户自己动光标（点别处 / 方向键）⇒ 之前记的裸光标作废
        textView.setSelectedRange(NSRange(location: 30, length: 0))
        textView.keyDown(with: up)
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        XCTAssertEqual(
            textView.multiSelection,
            [NSRange(location: 3, length: 0)],
            "用户点别处之后不许还留着旧光标（否则又是「看着一个光标、打字却在两处」）"
        )
    }

    // MARK: - ③ ⌥ 拖拽列选（逐行取值、短行夹到行尾、绝不跨换行）

    @MainActor
    func testOptionDragSelectsAColumnAcrossLinesWithoutCrossingThem() throws {
        // 第 2 行**故意短**（`select` 六个字符）：列宽拖宽了必须**夹到行尾**，不是跨过去。
        let text = "select alpha, beta from t\nselect\nselect alpha, gamma from t\n"
        let (host, textView) = try makeHost(text: text)
        let layout = try XCTUnwrap(textView.layoutManager)
        let origin = textView.textContainerOrigin

        /// 某一行的第一个字符处、竖直居中的那个点在视图里的位置（坐标不靠猜行高）。
        func point(lineStart: Int, inset: CGFloat) -> CGPoint {
            let glyph = layout.glyphIndexForCharacter(at: lineStart)
            let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            return CGPoint(x: origin.x + inset, y: origin.y + rect.midY)
        }

        // 从第 1 行行首按下、拖到第 3 行行首偏右（列宽 > 第 2 行的长度 ⇒ 那一行必须夹尾）
        let anchor = textView.convert(point(lineStart: 0, inset: 1), to: nil)
        let drag = textView.convert(point(lineStart: 33, inset: 90), to: nil)
        let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown, location: anchor, modifierFlags: [.option],
            timestamp: 0, windowNumber: host.window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1
        )!
        let mouseDrag = NSEvent.mouseEvent(
            with: .leftMouseDragged, location: drag, modifierFlags: [.option],
            timestamp: 0, windowNumber: host.window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 1
        )!
        textView.mouseDown(with: mouseDown)
        textView.mouseDragged(with: mouseDrag)

        let selection = textView.multiSelection
        XCTAssertEqual(selection.count, 3, "拖过三行就该有三段（每行一段）")
        XCTAssertEqual(
            selection.map(\.location),
            [0, 26, 33],
            "每段的起点都该是**它自己那一行的行首**（行首起拖 ⇒ 逐行取同一段列）"
        )
        guard selection.count == 3 else { return }
        XCTAssertEqual(selection[1].length, 6, "第 2 行只有 6 个字符 ⇒ 必须**夹到行尾**（不是拖过换行去吃下一行）")
        XCTAssertEqual(selection[0].length, selection[2].length, "宽窄相同的两行取到的列宽必须一致")
        XCTAssertGreaterThan(selection[0].length, selection[1].length, "夹具前提：第 1 行确实比第 2 行长")
        for range in selection {
            let selected = (textView.string as NSString).substring(with: range)
            XCTAssertFalse(selected.contains("\n"), "列选**绝不跨换行**")
        }
        try host.capture(name: "interaction-editor-column-selection")

        // 列选下打字：逐行各替换掉自己那一段 ⇒ 短的那一行整行被换掉，且一次撤销全回退
        let original = textView.string
        let width = selection[0].length
        textView.insertText("#", replacementRange: textView.selectedRange())
        let lines = textView.string.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "#" + original.split(separator: "\n", omittingEmptySubsequences: false)[0].dropFirst(width), "第 1 行该被替换掉前 \(width) 列")
        XCTAssertEqual(lines[1], "#", "第 2 行整行都被换掉了（那一行只有 6 个字符）")
        XCTAssertEqual(lines[2], "#" + original.split(separator: "\n", omittingEmptySubsequences: false)[2].dropFirst(width), "第 3 行同理")
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, original, "列选那一批同样是一次撤销")
    }
}
