import Foundation

/// 待办任务的**重复规则**（`FR-NTS-TODO-LIST-001` 判据①的第四个字段；概设 §15.11「本体四字段齐备」）。
///
/// 三条口径（逐条对着契约 §15.11 与已上盘的提醒引擎写，不新造枚举）：
///
///  ① **复用** `ReminderRule` / `ReminderUnit`（`Core/Reminder.swift`）—— 同一件事不许有第二套
///     取值空间：待办重复与到点提醒都是「按日 / 按周几重复」，各自一套枚举迟早出现「同一档两个名字」。
///  ② **「不重复」只有一种写法**：`Todo.repeatRule == nil`。`ReminderRule.once`（只响一次）在
///     待办这一侧**归一成 `nil`** —— 一次性不是一种重复，留着它就有了两种等价写法（存 `once`
///     与存空串），同步面对拍时同一条任务会算出两种载荷。
///  ③ **周内取值与提醒同一条落库文本**（`ReminderSpec.weekdaysText`：升序 / 去重 / 只留 1~7）。
///     不合法即归一：`weekly` 一天都没选 ⇒ 这条规则**没有发生日** ⇒ 归一成 `nil`（而不是存一条
///     永远不发生的规则，日历那一侧到时会「一条也铺不出来」却说不出为什么）。
///
/// **认不出的取值「当没给」**（与 `TodoPriority` 同一条口径，与 `NoteSource.Kind` 刻意相反）：
/// 别端多了一档规则时，这条任务仍要读得进来，只是这一格当没设 —— 重复规则错一位的后果是
/// 「日历铺错日子」，比整条拒收轻，而整条拒收会连标题一起丢。
public struct TodoRepeat: Equatable, Sendable {

    /// 规则种类（只可能是 `.interval` / `.weekly`；`.once` 在归一那一步就变成 `nil`）。
    public var rule: ReminderRule

    /// 间隔次数（`interval` 用；`< 1` 归一成 `1`）。
    public var intervalCount: Int

    /// 间隔单位（`interval` 用）。
    public var intervalUnit: ReminderUnit

    /// 周内第几天（`weekly` 用；ISO 1~7，升序去重）。
    public var weekdays: [Int]

    public init(
        rule: ReminderRule,
        intervalCount: Int = 1,
        intervalUnit: ReminderUnit = .day,
        weekdays: [Int] = []
    ) {
        self.rule = rule
        self.intervalCount = intervalCount
        self.intervalUnit = intervalUnit
        self.weekdays = weekdays
    }

    // MARK: - 便捷构造（界面只从这三档进，不自己拼字段）

    /// 每 `count` 个 `unit` 重复一次（例：每 2 天 / 每 3 周）。
    public static func every(_ count: Int, _ unit: ReminderUnit) -> TodoRepeat {
        TodoRepeat(rule: .interval, intervalCount: max(1, count), intervalUnit: unit)
    }

    /// 每周的这几天重复（ISO 1~7；空的 ⇒ 调用方拿到 `nil`，见 `normalized()`）。
    public static func weekly(_ weekdays: [Int]) -> TodoRepeat? {
        TodoRepeat(rule: .weekly, weekdays: weekdays).normalized()
    }

    /// 每天重复（= 每 1 天；界面「每天」那一档就是它，不另立取值）。
    public static var daily: TodoRepeat { every(1, .day) }

    // MARK: - 归一

    /// 归一后的这一条规则（`nil` = 没有重复）。
    ///
    /// · `interval`：次数 `< 1` ⇒ `1`（「每 0 天」不是一个规则）；单位照给定。
    /// · `weekly`：周内取值按提醒同一条文本归一；**一天都不剩 ⇒ `nil`**（没有发生日本身就不成立）。
    /// · `once`：⇒ `nil`（口径 ②）。
    public func normalized() -> TodoRepeat? {
        switch rule {
        case .once:
            return nil
        case .interval:
            return TodoRepeat(
                rule: .interval,
                intervalCount: max(1, intervalCount),
                intervalUnit: intervalUnit
            )
        case .weekly:
            let days = ReminderSpec.weekdays(from: ReminderSpec.weekdaysText(weekdays))
            guard !days.isEmpty else { return nil }
            return TodoRepeat(rule: .weekly, weekdays: days)
        }
    }

