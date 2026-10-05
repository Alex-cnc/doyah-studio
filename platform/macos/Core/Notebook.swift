import Foundation

// 两层归属（**笔记本架 → 笔记本 → 笔记**）的 Core 模型 —— 队列 `L-97` 的第一片（Core 半）。
//
// 契约出处：`DoyahNotes/Docs/核心契约.md` **§2.12 两层归属（`Shelf` / `Notebook`）**
// （该节由本侧循环第 151 轮落笔，提交 `357dbd6`）。本侧**只引用不复制**：
// 类型名与字段名与契约同形（宿主侧的 `Note` 即契约里的 `Inspiration`），语义逐条对齐。
//
// 这一片**刻意不碰存储、不碰界面**（两半各自成片，不半改）：
//   ① 纯逻辑：两层结构、默认容器、旧数据兜底、删除处置、跨笔记本移动、范围过滤；
//   ② 不新增库表 / 不改 `Note` 结构 —— 归属的落库与界面接线是下一片，
//      在这一片落地前，归属关系以 `NotebookPlacement`（`noteID` ↔ `notebookUid` 对）表示。
//
// 契约 §2.12 的五条口径，逐条对应到本文件：
//   ① 两层结构：架 → 笔记本 → 笔记，**层层有归属**、不开放任意深度、笔记不直接属于架；
//   ② 默认架 / 默认笔记本：首次运行创建、**不可删**、可改名；不新建即落默认；
//   ③ 旧数据 / 旧备份缺归属字段：一律落**默认笔记本**（不新造身份、不丢条目）；
//   ④ 删除处置：删笔记本（一并删 / **移到默认笔记本**）、删架（一并删 / **整架移到默认架**），默认都取后者；
//   ⑤ 跨笔记本移动**不刷新 `updatedAt`**；范围过滤**不得只靠索引**（命中后仍按归属复核）。

/// 顶层容器：**笔记本架**（契约 `Shelf`）。
///
/// `uid` = **跨端稳定身份**（契约 §2.11）：首次落库生成、此后不变；它与本机的自增 `id` 是两件事，
/// 只有 `uid` 进交换面。指纹不是身份 —— 改名不换 `uid`。
public struct Shelf: Identifiable, Codable, Equatable, Hashable, Sendable {

    public var uid: String
    public var name: String
    /// 界面排序位（同一层内比较；不参与交换面的语义判定）。
    public var sortOrder: Int
    public var createdAt: Date
    /// 默认架 —— **不可删**、可改名（契约 §2.12 第 3 条）。
    public var isDefault: Bool

    public var id: String { uid }

    public init(
        uid: String = UUID().uuidString,
        name: String,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        isDefault: Bool = false
    ) {
        self.uid = uid
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.isDefault = isDefault
    }
}

/// 中间层：**笔记本**（契约 `Notebook`）。它**必须**属于某个架 —— `shelfUid` 非空。
public struct Notebook: Identifiable, Codable, Equatable, Hashable, Sendable {

    public var uid: String
    /// 所属架。**非空**：不存在无归属的笔记本（契约 §2.12 契约级不变量）。
    public var shelfUid: String
    public var name: String
    public var sortOrder: Int
    public var createdAt: Date
    /// 默认笔记本 —— **不可删**、可改名（契约 §2.12 第 3 条）。
    public var isDefault: Bool

    public var id: String { uid }

    public init(
        uid: String = UUID().uuidString,
        shelfUid: String,
        name: String,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        isDefault: Bool = false
    ) {
        self.uid = uid
        self.shelfUid = shelfUid
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.isDefault = isDefault
    }
}

/// 删除容器时对**里面东西**的处置（契约 §2.12 第 3 条）。`moveToDefault` 是**默认档**。
public enum ContainerRemovalPolicy: String, Codable, Sendable, CaseIterable {
    /// 一并删掉里面的笔记 / 笔记本。
    case deleteTogether
    /// 移到默认容器（删笔记本 → 移到默认笔记本；删架 → 整架移到默认架）。**默认**。
    case moveToDefault

    public static let `default`: ContainerRemovalPolicy = .moveToDefault
}

/// 一条笔记的归属（`noteID` ↔ `notebookUid`）。
///
/// 为什么先有这个轻量对、而不是直接把字段塞进 `Note`：归属的落库（库表 + 迁移）是**另一片**，
/// 在那之前把字段塞进 `Note` 会让「读回来丢字段、写回去抹掉」变成一个**静默的数据损坏**。
public struct NotebookPlacement: Equatable, Hashable, Sendable {

    /// 笔记的身份（宿主侧 = `Note.id.uuidString`）。
    public var noteID: String
    /// 所属笔记本；`nil` / 空串 / 认不出的 uid 一律按「缺归属」处置（落默认笔记本）。
    public var notebookUid: String?

