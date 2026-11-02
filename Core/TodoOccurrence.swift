import Foundation

/// **重复任务按发生日铺开**（`FR-NTS-TODO-CALENDAR-001` 判据④）与「改一次：这一条 / 这一串」的选择。
///
/// 四条口径（逐条对着需求书 §3.5 与已上盘的 `TodoRepeat` / `ReminderSchedule` 写）：
///
///  ① **库里只有一条记录**：铺开是**投影**，不是预生成副本 —— 本文件没有任何写路，
///     日历拿到的仍是清单那一份 `[Todo]`（同一条任务在月中出现 5 天，`todos()` 仍回 1 行）。
///  ② **哪天算发生**：锚点 = `dueAt` 那一日（首发生日）；`interval` = 锚点起每 `count × unit.days` 天；
///     `weekly` = 锚点起每个落在 `weekdays` 里的日子；`nil` 规则 = 只有锚点那一天。
///     不早于锚点（「之前的日子」不是这次重复的发生日）。
///  ③ **跳过的日子不发生**：`TodoRepeat.skipped`（「只改这一条」留下的那一格）。
///     日期串**只在本文件一处生成**（`dayKey(for:calendar:)`），比较才对得上。
///  ④ **日期算术不在本文件另写一份**：日差走调用方传的 `Calendar`，星期走
///     `TodoCalendar.isoWeekday`（唯一一处 ISO 换算）—— 再写一份就会有两个「周日是第几天」。
public enum TodoOccurrence {

    /// 这一条任务在 `day` 有没有一次发生。
    public static func occurs(_ todo: Todo, on day: Date, calendar: Calendar) -> Bool {
        guard let dueAt = todo.dueAt else { return false }
        return occurs(repeatRule: todo.repeatRule, anchor: dueAt, on: day, calendar: calendar)
    }

    /// 规则 + 锚点 ⇒ 某一天是否发生（判据可以只喂规则，不必造整条任务）。
    public static func occurs(
        repeatRule: TodoRepeat?,
        anchor: Date,
        on day: Date,
        calendar: Calendar
    ) -> Bool {
        let start = calendar.startOfDay(for: anchor)
        let target = calendar.startOfDay(for: day)
        guard target >= start else { return false }
        guard let rule = repeatRule?.normalized() else { return target == start }
        if rule.isSkipped(dayKey(for: target, calendar: calendar)) { return false }
        switch rule.rule {
        case .once:
            // 归一后不会出现（`once` ⇒ `nil`）；留这一支是让 `switch` 完整，且行为可解释。
            return target == start
        case .weekly:
            return rule.weekdays.contains(TodoCalendar.isoWeekday(of: target, calendar: calendar))
        case .interval:
            let step = max(1, rule.intervalCount) * rule.intervalUnit.days
            guard step > 0,
                  let diff = calendar.dateComponents([.day], from: start, to: target).day
            else { return false }
            return diff >= 0 && diff % step == 0
        }
    }

    /// 这一条落在给定格子里的那些天（**保持格子的先后**：界面按格子画，顺序就是它）。
    public static func days(
        _ todo: Todo,
        in cells: [TodoCalendarCell],
        calendar: Calendar
    ) -> [Date] {
        cells.filter { occurs(todo, on: $0.date, calendar: calendar) }.map(\.date)
    }

    /// `[from, to]` 闭区间里这一条落到的那些天（详情 / 判据用；不含跳过的日子）。
    ///
    /// `from > to` ⇒ 空（不猜一个方向）。区间过长（> `ReminderSchedule.maxUpcoming` 天）按上限截断，
    /// 与提醒预演同一条防拖死口径。
    public static func days(
        _ todo: Todo,
        from: Date,
        to: Date,
        calendar: Calendar
    ) -> [Date] {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        guard start <= end,
              let span = calendar.dateComponents([.day], from: start, to: end).day,
              span >= 0
        else { return [] }
        let limit = min(span, ReminderSchedule.maxUpcoming)
        return (0...limit).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return occurs(todo, on: day, calendar: calendar) ? day : nil
        }
    }

    /// 日历日 → `YYYY-MM-DD`（**跳过表的唯一生成处**）。
    ///
    /// 为什么不让各处自己 `String(format:)`：跳过表是**逐字符比较**的，
    /// 某处写成 `2026-11-1`、另一处写成 `2026-11-01`，那一格就永远对不上（而两边看上去都对）。
    public static func dayKey(for day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `day` 那一天配上 `reference` 那一刻的**钟点**（秒以下带过来；`reference` 为 `nil` ⇒ 当天零点）。
    ///
    /// 为什么要它：重复任务的第 5 次发生与第 1 次是**同一个钟点**（用户排的是「每周三 09:00」），
    /// 在日历上点第 5 次去改期，改期框里该预填的是「那天 09:00」而不是「那天 00:00」——
    /// 这个换算与 `TodoCalendar.moment` 同一族（日期算术只在 Core），界面不自己拼 components。
    public static func momentMatching(
        _ day: Date,
        like reference: Date?,
        calendar: Calendar
    ) -> Date {
        let start = calendar.startOfDay(for: day)
        guard let reference else { return start }
        let parts = calendar.dateComponents([.hour, .minute, .second], from: reference)
        return TodoCalendar.moment(
            hour: parts.hour ?? 0, minute: parts.minute ?? 0, on: start, calendar: calendar
        ) ?? start
    }
}

