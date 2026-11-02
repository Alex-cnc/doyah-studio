import XCTest
@testable import DoyahCore

/// `FR-NTS-TODO-LINK-001`（任务 ↔ 笔记双向转化 · 概设 §15.14）的机械证据。
///
/// 五条判据各至少一条用例，**都跑真库文件**（临时目录）而不是 `:memory:`：
/// 「链接活过对象被删」「快照不跟着对方变」这两件事只有真库 + 真删才测得到。
///
/// 三条纪律（与 `TodoStorageTests` 同族）：
///   ① 判据读**库里的那一份事实**（写完读回），不读内存里刚构造的值；
///   ② 「原对象没被改写」按**逐字段相等**断言，不按「看起来还在」；
///   ③ 视图层不在这里测 —— 界面落点是 `notes-task-links` / `todo-detail-links` 两个
///      `accessibilityIdentifier`（由 `TestsUISnapshot` 取证），本文件只钉 Core + 存储。
final class TodoNoteLinkTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-todo-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func url(_ name: String = NoteDatabase.fileName) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    private func makeDatabase() throws -> NoteDatabase {
        try NoteDatabase(path: url().path)
    }

    private func makeLibrary() -> NoteLibrary {
        NoteLibrary(databaseURL: url())
    }

    private let moment = Date(timeIntervalSince1970: 1_700_000_000)

    private func sampleNote(title: String = "会话纪要", body: String = "第一行\n第二行") -> Note {
        Note(
            title: title,
            body: body,
            tags: ["工作"],
            createdAt: moment,
            updatedAt: moment
        )
    }

    // MARK: - 判据①：转化是新建，不是改类型

    /// 笔记 ⇒ 任务：新对象是**另一条**（不同 id），原笔记逐字段不变。
    func testCreatingATodoFromANoteLeavesTheNoteByteForByteUntouched() throws {
        let database = try makeDatabase()
        let note = sampleNote()
        _ = try database.upsert(note)
        let before = try XCTUnwrap(database.notes().first { $0.id == note.id })

        let todo = TodoLinkFactory.todo(from: note, fallbackTitle: "未命名", at: moment)
        XCTAssertNotEqual(todo.id, note.id, "转化产出的必须是新对象")
        _ = try database.upsert(todo)
        _ = try database.upsert(TodoLinkFactory.link(note: note, todo: todo, origin: .fromNote, at: moment))

        let after = try XCTUnwrap(database.notes().first { $0.id == note.id })
        XCTAssertEqual(after, before, "原笔记一个字段都不许被这次转化改写（类型也是笔记）")
        XCTAssertEqual(try database.todoCount(), 1)
    }

    /// 任务 ⇒ 笔记：原任务逐字段不变，新笔记的正文 = 任务备注（原样）。
    func testCreatingANoteFromATodoLeavesTheTodoUntouched() throws {
        let database = try makeDatabase()
        let todo = Todo(
            title: "交周报",
            tags: ["工作"],
            note: "带上上周的读数",
            createdAt: moment,
            updatedAt: moment
        )
        _ = try database.upsert(todo)
        let before = try XCTUnwrap(database.todo(id: todo.id))

        let note = TodoLinkFactory.note(from: todo, fallbackTitle: "未命名", at: moment)
        _ = try database.upsert(note)
        _ = try database.upsert(TodoLinkFactory.link(note: note, todo: todo, origin: .fromTodo, at: moment))

        XCTAssertEqual(try XCTUnwrap(database.todo(id: todo.id)), before)
        let savedNote = try XCTUnwrap(database.notes().first { $0.id == note.id })
        XCTAssertEqual(savedNote.title, "交周报")
        XCTAssertEqual(savedNote.body, "带上上周的读数")
        XCTAssertEqual(savedNote.source.kind, .manual)
    }

    // MARK: - 判据②：双向可见可跳转

    func testBothSidesSeeTheLinkAndPointAtEachOther() throws {
        let database = try makeDatabase()
        let note = sampleNote()
        let todo = TodoLinkFactory.todo(from: note, fallbackTitle: "未命名", at: moment)
        _ = try database.upsert(note)
        _ = try database.upsert(todo)
        let link = TodoLinkFactory.link(note: note, todo: todo, origin: .fromNote, at: moment)
        _ = try database.upsert(link)

        // 笔记侧：已生成任务，跳转目标是那条任务
        let fromNote = try XCTUnwrap(database.links(noteID: note.id).first)
        let noteReading = TodoLinkFactory.reading(of: fromNote, viewer: .note, counterpartExists: true)
        XCTAssertEqual(noteReading.originKey, .todoLinkGeneratedTodo)
        XCTAssertEqual(noteReading.counterpart, .todo)
        XCTAssertEqual(noteReading.counterpartID, todo.id)

        // 任务侧：来自笔记，跳转目标是那条笔记
        let fromTodo = try XCTUnwrap(database.links(todoID: todo.id).first)
        let todoReading = TodoLinkFactory.reading(of: fromTodo, viewer: .todo, counterpartExists: true)
        XCTAssertEqual(todoReading.originKey, .todoLinkFromNote)
        XCTAssertEqual(todoReading.counterpart, .note)
        XCTAssertEqual(todoReading.counterpartID, note.id)
        XCTAssertFalse(todoReading.counterpartMissing)
    }

    /// 反向转化（任务 ⇒ 笔记）的方向词必须翻面 —— 四个组合各有各的话。
    func testOriginWordingCoversBothDirections() {
        XCTAssertEqual(TodoLinkText.originKey(for: .note, origin: .fromTodo), .todoLinkFromTodo)
        XCTAssertEqual(TodoLinkText.originKey(for: .todo, origin: .fromTodo), .todoLinkGeneratedNote)
        XCTAssertEqual(TodoLinkText.originKey(for: .note, origin: .fromNote), .todoLinkGeneratedTodo)
        XCTAssertEqual(TodoLinkText.originKey(for: .todo, origin: .fromNote), .todoLinkFromNote)
    }

    // MARK: - 判据③：链接带快照（对方被改，链接不跟着变）

    func testTheSnapshotDoesNotFollowLaterEditsOfTheCounterpart() throws {
        let database = try makeDatabase()
        var note = sampleNote(title: "原标题", body: "原摘要")
        let todo = TodoLinkFactory.todo(from: note, fallbackTitle: "未命名", at: moment)
        _ = try database.upsert(note)
        _ = try database.upsert(todo)
        _ = try database.upsert(TodoLinkFactory.link(note: note, todo: todo, origin: .fromNote, at: moment))

        // 笔记后来被改名改文（另一条写路，**不碰链接**）
        note.title = "改过的标题"
        note.body = "改过的正文"
        note.updatedAt = moment.addingTimeInterval(60)
        _ = try database.upsert(note)

        let link = try XCTUnwrap(database.links(todoID: todo.id).first)
        XCTAssertEqual(link.snapshotTitle, "原标题", "快照是建立时那一份读数")
        XCTAssertEqual(link.snapshotExcerpt, "原摘要")
        let reading = TodoLinkFactory.reading(of: link, viewer: .todo, counterpartExists: true)
        XCTAssertEqual(reading.counterpartTitle, "原标题")
    }

    // MARK: - 判据④：可撤销

    /// 撤销目标 = **这次生成的那一个**（源头不删）。
    func testUndoTargetIsTheGeneratedObjectNotTheSource() {
        let note = sampleNote()
        let todo = Todo(title: "任务")
        let forward = TodoLinkFactory.link(note: note, todo: todo, origin: .fromNote)
        XCTAssertEqual(TodoLinkFactory.undoTarget(of: forward), .todo(todo.id))
        let backward = TodoLinkFactory.link(note: note, todo: todo, origin: .fromTodo)
        XCTAssertEqual(TodoLinkFactory.undoTarget(of: backward), .note(note.id))
    }

    /// 真撤销（删目标 + 销链接）之后：源头还在、链接没了、两端都不留悬挂引用。
    func testUndoRemovesOnlyTheGeneratedObjectAndTheLink() throws {
        let database = try makeDatabase()
        let note = sampleNote()
        let todo = TodoLinkFactory.todo(from: note, fallbackTitle: "未命名", at: moment)
        _ = try database.upsert(note)
        _ = try database.upsert(todo)
        let link = TodoLinkFactory.link(note: note, todo: todo, origin: .fromNote, at: moment)
        _ = try database.upsert(link)

        // 按 `undoTarget` 删（正是 `AppState.undoConversion` 的顺序）
        guard case .todo(let id) = TodoLinkFactory.undoTarget(of: link) else {
            return XCTFail("笔记 → 任务的撤销目标必须是任务")
        }
        try database.deleteTodo(id: id)
        XCTAssertEqual(try database.deleteLink(id: link.id), 1)

        XCTAssertEqual(try database.todoCount(), 0)
        XCTAssertTrue(try database.links().isEmpty, "链接随撤销一起销账")
        XCTAssertEqual(try database.notes().count, 1, "源头一个都不许少")
        XCTAssertEqual(try database.links(noteID: note.id).count, 0)
    }

    // MARK: - 判据⑤：来源被删要标注（留快照，不跟删）

    func testDeletingTheSourceKeepsTheLinkAndItsSnapshotAndMarksIt() throws {
        let database = try makeDatabase()
        let note = sampleNote(title: "会被删的笔记")
        let todo = TodoLinkFactory.todo(from: note, fallbackTitle: "未命名", at: moment)
        _ = try database.upsert(note)
        _ = try database.upsert(todo)
        _ = try database.upsert(TodoLinkFactory.link(note: note, todo: todo, origin: .fromNote, at: moment))

        _ = try database.delete(id: note.id, at: moment.addingTimeInterval(120))

        // 链接行还在（**没有外键级联**正是为了这一条）
        let link = try XCTUnwrap(database.links(todoID: todo.id).first)
        XCTAssertEqual(link.snapshotTitle, "会被删的笔记")
        // 读的一方现判「对方不在了」⇒ 标来源已删除，而不是断链
        let live = Set(try database.notes().map(\.id))
        let reading = TodoLinkFactory.reading(of: link, viewer: .todo, counterpartExists: live.contains(link.noteID))
        XCTAssertTrue(reading.counterpartMissing)
        XCTAssertFalse(reading.counterpartTitle.isEmpty, "快照仍在 —— 这是判据④能说人话的前提")
    }

    // MARK: - 存储口径

    /// 同一对对象只留一条链接（重复按「生成任务」不堆两行）。
    func testTheSamePairKeepsASingleLink() throws {
        let database = try makeDatabase()
        let note = sampleNote()
        let todo = Todo(title: "任务")
        _ = try database.upsert(note)
        _ = try database.upsert(todo)
        _ = try database.upsert(TodoLinkFactory.link(note: note, todo: todo, origin: .fromNote, at: moment))
        _ = try database.upsert(TodoLinkFactory.link(note: note, todo: todo, origin: .fromTodo, at: moment))
        XCTAssertEqual(try database.links().count, 1)
        XCTAssertEqual(try XCTUnwrap(database.links().first).origin, .fromTodo, "后写的那一次覆盖方向与快照")
    }

    /// 认不出的方向**不许猜**（猜错就是撤销删错对象）。
    func testAnUnknownOriginIsRejectedRatherThanGuessed() throws {
        let database = try makeDatabase()
        XCTAssertEqual(database.userVersion, NoteDatabase.supportedVersion)
        // 用**另一条连接**直接写一行坏方向（不经过 `upsert(_:)` 的归一）——
        // 这条判据要问的正是「读到坏值时读的一方怎么办」。
        let raw = try SQLiteConnection(path: url().path)
        try raw.execute(
            "INSERT INTO todo_note_link (uuid, note_uuid, todo_uuid, origin, snapshot_title, snapshot_excerpt, created_at) "
                + "VALUES (?, ?, ?, 'weekly', 't', '', 0)",
            [.text(UUID().uuidString), .text(UUID().uuidString), .text(UUID().uuidString)]
        )

        XCTAssertThrowsError(try database.links()) { error in
            XCTAssertEqual(error as? NoteStorageFailure, .unknownLinkOrigin("weekly"))
        }
    }

    /// schema 至少到 v13 且**跟着 `supportedVersion` 走**：链接表在、重开幂等。
    ///
    /// 判的是「v13 那张表与它的数据在不在」，**不是**「版本号恰等于 13」——
    /// 版本号会随下一次补列 / 补表往前挪（v14 补了待办的 `repeat_rule`），钉死数字就是给未来埋一条红。
    func testSchemaReachesV13AndKeepsTodoData() throws {
        let database = try makeDatabase()
        XCTAssertEqual(database.userVersion, NoteDatabase.supportedVersion)
        XCTAssertGreaterThanOrEqual(NoteDatabase.supportedVersion, NoteSchemaV13.version)
        XCTAssertTrue(try database.tableNames().contains("todo_note_link"))

        let todo = Todo(title: "老数据")
        _ = try database.upsert(todo)
        let reopened = try makeDatabase()
        XCTAssertEqual(reopened.userVersion, NoteDatabase.supportedVersion, "重开幂等")
        XCTAssertEqual(try reopened.todoCount(), 1, "补表不改既有语义")
    }

    /// 门面也走同一条路（`AppState` 只经 `NoteLibrary`）。
    func testLibraryFacadeRoundTripsLinks() async throws {
        let library = makeLibrary()
        let note = try await library.save(
            NoteDraft(title: "笔记", body: "正文", source: NoteSource(kind: .manual)),
            id: UUID()
        )
        let todo = Todo(title: "任务")
        _ = try await library.upsert(todo)
        _ = try await library.saveLink(TodoLinkFactory.link(note: note, todo: todo, origin: .fromNote))

        let links = try await library.links()
        XCTAssertEqual(links.count, 1)
        let byNote = try await library.links(noteID: note.id)
        let byTodo = try await library.links(todoID: todo.id)
        XCTAssertEqual(byNote.count, 1)
        XCTAssertEqual(byTodo.count, 1)
        let removed = try await library.deleteLink(id: links[0].id)
        XCTAssertEqual(removed, 1)
        let remaining = try await library.links()
        XCTAssertTrue(remaining.isEmpty)
    }
}
