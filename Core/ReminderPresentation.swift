import Foundation

/// 「一键挂提醒」与「到点把它弹出来」这两件事里，**属于本端界面层的那半纯逻辑**（队列 `L-100` 落法 ④）。
///
/// ## 为什么这一层在 Core 而不是写在视图里
///
/// 契约（`DoyahNotes/Docs/核心契约.md` §2.10 末尾）把这半**明确排除在契约之外**：原文写的是
/// 「提醒在界面上怎么展示与排序、系统通知怎么发（权限 / 通知渠道 / 后台唤起 / 免打扰）、铃声与
/// 提醒方式 —— 属**各端适配层与界面层**」。既然每端都要各写一次，就要写成**能被断言**的形式：
///
///  ① **档位 → 规则**（「提前 1 天」到底落在哪一天、哪一分钟）是**日期算术**。写在视图里就是几行
///     `Date` 加减；跨零点（00:20 的截止时间「提前 1 小时」要退到**前一天** 23:20）与大月小月这类
///     边界，界面上**看不出来**，只有用例能钉住；
///  ② **权限三档 → 排不排、为什么** 是**判定**：未决 / 被拒 / 已授权 与 待发 / 已结束 / 规则认不出
///     组合出的每一格都要有话说 —— 人工测试清单第 7 条那句「到点有通知」只在**已授权且有待发时刻**
///     那一格成立，其余各格都必须给出一句话，而不是静默不响；
///  ③ Core 里**一个汉字都不许有**（`Scripts/check-core-localization.py` 棘轮）：句子只在
///     `Localization.swift` 的语言表里，这一层只出「**哪个键 + 什么实参**」（`LKey`）。
///
/// ## 时区与「现在」都由调用方给（与 `ReminderSchedule` 同一条纪律）
///
/// 本层**不读系统时钟、不读系统时区**（系统时钟 / 系统时区 / 系统日历这三个平台 API 在本文件里
/// 零命中）：瞬间与偏移（`zoneOffsetMillis`）都从参数进来。理由是实测过的同一族：口径写死一处
/// 才判得准，而「提前 1 天算错一天」这种错只有在别的时区才现形。
///
/// ## 本片刻意不做的
///
/// 真正的系统通知（注册 / 授权请求 / 到点投递 / 免打扰）属**适配层**，在 `App/` 那一侧；
/// 这一层只回答三件事：**能不能挂**（`attachment`）、**排不排**（`notificationDecision`）、
/// **那句话怎么说**（`summary` / `nextText` / `notificationBody`）。

/// 一键挂提醒的档位（**相对任务的截止时刻**；队列 `L-100` 落法 ④「有截止时间的任务一键挂提醒」）。
///
/// 为什么是「相对截止时刻」而不是「星期几几点」：这一层的输入就是一条待办（它有 `dueAt`），
/// 用户点一下要的是「就在这件事到点前提醒我」；`weekly` / `interval` 那两类规则**不是**从一个
/// 截止时间能推出来的（那是用户在提醒编辑器里选的），所以这里**不发明**它们 —— 规则集合仍由
/// `ReminderRule` 定义（契约 §3.12），本层只用其中的 `once`。
public enum ReminderPreset: String, CaseIterable, Sendable {

    /// 到点那一刻（默认档 —— 人工测试清单第 7 条原文「到点有通知」）。
    case atDue = "atDue"
    /// 提前 15 分钟。
    case before15m = "before15m"
    /// 提前 1 小时。
    case before1h = "before1h"
    /// 提前 1 天。
    case before1d = "before1d"

    /// 提前量（分钟；「到点」= 0）。
    ///
    /// 用分钟而不是 `TimeInterval`：这一层的下游是「日历日 + 当日分钟」那套整数算术，
    /// 秒与毫秒在这里没有语义（契约 §3.12 口径 1）。
    public var leadMinutes: Int {
        switch self {
        case .atDue: return 0
        case .before15m: return 15
        case .before1h: return 60
        case .before1d: return 24 * 60
        }
    }

    /// 这一档在界面上那句话的键（句子只在语言表里）。
    public var key: LKey {
        switch self {
        case .atDue: return .reminderPresetAtDue
        case .before15m: return .reminderPresetBefore15m
        case .before1h: return .reminderPresetBefore1h
        case .before1d: return .reminderPresetBefore1d
        }
    }

    /// 默认档 = **到点**。
    ///
    /// 依据 = 人工测试清单（macOS 半 · Alpha 3）第 7 条那句「到点有通知」：一键挂提醒的默认必须
    /// 是用户最常要的那一档，而「提前量」是加法（想要的人自己选）。
    public static let presetDefault: ReminderPreset = .atDue

