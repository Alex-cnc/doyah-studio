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

    /// 活窗口（**默认不上屏**）：`NotesAreaView` + 根部那一套环境注入，泵几轮让布局落地。
    ///
    /// **不上屏**（`orderFront` 那条路本轮实测走不通，如实登记）：把窗口摆到屏上并设为 key 会拉起
    /// `ReminderNotifier`，而它在 `xctest` 直跑时没有真 bundle（`bundleProxyForCurrentProcess is nil`
    /// ⇒ 进程 `signal 6` 直接崩，整族一个读数都出不来）。所以这里一律离屏：量的东西全部改成
    /// 「渲染出的像素」与「合成事件投给窗口」，不再依赖 AppKit 视图树里看得见那两枚图标按钮。
    @MainActor
    private func makeLive(
        _ host: HostBundle,
        seconds: TimeInterval = 0.6
    ) -> (window: NSWindow, hosting: NSHostingView<AnyView>) {
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

    /// **任意视图**的离屏宿主（`makeLive` 的泛型版：口径逐字相同 —— `areaSize`、`.aqua`、泵 `seconds` 秒、
    /// 不上屏）。`N2-LW` 那条判据要在**同一轮运行**里挂**两份**视图（生产 + 改前复刻件），
    /// 而 `makeLive` 的根视图写死了 `NotesAreaView`，所以这里补一个能挂任意视图的。
    @MainActor
    private func makeOffscreenHost<V: View>(
        _ host: HostBundle,
        _ view: V,
        seconds: TimeInterval = 0.6
    ) -> (window: NSWindow, hosting: NSHostingView<AnyView>) {
        let appearance = NSAppearance(named: .aqua)
        let root = AnyView(
            view.snapshotEnvironment(
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

    /// 顶栏行末那一对**模式切换按钮**（人类主人令 `T-20261007-080`：**笔记本图标 + 闹钟图标**
    /// 替代原先那 2 个 button / 分段条）。
    ///
    /// ## 入口为什么不是「按 `accessibilityIdentifier` 找控件」（本轮实测结论 · 如实登记）
    ///
    /// 本轮诊断读数：活宿主里 **视图 50 个 · 带标识 0 个 · `NSButton` 0 枚 · `NSSegmentedControl` 0 枚**
    /// —— SwiftUI 的 `Button`（`.buttonStyle(.plain)` + 图标）在 AppKit 视图树里**不落地成 `NSView`**
    /// （只有 `Picker(.segmented)` 那类 AppKit 承载的控件才会，旧判据① 正是靠它找到的）。
    /// ⇒ 图标按钮**在离屏宿主里既挑不出来、也量不到矩形**；这条边界是环境性的，不是入口写错。
    ///
    /// ## 本轮还实测到两条硬边界（都不要再走一遍）
    ///
    /// 1. **把宿主窗口摆上屏**（`makeKeyAndOrderFront`）⇒ 拉起 `ReminderNotifier`，它在 `xctest`
    ///    直跑时没有真 bundle（`bundleProxyForCurrentProcess is nil`）⇒ 进程 `signal 6`，整族零读数；
    /// 2. **离屏投合成点击**（`window.sendEvent`）⇒ 事件收下了（路径有回执）但 **SwiftUI 的手势不响应**
    ///    ⇒ `notesModule` 不动（实测 `notes` 点完仍是 `notes`）。
    /// 3. **渲染该宿主取像素**（`bitmapImageRepForCachingDisplay` + `cacheDisplay`）⇒ 同样撞上面那条
    ///    `ReminderNotifier` 断言（进程崩）。
    ///
    /// ⇒ 本用例只判**AppKit 树里量得到的那一半**（旧形态必须消失）与**源锚点**；
    /// 「点得动 / 悬停出 tips / 高亮跟着走」三条交给**该包实跑的人眼证据**（见本单回执的「未验证项」），
    /// 不许拿「代码里有」替代（口径同 `T-20261007-072` 硬要求③）。
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func notesPanelSource() throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent("App/Views/NotesPanel.swift"), encoding: .utf8)
    }

    // MARK: - 判据① 行末那两枚：旧形态必须消失（`T-20261007-080`）

    /// **负半＋源锚点**（正半 = 「点得动 / 在最右」本轮量不到，见 helper 上那三条边界）：
    ///
    /// · 负半：顶栏里**不再有**「笔记 / 待办」分段控件（`NSSegmentedControl` · 分段标签匹配）——
    ///   那是「一组带字的 button」，本单要换掉的正是它。这一半在 AppKit 树里**量得到**，能判红。
    /// · 源锚点：`NotesPanel.swift` 的 `topBar` 里 `moduleSwitch` 仍挂在 `Spacer` **之后**
    ///   （＝行末那一处），且两枚按钮由 `moduleSwitchButton(for:systemName:)` 一处派生。
    ///   位置这一半只剩源锚点，是因为图标按钮在宿主里没有可量的矩形（同上）。
    @MainActor
    func testModuleSwitchIsNoLongerATextControl() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let live = makeLive(host)
        let labels = NotesModule.allCases.map { L($0.titleKey) }

        let textSegments = UISnapshot.LiveHost<Never>.findViews(ofType: NSSegmentedControl.self, in: live.hosting)
            .filter { control in
                (0..<control.segmentCount).map { control.label(forSegment: $0) ?? "" } == labels
            }
        XCTAssertTrue(
            textSegments.isEmpty,
            "顶栏里还留着「\(labels.joined(separator: " / "))」分段控件（\(textSegments.count) 枚）"
                + " —— 那是「一组带字的 button」，正是 `T-20261007-080` 要换掉的"
        )

        let source = try notesPanelSource()
        for anchor in [
            "Spacer(minLength: Spacing.s)\n            moduleSwitch",
            "moduleSwitchButton(for: .notes, systemName: NotesAreaView.notesModuleSymbol)",
            "moduleSwitchButton(for: .todos, systemName: NotesAreaView.todosModuleSymbol)",
        ] {
            XCTAssertTrue(source.contains(anchor), "源锚点失配：\(anchor) 不在 `App/Views/NotesPanel.swift` 里")
        }
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

    // MARK: - R3 / R4 / R5 预览态点正文 ⇒ 进编辑（`T-20261007-077` · 人类主人裁决「要 A + C，不要 B」）

    /// **预览态下，把一次鼠标按下投给正文那块文本 ⇒ 进编辑**（人类主人裁决 `T-20261007-077`：
    /// **A + C，不要 B**；原话逐字「**我的预期是 A 和 C，不是 B**」）。
    ///
    /// ## 对上的五条
    ///
    /// · **R1 / R2 是起点，不是本用例的判据**：先走 `handleNoteRowClick(_:modifiers:)`（列表里单击
    ///   那条入口）⇒ `editorMode == .preview`（R1 保留）；R2（列表里双击）本轮不碰。
    /// · **R3（= C）**：预览态下**单击正文**（`mouseDown` · `clickCount = 1`）⇒ `editorMode == .edit`；
    /// · **R4（= A）**：回到预览态后**双击正文**（`clickCount = 2`）⇒ `editorMode == .edit`；
    /// · **R5**：点之前，正文那个 `NSTextView.isEditable == false`（预览期仍只读 —— R3 / R4 是
    ///   「点了就切编辑」，不是「预览里能直接改字」）。
    ///
    /// ## 判据为什么是「投事件给真视图」，而不是「调一下入口」
    ///
    /// 单里写死的两条：① 判据必须是**对正文区发单击 / 双击事件**；② **不许拿「代码里有
    /// `onTapGesture`」当判据** —— 判的必须是 `editorMode` 由 `.preview` → `.edit` 这条**状态转移**。
    /// 所以这里把 `NSEvent`（左键按下）**真的投给宿主视图树里那块正文**，再看模式。
    ///
    /// ## 这条路为什么判得动（同文件里另两条手势判不动）
    ///
    /// `N2-3b` 与 `T-080` 那两条登记的边界是 **SwiftUI 的手势不响应合成事件**
    /// （`window.sendEvent` ⇒ 事件收下但 `notesModule` 不动）。本用例走的是 **AppKit 那一层**：
    /// 预览态正文是一个**真 `NSTextView`**（`App/Views/NotePreviewBody.swift` 的
    /// `PreviewTextView`），它对 `mouseDown(with:)` 的处置是**同步、确定**的 —— 直接把事件投给
    /// 那个视图即可，绕开 SwiftUI 的手势判定。
    ///
    /// ## 能判红（否则「投完就进编辑」可能是这套量法自己造的）
    ///
    /// 两条对照件都在同一次运行里：
    ///   ① **点前 / 点后成对**：点之前必须是 `.preview`（点后变 `.edit` 才有意义）；
    ///   ② **负对照**：把**同一个事件**投给一枚**跟产品无关的裸 `NSTextView`** ⇒ `editorMode`
    ///      必须**一个字节不动** —— 这一条挡的是「只要调了 `mouseDown` 模式就会翻」这类恒真量法。
    /// 改动前那一版（正文是裸 `NSTextView`、不接回调）**本用例当场红**（实测读数见本轮回执）。
    @MainActor
    func testR3R4ClickOnPreviewBodyEntersEditing() async throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        try await seedOneNote(host)
        await host.state.reloadNotes()
        let note = try XCTUnwrap(
            host.state.visibleNotes.first,
            "夹具没进列表（`visibleNotes` 是空的）⇒ 下面那两下「点正文」没有上下文"
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
        /// 预览态里那块**只读**正文（`isEditable == false` 的那一个 `NSTextView`）。
        func previewBody() throws -> NSTextView {
            let bodies = UISnapshot.LiveHost<Never>.findViews(ofType: NSTextView.self, in: live.hosting)
                .filter { !$0.isEditable }
            return try XCTUnwrap(
                bodies.first,
                "预览态里一个只读的 `NSTextView` 都没量到 —— 判据的入口没了"
                    + "（本用例要判的就是「在这块文本上按下鼠标」）"
            )
        }
        /// **把一次左键按下投给某个视图**（真 `NSEvent`；`clickCount` 区分单击 / 双击）。
        func press(_ view: NSView, clickCount: Int) throws {
            let event = try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: .leftMouseDown,
                    location: NSPoint(x: 8, y: 8),
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: live.window.windowNumber,
                    context: nil,
                    eventNumber: 1,
                    clickCount: clickCount,
                    pressure: 1
                ),
                "`NSEvent.mouseEvent` 没造出来 ⇒ 这一条判据的输入没了"
            )
            view.mouseDown(with: event)
        }

        // ── 起点：R1（列表里单击）⇒ 预览态 ─────────────────────────────────────────
        host.state.handleNoteRowClick(note, modifiers: [])
        settle()
        let startMode = host.state.editorMode
        print("T-077 起点（列表里单击之后）：editorMode=\(startMode)")
        XCTAssertEqual(
            startMode, .preview,
            "起点不是预览态（实测 \(startMode)）—— R1 那条「单击列表 ⇒ 预览」没成立，成对读数的点前不成立"
        )

        // ── R5 的前提：预览期正文只读 ────────────────────────────────────────────
        let body = try previewBody()
        print("T-077 正文那件：类型=\(type(of: body)) isEditable=\(body.isEditable)")
        XCTAssertFalse(
            body.isEditable,
            "预览期正文不是只读的（isEditable=true）—— R5 不成立"
        )

        // ── 负对照：同一个事件投给一枚跟产品无关的裸 `NSView` ⇒ 模式不许动 ──────────
        // **为什么不是裸 `NSTextView`**（本轮实测 · 别重走）：`NSTextView` 的 `mouseDown(with:)`
        // 会落进 **AppKit 的跟踪循环**、等一个 `mouseUp`；离屏探针里没有后续事件 ⇒ 整个用例挂在
        // 那一行（实测跑满 4 分钟 CPU 不返回，只能杀掉）。负对照要判的只是「投事件这个动作本身
        // 不会翻模式」，一枚普通 `NSView` 就够。
        let control = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 80))
        let beforeControl = host.state.editorMode
        try press(control, clickCount: 1)
        settle()
        print("T-077 负对照（裸 `NSView` 收同一个事件）：\(beforeControl) → \(host.state.editorMode)")
        XCTAssertEqual(
            host.state.editorMode, beforeControl,
            "同一个事件投给一枚跟产品无关的裸 `NSView` 也把模式翻掉了 ⇒ 这套量法恒真，判不出东西"
        )

        // ── R3 的前置守卫（同时也是本用例在**改动前**的判红点）──────────────────────
        // 正文必须由**产品自己的** `PreviewTextView` 处置鼠标按下：改动前那一版是裸 `NSTextView`
        // —— 它既不接回调，直接投事件还会落进 AppKit 跟踪循环 ⇒ 这条守卫让「R3 / R4 没落地」
        // **当场判红**，而不是把用例挂死。两条守卫都不绿就直接返回（后面那两下按不下去）。
        guard let preview = body as? PreviewTextView else {
            XCTFail(
                "预览态正文不是 `PreviewTextView`（`App/Views/NotePreviewBody.swift`）—— "
                    + "R3 / R4 那条「在正文上按下 ⇒ 进编辑」的事件路径不在产品上（实测类型 \(type(of: body))）"
            )
            return
        }
        guard preview.onActivate != nil else {
            XCTFail(
                "正文那件没接上回调（`onActivate` 是 nil）—— 投事件会挂死在 AppKit 的跟踪循环里；"
                    + "R3 / R4 的另一半也没接上"
            )
            return
        }

        // ── R3（= C）：预览态**单击**正文 ⇒ 进编辑 ────────────────────────────────
        let beforeSingle = host.state.editorMode
        try press(preview, clickCount: 1)
        settle()
        let afterSingle = host.state.editorMode
        print("T-077 R3 单击正文：\(beforeSingle) → \(afterSingle)")
        XCTAssertEqual(
            afterSingle, .edit,
            "R3（预览态单击正文 ⇒ 进编辑）没落地：投完单击之后 `editorMode` 还是 \(afterSingle)"
        )
        XCTAssertNotEqual(
            beforeSingle, afterSingle,
            "点前 / 点后读到同一个值（\(afterSingle)）⇒ 这一对读数是恒真的"
        )

        // ── R4（= A）：回到预览态，**双击**正文 ⇒ 进编辑 ──────────────────────────
        host.state.handleNoteRowClick(note, modifiers: [])
        settle()
        XCTAssertEqual(
            host.state.editorMode, .preview,
            "第二次「列表里单击」没回到预览态（实测 \(host.state.editorMode)）—— R4 的起点不成立"
        )
        let bodyForDouble = try previewBody()
        guard let previewForDouble = bodyForDouble as? PreviewTextView, previewForDouble.onActivate != nil else {
            XCTFail("双击那一路的正文不是接上回调的 `PreviewTextView`（类型 \(type(of: bodyForDouble))）")
            return
        }
        let beforeDouble = host.state.editorMode
        try press(previewForDouble, clickCount: 2)
        settle()
        let afterDouble = host.state.editorMode
        print("T-077 R4 双击正文：\(beforeDouble) → \(afterDouble)")
        XCTAssertEqual(
            afterDouble, .edit,
            "R4（预览态双击正文 ⇒ 进编辑）没落地：投完双击之后 `editorMode` 还是 \(afterDouble)"
        )
        XCTAssertNotEqual(
            beforeDouble, afterDouble,
            "点前 / 点后读到同一个值（\(afterDouble)）⇒ 这一对读数是恒真的"
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

    // MARK: - N2-7 新建笔记本入口组回左区顶部（几何判据 · 成对读数：改前 / 改后）

    /// **`+ New notebook` 与笔记本列表贴在左区（侧栏）顶部**（片 `N2-7` · 人类主人 2026-10-07 22:51
    /// 第三包截图定因：`N2-1`「入口由居中回顶部」**未做到** —— 侧栏里那棵树仍被**垂直居中**）。
    ///
    /// ## 判据
    ///
    /// 把左区（侧栏）那一份**真内容**——`MainWindow.swift:48` 那个
    /// `NebulaSurface(surface: .sidebar, layer: .sidebar) { NotesContainerTreeView() }`——
    /// 挂进一个**固定尺寸 248 × 700** 的离屏宿主（宽 = `Metrics.sidebarWidth`；高远大于树的内容，
    /// 让「内容挂顶还是被居中」在几何上看得出来），泵几轮让布局落地，量宿主里**最上面那一条
    /// 可读矩形**的上边缘离宿主顶边的距离 `top`：
    ///
    ///   · 内容贴在容器顶部时 `top` 只有几 pt（首个控件那一行的行内边距）；
    ///   · 被居中时 `top ≈ (700 − 内容高 114) / 2 = 293 pt`。
    ///
    /// 判据：**`top ≤ 40 pt`**（宿主高 700 的上 6%）。
    ///
    /// **成对读数**：改动前先跑一次记 `top_before`（**本机实测 293.0 pt**，判据当场红），改动后
    /// 再跑得 `top_after ≤ 40`。两次数都 `print` 出来（口径与同文件既有判据一致：读数即证据）。
    ///
    /// ## 量得到的对象（优先 → 退）
    ///
    /// 优先量 `accessibilityIdentifier == "notes-new-notebook"` 那一枚（入口自己）；若离屏宿主里
    /// 量不到它（SwiftUI 的 `Button` 在离屏时**不落到 `NSControl`**、无障碍树也不构建 —— 见
    /// `NotesEditorSaveProbeTests` 头注释实测），**退到**「宿主里最上面一条可读矩形」，
    /// 语义不变（那正是「树的内容挂在容器顶部」这件事的几何内容）。
    /// **一个矩形都量不到就停**（卡上边界：留 comment + 标 `needs_input`）——
    /// 不许把这条判据退化成读源码 / 读常量 / 数 `grep` 命中。
    @MainActor
    func testNewNotebookEntrySitsInTopBandOfLeftArea() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }

        // 左区（侧栏）固定尺寸：宽与导航分栏同规格（`Metrics.sidebarWidth` = 248），
        // 高取得远大于树的内容 —— 「挂顶还是居中」只在高度富余时才看得出来。
        //
        // **为什么不是直接挂 `NotesContainerTreeView()`**：本机实测（`NSHostingView` 根视图）
        // 那样挂**量不出这个缺陷** —— 根视图被钉在左上角，量到的 `top ≈ 0`（判据在改动前就绿，
        // 「成对读数」的对照那一半不成立）。真实左区不是「裸挂一棵树」：`MainWindow.swift:48`
        // 把它包在 `NebulaSurface(surface: .sidebar, layer: .sidebar) { … }` 里，而
        // `NebulaSurface.body` 是一个 `ZStack`（默认 `alignment = .center`）——
        // **这一层居中就是「入口组被垂直居中」的现场**。所以这里挂的是**左区那一份的真内容**
        // （`NebulaSurface` + 树），尺寸固定 248 × 700。
        let hostSize = CGSize(width: Metrics.sidebarWidth, height: 700)
        let root = AnyView(
            NebulaSurface(surface: .sidebar, layer: .sidebar) {
                NotesContainerTreeView()
            }
            .snapshotEnvironment(
                state: host.state, workspace: host.workspace, tabs: host.tabs, terminal: host.terminal
            )
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: hostSize)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: hostSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting

        // 泵几轮让布局落地（与 `makeLive` 同一套）。
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            window.layoutIfNeeded()
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        // 量对象一：入口那一枚（按 `accessibilityIdentifier` 找）。
        let entryRect = UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: hosting)
            .first { $0.accessibilityIdentifier() == "notes-new-notebook" }
            .map { rect(of: $0, in: hosting) }

        // 量对象二（退路）：宿主里最上面一条**可读矩形** —— 排除宿主自己与铺满宿主的背景层
        // （那是容器不是内容），剩下的就是树里真画出来的控件 / 行。
        let contentRects = UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: hosting)
            .filter { $0 !== hosting }
            .map { rect(of: $0, in: hosting) }
            .filter { !$0.isEmpty && $0.width > 1 && $0.height > 1 && $0.size != hostSize }

        let topmost = try XCTUnwrap(
            contentRects.min { distanceToTopEdge($0, in: hosting) < distanceToTopEdge($1, in: hosting) },
            "侧栏宿主里一个可读矩形都没量到 —— 判据的入口没了"
                + "（按卡上边界：停 + 卡上留 comment + 标 needs_input；不许退化成读源码）"
        )
        let measured = entryRect ?? topmost
        let top = distanceToTopEdge(measured, in: hosting)
        print(
            "NOTES-LAYOUT N2-7 左区顶部带：top=\(pt(top))pt（宿主 \(pt(hostSize.width))×\(pt(hostSize.height))，"
                + "量的是\(entryRect == nil ? "宿主里最上面一条可读矩形" : "notes-new-notebook 那一枚")，"
                + "可读矩形 \(contentRects.count) 条）｜限额 40.0pt"
        )

        XCTAssertLessThanOrEqual(
            top, 40,
            "新建笔记本入口组没贴在左区（侧栏）顶部：最上面那一条的上边缘离宿主顶边 \(pt(top))pt > 40pt"
                + " —— 这正是「入口组被垂直居中」的几何表现（`N2-1` 只改了水平对齐，垂直位置一字未动）"
        )
    }

    // MARK: - T-20261007-080：行末两枚图标（无文字按钮 / 名字 / 图标两枚分得开）

    /// **行末那两枚的形态判据**（人类主人令 `T-20261007-080` 第二节，**能判的那几条**）：
    ///
    ///   ① **不存在文字按钮**：旧形态（`NSSegmentedControl`，分段标签恰为「笔记 / 待办」）一枚不剩
    ///      （原话：「**我不要 button，我要图标 + tips**」）；
    ///   ② **两枚讲得出名字**：`help:` 是 `ToolbarIconButton` 的**构造参数**（漏了编译不过）；
    ///      本用例用**源锚点**把「两枚的 `help` 取 `L(module.titleKey)`」+「两枚用两个**不同**的
    ///      图标常量（笔记本 / 闹钟）」钉住（口径同 `NotePresentationTests` 的源码锚点）；
    ///   ③ **不是分段条/文字按钮**：`App/Views/NotesPanel.swift` 里 `moduleSwitch` 不再出现
    ///      `.pickerStyle(.segmented)`（那是旧形态；负向断言，能判红）。
    ///
    /// ## 未验证项（如实登记 · 不许用「代码里有」替代）
    ///
    /// **点得动 / 悬停出 tips / 选中态高亮**三条在**离屏宿主里量不到**（三条边界见上面 helper 的注释：
    /// 上屏 ⇒ `ReminderNotifier` 崩；离屏合成点击 ⇒ SwiftUI 不响应；渲染取像素 ⇒ 同上崩）⇒
    /// 交给**该包实跑的人眼证据**（本单回执：静置 / 悬停 / 点前 / 点后截图）。
    @MainActor
    func testModuleSwitchIsTwoIconButtonsWithTips() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let live = makeLive(host)
        let labels = NotesModule.allCases.map { L($0.titleKey) }

        let segments = UISnapshot.LiveHost<Never>.findViews(ofType: NSSegmentedControl.self, in: live.hosting)
        let textSegments = segments.filter { control in
            (0..<control.segmentCount).map { control.label(forSegment: $0) ?? "" } == labels
        }
        XCTAssertTrue(
            textSegments.isEmpty,
            "顶栏里还留着「\(labels.joined(separator: " / "))」分段控件（\(textSegments.count) 枚）"
        )

        let source = try notesPanelSource()
        for anchor in [
            "help: L(module.titleKey)",
            "isSelected: appState.notesModule == module",
            "static let todosModuleSymbol = \"alarm\"",
        ] {
            XCTAssertTrue(source.contains(anchor), "源锚点失配：`\(anchor)` 不在 `App/Views/NotesPanel.swift` 里")
        }
        XCTAssertFalse(
            source.contains("private var moduleSwitch: some View {\n        Picker("),
            "`moduleSwitch` 又变回 `Picker`（分段条 / 文字按钮的旧形态）"
        )
        XCTAssertNotEqual(
            NotesAreaView.notesModuleSymbol, NotesAreaView.todosModuleSymbol,
            "两枚用了同一个图标（\(NotesAreaView.notesModuleSymbol)）——「笔记本图标 + 闹钟图标」要求两枚分得开"
        )
        print("T-080 ① 顶栏分段控件 \(segments.count) 枚（其中「笔记 / 待办」\(textSegments.count) 枚）· "
              + "② 图标 = \(NotesAreaView.notesModuleSymbol) / \(NotesAreaView.todosModuleSymbol) · "
              + "③ 源锚点 3 条命中")
    }

    // MARK: - 判据③ 删除先确认（`T-20261007-079` ② / `T-20261007-081`）

    /// **破坏性操作先确认**（人类主人原话，2026-10-07 23:0x 逐字：「**delete 时连个确认都就直接删了**」
    /// —— 那是数据风险）。
    ///
    /// 判据的形状（`T-20261007-079` 第二节写死的）：**点删除 ⇒ 条目数不变，直到确认**。
    ///
    /// ## 入口为什么是「驱动 `AppState` 的状态机」而不是「点界面那枚按钮」
    ///
    /// 离屏宿主里 SwiftUI 的手势不响应（合成事件收下但 `notesModule` 不动），上屏 / 取像素又会撞
    /// `ReminderNotifier` 断言 ⇒ 界面事件这条路本轮量不到（三条边界见上面 helper 注释，别重走）。
    /// 但「点删除会不会就删了」这件事**不在视图里** —— 它由 `AppState` 的状态机决定，而状态机是
    /// **同步可驱动**的 ⇒ 直接量它，得到的是**同一件事**的机器读数：
    ///   ① `requestNoteRemoval()`（= 点删除）⇒ 挂上确认请求，**一条都没少**；
    ///   ② `cancelNoteRemoval()`（= 取消）⇒ 仍一条没少；
    ///   ③ `confirmNoteRemoval()`（= 确认）⇒ 这才少一条。
    ///
    /// ## 能判红（否则「没少」会被读成「都对」）
    ///
    /// 反例 = 改动前那一版 `deleteSelection()`：它直接调 `deleteNote(id:)` ⇒ 在 ① 那一步
    /// 条目数就已经少了一条，两条断言当场红。
    @MainActor
    func testDeletingANoteAsksForConfirmationBeforeTouchingTheLibrary() async throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        try await seedOneNote(host)
        await host.state.reloadNotes()

        let seeded = try XCTUnwrap(host.state.notes.first, "夹具没读进来 ⇒ 判据量不到「条目数不变」")
        let before = host.state.notes.count
        XCTAssertGreaterThan(before, 0)

        // ① 点删除 ⇒ 只挂请求，条目数不变
        host.state.selectedNoteIDs = [seeded.id]
        host.state.requestNoteRemoval()
        XCTAssertNotNil(
            host.state.pendingNoteRemoval,
            "点了删除却没挂上确认请求 ⇒ 破坏性操作没被拦下（数据风险）"
        )
        XCTAssertEqual(host.state.notes.count, before, "点删除就改了条目数 ⇒ 没有二次确认")

        // ② 取消 ⇒ 库一个字节不动
        host.state.cancelNoteRemoval()
        host.state.selectedNoteIDs = []
        await host.state.reloadNotes()
        XCTAssertEqual(host.state.notes.count, before, "取消之后条目数变了")

        // ③ 确认 ⇒ 这才少一条
        host.state.selectedNoteIDs = [seeded.id]
        host.state.requestNoteRemoval()
        await host.state.confirmNoteRemoval()
        XCTAssertEqual(host.state.notes.count, before - 1, "确认删除之后条目数没减")

        print(
            "T-081 ② 删除先确认：点删除后 \(before)（不变）· 取消后 \(before)（不变）· "
                + "确认后 \(before - 1)（减 1）｜确认动作 = "
                + "\(NoteRemovalPrompt.confirmActions.map(\.rawValue))"
        )
    }

    // MARK: - N2-LW 中栏（存放笔记列表的那一列）整列收窄（成对读数：改前 / 改后）

    /// **中栏那一列（存放笔记列表的左侧）的整列宽度 ≤ 改前的 60%**（片 `N2-LW` · 派单 `T-20261008-025`）
    /// —— 并随**前门裁决 `T-20261009-001`**跟到**改后目标档 `≤238.0pt`**（片 `N2-LW-238`）。
    ///
    /// ## 期望值的跟版（本片只改这一处 · 断言形状与负例一字未动）
    ///
    /// 前门裁定：「宽度判据取【真机真实窗口】⇒ `397 → 300 = 75.6%` 未达 ≤60% ⇒ 需重做 N2-LW 到
    /// **≤238pt**（允许工具条分 2 行，头部不许断词），**旧 520 / 300 只作离屏读数留档**」。⇒
    /// 本用例的**期望值**从「上一版改后的 `300.0pt` 读数」跟到**改后目标档 `238.0pt`**；
    /// **相对判据（`≤ 改前 × 0.60`）与改前复刻件（负例）一字未动**，新增的只是那一条更严的
    /// 目标档断言（见下面判据 ①b）。三个离屏读数按序留档：
    ///   · 改前（复刻件 `220 / 300 / 520`，本片不动）= **520.0pt**；
    ///   · 上一版改后（生产 `132 / 180 / 300`，本片改前）= **300.0pt**；
    ///   · 本版改后（生产 `132 / 143 / 238`）= **238.0pt**。
    ///
    /// ## 对上的那一句（人类主人 2026-10-08 14:3x 逐字）
    ///
    /// 「**C，左栏整体太宽了。我这里说的左栏不是最左侧的笔记本导航栏，是存放笔记列表的左侧，
    /// 右侧就是笔记内容**」
    /// —— 收窄对象是**中栏整列的宽度**，不是某一枚行内控件。前门已裁定「行内读数收敛」
    /// （搜索框 `320→200` · 行宽 `713.5→442pt`）**不算**本条完成，所以判据量的必须是**整列**。
    ///
    /// ## 量什么（真几何，不是读源码常量）
    ///
    /// 沿用本文件既有的离屏宿主口径（`areaSize = 1100×700`，`makeLive` 那一套）。`HSplitView`
    /// 在这个宿主里**落地成真 `NSSplitView`**：两个真子视图＝两列，第三个子是分隔线（实测宽 5pt，
    /// 按「宽 > 8pt 才是一列」排除）。量的就是这两列的**落地宽度**（＝整栏，不是行内控件）。
    ///
    /// ## 成对读数怎么来的（**同一轮运行里两份在位**）
    ///
    ///   · **改后** = 生产的 `NotesAreaView()` 挂进 1100×700 宿主；
    ///   · **改前** = **复刻件**：同一副骨架（`HSplitView` + `NotesListView` + `NotesEditorView`），
    ///     中栏那三档写**改前那三个数**（`220 / 300 / 520`，与 `App/Views/NotesPanel.swift` 里
    ///     `listPane*Width` 注释登记的改前值逐字相同），挂进同样大的宿主。
    ///
    /// 两次读数都在本机当场量出来 ⇒ 判据自足（不靠回执里手抄一个数）。本机实测：改前那一列
    /// 落地 **520.0pt**（＝它的 `maxWidth`：`HSplitView` 先各半分，中栏那半 549.5pt 被夹住），
    /// 右栏 579.0pt，两列和 1099pt ＋ 1pt 分隔线 ＝ 宿主 1100pt。
    ///
    /// ## 判据（缺一不算交付）
    ///
    ///   ① **中栏整列**：`改后 ≤ 改前 × 0.60`（旧口径 · 以离屏 520 为基准 ⇒ 限额 312pt）；
    ///   ①b **改后目标档**：`改后 ≤ 238.0pt`（本轮前门 `T-20261009-001` 给的目标档；
    ///      真机口径 `397 × 0.60 = 238.2` ⇒ ≤238 —— 这一条**更严**，是新增的「期望值」）；
    ///   ② **旁证（守恒）**：右栏（`NotesEditorView` 那一列）**变宽**，且**两列宽度和不变**
    ///      —— 整窗不变 ⇒ 中栏让出去的那一块原样进右栏，不是两列一起缩；
    ///   ③ **「量的确实是列表那一列」**：笔记列表（`NSTableView`）必须**落在左那一子视图里**
    ///      （不按位置假定，也不靠源码锚点）。
    ///
    /// ## 能判红（否则「改小了」会被读成「都对」）
    ///
    /// 反例 = **改动前那一版**：那时生产与复刻件是同一组常量 ⇒ 中栏两次都量到 520.0pt，
    /// `520.0 ≤ 520.0 × 0.60` 当场红（本机实测：改动前跑本用例 = 1 failure）。
    /// **不许跳过** —— 量不到两列（视图树变了）或列表不在左列，直接判红收场，本用例里没有 `XCTSkip`。
    ///
    /// ## 边界（如实登记）
    ///
    /// · 量的是**离屏宿主里两列的落地宽度**，不是真窗口上用户拖动分栏之后的宽度（用户拖动的宽度
    ///   本片**不碰**：不给 `HSplitView` 加持久化）；
    /// · 宿主宽 1100 ＝ 应用窗口内容区的**最小**宽（`App/DoyahStudioApp.swift` 的 `.frame(minWidth: 1_100…)`）；
    ///   真实运行时笔记区还要再窄（要减去活动栏与侧栏）—— 但**这一列实际多宽由 `maxWidth` 定**
    ///   （实测：宿主 700 / 800 / 852 / 1400 四档下，中栏宽 349.5 / 399.5 / 425.5 / 520.0pt，
    ///   都是「各半分，超 `maxWidth` 就夹住」的同一条规律），所以宿主再宽读数也一样；
    /// · 不判观感（「这样看着舒服吗」）—— 那是人类主人按整窗图看的那一半。
    @MainActor
    func testNotesListColumnWidthShrunk() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }

        // ── 改后：生产那一份（窄的是 `NotesAreaView` 里的 `listPane*Width`）──────────────────
        let after = makeLive(host)

        // ── 改前：复刻件（同骨架 · 中栏三档 = 改前那三个数）─────────────────────────────────
        let before = makeOffscreenHost(
            host,
            HSplitView {
                NotesListView()
                    .frame(minWidth: 220, idealWidth: 300, maxWidth: 520)
                NotesEditorView()
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )

        /// 宿主里那两列（左 = 中栏 / 右 = 正文那一列）各自的**真视图**与**落地宽度**。
        /// 分隔线那一子按宽度滤掉（实测 5pt，与两列相叠）。
        func panes(_ hosting: NSView) throws -> (left: NSView, right: NSView, leftWidth: CGFloat, rightWidth: CGFloat) {
            let split = try XCTUnwrap(
                UISnapshot.LiveHost<Never>.findViews(ofType: NSSplitView.self, in: hosting).first,
                "宿主里没有 `NSSplitView` —— `HSplitView` 没落地，量不到「整列宽度」（判据的入口没了）"
            )
            let ordered = split.subviews
                .map { (view: $0, rect: rect(of: $0, in: hosting)) }
                .filter { $0.rect.width > 8 }
                .sorted { $0.rect.minX < $1.rect.minX }
            let pair = try XCTUnwrap(
                ordered.count == 2 ? ordered : nil,
                "`HSplitView` 里量到的不是两列（实测 \(ordered.count) 列）—— 判据量不到「中栏 / 右栏」"
            )
            return (pair[0].view, pair[1].view, pair[0].rect.width, pair[1].rect.width)
        }

        let afterPanes = try panes(after.hosting)
        let beforePanes = try panes(before.hosting)

        // ── ③「左那一列 = 存放笔记列表的那一列」量实（不按位置假定）───────────────────────────
        let list = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: NSTableView.self, in: after.hosting).first,
            "宿主里没有 `NSTableView` —— 笔记列表没落地，判据量不到「存放笔记列表的那一列」"
        )
        XCTAssertTrue(
            list.isDescendant(of: afterPanes.left),
            "笔记列表（`NSTableView`）不落在左边那一子视图里 —— 量到的左列不是「存放笔记列表的左侧」"
        )

        let limit = beforePanes.leftWidth * 0.60
        print(
            "NOTES-LAYOUT N2-LW 中栏整列宽度（成对读数 · 同一轮两件在位）："
                + "改前 \(pt(beforePanes.leftWidth))pt → 改后 \(pt(afterPanes.leftWidth))pt"
                + "（限额 = 改前 × 0.60 = \(pt(limit))pt，余量 \(pt(limit - afterPanes.leftWidth))pt）"
                + " ｜ 右栏 \(pt(beforePanes.rightWidth))pt → \(pt(afterPanes.rightWidth))pt"
                + " ｜ 两列和 \(pt(beforePanes.leftWidth + beforePanes.rightWidth))pt → "
                + "\(pt(afterPanes.leftWidth + afterPanes.rightWidth))pt"
                + "（宿主 \(pt(areaSize.width))×\(pt(areaSize.height))，两列 + 1pt 分隔线）"
        )

        // ① 中栏整列 ≤ 改前 × 0.60
        XCTAssertGreaterThan(
            beforePanes.leftWidth, 100,
            "改前那一半量到 \(pt(beforePanes.leftWidth))pt —— 对照件不成立，下面那条比不出东西"
        )
        XCTAssertLessThanOrEqual(
            afterPanes.leftWidth, limit,
            "中栏（存放笔记列表的那一列）整列没收到改前的 60% 以内：改后 \(pt(afterPanes.leftWidth))pt"
                + " ＞ 限额 \(pt(limit))pt（改前 \(pt(beforePanes.leftWidth))pt）"
                + " —— 「左栏整体太宽了」指的就是这一列（不是最左侧的笔记本导航栏）"
        )
        // 一对读数不许恒等（否则「改小了」这句话没有内容）。
        XCTAssertNotEqual(
            afterPanes.leftWidth, beforePanes.leftWidth,
            "改前 / 改后量到同一个宽度（\(pt(afterPanes.leftWidth))pt）⇒ 这一对读数是恒真的"
        )

        // ② 旁证：右栏变宽 + 两列和守恒（整窗不变 ⇒ 让出去的那一块进了右栏）
        XCTAssertGreaterThan(
            afterPanes.rightWidth, beforePanes.rightWidth,
            "右栏（正文那一列）没有变宽：\(pt(beforePanes.rightWidth))pt → \(pt(afterPanes.rightWidth))pt"
                + " —— 整窗不变时中栏收掉的宽度应当原样进右栏"
        )
        XCTAssertEqual(
            afterPanes.leftWidth + afterPanes.rightWidth,
            beforePanes.leftWidth + beforePanes.rightWidth,
            accuracy: 1,
            "两列宽度和变了（\(pt(beforePanes.leftWidth + beforePanes.rightWidth))pt → "
                + "\(pt(afterPanes.leftWidth + afterPanes.rightWidth))pt）—— 那不是「中栏让宽」，是整块布局被动了"
        )

        // ①b **改后目标档**（前门裁决 `T-20261009-001`：真机口径 `397 × 0.60 = 238.2` ⇒ ≤238pt）。
        // 上面那条相对判据（≤ 改前 × 0.60 = 312pt）是**原来的口径**（以旧离屏 520 为基准），
        // 这一条是**本轮前门给的目标档**：改后读数必须落在 **238.0pt** 里。两条都留着 ——
        // 新的那条更严，旧的留作「≤ 旧口径 60%」的旁证（不删、不放宽）。
        print(
            "NOTES-LAYOUT N2-LW-238 改后目标档：中栏改后 \(pt(afterPanes.leftWidth))pt ≤ 238.0pt"
                + "（改前 = \(pt(beforePanes.leftWidth))pt 离屏留档 · 上一版改后读数 = 300.0pt 离屏留档）"
        )
        XCTAssertLessThanOrEqual(
            afterPanes.leftWidth, 238.0,
            "中栏整列没收到前门给的 **238pt** 档：改后 \(pt(afterPanes.leftWidth))pt ＞ 238.0pt"
                + "（`T-20261009-001`：宽度判据取真机真实窗口 ⇒ 397 × 0.60 = 238.2 ⇒ ≤238pt）"
        )
    }

    // MARK: - N2-LW-238 中栏头部在 238pt 档下不溢出（`T-20261009-001` 判据 2）

    /// **238pt 档下「中栏头部内容 ≤ 中栏可用宽度」（0 溢出）+ 工具条确实分了两行**。
    ///
    /// ## 由头（238 档的已登记缺陷）
    ///
    /// `a8454d8` 只把三档常量收到 238 时 **中栏自身的头部放不下**：`Notes 4` 被挤断成
    /// `Not` / `es` 两行、排序条被裁到栏外（旧图 `.build/n2lw-shots/after-1352.png`）。
    /// 前门 `T-20261009-001` 因此**允许工具条分 2 行**、但**头部不许断词**。本用例量「重排之后
    /// 头部还溢不溢」。
    ///
    /// ## 入口（与 `testNotesListColumnWidthShrunk` 同一套离屏宿主）
    ///
    /// `areaSize = 1100×700`；`HSplitView` 落地成真 `NSSplitView`，**左那一子 = 中栏**
    /// （宽 = `listPaneMaxWidth`）。头部那一带 = **栏内上缘往下 90pt** 的一条带。带里量得到的
    /// 是 **AppKit 承载的那几件**：排序条（`Picker(.menu)`）与「只看收藏」开关各落地成一个
    /// `_FocusRingView`（读数逐件 `print`）。
    ///
    /// ## 判据（缺一不绿）
    ///   ① **入口在**：头部带里至少量到 2 件控件 —— 一件都量不到 ⇒ 判红（不许悄悄跳过）；
    ///   ② **0 溢出**：每一件的右边缘 ≤ 中栏右边缘（容差 0.5pt = 子像素），且并集宽度 ≤ 中栏宽度；
    ///   ③ **工具条分了两行**：带里最高与最低那两件的**上缘相差 ≥ 20pt** —— 这是「允许工具条分
    ///      2 行」落地后的几何形状（改前的**单行**布局里两件同高，本判据当场红）；
    ///   ④ **源锚点（不许断词 / 不许截断）**：标题带 `.lineLimit(1)` + 横向 `fixedSize`；
    ///      两个判定入口 `notes-sort` / `notes-favorite-filter` 与搜索框占位键一字未动。
    ///
    /// ## 能判红（否则「量不到」会被读成「都对」）
    /// 把头部改回**单行**（`listHeader` 里两行并回一行）⇒ ③ 当场红；把中栏放回 300pt 档
    /// ⇒ ② 的并集宽度读数变宽、① 的入口仍在（② 仍绿 —— 它判的是溢出，不是宽度档，宽度档归
    /// `testNotesListColumnWidthShrunk`）。
    ///
    /// ## 边界（如实登记）
    /// · 量到的是**头部里 AppKit 承载的那几件**；标题 / 条数是 SwiftUI 文本、在这个离屏宿主里
    ///   **不落地成 `NSView`**（同文件既有的两条边界实测）⇒ 它们的宽度**量不到** ——
    ///   「标题不断词、搜索占位完整」那一半由 ④ 的源锚点钉住，**真实渲染那一半交真机整屏图人工判**
    ///   （回执里给成对图，本用例不许自称绿）；
    /// · 不判观感。
    @MainActor
    func testNotesListHeaderFitsInsideTheNarrowListPane() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let live = makeLive(host)

        let split = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: NSSplitView.self, in: live.hosting).first,
            "宿主里没有 `NSSplitView` —— `HSplitView` 没落地，量不到「中栏」"
        )
        let columns = split.subviews
            .map { (view: $0, rect: rect(of: $0, in: live.hosting)) }
            .filter { $0.rect.width > 8 }
            .sorted { $0.rect.minX < $1.rect.minX }
        let pane = try XCTUnwrap(
            columns.first,
            "`HSplitView` 里量不到列（实测 \(columns.count) 列）—— 判据量不到「中栏头部」"
        )
        let paneRect = pane.rect

        /// 头部那一带里的 AppKit **控件**：栏内上缘往下 90pt、高 ≤ 40pt（头部两行里最高的那件
        /// 也只有 24pt —— 这一刀把栏内容器视图（整条 56pt 高的头部栈）挡在外面）、
        /// 左缘不越过栏左缘（`KeyViewProxy` 那类代理会带负的 x，它是宿主内部件不是界面件）。
        let headerRects = UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: pane.view)
            .filter { $0 !== pane.view }
            .map { rect(of: $0, in: live.hosting) }
            .filter { r in
                guard !r.isEmpty, r.width > 1, r.height > 1, r.height <= 40 else { return false }
                guard r.minX >= paneRect.minX - 0.5, r.maxX > paneRect.minX else { return false }
                let topOffset = distanceToTopEdge(r, in: live.hosting) - distanceToTopEdge(paneRect, in: live.hosting)
                return topOffset >= -1 && topOffset <= 90
            }
            // 同一件控件被 SwiftUI 的桥接层包了两三层（`_FocusRingView` / 宿主容器），
            // 取**同矩形**里最内层那一件即可 —— 按矩形去重，免得同一件被算两次把并集算歪。
            .reduce(into: [CGRect]()) { unique, r in
                if !unique.contains(where: { abs($0.minX - r.minX) < 0.5 && abs($0.maxX - r.maxX) < 0.5
                    && abs($0.minY - r.minY) < 0.5 }) {
                    unique.append(r)
                }
            }
            .sorted { $0.minX < $1.minX }

        for r in headerRects {
            print(
                "NOTES-LAYOUT N2-LW-238 头部件：x=[\(pt(r.minX))…\(pt(r.maxX))] w=\(pt(r.width))"
                    + " h=\(pt(r.height)) top=+\(pt(distanceToTopEdge(r, in: live.hosting) - distanceToTopEdge(paneRect, in: live.hosting)))"
            )
        }
        let union = headerRects.reduce(CGRect.null) { $0.union($1) }
        let tops = headerRects.map { distanceToTopEdge($0, in: live.hosting) }
        let spread = (tops.max() ?? 0) - (tops.min() ?? 0)
        let overflow = headerRects.map { $0.maxX - paneRect.maxX }.max() ?? 0
        print(
            "NOTES-LAYOUT N2-LW-238 中栏头部：中栏 x=[\(pt(paneRect.minX))…\(pt(paneRect.maxX))] w=\(pt(paneRect.width))"
                + " ｜ 头部件 \(headerRects.count) 件 · 并集 w=\(pt(union.width))"
                + " ｜ 最右溢出 \(pt(overflow))pt ｜ 两行落差 \(pt(spread))pt"
        )

        // ① 入口在
        XCTAssertGreaterThanOrEqual(
            headerRects.count, 2,
            "中栏头部带里量到的控件不足 2 件（实测 \(headerRects.count) 件）—— 判据的入口没了"
                + "（排序条 / 只看收藏开关都是 AppKit 承载的控件，量不到就说明头部形态变了）"
        )
        // ② 0 溢出
        XCTAssertLessThanOrEqual(
            union.width, paneRect.width,
            "中栏头部内容宽度 \(pt(union.width))pt ＞ 中栏可用宽度 \(pt(paneRect.width))pt —— 头部溢出了这一栏"
        )
        XCTAssertLessThanOrEqual(
            overflow, 0.5,
            "中栏头部有控件越过这一栏的右边缘 \(pt(overflow))pt（> 0.5pt 容差）—— 排序条被裁到栏外就是这个症状"
        )
        // ③ 工具条分了两行
        XCTAssertGreaterThanOrEqual(
            spread, 20,
            "中栏头部那几件**同高**（上缘落差 \(pt(spread))pt）—— 工具条没有分两行，还是改前那条单行布局"
                + "（238pt 档下单行放不下，`Notes 4` 会被挤断）"
        )
        // ④ 源锚点（不许断词 / 不许截断 · 判定入口一字未动）
        let source = try notesPanelSource()
        for anchor in [
            "private var listHeader: some View",
            ".fixedSize(horizontal: true, vertical: false)",
            ".accessibilityIdentifier(\"notes-sort\")",
            ".accessibilityIdentifier(\"notes-favorite-filter\")",
            "TextField(L(.notesSearchPlaceholder), text: $appState.notesQuery)",
        ] {
            XCTAssertTrue(source.contains(anchor), "源锚点失配：`\(anchor)` 不在 `App/Views/NotesPanel.swift` 里")
        }
    }
}
