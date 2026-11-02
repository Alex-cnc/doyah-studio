import XCTest
@testable import DoyahCore

/// `FR-NTS-TODO-CALENDAR-001` 的机械证据：**月视图（可切周视图）把任务铺在日期上**
/// （按截止时间；有提醒的日子同时打点），判据四条逐条对上需求书 §3.5：
///
///  ① 月 / 周可切 —— 取值空间与切换器在 `TodoCalendarView`（`TodoCalendarTests` 已判）；
///  ② 任务出现在其截止日；
///  ③ 无截止时间的任务仍在清单可见、不因日历而丢；
///  ④ **带重复规则的任务按发生日铺开，而库里只有一条记录**（不预生成副本），
///     且改一次能说清改的是「这一条」还是「这一串」。
///
/// 本文件只判**投影与那两笔写入的形状**。真鼠标点格子 / 点菜单未点 ⇒ 那一条在证据里记「未验证」。
final class TodoOccurrenceTests: XCTestCase {

    // MARK: - 工具

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-todo-occurrence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    /// 固定时区 / 固定历法：发生日是按**日历日**算的，跟着运行机器的时区跑会让读数飘。
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.locale = Locale(identifier: "zh_CN")
        return value
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private func dayNumbers(_ days: [Date]) -> [Int] {
        days.map { calendar.component(.day, from: $0) }
    }

    private var monthCells: [TodoCalendarCell] {
        TodoCalendar.monthCells(year: 2026, month: 11, calendar: calendar)
    }

    /// 只取**属于本月**的格子（月视图整周补齐会带进相邻月的日子 —— 那些日子也是真日子，
    /// 铺开会在它们上面出现；断言「这个月有哪几天」时把补齐格剔掉，读数才是一次性的）。
    private var inMonthCells: [TodoCalendarCell] {
        monthCells.filter(\.inMonth)
    }

    private func library() -> NoteLibrary {
        NoteLibrary(databaseURL: directory.appendingPathComponent(NoteLibrary.fileName))
    }

    // MARK: - 判据② 任务出现在其截止日

    func testTaskAppearsOnItsDueDay() {
        let todo = Todo(title: "交房租", dueAt: day(2026, 11, 12, 9, 0))
        let days = TodoCalendar.tasksByDay([todo], cells: monthCells, now: day(2026, 11, 1), calendar: calendar)

        XCTAssertEqual(dayNumbers(days.map(\.date)), [12], "一次性任务只在截止日那一格出现")
        XCTAssertEqual(days.first?.open.map(\.id), [todo.id])
        XCTAssertEqual(days.first?.total, 1)
    }

    // MARK: - 判据③ 无截止的任务不因日历而丢

    func testTodoWithoutDueDateStaysOffTheCalendarButVisibleInTheList() {
        let noDue = Todo(title: "随时看的一本书")

        let days = TodoCalendar.tasksByDay([noDue], cells: monthCells, now: day(2026, 11, 1), calendar: calendar)
        XCTAssertTrue(days.isEmpty, "日历不替无截止的任务凭空给一个日子")

        let sections = TodoPresentation.sections([noDue])
        XCTAssertEqual(sections.first { $0.kind == .open }?.todos.map(\.id), [noDue.id],
                       "清单里仍然看得见它（无截止是「没排期」，不是「不存在」）")
    }

    // MARK: - 判据④ 重复规则按发生日铺开

    /// 每周一 / 周三 09:00（锚点 2026-11-02 是周一）：11 月里应有 2、4、9、11、16、18、23、25、30 这九天。
    func testWeeklyRepeatPaintsEveryScheduledDay() {
        let todo = Todo(
            title: "健身",
            dueAt: day(2026, 11, 2, 9, 0),
            repeatRule: TodoRepeat.weekly([1, 3])
        )

        let days = TodoCalendar.tasksByDay([todo], cells: inMonthCells, now: day(2026, 11, 1), calendar: calendar)

        XCTAssertEqual(dayNumbers(days.map(\.date)), [2, 4, 9, 11, 16, 18, 23, 25, 30],
                       "周内取值 (1,3) 从锚点起铺开：每个周一与周三各一格")
        XCTAssertTrue(days.allSatisfy { $0.open.map(\.id) == [todo.id] })
    }

