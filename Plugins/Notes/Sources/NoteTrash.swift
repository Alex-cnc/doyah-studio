import Foundation

// **回收站**（`FR-NTS-NOTE-TRASH-001`）与**归档**（`FR-NTS-NOTE-ORG-001` ③）的判定层。
//
// 为什么这一层单独成文件（而不是散进 `NoteLibrary` / 视图）：
//   · 契约 §15.9 的四条不变量（可恢复 / 清除前有提示 / 上限可见 / 恢复回原位）都是**纯判定**，
//     与 SQLite 和 SwiftUI 无关 ⇒ 它们能被单测钉住，而不是靠「点一下看看」；
//   · 上限那一条最容易写成「文档里有、界面里没有」：`NoteTrashSummary` 把「还剩几天 / 用了几格 /
//     哪几条马上要被清掉」算成读数，界面只负责把它说出来（`L(...)` 组句），不自己算；
//   · 归档与回收站是**两件事**（契约 §15.5 第 4 条：归档不占回收站、不受到期清除影响）⇒
//     归档位在 `Note.isArchived`，回收站在这张快照表里，两者不共用一个「隐藏」字段。
//
// 一条纪律：**Core 不读时钟、不组句子**。`now` 与策略都由调用方给；界面文字只从语言表来。

/// 回收站的两条上限（契约 §15.9「保留期与容量上限可查」）。
///
/// 默认 30 天 / 100 条：够「删错了过两天想起来」这一档，又不至于让回收站变成一个
/// 永不清理的第二份库（那与「彻底清除」这件事自相矛盾）。
public struct NoteTrashPolicy: Equatable, Sendable {

    /// 保留天数（≥ 1）。到期 ⇒ 进清除候选。
    public var retentionDays: Int
    /// 容量（条数，≥ 1）。超出 ⇒ **最旧的**那几条进清除候选。
    public var capacity: Int

    public init(retentionDays: Int = 30, capacity: Int = 100) {
        self.retentionDays = max(1, retentionDays)
        self.capacity = max(1, capacity)
    }

    public static let `default` = NoteTrashPolicy()

    /// 「接近上限」的门槛 = 容量的 80%（四舍五入向上，至少 1）。
    /// 为什么不留到 100% 才提示：到期清除是自动的，等满了再提示就等于「提示与清除同一刻」。
    public var nearLimitThreshold: Int { max(1, (capacity * 4 + 4) / 5) }

    /// 保留期对应的秒数。
    public var retentionSeconds: TimeInterval { TimeInterval(retentionDays) * 86_400 }
}

/// 回收站快照里的一条附件（**只存引用**：附件二进制本来就在文件系统，库里只存路径 —— `FR-PLUG-08`）。
public struct NoteTrashAttachment: Codable, Equatable, Sendable {
    public var id: UUID
    public var path: String
    public var byteCount: Int64?
    public var addedAt: Date

    public init(id: UUID, path: String, byteCount: Int64? = nil, addedAt: Date) {
        self.id = id
        self.path = path
        self.byteCount = byteCount
        self.addedAt = addedAt
    }
}

/// 回收站里的一条：**恢复所需的全部东西**（标题 + 原归属 + 标签 + 附件引用 + 删除时刻）。
///
/// `title` 是删除那一刻的标题 —— 彻底清除会把 `note` 行的标题清掉，而「清除后能说出清了哪些」
/// 需要它（收据上不能只剩一个 uuid）。
public struct NoteTrashEntry: Codable, Equatable, Sendable {
    public var noteID: UUID
    public var title: String
    public var notebookUid: String?
    public var tags: [String]
    public var attachments: [NoteTrashAttachment]
    public var deletedAt: Date
    /// 非空 = 内容已彻底清除（这条只剩收据，不能再恢复）。
    public var purgedAt: Date?

    public init(
        noteID: UUID,
        title: String,
        notebookUid: String? = nil,
        tags: [String] = [],
        attachments: [NoteTrashAttachment] = [],
        deletedAt: Date,
        purgedAt: Date? = nil
    ) {
        self.noteID = noteID
        self.title = title
        self.notebookUid = notebookUid
        self.tags = tags
        self.attachments = attachments
        self.deletedAt = deletedAt
        self.purgedAt = purgedAt
    }

    /// 还能恢复吗（已清除的只剩收据）。
    public var isRecoverable: Bool { purgedAt == nil }

    /// 还剩几天到期（向下取整；已到期 = 0）。已清除的没有意义 ⇒ `nil`。
    public func daysLeft(policy: NoteTrashPolicy, now: Date) -> Int? {
        guard isRecoverable else { return nil }
        let elapsed = now.timeIntervalSince(deletedAt)
        let remaining = policy.retentionSeconds - elapsed
        if remaining <= 0 { return 0 }
        return Int(remaining / 86_400)
    }

