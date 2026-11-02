import Foundation

/// 任务 ↔ 笔记**双向转化**（`FR-NTS-TODO-LINK-001` · 概设 §15.14）。
///
/// 五条口径（逐条对应概设 §15.14 的不变量行；**本文件是它们唯一的实现处**，
/// 界面与 `AppState` 只调这里，不自己拼「来自 / 已生成」或自己判「来源还在不在」）：
///
///  ① **转化是新建，不是改类型** —— `TodoLinkFactory` 只**造**新对象：原笔记的类型、正文、
///     时间一个字节都不碰（它读进来只是取标题 / 摘要做副本来源）；原任务同理。
///  ② **双向可见可跳转** —— 链接里两个 `id` 都在；`TodoLinkViewer` 决定这一侧读到的是
///     「来自笔记」还是「已生成任务」（两端详情读同一份链接、说各自那半句话）。
///  ③ **链接带快照** —— `snapshotTitle` / `snapshotExcerpt` **只在建立时写一次**；对方后来被改，
///     这一份不跟着变（这就是「追不出改的是谁」那条症状的解药：链接是当时的读数，不是活引用）。
///  ④ **可撤销** —— `undoTarget(of:)` 回答「撤销要删哪一个」：删的是**那条链接产出的新对象**，
///     方向由 `origin` 定，不由调用方猜。
///  ⑤ **来源被删要标注** —— 引用是否还在由 `TodoLinkReading.counterpartMissing` 回答；
///     链接行**不随对象级联删**（库里没有外键），于是被删之后仍留得下快照。
///
/// 为什么方向要当类型（`TodoLinkOrigin`）而不是两个可空 id：两个可空 id 允许出现
/// 「两头都空」或「两头都填」的坏行，而这两种行在界面上都表现为「点了没反应」——
/// 建档时就分成两个方向，坏行在库里写不进去（`CHECK` 之外的第二道：写入函数只此一处）。

/// 转化成是**从哪一边发起**的（决定措辞与撤销目标）。
public enum TodoLinkOrigin: String, Codable, Sendable, CaseIterable, Equatable {

    /// 笔记 ⇒ 任务（新对象是任务）。
    case fromNote
    /// 任务 ⇒ 笔记（新对象是笔记）。
    case fromTodo

    /// 存库 / 进交换面时写出去的那个串。
    public var raw: String { rawValue }

    /// 认不出的取值 ⇒ `nil`（**不猜方向**：猜错就是撤销时删掉另一个对象）。
    public init?(raw: String) {
        self.init(rawValue: raw)
    }

    /// 解码同样不猜：认不出就抛错（与 `NoteSource.Kind` 同族；此处丢不得，因为撤销靠它）。
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        guard let value = TodoLinkOrigin(raw: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "unknown todo link origin: \(raw)"
            )
        }
        self = value
    }
}

/// 一条链接（概设 §15.14「链接带快照」）。
///
/// **没有外键、没有级联**：`note` 与 `todo` 随便哪一边被删，这一行都留着 ——
/// 这正是判据④「来源被删时保留快照并标注」能成立的前提。
public struct TodoNoteLink: Identifiable, Codable, Equatable, Sendable {

