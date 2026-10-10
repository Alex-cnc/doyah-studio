import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **浮动覆盖式书架 + 笔记列表列位于最左**（`FR-NOTEUI-01` / `-02` / `-03` · 派单
/// `T-20261010-166` §三.2 · 人类主人 2026-10-10 原话②）。
///
/// ## 由头（逐字）
///
/// 「**笔记本管理栏可以节约空间改成浮动式的，把笔记管理左栏放到目前的笔记本管理导航栏去。**」
///
/// 改前（真机截图 2026-10-10 20:08）：左 → 右 = 活动栏 | 导航栏（New notebook / All Notes /
/// Favorites / Recent / Shelf / … / Tags） | 笔记列表列 | 正文 —— 笔记本架占着窗口**最左一整栏**，
/// 且它的入口是树里那枚「＋ 新建笔记本」**文字按钮**。
///
/// ## 这一族判据（`T-20261010-166` §三.2 那四条，逐条对上一个用例）
///
///   ① **无悬停时列表宽度不变**（证「覆盖非挤压」）→ `testRevealedShelfOverlaysWithoutSqueezingTheListColumn`
///   ② **悬停后 frame 重叠且 z 序在上** → 同上（几何的一半）+ `testRevealedShelfCoversTheListColumnPixels`（像素的一半）
///   ③ **移开自动收起** → `testCollapsingTheShelfRestoresTheCollapsedReading`
///   ④ **书架入口 = 图标 + tips（禁文字按钮）** → `testShelfEntryIsAnIconWithTipsAndNeverATextButton`
///   另加 `FR-NOTEUI-01`（笔记列表列位于最左）→ `testNoteListColumnSitsAtTheLeftmostOfTheNotesScreen`
///
/// ## 量法（真几何 / 真像素，不是读源码常量）
///
/// 把 `NotesAreaView`（三栏骨架的真身）挂进一个**不上屏**的 `NSWindow`（`List` / `ScrollView`
/// 这类 AppKit 自持容器只有真窗口宿主里才落地成 `NSView`），泵几轮运行循环让布局落地，然后在
/// **同一个坐标系**（宿主视图）里量矩形、取像素。
///
/// ## 边界（如实登记 · 不许用「代码里有」替代）
///
/// 1. **真的鼠标悬停**不在判据面里：离屏宿主里合成事件不响应（`NotesLayoutProbeTests` 头注释
///    实测三条：上屏 ⇒ `ReminderNotifier` 崩；离屏合成点击 ⇒ SwiftUI 手势不动；渲染取像素要
///    **活宿主**）。所以本文件判的是「**悬停这个动作写进状态之后**界面是什么样」
///    （`AppState.notesShelfRevealed` 是那一档状态的唯一出处，视图两处 `.onHover` 接线由源锚点
///    钉住）。真实鼠标那一下归**实跑的人眼证据**（本单回执的成对截图）。
/// 2. 不判观感（浮层的圆角 / 阴影好不好看）—— 那是设计语言片的对照表。
final class NotesShelfProbeTests: XCTestCase {

    /// 宿主面积：与 `NotesLayoutProbeTests` 逐字同档（够放下三栏）。
    private let areaSize = CGSize(width: 1100, height: 700)

    /// 整窗面积：与真机截图那一档同规格（`1352 × 785`），判 `FR-NOTEUI-01` 用。
    private let windowSize = CGSize(width: 1352, height: 785)

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏渲染要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    private struct HostBundle {
        let state: AppState
        let workspace: WorkspaceStore
        let tabs: WorkspaceTabsModel
        let terminal: TerminalModel
    }

    // MARK: - 装配（口径与 `NotesLayoutProbeTests` 同源）

    @MainActor
    private func makeHost() -> HostBundle {
        let scratch = UISnapshot.outputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let historyURL = scratch.appendingPathComponent("notes-shelf-probe-\(UUID().uuidString).json")

        let state = AppState()
        state.connections = []
        state.selectedConnectionID = nil
        return HostBundle(
            state: state,
            workspace: WorkspaceStore.shared,
            tabs: WorkspaceTabsModel(store: WorkspaceHistoryStore(fileURL: historyURL)),
            terminal: TerminalModel()
        )
    }

