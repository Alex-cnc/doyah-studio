import XCTest
@testable import DoyahCore

/// 队列 `L-100`（待办清单界面）**Core 半**的纯逻辑判据：分区与空标题。
///
/// 为什么这两件值得单测：
///  · **分区**是口径（两段永远都在 / 段序固定 / **段内不许重排** —— 排序与带在 `TodoSort` / `TodoQuery`），
///    写在视图里就是一串 `if`，谁都没断言过；
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

    // MARK: - 截止带 / 逾期

    /// 截止带（`TodoBand`）与逾期标识（`TodoDue.isOverdue`）在第 191 轮从本文件**搬到了**
    /// `Core/TodoQuery.swift` —— 契约 §3.13 第四条（`done = false` 且 `dueAt < 今天`）落笔后，
    /// 本文件原来的 `dueState`（`dueAt < now`）与两端一致的口径不符，已删除。
    /// 判据随之移到 `Tests/TodoQueryTests.swift`（带的五档 / 互斥穷尽 / 逾期与完成态 / 窗口三边界）。

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
            .todoDueNone, .todoDueOverdue, .todoDueToday, .todoDueThisWeek, .todoDueLater,
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
