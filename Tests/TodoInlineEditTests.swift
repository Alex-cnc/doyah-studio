import XCTest
@testable import DoyahCore

/// `FR-NTS-TODO-LIST-002` 的三条判据的机械证据：
///   ① **五列都显示且可改**（标题 / 截止时间 / 完成态 / 优先级 / 标签；空值也有话说）；
///   ② **新建到可见 ≤1 动作**（一次入口 ⇒ 编辑面当场可见，源锚点 + `beginNewTodo` 的那一支）；
///   ③ **删除可撤销**（撤销回来的是**同一条**，不是一条新的同名任务）。
///
/// 覆盖边界（如实）：真鼠标双击 / 真菜单点击本文件够不着 —— 界面那半只判到
/// 可访问性标识与源锚点（`testRowCarriesOneIdentifierPerColumn`）；像素级排版由
/// `verify-ui-interactions.sh` 那 116 条探针承担，本文件不重复。
final class TodoInlineEditTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-todo-inline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private var database: NoteDatabase {
        get throws { try NoteDatabase(path: directory.appendingPathComponent(NoteDatabase.fileName).path) }
    }

    /// 判据用的固定窗口（三个边界自己给 —— `TodoWindow` 的生产入口要「本地日历日 + 时区偏移」，
    /// 这里只要一个稳定的带，不涉及时区）。
    private let baseDate = Date(timeIntervalSince1970: 1_790_000_000)

    private var window: TodoWindow {
        TodoWindow(
            todayStart: baseDate,
            tomorrowStart: baseDate.addingTimeInterval(86_400),
            weekEnd: baseDate.addingTimeInterval(7 * 86_400)
        )
    }

    // MARK: - 判据①：五列都显示（空的那几列也有话说）

    func testFiveColumnsAreAlwaysListedAndNeverEmpty() {
        XCTAssertEqual(TodoInlineField.columns, [.title, .dueAt, .done, .priority, .tags],
                       "① 五列 = 标题 / 截止 / 完成态 / 优先级 / 标签，顺序即行上从左到右")

        // **最低配**的一条：无截止、无标签、普通优先级、未完成 —— 五列仍要各有话说。
        let bare = Todo(title: "")
        let texts = TodoInlinePresentation.allTexts(of: bare, window: window, language: .simplifiedChinese)
        XCTAssertEqual(texts.count, 5)
        XCTAssertTrue(texts.allSatisfy { !$0.isEmpty }, "① 空值也必须有话说（不许出现空串的那一列）：\(texts)")
        XCTAssertEqual(texts[1], "无截止", "② 截止那列空值的话")
        XCTAssertEqual(texts[4], "无标签", "⑤ 标签那列空值的话")
        XCTAssertEqual(texts[2], "未完成", "③ 完成态那列的话")
        XCTAssertEqual(texts[3], "普通", "④ 优先级那列的话")
    }

    func testColumnsShowRealValuesWhenPresent() {
        var todo = Todo(title: "交房租")
        todo.dueAt = Date(timeIntervalSince1970: 1_790_000_000)
        todo.done = true
        todo.priority = .high
        todo.tags = ["家", "钱"]
        let texts = TodoInlinePresentation.allTexts(of: todo, window: window, language: .simplifiedChinese)
        XCTAssertEqual(texts[0], "交房租")
        XCTAssertEqual(texts[3], "高")
        XCTAssertEqual(texts[4], "家、钱", "⑤ 多标签按语言表里的分隔符连起来（不在视图里拼）")
    }

    // MARK: - 判据①：五列各自「只改它那一格」

    func testEachColumnEditTouchesOnlyThatFieldAndKeepsOneRow() throws {
        let db = try database
        var original = Todo(title: "原标题")
        original.dueAt = Date(timeIntervalSince1970: 1_790_000_000)
        original.priority = .low
        original.tags = ["旧标签"]
        original.note = "备注不许被就地改碰掉"
        original.repeatRule = TodoRepeat.every(2, .day)
        try db.upsert(original)

        let now = original.updatedAt.addingTimeInterval(60)
        let edits: [(String, Todo)] = [
            ("① 标题", TodoInlineEdit.settingTitle("改过的标题", on: original, now: now)),
            ("② 截止", TodoInlineEdit.settingDueAt(Date(timeIntervalSince1970: 1_790_500_000), on: original, now: now)),
            ("④ 优先级", TodoInlineEdit.settingPriority(.high, on: original, now: now)),
            ("⑤ 标签", TodoInlineEdit.settingTags("新甲 新乙，新丙", on: original, now: now))
        ]
        for (label, value) in edits {
            try db.upsert(value)
            let restored = try XCTUnwrap(try db.todo(id: original.id), label)
            XCTAssertEqual(try db.todos().count, 1, "\(label) 就地改不许产生第二条")
            XCTAssertGreaterThanOrEqual(restored.updatedAt, original.updatedAt, label)
            // 不在五列里的东西一个都不许动
            XCTAssertEqual(restored.note, original.note, "\(label) 备注")
            XCTAssertEqual(restored.repeatRule, original.repeatRule, "\(label) 重复规则")
            XCTAssertEqual(restored.id, original.id, label)
        }
        // 最后一格：标签按空格 / 逗号切、去空
        // 存储层回读按字母序（`todo_tag` 的 `ORDER BY tag ASC`，与笔记同一口径）⇒ 判据按集合比。
        XCTAssertEqual(Set(try db.todo(id: original.id)?.tags ?? []), Set(["新甲", "新乙", "新丙"]))
    }

    func testDoneColumnKeepsDueDateAndMarksCompletion() throws {
        let db = try database
        var todo = Todo(title: "打卡")
        todo.dueAt = Date(timeIntervalSince1970: 1_790_000_000)
        try db.upsert(todo)

        let moment = Date(timeIntervalSince1970: 1_790_100_000)
        let done = TodoInlineEdit.settingDone(true, on: todo, at: moment)
        try db.upsert(done)
        let checked = try XCTUnwrap(try db.todo(id: todo.id))
        XCTAssertTrue(checked.done, "③ 完成态可改")
        XCTAssertEqual(checked.completedAt, moment, "③ 完成时刻随完成")
        XCTAssertEqual(checked.dueAt, todo.dueAt, "③ 切完成态不许丢截止时间（`FR-NOTE-36`）")

        let reopened = TodoInlineEdit.settingDone(false, on: checked, at: moment.addingTimeInterval(60))
        try db.upsert(reopened)
        let back = try XCTUnwrap(try db.todo(id: todo.id))
        XCTAssertFalse(back.done)
        XCTAssertNil(back.completedAt, "③ 重开即清完成时刻")
        XCTAssertEqual(back.dueAt, todo.dueAt)
    }

    func testTagsSplitOnSpacesAndBothCommasWithoutDuplicates() {
        XCTAssertEqual(TodoInlineEdit.tags(from: "  a  b,c，d  a "), ["a", "b", "c", "d"])
        XCTAssertEqual(TodoInlineEdit.tags(from: ""), [])
    }

    // MARK: - 判据③：删除可撤销

    func testUndoRestoresTheExactSameRowAfterDelete() throws {
        let db = try database
        var todo = Todo(title: "要删的")
        todo.dueAt = Date(timeIntervalSince1970: 1_790_000_000)
        todo.priority = .high
        todo.tags = ["甲", "乙"]
        todo.note = "备注也要回来"
        todo.repeatRule = TodoRepeat.weekly([1, 3]) ?? TodoRepeat.every(1, .week)
        try db.upsert(todo)

        let undo = TodoRemovalUndo(todo: todo, removedAt: Date(timeIntervalSince1970: 1_790_000_500))
        try db.deleteTodo(id: todo.id)
        XCTAssertNil(try db.todo(id: todo.id), "③ 删掉之后库里确实没有（不是「看起来删了」）")
        XCTAssertEqual(try db.todos().count, 0)

        let restored = undo.restored(now: Date(timeIntervalSince1970: 1_790_000_900))
        try db.upsert(restored)
        let back = try XCTUnwrap(try db.todo(id: todo.id), "③ 撤销回来的是同一条（同 id）")
        XCTAssertEqual(try db.todos().count, 1, "③ 不产生第二条")
        XCTAssertEqual(back.title, todo.title)
        XCTAssertEqual(back.dueAt, todo.dueAt)
        XCTAssertEqual(back.priority, todo.priority)
        XCTAssertEqual(Set(back.tags), Set(todo.tags), "⑤ 标签回读按字母序（存储层口径）")
        XCTAssertEqual(back.note, todo.note)
        XCTAssertEqual(back.repeatRule, todo.repeatRule)
        XCTAssertEqual(back.done, todo.done)
        XCTAssertEqual(back.updatedAt, restored.updatedAt, "③ 只把 updatedAt 推到还原时刻")
    }

    // MARK: - 判据① / ② / ③ 的界面半（源锚点；真鼠标点验本文件够不着）

    /// 行上**每列各有一个标识**（①）、就地改那四格 + 提交一次写入（①）、
    /// 新建那一条是**一个动作**（②）、撤销条与撤销动作在盘上（③）。
    ///
    /// 覆盖范围如实声明：只判「这些件在源树里、且标识与调用名对得上」；
    /// 像素排版、真实点击由 `verify-ui-interactions.sh` 与真机点验承担 —— 本文件不报通过。
    func testRowCarriesOneIdentifierPerColumnAndUndoStripExists() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        let row = try source("App/Views/TodoCalendarView.swift")
        for column in ["todo-cell-due-", "todo-cell-priority-", "todo-cell-tags-", "todo-inline-editor-"] {
            XCTAssertTrue(row.contains(column), "① 行上缺这一列的件：\(column)")
        }
        XCTAssertTrue(row.contains("todo-done-toggle-"), "③ 完成态那一列（行首开关）")
        XCTAssertTrue(row.contains("TodoInlinePresentation.text("), "① 五列的句子只从 Core 取")
        // ① 就地改的提交是**一次**写入：`commitTodoInlineEdit` 体内 `upsert` 只许出现一次。
        let state = try source("App/AppState.swift")
        let commit = try XCTUnwrap(
            state.range(of: "func commitTodoInlineEdit() async {"),
            "锚点失效：`commitTodoInlineEdit` 改名了 —— 先修判据，别改断言"
        )
        let tail = state[commit.upperBound...]
        let body = tail.prefix(1_200)
        XCTAssertEqual(
            body.components(separatedBy: "upsert(").count - 1, 1,
            "① 就地改必须一次写入（`upsert(` 只许出现一次）"
        )
        // ② 新建：一个动作 = 那枚唯一的入口 ⇒ 待办档直接进新建态（不经过第二屏）。
        let panel = try source("Plugins/Notes/Views/NotesPanel.swift")
        XCTAssertTrue(panel.contains("case .todos: appState.beginNewTodo()"),
                      "② 新建到可见必须是一个动作（同一个入口直接开新建态）")
        // ③ 撤销条在清单屏上，撤销动作只走 `undoLastTodoRemoval`
        XCTAssertTrue(panel.contains("\"todo-undo-removal\""), "③ 撤销按钮不在盘上")
        XCTAssertTrue(panel.contains("await appState.undoLastTodoRemoval()"), "③ 撤销按钮没接上写回")
        XCTAssertGreaterThanOrEqual(
            state.components(separatedBy: "todoUndoRemoval = TodoRemovalUndo(").count - 1, 1,
            "③ 删除前必须留快照（否则撤销没料可写回）"
        )
    }
}
