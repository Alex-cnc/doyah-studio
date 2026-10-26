import XCTest
@testable import DoyahCore

/// `FR-AGT-KNOW-CTX-002`（压缩落地）与 `FR-AGT-KNOW-MEM-002~005`（记忆治理）判据。
final class AgentKnowledgeTests: XCTestCase {

    // MARK: 压缩：优先级 + 可见标记 + 确定性

    private func sections() -> [AgentContextBudgetedSection] {
        [
            .init(id: "constraint", priority: .critical, body: String(repeating: "c", count: 20)),
            .init(id: "decision", priority: .high, body: String(repeating: "d", count: 40)),
            .init(id: "file", priority: .normal, body: String(repeating: "f", count: 100)),
            .init(id: "verbose", priority: .low, body: String(repeating: "v", count: 400)),
        ]
    }

    func testCriticalSurvivesAndLowDropsFirst() {
        let (kept, report) = AgentContextPriorityTruncator.truncate(sections(), maxCharacters: 70)
        XCTAssertTrue(kept.contains { $0.id == "constraint" })
        XCTAssertTrue(kept.contains { $0.id == "decision" })
        XCTAssertTrue(report.droppedIDs.contains("verbose"), "低优先级先丢")
        XCTAssertTrue(report.droppedIDs.contains("file"))
        XCTAssertTrue(report.didTruncate)
    }

    func testMarkerIsVisibleAndNamesDroppedSections() {
        let (_, report) = AgentContextPriorityTruncator.truncate(sections(), maxCharacters: 70)
        XCTAssertTrue(report.marker.contains("truncated"))
        XCTAssertTrue(report.marker.contains("verbose"))
    }

    func testNoTruncationWhenWithinBudget() {
        let (kept, report) = AgentContextPriorityTruncator.truncate(sections(), maxCharacters: 10_000)
        XCTAssertEqual(kept.count, 4)
        XCTAssertEqual(report.marker, "")
        XCTAssertFalse(report.didTruncate)
        XCTAssertEqual(report.charactersBefore, report.charactersAfter)
    }

    func testTruncationIsDeterministic() {
        let a = AgentContextPriorityTruncator.truncate(sections(), maxCharacters: 70)
        let b = AgentContextPriorityTruncator.truncate(sections(), maxCharacters: 70)
        XCTAssertEqual(a.report, b.report)
        XCTAssertEqual(a.kept.map(\.id), b.kept.map(\.id))
    }

    func testCriticalMayExceedBudgetRatherThanBeDropped() {
        let only = [AgentContextBudgetedSection(id: "soul", priority: .critical, body: String(repeating: "x", count: 200))]
        let (kept, report) = AgentContextPriorityTruncator.truncate(only, maxCharacters: 10)
        XCTAssertEqual(kept.count, 1, "约束永不被丢，宁可超预算")
        XCTAssertEqual(report.charactersAfter, 200)
        XCTAssertFalse(report.didTruncate)
    }

    // MARK: 记忆治理

    private func governance() throws -> AgentMemoryGovernance {
        var g = AgentMemoryGovernance()
        try g.upsert(kind: .preference, key: "language", value: "中文", source: "会话 1")
        try g.upsert(kind: .constraint, key: "readonly", value: "只读模式", source: "会话 2")
        try g.upsert(kind: .fact, key: "repo", value: "doyah-studio", source: "会话 3")
        return g
    }

    func testListIsStableAndFilterable() throws {
        let g = try governance()
        XCTAssertEqual(g.list().count, 3)
        XCTAssertEqual(g.list(kind: .constraint).map(\.key), ["readonly"])
        XCTAssertEqual(g.list(), g.list(), "两次导出必须逐字相同")
    }

    func testExplainSaysWhereItCameFrom() throws {
        let g = try governance()
        let text = g.explain(id: "preference:language")
        XCTAssertEqual(text, "preference/language = 中文 ← 会话 1")
        XCTAssertNil(g.explain(id: "nope"))
    }

    func testDeleteReallyDeletes() throws {
        var g = try governance()
        XCTAssertTrue(g.delete(id: "preference:language"))
        XCTAssertNil(g.item(id: "preference:language"))
        XCTAssertFalse(g.export().contains("language"), "真删：导出里也不许再出现")
        XCTAssertFalse(g.delete(id: "preference:language"), "再删一次返回 false")
    }

    func testDeleteAllByKind() throws {
        var g = try governance()
        XCTAssertEqual(g.deleteAll(kind: .constraint), 1)
        XCTAssertTrue(g.list(kind: .constraint).isEmpty)
        XCTAssertEqual(g.list().count, 2)
    }

    func testUpsertReplacesSameKey() throws {
        var g = try governance()
        try g.upsert(kind: .preference, key: "language", value: "英文", source: "会话 4")
        XCTAssertEqual(g.list(kind: .preference).count, 1, "同键只留一条")
        XCTAssertEqual(g.item(id: "preference:language")?.value, "英文")
    }

    func testEmptyValueRejected() throws {
        var g = try governance()
        XCTAssertThrowsError(try g.upsert(kind: .fact, key: "k", value: "   ", source: "s")) { error in
            XCTAssertEqual(error as? AgentMemoryGovernanceError, .emptyValue)
        }
        XCTAssertThrowsError(try g.upsert(kind: .fact, key: " ", value: "v", source: "s")) { error in
            XCTAssertEqual(error as? AgentMemoryGovernanceError, .emptyKey)
        }
    }

    // MARK: 技能候选

    func testSkillCandidatesAreParameterized() throws {
        let g = AgentMemoryGovernance()
        let candidates = g.skillCandidates(from: [
            "swift test --filter AgentA",
            "swift test --filter AgentB",
            "git status",
        ])
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.key, "swift test --filter <value>")
        XCTAssertEqual(candidates.first?.kind, .skillCandidate)
    }

    func testParameterizeReplacesPathsAndFiles() {
        XCTAssertEqual(AgentMemoryGovernance.parameterize("cat /work/proj/Core/A.swift"),
                       "cat <path>")
        XCTAssertEqual(AgentMemoryGovernance.parameterize("swift build --package-path /work/x"),
                       "swift build --package-path <path>")
    }

    func testSingleOccurrenceIsNotACandidate() {
        let g = AgentMemoryGovernance()
        XCTAssertTrue(g.skillCandidates(from: ["git status"]).isEmpty)
    }
}
