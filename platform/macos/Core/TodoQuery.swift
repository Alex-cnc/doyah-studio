import Foundation

/// 待办清单的**筛选 / 分组 / 视图**（队列 `L-100` 的「组织与检索」半 · 需求条文 `FR-NOTE-37`）。
///
/// **口径出处**：契约 `DoyahNotes/Docs/核心契约.md` **§3.13**（排序四条，落进 `TodoSort`）
/// 与对侧实现 `DoyahNotes/android/core/.../TodoQuery.kt`（**引用，不复制代码**）——
/// 「哪些行进列表」（筛选）、「怎么归堆」（分组）、「怎么排」（排序）三件事，三端同一套。
///
/// 为什么单独一层（与对侧同一条理由）：清单屏已经有了分区与顺序；「哪些该出现、按什么归堆」
/// 若各写在界面上，就会出现**第三套口径** —— 今天 / 本周的边界各算一遍、逾期各判一遍、
/// 标签归堆各写一遍，而每一处单独的用例都是绿的。
///
/// 四条口径（改之前先读）：
///  ① **参照窗口由调用方传**（`TodoWindow`：今天零点 / 明天零点 / 下周一零点）——
///     Core **不读系统时钟**（与 `Reminder` / `TodoCalendar` 同口径）；边界换算只经
///     `ReminderSchedule` 的日序原语（两端同口径、有跨端黄金样例），本层**不新写日期加减**；
///  ② **筛选与分组是两件正交的事**：筛选决定哪些行进来，分组决定怎么归堆；两者都**不改顺序**
///     —— 顺序仍只有 `TodoSort` 一处（「分组不改排序」= 组内仍是同一套三档）；
///  ③ **带与徽标是两件事，但共用同一套带**：分带（`band`）**不看完成态**（它回答「落在哪一天」），
///     逾期**标识**（`TodoDue.isOverdue`）**只看未完成**（它回答「要不要催」）—— 契约 §3.13 第四条；
///  ④ **认不出的取值「当没给」**：筛选 / 分组 / 排序的取值都只认本文件登记的档，认不出回默认档
///     （原样装进去会让界面显示一个不存在的档，而库里那一行永远筛不出来）。

/// 清单的**参照窗口**：三个边界时刻，**全由调用方传**。
///
/// 三个值都取「当天零点」，因此区间一律**左闭右开**：`[todayStart, tomorrowStart)` = 今天；
/// `[tomorrowStart, weekEnd)` = 本周剩下的日子。边界值的唯一生产入口是 ``of(today:zoneOffsetMillis:)``。
public struct TodoWindow: Equatable, Sendable {

    /// 今天零点。
    public let todayStart: Date
    /// 明天零点。
    public let tomorrowStart: Date
    /// 下周一零点（**周一起算**，与 `TodoCalendar` 的 `firstWeekdayISO` 同口径）。
    public let weekEnd: Date

    public init(todayStart: Date, tomorrowStart: Date, weekEnd: Date) {
        self.todayStart = todayStart
        self.tomorrowStart = tomorrowStart
        self.weekEnd = weekEnd
    }

    /// 「本地日历日 + 时区偏移」→ 三个边界（**唯一生产入口**：端侧只给这两样）。
    ///
    /// 日历加减**不在这里新写**：`dateOfDay(dayOf(date) + n)` 走 `ReminderSchedule` 的日序原语，
    /// 到点成形走 `ReminderSchedule.toEpoch`（清单的截止时间与提醒的到点因此共用同一套算术 ——
    /// 差一天是用户唯一会记住的那种错）。
    ///
    /// **脏值不抛错**：日期串非法 ⇒ 三个边界一起退到「远古」，此时任何有截止的任务都落在「更晚」那一带
    /// （宁可少提醒，也不凭空编一个日子出来）。
    public static func of(today: String, zoneOffsetMillis: Int) -> TodoWindow {
        let day = ReminderSchedule.dayOf(today)
        guard day >= 0 else {
            return TodoWindow(todayStart: .distantPast, tomorrowStart: .distantPast, weekEnd: .distantPast)
        }
        let weekday = ReminderSchedule.weekdayOfDay(day)
        func start(_ dayNumber: Int) -> Date {
            let epoch = ReminderSchedule.toEpoch(
                moment: ReminderMoment(date: ReminderSchedule.dateOfDay(dayNumber), minute: 0),
                zoneOffsetMillis: zoneOffsetMillis
            )
            return epoch < 0 ? .distantPast : Date(timeIntervalSince1970: Double(epoch) / 1000)
        }
        return TodoWindow(
            todayStart: start(day),
            tomorrowStart: start(day + 1),
            weekEnd: start(day + (8 - weekday))
        )
    }
}

