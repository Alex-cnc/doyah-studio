import Foundation

// 两级归属（笔记本架 → 笔记本 → 笔记）的**宿主装配侧导航** —— 队列 `L-97` 界面半的第一片；
// 队列 `L-184`（三栏重排）**第二片**在这里加两件事：左栏的「最近」/「标签」两个范围，
// 以及中栏那根**排序条**（`NotesSortOrder`）。
//
// 契约出处：`DoyahNotes/Docs/核心契约.md` **§2.12 两层归属（`Shelf` / `Notebook`）**；
// 结构那份模型在 `Core/Notebook.swift`（第一片），落库在 `Core/NoteStorage/*`（第二 / 三片）。
// 这一片只做**界面要用的那几个决定**，每个都写成纯函数（可单测、与视图无关）：
//   ① **选中态**（`NotesScope`）：看全部 / 看某个架 / 看某个笔记本 / 看某个标签 / 看「最近」——
//      并且**认不出的目标怎么处置**；
//   ② **范围过滤**（`filter`）：把一份笔记按当前范围筛一遍 —— 命中后仍按归属复核（契约 §2.12 第 5 条
//      「范围过滤不得只靠索引」），顺序**原样保留**（库里给的顺序即用户看到的顺序）；
//   ③ **搜索范围**（`NotesSearchScope`）：搜索时是搜「当前范围」还是搜「全部」——
//      这是界面上一枚开关，但它决定的是「哪些结果能显示」；
//   ④ **排序**（`NotesSortOrder`）：中栏列表按什么排 —— 一条总序 + 定死的第二关键字；
//   ⑤ **列表的唯一入口**（`listing`）= 过滤 + 排序，宿主只许调它（不许自己拼这两步）。
//
// 几条口径（写在这里，视图与 `AppState` 都只许引用，不许各写一套）：
//   · **缺归属的笔记算在默认笔记本里**（与 `NotebookDirectory.resolvedNotebookUid` 同一处兜底）；
//   · **认不出的范围目标 ⇒ 回落「全部」**（笔记本被删掉之后、标签下最后一条被删之后，界面不该停在
//     一个已经不存在的范围上、更不该显示成空 —— 空列表会被读成「笔记没了」，而事实是「那个东西没了」）；
//   · **新建笔记的落点**：当前在某个笔记本里 ⇒ 落那个笔记本；否则落默认笔记本（`destinationNotebookUid`）；
//   · **标签与「最近」是跨笔记本的范围**：它们不挂在某个容器上（标签横跨各笔记本、最近横跨各架），
//     所以列表行必须如实标出「属于哪个笔记本」（`isCrossNotebook`）。

/// 界面上「正在看哪一块」。
public enum NotesScope: Hashable, Sendable {
    /// 全部笔记（跨架跨笔记本）。
    case all
    /// 某个架（架里的所有笔记本）。
    case shelf(uid: String)
    /// 某个笔记本。
    case notebook(uid: String)
    /// **某个标签**（队列 `L-184` 第二片）：跨全部笔记本 —— 标签不挂在容器上
    /// （`Note.tags` 是笔记自己的字段，架 / 笔记本的归属在 `NotebookPlacement` 另存）。
    case tag(String)
    /// **「最近」**（队列 `L-184` 第二片）：最近更新过的那一批，跨全部笔记本。
    /// 份数由 `NotesNavigation.recentLimit` 定 —— 它是一个**有界的短列表**，不是第二个「全部笔记」。
    case recent

    /// 越界检查用：范围指向的那个 uid（`.all` / `.recent` / `.tag` 都是 `nil` —— 前者没有目标，
    /// 后两者指向的是**内容条件**而不是一个容器 uid）。
    public var targetUid: String? {
        switch self {
        case .all, .recent, .tag: return nil
        case .shelf(let uid): return uid
        case .notebook(let uid): return uid
        }
    }