    /// 到期了没有（`>=` 保留期即到期 —— 与 `daysLeft == 0` 同一处判，不留第二种算法）。
    public func isExpired(policy: NoteTrashPolicy, now: Date) -> Bool {
        isRecoverable && now.timeIntervalSince(deletedAt) >= policy.retentionSeconds
    }
}

/// 回收站的一整屏读数（**界面只说这份读数，不自己算**）。
public struct NoteTrashSummary: Equatable, Sendable {

    /// 还能恢复的那些（最近删的在前）。
    public var items: [NoteTrashEntry]
    /// 已彻底清除的收据（同一份表里 `purged_at` 非空的行）。
    public var purged: [NoteTrashEntry]
    public var policy: NoteTrashPolicy
    /// 到期该清的（按删除时间正序 —— 先删的先清）。
    public var expiredIDs: [UUID]
    /// 超出容量该清的（同样按删除时间正序）。
    public var overflowIDs: [UUID]

    /// 自己占几格（只数还能恢复的那些 —— 收据不占容量，否则「清干净了格子还是满的」）。
    public var count: Int { items.count }

    /// 用完的比例（0…1；容量至少 1，不会除零）。
    public var fillRatio: Double {
        min(1, Double(count) / Double(policy.capacity))
    }

    /// 接近上限了没有（契约 §15.9「接近上限时提示」）。
    public var nearLimit: Bool { count >= policy.nearLimitThreshold }

    /// 下一次自动清除会清掉几条（= 到期 + 超容量的并集）。
    public var purgeQueueIDs: [UUID] {
        var seen = Set<UUID>()
        var ordered: [UUID] = []
        for id in expiredIDs + overflowIDs where seen.insert(id).inserted { ordered.append(id) }
        return ordered
    }

    /// 自动清除会不会动到东西（界面据此决定要不要在打开回收站时提醒一次）。
    public var willPurgeOnOpen: Bool { !purgeQueueIDs.isEmpty }

    /// 还能恢复的那几条里，挂着附件的有几条（彻底清除前那句提示要用）。
    public var recoverableAttachmentCount: Int {
        items.reduce(0) { $0 + $1.attachments.count }
    }

    /// 按删除时间排的完整清单（最近删的在前）。
    public static func make(
        entries: [NoteTrashEntry],
        policy: NoteTrashPolicy = .default,
        now: Date
    ) -> NoteTrashSummary {
        let sorted = entries.sorted {
            if $0.deletedAt != $1.deletedAt { return $0.deletedAt > $1.deletedAt }
            return $0.noteID.uuidString > $1.noteID.uuidString
        }
        let recoverable = sorted.filter { $0.isRecoverable }
        let purged = sorted.filter { !$0.isRecoverable }

        // 到期：按删除时间**正序**（先删的先清）。
        let expired = recoverable
            .filter { $0.isExpired(policy: policy, now: now) }
            .sorted { $0.deletedAt < $1.deletedAt }
            .map(\.noteID)

        // 超容量：留下**最近删的** `capacity` 条，其余（更旧的）进清除候选。
        let alive = recoverable.filter { !$0.isExpired(policy: policy, now: now) }
        let kept = alive.prefix(policy.capacity)
        let overflow = alive.dropFirst(kept.count).sorted { $0.deletedAt < $1.deletedAt }.map(\.noteID)

        return NoteTrashSummary(
            items: recoverable,
            purged: purged,
            policy: policy,
            expiredIDs: expired,
            overflowIDs: overflow
        )
    }

    /// 上限那一行要说的事实（结构化，组句在界面）：用了几格 / 一共几格 / 还留几天。
    public struct Limits: Equatable, Sendable {
        public var used: Int
        public var capacity: Int
        public var retentionDays: Int
        public var nextPurgeCount: Int
        public var nearLimit: Bool
    }

    public var limits: Limits {
        Limits(
            used: count,
            capacity: policy.capacity,
            retentionDays: policy.retentionDays,
            nextPurgeCount: purgeQueueIDs.count,
            nearLimit: nearLimit
        )
    }
}

/// 恢复的落点（契约 §15.9「恢复回原位；原归属已不存在时落默认归属并说明」）。
public enum NoteRestorePlacement: Equatable, Sendable {
    /// 原归属还在 ⇒ 回原处。
    case original(uid: String)
    /// 原归属没了（或本来就没有）⇒ 落默认笔记本，**并且要说出来**。
    case fallbackToDefault(original: String?)
}

/// 恢复的结果（**落点要如实说**：原归属没了就不是「回原位」，界面得把这句话说出来）。
public struct NoteRestoreOutcome: Equatable, Sendable {
    public var noteID: UUID
    public var placement: NoteRestorePlacement

