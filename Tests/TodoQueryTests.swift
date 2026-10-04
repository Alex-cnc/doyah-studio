import XCTest
@testable import DoyahCore

/// 队列 `L-100` **组织与检索半**（第 191 轮）的判据：**截止带 / 逾期 / 筛选 / 分组 / 排序**。
///
/// 为什么这一族值得单测：
///  · 契约 §3.13 的四条排序口径与「逾期 = 未完成 且 早于今天零点」是**跨端比较面** ——
///    本侧排一套、对侧排一套，两边的自测都会是绿的，只有把「同一批输入」的**输出次序**钉住才拦得住；
///  · 带 / 筛选 / 分组三者的**互相关系**（互斥穷尽、今天 ∪ 本周不重复、分组不改排序）是口径，
///    写在界面上就是一串 `if`，谁都断言不到；
///  · 参照窗口**必须由调用方传**（Core 不读系统时钟）⇒ 用固定窗口构造时刻才判得准。
final class TodoQueryTests: XCTestCase {

    // MARK: - 工具（全部走 Core 的整数日序，不用平台日历）

    /// 时区偏移：0（判据不掺时区；换时区只影响 `Date` 的绝对值，不影响带 / 序）。
    private let offset = 0

    /// 固定「今天」= **2026-10-07（周三）** —— 周三才让「本周」那一带非空（周一起算，周一在 10-12）。
    private let today = "2026-10-07"

    private var window: TodoWindow { TodoWindow.of(today: today, zoneOffsetMillis: offset) }

    /// `YYYY-MM-DD` + 当日分钟 → 时刻（**与提醒那个「到点」同一套算术**）。
    private func at(_ date: String, _ minute: Int = 0) -> Date {
        let epoch = ReminderSchedule.toEpoch(
            moment: ReminderMoment(date: date, minute: minute),
            zoneOffsetMillis: offset
        )
        return Date(timeIntervalSince1970: Double(epoch) / 1000)
    }

    private func todo(
        _ title: String = "任务",
        due: Date? = nil,
        done: Bool = false,
        priority: TodoPriority = .normal,
        tags: [String] = [],
        created: Date? = nil,
        id: UUID = UUID()
    ) -> Todo {
        let created = created ?? at("2026-10-01")
        return Todo(
            id: id,
            title: title,
            dueAt: due,
            done: done,
            completedAt: nil,
            priority: priority,
            tags: tags,
            createdAt: created,
            updatedAt: created
        )
    }

