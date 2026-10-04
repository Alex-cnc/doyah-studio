import XCTest
@testable import DoyahCore

// 队列 `L-100` 落法 ④ 的**界面半第一片（Core 半）**：提醒的界面判定与文案。
//
// 这一片落的三件事：① **档位 → 规则**（`ReminderPreset` / `ReminderPresentation.attachment`：
// 「到点 / 提前 15 分钟 / 提前 1 小时 / 提前 1 天」翻成一条 `once` 的 `ReminderSpec`）；
// ② **权限 → 排不排**（`ReminderPermission` × `ReminderPlan` → `ReminderNotificationDecision`：
// 没问过就先问、被拒就说不排 + 去哪开、已授权只有「有待发时刻」才排）；
// ③ **规则 → 一句话**（`summary` / `nextText` / `notificationBody` / 标题）。
//
// 三条纪律：
//   ① **时刻用字面量**（`2026-10-05 09:00Z` = `1_791_190_800_000` 是独立算出来的），
//      不拿被测函数去造期望值；
//   ② **时区偏移是参数**（本层不读系统时区）⇒ 同一瞬间在 UTC / UTC+8 / UTC-5 下**各有各的**期望，
//      这是「提前 1 天算错一天」那一族唯一能被钉住的地方；
//   ③ **跨零点是重点**（`00:20` 的截止时间「提前 1 小时」= **前一天** `23:20`），
//      这条错的症状是「提醒早响一天」，而界面上看不出来。
final class ReminderPresentationTests: XCTestCase {

    /// `2026-10-05 09:00Z`（毫秒）。**独立算出**的字面量，不由被测函数生成。
    private let dueMorning: Date = Date(timeIntervalSince1970: 1_791_190_800)
    /// `2026-10-05 00:20Z`。
    private let dueLateNight: Date = Date(timeIntervalSince1970: 1_791_159_600)
    /// `1970-01-01 00:10Z`（提前 1 天就没法表示了）。
    private let dueEpochEdge: Date = Date(timeIntervalSince1970: 600)

    private let utc = 0
    private let utcPlus8 = 8 * 60 * 60 * 1000
    private let utcMinus5 = -5 * 60 * 60 * 1000

    private func moment(_ date: String, _ minute: Int) -> ReminderMoment {
        ReminderMoment(date: date, minute: minute)
    }

    // MARK: - 档位

    func testPresetLeadMinutesAndKeys() {
        XCTAssertEqual(ReminderPreset.allCases.count, 4)
        XCTAssertEqual(ReminderPreset.presetDefault, .atDue)
        XCTAssertEqual(ReminderPreset.atDue.leadMinutes, 0)
        XCTAssertEqual(ReminderPreset.before15m.leadMinutes, 15)
        XCTAssertEqual(ReminderPreset.before1h.leadMinutes, 60)
        XCTAssertEqual(ReminderPreset.before1d.leadMinutes, 24 * 60)
        XCTAssertEqual(ReminderPreset.before1h.key, .reminderPresetBefore1h)
        XCTAssertEqual(ReminderPreset.before1d.key, .reminderPresetBefore1d)
        // 四档各有各的句子（键不许撞）。
        XCTAssertEqual(Set(ReminderPreset.allCases.map(\.key)).count, 4)
        // 取值即协议：`known` 与枚举一一对应。
        XCTAssertEqual(ReminderPreset.known.sorted(), ReminderPreset.allCases.map(\.rawValue).sorted())
    }

    func testPresetNormalizedRejectsUnknown() {
        XCTAssertEqual(ReminderPreset.normalized("before1d"), .before1d)
        XCTAssertNil(ReminderPreset.normalized(nil))
        XCTAssertNil(ReminderPreset.normalized(""))
        // 认不出就当没给（不回落成一档「看着像」的提前量）。
        XCTAssertNil(ReminderPreset.normalized("tomorrow"))
    }

    func testPermissionNormalizedFallsBackToNotDetermined() {
        XCTAssertEqual(ReminderPermission.normalized("authorized"), .authorized)
        XCTAssertEqual(ReminderPermission.normalized("denied"), .denied)
        // 认不出 ⇒ 还没问过（安全侧：这一格的动作是「先问、不排」）。
        XCTAssertEqual(ReminderPermission.normalized(nil), .notDetermined)
        XCTAssertEqual(ReminderPermission.normalized("maybe"), .notDetermined)
    }

    // MARK: - 一键挂提醒

