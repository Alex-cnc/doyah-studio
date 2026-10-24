import XCTest
@testable import DoyahCore

/// `FR-AI-22` ② 现场读数 → 上下文的换算：**选区取哪段、起始行第几、越界怎么办、空的是什么样**。
///
/// 这一层是把「编辑器给的 `NSRange`」翻成「模型看见的那段文字」的唯一一处 ——
/// 翻错了在界面上表现为「我明明选了这段，它改的是别处」，纯靠人眼看对话框发现不了。
final class AgentWorkspaceSnapshotTests: XCTestCase {

    private let document = "line1\nline2\nline3\nline4"

    private func kinds(_ refs: [AgentContextReference]) -> [String] {
        refs.map {
            switch $0 {
            case .file: return "file"
            case .directory: return "directory"
            case .selection: return "selection"
            case .activeTab: return "activeTab"
            case .terminalTail: return "terminalTail"
            case .schemaSummary: return "schemaSummary"
            case .gitState: return "gitState"
            }
        }
    }

    // MARK: - 空就是空

    func testNothingOpenProducesNoReferences() {
        let facts = AgentWorkspaceSnapshot.facts()
        XCTAssertTrue(AgentWorkspaceContext.references(from: facts).isEmpty,
                      "没有文件 / 选中 / 终端 ⇒ 一段都不带")
    }

    func testHomeTabHasNoFileSection() {
        // Home（或对话页签）没有路径：只带终端那一段，不编一个空文件出来。
        let facts = AgentWorkspaceSnapshot.facts(filePath: nil, text: nil,
                                                 terminalText: "$ ls\nAGENTS.md")
        XCTAssertEqual(kinds(AgentWorkspaceContext.references(from: facts)), ["terminalTail"])
    }

    // MARK: - 当前文件

    func testActiveFileIsAttached() {
        let facts = AgentWorkspaceSnapshot.facts(filePath: "Sources/a.swift", text: "let a = 1")
        let refs = AgentWorkspaceContext.references(from: facts)
        XCTAssertEqual(kinds(refs), ["file"])
        guard case .file(let path, let text) = refs[0] else { return XCTFail("应是文件段") }
        XCTAssertEqual(path, "Sources/a.swift")
        XCTAssertEqual(text, "let a = 1", "正文逐字，不做任何加工")
    }

    // MARK: - 选中

    func testCaretWithoutSelectionIsNotASelection() {
        // 光标（length == 0）不是「用户指了这儿」。
        let facts = AgentWorkspaceSnapshot.facts(filePath: "a.swift", text: document,
                                                 selection: NSRange(location: 7, length: 0))
        XCTAssertEqual(kinds(AgentWorkspaceContext.references(from: facts)), ["file"])
    }

    func testSelectionBecomesTextAndFirstLine() {
        // "line3" 在第三行（偏移 12）。
        let facts = AgentWorkspaceSnapshot.facts(filePath: "a.swift", text: document,
                                                 selection: NSRange(location: 12, length: 5))
        let refs = AgentWorkspaceContext.references(from: facts)
        XCTAssertEqual(kinds(refs), ["selection", "file"], "选中在前、文件在后")
        guard case .selection(let path, let text, let firstLine) = refs[0] else { return XCTFail("应是选中段") }
        XCTAssertEqual(path, "a.swift")
        XCTAssertEqual(text, "line3", "取到的是那一段，不是整篇")
        XCTAssertEqual(firstLine, 3)
    }

    func testSelectionSpanningLinesKeepsRawText() {
        // 跨两行：换行原样留着（模型要看见「选了几行」，不是被拼成一行）。
        let facts = AgentWorkspaceSnapshot.facts(filePath: "a.swift", text: document,
                                                 selection: NSRange(location: 6, length: 11))
        guard case .selection(_, let text, let firstLine)? = AgentWorkspaceContext.references(from: facts)
            .first(where: { if case .selection = $0 { return true } else { return false } }) else {
            return XCTFail("应有选中段")
        }
        XCTAssertEqual(text, "line2\nline3")
        XCTAssertEqual(firstLine, 2)
    }

    func testSelectionPastDocumentEndIsClippedNotDropped() {
        // 重建 / 外部同步的瞬间，视图里的偏移会比正文长一拍：夹到末尾，仍是那一段。
        let facts = AgentWorkspaceSnapshot.facts(filePath: "a.swift", text: document,
                                                 selection: NSRange(location: 12, length: 999))
        guard case .selection(_, let text, _)? = AgentWorkspaceContext.references(from: facts)
            .first(where: { if case .selection = $0 { return true } else { return false } }) else {
            return XCTFail("越界也该带上（夹到末尾）")
        }
        XCTAssertEqual(text, "line3\nline4")
    }

    func testSelectionStartingPastDocumentIsDropped() {
        // 起点就落在文档之外 ⇒ 这一刻没有可带的东西（不编、也不报错）。
        XCTAssertNil(AgentWorkspaceSnapshot.selectionText(in: document,
                                                          range: NSRange(location: 999, length: 3),
                                                          path: "a.swift"))
    }

    func testSelectionEqualToWholeDocumentIsAttachedOnce() {
        let facts = AgentWorkspaceSnapshot.facts(filePath: "a.swift", text: document,
                                                 selection: NSRange(location: 0, length: (document as NSString).length))
        XCTAssertEqual(kinds(AgentWorkspaceContext.references(from: facts)), ["selection"],
                       "选中就是整篇 ⇒ 不重复带文件段")
    }

    func testFirstLineCountsByDocumentNotByGuess() {
        XCTAssertEqual(AgentWorkspaceSnapshot.firstLine(ofUTF16Offset: 0, in: document), 1)
        XCTAssertEqual(AgentWorkspaceSnapshot.firstLine(ofUTF16Offset: 6, in: document), 2, "换行之后的第一个字符属于第二行")
        XCTAssertEqual(AgentWorkspaceSnapshot.firstLine(ofUTF16Offset: 5, in: document), 1, "换行符本身还属于上一行")
        XCTAssertEqual(AgentWorkspaceSnapshot.firstLine(ofUTF16Offset: 999, in: document), 4, "超出末尾按最后一行算")
    }

    // MARK: - 终端尾部

    func testTerminalTailIsKeptAsTail() {
        let lines = (1...200).map { "out\($0)" }.joined(separator: "\n")
        let facts = AgentWorkspaceSnapshot.facts(terminalText: lines)
        let refs = AgentWorkspaceContext.references(from: facts)
        XCTAssertEqual(kinds(refs), ["terminalTail"])
        guard case .terminalTail(let text) = refs[0] else { return XCTFail("应是终端段") }
        XCTAssertTrue(text.contains("out200"), "末尾必须在")
        XCTAssertFalse(text.contains("out1\n"), "开头应被裁掉")
    }
}
