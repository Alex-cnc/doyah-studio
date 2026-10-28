import XCTest
@testable import DoyahCore

/// 项目规则文件（`FR-AGT-KNOW-CTX-003`）的机械判据。
///
/// 最容易被做松的三处，逐条钉住：
/// 1. **找不到要能说清找了哪几处**（否则「没读到规则」会被当成「没有规则」）；
/// 2. **路径跟正文一起**（同一句话从哪份文件来，含义不同）；
/// 3. **只读**：读一遍不许在磁盘上多出任何东西。
final class AgentProjectRulesTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-project-rules-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relativePath: String, _ text: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - 判据 ①：没有规则也要说清找了哪几处

    func testNoRulesFoundReportsWhereItLooked() {
        let result = AgentProjectRules.load(workspacePath: root.path)
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(result.searchedPaths.contains("AGENTS.md"))
        XCTAssertTrue(result.searchedPaths.contains("DOYAH.md"))
        XCTAssertTrue(result.searchedPaths.contains(".doyah/rules"))
        XCTAssertEqual(result.skippedFiles, 0)
    }

    func testNilWorkspaceIsEmptyButStillSearched() {
        let result = AgentProjectRules.load(workspacePath: nil)
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.searchedPaths, ["AGENTS.md", "DOYAH.md", ".doyah/rules"])
    }

    // MARK: - 判据 ②：路径跟正文一起，顺序稳定

    func testRootFilesAreReadWithTheirPaths() throws {
        try write("AGENTS.md", "发布前先跑 verify-core")
        try write("DOYAH.md", "文件名用中文，标识符用英文")

        let result = AgentProjectRules.load(workspacePath: root.path)
        XCTAssertEqual(result.sources.map(\.relativePath), ["AGENTS.md", "DOYAH.md"])
        XCTAssertEqual(result.sources.first?.text, "发布前先跑 verify-core")
        XCTAssertEqual(result.sources.last?.text, "文件名用中文，标识符用英文")
        XCTAssertEqual(result.truncatedCharacters, 0)
    }

    func testRulesDirectoryReadsMarkdownSortedAndIgnoresOthers() throws {
        try write(".doyah/rules/20-发布.md", "打 tag 前对账")
        try write(".doyah/rules/10-门禁.md", "三门全绿才提交")
        try write(".doyah/rules/notes.txt", "不是 markdown，不许读")

        let result = AgentProjectRules.load(workspacePath: root.path)
        XCTAssertEqual(result.sources.map(\.relativePath),
                       [".doyah/rules/10-门禁.md", ".doyah/rules/20-发布.md"])
        XCTAssertFalse(result.sources.contains { $0.relativePath.hasSuffix(".txt") })
    }

    func testEmptyFileIsSkippedInsteadOfCarriedAsEmptyShell() throws {
        try write("AGENTS.md", "   \n\n  ")
        let result = AgentProjectRules.load(workspacePath: root.path)
        XCTAssertTrue(result.isEmpty, "空白文件不许变成一条空规则")
    }

    // MARK: - 判据 ③：有界且如实报

    func testPerFileLimitTruncatesAndSaysHowMuch() throws {
        let long = String(repeating: "规", count: 120)
        try write("AGENTS.md", long)
        let result = AgentProjectRules.load(workspacePath: root.path,
                                            limits: .init(maxCharactersPerFile: 50, maxTotalCharacters: 1_000))
        XCTAssertEqual(result.sources.first?.text.count, 50)
        XCTAssertEqual(result.sources.first?.truncatedCharacters, 70)
        XCTAssertEqual(result.truncatedCharacters, 70)
    }

    func testTotalBudgetSkipsTheRestAndReportsCount() throws {
        try write("AGENTS.md", String(repeating: "a", count: 30))
        try write("DOYAH.md", String(repeating: "b", count: 30))
        let result = AgentProjectRules.load(workspacePath: root.path,
                                            limits: .init(maxCharactersPerFile: 100, maxTotalCharacters: 30))
        XCTAssertEqual(result.sources.count, 1, "预算用完就不再带后面的")
        XCTAssertEqual(result.skippedByBudget, 1, "跳过几份要报出来")
    }

    func testUnreadableFileIsCountedNotFatal() throws {
        let url = root.appendingPathComponent("AGENTS.md")
        try Data([0xFF, 0xFE, 0xFF]).write(to: url)
        try write("DOYAH.md", "还能读的那份")
        let result = AgentProjectRules.load(workspacePath: root.path)
        XCTAssertEqual(result.skippedFiles, 1)
        XCTAssertEqual(result.sources.map(\.relativePath), ["DOYAH.md"], "坏的跳过，好的照读")
    }

    // MARK: - 判据 ④：只读，不新建

    func testLoadingCreatesNothingOnDisk() throws {
        try write("AGENTS.md", "规矩")
        let before = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        _ = AgentProjectRules.load(workspacePath: root.path)
        let after = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        XCTAssertEqual(before, after, "读一遍不许在盘上多出东西（尤其不许新建空的 DOYAH.md）")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".doyah").path))
    }

    // MARK: - 进上下文的顺序：规矩在最前

    func testRulesGoFirstInWorkspaceContext() throws {
        try write("AGENTS.md", "规矩")
        let rules = AgentProjectRules.load(workspacePath: root.path).sources
        let facts = AgentWorkspaceFacts(workspacePath: root.path,
                                        workspaceEntries: ["AGENTS.md"],
                                        projectRules: rules)
        let refs = AgentWorkspaceContext.references(from: facts)
        guard case .projectRule(let path, let text) = refs.first else {
            return XCTFail("第一条应当是规则文件，实际是 \(refs.first.map(\.self) as Any)")
        }
        XCTAssertEqual(path, "AGENTS.md")
        XCTAssertEqual(text, "规矩")
    }
}