    func testAttachmentNeedsDueDateWhenTheTodoHasNone() {
        let result = ReminderPresentation.attachment(dueAt: nil, zoneOffsetMillis: utc)
        XCTAssertEqual(result, .needsDueDate)
        XCTAssertNil(result.spec)
        XCTAssertNil(result.preset)
        XCTAssertEqual(result.reasonKey, .reminderNeedsDue)
        XCTAssertEqual(result.moment, .none)
    }

    func testAttachmentAtDueKeepsTheDueMomentItself() throws {
        let result = ReminderPresentation.attachment(dueAt: dueMorning, preset: .atDue, zoneOffsetMillis: utc)
        XCTAssertEqual(result.moment, moment("2026-10-05", 540))
        let spec = try XCTUnwrap(result.spec)
        XCTAssertEqual(spec.rule, ReminderRule.once.rawValue)
        XCTAssertEqual(spec.anchorDate, "2026-10-05")
        XCTAssertEqual(spec.minuteOfDay, 540)
        // 一次性规则不吃这四个字段 —— 一律空，而不是编一个默认值。
        XCTAssertEqual(spec.intervalCount, 0)
        XCTAssertEqual(spec.intervalUnit, "")
        XCTAssertEqual(spec.weekdays, [])
        XCTAssertEqual(spec.untilDate, "")
        XCTAssertEqual(result.preset, .atDue)
        XCTAssertNil(result.reasonKey)
    }

    func testAttachmentLeadTimesStepBackFromTheDueMinute() {
        let quarter = ReminderPresentation.attachment(dueAt: dueMorning, preset: .before15m, zoneOffsetMillis: utc)
        XCTAssertEqual(quarter.moment, moment("2026-10-05", 525))
        let hour = ReminderPresentation.attachment(dueAt: dueMorning, preset: .before1h, zoneOffsetMillis: utc)
        XCTAssertEqual(hour.moment, moment("2026-10-05", 480))
        let day = ReminderPresentation.attachment(dueAt: dueMorning, preset: .before1d, zoneOffsetMillis: utc)
        XCTAssertEqual(day.moment, moment("2026-10-04", 540))
    }

    func testAttachmentCrossesMidnightToTheDayBefore() {
        // `2026-10-05 00:20` 提前 1 小时 = **前一天** 23:20（不是当天 23:20、也不是 00:20）。
        let result = ReminderPresentation.attachment(dueAt: dueLateNight, preset: .before1h, zoneOffsetMillis: utc)
        XCTAssertEqual(result.moment, moment("2026-10-04", 23 * 60 + 20))
        XCTAssertEqual(result.spec?.anchorDate, "2026-10-04")
        XCTAssertEqual(result.spec?.minuteOfDay, 1400)
    }

    func testAttachmentUsesTheOffsetTheCallerGives() {
        // 同一个瞬间：UTC 下是 09:00，UTC+8 下是本机 17:00，UTC-5 下是本机 04:00。
        XCTAssertEqual(
            ReminderPresentation.moment(of: dueMorning, zoneOffsetMillis: utc),
            moment("2026-10-05", 540)
        )
        XCTAssertEqual(
            ReminderPresentation.moment(of: dueMorning, zoneOffsetMillis: utcPlus8),
            moment("2026-10-05", 1020)
        )
        XCTAssertEqual(
            ReminderPresentation.moment(of: dueMorning, zoneOffsetMillis: utcMinus5),
            moment("2026-10-05", 240)
        )
        // 挂提醒那一半同样跟着偏移走。
        let plus8 = ReminderPresentation.attachment(dueAt: dueMorning, preset: .atDue, zoneOffsetMillis: utcPlus8)
        XCTAssertEqual(plus8.moment, moment("2026-10-05", 1020))
    }

    func testAttachmentRefusesMomentsBeforeNineteenSeventy() {
        // 提前 1 天把 `1970-01-01 00:10` 退到 1969-12-31 ⇒ 契约的日期形态表示不了 ⇒ 不编日期。
        let result = ReminderPresentation.attachment(dueAt: dueEpochEdge, preset: .before1d, zoneOffsetMillis: utc)
        XCTAssertEqual(result, .outOfRange)
        XCTAssertNil(result.spec)
        XCTAssertEqual(result.reasonKey, .reminderOutOfRange)
        // 同一个截止时刻「到点」是表示得了的（这一条判的是提前量，不是输入本身）。
        XCTAssertEqual(
            ReminderPresentation.attachment(dueAt: dueEpochEdge, preset: .atDue, zoneOffsetMillis: utc).moment,
            moment("1970-01-01", 10)
        )
    }

