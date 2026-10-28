import AppKit
import XCTest
@testable import DoyahCore
@testable import DoyahStudioApp

/// `FR-STD-WS-EDIT-014` 的**接线**判据：两个编辑面真的走了同一套撤销收口。
///
/// 判定层（`UndoGranularityTests`）全绿只说明「算得对」。这条需求最容易悄悄坏掉的三处都在接线面上：
/// 1. 某个落地口自己写了一句 `didChangeText()`、绕过了收口 —— 那一步就没有动作名、也不断开；
/// 2. 某个动作把类别传错（移行按「键入」报）—— 菜单里出现「撤销 键入」而实际移了行；
/// 3. 等长替换（`⌘L`）把光标顶掉 —— 需求 ③ 明确禁止。
///
/// **这一层证明的是「那条路被走了」，不是「撤销层数对不对」**：无事件流的探针里 `NSTextView`
/// 会把整段改动并成一层，层数读数不可信（实测见 `.agent/evidence/2026-10-29-EDIT-014.md`）。
/// 所以①「连续输入合成一步」只能人工按 ⌘Z 点验 —— 台账里实现列因此保持 `🟡`。
final class UndoScopeWiringTests: XCTestCase {

    /// 动作名只可能取这两个之一（中英各一条）：**两条都写死在判据里**，不从被测实现现取
    /// （从实现取期望值 = 判据恒绿）。
    private func assertActionName(_ view: NSTextView, oneOf expected: (chinese: String, english: String),
                                  file: StaticString = #filePath, line: UInt = #line) {
        let name = view.undoManager?.undoActionName ?? ""
        XCTAssertTrue([expected.chinese, expected.english].contains(name),
                      "撤销动作名是「\(name)」，既不是「\(expected.chinese)」也不是「\(expected.english)」"
                      + " —— 这一步没走收口，或者类别传错了", file: file, line: line)
    }

