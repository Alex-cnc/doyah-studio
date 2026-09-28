import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **侧边栏折叠状态活过一次活动栏切换**（`FR-CONN-15` / 队列 L-59）。
///
/// 人工点验批次 1 第 3 条实测为挂：「折叠状态记不住」。真因不在分组聚合
/// （那是 `Core/ConnectionGrouping.swift` 的纯函数，本就有单测），而在**状态活在哪**：
/// `ConnectionListView` 的 `collapsedGroups` 原本是**视图局部 `@State`**，而这个视图由
/// `MainWindow.sidebarContent` **按活动栏分支创建** ⇒ 切到「工作区 / 笔记」再切回来，
/// 分支被整个重建、状态当场归零（重开应用同理）。修法 = 状态上移 `AppState`。
///
/// ## 这一条为什么是「行为回归」而不是观感快照
/// 它要判的是「**同一段视图重建前后画出来的像素一不一样**」，判据是**逐字节比较**，
/// 所以刻意**不调 `UISnapshot.write`**（不进快照清单，免得搅乱「快照张数 / 组数」这类
/// 派生计数）；产物写到 `.build/ui-snapshot-state/` 只是**备查**，判据不靠人眼。
///
/// 三条纪律与 L-01 同源（见 `UISnapshotKit`）：不进每轮门禁（`verify-all` 会编译本 target，
/// 但用例默认 `XCTSkip`，要 `DOYAH_UI_SNAPSHOT=1`）、产物落 `.build/`、每个结论都带断言。
///
/// **能判什么、判不了什么（如实写清）**：
/// - 能判：折叠状态经 `AppState` 存活，且**折叠到像素上**（两种状态画出来不一样）；
///   把状态改回视图局部 `@State` ⇒ 第 ④ 步的逐字节比较当场判红（红/绿成对已实测，见开发记录）。
/// - 判不了：**重开应用**后是否保持 —— 本条没做磁盘持久化（人工点验报的现象是「切页签回来记不住」），
///   所以这里也不假装判它。
final class UISnapshotSidebarStateTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏渲染要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    // MARK: - 装配

    private typealias Host = (
        state: AppState, workspace: WorkspaceStore, tabs: WorkspaceTabsModel, terminal: TerminalModel
    )

    /// 宿主：连接**显式给**（不读用户真实连接），工作区历史指到临时文件。
    /// 与 `UISnapshotPanelsTests.makeEmptyHost` 同一套装配，差别只在连接和许可证。
    @MainActor
    private func makeHost() -> Host {
        let scratch = UISnapshot.outputDirectory.deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let historyURL = scratch.appendingPathComponent("workspace-history-\(UUID().uuidString).json")

        let state = AppState()
        let workspace = WorkspaceStore.shared
        let tabs = WorkspaceTabsModel(store: WorkspaceHistoryStore(fileURL: historyURL))
        let terminal = TerminalModel()
        return (state, workspace, tabs, terminal)
    }

    private func connection(_ name: String, group: String?) -> ConnectionConfig {
        ConnectionConfig(
            name: name,
            dbType: .postgresql,
            host: "127.0.0.1",
            port: 55433,
            database: "postgres",
            username: "tester",
            sslMode: .disable,
            group: group
        )
    }

    // MARK: - 用例

    @MainActor
    func testGroupCollapseSurvivesActivityBarSwitch() throws {
        let host = makeHost()

        // 三档都可见才切得动 —— Standard 档下工作区 / 数据库不可达，切过去会被落到笔记区，
        // 那样第 ③ 步就「没在测重建」了（断言会当场揭穿）。用完还原许可证。
        let load = try UISnapshot.applyLicense(.ultra, to: host.state)
        defer { UISnapshot.clearLicense(from: host.state) }
        XCTAssertTrue(
            load.entitlements.capabilities.contains(.database),
            "许可证没带数据库能力 —— 侧栏根本不会画连接列表"
        )

        // `selectActivityItem` 会把选择**写进偏好**（真实入口就是这么写的）。
        // 快照纪律是「只覆盖、不落盘、不动用户偏好」⇒ 记下原值，用完原样写回。
        let savedActivity = UserDefaults.standard.string(forKey: ActivityBarItem.storageKey)
        defer {
            if let savedActivity {
                UserDefaults.standard.set(savedActivity, forKey: ActivityBarItem.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: ActivityBarItem.storageKey)
            }
        }

        let group = "生产环境"
        host.state.connections = [
            connection("生产订单库", group: group),
            connection("生产报表库", group: group),
            connection("本地试验库", group: nil)
        ]
        host.state.selectedConnectionID = nil

        let sections = ConnectionGrouping.sections(host.state.connections)
        XCTAssertEqual(sections.count, 2, "应为「一个命名分组 + 未分组」两段")
        guard let named = sections.first(where: { !$0.isUngrouped }) else {
            return XCTFail("没有命名分组 —— 只有命名分组可折叠（未分组是兜底容器，设计上不给折叠）")
        }
        XCTAssertFalse(
            host.state.isConnectionGroupCollapsed(named.id),
            "默认必须全部展开：一进来就收起来会让人以为连接没了"
        )

        // ① 展开态基线
        let expanded = try renderSidebar(host, name: "collapse-01-expanded")

        // ② 折叠 —— **只能经 `AppState`**（集合是 `private(set)`，视图改不了它）
        host.state.setConnectionGroup(named.id, collapsed: true)
        XCTAssertTrue(host.state.isConnectionGroupCollapsed(named.id), "折叠没记上")
        let collapsed = try renderSidebar(host, name: "collapse-02-collapsed")
        XCTAssertNotEqual(
            expanded, collapsed,
            "折叠必须到像素上：同一段视图在「展开 / 折叠」两种状态下画出来必须不一样"
        )

        // ③ 切到工作区再切回数据库 —— 这一步正是人工点验做的动作（`sidebarContent` 会重建那个分支）
        host.state.selectActivityItem(.workspace)
        XCTAssertEqual(
            host.state.selectedActivityItem, .workspace,
            "没切到工作区 —— 那这一步就没在测「重建」，后面两条断言都会变成空话"
        )
        host.state.selectActivityItem(.database)
        XCTAssertEqual(host.state.selectedActivityItem, .database, "没切回数据库区")
        XCTAssertTrue(
            host.state.isConnectionGroupCollapsed(named.id),
            "折叠状态没活过活动栏切换（就是人工点验那次的现象）"
        )

        // ④ 重建后**重新构造**视图树再画一遍：像素必须与折叠那一遍**逐字节相同**。
        //    这是本条的判据本体 —— 状态若回到视图局部 `@State`，这一遍会画成展开态，当场判红。
        let afterSwitch = try renderSidebar(host, name: "collapse-03-after-switch")
        XCTAssertEqual(
            afterSwitch, collapsed,
            "视图树重建后折叠状态丢了：切页签回来画出来的是展开态（人工点验批次 1 第 3 条）"
        )
    }

    // MARK: - 离屏渲染（**不进快照清单**：本条的判据是逐字节比较，不是「图长这样」）

    @MainActor
    private func renderSidebar(_ host: Host, name: String) throws -> Data {
        let size = CGSize(width: 320, height: 560)
        let view = ZStack {
            Theme.surface(.window)
            ConnectionListView(onAdd: {}, onEdit: { _ in })
        }
        .frame(width: size.width, height: size.height)
        .snapshotEnvironment(
            state: host.state,
            workspace: host.workspace,
            tabs: host.tabs,
            terminal: host.terminal
        )

        // 侧栏是 AppKit 自绘容器（`List` + `.listStyle(.sidebar)`）：没有真实窗口就画不出内容
        // （L-11 第 10 轮的实测），所以这里给一个**不上屏**的 borderless 窗口。
        let appearance = NSAppearance(named: .aqua)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = appearance
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * scale).rounded()),
            pixelsHigh: Int((size.height * scale).rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw UISnapshot.SnapshotError.renderFailed("位图分配失败")
        }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw UISnapshot.SnapshotError.encodeFailed(name)
        }

        // 空跑防护：一张什么都没有的图也编码得出来，所以给一个**下限**。
        XCTAssertGreaterThan(
            data.count, 4000,
            "\(name) 只有 \(data.count) 字节 —— 像是渲染成了空白（侧栏没画出来）"
        )

        let directory = UISnapshot.outputDirectory.deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-state", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
        return data
    }
}