    /// 当前版本已定义的档位（取值即协议；**只增不改**）。
    public static var known: [String] { allCases.map(\.rawValue) }

    /// 归一化：**认不出当没给**（回 `nil`）。
    ///
    /// 与 `ReminderRule.normalized` 同口径：档位认不出就**不给**（调用方回落默认档），
    /// 而不是静默按一个用户没选过的档挂上提醒 —— 「错位的提醒」比「没提醒」更伤信任。
    public static func normalized(_ raw: String?) -> ReminderPreset? {
        ReminderPreset(rawValue: raw ?? "")
    }
}

/// 「一键挂提醒」的结果：能挂（带算好的规则）或**不能挂 + 为什么**（不抛错）。
///
/// 为什么把「不能挂」也做成一个结果而不是 `nil`：界面要**说一句人话**（「先给这个任务一个截止
/// 时间」），而 `nil` 只能让每个调用点各自猜原因。
public enum ReminderAttachment: Equatable, Sendable {

    /// 能挂：`spec` 是算好的规则（`once`，锚在档位对应的那一刻），`moment` 是那一刻本身。
    case ready(spec: ReminderSpec, preset: ReminderPreset, moment: ReminderMoment)
    /// 这条待办**没有截止时间** ⇒ 先要一个截止时间（键 `.reminderNeedsDue`）。
    case needsDueDate
    /// 提前量把时刻推到了 **1970-01-01 之前**（契约的日期形态只认 1970 起的四位数年份）⇒ 不编日期。
    case outOfRange

    /// 算好规则的那一份（不能挂时 `nil`）。
    public var spec: ReminderSpec? {
        if case .ready(let spec, _, _) = self { return spec }
        return nil
    }

    /// 挂上的档位（不能挂时 `nil`）。
    public var preset: ReminderPreset? {
        if case .ready(_, let preset, _) = self { return preset }
        return nil
    }

    /// 挂上的那一刻（不能挂时 = `.none`）。
    public var moment: ReminderMoment {
        if case .ready(_, _, let moment) = self { return moment }
        return .none
    }

    /// 不能挂时那一句话的键（能挂时 `nil`）。
    public var reasonKey: LKey? {
        switch self {
        case .ready: return nil
        case .needsDueDate: return .reminderNeedsDue
        case .outOfRange: return .reminderOutOfRange
        }
    }
}

/// 系统通知权限的三档（**界面看到的就是这三档**；本层不碰任何平台 API）。
public enum ReminderPermission: String, CaseIterable, Sendable {

    /// 还没问过系统。
    case notDetermined = "notDetermined"
    /// 问过了、用户关掉了。
    case denied = "denied"
    /// 已授权。
    case authorized = "authorized"

    /// 归一化：**认不出的一律当「还没问过」**。
    ///
    /// 为什么兜底到「未决」而不是「已授权」：未决那一格的动作是「先问、这一轮**不排**」，
    /// 排在安全侧；反过来兜底成已授权会去排一条**用户可能从没同意过**的通知。
    public static func normalized(_ raw: String?) -> ReminderPermission {
        ReminderPermission(rawValue: raw ?? "") ?? .notDetermined
    }

    /// 这一档在界面上那句话的键。
    public var key: LKey {
        switch self {
        case .notDetermined: return .reminderPermissionNotDetermined
        case .denied: return .reminderPermissionDenied
        case .authorized: return .reminderPermissionAuthorized
        }
    }
}

/// 界面该不该把这条提醒交给系统（以及为什么）。
public enum ReminderNotificationDecision: Equatable, Sendable {

    /// 排上：触发瞬间 = `triggerEpochMillis`（毫秒时间戳，交给系统通知那一层）。
    case schedule(triggerEpochMillis: Int)
    /// 还**没问过**权限 ⇒ 先问；**这一轮不排**（问的结果下一轮才看得见）。
    case askPermission
    /// 不排 + 一句人话（被拒 / 已结束 / 规则认不出 / 时刻算不出来）。
    case inactive(LKey)

    /// 排上了吗（界面据此决定「挂」这枚按钮的形态）。
    public var isScheduled: Bool {
        if case .schedule = self { return true }
        return false
    }

    /// 不排时那句话的键（其它情况 `nil`）。
    public var reasonKey: LKey? {
        switch self {
        case .schedule, .askPermission: return nil
        case .inactive(let key): return key
        }
    }
}

