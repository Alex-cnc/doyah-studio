import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **笔记面「左区骨架」的几何判据**（片 `N2-1` · 人类主人令 `T-20261007-004` 第三节第 1 / 2 条）。
///
/// ## 由头（人类主人 2026-10-07 07:0x 逐字）
///
/// 「**笔记和代办的增删查改的所有操作都应该是在左侧区域顶部，笔记和代办的切换才放最右侧**」
/// —— 这一条不是观感偏好，它有两个**可以量**的几何承诺：
///
/// 1. **切换控件贴在最右**：`Notes | Todos` 那一枚分段开关的**右边缘**必须落在**左区行
///    （左区顶部那一条操作行）的右边缘**上（判据①，容差 ±4 pt：分段控件自身描边那点余量）；
/// 2. **增删查改入口行在列表之上**：CRUD 那一行的**下边缘**必须高于笔记列表**首行的上边缘**
///    （判据②）—— 否则「入口在顶部」只是措辞，界面照旧把入口画在别处。
///
/// ## 量法（真几何，不是读源码常量）
///
/// 把 `NotesAreaView` 挂进一个**不上屏**的 `NSWindow`（`App/Views` 里那套视图是 AppKit 落地的：
/// 分段开关 = `NSSegmentedControl`、列表 = `NSTableView`），泵几轮运行循环让布局落地，
/// 然后在**同一个坐标系**（宿主视图）里量两个矩形。不渲染位图、不开真窗口抢前台、不需要人在场。
///
/// ## 判据能判红（否则「量不动」会被读成「都对」）
///
/// · ① 反例是**改动前**的界面本身：那时切换控件在第一格（左区最左），右边缘离左区行右边缘差着
///   整条行宽 ⇒ Δ 远大于 4，本判据当场红；
/// · ② 反例同源：那时 CRUD 那一枚「新建」画在行的**最右**、且列表里还没有「首行」的概念
///   —— 本判据量的是「入口行的下边缘」与「列表首行的上边缘」，两者一旦倒置就红；
/// · 还有第三条**前提断言**：列表里**必须真的有行**（夹具没进列表 ⇒ 判据量不到 ⇒ 直接红，
///   不许悄悄跳过 —— 跳过会被读成通过）。
///
/// ## 边界（如实登记）
///
/// · 量的是**应用内**的左区骨架，不是 AppKit 窗口标题栏那一层；
/// · 判据②里的「列表首行」取的是 `List` 落地出来的 `NSTableView` 的第 0 行，**不是**用户拖动
///   分栏之后的像素（那是 `HSplitView` 的持久化宽度，本片不动它）；
/// · 不判观感（配色 / 圆角 / 间距好不好看）—— 那是 `N2-2` 的对照表与设计语言片；
/// · 不碰用户数据：笔记库由取证脚本 `DOYAH_NOTES_DIR` 指到每轮清空的临时目录
///   （没设就 `XCTSkip` 并写明理由，绝不往真实数据家里写夹具 —— 与 `UISnapshotPanelsTests` 同一条纪律）。
final class NotesLayoutProbeTests: XCTestCase {

    /// 宿主面积：够放下三栏（侧栏 248 + 列表 + 正文），也够让顶栏完整铺开。
    private let areaSize = CGSize(width: 1100, height: 700)

    /// 判据①的容差（pt）：分段控件自身描边 / 对齐余量。
    private let tolerance: CGFloat = 4

    private struct HostBundle {
        let state: AppState
        let workspace: WorkspaceStore
        let tabs: WorkspaceTabsModel
        let terminal: TerminalModel
    }

    // MARK: - 装配

