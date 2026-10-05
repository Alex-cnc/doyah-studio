import Foundation

/// 待办清单的**排序口径**（队列 `L-100` 的「组织与检索」半 · 需求条文 `FR-NOTE-37`）。
///
/// **口径出处不是本侧发明**：契约 `DoyahNotes/Docs/核心契约.md` **§3.13 待办清单的排序口径**
/// （2026-10-04 契约所有者 `bluewhale` 落笔 · 队列 `N-11` 的契约半）四条 + 对侧实现
/// `DoyahNotes/android/core/.../Todo.kt` 的 `TodoSort`（**引用，不复制代码**）：
///  ① 三档第一关键字 = **截止时间**（早 → 晚）/ **优先级**（`high` → `low`）/ **创建时间**（早 → 晚）；
///  ② **无截止排在末尾**（哨兵取「大于任何真实时刻」的那一个 —— 取 0 会让没定时间的任务挤到最前面）；
///  ③ **同键以 `createdAt` 升序兜底**，再相同按 `id`（同一毫秒建的两条也要有确定次序，
///     否则界面每次刷新顺序都可能变）；
///  ④ **「逾期」只影响展示标识，不改排序位置** —— 所以本文件的比较器**一个字都不提逾期**
///     （逾期判定在 `TodoDue`，带在 `TodoQuery.band`）。
///
/// 三条纪律（与契约 §3.13 同向、也是判据钉住的东西）：
///  1. **不读系统时钟**：本对象只比较已存在的字段，不取参照时刻（与本仓 `Reminder` / `TodoQuery` 同口径）；
///  2. **排序只经本对象**：界面层不得自己 `sorted(by:)` 出清单顺序（那就是第二套排法，
///     两套各自的用例都会是绿的）；
///  3. **两个分区用同一套三档**：`completedAt` 只用于展示，**不做**已完成分区的主排序键
///     （契约 §3.13 与 `Todo.completedAt` 的定位一致）。
public enum TodoSort {

    /// 三档（界面做切换器时遍历 `allCases`；别处不再抄一份档位清单）。
    public enum Order: String, CaseIterable, Sendable {

        /// 第一关键字 = 截止时间（早 → 晚，无截止排末尾）。
        case due
        /// 第一关键字 = 优先级（`high` → `low`）。
        case priority
        /// 第一关键字 = 创建时间（早 → 晚）。
        case created

        /// 默认档 = **截止时间**（与对侧 `TodoSort.DEFAULT` 同一档：待办最常问的是「下一步做什么」）。
        public static var defaultOrder: Order { .due }

        /// 认不出的取值 ⇒ 默认档（与 `TodoPriority` / `ReminderRule` 的「认不出当没给」同族）。
        public static func normalized(_ raw: String?) -> Order {
            guard let raw else { return .defaultOrder }
            return Order(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                ?? .defaultOrder
        }

        /// 这一档在语言表里的名字。
        public var key: LKey {
            switch self {
            case .due: return .todoSortDue
            case .priority: return .todoSortPriority
            case .created: return .todoSortCreated
            }
        }
    }

    /// 无截止的排序哨兵：**大于任何真实时刻**（契约 §3.13 第二条）。
    private static let noDue: Date = .distantFuture

    /// `a` 是否排在 `b` 前面（**总序**：三档各自 + `createdAt` + `id`，逐级兜底）。
    public static func orderedBefore(_ a: Todo, _ b: Todo, order: Order = .defaultOrder) -> Bool {
        let primary: Int
        switch order {
        case .due:
            primary = compareTimes(a.dueAt ?? noDue, b.dueAt ?? noDue)
        case .priority:
            primary = priorityRank(a.priority) - priorityRank(b.priority)
        case .created:
            primary = compareTimes(a.createdAt, b.createdAt)
        }
        if primary != 0 { return primary < 0 }
        let secondary = compareTimes(a.createdAt, b.createdAt)
        if secondary != 0 { return secondary < 0 }
        // 最后一级只有一个要求：**确定**。用 UUID 的字面序（与对侧用自增 id 同一条用意）。
        return a.id.uuidString < b.id.uuidString
    }

    /// 排好的一份新列表（**唯一排序入口**）。
    public static func sorted(_ todos: [Todo], order: Order = .defaultOrder) -> [Todo] {
        todos.sorted { orderedBefore($0, $1, order: order) }
    }

    /// 先按档位排、再按完成态分区（**分区本身仍只有 `TodoPresentation.sections` 一处**）。
    ///
    /// 两个分区**用同一套三档**（契约 §3.13 与 `completedAt` 的定位）；段序固定 = 未完成在前。
    public static func sections(_ todos: [Todo], order: Order = .defaultOrder) -> [TodoSection] {
        TodoPresentation.sections(sorted(todos, order: order))
    }

    /// 优先级排序键：`high`(0) → `normal`(1) → `low`(2)。
    ///
    /// 取值先经 `TodoPriority` 归一 —— 与落库口径**同一处**（`TodoPriority.init(raw:)` 已把认不出的
    /// 变成 `.normal`），这里不写第二份「什么算合法取值」。
    private static func priorityRank(_ priority: TodoPriority) -> Int {
        switch priority {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }

    /// 两个时刻的三向比较（`Date` 自带 `Comparable`，这里只把它变成 `<0 / 0 / >0`）。
    private static func compareTimes(_ a: Date, _ b: Date) -> Int {
        if a < b { return -1 }
        if a > b { return 1 }
        return 0
    }
}