    /// 每 3 天（跨月边界）：锚点 2026-01-28 ⇒ 1/28、1/31、2/3、2/6 …；
    /// **锚点之前的日子不发生**（2 月视图里补进来的 1/26、1/27 不该有它）。
    func testIntervalRepeatPaintsEveryNthDayAndNeverBeforeTheAnchor() {
        let todo = Todo(
            title: "换水",
            dueAt: day(2026, 1, 28, 8, 0),
            repeatRule: TodoRepeat.every(3, .day)
        )
        let cells = TodoCalendar.monthCells(year: 2026, month: 2, calendar: calendar)

        let days = TodoOccurrence.days(todo, in: cells, calendar: calendar)
        let stamps = days.map { calendar.dateComponents([.month, .day], from: $0) }
            .map { ($0.month ?? 0, $0.day ?? 0) }

        XCTAssertEqual(stamps.map { "\($0.0)/\($0.1)" },
                       ["1/28", "1/31", "2/3", "2/6", "2/9", "2/12", "2/15", "2/18", "2/21", "2/24", "2/27"],
                       "锚点 1/28 起每 3 天；锚点之前的 1/26、1/27 不发生（二月视图补齐带进了它们）")
        XCTAssertTrue(cells.contains { !$0.inMonth && calendar.component(.day, from: $0.date) == 26 },
                      "前提：二月视图补齐时确实带进了 1/26")
    }

    /// 周视图与月视图**共用同一个铺法**：同一个任务在两周里数出来的次数必须一致。
    func testMonthAndWeekViewsShareTheSameOccurrenceSet() {
        let todo = Todo(title: "周报", dueAt: day(2026, 11, 2, 18, 0), repeatRule: TodoRepeat.weekly([1]))

        let monthDays = TodoOccurrence.days(todo, in: monthCells, calendar: calendar)
        let weekCellsForSecondWeek = TodoCalendar.weekCells(anchor: day(2026, 11, 11), calendar: calendar)
        let weekDays = TodoOccurrence.days(todo, in: weekCellsForSecondWeek, calendar: calendar)

        XCTAssertEqual(weekDays, monthDays.filter { weekCellsForSecondWeek.map(\.date).contains($0) })
        XCTAssertEqual(dayNumbers(weekDays), [9], "那一周只有一个周一")
    }

    /// **库里只有一条记录**：铺开是投影，不是预生成副本 —— 9 格都是同一个 `Todo`（同一条 `id`）。
    func testPaintingManyDaysKeepsASingleRecordInTheLibrary() async throws {
        let library = library()
        var todo = Todo(title: "健身", dueAt: day(2026, 11, 2, 9, 0), repeatRule: TodoRepeat.weekly([1, 3]))
        todo = try await library.upsert(todo)

        let stored = try await library.todos()
        XCTAssertEqual(stored.count, 1, "库里只有一条记录（铺开不写库）")

        let days = TodoCalendar.tasksByDay(stored, cells: inMonthCells, now: day(2026, 11, 1), calendar: calendar)
        XCTAssertEqual(days.count, 9, "同一份读回铺出 9 天")
        XCTAssertEqual(Set(days.flatMap { $0.open.map(\.id) }), [todo.id], "9 格是同一行（同一条 id）")
        let afterPainting = try await library.todos()
        XCTAssertEqual(afterPainting.count, 1, "铺开之后库里仍然只有一条")
    }

    /// 跳过的那个日子**不发生**（「只改这一条」留下的那一格）。
    func testSkippedOccurrenceDoesNotPaint() {
        var rule = TodoRepeat.weekly([1, 3])!
        rule.skipped = ["2026-11-11"]
        let todo = Todo(title: "健身", dueAt: day(2026, 11, 2, 9, 0), repeatRule: rule)

        let days = TodoCalendar.tasksByDay([todo], cells: inMonthCells, now: day(2026, 11, 1), calendar: calendar)

        XCTAssertEqual(dayNumbers(days.map(\.date)), [2, 4, 9, 16, 18, 23, 25, 30], "11/11 被跳过")
    }