// MARK: - 「改这一条 / 改这一串」

/// 改一条**重复任务**时先要回答的那一问（需求书 `FR-NTS-TODO-CALENDAR-001` 判据④
/// 「改一次要说清改的是『这一条』还是『这一串』」· 能力书 5.2.2）。
///
/// 两档的后果**不一样**，所以它是一个必须显式选的量，不是默认值能糊过去的东西：
/// · `.thisOccurrence` —— 只有那一天变（那一串里这一天被跳过，另起一条独立记录带着改动）；
/// · `.thisSeries`   —— 整串跟着变（仍然是**那一条**记录，锚点挪了，所有发生日重算）。
public enum TodoRepeatEditScope: String, CaseIterable, Sendable, Equatable {

    /// 只改那一天。
    case thisOccurrence
    /// 改整串。
    case thisSeries

    /// 默认 = **改整串**：用户在日历上点「改期」，多数时候想改的是「这件事以后都这个点」；
    /// 只改一天的后果更不可逆（会多出一条记录），所以那一条必须是他自己按的。
    public static var initial: TodoRepeatEditScope { .thisSeries }

    /// 这一档在语言表里的名字（一处出）。
    public var key: LKey {
        switch self {
        case .thisOccurrence: return .todoScopeThisOccurrence
        case .thisSeries: return .todoScopeThisSeries
        }
    }

    /// 认不出的取值「当没给」= `.thisSeries`（与 `TodoPriority` 同一条口径）。
    public init(raw: String) {
        self = TodoRepeatEditScope(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .initial
    }
}

/// 一次「改重复任务」要落的那几笔（**纯数据**：谁写、写几条，由调用方那一条事务落）。
public struct TodoOccurrenceEdit: Equatable, Sendable {

    /// 用户选的那一档。
    public let scope: TodoRepeatEditScope
    /// 那一串（**唯一那条记录**，改后的样子）。
    public let series: Todo
    /// 「只改这一条」新起的独立记录（`.thisSeries` ⇒ `nil`）。
    public let detached: Todo?
    /// 这一串里被跳过的那一天（`.thisSeries` ⇒ `nil`）。
    public let skippedDay: Date?

    public init(
        scope: TodoRepeatEditScope,
        series: Todo,
        detached: Todo? = nil,
        skippedDay: Date? = nil
    ) {
        self.scope = scope
        self.series = series
        self.detached = detached
        self.skippedDay = skippedDay
    }

    /// 要落的那几条（**一个事务里一起写**：半条是最难查的一类不一致）。
    public var writes: [Todo] {
        guard let detached else { return [series] }
        return [series, detached]
    }

    /// 这次改的是不是「一串」（界面据此决定要不要提示「其它日子也变了」）。
    public var isSeriesWide: Bool { scope == .thisSeries }
}

/// 把「改哪一头」变成要落的那几笔（**不读系统时钟**：`now` 由调用方传，与 `TodoCalendar` 同一条纪律）。
public enum TodoOccurrenceEditor {

    /// 改期：把这**一次**（`day` 那天的那一回）改到 `dueAt`。
    ///
    /// - Parameters:
    ///   - todo: 库里那一条（**唯一**那条记录）。
    ///   - day: 用户在日历上点的那一天（必须真的是它的一次发生日；不是 ⇒ 只有整串那一条路可走）。
    ///   - dueAt: 改到哪一刻（钟点取用户选的；日期通常就在 `day` 上，但允许跨天 —— 那是他自己的选择）。
    ///   - scope: 「这一条」还是「这一串」。
    ///   - now: 参照时刻（`updatedAt` / 新记录的 `createdAt` 用它；本层不读时钟）。
    public static func reschedule(
        _ todo: Todo,
        on day: Date,
        to dueAt: Date,
        scope: TodoRepeatEditScope,
        now: Date,
        calendar: Calendar
    ) -> TodoOccurrenceEdit {
        let key = TodoOccurrence.dayKey(for: day, calendar: calendar)
        // 这一天不是它的一次发生日 ⇒ 「只改这一条」不成立（没有那一条可改）⇒ 如实退成整串。
        let canEditOne = TodoOccurrence.occurs(todo, on: day, calendar: calendar)

        guard scope == .thisOccurrence, canEditOne, let rule = todo.repeatRule?.normalized() else {
            var series = todo
            series.dueAt = dueAt
            series.updatedAt = now
            return TodoOccurrenceEdit(scope: .thisSeries, series: series)
        }

        var series = todo
        var updatedRule = rule
        updatedRule.skipped = TodoRepeat.normalizedSkips(rule.skipped + [key])
        series.repeatRule = updatedRule
        series.updatedAt = now

        var detached = todo
        detached.id = UUID()
        detached.dueAt = dueAt
        detached.repeatRule = nil
        detached.done = false
        detached.completedAt = nil
        detached.createdAt = now
        detached.updatedAt = now

        return TodoOccurrenceEdit(
            scope: .thisOccurrence,
            series: series,
            detached: detached,
            skippedDay: calendar.startOfDay(for: day)
        )
    }
}