/// 提醒的**界面层纯逻辑**：档位 → 规则、权限 → 排不排、规则 → 一句话。
public enum ReminderPresentation {

    /// 提前量把时刻推到 1970 年之前时的那个哨兵判断（契约的日期形态只认 1970 起的年份）。
    ///
    /// 为什么要有这一条：`ReminderSchedule.dayOf` 对 1969 年回 -1（非法），如果照样拼一个
    /// `ReminderSpec` 出来，那条提醒在**库里是合法的一行**、却**永远算不出下一次** ——
    /// 反而更难查。这里当场判出来，界面知道该说「这个提前量算不出日期」。
    private static func isRepresentable(_ moment: ReminderMoment) -> Bool {
        ReminderSchedule.dayOf(moment.date) >= 0 && moment.minute >= 0
    }

    // MARK: - 瞬间 ↔（日历日, 分钟）

    /// 一个**瞬间**（`Date`）落在这个时区的哪一天哪一分钟（偏移由调用方给）。
    ///
    /// 与 `ReminderSchedule.momentOfEpoch` 的分工：那一半吃毫秒、这半边只做 `Date` → 毫秒的换算，
    /// **日长与日序原点仍只有那一处**（各写一份就会在夏令时 / 跨年那天错一天）。
    public static func moment(of date: Date, zoneOffsetMillis: Int) -> ReminderMoment {
        let millis = (date.timeIntervalSince1970 * 1000).rounded()
        guard millis.isFinite, millis >= Double(Int.min), millis <= Double(Int.max) else {
            return .none
        }
        return ReminderSchedule.momentOfEpoch(epochMillis: Int(millis), zoneOffsetMillis: zoneOffsetMillis)
    }

    /// 时刻的**数据文本**（`2026-10-05 09:00`）。
    ///
    /// 为什么不用系统的日期格式化器：这串是要**跟契约的日期形态对齐**的数据（`YYYY-MM-DD` +
    /// 24 小时制时刻），换语言换时区都不该变形；语言相关的排版（「10月5日 周一 09:00」）属界面层、
    /// 由界面按当前语言排 —— 与本文件无关。
    public static func momentText(_ moment: ReminderMoment) -> String {
        guard isRepresentable(moment) else { return "" }
        return "\(moment.date) \(clock(of: moment.minute))"
    }

    /// 只出**几点**（`09:00`）——「每天 / 每周几点」这类句子里用的那一半。
    ///
    /// 为什么不带上日期：`interval` / `weekly` 的 `anchorDate` 在契约 §2.10 里是「**首次允许的
    /// 最早日期**」（调度用的下界，不是「第一次响的日子」），把它摆进句子会说出一句用户没打算的
    /// 「从某天起」；真正要的那个日期由 ``nextText(_:language:)`` 单独说。
    public static func clockText(_ moment: ReminderMoment) -> String {
        guard isRepresentable(moment) else { return "" }
        return clock(of: moment.minute)
    }

    private static func clock(of minute: Int) -> String {
        let hour = minute / 60
        let rest = minute % 60
        let hh = hour < 10 ? "0\(hour)" : "\(hour)"
        let mm = rest < 10 ? "0\(rest)" : "\(rest)"
        return "\(hh):\(mm)"
    }

    // MARK: - 一键挂提醒（档位 → 规则）

    /// 把「一条待办的截止时刻 + 一个档位」翻成一条 `ReminderSpec`（**唯一一处**）。
    ///
    /// 三条口径：
    ///  ① **没有截止时间 ⇒ 不能一键挂**（`.needsDueDate`）—— 「有截止时间的任务一键挂提醒」这句话里
    ///     的「有」不是形容词，是**前提**；
    ///  ② **一次性规则**：`rule = once`、`anchorDate` = 档位对应的那一天、`minuteOfDay` = 那一天的第几分钟；
    ///     `intervalCount` / `intervalUnit` / `weekdays` / `untilDate` 一律写空 —— `once` 不吃它们，
    ///     写一个「看着像数据」的默认值会让库里出现一条字段与规则不符的行；
    ///  ③ **跨零点照算**：提前量是**从那一刻往回退的分钟数**，退到前一天就落在前一天
    ///     （00:20 的截止时间「提前 1 小时」= 前一天 23:20，不是当天 23:20、也不是 00:20）。
    public static func attachment(
        dueAt: Date?,
        preset: ReminderPreset = ReminderPreset.presetDefault,
        zoneOffsetMillis: Int
    ) -> ReminderAttachment {
        guard let dueAt else { return .needsDueDate }
        let dueMoment = moment(of: dueAt, zoneOffsetMillis: zoneOffsetMillis)
        guard isRepresentable(dueMoment) else { return .outOfRange }
        let dueEpoch = ReminderSchedule.toEpoch(moment: dueMoment, zoneOffsetMillis: zoneOffsetMillis)
        guard dueEpoch >= 0 else { return .outOfRange }
        let fireMoment = ReminderSchedule.momentOfEpoch(
            epochMillis: dueEpoch - preset.leadMinutes * 60_000,
            zoneOffsetMillis: zoneOffsetMillis
        )
        guard isRepresentable(fireMoment) else { return .outOfRange }
        let spec = ReminderSpec(
            rule: ReminderRule.once.rawValue,
            anchorDate: fireMoment.date,
            minuteOfDay: fireMoment.minute
        )
        return .ready(spec: spec, preset: preset, moment: fireMoment)
    }

