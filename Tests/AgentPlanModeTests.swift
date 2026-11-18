import XCTest
@testable import DoyahCore

/// **计划先获准**（`FR-AGT-PLAN-PLAN-007` / 概设 §18.4-8）。
///
/// 契约五条逐条落成用例：
/// ① 未批准时写类被拒、只读照旧；② 批准后按原计划执行、正文改了即失效；
/// ③ 退回后回规划态且**正文保留**；④ 会话恢复后状态不丢；⑤ 两条负例（未批准就写 / 退回清空计划）。
final class AgentPlanModeTests: XCTestCase {

    private func definition(_ name: String, level: AgentToolLevel) -> AgentToolDefinition {
        AgentToolDefinition(name: name, summary: "样例", capability: .readFile,
                            parameters: [:], required: [], level: level, approval: .none)
    }

    // MARK: ① 未批准：写拒、读放

    func testAwaitingApprovalBlocksWritesButAllowsReads() {
        var plan = AgentPlanState()
        plan.submit("1. 读 A\n2. 改 B\n3. 跑测试")

        XCTAssertEqual(plan.phase, .awaitingApproval)
        if case .awaitingApproval = plan.verdict(for: definition("write_file", level: .writable)) {} else {
            XCTFail("未批准时 write_file 必须被拒，实际：\(plan.verdict(for: definition("write_file", level: .writable)))")
        }
        XCTAssertEqual(plan.verdict(for: definition("read_file", level: .readOnly)), .allow,
                       "只读必须放行 —— 计划模式是「只探索与设计」，不是「什么都不许干」")
    }

    // MARK: ② 批准后执行；正文一改旧批准失效

    func testApprovedPlanExecutesUntilBodyChanges() {
        var plan = AgentPlanState()
        plan.submit("改 Core/A 的一行")
        plan.approve()
        XCTAssertEqual(plan.phase, .approved)
        XCTAssertEqual(plan.verdict(for: definition("write_file", level: .writable)), .allow)

        plan.body += "\n再改 Core/B"
        guard case .planChanged(let approved, let current) = plan.verdict(for: definition("write_file", level: .writable)) else {
            return XCTFail("计划正文改过之后，旧批准必须失效（否则等于批准了一张空白支票）")
        }
        XCTAssertNotEqual(approved, current)
    }

    // MARK: ③ 退回：回规划态、正文保留

    func testRejectedPlanKeepsBodyAndReturnsToPlanning() {
        var plan = AgentPlanState()
        plan.submit("1. 读 A\n2. 改 B")
        plan.reject(note: "第二步不该动 B")

        XCTAssertEqual(plan.phase, .rejected)
        XCTAssertEqual(plan.body, "1. 读 A\n2. 改 B", "退回不许清空计划 —— 清空等于让人从头写一遍")
        XCTAssertEqual(plan.history.map(\.kind), [.submitted, .rejected], "三态必须可回看")
        if case .awaitingApproval = plan.verdict(for: definition("write_file", level: .writable)) {} else {
            XCTFail("退回之后写类必须重新被拦")
        }
    }

    // MARK: ④ 会话恢复

    func testPlanPhaseSurvivesSessionReplay() {
        var plan = AgentPlanState()
        plan.submit("计划正文", at: Date(timeIntervalSince1970: 1))
        plan.approve(at: Date(timeIntervalSince1970: 2))

        let turns = plan.history.map { event in
            AgentSessionTurn(sessionID: "s1", workspace: "ws", kind: .plan, role: "system",
                             text: AgentPlanState.turnText(for: event, body: plan.body),
                             at: event.at)
        }
        let restored = AgentPlanState.replay(turns)

        XCTAssertEqual(restored.phase, .approved, "恢复后仍是已批准态（判据 ④）")
        XCTAssertEqual(restored.body, "计划正文")
        XCTAssertEqual(restored.verdict(for: definition("write_file", level: .writable)), .allow)
        XCTAssertEqual(restored.history.count, 2)
    }

    func testRejectedPlanSurvivesSessionReplayWithBody() {
        var plan = AgentPlanState()
        plan.submit("别丢我")
        plan.reject(note: "重想")
        let turns = plan.history.map {
            AgentSessionTurn(sessionID: "s1", workspace: "ws", kind: .plan, role: "system",
                             text: AgentPlanState.turnText(for: $0, body: plan.body), at: $0.at)
        }
        let restored = AgentPlanState.replay(turns)
        XCTAssertEqual(restored.phase, .rejected)
        XCTAssertEqual(restored.body, "别丢我", "恢复后也不许把退回的计划弄丢")
    }

    // MARK: ⑤ 负例

    func testNegativeNoApprovalMeansNoWrite() {
        var plan = AgentPlanState()
        plan.submit("只读探索")
        // 没调 approve ⇒ 任何写类都必须红
        let verdict = plan.verdict(for: definition("edit_file", level: .writable))
        XCTAssertNotEqual(verdict, .allow, "负例：未批准就放行写操作 = 判据失灵")
    }

    func testNegativeRejectMustNotClearPlan() {
        var plan = AgentPlanState()
        plan.submit("AAA")
        plan.reject()
        XCTAssertFalse(plan.body.isEmpty, "负例：退回把计划清空 = 判据失灵")
    }
}
