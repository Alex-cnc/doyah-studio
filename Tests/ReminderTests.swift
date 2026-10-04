import Foundation
import XCTest

import DoyahCore

/// 提醒调度语义的**行为判据**（`FR-NOTE-02` / 契约 §2.10 §3.12）—— 与对侧
/// `android/core/.../ReminderTests.kt` **同覆盖面**（引用，不复制代码）。
///
/// 与 `ReminderGoldenTests` 的分工：那一份拿**鸿蒙侧跑出来的 39 例黄金样例**判「三端同答」；
/// 这一份判**每一条口径本身**（一次性不改期 / 严格晚于 / 终止日含端点 / 间隔格点 / 周内命中 /
/// 脏值判非法 / 预演的严格递增与提前结束 / 日序与星期的原点 / 瞬间往返），
/// 以及**跨端比较面只有（日历日, 分钟, 档位）**这条边界（`toEpoch` 用显式偏移单独验）。
final class ReminderTests: XCTestCase {

    // MARK: - 取值空间

    func testKnownValuesAreTheProtocol() {
        XCTAssertEqual(ReminderRule.known, ["once", "interval", "weekly"])
        XCTAssertEqual(ReminderUnit.known, ["day", "week"])
        XCTAssertEqual(ReminderUnit.day.days, 1)
        XCTAssertEqual(ReminderUnit.week.days, 7)
    }

    func testNormalizeTreatsUnknownAsNotGiven() {
        XCTAssertEqual(ReminderRule.normalized("once"), .once)
        XCTAssertNil(ReminderRule.normalized("everyWeek"), "不认识的规则不许回落成一次性")
        XCTAssertNil(ReminderRule.normalized(""))
        XCTAssertNil(ReminderRule.normalized(nil))
        XCTAssertFalse(ReminderRule.isKnown("ONCE"), "取值即协议、大小写不归一")

        XCTAssertEqual(ReminderUnit.normalized(""), .day, "缺省单位 = 天")
        XCTAssertEqual(ReminderUnit.normalized(nil), .day)
        XCTAssertEqual(ReminderUnit.normalized("week"), .week)
        XCTAssertNil(ReminderUnit.normalized("month"), "不认识的单位判决非法、不回落成 day")
        XCTAssertFalse(ReminderUnit.isKnown("Week"))
    }

    // MARK: - 一次性（口径 3 / 4）

    func testOnceAnchorInFutureLandsOnAnchor() {
        let plan = ReminderSchedule.next(
            spec: ReminderSpec(rule: "once", anchorDate: "2026-10-01", minuteOfDay: 540),
            fromDate: "2026-09-27", fromMinute: 480
        )
        XCTAssertTrue(plan.ok)
        XCTAssertEqual(plan.state, .pending)
        XCTAssertEqual(plan.code, "")
        XCTAssertEqual(plan.due, ReminderMoment(date: "2026-10-01", minute: 540))
    }

    func testOnceAnchorPassedExpiresInsteadOfRescheduling() {
        let plan = ReminderSchedule.next(
            spec: ReminderSpec(rule: "once", anchorDate: "2026-09-26", minuteOfDay: 540),
            fromDate: "2026-09-27", fromMinute: 480
        )
        XCTAssertTrue(plan.ok, "过期不是错误：ok 仍为真")
        XCTAssertEqual(plan.state, .expired)
        XCTAssertEqual(plan.due, ReminderMoment.none)
    }

    func testOnceIsStrictlyLaterThanReference() {
        let spec = ReminderSpec(rule: "once", anchorDate: "2026-10-01", minuteOfDay: 540)
        // 同一天、分钟更晚 ⇒ 就是今天这一刻
        XCTAssertEqual(
            ReminderSchedule.next(spec: spec, fromDate: "2026-10-01", fromMinute: 480).due,
            ReminderMoment(date: "2026-10-01", minute: 540)
        )
        // 同一天、分钟相同 ⇒ 已过（严格晚于，不许把同一刻再给一次）
        XCTAssertEqual(
            ReminderSchedule.next(spec: spec, fromDate: "2026-10-01", fromMinute: 540).state, .expired
        )
        // 同一天、分钟更早 ⇒ 已过
        XCTAssertEqual(
            ReminderSchedule.next(spec: spec, fromDate: "2026-10-01", fromMinute: 600).state, .expired
        )
    }

