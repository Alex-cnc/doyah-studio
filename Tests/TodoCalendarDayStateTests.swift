import XCTest
@testable import DoyahCore
@testable import DoyahStudioApp

/// `FR-NTS-TODO-CALENDAR-002` / `FR-NTS-TODO-STATE-001` / `FR-NTS-TODO-STATE-002` 的机械证据
/// （v0.4.0 批次 `N3` 第二片）。三条是**同一件事的三个面**：
///
///  ① 点某天看当天任务、点任务进详情、**逾期显式标识**（`CALENDAR-002`）；
///  ② 完成 / 改期在清单与日历上是**同一次写入**，日历上能直接完成 / 改期（`STATE-001`）；
///  ③ 清单是**唯一事实源**：日历不另存、切视图不复制、不产生第二套状态（`STATE-002`）。
///
/// 判据分两层：能算的算（投影 / 逾期判定 / 拖拽载荷 / AppState 的派生读数），
/// 只能看接线的读源树（视图里有没有那一枚标、写路是不是同一条）。
/// **未验证**（本文件不覆盖）：真鼠标点格子 / 真拖一次 / 点开详情右栏的画面 —— 那属人工点验。
@MainActor
final class TodoCalendarDayStateTests: XCTestCase {

    // MARK: - 工具

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "UTC")!
        value.locale = Locale(identifier: "en_US_POSIX")
        return value
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    private func monthCells(_ year: Int, _ month: Int) -> [TodoCalendarCell] {
        TodoCalendar.monthCells(year: year, month: month, calendar: calendar)
    }

    private func dayTask(_ days: [TodoDayTasks], _ dayOfMonth: Int) -> TodoDayTasks? {
        days.first { calendar.component(.day, from: $0.date) == dayOfMonth }
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        return Self.stripComments(text)
    }

    /// 只剥 `//` 行注释：接线判据不该被注释里的词命中（同族判据既有做法）。
    private static func stripComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let range = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<range.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - ① 点某天看当天任务（CALENDAR-002）

    func testDayProjectionOnlyCarriesThatDaysTasks() {
        let monday = Todo(title: "开周会", dueAt: at(2026, 10, 5, 9))
        let tuesday = Todo(title: "交周报", dueAt: at(2026, 10, 6, 18))
        let floating = Todo(title: "随时读的一本书")

        let days = TodoCalendar.tasksByDay(
            [monday, tuesday, floating], cells: monthCells(2026, 10), now: at(2026, 10, 1), calendar: calendar
        )

        XCTAssertEqual(dayTask(days, 5)?.open.map(\.id), [monday.id], "点 10-05 只该看到那天的任务")
        XCTAssertEqual(dayTask(days, 6)?.open.map(\.id), [tuesday.id])
        XCTAssertEqual(dayTask(days, 5)?.total, 1, "别的日子不进这一格")
        XCTAssertTrue(days.allSatisfy { $0.total > 0 }, "空的天不出现（界面据此决定画不画点）")
        XCTAssertFalse(days.contains { $0.open.contains { $0.id == floating.id } },
                       "无截止的任务不进日历（它仍在清单里）")
    }

    func testSelectingADayShowsExactlyThatDaysTasks() {
        let state = AppState()
        let dayA = Todo(title: "A 日的活", dueAt: at(2027, 3, 15, 9))
        let dayB = Todo(title: "B 日的活", dueAt: at(2027, 3, 16, 9))
        state.todos = [dayA, dayB]

        state.selectTodoCalendarDay(at(2027, 3, 15, 12))
        let sectionsA = state.todoCalendarSelectedDaySections
        XCTAssertEqual(sectionsA.first { $0.kind == .open }?.todos.map(\.id), [dayA.id],
                       "点某天 ⇒ 那一区只画那天的任务")
        XCTAssertTrue(state.todoCalendarSelectedDayHasTasks)

        state.selectTodoCalendarDay(at(2027, 3, 16, 1))
        XCTAssertEqual(state.todoCalendarSelectedDaySections.first { $0.kind == .open }?.todos.map(\.id), [dayB.id],
                       "换一天 ⇒ 那一区跟着换（不是把上一天的行留在屏上）")
    }

    func testClickingATaskOpensReadOnlyDetail() {
        let state = AppState()
        let todo = Todo(title: "点开看看", dueAt: at(2027, 3, 15, 9))
        state.todos = [todo]

        state.showTodoDetail(todo)

        XCTAssertEqual(state.todoDetailID, todo.id, "点任务 ⇒ 右栏记下「看哪一条」")
        XCTAssertEqual(state.todoDetailTodo?.id, todo.id, "详情那一屏读的是**库里那一条**（同 id）")
        XCTAssertNil(state.todoEditingID, "点开是「看」，不是「改」")
    }

    // MARK: - ① 逾期显式标识（CALENDAR-002 判据③）

    /// 逾期按**那一格**判：锚点在过去的重复任务，未来的那几天**还没到**，不许刷成逾期。
    /// （反例见证据文件：把判定改回「原截止早于今天」⇒ 本例判红。）
    func testOverdueIsJudgedPerOccurrenceDayNotByTheAnchor() {
        let weekly = Todo(
            title: "健身",
            dueAt: at(2026, 9, 7, 9),
            repeatRule: TodoRepeat.weekly([1])
        )
        let days = TodoCalendar.tasksByDay(
            [weekly], cells: monthCells(2026, 10), now: at(2026, 10, 14), calendar: calendar
        )

        XCTAssertEqual(dayTask(days, 5)?.overdue, 1, "10-05 已过 ⇒ 逾期")
        XCTAssertEqual(dayTask(days, 12)?.overdue, 1, "10-12 已过 ⇒ 逾期")
        XCTAssertEqual(dayTask(days, 19)?.overdue, 0, "10-19 还没到 ⇒ 不算逾期（锚点在 9 月不算理由）")
        XCTAssertEqual(dayTask(days, 26)?.overdue, 0)
        XCTAssertEqual(dayTask(days, 5)?.overdueTodos.map(\.id), [weekly.id],
                       "逾期要说得清是**哪一条**（不是只给一个数）")
    }

    func testDoneOccurrenceIsNeverOverdueButStaysOnTheDay() {
        let finished = Todo(title: "已经做掉", dueAt: at(2026, 10, 6, 9), done: true)
        let days = TodoCalendar.tasksByDay(
            [finished], cells: monthCells(2026, 10), now: at(2026, 10, 20), calendar: calendar
        )

        XCTAssertEqual(dayTask(days, 6)?.overdue, 0, "做完的不算欠着")
        XCTAssertEqual(dayTask(days, 6)?.done.map(\.id), [finished.id], "它仍留在那一天（落在已完成那一区）")
        XCTAssertEqual(dayTask(days, 6)?.open.count, 0)
    }

    func testDueTodayIsNotOverdue() {
        let today = Todo(title: "今天到期", dueAt: at(2026, 10, 14, 9))
        let days = TodoCalendar.tasksByDay(
            [today], cells: monthCells(2026, 10), now: at(2026, 10, 14, 23), calendar: calendar
        )
        XCTAssertEqual(dayTask(days, 14)?.overdue, 0, "今天到期的还没过完，不算逾期")
    }

    func testDayPaneShowsOverdueCountAndRowBadgeFromTheSameProjection() {
        let state = AppState()
        let anchor = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let daily = Todo(title: "每天欠着的", dueAt: anchor, repeatRule: TodoRepeat.every(1, .day))
        state.todos = [daily]
        // 选**过去的那一天**：那一次发生日确实已经过去 ⇒ 逾期 1 条
        // （今天的格子永远不算逾期 —— 那正是「按那一格判」的意思）。
        let past = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        state.selectTodoCalendarDay(past)

        XCTAssertEqual(state.todoCalendarSelectedDayOverdue, 1,
                       "选中日的逾期读数来自同一份投影（不另算一遍）")
        XCTAssertEqual(state.todoCalendarSelectedDaySections.first { $0.kind == .open }?.todos.map(\.id),
                       [daily.id], "过期那一格仍看得到它（逾期不是「消失」）")
        XCTAssertEqual(state.todos.count, 1, "读一眼不改库、不多出一条")

        let view = try? source("App/Views/TodoCalendarView.swift")
        XCTAssertTrue(view?.contains("todo-calendar-overdue-count") ?? false,
                      "那一天顶上要**说出来**几条逾期")
        XCTAssertTrue(view?.contains("todo-overdue-badge-") ?? false,
                      "每一行要挂一枚「逾期」标（只染红字不算显式）")
        XCTAssertTrue(view?.contains("TodoDue.isOverdue(todo, on: occurrenceDay") ?? false,
                      "行上的逾期判定必须走唯一出处，并按那一格判")
    }

    func testDayListUsesTheSameRowRendererAndOpensDetail() throws {
        let view = try source("App/Views/TodoCalendarView.swift")
        XCTAssertTrue(view.contains("TodoSectionListView(\n                    sections: appState.todoCalendarSelectedDaySections,"),
                      "当天任务用清单那一个渲染件（两处各画一遍就会「一处多一枚标、另一处没有」）")
        XCTAssertTrue(view.contains("occurrenceDay: appState.todoCalendarSelectedDay"),
                      "日历画出来的行带着「哪一天那一回」")
        XCTAssertTrue(view.contains("TodoRowView(todo: todo, occurrenceDay: occurrenceDay)"))
        XCTAssertTrue(view.contains("appState.showTodoDetail(todo)"), "点一行 ⇒ 只读详情")
    }

    // MARK: - ② 完成 / 改期同一次写入（STATE-001）

    func testCalendarPaneNeverWritesTheDatabaseItself() throws {
        let view = try source("App/Views/TodoCalendarView.swift")
        for forbidden in ["NoteLibrary", "NoteDatabase", "upsert(", "setDone(", "saveOccurrenceEdit("] {
            XCTAssertFalse(view.contains(forbidden),
                           "日历视图里出现写库标识 `\(forbidden)` ⇒ 它自己开了一条写路（清单 / 日历就会各写一份）")
        }
        XCTAssertTrue(view.contains("appState.toggleTodoDone(todo)"),
                      "完成 / 重开走 AppState 那一条写路")
        XCTAssertTrue(view.contains("appState.beginReschedule(todo, on: occurrenceDay)"),
                      "改期走那一条既有写路")
    }

    func testRescheduleHasExactlyOneWriteSite() throws {
        let state = try source("App/AppState.swift")
        XCTAssertEqual(state.components(separatedBy: "row.dueAt = draft.dueAt").count - 1, 1,
                       "「改到哪一刻」只许有一处落笔（两处就会出现「一处刷新一处不刷新」）")
        XCTAssertEqual(state.components(separatedBy: "saveOccurrenceEdit(").count - 1, 1,
                       "重复任务那两笔只许有一个事务入口")
        XCTAssertTrue(state.contains("_ = try await NoteLibrary.defaultLibrary().upsert(row)"),
                      "非重复任务改期走门面那一条 upsert")
    }

    func testDraggingOntoACellLandsOnTheSameWritePath() throws {
        let state = try source("App/AppState.swift")
        let view = try source("App/Views/TodoCalendarView.swift")

        XCTAssertTrue(view.contains("dropDestination(for: String.self)"), "格子要收得下拖进来的行")
        XCTAssertTrue(view.contains(".draggable(appState.todoDragPayload(todo))"),
                      "日历画出来的行要能拖走（载荷只由 AppState 生产）")
        XCTAssertTrue(state.contains("TodoDragPayload.decode(payload)"), "落点先解载荷，不猜 id")
        XCTAssertTrue(state.contains("await rescheduleTodo(todo, to: day)"), "落点交给改期那一条路")

        guard let body = state.range(of: "func rescheduleTodo(_ todo: Todo, to day: Date) async {") else {
            return XCTFail("`rescheduleTodo` 不在 ⇒ 拖拽没有落点")
        }
        let tail = state[body.lowerBound...].prefix(900)
        XCTAssertTrue(tail.contains("await applyReschedule()"),
                      "拖拽改期必须走 `applyReschedule()`（自己再 upsert 一次就是第二条写路）")
        XCTAssertFalse(tail.contains(".upsert("), "拖拽那条路上不许出现第二个写库点")
    }

    func testDragPayloadRoundTripsAndRejectsJunk() {
        let id = UUID()
        XCTAssertEqual(TodoDragPayload.decode(TodoDragPayload.encode(id)), id)
        XCTAssertEqual(TodoDragPayload.decode("  \(TodoDragPayload.encode(id))  "), id, "首尾空白不算差异")
        XCTAssertNil(TodoDragPayload.decode(nil))
        XCTAssertNil(TodoDragPayload.decode(""))
        XCTAssertNil(TodoDragPayload.decode("note:\(id.uuidString)"), "别家的载荷不认")
        XCTAssertNil(TodoDragPayload.decode("todo:not-a-uuid"), "尾巴不是 UUID ⇒ 解不出（不抛错）")
    }

    func testDropKeepsTheOriginalClockAndOnlyMovesTheDay() {
        let due = at(2026, 10, 5, 9)
        let target = at(2026, 10, 9, 0)
        let moved = TodoOccurrence.momentMatching(target, like: due, calendar: calendar)

        XCTAssertEqual(calendar.component(.day, from: moved), 9, "拖到哪一天就是哪一天")
        XCTAssertEqual(calendar.component(.hour, from: moved), 9, "钟点沿用原截止（拖拽只改日子）")
        XCTAssertEqual(TodoOccurrence.momentMatching(target, like: nil, calendar: calendar), target,
                       "原来没有截止 ⇒ 落在目标日零点，不猜一个钟点")
    }

    func testCompletionIsOneRecordSeenByBothPanes() {
        var todo = Todo(title: "做完它", dueAt: at(2026, 10, 7, 9))
        todo.done = true
        todo.completedAt = at(2026, 10, 7, 10)

        let days = TodoCalendar.tasksByDay(
            [todo], cells: monthCells(2026, 10), now: at(2026, 10, 8), calendar: calendar
        )
        let day = dayTask(days, 7)
        XCTAssertEqual(day?.done.map(\.id), [todo.id], "日历读的是同一份 `done`（没有第二套状态）")
        XCTAssertEqual(day?.open.count, 0)
        XCTAssertEqual(TodoPresentation.sections([todo]).first { $0.kind == .completed }?.todos.map(\.id),
                       [todo.id], "清单那一段读到的也是它（同一个值、同一个 id）")
    }

    // MARK: - ③ 清单是唯一事实源（STATE-002）

    func testCalendarCoreHasNoWritePath() throws {
        for file in ["Core/TodoCalendar.swift", "Core/TodoOccurrence.swift", "Core/TodoDragPayload.swift"] {
            let text = try source(file)
            for forbidden in ["NoteLibrary", "NoteDatabase", "upsert", "setDone", "INSERT INTO", "DELETE FROM"] {
                XCTAssertFalse(text.contains(forbidden),
                               "\(file) 里出现 `\(forbidden)` ⇒ 投影层开了一条写路（日历就会另存一份）")
            }
        }
    }

    func testSchemaHasNoCalendarSpecificTable() throws {
        let schema = try source("Plugins/Notes/Sources/NoteStorage/NoteDatabase.swift")
        XCTAssertTrue(schema.contains("CREATE TABLE todo ("), "前提：这段扫的确实是待办那张表")
        let names = schema.components(separatedBy: "CREATE TABLE ").dropFirst()
            .compactMap { chunk -> String? in
                guard let end = chunk.firstIndex(where: { $0 == " " || $0 == "(" }) else { return nil }
                return String(chunk[chunk.startIndex..<end]).lowercased()
            }
        XCTAssertExpectedNoCalendarTable(names)
        XCTAssertTrue(names.contains("todo"), "扫出来的表名里要有 `todo`（否则这条判据在扫空气）")
    }

    private func XCTAssertExpectedNoCalendarTable(_ names: [String], file: StaticString = #filePath, line: UInt = #line) {
        let offenders = names.filter { $0.contains("calendar") || $0.contains("todo_day") || $0.contains("todo_week") }
        XCTAssertTrue(offenders.isEmpty, "日历不该有自己的表（第二份数据就是这么长出来的）：\(offenders)", file: file, line: line)
    }

    func testAppStateKeepsOneTodoArrayAndDerivesTheCalendarFromIt() throws {
        let state = try source("App/AppState.swift")
        XCTAssertEqual(state.components(separatedBy: "@Published var todos: [Todo]").count - 1, 1,
                       "任务只有一份内存态（`todos`）")
        for forbidden in ["@Published var calendarTodos", "@Published var weekTodos", "@Published var dayTodos"] {
            XCTAssertFalse(state.contains(forbidden), "又冒出第二份任务数组：`\(forbidden)`")
        }

        guard let start = state.range(of: "var todoCalendarDays: [Date: TodoDayTasks] {") else {
            return XCTFail("`todoCalendarDays` 不在")
        }
        let body = state[start.lowerBound...].prefix(600)
        XCTAssertTrue(body.contains("TodoCalendar.tasksByDay("), "日历投影必须走 Core 那一个函数")
        XCTAssertTrue(body.contains("todos,"), "喂进去的必须是清单那一份 `todos`（不是另一份）")
    }

    func testSwitchingPaneOrViewDoesNotCopyOrMutateAnything() {
        let state = AppState()
        let todo = Todo(title: "一份数据", dueAt: at(2027, 4, 6, 9))
        state.todos = [todo]
        state.selectTodoCalendarDay(at(2027, 4, 6, 12))

        let beforeIDs = state.todos.map(\.id)
        state.todoCalendarGoToday()
        state.selectTodoCalendarDay(at(2027, 4, 6, 12))
        state.setTodoPane(.calendar)
        state.setTodoCalendarView(.week)
        XCTAssertEqual(state.todos.map(\.id), beforeIDs, "切视图不复制任务")
        XCTAssertEqual(state.todoCalendarDays.count, 1, "周视图里仍是同一条，不出现第二格副本")
        state.setTodoCalendarView(.month)
        state.setTodoPane(.list)
        XCTAssertEqual(state.todos.map(\.id), beforeIDs, "切回清单仍是同一份")
    }

    func testMonthAndWeekProjectionsAgreeOnTheSameDay() {
        let todo = Todo(title: "同一条", dueAt: at(2026, 10, 7, 9))
        let month = TodoCalendar.tasksByDay(
            [todo], cells: monthCells(2026, 10), now: at(2026, 10, 1), calendar: calendar
        )
        let week = TodoCalendar.tasksByDay(
            [todo], cells: TodoCalendar.weekCells(anchor: at(2026, 10, 7, 15), calendar: calendar),
            now: at(2026, 10, 1), calendar: calendar
        )

        XCTAssertEqual(month.flatMap { $0.open.map(\.id) }, [todo.id])
        XCTAssertEqual(week.flatMap { $0.open.map(\.id) }, [todo.id], "同一任务在两档里是同一个 id（不是两份）")
    }
}
