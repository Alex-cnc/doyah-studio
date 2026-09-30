import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **工作区 chrome 行（页签条）的高度不变量** —— 队列 `L-144`（内测清单 **乙5**）。
///
/// ## 由头（需求提出者 2026-09-30 内测原话）
///
/// 「**新建 2 浏览器页签后，选择空白浏览器页签，整个标题栏撑得很高，整个布局全乱了**」。
/// 第二轮实测**未复现**（`L-149` 把浏览器页签从数据库侧搬到工作区后复现路径已变，
/// 那一轮**没有针对它的修复**），需求提出者第二轮判「**过**」⇒ 本条按
/// 「**用户判过 + 判据留网**」收口：缺陷本身不再追，但**「这一行的高度由什么决定」变成可断言**。
///
/// ## 为什么不靠眼睛、也不靠整页快照
///
/// 观感类条目一向走「快照 + 读图」，但那是**人读图**；本条要的是一条**每轮门禁都跑**的判据。
/// 离屏宿主 `NSHostingController.sizeThatFits(in:)` 给宽度约束、高度不限 ⇒ 拿到的是这一行
/// **在真实窗口宽度下会长多高**：不需要窗口、不需要屏幕录制、不需要人在场（快照基建的同一思路，
/// 但**不渲染位图**，所以不必挂 `DOYAH_UI_SNAPSHOT`，能在 `verify-core.sh` 里天天跑）。
///
/// ## 不变量（唯一出处写在 `App/Views/WorkspaceTabStrip.swift` 的文档注释里）
///
/// 这一行的高度**只由内边距与字高决定**：
///
/// 1. **不随内容变** —— 空白页签（默认标题）与有地址、有标题的页签**同高**；
/// 2. **不随数量变** —— 1 个与 4 个页签同高（页签多了是横向滚动，不是纵向变高）；
/// 3. **不随窗口宽度变** —— 420 / 640 / 900 / 1200 / 1440 五个宽度同高。
///
/// ## 判据必须能判红（第二批用例就是这件事）
///
/// 「四个配置同高」如果只是因为**这套量法根本量不动**，那就是假绿。所以同一族里带**两个对照**：
/// 往同一行里塞①会随宽度换行的长文案 ⇒ 窄窗口必须**明显更高**；②一个高理想高度的空态样玩具
/// ⇒ 必须**比基线高出一截**。两条对照都成立，「同高」才作数。
///
/// ## 边界（如实登记，别当已验）
///
/// · 量的是**应用内 chrome 行**（工作区页签条）——**不是** AppKit 窗口标题栏
///   （`NSWindow` 的 titlebar / toolbar）那一层；后者要真窗口，本轮**未机器化**；
/// · 不验观感（对齐 / 间距好不好看），也不验页签**点起来对不对**（那是既有点验项）；
/// · 不碰任何用户数据：`workspaceBrowser.browserPages` 直接在内存里摆
///   （队列 `L-149` 剩余① 之后浏览器状态归 `WorkspaceBrowserModel`，所以片场里要单独注入它），
///   页签历史指向 `.build/` 下的临时文件。
final class WorkspaceChromeHeightProbeTests: XCTestCase {

    /// 取样宽度：从「非全屏的窄窗口」到「大屏全屏」（内测报的是**非全屏**下出事）。
    private let widths: [CGFloat] = [420, 640, 900, 1200, 1440]

    /// 这一行允许的最大高度。**由内边距与字高决定** ⇒ 它就该是「一行小字 + 上下内边距」的量级；
    /// 取 48pt 是**留足余量**的天花板（真到了「撑得很高」那一类病，量出来是 90 / 130 这种数）。
    private let maximumChromeHeight: CGFloat = 48

    // MARK: - 装配（全部在内存 / 临时目录里，不碰用户数据）

    @MainActor
    private func makeHost() -> (state: AppState, tabs: WorkspaceTabsModel) {
        let scratch = UISnapshot.outputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let historyURL = scratch.appendingPathComponent("workspace-strip-probe-\(UUID().uuidString).json")

        let state = AppState()
        // **只在内存里摆页签**（`openBrowserTab()` 会落盘到真实数据目录 —— 探针不写用户数据）。
        state.workspaceBrowser.browserPages = []
        state.workspaceBrowser.selectedBrowserID = nil
        let tabs = WorkspaceTabsModel(store: WorkspaceHistoryStore(fileURL: historyURL))
        return (state, tabs)
    }

