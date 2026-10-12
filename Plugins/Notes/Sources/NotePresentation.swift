import Foundation

/// 笔记列表卡片要用的两件**纯逻辑**（队列 `L-184` 三栏重排的「中栏」）：摘要与相对时间。
///
/// 为什么放进 Core 而不是视图里：
///  ① **摘要**的规则会同时被「中栏卡片」与将来别的地方用；写在视图里就会各写一套
///     （本仓反复栽的那一族：同一个口径两处实现，改一处漏一处）；
///  ② **相对时间**的档位边界（59 秒 / 60 秒 / 23 小时 / 昨天 / 更早）是**语义**，
///     必须能被单测钉住 —— 视图里的 `if elapsed < 60` 谁都测不到；
///  ③ Core 里**一个汉字都不许有**（R-45 棘轮）：这里只出「哪一档 + 数字」，
///     句子由语言表给（`LKey`），于是中英界面各出各的形状。
public enum NoteRelativeTime: Equatable, Sendable {

    /// 一分钟以内。
    case justNow
    /// 今天之内、分钟档（1…59）。
    case minutes(Int)
    /// 今天之内、小时档（1…23）。
    case hours(Int)
    /// 昨天（日历意义上的昨天，不是「24 小时之前」）。
    case yesterday
    /// 前天及更早（2 天起，如实按整天数报，不做「周 / 月」的近似）。
    case days(Int)

    /// 这一档对应的语言表键（句子只在语言表里）。
    public var key: LKey {
        switch self {
        case .justNow: return .notesTimeJustNow
        case .minutes: return .notesTimeMinutesAgo
        case .hours: return .notesTimeHoursAgo
        case .yesterday: return .notesTimeYesterday
        case .days: return .notesTimeDaysAgo
        }
    }

    /// 模板里那一个 `%@` 的实参（`justNow` / `yesterday` 两档没有槽 ⇒ `nil`）。
    ///
    /// 为什么是已经写好数字的**字符串**而不是 `Int`：语言表里这几条模板用的是 `%@`
    /// （见 `check-format-arguments.py` 的四条判据 —— `Int` 落 `%@` 槽是判红项）；
    /// 而这几条文案里数字不参与任何 printf 宽度 / 精度，写法只有一种。
    public var argument: String? {
        switch self {
        case .justNow, .yesterday: return nil
        case .minutes(let value), .hours(let value), .days(let value): return String(value)
        }
    }
}

/// 笔记列表卡片的两条纯函数。
public enum NotePresentation {

    /// 卡片上的摘要：**一行**、按字符截断、超了加省略号（队列 `L-184` 中栏「标题 + 摘要 2 行」）。
    ///
    /// 三条口径：
    ///  ① **先折行再截**：正文里的换行 / 制表 / 连续空格折成一个空格，否则卡片会被空行撑成一片空白；
    ///  ② **按字符数截**（不是按词）：中英混排按词截会把中文整段吞掉；
    ///  ③ **截断只说「还有」**：末尾一个省略号，不编造「共 N 字」这类数字
    ///     （这里拿到的只是正文，不是「用户看到的全文」）。
    public static func excerpt(_ body: String, limit: Int = 120) -> String {
        var collapsed = ""
        var pendingSpace = false
        for character in body {
            if character.isWhitespace {
                pendingSpace = !collapsed.isEmpty
                continue
            }
            if pendingSpace {
                collapsed.append(" ")
                pendingSpace = false
            }
            collapsed.append(character)
        }
        guard limit > 0, collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }

    /// 相对时间（队列 `L-184` 中栏卡片右下角那一枚）：**按日历**分档，不按时长近似。
    ///
    /// 四条口径（都能被单测钉住）：
    ///  ① **60 秒以内 = 刚刚**；② **同一日历日内**才走分钟 / 小时档（跨零点就是昨天）；
    ///  ③ **昨天 = 日历日差 1 天**（23:59 → 次日 00:01 = 昨天，不是「2 分钟前」）；
    ///  ④ **未来时刻**（时钟回拨 / 库里写进未来的值）⇒ 按「刚刚」报，不出现负数。
    public static func relative(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> NoteRelativeTime {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return .justNow }
        if calendar.isDate(date, inSameDayAs: now) {
            if elapsed < 3600 { return .minutes(Int(elapsed / 60)) }
            return .hours(Int(elapsed / 3600))
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 1 { return .yesterday }
        return .days(days)
    }
}
