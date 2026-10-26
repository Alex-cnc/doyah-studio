import XCTest
@testable import DoyahCore

/// `FR-AGT-PLAN-CLAR-001` 与 `FR-AGT-PLAN-PLAN-004`：该问才问、改计划必须说理由。
final class AgentPlanningDisciplineTests: XCTestCase {
    private let gate = AgentClarificationGate()

    // MARK: - 澄清门

    func testEmptyGoalAsks() {
        guard case let .ask(req) = gate.decide(goal: "   ") else { return XCTFail("空目标必须问") }
        XCTAssertEqual(req.reason, .ambiguousGoal)
    }

    func testNounOnlyGoalAsks() {
        guard case let .ask(req) = gate.decide(goal: "那张表的索引") else {
            return XCTFail("只有名词没有动词，应问一句")
        }
        XCTAssertEqual(req.reason, .ambiguousGoal)
        XCTAssertTrue(req.question.contains("那张表的索引"))
    }

    func testMissingRequiredParameterAsksWithNames() {
        guard case let .ask(req) = gate.decide(goal: "备份数据库", missingRequiredParameters: ["库名", "目标目录"]) else {
            return XCTFail("缺关键参数必须问")
        }
        XCTAssertEqual(req.reason, .missingParameter)
        XCTAssertTrue(req.question.contains("库名"))
        XCTAssertTrue(req.question.contains("目标目录"))
    }

    func testBigCostGapAsksWithOptions() {
        guard case let .ask(req) = gate.decide(
            goal: "迁移这张表", approaches: ["在线重写": 240, "停机窗口": 30]) else {
            return XCTFail("代价差 8 倍必须问")
        }
        XCTAssertEqual(req.reason, .costTradeoff)
        XCTAssertEqual(req.options.count, 2)
        XCTAssertTrue(req.options.first!.contains("停机窗口"))
    }

    func testSmallCostGapProceedsWithoutAsking() {
        XCTAssertEqual(gate.decide(goal: "导出这张表", approaches: ["A": 30, "B": 20]), .proceed)
    }

    func testExecutableGoalProceeds() {
        XCTAssertEqual(gate.decide(goal: "查一下 t 表最近 10 行"), .proceed)
        XCTAssertEqual(gate.decide(goal: "run vacuum on zxvmax"), .proceed)
    }

    // MARK: - 计划修订

    func testRevisionWithoutReasonIsRejected() {
        var log = AgentPlanRevisionLog()
        XCTAssertThrowsError(try log.record(stepID: "S1", before: "全表扫描", after: "走索引",
                                            trigger: "EXPLAIN 显示 120 万行", reason: " ")) { error in
            XCTAssertEqual(error as? AgentPlanRevisionError, .missingReason)
        }
        XCTAssertTrue(log.revisions.isEmpty)
    }

    func testRevisionWithoutTriggerIsRejected() {
        var log = AgentPlanRevisionLog()
        XCTAssertThrowsError(try log.record(stepID: "S1", before: "a", after: "b",
                                            trigger: "\n", reason: "更快")) { error in
            XCTAssertEqual(error as? AgentPlanRevisionError, .missingTrigger)
        }
    }

    func testSilentRerouteIsDetectable() throws {
        var log = AgentPlanRevisionLog()
        try log.record(stepID: "S1", before: "全表扫描", after: "走索引",
                       trigger: "EXPLAIN 120 万行", reason: "顺序扫描超出预算")
        let planned = ["S1": "全表扫描", "S2": "导出 CSV"]
        let executed = ["S1": "走索引", "S2": "导出 JSON"]
        XCTAssertEqual(log.silentReroutes(planned: planned, executed: executed), ["S2"])
        XCTAssertEqual(log.revisionCount(for: "S1"), 1)
    }

    func testSummaryLineOnlyWhenRevised() throws {
        var log = AgentPlanRevisionLog()
        XCTAssertNil(log.summaryLine)
        try log.record(stepID: "S3", before: "跑全量", after: "分批跑",
                       trigger: "锁等待 30s", reason: "全量会把业务卡住")
        let line = try XCTUnwrap(log.summaryLine)
        XCTAssertTrue(line.contains("改计划 1 次"))
        XCTAssertTrue(line.contains("锁等待 30s"))
    }
}
