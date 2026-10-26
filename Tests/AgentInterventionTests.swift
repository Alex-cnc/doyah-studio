import XCTest
@testable import DoyahCore

/// `FR-AGT-UX-CONV-007`（中途干预）判据：**插话在当前步之后生效，不丢已产生结果**。
final class AgentInterventionTests: XCTestCase {

    func testRedirectAppliesAfterCurrentStep() {
        var queue = AgentInterventionQueue()
        queue.enqueue(.redirect(instruction: "改走只读"), duringStep: 2)
        // 第 1 步之后：还没生效
        XCTAssertTrue(queue.drain(afterCompleting: 1).isEmpty)
        // 第 2 步之后：生效一次
        let drained = queue.drain(afterCompleting: 2)
        XCTAssertEqual(drained, [.redirect(instruction: "改走只读")])
        // 再取一次不重复生效
        XCTAssertTrue(queue.drain(afterCompleting: 3).isEmpty)
    }

    func testStopStopsAfterCurrentStep() {
        var queue = AgentInterventionQueue()
        queue.enqueue(.stop(reason: "方向错了"), duringStep: 4)
        let drained = queue.drain(afterCompleting: 4)
        XCTAssertTrue(AgentInterventionQueue.stops(in: drained))
        XCTAssertEqual(AgentInterventionQueue.effect(of: .stop(reason: "x")), .stopsAfterCurrentStep)
    }

    func testConstraintAccumulatesAndKeepsEarlierResults() {
        var queue = AgentInterventionQueue()
        queue.enqueue(.constraint(text: "只读"), duringStep: 1)
        queue.enqueue(.constraint(text: "不许改 Vendor/"), duringStep: 1)
        let drained = queue.drain(afterCompleting: 1)
        XCTAssertEqual(AgentInterventionQueue.constraints(from: drained), ["只读", "不许改 Vendor/"])
        // 干预队列不持有也不清空结果 —— 它只回答「下一步要遵守什么」
        XCTAssertEqual(drained.count, 2)
    }

    func testLatestRedirectWins() {
        var queue = AgentInterventionQueue()
        queue.enqueue(.redirect(instruction: "先看日志"), duringStep: 1)
        queue.enqueue(.redirect(instruction: "先看配置"), duringStep: 1)
        let drained = queue.drain(afterCompleting: 1)
        XCTAssertEqual(AgentInterventionQueue.redirect(from: drained), "先看配置")
    }

    func testPendingStopIsVisibleBeforeDrain() {
        var queue = AgentInterventionQueue()
        XCTAssertFalse(queue.stopsRequested)
        queue.enqueue(.stop(reason: "x"), duringStep: 9)
        XCTAssertTrue(queue.stopsRequested)
        XCTAssertFalse(queue.isEmpty)
        _ = queue.drain(afterCompleting: 9)
        XCTAssertTrue(queue.isEmpty)
    }

    func testFutureStepIsNotDrainedEarly() {
        var queue = AgentInterventionQueue()
        queue.enqueue(.stop(reason: "x"), duringStep: 5)
        XCTAssertTrue(queue.drain(afterCompleting: 4).isEmpty)
        XCTAssertFalse(queue.isEmpty)
    }
}
