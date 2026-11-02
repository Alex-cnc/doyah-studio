import XCTest
@testable import DoyahCore

/// `FR-NTS-TODO-LIST-003`（待办的组织与检索 · 概设 §15.11 后三行）的机械证据。
///
/// 这一条**不是新功能**：分组 / 筛选 / 排序三件在 `Core/TodoQuery.swift` / `TodoSort.swift` 已落地，
/// 界面切换器在 `TodoQueryBar`。缺的是「三条判据各有一条可判定的读数」——
/// 本文件补的就是这三条（每条都配得上一条会变红的负例，见各用例注释）。
///
/// 判据原文（需求书 §3.5 `FR-NTS-TODO-LIST-003`）：
///   ① 分组与筛选可组合；② 筛选结果与清单同源（不另算一份）；③ 标签与清单归属是同一维，
///   不出现第二个字段。
final class TodoQueryOrganizationTests: XCTestCase {

    private let window = TodoWindow(
        todayStart: Date(timeIntervalSince1970: 1_700_000_000),
        tomorrowStart: Date(timeIntervalSince1970: 1_700_086_400),
        weekEnd: Date(timeIntervalSince1970: 1_700_432_000)
    )

    private func todo(
        _ title: String,
        due: TimeInterval? = nil,
        done: Bool = false,
        priority: TodoPriority = .normal,
        tags: [String] = [],
        created: TimeInterval = 0
    ) -> Todo {
        Todo(
            title: title,
            dueAt: due.map { Date(timeIntervalSince1970: 1_700_000_000 + $0) },
            done: done,
            priority: priority,
            tags: tags,
            createdAt: Date(timeIntervalSince1970: 1_699_000_000 + created),
            updatedAt: Date(timeIntervalSince1970: 1_699_000_000 + created)
        )
    }

    /// 一批覆盖五档的任务（今天两条、本周一条、更晚一条、过期一条、无截止一条）。
    private func sampleTodos() -> [Todo] {
        [
            todo("今天甲", due: 3_600, tags: ["工作"]),
            todo("今天乙", due: 7_200, priority: .high, tags: ["家"]),
            todo("本周", due: 200_000, tags: ["工作", "家"]),
            todo("更晚", due: 900_000),
            todo("过期", due: -86_400, tags: ["工作"]),
            todo("无截止", tags: []),
            todo("已完成的今天", due: 3_600, done: true, tags: ["工作"]),
        ]
    }

    // MARK: - 判据①：分组与筛选可组合

    /// 筛「今天」再按标签分组：**条数对得上**（组内合计 == 只筛不分的条数），
    /// 且每一条都真的同时满足「今天」与它所在的那个标签。
    ///
    /// 负例（会变红）：分组时不再从筛选剩下的那一批里取（例如按全量归堆）⇒ 合计 ≠ 筛选条数。
    func testFilterAndGroupingComposeWithoutChangingTheRowSet() {
        let todos = sampleTodos()
        let filtered = TodoQuery.board(todos, filter: .today, window: window)
        let combined = TodoQuery.board(todos, filter: .today, window: window, groupBy: .tag)

        XCTAssertEqual(filtered.total, 3, "今天档 = 两条未完成 + 一条已完成（分档不看完成态）")
        XCTAssertEqual(combined.total, filtered.total, "分组不许多一条、也不许少一条")

        let flatIDs = combined.groups.flatMap { $0.open.map(\.id) + $0.done.map(\.id) }
        XCTAssertEqual(Set(flatIDs), Set(filtered.sections.flatMap { $0.todos.map(\.id) }))
        // 按标签分组时**同一条任务可以出现在两组里**（它带两个标签 —— 契约 §3.13 的既定行为）；
        // 但不许出现在第三组，也不许把一条单标签任务复制到别处。
        var counts: [UUID: Int] = [:]
        for group in combined.groups {
            for row in group.open + group.done { counts[row.id, default: 0] += 1 }
        }
        let byID = Dictionary(uniqueKeysWithValues: todos.map { ($0.id, $0) })
        for (id, count) in counts {
            XCTAssertEqual(count, byID[id]?.tags.count ?? 0, "出现次数必须等于它带几个标签")
        }

        // 每一条都同时满足两个条件（组合是**交集**，不是并集）
        for group in combined.groups {
            for row in group.open + group.done {
                XCTAssertTrue(TodoFilter.today.matches(row, window: window), "\(row.title) 不在今天档里")
                if case .tag(let tag) = group.key {
                    XCTAssertTrue(row.tags.contains(tag), "\(row.title) 不在标签 \(tag) 那一组")
                }
            }
        }
    }

    /// 三档分组 × 五档筛选全组合：每一格的总数都等于「只筛」的条数，且一条不重复。
    ///
    /// 负例（会变红）：任一档分组在某个筛选下丢行或多行 ⇒ 这一格对不上。
    func testEveryGroupingAgreesWithEveryFilter() {
        let todos = sampleTodos()
        for filter in TodoFilter.allCases {
            let baseline = TodoQuery.board(todos, filter: filter, window: window)
            let baselineIDs = Set(baseline.sections.flatMap { $0.todos.map(\.id) })
            for groupBy in TodoGroupBy.allCases {
                let board = TodoQuery.board(todos, filter: filter, window: window, groupBy: groupBy)
                let ids = board.groups.flatMap { $0.open.map(\.id) + $0.done.map(\.id) }
                XCTAssertEqual(
                    Set(ids), baselineIDs,
                    "筛选 \(filter.rawValue) × 分组 \(groupBy.rawValue) 的行集与只筛不一致"
                )
                if groupBy == .tag {
                    // 标签组按「包含」归堆：一条多标签任务出现在多组里是**既定语义**（契约 §3.13），
                    // 所以这一档只判「没有凭空多出来的行」+「组内每行真有这个标签」。
                    for group in board.groups {
                        guard case .tag(let tag) = group.key else { continue }
                        for row in group.open + group.done {
                            XCTAssertTrue(row.tags.contains(tag), "\(row.title) 不在标签 \(tag) 那一组")
                        }
                    }
                } else {
                    XCTAssertEqual(board.total, baseline.total, "筛选 \(filter.rawValue) × 分组 \(groupBy.rawValue) 的条数对不上")
                    XCTAssertEqual(Set(ids).count, ids.count, "同一条任务在 \(groupBy.rawValue) 里出现了两次")
                }
            }
        }
    }

