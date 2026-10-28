import XCTest
@testable import DoyahCore

/// 整批撤回的**接线面判据**（`FR-STD-WS-EDIT-015`）：账当唯一前像来源、一次撤回全还原、
/// 人改过的不覆盖、撤回本身可再撤回、回执的读数来自落盘而不是自己数。
///
/// 为什么这一族与 `AgentWriteBatchRevertTests` 分开：那一族钉的是「计划/落盘」这两条纯函数，
/// 这一族钉的是「从账算批次」这条接线 —— 少了它，账里记的前像与撤回用的前像可以是两份。
final class AgentBatchRevertTests: XCTestCase {

    /// 假的盘：撤回是「按计划写盘」，用字典就能逐字节对拍（不必每次落真文件）。
    private final class Disk {
        var files: [String: String]
        init(_ files: [String: String]) { self.files = files }
        func read(_ path: String) -> String? { files[path] }
        func write(_ path: String, _ text: String?) {
            if let text { files[path] = text } else { files.removeValue(forKey: path) }
        }
    }

    private func edit(_ path: String, before: String?, after: String,
                      card: UUID = UUID()) -> AgentAppliedEdit {
        AgentAppliedEdit(cardID: card, path: path, before: before, after: after)
    }

    // MARK: - 账 → 批次

    func testSnapshotsComeStraightFromTheJournal() {
        let snaps = AgentWriteBatchRevert.snapshots(from: [edit("a.swift", before: "旧", after: "新")])
        XCTAssertEqual(snaps.count, 1)
        XCTAssertEqual(snaps[0].path, "a.swift")
        XCTAssertEqual(snaps[0].previousText, "旧", "前像就是账上那一份，不许另存")
        XCTAssertEqual(snaps[0].writtenDigest, AgentWriteSnapshot.digest("新"))
    }

    func testBatchRevertsRepeatedWriteBackToBeforeTheWholeBatch() {
        // 一批里同一个文件改了两次：撤回要回到**本批之前**，不是回到上一次写之前。
        let disk = Disk(["a.swift": "第二次"])
        let edits = [edit("a.swift", before: "最初", after: "第一次"),
                     edit("a.swift", before: "第一次", after: "第二次")]
        let steps = AgentWriteBatchRevert.plan(snapshots: AgentWriteBatchRevert.snapshots(from: edits),
                                              reader: disk.read)
        XCTAssertEqual(steps, [.restore(path: "a.swift", text: "最初")])
    }

    // MARK: - 人不背锅

    func testHumanEditIsNamedAndNeverWritten() throws {
        let disk = Disk(["a.swift": "人又改过的", "b.swift": "Agent 写的"])
        let edits = [edit("a.swift", before: "旧", after: "Agent 写的"),
                     edit("b.swift", before: "更旧", after: "Agent 写的")]
        let steps = AgentWriteBatchRevert.plan(snapshots: AgentWriteBatchRevert.snapshots(from: edits),
                                              reader: disk.read)
        XCTAssertEqual(steps, [.conflict(path: "a.swift", reason: .changedSinceWrite),
                               .restore(path: "b.swift", text: "更旧")])
        let result = try AgentWriteBatchRevert.apply(steps) { path, text in disk.write(path, text) }
        XCTAssertEqual(result.applied, 1)
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(disk.read("a.swift"), "人又改过的", "冲突的那条一个字都不许动")
        XCTAssertEqual(disk.read("b.swift"), "更旧")
    }

    // MARK: - 撤回本身可再撤回

    func testInverseBatchReturnsToTheVersionTheAgentWrote() throws {
        let disk = Disk(["a.swift": "Agent 写的"])
        let edits = [edit("a.swift", before: "旧", after: "Agent 写的")]
        let steps = AgentWriteBatchRevert.plan(snapshots: AgentWriteBatchRevert.snapshots(from: edits),
                                              reader: disk.read)
        // 反向批次**落盘前**算（落盘后就只剩撤后的样子了）。
        let inverse = AgentWriteBatchRevert.inverse(of: steps, reader: disk.read)
        _ = try AgentWriteBatchRevert.apply(steps) { path, text in disk.write(path, text) }
        XCTAssertEqual(disk.read("a.swift"), "旧")
        let back = AgentWriteBatchRevert.plan(snapshots: inverse, reader: disk.read)
        _ = try AgentWriteBatchRevert.apply(back) { path, text in disk.write(path, text) }
        XCTAssertEqual(disk.read("a.swift"), "Agent 写的", "撤销这次撤回 ⇒ 回到 Agent 写完那一份")
    }

