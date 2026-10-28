import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **页签条的「溢出」面** —— `FR-STD-WS-UI-010` 的 ② / ③ 两条（需求书原文：页签多了**横向滚动**，
/// 不换行、不把标题栏撑高；溢出时横向滚动条出现）。
///
/// ## 与 `WorkspaceChromeHeightProbeTests` 的分工
///
/// 那一条量的是**高度**（空白页签同高 / 数量与窗口宽度都不改变高度），走
/// `NSHostingController.sizeThatFits(in:)`；本条量的是**宽度与滚动**，必须走**真布局**：
/// `sizeThatFits` 只说「这一行要多大」，说不出「页签区多宽、内容有没有被压扁、滚动条在不在」。
///
/// 量法（本轮实测出来的唯一可行路径，别改成 `sizeThatFits`）：把 `WorkspaceTabStrip` 挂进一个
/// **离屏 `NSWindow`**，给窗口一个确定宽度 → `layoutIfNeeded()` → 跑一小段 runloop（SwiftUI 的
/// 布局是下一跳落的，不跑 runloop 拿到的全是 0×0 的退化帧，实测过两次）→ 在 AppKit 视图树里找
/// 那个横向 `NSScrollView`，读三样东西：
///
/// · `contentView.bounds.width`（**页签区宽度** = clip 宽，用户看得见的那一截）；
/// · `documentView.frame.width`（**页签内容宽度** = 所有页签的理想宽度之和）；
/// · `hasHorizontalScroller`（滚动条**开着**没有）。
///
/// 「溢出」= `documentView 宽 > clip 宽`。横向 `ScrollView` 天然不压缩子视图（内容保持理想宽度）
/// ⇒ 溢出时**内容宽度与窗口宽度无关**，这一条就是「不压缩」的判据。
///
/// ## 判据必须能判红
///
/// 最后一条 `testDetectorRespondsToTheThreeWaysItCanBreak` 用三个玩具证明这套量法**不是恒真**：
/// 没有滚动容器 ⇒ 找不到（不是「找到了一个假的」）；内容被拉伸到视口宽 ⇒ `doc == clip`（不报溢出）；
/// `showsIndicators: false` ⇒ `hasHorizontalScroller == false`（滚动条那一条真的在读数）。
///
/// ## 边界（如实登记）
///
/// · 量的是**版面几何**，不是观感（好不好看、间距舒不舒服仍然只有人判）；
/// · 不验「滚动条**画出来**是什么样」（那是 AppKit 的 overlay scroller，与系统偏好有关）；
/// · 不验鼠标滚动能不能滚（`NSScrollView` 的既有行为，不是本片引入的面）。
final class WorkspaceTabStripOverflowProbeTests: XCTestCase {

    /// 取样窗口宽度：非全屏窄窗口 → 大屏全屏。
    private let widths: [CGFloat] = [420, 640, 900, 1440]

    /// 窗口加宽的跨度（T1 用它断言「页签区吸收全部加宽」）。
    private var widthSpan: CGFloat { (widths.last ?? 1440) - (widths.first ?? 420) }

    /// 一行 chrome 的天花板（与 `WorkspaceChromeHeightProbeTests` 同口径，留足余量）。
    private let maximumChromeHeight: CGFloat = 48

    /// **行宽减去页签区宽度之后，右侧最多能占多少**（选中一个文件页签时的实测值 274pt + 2pt 余量）。
    ///
    /// 这个数就是「语言标签 + 编辑菜单 + 保存 / 对话 / 打开文件三枚按钮」那几件固定件的宽度；
    /// 页签区是这一行**唯一**的伸缩者 ⇒ 行宽 − 页签区宽度必须正好等于它。
    /// 往里再加一件固定件（新按钮）时，**把这里一起改**：那条断言量的就是这件事。
    private let maximumTrailingOccupancy: CGFloat = 276

    /// 离屏窗口的持有者：**只持有、不关闭**（见 `measure` 里的注释）。
    @MainActor private static var retainedWindows: [NSWindow] = []

    // MARK: - 量法

