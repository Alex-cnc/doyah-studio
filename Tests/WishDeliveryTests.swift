import XCTest
@testable import DoyahCore

/// 许愿式编程（`FR-STD-WS-AI-002`）的**交付面**：已落盘的账 → 改动清单 + 逐行差异 + 跑没跑通。
///
/// 否定面是重点：净效果为零的文件**不许**进清单（不编工作量）、没记验证读数**不许**当成跑通、
/// 验证非零必须落到 `.failed`（标明「没跑通」而不算交付成功）。
final class WishDeliveryTests: XCTestCase {

    private func edit(_ path: String, before: String?, after: String) -> AgentAppliedEdit {
        AgentAppliedEdit(cardID: UUID(), path: path, before: before, after: after)
    }

    private func make(_ edits: [AgentAppliedEdit],
                      validation: WishValidation? = nil) -> WishProposal {
        WishDelivery.proposal(runID: "wish-r1", root: "/tmp/ws", edits: edits, validation: validation)
    }

    // MARK: - ① 清单与差异

    func testNewFileIsCreatedWithOnlyAddedLines() {
        let proposal = make([edit("docs/new.md", before: nil, after: "一\n二")])

        XCTAssertEqual(proposal.state, .awaitingAcceptance)
        XCTAssertEqual(proposal.changes.count, 1)
        let change = proposal.changes[0]
        XCTAssertEqual(change.kind, .created)
        XCTAssertEqual(change.addedLines, 2)
        XCTAssertEqual(change.removedLines, 0, "新建文件的空前像不是「删掉一行」")
        XCTAssertNil(change.beforeDigest, "新建 ⇒ 前像不存在")
        XCTAssertNotNil(change.afterDigest)
        XCTAssertEqual(proposal.createdCount, 1)
        XCTAssertEqual(proposal.addedTotal, 2)
    }

    func testModifiedFileDiffMatchesTextDiff() {
        let proposal = make([edit("a.swift", before: "旧\n同一行", after: "新\n同一行")])

        let change = proposal.changes[0]
        XCTAssertEqual(change.kind, .modified)
        XCTAssertEqual(change.diff, AgentTextDiff.lines(before: "旧\n同一行", after: "新\n同一行"),
                       "差异必须与审批单同一份切分（同一输入同一读数）")
        XCTAssertEqual(change.addedLines, 1)
        XCTAssertEqual(change.removedLines, 1)
        XCTAssertEqual(proposal.modifiedCount, 1)
        XCTAssertEqual(proposal.removedTotal, 1)
        XCTAssertNotNil(change.beforeDigest)
    }

    func testSamePathTwiceYieldsOneRowFromEarliestBeforeToLatestAfter() {
        let proposal = make([
            edit("a.swift", before: "v1", after: "v2"),
            edit("a.swift", before: "v2", after: "v3")
        ])

        XCTAssertEqual(proposal.changes.count, 1, "同一路径只出一条")
        let change = proposal.changes[0]
        XCTAssertEqual(change.kind, .modified)
        XCTAssertEqual(change.diff, AgentTextDiff.lines(before: "v1", after: "v3"),
                       "前像取最早、后像取最新 —— 取最后一次前像会漏掉一段差异")
        XCTAssertEqual(change.beforeDigest, AgentWriteSnapshot.digest("v1"))
        XCTAssertEqual(change.afterDigest, AgentWriteSnapshot.digest("v3"))
    }

    func testNetZeroChangeIsNotListed() {
        let proposal = make([edit("a.swift", before: "原文", after: "原文")])

        XCTAssertTrue(proposal.changes.isEmpty, "改完又改回原样不算改动")
        XCTAssertEqual(proposal.state, .noChanges)
        XCTAssertEqual(WishDelivery.verdict(of: proposal), .noChanges)
    }

    func testRowsAreSortedByPath() {
        let proposal = make([
            edit("z.swift", before: nil, after: "z"),
            edit("a/b.swift", before: nil, after: "b"),
            edit("m.swift", before: nil, after: "m")
        ])

        XCTAssertEqual(proposal.changes.map(\.path), ["a/b.swift", "m.swift", "z.swift"],
                       "排序稳定，读数才可比")
    }

    func testEmptyJournalSaysNoChanges() {
        let proposal = make([], validation: WishValidation(command: "swift build", exitCode: 0))

        XCTAssertTrue(proposal.changes.isEmpty)
        XCTAssertEqual(proposal.state, .noChanges)
        XCTAssertEqual(WishDelivery.verdict(of: proposal), .noChanges,
                       "什么都没改时验证通过也不叫交付成功")
    }

    // MARK: - ③ 没跑通要说没跑通

    func testNoValidationReadingIsUnverified() {
        let proposal = make([edit("a.swift", before: nil, after: "x")])

        XCTAssertNil(proposal.validation)
        XCTAssertTrue(proposal.isValidationMissing)
        XCTAssertEqual(WishDelivery.verdict(of: proposal), .unverified, "没记读数不许当成跑通了")
        XCTAssertFalse(proposal.isValidationMissing == false)
    }

    func testPassingValidationIsPassed() {
        let proposal = make([edit("a.swift", before: nil, after: "x")],
                            validation: WishValidation(command: "swift build", exitCode: 0))

        XCTAssertEqual(proposal.state, .awaitingAcceptance)
        XCTAssertEqual(WishDelivery.verdict(of: proposal), .passed)
    }

    func testFailingValidationIsMarkedFailed() {
        let proposal = make([edit("a.swift", before: nil, after: "x")],
                            validation: WishValidation(command: "swift test", exitCode: 1,
                                                       outputTail: "error: boom"))

        XCTAssertEqual(proposal.state, .validationFailed, "非零退出 ⇒ 状态必须是「没跑通」")
        XCTAssertEqual(WishDelivery.verdict(of: proposal), .failed)
        XCTAssertEqual(proposal.validation?.outputTail, "error: boom")
        XCTAssertEqual(proposal.validation?.command, "swift test")
    }

    func testVerdictIgnoresRejectionsAndCountsAddUp() {
        let proposal = make([
            edit("new.md", before: nil, after: "一\n二\n三"),
            edit("old.md", before: "一\n二", after: "一")
        ])

        XCTAssertEqual(proposal.changes.count, 2)
        XCTAssertEqual(proposal.createdCount + proposal.modifiedCount + proposal.deletedCount, 2)
        XCTAssertEqual(proposal.deletedCount, 0, "这个账上没有删除型改动（如实边界）")
        XCTAssertEqual(proposal.addedTotal, 3)
        XCTAssertEqual(proposal.removedTotal, 1)
        XCTAssertEqual(WishDelivery.verdict(of: proposal), .unverified)
    }
}
