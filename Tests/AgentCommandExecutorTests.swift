import XCTest
@testable import DoyahCore

/// `FR-AGT-TOOL-SYS-003/004`：命令执行带 stdin/stdout/退出码、可超时、可取消、截断可见。
final class AgentCommandExecutorTests: XCTestCase {
    private let sh = "/bin/sh"

    func testEchoCapturesStdoutAndZeroExit() throws {
        let run = try AgentCommandExecutor().run(
            executable: sh, arguments: ["-c", "printf hello"],
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()))
        XCTAssertEqual(run.standardOutput, "hello")
        XCTAssertEqual(run.exitCode, 0)
        XCTAssertTrue(run.succeeded)
        XCTAssertFalse(run.terminatedEarly)
        XCTAssertTrue(run.combined.hasSuffix("exit:0"))
    }

    func testStderrAndNonZeroExitAreReportedNotSwallowed() throws {
        let run = try AgentCommandExecutor().run(
            executable: sh, arguments: ["-c", "echo boom 1>&2; exit 7"],
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()))
        XCTAssertEqual(run.exitCode, 7)
        XCTAssertEqual(run.standardError.trimmingCharacters(in: .whitespacesAndNewlines), "boom")
        XCTAssertFalse(run.succeeded)
        XCTAssertTrue(run.combined.contains("exit:7"))
    }

    func testTimeoutMarksTerminatedEarlyAndKeepsPartialOutput() throws {
        let limits = AgentCommandLimits(timeoutSeconds: 0.4)
        let run = try AgentCommandExecutor().run(
            executable: sh, arguments: ["-c", "echo started; sleep 3; echo never"],
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()), limits: limits)
        XCTAssertTrue(run.timedOut)
        XCTAssertTrue(run.terminatedEarly)
        XCTAssertFalse(run.succeeded)
        XCTAssertTrue(run.standardOutput.contains("started"))
        XCTAssertFalse(run.standardOutput.contains("never"))
        // 超时不许伪装成 0
        XCTAssertNotEqual(run.exitCode, 0)
    }

    func testCancelStopsRunningProcess() throws {
        let executor = AgentCommandExecutor()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { executor.cancel() }
        let run = try executor.run(
            executable: sh, arguments: ["-c", "sleep 5; echo done"],
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
            limits: AgentCommandLimits(timeoutSeconds: 20))
        XCTAssertTrue(run.terminatedEarly)
        XCTAssertFalse(run.succeeded)
        XCTAssertFalse(run.standardOutput.contains("done"))
        XCTAssertLessThan(run.durationMilliseconds, 4000)
    }

    func testOutputTruncationIsVisibleWithDroppedBytes() throws {
        let limits = AgentCommandLimits(timeoutSeconds: 20, maxOutputBytes: 1024)
        let run = try AgentCommandExecutor().run(
            executable: sh, arguments: ["-c", "yes A | head -c 20000"],
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()), limits: limits)
        XCTAssertTrue(run.truncated)
        XCTAssertGreaterThan(run.droppedOutputBytes, 0)
        XCTAssertLessThanOrEqual(run.standardOutput.utf8.count, 1024)
        XCTAssertTrue(run.combined.contains("输出已截断"))
    }

    func testNonExecutableIsRefusedBeforeSpawning() {
        XCTAssertThrowsError(try AgentCommandExecutor().run(
            executable: "/definitely/not/here", arguments: [],
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()))) { error in
            XCTAssertEqual(error as? AgentCommandExecutionError, .notExecutable("/definitely/not/here"))
        }
    }

    func testMissingWorkingDirectoryIsRefused() {
        XCTAssertThrowsError(try AgentCommandExecutor().run(
            executable: sh, arguments: ["-c", "true"],
            workingDirectory: URL(fileURLWithPath: "/no/such/dir"))) { error in
            XCTAssertEqual(error as? AgentCommandExecutionError, .outsideWorkspace("/no/such/dir"))
        }
    }

    /// `FR-AGT-TOOL-SYS-004`：越界参数不出工作区、危险形态必须进审批。
    func testPolicyRefusesPathEscapingWorkspaceAndFlagsDangerous() {
        let policy = AgentCommandPolicy.standard
        let root = URL(fileURLWithPath: "/Users/alex/work")
        XCTAssertNotNil(policy.argumentsStayInsideWorkspace(["../../etc/passwd"], root: root))
        XCTAssertNil(policy.argumentsStayInsideWorkspace(["notes/today.md"], root: root))
        if case .refused = policy.assess("rm -rf /tmp/x") {} else {
            XCTFail("rm -rf 应被策略拦下或送审批")
        }
    }
}
