import XCTest
@testable import DoyahCore

/// `FR-AI-25` ⑤：「差异应用后**可一步撤销**，撤销后文件**逐字节**回到应用前」。
///
/// 这一族判据咬的是**能落到字节上的事实** —— 撤销不是「界面上写着已撤销」，
/// 是盘上那份文件回到应用前的每一个字节（含换行符种类、末尾换行、非 ASCII）。
final class AgentEditJournalTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-undo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, to relative: String) throws {
        let url = root.appendingPathComponent(relative)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ relative: String) -> String? {
        try? String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    // MARK: - 账：记一笔 / 按卡片号找回 / 一步撤销取哪一条

    func testRecordAndLookupByCardIDNotByPath() {
        var journal = AgentEditJournal()
        let first = UUID(), second = UUID()
        // 同一个文件被改两次：按**卡片号**找回，两次各自的原文互不串味。
        journal.record(cardID: first, path: "a.swift", before: "v0", after: "v1")
        journal.record(cardID: second, path: "a.swift", before: "v1", after: "v2")

        XCTAssertEqual(journal.entry(for: first)?.before, "v0")
        XCTAssertEqual(journal.entry(for: second)?.before, "v1")
        XCTAssertEqual(journal.entries.count, 2)
    }

    func testLatestUndoableIsTheMostRecentUnreverted() {
        var journal = AgentEditJournal()
        let first = UUID(), second = UUID()
        journal.record(cardID: first, path: "a.txt", before: "A", after: "A2")
        journal.record(cardID: second, path: "b.txt", before: "B", after: "B2")
        XCTAssertEqual(journal.latestUndoable?.cardID, second, "一步撤销 = 最近一次")

        journal.markUndone(second)
        XCTAssertEqual(journal.latestUndoable?.cardID, first, "撤了最近那条，就轮到上一条")
        XCTAssertFalse(journal.canUndo(second), "同一笔不许撤两次（否则会拿旧原文盖掉后来改的内容）")
    }

    func testPayloadIsRestoreForExistingFileAndRemoveForNewFile() {
        let existing = AgentAppliedEdit(cardID: UUID(), path: "a.txt", before: "老正文", after: "新正文")
        XCTAssertEqual(AgentEditJournal.payload(for: existing), .restore("老正文"))

        let created = AgentAppliedEdit(cardID: UUID(), path: "new.txt", before: nil, after: "刚建的内容")
        XCTAssertEqual(AgentEditJournal.payload(for: created), .remove)
        XCTAssertTrue(created.createdFile)
        XCTAssertFalse(existing.createdFile)
    }

    func testMarkUndoneIsOneWayAndIdempotentRefuses() {
        var journal = AgentEditJournal()
        let card = UUID()
        journal.record(cardID: card, path: "a.txt", before: "x", after: "y")
        XCTAssertTrue(journal.markUndone(card))
        XCTAssertFalse(journal.markUndone(card), "第二次不许再标（同一笔只撤一次）")
        XCTAssertTrue(journal.undone.contains(card))
        XCTAssertEqual(journal.entries.count, 1, "撤销**不删账**：事后要能回答撤过哪一次")
    }

    // MARK: - 落盘：逐字节回到应用前

    func testRevertRestoresBytesExactlyIncludingTrailingNewlineAndUnicode() throws {
        // 原文刻意带：制表符 · 中文 · CRLF · 末尾空行 —— 这些都是「看起来一样但字节不同」的常客。
        let before = "第一行\t带制表\r\n第二行 枫叶 🍁\r\n\r\n"
        try write(before, to: "notes.txt")

        var journal = AgentEditJournal()
        let card = UUID()
        journal.record(cardID: card, path: "notes.txt", before: before, after: "被改过的正文")

        let reverter = AgentEditReverter(root: root)
        let edit = try XCTUnwrap(journal.entry(for: card))
        // 先模拟「已应用」：盘上就是 after 那一份。
        try "被改过的正文".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        guard case .restored(let restored) = reverter.revert(edit) else {
            return XCTFail("撤销应当成功")
        }
        XCTAssertEqual(restored, before)
        XCTAssertEqual(read("notes.txt"), before)
        // **字节级**：不认「字符串看起来一样」。
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("notes.txt")),
                       Data(before.utf8))
    }

    func testRevertRemovesFileThatDidNotExistBeforeApply() throws {
        // 应用前不存在 ⇒ 撤销是**删掉**，不是写成空串（空文件与不存在的文件是两回事）。
        try write("AI 新建的", to: "created.md")
        var journal = AgentEditJournal()
        let card = UUID()
        journal.record(cardID: card, path: "created.md", before: nil, after: "AI 新建的")
        let edit = try XCTUnwrap(journal.entry(for: card))

        guard case .removed = AgentEditReverter(root: root).revert(edit) else {
            return XCTFail("新建文件的撤销应当是删除")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("created.md").path))
    }

    func testRevertRefusesWhenFileChangedAgainAfterApply() throws {
        // 应用之后人又改过 ⇒ **不回退**（拿旧原文盖上去就是把人家后来的改动一起抹掉）。
        try write("应用后的正文", to: "live.txt")
        var journal = AgentEditJournal()
        let card = UUID()
        let before = "应用前的正文"
        journal.record(cardID: card, path: "live.txt", before: before, after: "应用后的正文")
        let edit = try XCTUnwrap(journal.entry(for: card))

        try write("应用后我又自己改的", to: "live.txt")   // 漂移

        guard case .refused(_, let detail) = AgentEditReverter(root: root).revert(edit) else {
            return XCTFail("漂移过就必须拒")
        }
        XCTAssertEqual(detail, "drifted", "拒的理由要能分辨：漂移不是写盘失败")
        XCTAssertEqual(read("live.txt"), "应用后我又自己改的", "拒了就不许动盘")
    }

    func testForceRevertStillRestoresWhenDrifted() throws {
        try write("应用后的正文", to: "live.txt")
        let edit = AgentAppliedEdit(cardID: UUID(), path: "live.txt",
                                    before: "应用前的正文", after: "应用后的正文")
        try write("漂移过的", to: "live.txt")

        guard case .restored(let text) = AgentEditReverter(root: root).revert(edit, force: true) else {
            return XCTFail("force 下应当回退")
        }
        XCTAssertEqual(text, "应用前的正文")
        XCTAssertEqual(read("live.txt"), "应用前的正文")
    }

    func testRevertRefusesOutsideWorkspace() {
        let edit = AgentAppliedEdit(cardID: UUID(), path: "../逃出去.txt", before: "x", after: "y")
        guard case .refused(.outsideWorkspace, _) = AgentEditReverter(root: root).revert(edit) else {
            return XCTFail("工作区外必须拒")
        }
    }

    func testSecondRevertAfterUndoIsRefusedNotSilentlyApplied() throws {
        // 撤过之后盘上已是 before，而账里的 after 对不上 ⇒ 再点一次必须是「拒」，
        // 不能因为「内容刚好等于 before」就当成又成功了一次（那会让界面显示已撤销两遍）。
        let before = "原文"
        // 模拟「已应用」：盘上此刻是 after 那一份。
        try write("改过", to: "again.txt")
        let edit = AgentAppliedEdit(cardID: UUID(), path: "again.txt", before: before, after: "改过")
        let reverter = AgentEditReverter(root: root)
        XCTAssertEqual(reverter.revert(edit), .restored(before))
        guard case .refused = reverter.revert(edit) else {
            return XCTFail("第二次应当拒（内容已不是应用后的那一份）")
        }
    }

    // MARK: - 编辑器缓冲区：什么时候跟着动

    func testBufferPlanOnlyReloadsCleanOpenTab() {
        XCTAssertEqual(AgentEditBufferPlan.action(hasOpenTab: true, isDirty: false), .reload,
                       "开着且没改动 ⇒ 立刻把新正文推进缓冲区（用户眨眼就看见）")
        XCTAssertEqual(AgentEditBufferPlan.action(hasOpenTab: true, isDirty: true), .leaveBuffer,
                       "有未保存改动 ⇒ 缓冲区不动（盖上去就是悄悄丢用户输入）")
        XCTAssertEqual(AgentEditBufferPlan.action(hasOpenTab: false, isDirty: false), .leaveBuffer,
                       "没开着的文件没有缓冲区可同步")
    }

    // MARK: - 卡片状态：已应用 → 已撤销

    func testCardMovesFromAppliedToUndoneAndOnlyFromApplied() {
        var state = AgentChatState()
        state.setEndpoint(.ready(model: "m", endpoint: "http://127.0.0.1:11434/v1"))
        // 缺省授权粒度 = 逐次批 ⇒ 这张卡一定落在「等审批」。
        let cardID = state.requestApproval(name: "write_file", fingerprint: "fp-1",
                                           preview: "a.txt\n+新")
        XCTAssertFalse(state.canUndo(cardID: cardID), "还在等审批 ⇒ 没有可撤的东西")
        XCTAssertFalse(state.markUndone(cardID: cardID), "等审批的卡片不许转已撤销")

        XCTAssertTrue(state.approve(cardID: cardID))
        XCTAssertFalse(state.canUndo(cardID: cardID), "批了还没应用 ⇒ 文件没被改过")

        XCTAssertTrue(state.markApplied(cardID: cardID))
        XCTAssertTrue(state.canUndo(cardID: cardID))
        XCTAssertTrue(state.markUndone(cardID: cardID))
        XCTAssertFalse(state.canUndo(cardID: cardID), "撤过就不能再撤")

        let card = state.cards.first { $0.id == cardID }
        XCTAssertEqual(card?.statusCode, "undone")
        XCTAssertTrue(card?.outcome.isTerminal ?? false)
    }
}