    func testAttachmentSpecIsSolvableByTheSchedulingHalf() throws {
        // 界面半算出来的规则，必须能被调度半（契约 §3.12）算出「下一次」——
        // 否则就是「库里有一行、永远不响」。
        let result = ReminderPresentation.attachment(dueAt: dueMorning, preset: .atDue, zoneOffsetMillis: utc)
        let spec = try XCTUnwrap(result.spec)
        let before = ReminderSchedule.next(spec: spec, fromDate: "2026-10-05", fromMinute: 539)
        XCTAssertEqual(before.state, .pending)
        XCTAssertEqual(before.due, moment("2026-10-05", 540))
        // 参照时刻正好落在那一刻 ⇒ 严格晚于 ⇒ 一次性规则已用尽。
        let at = ReminderSchedule.next(spec: spec, fromDate: "2026-10-05", fromMinute: 540)
        XCTAssertEqual(at.state, .expired)
    }

    // MARK: - 一句话

    func testSummaryOnceInBothLanguages() {
        let spec = ReminderSpec(rule: "once", anchorDate: "2026-10-05", minuteOfDay: 540)
        XCTAssertEqual(ReminderPresentation.summary(spec, language: .simplifiedChinese), "2026-10-05 09:00 提醒一次")
        XCTAssertEqual(ReminderPresentation.summary(spec, language: .english), "Once at 2026-10-05 09:00")
    }

    func testSummaryIntervalUsesANumberSlotThatRenders() {
        // 数字槽写 `%@` 会印出 `(null)` —— 这一条盯的就是那件事。
        // 重复类只说「几点」：`anchorDate` 对它们是「首次允许的最早日期」（调度下界），不摆进句子。
        let days = ReminderSpec(rule: "interval", anchorDate: "2026-10-01", minuteOfDay: 540,
                                intervalCount: 3, intervalUnit: "day")
        XCTAssertEqual(ReminderPresentation.summary(days, language: .simplifiedChinese),
                       "每 3 天 09:00 提醒")
        XCTAssertEqual(ReminderPresentation.summary(days, language: .english),
                       "Every 3 days at 09:00")
        let weeks = ReminderSpec(rule: "interval", anchorDate: "2026-10-01", minuteOfDay: 540,
                                 intervalCount: 2, intervalUnit: "week")
        XCTAssertEqual(ReminderPresentation.summary(weeks, language: .simplifiedChinese),
                       "每 2 周 09:00 提醒")
        XCTAssertEqual(ReminderPresentation.summary(weeks, language: .english),
                       "Every 2 weeks at 09:00")
        // 单位缺省按天（契约 §2.10）。
        let defaulted = ReminderSpec(rule: "interval", anchorDate: "2026-10-01", minuteOfDay: 540,
                                     intervalCount: 5, intervalUnit: "")
        XCTAssertEqual(ReminderPresentation.summary(defaulted, language: .simplifiedChinese),
                       "每 5 天 09:00 提醒")
    }

    func testSummaryWeeklyListsWeekdaysInTheTableLanguage() {
        // 脏值输入（乱序 + 重复 + 越界）⇒ 归一后升序，且分隔符跟着语言走。
        let spec = ReminderSpec(rule: "weekly", anchorDate: "2026-10-01", minuteOfDay: 540,
                                weekdays: [7, 1, 3, 1, 9])
        XCTAssertEqual(ReminderPresentation.summary(spec, language: .simplifiedChinese),
                       "每周周一、周三、周日 09:00 提醒")
        XCTAssertEqual(ReminderPresentation.summary(spec, language: .english),
                       "Weekly on Mon, Wed, Sun at 09:00")
    }

    func testSummaryAppendsTheTerminationDay() {
        let spec = ReminderSpec(rule: "once", anchorDate: "2026-10-05", minuteOfDay: 540,
                                untilDate: "2026-12-31")
        XCTAssertEqual(ReminderPresentation.summary(spec, language: .simplifiedChinese),
                       "2026-10-05 09:00 提醒一次（直到 2026-12-31）")
        XCTAssertEqual(ReminderPresentation.summary(spec, language: .english),
                       "Once at 2026-10-05 09:00 until 2026-12-31")
    }