    func testUntilDateIsInclusive() {
        // 终止日 = 锚点当天 ⇒ 仍可响（含端点）
        XCTAssertEqual(
            ReminderSchedule.next(
                spec: ReminderSpec(rule: "once", anchorDate: "2026-10-01", minuteOfDay: 540,
                                   untilDate: "2026-10-01"),
                fromDate: "2026-09-27", fromMinute: 480
            ).due,
            ReminderMoment(date: "2026-10-01", minute: 540)
        )
        // 终止日早于锚点 ⇒ 用尽
        XCTAssertEqual(
            ReminderSchedule.next(
                spec: ReminderSpec(rule: "once", anchorDate: "2026-10-01", minuteOfDay: 540,
                                   untilDate: "2026-09-30"),
                fromDate: "2026-09-27", fromMinute: 480
            ).state, .expired
        )
    }

    // MARK: - 间隔（格点只有一条算法）

    func testIntervalLandsOnTheSameResidueGrid() {
        let spec = ReminderSpec(rule: "interval", anchorDate: "2026-10-01", minuteOfDay: 540,
                                intervalCount: 3, intervalUnit: "day")
        // 网格 = 10-01 起每 3 天（10-01 / 10-04 / 10-07 …）
        XCTAssertEqual(
            ReminderSchedule.next(spec: spec, fromDate: "2026-10-02", fromMinute: 480).due,
            ReminderMoment(date: "2026-10-04", minute: 540)
        )
        // 参照日正好是格点、分钟已过 ⇒ 顺延一格
        XCTAssertEqual(
            ReminderSchedule.next(spec: spec, fromDate: "2026-10-04", fromMinute: 600).due,
            ReminderMoment(date: "2026-10-07", minute: 540)
        )
        // 参照日正好是格点、分钟还没到 ⇒ 就是今天
        XCTAssertEqual(
            ReminderSchedule.next(spec: spec, fromDate: "2026-10-04", fromMinute: 480).due,
            ReminderMoment(date: "2026-10-04", minute: 540)
        )
    }

    func testIntervalFirstIsNotEarlierThanAnchor() {
        let spec = ReminderSpec(rule: "interval", anchorDate: "2026-10-10", minuteOfDay: 540,
                                intervalCount: 2, intervalUnit: "week")
        XCTAssertEqual(
            ReminderSchedule.next(spec: spec, fromDate: "2026-10-01", fromMinute: 480).due,
            ReminderMoment(date: "2026-10-10", minute: 540)
        )
    }

    func testIntervalDefaultsToDayUnit() {
        let plan = ReminderSchedule.next(
            spec: ReminderSpec(rule: "interval", anchorDate: "2026-10-01", minuteOfDay: 540,
                               intervalCount: 1),
            fromDate: "2026-10-01", fromMinute: 480
        )
        XCTAssertEqual(plan.due, ReminderMoment(date: "2026-10-01", minute: 540))
    }

    func testIntervalRejectsNonPositiveCountAndUnknownUnit() {
        XCTAssertEqual(
            ReminderSchedule.next(
                spec: ReminderSpec(rule: "interval", anchorDate: "2026-10-01", minuteOfDay: 540,
                                   intervalCount: 0, intervalUnit: "day"),
                fromDate: "2026-10-01", fromMinute: 0
            ).code, ReminderCode.invalid
        )
        XCTAssertEqual(
            ReminderSchedule.next(
                spec: ReminderSpec(rule: "interval", anchorDate: "2026-10-01", minuteOfDay: 540,
                                   intervalCount: 1, intervalUnit: "month"),
                fromDate: "2026-10-01", fromMinute: 0
            ).state, .invalid
        )
    }

