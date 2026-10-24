import XCTest
@testable import DoyahCore

/// `FR-AGT-QUAL-VERIFY-001`（结果自验）的机械判据。
///
/// 台账三条：① 产出前自查（能跑跑一遍、能对对一遍）；② 自验记录进审计；③ **跳过自验判红**。
/// 判据钉的就是这三条 —— 尤其是 ③：动过东西却一条自验都没有，必须 `skipped` 而不是「通过」。
///
/// 纯函数判据：不读盘、不跑命令（盘上复核在完成判据那边已经做过一次，这里只折表）。

final class AgentSelfCheckTests: XCTestCase {

    private func write(_ path: String, step: Int = 0) -> AgentCompletionEvidence {
        AgentCompletionEvidence(kind: .write, toolName: "write_file", path: path,
                                digest: AgentCompletionEvidence.digest(of: "x"), step: step)
    }

    private func command(_ code: Int?, step: Int = 1) -> AgentCompletionEvidence {
        AgentCompletionEvidence(kind: .command, toolName: "run_command",
                                exitCode: code, step: step)
    }

    // MARK: - ① 能对的对一遍 / 能跑的跑一遍

    func testVerifiedWriteAndZeroExitCommandBothPass() {
        let report = AgentSelfCheck.report(
            evidence: [write("a.swift"), command(0, step: 1)],
            verifiedPaths: ["a.swift"])
        XCTAssertEqual(report.status, .passed)
        XCTAssertEqual(report.items.count, 2)
        XCTAssertEqual(report.passedCount, 2)
        XCTAssertEqual(report.code, "selfCheck:2/2")
        XCTAssertTrue(report.isClean)
    }

    /// 写过的文件没被完成判据复核到 ⇒ 这一条不算过（**没对上就是没过**，不许默认放行）。
    func testWriteWithoutVerificationIsNotPassed() {
        let report = AgentSelfCheck.report(evidence: [write("a.swift")], verifiedPaths: [])
        XCTAssertEqual(report.status, .failed)
        XCTAssertEqual(report.code, "selfCheckFailed:unverified")
        XCTAssertEqual(report.passedCount, 0)
    }

    /// 命令退出码非 0 ⇒ 判红，原因带码（「能跑跑一遍」的意思是**跑对了**，不是「跑过了」）。
    func testNonZeroExitFailsTheCheck() {
        let report = AgentSelfCheck.report(evidence: [command(2)], verifiedPaths: [])
        XCTAssertEqual(report.status, .failed)
        XCTAssertEqual(report.code, "selfCheckFailed:exitNonZero:2")
    }

    /// 命令连退出码都没有 ⇒ 没法验 ⇒ 不许当通过（「跑了但不知道结果」等于没验）。
    func testCommandWithoutExitCodeIsUnverified() {
        let report = AgentSelfCheck.report(evidence: [command(nil)], verifiedPaths: [])
        XCTAssertEqual(report.status, .failed)
        XCTAssertEqual(report.reason, "unverified")
    }

    /// 复核判定退出码对不上的那一跳，即使记录里写的是 0 也要判红（**以复核结论为准**）。
    func testFailedCommandStepsOverrideRecordedExitCode() {
        let report = AgentSelfCheck.report(evidence: [command(0)], verifiedPaths: [],
                                           failedCommandSteps: [1])
        XCTAssertEqual(report.status, .failed)
        XCTAssertEqual(report.reason, "exitNonZero:0")
    }

    // MARK: - ③ 跳过自验判红

    func testActedButNoSelfCheckIsSkippedNotPassed() {
        // 工具账里有写盘，调用方却交了空报告 —— 这是接线错误，必须判红。
        let report = AgentSelfCheck.audit(evidence: [write("a.swift")],
                                          report: AgentSelfCheckReport(status: .nothingToCheck))
        XCTAssertEqual(report.status, .skipped)
        XCTAssertEqual(report.code, "selfCheckSkipped:noEvidence")
        XCTAssertFalse(report.isClean, "skipped 不许被当干净")
    }

    /// 反例方向：这一轮真的什么都没动（纯问答）⇒ `nothingToCheck`，不判红、也不冒充「已自验」。
    func testPureAnswerIsNothingToCheckNotSkipped() {
        let readOnly = AgentCompletionEvidence(kind: .read, toolName: "read_file",
                                               path: "a.swift", step: 0)
        let report = AgentSelfCheck.audit(evidence: [readOnly],
                                          report: AgentSelfCheck.report(evidence: [readOnly]))
        XCTAssertEqual(report.status, .nothingToCheck)
        XCTAssertEqual(report.code, "selfCheck:none")
        XCTAssertTrue(report.isClean)
    }

    /// 只读条目**不进分母**：读过 10 个文件不叫「验过 10 条」。
    func testReadEvidenceDoesNotInflateTheDenominator() {
        let reads = (0..<10).map {
            AgentCompletionEvidence(kind: .read, toolName: "read_file", path: "f\($0).swift", step: $0)
        }
        let report = AgentSelfCheck.report(evidence: reads + [command(0, step: 10)], verifiedPaths: [])
        XCTAssertEqual(report.items.count, 1, "只读一律不进分母")
        XCTAssertEqual(report.code, "selfCheck:1/1")
    }

    // MARK: - ② 记录形状（审计要能读）

    func testCodeShapeIsMachineReadable() {
        let report = AgentSelfCheck.report(evidence: [write("a"), write("b", step: 1), command(0, step: 2)],
                                           verifiedPaths: ["a", "b"])
        XCTAssertEqual(report.code, "selfCheck:3/3")
        XCTAssertTrue(report.code.hasPrefix("selfCheck:"), "审计按前缀认，不许改成人话")
        XCTAssertFalse(report.code.contains(" "), "机器码里不许带空格：\(report.code)")
    }
}