    func testSummaryReturnsNilInsteadOfGuessing() {
        // 认不出的规则 / 不存在的日期 / 越界的分钟 / 空的星期集合 / 终止日为假 / 间隔次数为 0。
        XCTAssertNil(ReminderPresentation.summary(
            ReminderSpec(rule: "everyOtherTuesday", anchorDate: "2026-10-05", minuteOfDay: 540),
            language: .simplifiedChinese
        ))
        XCTAssertNil(ReminderPresentation.summary(
            ReminderSpec(rule: "once", anchorDate: "2026-02-30", minuteOfDay: 540),
            language: .simplifiedChinese
        ))
        XCTAssertNil(ReminderPresentation.summary(
            ReminderSpec(rule: "once", anchorDate: "2026-10-05", minuteOfDay: 1440),
            language: .simplifiedChinese
        ))
        XCTAssertNil(ReminderPresentation.summary(
            ReminderSpec(rule: "weekly", anchorDate: "2026-10-05", minuteOfDay: 540, weekdays: [9]),
            language: .simplifiedChinese
        ))
        XCTAssertNil(ReminderPresentation.summary(
            ReminderSpec(rule: "once", anchorDate: "2026-10-05", minuteOfDay: 540, untilDate: "2026-02-30"),
            language: .simplifiedChinese
        ))
        XCTAssertNil(ReminderPresentation.summary(
            ReminderSpec(rule: "interval", anchorDate: "2026-10-05", minuteOfDay: 540,
                         intervalCount: 0, intervalUnit: "day"),
            language: .simplifiedChinese
        ))
        XCTAssertNil(ReminderPresentation.summary(
            ReminderSpec(rule: "interval", anchorDate: "2026-10-05", minuteOfDay: 540,
                         intervalCount: 2, intervalUnit: "fortnight"),
            language: .simplifiedChinese
        ))
    }

    func testMomentTextIsTheContractShape() {
        XCTAssertEqual(ReminderPresentation.momentText(moment("2026-10-05", 540)), "2026-10-05 09:00")
        XCTAssertEqual(ReminderPresentation.momentText(moment("2026-10-05", 5)), "2026-10-05 00:05")
        XCTAssertEqual(ReminderPresentation.momentText(moment("2026-10-05", 1439)), "2026-10-05 23:59")
        // 没有时刻 / 表示不了的日期 ⇒ 空串（不编一个 `1970-01-01 00:00` 出来）。
        XCTAssertEqual(ReminderPresentation.momentText(.none), "")
        XCTAssertEqual(ReminderPresentation.momentText(moment("1969-12-31", 0)), "")
        // 只出几点的那一半（「每天 / 每周几点」那类句子用）。
        XCTAssertEqual(ReminderPresentation.clockText(moment("2026-10-05", 540)), "09:00")
        XCTAssertEqual(ReminderPresentation.clockText(moment("2026-10-05", 1439)), "23:59")
        XCTAssertEqual(ReminderPresentation.clockText(.none), "")
    }

    func testMomentRoundTripUsesTheGivenOffset() {
        XCTAssertEqual(ReminderPresentation.moment(of: dueMorning, zoneOffsetMillis: utc), moment("2026-10-05", 540))
        XCTAssertEqual(
            ReminderSchedule.toEpoch(moment: moment("2026-10-05", 540), zoneOffsetMillis: utc),
            1_791_190_800_000
        )
        // 溢出边界的毫秒数回空值，不抛错。
        XCTAssertEqual(ReminderPresentation.moment(of: Date(timeIntervalSince1970: 1e18), zoneOffsetMillis: utc), .none)
    }

    func testWeekdayKeyFollowsTheCalendarOrder() {
        XCTAssertEqual(ReminderPresentation.weekdayKey(1), .todoWeekdayMonday)
        XCTAssertEqual(ReminderPresentation.weekdayKey(7), .todoWeekdaySunday)
        XCTAssertNil(ReminderPresentation.weekdayKey(0))
        XCTAssertNil(ReminderPresentation.weekdayKey(8))
    }

    func testNextTextHasThreeEndings() {
        let spec = ReminderSpec(rule: "once", anchorDate: "2026-10-05", minuteOfDay: 540)
        let pending = ReminderSchedule.next(spec: spec, fromDate: "2026-10-01", fromMinute: 0)
        XCTAssertEqual(ReminderPresentation.nextText(pending, language: .simplifiedChinese), "下次 2026-10-05 09:00")
        XCTAssertEqual(ReminderPresentation.nextText(pending, language: .english), "Next 2026-10-05 09:00")
        let expired = ReminderSchedule.next(spec: spec, fromDate: "2026-10-06", fromMinute: 0)
        XCTAssertEqual(ReminderPresentation.nextText(expired, language: .simplifiedChinese), "已经结束了")
        let invalid = ReminderSchedule.next(
            spec: ReminderSpec(rule: "nope", anchorDate: "2026-10-05", minuteOfDay: 540),
            fromDate: "2026-10-01", fromMinute: 0
        )
        XCTAssertEqual(ReminderPresentation.nextText(invalid, language: .simplifiedChinese), "这条提醒的规则认不出来")
    }

