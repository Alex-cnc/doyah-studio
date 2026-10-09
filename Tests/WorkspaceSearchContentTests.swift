import XCTest
@testable import DoyahCore

/// 内容检索 —— `FR-EDIT-44`（工作区标头搜索框）与 `FR-EDIT-42`（跨文件搜索）**共用的一套引擎**。
///
/// 三层判据：① 命中准确（行号 1 起、摘要不改写原文、按文件分组、组内按行号）；
/// ② **跳过 ≠ 通过**（二进制 / 超大 / 读不了各记一笔，数得出来）；
/// ③ **唯一出处**（匹配谓词只在 `Core/WorkspaceSearch.swift` 一处，界面不许自造一套）。
final class WorkspaceSearchContentTests: XCTestCase {

    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent("ws-content-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try write("Core/a.swift", "let agent = 1\n// 第二行\nlet loop = agent\n")
        try write("Core/b.swift", "AGENT 大写\n什么都\n")
        try write("Core/cafe.md", "cafe 没有重音\n")
        try write("Core/many.txt", (1...5).map { "行 \($0) agent" }.joined(separator: "\n") + "\n")
        try write("Core/big.txt", (1...100).map { "agent \($0)" }.joined(separator: "\n") + "\n")
        try write("node_modules/dep.txt", "agent 在依赖里\n")
        try write("notes/deep/deeper/agent.txt", "deep agent\n")
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

    private func group(_ result: WorkspaceSearch.ContentResult, _ path: String) -> WorkspaceSearch.ContentGroup? {
        result.groups.first { $0.entry.relativePath == path }
    }

    private func source(_ relative: String) throws -> String {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repo.appendingPathComponent(relative), encoding: .utf8)
    }

    // MARK: - ① 命中准确

    /// 行号 1 起、摘要 = 该行原文去首尾空白（**不改写**），按文件分组。
    func testHitsCarryLineNumbersAndSnippets() {
        let result = WorkspaceSearch.findContents(in: root, query: "agent")
        guard let a = group(result, "Core/a.swift") else { return XCTFail("Core/a.swift 应当有命中") }
        XCTAssertEqual(a.hits.map(\.line), [1, 3], "行号必须 1 起、按行序")
        XCTAssertEqual(a.hits.first?.snippet, "let agent = 1")
        XCTAssertEqual(a.hits.last?.snippet, "let loop = agent")
        XCTAssertEqual(a.id, "Core/a.swift")
    }