    /// 量一行的高度：宽度给约束、高度不限。
    @MainActor
    private func height(of strip: WorkspaceTabStrip, in host: (state: AppState, tabs: WorkspaceTabsModel), width: CGFloat) -> CGFloat {
        let controller = NSHostingController(
            rootView: strip
                .environmentObject(host.state)
                .environmentObject(host.state.workspaceBrowser)
                .environmentObject(host.tabs)
        )
        let size = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        return size.height
    }

    /// 摆出某种页签组合，返回「每一档宽度」量到的高度。
    @MainActor
    private func measure(
        _ title: String,
        configure: (AppState, WorkspaceTabsModel) -> Void
    ) -> [CGFloat] {
        var heights: [CGFloat] = []
        for width in widths {
            let host = makeHost()
            configure(host.state, host.tabs)
            heights.append(height(of: WorkspaceTabStrip(), in: host, width: width))
        }
        print("CHROME \(title) -> \(heights)")
        return heights
    }

    // MARK: - 第一批：不变量（内容 / 数量 / 宽度都不许改变这一行的高度）

    @MainActor
    func testChromeRowHeightDoesNotFollowContentOrCountOrWidth() throws {
        // ① 基线：只有 Home（一个页签、没有浏览器）
        let baseline = measure("基线·仅 Home") { state, _ in
            state.workspaceBrowser.browserPages = []
            state.workspaceBrowser.selectedBrowserID = nil
        }

        // ② 内测原场景：2 个**空白**浏览器页签，选中空白那个
        let twoBlank = measure("2 个空白浏览器页签（选中空白）") { state, _ in
            let first = BrowserPage()
            let second = BrowserPage()
            state.workspaceBrowser.browserPages = [first, second]
            state.workspaceBrowser.selectedBrowserID = second.id
        }

        // ③ 对照 ②：2 个页签里有地址、有标题的那一个被选中
        let loaded = measure("2 个页签·选中「有地址」那个") { state, _ in
            let blank = BrowserPage()
            let page = BrowserPage(
                url: URL(string: "https://example.com/a/very/long/path/that/keeps/going")!,
                title: "Example Domain"
            )
            state.workspaceBrowser.browserPages = [blank, page]
            state.workspaceBrowser.selectedBrowserID = page.id
        }

        // ④ 数量：2 浏览器 + 2 文件页签（临时文件，真读真开）
        let mixed = measure("2 浏览器 + 2 文件页签") { state, tabs in
            let first = BrowserPage()
            let second = BrowserPage(url: URL(string: "https://example.org/")!, title: "Example")
            state.workspaceBrowser.browserPages = [first, second]
            state.workspaceBrowser.selectedBrowserID = first.id

            let scratch = UISnapshot.outputDirectory.deletingLastPathComponent()
                .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
            try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            for name in ["probe-a.txt", "probe-b.swift"] {
                let url = scratch.appendingPathComponent(name)
                try? "// 工作区页签条探针的临时文件\n".write(to: url, atomically: true, encoding: .utf8)
                tabs.openFile(at: url)
            }
            XCTAssertGreaterThan(tabs.tabs.count, 1, "文件页签没开起来 —— ④ 这一档就没验到「数量」")
        }

        for (title, heights) in [
            ("基线·仅 Home", baseline),
            ("2 个空白浏览器页签（选中空白）", twoBlank),
            ("2 个页签·选中「有地址」那个", loaded),
            ("2 浏览器 + 2 文件页签", mixed),
        ] {
            // 宽度不变
            XCTAssertEqual(
                Set(heights.map { ($0 * 100).rounded() }).count, 1,
                "「\(title)」的高度跟着窗口宽度变了：\(heights)（宽度取样 \(widths)）—— " +
                    "这一行只许由内边距与字高决定，见 `WorkspaceTabStrip` 的不变量"
            )
            // 是一行 chrome，不是一整块内容区
            if let value = heights.first {
                XCTAssertGreaterThan(value, 0, "「\(title)」量出来是 0 —— 这一行根本没画出来")
                XCTAssertLessThanOrEqual(
                    value, maximumChromeHeight,
                    "「\(title)」的高度 \(value) 超过 chrome 行的天花板 \(maximumChromeHeight)pt —— " +
                        "「标题栏撑得很高」这一类病又回来了"
                )
            }
        }

        // 四档之间同高：内容（空白 / 有地址）、数量（1 / 4 个页签）都不影响这一行。
        let values = [baseline, twoBlank, loaded, mixed].map { $0[0] }
        XCTAssertEqual(
            Set(values.map { ($0 * 100).rounded() }).count, 1,
            "四个配置量出来的高度不一样：基线 \(values[0]) / 空白 \(values[1]) / 有地址 \(values[2]) / 混合 \(values[3]) —— " +
                "页签的**内容与数量**不许改变这一行的高度"
        )

        print("CHROME 四档同高 = \(values[0])pt")
    }