    private func root(_ relative: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: root(relative), encoding: .utf8)
    }

    // MARK: - 窗口（三个边界唯一生产入口）

    func testWindowBuildsThreeMidnightsFromLocalDay() {
        let w = window
        XCTAssertEqual(w.todayStart, at("2026-10-07"))
        XCTAssertEqual(w.tomorrowStart, at("2026-10-08"))
        // 周一起算：周三 ⇒ 下周一 = 10-12 零点。
        XCTAssertEqual(w.weekEnd, at("2026-10-12"))
    }

    func testWindowStartsTheWeekOnMonday() {
        // 周日（2026-10-04）→ 「本周」只剩一天：下周一就是 10-05。
        let sunday = TodoWindow.of(today: "2026-10-04", zoneOffsetMillis: offset)
        XCTAssertEqual(sunday.weekEnd, at("2026-10-05"))
    }

    func testWindowOnDirtyDateFallsBackToTheDistantPast() {
        // 脏值不抛错：三个边界一起退到远古 ⇒ 有截止的都落「更晚」那一带，无截止的照旧。
        let dirty = TodoWindow.of(today: "2026-02-30", zoneOffsetMillis: offset)
        XCTAssertEqual(dirty.todayStart, .distantPast)
        XCTAssertEqual(dirty.tomorrowStart, .distantPast)
        XCTAssertEqual(dirty.weekEnd, .distantPast)
        XCTAssertEqual(TodoQuery.band(of: todo(due: at("2026-01-01")), window: dirty), .later)
    }

    // MARK: - 截止带（`FR-NOTE-37` 的时间分组 / `FR-NOTE-38` 的逾期标识）

    func testBandIsNoDueWithoutDueDate() {
        XCTAssertEqual(TodoQuery.band(of: todo(), window: window), .noDue)
    }

    func testBandIsOverdueOnlyBeforeTodayStart() {
        // 跟版订正（契约 §3.13 第四条）：**今天早上那一点不算逾期**，它落在「今天」那一带。
        // 旧口径（`dueAt < now`）会把它画成「已过期」，与对侧不一致。
        XCTAssertEqual(TodoQuery.band(of: todo(due: at("2026-10-06", 23 * 60 + 59)), window: window), .overdue)
        XCTAssertEqual(TodoQuery.band(of: todo(due: at("2026-10-07", 9 * 60)), window: window), .today)
        // 今天零点那一刻本身 = 今天（边界只钉一次：严格小于）。
        XCTAssertEqual(TodoQuery.band(of: todo(due: at("2026-10-07")), window: window), .today)
    }

    func testBandCoversTodayThisWeekAndLater() {
        XCTAssertEqual(TodoQuery.band(of: todo(due: at("2026-10-07", 23 * 60 + 59)), window: window), .today)
        XCTAssertEqual(TodoQuery.band(of: todo(due: at("2026-10-08", 1)), window: window), .thisWeek)
        XCTAssertEqual(TodoQuery.band(of: todo(due: at("2026-10-11", 23 * 60 + 59)), window: window), .thisWeek)
        // 下周一零点 = 更晚（`weekEnd` 是开区间的那一端）。
        XCTAssertEqual(TodoQuery.band(of: todo(due: at("2026-10-12")), window: window), .later)
        XCTAssertEqual(TodoQuery.band(of: todo(due: at("2027-01-01")), window: window), .later)
    }

    func testBandIgnoresCompletionButOverdueFlagDoesNot() {
        // 分带**不看完成态**（它回答「落在哪一天」）—— 契约 §3.13 第四条与对侧 `bandOf` 同口径。
        let finished = todo(due: at("2026-10-06"), done: true)
        XCTAssertEqual(TodoQuery.band(of: finished, window: window), .overdue)
        // 逾期**标识**只看未完成（它回答「要不要催」）。
        XCTAssertTrue(TodoDue.isOverdue(todo(due: at("2026-10-06")), window: window))
        XCTAssertFalse(TodoDue.isOverdue(finished, window: window))
        XCTAssertFalse(TodoDue.isOverdue(todo(), window: window), "无截止永不逾期")
        XCTAssertFalse(TodoDue.isOverdue(todo(due: at("2026-10-07")), window: window), "今天零点不算逾期")
    }

    func testBandIsMutuallyExclusiveAndExhaustive() {
        // 互斥且穷尽：任何一条都有且只有一个带（单测遍历一批样本）。
        let dues: [Date?] = [
            nil,
            at("2026-10-06"), at("2026-10-06", 23 * 60 + 59),
            at("2026-10-07"), at("2026-10-07", 12 * 60),
            at("2026-10-08"), at("2026-10-11", 23 * 60 + 59),
            at("2026-10-12"), at("2027-02-01"),
        ]
        let bands = dues.map { TodoQuery.band(of: todo(due: $0), window: window) }
        XCTAssertEqual(bands, [.noDue, .overdue, .overdue, .today, .today, .thisWeek, .thisWeek, .later, .later])
    }

    // MARK: - 筛选

    func testFilterMatchesEachOfTheFiveRanges() {
        let items = [
            todo("过期", due: at("2026-10-06")),
            todo("今天", due: at("2026-10-07", 10 * 60)),
            todo("本周", due: at("2026-10-09")),
            todo("更晚", due: at("2026-11-01")),
            todo("无截止"),
        ]
        func titles(_ filter: TodoFilter) -> [String] {
            TodoFilter.apply(items, filter: filter, window: window).map(\.title)
        }
        XCTAssertEqual(titles(.all), ["过期", "今天", "本周", "更晚", "无截止"])
        XCTAssertEqual(titles(.today), ["今天"])
        XCTAssertEqual(titles(.thisWeek), ["本周"])
        XCTAssertEqual(titles(.overdue), ["过期"])
        XCTAssertEqual(titles(.noDue), ["无截止"])
    }

    func testFilterTodayAndThisWeekNeverOverlapAndOverdueMissesToday() {
        // 「今天 ∪ 本周」不产生重复行（两档互斥）；「已过期」与「今天 / 本周」也不相交
        // —— 前者是 `due < todayStart`，后两者是 `due >= todayStart`。
        let items = [
            todo("过期", due: at("2026-10-01")),
            todo("今天", due: at("2026-10-07", 8 * 60)),
            todo("本周", due: at("2026-10-10")),
        ]
        let todayRows = TodoFilter.apply(items, filter: .today, window: window).map(\.id)
        let weekRows = TodoFilter.apply(items, filter: .thisWeek, window: window).map(\.id)
        let overdueRows = TodoFilter.apply(items, filter: .overdue, window: window).map(\.id)
        XCTAssertTrue(Set(todayRows).isDisjoint(with: Set(weekRows)))
        XCTAssertTrue(Set(overdueRows).isDisjoint(with: Set(todayRows)))
        XCTAssertTrue(Set(overdueRows).isDisjoint(with: Set(weekRows)))
    }

    func testFilterOverdueConsidersCompletionState() {
        // 「已过期」那一档是**未完成**且过期：做完的事不再催（与分带的差异就在这一条上）。
        let finished = todo("做完了", due: at("2026-10-01"), done: true)
        let open = todo("还欠着", due: at("2026-10-01"))
        XCTAssertEqual(TodoFilter.apply([finished, open], filter: .overdue, window: window).map(\.title), ["还欠着"])
    }

    func testUnknownFilterFallsBackToAll() {
        XCTAssertEqual(TodoFilter.normalized("nonsense"), .all)
        XCTAssertEqual(TodoFilter.normalized(nil), .all)
        XCTAssertEqual(TodoFilter.normalized("  Today "), .today, "归一认小写与首尾空白")
    }

    // MARK: - 排序（契约 §3.13 四条）

    func testSortByDuePutsMissingDueLast() {
        let late = todo("晚", due: at("2026-10-09"))
        let early = todo("早", due: at("2026-10-07"))
        let middle = todo("中", due: at("2026-10-08"))
        let none = todo("无")
        let sorted = TodoSort.sorted([none, late, early, middle])
        XCTAssertEqual(sorted.map(\.title), ["早", "中", "晚", "无"])
    }

    func testSortByPriorityIsHighToLow() {
        let low = todo("低", priority: .low)
        let high = todo("高", priority: .high)
        let normal = todo("普通", priority: .normal)
        XCTAssertEqual(TodoSort.sorted([low, high, normal], order: .priority).map(\.title), ["高", "普通", "低"])
    }

    func testSortByCreatedIsEarliestFirst() {
        let first = todo("先建", created: at("2026-09-01"))
        let second = todo("后建", created: at("2026-10-01"))
        XCTAssertEqual(TodoSort.sorted([second, first], order: .created).map(\.title), ["先建", "后建"])
    }

    func testSortTiesFallBackToCreatedAtThenIdentifier() {
        // 同一个第一关键字 ⇒ 按 `createdAt` 升序；连 `createdAt` 都一样 ⇒ 按标识升序（次序必须确定，
        // 否则界面每次刷新顺序都可能变）。
        let shared = at("2026-09-20")
        let a = todo("甲", priority: .high, created: shared, id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!)
        let b = todo("乙", priority: .high, created: shared, id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!)
        XCTAssertEqual(TodoSort.sorted([b, a], order: .priority).map(\.title), ["甲", "乙"])
    }

    func testSortIsATotalOrderRegardlessOfInputOrder() {
        let items = [
            todo("a", due: at("2026-10-08"), priority: .low, created: at("2026-09-05")),
            todo("b", due: at("2026-10-07"), priority: .high, created: at("2026-09-01")),
            todo("c", due: nil, priority: .normal, created: at("2026-09-03")),
            todo("d", due: at("2026-10-07"), priority: .high, created: at("2026-09-02")),
        ]
        let forward = TodoSort.sorted(items).map(\.title)
        let backward = TodoSort.sorted(items.reversed()).map(\.title)
        XCTAssertEqual(forward, backward, "总序：与输入次序无关")
        XCTAssertEqual(forward, ["b", "d", "a", "c"])
    }

    func testUnknownSortOrderFallsBackToDue() {
        XCTAssertEqual(TodoSort.Order.normalized("nonsense"), .due)
        XCTAssertEqual(TodoSort.Order.normalized(nil), .due)
        XCTAssertEqual(TodoSort.Order.defaultOrder, .due)
    }

    func testSectionsReuseTheOnlyPartitionImplementation() {
        // 排序版的分区与 `TodoPresentation.sections`（传入顺序）是**同一份分区**：
        // 先排再分区 ⇒ 每段内部正好是排好的子序列。
        let items = [
            todo("已做完", due: at("2026-10-07"), done: true),
            todo("晚", due: at("2026-10-09")),
            todo("早", due: at("2026-10-07")),
        ]
        let sections = TodoSort.sections(items)
        XCTAssertEqual(sections.map(\.kind), [.open, .completed])
        XCTAssertEqual(sections[0].todos.map(\.title), ["早", "晚"])
        XCTAssertEqual(sections[1].todos.map(\.title), ["已做完"])
    }

    // MARK: - 分组（`FR-NOTE-37` 的「分组」那一半）

    func testGroupNoneYieldsOneGroup() {
        let board = TodoQuery.board([todo("甲"), todo("乙", done: true)], window: window)
        XCTAssertEqual(board.groupBy, .none)
        XCTAssertEqual(board.groups.count, 1)
        XCTAssertEqual(board.groups[0].key, .all)
        XCTAssertEqual(board.total, 2)
    }

    func testGroupByStatusDropsEmptyGroups() {
        let onlyOpen = TodoQuery.board([todo("甲")], window: window, groupBy: .status)
        XCTAssertEqual(onlyOpen.groups.map(\.key), [.status(.open)])
        let mixed = TodoQuery.board([todo("甲"), todo("乙", done: true)], window: window, groupBy: .status)
        XCTAssertEqual(mixed.groups.map(\.key), [.status(.open), .status(.completed)])
    }

    func testGroupByDueUsesBandOrderAndDropsEmptyBands() {
        let board = TodoQuery.board(
            [
                todo("无"),
                todo("本周", due: at("2026-10-09")),
                todo("过期", due: at("2026-10-06")),
                todo("今天", due: at("2026-10-07", 10 * 60)),
            ],
            window: window,
            groupBy: .due
        )
        XCTAssertEqual(board.groups.map(\.key), [.band(.overdue), .band(.today), .band(.thisWeek), .band(.noDue)])
        XCTAssertEqual(board.total, 4)
    }

    func testGroupByTagPutsUntaggedLastAndLetsOneRowAppearTwice() {
        let both = todo("两条标签", tags: ["b", "a"])
        let untagged = todo("没标签")
        let board = TodoQuery.board([both, untagged], window: window, groupBy: .tag)
        // 标签升序 + 「未分类」最后；同一条带两个标签就出现在两组里（标签分组应有的行为）。
        XCTAssertEqual(board.groups.map(\.key), [.tag("a"), .tag("b"), .untagged])
        XCTAssertEqual(board.total, 3, "一条两标签的任务按组计数两次 —— 组计数不是去重计数")
        XCTAssertFalse(board.groups.map(\.key).contains(.tag("c")), "只认行上真有的标签")
    }

    func testGroupByTagIgnoresTagsOnlyPresentOnFilteredOutRows() {
        // 标签的存亡只看**筛剩下的**那一批（与 `NotesScope.normalized` 同一条用意）。
        let outside = todo("不在窗口里", due: at("2026-11-01"), tags: ["x"])
        let inside = todo("在窗口里", due: at("2026-10-07"), tags: ["y"])
        let board = TodoQuery.board([outside, inside], filter: .today, window: window, groupBy: .tag)
        XCTAssertEqual(board.groups.map(\.key), [.tag("y")])
    }

    func testUnknownGroupByFallsBackToNone() {
        XCTAssertEqual(TodoGroupBy.normalized("nonsense"), .none)
        XCTAssertEqual(TodoGroupBy.normalized(nil), .none)
    }

    // MARK: - 视图（三者合起来）

    func testBoardFiltersThenSortsThenGroups() {
        let items = [
            todo("今天-低", due: at("2026-10-07", 18 * 60), priority: .low),
            todo("今天-高", due: at("2026-10-07", 9 * 60), priority: .high),
            todo("本周-高", due: at("2026-10-09"), priority: .high),
        ]
        let board = TodoQuery.board(items, filter: .today, window: window, order: .priority)
        XCTAssertEqual(board.filter, .today)
        XCTAssertEqual(board.total, 2, "筛选先于分组：本周那条不进屏")
        XCTAssertEqual(board.groups[0].open.map(\.title), ["今天-高", "今天-低"], "组内顺序 = 排序那一档")
    }

    func testBoardGroupingNeverChangesOrderInsideAGroup() {
        let items = [
            todo("过期", due: at("2026-10-01"), created: at("2026-09-10")),
            todo("今天", due: at("2026-10-07", 9 * 60), created: at("2026-09-09")),
            todo("无", created: at("2026-09-08")),
        ]
        // 不分组：整屏就是排序档给的那一份。
        let none = TodoQuery.board(items, window: window, order: .created)
        XCTAssertEqual(none.groups[0].open.map(\.title), ["无", "今天", "过期"])
        // 分组只归堆：组的**顺序**由分组档决定、与排序档无关；每组的**成员**与组内次序仍来自同一套三档。
        let byDue = TodoQuery.board(items, window: window, groupBy: .due, order: .created)
        XCTAssertEqual(byDue.groups.map(\.key), [.band(.overdue), .band(.today), .band(.noDue)])
        let byDueByPriority = TodoQuery.board(items, window: window, groupBy: .due, order: .priority)
        XCTAssertEqual(byDueByPriority.groups.map(\.key), byDue.groups.map(\.key))
        XCTAssertEqual(byDue.groups.map(\.total), [1, 1, 1])
        XCTAssertEqual(byDue.groups.flatMap(\.open).map(\.title).count, items.count, "分组不重复计行")
    }

    func testEmptyInputYieldsEmptyBoard() {
        let board = TodoQuery.board([], window: window, groupBy: .due)
        XCTAssertTrue(board.groups.isEmpty)
        XCTAssertEqual(board.total, 0)
    }

    // MARK: - 形状判据（Core 不读时钟 / 界面不自排）

    func testCoreHasNoClockOrPlatformDateTokens() throws {
        // Core 这一层**只吃调用方传进来的参照窗口**：系统时钟 / 平台日历 / 时区 / 格式化器四类 token 零命中。
        let tokens = ["Date()", "Calendar.current", "TimeZone", "DateFormatter", "startOfDay"]
        for file in ["Core/TodoQuery.swift", "Core/TodoSort.swift"] {
            let text = try source(file)
            for token in tokens {
                XCTAssertFalse(text.contains(token), "\(file) 出现了 \(token)（参照窗口必须由调用方传）")
            }
        }
    }

    func testViewsDoNotSortOrFilterTodoOrderThemselves() throws {
        // 排序 / 筛 / 分组的**唯一入口**是 Core：界面层不许自己 `sorted(by:)`，也不许再用已退役的 `dueState`。
        for file in ["App/Views/TodoCalendarView.swift", "App/Views/NotesPanel.swift"] {
            let text = try source(file)
            XCTAssertFalse(text.contains("sorted(by:"), "\(file) 自己排序（第二套排法）")
            XCTAssertFalse(text.contains("dueState"), "\(file) 还在用退役的 `dueState`（档位已改为 `TodoQuery.band`）")
        }
    }

    // MARK: - 语言表

    func testQueryKeysExistInBothLanguages() {
        var keys: [LKey] = TodoBand.displayOrder.map(\.key)
        keys += TodoFilter.allCases.map(\.key)
        keys += TodoGroupBy.allCases.map(\.key)
        keys += TodoSort.Order.allCases.map(\.key)
        keys.append(TodoGroupKey.untagged.headerKey!)
        for key in keys {
            let chinese = LocalizedStrings.table[key]?[.simplifiedChinese]
            let english = LocalizedStrings.table[key]?[.english]
            XCTAssertNotNil(chinese, "\(key) 缺中文模板")
            XCTAssertNotNil(english, "\(key) 缺英文模板")
            XCTAssertNotEqual(chinese, english, "\(key) 中英同一句（漏了一条）")
        }
        // 组头的键只有一处来源：状态组直接复用段头那两句。
        XCTAssertEqual(TodoGroupKey.status(.open).headerKey, .todoSectionOpen)
        XCTAssertEqual(TodoGroupKey.status(.completed).headerKey, .todoSectionCompleted)
        XCTAssertNil(TodoGroupKey.tag("x").headerKey, "标签组的组头是标签本身（用户数据）")
    }
}