    /// 组内按行号升序、组间按路径升序 —— 不随扫描顺序漂。
    func testOrderingIsDeterministic() {
        let result = WorkspaceSearch.findContents(in: root, query: "agent")
        let paths = result.groups.map(\.entry.relativePath)
        XCTAssertEqual(paths, paths.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        for g in result.groups {
            XCTAssertEqual(g.hits.map(\.line), g.hits.map(\.line).sorted(), "\(g.id) 组内行号乱了")
        }
    }

    /// 大小写不敏感（与文件名搜索**同一个谓词**）。
    func testMatchesCaseInsensitively() {
        let result = WorkspaceSearch.findContents(in: root, query: "agent")
        XCTAssertEqual(group(result, "Core/b.swift")?.hits.first?.snippet, "AGENT 大写")
    }

    /// 变音符号不敏感：搜 `café` 也找得到写的是 `cafe` 的那一行。
    func testMatchesDiacriticInsensitively() {
        let result = WorkspaceSearch.findContents(in: root, query: "café")
        XCTAssertEqual(group(result, "Core/cafe.md")?.hits.first?.line, 1)
    }

    /// 查询词首尾空白先归一（`"  agent  "` 与 `"agent"` 同答）。
    func testQueryIsNormalized() {
        let a = WorkspaceSearch.findContents(in: root, query: "  agent  ")
        let b = WorkspaceSearch.findContents(in: root, query: "agent")
        XCTAssertEqual(a.groups.map(\.id), b.groups.map(\.id))
    }

    // MARK: - ② 有界：忽略名单 / 深度 / 符号链接

    func testRespectsIgnoreList() {
        let result = WorkspaceSearch.findContents(in: root, query: "agent")
        XCTAssertNil(group(result, "node_modules/dep.txt"), "忽略名单里的目录不许被读")
        XCTAssertTrue(result.groups.allSatisfy { !$0.id.hasPrefix("node_modules/") })
    }

    func testRespectsDepthLimit() {
        let shallow = WorkspaceSearch.findContents(in: root, query: "agent", maxDepth: 2)
        XCTAssertNil(group(shallow, "notes/deep/deeper/agent.txt"))
        let deep = WorkspaceSearch.findContents(in: root, query: "agent", maxDepth: 8)
        XCTAssertEqual(group(deep, "notes/deep/deeper/agent.txt")?.hits.first?.line, 1)
    }

    /// 不跟随符号链接（跟随会走出工作区，也会把同一个文件数两遍）。
    func testDoesNotFollowSymlinks() throws {
        try fileManager.createSymbolicLink(
            at: root.appendingPathComponent("link"),
            withDestinationURL: root.appendingPathComponent("Core")
        )
        let result = WorkspaceSearch.findContents(in: root, query: "agent")
        XCTAssertTrue(result.groups.allSatisfy { !$0.id.hasPrefix("link/") }, "符号链接被跟随了")
    }

    // MARK: - ③ 跳过 ≠ 通过 + 上限如实标记

    func testBinaryFilesAreSkippedAndCounted() {
        let result = WorkspaceSearch.findContents(in: root, query: "agent")
        XCTAssertEqual(result.skips.binary, 1, "bin.dat 应当被记成二进制一笔")
        XCTAssertFalse(result.skips.isEmpty)
        XCTAssertEqual(result.skips.total, result.skips.binary + result.skips.tooLarge + result.skips.unreadable)
    }

    func testLargeFilesAreSkippedAndCounted() {
        let result = WorkspaceSearch.findContents(in: root, query: "agent", maxFileSize: 16)
        XCTAssertNil(group(result, "Core/big.txt"), "超过上限的文件不许被读")
        XCTAssertGreaterThanOrEqual(result.skips.tooLarge, 1)
    }

    func testPerFileLimitCapsHitsInsideOneFile() {
        let result = WorkspaceSearch.findContents(in: root, query: "agent", perFileLimit: 3)
        XCTAssertEqual(group(result, "Core/big.txt")?.hits.count, 3)
        XCTAssertFalse(result.isTruncated, "只到每文件上限 ≠ 整体截断")
    }

    func testTotalLimitIsReported() {
        let result = WorkspaceSearch.findContents(in: root, query: "agent", limit: 2)
        XCTAssertEqual(result.hitCount, 2)
        XCTAssertTrue(result.isTruncated)
    }

    func testEmptyQueryReturnsEmptyResult() {
        let result = WorkspaceSearch.findContents(in: root, query: "   ")
        XCTAssertTrue(result.groups.isEmpty)
        XCTAssertEqual(result.scannedFiles, 0, "空查询不该读盘")
        XCTAssertTrue(result.skips.isEmpty, "没读盘就没有跳过可报")
    }

    func testSnippetIsTruncatedWithEllipsis() throws {
        try write("Core/long.txt", "agent " + String(repeating: "x", count: 60) + "\n")
        let result = WorkspaceSearch.findContents(in: root, query: "agent", snippetLimit: 12)
        guard let snippet = group(result, "Core/long.txt")?.hits.first?.snippet else {
            return XCTFail("Core/long.txt 应当有命中")
        }
        XCTAssertTrue(snippet.hasSuffix("…"))
        XCTAssertEqual(snippet.count, 13, "12 个字符 + 一个省略号")
    }

    /// 真正读了内容才计数（二进制 / 超大 / 忽略名单里的都不算）。
    func testScannedFilesCountsOnlyFilesActuallyRead() {
        let result = WorkspaceSearch.findContents(in: root, query: "agent")
        XCTAssertEqual(result.scannedFiles, 6)
    }

    // MARK: - ④ 唯一出处（界面不许自造第二套匹配）

    private func swiftSources(under relative: String) throws -> [URL] {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        var out: [URL] = []
        let walker = fileManager.enumerator(at: repo.appendingPathComponent(relative), includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            if url.pathExtension == "swift" { out.append(url) }
        }
        return out
    }

    /// 匹配谓词只许有一处：那两个 helper 在 Core + App 里各只出现一次。
    func testPredicateHasExactlyOneDefinition() throws {
        var matchCount = 0
        var normalizeCount = 0
        for dir in ["Core", "App"] {
            for file in try swiftSources(under: dir) {
                let text = try String(contentsOf: file, encoding: .utf8)
                matchCount += text.components(separatedBy: "static func matches(_ text: String").count - 1
                normalizeCount += text.components(separatedBy: "static func normalize(query: String)").count - 1
            }
        }
        XCTAssertEqual(matchCount, 1, "匹配谓词必须只有一个定义")
        XCTAssertEqual(normalizeCount, 1, "查询归一化必须只有一个定义")
    }

    /// 文件名搜索也走同一个谓词（不许回到自己那套 `localizedCaseInsensitiveContains`）。
    ///
    /// **先剥注释再判**（`AGENT-SPEC` §9 第 118 条）：说明文字里会引用那个坏例子，
    /// 拿整份文件搜子串会把注释当成命中 —— 这条判据初版就是这么误报的。
    func testFileNameSearchUsesTheSamePredicate() throws {
        let code = try codeOnly(source("Core/WorkspaceSearch.swift"))
        XCTAssertTrue(code.contains("matches(entry.name, normalizedQuery: needle)"),
                      "文件名搜索必须与内容搜索同谓词；锚点变了请更新这条判据，不要删掉它")
        XCTAssertFalse(code.contains("localizedCaseInsensitiveContains"))
    }

    /// 只留代码行（去掉 `//` 注释行）—— 判据扫源码前的第一步。
    private func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// 界面侧不许自造匹配谓词（`FR-EDIT-44` 与 `FR-EDIT-42` 共用一套引擎）。
    func testAppDoesNotRollItsOwnMatcher() throws {
        for file in try swiftSources(under: "App") {
            let text = codeOnly(try String(contentsOf: file, encoding: .utf8))
            XCTAssertFalse(text.contains("localizedCaseInsensitiveContains"),
                           "\(file.lastPathComponent) 自造了匹配谓词 —— 应改走 Core/WorkspaceSearch")
            XCTAssertFalse(text.contains("precomposedStringWithCanonicalMapping"),
                           "\(file.lastPathComponent) 自己归一化了查询 —— 应改走 Core/WorkspaceSearch")
        }
    }

    // MARK: - ⑤ 替换计划（FR-EDIT-42 的另一半：差异预览 / 可撤销 / 行尾保真 / 规则同源）

    /// 取某个相对路径的条目（构造 `replaceLine` 的入参）。
    private func entry(for relative: String) throws -> WorkspaceEntry {
        let url = root.appendingPathComponent(relative)
        let children = try WorkspaceTree.children(of: url.deletingLastPathComponent(), relativeTo: root)
        guard let found = children.first(where: { $0.relativePath == relative }) else {
            throw NSError(domain: "WorkspaceSearchContentTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "没有这个条目：\(relative)"])
        }
        return found
    }

    /// 计划给出**逐行差异预览**，且替换后的完整内容与预览出自同一次计算。
    func testReplacePlanCarriesPreviewAndReplacedText() {
        let plan = WorkspaceSearch.replacePlan(in: root, query: "agent", replacement: "runner")
        guard let a = plan.files.first(where: { $0.entry.relativePath == "Core/a.swift" }) else {
            return XCTFail("Core/a.swift 应当进计划")
        }
        XCTAssertEqual(a.count, 2)
        XCTAssertEqual(a.changes.map(\.line), [1, 3], "行号必须 1 起、带原文")
        XCTAssertEqual(a.changes.first?.before, "let agent = 1")
        XCTAssertEqual(a.changes.first?.after, "let runner = 1")
        XCTAssertEqual(a.replaced, "let runner = 1\n// 第二行\nlet loop = runner\n")
        XCTAssertEqual(plan.changeCount, plan.files.reduce(0) { $0 + $1.count })
    }

    /// 只改命中的那些字符，其余一字不动；大小写不敏感也照改。
    func testReplaceTouchesOnlyMatchedCharacters() {
        let lower = WorkspaceSearch.applyToLine(
            "let agent = 1; // agent", normalizedQuery: "agent", replacement: "runner"
        )
        XCTAssertEqual(lower.text, "let runner = 1; // runner")
        XCTAssertEqual(lower.count, 2)

        let upper = WorkspaceSearch.applyToLine(
            "AGENT 大写", normalizedQuery: WorkspaceSearch.normalize(query: "agent"), replacement: "x"
        )
        XCTAssertEqual(upper.text, "x 大写")
        XCTAssertEqual(upper.count, 1)

        let none = WorkspaceSearch.applyToLine(
            "没有那个词", normalizedQuery: "agent", replacement: "x"
        )
        XCTAssertEqual(none.text, "没有那个词")
        XCTAssertEqual(none.count, 0)
    }

    /// **空查询一律拒绝**（灾难的入口），换成同一个词也拒绝。
    func testReplacePlanRefusesEmptyAndIdenticalQuery() {
        XCTAssertTrue(WorkspaceSearch.replacePlan(in: root, query: "   ", replacement: "x").isEmpty)
        XCTAssertTrue(WorkspaceSearch.replacePlan(in: root, query: "agent", replacement: "agent").isEmpty)
        XCTAssertTrue(WorkspaceSearch.replacePlan(in: root, query: "nomatchhere", replacement: "x").isEmpty)
    }

    /// **排除规则同源**：忽略名单里的文件不进替换计划；二进制与检索同 —— 记一笔跳过，不假装改过。
    func testReplacePlanSharesTheSameIgnoreRules() {
        let plan = WorkspaceSearch.replacePlan(in: root, query: "agent", replacement: "runner")
        XCTAssertNil(plan.files.first { $0.entry.relativePath.hasPrefix("node_modules/") },
                     "忽略名单里的目录不许进替换计划")
        XCTAssertEqual(plan.skips.binary, 1, "二进制文件与检索同：记一笔跳过")
        XCTAssertNotNil(plan.files.first { $0.entry.relativePath == "Core/a.swift" })

        // 调用方给的忽略名单同样生效（与内容检索同一条口径）。
        let custom = WorkspaceSearch.replacePlan(in: root, query: "agent", replacement: "runner",
                                                ignored: ["notes"])
        XCTAssertNil(custom.files.first { $0.entry.relativePath.hasPrefix("notes/") })
    }

    /// **唯一出处（机器判据）**：内容检索与替换计划**共用**同一套规则 ——
    /// 匹配选项一处、跳过判定各一处（都在 `readTextFile` 里）。
    func testReplaceReusesTheEnginesSingleSourceRules() throws {
        let code = try codeOnly(source("Core/WorkspaceSearch.swift"))
        XCTAssertEqual(code.components(separatedBy: "[.caseInsensitive, .diacriticInsensitive]").count - 1, 1,
                       "匹配选项必须只有一处（检索与替换读同一张表）")
        for needle in ["skips.binary += 1", "skips.tooLarge += 1", "skips.unreadable += 1"] {
            XCTAssertEqual(code.components(separatedBy: needle).count - 1, 1,
                           "\(needle) 必须只有一处（检索与替换共用 readTextFile）")
        }
        XCTAssertTrue(code.contains("static func scanTextFiles("),
                      "有界遍历骨架必须是一处共用的（改了锚点请更新这条判据，不要删掉它）")
    }

    /// **行尾保真**：CRLF 的文件替换后不整篇变成 LF；LF 的仍是 LF；混排逐行保留、不多空行。
    func testReplacePreservesLineEndings() throws {
        try write("Core/crlf.txt", "TARGET first\r\nTARGET second\r\n")
        try write("Core/lf.txt", "TARGET first\nTARGET second\n")
        try write("Core/mixed.txt", "TARGET a\nTARGET b\r\nTARGET c")

        let plan = WorkspaceSearch.replacePlan(in: root, query: "target", replacement: "done")
        let crlf = plan.files.first { $0.entry.relativePath == "Core/crlf.txt" }?.replaced
        XCTAssertEqual(crlf, "done first\r\ndone second\r\n", "CRLF 必须原样保留")
        XCTAssertFalse(crlf?.contains("\n\n") ?? true, "不该多出空行")
        let lf = plan.files.first { $0.entry.relativePath == "Core/lf.txt" }?.replaced
        XCTAssertEqual(lf, "done first\ndone second\n", "LF 仍是 LF")
        let mixed = plan.files.first { $0.entry.relativePath == "Core/mixed.txt" }?.replaced
        XCTAssertEqual(mixed, "done a\ndone b\r\ndone c", "混排逐行保留")
    }

    /// **全量替换可撤销**：落盘 → 原文确实变了 → 撤销 → 逐字节回到原文。
    func testReplaceAllIsUndoable() throws {
        let before = try String(contentsOf: root.appendingPathComponent("Core/a.swift"), encoding: .utf8)
        let plan = WorkspaceSearch.replacePlan(in: root, query: "agent", replacement: "runner")
        XCTAssertFalse(plan.isEmpty)

        guard let undo = WorkspaceSearch.apply(plan, in: root) else { return XCTFail("落盘应当成功") }
        XCTAssertEqual(undo.fileCount, plan.fileCount)
        let after = try String(contentsOf: root.appendingPathComponent("Core/a.swift"), encoding: .utf8)
        XCTAssertEqual(after, "let runner = 1\n// 第二行\nlet loop = runner\n")

        XCTAssertTrue(WorkspaceSearch.revert(undo, in: root))
        let restored = try String(contentsOf: root.appendingPathComponent("Core/a.swift"), encoding: .utf8)
        XCTAssertEqual(restored, before, "撤销必须逐字节回到原文")
    }

    /// **单条替换**只改那一行，别的行不动；落盘 / 撤销与全部替换走同一条路。
    func testSingleLineReplaceTouchesOnlyThatLine() throws {
        let path = "Core/many.txt"
        let original = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        let plan = WorkspaceSearch.replaceLine(
            in: root, query: "agent", replacement: "runner", entry: try entry(for: path), line: 2
        )
        guard let file = plan.files.first else { return XCTFail("单条替换应当给出计划") }
        XCTAssertEqual(file.changes.map(\.line), [2])
        XCTAssertEqual(file.count, 1)

        guard let undo = WorkspaceSearch.apply(plan, in: root) else { return XCTFail("落盘应当成功") }
        let replaced = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        XCTAssertTrue(replaced.contains("行 2 runner"))
        XCTAssertTrue(replaced.contains("行 1 agent"), "别的行不许动")
        XCTAssertTrue(replaced.contains("行 5 agent"))

        _ = WorkspaceSearch.revert(undo, in: root)
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8), original
        )
    }
}
