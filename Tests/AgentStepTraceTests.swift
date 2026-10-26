import XCTest
@testable import DoyahCore

/// `FR-AGT-UX-CONV-006`（过程可见）判据：**每一步都必须留下一行，不许有静默步**。
final class AgentStepTraceTests: XCTestCase {

    func testEveryDeclaredStepGetsOneRecord() {
        var trace = AgentStepTrace()
        for i in 1...3 {
            trace.record(kind: .tool, label: "step-\(i)")
        }
        XCTAssertEqual(trace.records.count, 3)
        XCTAssertEqual(trace.silentSteps(declared: 3), 0)
        XCTAssertTrue(trace.isEveryStepVisible(declared: 3))
    }

    func testSilentStepIsDetected() {
        var trace = AgentStepTrace()
        trace.record(kind: .tool, label: "read_file")
        trace.record(kind: .command, label: "git status")
        // 声明跑了 3 跳，只留了 2 行 ⇒ 有 1 个静默步
        XCTAssertEqual(trace.silentSteps(declared: 3), 1)
        XCTAssertFalse(trace.isEveryStepVisible(declared: 3))
    }

    func testIndexIsAssignedByTraceNotCaller() {
        var trace = AgentStepTrace()
        trace.record(kind: .file, label: "Core/A.swift")
        trace.record(kind: .approval, label: "write_file")
        XCTAssertEqual(trace.records.map(\.index), [1, 2])
    }

    func testDuplicateIndexDoesNotCountTwice() {
        // 手工塞重号记录（不该发生，但一旦发生不许算成「两步都可见」）
        var trace = AgentStepTrace(records: [
            AgentStepRecord(index: 1, kind: .tool, label: "a"),
            AgentStepRecord(index: 1, kind: .tool, label: "b"),
        ])
        trace.record(kind: .tool, label: "c")
        XCTAssertEqual(trace.silentSteps(declared: 3), 1)
    }

    func testFilterByKind() {
        var trace = AgentStepTrace()
        trace.record(kind: .tool, label: "search")
        trace.record(kind: .file, label: "Core/A.swift")
        trace.record(kind: .file, label: "Core/B.swift")
        XCTAssertEqual(trace.records(of: .file).count, 2)
        XCTAssertEqual(trace.records(of: .command).count, 0)
    }

    func testDetailIsOptionalAndPreserved() {
        var trace = AgentStepTrace()
        trace.record(kind: .tool, label: "read_file", detail: "越界被拒")
        XCTAssertEqual(trace.records.first?.detail, "越界被拒")
        trace.record(kind: .tool, label: "search")
        XCTAssertNil(trace.records.last?.detail)
    }
}