/// 截止时间落在**哪一带**（`FR-NOTE-37` 的时间分组 + `FR-NOTE-38` 的逾期标识共用这一套取值）。
///
/// **互斥且穷尽**：任何一条任务都有且只有一个带（单测钉住这一条）。判定**只看截止时间**，
/// 不看完成态 —— 与「逾期标识」（``TodoDue/isOverdue(_:window:)``）刻意分开，见文件头 ③。
public enum TodoBand: String, CaseIterable, Sendable {

    /// 已过期：截止时间早于今天零点。
    case overdue
    /// 今天。
    case today
    /// 本周（今天之后、下周一零点之前）。
    case thisWeek
    /// 更晚（本周之后）。
    case later
    /// 无截止。
    case noDue

    /// 这一带在语言表里的名字。
    public var key: LKey {
        switch self {
        case .overdue: return .todoDueOverdue
        case .today: return .todoDueToday
        case .thisWeek: return .todoDueThisWeek
        case .later: return .todoDueLater
        case .noDue: return .todoDueNone
        }
    }

    /// 屏上顺序：先看还欠着的，再看今天 / 本周，最后是没定时间的（与对侧 `TodoQuery.BANDS` 同序）。
    public static var displayOrder: [TodoBand] {
        [.overdue, .today, .thisWeek, .later, .noDue]
    }
}

/// 逾期的**唯一判定处**（契约 §3.13 第四条：`done = false` 且 `dueAt < 今天`）。
public enum TodoDue {

    /// 是否逾期：未完成 且 截止时间早于今天零点；**无截止永不逾期**。
    public static func isOverdue(_ todo: Todo, window: TodoWindow) -> Bool {
        isOverdue(todo.dueAt, done: todo.done, todayStart: window.todayStart)
    }

    /// 同上，但吃三个散字段（日历那一层手上只有「参照时刻 + 日历」，见 `TodoCalendar.tasksByDay`）。
    public static func isOverdue(_ dueAt: Date?, done: Bool, todayStart: Date) -> Bool {
        guard let dueAt else { return false }
        return !done && dueAt < todayStart
    }

    /// 同上，参照时刻只给「今天零点」那一半（与对侧 `TodoDue.isOverdue(todo, todayStart)` 同形）。
    public static func isOverdue(_ todo: Todo, todayStart: Date) -> Bool {
        isOverdue(todo.dueAt, done: todo.done, todayStart: todayStart)
    }
}

/// 清单的**筛选档位**（`FR-NOTE-37` 的「筛选」那一半）—— 取值空间只落这一处。
public enum TodoFilter: String, CaseIterable, Sendable {

    /// 全部（不筛；**默认档** —— 用户进清单先看到全部）。
    case all
    /// 今天：截止时间落在 `[todayStart, tomorrowStart)`。
    case today
    /// 本周：截止时间在明天零点之后、下周一零点之前（**今天不算** —— 两档互斥才让「今天 ∪ 本周」不产生重复行）。
    case thisWeek
    /// 已过期：**未完成**且截止时间早于今天零点（判定复用 ``TodoDue/isOverdue(_:window:)``）。
    case overdue
    /// 无截止。
    case noDue

    /// 默认档 = 全部。
    public static var defaultFilter: TodoFilter { .all }

