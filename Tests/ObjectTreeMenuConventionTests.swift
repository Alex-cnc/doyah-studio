import Foundation
import XCTest

/// 对象树右键菜单的**目标行**判定（2026-09-28 人工点验实测缺陷）。
///
/// 现场（需求提出者原话）：「对象树的选择性能很差，点一下鼠标要等一下才能选择对象，
/// 否则马上点右键就会报：这一行没有可用的操作」。
///
/// 机制：整棵树是一个 `List` 行（为了紧行距），右键菜单只挂一份、内容由**悬停行**决定。
/// 而单击会改 `selectedTreeObject` ⇒ 整棵树重算、行视图重建 ⇒ SwiftUI 补一个**假的**
/// `mouseExited`（指针其实没动）把悬停盒子清空；指针没动，新的 `mouseEntered` 也不会来
/// —— 于是「点完立刻右键」拿到的是那张空菜单（`treeMenuEmpty`）。
///
/// 这条判据守住两种修法都还在：① 点击时把悬停盒子写成被点的那一行；
/// ② 盒子为空时兜底到「已选中那一行」（右键之前必然左键点过它）。
final class ObjectTreeMenuConventionTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testContextMenuTargetSurvivesRebuildClearingHover() throws {
        let text = try source("App/Views/ObjectTreeView.swift")

        XCTAssertTrue(
            text.contains(".contextMenu { menuItems(for: menuTargetObject) }"),
            "菜单目标必须走 `menuTargetObject`（悬停行 + 兜底）—— 只看悬停盒子的话，重建补的假 mouseExited 会让菜单变空"
        )

        guard let declaration = text.range(of: "private var menuTargetObject: DatabaseObject? {") else {
            return XCTFail("找不到 `menuTargetObject` —— 判据锚点变了，请更新这条判据而不是删掉它")
        }
        let body = String(text[declaration.lowerBound...].prefix(1_200))
        XCTAssertTrue(
            body.contains("if let hovered = hoveredMenuObject { return hovered }"),
            "悬停命中时必须优先用悬停行 —— 否则会退回「点数据库却弹服务器菜单」那个老毛病"
        )
        XCTAssertTrue(
            body.contains("appState.selectedTreeObject"),
            "悬停没命中要兜底到「已选中那一行」：右键之前必然是左键点过它"
        )

        // 点击本身就是「指针在这一行」的铁证：单击与双击都要写悬停盒子（连 onHover 共 ≥3 处写入）。
        let writes = text.components(separatedBy: "hoverBox.rowID = row.object.id").count - 1
        XCTAssertGreaterThanOrEqual(
            writes, 3,
            "单击与双击都要顺手写悬停盒子（当前只有 \(writes) 处写入）—— 否则手快的人点完立刻右键还是空菜单"
        )
    }
}
