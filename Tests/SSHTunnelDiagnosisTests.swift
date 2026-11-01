import XCTest
@testable import DoyahCore

/// SSH 隧道**归因**的判定（FR-CONN-18 判据 ②）：只有「配了隧道 + 隧道真的死了」才把失败说成隧道问题。
///
/// 反面同样是判据：直连、隧道好好活着、或者压根没起过隧道时，一个字节都不许改 ——
/// 把数据库自己的错误栽到隧道头上，也是一种误导。
final class SSHTunnelDiagnosisTests: XCTestCase {

    private let enabled = SSHTunnelConfig(isEnabled: true, host: "jump", username: "alice")
    private let disabled = SSHTunnelConfig(isEnabled: false, host: "jump", username: "alice")
    private let original = "connection closed by server"

    func testDirectConnectionIsNeverBlamedOnATunnel() {
        for state in [SSHTunnelProcess.State.ready(localPort: 55001), .failed("ssh 已退出"), .stopped] {
            XCTAssertEqual(
                SSHTunnelDiagnosis.annotate(message: original, tunnel: nil, state: state, language: .simplifiedChinese),
                original,
                "没配隧道就不许提隧道（\(state)）"
            )
        }
        XCTAssertEqual(
            SSHTunnelDiagnosis.annotate(message: original, tunnel: enabled, state: nil, language: .simplifiedChinese),
            original,
            "这一跳根本没起隧道时不许提隧道"
        )
        XCTAssertEqual(
            SSHTunnelDiagnosis.annotate(
                message: original, tunnel: disabled, state: .failed("x"), language: .simplifiedChinese
            ),
            original,
            "隧道被关掉时不许提隧道"
        )
    }

    func testHealthyTunnelLeavesTheDatabasesOwnErrorAlone() {
        for state in [SSHTunnelProcess.State.ready(localPort: 55001), .starting(localPort: 55001), .idle] {
            XCTAssertEqual(
                SSHTunnelDiagnosis.annotate(message: original, tunnel: enabled, state: state, language: .simplifiedChinese),
                original,
                "隧道活着的时候失败就是库/语句的失败（\(state)）"
            )
        }
    }

    func testDeadTunnelTakesTheBlameAndKeepsTheOriginalMessage() {
        let failed = SSHTunnelDiagnosis.annotate(
            message: original, tunnel: enabled, state: .failed("ssh 已退出：Connection refused"), language: .simplifiedChinese
        )
        XCTAssertNotEqual(failed, original)
        XCTAssertTrue(failed.contains("SSH 隧道"), "要说清是隧道的问题：\(failed)")
        XCTAssertTrue(failed.contains("Connection refused"), "要带上隧道自己的原因：\(failed)")
        XCTAssertTrue(failed.contains(original), "原始错误不许丢（它是后面排查的依据）：\(failed)")
        XCTAssertFalse(failed.contains("数据库拒绝了"), "不能反过来把它说成数据库拒绝")

        let stopped = SSHTunnelDiagnosis.annotate(
            message: original, tunnel: enabled, state: .stopped, language: .simplifiedChinese
        )
        XCTAssertTrue(stopped.contains("SSH 隧道"))
        XCTAssertTrue(stopped.contains(original))

        let english = SSHTunnelDiagnosis.annotate(
            message: original, tunnel: enabled, state: .failed("ssh exited"), language: .english
        )
        XCTAssertTrue(english.contains("SSH tunnel"))
        XCTAssertTrue(english.contains("not the database"))
        XCTAssertNotEqual(english, failed, "两种语言必须真的不同")
    }

    func testRebuildDecisionFollowsTheSameBoundary() {
        XCTAssertTrue(SSHTunnelDiagnosis.shouldRebuild(state: .failed("x"), tunnel: enabled))
        XCTAssertTrue(SSHTunnelDiagnosis.shouldRebuild(state: .stopped, tunnel: enabled))
        XCTAssertFalse(SSHTunnelDiagnosis.shouldRebuild(state: .ready(localPort: 55001), tunnel: enabled))
        XCTAssertFalse(SSHTunnelDiagnosis.shouldRebuild(state: .starting(localPort: 55001), tunnel: enabled))
        XCTAssertFalse(SSHTunnelDiagnosis.shouldRebuild(state: .failed("x"), tunnel: nil))
        XCTAssertFalse(SSHTunnelDiagnosis.shouldRebuild(state: .failed("x"), tunnel: disabled))
        XCTAssertFalse(SSHTunnelDiagnosis.shouldRebuild(state: nil, tunnel: enabled))
    }

    /// 状态改判的**边界**：只有「`.ready` + 进程没了」才改判。
    /// 还在建（`.starting`）或压根没起（`.idle`）时，进程没了是正常的，不该被说成「隧道断了」。
    func testMarkDeadIsANoOpBeforeTheTunnelIsReady() {
        let tunnel = SSHTunnelProcess(
            config: enabled,
            target: SSHTunnelTarget(host: "10.0.0.9", port: 5432),
            localPort: 55_901,
            knownHostsPath: NSTemporaryDirectory() + "doyah-diagnosis-known-hosts",
            executable: "/usr/bin/true",
            isPortOpen: { _, _ in false }
        )
        XCTAssertEqual(tunnel.currentState, .idle)
        XCTAssertFalse(tunnel.markDeadIfExited(language: .simplifiedChinese))
        XCTAssertEqual(tunnel.currentState, .idle, "没就绪过就不许被说成「断了」")
    }
}
