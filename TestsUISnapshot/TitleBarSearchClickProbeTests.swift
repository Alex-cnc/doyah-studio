import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 标题栏搜索栏「**看得见的框 = 能点的框**」的**点击地图判据**（派活单 `T-20261002-027`，
/// 承接 `T-20261002-011` / `041` / `051`；开发循环第 162 轮）。
///
/// ## 人类主人原话（未改写 · 2026-10-02 下午）
///
/// 「打开Doyah Studio测试，搜索框仍然是无法点击显示鼠标，也无法输入任何字母，跟没修复之前是一样的问题。」
///
/// ## 本轮量到的真因（不是「注入不了点击」，是**点击到不了那层接力**）
///
/// 第 161 轮那层接力**装上了，可点击落在它上面之前就被收走了**：SwiftUI 画的背景
/// `RoundedRectangle`（填充）与 `strokeBorder`（边线）**默认参与命中测试**，它们压在那层
/// AppKit 接力之上 ⇒ 真窗口里点留白，命中目标是 `NSHostingView`（SwiftUI 收走，没人处理）
/// ⇒ 没光标、打不出字 —— 与修前**一模一样**。用本文件同一套量法喂修前那份框实测：
/// 可见框内**只有圆角外那几个角点**能落到接力层，其余留白全落到宿主视图。
///
/// **修法**：装饰层不参与命中测试 —— 背景填充 / 边线 / 放大镜图标各加一处
/// `.allowsHitTesting(false)`（它们只负责画，不该把点击从「看得见的框」上收走）。
/// 一个字的 SwiftUI 状态都没动（第 161 轮那条教训继续成立）。

///
/// ## 这份探针判什么（四条，都能判红）
///
/// · ① **地图**：可见框内的采样点逐点断言命中目标 = 输入框或其接力层，任一点落空 ⇒ 判红；
/// · ② **真的给到键盘**：留白点按下 ⇒ 同一框里那枚输入框拿到第一响应者（读窗口的
///   `firstResponder`，不是读模型）；
/// · ③ **清空按钮那一段留给 SwiftUI**：接力层不许吞掉 `×` 的点击（宽度按 `trailingReserve` 让开）；
/// · ④ **红/绿成对**：同一套量法喂「修前那份框」（装饰参与命中测试）必须判红 —— 否则
///   这套量法量不出这件事，① 的绿也是假绿。
///
/// ## 怎么判（零权限）
///
/// 手工搭一个**真窗口 + `NSToolbar`**，把 `NSHostingView` 装进工具条项（与 SwiftUI
/// `.toolbar { ToolbarItem(placement: .principal) }` 同形）；命中测试走的是 AppKit 自己那条路
/// （`hitTest` 递归到子视图），合成事件的投递在**进程内**完成 ⇒ 不需要辅助功能 / 屏幕录制授权。
///
/// ## 边界（如实登记，别当已验）
///
/// · 宿主是**手工搭的**工具条窗口，**不是** App 自己那个窗口：SwiftUI 自家工具条那条接线、
///   系统怎么把真鼠标事件送进来，本判据判不到（要人在场点一次才算走完）；
/// · 本进程**拿不到 key 窗口**（实测 `isKeyWindow=false key=false`）：合成点击打在**输入框
///   自己身上**时 AppKit 那条编辑路径不会起来（第一响应者仍是窗口）⇒ ② 只判**留白点**
///   （那半是产品代码自己调 `makeFirstResponder`，不依赖窗口是不是 key）；
/// · 清空按钮的**动作**（点一下真把词清掉）进程内判不到：合成事件唤不起 SwiftUI 的手势识别
///   （实测投递 `mouseDown` + `mouseUp` 后查询词原样）⇒ ③ 只判「那一段没被接力层吞掉」。
final class TitleBarSearchClickProbeTests: XCTestCase {

    // MARK: - 宿主（手工工具条窗口）、几何、落点

