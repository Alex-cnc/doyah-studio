import Foundation

/// 工作区文件操作的**一次撤销**（`FR-STD-WS-FS-005` ③「改名可撤回」/ `FR-STD-WS-FS-006` ③「支持一次撤销」）。
///
/// 四条口径（需求书原话落地，别在实现里松掉）：
///   ① **只留一层** —— 「一次撤销」就是一层：记新的覆盖旧的、撤销完就没了（**没有重做栈**）。
///      用户说的是「我手滑了，收回来」，不是版本控制；栈一深，界面就得再解释一层语义，
///      而这一层语义没有任何需求支撑。
///   ② **撤销删除 = 从废纸篓搬回原处** —— 废纸篓那一份是唯一的真副本；它没了就如实拒绝
///      （`Failure.trashCopyMissing`），**不许**去别处找个同名文件顶上（那是拿猜测冒充撤销）。
///   ③ **撤销新建 = 再移进废纸篓** —— 不 `removeItem`。撤销本身也必须是可恢复的，
///      否则界面上唯一一个不可逆的按钮恰好叫「撤销」。
///   ④ **条目绑工作区** —— 三条路（`rename` / `delete` / `restore`）都走
///      `WorkspaceFileOperations` 的越界检查，所以换过工作区之后拿旧条目去撤，得到的是
///      `notContained`，不会把东西搬进另一个目录。
///
/// 为什么单独一个类型而不是往 `WorkspaceFileOperations` 里加三个方法：那里只管「往前做」，
/// 这里只管「把它退回去」；两边的失败面不一样（撤销多两条：废纸篓副本没了 / 原位置被占了），
/// 混在一起会让「失败」这个词在同一个枚举里承担两套含义。
public enum WorkspaceFileUndo: Equatable, Sendable {

    /// 新建了 `created`（撤销 = 把它移进废纸篓）。
    case creation(created: URL, workspace: URL)
    /// 从 `from` 改名到 `to`（撤销 = 改回去）。
    case rename(from: URL, to: URL, workspace: URL)
    /// 删除了 `original`，系统把它放在 `trashedTo`（撤销 = 搬回来）。
    case deletion(original: URL, trashedTo: URL?, workspace: URL)
    /// 从 `from` 搬到了 `to`（撤销 = 搬回原目录；`FR-STD-WS-FS-003` 的拖拽移动）。
    case move(from: URL, to: URL, workspace: URL)

    /// 界面按这一档选句子（Core 只有结构，句子在语言表里）。
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case creation
        case rename
        case deletion
        case move
    }

    public var kind: Kind {
        switch self {
        case .creation: return .creation
        case .rename: return .rename
        case .deletion: return .deletion
        case .move: return .move
        }
    }

    public var workspaceURL: URL {
        switch self {
        case let .creation(_, workspace): return workspace
        case let .rename(_, _, workspace): return workspace
        case let .deletion(_, _, workspace): return workspace
        case let .move(_, _, workspace): return workspace
        }
    }

    /// 操作前条目在哪（`creation` 为 `nil`：那一刻本来什么都没有）。
    public var originalURL: URL? {
        switch self {
        case .creation: return nil
        case let .rename(from, _, _): return from
        case let .deletion(original, _, _): return original
        case let .move(from, _, _): return from
        }
    }

    /// 操作后条目在哪（撤销就是从这里往回搬）。
    public var currentURL: URL {
        switch self {
        case let .creation(created, _): return created
        case let .rename(_, to, _): return to
        case let .deletion(original, _, _): return original
        case let .move(_, to, _): return to
        }
    }

    /// 删除时废纸篓里的位置。
    public var trashedURL: URL? {
        guard case let .deletion(_, trashedTo, _) = self else { return nil }
        return trashedTo
    }
}

/// 撤销账：**只有一层**（口径 ①）。
///
/// 单独一个结构（而不是在调用方留一个 `var pendingUndo: WorkspaceFileUndo?`）的理由：
/// 「记一条 / 取一条 / 取完就作废」这三件事的语义只写一遍，界面那边就没有第二套理解空间
/// —— 这类「一次撤销」最容易写成「能反复撤」，而重复撤销会把撤销本身变成破坏性操作。
public struct WorkspaceUndoLog: Equatable, Sendable {

    public private(set) var pending: WorkspaceFileUndo?

    public init(pending: WorkspaceFileUndo? = nil) {
        self.pending = pending
    }

    public var canUndo: Bool { pending != nil }

    /// 记一条：**覆盖**上一条（「一次撤销」= 只认最近那一次）。
    /// 传 `nil` = 这次操作没什么可撤（例如「点开改名又原样提交」）—— 顺手把旧条目也清掉，
    /// 否则界面上的「撤销」会去撤一件更早的事，而用户以为它撤的是刚才那一下。
    public mutating func record(_ undo: WorkspaceFileUndo?) {
        pending = undo
    }

    /// 取出即作废：撤销只有一次，撤完没有重做。
    public mutating func consume() -> WorkspaceFileUndo? {
        defer { pending = nil }
        return pending
    }

    public mutating func clear() {
        pending = nil
    }

    /// 真把条目搬回去。返回**撤销之后条目在哪**：
    /// 撤销「新建」时那份东西进的废纸篓（返回废纸篓里那个位置，`nil` = 系统没告诉我们）；
    /// 撤销「改名」「删除」时是条目回到的位置。
    ///
    /// 失败一律抛 `WorkspaceFileOperations.Failure`（与正向操作同一套失败面）：
    /// 废纸篓副本没了 = `trashCopyMissing`、原位置被占 = `alreadyExists`、
    /// 换过工作区 = `notContained`。
    @discardableResult
    public static func revert(_ undo: WorkspaceFileUndo) throws -> URL? {
        switch undo {
        case let .creation(created, workspace):
            return try WorkspaceFileOperations.delete(created, in: workspace)
        case let .rename(from, to, workspace):
            return try WorkspaceFileOperations.rename(to, to: from.lastPathComponent, in: workspace)
        case let .deletion(original, trashedTo, workspace):
            guard let trashedTo else { throw WorkspaceFileOperations.Failure.trashCopyMissing(original.lastPathComponent) }
            return try WorkspaceFileOperations.restore(trashedTo, to: original, in: workspace)
        case let .move(from, to, workspace):
            // 搬回原目录：原目录可能已经不在了（被同时删掉 / 改名）⇒ 走 `move` 的同一套失败面如实报。
            return try WorkspaceFileOperations.move(to, into: from.deletingLastPathComponent(), in: workspace)
        }
    }
}
