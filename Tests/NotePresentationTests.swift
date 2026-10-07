import XCTest
@testable import DoyahCore

/// 队列 `L-184`（三栏重排）的**纯逻辑**判据：中栏卡片要用的「摘要」与「相对时间」。
///
/// 为什么这两件值得单测、而不是「看着对就行」：
///  · 摘要的**折行 / 截断**是口径（`\n` 折成空格、按字符不按词、截断只说「还有」）——
///    写在视图里就是一堆 `if`，谁都没断言过；
///  · 相对时间的**档位边界**（59 秒 / 60 秒 / 跨零点 / 未来时刻）只能靠构造时刻来钉 —— 现场看是看不出来的。
final class NotePresentationTests: XCTestCase {

    // MARK: - 摘要

    func testExcerptCollapsesWhitespaceIntoOneLine() {
        XCTAssertEqual(NotePresentation.excerpt("第一行\n第二行"), "第一行 第二行")
        XCTAssertEqual(NotePresentation.excerpt("a\t\tb   c"), "a b c")
        XCTAssertEqual(NotePresentation.excerpt("  \n  "), "")
        XCTAssertEqual(NotePresentation.excerpt(""), "")
    }

    func testExcerptTrimsBothEnds() {
        XCTAssertEqual(NotePresentation.excerpt("\n\n  正文  \n"), "正文")
    }

    func testExcerptKeepsShortBodyUntouched() {
        XCTAssertEqual(NotePresentation.excerpt("五个字以内", limit: 120), "五个字以内")
    }

    func testExcerptTruncatesByCharactersAndMarksIt() {
        let long = String(repeating: "字", count: 200)
        let excerpt = NotePresentation.excerpt(long, limit: 10)
        // 10 个字符 + 一个省略号；中文按**字符**算（不是一个字算两个）。
        XCTAssertEqual(excerpt.count, 11)
        XCTAssertTrue(excerpt.hasSuffix("…"), "截断要如实标出「还有」，不假装这就是全文")
        XCTAssertEqual(String(excerpt.dropLast()), String(repeating: "字", count: 10))
    }

    func testExcerptExactlyAtLimitIsNotTruncated() {
        XCTAssertEqual(NotePresentation.excerpt("12345", limit: 5), "12345", "正好等于上限 ⇒ 不算截断")
        // 上限 ≤ 0 时**不截断**（宁可显示全文，也不要出现只有省略号的卡片）。
        XCTAssertEqual(NotePresentation.excerpt("12345", limit: 0), "12345")
    }

