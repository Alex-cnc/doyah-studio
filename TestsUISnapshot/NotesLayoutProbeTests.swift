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
