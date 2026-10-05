import Foundation

/// 备忘提醒的**调度语义**（`DoyahNotes` 核心契约 §2.10 / §3.12；需求条文 `FR-NOTE-02`，任务 `T83`）。
///
/// ## 这一半为什么必须三端一模一样
///
/// 「提醒」有两半：**算准下一次什么时候到**（本文件）与**到点把它弹出来**（各端适配层：系统通知 /
/// 权限 / 后台唤起 / 免打扰）。后者每端各写一次；前者三端**必须一模一样** —— 一次误响比不响更伤
/// 信任（用户会开始怀疑所有提醒），所以这一半要能**脱离设备被穷举验证**。契约 §6 的 `I9`
/// （「提醒的下一次到点 == 逐日扫描的结果，且严格晚于参照时刻」）钉的就是它。
///
/// ## 与对侧同口径（引用，不复制代码）
///
/// 口径出处 = `DoyahNotes/android/core/src/commonMain/kotlin/studio/doyah/notes/core/Reminder.kt`
/// 与鸿蒙侧 `entry/src/main/ets/common/Reminder.ets`（已交付的参考实现）。跨端对账的**真值**不是
/// 本文件、也不是安卓侧实现，而是 `tools/fixtures/reminder-golden-v1.json`（由鸿蒙侧实现跑出来，
/// **39 例**）—— 本侧把那份样例**原样收进 `Tests/Fixtures/`**（只读、不写），由
/// `Tests/ReminderGoldenTests.swift` 逐例断言。比较面只有**日历日 + 当日分钟 + 档位**（契约 §5 第 5 条）。
///
/// ## 六条口径（与契约 §3.12 逐条对应，改之前先读）
///
/// 1. **日历日 + 当日分钟，不做毫秒加法**：到点 =「某个本地日历日的第 N 分钟」。用毫秒累加，
///    在夏令时切换那天会把 09:00 变成 08:00 / 10:00（早响或漏一次）。内部一律用 **UTC 日序**做
///    日历算术（``ReminderSchedule/dayOf(_:)``），它对时区与夏令时**免疫**；只有
///    ``ReminderSchedule/toEpoch(moment:zoneOffsetMillis:)`` 才把（日期, 分钟）解释成本地瞬间。
/// 2. **严格晚于参照时刻**：``ReminderSchedule/next(spec:fromDate:fromMinute:)`` 回的一定是
///    **晚于**参照时刻的那一次；否则「刷新一次 → 又拿到同一个已过的时刻」，调用方可能陷进死循环。
/// 3. **一次性过期不自动改期**：`once` 的锚点时刻已过 ⇒ `expired`，而**不是**「排到明天」。
///    替用户改期是**产品决定**，不是调度细节。
/// 4. **终止日含端点**：`untilDate` 那天仍可以响；算出来的下一次超过它 ⇒ `expired`。
/// 5. **规则集合是数据驱动的**：本模块不预设「产品只支持每天 / 每周」—— 新增规则 = 加一个分支
///    加一组用例，既有规则的语义不受影响。
/// 6. **非法输入不抛错**：任何脏值都回一个 ``ReminderPlan``；错误用语言中立错误码表达
///    （``ReminderCode/invalid``）。口径是**宁可不出提醒，也不出一个错的提醒** —— 不认识的值一律
///    判非法，而**不是**回落成一个看起来合理的默认值。
///
/// ## 为什么这一层的日期是 `YYYY-MM-DD` 串而不是 `Date`
///
/// 本侧 Core 的**界面层**口径是「日期一律 `Date`、串只出现在跨端交换面」（见 `TodoCalendar`）。
/// 提醒这一层是例外，理由是它**本身就是跨端比较面**：契约 §5 第 5 条把「三端算出同一个下一次」
/// 定义在**日历日 + 当日分钟**上（时区 / 夏令时都不该让三端算出不同的结果），所以这里必须用契约
/// 写的那个形态，而不是任何一端的本机瞬间。`Date` ↔（日历日, 分钟）的换算属**适配层**
/// （存储 / 界面 / 系统通知），随 L-100 的「与提醒联动」那半落，不在本文件里发明。
///
/// ## 本片刻意不做的（如实登记）
///
/// 提醒的**存储**（库表 / 与待办的归属列）与**界面入口**（一键挂提醒 / 系统通知）都还没落 ——
/// 本片只落「算准下一次」这半（契约 §2.10 明写「提醒在界面上怎么展示与排序、系统通知怎么发
/// 属各端适配层与界面层」）。`FR-NOTE-02` 的状态位**不因本片翻**。
public enum ReminderRule: String, CaseIterable, Sendable {

