import XCTest
@testable import DoyahCore

/// **删除确认框的判据** —— 队列 `L-97` 界面半第二片（③ 删除确认框）。
///
/// 契约出处 = `DoyahNotes/Docs/核心契约.md` §2.12 第 3 条。这一片钉三件事：
///   · **动作与顺序**（默认档在最前、取消是退出口）—— 排错了就是让用户默认走进破坏档；
///   · **影响面那句话的形状**（空 / 只有笔记 / 只有笔记本 / 两个都有）—— 错法很安静：
///     删架走默认档时 `removedNotebookUids` 本来就是空，只数「被删的」会让确认框说
///     「将影响 0 个笔记本」，而整架都会改挂（第 168 轮实测）；
///   · **默认容器删不掉**：计划为 `nil` ⇒ 界面给一句人话，而不是一个点了没反应的菜单项。
///
/// 末例是**接线判据**：纯逻辑写好了却没人调用，是这一族最典型的假绿。
final class NotebookRemovalPromptTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 夹具：两个架 / 三个笔记本 / 两条笔记

    /// 结构（两个架都**可删**地各留了一个非默认容器在内 —— 默认容器本身删不掉，见末例）：
    ///   架 A（默认）→ 笔记本 A1（默认）
    ///   架 B（非默认）→ 笔记本 B1（非默认，**挂两条笔记**）、笔记本 B2（非默认，**空**）
    private func makeDirectory() -> NotebookDirectory {
        let shelfA = Shelf(uid: "shelf-a", name: "架A", sortOrder: 0, createdAt: t0, isDefault: true)
        let shelfB = Shelf(uid: "shelf-b", name: "架B", sortOrder: 1, createdAt: t0, isDefault: false)
        let a1 = Notebook(uid: "nb-a1", shelfUid: shelfA.uid, name: "笔记本A1", sortOrder: 0, createdAt: t0, isDefault: true)
        let b1 = Notebook(uid: "nb-b1", shelfUid: shelfB.uid, name: "笔记本B1", sortOrder: 0, createdAt: t0, isDefault: false)
        let b2 = Notebook(uid: "nb-b2", shelfUid: shelfB.uid, name: "笔记本B2", sortOrder: 1, createdAt: t0, isDefault: false)
        return NotebookDirectory(shelves: [shelfA, shelfB], notebooks: [a1, b1, b2])
    }

    private func makePlacements() -> [NotebookPlacement] {
        [
            NotebookPlacement(noteID: "n1", notebookUid: "nb-b1"),
            NotebookPlacement(noteID: "n2", notebookUid: "nb-b1"),
        ]
    }

    private func makePlan(kind: NotebookContainerKind, uid: String, policy: ContainerRemovalPolicy = .default) -> ContainerRemovalPlan {
        let directory = makeDirectory()
        let placements = makePlacements()
        switch kind {
        case .notebook:
            return directory.removalPlan(forNotebook: uid, policy: policy, placements: placements)!
        case .shelf:
            return directory.removalPlan(forShelf: uid, policy: policy, placements: placements)!
        }
    }

    // MARK: - 动作与顺序

    func testConfirmActionsPutTheDefaultPolicyFirstAndCancelLast() {
        XCTAssertEqual(
            ContainerRemovalPrompt.confirmActions,
            [.moveToDefault, .deleteTogether, .cancel],
            "契约「默认都取后者（不删内容）」的落点就是这一行的次序"
        )
        XCTAssertEqual(ContainerRemovalAction.moveToDefault.policy, .moveToDefault)
        XCTAssertEqual(ContainerRemovalAction.deleteTogether.policy, .deleteTogether)
        XCTAssertNil(ContainerRemovalAction.cancel.policy, "取消不落库")
        XCTAssertFalse(ContainerRemovalAction.moveToDefault.deletesContent, "默认档不删内容")
        XCTAssertTrue(ContainerRemovalAction.deleteTogether.deletesContent)
        XCTAssertFalse(ContainerRemovalAction.cancel.deletesContent)
    }

    func testButtonTitlesAreDistinctForTheTwoContainerKinds() {
        let keys = [
            ContainerRemovalPrompt.titleKey(for: .moveToDefault, kind: .notebook),
            ContainerRemovalPrompt.titleKey(for: .moveToDefault, kind: .shelf),
            ContainerRemovalPrompt.titleKey(for: .deleteTogether, kind: .notebook),
            ContainerRemovalPrompt.titleKey(for: .deleteTogether, kind: .shelf),
        ]
        XCTAssertEqual(Set(keys).count, 4, "「移到默认笔记本」与「笔记本整架移到默认架」不是同一件事")
        XCTAssertEqual(ContainerRemovalPrompt.titleKey(for: .cancel, kind: .notebook), .notesRemoveCancel)
        XCTAssertEqual(ContainerRemovalPrompt.titleKey(for: .cancel, kind: .shelf), .notesRemoveCancel)
        XCTAssertNotEqual(ContainerRemovalPrompt.titleKey(for: .cancel, kind: .shelf), keys[0])
    }

    // MARK: - 影响面那句话的形状

    func testNotebookPlanAffectsOnlyNotes() {
        let plan = makePlan(kind: .notebook, uid: "nb-b1")
        XCTAssertEqual(plan.affectedNotebookCount, 0, "删一个笔记本不牵动别的笔记本")
        XCTAssertEqual(plan.affectedNoteCount, 2)
        XCTAssertEqual(ContainerRemovalPrompt.request(plan: plan, containerName: "笔记本B1").summary, .notes(2))
    }

    func testEmptyNotebookSaysNothingWillBeAffected() {
        // 空的**非默认**笔记本（默认笔记本根本删不掉，见末例）：不写数字，照实说「不影响任何东西」。
        let plan = makePlan(kind: .notebook, uid: "nb-b2")
        XCTAssertEqual(plan.affectedNotebookCount, 0)
        XCTAssertEqual(plan.affectedNoteCount, 0)
        XCTAssertEqual(ContainerRemovalPrompt.request(plan: plan, containerName: "笔记本B2").summary, .empty)
    }

    func testShelfMovingToDefaultCountsNotebooksEvenThoughNoneIsDeleted() {
        // 默认档：一个笔记本都不删、整架都要改挂 ⇒ 只数「被删的」会说「将影响 0 个笔记本」，
        // 而事实是整架都会动（第 168 轮实测出来的那一条）。
        let plan = makePlan(kind: .shelf, uid: "shelf-b")
        XCTAssertTrue(plan.removedNotebookUids.isEmpty, "默认档一个笔记本都不删")
        XCTAssertEqual(plan.affectedNotebookCount, 2, "「受影响」= 被删的 + 被改挂的")
        XCTAssertEqual(plan.affectedNoteCount, 0, "笔记本整架搬走，笔记一条都不改挂")
        XCTAssertEqual(ContainerRemovalPrompt.request(plan: plan, containerName: "架B").summary, .notebooks(2))
    }

    func testShelfDeleteTogetherCountsNotebooksAndNotes() {
        // 架 B 一并删：两个笔记本（B1 / B2）连同 B1 里的两条笔记一起删。
        let plan = makePlan(kind: .shelf, uid: "shelf-b", policy: .deleteTogether)
        XCTAssertEqual(plan.affectedNotebookCount, 2)
        XCTAssertEqual(plan.affectedNoteCount, 2)
        XCTAssertEqual(
            ContainerRemovalPrompt.request(plan: plan, containerName: "架B").summary,
            .notebooksAndNotes(notebooks: 2, notes: 2)
        )
    }

    /// 形状 ↔ 文案键必须对得上：**带几个数就得配几个 `%d`**。
    /// 这条量的是真语言表（不是本文件的推断）——「把两个数的句子配给一个数的形状」在这里当场判红。
    func testSummaryKeysMatchTheNumberOfNumbers() {
        let shapes: [(ContainerRemovalSummary, Int)] = [
            (.empty, 0),
            (.notes(3), 1),
            (.notebooks(4), 1),
            (.notebooksAndNotes(notebooks: 5, notes: 6), 2),
        ]
        for (summary, slots) in shapes {
            for language in AppLanguage.allCases {
                let template = LocalizedStrings.text(summary.key, language: language)
                XCTAssertEqual(
                    template.components(separatedBy: "%d").count - 1, slots,
                    "\(summary) 的形状要 \(slots) 个 %d（\(language) 侧现在是：\(template)）"
                )
                XCTAssertFalse(template.contains("%@"), "数进数字槽，别用 %@（会印成 (null)）")
            }
        }
        XCTAssertEqual(
            Set(shapes.map(\.0.key)).count, 4,
            "四种形状各用各的键 —— 合成一句会让中英两侧都得硬塞一个「0 个笔记本」"
        )
    }

    func testConfirmTitleTakesTheContainerNameAsText() {
        for language in AppLanguage.allCases {
            let template = LocalizedStrings.text(ContainerRemovalPrompt.titleKey, language: language)
            XCTAssertEqual(template.components(separatedBy: "%@").count - 1, 1, "标题要写清删的是哪一个")
            XCTAssertFalse(template.contains("%d"))
            let notAllowed = LocalizedStrings.text(ContainerRemovalPrompt.notAllowedKey, language: language)
            XCTAssertTrue(notAllowed.contains("%@"), "「不能删」那句话要点名是哪个容器")
        }
    }

    // MARK: - 请求本身

    func testRequestCarriesKindNamePlanAndAllThreeActions() {
        let plan = makePlan(kind: .notebook, uid: "nb-b1")
        let request = ContainerRemovalPrompt.request(plan: plan, containerName: "笔记本B1")
        XCTAssertEqual(request.id, "nb-b1", "id = 容器 uid（确认框落地时按它删）")
        XCTAssertEqual(request.kind, .notebook)
        XCTAssertEqual(request.containerName, "笔记本B1")
        XCTAssertEqual(request.plan, plan)
        for action in ContainerRemovalAction.allCases {
            XCTAssertTrue(request.offers(action), "三个动作都要给（界面据此画按钮）")
        }
        XCTAssertNotEqual(
            ContainerRemovalPrompt.titleKey(for: .deleteTogether, kind: .notebook),
            ContainerRemovalPrompt.titleKey(for: .moveToDefault, kind: .notebook)
        )
    }

    func testDefaultContainersHaveNoPlanAtAll() {
        let directory = makeDirectory()
        let placements = makePlacements()
        XCTAssertNil(
            directory.removalPlan(forNotebook: "nb-a1", placements: placements),
            "默认笔记本不可删（契约 §2.12）"
        )
        XCTAssertNil(
            directory.removalPlan(forShelf: "shelf-a", placements: placements),
            "默认架不可删（同上）"
        )
        XCTAssertNil(
            directory.removalPlan(forNotebook: "认不出的", placements: placements),
            "认不出的 uid 也算删不掉（不猜）"
        )
    }

    // MARK: - 接线（源码判据）

    /// 视图与 `AppState` 必须**真的用**这套规则：判据全绿、界面上一个按钮都没接，是这一族最典型的假绿。
    /// 判法 = 在源码里钉住锚点（剥注释后再判 —— 注释里写着标识名不算接线）。
    func testHostWiringUsesThePromptInsteadOfHardWiringButtons() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let appState = Self.stripComments(try! String(contentsOf: root.appendingPathComponent("App/AppState.swift"), encoding: .utf8))
        let panel = Self.stripComments(try! String(contentsOf: root.appendingPathComponent("App/Views/NotesPanel.swift"), encoding: .utf8))

        XCTAssertTrue(appState.contains("pendingContainerRemoval"), "AppState 要持有那个请求")
        XCTAssertTrue(appState.contains("requestContainerRemoval"), "树上点删除走这一个入口")
        XCTAssertTrue(appState.contains("resolveContainerRemoval"), "选了动作走这一个入口")
        XCTAssertTrue(appState.contains("cancelContainerRemoval"), "退出口要真的收掉请求")
        XCTAssertTrue(appState.contains("await reloadNotes()"), "删完要重读库（树 / 条数 / 范围归一）")
        XCTAssertTrue(appState.contains("library.removalPlan(forNotebook: uid)"), "计划从库里现算，不在界面里算")
        XCTAssertTrue(appState.contains("library.removalPlan(forShelf: uid)"), "架那一半同一条路")

        XCTAssertTrue(panel.contains("confirmationDialog"), "删除要弹确认框，不是点了就删")
        XCTAssertTrue(panel.contains("ContainerRemovalPrompt"), "动作与顺序由模型给")
        XCTAssertTrue(panel.contains("appState.pendingContainerRemovalMessage"), "影响面那句由 AppState 一处生成")
        XCTAssertTrue(panel.contains("requestContainerRemoval(kind:"), "菜单项要真的接上入口")
        // 反向断言：视图里不许自己写影响面那句（写死一次就会与 Core 的形状判断分家）。
        XCTAssertFalse(panel.contains("将影响"), "句子只许在语言表里")
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