    /// 是不是「会重复」（归一后一定有 `rule != .once`；`nil` 归 `false`）。
    public var isRecurring: Bool { rule != .once }

    // MARK: - 存储文本（唯一写法：写与读走同一对函数）

    /// 落库文本（`todo.repeat_rule TEXT`）：**确定性 JSON**（键排序），空串 = 没有重复。
    ///
    /// 为什么用 JSON 而不是 `1,3,5` 那种逗号串：这一格有四个字段（种类 / 次数 / 单位 / 周内取值），
    /// 拼串要自己处理转义与缺字段；JSON 的键在排序后逐字节稳定，跨端对拍直接比字节。
    public var storageText: String {
        guard let value = normalized() else { return "" }
        let payload = Payload(repeat: value)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload), let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    /// 从落库文本还原（空串 / 解不出 / 规则认不出 ⇒ `nil`，**不抛错** —— 口径见类型注释）。
    public static func decode(storageText text: String?) -> TodoRepeat? {
        guard let text, !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return payload.repeat
    }

    /// 存储形态（与 `Codable` 的交换形态同一个字段集；`Payload` 只是它的落库外壳）。
    private struct Payload: Codable {
        var rule: String
        var intervalCount: Int
        var intervalUnit: String
        var weekdays: [Int]

        init(repeat value: TodoRepeat) {
            rule = value.rule.rawValue
            intervalCount = value.intervalCount
            intervalUnit = value.intervalUnit.rawValue
            weekdays = value.weekdays
        }

        var `repeat`: TodoRepeat? {
            guard let kind = ReminderRule.normalized(rule),
                  let unit = ReminderUnit.normalized(intervalUnit) else { return nil }
            return TodoRepeat(
                rule: kind,
                intervalCount: intervalCount,
                intervalUnit: unit,
                weekdays: weekdays
            ).normalized()
        }
    }
}

// MARK: - 交换面（`Todo` 的 `Codable` 用）

/// `TodoRepeat` 的交换形态：`{"rule":"weekly","intervalCount":1,"intervalUnit":"day","weekdays":[1,3,5]}`。
///
/// 与落库文本是**同一组键**（`storageText` 就是它的排序 JSON）—— 备份 / 交换面 / 库里那一格
/// 不是三种形状，省掉「同一个值三种编码」那一族缺陷。
extension TodoRepeat: Codable {

    private enum CodingKeys: String, CodingKey {
        case rule, intervalCount, intervalUnit, weekdays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .rule)
        guard let kind = ReminderRule.normalized(raw) else {
            // 认不出的规则 ⇒ **当没给**：调用方（`Todo.init(from:)`）用 `try?` 接住，落成「不重复」。
            throw DecodingError.dataCorruptedError(
                forKey: .rule, in: container,
                debugDescription: "unknown repeat rule: \(raw)"
            )
        }
        self.init(
            rule: kind,
            intervalCount: try container.decodeIfPresent(Int.self, forKey: .intervalCount) ?? 1,
            intervalUnit: ReminderUnit.normalized(try container.decodeIfPresent(String.self, forKey: .intervalUnit)) ?? .day,
            weekdays: try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rule.rawValue, forKey: .rule)
        try container.encode(intervalCount, forKey: .intervalCount)
        try container.encode(intervalUnit.rawValue, forKey: .intervalUnit)
        try container.encode(weekdays, forKey: .weekdays)
    }
}

// MARK: - 语言表出口（句子只在语言表里，取值只在 Core）

/// 编辑面「重复」那一格的四档（**界面档位**，不是存储取值）。
///
/// 为什么要单独一个枚举：存储那一侧只有「间隔」与「按周几」两组字段，而界面要问用户的是
/// 「不重复 / 每天 / 自定义间隔 / 每周几天」四件事 —— 「每天」只是「每 1 天」的一个快捷档，
/// 存进去仍是 `interval`。把这个映射写在一处（`TodoRepeat.mode` / `modeValue`），
/// 界面才不会自己拼「选每天的时候 intervalCount 填几」。
public enum TodoRepeatMode: String, CaseIterable, Sendable, Equatable {
    case none
    case daily
    case interval
    case weekdays

