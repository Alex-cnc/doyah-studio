import XCTest
@testable import DoyahCore

// 队列 `L-100` 落法 ④ 的**界面入口半**：那一区的合成状态（`ReminderEntry`）。
//
// 这一片落的判断只有两条，但两条都是「只有用例能钉住」的那种：
//   ① **档位回显** —— 库里的 `reminder` 表**没有档位列**（档位是派生量）⇒ 界面要显示「已经挂着的是
//      哪一档」就只能**重算**：拿四个档位各算一次 `attachment` 与那一条逐字段比。算不出来（那一条是
//      `weekly` / 截止时间后来被改过）就必须回 `nil`，**不能假装它是某一档**；
//   ② **合成** —— 一区要的那份答案（四个档位 + 选中档 + 规则 + 求解 + 权限那一档 + 排不排）只能有
//      一处合成；没有提醒时那一份 `plan` 也必须是**确定的**，不是随机的。
//
// 三条纪律（与 `ReminderPresentationTests` 同）：字面量独立算、时区偏移是参数、跨零点是重点。
final class ReminderEntryTests: XCTestCase {

    /// `2026-10-05 09:00Z`。
    private let dueMorning = Date(timeIntervalSince1970: 1_791_190_800)
    /// `2026-10-05 00:20Z`（跨零点那一档的截止时间）。
    private let dueLateNight = Date(timeIntervalSince1970: 1_791_159_600)
    /// `2026-10-04 12:00Z`（截止之前）。
    private let before = Date(timeIntervalSince1970: 1_791_115_200)
    /// `2026-10-05 10:00Z`（截止之后 ⇒ 一次性规则已经结束）。
    private let after = Date(timeIntervalSince1970: 1_791_194_400)

    private let utc = 0

    private func spec(_ due: Date, _ preset: ReminderPreset) -> ReminderSpec? {
        ReminderPresentation.attachment(dueAt: due, preset: preset, zoneOffsetMillis: utc).spec
    }

    // MARK: - 档位

    func testEntryCarriesEveryPreset() {
        // 档位空间**唯一来源**是 Core（界面不许自己列一遍四档）。
        let entry = ReminderEntry.make(
            dueAt: dueMorning, preset: .atDue, existing: nil,
            permission: .notDetermined, now: before, zoneOffsetMillis: utc
        )
        XCTAssertEqual(entry.presets, ReminderPreset.allCases)
        XCTAssertEqual(entry.presets.count, 4)
    }

    func testPresetEchoRoundTripsEveryPreset() throws {
        for preset in ReminderPreset.allCases {
            let spec = try XCTUnwrap(self.spec(dueMorning, preset))
            XCTAssertEqual(
                ReminderPresentation.preset(of: spec, dueAt: dueMorning, zoneOffsetMillis: utc),
                preset,
                "\(preset.rawValue) 那一档算不出自己"
            )
        }
    }

    func testPresetEchoWorksAcrossMidnight() throws {
        // 00:20 的截止时间「提前 1 小时」= 前一天 23:20 —— 档位回显也必须算得回来。
        let spec = try XCTUnwrap(self.spec(dueLateNight, .before1h))
        XCTAssertEqual(spec.anchorDate, "2026-10-04")
        XCTAssertEqual(spec.minuteOfDay, 23 * 60 + 20)
        XCTAssertEqual(
            ReminderPresentation.preset(of: spec, dueAt: dueLateNight, zoneOffsetMillis: utc),
            .before1h
        )
    }

    func testPresetEchoRefusesForeignRules() {
        // 不是四个档位之一的规则（重复类）⇒ **不假装是某一档**。
        let weekly = ReminderSpec(
            rule: ReminderRule.weekly.rawValue,
            anchorDate: "2026-10-05",
            minuteOfDay: 540,
            weekdays: [1, 3]
        )
        XCTAssertNil(ReminderPresentation.preset(of: weekly, dueAt: dueMorning, zoneOffsetMillis: utc))
        // 截止时间后来被改过 ⇒ 「到点」那一条的锚已经不是原来那一刻 ⇒ 也认不出（宁可认不出，不许错认）。
        let once = ReminderSpec(rule: ReminderRule.once.rawValue, anchorDate: "2026-10-05", minuteOfDay: 540)
        XCTAssertNil(ReminderPresentation.preset(of: once, dueAt: dueLateNight, zoneOffsetMillis: utc))
    }

    // MARK: - 能不能挂

    func testNoDueDateCannotAttachAndSaysWhy() {
        let entry = ReminderEntry.make(
            dueAt: nil, preset: .atDue, existing: nil,
            permission: .authorized, now: before, zoneOffsetMillis: utc
        )
        XCTAssertEqual(entry.attachment, .needsDueDate)
        XCTAssertFalse(entry.canAttach)
        XCTAssertEqual(entry.attachment.reasonKey, .reminderNeedsDue)
        XCTAssertFalse(entry.hasReminder)
    }

