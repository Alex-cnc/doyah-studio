import XCTest
@testable import DoyahCore

/// `FR-AI-23`（权限与审批）在本侧的判定面 —— 验收要点 ③④⑤⑥（① 与 ② 由 `FR-AI-19` / 沙箱那两族判据守着）。
final class AgentApprovalGateTests: XCTestCase {

    private var directory: URL!
    private var workspace: URL!
    private var store: MCPApprovalStore!
    private var gate: AgentApprovalGate!
    private var tools: AgentWorkspaceTools!

    private final class RecordingRunner: AgentCommandRunner, @unchecked Sendable {
        private(set) var calls: [String] = []
        func run(executable: String, arguments: [String], workingDirectory: URL) -> AgentCommandResult {
            calls.append(executable)
            return AgentCommandResult(exitCode: 0, standardOutput: "ok", standardError: "")
        }
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-gate-\(UUID().uuidString)", isDirectory: true)
        workspace = directory.appendingPathComponent("ws", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try "原始内容\n".write(to: workspace.appendingPathComponent("target.txt"), atomically: true, encoding: .utf8)
        store = MCPApprovalStore(directory: directory.appendingPathComponent("approvals", isDirectory: true))
        gate = AgentApprovalGate(store: store, timeout: 300)
        tools = AgentWorkspaceTools(root: workspace)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func bytes(of relativePath: String) -> Data? {
        try? Data(contentsOf: workspace.appendingPathComponent(relativePath))
    }

    private var writeTool: AgentToolDefinition { AgentToolRegistry.standard.definition(named: "write_file")! }

    // MARK: - ③ 队列里没有决定 ⇒ 一次都没执行（目标文件逐字节未变）

    func testNothingExecutesWithoutADecision() throws {
        let before = try XCTUnwrap(bytes(of: "target.txt"))
        guard case .needsApproval(let request) = tools.prepareWrite(path: "target.txt", content: "新内容\n") else {
            return XCTFail("要审批")
        }

        // 连单都没入队
        XCTAssertEqual(try gate.grant(fingerprint: request.fingerprint, at: Date()), .missing)
        // 入了队但没决定
        try gate.request(tool: writeTool, argumentsSummary: "target.txt", payload: request.payload,
                         fingerprint: request.fingerprint, at: Date())
        let pending = try gate.grant(fingerprint: request.fingerprint, at: Date())
        if case .pending = pending {} else { XCTFail("没人决定就是待审批，实际 = \(pending)") }
        XCTAssertEqual(try gate.pendingCount(), 1)

        // **未批准 ⇒ 不落盘**（判据点名的负例：比对目标文件逐字节未变）
        XCTAssertEqual(bytes(of: "target.txt"), before)

        // 命令那侧同样：没批 ⇒ 假终端零记录
        let runner = RecordingRunner()
        guard case .needsApproval(let commandRequest) = tools.prepareCommand("cat target.txt") else { return XCTFail("要审批") }
        _ = tools.runCommand("cat target.txt", fingerprint: commandRequest.fingerprint, granted: [], runner: runner)
        XCTAssertTrue(runner.calls.isEmpty, "未审批的命令一次都不许执行")
    }

    // MARK: - ④ 审批按**次**：一条批准只能兑现一次，换参数要重新批

    func testApprovalIsConsumedOnceAndArgumentsChangeNeedsANewSlip() throws {
        guard case .needsApproval(let request) = tools.prepareWrite(path: "target.txt", content: "改过的\n") else {
            return XCTFail("要审批")
        }
        let slip = try gate.request(tool: writeTool, argumentsSummary: "target.txt",
                                    payload: request.payload, fingerprint: request.fingerprint, at: Date())
        try store.decide(requestID: slip.id, approved: true, now: Date())

        // 第一次：批准 ⇒ 真写
        XCTAssertEqual(try gate.grant(fingerprint: request.fingerprint, at: Date()), .approved(requestID: slip.id))
        guard case .wrote = tools.writeFile(path: "target.txt", content: "改过的\n",
                                           fingerprint: request.fingerprint,
                                           granted: [request.fingerprint]) else {
            return XCTFail("批了就该写")
        }
        XCTAssertEqual(bytes(of: "target.txt"), Data("改过的\n".utf8))

        // 第二次：**同一条决定不许再用**（按次）
        let second = try gate.grant(fingerprint: request.fingerprint, at: Date())
        XCTAssertEqual(second, .denied(requestID: slip.id), "批准只能用一次，实际 = \(second)")

        // 换参数 ⇒ 指纹变 ⇒ 得重新批（拿旧指纹批准的那一次兑现不了新参数）
        guard case .needsApproval(let otherRequest) = tools.prepareWrite(path: "target.txt", content: "又改了\n") else {
            return XCTFail("要审批")
        }
        XCTAssertNotEqual(otherRequest.fingerprint, request.fingerprint)
        XCTAssertEqual(try gate.grant(fingerprint: otherRequest.fingerprint, at: Date()), .missing,
                       "换了参数就是另一张单，旧批准不算数")
        XCTAssertEqual(bytes(of: "target.txt"), Data("改过的\n".utf8), "第二次没批 ⇒ 盘上不动")
    }

    // MARK: - ⑤ 超时 = 拒绝

    func testTimeoutCountsAsDenied() throws {
        guard case .needsApproval(let request) = tools.prepareWrite(path: "target.txt", content: "x\n") else {
            return XCTFail("要审批")
        }
        let now = Date()
        let slip = try gate.request(tool: writeTool, argumentsSummary: "target.txt",
                                    payload: request.payload, fingerprint: request.fingerprint, at: now)
        try store.decide(requestID: slip.id, approved: true, now: now.addingTimeInterval(10))

        let tight = AgentApprovalGate(store: store, timeout: 5)
        let verdict = try tight.grant(fingerprint: request.fingerprint, at: now.addingTimeInterval(10))
        XCTAssertEqual(verdict, .expired(requestID: slip.id), "超时按拒绝处理，实际 = \(verdict)")
        XCTAssertFalse(verdict.isApproved)
        XCTAssertEqual(bytes(of: "target.txt"), Data("原始内容\n".utf8), "超时 ⇒ 不执行")

        // 时限内则照常批准
        let loose = AgentApprovalGate(store: store, timeout: 600)
        XCTAssertTrue(try loose.grant(fingerprint: request.fingerprint, at: now.addingTimeInterval(10)).isApproved)
    }

    // MARK: - ⑥ 只读模式下写 / 执行类**连审批单都建不出来**

    func testReadOnlyModeCannotEvenProduceAnApprovalSlip() throws {
        guard case .refused(let writeCode, let writeDetail) =
            tools.prepareWrite(path: "target.txt", content: "x\n", guardPolicy: .readOnlyDefault) else {
            return XCTFail("只读模式下写工具要直接拒")
        }
        XCTAssertEqual(writeCode, .deniedByPolicy)
        XCTAssertEqual(writeDetail, "writable", "细节串用机器码")

        guard case .refused(let commandCode, let commandDetail) =
            tools.prepareCommand("cat target.txt", guardPolicy: .readOnlyDefault) else {
            return XCTFail("只读模式下执行工具要直接拒")
        }
        XCTAssertEqual(commandCode, .deniedByPolicy)
        XCTAssertEqual(commandDetail, "executable")

        // 关键：**队列里一条都还没建**（不是"排着等批"，是根本没单）
        XCTAssertEqual(try gate.pendingCount(), 0, "只读模式下连审批单都不该出现")
        XCTAssertEqual(bytes(of: "target.txt"), Data("原始内容\n".utf8))
    }

    // MARK: - ① 等级与审批策略来自**同一份**注册表声明

    func testTheSlipCarriesTheRegistryDeclaration() throws {
        guard case .needsApproval(let request) = tools.prepareWrite(path: "target.txt", content: "x\n") else {
            return XCTFail("要审批")
        }
        let slip = try gate.request(tool: writeTool, argumentsSummary: "target.txt",
                                    payload: request.payload, fingerprint: request.fingerprint, at: Date())
        XCTAssertEqual(slip.tool, writeTool.name, "单上的工具名来自注册表")
        XCTAssertEqual(slip.fingerprint, request.fingerprint, "指纹由工具侧算，闸门不重算")
        XCTAssertEqual(writeTool.level, .writable)
        XCTAssertEqual(writeTool.approval, .required)
    }

    /// 队列被清理掉之后**绝不放行**（fail-safe：没有活着的请求就不批）。
    func testPruningTheQueueNeverLeavesAStandingApproval() throws {
        guard case .needsApproval(let request) = tools.prepareWrite(path: "target.txt", content: "x\n") else {
            return XCTFail("要审批")
        }
        let slip = try gate.request(tool: writeTool, argumentsSummary: "target.txt",
                                    payload: request.payload, fingerprint: request.fingerprint, at: Date())
        try store.decide(requestID: slip.id, approved: true, now: Date())
        XCTAssertTrue(try gate.grant(fingerprint: request.fingerprint, at: Date()).isApproved)

        // 清掉队列（审计另有其线，队列只是待办）⇒ 再问就是「没有这张单」
        try store.pruneDecided(now: Date())
        let after = AgentApprovalGate(store: store, timeout: 600)
        XCTAssertEqual(try after.grant(fingerprint: request.fingerprint, at: Date()), .missing)
    }
}
