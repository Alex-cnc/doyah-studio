import XCTest
@testable import DoyahCore

// **回收站 / 归档 / 一步撤销**的机械判据（`FR-NTS-NOTE-TRASH-001` ①②③ · `FR-NTS-NOTE-ORG-001` ②③）。
//
// 由头（2026-11-02 核要点读数）：这三条的实现列当时都写着「在盘」，判据列却是 🟡 —— 逐点对下来
// **要点根本不在盘上**：没有恢复路（没有 `deleted_at = NULL` 回写、没有回收站视图）、没有「彻底清除」
// 这一步（因而也没有清除前提示与上限）、没有归档、批量删除没有撤销栈。本文件的用例把这三片钉住。
//
// 三条口径（与仓里其它存储判据同源）：
//   ① 都跑**真库文件**（临时目录），不用 `:memory:` —— 墓碑列、`note_trash` 快照、FTS 外部内容表、
//      WAL 都是「只有落到真文件才成立」的东西；
//   ② **成对**：改前（物理删 / 没有恢复路）与改后（墓碑 + 快照 + 恢复）各有一条断言；
//   ③ **负例不许缺席**：已彻底清除的条目恢复不了、归档不进默认视图但能被搜到 —— 这两条正是
//      「功能在但不生效」最常见的两种假绿形状。
//
// 写法纪律：`NoteLibrary` 是 actor ⇒ 每个 `await` 的结果先落局部量再进 `XCTAssert`
// （`XCTAssert` 的 autoclosure 不收并发）。
final class NoteTrashTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-note-trash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    // MARK: - 夹具

    private var url: URL { directory.appendingPathComponent(NoteLibrary.fileName, isDirectory: false) }

    private func library() -> NoteLibrary { NoteLibrary(databaseURL: url) }

    private func draft(title: String, body: String = "正文", tags: [String] = []) -> NoteDraft {
        NoteDraft(title: title, body: body, tags: tags)
    }

    private func rawCount(_ sql: String) throws -> Int64 {
        let connection = try SQLiteConnection(path: url.path)
        defer { try? connection.close() }
        return try connection.scalarInt(sql) ?? -1
    }

    private func notebookUid(of id: UUID, in store: NoteLibrary) async throws -> String? {
        let placements = try await store.placements()
        return placements.first { $0.noteID == id.uuidString }?.notebookUid
    }

    private let at = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - ① 删除后可恢复（契约 §15.9 第 1 条）

    func testDeletingHidesTheNoteButLeavesARecoverableTrashEntry() async throws {
        let store = library()
        _ = try await store.ensureOwnership(shelfName: "架", notebookName: "默认笔记本")
        let note = try await store.upsert(draft(title: "要删的", tags: ["骑行", "计划"]))

        try await store.delete(id: note.id, at: at)

        let visible = try await store.load()
        XCTAssertTrue(visible.isEmpty, "删掉之后默认列表里不该还有它")
        let entries = try await store.trashedEntries()
        XCTAssertEqual(entries.count, 1, "回收站里要有这一条")
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.noteID, note.id)
        XCTAssertEqual(entry.tags.sorted(), ["计划", "骑行"].sorted(), "标签要进快照，否则恢复出来是裸笔记")
        XCTAssertNotNil(entry.notebookUid, "原归属要进快照（恢复回原位）")
        XCTAssertTrue(entry.isRecoverable)
        let daysLeft = entry.daysLeft(policy: .default, now: at)
        XCTAssertEqual(daysLeft, 30, "刚删的还剩整个保留期")
    }

    func testRestoringBringsBackTagsAttachmentAndTheOriginalNotebook() async throws {
        let store = library()
        let container = try await store.ensureOwnership(shelfName: "架", notebookName: "默认笔记本")
        let defaultShelfUid = try XCTUnwrap(container.defaultShelf).uid
        let createdSecond = try await store.createNotebook(inShelf: defaultShelfUid, name: "第二个")
        let second = try XCTUnwrap(createdSecond)
        let note = try await store.upsert(draft(title: "恢复我", tags: ["甲"]))
        _ = try await store.move(noteIDs: [note.id], toNotebook: second.uid)
        let source = directory.appendingPathComponent("附件.txt")
        try "附件正文".write(to: source, atomically: true, encoding: .utf8)
        let attachment = try await store.attach(fileAt: source, to: note.id, now: at)

        try await store.delete(id: note.id, at: at.addingTimeInterval(60))
        let restoredOutcome = try await store.restoreFromTrash(id: note.id, at: at.addingTimeInterval(120))
        let outcome = try XCTUnwrap(restoredOutcome)

        XCTAssertEqual(outcome.placement, .original(uid: second.uid), "原笔记本还在 ⇒ 回原位")
        XCTAssertFalse(outcome.movedToDefault)
        let loaded = try await store.load()
        let restored = try XCTUnwrap(loaded.first { $0.id == note.id })
        XCTAssertEqual(restored.tags, ["甲"], "标签要按快照放回")
        let placement = try await notebookUid(of: note.id, in: store)
        XCTAssertEqual(placement, second.uid, "归属要回原处")
        let attachments = try await store.attachments(of: note.id)
        XCTAssertEqual(attachments.map(\.id), [attachment.id], "附件索引要按快照放回（文件本来就没被动）")
        let remaining = try await store.trashedEntries()
        XCTAssertTrue(remaining.isEmpty, "恢复之后它不再在回收站里")
        // **恢复也要能被搜到**：删除时把 FTS 摘了，恢复不摘回来 = 「恢复了但搜不到」。
        let hits = try await store.search("恢复我")
        XCTAssertTrue(hits.notes.contains { $0.id == note.id }, "恢复后必须重新入检索索引")
    }

    func testRestoringFallsBackToTheDefaultNotebookAndSaysSoWhenTheOriginalIsGone() async throws {
        let store = library()
        let container = try await store.ensureOwnership(shelfName: "架", notebookName: "默认笔记本")
        let defaultNotebookUid = try XCTUnwrap(container.defaultNotebook).uid
        let defaultShelfUid = try XCTUnwrap(container.defaultShelf).uid
        let createdExtra = try await store.createNotebook(inShelf: defaultShelfUid, name: "临时")
        let extra = try XCTUnwrap(createdExtra)
        let note = try await store.upsert(draft(title: "家在没了的地方"))
        _ = try await store.move(noteIDs: [note.id], toNotebook: extra.uid)
        try await store.delete(id: note.id, at: at)
        // 删掉它原来的笔记本（默认档 = 里面的笔记移到默认笔记本；这条已经是墓碑，不带它走）
        _ = try await store.removeNotebook(uid: extra.uid, at: at.addingTimeInterval(30))

        let fallbackOutcome = try await store.restoreFromTrash(id: note.id, at: at.addingTimeInterval(60))
        let outcome = try XCTUnwrap(fallbackOutcome)

        XCTAssertTrue(outcome.movedToDefault, "原归属没了 ⇒ 落默认笔记本，并且要能说出这件事")
        XCTAssertEqual(outcome.placement, .fallbackToDefault(original: extra.uid))
        let placement = try await notebookUid(of: note.id, in: store)
        XCTAssertEqual(placement, defaultNotebookUid, "不许留下无归属条目")
    }

    // MARK: - ② 彻底清除前有明确提示（契约 §15.9 第 2 条）

    func testPurgingClearsTheContentButKeepsATombstoneAndAReceipt() async throws {
        let store = library()
        let note = try await store.upsert(draft(title: "彻底清掉", body: "不该留下的正文", tags: ["甲"]))
        try await store.delete(id: note.id, at: at)

        let changed = try await store.purgeFromTrash(id: note.id, at: at.addingTimeInterval(10))
        XCTAssertGreaterThan(changed, 0)

        // 内容清空、墓碑还在（删除了这件事仍要跨端传播 —— 顺手删行会让另一端的副本把它拉回来）。
        let uuid = note.id.uuidString
        let rows = try rawCount("SELECT count(*) FROM note WHERE uuid = '\(uuid)'")
        let emptyRows = try rawCount(
            "SELECT count(*) FROM note WHERE uuid = '\(uuid)' AND title = '' AND body = ''"
        )
        XCTAssertEqual(rows, 1, "行要留着（墓碑）")
        XCTAssertEqual(emptyRows, 1, "内容要真清掉")
        let entries = try await store.trashedEntries()
        let receipt = try XCTUnwrap(entries.first { $0.noteID == note.id })
        XCTAssertNotNil(receipt.purgedAt, "留一张收据：清除之后还要能说出清了哪些")
        XCTAssertEqual(receipt.title, "彻底清掉", "收据上不能只剩一个 uuid")
        XCTAssertFalse(receipt.isRecoverable)
        // 已彻底清除 ⇒ 恢复不成立（内容没了，恢复只能造出一条空笔记）。
        let outcome = try await store.restoreFromTrash(id: note.id, at: at.addingTimeInterval(20))
        XCTAssertNil(outcome, "已清除的条目必须恢复不了")
        let deletedAt = try await store.deletedAt(id: note.id)
        XCTAssertNotNil(deletedAt, "自检：它仍是墓碑（行还在）")
    }

    func testPurgePromptCountsNotesAndAttachmentsBeforeAnythingHappens() {
        let entry = NoteTrashEntry(
            noteID: UUID(),
            title: "带附件",
            attachments: [
                NoteTrashAttachment(id: UUID(), path: "/tmp/a", addedAt: Date(timeIntervalSince1970: 0)),
                NoteTrashAttachment(id: UUID(), path: "/tmp/b", addedAt: Date(timeIntervalSince1970: 0))
            ],
            deletedAt: Date(timeIntervalSince1970: 0)
        )
        let prompt = NoteTrash.purgePrompt(entries: [entry])
        XCTAssertEqual(prompt.noteCount, 1)
        XCTAssertEqual(prompt.attachmentCount, 2, "「附件一并处理」这句要带得上数")
        XCTAssertTrue(prompt.irreversible, "彻底清除必须写明不可恢复")
    }

    // MARK: - ③ 回收站有上限且可见（契约 §15.9 第 3 条）

    func testRetentionAndCapacityAreVisibleAndProduceThePurgeQueue() {
        // 容量 1：三格里 3 天前那条到期，剩下两条只有一条能留 ⇒ 另外那条超容量。
        // （写成容量 2 的话「到期那条清掉之后刚好装得下」，超容量一栏永远是空的 —— 那样这条判据
        //  就没有反例，是一句好听话。）
        let policy = NoteTrashPolicy(retentionDays: 2, capacity: 1)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        func entry(_ daysAgo: Int) -> NoteTrashEntry {
            NoteTrashEntry(noteID: UUID(), title: "x", deletedAt: base.addingTimeInterval(-Double(daysAgo) * 86_400))
        }
        let expired = entry(3)
        let oldest = entry(1)
        let middle = entry(0)
        let summary = NoteTrashSummary.make(entries: [expired, oldest, middle], policy: policy, now: base)

        XCTAssertEqual(summary.expiredIDs, [expired.noteID], "超过保留期 ⇒ 到期该清")
        XCTAssertEqual(summary.overflowIDs, [oldest.noteID], "容量 1 ⇒ 更旧的那一条超容量")
        XCTAssertEqual(summary.purgeQueueIDs, [expired.noteID, oldest.noteID], "到期 + 超容量按删除时间正序")
        XCTAssertEqual(summary.items.count, 3, "读数本身不清东西：清不清由调用方决定")
        // 上限**可见**（界面那一行直接用这三个数，不自己算）。
        XCTAssertEqual(summary.limits.used, 3)
        XCTAssertEqual(summary.limits.capacity, 1)
        XCTAssertEqual(summary.limits.retentionDays, 2)
        XCTAssertEqual(summary.limits.nextPurgeCount, 2)
        XCTAssertTrue(summary.nearLimit, "3 条 / 容量 2 ⇒ 早已超过 80% 门槛")

        // 负例：没过期也没超容量的那几条**一条都不许进清除队列**（做成「一打开就清光」是最坏的假实现）。
        let calm = NoteTrashSummary.make(entries: [middle], policy: policy, now: base)
        XCTAssertTrue(calm.purgeQueueIDs.isEmpty, "没到期、也没超容量 ⇒ 一条都不清")
        let roomy = NoteTrashSummary.make(entries: [middle], policy: NoteTrashPolicy(retentionDays: 30, capacity: 10), now: base)
        XCTAssertFalse(roomy.nearLimit, "1 / 10 条不该提示接近上限")
        XCTAssertTrue(roomy.purgeQueueIDs.isEmpty)
    }

    // MARK: - ②③ 归档（`FR-NTS-NOTE-ORG-001`）

    func testArchivingKeepsTheNoteSearchableButOutOfTheDefaultViews() async throws {
        let store = library()
        let archived = try await store.upsert(draft(title: "归档的", tags: ["旧"]))
        let live = try await store.upsert(draft(title: "活着的", tags: ["旧"]))
        _ = try await store.ensureOwnership(shelfName: "架", notebookName: "默认笔记本")

        let changed = try await store.setArchived(id: archived.id, true)
        XCTAssertGreaterThan(changed, 0)

        let notes = try await store.load()
        let container = try await store.notebookDirectory()
        let placements = try await store.placements()
        let navigation = NotesNavigation(directory: container, placements: placements)
        let archivedNote = try XCTUnwrap(notes.first { $0.id == archived.id })
        XCTAssertTrue(archivedNote.isArchived)
        let allRows = navigation.filter(notes, scope: .all)
        XCTAssertFalse(allRows.contains { $0.id == archived.id }, "归档 = 移出默认视图（全部笔记里不该再出现）")
        let archivedRows = navigation.filter(notes, scope: .archived)
        XCTAssertEqual(archivedRows.map(\.id), [archived.id], "「归档」那一栏只列归档的")
        let tagRows = navigation.filter(notes, scope: .tag("旧"))
        XCTAssertTrue(tagRows.contains { $0.id == live.id }, "别人的笔记不受影响")
        XCTAssertFalse(tagRows.contains { $0.id == archived.id })
        // **仍可被检索**（契约 §15.5：归档仍可被检索到；且不是删除 ⇒ 不占回收站）。
        let hits = try await store.search("归档的")
        XCTAssertTrue(hits.notes.contains { $0.id == archived.id }, "归档不等于删除：检索必须还能找到它")
        let trash = try await store.trashedEntries()
        XCTAssertTrue(trash.isEmpty, "归档不占回收站")

        // 取回：从「归档」那一栏原样回来。
        _ = try await store.setArchived(id: archived.id, false)
        let reloaded = try await store.load()
        let recovered = try XCTUnwrap(reloaded.first { $0.id == archived.id })
        XCTAssertFalse(recovered.isArchived)
        XCTAssertEqual(recovered.tags, ["旧"], "取回不许丢标签")
    }

    func testArchivingDoesNotRefreshUpdatedAtOrCreateAVersion() async throws {
        let store = library()
        let note = try await store.upsert(draft(title: "整理不刷新"))
        let before = try await store.load()
        let updatedBefore = try XCTUnwrap(before.first { $0.id == note.id }).updatedAt
        let versionsBefore = try await store.versionCount(of: note.id)

        _ = try await store.setArchived(id: note.id, true)

        let after = try await store.load()
        let updatedAfter = try XCTUnwrap(after.first { $0.id == note.id }).updatedAt
        let versionsAfter = try await store.versionCount(of: note.id)
        XCTAssertEqual(updatedAfter, updatedBefore, "整理是组织行为 ⇒ 不刷新内容更新时间（契约 §15.5 第 1 条）")
        XCTAssertEqual(versionsAfter, versionsBefore, "整理不产生内容版本")
    }

    // MARK: - ② 操作可撤销（契约 §15.5「一步可撤销」）

    func testABatchOfDeletesCanBeUndoneAsOneStepThroughTheTrash() async throws {
        let store = library()
        let first = try await store.upsert(draft(title: "一", tags: ["a"]))
        let second = try await store.upsert(draft(title: "二", tags: ["b"]))
        let third = try await store.upsert(draft(title: "三", tags: ["c"]))
        let notes = [first, second, third]
        let undo = NoteOrganizeUndo(kind: .delete, noteIDs: notes.map(\.id))
        XCTAssertEqual(undo.noteIDs.count, 3, "一次批量 = 一步（快照记的是整批）")

        for note in notes { try await store.delete(id: note.id, at: at) }
        let hidden = try await store.load()
        XCTAssertTrue(hidden.isEmpty)
        let trashed = try await store.trashedEntries()
        XCTAssertEqual(trashed.count, 3)

        // 撤销 = 按快照整批恢复（不是「再执行一次反向操作」）。
        for id in undo.noteIDs {
            let outcome = try await store.restoreFromTrash(id: id, at: at.addingTimeInterval(60))
            XCTAssertNotNil(outcome)
        }
        let restored = try await store.load()
        XCTAssertEqual(Set(restored.map(\.id)), Set(notes.map(\.id)), "整批回来")
        XCTAssertEqual(restored.first { $0.title == "二" }?.tags, ["b"], "标签逐条复原")
        let leftInTrash = try await store.trashedEntries()
        XCTAssertTrue(leftInTrash.isEmpty)
    }

    /// 负例：**只撤销其中一条**也是它自己那一条回来，不会把别的顺手带回来（撤销不是「全量重放」）。
    func testUndoingOneOfABatchRestoresOnlyThatOne() async throws {
        let store = library()
        let first = try await store.upsert(draft(title: "留着的"))
        let second = try await store.upsert(draft(title: "撤销的"))
        try await store.delete(id: first.id, at: at)
        try await store.delete(id: second.id, at: at)

        let outcome = try await store.restoreFromTrash(id: second.id, at: at.addingTimeInterval(1))
        XCTAssertNotNil(outcome)

        let visible = try await store.load()
        XCTAssertEqual(visible.map(\.id), [second.id])
        let left = try await store.trashedEntries()
        XCTAssertEqual(left.map(\.noteID), [first.id])
    }
}
