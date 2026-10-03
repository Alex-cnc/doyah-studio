import XCTest
@testable import DoyahCore

// 队列 `L-97` **第三片**（**删除处置落库半**）的机械证据。
//
// 这一片落的四件东西：① `ContainerRemovalPlan` 带上「被删的是架还是笔记本」
// （`removedContainerKind` —— 少了这一格，落库那一步只能靠猜 uid，猜错一次就是「删了架却把里面的
// 笔记本整批带走」）；② `NoteDatabase.applyRemovalPlan(_:)` 把计划**在一个事务里**写进库；
// ③ `NoteLibrary.removeNotebook / removeShelf` 门面（计划在同一次调用里重算再落库）；
// ④ 删架 `moveToDefault` 档的计划如实记下「哪些笔记本会被改挂」（确认框那句「将影响多少笔记本」）。
//
// 三条纪律：
//   ① **都跑真库文件**（临时目录，不用 `:memory:`）—— 级联删除、多连接、事务在内存库里不是同一回事；
//   ② **删了要真查孤儿行**（`note_tag` / `note_timeline`）：外键级联不是声明了就生效，
//      SQLite 默认**不**开外键（`configure` 里那句 `foreign_keys = ON` 才是前提）；
//   ③ **改挂之后要按归属列复核** —— 「没有无归属笔记」是可量的事实（`unassignedNoteCount`），
//      不是「我以为回填过了」。
final class NotebookRemovalTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_100_000)

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-notebook-removal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    // MARK: - 夹具

    private func url(_ name: String = NoteDatabase.fileName) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    private func makeDatabase() throws -> NoteDatabase {
        try NoteDatabase(path: url().path)
    }

    private func library() -> NoteLibrary {
        NoteLibrary(databaseURL: url())
    }

    private func note(title: String, tags: [String] = [], updatedAt: Date? = nil) -> Note {
        Note(
            id: UUID(),
            title: title,
            body: "正文",
            tags: tags,
            source: NoteSource(
                kind: .manual,
                connectionName: "连接甲",
                fingerprint: "fp-\(title)",
                capturedAt: t0
            ),
            createdAt: t0,
            updatedAt: updatedAt ?? t0,
            containsRowData: false
        )
    }

    /// 起一个库 + 默认两层（所有用例的共同起点）。
    private func seeded() throws -> (NoteDatabase, NotebookDirectory) {
        let database = try makeDatabase()
        let directory = try database.ensureDefaultContainers(
            shelfName: "默认架",
            notebookName: "默认笔记本",
            now: t0
        )
        return (database, directory)
    }

    // MARK: - 1) 删笔记本 · 默认档（里面的笔记移到默认笔记本）

    func testRemovingANotebookMovesItsNotesIntoTheDefaultNotebook() throws {
        let (database, bootstrap) = try seeded()
        let temporary = Notebook(shelfUid: bootstrap.defaultShelf!.uid, name: "临时", sortOrder: 1, createdAt: t0)
        try database.upsert(temporary)
        let kept = note(title: "留下")
        let carried = note(title: "跟着走", updatedAt: t1)
        try database.upsert(kept)
        try database.upsert(carried)
        try database.move(noteIDs: [carried.id], toNotebook: temporary.uid)

        let plan = try XCTUnwrap(database.removalPlan(forNotebook: temporary.uid))
        XCTAssertEqual(plan.policy, .moveToDefault, "默认档 = 移到默认笔记本")
        XCTAssertEqual(plan.removedContainerKind, .notebook, "落库那一步要知道被删的是笔记本")
        XCTAssertEqual(plan.targetContainerUid, bootstrap.defaultNotebook!.uid)
        XCTAssertEqual(plan.movedNoteIDs, [carried.id.uuidString])
        XCTAssertEqual(plan.deletedNoteIDs, [], "默认档不删笔记")
        XCTAssertEqual(plan.affectedNoteCount, 1)

        try database.applyRemovalPlan(plan)

        XCTAssertFalse(try database.notebooks().contains { $0.uid == temporary.uid }, "笔记本行必须真没了")
        XCTAssertEqual(try database.notebookUid(of: carried.id), bootstrap.defaultNotebook!.uid)
        XCTAssertEqual(try database.notebookUid(of: kept.id), bootstrap.defaultNotebook!.uid, "别人的笔记不受影响")
        XCTAssertEqual(try database.note(id: carried.id)?.updatedAt, t1, "改挂不是内容更新 ⇒ 不刷新 updatedAt")
        XCTAssertEqual(try database.unassignedNoteCount(), 0)
    }

    // MARK: - 2) 删笔记本 · 一并删（连标签 / 时间线一起走）

    func testRemovingANotebookTogetherDeletesItsNotesAndTheirChildRows() throws {
        let (database, bootstrap) = try seeded()
        let doomedBook = Notebook(shelfUid: bootstrap.defaultShelf!.uid, name: "一起删", sortOrder: 1, createdAt: t0)
        try database.upsert(doomedBook)
        let doomed = note(title: "跟着删", tags: ["甲", "乙"])
        let keeper = note(title: "别动", tags: ["丙"])
        try database.upsert(doomed)
        try database.upsert(keeper)
        try database.move(noteIDs: [doomed.id], toNotebook: doomedBook.uid)
        try database.recordTimeline(NoteTimelineEntry(at: t1, kind: "note", detail: "手工留的一条"), for: doomed.id)

        let plan = try XCTUnwrap(database.removalPlan(forNotebook: doomedBook.uid, policy: .deleteTogether))
        XCTAssertEqual(plan.deletedNoteIDs, [doomed.id.uuidString])
        XCTAssertEqual(plan.movedNoteIDs, [])
        XCTAssertEqual(plan.targetContainerUid, nil, "一并删时没有落点")

        try database.applyRemovalPlan(plan)

        XCTAssertNil(try database.note(id: doomed.id))
        XCTAssertNotNil(try database.note(id: keeper.id), "另一个笔记本里的笔记一个字都不许动")
        let raw = try SQLiteConnection(path: url().path)
        XCTAssertEqual(try raw.scalarInt("SELECT count(*) FROM note_tag"), 1, "只剩 keeper 的那一个标签")
        XCTAssertEqual(
            try raw.scalarInt("SELECT count(*) FROM note_tag WHERE note_id NOT IN (SELECT id FROM note)"),
            0,
            "孤儿标签行 = 外键没开"
        )
        XCTAssertEqual(
            try raw.scalarInt("SELECT count(*) FROM note_timeline WHERE note_id NOT IN (SELECT id FROM note)"),
            0,
            "孤儿时间线行同上"
        )
        XCTAssertEqual(try database.unassignedNoteCount(), 0)
    }

    // MARK: - 3) 删架 · 默认档（整架的笔记本改挂默认架，笔记一条都不动）

    func testRemovingAShelfMovesItsNotebooksToTheDefaultShelfWithoutMovingNotes() throws {
        let (database, bootstrap) = try seeded()
        let defaultShelfUid = bootstrap.defaultShelf!.uid
        let oldShelf = Shelf(name: "旧架", sortOrder: 1, createdAt: t0)
        try database.upsert(oldShelf)
        let second = Notebook(shelfUid: oldShelf.uid, name: "二", sortOrder: 0, createdAt: t0)
        let third = Notebook(shelfUid: oldShelf.uid, name: "三", sortOrder: 1, createdAt: t0)
        try database.upsert(second)
        try database.upsert(third)
        let carried = note(title: "在旧架里")
        try database.upsert(carried)
        try database.move(noteIDs: [carried.id], toNotebook: second.uid)

        let plan = try XCTUnwrap(database.removalPlan(forShelf: oldShelf.uid))
        XCTAssertEqual(plan.removedContainerKind, .shelf)
        XCTAssertEqual(plan.targetContainerUid, defaultShelfUid)
        XCTAssertEqual(plan.movedNotebookUids.sorted(), [second.uid, third.uid].sorted(), "整架搬的是笔记本")
        XCTAssertEqual(plan.affectedNotebookCount, 2, "确认框要写的「将影响多少笔记本」")
        XCTAssertEqual(plan.movedNoteIDs, [], "笔记跟着自己的笔记本，一条都不改挂")
        XCTAssertEqual(plan.deletedNoteIDs, [])

        try database.applyRemovalPlan(plan)

        let rehomed = Dictionary(uniqueKeysWithValues: try database.notebooks().map { ($0.uid, $0) })
        XCTAssertNil(rehomed[oldShelf.uid], "被删的架不该还留着")
        XCTAssertEqual(try XCTUnwrap(rehomed[second.uid]).shelfUid, defaultShelfUid)
        XCTAssertEqual(try XCTUnwrap(rehomed[third.uid]).shelfUid, defaultShelfUid)
        XCTAssertEqual(
            [try XCTUnwrap(rehomed[second.uid]).sortOrder, try XCTUnwrap(rehomed[third.uid]).sortOrder],
            [1, 2],
            "接在默认架现有条数（默认笔记本 = 0）之后，不重号"
        )
        XCTAssertFalse(try database.shelves().contains { $0.uid == oldShelf.uid })
        XCTAssertEqual(try database.notebookUid(of: carried.id), second.uid, "笔记的归属列一个字节没变")
        XCTAssertEqual(try database.unassignedNoteCount(), 0)
    }

    // MARK: - 4) 删架 · 一并删（默认笔记本不可删 ⇒ 改挂默认架，它里面的笔记不跟着删）

    func testRemovingAShelfTogetherKeepsTheDefaultNotebookAndItsNotes() throws {
        let (database, _) = try seeded()
        let defaultShelfUid = try XCTUnwrap(database.notebookDirectory().defaultShelf).uid
        let oldShelf = Shelf(name: "旧架", sortOrder: 1, createdAt: t0)
        try database.upsert(oldShelf)
        // 把**默认笔记本**摆进被删的架 —— 只有这个摆法才能真的考到「默认容器不可删」那条。
        var defaultNotebook = try XCTUnwrap(database.notebookDirectory().defaultNotebook)
        defaultNotebook.shelfUid = oldShelf.uid
        try database.upsert(defaultNotebook)

        let doomedBook = Notebook(shelfUid: oldShelf.uid, name: "一起删", sortOrder: 1, createdAt: t0)
        try database.upsert(doomedBook)
        let doomedNote = note(title: "跟着删")
        let survivingNote = note(title: "默认笔记本里的")
        try database.upsert(doomedNote)
        try database.upsert(survivingNote)
        try database.move(noteIDs: [doomedNote.id], toNotebook: doomedBook.uid)

        let plan = try XCTUnwrap(database.removalPlan(forShelf: oldShelf.uid, policy: .deleteTogether))
        XCTAssertEqual(plan.removedNotebookUids, [doomedBook.uid])
        XCTAssertEqual(plan.movedNotebookUids, [defaultNotebook.uid], "默认笔记本不可删 ⇒ 改挂默认架")
        XCTAssertEqual(plan.deletedNoteIDs, [doomedNote.id.uuidString], "默认笔记本里的笔记不跟着删")

        try database.applyRemovalPlan(plan)

        XCTAssertNil(try database.note(id: doomedNote.id))
        XCTAssertNotNil(try database.note(id: survivingNote.id), "不可删的那一边，笔记也一件不少")
        let keptNotebook = try XCTUnwrap(try database.notebooks().first { $0.uid == defaultNotebook.uid })
        XCTAssertEqual(keptNotebook.shelfUid, defaultShelfUid, "改挂必须排在删架之前，否则被外键级联一起带走")
        XCTAssertFalse(try database.shelves().contains { $0.uid == oldShelf.uid })
        XCTAssertEqual(try database.unassignedNoteCount(), 0)
    }

    // MARK: - 5) 默认容器删不掉（计划为 nil，库一个字节不动）

    func testTheDefaultContainersCannotBeRemovedAndTheLibraryIsUntouched() throws {
        let (database, bootstrap) = try seeded()
        try database.upsert(note(title: "一条"))

        let before = try database.notebookDirectory()
        XCTAssertNil(try database.removalPlan(forNotebook: bootstrap.defaultNotebook!.uid, policy: .deleteTogether))
        XCTAssertNil(try database.removalPlan(forShelf: bootstrap.defaultShelf!.uid, policy: .deleteTogether))
        XCTAssertNil(try database.removalPlan(forNotebook: "nb-没有这条", policy: .deleteTogether))
        XCTAssertNil(try database.removalPlan(forShelf: "sh-没有这条", policy: .deleteTogether))

        XCTAssertEqual(try database.notebookDirectory(), before, "认不出的容器 ⇒ 计划 nil，库不动")
        XCTAssertEqual(try database.noteCount(), 1)
    }

    // MARK: - 6) 门面（界面走的那一层）：计划重算 + 落库 + 第二次拒绝

    func testTheLibraryFacadeRecomputesThePlanAppliesItAndRefusesASecondTime() async throws {
        let library = library()
        _ = try await library.ensureOwnership(shelfName: "默认架", notebookName: "默认笔记本", now: t0)
        // 注意：`XCTAssert*` 的实参是**同步 autoclosure**，`await` 进不去 —— 先把库里的值取出来，
        // 再在断言里比（写成 `XCTAssertEqual(try await …)` 会报「actor-isolated call in a synchronous context」）。
        let opened = try await library.notebookDirectory()
        let shelfUid = try XCTUnwrap(opened.defaultShelf).uid
        let temporary = Notebook(shelfUid: shelfUid, name: "临时", sortOrder: 1, createdAt: t0)
        try makeDatabase().upsert(temporary)
        let written = try await library.upsert(
            NoteDraft(
                title: "一",
                body: "正文",
                tags: [],
                source: NoteSource(kind: .manual, connectionName: "连接甲", fingerprint: "fp-1")
            ),
            now: t0
        )
        try await library.move(noteIDs: [written.id], toNotebook: temporary.uid)

        let plan = try await library.removalPlan(forNotebook: temporary.uid)
        XCTAssertEqual(plan?.movedNoteIDs, [written.id.uuidString], "确认框上的数字 = 库里的账")

        let applied = try await library.removeNotebook(uid: temporary.uid)
        XCTAssertEqual(applied?.removedContainerUid, temporary.uid)

        let after = try await library.notebookDirectory()
        let placements = try await library.placements()
        let loaded = try await library.load()
        let again = try await library.removeNotebook(uid: temporary.uid)
        let defaultNotebookUid = try XCTUnwrap(after.defaultNotebook).uid
        let asDefault = try await library.removeNotebook(uid: defaultNotebookUid)

        XCTAssertFalse(after.notebooks.contains { $0.uid == temporary.uid })
        XCTAssertEqual(
            placements.first { $0.noteID == written.id.uuidString }?.notebookUid,
            after.defaultNotebook?.uid
        )
        XCTAssertEqual(loaded.count, 1, "默认档不删笔记")
        XCTAssertNil(again, "第二次 = 认不出的容器 ⇒ nil，库不再变")
        XCTAssertNil(asDefault, "默认笔记本删不掉")
    }
}