    // MARK: - 排不排

    func testDecisionAsksForPermissionBeforeScheduling() {
        let spec = ReminderSpec(rule: "once", anchorDate: "2026-10-05", minuteOfDay: 540)
        let plan = ReminderSchedule.next(spec: spec, fromDate: "2026-10-01", fromMinute: 0)
        XCTAssertEqual(
            ReminderPresentation.notificationDecision(permission: .notDetermined, plan: plan, zoneOffsetMillis: utc),
            .askPermission
        )
        XCTAssertEqual(
            ReminderPresentation.notificationDecision(permission: .denied, plan: plan, zoneOffsetMillis: utc),
            .inactive(.reminderPermissionDenied)
        )
    }

    func testDecisionSchedulesOnlyThePendingOneWhenAuthorized() {
        let spec = ReminderSpec(rule: "once", anchorDate: "2026-10-05", minuteOfDay: 540)
        let pending = ReminderSchedule.next(spec: spec, fromDate: "2026-10-01", fromMinute: 0)
        let decision = ReminderPresentation.notificationDecision(
            permission: .authorized, plan: pending, zoneOffsetMillis: utc
        )
        XCTAssertTrue(decision.isScheduled)
        // 触发瞬间 = 那一刻的毫秒时间戳（独立字面量）。
        XCTAssertEqual(decision, .schedule(triggerEpochMillis: 1_791_190_800_000))
        XCTAssertNil(decision.reasonKey)

        let expired = ReminderSchedule.next(spec: spec, fromDate: "2026-10-06", fromMinute: 0)
        XCTAssertEqual(
            ReminderPresentation.notificationDecision(permission: .authorized, plan: expired, zoneOffsetMillis: utc),
            .inactive(.reminderExpired)
        )
        let invalid = ReminderSchedule.next(
            spec: ReminderSpec(rule: "nope", anchorDate: "2026-10-05", minuteOfDay: 540),
            fromDate: "2026-10-01", fromMinute: 0
        )
        XCTAssertEqual(
            ReminderPresentation.notificationDecision(permission: .authorized, plan: invalid, zoneOffsetMillis: utc),
            .inactive(.reminderRuleUnknown)
        )
    }

    // MARK: - 通知的内容

    func testNotificationTitleIsTheTodoTitleItself() {
        XCTAssertNil(ReminderPresentation.notificationTitle(nil))
        XCTAssertNil(ReminderPresentation.notificationTitle("   "))
        XCTAssertEqual(ReminderPresentation.notificationTitle("买牛奶"), "买牛奶")
        // 首尾空白**不删**（与 `TodoPresentation.title` 同口径：标题里的空白是用户写的）。
        XCTAssertEqual(ReminderPresentation.notificationTitle(" 买牛奶 "), " 买牛奶 ")
    }

    func testNotificationBodyUsesTheMomentText() {
        XCTAssertEqual(
            ReminderPresentation.notificationBody(moment("2026-10-05", 540), language: .simplifiedChinese),
            "截止时间 2026-10-05 09:00"
        )
        XCTAssertEqual(
            ReminderPresentation.notificationBody(moment("2026-10-05", 540), language: .english),
            "Due 2026-10-05 09:00"
        )
        // 时刻表示不了 ⇒ 宁可只出标题，也不出一句假的。
        XCTAssertNil(ReminderPresentation.notificationBody(.none, language: .simplifiedChinese))
    }

    // MARK: - 这一层的形状

    func testSourceKeepsEveryPlatformApiOut() throws {
        // 本层要能在别的平台上被同样的用例跑（与 `ReminderSchedule` 同一条纪律）：
        // 系统时钟 / 系统时区 / 日期格式化器 / 通知框架，一个都不许出现在这个文件里。
        let text = try source("Core/ReminderPresentation.swift")
        for token in ["Date()", "TimeZone", "DateFormatter", "UNUserNotification", "Calendar.current"] {
            XCTAssertFalse(text.contains(token), "Core/ReminderPresentation.swift 里出现了 \(token)")
        }
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}
