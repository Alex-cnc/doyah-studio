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

    // MARK: 记忆治理（真实现：`AgentMemoryStore` + `MemoryGovernance`）
    //
    // 2026-11-18：原先这里判的是 `AgentMemoryGovernance` —— 一个**零生产引用的重复抽象**：
    // 它的类别词表（preference/fact/constraint/skill）与需求书里那份（`MemoryKind`：routine /
    // troubleshooting / pinned / general）对不上，而「按类型分生命周期 / 解释 / 升格脱敏」在
    // `Core/MemoryGovernance.swift` 里早有实现并在用。同一能力两处真源 ⇒ 删掉它，判据改判活的那份。

    private func seededStore() throws -> (AgentMemoryStore, String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-mem-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = AgentMemoryStore(directory: dir)
        let workspace = dir.path
        for (kind, note) in [(MemoryKind.pinned, "巡检脚本"),
                             (MemoryKind.routine, "每日汇总"),
                             (MemoryKind.general, "跨连接写法")] {
            try store.record(AgentMemoryDraft(workspace: workspace, connection: "", kind: kind,
                                              note: note, key: nil))
        }
        return (store, workspace)
    }

    /// `FR-AGT-KNOW-MEM-002` ②：**按类别清空**只删这一类，其余原样留着，且是**真删**。
    func testRemoveAllByKindOnlyTouchesThatKind() throws {
        let (store, workspace) = try seededStore()
        let removed = try store.removeAll(kind: .pinned, workspace: workspace)
        XCTAssertEqual(removed, 1, "只该删掉那一条")
        let left = store.entries(workspace: workspace).entries
        XCTAssertEqual(left.count, 2)
        XCTAssertFalse(left.contains { $0.memoryKind == .pinned }, "这一类必须真删（不是打标记）")
        XCTAssertEqual(try store.removeAll(kind: .pinned, workspace: workspace), 0,
                       "再删一次 = 0（没这条也算如实）")
    }

    /// `FR-AGT-KNOW-MEM-002` ②：删单条 = 真删，不连坐。
    func testRemoveByIdReallyDeletes() throws {
        let (store, workspace) = try seededStore()
        let id = try XCTUnwrap(store.entries(workspace: workspace).entries.first?.id)
        XCTAssertTrue(try store.remove(id: id, workspace: workspace))
        XCTAssertEqual(store.entries(workspace: workspace).entries.count, 2)
    }
}