    /// 只响一次（`anchorDate` 当天的第 `minuteOfDay` 分钟）。
    case once
    /// 固定间隔重复（每 `intervalCount` 个 `intervalUnit`）。
    case interval
    /// 按周内指定星期重复（`weekdays`，ISO 1~7）。
    case weekly

    /// 当前版本已定义的规则（取值即协议、**只增不改**）。
    public static var known: [String] { allCases.map(\.rawValue) }

    public static func isKnown(_ rule: String) -> Bool {
        ReminderRule(rawValue: rule) != nil
    }

    /// 归一化：**不认识就当没给**（回 `nil` ⇒ 校验判非法）。
    ///
    /// 为什么不回落成「一次性」：规则错一位就是「提醒在错误的时刻响」或「永远不响」，
    /// 宁可拒绝并提示，也不静默按用户没选过的规则排期（口径 6）。
    public static func normalized(_ raw: String?) -> ReminderRule? {
        ReminderRule(rawValue: raw ?? "")
    }
}

/// 间隔单位（取值即协议；契约 §3.12）。
public enum ReminderUnit: String, CaseIterable, Sendable {

    case day
    case week

    /// 当前版本已定义的单位。
    public static var known: [String] { allCases.map(\.rawValue) }

    public static func isKnown(_ unit: String) -> Bool {
        ReminderUnit(rawValue: unit) != nil
    }

    /// 归一化：**缺省按天**（间隔的最小单位）；不认识的值回 `nil` ⇒ 判非法。
    public static func normalized(_ raw: String?) -> ReminderUnit? {
        let text = raw ?? ""
        if text.isEmpty { return .day }
        return ReminderUnit(rawValue: text)
    }

    /// 一个单位折算成多少天（天 = 1 / 周 = 7）。
    public var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        }
    }
}

/// 到点状态（语言中立档位，界面按档位取文案；契约 §3.12）。
public enum ReminderState: String, Sendable {

    /// 算出了下一次（`due` 有效）。
    case pending
    /// 规则本身合法，但**已用尽**（一次性已过 / 超过终止日）—— 这不是错误，界面照常显示「已结束」，
    /// `ok` 仍为 `true`。
    case expired
    /// 规则不合法，`code` = ``ReminderCode/invalid``。
    case invalid
}

/// 契约 §4 的错误码（语言中立；本片只用到这两个）。
public enum ReminderCode {

    /// 没有错误。**空串**（与契约一致：空 = 无）。
    public static let none: String = ""
    /// `reminder.invalid`：提醒规则不合法（缺字段 / 不认识的规则 / 不存在的日期 / 星期越界）。
    public static let invalid: String = "reminder.invalid"
}

/// 一个到点时刻：本地日历日 + 当日分钟（`minute` 为 -1 表示「无」）。
public struct ReminderMoment: Equatable, Sendable {

    /// `YYYY-MM-DD`；无时为空串。
    public var date: String
    /// 当日第几分钟（0~1439）；无时为 -1。
    public var minute: Int

    public init(date: String = "", minute: Int = -1) {
        self.date = date
        self.minute = minute
    }

    /// 「没有时刻」的那个值（契约 §2.10：**不用「0 点」这种看着像数据的值兜底**）。
    public static let none = ReminderMoment()
}