    /// 夹具：一条笔记 + 把笔记能力打开（`reloadNotes()` 挂着 `notesEnabled` 那道守卫）。
    ///
    /// **先在临时家里再写**：`DOYAH_NOTES_DIR` 不在场就跳过 —— 探针不许往真实用户数据家写夹具。
    ///
    /// **返回落库后的那一条**，调用点在自己的用例末尾 `await removeSeed(...)` 收掉它：本进程里
    /// 所有笔记用例共用同一个 `DOYAH_NOTES_DIR`，播了不收拾就会把**别的**用例的「库里该有几条」
    /// 读数带偏（`UISnapshotPanelsTests.testNoteSearchGoesThroughTheLibraryAndDisclosesTheRoute`
    /// 与 `QueryHistoryPaneProbeTests` 各有一条这类断言 —— 实测：收拾干净之后两条都回到本色）。
    @MainActor
    @discardableResult
    private func seedOneNote(_ host: HostBundle) async throws -> Note {
        try XCTSkipIf(
            (ProcessInfo.processInfo.environment["DOYAH_NOTES_DIR"] ?? "").isEmpty,
            "本用例要往笔记库写夹具 ⇒ 必须在临时数据家里跑（`DOYAH_NOTES_DIR` 没设就跳过）"
        )
        let load = try UISnapshot.applyLicense(.standard, to: host.state)
        XCTAssertEqual(load.entitlements.basis, .licensed, "临时许可证没落地 ⇒ 下面读不到笔记能力")
        XCTAssertTrue(host.state.notesEnabled, "Standard 档必须带笔记能力（capabilities.notes）")
        return try await NoteLibrary.defaultLibrary().upsert(
            NoteDraft(title: "浮动书架探针夹具", body: "shelf probe")
        )
    }

    /// 收掉自己播的那一条（软删 ⇒ 重读之后 `notes` / `visibleNotes` 里不再有它）。
    private func removeSeed(_ note: Note) async {
        try? await NoteLibrary.defaultLibrary().delete(id: note.id, at: Date())
    }

    /// 活宿主（**不上屏**）：任意视图 + 根部那一套环境注入。
    ///
    /// 与 `NotesLayoutProbeTests.makeLive` 同一套口径（不上屏的理由见那边的头注释：上屏会拉起
    /// `ReminderNotifier`，它在 `xctest` 直跑时没有真 bundle ⇒ 进程 `signal 6`），但仍走
    /// `UISnapshot.LiveHost` —— 取图那一半要用它的 `capture`（非空白判据 / PNG 落盘 / 记录同源）。
    @MainActor
    private func makeLive<V: View>(
        _ host: HostBundle,
        _ view: V,
        size: CGSize? = nil,
        seconds: TimeInterval = 0.6
    ) -> UISnapshot.LiveHost<AnyView> {
        let root = AnyView(
            view.snapshotEnvironment(
                state: host.state,
                workspace: host.workspace,
                tabs: host.tabs,
                terminal: host.terminal
            )
        )
        let live = UISnapshot.LiveHost(root, size: size ?? areaSize, scheme: .light)
        live.pump(seconds)
        return live
    }

    // MARK: - 量法

    @MainActor
    private func rect(of view: NSView, in hosting: NSView) -> CGRect {
        hosting.convert(view.bounds, from: view)
    }

    @MainActor
    private func distanceToTopEdge(_ rect: CGRect, in hosting: NSView) -> CGFloat {
        hosting.isFlipped ? rect.minY : hosting.bounds.height - rect.maxY
    }

    private func pt(_ value: CGFloat) -> String { String(format: "%.1f", value) }

    private func rectText(_ r: CGRect) -> String {
        "x=[\(pt(r.minX))…\(pt(r.maxX))] y=[\(pt(r.minY))…\(pt(r.maxY))] w=\(pt(r.width)) h=\(pt(r.height))"
    }

