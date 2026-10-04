import XCTest
@testable import DoyahCore

/// **两级导航（笔记本架 → 笔记本 → 笔记）的宿主装配侧判据** —— 队列 `L-97` 界面半第一片。
///
/// 契约出处 = `DoyahNotes/Docs/核心契约.md` §2.12。这一片钉的是**界面要用的三个决定**
/// （选中态 / 范围过滤 / 搜索范围），每条都写成纯函数，所以能在这里逐条判。
///
/// 为什么这些必须判：它们的错法**全都很安静** ——
///   · 范围过滤少写了「命中后按归属复核」⇒ 索引与归属不一致时**笔记凭空少一条**；
///   · 认不出的范围不回落 ⇒ 笔记本被删之后界面停在空列表上，被读成「笔记没了」；
///   · 过滤时顺手重排 ⇒ 搜索结果的次序与命中次序不一致（用户找不到刚才看到的那条）。
final class NoteNavigationTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 夹具：两个架 / 三个笔记本 / 四条笔记（其中一条缺归属）

    /// 结构：
    ///   架 A（默认）→ 笔记本 A1（默认）、笔记本 A2
    ///   架 B        → 笔记本 B1
    /// 归属：n1 → A1、n2 → A2、n3 → B1、n4 = **缺归属**（落默认笔记本 A1）
    ///
    /// 时刻与标签（队列 `L-184` 第二片起）：更新时间 n4 > n1 > n2 > n3、创建时间 n1 < n2 < n3 < n4；
    /// 标签 = n1 `工作`、n2 `工作` `生活`、n3 无、n4 `生活` —— 排序与标签两组判据都靠这四个数 / 四个标签。
    private func makeSUT() -> (navigation: NotesNavigation, notes: [Note], ids: [String: UUID]) {
        let shelfA = Shelf(uid: "shelf-a", name: "架A", sortOrder: 0, createdAt: t0, isDefault: true)
        let shelfB = Shelf(uid: "shelf-b", name: "架B", sortOrder: 1, createdAt: t0, isDefault: false)
        let a1 = Notebook(uid: "nb-a1", shelfUid: shelfA.uid, name: "笔记本A1", sortOrder: 0, createdAt: t0, isDefault: true)
        let a2 = Notebook(uid: "nb-a2", shelfUid: shelfA.uid, name: "笔记本A2", sortOrder: 1, createdAt: t0, isDefault: false)
        let b1 = Notebook(uid: "nb-b1", shelfUid: shelfB.uid, name: "笔记本B1", sortOrder: 0, createdAt: t0, isDefault: false)
        let directory = NotebookDirectory(shelves: [shelfB, shelfA], notebooks: [a2, b1, a1])

        let n1 = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "n1",
            tags: ["工作"], createdAt: t0.addingTimeInterval(10), updatedAt: t0.addingTimeInterval(300)
        )
        let n2 = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "n2",
            tags: ["工作", "生活"], createdAt: t0.addingTimeInterval(20), updatedAt: t0.addingTimeInterval(200)
        )
        let n3 = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, title: "n3",
            tags: [], createdAt: t0.addingTimeInterval(30), updatedAt: t0.addingTimeInterval(100)
        )
        let n4 = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, title: "n4",
            tags: ["生活"], createdAt: t0.addingTimeInterval(40), updatedAt: t0.addingTimeInterval(400)
        )
        let placements = [
            NotebookPlacement(noteID: n1.id.uuidString, notebookUid: a1.uid),
            NotebookPlacement(noteID: n2.id.uuidString, notebookUid: a2.uid),
            NotebookPlacement(noteID: n3.id.uuidString, notebookUid: b1.uid),
            // n4 刻意**没有**归属行（旧数据形态）—— 它必须算在默认笔记本里
        ]
        let navigation = NotesNavigation(directory: directory, placements: placements)
        return (navigation, [n1, n2, n3, n4], ["n1": n1.id, "n2": n2.id, "n3": n3.id, "n4": n4.id])
    }

    // MARK: - 树

    func testShelvesAreSortedAndNotebooksStayInTheirShelf() {
        let sut = makeSUT().navigation
        XCTAssertEqual(sut.shelves.map(\.uid), ["shelf-a", "shelf-b"], "按排序位稳定排序")
        XCTAssertEqual(sut.notebooks(inShelf: "shelf-a").map(\.uid), ["nb-a1", "nb-a2"])
        XCTAssertEqual(sut.notebooks(inShelf: "shelf-b").map(\.uid), ["nb-b1"])
        XCTAssertEqual(sut.notebookCount(inShelf: "shelf-a"), 2)
    }

    func testNoteCountsFollowOwnershipAndTreatMissingPlacementAsDefaultNotebook() {
        let sut = makeSUT()
        let notes = sut.notes
        // **数的是这一屏真能看到的那些**：缺归属行的 n4 在列表里出现（落默认笔记本），
        // 树上的数字必须跟着它一起算 —— 否则树的数字比列表少一条（首跑就是被这条打回的）。
        XCTAssertEqual(sut.navigation.noteCount(inNotebook: "nb-a1", notes: notes), 2)
        XCTAssertEqual(sut.navigation.noteCount(inNotebook: "nb-a2", notes: notes), 1)
        XCTAssertEqual(sut.navigation.noteCount(inNotebook: "nb-b1", notes: notes), 1)
        XCTAssertEqual(sut.navigation.noteCount(inShelf: "shelf-a", notes: notes), 3)
        XCTAssertEqual(sut.navigation.noteCount(inShelf: "shelf-b", notes: notes), 1)
        // 与筛选同一条判断 ⇒ 计数与列表行数不可能对不上（这是这一族判据存在的理由）
        let scopes: [NotesScope] = [
            .all, .shelf(uid: "shelf-a"), .notebook(uid: "nb-a1"), .notebook(uid: "nb-a2"),
            .tag("工作"), .tag("生活"), .recent, .favorites,
        ]
        for scope in scopes {
            let rows = sut.navigation.filter(notes, scope: scope).count
            let counted: Int
            switch scope {
            case .all: counted = notes.count
            case .shelf(let uid): counted = sut.navigation.noteCount(inShelf: uid, notes: notes)
            case .notebook(let uid): counted = sut.navigation.noteCount(inNotebook: uid, notes: notes)
            case .tag(let name): counted = sut.navigation.noteCount(inTag: name, notes: notes)
            // 「最近」这一屏装得下这四条（上限 30）⇒ 计数就是全部
            case .recent: counted = notes.count
            // 「已收藏」（队列 `L-184` 第三片）：数的是同一批 —— 这一份夹具里一条都没收藏 ⇒ 0 行 0 数
            case .favorites: counted = sut.navigation.favoriteCount(in: notes)
            }
            XCTAssertEqual(counted, rows, "范围 \(scope) 的树计数必须等于列表行数")
        }
    }

    func testNotebookForNoteResolvesMissingOwnershipToTheDefaultNotebook() {
        let sut = makeSUT()
        XCTAssertEqual(sut.navigation.notebook(forNote: sut.ids["n4"]!.uuidString)?.uid, "nb-a1")
        // **认不出 = 缺归属，同一条兜底**（契约 §2.12 第 2 条）：没归属行的笔记与 uid 认不出的笔记
        // 处置相同 ⇒ 一个不存在的 id 也会得到默认笔记本。界面只在真存在的那条笔记上问这个问题。
        XCTAssertEqual(sut.navigation.notebook(forNote: "不存在的笔记")?.uid, "nb-a1")
    }

    // MARK: - 选中态归一（认不出 ⇒ 全部）

    func testNormalizedKeepsKnownTargetsAndFallsBackToAllForUnknownOnes() {
        let sut = makeSUT()
        let notes = sut.notes
        XCTAssertEqual(sut.navigation.normalized(.all, notes: notes), .all)
        XCTAssertEqual(sut.navigation.normalized(.notebook(uid: "nb-a2"), notes: notes), .notebook(uid: "nb-a2"))
        XCTAssertEqual(sut.navigation.normalized(.shelf(uid: "shelf-b"), notes: notes), .shelf(uid: "shelf-b"))
        // 容器被删掉之后：**回落全部**，不是显示空列表
        XCTAssertEqual(sut.navigation.normalized(.notebook(uid: "已经删了的笔记本"), notes: notes), .all)
        XCTAssertEqual(sut.navigation.normalized(.shelf(uid: "已经删了的架"), notes: notes), .all)
        XCTAssertEqual(sut.navigation.normalized(.notebook(uid: ""), notes: notes), .all)
        // **标签**（队列 `L-184` 第二片）：标签的存亡只在笔记里（没有「标签表」这回事）
        XCTAssertEqual(sut.navigation.normalized(.tag("工作"), notes: notes), .tag("工作"))
        XCTAssertEqual(
            sut.navigation.normalized(.tag("已经没有笔记用的标签"), notes: notes), .all,
            "标签下最后一条被删 / 改了标签 ⇒ 这个标签在侧栏上已经不存在，范围要回落「全部」而不是空"
        )
        // 「最近」永远有效（它不依赖任何容器或标签）
        XCTAssertEqual(sut.navigation.normalized(.recent, notes: notes), .recent)
        XCTAssertEqual(sut.navigation.normalized(.recent, notes: []), .recent)
    }

    // MARK: - 范围过滤

    func testFilterForANotebookKeepsOnlyItsNotesAndPreservesIncomingOrder() {
        let sut = makeSUT()
        let all = sut.notes
        let filtered = sut.navigation.filter(all, scope: .notebook(uid: "nb-a2"))
        XCTAssertEqual(filtered.map(\.title), ["n2"])
        // 顺序原样保留：把顺序反过来，过滤结果也跟着反过来（不许重排）
        let reversed = Array(all.reversed())
        XCTAssertEqual(sut.navigation.filter(reversed, scope: .notebook(uid: "nb-a2")).map(\.title), ["n2"])
        XCTAssertEqual(sut.navigation.filter(reversed, scope: .all).map(\.title), ["n4", "n3", "n2", "n1"])
    }

    func testFilterForAShelfSpansItsNotebooksAndExcludesTheOtherShelf() {
        let sut = makeSUT()
        XCTAssertEqual(sut.navigation.filter(sut.notes, scope: .shelf(uid: "shelf-a")).map(\.title), ["n1", "n2", "n4"])
        XCTAssertEqual(sut.navigation.filter(sut.notes, scope: .shelf(uid: "shelf-b")).map(\.title), ["n3"])
        XCTAssertEqual(sut.navigation.filter(sut.notes, scope: .notebook(uid: "nb-a1")).map(\.title), ["n1", "n4"])
    }

    func testFilterFallsBackToAllWhenTheScopeTargetIsGone() {
        let sut = makeSUT()
        XCTAssertEqual(
            sut.navigation.filter(sut.notes, scope: .notebook(uid: "删掉的")).map(\.title),
            ["n1", "n2", "n3", "n4"],
            "目标没了 ⇒ 看全部（而不是空）"
        )
    }

    func testSearchScopeAllIgnoresTheCurrentScopeAndCurrentHonoursIt() {
        let sut = makeSUT()
        XCTAssertEqual(
            sut.navigation.filter(sut.notes, scope: .notebook(uid: "nb-a2"), searchScope: .current).map(\.title),
            ["n2"]
        )
        XCTAssertEqual(
            sut.navigation.filter(sut.notes, scope: .notebook(uid: "nb-a2"), searchScope: .all).map(\.title),
            ["n1", "n2", "n3", "n4"],
            "搜「全部」时跨笔记本 —— 结果里要如实标出每条属于哪个笔记本（界面那一半）"
        )
    }

    func testContainsTreatsAnUnownedNoteAsPartOfTheDefaultNotebookAndItsShelf() {
        let sut = makeSUT()
        let unowned = sut.notes.first { $0.title == "n4" }!
        XCTAssertTrue(sut.navigation.contains(.notebook(uid: "nb-a1"), note: unowned))
        XCTAssertTrue(sut.navigation.contains(.shelf(uid: "shelf-a"), note: unowned))
        XCTAssertFalse(sut.navigation.contains(.notebook(uid: "nb-b1"), note: unowned))
        XCTAssertTrue(sut.navigation.contains(.all, note: unowned))
        // **标签与「最近」**（队列 `L-184` 第二片）
        XCTAssertTrue(sut.navigation.contains(.tag("生活"), note: unowned))
        XCTAssertFalse(sut.navigation.contains(.tag("工作"), note: unowned))
        XCTAssertTrue(sut.navigation.contains(.recent, note: unowned), "「最近」不挑成员（成员条件在 filter 里按更新时间裁）")
    }

    // MARK: - 新建笔记的落点

    func testDestinationNotebookIsTheSelectedOneOtherwiseTheDefault() {
        let sut = makeSUT().navigation
        XCTAssertEqual(sut.destinationNotebookUid(for: .notebook(uid: "nb-a2")), "nb-a2")
        XCTAssertEqual(sut.destinationNotebookUid(for: .all), "nb-a1", "看全部时落默认笔记本")
        XCTAssertEqual(sut.destinationNotebookUid(for: .shelf(uid: "shelf-b")), "nb-a1", "架不指定格子 ⇒ 同样落默认笔记本")
        XCTAssertEqual(sut.destinationNotebookUid(for: .notebook(uid: "删掉的")), "nb-a1")
        // 标签 / 最近（队列 `L-184` 第二片）是**跨笔记本**的范围，同样不指定格子 ⇒ 默认笔记本
        XCTAssertEqual(sut.destinationNotebookUid(for: .tag("工作")), "nb-a1")
        XCTAssertEqual(sut.destinationNotebookUid(for: .recent), "nb-a1")
    }

    // MARK: - 标签与「最近」（队列 `L-184` 第二片）

    /// 标签是**跨笔记本**的范围：n1 在 A1、n2 在 A2 —— 同一个标签把两个笔记本里的笔记捞到一起；
    /// 认不出的标签 ⇒ 回落「全部」（不是空列表，见 `normalized`）。
    func testTagScopeSpansNotebooksAndPreservesIncomingOrder() {
        let sut = makeSUT()
        XCTAssertEqual(sut.navigation.filter(sut.notes, scope: .tag("工作")).map(\.title), ["n1", "n2"])
        XCTAssertEqual(sut.navigation.filter(sut.notes, scope: .tag("生活")).map(\.title), ["n2", "n4"])
        XCTAssertEqual(
            sut.navigation.filter(Array(sut.notes.reversed()), scope: .tag("工作")).map(\.title),
            ["n2", "n1"], "顺序原样保留（库里给的顺序 = 用户看到的顺序）"
        )
        XCTAssertEqual(
            sut.navigation.filter(sut.notes, scope: .tag("没有笔记用的标签")).map(\.title),
            ["n1", "n2", "n3", "n4"], "认不出的标签 ⇒ 回落全部"
        )
    }

    /// 侧栏那一栏标签的数字与点进去的行数**必须相等**（同一笔记里重复写两次只算一条）。
    func testTagSummaryIsOrderedByCountThenNameAndMatchesTheRowCount() {
        let sut = makeSUT()
        let summary = sut.navigation.tags(in: sut.notes)
        XCTAssertEqual(summary.map(\.tag), ["工作", "生活"], "次数相同 ⇒ 字典序")
        XCTAssertEqual(summary.map(\.count), [2, 2])
        for entry in summary {
            XCTAssertEqual(
                sut.navigation.noteCount(inTag: entry.tag, notes: sut.notes), entry.count,
                "侧栏数字与点进去的列表行数必须相等"
            )
        }
        // 一条笔记里同一个标签写两遍 ⇒ 仍然只算一条（`Set` 去重那一处口径）
        let duplicated = Note(title: "重", tags: ["工作", "工作"])
        XCTAssertEqual(sut.navigation.noteCount(inTag: "工作", notes: [duplicated]), 1)
        XCTAssertTrue(sut.navigation.tags(in: []).isEmpty, "没有笔记 ⇒ 没有标签（左栏那一段整段不出现）")
    }

    /// 「最近」= **有界**的一屏：按更新时间取前 `recentLimit` 条 —— 无界的「最近」就等于「全部笔记」。
    func testRecentScopeIsBoundedAndKeepsTheMostRecentlyUpdated() {
        let sut = makeSUT()
        XCTAssertEqual(
            sut.navigation.filter(sut.notes, scope: .recent).map(\.title), ["n4", "n1", "n2", "n3"],
            "四条都装得下（上限 30）⇒ 全部，且顺序是更新时间倒序"
        )
        let many = (0..<40).map { index in
            Note(title: String(format: "m%02d", index), updatedAt: t0.addingTimeInterval(Double(index)))
        }
        let recent = sut.navigation.filter(many, scope: .recent)
        XCTAssertEqual(recent.count, NotesNavigation.recentLimit)
        XCTAssertEqual(recent.first?.title, "m39")
        XCTAssertEqual(recent.last?.title, "m10")
        XCTAssertFalse(recent.contains { $0.title == "m09" }, "更旧的进不来 —— 它是有界的短列表，不是第二个「全部笔记」")
    }

    /// 三档排序都是**总序**：同刻 / 同名时仍定得出先后（`sorted` 本身不稳定，少一个关键字就会「刷新一下顺序变了」）。
    func testSortOrdersAreTotalAndDeterministic() {
        let sut = makeSUT()
        let notes = sut.notes
        XCTAssertEqual(notes.sorted(by: NotesSortOrder.updatedDesc.comparator).map(\.title), ["n4", "n1", "n2", "n3"])
        XCTAssertEqual(notes.sorted(by: NotesSortOrder.createdDesc.comparator).map(\.title), ["n4", "n3", "n2", "n1"])
        XCTAssertEqual(notes.sorted(by: NotesSortOrder.titleAsc.comparator).map(\.title), ["n1", "n2", "n3", "n4"])

        let twinA = Note(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000aa")!, title: "同名", updatedAt: t0)
        let twinB = Note(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000bb")!, title: "同名", updatedAt: t0)
        XCTAssertEqual(
            [twinB, twinA].sorted(by: NotesSortOrder.updatedDesc.comparator).map { $0.id.uuidString },
            [twinA.id.uuidString, twinB.id.uuidString],
            "同刻同名 ⇒ 按 uid 定序（第三关键字；不许看运气）"
        )
        XCTAssertEqual([twinA, twinB].sorted(by: NotesSortOrder.titleAsc.comparator).map(\.title), ["同名", "同名"])
        XCTAssertEqual(NotesSortOrder.allCases.count, 3, "只有三档 —— 语言表里也一个不多一个不少")
    }

    /// `listing` = 列表的**唯一入口**（过滤 + 排序）：范围那一步的兜底与排序那一步的关键字都在 Core 一处。
    func testListingIsTheSingleEntryPointForFilteringAndSorting() {
        let sut = makeSUT()
        XCTAssertEqual(
            sut.navigation.listing(sut.notes, scope: .tag("工作"), sort: .titleAsc).map(\.title), ["n1", "n2"]
        )
        XCTAssertEqual(
            sut.navigation.listing(sut.notes, scope: .all).map(\.title), ["n4", "n1", "n2", "n3"],
            "默认 = 最近更新在前（三栏重排之前的口径，不许顺手改掉）"
        )
        XCTAssertEqual(
            sut.navigation.listing(
                sut.notes, scope: .notebook(uid: "nb-a2"), searchScope: .all, sort: .titleAsc
            ).map(\.title),
            ["n1", "n2", "n3", "n4"], "搜「全部笔记本」⇒ 不看当前范围"
        )
        XCTAssertEqual(
            sut.navigation.listing(sut.notes, scope: .recent, sort: .titleAsc).map(\.title),
            ["n1", "n2", "n3", "n4"], "「最近」裁成员、排序仍听排序条"
        )
    }

    /// 「这一块是不是跨笔记本的」只有一处判断（视图据此决定要不要在行上标笔记本）。
    func testScopeKnowsWhetherItSpansNotebooks() {
        XCTAssertTrue(NotesScope.all.isCrossNotebook)
        XCTAssertTrue(NotesScope.tag("工作").isCrossNotebook)
        XCTAssertTrue(NotesScope.recent.isCrossNotebook)
        XCTAssertFalse(NotesScope.shelf(uid: "shelf-a").isCrossNotebook)
        XCTAssertFalse(NotesScope.notebook(uid: "nb-a1").isCrossNotebook)
        // `targetUid` 只对容器有意义（标签 / 最近指向的是内容条件，不是一个 uid）
        XCTAssertNil(NotesScope.tag("工作").targetUid)
        XCTAssertNil(NotesScope.recent.targetUid)
        XCTAssertEqual(NotesScope.notebook(uid: "nb-a1").targetUid, "nb-a1")
    }

    // MARK: - 「已收藏」（队列 `L-184` 第三片）

    /// 这一片自己的一份小夹具：四条笔记里**两条**收藏，其中一条在另一个架里 ——
    /// 「已收藏」是**跨笔记本**的范围（收藏是笔记自己的状态，与它在哪一格无关）。
    private func makeFavoritesSUT() -> (navigation: NotesNavigation, notes: [Note]) {
        let shelfA = Shelf(uid: "shelf-a", name: "架A", sortOrder: 0, createdAt: t0, isDefault: true)
        let shelfB = Shelf(uid: "shelf-b", name: "架B", sortOrder: 1, createdAt: t0, isDefault: false)
        let a1 = Notebook(uid: "nb-a1", shelfUid: shelfA.uid, name: "笔记本A1", sortOrder: 0, createdAt: t0, isDefault: true)
        let b1 = Notebook(uid: "nb-b1", shelfUid: shelfB.uid, name: "笔记本B1", sortOrder: 0, createdAt: t0, isDefault: false)
        let directory = NotebookDirectory(shelves: [shelfA, shelfB], notebooks: [a1, b1])

        let plainNewest = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!, title: "普通·最新",
            createdAt: t0.addingTimeInterval(10), updatedAt: t0.addingTimeInterval(400)
        )
        let favoriteOld = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!, title: "收藏·较旧",
            createdAt: t0.addingTimeInterval(20), updatedAt: t0.addingTimeInterval(100),
            isFavorite: true
        )
        let favoriteOtherShelf = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!, title: "收藏·别的架",
            createdAt: t0.addingTimeInterval(30), updatedAt: t0.addingTimeInterval(200),
            isFavorite: true
        )
        let plainOldest = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A4")!, title: "普通·最旧",
            createdAt: t0.addingTimeInterval(40), updatedAt: t0.addingTimeInterval(50)
        )
        let placements = [
            NotebookPlacement(noteID: plainNewest.id.uuidString, notebookUid: a1.uid),
            NotebookPlacement(noteID: favoriteOld.id.uuidString, notebookUid: a1.uid),
            NotebookPlacement(noteID: favoriteOtherShelf.id.uuidString, notebookUid: b1.uid),
            NotebookPlacement(noteID: plainOldest.id.uuidString, notebookUid: b1.uid),
        ]
        return (NotesNavigation(directory: directory, placements: placements),
                [plainNewest, favoriteOld, favoriteOtherShelf, plainOldest])
    }

    /// 「已收藏」= **跨笔记本**的范围；计数与列表行数走同一条判断。
    func testFavoritesScopeIsCrossNotebookAndCountedByTheSamePredicate() {
        let sut = makeFavoritesSUT()
        XCTAssertTrue(NotesScope.favorites.isCrossNotebook, "收藏横跨各笔记本 / 各架")
        XCTAssertNil(NotesScope.favorites.targetUid, "收藏指向的是内容条件，不是一个容器 uid")
        XCTAssertEqual(sut.navigation.favoriteCount(in: sut.notes), 2)
        XCTAssertEqual(sut.navigation.filter(sut.notes, scope: .favorites).count, 2)
        // **跨架**：两条收藏分属两个架，范围里都得在（收藏与归属无关）
        XCTAssertEqual(sut.navigation.filter(sut.notes, scope: .favorites).map(\.title).sorted(),
                       ["收藏·别的架", "收藏·较旧"].sorted())
    }

    /// 一条收藏都没有时：「已收藏」这一栏**还在**（显示空），**不回落**成「全部」——
    /// 与「标签」的处置相反，因为标签没了 = 那个标签不存在了，而这一栏是常驻入口。
    func testFavoritesScopeStaysPutEvenWhenNothingIsFavorited() {
        let sut = makeFavoritesSUT()
        let none = sut.notes.map { note -> Note in var copy = note; copy.isFavorite = false; return copy }
        XCTAssertEqual(sut.navigation.normalized(.favorites, notes: none), .favorites)
        XCTAssertEqual(sut.navigation.normalized(.favorites, notes: []), .favorites)
        XCTAssertTrue(sut.navigation.filter(none, scope: .favorites).isEmpty)
    }

    /// **收藏上浮**（`FR-NOTE-18` 的第二档）：默认档（最近更新）里收藏的两条排在前面，
    /// 收藏区内部仍按更新时间倒序；未收藏的相对次序一字不变。
    func testFavoriteNotesFloatToTheTopOfTheDefaultOrder() {
        let sut = makeFavoritesSUT()
        let ordered = sut.navigation.listing(sut.notes, scope: .all, sort: .updatedDesc)
        XCTAssertEqual(ordered.map(\.title), ["收藏·别的架", "收藏·较旧", "普通·最新", "普通·最旧"])
        XCTAssertTrue(ordered[0].isFavorite && ordered[1].isFavorite, "前两条 = 收藏那一区")
        XCTAssertGreaterThan(ordered[0].updatedAt, ordered[1].updatedAt, "收藏区内部仍按更新时间倒序")
        XCTAssertFalse(ordered[2].isFavorite || ordered[3].isFavorite, "未收藏的相对次序一字不变（最新仍在最前）")
        // **别的档不吃这一口**：用户显式选了「标题」就按标题排（收藏只影响默认档这一条已登记的规则）
        let byTitle = sut.navigation.listing(sut.notes, scope: .all, sort: .titleAsc)
        XCTAssertEqual(byTitle.map(\.title), byTitle.map(\.title).sorted(), "标题档就是标题序")
    }

    /// 在「已收藏」里新建笔记 ⇒ 落**默认笔记本**（收藏不指定任何一格；与标签 / 最近同族）。
    func testCreatingFromFavoritesFallsBackToDefaultContainers() {
        let sut = makeFavoritesSUT()
        XCTAssertEqual(sut.navigation.destinationNotebookUid(for: .favorites), "nb-a1")
        XCTAssertEqual(
            NotebookCreation.destinationShelfUid(for: .favorites, directory: sut.navigation.directory),
            "shelf-a"
        )
    }

    // MARK: - 置顶（队列 `L-184` 第四片）

    /// **置顶上浮**（`FR-NOTE-18` 的**第一档**）：置顶的那一条排在**收藏区之前** ——
    /// 三档是**同一次比较的三个关键字**（置顶 → 收藏 → 更新时间倒序），不是三段各自排序。
    func testPinnedNotesFloatAboveFavoritesInTheDefaultOrder() {
        let sut = makeFavoritesSUT()
        // 把时间**最旧**的那一条（「收藏·较旧」）置顶 ⇒ 它必须排到最前，且压过另一条收藏。
        var notes = sut.notes
        notes[1].isPinned = true
        let ordered = sut.navigation.listing(notes, scope: .all, sort: .updatedDesc)
        XCTAssertEqual(ordered.map(\.title), ["收藏·较旧", "收藏·别的架", "普通·最新", "普通·最旧"])
        XCTAssertTrue(ordered[0].isPinned, "第一条就是置顶那条（时间最旧也照样第一）")
        XCTAssertFalse(ordered[1].isPinned, "置顶区只有那一条")

        // **两条都置顶**时：置顶区内部**照旧按收藏 → 时间**（三个关键字是同一次比较）
        var both = notes
        both[2].isPinned = true   // 「收藏·别的架」也置顶
        let two = sut.navigation.listing(both, scope: .all, sort: .updatedDesc)
        XCTAssertEqual(two.prefix(2).map(\.title), ["收藏·别的架", "收藏·较旧"],
                       "都是置顶 ⇒ 看第二关键字（收藏）与第三关键字（时间）")
        XCTAssertTrue(two.prefix(2).allSatisfy(\.isPinned))

        // **别的档不吃这一口**：用户显式选了「标题」就按标题排（与收藏同一条登记）。
        let byTitle = sut.navigation.listing(notes, scope: .all, sort: .titleAsc)
        XCTAssertEqual(byTitle.map(\.title), byTitle.map(\.title).sorted(), "标题档就是标题序")
    }

    /// 置顶是**排序关键字**，不是第六个容器：它不新造范围、也不改变任何范围里的成员
    /// （契约 §2.1 只给了排序位，没有 `pinnedOnly` —— 与收藏不同，这里刻意不加筛选）。
    func testPinningChangesOrderButNotAnyScopesMembership() {
        let sut = makeFavoritesSUT()
        var notes = sut.notes
        notes[0].isPinned = true
        XCTAssertEqual(sut.navigation.filter(notes, scope: .all).count, 4)
        XCTAssertEqual(sut.navigation.filter(notes, scope: .favorites).count,
                       sut.navigation.favoriteCount(in: notes))
        XCTAssertEqual(sut.navigation.favoriteCount(in: notes), 2, "置顶不改变收藏那一条判断")
        XCTAssertEqual(sut.navigation.listing(notes, scope: .all, sort: .updatedDesc).count, 4)
    }

    // MARK: - 接线（源码判据）

    /// 视图与 `AppState` 必须**真的用**这套导航 —— 纯逻辑写好了却没人调用，是这一族最典型的假绿
    /// （判据全绿、界面上一处都没接）。判法 = 在源码里钉住三个锚点（剥注释后再判）。
    func testHostWiringUsesTheNavigationInsteadOfItsOwnFiltering() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let appState = Self.stripComments(try! String(contentsOf: root.appendingPathComponent("App/AppState.swift"), encoding: .utf8))
        let panel = Self.stripComments(try! String(contentsOf: root.appendingPathComponent("App/Views/NotesPanel.swift"), encoding: .utf8))

        XCTAssertTrue(appState.contains("notesNavigation"), "AppState 要持有这份导航")
        XCTAssertTrue(appState.contains("notesScope"), "AppState 要持有选中态")
        XCTAssertTrue(appState.contains("selectNotesScope"), "选中的唯一入口")
        XCTAssertTrue(appState.contains("notesSearchScope"), "搜索范围那枚开关要在状态层")
        // 队列 `L-184` 第二片：排序的当前值在状态层，列表只许走 Core 那一个入口
        XCTAssertTrue(appState.contains("notesSortOrder"), "排序条当前选的那一档要在状态层")
        XCTAssertTrue(appState.contains("notesNavigation.listing("), "中栏列表走 Core 的 `listing`（过滤 + 排序一处）")
        XCTAssertFalse(
            appState.contains("mostRecentlyUpdatedFirst"),
            "排序口径搬进 Core 之后，宿主层不许再自己排一遍（两处各排一次必分家）"
        )
        XCTAssertTrue(panel.contains("NotesContainerTreeView"), "侧栏要有两级导航那一块")
        XCTAssertTrue(panel.contains("notesSearchScope"), "搜索范围开关要真的接在界面上")
        XCTAssertTrue(panel.contains("notesSortOrder"), "排序条要真的接在界面上")
        XCTAssertTrue(panel.contains("notes-scope-recent"), "左栏要有「最近」那一行")
        XCTAssertTrue(panel.contains("notes-scope-tag-"), "左栏要有标签分组（一行一个标签）")
        XCTAssertTrue(panel.contains("notesTagsSection"), "标签那一栏的标题来自语言表（不写死中文）")
        // 队列 `L-184` 第三片：左栏那一行 + 中栏那枚开关，且**开关不另立第二个状态**
        XCTAssertTrue(panel.contains("notes-scope-favorites"), "左栏要有「已收藏」那一行")
        XCTAssertTrue(panel.contains("notes-favorite-filter"), "中栏要有「只看收藏」筛选开关")
        XCTAssertTrue(appState.contains("notesFavoriteOnly"), "开关的当前值由宿主一处给（左栏那一行共用它）")
        XCTAssertTrue(appState.contains("setNotesFavoriteOnly"), "开关只有一个入口")
        XCTAssertTrue(appState.contains("toggleNoteFavorite"), "收藏的写库入口只此一处")
        // 队列 `L-184` 第四片：置顶（契约 §2.1 的**第一关键字**）也要有界面入口与唯一写库口
        XCTAssertTrue(panel.contains("notes-pinned-toggle-"), "行右键要有「置顶 / 取消置顶」")
        XCTAssertTrue(panel.contains("pin.fill"), "置顶过的行上要看得见图钉（与收藏的星分开）")
        XCTAssertTrue(appState.contains("toggleNotePinned"), "置顶的写库入口只此一处")
        XCTAssertFalse(
            appState.contains("@Published var notesFavoriteOnly"),
            "开关不许另立第二个状态 —— 两处各存一份必然出现「开关开着、列表在看全部」"
        )
        XCTAssertFalse(
            appState.contains("notes.filter { $0.notebookUid"),
            "按笔记本筛笔记只许经 NotesNavigation —— 不许在宿主层自己写一套过滤"
        )
    }

    /// 剥注释（`//` 与 `///` 行、`/* */` 块）—— 注释里写着标识名不算接线
    /// （第 162 轮那条「判据对标识是文本级对账，写在本文件里会当场报红」的同一个坑，反向用一次）。
    private static func stripComments(_ source: String) -> String {
        var output: [String] = []
        var inBlock = false
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inBlock {
                if trimmed.contains("*/") { inBlock = false }
                continue
            }
            if trimmed.hasPrefix("/*") {
                inBlock = !trimmed.contains("*/")
                continue
            }
            if trimmed.hasPrefix("//") { continue }
            output.append(String(line))
        }
        return output.joined(separator: "\n")
    }
}