    // MARK: - 判据②：筛选结果与清单同源（不另算一份）

    /// 一屏视图里的每一行**就是**输入那一份数据里的那一行（值与 id 都相等，不是拷贝改过的）。
    ///
    /// 负例（会变红）：视图层自己再算一遍（例如自己按「今天」重判一次、顺手把 `done` 翻成 `true`）
    /// ⇒ 这一条立刻不等。
    func testBoardRowsAreTheSameObjectsAsTheLoadedList() {
        let todos = sampleTodos()
        let board = TodoQuery.board(todos, filter: .all, window: window, groupBy: .due)
        let byID = Dictionary(uniqueKeysWithValues: todos.map { ($0.id, $0) })
        for group in board.groups {
            for row in group.open + group.done {
                XCTAssertEqual(row, byID[row.id], "清单里那一行必须与库里那一份逐字段相同")
            }
        }
    }

    /// 换视图（分组 / 排序 / 筛选）不产生第二套状态：同一份输入任何一次换法都落在**同一批行**里。
    ///
    /// 负例（会变红）：某个档位悄悄复制 / 删除行（例如按时间分组时把无截止的丢掉）。
    func testSwitchingViewsNeverInventsOrDropsRows() {
        let todos = sampleTodos()
        let all = Set(todos.map(\.id))
        for groupBy in TodoGroupBy.allCases {
            for order in TodoSort.Order.allCases {
                let board = TodoQuery.board(todos, filter: .all, window: window, groupBy: groupBy, order: order)
                let ids = Set(board.groups.flatMap { $0.open.map(\.id) + $0.done.map(\.id) })
                XCTAssertEqual(ids, all, "\(groupBy.rawValue) × \(order.rawValue) 换视图后行集变了")
            }
        }
    }

    // MARK: - 判据③：标签与清单归属是同一维

    /// 源树判据：`Todo` 的持久维度（`CodingKeys` 那一行）**只许这一套**，分类维度只有 `tags`。
    ///
    /// 覆盖范围（如实声明）：只读 `Core/Todo.swift` 里 `Todo` 的 `CodingKeys` 声明行 ——
    /// 它决定「什么会被存 / 会被同步」，是「第二套分类字段」唯一能藏住的形状；
    /// 不扫其它文件的局部变量（那不是模型的维度）。
    ///
    /// 负例（会变红）：在 `Todo` 上加一个 `listName: String` 并写进 `CodingKeys` ⇒ 这一条判红点名它。
    func testTodoHasExactlyOneClassificationDimension() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Core/Todo.swift"), encoding: .utf8)

        // 扫**整个** `CodingKeys` 枚举体，不只扫写着一串名字的那一行 ——
        // 只扫一行的话，另起一行 `case listName` 就能绕过这条判据（实测：那样改它仍判绿）。
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let startIndex = try XCTUnwrap(
            lines.firstIndex { $0.contains("enum CodingKeys") },
            "找不到 `Todo` 的 `CodingKeys` 声明 —— 判据锚点失效（先修判据，别改断言）"
        )
        var cases: [String] = []
        var depth = 0
        var opened = false
        for line in lines[startIndex...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("case ") {
                cases.append(String(trimmed.dropFirst("case ".count)))
            }
            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth > 0 { opened = true }
            if opened && depth == 0 { break }
        }
        let names = cases
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        XCTAssertEqual(
            Set(names),
            [
                "id", "title", "note", "dueAt", "done", "completedAt", "priority", "tags",
                // `repeatRule` 是**本体字段**（`FR-NTS-TODO-LIST-001` 判据①的第四个），不是分类维度：
                // 它说的是「这一条按什么节律再发生」，不参与归堆。加它不改「分类维度只有 `tags`」这条口径。
                "repeatRule", "createdAt", "updatedAt",
            ],
            "待办的持久维度只许这一套：分类维度只有 `tags` 一个"
        )
        XCTAssertTrue(names.contains("tags"), "标签那一维必须在")
        for forbidden in ["listName", "category", "bucket", "project", "folder", "groupId"] {
            XCTAssertFalse(names.contains(forbidden), "不许第二套分类字段：\(forbidden)")
        }
    }

    /// 标签分组的组键是**标签本身**（用户数据），没有标签的落「未分类」；
    /// 这与清单归属是同一维：改了标签就换了组，不另有一个「清单」字段在背后分堆。
    ///
    /// 负例（会变红）：改 `tags` 不动组（说明另有一个字段在决定归属）。
    func testTagGroupingFollowsTheTagsFieldOnly() {
        let onlyWork = todo("A", tags: ["工作"])
        let regrouped = Todo(id: onlyWork.id, title: "A", tags: ["家"], createdAt: onlyWork.createdAt, updatedAt: onlyWork.updatedAt)

        let before = TodoQuery.board([onlyWork], filter: .all, window: window, groupBy: .tag)
        let after = TodoQuery.board([regrouped], filter: .all, window: window, groupBy: .tag)

        XCTAssertEqual(before.groups.map(\.key), [.tag("工作")])
        XCTAssertEqual(after.groups.map(\.key), [.tag("家")])
    }
}
