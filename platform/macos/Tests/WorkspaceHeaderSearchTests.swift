import XCTest
@testable import DoyahCore

/// 标头搜索框的结果模型 —— `FR-EDIT-44`（工作区标头搜索框）的**界面半**判据。
///
/// 三层判据：① **两组的分组与顺序**（文件名在前 / 内容按文件分组且组内行号升序，
/// 键盘行走的顺序与渲染顺序是同一个）；② **同一份目录两次检索结果稳定**；
/// ③ **行号口径与编辑器同源** —— 命中给的行号换回位置后必须真的落在那一行
/// （「回车跳到命中行」全靠这条，两套数法的症状是静默跳到相邻行）。
final class WorkspaceHeaderSearchTests: XCTestCase {

    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent("ws-header-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try write("Core/agent.swift", "let agent = 1\n// 第二行\nlet loop = agent\n")
        try write("Core/other.swift", "无关内容\nagent 在第三行？\n真的在第二行\n")
        try write("Core/agent.md", "只有名字命中：这一行没有那个词\n")
        try write("node_modules/agent.txt", "agent 在依赖里\n")
        try binary("bin.dat", [0x41, 0x00, 0x42, 0x43])
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    private func write(_ relative: String, _ text: String) throws {
        let url = root.appendingPathComponent(relative)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func binary(_ relative: String, _ bytes: [UInt8]) throws {
        let url = root.appendingPathComponent(relative)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: url)
    }

    // MARK: - ① 分组与顺序

    /// 文件名命中在前、内容命中在后；两组的成员各自有序。
    func testFilesComeFirstThenContentInFileOrder() {
        let result = WorkspaceSearch.headerResults(in: root, query: "agent")
        XCTAssertEqual(result.files.map(\.relativePath), ["Core/agent.md", "Core/agent.swift"],
                       "文件名组按路径升序")
        let contentPaths = result.content.groups.map(\.entry.relativePath)
        XCTAssertEqual(contentPaths, ["Core/agent.swift", "Core/other.swift"],
                       "内容组按路径升序（只有真的读得出内容的文件）")
        XCTAssertEqual(result.contentHitCount, 3, "agent.swift 两处 + other.swift 一处")
    }

    /// 键盘行走的顺序 = 渲染的顺序（两份顺序不一致的症状：↑↓ 选中的行与高亮的行不是同一条）。
    func testKeyboardOrderIsTheRenderingOrder() {
        let result = WorkspaceSearch.headerResults(in: root, query: "agent")
        XCTAssertEqual(result.rows.count, result.files.count + result.contentHitCount)
        XCTAssertEqual(result.rows.prefix(result.files.count).compactMap { row -> String? in
            if case .file(let entry) = row { return entry.relativePath }
            return nil
        }, result.files.map(\.relativePath))
        let contentRows = result.rows.dropFirst(result.files.count).compactMap { row -> String? in
            if case .content(let hit) = row { return "\(hit.entry.relativePath)#\(hit.line)" }
            return nil
        }
        let expected = result.content.groups.flatMap { group -> [String] in
            group.hits.map { hit in "\(hit.entry.relativePath)#\(hit.line)" }
        }
        XCTAssertEqual(Array(contentRows), expected)
    }

    /// 一个文件可以同时出现在两组里（名字与内容都命中）；两行的 id 必须不同。
    func testSameFileCanAppearInBothGroups() {
        let result = WorkspaceSearch.headerResults(in: root, query: "agent")
        XCTAssertTrue(result.files.contains { $0.relativePath == "Core/agent.swift" })
        XCTAssertTrue(result.content.groups.contains { $0.entry.relativePath == "Core/agent.swift" })
        let ids = result.rows.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "行的 id 必须唯一（否则 ↑↓ 选中的是别的那条）")
    }

