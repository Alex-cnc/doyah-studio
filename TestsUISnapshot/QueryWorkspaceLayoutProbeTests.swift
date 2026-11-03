import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **查询页「工具条 ↔ 编辑区 ↔ 结果面」几何判据**（人类主人 2026-11-03 21:06 实测反馈：
/// 「数据库客户端的界面怎么又乱了」）。
///
/// ## 由头（截图上逐行量的读数，单位 pt）
///
/// · 上下文栏（服务器 / 库下拉）落在 **144–160**；
/// · 工具条那一排图标落在 **312–340**；
/// · SQL 编辑区的深色面从 **480** 才开始；结果面（网格 / 分页条 / 筛选条）一个像素都没有。
///
/// 三条合起来只有一个解释：**工具条那一行被拉成了约 320 pt 高的可伸缩行、内容竖直居中**
/// —— 上下各剩一片约 150 pt 的星空空白。
///
/// ## 根因（本探针钉住的形状，离屏活宿主实测）
///
/// 工具条 `HStack` 里挂着 `SQLTaskMenuButton`（`App/Views/SQLTaskAppKitMenu.swift`，
/// 一枚 `NSViewRepresentable` 包着的 `NSButton`）。macOS 上 `NSViewRepresentable`
/// **默认按父级提出的尺寸铺满**、不按内在尺寸收敛 ⇒ 缺 `sizeThatFits` 时那枚按钮被拉成
/// **540.5 × 307.5 pt**，整条 `HStack` 因此变成纵向可伸缩行（302.5 pt 高）；它又是
/// `QueryEditorView` 外层 `VStack` 的直接子视图 ⇒ `VStack` 把剩余高度在「工具条」与下面的
/// `GeometryReader`（编辑区 + 结果面）之间**对半分**，编辑区与结果面一起被压扁。
///
/// ## 判据（全部量真 AppKit 视图树里的 frame；坐标统一折算成「向下为正」）
///
/// ① **工具条那一行是一行，不是一片**：那枚 `NSButton` 的高度 ≤ 40 pt（反例 307.5 pt）；
/// ② **上下文栏到编辑区之间只许有两个工具条的高度**：编辑区上边缘 − 上下文栏下边缘 ≤ 72 pt
///    （反例 326.5 pt —— 多出来的就是那两片空白）；
/// ③ **结果面真的在、且紧贴编辑区**：结果面（表格所在滚动视图）的高度 > 60 pt，
///    且其上边缘 − 编辑区下边缘 ≤ 60 pt（中间只该有一条分隔条 / 一行出处）。
///
/// 三条都先过**前提断言**（按钮 / 编辑器 / 表格必须真在视图树里）—— 找不到就红，
/// 不许悄悄跳过（跳过会被读成通过）。
///
/// ## 反例读数（把 `sizeThatFits` 拿掉，即 2026-11-03 的真仓库状态）
///
/// · ① NSButton = 540.5 × **307.5**（修好应 ≈ 28 × 28）⇒ 红
/// · ② 编辑区上边缘 401.5 − 上下文栏下边缘 ≈ 75 = **326.5**（应 ≤ 72）⇒ 红
/// · ③ 编辑区只剩 158.5 pt、结果面 159 pt —— 半页被工具条吃掉
///
/// ## 边界（如实登记）
///
/// · 量的是**离屏**宿主（`NSHostingView` 不上屏），不是真屏幕像素；上屏那一版由人类主人点验；
/// · 夹具结果集是合成数据，不连数据库；
/// · 不判观感（配色 / 间距好不好看）；
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 与其他端上探针同一条纪律：取证才跑。
final class QueryWorkspaceLayoutProbeTests: XCTestCase {

    /// 宿主尺寸：与截图里右栏同量级（内容区 ≈ 1000 × 700）。
    private let pageSize = CGSize(width: 1000, height: 700)

    /// 判据②的上限：上下文栏一行(~26) + 工具条一行(~28) + 两条分隔与内边距。
    private let toolbarBlockLimit: CGFloat = 72

    // MARK: - 合成结果

    private let columns = [
        ColumnMeta(id: 0, name: "id", typeName: "int4"),
        ColumnMeta(id: 1, name: "note", typeName: "text"),
    ]

    private let rows: [[String?]] = [["1", "a"], ["2", "b"], ["3", "c"]]

    private enum ProbeError: Error { case fixture }

    private struct Host {
        let window: NSWindow
        let hosting: NSHostingView<AnyView>
        let state: AppState

        /// **刻意不释放**：`AppState` 里挂着数据库连接池，`PostgresNIO` 在
        /// `PostgresConnection` 未关闭就被析构时会 `Assertion failed` 直接 `SIGTRAP`
        /// 掉整个 xctest 进程（本轮实测：三条用例只跑完第一条，余下两条一条读数都出不来）。
        /// 探针只活一个进程的时间，别的用例不受这条约束。
        func tearDown() {}
    }

    /// 进程级保活（理由见 `Host.tearDown`）。
    private static var retained: [Any] = []

