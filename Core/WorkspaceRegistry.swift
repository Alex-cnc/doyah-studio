import Foundation

/// 工作区的**可用性**（`FR-STD-WS-FS-010`）：把 `DirectoryAccessStatus` 折成一档机器口径。
///
/// Core 不带人话：界面按这一档选句子（语言表里一格一条），这样「不可用」在菜单里、
/// 在首页、在提示条上是同一句说法，而不是三处各写一句。
public enum WorkspaceAvailability: String, Equatable, Sendable, CaseIterable {
    /// 能用。
    case available
    /// 从来没有书签（没授权过）。
    case notAuthorized
    /// 目录不在了（被删除 / 被移动 / 卷没挂载）。
    case missing
    /// 目录在但没有读权限。
    case denied
    /// 书签解析不出来（换机器 / 书签损坏）。
    case unresolved

    public var isUsable: Bool { self == .available }

    public init(_ status: DirectoryAccessStatus) {
        switch status {
        case .granted: self = .available
        case .notAuthorized: self = .notAuthorized
        case .missing: self = .missing
        case .denied: self = .denied
        case .resolutionFailed: self = .unresolved
        }
    }
}

/// 界面上那一条「已知工作区」。
public struct KnownWorkspace: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var displayName: String
    /// 最近一次解析出的路径（**只用于展示与去重**，不作为访问依据 —— 访问永远走书签）。
    public var path: String?
    public var availability: WorkspaceAvailability
    public var isActive: Bool

    public init(
        id: UUID,
        displayName: String,
        path: String?,
        availability: WorkspaceAvailability,
        isActive: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.availability = availability
        self.isActive = isActive
    }

    public var isUsable: Bool { availability.isUsable }
}

/// 切换裁决（`FR-STD-WS-FS-010`：可在多个已知工作区之间切换）。
///
/// 三档就是三条口径：
///   * `.switchTo` —— 可以切；
///   * `.alreadyActive` —— 已经是它了：**什么都不做**（重取一次授权 = 树整棵塌一次、展开状态清零，
///     用户看到的是「点了当前这一条，界面闪了一下」，而他要的是没反应）；
///   * `.refuse` —— 拒绝，理由分两档：那条不在表里（界面传错了 id），或那条**现在不可用**
///     （目录不在了 / 没权限 / 书签坏了）。**不可用的那条不许切过去** ——
///     否则界面会切到一个画不出内容的空工作区，还把用户原来那个停掉了。
public enum WorkspaceSwitchDecision: Equatable, Sendable {
    case switchTo(UUID)
    case alreadyActive
    case refuse(Refusal)

    public enum Refusal: Equatable, Sendable {
        case unknownWorkspace
        case unavailable(WorkspaceAvailability)
    }
}

/// 已知工作区表 + 当前活动的那一条（`FR-STD-WS-FS-010`）。
///
/// 需求原话是「可在多个已知工作区之间切换，**同一时刻只有一个活动工作区（不做并发多根）**」——
/// 这句话拆成四条可直接判的口径，都收在这一个类型里：
///   ① **只有一个活动** —— 表里 `activeID` 只有一格，`candidates` 里 `isActive` 至多一条为真；
///   ② **同一目录只登记一条** —— 用户把同一个文件夹选两次，列表里不该长出两条同名的行
///      （点哪一条都到同一个目录，用户只能靠自己记路径分辨）；去重按 `path`，活动那条优先留下：
///      否则「重新选一次当前目录」会把活动状态随去重一起丢掉，重启后界面回到「没打开工作区」；
///   ③ **容量有上限、但永不淘汰活动那条** —— 表尾是最久未用的，到上限就淘汰它；
///      活动那条即使排在最尾也不淘汰（宁可暂时多留一格，也不能把用户正在用的工作区踢出列表）；
///   ④ **不可用 ≠ 不可见** —— 目录被删 / 没权限的工作区仍然留在表里（用户要能看见「它还在，只是现在用不了」
///      并据此重新选一次），但它**不参与切换**（见 `decision(for:)`）。
///
/// 为什么是纯结构而不是直接改 `WorkspaceStore`：这张表的三条错法（重复行 / 活动丢失 / 活动被淘汰）
/// 都是「跑起来才发现」的，而它们全在纯逻辑里 —— 放 Core 才能逐条判红。
public struct WorkspaceRegistry: Equatable, Sendable {

    /// 一条登记项。与 `KnownWorkspace` 的差别：**不带 `isActive`** ——
    /// 活动状态只能有一个来源（`activeID`），否则表里会出现两处说法。
    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var displayName: String
        public var path: String?
        public var availability: WorkspaceAvailability

        public init(
            id: UUID,
            displayName: String,
            path: String?,
            availability: WorkspaceAvailability
        ) {
            self.id = id
            self.displayName = displayName
            self.path = path
            self.availability = availability
        }