    @MainActor
    private func makeHost() -> HostBundle {
        let scratch = UISnapshot.outputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let historyURL = scratch.appendingPathComponent("notes-layout-probe-\(UUID().uuidString).json")

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

    /// 夹具一条笔记 + 把笔记能力打开（`reloadNotes()` 挂着 `notesEnabled` 那道守卫）。
    ///
    /// **先在临时家里再写**：`DOYAH_NOTES_DIR` 不在场就跳过 —— 探针不许往真实用户数据家写夹具。
    @MainActor
    private func seedOneNote(_ host: HostBundle) async throws {
        try requireIsolatedNotesDirectory()
        let load = try UISnapshot.applyLicense(.standard, to: host.state)
        XCTAssertEqual(load.entitlements.basis, .licensed, "临时许可证没落地 ⇒ 下面读不到笔记能力")
        XCTAssertTrue(host.state.notesEnabled, "Standard 档必须带笔记能力（capabilities.notes）")
        _ = try await NoteLibrary.defaultLibrary().upsert(NoteDraft(title: "左区骨架探针夹具", body: "probe"))
    }

    /// 「夹具要写笔记库」的前置：口径与 `UISnapshotPanelsTests` 同一条。
    private func requireIsolatedNotesDirectory() throws {
        try XCTSkipIf(
            (ProcessInfo.processInfo.environment["DOYAH_NOTES_DIR"] ?? "").isEmpty,
            "本用例要往笔记库写夹具 ⇒ 必须在临时数据家里跑（`DOYAH_NOTES_DIR` 没设就跳过）—— "
                + "取证脚本 `Scripts/run-manual-verification-probes.sh` 会设它"
        )
    }

    /// 活窗口（**不上屏**）：`NotesAreaView` + 根部那一套环境注入，泵几轮让布局落地。
    @MainActor
    private func makeLive(_ host: HostBundle, seconds: TimeInterval = 0.6) -> (window: NSWindow, hosting: NSHostingView<AnyView>) {
        let appearance = NSAppearance(named: .aqua)
        let root = AnyView(
            NotesAreaView().snapshotEnvironment(
                state: host.state,
                workspace: host.workspace,
                tabs: host.tabs,
                terminal: host.terminal
            )
        )
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = appearance
        hosting.frame = CGRect(origin: .zero, size: areaSize)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: areaSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.isReleasedWhenClosed = false
        window.contentView = hosting

        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            window.layoutIfNeeded()
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        return (window, hosting)
    }

    // MARK: - 量法（宿主坐标系，翻不翻转都得出同一个结论）

    /// 某个 AppKit 视图在宿主坐标系里的矩形。
    @MainActor
    private func rect(of view: NSView, in hosting: NSView) -> CGRect {
        hosting.convert(view.bounds, from: view)
    }

    /// 矩形**上边缘**离宿主顶边多远（与翻转无关的「谁在上面」）。
    @MainActor
    private func distanceToTopEdge(_ rect: CGRect, in hosting: NSView) -> CGFloat {
        hosting.isFlipped ? rect.minY : hosting.bounds.height - rect.maxY
    }

    /// 矩形**下边缘**离宿主顶边多远。
    @MainActor
    private func distanceToBottomEdge(_ rect: CGRect, in hosting: NSView) -> CGFloat {
        hosting.isFlipped ? rect.maxY : hosting.bounds.height - rect.minY
    }

    private func pt(_ value: CGFloat) -> String { String(format: "%.1f", value) }

    /// 顶栏里那一枚**笔记 / 待办切换**：按**分段标签**挑，不靠遍历顺序。
    ///
    /// 为什么不取「第一个 `NSSegmentedControl`」：顶栏里还有「作用域」那一枚（`notes-search-scope`），
    /// 左区里还有「清单 / 日历」那一枚 —— 按顺序取会在任何一次重排之后量错东西（`UISnapshotKit`
    /// 里那条「一次拿全部、按文案挑」的同一课）。
    @MainActor
    private func moduleSwitchControl(in hosting: NSView) throws -> NSSegmentedControl {
        let labels = NotesModule.allCases.map { L($0.titleKey) }
        let candidates = UISnapshot.LiveHost<Never>.findViews(ofType: NSSegmentedControl.self, in: hosting)
        let control = candidates.first { candidate in
            (0..<candidate.segmentCount).map { candidate.label(forSegment: $0) ?? "" } == labels
        }
        return try XCTUnwrap(
            control,
            "顶栏里找不到「\(labels.joined(separator: " / "))」那一枚分段开关（找到 \(candidates.count) 枚分段控件）"
                + " —— 判据的入口没了，先核对界面再改这条"
        )
    }

    // MARK: - 判据① 切换控件右边缘 = 左区行右边缘（±4 pt）

    @MainActor
    func testModuleSwitchRightEdgeMatchesTheLeftAreaRowRightEdge() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let live = makeLive(host)

        let control = try moduleSwitchControl(in: live.hosting)
        let switchRect = rect(of: control, in: live.hosting)
        // 「左区行」= 左区顶部那一条操作行：它铺满笔记区宽度（行本身不设右侧留白），
        // 所以**行的右边缘 = 宿主的右边缘**。这一条量的是「切换控件是不是真的贴在它上面」。
        let rowRight = live.hosting.bounds.maxX
        let delta = abs(switchRect.maxX - rowRight)
        print("NOTES-LAYOUT ① 切换控件右边缘 \(pt(switchRect.maxX))pt ｜ 左区行右边缘 \(pt(rowRight))pt ⇒ Δ \(pt(delta))pt（容差 \(pt(tolerance))）")

        XCTAssertLessThanOrEqual(
            delta, tolerance,
            "切换控件没贴在左区行的右边缘上：Δ \(pt(delta))pt > \(pt(tolerance))pt"
                + "（切换控件右边缘 \(pt(switchRect.maxX)) / 行右边缘 \(pt(rowRight))）"
                + " —— 「笔记和待办的切换放最右侧」这条要求①量到的就是它"
        )

        // 反向（「最右侧」的另一半）：同一行里不许有别的控件伸到它右边去。
        let band = switchRect.insetBy(dx: 0, dy: -2)
        let strays = UISnapshot.LiveHost<Never>.findViews(ofType: NSControl.self, in: live.hosting)
            .filter { $0 !== control }
            .map { rect(of: $0, in: live.hosting) }
            .filter { !$0.isEmpty && $0.intersects(band) && $0.maxX > switchRect.maxX + tolerance }
        XCTAssertTrue(
            strays.isEmpty,
            "切换控件右边还有别的控件（「最右侧」不成立）："
                + strays.map { "[\(pt($0.minX))…\(pt($0.maxX))]" }.joined(separator: " · ")
        )
    }

