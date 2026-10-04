import Foundation

/// 待办日历的两档视图（队列 `L-100` 的「日历」界面 / 需求条文 `FR-NOTE-38`，任务 `T97`）。
///
/// 取值空间只落这一处（与 `TodoDueState` / `TodoPriority` 同族）：界面做切换器时遍历 `all`；
/// 认不出的取值「当没给」= `.month`（进来先看整月）—— 与对侧 `android/core/.../TodoCalendar.kt`
/// 的 `TodoCalendarView.normalize` **同口径**（引用，不复制代码）。
public enum TodoCalendarView: String, CaseIterable, Sendable {

    /// 月视图。
    case month
    /// 周视图。
    case week

    /// 默认档 = 月视图。
    public static var defaultView: TodoCalendarView { .month }

    /// 归一：认不出的档位「当没给」（大小写与首尾空白不算差异）。
    public init(raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = TodoCalendarView(rawValue: value) ?? .month
    }

    /// 这一档在语言表里的名字（切换器的唯一出处 —— 两处各写一遍迟早出现「同一档两个名字」）。
    public var key: LKey {
        switch self {
        case .month: return .todoCalendarMonth
        case .week: return .todoCalendarWeek
        }
    }
}

/// 月 / 周视图里的**一格**。
///
/// 格子的身份 = **当天零点**（`Date`）：与 `Note.createdAt` / `Todo.dueAt` 同口径 —— 本侧 Core 里
/// 日期一律是 `Date`（`YYYY-MM-DD` 串只出现在跨端交换面）。
public struct TodoCalendarCell: Equatable, Sendable {

    /// 当天零点（本地日历意义上的那一天）。
    public let date: Date
    /// 当月的第几日（1~31）。
    public let dayOfMonth: Int
    /// ISO 星期（**1 = 周一 … 7 = 周日**）。
    public let weekday: Int
    /// 是否属于本月（补齐整周时补进来的相邻月日子为 `false`，界面据此弱化显示）。
    public let inMonth: Bool

    public init(date: Date, dayOfMonth: Int, weekday: Int, inMonth: Bool) {
        self.date = date
        self.dayOfMonth = dayOfMonth
        self.weekday = weekday
        self.inMonth = inMonth
    }
}

/// **某一天的任务**（`FR-NOTE-38`「把任务铺在日期上」的产物）。
///
/// 一天的两区（未完成 / 已完成）与清单那一屏同一套分区口径（`TodoPresentation.sections`），
/// 因此「选中某天」看到的列表与清单页是**同一个顺序**；`overdue` 是当天**逾期未完成**的条数
/// （格子上的点用它画告警色）—— 逾期判定仍只有 `TodoPresentation.dueState` 一处（参照时刻由调用方传）。
///
/// 只有**有任务的天**会出现在投影结果里（空的天不出现：界面据此决定画不画点）。
public struct TodoDayTasks: Equatable, Sendable {

    /// 当天零点。
    public let date: Date
    /// 当天未完成（段内保持传入顺序）。
    public let open: [Todo]
    /// 当天已完成（同一套口径）。
    public let done: [Todo]
    /// 当天**逾期未完成**的条数（`> 0` ⇒ 格子上画告警色的点）。
    public let overdue: Int

    public init(date: Date, open: [Todo], done: [Todo], overdue: Int) {
        self.date = date
        self.open = open
        self.done = done
        self.overdue = overdue
    }

    /// 当天任务总数（格子上点数上限用）。
    public var total: Int { open.count + done.count }
}

