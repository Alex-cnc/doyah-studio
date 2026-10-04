import Foundation

/// 待办清单（队列 `L-100` 的「清单」界面）要用的三件**纯逻辑**：分区、截止档位、空标题。
///
/// 为什么放进 Core 而不是视图里（与 `NotePresentation` 同一条理由）：
///  ① **分区**（未完成 / 已完成）与**截止档位**（今天 / 明天 / 已过期…）是**语义**，
///     写在视图里就是一串 `if`，谁都断言不到；档位边界（到点那一刻 / 跨零点 / 未来时刻）
///     只能靠构造时刻来钉；
///  ② Core 里**一个汉字都不许有**（R-45 棘轮）：这里只出「哪一档 + 哪个键」，
///     句子由语言表给（`LKey`），于是中英界面各出各的形状。
///
/// **刻意不做的事：排序。** 三档排序口径（第一关键字 / 无截止排哪一端 / 同键次序 / 逾期的排序影响）
/// 属**契约半**（`DoyahNotes/Docs/核心契约.md`；契约层所有者 `bluewhale`，派单 `T-20261004-002` 在办）
/// —— 契约落笔前**不自行发明第二套次序**，所以这里的函数一律**保持传入顺序**
/// （行序由库读回时那一份决定，与 `NoteLibrary.todos` 同源）。
public enum TodoSectionKind: CaseIterable, Equatable, Sendable {

    /// 未完成（`done == false`）。
    case open
    /// 已完成（`done == true`）。
    case completed

    /// 本分区段头那一句话的键（句子只在语言表里）。
    public var titleKey: LKey {
        switch self {
        case .open: return .todoSectionOpen
        case .completed: return .todoSectionCompleted
        }
    }

    /// **已完成分区默认折叠**（需求条文 `FR-NOTE-36` 原文：「已完成默认折叠」）。
    ///
    /// 这里只给**默认值**：折叠状态是界面状态（住 `AppState`），Core 不持有它 ——
    /// 与侧边栏折叠状态同一条纪律（状态有归属、写入口唯一）。
    public var isCollapsedByDefault: Bool {
        self == .completed
    }

    /// 段序 = **未完成在前、已完成在后**（固定；与排序口径无关）。
    public static var displayOrder: [TodoSectionKind] {
        [.open, .completed]
    }
}

/// 一个分区：段头 + 该段的任务（**顺序 = 传进来的那一份**，见 `TodoPresentation.sections`）。
public struct TodoSection: Equatable, Sendable {

    public let kind: TodoSectionKind
    public let todos: [Todo]

    public init(kind: TodoSectionKind, todos: [Todo]) {
        self.kind = kind
        self.todos = todos
    }

    /// 条数（空态判定与段头计数都读它 —— 只有一处）。
    public var count: Int { todos.count }
}

/// 截止时间相对「现在」的那一档（`FR-NOTE-38` 的「逾期任务显式标识」）。
public enum TodoDueState: Equatable, Sendable {

    /// 没有截止时间。
    case none
    /// **已过期**：截止时刻已经过去了（**无论是不是今天** —— 今天早上那个点也照样是过期）。
    case overdue
    /// 今天之内、还没到点。
    case today
    /// 明天（**日历意义上的明天**，不是「24 小时之后」）。
    case tomorrow
    /// 后天及更远。
    case later

    /// 这一档对应的语言表键。
    public var key: LKey {
        switch self {
        case .none: return .todoDueNone
        case .overdue: return .todoDueOverdue
        case .today: return .todoDueToday
        case .tomorrow: return .todoDueTomorrow
        case .later: return .todoDueLater
        }
    }
}

/// 待办清单的三条纯函数。
public enum TodoPresentation {

    /// 按完成态**分区**（`FR-NOTE-36`：「未完成与已完成分区」）。
    ///
    /// 三条口径（都能被单测钉住）：
    ///  ① **两段永远都在**（哪怕一段 0 条）—— 空态与段头计数靠 `count` 判，
    ///     不靠「数组里有没有这一段」：否则界面得各写一套补齐逻辑；
    ///  ② **段序固定**（`TodoSectionKind.displayOrder`）；
    ///  ③ **段内顺序 = 传进来的顺序** —— 排序是契约半的事（见本文件顶部），这里不重排。
    public static func sections(_ todos: [Todo]) -> [TodoSection] {
        TodoSectionKind.displayOrder.map { kind in
            TodoSection(kind: kind, todos: todos.filter { $0.done == (kind == .completed) })
        }
    }

    /// 截止档位（`FR-NOTE-38` 的逾期标识）。
    ///
    /// 四条口径：
    ///  ① **逾期 = 截止时刻已经过去**（`dueAt < now`，严格小于）—— 今天早上 09:00 那个点
    ///     到下午就是**逾期**，不是「今天」：清单上最要紧的就是它还欠着；
    ///  ② **正好等于 `now`** ⇒ 算「今天」（还没过去）—— 边界只钉一次，别两处各判各的；
    ///  ③ 今天之内未到点 ⇒ `.today`；日历日差 1 天 ⇒ `.tomorrow`；更远 ⇒ `.later`
    ///     （**按日历日差算**，不按 24 / 48 小时近似：23:59 → 次日 00:01 就是明天）；
    ///  ④ **与完成态无关**：本函数只回答「这个截止时间相对现在是哪一档」；
    ///     已完成那一段画不画徽标是界面的事（`L-100` 界面半接线）。
    public static func dueState(
        _ dueAt: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TodoDueState {
        guard let dueAt else { return .none }
        if dueAt < now { return .overdue }
        if calendar.isDate(dueAt, inSameDayAs: now) { return .today }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: dueAt)
        ).day ?? 0
        return days <= 1 ? .tomorrow : .later
    }

    /// 行标题：**空白标题 ⇒ `nil`**，由视图用语言表兜底（`notesUntitled` 同族口径）。
    ///
    /// 口径：① 只有「全是空白」（空串 / 空格 / 换行 / 制表）才算没标题 —— 首尾空白**不删**
    /// （标题里的缩进是用户写的，Core 不擅自改写内容）；② 判定只有这一处，
    /// 免得「清单」与「日历」两个界面各写一套「空标题显示成什么」。
    public static func title(_ todo: Todo) -> String? {
        todo.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : todo.title
    }
}