    // MARK: - 判据④ 后半：「改这一条」与「改这一串」

    /// **只改这一天**：那一串补一格跳过（真正落库），另起一条独立记录带着改动。
    func testEditingOneOccurrenceSkipsThatDayAndWritesADetachedRecord() async throws {
        let library = library()
        let series = try await library.upsert(
            Todo(title: "健身", dueAt: day(2026, 11, 2, 9, 0), repeatRule: TodoRepeat.weekly([1, 3]))
        )

        let edit = TodoOccurrenceEditor.reschedule(
            series,
            on: day(2026, 11, 11),
            to: day(2026, 11, 11, 15, 30),
            scope: .thisOccurrence,
            now: day(2026, 11, 5, 10, 0),
            calendar: calendar
        )

        XCTAssertEqual(edit.scope, .thisOccurrence)
        XCTAssertEqual(edit.writes.count, 2, "两笔：那一串 + 新起的那一条")
        XCTAssertEqual(edit.series.repeatRule?.skipped, ["2026-11-11"], "那一串里这一天不再发生")
        let detached = try XCTUnwrap(edit.detached)
        XCTAssertNotEqual(detached.id, series.id, "独立记录是**另一条**")
        XCTAssertNil(detached.repeatRule, "独立记录不重复（只此一次）")
        XCTAssertEqual(detached.dueAt, day(2026, 11, 11, 15, 30), "改动落在那一天他要的时刻上")

        let written = try await library.saveOccurrenceEdit(edit)
        XCTAssertEqual(written.count, 2)
        let stored = try await library.todos()
        XCTAssertEqual(stored.count, 2, "库里两行：那一串 + 独立记录")

        let reloaded = try await library.todos()
        let payload = TodoCalendar.tasksByDay(
            reloaded, cells: inMonthCells, now: day(2026, 11, 5), calendar: calendar
        )
        let day11 = payload.first { calendar.component(.day, from: $0.date) == 11 }
        XCTAssertEqual(day11?.total, 1, "11/11 只剩改过的那一条")
        XCTAssertEqual(day11?.open.first?.id, detached.id, "11/11 上的是独立记录")
        let day4 = payload.first { calendar.component(.day, from: $0.date) == 4 }
        XCTAssertEqual(day4?.open.first?.id, series.id, "其它日子仍然是那一串（同一条记录）")
    }

    /// **改整串**：只写那一条，锚点挪走，所有发生日重算（间隔规则：整串平移）。
    func testEditingTheWholeSeriesMovesEveryOccurrenceAndKeepsOneRow() async throws {
        let library = library()
        let series = try await library.upsert(
            Todo(title: "交房租", dueAt: day(2026, 11, 2, 9, 0), repeatRule: TodoRepeat.every(7, .day))
        )

        let before = TodoCalendar.tasksByDay(
            try await library.todos(), cells: inMonthCells, now: day(2026, 11, 1), calendar: calendar
        )
        XCTAssertEqual(dayNumbers(before.map(\.date)), [2, 9, 16, 23, 30], "改之前：每 7 天从 11/2 起")

        let edit = TodoOccurrenceEditor.reschedule(
            series,
            on: day(2026, 11, 9),
            to: day(2026, 11, 4, 9, 0),
            scope: .thisSeries,
            now: day(2026, 11, 5, 10, 0),
            calendar: calendar
        )

        XCTAssertEqual(edit.writes.count, 1, "整串 = 那一行本身")
        XCTAssertNil(edit.detached)
        XCTAssertTrue(edit.isSeriesWide)

        _ = try await library.saveOccurrenceEdit(edit)
        let storedAfterSeriesEdit = try await library.todos()
        XCTAssertEqual(storedAfterSeriesEdit.count, 1, "整串改完仍然只有一行")

        let after = TodoCalendar.tasksByDay(
            storedAfterSeriesEdit, cells: inMonthCells, now: day(2026, 11, 5), calendar: calendar
        )
        XCTAssertEqual(dayNumbers(after.map(\.date)), [4, 11, 18, 25],
                       "整串平移：锚点 11/2 → 11/4，之后的每个发生日跟着挪 2 天")
    }

