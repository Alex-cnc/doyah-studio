import XCTest
@testable import DoyahCore

/// 整批撤回（`FR-STD-WS-EDIT-015`）的机械判据。
///
/// 盯住三处：**只撤 Agent 改的**、**人改过的不覆盖**（冲突逐条点名）、
/// **计划与落盘分开**（先能对拍计划，再验磁盘）。
final class AgentWriteBatchRevertTests: XCTestCase {

    private func snapshot(path: String, previous: String?, written: String) -> AgentWriteSnapshot {
        AgentWriteSnapshot(path: path, previousText: previous,
                           writtenDigest: AgentWriteSnapshot.digest(written))
    }

    // MARK: - 正常撤回

    func testRestoresPreviousContent() {
        let snap = snapshot(path: "a.swift", previous: "旧内容", written: "新内容")
        let steps = AgentWriteBatchRevert.plan(snapshots: [snap]) { path in
            path == "a.swift" ? "新内容" : nil
        }
        XCTAssertEqual(steps, [.restore(path: "a.swift", text: "旧内容")])
    }

    func testDeletesFileThatWasCreatedByTheAgent() {
        let snap = snapshot(path: "new.swift", previous: nil, written: "新建的")
        let steps = AgentWriteBatchRevert.plan(snapshots: [snap]) { _ in "新建的" }
        XCTAssertEqual(steps, [.delete(path: "new.swift")])
    }

    // MARK: - 人不背锅

    func testDoesNotTouchFileChangedByHumanAfterwards() {
        let snap = snapshot(path: "a.swift", previous: "旧内容", written: "Agent 写的")
        let steps = AgentWriteBatchRevert.plan(snapshots: [snap]) { _ in "人又改过的" }
        XCTAssertEqual(steps, [.conflict(path: "a.swift", reason: .changedSinceWrite)],
                       "写成之后被改过 ⇒ 一个字都不动")
    }

    func testCreatedFileAlreadyGoneIsReported() {
        let snap = snapshot(path: "new.swift", previous: nil, written: "新建的")
        let steps = AgentWriteBatchRevert.plan(snapshots: [snap]) { _ in nil }
        XCTAssertEqual(steps, [.conflict(path: "new.swift", reason: .alreadyGone)])
    }

    func testFileDeletedElsewhereIsNotResurrected() {
        let snap = snapshot(path: "a.swift", previous: "旧内容", written: "新内容")
        let steps = AgentWriteBatchRevert.plan(snapshots: [snap]) { _ in nil }
        XCTAssertEqual(steps, [.conflict(path: "a.swift", reason: .reappeared)],
                       "原来有、现在没了 ⇒ 别人删的，不许凭空造回来")
    }

    func testUntouchedFilesNeverEnterThePlan() {
        let snap = snapshot(path: "a.swift", previous: "旧", written: "新")
        let steps = AgentWriteBatchRevert.plan(snapshots: [snap]) { path in
            path == "b.swift" ? "人改的" : "新"
        }
        XCTAssertEqual(steps.count, 1, "批次里没有的路径不该出现在计划里")
        XCTAssertFalse(steps.contains { if case .restore(let p, _) = $0 { return p == "b.swift" }; return false })
    }

    // MARK: - 同一路径多次写入

    func testRepeatedWritesCollapseToTheEarliestPreImage() {
        let first = snapshot(path: "a.swift", previous: "最初", written: "第一次")
        let second = snapshot(path: "a.swift", previous: "第一次", written: "第二次")
        let steps = AgentWriteBatchRevert.plan(snapshots: [first, second]) { _ in "第二次" }
        XCTAssertEqual(steps, [.restore(path: "a.swift", text: "第一次")],
                       "只留最后一次写入的前像（撤回到下一次写之前）")
    }

    // MARK: - 落盘

    func testApplyWritesAndDeletesAndReportsConflicts() throws {
        let steps: [AgentRevertStep] = [
            .restore(path: "a.swift", text: "旧内容"),
            .delete(path: "new.swift"),
            .conflict(path: "b.swift", reason: .changedSinceWrite),
        ]
        var written: [String: String?] = [:]
        let result = try AgentWriteBatchRevert.apply(steps) { path, text in
            written[path] = text
        }
        XCTAssertEqual(result.applied, 2)
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(written["a.swift"], "旧内容")
        XCTAssertEqual(written["new.swift"], .some(nil), "删除即写 nil")
        XCTAssertNil(written["b.swift"], "冲突的不动")
    }

    func testDigestIsStableAndShort() {
        XCTAssertEqual(AgentWriteSnapshot.digest("同一段正文"), AgentWriteSnapshot.digest("同一段正文"))
        XCTAssertNotEqual(AgentWriteSnapshot.digest("甲"), AgentWriteSnapshot.digest("乙"))
        XCTAssertEqual(AgentWriteSnapshot.digest("甲").count, 16)
    }
}