    /// 这一块本身是不是**跨笔记本**的（标签 / 最近 / 全部）。
    /// 界面据此决定「列表行里要不要如实标出这条属于哪个笔记本」—— 判据在 Core 一处，
    /// 视图不自己 `switch`（两处各写一遍必分家，这一族的老毛病）。
    public var isCrossNotebook: Bool {
        switch self {
        case .all, .recent, .tag: return true
        case .shelf, .notebook: return false
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

/// **中栏列表按什么排**（队列 `L-184` 第二片）。
///
/// 三条口径：
///  ① **只有这三种**：最近更新 / 创建时间 / 标题 —— 够用且都能被单测钉住；
///  ② **每种都带第二关键字**（`sorted` 本身**不稳定**，只给一个关键字时同一批数据两次渲染
///     顺序可能不同 —— 界面上就是「刷新一下顺序变了」）；第二关键字 = 标题，第三 = `uid`
///     （标题重名时仍要有确定的次序）；
///  ③ **默认 = 最近更新在前**（三栏重排之前就是这个口径，改版不许顺手改掉它）。
public enum NotesSortOrder: String, CaseIterable, Sendable {
    /// 最近更新在前。
    case updatedDesc
    /// 最近创建在前。
    case createdDesc
    /// 标题升序。
    case titleAsc

    /// 这一档在语言表里的名字（句子只从语言表来 —— Core 里一个汉字都没有）。
    public var key: LKey {
        switch self {
        case .updatedDesc: return .notesSortUpdated
        case .createdDesc: return .notesSortCreated
        case .titleAsc: return .notesSortTitle
        }
    }

    /// 排序谓词（**总序**：任何两条都能定出先后，不存在「相等 ⇒ 顺序看运气」）。
    public var comparator: (Note, Note) -> Bool {
        switch self {
        case .updatedDesc:
            return { left, right in
                if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
                return Self.titleThenID(left, right)
            }
        case .createdDesc:
            return { left, right in
                if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
                return Self.titleThenID(left, right)
            }
        case .titleAsc:
            return { left, right in Self.titleThenID(left, right) }
        }
    }

    /// 第二 / 第三关键字：标题升序，重名时按 `uid` —— 保证是一个**总序**。
    private static func titleThenID(_ left: Note, _ right: Note) -> Bool {
        if left.title != right.title { return left.title < right.title }
        return left.id.uuidString < right.id.uuidString
    }
}

/// 两级导航的全部纯逻辑（值类型、无副作用）。
public struct NotesNavigation: Equatable, Sendable {

    /// 「最近」这一屏装多少条（队列 `L-184` 第二片）。
    ///
    /// 为什么是**有界**的：列表本来就按更新时间倒序，无界的「最近」就等于「全部笔记」——
    /// 那是一个没有内容的第二入口（`L-50` 同族：点了像没点）。30 条 = 一屏多一点、还能一眼扫完。
    public static let recentLimit = 30

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
        notes.filter { contains(.notebook(uid: notebookUid), note: $0) }.count
    }

    /// 某个架里有多少条笔记（同一条口径：数列表、走同一条判断）。
    public func noteCount(inShelf shelfUid: String, notes: [Note]) -> Int {
        notes.filter { contains(.shelf(uid: shelfUid), note: $0) }.count
    }

    /// **标签汇总**（队列 `L-184` 第二片）：出现次数降序、同次数字典序。
    ///
    /// 直接沿用检索那一份（`NoteSearch.tagCounts`）—— 「一个标签下有多少条」只许有一种算法。
    /// 与 `noteCount(inTag:notes:)` **是同一条判断**（都是「这条笔记含这个标签」，
    /// 且同一笔记里重复写两次只算一条），所以侧栏上的数字与点进去的列表行数不可能对不上。
    public func tags(in notes: [Note]) -> [(tag: String, count: Int)] {
        NoteSearch.tagCounts(notes)
    }

    /// 某个标签下有多少条（走同一条判断 `contains`；同一笔记重复写两次只算一条）。
    public func noteCount(inTag tag: String, notes: [Note]) -> Int {
        notes.filter { contains(.tag(tag), note: $0) }.count
    }

    // MARK: - 选中态

    /// 把选中态**归一**：指向已不存在的目标 ⇒ 回落「全部」。
    /// 为什么不是「显示空列表」：空的列表会被读成「笔记没了」，而事实是「那个容器 / 那个标签没了」。
    ///
    /// 为什么需要 `notes`：容器（架 / 笔记本）的存亡在 `directory` 里，**标签的存亡只在笔记里**
    /// （没有「标签表」这回事 —— 标签是笔记自己的字段）。传 `notes` 进来，两件事在同一处判。
    public func normalized(_ scope: NotesScope, notes: [Note]) -> NotesScope {
        switch scope {
        case .all, .recent:
            return scope
        case .shelf(let uid):
            return directory.shelf(uid: uid) == nil ? .all : scope
        case .notebook(let uid):
            return directory.notebook(uid: uid) == nil ? .all : scope
        case .tag(let name):
            // 一个标签下面一条都没有 ⇒ 这个标签在界面上已经不存在了（侧栏那一行都没了）
            return notes.contains { $0.tags.contains(name) } ? scope : .all
        }
    }

    // MARK: - 范围过滤

    /// 一条笔记是否落在某个范围里（**成员判定**）。
    ///
    /// `.recent` 的成员条件不在这一层：它要「先按更新时间排一遍、再取前 N 条」，
    /// 单看一条笔记判不出来 ⇒ 那一步在 `filter` / `listing` 里。这里 `.recent` 一律算「在」。
    public func contains(_ scope: NotesScope, note: Note) -> Bool {
        switch scope {
        case .all, .recent:
            return true
        case .tag(let name):
            return note.tags.contains(name)
        case .notebook(let uid):
            return notebookUid(forNote: note.id.uuidString) == uid
        case .shelf(let uid):
            return directory.notebook(uid: notebookUid(forNote: note.id.uuidString))?.shelfUid == uid
        }
    }

    /// 把一份笔记按范围筛一遍，**顺序原样保留**（库里给的顺序 = 用户看到的顺序；
    /// 这里只做「留 / 不留」，不重排 —— 重排会让搜索结果的次序与命中次序不一致）。
    ///
    /// `searchScope` = 搜索时的那枚开关：`.all` ⇒ 不看范围（跨笔记本搜）；`.current` ⇒ 限定在当前范围。
    ///
    /// `.recent` 是唯一会**裁掉**成员的（按更新时间取前 `recentLimit` 条）；其余范围只做留 / 不留。
    public func filter(
        _ notes: [Note],
        scope: NotesScope,
        searchScope: NotesSearchScope = .current
    ) -> [Note] {
        let effective: NotesScope = searchScope == .all ? .all : normalized(scope, notes: notes)
        if case .recent = effective {
            return Array(notes.sorted(by: NotesSortOrder.updatedDesc.comparator).prefix(Self.recentLimit))
        }
        guard effective != .all else { return notes }
        return notes.filter { contains(effective, note: $0) }
    }

    /// **中栏列表的唯一入口**（队列 `L-184` 第二片）= 范围过滤 + 排序。
    ///
    /// 宿主（`AppState.visibleNotes`）只许调它：过滤那一步的兜底（缺归属 / 认不出的范围）与
    /// 排序那一步的第二关键字（`NotesSortOrder.comparator`）都在 Core 一处，
    /// 视图或宿主自己拼一遍就会出现「列表顺序与判据不一致」。
    public func listing(
        _ notes: [Note],
        scope: NotesScope,
        searchScope: NotesSearchScope = .current,
        sort: NotesSortOrder = .updatedDesc
    ) -> [Note] {
        filter(notes, scope: scope, searchScope: searchScope).sorted(by: sort.comparator)
    }

    /// 新建笔记该落在哪个笔记本：在某个笔记本里 ⇒ 那个；其余（全部 / 某个架 / 标签 / 最近）⇒ 默认笔记本。
    /// 为什么架也落默认笔记本：架只说明「往哪一类里放」，具体格子没有指定过 —— 凭空挑一个格子
    /// 比落默认笔记本更意外（默认笔记本是契约里那个**不可删**的落点）。
    public func destinationNotebookUid(for scope: NotesScope) -> String {
        switch normalized(scope, notes: []) {
        case .notebook(let uid):
            return uid
        case .all, .shelf, .tag, .recent:
            return directory.resolvedNotebookUid(nil)
        }
    }
}
