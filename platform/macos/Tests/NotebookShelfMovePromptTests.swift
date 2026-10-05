import XCTest
@testable import DoyahCore

/// **跨架移动的判据** —— 队列 `L-97` 界面半第六片（落法 ① 的第四格）。
///
/// 契约出处 = `DoyahNotes/Docs/核心契约.md` §2.12（两层归属：架 → 笔记本；默认容器不可删、可改名）。
/// 这一片钉三件事：
///   · **目标清单的顺序与内容**（跟树上一致 + 当前架被标出来）—— 顺序错了用户就得在一堆架名里
///     猜哪一格是自己现在待的；
///   · **当前架不给选**：挪到自己所在的那个架是「什么都没发生」，与其点了没反应，
///     不如那一项不给选（`L-50` 的口径）；
///   · **落点判定只有一处**（认不出的笔记本 / 认不出的目标架 / 已经在该架 ⇒ 不写库），
///     界面不给点与落库前的守卫是**同一条判断**的两种说法。
///
/// 末例是**接线判据**：规则写好了却没人调用，是这一族最典型的假绿。
final class NotebookShelfMovePromptTests: XCTestCase {

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

    private func targets(_ notebookUid: String, directory: NotebookDirectory? = nil) -> [NotebookShelfMoveTarget] {
        NotebookShelfMovePrompt.targets(notebookUid: notebookUid, directory: directory ?? makeDirectory())
    }

    // MARK: - 目标清单

    func testTargetsFollowTreeOrderAndMarkTheCurrentShelf() {
        let list = targets("nb-b1")
        XCTAssertEqual(list.map(\.id), ["shelf-a", "shelf-b"], "顺序 = 树上看到的顺序（架A → 架B）")
        XCTAssertEqual(list.filter(\.isCurrent).map(\.id), ["shelf-b"], "当前架要被标出来（照实画）")
        XCTAssertEqual(list.filter(\.isSelectable).map(\.id), ["shelf-a"], "当前架不给选")
        XCTAssertEqual(list.map(\.name), ["架A", "架B"], "名字由模型给（视图不自己拼）")
    }

    /// 排序位不是数组次序：喂一份**乱序**的 `shelves` ⇒ 清单仍按排序位来（与树上同一份稳定排序）。
    func testTargetsRespectSortOrderNotArrayOrder() {
        let a = Shelf(uid: "shelf-a", name: "架A", sortOrder: 0, createdAt: t0, isDefault: true)
        let b = Shelf(uid: "shelf-b", name: "架B", sortOrder: 1, createdAt: t0, isDefault: false)
        let c = Shelf(uid: "shelf-c", name: "架C", sortOrder: 2, createdAt: t0, isDefault: false)
        let nb = Notebook(uid: "nb", shelfUid: "shelf-b", name: "本子", sortOrder: 0, createdAt: t0)
        let directory = NotebookDirectory(shelves: [c, a, b], notebooks: [nb])
        XCTAssertEqual(targets("nb", directory: directory).map(\.id), ["shelf-a", "shelf-b", "shelf-c"])
    }

    /// 认不出的笔记本（已删 / uid 拼错）⇒ 空清单：没有「它现在在哪个架」这件事。
    func testUnknownNotebookHasNoTargets() {
        XCTAssertTrue(targets("nb-nope").isEmpty, "认不出的笔记本 ⇒ 没有可去的架（界面给那句话）")
        XCTAssertFalse(NotebookShelfMovePrompt.hasDestination(targets("nb-nope")))
    }

    func testSingleShelfLibraryHasNowhereToGo() {
        let shelf = Shelf(uid: "s", name: "架", sortOrder: 0, createdAt: t0, isDefault: true)
        let only = Notebook(uid: "n", shelfUid: "s", name: "笔记本", sortOrder: 0, createdAt: t0, isDefault: true)
        let directory = NotebookDirectory(shelves: [shelf], notebooks: [only])
        let list = targets("n", directory: directory)
        XCTAssertEqual(list.count, 1, "清单里还是那一个架（照实画「你现在在这儿」）")
        XCTAssertFalse(
            NotebookShelfMovePrompt.hasDestination(list),
            "只有一个架 ⇒ 没地方可去 —— 界面给那句话，不是空菜单"
        )
    }

