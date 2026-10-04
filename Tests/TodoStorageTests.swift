import XCTest
@testable import DoyahCore

// 队列 `N-11` 的 **macOS 核心层半**（待办任务清单 · 契约 `Todo` 实体）的机械证据。
//
// 这一片落的三件东西：① schema **v5**（`todo` + `todo_tag` 两张表，**与笔记同库同连接** ——
// 「同一次事务」只有同一个连接才做得到，见 `NoteSchemaV5`）；② `NoteDatabase` 的任务写读口
// （upsert / setDone / delete / todos / todoCount）；③ `NoteLibrary` 门面。
//
// 三条纪律：
//   ① **都跑真库文件**（临时目录，不用 `:memory:`）—— v4 → v5 那条升级路只在真文件上走得到；
//   ② **升级路径用手搭的 v4 库**（拿 v1~v4 的 DDL 逐版建出来）：用当前代码建的库永远是最新版，
//      测不到「老库升上来」，而那正是这一片唯一有风险的路径；
//   ③ **写完读回**：判据读的是库里的那一份事实，不是内存里刚构造的那个值。
final class TodoStorageTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-todo-storage-\(UUID().uuidString)", isDirectory: true)
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

    private func moment(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offset)
    }

    private func sampleTodo(
        title: String,
        dueAt: Date? = nil,
        priority: TodoPriority = .normal,
        tags: [String] = [],
        createdAt: Date = Date(timeIntervalSince1970: 1_699_000_000)
    ) -> Todo {
        Todo(
            title: title,
            dueAt: dueAt,
            priority: priority,
            tags: tags,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    /// 手搭一个 **v4 库** —— 存量用户的库长什么样：v1~v4 的 DDL 都在、`user_version = 4`、
    /// 一张 `note` 表里有真数据和真标签（**表有几张就要写几张**：上一次的教训是标签忘了写，
    /// 让「标签搬过来没有」那条判据在 fixture 那一步就已经是假的）。
    private func makeVersionFourDatabase(notes: [Note]) throws {
        let connection = try SQLiteConnection(path: url().path)
        for statement in NoteSchemaV1.ddl { try connection.execute(statement) }
        for statement in NoteSchemaV2.ddl { try connection.execute(statement) }
        for statement in NoteSchemaV3.ddl { try connection.execute(statement) }
        for statement in NoteSchemaV4.ddl { try connection.execute(statement) }
        for note in notes {
            try connection.execute(
                """
                INSERT INTO note (
                    uuid, title, body, source_kind, source_connection_name, source_fingerprint,
                    source_captured_at, created_at, updated_at, contains_row_data, storage_version,
                    favorite, pinned
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0);
                """,
                [
                    .text(note.id.uuidString),
                    .text(note.title),
                    .text(note.body),
                    .text(note.source.kind.rawValue),
                    note.source.connectionName.map { SQLiteValue.text($0) } ?? .null,
                    note.source.fingerprint.map { SQLiteValue.text($0) } ?? .null,
                    .real(note.source.capturedAt.timeIntervalSince1970),
                    .real(note.createdAt.timeIntervalSince1970),
                    .real(note.updatedAt.timeIntervalSince1970),
                    .integer(note.containsRowData ? 1 : 0),
                    .integer(Int64(NoteSchemaV1.version))
                ]
            )
            if let rowID = try connection.scalarInt("SELECT id FROM note WHERE uuid = ?", [.text(note.id.uuidString)]) {
                for tag in note.tags {
                    try connection.execute(
                        "INSERT INTO note_tag (note_id, tag) VALUES (?, ?)",
                        [.integer(rowID), .text(tag)]
                    )
                }
            }
        }
        try connection.setPragma("user_version = \(NoteSchemaV4.version)")
        try connection.close()
    }

    // MARK: - ① 存量库升级（v4 → v5）

    /// 存量 v4 库打开后升到 **v5**：两张新表在、笔记（含标签）一字不丢、**任务表是空的**。
    func testVersionFourDatabaseUpgradesToVersionFiveWithoutLosingNotes() throws {
        let note = Note(
            title: "存量笔记",
            body: "洞庭湖",
            tags: ["骑行"],
            source: NoteSource(kind: .manual, connectionName: "连接甲", fingerprint: "fp-1"),
            createdAt: moment(0),
            updatedAt: moment(1)
        )
        try makeVersionFourDatabase(notes: [note])

        let database = try makeDatabase()
        XCTAssertEqual(database.userVersion, NoteSchemaV5.version, "v4 库要升到 v5（补表不改既有语义）")
        let tables = try database.tableNames()
        for expected in NoteSchemaV5.tables {
            XCTAssertTrue(tables.contains(expected), "升级后缺表 \(expected)；实际：\(tables)")
        }
        XCTAssertEqual(try database.noteCount(), 1)
        let restored = try XCTUnwrap(try database.note(id: note.id))
        XCTAssertEqual(restored.title, "存量笔记")
        XCTAssertEqual(restored.tags, ["骑行"], "笔记与它的标签都要原样在")
        XCTAssertEqual(try database.todoCount(), 0, "补表不带数据：老库升级后一条任务都没有")
        // 幂等：再开一次库，版本与数据都不动
        XCTAssertEqual(try makeDatabase().todoCount(), 0)
    }

    // MARK: - ② 往返（每条字段都真的进了库）

    /// 全字段往返：可选的两列（无截止 / 没完成过）读回来仍是「没有」，而不是被写成某个时间戳。
    func testTodoRoundTripsEveryField() throws {
        let database = try makeDatabase()
        let due = moment(3_600)
        let todo = sampleTodo(title: "交房租", dueAt: due, priority: .high, tags: ["生活", "钱"])
        try database.upsert(todo)

        let restored = try XCTUnwrap(try database.todo(id: todo.id))
        XCTAssertEqual(restored.title, "交房租")
        XCTAssertEqual(restored.dueAt, due)
        XCTAssertFalse(restored.done)
        XCTAssertNil(restored.completedAt, "没完成过 ⇒ nil（不许拿 0 充当一个真实时刻）")
        XCTAssertEqual(restored.priority, .high)
        XCTAssertEqual(restored.tags, ["生活", "钱"])
        XCTAssertEqual(restored.createdAt, todo.createdAt)
        XCTAssertEqual(restored.updatedAt, todo.updatedAt)

        // 没截止、没标签的那一条也要能往返（`nil` / 空数组不是同一件事）
        let bare = sampleTodo(title: "")
        try database.upsert(bare)
        let restoredBare = try XCTUnwrap(try database.todo(id: bare.id))
        XCTAssertNil(restoredBare.dueAt)
        XCTAssertEqual(restoredBare.tags, [])
        XCTAssertEqual(try database.todoCount(), 2)
        // 覆盖同一条不新增行，且标签是**全量替换**
        var edited = restored
        edited.tags = ["生活"]
        edited.title = "交水电"
        try database.upsert(edited)
        XCTAssertEqual(try database.todoCount(), 2)
        XCTAssertEqual(try database.todo(id: todo.id)?.tags, ["生活"])
        XCTAssertEqual(try database.todo(id: todo.id)?.title, "交水电")
        // 次序稳定：创建时间正序、同时间按 uuid
        let all = try database.todos()
        XCTAssertEqual(all.map(\.id).sorted(by: { $0.uuidString < $1.uuidString }),
                       all.map(\.id), "同一时刻创建的任务按 uuid 兜底排序")
    }

    // MARK: - ③ 完成 / 重开（`done` 与 `dueAt` 互不覆盖）

    /// **完成态切换不丢原始截止时间**（`FR-NOTE-36`、契约裁决 ①）：只动完成态 / 完成时刻 / `updatedAt`。
    func testCompletingAndReopeningNeverTouchesDueDate() throws {
        let database = try makeDatabase()
        let due = moment(86_400)
        let todo = sampleTodo(title: "去银行", dueAt: due)
        try database.upsert(todo)

        let completedAt = moment(90_000)
        XCTAssertEqual(try database.setDone(true, id: todo.id, at: completedAt), 1)
        let completed = try XCTUnwrap(try database.todo(id: todo.id))
        XCTAssertTrue(completed.done)
        XCTAssertEqual(completed.completedAt, completedAt)
        XCTAssertEqual(completed.dueAt, due, "完成任务不许把原始截止时间抹掉")
        XCTAssertEqual(completed.updatedAt, completedAt, "完成属于刷新 updatedAt 的那一档")

        let reopenedAt = moment(95_000)
        XCTAssertEqual(try database.setDone(false, id: todo.id, at: reopenedAt), 1)
        let reopened = try XCTUnwrap(try database.todo(id: todo.id))
        XCTAssertFalse(reopened.done)
        XCTAssertNil(reopened.completedAt, "重开之后「完成时刻」不再成立 ⇒ nil")
        XCTAssertEqual(reopened.dueAt, due, "重开也不许动截止时间（逾期仍按这个原值判）")
        XCTAssertEqual(reopened.updatedAt, reopenedAt)
    }

    /// 认不出的 id ⇒ **0 行**（调用方据此如实交代，而不是假装改成了）。
    func testSetDoneReportsUnmatchedIdentifiersInsteadOfPretending() throws {
        let database = try makeDatabase()
        let todo = sampleTodo(title: "只有这一条")
        try database.upsert(todo)
        XCTAssertEqual(try database.setDone(true, id: UUID(), at: moment(10)), 0, "库里没有这个 id ⇒ 一行都不该被改")
        XCTAssertFalse(try XCTUnwrap(try database.todo(id: todo.id)).done, "没有被点名的任务不该被顺手改掉")
        XCTAssertEqual(try database.setDone(true, id: todo.id, at: moment(10)), 1)
    }

    // MARK: - ④ 认不出的优先级「当没给」

    /// 库里躺着别端写进来的新取值（这里用 `urgent` 冒充）：读出来是 `.normal`，**不抛错、不降级成别的档**。
    func testUnknownPriorityReadsBackAsNormalRatherThanFailing() throws {
        let database = try makeDatabase()
        let todo = sampleTodo(title: "别端来的", priority: .high)
        try database.upsert(todo)
        XCTAssertEqual(try database.todo(id: todo.id)?.priority, .high)

        let connection = try SQLiteConnection(path: url().path)
        try connection.execute(
            "UPDATE todo SET priority = ? WHERE uuid = ?",
            [.text("urgent"), .text(todo.id.uuidString)]
        )
        try connection.close()

        XCTAssertEqual(
            try database.todo(id: todo.id)?.priority,
            .normal,
            "认不出的取值「当没给」= normal（别端多一档不该让整条任务读不出来）"
        )
        XCTAssertEqual(TodoPriority(raw: "urgent"), .normal)
        XCTAssertEqual(TodoPriority(raw: ""), .normal)
        XCTAssertEqual(TodoPriority(raw: "high"), .high)
    }

    // MARK: - ⑤ 删除与级联

    /// 删一条任务：它的标签跟着走（外键级联），**笔记一个字都不动**。
    func testDeletingTodoCascadesItsTagsAndLeavesNotesAlone() throws {
        let database = try makeDatabase()
        let note = Note(title: "笔记", body: "正文", source: NoteSource())
        try database.upsert(note)
        let todo = sampleTodo(title: "有标签的任务", tags: ["甲", "乙"])
        try database.upsert(todo)

        try database.deleteTodo(id: todo.id)

        XCTAssertEqual(try database.todoCount(), 0)
        XCTAssertNil(try database.todo(id: todo.id))
        XCTAssertEqual(try database.noteCount(), 1, "删任务不许碰笔记")
        // 孤儿行：标签表里不该留下任何一行（`foreign_keys = ON` 是前提）
        let connection = try SQLiteConnection(path: url().path)
        let orphans = try connection.scalarInt("SELECT count(*) FROM todo_tag")
        try connection.close()
        XCTAssertEqual(orphans, 0, "删任务留下的标签孤儿行 = 静默的数据损坏")
    }

    // MARK: - ⑥ 门面（`NoteLibrary`）

    /// 门面两层纪律：① 库不存在时**如实返回空表**（不顺手建一个空库）；
    /// ② 编辑保存**不许把完成态改回去**（完成态只有 `setDone` 一条写路）。
    func testLibraryFacadeKeepsCompletionStateOutOfTheEditPath() async throws {
        let library = NoteLibrary(databaseURL: url())
        let empty = try await library.todos()
        XCTAssertTrue(empty.isEmpty, "库还没建 ⇒ 空表（不是在磁盘上凭空造一个库）")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url().path), "读一下不许建库")

        let todo = sampleTodo(title: "写周报", dueAt: moment(3_600), priority: .low, tags: ["工作"])
        let saved = try await library.upsert(todo)
        XCTAssertEqual(saved.tags, ["工作"])
        _ = try await library.setDone(id: todo.id, true, at: moment(7_200))

        // 编辑标题：内存里这条故意写成「没完成」，库里那份才是事实
        var naive = todo
        naive.title = "写周报（改过）"
        naive.dueAt = moment(10_800)
        let afterEdit = try await library.upsert(naive)
        XCTAssertTrue(afterEdit.done, "门面回的是库里那一份：调用方传的 `done = false` 不许覆盖库里的「已完成」")
        let storedOrNil = try await library.todo(id: todo.id)
        let stored = try XCTUnwrap(storedOrNil)
        XCTAssertTrue(stored.done, "改个标题不许把已完成的任务静默改回未完成")
        XCTAssertEqual(stored.completedAt, moment(7_200))
        XCTAssertEqual(stored.dueAt, moment(10_800), "截止时间跟着调用方（改期就是重写这一列）")
        XCTAssertEqual(stored.title, "写周报（改过）")

        try await library.deleteTodo(id: todo.id)
        let remaining = try await library.todos()
        XCTAssertTrue(remaining.isEmpty)
    }
}