    public init(noteID: String, notebookUid: String?) {
        self.noteID = noteID
        self.notebookUid = notebookUid
    }
}

/// 被删容器的**种类**：删笔记本与删架是两条不同的路 ——
/// 前者改挂**笔记**（`note.notebook_uid`），后者改挂**笔记本**（`notebook.shelf_uid`）。
/// 没有这一格时，「把计划落库」那一步只能靠猜（探测 uid 是架还是笔记本），
/// 而猜错一次就是「删了架却把里面的笔记本整批带走」——所以这一格由计划自己带（第 168 轮补）。
public enum NotebookContainerKind: String, Codable, Sendable, CaseIterable {
    case shelf
    case notebook
}

/// 一次删除要动的**东西**（纯逻辑算出来的计划，本身不写库）。
public struct ContainerRemovalPlan: Equatable, Sendable {

    /// 被删掉的容器 uid（笔记本或架）。默认容器**不会**出现在这里。
    public var removedContainerUid: String
    /// 被删的容器是架还是笔记本（决定改挂笔记还是改挂笔记本）。
    public var removedContainerKind: NotebookContainerKind
    public var policy: ContainerRemovalPolicy
    /// `moveToDefault` 时的落点（删笔记本 → 默认笔记本；删架 → 默认架）。`deleteTogether` 时为 `nil`。
    public var targetContainerUid: String?
    /// 随之被删掉的笔记本 uid（删架 + `deleteTogether` 时才非空）。
    public var removedNotebookUids: [String]
    /// 不被删、但要**改挂**到别处的笔记本（删架 + `deleteTogether` 时的默认笔记本 —— 它不可删）。
    public var movedNotebookUids: [String]
    /// 会被**删掉**的笔记（`deleteTogether`）。
    public var deletedNoteIDs: [String]
    /// 会被**移动**的笔记（`moveToDefault`）。
    public var movedNoteIDs: [String]

    /// 确认框要写的那句话里的两个数（契约：非空时写明「将影响多少笔记本与多少条笔记」）。
    /// 「受影响」= **被删的 + 被改挂的**（与下面 `affectedNoteCount` 同一条形状）：删架走默认档时
    /// 一个笔记本都不删、但整架的笔记本都要改挂 —— 只数「被删的」会让确认框说「将影响 0 个笔记本」，
    /// 而实际上整架都会动（第 168 轮实测：`removedNotebookUids` 在这个档位**本来就该是空**）。
    public var affectedNotebookCount: Int { removedNotebookUids.count + movedNotebookUids.count }
    public var affectedNoteCount: Int { deletedNoteIDs.count + movedNoteIDs.count }
}

/// 两层归属的**目录**：把两层结构 + 归属语义收在一个值类型里（纯函数、无副作用、可单测）。
///
/// 纪律：**每个入口都先走 `normalized()` 的口径**（缺默认容器 ⇒ 补出来），
/// 这样「旧库 / 手改过的库 / 只写了半个的库」不会让上层各写一套兜底。
public struct NotebookDirectory: Equatable, Sendable {

    public private(set) var shelves: [Shelf]
    public private(set) var notebooks: [Notebook]

    public init(shelves: [Shelf], notebooks: [Notebook]) {
        self.shelves = shelves
        self.notebooks = notebooks
    }

    // MARK: - 默认容器

    /// 首次运行的两层结构：**一个默认架 + 一个默认笔记本**（都在架里落位）。
    ///
    /// **名字由调用方给**（`shelfName` / `notebookName`）：默认容器的名字是**要落库的数据**、
    /// 也是用户第一眼看到的东西 —— 它属于宿主层的语言表，Core 不许写死文案
    /// （口径 = `Docs/概要设计.md` §7「语言由调用方给定」，判据 = `Scripts/check-core-localization.py`）。
    public static func bootstrap(shelfName: String, notebookName: String, now: Date = Date()) -> NotebookDirectory {
        let shelf = Shelf(name: shelfName, sortOrder: 0, createdAt: now, isDefault: true)
        let notebook = Notebook(
            shelfUid: shelf.uid,
            name: notebookName,
            sortOrder: 0,
            createdAt: now,
            isDefault: true
        )
        return NotebookDirectory(shelves: [shelf], notebooks: [notebook])
    }

    public var defaultShelf: Shelf? { shelves.first { $0.isDefault } }

    public var defaultNotebook: Notebook? { notebooks.first { $0.isDefault } }