    // MARK: - 落点判定（唯一出处）

    func testMoveDestinationAcceptsALegalTarget() {
        XCTAssertEqual(
            NotebookShelfMovePrompt.moveDestination(
                notebookUid: "nb-b1", targetShelfUid: "shelf-a", directory: makeDirectory()
            ),
            "shelf-a",
            "挪到别的架 ⇒ 落点就是那个架"
        )
    }

    func testMoveDestinationRefusesTheCurrentShelf() {
        XCTAssertNil(
            NotebookShelfMovePrompt.moveDestination(
                notebookUid: "nb-b1", targetShelfUid: "shelf-b", directory: makeDirectory()
            ),
            "已经在该架 ⇒ 空操作（位置不是内容，白写一次库只是把「点了没反应」挪进库里）"
        )
    }

    func testMoveDestinationRefusesUnknownTargetAndUnknownNotebook() {
        let directory = makeDirectory()
        XCTAssertNil(
            NotebookShelfMovePrompt.moveDestination(
                notebookUid: "nb-b1", targetShelfUid: "shelf-nope", directory: directory
            ),
            "认不出的目标架 ⇒ 不写库（**不兜底到默认架** —— 与 `createNotebook` 同一条口径）"
        )
        XCTAssertNil(
            NotebookShelfMovePrompt.moveDestination(
                notebookUid: "nb-nope", targetShelfUid: "shelf-a", directory: directory
            ),
            "认不出的笔记本 ⇒ 不写库"
        )
    }

    /// 默认笔记本**可以挪架**（契约 §2.12 第 2 条只禁「删」；「可改名」同族 —— 挪架既不是删也不是改名）。
    func testDefaultNotebookMayMoveToAnotherShelf() {
        XCTAssertEqual(
            NotebookShelfMovePrompt.moveDestination(
                notebookUid: "nb-a1", targetShelfUid: "shelf-b", directory: makeDirectory()
            ),
            "shelf-b",
            "默认笔记本挪架不该被拦（只有默认**架**删不掉，挪里面一条笔记本与此无关）"
        )
    }

    // MARK: - 接线（源码判据）

    /// 视图与 `AppState` 必须**真的用**这套规则：判据全绿、界面上一个菜单项都没接，是这一族最典型的假绿。
    /// 判法 = 在源码里钉锚点（剥注释后再判 —— 注释里写着标识名不算接线）。
    func testHostWiringUsesThePromptInsteadOfHardWiringTargets() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let appState = Self.stripComments(
            try! String(contentsOf: root.appendingPathComponent("App/AppState.swift"), encoding: .utf8)
        )
        let panel = Self.stripComments(
            try! String(contentsOf: root.appendingPathComponent("App/Views/NotesPanel.swift"), encoding: .utf8)
        )

        XCTAssertTrue(appState.contains("func notebookShelfMoveTargets("), "清单由 AppState 一处给（视图不自己拼）")
        XCTAssertTrue(appState.contains("NotebookShelfMovePrompt.moveDestination("), "落库前的守卫走 Core 那一处判定")
        XCTAssertTrue(appState.contains(".moveNotebook(uid:"), "落库走 `NoteLibrary.moveNotebook` 门面")
        XCTAssertTrue(appState.contains("await reloadNotes()"), "挪完要重读库（树 / 条数 / 范围归一会跟着变）")

        XCTAssertTrue(panel.contains("NotebookShelfMovePrompt"), "目标清单与文案键由模型给")
        XCTAssertTrue(panel.contains("appState.notebookShelfMoveTargets(for:"), "菜单要真的问 AppState 要清单")
        XCTAssertTrue(panel.contains("appState.moveNotebook("), "选中目标要真的接上入口")
        XCTAssertTrue(panel.contains(".disabled(!target.isSelectable)"), "不可选的那一项要真的灰着（不是点了没反应）")

        // 反向断言：视图里不许写死那两句人话（写死一次就会与语言表分家）。
        XCTAssertFalse(panel.contains("没有别的地方可移"), "句子只许在语言表里")
        XCTAssertFalse(panel.contains("（当前架）"), "后缀只许在语言表里")
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
