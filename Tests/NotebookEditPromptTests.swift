import XCTest
@testable import DoyahCore

/// **容器编辑（新建 / 重命名 / 排序）的判据** —— 队列 `L-97` 界面半第四片（①）。
///
/// 契约出处 = `DoyahNotes/Docs/核心契约.md` **§2.12** 第 2 条（默认容器「不可删、**可改名**」）。
/// 这一片钉四件事：
///   · **名字规则只有一处**（洗净只动两端、「算不算一个名字」一条判断）—— `L-50` 那一课：
///     视图与 `AppState` 各写一遍必分家；
///   · **新建的落点跟着范围走**（架里 ⇒ 那个架；笔记本里 ⇒ 它所属的架；全部 ⇒ 默认架），
///     排序位按**该架内**现有条数（按全局计数会让新笔记本在架里跳到很后面）；
///   · **排序 = 相邻一步 + 整层重排**：`sort_order` 重号的库里，「交换两条」是空操作
///     （点了上移什么都没动）——这是本片最值钱的一条判据；
///   · **默认容器也能改名 / 也能排序**（契约只禁「删」）。
///
/// 末例是**接线判据**：规则写好了却没人调用，是这一族最典型的假绿。
final class NotebookEditPromptTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 夹具：两个架 / 三个笔记本（架B 里的两个 `sort_order` **都是 0**）

    /// 架A（默认）→ 笔记本A1（默认）；架B → 笔记本B1、笔记本B2。
    /// B1 与 B2 的 `sort_order` 刻意写成同一个数（历史的默认容器就长这样）——「整层重排」那条判据靠它。
    private func makeDirectory(duplicateSortOrders: Bool = true) -> NotebookDirectory {
        let shelfA = Shelf(uid: "shelf-a", name: "架A", sortOrder: 0, createdAt: t0, isDefault: true)
        let shelfB = Shelf(uid: "shelf-b", name: "架B", sortOrder: 1, createdAt: t0, isDefault: false)
        let a1 = Notebook(uid: "nb-a1", shelfUid: "shelf-a", name: "笔记本A1", sortOrder: 0, createdAt: t0, isDefault: true)
        let b1 = Notebook(uid: "nb-b1", shelfUid: "shelf-b", name: "笔记本B1", sortOrder: 0, createdAt: t0, isDefault: false)
        let b2 = Notebook(
            uid: "nb-b2",
            shelfUid: "shelf-b",
            name: "笔记本B2",
            sortOrder: duplicateSortOrders ? 0 : 1,
            createdAt: duplicateSortOrders ? t0 : t0.addingTimeInterval(1),
            isDefault: false
        )
        return NotebookDirectory(shelves: [shelfA, shelfB], notebooks: [a1, b1, b2])
    }

    // MARK: - ① 名字规则

    func testNameRuleTrimsOnlyTheEnds() {
        XCTAssertEqual(ContainerNameRule.sanitized("  笔记本B1  "), "笔记本B1")
        XCTAssertEqual(ContainerNameRule.sanitized("\n工作\t"), "工作", "换行与制表符也算两端")
        XCTAssertEqual(ContainerNameRule.sanitized("两个 词 中间"), "两个 词 中间", "**只动两端**：中间的空白是用户打的")
    }

    func testBlankNameIsNotAName() {
        XCTAssertFalse(ContainerNameRule.isAcceptable(""))
        XCTAssertFalse(ContainerNameRule.isAcceptable("   "))
        XCTAssertFalse(ContainerNameRule.isAcceptable("\n\t"))
        XCTAssertTrue(ContainerNameRule.isAcceptable(" 工作 "))
        XCTAssertTrue(ContainerNameRule.isAcceptable("x"))
    }

    /// 名字规则是**纯的**：同一个输入永远同一个输出，不看任何别的状态
    /// （⇒ 允许重名这条裁决才站得住：身份是 `uid`，名字不是主键）。同名两个笔记本靠 `uid` 区分。
    func testNameRuleIsPureAndDuplicateNamesAreKeptApartByUID() {
        let directory = NotebookDirectory(
            shelves: [Shelf(uid: "s", name: "架", sortOrder: 0, createdAt: t0, isDefault: true)],
            notebooks: [
                Notebook(uid: "first", shelfUid: "s", name: "工作", sortOrder: 0, createdAt: t0),
                Notebook(uid: "second", shelfUid: "s", name: "工作", sortOrder: 1, createdAt: t0),
            ]
        )
        XCTAssertEqual(ContainerNameRule.sanitized("工作"), ContainerNameRule.sanitized("工作"))
        XCTAssertEqual(directory.notebooks(inShelf: "s").map(\.uid), ["first", "second"], "同名两条都在（不按名字去重）")
        // 排序只动被点的那一个 —— 同名不妨碍它（次序靠 uid 指认）。
        let plan = ContainerReorder.plan(kind: .notebook, containerUid: "second", direction: .up, directory: directory)
        XCTAssertEqual(plan, [ContainerSortOrder(uid: "second", sortOrder: 0), ContainerSortOrder(uid: "first", sortOrder: 1)])
    }

    // MARK: - ② 新建的落点与排序位

    func testNewNotebookDestinationFollowsTheCurrentScope() {
        let directory = makeDirectory()
        XCTAssertEqual(
            NotebookCreation.destinationShelfUid(for: .shelf(uid: "shelf-b"), directory: directory),
            "shelf-b",
            "在某个架里 ⇒ 那个架"
        )
        XCTAssertEqual(
            NotebookCreation.destinationShelfUid(for: .notebook(uid: "nb-b1"), directory: directory),
            "shelf-b",
            "在某个笔记本里 ⇒ **它所属的架**（建同级笔记本，不是建到别处）"
        )
        XCTAssertEqual(
            NotebookCreation.destinationShelfUid(for: .all, directory: directory),
            "shelf-a",
            "「全部」⇒ 默认架（契约里那个不可删的落点）"
        )
    }

    func testUnknownScopeFallsBackToTheDefaultShelf() {
        // 指向已被删掉的容器 ⇒ 与 `NotesNavigation.normalized` 回落「全部」同一处置。
        let directory = makeDirectory()
        XCTAssertEqual(NotebookCreation.destinationShelfUid(for: .shelf(uid: "gone"), directory: directory), "shelf-a")
        XCTAssertEqual(NotebookCreation.destinationShelfUid(for: .notebook(uid: "gone"), directory: directory), "shelf-a")
    }

    func testNoShelfMeansNowhereToCreate() {
        let empty = NotebookDirectory(shelves: [], notebooks: [])
        XCTAssertNil(NotebookCreation.destinationShelfUid(for: .all, directory: empty), "一个架都没有 ⇒ 老老实实说没有落点")
        XCTAssertFalse(NotebookCreation.canCreate(in: empty))
        XCTAssertTrue(NotebookCreation.canCreate(in: makeDirectory()))
    }

    func testNewNotebookSortOrderCountsWithinItsOwnShelf() {
        let directory = makeDirectory()
        XCTAssertEqual(NotebookCreation.sortOrder(inShelf: "shelf-b", directory: directory), 2, "架B 里已有两个 ⇒ 新的是第 3 个")
        XCTAssertEqual(NotebookCreation.sortOrder(inShelf: "shelf-a", directory: directory), 1, "架A 里只有一个 ⇒ 新的是第 2 个（**不是全局条数**）")
    }

    // MARK: - ③ 排序

    func testReorderCannotMoveTheFirstUpOrTheLastDown() {
        let directory = makeDirectory()
        XCTAssertFalse(ContainerReorder.canMove(kind: .notebook, containerUid: "nb-b1", direction: .up, directory: directory))
        XCTAssertFalse(ContainerReorder.canMove(kind: .notebook, containerUid: "nb-b2", direction: .down, directory: directory))
        XCTAssertTrue(ContainerReorder.canMove(kind: .notebook, containerUid: "nb-b1", direction: .down, directory: directory))
        XCTAssertTrue(ContainerReorder.canMove(kind: .notebook, containerUid: "nb-b2", direction: .up, directory: directory))
        XCTAssertNil(ContainerReorder.plan(kind: .notebook, containerUid: "ghost", direction: .up, directory: directory), "认不出的 uid ⇒ 没有可挪的")
    }

    /// **本片最值钱的一条**：库里两条 `sort_order` 相同时，「交换两个数」是空操作
    /// （界面上就是「点了上移、什么都没动」）—— 整层重排才真的把可见次序换过来。
    func testReorderRewritesTheWholeLevelSoDuplicateSortOrdersStillMove() {
        let directory = makeDirectory(duplicateSortOrders: true)
        XCTAssertEqual(
            ContainerReorder.order(kind: .notebook, containerUid: "nb-b2", directory: directory),
            ["nb-b1", "nb-b2"],
            "重号时可见次序靠创建时刻兜底"
        )
        let plan = ContainerReorder.plan(kind: .notebook, containerUid: "nb-b2", direction: .up, directory: directory)
        XCTAssertEqual(
            plan,
            [ContainerSortOrder(uid: "nb-b2", sortOrder: 0), ContainerSortOrder(uid: "nb-b1", sortOrder: 1)],
            "整层重写成 0..<n 再交换 ⇒ 两个都写了，相邻一步一定生效"
        )
        // 反例留档：若只交换两条的 `sort_order`（旧写法），两个 0 换完还是两个 0。
        XCTAssertEqual(directory.notebook(uid: "nb-b1")?.sortOrder, directory.notebook(uid: "nb-b2")?.sortOrder)
    }

    func testReorderStaysInsideTheShelf() {
        let directory = makeDirectory()
        let plan = ContainerReorder.plan(kind: .notebook, containerUid: "nb-b1", direction: .down, directory: directory)
        XCTAssertEqual(plan?.map(\.uid), ["nb-b2", "nb-b1"], "只写**同架**的那一层，且**换的只是可见次序**（跨架挪是「移动」，不是排序）")
        XCTAssertFalse(plan?.contains { $0.uid == "nb-a1" } ?? true, "另一个架的笔记本一个字都不许动")
    }

    func testShelvesReorderOnTheirOwnLevel() {
        let directory = makeDirectory()
        XCTAssertEqual(ContainerReorder.order(kind: .shelf, containerUid: "shelf-a", directory: directory), ["shelf-a", "shelf-b"])
        XCTAssertEqual(
            ContainerReorder.plan(kind: .shelf, containerUid: "shelf-b", direction: .up, directory: directory),
            [ContainerSortOrder(uid: "shelf-b", sortOrder: 0), ContainerSortOrder(uid: "shelf-a", sortOrder: 1)]
        )
    }

    /// 契约 §2.12 第 2 条只禁「删」—— **默认容器可改名、也在同一层里参与排序**。
    func testDefaultContainersAreNotTreatedAsAPinnedRow() {
        let directory = makeDirectory()
        // 默认架在第一位 ⇒ 不能再上移（位置使然），但它**在排序这一层里**（不是被钉死、不参与）。
        XCTAssertEqual(ContainerReorder.order(kind: .shelf, containerUid: "shelf-a", directory: directory).first, "shelf-a")
        XCTAssertFalse(ContainerReorder.canMove(kind: .shelf, containerUid: "shelf-a", direction: .up, directory: directory))
        XCTAssertTrue(ContainerReorder.canMove(kind: .shelf, containerUid: "shelf-a", direction: .down, directory: directory))
        // 默认笔记本同样：给它一个同架的邻居，它就挪得动（不是被钉死、不参与排序的那一行）。
        let withNeighbour = NotebookDirectory(
            shelves: [Shelf(uid: "shelf-a", name: "架A", sortOrder: 0, createdAt: t0, isDefault: true)],
            notebooks: [
                Notebook(uid: "nb-a1", shelfUid: "shelf-a", name: "笔记本A1", sortOrder: 0, createdAt: t0, isDefault: true),
                Notebook(uid: "nb-a2", shelfUid: "shelf-a", name: "笔记本A2", sortOrder: 1, createdAt: t0),
            ]
        )
        XCTAssertTrue(ContainerReorder.canMove(kind: .notebook, containerUid: "nb-a1", direction: .down, directory: withNeighbour))
        XCTAssertFalse(ContainerReorder.canMove(kind: .notebook, containerUid: "nb-a1", direction: .up, directory: withNeighbour), "在第一位 ⇒ 上移走不动（位置使然，不是身份）")
        XCTAssertEqual(
            ContainerReorder.plan(kind: .notebook, containerUid: "nb-a1", direction: .down, directory: withNeighbour),
            [ContainerSortOrder(uid: "nb-a2", sortOrder: 0), ContainerSortOrder(uid: "nb-a1", sortOrder: 1)],
            "默认笔记本也在这一层里参与排序（契约 §2.12 第 2 条只禁「删」）"
        )
        // 改名这一半：请求本身**不带**「默认就改不了」的判定（`isDefault` 只用于界面交代）。
        let request = ContainerEditRequest(
            id: "shelf-a", mode: .rename, kind: .shelf, currentName: "架A", destinationShelfUid: nil, isDefault: true
        )
        XCTAssertEqual(request.mode, .rename)
        XCTAssertTrue(request.isDefault, "默认容器可改名（契约 §2.12 第 2 条）—— 这一格不是闸")
    }

    // MARK: - 接线（源码判据）

    /// 视图与 `AppState` 必须**真的用**这套规则：判据全绿、界面上一个菜单项都没接，是这一族最典型的假绿。
    /// 判法 = 在源码里钉锚点（剥注释后再判 —— 注释里写着标识名不算接线）。
    func testHostWiringUsesTheEditPromptInsteadOfHardWiringRules() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let appState = Self.stripComments(try String(contentsOf: root.appendingPathComponent("App/AppState.swift"), encoding: .utf8))
        let panel = Self.stripComments(try String(contentsOf: root.appendingPathComponent("App/Views/NotesPanel.swift"), encoding: .utf8))

        XCTAssertTrue(appState.contains("func beginNewNotebook("), "新建的入口由 AppState 一处给")
        XCTAssertTrue(appState.contains("func beginRenameContainer("), "重命名的入口由 AppState 一处给")
        XCTAssertTrue(appState.contains("func confirmContainerEdit("), "落库走这一个入口")
        XCTAssertTrue(appState.contains("library.createNotebook(inShelf:"), "新建走 `NoteLibrary.createNotebook`")
        XCTAssertTrue(appState.contains("library.renameNotebook(uid:"), "改名走 `NoteLibrary.renameNotebook`")
        XCTAssertTrue(appState.contains("library.renameShelf(uid:"), "架改名走 `NoteLibrary.renameShelf`")
        XCTAssertTrue(appState.contains("func moveContainer("), "排序走这一个入口")
        XCTAssertTrue(appState.contains(".reorder("), "落库走 `NoteLibrary.reorder`（整层重排那一条）")
        XCTAssertTrue(appState.contains("var containerEditNameIsAcceptable"), "判据属性是唯一出处")
        XCTAssertTrue(appState.contains("await reloadNotes()"), "编辑完要重读库（树 / 条数 / 范围归一会跟着变）")

        XCTAssertTrue(panel.contains("NotebookCreation.menuTitleKey"), "新建那一项的文字由 Core 给")
        XCTAssertTrue(panel.contains("ContainerEditPrompt.menuTitleKey"), "重命名那一项的文字由 Core 给")
        XCTAssertTrue(panel.contains("appState.beginNewNotebook(inShelf:"), "树上右键要指定「就建在这一行这个架里」")
        XCTAssertTrue(panel.contains("appState.beginRenameContainer("), "右键要真的接上重命名入口")
        XCTAssertTrue(panel.contains("appState.confirmContainerEdit()"), "弹框的「确定」要真的接上落库入口")
        XCTAssertTrue(panel.contains(".disabled(!appState.containerEditNameIsAcceptable)"), "空名字时「确定」要真的灰着（不是点了没反应）")
        XCTAssertTrue(panel.contains("appState.canMoveContainer("), "上移 / 下移要问 Core 能不能挪（视图不自己判）")
        XCTAssertTrue(panel.contains("ContainerReorderDirection.allCases"), "两个方向由 Core 的枚举给（不许视图硬写两行）")

        // 反向断言一：视图里不许自己重新推导判据（`L-50` 的病根就是两处各写一遍）。
        XCTAssertFalse(panel.contains("containerEditName.trimmingCharacters"), "名字判据只许住在一处")
        XCTAssertFalse(panel.contains("没有笔记本架"), "句子只许在语言表里")
        XCTAssertFalse(panel.contains(".sortOrder ="), "视图不许自己算排序位")
    }

    /// 反向断言二：新 Core 文件里的**代码**不许出现中文字面量（文案归语言表，判据 = `check-core-localization`）。
    /// 剥注释之后再找双引号里的汉字 —— 注释里写中文是允许的，那不算文案。
    func testCoreFileKeepsUserFacingTextOutOfStringLiterals() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = Self.stripComments(try String(contentsOf: root.appendingPathComponent("Core/NotebookEditPrompt.swift"), encoding: .utf8))
        let regex = try NSRegularExpression(pattern: "\"[^\"\\n]*[\\u4E00-\\u9FFF][^\"\\n]*\"")
        let hits = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        XCTAssertTrue(hits.isEmpty, "Core 里的用户文案必须走 LKey（实测命中 \\(hits.count) 处）")
    }

    /// 剥注释（`//` 与 `///` 行、`/* */` 块）—— 与 `NotebookMovePromptTests` 同一份实现（同一课）。
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