    public var id: UUID
    public var noteID: UUID
    public var todoID: UUID
    /// 从哪一边生成的（决定「来自 / 已生成」与撤销目标）。
    public var origin: TodoLinkOrigin
    /// 建立时的对方标题（**快照**，不随对方更新）。
    public var snapshotTitle: String
    /// 建立时的对方摘要（**快照**，纯文本，长度由 `TodoLinkText.excerpt` 截）。
    public var snapshotExcerpt: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        noteID: UUID,
        todoID: UUID,
        origin: TodoLinkOrigin,
        snapshotTitle: String,
        snapshotExcerpt: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.noteID = noteID
        self.todoID = todoID
        self.origin = origin
        self.snapshotTitle = snapshotTitle
        self.snapshotExcerpt = snapshotExcerpt
        self.createdAt = createdAt
    }

    /// 这条链接**产出的**那个对象（撤销要删的）。
    public var generatedID: UUID { origin == .fromNote ? todoID : noteID }

    /// 这条链接**的源头**那个对象（被删要标注的那一个）。
    public var sourceID: UUID { origin == .fromNote ? noteID : todoID }

    /// 解码：快照摘要是后加的字段（旧状态文件 / 旧备份里没有这一格）⇒ 缺字段按空串，
    /// 不让它变成「旧数据解不出来」的理由（与 `Todo.note` 同一条口径）。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        noteID = try container.decode(UUID.self, forKey: .noteID)
        todoID = try container.decode(UUID.self, forKey: .todoID)
        origin = try container.decode(TodoLinkOrigin.self, forKey: .origin)
        snapshotTitle = try container.decodeIfPresent(String.self, forKey: .snapshotTitle) ?? ""
        snapshotExcerpt = try container.decodeIfPresent(String.self, forKey: .snapshotExcerpt) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, noteID, todoID, origin, snapshotTitle, snapshotExcerpt, createdAt
    }
}

/// 站在哪一侧看这条链接（「来自 / 已生成」的措辞由此决定，界面不做第二个 `switch`）。
public enum TodoLinkViewer: Sendable, Equatable {
    case note
    case todo

    /// 这一侧看到的对方是哪一类（跳转去哪个面）。
    public var counterpart: TodoLinkViewer {
        self == .note ? .todo : .note
    }
}

/// 撤销要删的**是哪一个对象**（判据③「生成后可撤销」的机械形状）。
public enum TodoLinkUndoTarget: Equatable, Sendable {
    case note(UUID)
    case todo(UUID)

    public var id: UUID {
        switch self {
        case .note(let id): return id
        case .todo(let id): return id
        }
    }
}

/// 详情里那一行的读数（**唯一生产点**：界面照它画，不自己判「来源还在不在」）。
public struct TodoLinkReading: Equatable, Sendable {

    /// 这一行说的是哪条链接（撤销按钮带上它，避免删错一条）。
    public let linkID: UUID
    /// 对方的标题：**有链接快照就用快照**（判据③：对方被改不跟着变）。
    public let counterpartTitle: String
    /// 对方的摘要（同上，快照）。
    public let counterpartExcerpt: String
    /// 对方**现在还在不在**（不在 ⇒ 判据④「来源已删除」，链接与快照仍留着）。
    public let counterpartMissing: Bool
    /// 「来自笔记 / 已生成笔记 / 来自任务 / 已生成任务」那一句的键。
    public let originKey: LKey
    /// 这一侧看到的对方是哪一面（跳转用）。
    public let counterpart: TodoLinkViewer
    /// 对方的 id（**跳转的目标**；对方已被删时这个 id 指不到任何东西，由 `counterpartMissing` 说明）。
    public let counterpartID: UUID

    public init(
        linkID: UUID,
        counterpartTitle: String,
        counterpartExcerpt: String,
        counterpartMissing: Bool,
        originKey: LKey,
        counterpart: TodoLinkViewer,
        counterpartID: UUID
    ) {
        self.linkID = linkID
        self.counterpartTitle = counterpartTitle
        self.counterpartExcerpt = counterpartExcerpt
        self.counterpartMissing = counterpartMissing
        self.originKey = originKey
        self.counterpart = counterpart
        self.counterpartID = counterpartID
    }
}

/// 语言键与文本小工具（Core 里一个汉字都没有 —— `R-45` 棘轮）。
public enum TodoLinkText {

    /// 这一侧该说「来自…」还是「已生成…」：**由方向与视角两样共同决定**。
    ///
    /// 四种组合都必需（少一种就得由界面兜底，而那正是「同一件事两处措辞」的起点）：
    /// 站在笔记上看一条 `fromNote` 链接 = 「已生成任务」；站在任务上看同一条 = 「来自笔记」。
    public static func originKey(for viewer: TodoLinkViewer, origin: TodoLinkOrigin) -> LKey {
        switch (viewer, origin) {
        case (.note, .fromNote): return .todoLinkGeneratedTodo
        case (.note, .fromTodo): return .todoLinkFromTodo
        case (.todo, .fromNote): return .todoLinkFromNote
        case (.todo, .fromTodo): return .todoLinkGeneratedNote
        }
    }