    /// 已经挂着的那一条是**哪一档**（档位回显的**唯一出处**，界面入口半）。
    ///
    /// 怎么认：拿四个档位各算一次 `attachment`，与那一条的规则**逐字段比** —— 选中的档位不是
    /// 「另存一个字段」（库里没有档位列，也不该有：档位是派生量），而是「**能不能被同一个算式重算出来**」。
    /// 都重算不出来（那一条是 `weekly` / `interval`，或截止时间后来被改过）⇒ `nil`：
    /// 界面上一档都不选中，但那条规则照样按原文显示，不假装它是某一档。
    public static func preset(
        of spec: ReminderSpec,
        dueAt: Date?,
        zoneOffsetMillis: Int
    ) -> ReminderPreset? {
        ReminderPreset.allCases.first { candidate in
            attachment(dueAt: dueAt, preset: candidate, zoneOffsetMillis: zoneOffsetMillis).spec == spec
        }
    }

    // MARK: - 规则 → 一句话

    /// 把一条规则说成人话（**中英各一版**，句子只在语言表里）；规则认不出 ⇒ `nil`。
    ///
    /// 两条口径：
    ///  ① **一次性**说「哪天几点」；**重复类**（间隔 / 每周）只说「几点」——
    ///     `anchorDate` 对重复类在契约 §2.10 里是「首次允许的最早日期」，不是要摆给用户看的日期
    ///     （理由见 ``clockText(_:)``；下一次的那个日期由 ``nextText(_:language:)`` 说）；
    ///  ② **终止日**套在整句外面（`直到 …`），且终止日本身必须是真日历日 —— 写错一个终止日
    ///     不许被显示成「直到 2026-02-30」。
    ///
    /// 为什么返回整句而不是「键 + 实参」：这一个句子里的实参**本身也是译文**（星期名来自语言表），
    /// 交给视图拼就会在视图里出现第二套拼装逻辑（而它断言不到）。Core 侧已有同形先例
    /// （`Core/MySQLWording.swift` / `Core/ConnectionInfoText.swift`：拿 `language` 参数、直接出句）。
    public static func summary(_ spec: ReminderSpec, language: AppLanguage) -> String? {
        guard let rule = ReminderRule.normalized(spec.rule) else { return nil }
        let anchorDay = ReminderSchedule.dayOf(spec.anchorDate)
        guard anchorDay >= 0, (0..<1440).contains(spec.minuteOfDay) else { return nil }
        let moment = ReminderMoment(date: spec.anchorDate, minute: spec.minuteOfDay)

        let body: String
        switch rule {
        case .once:
            body = LocalizedStrings.format(.reminderSummaryOnce, language: language, momentText(moment))
        case .interval:
            guard let unit = ReminderUnit.normalized(spec.intervalUnit), spec.intervalCount > 0 else {
                return nil
            }
            let key: LKey = unit == .day ? .reminderSummaryEveryDay : .reminderSummaryEveryWeek
            body = LocalizedStrings.format(
                key, language: language, spec.intervalCount, clockText(moment)
            )
        case .weekly:
            let days = ReminderSpec.weekdays(from: spec.weekdaysText)
            guard !days.isEmpty else { return nil }
            let names = days.compactMap { weekdayKey($0) }.map { LocalizedStrings.text($0, language: language) }
            guard names.count == days.count else { return nil }
            let separator = LocalizedStrings.text(.reminderListSeparator, language: language)
            body = LocalizedStrings.format(
                .reminderSummaryWeekly, language: language, names.joined(separator: separator), clockText(moment)
            )
        }

        guard !spec.untilDate.isEmpty else { return body }
        guard ReminderSchedule.dayOf(spec.untilDate) >= 0 else { return nil }
        return LocalizedStrings.format(.reminderSummaryUntil, language: language, body, spec.untilDate)
    }

