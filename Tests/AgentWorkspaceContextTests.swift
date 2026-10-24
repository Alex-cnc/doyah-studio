import XCTest
@testable import DoyahCore

/// `FR-AI-22` 工作区上下文（当前文件 / 选中 / 终端尾部 / 目录）：
/// **带不带、谁在前、留头还是留尾，都要能被断言**。
final class AgentWorkspaceContextTests: XCTestCase {

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

    func testEmptyFactsProduceNoSections() {
        XCTAssertTrue(AgentWorkspaceContext.references(from: AgentWorkspaceFacts()).isEmpty)
    }

    func testWhitespaceOnlyFileIsNotAttached() {
        let facts = AgentWorkspaceFacts(activeFile: (path: "a.swift", text: "   \n\n  "))
        XCTAssertTrue(AgentWorkspaceContext.references(from: facts).isEmpty, "空白正文不该占预算")
    }

    // MARK: - 顺序与去重

    func testSelectionComesBeforeFile() {
        let facts = AgentWorkspaceFacts(
            activeFile: (path: "Sources/a.swift", text: "line1\nline2\nline3"),
            selection: (path: "Sources/a.swift", text: "line2", firstLine: 2))
        XCTAssertEqual(kinds(AgentWorkspaceContext.references(from: facts)), ["selection", "file"],
                       "用户指的那段要在前头")
    }

    func testSelectionEqualToWholeFileIsAttachedOnce() {
        let whole = "struct A {}\n"
        let facts = AgentWorkspaceFacts(
            activeFile: (path: "A.swift", text: whole),
            selection: (path: "A.swift", text: whole, firstLine: 1))
        XCTAssertEqual(kinds(AgentWorkspaceContext.references(from: facts)), ["selection"],
                       "选中就是整份文件 ⇒ 不重复带")
    }

    // MARK: - 终端只留尾

    func testTerminalKeepsTailLinesOnly() {
        let lines = (1...200).map { "line\($0)" }
        let facts = AgentWorkspaceFacts(terminalText: lines.joined(separator: "\n"))
        let refs = AgentWorkspaceContext.references(from: facts)
        XCTAssertEqual(kinds(refs), ["terminalTail"])
        guard case .terminalTail(let text) = refs[0] else { return XCTFail("应是终端段") }
        let head = text.split(separator: "\n").first.map(String.init) ?? ""
        XCTAssertEqual(head, "line\(200 - AgentWorkspaceContext.maxTerminalLines + 1)",
                       "最前面应该正好是保留的第一行 —— 留下的必须是**尾部**")
        XCTAssertTrue(text.hasSuffix("line200"), "最后一行必须在")
        XCTAssertEqual(text.split(separator: "\n").count, AgentWorkspaceContext.maxTerminalLines)
    }

    func testTerminalTrailingBlankLinesAreDropped() {
        let facts = AgentWorkspaceFacts(terminalText: "a\nb\n\n\n")
        guard case .terminalTail(let text)? = AgentWorkspaceContext.references(from: facts).first else {
            return XCTFail("应带终端段")
        }
        XCTAssertEqual(text, "a\nb")
    }

    func testShortTerminalIsKeptWhole() {
        let facts = AgentWorkspaceFacts(terminalText: "one\ntwo")
        guard case .terminalTail(let text)? = AgentWorkspaceContext.references(from: facts).first else {
            return XCTFail("应带终端段")
        }
        XCTAssertEqual(text, "one\ntwo")
    }

    // MARK: - 目录：只在没有文件时

    func testDirectoryOnlyWhenNoFileIsOpen() {
        let noFile = AgentWorkspaceFacts(workspacePath: "/w", workspaceEntries: ["a", "b"])
        XCTAssertEqual(kinds(AgentWorkspaceContext.references(from: noFile)), ["directory"])

        let withFile = AgentWorkspaceFacts(activeFile: (path: "/w/a.swift", text: "x"),
                                           workspacePath: "/w", workspaceEntries: ["a", "b"])
        XCTAssertEqual(kinds(AgentWorkspaceContext.references(from: withFile)), ["file"],
                       "有文件时不再列目录（重复占预算）")
    }

    func testDirectoryEntriesAreCapped() {
        let entries = (1...200).map { "f\($0)" }
        let facts = AgentWorkspaceFacts(workspacePath: "/w", workspaceEntries: entries)
        guard case .directory(_, let listed)? = AgentWorkspaceContext.references(from: facts).first else {
            return XCTFail("应带目录段")
        }
        XCTAssertEqual(listed.count, AgentWorkspaceContext.maxDirectoryEntries)
        XCTAssertEqual(listed.first, "f1", "按给定顺序取前 N 条，不重排")
    }

    // MARK: - 与组装器合起来（截断要如实）

    func testAssemblerMarksTruncationForOversizedFile() {
        let big = String(repeating: "x", count: 50_000)
        let facts = AgentWorkspaceFacts(activeFile: (path: "big.txt", text: big))
        let payload = AgentContextAssembler.assemble(AgentWorkspaceContext.references(from: facts))
        XCTAssertEqual(payload.truncatedSections.count, 1, "超限必须如实标截断")
        XCTAssertTrue(payload.text.contains("[truncated]"))
    }

    func testSecretsInsideFileAreRedactedAndCounted() {
        let facts = AgentWorkspaceFacts(activeFile: (path: "cfg", text: "api_key = sk-ABCDEFGH12345678\n"))
        let payload = AgentContextAssembler.assemble(AgentWorkspaceContext.references(from: facts))
        XCTAssertGreaterThan(payload.totalRedactedSecrets, 0, "密钥片段必须被挡并计数")
        XCTAssertFalse(payload.text.contains("sk-ABCDEFGH12345678"))
    }

    func testAllFourSectionsTogetherKeepStableOrder() {
        let facts = AgentWorkspaceFacts(
            activeFile: (path: "a.swift", text: "body"),
            selection: (path: "a.swift", text: "sel", firstLine: 3),
            terminalText: "t1\nt2",
            workspacePath: "/w",
            workspaceEntries: ["x"])
        XCTAssertEqual(kinds(AgentWorkspaceContext.references(from: facts)),
                       ["selection", "file", "terminalTail"],
                       "有文件时不带目录；顺序 selection → file → terminal")
    }
}
