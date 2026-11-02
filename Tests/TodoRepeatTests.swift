import XCTest
@testable import DoyahCore

/// `FR-NTS-TODO-LIST-001` 判据①的机械证据：**待办本体四字段（标题 / 截止时间 / 重复规则 / 完成态）
/// 齐全且可编辑**，空值语义明确（无截止 = 空，不是今天；从未完成 ⇒ 完成时刻为空；不重复 = `nil`）。
///
/// 判据③（加密）在本文件**不判通过**：本仓笔记侧没有开启存储层加密（概设 §15.6 说加密属整库层），
/// 这里只判「待办与笔记同一个库文件 / 同一条快照导出链路」—— 见 `testTodosLiveInTheSameLibraryFileAndSnapshot`。
final class TodoRepeatTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-todo-repeat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func url(_ name: String = NoteDatabase.fileName) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    private var database: NoteDatabase { get throws { try NoteDatabase(path: url().path) } }

    // MARK: - 判据①：四字段齐全且可编辑（写进去 → 读回来逐字段相等）

    func testAllFourBodyFieldsRoundTripThroughStorage() throws {
        let db = try database
        var todo = Todo(title: "交房租")
        todo.dueAt = Date(timeIntervalSince1970: 1_790_000_000)
        todo.repeatRule = TodoRepeat.every(2, .week)
        todo.done = true
        todo.completedAt = Date(timeIntervalSince1970: 1_790_000_500)

        try db.upsert(todo)
        let restored = try XCTUnwrap(try db.todo(id: todo.id))

        XCTAssertEqual(restored.title, "交房租", "① 标题")
        XCTAssertEqual(restored.dueAt, todo.dueAt, "② 截止时间")
        XCTAssertEqual(restored.repeatRule, TodoRepeat(rule: .interval, intervalCount: 2, intervalUnit: .week),
                       "③ 重复规则")
        XCTAssertEqual(restored.done, true, "④ 完成态")
        XCTAssertEqual(restored.completedAt, todo.completedAt)
    }

    /// 四个字段各自都能**单独改**，改一个不动另一个（可编辑 ≠ 一次性写死）。
    func testEachFieldCanBeEditedIndependently() throws {
        let db = try database
        var todo = Todo(title: "初稿")
        try db.upsert(todo)

        // 只改标题
        todo.title = "改过的标题"
        try db.upsert(todo)
        XCTAssertEqual(try db.todo(id: todo.id)?.title, "改过的标题")

        // 只加截止
        todo.dueAt = Date(timeIntervalSince1970: 1_790_000_100)
        try db.upsert(todo)
        XCTAssertEqual(try db.todo(id: todo.id)?.dueAt, todo.dueAt)
        XCTAssertNil(try db.todo(id: todo.id)?.repeatRule, "加截止不该顺手塞一条重复规则")

        // 只加重复规则
        todo.repeatRule = TodoRepeat.weekly([1, 3, 5])
        try db.upsert(todo)
        XCTAssertEqual(try db.todo(id: todo.id)?.repeatRule?.weekdays, [1, 3, 5])

        // 只改完成态（`setDone` 那条写路 —— 它碰不到 `due_at` / `repeat_rule`）
        _ = try db.setDone(true, id: todo.id, at: Date(timeIntervalSince1970: 1_790_000_200))
        let afterDone = try XCTUnwrap(try db.todo(id: todo.id))
        XCTAssertTrue(afterDone.done)
        XCTAssertEqual(afterDone.dueAt, todo.dueAt, "完成不清截止（契约裁决 ①）")
        XCTAssertEqual(afterDone.repeatRule?.weekdays, [1, 3, 5], "完成不改重复规则")
    }

    /// 空值语义：无截止 = `nil`（**不是今天**）；从未完成 ⇒ `completedAt` 为 `nil`；不重复 = `nil`。
    func testEmptyValuesStayEmptyInsteadOfDefaultingToToday() throws {
        let db = try database
        let todo = Todo(title: "没有截止的")
        try db.upsert(todo)

        let restored = try XCTUnwrap(try db.todo(id: todo.id))
        XCTAssertNil(restored.dueAt, "无截止就是空，不许被存成「今天到期」")
        XCTAssertNil(restored.completedAt, "从未完成 ⇒ 完成时刻为空")
        XCTAssertFalse(restored.done)
        XCTAssertNil(restored.repeatRule, "不重复 ⇒ 空（唯一的写法）")
        // 落库文本 = 空串（不是 `{}` 那种「有值但无意义」）—— 由存储层自己的写法证明：
        XCTAssertEqual(TodoRepeat.decode(storageText: ""), nil)
    }

    // MARK: - 归一：同一件事只有一种写法

    func testOnceRuleNormalizesToNoRepeat() {
        XCTAssertNil(TodoRepeat(rule: .once).normalized(), "`once`（只响一次）不是一种重复 ⇒ 归一成「不重复」")
        XCTAssertEqual(TodoRepeat(rule: .once).storageText, "", "归一之后落库文本是空串（同一件事只有一种写法）")
    }

    func testWeeklyRuleWithoutAnyDayNormalizesToNoRepeat() {
        XCTAssertNil(TodoRepeat(rule: .weekly, weekdays: []).normalized(), "一天都没选 ⇒ 没有发生日 ⇒ 不重复")
        XCTAssertNil(TodoRepeat(rule: .weekly, weekdays: [0, 8, -1]).normalized(), "非 1~7 的值不算数")
        XCTAssertEqual(TodoRepeat(rule: .weekly, weekdays: [5, 1, 1, 3]).normalized()?.weekdays, [1, 3, 5],
                       "周内取值升序去重（与提醒同一条归一）")
    }

    func testIntervalCountBelowOneNormalizesToOne() {
        XCTAssertEqual(TodoRepeat(rule: .interval, intervalCount: 0, intervalUnit: .day).normalized()?.intervalCount, 1)
        XCTAssertEqual(TodoRepeat(rule: .interval, intervalCount: -3, intervalUnit: .week).normalized()?.intervalCount, 1)
    }

    /// 落库文本**确定性**（同一规则两次编码逐字节相同），且与 `Codable` 是同一组键。
    func testStorageTextIsDeterministicAndDecodesBack() {
        let rule = TodoRepeat(rule: .weekly, weekdays: [3, 1])
        XCTAssertEqual(rule.storageText, rule.storageText)
        XCTAssertEqual(TodoRepeat.decode(storageText: rule.storageText)?.weekdays, [1, 3])
        XCTAssertNil(TodoRepeat.decode(storageText: ""), "空串 = 没有")
        XCTAssertNil(TodoRepeat.decode(storageText: "not json"), "解不出 ⇒ 没有（不抛错）")
        XCTAssertNil(
            TodoRepeat.decode(storageText: "{\"rule\":\"monthly\",\"intervalCount\":1,\"intervalUnit\":\"day\",\"weekdays\":[]}"),
            "认不出的规则 ⇒ 当没给"
        )
    }

    // MARK: - 交换面（`Codable`）：加字段不许让旧数据解不出来

    func testTodoCodableToleratesMissingAndUnknownRepeatField() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let base: [String: Any] = [
            "id": UUID().uuidString,
            "title": "旧备份里的任务",
            "note": "",
            "done": false,
            "priority": "normal",
            "tags": ["a"],
            "createdAt": 1_700_000_000,
            "updatedAt": 1_700_000_000,
        ]

        // ① 完全没有这一格（旧备份）
        let withoutField = try JSONSerialization.data(withJSONObject: base)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let old = try decoder.decode(Todo.self, from: withoutField)
        XCTAssertNil(old.repeatRule, "缺字段 ⇒ 不重复")
        XCTAssertEqual(old.title, "旧备份里的任务", "其余字段照常读回来（加字段不丢条目）")

        // ② 有这一格但规则认不出
        var unknown = base
        unknown["repeatRule"] = [
            "rule": "monthly", "intervalCount": 1, "intervalUnit": "day", "weekdays": [] as [Int],
        ]
        let unknownData = try JSONSerialization.data(withJSONObject: unknown)
        let tolerant = try decoder.decode(Todo.self, from: unknownData)
        XCTAssertNil(tolerant.repeatRule, "认不出的规则当没给")
        XCTAssertEqual(tolerant.tags, ["a"], "整条仍要读得进来")

        // ③ 正常值往返
        var roundTrip = old
        roundTrip.repeatRule = TodoRepeat.daily
        let data = try encoder.encode(roundTrip)
        let back = try decoder.decode(Todo.self, from: data)
        XCTAssertEqual(back.repeatRule, .daily)
    }

    // MARK: - schema v14：v13 库升上来不许动既有行

    func testVersionThirteenDatabaseUpgradesAddingRepeatColumnWithoutTouchingRows() throws {
        let existing = Todo(title: "v13 时的任务", dueAt: Date(timeIntervalSince1970: 1_780_000_000))
        try makeVersionThirteenDatabaseWithTodo(existing)

        let db = try database
        XCTAssertEqual(db.userVersion, NoteDatabase.supportedVersion, "v13 库要升到最新版")
        let restored = try XCTUnwrap(try db.todo(id: existing.id))
        XCTAssertEqual(restored.title, "v13 时的任务", "补列不许动既有行")
        XCTAssertEqual(restored.dueAt, existing.dueAt)
        XCTAssertNil(restored.repeatRule, "存量行的重复规则 = 不重复（`DEFAULT ''`），不是「读不出来」")

        // 补列之后写读同一条照样走得通
        var edited = restored
        edited.repeatRule = TodoRepeat.daily
        try db.upsert(edited)
        XCTAssertEqual(try db.todo(id: existing.id)?.repeatRule, .daily)
        XCTAssertEqual(try NoteDatabase(path: url().path).todo(id: existing.id)?.repeatRule, .daily, "重开仍在")
    }

    /// 手搭一个 **v13 库**（v1~v13 的 DDL 全在、`user_version = 13`、一条真任务）——
    /// 「老库升上来」是这一片唯一有风险的路径，只用当前代码建的库测不到它。
    private func makeVersionThirteenDatabaseWithTodo(_ todo: Todo) throws {
        let connection = try SQLiteConnection(path: url().path)
        for schema in [
            NoteSchemaV1.ddl, NoteSchemaV2.ddl, NoteSchemaV3.ddl, NoteSchemaV4.ddl,
            NoteSchemaV5.ddl, NoteSchemaV6.ddl, NoteSchemaV7.ddl, NoteSchemaV8.ddl,
            NoteSchemaV9.ddl, NoteSchemaV10.ddl, NoteSchemaV11.ddl, NoteSchemaV12.ddl,
            NoteSchemaV13.ddl,
        ] {
            for statement in schema { try connection.execute(statement) }
        }
        try connection.execute(
            """
            INSERT INTO todo (uuid, title, note, due_at, done, completed_at, priority, created_at, updated_at)
            VALUES (?, ?, '', ?, 0, NULL, 'normal', ?, ?);
            """,
            [
                .text(todo.id.uuidString),
                .text(todo.title),
                todo.dueAt.map { SQLiteValue.real($0.timeIntervalSince1970) } ?? .null,
                .real(todo.createdAt.timeIntervalSince1970),
                .real(todo.updatedAt.timeIntervalSince1970),
            ]
        )
        try connection.setPragma("user_version = \(NoteSchemaV13.version)")
        try connection.close()
    }

    // MARK: - 一句话说明（语言表一处出）

    func testPresentationUsesOneSentencePerRuleInBothLanguages() {
        XCTAssertNil(TodoRepeatPresentation.summary(nil, language: .simplifiedChinese), "不重复不出句子")
        XCTAssertNil(TodoRepeatPresentation.summary(TodoRepeat(rule: .once), language: .english))

        XCTAssertEqual(
            TodoRepeatPresentation.summary(TodoRepeat.daily, language: .simplifiedChinese),
            "每天"
        )
        XCTAssertEqual(
            TodoRepeatPresentation.summary(TodoRepeat.every(3, .day), language: .english),
            "Every 3 days"
        )
        XCTAssertEqual(
            TodoRepeatPresentation.summary(TodoRepeat.every(2, .week), language: .simplifiedChinese),
            "每 2 周"
        )
        XCTAssertEqual(
            TodoRepeatPresentation.summary(TodoRepeat.weekly([1, 3]), language: .simplifiedChinese),
            "每周 周一、周三"
        )
        XCTAssertEqual(
            TodoRepeatPresentation.summary(TodoRepeat.weekly([1, 3]), language: .english),
            "Every Mon, Wed"
        )
    }

    /// 判据③的**覆盖范围**（如实）：待办与笔记在**同一个库文件**里，快照导出走**同一条** `snapshot`；
    /// 加密本身没有开启 ⇒ 这一条**不算通过**，只证明「不另开第二套存储 / 导出链路」。
    func testTodosLiveInTheSameLibraryFileAndSnapshot() async throws {
        let library = NoteLibrary(databaseURL: url())
        let note = try await library.save(NoteDraft(title: "笔记", body: "正文"), id: UUID())
        let todo = try await library.upsert(Todo(title: "同一份里的任务"))
        XCTAssertEqual(note.title, "笔记")

        let baseline = try await library.todos()
        XCTAssertEqual(baseline.map(\.id), [todo.id], "待办读自同一个库")

        let snapshotURL = directory.appendingPathComponent("backup.sqlite3")
        _ = try await library.snapshot(to: snapshotURL)

        // 备份里**这两类对象都在**（同一份文件、同一条导出链路）
        let backup = try NoteDatabase(path: snapshotURL.path)
        XCTAssertEqual(try backup.todoCount(), 1, "快照带上待办")
        XCTAssertEqual(try backup.todos().first?.title, "同一份里的任务")
        // 备份里没有任何密钥材料（加密未开启 ⇒ 只有明文数据；这一条只证明「不带密钥」）
        let bytes = try Data(contentsOf: snapshotURL)
        XCTAssertNil(bytes.range(of: Data("BEGIN PRIVATE KEY".utf8)), "导出不带私钥块")
    }
}