    /// ISO 星期（1…7）→ 语言表键。
    ///
    /// **不写死「1 就是第一个键」**：键与编号的对应关系在 `TodoCalendar` 那一对
    /// （`weekdayOrder` / `weekdayHeaderKeys`）里，这里按下标找 —— 只此一处，
    /// 免得日历表头改了星期起算日而这里还按 1 去索引。
    public static func weekdayKey(_ isoWeekday: Int) -> LKey? {
        guard let index = TodoCalendar.weekdayOrder.firstIndex(of: isoWeekday),
              index < TodoCalendar.weekdayHeaderKeys.count else {
            return nil
        }
        return TodoCalendar.weekdayHeaderKeys[index]
    }

    /// 「下一次什么时候到」那一句；`expired` / `invalid` 各出各的话（**不返回空串**）。
    public static func nextText(_ plan: ReminderPlan, language: AppLanguage) -> String? {
        switch plan.state {
        case .pending:
            return LocalizedStrings.format(
                .reminderNext, language: language, momentText(plan.due)
            )
        case .expired:
            return LocalizedStrings.text(.reminderExpired, language: language)
        case .invalid:
            return LocalizedStrings.text(.reminderRuleUnknown, language: language)
        }
    }

    // MARK: - 排不排（权限 × 求解结果）

    /// 该不该把这条提醒交给系统通知（**唯一的判定处**）。
    ///
    /// 五条口径：
    ///  ① **没问过权限 ⇒ 先问、这一轮不排**（`.askPermission`）—— 悄悄弹一次系统授权框、
    ///     又把没排上的提醒当成排上了，是这一族最常见的假成功；
    ///  ② **被拒 ⇒ 不排 + 说去哪开**（`.inactive(.reminderPermissionDenied)`）：静默不响是
    ///     用户最难查的那种「提醒不见了」；
    ///  ③ **已授权**：`pending` 才排（`triggerEpochMillis` 由 `toEpoch` 现算 —— 时区变化由它吸收，
    ///     **不落库**）；`expired` / `invalid` 不排，各出各的话；
    ///  ④ **算不出瞬间**（`toEpoch` 回负）⇒ 不排，且**不假装**规则认不出之外的原因（仍是那句话）；
    ///  ⑤ 判定只看「权限档 × 求解结果」，**不看「现在几点」**：参照时刻是调用方给的
    ///     （与 `ReminderSchedule` 同一条纪律，界面每画一次就按当时的参照重算）。
    public static func notificationDecision(
        permission: ReminderPermission,
        plan: ReminderPlan,
        zoneOffsetMillis: Int
    ) -> ReminderNotificationDecision {
        switch permission {
        case .notDetermined: return .askPermission
        case .denied: return .inactive(.reminderPermissionDenied)
        case .authorized:
            guard plan.state == .pending else {
                return .inactive(plan.state == .expired ? .reminderExpired : .reminderRuleUnknown)
            }
            let epoch = ReminderSchedule.toEpoch(moment: plan.due, zoneOffsetMillis: zoneOffsetMillis)
            guard epoch >= 0 else { return .inactive(.reminderRuleUnknown) }
            return .schedule(triggerEpochMillis: epoch)
        }
    }

    // MARK: - 到点那条通知的内容

    /// 通知标题：**任务标题原样**（空白 ⇒ `nil`，由视图用语言表兜底，`notesUntitled` 同族口径）。
    ///
    /// 为什么要原样而不是套一句「待办提醒：%@」：到点那一刻用户只看得到通知，标题就是**任务本身**，
    /// 套一层前缀反而把真正要看的那几个字挤掉；空标题那一条的重读口径与清单行**同一处**
    /// （`TodoPresentation.title`），这里只做「有没有」的判断。
    public static func notificationTitle(_ todoTitle: String?) -> String? {
        guard let todoTitle else { return nil }
        return todoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : todoTitle
    }

    /// 通知正文：`截止时间 2026-10-05 09:00`；时刻不可表示 ⇒ `nil`（宁可只出标题，不出一句假的）。
    public static func notificationBody(_ moment: ReminderMoment, language: AppLanguage) -> String? {
        let text = momentText(moment)
        guard !text.isEmpty else { return nil }
        return LocalizedStrings.format(.reminderNotificationBody, language: language, text)
    }
}
