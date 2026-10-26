import XCTest
@testable import DoyahCore

/// `FR-AGT-CORE-CTX-001`（上下文供给）与 `FR-AGT-UX-CONV-007`（干预接线）判据。
final class AgentContextWiringTests: XCTestCase {

    // MARK: 供给：五类来源、预算、去重、稳定

    func testAllFiveKindsProduceSectionsInStableOrder() {
        let sources = [
            AgentContextSource(kind: .schema, text: "public.users"),
            AgentContextSource(kind: .file, path: "/w/a.swift", text: "let a = 1"),
            AgentContextSource(kind: .selection, text: "let s = 2"),
            AgentContextSource(kind: .terminal, text: "$ swift build"),
            AgentContextSource(kind: .directory, path: "/w", text: "a.swift\nb.swift"),
        ]
        let result = AgentContextSupply.assemble(sources)
        XCTAssertEqual(result.sections.count, 5)
        XCTAssertEqual(result.sections.map(\.title),
                       ["selection", "file:/w/a.swift", "dir:/w", "terminal", "schema"])
        // 两次组装逐字相同
        XCTAssertEqual(result, AgentContextSupply.assemble(sources))
    }

    func testDuplicateSourceIsKeptOnce() {
        let sources = [
            AgentContextSource(kind: .file, path: "/w/a.swift", text: "first"),
            AgentContextSource(kind: .file, path: "/w/a.swift", text: "second"),
        ]
        let result = AgentContextSupply.assemble(sources)
        XCTAssertEqual(result.sections.count, 1)
        XCTAssertEqual(result.sections.first?.body, "first", "先到的胜")
        XCTAssertEqual(result.deduplicated, ["file#/w/a.swift"])
    }

    func testPerKindBudgetTruncatesWithVisibleMarker() {
        let long = String(repeating: "x", count: 100)
        let limits = AgentContextSupplyLimits(perFile: 10, perTerminal: 100)
        let result = AgentContextSupply.assemble([
            AgentContextSource(kind: .file, path: "/w/a", text: long),
            AgentContextSource(kind: .terminal, text: "short"),
        ], limits: limits)
        XCTAssertEqual(result.sections.first?.truncated, true)
        XCTAssertTrue(result.sections.first?.body.contains("[…truncated 90 chars]") ?? false)
        XCTAssertEqual(result.sections.last?.truncated, false)
    }

    func testTruncateKeepsTail() {
        let (text, truncated) = AgentContextSupply.truncate("abcdefghij", limit: 4)
        XCTAssertTrue(truncated)
        XCTAssertTrue(text.hasSuffix("ghij"), "保留最近的内容")
    }

    // MARK: 干预信箱（线程安全引用件）

    func testInboxDrainsOnlyAfterStep() {
        let inbox = AgentInterventionInbox()
        inbox.enqueue(.constraint(text: "只读"), duringStep: 2)
        XCTAssertEqual(inbox.pendingCount, 1)
        XCTAssertTrue(inbox.drain(afterCompleting: 1).isEmpty)
        XCTAssertEqual(inbox.drain(afterCompleting: 2), [.constraint(text: "只读")])
        XCTAssertTrue(inbox.isEmpty)
    }

    func testInboxReportsPendingStop() {
        let inbox = AgentInterventionInbox()
        XCTAssertFalse(inbox.hasPendingStop)
        inbox.enqueue(.stop(reason: "方向错了"), duringStep: 1)
        XCTAssertTrue(inbox.hasPendingStop)
    }
}