    /// 工具条那一项：把**产品的那枚搜索栏**装进 `NSHostingView`（与 SwiftUI 工具条项同形）。
    private final class ToolbarItemDelegate: NSObject, NSToolbarDelegate {
        let item: NSToolbarItem
        init(item: NSToolbarItem) { self.item = item }
        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [item.itemIdentifier]
        }
        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [item.itemIdentifier]
        }
        func toolbar(
            _ toolbar: NSToolbar,
            itemForItemIdentifier identifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            identifier == item.itemIdentifier ? item : nil
        }
    }

    private struct Host {
        let window: NSWindow
        let hosting: NSHostingView<AnyView>
        private let delegate: ToolbarItemDelegate

        init(_ root: some View) {
            let hosting = NSHostingView(rootView: AnyView(root))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("titlebar-search-click-probe"))
            item.view = hosting
            let delegate = ToolbarItemDelegate(item: item)
            let toolbar = NSToolbar(identifier: "titlebar-search-click-probe")
            toolbar.delegate = delegate
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            window.makeKeyAndOrderFront(nil)
            window.layoutIfNeeded()
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            window.layoutIfNeeded()
            hosting.layoutSubtreeIfNeeded()
            self.window = window
            self.hosting = hosting
            self.delegate = delegate
        }

        /// 可见框内那三块矩形（**框内坐标**，由视图树实量，不是写死的数）。
        @MainActor
        var geometry: Geometry {
            let field = UISnapshot.LiveHost<Never>.findViews(ofType: NSTextField.self, in: hosting).first
            let relay = UISnapshot.LiveHost<Never>.findViews(
                ofType: TitleBarSearchClickRelay.RelayView.self,
                in: hosting
            ).first
            return Geometry(
                box: hosting.bounds,
                fieldRect: field.map { hosting.convert($0.bounds, from: $0) } ?? .zero,
                relayRect: relay.map { hosting.convert($0.bounds, from: $0) } ?? .zero,
                fieldView: field,
                relayView: relay
            )
        }

        /// 一个点按下去，命中测试会把它交给谁（走 AppKit 自己那条路）。
        @MainActor
        func hit(_ point: NSPoint) -> NSView? {
            hosting.hitTest(hosting.convert(point, to: hosting.superview))
        }

        @MainActor
        func click(_ point: NSPoint) -> NSView? {
            guard let target = hit(point) else { return nil }
            let event = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 100, y: 100),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )!
            target.mouseDown(with: event)
            return target
        }
    }

    private struct Geometry {
        let box: NSRect
        let fieldRect: NSRect
        let relayRect: NSRect
        let fieldView: NSTextField?
        let relayView: TitleBarSearchClickRelay.RelayView?
    }

    /// 一个采样点的落点分类（判据只认前两种）。
    private enum Landing: String {
        case field = "输入框"
        case relay = "接力层"
        case other = "别的视图"
        case nothing = "落空"

        var reachable: Bool { self == .field || self == .relay }
    }

    private func landing(of view: NSView?) -> Landing {
        guard let view else { return .nothing }
        if view is NSTextField { return .field }
        if view is TitleBarSearchClickRelay.RelayView { return .relay }
        return .other
    }

    // MARK: - 采样点（按实量的框推出来，不写死）

    /// 可见框内的采样点：**放大镜/左留白那一段**（输入框左缘之外）、**上下留白**
    /// （输入框上下缘之外）、**右留白**、**框中心**、**输入框内**几处。
    private func samplePoints(in geometry: Geometry) -> [(String, NSPoint)] {
        var points: [(String, NSPoint)] = []
        let box = geometry.box
        let field = geometry.fieldRect
        let midY = box.midY
        let midX = box.midX
        // 左留白（含放大镜那 22pt 那一段）：从框左内壁走到输入框左缘
        for x in stride(from: box.minX + 1, to: max(field.minX - 1, box.minX + 2), by: 4) {
            points.append(("左留白/放大镜 x=\(Int(x))", NSPoint(x: x, y: midY)))
        }
        // 上下留白：输入框上下缘之外，横向取几档
        for y in stride(from: box.minY + 1, to: max(field.minY - 0.5, box.minY + 2), by: 1) {
            for x in [box.minX + 6, midX, box.maxX - 6] {
                points.append(("下留白 y=\(Int(y))", NSPoint(x: x, y: y)))
            }
        }
        for y in stride(from: min(field.maxY + 0.5, box.maxY - 1), to: box.maxY, by: 1) {
            for x in [box.minX + 6, midX, box.maxX - 6] {
                points.append(("上留白 y=\(Int(y))", NSPoint(x: x, y: y)))
            }
        }
        // 右留白（没有清空按钮时，接力层铺到框的右边缘）
        for x in stride(from: max(field.maxX + 0.5, box.minX), to: box.maxX, by: 2) {
            points.append(("右留白 x=\(Int(x))", NSPoint(x: x, y: midY)))
        }
        // 框中心与输入框内的几处
        points.append(("框中心", NSPoint(x: midX, y: midY)))
        points.append(("输入框内·左", NSPoint(x: field.minX + 2, y: midY)))
        points.append(("输入框内·右", NSPoint(x: field.maxX - 2, y: midY)))
        points.append(("输入框内·上", NSPoint(x: midX, y: field.maxY - 1)))
        points.append(("输入框内·下", NSPoint(x: midX, y: field.minY + 1)))
        return points
    }

    // MARK: - ① 地图：可见框内的点，要么归输入框、要么归接力层

    @MainActor
    func testEveryVisiblePointInTheBoxLandsOnTheFieldOrTheRelay() throws {
        let state = AppState()
        let host = Host(
            TitleBarSearchField(windowWidth: 1440, titleText: "Doyah Studio - Workspace")
                .environmentObject(state)
        )
        let geometry = host.geometry
        // **非平凡的前提**：可见框真的比输入框大（否则这条判据没有内容）。
        XCTAssertGreaterThan(
            geometry.box.width - geometry.fieldRect.width, 8,
            "输入框铺满了整框 ⇒ 本判据没有可判的留白（量法或界面变了，先核对再改这条）"
        )
        XCTAssertGreaterThan(
            geometry.box.height - geometry.fieldRect.height, 2,
            "输入框铺满了整框高 ⇒ 上下留白那几档没有内容"
        )
        XCTAssertNotNil(geometry.fieldView, "视图树里没有输入框 —— 判据的入口没了")
        XCTAssertNotNil(geometry.relayView, "视图树里没有接力层（第 161 轮那层）—— 判据的入口没了")

        var readings: [String] = []
        var dead: [String] = []
        let points = samplePoints(in: geometry)
        for (name, point) in points {
            let where_ = landing(of: host.hit(point))
            readings.append("\(name)=\(where_.rawValue)")
            if !where_.reachable {
                dead.append("\(name)(\(Int(point.x)),\(Int(point.y)))=\(where_.rawValue)")
            }
        }
        print("TITLEBAR-CLICK ① 采样 \(points.count) 点 ⇒ \(readings.joined(separator: " · "))")
        XCTAssertTrue(
            dead.isEmpty,
            "可见框内有 \(dead.count) 个点点击落空（没有光标、打不出字就是这些点）：\(dead.joined(separator: ", "))"
        )
    }

    // MARK: - ② 留白点按下 ⇒ 同一框里那枚输入框拿到第一响应者

    @MainActor
    func testPaddingClicksHandTheFieldTheKeyboard() throws {
        let state = AppState()
        let host = Host(
            TitleBarSearchField(windowWidth: 1440, titleText: "Doyah Studio - Workspace")
                .environmentObject(state)
        )
        let geometry = host.geometry
        let field = try XCTUnwrap(geometry.fieldView)
        let padding = samplePoints(in: geometry).filter { landing(of: host.hit($0.1)) == .relay }
        // 前提：留白点真的存在（全归输入框的话，这条判据在判别的东西）。
        XCTAssertGreaterThanOrEqual(padding.count, 8, "留白采样点只有 \(padding.count) 个 ⇒ 采样太稀")

        var readings: [String] = []
        var refused: [String] = []
        for (name, point) in padding {
            host.window.makeFirstResponder(nil)
            _ = host.click(point)
            if !isFirstResponderTheField(host.window, field: field) {
                refused.append("\(name)(\(Int(point.x)),\(Int(point.y)))")
            }
            readings.append("\(name)=>\(describeFirstResponder(host.window))")
        }
        print("TITLEBAR-CLICK ② 留白 \(padding.count) 点按下 ⇒ \(readings.joined(separator: " · "))")
        XCTAssertTrue(
            refused.isEmpty,
            "这些留白点按下之后键盘没给到输入框（点了没光标）：\(refused.joined(separator: ", "))"
        )
    }

    /// 窗口的第一响应者是不是那枚输入框（字段编辑器也算 —— 它就是 AppKit 接手编辑后的形态）。
    @MainActor
    private func isFirstResponderTheField(_ window: NSWindow, field: NSTextField) -> Bool {
        guard let responder = window.firstResponder else { return false }
        if let text = responder as? NSTextField { return text === field }
        if let editor = responder as? NSTextView { return (editor.delegate as? NSTextField) === field }
        return false
    }

    @MainActor
    private func describeFirstResponder(_ window: NSWindow) -> String {
        guard let responder = window.firstResponder else { return "nil" }
        if let editor = responder as? NSTextView {
            return (editor.delegate as? NSTextField) != nil ? "字段编辑器(输入框)" : "字段编辑器(别的)"
        }
        if responder is NSTextField { return "输入框" }
        return String(describing: type(of: responder))
    }

    // MARK: - ③ 清空按钮那一段留给 SwiftUI（接力层不许吞掉 `×`）

    @MainActor
    func testClearButtonZoneIsLeftToSwiftUI() throws {
        let state = AppState()
        state.globalSearchQuery = "csv"
        let host = Host(
            TitleBarSearchField(windowWidth: 1440, titleText: "Doyah Studio - Workspace")
                .environmentObject(state)
        )
        let geometry = host.geometry
        let reserve = TitleBarSearchMetrics.trailingReserve(hasClearButton: true)
        XCTAssertGreaterThan(reserve, 8, "清空按钮那一段实量出来只有 \(reserve)pt ⇒ 右留白那几档没有内容")
        XCTAssertEqual(
            geometry.box.width - geometry.relayRect.width, reserve, accuracy: 0.5,
            "接力层没有按 `trailingReserve` 让开清空按钮那一段（会把 `×` 的点击抢走）"
        )
        // 这一段的口径：**接力层不许收**（收到就把 `×` 的点击抢走了），且不能落空
        // （落空说明这一段被谁都不管的视图收走 / 跑到框外去了）。
        // 图标之外那几 pt 是**交给 SwiftUI 的空白**：进程内判不到 SwiftUI 有没有拿它当按钮面
        // （合成事件唤不起 SwiftUI 的手势识别），这一档不判 —— 如实登记在文件头「边界」里。
        var readings: [String] = []
        var swallowed: [String] = []
        for x in stride(from: geometry.relayRect.maxX, through: geometry.box.maxX - 1, by: 3) {
            let where_ = landing(of: host.hit(NSPoint(x: x, y: geometry.box.midY)))
            readings.append("x=\(Int(x))=\(where_.rawValue)")
            if where_ == .relay || where_ == .nothing {
                swallowed.append("x=\(Int(x))=\(where_.rawValue)")
            }
        }
        print("TITLEBAR-CLICK ③ 清空按钮那一段（实量 \(reserve)pt，接力层宽 \(geometry.relayRect.width)/框宽 \(geometry.box.width)）⇒ \(readings.joined(separator: " · "))")
        XCTAssertTrue(
            swallowed.isEmpty,
            "清空按钮那一段被接力层收走 / 落空：\(swallowed.joined(separator: ", ")) —— 前者会把 `×` 的点击抢走"
        )
    }

    // MARK: - ④ 红/绿成对：同一套量法喂**修前那份框**必须判红

    @MainActor
    func testLegacyHitTestableDecorationsWouldSwallowTheBox() throws {
        let host = Host(LegacyHitTestableSearchBox())
        let geometry = host.geometry
        XCTAssertNotNil(geometry.relayView, "对照件里没有接力层 ⇒ 对照失效（它要复现的是第 161 轮那份）")
        var readings: [String] = []
        var unreachable = 0
        let points = samplePoints(in: geometry)
        for (name, point) in points {
            let where_ = landing(of: host.hit(point))
            readings.append("\(name)=\(where_.rawValue)")
            if !where_.reachable { unreachable += 1 }
        }
        print("TITLEBAR-CLICK ④ 修前那份框（装饰参与命中测试）采样 \(points.count) 点 ⇒ 落空 \(unreachable) 点 · \(readings.joined(separator: " · "))")
        XCTAssertGreaterThan(
            unreachable, 0,
            "对照失效：修前那份框居然每个留白点都点得到 ⇒ 本判据量不出「点击到不了接力层」这件事"
        )
    }

    // MARK: - ⑤ 源锚点：装修层别再参与命中测试

    /// 这三处 `.allowsHitTesting(false)` 就是本缺陷的钉：少一处，可见框里的留白就会
    /// 重新点不动（而界面看上去**一模一样**，只有点击地图能看出来）。
    func testSourceAnchorsKeepTheDecorationsOutOfHitTesting() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let field = try String(
            contentsOf: root.appendingPathComponent("App/Views/TitleBarSearchField.swift"),
            encoding: .utf8
        )
        let decorations = field.components(separatedBy: ".allowsHitTesting(false)").count - 1
        XCTAssertEqual(
            decorations, 3,
            "装饰层里 `.allowsHitTesting(false)` 有 \(decorations) 处（应当 3 处：背景填充 / 边线 / 放大镜图标）——"
                + "少了哪一处，可见框里那一片留白就会重新点不动；加了别的装饰请把期望数一起改"
        )
        XCTAssertTrue(field.contains(".background(alignment: .leading) {"))
        XCTAssertTrue(field.contains("TitleBarSearchClickRelay()"))
        XCTAssertTrue(field.contains("TitleBarSearchMetrics.trailingReserve("))
    }
}

/// **对照件**：第 161 轮那份框（`App/Views/TitleBarSearchField.swift` 修前的形状）——
/// 布局一样、接力层也在，**只有装饰层还参与命中测试**。只为证明本判据**能判红**：
/// 它不是产品代码、**不接进任何界面**。
private struct LegacyHitTestableSearchBox: View {
    @State private var query = ""

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .imageScale(.small)
                .foregroundStyle(Theme.text(.tertiary))
            TextField("", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.font(.body))
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Theme.surface(.raised))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Theme.hairline(.light), lineWidth: Metrics.hairline)
        )
        .background(alignment: .leading) {
            TitleBarSearchClickRelay()
                .frame(width: TitleBarSearchLayout.idealWidth)
        }
        .frame(width: TitleBarSearchLayout.idealWidth)
    }
}
