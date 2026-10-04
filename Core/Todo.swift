import Foundation

/// 待办任务的优先级（`DoyahNotes` 核心契约 `Todo.priority`；需求条文 `FR-NOTE-36`）。
///
/// 取值即协议、**只增不改**（提案 `0004` 裁决 ①）：认不出的取值**「当没给」= `.normal`**
/// —— 与 `ReminderRule` 同族。所以解码那一步**不抛错**：与 `NoteSource.Kind` 的
/// 「认不出就抛」刻意不同 —— 来源认不出是**数据损坏**（要让人知道），
/// 优先级认不出只可能是别端多了一档（当没给才是如实处置）。
public enum TodoPriority: String, Codable, Sendable, CaseIterable {
    case low
    case normal
    case high

    /// 存库 / 进交换面时写出去的那个串。
    public var raw: String { rawValue }

    /// 认不出的取值 ⇒ `.normal`（**当没给**：不抛错、也不偷偷降成别的档）。
    public init(raw: String) {
        self = TodoPriority(rawValue: raw) ?? .normal
    }

    /// 解交换面 / 旧备份时同样按「认不出当没给」走，而不是让 `Codable` 抛。
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(raw: (try? container.decode(String.self)) ?? "")
    }
}

/// 待办任务（`DoyahNotes` 核心契约 `Todo` 实体；需求条文 `FR-NOTE-36~39`，任务 `T95`）。
///
/// **本文件只有「模型」这一件事**：库表 / 行映射在 `NoteStorage/NoteDatabase.swift` 的
/// schema **v5**（`todo` + `todo_tag`），门面在 `NoteLibrary`。
///
/// 三条口径（逐条取自提案 `0004` 的**已采纳裁决**，本侧**不自行发明**）：
///   ① `done` 与 `dueAt` **互不覆盖** —— 完成任务**不清截止时间**，重开时「逾期」仍按原
///      `dueAt` 判（`FR-NOTE-36`）；
///   ② `completedAt` **只**用于已完工分区的展示与排序，**不做**未完工分区的主排序键；
///   ③ 「清单是唯一事实源、日历只是视图」（`FR-NOTE-39`）：**没有第二份数据**，
///      所以这里也没有「日历任务」这类类型 —— 日历那一侧由 `L-100` 直接投影本类型。
///
/// **未落**（如实登记）：排序口径（三档第一关键字 / 无截止排哪一端 / 同键次序 / 逾期的排序影响）
/// 与交换面 `todos[]` 属**契约半**（`DoyahNotes/Docs/核心契约.md`）——
/// 契约落笔前**不自行发明**（提案 `0004` 末尾明写），故本片只落「库表 / 行映射 / 共享模型」。
public struct Todo: Identifiable, Codable, Equatable, Sendable {

    /// 本机自增主键的**稳定形态**：与 `Note` 同口径（`id` 只在本机有意义、不进备份、不做跨端标识；
    /// 跨端稳定身份 `uid` 与笔记那一条同批处理，见 `N-08`）。
    public var id: UUID

    /// 标题。**允许空串**（与 `Note.title` 同口径：捕获优先 —— 先记下来比先想标题重要）。
    public var title: String

    /// 截止时间（**可空 = 无截止**）。完成态切换**不丢**这个原值（裁决 ①）。
    public var dueAt: Date?

    /// 完成态。与 `dueAt` **互不覆盖**。
    public var done: Bool

    /// 完成时刻（`nil` = 没完成过 / 被重开了）。只用于已完工分区的展示与排序（裁决 ②）。
    public var completedAt: Date?

    /// 优先级（认不出的取值「当没给」= `.normal`）。
    public var priority: TodoPriority

    /// 标签（**复用** `TagRules` 的口径；空数组 = 无标签，与 `Note.tags` 同口径）。
    public var tags: [String]

    public var createdAt: Date

    /// 最近更新时间。刷新面 = **内容编辑 / 完成 / 重开 / 改期**；
    /// **组织类操作（排序位 / 置顶 / 移动）不刷新**（裁决 ①③，与笔记侧既有口径同形）。
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        dueAt: Date? = nil,
        done: Bool = false,
        completedAt: Date? = nil,
        priority: TodoPriority = .normal,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.dueAt = dueAt
        self.done = done
        self.completedAt = completedAt
        self.priority = priority
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
