import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 标题栏搜索栏「**看得见的框 = 能点的框**」的**点击地图判据**（派活单 `T-20261002-027` 二次复测打回；
/// 承接 `T-20261002-011` / `041` / `051`；开发循环第 163 轮）。
///
/// ## 需求提出者原话（未改写 · 2026-10-02 晚）
///
/// 「这个搜索框是无法用鼠标点击到搜索框，所以也就无法输入，我怀疑是不是这个输入框的 enable =false」
///
/// ## 上一轮为什么"判绿了却没修好"
///
/// 第 162 轮把「点击进不去」判成「SwiftUI 装饰层参与命中测试」，修法是给填充 / 边线 / 图标各加
/// `.allowsHitTesting(false)`，再叠一层 AppKit 接力。那套判据量的是**手工搭的宿主**
/// （`NSHostingView` 直接塞进 `NSToolbarItem`）+ **放大的采样点**，而真包里那颗框跑的是
/// SwiftUI 自己的工具条那条接线 —— 判据的宿主与真包不是同一个东西，绿也说明不了真包：
/// 需求提出者当晚在同一份包上再点一次，仍然是「点不上、打不进」。
///
/// ## 本轮的换法（结构性，不再叠层）
///
/// 整框改成**一个 AppKit 视图**（`TitleBarSearchBoxView`）：输入框、放大镜、清空按钮都是它的
/// 子视图，可见区域内**一处 SwiftUI 内容都没有** ⇒ 命中测试就是普通 AppKit 那条路。
/// 判据随之改成量**产品自己那个视图**、并且从**窗口框架视图**（`NSThemeFrame`）往下量
/// （鼠标事件真正那条路；从 `contentView` 出发看不见标题栏 —— 上一轮就是在这里看偏的）。
///
/// ## 这份判据判什么（五条，四条能判红）
///
/// · ① **地图**：可见框内**内缩 1pt** 的采样点逐点断言命中目标 = 输入框 / 整框 / 清空按钮
///   （`×` 那一段归它自己），任一点落到别的视图或落空 ⇒ 判红；
/// · ② **真的给到键盘**：留白点（左侧放大镜那一段）按下 ⇒ 第一响应者变成那枚输入框（或它拉起的
///   字段编辑器）—— 读窗口的 `firstResponder`，不读模型；
/// · ③ **`×` 三态 + 回车接线**：空词不显示、有词显示、点它清空并回调（"点一下没反应"最容易被放过的一处）；
///   回车那条入口仍须转给外层（`onSubmit` —— 搜索栏不另做一套搜索）；
/// · ④ **红/绿成对**：同一套量法喂「上一轮那版」（SwiftUI 自绘 + 装饰层参与命中测试 + 叠了接力层）
///   必须判红 —— 它不红就说明这套量法量不出这件事，① 的绿也是假绿；
/// · ⑤ **打了字再按回车**：打字不许把 AppKit 的编辑会话收掉（`currentEditor()` 还在），
///   回车（字段编辑器吃 `insertNewline:`）之后那个词必须真的交出去 —— 2026-10-02 晚的真缺陷就是这条：
///   「字能打了，可回车不弹面板」（每敲一个字都写 SwiftUI 状态 ⇒ 工具条那一项重排 ⇒ 编辑会话被收掉）；
/// · ⑥ **源锚点**：整框在 `App/Views/TitleBarSearchField.swift` 里是纯 AppKit
///   （有 `TitleBarSearchBoxView` / 那枚 `acceptsFirstMouse` 的输入框；**没有**接力层、
///   **没有** `.allowsHitTesting(false)` 那套装饰补丁）。
///
/// ## 怎么判（零权限）
///
/// 真窗口 + `NSToolbar` + `NSHostingView`（与 App 自己那条接线同形），合成事件在**进程内**投递
/// ⇒ 不需要辅助功能 / 屏幕录制授权；零权限、不碰使用者偏好、几秒跑完 ⇒ 挂在
/// `./Scripts/verify-ui-interactions.sh`（交互入口）与每轮门禁 `./Scripts/verify-all.sh` 的第 1 项里。
///
/// ## 边界（如实登记，别当已验）
///
/// · 本判据判的是「**命中测试把点击交给谁**」与「留白点按下有没有把键盘交给输入框」；
///   **真鼠标按下去有没有光标、能不能打出字，仍要人在场点一次**（本机这一侧没有输入注入授权）；
/// · 框**最外那一圈**（内缩 1pt 之外）落在哪由 AppKit 与工具条项决定，本判据不判：
///   真窗口探针（`DOYAH_SEARCHBOX_PROBE`）实测**框下沿那 1pt** 归 `NSToolbarItemViewer` ——
///   是框架自己的边界，不是产品能定的；
/// · 非 key 窗口下 AppKit 那条**编辑**路径不会起来（与第 162 轮同一个边界）⇒ ② 只判留白点
///   （那半是产品代码自己调 `makeFirstResponder`）。
final class TitleBarSearchClickProbeTests: XCTestCase {