    /// 同一份目录两次检索结果稳定且有序（`FR-EDIT-44` 的判据原话）。
    func testResultsAreStableAcrossTwoRuns() {
        let first = WorkspaceSearch.headerResults(in: root, query: "agent")
        let second = WorkspaceSearch.headerResults(in: root, query: "agent")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.rows.map(\.id), second.rows.map(\.id))
        XCTAssertFalse(first.rows.isEmpty)
    }

    // MARK: - ② 有界：忽略名单 / 空查询 / 跳过与截断的透传

    func testIgnoreListAppliesToBothGroups() {
        let result = WorkspaceSearch.headerResults(in: root, query: "agent")
        XCTAssertFalse(result.rows.contains { $0.entry.relativePath.hasPrefix("node_modules/") },
                       "忽略名单对两组同时生效（同一个引擎）")
    }

    func testEmptyQueryReturnsEmptyAndDoesNotReadDisk() {
        let result = WorkspaceSearch.headerResults(in: root, query: "   ")
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.content.scannedFiles, 0, "空查询不该读盘")
        XCTAssertEqual(result, .empty)
    }

    /// **跳过 ≠ 通过**：二进制文件要计入「已跳过」，且不假装搜过。
    func testSkipsAreCarriedThrough() {
        let result = WorkspaceSearch.headerResults(in: root, query: "agent")
        XCTAssertEqual(result.skips.binary, 1)
        XCTAssertFalse(result.skips.isEmpty)
        XCTAssertFalse(result.rows.contains { $0.entry.relativePath == "bin.dat" })
    }

    /// 文件名组的上限触发时如实标记（内容组的截断另由 `ContentResult` 报）。
    func testTruncationIsReported() {
        let result = WorkspaceSearch.headerResults(in: root, query: "agent", fileLimit: 1)
        XCTAssertEqual(result.files.count, 1)
        XCTAssertTrue(result.filesTruncated)
        XCTAssertTrue(result.isTruncated)
    }

    // MARK: - ③ 行号口径与编辑器同源（「回车跳到命中行」的正确性）

    /// 命中行号必须与**编辑器的行号**是同一套数法：把命中行号换回位置后，
    /// 那个位置在原文里真的落在该行上。
    func testHitLineNumbersAreTheEditorsLineNumbers() throws {
        let text = try String(contentsOf: root.appendingPathComponent("Core/other.swift"), encoding: .utf8)
        let ns = text as NSString
        let result = WorkspaceSearch.headerResults(in: root, query: "agent")
        guard let group = result.content.groups.first(where: { $0.entry.relativePath == "Core/other.swift" }) else {
            return XCTFail("Core/other.swift 应当有命中")
        }
        for hit in group.hits {
            guard let range = CodeLines.range(ofLine: hit.line, in: text) else {
                return XCTFail("第 \(hit.line) 行换不出位置")
            }
            XCTAssertTrue(ns.substring(with: range).contains("agent"),
                          "第 \(hit.line) 行的原文里应当有命中的词")
            XCTAssertEqual(CodeLines.lineNumber(at: range.location, in: text), hit.line,
                           "行号换回位置再换回来必须回到同一行")
        }
    }

    /// `U+2028`（行分隔符）这类终止符上，旧写法（只按 `\\n` 切）与编辑器口径会差一行 ——
    /// 这条钉住「命中行号 = 编辑器行号」在同源之后仍成立。
    func testLineSeparatorTerminatorKeepsOneLineNumbering() throws {
        let text = "alpha agent\u{2028}beta agent\n"
        try write("Core/sep.txt", text)
        let result = WorkspaceSearch.headerResults(in: root, query: "agent")
        guard let group = result.content.groups.first(where: { $0.entry.relativePath == "Core/sep.txt" }) else {
            return XCTFail("Core/sep.txt 应当有命中")
        }
        XCTAssertEqual(group.hits.map(\.line), [1, 2], "U+2028 也算行终止符（与编辑器行号列同一份实现）")
        XCTAssertEqual(group.hits.map(\.snippet), ["alpha agent", "beta agent"])
        for hit in group.hits {
            guard let range = CodeLines.range(ofLine: hit.line, in: text) else {
                return XCTFail("第 \(hit.line) 行换不出位置")
            }
            XCTAssertTrue((text as NSString).substring(with: range).contains("agent"))
        }
    }

    // MARK: - ④ ↑↓ 的边界

    func testSelectionStaysInsideBounds() {
        let result = WorkspaceSearch.headerResults(in: root, query: "agent")
        XCTAssertGreaterThan(result.rows.count, 2)
        XCTAssertEqual(result.clamped(-5), 0)
        XCTAssertEqual(result.clamped(result.rows.count + 5), result.rows.count - 1)
        XCTAssertEqual(result.moved(from: 0, by: -1), 0, "第一行再按 ↑ 原地不动")
        XCTAssertEqual(result.moved(from: result.rows.count - 1, by: 1), result.rows.count - 1,
                       "最后一行再按 ↓ 原地不动")
        XCTAssertEqual(result.moved(from: 0, by: 1), 1)
    }

    func testSelectionOnEmptyResultsIsZero() {
        let result = WorkspaceSearch.headerResults(in: root, query: "这个词不存在")
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.clamped(3), 0)
        XCTAssertEqual(result.moved(from: 3, by: -1), 0)
    }
}