    func testAttachUsesTheSelectedPreset() throws {
        let entry = ReminderEntry.make(
            dueAt: dueMorning, preset: .before1d, existing: nil,
            permission: .authorized, now: before, zoneOffsetMillis: utc
        )
        let spec = try XCTUnwrap(entry.attachment.spec)
        XCTAssertEqual(spec.rule, ReminderRule.once.rawValue)
        XCTAssertEqual(spec.anchorDate, "2026-10-04")
        XCTAssertEqual(spec.minuteOfDay, 540)
        XCTAssertTrue(entry.canAttach)
    }

    // MARK: - 合成（有提醒 / 没提醒）

    func testEntryWithNoReminderHasADeterministicPlan() {
        let entry = ReminderEntry.make(
            dueAt: dueMorning, preset: .atDue, existing: nil,
            permission: .authorized, now: before, zoneOffsetMillis: utc
        )
        XCTAssertNil(entry.spec)
        XCTAssertNil(entry.existingPreset)
        XCTAssertFalse(entry.hasReminder)
        // 没有提醒时那一份 `plan` 是**确定的**：规则认不出（不是随机的、也不是 `pending`）。
        XCTAssertEqual(entry.plan.state, .invalid)
        XCTAssertEqual(entry.decision, .inactive(.reminderRuleUnknown))
    }

    func testEntryWithReminderEchoesPresetAndComposesDecision() throws {
        let spec = try XCTUnwrap(self.spec(dueMorning, .before15m))
        let entry = ReminderEntry.make(
            dueAt: dueMorning, preset: .before15m, existing: spec,
            permission: .notDetermined, now: before, zoneOffsetMillis: utc
        )
        XCTAssertTrue(entry.hasReminder)
        XCTAssertEqual(entry.existingPreset, .before15m)
        XCTAssertEqual(entry.plan.state, .pending)
        // 还没问过权限 ⇒ 先问、这一轮不排。
        XCTAssertEqual(entry.decision, .askPermission)
    }

    func testAuthorizedPendingDecisionMatchesScheduleArithmetic() throws {
        let spec = try XCTUnwrap(self.spec(dueMorning, .atDue))
        let entry = ReminderEntry.make(
            dueAt: dueMorning, preset: .atDue, existing: spec,
            permission: .authorized, now: before, zoneOffsetMillis: utc
        )
        let expected = ReminderSchedule.toEpoch(moment: entry.plan.due, zoneOffsetMillis: utc)
        XCTAssertEqual(entry.decision, .schedule(triggerEpochMillis: expected))
        // 触发瞬间就是「到点」那一刻（这一档提前量为 0）。
        XCTAssertEqual(expected, 1_791_190_800_000)
    }

    func testDeniedPermissionSaysWhereToTurnItOn() throws {
        let spec = try XCTUnwrap(self.spec(dueMorning, .atDue))
        let entry = ReminderEntry.make(
            dueAt: dueMorning, preset: .atDue, existing: spec,
            permission: .denied, now: before, zoneOffsetMillis: utc
        )
        XCTAssertEqual(entry.decision, .inactive(.reminderPermissionDenied))
        XCTAssertEqual(entry.decision.reasonKey, .reminderPermissionDenied)
    }

    func testExpiredReminderStaysVisibleButIsNotScheduled() throws {
        let spec = try XCTUnwrap(self.spec(dueMorning, .atDue))
        let entry = ReminderEntry.make(
            dueAt: dueMorning, preset: .atDue, existing: spec,
            permission: .authorized, now: after, zoneOffsetMillis: utc
        )
        // 已经结束：档位**照样回显**（那一条还在库里），但排不排那一格是「不排 + 一句人话」。
        XCTAssertEqual(entry.existingPreset, .atDue)
        XCTAssertEqual(entry.plan.state, .expired)
        XCTAssertEqual(entry.decision, .inactive(.reminderExpired))
    }

    // MARK: - 这一层的形状

    func testSourceKeepsEveryPlatformApiOut() throws {
        // 与 `ReminderPresentation` 同一条纪律：系统时钟 / 时区 / 平台日历 / 日期格式化器 /
        // 通知框架，一个都不许出现在这一层（否则它的用例在别的平台上跑不了）。
        let text = try source("Core/ReminderEntry.swift")
        for token in ["Date()", "TimeZone", "Calendar.current", "DateFormatter", "UNUserNotification"] {
            XCTAssertFalse(text.contains(token), "Core/ReminderEntry.swift 里出现了 \(token)")
        }
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}