/// 提醒规则（**数据驱动**：引擎只解释这些字段，不假设产品支持哪几种规则；契约 §2.10）。
///
/// 默认值与「没给」等价：不认识的取值一律由 ``ReminderSchedule/next(spec:fromDate:fromMinute:)``
/// 判非法，这里不兜底。
public struct ReminderSpec: Equatable, Sendable {

    /// 规则，取值见 ``ReminderRule``。
    public var rule: String
    /// 锚点日（`YYYY-MM-DD`）：一次性 = 当天；间隔 / 每周 = 首次允许的最早日期。
    public var anchorDate: String
    /// 当日第几分钟（0~1439）。
    public var minuteOfDay: Int
    /// 间隔次数（`interval` 用；其余规则忽略）。
    public var intervalCount: Int
    /// 间隔单位（`interval` 用，缺省 `day`）。
    public var intervalUnit: String
    /// 周内第几天（`weekly` 用，ISO 1~7；重复值被去掉、非法值被剔除）。
    public var weekdays: [Int]
    /// 终止日（含端点；空串表示不设终止）。
    public var untilDate: String

    public init(
        rule: String = "",
        anchorDate: String = "",
        minuteOfDay: Int = -1,
        intervalCount: Int = 0,
        intervalUnit: String = "",
        weekdays: [Int] = [],
        untilDate: String = ""
    ) {
        self.rule = rule
        self.anchorDate = anchorDate
        self.minuteOfDay = minuteOfDay
        self.intervalCount = intervalCount
        self.intervalUnit = intervalUnit
        self.weekdays = weekdays
        self.untilDate = untilDate
    }
}

/// 一次求解的结果（**不抛错**：任何输入都回这个结构；契约 §2.10）。
public struct ReminderPlan: Equatable, Sendable {

    /// 只有 ``ReminderState/invalid`` 为 false；`expired` 仍为 true（规则合法，只是用尽了）。
    public var ok: Bool
    /// 状态档位，取值见 ``ReminderState``。
    public var state: ReminderState
    /// 错误码：``ReminderCode/none`` 或 ``ReminderCode/invalid``。
    public var code: String
    /// 下一次到点；无（`expired` / `invalid`）时 = ``ReminderMoment/none``。
    public var due: ReminderMoment

    public init(ok: Bool, state: ReminderState, code: String, due: ReminderMoment) {
        self.ok = ok
        self.state = state
        self.code = code
        self.due = due
    }
}

/// 提醒的调度（求下一次 / 预演 / 把（日期, 分钟）解释成瞬间）。
///
/// 零平台 API：不落盘、不注册通知、**不读系统时间**（参照时刻由调用方传 —— 否则用例会随运行时刻
/// 飘，与 `NotePresentation.relativeTime` 同一条纪律）。
public enum ReminderSchedule {

    private static let msPerDay: Int = 24 * 60 * 60 * 1000
    private static let minutesPerDay: Int = 24 * 60

    /// 按周重复时，往后找最多这么多天必有命中（星期集合非空 ⇒ 7 天内必有一天命中）。
    private static let weeklyScanDays: Int = 7

    /// 预演次数上限（契约 §3.12：防调用方传天文数字把界面拖死）。
    public static let maxUpcoming: Int = 100

    // MARK: - 求解

