import XCTest
@testable import DoyahCore

/// 行内动作的口径（`FR-STD-WS-UI-013`）：哪几枚 / 画不画 / 标识怎么拼。
///
/// 这一族判的是**视图与探针共用的那一份口径**：视图不再自己写 `if entry.isDirectory`
/// 与 `"workspace-action-\(…)` 的字符串，探针也不自己拼一遍 —— 两处各写一份时，
/// 「目录三枚、文件两枚」改了视图没改判据（或反过来）没有任何门禁看得见。
///
/// 几何那半边（未悬停动作数 0 / 行宽不变 / 悬停即出即收）在像素上量，
/// 见 `TestsUISnapshot/RowActionRevealProbeTests`。
final class RowActionPolicyTests: XCTestCase {

    // MARK: - ① 这一行该有哪几枚

    func testDirectoryRowHasThreeActions() {
        XCTAssertEqual(RowActionPolicy.actions(isDirectory: true), [.create, .delete, .rename])
    }

    func testFileRowHasTwoActionsWithoutCreate() {
        let actions = RowActionPolicy.actions(isDirectory: false)
        XCTAssertEqual(actions, [.delete, .rename])
        XCTAssertFalse(actions.contains(.create), "文件行不该有「新建」—— 往文件里新建东西是错的")
    }

    /// 顺序是口径的一部分：探针按位置数簇，图标的左右次序一变读数就对不上。
    func testActionOrderIsStable() {
        XCTAssertEqual(RowAction.allCases.map(\.rawValue), ["plus", "minus", "pencil"])
        XCTAssertEqual(RowAction.allCases.map(\.symbolName), RowAction.allCases.map(\.rawValue))
    }

    /// 一枚都不许重复（重复 = 同一行画两遍同一枚动作，正是需求 ③ 要挡的形态）。
    func testNoDuplicateActionsInAnyRow() {
        for isDirectory in [true, false] {
            let actions = RowActionPolicy.actions(isDirectory: isDirectory)
            XCTAssertEqual(Set(actions).count, actions.count, "isDirectory=\(isDirectory) 有重复动作")
        }
    }

    // MARK: - ② 此刻画不画

    func testActionsAreHiddenWhenNotHovered() {
        XCTAssertFalse(RowActionPolicy.isVisible(isHovered: false, isRenaming: false))
    }

    func testActionsAppearOnHover() {
        XCTAssertTrue(RowActionPolicy.isVisible(isHovered: true, isRenaming: false))
    }

    /// 例外：正在行内改名的那一行**始终**画（鼠标一移开按钮就没了，用户点不到这一行的其他入口）。
    func testRenamingRowKeepsActionsWithoutHover() {
        XCTAssertTrue(RowActionPolicy.isVisible(isHovered: false, isRenaming: true))
        XCTAssertTrue(RowActionPolicy.isVisible(isHovered: true, isRenaming: true))
    }

    // MARK: - ③ 标识怎么拼（视图与探针的唯一出处）

    func testActionIdentifiersCarryPrefixAndPath() {
        for action in RowAction.allCases {
            let identifier = RowActionPolicy.accessibilityIdentifier(action, path: "notes/a.txt")
            XCTAssertTrue(
                identifier.hasPrefix(RowActionPolicy.identifierPrefix),
                "标识没有统一前缀：\(identifier)"
            )
            XCTAssertTrue(identifier.hasSuffix("notes/a.txt"), "标识里没有那一行的路径：\(identifier)")
            XCTAssertTrue(identifier.contains(action.rawValue), "标识里没有动作名：\(identifier)")
        }
    }

    /// 同一行里三枚动作的标识必须互不相同（否则探针按标识数不出「画了几枚」）。
    func testActionIdentifiersAreUniquePerRow() {
        let identifiers = RowAction.allCases.map {
            RowActionPolicy.accessibilityIdentifier($0, path: "pkg")
        }
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    /// 分组标题那枚「＋」走同一套前缀口径（两条前缀不可互相包含，否则按前缀扫会互相串）。
    func testGroupAddIdentifierShape() {
        let identifier = RowActionPolicy.groupAddAccessibilityIdentifier("ungrouped")
        XCTAssertEqual(identifier, "connection-group-plus-ungrouped")
        XCTAssertFalse(
            identifier.hasPrefix(RowActionPolicy.identifierPrefix),
            "分组标题的标识串进了行内动作的前缀里 —— 按前缀扫会把两件事数成一件"
        )
    }
}