    func testInverseOfACreatedFileBringsItBack() throws {
        let disk = Disk(["new.swift": "新建的"])
        let edits = [edit("new.swift", before: nil, after: "新建的")]
        let steps = AgentWriteBatchRevert.plan(snapshots: AgentWriteBatchRevert.snapshots(from: edits),
                                              reader: disk.read)
        XCTAssertEqual(steps, [.delete(path: "new.swift")])
        let inverse = AgentWriteBatchRevert.inverse(of: steps, reader: disk.read)
        _ = try AgentWriteBatchRevert.apply(steps) { path, text in disk.write(path, text) }
        XCTAssertNil(disk.read("new.swift"), "Agent 新建的文件，撤回 = 删掉")
        _ = try AgentWriteBatchRevert.apply(
            AgentWriteBatchRevert.plan(snapshots: inverse, reader: disk.read)
        ) { path, text in disk.write(path, text) }
        XCTAssertEqual(disk.read("new.swift"), "新建的", "再撤一次要把这个文件原样造回来")
    }

    func testInverseSkipsStepsThatNeverTouchedTheDisk() {
        let steps: [AgentRevertStep] = [.conflict(path: "a.swift", reason: .changedSinceWrite),
                                        .restore(path: "b.swift", text: "旧")]
        let inverse = AgentWriteBatchRevert.inverse(of: steps) { $0 == "b.swift" ? "Agent 写的" : "别处的" }
        XCTAssertEqual(inverse.count, 1, "冲突步没动过盘 —— 反向批次里不许出现它")
        XCTAssertEqual(inverse[0].path, "b.swift")
    }

    // MARK: - 回执（留痕）

    func testReceiptTakesItsCountsFromTheWriteResult() {
        let steps: [AgentRevertStep] = [.restore(path: "a", text: "旧"),
                                        .delete(path: "b"),
                                        .conflict(path: "c", reason: .changedSinceWrite)]
        let result = (applied: 2, conflicts: [steps[2]])
        let ids = [UUID(), UUID()]
        let receipt = AgentBatchRevertReceipt.make(batchID: UUID(), at: Date(),
                                                  result: result, cardIDs: ids)
        XCTAssertEqual(receipt.reverted, 2)
        XCTAssertEqual(receipt.unmoved.map(\.path), ["c"])
        XCTAssertEqual(receipt.unmoved.first?.reason, .changedSinceWrite)
        XCTAssertEqual(receipt.total, 3)
        XCTAssertFalse(receipt.isClean)
        XCTAssertEqual(receipt.cardIDs, ids)
    }

    func testCleanReceiptSaysSo() {
        let receipt = AgentBatchRevertReceipt.make(batchID: UUID(), at: Date(),
                                                  result: (applied: 3, conflicts: []),
                                                  cardIDs: [])
        XCTAssertTrue(receipt.isClean)
        XCTAssertEqual(receipt.total, 3)
    }

    // MARK: - 账的「已撤」标记是对称的

    func testUndoneMarkCanBeTakenBackSoTheBatchIsUndoableAgain() {
        var journal = AgentEditJournal()
        let card = UUID()
        journal.record(cardID: card, path: "a.swift", before: "旧", after: "新")
        XCTAssertEqual(journal.undoable.count, 1)
        XCTAssertTrue(journal.markUndone(card))
        XCTAssertEqual(journal.undoable.count, 0, "撤过就不能再撤一次")
        XCTAssertTrue(journal.unmarkUndone(card))
        XCTAssertEqual(journal.undoable.count, 1, "「撤销这次撤回」之后这一笔重新可撤")
    }
}