    /// 认不出的档位「当没给」= 默认档。
    public static func normalized(_ raw: String?) -> TodoFilter {
        guard let raw else { return .defaultFilter }
        return TodoFilter(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            ?? .defaultFilter
    }

    /// 这一档在语言表里的名字（切换器的唯一出处）。
    public var key: LKey {
        switch self {
        case .all: return .todoFilterAll
        case .today: return .todoFilterToday
        case .thisWeek: return .todoFilterThisWeek
        case .overdue: return .todoFilterOverdue
        case .noDue: return .todoFilterNoDue
        }
    }

    /// 一行是否落在当前档。
    public func matches(_ todo: Todo, window: TodoWindow) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            guard let dueAt = todo.dueAt else { return false }
            return dueAt >= window.todayStart && dueAt < window.tomorrowStart
        case .thisWeek:
            guard let dueAt = todo.dueAt else { return false }
            return dueAt >= window.tomorrowStart && dueAt < window.weekEnd
        case .overdue:
            return TodoDue.isOverdue(todo, window: window)
        case .noDue:
            return todo.dueAt == nil
        }
    }

    /// 筛出当前档的行（**唯一筛选入口**：界面只调它，不自己 `filter`）。
    public static func apply(_ todos: [Todo], filter: TodoFilter, window: TodoWindow) -> [Todo] {
        todos.filter { filter.matches($0, window: window) }
    }
}

/// 清单的**分组档位**（`FR-NOTE-37` 的「分组」那一半）—— 取值空间只落这一处。
public enum TodoGroupBy: String, CaseIterable, Sendable {

    /// 不分组（只有未完成 / 已完成两区）—— **默认档**，与界面半第一片的行为一致（升级不动老体验）。
    case none
    /// 按状态（未完成 / 已完成两组）。
    case status
    /// 按时间（截止时间落哪一带：见 `TodoBand`）。
    case due
    /// 按标签（一条任务带两个标签就出现在两组里 —— 这是标签分组应有的行为；没有标签的归「未分类」）。
    case tag

    /// 默认档 = 不分组。
    public static var defaultGroupBy: TodoGroupBy { .none }

    /// 认不出的档位「当没给」= 默认档。
    public static func normalized(_ raw: String?) -> TodoGroupBy {
        guard let raw else { return .defaultGroupBy }
        return TodoGroupBy(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            ?? .defaultGroupBy
    }

    /// 这一档在语言表里的名字（切换器的唯一出处）。
    public var key: LKey {
        switch self {
        case .none: return .todoGroupNone
        case .status: return .todoGroupStatus
        case .due: return .todoGroupDue
        case .tag: return .todoGroupTag
        }
    }
}

/// 一组的**组键**（语言中立；界面按它出文案 —— 标签组把标签原样带出来）。
///
/// 为什么不直接用字符串键（对侧用的是带前缀的 `String`）：这里用枚举把「标签叫 `today` 时会与
/// 时间带撞车」这件事在**类型上**去掉 —— 标签组是 `.tag("today")`，与 `.band(.today)` 是两件事，
/// 不可能撞。
/// `Hashable` 是给界面用的（`ForEach(..., id: \.key)`）—— 组键本来就是身份，不是内容。
public enum TodoGroupKey: Hashable, Sendable {

    /// 不分组时唯一那一组。
    case all
    /// 按状态分组的组键。
    case status(TodoSectionKind)
    /// 按时间分组的组键。
    case band(TodoBand)
    /// 按标签分组：某个标签（**标签本身是用户数据**，界面照原样显示）。
    case tag(String)
    /// 按标签分组：没有标签的行。
    case untagged

    /// 组头那句话的键；标签组在语言表之外（`nil` = 用组键里的标签本身）。
    public var headerKey: LKey? {
        switch self {
        case .all: return .todoAll
        case .status(let kind): return kind.titleKey
        case .band(let band): return band.key
        case .tag: return nil
        case .untagged: return .todoGroupUntagged
        }
    }

