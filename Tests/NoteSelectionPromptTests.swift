import XCTest
@testable import DoyahCore

/// **批量多选与拖拽的判据** —— 队列 `L-97` 界面半第五片（④ 的最后两件）。
///
/// 契约出处 = `DoyahNotes/Docs/核心契约.md` §2.12 第 1 / 4 条。这一片钉四件事：
///   · **修饰键语义**（无修饰 = 单选 + 打开编辑；⌘ = 切换；⇧ = 从锚点连选）——
///     错了的症状是「多选根本用不成」或「⇧ 一点就把一批没打算选的选中了」；
///   · **选中集合随时对着可见列表收一遍**（否则批量移动会带走界面上看不见的笔记）；
///   · **拖一条时带走哪些**（在选中集合里 ⇒ 整捆，否则只拖这一条）；
///   · **落点计划**（已在目标里的不写库；整捆都已在 ⇒ 不写库、给一句人话）。
///
/// 末例是**接线判据**：规则写好了却没人调用，是这一族最典型的假绿。
final class NoteSelectionPromptTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()

    /// 当前可见次序（界面上从上到下就是它）。
    private var ordered: [UUID] { [a, b, c, d] }

    private func clicked(
        _ id: UUID,
        _ modifiers: NoteSelectionModifiers = [],
        selection: Set<UUID> = [],
        anchor: UUID? = nil
    ) -> NoteSelectionOutcome {
        NoteSelectionRule.clicked(
            id,
            modifiers: modifiers,
            ordered: ordered,
            selection: selection,
            anchor: anchor
        )
    }

    // MARK: - ① 修饰键语义

    func testPlainClickSelectsOneAndOpensTheEditor() {
        // 无修饰点击 = 原来的行为（选中这一条 + 打开它），不能被多选改掉。
        let outcome = clicked(b, selection: [a, c], anchor: a)
        XCTAssertEqual(outcome.selection, [b], "无修饰点击 ⇒ 单选（清掉之前的多选）")
        XCTAssertEqual(outcome.anchor, b, "锚点跟到刚点的那一条")
        XCTAssertEqual(outcome.edited, b, "无修饰点击要打开编辑面（这是改多选之前就有的行为）")
    }

    func testCommandClickAddsAndRemovesAndMovesTheAnchor() {
        let added = clicked(c, .command, selection: [a], anchor: a)
        XCTAssertEqual(added.selection, [a, c], "⌘ 点 ⇒ 把这一条加进选中集合")
        XCTAssertEqual(added.anchor, c, "⌘ 点之后锚点跟到这一条（⇧ 从这儿往外扩）")
        XCTAssertNil(added.edited, "⌘ 点不该打开编辑面（不然多选时编辑器一直在换）")

        let removed = clicked(a, .command, selection: [a, c], anchor: a)
        XCTAssertEqual(removed.selection, [c], "再 ⌘ 点一次 ⇒ 取消这一条")
    }

    func testShiftClickSelectsTheClosedRangeFromTheAnchor() {
        let outcome = clicked(c, .shift, selection: [a], anchor: a)
        XCTAssertEqual(outcome.selection, [a, b, c], "⇧ 点 ⇒ 锚点到这一条的**闭区间**（两端都算）")
        XCTAssertEqual(outcome.anchor, a, "⇧ 点不动锚点 —— 否则范围只能选一次")
        XCTAssertNil(outcome.edited, "⇧ 点不该打开编辑面")
    }

    func testShiftClickBackwardsAlsoSelectsTheRange() {
        let outcome = clicked(a, .shift, selection: [c], anchor: c)
        XCTAssertEqual(outcome.selection, [a, b, c], "从下往上 ⇧ 点要得到同一段（次序反着来也是同一批）")
    }

    func testShiftClickKeepsTheAnchorSoTheRangeCanGrow() {
        let first = clicked(b, .shift, selection: [a], anchor: a)
        let grown = clicked(d, .shift, selection: first.selection, anchor: first.anchor)
        XCTAssertEqual(grown.selection, [a, b, c, d], "连着 ⇧ 点 ⇒ 范围从同一个锚点往外长")
    }

    func testShiftClickWithoutAUsableAnchorFallsBackToASingleSelection() {
        let noAnchor = clicked(c, .shift, selection: [], anchor: nil)
        XCTAssertEqual(noAnchor.selection, [c], "没有锚点 ⇒ 退化成单选（不替用户猜一个起点）")
        XCTAssertEqual(noAnchor.anchor, c, "顺手把锚点补上，下一次 ⇧ 就有起点了")
        XCTAssertNil(noAnchor.edited, "⇧ 点还是不打开编辑面")

        // 锚点已经不在可见次序里（范围换了 / 那条被删了）⇒ 同一条路。
        let staleAnchor = clicked(c, .shift, selection: [d], anchor: UUID())
        XCTAssertEqual(staleAnchor.selection, [c], "认不出的锚点不参与范围计算 ⇒ 退化成单选")
    }

    // MARK: - ② 选中集合对着可见列表收一遍

    func testPruneDropsWhatIsNoLongerVisible() {
        let pruned = NoteSelectionRule.pruned([a, c], within: [a, b])
        XCTAssertEqual(pruned, [a], "界面上看不见的那条要丢掉（否则批量移动会带走用户看不见的笔记）")
    }

    func testPruneEmptiesTheSelectionWhenNothingIsVisible() {
        XCTAssertEqual(NoteSelectionRule.pruned([a, b], within: []), [], "一条都看不见 ⇒ 空集合")
    }

    // MARK: - ③ 拖一条时带走哪些

    func testDraggingANoteInsideTheSelectionDragsTheWholeBundleInVisibleOrder() {
        let dragged = NoteSelectionRule.draggedNoteIDs(clicked: c, selection: [c, a], ordered: ordered)
        XCTAssertEqual(dragged, [a, c], "拖选中集合里的一条 ⇒ 整捆，顺序 = 可见次序（不是集合的遍历顺序）")
    }

    func testDraggingANoteOutsideTheSelectionDragsOnlyThatNote() {
        let dragged = NoteSelectionRule.draggedNoteIDs(clicked: d, selection: [a, b], ordered: ordered)
        XCTAssertEqual(dragged, [d], "拖一条**没被选中**的行 ⇒ 只拖这一条（不许顺手带上别的）")
    }

    func testDraggingWithASingleSelectionDragsOnlyThatNote() {
        let dragged = NoteSelectionRule.draggedNoteIDs(clicked: a, selection: [a], ordered: ordered)
        XCTAssertEqual(dragged, [a], "只选中一条时就是拖这一条（不是「整捆」的边界情况）")
    }

    // MARK: - 载荷编解码

    func testPayloadRoundTrips() {
        let encoded = NoteDragPayload.encode([a, c])
        XCTAssertTrue(encoded.hasPrefix("doyah-note-ids:"), "前缀要与普通文本拖拽区分开")
        XCTAssertEqual(NoteDragPayload.decode(encoded), [a, c], "编出来的要解得回来")
        XCTAssertEqual(NoteDragPayload.decode(NoteDragPayload.encode([])), [], "空捆也解得回来（空数组，不是坏输入）")
    }

    func testPayloadRejectsForeignAndBrokenInput() {
        XCTAssertEqual(NoteDragPayload.decode("just some text"), [], "别的程序拖来的文本 ⇒ 空数组（不猜）")
        XCTAssertEqual(NoteDragPayload.decode("doyah-note-ids:"), [], "只有前缀、没有内容 ⇒ 空数组")
        XCTAssertEqual(
            NoteDragPayload.decode("doyah-note-ids:not-a-uuid," + a.uuidString),
            [a],
            "坏的那一段丢掉，好的那一段照收（不是整捆作废）"
        )
    }

    // MARK: - ④ 落点计划

    /// 夹具：架S（默认）→ 笔记本A（默认）、笔记本B；a 在 A 里，b 与 c 在 B 里，d 缺归属行。
    private func makeDirectory() -> NotebookDirectory {
        let shelf = Shelf(uid: "shelf-s", name: "架S", sortOrder: 0, createdAt: t0, isDefault: true)
        let a = Notebook(uid: "nb-a", shelfUid: "shelf-s", name: "笔记本A", sortOrder: 0, createdAt: t0, isDefault: true)
        let b = Notebook(uid: "nb-b", shelfUid: "shelf-s", name: "笔记本B", sortOrder: 1, createdAt: t0, isDefault: false)
        return NotebookDirectory(shelves: [shelf], notebooks: [a, b])
    }

    private var placements: [NotebookPlacement] {
        [
            NotebookPlacement(noteID: a.uuidString, notebookUid: "nb-a"),
            NotebookPlacement(noteID: b.uuidString, notebookUid: "nb-b"),
            NotebookPlacement(noteID: c.uuidString, notebookUid: "nb-b"),
        ]
    }

    private func plan(_ noteIDs: [UUID], to notebookUid: String) -> NoteDropPlan {
        NoteDropRule.plan(
            noteIDs: noteIDs,
            toNotebook: notebookUid,
            directory: makeDirectory(),
            placements: placements
        )
    }

    func testOnlyNotebooksAcceptDrops() {
        XCTAssertTrue(NoteDropRule.acceptsDrop(kind: .notebook), "只有笔记本行接落点（笔记不直接属于架）")
        XCTAssertFalse(NoteDropRule.acceptsDrop(kind: .shelf), "架行不接 —— 接了就表示笔记能挂在架上")
    }

    func testDropPlanSkipsNotesAlreadyInTheTarget() {
        let plan = plan([a, b], to: "nb-b")
        XCTAssertEqual(plan.targetNotebookUid, "nb-b", "目标就是拖到的那一格")
        XCTAssertEqual(plan.targetNotebookName, "笔记本B", "名字取自目录（那句人话要用它）")
        XCTAssertEqual(plan.movingNoteIDs, [a], "只有 A 里那条要动；B 里那条已经在目标里 ⇒ 不写库")
        XCTAssertEqual(plan.alreadyThereCount, 1, "已经在目标里的条数要如实算出来")
        XCTAssertFalse(plan.isNoop, "还有要动的 ⇒ 不是空操作")
    }

    func testDropPlanIsANoopWhenTheWholeBundleIsAlreadyThere() {
        let plan = plan([b, c], to: "nb-b")
        XCTAssertTrue(plan.movingNoteIDs.isEmpty, "整捆都已在目标里 ⇒ 一条都不写")
        XCTAssertTrue(plan.isNoop, "空操作 ⇒ 界面给一句人话（位置不是内容，没必要白写一次）")
        XCTAssertEqual(plan.alreadyThereCount, 2)
    }

    func testDropPlanResolvesAnUnknownTargetToTheDefaultNotebook() {
        // 认不出的目标（那一格刚被删 / 载荷被改过）⇒ 默认笔记本，与树上、与移动菜单同一条兜底。
        let plan = plan([b], to: "nb-gone")
        XCTAssertEqual(plan.targetNotebookUid, "nb-a", "认不出的目标 ⇒ 默认笔记本（不新建、不静默丢弃）")
        XCTAssertEqual(plan.targetNotebookName, "笔记本A")
        XCTAssertEqual(plan.movingNoteIDs, [b], "B 里那条与默认笔记本不同 ⇒ 要动")
    }

    func testMissingPlacementCountsAsTheDefaultNotebook() {
        // 缺归属行的笔记按默认笔记本处置（契约 §2.12 第 2 条）—— 拖它到默认笔记本 = 空操作。
        XCTAssertTrue(plan([d], to: "nb-a").isNoop, "缺归属 ⇒ 算默认笔记本 ⇒ 拖到默认笔记本没什么可动")
    }

    // MARK: - 接线（源码判据）

    /// 规则与载荷写好了却没人调用 = 假绿。判法 = 在源码里钉锚点（剥注释后再判）。
    func testHostWiringUsesTheSelectionRules() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let appState = Self.stripComments(
            try! String(contentsOf: root.appendingPathComponent("App/AppState.swift"), encoding: .utf8)
        )
        let panel = Self.stripComments(
            try! String(contentsOf: root.appendingPathComponent("App/Views/NotesPanel.swift"), encoding: .utf8)
        )

        XCTAssertTrue(appState.contains("NoteSelectionRule.clicked("), "点击处置走 Core 规则（视图不自己判修饰键）")
        XCTAssertTrue(appState.contains("NoteDragPayload.encode("), "载荷只有一处生产点")
        XCTAssertTrue(appState.contains("NoteDragPayload.decode("), "落点解载荷走同一处")
        XCTAssertTrue(appState.contains("NoteDropRule.plan("), "落点计划由 Core 算")
        XCTAssertTrue(appState.contains("func moveNotes("), "落库仍走原来那个入口（不新写一条写库路）")

        XCTAssertTrue(panel.contains("appState.handleNoteRowClick("), "行上点了要真的接上入口")
        XCTAssertTrue(panel.contains(".draggable(appState.noteDragPayload(for: note))"), "拖拽载荷来自 AppState 一处")
        XCTAssertTrue(panel.contains("appState.handleNoteDrop("), "落点要真的接上入口")
        XCTAssertEqual(
            panel.components(separatedBy: ".dropDestination").count - 1,
            1,
            "落点只挂在一处（笔记本行）；架行与「全部」行不接 —— 契约 §2.12 第 1 条"
        )
        XCTAssertTrue(panel.contains("NoteSelectionPrompt"), "文案键由 Core 给")

        // 反向断言：视图里不许写死那两句话（写死一次就会与语言表分家）。
        XCTAssertFalse(panel.contains("这几条已经在"), "句子只许在语言表里")
        XCTAssertFalse(panel.contains("已选 %d 条"), "句子只许在语言表里")
    }

    /// 剥注释（`//` / `///` 行、`/* */` 块）—— 与 `NoteNavigationTests` 同一份实现（同一课）。
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