    /// 求**下一次**到点：严格晚于参照时刻的第一刻。
    ///
    /// - Parameters:
    ///   - spec: 规则（脏值安全：越界 / 不认识的值都判非法，不抛错）。
    ///   - fromDate: 参照日（`YYYY-MM-DD`，由调用方传「现在」—— 本层不读系统时间）。
    ///   - fromMinute: 参照时刻的当日分钟（0~1439）。
    public static func next(spec: ReminderSpec, fromDate: String, fromMinute: Int) -> ReminderPlan {
        guard let rule = ReminderRule.normalized(spec.rule) else {
            return invalid()
        }
        let anchorDay = dayOf(spec.anchorDate)
        guard anchorDay >= 0 else { return invalid() }
        let minute = spec.minuteOfDay
        guard isMinute(minute) else { return invalid() }
        let untilDay = untilDayOf(spec.untilDate)
        guard untilDay != untilDayInvalid else { return invalid() }
        let fromDay = dayOf(fromDate)
        guard fromDay >= 0, isMinute(fromMinute) else { return invalid() }

        switch rule {
        case .once:
            return onceAt(anchorDay: anchorDay, minute: minute, fromDay: fromDay,
                          fromMinute: fromMinute, untilDay: untilDay)
        case .interval:
            return intervalAt(spec: spec, anchorDay: anchorDay, minute: minute, fromDay: fromDay,
                              fromMinute: fromMinute, untilDay: untilDay)
        case .weekly:
            return weeklyAt(spec: spec, anchorDay: anchorDay, minute: minute, fromDay: fromDay,
                            fromMinute: fromMinute, untilDay: untilDay)
        }
    }

    /// 预演接下来 `count` 次到点（**严格递增**，首项即 ``next(spec:fromDate:fromMinute:)`` 的结果）。
    ///
    /// 用尽（`expired`）或规则非法（`invalid`）时**提前结束** —— 返回的条数可以少于 `count`，
    /// 但**绝不伪造时刻**；`count` 不是正整数时回空数组；超过 ``maxUpcoming`` 按上限截断。
    public static func upcoming(
        spec: ReminderSpec,
        fromDate: String,
        fromMinute: Int,
        count: Int
    ) -> [ReminderMoment] {
        var out: [ReminderMoment] = []
        guard count > 0 else { return out }
        let limit = min(count, maxUpcoming)
        var cursorDate = fromDate
        var cursorMinute = fromMinute
        for _ in 0..<limit {
            let plan = next(spec: spec, fromDate: cursorDate, fromMinute: cursorMinute)
            guard plan.state == .pending else { return out }
            out.append(plan.due)
            cursorDate = plan.due.date
            cursorMinute = plan.due.minute
        }
        return out
    }

    // MARK: - 瞬间（各端适配层把提醒交给系统通知时用）

    /// 把（日期, 分钟）解释成本地瞬间（毫秒时间戳）—— **不读平台时区 API**，偏移由调用方传。
    /// 非法输入回 -1（不抛错）。
    ///
    /// 注意**时区差异不进语义**：换一个时区，``upcoming(spec:fromDate:fromMinute:count:)`` 的结果
    /// 一模一样，变的只有这里。
    public static func toEpoch(moment: ReminderMoment, zoneOffsetMillis: Int) -> Int {
        let day = dayOf(moment.date)
        guard day >= 0, isMinute(moment.minute) else { return -1 }
        return day * msPerDay + moment.minute * 60_000 - zoneOffsetMillis
    }

    /// ``toEpoch(moment:zoneOffsetMillis:)`` 的**反向**：毫秒时间戳 → 它落在哪个本地日历日。
    ///
    /// 为什么要有它（而不是让用它的模块自己减一个日长）：正向与反向必须共用**同一个**日长常量与
    /// 同一个日序原点 —— 各写一份就会在「夏令时 / 跨年」这类边界上出现「存进去的截止时间，日历上
    /// 落到前一天」这种错，而两边各自的用例都会是绿的。
    public static func dateOfEpoch(epochMillis: Int, zoneOffsetMillis: Int) -> String {
        dateOfDay(floorDiv(epochMillis + zoneOffsetMillis, msPerDay))
    }

