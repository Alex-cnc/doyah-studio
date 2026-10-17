import XCTest
@testable import DoyahCore

/// `FR-AI-20` 第二片（`write_file` 的差异与审批 / `run_command` 的白名单与沙箱）——
/// 验收要点 ③ ④ 的机械判据。
final class AgentToolApprovalTests: XCTestCase {

    private var root: URL!
    private var tools: AgentWorkspaceTools!

    /// 假执行器（记录调用，不真起进程）。
    private final class RecordingRunner: AgentCommandRunner, @unchecked Sendable {
        private(set) var calls: [(executable: String, arguments: [String], workingDirectory: URL)] = []
        var result = AgentCommandResult(exitCode: 0, standardOutput: "ok", standardError: "")

        func run(executable: String, arguments: [String], workingDirectory: URL) -> AgentCommandResult {
            calls.append((executable, arguments, workingDirectory))
            return result
        }
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-approval-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "旧内容第一行\n旧内容第二行\n".write(to: root.appendingPathComponent("target.txt"),
                                            atomically: true, encoding: .utf8)
        tools = AgentWorkspaceTools(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func bytes(of relativePath: String) -> Data? {
        try? Data(contentsOf: root.appendingPathComponent(relativePath))
    }

    // MARK: - ③ 差异预览 + 未批准**不落盘**

    func testPrepareWriteShowsADiffAndWritesNothing() throws {
        let before = try XCTUnwrap(bytes(of: "target.txt"))
        let outcome = tools.prepareWrite(path: "target.txt", content: "旧内容第一行\n新内容\n")

        guard case .needsApproval(let request) = outcome else { return XCTFail("要审批") }
        XCTAssertEqual(request.toolName, "write_file")
        XCTAssertFalse(request.fingerprint.isEmpty)
        XCTAssertTrue(request.payload.hasPrefix("target.txt"), "差异预览首行是路径：\(request.payload)")
        XCTAssertTrue(request.payload.contains("-旧内容第二行"), "被删的行要在预览里")
        XCTAssertTrue(request.payload.contains("+新内容"), "新增的行要在预览里")
        XCTAssertTrue(request.payload.contains(" 旧内容第一行"), "没变的行作上下文")

        XCTAssertEqual(bytes(of: "target.txt"), before, "**未批准 ⇒ 盘上文件逐字节未变**")
    }

    func testPrepareWriteOnANewFileAlsoWritesNothing() {
        let outcome = tools.prepareWrite(path: "brand-new.txt", content: "新文件内容\n")
        guard case .needsApproval(let request) = outcome else { return XCTFail("要审批") }
        XCTAssertTrue(request.payload.contains("+新文件内容"))
        XCTAssertNil(bytes(of: "brand-new.txt"), "未批准不许凭空建文件")
    }

    /// 三种「不该写」的写法各一条：指纹不符 / 没在已批准集合里 / 目标逃出工作区。
    func testWriteIsRefusedUnlessTheExactFingerprintWasGranted() throws {
        let before = try XCTUnwrap(bytes(of: "target.txt"))
        guard case .needsApproval(let request) = tools.prepareWrite(path: "target.txt", content: "改过的\n") else {
            return XCTFail("要审批")
        }

        if case .refused(let code, _) = tools.writeFile(path: "target.txt", content: "改过的\n",
                                                        fingerprint: "deadbeef", granted: ["deadbeef"]) {
            XCTAssertEqual(code, .approvalRequired, "指纹不符要拒")
        } else { XCTFail("指纹不符要拒") }

        if case .refused(let code, _) = tools.writeFile(path: "target.txt", content: "改过的\n",
                                                        fingerprint: request.fingerprint, granted: []) {
            XCTAssertEqual(code, .approvalRequired, "没批要拒")
        } else { XCTFail("没批要拒") }

        // 换了参数的调用（内容变了）⇒ 指纹也变了 ⇒ 拿旧指纹批过的不算
        if case .refused(let code, _) = tools.writeFile(path: "target.txt", content: "换了内容\n",
                                                        fingerprint: request.fingerprint, granted: [request.fingerprint]) {
            XCTAssertEqual(code, .approvalRequired, "**换参数要重新批**（不许一次批准变成总开关）")
        } else { XCTFail("换参数要重新批") }

        XCTAssertEqual(bytes(of: "target.txt"), before, "以上三种都不许动盘")

        // 批了、指纹一致 ⇒ 真写
        guard case .wrote(let output) = tools.writeFile(path: "target.txt", content: "改过的\n",
                                                       fingerprint: request.fingerprint,
                                                       granted: [request.fingerprint]) else {
            return XCTFail("批了就该写")
        }
        XCTAssertEqual(output.text, "改过的\n")
        XCTAssertEqual(try XCTUnwrap(bytes(of: "target.txt")), Data("改过的\n".utf8))
    }

    func testWriteOutsideWorkspaceIsRefusedEvenWithApproval() {
        if case .refused(let code, _) = tools.prepareWrite(path: "../escape.txt", content: "x") {
            XCTAssertEqual(code, .outsideWorkspace)
        } else { XCTFail("工作区外连审批单都不该建") }
    }

    /// 伤害性命令的拒因**先于**白名单判定（`FR-AI-34`：有害就是有害，与策略无关）——
    /// 故 `rm -rf` 这类拿到的是 `.harmStopped` 而非 `.commandNotAllowed`（2026-10-17 起的行为变更）。
    func testHarmfulCommandsAreRefusedAsHarmStopNotAsAllowlistMiss() {
        for command in ["rm -rf /", "cat a.txt; rm -rf /"] {
            if case .refused(let code, _) = tools.prepareCommand(command) {
                XCTAssertEqual(code, .harmStopped, "\(command) 应当被刹停闸门挡下")
            } else {
                XCTFail("\(command) 不该通过")
            }
        }
    }

    // MARK: - ④ 命令白名单 + 工作目录沙箱 + 未审批不执行

    func testNonWhitelistedCommandsAndControlCharactersAreRefused() {
        for command in ["sh -c ls", "/bin/ls", "sed -i s/a/b/ target.txt",
                        "cat a.txt | grep x", "echo hi > out.txt", "ls `whoami`"] {
            if case .refused(let code, _) = tools.prepareCommand(command) {
                XCTAssertEqual(code, .commandNotAllowed, "\(command) 应当被白名单/词法挡下")
            } else {
                XCTFail("\(command) 不该通过")
            }
        }
    }

    func testWhitelistedCommandNeedsApprovalAndRunsInTheWorkspace() {
        guard case .needsApproval(let request) = tools.prepareCommand("cat target.txt") else {
            return XCTFail("白名单命令也要审批")
        }
        XCTAssertEqual(request.toolName, "run_command")
        XCTAssertEqual(request.payload, "cat target.txt")

        let runner = RecordingRunner()
        // 未批准 ⇒ 一次都不执行
        if case .refused(let code, _) = tools.runCommand("cat target.txt", fingerprint: request.fingerprint,
                                                        granted: [], runner: runner) {
            XCTAssertEqual(code, .approvalRequired)
        } else { XCTFail("未批准不许执行") }
        XCTAssertTrue(runner.calls.isEmpty, "**未审批的命令一次都不许执行**")

        // 批准 ⇒ 执行，且**工作目录钉在工作区根**
        guard case .command(let result) = tools.runCommand("cat target.txt", fingerprint: request.fingerprint,
                                                           granted: [request.fingerprint], runner: runner) else {
            return XCTFail("批准后应当执行")
        }
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls.first?.executable, "cat")
        XCTAssertEqual(runner.calls.first?.arguments, ["target.txt"])
        XCTAssertEqual(runner.calls.first?.workingDirectory.standardizedFileURL, root.standardizedFileURL,
                       "工作目录沙箱 = 工作区根")
    }