    /// 一次量的三样读数。
    struct StripGeometry {
        var stripHeight: CGFloat      // sizeThatFits 的高度（这一行要多高）
        var clipWidth: CGFloat        // 页签区宽度（用户看得见的那一截）
        var contentWidth: CGFloat     // 页签内容理想宽度之和
        var contentHeight: CGFloat    // 内容高度（一行 = 单行高；换行会翻倍）
        var hasHorizontalScroller: Bool
        var scrollViewCount: Int

        var isOverflowing: Bool { contentWidth > clipWidth + 0.5 }
    }

    /// 在 AppKit 视图树里找滚动容器（深度优先，取第一个）。
    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews {
            if let found = firstScrollView(in: sub) { return found }
        }
        return nil
    }

    private func scrollViewCount(in view: NSView) -> Int {
        var count = (view is NSScrollView) ? 1 : 0
        for sub in view.subviews { count += scrollViewCount(in: sub) }
        return count
    }

    @MainActor
    private func scratchDirectory() -> URL {
        let scratch = UISnapshot.outputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        return scratch
    }

    /// 摆一棵**确定的**页签树：`files` 个文件页签（+ Home）。
    ///
    /// 文件名**等长**（`overflow-tab-NN.txt`）⇒ 每个页签的宽度相同 ⇒ 内容宽度随数量线性长，
    /// 断言才能写成关系式而不是某个魔法数。
    @MainActor
    private func makeHost(files: Int) -> (state: AppState, tabs: WorkspaceTabsModel) {
        let scratch = scratchDirectory()
        let historyURL = scratch.appendingPathComponent("strip-overflow-\(UUID().uuidString).json")
        let state = AppState()
        // 只在内存里摆浏览器页签（`openBrowserTab()` 会落盘到真实数据目录 —— 探针不写用户数据）。
        state.workspaceBrowser.browserPages = []
        state.workspaceBrowser.selectedBrowserID = nil
        let tabs = WorkspaceTabsModel(store: WorkspaceHistoryStore(fileURL: historyURL))
        guard files > 0 else { return (state, tabs) }
        let root = scratch.appendingPathComponent("strip-overflow-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<files {
            let url = root.appendingPathComponent(String(format: "overflow-tab-%02d.txt", index))
            try? "// \(index)\n".write(to: url, atomically: true, encoding: .utf8)
            tabs.openFile(at: url)
        }
        return (state, tabs)
    }

    /// 真布局量一次（窗口宽度确定）。
    @MainActor
    private func measure(files: Int, windowWidth: CGFloat) -> StripGeometry {
        let host = makeHost(files: files)
        let strip = WorkspaceTabStrip()
            .environmentObject(host.state)
            .environmentObject(host.state.workspaceBrowser)
            .environmentObject(host.tabs)
        let controller = NSHostingController(rootView: strip)
        let fitted = controller.sizeThatFits(
            in: CGSize(width: windowWidth, height: CGFloat.greatestFiniteMagnitude)
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let view = controller.view
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: windowWidth, height: 200)
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        // SwiftUI 的布局**下一跳才落**：不跑这一段 runloop，读到的滚动容器是 0×0 的退化帧
        // （实测：documentView 0.0×0.0、clip 136×22 —— 那个 134 不是真宽度，是没布局完）。
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()

        let scroll = firstScrollView(in: view)
        let count = scrollViewCount(in: view)
        let geometry: StripGeometry
        if let scroll, let document = scroll.documentView {
            geometry = StripGeometry(
                stripHeight: fitted.height,
                clipWidth: scroll.contentView.bounds.width,
                contentWidth: document.frame.width,
                contentHeight: document.frame.height,
                hasHorizontalScroller: scroll.hasHorizontalScroller,
                scrollViewCount: count
            )
        } else {
            geometry = StripGeometry(
                stripHeight: fitted.height,
                clipWidth: -1, contentWidth: -1, contentHeight: -1,
                hasHorizontalScroller: false, scrollViewCount: count
            )
        }
        // **不要 `close()`**：离屏窗口在测试进程里一关，SwiftUI 的宿主视图会在 dealloc 时
        // 撞上已经拆掉的 AppKit 树（实测 SIGSEGV，signal 11）；这些窗口留着不关即可，
        // 一个测试进程内的窗口数量是几十个的量级。
        Self.retainedWindows.append(window)

        print(
            "STRIP files=\(files) tabs=\(host.tabs.tabs.count) w=\(Int(windowWidth)) "
                + "h=\(geometry.stripHeight) clip=\(geometry.clipWidth) "
                + "doc=\(geometry.contentWidth)x\(geometry.contentHeight) hasH=\(geometry.hasHorizontalScroller)"
        )
        return geometry
    }

    // MARK: - T1 页签区吸收全部窗口加宽，且不随页签数量变

    /// ② 的半边：页签区**是这一行唯一的伸缩者**。
    ///
    /// 两条断言：① 窗口加宽多少，页签区就加宽多少（多出来的宽度一点不漏给别人 —— 中间若再有
    /// 一个可伸缩的 `Spacer`，滚动容器就吃不满）；② 同一个窗口宽度下 2 / 5 / 11 个页签的页签区
    /// **同宽**（页签区宽度由可用宽度决定，不由页签数量决定）。
    @MainActor
    func testTabAreaAbsorbsWindowGrowthRegardlessOfTabCount() throws {
        let narrow = widths[0]
        let wide = widths[widths.count - 1]
        let span = wide - narrow

        var narrowWidths: [CGFloat] = []
        for files in [1, 4, 10] {
            let atNarrow = measure(files: files, windowWidth: narrow)
            let atWide = measure(files: files, windowWidth: wide)
            XCTAssertGreaterThan(atNarrow.clipWidth, 0, "找不到页签区（files=\(files)）—— 量法失效")

            // ① 加宽多少吸收多少（±1pt，取整误差）
            XCTAssertEqual(
                (atWide.clipWidth - atNarrow.clipWidth), span, accuracy: 1,
                "窗口加宽 \(span)pt，页签区只加宽了 \(atWide.clipWidth - atNarrow.clipWidth)pt" +
                    "（files=\(files)）—— 中间还有别的可伸缩者在抢宽度"
            )
            // ② 行宽 − 页签区宽度 = 右侧固定件（不多出第三个消费者）
            XCTAssertLessThanOrEqual(
                narrow - atNarrow.clipWidth, maximumTrailingOccupancy,
                "\(Int(narrow))pt 窗口里页签区只拿到 \(atNarrow.clipWidth)pt，行宽被占了 " +
                    "\(narrow - atNarrow.clipWidth)pt（上限 \(maximumTrailingOccupancy)）—— " +
                    "中间还插着一个可伸缩的 `Spacer`，那截空白本该是页签区"
            )
            narrowWidths.append(atNarrow.clipWidth)
        }

        // ② 数量不改变页签区宽度
        XCTAssertEqual(
            Set(narrowWidths.map { ($0 * 10).rounded() }).count, 1,
            "同一窗口宽度下 2 / 5 / 11 个页签的页签区宽度不一样：\(narrowWidths) —— " +
                "页签区宽度只许由可用宽度决定（见 `WorkspaceTabStrip` 的注释）"
        )
    }

    // MARK: - T2 溢出时不压缩内容

    /// 横向 `ScrollView` 的义：内容保持**理想宽度**，靠滚动看后面的。
    //
    /// 判据 = 内容宽度**与窗口宽度无关**（420 与 1440 同宽，±2%），且随页签数量线性增长。
    /// 内容被压扁的表现正好相反：窗口一窄，`documentView` 就跟着缩到 clip 那么宽。
    @MainActor
    func testOverflowKeepsTabContentAtIdealWidth() throws {
        for files in [1, 4, 10] {
            let narrow = measure(files: files, windowWidth: widths[0])
            let wide = measure(files: files, windowWidth: widths[widths.count - 1])
            XCTAssertGreaterThan(narrow.contentWidth, 0, "读不到页签内容宽度（files=\(files)）")
            let drift = abs(narrow.contentWidth - wide.contentWidth) / max(narrow.contentWidth, 1)
            XCTAssertLessThan(
                drift, 0.02,
                "页签内容宽度跟着窗口宽度变了（420pt 窗口 \(narrow.contentWidth) / 1440pt 窗口 " +
                    "\(wide.contentWidth)，差 \(Int(drift * 100))%）—— 内容被压扁了，不是滚动"
            )
        }

        // 内容宽度随数量长（等长文件名 ⇒ 近似线性）
        let two = measure(files: 1, windowWidth: widths[0]).contentWidth
        let five = measure(files: 4, windowWidth: widths[0]).contentWidth
        let eleven = measure(files: 10, windowWidth: widths[0]).contentWidth
        XCTAssertGreaterThan(five, two, "2 → 5 个页签内容宽度没变（\(two) → \(five)）")
        XCTAssertGreaterThan(eleven, five, "5 → 11 个页签内容宽度没变（\(five) → \(eleven)）")
        print("STRIP 内容宽度 2/5/11 个页签 = \(two) / \(five) / \(eleven)")
    }

    // MARK: - T3 溢出时横向滚动条可用

    /// ③ 的正向面：溢出（内容比页签区宽）时必须**能横向滚**——滚动条开着。
    @MainActor
    func testOverflowExposesHorizontalScroller() throws {
        for windowWidth in widths {
            let geometry = measure(files: 10, windowWidth: windowWidth)
            XCTAssertTrue(
                geometry.isOverflowing,
                "11 个页签在 \(Int(windowWidth))pt 宽的窗口里没有溢出（内容 \(geometry.contentWidth) / " +
                    "页签区 \(geometry.clipWidth)）—— 这一档就验不到「溢出」"
            )
            XCTAssertTrue(
                geometry.hasHorizontalScroller,
                "页签溢出时横向滚动条没有开（`ScrollView(showsIndicators:)` 被关掉了）—— 需求 ③ 要求它出现"
            )
        }
    }

    // MARK: - T4 未溢出时如实不报溢出

    /// ③ 的反向面：页签装得下的时候不许有溢出（否则 T3 的「溢出」是恒真断言）。
    @MainActor
    func testSingleTabDoesNotOverflow() throws {
        for windowWidth in widths {
            let geometry = measure(files: 0, windowWidth: windowWidth)
            XCTAssertGreaterThan(geometry.clipWidth, 0, "只有 Home 时读不到页签区宽度")
            XCTAssertFalse(
                geometry.isOverflowing,
                "只有 Home 一个页签也报溢出（内容 \(geometry.contentWidth) / 页签区 \(geometry.clipWidth)，" +
                    "窗口 \(Int(windowWidth))pt）—— 量法或版面有一处不对"
            )
        }
    }

    // MARK: - T5 高度不随数量与窗口宽度变（需求 ② 的「不撑高」那半边）

    /// 需求 ② 原文：「页签从 2 个加到 10 个，页签条高度不变」。既有探针最多量到 4 个，
    /// 本档把 **11 个**补上，并跨四个窗口宽度。
    @MainActor
    func testChromeHeightSurvivesElevenTabs() throws {
        var heights: [CGFloat] = []
        for files in [0, 1, 4, 10] {
            for windowWidth in widths {
                let geometry = measure(files: files, windowWidth: windowWidth)
                heights.append(geometry.stripHeight)
                XCTAssertLessThanOrEqual(
                    geometry.stripHeight, maximumChromeHeight,
                    "files=\(files) 窗口 \(Int(windowWidth))pt：页签条高 \(geometry.stripHeight)pt，" +
                        "超过 chrome 行天花板 \(maximumChromeHeight)pt —— 「标题栏被撑高」又回来了"
                )
            }
        }
        XCTAssertEqual(
            Set(heights.map { ($0 * 100).rounded() }).count, 1,
            "页签条高度随数量或窗口宽度变了：\(heights)（files=0/1/4/10 × 窗口 \(widths)）"
        )
        print("STRIP 四档数量 × 四档宽度同高 = \(heights.first ?? 0)pt")
    }

    // MARK: - T6 溢出时不换行

    /// 需求 ② 的「不换行」：内容高度必须还是**一行**。
    ///
    /// 换行的表现是 `documentView` 高度翻倍（两行），而这一行的高度仍可能被外层夹住 ——
    /// 所以「高度不变」（T5）**不能**代替这一条，得直接量内容高度。
    @MainActor
    func testOverflowDoesNotWrap() throws {
        let oneTab = measure(files: 0, windowWidth: widths[0])
        let elevenTabs = measure(files: 10, windowWidth: widths[0])
        XCTAssertGreaterThan(oneTab.contentHeight, 0, "读不到内容高度")
        XCTAssertEqual(
            elevenTabs.contentHeight, oneTab.contentHeight, accuracy: 1,
            "11 个页签的内容高度 \(elevenTabs.contentHeight) 与 1 个页签的 \(oneTab.contentHeight) 不同 —— " +
                "内容换行了（页签多了该横向滚动）"
        )
        XCTAssertEqual(
            elevenTabs.contentHeight, elevenTabs.contentHeight.rounded(), accuracy: 8,
            "内容高度 \(elevenTabs.contentHeight) 不像一行字的高度（量法存疑）"
        )
    }

    // MARK: - T7 判据自证：这套量法能判出三种坏法

    /// 三个玩具，各对应一种「机制被拆掉」的形状。**它们不进产品代码**，只证明上面的量法不是恒真。
    @MainActor
    func testDetectorRespondsToTheThreeWaysItCanBreak() throws {
        let host = makeHost(files: 0)

        // ① 没有滚动容器 ⇒ 找不到（而不是「找到一个假的」）
        let plain = hostView(
            AnyView(HStack { Text("没有滚动容器的一行").font(Theme.font(.caption)) }),
            host: host,
            width: 420
        )
        XCTAssertEqual(
            scrollViewCount(in: plain), 0,
            "一个纯 `HStack` 也被数出了滚动容器 —— 「找不到滚动容器」这条判断不可信"
        )

        // ② 内容被拉伸到视口宽 ⇒ 不报溢出（`doc == clip`，不是「永远 doc > clip」）
        let stretched = hostView(
            AnyView(
                ScrollView(.horizontal, showsIndicators: true) {
                    Text("被拉伸的内容").font(Theme.font(.caption)).frame(maxWidth: .infinity)
                }
            ),
            host: host,
            width: 420
        )
        let stretchedScroll = try XCTUnwrap(firstScrollView(in: stretched), "玩具里没有滚动容器")
        let stretchedDoc = try XCTUnwrap(stretchedScroll.documentView, "玩具里没有内容视图")
        XCTAssertLessThanOrEqual(
            stretchedDoc.frame.width, stretchedScroll.contentView.bounds.width + 0.5,
            "内容被拉伸到视口宽，却被判成溢出（内容 \(stretchedDoc.frame.width) / " +
                "视口 \(stretchedScroll.contentView.bounds.width)）—— 「溢出」这条读的是别的东西"
        )

        // ③ 关掉指示条 ⇒ `hasHorizontalScroller == false`（T3 的那一条真的在读数）
        let hiddenBar = hostView(
            AnyView(
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(0..<40, id: \.self) { Text("宽内容 \($0)").font(Theme.font(.caption)) } }
                }
            ),
            host: host,
            width: 420
        )
        let hiddenScroll = try XCTUnwrap(firstScrollView(in: hiddenBar), "玩具里没有滚动容器")
        XCTAssertFalse(
            hiddenScroll.hasHorizontalScroller,
            "`showsIndicators: false` 时仍读出「滚动条开着」—— T3 那一条量不到东西"
        )
    }

    /// 把任意视图挂进离屏窗口走一次真布局（与 `measure` 同一套，供玩具用）。
    @MainActor
    private func hostView(_ root: AnyView, host: (state: AppState, tabs: WorkspaceTabsModel), width: CGFloat) -> NSView {
        let controller = NSHostingController(
            rootView: root
                .environmentObject(host.state)
                .environmentObject(host.state.workspaceBrowser)
                .environmentObject(host.tabs)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let view = controller.view
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: width, height: 200)
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        Self.retainedWindows.append(window)
        return view
    }
}
