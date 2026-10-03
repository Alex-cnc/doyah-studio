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
    private func makeSUT() -> (navigation: NotesNavigation, notes: [Note], ids: [String: UUID]) {
        let shelfA = Shelf(uid: "shelf-a", name: "架A", sortOrder: 0, createdAt: t0, isDefault: true)
        let shelfB = Shelf(uid: "shelf-b", name: "架B", sortOrder: 1, createdAt: t0, isDefault: false)
        let a1 = Notebook(uid: "nb-a1", shelfUid: shelfA.uid, name: "笔记本A1", sortOrder: 0, createdAt: t0, isDefault: true)
        let a2 = Notebook(uid: "nb-a2", shelfUid: shelfA.uid, name: "笔记本A2", sortOrder: 1, createdAt: t0, isDefault: false)
        let b1 = Notebook(uid: "nb-b1", shelfUid: shelfB.uid, name: "笔记本B1", sortOrder: 0, createdAt: t0, isDefault: false)
        let directory = NotebookDirectory(shelves: [shelfB, shelfA], notebooks: [a2, b1, a1])

        let n1 = Note(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "n1")
        let n2 = Note(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "n2")
        let n3 = Note(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, title: "n3")
        let n4 = Note(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, title: "n4")
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
        for scope in [NotesScope.all, .shelf(uid: "shelf-a"), .notebook(uid: "nb-a1"), .notebook(uid: "nb-a2")] {
            let rows = sut.navigation.filter(notes, scope: scope).count
            let counted: Int
            switch scope {
            case .all: counted = notes.count
            case .shelf(let uid): counted = sut.navigation.noteCount(inShelf: uid, notes: notes)
            case .notebook(let uid): counted = sut.navigation.noteCount(inNotebook: uid, notes: notes)
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
        let sut = makeSUT().navigation
        XCTAssertEqual(sut.normalized(.all), .all)
        XCTAssertEqual(sut.normalized(.notebook(uid: "nb-a2")), .notebook(uid: "nb-a2"))
        XCTAssertEqual(sut.normalized(.shelf(uid: "shelf-b")), .shelf(uid: "shelf-b"))
        // 容器被删掉之后：**回落全部**，不是显示空列表
        XCTAssertEqual(sut.normalized(.notebook(uid: "已经删了的笔记本")), .all)
        XCTAssertEqual(sut.normalized(.shelf(uid: "已经删了的架")), .all)
        XCTAssertEqual(sut.normalized(.notebook(uid: "")), .all)
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
        let unowned = sut.ids["n4"]!.uuidString
        XCTAssertTrue(sut.navigation.contains(.notebook(uid: "nb-a1"), noteID: unowned))
        XCTAssertTrue(sut.navigation.contains(.shelf(uid: "shelf-a"), noteID: unowned))
        XCTAssertFalse(sut.navigation.contains(.notebook(uid: "nb-b1"), noteID: unowned))
        XCTAssertTrue(sut.navigation.contains(.all, noteID: unowned))
    }

    // MARK: - 新建笔记的落点

    func testDestinationNotebookIsTheSelectedOneOtherwiseTheDefault() {
        let sut = makeSUT().navigation
        XCTAssertEqual(sut.destinationNotebookUid(for: .notebook(uid: "nb-a2")), "nb-a2")
        XCTAssertEqual(sut.destinationNotebookUid(for: .all), "nb-a1", "看全部时落默认笔记本")
        XCTAssertEqual(sut.destinationNotebookUid(for: .shelf(uid: "shelf-b")), "nb-a1", "架不指定格子 ⇒ 同样落默认笔记本")
        XCTAssertEqual(sut.destinationNotebookUid(for: .notebook(uid: "删掉的")), "nb-a1")
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
        XCTAssertTrue(panel.contains("NotesContainerTreeView"), "侧栏要有两级导航那一块")
        XCTAssertTrue(panel.contains("notesSearchScope"), "搜索范围开关要真的接在界面上")
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
