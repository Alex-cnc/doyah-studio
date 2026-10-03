import Foundation

// 两级归属（笔记本架 → 笔记本 → 笔记）的**宿主装配侧导航** —— 队列 `L-97` 界面半的第一片。
//
// 契约出处：`DoyahNotes/Docs/核心契约.md` **§2.12 两层归属（`Shelf` / `Notebook`）**；
// 结构那份模型在 `Core/Notebook.swift`（第一片），落库在 `Core/NoteStorage/*`（第二 / 三片）。
// 这一片只做**界面要用的那三个决定**，每个都写成纯函数（可单测、与视图无关）：
//   ① **选中态**（`NotesScope`）：看全部 / 看某个架 / 看某个笔记本 —— 并且**认不出的目标怎么处置**；
//   ② **范围过滤**（`filter`）：把一份笔记按当前范围筛一遍 —— 命中后仍按归属复核（契约 §2.12 第 5 条
//      「范围过滤不得只靠索引」），顺序**原样保留**（库里给的顺序即用户看到的顺序）；
//   ③ **搜索范围**（`NotesSearchScope`）：搜索时是搜「当前范围」还是搜「全部」——
//      这是界面上一枚开关，但它决定的是「哪些结果能显示」。
//
// 三条口径（写在这里，视图与 `AppState` 都只许引用，不许各写一套）：
//   · **缺归属的笔记算在默认笔记本里**（与 `NotebookDirectory.resolvedNotebookUid` 同一处兜底）；
//   · **认不出的范围目标 ⇒ 回落「全部」**（笔记本被删掉之后，界面不该停在一个已经不存在的范围上、
//     更不该显示成空 —— 空列表会被读成「笔记没了」，而事实是「那个笔记本没了」）；
//   · **新建笔记的落点**：当前在某个笔记本里 ⇒ 落那个笔记本；否则落默认笔记本（`destinationNotebookUid`）。

/// 界面上「正在看哪一块」。
public enum NotesScope: Hashable, Sendable {
    /// 全部笔记（跨架跨笔记本）。
    case all
    /// 某个架（架里的所有笔记本）。
    case shelf(uid: String)
    /// 某个笔记本。
    case notebook(uid: String)

    /// 越界检查用：范围指向的那个 uid（`.all` 为 `nil`）。
    public var targetUid: String? {
        switch self {
        case .all: return nil
        case .shelf(let uid): return uid
        case .notebook(let uid): return uid
        }
    }
}

/// 搜索时的范围（队列 `L-97` ⑤「搜索范围切换（当前笔记本 / 全部）」）。
/// **只有搜索这一个消费者** —— 列表的筛选由 `NotesScope` 管，两者不是一回事：
/// 范围决定「列表里有什么」，搜索范围决定「搜索时要不要限定在这个范围里」。
public enum NotesSearchScope: String, CaseIterable, Sendable {
    /// 只在当前范围里搜（`.all` 范围下等同全部）。
    case current
    /// 跨笔记本搜（结果里要如实标出每条属于哪个笔记本）。
    case all
}

/// 两级导航的全部纯逻辑（值类型、无副作用）。
public struct NotesNavigation: Equatable, Sendable {

    public var directory: NotebookDirectory
    /// 归属对（`noteID` ↔ `notebookUid`）。缺归属的笔记不在里面也算正常 —— 按默认笔记本处置。
    public var placements: [NotebookPlacement]

    public init(directory: NotebookDirectory, placements: [NotebookPlacement]) {
        self.directory = directory
        self.placements = placements
    }

    // MARK: - 树（两级导航要画的东西）

    /// 架列表（稳定排序：排序位 → 创建时刻 → uid）。
    public var shelves: [Shelf] { directory.sortedShelves }

    /// 某个架里的笔记本（同一条稳定排序）。
    public func notebooks(inShelf shelfUid: String) -> [Notebook] {
        directory.notebooks(inShelf: shelfUid)
    }

    /// 默认笔记本 —— 界面上「全部」之外那个永远在的落点。
    public var defaultNotebook: Notebook? { directory.defaultNotebook }