/// 日历的**日期算术与投影**（`FR-NOTE-38`；队列 `L-100` 的 **Core 半第二片**）。
///
/// 为什么这块单独在 Core 里（与 `TodoPresentation` 同一条理由）：
///  ① 「哪一格是哪一天 / 哪些天有任务」是**投影**，把它画出来才是界面 —— 投影各端各写一遍就会出现
///     「同一个任务在月视图有、周视图没有」，而两侧各自的用例都会是绿的；
///  ② 日期算术（闰年 2 月 / 跨零点 / 跨年 / 补齐整周）只能靠构造时刻才钉得住。
///
/// 四条口径（**与对侧 `android/core/.../TodoCalendar.kt` 同口径**：引用，不复制代码）：
///  ① **不读系统时钟**：参照时刻（`now`）与日历（`calendar`）一律由调用方传；
///  ② **一周从周一开始**（`firstWeekdayISO` = 1，ISO 编号 1 = 周一 … 7 = 周日）：月视图第一格 =
///     当月 1 日所在周的周一、**整周补齐**（格数是 `columns` = 7 的整数倍），前后补上相邻月的日子
///     （`inMonth = false`）—— 界面不必自己补空格子；周视图恰好 `columns` 格；
///  ③ **唯一事实源**：日历**不另存任务** —— 这里的输入就是清单那一份 `[Todo]`
///     （`NoteLibrary.todos()` 的读回），本文件的函数**没有任何写路**（判据在本文件同轮的族里：
///     本文件不出现库 / 写口标识，库里也没有日历专属表）；
///  ④ **脏值不抛错**：坏的年 / 月回空（界面收到空即显示空视图，不崩、不猜）。
public enum TodoCalendar {

    /// 一周的天数（= 月 / 周视图的列数；界面表头长度必须取这个值，别各写一个 7）。
    public static let columns = 7

    /// 一周的第一天：ISO 口径 **1 = 周一**（与 `TodoCalendarCell.weekday` 同一套编号）。
    public static let firstWeekdayISO = 1

    // MARK: - 格子

    /// 月视图的格子序列（**整周补齐**）：从当月 1 日所在周的周一起，排到 `columns` 的整数倍。
    /// 坏的年 / 月回空列表。
    public static func monthCells(year: Int, month: Int, calendar: Calendar) -> [TodoCalendarCell] {
        let days = daysInMonth(year: year, month: month, calendar: calendar)
        guard days > 0, let first = day(year: year, month: month, day: 1, calendar: calendar) else {
            return []
        }
        let lead = (isoWeekday(of: first, calendar: calendar) - firstWeekdayISO + columns) % columns
        let total = ((lead + days) + columns - 1) / columns * columns
        guard let start = calendar.date(byAdding: .day, value: -lead, to: first) else { return [] }
        return (0..<total).compactMap { index in
            guard let current = calendar.date(byAdding: .day, value: index, to: start) else { return nil }
            return TodoCalendarCell(
                date: current,
                dayOfMonth: calendar.component(.day, from: current),
                weekday: isoWeekday(of: current, calendar: calendar),
                inMonth: index >= lead && index < lead + days
            )
        }
    }

    /// 某一周的格子（**恰好 `columns` 格**）：从 `anchor` 所在周的周一起。
    ///
    /// 与 `monthCells` 同源 —— 日序 / 星期都借同一套换算，本模块**不另写第二套日历算术**
    /// （两套算术就会有两个「闰年 2 月」的答案）。周视图的格子不涉及「属不属于本月」，
    /// 故 `inMonth` 一律为 `true`。
    public static func weekCells(anchor: Date, calendar: Calendar) -> [TodoCalendarCell] {
        let start = calendar.startOfDay(for: anchor)
        let lead = (isoWeekday(of: start, calendar: calendar) - firstWeekdayISO + columns) % columns
        guard let monday = calendar.date(byAdding: .day, value: -lead, to: start) else { return [] }
        return (0..<columns).compactMap { index in
            guard let current = calendar.date(byAdding: .day, value: index, to: monday) else { return nil }
            return TodoCalendarCell(
                date: current,
                dayOfMonth: calendar.component(.day, from: current),
                weekday: isoWeekday(of: current, calendar: calendar),
                inMonth: true
            )
        }
    }

    // MARK: - 日期算术

    /// 某月的天数（闰年 2 月 = 29）；坏的年 / 月回 0。
    public static func daysInMonth(year: Int, month: Int, calendar: Calendar) -> Int {
        guard year >= 1, year <= 9999, month >= 1, month <= 12,
              let first = day(year: year, month: month, day: 1, calendar: calendar),
              let range = calendar.range(of: .day, in: .month, for: first) else {
            return 0
        }
        return range.count
    }