    // MARK: - 判据② CRUD 行 y < 列表首行 y

    @MainActor
    func testCrudRowSitsAboveTheFirstRowOfTheNotesList() async throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        try await seedOneNote(host)
        await host.state.reloadNotes()
        XCTAssertFalse(
            host.state.visibleNotes.isEmpty,
            "夹具没进列表（`visibleNotes` 是空的）⇒ 判据②量不到「列表首行」，不许当成通过"
        )

        let live = makeLive(host)

        // CRUD 行 = 笔记区里**最上面那一条**控件行（增删查改入口行就画在左区顶部）。
        // 取的不是某一枚按钮，而是这一行里控件的垂直带 —— 换按钮 / 换图标都不影响这条判据。
        let controlRects = UISnapshot.LiveHost<Never>.findViews(ofType: NSControl.self, in: live.hosting)
            .map { rect(of: $0, in: live.hosting) }
            .filter { !$0.isEmpty && $0.width > 1 && $0.height > 1 && $0.height <= 60 }
        let topmost = try XCTUnwrap(
            controlRects.min { distanceToTopEdge($0, in: live.hosting) < distanceToTopEdge($1, in: live.hosting) },
            "笔记区里一个控件都没量到 —— 判据的入口没了"
        )
        // 同一行（与该控件垂直相交）的所有控件合成一条带，避免「一行里最高的那枚」把带切窄。
        let crudBand = controlRects
            .filter { $0.intersects(topmost.insetBy(dx: 0, dy: -2)) }
            .reduce(topmost) { $0.union($1) }

