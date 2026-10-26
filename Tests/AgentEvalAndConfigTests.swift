import XCTest
@testable import DoyahCore

/// `FR-AGT-OPS-OBS-003`：固定用例、可对比的通过率、能指出这次掉了哪几条。
final class AgentEvalHarnessTests: XCTestCase {
    private let runner = AgentEvalRunner()

    func testAllPassProducesFullRate() {
        let cases = [
            AgentEvalCase(id: "c1", prompt: "查 1", expectation: .contains("ok")),
            AgentEvalCase(id: "c2", prompt: "查 2", expectation: .equals("done")),
            AgentEvalCase(id: "c3", prompt: "查 3", expectation: .fails),
        ]
        let report = runner.run(cases) { prompt in
            switch prompt {
            case "查 1": return ("all ok", true)
            case "查 2": return ("done", true)
            default: return ("refused", false)
            }
        }
        XCTAssertEqual(report.passedCount, 3)
        XCTAssertEqual(report.passRate, 1.0)
        XCTAssertEqual(report.headline, "pass 3/3 (100%)")
        XCTAssertTrue(report.failedIDs.isEmpty)
    }

    func testFailuresAreItemisedWithVerdicts() {
        let cases = [
            AgentEvalCase(id: "has", prompt: "p1", expectation: .contains("42")),
            AgentEvalCase(id: "eq", prompt: "p2", expectation: .equals("expected")),
            AgentEvalCase(id: "fails", prompt: "p3", expectation: .fails),
        ]
        let report = runner.run(cases) { prompt in
            switch prompt {
            case "p1": return ("答案是 41", true)
            case "p2": return ("actual", true)
            default: return ("没拒", true)
            }
        }
        XCTAssertEqual(Set(report.failedIDs), ["has", "eq", "fails"])
        XCTAssertEqual(report.passRate, 0)
        XCTAssertTrue(report.results.first { $0.caseID == "has" }!.verdict.contains("缺"))
        XCTAssertTrue(report.results.first { $0.caseID == "fails" }!.verdict.contains("本该失败"))
    }

    func testOneFailureDoesNotStopTheBatch() {
        let cases = (1...5).map { AgentEvalCase(id: "c\($0)", prompt: "\($0)", expectation: .contains("ok")) }
        let report = runner.run(cases) { prompt in
            prompt == "3" ? ("bad", true) : ("ok", true)
        }
        XCTAssertEqual(report.total, 5)
        XCTAssertEqual(report.failedIDs, ["c3"])
        XCTAssertEqual(report.passedCount, 4)
    }

    func testRegressionsAgainstPreviousRun() {
        let cases = [
            AgentEvalCase(id: "a", prompt: "a", expectation: .contains("ok")),
            AgentEvalCase(id: "b", prompt: "b", expectation: .contains("ok")),
        ]
        let good = runner.run(cases) { _ in ("ok", true) }
        let worse = runner.run(cases) { prompt in prompt == "b" ? ("nope", true) : ("ok", true) }
        XCTAssertEqual(worse.regressions(against: good), ["b"])
        XCTAssertEqual(good.regressions(against: worse), [])
    }

    func testEmptyCaseSetIsZeroRateNotCrash() {
        let report = runner.run([]) { _ in ("", true) }
        XCTAssertEqual(report.total, 0)
        XCTAssertEqual(report.passRate, 0)
        XCTAssertEqual(report.headline, "pass 0/0 (0%)")
    }
}

/// `FR-AGT-OPS-OBS-002`：改配置越界拒收、必须给理由、改完立即生效、留痕。
final class AgentConfigStoreTests: XCTestCase {
    func testValidChangeAppliesImmediatelyAndIsRecorded() throws {
        var store = AgentConfigStore()
        try store.apply(key: "commandTimeoutSeconds", value: "120", reason: "长导出要更久")
        XCTAssertEqual(store.appliedSnapshot.commandTimeoutSeconds, 120)
        XCTAssertEqual(store.changes.count, 1)
        XCTAssertEqual(store.changes.first?.oldValue, "60")
        XCTAssertEqual(store.changes.first?.newValue, "120")
        XCTAssertTrue(store.changes.first!.summaryLine.contains("因为长导出要更久"))
    }

    func testOutOfRangeIsRejectedWithoutTouchingState() {
        var store = AgentConfigStore()
        XCTAssertThrowsError(try store.apply(key: "dailyTokenQuota", value: "0", reason: "省点")) { error in
            guard case let .outOfRange(_, _, allowed) = error as? AgentConfigError else {
                return XCTFail("应是越界错误")
            }
            XCTAssertTrue(allowed.contains("1000"))
        }
        XCTAssertEqual(store.appliedSnapshot.dailyTokenQuota, 200_000)
        XCTAssertTrue(store.changes.isEmpty)
    }

    func testMissingReasonIsRejected() {
        var store = AgentConfigStore()
        XCTAssertThrowsError(try store.apply(key: "model", value: "x", reason: "  ")) { error in
            XCTAssertEqual(error as? AgentConfigError, .missingReason)
        }
        XCTAssertEqual(store.appliedSnapshot.model, "默认")
    }

    func testUnknownKeyIsRefusedById() {
        var store = AgentConfigStore()
        XCTAssertThrowsError(try store.apply(key: "secretSauce", value: "1", reason: "试试")) { error in
            XCTAssertEqual(error as? AgentConfigError, .unknownKey("secretSauce"))
        }
    }

    func testBooleanAndListKeys() throws {
        var store = AgentConfigStore()
        try store.apply(key: "notificationsEnabled", value: "false", reason: "专心写稿")
        XCTAssertFalse(store.appliedSnapshot.notificationsEnabled)
        try store.apply(key: "toolWhitelist", value: "read_file, query_db ,", reason: "只留只读")
        XCTAssertEqual(store.appliedSnapshot.toolWhitelist, ["read_file", "query_db"])
        XCTAssertThrowsError(try store.apply(key: "notificationsEnabled", value: "yes", reason: "口语"))
    }

    func testConcurrencyBounds() throws {
        var store = AgentConfigStore()
        try store.apply(key: "maxConcurrentSubtasks", value: "8", reason: "多路并行")
        XCTAssertEqual(store.appliedSnapshot.maxConcurrentSubtasks, 8)
        XCTAssertThrowsError(try store.apply(key: "maxConcurrentSubtasks", value: "99", reason: "贪心"))
        XCTAssertEqual(store.appliedSnapshot.maxConcurrentSubtasks, 8)
    }
}
