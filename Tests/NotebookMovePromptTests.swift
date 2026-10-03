import XCTest
@testable import DoyahCore

/// **跨笔记本移动的判据** —— 队列 `L-97` 界面半第三片（④ 跨笔记本移动）。
///
/// 契约出处 = `DoyahNotes/Docs/核心契约.md` §2.12 第 4 条。这一片钉三件事：
///   · **目标清单的顺序与内容**（跟树上一致 + 当前格被标出来）—— 顺序错了用户就得在一堆
///     同名笔记本里猜哪一格是自己现在待的；
///   · **当前格不给选**：移到自己所在的那一格是「什么都没发生」，与其点了没反应，
///     不如那一项不给选（`L-50` 的口径）；
///   · **「一个可去的地方都没有」要被认出来**（库里只有一个笔记本）—— 否则界面给一个空菜单。
///
/// 末例是**接线判据**：规则写好了却没人调用，是这一族最典型的假绿。
final class NotebookMovePromptTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 夹具：两个架 / 三个笔记本

    /// 架A（默认）→ 笔记本A1（默认）；架B → 笔记本B1（非默认）、笔记本B2（非默认）。
    private func makeDirectory() -> NotebookDirectory {
        let shelfA = Shelf(uid: "shelf-a", name: "架A", sortOrder: 0, createdAt: t0, isDefault: true)
        let shelfB = Shelf(uid: "shelf-b", name: "架B", sortOrder: 1, createdAt: t0, isDefault: false)
        let a1 = Notebook(uid: "nb-a1", shelfUid: "shelf-a", name: "笔记本A1", sortOrder: 0, createdAt: t0, isDefault: true)
        let b1 = Notebook(uid: "nb-b1", shelfUid: "shelf-b", name: "笔记本B1", sortOrder: 0, createdAt: t0, isDefault: false)
        let b2 = Notebook(uid: "nb-b2", shelfUid: "shelf-b", name: "笔记本B2", sortOrder: 1, createdAt: t0, isDefault: false)
        return NotebookDirectory(shelves: [shelfA, shelfB], notebooks: [a1, b1, b2])
    }

    private func targets(noteIDs: [UUID], placements: [NotebookPlacement] = []) -> [NotebookMoveTarget] {
        NotebookMovePrompt.targets(directory: makeDirectory(), placements: placements, noteIDs: noteIDs)
    }

    // MARK: - 目标清单

    func testTargetsFollowTreeOrderAndMarkTheCurrentNotebook() {
        let n1 = UUID()
        let list = targets(
            noteIDs: [n1],
            placements: [NotebookPlacement(noteID: n1.uuidString, notebookUid: "nb-b1")]
        )
        XCTAssertEqual(list.map(\.id), ["nb-a1", "nb-b1", "nb-b2"], "顺序 = 树上看到的顺序（架A → 架B）")
        XCTAssertEqual(list.map(\.shelfName), ["架A", "架B", "架B"], "目标要带着架名（菜单按架分组）")
        XCTAssertEqual(list.filter(\.isCurrent).map(\.id), ["nb-b1"], "当前那一格要被标出来")
        XCTAssertEqual(list.filter(\.isSelectable).map(\.id), ["nb-a1", "nb-b2"], "当前格不给选")
    }

    func testABatchSpanningTwoNotebooksMarksNoCurrentNotebook() {
        let n1 = UUID()
        let n2 = UUID()
        let list = targets(
            noteIDs: [n1, n2],
            placements: [
                NotebookPlacement(noteID: n1.uuidString, notebookUid: "nb-b1"),
                NotebookPlacement(noteID: n2.uuidString, notebookUid: "nb-b2"),
            ]
        )
        XCTAssertFalse(list.contains(where: \.isCurrent), "跨格批量没有单一「当前」格 ⇒ 一个都不标")
        XCTAssertTrue(list.allSatisfy(\.isSelectable), "每一格都是可去的（含它们各自在的那两格）")
    }

    func testNoteWithoutPlacementIsTreatedAsDefaultNotebook() {
        // 缺归属行的笔记按默认笔记本处置（契约 §2.12 第 2 条）—— 与树上的兜底同一条路。
        let list = targets(noteIDs: [UUID()])
        XCTAssertEqual(list.filter(\.isCurrent).map(\.id), ["nb-a1"], "认不出归属 ⇒ 当前格是默认笔记本")
    }

    func testSingleNotebookLibraryHasNowhereToGo() {
        let shelf = Shelf(uid: "s", name: "架", sortOrder: 0, createdAt: t0, isDefault: true)
        let only = Notebook(uid: "n", shelfUid: "s", name: "笔记本", sortOrder: 0, createdAt: t0, isDefault: true)
        let list = NotebookMovePrompt.targets(
            directory: NotebookDirectory(shelves: [shelf], notebooks: [only]),
            placements: [],
            noteIDs: [UUID()]
        )
        XCTAssertEqual(list.count, 1, "清单里还是那一格（照实画「你现在在这儿」）")
        XCTAssertFalse(NotebookMovePrompt.hasDestination(list), "只有一个笔记本 ⇒ 没地方可去 —— 界面给那句话，不是空菜单")
    }

    // MARK: - 接线（源码判据）

    /// 视图与 `AppState` 必须**真的用**这套规则：判据全绿、界面上一个菜单项都没接，是这一族最典型的假绿。
    /// 判法 = 在源码里钉锚点（剥注释后再判 —— 注释里写着标识名不算接线）。
    func testHostWiringUsesThePromptInsteadOfHardWiringTargets() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let appState = Self.stripComments(try! String(contentsOf: root.appendingPathComponent("App/AppState.swift"), encoding: .utf8))
        let panel = Self.stripComments(try! String(contentsOf: root.appendingPathComponent("App/Views/NotesPanel.swift"), encoding: .utf8))

        XCTAssertTrue(appState.contains("func noteMoveTargets("), "目标清单由 AppState 一处给（视图不自己拼）")
        XCTAssertTrue(appState.contains("func moveNotes("), "移动走这一个入口")
        XCTAssertTrue(appState.contains(".move(noteIDs:"), "落库走 `NoteLibrary.move`（不刷新 updatedAt 的那一条）")
        XCTAssertTrue(appState.contains("await reloadNotes()"), "移完要重读库（树 / 条数 / 范围归一会跟着变）")

        XCTAssertTrue(panel.contains("NotebookMovePrompt"), "目标清单与文案键由模型给")
        XCTAssertTrue(panel.contains("appState.noteMoveTargets(for:"), "菜单要真的问 AppState 要清单")
        XCTAssertTrue(panel.contains("appState.moveNotes("), "选中目标要真的接上入口")
        XCTAssertTrue(panel.contains(".disabled(!target.isSelectable)"), "不可选的那一项要真的灰着（不是点了没反应）")
        // 反向断言：视图里不许自己写那句人话（写死一次就会与 Core 的判断分家）。
        XCTAssertFalse(panel.contains("没有别的地方"), "句子只许在语言表里")
    }

    /// 剥注释（`//` 与 `///` 行、`/* */` 块）—— 与 `NoteNavigationTests` 同一份实现（同一课）。
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