    /// 补出缺的默认容器（**幂等**）：一个默认架都没有 ⇒ 建一个；一个默认笔记本都没有 ⇒ 建一个（挂在默认架上）。
    /// 注意它**不会**把「多个 isDefault」悄悄收成一个 —— 那是数据异常，交给门禁 / 单测发现。
    public func normalized(shelfName: String, notebookName: String, now: Date = Date()) -> NotebookDirectory {
        var shelves = self.shelves
        var notebooks = self.notebooks

        if !shelves.contains(where: { $0.isDefault }) {
            shelves.append(Shelf(name: shelfName, sortOrder: shelves.count, createdAt: now, isDefault: true))
        }
        let shelfUid = shelves.first { $0.isDefault }!.uid

        if !notebooks.contains(where: { $0.isDefault }) {
            notebooks.append(
                Notebook(shelfUid: shelfUid, name: notebookName, sortOrder: notebooks.count, createdAt: now, isDefault: true)
            )
        }
        return NotebookDirectory(shelves: shelves, notebooks: notebooks)
    }

    /// 内部用的**结构补缺**：只补出「有个默认容器」这件事，名字留空。
    /// 为什么可以留空：所有调用点都只读它的 **uid**（兜底落点 / 删架目标），这个目录本身不会被落库、也不会被渲染。
    private func structuralized(now: Date = Date()) -> NotebookDirectory {
        normalized(shelfName: "", notebookName: "", now: now)
    }

    /// 归属解析（**唯一的一处兜底**）：认得出就用它，认不出（`nil` / 空串 / 未知 uid / 已删的笔记本）
    /// 一律落**默认笔记本**。契约 §2.12 第 2 条：旧数据与旧备份缺归属字段 ⇒ 落默认容器。
    public func resolvedNotebookUid(_ raw: String?) -> String {
        let directory = structuralized()
        guard let raw, !raw.isEmpty, directory.notebooks.contains(where: { $0.uid == raw }) else {
            return directory.defaultNotebook!.uid
        }
        return raw
    }

    /// 架归属解析（同一条兜底，落默认架）。
    public func resolvedShelfUid(_ raw: String?) -> String {
        let directory = structuralized()
        guard let raw, !raw.isEmpty, directory.shelves.contains(where: { $0.uid == raw }) else {
            return directory.defaultShelf!.uid
        }
        return raw
    }

    /// 认得出就回笔记本，认不出回 `nil`（**不兜底** —— 需要兜底的地方走 `resolvedNotebookUid`）。
    public func notebook(uid: String?) -> Notebook? {
        guard let uid else { return nil }
        return notebooks.first { $0.uid == uid }
    }

    public func shelf(uid: String?) -> Shelf? {
        guard let uid else { return nil }
        return shelves.first { $0.uid == uid }
    }

    // MARK: - 排序与列表

    /// 架列表：按（排序位 → 创建时刻 → uid）稳定排序 —— 三者都参与，排序位相同的两条不会来回跳。
    public var sortedShelves: [Shelf] {
        shelves.sorted(by: Self.before)
    }

    /// 某个架里的笔记本（同一条稳定排序）。
    public func notebooks(inShelf shelfUid: String) -> [Notebook] {
        notebooks.filter { $0.shelfUid == shelfUid }.sorted(by: Self.before)
    }

    /// 新建笔记本时的排序位（= 同架内现有条数，**不是**全局条数）。
    public func nextSortOrder(inShelf shelfUid: String) -> Int {
        notebooks(inShelf: shelfUid).count
    }

    private static func before<T>(_ lhs: T, _ rhs: T) -> Bool where T: Sortable {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.identityKey < rhs.identityKey
    }

    // MARK: - 范围过滤

    /// 按笔记本过滤笔记。**缺归属的笔记算在默认笔记本里**（与 `resolvedNotebookUid` 同一口径）。
    ///
    /// 契约 §2.12 第 3 条要求「范围过滤不得只靠索引」：所以这里对**每一条**都重算它的归属再比对，
    /// 而不是相信调用方送进来的分组结果（索引与归属不一致时，前者只是快，后者才是对）。
    public func notes(_ placements: [NotebookPlacement], inNotebook notebookUid: String) -> [NotebookPlacement] {
        placements.filter { resolvedNotebookUid($0.notebookUid) == notebookUid }
    }

    /// 按架过滤笔记：先落在架里的笔记本集合上，再逐条复核归属（同样不靠索引）。
    public func notes(_ placements: [NotebookPlacement], inShelf shelfUid: String) -> [NotebookPlacement] {
        let directory = structuralized()
        let inShelf = Set(directory.notebooks(inShelf: shelfUid).map(\.uid))
        return placements.filter { inShelf.contains(directory.resolvedNotebookUid($0.notebookUid)) }
    }

    // MARK: - 跨笔记本移动