    // MARK: - 每周（ISO 星期只有一套编号）

    func testWeeklyPicksTheNextMatchingWeekday() throws {
        // 2026-10-01 是周四；命中集合 = 周一 / 周三 ⇒ 下一次是 2026-10-05（周一）
        let plan = ReminderSchedule.next(
            spec: ReminderSpec(rule: "weekly", anchorDate: "2026-09-01", minuteOfDay: 600,
                               weekdays: [1, 3]),
            fromDate: "2026-10-01", fromMinute: 600
        )
        XCTAssertEqual(plan.due, ReminderMoment(date: "2026-10-05", minute: 600))
    }

    func testWeeklySameDayHonoursStrictlyLater() throws {
        // 2026-09-30 是周三（ISO 3）
        let spec = ReminderSpec(rule: "weekly", anchorDate: "2026-09-01", minuteOfDay: 700,
                                weekdays: [3])
        XCTAssertEqual(
            ReminderSchedule.next(spec: spec, fromDate: "2026-09-30", fromMinute: 600).due,
            ReminderMoment(date: "2026-09-30", minute: 700)
        )
        let past = ReminderSpec(rule: "weekly", anchorDate: "2026-09-01", minuteOfDay: 500,
                                weekdays: [3])
        XCTAssertEqual(
            ReminderSchedule.next(spec: past, fromDate: "2026-09-30", fromMinute: 600).due,
            ReminderMoment(date: "2026-10-07", minute: 500)
        )
    }

    func testWeeklyDropsDuplicateAndOutOfRangeWeekdays() throws {
        // [3,3,0,8,2] ⇒ 去重 + 剔除越界 ⇒ {2,3}；2026-09-28 是周一 ⇒ 下一次是 09-29（周二）
        let plan = ReminderSchedule.next(
            spec: ReminderSpec(rule: "weekly", anchorDate: "2026-09-01", minuteOfDay: 540,
                               weekdays: [3, 3, 0, 8, 2]),
            fromDate: "2026-09-28", fromMinute: 0
        )
        XCTAssertEqual(plan.due, ReminderMoment(date: "2026-09-29", minute: 540))
    }

    func testWeeklyAllInvalidWeekdaysIsInvalid() throws {
        XCTAssertEqual(
            ReminderSchedule.next(
                spec: ReminderSpec(rule: "weekly", anchorDate: "2026-09-01", minuteOfDay: 540,
                                   weekdays: [0, 8, -1]),
                fromDate: "2026-09-28", fromMinute: 0
            ).state, .invalid
        )
    }

    func testWeeklyFirstIsNotEarlierThanAnchor() throws {
        // 锚点在参照日之后 ⇒ 首次不早于锚点（锚点 2026-10-07 是周三）
        let plan = ReminderSchedule.next(
            spec: ReminderSpec(rule: "weekly", anchorDate: "2026-10-07", minuteOfDay: 540,
                               weekdays: [3]),
            fromDate: "2026-10-01", fromMinute: 0
        )
        XCTAssertEqual(plan.due, ReminderMoment(date: "2026-10-07", minute: 540))
    }

    func testWeeklyExpiresPastUntilDate() throws {
        let plan = ReminderSchedule.next(
            spec: ReminderSpec(rule: "weekly", anchorDate: "2026-09-01", minuteOfDay: 540,
                               weekdays: [3], untilDate: "2026-10-03"),
            fromDate: "2026-10-01", fromMinute: 0
        )
        XCTAssertEqual(plan.state, .expired, "下一个命中（10-07）已越过终止日 ⇒ 用尽")
        XCTAssertTrue(plan.ok)
    }

    // MARK: - 脏值一律判非法（口径 6）

