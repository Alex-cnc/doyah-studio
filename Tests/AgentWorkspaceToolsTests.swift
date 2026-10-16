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

    // MARK: - edit_file：定点改代码（2026-10-16 · 人类主人令「AI 编程应该就是那个定点改代码」）

    /// 定点替换：**唯一命中**才换，其余一字不动。
    func testApplyingEditReplacesTheOnlyOccurrenceAndTouchesNothingElse() {
        let text = "第一行\nneedle 在这里\n第三行\n"
        XCTAssertEqual(AgentWorkspaceTools.applyingEdit(to: text, oldString: "needle", newString: "换掉了"),
                       "第一行\n换掉了 在这里\n第三行\n")
    }

    /// **两条硬线**：锚点 0 次命中（你不知道现在长什么样）与多次命中（你改的不是你想改的那一处）**都拒**。
    func testApplyingEditRefusesMissingOrAmbiguousAnchors() {
        let twice = "needle\nneedle\n"
        XCTAssertNil(AgentWorkspaceTools.applyingEdit(to: twice, oldString: "needle", newString: "x"),
                     "多次命中必须拒 —— 绝不替人猜\"第一处\"，那正是 AI 改代码最容易悄悄改错地方的地方")
        XCTAssertNil(AgentWorkspaceTools.applyingEdit(to: twice, oldString: "这段没有", newString: "x"),
                     "0 次命中必须拒")
        XCTAssertNil(AgentWorkspaceTools.applyingEdit(to: twice, oldString: "", newString: "x"),
                     "空锚点拒")
    }

    /// 备单要**带差异预览**，拒的时候要**如实报出命中几次**（0 与多次的处置理由不一样，不许混成一句"改不了"）。
    func testPrepareEditPreviewsTheDiffAndReportsAnchorHits() {
        guard case .needsApproval(let request) = tools.prepareEdit(path: "dir/other.md", oldString: "needle",
                                                                  newString: "换掉了") else {
            return XCTFail("唯一锚点应当能备单")
        }
        XCTAssertTrue(request.payload.contains("needle"), "审批单要带差异预览：\(request.payload)")
        XCTAssertFalse(request.fingerprint.isEmpty, "指纹不许空（兑单靠它）")

        guard case .refused(_, let detail) = tools.prepareEdit(path: "dir/other.md", oldString: "这段没有",
                                                              newString: "x") else {
            return XCTFail("锚点对不上应当拒")
        }
        XCTAssertEqual(detail, "anchorHits:0", "拒的时候要报出命中几次")
    }

    /// **未批准不落盘**（与 `write_file` 同一口径），批准后才改，且只改锚点那一处。
    func testEditFileWithoutApprovalLeavesTheDiskUntouched() throws {
        let url = root.appendingPathComponent("dir/other.md")
        let before = try String(contentsOf: url, encoding: .utf8)
        guard case .needsApproval(let request) = tools.prepareEdit(path: "dir/other.md", oldString: "needle",
                                                                  newString: "换掉了") else {
            return XCTFail("应当备单")
        }
        guard case .refused(let code, _) = tools.editFile(path: "dir/other.md", oldString: "needle",
                                                          newString: "换掉了",
                                                          fingerprint: request.fingerprint, granted: []) else {
            return XCTFail("没批准不该落盘")
        }
        XCTAssertEqual(code, .approvalRequired)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), before, "未批准时盘上必须一字未动")

        guard case .wrote(let output) = tools.editFile(path: "dir/other.md", oldString: "needle",
                                                       newString: "换掉了",
                                                       fingerprint: request.fingerprint,
                                                       granted: [request.fingerprint]) else {
            return XCTFail("批准后应当落盘")
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "别的文件里也有 换掉了\n")
        XCTAssertEqual(output.path, "dir/other.md")
    }

    /// 越界（工作区之外）一律拒 —— 与只读件同一道沙箱。
    func testEditFileRefusesPathsOutsideTheWorkspace() {
        guard case .refused(let code, _) = tools.prepareEdit(path: "../outside.txt", oldString: "a",
                                                             newString: "b") else {
            return XCTFail("越界必须拒")
        }
        XCTAssertEqual(code, .outsideWorkspace)
    }
}