    /// 周内规则（`weekly`）的「改整串」改的是**锚点与钟点**，周内取值不动（那是规则本身）：
    /// 锚点挪到 11/3 之后，11/2 那次落在锚点之前 ⇒ 不再发生，其余周一 / 周三照旧。
    func testEditingAWeeklySeriesKeepsTheWeekdaySetAndOnlyMovesTheAnchor() {
        let series = Todo(title: "健身", dueAt: day(2026, 11, 2, 9, 0), repeatRule: TodoRepeat.weekly([1, 3]))

        let edit = TodoOccurrenceEditor.reschedule(
            series,
            on: day(2026, 11, 11),
            to: day(2026, 11, 3, 9, 0),
            scope: .thisSeries,
            now: day(2026, 11, 5, 10, 0),
            calendar: calendar
        )

        XCTAssertEqual(edit.series.repeatRule?.weekdays, [1, 3], "周内取值不随锚点变")
        let days = TodoCalendar.tasksByDay(
            edit.writes, cells: inMonthCells, now: day(2026, 11, 1), calendar: calendar
        )
        XCTAssertEqual(dayNumbers(days.map(\.date)), [4, 9, 11, 16, 18, 23, 25, 30],
                       "11/2 落在新锚点之前 ⇒ 只少了那一天")
    }

    /// 那一天**不是**它的一次发生日 ⇒ 「只改这一条」不成立，如实退成整串（不猜、不凭空造一条）。
    func testAskingForASingleOccurrenceOnANonOccurrenceDayFallsBackToTheSeries() {
        let series = Todo(title: "健身", dueAt: day(2026, 11, 2, 9, 0), repeatRule: TodoRepeat.weekly([1, 3]))

        let edit = TodoOccurrenceEditor.reschedule(
            series,
            on: day(2026, 11, 5),
            to: day(2026, 11, 5, 20, 0),
            scope: .thisOccurrence,
            now: day(2026, 11, 1, 10, 0),
            calendar: calendar
        )

        XCTAssertEqual(edit.scope, .thisSeries)
        XCTAssertEqual(edit.writes.count, 1)
        XCTAssertTrue(edit.series.repeatRule?.skipped.isEmpty ?? false, "不留下一个凭空的跳过日")
    }

    /// 两档取值空间与归一：认不出「当没给」= 整串（与 `TodoPriority` 同一条口径）。
    func testScopeChoiceHasTwoValuesAndNormalizesUnknownInput() {
        XCTAssertEqual(TodoRepeatEditScope.allCases, [.thisOccurrence, .thisSeries])
        XCTAssertEqual(TodoRepeatEditScope.initial, .thisSeries)
        XCTAssertEqual(TodoRepeatEditScope(raw: " thisSeries "), .thisSeries)
        XCTAssertEqual(TodoRepeatEditScope(raw: "whatever"), .thisSeries)
    }

    // MARK: - 存储形状（跳过表是后加的一格，旧载荷不变）

    func testSkippedDatesRoundTripThroughStorageAndExchange() throws {
        var rule = TodoRepeat.weekly([1, 3])!
        rule.skipped = ["2026-11-11"]
        let text = rule.storageText

        XCTAssertFalse(text.contains("weekdays\":[3,1]"), "周内取值仍是升序（归一只有一处）")
        XCTAssertEqual(TodoRepeat.decode(storageText: text)?.skipped, ["2026-11-11"])

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(TodoRepeat.self, from: data)
        XCTAssertEqual(decoded, rule.normalized(), "交换面与落库文本同一组键")
    }

    /// **没有跳过时字节不变**（旧载荷逐字节相同 ⇒ 跨端对拍不受这一格影响）。
    func testPayloadWithoutSkipsKeepsTheOldBytes() {
        let rule = TodoRepeat.weekly([1, 3])!
        XCTAssertEqual(
            rule.storageText,
            "{\"intervalCount\":1,\"intervalUnit\":\"day\",\"rule\":\"weekly\",\"weekdays\":[1,3]}"
        )
        let legacy = "{\"rule\":\"weekly\",\"intervalCount\":1,\"intervalUnit\":\"day\",\"weekdays\":[1,3]}"
        XCTAssertEqual(TodoRepeat.decode(storageText: legacy)?.skipped, [], "旧载荷缺这一格 ⇒ 空跳过表")
    }

