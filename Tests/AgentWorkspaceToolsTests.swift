import XCTest
@testable import DoyahCore

/// `FR-AI-20` 第一片（沙箱 + 只读三件）的机械判据 —— 验收要点 ① 与 ②。
final class AgentWorkspaceToolsTests: XCTestCase {

    private var root: URL!
    private var tools: AgentWorkspaceTools!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dir"), withIntermediateDirectories: true)
        try "第一行\nneedle 在这里\n第三行\n".write(to: root.appendingPathComponent("needle-notes.txt"),
                                                atomically: true, encoding: .utf8)
        try "别的文件里也有 needle\n".write(to: root.appendingPathComponent("dir/other.md"),
                                          atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02, 0xFF, 0xFE]).write(to: root.appendingPathComponent("dir/blob.bin"))
        tools = AgentWorkspaceTools(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - ① 只读三件各自可跑

    func testReadFileReturnsTheOriginalText() {
        guard case .file(let output) = tools.readFile(path: "needle-notes.txt") else {
            return XCTFail("应当读到文件")
        }
        XCTAssertEqual(output.text, "第一行\nneedle 在这里\n第三行\n", "得**原文**（逐字）")
        XCTAssertEqual(output.path, "needle-notes.txt")
        XCTAssertFalse(output.truncated)
        XCTAssertEqual(output.totalBytes, output.text.utf8.count)
    }

    func testListDirectoryReturnsSortedEntriesWithDirectoryMarkers() {
        guard case .directory(let output) = tools.listDirectory(path: ".") else {
            return XCTFail("应当列出目录")
        }
        XCTAssertEqual(output.entries, ["dir/", "needle-notes.txt"], "目录带 `/`，且已排序")
        XCTAssertFalse(output.truncated)

        guard case .directory(let nested) = tools.listDirectory(path: "dir") else { return XCTFail("子目录也要能列") }
        XCTAssertEqual(nested.entries, ["blob.bin", "other.md"])
    }

    /// 一次查询里**文件名命中**与**内容命中**都要有（判据点名要求两类各 ≥1）。
    func testSearchHitsBothFileNamesAndContents() {
        guard case .search(let output) = tools.search(query: "needle") else {
            return XCTFail("应当返回搜索结果")
        }
        XCTAssertGreaterThanOrEqual(output.fileNames.count, 1, "文件名命中至少一条")
        XCTAssertTrue(output.fileNames.contains("needle-notes.txt"))
        XCTAssertGreaterThanOrEqual(output.contentHits.count, 2, "内容命中至少两条（两个文件各一条）")
        XCTAssertTrue(output.contentHits.contains { $0.hasPrefix("needle-notes.txt:2:") },
                      "内容命中要带相对路径与行号：\(output.contentHits)")
        XCTAssertTrue(output.contentHits.contains { $0.hasPrefix("dir/other.md:1:") })
        XCTAssertFalse(output.truncated)
    }

    // MARK: - ② 边界：`..` 与绝对路径两种写法都要被拒并报明原因

    func testPathsThatEscapeTheWorkspaceAreRefusedWithAReason() {
        // `..` 爬出去
        guard case .refused(let code, let detail) = tools.readFile(path: "../outside.txt") else {
            return XCTFail("`..` 逃逸必须被拒")
        }
        XCTAssertEqual(code, .outsideWorkspace)
        XCTAssertFalse(detail.isEmpty, "要报明原因（细节串带上实际路径）")

        // 绝对路径落在工作区外
        guard case .refused(let absoluteCode, let absoluteDetail) = tools.readFile(path: "/etc/hosts") else {
            return XCTFail("工作区外的绝对路径必须被拒")
        }
        XCTAssertEqual(absoluteCode, .outsideWorkspace)
        XCTAssertEqual(absoluteDetail, "/etc/hosts")

        // 列目录同样挡
        if case .refused(let code, _) = tools.listDirectory(path: "../../") {
            XCTAssertEqual(code, .outsideWorkspace)
        } else {
            XCTFail("列目录也要挡逃逸")
        }

        // 深层逃逸：先钻进子目录再爬出去
        if case .refused(let code, _) = tools.readFile(path: "dir/../../escape.txt") {
            XCTAssertEqual(code, .outsideWorkspace)
        } else {
            XCTFail("深层逃逸也要挡")
        }
    }

    /// **反向**：归一化后仍在工作区内的 `..` 是合法的 —— 挡的是「出去」，不是 `..` 本身。
    func testDotDotThatStaysInsideIsAllowed() {
        guard case .file(let output) = tools.readFile(path: "dir/../needle-notes.txt") else {
            return XCTFail("留在工作区内的 `..` 不该被拒")
        }
        XCTAssertEqual(output.path, "needle-notes.txt")
    }

    // MARK: - 附带：拒绝的其余档位与截断都要如实

    func testOtherRefusalsAndTruncationAreHonest() {
        if case .refused(let code, _) = tools.readFile(path: "不存在.txt") { XCTAssertEqual(code, .notFound) } else { XCTFail("缺文件要如实拒") }
        if case .refused(let code, _) = tools.readFile(path: "dir") { XCTAssertEqual(code, .notAFile) } else { XCTFail("对目录读文件要如实拒") }
        if case .refused(let code, _) = tools.listDirectory(path: "needle-notes.txt") { XCTAssertEqual(code, .notADirectory) } else { XCTFail("对文件列目录要如实拒") }
        if case .refused(let code, _) = tools.readFile(path: "dir/blob.bin") { XCTAssertEqual(code, .binaryFile) } else { XCTFail("二进制要如实拒，不许塞乱码") }
        if case .refused(let code, _) = tools.search(query: "   ") { XCTAssertEqual(code, .emptyQuery) } else { XCTFail("空查询要如实拒") }

        // 截断：上限调小 ⇒ truncated 为真且正文确实变短（**不静默**）
        let small = AgentWorkspaceTools(root: root, maxReadBytes: 8)
        guard case .file(let output) = small.readFile(path: "needle-notes.txt") else { return XCTFail("应当读到") }
        XCTAssertTrue(output.truncated, "超上限要标记截断")
        XCTAssertLessThan(output.text.utf8.count, output.totalBytes, "截断后正文要短于全文")
        XCTAssertGreaterThan(output.totalBytes, 8, "总字节数仍如实报")
        XCTAssertFalse(output.text.isEmpty, "按字符安全截断：不许把多字节字符切成半截 ⇒ 更不许退化成空")
    }

    /// 沙箱本身：`resolve` 是唯一一处判据，直接钉住它的两档。
    func testSandboxResolutionIsTheSingleSource() {
        XCTAssertEqual(AgentWorkspaceSandbox.resolve("a.txt", in: root), .inside(root.appendingPathComponent("a.txt").standardizedFileURL))
        if case .outside = AgentWorkspaceSandbox.resolve("/tmp/elsewhere.txt", in: root) {} else { XCTFail("工作区外要判 outside") }
        if case .outside = AgentWorkspaceSandbox.resolve("", in: root) {} else { XCTFail("空路径要判 outside") }
    }
}