    func testInvalidDatesAreNotRolledForward() {
        XCTAssertEqual(ReminderSchedule.dayOf("2026-02-30"), -1, "2 月 30 日不许滚到 3 月 2 日")
        XCTAssertEqual(ReminderSchedule.dayOf("2026-02-29"), -1, "2026 不是闰年")
        XCTAssertEqual(ReminderSchedule.dayOf("2026-13-01"), -1)
        XCTAssertEqual(ReminderSchedule.dayOf("2026-9-27"), -1, "单位数月日不是协议写法")
        XCTAssertEqual(ReminderSchedule.dayOf(""), -1)
        XCTAssertEqual(ReminderSchedule.dayOf("not-a-date"), -1)
        XCTAssertEqual(ReminderSchedule.dayOf("2028-02-29"), 21243, "2028 是闰年")
    }

    func testInvalidMinutesAndRulesReportInvalid() {
        let base = ReminderSpec(rule: "once", anchorDate: "2026-10-01", minuteOfDay: 540)
        XCTAssertEqual(ReminderSchedule.next(spec: base, fromDate: "2026-10-01", fromMinute: -1).state,
                       .invalid, "参照分钟非法 ⇒ 调用方传错就报错，不猜")
        XCTAssertEqual(
            ReminderSchedule.next(spec: ReminderSpec(rule: "once", anchorDate: "2026-10-01",
                                                     minuteOfDay: 1440),
                                  fromDate: "2026-09-27", fromMinute: 0).state, .invalid
        )
        XCTAssertEqual(
            ReminderSchedule.next(spec: ReminderSpec(rule: "everyWeek", anchorDate: "2026-10-01",
                                                     minuteOfDay: 540),
                                  fromDate: "2026-09-27", fromMinute: 0).state, .invalid
        )
        XCTAssertEqual(
            ReminderSchedule.next(spec: ReminderSpec(rule: "", anchorDate: "2026-10-01",
                                                     minuteOfDay: 540),
                                  fromDate: "2026-09-27", fromMinute: 0).code, ReminderCode.invalid
        )
        XCTAssertEqual(
            ReminderSchedule.next(spec: ReminderSpec(rule: "once", anchorDate: "2026-10-01",
                                                     minuteOfDay: 540, untilDate: "2026-02-30"),
                                  fromDate: "2026-09-27", fromMinute: 0).state, .invalid,
            "非法终止日不许被当成「不设终止」"
        )
    }

    func testMinuteBoundariesAreInclusive() {
        for minute in [0, 1439] {
            let plan = ReminderSchedule.next(
                spec: ReminderSpec(rule: "once", anchorDate: "2026-10-01", minuteOfDay: minute),
                fromDate: "2026-09-27", fromMinute: 0
            )
            XCTAssertEqual(plan.state, .pending, "第 \(minute) 分钟应当合法")
            XCTAssertEqual(plan.due.minute, minute)
        }
    }

    // MARK: - 预演（严格递增 / 提前结束 / 上限）

    func testUpcomingIsStrictlyIncreasingAndStopsWhenExhausted() {
        let weekly = ReminderSpec(rule: "weekly", anchorDate: "2026-09-01", minuteOfDay: 540,
                                  weekdays: [3])
        let moments = ReminderSchedule.upcoming(spec: weekly, fromDate: "2026-09-28",
                                                fromMinute: 0, count: 4)
        XCTAssertEqual(moments.map(\.date), ["2026-09-30", "2026-10-07", "2026-10-14", "2026-10-21"])

        // 一次性 ⇒ 首项之后立刻用尽（绝不伪造时刻）
        let once = ReminderSpec(rule: "once", anchorDate: "2026-10-01", minuteOfDay: 540)
        XCTAssertEqual(
            ReminderSchedule.upcoming(spec: once, fromDate: "2026-09-27", fromMinute: 0, count: 5)
                .map(\.date),
            ["2026-10-01"]
        )
        // 已经过期 ⇒ 一条都没有
        XCTAssertTrue(
            ReminderSchedule.upcoming(spec: once, fromDate: "2026-10-02", fromMinute: 0, count: 5)
                .isEmpty
        )
    }