    /// 某月第一天的零点；坏的年 / 月回 `nil`。
    public static func firstDate(year: Int, month: Int, calendar: Calendar) -> Date? {
        day(year: year, month: month, day: 1, calendar: calendar)
    }

    /// 某月最后一天的零点；坏的年 / 月回 `nil`。
    public static func lastDate(year: Int, month: Int, calendar: Calendar) -> Date? {
        let days = daysInMonth(year: year, month: month, calendar: calendar)
        guard days > 0 else { return nil }
        return day(year: year, month: month, day: days, calendar: calendar)
    }

    /// 月份移位（跨年才对）`delta` 可负；坏输入回 `nil`。
    public static func shiftMonth(year: Int, month: Int, delta: Int) -> (year: Int, month: Int)? {
        guard year >= 1, year <= 9999, month >= 1, month <= 12 else { return nil }
        let total = year * 12 + (month - 1) + delta
        let nextYear = total >= 0 ? total / 12 : (total - 11) / 12
        let nextMonth = total - nextYear * 12 + 1
        guard nextYear >= 1, nextYear <= 9999, nextMonth >= 1, nextMonth <= 12 else { return nil }
        return (nextYear, nextMonth)
    }

    /// 日期平移 `delta` 天（周视图翻页与「跳到某天」都用它）；结果归到当天零点。
    public static func shift(days delta: Int, from date: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: date))
    }

    // MARK: - 投影（把任务铺在日期上）

    /// **把任务铺在给定的一组格子上**（月视图 = `monthCells`；周视图 = `weekCells`）——
    /// 两档视图共用**同一个**铺法（各写一遍就会出现「同一个任务月视图有、周视图没有」，
    /// 而两侧各自的用例都会是绿的）。
    ///
    /// 四条口径：
    ///  ① **`dueAt` → 哪一天**只有 `calendarDay(of:calendar:)` 一处出处，这里不自己减一个日长；
    ///  ② **参照时刻由调用方传**（`now`），本层不读系统时钟；
    ///  ③ **两区与顺序仍走 `TodoPresentation.sections`**（分区各写一遍 = 第二套口径；排序本身属
    ///     **契约半** ⇒ 段内保持传入顺序，与清单那一屏同一条纪律）；
    ///  ④ **无截止的任务不落在任何一天**（它们只在清单的「无截止」档里有位置）—— 日历不凭空给个日子。
    ///
    /// 结果按**格子的先后**（日升序），**空的天不出现**（界面据此决定画不画点）。
    public static func tasksByDay(
        _ todos: [Todo],
        cells: [TodoCalendarCell],
        now: Date,
        calendar: Calendar
    ) -> [TodoDayTasks] {
        guard !cells.isEmpty else { return [] }
        var buckets: [Date: [Todo]] = [:]
        for todo in todos {
            guard let dueAt = todo.dueAt else { continue }
            buckets[calendarDay(of: dueAt, calendar: calendar), default: []].append(todo)
        }
        return cells.compactMap { cell in
            guard let rows = buckets[cell.date], !rows.isEmpty else { return nil }
            let sections = TodoPresentation.sections(rows)
            let open = sections.first { $0.kind == .open }?.todos ?? []
            let done = sections.first { $0.kind == .completed }?.todos ?? []
            let overdue = open.filter {
                TodoPresentation.dueState($0.dueAt, now: now, calendar: calendar) == .overdue
            }.count
            return TodoDayTasks(date: cell.date, open: open, done: done, overdue: overdue)
        }
    }

    // MARK: - 换算（各一处出处）

    /// `dueAt` → **当天零点**（唯一一处出处）：格子、投影都读它，界面不许自己截断。
    public static func calendarDay(of date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    /// ISO 星期（**1 = 周一 … 7 = 周日**）：Foundation 的 `weekday` 是 1 = 周日 … 7 = 周六
    /// ⇒ 换算只有这一处（两处换算就会有两个「周日算第几天」的答案）。
    public static func isoWeekday(of date: Date, calendar: Calendar) -> Int {
        ((calendar.component(.weekday, from: date) + 5) % 7) + 1
    }

    /// `年 / 月 / 日` → 当天零点；坏输入回 `nil`。
    private static func day(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard year >= 1, year <= 9999, month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }
}