    /// 组头**那句话**：能翻的去语言表（`text` 由界面把 `L(...)` 传进来 —— 与 `TodoPresentation`
    /// 同一条纪律：Core 里一个汉字都没有），标签组给标签本身。
    ///
    /// 为什么由 Core 决定「哪一类去语言表、哪一类给原文」：让界面自己 `switch` 一遍组键，
    /// 就出现了第二份「什么键长什么样」的口径（新增一类组键时，改一处的人不会想到另一处）。
    public func headerText(_ text: (LKey) -> String) -> String {
        switch self {
        case .tag(let tag): return tag
        default: return headerKey.map(text) ?? ""
        }
    }
}

/// 一个分组：组键 + 组内两区（未完成 / 已完成，各自已按当前档位排好）。
///
/// 两区**始终都在**（分组不改变「未完成与已完成分区」这条既有口径）；按状态分组时其中一区必空 ——
/// 界面据此不再画内层分区头（组头已经是那两句话）。
public struct TodoGroup: Equatable, Sendable {

    public let key: TodoGroupKey
    public let open: [Todo]
    public let done: [Todo]

    public init(key: TodoGroupKey, open: [Todo] = [], done: [Todo] = []) {
        self.key = key
        self.open = open
        self.done = done
    }

    /// 组内条数（组头右侧的计数）。
    public var total: Int { open.count + done.count }

    /// 组内两区（未完成 / 已完成）—— **分区仍只有 `TodoPresentation.sections` 一处**：
    /// 这里只是把已经分好、已经排好的两批装回 `TodoSection`（不重排，见该函数的第 ③ 条口径）。
    ///
    /// 为什么要有它：分组那一屏不能把 `Section` 套在 `Section` 里，界面得把「组」画成外层、
    /// 把「未完成 / 已完成」画成组内的行 —— 若界面自己 `filter` 两遍来凑这两区，
    /// 就是第二条分区口径（对侧由 `check-ui-parity.py` 判红的那一族）。
    public var sections: [TodoSection] { TodoPresentation.sections(open + done) }
}

/// 清单的一屏视图：当前筛选档 + 分组档 + 归好堆的组（空组已被丢掉）。
public struct TodoBoard: Equatable, Sendable {

    public let filter: TodoFilter
    public let groupBy: TodoGroupBy
    public let groups: [TodoGroup]

    public init(filter: TodoFilter, groupBy: TodoGroupBy, groups: [TodoGroup]) {
        self.filter = filter
        self.groupBy = groupBy
        self.groups = groups
    }

    /// 屏上总条数（空态判定用 —— 与界面半第一片的 `count` 同一条用意：只有一处判空）。
    public var total: Int { groups.reduce(0) { $0 + $1.total } }

    /// **不分组**那一档的两区（分组档回空表 —— 组头已经承担了分组口径，见 `TodoGroupListView`）。
    ///
    /// 为什么让 Core 出这一句：界面若自己写 `groups.first?.sections ?? []`，
    /// 「哪一档才有两区」这条口径就住进了视图（分组档下它会静默画出一组两段，与组头重复）。
    public var sections: [TodoSection] {
        groupBy == .none ? (groups.first?.sections ?? []) : []
    }
}

/// 清单**空态**的两句话（队列 `L-100` 的组织与检索界面半）：`board.total == 0` 时该说哪一句。
///
/// 为什么要分两句：界面半第一片只有一句「还没有待办」（那时清单没有任何档位，空就是真的空）；
/// 有了筛选档之后，「库里一条都没有」与「有任务、但当前这一档把它们全筛掉了」是两种处境 ——
/// 都画同一句话，用户会以为自己的任务丢了（他会去找，找不到，然后来报一个不存在的 bug）。
public enum TodoEmptyKind: Equatable, Sendable {

    /// 一条任务都没有。
    case none
    /// 有任务，但当前这一档筛不出（把档位带出来，界面可以只说一句、也可以据此提示怎么回来）。
    case filteredOut(TodoFilter)

