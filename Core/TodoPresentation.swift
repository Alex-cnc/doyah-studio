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
/// **两件由别处管的事**（本文件只留「分区」与「标题」两件）：
///  · **排序** —— 契约 `DoyahNotes/Docs/核心契约.md` **§3.13** 已于 2026-10-04 落笔（队列 `N-11`
///    的契约半，契约所有者 `bluewhale`）⇒ 排序口径落在 `Core/TodoSort.swift`（**唯一比较器**）；
///  · **截止带 / 逾期判定** —— 落在 `Core/TodoQuery.swift` 的 `TodoBand` / `TodoDue`
///    （**与对侧 `TodoQuery.bandOf` / `TodoDue.isOverdue` 同口径**）。
///
/// ⚠ **一处跟版订正（第 191 轮）**：本文件原来的 `TodoDueState` / `dueState` 把「逾期」判成
/// 「截止时刻已经过去（`dueAt < now`）」—— 与契约 §3.13 第四条（`done = false` 且 `dueAt < 今天`）
/// 和安卓侧实现**不一致**（今晨九点的任务，本侧会画成「已过期」，对侧画成「今天」）。
/// 契约落笔后按两端一致的口径**改为** `TodoBand`（分带不看完成态）+ `TodoDue.isOverdue`（标识看未完成），
/// 旧的 `dueState` 一并删除（留着它就会有一处「第二套档位」）。
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

/// 待办清单这里只留两件事：**分区**与**空标题**（排序在 `TodoSort`，截止带 / 逾期在 `TodoQuery`）。
public enum TodoPresentation {

    /// 按完成态**分区**（`FR-NOTE-36`：「未完成与已完成分区」）。
    ///
    /// 三条口径（都能被单测钉住）：
    ///  ① **两段永远都在**（哪怕一段 0 条）—— 空态与段头计数靠 `count` 判，
    ///     不靠「数组里有没有这一段」：否则界面得各写一套补齐逻辑；
    ///  ② **段序固定**（`TodoSectionKind.displayOrder`）；
    ///  ③ **段内顺序 = 传进来的顺序** —— 本函数是**分区原语**（不重排）；
    ///     「先按档位排再分区」的唯一入口是 `TodoSort.sections(_:order:)`（它调本函数，
    ///     分区因此仍只有这一处实现）。
    public static func sections(_ todos: [Todo]) -> [TodoSection] {
        TodoSectionKind.displayOrder.map { kind in
            TodoSection(kind: kind, todos: todos.filter { $0.done == (kind == .completed) })
        }
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
