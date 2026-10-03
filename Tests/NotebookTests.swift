import XCTest
@testable import DoyahCore

/// **两层归属（笔记本架 → 笔记本 → 笔记）的 Core 判据** —— 队列 `L-97` 第一片（Core 半）。
///
/// 契约出处 = `DoyahNotes/Docs/核心契约.md` §2.12（§2.11 是身份口径）。这里逐条钉住的是
/// **口径**，不是「实现长什么样」：默认容器、旧数据兜底、删除处置的默认档、跨笔记本移动、
/// 范围过滤不靠索引。每一条错都很安静（笔记「突然不见了」/「被删了」），所以逐条写死。
final class NotebookTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 默认容器

    func testBootstrapCreatesOneDefaultShelfAndOneDefaultNotebook() {
        let directory = NotebookDirectory.bootstrap(shelfName: "默认架", notebookName: "默认笔记本", now: t0)
        XCTAssertEqual(directory.shelves.count, 1)
        XCTAssertEqual(directory.notebooks.count, 1)
        let shelf = try? XCTUnwrap(directory.defaultShelf)
        let notebook = try? XCTUnwrap(directory.defaultNotebook)
        XCTAssertEqual(shelf?.isDefault, true)
        XCTAssertEqual(notebook?.isDefault, true)
        XCTAssertEqual(notebook?.shelfUid, shelf?.uid, "默认笔记本必须挂在默认架下 —— 不存在无归属的笔记本")
        XCTAssertNotEqual(shelf?.uid, notebook?.uid, "架与笔记本各有各的 uid")
    }

    func testNormalizeIsIdempotentOnAHealthyDirectory() {
        let directory = NotebookDirectory.bootstrap(shelfName: "默认架", notebookName: "默认笔记本", now: t0)
        XCTAssertEqual(directory.normalized(shelfName: "默认架", notebookName: "默认笔记本", now: t0), directory)
    }

    func testNormalizeAddsMissingDefaultNotebookAndHangsItOnTheDefaultShelf() {
        let shelf = Shelf(name: "个人", sortOrder: 3, createdAt: t0, isDefault: true)
        let directory = NotebookDirectory(shelves: [shelf], notebooks: []).normalized(shelfName: "默认架", notebookName: "默认笔记本", now: t0)
        XCTAssertEqual(directory.notebooks.count, 1)
        XCTAssertEqual(directory.defaultNotebook?.shelfUid, shelf.uid)
        XCTAssertEqual(directory.defaultNotebook?.isDefault, true)
    }

    func testNormalizeKeepsAnExistingDefaultNotebookAsIs() {
        let shelf = Shelf(name: "个人", createdAt: t0, isDefault: true)
        let mine = Notebook(uid: "nb-mine", shelfUid: shelf.uid, name: "工作", createdAt: t0, isDefault: true)
        let directory = NotebookDirectory(shelves: [shelf], notebooks: [mine]).normalized(shelfName: "默认架", notebookName: "默认笔记本", now: t0)
        XCTAssertEqual(directory.defaultNotebook?.uid, "nb-mine", "已经有默认笔记本就不许再塞一个")
        XCTAssertEqual(directory.notebooks.count, 1)
    }

    // MARK: - 归属兜底（旧数据 / 旧备份）

    func testResolvedNotebookUidFallsBackForMissingOrUnknownValues() {
        let directory = NotebookDirectory.bootstrap(shelfName: "默认架", notebookName: "默认笔记本", now: t0)
        let fallback = directory.defaultNotebook?.uid
        XCTAssertEqual(directory.resolvedNotebookUid(nil), fallback)
        XCTAssertEqual(directory.resolvedNotebookUid(""), fallback)
        XCTAssertEqual(directory.resolvedNotebookUid("nb-已删掉的"), fallback, "认不出的归属一律落默认笔记本，不丢条目")
    }

    func testResolvedNotebookUidKeepsAKnownValue() {
        let shelf = Shelf(uid: "sh-1", name: "架", createdAt: t0, isDefault: true)
        let known = Notebook(uid: "nb-1", shelfUid: "sh-1", name: "工作", createdAt: t0)
        let directory = NotebookDirectory(shelves: [shelf], notebooks: [known])
        XCTAssertEqual(directory.resolvedNotebookUid("nb-1"), "nb-1")
    }

    func testResolvedShelfUidFallsBackToTheDefaultShelf() {
        let directory = NotebookDirectory.bootstrap(shelfName: "默认架", notebookName: "默认笔记本", now: t0)
        let fallback = directory.defaultShelf?.uid
        XCTAssertEqual(directory.resolvedShelfUid(nil), fallback)
        XCTAssertEqual(directory.resolvedShelfUid("sh-不存在"), fallback)
    }

    // MARK: - 列表与排序

    func testNotebooksInShelfOnlyReturnsThatShelfAndSortsStably() {
        let a = Shelf(uid: "sh-a", name: "A", createdAt: t0, isDefault: true)
        let b = Shelf(uid: "sh-b", name: "B", sortOrder: 1, createdAt: t0)
        let n1 = Notebook(uid: "nb-1", shelfUid: "sh-a", name: "一", sortOrder: 1, createdAt: t0)
        let n2 = Notebook(uid: "nb-2", shelfUid: "sh-a", name: "二", sortOrder: 0, createdAt: t0)
        let n3 = Notebook(uid: "nb-3", shelfUid: "sh-b", name: "三", sortOrder: 0, createdAt: t0)
        let directory = NotebookDirectory(shelves: [a, b], notebooks: [n1, n2, n3])
        XCTAssertEqual(directory.notebooks(inShelf: "sh-a").map(\.uid), ["nb-2", "nb-1"])
        XCTAssertEqual(directory.notebooks(inShelf: "sh-b").map(\.uid), ["nb-3"])
    }

    func testSortingFallsBackToCreatedAtThenUidWhenSortOrdersTie() {
        let a = Shelf(uid: "sh", name: "架", createdAt: t0, isDefault: true)
        let early = Notebook(uid: "nb-z", shelfUid: "sh", name: "早", sortOrder: 0, createdAt: t0)
        let late = Notebook(uid: "nb-a", shelfUid: "sh", name: "晚", sortOrder: 0, createdAt: t0.addingTimeInterval(60))
        let directory = NotebookDirectory(shelves: [a], notebooks: [late, early])
        XCTAssertEqual(directory.notebooks(inShelf: "sh").map(\.uid), ["nb-z", "nb-a"], "排序位相同时看创建时刻，不看 uid 的字母序")
    }

    func testNextSortOrderCountsWithinTheShelfNotGlobally() {
        let a = Shelf(uid: "sh-a", name: "A", createdAt: t0, isDefault: true)
        let b = Shelf(uid: "sh-b", name: "B", sortOrder: 1, createdAt: t0)
        let directory = NotebookDirectory(
            shelves: [a, b],
            notebooks: [
                Notebook(uid: "nb-1", shelfUid: "sh-a", name: "一", createdAt: t0),
                Notebook(uid: "nb-2", shelfUid: "sh-b", name: "二", createdAt: t0),
                Notebook(uid: "nb-3", shelfUid: "sh-b", name: "三", sortOrder: 1, createdAt: t0)
            ]
        )
        XCTAssertEqual(directory.nextSortOrder(inShelf: "sh-a"), 1)
        XCTAssertEqual(directory.nextSortOrder(inShelf: "sh-b"), 2)
    }

    // MARK: - 范围过滤

    func testScopeFilterPutsUnassignedNotesInTheDefaultNotebook() {
        let directory = NotebookDirectory.bootstrap(shelfName: "默认架", notebookName: "默认笔记本", now: t0)
        let fallback = directory.defaultNotebook!.uid
        let placements = [
            NotebookPlacement(noteID: "n1", notebookUid: nil),
            NotebookPlacement(noteID: "n2", notebookUid: ""),
            NotebookPlacement(noteID: "n3", notebookUid: "nb-已删掉"),
            NotebookPlacement(noteID: "n4", notebookUid: fallback)
        ]
        XCTAssertEqual(directory.notes(placements, inNotebook: fallback).map(\.noteID), ["n1", "n2", "n3", "n4"])
    }

    func testScopeFilterRecomputesOwnershipInsteadOfTrustingTheCallersGrouping() {
        let shelf = Shelf(uid: "sh", name: "架", createdAt: t0, isDefault: true)
        let mine = Notebook(uid: "nb-mine", shelfUid: "sh", name: "我的", createdAt: t0, isDefault: true)
        let other = Notebook(uid: "nb-other", shelfUid: "sh", name: "别的", sortOrder: 1, createdAt: t0)
        let directory = NotebookDirectory(shelves: [shelf], notebooks: [mine, other])
        let placements = [
            NotebookPlacement(noteID: "n1", notebookUid: "nb-other"),
            NotebookPlacement(noteID: "n2", notebookUid: "nb-mine")
        ]
        XCTAssertEqual(directory.notes(placements, inNotebook: "nb-mine").map(\.noteID), ["n2"])
        XCTAssertEqual(directory.notes(placements, inNotebook: "nb-other").map(\.noteID), ["n1"])
    }

    func testScopeFilterByShelfSpansEveryNotebookInThatShelf() {
        let a = Shelf(uid: "sh-a", name: "A", createdAt: t0, isDefault: true)
        let b = Shelf(uid: "sh-b", name: "B", sortOrder: 1, createdAt: t0)
        let directory = NotebookDirectory(
            shelves: [a, b],
            notebooks: [
                Notebook(uid: "nb-1", shelfUid: "sh-a", name: "一", createdAt: t0),
                Notebook(uid: "nb-2", shelfUid: "sh-a", name: "二", sortOrder: 1, createdAt: t0),
                Notebook(uid: "nb-3", shelfUid: "sh-b", name: "三", createdAt: t0, isDefault: true)
            ]
        )
        let placements = [
            NotebookPlacement(noteID: "n1", notebookUid: "nb-1"),
            NotebookPlacement(noteID: "n2", notebookUid: "nb-2"),
            NotebookPlacement(noteID: "n3", notebookUid: "nb-3"),
            NotebookPlacement(noteID: "n4", notebookUid: nil)
        ]
        XCTAssertEqual(directory.notes(placements, inShelf: "sh-a").map(\.noteID), ["n1", "n2"])
        XCTAssertEqual(directory.notes(placements, inShelf: "sh-b").map(\.noteID), ["n3", "n4"], "缺归属的笔记算在默认笔记本里（默认笔记本在 B 架）")
    }

    // MARK: - 跨笔记本移动

    func testMoveChangesOnlyTheListedNotes() {
        let shelf = Shelf(uid: "sh", name: "架", createdAt: t0, isDefault: true)
        let mine = Notebook(uid: "nb-mine", shelfUid: "sh", name: "我的", createdAt: t0, isDefault: true)
        let other = Notebook(uid: "nb-other", shelfUid: "sh", name: "别处", sortOrder: 1, createdAt: t0)
        let directory = NotebookDirectory(shelves: [shelf], notebooks: [mine, other])
        let placements = [
            NotebookPlacement(noteID: "n1", notebookUid: "nb-mine"),
            NotebookPlacement(noteID: "n2", notebookUid: "nb-mine")
        ]
        let moved = directory.move(placements, noteIDs: ["n1"], toNotebook: "nb-other")
        XCTAssertEqual(moved[0], NotebookPlacement(noteID: "n1", notebookUid: "nb-other"))
        XCTAssertEqual(moved[1], placements[1], "没点名的笔记一字不动")
    }

    func testMoveToAnUnknownTargetLandsInTheDefaultNotebook() {
        let directory = NotebookDirectory.bootstrap(shelfName: "默认架", notebookName: "默认笔记本", now: t0)
        let fallback = directory.defaultNotebook!.uid
        let placements = [NotebookPlacement(noteID: "n1", notebookUid: "nb-别的")]
        let moved = directory.move(placements, noteIDs: ["n1"], toNotebook: "nb-已删掉")
        XCTAssertEqual(moved.first?.notebookUid, fallback)
    }

    // MARK: - 删除处置

    func testDefaultRemovalPolicyIsMoveToDefault() {
        XCTAssertEqual(ContainerRemovalPolicy.default, .moveToDefault)
    }

    func testRemovingANotebookDefaultsToMovingItsNotesIntoTheDefaultNotebook() {
        let shelf = Shelf(uid: "sh", name: "架", createdAt: t0, isDefault: true)
        let mine = Notebook(uid: "nb-mine", shelfUid: "sh", name: "我的", createdAt: t0, isDefault: true)
        let target = Notebook(uid: "nb-t", shelfUid: "sh", name: "临时", sortOrder: 1, createdAt: t0)
        let directory = NotebookDirectory(shelves: [shelf], notebooks: [mine, target])
        let placements = [
            NotebookPlacement(noteID: "n1", notebookUid: "nb-t"),
            NotebookPlacement(noteID: "n2", notebookUid: "nb-mine")
        ]
        let plan = directory.removalPlan(forNotebook: "nb-t", placements: placements)
        XCTAssertEqual(plan?.removedContainerUid, "nb-t")
        XCTAssertEqual(plan?.policy, .moveToDefault)
        XCTAssertEqual(plan?.targetContainerUid, "nb-mine")
        XCTAssertEqual(plan?.movedNoteIDs, ["n1"])
        XCTAssertEqual(plan?.deletedNoteIDs, [], "默认档不删笔记")
        XCTAssertEqual(plan?.affectedNoteCount, 1, "确认框要写的「将影响多少条笔记」")
    }

    func testRemovingANotebookCanDeleteItsNotesWhenAsked() {
        let shelf = Shelf(uid: "sh", name: "架", createdAt: t0, isDefault: true)
        let target = Notebook(uid: "nb-t", shelfUid: "sh", name: "临时", createdAt: t0)
        let directory = NotebookDirectory(shelves: [shelf], notebooks: [target])
        let placements = [NotebookPlacement(noteID: "n1", notebookUid: "nb-t")]
        let plan = directory.removalPlan(forNotebook: "nb-t", policy: .deleteTogether, placements: placements)
        XCTAssertEqual(plan?.deletedNoteIDs, ["n1"])
        XCTAssertEqual(plan?.movedNoteIDs, [])
        XCTAssertEqual(plan?.targetContainerUid, nil)
    }

    func testTheDefaultNotebookCannotBeRemoved() {
        let directory = NotebookDirectory.bootstrap(shelfName: "默认架", notebookName: "默认笔记本", now: t0)
        let uid = directory.defaultNotebook!.uid
        XCTAssertNil(directory.removalPlan(forNotebook: uid, placements: []))
        XCTAssertNil(directory.removalPlan(forNotebook: "nb-没这条", placements: []))
    }

    func testTheDefaultShelfCannotBeRemoved() {
        let directory = NotebookDirectory.bootstrap(shelfName: "默认架", notebookName: "默认笔记本", now: t0)
        let uid = directory.defaultShelf!.uid
        XCTAssertNil(directory.removalPlan(forShelf: uid, placements: []))
        XCTAssertNil(directory.removalPlan(forShelf: "sh-没这条", placements: []))
    }

    func testRemovingAShelfDefaultsToMovingNotebooksToTheDefaultShelfAndKeepingTheirNotes() {
        let a = Shelf(uid: "sh-a", name: "默认", createdAt: t0, isDefault: true)
        let b = Shelf(uid: "sh-b", name: "旧架", sortOrder: 1, createdAt: t0)
        let directory = NotebookDirectory(
            shelves: [a, b],
            notebooks: [
                Notebook(uid: "nb-1", shelfUid: "sh-a", name: "默认笔记本", createdAt: t0, isDefault: true),
                Notebook(uid: "nb-2", shelfUid: "sh-b", name: "旧笔记本", createdAt: t0)
            ]
        )
        let placements = [
            NotebookPlacement(noteID: "n1", notebookUid: "nb-2"),
            NotebookPlacement(noteID: "n2", notebookUid: "nb-1")
        ]
        let plan = directory.removalPlan(forShelf: "sh-b", placements: placements)
        XCTAssertEqual(plan?.policy, .moveToDefault)
        XCTAssertEqual(plan?.targetContainerUid, "sh-a")
        XCTAssertEqual(plan?.deletedNoteIDs, [])
        XCTAssertEqual(plan?.movedNoteIDs, [], "整架搬走的是笔记本，笔记一条都不动")
    }

    func testDeletingAShelfTogetherKeepsTheUnremovableDefaultNotebook() {
        let a = Shelf(uid: "sh-a", name: "默认", createdAt: t0, isDefault: true)
        let b = Shelf(uid: "sh-b", name: "旧架", sortOrder: 1, createdAt: t0)
        let directory = NotebookDirectory(
            shelves: [a, b],
            notebooks: [
                Notebook(uid: "nb-default", shelfUid: "sh-b", name: "默认笔记本", createdAt: t0, isDefault: true),
                Notebook(uid: "nb-x", shelfUid: "sh-b", name: "一起删", sortOrder: 1, createdAt: t0)
            ]
        )
        let placements = [
            NotebookPlacement(noteID: "n1", notebookUid: "nb-x"),
            NotebookPlacement(noteID: "n2", notebookUid: "nb-default")
        ]
        let plan = directory.removalPlan(forShelf: "sh-b", policy: .deleteTogether, placements: placements)
        XCTAssertEqual(plan?.removedNotebookUids, ["nb-x"])
        XCTAssertEqual(plan?.movedNotebookUids, ["nb-default"], "默认笔记本不可删 ⇒ 改挂默认架")
        XCTAssertEqual(plan?.deletedNoteIDs, ["n1"], "默认笔记本里的笔记不跟着删")
        XCTAssertEqual(plan?.targetContainerUid, "sh-a")
    }

    func testMovedNotebooksContinueTheSortOrderOfTheDestinationShelf() {
        let a = Shelf(uid: "sh-a", name: "默认", createdAt: t0, isDefault: true)
        let b = Shelf(uid: "sh-b", name: "旧架", sortOrder: 1, createdAt: t0)
        let directory = NotebookDirectory(
            shelves: [a, b],
            notebooks: [
                Notebook(uid: "nb-1", shelfUid: "sh-a", name: "一", createdAt: t0, isDefault: true),
                Notebook(uid: "nb-2", shelfUid: "sh-b", name: "二", createdAt: t0),
                Notebook(uid: "nb-3", shelfUid: "sh-b", name: "三", sortOrder: 1, createdAt: t0)
            ]
        )
        let moved = directory.notebooksMovedToDefaultShelf(fromShelf: "sh-b")
        XCTAssertEqual(moved.map(\.uid), ["nb-2", "nb-3"])
        XCTAssertEqual(moved.map(\.shelfUid), ["sh-a", "sh-a"])
        XCTAssertEqual(moved.map(\.sortOrder), [1, 2], "接在默认架现有条数之后，不重号")
        XCTAssertTrue(directory.notebooksMovedToDefaultShelf(fromShelf: "sh-a").isEmpty, "默认架不参与")
    }

    // MARK: - 身份（契约 §2.11）

    func testRenamingKeepsTheUidSoTheIdentitySurvivesACodableRoundTrip() throws {
        let shelf = Shelf(uid: "sh-1", name: "旧名", createdAt: t0, isDefault: true)
        var renamed = shelf
        renamed.name = "新名"
        let data = try JSONEncoder().encode(renamed)
        let decoded = try JSONDecoder().decode(Shelf.self, from: data)
        XCTAssertEqual(decoded.uid, "sh-1", "改名不换身份 —— uid 是跨端稳定身份，不是标题的函数")
        XCTAssertEqual(decoded.name, "新名")
    }

    func testNotebookNeverHasAnEmptyShelfUidByConstruction() {
        let notebook = Notebook(shelfUid: "sh-1", name: "工作")
        XCTAssertFalse(notebook.shelfUid.isEmpty, "笔记本必有归属（构造器也不给「不传架」这条路）")
    }
    func testDefaultContainerNamesComeFromTheCallerSoCoreHoldsNoUserFacingCopy() {
        let directory = NotebookDirectory.bootstrap(shelfName: "工作", notebookName: "我的笔记", now: t0)
        XCTAssertEqual(directory.defaultShelf?.name, "工作")
        XCTAssertEqual(directory.defaultNotebook?.name, "我的笔记")
        let patched = NotebookDirectory(shelves: [], notebooks: []).normalized(shelfName: "工作", notebookName: "日记", now: t0)
        XCTAssertEqual(patched.defaultShelf?.name, "工作")
        XCTAssertEqual(patched.defaultNotebook?.name, "日记")
    }
}