    /// 这一档在语言表里的名字。
    public var key: LKey {
        switch self {
        case .none: return .todoRepeatNone
        case .daily: return .todoRepeatDaily
        case .interval: return .todoRepeatModeInterval
        case .weekdays: return .todoRepeatModeWeekdays
        }
    }
}

extension TodoRepeat {

    /// 这条规则落在哪一档（界面回显用；`nil` ⇒ `.none`）。
    public var mode: TodoRepeatMode {
        switch rule {
        case .once:
            return .none
        case .weekly:
            return .weekdays
        case .interval:
            return intervalCount == 1 && intervalUnit == .day ? .daily : .interval
        }
    }

    /// 某一档的**默认取值**（切换档位时用；`.none` ⇒ `nil`）。
    ///
    /// `.interval` 的默认是「每 2 天」而不是「每 1 天」：「每 1 天」就是「每天」那一档，
    /// 两档给同一个值会让用户切换后看不出变化。
    public static func defaultValue(for mode: TodoRepeatMode) -> TodoRepeat? {
        switch mode {
        case .none: return nil
        case .daily: return .daily
        case .interval: return .every(2, .day)
        case .weekdays: return .weekly([1])
        }
    }
}

extension TodoRepeat {

    /// 这一条规则在语言表里的名字（**一处出**：清单行 / 详情 / 编辑面共用）。
    ///
    /// 「每 N 天 / 每 N 周」走带数字槽的那两条（`%d`）；每周固定的那几天另走一条
    /// （`todoRepeatWeekly`，槽里填的是周内名字，不是数字 —— 数字对读者没有意义）。
    public func nameKey() -> LKey {
        switch rule {
        case .once:
            return .todoRepeatNone
        case .interval:
            if intervalCount == 1 {
                return intervalUnit == .day ? .todoRepeatDaily : .todoRepeatWeekly
            }
            return intervalUnit == .day ? .todoRepeatEveryDays : .todoRepeatEveryWeeks
        case .weekly:
            return .todoRepeatWeekdays
        }
    }

    /// 周内名字（语言表键；`ISO 1~7` ⇒ 周一…周日）。
    public static func weekdayKey(_ weekday: Int) -> LKey {
        switch weekday {
        case 1: return .todoWeekdayMonday
        case 2: return .todoWeekdayTuesday
        case 3: return .todoWeekdayWednesday
        case 4: return .todoWeekdayThursday
        case 5: return .todoWeekdayFriday
        case 6: return .todoWeekdaySaturday
        default: return .todoWeekdaySunday
        }
    }
}

// MARK: - 成形（句子只在语言表里；视图只画）

/// 重复规则的**一句话说明**（清单行 / 详情共用；编辑面读档位名另走 `TodoRepeatMode.key`）。
///
/// 为什么成形落 Core 而不在视图里拼：`%d` 与 `%@` 的槽位、周内名字的分隔符都要跟语言走，
/// 两处各拼一遍就会出现「清单说『每 2 天』、详情说『2 天一次』」这类两种说法。
public enum TodoRepeatPresentation {

    /// `nil` ⇒ `nil`（不重复**不出句子** —— 空态是一句话，不是一行字）。
    public static func summary(_ rule: TodoRepeat?, language: AppLanguage) -> String? {
        guard let value = rule?.normalized() else { return nil }
        switch value.rule {
        case .once:
            return nil
        case .interval:
            switch value.intervalUnit {
            case .day:
                return value.intervalCount == 1
                    ? LocalizedStrings.text(.todoRepeatDaily, language: language)
                    : LocalizedStrings.format(.todoRepeatEveryDays, language: language, value.intervalCount)
            case .week:
                return value.intervalCount == 1
                    ? LocalizedStrings.text(.todoRepeatWeekly, language: language)
                    : LocalizedStrings.format(.todoRepeatEveryWeeks, language: language, value.intervalCount)
            }
        case .weekly:
            let names = value.weekdays.map {
                LocalizedStrings.text(TodoRepeat.weekdayKey($0), language: language)
            }
            let separator = LocalizedStrings.text(.reminderListSeparator, language: language)
            return LocalizedStrings.format(
                .todoRepeatWeekdays, language: language, names.joined(separator: separator)
            )
        }
    }
}