    /// ``toEpoch(moment:zoneOffsetMillis:)`` 的**另一条**反向路：毫秒时间戳 → （本地日历日, 当日分钟）。
    ///
    /// 为什么要与 `dateOfEpoch` 并存：界面拿到的是 `Date`（截止时刻），要把它变成契约形态的
    /// （日期, 分钟）才挂得上提醒 —— 而**日长**与**日序原点**必须与正向那一份同一处：
    /// 各写一份就会在「夏令时 / 跨年」那天算错一天，而两边各自的用例都会是绿的。
    ///
    /// 极端值（快溢出 `Int` 的毫秒数）回 ``ReminderMoment/none``，**不抛错**（与本层同口径）。
    public static func momentOfEpoch(epochMillis: Int, zoneOffsetMillis: Int) -> ReminderMoment {
        guard epochMillis > Int.min / 2, epochMillis < Int.max / 2 else { return .none }
        let local = epochMillis + zoneOffsetMillis
        return ReminderMoment(
            date: dateOfDay(floorDiv(local, msPerDay)),
            minute: floorMod(local, msPerDay) / 60_000
        )
    }

    // MARK: - 规则分支（每条只负责「下一次是哪一天」；合法性已在 next 里统一校验）

    private static func onceAt(
        anchorDay: Int,
        minute: Int,
        fromDay: Int,
        fromMinute: Int,
        untilDay: Int
    ) -> ReminderPlan {
        if untilDay >= 0, anchorDay > untilDay { return expired() }
        if anchorDay > fromDay || (anchorDay == fromDay && minute > fromMinute) {
            return pending(day: anchorDay, minute: minute)
        }
        return expired()
    }

    private static func intervalAt(
        spec: ReminderSpec,
        anchorDay: Int,
        minute: Int,
        fromDay: Int,
        fromMinute: Int,
        untilDay: Int
    ) -> ReminderPlan {
        guard let unit = ReminderUnit.normalized(spec.intervalUnit), spec.intervalCount > 0 else {
            return invalid()
        }
        let step = spec.intervalCount * unit.days
        guard step > 0 else { return invalid() }
        // 直接算第 k 格（O(1)）：k 取「锚点之后第几个格子的日子 ≥ 参照日」，再按口径 2 往前挪一格。
        var k = 0
        if fromDay > anchorDay {
            k = ceilDiv(fromDay - anchorDay, step)
        }
        var candidate = anchorDay + k * step
        if candidate == fromDay && minute <= fromMinute {
            candidate += step
        }
        if fromDay < anchorDay {
            candidate = anchorDay
        }
        if untilDay >= 0, candidate > untilDay { return expired() }
        return pending(day: candidate, minute: minute)
    }

    private static func weeklyAt(
        spec: ReminderSpec,
        anchorDay: Int,
        minute: Int,
        fromDay: Int,
        fromMinute: Int,
        untilDay: Int
    ) -> ReminderPlan {
        let days = weekdaysOf(spec.weekdays)
        guard !days.isEmpty else { return invalid() }
        let start = fromDay > anchorDay ? fromDay : anchorDay
        for offset in 0...weeklyScanDays {
            let day = start + offset
            if !days.contains(weekdayOfDay(day)) { continue }
            if day == fromDay && minute <= fromMinute { continue }
            if untilDay >= 0, day > untilDay { return expired() }
            return pending(day: day, minute: minute)
        }
        return expired()
    }

    // MARK: - 归一化与日历算术

    /// 星期归一化：只保留 1~7 的整数，去重并升序（口径 7）。
    private static func weekdaysOf(_ raw: [Int]) -> [Int] {
        var out: [Int] = []
        for value in raw where value >= 1 && value <= 7 && !out.contains(value) {
            out.append(value)
        }
        return out.sorted()
    }

    private static func isMinute(_ value: Int) -> Bool {
        value >= 0 && value < minutesPerDay
    }

    /// 终止日的哨兵：`-1` = 不设；`-2` = 非法（**不设与非法必须分开**，否则「写错一个终止日」
    /// 会被静默当成「不设终止」）。
    private static let untilDayInvalid = -2

