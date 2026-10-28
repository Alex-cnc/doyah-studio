import XCTest
@testable import DoyahCore

/// `WorkspaceChangeScope`：外部改动后**该重列哪几个目录**（2026-10-27 主人拍板「只加载被修的节点」）。
final class WorkspaceChangeScopeTests: XCTestCase {

    private let root = "/Users/alex/dev/proj"

    func testRootChildMapsToRoot() {
        let got = WorkspaceChangeScope.directoriesToReload(
            changedPaths: ["/Users/alex/dev/proj/README.md"],
            rootPath: root, expandedPaths: [])
        // 根永远可见 ⇒ 根下任何改动都要重列根
        XCTAssertEqual(got, [""])
    }

    func testExpandedParentIsReloaded() {
        let got = WorkspaceChangeScope.directoriesToReload(
            changedPaths: ["/Users/alex/dev/proj/Sources/App/AppState.swift"],
            rootPath: root, expandedPaths: ["Sources", "Sources/App"])
        // 只重列**直接父级**，不连带把 Sources 也重列一次
        XCTAssertEqual(got, ["Sources/App"])
    }

    func testCollapsedParentIsSkipped() {
        let got = WorkspaceChangeScope.directoriesToReload(
            changedPaths: ["/Users/alex/dev/proj/Sources/App/AppState.swift"],
            rootPath: root, expandedPaths: ["Sources"])
        // Sources/App 没展开 ⇒ 看不见 ⇒ 不取（懒加载的应有之义）
        XCTAssertEqual(got, [])
    }

    func testPathsOutsideRootAreIgnored() {
        let got = WorkspaceChangeScope.directoriesToReload(
            changedPaths: ["/Users/alex/dev/other/file.swift", "/Users/alex/dev/projX/a.swift"],
            rootPath: root, expandedPaths: [])
        // 前缀必须整段匹配：`projX` 不是 `proj` 的子目录
        XCTAssertEqual(got, [])
    }

    func testIgnoredDirectoriesDoNotRefreshTree() {
        let got = WorkspaceChangeScope.directoriesToReload(
            changedPaths: ["/Users/alex/dev/proj/.git/index",
                           "/Users/alex/dev/proj/.build/debug/x.o",
                           "/Users/alex/dev/proj/node_modules/lodash/a.js"],
            rootPath: root, expandedPaths: ["", ".git", ".build"])
        // 编译 / 提交一次就往树里打一遍，是白刷
        XCTAssertEqual(got, [])
    }

    func testDuplicateParentsCollapseToOneReload() {
        let got = WorkspaceChangeScope.directoriesToReload(
            changedPaths: ["/Users/alex/dev/proj/Sources/a.swift",
                           "/Users/alex/dev/proj/Sources/b.swift",
                           "/Users/alex/dev/proj/Sources/c.swift"],
            rootPath: root, expandedPaths: ["Sources"])
        XCTAssertEqual(got, ["Sources"])
    }

    func testChangedDirectoryReloadsItsParentNotItself() {
        let got = WorkspaceChangeScope.directoriesToReload(
            changedPaths: ["/Users/alex/dev/proj/Sources"],
            rootPath: root, expandedPaths: ["Sources"])
        // 目录本身被改（新建 / 删除）⇒ 父级列表变了，重列根
        XCTAssertEqual(got, [""])
    }

    func testTrailingSlashAndRepeatedSlashesTolerated() {
        let got = WorkspaceChangeScope.directoriesToReload(
            changedPaths: ["/Users/alex/dev/proj/Sources/"],
            rootPath: "/Users/alex/dev/proj/", expandedPaths: ["Sources"])
        XCTAssertEqual(got, [""])
    }

    func testEmptyRootYieldsNothing() {
        XCTAssertEqual(WorkspaceChangeScope.directoriesToReload(
            changedPaths: ["/a/b"], rootPath: "", expandedPaths: [""]), [])
    }
}
