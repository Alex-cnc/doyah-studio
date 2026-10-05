import XCTest
@testable import DoyahCore

/// 队列 `L-100` 的 **Core 半第二片**（待办日历）的判据：格子 / 日期算术 / 把任务铺在日期上。
///
/// 为什么这些值得单测：
///  · 「哪一格是哪一天」是**跨端口径**（与对侧 `android/core/.../TodoCalendar.kt` 同一套）——
///    算错一次就是「同一份数据在两个端上落在不同的日子」，而这种差异**单端永远自洽**；
///  · 闰年 2 月 / 补齐整周 / 跨零点 / 跨年只有构造时刻才钉得住；
///  · 「无截止的任务不落任何一天」「日历不另存任务」是 `FR-NOTE-39` 的**唯一事实源**约束，
///    写不对不会崩，只会悄悄多出第二份数据。
final class TodoCalendarTests: XCTestCase {

    // MARK: - 工具

    /// 固定日历：公历 + UTC —— 判据不受本机时区与地区影响（跨零点那类用例只能靠固定时区钉）。
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "UTC")!
        value.locale = Locale(identifier: "en_US_POSIX")
        return value
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private func todo(_ title: String, due: Date? = nil, done: Bool = false) -> Todo {
        Todo(title: title, dueAt: due, done: done)
    }

    private func ymd(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private func monthCells(_ year: Int, _ month: Int) -> [TodoCalendarCell] {
        TodoCalendar.monthCells(year: year, month: month, calendar: calendar)
    }

    // MARK: - 月视图的格子

    /// 2026 年 10 月：1 日是周四 ⇒ 第一格 = 9 月 28 日（周一），整月 35 格（5 周），
    /// 最后补到 11 月 1 日。
    func testMonthCellsPadWholeWeeksStartingMonday() {
        let cells = monthCells(2026, 10)

        XCTAssertEqual(cells.count, 35, "3 + 31 = 34 天 ⇒ 补齐到 5 周（35 格）")
        XCTAssertEqual(ymd(cells[0].date), "2026-09-28", "第一格 = 当月 1 日所在周的周一")
        XCTAssertEqual(cells[0].weekday, TodoCalendar.firstWeekdayISO)
        XCTAssertEqual(cells[0].inMonth, false, "补进来的上月日子不算本月")
        XCTAssertEqual(cells[3].dayOfMonth, 1)
        XCTAssertEqual(ymd(cells[3].date), "2026-10-01", "第 4 格才是本月 1 日（前面补 3 天）")
        XCTAssertTrue(cells[3].inMonth)
        XCTAssertEqual(ymd(cells[34].date), "2026-11-01", "最后一格补到下月 1 日")
        XCTAssertEqual(cells[34].inMonth, false)
        XCTAssertEqual(cells.filter(\.inMonth).count, 31, "本月 31 天一天不少")
        XCTAssertEqual(cells.map(\.weekday), (0..<35).map { $0 % 7 + 1 }, "整列从周一到周日循环")
    }

    /// 整周补齐是**对每个月都成立**的不变量（界面据此铺满格子，不必自己补空格）。
    func testMonthCellsAlwaysWholeWeeksAndCoverWholeMonth() {
        for year in [2024, 2025, 2026, 2027] {
            for month in 1...12 {
                let cells = monthCells(year, month)
                let days = TodoCalendar.daysInMonth(year: year, month: month, calendar: calendar)
                XCTAssertEqual(cells.count % TodoCalendar.columns, 0, "\(year)-\(month) 不是整周")
                XCTAssertGreaterThanOrEqual(cells.count, days, "\(year)-\(month) 格子比天数还少")
                XCTAssertEqual(cells.filter(\.inMonth).count, days, "\(year)-\(month) 本月天数对不上")
                XCTAssertEqual(cells.first?.weekday, TodoCalendar.firstWeekdayISO, "\(year)-\(month) 第一格不是周一")
                XCTAssertEqual(cells.map(\.weekday), (0..<cells.count).map { $0 % 7 + 1 })
            }
        }
    }

    /// 脏值回空（**不抛错**）：界面收到空就显示空视图，不崩、不猜。
    func testMonthCellsRejectBadYearOrMonth() {
        XCTAssertTrue(monthCells(2026, 0).isEmpty)
        XCTAssertTrue(monthCells(2026, 13).isEmpty)
        XCTAssertTrue(monthCells(0, 10).isEmpty)
        XCTAssertTrue(TodoCalendar.monthCells(year: 2026, month: 10, calendar: calendar).isEmpty == false)
    }

    func testDaysInMonthHandlesLeapYears() {
        XCTAssertEqual(TodoCalendar.daysInMonth(year: 2024, month: 2, calendar: calendar), 29)
        XCTAssertEqual(TodoCalendar.daysInMonth(year: 2026, month: 2, calendar: calendar), 28)
        XCTAssertEqual(TodoCalendar.daysInMonth(year: 2000, month: 2, calendar: calendar), 29, "整百年能被 400 整除 ⇒ 闰年")
        XCTAssertEqual(TodoCalendar.daysInMonth(year: 1900, month: 2, calendar: calendar), 28, "整百年不能被 400 整除 ⇒ 平年")
        XCTAssertEqual(TodoCalendar.daysInMonth(year: 2026, month: 13, calendar: calendar), 0)
    }

    func testFirstAndLastDate() {
        XCTAssertEqual(ymd(TodoCalendar.firstDate(year: 2026, month: 10, calendar: calendar)!), "2026-10-01")
        XCTAssertEqual(ymd(TodoCalendar.lastDate(year: 2026, month: 10, calendar: calendar)!), "2026-10-31")
        XCTAssertEqual(ymd(TodoCalendar.lastDate(year: 2024, month: 2, calendar: calendar)!), "2024-02-29")
        XCTAssertNil(TodoCalendar.firstDate(year: 2026, month: 0, calendar: calendar))
        XCTAssertNil(TodoCalendar.lastDate(year: 2026, month: 13, calendar: calendar))
    }

    // MARK: - 周视图的格子

    func testWeekCellsStartOnMonday() {
        // 2026-10-07 是周三 ⇒ 这一周从 10-05（周一）到 10-11（周日）。
        let cells = TodoCalendar.weekCells(anchor: at(2026, 10, 7, 15, 30), calendar: calendar)

        XCTAssertEqual(cells.count, TodoCalendar.columns)
        XCTAssertEqual(ymd(cells[0].date), "2026-10-05")
        XCTAssertEqual(ymd(cells[6].date), "2026-10-11")
        XCTAssertEqual(cells.map(\.weekday), Array(1...7))
        XCTAssertTrue(cells.allSatisfy(\.inMonth), "周视图不涉及「属不属于本月」")
        XCTAssertEqual(cells.map(\.dayOfMonth), [5, 6, 7, 8, 9, 10, 11])
    }

    func testWeekCellsAnchorOnMondayIsItself() {
        let cells = TodoCalendar.weekCells(anchor: at(2026, 10, 5, 23, 59), calendar: calendar)

        XCTAssertEqual(ymd(cells[0].date), "2026-10-05")
        XCTAssertEqual(cells.map(\.weekday), Array(1...7))
    }

    /// 跨月 / 跨年那一周要**两边都补**（周视图不许在月边界截断）。
    func testWeekCellsCrossMonthAndYearBoundaries() {
        let crossing = TodoCalendar.weekCells(anchor: at(2027, 1, 1, 9), calendar: calendar)
        XCTAssertEqual(ymd(crossing[0].date), "2026-12-28", "2027-01-01 是周五 ⇒ 这一周从 2026-12-28 起")
        XCTAssertEqual(ymd(crossing[6].date), "2027-01-03")
    }

    // MARK: - 日期算术

    func testShiftMonthCrossesYearBothWays() {
        XCTAssertEqual(TodoCalendar.shiftMonth(year: 2026, month: 12, delta: 1)?.year, 2027)
        XCTAssertEqual(TodoCalendar.shiftMonth(year: 2026, month: 12, delta: 1)?.month, 1)
        XCTAssertEqual(TodoCalendar.shiftMonth(year: 2026, month: 1, delta: -1)?.year, 2025)
        XCTAssertEqual(TodoCalendar.shiftMonth(year: 2026, month: 1, delta: -1)?.month, 12)
        XCTAssertEqual(TodoCalendar.shiftMonth(year: 2026, month: 10, delta: 14)?.month, 12)
        XCTAssertNil(TodoCalendar.shiftMonth(year: 2026, month: 0, delta: 1))
        XCTAssertNil(TodoCalendar.shiftMonth(year: 2026, month: 13, delta: 1))
    }

    func testShiftDaysCrossesMonthAndYear() {
        XCTAssertEqual(ymd(TodoCalendar.shift(days: 1, from: at(2026, 10, 31, 8), calendar: calendar)!), "2026-11-01")
        XCTAssertEqual(ymd(TodoCalendar.shift(days: -1, from: at(2027, 1, 1, 8), calendar: calendar)!), "2026-12-31")
        XCTAssertEqual(ymd(TodoCalendar.shift(days: 0, from: at(2026, 10, 5, 23, 59), calendar: calendar)!), "2026-10-05",
                       "平移结果归到当天零点（同一天的不同时刻是同一格）")
    }

    // MARK: - 把任务铺在日期上

    /// 参照时刻：2026-10-04 15:00（与固定日历同一条时区）。
    private var now: Date { at(2026, 10, 4, 15) }

    private func project(_ todos: [Todo], _ cells: [TodoCalendarCell]) -> [TodoDayTasks] {
        TodoCalendar.tasksByDay(todos, cells: cells, now: now, calendar: calendar)
    }

    /// **无截止的任务不落在任何一天** —— 日历不凭空给个日子（它们只在清单的「无截止」档里）。
    func testTasksByDayIgnoresTodosWithoutDueDate() {
        let noDue = todo("没截止")
        let due = todo("有截止", due: at(2026, 10, 5, 9))
        let result = project([noDue, due], monthCells(2026, 10))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(ymd(result[0].date), "2026-10-05")
        XCTAssertEqual(result[0].open.map(\.id), [due.id])
        XCTAssertFalse(result.flatMap { $0.open + $0.done }.contains(noDue), "无截止的任务一条都不许出现")
    }

    /// 只落进**给定格子**里（窗口外的任务不出现；补齐整周补进来的相邻月日子照样铺）。
    func testTasksByDayOnlyFillsGivenCells() {
        let outer = todo("下个月", due: at(2026, 11, 20, 9))
        let paddedLead = todo("上月补格", due: at(2026, 9, 28, 9))
        let paddedTrail = todo("下月补格", due: at(2026, 11, 1, 9))
        let result = project([outer, paddedLead, paddedTrail], monthCells(2026, 10))

        XCTAssertEqual(result.map { ymd($0.date) }, ["2026-09-28", "2026-11-01"],
                       "两个补齐格都在，11-20 不在（补齐整周补进来的日子照样铺）")
        XCTAssertFalse(result.flatMap { $0.open }.contains(outer), "窗口外的任务不进这个月的格子")
    }

    /// 两区（未完成 / 已完成）走清单那一套口径，**段内保持传入顺序**（排序属契约半）。
    func testTasksByDaySplitsSectionsKeepingIncomingOrder() {
        let a = todo("甲", due: at(2026, 10, 5, 9))
        let b = todo("乙", due: at(2026, 10, 5, 18), done: true)
        let c = todo("丙", due: at(2026, 10, 5, 20))
        let d = todo("丁", due: at(2026, 10, 5, 21), done: true)
        let result = project([a, b, c, d], monthCells(2026, 10))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].open.map(\.id), [a.id, c.id])
        XCTAssertEqual(result[0].done.map(\.id), [b.id, d.id])
        XCTAssertEqual(result[0].total, 4)
    }

    /// 逾期**只数未完成的**，且「今天早上那个点」也算逾期（与清单那一屏同一条判据）。
    func testTasksByDayCountsOnlyOpenOverdue() {
        let morning = todo("今晨还没做", due: at(2026, 10, 4, 9))
        let evening = todo("今晚", due: at(2026, 10, 4, 23))
        let doneYesterday = todo("昨天做完了", due: at(2026, 10, 3, 9), done: true)
        let openYesterday = todo("昨天没做完", due: at(2026, 10, 3, 9))
        let result = project([morning, evening, doneYesterday, openYesterday], monthCells(2026, 10))

        XCTAssertEqual(result.map { ymd($0.date) }, ["2026-10-03", "2026-10-04"])
        XCTAssertEqual(result[0].overdue, 1, "昨天那条未完成 ⇒ 逾期；已完成的那条不算")
        // **契约 §3.13 第四条（第 191 轮跟版）**：逾期 = 未完成 且 **早于今天零点** ——
        // 今晨 09:00 与今晚 23:00 都落在「今天」那一带，**都不算逾期**
        // （旧口径 `dueAt < now` 会把今晨那条算成逾期，与对侧 `TodoDue.isOverdue` 不是同一个答案）。
        XCTAssertEqual(result[1].overdue, 0, "今天之内的时刻都不算逾期（边界 = 今天零点，严格小于）")
        XCTAssertEqual(result[1].open.map(\.id), [morning.id, evening.id], "两区仍按完成态分，与带无关")
    }

    /// 空的天不出现、结果按日升序（界面据此决定画不画点）。
    func testTasksByDayOmitsEmptyDaysAndKeepsDayOrder() {
        let a = todo("甲", due: at(2026, 10, 20, 9))
        let b = todo("乙", due: at(2026, 10, 2, 9))
        let c = todo("丙", due: at(2026, 10, 2, 20))
        let result = project([a, b, c], monthCells(2026, 10))

        XCTAssertEqual(result.map { ymd($0.date) }, ["2026-10-02", "2026-10-20"])
        XCTAssertEqual(result[0].total, 2)
    }

    /// 月 / 周两档**共用同一个铺法**：同一天在两档里必须是同一个结果
    /// （各写一遍就会出现「月视图有、周视图没有」，而两侧各自的用例都会是绿的）。
    func testMonthAndWeekShareTheSameProjection() {
        let open = todo("同一条", due: at(2026, 10, 7, 9))
        let done = todo("另一条", due: at(2026, 10, 7, 18), done: true)
        let todos = [open, done]
        let month = project(todos, monthCells(2026, 10))
        let week = project(todos, TodoCalendar.weekCells(anchor: at(2026, 10, 7, 9), calendar: calendar))

        XCTAssertEqual(month.first { ymd($0.date) == "2026-10-07" },
                       week.first { ymd($0.date) == "2026-10-07" })
    }

    /// 投影是**纯函数**：同样输入两次同形，且一个字节都不动输入（日历是视图，不是第二个写入面）。
    func testProjectionIsPureAndDoesNotMutateInputs() {
        let todos = [todo("甲", due: at(2026, 10, 5, 9)), todo("乙", done: true)]
        let before = todos
        let first = project(todos, monthCells(2026, 10))
        let second = project(todos, monthCells(2026, 10))

        XCTAssertEqual(first, second)
        XCTAssertEqual(todos, before)
    }

    func testTasksByDayWithNoCellsIsEmpty() {
        let due = todo("甲", due: at(2026, 10, 5, 9))
        XCTAssertTrue(TodoCalendar.tasksByDay([due], cells: [], now: now, calendar: calendar).isEmpty)
    }

    // MARK: - 两档视图的取值空间

    func testCalendarViewNormalizeDefaultsToMonth() {
        XCTAssertEqual(TodoCalendarView.allCases, [.month, .week], "两档只落这一处（界面别处不许再抄一份）")
        XCTAssertEqual(TodoCalendarView.initial, .month,
                       "默认档 = 月视图（第 187 轮改名 `defaultView` → `initial`：那个名字被「工作区用哪种视图打开」占着）")
        XCTAssertEqual(TodoCalendarView(raw: "week").rawValue, "week")
        XCTAssertEqual(TodoCalendarView(raw: " WEEK ").rawValue, "week", "大小写与首尾空白不算差异")
        XCTAssertEqual(TodoCalendarView(raw: "季度"), .month, "认不出的档位「当没给」= 月视图")
        XCTAssertEqual(TodoCalendarView(raw: ""), .month)
    }

    func testCalendarViewNamesAreLocalizedInBothLanguages() {
        for view in TodoCalendarView.allCases {
            let chinese = LocalizedStrings.table[view.key]?[.simplifiedChinese]
            let english = LocalizedStrings.table[view.key]?[.english]
            XCTAssertNotNil(chinese, "\(view) 缺中文模板")
            XCTAssertNotNil(english, "\(view) 缺英文模板")
            XCTAssertFalse((chinese ?? "").isEmpty, "\(view) 的中文模板是空的")
            XCTAssertFalse((english ?? "").isEmpty, "\(view) 的英文模板是空的")
            XCTAssertNotEqual(chinese, english, "\(view) 中英同一句（漏了一条）")
        }
        XCTAssertNotEqual(TodoCalendarView.month.key, TodoCalendarView.week.key, "两档不许共用一个键")
    }

    // MARK: - 唯一事实源（`FR-NOTE-39`：日历不另存任务）

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// 日历那一层**没有写路**：不碰库、不碰写口 —— 它的输入就是清单那一份读回。
    ///
    /// 判在**代码**上（注释先剥掉）：文档里提到 `NoteLibrary.todos()` 是在说明「输入从哪来」，
    /// 那不属于写路；判据要挡的是**真的去写**。
    func testCalendarLayerHasNoWritePath() throws {
        let text = try source("Core/TodoCalendar.swift")
        let code = Self.strippingComments(text)

        for forbidden in ["NoteDatabase", "NoteLibrary", "sqlite", "upsert", "deleteTodo", "setDone", "INSERT", "UPDATE"] {
            XCTAssertFalse(code.contains(forbidden),
                           "`\(forbidden)` 出现在日历那一层的代码里 —— 日历是视图，不许有第二条写路")
        }
    }

    /// 剥掉行注释与块注释（只留代码）：判据要判的是写路，不是注释里的名词。
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

    /// 库里**没有日历专属表**：任务只有 `todo` / `todo_tag` 两张表，日历读的是它们。
    func testStoreHasNoCalendarTable() throws {
        let text = try source("Core/NoteStorage/NoteDatabase.swift")

        XCTAssertTrue(text.contains("CREATE TABLE todo ("), "清单的表还在（日历读的就是它）")
        XCTAssertFalse(text.contains("CREATE TABLE calendar"), "不许为日历另存一份任务")
        XCTAssertFalse(text.contains("CREATE TABLE todo_calendar"), "不许为日历另存一份任务")
    }

    // MARK: - 表头与格子的列序同源（界面半第二片）

    /// 表头七列：条数 = 格子的列数（各写一个 7 就是错位的起点）、列序从 `firstWeekdayISO` 起、键不重复。
    func testWeekdayHeaderMatchesGridColumns() {
        let keys = TodoCalendar.weekdayHeaderKeys
        let order = TodoCalendar.weekdayOrder

        XCTAssertEqual(keys.count, TodoCalendar.columns, "表头列数必须等于格子列数（同一个 `columns`）")
        XCTAssertEqual(order.count, TodoCalendar.columns)
        XCTAssertEqual(order.first, TodoCalendar.firstWeekdayISO, "第一列 = 一周的第一天（ISO 周一）")
        XCTAssertEqual(Set(keys).count, keys.count, "七列各是各的名字（重复 = 有两列同名）")
    }

    /// **表头与格子的列序真的对得上**：格子的星期序列按 `weekdayOrder` 轮回。
    ///
    /// 这一条抓的是「表头写着周一、第一列其实是周日」那类错位 —— 两处各自排一遍时，
    /// 界面看上去只是「日期差一天」，单跑任何一侧都自洽。
    func testGridWeekdayCyclesInHeaderOrder() {
        let order = TodoCalendar.weekdayOrder
        for cells in [monthCells(2026, 10), TodoCalendar.weekCells(anchor: at(2026, 10, 4), calendar: calendar)] {
            XCTAssertFalse(cells.isEmpty)
            for (index, cell) in cells.enumerated() {
                XCTAssertEqual(cell.weekday, order[index % order.count],
                               "第 \(index) 格的星期与表头第 \(index % order.count) 列不是同一个 —— 表头与格子错位了")
            }
        }
    }

    // MARK: - 中栏两档（清单 / 日历）

    /// `TodoPane` 归一：认不出「当没给」（大小写与首尾空白不算差异）、默认档 = 清单。
    func testPaneNormalizesUnknownValue() {
        XCTAssertEqual(TodoPane.allCases.count, 2, "中栏只有两档")
        XCTAssertEqual(TodoPane.defaultPane, .list)
        XCTAssertEqual(TodoPane(raw: "  Calendar "), .calendar)
        XCTAssertEqual(TodoPane(raw: "WEEK"), .list, "认不出的档位当没给（周是日历那一档里的档位，不是中栏档）")
    }

    /// 两张切换器的键**不共用**：中栏那两档（清单 / 日历）与日历那两档（月 / 周）各是各的名字。
    func testPaneAndCalendarViewDoNotShareKeys() {
        let panes = TodoPane.allCases.map(\.key)
        let views = TodoCalendarView.allCases.map(\.key)
        XCTAssertTrue(panes.allSatisfy { !views.contains($0) },
                      "两张切换器显示成了同一套名字（清单/日历 与 月/周 必须分得开）")
    }

    /// 界面那一层**不算日期**：日历的界面只画格子，日期算术一律回 Core
    /// （界面自己再写一遍 `date(byAdding:)` 就是第二套算术）。
    func testCalendarViewKeepsDateArithmeticInCore() throws {
        let code = Self.strippingComments(try source("App/Views/TodoCalendarView.swift"))

        XCTAssertFalse(code.contains("date(byAdding:"), "界面不许自己算日期")
        for hardcoded in ["周一", "周日", "Monday", "Sunday"] {
            XCTAssertFalse(code.contains(hardcoded), "表头名字只能来自语言表：\(hardcoded)")
        }
    }
}