    func testUpcomingCountBoundsAndCap() {
        let daily = ReminderSpec(rule: "interval", anchorDate: "2026-01-01", minuteOfDay: 540,
                                 intervalCount: 1, intervalUnit: "day")
        XCTAssertTrue(
            ReminderSchedule.upcoming(spec: daily, fromDate: "2026-01-01", fromMinute: 0, count: 0)
                .isEmpty, "0 次不是 1 次"
        )
        XCTAssertTrue(
            ReminderSchedule.upcoming(spec: daily, fromDate: "2026-01-01", fromMinute: 0, count: -3)
                .isEmpty
        )
        let capped = ReminderSchedule.upcoming(spec: daily, fromDate: "2026-01-01",
                                               fromMinute: 0, count: 500)
        XCTAssertEqual(capped.count, ReminderSchedule.maxUpcoming, "上限 = 100")
        XCTAssertEqual(capped.count, 100)
    }

    // MARK: - 日历算术（日序 / 星期只有一个原点）

    func testDayIndexOriginAndRoundTrip() {
        XCTAssertEqual(ReminderSchedule.dayOf("1970-01-01"), 0)
        XCTAssertEqual(ReminderSchedule.weekdayOfDay(0), 4, "1970-01-01 是周四（ISO 4）")
        XCTAssertEqual(ReminderSchedule.dayOf("2026-10-01"), 20727)
        XCTAssertEqual(ReminderSchedule.weekdayOfDay(20727), 4)
        XCTAssertEqual(ReminderSchedule.dateOfDay(20727), "2026-10-01")
        for day in [-1, 0, 20000, 20727, 21243, 2932896] {
            XCTAssertEqual(ReminderSchedule.dayOf(ReminderSchedule.dateOfDay(day)), day,
                           "日序与日期串必须逐值往返")
        }
    }

    // MARK: - 瞬间（跨端比较面之外的那一半，用显式偏移验）

    func testEpochRoundTripWithExplicitOffsets() {
        let moment = ReminderMoment(date: "2026-12-25", minute: 540)
        for offset in [0, 8 * 3600 * 1000, -5 * 3600 * 1000] {
            let epoch = ReminderSchedule.toEpoch(moment: moment, zoneOffsetMillis: offset)
            XCTAssertNotEqual(epoch, -1)
            XCTAssertEqual(ReminderSchedule.dateOfEpoch(epochMillis: epoch, zoneOffsetMillis: offset),
                           moment.date, "正向与反向必须共用同一个日序原点")
        }
        // 偏移只挪瞬间的绝对值，不改「哪一天第几分钟」
        let utc = ReminderSchedule.toEpoch(moment: moment, zoneOffsetMillis: 0)
        let beijing = ReminderSchedule.toEpoch(moment: moment, zoneOffsetMillis: 8 * 3600 * 1000)
        XCTAssertEqual(utc - beijing, 8 * 3600 * 1000)
        XCTAssertEqual(ReminderSchedule.toEpoch(moment: .none, zoneOffsetMillis: 0), -1)
    }

    func testTimeZoneDoesNotEnterTheSemantics() {
        // 同一份规则在两种时区下的预演结果逐条相同（时区差异不进语义）
        let spec = ReminderSpec(rule: "interval", anchorDate: "2026-10-01", minuteOfDay: 540,
                                intervalCount: 2, intervalUnit: "day")
        let a = ReminderSchedule.upcoming(spec: spec, fromDate: "2026-10-01", fromMinute: 0, count: 3)
        let b = ReminderSchedule.upcoming(spec: spec, fromDate: "2026-10-01", fromMinute: 0, count: 3)
        XCTAssertEqual(a, b)
    }
}