    private func hostInWindow(_ view: NSTextView, text: String) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.allowsUndo = true
        view.string = text
        return window
    }

    // MARK: - 工作区编辑器

    func testMoveLinesNamesItsOwnUndoStep() {
        let view = CodeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let window = hostInWindow(view, text: "第一行\n第二行\n")
        defer { window.contentView = nil }
        view.completionLanguage = .swift
        view.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(view.moveLines(.down), "光标在首行，下移应当成立")
        XCTAssertEqual(view.string, "第二行\n第一行\n", "移行本身先要对")
        assertActionName(view, oneOf: ("移动行", "Move Lines"))

        view.undoManager?.undo()
        XCTAssertEqual(view.string, "第一行\n第二行\n", "一次撤销要把整次移动退回去（不是退一半）")
    }

    func testToggleCommentNamesItsOwnUndoStep() {
        let view = CodeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let window = hostInWindow(view, text: "let x = 1\n")
        defer { window.contentView = nil }
        view.completionLanguage = .swift
        view.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(view.toggleLineComment())
        assertActionName(view, oneOf: ("切换注释", "Toggle Comment"))
    }

    func testTaskToggleKeepsCaretBecauseTheReplacementIsEqualLength() {
        let view = CodeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let window = hostInWindow(view, text: "- [ ] 写文章\n")
        defer { window.contentView = nil }
        view.completionLanguage = .markdown
        // 光标停在方框之后很远的地方
        let caret = (view.string as NSString).range(of: "写文章").location + 1
        view.setSelectedRange(NSRange(location: caret, length: 0))

        XCTAssertTrue(view.toggleMarkdownTaskCheckbox())
        XCTAssertEqual(view.string, "- [x] 写文章\n", "只许动方框里那一个字符")
        XCTAssertEqual(view.selectedRange(), NSRange(location: caret, length: 0),
                       "等长替换把光标顶掉了（需求 ③）：用户按一次 ⌘L 光标就跳一下")
        assertActionName(view, oneOf: ("切换任务框", "Toggle Task"))

        view.undoManager?.undo()
        XCTAssertEqual(view.string, "- [ ] 写文章\n")
    }

    func testTaskToggleRefusesWithASelectionSoNothingIsDisplaced() {
        // 有选区时这个动作**不接**（`MarkdownListEditing.toggleTask` 只认零长度光标）：
        // 于是「等长替换会顶掉选区」这件事在这里根本不会发生 —— 按键交还系统，什么都不改。
        let view = CodeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let window = hostInWindow(view, text: "- [ ] 写文章\n")
        defer { window.contentView = nil }
        view.completionLanguage = .markdown
        let selected = (view.string as NSString).range(of: "写文章")
        view.setSelectedRange(selected)

        XCTAssertFalse(view.toggleMarkdownTaskCheckbox(), "有选区时它必须说「我不接」，不能吞掉这次按键")
        XCTAssertEqual(view.string, "- [ ] 写文章\n")
        XCTAssertEqual(view.selectedRange(), selected, "不接的时候连选区都不许动")
    }

    // MARK: - 数据库编辑器

    func testSQLGhostAcceptanceNamesItsOwnUndoStep() {
        let view = SQLTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let window = hostInWindow(view, text: "sel")
        defer { window.contentView = nil }
        view.setSelectedRange(NSRange(location: 3, length: 0))

        let suggestion = InlineGhostSuggestion(
            range: NSRange(location: 0, length: 3),
            insertText: "SELECT",
            ghost: "ECT",
            kind: .keyword,
            caretOffset: 6
        )
        XCTAssertTrue(view.applyGhost(suggestion))
        XCTAssertEqual(view.string, "SELECT")
        assertActionName(view, oneOf: ("补全", "Completion"))
    }

    // MARK: - 源树判据：收口只有一处、每个落地口都从它过

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ relative: String) throws -> String {
        let body = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        XCTAssertGreaterThan(body.count, 1500, "\(relative) 读到的内容太短，扫描面可疑")
        return body
    }

    private func count(_ needle: String, in body: String) -> Int {
        body.components(separatedBy: needle).count - 1
    }

    func testUndoScopeIsTheOnlyPlaceTouchingUndoManager() throws {
        let bridge = try text("App/Views/UndoScope.swift")
        XCTAssertTrue(bridge.contains("func performUndoable(_ kind: UndoEditKind"),
                      "收口函数不见了")
        // 只数**代码行**（注释里的反引号提及不算）：收口里应当在动手前与动手后各断开一次。
        let breakLines = bridge.split(separator: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces) == "breakUndoCoalescing()" }
        XCTAssertEqual(breakLines.count, 2,
                       "收口里应当在动手前与动手后各断开一次（少一处就等于没把这一步摘出来）")
        XCTAssertEqual(count("setActionName(", in: bridge), 1,
                       "动作名只许在收口里设一次")

        for (file, label) in [("App/Views/CodeEditorView.swift", "工作区编辑器"),
                              ("App/Views/SQLEditorView.swift", "SQL 编辑器")] {
            let body = try text(file)
            for forbidden in ["breakUndoCoalescing(", "setActionName(", "beginUndoGrouping(", "endUndoGrouping("] {
                XCTAssertFalse(body.contains(forbidden),
                               "\(label) 自己动了撤销分组（\(forbidden)）：两个编辑面会各有一套手感")
            }
            XCTAssertTrue(body.contains("var undoGranularity = UndoGranularity()"),
                          "\(label) 没有自己的粒度状态（共用一份会把 A 页签的动作名写到 B 上）")
        }
    }

    func testEveryTextMutationGoesThroughTheScope() throws {
        // 落地口径：一次用户动作 = 一次 `shouldChangeText → replaceCharacters → didChangeText`。
        // 于是「绕开收口」在源码上就表现为**多出一个没被收口包住的 `didChangeText()`**。
        for (file, label, extra) in [("App/Views/CodeEditorView.swift", "工作区编辑器", 0),
                                     ("App/Views/SQLEditorView.swift", "SQL 编辑器", 0)] {
            let body = try text(file)
            let mutations = count("didChangeText()", in: body) - count("textView.didChangeText()", in: body)
            let scoped = count("performUndoable(", in: body)
            XCTAssertEqual(mutations, scoped + extra,
                           "\(label)：文本改动 \(mutations) 处、收口只有 \(scoped) 处"
                           + "（容许的例外是整段外部载入那 \(extra) 处，它不进撤销栈）"
                           + " —— 有落地口绕过了收口，那一步既没有动作名也不会断开")
        }
    }

    func testBothEditorsDeclareTheSameScope() throws {
        let code = try text("App/Views/CodeEditorView.swift")
        XCTAssertTrue(code.contains("final class CodeTextView: NSTextView, UndoScopedEditor"))
        let sql = try text("App/Views/SQLEditorView.swift")
        XCTAssertTrue(sql.contains("final class SQLTextView: NSTextView, UndoScopedEditor"))
    }
}