    public init(noteID: UUID, placement: NoteRestorePlacement) {
        self.noteID = noteID
        self.placement = placement
    }

    /// 是不是「没回原位」（界面据此决定要不要多一句说明）。
    public var movedToDefault: Bool {
        if case .fallbackToDefault = placement { return true }
        return false
    }
}

/// 恢复 / 清除 / 归档的纯判定。
public enum NoteTrash {

    /// 恢复落点：`existingNotebookUids` 由调用方从库里的目录给（Core 不去查库）。
    public static func placement(
        originalNotebookUid: String?,
        existingNotebookUids: Set<String>,
        defaultNotebookUid: String?
    ) -> NoteRestorePlacement {
        if let uid = originalNotebookUid, existingNotebookUids.contains(uid) {
            return .original(uid: uid)
        }
        return .fallbackToDefault(original: originalNotebookUid)
    }

    /// 一条能不能恢复（已清除 / 不在表里 ⇒ 不能，调用方要如实说）。
    public static func canRestore(_ entry: NoteTrashEntry?) -> Bool {
        entry?.isRecoverable == true
    }

    /// 彻底清除前那句提示要带的读数（契约 §15.9「含不可恢复与附件一并处理」）。
    public struct PurgePrompt: Equatable, Sendable {
        public var noteCount: Int
        public var attachmentCount: Int
        public var irreversible: Bool
    }

    public static func purgePrompt(
        entries: [NoteTrashEntry],
        attachmentCount: Int? = nil
    ) -> PurgePrompt {
        PurgePrompt(
            noteCount: entries.count,
            attachmentCount: attachmentCount ?? entries.reduce(0) { $0 + $1.attachments.count },
            irreversible: true
        )
    }

    /// **自动清除候选**（保留期到 / 超容量）—— 与「人按的彻底清除」是两条路（契约 §15.9）。
    public static func purgeCandidates(_ summary: NoteTrashSummary) -> [UUID] {
        summary.purgeQueueIDs
    }
}

/// **一次整理动作的撤销快照**（`FR-NTS-NOTE-ORG-001` ②「操作可撤销」· 契约 §15.5「一步可撤销」）。
///
/// 为什么用「快照 + 类型」而不是一条 `undo()` 闭包：闭包抓不到「库里当时到底改了什么」，
/// 撤销就成了「再执行一次反向操作」—— 反向操作在笔记被别的端改过之后会写出第三种状态。
/// 这里只记**受影响的是哪几条、动的是哪一档**，撤销由 `NoteLibrary` 按当前库状态重算
/// （删除档走回收站恢复，归档 / 收藏 / 置顶 / 移动档走反向那一列）。
public struct NoteOrganizeUndo: Equatable, Sendable {

    public enum Kind: String, Equatable, Sendable {
        /// 批量删除（笔记进回收站 ⇒ 撤销 = 从回收站恢复）。
        case delete
        /// 批量归档（撤销 = 取消归档）。
        case archive
        /// 批量取消归档（撤销 = 重新归档）。
        case unarchive
        /// 跨笔记本移动（撤销 = 移回原笔记本）。
        case move
        /// 收集 / 取消收藏。
        case favorite
        /// 置顶 / 取消置顶。
        case pinned
    }

    public var kind: Kind
    public var noteIDs: [UUID]
    /// 移动档要记住「从哪来」（同一次批量移动的目标是同一个笔记本）。
    public var fromNotebookUid: String?
    public var toNotebookUid: String?
    /// 删除档若连带删了一个笔记本，撤销时要把这个笔记本一起建回来。
    public var removedNotebook: NotebookUndoSnapshot?

    public init(
        kind: Kind,
        noteIDs: [UUID],
        fromNotebookUid: String? = nil,
        toNotebookUid: String? = nil,
        removedNotebook: NotebookUndoSnapshot? = nil
    ) {
        self.kind = kind
        self.noteIDs = noteIDs
        self.fromNotebookUid = fromNotebookUid
        self.toNotebookUid = toNotebookUid
        self.removedNotebook = removedNotebook
    }

    public var isEmpty: Bool { noteIDs.isEmpty && removedNotebook == nil }
}

/// 撤销「删了一个笔记本」时要建回来的那几样（uid 保留 —— 恢复的笔记按原 uid 回原归属）。
public struct NotebookUndoSnapshot: Equatable, Sendable {
    public var uid: String
    public var name: String
    public var shelfUid: String
    public var sortOrder: Int

    public init(uid: String, name: String, shelfUid: String, sortOrder: Int) {
        self.uid = uid
        self.name = name
        self.shelfUid = shelfUid
        self.sortOrder = sortOrder
    }
}