        let table = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: NSTableView.self, in: live.hosting).first { $0.numberOfRows > 0 },
            "笔记列表没落地成有行的 `NSTableView`（一条都没有）⇒ 判据②量不到首行"
        )
        let firstRow = live.hosting.convert(table.rect(ofRow: 0), from: table)

        let crudBottom = distanceToBottomEdge(crudBand, in: live.hosting)
        let firstRowTop = distanceToTopEdge(firstRow, in: live.hosting)
        print("NOTES-LAYOUT ② CRUD 行下边缘 \(pt(crudBottom))pt ｜ 列表首行上边缘 \(pt(firstRowTop))pt（\(table.numberOfRows) 行）")

        XCTAssertLessThan(
            crudBottom, firstRowTop,
            "增删查改入口行没在列表之上：CRUD 行下边缘 \(pt(crudBottom))pt ≥ 列表首行上边缘 \(pt(firstRowTop))pt"
                + " —— 「增删查改的所有操作都在左侧区域顶部」这条要求量到的就是它"
        )
    }

    // MARK: - N2-3a 单击 ⇒ 预览（成对读数：点前 / 点后）

    /// **单击列表项 ⇒ 右栏进预览（正文只读）**（片 `N2-3a`「单击预览」· 人类主人令 `T-20261007-004`
    /// 第三节第 3 条）。
    ///
    /// 判据是**成对读数**（点前 / 点后各一次），两个数都读**真视图**上的事实：
    ///   ① `AppState.editorMode`（模式那一个值的唯一出处）—— 点前 `!= .preview`、点后 `== .preview`；
    ///   ② 正文区那个 `NSTextView` 的 `isEditable` —— 点前 `true`、点后 `false`。
    ///
    /// **为什么 ② 读 `NSTextView.isEditable` 这种底层的数**：只读这件事在 SwiftUI 这一层没有
    /// 直接读数（实测 `.disabled(_:)` **不改**底层 `isEditable` —— 见 `App/Views/NotePreviewBody.swift`
    /// 头注释），而「正文真的变成不可编辑」正是这一段要实现的东西 ⇒ 只能读它。
    /// **点前那一次就是对照件**：同一套遍历在 `.edit` 态必须读到 `true` —— 量法若恒读 `false`
    /// （或一个都量不到），这里当场红。
    ///
    /// **怎么算「单击」**：走生产那条入口 `AppState.handleNoteRowClick(_:modifiers:)`
    /// （行上 `.onTapGesture` 调的就是它，见 `App/Views/NotesPanel.swift:154`），修饰键给**空**
    /// （无修饰 = Core `NoteSelectionRule.clicked` 口径里的「打开这一条」）。
    ///
    /// **边界（如实登记）**：`onTapGesture` 自己（AppKit 把一次真实鼠标按下认成 tap）不在判据面里 ——
    /// 这里判的是「这条入口走完之后，模式与正文只读性各是什么」，真实鼠标点验归人工。
    @MainActor
    func testSingleClickOpensPreviewWithReadOnlyBody() async throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        try await seedOneNote(host)
        await host.state.reloadNotes()
        let note = try XCTUnwrap(
            host.state.visibleNotes.first,
            "夹具没进列表（`visibleNotes` 是空的）⇒ 下面那一下「单击」没有对象"
        )

        let live = makeLive(host)
        // 模式一变，SwiftUI 要在 `TextEditor` / `NotePreviewBody` 两支之间换视图 ⇒ 再泵一轮让它落地。
        func settle() {
            let deadline = Date().addingTimeInterval(0.5)
            while Date() < deadline {
                live.window.layoutIfNeeded()
                live.hosting.layoutSubtreeIfNeeded()
                live.hosting.displayIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            live.window.layoutIfNeeded()
            live.hosting.layoutSubtreeIfNeeded()
        }
        func bodyEditableFlags() -> [Bool] {
            UISnapshot.LiveHost<Never>.findViews(ofType: NSTextView.self, in: live.hosting).map(\.isEditable)
        }

        // ── 点前：默认 `.edit`，正文那一个 `NSTextView` 可编辑（= 对照件）────────────────
        let beforeMode = host.state.editorMode
        let beforeEditable = bodyEditableFlags()
        print("NOTES-N2-3a 点前：editorMode=\(beforeMode) 正文 NSTextView \(beforeEditable.count) 个 isEditable=\(beforeEditable)")
        XCTAssertNotEqual(
            beforeMode, .preview,
            "还没点任何行，编辑器就已经是 `.preview` 了 ⇒ 起点不对，成对读数的「点前」那一半不成立"
        )
        XCTAssertFalse(beforeEditable.isEmpty, "点前宿主里一个 `NSTextView` 都没量到 —— 判据的入口没了")
        XCTAssertTrue(
            beforeEditable.allSatisfy { $0 },
            "点前正文区不是可编辑的（isEditable=\(beforeEditable)）—— 对照件不成立，「点后变假」就说明不了什么"
        )

        // ── 单击（无修饰 = Core 口径里的「打开这一条」）──────────────────────────────
        host.state.handleNoteRowClick(note, modifiers: [])
        settle()

        // ── 点后：`.preview`，同一套遍历读到 `isEditable == false` ──────────────────────
        let afterMode = host.state.editorMode
        let afterEditable = bodyEditableFlags()
        print("NOTES-N2-3a 点后：editorMode=\(afterMode) 正文 NSTextView \(afterEditable.count) 个 isEditable=\(afterEditable)")
        XCTAssertEqual(
            afterMode, .preview,
            "单击之后 `editorMode` 不是 `.preview`（实测 \(afterMode)）——「单击预览」没落地"
        )
        XCTAssertFalse(afterEditable.isEmpty, "点后宿主里一个 `NSTextView` 都没量到 —— 只读那一半读不到")
        XCTAssertTrue(
            afterEditable.allSatisfy { !$0 },
            "单击之后正文区的 `NSTextView.isEditable` 不是 false（实测 \(afterEditable)）—— 正文没进只读"
        )
        // 成对的一条硬约束：两次读数必须**不一样**（否则「点前」只是把「点后」抄了一遍）。
        XCTAssertNotEqual(
            beforeEditable, afterEditable,
            "点前 / 点后读到的是同一个 isEditable 集合 ⇒ 这一对读数是恒真的"
        )
    }

    // MARK: - N2-3b 双击内容区 ⇒ 进编辑 + 顶部编辑工具条（成对读数：点前 / 点后）

    /// **双击内容区 ⇒ 进编辑 + 顶部编辑工具条出现**（片 `N2-3b` · 人类主人令 `T-20261007-004` 第 4 条：
    /// 「双击编辑 + 顶部编辑工具条」「保存进工具条（参考 SQL 界面）」「不许放底部」）。
    ///
    /// 判据是**成对读数**（点前 / 点后各一次），两个数都读**真视图**上的事实：
    ///   ① `AppState.editorMode`（模式那一个值的唯一出处）—— 点前 `== .preview`
    ///      （先走 `N2-3a` 的单击那条入口）、点后 `== .edit`；
    ///   ② **顶部编辑工具条出现** —— 判据是**几何**：正文那一块的上边缘被一条工具条**顶下去**了。
    ///      工具条是 `NotesEditorView` 的**第一行**子视图（`NotesEditorToolbar`），它一出现，
    ///      它下面的一切（标题 / 标签 / 正文）整体下移**一条行的量**。
    ///
    /// **为什么「下移」就是「工具条在这儿」**：这个离屏宿主里，SwiftUI 的 `Button` 不落到
    /// `NSControl`（`NotesEditorSaveProbeTests` 头注释实测 `NSButton` = 0 个），所以**工具条自己
    /// 没有一条可读的矩形**；而「它下面那块被顶下去多少」量得到，且正是「工具条占了栏顶那一带」
    /// 这句话在几何上的全部内容。本条同时把工具条按 `accessibilityIdentifier` 找一遍并**打印**
    /// 读数（找到了就直接给出一致证据，找不到也不影响判据成立）。
    ///
    /// **点前那一次就是对照件**：同一套遍历在预览态必须读到「没有工具条」——
    /// 量法若恒读同一个数（或一个都量不到），这里当场红。
    ///
    /// **怎么算「双击内容区」**：走生产那条入口 `AppState.beginEditingCurrentNote()`
    /// （`NotePreviewBody` 那一支上 `.onTapGesture(count: 2)` 调的就是它，见 `App/Views/NotesPanel.swift`）。
    /// 真实鼠标的双击由 AppKit 判定，不在判据面里 —— 与 `N2-3a` 同一条边界（那一侧也是走入口）。
    @MainActor
    func testN23bDoubleClickOnContentEntersEditingWithTopToolbar() async throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        try await seedOneNote(host)
        await host.state.reloadNotes()
        let note = try XCTUnwrap(
            host.state.visibleNotes.first,
            "夹具没进列表（`visibleNotes` 是空的）⇒ 下面那两下没有对象"
        )

        let live = makeLive(host)
        // 模式一变，SwiftUI 要在 `TextEditor` / `NotePreviewBody` 两支之间换视图 ⇒ 再泵一轮让它落地。
        func settle() {
            let deadline = Date().addingTimeInterval(0.5)
            while Date() < deadline {
                live.window.layoutIfNeeded()
                live.hosting.layoutSubtreeIfNeeded()
                live.hosting.displayIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            live.window.layoutIfNeeded()
            live.hosting.layoutSubtreeIfNeeded()
        }
        /// 正文那一块（`NotePreviewBody` / `TextEditor` 里那个真 `NSTextView`）的上边缘。
        func bodyTop() throws -> CGFloat {
            let rects = UISnapshot.LiveHost<Never>.findViews(ofType: NSTextView.self, in: live.hosting)
                .map { rect(of: $0, in: live.hosting) }
                .filter { !$0.isEmpty }
            return try XCTUnwrap(
                rects.map { distanceToTopEdge($0, in: live.hosting) }.min(),
                "右栏里一个 `NSTextView` 都没量到 —— 判据的入口没了"
            )
        }
        /// 顶部编辑工具条**自己**的矩形（按 `accessibilityIdentifier` 找；宿主不给这个读数时是 nil）。
        func toolbarRect() -> CGRect? {
            UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: live.hosting)
                .first { $0.accessibilityIdentifier() == "notes-editor-toolbar" }
                .map { rect(of: $0, in: live.hosting) }
        }
        func toolbarText() -> String {
            guard let r = toolbarRect() else { return "无读数" }
            return "[\(pt(r.minX))…\(pt(r.width))]×\(pt(r.height))pt"
        }

        // ── 点前：先单击（`N2-3a` 那条入口）⇒ 预览；此时正文贴着栏顶、工具条不在 ──────────
        host.state.handleNoteRowClick(note, modifiers: [])
        settle()
        let beforeMode = host.state.editorMode
        let beforeTop = try bodyTop()
        print("NOTES-N2-3b 点前：editorMode=\(beforeMode) 正文上边缘=\(pt(beforeTop))pt 工具条=\(toolbarText())")

        XCTAssertEqual(
            beforeMode, .preview,
            "点前不是预览态（实测 \(beforeMode)）—— 起点不对，成对读数的「点前」那一半不成立"
        )

        // ── 双击内容区（= `NotePreviewBody` 那一支上的双击手势调的那个入口）───────────────
        host.state.beginEditingCurrentNote()
        settle()

        // ── 点后：编辑态 + 正文被顶部工具条顶下去一条行的量 ────────────────────────────
        let afterMode = host.state.editorMode
        let afterTop = try bodyTop()
        print("NOTES-N2-3b 点后：editorMode=\(afterMode) 正文上边缘=\(pt(afterTop))pt 工具条=\(toolbarText())")

        XCTAssertEqual(
            afterMode, .edit,
            "双击内容区之后 `editorMode` 不是 `.edit`（实测 \(afterMode)）——「双击进编辑」没落地"
        )
        XCTAssertGreaterThan(
            afterTop, beforeTop + 24,
            "双击之后正文上边缘没有下移出一条工具条的量（点前 \(pt(beforeTop))pt / 点后 \(pt(afterTop))pt）"
                + " —— 顶部编辑工具条没出现，或它没画在正文之上（「不许放底部」的反面）"
        )
    }

    // MARK: - N2-2 探索：操作栏 / 工具条里**哪些东西量得动**（一次性诊断）

    /// 把「操作栏 / 工具条」相关的几件视图各量一遍宽度，并把活宿主顶带里的控件逐条打印出来
    /// —— 用来定 N2-2 那条「宽度收敛」的判据到底该量哪一个数（读源码常量会量错东西）。
    @MainActor
    func testN22ExploreMeasurableWidths() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }

        func fitting<V: View>(_ label: String, _ view: V, width: CGFloat = 4000, height: CGFloat = 80) {
            let controller = NSHostingController(
                rootView: AnyView(
                    view.snapshotEnvironment(
                        state: host.state, workspace: host.workspace, tabs: host.tabs, terminal: host.terminal
                    )
                )
            )
            let size = controller.sizeThatFits(in: CGSize(width: width, height: height))
            print("N2-2-EXPLORE fitting[\(label)] = \(pt(size.width)) x \(pt(size.height))")
        }
        fitting("NotesListView", NotesListView())
        fitting("TodoQueryBar", TodoQueryBar())
        fitting("TodoPaneView", TodoPaneView(), height: 400)
        fitting("NotesAreaView", NotesAreaView(), height: 700)

        let live = makeLive(host)
        for view in UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: live.hosting) {
            let r = rect(of: view, in: live.hosting)
            guard !r.isEmpty, r.height > 1, r.height <= 80 else { continue }
            let top = distanceToTopEdge(r, in: live.hosting)
            guard top <= 80 else { continue }
            print(
                "N2-2-EXPLORE view cls=\(String(describing: type(of: view)))"
                    + " id=\(view.accessibilityIdentifier())"
                    + " x=[\(pt(r.minX))…\(pt(r.maxX))] w=\(pt(r.width)) h=\(pt(r.height)) top=\(pt(top))"
            )
        }
    }
}
