import XCTest
@testable import DoyahCore

/// 工作区快照的**页签种类**判据（2026-10-22 人类主人实测：页签条上两个「首页」）。
///
/// 事故形状：`WorkspaceSessionSnapshot.Tab` 只存 `path` / `title`，恢复时按
/// 「`path == nil` ⇒ Home」**推**种类。对话页签同样没有 path ⇒ 存回再读出来就成了
/// **第二个 Home**；页签条渲染时 Home 的标题一律取语言表 ⇒ 两个「首页」。
///
/// 这些用例守的是：**种类存进去、原样回来**，且历史快照（无 kind 栏）不许把页签洗掉。
final class WorkspaceSessionTabKindTests: XCTestCase {

    private func snapshotJSON(_ tabs: String, selectedTabIndex: Int = 0) -> Data {
        Data("""
        {"version": 1, "workspacePath": "/tmp", "selectedTabIndex": \(selectedTabIndex),
         "tabs": [\(tabs)]}
        """.utf8)
    }

    /// 正例：Home + 对话页签存盘再读回，种类不许互换（本次事故的主判据）。
    func testKindSurvivesRoundTrip() throws {
        let tabs: [WorkspaceTab] = [
            .home(title: "首页"),
            .agentChat(title: "对话")
        ]
        let stored = tabs.map { WorkspaceSessionSnapshot.Tab($0) }
        let snapshot = WorkspaceSessionSnapshot(workspacePath: "/tmp", selectedTabIndex: 0, tabs: stored)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try WorkspaceSessionSnapshot.decode(from: data)
        let restored = WorkspaceSessionSnapshot.restore(from: decoded)

        XCTAssertEqual(restored.tabs.count, 2, "两页回来还是两页，不许凭空多一个首页")
        XCTAssertEqual(restored.tabs.filter { $0.isHome }.count, 1, "Home 只许有一个")
        XCTAssertEqual(restored.tabs[1].kind, WorkspaceTab.Kind.agentChat, "对话页签回来必须还是对话页签")
        XCTAssertEqual(restored.tabs[0].kind, WorkspaceTab.Kind.home)
    }

    /// 反例（历史快照）：没有 `kind` 栏、且里面已经躺着两个 `path == nil` 的页
    /// ⇒ 第一个当 Home、第二个当**对话页签**（既不许多出第二个首页，也不许把页签静默删掉）。
    func testLegacySnapshotWithTwoHomelessTabsKeepsOneHome() throws {
        let data = snapshotJSON("""
        {"title": "首页", "language": "plainText"},
        {"title": "对话", "language": "plainText"}
        """)
        let decoded = try WorkspaceSessionSnapshot.decode(from: data)
        let restored = WorkspaceSessionSnapshot.restore(from: decoded)

        XCTAssertEqual(restored.tabs.filter { $0.isHome }.count, 1, "旧快照里两个 Home ⇒ 只留一个")
        XCTAssertEqual(restored.tabs.count, 2, "第二个不许被静默删掉")
        XCTAssertEqual(restored.tabs[1].kind, WorkspaceTab.Kind.agentChat, "第二个按对话页签回来（否则就是第二个首页）")
    }

    /// 老快照只有文件页：种类仍按「有路径 ⇒ file」推，标题从路径重算（既有行为不变）。
    func testLegacyFileTabsStillRestoreAsFiles() throws {
        let data = snapshotJSON("""
        {"path": "/tmp/a.swift", "title": "a.swift", "language": "swift"}
        """)
        let decoded = try WorkspaceSessionSnapshot.decode(from: data)
        let restored = WorkspaceSessionSnapshot.restore(from: decoded, readFile: { _ in "let a = 1" })
        XCTAssertEqual(restored.tabs.count, 1)
        XCTAssertEqual(restored.tabs[0].kind, WorkspaceTab.Kind.file)
        XCTAssertFalse(restored.tabs[0].isHome)
    }
}