    // MARK: - 宿主（真窗口 + 工具条 + 产品自己那枚视图）

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

        /// **真实那条路**：鼠标事件先在窗口框架视图上做命中测试。
        ///
        /// 标题栏那一层是框架视图的**兄弟**（与内容视图并列）—— 从 `contentView` 出发**看不见**
        /// 它，所以第 162 轮那套 `hosting.hitTest(...)` 量的是"SwiftUI 内部怎么分"，量不到
        /// "真鼠标会不会走到这一层"。
        @MainActor
        func hit(_ windowPoint: NSPoint) -> NSView? {
            let root = window.contentView?.superview ?? window.contentView
            return root?.hitTest(windowPoint)
        }

        @MainActor
        func click(_ windowPoint: NSPoint) -> NSView? {
            guard let target = hit(windowPoint) else { return nil }
            let event = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: windowPoint,
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

    /// 采样网格（列 × 行）—— 与真窗口探针 `DOYAH_SEARCHBOX_PROBE` 同一个口径。
    private let columns = 7
    private let rows = 3

    /// 可见框内的采样点（**框内坐标**，内缩 1pt：最外那一圈由框架决定，见文件头「边界」）。
    private func samples(in bounds: NSRect) -> [NSPoint] {
        var points: [NSPoint] = []
        let inset: CGFloat = 1
        for row in 0...(rows - 1) {
            for column in 0...(columns - 1) {
                let unit = CGPoint(
                    x: CGFloat(column) / CGFloat(columns - 1),
                    y: CGFloat(row) / CGFloat(rows - 1)
                )
                points.append(
                    NSPoint(
                        x: bounds.minX + inset + unit.x * (bounds.width - 2 * inset - 1),
                        y: bounds.minY + inset + unit.y * (bounds.height - 2 * inset - 1)
                    )
                )
            }
        }
        return points
    }

    /// 窗口的第一响应者是不是那枚输入框（字段编辑器也算 —— 那就是 AppKit 接手编辑后的形态）。
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

    private func name(of view: NSView?) -> String {
        view.map { NSStringFromClass(type(of: $0)) } ?? "nil（落空）"
    }

    // MARK: - ① 地图：可见框里的点，要么归输入框、要么归整框（留白由整框转成聚焦）

    @MainActor
    func testEverySamplePointInTheVisibleBoxLandsOnTheBoxOrItsControls() throws {
        let host = Host(TitleBarSearchBox(width: 360, text: .constant(""), onSubmit: {}))
        let box = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: TitleBarSearchBoxView.self, in: host.hosting).first,
            "工具条里没有装出整框（`TitleBarSearchBoxView`）—— 判据的入口没了"
        )
        let field = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: NSTextField.self, in: box).first,
            "整框里没有输入框"
        )
        let clearButton = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: NSButton.self, in: box).first,
            "整框里没有清空按钮"
        )
        let fieldRect = field.convert(field.bounds, to: box)
        // **非平凡的前提**：可见框真的比输入框大（否则这条判据没有可判的留白）。
        XCTAssertGreaterThan(
            box.bounds.width - fieldRect.width, 8,
            "输入框铺满了整框 ⇒ 本判据没有可判的留白（量法或界面变了，先核对再改这条）"
        )
        XCTAssertGreaterThan(
            box.bounds.height - fieldRect.height, 2,
            "输入框铺满了整框高 ⇒ 上下留白那几档没有内容"
        )

        var readings: [String] = []
        var strayed: [String] = []
        let points = samples(in: box.bounds)
        for point in points {
            let target = host.hit(box.convert(point, to: nil))
            let owner: String
            switch target {
            case let view? where view === field: owner = "输入框"
            case let view? where view === clearButton: owner = "清空按钮"
            case let view? where view === box: owner = "整框"
            default: owner = "别的视图/落空"
            }
            readings.append(String(format: "(%.1f,%.1f)=%@", point.x, point.y, owner))
            if owner == "别的视图/落空" {
                strayed.append(String(format: "(%.1f,%.1f)→%@", point.x, point.y, name(of: target)))
            }
        }
        print("TITLEBAR-CLICK ① 采样 \(points.count) 点 ⇒ \(readings.joined(separator: " · "))")
        XCTAssertTrue(
            strayed.isEmpty,
            "可见框里这些点没交给整框 / 输入框 / 清空按钮：\(strayed.joined(separator: " · "))"
        )
    }

    // MARK: - ② 留白点按下 ⇒ 键盘真的给到输入框

    @MainActor
    func testPaddingClicksHandTheFieldTheKeyboard() throws {
        let host = Host(TitleBarSearchBox(width: 360, text: .constant(""), onSubmit: {}))
        let box = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: TitleBarSearchBoxView.self, in: host.hosting).first
        )
        let field = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: NSTextField.self, in: box).first
        )
        let fieldRect = field.convert(field.bounds, to: box)

        // 留白采样点：左侧放大镜那一段（输入框左缘之外）+ 上下内边距那两条。
        var padding: [(String, NSPoint)] = []
        for x in stride(from: box.bounds.minX + 1, to: max(fieldRect.minX - 1, box.bounds.minX + 2), by: 4) {
            padding.append(("左留白 x=\(Int(x))", NSPoint(x: x, y: box.bounds.midY)))
        }
        for y in [box.bounds.minY + 1, box.bounds.maxY - 1] {
            padding.append(("上下留白 y=\(Int(y))", NSPoint(x: box.bounds.midX, y: y)))
        }
        XCTAssertGreaterThanOrEqual(padding.count, 4, "留白采样点只有 \(padding.count) 个 ⇒ 采样太稀")

        var readings: [String] = []
        var refused: [String] = []
        for (label, point) in padding {
            XCTAssertFalse(fieldRect.contains(point), "\(label) 落在输入框里了 ⇒ 这条判据没量到留白")
            host.window.makeFirstResponder(nil)
            _ = host.click(box.convert(point, to: nil))
            if !isFirstResponderTheField(host.window, field: field) {
                refused.append("\(label)(\(Int(point.x)),\(Int(point.y)))")
            }
            readings.append("\(label)=>\(describeFirstResponder(host.window))")
        }
        print("TITLEBAR-CLICK ② 留白 \(padding.count) 点按下 ⇒ \(readings.joined(separator: " · "))")
        XCTAssertTrue(
            refused.isEmpty,
            "这些留白点按下之后键盘没给到输入框（点了没光标）：\(refused.joined(separator: ", "))"
        )
    }

    // MARK: - ③ `×` 三态：空词不显 / 有词显 / 点它清空并回调（顺带：回车那条接线还在）

    @MainActor
    func testClearButtonShowsWithTextAndClearsIt() throws {
        final class Counter { var submits = 0 }
        let counter = Counter()
        var writes: [String] = []
        let binding = Binding<String>(
            get: { writes.last ?? "" },
            set: { writes.append($0) }
        )
        let host = Host(
            TitleBarSearchBox(width: 360, text: binding, onSubmit: { counter.submits += 1 })
        )
        let box = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: TitleBarSearchBoxView.self, in: host.hosting).first
        )
        let field = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: NSTextField.self, in: box).first
        )
        let clearButton = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: NSButton.self, in: box).first
        )

        XCTAssertTrue(clearButton.isHidden, "空词时 `×` 就显示了")

        box.stringValue = "csv"
        host.hosting.layoutSubtreeIfNeeded()
        XCTAssertFalse(clearButton.isHidden, "有词了 `×` 还不显示")

        clearButton.performClick(nil)
        box.layoutSubtreeIfNeeded()
        XCTAssertEqual(box.stringValue, "", "点了 `×` 却没清掉词")
        XCTAssertEqual(
            UISnapshot.LiveHost<Never>.findViews(ofType: NSTextField.self, in: box).first?.stringValue,
            "",
            "`×` 清的是模型，界面里那枚输入框还留着旧词"
        )
        XCTAssertTrue(clearButton.isHidden, "清空之后 `×` 还留着")

        // 回调那一趟：**直接换掉整框自己的回调**再点一次。
        //
        // 不走绑定那一层量，是因为绑定那层有"值没变就不写"的短路（`if text != newValue`）——
        // 测试里的假绑定与整框里的词天然同值，量出来会是一条假红/假绿。
        var pushed: [String] = []
        box.onTextChange = { pushed.append($0) }
        box.stringValue = "csv"
        clearButton.performClick(nil)
        box.layoutSubtreeIfNeeded()
        XCTAssertEqual(pushed.last, "", "点了 `×` 没把「清空」这件事回调出去")
        XCTAssertEqual(box.stringValue, "", "第二次点 `×` 也没清掉")

        // 回车那条路：动作必须**仍然接在同一处入口**（搜索栏不另做一套搜索）——
        // 这里判的是接线（靶子/动作设上了、回调真被调），不是"回车键本身"（那要真键盘）。
        let action = try XCTUnwrap(field.action, "输入框没有接动作 ⇒ 回车这条入口断了")
        XCTAssertTrue(
            field.target?.responds(to: action) ?? false,
            "输入框的动作靶子不认这个动作 ⇒ 回车这条入口断了"
        )
        _ = field.target?.perform(action)
        XCTAssertEqual(counter.submits, 1, "回车那条入口没有转到外层（`onSubmit` 一次都没被调）")

        print("TITLEBAR-CLICK ③ `×` 三态 + 回车接线 ⇒ 空词隐藏 / 有词显示 / 点击清空并回调 \(writes) / 回车回调 \(counter.submits) 次")
    }

    // MARK: - ④ 红/绿成对：上一轮那版在同一套量法下必须判红

    @MainActor
    func testLegacySwiftUISearchBoxWouldSwallowThePaddingPoints() throws {
        let host = Host(LegacyHitTestableSearchBox())
        let field = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: NSTextField.self, in: host.hosting).first,
            "对照件里没有输入框 ⇒ 对照失效"
        )
        let boxRect = host.hosting.bounds
        let fieldRect = host.hosting.convert(field.bounds, from: field)

        var readings: [String] = []
        var strayed = 0
        let points = samples(in: boxRect)
        for point in points {
            let target = host.hit(host.hosting.convert(point, to: nil))
            let reachable = (target === field) || fieldRect.contains(point)
            readings.append(String(format: "(%.1f,%.1f)=%@", point.x, point.y, reachable ? "可达" : name(of: target)))
            if !reachable { strayed += 1 }
        }
        print("TITLEBAR-CLICK ④ 上一轮那版（SwiftUI 自绘 + 装饰层吃点击）采样 \(points.count) 点 ⇒ 落空 \(strayed) 点 · \(readings.joined(separator: " · "))")
        XCTAssertGreaterThan(
            strayed, 0,
            "对照失效：上一轮那版居然每个采样点都点得到 ⇒ 本判据量不出「点击进不去」这件事"
        )
    }

    // MARK: - ⑤ 打字之后按回车，那个词必须真的交出去

    /// 「**打了字再按回车**」这条路（2026-10-02 晚需求提出者实测：字能打进去了，可回车不弹面板）。
    ///
    /// 真因不是"出口没接"：那一刻直接打 `target/action` 面板起得来，而**回车这条路**起不来 ——
    /// 因为每敲一个字都写 SwiftUI 状态 ⇒ 工具条那一项跟着重排 ⇒ AppKit 的**编辑会话被收掉**
    /// （字段编辑器没了，Return 自然没人接）。
    ///
    /// 这条判据就钉那两件事：① 打字不会把编辑会话收掉（`currentEditor()` 还在）；
    /// ② 打完字按回车（字段编辑器吃 `insertNewline:`）之后，词真的交出去了。
    @MainActor
    func testTypedTextThenReturnStillHandsTheWordOut() throws {
        final class Handoff { var words: [String] = [] }
        let handoff = Handoff()
        let host = Host(
            TitleBarSearchBox(width: 360, text: .constant(""), onSubmit: {})
        )
        let box = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: TitleBarSearchBoxView.self, in: host.hosting).first
        )
        // 回调换掉之后再量（`onSubmit` 拿不到整框的当前词，这里直接把两者接上）。
        box.onSubmit = { handoff.words.append(box.stringValue) }

        let field = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: NSTextField.self, in: box).first
        )
        host.window.makeFirstResponder(field)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let editor = try XCTUnwrap(
            field.currentEditor() as? NSTextView,
            "输入框没能起字段编辑器（编辑会话都没起来，这条判据测不到东西）"
        )

        editor.insertText("csv", replacementRange: NSRange(location: 0, length: 0))
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(box.stringValue, "csv", "字没打进整框")
        XCTAssertNotNil(
            field.currentEditor(),
            "打字把编辑会话收掉了（`currentEditor()` 没了）—— 表现就是「打完字按回车没反应」"
        )

        editor.insertNewline(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(
            handoff.words.last, "csv",
            "打完字按回车，那个词没交出去（实测读到 \(handoff.words)）"
        )
        print("TITLEBAR-CLICK ⑤ 打字后回车 ⇒ 交出去的词 = \(String(describing: handoff.words.last))")
    }

    // MARK: - ⑥ 源锚点：整框是纯 AppKit，不再是叠层
    func testSourceAnchorsKeepTheBoxPureAppKit() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("App/Views/TitleBarSearchField.swift"),
            encoding: .utf8
        )
        // 只判**代码**：注释里会写到上一轮那些补丁（说明"为什么不再需要它们"），
        // 拿整份文件去 contains 会把自己的说明当成缺陷。
        let code = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")

        XCTAssertTrue(
            code.contains("final class TitleBarSearchBoxView: NSView"),
            "整框不再是 AppKit 视图 ⇒ 命中测试又会被 SwiftUI 那层接走（可见框里的留白重新点不动）"
        )
        XCTAssertTrue(
            code.contains("final class TitleBarSearchFieldView: NSTextField"),
            "输入框不再是自己的 `NSTextField` ⇒ 非活动窗口的第一击（`acceptsFirstMouse`）没处放"
        )
        XCTAssertTrue(
            code.contains("override func mouseDown(with event: NSEvent)"),
            "整框不再自己接留白点击 ⇒ 那几处重新变成「点上去没反应」"
        )
        XCTAssertTrue(
            code.contains("func controlTextDidEndEditing("),
            "编辑结束那条落定路没了 ⇒ 「打了字又去点别处」时词会丢"
        )
        XCTAssertFalse(
            code.contains("allowsHitTesting(false)"),
            "又给装饰层打「不参与命中测试」的补丁了 —— 那是上一轮那版的位置；整框已是纯 AppKit，不该再需要它"
        )
        XCTAssertFalse(
            code.contains("TitleBarSearchClickRelay"),
            "接力层又回来了（真窗口里它按类名去找目标，找不到时是**静默什么都不做**，肉眼与判据都看不出来）"
        )
        // **每敲一个字就写 SwiftUI 状态**这一条是"打了字按回车没反应"的真因（真窗口实测）：
        // 文本改动会连带工具条那一项重排，AppKit 的编辑会话当场被收掉。
        XCTAssertFalse(
            code.contains("func controlTextDidChange(_ obj: Notification) {\n        updateClearButton()\n        onTextChange?("),
            "又在「文本变化」里直接写绑定了 ⇒ 每敲一个字都会重排工具条、编辑会话被收掉，回车重新失效"
        )
    }
}

/// **对照件**：上一轮那版的样子（SwiftUI 自绘框 + 装饰层参与命中测试 + 叠了一层 AppKit 接力）。
///
/// 它不是产品代码、**不接进任何界面**：只喂给同一套点击地图量法，用来证明这套量法**量得出**
/// 「点击进不去」—— 否则 ① 的绿是假绿。
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
        .frame(width: 360, height: 24)
    }
}
