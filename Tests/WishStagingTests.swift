import XCTest
@testable import DoyahCore

/// 许愿式编程（`FR-STD-WS-AI-002`）：暂存 → 清单与差异 → 验证口径 → 验收落盘 → 可整批撤回。
///
/// 这一套判据的**否定面**是重点：暂存期间磁盘必须一个字节都不动、越界路径必须进拒绝而不是进清单、
/// 验证没跑通必须标「没跑通」且默认不许落盘。
final class WishStagingTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wish-staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }
    private func read(_ relative: String) -> String? { try? String(contentsOf: url(relative), encoding: .utf8) }

    @discardableResult
    private func write(_ relative: String, _ text: String) throws -> URL {
        let target = url(relative)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try text.write(to: target, atomically: true, encoding: .utf8)
        return target
    }

    private func makeStaging(maxFiles: Int = 64, maxFileBytes: Int = 512 * 1024) -> WishStaging {
        WishStaging(root: root, runID: "wish-1", maxFiles: maxFiles, maxFileBytes: maxFileBytes)
    }

    // MARK: - ① 先出改动、不先生效

    func testStagingLeavesDiskUntouchedUntilAccept() throws {
        try write("a.swift", "旧内容\n")
        let staging = makeStaging()

        let outcome = staging.stageWrite(path: "a.swift", text: "新内容\n")
        XCTAssertEqual(outcome, .staged(path: "a.swift", kind: .modified))
        XCTAssertEqual(read("a.swift"), "旧内容\n", "暂存期间磁盘必须一个字节都不动")

        let proposal = staging.proposal
        XCTAssertEqual(proposal.state, .awaitingAcceptance)
        XCTAssertEqual(proposal.changes.count, 1)
        XCTAssertEqual(proposal.changes[0].kind, .modified)
        XCTAssertEqual(proposal.changes[0].addedLines, 1)
        XCTAssertEqual(proposal.changes[0].removedLines, 1)
        XCTAssertTrue(proposal.changes[0].diff.contains(AgentTextDiff.Line(kind: .added, text: "新内容")))

        let result = staging.accept()
        XCTAssertTrue(result.didWriteAnything)
        XCTAssertEqual(result.applied, ["a.swift"])
        XCTAssertEqual(read("a.swift"), "新内容\n")
        XCTAssertEqual(staging.stagedCount, 0, "验收过的条目不该留在暂存里")
    }

    func testCreatedFileShowsEveryLineAsAdded() throws {
        let staging = makeStaging()
        XCTAssertEqual(staging.stageWrite(path: "docs/new.md", text: "一\n二"),
                       .staged(path: "docs/new.md", kind: .created))

        let change = try XCTUnwrap(staging.proposal.changes.first)
        XCTAssertEqual(change.kind, .created)
        XCTAssertEqual(change.addedLines, 2)
        XCTAssertEqual(change.removedLines, 0)
        XCTAssertNil(change.beforeDigest, "本来不存在的文件没有前像")

        _ = staging.accept()
        XCTAssertEqual(read("docs/new.md"), "一\n二", "验收时缺的中间目录要一起建出来")
    }

    func testDeletingAFileIsAChangeButDiskKeepsItUntilAccept() throws {
        try write("b.swift", "留着")
        let staging = makeStaging()
        XCTAssertEqual(staging.stageDelete(path: "b.swift"), .staged(path: "b.swift", kind: .deleted))
        XCTAssertEqual(read("b.swift"), "留着")
        XCTAssertEqual(try XCTUnwrap(staging.proposal.changes.first).removedLines, 1)

        _ = staging.accept()
        XCTAssertNil(read("b.swift"))
    }

    // MARK: - 空暂存：如实说没改，且不许落盘

    func testEmptyStagingReportsNoChangesAndIsBlocked() {
        let staging = makeStaging()
        let proposal = staging.proposal
        XCTAssertEqual(proposal.state, .noChanges)
        XCTAssertTrue(proposal.changes.isEmpty)
        XCTAssertEqual(proposal.addedTotal, 0)

        let result = staging.accept()
        XCTAssertEqual(result.block, .noChanges)
        XCTAssertFalse(result.didWriteAnything, "没有改动就不许有落盘动作")
    }

    func testWriteThenDeleteInTheSameRunIsNoChange() throws {
        let staging = makeStaging()
        XCTAssertEqual(staging.stageWrite(path: "tmp.txt", text: "x"), .staged(path: "tmp.txt", kind: .created))
        XCTAssertEqual(staging.stageDelete(path: "tmp.txt"), .unchanged(path: "tmp.txt"))
        XCTAssertEqual(staging.proposal.state, .noChanges, "净效果为零的活不该出现在清单里")
    }

    func testStagingTheSameTextAsOnDiskIsNotAChange() throws {
        try write("c.swift", "原样\n")
        let staging = makeStaging()
        XCTAssertEqual(staging.stageWrite(path: "c.swift", text: "原样\n"), .unchanged(path: "c.swift"))
        XCTAssertEqual(staging.proposal.state, .noChanges)
    }

    // MARK: - 同一路径多次写：差异按「暂存开始前」算

    func testSamePathTwiceKeepsTheOriginalBeforeImage() throws {
        try write("d.swift", "一\n二\n三\n")
        let staging = makeStaging()
        staging.stageWrite(path: "d.swift", text: "一\n二\n三\n四\n")
        staging.stageWrite(path: "d.swift", text: "一\n四\n")

        let proposal = staging.proposal
        XCTAssertEqual(proposal.changes.count, 1, "同一路径只出一条改动")
        let change = try XCTUnwrap(proposal.changes.first)
        XCTAssertEqual(change.addedLines, 1)
        XCTAssertEqual(change.removedLines, 2)
        _ = staging.accept()
        XCTAssertEqual(read("d.swift"), "一\n四\n", "落盘的必须是最后一次暂存的正文")
    }

    // MARK: - 越界与坏输入：进拒绝，不进清单

    func testPathOutsideTheWorkspaceIsRejectedAndNeverEntersTheList() {
        let staging = makeStaging()
        let outcome = staging.stageWrite(path: "../escape.txt", text: "x")
        guard case .rejected(let rejection) = outcome else {
            return XCTFail("越界路径必须被拒，实际：\(outcome)")
        }
        XCTAssertEqual(rejection.reason, .outsideWorkspace)
        XCTAssertTrue(staging.proposal.changes.isEmpty, "被拒的东西不许出现在「改了哪些文件」里")
        XCTAssertEqual(staging.proposal.rejections.count, 1)
    }

    func testDeletingSomethingThatIsNotThereIsRejected() {
        let staging = makeStaging()
        let outcome = staging.stageDelete(path: "nope.txt")
        guard case .rejected(let rejection) = outcome else {
            return XCTFail("删不存在的文件必须如实拒，实际：\(outcome)")
        }
        XCTAssertEqual(rejection.reason, .missingTarget)
    }

    func testTooManyFilesIsRejectedInsteadOfSilentlyDropped() throws {
        let staging = makeStaging(maxFiles: 2)
        XCTAssertEqual(staging.stageWrite(path: "1.txt", text: "a"), .staged(path: "1.txt", kind: .created))
        XCTAssertEqual(staging.stageWrite(path: "2.txt", text: "b"), .staged(path: "2.txt", kind: .created))
        let third = staging.stageWrite(path: "3.txt", text: "c")
        guard case .rejected(let rejection) = third else {
            return XCTFail("超出上限必须拒，实际：\(third)")
        }
        XCTAssertEqual(rejection.reason, .tooManyFiles)
        XCTAssertEqual(staging.proposal.changes.count, 2)
    }

    func testOversizedFileIsRejected() {
        let staging = makeStaging(maxFileBytes: 4)
        let outcome = staging.stageWrite(path: "big.txt", text: "超过四个字节")
        guard case .rejected(let rejection) = outcome else {
            return XCTFail("超过上限必须拒，实际：\(outcome)")
        }
        XCTAssertEqual(rejection.reason, .fileTooLarge)
    }

    // MARK: - ③ 没跑通必须标「没跑通」

    func testFailedValidationIsReportedAndBlocksAccept() throws {
        try write("e.swift", "旧\n")
        let staging = makeStaging()
        staging.stageWrite(path: "e.swift", text: "新\n")
        staging.recordValidation(command: "swift build", exitCode: 1, outputTail: "error: boom")

        let proposal = staging.proposal
        XCTAssertEqual(proposal.state, .validationFailed)
        XCTAssertEqual(proposal.validation?.passed, false)
        XCTAssertFalse(proposal.isValidationMissing)

        let blocked = staging.accept()
        XCTAssertEqual(blocked.block, .validationFailed)
        XCTAssertEqual(read("e.swift"), "旧\n", "没跑通的产出不许悄悄落盘")
        XCTAssertEqual(staging.stagedCount, 1, "被拦住时暂存要留着，等人决定")

        let forced = staging.accept(allowFailedValidation: true)
        XCTAssertEqual(forced.applied, ["e.swift"])
        XCTAssertEqual(read("e.swift"), "新\n")
    }

    func testPassedValidationKeepsTheDeliverableAwaitingAcceptance() throws {
        let staging = makeStaging()
        staging.stageWrite(path: "f.swift", text: "ok\n")
        staging.recordValidation(command: "swift build", exitCode: 0)
        XCTAssertEqual(staging.proposal.state, .awaitingAcceptance)
        XCTAssertEqual(staging.proposal.validation?.passed, true)
        XCTAssertEqual(staging.accept().applied, ["f.swift"])
    }

    func testUnvalidatedRunIsNotTreatedAsPassed() {
        let staging = makeStaging()
        staging.stageWrite(path: "g.swift", text: "x\n")
        XCTAssertTrue(staging.proposal.isValidationMissing, "没验证过就是没验证过，不许当跑通了")
        XCTAssertEqual(staging.proposal.state, .awaitingAcceptance)
    }

    // MARK: - 丢弃

    func testDiscardThrowsAwayTheWholeBatchWithoutTouchingDisk() throws {
        try write("h.swift", "原样\n")
        let staging = makeStaging()
        staging.stageWrite(path: "h.swift", text: "改过\n")
        staging.stageWrite(path: "new.txt", text: "新")
        staging.discard()

        XCTAssertEqual(staging.proposal.state, .noChanges)
        XCTAssertEqual(read("h.swift"), "原样\n")
        XCTAssertNil(read("new.txt"))
        XCTAssertEqual(staging.accept().block, .noChanges)
    }

    // MARK: - ② 改坏可整批撤回（与 EDIT-015 的接口）

    func testAcceptedBatchCanBeRevertedAsAWhole() throws {
        try write("i.swift", "原内容\n")
        let staging = makeStaging()
        staging.stageWrite(path: "i.swift", text: "Agent 改的\n")
        staging.stageWrite(path: "j.swift", text: "Agent 新建的\n")
        let result = staging.accept()
        XCTAssertEqual(result.applied.sorted(), ["i.swift", "j.swift"])

        let store = WishStaging.batchStore(runID: "wish-1", result: result)
        let steps = store.plan { self.read($0) }
        XCTAssertEqual(steps, [.restore(path: "i.swift", text: "原内容\n"),
                               .delete(path: "j.swift")])

        for step in steps {
            switch step {
            case .restore(let path, let text):
                try write(path, text)
            case .delete(let path):
                try? FileManager.default.removeItem(at: url(path))
            case .conflict:
                break
            }
        }
        XCTAssertEqual(read("i.swift"), "原内容\n")
        XCTAssertNil(read("j.swift"), "Agent 新建的，撤回就是删掉")
    }

    func testHumanEditAfterAcceptIsLeftAloneOnRevert() throws {
        try write("k.swift", "原内容\n")
        let staging = makeStaging()
        staging.stageWrite(path: "k.swift", text: "Agent 改的\n")
        let result = staging.accept()
        try write("k.swift", "人又改的\n")

        let store = WishStaging.batchStore(runID: "wish-1", result: result)
        XCTAssertEqual(store.plan { self.read($0) },
                       [.conflict(path: "k.swift", reason: .changedSinceWrite)])
        XCTAssertEqual(read("k.swift"), "人又改的\n")
    }

    func testDeletedFileComesBackOnRevert() throws {
        try write("l.swift", "要留住的")
        let staging = makeStaging()
        staging.stageDelete(path: "l.swift")
        let result = staging.accept()
        XCTAssertNil(read("l.swift"))

        let store = WishStaging.batchStore(runID: "wish-1", result: result)
        XCTAssertEqual(store.plan { self.read($0) },
                       [.restore(path: "l.swift", text: "要留住的")],
                       "这次任务自己删的，撤回就是把前像还原")
    }

    func testFileDeletedBySomeoneElseAfterAcceptStillConflicts() throws {
        try write("m.swift", "原\n")
        let staging = makeStaging()
        staging.stageWrite(path: "m.swift", text: "改\n")
        let result = staging.accept()
        try FileManager.default.removeItem(at: url("m.swift"))

        let store = WishStaging.batchStore(runID: "wish-1", result: result)
        XCTAssertEqual(store.plan { self.read($0) },
                       [.conflict(path: "m.swift", reason: .reappeared)],
                       "别人的删除不许被当成「我们删的」凭空造回来")
    }
}