    /// 宿主里**所有**可读矩形的逐条 dump（`N2-2-EXPLORE` 那一套的同一形状：量到什么就打印什么）。
    @MainActor
    private func dumpMeasurable(_ hosting: NSView, label: String) {
        var count = 0
        for view in UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: hosting) {
            let r = rect(of: view, in: hosting)
            guard !r.isEmpty, r.width > 1, r.height > 1 else { continue }
            count += 1
            print(
                "SHELF-DUMP[\(label)] cls=\(String(describing: type(of: view)))"
                    + " id=\(view.accessibilityIdentifier()) \(rectText(r))"
                    + " top=\(pt(distanceToTopEdge(r, in: hosting)))"
                    + (view.isHiddenOrHasHiddenAncestor ? " [HIDDEN]" : "")
            )
        }
        print("SHELF-DUMP[\(label)] 可读矩形 \(count) 条（宿主 \(pt(hosting.bounds.width))×\(pt(hosting.bounds.height))）")
    }

    /// 三栏骨架里**存放笔记列表的那一列**（＝左那一栏：`NSSplitView` 的子视图按 x 排序取最左）。
    @MainActor
    private func listColumn(_ hosting: NSView) throws -> (view: NSView, frame: CGRect, width: CGFloat) {
        let split = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: NSSplitView.self, in: hosting).first,
            "宿主里没有 `NSSplitView` —— `HSplitView` 没落地，判据量不到「存放笔记列表的那一栏」（入口没了）"
        )
        let ordered = split.subviews
            .map { (view: $0, rect: rect(of: $0, in: hosting)) }
            .filter { $0.rect.width > 8 }
            .sorted { $0.rect.minX < $1.rect.minX }
        let left = try XCTUnwrap(ordered.first, "`HSplitView` 里一个子视图都没量到")
        return (left.view, left.rect, left.rect.width)
    }

    /// 笔记列表本身（`NSTableView`）——判据③「列表内容有没有被重排」用它。
    @MainActor
    private func noteTable(_ hosting: NSView) throws -> NSTableView {
        try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: NSTableView.self, in: hosting).first,
            "笔记列表没落地成 `NSTableView` ⇒ 判据量不到列表"
        )
    }

    @MainActor
    private func noteTableOrNil(_ hosting: NSView) -> NSTableView? {
        UISnapshot.LiveHost<Never>.findViews(ofType: NSTableView.self, in: hosting).first
    }

    /// **导航侧栏那一格**在不在（按落地出来的承载视图类型名找）。
    ///
    /// `NavigationSplitView` 的侧栏在 AppKit 里落地成
    /// `NSHostingView<ModifiedContent<ColumnView, NavigationPaneModifier<SidebarStyleContext>>>` ——
    /// 详情那一栏的类型名里是 `ContainerStyleContext`。用类型名而不是尺寸，是为了不被
    /// 「侧栏宽度恰好等于谁」这种巧合骗到（`FR-NOTEUI-01` 要判的是**那一格在不在**）。
    ///
    /// 只数**没被藏起来**的（`isHiddenOrHasHiddenAncestor == false`）：收起态里 AppKit 可能把那一格
    /// 整个拆掉、也可能只藏起来 —— 两种都算「不在」。
    @MainActor
    private func sidebarColumnViews(_ hosting: NSView) -> [NSView] {
        UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: hosting)
            .filter { String(describing: type(of: $0)).contains("SidebarStyleContext") }
            .filter { !$0.isHiddenOrHasHiddenAncestor }
    }

    /// 宿主里**所有 `NSScrollView`**（按穿越序）。
    ///
    /// 用途：浮层里那一条 `ScrollView`（`NotesShelfPanel`）是**新出现的**那一条 ——
    /// 「浮出前后取差集」比「按名字猜哪一条是浮层」稳（浮层的 `accessibilityIdentifier` 不保证
    /// 落到某个具体 `NSView` 上；差集是**观测**出来的）。
    @MainActor
    private func scrollViews(_ hosting: NSView) -> [NSScrollView] {
        UISnapshot.LiveHost<Never>.findViews(ofType: NSScrollView.self, in: hosting)
    }

    /// 取差集：`after` 里有、`before` 里没有（按**对象身份**判 —— 矩形相等不算同一件，见下面
    /// `traversalIndex` 那一处的实测：浮层的矩形与列表那一栏**逐点相同**）。
    private func newViews(after: [NSScrollView], before: [NSScrollView]) -> [NSScrollView] {
        after.filter { candidate in !before.contains { $0 === candidate } }
    }

    /// 穿越序里某个**视图**的下标（AppKit 按子视图顺序**后画在上** ⇒ 下标大 = z 序在上）。
    ///
    /// **按对象身份找，不按矩形找**：本片实测浮层的矩形与列表那一栏**逐点相同**
    /// （`x=[0…238] y=[33…700]`，那正是「盖在它上面」的几何形状）—— 按矩形找会把两层命中成
    /// 同一件、判据当场变成恒真（`14 ≤ 14`）。所以入口必须是那一件视图自己。
    @MainActor
    private func traversalIndex(of target: NSView, in hosting: NSView) -> Int? {
        UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: hosting).firstIndex { $0 === target }
    }

    // MARK: - 判据① + ②（几何那半）：浮出**不挤压**列表那一栏，且浮层**压在**它上面

    /// **判据①**「无悬停时列表宽度不变（证覆盖非挤压）」+ **判据②**「悬停后 frame 重叠且 z 序在上」
    /// 里**几何**的那一半。
    ///
    /// ## 成对读数（同一轮、同一个活宿主上的两态）
    ///
    ///   ① 收起态（`notesShelfRevealed == false`）：量「存放笔记列表的那一栏」的**整列宽度**与
    ///      列表 `NSTableView` 的矩形，并把宿主里所有可读矩形 dump 出来（`SHELF-DUMP[before]`）；
    ///   ② 摆到「悬停后」那一档（`AppState.setNotesShelfRevealed(true)` —— 与视图里 `.onHover`
    ///      写的是**同一个入口**），泵两轮让布局与绘制落地；
    ///   ③ 再量同一组：**整列宽度必须逐点相同**（判据①）；浮层那一条 `NSScrollView`（取差集得到）
    ///      的矩形必须与列表那一栏**相交**（判据② 的「重叠」），且它的穿越序**大于**列表那一栏
    ///      （判据② 的「z 序在上」：AppKit 按子视图顺序后画在上）。
    ///
    /// ## 判据能判红
    ///
    /// · 若浮层改成「`HStack` 里加一栏」（＝挤压式），第 ③ 步的整列宽度当场变小 ⇒ 判据① 红；
    /// · 若浮层挂到了别处（不在列表那一栏上），第 ③ 步的相交 / 序位判据红；
    /// · 「一条新的 `NSScrollView` 都没出现」⇒ 浮层压根没画出来 ⇒ 红（不许悄悄跳过）。
    @MainActor
    func testRevealedShelfOverlaysWithoutSqueezingTheListColumn() async throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let fixture = try await seedOneNote(host)
        await host.state.reloadNotes()
        XCTAssertFalse(host.state.visibleNotes.isEmpty, "夹具没进列表 ⇒ 判据量不到「列表那一栏」")

        let live = makeLive(host, NotesAreaView())

        // ── ① 收起态 ────────────────────────────────────────────────────────────────
        let beforeColumn = try listColumn(live.hosting)
        let beforeTable = try noteTable(live.hosting)
        let beforeTableFrame = rect(of: beforeTable, in: live.hosting)
        let beforeScrolls = scrollViews(live.hosting)
        dumpMeasurable(live.hosting, label: "before")
        print(
            "SHELF-① 收起态：列表那一栏 \(rectText(beforeColumn.frame))"
                + "｜列表 \(rectText(beforeTableFrame))（\(beforeTable.numberOfRows) 行）"
                + "｜`NSScrollView` \(beforeScrolls.count) 条"
        )

        // ── ② 摆到「悬停后」那一档（与视图里 `.onHover` 同一个写入口）──────────────────
        host.state.setNotesShelfRevealed(true)
        live.pump(0.4)
        XCTAssertTrue(host.state.notesShelfRevealed, "状态没摆到「悬停后」那一档 —— 下面量的还是收起态")

        // ── ③ 再量同一组 ────────────────────────────────────────────────────────────
        let afterColumn = try listColumn(live.hosting)
        let afterTable = try noteTable(live.hosting)
        let afterTableFrame = rect(of: afterTable, in: live.hosting)
        let afterScrolls = scrollViews(live.hosting)
        let fresh = newViews(after: afterScrolls, before: beforeScrolls)
        dumpMeasurable(live.hosting, label: "after")

        print(
            "SHELF-①② 浮出态：列表那一栏 \(rectText(afterColumn.frame))"
                + "｜列表 \(rectText(afterTableFrame))（\(afterTable.numberOfRows) 行）"
                + "｜`NSScrollView` \(afterScrolls.count) 条（新出现 \(fresh.count) 条）"
        )

        // 判据①：整列宽度不变（覆盖非挤压）。
        XCTAssertEqual(
            afterColumn.width, beforeColumn.width, accuracy: 0.5,
            "浮出前后**列表那一栏的整列宽度**变了（\(pt(beforeColumn.width))pt → \(pt(afterColumn.width))pt）"
                + " —— 那是「挤压」，判据①（覆盖非挤压）量到的就是它"
        )
        XCTAssertEqual(
            afterTableFrame.width, beforeTableFrame.width, accuracy: 0.5,
            "浮出前后列表自己的宽度变了（\(pt(beforeTableFrame.width))pt → \(pt(afterTableFrame.width))pt）"
        )
        XCTAssertEqual(
            afterTable.numberOfRows, beforeTable.numberOfRows,
            "浮出前后列表的行数变了 —— 浮层不该动列表的数据"
        )

        // 判据②（几何半）：浮层确实画出来了（新出现一条 `NSScrollView`）。
        let panelView = try XCTUnwrap(
            fresh.count == 1 ? fresh[0] : nil,
            "浮出态里新出现的 `NSScrollView` 不是**恰一条**（实测 \(fresh.count) 条："
                + "\(fresh.map { rectText(rect(of: $0, in: live.hosting)) })）"
                + " —— 判据不成立（浮层没画出来 / 画出了两片）"
        )
        let panel = rect(of: panelView, in: live.hosting)
        print("SHELF-② 浮层（新出现的 `NSScrollView`）：\(rectText(panel))")

        // 判据②（几何半）：frame 重叠。
        XCTAssertTrue(
            panel.intersects(beforeColumn.frame),
            "浮层的矩形与「列表那一栏」不相交：浮层 \(rectText(panel)) vs 列表栏 \(rectText(beforeColumn.frame))"
        )
        // 浮层的左缘与上缘要压在列表那一栏的左缘与上缘上（它就是从那一栏左上角浮出来的）。
        XCTAssertEqual(
            panel.minX, beforeColumn.frame.minX, accuracy: 2,
            "浮层没贴在列表那一栏的左缘（\(pt(panel.minX)) vs \(pt(beforeColumn.frame.minX))）"
        )
        XCTAssertLessThanOrEqual(
            distanceToTopEdge(panel, in: live.hosting), distanceToTopEdge(beforeColumn.frame, in: live.hosting) + 2,
            "浮层没有从列表那一栏的**上缘**浮出（top \(pt(distanceToTopEdge(panel, in: live.hosting)))"
                + " > 列表栏 \(pt(distanceToTopEdge(beforeColumn.frame, in: live.hosting)))）"
        )

        // 判据②（z 序半）：浮层在列表那一栏**之后**被画（AppKit 子视图顺序：后画在上）。
        let panelIndex = try XCTUnwrap(
            traversalIndex(of: panelView, in: live.hosting),
            "浮层那一件视图在穿越序里找不到 —— 判据的入口没了"
        )
        let columnIndex = try XCTUnwrap(
            traversalIndex(of: beforeColumn.view, in: live.hosting),
            "列表那一栏那一件视图在穿越序里找不到 —— 判据的入口没了"
        )
        print("SHELF-② z 序：列表栏 index=\(columnIndex) ｜ 浮层 index=\(panelIndex)（大的画在上）")
        XCTAssertGreaterThan(
            panelIndex, columnIndex,
            "浮层在穿越序里排在列表那一栏**之前**（\(panelIndex) ≤ \(columnIndex)）⇒ 它是被压在下面的那一层"
        )

        await removeSeed(fixture)
    }

    // MARK: - 判据②（像素那半）：浮出把列表那一栏**盖住**（画在上）

    /// **判据②** 的另一半：**像素**。
    ///
    /// 几何那半证的是「矩形相交」；相交不等于**盖住**（半透明 / 落在下面同样能相交）。这一条取
    /// 浮出前后两张**真像素**，只看「列表那一栏」那一条竖带：两态必须**画得不一样**；再与上一条
    /// 的「整列宽度不变」合起来 —— 宽度没变而像素变了 ⇒ 唯一解释是**画在上面**（覆盖），
    /// 不是把列表挤走。
    ///
    /// 两条读数都 `print`：`differingPixels` 与其占那条带的比例（判据即证据）。
    @MainActor
    func testRevealedShelfCoversTheListColumnPixels() async throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let fixture = try await seedOneNote(host)
        await host.state.reloadNotes()

        let live = makeLive(host, NotesAreaView())
        let column = try listColumn(live.hosting)

        // 成对截图：两态 × 两语言 = 四张（`captureBothLanguages` 会加 `-zh` / `-en` 后缀）。
        let collapsedRecords = try live.captureBothLanguages(name: "noteui-02-shelf-collapsed")
        host.state.setNotesShelfRevealed(true)
        live.pump(0.4)
        let revealedRecords = try live.captureBothLanguages(name: "noteui-02-shelf-revealed")

        // 像素那半只看中文那一遍（同一张图的同一块区域，语言不影响这一条判据）。
        let collapsedRecord = try XCTUnwrap(collapsedRecords.first, "收起那张没拍出来")
        let revealedRecord = try XCTUnwrap(revealedRecords.first, "浮出那张没拍出来")

        let scale = 2
        let width = Int((column.width * CGFloat(scale)).rounded())
        let beforeBand = try XCTUnwrap(
            UISnapshot.columnBand(ofPNGAt: collapsedRecord.file, fromLeading: 0, width: width),
            "取不到「列表那一栏」那条竖带（收起那张）"
        )
        let afterBand = try XCTUnwrap(
            UISnapshot.columnBand(ofPNGAt: revealedRecord.file, fromLeading: 0, width: width),
            "取不到「列表那一栏」那条竖带（浮出那张）"
        )
        let differing = try XCTUnwrap(
            UISnapshot.differingPixels(beforeBand, afterBand),
            "两条带的尺寸不一致 —— 判据量不到「同一条带」"
        )
        let ratio = Double(differing) / Double(beforeBand.pixelCount)
        print(
            "SHELF-② 像素：列表那一栏竖带 \(width)px 宽 ｜ 差异 \(differing)/\(beforeBand.pixelCount) px"
                + "（\(String(format: "%.3f", ratio))）｜ 收起那张墨迹 \(beforeBand.ink) / 浮出那张 \(afterBand.ink)"
        )

        // 阈值留了余量：本机实测「1 条笔记」那档 4.6%、「8 条」那档 9.7% ⇒ 取 2%（那条带 1/50 的像素
        // 变了就已经远超抗锯齿级的噪声，而「没盖住」那一档是 0）。
        XCTAssertGreaterThan(
            differing, beforeBand.pixelCount / 50,
            "浮出前后「列表那一栏」那一条竖带几乎没有变化（差异 \(differing)/\(beforeBand.pixelCount)）。"
                + "宽度上一条已经判过没变 ⇒ 这里没变化只有一个解释：浮层没盖在它上面"
        )

        await removeSeed(fixture)
    }

    // MARK: - 判据③：移开自动收起（两态回到同一读数）

    /// **判据③**「移开自动收起」：收与放**各自**回到同一读数，且收起之后浮层**真的没了**。
    ///
    /// 三档读数（同一活宿主、同一条口径）：
    ///   · `收起 → 浮出 → 收起`，第 1 与第 3 档的「列表那一栏」矩形必须**逐点相同**（收干净了）；
    ///   · 第 3 档里那条「浮出 `NSScrollView`」必须**消失**（不是只变透明 / 只不响应点击）；
    ///   · 源锚点：「移开 ⇒ 收起」的唯一写入口 = 覆盖层自己那一处 `.onHover`
    ///     （`AppState.setNotesShelfRevealed($0)`）—— 离屏宿主里没法定「鼠标移开」这个动作，
    ///     所以这一半只能钉接线（口径同既有探针的「源锚点」做法）。
    @MainActor
    func testCollapsingTheShelfRestoresTheCollapsedReading() async throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let fixture = try await seedOneNote(host)
        await host.state.reloadNotes()

        let live = makeLive(host, NotesAreaView())

        let first = try listColumn(live.hosting)
        let firstScrolls = scrollViews(live.hosting)

        host.state.setNotesShelfRevealed(true)
        live.pump(0.4)
        let open = try listColumn(live.hosting)
        let openScrolls = scrollViews(live.hosting)
        XCTAssertEqual(
            newViews(after: openScrolls, before: firstScrolls).count, 1,
            "浮出态里没量到浮层那一条"
        )

        host.state.setNotesShelfRevealed(false)
        live.pump(0.4)
        let closed = try listColumn(live.hosting)
        let closedScrolls = scrollViews(live.hosting)
        let stragglers = newViews(after: closedScrolls, before: firstScrolls)

        print(
            "SHELF-③ 收放三档：列表那一栏 收起 \(rectText(first.frame)) → 浮出 \(rectText(open.frame)) →"
                + " 再收起 \(rectText(closed.frame)) ｜ 浮层残留 \(stragglers.count) 条"
        )

        XCTAssertEqual(
            closed.frame.minX, first.frame.minX, accuracy: 0.5,
            "再收起之后列表那一栏没回到原处（minX \(pt(first.frame.minX)) → \(pt(closed.frame.minX))）"
        )
        XCTAssertEqual(
            closed.frame.width, first.frame.width, accuracy: 0.5,
            "再收起之后列表那一栏的宽度没回到原值（\(pt(first.frame.width)) → \(pt(closed.frame.width))）"
        )
        XCTAssertTrue(
            stragglers.isEmpty,
            "收起之后浮层那一条 `NSScrollView` 还在（\(stragglers.map { rectText(rect(of: $0, in: live.hosting)) })）"
        )

        // 源锚点：**唯一**的「移开 ⇒ 收起」写入点。
        let source = try notesPanelSource()
        let panelBlock = try XCTUnwrap(
            Self.block(named: "struct NotesShelfPanel", in: source),
            "`NotesPanel.swift` 里找不到 `struct NotesShelfPanel` —— 浮层那一层没落地"
        )
        XCTAssertTrue(
            source.contains(".onHover { appState.setNotesShelfRevealed($0) }"),
            "没有找到「覆盖层的 `.onHover` 两态都写」的那一处接线 —— 「移开自动收起」没有入口"
        )
        XCTAssertFalse(
            panelBlock.contains(".onHover"),
            "`NotesShelfPanel` 自己挂了 `.onHover` —— 两态接线散进浮层里了（接线只许在挂它的那一处）"
        )

        await removeSeed(fixture)
    }

    // MARK: - 判据④：书架入口 = 图标 + tips（禁文字按钮）

    /// **判据④**「书架入口 = 图标 + tips（禁文字按钮）」。
    ///
    /// 两条腿：
    ///   · **负半（真视图）**：活宿主里**不存在**任何把那一句提示当**可见文字**画出来的控件
    ///     —— `NSButton` / `NSSegmentedControl` 的标题里都不许出现「笔记本架」（英文那遍是
    ///     「Shelf」）。改前那一枚是「＋ 新建笔记本」**文字按钮**，正落在这一条上。
    ///   · **源锚点（入口那一枚的形状）**：`shelfEntry` 那一块里必须有 `ToolbarIconButton`（本工程
    ///     里纯图标按钮的唯一出处，`help` 是**构造参数** ⇒ 有图标必有提示）与
    ///     `help: L(.notesShelfEntry)`，且**不许**出现 `Text(` / `Label(` —— 也就是「图标 + tips」，
    ///     不是文字按钮。
    ///   · **单点**：`L(.notesShelfEntry)` 在 `NotesPanel.swift` 里**恰好出现一次**（就在 `help:` 上
    ///     —— 提示与无障碍标签同一句，不另写第二个版本）。
    @MainActor
    func testShelfEntryIsAnIconWithTipsAndNeverATextButton() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let live = makeLive(host, NotesAreaView())

        // 负半：真视图里不许有把那句提示当标题画出来的控件。
        let label = UISnapshot.localizedText(.simplifiedChinese) { L(.notesShelfEntry) }
        let englishLabel = UISnapshot.localizedText(.english) { L(.notesShelfEntry) }
        let buttons = UISnapshot.LiveHost<Never>.findViews(ofType: NSButton.self, in: live.hosting)
        let segments = UISnapshot.LiveHost<Never>.findViews(ofType: NSSegmentedControl.self, in: live.hosting)
            .flatMap { control -> [String] in
                guard let cell = control.cell as? NSSegmentedCell else { return [] }
                return (0..<cell.segmentCount).map { cell.label(forSegment: $0) ?? "" }
            }
        let titled = buttons.map(\.title) + segments
        let offenders = titled.filter { $0.contains(label) || $0.contains(englishLabel) }
        print(
            "SHELF-④ 真视图里带标题的控件 \(titled.count) 枚（`NSButton` \(buttons.count) 枚 / 分段标签 \(segments.count) 条）"
                + "｜命中「\(label)」的 \(offenders.count) 枚：\(offenders)"
        )
        XCTAssertTrue(
            offenders.isEmpty,
            "书架入口被画成了**文字按钮**（标题命中「\(label)」：\(offenders)）—— `FR-NOTEUI-03` 禁的正是它"
        )

        // 源锚点。
        let source = try notesPanelSource()
        let entry = try XCTUnwrap(
            Self.block(named: "private var shelfEntry", in: source),
            "`NotesPanel.swift` 里找不到 `shelfEntry` —— 书架入口没落地"
        )
        XCTAssertTrue(entry.contains("ToolbarIconButton("), "书架入口不是 `ToolbarIconButton`（纯图标按钮的唯一出处）")
        XCTAssertTrue(entry.contains("help: L(.notesShelfEntry)"), "书架入口没有悬停提示（`help:` 是构造参数，漏了编译不过）")
        XCTAssertTrue(entry.contains(".accessibilityIdentifier(\"notes-shelf-entry\")"), "书架入口没有判定入口标识")
        XCTAssertTrue(entry.contains("systemName: NotesAreaView.shelfSymbol"), "书架入口的符号不是与树里「架」同一枚")
        XCTAssertFalse(entry.contains("Text("), "书架入口那一块里出现了 `Text(` —— 形态滑回文字按钮了")
        XCTAssertFalse(entry.contains("Label("), "书架入口那一块里出现了 `Label(` —— 形态滑回文字按钮了")

        let occurrences = source.components(separatedBy: ".notesShelfEntry").count - 1
        print("SHELF-④ 源锚点：`shelfEntry` 有 `ToolbarIconButton` + `help:` + 标识；`.notesShelfEntry` 在 NotesPanel.swift 出现 \(occurrences) 次")
        XCTAssertEqual(
            occurrences, 1,
            "`L(.notesShelfEntry)` 在 `NotesPanel.swift` 里出现 \(occurrences) 次（要求恰好 1 次：提示与无障碍标签同一句）"
        )
    }

    // MARK: - FR-NOTEUI-01：笔记列表列位于最左

    /// **`FR-NOTEUI-01` 笔记列表列位于最左**（成对读数 · 同一轮两件在位）。
    ///
    /// 量的是**真窗口**里「笔记列表那一列的左缘 x」：
    ///   · **改后（生产）** = `MainWindow` + `selectActivityItem(.notes)`：笔记屏里侧栏那一格是
    ///     `.detailOnly`（`MainWindow.syncSidebarVisibility`）⇒ 列表那一列直接贴在**活动栏**右边；
    ///   · **改前（复刻件）** = 同一副窗口骨架，但侧栏照旧摆着两级树
    ///     （`NavigationSplitView { NebulaSurface { NotesContainerTreeView() } } detail { NotesAreaView() }`）
    ///     ⇒ 列表被推到 活动栏 + `Metrics.sidebarWidth` 之后。
    ///
    /// 判据：**改后 ≈ 活动栏宽（`Metrics.activityBarWidth`）**，改前 ≈ 活动栏 + 238~248。两个读数
    /// 必须**明显不同**（否则「成对」不成立，这一条会变成恒真）。
    ///
    /// ## 边界
    ///
    /// · `selectActivityItem` 会写 `UserDefaults`（产品真实行为）⇒ 本用例**先存后还原**该键
    ///   （口径同 `PaletteWiringProbeTests`）；跑在 `swift test` 进程自己的域里，碰不到 App 的偏好。
    /// · 不判「列表栏是不是窄了」—— 那是 `N2-LW` 的既有判据（`NotesLayoutProbeTests`）。
    @MainActor
    func testNoteListColumnSitsAtTheLeftmostOfTheNotesScreen() async throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let fixture = try await seedOneNote(host)
        await host.state.reloadNotes()

        // 活动项那一格写 `UserDefaults`（产品真实行为）⇒ 先存后还原。
        let key = ActivityBarItem.storageKey
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        host.state.selectActivityItem(.notes)
        XCTAssertEqual(host.state.selectedActivityItem, .notes, "活动项没切到笔记屏 ⇒ 下面两条读数比不了")

        // ── 改后：生产那一份 ────────────────────────────────────────────────────────
        let after = makeLive(host, MainWindow(), size: windowSize, seconds: 0.8)
        // 侧栏那一格的收起是**异步**发生的（`MainWindow.task` 里同步可见性 ⇒ 布局重排）⇒
        // 等它落地再量（口径同「等真异步用 `pump(until:)`」；不等就量到的是中间态）。
        let leftmostLimit = Metrics.activityBarWidth + 40
        _ = after.pump(
            until: {
                guard let table = self.noteTableOrNil(after.hosting) else { return false }
                return self.rect(of: table, in: after.hosting).minX <= leftmostLimit
                    && self.sidebarColumnViews(after.hosting).isEmpty
            },
            timeout: 8
        )
        let afterTable = try noteTable(after.hosting)
        let afterFrame = rect(of: afterTable, in: after.hosting)
        let afterSidebar = sidebarColumnViews(after.hosting)
        dumpMeasurable(after.hosting, label: "leftmost-after")

        // ── 改前：同一副骨架 + 侧栏里那份真内容（`MainWindow.swift` 侧栏那一支的原样）────────
        let before = makeLive(
            host,
            HStack(spacing: 0) {
                ActivityBarView()
                NavigationSplitView {
                    NebulaSurface(surface: .sidebar, layer: .sidebar) {
                        NotesContainerTreeView()
                    }
                    .navigationSplitViewColumnWidth(
                        min: Metrics.sidebarWidth, ideal: Metrics.sidebarWidth, max: Metrics.sidebarWidth
                    )
                } detail: {
                    NotesAreaView()
                }
            },
            size: windowSize,
            seconds: 0.8
        )
        let beforeTable = try noteTable(before.hosting)
        let beforeFrame = rect(of: beforeTable, in: before.hosting)
        let beforeSidebar = sidebarColumnViews(before.hosting)

        print(
            "SHELF-FR-NOTEUI-01 笔记列表那一列的左缘（整窗 \(pt(windowSize.width))×\(pt(windowSize.height))）："
                + "改前 \(pt(beforeFrame.minX))pt → 改后 \(pt(afterFrame.minX))pt"
                + "（活动栏宽 \(pt(Metrics.activityBarWidth))pt，侧栏宽 \(pt(Metrics.sidebarWidth))pt）"
        )
        print("SHELF-FR-NOTEUI-01 列表栏矩形：改前 \(rectText(beforeFrame)) ｜ 改后 \(rectText(afterFrame))")
        print(
            "SHELF-FR-NOTEUI-01 侧栏那一格（`SidebarStyleContext`）：改前 \(beforeSidebar.count) 个"
                + "（\(beforeSidebar.map { rectText(rect(of: $0, in: before.hosting)) })）｜ 改后 \(afterSidebar.count) 个"
        )

        // 改后：侧栏那一格**不在**了（笔记屏不再固定占那一栏）。
        XCTAssertTrue(
            afterSidebar.isEmpty,
            "笔记屏里导航侧栏那一格还在（\(afterSidebar.map { rectText(rect(of: $0, in: after.hosting)) })）"
                + " —— `FR-NOTEUI-01`「笔记列表列位于最左」量到的就是它"
        )
        // 改前那条读数：侧栏在 ⇒ 列表被推后（这条同时是「对照件成立」的证明）。
        XCTAssertFalse(
            beforeSidebar.isEmpty,
            "改前复刻件里量不到侧栏那一格 —— 对照件不成立，下面那条比不出东西"
        )
        XCTAssertGreaterThanOrEqual(
            beforeFrame.minX, Metrics.activityBarWidth + Metrics.sidebarWidth - 8,
            "改前复刻件里列表没被侧栏推后（\(pt(beforeFrame.minX))pt）—— 对照件不成立，下面那条比不出东西"
        )
        // 判据：改后列表直接贴活动栏（侧栏那一格不再占位）。
        XCTAssertFalse(
            afterTable.isHiddenOrHasHiddenAncestor,
            "改后量到的笔记列表被藏起来了 ⇒ 那一列没有真的落在最左"
        )
        XCTAssertLessThanOrEqual(
            afterFrame.minX, leftmostLimit,
            "笔记屏里笔记列表那一列没有贴到最左（左缘 \(pt(afterFrame.minX))pt ＞ 活动栏 \(pt(Metrics.activityBarWidth)) + 容差 40）"
                + " —— 侧栏那一格还在固定占位（`FR-NOTEUI-01`「笔记列表列位于最左」量到的就是它）"
        )
        XCTAssertLessThan(
            afterFrame.minX, beforeFrame.minX - Metrics.sidebarWidth / 2,
            "改前 / 改后量到的位置几乎一样（\(pt(beforeFrame.minX)) → \(pt(afterFrame.minX))）⇒ 这一对读数是恒真的"
        )

        await removeSeed(fixture)
    }

    // MARK: - 源自证

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func notesPanelSource() throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent("App/Views/NotesPanel.swift"), encoding: .utf8)
    }

    /// 从源码里抠出一段（从 `marker` 那一行到与之匹配的**顶层** `}`）。拿去当源锚点的范围。
    private static func block(named marker: String, in source: String) -> String? {
        let lines = source.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(marker)
        }) else { return nil }
        var depth = 0
        var out: [String] = []
        for line in lines[start...] {
            out.append(line)
            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth == 0, out.count > 1 { break }
        }
        return out.joined(separator: "\n")
    }
}