    private static func untilDayOf(_ untilDate: String) -> Int {
        if untilDate.isEmpty { return -1 }
        let day = dayOf(untilDate)
        return day < 0 ? untilDayInvalid : day
    }

    /// `YYYY-MM-DD` → UTC 日序（**时区 / 夏令时免疫**）；非法（含 `2026-02-30`）回 -1。
    ///
    /// 算术不用任何平台时间 API（共享层零平台依赖）：儒略日式的整数换算。
    public static func dayOf(_ date: String) -> Int {
        guard let parts = partsOf(date) else { return -1 }
        return daysFromCivil(year: parts.0, month: parts.1, day: parts.2)
    }

    /// UTC 日序 → `YYYY-MM-DD`。
    public static func dateOfDay(_ day: Int) -> String {
        let parts = civilFromDays(day)
        return textOf(year: parts.0, month: parts.1, day: parts.2)
    }

    /// 日序 → ISO 星期（**1 = 周一 … 7 = 周日**）：1970-01-01 是周四 ⇒ 日序 0 回 4。
    public static func weekdayOfDay(_ day: Int) -> Int {
        floorMod(day + 3, 7) + 1
    }

    private static func textOf(year: Int, month: Int, day: Int) -> String {
        let m = month < 10 ? "0\(month)" : "\(month)"
        let d = day < 10 ? "0\(day)" : "\(day)"
        return "\(year)-\(m)-\(d)"
    }

    /// `YYYY-MM-DD` → `(年, 月, 日)`（逐项校验：位数、范围、以及当月**真实存在**的那一天）。
    ///
    /// 不存在的日期（`2026-02-30` / 非闰年的 `02-29` / `2026-13-01`）回 `nil` ——
    /// 「把 2 月 30 日滚到 3 月 2 日」是多数日期库的默认行为，对提醒来说是**静默错期**。
    private static func partsOf(_ date: String) -> (Int, Int, Int)? {
        let parts = date.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              year >= 1970, year <= 9999, month >= 1, month <= 12, day >= 1,
              day <= daysInMonth(year: year, month: month) else {
            return nil
        }
        return (year, month, day)
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        if month == 2 { return isLeapYear(year) ? 29 : 28 }
        if month == 4 || month == 6 || month == 9 || month == 11 { return 30 }
        return 31
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    private static func pending(day: Int, minute: Int) -> ReminderPlan {
        ReminderPlan(
            ok: true,
            state: .pending,
            code: ReminderCode.none,
            due: ReminderMoment(date: dateOfDay(day), minute: minute)
        )
    }

    private static func expired() -> ReminderPlan {
        ReminderPlan(ok: true, state: .expired, code: ReminderCode.none, due: .none)
    }

    private static func invalid() -> ReminderPlan {
        ReminderPlan(ok: false, state: .invalid, code: ReminderCode.invalid, due: .none)
    }

    // MARK: - 整数算术（不用平台日期 API；与对侧逐值一致）

    /// 元年（1970-01-01）的儒略式日序常量（Howard Hinnant 的 `days_from_civil`）。
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        var y = year
        if month <= 2 { y -= 1 }
        let era = floorDiv(y, 400)
        let yoe = y - era * 400
        let m = month
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// ``daysFromCivil(year:month:day:)`` 的逆运算。
    private static func civilFromDays(_ days: Int) -> (Int, Int, Int) {
        let z = days + 719468
        let era = floorDiv(z, 146097)
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        var y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        if m <= 2 { y += 1 }
        return (y, m, d)
    }

    private static func floorDiv(_ value: Int, _ divisor: Int) -> Int {
        var quotient = value / divisor
        if value % divisor != 0 && ((value < 0) != (divisor < 0)) {
            quotient -= 1
        }
        return quotient
    }

    private static func floorMod(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder < 0 ? remainder + divisor : remainder
    }

    /// 向上取整的整数除法（只在非负分子上使用：`fromDay - anchorDay > 0`）。
    private static func ceilDiv(_ value: Int, _ divisor: Int) -> Int {
        (value + divisor - 1) / divisor
    }
}

// MARK: - 落库的那一行（存储半 · 队列 `L-100` 落法 ④；第 189 轮）

/// 一条提醒**挂在谁身上**（笔记或待办，二选一）。
///
/// 为什么这一半现在才落：契约 §2.10 写的是「一条提醒的**规则数据**」（`ReminderSpec`），
/// 「挂在笔记上还是待办上」属**归属面** —— 对侧（小河马）已在 `DoyahNotes/Docs/proposals/0011`
/// 提请契约所有者裁决。本侧按与对侧**同一份默认口径**落（一条提醒恰好属于一个目标；
/// 人工测试清单第 7 条「有截止时间的任务一键挂提醒」= 建一条 `.todo` 的提醒），
/// **裁决若不同即改** —— 改点只有 schema v6 那一条 `CHECK` 与 `NoteDatabase.upsert(_ reminder:)`。
public enum ReminderOwner: Equatable, Sendable {