    // MARK: - 相对时间（档位边界）

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        Self.calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        )!
    }

    private func relative(_ date: Date, now: Date) -> NoteRelativeTime {
        NotePresentation.relative(date, now: now, calendar: Self.calendar)
    }

    func testUnderOneMinuteIsJustNow() {
        let now = moment(2026, 10, 4, 12, 0, 30)
        XCTAssertEqual(relative(moment(2026, 10, 4, 12, 0, 0), now: now), .justNow)
        // 59 秒仍是「刚刚」（边界包含）：60 秒才进分钟档。
        let at59 = moment(2026, 10, 4, 11, 59, 31)
        XCTAssertEqual(relative(at59, now: now), .justNow)
        XCTAssertEqual(relative(moment(2026, 10, 4, 11, 59, 30), now: now), .minutes(1))
    }

    func testMinutesAndHoursWithinTheSameDay() {
        let now = moment(2026, 10, 4, 12, 0)
        XCTAssertEqual(relative(moment(2026, 10, 4, 11, 1), now: now), .minutes(59))
        XCTAssertEqual(relative(moment(2026, 10, 4, 11, 0), now: now), .hours(1))
        // 23 小时档只能在**同一日历日**里出现（跨零点就是「昨天」）。
        let lateNight = moment(2026, 10, 4, 23, 59)
        XCTAssertEqual(relative(moment(2026, 10, 4, 0, 0, 30), now: lateNight), .hours(23))
    }

    /// **跨零点 = 昨天**，不是「2 分钟前」：档位按**日历**分，不按时长近似。
    func testCrossingMidnightIsYesterdayEvenIfOnlyMinutesAgo() {
        XCTAssertEqual(
            relative(moment(2026, 10, 3, 23, 59), now: moment(2026, 10, 4, 0, 1)),
            .yesterday
        )
    }

    func testOlderThanYesterdayCountsWholeDays() {
        XCTAssertEqual(
            relative(moment(2026, 10, 2, 10, 0), now: moment(2026, 10, 4, 12, 0)),
            .days(2)
        )
        // 跨年也不特殊（整天数是日历给的事实）。
        XCTAssertEqual(
            relative(moment(2025, 12, 30, 8, 0), now: moment(2026, 1, 2, 9, 0)),
            .days(3)
        )
    }

    /// 时钟回拨 / 库里写进未来的值：报「刚刚」，不出现负数。
    func testFutureTimestampFallsBackToJustNow() {
        XCTAssertEqual(
            relative(moment(2026, 10, 4, 12, 5), now: moment(2026, 10, 4, 12, 0)),
            .justNow
        )
    }

    // MARK: - 档位 → 语言表（句子只在语言表里）

    func testBucketMapsToLanguageKeyAndArgument() {
        XCTAssertEqual(NoteRelativeTime.justNow.key, .notesTimeJustNow)
        XCTAssertNil(NoteRelativeTime.justNow.argument, "「刚刚」那一档没有数字槽")
        XCTAssertNil(NoteRelativeTime.yesterday.argument, "「昨天」那一档没有数字槽")

        XCTAssertEqual(NoteRelativeTime.minutes(5).key, .notesTimeMinutesAgo)
        XCTAssertEqual(NoteRelativeTime.minutes(5).argument, "5")
        XCTAssertEqual(NoteRelativeTime.hours(3).key, .notesTimeHoursAgo)
        XCTAssertEqual(NoteRelativeTime.hours(3).argument, "3")
        XCTAssertEqual(NoteRelativeTime.days(12).key, .notesTimeDaysAgo)
        XCTAssertEqual(NoteRelativeTime.days(12).argument, "12")
    }

    /// 语言表两侧都要有：档位与键一一对上，中英模板都非空。
    func testEveryBucketHasBothLanguages() {
        let buckets: [NoteRelativeTime] = [.justNow, .minutes(1), .hours(1), .yesterday, .days(2)]
        for bucket in buckets {
            for language in [AppLanguage.simplifiedChinese, .english] {
                let template = LocalizedStrings.table[bucket.key]?[language]
                XCTAssertNotNil(template, "\(bucket.key) 缺 \(language) 模板")
                XCTAssertFalse((template ?? "").isEmpty, "\(bucket.key) 的 \(language) 模板是空的")
            }
        }
    }

    // MARK: - 接线（源码判据）

    /// 三栏重排这件事，判据全绿而界面还是两栏的话就没意义 ⇒ 在源码里钉锚点。
    func testThreeColumnWiring() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let window = Self.stripComments(try String(contentsOf: root.appendingPathComponent("App/Views/MainWindow.swift"), encoding: .utf8))
        let panel = Self.stripComments(try String(contentsOf: root.appendingPathComponent("App/Views/NotesPanel.swift"), encoding: .utf8))

        // ① 笔记那一档的右边是「三栏装配件」，左栏（侧栏）是两级树。
        XCTAssertTrue(window.contains("NotesAreaView()"), "`.notes` 的右边必须装配三栏件")
        XCTAssertTrue(window.contains("NotesContainerTreeView()"), "左栏 = 两级树")
        XCTAssertFalse(window.contains("NotesListView()"), "列表不再直接挂在窗口上（它在中栏里）")

        // ② 中栏在右栏左边（顺序即分工），且两者在同一件装配里。
        let area = try XCTUnwrap(panel.range(of: "struct NotesAreaView"))
        let rest = String(panel[area.lowerBound...])
        let split = try XCTUnwrap(rest.range(of: "HSplitView {"))
        let afterSplit = String(rest[split.lowerBound...])
        let listIndex = try XCTUnwrap(afterSplit.range(of: "NotesListView()"))
        let editorIndex = try XCTUnwrap(afterSplit.range(of: "NotesEditorView()"))
        XCTAssertTrue(listIndex.lowerBound < editorIndex.lowerBound, "中栏（列表）在右栏（编辑器）左边")

        // ③ 搜索框只有一处，且它绑的是那一个词；检索那条 `.task` 也只有一处。
        XCTAssertEqual(panel.components(separatedBy: "$appState.notesQuery").count - 1, 1, "搜索框只许有一个")
        XCTAssertEqual(panel.components(separatedBy: ".task(id: appState.notesQuery)").count - 1, 1, "检索只许挂一处")
        XCTAssertTrue(panel.contains(".accessibilityIdentifier(\"notes-search-field\")"), "搜索框要有标识（探针与点验都靠它）")

        // ④ 「新建」只有一处（栏头那个按钮搬走了）。
        //
        // **锚点跟版（片 `N2-4` 顺手清掉这条先红；口径一字未改）**：原先那句判据锚在
        // `Button(L(.notesNew))` 这个**字面形状**上，而入口形态此后换过两次 —— `N-UI-3`（2026-10-06，
        // 提交 559cd29）把它改成 `ToolbarIconButton(systemName: "plus", help: L(.notesNew))`，
        // `N2-2`（2026-10-07）再收成那一族 ⇒ 源码里再也找不到那个字面串 ⇒ 这条判据**自 559cd29 起
        // 就一直是红的**（基线 `f0fbf0a` 上复跑同一句话：实测 0、期望 1），而它红着会让
        // `verify-all.sh` 在第 1 项就中止（`set -e`）—— 十八项全跑不成。
        // 口径不变：**「新建」只许有一个入口**。改判**两件事各一处**（比原字面锚更贴口径）：
        // 文案键 `L(.notesNew)` 与 `accessibilityIdentifier("notes-new")` 都只出现一次 ——
        // 再画第二个「新建」入口（换文案 / 换图标 / 换按钮族）都至少会多出其中一处。
        XCTAssertEqual(
            panel.components(separatedBy: "L(.notesNew)").count - 1, 1,
            "「新建」只许有一个入口（数的是文案键 `L(.notesNew)` 的出现处数）"
        )
        XCTAssertEqual(
            panel.components(separatedBy: "\"notes-new\"").count - 1, 1,
            "「新建」只许有一个入口（数的是可读标识 `notes-new` 的出现处数）"
        )
    }

    /// 剥注释（`//` 与 `///` 行、`/* */` 块）—— 与 `NotebookMovePromptTests` 同一份实现（同一课）。
    private static func stripComments(_ source: String) -> String {
        var output: [String] = []
        var inBlock = false
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inBlock {
                if trimmed.contains("*/") { inBlock = false }
                continue
            }
            if trimmed.hasPrefix("/*") {
                inBlock = !trimmed.contains("*/")
                continue
            }
            if trimmed.hasPrefix("//") { continue }
            output.append(String(line))
        }
        return output.joined(separator: "\n")
    }
}
