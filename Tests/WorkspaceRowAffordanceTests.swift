import XCTest
@testable import DoyahCore

/// 工作区文件树行的**可发现性判据**（2026-10-02 需求提出者实测反馈）。
///
/// 原话：「**工作区导航栏新实现的悬浮菜单增删改应该增加鼠标悬停 tips，而鼠标悬停到目录上的自带文件名
/// tip 取消，因为没用，且遮住了增删改工具条按钮**」。
///
/// 两件事其实是一件事：**AppKit 一个时刻只给光标下最近的那一层提示** —— 整行挂了 tip，行内那三枚
/// 图标就永远看不到自己的名字（用户只能看到文件名，而那正是他说的「没用」）。所以判据要**成对**：
/// ① 整行不许再挂 `.help`；② 三枚动作必须各自有名字（tip + 无障碍标签）。
final class WorkspaceRowAffordanceTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// ① 行上那条「自带文件名 tip」必须不在（`help(entry.relativePath)` 是它原来的形状）。
    func testRowDoesNotCarryItsOwnTooltip() throws {
        let view = try source("App/Views/WorkspaceExplorerView.swift")
        XCTAssertFalse(
            view.contains(".help(entry.relativePath)"),
            "整行又挂上了自己的 tip —— 它会盖住行内三枚动作的 tip（需求提出者点名过这一点）"
        )
    }

    /// ② 三枚动作各自有名字：`删到废纸篓` / `重命名` / 加号那枚（新建文件 / 新建文件夹）。
    func testRowActionsCarryNames() throws {
        let view = try source("App/Views/WorkspaceExplorerView.swift")
        // 图标按钮（减号 / 铅笔）：`.help` + 无障碍标签都要有 —— 只挂 `accessibilityLabel` 的话，
        // 鼠标用户看不到「这是什么」。
        // 2026-10-13（人类主人令「按钮一律图标」）：减号 / 铅笔改走仓内**唯一出处组件**
        // `ToolbarIconButton(systemName:help:)` —— 名称提示是构造参数，`.help(` 与 `.accessibilityLabel(`
        // **搬进了组件本体**（`App/Views/ToolbarIcon.swift`）。判据跟着形状走（不变式不降）：
        // ① 调用点必须把名称交给 `help:`；② 组件本体必须把它同时接到悬停 tip 与无障碍标签 ——
        // 否则「搬进组件」会变成「没人看得见」，而这正是需求提出者点名过的那件事。
        for key in ["L(.workspaceDeleteToTrash)", "L(.workspaceRename)"] {
            XCTAssertTrue(
                view.contains("help: \(key))"),
                "\(key) 那枚图标没有把名称交给 ToolbarIconButton 的 help: 实参（tip 与无障碍标签都由它来）"
            )
        }
        let component = try source("App/Views/ToolbarIcon.swift")
        XCTAssertTrue(component.contains(".help(help)"), "组件本体没有把 help: 接到 `.help(` —— 纯图标按钮就没有悬停 tip 了")
        XCTAssertTrue(
            component.contains(".accessibilityLabel(Text(help))"),
            "组件本体没有把 help: 接到 `.accessibilityLabel(` —— 纯图标按钮就没有无障碍标签了"
        )
        // 加号是 `Menu`（点开两个子项）不是 `Button` ⇒ tip 必须挂在 `Menu` 本体上。
        XCTAssertTrue(
            view.contains("L(.workspaceNewFile)) / \\(L(.workspaceNewFolder))"),
            "加号那枚没有「新建文件 / 新建文件夹」的 tip"
        )
        XCTAssertTrue(view.contains(".accessibilityLabel(L(.workspaceNewFile))"), "加号那枚没有无障碍标签")
    }

    /// ③ 需要完整路径的地方仍在：右键「在访达中显示」不受影响（去掉悬停 tip 不等于去掉这个能力）。
    func testRevealContextMenuStillPresent() throws {
        let view = try source("App/Views/WorkspaceExplorerView.swift")
        XCTAssertTrue(view.contains("Button(L(.workspaceReveal)) { workspace.reveal(entry) }"),
                      "右键「在访达中显示」不在了 —— 去掉悬停 tip 时别把它一起删了")
    }
}