    /// 这一句在语言表里的键。
    public var key: LKey {
        switch self {
        case .none: return .todosEmpty
        case .filteredOut: return .todosEmptyFiltered
        }
    }
}

/// 清单的**唯一查询入口**：筛选 → 分区 → 分组。
///
/// 界面只 `board(...)` 一次然后照着画 —— 自己 `filter` / 自己归堆就是第二套口径
/// （对侧由 `android/tools/check-ui-parity.py` 的 V 条判红；本侧由 `Tests/TodoQueryTests.swift`
/// 的形状判据 + 队列条目钉住）。
public enum TodoQuery {

    /// 一行落在哪一带（**互斥且穷尽**：任何一行都有且只有一个带）。
    public static func band(of todo: Todo, window: TodoWindow) -> TodoBand {
        guard let dueAt = todo.dueAt else { return .noDue }
        if dueAt < window.todayStart { return .overdue }
        if dueAt < window.tomorrowStart { return .today }
        if dueAt < window.weekEnd { return .thisWeek }
        return .later
    }

    /// 清单空态该说哪一句（**唯一判定处**）：只吃两样 —— 库里有没有任务、当前是哪一档。
    ///
    /// 界面只在 `board.total == 0` 时问它；此时 `hasAnyTask == true` 且档位不是「全部」
    /// 就是「这一档筛掉了」（「全部」档下筛不掉任何一行，所以那一支到不了）。
    public static func emptyKind(hasAnyTask: Bool, filter: TodoFilter) -> TodoEmptyKind {
        hasAnyTask && filter != .defaultFilter ? .filteredOut(filter) : .none
    }

    /// 清单视图（**唯一入口**）：筛 → 排 → 分区 → 归堆。
    ///
    /// 组顺序固定：不分组 = 1 组（键 `.all`）；按状态 = 未完成 → 已完成；按时间 = `TodoBand.displayOrder`；
    /// 按标签 = 标签升序（确定序）+ 「未分类」最后。**空组一律丢掉**（界面上不画空组）。
    public static func board(
        _ todos: [Todo],
        filter: TodoFilter = .defaultFilter,
        window: TodoWindow,
        groupBy: TodoGroupBy = .defaultGroupBy,
        order: TodoSort.Order = .defaultOrder
    ) -> TodoBoard {
        let kept = TodoFilter.apply(todos, filter: filter, window: window)
        let sections = TodoSort.sections(kept, order: order)
        let open = sections.first { $0.kind == .open }?.todos ?? []
        let done = sections.first { $0.kind == .completed }?.todos ?? []

        let groups: [TodoGroup]
        switch groupBy {
        case .none:
            groups = [TodoGroup(key: .all, open: open, done: done)]

        case .status:
            groups = [
                TodoGroup(key: .status(.open), open: open),
                TodoGroup(key: .status(.completed), done: done),
            ]

        case .due:
            groups = TodoBand.displayOrder.map { band in
                TodoGroup(
                    key: .band(band),
                    open: open.filter { self.band(of: $0, window: window) == band },
                    done: done.filter { self.band(of: $0, window: window) == band }
                )
            }

        case .tag:
            // 标签的存亡只看**筛剩下的**那一批（与 `NotesScope.normalized` 同一条用意：
            // 拿得到行才谈得上这个标签还在不在）。
            let tags = Set(kept.flatMap { $0.tags }).sorted()
            var tagged = tags.map { tag in
                TodoGroup(
                    key: .tag(tag),
                    open: open.filter { $0.tags.contains(tag) },
                    done: done.filter { $0.tags.contains(tag) }
                )
            }
            if kept.contains(where: { $0.tags.isEmpty }) {
                tagged.append(
                    TodoGroup(
                        key: .untagged,
                        open: open.filter { $0.tags.isEmpty },
                        done: done.filter { $0.tags.isEmpty }
                    )
                )
            }
            groups = tagged
        }

        return TodoBoard(
            filter: filter,
            groupBy: groupBy,
            groups: groups.filter { $0.total > 0 }
        )
    }
}