    /// 把若干条笔记移到目标笔记本（纯变换）。
    ///
    /// 契约 §2.12 第 4 条：**移动不刷新 `updatedAt`** —— 这不是「实现时记得别改」的纪律，而是这个变换的
    /// **形状**：它的输入输出都只有归属对，**碰不到时间字段**（笔记的时间戳由调用方按自己的写入语义决定，
    /// 移动不属于「编辑正文」，所以不构成一次内容更新）。
    public func move(
        _ placements: [NotebookPlacement],
        noteIDs: [String],
        toNotebook notebookUid: String
    ) -> [NotebookPlacement] {
        let target = resolvedNotebookUid(notebookUid)
        let moving = Set(noteIDs)
        return placements.map {
            moving.contains($0.noteID) ? NotebookPlacement(noteID: $0.noteID, notebookUid: target) : $0
        }
    }

    // MARK: - 删除处置

    /// 删笔记本的计划。默认容器**删不掉**（返回 `nil`，调用方不必自己判）。
    public func removalPlan(
        forNotebook notebookUid: String,
        policy: ContainerRemovalPolicy = .default,
        placements: [NotebookPlacement]
    ) -> ContainerRemovalPlan? {
        let directory = structuralized()
        guard let target = directory.notebook(uid: notebookUid), !target.isDefault else { return nil }
        let affected = directory.notes(placements, inNotebook: target.uid).map(\.noteID)
        return ContainerRemovalPlan(
            removedContainerUid: target.uid,
            removedContainerKind: .notebook,
            policy: policy,
            targetContainerUid: policy == .moveToDefault ? directory.defaultNotebook?.uid : nil,
            removedNotebookUids: [],
            movedNotebookUids: [],
            deletedNoteIDs: policy == .deleteTogether ? affected : [],
            movedNoteIDs: policy == .moveToDefault ? affected : []
        )
    }

    /// 删架的计划：默认架删不掉；档位同删笔记本（删架 = 整架的笔记本跟着走）。
    /// `deleteTogether` 时把架里所有笔记本（以及它们的笔记）都算进「将被删」的清单。
    public func removalPlan(
        forShelf shelfUid: String,
        policy: ContainerRemovalPolicy = .default,
        placements: [NotebookPlacement]
    ) -> ContainerRemovalPlan? {
        let directory = structuralized()
        guard let target = directory.shelf(uid: shelfUid), !target.isDefault else { return nil }
        let notebooksInShelf = directory.notebooks(inShelf: target.uid)
        // 默认笔记本不随架一起删（契约：默认容器不可删）⇒ `deleteTogether` 时它改挂到默认架，
        // 它里面的笔记也**不删**（跟着笔记本走）。
        let unremovable = notebooksInShelf.filter { $0.isDefault }.map(\.uid)
        let deletableNotebooks = notebooksInShelf.filter { !$0.isDefault }
        let affected = placements.filter {
            deletableNotebooks.map(\.uid).contains(directory.resolvedNotebookUid($0.notebookUid))
        }.map(\.noteID)

        switch policy {
        case .moveToDefault:
            return ContainerRemovalPlan(
                removedContainerUid: target.uid,
                removedContainerKind: .shelf,
                policy: policy,
                targetContainerUid: directory.defaultShelf?.uid,
                removedNotebookUids: [],
                // 整架搬走的是**笔记本**（笔记跟着自己的笔记本，一条都不改挂）⇒ 计划里要如实记下
                // 「哪些笔记本会被改挂」，确认框那句「将影响多少笔记本」才算得出来（第 168 轮补）。
                movedNotebookUids: notebooksInShelf.map(\.uid),
                deletedNoteIDs: [],
                movedNoteIDs: []
            )
        case .deleteTogether:
            return ContainerRemovalPlan(
                removedContainerUid: target.uid,
                removedContainerKind: .shelf,
                policy: policy,
                targetContainerUid: directory.defaultShelf?.uid,
                removedNotebookUids: deletableNotebooks.map(\.uid),
                movedNotebookUids: unremovable,
                deletedNoteIDs: affected,
                movedNoteIDs: []
            )
        }
    }

    /// 删架（`moveToDefault` 档）时，架里的笔记本要挂到哪去：默认架，**排序位顺延**到默认架现有条数之后。
    public func notebooksMovedToDefaultShelf(fromShelf shelfUid: String) -> [Notebook] {
        let directory = structuralized()
        guard let targetShelf = directory.shelf(uid: shelfUid), !targetShelf.isDefault else { return [] }
        let destination = directory.defaultShelf!.uid
        var next = directory.notebooks(inShelf: destination).count
        return directory.notebooks(inShelf: shelfUid).map { notebook in
            var moved = notebook
            moved.shelfUid = destination
            moved.sortOrder = next
            next += 1
            return moved
        }
    }
}

/// 排序用的最小形状（让上面那一段稳定排序对 `Shelf` / `Notebook` 是同一份实现）。
protocol Sortable {
    var sortOrder: Int { get }
    var createdAt: Date { get }
    var identityKey: String { get }
}

extension Shelf: Sortable {
    var identityKey: String { uid }
}

extension Notebook: Sortable {
    var identityKey: String { uid }
}
