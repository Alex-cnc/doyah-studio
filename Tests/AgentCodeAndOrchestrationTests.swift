import XCTest
@testable import DoyahCore

/// `FR-AGT-TOOL-SYS-005/006`：代码执行受限目录、无网、超时、依赖如实报。
final class AgentCodeRunnerTests: XCTestCase {
    private let runner = AgentCodeRunner()
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("code-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testPythonRunsAndCapturesStdout() throws {
        let outcome = runner.run(.init(language: .python, source: "print(6*7)", workingDirectory: dir))
        XCTAssertTrue(outcome.succeeded, outcome.stderr)
        XCTAssertEqual(outcome.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "42")
        XCTAssertNil(outcome.failure)
    }

    func testSyntaxErrorIsRuntimeErrorNotSuccess() {
        let outcome = runner.run(.init(language: .python, source: "def broken(:", workingDirectory: dir))
        XCTAssertFalse(outcome.succeeded)
        XCTAssertNotEqual(outcome.exitCode, 0)
        XCTAssertEqual(outcome.failure, .runtimeError)
    }

    func testMissingDependencyIsReportedVerbatim() {
        let outcome = runner.run(.init(language: .python,
                                       source: "import definitely_not_installed_pkg_xyz",
                                       workingDirectory: dir))
        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.failure, .missingDependency)
        XCTAssertTrue(outcome.stderr.contains("definitely_not_installed_pkg_xyz"))
    }

    func testTimeoutIsMarked() {
        let outcome = runner.run(.init(language: .python, source: "import time; time.sleep(3)",
                                       workingDirectory: dir, timeoutSeconds: 0.5))
        XCTAssertEqual(outcome.failure, .timedOut)
        XCTAssertFalse(outcome.succeeded)
    }

    func testNetworkIsDeniedInsideSandbox() throws {
        let script = """
        import socket
        try:
            socket.create_connection(("1.1.1.1", 80), timeout=1)
            print("NETWORK-ALLOWED")
        except Exception as error:
            print("NETWORK-DENIED")
        """
        let outcome = runner.run(.init(language: .python, source: script, workingDirectory: dir, timeoutSeconds: 10))
        guard outcome.networkIsolated else {
            throw XCTSkip("本机无 sandbox-exec，无法验证无网剖面（如实跳过，不假装通过）")
        }
        XCTAssertTrue(outcome.stdout.contains("NETWORK-DENIED"), outcome.stdout + outcome.stderr)
    }

    func testMissingWorkingDirectoryIsRefused() {
        let outcome = runner.run(.init(language: .python, source: "print(1)",
                                       workingDirectory: URL(fileURLWithPath: "/no/such/dir")))
        XCTAssertEqual(outcome.failure, .outsideWorkspace)
        XCTAssertFalse(outcome.succeeded)
    }

    func testInterpreterWhitelistOnly() {
        // 白名单里只有三种语言；未知语言根本构造不出来（编译期就挡），这里钉住表的大小
        XCTAssertEqual(AgentCodeRunRequest.Language.allCases.count, 3)
        for language in AgentCodeRunRequest.Language.allCases {
            XCTAssertNotNil(AgentCodeRunner.interpreters[language])
        }
    }
}

/// `FR-AGT-TOOL-SYS-007/008` + `SYS-002`：并行、逐路结局、来源标注、待批回主控。
final class AgentOrchestratorTests: XCTestCase {
    func testRunsInParallelAndKeepsInputOrder() {
        let specs = (1...5).map { AgentSubtaskSpec(id: "S\($0)", label: "路\($0)", prompt: "do \($0)") }
        let report = AgentOrchestrator().run(specs, limits: .init(maxConcurrent: 3)) { spec in
            Thread.sleep(forTimeInterval: 0.05)
            return AgentSubtaskResult(subtaskID: spec.id, label: spec.label, status: .completed,
                                      summary: "done \(spec.id)", artifacts: ["/tmp/\(spec.id).csv"])
        }
        XCTAssertEqual(report.results.map(\.subtaskID), ["S1", "S2", "S3", "S4", "S5"])
        XCTAssertEqual(report.completedCount, 5)
        XCTAssertTrue(report.mergedSummary.contains("路1#S1"))
        XCTAssertTrue(report.mergedSummary.contains("/tmp/S1.csv"))
    }

    func testOneFailureDoesNotKillTheBatch() {
        let specs = [
            AgentSubtaskSpec(id: "ok", label: "好", prompt: "x"),
            AgentSubtaskSpec(id: "bad", label: "坏", prompt: "x"),
            AgentSubtaskSpec(id: "slow", label: "慢", prompt: "x"),
        ]
        let report = AgentOrchestrator().run(specs, limits: .init(maxConcurrent: 3)) { spec in
            switch spec.id {
            case "bad": return .init(subtaskID: spec.id, label: spec.label, status: .failed, summary: "报错", artifacts: [])
            case "slow": return .init(subtaskID: spec.id, label: spec.label, status: .timedOut, summary: "超预算", artifacts: [])
            default: return .init(subtaskID: spec.id, label: spec.label, status: .completed, summary: "好", artifacts: [])
            }
        }
        XCTAssertEqual(report.completedCount, 1)
        XCTAssertEqual(Set(report.failures.map(\.subtaskID)), ["bad", "slow"])
    }

    func testApprovalBubblesToMainController() {
        let report = AgentOrchestrator().run([.init(id: "w", label: "写盘", prompt: "x")],
                                             limits: .init(maxConcurrent: 2)) { spec in
            .init(subtaskID: spec.id, label: spec.label, status: .needsApproval,
                  summary: "要写 3 个文件", artifacts: [], approvalFingerprint: "fp-123")
        }
        XCTAssertEqual(report.needsApproval.count, 1)
        XCTAssertEqual(report.needsApproval.first?.approvalFingerprint, "fp-123")
        XCTAssertTrue(report.mergedSummary.contains("待主控批：写盘#w"))
    }

    func testConcurrencyLimitIsRespected() {
        let counter = Counter()
        let specs = (1...6).map { AgentSubtaskSpec(id: "S\($0)", label: "L", prompt: "x") }
        _ = AgentOrchestrator().run(specs, limits: .init(maxConcurrent: 2)) { spec in
            counter.enter()
            Thread.sleep(forTimeInterval: 0.05)
            counter.leave()
            return .init(subtaskID: spec.id, label: spec.label, status: .completed, summary: "ok", artifacts: [])
        }
        XCTAssertLessThanOrEqual(counter.peak, 2)
    }

    func testEmptyBatchIsEmptyReport() {
        let report = AgentOrchestrator().run([], limits: .init()) { spec in
            .init(subtaskID: spec.id, label: spec.label, status: .completed, summary: "", artifacts: [])
        }
        XCTAssertTrue(report.results.isEmpty)
        XCTAssertEqual(report.mergedSummary, "")
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var current = 0
        private(set) var peak = 0
        func enter() { lock.lock(); current += 1; peak = max(peak, current); lock.unlock() }
        func leave() { lock.lock(); current -= 1; lock.unlock() }
    }
}
