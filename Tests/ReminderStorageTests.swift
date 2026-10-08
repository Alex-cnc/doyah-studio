import XCTest
@testable import DoyahCore

// 队列 `L-100` 落法 ④ 的**存储半**（提醒的库表 + 与笔记 / 待办的归属列）的机械证据。
//
// 这一片落的三件东西：① schema **v6**（`reminder` 一张表：规格逐列 + 两个归属列，各自
// `ON DELETE CASCADE` + 一条「恰有一个归属」的 `CHECK`）；② `NoteDatabase` 的写读口
// （upsert / reminder(id:) / reminders(of:) / reminders() / reminderCount / deleteReminder）；
// ③ `NoteLibrary` 门面三件。
//
// 三条纪律（与 `TodoStorageTests` 同形）：
//   ① **都跑真库文件**（临时目录，不用 `:memory:`）—— v5 → v6 那条升级路只在真文件上走得到；
//   ② **升级路径用手搭的 v5 库**（拿 v1~v5 的 DDL 逐版建出来，里面真有笔记 + 标签 + 任务 + 标签）：
//      用当前代码建的库永远是最新版，测不到「老库升上来」，而那正是这一片唯一有风险的路径；
//   ③ **写完读回**：判据读的是库里的那一份事实，不是内存里刚构造的那个值。
final class ReminderStorageTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-reminder-storage-\(UUID().uuidString)", isDirectory: true)
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

    private func sampleTodo(title: String, createdAt: Date) -> Todo {
        Todo(title: title, priority: .normal, tags: ["生活"], createdAt: createdAt, updatedAt: createdAt)
    }

    private func sampleReminder(
        owner: ReminderOwner,
        spec: ReminderSpec = ReminderSpec(rule: "once", anchorDate: "2026-10-05", minuteOfDay: 540),
        createdAt: Date = Date(timeIntervalSince1970: 1_699_000_000)
    ) -> Reminder {
        Reminder(owner: owner, spec: spec, createdAt: createdAt, updatedAt: createdAt)
    }

    // MARK: - ① 新库 = 最新版（v7；reminder 表与索引都在）

    func testFreshDatabaseIsLatestVersionWithReminderTable() throws {
        let database = try makeDatabase()
        // 断言认的是**当前最新版**（`NoteDatabase.supportedVersion`）而不是某一版的号：
        // schema 每加一档（这里是 v7 查询历史），这条用例不该跟着改一个字。
        XCTAssertEqual(database.userVersion, NoteDatabase.supportedVersion)
        let tables = try database.tableNames()
        for expected in NoteSchemaV6.tables {
            XCTAssertTrue(tables.contains(expected), "缺表 \(expected)；实际：\(tables)")
        }
        XCTAssertTrue(try database.foreignKeysEnabled, "级联删靠它：外键必须是开着的")
        XCTAssertEqual(try database.reminderCount(), 0, "新库里一条提醒都没有")
        // 幂等：再开一次库，版本不动
        XCTAssertEqual(try makeDatabase().userVersion, NoteDatabase.supportedVersion)
    }

    // MARK: - ② 存量库升级（手搭 v5 库：v1 → 最新版那条路真的走得通）

    /// 手搭一个 **v5 库** —— 存量用户的库长什么样：v1~v5 的 DDL 都在、`user_version = 5`、
    /// 里面有真笔记（含标签）与真任务（含标签）。**表有几张就要写几张**：
    /// 上一次的教训是标签忘了写，让「标签搬过来没有」那条判据在 fixture 那一步就已经是假的。
    private func makeVersionFiveDatabase(note: Note, todo: Todo) throws {
        let connection = try SQLiteConnection(path: url().path)
        for statement in NoteSchemaV1.ddl { try connection.execute(statement) }
        for statement in NoteSchemaV2.ddl { try connection.execute(statement) }
        for statement in NoteSchemaV3.ddl { try connection.execute(statement) }
        for statement in NoteSchemaV4.ddl { try connection.execute(statement) }
        for statement in NoteSchemaV5.ddl { try connection.execute(statement) }
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
                .null,
                .null,
                .real(note.source.capturedAt.timeIntervalSince1970),
                .real(note.createdAt.timeIntervalSince1970),
                .real(note.updatedAt.timeIntervalSince1970),
                .integer(0),
                .integer(Int64(NoteSchemaV1.version))
            ]
        )
        if let rowID = try connection.scalarInt("SELECT id FROM note WHERE uuid = ?", [.text(note.id.uuidString)]) {
            for tag in note.tags {
                try connection.execute("INSERT INTO note_tag (note_id, tag) VALUES (?, ?)", [.integer(rowID), .text(tag)])
            }
        }
        try connection.execute(
            """
            INSERT INTO todo (uuid, title, due_at, done, completed_at, priority, created_at, updated_at)
            VALUES (?, ?, ?, 0, NULL, ?, ?, ?);
            """,
            [
                .text(todo.id.uuidString),
                .text(todo.title),
                .real(todo.dueAt?.timeIntervalSince1970 ?? 0),
                .text(todo.priority.raw),
                .real(todo.createdAt.timeIntervalSince1970),
                .real(todo.updatedAt.timeIntervalSince1970)
            ]
        )
        if let rowID = try connection.scalarInt("SELECT id FROM todo WHERE uuid = ?", [.text(todo.id.uuidString)]) {
            for tag in todo.tags {
                try connection.execute("INSERT INTO todo_tag (todo_id, tag) VALUES (?, ?)", [.integer(rowID), .text(tag)])
            }
        }
        try connection.setPragma("user_version = \(NoteSchemaV5.version)")
        try connection.close()
    }

    func testVersionFiveDatabaseUpgradesToLatestVersionWithoutLosingAnything() throws {
        let note = Note(
            title: "存量笔记",
            body: "洞庭湖",
            tags: ["骑行"],
            source: NoteSource(kind: .manual, connectionName: "连接甲", fingerprint: "fp-1"),
            createdAt: moment(0),
            updatedAt: moment(1)
        )
        let todo = sampleTodo(title: "存量任务", createdAt: moment(2))
        try makeVersionFiveDatabase(note: note, todo: todo)

        let database = try makeDatabase()
        XCTAssertEqual(database.userVersion, NoteDatabase.supportedVersion, "v5 库要升到最新版（补表不改既有语义）")
        XCTAssertTrue(try database.tableNames().contains("reminder"))
        XCTAssertEqual(try database.noteCount(), 1)
        XCTAssertEqual(try XCTUnwrap(try database.note(id: note.id)).tags, ["骑行"], "笔记与它的标签都要原样在")
        XCTAssertEqual(try database.todoCount(), 1)
        XCTAssertEqual(try XCTUnwrap(try database.todo(id: todo.id)).tags, ["生活"], "任务与它的标签都要原样在")
        XCTAssertEqual(try database.reminderCount(), 0, "补表不带数据：老库升级后一条提醒都没有")
        // 升级后能立刻挂提醒（老库上的新表真的能用）
        try database.upsert(sampleReminder(owner: .todo(todo.id)))
        XCTAssertEqual(try database.reminders(of: .todo(todo.id)).count, 1)
        XCTAssertEqual(try makeDatabase().userVersion, NoteDatabase.supportedVersion, "幂等")
    }

    // MARK: - ③ 往返（规格每个字段都真的进了库）

    func testReminderRoundTripsEverySpecField() throws {
        let database = try makeDatabase()
        let todo = sampleTodo(title: "交房租", createdAt: moment(0))
        try database.upsert(todo)
        let spec = ReminderSpec(
            rule: "weekly",
            anchorDate: "2026-10-05",
            minuteOfDay: 1_439,
            intervalCount: 3,
            intervalUnit: "week",
            weekdays: [5, 1, 1, 3, 9, 0],
            untilDate: "2026-12-31"
        )
        let reminder = Reminder(owner: .todo(todo.id), spec: spec, createdAt: moment(10), updatedAt: moment(11))
        let rowID = try database.upsert(reminder)
        XCTAssertGreaterThan(rowID, 0)

        let restored = try XCTUnwrap(try database.reminder(id: reminder.id))
        XCTAssertEqual(restored.owner, .todo(todo.id))
        XCTAssertFalse(restored.owner.isNote)
        XCTAssertEqual(restored.spec.rule, "weekly")
        XCTAssertEqual(restored.spec.anchorDate, "2026-10-05")
        XCTAssertEqual(restored.spec.minuteOfDay, 1_439)
        XCTAssertEqual(restored.spec.intervalCount, 3)
        XCTAssertEqual(restored.spec.intervalUnit, "week")
        XCTAssertEqual(restored.spec.untilDate, "2026-12-31")
        XCTAssertEqual(restored.spec.weekdays, [1, 3, 5], "去重 + 只留 1~7 + 升序")
        XCTAssertEqual(restored.createdAt, moment(10))
        XCTAssertEqual(restored.updatedAt, moment(11))

        // 库里那一列真的写的是**归一文本**（不是数组的另一种写法）
        let connection = try SQLiteConnection(path: url().path)
        let stored = try connection.scalarText(
            "SELECT weekdays FROM reminder WHERE uuid = ?",
            [.text(reminder.id.uuidString)]
        )
        try connection.close()
        XCTAssertEqual(stored, "1,3,5")
    }

    /// 挂到**笔记**上的一条：归属那一列与待办那条互不串（`note_id` 非空 ⇔ `todo_id` 为空）。
    func testReminderOnANoteKeepsTheNoteSide() throws {
        let database = try makeDatabase()
        let note = Note(title: "开会的备忘", createdAt: moment(0), updatedAt: moment(0))
        try database.upsert(note)
        let reminder = sampleReminder(owner: .note(note.id))
        try database.upsert(reminder)

        let restored = try XCTUnwrap(try database.reminder(id: reminder.id))
        XCTAssertEqual(restored.owner, .note(note.id))
        XCTAssertTrue(restored.owner.isNote)
        XCTAssertEqual(restored.owner.todoID, nil)
        XCTAssertEqual(try database.reminders(of: .note(note.id)).count, 1)
        XCTAssertEqual(try database.reminders(of: .todo(note.id)).count, 0, "同一条 uuid 挂在另一侧不许串台")
    }

    // MARK: - ④ 归属隔离 / 覆盖 / 顺序

    /// 两条任务各挂各自的提醒：查一条只回它自己那几条（**唯一新查询面**）。
    func testRemindersAreScopedToTheirOwner() throws {
        let database = try makeDatabase()
        let first = sampleTodo(title: "交房租", createdAt: moment(0))
        let second = sampleTodo(title: "去银行", createdAt: moment(1))
        try database.upsert(first)
        try database.upsert(second)
        try database.upsert(sampleReminder(owner: .todo(first.id), createdAt: moment(10)))
        try database.upsert(sampleReminder(owner: .todo(first.id), createdAt: moment(11)))
        try database.upsert(sampleReminder(owner: .todo(second.id), createdAt: moment(12)))

        XCTAssertEqual(try database.reminders(of: .todo(first.id)).map(\.createdAt), [moment(10), moment(11)])
        XCTAssertEqual(try database.reminders(of: .todo(second.id)).count, 1)
        XCTAssertEqual(try database.reminders().count, 3, "全部提醒 = 三条")
        XCTAssertEqual(try database.reminderCount(), 3)
        XCTAssertEqual(try database.reminders(of: .todo(UUID())), [], "问一条**不存在**的任务：如实回空表，不抛错")
    }

    /// 同一条 uuid 再写一次 = **覆盖**（不新增行）：规格与 `updatedAt` 跟着新值走。
    func testUpsertOverwritesTheSameRowInsteadOfAdding() throws {
        let database = try makeDatabase()
        let todo = sampleTodo(title: "交房租", createdAt: moment(0))
        try database.upsert(todo)
        var reminder = sampleReminder(owner: .todo(todo.id), createdAt: moment(10))
        try database.upsert(reminder)

        reminder.spec = ReminderSpec(rule: "interval", anchorDate: "2026-10-06", minuteOfDay: 600, intervalCount: 2, intervalUnit: "day")
        reminder.updatedAt = moment(20)
        try database.upsert(reminder)

        XCTAssertEqual(try database.reminderCount(), 1, "同一条 uuid 不许变成两行")
        let restored = try XCTUnwrap(try database.reminder(id: reminder.id))
        XCTAssertEqual(restored.spec.rule, "interval")
        XCTAssertEqual(restored.spec.intervalCount, 2)
        XCTAssertEqual(restored.updatedAt, moment(20))
        XCTAssertEqual(restored.createdAt, moment(10), "创建时刻不因改写而变")
    }

    /// **归属那一行不存在 ⇒ 写入失败**（不落一条谁也找不到的提醒 —— 它到点会弹，而界面里没有它）。
    func testWriteFailsWhenTheOwnerDoesNotExist() throws {
        let database = try makeDatabase()
        XCTAssertThrowsError(try database.upsert(sampleReminder(owner: .todo(UUID()))))
        XCTAssertThrowsError(try database.upsert(sampleReminder(owner: .note(UUID()))))
        XCTAssertEqual(try database.reminderCount(), 0, "失败的那一次一个字节都不该落库")
    }

    /// 删一条提醒：**幂等**（认不出的 id 不算错）。
    func testDeletingAReminderIsIdempotent() throws {
        let database = try makeDatabase()
        let todo = sampleTodo(title: "交房租", createdAt: moment(0))
        try database.upsert(todo)
        let reminder = sampleReminder(owner: .todo(todo.id))
        try database.upsert(reminder)

        try database.deleteReminder(id: reminder.id)
        XCTAssertEqual(try database.reminderCount(), 0)
        XCTAssertNil(try database.reminder(id: reminder.id))
        try database.deleteReminder(id: reminder.id)
        try database.deleteReminder(id: UUID())
        XCTAssertEqual(try database.reminderCount(), 0)
    }

    // MARK: - ⑤ 删目标 ⇒ 它的提醒一并走（人工测试清单第 7 条：不留孤儿提醒）

    /// **任务真删后它的提醒一并清** —— 靠外键级联（形状），不是靠删除路径上记得多写一句。
    func testDeletingATodoTakesItsRemindersWithIt() throws {
        let database = try makeDatabase()
        let todo = sampleTodo(title: "交房租", createdAt: moment(0))
        let keeper = sampleTodo(title: "去银行", createdAt: moment(1))
        try database.upsert(todo)
        try database.upsert(keeper)
        let doomed = sampleReminder(owner: .todo(todo.id), createdAt: moment(10))
        let survivor = sampleReminder(owner: .todo(keeper.id), createdAt: moment(11))
        try database.upsert(doomed)
        try database.upsert(survivor)

        try database.deleteTodo(id: todo.id)

        XCTAssertNil(try database.reminder(id: doomed.id), "孤儿提醒的害处是它到点会弹，而界面上找不到它")
        XCTAssertEqual(try database.reminders(of: .todo(todo.id)), [])
        XCTAssertEqual(try database.reminders(of: .todo(keeper.id)).map(\.id), [survivor.id], "别人的提醒一个都不许动")
    }

    /// 笔记同理（`note_id` 那条列也是 `ON DELETE CASCADE`）。
    func testDeletingANoteTakesItsRemindersWithIt() throws {
        let database = try makeDatabase()
        let note = Note(title: "要删的笔记", createdAt: moment(0), updatedAt: moment(0))
        let kept = Note(title: "留下的笔记", createdAt: moment(1), updatedAt: moment(1))
        try database.upsert(note)
        try database.upsert(kept)
        let doomed = sampleReminder(owner: .note(note.id), createdAt: moment(10))
        let survivor = sampleReminder(owner: .note(kept.id), createdAt: moment(11))
        try database.upsert(doomed)
        try database.upsert(survivor)

        try database.delete(id: note.id)

        XCTAssertNil(try database.reminder(id: doomed.id))
        XCTAssertEqual(try database.reminders(of: .note(kept.id)).map(\.id), [survivor.id])
        XCTAssertEqual(try database.reminderCount(), 1)
    }

    // MARK: - ⑥ 周内取值的落库文本（写与读同一个归一；脏值不抛错）

    func testWeekdaysTextNormalizesBothWays() throws {
        XCTAssertEqual(ReminderSpec.weekdaysText([]), "")
        XCTAssertEqual(ReminderSpec.weekdaysText([3, 1, 1, 7, 0, 8, -1]), "1,3,7", "去重 + 只留 1~7 + 升序")
        XCTAssertEqual(ReminderSpec.weekdays(from: " 5,1 ,x,,3 "), [1, 3, 5], "认不出的片段剔除、不抛错")
        XCTAssertEqual(ReminderSpec.weekdays(from: ""), [])
        XCTAssertEqual(ReminderSpec(weekdays: [5, 1, 3]).weekdaysText, "1,3,5")
        // 往返：文本 → 取值 → 文本 是同一个写法（否则库里与界面会是两种次序）
        XCTAssertEqual(ReminderSpec.weekdaysText(ReminderSpec.weekdays(from: "7,2,2")), "2,7")
    }

    /// 库里躺着别端写进来的脏文本：读出来是**剔过脏的那一份**，不抛错、也不整条读不出来。
    func testDirtyWeekdaysInTheDatabaseAreFilteredNotFatal() throws {
        let database = try makeDatabase()
        let todo = sampleTodo(title: "别端来的", createdAt: moment(0))
        try database.upsert(todo)
        let reminder = sampleReminder(
            owner: .todo(todo.id),
            spec: ReminderSpec(rule: "weekly", anchorDate: "2026-10-05", minuteOfDay: 540, weekdays: [2])
        )
        try database.upsert(reminder)

        let connection = try SQLiteConnection(path: url().path)
        try connection.execute(
            "UPDATE reminder SET weekdays = ? WHERE uuid = ?",
            [.text("2,2,9,mon,4"), .text(reminder.id.uuidString)]
        )
        try connection.close()

        let restored = try XCTUnwrap(try database.reminder(id: reminder.id))
        XCTAssertEqual(restored.spec.weekdays, [2, 4], "剔脏之后仍是升序取值；整条提醒照样读得出来")
        XCTAssertEqual(restored.spec.rule, "weekly")
    }
}