    /// 一条笔记归属的笔记本 uid（**走唯一那处兜底**：认不出 ⇒ 默认笔记本）。
    ///
    /// 「没有归属行」与「uid 认不出」在这里是**同一条路**（都落默认笔记本）—— 这是契约 §2.12 第 2 条
    /// 要的处置；因此对一个**根本不存在的**笔记 id 问归属，得到的也是默认笔记本。
    /// 界面只在真存在的那条笔记上问这个问题（行渲染），所以那条路径造不成误导。
    public func notebookUid(forNote noteID: String) -> String {
        let raw = placements.first { $0.noteID == noteID }?.notebookUid
        return directory.resolvedNotebookUid(raw)
    }

    /// 一条笔记归属的笔记本（拿来在跨笔记本的结果里标「属于哪个笔记本」）。
    public func notebook(forNote noteID: String) -> Notebook? {
        directory.notebook(uid: notebookUid(forNote: noteID))
    }

    public func notebookCount(inShelf shelfUid: String) -> Int {
        directory.notebooks(inShelf: shelfUid).count
    }

    /// 某个笔记本里有多少条笔记。**数的是「这一屏真能看到的那些」**（传入的笔记列表），
    /// 逐条按归属复核（契约 §2.12 第 5 条）——
    /// 为什么不数 `placements`：缺归属行的笔记在列表里会出现（落在默认笔记本），
    /// 却不在归属对里 ⇒ 树上的数字会比列表里的行数少一条（第 169 轮首跑被自己的判据当场打回）。
    /// **计数与筛选必须走同一条判断**（`contains`），所以两者不可能对不上。
    public func noteCount(inNotebook notebookUid: String, notes: [Note]) -> Int {
        notes.filter { contains(.notebook(uid: notebookUid), noteID: $0.id.uuidString) }.count
    }

    /// 某个架里有多少条笔记（同一条口径：数列表、走同一条判断）。
    public func noteCount(inShelf shelfUid: String, notes: [Note]) -> Int {
        notes.filter { contains(.shelf(uid: shelfUid), noteID: $0.id.uuidString) }.count
    }

    // MARK: - 选中态

    /// 把选中态**归一**：指向已不存在的容器（笔记本 / 架被删了、uid 是旧的）⇒ 回落「全部」。
    /// 为什么不是「显示空列表」：空的列表会被读成「笔记没了」，而事实是「那个容器没了」。
    public func normalized(_ scope: NotesScope) -> NotesScope {
        switch scope {
        case .all:
            return .all
        case .shelf(let uid):
            return directory.shelf(uid: uid) == nil ? .all : scope
        case .notebook(let uid):
            return directory.notebook(uid: uid) == nil ? .all : scope
        }
    }

    // MARK: - 范围过滤

    /// 一条笔记是否落在某个范围里。
    public func contains(_ scope: NotesScope, noteID: String) -> Bool {
        let notebookUid = notebookUid(forNote: noteID)
        switch normalized(scope) {
        case .all:
            return true
        case .notebook(let uid):
            return notebookUid == uid
        case .shelf(let uid):
            return directory.notebook(uid: notebookUid)?.shelfUid == uid
        }
    }

    /// 把一份笔记按范围筛一遍，**顺序原样保留**（库里给的顺序 = 用户看到的顺序；
    /// 这里只做「留 / 不留」，不重排 —— 重排会让搜索结果的次序与命中次序不一致）。
    ///
    /// `searchScope` = 搜索时的那枚开关：`.all` ⇒ 不看范围（跨笔记本搜）；`.current` ⇒ 限定在当前范围。
    public func filter(
        _ notes: [Note],
        scope: NotesScope,
        searchScope: NotesSearchScope = .current
    ) -> [Note] {
        let effective: NotesScope = searchScope == .all ? .all : normalized(scope)
        guard effective != .all else { return notes }
        return notes.filter { contains(effective, noteID: $0.id.uuidString) }
    }

    /// 新建笔记该落在哪个笔记本：在某个笔记本里 ⇒ 那个；其余（全部 / 某个架）⇒ 默认笔记本。
    /// 为什么架也落默认笔记本：架只说明「往哪一类里放」，具体格子没有指定过 —— 凭空挑一个格子
    /// 比落默认笔记本更意外（默认笔记本是契约里那个**不可删**的落点）。
    public func destinationNotebookUid(for scope: NotesScope) -> String {
        switch normalized(scope) {
        case .notebook(let uid):
            return uid
        case .all, .shelf:
            return directory.resolvedNotebookUid(nil)
        }
    }
}
