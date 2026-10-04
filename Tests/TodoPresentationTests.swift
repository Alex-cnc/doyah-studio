import XCTest
@testable import DoyahCore

/// 队列 `L-100`（待办清单界面）**Core 半**的纯逻辑判据：分区、截止档位、空标题。
///
/// 为什么这三件值得单测：
///  · **分区**是口径（两段永远都在 / 段序固定 / **段内不许重排** —— 排序是契约半的事），
///    写在视图里就是一串 `if`，谁都没断言过；
///  · **档位边界**（到点那一刻 / 今天早上已过去 / 跨零点 / 明天）只能靠构造时刻来钉，
///    现场看是看不出来的；
///  · **空标题**的哨兵值定在 Core ⇒ 「清单」与「日历」两个界面不必各写一套。
final class TodoPresentationTests: XCTestCase {

    // MARK: - 工具

    private func todo(
        _ title: String = "任务",
        due: Date? = nil,
        done: Bool = false
    ) -> Todo {
        Todo(title: title, dueAt: due, done: done)
    }

    /// 一个固定的「现在」：2026-10-04 15:00（本地时区）—— 所有档位判据都以它为参照。
    private var now: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 4
        components.hour = 15
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components)!
    }

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 4) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    // MARK: - 分区

    func testSectionsSplitByDoneAndKeepIncomingOrder() {
        let first = todo("甲")
        let second = todo("乙", done: true)
        let third = todo("丙")
        let fourth = todo("丁", done: true)
        let sections = TodoPresentation.sections([first, second, third, fourth])

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].kind, .open)
        XCTAssertEqual(sections[0].todos.map(\.id), [first.id, third.id])
        XCTAssertEqual(sections[1].kind, .completed)
        XCTAssertEqual(sections[1].todos.map(\.id), [second.id, fourth.id])
    }

    func testSectionsKeepBothSectionsWhenNothingToShow() {
        // 两段永远都在（哪怕 0 条）：空态与段头计数靠 `count` 判，不靠「数组里有没有这一段」。
        let sections = TodoPresentation.sections([])

        XCTAssertEqual(sections.map(\.kind), [.open, .completed])
        XCTAssertEqual(sections.map(\.count), [0, 0])
    }

    func testSectionHeadersAndDefaultCollapse() {
        // 段序固定：未完成在前。
        XCTAssertEqual(TodoSectionKind.displayOrder, [.open, .completed])
        XCTAssertEqual(TodoSectionKind.open.titleKey, .todoSectionOpen)
        XCTAssertEqual(TodoSectionKind.completed.titleKey, .todoSectionCompleted)
        // `FR-NOTE-36`：已完成**默认折叠**（这里只给默认值，折叠状态住界面）。
        XCTAssertTrue(TodoSectionKind.completed.isCollapsedByDefault)
        XCTAssertFalse(TodoSectionKind.open.isCollapsedByDefault)
    }

    // MARK: - 截止档位

    func testDueStateIsNoneWithoutDueDate() {
        XCTAssertEqual(TodoPresentation.dueState(nil, now: now), .none)
    }

    func testDueStateIsOverdueWhenTheMomentHasPassed() {
        // 今天早上 09:00 到下午就是**过期**（不是「今天」）—— 清单上最要紧的是它还欠着。
        XCTAssertEqual(TodoPresentation.dueState(at(9), now: now), .overdue)
        // 更早的日子同样过期。
        XCTAssertEqual(TodoPresentation.dueState(at(9, day: 3), now: now), .overdue)
    }

    func testDueStateIsTodayOnlyBeforeTheMomentArrives() {
        XCTAssertEqual(TodoPresentation.dueState(at(15, 30), now: now), .today)
        XCTAssertEqual(TodoPresentation.dueState(at(23, 59), now: now), .today)
    }

    func testDueStateTreatsTheExactMomentAsToday() {
        // 「正好到点」算今天（还没过去）；逾期的判定是**严格小于** —— 边界只钉这一处。
        XCTAssertEqual(TodoPresentation.dueState(now, now: now), .today)
    }

    func testDueStateTomorrowIsCalendarDayNot24Hours() {
        // 次日 00:01 = 明天（按日历日差算，不按「还差不到 24 小时」近似）。
        XCTAssertEqual(TodoPresentation.dueState(at(0, 1, day: 5), now: now), .tomorrow)
        XCTAssertEqual(TodoPresentation.dueState(at(9, 0, day: 5), now: now), .tomorrow)
    }

    func testDueStateLaterBeyondTomorrow() {
        XCTAssertEqual(TodoPresentation.dueState(at(9, 0, day: 6), now: now), .later)
        XCTAssertEqual(TodoPresentation.dueState(at(9, 0, day: 20), now: now), .later)
    }

    func testDueStateIsIndependentOfCompletion() {
        // 完成态不影响档位判定（已完成那一段画不画徽标是界面的事）。
        let finishedOverdue = todo("早该做的事", due: at(9), done: true)
        XCTAssertEqual(TodoPresentation.dueState(finishedOverdue.dueAt, now: now), .overdue)
    }

    func testDueStateKeysAreDistinct() {
        let states: [TodoDueState] = [.none, .overdue, .today, .tomorrow, .later]
        XCTAssertEqual(Set(states.map(\.key)).count, states.count)
    }

    // MARK: - 空标题

    func testTitleIsNilOnlyWhenAllWhitespace() {
        XCTAssertNil(TodoPresentation.title(todo("")))
        XCTAssertNil(TodoPresentation.title(todo("   ")))
        XCTAssertNil(TodoPresentation.title(todo("\n\t ")))
        XCTAssertEqual(TodoPresentation.title(todo(" 买牛奶 ")), " 买牛奶 ")
    }

    // MARK: - 语言表

    func testTodoKeysExistInBothLanguages() {
        // 句子只在语言表里：这一组的每一条都必须中英齐、且两语不同（否则就是漏了一条）。
        let keys: [LKey] = [
            .todoSectionOpen, .todoSectionCompleted,
            .todoDueNone, .todoDueOverdue, .todoDueToday, .todoDueTomorrow, .todoDueLater,
        ]
        for key in keys {
            let chinese = LocalizedStrings.table[key]?[.simplifiedChinese]
            let english = LocalizedStrings.table[key]?[.english]
            XCTAssertNotNil(chinese, "\(key) 缺中文模板")
            XCTAssertNotNil(english, "\(key) 缺英文模板")
            XCTAssertFalse((chinese ?? "").isEmpty, "\(key) 的中文模板是空的")
            XCTAssertFalse((english ?? "").isEmpty, "\(key) 的英文模板是空的")
            XCTAssertNotEqual(chinese, english, "\(key) 中英同一句（漏了一条）")
        }
    }
}