    /// 挂在**笔记**上。
    case note(UUID)
    /// 挂在**待办任务**上。
    case todo(UUID)

    /// 归属笔记的 id（不是这一类就是 `nil`）。
    public var noteID: UUID? {
        if case .note(let id) = self { return id }
        return nil
    }

    /// 归属任务的 id（不是这一类就是 `nil`）。
    public var todoID: UUID? {
        if case .todo(let id) = self { return id }
        return nil
    }

    /// 归属是一条笔记吗（`false` = 一条任务）。
    public var isNote: Bool { noteID != nil }
}

/// 库里**一条提醒**：归属 + 规则（``ReminderSpec``）+ 两个时刻。
///
/// 与 `ReminderSpec` 的分工：规格回答「什么时候响」（契约 §2.10 的那份纯数据，三端同义），
/// 本结构回答「这是**谁**的提醒、什么时候建的」（本端库里的一行 —— 列名与存储形态属实现面，
/// 契约不承诺）。**「到没到点」不落库**：那件事由 ``ReminderSchedule`` 按参照时刻**当场算**
/// （存下来就有两个事实源，且时区一改就是错的）。
public struct Reminder: Identifiable, Equatable, Sendable {

    public var id: UUID
    public var owner: ReminderOwner
    public var spec: ReminderSpec
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        owner: ReminderOwner,
        spec: ReminderSpec,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.owner = owner
        self.spec = spec
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 周内取值的**落库文本**（`1,3,5`）与回读。
///
/// 为什么要有这一对：`weekdays` 在契约里是**数组**（ISO 1~7），而库那一列是 `TEXT`。
/// 归一（去重 + 只留 1~7 + 升序）在**写与读两侧是同一个函数** —— 否则「库里存的顺序」与
/// 「界面上显示的顺序」会各有一套，跨端对拍时同一条规则会给出两种文本。
extension ReminderSpec {

    /// 周内取值 → 落库文本（升序、去重、非 1~7 的值剔除；空串 = 不按星期）。
    public var weekdaysText: String { ReminderSpec.weekdaysText(weekdays) }

    /// 落库文本 → 周内取值（认不出的片段一律剔除、**不抛错** —— 与调度那一层「脏值不抛错」同口径）。
    public static func weekdays(from text: String) -> [Int] {
        let values = text
            .split(separator: ",")
            .compactMap { Int(String($0).trimmingCharacters(in: .whitespaces)) }
        return normalizedWeekdays(values)
    }

    /// 归一后的文本（唯一的写法，写与读都走它）。
    public static func weekdaysText(_ values: [Int]) -> String {
        normalizedWeekdays(values).map(String.init).joined(separator: ",")
    }

    private static func normalizedWeekdays(_ values: [Int]) -> [Int] {
        var seen = Set<Int>()
        return values
            .filter { (1...7).contains($0) && seen.insert($0).inserted }
            .sorted()
    }
}
