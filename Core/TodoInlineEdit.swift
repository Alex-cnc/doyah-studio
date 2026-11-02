import Foundation

// MARK: - 五列（`FR-NTS-TODO-LIST-002` 判据①：五列都显示且可改）

/// 清单行上的五列 —— **标题 / 截止时间 / 完成态 / 优先级 / 标签**。
///
/// 为什么做成一个能一次列出五列的东西、而不是五个散落的布尔：
/// 判据①要的是「五列都在、都能改」。散着写就没有任何一处能回答「现在有几列、
/// 哪一列不见了」—— 删掉标签那一列也不会有读数变红。`columns` 就是那个唯一的清单。
/// 顺序也是口径（与行上从左到右一致）。
public enum TodoInlineField: String, CaseIterable, Sendable, Equatable {
    case title
    case dueAt
    case done
    case priority
    case tags

    /// 行上的显示顺序（判据读它；改顺序要同批改探针）。
    public static let columns: [TodoInlineField] = [.title, .dueAt, .done, .priority, .tags]
}

// MARK: - 五列各自「只改它那一格」
/// 五列的就地改：**每一格一个函数，改一格不碰别格**（`LIST-001` 的重复规则 / 备注
/// 不在五列里 ⇒ 就地改永远碰不到它们，这是「改标题不会顺手把重复规则清掉」的形状保证）。
///
/// 写路仍只有一条：函数只**变换值**，落库还是调用方那一次 `NoteDatabase.upsert`
/// （同一次写入、同一行 —— `LIST-002` 判据①与 `STATE-002`「只有一份数据」同一条纪律）。
public enum TodoInlineEdit {

    public static func settingTitle(_ raw: String, on todo: Todo, now: Date = Date()) -> Todo {
        var value = todo
        value.title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        value.updatedAt = now
        return value
    }

    /// 截止时间：`nil` = **显式清掉**（「无截止」是一个值，不是「没填」）。
    public static func settingDueAt(_ dueAt: Date?, on todo: Todo, now: Date = Date()) -> Todo {
        var value = todo
        value.dueAt = dueAt
        value.updatedAt = now
        return value
    }

    /// 完成态：完成即补 `completedAt`、重开即清 —— 与 `setDone` 那条写路同一口径
    /// （`FR-NOTE-36`：切完成态**不动**截止时间）。
    public static func settingDone(_ done: Bool, on todo: Todo, at moment: Date = Date()) -> Todo {
        var value = todo
        value.done = done
        value.completedAt = done ? (todo.completedAt ?? moment) : nil
        value.updatedAt = moment
        return value
    }

    public static func settingPriority(
        _ priority: TodoPriority, on todo: Todo, now: Date = Date()
    ) -> Todo {
        var value = todo
        value.priority = priority
        value.updatedAt = now
        return value
    }

    public static func settingTags(_ raw: String, on todo: Todo, now: Date = Date()) -> Todo {
        var value = todo
        value.tags = tags(from: raw)
        value.updatedAt = now
        return value
    }

    /// 标签的切分口径（与编辑面同一套）：空格 / 半角逗号 / 全角逗号切，去空、去重（保序）。
    /// **只在 Core 一处**：两处各切一遍就会出现「行上写 a b、编辑面存成 a,b」两种结果。
    ///
    /// 顺序说明（如实）：这里保序只在本进程内成立 —— 存储层回读标签走 `ORDER BY tag ASC`
    /// （`todo_tag`，与笔记 `note_tag` 同一口径），所以从库里读回来的那一份是字母序。
    /// 判据按**集合**比，不按顺序比（顺序不是本需求给的语义）。
    public static func tags(from raw: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for piece in raw.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "，" }) {
            let tag = String(piece)
            guard !tag.isEmpty, seen.insert(tag).inserted else { continue }
            result.append(tag)
        }
        return result
    }
}

// MARK: - 五列的显示（句子只在语言表里；空值也有话说）

/// 五列各自的**显示文本**：`nil` 不许出现 —— 空截止、空标签**也有话说**
/// （「无截止」「无标签」），否则那一列在行上就凭空消失了，读的人会以为没有这一列。
///
/// 为什么成形落 Core 而不在视图里拼：与 `TodoRepeatPresentation` 同一条理由 ——
/// 分带词、优先级名字、完成态名字都要跟语言走，视图各拼一遍就会出现两种说法。
public enum TodoInlinePresentation {

    /// 某一列在行上的那一句。**五列都回非空字符串**（判据①的读数就是这一条）。
    public static func text(
        _ field: TodoInlineField,
        of todo: Todo,
        window: TodoWindow,
        language: AppLanguage
    ) -> String {
        switch field {
        case .title:
            return TodoPresentation.title(todo)
                ?? LocalizedStrings.text(.notesUntitled, language: language)
        case .dueAt:
            return LocalizedStrings.text(TodoQuery.band(of: todo, window: window).key, language: language)
        case .done:
            let key: LKey = todo.done ? .todoSectionCompleted : .todoSectionOpen
            return LocalizedStrings.text(key, language: language)
        case .priority:
            return LocalizedStrings.text(todo.priority.key, language: language)
        case .tags:
            guard !todo.tags.isEmpty else {
                return LocalizedStrings.text(.todoTagsNone, language: language)
            }
            let separator = LocalizedStrings.text(.reminderListSeparator, language: language)
            return todo.tags.joined(separator: separator)
        }
    }

    /// 五列一次列齐（顺序 = `TodoInlineField.columns`）—— 探针与视图共用这一份。
    public static func allTexts(
        of todo: Todo, window: TodoWindow, language: AppLanguage
    ) -> [String] {
        TodoInlineField.columns.map { text($0, of: todo, window: window, language: language) }
    }
}

// MARK: - 删除可撤销（判据③）

/// 删掉的那一条的**完整快照**（删前抓、撤销时原样写回）。
///
/// 为什么不是「回收站」：需求给的出口是「删除可撤销」（一次、当场的那个动作），
/// 不是「笔记那种墓碑 + 回收站」—— 待办侧没有墓碑列，硬加一列会把「删了」变成
/// 「看起来删了」，那属于另一条需求。这里只保证：**撤销回来的那一行与删之前逐字段相等**，
/// 同 id ⇒ 不与任何别的行冲突，也不产生第二条。
public struct TodoRemovalUndo: Equatable, Sendable {

    public let todo: Todo
    public let removedAt: Date

    public init(todo: Todo, removedAt: Date = Date()) {
        self.todo = todo
        self.removedAt = removedAt
    }

    /// 还原用的那一份：**同 id、同全部字段**，只把 `updatedAt` 推到还原时刻
    /// （否则同步侧会把它当更旧的版本丢掉）。
    public func restored(now: Date = Date()) -> Todo {
        var value = todo
        value.updatedAt = now
        return value
    }
}