    /// 参数里带路径 ⇒ 必须落在工作区内（否则等于绕开沙箱）。
    func testArgumentsThatPointOutsideTheWorkspaceAreRefused() {
        for command in ["cat /etc/passwd", "head -n 5 ../../etc/hosts", "grep x /tmp/elsewhere.txt"] {
            if case .refused(let code, _) = tools.prepareCommand(command) {
                XCTAssertEqual(code, .outsideWorkspace, "\(command) 的参数跑出工作区了")
            } else {
                XCTFail("\(command) 不该通过")
            }
        }
        // 反向：工作区内的相对路径照样能用
        if case .needsApproval = tools.prepareCommand("head -n 5 target.txt") {} else {
            XCTFail("工作区内路径不该被拒")
        }
    }

    /// 退出码要如实带出来（不许只给 stdout 假装成功）。
    func testNonZeroExitCodeIsReportedNotHidden() {
        let runner = RecordingRunner()
        runner.result = AgentCommandResult(exitCode: 2, standardOutput: "", standardError: "no such file\n")
        guard case .needsApproval(let request) = tools.prepareCommand("cat missing.txt") else { return XCTFail("要审批") }
        guard case .command(let result) = tools.runCommand("cat missing.txt", fingerprint: request.fingerprint,
                                                           granted: [request.fingerprint], runner: runner) else {
            return XCTFail("应当执行")
        }
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.combined.contains("no such file"), "stderr 要带出来")
        XCTAssertTrue(result.combined.contains("exit:2"), "退出码要带出来")
    }

    // MARK: - 差异算法本身

    func testDiffIsHonestAboutAddedRemovedAndUnchanged() {
        let same = AgentTextDiff.summary(before: "a\nb\n", after: "a\nb\n")
        XCTAssertTrue(same.unchanged, "没变就是没变")
        XCTAssertEqual(same.added, 0)
        XCTAssertEqual(same.removed, 0)

        let changed = AgentTextDiff.summary(before: "a\nb\nc\n", after: "a\nX\nc\n")
        XCTAssertEqual(changed.added, 1)
        XCTAssertEqual(changed.removed, 1)
        XCTAssertFalse(changed.unchanged)

        // 空行是内容的一部分，不许被吃掉
        let blank = AgentTextDiff.lines(before: "", after: "第一行\n\n第三行\n")
        XCTAssertEqual(blank.filter { $0.kind == .added }.count, 3)
    }
}