    /// 摘要：换行压成空格（快照是**一行读数**，不是正文副本）、首尾空白去掉、按字符截到 `limit`。
    public static func excerpt(_ body: String, limit: Int = 120) -> String {
        let flattened = body
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > limit else { return flattened }
        return String(flattened.prefix(limit))
    }

    /// 标题：空白 ⇒ 调用方给的兜底句（**不在这里写汉字**）。
    public static func title(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

/// 转化本身：**只造新对象**（判据①「原对象不被改写」在形状上成立 —— 这里拿不到原对象的可变引用）。
public enum TodoLinkFactory {

    /// 笔记 ⇒ 任务：标题取笔记标题（空则用调用方给的兜底句），备注放正文摘要，标签照搬。
    /// **不搬**：`dueAt` / `done` / 提醒（笔记上没有这些语义，凭空造一个截止就是编数据）。
    public static func todo(
        from note: Note,
        fallbackTitle: String,
        at moment: Date = Date()
    ) -> Todo {
        Todo(
            title: TodoLinkText.title(note.title, fallback: fallbackTitle),
            tags: note.tags,
            note: TodoLinkText.excerpt(note.body),
            createdAt: moment,
            updatedAt: moment
        )
    }

    /// 任务 ⇒ 笔记：标题取任务标题（空则兜底），正文 = 备注正文（原样，不加工成 Markdown）。
    /// 来源标 `.manual`（这一条是人按出来的，不是 AI 产物 / 捕获 / 冲突副本 —— 四类都不是它）。
    public static func note(
        from todo: Todo,
        fallbackTitle: String,
        at moment: Date = Date()
    ) -> Note {
        Note(
            title: TodoLinkText.title(todo.title, fallback: fallbackTitle),
            body: todo.note,
            tags: todo.tags,
            source: NoteSource(kind: .manual, capturedAt: moment),
            createdAt: moment,
            updatedAt: moment
        )
    }

    /// 建立链接：快照取**被转换方**（`origin == .fromNote` 时快照 = 笔记的标题与摘要）。
    public static func link(
        note: Note,
        todo: Todo,
        origin: TodoLinkOrigin,
        at moment: Date = Date()
    ) -> TodoNoteLink {
        let title: String
        let excerpt: String
        switch origin {
        case .fromNote:
            title = note.title
            excerpt = TodoLinkText.excerpt(note.body)
        case .fromTodo:
            title = todo.title
            excerpt = TodoLinkText.excerpt(todo.note)
        }
        return TodoNoteLink(
            noteID: note.id,
            todoID: todo.id,
            origin: origin,
            snapshotTitle: title,
            snapshotExcerpt: excerpt,
            createdAt: moment
        )
    }

    /// 撤销要删的对象 = **这条链接产出的那一个**（源头不动）。
    public static func undoTarget(of link: TodoNoteLink) -> TodoLinkUndoTarget {
        switch link.origin {
        case .fromNote: return .todo(link.todoID)
        case .fromTodo: return .note(link.noteID)
        }
    }

    /// 详情读数（**唯一入口**）：`counterpartExists` 由调用方按当前库 / 列表现算，
    /// 本函数只决定「说哪一句话 + 快照显示什么」。
    public static func reading(
        of link: TodoNoteLink,
        viewer: TodoLinkViewer,
        counterpartExists: Bool
    ) -> TodoLinkReading {
        TodoLinkReading(
            linkID: link.id,
            counterpartTitle: link.snapshotTitle,
            counterpartExcerpt: link.snapshotExcerpt,
            counterpartMissing: !counterpartExists,
            originKey: TodoLinkText.originKey(for: viewer, origin: link.origin),
            counterpart: viewer.counterpart,
            counterpartID: viewer == .note ? link.todoID : link.noteID
        )
    }
}