    private func skipUnlessProbeEnabled() throws {
        guard ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1" else {
            throw XCTSkip("几何探针要真 AppKit 视图树：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）")
        }
    }

    // MARK: - 装配（真 QueryWorkspaceView + 一个真页签 + 一条真表格结果）

    @MainActor
    private func mount() throws -> Host {
        let state = AppState()
        state.connections = []
        state.selectedConnectionID = nil
        state.newQueryTab()

        guard let tabID = state.selectedTabID,
              let index = state.tabs.firstIndex(where: { $0.id == tabID }) else {
            XCTFail("newQueryTab 之后没有选中页签 —— 夹具坏了")
            throw ProbeError.fixture
        }
        state.tabs[index].sql = "select id, note from demo"
        state.tabs[index].results = [QueryResult(columns: columns, rows: rows, executionTime: 0.01)]
        state.tabs[index].selectedResultIndex = 0

        let root = AnyView(
            QueryWorkspaceView()
                .environmentObject(state.editorBuffer)
                .snapshotEnvironment(
                    state: state,
                    workspace: WorkspaceStore.shared,
                    tabs: WorkspaceTabsModel(),
                    terminal: TerminalModel()
                )
        )

        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: pageSize)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: pageSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        pump()

        Self.retained.append(contentsOf: [state, hosting, window] as [Any])
        return Host(window: window, hosting: hosting, state: state)
    }

    @MainActor
    private func pump(_ seconds: TimeInterval = 0.5) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    // MARK: - 坐标系（`NSHostingView` 是 flipped：y 向下为正；不是就先折过来）

    /// 把一个视图的 frame 折成「向下为正」：`minY` = 上边缘，`maxY` = 下边缘。
    /// 不折的话，「谁在谁上面」会整个反过来（本轮实测：不折时结果面读到 -329，
    /// 看着像「表格跑到编辑区上方」，其实只是坐标系反了）。
    @MainActor
    private func rect(of view: NSView, in host: NSView) -> CGRect {
        var r = view.convert(view.bounds, to: host)
        if !host.isFlipped {
            r.origin.y = host.bounds.height - r.maxY
        }
        return r
    }

    // MARK: - 视图树里找东西

    /// 编辑器：文档视图是 `SQLTextView` 的那个滚动视图。
    @MainActor
    private func editorScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.documentView is SQLTextView { return scroll }
        for child in view.subviews {
            if let found = editorScrollView(in: child) { return found }
        }
        return nil
    }

    @MainActor
    private func firstTableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for child in view.subviews {
            if let found = firstTableView(in: child) { return found }
        }
        return nil
    }

    @MainActor
    private func allViews(in view: NSView, into out: inout [NSView]) {
        out.append(view)
        for child in view.subviews { allViews(in: child, into: &out) }
    }

    /// 编辑区 / 结果面那一个 `VSplitView` 落地出来的 `NSSplitView`。
    @MainActor
    private func firstSplitView(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView { return split }
        for child in view.subviews {
            if let found = firstSplitView(in: child) { return found }
        }
        return nil
    }

    /// 「任务」菜单那枚按钮：`SQLTaskMenuButton.updateNSView` 把 `help` 挂成 `toolTip`。
    @MainActor
    private func taskMenuButton(in host: NSView) -> NSButton? {
        var views: [NSView] = []
        allViews(in: host, into: &views)
        let help = L(.sqlTaskMenuHelp)
        return views.compactMap { $0 as? NSButton }.first { $0.toolTip == help }
    }

    /// 上下文栏 —— 服务器 / 库下拉（树里最上面那一枚 SwiftUI 弹窗按钮）的下边缘。
    @MainActor
    private func contextBarBottom(in host: NSView) -> CGFloat? {
        var views: [NSView] = []
        allViews(in: host, into: &views)
        let popups = views.filter { String(describing: type(of: $0)) == "SwiftUIPopupButton" }
        guard let top = popups.min(by: { rect(of: $0, in: host).minY < rect(of: $1, in: host).minY })
        else { return nil }
        return rect(of: top, in: host).maxY
    }

    // MARK: - 读数

    private struct Readings {
        let taskButton: CGRect
        let contextBarBottom: CGFloat?
        let editor: CGRect
        let resultFace: CGRect?
        let resultScroll: CGRect?

        /// ② 上下文栏下边缘 → 编辑区上边缘：这一段里只该有两个工具条。
        var toolbarBlock: CGFloat? { contextBarBottom.map { editor.minY - $0 } }
        /// ③ 编辑区下边缘 → **结果面容器**上边缘（容器 = `VSplitView` 第二项，含出处 / 筛选 / 分页那些条）。
        var editorToResultGap: CGFloat? { resultFace.map { $0.minY - editor.maxY } }
    }

    @MainActor
    private func measure(_ host: Host) throws -> Readings {
        let hosting = host.hosting

        let button = try XCTUnwrap(
            taskMenuButton(in: hosting),
            "视图树里没有「任务」菜单那枚按钮 —— 工具条没挂上（后续判据会量到假值）"
        )
        let editor = try XCTUnwrap(
            editorScrollView(in: hosting),
            "视图树里没有编辑器（文档视图应为 SQLTextView）—— 挂载路径坏了"
        )

        let table = firstTableView(in: hosting)

        // 结果面容器：`VSplitView` 的第二项（第一项是编辑区）。按**容器**量而不是按表格量 ——
        // 表格上方还有出处 / 客户端视图 / 筛选项那几条，按表格量会把它们算成「空白」。
        let resultFace = firstSplitView(in: hosting).flatMap { split -> CGRect? in
            guard split.arrangedSubviews.count >= 2 else { return nil }
            return rect(of: split.arrangedSubviews[1], in: hosting)
        }

        return Readings(
            taskButton: rect(of: button, in: hosting),
            contextBarBottom: contextBarBottom(in: hosting),
            editor: rect(of: editor, in: hosting),
            resultFace: resultFace,
            resultScroll: table.flatMap { $0.enclosingScrollView }.map { rect(of: $0, in: hosting) }
        )
    }

    /// 诊断用：把视图树按类型 + frame 打出来（`DOYAH_PROBE_DUMP=1` 才打）。
    @MainActor
    private func dumpTree(_ view: NSView, in host: NSView, depth: Int = 0, limit: Int = 14) {
        if depth > limit { return }
        print(String(repeating: "  ", count: depth) + "\(type(of: view)) frame=\(rect(of: view, in: host))")
        for child in view.subviews { dumpTree(child, in: host, depth: depth + 1, limit: limit) }
    }

    private var dumpRequested: Bool {
        ProcessInfo.processInfo.environment["DOYAH_PROBE_DUMP"] == "1"
    }

    // MARK: - 判据

    /// ① 工具条那一行必须是一行 —— 不是被 `NSViewRepresentable` 拉成的一片。
    @MainActor
    func testToolbarRowHugsItsContent() throws {
        try skipUnlessProbeEnabled()
        let host = try mount()
        defer { host.tearDown() }

        let readings = try measure(host)
        print("【读数①】任务按钮 = \(readings.taskButton)")

        XCTAssertLessThanOrEqual(
            readings.taskButton.height, 40,
            "「任务」菜单那枚 NSButton 被拉到了 \(readings.taskButton.width) × "
                + "\(readings.taskButton.height) pt —— 它所在的 HStack 变成了纵向可伸缩行"
                + "（NSViewRepresentable 按提出尺寸铺满、自己没报 sizeThatFits），"
                + "工具条于是吃掉一半剩余高度、上下各留一片空白"
        )

        if dumpRequested { dumpTree(host.hosting, in: host.hosting, limit: 18) }
    }

    /// ② 上下文栏到编辑区之间只许有两个工具条的高度 —— 不许出现成片空白。
    @MainActor
    func testNoVoidBetweenToolbarAndEditor() throws {
        try skipUnlessProbeEnabled()
        let host = try mount()
        defer { host.tearDown() }

        let readings = try measure(host)
        let block = try XCTUnwrap(
            readings.toolbarBlock,
            "视图树里找不到上下文栏的下拉框 —— 量不到这一段的高度（不许当成通过）"
        )
        print("【读数②】上下文栏下边缘 → 编辑区上边缘 = \(block) pt（上限 \(toolbarBlockLimit)）")
        print("【读数②】编辑区 = \(readings.editor)")

        if block > toolbarBlockLimit && dumpRequested {
            dumpTree(host.hosting, in: host.hosting)
        }

        XCTAssertLessThanOrEqual(
            block, toolbarBlockLimit,
            "上下文栏与编辑区之间占了 \(block) pt —— 这一整段应当只有「上下文栏一行 + 工具条一行」"
                + "（上限 \(toolbarBlockLimit) pt）。多出来的就是工具条被拉成可伸缩行后留下的空白"
        )
    }

    /// ③ 结果面真的在，且紧贴编辑区（不是被压成 0，也不是被空白顶走）。
    @MainActor
    func testResultFaceRendersBelowEditor() throws {
        try skipUnlessProbeEnabled()
        let host = try mount()
        defer { host.tearDown() }

        let readings = try measure(host)
        let result = try XCTUnwrap(
            readings.resultScroll,
            "有表格结果的页签却没有结果面（NSTableView 不在视图树里）—— 结果面根本没渲染"
        )
        let face = try XCTUnwrap(
            readings.resultFace,
            "`VSplitView` 里没有结果面那一项 —— 结果面没进场"
        )
        let gap = try XCTUnwrap(readings.editorToResultGap)
        print("【读数③】编辑区 = \(readings.editor)")
        print("【读数③】结果面容器 = \(face) · 其中表格滚动视图 = \(result)")
        print("【读数③】编辑区下边缘 → 结果面容器上边缘 = \(gap) pt")

        XCTAssertGreaterThan(face.height, 60, "结果面高度只有 \(face.height) pt —— 被挤没了")
        XCTAssertGreaterThan(result.height, 60, "结果表高度只有 \(result.height) pt —— 被挤没了")
        XCTAssertLessThanOrEqual(
            gap, 20,
            "编辑区与结果面之间隔着 \(gap) pt —— 中间只该有一条分隔条（≤ 20 pt 容差）"
        )

        if dumpRequested { dumpTree(host.hosting, in: host.hosting, limit: 18) }
    }
}