    // MARK: - 第二批：对照（证明这套量法真的量得动 —— 否则第一批是假绿）

    @MainActor
    func testMeasurementRespondsToContentDrivenHeight() throws {
        let baseline = measure("对照·基线（同一行）") { state, _ in
            state.workspaceBrowser.browserPages = [BrowserPage()]
            state.workspaceBrowser.selectedBrowserID = nil
        }

        // 玩具①：会随宽度换行的长文案（「往 chrome 行里塞内容」这一类病的原型）
        var wrapping: [CGFloat] = []
        // 玩具②：一个高理想高度的空态样摆放（与「空白页签显示空态」同形）
        var tall: [CGFloat] = []
        for width in widths {
            let host = makeHost()
            host.state.workspaceBrowser.browserPages = [BrowserPage()]
            host.state.workspaceBrowser.selectedBrowserID = nil

            let wrapController = NSHostingController(
                rootView: StripWithToy(wrappingCopy: true)
                    .environmentObject(host.state)
                    .environmentObject(host.state.workspaceBrowser)
                    .environmentObject(host.tabs)
            )
            wrapping.append(
                wrapController.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
            )

            let tallController = NSHostingController(
                rootView: StripWithToy(wrappingCopy: false)
                    .environmentObject(host.state)
                    .environmentObject(host.state.workspaceBrowser)
                    .environmentObject(host.tabs)
            )
            tall.append(
                tallController.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
            )
        }
        print("CHROME 对照·会换行的长文案 -> \(wrapping)")
        print("CHROME 对照·空态样高块 -> \(tall)")

        // ① 宽度敏感：窄窗口下必须**明显**更高（换行了）——证明量法真的跟着宽度走
        XCTAssertGreaterThan(
            wrapping[0], wrapping[widths.count - 1] + 8,
            "会换行的长文案在窄窗口里没把这一行顶高（420pt → \(wrapping[0])，1440pt → \(wrapping[widths.count - 1])）" +
                "⇒ 这套量法量不出「内容驱动的高度」，第一批的同高断言不算数"
        )
        // ② 内容敏感：高理想高度的东西必须把这一行顶高一截
        XCTAssertGreaterThan(
            tall[2], baseline[2] + 40,
            "高理想高度的空态块没有把这一行顶高（基线 \(baseline[2]) / 空态样 \(tall[2])）" +
                "⇒ 同上：判据量不动高度"
        )
    }
}

/// 对照组：**同一行**里塞进一个「会随宽度换行」或「高理想高度」的玩具。
///
/// 它不进产品代码、也不被任何产品路径引用 —— 它存在的唯一目的是让
/// `testMeasurementRespondsToContentDrivenHeight` 能证明上面的量法**真的量得动**。
private struct StripWithToy: View {
    let wrappingCopy: Bool

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceTabStrip()
            if wrappingCopy {
                Text(String(repeating: "很长的说明文字", count: 12))
                    .font(Theme.font(.caption))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: Spacing.xs) {
                    Image(systemName: "globe").imageScale(.large)
                    Text("空态标题").font(Theme.font(.body))
                    Text("空态说明").font(Theme.font(.caption))
                    Button("一个按钮") {}
                }
                .padding(.vertical, Spacing.l)
            }
        }
    }
}