    /// 坏日子在归一那一步丢掉（一格坏日子不该让整条任务读不进来）。
    func testBadSkipKeysAreDroppedOnNormalization() {
        var rule = TodoRepeat.weekly([1])!
        rule.skipped = ["2026-11-11", "2026-02-30", "not a date", " 2026-11-04 ", "2026-11-11"]
        XCTAssertEqual(rule.normalized()?.skipped, ["2026-11-04", "2026-11-11"])
    }

    /// 日历上点第 N 次去改期，改期框预填的是**那天 + 原来的钟点**（不是当天零点）。
    func testMomentMatchingKeepsTheTimeOfDay() {
        let moment = TodoOccurrence.momentMatching(
            day(2026, 11, 11),
            like: day(2026, 11, 2, 9, 0),
            calendar: calendar
        )
        XCTAssertEqual(moment, day(2026, 11, 11, 9, 0))
        XCTAssertEqual(
            TodoOccurrence.momentMatching(day(2026, 11, 11), like: nil, calendar: calendar),
            day(2026, 11, 11, 0, 0)
        )
    }

    // MARK: - 唯一事实源（这一层也没有写路）

    /// 铺开那一层**不碰库**：它拿到的就是清单那一份 `[Todo]`，输出是投影。
    /// 判在**代码**上（注释先剥掉）：注释里提到 `upsert` / `NoteLibrary` 是在说明「写在哪一条路上」。
    func testOccurrenceLayerHasNoWritePath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let text = try String(
            contentsOf: root.appendingPathComponent("Core/TodoOccurrence.swift"), encoding: .utf8
        )
        for forbidden in ["NoteDatabase", "NoteLibrary", "sqlite", "upsert", "deleteTodo", "setDone", "INSERT", "UPDATE"] {
            XCTAssertFalse(Self.strippingComments(text).contains(forbidden),
                           "`\(forbidden)` 出现在铺开那一层的代码里 —— 日历是视图，不许有第二条写路")
        }
    }

    /// 「只改这一条」那两笔**只走一条批量写口**（一个事务）：`saveOccurrenceEdit` 里 `upsert(` 只出现 **1 次**。
    ///
    /// 这是结构判据而不是原子性证明（SQLite 那边没有能稳定注入的失败点）：它挡的是最容易发生的那种退化 ——
    /// 「先写这一条、再写那一条」，两步各自都成功过，日志里看不出问题，而用户那边少了一次任务。
    func testOccurrenceEditIsWrittenThroughASingleBatchCall() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Plugins/Notes/Sources/NoteStorage/NoteLibrary.swift"),
            encoding: .utf8
        )
        let marker = "func saveOccurrenceEdit("
        let start = try XCTUnwrap(source.range(of: marker)?.lowerBound)
        let rest = source[start...]
        let end = rest.range(of: "\n    public func ")?.lowerBound ?? rest.endIndex
        let body = Self.strippingComments(String(rest[..<end]))

        let call = try XCTUnwrap(body.range(of: "upsert("))
        let argument = body[call.upperBound...].prefix { $0 != ")" }
        XCTAssertEqual(body.components(separatedBy: "upsert(").count - 1, 1,
                       "两笔必须走同一个批量写口（一个事务）—— 写两次就是「半条也能落库」")
        XCTAssertEqual(String(argument), "rows",
                       "那一次写的实参必须是**整批**（`upsert(rows)`）—— 逐个写（`upsert(row)`）就不是一个事务")
    }

    private static func strippingComments(_ text: String) -> String {
        var out: [String] = []
        var inBlock = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inBlock {
                if let end = trimmed.range(of: "*/") {
                    inBlock = false
                    out.append(String(trimmed[end.upperBound...]))
                }
                continue
            }
            if trimmed.hasPrefix("//") { continue }
            if trimmed.hasPrefix("/*") {
                if let end = trimmed.range(of: "*/") {
                    out.append(String(trimmed[end.upperBound...]))
                } else {
                    inBlock = true
                }
                continue
            }
            out.append(String(line))
        }
        return out.joined(separator: "\n")
    }
}