        public init(bookmark: DirectoryBookmark, availability: WorkspaceAvailability) {
            let trimmed = bookmark.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            self.init(
                id: bookmark.id,
                displayName: trimmed.isEmpty
                    ? (bookmark.lastKnownPath.map { ($0 as NSString).lastPathComponent } ?? "")
                    : trimmed,
                path: bookmark.lastKnownPath,
                availability: availability
            )
        }
    }

    /// 已知工作区最多登记几条（界面上一屏能扫完、又不至于让常用的那条被挤掉）。
    public static let capacity = 8

    /// **最近使用的在前**（第一条 = 活动的那条）。
    public private(set) var entries: [Entry]
    public private(set) var activeID: UUID?

    public init(entries: [Entry] = [], activeID: UUID? = nil) {
        self.entries = entries
        self.activeID = activeID
        // 建好就守住容量：调用方（启动重建 / 测试）不需要记得再调一次。
        enforceCapacity()
    }

    public var isEmpty: Bool { entries.isEmpty }

    public var active: Entry? {
        guard let activeID else { return nil }
        return entries.first { $0.id == activeID }
    }

    /// 界面用的那一份：只在这里把 `activeID` 折成 `isActive`。
    public var candidates: [KnownWorkspace] {
        entries.map {
            KnownWorkspace(
                id: $0.id,
                displayName: $0.displayName,
                path: $0.path,
                availability: $0.availability,
                isActive: $0.id == activeID
            )
        }
    }

    public func entry(id: UUID) -> Entry? {
        entries.first { $0.id == id }
    }

    // MARK: 从磁盘那一份重建

    /// 由书签表重建（启动时走这条路）。
    ///
    /// - 去重键是**解析出的路径**（不是书签 id —— 同一个目录选两次会拿到两条不同 id 的书签）；
    /// - 活动那条**提到最前**：磁盘上只记 `createdAt`，没有「最近一次切换时刻」，
    ///   所以顺序口径就是「活动的第一条 + 其余按书签文件顺序」，`activate` 之后同样提前；
    /// - `activeID` 若在那之后并不在表里（书签被删了 / 全都没了）⇒ 折成 `nil`，
    ///   界面据此回到「没打开工作区」，**不猜**该用哪一条。
    public static func reconciled(
        bookmarks: [DirectoryBookmark],
        activeID: UUID?,
        availability: (DirectoryBookmark) -> WorkspaceAvailability
    ) -> WorkspaceRegistry {
        var entries: [Entry] = []
        var indexByPath: [String: Int] = [:]
        var createdAtByID: [UUID: Date] = [:]

        for bookmark in bookmarks {
            createdAtByID[bookmark.id] = bookmark.createdAt
            let entry = Entry(bookmark: bookmark, availability: availability(bookmark))
            let key = bookmark.lastKnownPath ?? "id:\(bookmark.id.uuidString)"

            if let index = indexByPath[key] {
                let keeper = entries[index]
                let keeperIsActive = keeper.id == activeID
                let candidateIsActive = bookmark.id == activeID
                let candidateIsNewer = (createdAtByID[bookmark.id] ?? .distantPast)
                    > (createdAtByID[keeper.id] ?? .distantPast)
                if candidateIsActive || (!keeperIsActive && candidateIsNewer) {
                    entries[index] = entry
                }
                continue
            }
            indexByPath[key] = entries.count
            entries.append(entry)
        }

        var registry = WorkspaceRegistry(entries: entries, activeID: activeID)
        guard let activeID, entries.contains(where: { $0.id == activeID }) else {
            registry.activeID = nil
            registry.enforceCapacity()
            return registry
        }
        if let index = registry.entries.firstIndex(where: { $0.id == activeID }), index > 0 {
            let entry = registry.entries.remove(at: index)
            registry.entries.insert(entry, at: 0)
        }
        registry.enforceCapacity()
        return registry
    }

    // MARK: 切换

    /// 能不能切到这一条。
    public func decision(for id: UUID) -> WorkspaceSwitchDecision {
        guard let entry = entry(id: id) else { return .refuse(.unknownWorkspace) }
        if entry.id == activeID { return .alreadyActive }
        guard entry.availability.isUsable else { return .refuse(.unavailable(entry.availability)) }
        return .switchTo(entry.id)
    }

    /// 切过去：裁决通过才动（提前 + 设活动），否则原样返回。
    ///
    /// 返回裁决本身 —— 调用方要按它决定「取不取授权 / 报不报不可用」，不能自己再判一遍
    /// （两处各判一次，迟早出现「这边说能切、那边说不能」）。
    @discardableResult
    public mutating func activate(_ id: UUID) -> WorkspaceSwitchDecision {
        let verdict = decision(for: id)
        guard case .switchTo = verdict, let index = entries.firstIndex(where: { $0.id == id }) else {
            return verdict
        }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
        activeID = entry.id
        return verdict
    }

    /// 登记一个新选的工作区（并把活动指过去），返回**最终落到的那个 id**。
    ///
    /// 返回 id 是关键：同一目录已登记过时这里**复用旧 id**，调用方得按返回的 id 落盘
    /// （把新书签数据存到旧 id 上），否则磁盘上会同时留着两条指向同一目录的书签。
    @discardableResult
    public mutating func add(_ entry: Entry) -> UUID {
        var resolved = entry
        if let path = entry.path, let index = entries.firstIndex(where: { $0.path == path }) {
            resolved.id = entries[index].id
            entries.remove(at: index)
        } else if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries.remove(at: index)
        }
        entries.insert(resolved, at: 0)
        activeID = resolved.id
        enforceCapacity()
        return resolved.id
    }

    /// 容量：到上限淘汰表尾（最久未用），但**永不淘汰活动那条**。
    private mutating func enforceCapacity() {
        while entries.count > Self.capacity {
            guard let index = entries.lastIndex(where: { $0.id != activeID }) else { return }
            entries.remove(at: index)
        }
    }
}
